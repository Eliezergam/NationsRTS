-- Física del robot pequeño, calculada por código (el dueño, 17-nov: «hazlos
-- procedural», física del robot). Va justo después de la conducción, que ya
-- ha movido el robot este cuadro:
--
-- 1. Choque: la base (un círculo de `radio` m a la altura de las ruedas)
--    no atraviesa las cajas fijas del almacén (paredes, racks, mesas:
--    assets/almacen/colisiones.lua) ni a los otros robots. Si entra, el
--    choque la saca por el lado más corto y quita la velocidad que llevaba
--    contra ello; el golpe sacude el cuerpo.
-- 2. Cabeceo: el cuerpo es un péndulo sobre las ruedas (muelle con
--    amortiguador). Al acelerar o frenar se echa atrás o adelante, más
--    cuanto más pesa lo que lleva (masa de la carga / masa del robot).
-- 3. Curvas: se inclina hacia fuera con la aceleración lateral (v · giro).
--
-- 4. Postura (el dueño, 17-nov: «puede agacharse para equilibrar…, que
--    cambie a recto, procedural»): `agachado` va de -1 (recto, rodillas
--    estiradas) a 1 (agachado a tope). Quieto y sin carga se pone recto;
--    al correr baja el centro de gravedad; con carga, más cuanto más pesa;
--    y al frenar, arrancar, chocar o en una curva flexiona las rodillas
--    para amortiguar. Además el torso contrarresta el vaivén (se echa al
--    contrario del cabeceo y de la inclinación), como quien va de pie en un
--    autobús. La postura también es un muelle: nunca cambia de golpe.
--
-- Solo mueve el robot y sus piezas; no empuja cajas (eso vendría después).

---@class Fisica : Robot
local Fisica = {}
local MundoRobot = require('almacen.robots.mundo')

Fisica.radio = 0.3 -- m: la base con las ruedas
Fisica.alturas = { 0.03, 0.45 } -- m: lo que choca (la base; el cuerpo pasa por encima de las mesas)
Fisica.masa = 60 -- kg del robot pequeño
Fisica.frecuencia = 1.8 -- Hz del cuerpo sobre las ruedas
Fisica.amortiguacion = 0.22
Fisica.cabeceo = 0.015 -- rad por m/s² (vacío)
Fisica.inclinacion = 0.05 -- rad por m/s² de aceleración lateral
Fisica.golpe = 0.2 -- rad/s de sacudida por m/s de choque
Fisica.maximo = 0.14 -- rad
-- Postura (unidades de `agachado`; el juego de piernas, como el de la
-- conducción: espinilla -0,28·a, muslo +0,56·a, torso -0,08·a).
Fisica.recto = -0.23 -- quieto y sin carga
Fisica.correrDesde = 1.0 -- m/s
Fisica.porVelocidad = 0.45 -- por m/s de más
Fisica.porKilo = 0.025
Fisica.porAceleracion = 0.25 -- por m/s² (frenar, arrancar, curva)
Fisica.porGolpe = 0.8 -- por m/s de choque
Fisica.compensar = 0.7 -- lo que el torso contrarresta del vaivén
Fisica.frecuenciaPostura = 1.4 -- Hz

function Fisica:prerequisitos()
    -- El robot pequeño (una pierna) y el soldado (dos: su postura la pone
    -- piernasSoldado.lua con lo que calcula aquí).
    return self:getTienePieza('espinilla') or self:getTienePieza('espinillaIzq')
end

function Fisica:onLoad()
    local d = self.datos.fisica
    d.cab, d.vCab = 0, 0
    d.lat, d.vLat = 0, 0
    d.antes = self.velocidad or 0
    d.agachado, d.vAgachado = Fisica.recto, 0
    d.reflejo = 0
end

-- Saca el círculo (x, y, r) de la caja (x0, y0)-(x1, y1): devuelve cuánto
-- moverlo (nx, ny ya multiplicados) o nil si no la toca.
local function salir(x, y, r, x0, y0, x1, y1)
    local px = math.max(x0, math.min(x, x1))
    local py = math.max(y0, math.min(y, y1))
    local dx, dy = x - px, y - py
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then
        return nil
    end
    if d2 > 1e-10 then
        local d = math.sqrt(d2)
        return dx / d * (r - d), dy / d * (r - d)
    end
    -- El centro dentro de la caja: por el lado más cercano.
    local izq, der, abajo, arriba = x - x0, x1 - x, y - y0, y1 - y
    local m = math.min(izq, der, abajo, arriba)
    if m == izq then
        return -(izq + r), 0
    elseif m == der then
        return der + r, 0
    elseif m == abajo then
        return 0, -(abajo + r)
    end
    return 0, arriba + r
end

-- Un paso del muelle.
local function muelle(x, v, objetivo, dt)
    local w = 2 * math.pi * Fisica.frecuencia
    local a = -w * w * (x - objetivo) - 2 * Fisica.amortiguacion * w * v
    v = v + a * dt
    return x + v * dt, v
end

function Fisica:onUpdate(dt)
    if dt <= 0 then
        return
    end
    local d = self.datos.fisica
    local r = Fisica.radio
    -- 1. Choques (dos pasadas: una esquina puede empujar contra otra caja).
    local golpe = 0
    for _ = 1, 2 do
        local z0, z1 = Fisica.alturas[1], Fisica.alturas[2]
        -- Las cajas fijas de la nave y las de los objetos sólidos (los
        -- bloques enemigos de pie: almacen/blancos.lua), en el mismo formato.
        local cajas = MundoRobot.cajasEn(self.x - r, self.y - r, self.x + r, self.y + r, z0, z1)
        for _, o in ipairs(GestorObjetos.getObjetos()) do
            if o.solido then
                for _, k in ipairs(o:getCajasColisionCache()) do
                    if k[1] < self.x + r and k[4] > self.x - r and k[2] < self.y + r and k[5] > self.y - r then
                        cajas[#cajas + 1] = { o.tipo, k[1], k[2], k[3], k[4], k[5], k[6], objeto = true }
                    end
                end
            end
        end
        for _, c in ipairs(cajas) do
            local mx, my = salir(self.x, self.y, r, c[2], c[3], c[5], c[6])
            if mx and self.getMapa and not c.objeto then
                -- Lo que toca, a su mapa (si el lidar no lo veía, ya lo sabe).
                self:getMapa():setChoque(c[2], c[3], c[5], c[6], self.x, self.y, r + 0.3, c[1])
            end
            if mx then
                self.x, self.y = self.x + mx, self.y + my
                local largo = math.sqrt(mx * mx + my * my)
                local nx, ny = mx / largo, my / largo
                -- Velocidad contra la caja: se pierde.
                local contra = (math.cos(self.rumbo) * nx + math.sin(self.rumbo) * ny) * self.velocidad
                if contra < 0 then
                    golpe = math.max(golpe, -contra)
                    self.velocidad = self.velocidad * (1 - math.abs(math.cos(self.rumbo) * nx + math.sin(self.rumbo) * ny))
                end
            end
        end
        for _, otro in ipairs(GestorRobots.getRobots()) do
            if otro ~= self then
                local ro = (otro.getAncho and otro:getAncho() or 0.8) / 2
                local dx, dy = self.x - otro.x, self.y - otro.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < r + ro and dist > 1e-6 then
                    local entra = r + ro - dist
                    self.x, self.y = self.x + dx / dist * entra, self.y + dy / dist * entra
                end
            end
        end
    end
    if golpe > 0.05 then
        -- Choca con lo de delante yendo hacia delante: el cuerpo sigue y cabecea.
        d.vCab = d.vCab + golpe * Fisica.golpe * (self.velocidad >= 0 and 1 or -1)
        d.choques = (d.choques or 0) + 1
        print(string.format('FISICA choque %d a %.2f m/s en (%.2f, %.2f)', d.choques, golpe, self.x, self.y))
    end
    -- 2 y 3. El cuerpo sobre las ruedas.
    local llevando = self.getLlevando and self:getLlevando()
    local carga = llevando and llevando.getPeso and llevando:getPeso() or 0
    local factor = 1 + 2 * carga / Fisica.masa
    local acel = (self.velocidad - d.antes) / dt
    d.antes = self.velocidad
    d.acel = (d.acel or 0) + (acel - (d.acel or 0)) * math.min(1, dt * 10)
    local objetivoCab = math.max(-Fisica.maximo, math.min(Fisica.maximo, -d.acel * Fisica.cabeceo * factor))
    local lateral = self.velocidad * (self.giro or 0)
    local objetivoLat = math.max(-Fisica.maximo, math.min(Fisica.maximo, lateral * Fisica.inclinacion * factor))
    local pasos = math.max(1, math.ceil(dt / 0.005))
    local h = dt / pasos
    for _ = 1, pasos do
        d.cab, d.vCab = muelle(d.cab, d.vCab, objetivoCab, h)
        d.lat, d.vLat = muelle(d.lat, d.vLat, objetivoLat, h)
    end
    d.cab = math.max(-Fisica.maximo, math.min(Fisica.maximo, d.cab))
    d.lat = math.max(-Fisica.maximo, math.min(Fisica.maximo, d.lat))
    -- 4. Postura. El reflejo (rodillas que amortiguan) sube con lo brusco y
    -- se apaga en un segundo.
    local brusco = math.abs(d.acel) + math.abs(lateral)
    d.reflejo = math.max(d.reflejo * math.exp(-dt * 1.2), brusco * Fisica.porAceleracion + golpe * Fisica.porGolpe)
    local v = math.abs(self.velocidad)
    local objetivo = Fisica.recto
        + math.max(0, v - Fisica.correrDesde) * Fisica.porVelocidad
        + carga * Fisica.porKilo
        + d.reflejo
    objetivo = math.max(-1, math.min(1, objetivo))
    local w = 2 * math.pi * Fisica.frecuenciaPostura
    for _ = 1, pasos do
        local a = -w * w * (d.agachado - objetivo) - 2 * 0.7 * w * d.vAgachado
        d.vAgachado = d.vAgachado + a * h
        d.agachado = d.agachado + d.vAgachado * h
    end
end

--- Postura de ahora: -1 recto .. 1 agachado (física).
function GestorRobots.Robot:getPostura()
    return self.datos.fisica and self.datos.fisica.agachado or 0
end

function Fisica:onPose()
    local d = self.datos.fisica
    -- El soldado: sus piernas las pone piernasSoldado.lua.
    if not self:getTienePieza('espinilla') then
        return
    end
    -- Cabeceo con el mismo signo que el de la conducción (al acelerar,
    -- atrás); hacia fuera de la curva (giro a la izquierda: se inclina a la
    -- derecha), giro en x.
    self:getPieza('espinilla'):setGiro('y', d.cab, 'cabeceo')
    self:getPieza('espinilla'):setGiro('x', d.lat, 'curva')
    -- Postura y equilibrio activo.
    local a = d.agachado
    self:getPieza('espinilla'):setGiro('y', -0.28 * a, 'postura')
    self:getPieza('muslo'):setGiro('y', 0.56 * a, 'postura')
    self:getPieza('torso'):setGiro('y', -0.08 * a - Fisica.compensar * d.cab, 'postura')
    self:getPieza('torso'):setGiro('x', -Fisica.compensar * d.lat, 'equilibrio')
end

GestorRobots.registrarEspecializacion('fisica', Fisica)
return Fisica

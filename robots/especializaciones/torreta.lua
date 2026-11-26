-- Torreta enemiga (el dueño, 18-nov: «crea una torreta y que esa torreta le
-- dispare»). Modelo: tools/blender/torreta.py (base, cabezal que gira a los
-- lados, cañón que sube y baja).
--
-- Busca robots con combate (soldados) a menos de `alcance` m; si ve uno (sin
-- nada en medio, desde su sensor), gira el cabezal y sube o baja el cañón
-- hacia su pecho a la velocidad de sus motores y, apuntado, dispara ráfagas.
-- Cada bala es un rayo: contra el mundo de la escena y contra las zonas del
-- robot (robots/especializaciones/impactos.lua); si le da, el robot recibe el
-- impacto (Robot:setImpacto) y reacciona. Falla más cuanto más lejos.
-- Sin nadie a la vista, barre despacio de lado a lado.
--
-- Recibe balas por el objeto de su cuerpo (lo pone la escena:
-- almacen/blancos.lua) con robot:setDanoTorreta(); sin vida, el cañón cae,
-- deja de disparar y al rato se rearma.

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local Torreta = {}

Torreta.alcance = 25
Torreta.giroCabezal = math.rad(70) -- rad/s
Torreta.giroCanon = math.rad(45)
Torreta.canonMin, Torreta.canonMax = math.rad(-20), math.rad(35)
Torreta.cadencia = 8 -- balas/s
Torreta.rafaga = { 0.4, 0.7 }
Torreta.pausa = { 0.5, 0.9 }
Torreta.apuntado = math.rad(2.5)
Torreta.dispersion = math.rad(1.4)
Torreta.dispersionPorMetro = math.rad(0.1)
Torreta.fuerza = 1 -- de cada bala (robots/especializaciones/impactos.lua)
Torreta.boca = 0.97 -- m del pivote del cañón a la boca
Torreta.sensor = { -0.055, 0, 0.3 } -- en el cabezal
Torreta.vida = 80
Torreta.rearme = 40 -- s sin vida
Torreta.barrido = math.rad(25) -- rad/s sin nadie
Torreta.trazadora = 0.07

function Torreta:onLoad()
    local d = self.datos.torreta
    d.lado, d.arriba = 0, 0
    d.disparos, d.chispas = {}, {}
    d.reloj = 0
    d.pausa, d.rafaga = 0.5, 0
    d.vida = Torreta.vida
    d.barrer = 1
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Donde apunta: el pecho (la pieza torso, `alto` m por encima de la
-- cintura; 0,25 el centro del pecho, 0,6 la cabeza).
local function pechoDe(r, alto)
    local p = r.piezas.torso
    if p and p:getMatriz() then
        return p:getPunto(0, 0, alto or 0.25)
    end
    return r.x, r.y, 1.2
end
Torreta.cabeza = 0.2 -- de las ráfagas, las que apunta a la cabeza

local function boca(self)
    local c = self:getPieza('canon')
    local m = c:getMatriz()
    if not m then
        return nil
    end
    local x, y, z = c:getPunto(Torreta.boca, 0, 0.01)
    return x, y, z, m[1], m[5], m[9]
end

-- ¿Lo ve? Rayo desde el sensor hasta su pecho sin nada en medio.
local function loVe(self, r)
    local sx, sy, sz = self:getPieza('cabezal'):getPunto(Torreta.sensor[1], Torreta.sensor[2], Torreta.sensor[3])
    local tx, ty, tz = pechoDe(r)
    local dx, dy, dz = tx - sx, ty - sy, tz - sz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > Torreta.alcance then
        return false
    end
    local choque = self:getRayoMundo(sx, sy, sz, dx, dy, dz, dist, self.cuerpo)
    return not choque or choque >= dist - 0.4, dist
end

local function disparar(self, d, distancia)
    local bx, by, bz, gx, gy, gz = boca(self)
    if not bx then
        return
    end
    local sigma = Torreta.dispersion + Torreta.dispersionPorMetro * distancia
    local r = math.abs(love.math.randomNormal(sigma, 0))
    local a = love.math.random() * 2 * math.pi
    local ux, uy = -gy, gx
    local n = math.max(1e-6, math.sqrt(ux * ux + uy * uy))
    ux, uy = ux / n, uy / n
    local vx, vy, vz = -gz * uy, gz * ux, gx * uy - gy * ux
    local dx = gx + (ux * math.cos(a) + vx * math.sin(a)) * r
    local dy = gy + (uy * math.cos(a) + vy * math.sin(a)) * r
    local dz = gz + (vz * math.sin(a)) * r
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / largo, dy / largo, dz / largo
    -- Lo primero que toca: el mundo o un robot.
    local dist, tipo, objeto = self:getRayoMundo(bx, by, bz, dx, dy, dz, Torreta.alcance + 5, self.cuerpo)
    dist = dist or Torreta.alcance + 5
    local robot, zona
    for _, otro in ipairs(self.gestor:getRobots()) do
        if otro ~= self and otro.getImpactoRayo then
            local t, z = otro:getImpactoRayo(bx, by, bz, dx, dy, dz, dist)
            if t and t < dist then
                dist, robot, zona = t, otro, z
            end
        end
    end
    local hx, hy, hz = bx + dx * dist, by + dy * dist, bz + dz * dist
    d.disparos[#d.disparos + 1] = { bx, by, bz, hx, hy, hz, t = 0 }
    if robot then
        robot:setImpacto(hx, hy, hz, dx, dy, dz, Torreta.fuerza, zona)
        d.chispas[#d.chispas + 1] = { hx, hy, hz, t = 0, enemigo = true }
        d.aciertos = (d.aciertos or 0) + 1
    elseif tipo then
        d.chispas[#d.chispas + 1] = { hx, hy, hz, t = 0 }
        if objeto and objeto.setDano then
            objeto:setDano(1, hx, hy, hz, dx, dy, dz)
        end
    end
    d.balas = (d.balas or 0) + 1
    d.fogonazo = 0.05
    d.fogonazoPunto = { bx, by, bz }
    d.retroceso = 1
end

function Torreta:onUpdate(dt)
    local d = self.datos.torreta
    d.reloj = d.reloj + dt
    for _, lista in ipairs({ d.disparos, d.chispas }) do
        for k = #lista, 1, -1 do
            lista[k].t = lista[k].t + dt
            if lista[k].t > (lista == d.chispas and 0.25 or Torreta.trazadora) then
                table.remove(lista, k)
            end
        end
    end
    d.fogonazo = math.max(0, (d.fogonazo or 0) - dt)
    d.retroceso = math.max(0, (d.retroceso or 0) - dt * 12)
    -- Sin vida: el cañón cae y espera a rearmarse.
    if d.vida <= 0 then
        d.muerta = (d.muerta or 0) + dt
        d.arriba = math.max(Torreta.canonMin, d.arriba - dt * 1.5)
        d.objetivo = nil
        if d.muerta > Torreta.rearme then
            d.vida, d.muerta = Torreta.vida, nil
            print('TORRETA rearmada')
        end
        return
    end
    -- El robot con combate más cercano que ve.
    local objetivo, distancia
    for _, r in ipairs(self.gestor:getRobots()) do
        if r ~= self and r.datos.combate then
            local ve, dist = loVe(self, r)
            if ve and (not distancia or dist < distancia) then
                objetivo, distancia = r, dist
            end
        end
    end
    if objetivo and objetivo ~= d.objetivo then
        print(string.format('TORRETA veo a %s a %.1f m', objetivo:getNombreTipo(), distancia))
    end
    d.objetivo = objetivo
    local quiereLado, quiereArriba
    if objetivo then
        local tx, ty, tz = pechoDe(objetivo, d.alto)
        local cx, cy, cz = self:getPieza('canon'):getPosicion()
        quiereLado = angulo(math.atan2(ty - cy, tx - cx) - self.rumbo)
        quiereArriba = math.atan2(tz - cz, math.sqrt((tx - cx) ^ 2 + (ty - cy) ^ 2))
    else
        -- Barre de lado a lado.
        if math.abs(d.lado) > math.rad(80) then
            d.barrer = d.lado > 0 and -1 or 1
        end
        quiereLado = d.lado + d.barrer * Torreta.barrido * dt
        quiereArriba = 0
    end
    local function hacia(actual, quiere, rapidez)
        local e = angulo(quiere - actual)
        return actual + math.max(-rapidez * dt, math.min(rapidez * dt, e)), math.abs(e)
    end
    local eLado, eArriba
    d.lado, eLado = hacia(d.lado, quiereLado, Torreta.giroCabezal)
    d.arriba, eArriba = hacia(d.arriba, quiereArriba, Torreta.giroCanon)
    d.arriba = math.max(Torreta.canonMin, math.min(Torreta.canonMax, d.arriba))
    -- Ráfagas, apuntado.
    if objetivo and eLado < Torreta.apuntado and eArriba < Torreta.apuntado then
        if d.pausa > 0 then
            d.pausa = d.pausa - dt
            if d.pausa <= 0 then
                d.rafaga = Torreta.rafaga[1] + love.math.random() * (Torreta.rafaga[2] - Torreta.rafaga[1])
                -- La siguiente, al pecho o a la cabeza.
                d.alto = love.math.random() < Torreta.cabeza and 0.62 or 0.25
            end
        else
            d.cuenta = (d.cuenta or 0) + dt * Torreta.cadencia
            while d.cuenta >= 1 do
                d.cuenta = d.cuenta - 1
                disparar(self, d, distancia)
            end
            d.rafaga = d.rafaga - dt
            if d.rafaga <= 0 then
                d.pausa = Torreta.pausa[1] + love.math.random() * (Torreta.pausa[2] - Torreta.pausa[1])
            end
        end
    else
        d.cuenta = 0
    end
end

function Torreta:onPose()
    local d = self.datos.torreta
    self:getPieza('cabezal'):setGiro('z', d.lado, 'apuntar')
    -- Girar en y negativo sube el cañón; el retroceso lo echa atrás un poco.
    self:getPieza('canon'):setGiro('y', -d.arriba, 'apuntar')
    self:getPieza('canon'):setDesplazamiento(-0.03 * (d.retroceso or 0), 0, 0, 'retroceso')
end

--- Una bala en su cuerpo.
function Robot:setDanoTorreta(cantidad)
    local d = self.datos.torreta
    if d and d.vida > 0 then
        d.vida = d.vida - cantidad
        if d.vida <= 0 then
            print('TORRETA destruida')
        end
    end
end

function Robot:getVidaTorreta()
    local d = self.datos.torreta
    return d and d.vida or 0, Torreta.vida
end

Nucleo.registrarEspecializacion('torreta', Torreta)
return Torreta

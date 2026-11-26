-- Impactos que recibe un robot (el dueño, 18-nov: «que lo empuje un poco
-- hacia atrás; si le da en un lado del pecho, medio lo gira de ese lado, no
-- todo el cuerpo; si le da en la cabeza, que le tuerza un poco la cabeza
-- para atrás; todo procedural»).
--
-- Cada bala es un empujón (impulso) en el punto donde da. Con el punto y la
-- dirección se calcula el par de giro, como en física (par = r × F): un
-- golpe a un lado del pecho tuerce el torso hacia ese lado; uno alto lo echa
-- hacia atrás; uno en la cabeza la tuerce hacia atrás y hacia el lado. Cada
-- giro es un muelle con amortiguador (vuelve solo, pasándose un poco) y se
-- suman si caen varias balas seguidas. Además todo el robot retrocede un
-- poco (sus ruedas no lo frenan del todo) y el cuerpo cabecea (fisica.lua).
--
-- Dónde le pueden dar: cajas en los ejes de sus piezas (ajuste `zonas`):
--   { zona, pieza, cx, cy, cz, mx, my, mz } (centro y mitades, en metros)
-- y las zonas que tuercen algo: 'pecho' (pieza torso) y 'cabeza' (cabeza).
--
-- Órdenes que añade al robot:
--   robot:getImpactoRayo(x, y, z, dx, dy, dz, alcance)  distancia, zona, punto
--   robot:setImpacto(x, y, z, dx, dy, dz, fuerza, zona) le da una bala

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local Impactos = {}

-- El soldado (tools/blender/robot_soldado.py): pecho y abdomen en el torso
-- (pivote en la cintura), casco y mandíbula en la cabeza (pivote en el
-- cuello), cadera y piernas en la pelvis.
Impactos.zonas = {
    { 'pecho', 'torso', 0.0, 0.0, 0.24, 0.16, 0.24, 0.23 },
    { 'cabeza', 'cabeza', 0.01, 0.0, 0.18, 0.13, 0.11, 0.14 },
    { 'piernas', 'pelvis', 0.0, 0.0, -0.45, 0.14, 0.22, 0.5 },
}
Impactos.empuje = 0.05 -- m/s que retrocede por bala
Impactos.frenoEmpuje = 5 -- 1/s: lo que tarda en pararse
Impactos.parTorso = 20 -- rad/s por (m · fuerza) en el torso (echarse atrás)
Impactos.parGiroTorso = 45 -- y al torcerse (un golpe a un lado)
Impactos.parCabeza = 28
Impactos.cabeceo = 0.15 -- rad/s de cabeceo del cuerpo (fisica.lua) por bala
-- Muelles: frecuencia (Hz) y amortiguación; y lo más que gira cada cosa.
Impactos.muelleTorso = { 2.6, 0.35 }
Impactos.muelleCabeza = { 3.5, 0.3 }
Impactos.maximoTorso = { giro = 0.45, atras = 0.25 }
Impactos.maximoCabeza = { giro = 0.5, atras = 0.45 }

function Impactos:prerequisitos()
    return self:getTienePieza('torso')
end

function Impactos:onLoad()
    local d = self.datos.impactos
    -- Ángulo y velocidad de cada giro.
    d.torsoGiro, d.vTorsoGiro, d.torsoAtras, d.vTorsoAtras = 0, 0, 0, 0
    d.cabezaGiro, d.vCabezaGiro, d.cabezaAtras, d.vCabezaAtras = 0, 0, 0, 0
    d.ex, d.ey = 0, 0 -- velocidad del empujón
    d.recibidos = 0
end

-- Rayo contra una caja en los ejes de la matriz `m` (por filas): distancia o nil.
local function rayoCaja(m, x, y, z, dx, dy, dz, c)
    -- Al espacio de la pieza (la rotación es ortonormal: la inversa es la
    -- traspuesta).
    local qx, qy, qz = x - m[4], y - m[8], z - m[12]
    local lx = m[1] * qx + m[5] * qy + m[9] * qz - c[3]
    local ly = m[2] * qx + m[6] * qy + m[10] * qz - c[4]
    local lz = m[3] * qx + m[7] * qy + m[11] * qz - c[5]
    local ldx = m[1] * dx + m[5] * dy + m[9] * dz
    local ldy = m[2] * dx + m[6] * dy + m[10] * dz
    local ldz = m[3] * dx + m[7] * dy + m[11] * dz
    local t0, t1 = -math.huge, math.huge
    for _, e in ipairs({ { lx, ldx, c[6] }, { ly, ldy, c[7] }, { lz, ldz, c[8] } }) do
        local p, v, h = e[1], e[2], e[3]
        if math.abs(v) < 1e-9 then
            if p < -h or p > h then
                return nil
            end
        else
            local a, b = (-h - p) / v, (h - p) / v
            if a > b then
                a, b = b, a
            end
            t0, t1 = math.max(t0, a), math.min(t1, b)
            if t0 > t1 then
                return nil
            end
        end
    end
    if t1 < 0 then
        return nil
    end
    return math.max(0, t0)
end

--- Lo primero del robot que toca un rayo: distancia, zona y punto (nil si nada).
function Robot:getImpactoRayo(x, y, z, dx, dy, dz, alcance)
    if not self.datos.impactos then
        return nil
    end
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / n, dy / n, dz / n
    local mejor, zona
    for _, c in ipairs(self:getAjustes('impactos').zonas) do
        local p = self.piezas[c[2]]
        local m = p and p:getMatriz()
        if m then
            local t = rayoCaja(m, x, y, z, dx, dy, dz, c)
            if t and t <= (alcance or math.huge) and (not mejor or t < mejor) then
                mejor, zona = t, c[1]
            end
        end
    end
    if mejor then
        return mejor, zona, x + dx * mejor, y + dy * mejor, z + dz * mejor
    end
end

-- Par de giro (en los ejes de la pieza) de una fuerza `f` en el punto `p`.
local function par(pieza, px, py, pz, fx, fy, fz)
    local m = pieza:getMatriz()
    local qx, qy, qz = px - m[4], py - m[8], pz - m[12]
    local rx = m[1] * qx + m[5] * qy + m[9] * qz
    local ry = m[2] * qx + m[6] * qy + m[10] * qz
    local rz = m[3] * qx + m[7] * qy + m[11] * qz
    local lx = m[1] * fx + m[5] * fy + m[9] * fz
    local ly = m[2] * fx + m[6] * fy + m[10] * fz
    local lz = m[3] * fx + m[7] * fy + m[11] * fz
    -- r × F: en y (inclinarse: positivo = hacia delante) y en z (girar).
    return rz * lx - rx * lz, rx * ly - ry * lx
end

--- Le da una bala en (x, y, z) que iba hacia (dx, dy, dz).
function Robot:setImpacto(x, y, z, dx, dy, dz, fuerza, zona)
    local d = self.datos.impactos
    if not d then
        return
    end
    local A = self:getAjustes('impactos')
    fuerza = fuerza or 1
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / n * fuerza, dy / n * fuerza, dz / n * fuerza
    d.recibidos = d.recibidos + 1
    -- Todo el robot, un poco hacia atrás.
    d.ex, d.ey = d.ex + dx * A.empuje, d.ey + dy * A.empuje
    local f = self.datos.fisica
    if f and f.vCab then
        -- El cuerpo cabecea hacia donde va la bala (en los ejes del robot).
        local haciaDelante = dx * math.cos(self.rumbo) + dy * math.sin(self.rumbo)
        f.vCab = f.vCab + haciaDelante * A.cabeceo
    end
    if zona == 'pecho' then
        local atras, giro = par(self:getPieza('torso'), x, y, z, dx, dy, dz)
        d.vTorsoAtras = d.vTorsoAtras + atras * A.parTorso
        d.vTorsoGiro = d.vTorsoGiro + giro * A.parGiroTorso
    elseif zona == 'cabeza' then
        local atras, giro = par(self:getPieza('cabeza'), x, y, z, dx, dy, dz)
        d.vCabezaAtras = d.vCabezaAtras + atras * A.parCabeza
        d.vCabezaGiro = d.vCabezaGiro + giro * A.parCabeza
        -- El cuello también lo nota un poco.
        local atrasT, giroT = par(self:getPieza('torso'), x, y, z, dx, dy, dz)
        d.vTorsoAtras = d.vTorsoAtras + atrasT * A.parTorso * 0.25
        d.vTorsoGiro = d.vTorsoGiro + giroT * A.parGiroTorso * 0.25
    end
    if os.getenv('IMPACTOS_DEPURAR') then
        print(string.format('IMPACTO %d %s torso giro=%.1f° atras=%.1f° cabeza giro=%.1f° atras=%.1f° empuje=%.2f m/s', d.recibidos, zona or '-', math.deg(d.torsoGiro), math.deg(d.torsoAtras), math.deg(d.cabezaGiro), math.deg(d.cabezaAtras), math.sqrt(d.ex ^ 2 + d.ey ^ 2)))
    end
    -- ¿De dónde viene? Que lo mire (combate.lua).
    if self.setAtacadoDesde then
        self:setAtacadoDesde(x - dx / fuerza * 6, y - dy / fuerza * 6, z - dz / fuerza * 6)
    end
end

local function muelle(x, v, frecuencia, amortiguacion, maximo, dt)
    local w = 2 * math.pi * frecuencia
    local a = -w * w * x - 2 * amortiguacion * w * v
    v = v + a * dt
    x = x + v * dt
    if x > maximo then
        x, v = maximo, math.min(v, 0)
    elseif x < -maximo then
        x, v = -maximo, math.max(v, 0)
    end
    return x, v
end

function Impactos:onUpdate(dt)
    if dt <= 0 then
        return
    end
    local d = self.datos.impactos
    local A = self:getAjustes('impactos')
    local pasos = math.max(1, math.ceil(dt / 0.005))
    local h = dt / pasos
    local mt, mc = A.muelleTorso, A.muelleCabeza
    for _ = 1, pasos do
        d.torsoGiro, d.vTorsoGiro = muelle(d.torsoGiro, d.vTorsoGiro, mt[1], mt[2], A.maximoTorso.giro, h)
        d.torsoAtras, d.vTorsoAtras = muelle(d.torsoAtras, d.vTorsoAtras, mt[1], mt[2], A.maximoTorso.atras, h)
        d.cabezaGiro, d.vCabezaGiro = muelle(d.cabezaGiro, d.vCabezaGiro, mc[1], mc[2], A.maximoCabeza.giro, h)
        d.cabezaAtras, d.vCabezaAtras = muelle(d.cabezaAtras, d.vCabezaAtras, mc[1], mc[2], A.maximoCabeza.atras, h)
    end
    -- El empujón mueve el robot y se frena.
    self.x, self.y = self.x + d.ex * dt, self.y + d.ey * dt
    local k = math.exp(-A.frenoEmpuje * dt)
    d.ex, d.ey = d.ex * k, d.ey * k
end

function Impactos:onPose()
    local d = self.datos.impactos
    -- Cada giro en su capa (una capa guarda un solo giro).
    local torso = self:getPieza('torso')
    torso:setGiro('y', d.torsoAtras, 'impactoAtras')
    torso:setGiro('z', d.torsoGiro, 'impactoGiro')
    local cabeza = self:getPieza('cabeza')
    cabeza:setGiro('y', d.cabezaAtras, 'impactoAtras')
    cabeza:setGiro('z', d.cabezaGiro, 'impactoGiro')
end

--- Balas que ha recibido.
function Robot:getRecibidos()
    local d = self.datos.impactos
    return d and d.recibidos or 0
end

Nucleo.registrarEspecializacion('impactos', Impactos)
return Impactos

-- Orugas del robot grande: cada oruga es un camino cerrado (recta de abajo,
-- vuelta delantera, recta de arriba, vuelta trasera) alrededor de la rueda
-- motriz y la tensora, y sus tejas van por él como en los vehículos de
-- cadenas de los juegos (tejas sueltas repartidas cada cuadro por un camino
-- cerrado, a la misma distancia unas de otras). Cada oruga avanza lo que
-- rueda su lado: al girar en el sitio, una va hacia delante y la otra hacia
-- atrás (como un tanque). Las ruedas y los rodillos giran con ella.
--
-- La conducción (velocidad y giro del robot) es la de conduccion.lua; esto
-- solo mueve las piezas. Camino y medidas: assets/almacen/robot_pesado_oruga.lua
-- (tools/blender/robot_pesado.py --glb).

---@class Orugas : Robot
local Orugas = {}
local Robot = GestorRobots.Robot

Orugas.datos = 'assets/almacen/robot_pesado_oruga.lua'
Orugas.rodillos = 5

local camino

-- Punto (x, z) y ángulo de la tangente a `s` m por el camino (como
-- caminoOruga de robot_pesado.py).
local function puntoCamino(s)
    local xp, r = camino.xPunta, camino.radio
    local recta, curva = 2 * xp, math.pi * r
    s = s % (2 * recta + 2 * curva)
    if s < recta then
        return -xp + s, 0, 0
    end
    s = s - recta
    if s < curva then
        local a = -math.pi / 2 + s / r
        return xp + r * math.cos(a), r + r * math.sin(a), a + math.pi / 2
    end
    s = s - curva
    if s < recta then
        return xp - s, 2 * r, math.pi
    end
    s = s - recta
    local a = math.pi / 2 + s / r
    return -xp + r * math.cos(a), r + r * math.sin(a), a + math.pi / 2
end

function Orugas:onLoad()
    camino = camino or love.filesystem.load(Orugas.datos)()
    local d = self.datos.orugas
    -- Lo que ha rodado cada oruga (m).
    d.Izq, d.Der = 0, 0
end

function Orugas:onUpdate(dt)
    local d = self.datos.orugas
    local mitad = camino.y.Izq
    d.Izq = d.Izq + (self.velocidad - self.giro * mitad) * dt
    d.Der = d.Der + (self.velocidad + self.giro * mitad) * dt
end

function Orugas:onPose()
    local d = self.datos.orugas
    for _, s in ipairs({ 'Izq', 'Der' }) do
        local y = camino.y[s]
        -- Las tejas que pisan el suelo se quedan quietas respecto a él: van
        -- hacia atrás en el robot lo que este avanza.
        local corre = -d[s]
        for k = 0, camino.n - 1 do
            local x, z, a = puntoCamino(k * camino.paso + corre)
            local c, sn = math.cos(-a), math.sin(-a)
            self:getPieza(string.format('teja%s%02d', s, k)):setMatrizLocal({ c, 0, sn, x, 0, 1, 0, y, -sn, 0, c, z + camino.alto, 0, 0, 0, 1 })
        end
        local giro = d[s] / camino.radioRueda
        self:getPieza('ruedaMotriz' .. s):setGiro('y', giro)
        self:getPieza('ruedaTensora' .. s):setGiro('y', giro)
        for k = 1, Orugas.rodillos do
            self:getPieza('rodillo' .. s .. k):setGiro('y', d[s] / camino.radioRodillo)
        end
    end
end

--- Lo que ha rodado cada oruga (m): izquierda, derecha.
function Robot:getRodadoOrugas()
    local d = self.datos.orugas
    return d.Izq, d.Der
end

GestorRobots.registrarEspecializacion('orugas', Orugas)
return Orugas

-- Ruedas del camión de misiles (el dueño, 18-nov): conduce como un coche
-- (bicicleta: las delanteras giran, el giro sale de la batalla entre ejes),
-- hace rodar las ocho ruedas, sube y baja cada suspensión con el terreno y
-- mueve el puesto del conductor (los engranajes giran con las ruedas:
-- assets/batalla/robots/camionMisiles_puesto.lua).
--
-- Quien conduce (el robot conductor, pilotar.lua) solo pide:
--   camion:setConducir(velocidad m/s (negativa: marcha atrás), direccion rad)
-- Lo de ahora, en camion.datos.ruedasCamion: velocidad, direccion,
-- giroRueda (rad acumulados de las ruedas: lo leen el puesto y los pies del
-- robot).

local Nucleo = require('robots.nucleo')
local Mundo = require('batalla.robots.mundo')
local Robot = Nucleo.Robot

local RuedasCamion = {}

RuedasCamion.radio = 0.7 -- m
RuedasCamion.entreEjes = 5.97 -- m del eje delantero al centro de los dos traseros
RuedasCamion.direccionMaxima = 0.45 -- rad
RuedasCamion.velocidadDireccion = 1.6 -- rad/s
RuedasCamion.aceleracion = 2.2 -- m/s²
RuedasCamion.frenada = 5
RuedasCamion.velocidadMaxima = 14
RuedasCamion.recorrido = 0.16 -- m que sube o baja cada suspensión
RuedasCamion.relacionPuesto = 0.21 -- vueltas de la rueda por vuelta del pie del robot
RuedasCamion.puesto = 'assets/batalla/robots/camionMisiles_puesto.lua'

function RuedasCamion.prerequisitos(self)
    return self:getTienePieza('ruedaDelanteraDerecha')
end

local function acercar(a, b, paso)
    if a < b then
        return math.min(b, a + paso)
    end
    return math.max(b, a - paso)
end

function RuedasCamion.onLoad(self)
    local d = self.datos.ruedasCamion
    d.velocidad, d.quiere = 0, 0
    d.direccion, d.quiereDireccion = 0, 0
    d.giroRueda = 0
    d.ruedas, d.suspensiones, d.delanteras = {}, {}, {}
    for _, nombre in ipairs(self:getNombresPiezas()) do
        local p = self:getPieza(nombre)
        if nombre:match('^rueda') then
            d.ruedas[#d.ruedas + 1] = p
            if nombre:match('^ruedaDelantera') then
                d.delanteras[#d.delanteras + 1] = p
                -- La dirección antes que el rodar (su capa va primero).
                p:setGiro('z', 0, 'direccion')
            end
        elseif nombre:match('^suspension') then
            local m = p.datos.matriz
            d.suspensiones[#d.suspensiones + 1] = { pieza = p, x = m[4], y = m[8], z = m[12] }
        end
    end
    d.puesto = {}
    for _, g in ipairs(love.filesystem.load(RuedasCamion.puesto)()) do
        if self:getTienePieza(g.pieza) then
            d.puesto[#d.puesto + 1] = { pieza = self:getPieza(g.pieza), eje = g.eje, giro = g.giro }
        end
    end
    d.ventiladores = {}
    for _, nombre in ipairs({ 'ventiladorRadiadorDerecho', 'ventiladorRadiadorIzquierdo' }) do
        if self:getTienePieza(nombre) then
            d.ventiladores[#d.ventiladores + 1] = self:getPieza(nombre)
        end
    end
    d.ventilador = 0
end

--- Lo que pide el conductor (m/s y rad).
function Robot:setConducir(velocidad, direccion)
    local d = self.datos.ruedasCamion
    d.quiere = math.max(-RuedasCamion.velocidadMaxima * 0.4, math.min(RuedasCamion.velocidadMaxima, velocidad or 0))
    d.quiereDireccion = math.max(-RuedasCamion.direccionMaxima, math.min(RuedasCamion.direccionMaxima, direccion or 0))
end

function RuedasCamion.onUpdate(self, dt)
    local d = self.datos.ruedasCamion
    local paso = (math.abs(d.quiere) < math.abs(d.velocidad) or d.quiere * d.velocidad < 0) and RuedasCamion.frenada or RuedasCamion.aceleracion
    d.velocidad = acercar(d.velocidad, d.quiere, paso * dt)
    d.direccion = acercar(d.direccion, d.quiereDireccion, RuedasCamion.velocidadDireccion * dt)
    self.rumbo = self.rumbo + d.velocidad * math.tan(d.direccion) / RuedasCamion.entreEjes * dt
    self.x = self.x + math.cos(self.rumbo) * d.velocidad * dt
    self.y = self.y + math.sin(self.rumbo) * d.velocidad * dt
    d.giroRueda = d.giroRueda + d.velocidad * dt / RuedasCamion.radio
    d.ventilador = d.ventilador + (6 + math.abs(d.velocidad)) * dt
end

function RuedasCamion.onPose(self)
    local d = self.datos.ruedasCamion
    for _, p in ipairs(d.delanteras) do
        p:setGiro('z', d.direccion, 'direccion')
    end
    for _, p in ipairs(d.ruedas) do
        p:setGiro('y', d.giroRueda, 'rodar')
    end
    -- Cada suspensión a la altura del suelo bajo su rueda (respecto a donde
    -- la pone el chasis inclinado), dentro de su recorrido.
    local chasis = self:getPieza('chasis'):getMatriz()
    if chasis then
        for _, s in ipairs(d.suspensiones) do
            -- Dónde pisaría la rueda con la suspensión en reposo (el suelo
            -- del chasis bajo ella) y dónde está el terreno de verdad.
            local wx = chasis[1] * s.x + chasis[2] * s.y + chasis[4]
            local wy = chasis[5] * s.x + chasis[6] * s.y + chasis[8]
            local wz = chasis[9] * s.x + chasis[10] * s.y + chasis[12]
            local r = RuedasCamion.recorrido
            s.pieza:setDesplazamiento(0, 0, math.max(-r, math.min(r, Mundo.altura(wx, wy) - wz)))
        end
    end
    local pie = d.giroRueda / RuedasCamion.relacionPuesto
    for _, g in ipairs(d.puesto) do
        g.pieza:setGiro(g.eje, pie * g.giro, 'puesto')
    end
    for _, p in ipairs(d.ventiladores) do
        p:setGiro('x', d.ventilador, 'ventilador')
    end
end

Nucleo.registrarEspecializacion('ruedasCamion', RuedasCamion)
return RuedasCamion

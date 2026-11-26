-- Reposo: cuando el robot está quieto no se queda de piedra. El cuerpo se
-- mece muy poco (los motores corrigen el equilibrio) y las pinzas tiemblan
-- un pelo. Solo cosmético: no cambia nada que lean otros scripts.

---@class Reposo : Robot
local Reposo = {}

Reposo.vaiven = 0.012 -- rad
Reposo.ritmo = 0.35 -- vueltas por segundo

function Reposo:onLoad()
    self.datos.reposo.t = love.math.random() * 10
    self.datos.reposo.peso = 1
end

function Reposo:onUpdate(dt)
    local d = self.datos.reposo
    d.t = d.t + dt
    -- Andando, el vaivén se apaga.
    -- Trabajando con las manos tampoco (movería lo que sujeta).
    local m = self.datos.manipulacion
    local manos = m and (m.objeto or m.izq.objetivo or m.der.objetivo)
    local quieto = math.abs(self.velocidad) < 0.05 and math.abs(self.giro) < 0.05 and not manos
    d.peso = d.peso + ((quieto and 1 or 0) - d.peso) * math.min(1, dt * 2)
end

function Reposo:onPose()
    local d = self.datos.reposo
    local a = math.sin(d.t * Reposo.ritmo * 2 * math.pi) * Reposo.vaiven * d.peso
    self:getPieza('torso'):setGiro('y', a)
    self:getPieza('cabeza'):setGiro('z', a * 0.8)
end

GestorRobots.registrarEspecializacion('reposo', Reposo)
return Reposo

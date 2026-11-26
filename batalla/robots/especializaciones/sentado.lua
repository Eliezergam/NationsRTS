-- Sentado en el puesto del camión de misiles (el dueño, 18-nov): el robot
-- conductor (tipo `conductor`) va donde dice la pieza `asientoConductor` del
-- camión que conduce (`robot.vehiculo`, lo pone la escena), con las ruedas de
-- los pies hechas engranajes (engranajePie{Der,Izq}). Su pose de reposo ya es
-- la de sentado con las garras en las palancas (tools/blender/robot_conductor.py).
--
-- Los engranajes de los pies giran con las ruedas del camión: el camión
-- apunta en `datos.camion.giroRueda` (radianes de sus ruedas, ruedasCamion.lua);
-- si no, quietos. Por cada radián de la rueda del camión el pie gira
-- 1 / Sentado.relacion (la del puesto: la rueda del camión gira 0,21 lo que
-- el pie).

local Nucleo = require('robots.nucleo')
local PiezaRobot = require('robots.pieza')

local Sentado = {}

Sentado.relacion = 0.21

function Sentado.prerequisitos(self)
    return self:getTienePieza('engranajePieDer') and self:getTienePieza('engranajePieIzq')
end

function Sentado.onLoad(self)
    for _, nombre in ipairs({ 'ruedaDer', 'ruedaIzq' }) do
        local p = self:getPieza(nombre)
        if p then
            p:setVisible(false)
        end
    end
    local pelvis = self:getPieza('pelvis').datos.matriz
    -- Raíz = asiento por la inversa del reposo de la pelvis (solo traslada).
    self.datos.sentado.bajarPelvis = { 1, 0, 0, -pelvis[4], 0, 1, 0, -pelvis[8], 0, 0, 1, -pelvis[12], 0, 0, 0, 1 }
    self.datos.sentado.giroPie = 0
end

function Sentado.onUpdate(self, dt)
    local d = self.datos.sentado
    local v = self.vehiculo
    local asiento = v and v:getPieza('asientoConductor')
    local m = asiento and asiento:getMatriz()
    if not m then
        return
    end
    self.raizFija = PiezaRobot.multiplicarEn(m, d.bajarPelvis, self.raizFija or {})
    self.x, self.y, self.rumbo = m[4], m[8], v.rumbo
    local camion = v.datos.ruedasCamion
    if camion and camion.giroRueda then
        d.giroPie = camion.giroRueda / Sentado.relacion
    end
end

function Sentado.onPose(self)
    local giro = self.datos.sentado.giroPie
    self:getPieza('engranajePieDer'):setGiro('y', giro, 'rodar')
    self:getPieza('engranajePieIzq'):setGiro('y', giro, 'rodar')
end

Nucleo.registrarEspecializacion('sentado', Sentado)
return Sentado

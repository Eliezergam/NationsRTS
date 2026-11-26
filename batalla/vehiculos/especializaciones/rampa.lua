-- Especialización `rampa`: gira la rampa de los misiles en su bisagra según
-- la elevación que lleva la simulación (`unidad.elevacion`, en grados; la
-- sube y la baja Tropas). Los misiles cargados y el vástago del pistón son
-- hijos de la rampa: la siguen solos, y el cilindro apunta a su unión
-- (batalla/articulacion_camion.lua).

---@class Rampa : Especializacion, Vehiculo
local Rampa = {}

-- La pieza y su eje de giro (con un ángulo negativo, la punta sube).
Rampa.pieza = 'rampaLanzador'
Rampa.eje = 'y'

function Rampa:prerequisitos()
    return self:getTienePieza(Rampa.pieza)
end

function Rampa:onLoad()
    self.datos.rampa = {
        pieza = self:getPieza(Rampa.pieza),
    }
end

--- Antes de cada cálculo de matrices: la rampa en la elevación de ahora
-- (la boca de los misiles sale de ella al dispararlos).
function Rampa:onPose()
    local elevacion = self.unidad.elevacion or 0
    self.datos.rampa.pieza:setGiro(Rampa.eje, -math.rad(elevacion))
end

GestorVehiculos.registrarEspecializacion('rampa', Rampa)

return Rampa

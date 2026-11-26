-- Especialización `hidraulicos`: los amortiguadores y el pistón de la rampa.
--
-- Cada uno es un cuerpo y un vástago que se miran: el cuerpo apunta a su
-- ancla de abajo (en la suspensión) y el vástago a la de arriba (en el
-- chasis); al moverse la rueda o la rampa, se estiran y encogen. Lo hace
-- `pieza:setApuntarA(destino, x, y, z)`, una restricción como la «Track To» de
-- Blender: la pieza gira lo mínimo para que su eje mire al destino, con el
-- destino de este mismo cuadro.
--
-- Qué apunta a qué sale de la tabla `apuntan` del modelo: `hacia` es un
-- punto de `puntos` (una pieza y un punto suyo) o el pivote de otra pieza.

---@class Hidraulicos : Especializacion, Vehiculo
local Hidraulicos = {}

function Hidraulicos:prerequisitos()
    local datos = self:getContrato('apuntan')
    return datos ~= nil and #datos > 0
end

function Hidraulicos:onLoad()
    local puntos = self:getContrato('puntos') or {}
    local lista = {}
    for _, dato in ipairs(self:getContrato('apuntan')) do
        if self:getTienePieza(dato.pieza) then
            local pieza = self:getPieza(dato.pieza)
            local punto = puntos[dato.hacia]
            if punto then
                local p = punto.punto
                pieza:setApuntarA(punto.pieza, p[1], p[2], p[3])
            else
                pieza:setApuntarA(dato.hacia)
            end
            lista[#lista + 1] = pieza
        end
    end
    self.datos.hidraulicos = { lista = lista }
end

GestorVehiculos.registrarEspecializacion('hidraulicos', Hidraulicos)

return Hidraulicos

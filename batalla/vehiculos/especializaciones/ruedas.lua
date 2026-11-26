-- Especialización `ruedas`: cada rueda rueda lo que su lado ha avanzado y
-- las de dirección giran con el volante. Lo que ha rodado cada una
-- (`unidad.giroRuedas`) y el volante (`unidad.direccionRuedas`) los lleva
-- Lanzamisiles:medirMovimiento con el movimiento real del camión; aquí solo
-- se ponen en las piezas: primero el volante (sobre z) y encima lo que rueda
-- (sobre y), en dos capas.

---@class Ruedas : Especializacion, Vehiculo
local Ruedas = {}

-- Las piezas de las ruedas empiezan así.
Ruedas.prefijo = 'rueda'

function Ruedas:prerequisitos()
    return self:getContrato('ruedas') ~= nil
end

function Ruedas:onLoad()
    local deDireccion = {}
    for _, nombre in ipairs(self:getContrato('ruedas').direccion or {}) do
        deDireccion[nombre] = true
    end
    local lista = {}
    for _, nombre in ipairs(self:getNombresPiezas()) do
        if nombre:sub(1, #Ruedas.prefijo) == Ruedas.prefijo then
            local rueda = {
                nombre = nombre,
                pieza = self:getPieza(nombre),
                direccion = deDireccion[nombre] or false,
            }
            -- Las dos capas, en este orden: volante y luego lo que rueda.
            rueda.pieza:setGiro('z', 0, 'direccion')
            rueda.pieza:setGiro('y', 0, 'rodar')
            lista[#lista + 1] = rueda
        end
    end
    self.datos.ruedas = { lista = lista }
end

--- Antes de cada cálculo de matrices: cada rueda con su volante y su giro.
function Ruedas:onPose()
    local unidad = self.unidad
    local volante = unidad.direccionRuedas or 0
    local giros = unidad.giroRuedas
    for _, rueda in ipairs(self.datos.ruedas.lista) do
        rueda.pieza:setGiro('z', rueda.direccion and volante or 0, 'direccion')
        rueda.pieza:setGiro('y', giros[rueda.nombre] or 0, 'rodar')
    end
end

GestorVehiculos.registrarEspecializacion('ruedas', Ruedas)

return Ruedas

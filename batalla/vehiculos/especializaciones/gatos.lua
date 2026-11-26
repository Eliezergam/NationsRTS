-- Especialización `gatos`: los cuatro gatos hidráulicos que apoyan el camión
-- antes de subir la rampa. La simulación lleva `unidad.gatos` de 0
-- (recogidos) a 1 (apoyados) en línea recta (Tropas, fases `apoyando` y
-- `bajando`); aquí cada gato baja su recorrido con arranque y frenada suaves.
-- Sus datos salen de la tabla `gatos` del modelo
-- (assets/modelos3d/CAMION_MISILES_CONTRATO.md).

---@class Gatos : Especializacion, Vehiculo
local Gatos = {}

function Gatos:prerequisitos()
    local datos = self:getContrato('gatos')
    return datos ~= nil and #datos > 0
end

function Gatos:onLoad()
    local lista = {}
    for _, dato in ipairs(self:getContrato('gatos')) do
        if self:getTienePieza(dato.pieza) then
            lista[#lista + 1] = {
                pieza = self:getPieza(dato.pieza),
                -- Cuánto baja (px, negativo hacia el suelo).
                bajada = dato.zDesplegado - dato.zRecogido,
            }
        end
    end
    self.datos.gatos = { lista = lista }
end

--- Antes de cada cálculo de matrices: cada gato a su altura de ahora.
function Gatos:onPose()
    local g = self.unidad.gatos or 0
    local suave = g * g * (3 - 2 * g)
    for _, gato in ipairs(self.datos.gatos.lista) do
        gato.pieza:setDesplazamiento(0, 0, gato.bajada * suave)
    end
end

GestorVehiculos.registrarEspecializacion('gatos', Gatos)

return Gatos

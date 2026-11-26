-- Especialización `misiles`: en la rampa solo se ven los misiles que quedan
-- cargados. Salen en el orden de disparo (self:ordenMisiles); destruido
-- el camión, ninguno. Se decide antes de cada cálculo de matrices, también
-- en el mismo instante en que sale un misil.

---@class Misiles : Especializacion, Vehiculo
local Misiles = {}

function Misiles:prerequisitos()
    return #self:getOrdenMisiles() > 0
end

function Misiles:onLoad()
    local lista = {}
    for indice, nombre in ipairs(self:getOrdenMisiles()) do
        lista[indice] = self:getPieza(nombre)
    end
    self.datos.misiles = { lista = lista }
end

function Misiles:onPose()
    local lista = self.datos.misiles.lista
    -- Los que ya salieron son los primeros del orden de disparo.
    local disparados = #lista - self:getMisilesCargados()
    for indice, pieza in ipairs(lista) do
        pieza:setVisible(self:getVivo() and indice > disparados)
    end
end

GestorVehiculos.registrarEspecializacion('misiles', Misiles)

return Misiles

-- Especialización `ventiladores`: los ventiladores del radiador giran sobre
-- su eje siempre: al ralentí y algo más rápido al avanzar. Con el camión
-- parado solo se recomponen ellos (Vehiculo:recomponeSiempre).

---@class Ventiladores : Especializacion, Vehiculo
local Ventiladores = {}

-- Vueltas por segundo de más por cada metro por segundo, y como mucho.
Ventiladores.vueltasPorMetro = 0.6
Ventiladores.vueltasMarchaMaximas = 8
-- Al ralentí, si el modelo no lo dice.
Ventiladores.vueltasRalenti = 8

function Ventiladores:prerequisitos()
    local datos = self:getContrato('ventiladores')
    return datos ~= nil and #datos > 0
end

function Ventiladores:onLoad()
    local lista = {}
    for _, dato in ipairs(self:getContrato('ventiladores')) do
        if self:getTienePieza(dato.pieza) then
            lista[#lista + 1] = {
                pieza = self:getPieza(dato.pieza),
                eje = dato.eje or 'x',
                ralenti = dato.vueltasPorSegundoAlRalenti or Ventiladores.vueltasRalenti,
                giro = 0,
            }
        end
    end
    self.datos.ventiladores = { lista = lista }
end

function Ventiladores:onUpdate(dt)
    -- 10 px = 1 m.
    local metros = self:getVelocidad() / 10
    local marcha = math.min(Ventiladores.vueltasMarchaMaximas, metros * Ventiladores.vueltasPorMetro)
    for _, ventilador in ipairs(self.datos.ventiladores.lista) do
        local vueltas = ventilador.ralenti + marcha
        ventilador.giro = (ventilador.giro + vueltas * 2 * math.pi * dt) % (math.pi * 2)
    end
end

function Ventiladores:onPose()
    for _, ventilador in ipairs(self.datos.ventiladores.lista) do
        ventilador.pieza:setGiro(ventilador.eje, ventilador.giro)
    end
end

GestorVehiculos.registrarEspecializacion('ventiladores', Ventiladores)

return Ventiladores

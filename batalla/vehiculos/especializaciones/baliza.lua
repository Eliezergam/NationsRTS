-- Especialización `baliza`: la luz del techo que parpadea.
--
-- La luz encendida es una pieza aparte (la cubierta con el naranja que
-- brilla del atlas, tools/blender/camion_misiles_baliza_luz.py) por fuera de
-- la apagada: encendida se enseña y apagada se oculta, y se ve la de debajo.
-- El reloj es el de la batalla (el dt de cada paso): en pausa, se queda como
-- está. Destruido el vehículo, apagada.

---@class Baliza : Especializacion, Vehiculo
local Baliza = {}

-- Parpadeo, en segundos:
--   periodo      lo que dura un ciclo completo
--   destellos    cuántos destellos hay al principio de cada ciclo
--   encendida    cuánto dura encendido cada destello
--   separacion   del inicio de un destello al del siguiente
-- Doble destello cada 1,2 s, como las balizas de LED de los camiones.
Baliza.nombrePieza = 'balizaLuz'
Baliza.periodo = 1.2
Baliza.destellos = 2
Baliza.encendida = 0.09
Baliza.separacion = 0.2

function Baliza:prerequisitos()
    return self:getTienePieza(Baliza.nombrePieza)
end

function Baliza:onLoad()
    local unidad = self.unidad
    -- Desfase de cada vehículo en el ciclo para que no parpadeen todos a la
    -- vez: sale de su orden de entrada y su bando (batalla/tropas.lua).
    local numero = (unidad.numero or 0) + (unidad.bando or 0) * 0.5
    self.datos.baliza = {
        pieza = self:getPieza(Baliza.nombrePieza),
        tiempo = (numero * 0.618034 % 1) * Baliza.periodo,
    }
    self.datos.baliza.pieza:setVisible(false)
end

function Baliza:onUpdate(dt)
    local baliza = self.datos.baliza
    baliza.tiempo = (baliza.tiempo + dt) % Baliza.periodo
    local encendida = not self.unidad.muerto and Baliza.getEncendidaEn(baliza.tiempo)
    baliza.pieza:setVisible(encendida)
end

--- ¿Está encendida en el instante `fase` del ciclo (segundos)?
function Baliza.getEncendidaEn(fase)
    for destello = 0, Baliza.destellos - 1 do
        local inicio = destello * Baliza.separacion
        if fase >= inicio and fase < inicio + Baliza.encendida then
            return true
        end
    end
    return false
end

GestorVehiculos.registrarEspecializacion('baliza', Baliza)

return Baliza

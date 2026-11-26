-- Especialización `estremecimiento`: el chasis tiembla con cada misil que
-- sale. El empuje va hacia atrás y abajo por la rampa (bisagra trasera):
-- baja la trasera (el frente sube), hunde el chasis y baja el lado del
-- misil. Es un muelle amortiguado que se apaga en menos de 1 s. Las ruedas
-- siguen en el suelo (lo compensa la especialización `suspension`).

---@class Estremecimiento : Especializacion, Vehiculo
local Estremecimiento = {}

-- Muelle: frecuencia (Hz) y amortiguamiento (0 oscila siempre, 1 sin
-- rebote).
Estremecimiento.frecuencia = 3.5
Estremecimiento.amortiguamiento = 0.3
-- Impulso de cada disparo: cabeceo y balanceo en rad/s, altura en px/s.
Estremecimiento.impulsoCabeceo = 0.24
Estremecimiento.impulsoBalanceo = 0.12
Estremecimiento.impulsoAltura = 7

function Estremecimiento:prerequisitos()
    return #self:getOrdenMisiles() > 0
end

function Estremecimiento:onLoad()
    self.datos.estremecimiento = {
        cabeceo = 0,
        vCabeceo = 0,
        balanceo = 0,
        vBalanceo = 0,
        altura = 0,
        vAltura = 0,
        activo = false,
        cargadosVistos = self:getMisilesCargados(),
    }
end

--- Golpe del misil `nombre` al salir.
function Estremecimiento:golpe(nombre)
    local e = self.datos.estremecimiento
    local _, y = self:getPieza(nombre):getPivoteVehiculo()
    local lado = y > 0 and 1 or (y < 0 and -1 or 0)
    e.vCabeceo = e.vCabeceo - Estremecimiento.impulsoCabeceo
    e.vAltura = e.vAltura - Estremecimiento.impulsoAltura
    e.vBalanceo = e.vBalanceo - lado * Estremecimiento.impulsoBalanceo
    e.activo = true
end

--- Un paso del muelle (posición `p`, velocidad `v`) hacia 0.
local function muelle(p, v, dt)
    local w = 2 * math.pi * Estremecimiento.frecuencia
    local zeta = Estremecimiento.amortiguamiento
    -- Euler semiimplícito en subpasos de 1/240 s: estable con cualquier dt.
    local pasos = math.max(1, math.ceil(dt * 240))
    local h = dt / pasos
    for _ = 1, pasos do
        v = v + (-w * w * p - 2 * zeta * w * v) * h
        p = p + v * h
    end
    return p, v
end

function Estremecimiento:onUpdate(dt)
    local e = self.datos.estremecimiento
    -- Cada misil que falta desde el paso anterior da su golpe.
    local cargados = self:getMisilesCargados()
    if cargados < e.cargadosVistos and self:getVivo() then
        local orden = self:getOrdenMisiles()
        for k = e.cargadosVistos, cargados + 1, -1 do
            Estremecimiento.golpe(self, orden[#orden - k + 1])
        end
    end
    e.cargadosVistos = cargados
    if not e.activo then
        return
    end
    e.cabeceo, e.vCabeceo = muelle(e.cabeceo, e.vCabeceo, dt)
    e.balanceo, e.vBalanceo = muelle(e.balanceo, e.vBalanceo, dt)
    e.altura, e.vAltura = muelle(e.altura, e.vAltura, dt)
    local giro = math.abs(e.cabeceo) + math.abs(e.balanceo) + (math.abs(e.vCabeceo) + math.abs(e.vBalanceo)) * 0.01
    local alto = math.abs(e.altura) + math.abs(e.vAltura) * 0.01
    if giro < 0.00005 and alto < 0.005 then
        e.cabeceo, e.vCabeceo, e.balanceo, e.vBalanceo, e.altura, e.vAltura = 0, 0, 0, 0, 0, 0
        e.activo = false
    end
    self:setInclinacionChasis(e.altura, e.cabeceo, e.balanceo)
end

GestorVehiculos.registrarEspecializacion('estremecimiento', Estremecimiento)

return Estremecimiento

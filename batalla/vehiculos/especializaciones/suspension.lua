-- Especialización `suspension`: las ruedas se apoyan en el suelo.
--
-- Cada vez que el camión se mueve se mide el terreno bajo cada rueda. El
-- chasis se lleva una parte del desnivel (`promedioChasis`: altura, cabeceo
-- y balanceo por mínimos cuadrados) y cada suspensión el resto, dentro de su
-- recorrido. Las dos cosas llegan a su sitio con suavizado.
--
-- Las ruedas siguen en el suelo aunque otra especialización mueva el chasis
-- (el temblor del disparo, `estremecimiento`): cada suspensión compensa lo
-- que el chasis se aparta por las capas de las demás. Se ve en los
-- amortiguadores (especialización `hidraulicos`).
--
-- Sus datos salen de la tabla `suspensiones` del modelo
-- (assets/modelos3d/CAMION_MISILES_CONTRATO.md).

---@class Suspension : Especializacion, Vehiculo
local Suspension = {}

-- Parte del desnivel que se lleva el chasis (0 nada, 1 todo).
Suspension.promedioChasis = 0.5
-- Segundos en que la suspensión y el chasis llegan casi a su sitio.
Suspension.suavizadoRuedas = 0.06
Suspension.suavizadoChasis = 0.12

function Suspension:prerequisitos()
    local datos = self:getContrato('suspensiones')
    return datos ~= nil and #datos > 0
end

function Suspension:onLoad()
    local lista = {}
    for _, dato in ipairs(self:getContrato('suspensiones')) do
        if self:getTienePieza(dato.pieza) then
            local pieza = self:getPieza(dato.pieza)
            local x, y = pieza:getPivoteVehiculo()
            lista[#lista + 1] = {
                nombre = dato.pieza,
                pieza = pieza,
                x = x,
                y = y,
                arriba = dato.recorridoArriba,
                abajo = dato.recorridoAbajo,
                z = 0,
                objetivo = 0,
            }
        end
    end
    self.datos.suspension = {
        lista = lista,
        chasis = { altura = 0, cabeceo = 0, balanceo = 0 },
        chasisObjetivo = { altura = 0, cabeceo = 0, balanceo = 0 },
        medido = false,
    }
end

--- Mide el suelo bajo cada rueda con el casco de ahora y fija los objetivos.
function Suspension:medirSuelo()
    local datos = self.datos.suspension
    local lista = datos.lista
    local centro = self:getCentroChasis()
    local n = #lista
    local sx, sy, sd, sxx, syy, sxd, syd = 0, 0, 0, 0, 0, 0, 0
    for _, s in ipairs(lista) do
        local wx, wy, wz = self:getPuntoMundo(s.x, s.y, 0)
        local d = self:getAlturaSuelo(wx, wy) - wz
        s.desnivel = d
        local x = s.x - centro
        sx, sy, sd = sx + x, sy + s.y, sd + d
        sxx, syy = sxx + x * x, syy + s.y * s.y
        sxd, syd = sxd + x * d, syd + s.y * d
    end
    local mx, my, md = sx / n, sy / n, sd / n
    local varX = sxx / n - mx * mx
    local varY = syy / n - my * my
    local pendienteX = varX > 1e-6 and (sxd / n - mx * md) / varX or 0
    local pendienteY = varY > 1e-6 and (syd / n - my * md) / varY or 0
    local f = Suspension.promedioChasis
    local objetivo = datos.chasisObjetivo
    objetivo.altura = md * f
    -- Suelo más alto delante: el frente sube (cabeceo negativo).
    objetivo.cabeceo = -math.atan(pendienteX * f)
    objetivo.balanceo = math.atan(pendienteY * f)
    for _, s in ipairs(lista) do
        local x = s.x - centro
        local chasis = objetivo.altura + x * pendienteX * f + s.y * pendienteY * f
        s.objetivo = math.max(-s.abajo, math.min(s.arriba, s.desnivel - chasis))
    end
end

--- `actual` acercándose a `objetivo` en `tiempo` segundos (exponencial).
local function acercar(actual, objetivo, dt, tiempo, margen)
    local mezcla = dt > 0 and (1 - math.exp(-dt / tiempo)) or 1
    local valor = actual + (objetivo - actual) * mezcla
    if math.abs(valor - objetivo) < margen then
        valor = objetivo
    end
    return valor
end

function Suspension:onUpdate(dt)
    if not self:getVivo() then
        return
    end
    local datos = self.datos.suspension
    if self:getSeHaMovido() or not datos.medido then
        Suspension.medirSuelo(self)
        datos.medido = true
    end
    for _, s in ipairs(datos.lista) do
        s.z = acercar(s.z, s.objetivo, dt, Suspension.suavizadoRuedas, 0.001)
    end
    local chasis, objetivo = datos.chasis, datos.chasisObjetivo
    for clave, valor in pairs(objetivo) do
        chasis[clave] = acercar(chasis[clave], valor, dt, Suspension.suavizadoChasis, 0.00001)
    end
    self:setInclinacionChasis(chasis.altura, chasis.cabeceo, chasis.balanceo)
end

--- Antes de cada cálculo de matrices: cada suspensión a su altura, con lo
-- que compensa del chasis que mueven los demás.
function Suspension:onPose()
    local datos = self.datos.suspension
    local centro = self:getCentroChasis()
    local altura, cabeceo, balanceo = self:getChasisDeOtros()
    local otros = altura ~= 0 or cabeceo ~= 0 or balanceo ~= 0
    for _, s in ipairs(datos.lista) do
        local z = s.z
        if otros then
            z = z - altura + (s.x - centro) * cabeceo - s.y * balanceo
            z = math.max(-s.abajo, math.min(s.arriba, z))
        end
        s.pieza:setDesplazamiento(0, 0, z)
    end
end

GestorVehiculos.registrarEspecializacion('suspension', Suspension)

return Suspension

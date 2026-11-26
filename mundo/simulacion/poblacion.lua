--- Población por edades y sexo (diseno/poblacion.md): cohortes, nacimientos, muertes, reclutas y retiro.
--
-- Cada ciudad guarda a su gente en `c.demografia`:
--   H[1..90], M[1..90]    hombres y mujeres de cada edad (índice = edad + 1)
--   RH[1..90], RM[1..90]  de esa cohorte, cuántos están en filas (0 ≤ R ≤ H o M)
--   resto[1..180]         lo que queda de las muertes de cada cohorte (en
--                         millonésimas de persona, entero; 2·edad+1 hombres,
--                         2·edad+2 mujeres)
--   restoH, restoM        lo mismo de los nacimientos
--   anio                  lo del año en curso: nacidos, muertos por causa
--                         (natural, hambre, vejez, combate) y retirados
-- `c.poblacion` sigue siendo el total (Σ H + Σ M).
--
-- «En filas» es todo soldado de la ciudad en el inventario de la economía (en
-- instrucción, en la guarnición, fuera en un grupo, una base o un campamento,
-- herido): Σ RH + Σ RM = inventarioCiudad(c).soldados (el invariante).
--
-- Todo son enteros: las fracciones de cada día se acumulan en `resto` y los
-- repartos entre cohortes son por restos mayores (ayudas.repartirRestos), a
-- igual fracción la menor edad y antes los hombres. Sin azar.
--
-- Módulo de `mundo/simulacion.lua`: `Poblacion.instalar(Simulacion)` cuelga sus
-- funciones de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')

local repartirRestos = Ayudas.repartirRestos

local Poblacion = {}

-- Se fija en `instalar`: la clase.
local Simulacion

local MILLON = 1000000

-- Reglas (diseno/poblacion.md, F1 a F11 y §7) ------------------------------------------------------

Poblacion.reglas = {
    anio = 10, -- F1: días de juego por año
    edades = 90, -- cohortes de 0 a 89 años; quien cumple 90 muere
    -- F4: mortalidad natural anual por edad ({ desde, tasa }).
    mortalidad = {
        { 0, 0.04 },
        { 1, 0.01 },
        { 5, 0.003 },
        { 15, 0.004 },
        { 50, 0.01 },
        { 60, 0.025 },
        { 70, 0.06 },
        { 80, 0.15 },
    },
    natalidad = 0.22, -- F3: hijos por pareja y año con todo a favor
    varones = 0.512, -- parte de los nacimientos que son niños
    fertilMin = 15, -- F2: mujeres que forman pareja
    fertilMax = 49,
    parejaMin = 15, -- F2: hombres que forman pareja
    parejaMax = 64,
    edadMin = 18, -- F6: edad militar (hombres y mujeres)
    edadMax = 49,
    parte = 0.5, -- F6: parte de los aptos que puede estar en filas
    retiro = 60, -- F7: el soldado que cumple esta edad vuelve a casa
    trabajaMin = 15, -- F8: edad de trabajar
    trabajaMax = 64,
    hambre = 0.003, -- F5: muertes extra al día sin comida
    comidaHolgada = 0.25, -- F3: granero por encima del cual la comida no frena
    asedio = 0.5, -- F3: natalidad de una ciudad sitiada
    viviendas = { 20, 26, 34, 42, 50 }, -- F3: habitantes por px de radio según el nivel
    viviendaLlena = 0.8, -- F3: ocupación desde la que bajan los nacimientos
    crecimientoInicial = 0.02, -- F11: forma de la pirámide inicial (crecimiento anual)
    minimo = 200, -- F10: colonos si la ciudad baja de aquí
    -- Edades de las que salen los soldados que no caben en los aptos (partida
    -- vieja o escenario): primero 15 a 17 y 50 a 59, después cualquier adulto.
    reservaMin = 15,
    reservaMax = 59,
}

local REGLAS = Poblacion.reglas
local EDADES = REGLAS.edades

-- Muertes al día por cada millón de personas de cada edad (F4 / anio): enteros,
-- para que los restos sean enteros y el guardado corto.
local MUERTES = {}
for a = 0, EDADES - 1 do
    local tasa = 0
    for _, fila in ipairs(REGLAS.mortalidad) do
        if a >= fila[1] then
            tasa = fila[2]
        end
    end
    MUERTES[a + 1] = math.floor(tasa * MILLON / REGLAS.anio + 0.5)
end
local HAMBRE = math.floor(REGLAS.hambre * MILLON + 0.5)

-- Utilidades -----------------------------------------------------------------------------------------

--- Σ de `t` entre las edades `desde` y `hasta`.
local function suma(t, desde, hasta)
    local s = 0
    for a = desde, hasta do
        s = s + t[a + 1]
    end
    return s
end

--- Habitantes de la demografía `d`.
function Poblacion.total(d)
    return suma(d.H, 0, EDADES - 1) + suma(d.M, 0, EDADES - 1)
end

--- Personas en filas de `d`.
function Poblacion.enFilas(d)
    return suma(d.RH, 0, EDADES - 1) + suma(d.RM, 0, EDADES - 1)
end

--- Aptos para filas (F6): hombres y mujeres de `edadMin` a `edadMax`, en filas o no.
function Poblacion.aptos(d)
    return suma(d.H, REGLAS.edadMin, REGLAS.edadMax) + suma(d.M, REGLAS.edadMin, REGLAS.edadMax)
end

--- Personas en edad de trabajar (F8), en filas o no.
function Poblacion.enEdadDeTrabajar(d)
    return suma(d.H, REGLAS.trabajaMin, REGLAS.trabajaMax) + suma(d.M, REGLAS.trabajaMin, REGLAS.trabajaMax)
end

local function anioVacio()
    return { nacidos = 0, natural = 0, hambre = 0, vejez = 0, combate = 0, retirados = 0, colonos = 0 }
end

--- Pesos intercalados por edad (hombres antes que mujeres) de las edades
-- `desde`..`hasta`: `peso(sexo, i)` con sexo 'H' o 'M' e i = edad + 1.
local function intercalados(desde, hasta, peso)
    local pesos, cohortes = {}, {}
    for a = desde, hasta do
        for _, sexo in ipairs({ 'H', 'M' }) do
            pesos[#pesos + 1] = peso(sexo, a + 1)
            cohortes[#cohortes + 1] = { sexo, a + 1 }
        end
    end
    return pesos, cohortes
end

-- Crear -----------------------------------------------------------------------------------------------

--- Demografía nueva de `poblacion` habitantes (F11: pirámide estable que crece
-- un `crecimientoInicial` al año con la mortalidad de F4) con `soldados` en
-- filas (ver `alistar`).
function Poblacion.crearDemografia(poblacion, soldados)
    local pesos = {}
    local vivos = 1
    for a = 0, EDADES - 1 do
        local w = vivos * math.exp(-REGLAS.crecimientoInicial * a)
        pesos[2 * a + 1] = w * REGLAS.varones
        pesos[2 * a + 2] = w * (1 - REGLAS.varones)
        vivos = vivos * (1 - MUERTES[a + 1] * REGLAS.anio / MILLON)
    end
    local n = repartirRestos(pesos, poblacion)
    local d = { H = {}, M = {}, RH = {}, RM = {}, resto = {}, restoH = 0, restoM = 0, anio = anioVacio() }
    for a = 1, EDADES do
        d.H[a] = n[2 * a - 1]
        d.M[a] = n[2 * a]
        d.RH[a] = 0
        d.RM[a] = 0
        d.resto[2 * a - 1] = 0
        d.resto[2 * a] = 0
    end
    Poblacion.alistar(d, soldados or 0)
    return d
end

-- Filas -----------------------------------------------------------------------------------------------

--- Pone `cantidad` civiles de las edades `desde`..`hasta` en filas, en
-- proporción a los civiles de cada cohorte. Devuelve cuántos.
local function alistarEntre(d, cantidad, desde, hasta)
    local pesos, cohortes = intercalados(desde, hasta, function(sexo, i)
        return d[sexo][i] - d['R' .. sexo][i]
    end)
    local r = repartirRestos(pesos, cantidad, pesos)
    local hecho = 0
    for k, v in ipairs(r) do
        local sexo, i = cohortes[k][1], cohortes[k][2]
        d['R' .. sexo][i] = d['R' .. sexo][i] + v
        hecho = hecho + v
    end
    return hecho
end

--- Recluta `cantidad` (3.5): primero de los civiles aptos; lo que no quepa
-- (una partida vieja o el escenario de prueba), de 15 a 17 y 50 a 59, después
-- de cualquier adulto y, si ni así, llegan como colonos de 25 años ya en
-- filas. Devuelve cuántos tuvieron que llegar de fuera.
function Poblacion.alistar(d, cantidad)
    local falta = cantidad - alistarEntre(d, cantidad, REGLAS.edadMin, REGLAS.edadMax)
    if falta > 0 then
        falta = falta - alistarEntre(d, falta, REGLAS.reservaMin, REGLAS.reservaMax)
    end
    if falta > 0 then
        falta = falta - alistarEntre(d, falta, REGLAS.reservaMin, EDADES - 1)
    end
    local llegan = falta
    if falta > 0 then
        local hombres = math.ceil(falta / 2)
        d.H[26], d.RH[26] = d.H[26] + hombres, d.RH[26] + hombres
        d.M[26], d.RM[26] = d.M[26] + falta - hombres, d.RM[26] + falta - hombres
    end
    return llegan
end

--- Quita `cantidad` de los que están en filas, en proporción a los de cada
-- cohorte; con `mueren`, salen también de la población. Devuelve cuántos.
function Poblacion.quitarDeFilas(d, cantidad, mueren)
    local pesos, cohortes = intercalados(0, EDADES - 1, function(sexo, i)
        return d['R' .. sexo][i]
    end)
    local r = repartirRestos(pesos, cantidad, pesos)
    local hecho = 0
    for k, v in ipairs(r) do
        if v > 0 then
            local sexo, i = cohortes[k][1], cohortes[k][2]
            d['R' .. sexo][i] = d['R' .. sexo][i] - v
            if mueren then
                d[sexo][i] = d[sexo][i] - v
            end
            hecho = hecho + v
        end
    end
    return hecho
end

--- Quita de la población `cantidad` civiles (los que no están en filas) de
-- las edades `desde`..`hasta`, en proporción a los civiles de cada cohorte.
-- Devuelve cuántos.
local function quitarCiviles(d, cantidad, desde, hasta)
    local pesos, cohortes = intercalados(desde, hasta, function(sexo, i)
        return d[sexo][i] - d['R' .. sexo][i]
    end)
    local r = repartirRestos(pesos, cantidad, pesos)
    local hecho = 0
    for k, v in ipairs(r) do
        if v > 0 then
            local sexo, i = cohortes[k][1], cohortes[k][2]
            d[sexo][i] = d[sexo][i] - v
            hecho = hecho + v
        end
    end
    return hecho
end

--- Mueve `cantidad` de los que están en filas de `d` a `destino`, con su edad
-- y su sexo (siguen en filas). Devuelve cuántos.
local function mudarFilas(d, destino, cantidad)
    local pesos, cohortes = intercalados(0, EDADES - 1, function(sexo, i)
        return d['R' .. sexo][i]
    end)
    local r = repartirRestos(pesos, cantidad, pesos)
    local hecho = 0
    for k, v in ipairs(r) do
        if v > 0 then
            local sexo, i = cohortes[k][1], cohortes[k][2]
            d['R' .. sexo][i] = d['R' .. sexo][i] - v
            d[sexo][i] = d[sexo][i] - v
            destino['R' .. sexo][i] = destino['R' .. sexo][i] + v
            destino[sexo][i] = destino[sexo][i] + v
            hecho = hecho + v
        end
    end
    return hecho
end

-- El día --------------------------------------------------------------------------------------------

--- Año nuevo (3.2): todas las cohortes cumplen un año (los de 89 mueren de
-- viejos) y se retiran los soldados de `retiro` años o más que están en la
-- guarnición (F7). Devuelve cuántos se retiraron.
local function anioNuevo(d, c)
    d.anio = anioVacio()
    -- Los que están en filas con 89 años no mueren de viejos: siguen en el
    -- inventario (en un grupo, en el taller...) y se quedan en la última
    -- cohorte hasta que se retiren en casa. Si murieran aquí, el inventario los
    -- seguiría contando.
    local filasH, filasM = d.RH[EDADES], d.RM[EDADES]
    d.anio.vejez = d.H[EDADES] - filasH + d.M[EDADES] - filasM
    for _, campo in ipairs({ 'H', 'M', 'RH', 'RM' }) do
        local t = d[campo]
        for a = EDADES, 2, -1 do
            t[a] = t[a - 1]
        end
        t[1] = 0
    end
    d.H[EDADES], d.RH[EDADES] = d.H[EDADES] + filasH, d.RH[EDADES] + filasH
    d.M[EDADES], d.RM[EDADES] = d.M[EDADES] + filasM, d.RM[EDADES] + filasM
    for a = EDADES, 2, -1 do
        d.resto[2 * a - 1] = d.resto[2 * a - 3]
        d.resto[2 * a] = d.resto[2 * a - 2]
    end
    d.resto[1], d.resto[2] = 0, 0
    local pesos, cohortes = intercalados(REGLAS.retiro, EDADES - 1, function(sexo, i)
        return d['R' .. sexo][i]
    end)
    local retirables = 0
    for _, v in ipairs(pesos) do
        retirables = retirables + v
    end
    local salen = math.min(retirables, c.soldados or 0)
    if salen > 0 then
        local r = repartirRestos(pesos, salen, pesos)
        for k, v in ipairs(r) do
            local sexo, i = cohortes[k][1], cohortes[k][2]
            d['R' .. sexo][i] = d['R' .. sexo][i] - v
        end
        c.soldados = c.soldados - salen
        d.anio.retirados = salen
    end
    return salen
end

--- Muertes naturales y por hambre del día (F4, F5): solo civiles.
local function morir(d, hambre)
    local extra = hambre and HAMBRE or 0
    for a = 1, EDADES do
        for s = 1, 2 do
            local N = s == 1 and d.H or d.M
            local R = s == 1 and d.RH or d.RM
            local i = 2 * a - 2 + s
            local civiles = N[a] - R[a]
            if civiles > 0 then
                local x = civiles * (MUERTES[a] + extra) + d.resto[i]
                local k = math.min(civiles, math.floor(x / MILLON))
                d.resto[i] = x - k * MILLON
                N[a] = N[a] - k
                if k > 0 then
                    -- Los de hambre: su parte de la tasa, redondeada.
                    local deHambre = extra > 0 and math.floor(k * extra / (MUERTES[a] + extra) + 0.5) or 0
                    d.anio.hambre = d.anio.hambre + deHambre
                    d.anio.natural = d.anio.natural + k - deHambre
                end
            end
        end
    end
end

--- Factores de los nacimientos de `c` (F3): comida, vivienda, asedio y la
-- ocupación de la vivienda.
local function factores(self, c)
    local d = c.demografia
    local fComida = 0
    if not c.hambre then
        local lleno = (c.comida or 0) / math.max(1, Simulacion.granero(c))
        fComida = math.min(1, 0.5 + 0.5 * lleno / REGLAS.comidaHolgada)
    end
    local viviendas = REGLAS.viviendas
    local capacidad = c.radio * viviendas[math.max(1, math.min(#viviendas, c.nivel or 1))]
    local ocupacion = Poblacion.total(d) / capacidad
    local fVivienda = math.max(0, math.min(1, (1 - ocupacion) / (1 - REGLAS.viviendaLlena)))
    local fAsedio = self:sitiada(c) and REGLAS.asedio or 1
    return fComida, fVivienda, fAsedio, ocupacion
end
Poblacion.factores = factores

--- Parejas de `d` (F2): el menor entre mujeres de 15 a 49 y hombres de 15 a
-- 64, civiles y soldados, estén donde estén.
function Poblacion.parejas(d)
    return math.min(suma(d.M, REGLAS.fertilMin, REGLAS.fertilMax), suma(d.H, REGLAS.parejaMin, REGLAS.parejaMax))
end

--- Nacimientos del día (F2, F3); `politica` es `n.natalidad` (1 si falta).
local function nacer(self, d, c, politica)
    local fComida, fVivienda, fAsedio = Poblacion.factores(self, c)
    local nacen = Poblacion.parejas(d) * REGLAS.natalidad * politica / REGLAS.anio * fComida * fVivienda * fAsedio
    -- En millonésimas enteras, como las muertes.
    local x = math.floor(nacen * REGLAS.varones * MILLON) + d.restoH
    local h = math.floor(x / MILLON)
    d.restoH = x - h * MILLON
    x = math.floor(nacen * (1 - REGLAS.varones) * MILLON) + d.restoM
    local m = math.floor(x / MILLON)
    d.restoM = x - m * MILLON
    d.H[1] = d.H[1] + h
    d.M[1] = d.M[1] + m
    d.anio.nacidos = d.anio.nacidos + h + m
end

--- Colonos (F10): si la ciudad baja de `minimo`, llegan de 21 a 30 años,
-- mitad hombres y mitad mujeres, hasta `minimo`.
local function colonos(d)
    local faltan = REGLAS.minimo - Poblacion.total(d)
    if faltan <= 0 then
        return 0
    end
    local hombres = math.floor(faltan / 2)
    for k = 1, faltan do
        local i = 20 + (k - 1) % 10 + 2
        if k <= hombres then
            d.H[i] = d.H[i] + 1
        else
            d.M[i] = d.M[i] + 1
        end
    end
    d.anio.colonos = d.anio.colonos + faltan
    return faltan
end

--- Un día de la población de la ciudad `c` de la nación `n` (3.2 a 3.4, F10),
-- después de la economía del día (el hambre ya está decidida).
function Poblacion:diaDemografico(n, c)
    local d = c.demografia
    if not d then
        return
    end
    if self.estado.dia % REGLAS.anio == 0 then
        local salen = anioNuevo(d, c)
        self:medir('retirados', salen, c.nacion)
        self:medir('muertosVejez', d.anio.vejez)
    end
    local a = d.anio
    local nacidos, natural, hambre, llegan = a.nacidos, a.natural, a.hambre, a.colonos
    morir(d, c.hambre)
    nacer(self, d, c, n.natalidad or 1)
    colonos(d)
    c.poblacion = Poblacion.total(d)
    -- Medidas (solo si alguien mide: `sim.medidas`).
    self:medir('nacidos', a.nacidos - nacidos, c.nacion)
    self:medir('muertosNaturales', a.natural - natural)
    self:medir('muertosHambre', a.hambre - hambre)
    self:medir('colonos', a.colonos - llegan)
end

-- Reclutar, licenciar y morir -------------------------------------------------------------------------

--- Pone `cantidad` civiles aptos de `c` en filas (al encargar soldados).
function Poblacion:reclutar(c, cantidad)
    if c.demografia and cantidad > 0 then
        local llegan = Poblacion.alistar(c.demografia, cantidad)
        self:medir('reclutasSinCohorte', llegan, c.nacion)
        c.poblacion = Poblacion.total(c.demografia)
    end
end

--- `cantidad` soldados de `c` vuelven a ser civiles (licencia, orden cancelada).
function Poblacion:volverACasa(c, cantidad)
    if c.demografia and cantidad > 0 then
        Poblacion.quitarDeFilas(c.demografia, cantidad, false)
    end
end

--- Mueren en combate `cantidad` soldados de la nación `nid` que pertenecen a
-- la ciudad `ciudad` (F9): salen de filas y de la población de su cohorte. Si
-- allí no hay tantos en filas, de las demás ciudades de la nación (la capital
-- primero). Anota `muertos`.
function Poblacion:morirSoldados(nid, ciudad, cantidad)
    if not cantidad or cantidad <= 0 then
        return
    end
    self:medir('muertos', cantidad, nid)
    local quedan = cantidad
    local n = self.estado.naciones[nid]
    local orden = {}
    if ciudad and ciudad.nacion == nid then
        orden[1] = ciudad
    end
    local capital = n and self.estado.ciudades[n.capital]
    if capital and capital ~= ciudad and capital.nacion == nid then
        orden[#orden + 1] = capital
    end
    for _, c in ipairs(self:ciudadesDe(nid)) do
        if c ~= ciudad and c ~= capital then
            orden[#orden + 1] = c
        end
    end
    for _, c in ipairs(orden) do
        local d = c.demografia
        if quedan > 0 and d then
            local salen = Poblacion.quitarDeFilas(d, quedan, true)
            quedan = quedan - salen
            d.anio.combate = d.anio.combate + salen
            c.poblacion = Poblacion.total(d)
        end
    end
    self:medir('muertosSinCohorte', quedan, nid)
end

--- Mueren en combate `cantidad` tripulantes de vehículos de la nación `nid`
-- de la ciudad `ciudad` (decisión del dueño del 2026-10-01). Las
-- tripulaciones no están en filas (el invariante cuenta solo los soldados):
-- salen de la población, de los civiles en edad militar (`edadMin` a
-- `edadMax`) y, si no hay, de los de 15 a 59 y después de cualquier edad; de
-- su ciudad y, si no alcanza, de las demás (la capital primero), como F9.
-- Cuentan como muertos en combate del año (`anio.combate`). Anota
-- `muertosTripulacion`.
function Poblacion:morirTripulantes(nid, ciudad, cantidad)
    if not cantidad or cantidad <= 0 then
        return
    end
    self:medir('muertosTripulacion', cantidad, nid)
    local quedan = cantidad
    local n = self.estado.naciones[nid]
    local orden = {}
    if ciudad and ciudad.nacion == nid then
        orden[1] = ciudad
    end
    local capital = n and self.estado.ciudades[n.capital]
    if capital and capital ~= ciudad and capital.nacion == nid then
        orden[#orden + 1] = capital
    end
    for _, c in ipairs(self:ciudadesDe(nid)) do
        if c ~= ciudad and c ~= capital then
            orden[#orden + 1] = c
        end
    end
    for _, c in ipairs(orden) do
        local d = c.demografia
        if quedan > 0 and d then
            local salen = quitarCiviles(d, quedan, REGLAS.edadMin, REGLAS.edadMax)
            if salen < quedan then
                salen = salen + quitarCiviles(d, quedan - salen, REGLAS.reservaMin, REGLAS.reservaMax)
            end
            if salen < quedan then
                salen = salen + quitarCiviles(d, quedan - salen, 0, EDADES - 1)
            end
            quedan = quedan - salen
            d.anio.combate = d.anio.combate + salen
            c.poblacion = Poblacion.total(d)
        end
    end
    self:medir('tripulantesSinCohorte', quedan, nid)
end

--- Ciudad a la que pertenece una fuerza (un grupo o un sitio) de su nación.
function Poblacion:ciudadDeFuerza(q)
    if q.mision then
        return self:ciudadDeGrupo(q)
    end
    return self:ciudadDeSitio(q.nacion, q)
end

--- Pone de acuerdo las filas de cada ciudad de `nid` con su inventario de
-- soldados: cuando una ciudad cambia de manos o cae un sitio, los soldados
-- que están fuera pueden pasar a contar en otra ciudad de la nación (la más
-- cercana). Las personas se mudan con su edad y su sexo, de las ciudades que
-- tienen de más a las que tienen de menos. Con una sola ciudad no hace nada.
function Poblacion:ajustarFilas(nid)
    local ciudades = self:ciudadesDe(nid)
    if #ciudades < 2 then
        return
    end
    local inv = self:inventario(nid)
    local sobran, faltan = {}, {}
    for _, c in ipairs(ciudades) do
        local d = c.demografia
        if d then
            local tiene = inv.ciudades[c.id] and inv.ciudades[c.id].soldados or 0
            local dif = Poblacion.enFilas(d) - tiene
            if dif > 0 then
                sobran[#sobran + 1] = { c = c, n = dif }
            elseif dif < 0 then
                faltan[#faltan + 1] = { c = c, n = -dif }
            end
        end
    end
    local k = 1
    for _, f in ipairs(faltan) do
        while f.n > 0 and k <= #sobran do
            local s = sobran[k]
            local mueve = mudarFilas(s.c.demografia, f.c.demografia, math.min(f.n, s.n))
            s.n, f.n = s.n - mueve, f.n - mueve
            if s.n <= 0 or mueve == 0 then
                k = k + 1
            end
        end
    end
    for _, c in ipairs(ciudades) do
        if c.demografia then
            c.poblacion = Poblacion.total(c.demografia)
        end
    end
end

--- Una ciudad cedida (3.10): sus civiles se quedan; los que están en filas se
-- mudan a `capital` con su edad y su sexo.
function Poblacion.mudarFilasA(c, capital)
    local d, destino = c.demografia, capital.demografia
    if d and destino then
        mudarFilas(d, destino, Poblacion.enFilas(d))
        c.poblacion = Poblacion.total(d)
        capital.poblacion = Poblacion.total(destino)
    end
end

-- Consultas para la vista -----------------------------------------------------------------------------

--- La población de la ciudad `cid` para la vista: { total, decenios = { {
-- desde, hasta, hombres, mujeres, hombresEnFilas, mujeresEnFilas } } (de 0-9
-- a 80-89), aptos, enFilas, trabajan, ocupacion, frena = { vivienda, hambre,
-- sitiada } y el año en curso (nacidos, muertos por causa, retirados) }, o nil.
function Poblacion:demografiaCiudad(cid)
    local c = self.estado.ciudades[cid]
    local d = c and c.demografia
    if not d then
        return nil
    end
    local decenios = {}
    for desde = 0, EDADES - 1, 10 do
        local hasta = math.min(EDADES - 1, desde + 9)
        decenios[#decenios + 1] = {
            desde = desde,
            hasta = hasta,
            hombres = suma(d.H, desde, hasta),
            mujeres = suma(d.M, desde, hasta),
            hombresEnFilas = suma(d.RH, desde, hasta),
            mujeresEnFilas = suma(d.RM, desde, hasta),
        }
    end
    local _, fVivienda, fAsedio, ocupacion = Poblacion.factores(self, c)
    local enFilas = Poblacion.enFilas(d)
    local a = d.anio
    return {
        total = Poblacion.total(d),
        decenios = decenios,
        aptos = Poblacion.aptos(d),
        enFilas = enFilas,
        trabajan = math.max(0, Poblacion.enEdadDeTrabajar(d) - enFilas),
        ocupacion = ocupacion,
        frena = { vivienda = fVivienda < 1, hambre = c.hambre == true, sitiada = fAsedio < 1 },
        anio = {
            nacidos = a.nacidos,
            natural = a.natural,
            hambre = a.hambre,
            vejez = a.vejez,
            combate = a.combate,
            retirados = a.retirados,
        },
    }
end

--- Año del juego del día `dia` (F1, un solo calendario): 1 + floor((dia − 1) / anio).
function Poblacion.anioDelJuego(dia)
    return 1 + math.floor((dia - 1) / REGLAS.anio)
end

local publicas = {
    'diaDemografico',
    'reclutar',
    'volverACasa',
    'morirSoldados',
    'ciudadDeFuerza',
    'ajustarFilas',
    'demografiaCiudad',
    'morirTripulantes',
}

--- Cuelga de la clase Simulacion las reglas y funciones de la población.
function Poblacion.instalar(clase)
    Simulacion = clase
    clase.poblacion = REGLAS
    clase.Poblacion = Poblacion
    clase.anioDelJuego = Poblacion.anioDelJuego
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Poblacion[nombre]
    end
end

return Poblacion

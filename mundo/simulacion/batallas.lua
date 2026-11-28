--- Batallas de campo: bandos, un día simulado (F8 con munición), bajas y el resultado de la escena 3D.
--
-- Toda pelea es una batalla de campo, en un sitio (ciudad, campamento, base o
-- bandera), en una mina o en campo abierto (dos grupos que se cruzan):
--
--   e.batallas[id] = { id, lugar = { tipo = 'sitio' | 'mina' | 'campo', id },
--       x, y, inicio, dias, enEscena (nación que la juega en 3D, o nil),
--       escenaDesde, decision = { [nación] = 'sola' },
--       bandos = { atacante = { grupos = { gid, ... } },
--                  defensor = { grupos = { gid, ... }, sitio, nacionSitio } } }
--
-- Cada grupo apunta su batalla en `g.batalla`. La hostilidad sale de
-- `hostiles`. Nadie la ve: `diaBatalla` cada día. La ve un jugador: se
-- congela (`enEscena`) y la escena 3D la cierra con `resolverBatalla`.
--
-- Un día simulado (diseno/economia.md, 3.9, F6, F8, F11b): cada bando golpea
-- con lo sano de sus grupos (y el defensor, con la guarnición de su sitio),
-- cada tropa en proporción a la munición que tiene para ese día; la gasta
-- (los grupos, la suya; la guarnición, la del polvorín de su ciudad). Lo que
-- cae: de los soldados, `muertos` (0,4) mueren y el resto queda herido; cada
-- vehículo queda averiado con averías por zona y bajas en su tripulación
-- sacadas de lo que pasa en la batalla 3D (averias.lua, `Averias.simular`,
-- con un azar de la semilla, el día y la batalla). En la guarnición igual: sus
-- heridos y averiados van al taller de su ciudad. Nada se destruye. Los
-- tripulantes que mueren salen de la población de su ciudad
-- (`morirTripulantes`); los heridos van con las averías al taller.
--
-- CONTRATO DE LA ESCENA 3D (para batalla/ y main.lua) ---------------------------------------
--
-- Entrada: `sim:estadoBatalla(bid)` (consultas.lua) da por bando lo sano por
-- tipo (`sanos`), cada grupo con su munición (`grupos[k].municion = { balas,
-- misiles }`), la guarnición del sitio con la del polvorín de su
-- ciudad (`sitio.municion`), el total (`municion`) y el tamaño de escuadra
-- (`escuadra`, F10: soldados por figura). El gasto por disparo está en
-- `Simulacion.produccion.municion[tipo].porDisparo`.
--
-- Salida: `ejecutar({ tipo = 'resolverBatalla', batalla = bid, resultado =
-- { atacante = bando, defensor = bando }, retira, vida })`, con
--   bando = {
--     soldados = { muertos = n, heridos = n },
--     averiados = { lanzacohetes = { daño, ... },
--                   zonas = { lanzacohetes = { zonas, ... } } },
--       -- un daño de 0 a 1 (1 − vida / vidaMax) por cada vehículo que termina
--       -- averiado; los que terminan con toda la vida no se nombran. `zonas`
--       -- (opcional, en el mismo orden): { orugas, torreta, canon, motor =
--       -- true, estructura = 0 a 1, tripulacion = bajas, tripulacionMuertos }
--       -- (batalla/DANO-REAL.md §5.5). Lo que se repara y se paga sale de las
--       -- zonas; sin ellas, del azar de la batalla simulada.
--     tripulacion = { muertos, heridos },
--       -- opcional: las bajas de las tripulaciones del bando, si las zonas no
--       -- las traen vehículo a vehículo
--     municion = { [gid] = { balas, misiles }, sitio = { ... } },
--       -- munición gastada por cada grupo y por la guarnición (su polvorín)
--   }
--   `retira` ('atacante', 'defensor' o nil) y `vida` (la que pierde el
--   sitio, 0 a 100; sin ella, F3). Muertos y heridos se reparten entre los
--   grupos del bando (y la guarnición al final) en proporción a sus soldados
--   sanos; los averiados, igual, por tipo, en el orden de la lista. La
--   munición gastada se recorta a la que tenía cada uno.
--   Sigue valiendo el formato de antes (`caidos = { atacante = { soldados,
--   lanzacohetes }, defensor = {...} }`): los soldados caídos se
--   parten con F11b y los vehículos quedan averiados con daño 1.
-- Devuelve false si un bando pierde más de lo que tenía sano (la batalla
-- sigue simulada) o true y lo aplicado por bando: { muertos, heridos
-- (soldados), averiados = { lanzacohetes } (cuántos), dano = {
-- lanzacohetes } (trabajo de taller total, averias.lua), tripulacion
-- = { muertos, heridos }, municion = { balas, misiles } (gastada) }.
-- Si la batalla no termina, sigue simulada con lo que quede.
--
-- Módulo de `mundo/simulacion.lua`: `Batallas.instalar(Simulacion)` cuelga sus
-- funciones y `Simulacion.batalla` (las reglas) de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')
local Averias = require('mundo.simulacion.averias')
local Ruido = require('mundo.ruido')

local ordenadas = Ayudas.ordenadas
local tropasVacias = Ayudas.tropasVacias
local esCiudad = Ayudas.esCiudad
local anotar = Ayudas.anotar
local TROPAS = Ayudas.TROPAS
local LADOS = Ayudas.LADOS
local OTRO_LADO = Ayudas.OTRO_LADO
local nacionesBando = Ayudas.nacionesBando
local sanosBando = Ayudas.sanosBando
local prepararCombate = Ayudas.prepararCombate
local cargaDe = Ayudas.cargaDe

local Batallas = {}

-- Se fija en `instalar`: la clase.
local Simulacion

Batallas.reglas = {
    golpeMin = 0.06, -- F8: bajas = golpe × azar(golpeMin, golpeMax) × ventaja
    golpeMax = 0.12,
    diasEscenaMax = 3, -- una batalla congelada que nadie resuelve vuelve a F8 a estos días
}

local VEHICULOS = { 'lanzacohetes' }
local MUNICIONES = { 'balas', 'misiles' }

--- Vida de una tropa de `q` (un grupo, un sitio o sus tiradores): los
-- soldados, 1 cada uno; los vehículos, la de su modelo (armamento.lua; con
-- todo Scud-B, lanzacohetes 40).
local function vidaTropa(q, tropa)
    if tropa == 'soldados' then
        return (q.soldados or 0) * Simulacion.vidaCiudad.pesos.soldados
    end
    return Armamento.vidaDe(q, tropa)
end

--- Golpe de una tropa de `q` con toda su munición.
local function golpeTropa(q, tropa)
    if tropa == 'soldados' then
        return (q.soldados or 0) * Simulacion.vidaCiudad.pesos.soldados
    end
    return Armamento.golpeDe(q, tropa)
end

-- Bajas (F11b) ------------------------------------------------------------------------------------

--- De `caen` soldados que caen en `q` (un grupo o un sitio), mueren
-- round(caen × muertos), con el resto de redondeo guardado en `q.restoMuertos`.
-- Devuelve muertos y heridos.
local function partirSoldados(q, caen)
    if caen <= 0 then
        return 0, 0
    end
    local acumulado = (q.restoMuertos or 0) + caen * Simulacion.produccion.muertos
    local muertos = math.min(caen, math.floor(acumulado + 1e-9))
    local resto = acumulado - muertos
    q.restoMuertos = resto > 1e-9 and resto or nil
    return muertos, caen - muertos
end

--- Reparte `dano` (puntos de vida) entre las tropas sanas de `q` según la
-- vida de cada tipo, sin azar; lo que no llega a una unidad entera se guarda
-- para el día siguiente (`q.resto`). Cada tipo recibe la parte de su vida y
-- pierde esa parte dividida por la vida de una unidad: caen `dano × unidades
-- / vida total`, sea cual sea el modelo; los que caen se reparten entre sus
-- modelos en proporción (restos mayores, en orden de catálogo). Devuelve lo
-- que cae de cada tipo y, en `modelos`, de qué modelos.
local function caidasPorTipo(q, dano)
    local vida = 0
    for _, tropa in ipairs(TROPAS) do
        vida = vida + vidaTropa(q, tropa)
    end
    local caen = tropasVacias()
    caen.modelos = {}
    if vida <= 0 or dano <= 0 then
        return caen
    end
    dano = math.min(dano, vida)
    q.resto = q.resto or tropasVacias()
    for _, tropa in ipairs(TROPAS) do
        local tiene = q[tropa] or 0
        if tiene > 0 then
            q.resto[tropa] = q.resto[tropa] + dano * tiene / vida
            caen[tropa] = math.min(tiene, math.floor(q.resto[tropa] + 1e-9))
            q.resto[tropa] = q.resto[tropa] - caen[tropa]
            if tropa == 'soldados' then
                q[tropa] = tiene - caen[tropa]
            else
                caen.modelos[tropa] = Armamento.sacar(q, tropa, caen[tropa])
            end
        end
    end
    return caen
end

--- Azar de las averías de la batalla simulada: el de la batalla `b` hoy o,
-- sin batalla, el de la fuerza `q` (por su sitio en el mapa) hoy, con `sal`.
function Batallas:azarAverias(b, q, sal)
    local e = self.estado
    if b then
        return Ruido.azar(Ruido.hash(e.semilla, e.dia, b.id, 97))
    end
    return Ruido.azar(Ruido.hash(e.semilla, e.dia * 8 + sal, math.floor(q.x or 0), math.floor(q.y or 0)))
end

--- Los vehículos que caen en la batalla simulada (`caen[tipo]` de los modelos
-- `caen.modelos[tipo]`), con sus averías por zona y las bajas de sus
-- tripulaciones (`Averias.simular`), anotados en `averias`. Devuelve los
-- tripulantes muertos y heridos.
local function averiarCaidos(caen, averias, azar)
    local muertos, heridos = 0, 0
    for _, tipo in ipairs(VEHICULOS) do
        for _, modelo in ipairs(Armamento.lista(caen.modelos[tipo], tipo, caen[tipo] or 0)) do
            local codigo, bajas, mueren = Averias.simular(azar, tipo, Armamento.tripulacion(modelo))
            Simulacion.anotarAveria(averias, tipo, codigo, modelo)
            muertos = muertos + mueren
            heridos = heridos + bajas - mueren
        end
    end
    return muertos, heridos
end

--- Munición de una rampa llena del lanzacohetes `modelo` (el Scud-B, 4
-- misiles; el BM-21 y el HIMARS, una salva), como la carga la escena 3D.
local function cargaRampa(modelo)
    local escena = Simulacion.fichaModelo(modelo).escena
    return escena.carga * escena.porDisparo
end

--- Los lanzacohetes de `q` que caen hoy (`caen`, ya sacados de `q`) pierden
-- lo que llevaban cargado en la rampa: explota con ellos y cuenta como
-- gastado (decisión del dueño, 2026-10-02, la misma regla que la escena 3D,
-- `Tropas.perderCarga`). Lo cargado del bando es su munición de misiles
-- (`municion`, la del grupo o la del polvorín de la guarnición) hasta llenar
-- las rampas de todos sus lanzacohetes de antes del golpe; los caídos
-- pierden su parte, por la carga de su modelo. Devuelve los misiles perdidos.
function Batallas:perderRampas(q, caen, municion)
    local n = caen.lanzacohetes or 0
    if n <= 0 or not municion or (municion.misiles or 0) <= 0 then
        return 0
    end
    local caidos = 0
    for _, m in ipairs(Armamento.lista(caen.modelos.lanzacohetes, 'lanzacohetes', n)) do
        caidos = caidos + cargaRampa(m)
    end
    local todas = caidos
    local quedan = q.lanzacohetes or 0
    for _, m in ipairs(Armamento.lista(Armamento.porModelo(q, 'lanzacohetes'), 'lanzacohetes', quedan)) do
        todas = todas + cargaRampa(m)
    end
    if todas <= 0 then
        return 0
    end
    local cargado = math.min(municion.misiles, todas)
    local pierde = math.min(municion.misiles, math.floor(cargado * caidos / todas + 1e-9))
    if pierde <= 0 then
        return 0
    end
    municion.misiles = municion.misiles - pierde
    self:anotarGasto({ balas = 0, misiles = pierde })
    self:medir('misilesRampaPerdidos', pierde)
    return pierde
end

--- Daño a un grupo: sus soldados que caen mueren o quedan heridos (F11b) y
-- sus vehículos quedan averiados por zonas, y viajan con él con sus
-- tripulantes heridos. `azar`: el de las averías (sin él, `azarAverias`).
function Batallas:herirGrupo(g, dano, azar)
    local caen = caidasPorTipo(g, dano)
    local muertos, heridos = partirSoldados(g, caen.soldados)
    g.heridos = g.heridos or tropasVacias()
    g.heridos.soldados = g.heridos.soldados + heridos
    if caen.lanzacohetes > 0 then
        self:perderRampas(g, caen, g.municion)
        g.averias = g.averias or Simulacion.averiasVacias()
        local antes = { lanzacohetes = #g.averias.lanzacohetes }
        local tripMuertos, tripHeridos = averiarCaidos(caen, g.averias, azar or self:azarAverias(nil, g, 1))
        for _, tipo in ipairs(VEHICULOS) do
            g.heridos[tipo] = g.heridos[tipo] + #g.averias[tipo] - antes[tipo]
        end
        Simulacion.herirTripulantes(g, tripHeridos)
        self:morirTripulantes(g.nacion, self:ciudadDeGrupo(g), tripMuertos)
    end
    self:morirSoldados(g.nacion, self:ciudadDeGrupo(g), muertos)
end

--- Daño a la guarnición de un sitio: igual que a un grupo, pero sus heridos
-- y averiados van al taller de su ciudad.
function Batallas:herirSitio(s, dano, azar)
    local caen = caidasPorTipo(s, dano)
    local muertos, heridos = partirSoldados(s, caen.soldados)
    local averias = Simulacion.averiasVacias()
    local c = self:ciudadDeSitio(s.nacion, s)
    if caen.lanzacohetes > 0 then
        self:perderRampas(s, caen, self:polvorinDe(s))
        local tripMuertos, tripHeridos = averiarCaidos(caen, averias, azar or self:azarAverias(nil, s, 2))
        averias.tripulantes = tripHeridos > 0 and tripHeridos or nil
        self:morirTripulantes(s.nacion, c, tripMuertos)
    end
    if c then
        self:sumarCola(c, heridos, averias)
    end
    self:morirSoldados(s.nacion, c, muertos)
end

-- Bandos -------------------------------------------------------------------------------------------

--- Mete a `g` en el bando `lado` de la batalla `b`.
function Batallas:unirBatalla(b, g, lado)
    prepararCombate(self, g)
    g.batalla = b.id
    local grupos = b.bandos[lado].grupos
    grupos[#grupos + 1] = g.id
    table.sort(grupos)
end

--- Empieza una batalla en `lugar` ({ tipo, id }) entre los grupos
-- `atacantes` y `defensores` (y el sitio `sitioId`, que defiende con su
-- guarnición). Devuelve la batalla.
function Batallas:crearBatalla(lugar, x, y, atacantes, defensores, sitioId)
    local e = self.estado
    local id = e.siguienteBatalla
    e.siguienteBatalla = id + 1
    local sitio = sitioId and self:sitio(sitioId)
    local b = {
        id = id,
        lugar = lugar,
        x = x,
        y = y,
        inicio = e.dia,
        dias = 0,
        bandos = {
            atacante = { grupos = {} },
            defensor = { grupos = {}, sitio = sitio and sitio.id, nacionSitio = sitio and sitio.nacion },
        },
    }
    e.batallas[id] = b
    for _, g in ipairs(atacantes) do
        self:unirBatalla(b, g, 'atacante')
    end
    for _, g in ipairs(defensores or {}) do
        self:unirBatalla(b, g, 'defensor')
    end
    return b
end

--- Grupos de un bando que siguen en la batalla, en orden de id (la lista se
-- limpia de los que ya no están).
function Batallas:gruposBando(b, lado)
    local e = self.estado
    local bando = b.bandos[lado]
    local out, ids = {}, {}
    for _, gid in ipairs(bando.grupos) do
        local g = e.grupos[gid]
        if g and g.batalla == b.id then
            out[#out + 1] = g
            ids[#ids + 1] = gid
        end
    end
    bando.grupos = ids
    return out
end

--- Sitio que defiende el bando defensor, si sigue en pie y es de la misma
-- nación que al empezar; nil si no. Solo los guardados: una bandera atacada
-- está guardada, y si cae, cae (aunque su bloque siga teniendo bandera).
function Batallas:sitioBando(b)
    local d = b.bandos.defensor
    local e = self.estado
    local s = d.sitio and (e.ciudades[d.sitio] or e.instalaciones[d.sitio])
    if s and s.nacion == d.nacionSitio then
        return s
    end
    return nil
end

--- Bando en el que pelea `nid` en la batalla `b` ('atacante', 'defensor') o nil.
function Batallas:ladoDe(b, nid)
    for _, lado in ipairs(LADOS) do
        if nacionesBando(self, b, lado)[nid] then
            return lado
        end
    end
    return nil
end

--- Batalla abierta en un lugar ('sitio', 'mina') con ese id, o nil.
function Batallas:batallaEn(tipo, id)
    local e = self.estado
    for _, bid in ipairs(ordenadas(e.batallas)) do
        local b = e.batallas[bid]
        if b.lugar.tipo == tipo and b.lugar.id == id then
            return b
        end
    end
    return nil
end

--- ¿Tiene algo sano el sitio para seguir defendiendo? Una ciudad, mientras le
-- queden soldados (la vida a 0 no la vence: 3.9); una instalación o una
-- bandera, mientras siga en pie.
local function sitioEnPie(s)
    if esCiudad(s) then
        return s.soldados > 0
    end
    return (s.salud or 0) > 0
end

--- Tropas de la guarnición de `s` que disparan: en una ciudad en ruinas (vida
-- 0) o en una instalación, sus lanzacohetes no.
local function tiradoresSitio(s)
    local lanzan = esCiudad(s) and (s.vida or Simulacion.vidaCiudad.maxima) > 0
    local lanzacohetes = lanzan and (s.lanzacohetes or 0) or 0
    return {
        soldados = s.soldados or 0,
        lanzacohetes = lanzacohetes,
        lanzacohetesPor = lanzan and s.lanzacohetesPor or nil,
    }
end

--- Golpe de la guarnición de un sitio (F8) con la parte de cada tropa que
-- tiene munición (`partes`; sin ella, todas): soldados y lanzacohetes; con vida > 0 también las baterías (una ciudad a 0 está en
-- ruinas y sus defensas fijas no golpean). Una instalación, con su
-- fortificación.
local function golpeSitio(s, partes)
    partes = partes or { soldados = 1, lanzacohetes = 1 }
    if s.tipo == 'bandera' then
        return 0
    end
    local t = tiradoresSitio(s)
    local golpe = golpeTropa(t, 'soldados') * partes.soldados
    if esCiudad(s) then
        golpe = golpe + golpeTropa(t, 'lanzacohetes') * partes.lanzacohetes
        if (s.vida or Simulacion.vidaCiudad.maxima) > 0 then
            golpe = golpe + (s.baterias or 0) * Simulacion.vidaCiudad.pesos.baterias
        end
        return golpe
    end
    return golpe * (1 + (s.fortificacion or 0))
end
Batallas.golpeSitio = golpeSitio

--- Golpe de un grupo con la parte de cada tropa que tiene munición.
local function golpeGrupo(g, partes)
    local golpe = 0
    for _, tropa in ipairs(TROPAS) do
        golpe = golpe + golpeTropa(g, tropa) * (partes and partes[tropa] or 1)
    end
    return golpe
end

--- Vida del sitio para repartir las bajas (D en F3): lo que aguanta.
local function aguanteSitio(s)
    local pesosCiudad = Simulacion.vidaCiudad.pesos
    return (s.soldados or 0) * pesosCiudad.soldados
        + Armamento.vidaDe(s, 'lanzacohetes')
        + (s.baterias or 0) * pesosCiudad.baterias
end

--- Vida (sobre 100) que pierde un sitio en un día de batalla (F3):
-- 100 × G / (G + D), con G las bajas que le causa el atacante.
local function vidaPerdida(bajasSuyas, aguante)
    if bajasSuyas + aguante <= 0 then
        return 0
    end
    return 100 * bajasSuyas / (bajasSuyas + aguante)
end

--- ¿Se retira un grupo tras el combate? Si su vida baja de su umbral o si el
-- peor día del enemigo (`preventiva` de su fuerza, `suya`) acabaría con él. Con
-- umbral 0 lucha hasta el final.
local function debeRetirarse(g, suya)
    local umbral = g.umbral or 0
    if umbral <= 0 then
        return false
    end
    local vida = Simulacion.vidaGrupo(g)
    return vida < umbral * (g.vidaMax or vida) or vida <= math.floor(suya * Simulacion.recuperacion.preventiva)
end

--- Ventaja de un bando (F8): +`ventajaDefensa` si pelea en la tierra de la
-- nación que lo encabeza (la del sitio o la de su primer grupo) y, si
-- defiende una ciudad, × el efecto de su vida (F6).
function Batallas:ventajaBando(b, lado)
    local s = lado == 'defensor' and self:sitioBando(b)
    local nid = s and s.nacion
    if not nid then
        local primero = self:gruposBando(b, lado)[1]
        nid = primero and primero.nacion
    end
    local ventaja = 1
    local dueno = self:dueno(b.x, b.y)
    if nid and dueno and dueno.id == nid then
        ventaja = ventaja + Simulacion.choque.ventajaDefensa
    end
    if s and esCiudad(s) then
        ventaja = ventaja * Simulacion.efectoVida(s.vida or Simulacion.vidaCiudad.maxima)
    end
    return ventaja
end

--- Nombre de una batalla para las noticias.
function Batallas:nombreBatalla(b)
    local e = self.estado
    if b.lugar.tipo == 'sitio' then
        local s = self:sitio(b.lugar.id)
        return s and Simulacion.nombreBlanco(self, s) or 'un sitio arrasado'
    elseif b.lugar.tipo == 'mina' then
        local d = e.depositos[b.lugar.id]
        local recurso = d and Simulacion.recursos[d.tipo]
        return recurso and (recurso.articulo .. ' ' .. recurso.nombre) or 'una mina'
    end
    return 'campo abierto cerca de ' .. self:lugarCercano(b.x, b.y)
end

--- La carga de `g`, que pierde una batalla, pasa al bando `lado`: cada grupo
-- sano se lleva lo que le quepa (en orden de id) y, en una mina, el resto
-- vuelve a ella (decisión 2 del dueño). En campo abierto el resto se pierde.
function Batallas:repartirCarga(b, g, lado)
    local carga = cargaDe(g)
    if carga <= 0 then
        return
    end
    g.carga = 0
    for _, o in ipairs(self:gruposBando(b, lado)) do
        local suya = cargaDe(o)
        if carga > 0 and Simulacion.vidaGrupo(o) > 0 and (suya <= 0 or o.tipoCarga == g.tipoCarga) then
            local toma = math.min(carga, math.max(0, Simulacion.capacidad(o) - suya))
            if toma > 0 then
                o.carga = suya + toma
                o.tipoCarga = g.tipoCarga
                carga = carga - toma
            end
        end
    end
    local d = b.lugar.tipo == 'mina' and self.estado.depositos[b.lugar.id]
    if carga > 0 and d then
        self:devolverAMina(d, carga)
    end
end

--- Un grupo cae en la batalla (nada sano): su carga va al otro bando, su
-- munición se pierde y sus vehículos, averiados, vuelven remolcados al
-- taller de su ciudad de origen (3.8.5) con sus soldados y sus tripulantes
-- heridos, que entran en la cola de heridos de esa ciudad (decisión de
-- El dueño del 2026-10-01; antes los soldados heridos morían).
function Batallas:caerEnBatalla(b, g, ganador, azar)
    local e = self.estado
    self:repartirCarga(b, g, ganador)
    anotar(self, g, 'derrotas')
    local heridos = g.heridos or tropasVacias()
    local averias = Simulacion.averiasDe(heridos, g.averias)
    for _, tipo in ipairs(VEHICULOS) do
        local sanos = g[tipo] or 0
        if sanos > 0 then
            azar = azar or self:azarAverias(b, g, 3)
            for _, modelo in ipairs(Armamento.lista(Armamento.porModelo(g, tipo), tipo, sanos)) do
                local codigo = Averias.simular(azar, tipo, Armamento.tripulacion(modelo))
                Simulacion.anotarAveria(averias, tipo, codigo, modelo)
            end
        end
    end
    -- Sin ciudad a la que volver (la nación ya no tiene), los heridos mueren.
    local ciudad = self:ciudadTaller(g)
    local vuelven = ciudad and heridos.soldados or 0
    self:morirSoldados(g.nacion, self:ciudadDeGrupo(g), heridos.soldados - vuelven + (g.soldados or 0))
    self:medir('heridosRemolcados', vuelven)
    self:perderMunicion(g)
    e.grupos[g.id] = nil
    self:remolcar(g.nacion, g.x, g.y, ciudad, {
        soldados = vuelven,
        lanzacohetes = #averias.lanzacohetes,
    }, averias)
    if g.lider then
        self:noticia(
            string.format('El ejército de %s cae en %s', self:nombreNacionDe(g), self:nombreBatalla(b)),
            { 1, 0.45, 0.35 }
        )
        self:hecho('derrota', g.nacion)
    end
end

--- Un grupo se retira de la batalla: pierde la carga (va al otro bando) y
-- vuelve a casa con los vivos, los heridos y su munición.
function Batallas:retirarDeBatalla(b, g, ganador)
    self:repartirCarga(b, g, ganador)
    g.batalla = nil
    self:retirar(g, self:nombreBatalla(b))
end

--- Suelta de la batalla a los grupos que ya no tienen contra quién pelear
-- (se firmó la paz o un alto el fuego): siguen con lo suyo.
function Batallas:limpiarBatalla(b)
    for _, lado in ipairs(LADOS) do
        local otras = nacionesBando(self, b, OTRO_LADO[lado])
        for _, g in ipairs(self:gruposBando(b, lado)) do
            local contra = false
            for _, nid in ipairs(ordenadas(otras)) do
                if self:hostiles(g.nacion, nid) then
                    contra = true
                    break
                end
            end
            if not contra then
                g.batalla = nil
            end
        end
    end
end

--- Un día de daño a un sitio que defiende: una ciudad pierde tropas (F11b,
-- al taller los heridos y averiados) y vida (F3); una instalación, tropas y
-- salud (a 0, o sin guarnición, se destruye); una bandera, solo salud (F7), y
-- solo si no la defiende ningún grupo (su guarnición: banderas.lua).
function Batallas:danarSitio(b, s, bajas, atacante, conGrupos, azar)
    local e = self.estado
    local aguante = aguanteSitio(s)
    if esCiudad(s) then
        s.asediadaDia = e.dia
        self:herirSitio(s, bajas, azar)
        s.vida = math.max(0, (s.vida or Simulacion.vidaCiudad.maxima) - vidaPerdida(bajas, aguante))
        self:sumarCansancio(s.nacion, bajas * 0.01)
        return
    end
    s.atacadaDia = e.dia
    if s.tipo == 'bandera' then
        if conGrupos then
            return
        end
        local reglas = Simulacion.bandera
        local perdida = math.min(100, bajas * 100 / reglas.aguante) * (s.progreso < 1 and 1.5 or 1)
        local empieza = (s.atacadaPor == nil) or (b.dias <= 1)
        s.atacadaPor = atacante
        s.salud = math.max(0, s.salud - perdida)
        if s.salud <= 0 then
            self:destruirInstalacion(s, atacante)
        elseif empieza and perdida > 0 then
            self:noticia(
                string.format(
                    '%s ataca una bandera de %s en (%d, %d): cae en %d días',
                    e.naciones[atacante].nombre,
                    e.naciones[s.nacion].nombre,
                    math.floor(s.x),
                    math.floor(s.y),
                    math.ceil(s.salud / perdida)
                ),
                { 1, 0.6, 0.35 }
            )
            self:hecho('asedio', atacante, s.nacion)
        end
        return
    end
    self:herirSitio(s, bajas, azar)
    -- La vida sobre 100 se lleva a la escala de cada tipo (campamento 30, base 180).
    local escala = Simulacion.saludMaxima[s.tipo] / 100 * (s.progreso < 1 and 1.5 or 1)
    s.salud = math.max(0, s.salud - vidaPerdida(bajas, aguante) * escala)
    self:sumarCansancio(s.nacion, bajas * 0.01)
    if s.salud <= 0 or (s.soldados <= 0 and not conGrupos) then
        self:destruirInstalacion(s, atacante)
    end
end

--- Golpe de un bando hoy con su munición (F6), y la gasta: la de cada grupo
-- y, en el defensor, la del polvorín de la ciudad del sitio.
function Batallas:golpeConMunicion(grupos, sitio)
    local golpe, lleno = 0, 0
    for _, g in ipairs(grupos) do
        local partes = Simulacion.partesMunicion(g, g.municion)
        golpe = golpe + golpeGrupo(g, partes)
        lleno = lleno + golpeGrupo(g, nil)
        local gastado = Simulacion.gastarMunicionDia(g, g.municion)
        self:anotarGasto(gastado)
    end
    if sitio then
        local polvorin = self:polvorinDe(sitio)
        local tiradores = tiradoresSitio(sitio)
        golpe = golpe + golpeSitio(sitio, Simulacion.partesMunicion(tiradores, polvorin))
        lleno = lleno + golpeSitio(sitio, nil)
        self:anotarGasto(Simulacion.gastarMunicionDia(tiradores, polvorin))
    end
    self:medir('bandoDias', 1)
    if lleno > 0 then
        self:medir('golpePerdido', 1 - golpe / lleno)
    end
    return golpe
end

--- Anota en las medidas la munición gastada.
function Batallas:anotarGasto(gastado)
    for _, tipo in ipairs(MUNICIONES) do
        self:medir('municionGastada|' .. tipo, gastado[tipo])
    end
end

--- Un día de batalla sin ver (F8, con munición): cada bando golpea con la
-- munición que tiene; las bajas al otro bando se reparten en proporción a la
-- vida de cada uno (el sitio cuenta como un grupo más); después cae quien se
-- quede sin nada sano y se retira quien deba.
function Batallas:diaBatalla(b, azar)
    local reglas = Simulacion.batalla
    b.dias = b.dias + 1
    local grupos = { atacante = self:gruposBando(b, 'atacante'), defensor = self:gruposBando(b, 'defensor') }
    local sitio = self:sitioBando(b)
    local golpe = {
        atacante = self:golpeConMunicion(grupos.atacante, nil),
        defensor = self:golpeConMunicion(grupos.defensor, sitio),
    }
    local bajas = {}
    bajas.defensor =
        math.floor(golpe.atacante * azar(reglas.golpeMin, reglas.golpeMax) * self:ventajaBando(b, 'atacante'))
    bajas.atacante =
        math.floor(golpe.defensor * azar(reglas.golpeMin, reglas.golpeMax) * self:ventajaBando(b, 'defensor'))
    local primero = grupos.atacante[1]
    local azarAverias = self:azarAverias(b)
    for _, lado in ipairs(LADOS) do
        local vidas, total = {}, 0
        for k, g in ipairs(grupos[lado]) do
            vidas[k] = Simulacion.vidaGrupo(g)
            total = total + vidas[k]
        end
        local aguante = 0
        if lado == 'defensor' and sitio then
            aguante = aguanteSitio(sitio)
            total = total + aguante
        end
        if total > 0 then
            for k, g in ipairs(grupos[lado]) do
                self:herirGrupo(g, bajas[lado] * vidas[k] / total, azarAverias)
            end
        end
        if lado == 'defensor' and sitio and primero then
            local parte = total > 0 and math.floor(bajas.defensor * aguante / total + 1e-9) or bajas.defensor
            self:danarSitio(b, sitio, parte, primero.nacion, #grupos.defensor > 0, azarAverias)
        end
        self:sumarCansancio((grupos[lado][1] or {}).nacion, bajas[lado] * 0.01)
    end
    -- Lo que golpea cada bando tras el golpe (para la retirada preventiva).
    sitio = self:sitioBando(b)
    local queda = { atacante = 0, defensor = sitio and golpeSitio(sitio) or 0 }
    for _, lado in ipairs(LADOS) do
        for _, g in ipairs(grupos[lado]) do
            queda[lado] = queda[lado] + golpeGrupo(g, nil)
        end
    end
    for _, lado in ipairs(LADOS) do
        local otro = OTRO_LADO[lado]
        for _, g in ipairs(grupos[lado]) do
            if Simulacion.vidaGrupo(g) <= 0 then
                self:caerEnBatalla(b, g, otro, azarAverias)
            elseif debeRetirarse(g, queda[otro]) then
                self:retirarDeBatalla(b, g, otro)
            elseif cargaDe(g) > Simulacion.capacidad(g) then
                -- Con bajas carga menos: lo que no cabe se pierde.
                g.carga = Simulacion.capacidad(g)
            end
        end
    end
end

--- Termina la batalla si un bando no tiene nada sano o se ha ido entero.
-- Devuelve true si terminó.
function Batallas:terminarSiToca(b)
    local atacan = #self:gruposBando(b, 'atacante') > 0
    local sitio = self:sitioBando(b)
    local defienden = #self:gruposBando(b, 'defensor') > 0 or (sitio ~= nil and sitioEnPie(sitio))
    if atacan and defienden then
        return false
    end
    local ganador
    if atacan then
        ganador = 'atacante'
    elseif defienden or sitio then
        ganador = 'defensor'
    end
    self:cerrarBatalla(b, ganador)
    return true
end

--- Cierra la batalla con su ganador ('atacante', 'defensor' o nil si no
-- queda nadie). En un sitio, si gana el atacante: una ciudad queda a
-- `derrota` de vida y la saquean (3.9); una instalación ya cayó. En una mina,
-- los recolectores que ganan siguen recolectando y los atacantes que ganan
-- vuelven con el botín. En campo abierto, cada uno sigue con lo suyo.
function Batallas:cerrarBatalla(b, ganador)
    local e = self.estado
    -- Los que quedan pueden seguir su camino (ver `moverPaso`).
    self.cambiosMarcha = (self.cambiosMarcha or 0) + 1
    e.batallas[b.id] = nil
    local sitio = self:sitioBando(b)
    local ganadores = ganador and self:gruposBando(b, ganador) or {}
    for _, lado in ipairs(LADOS) do
        for _, g in ipairs(self:gruposBando(b, lado)) do
            g.batalla = nil
        end
    end
    for _, g in ipairs(ganadores) do
        if b.lugar.tipo ~= 'campo' or g.mision == 'atacar' then
            anotar(self, g, 'victorias')
        end
    end
    if b.lugar.tipo == 'sitio' and ganador == 'atacante' and sitio and esCiudad(sitio) then
        self:saquearCapital(sitio, ganadores[1])
    elseif b.lugar.tipo == 'sitio' and ganador == 'defensor' and sitio and esCiudad(sitio) then
        local atacante = b.atacante
        self:noticia(
            string.format('%s resiste el asalto%s', sitio.nombre, atacante and (' de ' .. atacante) or ''),
            { 1, 0.75, 0.5 }
        )
        local asaltante = self:gruposBando(b, 'atacante')[1]
        if asaltante then
            self:hecho('resiste', sitio.nacion, asaltante.nacion)
        end
    end
    for _, g in ipairs(ganadores) do
        if e.grupos[g.id] == g then
            local sigue = b.lugar.tipo == 'campo' and g.mision ~= 'apoyo'
            local mina = b.lugar.tipo == 'mina' and g.mision == 'recolectar'
            -- La guarnición que gana se queda en su bandera (o sigue hacia ella).
            local guardia = g.mision == 'guarnicion'
            if not (sigue or mina or guardia) and g.mision ~= 'regreso' then
                self:volver(g)
            end
        end
    end
end

--- Pelea las batallas del día, en orden de id: las congeladas (un jugador
-- dentro de la escena 3D) esperan a `resolverBatalla`, hasta `diasEscenaMax`.
function Batallas:resolverBatallas(azar)
    local e = self.estado
    for _, id in ipairs(ordenadas(e.batallas)) do
        local b = e.batallas[id]
        if b and b.enEscena and e.dia - (b.escenaDesde or e.dia) >= Simulacion.batalla.diasEscenaMax then
            b.enEscena, b.escenaDesde = nil, nil
        end
        if b and not b.enEscena then
            self:limpiarBatalla(b)
            if not self:terminarSiToca(b) then
                self:diaBatalla(b, azar)
                self:terminarSiToca(b)
            end
        end
    end
end

--- La nación `nid`, que pelea en la batalla, la juega en 3D: la simulación la
-- congela hasta que llegue `resolverBatalla`. Devuelve su estado
-- (`estadoBatalla`) o false.
function Batallas:entrarBatalla(nid, bid)
    local b = self.estado.batallas[bid]
    if not b or not self:ladoDe(b, nid) or (b.enEscena and b.enEscena ~= nid) then
        return false
    end
    b.enEscena = nid
    b.escenaDesde = self.estado.dia
    return self:estadoBatalla(bid)
end

--- La nación `nid` no defiende en 3D: la batalla sigue sola con F8. Solo se
-- apunta, para que la vista no vuelva a preguntar.
function Batallas:noDefender(nid, bid)
    local b = self.estado.batallas[bid]
    if not b or not self:ladoDe(b, nid) then
        return false
    end
    b.decision = b.decision or {}
    b.decision[nid] = 'sola'
    return true
end

-- Resultado de la escena 3D (ver el contrato en la cabecera) ---------------------------------------

--- Reparte `total` entre `capacidades` (lista de números) en proporción, sin
-- pasar de cada una; el sobrante de redondeo, al primero que aún tenga sitio.
local function repartir(capacidades, total)
    local suma = 0
    for _, c in ipairs(capacidades) do
        suma = suma + c
    end
    local partes, quedan = {}, total
    for k, c in ipairs(capacidades) do
        partes[k] = suma > 0 and math.floor(total * c / suma) or 0
        quedan = quedan - partes[k]
    end
    for k, c in ipairs(capacidades) do
        local extra = math.max(0, math.min(quedan, c - partes[k]))
        partes[k] = partes[k] + extra
        quedan = quedan - extra
    end
    return partes
end

--- El formato de antes (`caidos` por tipo) en el de ahora: soldados con F11b
-- y vehículos averiados con daño 1.
local function resultadoDeCaidos(caidos)
    local out = {}
    for _, lado in ipairs(LADOS) do
        local c = caidos and caidos[lado] or {}
        local soldados = tonumber(c.soldados) or 0
        local muertos = math.floor(soldados * Simulacion.produccion.muertos + 0.5)
        local r = {
            soldados = { muertos = muertos, heridos = soldados - muertos },
            averiados = { lanzacohetes = {} },
        }
        for _, tipo in ipairs(VEHICULOS) do
            for k = 1, tonumber(c[tipo]) or 0 do
                r.averiados[tipo][k] = 1
            end
        end
        out[lado] = r
    end
    return out
end

local function entero(n)
    return type(n) == 'number' and n >= 0 and n == math.floor(n)
end

--- ¿Cabe el resultado de un bando en lo que tenía sano?
local function resultadoValido(r, sanos)
    local s = r.soldados or {}
    local muertos, heridos = s.muertos or 0, s.heridos or 0
    if not (entero(muertos) and entero(heridos)) or muertos + heridos > sanos.soldados then
        return false
    end
    for _, tipo in ipairs(VEHICULOS) do
        local lista = r.averiados and r.averiados[tipo] or {}
        if type(lista) ~= 'table' or #lista > sanos[tipo] then
            return false
        end
        for _, d in ipairs(lista) do
            if type(d) ~= 'number' or d <= 0 then
                return false
            end
        end
    end
    return true
end

--- Código de averías y bajas de tripulación (bajas, muertos) del vehículo de
-- `tipo` y `modelo` con las zonas `z` de la escena (una tabla) o, sin ellas,
-- del azar de la batalla simulada. Con las zonas, si no dicen cuántos
-- tripulantes murieron, cada baja muere con `muerteTripulante`.
local function averiaDeEscena(z, tipo, modelo, azar)
    if type(z) ~= 'table' then
        local codigo, bajas, muertos = Averias.simular(azar, tipo, Armamento.tripulacion(modelo))
        return codigo, bajas, muertos
    end
    local bajas = math.max(0, math.floor(tonumber(z.tripulacion) or 0))
    local muertos = tonumber(z.tripulacionMuertos)
    if muertos then
        muertos = math.max(0, math.min(bajas, math.floor(muertos)))
    else
        muertos = 0
        for _ = 1, bajas do
            if azar() < Averias.reglas.muerteTripulante then
                muertos = muertos + 1
            end
        end
    end
    return Averias.codificar(z), bajas, muertos
end

--- Saca de los `quienes` de un bando los `cuantos` averiados de `tipo` de la
-- escena, cada uno de su modelo (`modelos[tipo][k]`, `averiados.modelos`):
-- los de un modelo se reparten entre quienes tienen ese modelo sano, en
-- proporción a cuántos tiene cada uno. Lo que no se pueda emparejar (sin
-- modelo, o con más de los que hay de él) sale en proporción a los sanos que
-- queden, de cualquier modelo. Devuelve por cada uno de `quienes` su lista de
-- { índice de la avería, modelo }, en orden de índice.
local function repartirPorModelo(quienes, tipo, cuantos, modelos)
    local lista = type(modelos) == 'table' and type(modelos[tipo]) == 'table' and modelos[tipo] or {}
    local out, libres = {}, {}
    for k = 1, #quienes do
        out[k] = {}
    end
    -- Índices de cada modelo, en orden de catálogo.
    local deModelo = {}
    for indice = 1, cuantos do
        local m = lista[indice]
        if type(m) == 'string' and Armamento.tipoDe(m) == tipo then
            deModelo[m] = deModelo[m] or {}
            table.insert(deModelo[m], indice)
        else
            libres[#libres + 1] = indice
        end
    end
    for _, m in ipairs(Armamento.modelos(tipo)) do
        local indices = deModelo[m]
        if indices then
            local capacidades = {}
            for k, q in ipairs(quienes) do
                capacidades[k] = Armamento.porModelo(q, tipo)[m] or 0
            end
            local partes = repartir(capacidades, #indices)
            local siguiente = 1
            for k, q in ipairs(quienes) do
                Armamento.sacar(q, tipo, partes[k], { [m] = partes[k] })
                for _ = 1, partes[k] do
                    table.insert(out[k], { indices[siguiente], m })
                    siguiente = siguiente + 1
                end
            end
            for j = siguiente, #indices do
                libres[#libres + 1] = indices[j]
            end
        end
    end
    -- Sin pareja: en proporción a los sanos que quedan.
    table.sort(libres)
    if #libres > 0 then
        local capacidades = {}
        for k, q in ipairs(quienes) do
            capacidades[k] = q[tipo] or 0
        end
        local partes = repartir(capacidades, #libres)
        local siguiente = 1
        for k, q in ipairs(quienes) do
            local sacados = Armamento.lista(Armamento.sacar(q, tipo, partes[k]), tipo, partes[k])
            for j = 1, partes[k] do
                table.insert(out[k], { libres[siguiente], sacados[j] })
                siguiente = siguiente + 1
            end
        end
    end
    for k = 1, #quienes do
        table.sort(out[k], function(a, b)
            return a[1] < b[1]
        end)
    end
    return out
end

--- Aplica a los `quienes` de un bando (sus grupos y, al final, el sitio) el
-- resultado `r` de la escena, con el azar `azar` para lo que la escena no
-- diga (zonas y tripulación). Devuelve lo aplicado.
function Batallas:aplicarResultado(quienes, sitio, r, azar)
    azar = azar or Ruido.azar(Ruido.hash(self.estado.semilla, self.estado.dia, 0, 96))
    local aplicado = {
        muertos = 0,
        heridos = 0,
        averiados = { lanzacohetes = 0 },
        dano = { lanzacohetes = 0 },
        tripulacion = { muertos = 0, heridos = 0 },
        municion = Simulacion.municionVacia(),
    }
    -- Munición gastada, antes de quitar a nadie: la de cada grupo y la del polvorín del sitio.
    local gasto = r.municion or {}
    for _, q in ipairs(quienes) do
        local pide = q == sitio and gasto.sitio or gasto[q.id]
        local m = q == sitio and self:polvorinDe(q) or q.municion
        if type(pide) == 'table' and m then
            for _, tipo in ipairs(MUNICIONES) do
                local gasta = math.max(0, math.min(m[tipo] or 0, math.floor(tonumber(pide[tipo]) or 0)))
                m[tipo] = m[tipo] - gasta
                aplicado.municion[tipo] = aplicado.municion[tipo] + gasta
            end
        end
    end
    self:anotarGasto(aplicado.municion)
    -- Soldados: los caídos, en proporción a los sanos de cada uno; de ellos, los muertos.
    local s = r.soldados or {}
    local muertos, heridos = s.muertos or 0, s.heridos or 0
    local capacidades = {}
    for k, q in ipairs(quienes) do
        capacidades[k] = q.soldados or 0
    end
    local caen = repartir(capacidades, muertos + heridos)
    local mueren = repartir(caen, muertos)
    local averias = {}
    for k, q in ipairs(quienes) do
        q.soldados = (q.soldados or 0) - caen[k]
        averias[k] = Simulacion.averiasVacias()
        averias[k].soldados = caen[k] - mueren[k]
    end
    aplicado.muertos, aplicado.heridos = muertos, heridos
    for k, q in ipairs(quienes) do
        self:morirSoldados(q.nacion, self:ciudadDeFuerza(q), mueren[k])
    end
    -- Vehículos: por tipo, cada avería a un vehículo de su modelo
    -- (`repartirPorModelo`), con sus zonas (sin zonas, las de la batalla
    -- simulada) y sus bajas de tripulación.
    local zonas = r.averiados and r.averiados.zonas
    local totales = type(zonas) ~= 'table' and type(r.tripulacion) == 'table' and r.tripulacion or nil
    local tripulacion, vehiculos = {}, {}
    for k = 1, #quienes do
        tripulacion[k] = { muertos = 0, heridos = 0 }
        vehiculos[k] = 0
    end
    for _, tipo in ipairs(VEHICULOS) do
        local lista = r.averiados and r.averiados[tipo] or {}
        local zonasTipo = type(zonas) == 'table' and zonas[tipo] or {}
        local reparto = repartirPorModelo(quienes, tipo, #lista, r.averiados and r.averiados.modelos)
        for k in ipairs(quienes) do
            for _, par in ipairs(reparto[k]) do
                local indice, modelo = par[1], par[2]
                local codigo, bajas, fallecen = averiaDeEscena(zonasTipo[indice], tipo, modelo, azar)
                Simulacion.anotarAveria(averias[k], tipo, codigo, modelo)
                aplicado.averiados[tipo] = aplicado.averiados[tipo] + 1
                aplicado.dano[tipo] = aplicado.dano[tipo] + Averias.trabajo(codigo)
                vehiculos[k] = vehiculos[k] + 1
                if not totales then
                    tripulacion[k].muertos = tripulacion[k].muertos + fallecen
                    tripulacion[k].heridos = tripulacion[k].heridos + bajas - fallecen
                end
            end
        end
    end
    -- Las bajas de tripulación del bando, sin zonas: en proporción a los averiados de cada uno.
    if totales then
        local caidos = repartir(vehiculos, math.max(0, math.floor(tonumber(totales.muertos) or 0)))
        local hieren = repartir(vehiculos, math.max(0, math.floor(tonumber(totales.heridos) or 0)))
        for k = 1, #quienes do
            tripulacion[k].muertos, tripulacion[k].heridos = caidos[k], hieren[k]
        end
    end
    -- Heridos y averiados: con su grupo o, los de la guarnición, al taller.
    -- Los tripulantes muertos salen de la población de su ciudad.
    for k, q in ipairs(quienes) do
        local a = averias[k]
        local t = tripulacion[k]
        aplicado.tripulacion.muertos = aplicado.tripulacion.muertos + t.muertos
        aplicado.tripulacion.heridos = aplicado.tripulacion.heridos + t.heridos
        self:morirTripulantes(q.nacion, self:ciudadDeFuerza(q), t.muertos)
        if q == sitio then
            local c = self:ciudadDeSitio(q.nacion, q)
            a.tripulantes = t.heridos > 0 and t.heridos or nil
            if c then
                self:sumarCola(c, a.soldados, a)
            end
        else
            q.heridos = q.heridos or tropasVacias()
            q.heridos.soldados = q.heridos.soldados + a.soldados
            for _, tipo in ipairs(VEHICULOS) do
                for j = 1, #a[tipo] do
                    Simulacion.averiar(q, tipo, Averias.codigo(a, tipo, j), Armamento.modeloAveria(a, tipo, j))
                end
            end
            Simulacion.herirTripulantes(q, t.heridos)
        end
    end
    return aplicado
end

--- Resultado de la escena 3D (3.7, 3.9): ver el contrato en la cabecera.
function Batallas:resolverBatalla(c)
    local e = self.estado
    local b = e.batallas[c.batalla]
    if not b then
        return false
    end
    b.enEscena, b.escenaDesde = nil, nil
    local resultado = c.resultado or resultadoDeCaidos(c.caidos)
    for _, lado in ipairs(LADOS) do
        if not resultadoValido(resultado[lado] or {}, sanosBando(self, b, lado, true)) then
            return false
        end
    end
    local sitio = self:sitioBando(b)
    local aplicado = {}
    local azar = Ruido.azar(Ruido.hash(e.semilla, e.dia, b.id, 96))
    for _, lado in ipairs(LADOS) do
        local quienes = self:gruposBando(b, lado)
        local suyo = lado == 'defensor' and sitio or nil
        if suyo then
            quienes[#quienes + 1] = suyo
        end
        local aguante = suyo and aguanteSitio(suyo) or 0
        aplicado[lado] = self:aplicarResultado(quienes, suyo, resultado[lado] or {}, azar)
        if suyo and esCiudad(suyo) then
            local perdido = aguante - aguanteSitio(suyo)
            local vida = c.vida or vidaPerdida(perdido, aguanteSitio(suyo))
            suyo.vida = math.max(0, (suyo.vida or Simulacion.vidaCiudad.maxima) - vida)
            suyo.asediadaDia = e.dia
        end
    end
    for _, lado in ipairs(LADOS) do
        local otro = OTRO_LADO[lado]
        for _, g in ipairs(self:gruposBando(b, lado)) do
            if Simulacion.vidaGrupo(g) <= 0 then
                self:caerEnBatalla(b, g, otro, azar)
            elseif c.retira == lado then
                self:retirarDeBatalla(b, g, otro)
            end
        end
    end
    local s = self:sitioBando(b)
    if s and not esCiudad(s) and s.tipo ~= 'bandera' and s.soldados <= 0 then
        local primero = self:gruposBando(b, 'atacante')[1]
        if primero then
            self:destruirInstalacion(s, primero.nacion)
        end
    end
    self:terminarSiToca(b)
    return true, aplicado
end

local publicas = {
    'azarAverias',
    'perderRampas',
    'herirGrupo',
    'herirSitio',
    'unirBatalla',
    'crearBatalla',
    'gruposBando',
    'sitioBando',
    'ladoDe',
    'batallaEn',
    'ventajaBando',
    'nombreBatalla',
    'repartirCarga',
    'caerEnBatalla',
    'retirarDeBatalla',
    'limpiarBatalla',
    'danarSitio',
    'golpeConMunicion',
    'anotarGasto',
    'diaBatalla',
    'terminarSiToca',
    'cerrarBatalla',
    'resolverBatallas',
    'entrarBatalla',
    'noDefender',
    'aplicarResultado',
    'resolverBatalla',
}

--- Cuelga de la clase Simulacion las funciones de batalla y `Simulacion.batalla` (las reglas).
function Batallas.instalar(clase)
    Simulacion = clase
    clase.batalla = Batallas.reglas
    clase.golpeSitio = golpeSitio
    clase.aguanteSitio = aguanteSitio
    clase.sitioEnPie = sitioEnPie
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Batallas[nombre]
    end
end

return Batallas

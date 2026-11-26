--- Armamento: modelos reales de lanzacohetes, sus cifras de juego, las eras y el desglose por modelo.
--
-- Sin tanques desde el 19-nov (el dueño: «los tanques no los usaremos, todo
-- esto será un mundo de robots»): la partida v30 los devuelve en dinero
-- (guardado.lua). Los vehículos son los lanzacohetes, que conducen robots.
-- Desde el 21-nov (el dueño: en el juego solo robots y lo hecho por el
-- estudio) queda un único modelo, el camión de misiles con robot conductor
-- (clave 'scudb'); el BM-21 y el HIMARS salieron del catálogo y sus claves,
-- en partidas viejas, cuentan como él (RETIRADOS).
--
-- Diseño en diseno/catalogo-armamento.md (decisiones del dueño del 2026-09-30, P1 a P8).
-- Datos reales y nombres visibles: catalogoArmamento.lua (el único archivo con nombres).
--
-- Cada vehículo es de un MODELO, con una clave interna fija:
--   lanzacohetes 'scudb' (era 1, el camión de misiles con robot conductor)
-- Las fórmulas F1 a F12 del documento dan a cada modelo unos FACTORES sobre las
-- reglas de hoy (vida, golpe, coste, días, sueldo, combustible, taller,
-- munición, velocidad). La referencia ('scudb') tiene todos a 1. Las variantes del
-- kit de piezas (diseno-de-armamento.md, más adelante) serán un modelo base
-- más modificadores que multipliquen estos factores.
--
-- Estado (solo datos, claves internas; nunca nombres):
--   Junto a cada recuento de vehículos, su desglose por modelo:
--     ciudades, instalaciones y grupos: `lanzacohetesPor`
--     parque de una ciudad: `parquePor`; entrega de lanzacohetes: `g.carga.cantidadPor`
--     obra que lleva lanzacohetes: `g.construye.lanzacohetesPor`
--   { scudb = 3 }: la suma es el recuento. Lo que falte en un desglose
--   (tablas hechas a mano, pruebas) cuenta como del modelo de referencia;
--   `Armamento.revisar` lo señala.
--   Averías de un grupo y cola del taller: junto a cada lista de daños, la de
--   sus modelos en el mismo orden: `averias.modelos = { lanzacohetes = { m, ... } }`
--   (`g.averias`, `c.recuperando.danos`).
--   Fábrica: cada orden de vehículos lleva su `modelo`.
--   Eras: tres tecnologías al final de `Simulacion.tecnologias` ('era2',
--   'era3', 'era4'); no suben el dinero del trabajo ni la fuerza por
--   tecnología (P7): ver `Simulacion.tecnologiasQueCuentan`.
--
-- API PARA LA VISTA (Arsenal, fichas de ejército, batalla 3D) --------------------------------------
--
--   Simulacion.Armamento.modelos(tipo)          ids en orden de catálogo ('lanzacohetes' o nil: todos)
--   Simulacion.Armamento.modelosDeEra(era, tipo) ids de esa era
--   Simulacion.fichaModelo(id) -> {
--       id, tipo, nombre, era, categoria ('artilleria' | 'misiles'),
--       tecnologia (id de la que lo desbloquea, o nil), real = { textos de la ficha pública },
--       juego = { vida, golpe, poder, velocidad, consumo, coste = { dinero, metal, petroleo },
--                 dias, sueldo, combustible = { parado, marcha }, ritmoTaller,
--                 reparacion = { dinero, metal }, municion = { tipo, porDia, porDisparo } },
--       escena = { proyectiles, carga, radio, cep, cepProvisional, porDisparo, alcance, alcanceMinimo } }
--       (`carga`: proyectiles que caben cargados en el camión; el Scud-B, 4
--       misiles que dispara de uno en uno; los demás, una salva. Cada
--       proyectil gasta `porDisparo` misiles de munición: el Scud-B, 1)
--   Simulacion.nombreModelo(id)                 el nombre visible (del archivo de datos)
--   sim:eraDe(nid)                              1 a 4
--   sim:modelosFabricables(nid, tipo)           lo que fabrica HOY cualquier ciudad de `nid` (todo lo de su era y anteriores)
--   sim:puedeFabricarModelo(nid, id)            true, o false y 'modelo' | 'tecnologia' | 'era'
--   sim:modeloPorDefecto(nid, tipo)             el que se encarga si `producir` no dice modelo
--   Simulacion.desglose(q, campo)               { { modelo, cantidad }, ... } de un grupo, sitio o bando
--                                               (campo 'lanzacohetes' o 'parque')
--   sim:inventario(nid).total.modelos[id] = { sanos, heridos, fabrica } (y .ciudades[cid].modelos)
--   sim:estadoBatalla(bid): cada grupo y el sitio llevan `lanzacohetesPor`
--       (completos) y cada bando `sanosPor` (modelo -> sanos)
--   ejecutar({ tipo = 'producir', ..., tropa = 'lanzacohetes', modelo = 'scudb' })
--   ejecutar({ tipo = 'enviarGrupo' | 'recolectar', ..., modelos = { scudb = 2 } })
--       elige qué modelos salen (sin `modelos`, salen en proporción a lo que hay)
--
-- Módulo de `mundo/simulacion.lua`: `Armamento.instalar(Simulacion)`. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Catalogo = require('mundo.simulacion.catalogoArmamento')

local repartirRestos = Ayudas.repartirRestos

local Armamento = {}
Armamento.Catalogo = Catalogo

-- Se fija en `instalar`: la clase.
local Simulacion

--- Perillas (diseno/catalogo-armamento.md, §7). Tras cambiar una de las
-- fórmulas (alfa, beta, factorEra, límites...), `Armamento.calcular()`.
Armamento.reglas = {
    catalogo = true, -- false: todo es Scud-B, sin eras (el mundo de antes)
    betaLanza = 1 / 3, -- P4
    factorEra = { 0.75, 1, 1.2, 1.35 }, -- F1: k(era)
    finEra = { 1968, 1978, 1999 }, -- F1: último año de las eras 1 a 3
    limiteLanza = { 0.75, 2 }, -- F11: golpe relativo de un lanzacohetes (P9: tope ×2, decidido por el dueño)
    limiteVelocidad = { 0.75, 1.3 }, -- F4
    referencia = { lanzacohetes = 'scudb' },
    diasMinimos = { lanzacohetes = 3 }, -- F6
    radioReferencia = 18, -- F10: m, radio de daño del Scud-B en la escena
    dispersionSinGuiar = 62, -- F10: m, CEP en la escena sin guiado o sin dato
    cepEscala = 0.1, -- F10: CEP en la escena = CEP real × cepEscala
    limiteCep = { 2, 90 },
    alcance = { base = 2.1, porDecada = 0.9, referencia = 3, minimo = 1.5, maximo = 4, minimoDisparo = 0.5 }, -- F12, km
    -- Tecnologías de era, al final de la fila de investigación (§3.4).
    tecnologias = {
        { id = 'era2', era = 2, coste = 1500 },
        { id = 'era3', era = 3, coste = 4500 },
        { id = 'era4', era = 4, coste = 9000 },
    },
    decimales = 10000, -- los factores se redondean a 4 decimales: iguales en toda máquina
}

local TIPOS = { 'lanzacohetes' }
Armamento.TIPOS = TIPOS

-- Campo del desglose de cada recuento y el tipo de vehículo que cuenta.
local POR = { lanzacohetes = 'lanzacohetesPor', parque = 'parquePor', cantidad = 'cantidadPor' }
local TIPO_CAMPO = { lanzacohetes = 'lanzacohetes', parque = 'lanzacohetes', cantidad = 'lanzacohetes' }
Armamento.POR = POR
Armamento.TIPO_CAMPO = TIPO_CAMPO

local ORDEN = Catalogo.orden
local TODOS = {}
local TIPO = {} -- modelo -> tipo
local DATOS = {} -- modelo -> ficha real
for _, tipo in ipairs(TIPOS) do
    for _, id in ipairs(ORDEN[tipo]) do
        TODOS[#TODOS + 1] = id
        TIPO[id] = tipo
        DATOS[id] = Catalogo[tipo][id]
    end
end

-- Modelos que salieron del catálogo (21-nov: camiones con cabina humana) ->
-- el que ocupa su lugar. Una partida vieja aún puede traerlos en un desglose,
-- una avería o una orden de fábrica: cuentan como ese, con sus mismas cifras,
-- y no se listan ni se fabrican (no están en el orden del catálogo).
local RETIRADOS = { bm21 = 'scudb', himars = 'scudb' }
Armamento.RETIRADOS = RETIRADOS
for viejo, nuevo in pairs(RETIRADOS) do
    TIPO[viejo] = TIPO[nuevo]
    DATOS[viejo] = DATOS[nuevo]
end

-- Factores de cada modelo (se rellenan en `calcular`).
local F = {}
Armamento.factores = F

local function limitar(x, a, b)
    return math.max(a, math.min(b, x))
end

local function redondear(x)
    local d = Armamento.reglas.decimales
    return math.floor(x * d + 0.5) / d
end

--- Era de un año (F1).
local function eraDeAnio(anio)
    local fin = Armamento.reglas.finEra
    for era = 1, #fin do
        if anio <= fin[era] then
            return era
        end
    end
    return #fin + 1
end

--- Radio, CEP de la escena, probabilidad de caer dentro y efecto de una salva (F10).
local function efectoSalva(m)
    local reglas = Armamento.reglas
    local ref = DATOS[reglas.referencia.lanzacohetes]
    local radio = reglas.radioReferencia * (m.ojiva / ref.ojiva) ^ (1 / 3)
    local cep = reglas.dispersionSinGuiar
    if m.cep then
        cep = limitar(m.cep * reglas.cepEscala, reglas.limiteCep[1], reglas.limiteCep[2])
    end
    local q = radio / cep
    local p = 1 - 2 ^ -(q * q)
    return m.proyectiles * p, radio, cep
end

--- Alcance en la escena (F12), km.
local function alcanceEscena(km)
    local a = Armamento.reglas.alcance
    return limitar(a.base + a.porDecada * math.log10(km / a.referencia), a.minimo, a.maximo)
end

--- Factores de un lanzacohetes respecto al de referencia (F10, F11). La
-- velocidad se mide contra el Scud-B (45 km/h): el camión de hoy va como hoy (A1).
local function factoresLanza(m, r)
    local reglas = Armamento.reglas
    local e = efectoSalva(m)
    local eRef = efectoSalva(r)
    local masa = m.masa or r.masa
    local f = {}
    f.golpe = redondear(limitar((e / eRef) ^ reglas.betaLanza, reglas.limiteLanza[1], reglas.limiteLanza[2]))
    f.vida = redondear((masa / r.masa) ^ (1 / 3))
    f.medio = (f.vida + f.golpe) / 2
    f.metal = redondear(limitar(masa / r.masa, 0.4, 1.5))
    f.velocidad = redondear(
        limitar((m.velocidad or r.velocidad) / r.velocidad, reglas.limiteVelocidad[1], reglas.limiteVelocidad[2])
    )
    f.consumo = redondear((m.potencia or r.potencia) / r.potencia)
    f.sueldo = redondear((m.tripulacion or r.tripulacion) / r.tripulacion)
    f.ritmo = redondear(1 / f.vida)
    f.municion = f.golpe -- F11: porDia = 7 × golpe / 40
    return f
end

--- Recalcula los factores de todos los modelos con las perillas de ahora.
function Armamento.calcular()
    local reglas = Armamento.reglas
    for _, tipo in ipairs(TIPOS) do
        local r = DATOS[reglas.referencia[tipo]]
        for _, id in ipairs(ORDEN[tipo]) do
            local f = factoresLanza(DATOS[id], r)
            f.era = eraDeAnio(DATOS[id].anio)
            F[id] = f
        end
    end
    for viejo, nuevo in pairs(RETIRADOS) do
        F[viejo] = F[nuevo]
    end
end

Armamento.calcular()

-- Catálogo -----------------------------------------------------------------------------------------

--- Modelos de un tipo (o todos) en orden de catálogo.
function Armamento.modelos(tipo)
    local lista = tipo and ORDEN[tipo] or TODOS
    local out = {}
    for k, id in ipairs(lista) do
        out[k] = id
    end
    return out
end

--- Modelos de una era (de un tipo o de los dos), en orden de catálogo.
function Armamento.modelosDeEra(era, tipo)
    local out = {}
    for _, id in ipairs(tipo and ORDEN[tipo] or TODOS) do
        if F[id].era == era then
            out[#out + 1] = id
        end
    end
    return out
end

--- Tipo de vehículo de un modelo ('lanzacohetes'), o nil si no existe.
function Armamento.tipoDe(id)
    return TIPO[id]
end

--- Modelo de referencia de un tipo (el de las cifras de hoy).
local function referencia(tipo)
    return Armamento.reglas.referencia[tipo]
end
Armamento.referencia = referencia

--- Nombre visible de un modelo o de una tecnología de era (del archivo de datos; sin él, la clave).
function Armamento.nombre(id)
    return Catalogo.nombres[RETIRADOS[id] or id] or id
end

--- Era de un modelo.
function Armamento.eraModelo(id)
    return F[id].era
end

--- Tecnología que desbloquea un modelo: ninguna en la era 1 y la de su era después.
function Armamento.tecnologiaDe(id)
    local era = F[id].era
    if era > 1 then
        return 'era' .. era
    end
    return nil
end

-- Cifras de juego de un modelo (las reglas de hoy × sus factores) ----------------------------------

--- Peso de la referencia en combate: lanzacohetes 40 (las perillas de hoy).
local function pesoReferencia(_tipo)
    return Simulacion.conquista.fuerzaLanzacohetes
end
Armamento.pesoReferencia = pesoReferencia

function Armamento.vida(id)
    return pesoReferencia(TIPO[id]) * F[id].vida
end

function Armamento.golpe(id)
    return pesoReferencia(TIPO[id]) * F[id].golpe
end

--- Poder de una unidad (F9): escalaPoder × (vida + golpe) / 2.
function Armamento.poder(id)
    return Simulacion.escalaPoder * pesoReferencia(TIPO[id]) * F[id].medio
end

--- Coste de una unidad (F6).
function Armamento.coste(id)
    local f = F[id]
    local base = Simulacion.produccion.coste[TIPO[id]]
    return { dinero = base.dinero * f.medio, metal = base.metal * f.metal, petroleo = base.petroleo }
end

--- Días de fábrica de una tanda (F6).
function Armamento.dias(id)
    local tipo = TIPO[id]
    local dias = Simulacion.produccion.dias[tipo]
    return math.max(Armamento.reglas.diasMinimos[tipo], math.floor(dias * F[id].medio + 0.5))
end

--- Sueldo al día (F7).
function Armamento.sueldo(id)
    return Simulacion.produccion.sueldo[TIPO[id]] * F[id].sueldo
end

--- Puntos de taller al día y por nivel (F8).
function Armamento.ritmo(id)
    return Simulacion.recuperacion.ritmo[TIPO[id]] * F[id].ritmo
end

--- Lo que cuesta reparar daño 1 (F8).
function Armamento.reparacion(id)
    local base = Simulacion.produccion.reparacion[TIPO[id]]
    return { dinero = base.dinero * F[id].medio, metal = base.metal * F[id].metal }
end

--- Tripulantes de un modelo (los de su ficha real; sin dato, los del de referencia).
function Armamento.tripulacion(id)
    local ref = DATOS[referencia('lanzacohetes')]
    local datos = DATOS[id] or ref
    return datos.tripulacion or ref.tripulacion or 3
end

--- Munición (misiles) que gasta una unidad en un día de batalla (F11).
function Armamento.porDia(id)
    return Simulacion.produccion.municion.misiles.porDia * F[id].municion
end

--- Ficha de un modelo para la vista (ver la cabecera), o nil si no existe.
function Armamento.ficha(id)
    local tipo = TIPO[id]
    if not tipo then
        return nil
    end
    local f = F[id]
    local datos = DATOS[id]
    local reglas = Simulacion.produccion
    local municion = 'misiles'
    local ficha = {
        id = id,
        tipo = tipo,
        nombre = Armamento.nombre(id),
        era = f.era,
        categoria = datos.categoria,
        tecnologia = Armamento.tecnologiaDe(id),
        real = {},
        juego = {
            vida = Armamento.vida(id),
            golpe = Armamento.golpe(id),
            poder = Armamento.poder(id),
            velocidad = f.velocidad,
            consumo = f.consumo,
            coste = Armamento.coste(id),
            dias = Armamento.dias(id),
            sueldo = Armamento.sueldo(id),
            combustible = {
                parado = reglas.combustible.parado[tipo] * f.consumo,
                marcha = reglas.combustible.marcha[tipo] * f.consumo,
            },
            ritmoTaller = Armamento.ritmo(id),
            reparacion = Armamento.reparacion(id),
            municion = {
                tipo = municion,
                porDia = Armamento.porDia(id),
                porDisparo = reglas.municion[municion].porDisparo * f.municion / (datos.proyectiles or 1),
            },
        },
    }
    for clave, texto in pairs(datos.texto) do
        ficha.real[clave] = texto
    end
    local _, radio = efectoSalva(datos)
    local eRef = efectoSalva(DATOS[referencia('lanzacohetes')])
    -- F11b: la dispersión con la que una salva vale su golpe.
    local p = math.min(0.999999, eRef * f.golpe / datos.proyectiles)
    ficha.escena = {
        proyectiles = datos.proyectiles,
        carga = datos.carga or datos.proyectiles,
        radio = radio,
        cep = radio / math.sqrt(-math.log(1 - p) / math.log(2)),
        cepProvisional = datos.cepProvisional or false,
        porDisparo = ficha.juego.municion.porDisparo,
        alcance = alcanceEscena(datos.alcance),
        alcanceMinimo = Armamento.reglas.alcance.minimoDisparo,
    }
    return ficha
end

-- Desglose por modelo de un recuento ---------------------------------------------------------------

--- Cantidades de cada modelo del tipo de `q[campo]`, en orden de catálogo (lo
-- que no está en el desglose, del de referencia). Devuelve la lista y los ids.
local function cuentas(q, campo)
    local tipo = TIPO_CAMPO[campo]
    local lista = ORDEN[tipo]
    local total = q[campo] or 0
    local por = q[POR[campo]]
    local out = {}
    local puestos = 0
    for i = 1, #lista do
        local k = por and por[lista[i]] or 0
        k = math.max(0, math.min(k, total - puestos))
        out[i] = k
        puestos = puestos + k
    end
    if puestos < total then
        local ref = referencia(tipo)
        for i = 1, #lista do
            if lista[i] == ref then
                out[i] = out[i] + total - puestos
            end
        end
    end
    return out, lista
end

--- Σ cantidad × factor[clave] de los modelos de `q[campo]` (un número por
-- unidad para la referencia: con todo de referencia, el recuento).
function Armamento.suma(q, campo, clave)
    local total = q[campo] or 0
    if total <= 0 then
        return 0
    end
    local tipo = TIPO_CAMPO[campo]
    local por = q[POR[campo]]
    local ref = Armamento.reglas.referencia[tipo]
    if not por then
        return total * F[ref][clave]
    end
    local lista = ORDEN[tipo]
    local suma, puestos = 0, 0
    for i = 1, #lista do
        local m = lista[i]
        local k = por[m]
        if k and k > 0 then
            k = math.min(k, total - puestos)
            suma = suma + k * F[m][clave]
            puestos = puestos + k
        end
    end
    if puestos < total then
        suma = suma + (total - puestos) * F[ref][clave]
    end
    return suma
end

--- Vida y golpe de los vehículos de `q[campo]`.
function Armamento.vidaDe(q, campo)
    return pesoReferencia(TIPO_CAMPO[campo]) * Armamento.suma(q, campo, 'vida')
end

function Armamento.golpeDe(q, campo)
    return pesoReferencia(TIPO_CAMPO[campo]) * Armamento.suma(q, campo, 'golpe')
end

--- Peso (vida + golpe) / 2 de los vehículos de `q[campo]`.
function Armamento.pesoDe(q, campo)
    return pesoReferencia(TIPO_CAMPO[campo]) * Armamento.suma(q, campo, 'medio')
end

--- Poder de los vehículos de `q[campo]` (F9).
function Armamento.poderDe(q, campo)
    return Simulacion.escalaPoder * pesoReferencia(TIPO_CAMPO[campo]) * Armamento.suma(q, campo, 'medio')
end

--- Desglose completo de `q[campo]`: tabla modelo -> cantidad (nueva).
function Armamento.porModelo(q, campo)
    local tiene, lista = cuentas(q, campo)
    local out = {}
    for i, m in ipairs(lista) do
        if tiene[i] > 0 then
            out[m] = tiene[i]
        end
    end
    return out
end

--- Desglose de `q[campo]` como lista: { { modelo, cantidad }, ... } en orden de catálogo.
function Armamento.desglose(q, campo)
    local tiene, lista = cuentas(q, campo)
    local out = {}
    for i, m in ipairs(lista) do
        if tiene[i] > 0 then
            out[#out + 1] = { modelo = m, cantidad = tiene[i] }
        end
    end
    return out
end

--- Qué modelos saldrían al sacar `n` de `q[campo]` (sin cambiar nada): los
-- que pide `pide` (modelo -> cantidad) mientras haya, y el resto en proporción
-- a lo que hay de cada uno (restos mayores; a igual resto, el primero del
-- catálogo). Devuelve una tabla modelo -> cantidad.
function Armamento.partir(q, campo, n, pide)
    local out = {}
    if not n or n <= 0 then
        return out
    end
    if not pide then
        -- Lo más común: todo de un modelo (o sin desglose). Sin tablas de más.
        local tipo = TIPO_CAMPO[campo]
        local total = q[campo] or 0
        local por = q[POR[campo]]
        local unico, puestos, distintos = referencia(tipo), 0, 0
        if por then
            for _, m in ipairs(ORDEN[tipo]) do
                local k = por[m]
                if k and k > 0 then
                    distintos = distintos + 1
                    unico = m
                    puestos = puestos + k
                end
            end
        end
        if puestos < total and unico ~= referencia(tipo) then
            distintos = distintos + 1
        end
        if distintos <= 1 then
            local k = math.min(n, total)
            if k > 0 then
                out[unico] = k
            end
            return out
        end
    end
    local tiene, lista = cuentas(q, campo)
    local quedan = n
    if pide then
        for i, m in ipairs(lista) do
            local k = math.min(tiene[i], math.floor(tonumber(pide[m]) or 0), quedan)
            if k > 0 then
                out[m] = k
                tiene[i] = tiene[i] - k
                quedan = quedan - k
            end
        end
    end
    if quedan <= 0 then
        return out
    end
    -- Con un solo modelo no hace falta repartir.
    local unico
    local distintos = 0
    for i = 1, #lista do
        if tiene[i] > 0 then
            distintos = distintos + 1
            unico = i
        end
    end
    if distintos == 1 then
        local k = math.min(quedan, tiene[unico])
        out[lista[unico]] = (out[lista[unico]] or 0) + k
        return out
    end
    if distintos == 0 then
        return out
    end
    local partes = repartirRestos(tiene, quedan, tiene)
    for i, m in ipairs(lista) do
        if partes[i] > 0 then
            out[m] = (out[m] or 0) + partes[i]
        end
    end
    return out
end

--- Cuántas unidades hay en un desglose (tabla modelo -> cantidad).
function Armamento.contar(por)
    local total = 0
    for _, m in ipairs(TODOS) do
        total = total + (por and por[m] or 0)
    end
    return total
end

--- Saca de `q[campo]` el desglose `por` (tabla modelo -> cantidad) que ya se sabe que está.
local function quitarPor(q, campo, por)
    local total = 0
    local suyo = q[POR[campo]]
    for _, m in ipairs(ORDEN[TIPO_CAMPO[campo]]) do
        local k = por[m]
        if k and k > 0 then
            total = total + k
            if suyo then
                local t = suyo[m] or 0
                t = t - math.min(t, k)
                suyo[m] = t > 0 and t or nil
            end
        end
    end
    if total == 0 then
        return
    end
    q[campo] = (q[campo] or 0) - total
    if suyo then
        -- Sin nada desglosado, el desglose se borra.
        local queda = false
        for _, m in ipairs(ORDEN[TIPO_CAMPO[campo]]) do
            if suyo[m] then
                queda = true
            end
        end
        if not queda then
            q[POR[campo]] = nil
        end
    end
end

--- Saca `n` vehículos de `q[campo]` (ver `partir`) y devuelve su desglose.
function Armamento.sacar(q, campo, n, pide)
    local por = Armamento.partir(q, campo, n, pide)
    quitarPor(q, campo, por)
    return por
end

--- Saca todos los vehículos de `q[campo]` y devuelve su desglose.
function Armamento.vaciar(q, campo)
    local por = Armamento.porModelo(q, campo)
    q[campo] = 0
    q[POR[campo]] = nil
    return por
end

--- Mete `n` vehículos del modelo `id` en `q[campo]`.
function Armamento.meter(q, campo, id, n)
    if not n or n <= 0 then
        return
    end
    q[campo] = (q[campo] or 0) + n
    local clave = POR[campo]
    local por = q[clave]
    if not por then
        por = {}
        q[clave] = por
    end
    por[id] = (por[id] or 0) + n
end

--- Mete en `q[campo]` un desglose entero (tabla modelo -> cantidad).
function Armamento.meterPor(q, campo, por)
    if not por then
        return
    end
    for _, m in ipairs(ORDEN[TIPO_CAMPO[campo]]) do
        local k = por[m]
        if k and k > 0 then
            Armamento.meter(q, campo, m, k)
        end
    end
end

--- Pasa `n` vehículos de `desde[campoDesde]` a `hacia[campoHacia]` y devuelve su desglose.
function Armamento.mover(desde, campoDesde, hacia, campoHacia, n, pide)
    local por = Armamento.sacar(desde, campoDesde, n, pide)
    Armamento.meterPor(hacia, campoHacia, por)
    return por
end

--- `pide` menos lo que ya salió (`por`): una tabla nueva, o nil sin `pide`.
function Armamento.restar(pide, por)
    if not pide then
        return nil
    end
    local out = {}
    for _, m in ipairs(TODOS) do
        local k = (tonumber(pide[m]) or 0) - (por and por[m] or 0)
        if k > 0 then
            out[m] = k
        end
    end
    return out
end

--- Cuántas unidades de un tipo pide `pide` (tabla modelo -> cantidad).
function Armamento.pedidas(pide, tipo)
    local total = 0
    for _, m in ipairs(ORDEN[tipo]) do
        total = total + math.max(0, math.floor(tonumber(pide[m]) or 0))
    end
    return total
end

--- Lista de modelos de un desglose, uno por unidad, en orden de catálogo.
function Armamento.lista(por, tipo, n)
    local out = {}
    for _, m in ipairs(tipo and ORDEN[tipo] or TODOS) do
        for _ = 1, por and por[m] or 0 do
            out[#out + 1] = m
        end
    end
    -- Sin desglose (o corto): de referencia.
    for _ = #out + 1, n or 0 do
        out[#out + 1] = referencia(tipo)
    end
    return out
end

--- Los lanzacohetes que saldrían de `desde` (como en `enviarGrupo`: primero
-- del parque), con su desglose: { lanzacohetes, lanzacohetesPor }. No cambia nada.
function Armamento.salen(desde, lanzacohetes, pide)
    local out = { lanzacohetes = lanzacohetes }
    local delParque = math.min(lanzacohetes, desde.parque or 0)
    local porParque = Armamento.partir(desde, 'parque', delParque, pide)
    local porPlataformas =
        Armamento.partir(desde, 'lanzacohetes', lanzacohetes - delParque, Armamento.restar(pide, porParque))
    out.lanzacohetesPor = {}
    for _, m in ipairs(TODOS) do
        local k = (porParque[m] or 0) + (porPlataformas[m] or 0)
        if k > 0 then
            out.lanzacohetesPor[m] = k
        end
    end
    return out
end

--- Velocidad de un grupo (F4): la de su modelo más lento; 1 sin vehículos.
function Armamento.velocidadGrupo(g)
    local v
    for _, tipo in ipairs(TIPOS) do
        local total = g[tipo] or 0
        if total > 0 then
            local por = g[POR[tipo]]
            local puestos = 0
            if por then
                for _, m in ipairs(ORDEN[tipo]) do
                    local k = por[m]
                    if k and k > 0 then
                        puestos = puestos + k
                        if not v or F[m].velocidad < v then
                            v = F[m].velocidad
                        end
                    end
                end
            end
            if puestos < total then
                local ref = F[referencia(tipo)].velocidad
                if not v or ref < v then
                    v = ref
                end
            end
        end
    end
    return v or 1
end

-- Averías y taller: un modelo por daño --------------------------------------------------------------

--- Modelo del daño `k` de la lista de `tipo` de unas averías (o de la cola del taller).
function Armamento.modeloAveria(averias, tipo, k)
    local modelos = averias and averias.modelos and averias.modelos[tipo]
    return modelos and modelos[k] or referencia(tipo)
end

--- Apunta un daño `dano` del modelo `id` en unas averías.
function Armamento.anotarAveria(averias, tipo, dano, id)
    local lista = averias[tipo]
    lista[#lista + 1] = dano
    averias.modelos = averias.modelos or { lanzacohetes = {} }
    local modelos = averias.modelos[tipo]
    modelos[#lista] = id or referencia(tipo)
end

-- Eras y fabricación ---------------------------------------------------------------------------------

--- Pone o quita el catálogo (y con él las tecnologías de era al final de la fila).
function Armamento.usarCatalogo(activo)
    Armamento.reglas.catalogo = activo and true or false
    local lista = Simulacion.tecnologias
    for k = #lista, 1, -1 do
        if lista[k].era then
            table.remove(lista, k)
        end
    end
    Armamento.tecnologiasBase = #lista
    if activo then
        for _, t in ipairs(Armamento.reglas.tecnologias) do
            lista[#lista + 1] = { id = t.id, nombre = Armamento.nombre(t.id), coste = t.coste, era = t.era }
        end
    end
end

--- Tecnologías de `n` que cuentan para el dinero del trabajo y la fuerza: todas salvo las de era (P7).
function Armamento.tecnologiasQueCuentan(n)
    return math.min(n.tecnologia, Armamento.tecnologiasBase)
end

--- Era de la nación `nid` (1 a 4): la de su última tecnología de era.
function Armamento:eraDe(nid)
    local era = 1
    for _, t in ipairs(Armamento.reglas.tecnologias) do
        if self:tiene(nid, t.id) then
            era = t.era
        end
    end
    return era
end

--- ¿Puede la nación `nid` fabricar el modelo `id`? true, o false y el motivo:
-- 'modelo' (no existe o salió del catálogo) o 'era'.
-- `era`: la de la nación, si ya se sabe.
function Armamento:puedeFabricarModelo(nid, id, era)
    local tipo = TIPO[id]
    if not tipo or RETIRADOS[id] then
        return false, 'modelo'
    end
    if not Armamento.reglas.catalogo then
        if id ~= referencia(tipo) then
            return false, 'era'
        end
        return true
    end
    if F[id].era > (era or self:eraDe(nid)) then
        return false, 'era'
    end
    return true
end

--- Modelos de `tipo` que fabrica hoy la nación `nid`, en orden de catálogo.
function Armamento:modelosFabricables(nid, tipo)
    local out = {}
    local era = self:eraDe(nid)
    for _, id in ipairs(ORDEN[tipo]) do
        if self:puedeFabricarModelo(nid, id, era) then
            out[#out + 1] = id
        end
    end
    return out
end

--- El modelo que se encarga si `producir` no dice cuál: el de más poder que
-- puede fabricar (a igual poder, el primero del catálogo); sin ninguno, el
-- primero de su tipo (para que el motivo del rechazo sea el suyo).
function Armamento:modeloPorDefecto(nid, tipo)
    local mejor
    for _, id in ipairs(self:modelosFabricables(nid, tipo)) do
        if not mejor or F[id].medio > F[mejor].medio then
            mejor = id
        end
    end
    if mejor then
        return mejor
    end
    if not Armamento.reglas.catalogo then
        return referencia(tipo)
    end
    return ORDEN[tipo][1]
end

--- Modelo con el que nace una nación (§3.4): el primero de la era 1 de su
-- tipo (T-55 y Scud-B); sin catálogo, el de referencia.
function Armamento.modeloInicial(tipo)
    if not Armamento.reglas.catalogo then
        return referencia(tipo)
    end
    return Armamento.modelosDeEra(1, tipo)[1]
end

--- El modelo que encarga el presidente NPC (§10.7): el de más poder que
-- puede fabricar y pagar (`puedePagar(coste)`); sin combustible, el que menos
-- gasta. nil si no puede pagar ninguno. `fabricables`: los de
-- `modelosFabricables`, si ya se tienen.
function Armamento:modeloParaNPC(n, tipo, puedePagar, fabricables)
    local mejor
    for _, id in ipairs(fabricables or self:modelosFabricables(n.id, tipo)) do
        if puedePagar(Armamento.coste(id)) then
            if not mejor then
                mejor = id
            elseif n.sinCombustible then
                if F[id].consumo < F[mejor].consumo then
                    mejor = id
                end
            elseif F[id].medio > F[mejor].medio then
                mejor = id
            end
        end
    end
    return mejor
end

-- Revisión del invariante (pruebas y auditoría) ----------------------------------------------------

--- Problemas de desglose del estado: recuentos cuyo desglose no suma lo
-- mismo, modelos que no existen o de otro tipo, y listas de modelos de
-- averías que no cuadran con sus daños. Lista de textos (vacía si todo cuadra).
function Armamento.revisar(sim)
    local e = sim.estado
    local out = {}
    local function recuento(que, q, campo)
        local total = q[campo] or 0
        local por = q[POR[campo]]
        local suma = 0
        for m, k in pairs(por or {}) do
            if TIPO[m] ~= TIPO_CAMPO[campo] then
                out[#out + 1] = string.format('%s: %s con el modelo %s', que, campo, tostring(m))
            end
            if type(k) ~= 'number' or k <= 0 or k ~= math.floor(k) then
                out[#out + 1] = string.format('%s: %s.%s = %s', que, campo, tostring(m), tostring(k))
            else
                suma = suma + k
            end
        end
        if suma ~= total then
            out[#out + 1] = string.format('%s: %s = %s y su desglose suma %s', que, campo, tostring(total), suma)
        end
    end
    local function averias(que, a, cuantos)
        for _, tipo in ipairs(TIPOS) do
            local n = #(a and a[tipo] or {})
            if cuantos and cuantos[tipo] and cuantos[tipo] ~= n then
                out[#out + 1] = string.format('%s: %d %s averiados y %d daños', que, cuantos[tipo], tipo, n)
            end
            local modelos = a and a.modelos and a.modelos[tipo] or {}
            if n > 0 and #modelos ~= n then
                out[#out + 1] = string.format('%s: %d daños de %s y %d modelos', que, n, tipo, #modelos)
            end
            for _, m in ipairs(modelos) do
                if TIPO[m] ~= tipo then
                    out[#out + 1] = string.format('%s: avería de %s con el modelo %s', que, tipo, tostring(m))
                end
            end
        end
    end
    for _, id in ipairs(Ayudas.ordenadas(e.ciudades)) do
        local c = e.ciudades[id]
        local que = 'ciudad ' .. id
        recuento(que, c, 'lanzacohetes')
        recuento(que, c, 'parque')
        if c.recuperando then
            averias('taller ' .. id, c.recuperando.danos, c.recuperando)
        end
        for _, o in ipairs(c.fabrica or {}) do
            if o.tropa ~= 'soldados' and TIPO[o.modelo] ~= o.tropa then
                out[#out + 1] = string.format('%s: orden %d de %s sin modelo válido', que, o.id, o.tropa)
            end
        end
    end
    for _, id in ipairs(Ayudas.ordenadas(e.instalaciones)) do
        local i = e.instalaciones[id]
        recuento('instalación ' .. id, i, 'lanzacohetes')
    end
    for _, id in ipairs(Ayudas.ordenadas(e.grupos)) do
        local g = e.grupos[id]
        local que = 'grupo ' .. id
        recuento(que, g, 'lanzacohetes')
        if g.heridos then
            averias(que, g.averias, g.heridos)
        end
        if type(g.carga) == 'table' then
            recuento(que .. ' (carga)', g.carga, 'cantidad')
        end
        if g.construye then
            recuento(que .. ' (obra)', g.construye, 'lanzacohetes')
        end
    end
    return out
end

--- Pasa a modelos un estado sin ellos (partidas de la versión 24): todo lo que
-- había es del modelo de referencia (Scud-B), así nada cambia de golpe. Los
-- tanques de esas partidas los devuelve en dinero la migración a la v30
-- (guardado.lua), que no necesita sus modelos.
function Armamento.migrar(estado)
    local function explicito(q, campo)
        if (q[campo] or 0) > 0 and not q[POR[campo]] then
            q[POR[campo]] = { [referencia(TIPO_CAMPO[campo])] = q[campo] }
        end
    end
    local function modelos(a)
        if not a then
            return
        end
        if not a.modelos and #(a.lanzacohetes or {}) == 0 then
            -- Nada averiado: sin lista de modelos, como la deja la versión de hoy.
            return
        end
        a.modelos = a.modelos or { lanzacohetes = {} }
        for _, tipo in ipairs(TIPOS) do
            local lista = a.modelos[tipo]
            for k = #lista + 1, #(a[tipo] or {}) do
                lista[k] = referencia(tipo)
            end
        end
    end
    for _, id in ipairs(Ayudas.ordenadas(estado.ciudades)) do
        local c = estado.ciudades[id]
        explicito(c, 'lanzacohetes')
        explicito(c, 'parque')
        if c.recuperando then
            modelos(c.recuperando.danos)
        end
        for _, o in ipairs(c.fabrica or {}) do
            if o.tropa ~= 'soldados' then
                o.modelo = o.modelo or referencia(o.tropa)
            end
        end
    end
    for _, id in ipairs(Ayudas.ordenadas(estado.instalaciones)) do
        explicito(estado.instalaciones[id], 'lanzacohetes')
    end
    for _, id in ipairs(Ayudas.ordenadas(estado.grupos)) do
        local g = estado.grupos[id]
        explicito(g, 'lanzacohetes')
        modelos(g.averias)
        if type(g.carga) == 'table' then
            explicito(g.carga, 'cantidad')
        end
        if g.construye then
            explicito(g.construye, 'lanzacohetes')
        end
    end
end

local publicas = {
    'eraDe',
    'puedeFabricarModelo',
    'modelosFabricables',
    'modeloPorDefecto',
    'modeloParaNPC',
}

--- Cuelga de la clase Simulacion el armamento (`Simulacion.Armamento`) y sus
-- consultas, y pone las tecnologías de era al final de la fila.
function Armamento.instalar(clase)
    Simulacion = clase
    clase.Armamento = Armamento
    clase.armamento = Armamento.reglas
    clase.fichaModelo = Armamento.ficha
    clase.nombreModelo = Armamento.nombre
    clase.desglose = Armamento.desglose
    clase.tecnologiasQueCuentan = Armamento.tecnologiasQueCuentan
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Armamento[nombre]
    end
    Armamento.usarCatalogo(Armamento.reglas.catalogo)
end

return Armamento

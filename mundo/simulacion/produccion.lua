--- Producción, inventario, sueldos y dinero del trabajo: la economía cerrada (diseno/economia.md).
--
-- Nada nace solo: toda unidad y toda munición se encarga con la misma orden,
-- para el jugador y para los NPC:
--
--   ejecutar({ tipo = 'producir', nacion, ciudad, tropa, cantidad, modelo })
--     tropa: 'soldados', 'lanzacohetes' (unidades; `cantidad` = unidades) o
--     'balas', 'misiles' (munición; `cantidad` = lotes). Sin tanques ni
--     obuses desde el 19-nov. También vale el singular ('soldado', 'bala'...) y la forma
--     del diseño `{ municion = 'balas', lotes = n }`. Los vehículos son de un
--     `modelo` (armamento.lua: 'scudb'); sin él, el que da
--     `modeloPorDefecto`. Coste y días, los del modelo. Devuelve el id de la
--     orden, o false y el motivo (ver `puedeProducir`).
--   ejecutar({ tipo = 'cancelarProduccion', nacion, ciudad, orden })
--     devuelve `devolucion` (50 %) de lo que aún no salió.
--   sim:puedeProducir(nacion, ciudad, tropa, cantidad, modelo) -> true, coste,
--     dias, modelo o false, motivo: 'noEsSuya', 'tropa', 'modelo' (no es de
--     esa tropa), 'impago', 'sitiada' (solo unidades),
--     'era' (modelo de una era que no tiene), 'cantidad', 'tope', 'poblacion'
--     (soldados), 'dinero', 'metal', 'petroleo'. Sin efectos: sirve al
--     Arsenal para enseñar el motivo y el máximo.
--   sim:maximoProducible(nacion, ciudad, tropa, modelo) -> la mayor cantidad
--     que hoy pasaría `puedeProducir` (0 si ninguna).
--
-- Se paga todo al encargar, primero de afuera. Las unidades van a la cola de
-- la ciudad (`c.fabrica`): cada día avanzan las primeras `nivel` órdenes y
-- cada una entrega una tanda (F2) cada `dias[tropa]` días; con la ciudad
-- sitiada la cola no avanza. La munición va aparte (`c.fabricaMunicion`), sin
-- líneas ni tope: todos sus lotes salen a la vez al cumplirse sus días,
-- también en asedio. Lo terminado entra ese día en la ciudad (los
-- lanzacohetes, en sus plataformas y lo que no cabe en el parque, `c.parque`).
--
-- Estado (solo datos):
--   c.fabrica = { { id, tropa, cantidad (lo que falta), dias (de la tanda en curso), modelo } }
--   c.fabricaMunicion = { { id, municion, lotes, dias (los que faltan) } }
--   c.siguienteOrden, c.parque, c.municion = { balas, misiles }
--   n.impago (true el día en que no pagó los sueldos enteros)
--
-- Módulo de `mundo/simulacion.lua`: `Produccion.instalar(Simulacion)` cuelga sus
-- funciones y `Simulacion.produccion` (las reglas, públicas para el Arsenal).
-- Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local esCiudad = Ayudas.esCiudad
local tropasVacias = Ayudas.tropasVacias

local Produccion = {}

-- Se fija en `instalar`: la clase.
local Simulacion

--- Reglas de la economía cerrada (F1 a F12 de diseno/economia.md). Públicas:
-- el Arsenal lee de aquí costos, días y topes.
Produccion.reglas = {
    -- F1: costo de una unidad (se paga al encargar).
    coste = {
        soldados = { dinero = 1 },
        lanzacohetes = { dinero = 40, metal = 6, petroleo = 2 },
    },
    civiles = { soldados = 1 }, -- F1: civiles que deja de trabajar cada unidad
    -- F2: días por tanda y unidades por tanda.
    dias = { soldados = 2, lanzacohetes = 6 },
    tanda = { soldados = 50, lanzacohetes = 1 },
    minimoCiviles = 0.8, -- F1b de antes: ya no se usa (el tope sale de los aptos, diseno/poblacion.md F6)
    -- F3: tope por nivel de la ciudad (1 a 5). Los lanzacohetes: sus
    -- plataformas (`Simulacion.topeLanzacohetes`) más `lanzacohetesBase` por base.
    tope = {
        soldados = { 1000, 2000, 3000, 4500, 6000 },
        lanzacohetesBase = 6,
    },
    -- F4 y F6: munición. `porDia` es el gasto de una unidad en un día de
    -- batalla simulada; `porDisparo`, lo que gasta cada disparo en la escena
    -- 3D (las balas, por soldado de la escuadra: una ráfaga de una figura de N
    -- soldados gasta 5 × N).
    municion = {
        balas = { tropa = 'soldados', lote = 10000, coste = { dinero = 1 }, dias = 1, porDia = 550, porDisparo = 5 },
        misiles = {
            tropa = 'lanzacohetes',
            lote = 10,
            coste = { dinero = 12, metal = 1, petroleo = 1 },
            dias = 1,
            porDia = 7,
            porDisparo = 1,
        },
    },
    fuego = 0.8, -- F6: parte del combate que una unidad dispara (ya va dentro de `porDia`)
    dotacion = { atacar = 5, mover = 5, guarnicion = 5, recolectar = 2 }, -- F5: días de batalla que se lleva un grupo
    reservaMunicion = 5, -- NPC: días de batalla de su ejército que quiere en el polvorín
    umbralAbasto = 2, -- días de munición por debajo de los que se avisa (y la NPC manda un convoy)
    muertos = 0.4, -- F11b: parte de los soldados que caen que muere
    -- F12: lo que cuesta reparar un vehículo con daño 1 (× su daño), al salir del taller.
    reparacion = {
        lanzacohetes = { dinero = 16, metal = 3 },
    },
    sueldo = { soldados = 0.01, lanzacohetes = 0.2 }, -- F7: dinero al día por unidad
    desercion = 0.02, -- F8: parte de la guarnición que se licencia al día sin paga o sin comida
    -- F9: petróleo al día de cada vehículo.
    combustible = {
        parado = { lanzacohetes = 0.01 },
        marcha = { lanzacohetes = 0.15 },
    },
    devolucion = 0.5, -- lo que se devuelve al cancelar (de lo que aún no salió)
    -- F2b: dinero del trabajo = trabajadores × base × (1 + tecnologia × nivel
    -- de tecnología) × hambre × f(vida) × presupuesto × parte.
    -- base: por trabajador de 15 a 64 años que no está en filas (diseno/poblacion.md F8).
    trabajo = { base = 0.022, tecnologia = 0.15, presupuesto = 0.6, parte = 0.65 },
    figuras = 48, -- F10: figuras de infantería por bando en la escena 3D
    -- NPC: parte del tope que quiere en paz (parteBase + parteAgresividad × agresividad); en guerra, 1.
    parteBase = 0.6,
    parteAgresividad = 0.4,
}

local UNIDADES = { 'soldados', 'lanzacohetes' }
local TODOS_MODELOS = Armamento.modelos()
local CAMPOS_CIUDAD = { 'lanzacohetes', 'parque' }
local ESTADOS = { 'sanos', 'heridos', 'fabrica' }
local VEHICULOS = { 'lanzacohetes' }
local MUNICIONES = { 'balas', 'misiles' }
local RECURSOS = { 'dinero', 'metal', 'petroleo' }
Produccion.UNIDADES = UNIDADES
Produccion.MUNICIONES = MUNICIONES

local SINGULAR = {
    soldado = 'soldados',
    lanzacohete = 'lanzacohetes',
    bala = 'balas',
    misil = 'misiles',
}

--- Nombre canónico de lo que se produce ('soldado' -> 'soldados'...).
function Produccion.normalizar(tropa)
    return SINGULAR[tropa] or tropa
end

--- ¿Es munición (y no una unidad)?
function Produccion.esMunicion(tropa)
    return Simulacion.produccion.municion[tropa] ~= nil
end

local function municionVacia()
    return { balas = 0, misiles = 0 }
end
Produccion.municionVacia = municionVacia

-- Inventario -----------------------------------------------------------------------------------

--- Inventario de una ciudad (o de la nación): unidades por tipo contando
-- todo lo suyo (`soldados`, `lanzacohetes`: sanas, heridas o
-- averiadas y en fábrica), el detalle `sanos`, `heridos` y `fabrica`, el de
-- cada modelo de vehículo (`modelos[id] = { sanos, heridos, fabrica }`) y la
-- munición (en el polvorín y en sus grupos: `municion`; encargada:
-- `fabricaMunicion`).
local function inventarioVacio()
    return {
        soldados = 0,
        lanzacohetes = 0,
        sanos = tropasVacias(),
        heridos = tropasVacias(),
        fabrica = tropasVacias(),
        modelos = {},
        municion = municionVacia(),
        fabricaMunicion = municionVacia(),
    }
end
Produccion.inventarioVacio = inventarioVacio

--- Ciudad de `nid` a la que pertenece el sitio `s` (una ciudad suya, o la
-- suya más cercana a él); sin sitio, su capital o su primera ciudad.
function Produccion:ciudadDeSitio(nid, s)
    if s and esCiudad(s) and s.nacion == nid then
        return s
    end
    if s then
        local c = self:ciudadDuena(nid, s.x, s.y)
        if c then
            return c
        end
    end
    local n = self.estado.naciones[nid]
    local capital = n and self.estado.ciudades[n.capital]
    if capital and capital.nacion == nid then
        return capital
    end
    return self:ciudadesDe(nid)[1]
end

--- Ciudad a la que pertenece un grupo: la de su sitio de origen (o de salida).
function Produccion:ciudadDeGrupo(g)
    return self:ciudadDeSitio(g.nacion, self:sitio(g.origen or g.desde))
end

--- Suma `v` de `tropa` al campo `campo` ('sanos', 'heridos' o 'fabrica') del
-- inventario y a su total.
local function anotarUnidades(inv, campo, tropa, v)
    if v and v ~= 0 then
        inv[campo][tropa] = inv[campo][tropa] + v
        inv[tropa] = inv[tropa] + v
    end
end

--- Suma `v` del modelo `id` al campo `campo` de su detalle en el inventario.
local function anotarModelo(inv, campo, id, v)
    if v and v > 0 then
        local m = inv.modelos[id]
        if not m then
            m = { sanos = 0, heridos = 0, fabrica = 0 }
            inv.modelos[id] = m
        end
        m[campo] = m[campo] + v
    end
end

--- Suma al detalle por modelo del inventario los vehículos de `q[campo]`
-- (`campo` 'lanzacohetes', 'parque' o 'cantidad'); lo que no está
-- desglosado, al de referencia. Sin tablas nuevas: se llama muchas veces al día.
local function anotarDesglose(inv, estado, q, campo)
    local total = q[campo] or 0
    if total <= 0 then
        return
    end
    local tipo = Armamento.TIPO_CAMPO[campo]
    local por = q[Armamento.POR[campo]]
    if not por then
        anotarModelo(inv, estado, Armamento.referencia(tipo), total)
        return
    end
    local puestos = 0
    for _, id in ipairs(Armamento.Catalogo.orden[tipo]) do
        local k = por[id]
        if k and k > 0 then
            k = math.min(k, total - puestos)
            anotarModelo(inv, estado, id, k)
            puestos = puestos + k
        end
    end
    if puestos < total then
        anotarModelo(inv, estado, Armamento.referencia(tipo), total - puestos)
    end
end

--- Suma los averiados de unas averías (`cuantos` de cada tipo) a su modelo.
local function anotarAverias(inv, averias, cuantos)
    for _, tipo in ipairs(VEHICULOS) do
        for k = 1, cuantos and cuantos[tipo] or 0 do
            anotarModelo(inv, 'heridos', Armamento.modeloAveria(averias, tipo, k), 1)
        end
    end
end

local function anotarMunicion(inv, campo, m)
    if m then
        for _, tipo in ipairs(MUNICIONES) do
            inv[campo][tipo] = inv[campo][tipo] + (m[tipo] or 0)
        end
    end
end

--- Inventario de la nación `nid`: `{ total = inventario, ciudades = { [cid] =
-- inventario } }` (ver `inventarioVacio`). Cada unidad cuenta una vez, en un
-- solo estado; las de bases, campamentos y grupos, en la ciudad a la que
-- pertenecen. Suma enteros: no depende del orden.
function Produccion:inventario(nid)
    -- Mientras la IA planea (`planearProduccion`) se reutiliza el suyo, que
    -- `producir` mantiene al día: no se vuelve a contar todo en cada orden.
    local enCurso = self.inventarioEnCurso
    if enCurso and enCurso.nid == nid then
        return enCurso.inventario
    end
    local e = self.estado
    local total = inventarioVacio()
    local porCiudad = {}
    local function de(c)
        if not c then
            return nil
        end
        local inv = porCiudad[c.id]
        if not inv then
            inv = inventarioVacio()
            porCiudad[c.id] = inv
        end
        return inv
    end
    local function unidades(c, campo, tropa, v)
        anotarUnidades(total, campo, tropa, v)
        local inv = de(c)
        if inv then
            anotarUnidades(inv, campo, tropa, v)
        end
    end
    local function municion(c, campo, m)
        anotarMunicion(total, campo, m)
        local inv = de(c)
        if inv then
            anotarMunicion(inv, campo, m)
        end
    end
    -- Modelos: los vehículos de `q[campo]`, o las averías de `averias`. Van a
    -- la ciudad (el total los suma al final) o, sin ciudad, al total.
    local function modelos(c, estado, q, campo)
        anotarDesglose(de(c) or total, estado, q, campo)
    end
    local function averiados(c, averias, cuantos)
        anotarAverias(de(c) or total, averias, cuantos)
    end
    for _, c in ipairs(self:ciudadesDe(nid)) do
        de(c)
        for _, tropa in ipairs(UNIDADES) do
            unidades(c, 'sanos', tropa, c[tropa] or 0)
        end
        unidades(c, 'sanos', 'lanzacohetes', c.parque or 0)
        for _, campo in ipairs(CAMPOS_CIUDAD) do
            modelos(c, 'sanos', c, campo)
        end
        local r = c.recuperando
        if r then
            for _, tropa in ipairs(UNIDADES) do
                unidades(c, 'heridos', tropa, r[tropa])
            end
            averiados(c, r.danos, r)
        end
        for _, o in ipairs(c.fabrica or {}) do
            unidades(c, 'fabrica', o.tropa, o.cantidad)
            if o.tropa ~= 'soldados' then
                anotarModelo(de(c), 'fabrica', o.modelo or Armamento.referencia(o.tropa), o.cantidad)
            end
        end
        municion(c, 'municion', c.municion)
        for _, o in ipairs(c.fabricaMunicion or {}) do
            local lote = Simulacion.produccion.municion[o.municion].lote
            municion(c, 'fabricaMunicion', { [o.municion] = o.lotes * lote })
        end
    end
    for _, i in ipairs(self:instalacionesDe(nid)) do
        local c = self:ciudadDeSitio(nid, i)
        for _, tropa in ipairs(UNIDADES) do
            unidades(c, 'sanos', tropa, i[tropa] or 0)
        end
        for _, tipo in ipairs(VEHICULOS) do
            modelos(c, 'sanos', i, tipo)
        end
    end
    for _, g in ipairs(self:gruposDe(nid)) do
        local c = self:ciudadDeGrupo(g)
        for _, tropa in ipairs(UNIDADES) do
            unidades(c, 'sanos', tropa, g[tropa] or 0)
            if g.heridos then
                unidades(c, 'heridos', tropa, g.heridos[tropa])
            end
        end
        for _, tipo in ipairs(VEHICULOS) do
            modelos(c, 'sanos', g, tipo)
        end
        if g.heridos then
            averiados(c, g.averias, g.heridos)
        end
        if type(g.carga) == 'table' and g.carga.tipo == 'lanzacohetes' then
            unidades(c, 'sanos', 'lanzacohetes', g.carga.cantidad)
            modelos(c, 'sanos', g.carga, 'cantidad')
        end
        if g.construye and (g.construye.lanzacohetes or 0) > 0 then
            unidades(c, 'sanos', 'lanzacohetes', g.construye.lanzacohetes)
            modelos(c, 'sanos', g.construye, 'lanzacohetes')
        end
        municion(c, 'municion', g.municion)
    end
    -- El detalle por modelo del total: la suma del de cada ciudad (enteros).
    for _, c in ipairs(self:ciudadesDe(nid)) do
        for _, id in ipairs(TODOS_MODELOS) do
            local m = porCiudad[c.id].modelos[id]
            if m then
                for _, campo in ipairs(ESTADOS) do
                    anotarModelo(total, campo, id, m[campo])
                end
            end
        end
    end
    return { total = total, ciudades = porCiudad }
end

--- Inventario de una ciudad (ver `inventario`).
function Produccion:inventarioCiudad(cid)
    local c = self.estado.ciudades[cid]
    if not c then
        return inventarioVacio()
    end
    return self:inventario(c.nacion).ciudades[cid] or inventarioVacio()
end

--- Bases terminadas que abastece la ciudad `c` (su ciudad propia más cercana).
function Produccion:basesDeCiudad(c)
    local out = {}
    for _, b in ipairs(self:instalacionesDe(c.nacion, 'base')) do
        if b.progreso >= 1 and self:ciudadDuena(c.nacion, b.x, b.y) == c then
            out[#out + 1] = b
        end
    end
    return out
end

--- Tope de `tropa` de la ciudad `c` (F3).
function Produccion:topeCiudad(c, tropa)
    local tope = Simulacion.produccion.tope
    if tropa == 'lanzacohetes' then
        return Simulacion.topeLanzacohetes(c) + tope.lanzacohetesBase * #self:basesDeCiudad(c)
    end
    local tabla = tope[tropa]
    return tabla[math.max(1, math.min(#tabla, c.nivel or 1))]
end

--- Soldados en instrucción de una ciudad (los de sus órdenes de fábrica).
function Produccion.enInstruccion(c)
    local total = 0
    for _, o in ipairs(c.fabrica or {}) do
        if o.tropa == 'soldados' then
            total = total + o.cantidad
        end
    end
    return total
end

--- Soldados que la ciudad aún puede encargar (diseno/poblacion.md F6): en
-- filas como mucho `parte` de sus aptos (18 a 49 años, hombres y mujeres);
-- `inv` es su inventario.
function Produccion.maximoSoldados(c, inv)
    local d = c.demografia
    if not d then
        return 0
    end
    return math.floor(Simulacion.Poblacion.aptos(d) * Simulacion.poblacion.parte) - inv.soldados
end

-- Encargar ---------------------------------------------------------------------------------------

--- ¿Es un vehículo (lleva modelo)?
local function esVehiculo(tropa)
    return tropa == 'lanzacohetes'
end

--- Coste de `cantidad` de `tropa` (unidades, o lotes de munición); un
-- vehículo, el de su `modelo` (sin él, el de referencia).
function Produccion.costeDe(tropa, cantidad, modelo)
    local reglas = Simulacion.produccion
    local k = reglas.municion[tropa] and reglas.municion[tropa].coste or reglas.coste[tropa]
    if esVehiculo(tropa) then
        k = Armamento.coste(modelo or Armamento.referencia(tropa))
    end
    local out = {}
    for _, r in ipairs(RECURSOS) do
        out[r] = (k[r] or 0) * cantidad
    end
    return out
end

--- Días de una tanda de `tropa` (F2); un vehículo, los de su `modelo`.
local function diasTanda(tropa, modelo)
    if esVehiculo(tropa) then
        return Armamento.dias(modelo or Armamento.referencia(tropa))
    end
    return Simulacion.produccion.dias[tropa]
end

--- Días que tarda una orden sola en su línea (F2), o los de un lote (F4).
function Produccion.diasDe(tropa, cantidad, modelo)
    local reglas = Simulacion.produccion
    if reglas.municion[tropa] then
        return reglas.municion[tropa].dias
    end
    return math.ceil(cantidad / reglas.tanda[tropa]) * diasTanda(tropa, modelo)
end

--- ¿Puede `nid` encargar `cantidad` de `tropa` (de `modelo`, si es un
-- vehículo) en su ciudad `cid`? Devuelve true, el coste ({ dinero, metal,
-- petroleo }), los días y el modelo (nil si no es un vehículo), o false y el
-- motivo, comprobado en este orden: 'noEsSuya', 'tropa', 'modelo',
-- 'impago', 'sitiada', 'tecnologia', 'era', 'cantidad', 'tope', 'poblacion',
-- 'dinero', 'metal', 'petroleo'. No cambia nada.
function Produccion:puedeProducir(nid, cid, tropa, cantidad, modelo)
    local e = self.estado
    local reglas = Simulacion.produccion
    local n, c = e.naciones[nid], e.ciudades[cid]
    if not (n and c) or c.nacion ~= nid then
        return false, 'noEsSuya'
    end
    tropa = Produccion.normalizar(tropa)
    local municion = reglas.municion[tropa] ~= nil
    if not municion and not reglas.coste[tropa] then
        return false, 'tropa'
    end
    if esVehiculo(tropa) then
        modelo = modelo or self:modeloPorDefecto(nid, tropa)
        if Armamento.tipoDe(modelo) ~= tropa then
            return false, 'modelo'
        end
    else
        modelo = nil
    end
    if n.impago then
        return false, 'impago'
    end
    if not municion and self:sitiada(c) then
        return false, 'sitiada'
    end
    if modelo then
        local puede, motivo = self:puedeFabricarModelo(nid, modelo)
        if not puede then
            return false, motivo
        end
    end
    if type(cantidad) ~= 'number' or cantidad < 1 or cantidad ~= math.floor(cantidad) then
        return false, 'cantidad'
    end
    if not municion then
        local inv = self:inventarioCiudad(cid)
        if inv[tropa] + cantidad > self:topeCiudad(c, tropa) then
            return false, 'tope'
        end
        if tropa == 'soldados' and cantidad > Produccion.maximoSoldados(c, inv) then
            return false, 'poblacion'
        end
    end
    local coste = Produccion.costeDe(tropa, cantidad, modelo)
    for _, r in ipairs(RECURSOS) do
        if Simulacion.disponible(n, r) < coste[r] then
            return false, r
        end
    end
    return true, coste, Produccion.diasDe(tropa, cantidad, modelo), modelo
end

--- Lo más que `nid` puede encargar hoy de `tropa` (de `modelo`) en `cid` (0
-- si nada): lo que pasa `puedeProducir`, sin mirar reservas.
function Produccion:maximoProducible(nid, cid, tropa, modelo)
    tropa = Produccion.normalizar(tropa)
    local puede, _, _, elegido = self:puedeProducir(nid, cid, tropa, 1, modelo)
    if not puede then
        return 0
    end
    local e = self.estado
    local reglas = Simulacion.produccion
    local n, c = e.naciones[nid], e.ciudades[cid]
    local maximo = math.huge
    if not reglas.municion[tropa] then
        local inv = self:inventarioCiudad(cid)
        maximo = self:topeCiudad(c, tropa) - inv[tropa]
        if tropa == 'soldados' then
            maximo = math.min(maximo, Produccion.maximoSoldados(c, inv))
        end
    end
    local unidad = Produccion.costeDe(tropa, 1, elegido)
    for _, r in ipairs(RECURSOS) do
        if unidad[r] > 0 then
            maximo = math.min(maximo, math.floor(Simulacion.disponible(n, r) / unidad[r] + 1e-9))
        end
    end
    return math.max(0, maximo)
end

--- Encarga `cantidad` de `tropa` (de `modelo`) en la ciudad `cid` (ver la
-- cabecera). Devuelve el id de la orden, o false y el motivo.
function Produccion:producir(nid, cid, tropa, cantidad, modelo)
    tropa = Produccion.normalizar(tropa)
    local puede, coste, _, elegido = self:puedeProducir(nid, cid, tropa, cantidad, modelo)
    if not puede then
        return false, coste
    end
    local e = self.estado
    local c = e.ciudades[cid]
    Simulacion.pagar(e.naciones[nid], coste)
    local id = c.siguienteOrden or 1
    c.siguienteOrden = id + 1
    if Simulacion.produccion.municion[tropa] then
        c.fabricaMunicion = c.fabricaMunicion or {}
        table.insert(
            c.fabricaMunicion,
            { id = id, municion = tropa, lotes = cantidad, dias = Simulacion.produccion.municion[tropa].dias }
        )
    else
        c.fabrica = c.fabrica or {}
        table.insert(c.fabrica, { id = id, tropa = tropa, cantidad = cantidad, dias = 0, modelo = elegido })
        if tropa == 'soldados' then
            -- Desde ahora están en filas (en instrucción): salen de los civiles aptos.
            self:reclutar(c, cantidad)
        end
    end
    local enCurso = self.inventarioEnCurso
    if enCurso and enCurso.nid == nid then
        local inv = enCurso.inventario
        inv.ciudades[cid] = inv.ciudades[cid] or inventarioVacio()
        for _, i in ipairs({ inv.total, inv.ciudades[cid] }) do
            if Simulacion.produccion.municion[tropa] then
                i.fabricaMunicion[tropa] = i.fabricaMunicion[tropa]
                    + cantidad * Simulacion.produccion.municion[tropa].lote
            else
                anotarUnidades(i, 'fabrica', tropa, cantidad)
                if elegido then
                    anotarModelo(i, 'fabrica', elegido, cantidad)
                end
            end
        end
    end
    return id
end

--- Cancela la orden `ordenId` de la ciudad `cid`: devuelve `devolucion` del
-- coste de lo que aún no salió (lo que no quepa, afuera). Los soldados en
-- instrucción vuelven a trabajar. Devuelve true, o false y el motivo.
function Produccion:cancelarProduccion(nid, cid, ordenId)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    if not (n and c) or c.nacion ~= nid then
        return false, 'noEsSuya'
    end
    for _, campo in ipairs({ 'fabrica', 'fabricaMunicion' }) do
        local cola = c[campo]
        for k, o in ipairs(cola or {}) do
            if o.id == ordenId then
                table.remove(cola, k)
                if #cola == 0 then
                    c[campo] = nil
                end
                local coste = Produccion.costeDe(o.tropa or o.municion, o.cantidad or o.lotes, o.modelo)
                for _, r in ipairs(RECURSOS) do
                    self:ingresar(n, r, coste[r] * Simulacion.produccion.devolucion)
                end
                if o.tropa == 'soldados' then
                    self:volverACasa(c, o.cantidad)
                end
                return true
            end
        end
    end
    return false, 'orden'
end

--- Pone `cantidad` lanzacohetes (de los modelos de `por`; sin él o si no
-- llega, de referencia) en el sitio `s`: en sus plataformas hasta su tope y
-- lo que no cabe en el parque de su ciudad (nunca se desguazan). Los modelos
-- se reparten en proporción entre plataformas y parque.
function Produccion:colocarLanzacohetes(s, cantidad, por)
    if cantidad <= 0 then
        return
    end
    -- Una copia: `por` puede ser parte del estado de quien los trae.
    local llegan = { cantidad = 0 }
    Armamento.meterPor(llegan, 'cantidad', por)
    llegan.cantidad = cantidad
    local caben = math.max(0, math.min(cantidad, Simulacion.topeLanzacohetes(s) - (s.lanzacohetes or 0)))
    s.lanzacohetes = s.lanzacohetes or 0
    Armamento.mover(llegan, 'cantidad', s, 'lanzacohetes', caben)
    local sobran = cantidad - caben
    if sobran > 0 then
        local c = self:ciudadDeSitio(s.nacion, s) or s
        c.parque = c.parque or 0
        Armamento.mover(llegan, 'cantidad', c, 'parque', sobran)
    end
end

--- Lo terminado entra en la ciudad: soldados a su guarnición,
-- lanzacohetes a sus plataformas o a su parque; los vehículos, de su `modelo`.
function Produccion:entregarUnidades(c, tropa, cantidad, modelo)
    if tropa == 'lanzacohetes' then
        self:colocarLanzacohetes(c, cantidad, { [modelo or Armamento.referencia(tropa)] = cantidad })
    else
        c[tropa] = (c[tropa] or 0) + cantidad
    end
    self:medir('producido|' .. tropa, cantidad, c.nacion)
    if modelo then
        self:medir('producido|' .. modelo, cantidad, c.nacion)
    end
end

--- Un día de las fábricas de una ciudad (ver la cabecera).
function Produccion:avanzarFabrica(c)
    local reglas = Simulacion.produccion
    local cola = c.fabrica
    if cola and not self:sitiada(c) then
        local lineas = c.nivel or 1
        local k = 1
        while k <= #cola and lineas > 0 do
            local o = cola[k]
            lineas = lineas - 1
            o.dias = o.dias + 1
            if o.dias >= diasTanda(o.tropa, o.modelo) then
                local sale = math.min(reglas.tanda[o.tropa], o.cantidad)
                o.cantidad = o.cantidad - sale
                o.dias = 0
                self:entregarUnidades(c, o.tropa, sale, o.modelo)
            end
            if o.cantidad <= 0 then
                table.remove(cola, k)
            else
                k = k + 1
            end
        end
        if #cola == 0 then
            c.fabrica = nil
        end
    end
    local municion = c.fabricaMunicion
    if municion then
        local quedan = {}
        for _, o in ipairs(municion) do
            o.dias = o.dias - 1
            if o.dias <= 0 then
                local cantidad = o.lotes * reglas.municion[o.municion].lote
                c.municion = c.municion or municionVacia()
                c.municion[o.municion] = c.municion[o.municion] + cantidad
                self:medir('municionHecha|' .. o.municion, cantidad)
            else
                quedan[#quedan + 1] = o
            end
        end
        c.fabricaMunicion = #quedan > 0 and quedan or nil
    end
end

-- Medidas (fuera del estado) ---------------------------------------------------------------------

--- Suma `valor` a la medida `clave` (y a `clave|nid` si se da la nación) en
-- `self.medidas`, una tabla que no es estado ni se guarda: solo existe si la
-- pone quien mide (las pruebas, tools/medir_economia_nationsrts.lua).
function Produccion:medir(clave, valor, nid)
    local m = self.medidas
    if not m or not valor or valor == 0 then
        return
    end
    m[clave] = (m[clave] or 0) + valor
    if nid then
        local suya = clave .. '|' .. nid
        m[suya] = (m[suya] or 0) + valor
    end
end

-- Dinero del trabajo y sueldos ------------------------------------------------------------------

--- Dinero del trabajo de una ciudad (F2b), antes de repartir: trabajadores ×
-- base × (1 + tecnología) × hambre × f(vida). `soldados` son todos los de la
-- ciudad (dentro, fuera, heridos y en instrucción).
function Produccion.trabajoCiudad(n, c, soldados)
    local reglas = Simulacion.produccion.trabajo
    -- Trabajan los de 15 a 64 años que no están en filas (diseno/poblacion.md F8).
    local enEdad = c.demografia and Simulacion.Poblacion.enEdadDeTrabajar(c.demografia) or c.poblacion
    local trabajadores = math.max(0, enEdad - soldados)
    -- Las tecnologías de era no cuentan (P7 de diseno/catalogo-armamento.md).
    return trabajadores
        * reglas.base
        * (1 + Simulacion.tecnologiasQueCuentan(n) * reglas.tecnologia)
        * (c.hambre and Simulacion.consumo.trabajoHambre or 1)
        * Simulacion.efectoVida(c.vida or Simulacion.vidaCiudad.maxima)
end

--- Munición de tipo `m` que gasta en un día de batalla todo lo sano del
-- inventario `inv` (F4): los misiles, según el modelo de cada lanzacohetes.
function Produccion.necesidadDia(inv, m)
    local k = Simulacion.produccion.municion[m]
    if not esVehiculo(k.tropa) then
        return inv.sanos[k.tropa] * k.porDia
    end
    local suma = 0
    for _, id in ipairs(Armamento.Catalogo.orden[k.tropa]) do
        local modelo = inv.modelos[id]
        if modelo then
            suma = suma + modelo.sanos * Armamento.factores[id].municion
        end
    end
    return k.porDia * suma
end

--- Dinero que entra al tesoro por `produccion` de trabajo (F2b).
function Produccion.dineroDelTrabajo(produccion)
    local reglas = Simulacion.produccion.trabajo
    return produccion * reglas.presupuesto * reglas.parte
end

--- Licencia `parte` de la guarnición de la ciudad `c` (F8): vuelven a ser
-- civiles (siguen en la población). Devuelve cuántos.
function Produccion:licenciar(c, parte)
    local idos = math.min(c.soldados, math.floor(c.soldados * Simulacion.produccion.desercion * parte + 0.5))
    c.soldados = c.soldados - idos
    self:volverACasa(c, idos)
    self:medir('licenciados', idos, c.nacion)
    return idos
end

--- Sueldos del día (F7) de todo lo que tiene la nación salvo lo que está en
-- fábrica; cada vehículo, el de su modelo. Si no alcanza, paga lo que puede,
-- queda en impago (`n.impago`, que rechaza encargos) y licencia parte de sus
-- guarniciones (F8).
function Produccion:pagarSueldos(n, inv)
    local sueldo = Simulacion.produccion.sueldo
    local debe = (inv.sanos.soldados + inv.heridos.soldados) * sueldo.soldados
    for _, tipo in ipairs(VEHICULOS) do
        for _, id in ipairs(Armamento.Catalogo.orden[tipo]) do
            local m = inv.modelos[id]
            if m then
                debe = debe + (m.sanos + m.heridos) * Armamento.sueldo(id)
            end
        end
    end
    local paga = math.min(debe, math.max(0, Simulacion.disponible(n, 'dinero')))
    if paga > 0 then
        Simulacion.pagar(n, { dinero = paga })
    end
    self:medir('sueldos', paga)
    n.impago = nil
    if debe - paga > 1e-9 then
        n.impago = true
        for _, c in ipairs(self:ciudadesDe(n.id)) do
            self:licenciar(c, (debe - paga) / debe)
        end
    end
end

-- Ciudades cedidas ---------------------------------------------------------------------------------

--- La nación dueña de `c` se la cede a `nid` (una paz con concesión). Las
-- unidades no se capturan (decisión del dueño): todo lo suyo vuelve a la
-- capital de la que cede, al momento: guarnición, parque, polvorín, taller y
-- fábricas. La ciudad pasa vacía. Devuelve true, o false si la que cede no
-- tiene otra capital a la que volver.
function Produccion:cederCiudad(c, nid)
    local e = self.estado
    local n = e.naciones[c.nacion]
    local capital = n and e.ciudades[n.capital]
    if not capital or capital == c or capital.nacion ~= n.id then
        return false
    end
    for _, tropa in ipairs(UNIDADES) do
        if tropa == 'lanzacohetes' then
            local cuantos = (c.lanzacohetes or 0) + (c.parque or 0)
            local por = Armamento.vaciar(c, 'lanzacohetes')
            local sobre = { cantidad = 0 }
            Armamento.meterPor(sobre, 'cantidad', por)
            Armamento.meterPor(sobre, 'cantidad', Armamento.vaciar(c, 'parque'))
            self:colocarLanzacohetes(capital, cuantos, sobre.cantidadPor)
        else
            capital[tropa] = (capital[tropa] or 0) + (c[tropa] or 0)
        end
        c[tropa] = 0
    end
    c.parque = nil
    capital.municion = capital.municion or municionVacia()
    for _, m in ipairs(MUNICIONES) do
        capital.municion[m] = capital.municion[m] + (c.municion and c.municion[m] or 0)
    end
    c.municion = municionVacia()
    local r = c.recuperando
    if r then
        self:sumarCola(capital, r.soldados, Simulacion.averiasDe(r, r.danos))
        c.recuperando = nil
    end
    for _, campo in ipairs({ 'fabrica', 'fabricaMunicion' }) do
        for _, o in ipairs(c[campo] or {}) do
            o.id = capital.siguienteOrden or 1
            capital.siguienteOrden = o.id + 1
            capital[campo] = capital[campo] or {}
            table.insert(capital[campo], o)
        end
        c[campo] = nil
    end
    -- Su gente en filas se muda a la capital; los civiles se quedan (diseno/poblacion.md 3.10).
    Simulacion.Poblacion.mudarFilasA(c, capital)
    -- Los grupos que salieron de ella pasan a ser de la capital.
    for _, g in ipairs(self:gruposDe(n.id)) do
        if (g.origen or g.desde) == c.id then
            g.origen = capital.id
        end
    end
    c.nacion = nid
    self:ensuciar()
    return true
end

-- NPC: la misma orden que el jugador (3.12) ----------------------------------------------------

--- Cuántas unidades de `coste` (por unidad) puede pagar `n` sin bajar de sus
-- reservas: `reservaTesoro` de dinero, `reservaMetal` y lo que ahorra para su
-- mejora (`n.plan`) de metal y petróleo.
local function pagables(n, coste)
    local plan = n.plan or {}
    local libre = {
        dinero = Simulacion.disponible(n, 'dinero') - Simulacion.recuperacion.reservaTesoro,
        metal = Simulacion.disponible(n, 'metal') - Simulacion.consumo.reservaMetal - (plan.metal or 0),
        petroleo = Simulacion.disponible(n, 'petroleo') - (plan.petroleo or 0),
    }
    local cuantas = math.huge
    for _, r in ipairs(RECURSOS) do
        if (coste[r] or 0) > 0 then
            cuantas = math.min(cuantas, math.floor(libre[r] / coste[r]))
        end
    end
    return math.max(0, cuantas)
end

--- La política de producción del presidente NPC (3.12), con `producir`:
-- primero munición hasta `reservaMunicion` días de su ejército sano (contando
-- la de sus grupos y la que ya encargó); después, sin asedio, soldados
-- hasta `parte` de su tope y lanzacohetes hasta el tope, lo que pueda
-- pagar sin tocar sus reservas.
function Produccion:planearProduccion(n)
    if n.jugador or n.impago then
        return
    end
    local reglas = Simulacion.produccion
    local enGuerra = self:numeroGuerras(n.id) > 0
    local parte = enGuerra and 1 or (reglas.parteBase + reglas.parteAgresividad * n.gobernante.agresividad)
    local inv = self:inventario(n.id)
    self.inventarioEnCurso = { nid = n.id, inventario = inv }
    local function puedePagar(coste)
        return pagables(n, coste) >= 1
    end
    -- Lo que fabrica hoy (no cambia mientras planea).
    local fabricables = {}
    for _, tipo in ipairs(VEHICULOS) do
        fabricables[tipo] = self:modelosFabricables(n.id, tipo)
    end
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        inv.ciudades[c.id] = inv.ciudades[c.id] or inventarioVacio()
        local i = inv.ciudades[c.id]
        for _, m in ipairs(MUNICIONES) do
            local k = reglas.municion[m]
            local falta = Produccion.necesidadDia(i, m) * reglas.reservaMunicion - i.municion[m] - i.fabricaMunicion[m]
            if falta > 0 then
                local lotes = math.min(math.ceil(falta / k.lote), pagables(n, k.coste))
                if lotes >= 1 then
                    self:ejecutar({ tipo = 'producir', nacion = n.id, ciudad = c.id, tropa = m, cantidad = lotes })
                end
            end
        end
        if not self:sitiada(c) then
            local quiere = math.min(
                math.floor(self:topeCiudad(c, 'soldados') * parte) - i.soldados,
                Produccion.maximoSoldados(c, i)
            )
            local soldados = math.min(quiere, pagables(n, reglas.coste.soldados))
            if soldados >= 1 then
                self:ejecutar({
                    tipo = 'producir',
                    nacion = n.id,
                    ciudad = c.id,
                    tropa = 'soldados',
                    cantidad = soldados,
                })
            end
            for _, tropa in ipairs(VEHICULOS) do
                local objetivo = self:topeCiudad(c, tropa)
                -- De uno en uno: cada orden ocupa su línea, con el mejor
                -- modelo que pueda pagar (sin combustible, el que menos gasta).
                for _ = 1, objetivo - i[tropa] do
                    local modelo = self:modeloParaNPC(n, tropa, puedePagar, fabricables[tropa])
                    if not modelo then
                        break
                    end
                    if
                        not self:ejecutar({
                            tipo = 'producir',
                            nacion = n.id,
                            ciudad = c.id,
                            tropa = tropa,
                            cantidad = 1,
                            modelo = modelo,
                        })
                    then
                        break
                    end
                end
            end
        end
    end
    self.inventarioEnCurso = nil
end

local publicas = {
    'medir',
    'cederCiudad',
    'ciudadDeSitio',
    'ciudadDeGrupo',
    'inventario',
    'inventarioCiudad',
    'basesDeCiudad',
    'topeCiudad',
    'puedeProducir',
    'maximoProducible',
    'producir',
    'cancelarProduccion',
    'colocarLanzacohetes',
    'entregarUnidades',
    'avanzarFabrica',
    'licenciar',
    'pagarSueldos',
    'planearProduccion',
}

--- Cuelga de la clase Simulacion las funciones y `Simulacion.produccion` (las reglas).
function Produccion.instalar(clase)
    Simulacion = clase
    clase.produccion = Produccion.reglas
    clase.inventarioVacio = inventarioVacio
    clase.municionVacia = municionVacia
    clase.esMunicion = Produccion.esMunicion
    clase.normalizarTropa = Produccion.normalizar
    clase.costeProduccion = Produccion.costeDe
    clase.diasProduccion = Produccion.diasDe
    clase.diasTanda = diasTanda
    clase.necesidadMunicion = Produccion.necesidadDia
    clase.enInstruccion = Produccion.enInstruccion
    clase.maximoSoldados = Produccion.maximoSoldados
    clase.trabajoCiudad = Produccion.trabajoCiudad
    clase.dineroDelTrabajo = Produccion.dineroDelTrabajo
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Produccion[nombre]
    end
end

return Produccion

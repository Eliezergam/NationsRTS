-- Arsenal al estilo de la pantalla de unidades de Warpath
-- (diseno/referencias-warpath/unidad_*.jpg y suministros_2.jpg): fondo claro
-- gris niebla a pantalla completa y, en el centro, el modelo 3D de lo elegido
-- en grande (interfaz/vitrina.lua: 3DreamEngine en vivo, gira despacio solo y
-- se gira arrastrando con el ratón).
--
--   * Arriba a la izquierda, la designación del modelo («T-72B») y su poder.
--   * Columna izquierda: las pestañas (Ficha, Producir, Comparar, Variantes)
--     como botones grises verticales y, debajo, las categorías con su
--     contador de modelos que puedes fabricar («2/4»).
--   * A la derecha, el panel de datos de la pestaña (cabecera oscura, cuerpo
--     claro): la ficha, o producir con la ciudad que fabrica, la cantidad, el
--     coste, los días, el motivo si no se puede y la cola de fábrica.
--   * Comparar pone el modelo frente al de la era siguiente de su tipo (o el
--     anterior frente a él, si es el más moderno) con sus cifras y una flecha.
--   * Variantes es el hueco del kit de piezas: «Próximamente».
--   * Abajo, la tira de miniaturas para cambiar de modelo, con el buscador y
--     el orden.
--
-- Economía cerrada (diseno/economia.md): todo se encarga a mano con la orden
-- `producir` en una ciudad tuya. Las unidades (soldados y lanzacohetes)
-- caben hasta el tope de su ciudad; la munición (balas y misiles) se encarga por lotes y va al polvorín. «Producir» está activo si
-- `sim:puedeProducir` lo deja; si no, se dice el motivo. «Máx» pone
-- `sim:maximoProducible`.
--
-- Catálogo de armamento (diseno/catalogo-armamento.md, §3.8): los nombres
-- salen del archivo de datos (`Simulacion.fichaModelo`), nunca de aquí. Los
-- de una era que la nación no tiene salen bloqueados y dicen qué les falta.
--
-- Solo lee la simulación. `pulsar` devuelve `cerrar`, `nada` o { comandos }
-- (los manda main.lua); la búsqueda recibe el texto de main.lua (`texto`,
-- `tecla`) y el giro del modelo, el ratón (`mover`, `soltar`).

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Clara = require('interfaz.clara')
local Paleta = require('interfaz.paleta')
local Indice = require('assets.ui.indice')
local Simulacion = require('mundo.simulacion')
local Fabrica = require('interfaz.fabrica')
local Vitrina = require('interfaz.vitrina')
local Vida = require('interfaz.vida')

local Arsenal = {}
Arsenal.__index = Arsenal

local Armamento = Simulacion.Armamento

-- Arte de cada tropa (la munición, la de la tropa que la dispara): el render
-- de respaldo si no hay 3D. El camión de misiles no tiene render (el de los
-- lanzacohetes del pack Synty se quitó el 21-nov): se ve en la vitrina 3D.
local ARTE_TROPA = { soldados = 'soldado' }

-- Giro solo del modelo (radianes por segundo) y ángulo de partida: de tres
-- cuartos, con el frente hacia la izquierda, como en Warpath.
local GIRO = 0.22
local ANGULO_INICIAL = 2.3

--- Lo que se produce hoy. `id` es la clave de la tarjeta: la tropa
-- ('soldados'), la clave del modelo ('scudb') o la munición;
-- `tropa`, lo que se encarga; `modelo`, el modelo (vehículos). La munición
-- (`municion = true`) no tiene modelo 3D: lleva el icono de la caja y el de
-- la tropa que la dispara.
local function construirUnidades()
    local out = {
        { id = 'soldados', tropa = 'soldados', nombre = 'Soldado', tipo = 'Infantería', cat = 'infanteria' },
    }
    for _, tropa in ipairs(Armamento.TIPOS) do
        for _, id in ipairs(Armamento.modelos(tropa)) do
            local ficha = Simulacion.fichaModelo(id)
            local clase = ficha.real.tipo or 'Lanzacohetes'
            out[#out + 1] = {
                id = id,
                tropa = tropa,
                modelo = id,
                nombre = ficha.nombre,
                era = ficha.era,
                clase = clase,
                tipo = string.format('Era %d · %s', ficha.era, clase),
                cat = ficha.categoria,
            }
        end
    end
    out[#out + 1] = {
        id = 'balas',
        tropa = 'balas',
        nombre = 'Balas',
        tipo = 'Munición de los soldados',
        cat = 'municion',
        municion = true,
    }
    out[#out + 1] = {
        id = 'misiles',
        tropa = 'misiles',
        nombre = 'Misiles',
        tipo = 'Munición de los lanzacohetes',
        cat = 'municion',
        municion = true,
    }
    return out
end

local UNIDADES = construirUnidades()
local POR_ID = {}
for _, u in ipairs(UNIDADES) do
    POR_ID[u.id] = u
end

-- Categorías de la columna izquierda (solo las que tienen unidades): cada una
-- junta categorías del catálogo.
local CATEGORIAS = {
    {
        id = 'artilleria',
        nombre = 'Artillería y cohetes',
        icono = 'cat_artilleria',
        cats = { artilleria = true, misiles = true },
    },
    { id = 'infanteria', nombre = 'Infantería', icono = 'soldado', cats = { infanteria = true } },
    { id = 'municion', nombre = 'Munición', icono = 'suministros', cats = { municion = true } },
}
local CATEGORIA = {}
for _, c in ipairs(CATEGORIAS) do
    CATEGORIA[c.id] = c
end

-- Pestañas de la columna izquierda.
local PESTANAS = {
    { id = 'ficha', texto = 'Ficha' },
    { id = 'producir', texto = 'Producir' },
    { id = 'comparar', texto = 'Comparar' },
    { id = 'variantes', texto = 'Variantes' },
}

local ORDENES = { 'Poder', 'Nombre', 'Existencias' }

-- Posición de cada cosa en `UNIDADES` (para ordenar la munición).
local posicion = {}
for k, u in ipairs(UNIDADES) do
    posicion[u.id] = k
end

--- ¿Entra la unidad `u` en la categoría `cat` de la columna?
local function enCategoria(u, cat)
    local c = CATEGORIA[cat]
    return c ~= nil and c.cats[u.cat] == true
end

--- Categoría de la columna de una unidad.
local function categoriaDe(u)
    for _, c in ipairs(CATEGORIAS) do
        if c.cats[u.cat] then
            return c.id
        end
    end
    return CATEGORIAS[1].id
end

--- Los modelos del mismo tipo de la era anterior y la siguiente más cercanas
-- (Comparar): devuelve el más antiguo y el más moderno de la pareja, o nil.
local function parComparar(u)
    if not u.modelo then
        return nil
    end
    local siguiente, anterior
    for _, id in ipairs(Armamento.modelos(u.tropa)) do
        local era = Simulacion.fichaModelo(id).era
        if era > u.era and (not siguiente or era < Simulacion.fichaModelo(siguiente).era) then
            siguiente = id
        elseif era < u.era and (not anterior or era > Simulacion.fichaModelo(anterior).era) then
            anterior = id
        end
    end
    if siguiente then
        return u.id, siguiente
    elseif anterior then
        return anterior, u.id
    end
    return nil
end

function Arsenal.nuevo()
    local self = setmetatable({}, Arsenal)
    self.abierto = false
    self.cat = 'infanteria'
    self.sel = 'soldados'
    self.pestana = 'ficha'
    self.orden = 1
    self.busqueda = ''
    self.buscando = false
    self.cantidad = 1
    self.zonas = {}
    self.ayuda = nil
    self.imagenes = {}
    self.ciudad = nil -- id de la ciudad que fabrica (nil: tu capital)
    self.mensaje = nil -- { texto, color, hasta }: lo que pasó con el último encargo
    self.vitrina = Vitrina.nueva()
    self.angulo = ANGULO_INICIAL
    self.giro = nil -- { x }: arrastrando el modelo
    self.reloj = nil
    self.inicioTira = 0
    return self
end

--- Abre el arsenal; con `ciudad` (id), fabricando en ella.
function Arsenal:abrir(ciudad)
    self.abierto = true
    self.buscando = false
    self.cantidad = 1
    self.mensaje = nil
    self.giro = nil
    if ciudad then
        self.ciudad = ciudad
    end
end

--- Ciudad tuya que fabrica: la elegida si sigue siendo tuya o tu capital (o
-- la primera). Devuelve la ciudad y la lista de tus ciudades.
function Arsenal:ciudadElegida(sim, nid)
    local ciudades = sim:ciudadesDe(nid)
    local c = self.ciudad and sim.estado.ciudades[self.ciudad]
    if not c or c.nacion ~= nid then
        local n = sim:nacion(nid)
        c = n and sim.estado.ciudades[n.capital]
        if not c or c.nacion ~= nid then
            c = ciudades[1]
        end
        self.ciudad = c and c.id or nil
    end
    return c, ciudades
end

--- Resultado de mandar los comandos de `pulsar` (main.lua lo llama).
function Arsenal:resultado(ok, texto)
    self.mensaje = { texto = texto, color = ok and 'verde' or 'rojoTexto', hasta = love.timer.getTime() + 4 }
end

function Arsenal:cerrar()
    self.abierto = false
    self.buscando = false
    self.giro = nil
end

--- Imagen de arte de una unidad (se carga una vez): el render de su tropa,
-- de respaldo si no hay 3D.
function Arsenal:arte(unidad, cual)
    local clave = ARTE_TROPA[unidad.tropa]
    if unidad.municion then
        clave = ARTE_TROPA[Simulacion.produccion.municion[unidad.id].tropa]
    elseif unidad.modelo and Indice.arsenal[unidad.modelo] then
        clave = unidad.modelo
    end
    local datos = clave and Indice.arsenal[clave]
    local ruta = datos and datos[cual] or ('sin render:' .. cual)
    local img = self.imagenes[ruta]
    if not img then
        if datos and love.filesystem.getInfo(Indice.carpeta .. ruta, 'file') then
            img = love.graphics.newImage(Indice.carpeta .. ruta)
        else
            -- Sin el render (no lo tiene, o la copia pública del código va
            -- sin los de pago): una imagen transparente de su tamaño, el
            -- hueco queda vacío.
            local ancho, alto = 200, 120
            if cual == 'detalle' then
                ancho, alto = 520, 230
            end
            img = love.graphics.newImage(love.image.newImageData(ancho, alto))
        end
        img:setFilter('linear', 'linear')
        self.imagenes[ruta] = img
    end
    return img
end

--- Minúsculas sin acentos, para buscar.
local function normal(texto)
    local mapa = { ['á'] = 'a', ['é'] = 'e', ['í'] = 'i', ['ó'] = 'o', ['ú'] = 'u', ['ñ'] = 'n', ['ü'] = 'u' }
    return (texto:lower():gsub('[\195][\128-\191]', mapa))
end

--- Existencias de una nación: los soldados, en ciudades y bases y en
-- ejércitos; la munición, en los polvorines y en los ejércitos. Los vehículos
-- van por modelo (`existenciasModelos`).
local function existencias(sim, nid)
    local r = {}
    for _, u in ipairs(UNIDADES) do
        r[u.id] = { sitios = 0, ejercitos = 0 }
    end
    local function sumar(lista, campo)
        for _, s in ipairs(lista) do
            for _, u in ipairs(UNIDADES) do
                if u.municion then
                    if s.municion then
                        r[u.id][campo] = r[u.id][campo] + (s.municion[u.id] or 0)
                    end
                elseif not u.modelo then
                    r[u.id][campo] = r[u.id][campo] + (s[u.id] or 0)
                end
            end
        end
    end
    sumar(sim:ciudadesDe(nid), 'sitios')
    local instalaciones = {}
    for _, i in ipairs(sim:instalacionesDe(nid)) do
        -- Las instalaciones no tienen polvorín propio (dispara el de su ciudad).
        instalaciones[#instalaciones + 1] = { soldados = i.soldados }
    end
    sumar(instalaciones, 'sitios')
    local grupos = {}
    for _, id in ipairs(Simulacion.ordenadas(sim.estado.grupos)) do
        local g = sim.estado.grupos[id]
        if g.nacion == nid then
            grupos[#grupos + 1] = g
        end
    end
    sumar(grupos, 'ejercitos')
    return r
end

--- Lo que le falta a la nación `nid` para fabricar el modelo `id` (nil si
-- puede): la frase entera («era 3: control de tiro digital») y la corta
-- («Requiere era 3»).
local function bloqueo(sim, nid, id)
    local puede, motivo = sim:puedeFabricarModelo(nid, id)
    if puede then
        return nil
    end
    local era = Simulacion.fichaModelo(id).era
    return Fabrica.requisito(id) or motivo, 'Requiere era ' .. era
end

--- Datos vivos de cada unidad (poder, fuerza, existencias, recuperación y,
-- los modelos, sus sanos, averiados, en fábrica y lo que les falta) y de la
-- ciudad que fabrica (inventario, topes, polvorín y cola).
function Arsenal:datos(sim, nid)
    local ahora = love.timer.getTime()
    local c = self:ciudadElegida(sim, nid)
    local cache = self.cache
    local vale = cache and cache.nid == nid and cache.sim == sim and cache.ciudad == (c and c.id)
    if vale and ahora - cache.tiempo < 0.5 and cache.dia == sim.estado.dia and not self.sucio then
        return cache
    end
    self.sucio = false
    local nivel = c and c.nivel or 1
    local ex = existencias(sim, nid)
    local modelos = sim:inventario(nid).total.modelos
    local porUnidad = {}
    for _, u in ipairs(UNIDADES) do
        local d
        if u.modelo then
            local ficha = Simulacion.fichaModelo(u.modelo)
            local falta, corta = bloqueo(sim, nid, u.modelo)
            local m = modelos[u.modelo] or {}
            d = {
                ficha = ficha,
                poder = ficha.juego.poder,
                fuerza = ficha.juego.poder / Simulacion.escalaPoder,
                sitios = m.sanos or 0,
                ejercitos = 0,
                total = m.sanos or 0,
                heridos = m.heridos or 0,
                fabrica = m.fabrica or 0,
                bloqueo = falta,
                bloqueoCorto = corta,
                ritmo = ficha.juego.ritmoTaller * nivel,
            }
        else
            local poder = u.municion and 0 or Simulacion.poderUnidad(u.id)
            d = {
                poder = poder,
                fuerza = poder / Simulacion.escalaPoder,
                sitios = ex[u.id].sitios,
                ejercitos = ex[u.id].ejercitos,
                total = ex[u.id].sitios + ex[u.id].ejercitos,
                ritmo = u.municion and 0 or Simulacion.recuperacion.ritmo[u.id] * nivel,
                precio = u.municion and 0 or Simulacion.recuperacion.precio[u.id],
            }
        end
        porUnidad[u.id] = d
    end
    local n = sim:nacion(nid)
    self.cache = {
        tiempo = ahora,
        dia = sim.estado.dia,
        nid = nid,
        sim = sim,
        ciudad = c and c.id,
        nivel = nivel,
        unidades = porUnidad,
        color = n and n.color or { 0.75, 0.62, 0.2 },
        inventario = c and sim:inventarioCiudad(c.id),
        polvorin = c and sim:polvorin(c.id),
        cola = c and sim:colaFabrica(c.id),
    }
    return self.cache
end

--- Zona que se puede pulsar en este cuadro.
function Arsenal:zona(x, y, w, h, accion, dato)
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, accion = accion, dato = dato }
end

--- Número con coma decimal y hasta un decimal (5,5).
local function decimal(v)
    if math.abs(v - math.floor(v)) < 0.05 then
        return Tema.numero(v)
    end
    return (string.format('%.1f', v):gsub('%.', ','))
end

--- Número con coma decimal y hasta `cifras` decimales, sin ceros de más (0,063).
local function decimales(v, cifras)
    local texto = string.format('%.' .. cifras .. 'f', v):gsub('0+$', ''):gsub('%.$', '')
    return (texto:gsub('%.', ','))
end

--- Lista filtrada y ordenada de unidades: las de la categoría o, con algo
-- escrito en el buscador, las de todas que coincidan.
function Arsenal:lista(datos)
    local salida = {}
    local buscar = normal(self.busqueda)
    for _, u in ipairs(UNIDADES) do
        local vale
        if buscar ~= '' then
            vale = normal(u.nombre):find(buscar, 1, true) or normal(u.tipo):find(buscar, 1, true)
        else
            vale = enCategoria(u, self.cat)
        end
        if vale then
            salida[#salida + 1] = u
        end
    end
    local orden = self.orden
    table.sort(salida, function(a, b)
        local da, db = datos.unidades[a.id], datos.unidades[b.id]
        -- Lo que aún no se puede fabricar (falta su era), al final.
        if (da.bloqueo ~= nil) ~= (db.bloqueo ~= nil) then
            return db.bloqueo ~= nil
        end
        if orden == 2 then
            return a.nombre < b.nombre
        elseif orden == 3 and da.total ~= db.total then
            return da.total > db.total
        elseif orden == 1 and da.poder ~= db.poder then
            return da.poder > db.poder
        elseif orden == 1 and a.municion and b.municion then
            -- La munición no tiene poder: balas y misiles, como sus tropas.
            return posicion[a.id] < posicion[b.id]
        end
        return a.nombre < b.nombre
    end)
    return salida
end

-- Dibujo: piezas de la familia de niebla -----------------------------------------------------

local vineta -- imagen de la viñeta del fondo

--- Fondo claro gris niebla de pantalla completa: cielo, horizonte claro y
-- suelo de estudio con unas líneas de fuga muy tenues.
local function fondoNiebla()
    local g = love.graphics
    local w, h = g.getDimensions()
    local horizonte = math.floor(h * 0.5)
    Tema.degradado(0, 0, w, horizonte, { 0.74, 0.75, 0.765 }, { 0.92, 0.925, 0.93 })
    Tema.degradado(0, horizonte, w, h - horizonte, { 0.9, 0.905, 0.91 }, { 0.76, 0.765, 0.775 })
    -- Brillo del horizonte.
    Tema.degradado(0, horizonte - h * 0.06, w, h * 0.06, { 0.93, 0.93, 0.935 }, { 0.96, 0.96, 0.965 }, 0.0)
    g.setColor(1, 1, 1, 0.35)
    g.rectangle('fill', 0, horizonte - 1, w, 2)
    -- Líneas de fuga del suelo, hacia el centro del horizonte.
    g.setColor(0.45, 0.46, 0.48, 0.07)
    g.setLineWidth(1)
    for k = -9, 9 do
        g.line(w / 2 + k * w * 0.02, horizonte, w / 2 + k * w * 0.22, h)
    end
    for k = 1, 6 do
        local t = (k / 6) ^ 2
        g.line(0, horizonte + (h - horizonte) * t, w, horizonte + (h - horizonte) * t)
    end
    if not vineta then
        local datos = love.image.newImageData(64, 64)
        datos:mapPixel(function(px, py)
            local dx, dy = (px + 0.5) / 32 - 1, (py + 0.5) / 32 - 1
            local d = math.min(1, math.sqrt(dx * dx + dy * dy) / 1.3)
            return 0.3, 0.31, 0.33, math.max(0, d - 0.4) * 0.6
        end)
        vineta = love.graphics.newImage(datos)
        vineta:setFilter('linear', 'linear')
    end
    g.setColor(1, 1, 1, 1)
    g.draw(vineta, 0, 0, 0, w / 64, h / 64)
end

--- Texto blanco con una sombra suave (sobre los botones grises).
local function textoSombra(fuente, texto, x, y, color, alfa)
    local g = love.graphics
    g.setFont(fuente)
    g.setColor(0, 0, 0, 0.55 * (alfa or 1))
    g.print(texto, x + 1, y + 1)
    if color then
        g.setColor(color[1], color[2], color[3], alfa or 1)
    else
        g.setColor(0.97, 0.97, 0.95, alfa or 1)
    end
    g.print(texto, x, y)
end

--- Botón gris vertical de Warpath: degradado gris oscuro con filo claro; el
-- activo, crema con el texto apagado; el desactivado, gris lavado. Devuelve
-- si el ratón está encima.
local function botonGris(x, y, w, h, texto, estado, opciones)
    opciones = opciones or {}
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, w, h)
    if estado == 'normal' and encima then
        estado = love.mouse.isDown(1) and 'pulsado' or 'resaltado'
    end
    local baja = estado == 'pulsado' and 1 or 0
    -- Vida (interfaz/vida.lua): crece un poco con el ratón encima y se hunde
    -- al pulsar; el texto no se escala.
    if estado ~= 'desactivado' and estado ~= 'activo' then
        local crece, hunde = Vida.boton(Vida.claveRect('g', x, y, w, h), encima, estado == 'pulsado')
        local m = Tema.escala() * (crece * 5 - hunde * 2)
        x, y, w, h = x - m, y - m + hunde * Tema.escala() * 2, w + m * 2, h + m * 2
    end
    -- Sombra de abajo.
    g.setColor(0, 0, 0, 0.25)
    g.rectangle('fill', x + 1, y + 2, w, h)
    if estado == 'activo' then
        Tema.degradado(x, y, w, h, { 0.95, 0.94, 0.88 }, { 0.84, 0.83, 0.76 })
    elseif estado == 'desactivado' then
        Tema.degradado(x, y, w, h, { 0.6, 0.6, 0.6 }, { 0.5, 0.5, 0.5 }, 0.85)
    elseif estado == 'resaltado' then
        Tema.degradado(x, y, w, h, { 0.4, 0.4, 0.4 }, { 0.26, 0.26, 0.26 })
    elseif estado == 'pulsado' then
        Tema.degradado(x, y, w, h, { 0.2, 0.2, 0.2 }, { 0.28, 0.28, 0.28 })
    else
        Tema.degradado(x, y, w, h, { 0.33, 0.33, 0.33 }, { 0.19, 0.19, 0.19 })
    end
    -- Filo claro y brillo de arriba.
    g.setLineWidth(math.max(1, Tema.px(2)))
    g.setColor(0.86, 0.86, 0.84, estado == 'activo' and 0.9 or 0.75)
    g.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    g.setLineWidth(1)
    g.setColor(1, 1, 1, estado == 'activo' and 0.5 or 0.12)
    g.rectangle('fill', x + 2, y + 2, w - 4, 1)
    local fuente = opciones.fuente or Acero.fuente('boton', 24)
    local lineas = { texto }
    local _, partes = fuente:getWrap(texto, w - Tema.px(20))
    if #partes > 1 then
        lineas = { partes[1], table.concat(partes, ' ', 2) }
    end
    local icono = opciones.icono
    local lado = icono and math.floor(math.min(h * 0.55, fuente:getHeight() * 1.1)) or 0
    local cuenta = opciones.cuenta
    local fc = Acero.fuente('etiqueta', 16)
    local anchoCuenta = cuenta and (fc:getWidth(cuenta) + Tema.px(14)) or 0
    local libre = w - Tema.px(16) - (icono and (lado + Tema.px(8)) or 0) - anchoCuenta
    local altoTexto = #lineas * fuente:getHeight()
    local ty = math.floor(y + (h - altoTexto) / 2) + baja
    local colorTexto
    local alfa = 1
    if estado == 'activo' then
        colorTexto = { 0.5, 0.5, 0.46 }
    elseif estado == 'desactivado' then
        colorTexto = { 0.86, 0.86, 0.84 }
        alfa = 0.85
    end
    local tx0 = x + Tema.px(8) + (icono and (lado + Tema.px(8)) or 0)
    for k, linea in ipairs(lineas) do
        linea = Tema.cortar(fuente, linea, libre)
        local tx = icono and tx0 or math.floor(x + (w - fuente:getWidth(linea)) / 2)
        local ly = ty + (k - 1) * fuente:getHeight()
        if estado == 'activo' then
            g.setFont(fuente)
            g.setColor(colorTexto[1], colorTexto[2], colorTexto[3], 1)
            g.print(linea, tx, ly)
        else
            textoSombra(fuente, linea, tx, ly, colorTexto, alfa)
        end
    end
    if icono then
        local c = estado == 'activo' and 'tintaTenue' or 'textoHud'
        Acero.icono(icono, x + Tema.px(10), y + (h - lado) / 2 + baja, lado, c, estado == 'desactivado' and 0.7 or 1)
    end
    if cuenta then
        g.setFont(fc)
        local cw = anchoCuenta
        local ch = fc:getHeight() + Tema.px(4)
        local cx = x + w - cw - Tema.px(6)
        local cy = y + (h - ch) / 2 + baja
        g.setColor(0, 0, 0, estado == 'activo' and 0.12 or 0.35)
        g.rectangle('fill', cx, cy, cw, ch, Tema.px(3), Tema.px(3))
        g.setColor(estado == 'activo' and 0.3 or 0.95, estado == 'activo' and 0.3 or 0.95, 0.9, 1)
        g.print(cuenta, cx + (cw - fc:getWidth(cuenta)) / 2, cy + Tema.px(2))
    end
    if opciones.nota then
        -- Etiqueta pequeña en la esquina (Próximamente).
        local fn = Acero.fuente('etiqueta', 13)
        local nw = fn:getWidth(opciones.nota) + Tema.px(12)
        local nh = fn:getHeight() + Tema.px(2)
        g.setColor(0.18, 0.18, 0.18, 0.92)
        g.rectangle('fill', x + w - nw, y - nh / 2, nw, nh)
        g.setFont(fn)
        g.setColor(0.95, 0.85, 0.45, 1)
        g.print(opciones.nota, x + w - nw + Tema.px(6), y - nh / 2 + Tema.px(1))
    end
    return encima
end

--- Panel de datos de la derecha (suministros_2.jpg): cabecera oscura con
-- rayas finas en las esquinas y cuerpo claro. Devuelve el rectángulo del
-- cuerpo (x, y, w, h).
local function panelDatos(x, y, w, h, titulo, subtitulo, insignia)
    local g = love.graphics
    local px = Tema.px
    local ft = Acero.fuente('titulo', 30)
    local fs = Acero.fuente('cuerpo', 17)
    local ch = math.max(math.floor(h * 0.13), ft:getHeight() + (subtitulo and fs:getHeight() or 0) + px(36))
    -- Sombra del panel.
    g.setColor(0, 0, 0, 0.18)
    g.rectangle('fill', x + px(4), y + px(6), w, h)
    Tema.degradado(x, y, w, ch, { 0.36, 0.36, 0.36 }, { 0.24, 0.24, 0.24 })
    -- Rayas diagonales en las esquinas de abajo.
    g.setScissor(x, y, w, ch)
    g.setColor(1, 1, 1, 0.07)
    g.setLineWidth(math.max(1, px(3)))
    for k = 0, 1 do
        g.line(x + px(10) + k * px(14), y + ch, x + px(40) + k * px(14), y + ch - px(60))
        g.line(x + w - px(40) - k * px(14), y + ch, x + w - px(10) - k * px(14), y + ch - px(60))
    end
    g.setLineWidth(1)
    g.setScissor()
    local pad = px(18)
    local libre = w - pad * 2 - (insignia and px(70) or 0)
    g.setFont(ft)
    g.setColor(0.97, 0.97, 0.95, 1)
    g.print(Tema.cortar(ft, titulo, libre), x + pad, y + px(14))
    if subtitulo then
        g.setFont(fs)
        g.setColor(0.8, 0.8, 0.78, 1)
        g.print(Tema.cortar(fs, subtitulo, libre), x + pad, y + px(14) + ft:getHeight())
    end
    if insignia then
        -- Insignia de la era en un hexágono (la «VI» de Warpath).
        local r = px(30)
        local cx, cy = x + w - pad - r, y + ch / 2
        Clara.hexagonoPlano(cx, cy, r, 'hexMetal', 'hexMetalClaro')
        local fi = Acero.fuente('titulo', 30)
        g.setFont(fi)
        g.setColor(0.95, 0.95, 0.92, 1)
        g.print(insignia, math.floor(cx - fi:getWidth(insignia) / 2), math.floor(cy - fi:getHeight() / 2))
    end
    Tema.degradado(x, y + ch, w, h - ch, { 0.9, 0.9, 0.9 }, { 0.83, 0.83, 0.83 })
    g.setColor(0.6, 0.6, 0.6, 1)
    g.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    return x, y + ch, w, h - ch
end

--- Barra negra de título de sección (como IMAGEN en las opciones).
local function barraSeccion(x, y, w, texto)
    local g = love.graphics
    local f = Acero.fuente('boton', 19)
    local h = f:getHeight() + Tema.px(10)
    g.setColor(0.1, 0.1, 0.1, 0.92)
    g.rectangle('fill', x, y, w, h)
    g.setFont(f)
    g.setColor(0.95, 0.95, 0.93, 1)
    g.print(Tema.cortar(f, texto, w - Tema.px(20)), x + Tema.px(10), y + Tema.px(5))
    return h
end

--- Fila de datos del cuerpo claro: etiqueta gris a la izquierda y valor negro
-- a la derecha, sobre franjas alternas.
local function filaDato(x, y, w, h, etiqueta, valor, k, colorValor)
    local g = love.graphics
    local f = Acero.fuente('cuerpo', 16)
    local fv = Acero.fuente('cifra', 16)
    g.setColor(0, 0, 0, k % 2 == 1 and 0.07 or 0.03)
    g.rectangle('fill', x, y, w, h)
    g.setFont(f)
    Tema.color('tintaTenue')
    g.print(Tema.cortar(f, etiqueta, w * 0.58), x + Tema.px(10), y + (h - f:getHeight()) / 2)
    g.setFont(fv)
    Tema.color(colorValor or 'tinta')
    local v = Tema.cortar(fv, valor, w * 0.4)
    g.print(v, x + w - Tema.px(10) - fv:getWidth(v), y + (h - fv:getHeight()) / 2)
end

--- Barra de estadística sobre el cuerpo claro.
local function barra(x, y, w, etiqueta, icono, parte, valor)
    local g = love.graphics
    local px = Tema.px
    local fuente = Acero.fuente('cuerpo', 16)
    Acero.icono(icono, x, y + px(1), px(22), 'tintaTenue')
    g.setFont(fuente)
    Tema.color('tinta')
    g.print(etiqueta, x + px(30), y)
    local bx = x + px(170)
    local bw = w - px(170) - px(100)
    local by = y + (fuente:getHeight() - px(12)) / 2
    local bh = px(12)
    g.setColor(0.62, 0.62, 0.62, 1)
    g.rectangle('fill', bx, by, bw, bh)
    local rw = math.max(0, math.floor((bw - 2) * math.max(0, math.min(1, parte))))
    Tema.degradado(bx + 1, by + 1, rw, bh - 2, { 0.5, 0.72, 0.26 }, { 0.32, 0.55, 0.14 })
    g.setFont(Acero.fuente('cifra', 16))
    Tema.color('tinta')
    g.print(valor, bx + bw + px(12), y)
end

--- Pastilla clara inclinada con un icono a color y una cifra (el poder de
-- unidad_1_modelo.jpg). Devuelve su ancho.
local function pastillaPoder(x, y, h, icono, texto, colorTexto)
    local g = love.graphics
    local f = Acero.fuente('cifra', 24)
    local lado = math.floor(h * 0.86)
    local w = lado + Tema.px(14) + f:getWidth(texto) + Tema.px(36)
    local corte = math.floor(h * 0.45)
    g.setColor(0, 0, 0, 0.2)
    g.polygon('fill', x + 2, y + 3, x + w + 2, y + 3, x + w - corte + 2, y + h + 3, x + 2, y + h + 3)
    g.setColor(0.95, 0.95, 0.95, 0.92)
    g.polygon('fill', x, y, x + w, y, x + w - corte, y + h, x, y + h)
    g.setColor(0.3, 0.3, 0.3, 0.6)
    g.setLineWidth(1)
    g.polygon('line', x + 0.5, y + 0.5, x + w - 0.5, y + 0.5, x + w - corte, y + h - 0.5, x + 0.5, y + h - 0.5)
    if Indice.iconosColor[icono] then
        Acero.iconoColor(icono, x + Tema.px(4), y + (h - lado) / 2, lado)
    else
        Acero.icono(icono, x + Tema.px(4), y + (h - lado) / 2, lado, 'tinta')
    end
    g.setFont(f)
    Tema.color(colorTexto or 'tinta')
    g.print(texto, x + lado + Tema.px(12), y + (h - f:getHeight()) / 2)
    return w
end

--- Recuadro de la munición en el centro (no tiene modelo 3D): la caja y el
-- icono de la tropa que la dispara, con su sombra en el suelo.
local function dibujarMunicion(u, x, y, w, h, alfa)
    local lado = math.floor(math.min(w, h) * 0.42)
    local cx, cy = x + w / 2, y + h * 0.48
    love.graphics.setColor(0.08, 0.09, 0.1, 0.12 * alfa)
    love.graphics.ellipse('fill', cx, cy + lado * 0.55, lado * 0.7, lado * 0.12)
    Acero.icono('suministros', cx - lado / 2, cy - lado / 2, lado, 'tintaTenue', 0.9 * alfa)
    local chico = math.floor(lado * 0.4)
    local tropa = Simulacion.produccion.municion[u.id].tropa
    Acero.icono(Fabrica.ICONOS[tropa], cx + lado * 0.32, cy + lado * 0.12, chico, 'tinta', alfa)
end

-- Columna izquierda ----------------------------------------------------------------------------

--- Pestañas: botones grises verticales.
function Arsenal:dibujarPestanas(x, y, w, alto, paso, unidad)
    local comparable = parComparar(unidad) ~= nil
    local mx, my = love.mouse.getPosition()
    for k, p in ipairs(PESTANAS) do
        local by = y + (k - 1) * paso
        local estado = self.pestana == p.id and 'activo' or 'normal'
        local nota
        local disponible = true
        if p.id == 'comparar' and not comparable then
            disponible = false
        elseif p.id == 'variantes' then
            nota = 'Próximamente'
        end
        if not disponible then
            estado = 'desactivado'
        end
        botonGris(x, by, w, alto, p.texto, estado, { nota = nota })
        if disponible then
            self:zona(x, by, w, alto, 'pestana', p.id)
        elseif Tema.dentro(mx, my, x, by, w, alto) then
            self.ayuda = unidad.nombre .. ' no tiene otro modelo de su tipo con el que compararse.'
        end
        if p.id == 'variantes' and Tema.dentro(mx, my, x, by, w, alto) then
            self.ayuda = 'Variantes: el kit de piezas para diseñar tus propias versiones llegará más adelante.'
        end
    end
end

--- Categorías con su contador de modelos que puedes fabricar.
function Arsenal:dibujarCategorias(x, y, w, alto, paso, datos)
    local g = love.graphics
    local fuente = Acero.fuente('boton', 17)
    g.setFont(fuente)
    Tema.color('tintaTenue')
    g.print('CATEGORÍAS', x + Tema.px(2), y)
    y = y + fuente:getHeight() + Tema.px(6)
    local mx, my = love.mouse.getPosition()
    for k, c in ipairs(CATEGORIAS) do
        local total, puedes = 0, 0
        for _, u in ipairs(UNIDADES) do
            if c.cats[u.cat] then
                total = total + 1
                if not datos.unidades[u.id].bloqueo then
                    puedes = puedes + 1
                end
            end
        end
        local by = y + (k - 1) * paso
        local activa = self.cat == c.id and self.busqueda == ''
        botonGris(x, by, w, alto, c.nombre, activa and 'activo' or 'normal', {
            icono = c.icono,
            cuenta = puedes .. '/' .. total,
            fuente = Acero.fuente('boton', 19),
        })
        self:zona(x, by, w, alto, 'categoria', c.id)
        if Tema.dentro(mx, my, x, by, w, alto) then
            self.ayuda = string.format(
                '%s: puedes fabricar %d de sus %d modelos; los demás piden una era más.',
                c.nombre,
                puedes,
                total
            )
        end
    end
end

-- Centro: el modelo ----------------------------------------------------------------------------

--- Modelo de la unidad `u` en el rectángulo, en 3D si se puede; si no, el
-- render de su tropa o, la munición, sus iconos.
function Arsenal:dibujarModelo(u, d, x, y, w, h, angulo, ranura, color)
    if u.municion then
        dibujarMunicion(u, x, y, w, h, 1)
        return
    end
    local ok = self.vitrina:dibujar(u.modelo or u.id, x, y, w, h, angulo, {
        ranura = ranura,
        color = color,
        oscuro = d.bloqueo ~= nil,
        llenar = 0.98,
    })
    if not ok then
        local img = self:arte(u, 'detalle')
        local escala = math.min(w / img:getWidth(), h / img:getHeight()) * 0.9
        love.graphics.setColor(1, 1, 1, d.bloqueo and 0.55 or 1)
        love.graphics.draw(
            img,
            x + (w - img:getWidth() * escala) / 2,
            y + (h - img:getHeight() * escala) / 2,
            0,
            escala,
            escala
        )
    end
end

--- Las cifras de un vehículo que se comparan: { etiqueta, valor, texto, mejorSiMayor }.
local function cifrasComparar(u, d)
    local juego, escena = d.ficha.juego, d.ficha.escena
    local filas = {
        { 'Poder', d.poder, decimal(d.poder), true },
        { 'Vida', juego.vida, decimal(juego.vida), true },
        { 'Golpe', juego.golpe, decimal(juego.golpe), true },
    }
    filas[#filas + 1] = { 'Proyectiles por salva', escena.proyectiles, Tema.numero(escena.proyectiles), true }
    filas[#filas + 1] = { 'Velocidad', juego.velocidad, '×' .. decimales(juego.velocidad, 2), true }
    filas[#filas + 1] = { 'Dinero por unidad', juego.coste.dinero or 0, Tema.numero(juego.coste.dinero or 0), false }
    return filas
end

--- Comparar (unidad_2_mejorar.jpg): dos modelos, sus filas y la flecha verde.
function Arsenal:dibujarComparar(u, datos, x, y, w, h, angulo)
    local g = love.graphics
    local px = Tema.px
    local viejo, nuevo = parComparar(u)
    local a, b = POR_ID[viejo], POR_ID[nuevo]
    local da, db = datos.unidades[a.id], datos.unidades[b.id]
    local fa, fb = cifrasComparar(a, da), cifrasComparar(b, db)
    local hueco = math.floor(w * 0.1)
    local cw = math.floor((w - hueco) / 2)
    local fila = math.floor(Acero.fuente('cuerpo', 18):getHeight() * 1.35)
    local fn = Acero.fuente('boton', 20)
    local etiquetaH = fn:getHeight() + px(10)
    local tablaH = #fa * (fila + px(3))
    local fBloqueo = Acero.fuente('cuerpo', 16)
    if da.bloqueo or db.bloqueo then
        tablaH = tablaH + fBloqueo:getHeight() + px(6)
    end
    local pieH = px(70)
    local modeloH = math.max(px(120), h - etiquetaH - tablaH - pieH - px(30))
    for lado = 1, 2 do
        local unidad, dato, filas = a, da, fa
        if lado == 2 then
            unidad, dato, filas = b, db, fb
        end
        local cx = x + (lado - 1) * (cw + hueco)
        self:dibujarModelo(unidad, dato, cx, y, cw, modeloH, angulo, 'comparar' .. lado, datos.color)
        local ty = y + modeloH + px(6)
        -- Etiqueta oscura con el nombre.
        local nombre = unidad.nombre .. ' · era ' .. unidad.era
        local nw = fn:getWidth(nombre) + px(24)
        g.setColor(0.16, 0.16, 0.16, 0.92)
        g.rectangle('fill', cx, ty, nw, etiquetaH)
        textoSombra(fn, nombre, cx + px(12), ty + px(5))
        if unidad.id == self.sel then
            g.setColor(0.98, 0.85, 0.35, 1)
            g.rectangle('fill', cx, ty + etiquetaH - px(3), nw, px(3))
        end
        ty = ty + etiquetaH + px(8)
        for k, f in ipairs(filas) do
            local fy = ty + (k - 1) * (fila + px(3))
            local colorValor
            if lado == 2 and f[2] ~= fa[k][2] then
                local mejor = (f[2] > fa[k][2]) == f[4]
                colorValor = mejor and Paleta.claro.verde or Paleta.claro.rojoTexto
            end
            g.setColor(0.55, 0.55, 0.55, 0.55)
            g.rectangle('fill', cx, fy, cw, fila)
            local fe = Acero.fuente('cuerpo', 18)
            g.setFont(fe)
            g.setColor(0.98, 0.98, 0.97, 1)
            g.print(f[1], cx + px(10), fy + (fila - fe:getHeight()) / 2)
            local fv = Acero.fuente('cifra', 18)
            g.setFont(fv)
            Tema.color(colorValor or 'tinta')
            g.print(f[3], cx + cw - px(10) - fv:getWidth(f[3]), fy + (fila - fv:getHeight()) / 2)
        end
        if dato.bloqueo then
            g.setFont(fBloqueo)
            Tema.color(Paleta.claro.rojoTexto)
            g.print(
                Tema.cortar(fBloqueo, 'Requiere ' .. dato.bloqueo, cw),
                cx,
                ty + #filas * (fila + px(3)) + px(4)
            )
        end
    end
    -- Flecha verde entre las dos tablas.
    local ay = y + modeloH + px(6) + etiquetaH + px(8) + #fa * (fila + px(3)) / 2
    local ax = x + cw + hueco / 2
    local s = math.min(hueco * 0.35, px(40))
    g.setColor(0.25, 0.55, 0.12, 0.35)
    for k = 0, 2 do
        g.rectangle('fill', ax - s * 1.2 + k * s * 0.18, ay - s * 0.28, s * 0.08, s * 0.56)
    end
    Tema.degradado(ax - s * 0.6, ay - s * 0.28, s * 0.7, s * 0.56, { 0.42, 0.75, 0.2 }, { 0.26, 0.55, 0.1 })
    g.setColor(0.32, 0.65, 0.14, 1)
    g.polygon('fill', ax + s * 0.1, ay - s * 0.62, ax + s * 0.8, ay, ax + s * 0.1, ay + s * 0.62)
    -- Pie: la frase y el botón para ir a la ficha del otro.
    local otro = a.id == self.sel and b or a
    local fy = y + h - pieH
    local fe = Acero.fuente('cuerpo', 17)
    g.setFont(fe)
    Tema.color('tintaTenue')
    local frase
    if db.bloqueo then
        frase = string.format('El %s llega con la era %d: más poder para tu ejército.', b.nombre, b.era)
    else
        frase = string.format('Ya puedes fabricar el %s.', b.nombre)
    end
    local bw = math.min(px(380), math.floor(w * 0.36))
    g.printf(frase, x, fy + (pieH - fe:getHeight() * 2) / 2, w - bw - px(30), 'left')
    local texto = 'Ver el ' .. otro.nombre
    Acero.boton({ texto = texto, tipo = 'principal' }, x + w - bw, fy + px(6), bw, pieH - px(12))
    self:zona(x + w - bw, fy + px(6), bw, pieH - px(12), 'verOtro', otro.id)
end

-- Panel de la derecha ---------------------------------------------------------------------------

--- Descripción de lo elegido.
local function descripcionDe(unidad, d)
    if unidad.id == 'soldados' then
        return 'La unidad básica: se recluta en las ciudades, defiende, ataca y recolecta en las minas. '
            .. 'Cada soldado deja de trabajar mientras está en armas.'
    elseif unidad.tropa == 'lanzacohetes' then
        local escena = d.ficha.escena
        local proyectiles = escena.proyectiles == 1 and '1 misil' or (Tema.numero(escena.proyectiles) .. ' cohetes')
        return string.format(
            'Cada salva lanza %s con %s m de radio de daño. En tierra pesa como %s soldados.',
            proyectiles,
            decimales(escena.radio, 1),
            decimal(d.fuerza)
        )
    end
    local m = Simulacion.produccion.municion[unidad.id]
    local tropa = Fabrica.NOMBRES[m.tropa]
    return string.format(
        'Munición de los %s: cada uno gasta %s al día de batalla. Sin ella no disparan (siguen en el campo). '
            .. 'Se fabrica por lotes de %s, también con la ciudad sitiada.',
        tropa[2],
        Tema.numero(m.porDia),
        Tema.numero(m.lote)
    )
end

--- Unos datos reales del modelo, en letra pequeña: calibre, peso y año (de
-- la ficha pública del archivo de datos).
local function datosReales(unidad, d)
    local real = d.ficha.real
    local partes = {}
    partes[#partes + 1] = 'calibre ' .. (real.calibre or 'no recogido')
    local masa = Armamento.Catalogo.lanzacohetes[unidad.modelo].masa
    partes[#partes + 1] = masa and (decimales(masa, 2) .. ' t') or 'peso no recogido'
    partes[#partes + 1] = real.anio
    return 'Real: ' .. table.concat(partes, ' · ')
end

--- Filas de la tabla de datos.
local function filasDe(unidad, d, datos, c, sim)
    local nombreCiudad = c and c.nombre or 'la ciudad'
    local filas = {}
    if unidad.municion then
        local m = Simulacion.produccion.municion[unidad.id]
        local enFabrica = datos.inventario and datos.inventario.fabricaMunicion[unidad.id] or 0
        filas[#filas + 1] =
            { 'Polvorín de ' .. nombreCiudad, Tema.numero(datos.polvorin and datos.polvorin[unidad.id] or 0) }
        filas[#filas + 1] = { 'En fábrica en ' .. nombreCiudad, Tema.numero(enFabrica) }
        filas[#filas + 1] = { 'En ejércitos', Tema.numero(d.ejercitos) }
        filas[#filas + 1] = { 'En todos tus polvorines', Tema.numero(d.sitios) }
        filas[#filas + 1] = { 'Gasto al día de batalla', Tema.numero(m.porDia) .. ' por unidad' }
        return filas
    end
    local inv = datos.inventario
    local tropa = unidad.tropa
    local tope = c and sim:topeCiudad(c, tropa) or 0
    local tiene = inv and inv[tropa] or 0
    local juego = d.ficha and d.ficha.juego
    if juego then
        filas[#filas + 1] = {
            'Petróleo en marcha',
            decimales(juego.combustible.marcha, 3) .. ' al día',
        }
    end
    filas[#filas + 1] = {
        nombreCiudad .. ' (tope nv. ' .. (c and c.nivel or 1) .. ')',
        string.format('%s / %s', Tema.numero(tiene), Tema.numero(tope)),
        color = tiene >= tope and Paleta.claro.rojoTexto or nil,
    }
    if juego then
        filas[#filas + 1] = {
            'Tienes de este modelo',
            string.format('%s sanos · %s averiados', Tema.numero(d.total), Tema.numero(d.heridos)),
        }
        local m = inv and inv.modelos[unidad.modelo]
        filas[#filas + 1] = { 'En fábrica en ' .. nombreCiudad, Tema.numero(m and m.fabrica or 0) }
        if tropa == 'lanzacohetes' then
            filas[#filas + 1] = { 'Misiles por día de batalla', decimales(juego.municion.porDia, 1) }
        end
        filas[#filas + 1] = { 'Sueldo al día', decimales(juego.sueldo, 3) .. ' de dinero' }
        filas[#filas + 1] = { 'Taller', decimales(d.ritmo, 2) .. ' de daño al día' }
        return filas
    end
    filas[#filas + 1] = { 'En fábrica en ' .. nombreCiudad, Tema.numero(inv and inv.fabrica[tropa] or 0) }
    filas[#filas + 1] = { 'En ejércitos', Tema.numero(d.ejercitos) }
    filas[#filas + 1] = { 'En ciudades y bases', Tema.numero(d.sitios) }
    filas[#filas + 1] = {
        'Sueldo al día',
        (string.format('%.2f', Simulacion.produccion.sueldo[tropa]):gsub('%.', ',')) .. ' de dinero c/u',
    }
    return filas
end

--- Números romanos de las eras (la insignia del panel).
local ROMANOS = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII' }

--- Texto en párrafo con un máximo de líneas (la última, cortada con «…»).
-- Devuelve el alto usado.
local function parrafo(fuente, texto, x, y, w, maxLineas, interlinea)
    local g = love.graphics
    local _, lineas = fuente:getWrap(texto, w)
    local n = math.min(#lineas, maxLineas)
    g.setFont(fuente)
    for k = 1, n do
        local linea = lineas[k]
        if k == n and #lineas > n then
            linea = Tema.cortar(fuente, linea .. ' ' .. lineas[k + 1], w)
        end
        g.print(linea, x, y + (k - 1) * fuente:getHeight() * interlinea)
    end
    return n * fuente:getHeight() * interlinea
end

--- Pestaña Ficha: descripción, datos reales, barras y la tabla de datos.
function Arsenal:dibujarFicha(u, d, datos, sim, x, y, w, h)
    local g = love.graphics
    local px = Tema.px
    local c = self.ciudad and sim.estado.ciudades[self.ciudad]
    local bx, by, bw, bh = panelDatos(x, y, w, h, u.nombre, u.tipo, u.era and ROMANOS[u.era] or nil)
    local pad = px(18)
    local cx, cw = bx + pad, bw - pad * 2
    local cy = by + pad
    Tema.color('tinta')
    cy = cy + parrafo(Acero.fuente('cuerpo', 17), descripcionDe(u, d), cx, cy, cw, 4, 1.25) + px(8)
    if d.ficha then
        Tema.color('tintaTenue')
        cy = cy + parrafo(Acero.fuente('etiqueta', 14), datosReales(u, d), cx, cy, cw, 2, 1.2) + px(10)
    end
    if d.bloqueo then
        Tema.color(Paleta.claro.rojoTexto)
        cy = cy + parrafo(Acero.fuente('cuerpo', 16), 'Requiere ' .. d.bloqueo .. '.', cx, cy, cw, 2, 1.2) + px(8)
    end
    -- Barras (las cifras reales de hoy; la munición no las tiene).
    if not u.municion then
        local paso = math.floor(Acero.fuente('cuerpo', 16):getHeight() * 1.6)
        if d.ficha then
            local maximo = { vida = 0, golpe = 0, alcance = 0, velocidad = 0 }
            for _, v in pairs(datos.unidades) do
                if v.ficha and v.ficha.tipo == d.ficha.tipo then
                    maximo.vida = math.max(maximo.vida, v.ficha.juego.vida)
                    maximo.golpe = math.max(maximo.golpe, v.ficha.juego.golpe)
                    maximo.alcance = math.max(maximo.alcance, v.ficha.escena.alcance)
                    maximo.velocidad = math.max(maximo.velocidad, v.ficha.juego.velocidad)
                end
            end
            local juego, escena = d.ficha.juego, d.ficha.escena
            barra(cx, cy, cw, 'Vida', 'vida', juego.vida / maximo.vida, decimal(juego.vida))
            barra(cx, cy + paso, cw, 'Golpe', 'atacar', juego.golpe / maximo.golpe, decimal(juego.golpe))
            barra(
                cx,
                cy + paso * 2,
                cw,
                'Alcance',
                'mover',
                escena.alcance / maximo.alcance,
                decimales(escena.alcance, 1) .. ' km'
            )
            barra(
                cx,
                cy + paso * 3,
                cw,
                'Velocidad',
                'ejercito',
                juego.velocidad / maximo.velocidad,
                '×' .. decimales(juego.velocidad, 2)
            )
            cy = cy + paso * 4 + px(6)
        else
            local maxFuerza, maxPoder, maxTotal = 0, 0, 1
            for id, v in pairs(datos.unidades) do
                if not Simulacion.produccion.municion[id] then
                    maxFuerza, maxPoder, maxTotal =
                        math.max(maxFuerza, v.fuerza), math.max(maxPoder, v.poder), math.max(maxTotal, v.total)
                end
            end
            barra(cx, cy, cw, 'Fuerza', 'vida', d.fuerza / maxFuerza, decimal(d.fuerza))
            barra(cx, cy + paso, cw, 'Poder', 'poder', d.poder / maxPoder, decimal(d.poder))
            barra(cx, cy + paso * 2, cw, 'Tienes', 'soldado', d.total / maxTotal, Tema.numero(d.total))
            cy = cy + paso * 3 + px(6)
        end
    end
    -- Botón de abajo: a producir.
    local qh = px(56)
    local qy = by + bh - pad - qh
    -- Tabla de datos en lo que queda.
    local filas = filasDe(u, d, datos, c, sim)
    local fh = math.floor(Acero.fuente('cuerpo', 16):getHeight() * 1.7)
    local caben = math.floor((qy - px(12) - cy) / fh)
    if caben >= #filas then
        fh = math.min(math.floor(fh * 1.8), math.floor((qy - px(12) - cy) / #filas))
    end
    for k = 1, math.min(caben, #filas) do
        local f = filas[k]
        filaDato(cx, cy, cw, fh, f[1], f[2], k, f.color)
        cy = cy + fh
    end
    -- Activo solo si se puede fabricar (igual que en la pestaña Producir); el
    -- clic lleva a esa pestaña, donde se ve el motivo.
    local nid = self.nacion
    local cantidad = math.max(1, self.cantidad)
    local puede, costeOMotivo = sim:puedeProducir(nid, self.ciudad, u.tropa, cantidad, u.modelo)
    Acero.boton({ texto = 'Producir', tipo = 'principal', icono = 'construir', activo = puede == true }, cx, qy, cw, qh)
    self:zona(cx, qy, cw, qh, 'pestana', 'producir')
    local mx, my = love.mouse.getPosition()
    if puede ~= true and Tema.dentro(mx, my, cx, qy, cw, qh) then
        self.ayuda = Fabrica.textoMotivo(sim, nid, self.ciudad, u.tropa, cantidad, costeOMotivo, u.modelo)
    end
end

--- Selector de la ciudad que fabrica: «Fábrica de» ‹ Casa · nv. 2 ›.
function Arsenal:dibujarSelectorCiudad(x, y, w, h, sim, nid)
    local g = love.graphics
    local px = Tema.px
    local c, ciudades = self:ciudadElegida(sim, nid)
    local fuente = Acero.fuente('cuerpo', 17)
    local etiqueta = 'Fábrica de'
    g.setFont(fuente)
    Tema.color('tintaTenue')
    local ew = fuente:getWidth(etiqueta)
    g.print(etiqueta, x, y + (h - fuente:getHeight()) / 2)
    local lado = h
    local bx = x + ew + px(10)
    local varias = #ciudades > 1
    Acero.boton({ texto = '‹', tipo = 'oscuro', activo = varias }, bx, y, lado, h, true)
    local nx = bx + lado + px(6)
    local nw = w - (nx - x) - lado - px(6)
    g.setColor(1, 1, 1, 0.55)
    g.rectangle('fill', nx, y, nw, h)
    g.setColor(0.45, 0.45, 0.45, 1)
    g.rectangle('line', nx + 0.5, y + 0.5, nw - 1, h - 1)
    local negrita = Acero.fuente('boton', 19)
    g.setFont(negrita)
    Tema.color('tinta')
    local nombre = c and string.format('%s · nv. %d', c.nombre, c.nivel or 1) or 'Sin ciudades'
    nombre = Tema.cortar(negrita, nombre, nw - px(12))
    g.print(nombre, nx + (nw - negrita:getWidth(nombre)) / 2, y + (h - negrita:getHeight()) / 2)
    Acero.boton({ texto = '›', tipo = 'oscuro', activo = varias }, nx + nw + px(6), y, lado, h, true)
    if varias then
        self:zona(bx, y, lado, h, 'ciudad', -1)
        self:zona(nx + nw + px(6), y, lado, h, 'ciudad', 1)
    end
    local mx, my = love.mouse.getPosition()
    if Tema.dentro(mx, my, x, y, w, h) then
        self.ayuda = 'La ciudad que fabrica lo que encargues (y cuya cola ves abajo). '
            .. 'Cada ciudad tiene su tope por nivel y su polvorín.'
    end
end

--- Filas de la cola de fábrica de la ciudad elegida.
local function filasCola(cola)
    local filas = {}
    for _, o in ipairs(cola and cola.unidades or {}) do
        local estado
        if not o.enLinea then
            estado = 'espera línea'
        elseif o.cantidad > o.tanda then
            estado = string.format(
                'tanda de %s en %s · todo en %s',
                Tema.numero(o.tanda),
                Fabrica.textoDias(o.proxima),
                Fabrica.textoDias(o.dias)
            )
        else
            estado = 'listos en ' .. Fabrica.textoDias(o.dias)
        end
        filas[#filas + 1] = {
            id = o.id,
            icono = Fabrica.ICONOS[o.tropa],
            texto = Fabrica.nombreEncargo(o.tropa, o.cantidad, o.modelo),
            estado = estado,
            devuelve = Simulacion.costeProduccion(o.tropa, o.cantidad, o.modelo),
        }
    end
    for _, o in ipairs(cola and cola.municion or {}) do
        filas[#filas + 1] = {
            id = o.id,
            icono = 'suministros',
            texto = string.format(
                '%s de %s (%s)',
                Fabrica.plural(o.lotes, 'lote', 'lotes'),
                Fabrica.NOMBRES[o.municion][2],
                Tema.numero(o.cantidad)
            ),
            estado = 'listos en ' .. Fabrica.textoDias(o.dias),
            devuelve = Simulacion.costeProduccion(o.municion, o.lotes),
        }
    end
    return filas
end

--- Cola de fábrica, con «Cancelar» en cada orden, desde `y` hasta `fondo`.
function Arsenal:dibujarCola(x, y, w, fondo, datos, sim)
    local g = love.graphics
    local px = Tema.px
    local c = self.ciudad and sim.estado.ciudades[self.ciudad]
    local cola = datos.cola
    local cabecera = 'COLA DE FÁBRICA' .. (c and (' · ' .. Tema.mayusculas(c.nombre)) or '')
    y = y + barraSeccion(x, y, w, cabecera) + px(4)
    local pequena = Acero.fuente('etiqueta', 14)
    if cola then
        g.setFont(pequena)
        Tema.color(cola.sitiada and Paleta.claro.rojoTexto or 'tintaTenue')
        local nota = string.format(
            '%d %s para unidades%s',
            cola.lineas,
            cola.lineas == 1 and 'línea' or 'líneas',
            cola.sitiada and ' · sitiada: las unidades no avanzan' or ''
        )
        g.print(Tema.cortar(pequena, nota, w), x, y)
        y = y + pequena:getHeight() + px(4)
    end
    local filas = filasCola(cola)
    local fuente = Acero.fuente('cuerpo', 16)
    if #filas == 0 then
        g.setFont(fuente)
        Tema.color('tintaTenue')
        parrafo(fuente, 'Nada en fábrica. Elige la cantidad y pulsa «Producir».', x, y + px(4), w, 2, 1.2)
        return
    end
    local alto = math.floor(fuente:getHeight() * 2.5)
    local caben = math.max(1, math.floor((fondo - y) / alto))
    local mx, my = love.mouse.getPosition()
    for k, f in ipairs(filas) do
        if k > caben then
            break
        end
        local fy = y + (k - 1) * alto
        if k == caben and #filas > caben then
            g.setFont(fuente)
            Tema.color('tintaTenue')
            g.print(string.format('… y %d encargos más', #filas - caben + 1), x, fy + px(6))
            break
        end
        g.setColor(0, 0, 0, k % 2 == 1 and 0.07 or 0.03)
        g.rectangle('fill', x, fy, w, alto - px(2))
        local ic = px(24)
        Acero.icono(f.icono, x + px(6), fy + (alto - ic) / 2, ic, 'tintaTenue')
        local bw = px(118)
        local tx = x + ic + px(14)
        local libre = w - (tx - x) - bw - px(10)
        g.setFont(fuente)
        Tema.color('tinta')
        g.print(Tema.cortar(fuente, f.texto, libre), tx, fy + px(4))
        local chica = Acero.fuente('etiqueta', 14)
        g.setFont(chica)
        Tema.color('tintaTenue')
        g.print(Tema.cortar(chica, f.estado, libre), tx, fy + px(4) + fuente:getHeight())
        local bx = x + w - bw - px(4)
        local bh = alto - px(14)
        local bby = fy + (alto - px(2) - bh) / 2
        Acero.boton({ texto = 'Cancelar', tipo = 'rojo' }, bx, bby, bw, bh, true)
        self:zona(bx, bby, bw, bh, 'cancelarOrden', f.id)
        if Tema.dentro(mx, my, bx, bby, bw, bh) then
            local parte = Simulacion.produccion.devolucion
            local partes = {}
            for _, r in ipairs({ 'dinero', 'metal', 'petroleo' }) do
                if f.devuelve[r] > 0 then
                    partes[#partes + 1] = Tema.numero(math.floor(f.devuelve[r] * parte))
                        .. ' '
                        .. (r == 'petroleo' and 'petróleo' or r)
                end
            end
            self.ayuda = string.format(
                'Cancelar la orden: devuelve el %d %% de lo que aún no salió (%s).',
                math.floor(parte * 100 + 0.5),
                table.concat(partes, ', ')
            )
        end
    end
end

--- Pestaña Producir: la ciudad, lo que cabe, cantidad, coste, días, el
-- motivo si no se puede, «Producir» y la cola de fábrica.
function Arsenal:dibujarProducir(u, d, datos, sim, nid, x, y, w, h)
    local g = love.graphics
    local px = Tema.px
    local c = self.ciudad and sim.estado.ciudades[self.ciudad]
    local bx, by, bw, bh = panelDatos(x, y, w, h, 'Producir', u.nombre .. ' · ' .. u.tipo)
    local pad = px(18)
    local cx, cw = bx + pad, bw - pad * 2
    local cy = by + pad
    self:dibujarSelectorCiudad(cx, cy, cw, px(40), sim, nid)
    cy = cy + px(40) + px(12)
    -- Dos filas de lo que importa al encargar.
    local filas = filasDe(u, d, datos, c, sim)
    local fh = math.floor(Acero.fuente('cuerpo', 16):getHeight() * 1.6)
    local elegidas = {}
    for _, f in ipairs(filas) do
        if f[1]:find('tope', 1, true) or f[1]:find('Polvorín', 1, true) or f[1]:find('En fábrica', 1, true) then
            elegidas[#elegidas + 1] = f
        end
    end
    for k, f in ipairs(elegidas) do
        filaDato(cx, cy, cw, fh, f[1], f[2], k, f.color)
        cy = cy + fh
    end
    cy = cy + px(12)
    -- Coste y días.
    local cantidad = math.max(1, self.cantidad)
    local tropa, modelo = u.tropa, u.modelo
    local puede, costeOMotivo, dias = sim:puedeProducir(nid, self.ciudad, tropa, cantidad, modelo)
    local coste = Simulacion.costeProduccion(tropa, cantidad, modelo)
    local fc = Acero.fuente('cuerpo', 17)
    local fcif = Acero.fuente('cifra', 24)
    local etiqueta
    if u.municion then
        etiqueta = string.format(
            'Coste de %s (%s)',
            Fabrica.plural(cantidad, 'lote', 'lotes'),
            Tema.numero(cantidad * Simulacion.produccion.municion[u.id].lote)
        )
    else
        etiqueta = 'Coste de ' .. Fabrica.nombreEncargo(tropa, cantidad, modelo)
    end
    local tt = 'Tiempo'
    g.setFont(fc)
    Tema.color('tintaTenue')
    g.print(Tema.cortar(fc, etiqueta, cw - fc:getWidth(tt) - px(12)), cx, cy)
    g.print(tt, cx + cw - fc:getWidth(tt), cy)
    local n = sim:nacion(nid)
    Tema.modoClaro = true
    Fabrica.dibujarCoste(coste, cx, cy + fc:getHeight(), fcif, Fabrica.falta(n, coste))
    Tema.modoClaro = false
    g.setFont(fcif)
    Tema.color('tinta')
    local textoDias = Fabrica.textoDias(dias or Simulacion.diasProduccion(tropa, cantidad, modelo))
    g.print(textoDias, cx + cw - fcif:getWidth(textoDias), cy + fc:getHeight())
    cy = cy + fc:getHeight() + fcif:getHeight() + px(6)
    -- Motivo o lo que pasó con el último encargo (dos líneas como mucho).
    local motivo
    if not puede then
        motivo = Fabrica.textoMotivo(sim, nid, self.ciudad, tropa, cantidad, costeOMotivo, modelo)
    end
    local mensaje = self.mensaje
    if mensaje and love.timer.getTime() > mensaje.hasta then
        self.mensaje = nil
        mensaje = nil
    end
    local fm = Acero.fuente('cuerpo', 16)
    local altoMotivo = fm:getHeight() * 2.4
    if mensaje then
        Tema.color(Paleta.claro[mensaje.color] or Paleta.claro.verde)
        parrafo(fm, mensaje.texto, cx, cy, cw, 2, 1.2)
    elseif motivo then
        Tema.color(Paleta.claro.rojoTexto)
        parrafo(fm, motivo, cx, cy, cw, 2, 1.2)
    end
    local mx, my = love.mouse.getPosition()
    if motivo and Tema.dentro(mx, my, cx, cy, cw, altoMotivo) then
        self.ayuda = motivo
    end
    cy = cy + altoMotivo
    -- Cantidad, «Máx» y «Producir».
    local qh = px(52)
    local qw = math.floor(qh * 3.4)
    local mitad = math.floor(qh)
    local estado = 'normal'
    if Tema.dentro(mx, my, cx, cy, mitad, qh) and love.mouse.isDown(1) then
        estado = 'menos_pulsado'
    elseif Tema.dentro(mx, my, cx + qw - mitad, cy, mitad, qh) and love.mouse.isDown(1) then
        estado = 'mas_pulsado'
    end
    Acero.pieza('selector_cantidad', estado, cx, cy, qw, qh)
    local fq = Acero.fuente('cifra', 24)
    g.setFont(fq)
    Tema.color('textoHud')
    local cifra = Tema.numero(self.cantidad)
    g.print(cifra, cx + (qw - fq:getWidth(cifra)) / 2, cy + (qh - fq:getHeight()) / 2)
    local paso = u.id == 'soldados' and 10 or 1
    self:zona(cx, cy, mitad, qh, 'cantidad', -paso)
    self:zona(cx + qw - mitad, cy, mitad, qh, 'cantidad', paso)
    local maximo = sim:maximoProducible(nid, self.ciudad, tropa, modelo)
    local maxW = px(86)
    local maxX = cx + qw + px(8)
    Acero.boton({ texto = 'Máx', tipo = 'oscuro', activo = maximo > 0 }, maxX, cy, maxW, qh, true)
    if maximo > 0 then
        self:zona(maxX, cy, maxW, qh, 'maximo', maximo)
    end
    if Tema.dentro(mx, my, maxX, cy, maxW, qh) then
        self.ayuda = maximo > 0 and ('Lo más que puedes encargar hoy aquí: ' .. Tema.numero(maximo))
            or (motivo or 'Hoy no se puede encargar más')
    end
    local pbx = maxX + maxW + px(8)
    local pbw = cx + cw - pbx
    Acero.boton({ texto = 'Producir', tipo = 'principal', activo = puede == true }, pbx, cy, pbw, qh)
    if puede then
        self:zona(pbx, cy, pbw, qh, 'producir', { tropa = tropa, cantidad = cantidad, modelo = modelo })
    elseif Tema.dentro(mx, my, pbx, cy, pbw, qh) then
        self.ayuda = motivo
    end
    cy = cy + qh + px(18)
    -- Cola de fábrica.
    self:dibujarCola(cx, cy, cw, by + bh - pad, datos, sim)
end

--- Pestaña Variantes (unidad_3_modificar.jpg): el hueco del kit de piezas,
-- con las casillas vacías y «Próximamente».
function Arsenal:dibujarVariantes(u, x, y, w, h)
    local g = love.graphics
    local px = Tema.px
    local bx, by, bw, bh = panelDatos(x, y, w, h, 'Variantes', u.nombre)
    local pad = px(18)
    local cx, cw = bx + pad, bw - pad * 2
    local cy = by + pad
    -- Árbol de casillas vacías, en gris.
    local lado = math.floor(math.min(px(84), (cw - px(80)) / 3))
    local hueco = math.floor((cw - lado * 3) / 2)
    for fila = 0, 1 do
        local fy = cy + fila * (lado + px(40))
        for col = 0, 2 do
            local fx = cx + col * (lado + hueco)
            g.setColor(0.55, 0.55, 0.55, 0.35)
            g.rectangle('fill', fx, fy, lado, lado)
            g.setColor(0.45, 0.45, 0.45, 0.8)
            g.rectangle('line', fx + 0.5, fy + 0.5, lado - 1, lado - 1)
            if col < 2 then
                g.setColor(0.4, 0.4, 0.4, 0.6)
                local ay = fy + lado / 2
                g.line(fx + lado + px(8), ay, fx + lado + hueco - px(8), ay)
                g.polygon(
                    'fill',
                    fx + lado + hueco - px(8),
                    ay - px(5),
                    fx + lado + hueco - px(1),
                    ay,
                    fx + lado + hueco - px(8),
                    ay + px(5)
                )
            end
        end
    end
    cy = cy + 2 * lado + px(40) + px(24)
    local ft = Acero.fuente('titulo', 34)
    g.setFont(ft)
    Tema.color('tintaTenue')
    local texto = 'Próximamente'
    g.print(texto, cx + (cw - ft:getWidth(texto)) / 2, cy)
    cy = cy + ft:getHeight() + px(8)
    Tema.color('tintaTenue')
    parrafo(
        Acero.fuente('cuerpo', 17),
        'Aquí irá el kit de piezas: cambiar el cañón, el blindaje o el motor de cada modelo y '
            .. 'guardar tus propias variantes. Todavía no está en el juego.',
        cx,
        cy,
        cw,
        5,
        1.25
    )
end

-- Tira de miniaturas ----------------------------------------------------------------------------

--- Tira de abajo: el contador de la categoría, el buscador, el orden y las
-- miniaturas para cambiar de modelo.
function Arsenal:dibujarTira(x, y, w, h, datos)
    local g = love.graphics
    local px = Tema.px
    local lista = self:lista(datos)
    -- Línea de arriba: contador, buscador y orden.
    local fc = Acero.fuente('cifra', 22)
    local lineaH = px(44)
    local puedes = 0
    for _, u in ipairs(lista) do
        if not datos.unidades[u.id].bloqueo then
            puedes = puedes + 1
        end
    end
    local icono = self.busqueda ~= '' and 'busqueda' or CATEGORIA[self.cat].icono
    Acero.icono(icono, x, y + (lineaH - px(30)) / 2, px(30), 'tintaTenue')
    g.setFont(fc)
    Tema.color('tintaTenue')
    local contador = puedes .. '/' .. #lista
    g.print(contador, x + px(40), y + (lineaH - fc:getHeight()) / 2)
    local mx, my = love.mouse.getPosition()
    if Tema.dentro(mx, my, x, y, px(40) + fc:getWidth(contador), lineaH) then
        self.ayuda = string.format('Puedes fabricar %d de los %d modelos que se ven.', puedes, #lista)
    end
    -- Orden (como «Estrellas ↓» de Warpath) y buscador, a la derecha.
    local ow = px(220)
    local bh = px(38)
    local oy = y + (lineaH - bh) / 2
    local ox = x + w - ow
    local fb = Acero.fuente('boton', 19)
    g.setColor(0.95, 0.95, 0.95, 0.85)
    g.rectangle('fill', ox, oy, ow, bh)
    g.setColor(0.35, 0.35, 0.35, 1)
    g.rectangle('line', ox + 0.5, oy + 0.5, ow - 1, bh - 1)
    g.setFont(fb)
    Tema.color('tinta')
    g.print(ORDENES[self.orden], ox + px(14), oy + (bh - fb:getHeight()) / 2)
    Acero.icono('flecha_abajo', ox + ow - px(32), oy + (bh - px(22)) / 2, px(22), 'tinta')
    self:zona(ox, oy, ow, bh, 'orden')
    if Tema.dentro(mx, my, ox, oy, ow, bh) then
        self.ayuda = 'Orden de la tira: por poder, por nombre o por lo que tienes. Lo bloqueado va al final.'
    end
    local sw = math.min(px(420), math.floor(w * 0.36))
    local sx = ox - px(12) - sw
    g.setColor(1, 1, 1, self.buscando and 0.95 or 0.7)
    g.rectangle('fill', sx, oy, sw, bh)
    g.setColor(0.35, 0.35, 0.35, 1)
    g.setLineWidth(self.buscando and 2 or 1)
    g.rectangle('line', sx + 0.5, oy + 0.5, sw - 1, bh - 1)
    g.setLineWidth(1)
    Acero.icono('busqueda', sx + px(8), oy + (bh - px(24)) / 2, px(24), 'tintaTenue')
    local fs = Acero.fuente('cuerpo', 17)
    g.setFont(fs)
    local mostrar = self.busqueda
    if mostrar == '' and not self.buscando then
        Tema.color('tintaTenue')
        g.print('Buscar en todo el arsenal…', sx + px(40), oy + (bh - fs:getHeight()) / 2)
    else
        Tema.color('tinta')
        if self.buscando and math.floor(love.timer.getTime() * 2) % 2 == 0 then
            mostrar = mostrar .. '|'
        end
        g.print(Tema.cortar(fs, mostrar, sw - px(50)), sx + px(40), oy + (bh - fs:getHeight()) / 2)
    end
    self:zona(sx, oy, sw, bh, 'buscar')
    -- Raya bajo la línea (como en unidad_5_categorias.jpg).
    g.setColor(0.2, 0.2, 0.2, 0.7)
    g.rectangle('fill', x, y + lineaH + px(2), w, math.max(1, px(2)))
    -- Miniaturas.
    local ty = y + lineaH + px(14)
    local th = y + h - ty
    local tw = math.floor(th * 1.3)
    local hueco = px(12)
    local flecha = px(36)
    local caben = math.max(1, math.floor((w + hueco) / (tw + hueco)))
    local desborda = #lista > caben
    if desborda then
        caben = math.max(1, math.floor((w - (flecha + hueco) * 2 + hueco) / (tw + hueco)))
    end
    self.inicioTira = math.max(0, math.min(self.inicioTira, #lista - caben))
    local x0 = x + (desborda and (flecha + hueco) or 0)
    if #lista == 0 then
        g.setFont(Acero.fuente('cuerpo', 20))
        Tema.color('tintaTenue')
        g.print('Nada coincide con la búsqueda.', x, ty + px(10))
    end
    for k = 1, caben do
        local u = lista[self.inicioTira + k]
        if not u then
            break
        end
        self:dibujarMiniatura(u, datos.unidades[u.id], x0 + (k - 1) * (tw + hueco), ty, tw, th, datos.color)
    end
    if desborda then
        local puedeAtras = self.inicioTira > 0
        local puedeAdelante = self.inicioTira + caben < #lista
        Acero.boton({ texto = '‹', tipo = 'oscuro', activo = puedeAtras }, x, ty, flecha, th, true)
        Acero.boton({ texto = '›', tipo = 'oscuro', activo = puedeAdelante }, x + w - flecha, ty, flecha, th, true)
        if puedeAtras then
            self:zona(x, ty, flecha, th, 'tira', -caben)
        end
        if puedeAdelante then
            self:zona(x + w - flecha, ty, flecha, th, 'tira', caben)
        end
    end
end

--- Una miniatura de la tira: el modelo en 3D (fijo), su nombre y lo que tienes.
function Arsenal:dibujarMiniatura(u, d, x, y, w, h, color)
    local g = love.graphics
    local px = Tema.px
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, w, h)
    local activa = self.sel == u.id
    g.setColor(0, 0, 0, 0.15)
    g.rectangle('fill', x + px(2), y + px(3), w, h)
    Tema.degradado(x, y, w, h, { 0.97, 0.97, 0.97 }, { 0.84, 0.84, 0.85 }, encima and 1 or 0.88)
    local nombre = Acero.fuente('boton', 18)
    local chica = Acero.fuente('etiqueta', 13)
    local textoH = nombre:getHeight() + chica:getHeight() + px(6)
    local iw, ih = w - px(8), h - textoH - px(6)
    if u.municion then
        dibujarMunicion(u, x + px(4), y + px(4), iw, ih, 1)
    else
        local lienzo = self.vitrina:miniatura(u.modelo or u.id, iw, ih, color)
        if lienzo then
            g.setColor(1, 1, 1, d.bloqueo and 0.45 or 1)
            g.draw(lienzo, x + px(4), y + px(4))
        else
            local img = self:arte(u, 'miniatura')
            local escala = math.min(iw / img:getWidth(), ih / img:getHeight())
            g.setColor(1, 1, 1, d.bloqueo and 0.45 or 1)
            g.draw(img, x + px(4) + (iw - img:getWidth() * escala) / 2, y + px(4), 0, escala, escala)
        end
    end
    if d.bloqueo then
        local lado = px(26)
        Acero.icono('investigar', x + w - lado - px(6), y + px(6), lado, 'tintaTenue')
    end
    -- Nombre y debajo, lo que tienes o lo que falta.
    local ty = y + h - textoH
    g.setColor(0.18, 0.18, 0.18, 0.88)
    g.rectangle('fill', x, ty, w, textoH)
    g.setFont(nombre)
    g.setColor(0.97, 0.97, 0.95, d.bloqueo and 0.6 or 1)
    g.print(Tema.cortar(nombre, u.nombre, w - px(12)), x + px(6), ty + px(2))
    g.setFont(chica)
    local linea
    if d.bloqueo then
        g.setColor(0.95, 0.55, 0.45, 1)
        linea = d.bloqueoCorto
    else
        g.setColor(0.8, 0.8, 0.76, 1)
        linea = 'Tienes ' .. Tema.numero(d.total)
    end
    g.print(Tema.cortar(chica, linea, w - px(12)), x + px(6), ty + px(2) + nombre:getHeight())
    if activa then
        g.setLineWidth(math.max(2, px(4)))
        g.setColor(0.98, 0.82, 0.3, 1)
        g.rectangle('line', x + 1, y + 1, w - 2, h - 2)
        g.setLineWidth(1)
    elseif encima then
        g.setColor(1, 1, 1, 0.9)
        g.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    end
    if d.bloqueo and encima then
        self.ayuda = string.format(
            '%s: requiere %s. Cuando la tengas podrás fabricarlo; los que ya tengas siguen peleando.',
            u.nombre,
            d.bloqueo
        )
    end
    self:zona(x, y, w, h, 'unidad', u.id)
end

-- Pantalla ---------------------------------------------------------------------------------------

--- La categoría y la pestaña siguen valiendo para lo elegido (la de
-- `--arsenal` puede venir con los nombres de antes).
function Arsenal:corregir()
    local u = POR_ID[self.sel] or UNIDADES[1]
    self.sel = u.id
    if not CATEGORIA[self.cat] then
        self.cat = categoriaDe(u)
    end
    if self.pestana == 'comparar' and not parComparar(u) then
        self.pestana = 'ficha'
    end
    return u
end

--- Dibuja el arsenal. `ctx` = { sim, nacion }.
function Arsenal:dibujar(ctx)
    if not self.abierto then
        return
    end
    local g = love.graphics
    local px = Tema.px
    local sim = ctx.sim
    local w, h = g.getDimensions()
    self.zonas = {}
    self.ayuda = nil
    -- Giro solo del modelo (tiempo real de la interfaz).
    local ahora = love.timer.getTime()
    local dt = math.min(0.1, ahora - (self.reloj or ahora))
    self.reloj = ahora
    if not self.giro then
        self.angulo = self.angulo + GIRO * dt
    end
    fondoNiebla()
    local recursos = ctx.nacion and Clara.recursosDe(sim, ctx.nacion) or {}
    if not ctx.nacion then
        local logo = Clara.cabecera('ARSENAL', recursos)
        self:zona(logo.x, logo.y, logo.w, logo.h, 'cerrar')
        g.setFont(Acero.fuente('titulo', 28))
        Tema.color('tinta')
        g.print('Sin nación: no hay arsenal que mostrar.', px(96), px(120))
        return
    end
    local datos = self:datos(sim, ctx.nacion)
    self.nacion = ctx.nacion
    local u = self:corregir()
    local d = datos.unidades[u.id]
    -- Cabecera: solo la designación del modelo.
    local logo = Clara.cabecera(u.nombre, recursos)
    self:zona(logo.x, logo.y, logo.w, logo.h, 'cerrar')
    local mx, my = love.mouse.getPosition()
    if Tema.dentro(mx, my, logo.x, logo.y, logo.w, logo.h) then
        self.ayuda = 'Volver al mapa (Esc)'
    end
    -- Medidas: proporcionales a la pantalla.
    local margen = logo.x
    local columnaW = math.floor(w * 0.12)
    local botonH = math.floor(h * 0.06)
    local paso = math.floor(h * 0.078)
    local arriba = logo.y + logo.h + math.floor(h * 0.03)
    local derechaW = math.floor(w * 0.27)
    local derechaX = w - px(28) - derechaW
    local abajo = h - math.floor(h * 0.035)
    -- Poder (o el lote) bajo el título, a la derecha de la columna.
    local pillH = math.floor(h * 0.042)
    local pillX = margen + columnaW + px(24)
    local pillY = logo.y + logo.h + px(4)
    if u.municion then
        pastillaPoder(
            pillX,
            pillY,
            pillH,
            'suministros',
            'Lote de ' .. Tema.numero(Simulacion.produccion.municion[u.id].lote)
        )
    else
        local pw = pastillaPoder(pillX, pillY, pillH, 'poder', decimal(d.poder))
        if Tema.dentro(mx, my, pillX, pillY, pw, pillH) then
            self.ayuda = 'Poder: lo que pesa una unidad en la fuerza de tu ejército.'
        end
        if d.bloqueo then
            pastillaPoder(pillX, pillY + pillH + px(8), pillH, 'investigar', d.bloqueoCorto, Paleta.claro.rojoTexto)
        end
    end
    -- Columna izquierda: pestañas y categorías.
    self:dibujarPestanas(margen, arriba, columnaW, botonH, paso, u)
    local catY = arriba + #PESTANAS * paso + math.floor(h * 0.02)
    self:dibujarCategorias(margen, catY, columnaW, math.floor(botonH * 0.85), math.floor(paso * 0.82), datos)
    -- Centro y tira.
    local centroX = margen + columnaW + math.floor(w * 0.02)
    local conPanel = self.pestana ~= 'comparar'
    local centroW = (conPanel and (derechaX - px(24)) or (w - px(28))) - centroX
    local tiraH = math.floor(h * 0.2)
    local tiraY = abajo - tiraH
    local centroY = pillY + pillH + px(10)
    local centroH = tiraY - px(16) - centroY
    if self.pestana == 'comparar' then
        self:dibujarComparar(u, datos, centroX, centroY, centroW, centroH, self.angulo)
    else
        self:dibujarModelo(u, d, centroX, centroY, centroW, centroH, self.angulo, 'principal', datos.color)
        self:zona(centroX, centroY, centroW, centroH, 'girar')
        if u.municion == nil and Tema.dentro(mx, my, centroX, centroY, centroW, centroH) then
            self.ayuda = 'Arrastra para girar el modelo.'
        end
    end
    self:dibujarTira(centroX, tiraY, centroW, tiraH, datos)
    -- Panel de la derecha: entra deslizándose al cambiar de pestaña.
    if conPanel then
        local py = logo.y + logo.h + px(6)
        local ph = abajo - py
        Vida.entrar('arsenal:' .. self.pestana, px(40), 0)
        if self.pestana == 'producir' then
            self:dibujarProducir(u, d, datos, sim, ctx.nacion, derechaX, py, derechaW, ph)
        elseif self.pestana == 'variantes' then
            self:dibujarVariantes(u, derechaX, py, derechaW, ph)
        else
            self:dibujarFicha(u, d, datos, sim, derechaX, py, derechaW, ph)
        end
        Vida.fin()
    end
end

function Arsenal:dibujarAyuda()
    if self.abierto and self.ayuda and not self.giro then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my, Tema.px(380))
    end
end

--- Texto escrito (buscador).
function Arsenal:texto(t)
    if self.abierto and self.buscando and #self.busqueda < 30 then
        self.busqueda = self.busqueda .. t
        self.inicioTira = 0
    end
end

--- Tecla pulsada. Devuelve true si el arsenal la usó.
function Arsenal:tecla(tecla)
    if not self.abierto then
        return false
    end
    if self.buscando then
        if tecla == 'backspace' then
            local corte = #self.busqueda
            while corte > 1 and self.busqueda:byte(corte) >= 128 and self.busqueda:byte(corte) < 192 do
                corte = corte - 1
            end
            self.busqueda = self.busqueda:sub(1, corte - 1)
            return true
        elseif tecla == 'return' or tecla == 'escape' then
            self.buscando = false
            return true
        end
        return true
    end
    if tecla == 'escape' then
        self:cerrar()
    end
    return true
end

--- Ratón movido: con el modelo agarrado, lo gira.
function Arsenal:mover(x)
    if self.abierto and self.giro then
        self.angulo = self.angulo + (x - self.giro.x) * 0.012
        self.giro.x = x
    end
end

--- Botón del ratón soltado: suelta el modelo.
function Arsenal:soltar()
    self.giro = nil
end

--- Elige la unidad `id` (la cantidad vuelve a 1 si cambia).
function Arsenal:elegir(id)
    if self.sel ~= id then
        self.cantidad = 1
    end
    self.sel = id
    local u = POR_ID[id]
    if u and self.busqueda == '' then
        self.cat = categoriaDe(u)
    end
end

--- Clic. Devuelve `cerrar`, `nada` o { comandos = { … } } (producir o
-- cancelar una orden: los manda main.lua y avisa con `resultado`).
function Arsenal:pulsar(x, y)
    self.buscando = false
    for k = #self.zonas, 1, -1 do
        local z = self.zonas[k]
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local a = z.accion
            if a == 'cerrar' then
                return 'cerrar'
            elseif a == 'girar' then
                self.giro = { x = x }
            elseif a == 'pestana' then
                self.pestana = z.dato
            elseif a == 'categoria' then
                self.cat = z.dato
                self.busqueda = ''
                self.inicioTira = 0
                -- Lo elegido pasa a lo primero de la categoría si no está en ella.
                if not enCategoria(POR_ID[self.sel], self.cat) then
                    local lista = self:lista(self.cache)
                    if lista[1] then
                        self:elegir(lista[1].id)
                    end
                end
            elseif a == 'unidad' then
                self:elegir(z.dato)
            elseif a == 'verOtro' then
                self:elegir(z.dato)
                self.pestana = 'ficha'
            elseif a == 'tira' then
                self.inicioTira = self.inicioTira + z.dato
            elseif a == 'ciudad' then
                local ciudades = self.cache and self.cache.sim and self.cache.sim:ciudadesDe(self.nacion) or {}
                for i, c in ipairs(ciudades) do
                    if c.id == self.ciudad then
                        self.ciudad = ciudades[(i - 1 + z.dato) % #ciudades + 1].id
                        break
                    end
                end
                self.sucio = true
            elseif a == 'maximo' then
                self.cantidad = z.dato
            elseif a == 'producir' then
                self.sucio = true
                return {
                    comandos = {
                        {
                            tipo = 'producir',
                            nacion = self.nacion,
                            ciudad = self.ciudad,
                            tropa = z.dato.tropa,
                            cantidad = z.dato.cantidad,
                            modelo = z.dato.modelo,
                        },
                    },
                }
            elseif a == 'cancelarOrden' then
                self.sucio = true
                return {
                    comandos = {
                        { tipo = 'cancelarProduccion', nacion = self.nacion, ciudad = self.ciudad, orden = z.dato },
                    },
                }
            elseif a == 'buscar' then
                self.buscando = true
            elseif a == 'orden' then
                self.orden = self.orden % #ORDENES + 1
            elseif a == 'cantidad' then
                -- Con paso de 10, de 1 se va a 10 (no a 11) y de 10 a 1.
                local nuevo = self.cantidad + z.dato
                if math.abs(z.dato) > 1 and self.cantidad % z.dato ~= 0 then
                    local paso = math.abs(z.dato)
                    nuevo = z.dato > 0 and (math.floor(self.cantidad / paso) + 1) * paso
                        or math.floor(self.cantidad / paso) * paso
                end
                self.cantidad = math.max(1, nuevo)
            end
            return 'nada'
        end
    end
    return 'nada'
end

return Arsenal

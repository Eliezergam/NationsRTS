-- Páginas web de Vexar: archivos `.vex`, escritos en Lua (el dueño, 26-nov).
--
-- La página se ejecuta entera cada vez que el navegador la rehace (unas diez
-- veces por segundo, y en cuanto se hace clic), así que lo que muestra está
-- siempre al día. Corre aislada como los programas de la terminal
-- (almacen/pc/lua.lua): solo ve Lua sin acceso a nada de fuera y esto:
--
--   nombre('Mi base')            el título de la pestaña
--   titulo('Texto', nivel)       nivel 1 (por defecto), 2 o 3
--   texto('Hola **mundo**', color)  un párrafo; color opcional ('rojo'...)
--   punto('Algo')                un punto de una lista
--   nota('Aviso')                un recuadro destacado
--   enlace('Noticias', 'noticias.red')
--   boton('Mandar robot')        true en la vuelta en que se pulsa
--   tabla({ { 'Recurso', 'Cantidad' }, { 'Oro', 120 } })  la primera fila es
--                                la cabecera
--   separador()   espacio(px)
--   miles(1234567)               '1.234.567'
--   publicacion({ nombre, usuario, color, dia, texto, apoyos, reenvios,
--                 comentarios, enlace, cita })  una publicación
--   comentarios(p, desde, cuantos)   los comentarios de la gente de `p`
--   comentario(c)                    uno de ellos, pintado
--   parametro                        lo que va tras el sitio en la dirección
--                                    ('ondix.red/Dobel' -> 'Dobel')
--   memoria                          una tabla que dura mientras está abierta
--   partida                      nacion, anio, dia, misiles, capacidad,
--                                recursos = { { tipo, nombre, cantidad, tope } },
--                                noticias = { { dia, texto } },
--                                ondix = { { id, dia, nacion, usuario,
--                                presidente, color, texto, respondeA, apoyos,
--                                reenvios, respuestas } },
--                                perfiles = { { usuario, presidente, nacion,
--                                color, capital, orden, habitantes,
--                                seguidores, tono, jugador } } (una copia)
--   robots                       la API de los robots (almacen/pc/api_robots.lua)
--
-- Dentro de un texto: **negrita**, [enlace](destino), {rojo|en color}.
--
--   local bloques, nombre, error = Pagina.ejecutar(codigo, archivo, ctx, pulsados)

local Lua = require('almacen.pc.lua')
local Dibujo = require('almacen.pc.dibujo')
local Maqueta = require('almacen.pc.web.maqueta')
local ApiRobots = require('almacen.pc.api_robots')
local Gente = require('mundo.simulacion.ondix_gente')

local Pagina = {}

Pagina.extension = '.vex'
-- Instrucciones que puede gastar una página en cada vuelta.
Pagina.limite = 1000000

-- Páginas ya compiladas, por su código (solo se compila si cambia).
local compiladas = {}
local cantidadCompiladas = 0

local function compilar(codigo, archivo)
    local hecha = compiladas[codigo]
    if hecha then
        return hecha.f, hecha.fallo
    end
    if cantidadCompiladas > 64 then
        compiladas, cantidadCompiladas = {}, 0
    end
    local f, fallo
    if codigo:byte(1) == 27 then
        fallo = 'no se pueden cargar páginas compiladas'
    else
        f, fallo = loadstring(codigo, '=' .. (archivo:match('[^/]+$') or 'página'))
    end
    if f then
        jit.off(f, true)
    end
    compiladas[codigo] = { f = f, fallo = fallo }
    cantidadCompiladas = cantidadCompiladas + 1
    return f, fallo
end

local function copiaProfunda(t)
    if type(t) ~= 'table' then
        return t
    end
    local c = {}
    for k, v in pairs(t) do
        c[k] = copiaProfunda(v)
    end
    return c
end

--- Los datos de la partida que ve una página (una copia: no puede cambiar
-- nada del juego).
local function datosPartida(ctx)
    local p = ctx.partida or {}
    return {
        nacion = p.nacion,
        anio = p.anio,
        dia = p.dia,
        misiles = ctx.misiles or 0,
        capacidad = ctx.capacidad or 0,
        recursos = copiaProfunda(p.recursos or {}),
        noticias = copiaProfunda(p.noticias or {}),
        ondix = copiaProfunda(p.ondix or {}),
        perfiles = copiaProfunda(p.perfiles or {}),
    }
end

local function colorDe(color)
    if type(color) == 'string' then
        return Maqueta.colores[color]
    elseif type(color) == 'table' then
        return { tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1 }
    end
end

local function trozosCon(texto, color)
    local trozos = Maqueta.trozos(tostring(texto == nil and '' or texto))
    local c = colorDe(color)
    if c then
        for _, t in ipairs(trozos) do
            if not t.enlace then
                t.color = t.color or c
            end
        end
    end
    return trozos
end

--- Ejecuta la página. `pulsados`: { [indice] = true } con los botones que se
-- pulsaron desde la vuelta anterior. Devuelve los bloques (Maqueta.colocar),
-- el nombre de la página y, si falló, el error (con su línea).
function Pagina.ejecutar(codigo, archivo, ctx, pulsados, parametro, memoria, campos)
    local f, fallo = compilar(codigo, archivo)
    if not f then
        return {}, nil, fallo
    end
    local bloques = {}
    local nombre
    local botones = 0
    local carpeta = archivo:match('^(.*)/[^/]*$') or '/home/operador'
    local api = {
        partida = datosPartida(ctx),
        robots = ctx.ordenador and ApiRobots.para(ctx.ordenador, carpeta) or nil,
    }
    local env = Lua.entorno(api, function() end)
    env.sleep = function()
        error('sleep no se usa en las páginas: la página se rehace sola', 2)
    end
    local function poner(b)
        bloques[#bloques + 1] = b
    end
    function env.nombre(t)
        nombre = tostring(t)
    end
    function env.titulo(t, nivel)
        nivel = math.max(1, math.min(3, math.floor(tonumber(nivel) or 1)))
        poner({ tipo = 'titulo', nivel = nivel, trozos = trozosCon(t) })
    end
    function env.texto(t, color)
        poner({ tipo = 'parrafo', trozos = trozosCon(t, color) })
    end
    function env.punto(t, color)
        poner({ tipo = 'lista', trozos = trozosCon(t, color) })
    end
    function env.nota(t, color)
        poner({ tipo = 'nota', trozos = trozosCon(t, color) })
    end
    function env.enlace(t, destino)
        poner({ tipo = 'parrafo', trozos = { { texto = tostring(t), enlace = tostring(destino) } } })
    end
    function env.separador()
        poner({ tipo = 'separador' })
    end
    function env.espacio(px)
        poner({ tipo = 'espacio', alto = math.max(0, math.min(400, tonumber(px) or 12)) })
    end
    -- Un cuadro para escribir: campo(pista, lineas, limite) devuelve lo
    -- escrito hasta ahora.
    local numeroCampos = 0
    campos = campos or {}
    function env.campo(pista, lineas, limite)
        numeroCampos = numeroCampos + 1
        poner({
            tipo = 'campo',
            indice = numeroCampos,
            pista = tostring(pista or ''),
            lineas = math.max(1, math.min(8, math.floor(tonumber(lineas) or 3))),
            limite = math.max(1, math.min(2000, math.floor(tonumber(limite) or 280))),
        })
        return campos[numeroCampos] or ''
    end
    -- Publica en Ondix desde el perfil del presidente. Solo al pulsar un
    -- botón (la página se rehace sola: así no publica a cada vuelta) y una
    -- vez por pulsación. Vacía los cuadros si se publicó.
    local publicado = false
    function env.publicar(texto, cita)
        if publicado or not (pulsados and next(pulsados)) or not ctx.publicarOndix then
            return false
        end
        publicado = true
        local hecho = ctx.publicarOndix(tostring(texto or ''), tonumber(cita))
        if hecho then
            for k in pairs(campos) do
                campos[k] = nil
            end
        end
        return hecho
    end
    function env.boton(t)
        botones = botones + 1
        poner({ tipo = 'boton', texto = tostring(t), indice = botones })
        return pulsados and pulsados[botones] or false
    end
    function env.tabla(filas)
        local tabla = { tipo = 'tabla', filas = {} }
        for _, fila in ipairs(type(filas) == 'table' and filas or {}) do
            local celdas = {}
            for c, valor in ipairs(type(fila) == 'table' and fila or { fila }) do
                celdas[c] = trozosCon(valor)
            end
            tabla.filas[#tabla.filas + 1] = celdas
        end
        poner(tabla)
    end
    --- Una publicación de Ondix con su foto, nombre, @, día, texto y
    -- contadores: publicacion({ nombre, usuario, color, dia, texto, apoyos,
    -- reenvios, comentarios, enlace, cita = { nombre, usuario,
    -- color, dia, texto, enlace } }).
    function env.publicacion(p)
        p = type(p) == 'table' and p or {}
        poner({
            tipo = 'publicacion',
            nombre = tostring(p.nombre or ''),
            usuario = tostring(p.usuario or ''),
            color = colorDe(p.color) or Maqueta.colores.gris,
            dia = tonumber(p.dia),
            trozos = Maqueta.trozosSociales(tostring(p.texto or '')),
            apoyos = tonumber(p.apoyos) or 0,
            reenvios = tonumber(p.reenvios) or 0,
            respuestas = tonumber(p.comentarios or p.respuestas) or 0,
            enlace = p.enlace and tostring(p.enlace),
            cita = type(p.cita) == 'table' and {
                nombre = tostring(p.cita.nombre or p.cita.presidente or ''),
                usuario = tostring(p.cita.usuario or ''),
                color = colorDe(p.cita.color) or Maqueta.colores.gris,
                dia = tonumber(p.cita.dia),
                trozos = Maqueta.trozosSociales(tostring(p.cita.texto or '')),
                enlace = p.cita.enlace and tostring(p.cita.enlace),
            } or nil,
        })
    end
    env.miles = Dibujo.miles
    -- Lo que va tras el nombre en la dirección ('ondix.red/Dobel' -> 'Dobel').
    env.parametro = parametro
    -- Una tabla que se conserva mientras la página está abierta.
    env.memoria = memoria or {}
    --- Los comentarios de la gente de la publicación `p` (de partida.ondix):
    -- `cuantos` desde el número `desde`.
    function env.comentarios(p, desde, cuantos)
        local lista = {}
        if type(p) ~= 'table' or not p.semilla then
            return lista
        end
        local etiqueta = tostring(p.texto or ''):match('#[%w_\128-\255]+')
        local contexto = { autor = p.usuario, sobre = p.sobre, etiqueta = etiqueta }
        desde = math.max(1, math.floor(tonumber(desde) or 1))
        cuantos = math.max(0, math.min(200, math.floor(tonumber(cuantos) or 20)))
        local total = tonumber(p.comentarios) or 0
        for k = desde, math.min(total, desde + cuantos - 1) do
            lista[#lista + 1] = Gente.comentario(p, k, contexto)
        end
        return lista
    end
    --- Un comentario de la gente debajo de una publicación.
    function env.comentario(c)
        c = type(c) == 'table' and c or {}
        poner({
            tipo = 'publicacion',
            pequena = true,
            nombre = tostring(c.usuario or ''),
            usuario = '',
            color = Gente.colorDe(c.usuario),
            trozos = Maqueta.trozosSociales(tostring(c.texto or '')),
            apoyos = tonumber(c.apoyos) or 0,
        })
    end
    setfenv(f, env)
    debug.sethook(function()
        error('la página tarda demasiado (¿un bucle sin fin?)', 2)
    end, '', Pagina.limite)
    local ok, mensaje = pcall(f)
    debug.sethook()
    if not ok then
        return bloques, nombre, tostring(mensaje)
    end
    return bloques, nombre
end

--- La ruta del archivo de una dirección, vista desde la página `desde` (para
-- los enlaces con solo un nombre). Direcciones:
--   'noticias.red'     /red/web/noticias.vex (las páginas del juego)
--   'local/mibase'     /home/operador/web/mibase.vex (las de este puesto)
--   '/ruta/a.vex', '~/web/a.vex'
--   'otra'             otra.vex en la carpeta de la página `desde`
function Pagina.ruta(direccion, desde)
    direccion = tostring(direccion or ''):match('^%s*(.-)%s*$')
    if direccion == '' then
        return nil
    end
    local function conExtension(r)
        if r:sub(-#Pagina.extension) ~= Pagina.extension then
            r = r .. Pagina.extension
        end
        return r
    end
    local sitio, parametro = direccion:match('^([%w_%-]+)%.red/(.+)$')
    if sitio then
        return '/red/web/' .. sitio .. Pagina.extension .. '?' .. parametro
    end
    sitio = direccion:match('^([%w_%-]+)%.red$')
    if sitio then
        return '/red/web/' .. sitio .. Pagina.extension
    end
    local propia = direccion:match('^local/(.+)$')
    if propia then
        return conExtension('/home/operador/web/' .. propia)
    end
    if direccion:sub(1, 1) == '/' or direccion:sub(1, 1) == '~' then
        return conExtension(require('almacen.pc.archivos').resolver('/home/operador', direccion))
    end
    local carpeta = desde and desde:match('^(.*)/[^/]*$') or '/red/web'
    return conExtension(carpeta .. '/' .. direccion)
end

--- El archivo y el parámetro de una ruta ('/red/web/ondix.vex?Dobel').
function Pagina.partes(ruta)
    local archivo, parametro = ruta:match('^(.-)%?(.*)$')
    if archivo then
        return archivo, parametro
    end
    return ruta, nil
end

--- La dirección corta que se enseña en la barra para la ruta de un archivo.
function Pagina.direccion(ruta)
    local conParametro, parametro = ruta:match('^/red/web/([%w_%-]+)%.vex%?(.+)$')
    if conParametro then
        return conParametro .. '.red/' .. parametro
    end
    local sitio = ruta:match('^/red/web/([%w_%-]+)%.vex$')
    if sitio then
        return sitio .. '.red'
    end
    local propia = ruta:match('^/home/operador/web/(.+)%.vex$')
    if propia then
        return 'local/' .. propia
    end
    return ruta
end

return Pagina

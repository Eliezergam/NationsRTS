-- Texturas procedurales del estilo de la batalla (de la prueba de Camila,
-- batalla/pruebas_estilo). Ninguna viene de un archivo:
-- se pintan en código con ruido y trazos (lienzo.lua) al arrancar. Los
-- colores van en sRGB; 3DreamEngine los pasa a lineal al leerlos.
--
-- Suelo (se repiten sin costura, alfa = altura para mezclarlas):
--   hierbaVerde, hierbaSeca, tierra
-- Materiales: corteza, roca (con liquen)
-- Recortadas (alfa = silueta): rama (agujas de pino), mata (hierba),
-- arbusto (hojas).

local Lienzo = require('batalla.dream.estilo.lienzo')

local Texturas = {}

-- Umbral del alfa de las texturas recortadas (material:setAlphaCutoff).
Texturas.corte = 0.45

local ruido = Lienzo.ruidoCiclico

local function mezclarColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

local function aleatorio(generador, minimo, maximo)
    return minimo + (maximo - minimo) * generador:random()
end

--- Fondo con ruido a varias escalas entre dos colores y alfa = altura.
local function fondo(lado, colorBajo, colorAlto, frecuencia, semilla)
    local lienzo = Lienzo.nuevo(lado, lado)
    local d = lienzo.datos
    for y = 0, lado - 1 do
        for x = 0, lado - 1 do
            local u, v = x / lado, y / lado
            local n = ruido(u, v, frecuencia, 4, semilla) * 0.5 + 0.5
            local fino = ruido(u, v, frecuencia * 8, 2, semilla + 3) * 0.5 + 0.5
            local t = math.max(0, math.min(1, n * 0.75 + fino * 0.25))
            local c = mezclarColor(colorBajo, colorAlto, t)
            local k = lienzo:indice(x, y)
            d[k] = c[1]
            d[k + 1] = c[2]
            d[k + 2] = c[3]
            d[k + 3] = t
        end
    end
    return lienzo
end

--- Briznas cortas de hierba vistas desde arriba (trazos en todas las
-- direcciones) que suben la altura del alfa donde caen.
local function briznas(lienzo, generador, cantidad, colores, largo, ancho)
    local lado = lienzo.ancho
    for _ = 1, cantidad do
        local x = generador:random() * lado
        local y = generador:random() * lado
        local angulo = generador:random() * math.pi * 2
        local l = aleatorio(generador, largo * 0.5, largo)
        local color = colores[generador:random(1, #colores)]
        local claro = aleatorio(generador, 0.8, 1.15)
        local c = { color[1] * claro, color[2] * claro, color[3] * claro }
        lienzo:trazo(
            x,
            y,
            x + math.cos(angulo) * l,
            y + math.sin(angulo) * l,
            ancho,
            ancho * 0.4,
            c,
            c,
            { envolver = true, opacidad = 0.85 }
        )
    end
end

function Texturas.hierbaVerde()
    local generador = love.math.newRandomGenerator(11)
    local lienzo = fondo(512, { 0.13, 0.16, 0.07 }, { 0.3, 0.34, 0.15 }, 6, 1)
    briznas(lienzo, generador, 9000, {
        { 0.24, 0.3, 0.12 },
        { 0.33, 0.38, 0.16 },
        { 0.2, 0.24, 0.1 },
        { 0.42, 0.42, 0.2 },
    }, 9, 1.6)
    return lienzo:niveles(nil)
end

function Texturas.hierbaSeca()
    local generador = love.math.newRandomGenerator(12)
    local lienzo = fondo(512, { 0.27, 0.24, 0.13 }, { 0.43, 0.39, 0.23 }, 5, 2)
    briznas(lienzo, generador, 8000, {
        { 0.55, 0.47, 0.26 },
        { 0.45, 0.37, 0.19 },
        { 0.38, 0.36, 0.18 },
        { 0.62, 0.55, 0.33 },
    }, 10, 1.5)
    return lienzo:niveles(nil)
end

--- Tierra rojiza con pinocha (trazos finos rojizos) y piedrecitas.
function Texturas.tierra()
    local generador = love.math.newRandomGenerator(13)
    local lienzo = fondo(512, { 0.2, 0.12, 0.08 }, { 0.42, 0.27, 0.17 }, 7, 3)
    briznas(lienzo, generador, 2500, {
        { 0.45, 0.24, 0.13 },
        { 0.33, 0.18, 0.1 },
        { 0.52, 0.33, 0.2 },
    }, 12, 1.1)
    for _ = 1, 500 do
        local x = generador:random() * 512
        local y = generador:random() * 512
        local radio = aleatorio(generador, 1, 3)
        local gris = aleatorio(generador, 0.3, 0.5)
        local c = { gris * 1.05, gris, gris * 0.92 }
        lienzo:trazo(x, y, x + 0.5, y + 0.5, radio * 2, radio * 2, c, c, { envolver = true, opacidad = 0.8 })
    end
    return lienzo:niveles(nil)
end

--- Corteza: surcos verticales (ruido estirado en v) marrón rojizo.
function Texturas.corteza()
    local lado = 256
    local lienzo = Lienzo.nuevo(lado, lado)
    local d = lienzo.datos
    for y = 0, lado - 1 do
        for x = 0, lado - 1 do
            local u, v = x / lado, y / lado
            local ondulacion = ruido(u, v, 3, 2, 21) * 0.08
            local surco = math.abs(math.sin((u + ondulacion) * math.pi * 12))
            surco = surco ^ 0.6
            local placas = ruido(u, v * 0.25, 10, 3, 22) * 0.5 + 0.5
            local grano = ruido(u, v, 40, 2, 23) * 0.5 + 0.5
            local t = surco * 0.6 + placas * 0.3 + grano * 0.1
            local c = mezclarColor({ 0.08, 0.045, 0.035 }, { 0.34, 0.19, 0.13 }, t)
            local k = lienzo:indice(x, y)
            d[k] = c[1]
            d[k + 1] = c[2]
            d[k + 2] = c[3]
        end
    end
    return lienzo:niveles(nil)
end

--- Roca gris con manchas de liquen verdoso y claro.
function Texturas.roca()
    local lado = 256
    local lienzo = Lienzo.nuevo(lado, lado)
    local d = lienzo.datos
    for y = 0, lado - 1 do
        for x = 0, lado - 1 do
            local u, v = x / lado, y / lado
            local base = ruido(u, v, 4, 5, 31) * 0.5 + 0.5
            local grano = ruido(u, v, 48, 2, 32) * 0.5 + 0.5
            local c = mezclarColor({ 0.2, 0.21, 0.21 }, { 0.44, 0.45, 0.44 }, base * 0.7 + grano * 0.3)
            local liquen = ruido(u, v, 7, 4, 33) * 0.5 + 0.5
            if liquen > 0.63 then
                local fuerza = math.min(1, (liquen - 0.63) * 6)
                c = mezclarColor(c, { 0.4, 0.43, 0.3 }, fuerza * 0.6)
            end
            local claro = ruido(u, v, 11, 3, 34) * 0.5 + 0.5
            if claro > 0.62 then
                c = mezclarColor(c, { 0.62, 0.64, 0.58 }, math.min(1, (claro - 0.62) * 8) * 0.6)
            end
            local k = lienzo:indice(x, y)
            d[k] = c[1]
            d[k + 1] = c[2]
            d[k + 2] = c[3]
        end
    end
    return lienzo:niveles(nil)
end

--- Rama de pino vista desde arriba. u (x) va del tronco (0) a la punta (1),
-- v (y) de un borde al otro con el eje en 0,5. Tallo marrón, ramillas a
-- los lados hacia la punta y agujas cortas a lo largo de todo.
function Texturas.rama(semilla)
    local ancho, alto = 256, 128
    local generador = love.math.newRandomGenerator(40 + (semilla or 0))
    local lienzo = Lienzo.nuevo(ancho, alto, 0, 0, 0, 0)
    local tallo = { 0.32, 0.17, 0.1 }
    local verdes = {
        { 0.12, 0.19, 0.1 },
        { 0.16, 0.25, 0.13 },
        { 0.22, 0.31, 0.17 },
        { 0.1, 0.15, 0.09 },
        { 0.28, 0.35, 0.2 },
    }
    local centro = alto * 0.5

    --- Media anchura del follaje (px) a lo largo de la rama.
    local function envolvente(t)
        local sube = math.min(1, t / 0.35)
        local baja = 1 - math.max(0, (t - 0.35) / 0.65) ^ 1.4
        return alto * 0.49 * (0.5 + 0.5 * sube) * baja
    end

    --- Agujas a lo largo de un segmento: trazos cortos inclinados hacia la punta.
    local function agujas(x0, y0, x1, y1, cantidad, largo)
        for _ = 1, cantidad do
            local t = generador:random()
            local x = x0 + (x1 - x0) * t
            local y = y0 + (y1 - y0) * t
            local direccion = math.atan2(y1 - y0, x1 - x0)
            local lado = generador:random() < 0.5 and -1 or 1
            local angulo = direccion + lado * aleatorio(generador, 0.5, 1.1)
            local l = aleatorio(generador, largo * 0.6, largo)
            local base = verdes[generador:random(1, #verdes)]
            -- Hacia el tronco, más oscuro: sombra del interior de la copa.
            local sombra = 0.55 + 0.45 * math.min(1, x / (ancho * 0.6))
            local c = { base[1] * sombra, base[2] * sombra, base[3] * sombra }
            lienzo:trazo(x, y, x + math.cos(angulo) * l, y + math.sin(angulo) * l, 1.7, 1.0, c, c, { alfa = true })
        end
    end

    -- Ramillas: salen del tallo hacia la punta, alternando los lados.
    local x = 6
    local lado = 1
    local puntos = {}
    while x < ancho * 0.9 do
        local t = x / ancho
        local alcance = envolvente(t)
        local finX = x + alcance * aleatorio(generador, 0.6, 0.9)
        local finY = centro + lado * alcance * aleatorio(generador, 0.8, 1.0)
        puntos[#puntos + 1] = { x, centro, finX, finY }
        x = x + aleatorio(generador, 6, 10)
        lado = -lado
    end
    for _, p in ipairs(puntos) do
        agujas(p[1], p[2], p[3], p[4], 110, 14)
    end
    agujas(0, centro, ancho * 0.97, centro, 260, 15)
    -- El tallo y las ramillas por encima, para que se lean como en la
    -- referencia (ramas marrones entre las agujas).
    for _, p in ipairs(puntos) do
        lienzo:trazo(p[1], p[2], p[3], p[4], 1.8, 0.8, tallo, verdes[2], { alfa = true })
    end
    lienzo:trazo(0, centro, ancho * 0.95, centro, 5, 1.2, tallo, tallo, { alfa = true })
    lienzo:rellenarTransparentes()
    return lienzo:niveles(Texturas.corte)
end

--- Mata de hierba de perfil: briznas curvas que nacen abajo (v = 1).
function Texturas.mata(seca)
    local lado = 256
    local generador = love.math.newRandomGenerator(seca and 51 or 52)
    local lienzo = Lienzo.nuevo(lado, lado, 0, 0, 0, 0)
    local colores
    if seca then
        colores = {
            { 0.66, 0.58, 0.36 },
            { 0.56, 0.47, 0.27 },
            { 0.72, 0.64, 0.42 },
            { 0.47, 0.44, 0.24 },
        }
    else
        colores = {
            { 0.4, 0.44, 0.2 },
            { 0.5, 0.52, 0.26 },
            { 0.32, 0.37, 0.16 },
            { 0.6, 0.57, 0.32 },
        }
    end
    for _ = 1, 150 do
        local base = lado * 0.5 + (generador:random() - 0.5) * lado * 0.55
        local altura = lado * aleatorio(generador, 0.35, 0.95)
        local inclinacion = (generador:random() - 0.5) * 1.2 + (base - lado * 0.5) / lado * 1.4
        local c = colores[generador:random(1, #colores)]
        local oscuro = { c[1] * 0.45, c[2] * 0.45, c[3] * 0.4 }
        local x, y = base, lado - 1
        local tramos = 5
        for tramo = 1, tramos do
            local t = tramo / tramos
            local nx = base + inclinacion * altura * t * t
            local ny = lado - 1 - altura * t
            local grosor0 = 3.2 * (1 - (tramo - 1) / tramos) + 0.6
            local grosor1 = 3.2 * (1 - t) + 0.6
            local c0 = mezclarColor(oscuro, c, (tramo - 1) / tramos)
            local c1 = mezclarColor(oscuro, c, t)
            lienzo:trazo(x, y, nx, ny, grosor0, grosor1, c0, c1, { alfa = true })
            x, y = nx, ny
        end
    end
    lienzo:rellenarTransparentes()
    return lienzo:niveles(Texturas.corte)
end

-- Texturas: nombre, función que da sus niveles y si se repite. Las matas
-- son dos (seca y verde).
local LISTA = {
    { 'hierbaVerde', Texturas.hierbaVerde, true },
    { 'hierbaSeca', Texturas.hierbaSeca, true },
    { 'tierra', Texturas.tierra, true },
    { 'corteza', Texturas.corteza, true },
    { 'roca', Texturas.roca, true },
    {
        'rama',
        function()
            return Texturas.rama(0)
        end,
        false,
    },
    {
        'mataSeca',
        function()
            return Texturas.mata(true)
        end,
        false,
    },
    {
        'mataVerde',
        function()
            return Texturas.mata(false)
        end,
        false,
    },
}

--- Niveles de mipmap (ImageData) de todas las texturas, por nombre. No usa
-- love.graphics: es lo que hace el hilo (hilo_texturas.lua).
function Texturas.generarNiveles()
    local niveles = {}
    for _, t in ipairs(LISTA) do
        niveles[t[1]] = t[2]()
    end
    return niveles
end

--- Las imágenes de LÖVE de unos niveles (en el hilo principal).
function Texturas.imagenes(niveles)
    local imagenes = {}
    for _, t in ipairs(LISTA) do
        imagenes[t[1]] = Lienzo.imagenDeNiveles(niveles[t[1]], t[3])
    end
    imagenes.matas = { imagenes.mataSeca, imagenes.mataVerde }
    return imagenes
end

local hilo, canal, listas

--- Empieza a pintar las texturas en un hilo (tardan ~1,4 s): la batalla
-- genera el suelo mientras tanto. Las texturas no dependen de la semilla,
-- así que se pintan una vez por partida.
function Texturas.empezar()
    if listas or hilo then
        return
    end
    canal = love.thread.newChannel()
    hilo = love.thread.newThread('batalla/dream/estilo/hilo_texturas.lua')
    hilo:start(canal)
end

--- Las texturas (espera al hilo si hace falta; sin hilo, las pinta aquí).
function Texturas.crear()
    if listas then
        return listas
    end
    local inicio = love.timer.getTime()
    local niveles
    if hilo then
        niveles = {}
        while true do
            local mensaje = canal:demand(30)
            if mensaje == nil then
                error('el hilo de las texturas no respondió: ' .. tostring(hilo:getError()))
            end
            if mensaje == 'fin' then
                break
            end
            local lista = {}
            for k = 2, #mensaje do
                lista[k - 1] = mensaje[k]
            end
            niveles[mensaje[1]] = lista
        end
        hilo = nil
    else
        niveles = Texturas.generarNiveles()
    end
    listas = Texturas.imagenes(niveles)
    print(string.format('ESTILO texturas listas en %.2f s (espera del hilo incluida)', love.timer.getTime() - inicio))
    return listas
end

return Texturas

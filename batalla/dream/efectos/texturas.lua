-- Texturas de los efectos de la batalla (Camila), pintadas en código al
-- arrancar con ruido: nada se importa. Todas son datos, no color: el canal
-- rojo es el brillo o la densidad interior y el alfa, la cobertura.
--
--   humo     atlas 2 x 2 de bocanadas distintas: borde irregular por ruido
--            fractal, interior con grumos y un poco más oscuro en el borde
--   fuego    atlas 2 x 2 de lenguas de fuego: núcleo caliente (rojo alto) y
--            jirones en el borde
--   chispa   trazo alargado de núcleo blanco, para chispas y trazadores
--   estela   cinta que se repite a lo largo (u) sin costura: bordes
--            deshilachados y jirones interiores
--   marca    quemado del suelo: centro oscuro, borde roto y rayos de la
--            explosión hacia fuera

local ffi = require('ffi')

local Texturas = {}

local ruido = love.math.noise
local DOS_PI = math.pi * 2

--- Ruido fractal 2D (4 octavas) en [0, 1].
local function fractal(x, y, z)
    local suma, amplitud, total = 0, 1, 0
    for _ = 1, 4 do
        suma = suma + ruido(x, y, z) * amplitud
        total = total + amplitud
        x, y, z = x * 2.03, y * 2.03, z + 7.1
        amplitud = amplitud * 0.5
    end
    return suma / total
end

--- Ruido fractal que se repite en u (0 a 1): el eje u da la vuelta a un
-- círculo en el ruido 4D.
local function fractalCiclico(u, v, escalaU, escalaV, semilla)
    local suma, amplitud, total = 0, 1, 0
    local radio = escalaU / DOS_PI
    for _ = 1, 4 do
        local a = u * DOS_PI
        suma = suma + ruido(math.cos(a) * radio, math.sin(a) * radio, v * escalaV, semilla) * amplitud
        total = total + amplitud
        radio, escalaV, semilla = radio * 2.03, escalaV * 2.03, semilla + 3.3
        amplitud = amplitud * 0.5
    end
    return suma / total
end

local function suave(a, b, x)
    local t = math.max(0, math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

--- Lienzo RGBA8 con puntero FFI para escribir rápido.
local function lienzo(ancho, alto)
    local datos = love.image.newImageData(ancho, alto, 'rgba8')
    return datos, ffi.cast('uint8_t*', datos:getFFIPointer())
end

local function poner(p, indice, r, g, b, a)
    local k = indice * 4
    p[k] = math.max(0, math.min(255, r * 255 + 0.5))
    p[k + 1] = math.max(0, math.min(255, g * 255 + 0.5))
    p[k + 2] = math.max(0, math.min(255, b * 255 + 0.5))
    p[k + 3] = math.max(0, math.min(255, a * 255 + 0.5))
end

local function imagen(datos)
    local img = love.graphics.newImage(datos, { mipmaps = true })
    img:setFilter('linear', 'linear')
    img:setMipmapFilter('linear')
    return img
end

--- Una bocanada de `lado` px en el cuadro (ox, oy) del atlas: varias bolas
-- blandas que se funden (forma de coliflor), deformadas por ruido.
local function pintarBocanada(p, ancho, ox, oy, lado, semilla, fuego)
    local azar = love.math.newRandomGenerator(math.floor(semilla * 1000))
    local bolas = {}
    local cuantas = fuego and 5 or 7
    for k = 1, cuantas do
        local a = azar:random() * DOS_PI
        local d = k == 1 and 0 or 0.15 + azar:random() * 0.3
        bolas[k] = { math.cos(a) * d, math.sin(a) * d, 0.27 + azar:random() * 0.17 }
    end
    for y = 0, lado - 1 do
        for x = 0, lado - 1 do
            local u = (x + 0.5) / lado * 2 - 1
            local v = (y + 0.5) / lado * 2 - 1
            -- El ruido desplaza el punto antes de medir: bordes con jirones.
            local wu = u + (fractal(u * 2.2 + semilla, v * 2.2, semilla) - 0.5) * 0.45
            local wv = v + (fractal(u * 2.2 - semilla, v * 2.2 + 3.7, semilla + 5) - 0.5) * 0.45
            local campo = 0
            for k = 1, cuantas do
                local b = bolas[k]
                local du, dv = wu - b[1], wv - b[2]
                campo = campo + math.exp(-(du * du + dv * dv) / (b[3] * b[3]))
            end
            local detalle = fractal(u * 5.5 - semilla, v * 5.5 + semilla * 2.3, semilla + 11)
            local r = math.sqrt(u * u + v * v)
            local cierre = 1 - suave(0.8, 0.98, r)
            local a
            local brillo
            if fuego then
                local densidad = campo * (0.55 + 0.8 * detalle)
                a = suave(0.2, 0.95, densidad) * cierre
                -- Núcleo caliente: el rojo lleva la temperatura (1 en el centro).
                brillo = suave(0.5, 1.6, densidad)
            else
                local densidad = campo * (0.7 + 0.6 * detalle)
                a = suave(0.08, 1.5, densidad) ^ 1.15 * cierre
                -- Grumos más claros sobre un fondo algo más oscuro: se lee el volumen.
                brillo = 0.62 + 0.22 * suave(0.4, 1.6, campo) + 0.2 * (detalle - 0.5)
            end
            poner(p, (oy + y) * ancho + ox + x, brillo, brillo, brillo, math.max(0, a))
        end
    end
end

function Texturas.humo()
    local lado = 128
    local datos, p = lienzo(lado * 2, lado * 2)
    for k = 0, 3 do
        pintarBocanada(p, lado * 2, (k % 2) * lado, math.floor(k / 2) * lado, lado, 1.7 + k * 2.9, false)
    end
    return imagen(datos)
end

function Texturas.fuego()
    local lado = 128
    local datos, p = lienzo(lado * 2, lado * 2)
    for k = 0, 3 do
        pintarBocanada(p, lado * 2, (k % 2) * lado, math.floor(k / 2) * lado, lado, 5.3 + k * 3.7, true)
    end
    return imagen(datos)
end

function Texturas.chispa()
    local ancho, alto = 64, 16
    local datos, p = lienzo(ancho, alto)
    for y = 0, alto - 1 do
        for x = 0, ancho - 1 do
            local u = (x + 0.5) / ancho * 2 - 1
            local v = (y + 0.5) / alto * 2 - 1
            -- Más ancha y brillante en la cabeza (u = 1), afilada en la cola.
            local cabeza = 0.35 + 0.65 * (u * 0.5 + 0.5)
            local a = math.exp(-(v * v) / (0.12 * cabeza)) * (1 - suave(0.75, 1, math.abs(u)))
            local nucleo = math.exp(-(v * v) / 0.03)
            poner(p, y * ancho + x, 0.6 + 0.4 * nucleo, 0, 0, a)
        end
    end
    return imagen(datos)
end

function Texturas.estela()
    local ancho, alto = 256, 64
    local datos, p = lienzo(ancho, alto)
    for y = 0, alto - 1 do
        for x = 0, ancho - 1 do
            local u = (x + 0.5) / ancho
            local v = (y + 0.5) / alto
            local lado = math.abs(v * 2 - 1)
            -- El borde se deshilacha: su posición cambia a lo largo de la cinta.
            local jiron = fractalCiclico(u, v, 5, 3, 1.3)
            local borde = 0.62 + 0.36 * jiron
            local cobertura = 1 - suave(borde * 0.45, borde, lado)
            local grumos = fractalCiclico(u, v, 9, 7, 8.9)
            local a = cobertura * (0.55 + 0.6 * grumos)
            local brillo = 0.8 + 0.25 * (grumos - 0.5) + 0.1 * (1 - lado)
            poner(p, y * ancho + x, brillo, brillo, brillo, math.min(1, a))
        end
    end
    local img = imagen(datos)
    img:setWrap('repeat', 'clamp')
    return img
end

function Texturas.marca()
    local lado = 128
    local datos, p = lienzo(lado, lado)
    for y = 0, lado - 1 do
        for x = 0, lado - 1 do
            local u = (x + 0.5) / lado * 2 - 1
            local v = (y + 0.5) / lado * 2 - 1
            local r = math.sqrt(u * u + v * v)
            local angulo = math.atan2(v, u)
            local borde = fractal(math.cos(angulo) * 1.8 + 4, math.sin(angulo) * 1.8, 2.2)
            -- Rayos de tierra quemada que salen del centro.
            local rayos = fractal(math.cos(angulo) * 5 + 9, math.sin(angulo) * 5 - 3, 6.1)
            local limite = 0.55 + 0.35 * borde + 0.25 * math.max(0, rayos - 0.45)
            local manchas = fractal(u * 4 + 1.1, v * 4 - 2.3, 3.3)
            local a = (1 - suave(limite * 0.3, limite, r)) * (0.65 + 0.5 * manchas)
            -- Centro casi negro (hollín), borde pardo.
            local brillo = 0.08 + 0.35 * suave(0.1, limite, r) + 0.08 * manchas
            poner(p, y * lado + x, brillo, brillo * 0.92, brillo * 0.82, math.min(1, a))
        end
    end
    return imagen(datos)
end

--- Todas, pintadas una vez.
function Texturas.crear()
    local inicio = love.timer.getTime()
    local texturas = {
        humo = Texturas.humo(),
        fuego = Texturas.fuego(),
        chispa = Texturas.chispa(),
        estela = Texturas.estela(),
        marca = Texturas.marca(),
    }
    texturas.segundos = love.timer.getTime() - inicio
    return texturas
end

return Texturas

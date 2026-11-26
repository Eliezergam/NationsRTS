-- Modelos renderizados en Blender con el estilo militar realista
-- (tools/blender/render_sprites_militares.py): el lanzacohetes y el misil.
--
-- lanzacohetes.png es una hoja de 8 columnas (direcciones, cada 45 grados del
-- juego) por 7 filas (posturas: plegado y el frente del contenedor subiendo
-- hasta 35 grados). El centro de cada cuadro es el punto del suelo donde está el camión.
-- misil.png es el misil de perfil apuntando a la derecha: se gira según su
-- trayectoria en pantalla.
--
-- Las hojas terminadas en _color tienen los mismos cuadros, pero solo con las
-- piezas que llevan el color de la nación (franjas y techo de la cabina), ya
-- sombreadas: se dibujan encima, teñidas con ese color.

local Iso = require('mundo.iso')

local Modelos = {}

Modelos.direcciones = 8
Modelos.posturas = 7
Modelos.lado = 200
Modelos.cuadrosMarcha = 4 -- lanzacohetes_marcha.png: 8 direcciones x 4 cuadros
-- Distancia, en píxeles de misil.png, del centro de la imagen al final de la
-- llama: ahí empieza la estela de humo.
Modelos.colaMisil = 110
-- misil.png se renderiza a 3 veces la escala del juego: a 1/3, tamaño real
-- (unos 4 m, 1 px = 10 cm).
Modelos.escalaMisil = 1 / 3

local hoja, cuadros, misil, misilApagado, hojaMarcha, cuadrosMarcha
local hojaColor, hojaMarchaColor

--- Carga una hoja con filtro lineal.
local function cargarHoja(nombre)
    local i = love.graphics.newImage('assets/modelos/' .. nombre)
    i:setFilter('linear', 'linear')
    return i
end

--- Dibuja el cuadro `quad` de `hojaBase` centrado en (vx, vy) y encima el mismo
-- cuadro de su hoja de color `hojaTinte` teñido con `color`.
local function dibujarCuadro(hojaBase, hojaTinte, quad, vx, vy, mitad, color)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(hojaBase, quad, vx, vy, 0, 1, 1, mitad, mitad)
    if color then
        love.graphics.setColor(color[1], color[2], color[3], 1)
        love.graphics.draw(hojaTinte, quad, vx, vy, 0, 1, 1, mitad, mitad)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

local function cargar()
    if hoja then
        return
    end
    hoja = cargarHoja('lanzacohetes.png')
    hojaColor = cargarHoja('lanzacohetes_color.png')
    cuadros = {}
    local ancho, alto = hoja:getDimensions()
    for postura = 0, Modelos.posturas - 1 do
        cuadros[postura] = {}
        for d = 0, Modelos.direcciones - 1 do
            cuadros[postura][d] =
                love.graphics.newQuad(d * Modelos.lado, postura * Modelos.lado, Modelos.lado, Modelos.lado, ancho, alto)
        end
    end
    misil = cargarHoja('misil.png')
    misilApagado = cargarHoja('misil_apagado.png')
    hojaMarcha = cargarHoja('lanzacohetes_marcha.png')
    hojaMarchaColor = cargarHoja('lanzacohetes_marcha_color.png')
    cuadrosMarcha = {}
    local anchoMarcha, altoMarcha = hojaMarcha:getDimensions()
    for c = 0, Modelos.cuadrosMarcha - 1 do
        cuadrosMarcha[c] = {}
        for d = 0, Modelos.direcciones - 1 do
            cuadrosMarcha[c][d] = love.graphics.newQuad(
                d * Modelos.lado,
                c * Modelos.lado,
                Modelos.lado,
                Modelos.lado,
                anchoMarcha,
                altoMarcha
            )
        end
    end
end

-- Medidas del modelo (tools/blender/lanzacohetes_militar.py y
-- render_sprites_militares.py), en unidades de Blender: el contenedor pivota
-- en (x = -0.92, z = 0.42), las bocas están a 1.31 del pivote, sube 35 grados y
-- los 4 tubos están en (y, z) del contenedor. La imagen sale a tamaño real:
-- 1 unidad = 32 px del mundo (3,2 m).
local PIVOTE_X, PIVOTE_Z, LARGO = -0.92, 0.42, 1.31
local ELEVACION = math.rad(35)
local TUBOS = { { -0.1, 0.1 }, { 0.1, 0.1 }, { -0.1, 0.27 }, { 0.1, 0.27 } }
local UNIDAD = 32

--- Boca del tubo `n` (1 a 4) de un lanzacohetes con el contenedor arriba,
-- respecto al punto del suelo del camión, mirando a `angulo`: dx, dy, dz en px
-- del mundo.
function Modelos.bocaTubo(angulo, n)
    local tubo = TUBOS[(n - 1) % #TUBOS + 1]
    local lado, alto = tubo[1], tubo[2]
    local c, s = math.cos(ELEVACION), math.sin(ELEVACION)
    local delante = (PIVOTE_X + LARGO * c - alto * s) * UNIDAD
    local arriba = (PIVOTE_Z + LARGO * s + alto * c) * UNIDAD
    -- +y de Blender (izquierda del camión) es -y del juego.
    local izquierda = lado * UNIDAD
    local fx, fy = math.cos(angulo), math.sin(angulo)
    return fx * delante + fy * izquierda, fy * delante - fx * izquierda, arriba
end

--- Dirección de la hoja (0 a 7) más cercana a un ángulo del mundo.
function Modelos.direccion(angulo)
    local paso = 2 * math.pi / Modelos.direcciones
    return math.floor(angulo / paso + 0.5) % Modelos.direcciones
end

--- Lanzacohetes en el punto (x, y, z) del suelo. `angulo`: hacia dónde miran la
-- cabina y las bocas de los tubos (el contenedor pivota atrás y sube el frente). `elevacion` de 0
-- (plegado) a 1 (contenedor arriba del todo). `color`: el de su nación (franja
-- del contenedor y techo de la cabina).
function Modelos.dibujarLanzacohetes(x, y, z, angulo, elevacion, color)
    cargar()
    local postura = 0
    if elevacion > 0 then
        postura = math.max(1, math.min(Modelos.posturas - 1, math.floor(elevacion * (Modelos.posturas - 1) + 0.5)))
    end
    local vx, vy = Iso.vista(x, y, z)
    local quad = cuadros[postura][Modelos.direccion(angulo)]
    dibujarCuadro(hoja, hojaColor, quad, vx, vy, Modelos.lado / 2, color)
end

--- Lanzacohetes en marcha (plegado): `cuadro` avanza las ruedas y el rebote.
-- `color`: el de su nación.
function Modelos.dibujarLanzacohetesMarcha(x, y, z, angulo, cuadro, color)
    cargar()
    local vx, vy = Iso.vista(x, y, z)
    local quad = cuadrosMarcha[cuadro % Modelos.cuadrosMarcha][Modelos.direccion(angulo)]
    dibujarCuadro(hojaMarcha, hojaMarchaColor, quad, vx, vy, Modelos.lado / 2, color)
end

--- Misil en el punto de la vista (vx, vy), girado `angulo` en pantalla y a
-- `escala` de su imagen. `apagado`: sin llama (recién expulsado del tubo).
function Modelos.dibujarMisil(vx, vy, angulo, escala, apagado)
    cargar()
    local imagen = apagado and misilApagado or misil
    local ancho, alto = imagen:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(imagen, vx, vy, angulo, escala, escala, ancho / 2, alto / 2)
end

return Modelos

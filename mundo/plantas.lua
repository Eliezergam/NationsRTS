-- Plantas procedurales: ninguna igual a otra.
--
-- Cada trozo de terreno reparte sus plantas con un azar que sale de sus
-- coordenadas (Ruido.hash): el mismo trozo da siempre las mismas plantas, pero
-- cada una tiene sus propios números (altura, anchura, capas, lóbulos, tono).
-- Se dibujan como triángulos low-poly con una cara de luz y otra de sombra, y
-- todas las de un trozo van en una sola malla (un solo dibujo por trozo).

local Ruido = require('mundo.ruido')
local Iso = require('mundo.iso')

local Plantas = {}

-- Cuántos intentos de planta por trozo según el bioma, y qué tipos salen. Hay
-- pocas: llanuras abiertas, bosquecillos pequeños y separados, árboles sueltos.
-- `umbral` es cuánto ruido de mancha hace falta para que salgan árboles: bajo
-- en el bosque, alto en la pradera y la zona seca (solo en los bosquecillos).
local POR_BIOMA = {
    bosque = { intentos = 34, umbral = 0.05, tipos = { 'pino', 'pino', 'copa', 'copa', 'arbusto' } },
    pradera = { intentos = 12, umbral = 0.38, tipos = { 'copa', 'arbusto', 'arbusto', 'flores', 'flores', 'pino' } },
    seca = { intentos = 7, umbral = 0.5, tipos = { 'matorral', 'matorral', 'copa', 'roca' } },
    arena = { intentos = 3, umbral = 0.9, tipos = { 'cactus', 'matorral' } },
    roca = { intentos = 12, umbral = 0.5, tipos = { 'penasco', 'penasco', 'roca', 'roca', 'pino' } },
    nieve = { intentos = 6, umbral = 0.5, tipos = { 'pinoNevado', 'roca' } },
    agua = { intentos = 0, umbral = 1, tipos = {} },
}

local ARBOLES = { pino = true, copa = true, pinoNevado = true }

local function variar(color, azar, cuanto)
    local k = 1 + (azar() - 0.5) * cuanto
    local tinte = (azar() - 0.5) * cuanto * 0.5
    return { color[1] * k + tinte, color[2] * k, color[3] * k - tinte }
end

local function oscurecer(color, k)
    return { color[1] * k, color[2] * k, color[3] * k }
end

-- Los vértices van en una lista plana de números (`v.n` vértices, 6 números
-- cada uno: x, y, r, g, b, a): así se pasan a una malla de golpe (y desde un
-- hilo) sin crear una tabla por vértice.
local NUMEROS = 6
Plantas.numerosPorVertice = NUMEROS

local function vertice(v, x, y, r, g, b, a)
    local k = v.n * NUMEROS
    v[k + 1], v[k + 2], v[k + 3], v[k + 4], v[k + 5], v[k + 6] = x, y, r, g, b, a
    v.n = v.n + 1
end

--- Añade un triángulo de color plano a la lista de vértices.
local function tri(v, ax, ay, bx, by, cx, cy, color, alfa)
    local r, g, b, a = color[1], color[2], color[3], alfa or 1
    vertice(v, ax, ay, r, g, b, a)
    vertice(v, bx, by, r, g, b, a)
    vertice(v, cx, cy, r, g, b, a)
end

--- Polígono convexo en abanico, con la mitad izquierda en luz y la derecha en sombra.
local function mancha(v, cx, cy, radioX, radioY, lados, color, azar)
    local luz, sombra = oscurecer(color, 1.12), oscurecer(color, 0.78)
    local puntos = {}

    for k = 0, lados - 1 do
        local a = k / lados * math.pi * 2
        local r = 0.82 + azar() * 0.3
        puntos[#puntos + 1] = { cx + math.cos(a) * radioX * r, cy + math.sin(a) * radioY * r }
    end

    for k = 1, lados do
        local p, q = puntos[k], puntos[k % lados + 1]
        local medio = (p[1] + q[1]) * 0.5
        tri(v, cx, cy, p[1], p[2], q[1], q[2], medio < cx and luz or sombra)
    end
end

local function sombraSuelo(v, x, y, ancho)
    mancha(v, x + ancho * 0.25, y + ancho * 0.05, ancho, ancho * 0.45, 8, { 0, 0, 0 }, function()
        return 0.5
    end)
    -- La mancha anterior es negra y opaca: se aclara con alfa.
    for k = v.n - 24, v.n - 1 do
        v[k * NUMEROS + 6] = 0.22
    end
end

-- Luz del mapa: de arriba a la izquierda de la pantalla.
local LUZ_X, LUZ_Y = -0.6, -0.8

--- Masa de copa con hojas (el dueño, 20-nov: «ponerle hojitas, que se ven
-- raros poligonales»): una base redonda y oscura, la sombra de dentro de la
-- copa, y encima muchas hojas pequeñas en rombo, cada una con su nervio (la
-- mitad clara y la mitad oscura). Las de cara a la luz (arriba a la
-- izquierda) más claras y dibujadas encima; las del otro lado, oscuras.
local function masa(v, cx, cy, rx, ry, _, color, azar)
    -- Base: elipse suave de 12 lados.
    local base = oscurecer(color, 0.62)
    local lados = 12
    local px, py
    for k = 0, lados do
        local a = k / lados * math.pi * 2
        local qx, qy = cx + math.cos(a) * rx * 0.92, cy + math.sin(a) * ry * 0.92
        if px then
            tri(v, cx, cy, px, py, qx, qy, base)
        end
        px, py = qx, qy
    end
    -- Hojas: tantas como quepan (unas 26 en una copa mediana).
    local tam = math.max(3.5, rx * 0.2)
    local n = math.floor(math.max(10, math.min(40, rx * ry / (tam * tam) * 1.6)))
    local hojas = {}
    for _ = 1, n do
        local a = azar() * math.pi * 2
        local r = math.sqrt(azar()) * 0.95
        local ux, uy = math.cos(a) * r, math.sin(a) * r
        local luz = ux * LUZ_X + uy * LUZ_Y
        hojas[#hojas + 1] = { cx + ux * rx, cy + uy * ry, luz + (azar() - 0.5) * 0.5, azar() * math.pi, azar(0.75, 1.25) }
    end
    table.sort(hojas, function(a, b)
        return a[3] < b[3]
    end)
    for _, h in ipairs(hojas) do
        local k = 0.82 + h[3] * 0.28
        local dx, dy = math.cos(h[4]) * tam * h[5], math.sin(h[4]) * tam * h[5] * 0.8
        local wx, wy = -dy * 0.45, dx * 0.45
        local x, y = h[1], h[2]
        tri(v, x - dx, y - dy, x + dx, y + dy, x + wx, y + wy, oscurecer(color, k * 1.08))
        tri(v, x - dx, y - dy, x + dx, y + dy, x - wx, y - wy, oscurecer(color, k * 0.88))
    end
end

-- Especie de un árbol de copa (las de la batalla 3D): roble o abedul,
-- y su verde (PALETA de batalla/vegetacion.lua).
local function especieCopa(azar)
    -- Solo los de la batalla 3D (el pack StyleHex: frondoso y abedul;
    -- batalla/colocacion.lua cambia pinos, abetos y álamos por estos dos).
    if azar() < 0.58 then
        return 'roble', { 0.3, 0.47, 0.16 }
    end
    return 'abedul', { 0.53, 0.66, 0.26 }
end

local DIBUJOS = {}

function DIBUJOS.pino(v, x, y, azar, nevado)
    -- A escala real (1 px = 10 cm): pinos de 7 a 14 m.
    local alto = azar(34, 70) * 2.5
    local ancho = alto * azar(0.28, 0.4)
    local capas = math.floor(azar(3, 5.99))
    local verde = variar(nevado and { 0.24, 0.38, 0.22 } or { 0.2, 0.42, 0.2 }, azar, 0.3)
    sombraSuelo(v, x, y, ancho)
    local tronco = { 0.35, 0.24, 0.16 }
    tri(v, x - 5, y, x + 5, y, x + 5, y - alto * 0.25, oscurecer(tronco, 0.8))
    tri(v, x - 5, y, x + 5, y - alto * 0.25, x - 5, y - alto * 0.25, tronco)

    for k = 0, capas - 1 do
        local base = y - alto * (0.18 + k * 0.72 / capas)
        local punta = base - alto * 0.42
        local w = ancho * (1 - k / (capas + 1))
        local color = oscurecer(verde, 1 + k * 0.06)
        -- Tres caras, como el cono facetado del pino 3D: la de la luz, la
        -- del frente y la de la sombra, con el borde de abajo en picos.
        local m1, m2 = x - w * 0.35, x + w * 0.3
        tri(v, x - w, base, m1, base + w * 0.16, x, punta, oscurecer(color, 1.15))
        tri(v, m1, base + w * 0.16, m2, base + w * 0.14, x, punta, oscurecer(color, 0.95))
        tri(v, m2, base + w * 0.14, x + w, base, x, punta, oscurecer(color, 0.72))
        tri(v, x - w * 0.7, base + w * 0.08, x - w * 0.45, base + w * 0.2, x - w * 0.2, base + w * 0.12, oscurecer(color, 0.85))
        tri(v, x + w * 0.1, base + w * 0.14, x + w * 0.35, base + w * 0.22, x + w * 0.6, base + w * 0.1, oscurecer(color, 0.62))

        if nevado then
            tri(v, x - w * 0.35, punta + (base - punta) * 0.35, x + w * 0.35, punta + (base - punta) * 0.35, x, punta, {
                0.94,
                0.95,
                0.97,
            })
        end
    end
end

function DIBUJOS.pinoNevado(v, x, y, azar)
    DIBUJOS.pino(v, x, y, azar, true)
end

function DIBUJOS.copa(v, x, y, azar)
    -- Árboles de copa de 5 a 10 m, con la forma de los de la batalla 3D
    -- (el dueño, 20-nov: «que se parezcan un poco a los del 3D»).
    local alto = azar(26, 50) * 2.5
    local radio = alto * azar(0.4, 0.62)
    local especie, base = especieCopa(azar)
    local verde = variar(base, azar, 0.2)
    sombraSuelo(v, x, y, radio * 0.9)
    if especie == 'abedul' then
        -- Tronco fino y blanco con sus marcas negras; copa más pequeña y clara.
        local blanco, marca = { 0.88, 0.86, 0.8 }, { 0.12, 0.11, 0.1 }
        local arriba = y - alto * 0.7
        tri(v, x - 3, y, x + 3, y, x + 3, arriba, oscurecer(blanco, 0.82))
        tri(v, x - 3, y, x + 3, arriba, x - 3, arriba, blanco)
        for k = 1, 3 do
            local z = y - alto * (0.12 + k * 0.14)
            tri(v, x - 3, z, x + 2, z - 2, x - 3, z - 4, marca)
        end
        local masas = math.floor(azar(3, 4.99))
        for k = 1, masas do
            local ox = (azar() - 0.5) * radio * 0.8
            local oy = -alto * 0.62 - azar() * alto * 0.3
            local r = radio * azar(0.42, 0.6)
            masa(v, x + ox, y + oy, r, r * 0.9, 7, oscurecer(verde, 0.92 + k * 0.04), azar)
        end
    else
        -- Roble: tronco recio con dos ramas y una copa ancha de varias masas.
        local tronco = { 0.4, 0.28, 0.18 }
        local arriba = y - alto * 0.5
        tri(v, x - 6, y, x + 6, y, x + 6, arriba, oscurecer(tronco, 0.8))
        tri(v, x - 6, y, x + 6, arriba, x - 6, arriba, tronco)
        tri(v, x - 2, arriba + 8, x + 2, arriba + 8, x - radio * 0.5, arriba - alto * 0.12, tronco)
        tri(v, x - 2, arriba + 8, x + 2, arriba + 8, x + radio * 0.5, arriba - alto * 0.12, oscurecer(tronco, 0.8))
        local masas = math.floor(azar(4, 6.99))
        for k = 1, masas do
            local ox = (azar() - 0.5) * radio * 1.1
            local oy = -alto * 0.62 - azar() * alto * 0.3
            local r = radio * azar(0.48, 0.7)
            masa(v, x + ox, y + oy, r, r * 0.85, 8, oscurecer(verde, 0.9 + k * 0.03), azar)
        end
    end
end

function DIBUJOS.arbusto(v, x, y, azar)
    local r = azar(7, 14) * 1.6
    local verde = variar({ 0.34, 0.52, 0.22 }, azar, 0.4)
    sombraSuelo(v, x, y, r)
    mancha(v, x, y - r * 0.6, r, r * 0.7, 6, verde, azar)
    mancha(v, x + r * 0.5, y - r * 0.3, r * 0.6, r * 0.5, 6, oscurecer(verde, 0.9), azar)
end

function DIBUJOS.matorral(v, x, y, azar)
    local r = azar(6, 11) * 1.6
    local color = variar({ 0.55, 0.5, 0.26 }, azar, 0.35)
    mancha(v, x, y - r * 0.4, r, r * 0.55, 5, color, azar)
end

function DIBUJOS.flores(v, x, y, azar)
    local colores = {
        { 0.95, 0.72, 0.2 },
        { 0.92, 0.45, 0.55 },
        { 0.95, 0.95, 0.9 },
        { 0.62, 0.5, 0.9 },
        { 0.95, 0.55, 0.25 },
    }
    local color = colores[math.floor(azar(1, #colores + 0.99))]
    local cuantas = math.floor(azar(4, 9))

    for _ = 1, cuantas do
        local fx, fy = x + (azar() - 0.5) * 26, y + (azar() - 0.5) * 13
        local r = azar(1.6, 3)
        tri(v, fx - r, fy, fx + r, fy, fx, fy - r * 1.4, color)
        tri(v, fx - r, fy, fx + r, fy, fx, fy + r * 0.6, oscurecer(color, 0.8))
    end
end

function DIBUJOS.cactus(v, x, y, azar)
    local alto = azar(18, 34)
    local verde = variar({ 0.36, 0.56, 0.3 }, azar, 0.25)
    sombraSuelo(v, x, y, 6)
    local w = 3.5
    tri(v, x - w, y, x, y, x, y - alto, oscurecer(verde, 1.1))
    tri(v, x - w, y, x, y - alto, x - w, y - alto + 2, oscurecer(verde, 1.1))
    tri(v, x, y, x + w, y, x + w, y - alto + 2, oscurecer(verde, 0.78))
    tri(v, x, y, x + w, y - alto + 2, x, y - alto, oscurecer(verde, 0.78))

    -- Brazos: cuántos y a qué altura, distinto en cada cactus.
    for _ = 1, math.floor(azar(0, 2.99)) do
        local lado = azar() < 0.5 and -1 or 1
        local h = y - alto * azar(0.35, 0.65)
        local bx = x + lado * (w + 6)
        tri(v, x, h, bx, h, bx, h - 3, verde)
        tri(v, bx - 1.5, h, bx + 1.5, h, bx, h - alto * 0.35, oscurecer(verde, lado < 0 and 1.1 or 0.8))
    end
end

function DIBUJOS.roca(v, x, y, azar)
    local r = azar(6, 16)
    local gris = variar({ 0.56, 0.53, 0.5 }, azar, 0.25)
    sombraSuelo(v, x, y, r)
    local h = r * azar(0.6, 1.1)
    tri(v, x - r, y, x, y + r * 0.3, x - r * 0.2, y - h, oscurecer(gris, 1.12))
    tri(v, x, y + r * 0.3, x + r, y, x - r * 0.2, y - h, oscurecer(gris, 0.78))
end

--- Peñasco: una roca grande de las laderas (de 2 a 5 m), con caras marcadas.
function DIBUJOS.penasco(v, x, y, azar)
    local r = azar(22, 46)
    local gris = variar({ 0.5, 0.47, 0.44 }, azar, 0.25)
    sombraSuelo(v, x, y, r)
    local h = r * azar(0.7, 1.2)
    local cima = x + (azar() - 0.5) * r * 0.5
    tri(v, x - r, y, x - r * 0.1, y + r * 0.3, cima, y - h, oscurecer(gris, 1.15))
    tri(v, x - r * 0.1, y + r * 0.3, x + r * 0.55, y + r * 0.1, cima, y - h, oscurecer(gris, 0.85))
    tri(v, x + r * 0.55, y + r * 0.1, x + r, y, cima, y - h, oscurecer(gris, 0.65))
end

--- Plantas de un trozo, sin dibujar: { x, y, h, tipo, semilla } de cada una.
-- Salen de la semilla del mundo y de las coordenadas del trozo, así que el
-- mapa y la escena de batalla ven exactamente las mismas. `dentroDeCiudad(x, y)`
-- quita las que caen en calles.
function Plantas.enTrozo(terreno, tx, ty, dentroDeCiudad)
    local n = 16 * 32
    local x0, y0 = tx * n, ty * n
    local semilla = Ruido.hash(terreno.semilla, tx, ty, 7)
    local azar = Ruido.azar(semilla)
    local bioma = terreno:bioma(x0 + n / 2, y0 + n / 2)
    local reglas = POR_BIOMA[bioma] or POR_BIOMA.pradera
    local plantas = {}

    for _ = 1, reglas.intentos do
        local x, y = x0 + azar() * n, y0 + azar() * n
        local aqui, h = terreno:bioma(x, y)
        local local_ = POR_BIOMA[aqui]

        -- Bosquecillos: el ruido de manchas los agrupa y deja el resto libre.
        if local_ and #local_.tipos > 0 and not dentroDeCiudad(x, y) then
            local tipo = local_.tipos[math.floor(azar(1, #local_.tipos + 0.99))]
            local u = azar()
            local pone

            if ARBOLES[tipo] then
                local ruido = terreno.detalle:simplex(x / 620 + 90, y / 620)
                local t = math.max(0, math.min(1, (ruido - local_.umbral) / 0.3))
                -- Dentro de la mancha, la mayoría; fuera, algún árbol suelto.
                pone = u < t * t * (3 - 2 * t) * 0.9 + 0.015
            else
                pone = u < 0.5
            end

            if pone then
                plantas[#plantas + 1] =
                    { x = x, y = y, h = h, tipo = tipo, semilla = math.floor(azar() * 2147483646) + 1 }
            end
        end
    end

    return plantas
end

-- De lejos (zoom bajo), cada planta se dibuja con su silueta y nada más: sin
-- sombra en el suelo, sin tronco y con menos capas. Mide lo mismo y tiene el
-- mismo color que la de cerca (los mismos números del azar al empezar), así
-- que al cambiar de detalle no salta a la vista.
local LEJOS = {}

function LEJOS.pino(v, x, y, azar, nevado)
    local alto = azar(34, 70) * 2.5
    local ancho = alto * azar(0.28, 0.4)
    azar(3, 5.99)
    local verde = variar(nevado and { 0.24, 0.38, 0.22 } or { 0.2, 0.42, 0.2 }, azar, 0.3)
    local base = y - alto * 0.18
    local punta = y - alto * 0.98
    tri(v, x - ancho, base, x, base + ancho * 0.12, x, punta, oscurecer(verde, 1.15))
    tri(v, x, base + ancho * 0.12, x + ancho, base, x, punta, oscurecer(verde, 0.8))
end

function LEJOS.pinoNevado(v, x, y, azar)
    LEJOS.pino(v, x, y, azar, true)
end

function LEJOS.copa(v, x, y, azar)
    local alto = azar(26, 50) * 2.5
    local radio = alto * azar(0.4, 0.62)
    local _, base = especieCopa(azar)
    local verde = variar(base, azar, 0.2)
    mancha(v, x, y - alto * 0.78, radio * 0.85, radio * 0.75, 5, verde, azar)
end

function LEJOS.arbusto(v, x, y, azar)
    local r = azar(7, 14) * 1.6
    local verde = variar({ 0.34, 0.52, 0.22 }, azar, 0.4)
    mancha(v, x, y - r * 0.6, r * 1.1, r * 0.8, 4, verde, azar)
end

function LEJOS.matorral(v, x, y, azar)
    local r = azar(6, 11) * 1.6
    local color = variar({ 0.55, 0.5, 0.26 }, azar, 0.35)
    mancha(v, x, y - r * 0.4, r, r * 0.55, 4, color, azar)
end

function LEJOS.flores()
    -- Un par de píxeles de lejos: no se dibujan.
end

function LEJOS.cactus(v, x, y, azar)
    local alto = azar(18, 34)
    local verde = variar({ 0.36, 0.56, 0.3 }, azar, 0.25)
    tri(v, x - 3.5, y, x + 3.5, y, x, y - alto, verde)
end

LEJOS.roca = DIBUJOS.roca
LEJOS.penasco = DIBUJOS.penasco

--- Vértices de todas las plantas de un trozo, ordenadas de atrás adelante,
-- añadidos a la lista plana `v` (ver `vertice`). Con `lejos`, la versión
-- sencilla de cada planta. Devuelve cuántas plantas hay. `dentroDeCiudad(x, y)`
-- quita las que caen en calles.
function Plantas.vertices(v, terreno, tx, ty, dentroDeCiudad, lejos)
    local plantas = Plantas.enTrozo(terreno, tx, ty, dentroDeCiudad)

    table.sort(plantas, function(a, b)
        return Iso.profundidad(a.x, a.y) < Iso.profundidad(b.x, b.y)
    end)

    local dibujos = lejos and LEJOS or DIBUJOS

    for _, p in ipairs(plantas) do
        local vx, vy = Iso.vista(p.x, p.y, p.h)
        dibujos[p.tipo](v, vx, vy, Ruido.azar(p.semilla))
    end

    return #plantas
end

--- Malla con todas las plantas de un trozo, ordenadas de atrás adelante. Nil
-- si el trozo no tiene ninguna. `dentroDeCiudad(x, y)` quita las que caen en calles.
function Plantas.mallaTrozo(terreno, tx, ty, dentroDeCiudad)
    local v = { n = 0 }
    local cuantas = Plantas.vertices(v, terreno, tx, ty, dentroDeCiudad)

    if cuantas == 0 or v.n == 0 then
        return nil, 0
    end

    local vertices = {}

    for k = 0, v.n - 1 do
        local i = k * NUMEROS
        vertices[k + 1] = { v[i + 1], v[i + 2], 0, 0, v[i + 3], v[i + 4], v[i + 5], v[i + 6] }
    end

    return love.graphics.newMesh(vertices, 'triangles', 'static'), cuantas
end

-- En la batalla 3D no hay pinos ni abetos (batalla/colocacion.lua los
-- cambia por frondosos y abedules): en el mapa tampoco (el dueño, 20-nov).
-- Donde el bioma pone un pino sale un árbol de copa.
DIBUJOS.pino, DIBUJOS.pinoNevado = DIBUJOS.copa, DIBUJOS.copa
LEJOS.pino, LEJOS.pinoNevado = LEJOS.copa, LEJOS.copa

return Plantas

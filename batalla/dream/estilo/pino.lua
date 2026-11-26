-- Pino procedural con ramas de planos (de la prueba de estilo de Camila,
-- batalla/pruebas_estilo/pino.lua), como los de la referencia: tronco
-- cónico con corteza, tronco desnudo abajo y pisos (verticilos) de ramas
-- arriba. Cada rama es un palo fino de corteza y dos planos cruzados con la
-- textura de agujas recortada (texturas.lua, Texturas.rama): uno casi
-- horizontal y otro girado sobre el eje de la rama. Las ramas se curvan
-- hacia abajo en la punta. Todo sale de la semilla.
--
-- Pino.nuevo(semilla) devuelve dos Geometria (tronco y follaje) en metros,
-- con el origen en el pie del tronco.

local Geometria = require('batalla.dream.estilo.geometria')

local Pino = {}

local function aleatorio(generador, minimo, maximo)
    return minimo + (maximo - minimo) * generador:random()
end

local function normalizar(x, y, z)
    local largo = math.sqrt(x * x + y * y + z * z)
    return x / largo, y / largo, z / largo
end

--- Tronco: cono de `lados` caras con ensanche en el pie.
local function tronco(geometria, altura, radioBase, lados)
    local anillos = 8
    local puntos = {}
    for anillo = 0, anillos do
        local t = anillo / anillos
        local h = altura * t
        local radio = radioBase * (1 - t) ^ 0.9 + radioBase * 0.35 * math.exp(-h * 2.5) + 0.02
        puntos[anillo] = { h = h, radio = radio }
    end
    for anillo = 0, anillos - 1 do
        local a, b = puntos[anillo], puntos[anillo + 1]
        for lado = 0, lados - 1 do
            local angulo0 = lado / lados * math.pi * 2
            local angulo1 = (lado + 1) / lados * math.pi * 2
            local c0, s0 = math.cos(angulo0), math.sin(angulo0)
            local c1, s1 = math.cos(angulo1), math.sin(angulo1)
            local u0 = lado / lados * 2
            local u1 = (lado + 1) / lados * 2
            local v0 = a.h / 3
            local v1 = b.h / 3
            geometria:cuadrilatero(
                { c0 * a.radio, a.h, s0 * a.radio, c0, 0.15, s0, u0, v0 },
                { c0 * b.radio, b.h, s0 * b.radio, c0, 0.15, s0, u0, v1 },
                { c1 * b.radio, b.h, s1 * b.radio, c1, 0.15, s1, u1, v1 },
                { c1 * a.radio, a.h, s1 * a.radio, c1, 0.15, s1, u1, v0 }
            )
        end
    end
end

--- Palo fino (prisma de tres caras) de `a` a `b` con radios ra y rb.
local function palo(geometria, a, b, ra, rb)
    local dx, dy, dz = normalizar(b[1] - a[1], b[2] - a[2], b[3] - a[3])
    -- Dos vectores perpendiculares al palo.
    local px, py, pz = normalizar(-dz, 0, dx)
    local qx = dy * pz - dz * py
    local qy = dz * px - dx * pz
    local qz = dx * py - dy * px
    for lado = 0, 2 do
        local angulo0 = lado / 3 * math.pi * 2
        local angulo1 = (lado + 1) / 3 * math.pi * 2
        local c0, s0 = math.cos(angulo0), math.sin(angulo0)
        local c1, s1 = math.cos(angulo1), math.sin(angulo1)
        local n0 = { px * c0 + qx * s0, py * c0 + qy * s0, pz * c0 + qz * s0 }
        local n1 = { px * c1 + qx * s1, py * c1 + qy * s1, pz * c1 + qz * s1 }
        geometria:cuadrilatero(
            { a[1] + n0[1] * ra, a[2] + n0[2] * ra, a[3] + n0[3] * ra, n0[1], n0[2], n0[3], 0, 0 },
            { a[1] + n1[1] * ra, a[2] + n1[2] * ra, a[3] + n1[3] * ra, n1[1], n1[2], n1[3], 0.3, 0 },
            { b[1] + n1[1] * rb, b[2] + n1[2] * rb, b[3] + n1[3] * rb, n1[1], n1[2], n1[3], 0.3, 1 },
            { b[1] + n0[1] * rb, b[2] + n0[2] * rb, b[3] + n0[3] * rb, n0[1], n0[2], n0[3], 0, 1 }
        )
    end
end

--- Una rama: palo y dos planos de agujas curvados en tres cortes.
local function rama(troncoGeo, follaje, base, azimut, largo, ancho, caida, giro)
    local dx, dz = math.cos(azimut), math.sin(azimut)
    local sx, sz = -dz, dx
    local cortes = { 0, 0.5, 1 }

    --- Centro de la rama a la fracción t del largo.
    local function centro(t)
        local subida = 0.12 * t - caida * t * t
        return base[1] + dx * largo * t, base[2] + subida * largo, base[3] + dz * largo * t
    end

    local c0 = { centro(0) }
    local c1 = { centro(0.55) }
    local c2 = { centro(0.9) }
    palo(troncoGeo, c0, c1, 0.035 + largo * 0.012, 0.025)
    palo(troncoGeo, c1, c2, 0.025, 0.012)

    -- Luz del follaje: normal hacia fuera y hacia arriba (copa redondeada),
    -- no la del plano, para que no se apague al verlo de canto.
    local nx, ny, nz = normalizar(dx * 0.55, 0.85, dz * 0.55)
    for plano = 1, 2 do
        local balanceo = plano == 1 and giro or giro + 1.0
        local anchoPlano = plano == 1 and ancho or ancho * 0.8
        local cosB, sinB = math.cos(balanceo), math.sin(balanceo)
        -- Lado del plano: el lateral de la rama girado `balanceo` sobre su eje.
        local lx, ly, lz = sx * cosB, sinB, sz * cosB
        for k = 1, #cortes - 1 do
            local t0, t1 = cortes[k], cortes[k + 1]
            local ax, ay, az = centro(t0)
            local bx, by, bz = centro(t1)
            local m0 = anchoPlano * 0.5
            local m1 = anchoPlano * 0.5
            follaje:cuadrilatero(
                { ax - lx * m0, ay - ly * m0, az - lz * m0, nx, ny, nz, t0, 0 },
                { bx - lx * m1, by - ly * m1, bz - lz * m1, nx, ny, nz, t1, 0 },
                { bx + lx * m1, by + ly * m1, bz + lz * m1, nx, ny, nz, t1, 1 },
                { ax + lx * m0, ay + ly * m0, az + lz * m0, nx, ny, nz, t0, 1 },
                true
            )
        end
    end
end

--- Punta: tres planos verticales cruzados con la rama puesta de pie.
local function punta(follaje, altura, largo)
    for k = 0, 2 do
        local angulo = k / 3 * math.pi
        local sx, sz = math.cos(angulo), math.sin(angulo)
        local m = largo * 0.28
        local y0 = altura - largo
        local y1 = altura + 0.3
        follaje:cuadrilatero(
            { -sx * m, y0, -sz * m, 0, 1, 0, 0, 0 },
            { -sx * m * 0.1, y1, -sz * m * 0.1, 0, 1, 0, 1, 0 },
            { sx * m * 0.1, y1, sz * m * 0.1, 0, 1, 0, 1, 1 },
            { sx * m, y0, sz * m, 0, 1, 0, 0, 1 },
            true
        )
    end
end

--- Pino de la semilla `semilla`. `detalle` (1 cerca, 2 lejos) reduce ramas.
-- `opciones.abeto`: copa que empieza más abajo y más estrecha (abeto).
-- `opciones.altura`: se escala entero para medir eso (m) hasta la punta.
function Pino.nuevo(semilla, detalle, opciones)
    detalle = detalle or 1
    opciones = opciones or {}
    local generador = love.math.newRandomGenerator(1000 + semilla)
    local troncoGeo = Geometria.nueva()
    local follaje = Geometria.nueva()
    local altura = aleatorio(generador, 15, 23)
    local radioBase = altura * aleatorio(generador, 0.016, 0.022)
    local inicioCopa = altura * aleatorio(generador, 0.36, 0.5)
    local largoMaximo = altura * aleatorio(generador, 0.24, 0.3)
    if opciones.abeto then
        inicioCopa = altura * aleatorio(generador, 0.16, 0.26)
        largoMaximo = altura * aleatorio(generador, 0.2, 0.24)
    end
    tronco(troncoGeo, altura * 0.93, radioBase, detalle == 1 and 8 or 5)

    -- Muñones secos en el tronco desnudo.
    if detalle == 1 then
        for _ = 1, generador:random(2, 5) do
            local h = aleatorio(generador, 2, inicioCopa)
            local azimut = generador:random() * math.pi * 2
            local l = aleatorio(generador, 0.4, 1.2)
            palo(troncoGeo, { 0, h, 0 }, {
                math.cos(azimut) * l,
                h + l * 0.2,
                math.sin(azimut) * l,
            }, 0.04, 0.01)
        end
    end

    local h = inicioCopa
    local azimutPiso = generador:random() * math.pi * 2
    while h < altura - 2 do
        local t = (h - inicioCopa) / (altura - inicioCopa)
        local ramas = generador:random(6, 9)
        if detalle > 1 then
            ramas = math.max(3, ramas - 2)
        end
        for k = 1, ramas do
            local azimut = azimutPiso + k / ramas * math.pi * 2 + aleatorio(generador, -0.35, 0.35)
            local largo = (largoMaximo * (1 - t) ^ 0.85 + 0.7) * aleatorio(generador, 0.75, 1.1)
            local ancho = math.min(3.4, largo * 0.7 + 0.6)
            local caida = aleatorio(generador, 0.18, 0.4) * (1 - t * 0.5)
            local giro = aleatorio(generador, -0.25, 0.25)
            local radioAqui = radioBase * (1 - h / altura)
            local base = { math.cos(azimut) * radioAqui, h, math.sin(azimut) * radioAqui }
            rama(troncoGeo, follaje, base, azimut, largo, ancho, caida, giro)
        end
        azimutPiso = azimutPiso + 2.4
        h = h + aleatorio(generador, 0.8, 1.2) * (1 - t * 0.35) * (detalle > 1 and 1.4 or 1)
    end
    punta(follaje, altura, 3)
    if opciones.altura then
        local factor = opciones.altura / (altura + 0.3)
        troncoGeo:escalar(factor)
        follaje:escalar(factor)
        altura = opciones.altura
    end
    return troncoGeo, follaje, altura
end

return Pino

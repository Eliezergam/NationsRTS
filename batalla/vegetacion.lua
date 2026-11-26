-- Prototipos de la vegetación y las rocas de la batalla, construidos en código
-- (ESTILO-TERRENO.md §3): roble, álamo, abedul, flor y cañas, más el abeto
-- nevado, el nenúfar y el cactus del mapa. No se importa ningún modelo.
--
-- El pino, el abeto, el arbusto, las matas y la roca llevan `estilo`: son los
-- de la prueba de estilo de Camila (batalla/dream/estilo/, texturas y ramas
-- de planos) y se construyen en batalla/dream/estilo/recursos.lua; aquí solo
-- queda su nombre, sus variantes y su altura.
--
-- Cada especie tiene varias variantes que salen de la semilla del mundo
-- (`Ruido.hash(semilla, especie, variante, 4099)`) y hasta tres niveles de
-- detalle. Las medidas del documento están en metros; aquí se pasan a px
-- (1 m = 10 px) con la base del prototipo en el origen.

local Ruido = require('mundo.ruido')
local Terreno = require('mundo.terreno')
local Malla = require('batalla.malla')

local Vegetacion = {}

local M = 10 -- px por metro
local DOS_PI = math.pi * 2

local PALETA = {
    tronco = { 0.4, 0.28, 0.18 },
    cortezaAbedul = { 0.88, 0.86, 0.8 },
    marcaAbedul = { 0.12, 0.11, 0.1 },
    abeto = { 0.12, 0.29, 0.21 },
    roble = { 0.3, 0.47, 0.16 },
    alamo = { 0.46, 0.6, 0.22 },
    abedul = { 0.53, 0.66, 0.26 },
    hierba = { 0.42, 0.56, 0.2 },
    cana = { 0.48, 0.56, 0.24 },
    espiga = { 0.34, 0.22, 0.13 },
    nenufar = { 0.3, 0.48, 0.16 },
    cactus = { 0.36, 0.56, 0.3 },
}
Vegetacion.paleta = PALETA

local COLORES_FLOR = {
    { 0.85, 0.14, 0.1 },
    { 0.96, 0.8, 0.16 },
    { 0.96, 0.95, 0.9 },
    { 0.6, 0.38, 0.8 },
}

local variar = Malla.variarPieza

--- Masa de copa (icosaedro sin deformar) centrada en (x, y, z) m.
local function masa(m, x, y, z, ex, ey, ez, gx, gy, gz, color)
    m:icosaedroLibre(x * M, y * M, z * M, ex * M, ey * M, ez * M, gx, gy, gz, color)
end

--- Tronco o rama entre dos puntos en m.
local function palo(m, x0, y0, z0, x1, y1, z1, r0, r1, lados, color, giro)
    m:prismaEntre(x0 * M, y0 * M, z0 * M, x1 * M, y1 * M, z1 * M, r0 * M, r1 * M, lados, color, giro)
end

-- Especies ---------------------------------------------------------------------------------

local PROTO = {}

function PROTO.Abeto(m, U, lod, nevado)
    local alto = U(10, 13)
    if lod < 2 then
        palo(m, 0, 0, -0.4, 0, 0, 2.0, 0.32, 0.32, lod == 0 and 5 or 4, variar(PALETA.tronco, U, 0.08), 0)
    end
    if lod == 2 then
        local color = variar(PALETA.abeto, U, 0.08)
        m:prisma(0, 0, 1.0 * M, 3.1 * M, 0, (alto - 0.4) * M, 6, color, U(0, 1))
        if nevado then
            m:prisma(
                0,
                0,
                (1.0 + (alto - 0.4) * 0.58) * M,
                3.1 * 0.42 * M,
                0,
                (alto - 0.4) * 0.42 * M + 1,
                6,
                Terreno.colores.nieve,
                0
            )
        end
        return alto + 0.9
    end
    local pisos = math.floor(U(5, 6.99))
    if lod == 1 then
        pisos = 3
    end
    for k = 0, pisos - 1 do
        local f = k / (pisos - 1)
        local r = 3.1 * (1 - f) + 0.9 * f
        local z = 1.4 + f * (alto - 3.6)
        local color = variar(PALETA.abeto, U, 0.08)
        if k % 2 == 0 then
            color = { color[1] * 0.9, color[2] * 0.93, color[3] * 0.93 }
        end
        local giro = U(0, 1)
        m:prisma(0, 0, (z - 0.1) * M, r * M, 0.12 * M, 3.2 * M, 7, color, giro)
        if nevado then
            local nieve = Terreno.colores.nieve
            m:prisma(0, 0, (z - 0.1 + 3.2 * 0.58) * M, r * 0.44 * M, 0.1 * M, 3.2 * 0.42 * M + 1, 7, nieve, giro)
        end
    end
    return alto + 0.9
end

function PROTO.AbetoNevado(m, U, lod)
    return PROTO.Abeto(m, U, lod, true)
end

function PROTO.Roble(m, U, lod)
    local tronco = variar(PALETA.tronco, U, 0.08)
    if lod == 2 then
        masa(m, 0, 0, 6.4, 5.2, 5.2, 3.6, 0, 0, U(0, 3), variar(PALETA.roble, U, 0.08))
        return 10
    end
    palo(m, 0, 0, -0.4, 0, 0, 3.6, 0.55, 0.38, lod == 0 and 6 or 4, tronco, 0)
    if lod == 0 then
        for _ = 1, 2 do
            local a = U(0, DOS_PI)
            local c, s = math.cos(a), math.sin(a)
            palo(m, 0.122 * c, 0.122 * s, 2.91, 1.478 * c, 1.478 * s, 4.89, 0.22, 0.12, 5, tronco, 0)
        end
    end
    local masas = lod == 1 and 3 or math.floor(U(5, 7.99))
    for _ = 1, masas do
        local a = U(0, DOS_PI)
        local d = U(0.8, 2.8)
        local R = U(2.3, 3.2)
        if lod == 1 then
            R = R * 1.25
        end
        masa(
            m,
            math.cos(a) * d,
            math.sin(a) * d,
            U(5.2, 7.6),
            R,
            R,
            0.85 * R,
            U(0, 1),
            U(0, 1),
            0,
            variar(PALETA.roble, U, 0.1)
        )
    end
    return 10
end

function PROTO.Alamo(m, U, lod)
    if lod < 2 then
        palo(m, 0, 0, -0.2, 0, 0, 3.0, 0.36, 0.26, lod == 0 and 5 or 4, variar(PALETA.tronco, U, 0.08), 0)
    end
    local R = 1.9
    masa(m, 0, 0, 7.4, R, R, 3.1 * R, 0, 0, U(0, 3), variar(PALETA.alamo, U, 0.08))
    if lod == 0 then
        for _ = 1, 2 do
            local a = U(0, DOS_PI)
            local r = 1.3
            masa(
                m,
                math.cos(a) * 0.9,
                math.sin(a) * 0.9,
                U(5.5, 8.5),
                r,
                r,
                2.4 * r,
                0,
                0,
                0,
                variar(PALETA.alamo, U, 0.1)
            )
        end
    end
    return 13.3
end

function PROTO.Abedul(m, U, lod)
    local alto = U(6.5, 8)
    local gx, gy = U(-0.08, 0.08), U(-0.08, 0.08)
    local px, py = math.sin(gy) * alto, -math.sin(gx) * alto
    if lod == 2 then
        masa(m, px * 0.8, py * 0.8, alto - 1.5, 2.6, 2.6, 3.0, 0, 0, U(0, 1), variar(PALETA.abedul, U, 0.08))
        return alto + 1
    end
    palo(m, 0, 0, -0.3, px, py, alto - 0.3, 0.22, 0.13, lod == 0 and 5 or 4, variar(PALETA.cortezaAbedul, U, 0.04), 0)
    if lod == 0 then
        for _ = 1, 5 do
            local z = U(0.8, alto - 2.5)
            local a = U(0, DOS_PI)
            local t = z / alto
            local bx = px * t + 0.18 * math.cos(a)
            local by = py * t + 0.18 * math.sin(a)
            m:caja(bx * M, by * M, (z - 0.06) * M, 0.2 * M, 0.2 * M, 0.12 * M, a, PALETA.marcaAbedul)
        end
    end
    local masas = lod == 1 and 2 or math.floor(U(3, 4.99))
    for _ = 1, masas do
        local a = U(0, DOS_PI)
        local d = U(0.3, 1.3)
        local R = U(1.3, 1.9)
        if lod == 1 then
            R = R * 1.2
        end
        local z = alto - 1.5 + U(-1.2, 1.2)
        local t = z / alto
        masa(
            m,
            px * t + math.cos(a) * d,
            py * t + math.sin(a) * d,
            z,
            R,
            R,
            1.25 * R,
            U(0, 1),
            0,
            U(0, 1),
            variar(PALETA.abedul, U, 0.1)
        )
    end
    return alto + 1
end

--- Hojas de una mata: conos de 3 lados inclinados hacia fuera.
local function hojas(m, U, color, cuantas)
    for _ = 1, cuantas do
        local a = U(0, DOS_PI)
        local alto = U(0.5, 0.95)
        local i = U(0.15, 0.45)
        local bx, by = 0.15 * math.cos(a), 0.15 * math.sin(a)
        local tx = bx + alto * math.sin(i) * math.cos(a)
        local ty = by + alto * math.sin(i) * math.sin(a)
        local tz = -0.05 + alto * math.cos(i)
        palo(m, bx, by, -0.05, tx, ty, tz, 0.09, 0, 3, variar(color, U, 0.12), U(0, 1))
    end
end

--- Flor del color `c` (1 a 4): una mata verde con 4 a 6 cabezas.
local function flor(c)
    return function(m, U)
        hojas(m, U, PALETA.hierba, math.floor(U(7, 11.99)))
        for _ = 1, math.floor(U(4, 6.99)) do
            local a = U(0, DOS_PI)
            local d = U(0.05, 0.35)
            local r = 0.16 * M
            m:octaedro(
                math.cos(a) * d * M,
                math.sin(a) * d * M,
                U(0.5, 0.8) * M,
                r,
                r,
                variar(COLORES_FLOR[c], U, 0.08)
            )
        end
        return 0.9
    end
end

PROTO.Flor1 = flor(1)
PROTO.Flor2 = flor(2)
PROTO.Flor3 = flor(3)
PROTO.Flor4 = flor(4)

function PROTO.Canas(m, U)
    for _ = 1, math.floor(U(9, 14.99)) do
        local bx, by = U(-0.5, 0.5), U(-0.5, 0.5)
        local alto = U(1.3, 2.2)
        local gx, gy = U(-0.12, 0.12), U(-0.12, 0.12)
        palo(
            m,
            bx,
            by,
            -0.3,
            bx + math.sin(gy) * alto,
            by - math.sin(gx) * alto,
            alto - 0.3,
            0.05,
            0,
            3,
            variar(PALETA.cana, U, 0.1),
            0
        )
        if U() < 0.35 then
            local cx, cy = bx + gy * alto * 0.4, by - gx * alto * 0.4
            m:prisma(
                cx * M,
                cy * M,
                (alto * 0.72 - 0.3 - 0.16) * M,
                0.08 * M,
                0.08 * M,
                0.32 * M,
                5,
                variar(PALETA.espiga, U, 0.08)
            )
        end
    end
    return 2.2
end

function PROTO.Nenufar(m, U)
    local r = U(0.45, 0.85) * M
    m:prisma(0, 0, 0, r, r, 0.06 * M, 7, variar(PALETA.nenufar, U, 0.12), U(0, 6))
    return 0.06
end

function PROTO.Cactus(m, U)
    local alto = U(1.8, 3.4)
    m:prisma(0, 0, -0.1 * M, 0.35 * M, 0.3 * M, alto * M, 5, variar(PALETA.cactus, U, 0.12))
    return alto
end

-- Variantes por especie y niveles de detalle (0, 1 y 2) que tiene cada una.
Vegetacion.especies = {
    -- Pino y abeto: los del estilo de la batalla (batalla/dream/estilo/pino.lua,
    -- de la prueba de Camila), con sus tres detalles (completo, simplificado e
    -- impostor). Aquí no se construyen: `estilo` y su altura hasta la punta.
    { nombre = 'Pino', variantes = 3, lods = 3, estilo = 'pino', alto = 12.0 },
    { nombre = 'Abeto', variantes = 3, lods = 3, estilo = 'pino', alto = 13.5 },
    { nombre = 'AbetoNevado', variantes = 2, lods = 3 },
    { nombre = 'Roble', variantes = 4, lods = 3 },
    { nombre = 'Alamo', variantes = 2, lods = 3 },
    { nombre = 'Abedul', variantes = 3, lods = 3 },
    -- Arbusto, matas y roca: también del estilo (batalla/dream/estilo/matas.lua
    -- y roca.lua).
    { nombre = 'Arbusto', variantes = 4, lods = 2, estilo = 'arbusto', alto = 1.6 },
    { nombre = 'Mata', variantes = 3, lods = 2, estilo = 'mata', alto = 0.95 },
    { nombre = 'MataSeca', variantes = 2, lods = 2, estilo = 'mata', alto = 0.95 },
    { nombre = 'Flor1', variantes = 2, lods = 1 },
    { nombre = 'Flor2', variantes = 2, lods = 1 },
    { nombre = 'Flor3', variantes = 2, lods = 1 },
    { nombre = 'Flor4', variantes = 2, lods = 1 },
    { nombre = 'Roca', variantes = 5, lods = 1, estilo = 'roca', alto = 0.72 },
    { nombre = 'Canas', variantes = 3, lods = 1 },
    { nombre = 'Nenufar', variantes = 3, lods = 1 },
    { nombre = 'Cactus', variantes = 3, lods = 1 },
    -- Restos abandonados (tools/restos_campo.py, batalla/dream/estilo/arboles_pack.lua):
    -- contenedor (cerrado y con una puerta abierta), bidón y caja de madera.
    { nombre = 'Contenedor', variantes = 2, lods = 1, estilo = 'resto', alto = 2.6 },
    { nombre = 'Bidon', variantes = 1, lods = 1, estilo = 'resto', alto = 0.9 },
    { nombre = 'Caja', variantes = 1, lods = 1, estilo = 'resto', alto = 0.8 },
}

Vegetacion.porNombre = {}
for indice, e in ipairs(Vegetacion.especies) do
    e.indice = indice
    Vegetacion.porNombre[e.nombre] = e
end

--- Construye todas las variantes y niveles de detalle de la semilla del mundo.
-- Devuelve `protos[nombre] = { alto = m, [lod] = { malla LÖVE por variante } }`
-- y el total de triángulos de los prototipos de detalle 0.
function Vegetacion.construir(semillaMundo)
    local protos = {}
    local triangulos = 0
    for _, e in ipairs(Vegetacion.especies) do
        local proto = { alto = e.alto or 1 }
        for lod = 0, e.estilo and -1 or e.lods - 1 do
            proto[lod] = {}
            for v = 1, e.variantes do
                -- La misma semilla en todos los niveles: se parecen.
                local U = Ruido.azar(Ruido.hash(semillaMundo, e.indice, v, 4099))
                local m = Malla.nueva(2048)
                local alto = PROTO[e.nombre](m, U, lod)
                if lod == 0 then
                    proto.alto = math.max(proto.alto, alto or 1)
                    triangulos = triangulos + m:vertices() / 3
                end
                proto[lod][v] = m:crear()
            end
        end
        protos[e.nombre] = proto
    end
    return protos, triangulos
end

return Vegetacion

-- Color del terreno de batalla (`colores_terreno` del paisaje de Blender,
-- traducido en ESTILO-TERRENO.md §2.3), con la paleta exacta del script. Se
-- calcula en cada vértice y se interpola en el triángulo (degradados, no
-- parches); el grano de cerca lo pone el shader (dream/textura_terreno.lua).
-- Trabaja con números sueltos y no con tablas: se llama unas 200 000 veces.

local Terreno = require('mundo.terreno')

local ColorTerreno = {}

-- Paleta del terreno (sRGB), exacta del script.
local PRADO_A = { 0.33, 0.5, 0.17 }
local PRADO_B = { 0.46, 0.58, 0.22 }
local SECA = { 0.68, 0.62, 0.33 }
local TIERRA = { 0.47, 0.36, 0.23 }
local ARENA = { 0.76, 0.69, 0.5 }
local ROCA = { 0.5, 0.45, 0.4 }
local ROCA_OSC = { 0.36, 0.32, 0.28 }
local BOSQUE = { 0.2, 0.33, 0.12 }
local FONDO = { 0.26, 0.3, 0.0 }
local NIEVE = Terreno.colores.nieve

-- Colores de flor (también tiñen el suelo de su mancha).
ColorTerreno.flores = {
    { 0.85, 0.14, 0.1 },
    { 0.96, 0.8, 0.16 },
    { 0.96, 0.95, 0.9 },
    { 0.6, 0.38, 0.8 },
}

-- Umbrales de pendiente de la roca (§2.3). Medidos con tres semillas: ver
-- el comentario de `Suelo.medirPendientes`.
ColorTerreno.rocaDesde = 0.10
ColorTerreno.rocaHasta = 0.34
-- Un camino de tierra de unos 8 m (el dueño, 19-nov: la franja de tierra de
-- 228 m de los pasillos se veía como un erial). El pasillo sigue libre de
-- árboles, pero con hierba.
ColorTerreno.mitadCamino = 30 -- px de tierra visible a cada lado del eje
ColorTerreno.bordeCamino = 70 -- px hasta fundirse con la pradera

--- Smoothstep de `a` a `b` (si a > b, va de 1 a 0). Con `min` y `max` y
-- no con `if`: LuaJIT lo compila sin ramas (se llama millones de veces).
function ColorTerreno.suave(a, b, x)
    local t = math.min(1, math.max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

local suave = ColorTerreno.suave

--- Tierra pisada en el centro del pasillo, con borde irregular y suave.
function ColorTerreno.pesoCamino(distancia, ruido)
    local borde = ColorTerreno.bordeCamino + (ruido or 0) * 25
    return 1 - suave(ColorTerreno.mitadCamino, borde, distancia)
end

--- Color sRGB (r, g, b) de un vértice. `c` lleva sus campos:
-- x, y, h (px), nx, ny, nz (normal), n1, n2, fino (ruidos), humedad, bosque,
-- dAgua (m), nivelAgua (px), manchas (lista de manchas de flores cercanas).
-- `s` es el suelo (hRef, solX, solY, nivelMar).
--
-- Deja además en `c` el peso (0 a 1) de cada capa, para las texturas del
-- suelo (batalla/dream/terreno_pbr.lua): pSeca, pBosque, pPedregoso,
-- pCamino, pArena, pBarro, pRoca, pNieve y pFondo.
function ColorTerreno.cara(s, c)
    local pendiente = 1 - c.nz
    local zRel = (c.h - s.hRef) / 10
    local n1, fino = c.n1, c.fino
    local solana = math.max(0, c.nx * s.solX + c.ny * s.solY)

    -- 1. Pradera: dos verdes mezclados por el ruido grande (al 70 %: con el
    -- 100 % los saltos entre vecinos se leían como parches).
    local t = 0.5 + 0.35 * n1
    local r = PRADO_A[1] + (PRADO_B[1] - PRADO_A[1]) * t
    local g = PRADO_A[2] + (PRADO_B[2] - PRADO_A[2]) * t
    local b = PRADO_A[3] + (PRADO_B[3] - PRADO_A[3]) * t

    -- 2. Hierba seca: manchas, altura, laderas al sol y bioma 'seca' del mapa.
    local seca = suave(0.05, 0.45, c.n2) * 0.6
    seca = seca + suave(10, 28, zRel) * 0.35
    seca = seca + solana * 1.2 * suave(0.06, 0.2, pendiente)
    seca = seca + suave(-0.1, -0.4, c.humedad) * 0.45
    seca = math.min(0.75, seca)
    c.pSeca = seca / 0.75
    -- Lo más seco del mapa (bioma 'seca') es tierra con piedras.
    c.pPedregoso = suave(-0.3, -0.6, c.humedad) * suave(-0.1, 0.4, c.n2)
    r = r + (SECA[1] - r) * seca
    g = g + (SECA[2] - g) * seca
    b = b + (SECA[3] - b) * seca

    -- 3. Suelo de bosque, más oscuro.
    local bosque = c.bosque * 0.75
    c.pBosque = c.bosque
    r = r + (BOSQUE[1] - r) * bosque
    g = g + (BOSQUE[2] - g) * bosque
    b = b + (BOSQUE[3] - b) * bosque

    -- 4. Manchas de flores: un 10 %.
    if c.manchas then
        for _, f in ipairs(c.manchas) do
            local d = math.sqrt((c.x - f.x) ^ 2 + (c.y - f.y) ^ 2) / 10
            if d < f.r then
                local color = ColorTerreno.flores[f.color]
                local k = 0.1 * suave(f.r, f.r * 0.3, d)
                r = r + (color[1] - r) * k
                g = g + (color[2] - g) * k
                b = b + (color[3] - b) * k
            end
        end
    end

    -- 5. Orillas: arena o tierra húmeda, al 72 %. La costa del mar (bioma
    -- 'arena' del mapa, menos de 12 px sobre el mar) cuenta como orilla.
    local orilla = c.dAgua < 2.4 and c.h < c.nivelAgua + 10
    orilla = orilla or (c.h >= s.nivelMar and c.h < s.nivelMar + 12)
    c.pArena, c.pBarro = 0, 0
    if orilla then
        local arena = n1 > -0.15 and ARENA or TIERRA
        if arena == ARENA then
            c.pArena = 0.72
        else
            c.pBarro = 0.72
        end
        r = r + (arena[1] - r) * 0.72
        g = g + (arena[2] - g) * 0.72
        b = b + (arena[3] - b) * 0.72
    end

    -- 6. Roca en lo empinado y en lo alto (bioma 'roca' del mapa).
    local roca = suave(ColorTerreno.rocaDesde, ColorTerreno.rocaHasta, pendiente + 0.05 * fino)
    -- (Alturas del mapa: con el terreno a tamaño real, batalla/terreno_escalado.lua,
    -- los umbrales se amplían igual.)
    -- En lo alto, solo en las laderas (desde unos 16°): un llano del macizo
    -- con hierba y árboles no es roca. Antes contaba también el llano, y la
    -- foto del acantilado, repetida cada 4 m, salía en filas por el valle y
    -- lavaba el suelo (el dueño, 19-nov: «esos surcos que parecen hoyos»).
    local E = s.escalaMundo or 1
    roca = math.max(roca, suave(140 * E, 200 * E, c.h) * 0.8 * suave(0.04, 0.15, pendiente))
    c.pRoca = roca
    if roca > 0 then
        local m = 0.5 + 0.5 * fino
        local gr = ROCA[1] + (ROCA_OSC[1] - ROCA[1]) * m
        local gg = ROCA[2] + (ROCA_OSC[2] - ROCA[2]) * m
        local gb = ROCA[3] + (ROCA_OSC[3] - ROCA[3]) * m
        local k = roca * (0.78 + 0.22 * suave(-0.3, 0.3, n1))
        r = r + (gr - r) * k
        g = g + (gg - g) * k
        b = b + (gb - b) * k
    end

    -- 7. Nieve del mapa (sobre 900 px, solo las cumbres de los macizos): la batalla corresponde con el mapa.
    local nieve = suave(900 * E, 1000 * E, c.h) * (1 - roca * 0.5)
    c.pNieve = nieve
    r = r + (NIEVE[1] - r) * nieve
    g = g + (NIEVE[2] - g) * nieve
    b = b + (NIEVE[3] - b) * nieve

    -- Los caminos generados se ven como tierra compactada. Su franja ancha
    -- permanece despejada para maniobrar, con hierba en los márgenes.
    local camino = ColorTerreno.pesoCamino(c.dPasillo or math.huge, n1)
    c.pCamino = camino * 0.9
    local tonoTierra = 1.06 + fino * 0.06
    r = r + (TIERRA[1] * tonoTierra - r) * camino * 0.9
    g = g + (TIERRA[2] * tonoTierra - g) * camino * 0.9
    b = b + (TIERRA[3] * tonoTierra - b) * camino * 0.9

    -- 8. Bajo el agua: fondo turbio, más oscuro cuanto más hondo.
    local hondo = (c.nivelAgua - c.h) / 10
    c.pFondo = hondo > 0.05 and suave(0.05, 1.2, hondo) or 0
    if hondo > 0.05 then
        local m = suave(0.05, 1.2, hondo)
        local k = 1 - 0.35 * suave(0.8, 3.0, hondo)
        r = (ARENA[1] + (FONDO[1] - ARENA[1]) * m) * k
        g = (ARENA[2] + (FONDO[2] - ARENA[2]) * m) * k
        b = (ARENA[3] + (FONDO[3] - ARENA[3]) * m) * k
    end

    -- 9. Variación por vértice: +-1,5 % (antes +-4 % por cara, un mosaico).
    local k = 0.985 + 0.015 * fino
    return r * k, g * k, b * k
end

return ColorTerreno

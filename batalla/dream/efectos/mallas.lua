-- Mallas de los escombros (Camila), hechas en código: un terrón o trozo de
-- roca (icosaedro deformado), una astilla (listón afilado) y una chapa
-- (placa fina doblada). Caras planas, del tamaño unidad: el sombreador las
-- escala con el tamaño de cada copia.

local Mallas = {}

local FORMATO = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexNormal', 'byte', 4 },
}

local function aByte(n)
    return n * 0.5 + 0.5
end

--- Malla de LÖVE con los triángulos `caras` ({ {x, y, z} x 3 } cada uno) y
-- la normal de cada cara.
local function construir(caras)
    local vertices = {}
    for _, cara in ipairs(caras) do
        local a, b, c = cara[1], cara[2], cara[3]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local l = math.max(1e-9, math.sqrt(nx * nx + ny * ny + nz * nz))
        nx, ny, nz = nx / l, ny / l, nz / l
        for _, p in ipairs(cara) do
            vertices[#vertices + 1] = { p[1], p[2], p[3], aByte(nx), aByte(ny), aByte(nz), 0 }
        end
    end
    return love.graphics.newMesh(FORMATO, vertices, 'triangles', 'static')
end

local T = (1 + math.sqrt(5)) / 2
local ICOSAEDRO = {
    { -1, T, 0 },
    { 1, T, 0 },
    { -1, -T, 0 },
    { 1, -T, 0 },
    { 0, -1, T },
    { 0, 1, T },
    { 0, -1, -T },
    { 0, 1, -T },
    { T, 0, -1 },
    { T, 0, 1 },
    { -T, 0, -1 },
    { -T, 0, 1 },
}
local CARAS_ICOSAEDRO = {
    { 1, 12, 6 },
    { 1, 6, 2 },
    { 1, 2, 8 },
    { 1, 8, 11 },
    { 1, 11, 12 },
    { 2, 6, 10 },
    { 6, 12, 5 },
    { 12, 11, 3 },
    { 11, 8, 7 },
    { 8, 2, 9 },
    { 4, 10, 5 },
    { 4, 5, 3 },
    { 4, 3, 7 },
    { 4, 7, 9 },
    { 4, 9, 10 },
    { 5, 10, 6 },
    { 3, 5, 12 },
    { 7, 3, 11 },
    { 9, 7, 8 },
    { 10, 9, 2 },
}

--- Trozo de roca o terrón: icosaedro aplastado con los vértices movidos.
function Mallas.roca()
    local azar = love.math.newRandomGenerator(4242)
    local puntos = {}
    local escala = 0.5 / math.sqrt(1 + T * T)
    for k, v in ipairs(ICOSAEDRO) do
        local r = escala * (0.7 + azar:random() * 0.55)
        puntos[k] = { v[1] * r * 1.15, v[2] * r * 0.7, v[3] * r }
    end
    local caras = {}
    for _, c in ipairs(CARAS_ICOSAEDRO) do
        caras[#caras + 1] = { puntos[c[1]], puntos[c[2]], puntos[c[3]] }
    end
    return construir(caras)
end

--- Caja de semiejes (a, b, c) con la cara +X más estrecha (factor `punta`).
local function caja(a, b, c, punta, doblez)
    local function p(x, y, z)
        local f = x > 0 and punta or 1
        return { x * a, y * b * f + math.abs(x) * doblez, z * c * f }
    end
    local v = {
        p(-1, -1, -1),
        p(1, -1, -1),
        p(1, 1, -1),
        p(-1, 1, -1),
        p(-1, -1, 1),
        p(1, -1, 1),
        p(1, 1, 1),
        p(-1, 1, 1),
    }
    local quads = {
        { 1, 2, 3, 4 },
        { 5, 8, 7, 6 },
        { 1, 5, 6, 2 },
        { 2, 6, 7, 3 },
        { 3, 7, 8, 4 },
        { 4, 8, 5, 1 },
    }
    local caras = {}
    for _, q in ipairs(quads) do
        caras[#caras + 1] = { v[q[1]], v[q[2]], v[q[3]] }
        caras[#caras + 1] = { v[q[1]], v[q[3]], v[q[4]] }
    end
    return caras
end

--- Astilla: listón largo y fino que se afila en un extremo.
function Mallas.astilla()
    return construir(caja(0.5, 0.07, 0.045, 0.25, 0))
end

--- Chapa: placa fina, algo doblada.
function Mallas.metal()
    return construir(caja(0.45, 0.025, 0.32, 0.8, 0.12))
end

return Mallas

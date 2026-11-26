-- Marcas de quemado en el suelo (Camila): cada una es una rejilla de 5 x 5
-- vértices pegada al relieve (`suelo:altura`) un palmo por encima, con la
-- textura `marca` de `texturas.lua`. Se guardan en un anillo: la más vieja
-- deja su sitio a la nueva. Solo se sube la marca que cambia, al crearla.

local ffi = require('ffi')

pcall(
    ffi.cdef,
    [[
    typedef struct {
        float x, y, z, w;
        float u, v;
        uint8_t nx, ny, nz, nw;
        uint8_t tx, ty, tz, tw;
    } efectoMarcaVertice;
]]
)

local Marcas = {}
Marcas.__index = Marcas

local LADO = 5 -- vértices por lado
local POR_MARCA = LADO * LADO
local ELEVACION = 1.5 -- px sobre el suelo
local FORMATO = {
    { 'VertexPosition', 'float', 4 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexNormal', 'byte', 4 },
    { 'VertexTangent', 'byte', 4 },
}
local TAMANO = ffi.sizeof('efectoMarcaVertice')

function Marcas.nuevas(dream, conversor, suelo, opciones)
    local self = setmetatable({}, Marcas)
    self.dream = dream
    self.conversor = conversor
    self.suelo = suelo
    self.capacidad = opciones.capacidad
    self.orden = opciones.orden or 0
    self.cursor = 0
    self.usadas = 0
    local vertices = self.capacidad * POR_MARCA
    self.malla = love.graphics.newMesh(FORMATO, vertices, 'triangles', 'dynamic')
    self.malla:setVertices(love.data.newByteData(vertices * TAMANO), 1, vertices)
    local celdas = (LADO - 1) * (LADO - 1)
    local indices = love.data.newByteData(self.capacidad * celdas * 6 * 4)
    local p = ffi.cast('uint32_t*', indices:getFFIPointer())
    local k = 0
    for m = 0, self.capacidad - 1 do
        local base = m * POR_MARCA
        for j = 0, LADO - 2 do
            for i = 0, LADO - 2 do
                local a = base + j * LADO + i
                -- El cambio de eje (Z del juego a Y de Dream) invierte el giro.
                p[k], p[k + 1], p[k + 2] = a, a + LADO + 1, a + 1
                p[k + 3], p[k + 4], p[k + 5] = a, a + LADO, a + LADO + 1
                k = k + 6
            end
        end
    end
    self.malla:setVertexMap(indices, 'uint32')
    self.paso = love.data.newByteData(POR_MARCA * TAMANO)
    self.pPaso = ffi.cast('efectoMarcaVertice*', self.paso:getFFIPointer())

    local material = dream:newMaterial('marcas')
    material:setAlbedoTexture(opciones.textura)
    material:setColor(1, 1, 1, 0.92)
    material:setRoughness(1)
    material:setMetallic(0)
    material:setAlpha()
    material:setCullMode('none')
    local malla = dream:newMesh(material)
    malla.name = 'marcas'
    malla:setShadowVisibility(false)
    malla.boundingSphere = dream:newBoundingSphere(dream.vec3(0, 0, 0), 0)
    local marcas = self
    malla.getMesh = function(_, nombre)
        if nombre ~= nil and nombre ~= 'mesh' then
            return nil
        end
        if marcas.usadas == 0 then
            return nil
        end
        return marcas.malla
    end
    self.dreamMalla = malla
    return self
end

local function aByte(n)
    return math.floor(n * 127.5 + 127.5 + 0.5)
end

--- Marca de `radio` m centrada en (x, y) px, girada `giro` rad.
function Marcas:anadir(x, y, radio, giro)
    local suelo = self.suelo
    local r = radio * 10
    local c, s = math.cos(giro), math.sin(giro)
    local p = self.pPaso
    for j = 0, LADO - 1 do
        for i = 0, LADO - 1 do
            local u = i / (LADO - 1) * 2 - 1
            local v = j / (LADO - 1) * 2 - 1
            local px = x + (u * c - v * s) * r
            local py = y + (u * s + v * c) * r
            local h = suelo:altura(px, py)
            local d = 8
            local nx = suelo:altura(px - d, py) - suelo:altura(px + d, py)
            local ny = suelo:altura(px, py - d) - suelo:altura(px, py + d)
            local nz = 2 * d
            local l = math.sqrt(nx * nx + ny * ny + nz * nz)
            local vx, vy, vz = self.conversor:punto(px, py, h + ELEVACION)
            local q = p[j * LADO + i]
            q.x, q.y, q.z, q.w = vx, vy, vz, 1
            q.u, q.v = u * 0.5 + 0.5, v * 0.5 + 0.5
            q.nx, q.ny, q.nz, q.nw = aByte(nx / l), aByte(nz / l), aByte(ny / l), 0
            q.tx, q.ty, q.tz, q.tw = 255, 128, 128, 0
        end
    end
    self.malla:setVertices(self.paso, self.cursor * POR_MARCA + 1, POR_MARCA)
    self.cursor = (self.cursor + 1) % self.capacidad
    self.usadas = math.min(self.capacidad, self.usadas + 1)
end

function Marcas:dibujar(ox, oy, oz)
    if self.usadas == 0 then
        return
    end
    local centro = self.dreamMalla.boundingSphere.center
    centro[1], centro[2], centro[3] = ox, oy + self.orden, oz
    self.dream:draw(self.dreamMalla)
end

return Marcas

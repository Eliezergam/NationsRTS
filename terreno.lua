-- Terreno infinito: altura, tipo de suelo (bioma) y malla de cada trozo.
--
-- La altura de cualquier punto sale del ruido con la semilla del mundo:
--   continentes  fBm muy ancho: dónde hay tierra y dónde mar
--   cordilleras  crestas que solo suben donde ya hay tierra
--   humedad      otro ruido: pradera seca, pradera verde o bosque
-- Bajo cada ciudad el terreno se aplana suavemente hasta la altura de su plaza.

local Ruido = require('mundo.ruido')
local Iso = require('mundo.iso')

local Terreno = {}
Terreno.__index = Terreno

Terreno.celda = 32 -- px de mundo entre vértices
Terreno.celdasPorTrozo = 16 -- un trozo mide 512 px de lado
Terreno.nivelMar = 0

-- Luz de la tarde, desde arriba a la izquierda de la pantalla.
local LUZ = { -0.45, -0.55, 0.7 }
do
    local l = math.sqrt(LUZ[1] ^ 2 + LUZ[2] ^ 2 + LUZ[3] ^ 2)
    LUZ = { LUZ[1] / l, LUZ[2] / l, LUZ[3] / l }
end

function Terreno.nuevo(semilla)
    local self = setmetatable({}, Terreno)
    self.semilla = semilla
    self.continentes = Ruido.nuevo(semilla)
    self.montes = Ruido.nuevo(semilla + 101)
    self.humedad = Ruido.nuevo(semilla + 202)
    self.detalle = Ruido.nuevo(semilla + 303)
    self.ciudades = nil -- lo pone el mundo: el terreno se aplana bajo ellas
    return self
end

--- Altura natural (sin ciudades), en px de mundo. Negativa = bajo el mar.
function Terreno:base(x, y)
    local c = self.continentes:fbm(x / 5200, y / 5200, 4)
    local tierra = c * 150 + 20
    local cordillera = self.montes:crestas(x / 1500, y / 1500, 4)
    local montes = cordillera * cordillera * math.max(0, c + 0.15) * 520
    local ondas = self.detalle:fbm(x / 520, y / 520, 3) * 14
    return tierra + montes + ondas
end

--- Humedad en [-1, 1]: decide pradera seca, verde o bosque.
function Terreno:humedadEn(x, y)
    return self.humedad:fbm(x / 3000, y / 3000, 3)
end

--- Altura final: la natural, aplanada bajo las ciudades.
function Terreno:altura(x, y)
    local h = self:base(x, y)

    if self.ciudades then
        for _, ciudad in ipairs(self.ciudades:cercanas(x, y)) do
            local dx, dy = x - ciudad.x, y - ciudad.y
            local d = math.sqrt(dx * dx + dy * dy)
            -- El borde según la forma del casco (alargada, irregular...).
            local casco = self.ciudades.borde(ciudad, math.atan2(dy, dx))
            local borde = casco + 260

            if d < borde then
                local t = math.max(0, math.min(1, (borde - d) / (borde - casco * 0.95)))
                t = t * t * (3 - 2 * t)
                h = h + (ciudad.altura - h) * t
            end
        end
    end

    return h
end

local function mezcla(a, b, t)
    t = math.max(0, math.min(1, t))
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local COLORES = {
    hondo = { 0.16, 0.38, 0.6 },
    agua = { 0.26, 0.56, 0.72 },
    arena = { 0.86, 0.77, 0.52 },
    seca = { 0.66, 0.66, 0.32 },
    pradera = { 0.49, 0.63, 0.26 },
    bosque = { 0.32, 0.5, 0.22 },
    roca = { 0.56, 0.49, 0.44 },
    nieve = { 0.95, 0.95, 0.97 },
}
Terreno.colores = COLORES

--- Color del suelo según altura y humedad.
function Terreno:color(h, humedad)
    if h < self.nivelMar then
        return mezcla(COLORES.agua, COLORES.hondo, -h / 90)
    end

    if h < 12 then
        return COLORES.arena
    end

    local verde = mezcla(COLORES.seca, COLORES.pradera, (humedad + 0.2) * 2)
    verde = mezcla(verde, COLORES.bosque, (humedad - 0.15) * 3)
    local c = mezcla(verde, COLORES.roca, (h - 170) / 70)
    return mezcla(c, COLORES.nieve, (h - 300) / 40)
end

--- Bioma de un punto, para las plantas: 'agua', 'arena', 'seca', 'pradera',
-- 'bosque', 'roca' o 'nieve'.
function Terreno:bioma(x, y)
    local h = self:altura(x, y)

    if h < self.nivelMar then
        return 'agua', h
    elseif h < 12 then
        return 'arena', h
    elseif h > 300 then
        return 'nieve', h
    elseif h > 190 then
        return 'roca', h
    end

    local humedad = self:humedadEn(x, y)

    if humedad > 0.2 then
        return 'bosque', h
    elseif humedad < -0.25 then
        return 'seca', h
    end

    return 'pradera', h
end

--- Malla de un trozo (tx, ty): vértices en coordenadas de vista, con el color
-- del suelo y la luz de su ladera en cada vértice. El mar es plano a su nivel.
function Terreno:mallaTrozo(tx, ty)
    local n = Terreno.celdasPorTrozo
    local s = Terreno.celda
    local x0, y0 = tx * n * s, ty * n * s
    local alturas = {}

    -- Una fila y columna de más por cada lado, para las normales del borde.
    for j = -1, n + 1 do
        alturas[j] = {}

        for i = -1, n + 1 do
            alturas[j][i] = self:altura(x0 + i * s, y0 + j * s)
        end
    end

    local puntos = {}

    for j = 0, n do
        puntos[j] = {}

        for i = 0, n do
            local x, y = x0 + i * s, y0 + j * s
            local h = alturas[j][i]
            local visible = math.max(h, self.nivelMar)
            local color = self:color(h, self:humedadEn(x, y))
            local luz

            if h >= self.nivelMar then
                local nx = -(alturas[j][i + 1] - alturas[j][i - 1]) / (2 * s)
                local ny = -(alturas[j + 1][i] - alturas[j - 1][i]) / (2 * s)
                local l = math.sqrt(nx * nx + ny * ny + 1)
                luz = 0.62 + 0.48 * math.max(0, (nx * LUZ[1] + ny * LUZ[2] + LUZ[3]) / l)
            else
                -- El agua brilla un poco donde es poco profunda.
                luz = 0.95 + 0.1 * math.max(0, 1 + h / 40)
            end

            local vx, vy = Iso.vista(x, y, visible)
            puntos[j][i] = { vx, vy, color[1] * luz, color[2] * luz, color[3] * luz }
        end
    end

    local vertices = {}

    local function vertice(p)
        vertices[#vertices + 1] = { p[1], p[2], 0, 0, p[3], p[4], p[5], 1 }
    end

    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local a, b = puntos[j][i], puntos[j][i + 1]
            local c, d = puntos[j + 1][i], puntos[j + 1][i + 1]
            vertice(a)
            vertice(b)
            vertice(d)
            vertice(a)
            vertice(d)
            vertice(c)
        end
    end

    -- `puntos` (posición en la vista de cada vértice) lo usa el territorio para
    -- pintarse encima siguiendo las colinas.
    return love.graphics.newMesh(vertices, 'triangles', 'static'), puntos
end

return Terreno

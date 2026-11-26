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
Terreno.luz = LUZ

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

local function suave(a, b, x)
    local t = math.max(0, math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

--- Altura natural (sin ciudades), en px de mundo. Negativa = bajo el mar.
-- Como en Warpath: llanuras abiertas y colinas muy suaves, y de tarde en
-- tarde un macizo grande y aislado de roca con crestas marcadas.
function Terreno:base(x, y)
    local c = self.continentes:fbm(x / 5200, y / 5200, 2)
    -- Mar hondo y costa con pendiente; tierra adentro, casi llana.
    local tierra = c * 150 + 20

    if c > -0.1 then
        tierra = 5 + (c + 0.1) * 70
    end

    -- Colinas muy suaves (cientos de metros de largo, pocos metros de alto).
    local ondas = self.detalle:fbm(x / 1700, y / 1700, 2) * 22 + self.detalle:fbm(x / 640 + 50, y / 640, 2) * 3

    -- Macizos: donde el ruido ancho pasa de un umbral alto (pocos y separados
    -- por amplias llanuras) sube la base y encima las crestas.
    local zona = self.montes:fbm(x / 20000, y / 20000, 2)
    local macizo = suave(0.42, 0.64, zona) * suave(0.0, 0.35, c + 0.1)
    local montes = 0

    if macizo > 0 then
        local cresta = self.montes:crestas(x / 4200 + 7, y / 4200, 4)
        montes = macizo * (200 + macizo * cresta * cresta * 1500)
    end

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
    roca = { 0.64, 0.57, 0.5 },
    nieve = { 0.95, 0.95, 0.97 },
}
Terreno.colores = COLORES

--- Color del suelo según altura y humedad.
function Terreno:color(h, humedad, x, y, pendiente)
    if h < self.nivelMar then
        return mezcla(COLORES.agua, COLORES.hondo, -h / 90)
    end

    if h < 7 then
        return COLORES.arena
    end

    local verde = mezcla(COLORES.seca, COLORES.pradera, (humedad + 0.55) * 2.5)
    verde = mezcla(verde, COLORES.bosque, (humedad - 0.15) * 3)

    -- Pasto con manchas: tonos que cambian en claros de unas decenas de metros.
    if x then
        local m = self.detalle:simplex(x / 200 + 11, y / 200)
        local k = 1 + m * 0.11
        verde = { verde[1] * k, verde[2] * (1 + m * 0.07), verde[3] * k }
    end

    -- La roca sale en lo alto y en las laderas empinadas de los macizos.
    local roca = math.max((h - 140) / 60, h > 110 and ((pendiente or 0) - 0.3) / 0.35 or 0)
    local piedra = COLORES.roca

    if x and roca > 0 then
        -- Vetas y lascas de roca: tonos que cambian con la ladera.
        local v = 1 + self.detalle:simplex(x / 170, y / 170 + 30) * 0.16
        piedra = { piedra[1] * v, piedra[2] * v, piedra[3] * v * 1.03 }
    end

    local c = mezcla(verde, piedra, roca)
    return mezcla(c, COLORES.nieve, (h - 900) / 100)
end

--- Bioma de un punto, para las plantas: 'agua', 'arena', 'seca', 'pradera',
-- 'bosque', 'roca' o 'nieve'.
function Terreno:bioma(x, y)
    local h = self:altura(x, y)

    if h < self.nivelMar then
        return 'agua', h
    elseif h < 7 then
        return 'arena', h
    elseif h > 900 then
        return 'nieve', h
    elseif h > 170 then
        return 'roca', h
    end

    local humedad = self:humedadEn(x, y)

    if humedad > 0.2 then
        return 'bosque', h
    elseif humedad < -0.45 then
        return 'seca', h
    end

    return 'pradera', h
end

--- Malla de un trozo (tx, ty): por vértice, su punto del mundo, su altura y
-- su pendiente; el color y la luz los pone la GPU (`mundo/sombreado.lua`).
-- Devuelve también `puntos`: la posición en la vista de cada vértice (el mar,
-- plano a su nivel), que usa el territorio para pegarse a las colinas.
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
    local datos = {}

    for j = 0, n do
        puntos[j] = {}
        datos[j] = {}

        for i = 0, n do
            local x, y = x0 + i * s, y0 + j * s
            local h = alturas[j][i]
            local nx = -(alturas[j][i + 1] - alturas[j][i - 1]) / (2 * s)
            local ny = -(alturas[j + 1][i] - alturas[j - 1][i]) / (2 * s)
            local vx, vy = Iso.vista(x, y, math.max(h, self.nivelMar))
            puntos[j][i] = { vx, vy }
            datos[j][i] = { x, y, h, nx, ny }
        end
    end

    local vertices = {}

    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local a, b = datos[j][i], datos[j][i + 1]
            local c, d = datos[j + 1][i], datos[j + 1][i + 1]
            vertices[#vertices + 1] = a
            vertices[#vertices + 1] = b
            vertices[#vertices + 1] = d
            vertices[#vertices + 1] = a
            vertices[#vertices + 1] = d
            vertices[#vertices + 1] = c
        end
    end

    local formato = { { 'VertexPosition', 'float', 2 }, { 'Suelo', 'float', 3 } }
    return love.graphics.newMesh(formato, vertices, 'triangles', 'static'), puntos
end

return Terreno

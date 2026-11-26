-- Yacimientos: petróleo, metal, oro y comida (diseno/territorio-y-capitales.md, 3.8).
--
-- Como las ciudades, salen de la semilla: el mundo se divide en celdas de
-- `celda` px y cada celda puede tener un yacimiento en un punto al azar, del
-- tipo que mejor le va al terreno (F10). Producen para la nación que los
-- explota, y solo se explotan dentro del territorio propio: son motivo de
-- banderas y de guerra.

local Ruido = require('mundo.ruido')
local Iso = require('mundo.iso')
local Ondear = require('mundo.ondear')
local Llano = require('mundo.llano')
local Ciudades = require('mundo.ciudades')

local Recursos = {}
Recursos.__index = Recursos

Recursos.region = 8192 -- se piden por regiones de este lado (caché, zonas y trozos)
Recursos.celda = 3200 -- una prueba de yacimiento por celda (F10)
Recursos.densidad = { petroleo = 0.6, metal = 0.9, oro = 0.3, comida = 0.6 }
Recursos.orden = { 'oro', 'metal', 'petroleo', 'comida' } -- desempate entre aptitudes iguales
Recursos.alcanceLlano = 2000 -- px (m de la batalla) de la veta a lo llano donde va la mina
Recursos.lejosCiudad = 700 -- px fuera del casco de una ciudad, como poco

function Recursos.nuevo(terreno, ciudades)
    local self = setmetatable({}, Recursos)
    self.terreno = terreno
    self.ciudades = ciudades
    self.regiones = {}
    self.celdas = {}
    return self
end

--- Pendiente del terreno natural en (x, y): |∇altura| medida a ±100 px.
function Recursos:pendiente(x, y)
    local t = self.terreno
    local dx = t:base(x + 100, y) - t:base(x - 100, y)
    local dy = t:base(x, y + 100) - t:base(x, y - 100)
    return math.sqrt(dx * dx + dy * dy) / 200
end

--- Aptitud de (x, y) para cada tipo (tabla de 3.8), el bioma y la altura; nil
-- en el agua.
function Recursos:aptitudes(x, y)
    local t = self.terreno
    local bioma, h = t:bioma(x, y)
    if bioma == 'agua' then
        return nil
    end
    local humedad = t:humedadEn(x, y)
    local pendiente = self:pendiente(x, y)
    local costa = false
    for _, o in ipairs({ { 300, 0 }, { -300, 0 }, { 0, 300 }, { 0, -300 } }) do
        if t:base(x + o[1], y + o[2]) < 0 then
            costa = true
        end
    end
    local media = (t:base(x + 400, y) + t:base(x - 400, y) + t:base(x, y + 400) + t:base(x, y - 400)) / 4
    -- El terreno no tiene ríos: un "cauce" es un valle húmedo.
    local cauce = h > 12 and h < 190 and humedad > 0.1 and h < media - 3
    local a = {}
    if bioma == 'seca' or bioma == 'arena' then
        a.petroleo = 1
    elseif h < 60 and pendiente < 0.1 then
        a.petroleo = 0.4
    elseif costa and h < 40 then
        a.petroleo = 0.7
    else
        a.petroleo = 0
    end
    if h > 170 then
        a.metal = 1
    elseif h > 110 then
        a.metal = 0.7
    elseif pendiente > 0.15 then
        a.metal = 0.5
    else
        a.metal = 0
    end
    if cauce then
        a.oro = 1
    elseif h > 220 then
        a.oro = 0.5
    else
        a.oro = 0
    end
    local cultivable = (bioma == 'pradera' or bioma == 'bosque')
        and humedad > -0.1
        and humedad < 0.45
        and pendiente < 0.3
        and h < 150
    a.comida = cultivable and 1 or 0
    return a, bioma, h
end

--- Yacimiento de la celda (cx, cy) o false (F10). Siempre se tiran los cuatro
-- números, haya yacimiento o no.
function Recursos:deCelda(cx, cy)
    local clave = cx .. ',' .. cy
    local guardado = self.celdas[clave]
    if guardado ~= nil then
        return guardado
    end
    local azar = Ruido.azar(Ruido.hash(self.terreno.semilla, cx, cy, 91))
    local x = (cx + azar(0.1, 0.9)) * Recursos.celda
    local y = (cy + azar(0.1, 0.9)) * Recursos.celda
    local u = azar()
    local r = azar()
    local yacimiento = false
    if not self.ciudades:dentro(x, y) then
        local aptitud, _, h = self:aptitudes(x, y)
        if aptitud then
            local tipo, mejor
            for _, k in ipairs(Recursos.orden) do
                if aptitud[k] > 0 and (not mejor or aptitud[k] > mejor) then
                    tipo, mejor = k, aptitud[k]
                end
            end
            if tipo and u < Recursos.densidad[tipo] * mejor then
                local riqueza
                if tipo == 'oro' then
                    riqueza = 1 + math.floor(r * 1.99)
                else
                    riqueza = 1 + math.floor(r * 2.99)
                end
                -- La veta decide el tipo (el metal, en los macizos); la mina
                -- (recinto y aeródromo) va en lo llano más cercano, fuera de
                -- las ciudades, como en el mapa 3D (mundo/llano.lua). Si no
                -- hay sitio llano cerca, no hay mina (el dueño, 20-nov).
                local ciudades = self.ciudades
                local lx, ly = Llano.buscar(self.terreno, x, y, Llano.huellaMina, Recursos.alcanceLlano, nil, function(px, py)
                    for _, c in ipairs(ciudades:cercanas(px, py)) do
                        if Ciudades.cerca(c, px, py, Recursos.lejosCiudad) then
                            return false
                        end
                    end
                    return true
                end)
                if lx then
                    yacimiento = {
                        id = 'y:' .. clave,
                        tipo = tipo,
                        x = lx,
                        y = ly,
                        altura = self.terreno:base(lx, ly),
                        riqueza = riqueza,
                    }
                end
            end
        end
    end
    self.celdas[clave] = yacimiento
    return yacimiento
end

--- Yacimientos de la región (rx, ry): `{ id, tipo, x, y, riqueza, altura }`,
-- los de las celdas cuyo punto cae dentro de la región (así cada uno sale en
-- una sola región).
function Recursos:deRegion(rx, ry)
    local clave = rx .. ',' .. ry
    if self.regiones[clave] then
        return self.regiones[clave]
    end
    local lado, celda = Recursos.region, Recursos.celda
    local lista = {}
    -- Con las celdas de alrededor: una mina se mueve hasta `alcanceLlano`.
    local m = Recursos.alcanceLlano
    for cy = math.floor((ry * lado - m) / celda), math.floor(((ry + 1) * lado - 1 + m) / celda) do
        for cx = math.floor((rx * lado - m) / celda), math.floor(((rx + 1) * lado - 1 + m) / celda) do
            local d = self:deCelda(cx, cy)
            if d and math.floor(d.x / lado) == rx and math.floor(d.y / lado) == ry then
                lista[#lista + 1] = d
            end
        end
    end
    self.regiones[clave] = lista
    return lista
end

-- Dibujo ------------------------------------------------------------------------------

local function poligono(color, ...)
    love.graphics.setColor(color)
    love.graphics.polygon('fill', ...)
end

local function p(x, y, z)
    return Iso.vista(x, y, z)
end

--- Aro del color de la nación que lo controla (o gris si es de nadie).
local function aro(d, color)
    local vx, vy = p(d.x, d.y, d.altura)
    love.graphics.setColor(color[1], color[2], color[3], 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.ellipse('line', vx, vy, 44, 22)
    love.graphics.setLineWidth(1)
end

local function mina(d)
    local x, y, z = d.x, d.y, d.altura
    local vx, vy = p(x, y, z)
    love.graphics.setColor(0.16, 0.14, 0.13)
    love.graphics.ellipse('fill', vx - 10, vy + 4, 12, 6)
    -- Montón de mineral.
    local ax, ay = p(x + 14, y + 6, z)
    local bx, by = p(x + 26, y + 6, z)
    local cx, cy = p(x + 20, y + 6, z + 14)
    poligono({ 0.5, 0.46, 0.44 }, ax, ay, bx, by, cx, cy)
    -- Castillete de madera.
    local pie1x, pie1y = p(x - 16, y - 10, z)
    local pie2x, pie2y = p(x - 4, y - 10, z)
    local topx, topy = p(x - 10, y - 10, z + 38)
    love.graphics.setColor(0.42, 0.3, 0.2)
    love.graphics.setLineWidth(3)
    love.graphics.line(pie1x, pie1y, topx, topy, pie2x, pie2y)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.3, 0.3, 0.32)
    love.graphics.circle('fill', topx, topy, 4)
end

local function pozo(d)
    local x, y, z = d.x, d.y, d.altura
    local b1x, b1y = p(x - 10, y + 8, z)
    local b2x, b2y = p(x + 8, y - 8, z)
    local tx, ty = p(x, y, z + 58)
    love.graphics.setColor(0.25, 0.25, 0.28)
    love.graphics.setLineWidth(2)
    love.graphics.line(b1x, b1y, tx, ty, b2x, b2y)
    for k = 1, 4 do
        local t = k / 5
        love.graphics.line(b1x + (tx - b1x) * t, b1y + (ty - b1y) * t, b2x + (tx - b2x) * t, b2y + (ty - b2y) * t)
    end
    -- Bomba de balancín que cabecea (reloj real de la interfaz, con su fase,
    -- mundo/ondear.lua): poste en A, viga, cabeza de caballo sobre el pozo y,
    -- detrás, la biela y la manivela con su contrapeso que gira.
    local t = Ondear.ahora() * 1.6 + Ondear.fase(x, y)
    local giro = t
    local cabeceo = math.sin(giro) * 0.32
    local g = love.graphics
    local px0, py0, pz0 = x + 24, y + 10, z + 22 -- eje de la viga
    local largo = 18
    local ca, sa = math.cos(cabeceo), math.sin(cabeceo)
    -- Extremos de la viga (en el plano x-z del mundo).
    local frente = { px0 + largo * ca, py0, pz0 + largo * sa }
    local cola = { px0 - largo * 0.8 * ca, py0, pz0 - largo * 0.8 * sa }
    -- Poste en A.
    local e1x, e1y = p(px0, py0, pz0)
    local s1x, s1y = p(px0 - 5, py0 + 5, z)
    local s2x, s2y = p(px0 + 5, py0 - 5, z)
    g.setColor(0.3, 0.3, 0.32)
    g.setLineWidth(2)
    g.line(s1x, s1y, e1x, e1y, s2x, s2y)
    -- Manivela y contrapeso, detrás, girando.
    local mx0, mz0 = px0 - largo * 0.8, z + 8
    local mx, mz = mx0 + math.cos(giro) * 5, mz0 + math.sin(giro) * 5
    local m0x, m0y = p(mx0, py0, mz0)
    local m1x, m1y = p(mx, py0, mz)
    g.setColor(0.24, 0.24, 0.26)
    g.setLineWidth(3)
    g.line(m0x, m0y, m1x, m1y)
    g.circle('fill', m1x, m1y, 3.2)
    -- Biela de la manivela a la cola de la viga.
    local cx, cy = p(cola[1], cola[2], cola[3])
    g.setLineWidth(1.5)
    g.line(m1x, m1y, cx, cy)
    -- Viga y cabeza de caballo.
    local fx, fy = p(frente[1], frente[2], frente[3])
    g.setColor(0.8, 0.52, 0.2)
    g.setLineWidth(4)
    g.line(cx, cy, fx, fy)
    local h1x, h1y = p(frente[1] + 2 * ca, py0, frente[3] + 6 + 2 * sa)
    local h2x, h2y = p(frente[1] + 3 * ca, py0, frente[3] - 7 + 3 * sa)
    g.setLineWidth(3)
    g.line(h1x, h1y, h2x, h2y)
    -- Cable de la cabeza al pozo.
    local bx, by = p(frente[1] + 3, py0, z + 4)
    g.setColor(0.2, 0.2, 0.2)
    g.setLineWidth(1)
    g.line(h2x, h2y, bx, by)
end

local function granja(d)
    local x, y, z = d.x, d.y, d.altura
    local colores = { { 0.78, 0.7, 0.3 }, { 0.5, 0.64, 0.26 }, { 0.62, 0.5, 0.3 } }
    for k = 0, 2 do
        local ox = x - 40 + k * 26
        local ax, ay = p(ox, y - 30, z)
        local bx, by = p(ox + 22, y - 30, z)
        local cx, cy = p(ox + 22, y + 30, z)
        local dx, dy = p(ox, y + 30, z)
        poligono(colores[k % 3 + 1], ax, ay, bx, by, cx, cy, dx, dy)
        love.graphics.setColor(0, 0, 0, 0.12)
        for s = 1, 4 do
            local fy = y - 30 + s * 12
            local lx, ly = p(ox, fy, z)
            local rx, ry = p(ox + 22, fy, z)
            love.graphics.line(lx, ly, rx, ry)
        end
    end
    -- Granero.
    local x0, y0, x1, y1 = x + 40, y - 10, x + 58, y + 10
    local a, b, c, e = { p(x0, y1, z) }, { p(x1, y1, z) }, { p(x1, y1, z + 16) }, { p(x0, y1, z + 16) }
    poligono({ 0.7, 0.26, 0.2 }, a[1], a[2], b[1], b[2], c[1], c[2], e[1], e[2])
    local f, g, h, i = { p(x1, y1, z) }, { p(x1, y0, z) }, { p(x1, y0, z + 16) }, { p(x1, y1, z + 16) }
    poligono({ 0.55, 0.2, 0.16 }, f[1], f[2], g[1], g[2], h[1], h[2], i[1], i[2])
    local r1, r2, r3 = { p(x0, y1, z + 16) }, { p(x1, y1, z + 16) }, { p((x0 + x1) / 2, y1, z + 26) }
    poligono({ 0.5, 0.44, 0.38 }, r1[1], r1[2], r2[1], r2[2], r3[1], r3[2])
end

--- Placer de oro: un montón de grava dorada junto a una batea.
local function placer(d)
    local x, y, z = d.x, d.y, d.altura
    local vx, vy = p(x, y, z)
    love.graphics.setColor(0.36, 0.3, 0.2)
    love.graphics.ellipse('fill', vx, vy + 2, 22, 10)
    local ax, ay = p(x - 12, y + 4, z)
    local bx, by = p(x + 12, y + 4, z)
    local cx, cy = p(x, y + 4, z + 16)
    poligono({ 0.86, 0.68, 0.2 }, ax, ay, bx, by, cx, cy)
    love.graphics.setColor(1, 0.9, 0.45)
    love.graphics.circle('fill', cx - 3, cy + 5, 2)
end

--- Dibuja un yacimiento con el aro de su dueño.
function Recursos.dibujar(d, colorDueno, tiempo)
    aro(d, colorDueno or { 0.6, 0.6, 0.6 })
    if d.tipo == 'metal' then
        mina(d)
    elseif d.tipo == 'petroleo' then
        pozo(d)
    elseif d.tipo == 'oro' then
        placer(d)
    else
        granja(d)
    end
end

return Recursos

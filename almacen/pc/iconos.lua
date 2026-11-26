-- Iconos de archivos de los ordenadores de la sala: carpetas (con su
-- emblema: casa, red), documentos (texto, hoja de cálculo, programa de Lua)
-- y la unidad del equipo. Los usan el escritorio y el explorador «Archivos».
-- Todos se pintan en un cuadrado de `s` px con la esquina en (x, y).

local Dibujo = require('almacen.pc.dibujo')

local Iconos = {}

Iconos.amarillo = { 0.88, 0.68, 0.3 }
Iconos.azul = { 0.36, 0.62, 0.92 }

local function mezclar(c, f)
    return { c[1] * f, c[2] * f, c[3] * f }
end

local function casa(cx, cy, r)
    local g = love.graphics
    g.polygon('fill', cx - r, cy, cx, cy - r * 0.9, cx + r, cy)
    g.rectangle('fill', cx - r * 0.7, cy, r * 1.4, r * 0.85)
end

local function red(cx, cy, r)
    local g = love.graphics
    g.setLineWidth(math.max(1, r * 0.22))
    g.line(cx, cy - r * 0.55, cx, cy + r * 0.1)
    g.line(cx - r, cy + r * 0.1, cx + r, cy + r * 0.1)
    g.line(cx - r, cy + r * 0.1, cx - r, cy + r * 0.5)
    g.line(cx + r, cy + r * 0.1, cx + r, cy + r * 0.5)
    g.setLineWidth(1)
    g.rectangle('fill', cx - r * 0.4, cy - r, r * 0.8, r * 0.6, r * 0.1)
    g.rectangle('fill', cx - r * 1.35, cy + r * 0.45, r * 0.7, r * 0.55, r * 0.1)
    g.rectangle('fill', cx + r * 0.65, cy + r * 0.45, r * 0.7, r * 0.55, r * 0.1)
end

--- Carpeta: lengüeta y fondo, una hoja asomando y la tapa delante.
-- `emblema`: nil, 'casa' o 'red'.
function Iconos.carpeta(x, y, s, color, emblema)
    local g = love.graphics
    color = color or Iconos.amarillo
    local radio = s * 0.07
    g.setColor(mezclar(color, 0.72))
    g.rectangle('fill', x + s * 0.02, y + s * 0.1, s * 0.4, s * 0.16, radio)
    g.rectangle('fill', x + s * 0.02, y + s * 0.17, s * 0.96, s * 0.7, radio)
    g.setColor(0.93, 0.94, 0.95)
    g.rectangle('fill', x + s * 0.1, y + s * 0.22, s * 0.8, s * 0.3, radio * 0.5)
    g.setColor(color)
    g.rectangle('fill', x, y + s * 0.3, s, s * 0.6, radio)
    g.setColor(math.min(1, color[1] * 1.18), math.min(1, color[2] * 1.18), math.min(1, color[3] * 1.18))
    g.rectangle('fill', x + radio, y + s * 0.3, s - radio * 2, math.max(1, s * 0.03))
    if emblema then
        g.setColor(mezclar(color, 0.55))
        local cx, cy, r = x + s * 0.5, y + s * 0.6, s * 0.15
        if emblema == 'casa' then
            casa(cx, cy + r * 0.1, r)
        elseif emblema == 'red' then
            red(cx, cy, r)
        end
    end
end

--- Documento: hoja con la esquina doblada y lo de dentro según su tipo
-- ('texto', 'hoja' o 'lua'). `vivo`: punto verde (lo escribe la partida).
function Iconos.documento(x, y, s, tipo, vivo)
    local g = love.graphics
    local x0, x1 = x + s * 0.16, x + s * 0.84
    local y0, y1 = y + s * 0.02, y + s * 0.98
    local d = s * 0.2
    g.setColor(0.94, 0.95, 0.96)
    g.polygon('fill', x0, y0, x1 - d, y0, x1, y0 + d, x1, y1, x0, y1)
    g.setColor(0.72, 0.75, 0.78)
    g.polygon('fill', x1 - d, y0, x1, y0 + d, x1 - d, y0 + d)
    local m = s * 0.12
    if tipo == 'hoja' then
        g.setColor(0.2, 0.62, 0.36)
        g.rectangle('fill', x0 + m * 0.6, y0 + d + m * 0.3, x1 - x0 - m * 1.2, s * 0.1)
        g.setColor(0.55, 0.62, 0.6)
        local ancho, alto = x1 - x0 - m * 1.2, s * 0.5
        local bx, by = x0 + m * 0.6, y0 + d + m * 0.3 + s * 0.1
        g.setLineWidth(math.max(1, s * 0.02))
        g.rectangle('line', bx, by, ancho, alto)
        for k = 1, 3 do
            g.line(bx, by + alto * k / 4, bx + ancho, by + alto * k / 4)
        end
        g.line(bx + ancho * 0.4, by, bx + ancho * 0.4, by + alto)
        g.setLineWidth(1)
    elseif tipo == 'lua' then
        local sangria = { 0, 0.12, 0.12, 0.24, 0.12, 0 }
        local largo = { 0.55, 0.45, 0.6, 0.3, 0.4, 0.25 }
        local colores = { { 0.3, 0.5, 0.85 }, { 0.5, 0.55, 0.6 }, { 0.75, 0.45, 0.2 }, { 0.5, 0.55, 0.6 }, { 0.5, 0.55, 0.6 }, { 0.3, 0.5, 0.85 } }
        for k = 1, 4 do
            g.setColor(colores[k])
            g.rectangle('fill', x0 + m * 0.7 + s * sangria[k], y0 + d + (k - 1) * s * 0.1, s * largo[k], math.max(1, s * 0.045))
        end
        g.setColor(0.22, 0.4, 0.82)
        g.rectangle('fill', x0, y1 - s * 0.24, x1 - x0, s * 0.24)
        g.setColor(1, 1, 1)
        local letra = Dibujo.letra('titulo', math.max(8, math.floor(s * 0.2)))
        g.setFont(letra)
        g.printf('LUA', x0, y1 - s * 0.24 + (s * 0.24 - letra:getHeight()) / 2, x1 - x0, 'center')
    else
        g.setColor(0.58, 0.62, 0.66)
        for k = 1, 6 do
            local largo = (k % 3 == 0) and 0.55 or 1
            g.rectangle('fill', x0 + m * 0.7, y0 + d * 0.6 + k * s * 0.1, (x1 - x0 - m * 1.4) * largo, math.max(1, s * 0.035))
        end
    end
    g.setColor(0.66, 0.69, 0.72)
    g.setLineWidth(math.max(1, s * 0.015))
    g.polygon('line', x0, y0, x1 - d, y0, x1, y0 + d, x1, y1, x0, y1)
    g.setLineWidth(1)
    if vivo then
        local r = s * 0.11
        g.setColor(0.1, 0.11, 0.12)
        g.circle('fill', x1 - r * 0.3, y1 - r * 0.3, r * 1.35)
        g.setColor(Dibujo.verde)
        g.circle('fill', x1 - r * 0.3, y1 - r * 0.3, r)
    end
end

--- La unidad del equipo (la raíz, «/»).
function Iconos.disco(x, y, s)
    local g = love.graphics
    g.setColor(0.42, 0.45, 0.48)
    g.rectangle('fill', x + s * 0.04, y + s * 0.3, s * 0.92, s * 0.46, s * 0.08)
    g.setColor(0.58, 0.61, 0.64)
    g.rectangle('fill', x + s * 0.04, y + s * 0.3, s * 0.92, s * 0.2, s * 0.08)
    g.setColor(0.22, 0.24, 0.26)
    g.rectangle('fill', x + s * 0.12, y + s * 0.58, s * 0.5, s * 0.06)
    g.setColor(Dibujo.verde)
    g.circle('fill', x + s * 0.8, y + s * 0.62, s * 0.05)
end

--- El icono que toca a `nodo` (de almacen/pc/archivos.lua) en `ruta`.
function Iconos.de(nodo, ruta, x, y, s)
    if nodo.carpeta then
        if ruta == '/home/operador' then
            Iconos.carpeta(x, y, s, Iconos.amarillo, 'casa')
        elseif ruta == '/red' or ruta == '/red/almacen' then
            Iconos.carpeta(x, y, s, Iconos.azul, 'red')
        elseif ruta:sub(1, 5) == '/red/' then
            Iconos.carpeta(x, y, s, Iconos.azul)
        else
            Iconos.carpeta(x, y, s, Iconos.amarillo)
        end
    elseif nodo.tipo == 'hoja' then
        Iconos.documento(x, y, s, 'hoja', nodo.leer ~= nil)
    elseif nodo.nombre:match('%.lua$') then
        Iconos.documento(x, y, s, 'lua', nodo.leer ~= nil)
    else
        Iconos.documento(x, y, s, 'texto', nodo.leer ~= nil)
    end
end

return Iconos

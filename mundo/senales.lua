-- Señales del mapa en píxeles de pantalla: los iconos de los yacimientos
-- (diseno/territorio-y-capitales.md, 3.8) y el mástil de las banderas (3.7).
-- Tienen el mismo tamaño a cualquier zoom: quien llama ya ha puesto la
-- escala 1 / zoom en el punto del mapa (como las fichas de los ejércitos).
--
-- Solo dibujan lo que se les pasa: no leen ni cambian la simulación.

local Tema = require('interfaz.tema')
local Ondear = require('mundo.ondear')
local Estandartes = require('mundo.estandartes')

local Senales = {}

local GRIS = { 0.62, 0.6, 0.56 }

--- Gota de petróleo, negra con un brillo.
local function gota(cx, cy, r, alfa)
    local g = love.graphics
    g.setColor(0.1, 0.1, 0.12, alfa)
    g.circle('fill', cx, cy + r * 0.28, r * 0.52)
    g.polygon('fill', cx, cy - r * 0.78, cx - r * 0.47, cy + r * 0.1, cx + r * 0.47, cy + r * 0.1)
    g.setColor(0.7, 0.72, 0.8, 0.8 * alfa)
    g.circle('fill', cx - r * 0.18, cy + r * 0.2, r * 0.13)
end

--- Pico de minero sobre un lingote gris.
local function pico(cx, cy, r, alfa)
    local g = love.graphics
    g.setColor(0.6, 0.62, 0.66, alfa)
    g.polygon(
        'fill',
        cx - r * 0.55,
        cy + r * 0.35,
        cx + r * 0.55,
        cy + r * 0.35,
        cx + r * 0.72,
        cy + r * 0.72,
        cx - r * 0.72,
        cy + r * 0.72
    )
    -- Mango de madera en diagonal.
    g.setColor(0.62, 0.42, 0.24, alfa)
    g.setLineWidth(math.max(1.5, r * 0.2))
    g.line(cx - r * 0.5, cy + r * 0.3, cx + r * 0.35, cy - r * 0.55)
    -- Cabeza curva de hierro.
    g.setColor(0.82, 0.84, 0.88, alfa)
    g.setLineWidth(math.max(1.5, r * 0.22))
    g.arc('line', 'open', cx + r * 0.6, cy - r * 0.05, r * 0.72, math.pi * 1.05, math.pi * 1.55)
    g.setLineWidth(1)
end

--- Pepita de oro: un polígono irregular dorado con un brillo leve.
local function pepita(cx, cy, r, alfa)
    local g = love.graphics
    local puntos = {
        cx - r * 0.62,
        cy + r * 0.05,
        cx - r * 0.3,
        cy - r * 0.5,
        cx + r * 0.18,
        cy - r * 0.58,
        cx + r * 0.66,
        cy - r * 0.12,
        cx + r * 0.5,
        cy + r * 0.45,
        cx - r * 0.1,
        cy + r * 0.6,
    }
    g.setColor(0.96, 0.76, 0.18, alfa)
    for _, t in ipairs(love.math.triangulate(puntos)) do
        g.polygon('fill', t)
    end
    g.setColor(0.55, 0.38, 0.08, alfa)
    g.setLineWidth(1)
    g.polygon('line', puntos)
    g.setColor(1, 0.97, 0.75, 0.9 * alfa)
    g.circle('fill', cx - r * 0.12, cy - r * 0.2, r * 0.14)
end

--- Espiga verde: tallo y granos a los dos lados.
local function espiga(cx, cy, r, alfa)
    local g = love.graphics
    g.setColor(0.46, 0.66, 0.24, alfa)
    g.setLineWidth(math.max(1.2, r * 0.14))
    g.line(cx, cy + r * 0.8, cx, cy - r * 0.55)
    g.setLineWidth(1)
    g.setColor(0.72, 0.8, 0.3, alfa)
    for k = 0, 2 do
        local gy = cy - r * 0.45 + k * r * 0.34
        g.ellipse('fill', cx - r * 0.2, gy, r * 0.17, r * 0.1)
        g.ellipse('fill', cx + r * 0.2, gy, r * 0.17, r * 0.1)
    end
    g.ellipse('fill', cx, cy - r * 0.68, r * 0.1, r * 0.17)
end

local DIBUJOS = { petroleo = gota, metal = pico, oro = pepita, comida = espiga }

--- Lado en pantalla del icono de un yacimiento (más pequeño muy de lejos).
function Senales.ladoYacimiento(zoom)
    return Tema.px((zoom or 1) < 0.14 and 18 or 24)
end

--- Dos espadas cruzadas centradas en (cx, cy), de radio `r`.
local function espadas(cx, cy, r)
    local g = love.graphics
    Tema.color('olivaNegro', 0.9)
    g.circle('fill', cx, cy, r * 1.5)
    Tema.color('rojoTexto')
    g.setLineWidth(math.max(1.5, r * 0.35))
    g.line(cx - r, cy + r, cx + r, cy - r)
    g.line(cx - r, cy - r, cx + r, cy + r)
    g.setLineWidth(1)
end

--- Icono de un yacimiento con el centro en (cx, cy). `y` es el de
-- `sim:yacimientosEn` / `sim:mina` (tipo, riqueza, queda, reserva, cerrada,
-- diasCerrada, batalla). `estilo` = { aro (color del dueño o nil), tuyo,
-- puntos (dibujar la riqueza y la barra), escudo (combinación del escudo de
-- quien más recolecta, o nil), naciones (cuántas recolectan), bonus (tus
-- recolectores tienen el +25 % de tu territorio) }. Encima, a la derecha, el
-- escudo (con «×N» si son varias naciones); a la izquierda, las espadas de
-- una batalla; debajo, la barra de lo que queda o «Cerrada · N d».
-- Devuelve la caja que ocupa (px de pantalla, respecto al punto de dibujo).
function Senales.yacimiento(y, cx, cy, lado, estilo)
    local g = love.graphics
    local r = lado / 2
    local cerrada = y.cerrada
    local alfa = cerrada and 0.45 or 1
    -- Sombra, disco de fondo y aro del dueño (gris si es de nadie).
    g.setColor(0, 0, 0, 0.3)
    g.circle('fill', cx + 1, cy + 2, r + 2)
    Tema.color(estilo.tuyo and 'olivaClaro' or 'olivaNegro', cerrada and 0.7 or 0.88)
    g.circle('fill', cx, cy, r + 1)
    local aro = (not cerrada and estilo.aro) or GRIS
    g.setColor(aro[1], aro[2], aro[3], 1)
    g.setLineWidth(math.max(1.5, lado * 0.09))
    g.circle('line', cx, cy, r + 1)
    if estilo.tuyo then
        Tema.color('textoHud', 0.9)
        g.setLineWidth(1)
        g.circle('line', cx, cy, r + 3)
    end
    g.setLineWidth(1)
    local dibujo = DIBUJOS[y.tipo] or espiga
    dibujo(cx, cy, r * 0.82, alfa)
    local x0, y0, x1, y1 = cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3
    -- Riqueza: de 1 a 3 puntos encima.
    if estilo.puntos then
        local pr = math.max(1.5, lado * 0.08)
        local paso = pr * 3
        local n = y.riqueza or 1
        local px0 = cx - (n - 1) * paso / 2
        for k = 0, n - 1 do
            Tema.color('olivaNegro', 0.9)
            g.circle('fill', px0 + k * paso, cy - r - pr * 2.2, pr + 1)
            Tema.color('amarillo')
            g.circle('fill', px0 + k * paso, cy - r - pr * 2.2, pr)
        end
        y0 = cy - r - pr * 3.4
    end
    -- Escudo de la nación que más recolecta, a la derecha, sobre una placa.
    if estilo.escudo and not cerrada then
        local alto = lado * 1.1
        local ex, ey = cx + r + Tema.px(4) + alto * 0.45, cy
        Tema.color('olivaNegro', 0.85)
        g.rectangle('fill', ex - alto * 0.55, ey - alto * 0.6, alto * 1.1, alto * 1.2, 3, 3)
        Estandartes.dibujarEscudo(estilo.escudo, ex, ey, 2, alto / 36, 1)
        x1 = math.max(x1, ex + alto * 0.55)
        y0 = math.min(y0, ey - alto * 0.6)
        if (estilo.naciones or 0) > 1 then
            local fuente = Tema.fuente('sansNegrita', 12, 10)
            local texto = '×' .. estilo.naciones
            local tw = fuente:getWidth(texto) + Tema.px(4)
            local tx, ty = ex + alto * 0.55, ey - fuente:getHeight() / 2
            Tema.color('olivaNegro', 0.9)
            g.rectangle('fill', tx, ty, tw, fuente:getHeight(), 2, 2)
            g.setFont(fuente)
            Tema.color('textoHud')
            g.print(texto, tx + Tema.px(2), ty)
            x1 = math.max(x1, tx + tw)
        end
    end
    -- En batalla: dos espadas a la izquierda.
    if y.batalla then
        local er = lado * 0.22
        local ex = cx - r - er * 1.2
        espadas(ex, cy - r * 0.55, er)
        x0 = math.min(x0, ex - er * 1.5)
    end
    -- Debajo: la barra de lo que queda, o «Cerrada · N d».
    local by = cy + r + Tema.px(4)
    if cerrada then
        local fuente = Tema.fuente('sansNegrita', 12, 10)
        local texto = string.format('Cerrada · %d d', y.diasCerrada or 0)
        local tw = fuente:getWidth(texto) + Tema.px(6)
        local tx = math.floor(cx - tw / 2)
        Tema.color('olivaNegro', 0.85)
        g.rectangle('fill', tx, by, tw, fuente:getHeight(), 2, 2)
        g.setFont(fuente)
        Tema.color('textoHudTenue')
        g.print(texto, tx + Tema.px(3), by)
        x0, x1 = math.min(x0, tx), math.max(x1, tx + tw)
        y1 = by + fuente:getHeight()
    elseif estilo.puntos and y.reserva then
        local parte = (y.queda or y.reserva) / math.max(1, y.reserva)
        local ancho, alto = math.floor(lado * 1.2), math.max(2, Tema.px(3))
        local bx = math.floor(cx - ancho / 2)
        Tema.color('olivaNegro', 0.9)
        g.rectangle('fill', bx - 1, by - 1, ancho + 2, alto + 2)
        local c = parte > 0.5 and Tema.colores.amarillo or (parte > 0.2 and Tema.colores.amarillo or Tema.colores.rojo)
        g.setColor(c[1], c[2], c[3], 1)
        g.rectangle('fill', bx, by, math.floor(ancho * math.max(0, math.min(1, parte))), alto)
        y1 = by + alto + 1
    end
    -- Bonus de tu territorio: «+25 %» bajo la barra.
    if estilo.bonus and not cerrada then
        local fuente = Tema.fuente('sansNegrita', 12, 10)
        local texto = '+25 %'
        local tw = fuente:getWidth(texto) + Tema.px(6)
        local tx, ty = math.floor(cx - tw / 2), y1 + Tema.px(2)
        Tema.color('olivaNegro', 0.9)
        g.rectangle('fill', tx, ty, tw, fuente:getHeight(), 2, 2)
        g.setFont(fuente)
        Tema.color('verde')
        g.print(texto, tx + Tema.px(3), ty)
        x0, x1 = math.min(x0, tx), math.max(x1, tx + tw)
        y1 = ty + fuente:getHeight()
    end
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

--- Barra fina de proporción centrada en `cx` (obra o vida de una bandera).
local function barra(cx, y, ancho, alto, parte, color)
    local g = love.graphics
    local x = math.floor(cx - ancho / 2)
    Tema.color('olivaNegro', 0.9)
    g.rectangle('fill', x - 1, y - 1, ancho + 2, alto + 2)
    g.setColor(color[1], color[2], color[3], 1)
    g.rectangle('fill', x, y, math.floor(ancho * math.max(0, math.min(1, parte))), alto)
end

--- Medidas de la señal de una bandera (px de pantalla): alto del mástil y
-- ancho del paño.
function Senales.medidasBandera()
    return Tema.px(40), Tema.px(26)
end

--- Bandera con el pie del mástil en (sx, sy). `b` es la de `sim:banderas`,
-- `color` el de su nación y `escudo` su combinación (Estandartes.escudoDe).
-- Con `soloBarras`, solo las barras (de cerca ya se ve el mástil del mundo).
-- Devuelve la caja que ocupa.
function Senales.bandera(b, sx, sy, color, escudo, soloBarras)
    local g = love.graphics
    local alto, largo = Senales.medidasBandera()
    local pano = math.floor(largo * 0.68)
    local arriba = sy - alto
    local alfa = b.enObra and 0.55 or 1
    if not soloBarras then
        g.setColor(0, 0, 0, 0.3)
        g.ellipse('fill', sx, sy, Tema.px(6), Tema.px(3))
        -- Mástil.
        g.setColor(0.25, 0.18, 0.12, alfa)
        g.setLineWidth(math.max(1.5, Tema.px(2.5)))
        g.line(sx, sy, sx, arriba - Tema.px(3))
        g.setLineWidth(1)
        Tema.color('amarillo', alfa)
        g.circle('fill', sx, arriba - Tema.px(4), Tema.px(2.5))
        -- Paño del color de la nación con su escudo; en obra, a media asta.
        local py = b.enObra and sy - alto * (0.3 + 0.5 * b.progreso) or arriba
        -- El paño ondea con su fase (mundo/ondear.lua); el escudo sigue la onda.
        local contorno, onda =
            Ondear.pano(sx + 1, py, largo, pano, color, Ondear.fase(b.x, b.y), Tema.px(2.2), alfa, 5)
        g.setColor(0.1, 0.07, 0.05, 0.9 * alfa)
        g.polygon('line', contorno)
        if escudo then
            local s = Tema.escala() * 0.72
            Estandartes.dibujarEscudo(escudo, sx + 1 + largo / 2, py + pano / 2 + onda, 1, s, alfa)
        end
    end
    -- Barras bajo el pie: la obra en bronce y, si la atacan, la vida.
    local ancho, gruesa = Tema.px(34), Tema.px(4)
    local by = sy + Tema.px(5)
    if b.enObra then
        barra(sx, by, ancho, gruesa, b.progreso, Tema.colores.amarillo)
        by = by + gruesa + Tema.px(3)
    end
    if b.atacada or b.vida < 99.5 then
        local parte = b.vida / 100
        local c = parte > 0.5 and Tema.colores.verde or (parte > 0.25 and Tema.colores.amarillo or Tema.colores.rojo)
        barra(sx, by, ancho, gruesa, parte, b.atacada and Tema.colores.rojo or c)
        by = by + gruesa + Tema.px(3)
        if b.atacada then
            -- Dos espadas cruzadas junto a la barra: la están atacando.
            local ex, ey, er = sx + ancho / 2 + Tema.px(8), by - gruesa - Tema.px(1), Tema.px(5)
            Tema.color('rojoTexto')
            g.setLineWidth(math.max(1.5, Tema.px(2)))
            g.line(ex - er, ey + er, ex + er, ey - er)
            g.line(ex - er, ey - er, ex + er, ey + er)
            g.setLineWidth(1)
        end
    end
    return { x = sx - ancho / 2, y = arriba - Tema.px(6), w = math.max(ancho, largo + 2), h = by - arriba + Tema.px(6) }
end

return Senales

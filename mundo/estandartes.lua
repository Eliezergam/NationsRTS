-- Estandartes de los ejércitos en el mapa (diseno/ejercitos-en-el-mapa.md, §3.1).
--
-- Cada grupo se dibuja como UNA ficha: un estandarte colgante con el paño del
-- color de su nación y su escudo, y debajo la etiqueta «Gral. X · 1 240»
-- (líder y poder). Los convoyes (obras, entregas) llevan un banderín pequeño
-- sin líder ni poder. El arte es de Camila (assets/estandarte/indice.lua).
--
-- La ficha tiene tamaño fijo en pantalla, se lea con el zoom que se lea: se
-- dibuja en píxeles de pantalla, con la hoja _x2 en pantallas grandes. Solo
-- lee la ficha de la simulación (`sim:fichaGrupo`); no cambia nada.

local Indice = require('assets.estandarte.indice')
local Ruido = require('mundo.ruido')
local Tema = require('interfaz.tema')
local Ondear = require('mundo.ondear')

local Estandartes = {}

local PALIDO = { 0.73, 0.66, 0.52 } -- pergamino tenue: hacia él se mezcla el paño en retirada
local imagenes = {}
local escudos = {} -- nación -> combinación de su escudo (sale de la semilla del mundo)

--- Imagen de assets/estandarte (se carga una sola vez).
local function imagen(archivo)
    local img = imagenes[archivo]
    if img == nil then
        local ruta = Indice.carpeta .. archivo
        img = love.filesystem.getInfo(ruta) and love.graphics.newImage(ruta) or false
        if img then
            img:setFilter('linear', 'linear')
        end
        imagenes[archivo] = img
    end
    return img or nil
end

--- Hoja que toca a esta escala de interfaz: la 1x a tamaño natural hasta 1,4 y,
-- por encima, la _x2 (que mide el doble) escalada. Devuelve el multiplicador
-- de la hoja (1 o 2) y la escala a la que se dibuja.
function Estandartes.escala()
    local e = Tema.escala()
    if e >= 1.4 then
        return 2, e / 2
    end
    return 1, 1
end

--- Medidas de la hoja 1x del estandarte (ancho, alto, ancla, etiqueta).
function Estandartes.medidas()
    return Indice.estandarte
end

--- Semilla del escudo de una nación: una por nación, estable (sale de la
-- semilla del mundo y de su zona 'z:zx,zy'; no se guarda).
function Estandartes.semillaEscudo(semillaMundo, nid)
    local zx, zy = tostring(nid):match('^z:(-?%d+),(-?%d+)$')
    return Ruido.hash(semillaMundo or 0, tonumber(zx) or 0, tonumber(zy) or 0, 4099) % 2147483646 + 1
end

--- Combinación del escudo de una nación (forma, partición, carga y esmaltes).
function Estandartes.escudoDe(semillaMundo, nid)
    local clave = tostring(semillaMundo) .. ':' .. tostring(nid)
    local e = escudos[clave]
    if not e then
        e = Indice.combinar(Estandartes.semillaEscudo(semillaMundo, nid))
        escudos[clave] = e
    end
    return e
end

local function esmalte(nombre)
    return Indice.esmaltes.metales[nombre] or Indice.esmaltes.colores[nombre] or { 1, 1, 1 }
end

local function formaDe(nombre)
    for _, f in ipairs(Indice.formas) do
        if f.nombre == nombre then
            return f
        end
    end
    return Indice.formas[1]
end

local function cargaDe(nombre)
    for _, c in ipairs(Indice.cargas) do
        if c.nombre == nombre then
            return c
        end
    end
    return Indice.cargas[1]
end

--- Dibuja el escudo `combinacion` con su centro en (cx, cy) de pantalla.
-- `hoja` es 1, 2 o 4 (la versión de las imágenes) y `s` la escala a la que se
-- dibuja esa hoja. `alfa` para el escudo pálido de la retirada.
function Estandartes.dibujarEscudo(combinacion, cx, cy, hoja, s, alfa)
    local g = love.graphics
    alfa = alfa or 1
    local forma = formaDe(combinacion.forma)
    local centro = Indice.escudo.centro
    local ox, oy = centro.x * hoja, centro.y * hoja
    local function capa(archivo, color, dx, dy)
        local img = archivo and imagen(Indice.conEscala(archivo, hoja))
        if img then
            g.setColor(color[1], color[2], color[3], alfa)
            g.draw(img, cx, cy, 0, s, s, ox - (dx or 0) * hoja, oy - (dy or 0) * hoja)
        end
    end
    capa(forma.forma, esmalte(combinacion.campo))
    local particion = Indice.archivoParticion(forma.nombre, combinacion.particion)
    if particion then
        capa(particion, esmalte(combinacion.segundo))
    end
    capa(cargaDe(combinacion.carga).archivo, esmalte(combinacion.figura), forma.carga.x, forma.carga.y)
    capa(forma.relieve, { 1, 1, 1 })
end

--- Pose de un grupo: 'retirada', 'combate' (pelea en una batalla,
-- `gr.batalla`, o ataca y ya está en su objetivo) o 'marcha'.
function Estandartes.pose(gr)
    if gr.retirada then
        return 'retirada'
    end
    if gr.batalla then
        return 'combate'
    end
    if gr.mision == 'atacar' and gr.recorrido >= gr.largo and not gr.detenido then
        return 'combate'
    end
    return 'marcha'
end

--- Estandarte de un ejército con el pie del asta en (sx, sy) de pantalla.
-- `ficha` es la de `sim:fichaGrupo`; `izquierda` si va hacia la izquierda de
-- la pantalla (se refleja; el escudo no). Devuelve la caja que ocupa el
-- estandarte (sin la etiqueta), en píxeles de pantalla.
function Estandartes.dibujarEstandarte(sx, sy, ficha, pose, izquierda, semillaMundo)
    local g = love.graphics
    local datos = Indice.estandarte
    local p = datos.poses[pose] or datos.poses.marcha
    local hoja, s = Estandartes.escala()
    local base = imagen(hoja == 2 and p.base2x or p.base)
    local color = imagen(hoja == 2 and p.color2x or p.color)
    local ax, ay = datos.ancla.x * hoja, datos.ancla.y * hoja
    local sx2 = izquierda and -s or s
    local tinte = ficha.color or { 1, 1, 1 }
    local alfaEscudo = 1
    if pose == 'retirada' then
        tinte = Tema.mezcla(tinte, PALIDO, 0.4)
        alfaEscudo = 0.85
    end
    if base then
        g.setColor(1, 1, 1, 1)
        g.draw(base, sx, sy, 0, sx2, s, ax, ay)
    end
    if color then
        g.setColor(tinte[1], tinte[2], tinte[3], 1)
        g.draw(color, sx, sy, 0, sx2, s, ax, ay)
    end
    -- El escudo, sin reflejar: solo se refleja su centro.
    local ex = p.escudo.x
    if izquierda then
        ex = datos.ancla.x - (p.escudo.x - datos.ancla.x)
    end
    local ecx = sx + (ex - datos.ancla.x) * hoja * s
    local ecy = sy + (p.escudo.y - datos.ancla.y) * hoja * s
    local combinacion = Estandartes.escudoDe(semillaMundo, ficha.nacion)
    Estandartes.dibujarEscudo(combinacion, ecx, ecy, hoja, s * (p.escudo.escala or 1), alfaEscudo)
    local ancho, alto = datos.ancho * hoja * s, datos.alto * hoja * s
    local x0 = izquierda and sx - (ancho - ax * s) or sx - ax * s
    return { x = x0, y = sy - ay * s, w = ancho, h = alto }
end

--- Banderín pequeño de un convoy (sin líder ni poder), con el pie en (sx, sy).
--- Escala del banderín en el mapa (el dueño, 2026-09-30: más grande). No sigue
-- a la escala de la interfaz: es parte del mundo.
Estandartes.tamBanderin = 2

function Estandartes.dibujarBanderin(sx, sy, color, izquierda, fase)
    local g = love.graphics
    local e = Estandartes.tamBanderin
    local alto, largoPano = 24 * e, 13 * e
    local lado = izquierda and -1 or 1
    local arriba = sy - alto
    g.setColor(0, 0, 0, 0.25)
    g.ellipse('fill', sx, sy, 4 * e, 2 * e)
    -- Paño triangular del color de la nación, con su borde oscuro; ondea con
    -- su fase (la del grupo, mundo/ondear.lua).
    local puntos = Ondear.banderin(sx, arriba, largoPano, 8 * e, color, fase or 0, 1.4 * e, lado)
    g.setColor(0.1, 0.07, 0.05, 0.9)
    g.setLineWidth(math.max(1, e))
    g.polygon('line', puntos)
    -- Asta.
    g.setColor(0.28, 0.2, 0.13, 1)
    g.setLineWidth(math.max(1.5, 2 * e))
    g.line(sx, sy, sx, arriba - 2 * e)
    g.setLineWidth(1)
    local x0 = izquierda and sx - largoPano or sx - 3 * e
    return { x = x0 - 2 * e, y = arriba - 3 * e, w = largoPano + 6 * e, h = alto + 5 * e }
end

--- ¿Se lee el grupo como recolector? Los que llevan carga de una mina
-- (misión `recolectar`, o `apoyo` y `regreso` redirigidos desde ella) y no
-- tienen líder: van con un banderín y su bolsa, no con un estandarte.
function Estandartes.esRecolector(ficha)
    return ficha.capacidad ~= nil and not ficha.lider
end

-- Color de lo que lleva la bolsa de un recolector, por recurso.
local COLOR_CARGA = {
    metal = { 0.72, 0.74, 0.78 },
    petroleo = { 0.16, 0.16, 0.2 },
    oro = { 0.96, 0.76, 0.18 },
    comida = { 0.56, 0.72, 0.28 },
}

--- Cifra corta de una carga: con un decimal por debajo de 10 («2,4»), entera si no.
function Estandartes.cifraCarga(valor)
    valor = valor or 0
    if valor < 10 then
        return (string.format('%.1f', valor):gsub('%.', ','))
    end
    return Tema.numero(valor)
end

--- Texto de la etiqueta de un recolector: «12 / 30», o «×3 · 36 / 90» si
-- resume varios grupos (`ficha.cuantos`).
function Estandartes.textoRecolector(ficha)
    local texto = Estandartes.cifraCarga(ficha.carga) .. ' / ' .. Estandartes.cifraCarga(ficha.capacidad)
    if (ficha.cuantos or 1) > 1 then
        texto = '×' .. ficha.cuantos .. ' · ' .. texto
    end
    return texto
end

--- Medidas de la ficha de un recolector con el pie en (sx, sy), en px de
-- pantalla: la bolsa (`bx`, `by`, `bw`, `bh`), la etiqueta (`tx`, `ty`,
-- `ancho`, `alto`, `texto`, `fuente`) y la caja que ocupa todo (`caja`).
local function medidasRecolector(sx, sy, ficha, izquierda, pose)
    -- Solo el banderín (el dueño, 2026-09-30: sin la bolsa ni la etiqueta de
    -- «carga / capacidad», que molestaban).
    local e = Estandartes.tamBanderin
    local m = { lado = izquierda and 1 or -1 }
    local largoPano = 13 * e
    local x0 = (izquierda and sx - largoPano or sx - 3 * e) - 2 * e
    local y0 = sy - 27 * e
    if pose == 'combate' then
        y0 = math.min(y0, sy - 40 * e)
    end
    m.caja = { x = x0, y = y0, w = largoPano + 6 * e, h = sy + 2 * e - y0 }
    return m
end

--- Caja (px de pantalla) que ocuparía la ficha de un recolector con el pie
-- en (sx, sy), sin dibujarla.
function Estandartes.cajaRecolector(sx, sy, ficha, izquierda, pose)
    return medidasRecolector(sx, sy, ficha, izquierda, pose).caja
end

--- Banderín de un recolector con el pie en (sx, sy). En una batalla, dos
-- espadas sobre el paño. Devuelve la caja que ocupa (px de pantalla).
function Estandartes.dibujarRecolector(sx, sy, ficha, izquierda, pose, fase)
    local g = love.graphics
    local e = Estandartes.tamBanderin
    local color = ficha.color or { 1, 1, 1 }
    Estandartes.dibujarBanderin(sx, sy, color, izquierda, fase)
    local m = medidasRecolector(sx, sy, ficha, izquierda, pose)
    if pose == 'combate' then
        local ex, ey, er = sx - m.lado * 6 * e, sy - 34 * e, 5 * e
        Tema.color('rojoTexto')
        g.setLineWidth(math.max(1.5, 2 * e))
        g.line(ex - er, ey + er, ex + er, ey - er)
        g.line(ex - er, ey - er, ex + er, ey + er)
        g.setLineWidth(1)
    end
    return m.caja
end

--- Texto de la etiqueta: «Gral. Mira Oriel · 1 240». Un ejército ajeno sin
-- informe (`poderOculto`, interfaz/inteligencia.lua) lleva «?»; con informe
-- de otro día, sus días detrás: «1 240 (3 d)».
function Estandartes.textoEtiqueta(ficha)
    local lider = ficha.lider and ficha.lider.etiqueta or ficha.nombreNacion or '?'
    if ficha.poderOculto then
        return lider .. ' · ?'
    end
    local poder = Tema.numero(ficha.poderRedondeado or 0)
    if ficha.informeDia and ficha.diasInforme and ficha.diasInforme > 0 then
        poder = string.format('%s (%d d)', poder, ficha.diasInforme)
    end
    return lider .. ' · ' .. poder
end

--- Caja (px de pantalla) que ocuparían el estandarte y la etiqueta de un
-- ejército con el pie en (sx, sy), sin dibujarlos (como `dibujarEstandarte`
-- y `dibujarEtiqueta` sin `pegada`).
function Estandartes.cajaEjercito(sx, sy, ficha, izquierda)
    local datos = Indice.estandarte
    local hoja, s = Estandartes.escala()
    local ax, ay = datos.ancla.x * hoja, datos.ancla.y * hoja
    local ancho, alto = datos.ancho * hoja * s, datos.alto * hoja * s
    local x0 = izquierda and sx - (ancho - ax * s) or sx - ax * s
    local y0 = sy - ay * s
    local fuente = Tema.fuente('sansNegrita', 13)
    local anchoEtiqueta = fuente:getWidth(Estandartes.textoEtiqueta(ficha)) + Tema.px(6) * 2
    local altoEtiqueta = fuente:getHeight() + Tema.px(2)
    local dx = (datos.etiqueta.x - datos.ancla.x) * hoja * s
    if izquierda then
        dx = -dx
    end
    local ex = math.floor(sx + dx - anchoEtiqueta / 2)
    local ey = math.floor(sy + (datos.etiqueta.y - datos.ancla.y) * hoja * s)
    local x1 = math.max(x0 + ancho, ex + anchoEtiqueta)
    local y1 = math.max(y0 + alto, ey + altoEtiqueta)
    x0, y0 = math.min(x0, ex), math.min(y0, ey)
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

--- Etiqueta bajo el estandarte, centrada en el asta. Devuelve su caja.
-- `pegada` (opcional) la coloca junto a la x `pegada.x` en vez de centrarla:
-- con `pegada.lado` -1 termina en esa x y con 1 empieza en ella (las dos
-- etiquetas de un choque, una a cada lado del punto de encuentro).
function Estandartes.dibujarEtiqueta(sx, sy, ficha, izquierda, pegada)
    local g = love.graphics
    local datos = Indice.estandarte
    local hoja, s = Estandartes.escala()
    local fuente = Tema.fuente('sansNegrita', 13)
    local texto = Estandartes.textoEtiqueta(ficha)
    local relleno = Tema.px(6)
    local ancho = fuente:getWidth(texto) + relleno * 2
    local alto = fuente:getHeight() + Tema.px(2)
    local dx = (datos.etiqueta.x - datos.ancla.x) * hoja * s
    if izquierda then
        dx = -dx
    end
    local x = math.floor(sx + dx - ancho / 2)
    if pegada then
        x = math.floor(pegada.lado < 0 and pegada.x - ancho or pegada.x)
    end
    local y = math.floor(sy + (datos.etiqueta.y - datos.ancla.y) * hoja * s)
    Tema.color('olivaNegro', 0.85)
    g.rectangle('fill', x, y, ancho, alto, 2, 2)
    local c = ficha.color or { 1, 1, 1 }
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle('fill', x, y, Tema.px(3), alto)
    g.setFont(fuente)
    Tema.color('textoHud')
    g.print(texto, x + relleno, y + Tema.px(1))
    return { x = x, y = y, w = ancho, h = alto }
end

return Estandartes

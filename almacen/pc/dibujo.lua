-- Lo que comparten las pantallas de la sala de control y los programas de
-- los ordenadores: colores de los recursos, números con puntos de miles, el
-- símbolo del polvorín y las letras.

local Dibujo = {}

Dibujo.verde = { 0.24, 0.9, 0.42 }
Dibujo.colorEstado = {
    holgado = { 0.3, 0.85, 0.4 },
    justo = { 0.95, 0.8, 0.25 },
    escasez = { 1.0, 0.55, 0.15 },
    crisis = { 1.0, 0.27, 0.2 },
}
Dibujo.textoEstado = { holgado = 'BIEN', justo = 'JUSTO', escasez = 'ESCASEZ', crisis = 'CRISIS' }
Dibujo.colorRecurso = {
    metal = { 0.73, 0.77, 0.8 },
    petroleo = { 0.4, 0.45, 1.0 },
    comida = { 0.91, 0.7, 0.23 },
    dinero = { 0.35, 0.77, 0.42 },
}

local LETRA_TITULO = 'assets/fuentes/BarlowCondensed-SemiBold.ttf'
local LETRA_DATO = 'assets/fuentes/JetBrainsMono-SemiBold.ttf'
-- Las letras por nombre: 'titulo', 'dato' y las del texto de las páginas
-- del navegador ('pagina' y 'paginaNegrita').
local ARCHIVOS_LETRA = {
    titulo = LETRA_TITULO,
    dato = LETRA_DATO,
    pagina = 'assets/fuentes/BarlowSemiCondensed-Medium.ttf',
    paginaNegrita = 'assets/fuentes/BarlowSemiCondensed-SemiBold.ttf',
}
local letras = {}

-- Los ordenadores pintan en 1280 x 720 «lógicos» sobre un lienzo de más
-- píxeles (almacen/pc/ordenador.lua); las letras se rasterizan a esa misma
-- densidad para que se lean nítidas a pantalla completa.
Dibujo.densidad = 1.5

--- La letra `cual` ('titulo', 'dato', 'pagina' o 'paginaNegrita') a
-- `tamano` px (se crea una vez).
function Dibujo.letra(cual, tamano)
    local clave = cual .. tamano
    if not letras[clave] then
        letras[clave] = love.graphics.newFont(ARCHIVOS_LETRA[cual] or LETRA_DATO, tamano, 'normal', Dibujo.densidad)
    end
    return letras[clave]
end

--- Recorta lo que se pinte dentro de `f` al rectángulo (x, y, w, h) en las
-- coordenadas de ahora (con la ventana trasladada), sin salirse del recorte
-- que ya hubiera; al acabar deja el de antes.
function Dibujo.recortado(x, y, w, h, f)
    local g = love.graphics
    local ax, ay = g.transformPoint(x, y)
    local bx, by = g.transformPoint(x + w, y + h)
    g.push('all')
    g.intersectScissor(ax, ay, math.max(0, bx - ax), math.max(0, by - ay))
    f()
    g.pop()
end

--- 1234567 → '1.234.567'.
function Dibujo.miles(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local signo = ''
    if s:sub(1, 1) == '-' then
        signo, s = '-', s:sub(2)
    end
    return signo .. s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
end

function Dibujo.fondo(w, h, r, gr, b)
    local g = love.graphics
    g.setColor(r, gr, b, 1)
    g.rectangle('fill', 0, 0, w, h)
end

--- Símbolo de radiactividad (trébol) en (x, y) de radio r sobre amarillo.
function Dibujo.trebol(x, y, r)
    local g = love.graphics
    g.setColor(0.91, 0.77, 0.28)
    g.circle('fill', x, y, r * 1.18)
    g.setColor(0.05, 0.05, 0.05)
    for k = 0, 2 do
        local a = -math.pi / 2 + k * 2 * math.pi / 3 - math.pi / 6
        g.arc('fill', x, y, r, a, a + math.pi / 3)
    end
    g.setColor(0.91, 0.77, 0.28)
    g.circle('fill', x, y, r * 0.3)
    g.setColor(0.05, 0.05, 0.05)
    g.circle('fill', x, y, r * 0.18)
end

return Dibujo

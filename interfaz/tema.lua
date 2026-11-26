-- Tema de la interfaz «Acero» (diseno/interfaz-militar.md, §3): escala e,
-- fuentes Barlow con caché por tamaño, colores (`interfaz/paleta.lua`) y las
-- piezas de dibujo que comparten todos los paneles (botones, medidores,
-- casillas, rayados, textos cortados y números con el formato F11).
--
-- Los colores son los de `interfaz/paleta.lua` (estilo Warpath original).

local utf8 = require('utf8')
local Paleta = require('interfaz.paleta')
local Indice = require('assets.ui.indice')

local Tema = {}

Tema.colores = {}
for nombre, color in pairs(Paleta.colores) do
    Tema.colores[nombre] = color
end

--- Con `modoClaro` los nombres de color del HUD oscuro se leen sobre gris
-- caqui claro (`Paleta.claro`): texto negro, acentos oscuros. Lo activan los
-- paneles de sitio y las noticias mientras se dibujan.
Tema.modoClaro = false

-- Color de cada estado de reserva (F4) para el relleno y para el texto.
Tema.rellenoEstado = {
    holgado = Tema.colores.verde,
    justo = Tema.colores.amarillo,
    escasez = Tema.colores.rojo,
    crisis = Tema.colores.rojo,
}
Tema.textoEstado = {
    holgado = 'verde',
    justo = 'amarillo',
    escasez = 'rojoTexto',
    crisis = 'rojoTexto',
}

-- Fuentes (Barlow, licencia OFL). Los tipos viejos (`sc`, `sans`…) siguen
-- valiendo: cada uno con el factor que lleva su tamaño de antes al del diseño
-- (§3.4); los estilos nuevos (`Acero.fuente`) piden el tamaño exacto.
local ARCHIVOS = {
    sc = Indice.tipografia.archivos.titulo,
    scNegra = Indice.tipografia.archivos.titulo,
    sans = Indice.tipografia.archivos.cuerpo,
    sansNegrita = Indice.tipografia.archivos.cuerpo_negrita,
    sansCursiva = Indice.tipografia.archivos.cuerpo,
    condensada = Indice.tipografia.archivos.titulo,
    condensadaMedia = Indice.tipografia.archivos.rotulo,
    semi = Indice.tipografia.archivos.cuerpo,
    semiNegrita = Indice.tipografia.archivos.cuerpo_negrita,
}
local FACTOR = { sc = 1.1, scNegra = 1, sans = 1.2, sansNegrita = 1.2, sansCursiva = 1.2 }

local cacheFuentes = {}
local escalaActual = 1

--- Escala de la interfaz (F1): e = FACTOR × max(0,8; alto / 1080), con tope
-- ancho / 1920 × 1,25 × FACTOR en pantallas más estrechas que 16:9. El dueño
-- pidió la interfaz a la mitad (2026-09-30): FACTOR 0,6, antes 1,25.
-- Se calcula una vez por cuadro con `Tema.actualizar`.
Tema.FACTOR = 0.6

--- Tamaño del texto sobre la escala de la interfaz: el texto muy pequeño se ve
-- borroso, así que puede ir más grande que los paneles.
Tema.TEXTO = 1.5

function Tema.actualizar()
    local ancho, alto = love.graphics.getDimensions()
    local e = math.max(0.8, alto / 1080)
    if ancho / alto < 16 / 9 then
        e = math.min(e, math.max(0.8, ancho / 1920 * 1.25))
    end
    e = e * Tema.FACTOR
    escalaActual = e
    return e
end

--- ¿La pantalla es «pequeña» (el lienzo de diseño mide menos de 1700 de
-- ancho)? Los paneles se estrechan un poco.
function Tema.compacta()
    return love.graphics.getWidth() / escalaActual < 1700
end

function Tema.escala()
    return escalaActual
end

--- Una medida de diseño (a 1920×1080) en píxeles de pantalla, entera.
function Tema.px(valor)
    return math.floor(valor * escalaActual + 0.5)
end

--- Fuente de un tipo y tamaño de diseño (F2): nunca baja de `minimo` (12 para
-- texto, 10 para etiquetas). Cada tamaño se carga una sola vez.
function Tema.fuente(tipo, base, minimo)
    return Tema.fuenteExacta(tipo, base * (FACTOR[tipo] or 1), minimo)
end

--- Como `fuente`, pero sin el factor de los tipos viejos: `base` es el tamaño
-- de diseño tal cual.
function Tema.fuenteExacta(tipo, base, minimo)
    local tam = math.max(minimo or 12, math.floor(base * escalaActual * Tema.TEXTO + 0.5))
    local clave = tipo .. ':' .. tam
    local fuente = cacheFuentes[clave]
    if not fuente then
        local archivo = ARCHIVOS[tipo]
        if archivo and love.filesystem.getInfo(archivo) then
            fuente = love.graphics.newFont(archivo, tam)
        else
            fuente = love.graphics.newFont(tam)
        end
        cacheFuentes[clave] = fuente
    end
    return fuente
end

--- Pone un color del tema (o uno dado como tabla) con su opacidad.
function Tema.color(nombre, alfa)
    local c = type(nombre) == 'table' and nombre or (Tema.modoClaro and Paleta.claro[nombre]) or Tema.colores[nombre]
    love.graphics.setColor(c[1], c[2], c[3], alfa or c[4] or 1)
end

--- Mezcla de dos colores: `t` = 0 da `a`, 1 da `b`.
function Tema.mezcla(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

-- Formato de números (F11): miles con espacio fino, coma decimal y signo
-- menos tipográfico, si la fuente los trae.
local ESPACIO_FINO = '\u{00A0}'
local MENOS = '\u{2212}'

local function separarMiles(entero)
    local texto = tostring(entero)
    local partes = {}
    while #texto > 3 do
        table.insert(partes, 1, texto:sub(-3))
        texto = texto:sub(1, -4)
    end
    table.insert(partes, 1, texto)
    return table.concat(partes, ESPACIO_FINO)
end

--- Texto en mayúsculas, con las vocales acentuadas y la ñ (`string.upper` no
-- las toca).
function Tema.mayusculas(texto)
    local mapa =
        { ['á'] = 'Á', ['é'] = 'É', ['í'] = 'Í', ['ó'] = 'Ó', ['ú'] = 'Ú', ['ñ'] = 'Ñ', ['ü'] = 'Ü' }
    return (texto:upper():gsub('[\195][\128-\191]', mapa))
end

--- Número entero con el formato del juego: «19 039», «123 k», «1,2 M».
function Tema.numero(valor)
    valor = math.floor((valor or 0) + 0.5)
    local signo = valor < 0 and MENOS or ''
    local absoluto = math.abs(valor)
    if absoluto >= 1000000 then
        return signo .. string.format('%.1f', absoluto / 1000000):gsub('%.', ',') .. ESPACIO_FINO .. 'M'
    end
    if absoluto >= 100000 then
        return signo .. math.floor(absoluto / 1000) .. ESPACIO_FINO .. 'k'
    end
    return signo .. separarMiles(absoluto)
end

--- Número con un decimal y signo siempre: «+18,3», «−21,9».
function Tema.decimal(valor)
    local signo = valor < 0 and MENOS or '+'
    return signo .. string.format('%.1f', math.abs(valor)):gsub('%.', ',')
end

--- Texto cortado con «…» si no cabe en `ancho` con la fuente dada.
function Tema.cortar(fuente, texto, ancho)
    if fuente:getWidth(texto) <= ancho then
        return texto
    end
    local puntos = '…'
    local largo = utf8.len(texto)
    while largo > 1 do
        largo = largo - 1
        local corte = texto:sub(1, utf8.offset(texto, largo + 1) - 1) .. puntos
        if fuente:getWidth(corte) <= ancho then
            return corte
        end
    end
    return puntos
end

--- Texto en versalitas con espaciado (etiquetas y títulos de sección). Devuelve
-- el ancho que ocupa.
function Tema.espaciado(texto, x, y, fuente, espacio)
    local g = love.graphics
    g.setFont(fuente)
    local cursor = x
    for _, codigo in utf8.codes(texto) do
        local letra = utf8.char(codigo)
        g.print(letra, math.floor(cursor + 0.5), y)
        cursor = cursor + fuente:getWidth(letra) + espacio
    end
    return cursor - x - espacio
end

function Tema.anchoEspaciado(texto, fuente, espacio)
    local ancho = 0
    for _, codigo in utf8.codes(texto) do
        ancho = ancho + fuente:getWidth(utf8.char(codigo)) + espacio
    end
    return ancho - espacio
end

-- Degradado vertical: una sola malla de cuatro vértices que se recolorea.
local mallaDegradado

--- Rectángulo con degradado de `arriba` a `abajo`.
function Tema.degradado(x, y, w, h, arriba, abajo, alfa)
    if not mallaDegradado then
        mallaDegradado = love.graphics.newMesh({
            { 0, 0, 0, 0 },
            { 1, 0, 1, 0 },
            { 1, 1, 1, 1 },
            { 0, 1, 0, 1 },
        }, 'fan', 'dynamic')
    end
    alfa = alfa or 1
    mallaDegradado:setVertexAttribute(1, 3, arriba[1], arriba[2], arriba[3], alfa)
    mallaDegradado:setVertexAttribute(2, 3, arriba[1], arriba[2], arriba[3], alfa)
    mallaDegradado:setVertexAttribute(3, 3, abajo[1], abajo[2], abajo[3], alfa)
    mallaDegradado:setVertexAttribute(4, 3, abajo[1], abajo[2], abajo[3], alfa)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mallaDegradado, x, y, 0, w, h)
end

--- Rayado diagonal de dos colores dentro de un rectángulo (crisis, recuperándose).
function Tema.rayado(x, y, w, h, fondo, raya, paso)
    local g = love.graphics
    Tema.color(fondo)
    g.rectangle('fill', x, y, w, h)
    local sx, sy, sw, sh = g.getScissor()
    g.intersectScissor(x, y, w, h)
    Tema.color(raya)
    g.setLineWidth(math.max(1, paso * 0.45))
    for d = -h, w, paso do
        g.line(x + d, y + h, x + d + h, y)
    end
    g.setLineWidth(1)
    if sx then
        g.setScissor(sx, sy, sw, sh)
    else
        g.setScissor()
    end
end

--- Borde de 1 px por dentro de un rectángulo.
function Tema.borde(x, y, w, h, nombre, alfa)
    Tema.color(nombre, alfa)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
end

--- ¿Está el punto dentro del rectángulo?
function Tema.dentro(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

--- Botón (C5): lo dibuja `Acero.boton` con las piezas del kit. `boton` =
-- { texto, tipo, activo, precio }; los tipos viejos valen: `principal` es
-- dorado, `secundario` gris y `peligro` rojo. Devuelve si el ratón está encima.
function Tema.boton(boton, x, y, w, h, compacto)
    return require('interfaz.acero').boton(boton, x, y, w, h, compacto)
end

--- Ancho que pide un botón con su texto y su precio.
function Tema.anchoBoton(boton, compacto)
    return require('interfaz.acero').anchoBoton(boton, compacto)
end

--- Icono de moneda (dinero), del kit.
function Tema.moneda(cx, cy, radio, vivo)
    local color = vivo and 'amarilloDinero' or 'textoDesact'
    require('interfaz.acero').icono('dinero', cx - radio, cy - radio, radio * 2, color)
end

--- Reloj (plazo): un círculo con dos manecillas.
function Tema.reloj(cx, cy, radio, nombre)
    local g = love.graphics
    Tema.color(nombre or 'amarillo')
    g.setLineWidth(math.max(1, radio * 0.22))
    g.circle('line', cx, cy, radio)
    g.line(cx, cy, cx, cy - radio * 0.6)
    g.line(cx, cy, cx + radio * 0.5, cy)
    g.setLineWidth(1)
end

--- Icono de un recurso (metal, petróleo, comida, dinero), del kit, en `lado` px.
function Tema.iconoRecurso(tipo, x, y, lado)
    require('interfaz.acero').iconoColor(tipo == 'oro' and 'dinero' or tipo, x, y, lado)
end

--- Título de sección (RESERVAS, DEFENSAS): estilo `subtitulo` en dorado con
-- una raya fina hasta el borde. Devuelve el alto que ocupa.
function Tema.tituloSeccion(texto, x, y, w)
    local fuente = Tema.fuenteExacta('condensada', 17, 12)
    Tema.color('amarilloDinero')
    local ancho = Tema.espaciado(texto, x, y, fuente, fuente:getHeight() * 0.06)
    Tema.color('lineaOliva')
    local rayaY = math.floor(y + fuente:getHeight() / 2) + 0.5
    love.graphics.line(x + ancho + Tema.px(8), rayaY, x + w, rayaY)
    return fuente:getHeight()
end

--- Estado de una reserva escrito (F4): nada si está holgada.
function Tema.textoReserva(r)
    if r.estado == 'justo' then
        return string.format('JUSTO · %d DÍAS', r.dias)
    end
    if r.estado == 'escasez' then
        return string.format('ESCASEZ · %d DÍAS', r.dias)
    end
    if r.estado == 'crisis' then
        return 'CRISIS · VACÍO'
    end
    return nil
end

--- Medidor de reserva (C4): icono · nombre · barra · valor; debajo, el estado
-- si no está holgada. Devuelve el alto que ocupa.
function Tema.alturaMedidor(r)
    local alto = Tema.px(30)
    if Tema.textoReserva(r) then
        alto = alto + Tema.fuente('sans', 13, 10):getHeight() - Tema.px(2)
    end
    return alto
end

function Tema.medidor(r, nombre, x, y, w)
    local g = love.graphics
    local lado = Tema.px(26)
    local filaAlto = Tema.px(30)
    Tema.iconoRecurso(r.tipo, x, y + (filaAlto - lado) / 2, lado)
    local texto = Tema.fuente('sans', 15)
    g.setFont(texto)
    Tema.color('textoHud')
    local textoY = math.floor(y + (filaAlto - texto:getHeight()) / 2)
    g.print(nombre, x + lado + Tema.px(8), textoY)
    local anchoValor = Tema.px(56)
    local barraX = x + lado + Tema.px(8) + Tema.px(80)
    local barraW = w - (barraX - x) - anchoValor - Tema.px(8)
    local barraH = Tema.px(12)
    local barraY = math.floor(y + (filaAlto - barraH) / 2)
    if r.estado == 'crisis' then
        Tema.rayado(barraX, barraY, barraW, barraH, 'rojoOscuro', 'rojo', Tema.px(6))
        Tema.borde(barraX, barraY, barraW, barraH, 'rojoTexto')
    else
        local relleno = math.min(1, (r.cantidad or 0) / math.max(1, r.tope or 1))
        local tipo = ({ holgado = 'energia', justo = 'recurso', escasez = 'peligro' })[r.estado] or 'energia'
        require('interfaz.acero').barra(barraX, barraY, barraW, barraH, relleno, tipo)
    end
    local negrita = Tema.fuente('sansNegrita', 15)
    g.setFont(negrita)
    Tema.color('textoHud')
    local valor = Tema.numero(r.estado == 'crisis' and 0 or r.cantidad)
    g.print(valor, x + w - negrita:getWidth(valor), math.floor(y + (filaAlto - negrita:getHeight()) / 2))
    local estado = Tema.textoReserva(r)
    if estado then
        local etiqueta = Tema.fuente('sans', 13, 10)
        g.setFont(etiqueta)
        Tema.color(Tema.textoEstado[r.estado])
        g.print(estado, barraX, y + filaAlto - Tema.px(4))
    end
    return Tema.dentro(love.mouse.getX(), love.mouse.getY(), x, y, w, Tema.alturaMedidor(r))
end

--- Casillas de defensas (C7): una por plaza del tope. `partes` = { listas,
-- recuperando, fuera }. Devuelve el alto que ocupa.
function Tema.casillas(partes, plazas, x, y, w)
    local g = love.graphics
    local hueco = Tema.px(3)
    local porFila = math.min(plazas, 15)
    local lado = math.min(Tema.px(18), math.floor((w - hueco * (porFila - 1)) / porFila))
    local filas = math.ceil(plazas / porFila)
    local k = 0
    local function casilla(tipo)
        if k >= plazas then
            return
        end
        local fila = math.floor(k / porFila)
        local columna = k % porFila
        local cx = x + columna * (lado + hueco)
        local cy = y + fila * (lado + hueco)
        if tipo == 'lista' then
            Tema.color('verde')
            g.rectangle('fill', cx, cy, lado, lado)
            Tema.borde(cx, cy, lado, lado, 'verdeOscuro')
        elseif tipo == 'recuperando' then
            Tema.rayado(cx, cy, lado, lado, 'olivaNegro', 'amarillo', Tema.px(5))
            Tema.borde(cx, cy, lado, lado, 'amarillo')
        elseif tipo == 'fuera' then
            Tema.color('olivaNegro')
            g.rectangle('fill', cx, cy, lado, lado)
            Tema.color('caquiPestana')
            for rx = cx + 2, cx + lado - 2, math.max(3, Tema.px(4)) do
                g.rectangle('fill', rx, cy + 2, 1, lado - 4)
            end
            Tema.borde(cx, cy, lado, lado, 'caquiPestana')
        else
            Tema.color('olivaNegro')
            g.rectangle('fill', cx, cy, lado, lado)
            Tema.borde(cx, cy, lado, lado, 'lineaOliva')
        end
        k = k + 1
    end
    for _ = 1, partes.listas or 0 do
        casilla('lista')
    end
    for _ = 1, partes.recuperando or 0 do
        casilla('recuperando')
    end
    for _ = 1, partes.fuera or 0 do
        casilla('fuera')
    end
    while k < plazas do
        casilla('vacia')
    end
    return filas * lado + (filas - 1) * hueco
end

--- Caja de ayuda al pasar el ratón (`Acero.tooltip`), pegada al puntero y
-- metida en la pantalla.
function Tema.ayuda(texto, mx, my, anchoMax)
    require('interfaz.acero').tooltip(texto, mx, my, anchoMax)
end

-- Texto nítido: LÖVE dibuja borroso el texto que cae entre dos píxeles, y la
-- interfaz centra muchas líneas con divisiones (y + (h - alto) / 2). Se
-- redondea la posición de todo `print`/`printf` al píxel entero.
do
    local print0, printf0 = love.graphics.print, love.graphics.printf
    local floor = math.floor
    function love.graphics.print(texto, x, y, ...)
        if type(x) == 'number' and type(y) == 'number' then
            return print0(texto, floor(x + 0.5), floor(y + 0.5), ...)
        end
        return print0(texto, x, y, ...)
    end
    function love.graphics.printf(texto, x, y, ...)
        if type(x) == 'number' and type(y) == 'number' then
            return printf0(texto, floor(x + 0.5), floor(y + 0.5), ...)
        end
        return printf0(texto, x, y, ...)
    end
end

return Tema

-- Programa «Editor de texto»: abre los archivos de texto. Los de la carpeta
-- personal se pueden escribir (el cursor va donde se hace clic; flechas,
-- Inicio, Fin, Intro, Retroceso y Supr como en cualquier editor; se guarda
-- solo, en el propio archivo). Los de la red los escribe la partida: se ven
-- en vivo y no se pueden cambiar.

local Dibujo = require('almacen.pc.dibujo')
local Archivos = require('almacen.pc.archivos')

local Texto = {}

Texto.titulo = 'Editor de texto'
Texto.orden = 4
Texto.ancho, Texto.alto = 760, 500

local ALTO_BARRA = 30
local MARGEN = 56

function Texto.nuevo(ordenador, opciones)
    return { archivo = opciones and opciones.archivo, fila = 1, columna = 0, desde = 0 }
end

function Texto.tituloDe(estado)
    if estado.archivo then
        return estado.archivo:match('[^/]+$') .. ' — Editor de texto'
    end
    return 'Editor de texto'
end

-- Las líneas del archivo (la tabla misma si se puede escribir) y si se puede.
local function lineas(estado, ctx)
    if not estado.archivo then
        return { 'Abre un texto desde Archivos o con «editar <archivo>» en la terminal.' }, false
    end
    local fs = ctx.ordenador.archivos
    local nodo = fs:buscar(estado.archivo)
    if not nodo then
        return { 'El archivo ya no existe.' }, false
    end
    if nodo.leer then
        return nodo.leer(ctx) or {}, false
    end
    nodo.contenido = nodo.contenido or { '' }
    return nodo.contenido, Archivos.escribible(estado.archivo)
end

-- Columnas en bytes respetando UTF-8: el byte de inicio del carácter anterior
-- o siguiente.
local function anterior(s, c)
    c = c - 1
    while c > 0 and s:byte(c + 1) and s:byte(c + 1) >= 0x80 and s:byte(c + 1) < 0xC0 do
        c = c - 1
    end
    return math.max(0, c)
end

local function siguiente(s, c)
    c = c + 1
    while c < #s and s:byte(c + 1) >= 0x80 and s:byte(c + 1) < 0xC0 do
        c = c + 1
    end
    return math.min(#s, c)
end

local function ajustar(estado, l)
    estado.fila = math.max(1, math.min(#l, estado.fila))
    estado.columna = math.max(0, math.min(#l[estado.fila], estado.columna))
end

function Texto.dibujar(estado, ctx, w, h)
    local g = love.graphics
    local l, escribible = lineas(estado, ctx)
    ajustar(estado, l)
    Dibujo.fondo(w, h, 0.08, 0.085, 0.09)
    g.setColor(0.14, 0.15, 0.16)
    g.rectangle('fill', 0, 0, w, ALTO_BARRA)
    g.setFont(Dibujo.letra('dato', 14))
    g.setColor(0.6, 0.65, 0.66)
    g.print(estado.archivo or '', 12, 7)
    g.printf(escribible and 'se guarda solo' or 'solo lectura · en vivo', 0, 7, w - 12, 'right')
    local letra = Dibujo.letra('dato', 17)
    g.setFont(letra)
    local alto = letra:getHeight() + 4
    local caben = math.floor((h - ALTO_BARRA - 12) / alto)
    -- Que la fila del cursor se vea.
    if estado.fila <= estado.desde then
        estado.desde = estado.fila - 1
    elseif estado.fila > estado.desde + caben then
        estado.desde = estado.fila - caben
    end
    g.setColor(0.06, 0.065, 0.07)
    g.rectangle('fill', 0, ALTO_BARRA, MARGEN - 10, h - ALTO_BARRA)
    for k = 1, caben do
        local n = estado.desde + k
        local linea = l[n]
        if not linea then
            break
        end
        local y = ALTO_BARRA + 6 + (k - 1) * alto
        g.setColor(n == estado.fila and { 0.4, 0.9, 0.5 } or { 0.4, 0.44, 0.45 })
        g.printf(tostring(n), 0, y, MARGEN - 18, 'right')
        g.setColor(0.9, 0.92, 0.92)
        g.print(linea, MARGEN, y)
        if escribible and n == estado.fila and math.floor((ctx.reloj or 0) * 2) % 2 == 0 then
            local x = MARGEN + letra:getWidth(linea:sub(1, estado.columna))
            g.setColor(0.3, 0.85, 0.45)
            g.rectangle('fill', x, y + 1, 2, alto - 4)
        end
    end
    estado.alto, estado.caben = alto, caben
end

function Texto.raton(estado, ctx, accion, x, y, boton)
    if accion ~= 'pulsar' or not estado.alto then
        return
    end
    local l = lineas(estado, ctx)
    local fila = estado.desde + math.floor((y - ALTO_BARRA - 6) / estado.alto) + 1
    if not l[fila] then
        fila = #l
    end
    estado.fila = fila
    -- La columna más cercana al clic.
    local letra = Dibujo.letra('dato', 17)
    local linea = l[fila] or ''
    local mejor, c = 0, 0
    while c <= #linea do
        if letra:getWidth(linea:sub(1, c)) <= x - MARGEN then
            mejor = c
        end
        if c == #linea then
            break
        end
        c = siguiente(linea, c)
    end
    estado.columna = mejor
end

function Texto.texto(estado, ctx, t)
    local l, escribible = lineas(estado, ctx)
    if not escribible then
        return
    end
    ajustar(estado, l)
    local s = l[estado.fila]
    l[estado.fila] = s:sub(1, estado.columna) .. t .. s:sub(estado.columna + 1)
    estado.columna = estado.columna + #t
end

function Texto.tecla(estado, ctx, tecla)
    local l, escribible = lineas(estado, ctx)
    ajustar(estado, l)
    local s = l[estado.fila]
    if tecla == 'up' then
        estado.fila = estado.fila - 1
    elseif tecla == 'down' then
        estado.fila = estado.fila + 1
    elseif tecla == 'left' then
        if estado.columna > 0 then
            estado.columna = anterior(s, estado.columna)
        elseif estado.fila > 1 then
            estado.fila = estado.fila - 1
            estado.columna = #l[estado.fila]
        end
    elseif tecla == 'right' then
        if estado.columna < #s then
            estado.columna = siguiente(s, estado.columna)
        elseif estado.fila < #l then
            estado.fila, estado.columna = estado.fila + 1, 0
        end
    elseif tecla == 'home' then
        estado.columna = 0
    elseif tecla == 'end' then
        estado.columna = #s
    elseif not escribible then
        return
    elseif tecla == 'tab' then
        Texto.texto(estado, ctx, '    ')
    elseif tecla == 'return' or tecla == 'kpenter' then
        -- La línea nueva empieza con la sangría de la de arriba.
        local sangria = s:sub(1, estado.columna):match('^%s*')
        l[estado.fila] = s:sub(1, estado.columna)
        table.insert(l, estado.fila + 1, sangria .. s:sub(estado.columna + 1))
        estado.fila, estado.columna = estado.fila + 1, #sangria
    elseif tecla == 'backspace' then
        if estado.columna > 0 then
            local c = anterior(s, estado.columna)
            l[estado.fila] = s:sub(1, c) .. s:sub(estado.columna + 1)
            estado.columna = c
        elseif estado.fila > 1 then
            local arriba = l[estado.fila - 1]
            l[estado.fila - 1] = arriba .. s
            table.remove(l, estado.fila)
            estado.fila, estado.columna = estado.fila - 1, #arriba
        end
    elseif tecla == 'delete' then
        if estado.columna < #s then
            l[estado.fila] = s:sub(1, estado.columna) .. s:sub(siguiente(s, estado.columna) + 1)
        elseif estado.fila < #l then
            l[estado.fila] = s .. l[estado.fila + 1]
            table.remove(l, estado.fila + 1)
        end
    end
end

function Texto.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.86, 0.88, 0.9)
    g.rectangle('fill', x + s * 0.12, y, s * 0.76, s, s * 0.1)
    g.setColor(0.24, 0.55, 0.85)
    for k = 1, 4 do
        g.rectangle('fill', x + s * 0.24, y + s * 0.18 * k, s * (k == 4 and 0.3 or 0.52), s * 0.07)
    end
end

return Texto

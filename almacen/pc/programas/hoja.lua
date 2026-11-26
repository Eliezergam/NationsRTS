-- Programa «Hoja de cálculo»: abre los archivos `.hoja` (los de la red del
-- almacén y los de la carpeta del puesto). Sin archivo enseña la lista de
-- hojas para elegir una (clic para marcar, doble clic o Intro para abrir);
-- con una abierta, la cuadrícula con las columnas A, B, C... y las filas
-- numeradas, la celda elegida (clic o flechas) y su barra de fórmulas, como
-- cualquier hoja de cálculo. «Archivo» vuelve a la lista.

local Dibujo = require('almacen.pc.dibujo')

local Hoja = {}

Hoja.titulo = 'Hoja de cálculo'
Hoja.orden = 1

local ALTO_MENU = 30
local ALTO_BARRA = 34
local ALTO_FILA = 28
local ANCHO_NUMEROS = 46
local ANCHO_COLUMNA = 110
local ALTO_PESTANAS = 30
local MENUS = { 'Archivo', 'Editar', 'Ver', 'Insertar', 'Formato', 'Datos' }

--- `opciones.archivo`: la ruta de la hoja que abre (sin ella, la lista).
function Hoja.nuevo(ordenador, opciones)
    return {
        archivo = opciones and opciones.archivo,
        elegido = 1, -- en la lista de archivos
        celda = { 1, 1 }, -- columna, fila
    }
end

function Hoja.tituloDe(estado)
    if estado.archivo then
        return estado.archivo:match('[^/]+$') .. ' — Hoja de cálculo'
    end
    return 'Hoja de cálculo'
end

local function letraColumna(k)
    local s = ''
    while k > 0 do
        local r = (k - 1) % 26
        s = string.char(65 + r) .. s
        k = math.floor((k - 1) / 26)
    end
    return s
end

local function textoDe(c)
    if type(c) == 'table' then
        return tostring(c.texto or '')
    end
    return c ~= nil and tostring(c) or ''
end

local function menu(w)
    local g = love.graphics
    g.setColor(0.16, 0.17, 0.19)
    g.rectangle('fill', 0, 0, w, ALTO_MENU)
    local letra = Dibujo.letra('titulo', 20)
    g.setFont(letra)
    g.setColor(0.82, 0.85, 0.86)
    local x = 14
    for _, nombre in ipairs(MENUS) do
        g.print(nombre, x, 4)
        x = x + letra:getWidth(nombre) + 22
    end
end

-- Lista ---------------------------------------------------------------------------

local function rutas(ctx)
    return ctx.ordenador.archivos:listar('hoja')
end

local Y_LISTA = ALTO_MENU + 30 + 84
local ALTO_ITEM = 46

local function lista(estado, ctx, w, h)
    local g = love.graphics
    local todas = rutas(ctx)
    Dibujo.fondo(w, h, 0.11, 0.12, 0.13)
    menu(w)
    local x0, y0 = 40, ALTO_MENU + 30
    g.setColor(0.9, 0.92, 0.92)
    g.setFont(Dibujo.letra('titulo', 32))
    g.print('Abrir una hoja', x0, y0)
    g.setColor(0.6, 0.65, 0.66)
    g.setFont(Dibujo.letra('dato', 16))
    g.print('Doble clic o Intro para abrir · hojas de la red del almacén y de este puesto', x0, y0 + 42)
    local y = Y_LISTA
    g.setFont(Dibujo.letra('dato', 18))
    for k, ruta in ipairs(todas) do
        if k == estado.elegido then
            g.setColor(0.17, 0.42, 0.26)
            g.rectangle('fill', x0 - 10, y - 6, w - 2 * x0 + 20, 40, 4)
        end
        Hoja.icono(x0, y, 28)
        g.setColor(0.92, 0.94, 0.94)
        g.print(ruta:match('[^/]+$'), x0 + 40, y + 4)
        g.setColor(0.55, 0.6, 0.6)
        g.print(ruta:match('^(.*)/[^/]+$'), x0 + 300, y + 4)
        y = y + ALTO_ITEM
    end
    if #todas == 0 then
        g.setColor(0.55, 0.6, 0.6)
        g.print('No hay hojas.', x0, y)
    end
end

-- Cuadrícula -----------------------------------------------------------------------

-- Bordes de las columnas (px desde la izquierda) para el ancho `w`.
local function columnas(datos, w)
    local anchos = datos.anchos or {}
    local xs = { ANCHO_NUMEROS }
    local n = 0
    while xs[#xs] < w do
        n = n + 1
        xs[#xs + 1] = xs[#xs] + (anchos[n] or ANCHO_COLUMNA)
    end
    return xs, n
end

local function cuadricula(estado, ctx, w, h)
    local g = love.graphics
    local datos = ctx.ordenador.archivos:leer(estado.archivo, ctx) or { filas = {} }
    local filas = datos.filas or {}
    estado.tamano = { w, h }
    Dibujo.fondo(w, h, 0.09, 0.095, 0.1)
    menu(w)
    -- Barra de fórmulas: la referencia de la celda y lo que tiene.
    local yb = ALTO_MENU
    g.setColor(0.13, 0.14, 0.15)
    g.rectangle('fill', 0, yb, w, ALTO_BARRA)
    g.setColor(0.07, 0.075, 0.08)
    g.rectangle('fill', 8, yb + 5, 80, ALTO_BARRA - 10, 3)
    g.rectangle('fill', 130, yb + 5, w - 140, ALTO_BARRA - 10, 3)
    local c, f = estado.celda[1], estado.celda[2]
    g.setFont(Dibujo.letra('dato', 16))
    g.setColor(0.85, 0.88, 0.88)
    g.print(letraColumna(c) .. f, 16, yb + 8)
    g.setColor(0.6, 0.65, 0.66)
    g.print('fx', 100, yb + 8)
    g.setColor(0.92, 0.94, 0.94)
    g.print(textoDe(filas[f] and filas[f][c]), 140, yb + 8)
    -- Cabeceras.
    local y0 = ALTO_MENU + ALTO_BARRA
    local abajo = h - ALTO_PESTANAS
    local xs, ncol = columnas(datos, w)
    g.setColor(0.15, 0.16, 0.17)
    g.rectangle('fill', 0, y0, w, ALTO_FILA)
    g.rectangle('fill', 0, y0, ANCHO_NUMEROS, abajo - y0)
    g.setFont(Dibujo.letra('dato', 14))
    for k = 1, ncol do
        g.setColor(k == c and 0.4 or 0.62, k == c and 0.9 or 0.66, k == c and 0.5 or 0.67)
        g.printf(letraColumna(k), xs[k], y0 + 6, xs[k + 1] - xs[k], 'center')
    end
    local visibles = math.floor((abajo - y0 - ALTO_FILA) / ALTO_FILA)
    estado.desde = estado.desde or 0
    for k = 1, visibles do
        local fila = estado.desde + k
        local y = y0 + k * ALTO_FILA
        g.setColor(fila == f and 0.4 or 0.62, fila == f and 0.9 or 0.66, fila == f and 0.5 or 0.67)
        g.printf(tostring(fila), 0, y + 6, ANCHO_NUMEROS - 6, 'right')
    end
    -- Celdas.
    for k = 1, visibles do
        local y = y0 + k * ALTO_FILA
        local fila = filas[estado.desde + k] or {}
        for j = 1, ncol do
            local v = fila[j]
            if v ~= nil then
                local negrita = type(v) == 'table' and v.negrita
                local color = type(v) == 'table' and v.color or { 0.9, 0.92, 0.92 }
                local alinear = type(v) == 'number' and 'right' or 'left'
                -- El texto se extiende sobre las celdas vacías de su derecha,
                -- como en cualquier hoja de cálculo (los números no).
                local fin = j + 1
                if alinear == 'left' then
                    while fin <= ncol and fila[fin] == nil do
                        fin = fin + 1
                    end
                end
                local ancho = xs[math.min(fin, #xs)] - xs[j]
                Dibujo.recortado(xs[j], y, ancho, ALTO_FILA, function()
                    g.setColor(color)
                    g.setFont(negrita and Dibujo.letra('titulo', 19) or Dibujo.letra('dato', 15))
                    g.printf(textoDe(v), xs[j] + 6, y + 5, alinear == 'left' and 2000 or xs[j + 1] - xs[j] - 12, alinear)
                end)
            end
        end
    end
    -- Rejilla.
    g.setColor(0.2, 0.21, 0.22)
    g.setLineWidth(1)
    for k = 1, #xs do
        g.line(xs[k] + 0.5, y0, xs[k] + 0.5, abajo)
    end
    for k = 0, visibles + 1 do
        local y = y0 + k * ALTO_FILA + 0.5
        g.line(0, y, w, y)
    end
    -- La celda elegida.
    local fv = f - estado.desde
    if c <= ncol and fv >= 1 and fv <= visibles then
        g.setColor(0.3, 0.85, 0.45)
        g.setLineWidth(2)
        g.rectangle('line', xs[c] + 1, y0 + fv * ALTO_FILA + 1, xs[c + 1] - xs[c] - 1, ALTO_FILA - 1)
        g.setLineWidth(1)
    end
    -- Pestaña de la hoja.
    g.setColor(0.12, 0.13, 0.14)
    g.rectangle('fill', 0, abajo, w, ALTO_PESTANAS)
    local nombre = estado.archivo:match('[^/]+$'):gsub('%.hoja$', '')
    g.setFont(Dibujo.letra('dato', 14))
    local ancho = Dibujo.letra('dato', 14):getWidth(nombre) + 28
    g.setColor(0.09, 0.095, 0.1)
    g.rectangle('fill', 12, abajo, ancho, ALTO_PESTANAS - 4)
    g.setColor(0.3, 0.85, 0.45)
    g.rectangle('fill', 12, abajo + ALTO_PESTANAS - 6, ancho, 2)
    g.setColor(0.9, 0.92, 0.92)
    g.print(nombre, 26, abajo + 6)
    estado.visibles, estado.columnas = visibles, ncol
    estado.xs = xs
end

local function abierta(estado, ctx)
    return estado.archivo and ctx.ordenador.archivos:buscar(estado.archivo)
end

function Hoja.dibujar(estado, ctx, w, h)
    if abierta(estado, ctx) then
        cuadricula(estado, ctx, w, h)
    else
        estado.archivo = nil
        lista(estado, ctx, w, h)
    end
end

-- Entrada ---------------------------------------------------------------------------

-- Mueve la celda elegida y desplaza para que se vea.
local function moverCelda(estado, dc, df)
    estado.celda[1] = math.max(1, estado.celda[1] + dc)
    estado.celda[2] = math.max(1, estado.celda[2] + df)
    local visibles = estado.visibles or 20
    estado.desde = estado.desde or 0
    if estado.celda[2] <= estado.desde then
        estado.desde = estado.celda[2] - 1
    elseif estado.celda[2] > estado.desde + visibles then
        estado.desde = estado.celda[2] - visibles
    end
end

function Hoja.raton(estado, ctx, accion, x, y, boton, doble)
    if accion ~= 'pulsar' then
        return
    end
    -- «Archivo» (el primer menú): a la lista para abrir otra.
    if y < ALTO_MENU and x < 80 then
        estado.archivo = nil
        return
    end
    if not abierta(estado, ctx) then
        local k = math.floor((y - Y_LISTA + 6) / ALTO_ITEM) + 1
        local todas = rutas(ctx)
        if y >= Y_LISTA - 6 and todas[k] then
            estado.elegido = k
            if doble then
                estado.archivo = todas[k]
                estado.celda, estado.desde = { 1, 1 }, 0
            end
        end
        return
    end
    -- En la cuadrícula: la celda bajo el ratón.
    local y0 = ALTO_MENU + ALTO_BARRA + ALTO_FILA
    if y >= y0 and x >= ANCHO_NUMEROS and estado.xs then
        local fila = (estado.desde or 0) + math.floor((y - y0) / ALTO_FILA) + 1
        for j = 1, #estado.xs - 1 do
            if x >= estado.xs[j] and x < estado.xs[j + 1] then
                estado.celda = { j, fila }
                return
            end
        end
    end
end

function Hoja.tecla(estado, ctx, tecla)
    if not abierta(estado, ctx) then
        local n = #rutas(ctx)
        if tecla == 'down' then
            estado.elegido = math.min(n, estado.elegido + 1)
        elseif tecla == 'up' then
            estado.elegido = math.max(1, estado.elegido - 1)
        elseif tecla == 'return' or tecla == 'kpenter' then
            estado.archivo = rutas(ctx)[estado.elegido]
            estado.celda, estado.desde = { 1, 1 }, 0
        end
        return
    end
    local pasos = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 }, tab = { 1, 0 }, ['return'] = { 0, 1 } }
    if pasos[tecla] then
        moverCelda(estado, pasos[tecla][1], pasos[tecla][2])
    elseif tecla == 'pagedown' then
        moverCelda(estado, 0, estado.visibles or 20)
    elseif tecla == 'pageup' then
        moverCelda(estado, 0, -(estado.visibles or 20))
    elseif tecla == 'home' then
        estado.celda, estado.desde = { 1, 1 }, 0
    end
end

--- Icono del programa (panel y escritorio), en un cuadro de s px.
function Hoja.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.2, 0.62, 0.34)
    g.rectangle('fill', x, y, s, s, s * 0.18)
    g.setColor(0.95, 0.97, 0.95)
    local m = s * 0.22
    for k = 0, 2 do
        g.rectangle('fill', x + m, y + m + k * (s - 2 * m) / 2.5, s - 2 * m, s * 0.06)
    end
    g.rectangle('fill', x + s * 0.45, y + m, s * 0.06, s - 2 * m)
end

return Hoja

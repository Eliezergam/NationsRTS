-- Programa «Archivos»: el explorador de carpetas (como Dolphin en KDE). Barra
-- con la ruta y los botones atrás y arriba, lugares a la izquierda (carpeta
-- personal y red del almacén) y la lista de lo que hay. Clic para marcar,
-- doble clic (o Intro) para entrar en una carpeta o abrir un archivo con su
-- programa; Retroceso sube una carpeta.

local Dibujo = require('almacen.pc.dibujo')
local Archivos = require('almacen.pc.archivos')

local Explorador = {}

Explorador.titulo = 'Archivos'
Explorador.orden = 3
Explorador.ancho, Explorador.alto = 820, 520

local ALTO_BARRA = 44
local ANCHO_LUGARES = 190
local ALTO_ITEM = 40
local LUGARES = {
    { 'Carpeta personal', '/home/operador', { 0.85, 0.66, 0.3 } },
    { 'Red del almacén', '/red/almacen', { 0.36, 0.62, 0.9 } },
    { 'Raíz', '/', { 0.55, 0.58, 0.6 } },
}

function Explorador.nuevo(ordenador, opciones)
    return { ruta = opciones and opciones.ruta or '/home/operador', elegido = nil, atras = {} }
end

function Explorador.tituloDe(estado)
    local nombre = estado.ruta == '/' and '/' or estado.ruta:match('[^/]+$')
    return nombre .. ' — Archivos'
end

local function entradas(estado, ctx)
    local fs = ctx.ordenador.archivos
    local nodo = fs:buscar(estado.ruta)
    local lista = {}
    for _, h in ipairs(nodo and nodo.hijos or {}) do
        lista[#lista + 1] = h
    end
    -- Las carpetas primero, luego por nombre.
    table.sort(lista, function(a, b)
        if (a.carpeta and 1 or 0) ~= (b.carpeta and 1 or 0) then
            return a.carpeta == true
        end
        return a.nombre < b.nombre
    end)
    return lista
end

local function icono(nodo, x, y, s)
    local g = love.graphics
    if nodo.carpeta then
        local azul = nodo.nombre == 'red' or nodo.nombre == 'almacen'
        require('almacen.pc.ordenador').iconoCarpeta(x, y, s, azul and { 0.36, 0.62, 0.9 } or { 0.85, 0.66, 0.3 })
    elseif nodo.tipo == 'hoja' then
        require('almacen.pc.programas.hoja').icono(x, y, s)
    else
        g.setColor(0.86, 0.88, 0.9)
        g.rectangle('fill', x + s * 0.15, y, s * 0.7, s, s * 0.08)
        g.setColor(0.45, 0.5, 0.52)
        for k = 1, 4 do
            g.rectangle('fill', x + s * 0.25, y + s * 0.18 * k, s * 0.5, s * 0.06)
        end
    end
end

local function ir(estado, ruta)
    if ruta ~= estado.ruta then
        estado.atras[#estado.atras + 1] = estado.ruta
        estado.ruta = ruta
        estado.elegido = nil
    end
end

local function abrir(estado, ctx, nodo)
    local ruta = Archivos.resolver(estado.ruta, nodo.nombre)
    if nodo.carpeta then
        ir(estado, ruta)
    else
        local programa = ctx.ordenador.archivos:programaPara(ruta)
        ctx.ordenador:abrir(programa, nil, nil, nil, nil, { archivo = ruta })
    end
end

function Explorador.dibujar(estado, ctx, w, h)
    local g = love.graphics
    if not ctx.ordenador.archivos:buscar(estado.ruta) then
        estado.ruta = '/home/operador'
    end
    Dibujo.fondo(w, h, 0.1, 0.105, 0.115)
    -- Barra: atrás, arriba y la ruta.
    g.setColor(0.14, 0.15, 0.16)
    g.rectangle('fill', 0, 0, w, ALTO_BARRA)
    g.setColor(#estado.atras > 0 and { 0.85, 0.88, 0.88 } or { 0.4, 0.43, 0.44 })
    g.setLineWidth(2)
    g.line(26, 14, 18, 22, 26, 30)
    g.setColor(estado.ruta ~= '/' and { 0.85, 0.88, 0.88 } or { 0.4, 0.43, 0.44 })
    g.line(48, 28, 56, 18, 64, 28)
    g.setLineWidth(1)
    g.setColor(0.07, 0.075, 0.08)
    g.rectangle('fill', 82, 8, w - 94, ALTO_BARRA - 16, 4)
    g.setColor(0.9, 0.92, 0.92)
    g.setFont(Dibujo.letra('dato', 16))
    g.print(estado.ruta, 94, 13)
    -- Lugares.
    g.setColor(0.085, 0.09, 0.1)
    g.rectangle('fill', 0, ALTO_BARRA, ANCHO_LUGARES, h - ALTO_BARRA)
    g.setColor(0.55, 0.6, 0.6)
    g.setFont(Dibujo.letra('dato', 13))
    g.print('LUGARES', 16, ALTO_BARRA + 12)
    g.setFont(Dibujo.letra('titulo', 19))
    for k, l in ipairs(LUGARES) do
        local y = ALTO_BARRA + 36 + (k - 1) * 38
        if estado.ruta == l[2] then
            g.setColor(0.17, 0.42, 0.26)
            g.rectangle('fill', 6, y - 4, ANCHO_LUGARES - 12, 34, 4)
        end
        require('almacen.pc.ordenador').iconoCarpeta(16, y + 2, 22, l[3])
        g.setColor(0.9, 0.92, 0.92)
        g.print(l[1], 48, y + 2)
    end
    -- Lo que hay en la carpeta.
    local lista = entradas(estado, ctx)
    local x0 = ANCHO_LUGARES + 16
    g.setFont(Dibujo.letra('dato', 17))
    for k, nodo in ipairs(lista) do
        local y = ALTO_BARRA + 12 + (k - 1) * ALTO_ITEM
        if y + ALTO_ITEM > h then
            break
        end
        if estado.elegido == k then
            g.setColor(0.17, 0.42, 0.26)
            g.rectangle('fill', x0 - 6, y - 4, w - x0 - 10, ALTO_ITEM - 2, 4)
        end
        icono(nodo, x0, y, 28)
        g.setColor(0.92, 0.94, 0.94)
        g.print(nodo.nombre, x0 + 42, y + 5)
        g.setColor(0.55, 0.6, 0.6)
        local tipo = nodo.carpeta and 'Carpeta' or (nodo.tipo == 'hoja' and 'Hoja de cálculo' or 'Texto')
        if nodo.leer then
            tipo = tipo .. ' · en vivo'
        end
        g.print(tipo, w - 260, y + 5)
    end
    if #lista == 0 then
        g.setColor(0.55, 0.6, 0.6)
        g.print('Carpeta vacía', x0, ALTO_BARRA + 16)
    end
end

function Explorador.raton(estado, ctx, accion, x, y, boton, doble)
    if accion ~= 'pulsar' then
        return
    end
    if y < ALTO_BARRA then
        if x < 36 and #estado.atras > 0 then
            estado.ruta = table.remove(estado.atras)
            estado.elegido = nil
        elseif x >= 36 and x < 76 and estado.ruta ~= '/' then
            ir(estado, Archivos.resolver(estado.ruta, '..'))
        end
        return
    end
    if x < ANCHO_LUGARES then
        local k = math.floor((y - ALTO_BARRA - 32) / 38) + 1
        if LUGARES[k] then
            ir(estado, LUGARES[k][2])
        end
        return
    end
    local k = math.floor((y - ALTO_BARRA - 8) / ALTO_ITEM) + 1
    local lista = entradas(estado, ctx)
    if lista[k] then
        estado.elegido = k
        if doble then
            abrir(estado, ctx, lista[k])
        end
    else
        estado.elegido = nil
    end
end

function Explorador.tecla(estado, ctx, tecla)
    local lista = entradas(estado, ctx)
    if tecla == 'down' then
        estado.elegido = math.min(#lista, (estado.elegido or 0) + 1)
    elseif tecla == 'up' then
        estado.elegido = math.max(1, (estado.elegido or 2) - 1)
    elseif (tecla == 'return' or tecla == 'kpenter') and estado.elegido and lista[estado.elegido] then
        abrir(estado, ctx, lista[estado.elegido])
    elseif tecla == 'backspace' and estado.ruta ~= '/' then
        ir(estado, Archivos.resolver(estado.ruta, '..'))
    end
end

function Explorador.icono(x, y, s)
    require('almacen.pc.ordenador').iconoCarpeta(x, y, s, { 0.85, 0.66, 0.3 })
end

return Explorador

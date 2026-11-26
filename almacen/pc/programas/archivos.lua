-- Programa «Archivos»: el explorador de carpetas, como el de un escritorio
-- de verdad (el dueño, 26-nov: «que se vean como un explorador de archivos de
-- verdad»).
--
--   * Barra de herramientas: atrás, adelante, arriba, la ruta por partes (se
--     pincha una para ir allí) y el cambio de vista (iconos o detalles).
--   * A la izquierda, los lugares: la carpeta personal y sus carpetas, la red
--     del almacén y el equipo («/»).
--   * En medio, lo que hay: iconos grandes con su nombre, o una tabla con
--     nombre, tamaño y tipo. Clic marca, doble clic (o Intro) abre, la rueda
--     desplaza.
--   * Botón derecho: menú con abrir, carpeta nueva, documento nuevo,
--     renombrar y borrar (solo en la carpeta personal; la red la escribe la
--     partida). F2 renombra y Supr borra.
--   * Abajo, la barra de estado: cuántas cosas hay o qué es lo marcado.

local Dibujo = require('almacen.pc.dibujo')
local Archivos = require('almacen.pc.archivos')
local Iconos = require('almacen.pc.iconos')
local utf8 = require('utf8')

local Explorador = {}

Explorador.titulo = 'Archivos'
Explorador.orden = 3
Explorador.ancho, Explorador.alto = 900, 560

local ALTO_BARRA = 50
local ALTO_ESTADO = 30
local ANCHO_LUGARES = 210
local ANCHO_CELDA, ALTO_CELDA = 118, 118
local ICONO_GRANDE = 60
local ALTO_FILA = 32
local ALTO_CABECERA = 30
local ANCHO_MENU, ALTO_ITEM_MENU = 230, 32

local C = {
    barra = { 0.165, 0.175, 0.19 },
    lateral = { 0.135, 0.145, 0.16 },
    contenido = { 0.105, 0.11, 0.12 },
    borde = { 0.07, 0.075, 0.08 },
    texto = { 0.92, 0.94, 0.95 },
    tenue = { 0.58, 0.62, 0.65 },
    apagado = { 0.36, 0.39, 0.41 },
    boton = { 0.22, 0.235, 0.25 },
    encima = { 1, 1, 1, 0.06 },
    marcado = { 0.24, 0.53, 0.84, 0.38 },
    marcadoBorde = { 0.36, 0.64, 0.95 },
    menu = { 0.19, 0.2, 0.215 },
}

-- Los lugares de la izquierda, por secciones: { título, ruta, emblema }.
local LUGARES = {
    { seccion = 'Lugares' },
    { 'Carpeta personal', '/home/operador', 'casa' },
    { 'Guiones', '/home/operador/guiones' },
    { 'Programas', '/home/operador/programas' },
    { seccion = 'Red' },
    { 'Red del almacén', '/red/almacen', 'red' },
    { seccion = 'Equipo' },
    { 'Sistema (/)', '/', 'disco' },
}

function Explorador.nuevo(ordenador, opciones)
    return {
        ruta = opciones and opciones.ruta or '/home/operador',
        elegido = nil, -- el nombre de lo marcado
        atras = {},
        adelante = {},
        vista = 'iconos',
        desplazamiento = 0,
    }
end

function Explorador.tituloDe(estado)
    local nombre = estado.ruta == '/' and 'Sistema' or estado.ruta:match('[^/]+$')
    if estado.ruta == '/home/operador' then
        nombre = 'Carpeta personal'
    elseif estado.ruta == '/red/almacen' then
        nombre = 'Red del almacén'
    end
    return nombre .. ' — Archivos'
end

local function dentro(z, x, y)
    return z and x >= z[1] and x < z[1] + z[3] and y >= z[2] and y < z[2] + z[4]
end

local function rutaDe(estado, nodo)
    return Archivos.resolver(estado.ruta, nodo.nombre)
end

local function entradas(estado, ctx)
    local nodo = ctx.ordenador.archivos:buscar(estado.ruta)
    local lista = {}
    for _, h in ipairs(nodo and nodo.hijos or {}) do
        lista[#lista + 1] = h
    end
    -- Las carpetas primero, luego por nombre.
    table.sort(lista, function(a, b)
        if (a.carpeta and 1 or 0) ~= (b.carpeta and 1 or 0) then
            return a.carpeta == true
        end
        return a.nombre:lower() < b.nombre:lower()
    end)
    return lista
end

local function indiceDe(lista, nombre)
    for k, n in ipairs(lista) do
        if n.nombre == nombre then
            return k
        end
    end
end

local function tipoDe(nodo)
    if nodo.carpeta then
        return 'Carpeta'
    elseif nodo.tipo == 'hoja' then
        return 'Hoja de cálculo'
    elseif nodo.nombre:match('%.lua$') then
        return 'Programa de Lua'
    end
    return 'Documento de texto'
end

local function bytes(n)
    if n < 1024 then
        return n .. (n == 1 and ' byte' or ' bytes')
    end
    return (string.format('%.1f KB', n / 1024):gsub('%.', ','))
end

local function tamanoDe(nodo)
    if nodo.carpeta then
        local n = #(nodo.hijos or {})
        if n == 0 then
            return 'Vacía'
        end
        return n .. (n == 1 and ' elemento' or ' elementos')
    elseif nodo.leer then
        return 'En vivo'
    end
    local total = 0
    local c = nodo.contenido
    if type(c) == 'table' and c.filas then
        for _, fila in ipairs(c.filas) do
            for _, celda in ipairs(fila) do
                total = total + #tostring(type(celda) == 'table' and celda.texto or celda) + 1
            end
        end
    elseif type(c) == 'table' then
        for _, l in ipairs(c) do
            total = total + #l + 1
        end
    end
    return bytes(total)
end

-- Navegación ---------------------------------------------------------------

local function ir(estado, ruta)
    if ruta ~= estado.ruta then
        estado.atras[#estado.atras + 1] = estado.ruta
        estado.adelante = {}
        estado.ruta = ruta
        estado.elegido = nil
        estado.desplazamiento = 0
        estado.renombrando = nil
    end
end

local function volver(estado)
    if #estado.atras > 0 then
        estado.adelante[#estado.adelante + 1] = estado.ruta
        estado.ruta = table.remove(estado.atras)
        estado.elegido = nil
        estado.desplazamiento = 0
        estado.renombrando = nil
    end
end

local function avanzar(estado)
    if #estado.adelante > 0 then
        estado.atras[#estado.atras + 1] = estado.ruta
        estado.ruta = table.remove(estado.adelante)
        estado.elegido = nil
        estado.desplazamiento = 0
        estado.renombrando = nil
    end
end

local function subir(estado)
    if estado.ruta ~= '/' then
        ir(estado, Archivos.resolver(estado.ruta, '..'))
    end
end

local function abrir(estado, ctx, nodo)
    local ruta = rutaDe(estado, nodo)
    if nodo.carpeta then
        ir(estado, ruta)
    else
        local programa = ctx.ordenador.archivos:programaPara(ruta)
        ctx.ordenador:abrir(programa, nil, nil, nil, nil, { archivo = ruta })
    end
end

-- Cambios (solo en la carpeta personal) ------------------------------------

local function nombreLibre(ctx, carpeta, base, extension)
    local fs = ctx.ordenador.archivos
    local nombre = base .. extension
    local n = 2
    while fs:buscar(Archivos.resolver(carpeta, nombre)) do
        nombre = base .. ' ' .. n .. extension
        n = n + 1
    end
    return nombre
end

local function crear(estado, ctx, carpeta)
    if not Archivos.escribible(estado.ruta) then
        return
    end
    local nombre = carpeta and nombreLibre(ctx, estado.ruta, 'Carpeta nueva', '') or nombreLibre(ctx, estado.ruta, 'Documento nuevo', '.txt')
    if ctx.ordenador.archivos:crear(Archivos.resolver(estado.ruta, nombre), carpeta) then
        estado.elegido = nombre
        estado.renombrando = { nombre = nombre, texto = nombre, todo = true }
    end
end

local function borrar(estado, ctx)
    if estado.elegido and Archivos.escribible(estado.ruta) then
        ctx.ordenador.archivos:borrar(Archivos.resolver(estado.ruta, estado.elegido))
        estado.elegido = nil
        estado.renombrando = nil
    end
end

local function empezarRenombrar(estado)
    if estado.elegido and Archivos.escribible(estado.ruta) then
        estado.renombrando = { nombre = estado.elegido, texto = estado.elegido, todo = true }
    end
end

local function acabarRenombrar(estado, ctx)
    local r = estado.renombrando
    estado.renombrando = nil
    if not r then
        return
    end
    local nuevo = r.texto:gsub('^%s+', ''):gsub('%s+$', '')
    if nuevo == '' or nuevo == r.nombre or nuevo:find('/', 1, true) then
        return
    end
    local fs = ctx.ordenador.archivos
    local padre = fs:buscar(estado.ruta)
    if fs:buscar(Archivos.resolver(estado.ruta, nuevo)) then
        return
    end
    for _, h in ipairs(padre and padre.hijos or {}) do
        if h.nombre == r.nombre then
            h.nombre = nuevo
            if not h.carpeta then
                h.tipo = nuevo:match('%.hoja$') and 'hoja' or h.tipo
            end
            estado.elegido = nuevo
        end
    end
end

-- Dibujo ---------------------------------------------------------------

local function botonBarra(z, activo, encima, dibujo)
    local g = love.graphics
    if activo and encima then
        g.setColor(C.boton)
        g.rectangle('fill', z[1], z[2], z[3], z[4], 6)
    end
    g.setColor(activo and C.texto or C.apagado)
    g.setLineWidth(2.5)
    g.setLineJoin('none')
    dibujo(z[1] + z[3] / 2, z[2] + z[4] / 2)
    g.setLineWidth(1)
end

local function iconoLugar(l, x, y, s)
    if l[3] == 'disco' then
        Iconos.disco(x, y, s)
    elseif l[2]:sub(1, 5) == '/red/' then
        Iconos.carpeta(x, y, s, Iconos.azul, l[3])
    else
        Iconos.carpeta(x, y, s, Iconos.amarillo, l[3])
    end
end

-- Corta `texto` a `lineas` líneas de `ancho` px, con «…» si no cabe.
local function cortar(letra, texto, ancho, lineas)
    local _, partes = letra:getWrap(texto, ancho)
    if #partes <= lineas then
        return texto
    end
    local s = table.concat(partes, '', 1, lineas)
    while #s > 0 and letra:getWidth(s .. '…') > ancho * lineas do
        s = s:sub(1, utf8.offset(s, -1) - 1)
    end
    return s .. '…'
end

local function dibujarBarra(estado, z, w)
    local g = love.graphics
    g.setColor(C.barra)
    g.rectangle('fill', 0, 0, w, ALTO_BARRA)
    g.setColor(C.borde)
    g.rectangle('fill', 0, ALTO_BARRA - 1, w, 1)
    local cur = estado._cursor or { -1, -1 }
    z.atras = { 8, 9, 32, 32 }
    z.adelante = { 44, 9, 32, 32 }
    z.arriba = { 80, 9, 32, 32 }
    botonBarra(z.atras, #estado.atras > 0, dentro(z.atras, cur[1], cur[2]), function(cx, cy)
        g.line(cx + 4, cy - 8, cx - 4, cy, cx + 4, cy + 8)
    end)
    botonBarra(z.adelante, #estado.adelante > 0, dentro(z.adelante, cur[1], cur[2]), function(cx, cy)
        g.line(cx - 4, cy - 8, cx + 4, cy, cx - 4, cy + 8)
    end)
    botonBarra(z.arriba, estado.ruta ~= '/', dentro(z.arriba, cur[1], cur[2]), function(cx, cy)
        g.line(cx - 8, cy + 3, cx, cy - 5, cx + 8, cy + 3)
    end)
    -- La ruta por partes.
    local x0, x1 = 124, w - 98
    g.setColor(C.borde)
    g.rectangle('fill', x0, 9, x1 - x0, 32, 6)
    local letra = Dibujo.letra('titulo', 19)
    g.setFont(letra)
    local partes = { { '/', 'Sistema' } }
    local acumulada = ''
    for parte in estado.ruta:gmatch('[^/]+') do
        acumulada = acumulada .. '/' .. parte
        partes[#partes + 1] = { acumulada, parte }
    end
    z.migas = {}
    -- Si no cabe, se quitan las primeras (como hace un explorador).
    local anchos, total = {}, 0
    for k, p in ipairs(partes) do
        anchos[k] = letra:getWidth(p[2]) + 18
        total = total + anchos[k] + 14
    end
    local primera = 1
    while total > x1 - x0 - 16 and primera < #partes do
        total = total - anchos[primera] - 14
        primera = primera + 1
    end
    local x = x0 + 4
    for k = primera, #partes do
        local p = partes[k]
        local zona = { x, 12, anchos[k], 26 }
        z.migas[#z.migas + 1] = { zona, p[1] }
        local ultima = k == #partes
        if ultima or dentro(zona, cur[1], cur[2]) then
            g.setColor(ultima and C.boton or C.encima)
            g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 4)
        end
        g.setColor(ultima and C.texto or C.tenue)
        g.print(p[2], x + 9, 12 + (26 - letra:getHeight()) / 2)
        x = x + anchos[k]
        if not ultima then
            g.setColor(C.apagado)
            g.setLineWidth(2)
            g.line(x + 4, 20, x + 9, 25, x + 4, 30)
            g.setLineWidth(1)
            x = x + 14
        end
    end
    -- Vista: iconos o detalles.
    z.vistaIconos = { w - 88, 9, 36, 32 }
    z.vistaDetalles = { w - 48, 9, 36, 32 }
    for _, v in ipairs({ { z.vistaIconos, 'iconos' }, { z.vistaDetalles, 'detalles' } }) do
        local zona, cual = v[1], v[2]
        local activa = estado.vista == cual
        if activa or dentro(zona, cur[1], cur[2]) then
            g.setColor(activa and C.marcado or C.boton)
            g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 6)
        end
        g.setColor(activa and C.texto or C.tenue)
        local cx, cy = zona[1] + zona[3] / 2, zona[2] + zona[4] / 2
        if cual == 'iconos' then
            for i = 0, 1 do
                for j = 0, 1 do
                    g.rectangle('fill', cx - 8 + i * 9, cy - 8 + j * 9, 7, 7, 1)
                end
            end
        else
            for j = 0, 2 do
                g.rectangle('fill', cx - 9, cy - 7 + j * 6, 4, 3)
                g.rectangle('fill', cx - 3, cy - 7 + j * 6, 12, 3)
            end
        end
    end
end

local function dibujarLugares(estado, z, h)
    local g = love.graphics
    g.setColor(C.lateral)
    g.rectangle('fill', 0, ALTO_BARRA, ANCHO_LUGARES, h - ALTO_BARRA - ALTO_ESTADO)
    g.setColor(C.borde)
    g.rectangle('fill', ANCHO_LUGARES - 1, ALTO_BARRA, 1, h - ALTO_BARRA - ALTO_ESTADO)
    local cur = estado._cursor or { -1, -1 }
    z.lugares = {}
    local y = ALTO_BARRA + 10
    for _, l in ipairs(LUGARES) do
        if l.seccion then
            g.setColor(C.tenue)
            g.setFont(Dibujo.letra('titulo', 16))
            g.print(l.seccion, 16, y + 6)
            y = y + 30
        else
            local zona = { 6, y, ANCHO_LUGARES - 12, 32 }
            z.lugares[#z.lugares + 1] = { zona, l[2] }
            if estado.ruta == l[2] then
                g.setColor(C.marcado)
                g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 5)
            elseif dentro(zona, cur[1], cur[2]) then
                g.setColor(C.encima)
                g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 5)
            end
            iconoLugar(l, 16, y + 5, 22)
            g.setColor(C.texto)
            g.setFont(Dibujo.letra('titulo', 19))
            g.print(l[1], 48, y + 4)
            y = y + 34
        end
    end
end

-- Dónde va cada elemento en la vista de iconos: { x, y, ancho, alto }.
local function celdas(estado, lista, area)
    local columnas = math.max(1, math.floor((area[3] - 16) / ANCHO_CELDA))
    estado._columnas = columnas
    local t = {}
    for k = 1, #lista do
        local c, f = (k - 1) % columnas, math.floor((k - 1) / columnas)
        t[k] = { area[1] + 12 + c * ANCHO_CELDA, area[2] + 10 + f * ALTO_CELDA - estado.desplazamiento, ANCHO_CELDA - 6, ALTO_CELDA - 6 }
    end
    return t, math.ceil(#lista / columnas) * ALTO_CELDA + 20
end

local function filas(estado, lista, area)
    local t = {}
    for k = 1, #lista do
        t[k] = { area[1], area[2] + ALTO_CABECERA + (k - 1) * ALTO_FILA - estado.desplazamiento, area[3], ALTO_FILA }
    end
    return t, ALTO_CABECERA + #lista * ALTO_FILA + 10
end

local function campoRenombrar(estado, x, y, ancho, letra, centrado)
    local g = love.graphics
    local texto = estado.renombrando.texto
    local tw = letra:getWidth(texto)
    local cx = centrado and x + (ancho - math.min(ancho, tw + 12)) / 2 or x
    local cw = math.min(ancho, math.max(centrado and 40 or ancho, tw + 12))
    g.setColor(0.05, 0.055, 0.06)
    g.rectangle('fill', cx, y - 2, cw, letra:getHeight() + 4, 3)
    g.setColor(C.marcadoBorde)
    g.rectangle('line', cx, y - 2, cw, letra:getHeight() + 4, 3)
    if estado.renombrando.todo then
        g.setColor(C.marcado)
        g.rectangle('fill', cx + 5, y, tw + 2, letra:getHeight())
    end
    g.setColor(C.texto)
    g.print(texto, cx + 6, y)
    if not estado.renombrando.todo and love.timer.getTime() % 1 < 0.55 then
        g.rectangle('fill', cx + 6 + tw + 1, y + 1, 2, letra:getHeight() - 2)
    end
end

local function dibujarContenido(estado, ctx, z, lista, area)
    local g = love.graphics
    g.setColor(C.contenido)
    g.rectangle('fill', area[1], area[2], area[3], area[4])
    local cur = estado._cursor or { -1, -1 }
    local zonas, alto
    if estado.vista == 'iconos' then
        zonas, alto = celdas(estado, lista, area)
    else
        zonas, alto = filas(estado, lista, area)
    end
    estado._altoContenido = alto
    z.items = zonas
    Dibujo.recortado(area[1], area[2], area[3], area[4], function()
        if estado.vista == 'iconos' then
            local letra = Dibujo.letra('titulo', 18)
            g.setFont(letra)
            for k, nodo in ipairs(lista) do
                local c = zonas[k]
                if c[2] + c[4] > area[2] and c[2] < area[2] + area[4] then
                    local marcado = estado.elegido == nodo.nombre
                    if marcado then
                        g.setColor(C.marcado)
                        g.rectangle('fill', c[1], c[2], c[3], c[4], 6)
                        g.setColor(C.marcadoBorde)
                        g.rectangle('line', c[1] + 0.5, c[2] + 0.5, c[3] - 1, c[4] - 1, 6)
                    elseif dentro(c, cur[1], cur[2]) then
                        g.setColor(C.encima)
                        g.rectangle('fill', c[1], c[2], c[3], c[4], 6)
                    end
                    Iconos.de(nodo, rutaDe(estado, nodo), c[1] + (c[3] - ICONO_GRANDE) / 2, c[2] + 8, ICONO_GRANDE)
                    local ty = c[2] + ICONO_GRANDE + 14
                    if estado.renombrando and estado.renombrando.nombre == nodo.nombre then
                        campoRenombrar(estado, c[1] + 2, ty, c[3] - 4, letra, true)
                    else
                        g.setColor(C.texto)
                        g.printf(cortar(letra, nodo.nombre, c[3] - 8, 2), c[1] + 4, ty, c[3] - 8, 'center')
                    end
                end
            end
        else
            -- Cabecera de la tabla.
            local columnas = { { 'Nombre', area[1] + 44 }, { 'Tamaño', area[1] + area[3] - 330 }, { 'Tipo', area[1] + area[3] - 190 } }
            local letra = Dibujo.letra('titulo', 18)
            g.setFont(letra)
            for k, nodo in ipairs(lista) do
                local f = zonas[k]
                if f[2] + f[4] > area[2] + ALTO_CABECERA and f[2] < area[2] + area[4] then
                    local marcado = estado.elegido == nodo.nombre
                    if marcado then
                        g.setColor(C.marcado)
                        g.rectangle('fill', f[1] + 4, f[2], f[3] - 8, f[4], 4)
                    elseif dentro(f, cur[1], cur[2]) then
                        g.setColor(C.encima)
                        g.rectangle('fill', f[1] + 4, f[2], f[3] - 8, f[4], 4)
                    elseif k % 2 == 0 then
                        g.setColor(1, 1, 1, 0.025)
                        g.rectangle('fill', f[1] + 4, f[2], f[3] - 8, f[4])
                    end
                    Iconos.de(nodo, rutaDe(estado, nodo), f[1] + 14, f[2] + 5, 22)
                    local ty = f[2] + (ALTO_FILA - letra:getHeight()) / 2
                    if estado.renombrando and estado.renombrando.nombre == nodo.nombre then
                        campoRenombrar(estado, columnas[1][2], ty, columnas[2][2] - columnas[1][2] - 20, letra, false)
                    else
                        g.setColor(C.texto)
                        g.print(cortar(letra, nodo.nombre, columnas[2][2] - columnas[1][2] - 20, 1), columnas[1][2], ty)
                    end
                    g.setColor(C.tenue)
                    g.print(tamanoDe(nodo), columnas[2][2], ty)
                    g.print(tipoDe(nodo), columnas[3][2], ty)
                end
            end
            g.setColor(C.barra)
            g.rectangle('fill', area[1], area[2], area[3], ALTO_CABECERA)
            g.setColor(C.borde)
            g.rectangle('fill', area[1], area[2] + ALTO_CABECERA - 1, area[3], 1)
            g.setColor(C.tenue)
            for k, col in ipairs(columnas) do
                g.print(col[1], col[2], area[2] + (ALTO_CABECERA - letra:getHeight()) / 2)
                if k > 1 then
                    g.setColor(C.borde)
                    g.rectangle('fill', col[2] - 12, area[2] + 6, 1, ALTO_CABECERA - 12)
                    g.setColor(C.tenue)
                end
            end
        end
        if #lista == 0 then
            g.setColor(C.tenue)
            g.setFont(Dibujo.letra('titulo', 22))
            g.printf('Esta carpeta está vacía', area[1], area[2] + area[4] / 2 - 14, area[3], 'center')
        end
    end)
    -- La barra de desplazamiento, si no cabe.
    local visible = area[4]
    if alto > visible then
        local largo = math.max(30, visible * visible / alto)
        local pos = (visible - largo) * estado.desplazamiento / (alto - visible)
        g.setColor(1, 1, 1, 0.18)
        g.rectangle('fill', area[1] + area[3] - 8, area[2] + pos + 2, 5, largo - 4, 2)
    end
end

local function dibujarEstado(estado, ctx, lista, w, h)
    local g = love.graphics
    local y = h - ALTO_ESTADO
    g.setColor(C.barra)
    g.rectangle('fill', 0, y, w, ALTO_ESTADO)
    g.setColor(C.borde)
    g.rectangle('fill', 0, y, w, 1)
    local letra = Dibujo.letra('titulo', 17)
    g.setFont(letra)
    local ty = y + (ALTO_ESTADO - letra:getHeight()) / 2
    local texto
    local k = estado.elegido and indiceDe(lista, estado.elegido)
    if k then
        local nodo = lista[k]
        texto = '«' .. nodo.nombre .. '»  ·  ' .. tipoDe(nodo) .. '  ·  ' .. tamanoDe(nodo)
        if nodo.leer then
            texto = '«' .. nodo.nombre .. '»  ·  ' .. tipoDe(nodo) .. '  ·  lo escribe la partida en vivo'
        end
    else
        local carpetas, archivos = 0, 0
        for _, n in ipairs(lista) do
            if n.carpeta then
                carpetas = carpetas + 1
            else
                archivos = archivos + 1
            end
        end
        texto = carpetas .. (carpetas == 1 and ' carpeta, ' or ' carpetas, ') .. archivos .. (archivos == 1 and ' archivo' or ' archivos')
    end
    g.setColor(C.tenue)
    g.print(texto, 14, ty)
    if not Archivos.escribible(estado.ruta) then
        g.setColor(0.85, 0.66, 0.3)
        g.printf('Solo lectura', 0, ty, w - 14, 'right')
    end
end

-- Las opciones del menú del botón derecho.
local function opcionesMenu(estado)
    local escribible = Archivos.escribible(estado.ruta)
    if estado.menu.nombre then
        return {
            { 'Abrir', 'abrir', true, 'Intro' },
            {},
            { 'Renombrar', 'renombrar', escribible, 'F2' },
            { 'Borrar', 'borrar', escribible, 'Supr' },
        }
    end
    return {
        { 'Carpeta nueva', 'carpeta', escribible },
        { 'Documento de texto nuevo', 'documento', escribible },
        {},
        { 'Ver como iconos', 'iconos', true },
        { 'Ver como detalles', 'detalles', true },
    }
end

local function dibujarMenu(estado, z, w, h)
    local g = love.graphics
    local m = estado.menu
    local opciones = opcionesMenu(estado)
    local alto = 8
    for _, o in ipairs(opciones) do
        alto = alto + (o[1] and ALTO_ITEM_MENU or 9)
    end
    local x = math.min(m.x, w - ANCHO_MENU - 4)
    local y = math.min(m.y, h - alto - 4)
    g.setColor(0, 0, 0, 0.35)
    g.rectangle('fill', x + 3, y + 4, ANCHO_MENU, alto, 6)
    g.setColor(C.menu)
    g.rectangle('fill', x, y, ANCHO_MENU, alto, 6)
    g.setColor(C.borde)
    g.rectangle('line', x + 0.5, y + 0.5, ANCHO_MENU - 1, alto - 1, 6)
    local cur = estado._cursor or { -1, -1 }
    local letra = Dibujo.letra('titulo', 18)
    g.setFont(letra)
    z.menu = { zona = { x, y, ANCHO_MENU, alto }, items = {} }
    local yy = y + 4
    for _, o in ipairs(opciones) do
        if o[1] then
            local zona = { x + 4, yy, ANCHO_MENU - 8, ALTO_ITEM_MENU }
            if o[3] and dentro(zona, cur[1], cur[2]) then
                g.setColor(C.marcado)
                g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 4)
            end
            g.setColor(o[3] and C.texto or C.apagado)
            g.print(o[1], zona[1] + 12, yy + (ALTO_ITEM_MENU - letra:getHeight()) / 2)
            if o[4] then
                g.setColor(o[3] and C.tenue or C.apagado)
                g.printf(o[4], zona[1], yy + (ALTO_ITEM_MENU - letra:getHeight()) / 2, zona[3] - 12, 'right')
            end
            z.menu.items[#z.menu.items + 1] = { zona, o[2], o[3] }
            yy = yy + ALTO_ITEM_MENU
        else
            g.setColor(C.borde)
            g.rectangle('fill', x + 10, yy + 4, ANCHO_MENU - 20, 1)
            yy = yy + 9
        end
    end
end

local function areaContenido(w, h)
    return { ANCHO_LUGARES, ALTO_BARRA, w - ANCHO_LUGARES, h - ALTO_BARRA - ALTO_ESTADO }
end

local function limitarDesplazamiento(estado, area)
    local maximo = math.max(0, (estado._altoContenido or 0) - area[4])
    estado.desplazamiento = math.max(0, math.min(maximo, estado.desplazamiento))
end

function Explorador.dibujar(estado, ctx, w, h)
    if not ctx.ordenador.archivos:buscar(estado.ruta) then
        estado.ruta = '/home/operador'
    end
    estado._w, estado._h = w, h
    local z = {}
    estado._z = z
    local lista = entradas(estado, ctx)
    if estado.elegido and not indiceDe(lista, estado.elegido) then
        estado.elegido = nil
    end
    local area = areaContenido(w, h)
    limitarDesplazamiento(estado, area)
    dibujarContenido(estado, ctx, z, lista, area)
    dibujarLugares(estado, z, h)
    dibujarBarra(estado, z, w)
    dibujarEstado(estado, ctx, lista, w, h)
    if estado.menu then
        dibujarMenu(estado, z, w, h)
    end
end

-- Entrada --------------------------------------------------------------

local function hacer(estado, ctx, accion)
    local lista = entradas(estado, ctx)
    local k = estado.elegido and indiceDe(lista, estado.elegido)
    if accion == 'abrir' and k then
        abrir(estado, ctx, lista[k])
    elseif accion == 'renombrar' then
        empezarRenombrar(estado)
    elseif accion == 'borrar' then
        borrar(estado, ctx)
    elseif accion == 'carpeta' then
        crear(estado, ctx, true)
    elseif accion == 'documento' then
        crear(estado, ctx, false)
    elseif accion == 'iconos' or accion == 'detalles' then
        estado.vista = accion
        estado.desplazamiento = 0
    end
end

-- El elemento bajo (x, y), o nil.
local function itemEn(estado, x, y)
    local z = estado._z or {}
    local area = areaContenido(estado._w or Explorador.ancho, estado._h or Explorador.alto)
    if not dentro(area, x, y) or (estado.vista == 'detalles' and y < area[2] + ALTO_CABECERA) then
        return nil
    end
    for k, c in ipairs(z.items or {}) do
        if dentro(c, x, y) then
            return k
        end
    end
end

function Explorador.raton(estado, ctx, accion, x, y, boton, doble)
    if accion == 'mover' then
        estado._cursor = { x, y }
        return
    end
    if accion ~= 'pulsar' then
        return
    end
    estado._cursor = { x, y }
    local z = estado._z or {}
    -- El menú abierto: una opción, o se cierra.
    if estado.menu then
        local menu = z.menu
        estado.menu = nil
        if menu and dentro(menu.zona, x, y) then
            for _, item in ipairs(menu.items) do
                if item[3] and dentro(item[1], x, y) then
                    hacer(estado, ctx, item[2])
                end
            end
            return
        end
    end
    if estado.renombrando then
        acabarRenombrar(estado, ctx)
    end
    if dentro(z.atras, x, y) then
        volver(estado)
        return
    elseif dentro(z.adelante, x, y) then
        avanzar(estado)
        return
    elseif dentro(z.arriba, x, y) then
        subir(estado)
        return
    elseif dentro(z.vistaIconos, x, y) then
        hacer(estado, ctx, 'iconos')
        return
    elseif dentro(z.vistaDetalles, x, y) then
        hacer(estado, ctx, 'detalles')
        return
    end
    for _, m in ipairs(z.migas or {}) do
        if dentro(m[1], x, y) then
            ir(estado, m[2])
            return
        end
    end
    for _, l in ipairs(z.lugares or {}) do
        if dentro(l[1], x, y) then
            ir(estado, l[2])
            return
        end
    end
    if y < ALTO_BARRA or x < ANCHO_LUGARES then
        return
    end
    local lista = entradas(estado, ctx)
    local k = itemEn(estado, x, y)
    estado.elegido = k and lista[k].nombre or nil
    if boton == 2 then
        estado.menu = { x = x, y = y, nombre = estado.elegido }
    elseif k and doble then
        abrir(estado, ctx, lista[k])
    end
end

function Explorador.rueda(estado, ctx, dy)
    estado.menu = nil
    estado.desplazamiento = estado.desplazamiento - dy * 60
    limitarDesplazamiento(estado, areaContenido(estado._w or Explorador.ancho, estado._h or Explorador.alto))
end

function Explorador.texto(estado, ctx, t)
    local r = estado.renombrando
    if r and not t:find('/', 1, true) then
        r.texto = (r.todo and '' or r.texto) .. t
        r.todo = false
    end
end

-- Que lo marcado se vea entero (al moverse con las flechas).
local function aLaVista(estado, k)
    local area = areaContenido(estado._w or Explorador.ancho, estado._h or Explorador.alto)
    local arriba, alto
    if estado.vista == 'iconos' then
        arriba = 10 + math.floor((k - 1) / (estado._columnas or 1)) * ALTO_CELDA
        alto = ALTO_CELDA
    else
        arriba = (k - 1) * ALTO_FILA
        alto = ALTO_FILA + ALTO_CABECERA
    end
    if arriba < estado.desplazamiento then
        estado.desplazamiento = arriba
    elseif arriba + alto > estado.desplazamiento + area[4] then
        estado.desplazamiento = arriba + alto - area[4]
    end
end

function Explorador.tecla(estado, ctx, tecla)
    if estado.renombrando then
        local r = estado.renombrando
        if tecla == 'return' or tecla == 'kpenter' then
            acabarRenombrar(estado, ctx)
        elseif tecla == 'backspace' and r.todo then
            r.texto, r.todo = '', false
        elseif tecla == 'backspace' then
            local corte = utf8.offset(r.texto, -1)
            if corte then
                r.texto = r.texto:sub(1, corte - 1)
            end
        end
        return
    end
    estado.menu = nil
    local lista = entradas(estado, ctx)
    local k = estado.elegido and indiceDe(lista, estado.elegido)
    local paso = estado.vista == 'iconos' and (estado._columnas or 1) or 1
    local nuevo
    if tecla == 'right' and estado.vista == 'iconos' then
        nuevo = math.min(#lista, (k or 0) + 1)
    elseif tecla == 'left' and estado.vista == 'iconos' then
        nuevo = math.max(1, (k or 2) - 1)
    elseif tecla == 'down' then
        nuevo = k and math.min(#lista, k + paso) or 1
    elseif tecla == 'up' then
        nuevo = k and math.max(1, k - paso) or 1
    elseif tecla == 'home' then
        nuevo = 1
    elseif tecla == 'end' then
        nuevo = #lista
    elseif (tecla == 'return' or tecla == 'kpenter') and k then
        abrir(estado, ctx, lista[k])
    elseif tecla == 'backspace' then
        subir(estado)
    elseif tecla == 'f2' then
        empezarRenombrar(estado)
    elseif tecla == 'delete' then
        borrar(estado, ctx)
    end
    if nuevo and lista[nuevo] then
        estado.elegido = lista[nuevo].nombre
        aLaVista(estado, nuevo)
    end
end

function Explorador.icono(x, y, s)
    Iconos.carpeta(x, y, s, Iconos.amarillo)
end

return Explorador

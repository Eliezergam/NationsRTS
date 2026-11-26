-- Programa «Robots»: ejecutar cosas en los robots del almacén desde la sala
-- de control (el dueño, 26-nov). A la izquierda los robots con lo que ejecuta
-- cada uno; a la derecha, el elegido: sus ejecutables (los del juego, de
-- /red/almacen/guiones, y los míos, de ~/guiones), botones Ejecutar y Parar
-- (doble clic en uno también lo ejecuta) y lo último que ha escrito.
-- Cada robot ejecuta uno solo a la vez: el nuevo sustituye al anterior.

local Dibujo = require('almacen.pc.dibujo')
local ApiRobots = require('almacen.pc.api_robots')

local Robots = {}

Robots.titulo = 'Robots'
Robots.orden = 5
Robots.ancho, Robots.alto = 940, 600

local ANCHO_LISTA = 300
local ALTO_ROBOT = 74
local MIOS = '/home/operador/guiones'
local DEL_JUEGO = '/red/almacen/guiones'
local ALTO_FILA = 30
local Y_LISTA = 170 -- donde empieza la lista de ejecutables
local VERDE = { 0.3, 0.78, 0.45 }
local AZUL = { 0.36, 0.62, 0.95 }
local AMBAR = { 0.9, 0.7, 0.25 }

function Robots.nuevo()
    return { elegido = 1, aviso = nil }
end

-- Los ejecutables del robot `r`: { { ruta, nombre, delJuego }, ... } con un
-- título antes de cada grupo ({ titulo = '...' }).
local function ejecutables(ctx, r)
    local lista = { { titulo = 'DEL JUEGO  ' .. DEL_JUEGO } }
    for _, e in ipairs(r:getEjecutables()) do
        lista[#lista + 1] = { ruta = DEL_JUEGO .. '/' .. e.archivo, nombre = e.archivo, delJuego = true, descripcion = e.descripcion }
    end
    lista[#lista + 1] = { titulo = 'MÍOS  ~/guiones' }
    local nodo = ctx.ordenador.archivos:buscar(MIOS)
    for _, h in ipairs(nodo and nodo.hijos or {}) do
        if not h.carpeta and h.nombre:match('%.lua$') then
            lista[#lista + 1] = { ruta = MIOS .. '/' .. h.nombre, nombre = h.nombre }
        end
    end
    return lista
end

-- Zonas de los botones (en px del área de la ventana), según el ancho.
local function botones(w)
    local x = ANCHO_LISTA + 24
    return {
        ejecutar = { x, 104, 140, 38 },
        parar = { x + 152, 104, 110, 38 },
    }
end

local function dentro(z, x, y)
    return x >= z[1] and x < z[1] + z[3] and y >= z[2] and y < z[2] + z[4]
end

local function boton(z, texto, color, activo)
    local g = love.graphics
    g.setColor(activo and color or { 0.22, 0.24, 0.25 })
    g.rectangle('fill', z[1], z[2], z[3], z[4], 5)
    g.setColor(activo and { 0.05, 0.06, 0.06 } or { 0.5, 0.53, 0.54 })
    g.setFont(Dibujo.letra('titulo', 19))
    g.printf(texto, z[1], z[2] + z[4] / 2 - 12, z[3], 'center')
end

local function queHace(r)
    if r:getModo() == 'parado' then
        return 'parado', AMBAR
    end
    return 'ejecuta ' .. tostring(r:getGuion()), VERDE
end

function Robots.dibujar(estado, ctx, w, h)
    local g = love.graphics
    Dibujo.fondo(w, h, 0.09, 0.095, 0.105)
    local lista = ApiRobots.robots()
    estado.elegido = math.max(1, math.min(#lista, estado.elegido or 1))
    -- Los robots.
    g.setColor(0.07, 0.075, 0.08)
    g.rectangle('fill', 0, 0, ANCHO_LISTA, h)
    g.setColor(0.55, 0.6, 0.6)
    g.setFont(Dibujo.letra('dato', 13))
    g.print('ROBOTS DEL ALMACÉN', 16, 12)
    for k, e in ipairs(lista) do
        local r = e.robot
        local y = 36 + (k - 1) * ALTO_ROBOT
        if k == estado.elegido then
            g.setColor(0.14, 0.2, 0.17)
            g.rectangle('fill', 6, y, ANCHO_LISTA - 12, ALTO_ROBOT - 6, 5)
        end
        local texto, color = queHace(r)
        g.setColor(color)
        g.circle('fill', 22, y + 18, 6)
        g.setColor(0.93, 0.95, 0.95)
        g.setFont(Dibujo.letra('titulo', 20))
        g.print(e.titulo, 36, y + 6)
        g.setColor(0.6, 0.64, 0.65)
        g.setFont(Dibujo.letra('dato', 13))
        Dibujo.recortado(36, y + 30, ANCHO_LISTA - 50, 36, function()
            g.print(e.nombre .. ' · ' .. texto, 36, y + 32)
            g.print(r.getTarea and r:getTarea() or '', 36, y + 49)
        end)
    end
    if #lista == 0 then
        g.setColor(0.55, 0.6, 0.6)
        g.print('No hay robots en el almacén.', 16, 40)
        return
    end
    -- El elegido.
    local e = lista[estado.elegido]
    local r = e.robot
    local x0 = ANCHO_LISTA + 24
    g.setColor(0.95, 0.96, 0.96)
    g.setFont(Dibujo.letra('titulo', 30))
    g.print(e.titulo, x0, 14)
    local texto, color = queHace(r)
    g.setFont(Dibujo.letra('dato', 15))
    g.setColor(color)
    g.print(texto, x0, 54)
    g.setColor(0.7, 0.74, 0.75)
    Dibujo.recortado(x0, 76, w - x0 - 16, 22, function()
        g.print(r.getTarea and r:getTarea() or '', x0, 78)
    end)
    -- Los ejecutables.
    local filas = ejecutables(ctx, r)
    local elegida
    for _, f in ipairs(filas) do
        if f.ruta and f.ruta == estado.ruta then
            elegida = f
        end
    end
    if not elegida then
        for _, f in ipairs(filas) do
            if f.ruta then
                elegida = f
                estado.ruta = f.ruta
                break
            end
        end
    end
    local b = botones(w)
    boton(b.ejecutar, 'Ejecutar', VERDE, elegida ~= nil)
    boton(b.parar, 'Parar', AMBAR, r:getModo() ~= 'parado')
    local limite = math.floor(h * 0.62)
    for k, f in ipairs(filas) do
        local y = Y_LISTA + (k - 1) * ALTO_FILA
        if y + ALTO_FILA > limite then
            break
        end
        if f.titulo then
            g.setColor(0.55, 0.6, 0.6)
            g.setFont(Dibujo.letra('dato', 13))
            g.print(f.titulo, x0, y + 10)
        else
            if f.ruta == estado.ruta then
                g.setColor(0.17, 0.3, 0.45)
                g.rectangle('fill', x0 - 6, y, w - x0 - 10, ALTO_FILA - 3, 4)
            end
            require('almacen.pc.programas.texto').icono(x0, y + 3, 21)
            local corriendo = r:getModo() ~= 'parado' and r:getGuion() == f.nombre
            g.setFont(Dibujo.letra('dato', 16))
            g.setColor(corriendo and VERDE or { 0.92, 0.94, 0.94 })
            g.print(f.nombre, x0 + 32, y + 4)
            g.setFont(Dibujo.letra('dato', 13))
            g.setColor(0.55, 0.6, 0.6)
            local nota = corriendo and 'en marcha' or (f.descripcion or '')
            Dibujo.recortado(x0 + 240, y, w - x0 - 260, ALTO_FILA, function()
                g.print(nota, x0 + 240, y + 7)
            end)
        end
    end
    -- Su salida.
    local ys = limite + 8
    g.setColor(0.04, 0.045, 0.05)
    g.rectangle('fill', x0 - 8, ys, w - x0 - 8, h - ys - 10, 4)
    local letra = Dibujo.letra('dato', 14)
    g.setFont(letra)
    local salida = r:getSalida()
    local alto = letra:getHeight() + 2
    local caben = math.floor((h - ys - 20) / alto)
    local y = ys + 6
    if estado.aviso then
        caben = caben - 1
    end
    for k = math.max(1, #salida - caben + 1), #salida do
        local linea = salida[k]
        g.setColor(linea:sub(1, 3) == '—' and { 0.55, 0.6, 0.6 } or { 0.85, 0.88, 0.87 })
        Dibujo.recortado(x0, y, w - x0 - 20, alto, function()
            g.print(linea, x0, y)
        end)
        y = y + alto
    end
    if estado.aviso then
        g.setColor(1, 0.45, 0.35)
        g.print(estado.aviso, x0, y)
    end
end

local function ejecutar(estado, ctx)
    local e = ApiRobots.robots()[estado.elegido]
    if not (e and estado.ruta) then
        return
    end
    local ok, error = ApiRobots.ejecutar(ctx.ordenador, e.nombre, estado.ruta)
    estado.aviso = not ok and ('no se pudo ejecutar: ' .. tostring(error)) or nil
    -- Su depuración en una ventanita: todo lo que va haciendo.
    if ok then
        require('almacen.pc.programas.depurador').abrirPara(ctx.ordenador, e.nombre)
    end
end

-- Mueve la elegida `paso` filas (saltando los títulos).
local function moverEleccion(estado, ctx, paso)
    local e = ApiRobots.robots()[estado.elegido]
    if not e then
        return
    end
    local rutas = {}
    local actual = 1
    for _, f in ipairs(ejecutables(ctx, e.robot)) do
        if f.ruta then
            rutas[#rutas + 1] = f.ruta
            if f.ruta == estado.ruta then
                actual = #rutas
            end
        end
    end
    estado.ruta = rutas[math.max(1, math.min(#rutas, actual + paso))]
end

function Robots.raton(estado, ctx, accion, x, y, boton, doble)
    if accion ~= 'pulsar' then
        return
    end
    local w = ctx.anchoVentana or Robots.ancho
    local lista = ApiRobots.robots()
    if x < ANCHO_LISTA then
        local k = math.floor((y - 36) / ALTO_ROBOT) + 1
        if lista[k] then
            estado.elegido = k
            estado.aviso = nil
        end
        return
    end
    local e = lista[estado.elegido]
    if not e then
        return
    end
    local b = botones(w)
    if dentro(b.ejecutar, x, y) then
        ejecutar(estado, ctx)
    elseif dentro(b.parar, x, y) then
        e.robot:setOrden('parar')
        estado.aviso = nil
    elseif y >= Y_LISTA then
        local f = ejecutables(ctx, e.robot)[math.floor((y - Y_LISTA) / ALTO_FILA) + 1]
        if f and f.ruta then
            estado.ruta = f.ruta
            if doble then
                ejecutar(estado, ctx)
            end
        end
    end
end

function Robots.tecla(estado, ctx, tecla)
    if tecla == 'up' then
        moverEleccion(estado, ctx, -1)
    elseif tecla == 'down' then
        moverEleccion(estado, ctx, 1)
    elseif tecla == 'return' or tecla == 'kpenter' then
        ejecutar(estado, ctx)
    end
end

function Robots.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.2, 0.36, 0.55)
    g.rectangle('fill', x, y, s, s, s * 0.18)
    -- Una cabeza de robot: caja, dos ojos y antena.
    g.setColor(0.88, 0.92, 0.95)
    g.rectangle('fill', x + s * 0.22, y + s * 0.34, s * 0.56, s * 0.42, s * 0.08)
    g.setColor(0.25, 0.85, 0.95)
    g.circle('fill', x + s * 0.38, y + s * 0.53, s * 0.07)
    g.circle('fill', x + s * 0.62, y + s * 0.53, s * 0.07)
    g.setColor(0.88, 0.92, 0.95)
    g.rectangle('fill', x + s * 0.48, y + s * 0.16, s * 0.04, s * 0.18)
    g.circle('fill', x + s * 0.5, y + s * 0.16, s * 0.06)
end

return Robots

-- Programa «Depurador» (el dueño, 26-nov): todo lo que escriben con print()
-- los guiones de los robots y los programas de los ordenadores, con la hora,
-- de quién es, el archivo y la línea; los errores en rojo, con por dónde
-- pasó. Las tablas salen desplegadas: print(self:getPieza('cabeza')) enseña
-- sus campos y sus métodos get... (almacen/pc/depuracion.lua).
--
-- Arriba se elige qué ver (todo, un robot o los ordenadores). Abajo, una
-- línea para evaluar Lua al momento: con un robot elegido, `self` es ese
-- robot (self:getPieza('cabeza'), self.x, self:setMirarA(0, 0, 1)); con
-- «Ordenadores», está la API `robots`. Flechas arriba/abajo: lo escrito
-- antes; RePág/AvPág: subir y bajar por la lista (Fin vuelve a lo último).

local Dibujo = require('almacen.pc.dibujo')
local Depuracion = require('almacen.pc.depuracion')
local ApiRobots = require('almacen.pc.api_robots')

local Depurador = {}

Depurador.titulo = 'Depurador'
Depurador.orden = 6
Depurador.ancho, Depurador.alto = 1040, 620

local ALTO_BARRA = 40
local ALTO_ENTRADA = 38
local COLORES = {
    print = { 0.88, 0.9, 0.9 },
    error = { 1, 0.42, 0.36 },
    orden = { 0.45, 0.8, 0.95 },
    resultado = { 0.5, 0.88, 0.55 },
}

function Depurador.nuevo(ordenador, opciones)
    return { filtro = opciones and opciones.robot or 'todo', robot = opciones and opciones.robot, escrito = '', historial = {}, subir = 0 }
end

--- El título: la de un robot dice qué ejecuta ahora.
function Depurador.tituloDe(estado)
    local r = estado.robot and ApiRobots.buscar(estado.robot)
    if r then
        local que = r:getModo() == 'parado' and 'parado' or tostring(r:getGuion())
        return 'Depuración · ' .. estado.robot .. ' (' .. que .. ')'
    end
    return 'Depurador'
end

-- Tamaño de la ventanita que se abre al ejecutar algo en un robot.
Depurador.anchoPequeno, Depurador.altoPequeno = 660, 380

--- Abre (o pone delante) la ventanita de depuración del robot `nombre`:
-- lo llaman Robots y la terminal al ejecutar algo en él.
function Depurador.abrirPara(ordenador, nombre)
    for _, v in ipairs(ordenador.datos.ventanas) do
        if v.programa == 'depurador' and v.estado.robot == nombre then
            ordenador:activar(v)
            v.estado.subir = 0
            return v
        end
    end
    local Ordenador = require('almacen.pc.ordenador')
    local w, h = Depurador.anchoPequeno, Depurador.altoPequeno
    -- Abajo a la derecha, una por robot un poco desplazada.
    local n = 0
    for _, v in ipairs(ordenador.datos.ventanas) do
        if v.programa == 'depurador' and v.estado.robot then
            n = n + 1
        end
    end
    local x = Ordenador.ancho - w - 16 - (n % 4) * 30
    local y = Ordenador.alto - Ordenador.altoPanel - h - 12 - (n % 4) * 30
    return ordenador:abrir('depurador', x, y, w, h, { robot = nombre })
end

-- Los filtros de arriba: { clave, texto }.
local function filtros()
    local lista = { { 'todo', 'Todo' } }
    for _, e in ipairs(ApiRobots.robots()) do
        lista[#lista + 1] = { e.nombre, e.titulo }
    end
    lista[#lista + 1] = { 'ordenadores', 'Ordenadores' }
    return lista
end

local function pasa(estado, l)
    if estado.filtro == 'todo' then
        return true
    elseif estado.filtro == 'ordenadores' then
        return l.puesto ~= nil
    end
    return l.robot == estado.filtro
end

local function deQuien(l)
    local quien = l.robot or l.puesto or ''
    local donde = l.archivo and (l.archivo .. (l.linea and (':' .. l.linea) or '')) or ''
    return quien .. (donde ~= '' and (' · ' .. donde) or '')
end

function Depurador.dibujar(estado, ctx, w, h)
    local g = love.graphics
    estado._zonas = { filtros = {} }
    Dibujo.fondo(w, h, 0.03, 0.035, 0.04)
    -- Filtros y Limpiar.
    g.setColor(0.1, 0.105, 0.115)
    g.rectangle('fill', 0, 0, w, ALTO_BARRA)
    local letra = Dibujo.letra('titulo', 18)
    g.setFont(letra)
    local x = 10
    for _, f in ipairs(filtros()) do
        local ancho = letra:getWidth(f[2]) + 24
        local activo = estado.filtro == f[1]
        g.setColor(activo and { 0.17, 0.42, 0.26 } or { 0.16, 0.17, 0.18 })
        g.rectangle('fill', x, 7, ancho, ALTO_BARRA - 14, 4)
        g.setColor(activo and { 0.95, 0.97, 0.96 } or { 0.7, 0.73, 0.74 })
        g.print(f[2], x + 12, 9)
        estado._zonas.filtros[#estado._zonas.filtros + 1] = { x, ancho, f[1] }
        x = x + ancho + 6
    end
    local limpiar = letra:getWidth('Limpiar') + 24
    g.setColor(0.16, 0.17, 0.18)
    g.rectangle('fill', w - limpiar - 10, 7, limpiar, ALTO_BARRA - 14, 4)
    g.setColor(0.75, 0.78, 0.79)
    g.print('Limpiar', w - limpiar + 2, 9)
    estado._zonas.limpiar = { w - limpiar - 10, limpiar }
    -- Las líneas (partidas al ancho), de abajo arriba.
    local datos = Dibujo.letra('dato', 15)
    g.setFont(datos)
    local alto = datos:getHeight() + 3
    local yTope, yFondo = ALTO_BARRA + 6, h - ALTO_ENTRADA - 6
    local caben = math.floor((yFondo - yTope) / alto)
    local ancho = w - 24
    local visibles = {}
    for _, l in ipairs(Depuracion.lineas) do
        if pasa(estado, l) then
            local cabeza = l.hora .. '  [' .. deQuien(l) .. ']  '
            local _, partes = datos:getWrap(cabeza .. l.texto, ancho)
            for k, p in ipairs(partes) do
                visibles[#visibles + 1] = { l = l, texto = p, primera = k == 1, cabeza = cabeza }
            end
        end
    end
    estado.subir = math.max(0, math.min(estado.subir or 0, #visibles - caben))
    local ultima = #visibles - estado.subir
    local y = yTope
    for k = math.max(1, ultima - caben + 1), ultima do
        local v = visibles[k]
        if v.primera then
            -- La cabeza (hora y de quién) en gris; el texto en su color.
            g.setColor(0.45, 0.5, 0.52)
            g.print(v.cabeza, 12, y)
            g.setColor(COLORES[v.l.tipo] or COLORES.print)
            g.print(v.texto:sub(#v.cabeza + 1), 12 + datos:getWidth(v.cabeza), y)
        else
            g.setColor(COLORES[v.l.tipo] or COLORES.print)
            g.print(v.texto, 12, y)
        end
        y = y + alto
    end
    if #visibles == 0 then
        g.setColor(0.45, 0.5, 0.52)
        g.print('Aquí sale lo que escriben con print() los guiones de los robots y los programas.', 12, yTope)
    end
    if estado.subir > 0 then
        g.setColor(0.9, 0.7, 0.25)
        g.printf('… ' .. estado.subir .. ' líneas más abajo (Fin)', 0, yFondo - alto, w - 14, 'right')
    end
    -- La línea para evaluar.
    g.setColor(0.08, 0.085, 0.09)
    g.rectangle('fill', 0, h - ALTO_ENTRADA, w, ALTO_ENTRADA)
    local quien = estado.filtro == 'todo' and 'ordenadores' or estado.filtro
    local pide = quien .. '> '
    g.setColor(0.45, 0.8, 0.95)
    g.print(pide, 12, h - ALTO_ENTRADA + 9)
    local xe = 12 + datos:getWidth(pide)
    g.setColor(0.92, 0.95, 0.93)
    g.print(estado.escrito, xe, h - ALTO_ENTRADA + 9)
    if math.floor((ctx.reloj or 0) * 2) % 2 == 0 then
        g.rectangle('fill', xe + datos:getWidth(estado.escrito) + 1, h - ALTO_ENTRADA + 10, datos:getWidth('m'), alto - 5)
    end
end

-- Evalúa lo escrito en el robot elegido (o en los ordenadores).
local function evaluar(estado, ctx)
    local codigo = estado.escrito
    if codigo:match('^%s*$') then
        return
    end
    estado.escrito = ''
    estado.paso = nil
    estado.subir = 0
    estado.historial[#estado.historial + 1] = codigo
    while #estado.historial > 100 do
        table.remove(estado.historial, 1)
    end
    local r = ApiRobots.buscar(estado.filtro)
    if r then
        Depuracion.evaluar(codigo, { self = r, Lugares = require('almacen.robots.especializaciones.guion').lugares() }, { robot = estado.filtro, archivo = 'depurador' })
    else
        Depuracion.evaluar(codigo, { robots = ApiRobots.para(ctx.ordenador), muro = require('almacen.pc.muro').para() }, { puesto = ctx.ordenador.nombre, archivo = 'depurador' })
    end
end

function Depurador.raton(estado, ctx, accion, x, y)
    if accion ~= 'pulsar' or y > ALTO_BARRA or not estado._zonas then
        return
    end
    local l = estado._zonas.limpiar
    if l and x >= l[1] and x < l[1] + l[2] then
        Depuracion.limpiar()
        estado.subir = 0
        return
    end
    for _, f in ipairs(estado._zonas.filtros) do
        if x >= f[1] and x < f[1] + f[2] then
            estado.filtro = f[3]
            estado.subir = 0
        end
    end
end

function Depurador.texto(estado, ctx, t)
    estado.escrito = estado.escrito .. t
    estado.paso = nil
end

function Depurador.tecla(estado, ctx, tecla)
    if tecla == 'return' or tecla == 'kpenter' then
        evaluar(estado, ctx)
    elseif tecla == 'backspace' then
        local s = estado.escrito
        local corte = #s
        while corte > 0 and s:byte(corte) >= 0x80 and s:byte(corte) < 0xC0 do
            corte = corte - 1
        end
        estado.escrito = s:sub(1, math.max(0, corte - 1))
    elseif tecla == 'up' or tecla == 'down' then
        local h = estado.historial
        if #h > 0 then
            local paso = estado.paso or (#h + 1)
            paso = math.max(1, math.min(#h + 1, paso + (tecla == 'up' and -1 or 1)))
            estado.paso = paso
            estado.escrito = h[paso] or ''
        end
    elseif tecla == 'pageup' then
        estado.subir = (estado.subir or 0) + 10
    elseif tecla == 'pagedown' then
        estado.subir = math.max(0, (estado.subir or 0) - 10)
    elseif tecla == 'end' then
        estado.subir = 0
    end
end

--- Icono: un bicho dentro de un cuadro (el de los depuradores).
function Depurador.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.55, 0.22, 0.2)
    g.rectangle('fill', x, y, s, s, s * 0.18)
    g.setColor(0.95, 0.88, 0.85)
    g.ellipse('fill', x + s * 0.5, y + s * 0.56, s * 0.17, s * 0.23)
    g.circle('fill', x + s * 0.5, y + s * 0.3, s * 0.1)
    g.setLineWidth(math.max(1, s * 0.05))
    for _, f in ipairs({ 0.45, 0.58, 0.71 }) do
        g.line(x + s * 0.22, y + s * f, x + s * 0.78, y + s * f)
    end
    g.setLineWidth(1)
end

return Depurador

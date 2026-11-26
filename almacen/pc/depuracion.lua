-- Lo que escriben los guiones y programas con print(), para el Depurador de
-- los ordenadores de la sala (el dueño, 26-nov: «que los print de Lua se
-- muestren en el PC»). Es de la red: todos los puestos ven lo mismo.
--
--   Depuracion.apuntar(origen, texto, tipo, linea)
--       origen: { robot = 'soldado', archivo = 'patrulla.lua' } o
--       { puesto = 'puesto-2', archivo = 'estado.lua' }; tipo 'print' o
--       'error'; linea: la del archivo donde se llamó
--   Depuracion.texto(v)      v en texto; las tablas desplegadas (campos,
--                            piezas con su nombre, métodos get...)
--   Depuracion.lineas        las apuntadas (las últimas `maximo`)

local Depuracion = {}

Depuracion.maximo = 2000
Depuracion.lineas = {}
Depuracion.numero = 0 -- cuántas se han apuntado en total (para seguir la última)
Depuracion.campos = 24 -- campos de una tabla que se enseñan
Depuracion.hondo = 2 -- niveles de tablas dentro de tablas

function Depuracion.apuntar(origen, texto, tipo, linea)
    local reloj = love.timer and love.timer.getTime() or os.clock()
    for parte in (tostring(texto) .. '\n'):gmatch('(.-)\n') do
        Depuracion.numero = Depuracion.numero + 1
        Depuracion.lineas[#Depuracion.lineas + 1] = {
            reloj = reloj,
            hora = os.date('%H:%M:%S'),
            robot = origen.robot,
            puesto = origen.puesto,
            archivo = origen.archivo,
            linea = linea and linea > 0 and linea or nil,
            tipo = tipo or 'print',
            texto = parte,
        }
    end
    while #Depuracion.lineas > Depuracion.maximo do
        table.remove(Depuracion.lineas, 1)
    end
end

function Depuracion.limpiar()
    Depuracion.lineas = {}
end

local function numero(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format('%d', v)
    end
    return string.format('%.4g', v)
end

-- Una tabla en una palabra: la pieza con su nombre, el robot con su tipo...
local function resumen(t)
    local mt = getmetatable(t)
    if type(t.nombre) == 'string' and t.robot then
        return '<pieza ' .. t.nombre .. '>'
    end
    if t.tipo and t.datos and t.piezas then
        return '<robot ' .. tostring(t.tipo) .. '>'
    end
    if t.getNombre and mt then
        local ok, n = pcall(t.getNombre, t)
        if ok then
            return '<' .. tostring(n) .. '>'
        end
    end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return mt and ('<objeto, ' .. n .. ' campos>') or ('{… ' .. n .. '}')
end

-- Los métodos get... de un objeto (por su metatabla), para saber qué se le
-- puede preguntar.
local function metodos(t)
    local lista, vistos = {}, {}
    local mt = getmetatable(t)
    local indice = mt and mt.__index
    local vueltas = 0
    while type(indice) == 'table' and vueltas < 5 do
        for k, v in pairs(indice) do
            if type(k) == 'string' and type(v) == 'function' and k:match('^get') and not vistos[k] then
                vistos[k] = true
                lista[#lista + 1] = k
            end
        end
        local m = getmetatable(indice)
        indice = m and m.__index
        vueltas = vueltas + 1
    end
    table.sort(lista)
    return lista
end

local function texto(v, hondo, sangria)
    local t = type(v)
    if t == 'string' then
        return v
    elseif t == 'number' then
        return numero(v)
    elseif t ~= 'table' then
        return tostring(v)
    end
    if hondo <= 0 then
        return resumen(v)
    end
    -- Las claves en orden: números primero, luego por nombre.
    local claves = {}
    for k, x in pairs(v) do
        if type(x) ~= 'function' then
            claves[#claves + 1] = k
        end
    end
    table.sort(claves, function(a, b)
        if type(a) ~= type(b) then
            return type(a) == 'number'
        end
        return tostring(a) < tostring(b)
    end)
    local partes = {}
    local otra = sangria .. '  '
    for k = 1, math.min(#claves, Depuracion.campos) do
        local c = claves[k]
        local x = v[c]
        local valor = type(x) == 'table' and (hondo > 1 and texto(x, hondo - 1, otra) or resumen(x)) or texto(x, 0, otra)
        if type(x) == 'string' then
            valor = string.format('%q', x)
        end
        partes[#partes + 1] = otra .. tostring(c) .. ' = ' .. valor
    end
    if #claves > Depuracion.campos then
        partes[#partes + 1] = otra .. '… y ' .. (#claves - Depuracion.campos) .. ' más'
    end
    -- Los métodos, solo del primer nivel (los de dentro lo llenarían todo).
    local get = sangria == '' and getmetatable(v) and metodos(v) or {}
    if #get > 0 then
        partes[#partes + 1] = otra .. 'métodos: ' .. table.concat(get, ', ')
    end
    if #partes == 0 then
        return resumen(v) == '{… 0}' and '{}' or resumen(v)
    end
    return resumen(v) .. ' {\n' .. table.concat(partes, '\n') .. '\n' .. sangria .. '}'
end

--- El nombre corto de un robot (el de las órdenes: 'almacen', 'soldado').
function Depuracion.nombreDe(robot)
    local Guion = require('almacen.robots.especializaciones.guion')
    return Guion.nombres[robot.tipo] or tostring(robot.tipo)
end

--- Desde ahora, print() en el código de cualquier robot (sus
-- especializaciones, también las del juego: almacenaje, transporte...) sale
-- además en su depuración, con el archivo y la línea. Lo demás del juego
-- sigue yendo solo a la consola.
function Depuracion.engancharPrint()
    if Depuracion.printOriginal then
        return
    end
    local original = print
    Depuracion.printOriginal = original
    print = function(...)
        original(...)
        local Robot = GestorRobots and GestorRobots.Robot
        local r = Robot and Robot.enCurso
        if not r then
            return
        end
        local partes = {}
        for k = 1, select('#', ...) do
            partes[k] = Depuracion.texto((select(k, ...)))
        end
        local info = debug.getinfo(2, 'Sl')
        local archivo = info and info.source and info.source:match('([^/@=]+)$')
        Depuracion.apuntar({ robot = Depuracion.nombreDe(r), archivo = archivo }, table.concat(partes, '  '), 'print', info and info.currentline)
    end
end

--- Evalúa una línea de Lua escrita en el depurador (una expresión, como
-- `self:getPieza('cabeza')`, o una orden, como `self:setMirarA(0, 0, 1)`),
-- con `api` a la vista (`self`, `robots`, `Lugares`...). Apunta lo escrito
-- y su resultado (o el error) con `origen`.
function Depuracion.evaluar(codigo, api, origen)
    local Lua = require('almacen.pc.lua')
    Depuracion.apuntar(origen, '> ' .. codigo, 'orden')
    local f = loadstring('return ' .. codigo, '=depurador')
    if not f then
        local error
        f, error = loadstring(codigo, '=depurador')
        if not f then
            Depuracion.apuntar(origen, error, 'error')
            return
        end
    end
    local env = Lua.entorno(api, function(texto, linea)
        Depuracion.apuntar(origen, texto, 'print', linea)
    end)
    env.sleep = nil
    setfenv(f, env)
    jit.off(f, true)
    debug.sethook(function()
        error('demasiado tiempo sin terminar', 2)
    end, '', Lua.limite)
    local resultado = { pcall(f) }
    debug.sethook()
    if not resultado[1] then
        Depuracion.apuntar(origen, tostring(resultado[2]), 'error')
        return
    end
    local partes = {}
    for k = 2, table.maxn(resultado) do
        partes[#partes + 1] = Depuracion.texto(resultado[k])
    end
    if #partes > 0 then
        Depuracion.apuntar(origen, table.concat(partes, '\t'), 'resultado')
    end
end

--- `v` en texto, con las tablas desplegadas.
function Depuracion.texto(v)
    local ok, r = pcall(texto, v, Depuracion.hondo, '')
    return ok and r or tostring(v)
end

return Depuracion

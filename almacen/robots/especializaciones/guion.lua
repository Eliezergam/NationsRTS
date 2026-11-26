-- Ejecutables de los robots, desde los ordenadores de la sala (el dueño,
-- 26-nov). Un ejecutable es una especialización como las de esta carpeta
-- (onLoad, onUpdate... y `self` = el robot, con todas sus órdenes): los de
-- ~/guiones se escriben en un ordenador y se puede programar el robot desde
-- 0; los del juego (almacen/robots/ejecutables.lua) ponen en marcha lo que
-- hacía de siempre (trabajar.lua, practicar.lua). Muchos pequeños, uno
-- para cada cosa.
--
-- Cada robot tiene especializaciones de cuerpo (conducción, lidar,
-- navegación, brazos, transporte...) y de trabajo (las de `trabajo = { ... }`
-- en su tipo). Ejecuta uno solo a la vez: el nuevo sustituye al anterior,
-- nunca va encima. Modos: 'ejecutando' o 'parado'.
-- Al cambiar, lo que llevaba en las manos vuelve a donde lo cogió (el hueco
-- del rack o de la mesa de descarga), no se suelta donde esté; brazos,
-- pinzas, mirada y ruta quedan en reposo. Un ejecutable del juego empieza
-- siempre de nuevo (onLoad).
--
-- Órdenes que añade al robot:
--   robot:setGuion(codigo, nombre) -> true o false, error   (uno de ~/guiones)
--   robot:setEjecutable(entrada) -> true o false, error      (uno del juego)
--   robot:setOrden('parar' | 'trabajar')  quieto / el primero del juego
--   robot:getEjecutables()          los del juego que puede ejecutar
--   robot:setTarea(texto)           lo que dice que hace (sale en Robots)
--   robot:getModo(), robot:getGuion() (lo que ejecuta), robot:getSalida()
--
-- En un ejecutable de ~/guiones, además de lo de Lua (math, string, table,
-- print...), está `Lugares` (Lugares.patio = { x, y }: almacen/robots/
-- lugares.lua). Un error, o un onUpdate que no termina, lo para y queda
-- escrito en su salida.

local Lua = require('almacen.pc.lua')
local ListaLugares = require('almacen.robots.lugares')
local Ejecutables = require('almacen.robots.ejecutables')
local Depuracion = require('almacen.pc.depuracion')

local Guion = {}
Guion.maximoSalida = 200

-- El nombre corto de cada tipo (el que se usa en las órdenes).
Guion.nombres = { robotAlmacen = 'almacen', robotSoldado = 'soldado', robotPesado = 'pesado' }
Guion.titulos = { robotAlmacen = 'Robot del almacén', robotSoldado = 'Soldado', robotPesado = 'Robot pesado' }

local Robot = GestorRobots.Robot
local montar

function Guion:onLoad()
    local d = self.datos.guion
    d.modo = 'ejecutando'
    d.salida = {}
    -- Las especializaciones tal como las dejó su tipo (para volver a ellas).
    d.original = {}
    for k, e in ipairs(self.especializaciones) do
        d.original[k] = e
    end
    -- Al empezar, el primero del juego que le sirve (lo de siempre), con
    -- solo sus especializaciones de trabajo.
    local primero = self:getEjecutables()[1]
    d.nombre = primero and primero.archivo
    montar(self, primero and primero.especializaciones or {})
end

--- Los sitios con nombre, como los ven los guiones: { patio = { x, y }, ... }.
function Guion.lugares()
    local lugares = {}
    for _, l in ipairs(ListaLugares) do
        lugares[l[1]] = { l[2], l[3] }
    end
    return lugares
end

local function apuntar(self, texto)
    local d = self.datos.guion
    for linea in (tostring(texto) .. '\n'):gmatch('(.-)\n') do
        d.salida[#d.salida + 1] = linea
    end
    while #d.salida > Guion.maximoSalida do
        table.remove(d.salida, 1)
    end
end

--- Lo que dice que está haciendo (donde lo leen getTarea y el panel).
function Robot:setTarea(texto)
    texto = tostring(texto)
    if self.datos.transporte then
        self.datos.transporte.tarea = texto
    end
    if self.datos.practicaSoldado then
        self.datos.practicaSoldado.tarea = texto
    end
end

local function esTrabajo(self, nombre)
    for _, n in ipairs(self.trabajo or {}) do
        if n == nombre then
            return true
        end
    end
    return false
end

-- Lo que lleva vuelve al hueco de donde lo cogió (si alguien lo ha ocupado,
-- a otro libre del mismo mueble).
local function devolver(self)
    local m = self.datos.manipulacion
    local o = m and m.objeto
    if not o then
        return
    end
    local mueble, numero = m.origen and m.origen[1], m.origen and m.origen[2]
    m.objeto, m.agarres, m.origen = nil, nil, nil
    o.llevadoPor = nil
    if mueble then
        if mueble.huecosOcupados[numero] then
            numero = nil
            for k in ipairs(mueble:getHuecos()) do
                if not mueble.huecosOcupados[k] then
                    numero = k
                    break
                end
            end
        end
        if numero then
            o:setApoyar(mueble, numero)
            apuntar(self, '— la ' .. o:getNombre() .. ' vuelve a ' .. mueble:getNombre())
            print('ROBOT devuelvo la ' .. o:getNombre() .. ' a ' .. mueble:getNombre() .. ' (hueco ' .. numero .. ')')
            return
        end
    end
    print('ROBOT no tengo dónde devolver la ' .. o:getNombre())
end

-- Deja el cuerpo en reposo: devuelve lo que lleva, sin encargos, brazos
-- abajo, sin mirar nada y quieto.
local function reposo(self)
    devolver(self)
    local t = self.datos.transporte
    if t then
        t.hilo = nil
        t.encargos = {}
    end
    if self.datos.brazos then
        for _, lado in ipairs({ 'izq', 'der' }) do
            self:setBrazo(lado, 0, 0, 0, 0)
            self:setPinza(lado, 0.05)
        end
        self:setAgachar(0)
    end
    if self.datos.mirada then
        self:setMirarA(nil)
        self:setFoco(nil)
    end
    if self.datos.navegacion then
        self.datos.navegacion.destino = nil
        self.datos.navegacion.ruta = nil
    end
    self:setParar()
end

-- Pone la lista de especializaciones: las de su tipo sin las de trabajo y,
-- si hay, el guion al final. (Una tabla nueva: si esto pasa dentro de
-- llamar(), el recorrido sigue con la de antes sin saltarse nada.)
montar = function(self, activas, entrada)
    local si = {}
    for _, n in ipairs(activas) do
        si[n] = true
    end
    local lista = {}
    for _, e in ipairs(self.datos.guion.original) do
        if si[e.nombre] or not esTrabajo(self, e.nombre) then
            lista[#lista + 1] = e
        end
    end
    lista[#lista + 1] = entrada
    self.especializaciones = lista
end

-- Llama un evento del guion con el contador de instrucciones puesto; si
-- falla, el robot se para y el error queda en su salida.
local function protegido(self, f, ...)
    debug.sethook(function()
        error('demasiado tiempo sin terminar (¿un bucle que no acaba?)', 2)
    end, '', Lua.limite)
    local ok, error = xpcall(f, debug.traceback, self, ...)
    debug.sethook()
    if not ok then
        -- En el depurador, con por dónde pasó; en su salida, solo el error.
        local d = self.datos.guion
        Depuracion.apuntar({ robot = Guion.nombres[self.tipo] or tostring(self.tipo), archivo = d.nombre }, tostring(error):gsub('\n%s*%[C%]: in function \'xpcall\'.*$', ''), 'error')
        error = tostring(error):match('^[^\n]*')
        apuntar(self, '— error: ' .. tostring(error))
        -- A la consola solo (en la depuración ya está, en rojo).
        ;(Depuracion.printOriginal or print)('ROBOT error en el guion ' .. tostring(self.datos.guion.nombre) .. ': ' .. tostring(error))
        self:setOrden('parar')
    end
    return ok
end

local EVENTOS = { 'onLoad', 'onUpdate', 'onPose' }

--- Los ejecutables del juego que puede ejecutar este robot (los que tienen
-- todas sus especializaciones en su `trabajo`).
function Robot:getEjecutables()
    local lista = {}
    for _, e in ipairs(Ejecutables) do
        local sirve = true
        for _, n in ipairs(e.especializaciones) do
            sirve = sirve and esTrabajo(self, n)
        end
        if sirve then
            lista[#lista + 1] = e
        end
    end
    return lista
end

-- Quita lo que ejecutaba (con lo que llevase en las manos devuelto).
local function quitar(self)
    local d = self.datos.guion
    if d.nombre then
        apuntar(self, '— «' .. d.nombre .. '» quitado')
    end
    reposo(self)
    d.nombre, d.clave = nil, nil
end

--- Ejecuta uno del juego (`entrada` de almacen/robots/ejecutables.lua):
-- sus especializaciones de trabajo empiezan de nuevo.
function Robot:setEjecutable(entrada)
    for _, n in ipairs(entrada.especializaciones) do
        if not esTrabajo(self, n) then
            return false, 'este robot no sabe hacer ' .. entrada.archivo
        end
    end
    local d = self.datos.guion
    quitar(self)
    d.modo = 'ejecutando'
    d.nombre = entrada.archivo
    montar(self, entrada.especializaciones)
    for _, e in ipairs(self.especializaciones) do
        if esTrabajo(self, e.nombre) then
            self.datos[e.nombre] = {}
            if e.tabla.onLoad then
                self.actual, Robot.enCurso = e.nombre, self
                e.tabla.onLoad(self)
                self.actual, Robot.enCurso = nil, nil
            end
        end
    end
    self:setTarea('ejecuto ' .. entrada.archivo)
    apuntar(self, '— «' .. entrada.archivo .. '» en marcha')
    return true
end

--- 'parar' (quieto, sin ejecutar nada) o 'trabajar' (el primero del juego
-- que le sirve: lo de siempre).
function Robot:setOrden(orden)
    if orden == 'trabajar' then
        local primero = self:getEjecutables()[1]
        if primero then
            return self:setEjecutable(primero)
        end
    end
    local d = self.datos.guion
    quitar(self)
    d.modo = 'parado'
    montar(self, {})
    self:setTarea('parado: espero órdenes')
    apuntar(self, '— parado')
    return true
end

--- Le pone el guion `codigo` (una especialización en Lua: devuelve su
-- tabla) en lugar de su trabajo o del guion anterior. Si no compila o falla
-- al cargar, no cambia nada y devuelve false y el error.
function Robot:setGuion(codigo, nombre)
    local d = self.datos.guion
    local clave = (nombre or 'guion'):gsub('%.lua$', ''):gsub('[^%w_]', '_')
    -- Que no pise los datos de una especialización del robot.
    if self.datos[clave] and clave ~= d.clave then
        clave = 'guion_' .. clave
    end
    local lugares = Guion.lugares()
    local origen = { robot = Guion.nombres[self.tipo] or tostring(self.tipo), archivo = nombre }
    local env = Lua.entorno({ Lugares = lugares }, function(texto, linea)
        apuntar(self, texto)
        Depuracion.apuntar(origen, texto, 'print', linea)
    end)
    env.math.random = love.math.random
    -- Un guion no espera dentro de onUpdate (como una especialización): mira
    -- el reloj (dt) y sigue en el cuadro siguiente.
    env.sleep = nil
    local f, error = loadstring(codigo, '=' .. tostring(nombre))
    if not f then
        apuntar(self, '— error en «' .. tostring(nombre) .. '»: ' .. tostring(error))
        Depuracion.apuntar(origen, tostring(error), 'error')
        return false, error
    end
    setfenv(f, env)
    jit.off(f, true)
    debug.sethook(function()
        error('demasiado tiempo sin terminar', 2)
    end, '', Lua.limite)
    local ok, tabla = pcall(f)
    debug.sethook()
    if not ok or type(tabla) ~= 'table' then
        local motivo = not ok and tostring(tabla) or 'el guion tiene que acabar con «return» y su tabla (como las especializaciones)'
        apuntar(self, '— error en «' .. tostring(nombre) .. '»: ' .. motivo)
        Depuracion.apuntar(origen, motivo, 'error')
        return false, motivo
    end
    -- Fuera lo de antes, con lo que llevase devuelto.
    quitar(self)
    -- Sus eventos, protegidos.
    local envuelta = {}
    for _, evento in ipairs(EVENTOS) do
        if type(tabla[evento]) == 'function' then
            local fn = tabla[evento]
            envuelta[evento] = function(robot, ...)
                protegido(robot, fn, ...)
            end
        end
    end
    d.modo = 'ejecutando'
    d.nombre = nombre
    d.clave = clave
    self.datos[clave] = {}
    montar(self, {}, { nombre = clave, tabla = envuelta })
    self:setTarea('ejecuto ' .. tostring(nombre))
    apuntar(self, '— «' .. tostring(nombre) .. '» en marcha')
    if envuelta.onLoad then
        self.actual, Robot.enCurso = clave, self
        envuelta.onLoad(self)
        self.actual, Robot.enCurso = nil, nil
    end
    return true
end

function Robot:getModo()
    return self.datos.guion.modo
end

function Robot:getGuion()
    return self.datos.guion.nombre
end

function Robot:getSalida()
    return self.datos.guion.salida
end

GestorRobots.registrarEspecializacion('guion', Guion)
return Guion

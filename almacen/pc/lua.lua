-- Lua dentro del juego (26-nov): los programas que se escriben en los
-- ordenadores de la sala corren aislados, cada uno en su corrutina:
--   * solo ven lo que se les da (math, string, table, print, sleep... y la API
--     de quien los corre: `robots` en un ordenador); nada del juego ni del
--     disco;
--   * sleep cede el turno (coroutine.yield) y el programa sigue en un cuadro
--     posterior;
--   * si un programa no cede en mucho rato (un bucle sin `sleep`), se corta
--     con «demasiado tiempo sin esperar».
--
--   local p, error = Lua.cargar(codigo, 'patrulla.lua', api, salida)
--   p:paso(dt) -> 'sigue' | 'fin' | 'error', mensaje

local Lua = {}
Lua.__index = Lua

-- Instrucciones seguidas sin ceder antes de cortarlo.
Lua.limite = 2000000

local function copia(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

--- El entorno de un programa: lo de Lua que no toca nada de fuera, `api`
-- (tabla de tablas: { robot = {...} }) y print/write/sleep que van a
-- `salida(texto)`.
function Lua.entorno(api, salida)
    local env = {
        math = copia(math),
        string = copia(string),
        table = copia(table),
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        select = select,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        error = error,
        assert = assert,
        pcall = pcall,
        unpack = unpack,
        rawequal = rawequal,
        setmetatable = setmetatable,
        -- Solo de sus tablas: la de las cadenas es la del juego.
        getmetatable = function(t)
            if type(t) == 'table' then
                return getmetatable(t)
            end
        end,
        os = {
            clock = os.clock,
            time = os.time,
            date = os.date,
        },
    }
    env._G = env
    -- print: las tablas desplegadas (almacen/pc/depuracion.lua); a `salida`
    -- va también la línea del archivo desde donde se llamó.
    local Depuracion = require('almacen.pc.depuracion')
    function env.print(...)
        local partes = {}
        for k = 1, select('#', ...) do
            partes[k] = Depuracion.texto((select(k, ...)))
        end
        local info = debug.getinfo(2, 'l')
        salida(table.concat(partes, '\t'), info and info.currentline)
    end
    env.write = function(texto)
        local info = debug.getinfo(2, 'l')
        salida(tostring(texto), info and info.currentline)
    end
    --- Espera `s` segundos de juego (cede el turno mientras).
    function env.sleep(s)
        local queda = tonumber(s) or 0
        repeat
            queda = queda - coroutine.yield()
        until queda <= 0
    end
    for nombre, tabla in pairs(api or {}) do
        env[nombre] = tabla
    end
    return env
end

--- Compila `codigo`. Devuelve el programa o nil y el error (en español).
function Lua.cargar(codigo, nombre, api, salida)
    if codigo:byte(1) == 27 then
        return nil, 'no se pueden cargar programas compilados'
    end
    local f, error = loadstring(codigo, '=' .. (nombre or 'programa'))
    if not f then
        return nil, error
    end
    local env = Lua.entorno(api, salida)
    setfenv(f, env)
    -- Sin JIT, para que el contador de instrucciones salte también dentro
    -- de los bucles compilados.
    jit.off(f, true)
    local self = setmetatable({}, Lua)
    self.nombre = nombre
    self.hilo = coroutine.create(f)
    self.estado = 'sigue'
    return self
end

--- Sigue el programa hasta que ceda o acabe. `dt`: s desde el paso anterior
-- (lo que devuelve el yield en que esperaba).
function Lua:paso(dt)
    if self.estado ~= 'sigue' then
        return self.estado, self.mensaje
    end
    -- El contador de instrucciones: en LuaJIT es de toda la máquina, no de
    -- la corrutina; se pone solo mientras corre el programa.
    debug.sethook(function()
        error('demasiado tiempo sin esperar (usa sleep en los bucles)', 2)
    end, '', Lua.limite)
    local ok, mensaje = coroutine.resume(self.hilo, dt or 0)
    debug.sethook()
    if not ok then
        self.estado, self.mensaje = 'error', tostring(mensaje)
    elseif coroutine.status(self.hilo) == 'dead' then
        self.estado = 'fin'
    end
    return self.estado, self.mensaje
end

--- Lo corta desde fuera (Ctrl+T, otra orden).
function Lua:terminar()
    if self.estado == 'sigue' then
        self.estado, self.mensaje = 'error', 'terminado'
    end
end

return Lua

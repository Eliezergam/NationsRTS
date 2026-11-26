-- Profiler de NV: cuenta y cronometra lo que hace la navegación en cada
-- cuadro, solo cuando está encendido.
--
--   local NvProfiler = require('runtime.nv.profiler')
--   local prof = NvProfiler.new()
--   prof:setEnabled(true)              -- prof.enabled
--   prof:beginFrame()                  -- al empezar el trabajo NV del cuadro
--   local t = prof:start()             -- nil si está apagado
--   ... trabajo ...
--   prof:finish('agents', t)           -- suma a la sección (no hace nada con t = nil)
--   prof:count('repaths')              -- contador acumulado (+1, o +n)
--   prof:endFrame()                    -- cierra: cpuMs = suma de secciones
--   prof.cpuMs, prof.sections.agents, prof.counters.repaths
--
-- Apagado cuesta casi nada: `start` devuelve nil sin mirar el reloj,
-- `finish` y `count` vuelven en la primera comparación y `beginFrame` /
-- `endFrame` no hacen nada. El reloj es `love.timer.getTime` si hay LÖVE
-- (detección con `pcall`, igual que el planificador) y `os.clock` si no.
--
-- `cpuMs` es la suma de las secciones medidas en el cuadro (planificador,
-- índice de agentes, LOD, agentes, grupos), no el tiempo de pared entre
-- `beginFrame` y `endFrame`: entre medias corren otras entidades del nivel
-- que no son de NV. `frameMs` sí guarda ese tiempo de pared, por si se
-- quiere comparar.
--
-- Memoria (fase F): encendido, `start` también apunta
-- `collectgarbage('count')` y `finish` suma lo que creció la memoria de Lua
-- dentro de la sección; `gcKilobytes` es la suma del último cuadro completo
-- (KB). Es una cota por abajo: si un paso del recolector libera memoria
-- dentro de una sección, esa sección cuenta 0. Las secciones no se anidan
-- (la marca de memoria es una sola); leer el contador no reserva nada.

local NvUtil = require('runtime.nv.util')
local NavigationScheduler = require('runtime.nv.scheduler')

local NvProfiler = NvUtil.class('NvProfiler')

function NvProfiler:init(opts)
    opts = opts or {}
    self.enabled = opts.enabled == true
    self.clock = type(opts.clock) == 'function' and opts.clock or NavigationScheduler.detectClock()
    self.cpuMs = 0
    self.frameMs = 0
    self.frames = 0
    self.sections = {} -- nombre → ms del último cuadro completo
    self.counters = {} -- nombre → acumulado desde el último reset
    self._sections = {} -- en curso
    self._t0 = nil
    self.gcKilobytes = 0 -- KB que creció la memoria de Lua en las secciones del último cuadro
    self._gc = 0 -- en curso
    self._kb = 0 -- marca de memoria del último `start`
end

function NvProfiler:setEnabled(enabled)
    self.enabled = enabled == true
    if not self.enabled then
        self.cpuMs, self.frameMs = 0, 0
        self.gcKilobytes, self._gc = 0, 0
        self._t0 = nil
    end
    return self
end

--- Marca de tiempo para `finish`, o nil si está apagado.
function NvProfiler:start()
    if not self.enabled then
        return nil
    end
    self._kb = collectgarbage('count')
    return self.clock()
end

--- Suma a la sección `name` el tiempo desde `t` (una marca de `start`).
function NvProfiler:finish(name, t)
    if t == nil or not self.enabled then
        return 0
    end
    local ms = (self.clock() - t) * 1000
    self._sections[name] = (self._sections[name] or 0) + ms
    local grown = collectgarbage('count') - self._kb
    if grown > 0 then
        self._gc = self._gc + grown
    end
    return ms
end

--- Suma `n` (1 por defecto) al contador `name`.
function NvProfiler:count(name, n)
    if not self.enabled then
        return
    end
    self.counters[name] = (self.counters[name] or 0) + (n or 1)
end

function NvProfiler:beginFrame()
    if not self.enabled then
        return
    end
    self._t0 = self.clock()
    for name in pairs(self._sections) do
        self._sections[name] = 0
    end
    self._gc = 0
end

function NvProfiler:endFrame()
    if not self.enabled then
        return
    end
    local total = 0
    for name, ms in pairs(self._sections) do
        self.sections[name] = ms
        total = total + ms
    end
    self.cpuMs = total
    self.gcKilobytes = self._gc
    if self._t0 then
        self.frameMs = (self.clock() - self._t0) * 1000
    end
    self.frames = self.frames + 1
end

--- Pone a cero contadores y secciones.
function NvProfiler:reset()
    self.counters = {}
    self.sections = {}
    self._sections = {}
    self.cpuMs, self.frameMs, self.frames = 0, 0, 0
    self.gcKilobytes, self._gc = 0, 0
    return self
end

return NvProfiler

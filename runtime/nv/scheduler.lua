-- Planificador de búsquedas de ruta (NavigationScheduler): una cola con
-- presupuesto por cuadro para que una orden a 500 unidades no lance 500 A*
-- en el mismo `update`.
--
--   local NavigationScheduler = require('runtime.nv.scheduler')
--   local s = NavigationScheduler.new(manager, { maxRequestsPerFrame = 20, maxPathfindingTimeMs = 2 })
--   local request = s:request({
--       system = sys, sx = x0, sy = y0, tx = x1, ty = y1, props = agentProps,
--       owner = agent,                 -- una petición nueva del mismo dueño cancela la pendiente
--       priority = 'order',            -- 'selected' | 'order' | 'repath' | 'normal' | 'speculative'
--       callback = function(route, err, request) ... end,
--       immediate = false,             -- true: se resuelve ahora, fuera del presupuesto
--   })
--   request.state                      -- 'queued' | 'done' | 'failed' | 'cancelled'
--   s:update()                         -- una vez por cuadro: procesa la cola
--   s:cancel(request)  s:cancelFor(owner)
--   s:stats()                          -- queued, processedPerFrame, cacheHits, cacheMisses,
--                                      -- averageSearchMs, maxSearchMs, cancelled, deduplicated, failed
--
-- Orden de una petición:
--
--   1. Proyección síncrona de origen y destino sobre la red (barata: consulta
--      al spatial hash de tramos). Si alguna falla, la petición falla YA con
--      'origen lejos de la red' / 'destino lejos de la red': el que llama no
--      espera cuadros para saber que su unidad no llega a la red.
--   2. Consulta a `PathCache` ANTES de gastar presupuesto:
--      `system:requestPath(..., { cacheOnly = true })` construye la ruta si
--      todos los tramos de nodos que necesita ya están en la caché (o si origen
--      y destino caen en el mismo tramo, que no necesita A*). Cuenta como
--      `cacheHits` y el callback se llama en el acto.
--   3. Si no, entra en la cola (`cacheMisses`) con prioridad y número de orden:
--      dentro de una misma prioridad se atiende por llegada.
--
-- Presupuesto (`update`): se sacan peticiones hasta `maxRequestsPerFrame` o
-- hasta que la suma de tiempos de búsqueda del cuadro supera
-- `maxPathfindingTimeMs`. El tiempo se mide con `love.timer.getTime` si hay
-- LÖVE y con `os.clock` si no (detección con `pcall`; este módulo no usa
-- `love` para nada más). Una búsqueda que se pasa del tiempo no se corta (A*
-- no es reanudable); el límite de tiempo es "no empezar otra si ya nos
-- pasamos", el de peticiones es estricto.
--
-- Deduplicación: dos peticiones son equivalentes si van a la misma red,
-- salen y entran por los mismos tramos proyectados y tienen la misma clase
-- de agente (`key`). Cuando se resuelve la primera con una búsqueda de
-- verdad, las demás con su misma clave se resuelven acto seguido por la
-- caché (sin A*: `deduplicated`). Así los miembros de un grupo comparten los
-- pasos de A* (la misma tabla `route.steps`, vía `PathCache`) y cada uno
-- conserva su tramo de entrada y salida propio. Un tag distinto o una clase
-- distinta es otra clave: no comparten.
--
-- Cancelación: `cancel(request)` marca la petición y la saca de los índices;
-- el heap la descarta al sacarla (reinserción perezosa, como en A*). Una
-- petición nueva con el mismo `owner` cancela la anterior pendiente.

local NvUtil = require('runtime.nv.util')
local Heap = require('runtime.nv.heap')

local NavigationScheduler = NvUtil.class('NavigationScheduler')

NavigationScheduler.defaults = { maxRequestsPerFrame = 20, maxPathfindingTimeMs = 2.0 }

--- Prioridades: menor número, antes.
NavigationScheduler.priority = { selected = 1, order = 2, repath = 3, normal = 4, speculative = 5 }

local SEQUENCE_SPAN = 2 ^ 32

--- Reloj en segundos: `love.timer.getTime` si existe, si no `os.clock`.
function NavigationScheduler.detectClock()
    local ok, fn = pcall(function()
        local timer = love and love.timer
        if timer and type(timer.getTime) == 'function' then
            return timer.getTime
        end
        return nil
    end)
    if ok and fn then
        return fn
    end
    return os.clock
end

function NavigationScheduler:init(manager, opts)
    opts = opts or {}
    local d = NavigationScheduler.defaults
    self.manager = manager
    self.maxRequestsPerFrame = math.max(1, math.floor(NvUtil.finite(opts.maxRequestsPerFrame, d.maxRequestsPerFrame)))
    self.maxPathfindingTimeMs = NvUtil.atLeast(opts.maxPathfindingTimeMs, d.maxPathfindingTimeMs, 0)
    self.clock = type(opts.clock) == 'function' and opts.clock or NavigationScheduler.detectClock()
    self.heap = Heap.new()
    self.sequence = 0
    self.byOwner = {} -- dueño → petición en cola
    self.byKey = {} -- clave → lista de peticiones en cola
    self.queued = 0
    self.frame = 0
    self._stats = {
        queued = 0,
        processedPerFrame = 0,
        cacheHits = 0,
        cacheMisses = 0,
        averageSearchMs = 0,
        maxSearchMs = 0,
        cancelled = 0,
        deduplicated = 0,
        failed = 0,
        searches = 0,
        totalSearchMs = 0,
        frameSearchMs = 0,
        immediate = 0,
    }
end

local function priorityOf(value)
    if type(value) == 'number' then
        return value
    end
    return NavigationScheduler.priority[value] or NavigationScheduler.priority.normal
end

--- Clave de deduplicación: red, tramo de salida, tramo de entrada y clase.
function NavigationScheduler.key(system, startSegmentId, goalSegmentId, agentClass)
    return tostring(system.id)
        .. '|'
        .. tostring(startSegmentId)
        .. '|'
        .. tostring(goalSegmentId)
        .. '|'
        .. tostring(agentClass or '*')
end

local function finish(self, request, route, err)
    request.state = route and 'done' or 'failed'
    request.route, request.err = route, err
    if not route then
        self._stats.failed = self._stats.failed + 1
    end
    if request.callback then
        request.callback(route, err, request)
    end
end

local function unindex(self, request)
    if self.byOwner[request.owner] == request then
        self.byOwner[request.owner] = nil
    end
    local list = self.byKey[request.key]
    if list then
        for i = #list, 1, -1 do
            if list[i] == request then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            self.byKey[request.key] = nil
        end
    end
end

--- Cancela una petición en cola. Devuelve true si estaba pendiente.
function NavigationScheduler:cancel(request)
    if not request or request.state ~= 'queued' then
        return false
    end
    request.state = 'cancelled'
    unindex(self, request)
    self.queued = self.queued - 1
    self._stats.cancelled = self._stats.cancelled + 1
    return true
end

--- Cancela la petición pendiente de un dueño (agente).
function NavigationScheduler:cancelFor(owner)
    if owner == nil then
        return false
    end
    return self:cancel(self.byOwner[owner])
end

--- Petición pendiente de un dueño, o nil.
function NavigationScheduler:pendingFor(owner)
    return self.byOwner[owner]
end

-- Búsqueda completa (con A*), cronometrada.
local function search(self, request)
    local t0 = self.clock()
    local route, err = request.system:requestPath(request.sx, request.sy, request.tx, request.ty, request.props, {
        startProjection = request.startProjection,
        goalProjection = request.goalProjection,
    })
    local ms = (self.clock() - t0) * 1000
    local s = self._stats
    s.searches = s.searches + 1
    s.totalSearchMs = s.totalSearchMs + ms
    s.averageSearchMs = s.totalSearchMs / s.searches
    if ms > s.maxSearchMs then
        s.maxSearchMs = ms
    end
    return route, err, ms
end

-- Intento sin A*: solo si todo lo que hace falta está en la caché.
local function fromCache(request)
    return request.system:requestPath(request.sx, request.sy, request.tx, request.ty, request.props, {
        startProjection = request.startProjection,
        goalProjection = request.goalProjection,
        cacheOnly = true,
    })
end

--- Encola (o resuelve en el acto) una petición. `spec`: `system`, `sx`, `sy`,
-- `tx`, `ty`, `props`, `owner`, `priority`, `callback`, `immediate`.
-- Devuelve la petición con su `state`.
function NavigationScheduler:request(spec)
    local system = spec.system
    local props = spec.props or {}
    local request = {
        system = system,
        sx = spec.sx,
        sy = spec.sy,
        tx = spec.tx,
        ty = spec.ty,
        props = props,
        owner = spec.owner,
        priority = priorityOf(spec.priority),
        callback = spec.callback,
        state = 'queued',
        route = nil,
        err = nil,
        key = nil,
        startProjection = nil,
        goalProjection = nil,
        sequence = 0,
    }
    if spec.owner ~= nil then
        self:cancelFor(spec.owner)
    end
    if not system then
        request.state = 'failed'
        finish(self, request, nil, 'sin red')
        return request
    end
    -- 1. Proyección síncrona: fallo inmediato si no se llega a la red.
    local maxDist = NvUtil.finite(props.maxProjectDistance, system.options.maxProjectDistance)
    local ps = system:projectPoint(spec.sx, spec.sy, maxDist)
    if not ps then
        finish(self, request, nil, 'origen lejos de la red')
        return request
    end
    local pt = system:projectPoint(spec.tx, spec.ty, maxDist)
    if not pt then
        finish(self, request, nil, 'destino lejos de la red')
        return request
    end
    request.startProjection, request.goalProjection = ps, pt
    request.key = NavigationScheduler.key(system, ps.segment.id, pt.segment.id, props.class)
    -- 2. Caché antes que presupuesto.
    local route = fromCache(request)
    if route then
        self._stats.cacheHits = self._stats.cacheHits + 1
        finish(self, request, route)
        return request
    end
    self._stats.cacheMisses = self._stats.cacheMisses + 1
    -- 3. Inmediata (fuera de presupuesto) o a la cola.
    if spec.immediate then
        self._stats.immediate = self._stats.immediate + 1
        local found, err = search(self, request)
        finish(self, request, found, err)
        return request
    end
    self.sequence = self.sequence + 1
    request.sequence = self.sequence
    self.heap:push(request, request.priority * SEQUENCE_SPAN + request.sequence)
    self.queued = self.queued + 1
    if request.owner ~= nil then
        self.byOwner[request.owner] = request
    end
    local list = self.byKey[request.key]
    if not list then
        list = {}
        self.byKey[request.key] = list
    end
    list[#list + 1] = request
    return request
end

-- Resuelve una petición de la cola con búsqueda y, si salió bien, las
-- equivalentes por la caché. Devuelve los ms de la búsqueda.
local function run(self, request)
    unindex(self, request)
    self.queued = self.queued - 1
    local route, err, ms = search(self, request)
    finish(self, request, route, err)
    local siblings = self.byKey[request.key]
    if siblings then
        -- De atrás hacia delante: `unindex` quita de la lista.
        for i = #siblings, 1, -1 do
            local other = siblings[i]
            if other.state == 'queued' then
                local shared
                if route then
                    shared = fromCache(other)
                end
                if shared or not route then
                    -- Con ruta compartida se resuelve; sin ruta para la clave, la
                    -- búsqueda fallará igual (la caché guarda también los fallos).
                    unindex(self, other)
                    self.queued = self.queued - 1
                    self._stats.deduplicated = self._stats.deduplicated + 1
                    if shared then
                        finish(self, other, shared)
                    else
                        finish(self, other, nil, err)
                    end
                end
            end
        end
    end
    return ms
end

--- Procesa la cola con el presupuesto del cuadro. Devuelve cuántas
-- búsquedas hizo.
function NavigationScheduler:update()
    self.frame = self.frame + 1
    local processed, elapsedMs = 0, 0
    local heap = self.heap
    while processed < self.maxRequestsPerFrame and elapsedMs < self.maxPathfindingTimeMs do
        local request = heap:pop()
        if not request then
            break
        end
        if request.state == 'queued' then
            elapsedMs = elapsedMs + run(self, request)
            processed = processed + 1
        end
    end
    local s = self._stats
    s.processedPerFrame = processed
    s.frameSearchMs = elapsedMs
    s.queued = self.queued
    return processed
end

--- Vacía la cola cancelando todo lo pendiente.
function NavigationScheduler:clear()
    local heap = self.heap
    while not heap:empty() do
        local request = heap:pop()
        if request.state == 'queued' then
            self:cancel(request)
        end
    end
    return self
end

--- Estadísticas (tabla reutilizada): `queued`, `processedPerFrame`,
-- `cacheHits`, `cacheMisses`, `averageSearchMs`, `maxSearchMs`, `cancelled`,
-- `deduplicated`, `failed`, `searches`, `totalSearchMs`, `frameSearchMs`,
-- `immediate`.
function NavigationScheduler:stats()
    self._stats.queued = self.queued
    return self._stats
end

--- Pone a cero los acumulados (la cola no se toca).
function NavigationScheduler:resetStats()
    local s = self._stats
    s.processedPerFrame, s.cacheHits, s.cacheMisses = 0, 0, 0
    s.averageSearchMs, s.maxSearchMs, s.cancelled, s.deduplicated = 0, 0, 0, 0
    s.failed, s.searches, s.totalSearchMs, s.frameSearchMs, s.immediate = 0, 0, 0, 0, 0
    return self
end

return NavigationScheduler

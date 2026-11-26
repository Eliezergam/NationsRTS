-- Gestor de sistemas de navegación: uno por tag (`TankNavigation`,
-- `InfantryNavigation`…), con las consultas por tag y la carga/guardado.
--
--   local NavigationManager = require('runtime.nv.manager')
--   local nav = NavigationManager.new()
--   local tanks = nav:addSystem('TankNavigation')
--   nav:getSystem('TankNavigation')
--   nav:findNearestNode(x, y, 'TankNavigation')     -- sin tag: en todos los sistemas
--   local nav2 = NavigationManager.fromData(data)    -- ver runtime/nv/serializer.lua
--   local data = nav:toData({ keepRaw = false })
--
-- Servicios por cuadro (los usa `runtime/level_loader.lua`; en las pruebas
-- unitarias no hacen falta):
--
--   nav:enableScheduler({ maxRequestsPerFrame = 20, maxPathfindingTimeMs = 2 })
--                                    -- desde entonces `agent:setDestination` va programado
--   nav:beginFrame(agents)           -- procesa la cola de rutas y actualiza el índice de agentes
--   ... update de los agentes ...
--   nav:endFrame()                   -- cierra el profiler
--   nav:setProfiling(true)           -- nav.profiler.enabled
--   nav:stats()                      -- la tabla que enseña el panel NV PROFILER
--
-- `nav.agentIndex` es el `AgentSpatialHash` de los agentes móviles (se crea en
-- el primer `beginFrame`/`updateAgents`); `nav.scheduler` el planificador (nil
-- hasta `enableScheduler`); `nav.profiler` el `NvProfiler` (siempre existe,
-- apagado por defecto). `nav.bounds` ({x, y, w, h}) y `nav.blocked(x, y, r)`
-- los pone el nivel para la validación de puestos de los grupos y para los
-- flow fields.
--
-- Opciones (`NavigationManager.new(options)` / `NV.load(map, options)`):
-- `agentCellSize`; `strategy = { mediumFrom=, massiveFrom= }` (umbrales de
-- tamaño de grupo, ver `group.lua`); `flowField = { cellSize=, margin= ... }`
-- (opciones de `flow_field.lua` para los grupos masivos). Los flow fields
-- activos se registran aquí (`trackFlowField` / `untrackFlowField`) para que
-- `stats()` y el dibujo de depuración los vean.
--
-- Congestión (fase E): `nav.repathCount` cuenta TODOS los recálculos de ruta
-- (los agentes y los grupos llaman a `noteRepath`, con el profiler encendido
-- o apagado) y `nav.yieldingAgents` cuántos agentes ceden el paso ahora
-- mismo (lo mantienen `agent:beginYield` / `endYield`).
--
-- LOD de navegación (fase F, `docs/NV.md` → "LOD"):
--
--   nav:setFocus(x, y, w, h)         -- rectángulo de interés en el mundo (la cámara); nil lo quita
--   nav:setSelected(agents)          -- las seleccionadas van siempre a tope
--   nav:lodLevelOf(agent)            -- 'full' | 'reduced' | 'coarse'
--
-- En cada `beginFrame`, después del índice de agentes, `updateLod` pone a
-- cada agente un nivel según la distancia de su posición al rectángulo de
-- foco (0 dentro), con los umbrales de `options.lod` (px de mundo, nunca de
-- pantalla):
--
--   seleccionado, o d ≤ nearDistance     'full'     decide cada cuadro (lo de siempre)
--   d ≤ farDistance                      'reduced'  decide cada `reducedInterval` cuadros
--   más lejos, en marcha tranquila       'coarse'   decide cada `coarseInterval` cuadros,
--   (sin atasco, cesión ni contacto)                con `coarseMaxNeighbours` vecinos en la esquiva
--
-- "Decidir" es la parte cara del agente (reproyección sobre la ruta,
-- vecinos, esquiva, atascos, comprobaciones de repath); entre decisiones el
-- agente sigue integrando su movimiento en cada cuadro con la última
-- decisión (`agent:coast`), así que nunca salta. Qué cuadro le toca a cada
-- agente lo reparte una cubeta: decide cuando `(cuadro + serial) % intervalo
-- == 0`, así que en cualquier tramo de `intervalo` cuadros decide cada uno
-- exactamente una vez y la carga se reparte entre cuadros. Para no
-- parpadear en un borde, bajar de nivel pide `hysteresis` px más. Sin foco
-- (o con `options.lod = false`) todos van 'full': el comportamiento de
-- siempre, cuadro a cuadro.

local NvUtil = require('runtime.nv.util')
local NavigationSystem = require('runtime.nv.system')
local Serializer = require('runtime.nv.serializer')
local AgentSpatialHash = require('runtime.nv.agent_spatial_hash')
local NavigationScheduler = require('runtime.nv.scheduler')
local NvProfiler = require('runtime.nv.profiler')

local NavigationManager = NvUtil.class('NavigationManager')

NavigationManager.defaults = { agentCellSize = 64 }

--- Umbrales del LOD de navegación (`options.lod` los pisa uno a uno; ver la
-- cabecera). Distancias en px de mundo desde el borde del rectángulo de foco.
NavigationManager.lodDefaults = {
    enabled = true,
    nearDistance = 256,
    farDistance = 1024,
    hysteresis = 64,
    reducedInterval = 2,
    coarseInterval = 4,
    coarseMaxNeighbours = 6,
    coarseMinGap = 0,
}

--- Niveles de LOD por número (el agente guarda el número en `lodLevel`).
NavigationManager.LOD_FULL = 1
NavigationManager.LOD_REDUCED = 2
NavigationManager.LOD_COARSE = 3
NavigationManager.lodNames = { 'full', 'reduced', 'coarse' }

local LOD_FULL = NavigationManager.LOD_FULL
local LOD_REDUCED = NavigationManager.LOD_REDUCED
local LOD_COARSE = NavigationManager.LOD_COARSE

--- Opciones de LOD saneadas a partir de `options.lod` (`false` lo apaga).
function NavigationManager.lodOptions(raw)
    local d = NavigationManager.lodDefaults
    local out = {}
    if raw == false then
        raw = { enabled = false }
    end
    if type(raw) ~= 'table' then
        raw = {}
    end
    out.enabled = NvUtil.bool(raw.enabled, d.enabled)
    out.nearDistance = NvUtil.atLeast(raw.nearDistance, d.nearDistance, 0)
    out.farDistance = NvUtil.atLeast(raw.farDistance, d.farDistance, out.nearDistance)
    out.hysteresis = NvUtil.atLeast(raw.hysteresis, d.hysteresis, 0)
    out.reducedInterval = math.floor(NvUtil.atLeast(raw.reducedInterval, d.reducedInterval, 1))
    out.coarseInterval = math.floor(NvUtil.atLeast(raw.coarseInterval, d.coarseInterval, out.reducedInterval))
    out.coarseMaxNeighbours = math.floor(NvUtil.atLeast(raw.coarseMaxNeighbours, d.coarseMaxNeighbours, 1))
    out.coarseMinGap = NvUtil.finite(raw.coarseMinGap, d.coarseMinGap)
    return out
end

function NavigationManager:init(options)
    self.options = type(options) == 'table' and options or {}
    self.byName = {}
    self.nextSystemId = 1
    self._list = nil
    self.scheduler = nil
    self.agentIndex = nil
    self.agents = nil -- la última lista pasada a `updateAgents`
    self.profiler = NvProfiler.new()
    self.bounds = nil
    self.blocked = nil
    self.flowFields = {} -- campo → true (activos)
    self.flowFieldCount = 0
    self.lastFlowFieldBuildMs = 0
    self.repathCount = 0 -- recálculos de ruta acumulados (agentes y grupos)
    self.yieldingAgents = 0 -- agentes que ceden el paso ahora mismo
    self._stats = nil
    -- LOD (fase F, ver la cabecera).
    self.lod = NavigationManager.lodOptions(self.options.lod)
    self.focus = { x = 0, y = 0, w = 0, h = 0 }
    self.hasFocus = false
    self.lodSelected = {} -- agente → true (siempre 'full')
    self.lodFrame = 0
    self.lodActive = false -- ¿el último `updateLod` repartió niveles?
    self.lodFull, self.lodReduced, self.lodCoarse = 0, 0, 0
end

--- Anota un recálculo de ruta (lo llaman `agent:repath` y el grupo al
-- regenerar su flow field).
function NavigationManager:noteRepath(n)
    self.repathCount = self.repathCount + (n or 1)
    return self
end

--- Crea un sistema (o devuelve el que ya tiene ese nombre). `opts.id` fija el
-- id al cargar.
function NavigationManager:addSystem(name, opts)
    name = tostring(name or '')
    if name == '' then
        return nil, 'nombre vacío'
    end
    local existing = self.byName[name]
    if existing then
        return existing
    end
    opts = opts or {}
    local id = opts.id and math.floor(NvUtil.finite(opts.id, 0)) or nil
    if not id or id < 1 or self:systemById(id) then
        id = self.nextSystemId
    end
    if id >= self.nextSystemId then
        self.nextSystemId = id + 1
    end
    local options = NvUtil.shallowCopy(self.options)
    for k, v in pairs(opts) do
        if k ~= 'id' then
            options[k] = v
        end
    end
    local system = NavigationSystem.new(id, name, options)
    self.byName[name] = system
    self._list = nil
    return system
end

function NavigationManager:systemById(id)
    for _, system in pairs(self.byName) do
        if system.id == id then
            return system
        end
    end
    return nil
end

function NavigationManager:removeSystem(name)
    if not self.byName[name] then
        return false
    end
    self.byName[name] = nil
    self._list = nil
    return true
end

function NavigationManager:renameSystem(old, new)
    new = tostring(new or '')
    local system = self.byName[old]
    if not system then
        return false, 'no existe'
    end
    if new == '' then
        return false, 'nombre vacío'
    end
    if new == old then
        return true
    end
    if self.byName[new] then
        return false, 'ya existe'
    end
    self.byName[old] = nil
    system.name = new
    self.byName[new] = system
    self._list = nil
    return true
end

function NavigationManager:getSystem(tag)
    if tag == nil then
        return nil
    end
    return self.byName[tag]
end

--- Lista de sistemas ordenada por nombre (cacheada).
function NavigationManager:systems()
    if not self._list then
        local list = {}
        for _, system in pairs(self.byName) do
            list[#list + 1] = system
        end
        table.sort(list, function(a, b)
            return a.name < b.name
        end)
        self._list = list
    end
    return self._list
end

function NavigationManager:count()
    return #self:systems()
end

-- Sistemas a consultar para un tag (todos si es nil).
function NavigationManager:targets(tag)
    if tag ~= nil then
        local system = self.byName[tag]
        if system then
            return { system }
        end
        return {}
    end
    return self:systems()
end

--- Nodo más cercano: nodo, distancia, sistema.
function NavigationManager:findNearestNode(x, y, tag, maxDist)
    local best, bestD, bestSystem
    for _, system in ipairs(self:targets(tag)) do
        local node, d = system:findNearestNode(x, y, maxDist)
        if node and (not bestD or d < bestD) then
            best, bestD, bestSystem = node, d, system
        end
    end
    return best, bestD, bestSystem
end

function NavigationManager:findNodesInArea(x, y, w, h, tag)
    local out = {}
    for _, system in ipairs(self:targets(tag)) do
        for _, node in ipairs(system:findNodesInArea(x, y, w, h)) do
            out[#out + 1] = node
        end
    end
    return out
end

function NavigationManager:findSegmentsNear(x, y, r, tag)
    local out = {}
    for _, system in ipairs(self:targets(tag)) do
        for _, seg in ipairs(system:findSegmentsNear(x, y, r)) do
            out[#out + 1] = seg
        end
    end
    return out
end

--- Procesa lo sucio de todos los sistemas.
function NavigationManager:update()
    local n = 0
    for _, system in ipairs(self:systems()) do
        n = n + system:update()
    end
    return n
end

--- Suma de versiones (cambia si cambia cualquier sistema).
function NavigationManager:version()
    local v = 0
    for _, system in ipairs(self:systems()) do
        v = v + system.version
    end
    return v
end

-- Servicios por cuadro ------------------------------------------------------------

--- Crea (o devuelve) el planificador de rutas. Con él, `setDestination` de
-- los agentes de este manager queda programado por defecto.
function NavigationManager:enableScheduler(opts)
    if not self.scheduler then
        self.scheduler = NavigationScheduler.new(self, opts)
    end
    return self.scheduler
end

--- Quita el planificador (las peticiones pendientes se cancelan).
function NavigationManager:disableScheduler()
    if self.scheduler then
        self.scheduler:clear()
        self.scheduler = nil
    end
    return self
end

--- El índice espacial de agentes (se crea al primer uso).
function NavigationManager:agentHash()
    if not self.agentIndex then
        local size = NvUtil.atLeast(self.options.agentCellSize, NavigationManager.defaults.agentCellSize, 1)
        self.agentIndex = AgentSpatialHash.new(size)
    end
    return self.agentIndex
end

--- Sincroniza el índice de agentes con la lista (una vez por cuadro, antes
-- de moverlos).
function NavigationManager:updateAgents(agents)
    self.agents = agents
    local profiler = self.profiler
    local t = profiler:start()
    local moved = self:agentHash():update(agents)
    profiler:finish('agentIndex', t)
    return moved
end

--- Trabajo NV de principio de cuadro: cola de rutas, índice de agentes y
-- niveles de LOD.
function NavigationManager:beginFrame(agents)
    local profiler = self.profiler
    profiler:beginFrame()
    if self.scheduler then
        local t = profiler:start()
        self.scheduler:update()
        profiler:finish('scheduler', t)
    end
    if agents then
        self:updateAgents(agents)
        local t = profiler:start()
        self:updateLod(agents)
        profiler:finish('lod', t)
    end
    return self
end

-- LOD ------------------------------------------------------------------------------

--- Rectángulo de interés en coordenadas de mundo (normalmente
-- `camera:visibleRect()`). Admite `(x, y, w, h)` o una tabla `{x, y, w, h}`;
-- `nil` lo quita (sin foco todos van 'full'). Copia los números: no guarda
-- la tabla.
function NavigationManager:setFocus(x, y, w, h)
    if type(x) == 'table' then
        x, y, w, h = x.x, x.y, x.w, x.h
    end
    x, y, w, h = NvUtil.finite(x), NvUtil.finite(y), NvUtil.finite(w), NvUtil.finite(h)
    if not x or not y or not w or not h then
        self.hasFocus = false
        return self
    end
    local f = self.focus
    if w < 0 then
        x, w = x + w, -w
    end
    if h < 0 then
        y, h = y + h, -h
    end
    f.x, f.y, f.w, f.h = x, y, w, h
    self.hasFocus = true
    return self
end

--- El rectángulo de foco: x, y, w, h, o nil si no hay.
function NavigationManager:getFocus()
    if not self.hasFocus then
        return nil
    end
    local f = self.focus
    return f.x, f.y, f.w, f.h
end

--- Agentes seleccionados: van 'full' aunque estén lejos del foco. Sustituye
-- la selección anterior (la tabla interna se reutiliza).
function NavigationManager:setSelected(agents)
    local set = self.lodSelected
    for agent in pairs(set) do
        set[agent] = nil
    end
    if type(agents) == 'table' then
        for i = 1, #agents do
            set[agents[i]] = true
        end
    end
    return self
end

--- Nombre del nivel de LOD de un agente: 'full' | 'reduced' | 'coarse'.
function NavigationManager:lodLevelOf(agent)
    return NavigationManager.lodNames[agent and agent.lodLevel or LOD_FULL] or 'full'
end

-- ¿Puede ir 'coarse'? Solo en marcha tranquila: sin atasco, sin ceder el
-- paso, sin contraflujo, sin estar haciendo sitio y sin nadie a menos de
-- `minGap` px de superficie en su última decisión (en contacto, un agente
-- que reacciona cada 4 cuadros se mete más en los otros). Si no, 'reduced'.
local function calmForCoarse(agent, minGap)
    if agent.yieldState ~= 'none' or agent.makingWay then
        return false
    end
    local c = agent.congestion
    if c ~= nil and (c.state ~= 'moving' or c.keepRight > 0) then
        return false
    end
    local la = agent.avoidance
    return la == nil or la.nearestSurface > minGap
end

--- Reparte los niveles de LOD y las cubetas del cuadro (lo llama
-- `beginFrame`, después del índice de agentes). Solo mira a los
-- `NavigationAgent` de la lista (las tablas planas son obstáculos). También
-- deja en cada grupo de `group.lua` el intervalo más corto de sus miembros
-- (`group.lodInterval`), para escalonar su formación. Devuelve cuántos van
-- 'full', 'reduced' y 'coarse'.
function NavigationManager:updateLod(agents)
    self.lodFrame = self.lodFrame + 1
    local frame = self.lodFrame
    local lod = self.lod
    local active = lod.enabled and self.hasFocus
    local full, reduced, coarse = 0, 0, 0
    if not active then
        -- Sin LOD: todos a tope (también el que tenía un nivel de antes).
        for i = 1, #agents do
            local agent = agents[i]
            if agent.props then
                full = full + 1
                if agent.lodLevel ~= LOD_FULL or not agent.lodDecide then
                    agent.lodLevel, agent.lodInterval, agent.lodDecide = LOD_FULL, 1, true
                end
                local group = agent.navGroup
                if group and group.lodInterval ~= nil and group.lodInterval ~= 1 then
                    group.lodInterval = 1
                end
            end
        end
        self.lodActive = false
        self.lodFull, self.lodReduced, self.lodCoarse = full, 0, 0
        return full, 0, 0
    end
    self.lodActive = true
    local f = self.focus
    local x0, y0 = f.x, f.y
    local x1, y1 = x0 + f.w, y0 + f.h
    local near, far, hysteresis = lod.nearDistance, lod.farDistance, lod.hysteresis
    local reducedInterval, coarseInterval = lod.reducedInterval, lod.coarseInterval
    local coarseMinGap = lod.coarseMinGap
    local selected = self.lodSelected
    for i = 1, #agents do
        local agent = agents[i]
        if agent.props then
            local level = LOD_FULL
            if not selected[agent] then
                local t = agent.target
                local x, y = t.x, t.y
                local dx = x0 - x
                if x - x1 > dx then
                    dx = x - x1
                end
                if dx < 0 then
                    dx = 0
                end
                local dy = y0 - y
                if y - y1 > dy then
                    dy = y - y1
                end
                if dy < 0 then
                    dy = 0
                end
                local dSq = dx * dx + dy * dy
                -- Bajar de nivel pide `hysteresis` px más que subir.
                local previous = agent.lodLevel or LOD_FULL
                local nearLimit = near
                if previous == LOD_FULL then
                    nearLimit = near + hysteresis
                end
                local farLimit = far
                if previous ~= LOD_COARSE then
                    farLimit = far + hysteresis
                end
                if dSq > nearLimit * nearLimit then
                    level = LOD_REDUCED
                    if dSq > farLimit * farLimit and calmForCoarse(agent, coarseMinGap) then
                        level = LOD_COARSE
                    end
                end
            end
            local interval = 1
            if level == LOD_FULL then
                full = full + 1
            elseif level == LOD_REDUCED then
                reduced = reduced + 1
                interval = reducedInterval
            else
                coarse = coarse + 1
                interval = coarseInterval
            end
            agent.lodLevel, agent.lodInterval = level, interval
            -- Cubeta: en cada tramo de `interval` cuadros decide una vez.
            agent.lodDecide = interval <= 1 or (frame + (agent.serial or 0)) % interval == 0
            local group = agent.navGroup
            if group then
                if group.lodFrame ~= frame then
                    group.lodFrame = frame
                    group.lodInterval = interval
                elseif interval < group.lodInterval then
                    group.lodInterval = interval
                end
            end
        end
    end
    self.lodFull, self.lodReduced, self.lodCoarse = full, reduced, coarse
    return full, reduced, coarse
end

--- Cierra el cuadro del profiler.
function NavigationManager:endFrame()
    self.profiler:endFrame()
    return self
end

function NavigationManager:setProfiling(enabled)
    self.profiler:setEnabled(enabled)
    return self
end

--- Registra un flow field activo (lo hace `group.lua` al construirlo).
function NavigationManager:trackFlowField(field)
    if field and not self.flowFields[field] then
        self.flowFields[field] = true
        self.flowFieldCount = self.flowFieldCount + 1
    end
    if field then
        self.lastFlowFieldBuildMs = field.buildMs or 0
    end
    return self
end

--- Da de baja un flow field (cuando su grupo termina).
function NavigationManager:untrackFlowField(field)
    if field and self.flowFields[field] then
        self.flowFields[field] = nil
        self.flowFieldCount = self.flowFieldCount - 1
        return true
    end
    return false
end

--- Estadísticas para el panel NV PROFILER (tabla reutilizada; números, 0 si
-- no aplica): agents, moving, pendingPaths, astarRequestsPerFrame,
-- astarAverageMs, astarMaxMs, cacheHitRate (0..1), avoidanceQueries,
-- averageNeighbours, maxNeighbours, flowFields (campos activos),
-- flowFieldBuildMs (lo que tardó el último campo construido), dirtyRegions
-- (regiones jerárquicas pendientes de reconstruir), hierarchicalSearches
-- (acumuladas), cpuMs, scheduledQueued, cancelledRequests, stuckAgents,
-- repaths. Congestión: stuckAgents (en marcha con `congestion.state =
-- 'stuck'`), slowAgents, locallyBlockedAgents, repathPendingAgents,
-- yieldingAgents; repaths = `repathCount` más lo que se haya contado a mano
-- en el profiler (`profiler:count('repaths')`). LOD (fase F): lodFull,
-- lodReduced, lodCoarse (agentes en cada nivel en el último `beginFrame`) y
-- gcKilobytesPerFrame (KB de Lua que crecieron dentro de las secciones
-- medidas en el último cuadro; 0 con el profiler apagado).
function NavigationManager:stats()
    local out = self._stats
    if not out then
        out = {}
        self._stats = out
    end
    local agents = self.agents
    local total, moving, pending, stuck = 0, 0, 0, 0
    local slow, blocked, repathPending, yielding = 0, 0, 0, 0
    if agents then
        for i = 1, #agents do
            local agent = agents[i]
            local state = agent.state
            if state then
                total = total + 1
            end
            if state == 'moving' then
                moving = moving + 1
                local c = agent.congestion
                local cs = c and c.state
                if cs == 'stuck' then
                    stuck = stuck + 1
                elseif cs == 'slow' then
                    slow = slow + 1
                elseif cs == 'locallyBlocked' then
                    blocked = blocked + 1
                elseif cs == 'repathPending' then
                    repathPending = repathPending + 1
                end
                if agent.yieldState == 'yielding' then
                    yielding = yielding + 1
                end
            elseif state == 'pending' then
                pending = pending + 1
            end
        end
    end
    out.agents, out.moving, out.pendingPaths, out.stuckAgents = total, moving, pending, stuck
    out.slowAgents, out.locallyBlockedAgents = slow, blocked
    out.repathPendingAgents, out.yieldingAgents = repathPending, yielding
    local scheduler = self.scheduler
    if scheduler then
        local s = scheduler:stats()
        out.astarRequestsPerFrame = s.processedPerFrame
        out.astarAverageMs = s.averageSearchMs
        out.astarMaxMs = s.maxSearchMs
        out.scheduledQueued = s.queued
        out.cancelledRequests = s.cancelled
    else
        out.astarRequestsPerFrame, out.astarAverageMs, out.astarMaxMs = 0, 0, 0
        out.scheduledQueued, out.cancelledRequests = 0, 0
    end
    local hits, misses, dirty, hierarchical = 0, 0, 0, 0
    for _, system in ipairs(self:systems()) do
        hits, misses = hits + system.cache.hits, misses + system.cache.misses
        dirty = dirty + system:dirtyRegionCount()
        hierarchical = hierarchical + (system.hierarchicalSearches or 0)
    end
    out.cacheHitRate = (hits + misses) > 0 and hits / (hits + misses) or 0
    out.dirtyRegions = dirty
    out.hierarchicalSearches = hierarchical
    out.flowFields = self.flowFieldCount
    out.flowFieldBuildMs = self.lastFlowFieldBuildMs
    local index = self.agentIndex
    if index then
        local s = index:stats()
        out.avoidanceQueries = s.queriesPerFrame
        out.averageNeighbours = s.averageNeighbours
        out.maxNeighbours = s.maxNeighbours
    else
        out.avoidanceQueries, out.averageNeighbours, out.maxNeighbours = 0, 0, 0
    end
    out.cpuMs = self.profiler.cpuMs
    out.lodFull, out.lodReduced, out.lodCoarse = self.lodFull, self.lodReduced, self.lodCoarse
    out.gcKilobytesPerFrame = self.profiler.gcKilobytes
    out.repaths = self.repathCount + (self.profiler.counters.repaths or 0)
    return out
end

function NavigationManager:toData(opts)
    return Serializer.toData(self, opts)
end

--- Construye un gestor desde datos guardados (tolerante: nunca lanza).
function NavigationManager.fromData(data, options)
    local manager = NavigationManager.new(options)
    Serializer.fromData(data, manager)
    return manager
end

return NavigationManager

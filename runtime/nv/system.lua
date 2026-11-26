-- Un sistema de navegación (una red con nombre = tag): su grafo, sus índices
-- espaciales, la caché de rutas y la proyección de puntos sobre la red.
--
--   local NavigationSystem = require('runtime.nv.system')
--   local sys = NavigationSystem.new(id, 'TankNavigation', options)
--   sys.graph:addNode(...) / addSegment(...)     -- los índices se mantienen solos
--   local node, dist = sys:findNearestNode(x, y, maxDist)
--   local proj = sys:projectPoint(x, y, maxDist)  -- { segment=, d=, x=, y=, dist= } o nil
--   local route, err = sys:requestPath(sx, sy, tx, ty, agentProps)
--   sys:update()                                   -- reconstruye lo sucio (editor)
--
-- Índices: dos spatial hash (`nodeIndex` con cajas puntuales, `segmentIndex`
-- con las cajas de los segmentos) que el grafo avisa por su observador; no se
-- recorre el grafo al mover un nodo. `options.quadtree = true` mantiene además
-- un `Quadtree` de segmentos (opcional; para consultas de área en mapas
-- irregulares).
--
-- Proyección de destino (Destination Projection): el punto navegable más
-- cercano de la red. Se consultan los segmentos cuya caja queda a `r` o menos,
-- con `r` creciendo por múltiplos de `cellSize` hasta `maxProjectDistance`, y
-- se para en cuanto el mejor punto exacto está a menos de `r` (lo no visto
-- queda más lejos).
--
-- `requestPath`: proyecta origen y destino; si caen en el mismo segmento y el
-- sentido lo permite la ruta es directa; además prueba salir por cualquiera de
-- los dos extremos del segmento de origen y entrar por cualquiera de los dos
-- del de destino (respetando `oneWay`), busca con A* (o jerárquico) entre esos
-- nodos —con `PathCache`— y se queda con la combinación de coste mínimo:
-- coste = trozo de salida + ruta de nodos + trozo de entrada.
--
-- Plano o jerárquico (`useHierarchical`, por par de nodos):
--
--   options.hierarchical = true    siempre el buscador de portales (`hierarchical.lua`)
--   options.hierarchical = false   nunca
--   options.hierarchical = 'auto'  (por defecto) jerárquico cuando la recta origen → destino
--                                  cruza al menos `hierarchicalMinRegions` regiones de
--                                  `clusterSize` px (ruta larga), o cuando el grafo pasa de
--                                  `hierarchicalThreshold` nodos y origen y destino no
--                                  comparten región; las rutas cortas y los grafos pequeños
--                                  siguen con el A* plano, que ahí es más barato.
--
-- El resultado es el mismo (`hierarchical.lua` es exacto), pasa por la misma
-- caché y por el mismo planificador. El buscador jerárquico recibe los eventos
-- del grafo (observador de abajo) para ensuciar solo las regiones tocadas.
--
-- Opciones de `requestPath(..., opts)` para el planificador
-- (`runtime/nv/scheduler.lua`): `startProjection` y `goalProjection` (ya
-- calculadas, para no proyectar dos veces) y `cacheOnly` (construir la ruta
-- solo si ningún par de nodos necesita A*; si no, `nil, 'sin caché'`). Los
-- fallos de A* también se guardan en la caché (`NavigationSystem.NOROUTE`)
-- para que cien agentes con el mismo par de nodos no repitan cien búsquedas
-- fallidas; la versión del grafo en la clave los invalida al editar.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')
local NavigationGraph = require('runtime.nv.graph')
local SpatialHash = require('runtime.nv.spatial_hash')
local Quadtree = require('runtime.nv.quadtree')
local AStar = require('runtime.nv.astar')
local PathCache = require('runtime.nv.path_cache')
local Hierarchical = require('runtime.nv.hierarchical')
local Route = require('runtime.nv.route')

local NavigationSystem = NvUtil.class('NavigationSystem')

NavigationSystem.defaults = {
    cellSize = 256,
    maxProjectDistance = 400,
    hierarchical = 'auto',
    hierarchicalThreshold = 400,
    hierarchicalMinRegions = 4,
    clusterSize = 1024,
    cacheSize = 256,
    quadtree = false,
}

--- `'auto' | true | false` a partir de lo que venga (datos guardados incluidos).
function NavigationSystem.hierarchicalMode(value)
    if value == true then
        return true
    end
    if value == false then
        return false
    end
    return 'auto'
end

local EMPTY = {}

function NavigationSystem:init(id, name, options)
    options = type(options) == 'table' and options or EMPTY
    local d = NavigationSystem.defaults
    self.id = id
    self.name = tostring(name or ('sistema' .. tostring(id)))
    self.options = {
        cellSize = NvUtil.atLeast(options.cellSize, d.cellSize, 1),
        maxProjectDistance = NvUtil.atLeast(options.maxProjectDistance, d.maxProjectDistance, 0),
        hierarchical = NavigationSystem.hierarchicalMode(options.hierarchical),
        hierarchicalThreshold = NvUtil.atLeast(options.hierarchicalThreshold, d.hierarchicalThreshold, 1),
        hierarchicalMinRegions = NvUtil.atLeast(options.hierarchicalMinRegions, d.hierarchicalMinRegions, 1),
        clusterSize = NvUtil.atLeast(options.clusterSize, d.clusterSize, 1),
        cacheSize = NvUtil.atLeast(options.cacheSize, d.cacheSize, 1),
        quadtree = options.quadtree == true,
        rebuild = type(options.rebuild) == 'table' and options.rebuild or nil,
    }
    self.graph = NavigationGraph.new({ rebuild = self.options.rebuild })
    self.graph.observer = self
    self.nodeIndex = SpatialHash.new(self.options.cellSize)
    self.segmentIndex = SpatialHash.new(self.options.cellSize)
    self.quadtree = nil
    self.cache = PathCache.new(self.options.cacheSize)
    self.version = 0
    self.pathfinder = nil
    self._ids = {}
    self._ids2 = {}
    self.lastSearch = nil -- último resultado de A* (para el debug: nodos explorados)
    self.searches = 0 -- búsquedas de nodos (planas o jerárquicas)
    self.hierarchicalSearches = 0
end

--- Nombre = tag.
function NavigationSystem:tag()
    return self.name
end

-- Observador del grafo -----------------------------------------------------------

local POINT = { x = 0, y = 0, w = 0, h = 0 }

-- El buscador jerárquico (si ya existe) recibe cada evento para ensuciar
-- solo las regiones tocadas; se crea perezosamente, así que sin él no hay
-- nada que mantener.
local function forward(self, event, item)
    local pathfinder = self.pathfinder
    if pathfinder then
        pathfinder[event](pathfinder, item)
    end
end

function NavigationSystem:nodeAdded(node)
    POINT.x, POINT.y = node.x, node.y
    self.nodeIndex:insert(node.id, POINT)
    forward(self, 'nodeAdded', node)
    self:changed()
end

function NavigationSystem:nodeMoved(node)
    POINT.x, POINT.y = node.x, node.y
    self.nodeIndex:update(node.id, POINT)
    forward(self, 'nodeMoved', node)
    self:changed()
end

function NavigationSystem:nodeRemoved(node)
    self.nodeIndex:remove(node.id)
    forward(self, 'nodeRemoved', node)
    self:changed()
end

function NavigationSystem:segmentAdded(seg)
    -- La caja no vale hasta `rebuild`; se indexa en `segmentRebuilt`.
    forward(self, 'segmentAdded', seg)
    self:changed()
end

function NavigationSystem:segmentRebuilt(seg)
    self.segmentIndex:update(seg.id, seg.bounds)
    if self.quadtree then
        self.quadtree:update(seg.id, seg.bounds)
    end
    forward(self, 'segmentRebuilt', seg)
    self:changed()
end

function NavigationSystem:segmentRemoved(seg)
    self.segmentIndex:remove(seg.id)
    if self.quadtree then
        self.quadtree:remove(seg.id)
    end
    forward(self, 'segmentRemoved', seg)
    self:changed()
end

function NavigationSystem:changed()
    self.version = self.graph.version
    self.cache:invalidate()
end

-- Mantenimiento -------------------------------------------------------------------

--- Marca un tramo sucio (se reconstruye en `update`). Sus regiones
-- jerárquicas quedan sucias desde ya, no al reconstruir.
function NavigationSystem:markDirty(segmentId)
    local ok = self.graph:markDirty(segmentId)
    if ok then
        forward(self, 'segmentDirty', self.graph:segment(segmentId))
    end
    return ok
end

--- Regiones jerárquicas pendientes de reconstruir (0 sin buscador jerárquico).
function NavigationSystem:dirtyRegionCount()
    local pathfinder = self.pathfinder
    return pathfinder and pathfinder:dirtyRegionCount() or 0
end

--- Procesa los segmentos sucios (incremental). Devuelve cuántos reconstruyó.
function NavigationSystem:update()
    return self.graph:rebuildDirty()
end

--- Reconstruye todo: segmentos e índices (tras cargar o cambiar opciones).
function NavigationSystem:rebuild()
    self.nodeIndex:clear()
    self.segmentIndex:clear()
    if self.options.quadtree then
        local x, y, w, h = self.graph:bounds()
        self.quadtree = Quadtree.new({ x = x or 0, y = y or 0, w = w or 1024, h = h or 1024 })
    else
        self.quadtree = nil
    end
    for _, node in ipairs(self.graph:nodes()) do
        POINT.x, POINT.y = node.x, node.y
        self.nodeIndex:insert(node.id, POINT)
    end
    self.graph:rebuildAll()
    for _, seg in ipairs(self.graph:segments()) do
        self.segmentIndex:update(seg.id, seg.bounds)
        if self.quadtree then
            self.quadtree:update(seg.id, seg.bounds)
        end
    end
    self.pathfinder = nil
    self:changed()
    return self
end

-- Consultas ----------------------------------------------------------------------

--- Nodo más cercano a (x, y) a no más de `maxDist` (por defecto sin límite).
-- Devuelve nodo, distancia.
function NavigationSystem:findNearestNode(x, y, maxDist)
    local id, dist = self.nodeIndex:nearest(x, y, maxDist)
    if not id then
        return nil
    end
    return self.graph:node(id), dist
end

--- Nodos dentro del rectángulo.
function NavigationSystem:findNodesInArea(x, y, w, h, out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end
    local ids = self.nodeIndex:queryRect(x, y, w, h, self._ids)
    for i = 1, #ids do
        out[#out + 1] = self.graph:node(ids[i])
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

--- Segmentos cuya caja queda a `r` o menos del punto (candidatos; la
-- distancia exacta la da `segment:nearestPoint`).
function NavigationSystem:findSegmentsNear(x, y, r, out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end
    local ids = self.segmentIndex:queryRadius(x, y, r, self._ids)
    for i = 1, #ids do
        out[#out + 1] = self.graph:segment(ids[i])
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

--- Proyección de un punto sobre la red: `{ segment=, d=, x=, y=, dist= }` o
-- nil si no hay nada a `maxDist` (por defecto `options.maxProjectDistance`).
-- `out` opcional para reutilizar la tabla.
function NavigationSystem:projectPoint(x, y, maxDist, out)
    maxDist = NvUtil.finite(maxDist, self.options.maxProjectDistance)
    if self.segmentIndex.count == 0 then
        return nil
    end
    local step = self.options.cellSize
    local r = math.min(step, maxDist)
    local bestSeg, bestD, bestX, bestY, bestDist = nil, 0, 0, 0, math.huge
    local ids = self._ids2
    while true do
        self.segmentIndex:queryRadius(x, y, r, ids)
        for i = 1, #ids do
            local seg = self.graph:segment(ids[i])
            if seg and seg.arc then
                local px, py, dist, along = seg:nearestPoint(x, y)
                if dist < bestDist then
                    bestSeg, bestD, bestX, bestY, bestDist = seg, along, px, py, dist
                end
            end
        end
        if bestSeg and bestDist <= r then
            break
        end
        if r >= maxDist then
            break
        end
        r = math.min(maxDist, r + step)
    end
    if not bestSeg or bestDist > maxDist then
        return nil
    end
    out = out or {}
    out.segment, out.d, out.x, out.y, out.dist = bestSeg, bestD, bestX, bestY, bestDist
    return out
end

-- Búsqueda -------------------------------------------------------------------------

--- ¿Buscador jerárquico para este par de nodos? Ver la cabecera ("Plano o
-- jerárquico"). Sin ids (llamada vieja) decide solo por el tamaño del grafo.
function NavigationSystem:useHierarchical(startId, goalId)
    local mode = self.options.hierarchical
    if mode == true then
        return true
    end
    if mode == false then
        return false
    end
    local big = self.graph.nodeCount > self.options.hierarchicalThreshold
    local start, goal = self.graph:node(startId), self.graph:node(goalId)
    if not start or not goal then
        return big
    end
    local regions = self:hierarchical():regionsBetween(start.x, start.y, goal.x, goal.y)
    if regions >= self.options.hierarchicalMinRegions then
        return true
    end
    return big and regions > 1
end

--- El buscador jerárquico (se crea al primer uso, enganchado a los eventos
-- del grafo).
function NavigationSystem:hierarchical()
    if not self.pathfinder then
        self.pathfinder = Hierarchical.new(self, { clusterSize = self.options.clusterSize, attached = true })
    end
    return self.pathfinder
end

--- Marcador de "no hay ruta" guardado en la caché.
NavigationSystem.NOROUTE = { failed = true, steps = {}, nodes = {}, cost = math.huge, explored = {} }

--- Ruta de nodos entre dos ids (con caché por clase de agente y versión).
-- Devuelve el resultado de `AStar.find` o nil, motivo. Con `cacheOnly` no
-- busca: devuelve el acierto o `nil, 'sin caché'`.
function NavigationSystem:findNodePath(startId, goalId, agent, cacheOnly)
    agent = agent or EMPTY
    local useCache = agent.usePathCache ~= false
    local key = PathCache.key(self.id, startId, goalId, agent.class, self.version)
    if useCache then
        local hit
        if cacheOnly then
            hit = self.cache:peek(key)
        else
            hit = self.cache:get(key)
        end
        if hit then
            if hit.failed then
                return nil, 'sin ruta'
            end
            self.lastSearch = hit
            return hit
        end
    end
    if cacheOnly then
        return nil, 'sin caché'
    end
    local opts = { agent = agent, explored = agent.explored == true }
    local result, err
    if self:useHierarchical(startId, goalId) then
        result, err = self:hierarchical():find(startId, goalId, opts)
        self.hierarchicalSearches = self.hierarchicalSearches + 1
    else
        result, err = AStar.find(self.graph, startId, goalId, opts)
    end
    self.searches = self.searches + 1
    if not result then
        if useCache then
            self.cache:put(key, NavigationSystem.NOROUTE)
        end
        return nil, err
    end
    self.lastSearch = result
    if useCache then
        self.cache:put(key, result)
    end
    return result
end

-- Extremos por los que se puede salir de un segmento desde la distancia `d`
-- (o entrar hasta ella): lista de { node=, d= }.
local function exits(seg, out)
    out[1], out[2] = nil, nil
    local n = 0
    n = n + 1
    out[n] = { node = seg.to, d = seg.length }
    if seg:allowsReverse() then
        n = n + 1
        out[n] = { node = seg.from, d = 0 }
    end
    return out
end

local function entries(seg, out)
    out[1], out[2] = nil, nil
    local n = 0
    n = n + 1
    out[n] = { node = seg.from, d = 0 }
    if seg:allowsReverse() then
        n = n + 1
        out[n] = { node = seg.to, d = seg.length }
    end
    return out
end

--- Ruta desde (sx, sy) hasta (tx, ty) para un agente. Devuelve `Route` o nil,
-- motivo. `agent`: `maxProjectDistance`, `class`, `usePathCache` y lo que lea
-- `NavigationSegment:cost`. `opts`: `startProjection`, `goalProjection`,
-- `cacheOnly` (ver la cabecera).
function NavigationSystem:requestPath(sx, sy, tx, ty, agent, opts)
    agent = agent or EMPTY
    opts = opts or EMPTY
    local maxDist = NvUtil.finite(agent.maxProjectDistance, self.options.maxProjectDistance)
    local ps = opts.startProjection or self:projectPoint(sx, sy, maxDist)
    if not ps then
        return nil, 'origen lejos de la red'
    end
    local pt = opts.goalProjection or self:projectPoint(tx, ty, maxDist)
    if not pt then
        return nil, 'destino lejos de la red'
    end
    local cacheOnly = opts.cacheOnly == true
    local segS, segT = ps.segment, pt.segment
    local best, bestCost = nil, math.huge
    -- Directa por el mismo segmento.
    if segS == segT and (pt.d >= ps.d or segS:allowsReverse()) then
        local c = segS:partialCost(agent, math.abs(pt.d - ps.d))
        if c < bestCost then
            best, bestCost = { direct = true }, c
        end
    end
    -- Por los nodos.
    local exitList, entryList = exits(segS, {}), entries(segT, {})
    local lastErr = 'sin ruta'
    -- Se evalúan las cuatro combinaciones siempre (sin podar por el coste de
    -- salida): así la caché queda completa para ese par de tramos y cualquier
    -- agente equivalente, esté donde esté dentro del tramo, se resuelve sin A*.
    for _, ex in ipairs(exitList) do
        local exitCost = segS:partialCost(agent, math.abs(ex.d - ps.d))
        for _, en in ipairs(entryList) do
            local entryCost = segT:partialCost(agent, math.abs(pt.d - en.d))
            -- También con salida = entrada pasa por la caché: así los
            -- agentes equivalentes comparten la misma tabla de pasos.
            local result, err = self:findNodePath(ex.node, en.node, agent, cacheOnly)
            if result then
                local total = exitCost + result.cost + entryCost
                if total < bestCost then
                    best, bestCost = { exit = ex, entry = en, result = result }, total
                end
            elseif err == 'sin caché' then
                return nil, err
            else
                lastErr = err or lastErr
            end
        end
    end
    if not best then
        return nil, lastErr
    end
    local route = Route.new(self)
    route.start = { x = sx, y = sy }
    route.goal = { x = tx, y = ty }
    route.startProjection = { segment = segS, d = ps.d, x = ps.x, y = ps.y, dist = ps.dist }
    route.goalProjection = { segment = segT, d = pt.d, x = pt.x, y = pt.y, dist = pt.dist }
    route.cost = bestCost
    route:addLine(sx, sy, ps.x, ps.y)
    if best.direct then
        route:addSegmentPart(segS, ps.d, pt.d, nil, nil)
        route.nodes = {}
    else
        route:addSegmentPart(segS, ps.d, best.exit.d, nil, best.exit.node)
        for _, step in ipairs(best.result.steps) do
            route:addStep(step)
        end
        route:addSegmentPart(segT, best.entry.d, pt.d, best.entry.node, nil)
        route.steps = best.result.steps
        route.nodes = best.result.nodes
    end
    route:addLine(pt.x, pt.y, tx, ty)
    route:finish()
    return route
end

return NavigationSystem

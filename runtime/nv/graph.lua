-- Grafo de navegación: nodos y segmentos con ids estables, reconstrucción
-- incremental por segmento y un contador `version` que invalida cachés.
--
--   local NavigationGraph = require('runtime.nv.graph')
--   local g = NavigationGraph.new()
--   local a = g:addNode(0, 0); local b = g:addNode(300, 0)
--   local s = g:addSegment(a.id, b.id, { {x=0,y=0}, {x=150,y=40}, {x=300,y=0} }, { width = 96 })
--   for _, n in ipairs(g:neighbours(a.id)) do  -- { segment=, other=, reversed= }
--
-- Ids: `nextNodeId` y `nextSegmentId` solo suben; al cargar un mapa se
-- restauran y nunca se reutiliza un id borrado.
--
-- Cambios incrementales: `moveNode` no reconstruye el grafo, solo marca como
-- sucios (`dirtySegments`) los segmentos que tocan ese nodo, ajusta su primer o
-- último punto al nodo y los reconstruye (`rebuildDirty`). Con
-- `graph.deferRebuild = true` (el editor arrastrando un nodo) solo se marcan y
-- se reconstruyen cuando alguien llama a `rebuildDirty()` (por ejemplo
-- `NavigationSystem:update`).
--
-- `version` sube en cada cambio (nodo o segmento añadido, quitado, movido o
-- reconstruido). `PathCache` la incluye en su clave y el agente la compara
-- para el `autoRepath`.
--
-- `heuristicScale()` es el menor `costFactor` del grafo acotado a [0, 1]: A*
-- multiplica por él su heurística euclídea para seguir siendo admisible
-- aunque un tramo tenga `costFactor < 1` (ver `runtime/nv/astar.lua`). Se
-- recalcula perezosamente tras cada cambio.
--
-- Observador opcional (`graph.observer`), con cualquiera de: `nodeAdded(node)`,
-- `nodeMoved(node)`, `nodeRemoved(node)`, `segmentAdded(seg)`,
-- `segmentRemoved(seg)`, `segmentRebuilt(seg)`. `NavigationSystem` lo usa para
-- mantener los índices espaciales sin recorrer todo el grafo.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')
local NavigationNode = require('runtime.nv.node')
local NavigationSegment = require('runtime.nv.segment')

local NavigationGraph = NvUtil.class('NavigationGraph')

function NavigationGraph:init(opts)
    opts = opts or {}
    self.nodeById = {}
    self.segmentById = {}
    self.nodeCount, self.segmentCount = 0, 0
    self.nextNodeId = math.max(1, math.floor(NvUtil.finite(opts.nextNodeId, 1)))
    self.nextSegmentId = math.max(1, math.floor(NvUtil.finite(opts.nextSegmentId, 1)))
    self.version = 0
    self.dirtySegments = {}
    self.deferRebuild = false
    self.rebuildOptions = type(opts.rebuild) == 'table' and opts.rebuild or {}
    self.observer = nil
    self._nodeList, self._segmentList = nil, nil
    self._scratch = {}
end

local function notify(self, event, item)
    local observer = self.observer
    local fn = observer and observer[event]
    if fn then
        fn(observer, item)
    end
end

function NavigationGraph:touch()
    self.version = self.version + 1
    self._nodeList, self._segmentList = nil, nil
    self._heuristicScale = nil
end

--- Escala de la heurística de A*: `min(1, menor costFactor del grafo)`. Con
-- todos los factores ≥ 1 vale 1 (heurística euclídea pura); con un tramo a
-- 0,5 vale 0,5, para que ningún camino real cueste menos de lo que la
-- heurística promete. Cacheada hasta el siguiente cambio.
function NavigationGraph:heuristicScale()
    local scale = self._heuristicScale
    if scale then
        return scale
    end
    scale = 1
    for _, seg in pairs(self.segmentById) do
        if seg.costFactor < scale then
            scale = seg.costFactor
        end
    end
    if scale < 0 then
        scale = 0
    end
    self._heuristicScale = scale
    return scale
end

-- Nodos ------------------------------------------------------------------------

--- Añade un nodo. `id` es opcional (al cargar); si se da, `nextNodeId` avanza
-- por encima de él.
function NavigationGraph:addNode(x, y, id, metadata)
    id = id and math.floor(NvUtil.finite(id, 0)) or nil
    if not id or id < 1 or self.nodeById[id] then
        id = self.nextNodeId
    end
    if id >= self.nextNodeId then
        self.nextNodeId = id + 1
    end
    local node = NavigationNode.new(id, x, y, metadata)
    self.nodeById[id] = node
    self.nodeCount = self.nodeCount + 1
    self:touch()
    notify(self, 'nodeAdded', node)
    return node
end

function NavigationGraph:node(id)
    return self.nodeById[id]
end

--- Lista de nodos ordenada por id (se cachea hasta el siguiente cambio).
function NavigationGraph:nodes()
    if not self._nodeList then
        local list = {}
        for _, node in pairs(self.nodeById) do
            list[#list + 1] = node
        end
        table.sort(list, function(a, b)
            return a.id < b.id
        end)
        self._nodeList = list
    end
    return self._nodeList
end

--- Quita un nodo y todos sus segmentos.
function NavigationGraph:removeNode(id)
    local node = self.nodeById[id]
    if not node then
        return false
    end
    for i = #node.connections, 1, -1 do
        self:removeSegment(node.connections[i])
    end
    self.nodeById[id] = nil
    self.nodeCount = self.nodeCount - 1
    self:touch()
    notify(self, 'nodeRemoved', node)
    return true
end

--- Mueve un nodo: los segmentos que lo tocan quedan sucios con su extremo
-- ajustado, y se reconstruyen salvo con `deferRebuild`.
function NavigationGraph:moveNode(id, x, y)
    local node = self.nodeById[id]
    if not node then
        return false
    end
    x, y = NvUtil.finite(x, node.x), NvUtil.finite(y, node.y)
    if math.abs(x - node.x) <= V.EPSILON and math.abs(y - node.y) <= V.EPSILON then
        return true
    end
    node.x, node.y = x, y
    for _, segmentId in ipairs(node.connections) do
        local seg = self.segmentById[segmentId]
        if seg then
            self:snapEndpoints(seg)
            self:markDirty(segmentId)
        end
    end
    self:touch()
    notify(self, 'nodeMoved', node)
    if not self.deferRebuild then
        self:rebuildDirty()
    end
    return true
end

-- Segmentos --------------------------------------------------------------------

-- Ajusta el primer y último punto a las posiciones de sus nodos.
function NavigationGraph:snapEndpoints(seg)
    local from, to = self.nodeById[seg.from], self.nodeById[seg.to]
    local pts = seg.points
    if #pts == 0 then
        if from then
            pts[1] = { x = from.x, y = from.y }
        end
        if to then
            pts[#pts + 1] = { x = to.x, y = to.y }
        end
        return
    end
    if #pts == 1 and from and to then
        pts[2] = { x = to.x, y = to.y }
    end
    if from then
        pts[1].x, pts[1].y = from.x, from.y
    end
    if to then
        pts[#pts].x, pts[#pts].y = to.x, to.y
    end
end

--- Añade un segmento de `fromId` a `toId`. `points` incluye los extremos (si
-- el primero/último no coincide con el nodo, se ajusta). `props` como en
-- `NavigationSegment.new`, más `id` opcional (al cargar).
function NavigationGraph:addSegment(fromId, toId, points, props)
    local from, to = self.nodeById[fromId], self.nodeById[toId]
    if not from or not to then
        return nil, 'nodo inexistente'
    end
    props = props or {}
    local id = props.id and math.floor(NvUtil.finite(props.id, 0)) or nil
    if not id or id < 1 or self.segmentById[id] then
        id = self.nextSegmentId
    end
    if id >= self.nextSegmentId then
        self.nextSegmentId = id + 1
    end
    local seg = NavigationSegment.new(id, fromId, toId, points, props)
    self:snapEndpoints(seg)
    self.segmentById[id] = seg
    self.segmentCount = self.segmentCount + 1
    from:connect(id)
    to:connect(id)
    self:markDirty(id)
    self:touch()
    notify(self, 'segmentAdded', seg)
    if not self.deferRebuild then
        self:rebuildDirty()
    end
    return seg
end

function NavigationGraph:segment(id)
    return self.segmentById[id]
end

--- Lista de segmentos ordenada por id (cacheada).
function NavigationGraph:segments()
    if not self._segmentList then
        local list = {}
        for _, seg in pairs(self.segmentById) do
            list[#list + 1] = seg
        end
        table.sort(list, function(a, b)
            return a.id < b.id
        end)
        self._segmentList = list
    end
    return self._segmentList
end

--- Quita un segmento sin tocar los demás ni sus nodos.
function NavigationGraph:removeSegment(id)
    local seg = self.segmentById[id]
    if not seg then
        return false
    end
    local from, to = self.nodeById[seg.from], self.nodeById[seg.to]
    if from then
        from:disconnect(id)
    end
    if to then
        to:disconnect(id)
    end
    self.segmentById[id] = nil
    self.dirtySegments[id] = nil
    self.segmentCount = self.segmentCount - 1
    self:touch()
    notify(self, 'segmentRemoved', seg)
    return true
end

--- Cambia propiedades editables de un segmento (`width`, `oneWay`,
-- `speedLimit`, `costFactor`, `metadata`, `points`) y lo marca sucio.
function NavigationGraph:updateSegment(id, props)
    local seg = self.segmentById[id]
    if not seg or type(props) ~= 'table' then
        return false
    end
    local d = NavigationSegment.defaults
    if props.width ~= nil then
        seg.width = NvUtil.atLeast(props.width, d.width, 0)
    end
    if props.oneWay ~= nil then
        seg.oneWay = props.oneWay == 'forward' and 'forward' or false
    end
    if props.speedLimit ~= nil then
        seg.speedLimit = NvUtil.atLeast(props.speedLimit, d.speedLimit, 0)
    end
    if props.costFactor ~= nil then
        seg.costFactor = NvUtil.atLeast(props.costFactor, d.costFactor, 0)
    end
    if type(props.metadata) == 'table' then
        seg.metadata = props.metadata
    end
    if props.points ~= nil then
        seg.points = NvUtil.copyPoints(props.points)
        self:snapEndpoints(seg)
    end
    if props.rawPoints ~= nil then
        seg.rawPoints = NvUtil.copyPoints(props.rawPoints)
    end
    self:markDirty(id)
    self:touch()
    if not self.deferRebuild then
        self:rebuildDirty()
    end
    return true
end

-- Sucios -------------------------------------------------------------------------

function NavigationGraph:markDirty(segmentId)
    local seg = self.segmentById[segmentId]
    if not seg then
        return false
    end
    seg.dirty = true
    self.dirtySegments[segmentId] = true
    return true
end

--- Reconstruye solo los segmentos sucios. Devuelve cuántos.
function NavigationGraph:rebuildDirty()
    local count = 0
    -- Orden estable para que las pruebas y los índices sean reproducibles.
    local ids = {}
    for id in pairs(self.dirtySegments) do
        ids[#ids + 1] = id
    end
    if #ids == 0 then
        return 0
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local seg = self.segmentById[id]
        self.dirtySegments[id] = nil
        if seg then
            seg:rebuild(self.rebuildOptions)
            count = count + 1
            notify(self, 'segmentRebuilt', seg)
        end
    end
    if count > 0 then
        self:touch()
    end
    return count
end

--- Marca todo sucio y lo reconstruye (cambio de opciones o carga).
function NavigationGraph:rebuildAll()
    for id in pairs(self.segmentById) do
        self:markDirty(id)
    end
    return self:rebuildDirty()
end

function NavigationGraph:hasDirty()
    return next(self.dirtySegments) ~= nil
end

-- Vecinos ------------------------------------------------------------------------

--- Vecinos de un nodo respetando `oneWay`: lista de `{ segment=, other=,
-- reversed= }`. La lista se REUTILIZA entre llamadas (salvo que se pase
-- `out`): el que la recibe tiene que consumirla antes de volver a llamar.
function NavigationGraph:neighbours(nodeId, out)
    out = out or self._scratch
    local n = 0
    local node = self.nodeById[nodeId]
    if node then
        for _, segmentId in ipairs(node.connections) do
            local seg = self.segmentById[segmentId]
            if seg then
                local reversed = seg.to == nodeId and seg.from ~= nodeId
                if seg.from == nodeId or seg:allowsReverse() then
                    n = n + 1
                    local entry = out[n]
                    if not entry then
                        entry = {}
                        out[n] = entry
                    end
                    entry.segment, entry.other, entry.reversed = seg, seg:otherEnd(nodeId), reversed
                end
            end
        end
    end
    for i = #out, n + 1, -1 do
        out[i] = nil
    end
    return out
end

--- Caja envolvente de todos los nodos (x, y, w, h) o nil si no hay.
function NavigationGraph:bounds()
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, node in pairs(self.nodeById) do
        if node.x < minX then
            minX = node.x
        end
        if node.x > maxX then
            maxX = node.x
        end
        if node.y < minY then
            minY = node.y
        end
        if node.y > maxY then
            maxY = node.y
        end
    end
    for _, seg in pairs(self.segmentById) do
        local b = seg.bounds
        if b.x < minX then
            minX = b.x
        end
        if b.x + b.w > maxX then
            maxX = b.x + b.w
        end
        if b.y < minY then
            minY = b.y
        end
        if b.y + b.h > maxY then
            maxY = b.y + b.h
        end
    end
    if minX == math.huge then
        return nil
    end
    return minX, minY, maxX - minX, maxY - minY
end

return NavigationGraph

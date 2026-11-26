-- Búsqueda jerárquica v2 (HPA* con portales): los nodos se agrupan en
-- regiones (celdas de `clusterSize` px) y cada región conoce sus PORTALES: los
-- nodos con algún tramo cuyo otro extremo cae en otra región. Entre los
-- portales de una misma región se precalculan los costes (y los pasos) con
-- un Dijkstra local que no sale de la región; los tramos que cruzan de una
-- región a otra son las aristas del grafo abstracto.
--
--   local Hierarchical = require('runtime.nv.hierarchical')
--   local hp = Hierarchical.new(system, { clusterSize = 1024 })
--   local path, err = hp:find(startId, goalId, opts)     -- mismo resultado que AStar.find
--   hp.regions[key].portals                              -- ids de los portales de esa región
--   hp:dirtyRegionCount()                                -- regiones pendientes de reconstruir
--
-- Búsqueda (`find`):
--
--   origen ──Dijkstra local──▶ portales de su región
--          ──grafo abstracto (portal → portal dentro de la región, precalculado;
--                            portal → portal entre regiones, el tramo que cruza)──▶
--          portales de la región destino ──Dijkstra local inverso──▶ destino
--
-- El resultado es EXACTO (coincide con el A* plano): cualquier camino óptimo
-- se descompone en trozos entre cruces consecutivos, y cada trozo vive
-- entero dentro de una región entre dos de sus portales (o el origen/destino),
-- así que el coste precalculado de ese par nunca es mayor que el del trozo. Si
-- origen y destino comparten región también se prueba el camino local
-- directo, y el camino que sale y vuelve a entrar queda cubierto por los
-- portales. Con `opts.cost` u `opts.heuristic` a mano se delega en el A* plano
-- (las tablas precalculadas asumen el modelo de coste de `segment:cost`).
--
-- Costes por clase de agente: `segment:cost(agent)` depende de la clase
-- (`classCost`, ancho, velocidad), igual que la clave de `PathCache`, así que
-- cada región guarda una capa (`layers[clase]`) de costes portal → portal,
-- calculada la primera vez que una búsqueda de esa clase pasa por la región.
--
-- Regiones sucias: el `NavigationSystem` reenvía los eventos del grafo
-- (`nodeAdded`, `nodeMoved`, `nodeRemoved`, `segmentAdded`, `segmentRebuilt`,
-- `segmentRemoved` y `segmentDirty` desde `system:markDirty`). Un tramo
-- editado marca sucias solo las regiones de sus dos extremos; el siguiente
-- `build()` (al buscar, o al dibujar) recalcula los portales y los cruces de
-- esas regiones y tira sus capas, y nada más. Sin sistema detrás (`attached =
-- false`, como en las pruebas con un grafo suelto) `build()` reconstruye todo
-- cuando cambia `graph.version`.
--
-- Cuándo se usa: lo decide `NavigationSystem:useHierarchical` con
-- `options.hierarchical = 'auto' | true | false`, `hierarchicalThreshold` y
-- `hierarchicalMinRegions` (ver `system.lua`). La búsqueda pasa por la misma
-- `PathCache` y el mismo planificador que el A* plano.

local NvUtil = require('runtime.nv.util')
local AStar = require('runtime.nv.astar')
local Heap = require('runtime.nv.heap')

local Hierarchical = NvUtil.class('HierarchicalPathfinder')

Hierarchical.defaults = { clusterSize = 1024 }

local EMPTY = {}

function Hierarchical:init(system, opts)
    opts = opts or {}
    self.system = system
    self.graph = system.graph
    self.clusterSize = NvUtil.atLeast(opts.clusterSize, Hierarchical.defaults.clusterSize, 1)
    -- Con `attached` el sistema reenvía los eventos del grafo y `build` solo
    -- toca las regiones sucias; sin él se reconstruye todo al cambiar la versión.
    self.attached = opts.attached == true
    self.builtVersion = nil
    self.regionOf = {} -- nodeId → clave de región
    self.regions = {} -- clave → región (ver `newRegion`)
    self.regionList = {} -- regiones ordenadas por clave (reproducible)
    self.dirty = {} -- clave → true: pendientes de reconstruir
    self.dirtyCount = 0
    self.searches = 0
    self.rebuilds = 0 -- regiones reconstruidas (acumulado)
    self.lastRebuilt = 0 -- regiones reconstruidas en el último `build`
    self.portalCount = 0
    self._scratch = {} -- vecinos (buffer propio: el del grafo lo usa el Dijkstra local)
end

--- Clave de la región de un punto (y sus índices de celda).
function Hierarchical:regionKey(x, y)
    local size = self.clusterSize
    local cx, cy = math.floor(x / size), math.floor(y / size)
    return cx .. ',' .. cy, cx, cy
end

--- Regiones que como mínimo cruza la recta entre dos puntos (distancia de
-- Chebyshev entre sus celdas más una): 1 si comparten región.
function Hierarchical:regionsBetween(x1, y1, x2, y2)
    local _, ax, ay = self:regionKey(x1, y1)
    local _, bx, by = self:regionKey(x2, y2)
    return math.max(math.abs(ax - bx), math.abs(ay - by)) + 1
end

-- Regiones ---------------------------------------------------------------------------

local function newRegion(self, key, cx, cy)
    local size = self.clusterSize
    local region = {
        key = key,
        cx = cx,
        cy = cy,
        x = (cx + 0.5) * size,
        y = (cy + 0.5) * size,
        nodes = {}, -- id → true
        nodeCount = 0,
        portals = {}, -- ids ordenados
        portalSet = {}, -- id → true
        crossings = {}, -- portal → lista de { other=, segment=, step = { segment=, reversed= } }
        links = {}, -- clave de región vecina → coste mínimo del cruce (longitud)
        layers = {}, -- clase → { [portal] = { [portal] = { cost=, steps= } } }
        rebuilds = 0,
        dirty = true,
    }
    self.regions[key] = region
    self.regionList[#self.regionList + 1] = region
    table.sort(self.regionList, function(p, q)
        return p.key < q.key
    end)
    return region
end

local function dropRegion(self, region)
    self.regions[region.key] = nil
    for i = #self.regionList, 1, -1 do
        if self.regionList[i] == region then
            table.remove(self.regionList, i)
        end
    end
    if self.dirty[region.key] then
        self.dirty[region.key] = nil
        self.dirtyCount = self.dirtyCount - 1
    end
end

--- Marca sucia una región (por clave). Devuelve true si no lo estaba ya.
function Hierarchical:markRegionDirty(key)
    local region = key and self.regions[key]
    if not region or self.dirty[key] then
        return false
    end
    self.dirty[key] = true
    self.dirtyCount = self.dirtyCount + 1
    region.dirty = true
    return true
end

function Hierarchical:dirtyRegionCount()
    return self.dirtyCount
end

-- Mete un nodo en su región (creándola si hace falta) y la marca sucia.
local function assignNode(self, node)
    local key, cx, cy = self:regionKey(node.x, node.y)
    local region = self.regions[key] or newRegion(self, key, cx, cy)
    if not region.nodes[node.id] then
        region.nodes[node.id] = true
        region.nodeCount = region.nodeCount + 1
    end
    self.regionOf[node.id] = key
    self:markRegionDirty(key)
    return region
end

-- Saca un nodo de su región; una región vacía desaparece.
local function unassignNode(self, nodeId)
    local key = self.regionOf[nodeId]
    local region = key and self.regions[key]
    self.regionOf[nodeId] = nil
    if not region then
        return
    end
    if region.nodes[nodeId] then
        region.nodes[nodeId] = nil
        region.nodeCount = region.nodeCount - 1
    end
    if region.nodeCount <= 0 then
        dropRegion(self, region)
    else
        self:markRegionDirty(key)
    end
end

-- Eventos del grafo (los reenvía NavigationSystem) ------------------------------------

function Hierarchical:nodeAdded(node)
    if not self.builtVersion then
        return
    end
    assignNode(self, node)
end

function Hierarchical:nodeRemoved(node)
    if not self.builtVersion then
        return
    end
    unassignNode(self, node.id)
end

--- Un nodo movido puede cambiar de región; sus vecinos pueden dejar de ser
-- (o pasar a ser) portales, así que sus regiones también quedan sucias.
function Hierarchical:nodeMoved(node)
    if not self.builtVersion then
        return
    end
    local key = self:regionKey(node.x, node.y)
    local old = self.regionOf[node.id]
    if old ~= key then
        unassignNode(self, node.id)
        assignNode(self, node)
    else
        self:markRegionDirty(key)
    end
    local graph = self.graph
    for _, segmentId in ipairs(node.connections) do
        local seg = graph:segment(segmentId)
        if seg then
            self:markRegionDirty(self.regionOf[seg:otherEnd(node.id)])
        end
    end
end

--- Cualquier cambio de un tramo ensucia las regiones de sus dos extremos:
-- ahí viven sus portales, sus cruces y los costes locales que lo usan.
function Hierarchical:segmentChanged(seg)
    if not self.builtVersion then
        return
    end
    self:markRegionDirty(self.regionOf[seg.from])
    self:markRegionDirty(self.regionOf[seg.to])
end

Hierarchical.segmentAdded = Hierarchical.segmentChanged
Hierarchical.segmentRebuilt = Hierarchical.segmentChanged
Hierarchical.segmentRemoved = Hierarchical.segmentChanged
Hierarchical.segmentDirty = Hierarchical.segmentChanged

-- Reconstrucción -----------------------------------------------------------------------

-- Recalcula portales, cruces y enlaces de una región y tira sus capas.
local function rebuildRegion(self, region)
    local graph = self.graph
    local regionOf = self.regionOf
    local key = region.key
    local portals, portalSet, crossings, links = {}, {}, {}, {}
    for id in pairs(region.nodes) do
        local node = graph:node(id)
        if node then
            local isPortal = false
            for _, segmentId in ipairs(node.connections) do
                local seg = graph:segment(segmentId)
                if seg then
                    local other = seg:otherEnd(id)
                    local otherKey = regionOf[other]
                    if otherKey and otherKey ~= key then
                        isPortal = true
                    end
                end
            end
            if isPortal then
                portals[#portals + 1] = id
                portalSet[id] = true
                -- Cruces salientes (respetan `oneWay`): las aristas del grafo abstracto.
                local list = {}
                local edges = graph:neighbours(id, self._scratch)
                for i = 1, #edges do
                    local edge = edges[i]
                    local otherKey = regionOf[edge.other]
                    if otherKey and otherKey ~= key then
                        list[#list + 1] = {
                            other = edge.other,
                            segment = edge.segment,
                            step = { segment = edge.segment, reversed = edge.reversed },
                        }
                        local c = edge.segment.length
                        links[otherKey] = math.min(links[otherKey] or math.huge, c)
                    end
                end
                crossings[id] = list
            end
        end
    end
    table.sort(portals)
    region.portals, region.portalSet, region.crossings, region.links = portals, portalSet, crossings, links
    region.layers = {}
    region.rebuilds = region.rebuilds + 1
    region.dirty = false
    self.rebuilds = self.rebuilds + 1
end

-- Todo desde cero: regiones, nodos y portales.
local function rebuildAll(self)
    self.regionOf, self.regions, self.regionList = {}, {}, {}
    self.dirty, self.dirtyCount = {}, 0
    for _, node in ipairs(self.graph:nodes()) do
        assignNode(self, node)
    end
    local n = 0
    for _, region in ipairs(self.regionList) do
        rebuildRegion(self, region)
        n = n + 1
    end
    self.dirty, self.dirtyCount = {}, 0
    self.lastRebuilt = n
end

--- Pone al día el grafo de regiones: todo la primera vez (o cuando cambia la
-- versión sin estar `attached`); después, solo las regiones sucias. Devuelve
-- true si reconstruyó algo.
function Hierarchical:build()
    local graph = self.graph
    if not self.builtVersion or (not self.attached and self.builtVersion ~= graph.version) then
        rebuildAll(self)
        self.builtVersion = graph.version
        self:countPortals()
        return true
    end
    self.builtVersion = graph.version
    if self.dirtyCount == 0 then
        self.lastRebuilt = 0
        return false
    end
    local keys = {}
    for key in pairs(self.dirty) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local n = 0
    for _, key in ipairs(keys) do
        local region = self.regions[key]
        if region then
            rebuildRegion(self, region)
            n = n + 1
        end
    end
    self.dirty, self.dirtyCount = {}, 0
    self.lastRebuilt = n
    self:countPortals()
    return true
end

function Hierarchical:countPortals()
    local n = 0
    for _, region in ipairs(self.regionList) do
        n = n + #region.portals
    end
    self.portalCount = n
    return n
end

-- Dijkstra local ------------------------------------------------------------------------

-- Dijkstra dentro de una región desde `sourceId` hasta los nodos de `targets`
-- (conjunto id → true; puede incluir `extra`). Solo pisa nodos de la región.
-- Devuelve { [target] = { cost=, steps= } } para los alcanzados (sin el propio
-- origen). Los pasos van en el sentido de recorrido, como en `AStar.find`.
local function localDijkstra(self, sourceId, region, agent, targets, extra)
    local graph = self.graph
    local nodes = region.nodes
    local open = Heap.new()
    local g = { [sourceId] = 0 }
    local cameFrom, cameBy, closed = {}, {}, {}
    local wanted = 0
    for id in pairs(targets) do
        if id ~= sourceId then
            wanted = wanted + 1
        end
    end
    if extra and extra ~= sourceId and not targets[extra] then
        wanted = wanted + 1
    end
    open:push(sourceId, 0)
    local settled = 0
    while wanted > 0 and not open:empty() do
        local current, cost = open:pop()
        if not closed[current] and cost <= g[current] then
            closed[current] = true
            if current ~= sourceId and (targets[current] or current == extra) then
                settled = settled + 1
                wanted = wanted - 1
            end
            local edges = graph:neighbours(current)
            for i = 1, #edges do
                local edge = edges[i]
                local other = edge.other
                if other and not closed[other] and (nodes[other] or other == extra) then
                    local c = edge.segment:cost(agent)
                    if c ~= math.huge and c >= 0 then
                        local tentative = cost + c
                        if not g[other] or tentative < g[other] then
                            g[other] = tentative
                            cameFrom[other] = current
                            cameBy[other] = edge.segment
                            open:push(other, tentative)
                        end
                    end
                end
            end
        end
    end
    local out = {}
    if settled == 0 then
        return out
    end
    for id in pairs(targets) do
        if id ~= sourceId and closed[id] then
            local steps = {}
            local at = id
            while at ~= sourceId do
                local prev = cameFrom[at]
                local seg = cameBy[at]
                table.insert(steps, 1, { segment = seg, reversed = seg.to == prev and seg.from ~= prev })
                at = prev
            end
            out[id] = { cost = g[id], steps = steps }
        end
    end
    if extra and extra ~= sourceId and not targets[extra] and closed[extra] then
        local steps = {}
        local at = extra
        while at ~= sourceId do
            local prev = cameFrom[at]
            local seg = cameBy[at]
            table.insert(steps, 1, { segment = seg, reversed = seg.to == prev and seg.from ~= prev })
            at = prev
        end
        out[extra] = { cost = g[extra], steps = steps }
    end
    return out
end

-- Dijkstra INVERSO dentro de una región: desde `goalId` hacia atrás por las
-- aristas que ENTRAN en cada nodo (un tramo `m → n` vale de `from` a `to`, y
-- de `to` a `from` si admite el sentido contrario). Devuelve, para cada
-- portal alcanzado, el coste y los pasos de ese portal HASTA el destino.
local function localDijkstraReverse(self, goalId, region, agent, targets)
    local graph = self.graph
    local nodes = region.nodes
    local open = Heap.new()
    local g = { [goalId] = 0 }
    local nextOf, viaSeg, closed = {}, {}, {}
    local wanted = 0
    for id in pairs(targets) do
        if id ~= goalId then
            wanted = wanted + 1
        end
    end
    open:push(goalId, 0)
    while wanted > 0 and not open:empty() do
        local current, cost = open:pop()
        if not closed[current] and cost <= g[current] then
            closed[current] = true
            if current ~= goalId and targets[current] then
                wanted = wanted - 1
            end
            local node = graph:node(current)
            for _, segmentId in ipairs(node and node.connections or EMPTY) do
                local seg = graph:segment(segmentId)
                if seg and seg.from ~= seg.to then
                    local m = nil
                    if seg.to == current then
                        m = seg.from -- de from a to: siempre
                    elseif seg.from == current and seg:allowsReverse() then
                        m = seg.to -- de to a from: solo en doble sentido
                    end
                    if m and not closed[m] and nodes[m] then
                        local c = seg:cost(agent)
                        if c ~= math.huge and c >= 0 then
                            local tentative = cost + c
                            if not g[m] or tentative < g[m] then
                                g[m] = tentative
                                nextOf[m] = current
                                viaSeg[m] = seg
                                open:push(m, tentative)
                            end
                        end
                    end
                end
            end
        end
    end
    local out = {}
    for id in pairs(targets) do
        if closed[id] then
            local steps = {}
            local at = id
            while at ~= goalId do
                local seg = viaSeg[at]
                steps[#steps + 1] = { segment = seg, reversed = seg.to == at and seg.from ~= at }
                at = nextOf[at]
            end
            out[id] = { cost = g[id], steps = steps }
        end
    end
    return out
end

-- Capa de costes portal → portal de una región para una clase de agente
-- (perezosa: se calcula la primera vez y vive hasta que la región se ensucia).
local function layerFor(self, region, agent)
    local key = tostring(agent.class or '*')
    local layer = region.layers[key]
    if layer then
        return layer
    end
    layer = {}
    for _, p in ipairs(region.portals) do
        layer[p] = localDijkstra(self, p, region, agent, region.portalSet)
    end
    region.layers[key] = layer
    return layer
end

-- Búsqueda ---------------------------------------------------------------------------------

local function euclid(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Igual que `AStar.find` (mismo resultado: `nodes`, `steps`, `cost`,
-- `explored`), por el grafo de portales. `explored` son los nodos abstractos
-- cerrados (portales, origen y destino) cuando `opts.explored`.
function Hierarchical:find(startId, goalId, opts)
    opts = opts or EMPTY
    self:build()
    local graph = self.graph
    local start, goal = graph:node(startId), graph:node(goalId)
    if not start or not goal or opts.cost or opts.heuristic then
        return AStar.find(graph, startId, goalId, opts)
    end
    self.searches = self.searches + 1
    if startId == goalId then
        return { nodes = { startId }, steps = {}, cost = 0, explored = {} }
    end
    local regionOf, regions = self.regionOf, self.regions
    local rs, rg = regionOf[startId], regionOf[goalId]
    local regionS, regionG = regions[rs], regions[rg]
    if not regionS or not regionG then
        return AStar.find(graph, startId, goalId, opts)
    end
    local agent = opts.agent or EMPTY
    -- 1. Salida: del origen a los portales de su región (y al destino si comparten región).
    local fromStart = localDijkstra(self, startId, regionS, agent, regionS.portalSet, rs == rg and goalId or nil)
    -- 2. Entrada: de los portales de la región destino al destino.
    local toGoal = localDijkstraReverse(self, goalId, regionG, agent, regionG.portalSet)
    -- 3. A* sobre el grafo abstracto. La heurística euclídea escalada sigue
    -- siendo admisible: cada arista abstracta es un camino real.
    local scale = graph.heuristicScale and graph:heuristicScale() or 1
    local open = Heap.new()
    local g = { [startId] = 0 }
    local cameFrom, cameSteps, closed = {}, {}, {}
    local explored = opts.explored and {} or nil
    open:push(startId, euclid(start, goal) * scale)
    local found = false
    local function relax(current, other, cost, steps)
        if cost == math.huge or closed[other] then
            return
        end
        local tentative = g[current] + cost
        if not g[other] or tentative < g[other] then
            g[other] = tentative
            cameFrom[other] = current
            cameSteps[other] = steps
            open:push(other, tentative + euclid(graph:node(other), goal) * scale)
        end
    end
    while not open:empty() do
        local current = open:pop()
        if not closed[current] then
            closed[current] = true
            if explored then
                explored[#explored + 1] = current
            end
            if current == goalId then
                found = true
                break
            end
            if current == startId then
                for id, entry in pairs(fromStart) do
                    relax(current, id, entry.cost, entry.steps)
                end
            end
            local key = regionOf[current]
            local region = regions[key]
            if region and region.portalSet[current] then
                local layer = layerFor(self, region, agent)
                for q, entry in pairs(layer[current] or EMPTY) do
                    relax(current, q, entry.cost, entry.steps)
                end
                local crossings = region.crossings[current] or EMPTY
                for i = 1, #crossings do
                    local cross = crossings[i]
                    relax(current, cross.other, cross.segment:cost(agent), cross.step)
                end
                if key == rg and toGoal[current] then
                    relax(current, goalId, toGoal[current].cost, toGoal[current].steps)
                end
            end
        end
    end
    if not found then
        return nil, 'sin ruta'
    end
    -- Reconstrucción: concatenar los pasos de cada arista abstracta.
    local chain = {}
    local id = goalId
    while id ~= startId do
        table.insert(chain, 1, cameSteps[id])
        id = cameFrom[id]
    end
    local steps, nodes, corridor = {}, { startId }, {}
    local at = startId
    corridor[regionOf[startId]] = true
    for _, piece in ipairs(chain) do
        if piece.segment then
            -- Un cruce: un solo paso.
            steps[#steps + 1] = piece
            at = piece.segment:otherEnd(at)
            nodes[#nodes + 1] = at
            corridor[regionOf[at]] = true
        else
            for i = 1, #piece do
                local step = piece[i]
                steps[#steps + 1] = step
                at = step.segment:otherEnd(at)
                nodes[#nodes + 1] = at
                corridor[regionOf[at]] = true
            end
        end
    end
    return { nodes = nodes, steps = steps, cost = g[goalId], explored = explored or {}, corridor = corridor }
end

--- A* solo sobre regiones (por `links`): el conjunto de claves de un corredor
-- de regiones, o nil. Se conserva para depurar y para quien quiera un
-- corredor grueso sin la búsqueda completa.
function Hierarchical:regionPath(fromKey, toKey)
    self:build()
    local corridor = {}
    if fromKey == toKey then
        corridor[fromKey] = true
        return corridor
    end
    local regions = self.regions
    local goal = regions[toKey]
    if not goal or not regions[fromKey] then
        return nil
    end
    local function h(key)
        local r = regions[key]
        local dx, dy = goal.x - r.x, goal.y - r.y
        return math.sqrt(dx * dx + dy * dy)
    end
    local open = Heap.new()
    local g, cameFrom, closed = { [fromKey] = 0 }, {}, {}
    open:push(fromKey, h(fromKey))
    local found = false
    while not open:empty() do
        local current = open:pop()
        if not closed[current] then
            closed[current] = true
            if current == toKey then
                found = true
                break
            end
            for other, c in pairs(regions[current].links) do
                if not closed[other] and regions[other] then
                    local tentative = g[current] + c
                    if not g[other] or tentative < g[other] then
                        g[other] = tentative
                        cameFrom[other] = current
                        open:push(other, tentative + h(other))
                    end
                end
            end
        end
    end
    if not found then
        return nil
    end
    local key = toKey
    while key do
        corridor[key] = true
        key = cameFrom[key]
    end
    return corridor
end

--- Resumen: regiones, portales, sucias, búsquedas y reconstrucciones.
function Hierarchical:stats()
    return {
        regions = #self.regionList,
        portals = self.portalCount,
        dirty = self.dirtyCount,
        searches = self.searches,
        rebuilds = self.rebuilds,
    }
end

return Hierarchical

-- A* sobre el grafo de navegación (nodos y segmentos, no muestras de spline).
--
--   local AStar = require('runtime.nv.astar')
--   local path, err = AStar.find(graph, startId, goalId, {
--       agent = agentProps,                      -- para el coste de cada segmento
--       cost = function(segment, reversed, agent) ... end,   -- opcional
--       heuristic = function(nodeA, nodeB) ... end,          -- opcional (euclídea)
--       explored = true,                         -- devolver los nodos explorados
--       allow = function(nodeId) ... end,        -- opcional: restringir nodos (jerárquico)
--   })
--   -- path = { nodes = {ids}, steps = { {segment=, reversed=}, ... }, cost = , explored = {ids} }
--   -- o nil, 'sin ruta'
--
-- Cola abierta: `runtime/nv/heap.lua` (min-heap binario, reinserción perezosa).
--
-- Memoria (fase F): las tablas de trabajo (cola, `g`, de dónde viene cada
-- nodo, cerrados) son del módulo y se reutilizan entre búsquedas con un
-- sello por búsqueda (un nodo vale en esta búsqueda si su sello es el
-- actual), y el tramo por el que se llega a cada nodo va en dos tablas
-- paralelas en vez de una tabla por nodo. Antes, una búsqueda de esquina a
-- esquina en una rejilla de 16 × 12 nodos reservaba ~37 KB; ahora solo el
-- resultado (`nodes`, `steps`, que la caché guarda y comparte). Si una
-- búsqueda empieza dentro de otra (un `opts.cost` que busque), la de dentro
-- usa tablas propias.
-- Coste de una arista: `opts.cost(segment, reversed, agent)` o
-- `segment:cost(agent)`; `math.huge` (o negativo) = intransitable.
--
-- Heurística y optimalidad. A* devuelve el camino de coste mínimo solo si la
-- heurística es admisible (`h(n) ≤ coste real mínimo de n al destino`) y,
-- para no reabrir nodos con la lista cerrada que se usa aquí, consistente
-- (`h(a) ≤ coste(a, b) + h(b)`). La heurística por defecto es
--
--     h(n) = escala · dist(n, destino)
--
-- con `escala = graph:heuristicScale() = min(1, menor costFactor del grafo)`.
-- Vale porque el modelo de coste de `runtime/nv/segment.lua` es
--
--     coste = costFactor · (longitud + penalizaciones ≥ 0)   ≥   costFactor · longitud
--
-- y la longitud de un tramo (arco de la spline entre sus dos nodos) nunca es
-- menor que la distancia recta entre esos nodos; por la desigualdad
-- triangular, la suma de las rectas de un camino nunca es menor que la recta
-- al destino. Con todos los `costFactor ≥ 1` la escala es 1 (euclídea pura);
-- un tramo con `costFactor` en (0, 1) ("carretera bonificada") reduce la escala
-- a ese factor: A* explora algo más pero no pierde el óptimo. Las
-- penalizaciones (`terrainCost`, `vehiclePenalty`, `classCost`) se acotan a
-- ≥ 0 en `segment.lua` por la misma razón: una bonificación negativa
-- rompería la desigualdad sin que nadie lo notara. `opts.heuristicScale`
-- fija la escala a mano y `opts.heuristic` la sustituye del todo: entonces la
-- admisibilidad es responsabilidad del que llama (igual que con `opts.cost`).
--
-- Es direccional: `neighbours` respeta `oneWay` y el coste puede depender de
-- `reversed`, así que A→B no tiene por qué ser igual que B→A.

local Heap = require('runtime.nv.heap')

local AStar = {}

local EMPTY = {}

local function euclid(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return math.sqrt(dx * dx + dy * dy)
end
AStar.euclid = euclid

local function defaultCost(segment, _reversed, agent)
    return segment:cost(agent)
end

-- Tablas de trabajo compartidas (ver la cabecera).
local function newWorkspace()
    return {
        open = Heap.new(),
        stamp = 0,
        seen = {}, -- nodeId → sello de la búsqueda que le dio `g`
        closed = {}, -- nodeId → sello de la búsqueda que lo cerró
        g = {}, -- nodeId → coste acumulado
        cameFrom = {}, -- nodeId → nodeId anterior
        bySegment = {}, -- nodeId → tramo por el que se llega
        byReversed = {}, -- nodeId → ¿a contramano?
    }
end
local shared = newWorkspace()
local sharedBusy = false

function AStar.find(graph, startId, goalId, opts)
    opts = opts or EMPTY
    local start, goal = graph:node(startId), graph:node(goalId)
    if not start then
        return nil, 'nodo de origen inexistente'
    end
    if not goal then
        return nil, 'nodo de destino inexistente'
    end
    local agent = opts.agent or EMPTY
    local cost = opts.cost or defaultCost
    local heuristic = opts.heuristic
    if not heuristic then
        local scale = opts.heuristicScale
        if scale == nil then
            scale = graph.heuristicScale and graph:heuristicScale() or 1
        end
        if scale == 1 then
            heuristic = euclid
        else
            heuristic = function(a, b)
                return euclid(a, b) * scale
            end
        end
    end
    local allow = opts.allow
    local explored = opts.explored and {} or nil
    if startId == goalId then
        return { nodes = { startId }, steps = {}, cost = 0, explored = explored or {} }
    end
    local ws = shared
    local own = sharedBusy
    if own then
        ws = newWorkspace()
    end
    sharedBusy = true
    ws.stamp = ws.stamp + 1
    local stamp = ws.stamp
    local open = ws.open
    open:clear()
    local seen, closed, g = ws.seen, ws.closed, ws.g
    local cameFrom, bySegment, byReversed = ws.cameFrom, ws.bySegment, ws.byReversed
    seen[startId] = stamp
    g[startId] = 0
    cameFrom[startId] = nil
    bySegment[startId], byReversed[startId] = nil, nil
    open:push(startId, heuristic(start, goal))
    local found = false
    while not open:empty() do
        local current = open:pop()
        if closed[current] ~= stamp then
            closed[current] = stamp
            if explored then
                explored[#explored + 1] = current
            end
            if current == goalId then
                found = true
                break
            end
            local here = graph:node(current)
            local gHere = g[current]
            local list = graph:neighbours(current)
            for i = 1, #list do
                local edge = list[i]
                local other = edge.other
                if other and closed[other] ~= stamp and (not allow or allow(other)) then
                    local c = cost(edge.segment, edge.reversed, agent)
                    if c ~= math.huge and c >= 0 then
                        local tentative = gHere + c
                        if seen[other] ~= stamp or tentative < g[other] then
                            seen[other] = stamp
                            g[other] = tentative
                            cameFrom[other] = current
                            bySegment[other], byReversed[other] = edge.segment, edge.reversed
                            open:push(other, tentative + heuristic(graph:node(other), goal))
                        end
                    end
                end
            end
            -- `here` solo se usa para la heurística de los vecinos; queda por claridad.
            if not here then
                break
            end
        end
    end
    if not own then
        sharedBusy = false
    end
    if not found then
        open:clear()
        return nil, 'sin ruta'
    end
    local nodes, steps = {}, {}
    local id = goalId
    while id do
        table.insert(nodes, 1, id)
        local segment = bySegment[id]
        if segment then
            table.insert(steps, 1, { segment = segment, reversed = byReversed[id] })
        end
        id = cameFrom[id]
    end
    open:clear()
    return { nodes = nodes, steps = steps, cost = g[goalId], explored = explored or {} }
end

--- Longitud en píxeles de una lista de pasos.
function AStar.stepsLength(steps)
    local total = 0
    for _, step in ipairs(steps or EMPTY) do
        total = total + step.segment.length
    end
    return total
end

return AStar

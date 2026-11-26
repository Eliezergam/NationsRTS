-- Dibujo de depuración de NV con `love.graphics`, en coordenadas de mundo:
-- vale dentro de `camera:attach()` y dentro del `translate/scale` del editor.
--
--   local NavigationDebug = require('runtime.nv.debug')
--   NavigationDebug.draw(manager, flags, { agents = list, groups = list, selected = list, zoom = 2 })
--
-- `flags` son booleanos con exactamente estos nombres (`NavigationDebug.flagNames`):
--   showNavigation, showNodes, showSegments, showSplines, showRawPoints,
--   showOptimizedPoints, showSpatialGrid, showQuadtree, showRegions, showAStarPath,
--   showCachedPaths, showLookAhead, showCurvature, showNavigationCosts,
--   showSelectedUnitPaths, showGroupRoute, showFormationAnchor, showDestinationSlots,
--   showRequestedDestination, showProjectedDestination, showLocalAvoidanceVectors,
--   showSteeringVector, showAgentState, showRepathReason,
--   showAgentGrid, showNeighbours, showScheduler, showFlowField, showCorridor,
--   showCongestion, showYield, showLod
--
-- `showNavigation` es el interruptor de la red (nodos, segmentos, splines,
-- puntos, rejilla, quadtree, regiones, costes, curvatura, última búsqueda A*
-- y caché); los flags de agentes y grupos son independientes. `extra.zoom` es
-- la escala de mundo a pantalla, para que las líneas midan lo mismo en
-- píxeles a cualquier zoom. El color y el grosor de línea se restauran al
-- terminar.
--
-- Escala: `showAgentGrid` pinta las celdas ocupadas del `AgentSpatialHash`
-- del manager (`manager.agentIndex`, o `extra.agentIndex`) con su cuenta;
-- `showNeighbours` une cada agente seleccionado con los vecinos que consultó
-- en su último `update`; `showScheduler` marca a los agentes con ruta
-- pendiente en el planificador (un rombo con "pending").
--
-- Mapas grandes y ejércitos: `showRegions` pinta las regiones del buscador
-- jerárquico v2 (las sucias, rellenas) y sus PORTALES (círculo relleno en
-- cada nodo con un tramo hacia otra región); `showFlowField` una flecha por
-- celda válida de cada flow field activo (`manager.flowFields`), atenuada
-- cuanto mayor es su coste integrado; `showCorridor` el contorno de las
-- celdas válidas de cada campo (el corredor) y su destino.
--
-- Congestión (fase E): `showCongestion` rodea a cada agente en marcha que no
-- está en 'moving' con un aro del color de su estado de atasco (amarillo
-- 'slow', naranja 'locallyBlocked', rojo 'stuck', magenta 'repathPending'),
-- con el nombre del estado y el tiempo bloqueado; un llegado que está
-- haciendo sitio lleva un aro azul discontinuo. `showYield` marca a los que
-- ceden el paso (flecha hacia atrás y "cede") unida al agente al que ceden,
-- y a los que tienen el paso ("prio").
--
-- LOD (fase F): `showLod` pone a cada agente un punto del color de su nivel
-- (verde 'full', amarillo 'reduced', rojo 'coarse'; más grande en el
-- cuadro en que decide) y el contorno del rectángulo de foco del manager
-- (`manager:setFocus`) con la cuenta de cada nivel.

local NavigationDebug = {}

NavigationDebug.flagNames = {
    'showNavigation',
    'showNodes',
    'showSegments',
    'showSplines',
    'showRawPoints',
    'showOptimizedPoints',
    'showSpatialGrid',
    'showQuadtree',
    'showRegions',
    'showAStarPath',
    'showCachedPaths',
    'showLookAhead',
    'showCurvature',
    'showNavigationCosts',
    'showSelectedUnitPaths',
    'showGroupRoute',
    'showFormationAnchor',
    'showDestinationSlots',
    'showRequestedDestination',
    'showProjectedDestination',
    'showLocalAvoidanceVectors',
    'showSteeringVector',
    'showAgentState',
    'showRepathReason',
    'showAgentGrid',
    'showNeighbours',
    'showScheduler',
    'showFlowField',
    'showCorridor',
    'showCongestion',
    'showYield',
    'showLod',
}

NavigationDebug.colors = {
    node = { 0.35, 0.85, 1 },
    segment = { 0.3, 0.6, 1 },
    spline = { 1, 1, 1 },
    raw = { 1, 0.5, 0.2 },
    optimized = { 1, 0.9, 0.2 },
    grid = { 1, 1, 1, 0.12 },
    quadtree = { 0.6, 1, 0.6, 0.35 },
    region = { 1, 0.6, 1, 0.3 },
    astar = { 1, 0.3, 0.3 },
    explored = { 1, 0.3, 0.3, 0.25 },
    cached = { 0.7, 0.7, 1, 0.5 },
    path = { 0.3, 1, 0.5 },
    selected = { 1, 1, 0.3 },
    lookAhead = { 1, 0.4, 1 },
    anchor = { 1, 0.8, 0.2 },
    slot = { 0.4, 1, 0.9 },
    requested = { 1, 0.3, 0.3 },
    projected = { 0.3, 1, 0.3 },
    avoid = { 1, 0.5, 0.1 },
    steer = { 0.5, 0.8, 1 },
    text = { 1, 1, 1 },
    agentGrid = { 0.3, 1, 0.8, 0.25 },
    neighbour = { 1, 0.85, 0.3, 0.7 },
    pending = { 1, 0.6, 0.2 },
    regionDirty = { 1, 0.6, 1, 0.12 },
    portal = { 1, 0.75, 1 },
    flow = { 0.4, 0.9, 1 },
    corridor = { 1, 0.9, 0.3, 0.8 },
    slow = { 1, 0.9, 0.2 },
    locallyBlocked = { 1, 0.55, 0.1 },
    stuck = { 1, 0.15, 0.15 },
    repathPending = { 1, 0.3, 1 },
    makingWay = { 0.4, 0.7, 1 },
    yielding = { 0.7, 0.5, 1 },
    priority = { 0.3, 1, 0.6 },
    lodFull = { 0.3, 1, 0.4 },
    lodReduced = { 1, 0.85, 0.2 },
    lodCoarse = { 1, 0.3, 0.25 },
    lodFocus = { 0.3, 1, 0.4, 0.8 },
}

-- Color de cada nivel de LOD (`agent.lodLevel`).
local LOD_COLORS = { 'lodFull', 'lodReduced', 'lodCoarse' }

--- ¿Hay algún flag activo?
function NavigationDebug.anyActive(flags)
    if type(flags) ~= 'table' then
        return false
    end
    for _, name in ipairs(NavigationDebug.flagNames) do
        if flags[name] then
            return true
        end
    end
    return false
end

--- Todos los flags a `value` (false por defecto).
function NavigationDebug.flags(value)
    local out = {}
    for _, name in ipairs(NavigationDebug.flagNames) do
        out[name] = value == true
    end
    return out
end

local EMPTY = {}

-- Color de la curvatura: verde recta, rojo cerrada (k = 1/40 o más).
local function curvatureColor(k)
    local t = math.min(1, k * 40)
    return 1 * t + 0.2 * (1 - t), 0.9 * (1 - t) + 0.2 * t, 0.2
end

-- Buffers del dibujo, reutilizados entre cuadros (fase F: el dibujo de
-- depuración con 1000 agentes reservaba ~150 KB por cuadro, casi todo en
-- estas listas; ver `docs/NV.md` → "Rendimiento").
local flat = {} -- polilínea plana {x1, y1, x2, y2, ...}
local flatCount = 0
local gridCells = { {}, {} } -- celdas ocupadas del índice de tramos y del de nodos
local agentCells = {} -- celdas ocupadas del índice de agentes
local selectedSet = {} -- agente → true, durante un `draw`

local function polyline(g, xs, ys, n)
    if n < 2 then
        return
    end
    local m = 0
    for i = 1, n do
        flat[m + 1] = xs[i]
        flat[m + 2] = ys[i]
        m = m + 2
    end
    for i = flatCount, m + 1, -1 do
        flat[i] = nil
    end
    flatCount = m
    g.line(flat)
end

local function drawSystem(g, system, flags, px, font)
    local C = NavigationDebug.colors
    local graph = system.graph
    if flags.showSpatialGrid then
        g.setColor(C.grid)
        g.setLineWidth(px)
        local size = system.segmentIndex.cellSize
        for pass = 1, 2 do
            local index = pass == 1 and system.segmentIndex or system.nodeIndex
            local cells = index:occupiedCells(gridCells[pass])
            for i = 1, #cells do
                local cell = cells[i]
                g.rectangle('line', cell.cx * size, cell.cy * size, size, size)
            end
        end
    end
    if flags.showQuadtree and system.quadtree then
        g.setColor(C.quadtree)
        g.setLineWidth(px)
        system.quadtree:eachNode(function(node)
            g.rectangle('line', node.x, node.y, node.w, node.h)
        end)
    end
    if flags.showRegions then
        -- Regiones y portales del buscador jerárquico (se crea si no existe:
        -- son datos derivados, y así el editor también los enseña).
        local hp = system:hierarchical()
        hp:build()
        g.setLineWidth(px)
        local size = hp.clusterSize
        for _, region in ipairs(hp.regionList) do
            if region.dirty then
                g.setColor(C.regionDirty)
                g.rectangle('fill', region.cx * size, region.cy * size, size, size)
            end
            g.setColor(C.region)
            g.rectangle('line', region.cx * size, region.cy * size, size, size)
        end
        g.setColor(C.portal)
        for _, region in ipairs(hp.regionList) do
            for _, id in ipairs(region.portals) do
                local node = graph:node(id)
                if node then
                    g.circle('fill', node.x, node.y, 4 * px)
                end
            end
        end
    end
    for _, seg in ipairs(graph:segments()) do
        if seg.arc then
            local arc = seg.arc
            if flags.showSegments then
                g.setColor(C.segment[1], C.segment[2], C.segment[3], 0.25)
                g.setLineWidth(seg.width)
                polyline(g, arc.xs, arc.ys, arc.count)
            end
            if flags.showSplines or flags.showCurvature then
                g.setLineWidth(2 * px)
                if flags.showCurvature then
                    for i = 1, arc.count - 1 do
                        g.setColor(curvatureColor(seg:curvatureAt(arc.ds[i])))
                        g.line(arc.xs[i], arc.ys[i], arc.xs[i + 1], arc.ys[i + 1])
                    end
                else
                    g.setColor(C.spline)
                    polyline(g, arc.xs, arc.ys, arc.count)
                end
                if seg.oneWay == 'forward' then
                    -- Flecha en el medio, en el sentido permitido.
                    local mid = seg.length * 0.5
                    local x, y = seg:positionAt(mid)
                    local tx, ty = seg:tangentAt(mid)
                    local s = 8 * px
                    g.setColor(C.spline)
                    g.line(
                        x - tx * s - ty * s,
                        y - ty * s + tx * s,
                        x + tx * s,
                        y + ty * s,
                        x - tx * s + ty * s,
                        y - ty * s - tx * s
                    )
                end
            end
            if flags.showRawPoints and seg.rawPoints then
                g.setColor(C.raw)
                for _, p in ipairs(seg.rawPoints) do
                    g.circle('fill', p.x, p.y, 2 * px)
                end
            end
            if flags.showOptimizedPoints then
                g.setColor(C.optimized)
                for _, p in ipairs(seg.points) do
                    g.circle('line', p.x, p.y, 3.5 * px)
                end
            end
            if flags.showNavigationCosts and font then
                local x, y = seg:positionAt(seg.length * 0.5)
                g.setColor(C.text)
                g.print(
                    ('%d | k %.3f | v %d'):format(seg.baseCost, seg.maxCurvature, seg.recommendedSpeed),
                    x + 4 * px,
                    y + 4 * px,
                    0,
                    px,
                    px
                )
            end
        end
    end
    if flags.showNodes then
        g.setLineWidth(2 * px)
        for _, node in ipairs(graph:nodes()) do
            g.setColor(0, 0, 0, 0.6)
            g.circle('fill', node.x, node.y, 6 * px)
            g.setColor(C.node)
            g.circle('line', node.x, node.y, 6 * px)
            if font and flags.showNavigationCosts then
                g.print(tostring(node.id), node.x + 7 * px, node.y - 7 * px, 0, px, px)
            end
        end
    end
    if flags.showAStarPath and system.lastSearch then
        local search = system.lastSearch
        g.setColor(C.explored)
        for _, id in ipairs(search.explored or EMPTY) do
            local node = graph:node(id)
            if node then
                g.circle('fill', node.x, node.y, 9 * px)
            end
        end
        g.setColor(C.astar)
        g.setLineWidth(3 * px)
        for _, step in ipairs(search.steps or EMPTY) do
            local arc = step.segment.arc
            if arc then
                polyline(g, arc.xs, arc.ys, arc.count)
            end
        end
    end
    if flags.showCachedPaths then
        g.setColor(C.cached)
        g.setLineWidth(px)
        system.cache:each(function(_, result)
            for _, step in ipairs(result.steps or EMPTY) do
                local arc = step.segment.arc
                if arc then
                    polyline(g, arc.xs, arc.ys, arc.count)
                end
            end
        end)
    end
end

local function drawRoute(g, route, color, width)
    local wp = route:waypoints()
    if #wp >= 4 then
        g.setColor(color)
        g.setLineWidth(width)
        g.line(wp)
    end
end

local function drawAgent(g, agent, flags, px, font, selected)
    local C = NavigationDebug.colors
    local t = agent.target
    if not t or (t.isDestroyed and t:isDestroyed()) then
        return
    end
    local x, y = t.x, t.y
    local route = agent.route
    if route and ((flags.showSelectedUnitPaths and selected) or flags.showGroupRoute) then
        drawRoute(g, route, selected and C.selected or C.path, (selected and 2.5 or 1.5) * px)
    end
    if flags.showLookAhead and agent:isMoving() then
        local la = agent.lookAheadTarget
        g.setColor(C.lookAhead)
        g.setLineWidth(px)
        g.line(x, y, la.x, la.y)
        g.circle('line', la.x, la.y, 4 * px)
        if route and agent.follower then
            local last, nextNode = route:nodeAt(agent.follower.distance)
            local sys = agent.system
            local node = sys and sys.graph:node(nextNode or last or -1)
            if node then
                g.circle('line', node.x, node.y, 10 * px)
            end
        end
    end
    if flags.showSteeringVector and agent:isMoving() then
        local s = agent.steering
        g.setColor(C.steer)
        g.setLineWidth(2 * px)
        g.line(x, y, x + s.x * 32 * px, y + s.y * 32 * px)
    end
    if flags.showLocalAvoidanceVectors then
        local a = agent.avoidVector
        if a.x ~= 0 or a.y ~= 0 then
            g.setColor(C.avoid)
            g.setLineWidth(2 * px)
            g.line(x, y, x + a.x * 32 * px, y + a.y * 32 * px)
        end
        local ft = agent.formationTarget
        if ft.active then
            g.setColor(C.anchor[1], C.anchor[2], C.anchor[3], 0.6)
            g.setLineWidth(px)
            g.line(x, y, ft.x, ft.y)
        end
    end
    if flags.showNeighbours and selected then
        local list = agent:lastNeighbours()
        if list then
            g.setColor(C.neighbour)
            g.setLineWidth(px)
            for i = 1, #list do
                local n = list[i]
                local nt = n.target or n
                if nt.x and nt.y then
                    g.line(x, y, nt.x, nt.y)
                end
            end
            g.circle('line', x, y, agent.props.avoidanceRadius)
        end
    end
    if flags.showScheduler and agent:isPending() then
        g.setColor(C.pending)
        g.setLineWidth(2 * px)
        local s = 8 * px
        g.line(x, y - s, x + s, y, x, y + s, x - s, y, x, y - s)
        if font then
            g.print('pending', x + 10 * px, y + 4 * px, 0, px, px)
        end
    end
    if flags.showCongestion then
        local c = agent.congestion
        local r = (agent.props and agent.props.radius or 16) + 4 * px
        if agent:isMoving() and c and c.state ~= 'moving' then
            g.setColor(C[c.state] or C.text)
            g.setLineWidth(2 * px)
            g.circle('line', x, y, r)
            if font then
                g.print(('%s %.1f'):format(c.state, c.blockedTime), x + r, y + 2 * px, 0, px, px)
            end
        elseif agent.makingWay then
            g.setColor(C.makingWay)
            g.setLineWidth(px)
            for k = 0, 7 do
                local a0 = k * math.pi / 4
                g.arc('line', 'open', x, y, r, a0, a0 + math.pi / 8)
            end
        end
    end
    if flags.showYield and agent.yieldState and agent.yieldState ~= 'none' then
        g.setLineWidth(2 * px)
        if agent.yieldState == 'yielding' then
            g.setColor(C.yielding)
            local to = agent.yieldTo and agent.yieldTo.target
            if to and to.x and to.y then
                g.line(x, y, to.x, to.y)
            end
            local hx, hy = math.cos(agent.heading), math.sin(agent.heading)
            local s = 12 * px
            g.line(x, y, x - hx * s, y - hy * s)
            g.line(x - hx * s, y - hy * s, x - hx * s * 0.5 - hy * s * 0.4, y - hy * s * 0.5 + hx * s * 0.4)
            if font then
                g.print('cede', x + 10 * px, y + 14 * px, 0, px, px)
            end
        else
            g.setColor(C.priority)
            if font then
                g.print('prio', x + 10 * px, y + 14 * px, 0, px, px)
            end
        end
    end
    if flags.showLod then
        local level = agent.lodLevel or 1
        g.setColor(C[LOD_COLORS[level]] or C.lodFull)
        local r = 3 * px
        if level > 1 and agent.lodDecide then
            r = 5 * px -- decide en este cuadro
        end
        g.circle('fill', x, y, r)
    end
    if flags.showRequestedDestination and agent.destination then
        g.setColor(C.requested)
        g.setLineWidth(px)
        local d = agent.destination
        g.line(d.x - 5 * px, d.y - 5 * px, d.x + 5 * px, d.y + 5 * px)
        g.line(d.x - 5 * px, d.y + 5 * px, d.x + 5 * px, d.y - 5 * px)
    end
    if flags.showProjectedDestination and route and route.goalProjection then
        local p = route.goalProjection
        g.setColor(C.projected)
        g.circle('line', p.x, p.y, 5 * px)
    end
    if font and (flags.showAgentState or flags.showRepathReason) then
        local text = ''
        if flags.showAgentState then
            text = agent:getState() .. (' %.0f'):format(agent.speed)
        end
        if flags.showRepathReason and agent.repathReason then
            text = text .. ' repath: ' .. agent.repathReason
        end
        if agent.failReason and agent:getState() ~= 'moving' then
            text = text .. ' ' .. agent.failReason
        end
        g.setColor(C.text)
        g.print(text, x + 10 * px, y - 10 * px, 0, px, px)
    end
end

local function drawGroups(g, groups, flags, px)
    local C = NavigationDebug.colors
    for _, request in ipairs(groups) do
        if flags.showRequestedDestination then
            local d = request.requestedDestination
            g.setColor(C.requested)
            g.setLineWidth(2 * px)
            g.circle('line', d.x, d.y, 8 * px)
        end
        for _, group in ipairs(request.groups) do
            if flags.showProjectedDestination and group.navigationDestination then
                local nd = group.navigationDestination
                g.setColor(C.projected)
                g.setLineWidth(2 * px)
                g.circle('line', nd.x, nd.y, 8 * px)
                g.line(request.requestedDestination.x, request.requestedDestination.y, nd.x, nd.y)
            end
            if flags.showDestinationSlots then
                g.setLineWidth(px)
                for _, slot in ipairs(group.slots) do
                    if slot.failed then
                        -- Puesto sin candidato válido: un aspa.
                        g.setColor(C.requested)
                        g.line(slot.x - 5 * px, slot.y - 5 * px, slot.x + 5 * px, slot.y + 5 * px)
                        g.line(slot.x - 5 * px, slot.y + 5 * px, slot.x + 5 * px, slot.y - 5 * px)
                    else
                        g.setColor(C.slot)
                        g.circle('line', slot.x, slot.y, 5 * px)
                        if slot.fallback then
                            -- Recolocado por el validador: un punto dentro.
                            g.circle('fill', slot.x, slot.y, 2 * px)
                        end
                    end
                end
            end
            local f = group.formation
            if f and f.active then
                if flags.showGroupRoute then
                    drawRoute(g, f.route, C.path, 1.5 * px)
                end
                if flags.showFormationAnchor then
                    g.setColor(C.anchor)
                    g.setLineWidth(2 * px)
                    g.circle('line', f.anchor.x, f.anchor.y, 7 * px)
                    g.line(
                        f.anchor.x,
                        f.anchor.y,
                        f.anchor.x + f.anchor.tx * 20 * px,
                        f.anchor.y + f.anchor.ty * 20 * px
                    )
                end
            end
        end
    end
end

-- Flechas por celda válida, atenuadas por coste, y contorno del corredor.
local function drawFlowField(g, field, flags, px, font)
    local C = NavigationDebug.colors
    if not field.built or field.count == 0 then
        return
    end
    local size, cols, rows = field.cellSize, field.cols, field.rows
    local ox, oy = field.ox, field.oy
    local valid, dirX, dirY, cost = field.valid, field.dirX, field.dirY, field.integrationCost
    local maxCost = field.maxCost > 0 and field.maxCost or 1
    if flags.showFlowField then
        g.setLineWidth(px)
        local len = size * 0.4
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                local i = row * cols + col + 1
                if valid[i] then
                    local cx, cy = ox + (col + 0.5) * size, oy + (row + 0.5) * size
                    local a = 0.2 + 0.8 * (1 - math.min(1, cost[i] / maxCost))
                    g.setColor(C.flow[1], C.flow[2], C.flow[3], a)
                    local dx, dy = dirX[i], dirY[i]
                    if dx ~= 0 or dy ~= 0 then
                        local hx, hy = cx + dx * len, cy + dy * len
                        g.line(cx - dx * len * 0.5, cy - dy * len * 0.5, hx, hy)
                        -- Punta: dos trazos cortos hacia atrás.
                        local s = size * 0.15
                        g.line(hx, hy, hx - dx * s - dy * s, hy - dy * s + dx * s)
                        g.line(hx, hy, hx - dx * s + dy * s, hy - dy * s - dx * s)
                    else
                        g.circle('fill', cx, cy, 2 * px)
                    end
                end
            end
        end
    end
    if flags.showCorridor then
        g.setColor(C.corridor)
        g.setLineWidth(1.5 * px)
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                local i = row * cols + col + 1
                if valid[i] then
                    local x0, y0 = ox + col * size, oy + row * size
                    -- Un borde por cada vecino ortogonal inválido (o fuera).
                    if col == 0 or not valid[i - 1] then
                        g.line(x0, y0, x0, y0 + size)
                    end
                    if col == cols - 1 or not valid[i + 1] then
                        g.line(x0 + size, y0, x0 + size, y0 + size)
                    end
                    if row == 0 or not valid[i - cols] then
                        g.line(x0, y0, x0 + size, y0)
                    end
                    if row == rows - 1 or not valid[i + cols] then
                        g.line(x0, y0 + size, x0 + size, y0 + size)
                    end
                end
            end
        end
        local dest = field.destination
        if dest then
            g.circle('line', dest.x, dest.y, 8 * px)
            if font then
                local st = field:stats()
                g.print(('%d celdas, %.2f ms'):format(st.validCells, st.buildMs), dest.x + 10 * px, dest.y, 0, px, px)
            end
        end
    end
end

--- Dibuja. `extra = { agents = list, groups = list, selected = list, zoom = number }`.
-- `love.graphics` con `print` de pie (ver `NavigationDebug.draw`).
local uprightGraphics = setmetatable({
    print = function(text, x, y, r, sx, sy)
        require('runtime.projection').upright(x or 0, y or 0, function()
            love.graphics.print(text, 0, 0, r, sx, sy)
        end)
    end,
}, {
    __index = function(_, key)
        return love.graphics[key]
    end,
})

function NavigationDebug.draw(manager, flags, extra)
    if not (love and love.graphics) or type(flags) ~= 'table' then
        return
    end
    extra = extra or EMPTY
    local g = love.graphics
    -- En isométrico los rótulos se escriben de pie: el resto (líneas, círculos,
    -- celdas) va sobre el suelo y sale en rombo con la transformación del mundo.
    local Projection = require('runtime.projection')
    if Projection.isIso(Projection.current) then
        g = uprightGraphics
    end
    local r0, g0, b0, a0 = g.getColor()
    local lw = g.getLineWidth()
    local zoom = tonumber(extra.zoom) or 1
    if zoom <= 0 then
        zoom = 1
    end
    local px = 1 / zoom
    local font = g.getFont and g.getFont() or nil
    if flags.showNavigation ~= false and manager then
        local networkFlags = flags.showNodes
            or flags.showSegments
            or flags.showSplines
            or flags.showRawPoints
            or flags.showOptimizedPoints
            or flags.showSpatialGrid
            or flags.showQuadtree
            or flags.showRegions
            or flags.showAStarPath
            or flags.showCachedPaths
            or flags.showCurvature
            or flags.showNavigationCosts
        if networkFlags then
            for _, system in ipairs(manager:systems()) do
                drawSystem(g, system, flags, px, font)
            end
        end
    end
    local agentIndex = extra.agentIndex or (manager and manager.agentIndex)
    if flags.showAgentGrid and agentIndex then
        local C = NavigationDebug.colors
        local size = agentIndex.cellSize
        g.setColor(C.agentGrid)
        g.setLineWidth(px)
        for _, cell in ipairs(agentIndex:cells(agentCells)) do
            g.rectangle('line', cell.cx * size, cell.cy * size, size, size)
            if font then
                g.print(tostring(cell.n), cell.cx * size + 2 * px, cell.cy * size + 2 * px, 0, px, px)
            end
        end
    end
    if (flags.showFlowField or flags.showCorridor) and manager and manager.flowFields then
        for field in pairs(manager.flowFields) do
            drawFlowField(g, field, flags, px, font)
        end
    end
    if extra.groups then
        drawGroups(g, extra.groups, flags, px)
    end
    if flags.showLod and manager and manager.getFocus then
        local fx, fy, fw, fh = manager:getFocus()
        if fx then
            local C = NavigationDebug.colors
            g.setColor(C.lodFocus)
            g.setLineWidth(2 * px)
            g.rectangle('line', fx, fy, fw, fh)
            if font then
                g.print(
                    ('LOD %d / %d / %d'):format(manager.lodFull or 0, manager.lodReduced or 0, manager.lodCoarse or 0),
                    fx + 4 * px,
                    fy + 4 * px,
                    0,
                    px,
                    px
                )
            end
        end
    end
    for _, agent in ipairs(extra.selected or EMPTY) do
        selectedSet[agent] = true
    end
    for _, agent in ipairs(extra.agents or EMPTY) do
        drawAgent(g, agent, flags, px, font, selectedSet[agent])
    end
    for _, agent in ipairs(extra.selected or EMPTY) do
        selectedSet[agent] = nil
        if not extra.agents then
            drawAgent(g, agent, flags, px, font, true)
        end
    end
    g.setLineWidth(lw)
    g.setColor(r0, g0, b0, a0)
end

return NavigationDebug

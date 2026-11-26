-- Índice espacial dinámico SOLO para agentes móviles (AgentSpatialHash).
--
--   local AgentSpatialHash = require('runtime.nv.agent_spatial_hash')
--   local index = AgentSpatialHash.new(64)
--   index:update(agents)                              -- una vez por cuadro, antes de mover
--   local list = index:queryRadius(x, y, r, out, me)  -- vecinos a ≤ r (+ su radio), nunca `me`
--   index:stats()   -- activeAgents, averageNeighbours, maxNeighbours, queriesPerFrame, candidateChecksPerFrame
--   index:cells(out) -- { {cx=, cy=, n=}, ... } para el dibujo de depuración (reutiliza `out`)
--
-- No es el `SpatialHash` de nodos y segmentos (`runtime/nv/spatial_hash.lua`):
-- aquel indexa cajas estáticas que cambian al editar; este indexa puntos que
-- cambian TODOS los cuadros, así que está pensado para `update` barato:
--
--   * cada agente ocupa una sola celda (la de su centro); su radio se tiene en
--     cuenta en la consulta, no en la inserción, para que mover un agente sea
--     cambiarlo de una lista a otra como mucho;
--   * los agentes viven en arrays paralelos por índice (`tracked[i]`, `xs[i]`,
--     `ys[i]`, `rs[i]`, `cellKey[i]`) y las celdas guardan índices, no
--     tablas: el bucle de la consulta lee tres números por candidato y LuaJIT
--     lo compila entero (con tablas de agente y ramas por candidato abortaba
--     la traza y corría interpretado);
--   * `update` no reconstruye nada: para cada agente refresca su posición y
--     radio en los arrays, calcula la clave de su celda y solo lo mueve de
--     lista si cambió; los que ya no están en la lista se quitan comparando
--     un sello por cuadro (el último ocupa el hueco, como en un swap-remove);
--     las listas de celda vacías se guardan en una reserva y en régimen
--     estacionario no se crea ninguna tabla por cuadro;
--   * `queryRadius` recorre las celdas que cruza el círculo `(x, y, r + radioMax)`
--     y acepta al agente `n` si `dist(p, n) ≤ r + radio(n)`: así una unidad
--     grande entra en la vecindad de una pequeña aunque su centro quede lejos.
--     El resultado se escribe en `out` (una lista reutilizada por el que llama)
--     y nunca incluye a `exclude`. Las posiciones son las del último `update`
--     (el principio del cuadro): todos los agentes ven la misma foto.
--
-- Sin este índice la esquiva local compara cada agente contra todos los demás:
-- 1 000 agentes → 1 000 000 comparaciones por cuadro. Con celdas del tamaño
-- del radio de consulta, cada agente mira ~9-16 celdas y solo a los que están
-- de verdad cerca (`candidateChecksPerFrame` lo mide).

local NvUtil = require('runtime.nv.util')

local AgentSpatialHash = NvUtil.class('AgentSpatialHash')

AgentSpatialHash.defaults = { cellSize = 64 }

local EMPTY = {}

-- Clave entera de la celda (cx, cy): sin strings por cuadro.
local OFFSET = 2 ^ 20
local STRIDE = 2 ^ 21
local function key(cx, cy)
    return (cy + OFFSET) * STRIDE + (cx + OFFSET)
end

local function positionOf(agent)
    local t = agent.target
    if t then
        return t.x, t.y
    end
    return agent.x, agent.y
end
AgentSpatialHash.positionOf = positionOf

-- Radio sin saneado por consulta: `NavigationAgent.normalizeProps` ya deja
-- `props.radius` como número finito; una tabla plana trae `radius` o nada.
local function radiusOf(agent)
    local props = agent.props
    local r
    if props then
        r = props.radius
    else
        r = agent.radius
    end
    if r == nil or r ~= r then
        return 16
    end
    return r
end
AgentSpatialHash.radiusOf = radiusOf

function AgentSpatialHash:init(cellSize)
    self.cellSize = NvUtil.atLeast(cellSize, AgentSpatialHash.defaults.cellSize, 1)
    self.buckets = {} -- clave de celda → lista de índices
    self.tracked = {} -- índice → agente
    self.trackedIndex = {} -- agente → índice
    self.xs, self.ys, self.rs = {}, {}, {} -- índice → posición y radio del último update
    self.cellKey = {} -- índice → clave de su celda
    self.stamp = {} -- índice → sello del último `update` en que apareció
    self.frame = 0
    self.count = 0
    self.maxRadius = 0 -- el radio mayor entre los agentes indexados
    self._pool = {} -- listas de celda vacías para reutilizar
    self._out = {} -- resultado de consulta cuando el que llama no trae lista
    -- Contadores del cuadro en curso y copia del último completo.
    self._queries, self._candidates, self._neighbours, self._maxNeighbours = 0, 0, 0, 0
    self._stats = {
        activeAgents = 0,
        averageNeighbours = 0,
        maxNeighbours = 0,
        queriesPerFrame = 0,
        candidateChecksPerFrame = 0,
    }
end

function AgentSpatialHash:cellOf(v)
    return math.floor(v / self.cellSize)
end

local function takeList(self)
    local pool = self._pool
    local n = #pool
    if n > 0 then
        local list = pool[n]
        pool[n] = nil
        return list
    end
    return {}
end

local function addToCell(self, k, index)
    local list = self.buckets[k]
    if not list then
        list = takeList(self)
        self.buckets[k] = list
    end
    list[#list + 1] = index
end

local function removeFromCell(self, k, index)
    local list = self.buckets[k]
    if not list then
        return
    end
    local n = #list
    for i = n, 1, -1 do
        if list[i] == index then
            list[i] = list[n]
            list[n] = nil
            n = n - 1
        end
    end
    if n == 0 then
        self.buckets[k] = nil
        self._pool[#self._pool + 1] = list
    end
end

-- Sustituye el índice `from` por `to` en la lista de su celda.
local function renameInCell(self, k, from, to)
    local list = self.buckets[k]
    if not list then
        return
    end
    for i = 1, #list do
        if list[i] == from then
            list[i] = to
            return
        end
    end
end

local function track(self, agent)
    local i = self.count + 1
    self.count = i
    self.tracked[i] = agent
    self.trackedIndex[agent] = i
    return i
end

-- Quita el índice `i`: el último ocupa su hueco (y su celda aprende el índice nuevo).
local function untrack(self, i)
    local tracked, xs, ys, rs, cellKey, stamp = self.tracked, self.xs, self.ys, self.rs, self.cellKey, self.stamp
    local agent = tracked[i]
    local k = cellKey[i]
    if k then
        removeFromCell(self, k, i)
    end
    self.trackedIndex[agent] = nil
    local last = self.count
    if i ~= last then
        local mover = tracked[last]
        tracked[i], xs[i], ys[i], rs[i], cellKey[i], stamp[i] =
            mover, xs[last], ys[last], rs[last], cellKey[last], stamp[last]
        self.trackedIndex[mover] = i
        if cellKey[i] then
            renameInCell(self, cellKey[i], last, i)
        end
    end
    tracked[last], xs[last], ys[last], rs[last], cellKey[last], stamp[last] = nil, nil, nil, nil, nil, nil
    self.count = last - 1
end

--- Sincroniza el índice con la lista `agents`: refresca posiciones y radios,
-- mueve a los que cambiaron de celda, añade a los nuevos y quita a los que ya
-- no están. Cierra las estadísticas del cuadro anterior. Devuelve cuántos
-- agentes cambiaron de celda.
function AgentSpatialHash:update(agents)
    -- Estadísticas del cuadro que termina.
    local s = self._stats
    s.activeAgents = self.count
    s.queriesPerFrame = self._queries
    s.candidateChecksPerFrame = self._candidates
    s.maxNeighbours = self._maxNeighbours
    s.averageNeighbours = self._queries > 0 and self._neighbours / self._queries or 0
    self._queries, self._candidates, self._neighbours, self._maxNeighbours = 0, 0, 0, 0
    self.frame = self.frame + 1
    local frame = self.frame
    local size = self.cellSize
    local trackedIndex, xs, ys, rs, cellKey, stamp =
        self.trackedIndex, self.xs, self.ys, self.rs, self.cellKey, self.stamp
    local moved = 0
    local maxRadius = 0
    agents = agents or EMPTY
    for j = 1, #agents do
        local agent = agents[j]
        local i = trackedIndex[agent]
        if not i then
            i = track(self, agent)
        end
        local x, y = positionOf(agent)
        if x == nil or x ~= x or x == math.huge or x == -math.huge then
            x = 0
        end
        if y == nil or y ~= y or y == math.huge or y == -math.huge then
            y = 0
        end
        local r = radiusOf(agent)
        xs[i], ys[i], rs[i] = x, y, r
        local k = key(math.floor(x / size), math.floor(y / size))
        local old = cellKey[i]
        if old ~= k then
            if old then
                removeFromCell(self, old, i)
                moved = moved + 1
            end
            addToCell(self, k, i)
            cellKey[i] = k
        end
        stamp[i] = frame
        if r > maxRadius then
            maxRadius = r
        end
    end
    -- Los que no aparecieron este cuadro se van (recorrido inverso: `untrack`
    -- mueve el último al hueco y ese último ya está revisado).
    for i = self.count, 1, -1 do
        if stamp[i] ~= frame then
            untrack(self, i)
        end
    end
    self.maxRadius = maxRadius
    return moved
end

--- Agentes a `r` (más su propio radio) o menos del punto, sin `exclude`.
-- `out` se vacía y se rellena; si no se da, se usa una lista interna.
function AgentSpatialHash:queryRadius(x, y, r, out, exclude)
    out = out or self._out
    local n = 0
    r = NvUtil.finite(r, 0)
    if r < 0 then
        r = 0
    end
    local reach = r + self.maxRadius
    local size = self.cellSize
    local buckets, tracked, xs, ys, rs = self.buckets, self.tracked, self.xs, self.ys, self.rs
    local excludeIndex = -1
    if exclude ~= nil then
        excludeIndex = self.trackedIndex[exclude] or -1
    end
    local x0, y0 = math.floor((x - reach) / size), math.floor((y - reach) / size)
    local x1, y1 = math.floor((x + reach) / size), math.floor((y + reach) / size)
    local checks = 0
    for cy = y0, y1 do
        for cx = x0, x1 do
            local list = buckets[key(cx, cy)]
            if list then
                local m = #list
                checks = checks + m
                for i = 1, m do
                    local idx = list[i]
                    local dx, dy = xs[idx] - x, ys[idx] - y
                    local range = r + rs[idx]
                    if idx ~= excludeIndex and dx * dx + dy * dy <= range * range then
                        n = n + 1
                        out[n] = tracked[idx]
                    end
                end
            end
        end
    end
    for i = #out, n + 1, -1 do
        out[i] = nil
    end
    if excludeIndex ~= -1 then
        checks = checks - 1 -- el propio agente se lee pero no cuenta como candidato
    end
    self._queries = self._queries + 1
    self._candidates = self._candidates + checks
    self._neighbours = self._neighbours + n
    if n > self._maxNeighbours then
        self._maxNeighbours = n
    end
    return out
end

--- ¿Está indexado?
function AgentSpatialHash:contains(agent)
    return self.trackedIndex[agent] ~= nil
end

--- Quita a un agente sin esperar al siguiente `update`.
function AgentSpatialHash:remove(agent)
    local i = self.trackedIndex[agent]
    if not i then
        return false
    end
    untrack(self, i)
    return true
end

function AgentSpatialHash:clear()
    self.buckets, self.tracked, self.trackedIndex = {}, {}, {}
    self.xs, self.ys, self.rs, self.cellKey, self.stamp = {}, {}, {}, {}, {}
    self.count = 0
    self.maxRadius = 0
    return self
end

--- Estadísticas del último cuadro completo (tabla reutilizada):
-- `activeAgents`, `averageNeighbours`, `maxNeighbours`, `queriesPerFrame`,
-- `candidateChecksPerFrame`.
function AgentSpatialHash:stats()
    return self._stats
end

local function byRowThenColumn(a, b)
    if a.cy ~= b.cy then
        return a.cy < b.cy
    end
    return a.cx < b.cx
end

--- Celdas ocupadas como lista de `{cx=, cy=, n=}`, ordenadas por fila y
-- columna (para el dibujo). Sin `out` reserva una lista nueva; con el `out`
-- de una llamada anterior reutiliza sus tablas de celda (el dibujo de
-- depuración lo pide cada cuadro).
function AgentSpatialHash:cells(out)
    out = out or {}
    local n = 0
    for k, list in pairs(self.buckets) do
        local cy = math.floor(k / STRIDE) - OFFSET
        local cx = k - (cy + OFFSET) * STRIDE - OFFSET
        n = n + 1
        local cell = out[n]
        if type(cell) ~= 'table' then
            cell = {}
            out[n] = cell
        end
        cell.cx, cell.cy, cell.n = cx, cy, #list
    end
    for i = #out, n + 1, -1 do
        out[i] = nil
    end
    table.sort(out, byRowThenColumn)
    return out
end

return AgentSpatialHash

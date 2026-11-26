-- Flow field: un campo de direcciones sobre una rejilla de celdas para que
-- cientos de agentes con el MISMO destino compartan una sola decisión global
-- en vez de una ruta cada uno. Cada celda lleva `integrationCost` (coste
-- acumulado hasta el destino), `direction` (hacia la celda vecina más barata)
-- y `valid` (navegable y desde la que se llega al destino).
--
--   local FlowField = require('runtime.nv.flow_field')
--   local field = FlowField.new(system, route, { cellSize = 32, margin = 32, destination = { x=, y= } })
--   field:build()
--   local dx, dy, valid, cost = field:sample(x, y)   -- dirección unitaria interpolada, o valid = false
--   field:contains(x, y)                            -- ¿cae en una celda válida?
--   field:invalidate()  field:stale()  field:ensure()
--   field:cells()  field:stats()                    -- para depurar (reservan memoria)
--
-- Corredor (sección 8 de la especificación): el campo NO cubre el mundo, solo
-- el corredor de una ruta global (`route`, A* o jerárquica, con sus trozos) y,
-- opcionalmente, la zona de salida del grupo (`opts.startArea`, la caja de
-- los agentes al dar la orden). Se construye así:
--
--   1. Caja: la unión de las cajas de los trozos de la ruta ensanchadas
--      `width/2 + margin` (las rectas de entrada y salida, `lineWidth/2 +
--      margin`), la zona de salida y el destino, ajustada a la rejilla. Si
--      saliera con más de `maxCells` celdas la celda se dobla hasta caber.
--   2. Sellado del corredor: se recorre cada trozo de la ruta cada
--      `cellSize/2` px y se estampa un disco de radio `width/2 + margin`; la
--      celda queda navegable con coste por píxel
--      `segment:cost(agent) / segment.length` (el modelo de coste de
--      `segment.lua` con `costFactor`, terreno, clase y `speedLimit`; la
--      mínima si la cubren varios tramos) y con el `speedLimit` del tramo.
--      Las rectas fuera de la red cuestan `offNetworkCost` por píxel.
--   3. Zona de salida: sus celdas son navegables (coste `offNetworkCost`), y
--      los tramos de la red que caen dentro (índice espacial del sistema) se
--      estampan con su coste: los agentes prefieren la carretera si no es un
--      rodeo, pero pueden cruzar el campo hasta ella, como hace la recta de
--      entrada de una `Route`.
--   4. Bloqueos: una celda navegable fuera de `bounds` (rectángulo del mapa)
--      o con `blocked(x, y, cellSize/2)` (colisión estática del nivel) deja
--      de serlo. Un tramo intransitable para el agente (`cost = ∞`, por
--      ejemplo más estrecho que `agent.width`) no se estampa.
--   5. Integración: Dijkstra desde el destino (todas las celdas navegables a
--      `goalRadius` o menos del destino arrancan a coste 0, y también las de
--      `opts.sources`, los puestos del grupo: así el campo no embudo a todo el
--      mundo hacia un único punto de la carretera sino hacia la zona de los
--      puestos) con 8 vecinos; arista = media de los costes por píxel de las dos celdas ×
--      `cellSize` (× √2 en diagonal); una diagonal solo vale si sus dos
--      ortogonales son navegables (no se cortan esquinas). Lo que no se
--      alcanza queda `valid = false`.
--   6. Dirección: hacia el vecino de menor coste integrado (con empate, el
--      ortogonal antes que el diagonal), unitaria; 0 en el destino.
--
-- `sample(x, y)` interpola bilinealmente la dirección y el coste de las
-- cuatro celdas que rodean el punto (las inválidas no pesan) y normaliza: la
-- dirección cambia de forma continua entre celdas, que es lo que el agente
-- necesita para que su rumbo no salte. Sin celda válida alrededor devuelve
-- `0, 0, false, ∞`; `nearestValid(x, y)` da entonces la dirección hacia la
-- celda válida más cercana (en anillos de hasta `pullRings` celdas) para
-- volver al corredor.
--
-- Cuándo se regenera (`stale`): el campo guarda la versión del sistema al
-- construirse y, por cada tramo bajo su caja, cuántas veces se había
-- reconstruido. Si la versión cambia se comparan: un tramo reconstruido,
-- nuevo o borrado dentro de la caja (una región sucia que toca el corredor)
-- lo deja `stale`; un cambio lejos, no. `invalidate()` lo fuerza. Cambiar el
-- destino o la ruta es un campo nuevo (`group.lua` lo crea por grupo y
-- destino, una vez, no por agente). Un bloqueo nuevo lo debe invalidar quien
-- lo pone (`field:invalidate()`), porque el campo no observa la física.
--
-- Sin `love.*`: el reloj de `buildMs` es el de `NavigationScheduler.detectClock`
-- (una lectura por construcción). Arrays planos (índice = fila·columnas +
-- columna) reutilizados entre construcciones; `sample` no reserva memoria.

local NvUtil = require('runtime.nv.util')
local Heap = require('runtime.nv.heap')
local NavigationScheduler = require('runtime.nv.scheduler')

local FlowField = NvUtil.class('FlowField')

FlowField.defaults = {
    cellSize = 32,
    margin = 32,
    lineWidth = 64, -- ancho de las rectas de entrada/salida de la ruta
    offNetworkCost = 1.5, -- coste por píxel fuera de la red (1 = como una carretera sin penalizar)
    goalRadius = 0, -- 0 = media anchura del tramo de destino (mínimo una celda)
    maxCells = 65536,
    pullRings = 4, -- anillos de celdas que mira `nearestValid`
}

local EMPTY = {}
local SQRT2 = math.sqrt(2)

-- Vecinos: 4 ortogonales primero (empates a favor de la recta), luego diagonales.
local NEIGHBOUR_DX = { 1, -1, 0, 0, 1, -1, 1, -1 }
local NEIGHBOUR_DY = { 0, 0, 1, -1, 1, 1, -1, -1 }

function FlowField:init(system, route, opts)
    opts = opts or EMPTY
    local d = FlowField.defaults
    self.system = system
    self.route = route
    self.cellSize = NvUtil.atLeast(opts.cellSize, d.cellSize, 1)
    self.baseCellSize = self.cellSize
    self.margin = NvUtil.atLeast(opts.margin, d.margin, 0)
    self.lineWidth = NvUtil.atLeast(opts.lineWidth, d.lineWidth, 0)
    self.offNetworkCost = NvUtil.atLeast(opts.offNetworkCost, d.offNetworkCost, 1e-3)
    self.goalRadius = NvUtil.atLeast(opts.goalRadius, d.goalRadius, 0)
    self.maxCells = math.max(16, math.floor(NvUtil.finite(opts.maxCells, d.maxCells)))
    self.pullRings = math.max(1, math.floor(NvUtil.finite(opts.pullRings, d.pullRings)))
    self.agent = type(opts.agent) == 'table' and opts.agent or EMPTY
    local dest = opts.destination or (route and route.goal) or nil
    self.destination = dest and { x = NvUtil.finite(dest.x, 0), y = NvUtil.finite(dest.y, 0) } or nil
    self.sources = type(opts.sources) == 'table' and opts.sources or nil -- { {x=, y=}, ... } a coste 0
    self.startArea = type(opts.startArea) == 'table' and opts.startArea or nil
    self.blocked = type(opts.blocked) == 'function' and opts.blocked or nil
    self.bounds = type(opts.bounds) == 'table' and opts.bounds or nil
    self.clock = type(opts.clock) == 'function' and opts.clock or NavigationScheduler.detectClock()
    -- Rejilla.
    self.ox, self.oy, self.cols, self.rows = 0, 0, 0, 0
    self.count = 0
    self.cellCost = {} -- coste por píxel de cruzar la celda; ∞ = no navegable
    self.integrationCost = {} -- coste acumulado hasta el destino; ∞ = no se llega
    self.dirX, self.dirY = {}, {}
    self.valid = {} -- true si navegable y con camino al destino
    self.speedLimits = {} -- px/s del tramo bajo la celda, 0 = sin límite
    self.validCount = 0
    self.maxCost = 0
    self.goalIndex = nil
    self.built = false
    self.builtVersion = nil
    self.builds = 0
    self.buildMs = 0
    self.segmentStamp = {} -- id → rebuilds del tramo al construir
    self._heap = Heap.new()
    self._ids = {}
end

-- Rejilla -------------------------------------------------------------------------------

--- Índice de la celda que contiene (x, y), o nil fuera de la caja.
function FlowField:cellIndex(x, y)
    local size = self.cellSize
    local col = math.floor((x - self.ox) / size)
    local row = math.floor((y - self.oy) / size)
    if col < 0 or row < 0 or col >= self.cols or row >= self.rows then
        return nil
    end
    return row * self.cols + col + 1, col, row
end

--- Centro de la celda `index`.
function FlowField:cellCenter(index)
    local col = (index - 1) % self.cols
    local row = (index - 1 - col) / self.cols
    return self.ox + (col + 0.5) * self.cellSize, self.oy + (row + 0.5) * self.cellSize
end

--- ¿El punto cae en una celda válida (navegable con camino al destino)?
function FlowField:contains(x, y)
    if not self.built then
        return false
    end
    local i = self:cellIndex(x, y)
    return i ~= nil and self.valid[i] == true
end

--- Coste integrado de la celda bajo el punto (∞ fuera o inválida).
function FlowField:costAt(x, y)
    local i = self:cellIndex(x, y)
    if not i or not self.valid[i] then
        return math.huge
    end
    return self.integrationCost[i]
end

--- Límite de velocidad del tramo bajo el punto (0 = ninguno).
function FlowField:speedLimitAt(x, y)
    local i = self:cellIndex(x, y)
    if not i then
        return 0
    end
    return self.speedLimits[i] or 0
end

-- Construcción ---------------------------------------------------------------------------

local function growBox(box, x, y, w, h)
    if x < box.minX then
        box.minX = x
    end
    if y < box.minY then
        box.minY = y
    end
    if x + w > box.maxX then
        box.maxX = x + w
    end
    if y + h > box.maxY then
        box.maxY = y + h
    end
end

-- Caja del campo: ruta ensanchada, zona de salida y destino.
local function computeBox(self)
    local box = { minX = math.huge, minY = math.huge, maxX = -math.huge, maxY = -math.huge }
    local margin = self.margin
    local route = self.route
    if route then
        for _, piece in ipairs(route.pieces) do
            if piece.kind == 'segment' then
                local b = piece.segment.bounds
                growBox(box, b.x - margin, b.y - margin, b.w + 2 * margin, b.h + 2 * margin)
            else
                local r = self.lineWidth * 0.5 + margin
                local x0, x1 = math.min(piece.x1, piece.x2), math.max(piece.x1, piece.x2)
                local y0, y1 = math.min(piece.y1, piece.y2), math.max(piece.y1, piece.y2)
                growBox(box, x0 - r, y0 - r, x1 - x0 + 2 * r, y1 - y0 + 2 * r)
            end
        end
    end
    local area = self.startArea
    if area then
        growBox(box, area.x - margin, area.y - margin, area.w + 2 * margin, area.h + 2 * margin)
    end
    local dest = self.destination
    if dest then
        growBox(box, dest.x - margin, dest.y - margin, 2 * margin, 2 * margin)
    end
    for _, p in ipairs(self.sources or EMPTY) do
        growBox(box, p.x - margin, p.y - margin, 2 * margin, 2 * margin)
    end
    if box.minX == math.huge then
        box.minX, box.minY, box.maxX, box.maxY = 0, 0, 0, 0
    end
    return box
end

-- Estampa un disco: las celdas cuyo centro queda a `r` o menos de (x, y)
-- pasan a navegables con el coste mínimo y el límite de velocidad dado.
local function stampDisc(self, x, y, r, perPx, speedLimit)
    local size, ox, oy, cols, rows = self.cellSize, self.ox, self.oy, self.cols, self.rows
    local c0 = math.max(0, math.floor((x - r - ox) / size))
    local c1 = math.min(cols - 1, math.floor((x + r - ox) / size))
    local r0 = math.max(0, math.floor((y - r - oy) / size))
    local r1 = math.min(rows - 1, math.floor((y + r - oy) / size))
    local rr = r * r
    local cellCost, limits = self.cellCost, self.speedLimits
    for row = r0, r1 do
        local cy = oy + (row + 0.5) * size
        local dy = cy - y
        for col = c0, c1 do
            local cx = ox + (col + 0.5) * size
            local dx = cx - x
            if dx * dx + dy * dy <= rr then
                local i = row * cols + col + 1
                if perPx < cellCost[i] then
                    cellCost[i] = perPx
                end
                if speedLimit > 0 and (limits[i] == 0 or speedLimit < limits[i]) then
                    limits[i] = speedLimit
                end
            end
        end
    end
end

-- Recorre un tramo (entre las distancias d0 y d1 desde `from`) estampando
-- discos cada media celda.
local function stampSegment(self, seg, d0, d1, agent)
    if not seg.arc or seg.length <= 0 then
        return
    end
    local full = seg:cost(agent)
    if full == math.huge then
        return -- intransitable para este agente: no forma parte del corredor
    end
    local perPx = full / seg.length
    local r = seg.width * 0.5 + self.margin
    local step = self.cellSize * 0.5
    local len = math.abs(d1 - d0)
    local dir = d1 >= d0 and 1 or -1
    local s = 0
    while true do
        local x, y = seg:positionAt(d0 + dir * s)
        stampDisc(self, x, y, r, perPx, seg.speedLimit)
        if s >= len then
            break
        end
        s = math.min(len, s + step)
    end
end

local function stampLine(self, x1, y1, x2, y2)
    local r = self.lineWidth * 0.5 + self.margin
    local step = self.cellSize * 0.5
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local s = 0
    while true do
        local t = len > 0 and s / len or 0
        stampDisc(self, x1 + dx * t, y1 + dy * t, r, self.offNetworkCost, 0)
        if s >= len then
            break
        end
        s = math.min(len, s + step)
    end
end

-- Zona de salida: navegable fuera de la red y con los tramos que caen dentro.
local function stampStartArea(self)
    local area = self.startArea
    if not area then
        return
    end
    local size, ox, oy, cols, rows = self.cellSize, self.ox, self.oy, self.cols, self.rows
    local margin = self.margin
    local c0 = math.max(0, math.floor((area.x - margin - ox) / size))
    local c1 = math.min(cols - 1, math.floor((area.x + area.w + margin - ox) / size))
    local r0 = math.max(0, math.floor((area.y - margin - oy) / size))
    local r1 = math.min(rows - 1, math.floor((area.y + area.h + margin - oy) / size))
    local cellCost, off = self.cellCost, self.offNetworkCost
    for row = r0, r1 do
        for col = c0, c1 do
            local i = row * cols + col + 1
            if off < cellCost[i] then
                cellCost[i] = off
            end
        end
    end
    local system = self.system
    if system and system.segmentIndex then
        local ids = system.segmentIndex:queryRect(
            area.x - margin,
            area.y - margin,
            area.w + 2 * margin,
            area.h + 2 * margin,
            self._ids
        )
        for i = 1, #ids do
            local seg = system.graph:segment(ids[i])
            if seg then
                stampSegment(self, seg, 0, seg.length, self.agent)
            end
        end
    end
end

-- Bloqueos y límites: fuera del mapa o sobre colisión estática no se navega.
local function applyBlocked(self)
    local bounds, blocked = self.bounds, self.blocked
    if not bounds and not blocked then
        return
    end
    local cellCost = self.cellCost
    local half = self.cellSize * 0.5
    for i = 1, self.count do
        if cellCost[i] < math.huge then
            local x, y = self:cellCenter(i)
            if bounds and (x < bounds.x or y < bounds.y or x > bounds.x + bounds.w or y > bounds.y + bounds.h) then
                cellCost[i] = math.huge
            elseif blocked and blocked(x, y, half) then
                cellCost[i] = math.huge
            end
        end
    end
end

-- Celda navegable más cercana a un punto (la suya, o en anillos crecientes
-- hasta `maxRing`).
local function navigableCellNear(self, dest, maxRing)
    local i, col, row = self:cellIndex(dest.x, dest.y)
    local cellCost, cols, rows = self.cellCost, self.cols, self.rows
    if i and cellCost[i] < math.huge then
        return i
    end
    if not i then
        col = math.max(0, math.min(cols - 1, math.floor((dest.x - self.ox) / self.cellSize)))
        row = math.max(0, math.min(rows - 1, math.floor((dest.y - self.oy) / self.cellSize)))
    end
    for ring = 1, maxRing do
        local best, bestSq = nil, math.huge
        for r = row - ring, row + ring do
            for c = col - ring, col + ring do
                if
                    r >= 0
                    and c >= 0
                    and r < rows
                    and c < cols
                    and (r == row - ring or r == row + ring or c == col - ring or c == col + ring)
                then
                    local j = r * cols + c + 1
                    if cellCost[j] < math.huge then
                        local cx, cy = self:cellCenter(j)
                        local sq = (cx - dest.x) ^ 2 + (cy - dest.y) ^ 2
                        if sq < bestSq then
                            best, bestSq = j, sq
                        end
                    end
                end
            end
        end
        if best then
            return best
        end
    end
    return nil
end

-- Dijkstra de integración desde el disco del destino y los puestos.
local function integrate(self)
    local cols, rows, count = self.cols, self.rows, self.count
    local cellCost, integration, valid = self.cellCost, self.integrationCost, self.valid
    local size = self.cellSize
    local heap = self._heap
    heap:clear()
    local goal = self.destination and navigableCellNear(self, self.destination, math.max(cols, rows)) or nil
    self.goalIndex = goal
    if not goal then
        return
    end
    for _, p in ipairs(self.sources or EMPTY) do
        local i = navigableCellNear(self, p, 2)
        if i then
            integration[i] = 0
            heap:push(i, 0)
        end
    end
    local gx, gy = self:cellCenter(goal)
    local dest = self.destination
    local radius = self.goalRadius
    if radius <= 0 then
        radius = size
    end
    local rr = radius * radius
    -- Fuentes: el destino y las celdas navegables a `goalRadius` o menos.
    local gcol = (goal - 1) % cols
    local grow = (goal - 1 - gcol) / cols
    local span = math.ceil(radius / size)
    for row = math.max(0, grow - span), math.min(rows - 1, grow + span) do
        for col = math.max(0, gcol - span), math.min(cols - 1, gcol + span) do
            local i = row * cols + col + 1
            if cellCost[i] < math.huge then
                local cx, cy = self:cellCenter(i)
                local dx, dy = cx - (dest and dest.x or gx), cy - (dest and dest.y or gy)
                if i == goal or dx * dx + dy * dy <= rr then
                    integration[i] = 0
                    heap:push(i, 0)
                end
            end
        end
    end
    local closed = self._closed or {}
    self._closed = closed
    for i = 1, count do
        closed[i] = false
    end
    while not heap:empty() do
        local current, cost = heap:pop()
        if not closed[current] and cost <= integration[current] then
            closed[current] = true
            valid[current] = true
            local col = (current - 1) % cols
            local row = (current - 1 - col) / cols
            local here = cellCost[current]
            for k = 1, 8 do
                local dx, dy = NEIGHBOUR_DX[k], NEIGHBOUR_DY[k]
                local c, r = col + dx, row + dy
                if c >= 0 and r >= 0 and c < cols and r < rows then
                    local other = r * cols + c + 1
                    local otherCost = cellCost[other]
                    if otherCost < math.huge and not closed[other] then
                        local ok = true
                        if k > 4 then
                            -- Diagonal: solo si no corta una esquina bloqueada.
                            local a = row * cols + c + 1
                            local b = r * cols + col + 1
                            ok = cellCost[a] < math.huge and cellCost[b] < math.huge
                        end
                        if ok then
                            local dist = k > 4 and size * SQRT2 or size
                            local tentative = cost + 0.5 * (here + otherCost) * dist
                            if tentative < integration[other] then
                                integration[other] = tentative
                                heap:push(other, tentative)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Dirección de cada celda válida: hacia el vecino más barato.
local function computeDirections(self)
    local cols, rows, count = self.cols, self.rows, self.count
    local cellCost, integration, valid = self.cellCost, self.integrationCost, self.valid
    local dirX, dirY = self.dirX, self.dirY
    local validCount, maxCost = 0, 0
    for i = 1, count do
        if valid[i] then
            validCount = validCount + 1
            local mine = integration[i]
            if mine > maxCost then
                maxCost = mine
            end
            local col = (i - 1) % cols
            local row = (i - 1 - col) / cols
            local best, bx, by = mine, 0, 0
            for k = 1, 8 do
                local dx, dy = NEIGHBOUR_DX[k], NEIGHBOUR_DY[k]
                local c, r = col + dx, row + dy
                if c >= 0 and r >= 0 and c < cols and r < rows then
                    local other = r * cols + c + 1
                    if valid[other] then
                        local ok = true
                        if k > 4 then
                            ok = cellCost[row * cols + c + 1] < math.huge and cellCost[r * cols + col + 1] < math.huge
                        end
                        if ok and integration[other] < best then
                            best, bx, by = integration[other], dx, dy
                        end
                    end
                end
            end
            if bx ~= 0 and by ~= 0 then
                dirX[i], dirY[i] = bx / SQRT2, by / SQRT2
            else
                dirX[i], dirY[i] = bx, by
            end
        end
    end
    self.validCount, self.maxCost = validCount, maxCost
end

-- Guarda el estado de los tramos bajo la caja para `stale`.
local function snapshotSegments(self)
    local stamp = self.segmentStamp
    for k in pairs(stamp) do
        stamp[k] = nil
    end
    local system = self.system
    if not system or not system.segmentIndex then
        return
    end
    local w, h = self.cols * self.cellSize, self.rows * self.cellSize
    local ids = system.segmentIndex:queryRect(self.ox, self.oy, w, h, self._ids)
    for i = 1, #ids do
        local seg = system.graph:segment(ids[i])
        if seg then
            stamp[seg.id] = seg.rebuilds
        end
    end
    self.builtVersion = system.version
end

--- Construye (o reconstruye) el campo. Devuelve el propio campo.
function FlowField:build()
    local t0 = self.clock()
    local box = computeBox(self)
    self.cellSize = self.baseCellSize
    local size = self.cellSize
    local ox, oy = math.floor(box.minX / size) * size, math.floor(box.minY / size) * size
    local cols = math.max(1, math.ceil((box.maxX - ox) / size))
    local rows = math.max(1, math.ceil((box.maxY - oy) / size))
    -- Demasiadas celdas: celda más gruesa hasta caber en `maxCells`.
    while cols * rows > self.maxCells do
        size = size * 2
        self.cellSize = size
        ox, oy = math.floor(box.minX / size) * size, math.floor(box.minY / size) * size
        cols = math.max(1, math.ceil((box.maxX - ox) / size))
        rows = math.max(1, math.ceil((box.maxY - oy) / size))
    end
    self.ox, self.oy, self.cols, self.rows = ox, oy, cols, rows
    local count = cols * rows
    self.count = count
    local cellCost, integration, valid = self.cellCost, self.integrationCost, self.valid
    local dirX, dirY, limits = self.dirX, self.dirY, self.speedLimits
    for i = 1, count do
        cellCost[i], integration[i], valid[i] = math.huge, math.huge, false
        dirX[i], dirY[i], limits[i] = 0, 0, 0
    end
    for i = #cellCost, count + 1, -1 do
        cellCost[i], integration[i], valid[i] = nil, nil, nil
        dirX[i], dirY[i], limits[i] = nil, nil, nil
    end
    -- 2. Corredor de la ruta.
    local route = self.route
    if route then
        for _, piece in ipairs(route.pieces) do
            if piece.kind == 'segment' then
                stampSegment(self, piece.segment, piece.d0, piece.d0 + piece.dir * piece.len, self.agent)
            else
                stampLine(self, piece.x1, piece.y1, piece.x2, piece.y2)
            end
        end
    end
    -- 3. Zona de salida.
    stampStartArea(self)
    -- El destino siempre tiene su celda (la recta final puede medir 0).
    local dest = self.destination
    if dest then
        stampDisc(self, dest.x, dest.y, self.margin, self.offNetworkCost, 0)
    end
    -- 4. Bloqueos. 5. Integración. 6. Direcciones.
    applyBlocked(self)
    integrate(self)
    computeDirections(self)
    snapshotSegments(self)
    self.built = true
    self.builds = self.builds + 1
    self.buildMs = (self.clock() - t0) * 1000
    return self
end

--- Marca el campo para reconstruir en el siguiente `ensure`.
function FlowField:invalidate()
    self.built = false
    return self
end

--- ¿Cambió la red bajo el corredor desde que se construyó? Un cambio lejos
-- del campo no cuenta (y se anota la versión nueva para no volver a mirar).
function FlowField:stale()
    if not self.built then
        return true
    end
    local system = self.system
    if not system or system.version == self.builtVersion then
        return false
    end
    local stamp = self.segmentStamp
    local w, h = self.cols * self.cellSize, self.rows * self.cellSize
    local ids = system.segmentIndex:queryRect(self.ox, self.oy, w, h, self._ids)
    local seen = 0
    for i = 1, #ids do
        local seg = system.graph:segment(ids[i])
        if seg then
            seen = seen + 1
            if stamp[seg.id] ~= seg.rebuilds then
                return true
            end
        end
    end
    local known = 0
    for _ in pairs(stamp) do
        known = known + 1
    end
    if known ~= seen then
        return true -- un tramo nuevo o borrado bajo la caja
    end
    self.builtVersion = system.version
    return false
end

--- Construye si hace falta (nuevo, invalidado o `stale`). Devuelve true si construyó.
function FlowField:ensure()
    if self:stale() then
        self:build()
        return true
    end
    return false
end

-- Consulta -----------------------------------------------------------------------------

--- Dirección unitaria interpolada en (x, y): `dx, dy, valid, cost`. Sin
-- celda válida alrededor: `0, 0, false, ∞`. No reserva memoria.
function FlowField:sample(x, y)
    if not self.built then
        return 0, 0, false, math.huge
    end
    local size, cols, rows = self.cellSize, self.cols, self.rows
    local fx = (x - self.ox) / size - 0.5
    local fy = (y - self.oy) / size - 0.5
    local c0, r0 = math.floor(fx), math.floor(fy)
    local tx, ty = fx - c0, fy - r0
    local valid, dirX, dirY, integration = self.valid, self.dirX, self.dirY, self.integrationCost
    local sx, sy, sc, sw = 0, 0, 0, 0
    for k = 0, 3 do
        local c = c0 + (k % 2)
        local r = r0 + (k >= 2 and 1 or 0)
        if c >= 0 and r >= 0 and c < cols and r < rows then
            local i = r * cols + c + 1
            if valid[i] then
                local w = ((k % 2) == 0 and (1 - tx) or tx) * (k < 2 and (1 - ty) or ty)
                if w > 0 then
                    sx, sy = sx + dirX[i] * w, sy + dirY[i] * w
                    sc, sw = sc + integration[i] * w, sw + w
                end
            end
        end
    end
    if sw <= 0 then
        return 0, 0, false, math.huge
    end
    sx, sy, sc = sx / sw, sy / sw, sc / sw
    local len = math.sqrt(sx * sx + sy * sy)
    if len > 1e-9 then
        sx, sy = sx / len, sy / len
    else
        sx, sy = 0, 0
    end
    return sx, sy, true, sc
end

--- Dirección unitaria hacia el centro de la celda válida más cercana (en
-- anillos de hasta `pullRings` celdas): `dx, dy, true`, o `0, 0, false`.
function FlowField:nearestValid(x, y)
    if not self.built or self.count == 0 then
        return 0, 0, false
    end
    local size, cols, rows = self.cellSize, self.cols, self.rows
    local rings = self.pullRings
    local col = math.floor((x - self.ox) / size)
    local row = math.floor((y - self.oy) / size)
    if col < -rings or row < -rings or col >= cols + rings or row >= rows + rings then
        return 0, 0, false -- más lejos de la caja que los anillos que se miran
    end
    col = math.max(0, math.min(cols - 1, col))
    row = math.max(0, math.min(rows - 1, row))
    local valid = self.valid
    local best, bestSq = nil, math.huge
    for ring = 0, rings do
        for r = row - ring, row + ring do
            if r >= 0 and r < rows then
                for c = col - ring, col + ring do
                    if
                        c >= 0
                        and c < cols
                        and (r == row - ring or r == row + ring or c == col - ring or c == col + ring)
                    then
                        local i = r * cols + c + 1
                        if valid[i] then
                            local cx, cy = self.ox + (c + 0.5) * size, self.oy + (r + 0.5) * size
                            local sq = (cx - x) ^ 2 + (cy - y) ^ 2
                            if sq < bestSq then
                                best, bestSq = i, sq
                            end
                        end
                    end
                end
            end
        end
        if best then
            break
        end
    end
    if not best then
        return 0, 0, false
    end
    local cx, cy = self:cellCenter(best)
    local dx, dy = cx - x, cy - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 1e-9 then
        return 0, 0, true
    end
    return dx / len, dy / len, true
end

-- Depuración -----------------------------------------------------------------------------

--- Lista de celdas `{ col=, row=, x=, y=, dx=, dy=, cost=, cellCost=, valid= }`
-- (reserva memoria: solo para pruebas y dibujo).
function FlowField:cells()
    local out = {}
    for i = 1, self.count do
        local x, y = self:cellCenter(i)
        local col = (i - 1) % self.cols
        out[#out + 1] = {
            index = i,
            col = col,
            row = (i - 1 - col) / self.cols,
            x = x,
            y = y,
            dx = self.dirX[i],
            dy = self.dirY[i],
            cost = self.integrationCost[i],
            cellCost = self.cellCost[i],
            valid = self.valid[i],
        }
    end
    return out
end

--- Resumen: `cols`, `rows`, `cells`, `validCells`, `cellSize`, `maxCost`,
-- `builds`, `buildMs`.
function FlowField:stats()
    return {
        cols = self.cols,
        rows = self.rows,
        cells = self.count,
        validCells = self.validCount,
        cellSize = self.cellSize,
        maxCost = self.maxCost,
        builds = self.builds,
        buildMs = self.buildMs,
    }
end

return FlowField

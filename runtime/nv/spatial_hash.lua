-- Índice espacial por celdas (spatial hash) para nodos y segmentos.
--
--   local SpatialHash = require('runtime.nv.spatial_hash')
--   local index = SpatialHash.new(256)
--   index:insert(id, { x=, y=, w=, h= })       -- la caja se copia
--   index:queryRect(x, y, w, h, out)           -- ids cuyas cajas tocan el rectángulo
--   index:queryRadius(x, y, r, out)            -- ids cuyas cajas quedan a ≤ r del punto
--   local id, dist = index:nearest(x, y, maxDist, accept)
--
-- Cada elemento se apunta en todas las celdas que cruza su caja. Las consultas
-- devuelven ids sin repetir (se marca con un sello por consulta, sin tablas
-- nuevas) y filtradas por la caja real, no solo por celda.
--
-- `nearest` mira la celda del punto y luego anillos crecientes (distancia de
-- Chebyshev 1, 2, 3…). Todo lo que hay en el anillo k+1 queda a por lo menos
-- k·cellSize del punto, así que en cuanto el mejor encontrado está a ≤
-- k·cellSize se puede parar: nunca recorre todo el mundo si hay algo cerca.
-- La distancia es la del punto a la caja (0 si está dentro): para nodos, cuya
-- caja es un punto, es la distancia exacta.

local NvUtil = require('runtime.nv.util')

local SpatialHash = NvUtil.class('SpatialHash')

SpatialHash.defaults = { cellSize = 256 }

-- Clave entera de la celda (cx, cy): sin strings por consulta.
local OFFSET = 2 ^ 20
local STRIDE = 2 ^ 21
local function key(cx, cy)
    return (cy + OFFSET) * STRIDE + (cx + OFFSET)
end

function SpatialHash:init(cellSize)
    self.cellSize = NvUtil.atLeast(cellSize, SpatialHash.defaults.cellSize, 1e-3)
    self.cells = {} -- clave → lista de ids
    self.boxes = {} -- id → { x, y, w, h }
    self.count = 0
    self._stamp = 0
    self._seen = {}
    self._out = {}
end

function SpatialHash:cellOf(v)
    return math.floor(v / self.cellSize)
end

-- Rango de celdas de una caja.
function SpatialHash:cellRange(x, y, w, h)
    local size = self.cellSize
    return math.floor(x / size), math.floor(y / size), math.floor((x + w) / size), math.floor((y + h) / size)
end

local function addToCell(self, k, id)
    local list = self.cells[k]
    if not list then
        list = {}
        self.cells[k] = list
    end
    list[#list + 1] = id
end

local function removeFromCell(self, k, id)
    local list = self.cells[k]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == id then
            list[i] = list[#list]
            list[#list] = nil
        end
    end
    if #list == 0 then
        self.cells[k] = nil
    end
end

--- Inserta (o reemplaza) el elemento `id` con su caja `{x, y, w, h}`.
function SpatialHash:insert(id, bounds)
    if self.boxes[id] then
        self:remove(id)
    end
    local box = {
        x = NvUtil.finite(bounds.x, 0),
        y = NvUtil.finite(bounds.y, 0),
        w = math.max(0, NvUtil.finite(bounds.w, 0)),
        h = math.max(0, NvUtil.finite(bounds.h, 0)),
    }
    self.boxes[id] = box
    self.count = self.count + 1
    local x0, y0, x1, y1 = self:cellRange(box.x, box.y, box.w, box.h)
    for cy = y0, y1 do
        for cx = x0, x1 do
            addToCell(self, key(cx, cy), id)
        end
    end
    return self
end

function SpatialHash:remove(id)
    local box = self.boxes[id]
    if not box then
        return false
    end
    local x0, y0, x1, y1 = self:cellRange(box.x, box.y, box.w, box.h)
    for cy = y0, y1 do
        for cx = x0, x1 do
            removeFromCell(self, key(cx, cy), id)
        end
    end
    self.boxes[id] = nil
    self.count = self.count - 1
    return true
end

--- Mueve un elemento: si sigue en las mismas celdas solo actualiza la caja.
function SpatialHash:update(id, bounds)
    local box = self.boxes[id]
    if not box then
        return self:insert(id, bounds)
    end
    local ax0, ay0, ax1, ay1 = self:cellRange(box.x, box.y, box.w, box.h)
    local nx, ny = NvUtil.finite(bounds.x, 0), NvUtil.finite(bounds.y, 0)
    local nw, nh = math.max(0, NvUtil.finite(bounds.w, 0)), math.max(0, NvUtil.finite(bounds.h, 0))
    local bx0, by0, bx1, by1 = self:cellRange(nx, ny, nw, nh)
    if ax0 == bx0 and ay0 == by0 and ax1 == bx1 and ay1 == by1 then
        box.x, box.y, box.w, box.h = nx, ny, nw, nh
        return self
    end
    self:remove(id)
    return self:insert(id, bounds)
end

function SpatialHash:contains(id)
    return self.boxes[id] ~= nil
end

function SpatialHash:bounds(id)
    return self.boxes[id]
end

function SpatialHash:clear()
    self.cells, self.boxes, self.count = {}, {}, 0
    return self
end

-- Sello nuevo para una consulta.
local function beginQuery(self)
    self._stamp = self._stamp + 1
    if self._stamp > 1e15 then
        self._stamp = 1
        self._seen = {}
    end
    return self._stamp
end

local function overlaps(box, x, y, w, h)
    return box.x <= x + w and box.x + box.w >= x and box.y <= y + h and box.y + box.h >= y
end

-- Distancia de un punto a una caja (0 dentro).
local function boxDistance(box, x, y)
    local dx = 0
    if x < box.x then
        dx = box.x - x
    elseif x > box.x + box.w then
        dx = x - box.x - box.w
    end
    local dy = 0
    if y < box.y then
        dy = box.y - y
    elseif y > box.y + box.h then
        dy = y - box.y - box.h
    end
    return math.sqrt(dx * dx + dy * dy)
end
SpatialHash.boxDistance = boxDistance

--- Ids cuyas cajas tocan el rectángulo. `out` se vacía y se rellena (si no se
-- da, se usa una lista interna reutilizada).
function SpatialHash:queryRect(x, y, w, h, out)
    out = out or self._out
    for i = #out, 1, -1 do
        out[i] = nil
    end
    if w < 0 then
        x, w = x + w, -w
    end
    if h < 0 then
        y, h = y + h, -h
    end
    local stamp = beginQuery(self)
    local seen, boxes, cells = self._seen, self.boxes, self.cells
    local x0, y0, x1, y1 = self:cellRange(x, y, w, h)
    for cy = y0, y1 do
        for cx = x0, x1 do
            local list = cells[key(cx, cy)]
            if list then
                for i = 1, #list do
                    local id = list[i]
                    if seen[id] ~= stamp then
                        seen[id] = stamp
                        if overlaps(boxes[id], x, y, w, h) then
                            out[#out + 1] = id
                        end
                    end
                end
            end
        end
    end
    return out
end

--- Ids cuyas cajas quedan a `r` o menos del punto.
function SpatialHash:queryRadius(x, y, r, out)
    out = out or self._out
    r = math.max(0, r or 0)
    self:queryRect(x - r, y - r, r * 2, r * 2, out)
    local boxes = self.boxes
    for i = #out, 1, -1 do
        if boxDistance(boxes[out[i]], x, y) > r then
            out[i] = out[#out]
            out[#out] = nil
        end
    end
    return out
end

--- El elemento más cercano al punto (distancia a su caja), a no más de
-- `maxDist`. `accept(id)` opcional descarta candidatos. Devuelve id, distancia.
function SpatialHash:nearest(x, y, maxDist, accept)
    if self.count == 0 then
        return nil
    end
    maxDist = maxDist or math.huge
    local size = self.cellSize
    local cx, cy = math.floor(x / size), math.floor(y / size)
    local boxes, cells = self.boxes, self.cells
    local best, bestD = nil, maxDist
    local stamp = beginQuery(self)
    local seen = self._seen
    local function visit(k)
        local list = cells[k]
        if not list then
            return
        end
        for i = 1, #list do
            local id = list[i]
            if seen[id] ~= stamp then
                seen[id] = stamp
                if not accept or accept(id) then
                    local d = boxDistance(boxes[id], x, y)
                    if d <= bestD and (not best or d < bestD) then
                        best, bestD = id, d
                    end
                end
            end
        end
    end
    local ring = 0
    -- Tope de anillos: hasta cubrir maxDist, o todo lo que hay si maxDist es infinito.
    local maxRing = maxDist == math.huge and math.huge or math.ceil(maxDist / size) + 1
    while ring <= maxRing do
        if ring == 0 then
            visit(key(cx, cy))
        else
            for i = -ring, ring do
                visit(key(cx + i, cy - ring))
                visit(key(cx + i, cy + ring))
            end
            for j = -ring + 1, ring - 1 do
                visit(key(cx - ring, cy + j))
                visit(key(cx + ring, cy + j))
            end
        end
        if best and bestD <= ring * size then
            break
        end
        if maxDist == math.huge and ring * size > self:extent() then
            break
        end
        ring = ring + 1
    end
    if not best then
        return nil
    end
    return best, bestD
end

-- Radio que cubre todos los elementos (para no girar sin fin con maxDist = ∞).
function SpatialHash:extent()
    if self._extentCount == self.count and self._extent then
        return self._extent
    end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, box in pairs(self.boxes) do
        if box.x < minX then
            minX = box.x
        end
        if box.y < minY then
            minY = box.y
        end
        if box.x + box.w > maxX then
            maxX = box.x + box.w
        end
        if box.y + box.h > maxY then
            maxY = box.y + box.h
        end
    end
    self._extent = minX == math.huge and 0 or math.max(maxX - minX, maxY - minY) * 2 + self.cellSize * 2
    self._extentCount = self.count
    return self._extent
end

--- Celdas ocupadas, como lista de `{cx, cy, n}` (para el dibujo de depuración).
function SpatialHash:occupiedCells(out)
    out = out or {}
    -- Con `out` de una llamada anterior se reutilizan sus tablas de celda
    -- (el dibujo de depuración lo pide cada cuadro).
    local n = 0
    for k, list in pairs(self.cells) do
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
    return out
end

return SpatialHash

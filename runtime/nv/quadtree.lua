-- Quadtree de regiones para consultas de área en mapas con reparto muy
-- irregular. OPCIONAL: `NavigationSystem` usa el spatial hash para todo; este
-- árbol existe para quien quiera activarlo (`options.quadtree = true`) o
-- usarlo suelto en el juego.
--
--   local Quadtree = require('runtime.nv.quadtree')
--   local tree = Quadtree.new({ x=0, y=0, w=4096, h=4096 }, 8, 6)
--   tree:insert(id, { x=, y=, w=, h= })
--   tree:queryRect(x, y, w, h, out)
--   tree:rebuild({ [id] = bounds, ... })    -- o lista de { id=, bounds= }
--
-- Cada elemento vive en el nodo más profundo que contiene su caja ENTERA; un
-- nodo se divide en cuatro cuando pasa de `capacity` elementos y no ha llegado
-- a `maxDepth`. Lo que se sale de la raíz se queda en la raíz. `remove` sabe
-- en qué nodo está cada id (`where`), sin recorrer el árbol.

local NvUtil = require('runtime.nv.util')

local Quadtree = NvUtil.class('Quadtree')

Quadtree.defaults = { capacity = 8, maxDepth = 6 }

local function newNode(x, y, w, h, depth)
    return { x = x, y = y, w = w, h = h, depth = depth, ids = {}, children = nil }
end

function Quadtree:init(bounds, capacity, maxDepth)
    bounds = bounds or {}
    self.capacity = math.max(1, math.floor(NvUtil.finite(capacity, Quadtree.defaults.capacity)))
    self.maxDepth = math.max(0, math.floor(NvUtil.finite(maxDepth, Quadtree.defaults.maxDepth)))
    self.root = newNode(
        NvUtil.finite(bounds.x, 0),
        NvUtil.finite(bounds.y, 0),
        math.max(1, NvUtil.finite(bounds.w, 1024)),
        math.max(1, NvUtil.finite(bounds.h, 1024)),
        0
    )
    self.boxes = {}
    self.where = {}
    self.count = 0
    self._out = {}
end

local function contains(node, box)
    return box.x >= node.x and box.y >= node.y and box.x + box.w <= node.x + node.w and box.y + box.h <= node.y + node.h
end

local function overlaps(ax, ay, aw, ah, box)
    return box.x <= ax + aw and box.x + box.w >= ax and box.y <= ay + ah and box.y + box.h >= ay
end

local function split(self, node)
    local hw, hh = node.w * 0.5, node.h * 0.5
    local d = node.depth + 1
    node.children = {
        newNode(node.x, node.y, hw, hh, d),
        newNode(node.x + hw, node.y, hw, hh, d),
        newNode(node.x, node.y + hh, hw, hh, d),
        newNode(node.x + hw, node.y + hh, hw, hh, d),
    }
    -- Bajar lo que quepa entero en un hijo.
    local keep = {}
    for _, id in ipairs(node.ids) do
        local box = self.boxes[id]
        local placed = false
        for _, child in ipairs(node.children) do
            if contains(child, box) then
                child.ids[#child.ids + 1] = id
                self.where[id] = child
                placed = true
                break
            end
        end
        if not placed then
            keep[#keep + 1] = id
        end
    end
    node.ids = keep
end

local function insertInto(self, node, id, box)
    if node.children then
        for _, child in ipairs(node.children) do
            if contains(child, box) then
                return insertInto(self, child, id, box)
            end
        end
    end
    node.ids[#node.ids + 1] = id
    self.where[id] = node
    if not node.children and #node.ids > self.capacity and node.depth < self.maxDepth then
        split(self, node)
    end
end

function Quadtree:insert(id, bounds)
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
    insertInto(self, self.root, id, box)
    return self
end

function Quadtree:remove(id)
    local node = self.where[id]
    if not node then
        return false
    end
    for i = #node.ids, 1, -1 do
        if node.ids[i] == id then
            table.remove(node.ids, i)
        end
    end
    self.where[id], self.boxes[id] = nil, nil
    self.count = self.count - 1
    return true
end

function Quadtree:update(id, bounds)
    self:remove(id)
    return self:insert(id, bounds)
end

function Quadtree:contains(id)
    return self.boxes[id] ~= nil
end

-- La raíz nunca se poda: guarda también lo que se sale del mundo.
local function query(self, node, x, y, w, h, out)
    if node ~= self.root and not overlaps(x, y, w, h, node) then
        return
    end
    local boxes = self.boxes
    for _, id in ipairs(node.ids) do
        if overlaps(x, y, w, h, boxes[id]) then
            out[#out + 1] = id
        end
    end
    if node.children then
        for _, child in ipairs(node.children) do
            query(self, child, x, y, w, h, out)
        end
    end
end

--- Ids cuyas cajas tocan el rectángulo.
function Quadtree:queryRect(x, y, w, h, out)
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
    query(self, self.root, x, y, w, h, out)
    return out
end

--- Vacía el árbol y lo rellena con `items`: mapa `id → bounds` o lista de
-- `{ id=, bounds= }`.
function Quadtree:rebuild(items)
    local r = self.root
    self.root = newNode(r.x, r.y, r.w, r.h, 0)
    self.boxes, self.where, self.count = {}, {}, 0
    if type(items) ~= 'table' then
        return self
    end
    local first = items[1]
    if type(first) == 'table' and first.bounds ~= nil then
        for _, item in ipairs(items) do
            self:insert(item.id, item.bounds)
        end
    else
        local ids = {}
        for id in pairs(items) do
            ids[#ids + 1] = id
        end
        table.sort(ids, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, id in ipairs(ids) do
            self:insert(id, items[id])
        end
    end
    return self
end

--- Recorre los nodos del árbol: `fn(node)` con `x, y, w, h, depth, ids`.
function Quadtree:eachNode(fn)
    local function walk(node)
        fn(node)
        if node.children then
            for _, child in ipairs(node.children) do
                walk(child)
            end
        end
    end
    walk(self.root)
end

return Quadtree

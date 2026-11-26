-- Acceso por nombre a lo que hay en un nivel cargado, al estilo Lua/LÖVE.
--
--   local world = require('runtime.world').new(level)
--   local tanke = world.Vehiculos.Tanke          -- capa "Vehiculos", objeto "Tanke"
--   local tanke = world:find('Vehiculos/Tanke')  -- lo mismo, para nombres con espacios
--   tanke.x = tanke.x + 10                       -- mueve tambien el cuerpo de love.physics
--
-- Las capas del mapa son las carpetas. Una capa llamada "Vehiculos/Ligeros" crea el arbol
-- world.Vehiculos.Ligeros, asi que se pueden anidar carpetas sin cambiar el formato del mapa.
local Transform = require('runtime.transform')

local World = {}

local Folder = {}
local Node = {}

local function splitPath(path)
    local parts = {}
    -- La variable de iteración de gmatch es constante en Lua 5.4+, así que
    -- se recorta en otra variable.
    for trozo in tostring(path or ''):gmatch('[^/]+') do
        local part = trozo:gsub('^%s+', ''):gsub('%s+$', '')
        if part ~= '' then
            parts[#parts + 1] = part
        end
    end
    return parts
end

-- Nombre libre dentro de una carpeta: "Tanke", "Tanke 2", "Tanke 3"...
local function freeName(entries, name)
    if not entries[name] then
        return name
    end
    local index = 2
    while entries[name .. ' ' .. index] do
        index = index + 1
    end
    return name .. ' ' .. index
end

--------------------------------------------------------------------------------
-- Node: un objeto colocado en el mapa
--------------------------------------------------------------------------------

Node.__index = function(node, key)
    local method = Node[key]
    if method ~= nil then
        return method
    end
    local data = rawget(node, '_data')
    if key == 'x' or key == 'y' then
        local body = rawget(node, '_world').level.bodyForObject[data]
        if body and not body:isDestroyed() then
            local bx, by = body:getPosition()
            return key == 'x' and bx or by
        end
        return data[key]
    end
    if key == 'angle' then
        local body = rawget(node, '_world').level.bodyForObject[data]
        if body and not body:isDestroyed() then
            return body:getAngle()
        end
        return data.rotation or 0
    end
    if key == 'name' then
        return rawget(node, '_name')
    end
    if key == 'parent' then
        return rawget(node, '_parent')
    end
    if key == 'data' then
        return data
    end
    if key == 'body' then
        return rawget(node, '_world').level.bodyForObject[data]
    end
    -- El agente de navegación (runtime/nv) del objeto, si el nivel lo creo. Solo
    -- lectura, como `body`: `self.obj.navigation:setDestination(x, y)`.
    if key == 'navigation' then
        local agents = rawget(node, '_world').level.agents
        return agents and agents[data] or nil
    end
    return data[key]
end

-- Escribir posicion o angulo mueve tambien el cuerpo fisico, para que el dibujo,
-- las colisiones y el dato no se desincronicen.
Node.__newindex = function(node, key, value)
    local data = rawget(node, '_data')
    local body = rawget(node, '_world').level.bodyForObject[data]
    local alive = body and not body:isDestroyed()
    if key == 'x' then
        data.x = value
        if alive then
            body:setPosition(value, data.y or 0)
        end
    elseif key == 'y' then
        data.y = value
        if alive then
            body:setPosition(data.x or 0, value)
        end
    elseif key == 'angle' then
        data.rotation = value
        if alive then
            body:setAngle(value)
        end
    elseif key == 'name' or key == 'parent' or key == 'data' or key == 'body' or key == 'navigation' then
        error('world: el campo "' .. key .. '" es de solo lectura', 2)
    else
        data[key] = value
    end
end

function Node:path()
    local parts = { rawget(self, '_name') }
    local parent = rawget(self, '_parent')
    while parent and rawget(parent, '_name') do
        table.insert(parts, 1, rawget(parent, '_name'))
        parent = rawget(parent, '_parent')
    end
    return table.concat(parts, '/')
end

function Node:position()
    return self.x, self.y
end

function Node:move(dx, dy)
    self.x = self.x + (dx or 0)
    self.y = self.y + (dy or 0)
end

--- ¿Es de este tipo? Vale el tipo del objeto, su rol RTS (`unit`,
-- `building`…), su tipo RTS (`tank`, `soldier`…) o su tipo de entidad.
function Node:isA(role)
    local data = rawget(self, '_data')
    local rts = data.rts or {}

    -- Sin datos RTS un objeto es decoración (así lo enseña el inspector).
    if role == 'decor' and (rts.role == nil or rts.role == '') then
        return true
    end

    return data.type == role
        or rts.role == role
        or rts.kind == role
        or rts.unitType == role
        or rts.buildingType == role
        or rts.resourceKind == role
        or data.entityType == role
end

--------------------------------------------------------------------------------
-- Colisión en coordenadas de mundo
--
-- La forma es la que el editor dibuja en rojo: la del bloque `collider` del
-- objeto (desplazada, girada y con su tamaño) o, sin bloque, la del sprite.
-- Sigue al objeto: si tiene cuerpo físico, a su posición y giro reales.
--------------------------------------------------------------------------------

--- ¿Tiene colisión? (La misma regla con la que el editor la dibuja.)
function Node:hasCollider()
    local data = rawget(self, '_data')

    if self:isDestroyed() then
        return false
    end

    return data.type == 'collision'
        or data.collisionEnabled == true
        or (data.bodyType ~= nil and data.bodyType ~= 'none')
end

--- Pasa un punto local de la colisión (px del cuerpo) al mundo.
local function toWorld(node, lx, ly)
    local angle = node.angle or 0
    local c, s = math.cos(angle), math.sin(angle)
    return node.x + c * lx - s * ly, node.y + s * lx + c * ly
end

--- Forma de la colisión en el mundo: `{ kind = 'circle', x, y, r }` o
-- `{ kind = 'polygon', points = { x1, y1, x2, y2, ... } }`. nil sin colisión.
function Node:colliderShape()
    if not self:hasCollider() then
        return nil
    end

    local data = rawget(self, '_data')
    local ox, oy, rot, w, h, r = Transform.collider(data)

    if data.shape == 'circle' then
        local x, y = toWorld(self, ox, oy)
        return { kind = 'circle', x = x, y = y, r = r }
    end

    local points = {}

    if data.shape == 'polygon' and type(data.polygon) == 'table' and #data.polygon >= 3 then
        local local_ = Transform.colliderPoints(data)

        for i = 1, #local_, 2 do
            points[#points + 1], points[#points + 2] = toWorld(self, local_[i], local_[i + 1])
        end
    else
        local c, s = math.cos(rot), math.sin(rot)

        for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
            local lx, ly = corner[1] * w / 2, corner[2] * h / 2
            points[#points + 1], points[#points + 2] = toWorld(self, ox + c * lx - s * ly, oy + s * lx + c * ly)
        end
    end

    return { kind = 'polygon', points = points }
end

--- Centro de la colisión en el mundo: el "punto caliente" al que apunta un
-- buscador de calor. Sin colisión, nil.
function Node:heatPoint()
    if not self:hasCollider() then
        return nil
    end

    local data = rawget(self, '_data')
    local ox, oy = Transform.collider(data)
    return toWorld(self, ox, oy)
end

local function pointInPolygon(points, x, y)
    local inside = false
    local n = #points
    local j = n - 1

    for i = 1, n, 2 do
        local ax, ay, bx, by = points[i], points[i + 1], points[j], points[j + 1]

        if ((ay > y) ~= (by > y)) and (x < (bx - ax) * (y - ay) / (by - ay) + ax) then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function segmentDistance2(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local qx, qy = ax + dx * t - px, ay + dy * t - py
    return qx * qx + qy * qy
end

local function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)
    local function side(px, py, qx, qy, rx, ry)
        return (qx - px) * (ry - py) - (qy - py) * (rx - px)
    end

    local d1, d2 = side(cx, cy, dx, dy, ax, ay), side(cx, cy, dx, dy, bx, by)
    local d3, d4 = side(ax, ay, bx, by, cx, cy), side(ax, ay, bx, by, dx, dy)
    return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end

local function circleTouchesPolygon(cx, cy, r, points)
    if pointInPolygon(points, cx, cy) then
        return true
    end

    local n = #points
    local j = n - 1

    for i = 1, n, 2 do
        if segmentDistance2(cx, cy, points[j], points[j + 1], points[i], points[i + 1]) <= r * r then
            return true
        end

        j = i
    end

    return false
end

local function polygonsTouch(a, b)
    if pointInPolygon(b, a[1], a[2]) or pointInPolygon(a, b[1], b[2]) then
        return true
    end

    local na, nb = #a, #b
    local i2 = na - 1

    for i = 1, na, 2 do
        local j2 = nb - 1

        for j = 1, nb, 2 do
            if segmentsCross(a[i2], a[i2 + 1], a[i], a[i + 1], b[j2], b[j2 + 1], b[j], b[j + 1]) then
                return true
            end

            j2 = j
        end

        i2 = i
    end

    return false
end

--- ¿Se tocan las dos formas? Circulos, poligonos (rectangulos girados
-- incluidos, convexos o no) y sus mezclas.
function World.shapesTouch(a, b)
    if not a or not b then
        return false
    end

    if a.kind == 'circle' and b.kind == 'circle' then
        local dx, dy = a.x - b.x, a.y - b.y
        return dx * dx + dy * dy <= (a.r + b.r) ^ 2
    end

    if a.kind == 'circle' then
        return circleTouchesPolygon(a.x, a.y, a.r, b.points)
    end

    if b.kind == 'circle' then
        return circleTouchesPolygon(b.x, b.y, b.r, a.points)
    end

    return polygonsTouch(a.points, b.points)
end

--- ¿Toca la colisión de `other`? Si este objeto no tiene colisión se usa un
-- círculo de `radius` px en su posición (un misil sin forma propia, por ejemplo).
-- `other` sin colisión nunca se toca: no hay nada físico contra lo que chocar.
function Node:touches(other, radius)
    local target = other and other.colliderShape and other:colliderShape()

    if not target then
        return false
    end

    local mine = self:colliderShape()

    if not mine then
        mine = { kind = 'circle', x = self.x, y = self.y, r = math.max(0, tonumber(radius) or 0) }
    end

    return World.shapesTouch(mine, target)
end

function Node:distanceTo(other)
    local ox, oy
    if type(other) == 'table' and getmetatable(other) == Node then
        ox, oy = other.x, other.y
    elseif type(other) == 'table' then
        ox, oy = other.x or other[1], other.y or other[2]
    end
    if not ox or not oy then
        return math.huge
    end
    local dx, dy = self.x - ox, self.y - oy
    return math.sqrt(dx * dx + dy * dy)
end

function Node:destroy()
    local world = rawget(self, '_world')
    local data = rawget(self, '_data')
    world:_remove(self)
    local body = world.level.bodyForObject[data]
    if body and not body:isDestroyed() then
        body:destroy()
    end
    world.level.bodyForObject[data] = nil
    if world.level.agents then
        world.level.agents[data] = nil
    end
    local function drop(list, match)
        for i = #list, 1, -1 do
            if match(list[i]) then
                table.remove(list, i)
            end
        end
    end
    drop(world.level.sprites, function(entry)
        return entry.data == data
    end)
    drop(world.level.drawItems, function(entry)
        return entry.data == data
    end)
    drop(world.level.bodies, function(entry)
        return entry.data == data
    end)
    drop(world.level.entities, function(entity)
        return entity.object == data or entity.obj == data
    end)
    if world.level.agentList then
        drop(world.level.agentList, function(agent)
            return agent.target == self
        end)
    end
    for _, layer in ipairs(world.level.data.layers or {}) do
        drop(layer.objects or {}, function(object)
            return object == data
        end)
    end
    rawset(self, '_destroyed', true)
    return true
end

function Node:isDestroyed()
    return rawget(self, '_destroyed') == true
end

--------------------------------------------------------------------------------
-- Folder: una capa del mapa (o un tramo de una capa con nombre "A/B")
--------------------------------------------------------------------------------

Folder.__index = function(folder, key)
    local method = Folder[key]
    if method ~= nil then
        return method
    end
    if key == 'name' then
        return rawget(folder, '_name')
    end
    if key == 'parent' then
        return rawget(folder, '_parent')
    end
    if key == 'layer' then
        return rawget(folder, '_layer')
    end
    return rawget(folder, '_entries')[key]
end

Folder.__newindex = function(_, key)
    error('world: las carpetas son de solo lectura (no se puede asignar "' .. tostring(key) .. '")', 2)
end

Folder.__len = function(folder)
    return #rawget(folder, '_order')
end

function Folder:path()
    return Node.path(self)
end

function Folder:children()
    local list = {}
    for index, name in ipairs(rawget(self, '_order')) do
        list[index] = rawget(self, '_entries')[name]
    end
    return list
end

function Folder:names()
    local list = {}
    for index, name in ipairs(rawget(self, '_order')) do
        list[index] = name
    end
    return list
end

-- Busca por ruta relativa: folder:find('Ligeros/Tanke'). Devuelve nil si algo del camino falta.
function Folder:find(path)
    local current = self
    for _, part in ipairs(splitPath(path)) do
        if getmetatable(current) ~= Folder then
            return nil
        end
        current = rawget(current, '_entries')[part]
        if current == nil then
            return nil
        end
    end
    if current == self then
        return nil
    end
    return current
end

-- Recorre todo el subarbol. Con `role`, solo los objetos que cumplen Node:isA(role).
function Folder:descendants(role)
    local list = {}
    local function walk(folder)
        for _, child in ipairs(folder:children()) do
            if getmetatable(child) == Folder then
                walk(child)
            elseif not role or child:isA(role) then
                list[#list + 1] = child
            end
        end
    end
    walk(self)
    return list
end

--------------------------------------------------------------------------------
-- World
--------------------------------------------------------------------------------

local WorldMeta = {}
WorldMeta.__index = function(world, key)
    local method = World[key]
    if method ~= nil then
        return method
    end
    return rawget(world, 'root')[key]
end

-- Igual que las carpetas: el arbol se cambia con los objetos, no asignando sobre el.
WorldMeta.__newindex = function(_, key)
    error('world: el arbol es de solo lectura (no se puede asignar "' .. tostring(key) .. '")', 2)
end

local function newFolder(name, parent, layer)
    return setmetatable({ _name = name, _parent = parent, _layer = layer, _entries = {}, _order = {} }, Folder)
end

local function addEntry(folder, name, entry)
    local entries = rawget(folder, '_entries')
    entries[name] = entry
    local order = rawget(folder, '_order')
    order[#order + 1] = name
end

-- Crea (o reutiliza) la carpeta que describe el nombre de una capa: "Vehiculos/Ligeros".
local function folderForLayer(root, layer, index)
    local parts = splitPath(layer.name)
    if #parts == 0 then
        parts = { 'Capa ' .. index }
    end
    local current = root
    for depth, part in ipairs(parts) do
        local entries = rawget(current, '_entries')
        local existing = entries[part]
        if getmetatable(existing) ~= Folder then
            if existing ~= nil then
                part = freeName(entries, part)
            end
            existing = newFolder(part, current, depth == #parts and layer or nil)
            addEntry(current, part, existing)
        elseif depth == #parts then
            rawset(existing, '_layer', layer)
        end
        current = existing
    end
    return current
end

function World.new(level)
    if not level then
        return nil, 'Nivel invalido'
    end
    local world = setmetatable({ level = level, root = newFolder(nil, nil, nil), nodes = {} }, WorldMeta)
    world:rebuild()
    return world
end

function World:rebuild()
    rawset(self, 'root', newFolder(nil, nil, nil))
    local nodes = {}
    rawset(self, 'nodes', nodes)
    local layers = (self.level.data or {}).layers or {}
    for index, layer in ipairs(layers) do
        local folder = folderForLayer(self.root, layer, index)
        for objectIndex, object in ipairs(layer.objects or {}) do
            local name = object.name
            if type(name) ~= 'string' or name:gsub('%s', '') == '' then
                name = (object.type or 'Objeto') .. ' ' .. objectIndex
            end
            name = freeName(rawget(folder, '_entries'), name)
            local node = setmetatable({ _data = object, _name = name, _parent = folder, _world = self }, Node)
            addEntry(folder, name, node)
            nodes[object] = node
        end
    end
    return self
end

function World:addObject(layer, object)
    if type(layer) ~= 'table' or type(object) ~= 'table' then
        return nil
    end
    local layers = (self.level.data or {}).layers or {}
    local index = #layers
    for i, existing in ipairs(layers) do
        if existing == layer then
            index = i
            break
        end
    end
    local folder = folderForLayer(self.root, layer, index)
    local name = object.name
    if type(name) ~= 'string' or name:gsub('%s', '') == '' then
        name = object.type or 'Objeto'
    end
    name = freeName(rawget(folder, '_entries'), name)
    local node = setmetatable({ _data = object, _name = name, _parent = folder, _world = self }, Node)
    addEntry(folder, name, node)
    rawget(self, 'nodes')[object] = node
    return node
end

function World:_remove(node)
    local folder = rawget(node, '_parent')
    if not folder then
        return
    end
    local name = rawget(node, '_name')
    rawget(folder, '_entries')[name] = nil
    local order = rawget(folder, '_order')
    for i = #order, 1, -1 do
        if order[i] == name then
            table.remove(order, i)
        end
    end
    rawget(self, 'nodes')[rawget(node, '_data')] = nil
end

function World:find(path)
    return Folder.find(self.root, path)
end

function World:children()
    return Folder.children(self.root)
end

function World:names()
    return Folder.names(self.root)
end

function World:objects(role)
    return Folder.descendants(self.root, role)
end

function World:nodeFor(object)
    return rawget(self, 'nodes')[object]
end

--- Crea un objeto durante Play usando la misma ruta del level loader que los
-- objetos guardados en el mapa. Devuelve el Node creado, o nil y el motivo.
function World:spawn(asset, x, y, props)
    local level = rawget(self, 'level')
    if not level or type(level.spawnObject) ~= 'function' then
        return nil, 'El nivel no permite crear objetos'
    end
    return level:spawnObject(asset, x, y, props)
end

--- Atajo para destruir por Node o por ruta (`world:destroy('Capa/Objeto')`).
function World:destroy(target)
    local node = target
    if type(target) == 'string' then
        node = self:find(target)
    end
    if getmetatable(node) ~= Node then
        return false
    end
    return node:destroy()
end

-- El objeto mas cercano a `from`, opcionalmente filtrando por rol y por radio maximo.
-- Compara por distancia al cuadrado y solo saca la raiz al final.
--- Objetivos de un buscador de calor: objetos de ese tipo (ver `Node:isA`)
-- que tienen colisión, sin `exclude`. Sin tipo, cualquiera con colisión.
function World:hotTargets(kind, exclude)
    local out = {}

    for _, node in ipairs(self:objects(nil)) do
        if node ~= exclude and node:hasCollider() and (not kind or kind == '' or node:isA(kind)) then
            out[#out + 1] = node
        end
    end

    return out
end

function World:nearest(from, role, maxDistance)
    local fx, fy
    if getmetatable(from) == Node then
        fx, fy = from.x, from.y
    elseif type(from) == 'table' then
        fx, fy = from.x or from[1], from.y or from[2]
    end
    if not fx or not fy then
        return nil
    end
    local limit = maxDistance and maxDistance * maxDistance or math.huge
    local best, bestDistance
    for _, node in ipairs(self:objects(role)) do
        if node ~= from then
            local dx, dy = node.x - fx, node.y - fy
            local distance = dx * dx + dy * dy
            if distance <= limit and (not bestDistance or distance < bestDistance) then
                best, bestDistance = node, distance
            end
        end
    end
    if not best then
        return nil
    end
    return best, math.sqrt(bestDistance)
end

-- Los objetos dentro de un rectangulo del mundo (bordes incluidos).
function World:inRect(x, y, w, h, role)
    local x1, y1 = math.min(x, x + w), math.min(y, y + h)
    local x2, y2 = math.max(x, x + w), math.max(y, y + h)
    local list = {}
    for _, node in ipairs(self:objects(role)) do
        local nx, ny = node.x, node.y
        if nx >= x1 and nx <= x2 and ny >= y1 and ny <= y2 then
            list[#list + 1] = node
        end
    end
    return list
end

World.Node = Node
World.Folder = Folder
World.splitPath = splitPath

return World

-- Caché LRU de rutas entre nodos.
--
--   local PathCache = require('runtime.nv.path_cache')
--   local cache = PathCache.new(256)
--   local key = PathCache.key(systemId, startId, goalId, agentClass, version)
--   local hit = cache:get(key)  or  cache:put(key, result)
--   cache:invalidate()            -- al subir `version` del grafo
--
-- La clave lleva la versión del grafo, así que una ruta vieja nunca coincide
-- con una consulta nueva aunque nadie llame a `invalidate`; `invalidate` solo
-- libera memoria. LRU con lista doblemente enlazada: `get`, `put` y el
-- desalojo son O(1).

local NvUtil = require('runtime.nv.util')

local PathCache = NvUtil.class('PathCache')

PathCache.defaults = { maxEntries = 256 }

function PathCache.key(systemId, startId, goalId, agentClass, version)
    return tostring(systemId)
        .. '|'
        .. tostring(startId)
        .. '|'
        .. tostring(goalId)
        .. '|'
        .. tostring(agentClass or '*')
        .. '|'
        .. tostring(version)
end

function PathCache:init(maxEntries)
    self.maxEntries = math.max(1, math.floor(NvUtil.finite(maxEntries, PathCache.defaults.maxEntries)))
    self.entries = {}
    self.count = 0
    self.hits, self.misses = 0, 0
    -- Lista: head = más reciente, tail = más antiguo.
    self.head, self.tail = nil, nil
end

local function unlink(self, e)
    if e.prev then
        e.prev.next = e.next
    else
        self.head = e.next
    end
    if e.next then
        e.next.prev = e.prev
    else
        self.tail = e.prev
    end
    e.prev, e.next = nil, nil
end

local function pushFront(self, e)
    e.next, e.prev = self.head, nil
    if self.head then
        self.head.prev = e
    end
    self.head = e
    if not self.tail then
        self.tail = e
    end
end

function PathCache:get(key)
    local e = self.entries[key]
    if not e then
        self.misses = self.misses + 1
        return nil
    end
    self.hits = self.hits + 1
    if self.head ~= e then
        unlink(self, e)
        pushFront(self, e)
    end
    return e.value
end

function PathCache:put(key, value)
    local e = self.entries[key]
    if e then
        e.value = value
        if self.head ~= e then
            unlink(self, e)
            pushFront(self, e)
        end
        return value
    end
    e = { key = key, value = value }
    self.entries[key] = e
    pushFront(self, e)
    self.count = self.count + 1
    while self.count > self.maxEntries and self.tail do
        local old = self.tail
        unlink(self, old)
        self.entries[old.key] = nil
        self.count = self.count - 1
    end
    return value
end

function PathCache:has(key)
    return self.entries[key] ~= nil
end

--- Como `get`, pero sin contar acierto ni fallo ni tocar el orden LRU (para
-- las consultas "solo caché" del planificador).
function PathCache:peek(key)
    local e = self.entries[key]
    if not e then
        return nil
    end
    return e.value
end

function PathCache:size()
    return self.count
end

function PathCache:invalidate()
    self.entries, self.count = {}, 0
    self.head, self.tail = nil, nil
    return self
end

--- Recorre las rutas guardadas (de la más reciente a la más antigua).
function PathCache:each(fn)
    local e = self.head
    while e do
        fn(e.key, e.value)
        e = e.next
    end
end

return PathCache

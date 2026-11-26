-- Min-heap binario para la cola de prioridad de A*.
--
--   local Heap = require('runtime.nv.heap')
--   local open = Heap.new()
--   open:push(nodeId, f)
--   local id, f = open:pop()      -- el de menor prioridad
--
-- Se guardan dos listas paralelas (`items`, `priorities`) en vez de una tabla
-- por entrada: `push` no reserva memoria salvo el hueco nuevo del array.
--
-- No hay `decreaseKey`: A* reinserta el nodo con la prioridad menor
-- (`decrease` es un alias de `push`) y al sacarlo comprueba si esa entrada es
-- la vigente (si `g` guardado es menor que el que trae, se descarta). Es la
-- variante "perezosa": el heap puede tener entradas repetidas, pero cada una
-- se procesa como mucho una vez y el coste sigue siendo O(log n) por operación.

local NvUtil = require('runtime.nv.util')

local Heap = NvUtil.class('Heap')

function Heap:init()
    self.items = {}
    self.priorities = {}
    self.n = 0
end

function Heap:size()
    return self.n
end

function Heap:empty()
    return self.n == 0
end

function Heap:clear()
    for i = self.n, 1, -1 do
        self.items[i], self.priorities[i] = nil, nil
    end
    self.n = 0
end

function Heap:push(item, priority)
    local items, pr = self.items, self.priorities
    local i = self.n + 1
    self.n = i
    items[i], pr[i] = item, priority
    -- Subir mientras el padre sea mayor.
    while i > 1 do
        local parent = math.floor(i / 2)
        if pr[parent] <= pr[i] then
            break
        end
        items[parent], items[i] = items[i], items[parent]
        pr[parent], pr[i] = pr[i], pr[parent]
        i = parent
    end
    return self
end

--- Reinserción perezosa: igual que `push`.
Heap.decrease = Heap.push

--- Saca el elemento de menor prioridad: devuelve elemento, prioridad (o nil).
function Heap:pop()
    local n = self.n
    if n == 0 then
        return nil
    end
    local items, pr = self.items, self.priorities
    local top, topPriority = items[1], pr[1]
    items[1], pr[1] = items[n], pr[n]
    items[n], pr[n] = nil, nil
    n = n - 1
    self.n = n
    local i = 1
    while true do
        local left, right = i * 2, i * 2 + 1
        local smallest = i
        if left <= n and pr[left] < pr[smallest] then
            smallest = left
        end
        if right <= n and pr[right] < pr[smallest] then
            smallest = right
        end
        if smallest == i then
            break
        end
        items[smallest], items[i] = items[i], items[smallest]
        pr[smallest], pr[i] = pr[i], pr[smallest]
        i = smallest
    end
    return top, topPriority
end

--- El mínimo sin sacarlo.
function Heap:peek()
    if self.n == 0 then
        return nil
    end
    return self.items[1], self.priorities[1]
end

return Heap

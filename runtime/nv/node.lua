-- Nodo del grafo de navegación: un extremo, cruce o intersección de rutas.
--
--   local NavigationNode = require('runtime.nv.node')
--   local n = NavigationNode.new(id, x, y, metadata)
--   n.connections      -- lista de ids de segmento que tocan este nodo
--
-- Los puntos intermedios de una curva NO son nodos: pertenecen al segmento.
-- El id es un entero estable que asigna el grafo; nunca un índice de lista.

local NvUtil = require('runtime.nv.util')

local NavigationNode = NvUtil.class('NavigationNode')

function NavigationNode:init(id, x, y, metadata)
    self.id = id
    self.x = NvUtil.finite(x, 0)
    self.y = NvUtil.finite(y, 0)
    self.connections = {}
    self.metadata = type(metadata) == 'table' and metadata or {}
end

--- Apunta un segmento (idempotente).
function NavigationNode:connect(segmentId)
    for _, id in ipairs(self.connections) do
        if id == segmentId then
            return false
        end
    end
    self.connections[#self.connections + 1] = segmentId
    return true
end

function NavigationNode:disconnect(segmentId)
    for i = #self.connections, 1, -1 do
        if self.connections[i] == segmentId then
            table.remove(self.connections, i)
            return true
        end
    end
    return false
end

function NavigationNode:isConnected(segmentId)
    for _, id in ipairs(self.connections) do
        if id == segmentId then
            return true
        end
    end
    return false
end

--- Cuántos segmentos tocan el nodo.
function NavigationNode:degree()
    return #self.connections
end

--- Caja envolvente puntual (para el índice espacial).
function NavigationNode:bounds()
    return self.x, self.y, 0, 0
end

return NavigationNode

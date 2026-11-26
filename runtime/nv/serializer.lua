-- Guardado y carga de las redes de navegación. Formato versionado:
--
--   {
--     format = 'practicalove2d-navigation', version = 1, nextSystemId = 3,
--     systems = {
--       { id = 1, name = 'TankNavigation', nextNodeId = 12, nextSegmentId = 9,
--         options = { cellSize = 256, maxProjectDistance = 400 },     -- opcional
--         nodes = { { id = 1, x = 100, y = 200, metadata = {} }, ... },
--         segments = { { id = 1, from = 1, to = 2, points = { {x=,y=}, ... }, rawPoints = nil,
--                        width = 64, oneWay = false, speedLimit = 0, costFactor = 1, metadata = {} }, ... } },
--     },
--   }
--
-- Solo se guardan los datos editables: la spline, la tabla de arco, la
-- curvatura, la caja y los costes se recalculan al cargar (`rebuild`). Así un
-- cambio de algoritmo nunca deja un mapa viejo inservible. Todo son listas y
-- claves con nombre: pasa por `src/util.lua` `serialize` y por JSON tal cual.
--
--   Serializer.toData(manager, { keepRaw = false })  -- `rawPoints` solo con keepRaw
--   Serializer.fromData(data, manager)               -- rellena un manager; tipos malos → valores por defecto
--   Serializer.migrate(data)                         -- versiones viejas → la actual

local NvUtil = require('runtime.nv.util')

local Serializer = {}

Serializer.FORMAT = 'practicalove2d-navigation'
Serializer.VERSION = 1

local function pointList(points)
    local out = {}
    for i, p in ipairs(points or {}) do
        out[i] = { x = p.x, y = p.y }
    end
    return out
end

--- Datos de un solo sistema.
function Serializer.systemToData(system, opts)
    opts = opts or {}
    local data = {
        id = system.id,
        name = system.name,
        nextNodeId = system.graph.nextNodeId,
        nextSegmentId = system.graph.nextSegmentId,
        options = {
            cellSize = system.options.cellSize,
            maxProjectDistance = system.options.maxProjectDistance,
            hierarchical = system.options.hierarchical, -- 'auto' | true | false
            hierarchicalThreshold = system.options.hierarchicalThreshold,
            hierarchicalMinRegions = system.options.hierarchicalMinRegions,
            clusterSize = system.options.clusterSize,
        },
        nodes = {},
        segments = {},
    }
    for _, node in ipairs(system.graph:nodes()) do
        data.nodes[#data.nodes + 1] =
            { id = node.id, x = node.x, y = node.y, metadata = NvUtil.deepCopy(node.metadata) }
    end
    for _, seg in ipairs(system.graph:segments()) do
        local entry = {
            id = seg.id,
            from = seg.from,
            to = seg.to,
            points = pointList(seg.points),
            width = seg.width,
            oneWay = seg.oneWay,
            speedLimit = seg.speedLimit,
            costFactor = seg.costFactor,
            metadata = NvUtil.deepCopy(seg.metadata),
        }
        if opts.keepRaw and seg.rawPoints then
            entry.rawPoints = pointList(seg.rawPoints)
        end
        data.segments[#data.segments + 1] = entry
    end
    return data
end

function Serializer.toData(manager, opts)
    local data =
        { format = Serializer.FORMAT, version = Serializer.VERSION, nextSystemId = manager.nextSystemId, systems = {} }
    for _, system in ipairs(manager:systems()) do
        data.systems[#data.systems + 1] = Serializer.systemToData(system, opts)
    end
    return data
end

--- Lleva datos de versiones anteriores a la actual. Hoy solo hay la 1; una
-- versión desconocida (más nueva) se deja tal cual y se carga con tolerancia.
function Serializer.migrate(data)
    if type(data) ~= 'table' then
        return { format = Serializer.FORMAT, version = Serializer.VERSION, systems = {} }
    end
    local version = NvUtil.finite(data.version, 0)
    if version < 1 then
        data.version = 1
    end
    data.format = Serializer.FORMAT
    if type(data.systems) ~= 'table' then
        data.systems = {}
    end
    return data
end

-- Carga un sistema en el manager. Nunca lanza: lo que no se entiende se salta.
local function loadSystem(manager, entry)
    if type(entry) ~= 'table' then
        return nil
    end
    local name = entry.name
    if type(name) ~= 'string' or name == '' then
        name = 'Navigation' .. tostring(NvUtil.finite(entry.id, manager.nextSystemId))
    end
    local options = type(entry.options) == 'table' and NvUtil.shallowCopy(entry.options) or {}
    options.id = NvUtil.finite(entry.id)
    local system = manager:addSystem(name, options)
    if not system then
        return nil
    end
    local graph = system.graph
    graph.deferRebuild = true
    for _, n in ipairs(type(entry.nodes) == 'table' and entry.nodes or {}) do
        if type(n) == 'table' then
            graph:addNode(
                NvUtil.finite(n.x, 0),
                NvUtil.finite(n.y, 0),
                NvUtil.finite(n.id),
                type(n.metadata) == 'table' and n.metadata or nil
            )
        end
    end
    for _, s in ipairs(type(entry.segments) == 'table' and entry.segments or {}) do
        if type(s) == 'table' then
            local from, to = NvUtil.finite(s.from), NvUtil.finite(s.to)
            if from and to and graph:node(from) and graph:node(to) then
                graph:addSegment(from, to, s.points, {
                    id = NvUtil.finite(s.id),
                    width = s.width,
                    oneWay = s.oneWay,
                    speedLimit = s.speedLimit,
                    costFactor = s.costFactor,
                    metadata = type(s.metadata) == 'table' and s.metadata or nil,
                    rawPoints = type(s.rawPoints) == 'table' and s.rawPoints or nil,
                })
            end
        end
    end
    local nextNode = NvUtil.finite(entry.nextNodeId, 0)
    if nextNode > graph.nextNodeId then
        graph.nextNodeId = math.floor(nextNode)
    end
    local nextSegment = NvUtil.finite(entry.nextSegmentId, 0)
    if nextSegment > graph.nextSegmentId then
        graph.nextSegmentId = math.floor(nextSegment)
    end
    graph.deferRebuild = false
    system:rebuild()
    return system
end

--- Rellena `manager` con los sistemas de `data`. Devuelve el manager.
function Serializer.fromData(data, manager)
    data = Serializer.migrate(data)
    for _, entry in ipairs(data.systems) do
        loadSystem(manager, entry)
    end
    local nextSystem = NvUtil.finite(data.nextSystemId, 0)
    if nextSystem > manager.nextSystemId then
        manager.nextSystemId = math.floor(nextSystem)
    end
    return manager
end

return Serializer

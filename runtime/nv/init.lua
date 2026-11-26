-- NV: fachada del sistema de navegación por rutas dibujadas.
--
--   local NV = require('runtime.nv')
--   local nav = NV.load(map)                       -- NavigationManager desde map.navigation (o vacío),
--                                                  -- con planificador de rutas (NV.load(map, { scheduler = false }) sin él)
--   local agent = NV.Agent.new(nav, node, NV.agentProps(object))
--   local flags = NV.defaultFlags()                 -- todos los flags de depuración a false
--
-- Pipeline: dibujo → muestras por distancia (`Simplify.sampleByDistance`) →
-- RDP (`Simplify.rdp`) → Catmull-Rom (`CatmullRom`) → tabla de arco
-- (`ArcLength`) → curvatura (`Curvature`) → `Segment` → índices (`SpatialHash`,
-- `Quadtree`) → `Graph` → `AStar` / `Hierarchical` → `PathCache` → `Agent` →
-- look-ahead (`PathFollower`) → `Steering` (+ `LocalAvoidance`, `Group`).
-- Escala: `AgentSpatialHash` (vecinos solo cercanos), `Scheduler` (rutas con
-- presupuesto por cuadro), `SlotValidator` (puestos válidos), `Profiler`,
-- `Hierarchical` v2 (regiones con portales), `FlowField` (campo de
-- direcciones en el corredor de la ruta global para los grupos masivos) y el
-- LOD de navegación del manager (`setFocus`, `setSelected`).
--
-- Cada módulo se puede `require` suelto (`runtime.nv.<módulo>`); este archivo
-- solo los reúne. Todo el runtime, incluida esta carpeta, se copia al juego.

local NV = {}

NV.Util = require('runtime.nv.util')
NV.Vector2 = require('runtime.nv.vector2')
NV.Simplify = require('runtime.nv.simplify')
NV.CatmullRom = require('runtime.nv.catmull_rom')
NV.ArcLength = require('runtime.nv.arc_length')
NV.Curvature = require('runtime.nv.curvature')
NV.Heap = require('runtime.nv.heap')
NV.Node = require('runtime.nv.node')
NV.Segment = require('runtime.nv.segment')
NV.Graph = require('runtime.nv.graph')
NV.SpatialHash = require('runtime.nv.spatial_hash')
NV.Quadtree = require('runtime.nv.quadtree')
NV.AStar = require('runtime.nv.astar')
NV.PathCache = require('runtime.nv.path_cache')
NV.Hierarchical = require('runtime.nv.hierarchical')
NV.FlowField = require('runtime.nv.flow_field')
NV.Route = require('runtime.nv.route')
NV.System = require('runtime.nv.system')
NV.Serializer = require('runtime.nv.serializer')
NV.Manager = require('runtime.nv.manager')
NV.Steering = require('runtime.nv.steering')
NV.PathFollower = require('runtime.nv.path_follower')
NV.LocalAvoidance = require('runtime.nv.local_avoidance')
NV.Agent = require('runtime.nv.agent')
NV.Group = require('runtime.nv.group')
NV.DestinationSlots = NV.Group.DestinationSlots
NV.FormationController = NV.Group.FormationController
NV.GroupNavigation = NV.Group.GroupNavigation
NV.GroupNavigationRequest = NV.Group.GroupNavigationRequest
NV.Commands = require('runtime.nv.commands')
NV.MoveCommand = NV.Commands.MoveCommand
NV.CommandSystem = NV.Commands.CommandSystem
NV.AgentSpatialHash = require('runtime.nv.agent_spatial_hash')
NV.SlotValidator = require('runtime.nv.slot_validator')
NV.Scheduler = require('runtime.nv.scheduler')
NV.Profiler = require('runtime.nv.profiler')
NV.Debug = require('runtime.nv.debug')

--- Manager desde los datos del mapa (`mapData.navigation`); sin ellos, vacío.
-- En el juego las rutas van programadas (`manager.scheduler`, presupuesto por
-- cuadro); `options.scheduler = false` lo deja síncrono y
-- `options.scheduler = { maxRequestsPerFrame=, maxPathfindingTimeMs= }` lo ajusta.
-- `options.strategy = { mediumFrom=, massiveFrom= }` y `options.flowField =
-- { cellSize=, margin= ... }` ajustan la estrategia de los grupos (`group.lua`).
-- `options.lod = { nearDistance=, farDistance= ... }` ajusta el LOD de
-- navegación (`manager.lua`) y `options.lod = false` lo apaga.
function NV.load(mapData, options)
    options = type(options) == 'table' and options or {}
    local data = type(mapData) == 'table' and mapData.navigation or nil
    local managerOptions = {}
    if type(options.strategy) == 'table' then
        managerOptions.strategy = options.strategy
    end
    if type(options.flowField) == 'table' then
        managerOptions.flowField = options.flowField
    end
    if type(options.lod) == 'table' or options.lod == false then
        managerOptions.lod = options.lod
    end
    local manager
    if type(data) ~= 'table' then
        manager = NV.Manager.new(managerOptions)
    else
        manager = NV.Manager.fromData(data, managerOptions)
    end
    if options.scheduler ~= false then
        manager:enableScheduler(type(options.scheduler) == 'table' and options.scheduler or nil)
    end
    return manager
end

--- ¿El mapa trae alguna red?
function NV.hasNetworks(mapData)
    local data = type(mapData) == 'table' and mapData.navigation or nil
    return type(data) == 'table' and type(data.systems) == 'table' and #data.systems > 0
end

--- Propiedades de agente a partir del componente `object.navigation`
-- (`tag` obligatorio; el resto opcional), con estos respaldos:
--   maxSpeed     ← navigation.maxSpeed, properties.velocidad, rts.speed
--   orientacion  ← navigation.orientacion, properties.orientacion (90 por defecto)
--   radius       ← navigation.radius, la mitad del lado mayor del sprite escalado
--   class        ← navigation.class, rts.kind, el propio tag
-- Devuelve nil si el objeto no lleva componente con tag.
function NV.agentProps(object)
    if type(object) ~= 'table' then
        return nil
    end
    local nav = object.navigation
    if type(nav) ~= 'table' then
        return nil
    end
    local tag = nav.tag or nav.navigationTag
    if type(tag) ~= 'string' or tag == '' then
        return nil
    end
    local props = NV.Util.shallowCopy(nav)
    props.navigationTag, props.tag = tag, tag
    local properties = type(object.properties) == 'table' and object.properties or {}
    local rts = type(object.rts) == 'table' and object.rts or {}
    if props.maxSpeed == nil then
        props.maxSpeed = tonumber(properties.velocidad) or tonumber(rts.speed)
    end
    if props.orientacion == nil then
        props.orientacion = tonumber(properties.orientacion)
    end
    if props.radius == nil then
        local w = math.abs((tonumber(object.w) or 0) * (tonumber(object.scaleX) or 1))
        local h = math.abs((tonumber(object.h) or 0) * (tonumber(object.scaleY) or 1))
        local r = math.max(w, h) * 0.5
        if r > 0 then
            props.radius = r
        end
    end
    if props.class == nil then
        props.class = rts.kind
    end
    return NV.Agent.normalizeProps(props)
end

--- Flags de depuración, todos a false.
function NV.defaultFlags()
    return NV.Debug.flags(false)
end

return NV

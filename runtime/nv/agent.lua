-- Agente de navegación: mueve un objeto por la red de su tag.
--
--   local NavigationAgent = require('runtime.nv.agent')
--   local agent = NavigationAgent.new(manager, target, { navigationTag = 'TankNavigation', maxSpeed = 120 })
--   agent:setDestination(x, y)     -- true, o false y el motivo
--   agent:setDestination(x, y, { immediate = true, priority = 'selected' })
--   agent:update(dt)               -- lo mueve: escribe target.x, target.y, target.angle
--   agent:getState()               -- 'idle' | 'pending' | 'moving' | 'arrived' | 'blocked' | 'noroute'
--   agent:getCongestionState()     -- 'moving' | 'slow' | 'locallyBlocked' | 'stuck' | 'repathPending'
--   agent:stop()  agent:clearDestination()  agent:isMoving()  agent:isPending()  agent:getCurrentPath()
--
-- `target` es cualquier tabla con `x`, `y` y `angle` legibles y escribibles:
-- el `Node` de `runtime/world.lua` (que mueve también el cuerpo físico) o una
-- tabla plana en las pruebas. El rumbo visual es `angle = heading +
-- rad(orientacion)`, como en `runtime/units.lua`.
--
-- Cada `update`:
--
--   1. `autoRepath`: si cambió la versión del grafo o si la unidad se desvió más
--      de `maxDeviation` de su ruta, se pide la ruta otra vez (`repathReason`
--      dice por qué; el bloqueo lo decide la detección de atascos, abajo);
--   2. el seguidor reproyecta la posición real sobre la ruta y da el objetivo
--      adelantado a `lookAheadDistance`;
--   3. velocidad preferida = min(maxSpeed, velocidad por curvatura en los
--      próximos `2·lookAheadDistance` px si `avoidSharpTurns`, límite del
--      segmento, velocidad de llegada `sqrt(2·braking·(dist − stoppingDistance))`);
--   4. detección de atascos (`props.congestion`, por defecto sí; ver abajo);
--      dirección deseada = hacia el objetivo adelantado
--        + corrección de formación (hacia `formationTarget`, peso `formationWeight`;
--          con v2 solo en espacio libre: con un vecino a menos de un radio no tira)
--        + carril derecho si viene de frente otro grupo (ver "Contraflujo");
--   5. esquiva local:
--        v1 (`props.avoidance = 'v1'`): dirección += esquiva · `avoidanceWeight`,
--        giro acotado y rapidez = la preferida, 0 si el objetivo queda a 90° o
--        más (gira en el sitio, como `Units.step`);
--        v2 (por defecto): velocidad preferida → `LocalAvoidance:safeVelocity`
--        (semiplanos tipo ORCA con los vecinos y el borde del tramo) → giro
--        acotado hacia la velocidad segura (o hacia su opuesta, marcha atrás,
--        si hay que retroceder para esquivar o para ceder el paso) → la
--        rapidez es la que cumple los semiplanos a lo largo del rumbo real
--        (`speedAlong`), entre `−reverseSpeed` y `maxSpeed`;
--      el giro siempre está acotado a `ω = max(|v|, 0,3·maxSpeed) / turningRadius` rad/s;
--   6. la velocidad se acerca a la objetivo a `acceleration` / `braking` (v2
--      frena al doble si la esquiva lo pide), se avanza `v·dt` en el rumbo sin
--      pasarse del destino y se escribe el objeto;
--   7. a `stoppingDistance` o menos del destino: `arrived`.
--
-- Prioridades de movimiento (spec §9): 1) no chocar (los semiplanos de los
-- vecinos), 2) seguir en la red (el semiplano del borde del tramo, que cede si
-- con él no hay velocidad sin choque), 3) avanzar (la velocidad segura es la
-- más cercana a la preferida), 4) formación (ya va dentro de la preferida,
-- con poco peso, solo en espacio libre, y se relaja en un atasco).
--
-- Atascos (`agent.congestion`, spec §10). Cada `congestionWindow` s (0,5) se
-- compara el PROGRESO real (lo que avanzó la distancia a lo largo de la ruta,
-- o lo que bajó el coste del flow field, o la distancia al puesto en la recta
-- final) con la velocidad PREFERIDA media de la ventana:
--
--   preferida < 20 % de maxSpeed (frena para llegar, gira en el sitio)  → 'moving'
--     (salvo a `crowdArrivalRadius` o menos del puesto: ahí cualquiera cuenta)
--   progreso ≥ 50 % de la preferida                                     → 'moving' (todo a cero)
--   progreso ≥ 15 %                                                     → 'slow'
--   menos                                                               → 'locallyBlocked'
--
-- El tiempo bloqueado acumulado (`blockedTime`) sube las acciones de una en
-- una, nunca de golpe (`stuckAfter` = 2 s por defecto):
--
--   desde la primera ventana bloqueada   'locallyBlocked': la esquiva (v2: los semiplanos;
--                                        v1: el vector) ya actúa en cada cuadro
--   ≥ 0,5 · stuckAfter                   relajar la formación (deja de tirar) y, dentro
--                                        de la zona de puestos de su grupo, cambiar su
--                                        puesto por uno libre más cercano
--                                        (`GroupNavigationRequest:swapNearestSlot`)
--   ≥ 0,75 · stuckAfter                  ceder el paso: `negotiateYield` (abajo), fuera de
--                                        la zona de puestos (ahí no hay cruce que ceder)
--   ≥ stuckAfter                         'stuck': si está a `crowdArrivalRadius` o menos
--                                        de su puesto, llega ahí mismo (`congestion.crowdArrival`);
--                                        si no, con ruta propia y `autoRepath`, repite la
--                                        búsqueda ('bloqueo'), como mucho `maxStuckRepaths`
--                                        veces seguidas y con `repathCooldown` s entre dos;
--                                        con planificador queda 'repathPending' hasta que
--                                        llega la ruta. Un agente de flow field no repite
--                                        búsqueda (el campo es del grupo): sigue 'stuck'.
--
-- Un par de cuadros de congestión nunca llega a nada: la primera medida es al
-- cerrar una ventana entera y el repath necesita `stuckAfter` s seguidos sin
-- progreso. Con `props.congestion = false` no hay escalera: repite la
-- búsqueda cuando `LocalAvoidance.blockedFor` pasa de `repathAfter` (lo de
-- antes de la fase E).
--
-- Contraflujo: si por delante viene de frente un agente de otro grupo
-- (direcciones preferidas opuestas, dentro de `avoidanceRadius`), durante
-- 1 s el agente tira hacia su mitad derecha del tramo (con ruta: hacia un
-- carril a ¼ del ancho a la derecha de su avance, salvo en un tramo donde
-- no caben dos carriles, `< 4·radius + 2·margen`, que es cosa de la cesión;
-- con flow field: un sesgo suave a la derecha) y no tira de la formación. Dos columnas densas de
-- frente se ordenan en dos carriles en vez de trabarse. No actúa dentro de la
-- zona de puestos de su grupo (varios grupos que llegan al mismo sitio desde
-- lados opuestos no están cruzándose).
--
-- Hacer sitio (v2 con atascos): un agente llegado no se mueve, así que para
-- la esquiva es un obstáculo fijo; pero si uno en marcha se le echa encima
-- (lo marca `nudged` la esquiva v2), en su siguiente `update` da un paso de
-- esquiva v2 compartiendo el desvío (`makingWay`, sin dejar de estar
-- 'arrived') y después vuelve despacio a donde llegó (`holdX`, `holdY`). Sin
-- nadie encima y en su sitio no cuesta nada.
--
-- Ceder el paso (spec §11): `movementPriority` (props, 0 por defecto) y, a
-- igualdad, la orden más antigua (`orderSerial`, uno por grupo de
-- `group.lua` o por `setDestination`) tienen prioridad. En `negotiateYield`
-- el agente mira a los vecinos de OTRO grupo que le cierran el paso por
-- delante: si alguno tiene prioridad, cede (`yieldState = 'yielding'`); si
-- no, él pasa a 'priority' y hace ceder a los otros. El que cede se aparta
-- de los que tienen prioridad (marcha atrás a `reverseSpeed` si hace falta),
-- asume el 80 % de cada desvío de la esquiva v2, no respeta el borde del
-- tramo y congela su reloj de atasco; sus compañeros de grupo que vienen
-- detrás y lo ven ceder también ceden (la cesión se propaga por la columna;
-- la "presión" nace en un rival con prioridad y se gasta por el camino, así
-- que dos compañeros no se quedan cediendo el uno al otro). Termina cuando pasan `yieldTime` s y lleva 0,5 s
-- sin nadie con prioridad cerca (o a los `maxYieldTime` s); entonces
-- `PathFollower:rewindTo` recoloca su distancia sobre la ruta.
--
-- `lateralAccel` por defecto es `maxSpeed² / (4·turningRadius)`: a toda
-- velocidad toma curvas de radio ≥ 4·turningRadius y en su radio mínimo va a
-- la mitad.
--
-- Vecinos para la esquiva local: si el manager tiene un índice de agentes
-- (`manager.agentIndex`, un `AgentSpatialHash` que el nivel actualiza una vez
-- por cuadro) o el agente lleva el suyo (`agent.spatialHash`), cada `update`
-- consulta SOLO los agentes a `avoidanceRadius` o menos (más el radio de cada
-- vecino) en un buffer propio reutilizado (`agent._neighbours`, sin reservar
-- memoria por cuadro). Sin índice vale la lista `agent.neighbours` de siempre
-- (todos contra todos; solo para pruebas pequeñas). `avoidanceRadius` por
-- defecto es `max(2·radius + margen, radius + margen + maxSpeed·horizonte)`:
-- lo que la predicción de `LocalAvoidance` puede llegar a mirar.
--
-- Rutas programadas: si el manager tiene planificador (`manager.scheduler`,
-- ver `runtime/nv/scheduler.lua`), `setDestination` proyecta origen y destino
-- en el acto (fallo inmediato si no se llega a la red), pide la ruta al
-- planificador y deja al agente en `'pending'`: no se mueve ni tiembla hasta
-- que llega la ruta (o sale de la caché, que es inmediato). Un `autoRepath`
-- con planificador sigue la ruta vieja mientras espera la nueva. Una orden
-- nueva, `stop` o `clearDestination` cancelan la petición pendiente.
-- `setDestination(x, y, { immediate = true })` conserva el comportamiento
-- síncrono (también es lo que pasa sin planificador).
--
-- Flow field (grupos masivos, ver `runtime/nv/flow_field.lua` y `group.lua`):
-- `agent:followFlowField(field, x, y, opts)` sustituye el `PathFollower` por
-- el campo: no hay spline, así que la dirección deseada es la del campo en la
-- posición del agente promediada con la de `lookAheadDistance` px por delante
-- (muestras bilineales entre celdas vecinas), y la curvatura que frena es el
-- giro entre esas dos muestras repartido en esa distancia, `k ≈ Δθ /
-- lookAheadDistance`. A `fieldSwitchRadius` o menos del puesto (o si el
-- campo no da dirección, que es lo que pasa en el disco del destino) el
-- agente va recto a su puesto; fuera del corredor tira hacia la celda válida
-- más cercana. La esquiva, el giro acotado, la aceleración y la llegada son
-- los de siempre; la formación no actúa (cada uno va a su puesto) y no hay
-- `autoRepath` por versión ni por desvío: el campo lo regenera el grupo.
-- `getCurrentPath()` devuelve la ruta global compartida del grupo y
-- `agent.flowField` el campo. `awaitFlowField(x, y)` deja al agente
-- 'pending' (quieto) mientras el grupo espera la ruta global.
--
-- LOD de navegación (fase F, ver `manager.lua` y `docs/NV.md` → "LOD"): el
-- manager pone en cada `beginFrame` el nivel del agente (`lodLevel`: 1
-- 'full', 2 'reduced', 3 'coarse') y si le toca decidir en este cuadro
-- (`lodDecide`, por cubetas). Un `update` se parte en dos:
--
--   decidir   los pasos 1-5 de arriba (reproyección, repath por grafo o
--             desvío, velocidad preferida, atascos, cesión, vecinos, esquiva
--             y giro); los relojes (ventana de atasco, cesión, contraflujo,
--             bloqueo de la esquiva) avanzan con el tiempo que pasó desde la
--             decisión anterior (`lodElapsed`), no con el del cuadro;
--   integrar  el paso 6 y la llegada, en TODOS los cuadros.
--
-- 'full' decide en todos los cuadros: es exactamente el `update` de siempre.
-- En 'reduced' y 'coarse', en los cuadros sin decisión `coast` gira hacia el
-- último rumbo decidido (con el giro acotado de siempre), acerca la rapidez
-- a la última decidida (a 90° o más del rumbo, 0) y avanza `v·dt` sin
-- pasarse del destino: la posición se integra cada cuadro, nunca salta. En
-- 'coarse' la esquiva v2 mira como mucho `coarseMaxNeighbours` vecinos. Sin
-- decisión todavía (ruta recién adoptada, llegada, cesión nueva) decide en
-- el acto aunque no le toque.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')
local Steering = require('runtime.nv.steering')
local PathFollower = require('runtime.nv.path_follower')
local LocalAvoidance = require('runtime.nv.local_avoidance')

local NavigationAgent = NvUtil.class('NavigationAgent')

local EMPTY = {}

-- Niveles de LOD (los mismos números que `NavigationManager.LOD_*`).
local LOD_FULL = 1
local LOD_COARSE = 3

NavigationAgent.defaults = {
    maxSpeed = 120,
    acceleration = 200,
    braking = 300,
    turningRadius = 40,
    lookAheadDistance = 48,
    stoppingDistance = 6,
    autoRepath = true,
    avoidSharpTurns = true,
    usePathCache = true,
    orientacion = 90,
    maxProjectDistance = 400,
    radius = 16,
    repathAfter = 1.5,
    formationWeight = 0.5,
    avoidanceWeight = 1.5,
    minTurnSpeedFactor = 0.3,
    avoidanceMargin = 8,
    avoidanceHorizon = 0.6,
    avoidance = 'v2',
    congestion = true,
    avoidanceTimeHorizon = 0.5,
    reverseSpeedFactor = 0.5,
    congestionWindow = 0.5,
    stuckAfter = 2,
    repathCooldown = 4,
    maxStuckRepaths = 3,
    crowdArrivalFactor = 3,
    movementPriority = 0,
    yieldTime = 1.5,
    maxYieldTime = 8,
}

-- Escalera de atascos (ver la cabecera).
local MIN_DESIRED = 0.2 -- × maxSpeed: por debajo el agente no intenta avanzar
local SLOW_RATIO = 0.5 -- progreso / preferida para seguir en 'moving'
local BLOCKED_RATIO = 0.15 -- por debajo, 'locallyBlocked'
local YIELD_CLEAR = 0.5 -- s sin nadie con prioridad cerca para dejar de ceder
local KEEP_RIGHT_BIAS = 0.6 -- tirón máximo hacia el carril derecho en contraflujo
local YIELD_SIDE = 0.5 -- peso del lado frente a hacia atrás al ceder

--- Sanea las propiedades (números finitos, defaults). `lateralAccel` y
-- `maxDeviation` se derivan si faltan.
function NavigationAgent.normalizeProps(props)
    props = type(props) == 'table' and props or {}
    local d = NavigationAgent.defaults
    local out = {}
    out.navigationTag = props.navigationTag or props.tag
    if type(out.navigationTag) ~= 'string' or out.navigationTag == '' then
        out.navigationTag = nil
    end
    out.tag = out.navigationTag
    out.maxSpeed = NvUtil.atLeast(props.maxSpeed, d.maxSpeed, 0)
    out.acceleration = NvUtil.atLeast(props.acceleration, d.acceleration, 1e-3)
    out.braking = NvUtil.atLeast(props.braking, d.braking, 1e-3)
    out.turningRadius = NvUtil.atLeast(props.turningRadius, d.turningRadius, 1e-3)
    out.lookAheadDistance = NvUtil.atLeast(props.lookAheadDistance, d.lookAheadDistance, 1)
    out.stoppingDistance = NvUtil.atLeast(props.stoppingDistance, d.stoppingDistance, 0)
    out.autoRepath = NvUtil.bool(props.autoRepath, d.autoRepath)
    out.avoidSharpTurns = NvUtil.bool(props.avoidSharpTurns, d.avoidSharpTurns)
    out.usePathCache = NvUtil.bool(props.usePathCache, d.usePathCache)
    out.orientacion = NvUtil.finite(props.orientacion, d.orientacion)
    out.maxProjectDistance = NvUtil.atLeast(props.maxProjectDistance, d.maxProjectDistance, 0)
    out.radius = NvUtil.atLeast(props.radius, d.radius, 0)
    out.width = NvUtil.finite(props.width)
    out.class = props.class or out.tag
    out.repathAfter = NvUtil.atLeast(props.repathAfter, d.repathAfter, 0)
    out.formationWeight = NvUtil.atLeast(props.formationWeight, d.formationWeight, 0)
    out.avoidanceWeight = NvUtil.atLeast(props.avoidanceWeight, d.avoidanceWeight, 0)
    out.lateralAccel = NvUtil.atLeast(props.lateralAccel, out.maxSpeed * out.maxSpeed / (4 * out.turningRadius), 0)
    out.maxDeviation = NvUtil.atLeast(props.maxDeviation, out.lookAheadDistance * 3, 1)
    out.minTurnSpeedFactor = NvUtil.atLeast(props.minTurnSpeedFactor, d.minTurnSpeedFactor, 0)
    out.curvatureWeight = NvUtil.finite(props.curvatureWeight)
    out.explored = props.explored == true
    out.avoidanceRadius = NvUtil.atLeast(
        props.avoidanceRadius,
        math.max(out.radius * 2 + d.avoidanceMargin, out.radius + d.avoidanceMargin + out.maxSpeed * d.avoidanceHorizon),
        0
    )
    -- Fase E: esquiva v2 (o la v1 de respaldo), atascos y cesión de paso.
    if props.avoidance == 'v1' then
        out.avoidance = 'v1'
    else
        out.avoidance = d.avoidance
    end
    out.congestion = NvUtil.bool(props.congestion, d.congestion)
    out.avoidanceTimeHorizon = NvUtil.atLeast(props.avoidanceTimeHorizon, d.avoidanceTimeHorizon, 1e-3)
    out.reverseSpeed = NvUtil.atLeast(props.reverseSpeed, out.maxSpeed * d.reverseSpeedFactor, 0)
    out.congestionWindow = NvUtil.atLeast(props.congestionWindow, d.congestionWindow, 0.05)
    out.stuckAfter = NvUtil.atLeast(props.stuckAfter, d.stuckAfter, out.congestionWindow)
    out.repathCooldown = NvUtil.atLeast(props.repathCooldown, d.repathCooldown, 0)
    out.maxStuckRepaths = math.floor(NvUtil.atLeast(props.maxStuckRepaths, d.maxStuckRepaths, 0))
    out.crowdArrivalRadius = NvUtil.atLeast(props.crowdArrivalRadius, out.radius * d.crowdArrivalFactor, 0)
    out.movementPriority = NvUtil.finite(props.movementPriority, d.movementPriority)
    out.yieldTime = NvUtil.atLeast(props.yieldTime, d.yieldTime, 0)
    out.maxYieldTime = NvUtil.atLeast(props.maxYieldTime, d.maxYieldTime, out.yieldTime)
    return out
end

function NavigationAgent:init(manager, target, props)
    self.manager = manager
    self.target = target
    self.props = NavigationAgent.normalizeProps(props)
    self.system = nil
    self.state = 'idle'
    self.route, self.follower = nil, nil
    self.destination = nil -- { x, y } pedido a setDestination
    self.speed = 0
    self.vx, self.vy = 0, 0
    self.heading = (NvUtil.finite(target and target.angle, 0)) - math.rad(self.props.orientacion)
    self.lookAheadTarget = { x = 0, y = 0 }
    self.steering = { x = 0, y = 0 } -- dirección deseada final (unitaria)
    self.avoidance = LocalAvoidance.new({ timeHorizon = self.props.avoidanceTimeHorizon })
    self.avoidVector = { x = 0, y = 0 }
    self.neighbours = nil -- lista global (respaldo sin índice)
    self.spatialHash = nil -- AgentSpatialHash propio (si no, el del manager)
    self._neighbours = {} -- buffer de la última consulta de vecinos
    self.neighbourCount = 0
    self.formationTarget = { x = 0, y = 0, active = false }
    self.repathReason = nil
    self.repaths = 0
    self.routeVersion = nil
    self.failReason = nil
    self.pendingRequest = nil -- petición en el planificador, mientras espera
    self.pendingKind = nil -- 'destination' | 'repath'
    self.flowField = nil -- FlowField que sigue (grupos masivos); entonces `follower` es nil
    self.fieldSwitchRadius = 0 -- a esta distancia del puesto deja el campo y va recto
    self.fieldCurvature = 0 -- curvatura estimada del campo por delante (para depurar)
    self.fieldCost = math.huge -- coste integrado bajo el agente (progreso con campo)
    self.fieldSeek = false -- ¿va recto a su puesto en vez de seguir el campo?
    -- Fase E: atascos y cesión de paso (ver la cabecera).
    self.serial = NvUtil.nextSerial()
    self.orderSerial = self.serial -- orden en curso: la más antigua tiene prioridad
    self.navGroup = nil -- grupo de `group.lua` de la orden en curso
    self.movementPriority = self.props.movementPriority
    self.yieldState = 'none' -- 'none' | 'yielding' | 'priority'
    self.yieldTo = nil -- agente al que cede
    self.yieldTimer, self.yieldElapsed, self.yieldClear = 0, 0, 0
    self.yieldPressure = math.huge -- s desde la última presión real (un rival con prioridad)
    self.prefX, self.prefY = 1, 0 -- dirección preferida (ruta o campo) del último cuadro
    self.holdX, self.holdY = nil, nil -- donde llegó (vuelve ahí después de hacer sitio)
    self.nudged = false -- un vecino en marcha le pide sitio (lo pone la esquiva v2)
    self.makingWay = false -- llegado, pero apartándose o volviendo a su sitio
    self.congestion = {
        state = 'moving', -- 'moving' | 'slow' | 'locallyBlocked' | 'stuck' | 'repathPending'
        progress = 0, -- px/s de la última ventana
        desired = 0, -- velocidad preferida media de la última ventana
        ratio = 1,
        blockedTime = 0, -- s bloqueado acumulados
        windowTime = 0,
        desiredSum = 0,
        windowMetric = 0,
        windowSource = nil, -- seguidor, campo o puesto con el que se mide la ventana
        relaxFormation = false,
        stuckCount = 0, -- veces que llegó a 'stuck' (acumulado)
        stuckRepaths = 0, -- repaths por atasco seguidos (sin progreso entre medias)
        sinceRepath = math.huge,
        crowdArrival = false, -- llegó a su puesto entre la multitud
        keepRight = 0, -- s que le quedan por su carril derecho (contraflujo)
    }
    -- LOD (fase F): el nivel y la cubeta los pone el manager en `beginFrame`.
    self.lodLevel = LOD_FULL -- 1 'full' | 2 'reduced' | 3 'coarse'
    self.lodInterval = 1 -- cuadros entre decisiones
    self.lodDecide = true -- ¿le toca decidir en este cuadro?
    self.lodElapsed = 0 -- s desde la última decisión
    self.lodReady = false -- ¿hay una decisión vigente que integrar?
    self.lodDesired = self.heading -- rumbo decidido
    self.lodTarget = 0 -- rapidez decidida (negativa = marcha atrás)
end

-- Vuelve la detección de atascos a 'moving'. `full` también olvida los
-- repaths seguidos y la llegada entre la multitud (orden nueva).
local function resetCongestion(self, full)
    local c = self.congestion
    c.state = 'moving'
    c.blockedTime, c.windowTime, c.desiredSum = 0, 0, 0
    c.windowSource = nil
    c.relaxFormation = false
    c.progress, c.ratio = 0, 1
    if full then
        c.stuckRepaths = 0
        c.sinceRepath = math.huge
        c.crowdArrival = false
    end
end

--- Estado de la detección de atascos: 'moving' | 'slow' | 'locallyBlocked'
-- | 'stuck' | 'repathPending' (no sustituye a `getState`).
function NavigationAgent:getCongestionState()
    return self.congestion.state
end

--- El sistema de su tag (nil si no hay red con ese nombre).
function NavigationAgent:resolveSystem()
    local tag = self.props.tag
    self.system = tag and self.manager and self.manager:getSystem(tag) or nil
    return self.system
end

function NavigationAgent:hasNetwork()
    return self:resolveSystem() ~= nil
end

function NavigationAgent:getState()
    return self.state
end

function NavigationAgent:isMoving()
    return self.state == 'moving'
end

--- ¿Espera una ruta del planificador sin moverse todavía?
function NavigationAgent:isPending()
    return self.state == 'pending'
end

function NavigationAgent:getCurrentPath()
    return self.route
end

-- Adopta una ruta recién calculada.
local function adopt(self, route, system)
    self.route = route
    self.follower = PathFollower.new(route, self.props)
    self.flowField = nil
    self.routeVersion = system.version
    self.failReason = nil
    self.avoidance:reset()
    resetCongestion(self, false)
    self.lodReady = false
end

-- Cancela la petición pendiente en el planificador, si la hay.
function NavigationAgent:cancelPending()
    local request = self.pendingRequest
    self.pendingRequest, self.pendingKind = nil, nil
    if request and request.state == 'queued' then
        local scheduler = self.manager and self.manager.scheduler
        if scheduler then
            scheduler:cancel(request)
        end
        return true
    end
    return false
end

-- Llega (o falla) una ruta del planificador para la petición `request`.
function NavigationAgent:routeReady(route, err, request)
    if request ~= self.pendingRequest then
        return -- una petición vieja, cancelada o reemplazada
    end
    local kind = self.pendingKind
    self.pendingRequest, self.pendingKind = nil, nil
    local system = self.system or self:resolveSystem()
    if route and system then
        adopt(self, route, system)
        if self.state == 'pending' or self.state == 'moving' then
            self.state = 'moving'
        end
        return
    end
    self.failReason = err or 'sin ruta'
    self.speed, self.vx, self.vy = 0, 0, 0
    if kind == 'repath' then
        self.state = 'blocked'
    else
        self.state = 'noroute'
        self.route, self.follower = nil, nil
    end
end

-- Pide la ruta al sistema desde la posición actual. Devuelve true (ruta
-- lista, o pendiente en el planificador: segundo valor 'pending') o false,
-- motivo. `opts`: `immediate`, `priority`, `kind`.
function NavigationAgent:request(x, y, opts)
    opts = opts or EMPTY
    local system = self:resolveSystem()
    if not system then
        self.failReason = 'sin red "' .. tostring(self.props.tag) .. '"'
        return false, self.failReason
    end
    self:cancelPending()
    local scheduler = self.manager and self.manager.scheduler
    if scheduler then
        local kind = opts.kind or 'destination'
        local request
        request = scheduler:request({
            system = system,
            sx = self.target.x,
            sy = self.target.y,
            tx = x,
            ty = y,
            props = self.props,
            owner = self,
            priority = opts.priority or (kind == 'repath' and 'repath' or 'normal'),
            immediate = opts.immediate == true,
            callback = function(route, err, req)
                if req.state == 'queued' or req ~= self.pendingRequest then
                    -- Resuelta en el acto (caché o fallo de proyección): se trata abajo.
                    return
                end
                self:routeReady(route, err, req)
            end,
        })
        if request.state == 'done' then
            adopt(self, request.route, system)
            return true
        end
        if request.state == 'failed' then
            self.failReason = request.err
            return false, request.err
        end
        self.pendingRequest, self.pendingKind = request, kind
        return true, 'pending'
    end
    local route, err = system:requestPath(self.target.x, self.target.y, x, y, self.props)
    if not route then
        self.failReason = err
        return false, err
    end
    adopt(self, route, system)
    return true
end

--- Fija el destino y calcula la ruta. Devuelve true, o false y el motivo
-- (`getState()` pasa a 'noroute'). Con planificador el agente queda en
-- 'pending' hasta que llega la ruta; `opts.immediate = true` la calcula ya.
-- `opts.priority`: 'selected' | 'order' | 'repath' | 'normal' | 'speculative'.
function NavigationAgent:setDestination(x, y, opts)
    x, y = NvUtil.finite(x), NvUtil.finite(y)
    if not x or not y then
        return false, 'destino inválido'
    end
    self.destination = self.destination or {}
    self.destination.x, self.destination.y = x, y
    self.repathReason = nil
    -- Orden nueva: sale de su grupo (el grupo lo vuelve a poner) y de la cesión.
    self.navGroup = nil
    self.orderSerial = NvUtil.nextSerial()
    self:endYield()
    self.nudged, self.makingWay = false, false
    local ok, extra = self:request(x, y, opts)
    if not ok then
        self.state = 'noroute'
        self.route, self.follower = nil, nil
        self.speed = 0
        return false, extra
    end
    resetCongestion(self, true)
    if extra == 'pending' then
        self.state = 'pending'
        self.speed, self.vx, self.vy = 0, 0, 0
        return true
    end
    self.state = 'moving'
    return true
end

-- Vuelve a pedir la ruta al destino actual. Sin ruta pasa a 'blocked'. Con
-- planificador devuelve true y sigue la ruta vieja hasta que llegue la nueva.
function NavigationAgent:repath(reason)
    self.repathReason = reason
    self.repaths = self.repaths + 1
    local manager = self.manager
    if manager and manager.noteRepath then
        manager:noteRepath()
    end
    local dest = self.destination
    if not dest then
        self.state = 'idle'
        return false
    end
    local ok = self:request(dest.x, dest.y, { kind = 'repath', priority = 'repath' })
    if not ok then
        self.state = 'blocked'
        self.speed = 0
        return false
    end
    return true
end

--- Cambia de puesto SIN cambiar de orden (el grupo reordena los puestos al
-- llegar, ver `group.lua`): mismo grupo y misma prioridad de paso. Con ruta
-- propia pide la nueva (prioridad 'repath', sigue la vieja mientras llega);
-- con flow field solo cambia el punto al que va. Devuelve true, o false y
-- el motivo.
function NavigationAgent:retarget(x, y)
    x, y = NvUtil.finite(x), NvUtil.finite(y)
    if not x or not y then
        return false, 'destino inválido'
    end
    if self.state ~= 'moving' or not self.destination then
        return false, 'no está en marcha'
    end
    self.destination.x, self.destination.y = x, y
    self.lodReady = false
    if self.flowField then
        return true
    end
    return self:request(x, y, { kind = 'repath', priority = 'repath' })
end

--- Para donde está (conserva la ruta para `getCurrentPath`).
function NavigationAgent:stop()
    self:cancelPending()
    self:endYield()
    self.nudged, self.makingWay = false, false
    resetCongestion(self, true)
    self.state = 'idle'
    self.speed = 0
    self.vx, self.vy = 0, 0
    self.lodReady = false
    return self
end

--- Para y olvida destino, ruta y campo.
function NavigationAgent:clearDestination()
    self:stop()
    self.destination = nil
    self.route, self.follower, self.flowField = nil, nil, nil
    self.formationTarget.active = false
    self.repathReason = nil
    return self
end

--- Fija el puesto y deja al agente 'pending' sin pedir ruta propia: el grupo
-- traerá el flow field. Devuelve true, o false y el motivo.
function NavigationAgent:awaitFlowField(x, y)
    x, y = NvUtil.finite(x), NvUtil.finite(y)
    if not x or not y then
        return false, 'destino inválido'
    end
    if not self:resolveSystem() then
        self.failReason = 'sin red "' .. tostring(self.props.tag) .. '"'
        self.state = 'noroute'
        return false, self.failReason
    end
    self:cancelPending()
    self:endYield()
    self.nudged, self.makingWay = false, false
    resetCongestion(self, true)
    self.navGroup = nil
    self.orderSerial = NvUtil.nextSerial()
    self.destination = self.destination or {}
    self.destination.x, self.destination.y = x, y
    self.route, self.follower, self.flowField = nil, nil, nil
    self.formationTarget.active = false
    self.repathReason, self.failReason = nil, nil
    self.state = 'pending'
    self.speed, self.vx, self.vy = 0, 0, 0
    self.lodReady = false
    return true
end

--- Sigue `field` (un `FlowField` construido) hasta el puesto (x, y) (o el
-- destino ya fijado). `opts.route`: la ruta global compartida que devuelve
-- `getCurrentPath`; `opts.switchRadius`: distancia al puesto a partir de la
-- que va recto (por defecto `2·lookAheadDistance`). Devuelve true, o false y
-- el motivo.
function NavigationAgent:followFlowField(field, x, y, opts)
    opts = opts or EMPTY
    if type(field) ~= 'table' or type(field.sample) ~= 'function' then
        return false, 'campo inválido'
    end
    if x ~= nil or y ~= nil then
        x, y = NvUtil.finite(x), NvUtil.finite(y)
        if not x or not y then
            return false, 'destino inválido'
        end
        self.destination = self.destination or {}
        self.destination.x, self.destination.y = x, y
    end
    if not self.destination then
        return false, 'sin destino'
    end
    local system = self:resolveSystem()
    if not system then
        self.failReason = 'sin red "' .. tostring(self.props.tag) .. '"'
        self.state = 'noroute'
        return false, self.failReason
    end
    self:cancelPending()
    self.flowField = field
    self.route = opts.route or field.route
    self.follower = nil
    self.fieldSwitchRadius = NvUtil.atLeast(opts.switchRadius, self.props.lookAheadDistance * 2, 0)
    self.routeVersion = system.version
    self.failReason, self.repathReason = nil, nil
    self.formationTarget.active = false
    self.avoidance:reset()
    resetCongestion(self, false)
    self.state = 'moving'
    self.lodReady = false
    return true
end

-- Dirección deseada, curvatura, límite de velocidad y distancia restante
-- según el flow field (ver la cabecera). Sin reservar memoria.
function NavigationAgent:planFromField(field, x, y, la, dest, goalDist)
    local d0x, d0y, ok0, cost0 = field:sample(x, y)
    self.fieldCost = cost0
    local seek = goalDist <= self.fieldSwitchRadius
    if not seek and (not ok0 or (d0x == 0 and d0y == 0)) then
        if ok0 then
            -- Dentro del disco del destino: ya no hay campo, al puesto.
            seek = true
        else
            -- Fuera del corredor: hacia la celda válida más cercana.
            local px, py, ok = field:nearestValid(x, y)
            if ok and (px ~= 0 or py ~= 0) then
                d0x, d0y = px, py
            else
                seek = true
            end
        end
    end
    local dirx, diry, k
    if seek then
        dirx, diry = V.normalize(dest.x - x, dest.y - y)
        k = 0
    else
        local d1x, d1y, ok1 = field:sample(x + d0x * la, y + d0y * la)
        if not ok1 or (d1x == 0 and d1y == 0) then
            d1x, d1y = d0x, d0y
        end
        dirx, diry = V.normalize(d0x + d1x, d0y + d1y)
        if dirx == 0 and diry == 0 then
            dirx, diry = d0x, d0y
        end
        -- Giro entre las dos muestras repartido en la distancia adelantada.
        local dot = d0x * d1x + d0y * d1y
        if dot > 1 then
            dot = 1
        elseif dot < -1 then
            dot = -1
        end
        k = math.acos(dot) / la
    end
    self.fieldCurvature = k
    self.fieldSeek = seek
    self.lookAheadTarget.x, self.lookAheadTarget.y = x + dirx * la, y + diry * la
    return dirx, diry, k, field:speedLimitAt(x, y), goalDist
end

--- Punto de formación al que tirar (nil lo desactiva).
function NavigationAgent:setFormationTarget(x, y)
    if x == nil then
        self.formationTarget.active = false
        return self
    end
    self.formationTarget.x, self.formationTarget.y, self.formationTarget.active = x, y, true
    return self
end

--- Vecinos para la esquiva: del índice espacial (el propio o el del
-- manager) en el buffer reutilizado, o la lista `neighbours` de respaldo.
function NavigationAgent:queryNeighbours(x, y)
    local hash = self.spatialHash or (self.manager and self.manager.agentIndex)
    if hash then
        local out = hash:queryRadius(x, y, self.props.avoidanceRadius, self._neighbours, self)
        self.neighbourCount = #out
        return out
    end
    local list = self.neighbours
    self.neighbourCount = list and #list or 0
    return list
end

--- Vecinos de la última consulta (para el dibujo de depuración).
function NavigationAgent:lastNeighbours()
    if self.spatialHash or (self.manager and self.manager.agentIndex) then
        return self._neighbours
    end
    return self.neighbours
end

-- Pone a cero la velocidad de un cuerpo dinámico: la orden manda, no los choques.
local function calmBody(target)
    local body = target.body
    if type(body) == 'userdata' and not body:isDestroyed() and body:getType() == 'dynamic' then
        body:setLinearVelocity(0, 0)
        body:setAngularVelocity(0)
    end
end

-- Cesión de paso -----------------------------------------------------------------

--- ¿Van en el mismo grupo (misma orden de `group.lua`)?
function NavigationAgent:sameGroup(other)
    local group = self.navGroup
    return group ~= nil and group == other.navGroup
end

--- ¿Tiene prioridad de paso sobre `other`? `movementPriority` mayor; a
-- igualdad, la orden más antigua; a igualdad, el agente más antiguo.
function NavigationAgent:hasPriorityOver(other)
    local a, b = self.movementPriority or 0, other.movementPriority or 0
    if a ~= b then
        return a > b
    end
    local sa, sb = self.orderSerial or 0, other.orderSerial or 0
    if sa ~= sb then
        return sa < sb
    end
    return (self.serial or 0) < (other.serial or 0)
end

--- Empieza a ceder el paso a `to` (un agente con prioridad).
function NavigationAgent:beginYield(to)
    local manager = self.manager
    if self.yieldState ~= 'yielding' and manager then
        manager.yieldingAgents = (manager.yieldingAgents or 0) + 1
    end
    self.yieldState = 'yielding'
    self.yieldTo = to
    self.yieldTimer = self.props.yieldTime
    self.yieldElapsed, self.yieldClear = 0, 0
    self.yieldPressure = 0
    self.lodReady = false
    return self
end

--- Deja de ceder (o de tener prioridad). Recoloca el seguidor sobre la ruta
-- (retrocedió a propósito) y vuelve a medir el atasco desde cero.
function NavigationAgent:endYield()
    local state = self.yieldState
    if state == 'none' then
        return self
    end
    local manager = self.manager
    if state == 'yielding' and manager then
        manager.yieldingAgents = math.max(0, (manager.yieldingAgents or 0) - 1)
    end
    self.yieldState = 'none'
    self.yieldTo = nil
    self.yieldTimer, self.yieldElapsed, self.yieldClear = 0, 0, 0
    self.lodReady = false
    if state == 'yielding' then
        local t = self.target
        if self.follower and t then
            self.follower:rewindTo(t.x, t.y)
        end
        resetCongestion(self, false)
    end
    return self
end

-- ¿`n` cierra el paso a este agente? Otro agente en marcha, por delante
-- (según la dirección preferida) y casi tocando.
local function closesPath(self, n, x, y)
    if n == self or not n.props or n.state ~= 'moving' then
        return false
    end
    local nt = n.target
    local dx, dy = nt.x - x, nt.y - y
    if dx * self.prefX + dy * self.prefY <= 0 then
        return false
    end
    local reach = self.props.radius + n.props.radius + 2 * NavigationAgent.defaults.avoidanceMargin
    return dx * dx + dy * dy <= reach * reach
end

--- Paso de "ceder el paso" de la escalera de atascos: con vecinos de otro
-- grupo que le cierran el paso, cede al que tenga prioridad; si la tiene él,
-- pasa a 'priority' y los hace ceder.
function NavigationAgent:negotiateYield()
    local list = self:lastNeighbours()
    if not list or #list == 0 then
        return false
    end
    local t = self.target
    local x, y = t.x, t.y
    local winner = nil
    local blockers = 0
    for i = 1, #list do
        local n = list[i]
        if closesPath(self, n, x, y) and not self:sameGroup(n) then
            blockers = blockers + 1
            if n:hasPriorityOver(self) and (not winner or n:hasPriorityOver(winner)) then
                winner = n
            end
        end
    end
    if winner then
        self:beginYield(winner)
        return true
    end
    if blockers == 0 then
        return false
    end
    self.yieldState = 'priority'
    self.yieldTimer = self.props.yieldTime
    for i = 1, #list do
        local n = list[i]
        if
            closesPath(self, n, x, y)
            and not self:sameGroup(n)
            and n.props.congestion
            and n.yieldState ~= 'yielding'
        then
            n:beginYield(self)
        end
    end
    return true
end

-- Mientras cede: dirección para apartarse de los que tienen prioridad (y de
-- los compañeros de delante que también ceden), o 0, 0 si ya está fuera de
-- su camino o no hay nadie (espera quieto). Apartarse es sobre todo hacia
-- atrás y algo hacia un lado del carril del otro (perpendicular a su
-- dirección, hacia el lado en que ya está, con peso `YIELD_SIDE`); si el
-- lado está cerrado (un puente con muros) la esquiva v2 deja solo la parte
-- hacia atrás. Termina la cesión cuando toca: devuelve nil. Devuelve dx, dy.
function NavigationAgent:yieldAway(neighbours, x, y, dt)
    self.yieldTimer = self.yieldTimer - dt
    self.yieldElapsed = self.yieldElapsed + dt
    local margin = NavigationAgent.defaults.avoidanceMargin
    local r = self.props.radius
    local ax, ay = 0, 0
    local found = false
    local pressure = math.huge
    for i = 1, neighbours and #neighbours or 0 do
        local n = neighbours[i]
        if n ~= self and n.props then
            local nt = n.target
            local dx, dy = x - nt.x, y - nt.y
            local threat
            if self:sameGroup(n) then
                -- Un compañero por delante que cede porque tiene de verdad a
                -- alguien con prioridad encima (la presión nace en un rival y
                -- se va gastando por la columna: dos compañeros no se
                -- mantienen cediendo el uno al otro).
                threat = n.yieldState == 'yielding'
                    and n.yieldPressure < YIELD_CLEAR
                    and dx * self.prefX + dy * self.prefY < 0
                if threat then
                    pressure = math.min(pressure, n.yieldPressure + dt)
                end
            else
                threat = n.state == 'moving' and n.yieldState ~= 'yielding' and n:hasPriorityOver(self)
                if threat then
                    pressure = 0
                end
            end
            if threat then
                found = true
                local d = math.sqrt(dx * dx + dy * dy)
                -- Carril del otro: su dirección preferida (la suya si retrocede).
                local tx, ty = n.prefX or 0, n.prefY or 0
                local lateral = dx * -ty + dy * tx
                local clearance = r + n.props.radius + margin
                if d > V.EPSILON and math.abs(lateral) < clearance then
                    local sx, sy = -ty, tx
                    if lateral < 0 then
                        sx, sy = ty, -tx
                    end
                    local w = 1 / d
                    ax = ax + (YIELD_SIDE * sx + dx / d) * w
                    ay = ay + (YIELD_SIDE * sy + dy / d) * w
                end
            end
        end
    end
    if found and pressure < YIELD_CLEAR then
        self.yieldClear = 0
        self.yieldPressure = pressure
    else
        self.yieldClear = self.yieldClear + dt
        self.yieldPressure = self.yieldPressure + dt
    end
    if (self.yieldTimer <= 0 and self.yieldClear >= YIELD_CLEAR) or self.yieldElapsed >= self.props.maxYieldTime then
        self:endYield()
        return nil
    end
    local nx, ny, len = V.normalize(ax, ay)
    if len > 0 then
        return nx, ny
    end
    return 0, 0
end

-- Contraflujo: ¿viene de frente, por delante y cerca, un agente de otro
-- grupo? (dirección preferida opuesta, a `avoidanceRadius` o menos).
local function counterflow(self, neighbours, x, y)
    local px, py = self.prefX, self.prefY
    for i = 1, #neighbours do
        local n = neighbours[i]
        if n ~= self and n.props and n.state == 'moving' and not self:sameGroup(n) then
            local nt = n.target
            if (nt.x - x) * px + (nt.y - y) * py > 0 and (n.prefX or 0) * px + (n.prefY or 0) * py < -0.5 then
                return true
            end
        end
    end
    return false
end

-- Un compañero de grupo por delante que ya cede (con presión de verdad): cede
-- también (la cesión se propaga por la columna).
local function catchYield(self, neighbours, x, y)
    for i = 1, #neighbours do
        local n = neighbours[i]
        if n ~= self and n.yieldState == 'yielding' and n.yieldPressure < YIELD_CLEAR and self:sameGroup(n) then
            local nt = n.target
            local dx, dy = nt.x - x, nt.y - y
            local reach = 2 * (self.props.radius + n.props.radius) + NavigationAgent.defaults.avoidanceMargin
            if dx * self.prefX + dy * self.prefY > 0 and dx * dx + dy * dy <= reach * reach then
                self:beginYield(n.yieldTo or n)
                return true
            end
        end
    end
    return false
end

-- Atascos --------------------------------------------------------------------------

--- Cierra la ventana de medida si toca y aplica la escalera (ver la
-- cabecera). `metric` crece con el progreso; `source` identifica con qué se
-- mide (una fuente nueva abre ventana). Devuelve false si el agente dejó de
-- moverse (llegó entre la multitud o el repath falló).
function NavigationAgent:updateCongestion(metric, source, goalDist, canRepath)
    local c = self.congestion
    local p = self.props
    if c.windowSource ~= source then
        c.windowSource = source
        c.windowMetric = metric
        c.windowTime, c.desiredSum = 0, 0
        return true
    end
    if c.windowTime < p.congestionWindow - 1e-9 then
        return true
    end
    local elapsed = c.windowTime
    local desired = c.desiredSum / elapsed
    local progress = (metric - c.windowMetric) / elapsed
    c.windowMetric, c.windowTime, c.desiredSum = metric, 0, 0
    if self.yieldState == 'yielding' then
        return true -- cediendo: el reloj de atasco se congela
    end
    c.progress, c.desired = progress, desired
    -- Rematando junto al puesto la preferida es pequeña (la de llegada) pero
    -- sí intenta avanzar: ahí cuenta cualquiera.
    local finishing = goalDist <= p.crowdArrivalRadius and desired > 1e-3
    if desired < MIN_DESIRED * p.maxSpeed and not finishing then
        -- No intenta avanzar (frena para llegar, gira en el sitio): nada que medir.
        c.state, c.ratio = 'moving', 1
        c.blockedTime = 0
        c.relaxFormation = false
        return true
    end
    local ratio = progress / desired
    c.ratio = ratio
    if ratio >= SLOW_RATIO then
        c.state = 'moving'
        c.blockedTime = 0
        c.relaxFormation = false
        c.stuckRepaths = 0
        return true
    end
    if ratio >= BLOCKED_RATIO then
        c.state = 'slow'
        return true
    end
    local wasStuck = c.state == 'stuck'
    c.blockedTime = c.blockedTime + elapsed
    c.state = 'locallyBlocked'
    local stuckAfter = p.stuckAfter
    local group = self.navGroup
    local inSlotZone = group ~= nil and group.slotZone ~= nil and goalDist <= group.slotZone
    if c.blockedTime >= stuckAfter * 0.5 then
        c.relaxFormation = true
        -- En la zona de puestos: cambiar a un puesto libre más cercano.
        if inSlotZone and group.request and group.request:swapNearestSlot(group, self) then
            return true
        end
    end
    if c.blockedTime >= stuckAfter * 0.75 and self.yieldState == 'none' and not inSlotZone then
        self:negotiateYield()
    end
    if self.yieldState ~= 'none' then
        return true -- conflicto de paso: lo resuelve la cesión, no un repath
    end
    if c.blockedTime < stuckAfter - 1e-9 then
        return true
    end
    c.state = 'stuck'
    if not wasStuck then
        c.stuckCount = c.stuckCount + 1
    end
    if goalDist <= p.crowdArrivalRadius then
        -- Su puesto está ocupado o rodeado: llega donde está.
        local t = self.target
        self:arrive(t.x, t.y)
        c.crowdArrival = true
        return false
    end
    if self.follower and canRepath and c.sinceRepath >= p.repathCooldown and c.stuckRepaths < p.maxStuckRepaths then
        c.stuckRepaths = c.stuckRepaths + 1
        c.sinceRepath = 0
        if not self:repath('bloqueo') then
            return false
        end
        if self.pendingRequest then
            c.state = 'repathPending'
        end
    end
    return true
end

-- Borde del tramo bajo el agente como semiplano `v·n ≤ c` (n hacia fuera):
-- solo con ruta propia, sobre un tramo y lejos del final (en la recta final
-- el puesto puede estar fuera del ancho). Devuelve nx, ny, c o nil.
local function corridorLine(self, f, x, y, maxSpeed)
    local seg, sd = self.route:segmentAt(f.distance)
    if not seg or not seg.arc or not seg.width then
        return nil
    end
    local px, py = seg:positionAt(sd)
    local tx, ty = seg.arc:tangentAtDistance(sd)
    local nx, ny = -ty, tx
    local lateral = (x - px) * nx + (y - py) * ny
    if lateral < 0 then
        nx, ny, lateral = -nx, -ny, -lateral
    end
    local allowed = seg.width * 0.5 - self.props.radius
    if allowed < 0 then
        allowed = 0
    end
    -- Holgura en velocidad: lo que queda hasta el borde en medio segundo; si
    -- ya está fuera, volver hacia dentro sin pasar de media velocidad.
    local c = (allowed - lateral) * 2
    if c >= maxSpeed then
        return nil -- lejos del borde: no recorta nada
    end
    if c < -maxSpeed * 0.5 then
        c = -maxSpeed * 0.5
    end
    return nx, ny, c
end

function NavigationAgent:update(dt)
    dt = NvUtil.finite(dt, 0)
    if dt <= 0 then
        return
    end
    if self.state ~= 'moving' then
        self.lodElapsed = 0
        self.lodReady = false
        if self.state == 'arrived' and (self.nudged or self.makingWay) then
            self:makeWay(dt)
            return
        end
        self.speed, self.vx, self.vy = 0, 0, 0
        return
    end
    local t = self.target
    if t.isDestroyed and t:isDestroyed() then
        self.state = 'idle'
        return
    end
    -- LOD: sin decisión en este cuadro, solo se integra el movimiento. Los
    -- relojes de la decisión avanzan con todo lo que pasó desde la anterior
    -- (en 'full', justo `dt`).
    self.lodElapsed = self.lodElapsed + dt
    if self.lodLevel ~= LOD_FULL and self.lodReady and not self.lodDecide then
        self:coast(dt)
        return
    end
    local elapsed = self.lodElapsed
    self.lodElapsed = 0
    self.lodReady = false
    local p = self.props
    local x, y = t.x, t.y
    local la = p.lookAheadDistance
    local dest = self.destination
    local goalDist = V.distance(x, y, dest.x, dest.y)
    local c = self.congestion
    local congestion = p.congestion
    local dirx, diry, curvature, limit, remaining
    local metric, source
    local canRepath = false
    local field = self.flowField
    local f = nil
    if field then
        -- Flow field: la dirección la da el campo (ver `planFromField`).
        dirx, diry, curvature, limit, remaining = self:planFromField(field, x, y, la, dest, goalDist)
        if self.fieldSeek or self.fieldCost == math.huge then
            metric, source = -goalDist, dest
        else
            metric, source = -self.fieldCost, field
        end
    else
        -- Con una petición de repath en vuelo se sigue la ruta vieja sin pedir otra.
        local waiting = self.pendingRequest ~= nil
        canRepath = p.autoRepath and not waiting
        -- 1. Repetir la búsqueda si hace falta.
        if canRepath and self.system and self.system.version ~= self.routeVersion then
            if not self:repath('grafo') then
                return
            end
            waiting = self.pendingRequest ~= nil
            canRepath = canRepath and not waiting
        end
        f = self.follower
        -- 2. Reproyección y objetivo adelantado.
        local _, deviation = f:advanceTo(x, y)
        if canRepath and deviation > p.maxDeviation and self.yieldState ~= 'yielding' then
            if not self:repath('desvío') then
                return
            end
            f = self.follower
            f:advanceTo(x, y)
            waiting = self.pendingRequest ~= nil
            canRepath = canRepath and not waiting
        end
        local tx, ty = f:lookAhead(la)
        self.lookAheadTarget.x, self.lookAheadTarget.y = tx, ty
        local dist
        dirx, diry, dist = V.normalize(tx - x, ty - y)
        if dist <= V.EPSILON then
            dirx, diry = math.cos(self.heading), math.sin(self.heading)
        end
        curvature = p.avoidSharpTurns and f:curvatureAhead(la * 2) or 0
        local seg = self.route:segmentAt(f.distance)
        limit = seg and seg.speedLimit or 0
        remaining = f:remaining()
        metric, source = f.distance, f
    end
    self.prefX, self.prefY = dirx, diry
    -- 3. Velocidad preferida (ruta: curvatura, límite del tramo, llegada).
    local target = p.maxSpeed
    if p.avoidSharpTurns then
        target = math.min(target, Steering.speedForCurvature(curvature, p.lateralAccel, p.maxSpeed))
    end
    if limit > 0 then
        target = math.min(target, limit)
    end
    target =
        math.min(target, Steering.arrive(math.min(remaining + la, goalDist), p.stoppingDistance, p.maxSpeed, p.braking))
    -- 4. Atascos: cerrar la ventana anterior y subir (o bajar) la escalera.
    if congestion then
        if not self:updateCongestion(metric, source, goalDist, canRepath) then
            return
        end
        if f and self.follower ~= f then
            -- Repath síncrono por atasco: seguidor nuevo desde ya.
            f = self.follower
            f:advanceTo(x, y)
            remaining = f:remaining()
        end
        -- La ventana en curso: cuenta la preferida solo si intenta avanzar
        -- (mira a menos de 60° de donde quiere ir; no mientras gira en el
        -- sitio para dar la vuelta).
        local facing = math.cos(self.heading) * dirx + math.sin(self.heading) * diry
        c.windowTime = c.windowTime + elapsed
        if facing > 0.5 then
            c.desiredSum = c.desiredSum + target * elapsed
        end
        c.sinceRepath = c.sinceRepath + elapsed
    end
    -- Formación (relajada en un atasco).
    local ft = self.formationTarget
    -- Con v2 la formación (prioridad 4) solo tira en espacio libre: con un
    -- vecino a menos de un radio (superficie con superficie, cuadro anterior)
    -- manda la esquiva.
    local crowded = p.avoidance ~= 'v1' and self.avoidance.nearestSurface < p.radius
    local relaxed = congestion and (c.relaxFormation or c.keepRight > 0)
    if ft.active and not relaxed and not crowded then
        local fx, fy, fd = V.normalize(ft.x - x, ft.y - y)
        local w = math.min(1, fd / la) * p.formationWeight
        dirx, diry = dirx + fx * w, diry + fy * w
    end
    local neighbours = self:queryNeighbours(x, y)
    -- Cesión de paso: apartarse de los que tienen prioridad.
    local yielding = false
    if congestion then
        local manager = self.manager
        if self.yieldState == 'none' and neighbours then
            if manager and (manager.yieldingAgents or 0) > 0 then
                catchYield(self, neighbours, x, y)
            end
        end
        if self.yieldState == 'yielding' then
            local ax, ay = self:yieldAway(neighbours, x, y, elapsed)
            if ax then
                yielding = true
                if ax ~= 0 or ay ~= 0 then
                    dirx, diry = ax, ay
                    target = p.reverseSpeed
                else
                    target = 0
                end
            end
        elseif self.yieldState == 'priority' then
            self.yieldTimer = self.yieldTimer - elapsed
            if self.yieldTimer <= 0 then
                self:endYield()
            end
        end
        -- Contraflujo con otro grupo: cada uno por su mitad derecha del tramo
        -- (con ruta: hacia un carril a ¼ del ancho a su derecha; con campo:
        -- un sesgo suave a la derecha). Dos corrientes densas de frente no se
        -- cruzan con la esquiva sola; con carriles, sí.
        local group = self.navGroup
        local inSlotZone = group ~= nil and group.slotZone ~= nil and goalDist <= group.slotZone
        if not yielding and neighbours and not inSlotZone then
            if counterflow(self, neighbours, x, y) then
                c.keepRight = 1
            elseif c.keepRight > 0 then
                c.keepRight = c.keepRight - elapsed
            end
            if c.keepRight > 0 then
                local rx, ry = -self.prefY, self.prefX -- a la derecha del avance (Y hacia abajo)
                local push = KEEP_RIGHT_BIAS
                if f then
                    local seg, sd = self.route:segmentAt(f.distance)
                    if seg and seg.arc and seg.width then
                        if seg.width < 4 * p.radius + 2 * NavigationAgent.defaults.avoidanceMargin then
                            -- Paso de un carril: no caben dos; decide la cesión.
                            push = 0
                        else
                            local cx, cy = seg:positionAt(sd)
                            local lateral = (x - cx) * rx + (y - cy) * ry
                            push = V.clamp((seg.width * 0.25 - lateral) / la, -KEEP_RIGHT_BIAS, KEEP_RIGHT_BIAS)
                        end
                    end
                end
                dirx, diry = dirx + rx * push, diry + ry * push
            end
        end
    end
    -- 'coarse': la esquiva mira menos vecinos (los más cercanos).
    if self.lodLevel == LOD_COARSE then
        local manager = self.manager
        self.avoidance.neighbourLimit = manager and manager.lod and manager.lod.coarseMaxNeighbours or nil
    else
        self.avoidance.neighbourLimit = nil
    end
    if p.avoidance == 'v1' then
        target = self:steerV1(neighbours, dirx, diry, target, dt, elapsed)
    else
        target = self:steerV2(neighbours, dirx, diry, target, dt, f, x, y, yielding, elapsed)
    end
    -- Decisión vigente hasta la siguiente (LOD): rumbo y rapidez.
    self.lodTarget = target
    self.lodReady = true
    -- Bloqueo persistente sin escalera (`congestion = false`, lo de antes de
    -- la fase E): con ruta se repite la búsqueda; con campo el plan global ya
    -- está y solo se suelta el contador (la esquiva sigue actuando).
    if not congestion then
        local blockedFor = self.avoidance.blockedFor
        c.state = blockedFor > 0 and 'stuck' or 'moving'
        if blockedFor > p.repathAfter then
            if canRepath then
                self.avoidance:reset()
                if not self:repath('bloqueo') then
                    return
                end
            elseif field then
                self.avoidance:reset()
            end
        end
    end
    -- 6. Avance.
    local braking = p.braking
    if p.avoidance ~= 'v1' and target < self.speed then
        braking = braking * 2
    end
    self.speed = Steering.accelerate(self.speed, target, p.acceleration, braking, dt)
    local step = self.speed * dt
    if remaining <= la and step > goalDist then
        step = goalDist
    end
    local mx, my = x + math.cos(self.heading) * step, y + math.sin(self.heading) * step
    self.vx, self.vy = (mx - x) / dt, (my - y) / dt
    t.x, t.y = mx, my
    t.angle = self.heading + math.rad(p.orientacion)
    calmBody(t)
    -- 7. Llegada.
    if V.distance(mx, my, dest.x, dest.y) <= p.stoppingDistance then
        self:arrive(mx, my)
    end
end

--- Entre dos decisiones (LOD 'reduced' y 'coarse', ver la cabecera):
-- integra el movimiento de este cuadro con la última decisión. Gira hacia
-- el rumbo decidido con el giro acotado de siempre, acerca la rapidez a la
-- decidida (0 si el rumbo queda a 90° o más, salvo marcha atrás) y avanza
-- `v·dt` sin pasarse del destino. No consulta vecinos ni la ruta.
function NavigationAgent:coast(dt)
    local p = self.props
    local t = self.target
    local x, y = t.x, t.y
    local dest = self.destination
    local desired = self.lodDesired
    local speed = self.speed
    local turnRate = Steering.maxTurnRate(math.abs(speed), p.turningRadius, p.maxSpeed * p.minTurnSpeedFactor)
    self.heading = Steering.limitTurn(self.heading, desired, turnRate * dt)
    self.heading = V.wrapAngle(self.heading)
    local target = self.lodTarget
    if target > 0 and math.abs(V.wrapAngle(desired - self.heading)) >= math.pi * 0.5 then
        target = 0 -- gira en el sitio
    end
    local braking = p.braking
    if p.avoidance ~= 'v1' and target < speed then
        braking = braking * 2
    end
    self.speed = Steering.accelerate(speed, target, p.acceleration, braking, dt)
    local goalDist = V.distance(x, y, dest.x, dest.y)
    local step = self.speed * dt
    if step > goalDist then
        step = goalDist
    end
    local mx, my = x + math.cos(self.heading) * step, y + math.sin(self.heading) * step
    self.vx, self.vy = (mx - x) / dt, (my - y) / dt
    t.x, t.y = mx, my
    t.angle = self.heading + math.rad(p.orientacion)
    calmBody(t)
    if V.distance(mx, my, dest.x, dest.y) <= p.stoppingDistance then
        self:arrive(mx, my)
    end
end

-- Pasa a 'arrived' en (x, y): ahí vuelve después de hacer sitio.
function NavigationAgent:arrive(x, y)
    self.state = 'arrived'
    self.speed, self.vx, self.vy = 0, 0, 0
    self.holdX, self.holdY = x, y
    self.nudged, self.makingWay = false, false
    self.lodReady = false
    if self.props.congestion then
        resetCongestion(self, false)
    end
end

--- Hacer sitio (llegado, v2 con atascos): un vecino en marcha se le echó
-- encima (`nudged`), así que da un paso de esquiva v2 compartiendo el
-- desvío, sin salir de 'arrived', y después vuelve despacio a donde llegó.
-- Sin nadie cerca y en su sitio no hace nada (ni consulta vecinos).
function NavigationAgent:makeWay(dt)
    local p = self.props
    local t = self.target
    if t.isDestroyed and t:isDestroyed() then
        self.nudged, self.makingWay = false, false
        return
    end
    local x, y = t.x, t.y
    local hx, hy = self.holdX or x, self.holdY or y
    local dx, dy, off = V.normalize(hx - x, hy - y)
    if not self.nudged and off <= p.stoppingDistance then
        self.makingWay = false
        self.speed, self.vx, self.vy = 0, 0, 0
        return
    end
    self.nudged = false
    self.makingWay = true
    local target = 0
    if off > p.stoppingDistance then
        target = math.min(p.maxSpeed * 0.5, Steering.arrive(off, p.stoppingDistance * 0.5, p.maxSpeed, p.braking))
    else
        dx, dy = math.cos(self.heading), math.sin(self.heading)
    end
    self.prefX, self.prefY = dx, dy
    local neighbours = self:queryNeighbours(x, y)
    target = self:steerV2(neighbours, dx, dy, target, dt, nil, x, y, false)
    self.speed = Steering.accelerate(self.speed, target, p.acceleration, p.braking * 2, dt)
    local step = self.speed * dt
    if step > off and off > p.stoppingDistance then
        step = off
    end
    local mx, my = x + math.cos(self.heading) * step, y + math.sin(self.heading) * step
    self.vx, self.vy = (mx - x) / dt, (my - y) / dt
    t.x, t.y = mx, my
    t.angle = self.heading + math.rad(p.orientacion)
    calmBody(t)
end

--- v1: la esquiva es un vector que se suma a la dirección; giro acotado; la
-- rapidez es la preferida, o 0 si el objetivo queda a 90° o más. Devuelve la
-- rapidez objetivo. `elapsed` (por defecto `dt`): s desde la decisión
-- anterior, para el reloj de bloqueo de la esquiva (LOD); el giro es de `dt`.
function NavigationAgent:steerV1(neighbours, dirx, diry, target, dt, elapsed)
    local p = self.props
    elapsed = elapsed or dt
    local ax, ay = 0, 0
    if neighbours and #neighbours > 0 then
        ax, ay = self.avoidance:compute(self, neighbours, elapsed)
    else
        self.avoidance.blockedFor = 0
    end
    self.avoidVector.x, self.avoidVector.y = ax, ay
    if ax ~= 0 or ay ~= 0 then
        dirx, diry = dirx + ax * p.avoidanceWeight, diry + ay * p.avoidanceWeight
    end
    local nx, ny, nlen = V.normalize(dirx, diry)
    if nlen <= V.EPSILON then
        nx, ny = math.cos(self.heading), math.sin(self.heading)
    end
    self.steering.x, self.steering.y = nx, ny
    local desired = math.atan2(ny, nx)
    self.lodDesired = desired
    local turnRate = Steering.maxTurnRate(self.speed, p.turningRadius, p.maxSpeed * p.minTurnSpeedFactor)
    self.heading = Steering.limitTurn(self.heading, desired, turnRate * dt)
    self.heading = V.wrapAngle(self.heading)
    local err = math.abs(V.wrapAngle(desired - self.heading))
    if err >= math.pi * 0.5 then
        return 0
    end
    return target
end

--- v2: velocidad preferida → velocidad segura → giro acotado → rapidez
-- segura a lo largo del rumbo real (ver la cabecera). Devuelve la rapidez
-- objetivo (negativa = marcha atrás). `elapsed` (por defecto `dt`): s desde
-- la decisión anterior, para el reloj de bloqueo de la esquiva (LOD); el
-- giro es de `dt`.
function NavigationAgent:steerV2(neighbours, dirx, diry, target, dt, f, x, y, yielding, elapsed)
    local p = self.props
    elapsed = elapsed or dt
    local maxSpeed = p.maxSpeed
    local nx, ny, nlen = V.normalize(dirx, diry)
    if nlen <= V.EPSILON then
        nx, ny = math.cos(self.heading), math.sin(self.heading)
    end
    local pvx, pvy = nx * target, ny * target
    local cnx, cny, cc
    if f and not yielding and f:remaining() > 2 * p.lookAheadDistance then
        cnx, cny, cc = corridorLine(self, f, x, y, maxSpeed)
    end
    local la = self.avoidance
    local sx, sy = la:safeVelocity(self, neighbours, pvx, pvy, elapsed, maxSpeed, cnx, cny, cc)
    self.avoidVector.x, self.avoidVector.y = la.x, la.y
    local hx, hy = math.cos(self.heading), math.sin(self.heading)
    local sLen = math.sqrt(sx * sx + sy * sy)
    local reverse = false
    local desired
    if sLen > maxSpeed * 0.01 then
        local ux, uy = sx / sLen, sy / sLen
        -- Marcha atrás solo para esquivar o ceder: si la ruta pide dar la
        -- vuelta, se gira en el sitio como siempre.
        if ux * hx + uy * hy < 0 and p.reverseSpeed > 0 and (yielding or sx * pvx + sy * pvy < 0) then
            reverse = true
            desired = math.atan2(-uy, -ux)
        else
            desired = math.atan2(uy, ux)
        end
        self.steering.x, self.steering.y = ux, uy
    else
        desired = math.atan2(ny, nx)
        self.steering.x, self.steering.y = nx, ny
    end
    self.lodDesired = desired
    local turnRate = Steering.maxTurnRate(math.abs(self.speed), p.turningRadius, maxSpeed * p.minTurnSpeedFactor)
    self.heading = Steering.limitTurn(self.heading, desired, turnRate * dt)
    self.heading = V.wrapAngle(self.heading)
    hx, hy = math.cos(self.heading), math.sin(self.heading)
    local along = sx * hx + sy * hy
    local want
    if reverse then
        want = math.max(along, -p.reverseSpeed)
    elseif along > 0 and math.abs(V.wrapAngle(desired - self.heading)) < math.pi * 0.5 then
        want = along
    else
        want = 0 -- gira en el sitio
    end
    return la:speedAlong(hx, hy, -p.reverseSpeed, maxSpeed, want)
end

return NavigationAgent

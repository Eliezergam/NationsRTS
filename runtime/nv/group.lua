-- Navegación de grupos: puestos de destino, controlador de formación y la
-- petición de grupo que reparte una orden entre redes.
--
--   local Group = require('runtime.nv.group')
--   local slots = Group.DestinationSlots.generate(cx, cy, n, spacing, width, angle)
--   local gn = Group.GroupNavigation.new(manager, { spacing = 40, arrivedFraction = .8 })
--   local request = gn:moveGroup(agents, x, y)     -- GroupNavigationRequest
--   gn:update(dt)                                  -- anclas de formación
--   request:arrived()                              -- ≥ 80 % de los agentes en su puesto
--
-- Puestos (`DestinationSlots.generate`): una rejilla centrada en (cx, cy) y
-- orientada según `angle` (la tangente de la red en el destino, en el sentido
-- en que llega el grupo: la fila 0, la primera que se reparte, queda al
-- fondo). Las columnas
-- van en perpendicular al avance y las filas hacia atrás. Con `width` (ancho
-- navegable) el número de columnas es `floor(width / spacing)`, como mínimo 1:
-- un paso estrecho comprime la formación a una columna. Sin `width`, la
-- rejilla es casi cuadrada (`ceil(sqrt(n))` columnas). Dos puestos nunca
-- quedan a menos de `spacing`: dentro de una fila están a `spacing` y las
-- filas distan `spacing`.
--
-- Formación (`FormationController`): un ancla avanza por la ruta principal del
-- grupo (la distancia mínima de los miembros más `lead`) y cada miembro tiene
-- un desplazamiento (a lo largo, lateral) respecto a ella. El lateral se
-- multiplica por `compress`, que se acerca a `min(1, anchoDelSegmento /
-- anchoDeLaFormación)` a `compressRate` por segundo: al entrar en un paso
-- estrecho la formación se cierra poco a poco y se vuelve a abrir al salir,
-- nunca de golpe. El agente solo recibe un punto de formación al que tirar
-- (`setFormationTarget`), y su ruta y su esquiva mandan sobre él.
--
-- Petición (`GroupNavigationRequest`): clasifica por tag, proyecta el destino
-- por red, genera y VALIDA los puestos (`SlotValidator`: límites del mapa,
-- distancia a la red, tramo apto, hueco entre puestos y colisión estática si
-- el nivel la expone), los reparte por red (cada puesto, del centro hacia
-- fuera, se lo queda el agente libre más cercano, como `Units.assign`) y pide
-- las rutas. Un puesto sin candidato válido queda `failed = true` y la
-- formación se degrada de forma controlada: el agente que se quedó sin puesto
-- va al puesto válido más cercano (`degraded = true`; la esquiva local los
-- separa), y si no hay ninguno válido el grupo falla con 'sin puesto válido'.
-- `group.slotState` lo resume: 'ok' | 'degraded' | 'failed'.
--
-- Reordenar puestos al llegar (fase E, congestión en los últimos metros):
-- cada `slotReorderInterval` s (0,25) los miembros en marcha que ya están en
-- la zona de puestos (`group.slotZone`: la hondura de la rejilla + 4
-- separaciones alrededor del destino) y a más de una separación de su
-- puesto se reparten SUS puestos de nuevo: el que va más adelante en el
-- sentido de llegada se queda la fila más honda y, dentro de una fila, por
-- orden lateral. Así nadie que ya llegó tapa el paso a los que vienen detrás
-- hacia filas más hondas (con la esquiva v2 no se atraviesan). El progreso
-- se redondea a una separación y a igualdad se conserva el puesto actual:
-- no hay intercambios de ida y vuelta. Un cambio es `agent:retarget` (ruta
-- nueva por la caché/planificador; con flow field, solo el punto).
-- `opts.slotReorder = false` lo apaga. `group.slotSwaps` cuenta los cambios,
-- también los de `swapNearestSlot` (un miembro atascado en la zona cambia su
-- puesto por uno libre más cercano, ver la escalera de `agent.lua`).
--
-- Los agentes de una misma red con el mismo nodo de salida y de entrada
-- comparten los pasos de A* a través de `PathCache` (`route.steps` es la
-- misma tabla); cada uno conserva su seguimiento. Con planificador
-- (`manager.scheduler`) las rutas llegan a lo largo de varios cuadros: cada
-- agente arranca en cuanto tiene la suya, la petición sigue `active()`
-- mientras alguien esté 'pending' y el controlador de formación se crea
-- cuando todos han resuelto (`opts.priority` fija la prioridad de la cola;
-- `opts.immediate = true` mantiene todo síncrono).
--
-- Estrategia por grupo (mismo tag y destino), según cuántos agentes tiene
-- (`Group.strategyDefaults`, pisados por `manager.options.strategy = {
-- mediumFrom=, massiveFrom= }` y por `opts.strategy` para forzar una):
--
--   'small'   n < mediumFrom    A* por agente (compartido por la caché), sin formación
--   'medium'  n < massiveFrom   lo mismo más el `FormationController` (como hasta ahora)
--   'massive' n ≥ massiveFrom   UNA ruta global (`system:requestPath` desde el centro del
--                               grupo, por el planificador: plana o jerárquica, lo decide el
--                               sistema) → UN `FlowField` en su corredor, con la caja de
--                               salida del grupo (`flow_field.lua`) → cada agente lo sigue
--                               hasta su puesto (`agent:followFlowField`). Ni un A* por
--                               agente ni formación: la esquiva local reparte. Mientras
--                               llega la ruta global los agentes esperan 'pending'
--                               (`agent:awaitFlowField`). Si la ruta global falla (por
--                               ejemplo, el centro del grupo lejos de la red) el grupo cae a
--                               'medium' (`group.strategyFallback` dice por qué).
--
-- El campo se construye una vez por grupo y destino, no por agente, con las
-- propiedades del primer agente y el ancho del más exigente (`group.props`).
-- Se regenera (`refreshField`, con una ruta global nueva por el
-- planificador, prioridad 'repath') cuando `field:stale()`: un tramo bajo su
-- corredor cambió. Los campos activos se registran en el manager
-- (`manager.flowFields`) hasta que la petición termina (`release`).

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')
local SlotValidator = require('runtime.nv.slot_validator')
local FlowField = require('runtime.nv.flow_field')

local Group = {}

--- Cada cuánto (s) se reordenan los puestos de los que llegan.
Group.slotReorderInterval = 0.25

--- Umbrales de estrategia por tamaño de grupo (ver la cabecera y
-- `docs/NV.md` → "Estrategia").
Group.strategyDefaults = { mediumFrom = 2, massiveFrom = 60 }

--- Estrategia para `n` agentes con unos umbrales (`opts` puede ser nil).
function Group.chooseStrategy(n, opts)
    opts = type(opts) == 'table' and opts or Group.strategyDefaults
    local d = Group.strategyDefaults
    local mediumFrom = math.max(1, math.floor(NvUtil.finite(opts.mediumFrom, d.mediumFrom)))
    local massiveFrom = math.max(mediumFrom, math.floor(NvUtil.finite(opts.massiveFrom, d.massiveFrom)))
    if n >= massiveFrom then
        return 'massive'
    end
    if n >= mediumFrom then
        return 'medium'
    end
    return 'small'
end

--------------------------------------------------------------------------------
-- DestinationSlots
--------------------------------------------------------------------------------

local DestinationSlots = {}
Group.DestinationSlots = DestinationSlots

--- Lista de `{x=, y=}` para `n` unidades separadas `spacing`, centrada en
-- (cx, cy), orientada `angle` radianes; `width` opcional acota las columnas.
function DestinationSlots.generate(cx, cy, n, spacing, width, angle)
    n = math.max(0, math.floor(NvUtil.finite(n, 0)))
    spacing = NvUtil.atLeast(spacing, 40, 1e-3)
    angle = NvUtil.finite(angle, 0)
    local out = {}
    if n == 0 then
        return out
    end
    if n == 1 then
        out[1] = { x = cx, y = cy }
        return out
    end
    local cols = math.ceil(math.sqrt(n))
    width = NvUtil.finite(width)
    if width then
        cols = math.max(1, math.min(cols, math.floor(width / spacing + 1e-9)))
    end
    local rows = math.ceil(n / cols)
    local c, s = math.cos(angle), math.sin(angle)
    local index, sumAlong = 0, 0
    for row = 0, rows - 1 do
        local inRow = math.min(cols, n - index)
        local along = ((rows - 1) * 0.5 - row) * spacing
        for col = 0, inRow - 1 do
            local lateral = (col - (inRow - 1) * 0.5) * spacing
            index = index + 1
            out[index] = { along = along, lateral = lateral }
            sumAlong = sumAlong + along
        end
    end
    -- Con la última fila incompleta el centro de masas se corre hacia delante:
    -- se resta la media para que el centro quede exactamente en (cx, cy).
    local meanAlong = sumAlong / n
    for _, slot in ipairs(out) do
        local along, lateral = slot.along - meanAlong, slot.lateral
        slot.along = along
        slot.x, slot.y = cx + along * c - lateral * s, cy + along * s + lateral * c
    end
    return out
end

--- Reparto: cada puesto, en orden, se lo queda la unidad libre más cercana.
-- `positions` y `slots` son listas de `{x, y}`; devuelve `assign[i]` = índice
-- del puesto de la unidad i.
function DestinationSlots.assign(positions, slots)
    local assign, taken = {}, {}
    for slotIndex, slot in ipairs(slots) do
        local best, bestD
        for i, p in ipairs(positions) do
            if not taken[i] then
                local d = V.distanceSq(p.x, p.y, slot.x, slot.y)
                if not bestD or d < bestD then
                    best, bestD = i, d
                end
            end
        end
        if best then
            taken[best] = true
            assign[best] = slotIndex
        end
    end
    return assign
end

--------------------------------------------------------------------------------
-- FormationController
--------------------------------------------------------------------------------

local FormationController = NvUtil.class('FormationController')
Group.FormationController = FormationController

FormationController.defaults = { lead = 24, compressRate = 1.5 }

--- `members`: lista de `{ agent=, along=, lateral= }` (desplazamientos
-- respecto al ancla, en px). `route`: la ruta principal del grupo.
function FormationController:init(route, members, opts)
    opts = opts or {}
    local d = FormationController.defaults
    self.route = route
    self.members = members or {}
    self.lead = NvUtil.atLeast(opts.lead, d.lead, 0)
    self.compressRate = NvUtil.atLeast(opts.compressRate, d.compressRate, 0)
    self.spacing = NvUtil.atLeast(opts.spacing, 40, 1e-3)
    self.anchorD = 0
    self.anchor = { x = 0, y = 0, tx = 1, ty = 0 }
    self.compress = 1
    self.targetCompress = 1
    local maxLateral = 0
    for _, m in ipairs(self.members) do
        maxLateral = math.max(maxLateral, math.abs(m.lateral or 0))
    end
    self.formationWidth = maxLateral * 2 + self.spacing
    self.active = true
    self.lodElapsed = 0 -- s acumulados sin actualizar (formación lejana, LOD)
end

--- Avanza el ancla y reparte los puntos de formación.
function FormationController:update(dt)
    if not self.active or not self.route then
        return
    end
    dt = NvUtil.finite(dt, 0)
    -- El ancla va con el más rezagado: el que más distancia tiene por delante.
    -- Se mide por lo que falta (`remaining`), comparable entre rutas paralelas
    -- que acaban en puestos vecinos, no por la distancia recorrida en cada una.
    local maxRemaining, moving = 0, 0
    for _, m in ipairs(self.members) do
        local agent = m.agent
        if agent:isMoving() and agent.follower then
            moving = moving + 1
            maxRemaining = math.max(maxRemaining, agent.follower:remaining())
        end
    end
    if moving == 0 then
        self.active = false
        for _, m in ipairs(self.members) do
            m.agent:setFormationTarget(nil)
        end
        return
    end
    local total = self.route:length()
    self.anchorD = V.clamp(math.max(self.anchorD, total - maxRemaining + self.lead), 0, total)
    local ax, ay = self.route:positionAt(self.anchorD)
    local tx, ty = self.route:tangentAt(self.anchorD)
    if tx == 0 and ty == 0 then
        tx, ty = self.anchor.tx, self.anchor.ty
    end
    self.anchor.x, self.anchor.y, self.anchor.tx, self.anchor.ty = ax, ay, tx, ty
    -- Compresión según el ancho del segmento bajo el ancla.
    local seg = self.route:segmentAt(self.anchorD)
    local width = seg and seg.width or math.huge
    self.targetCompress = math.min(1, width / self.formationWidth)
    local rate = self.compressRate * dt
    if self.compress > self.targetCompress then
        self.compress = math.max(self.targetCompress, self.compress - rate)
    else
        self.compress = math.min(self.targetCompress, self.compress + rate)
    end
    -- Cerca del final la formación deja de tirar: cada uno va a su puesto.
    local nearEnd = total - self.anchorD < self.formationWidth
    for _, m in ipairs(self.members) do
        local agent = m.agent
        if nearEnd or not agent:isMoving() then
            agent:setFormationTarget(nil)
        else
            local along, lateral = m.along or 0, (m.lateral or 0) * self.compress
            agent:setFormationTarget(ax + along * tx - lateral * ty, ay + along * ty + lateral * tx)
        end
    end
end

--------------------------------------------------------------------------------
-- GroupNavigationRequest
--------------------------------------------------------------------------------

local GroupNavigationRequest = NvUtil.class('GroupNavigationRequest')
Group.GroupNavigationRequest = GroupNavigationRequest

GroupNavigationRequest.defaults = { spacing = 40, arrivedFraction = 0.8 }

local function tagOf(agent)
    return agent.props and agent.props.tag or nil
end

--- Clasifica, proyecta, reparte y pide las rutas. `opts`: `spacing`,
-- `arrivedFraction`, `formation` (false para no crear controlador).
function GroupNavigationRequest:init(manager, agents, x, y, opts)
    opts = opts or {}
    local d = GroupNavigationRequest.defaults
    self.manager = manager
    self.requestedDestination = { x = x, y = y }
    self.spacing = NvUtil.atLeast(opts.spacing, d.spacing, 1e-3)
    self.arrivedFraction = V.clamp(NvUtil.finite(opts.arrivedFraction, d.arrivedFraction), 0, 1)
    self.agents = {}
    self.groups = {}
    self.byTag = {}
    self.failed = {} -- { agent=, reason= }
    self.routed = {}
    self.pending = {} -- agentes que esperan ruta del planificador
    self.immediate = opts.immediate == true
    self.priority = opts.priority or 'order'
    self.formationEnabled = opts.formation ~= false
    self.slotValidation = opts.slotValidation ~= false
    self.slotReorder = opts.slotReorder ~= false
    self.slotOrientation = opts.slotOrientation == 'segment' and 'segment' or 'approach'
    local managerOptions = manager and manager.options or {}
    self.strategyOptions = type(opts.strategyThresholds) == 'table' and opts.strategyThresholds
        or managerOptions.strategy
    self.forcedStrategy = opts.strategy
    self.flowFieldOptions = type(opts.flowField) == 'table' and opts.flowField or managerOptions.flowField or {}
    for _, agent in ipairs(agents or {}) do
        self.agents[#self.agents + 1] = agent
        local tag = tagOf(agent)
        if not tag then
            self.failed[#self.failed + 1] = { agent = agent, reason = 'sin tag' }
        else
            local group = self.byTag[tag]
            if not group then
                group = {
                    tag = tag,
                    system = manager and manager:getSystem(tag) or nil,
                    agents = {},
                    slots = {},
                    assignments = {},
                    navigationDestination = nil,
                    formation = nil,
                    failed = {},
                    members = {},
                    spacing = 0,
                    slotState = 'ok',
                    degraded = 0,
                    validator = nil,
                    strategy = 'small',
                    strategyFallback = nil,
                    props = nil, -- propiedades representativas (ruta global y campo)
                    route = nil, -- ruta global compartida ('massive')
                    field = nil, -- FlowField del grupo ('massive')
                    globalRequest = nil,
                    refreshing = false,
                    slotAngle = 0,
                    slotZone = 0, -- radio de la zona de puestos (reordenación)
                    slotSwaps = 0,
                    reorderTimer = 0,
                    request = self, -- la petición (para `swapNearestSlot`)
                }
                self.byTag[tag] = group
                self.groups[#self.groups + 1] = group
            end
            group.agents[#group.agents + 1] = agent
        end
    end
    table.sort(self.groups, function(a, b)
        return a.tag < b.tag
    end)
    for _, group in ipairs(self.groups) do
        self:resolveGroup(group, opts)
    end
end

local function fail(self, group, agent, reason)
    group.failed[#group.failed + 1] = { agent = agent, reason = reason }
    self.failed[#self.failed + 1] = { agent = agent, reason = reason }
    if agent.state ~= 'noroute' then
        agent.state = 'noroute'
        agent.failReason = reason
    end
end

function GroupNavigationRequest:resolveGroup(group, opts)
    local system = group.system
    if not system then
        for _, agent in ipairs(group.agents) do
            fail(self, group, agent, 'sin red "' .. group.tag .. '"')
        end
        return
    end
    local maxProject = 0
    local maxRadius = 0
    for _, agent in ipairs(group.agents) do
        maxProject = math.max(maxProject, agent.props.maxProjectDistance or 0)
        maxRadius = math.max(maxRadius, agent.props.radius or 0)
    end
    local dest = self.requestedDestination
    local proj = system:projectPoint(dest.x, dest.y, maxProject)
    if not proj then
        for _, agent in ipairs(group.agents) do
            fail(self, group, agent, 'destino lejos de la red')
        end
        return
    end
    local tx, ty = proj.segment:tangentAt(proj.d)
    group.navigationDestination = { x = proj.x, y = proj.y, segment = proj.segment, d = proj.d, tx = tx, ty = ty }
    local spacing = math.max(self.spacing, maxRadius * 2 + 4)
    group.spacing = spacing
    local n = #group.agents
    -- La rejilla mira en el sentido en que LLEGA el grupo (del centro del
    -- grupo al destino), no en el del tramo: así la primera fila (la que se
    -- reparte primero, al más cercano) es la del fondo y los que llegan antes
    -- no tapan el paso a los demás (fase E: congestión en los últimos metros).
    -- `opts.slotOrientation = 'segment'` conserva la de antes (la del tramo).
    local cx, cy = 0, 0
    for _, agent in ipairs(group.agents) do
        cx, cy = cx + agent.target.x, cy + agent.target.y
    end
    cx, cy = cx / n, cy / n
    local angle = math.atan2(ty, tx)
    if self.slotOrientation == 'approach' and (proj.x - cx) * tx + (proj.y - cy) * ty < 0 then
        angle = angle + math.pi
    end
    group.slotAngle = angle
    group.slots = DestinationSlots.generate(proj.x, proj.y, n, spacing, proj.segment.width, angle)
    local depth = 0
    for _, slot in ipairs(group.slots) do
        depth = math.max(depth, math.abs(slot.along or 0), math.abs(slot.lateral or 0))
    end
    group.slotZone = depth + 4 * spacing
    local valid = self:validateSlots(group, maxProject, maxRadius, spacing)
    if #valid == 0 then
        group.slotState = 'failed'
        for _, agent in ipairs(group.agents) do
            fail(self, group, agent, 'sin puesto válido')
        end
        return
    end
    local positions = {}
    for i, agent in ipairs(group.agents) do
        positions[i] = { x = agent.target.x, y = agent.target.y }
    end
    local assign = DestinationSlots.assign(positions, valid)
    for i, agent in ipairs(group.agents) do
        local slot = valid[assign[i]]
        if not slot then
            -- Sin puesto propio: al válido más cercano (degradación controlada).
            slot = self:nearestSlot(valid, positions[i])
            group.degraded = group.degraded + 1
            group.slotState = 'degraded'
        end
        group.assignments[agent] = slot
    end
    -- Número de orden del grupo: a igualdad de `movementPriority`, la orden
    -- más antigua tiene paso (ver "Ceder el paso" en `agent.lua`).
    group.serial = NvUtil.nextSerial()
    group.strategy = self.forcedStrategy or Group.chooseStrategy(n, self.strategyOptions)
    if group.strategy == 'massive' then
        if not self:resolveMassive(group, positions, maxProject) then
            group.strategy = 'medium'
            self:resolvePerAgent(group)
        end
    else
        self:resolvePerAgent(group)
    end
    self:settle(group)
end

-- El agente pasa a ser del grupo: comparte su número de orden (prioridad de
-- paso) y no se cede el paso a sí mismo.
local function joinGroup(agent, group)
    agent.navGroup = group
    agent.orderSerial = group.serial
end

-- 'small' y 'medium': cada agente pide su ruta (compartida por la caché).
function GroupNavigationRequest:resolvePerAgent(group)
    local requestOpts = { immediate = self.immediate, priority = self.priority }
    for _, agent in ipairs(group.agents) do
        local slot = group.assignments[agent]
        local ok, err = agent:setDestination(slot.x, slot.y, requestOpts)
        if ok then
            joinGroup(agent, group)
            self.routed[#self.routed + 1] = agent
            group.members[#group.members + 1] = { agent = agent, along = slot.along or 0, lateral = slot.lateral or 0 }
            if agent:isPending() then
                self.pending[#self.pending + 1] = agent
            end
        else
            fail(self, group, agent, err or 'sin ruta')
        end
    end
end

-- Propiedades representativas del grupo: las del primero con el ancho del
-- más exigente (la ruta global y el campo tienen que valer para todos).
local function groupProps(group)
    local props = NvUtil.shallowCopy(group.agents[1].props)
    local width = 0
    for _, agent in ipairs(group.agents) do
        width = math.max(width, agent.props.width or 0)
    end
    if width > 0 then
        props.width = width
    end
    return props
end

-- Caja que envuelve una lista de posiciones.
local function boundingBox(positions)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(positions) do
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
    end
    if minX == math.huge then
        return nil
    end
    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

-- Punto de salida de la ruta global: el centro del grupo si llega a la red;
-- si no, el agente más cercano al centro. Devuelve x, y o nil.
local function globalStart(system, positions, maxProject)
    local n = #positions
    if n == 0 then
        return nil
    end
    local cx, cy = 0, 0
    for _, p in ipairs(positions) do
        cx, cy = cx + p.x, cy + p.y
    end
    cx, cy = cx / n, cy / n
    if system:projectPoint(cx, cy, maxProject) then
        return cx, cy
    end
    local best, bestD
    for _, p in ipairs(positions) do
        local d = V.distanceSq(p.x, p.y, cx, cy)
        if (not bestD or d < bestD) and system:projectPoint(p.x, p.y, maxProject) then
            best, bestD = p, d
        end
    end
    if best then
        return best.x, best.y
    end
    return nil
end

-- Pide la ruta global del grupo (por el planificador si lo hay). `done(route, err)`.
local function requestGlobal(self, group, sx, sy, priority, done)
    local system = group.system
    local nd = group.navigationDestination
    local scheduler = self.manager and self.manager.scheduler
    if scheduler then
        local request
        request = scheduler:request({
            system = system,
            sx = sx,
            sy = sy,
            tx = nd.x,
            ty = nd.y,
            props = group.props,
            owner = group,
            priority = priority,
            immediate = self.immediate,
            callback = function(route, err, req)
                if req.state == 'queued' or req ~= group.globalRequest then
                    return -- resuelta en el acto: se trata abajo
                end
                done(route, err)
            end,
        })
        if request.state == 'queued' then
            group.globalRequest = request
            return true
        end
        group.globalRequest = nil
        done(request.route, request.err)
        return request.route ~= nil
    end
    local route, err = system:requestPath(sx, sy, nd.x, nd.y, group.props)
    done(route, err)
    return route ~= nil
end

--- 'massive': una ruta global y un flow field para todo el grupo. Devuelve
-- false si ni siquiera hay desde dónde pedir la ruta (el grupo cae a
-- 'medium'); si la ruta global falla después, `globalRouteReady` degrada.
function GroupNavigationRequest:resolveMassive(group, positions, maxProject)
    local system = group.system
    group.props = groupProps(group)
    local sx, sy = globalStart(system, positions, maxProject)
    if not sx then
        group.strategyFallback = 'origen lejos de la red'
        return false
    end
    group.startArea = boundingBox(positions)
    for _, agent in ipairs(group.agents) do
        local slot = group.assignments[agent]
        local ok, err = agent:awaitFlowField(slot.x, slot.y)
        if ok then
            joinGroup(agent, group)
            self.routed[#self.routed + 1] = agent
            group.members[#group.members + 1] = { agent = agent, along = slot.along or 0, lateral = slot.lateral or 0 }
            self.pending[#self.pending + 1] = agent
        else
            fail(self, group, agent, err or 'sin ruta')
        end
    end
    -- Si la ruta llega (o falla) en el acto, `globalRouteReady` lo resuelve
    -- aquí mismo; si queda en cola, cuando el planificador la sirva.
    requestGlobal(self, group, sx, sy, self.priority, function(route, err)
        self:globalRouteReady(group, route, err)
    end)
    return true
end

-- Construye el campo del grupo sobre su ruta global y lo registra.
function GroupNavigationRequest:buildField(group, route)
    local manager = self.manager
    local nd = group.navigationDestination
    local opts = NvUtil.shallowCopy(self.flowFieldOptions)
    opts.destination = { x = nd.x, y = nd.y }
    opts.agent = group.props
    opts.startArea = group.startArea
    opts.blocked = manager and manager.blocked or nil
    opts.bounds = manager and manager.bounds or nil
    if opts.goalRadius == nil then
        opts.goalRadius = nd.segment.width * 0.5
    end
    -- Los puestos son fuentes a coste 0: el campo reparte a lo ancho de la
    -- zona de puestos en vez de embudar a todos hacia el destino proyectado.
    if opts.sources == nil then
        local sources = {}
        for _, slot in ipairs(group.slots) do
            if slot.valid then
                sources[#sources + 1] = { x = slot.x, y = slot.y }
            end
        end
        opts.sources = sources
    end
    local field = FlowField.new(group.system, route, opts)
    field:build()
    if manager and manager.trackFlowField then
        manager:trackFlowField(field)
    end
    return field
end

-- Radio a partir del cual cada agente deja el campo y va recto a su puesto:
-- el ancho del tramo de destino (los puestos se reparten a lo ancho) o dos
-- separaciones, lo que sea mayor.
local function switchRadius(group)
    return math.max(group.navigationDestination.segment.width, group.spacing * 2)
end

--- Llega (o falla) la ruta global de un grupo masivo.
function GroupNavigationRequest:globalRouteReady(group, route, err)
    group.globalRequest = nil
    if not route then
        -- Degradación controlada: cada agente pide su ruta como en 'medium'.
        group.strategy = 'medium'
        group.strategyFallback = err or 'sin ruta global'
        local members = group.members
        for i = #members, 1, -1 do
            table.remove(members, i)
        end
        for i = #self.routed, 1, -1 do
            if group.assignments[self.routed[i]] then
                table.remove(self.routed, i)
            end
        end
        self:resolvePerAgent(group)
        return
    end
    group.route = route
    group.field = self:buildField(group, route)
    local radius = switchRadius(group)
    for _, m in ipairs(group.members) do
        local agent = m.agent
        local slot = group.assignments[agent]
        agent:followFlowField(group.field, slot.x, slot.y, { route = route, switchRadius = radius })
    end
end

--- El corredor cambió (`field:stale()`): ruta global nueva desde el centro
-- de los que siguen en marcha y campo nuevo; mientras llega, siguen el viejo.
function GroupNavigationRequest:refreshField(group)
    local positions = {}
    for _, m in ipairs(group.members) do
        if m.agent:isMoving() then
            positions[#positions + 1] = { x = m.agent.target.x, y = m.agent.target.y }
        end
    end
    if #positions == 0 then
        return false
    end
    local maxProject = group.props.maxProjectDistance or group.system.options.maxProjectDistance
    local sx, sy = globalStart(group.system, positions, maxProject)
    local old = group.field
    if not sx then
        old:build() -- sin ruta nueva posible: al menos el corredor viejo con la red actual
        return false
    end
    group.refreshing = true
    local manager = self.manager
    if manager and manager.noteRepath then
        manager:noteRepath()
    end
    requestGlobal(self, group, sx, sy, 'repath', function(route, err)
        group.refreshing = false
        if not route then
            group.refreshFailed = err
            old:build()
            return
        end
        local field = self:buildField(group, route)
        if manager and manager.untrackFlowField then
            manager:untrackFlowField(old)
        end
        group.route, group.field = route, field
        local radius = switchRadius(group)
        for _, m in ipairs(group.members) do
            local agent = m.agent
            if agent:isMoving() and agent.flowField == old then
                agent:followFlowField(field, nil, nil, { route = route, switchRadius = radius })
            end
        end
    end)
    return true
end

-- Puesto válido más cercano a una posición.
function GroupNavigationRequest:nearestSlot(slots, p)
    local best, bestD
    for _, slot in ipairs(slots) do
        local d = V.distanceSq(p.x, p.y, slot.x, slot.y)
        if not bestD or d < bestD then
            best, bestD = slot, d
        end
    end
    return best
end

--- Valida los puestos de un grupo con `SlotValidator` (límites y colisión
-- estática del manager, distancia a la red del propio sistema). Marca cada
-- puesto (`valid`, `failed`, `fallback`, `reason`) y devuelve la lista de los
-- válidos, en el mismo orden (del centro hacia fuera).
function GroupNavigationRequest:validateSlots(group, maxProject, maxRadius, spacing)
    local valid = {}
    if not self.slotValidation then
        for _, slot in ipairs(group.slots) do
            slot.valid = true
            valid[#valid + 1] = slot
        end
        return valid
    end
    local manager = self.manager
    local validator = SlotValidator.new(group.system, {
        bounds = manager and manager.bounds or nil,
        blocked = manager and manager.blocked or nil,
        maxProjectDistance = maxProject,
        ringStep = spacing,
    })
    group.validator = validator
    -- El puesto tiene que valer para cualquier agente del grupo: se valida
    -- con el más exigente (el ancho mayor).
    local strictest = { width = 0 }
    for _, agent in ipairs(group.agents) do
        strictest.width = math.max(strictest.width, agent.props.width or 0)
    end
    for _, slot in ipairs(group.slots) do
        local placed, reason, original = validator:place(slot.x, slot.y, maxRadius, strictest)
        if placed then
            slot.x, slot.y = placed.x, placed.y
            slot.valid, slot.failed, slot.fallback = true, false, placed.fallback
            slot.reason = placed.fallback and reason or nil
            slot.taken = placed.taken
            valid[#valid + 1] = slot
        else
            slot.valid, slot.failed, slot.fallback = false, true, false
            slot.reason = original or reason
        end
    end
    return valid
end

-- Cuando ya nadie espera ruta: quita a los que fallaron, crea la formación.
function GroupNavigationRequest:settle(group)
    if group.settled then
        return
    end
    local members = group.members
    for i = #members, 1, -1 do
        local agent = members[i].agent
        local state = agent:getState()
        if state == 'pending' then
            return -- todavía falta alguien
        end
        if state == 'noroute' or state == 'blocked' then
            fail(self, group, agent, agent.failReason or 'sin ruta')
            table.remove(members, i)
            for j = #self.routed, 1, -1 do
                if self.routed[j] == agent then
                    table.remove(self.routed, j)
                end
            end
        end
    end
    group.settled = true
    -- Formación solo en 'medium': en 'small' cada uno va a su puesto y en
    -- 'massive' el campo y la esquiva reparten.
    if group.strategy ~= 'medium' then
        return
    end
    local mainRoute, mainLength = nil, -1
    for _, m in ipairs(members) do
        local route = m.agent.route
        if route then
            local len = route:length()
            if len > mainLength then
                mainRoute, mainLength = route, len
            end
        end
    end
    if self.formationEnabled and mainRoute and #members > 1 then
        group.formation = FormationController.new(mainRoute, members, { spacing = group.spacing })
        group.formation:update(0)
    end
end

--- Avanza las formaciones, regenera los campos cuyo corredor cambió y
-- cierra los grupos cuyas rutas ya llegaron.
function GroupNavigationRequest:update(dt)
    if #self.pending > 0 then
        for i = #self.pending, 1, -1 do
            if not self.pending[i]:isPending() then
                table.remove(self.pending, i)
            end
        end
        for _, group in ipairs(self.groups) do
            if not group.settled then
                self:settle(group)
            end
        end
    end
    local manager = self.manager
    local frame = manager and manager.lodFrame or 0
    for _, group in ipairs(self.groups) do
        local formation = group.formation
        if formation then
            -- Formación lejana (LOD): si ningún miembro va 'full', el ancla se
            -- mueve cada `group.lodInterval` cuadros (por cubetas, con el
            -- tiempo acumulado); con alguno 'full', en todos.
            formation.lodElapsed = formation.lodElapsed + dt
            local interval = 1
            if group.lodFrame == frame and group.lodInterval then
                interval = group.lodInterval
            end
            if interval <= 1 or (frame + (group.serial or 0)) % interval == 0 then
                local elapsed = formation.lodElapsed
                formation.lodElapsed = 0
                formation:update(elapsed)
            end
        end
        if self.slotReorder and group.navigationDestination then
            group.reorderTimer = group.reorderTimer + dt
            if group.reorderTimer >= Group.slotReorderInterval then
                group.reorderTimer = 0
                self:reorderSlots(group)
            end
        end
        if group.field and not group.refreshing and group.field:stale() then
            self:refreshField(group)
        end
    end
end

-- Buffers de la reordenación (uno por módulo: se usa de uno en uno).
local reorderAgents, reorderSlotsList = {}, {}
local reorderProgress, reorderDepth, reorderLateral = {}, {}, {}

local function byProgress(a, b)
    local pa, pb = reorderProgress[a], reorderProgress[b]
    if pa ~= pb then
        return pa > pb
    end
    return reorderDepth[a] > reorderDepth[b]
end

local function byDepth(a, b)
    local da, db = reorderDepth[a], reorderDepth[b]
    if da ~= db then
        return da > db
    end
    return reorderLateral[a] < reorderLateral[b]
end

local function byLateral(a, b)
    return reorderLateral[a] < reorderLateral[b]
end

-- Ordena la parte [i, j] de `list` con `cmp`, de forma ESTABLE (a
-- igualdad conserva el orden). Por inserción en bloques cortos; en los
-- largos, mezcla ascendente con un buffer del módulo: el mismo resultado
-- (las dos son estables) sin el coste cuadrático. Fase F: con 2500 agentes
-- en la zona de puestos, la inserción tardaba ~60 ms cada 0,25 s (155 ms con
-- 5000); ver `docs/NV.md` → "Rendimiento".
local SORT_INSERTION = 24
local sortBuffer = {}

local function insertionRange(list, i, j, cmp)
    for k = i + 1, j do
        local v = list[k]
        local m = k - 1
        while m >= i and cmp(v, list[m]) do
            list[m + 1] = list[m]
            m = m - 1
        end
        list[m + 1] = v
    end
end

local function sortRange(list, i, j, cmp)
    local n = j - i + 1
    if n <= SORT_INSERTION then
        insertionRange(list, i, j, cmp)
        return
    end
    -- Tramos iniciales ordenados por inserción; después, mezclas de tramos
    -- vecinos que doblan su ancho en cada pasada.
    for a = i, j, SORT_INSERTION do
        insertionRange(list, a, math.min(a + SORT_INSERTION - 1, j), cmp)
    end
    local buffer = sortBuffer
    local width = SORT_INSERTION
    while width < n do
        for a = i, j, 2 * width do
            local mid = a + width - 1
            if mid < j then
                local b = math.min(a + 2 * width - 1, j)
                for k = a, mid do
                    buffer[k - a + 1] = list[k]
                end
                local left, leftEnd = 1, mid - a + 1
                local right = mid + 1
                local out = a
                while left <= leftEnd and right <= b do
                    -- Estable: el de la derecha pasa delante solo si es
                    -- estrictamente menor.
                    if cmp(list[right], buffer[left]) then
                        list[out] = list[right]
                        right = right + 1
                    else
                        list[out] = buffer[left]
                        left = left + 1
                    end
                    out = out + 1
                end
                while left <= leftEnd do
                    list[out] = buffer[left]
                    left = left + 1
                    out = out + 1
                end
                for k = 1, leftEnd do
                    buffer[k] = nil
                end
            end
        end
        width = width * 2
    end
end

--- El orden estable de la reordenación de puestos (para las pruebas).
Group.stableSort = sortRange

--- Reparte de nuevo los puestos de los miembros en marcha que ya están en
-- la zona de puestos (ver la cabecera). Devuelve cuántos cambiaron.
function GroupNavigationRequest:reorderSlots(group)
    local nd = group.navigationDestination
    local assignments = group.assignments
    local ax, ay = math.cos(group.slotAngle), math.sin(group.slotAngle)
    local zone = group.slotZone
    local bin = math.max(1, group.spacing)
    local agents, slots = reorderAgents, reorderSlotsList
    local n = 0
    for _, m in ipairs(group.members) do
        local agent = m.agent
        local slot = assignments[agent]
        if slot and agent.state == 'moving' then
            local t = agent.target
            local dx, dy = t.x - nd.x, t.y - nd.y
            -- A menos de una separación de su puesto ya no se lo cambian.
            local sx, sy = t.x - slot.x, t.y - slot.y
            local lock = group.spacing
            if dx * dx + dy * dy <= zone * zone and sx * sx + sy * sy > lock * lock then
                n = n + 1
                agents[n] = agent
                slots[n] = slot
                reorderProgress[agent] = math.floor((dx * ax + dy * ay) / bin)
                reorderDepth[agent] = (slot.x - nd.x) * ax + (slot.y - nd.y) * ay
                reorderLateral[agent] = dx * -ay + dy * ax
                reorderDepth[slot] = reorderDepth[agent]
                reorderLateral[slot] = (slot.x - nd.x) * -ay + (slot.y - nd.y) * ax
            end
        end
    end
    local swaps = 0
    if n >= 2 then
        sortRange(agents, 1, n, byProgress)
        sortRange(slots, 1, n, byDepth)
        -- Por filas (misma hondura): emparejar por orden lateral.
        local rowBin = math.max(1, group.spacing * 0.25)
        local i = 1
        while i <= n do
            local row = math.floor(reorderDepth[slots[i]] / rowBin + 0.5)
            local j = i
            while j < n and math.floor(reorderDepth[slots[j + 1]] / rowBin + 0.5) == row do
                j = j + 1
            end
            sortRange(agents, i, j, byLateral)
            sortRange(slots, i, j, byLateral)
            for k = i, j do
                local agent, slot = agents[k], slots[k]
                if assignments[agent] ~= slot then
                    assignments[agent] = slot
                    agent:retarget(slot.x, slot.y)
                    swaps = swaps + 1
                end
            end
            i = j + 1
        end
    end
    for k = 1, n do
        local agent, slot = agents[k], slots[k]
        reorderProgress[agent], reorderDepth[agent], reorderLateral[agent] = nil, nil, nil
        reorderDepth[slot], reorderLateral[slot] = nil, nil
        agents[k], slots[k] = nil, nil
    end
    group.slotSwaps = group.slotSwaps + swaps
    return swaps
end

-- Dueño de cada puesto para `swapNearestSlot`: una tabla del módulo que se
-- rellena y se vacía en cada llamada (antes era una tabla nueva por llamada:
-- con 1000 agentes en la zona de puestos, ~44 KB por cuadro de basura).
local slotOwners = {}

--- Un miembro bloqueado dentro de la zona de puestos cambia su puesto por
-- el más cercano a él (de los que aún no ocupa nadie que haya llegado) si
-- está claramente más cerca que el suyo; el dueño de ese puesto se queda el
-- de `agent`. Lo pide la escalera de atascos del agente. Devuelve true si
-- cambió.
function GroupNavigationRequest:swapNearestSlot(group, agent)
    local assignments = group.assignments
    local mine = assignments[agent]
    if not mine then
        return false
    end
    local t = agent.target
    local x, y = t.x, t.y
    local current = V.distanceSq(x, y, mine.x, mine.y)
    local limit = math.sqrt(current) - group.spacing * 0.5
    if limit <= 0 then
        return false
    end
    local owners = slotOwners
    local members = group.members
    for i = 1, #members do
        local member = members[i].agent
        local slot = assignments[member]
        if slot then
            owners[slot] = member
        end
    end
    local best, bestD = nil, limit * limit
    local slots = group.slots
    for i = 1, #slots do
        local slot = slots[i]
        if slot ~= mine and slot.valid ~= false then
            local owner = owners[slot]
            if not owner or owner.state == 'moving' or owner.state == 'pending' then
                local d = V.distanceSq(x, y, slot.x, slot.y)
                if d < bestD then
                    best, bestD = slot, d
                end
            end
        end
    end
    local other = best and owners[best] or nil
    for i = 1, #members do
        local slot = assignments[members[i].agent]
        if slot then
            owners[slot] = nil
        end
    end
    if not best then
        return false
    end
    assignments[agent] = best
    agent:retarget(best.x, best.y)
    if other then
        assignments[other] = mine
        if other.state == 'moving' then
            other:retarget(mine.x, mine.y)
        elseif other.destination then
            other.destination.x, other.destination.y = mine.x, mine.y
        end
    end
    group.slotSwaps = group.slotSwaps + 1
    return true
end

--- Da de baja los campos de la petición (cuando termina).
function GroupNavigationRequest:release()
    local manager = self.manager
    for _, group in ipairs(self.groups) do
        if group.field and manager and manager.untrackFlowField then
            manager:untrackFlowField(group.field)
        end
        if group.globalRequest and manager and manager.scheduler then
            manager.scheduler:cancel(group.globalRequest)
            group.globalRequest = nil
        end
    end
    return self
end

--- ¿Sigue alguien en camino (o esperando ruta)?
function GroupNavigationRequest:active()
    for _, agent in ipairs(self.routed) do
        if agent:isMoving() or agent:isPending() then
            return true
        end
    end
    return false
end

--- ¿Cuántos agentes de la petición esperan todavía su ruta?
function GroupNavigationRequest:pendingCount()
    local n = 0
    for _, agent in ipairs(self.routed) do
        if agent:isPending() then
            n = n + 1
        end
    end
    return n
end

--- Llegado cuando al menos `fraction` (por defecto `arrivedFraction`) de los
-- agentes con ruta está en su puesto. Sin agentes con ruta: true.
function GroupNavigationRequest:arrived(fraction)
    fraction = NvUtil.finite(fraction, self.arrivedFraction)
    local n = #self.routed
    if n == 0 then
        return true
    end
    local done = 0
    for _, agent in ipairs(self.routed) do
        if agent:getState() == 'arrived' then
            done = done + 1
        end
    end
    return done / n >= fraction - 1e-9
end

function GroupNavigationRequest:group(tag)
    return self.byTag[tag]
end

--------------------------------------------------------------------------------
-- GroupNavigation
--------------------------------------------------------------------------------

local GroupNavigation = NvUtil.class('GroupNavigation')
Group.GroupNavigation = GroupNavigation

function GroupNavigation:init(manager, opts)
    self.manager = manager
    self.options = type(opts) == 'table' and opts or {}
    self.requests = {} -- activas
end

--- Manda `agents` (lista de `NavigationAgent`) hacia (x, y). Devuelve la
-- petición. `opts` puntuales (`spacing`, `priority`, `immediate`,
-- `formation`, `slotValidation`, `strategy`, `strategyThresholds`,
-- `flowField`) pisan las del constructor.
function GroupNavigation:moveGroup(agents, x, y, opts)
    local merged = NvUtil.shallowCopy(self.options)
    for k, v in pairs(opts or {}) do
        merged[k] = v
    end
    -- Un agente que recibe una orden nueva sale de las peticiones viejas.
    local set = {}
    for _, agent in ipairs(agents or {}) do
        set[agent] = true
    end
    for _, request in ipairs(self.requests) do
        for _, group in ipairs(request.groups) do
            if group.formation then
                for i = #group.formation.members, 1, -1 do
                    local m = group.formation.members[i]
                    if set[m.agent] then
                        m.agent:setFormationTarget(nil)
                        table.remove(group.formation.members, i)
                    end
                end
            end
        end
    end
    local request = GroupNavigationRequest.new(self.manager, agents, x, y, merged)
    self.requests[#self.requests + 1] = request
    return request
end

--- Avanza las formaciones y olvida las peticiones terminadas.
function GroupNavigation:update(dt)
    for i = #self.requests, 1, -1 do
        local request = self.requests[i]
        request:update(dt)
        if not request:active() then
            request:release()
            table.remove(self.requests, i)
        end
    end
end

function GroupNavigation:activeRequests()
    return self.requests
end

return Group

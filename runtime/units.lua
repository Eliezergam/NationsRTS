--- Selección de unidades y órdenes de mover, al estilo de OpenRA.
--
--   local Units = require('runtime.units')
--   local units = Units.new(level, camera, { speed = 120, turn = 180 })
--   function love.update(dt) level:update(dt); units:update(dt) end
--   function love.draw()
--       camera:attach(); level:draw(camera:visibleRect()); units:draw(); camera:detach()
--       units:drawHud(20, 20)                        -- opcional, fuera de la cámara
--   end
--   -- y los manejadores, después de la UI y del minimapa y antes de la cámara
--
-- Lo que hace, copiado de OpenRA (`WorldInteractionControllerWidget`,
-- `Selection.Combine`, `SelectionUtils.SelectActorsInBoxWithDeadzone`):
--
--   * **clic izquierdo** sobre una unidad la selecciona y suelta las demás; en
--     vacío, deselecciona. Con **Shift** el clic añade o quita esa unidad;
--   * **arrastre izquierdo**: caja de selección. Solo cuenta como caja si el
--     puntero se alejó más de `dragThreshold` px (24, el `SelectionDeadzone` de
--     OpenRA); si no, es un clic en el punto donde se soltó. Entran las unidades
--     cuyo rectángulo toca la caja (`Bounds.IntersectsWith` en OpenRA). Con
--     Shift la caja se suma a lo que había;
--   * la selección se aplica al **soltar** el botón, como OpenRA;
--   * **clic derecho** con unidades seleccionadas: si cae sobre una unidad
--     enemiga, orden de ataque; si cae sobre suelo, orden de mover al punto. Se
--     da al **soltar**, y no si el puntero se movió más de `orderDeadzone` px
--     (8, el `MouseScrollDeadzone` de OpenRA), para que arrastrar la cámara con
--     el botón derecho no mande a nadie a ningún sitio;
--   * un clic derecho **sobre el minimapa** (`opts.minimap`) manda las unidades
--     al punto del mapa que representa;
--   * cada orden deja una **marca** en el destino que se desvanece en 0,6 s.
--
-- Las cuentas (reparto de destinos, giro acotado, avance, llegada) son
-- funciones puras al final de la sección "Cuentas": se prueban sin ventana.
-- `love.*` solo aparece en `draw`, `drawHud` y en la consulta de Shift.
--
-- Con redes de navegación (`level.navigation`, ver `docs/NV.md`), las unidades
-- cuyo objeto lleva `navigation.tag` con red se mandan por NV: una sola orden
-- se convierte en `CommandSystem:moveUnits` (grupos por tag, puestos de
-- destino, rutas compartidas) y las mueve su `NavigationAgent` en
-- `level:update`, no `Units.step`. Las demás siguen exactamente como antes.
-- `opts.navigationDebug` (tabla de flags de `runtime/nv/debug.lua`) dibuja las
-- rutas de las unidades seleccionadas en `draw`. LOD de NV (fase F): la
-- cámara de `Units.new` es el foco del nivel (`level.navigationCamera`) y
-- `update` pasa la selección al manager (`setSelected`): las seleccionadas
-- van siempre a tope, estén donde estén.

local Transform = require('runtime.transform')

local Units = {}
Units.__index = Units

Units.defaults = {
    role = 'unit',
    speed = 120, -- px de mundo por segundo
    turn = 180, -- grados por segundo de giro máximo
    arrive = 6, -- px: a esta distancia del destino se da por llegada
    orientacion = 90, -- grados que se suman al rumbo para dibujar el sprite
    spacing = 40, -- px entre destinos de una orden de grupo
    attackRange = 96, -- px: distancia a la que una orden de atacar se detiene
    selectRadius = 12, -- px de pantalla extra para acertar con el dedo
    dragThreshold = 24, -- px de pantalla: SelectionDeadzone de OpenRA
    orderDeadzone = 8, -- px de pantalla: MouseScrollDeadzone de OpenRA
    tapSlop = 16, -- px de pantalla que puede moverse un dedo y seguir siendo toque
    markerTime = 0.6, -- segundos que dura la marca del destino
}

local TWO_PI = math.pi * 2

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

--------------------------------------------------------------------------------
-- Cuentas (puras)
--------------------------------------------------------------------------------

--- Ángulo llevado a (-π, π].
function Units.wrapAngle(a)
    a = (a + math.pi) % TWO_PI - math.pi
    if a <= -math.pi then
        a = a + TWO_PI
    end
    return a
end

--- Gira `heading` hacia `desired` sin pasar de `maxStep` radianes (por el lado
-- corto). Devuelve el rumbo nuevo y el giro aplicado. `maxStep` negativo o
-- infinito = giro instantáneo.
function Units.turnToward(heading, desired, maxStep)
    local diff = Units.wrapAngle(desired - heading)
    if maxStep and maxStep >= 0 and maxStep ~= math.huge then
        if diff > maxStep then
            diff = maxStep
        elseif diff < -maxStep then
            diff = -maxStep
        end
    end
    return heading + diff, diff
end

--- Un paso de movimiento cinemático, como el misil.
--
--   1. se gira hacia el destino sin pasar de `turnRate·dt`;
--   2. se elige la velocidad de avance:
--        * si el destino queda a 90° o más del rumbo, **no se avanza**: la unidad
--          gira en el sitio antes de arrancar, como hace `Move` en OpenRA
--          (encola un `Turn` antes de salir);
--        * si no, el círculo tangente al rumbo que pasa por el destino tiene
--          radio `r = d / (2·|sen α|)` (α = ángulo que falta, d = distancia).
--          A velocidad `v` y giro `ω` la unidad describe un círculo de radio
--          `v/ω`; si ese radio es mayor que `r` el destino queda dentro de la
--          curva y la unidad lo rodearía para siempre. Por eso
--          `v = min(speed, r·ω)`: frena lo justo para que su curva pase por el
--          destino. Lejos y de frente, `r` es enorme y va a toda velocidad;
--   3. se avanza `min(v·dt, d)` en el rumbo actual, así nunca se pasa de largo;
--   4. llega cuando la distancia queda en `arrive` o menos.
--
-- Devuelve x, y, rumbo, llegada(bool), distancia restante.
function Units.step(x, y, heading, tx, ty, dt, speed, turnRate, arrive)
    local dx, dy = tx - x, ty - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= arrive then
        return x, y, heading, true, d
    end
    local desired = math.atan2(dy, dx)
    local instant = not turnRate or turnRate <= 0 or turnRate == math.huge
    if instant then
        heading = desired
    else
        heading = Units.turnToward(heading, desired, turnRate * dt)
    end
    local rest = math.abs(Units.wrapAngle(desired - heading))
    local v = speed
    if rest >= math.pi * 0.5 then
        v = 0
    elseif not instant and rest > 1e-9 then
        local r = d / (2 * math.sin(rest))
        v = math.min(speed, r * turnRate)
    end
    local advance = math.min(v * dt, d)
    x = x + math.cos(heading) * advance
    y = y + math.sin(heading) * advance
    dx, dy = tx - x, ty - y
    d = math.sqrt(dx * dx + dy * dy)
    return x, y, heading, d <= arrive, d
end

--- Desplazamientos de una formación de `n` puestos separados `spacing` px,
-- centrados en (0, 0). Lista de `{x, y}`.
--
--   * n = 1: el propio punto.
--   * 2 ≤ n ≤ 6: un polígono regular de radio `s / (2·sen(π/n))`, de modo que
--     dos vecinos quedan exactamente a `s` (2 → segmento de lado s, 3 →
--     triángulo, … 6 → hexágono de radio s).
--   * n ≥ 7: un puesto en el centro y anillos de radio `k·s`; el anillo k admite
--     `floor(π / asin(1/(2k)))` puestos (6, 12, 18…), que es lo que cabe con la
--     cuerda entre vecinos `2·k·s·sen(π/m) ≥ s`. El último anillo reparte los
--     que queden **a partes iguales** en su circunferencia; si solo quedara uno,
--     se quita el del centro y ese anillo lleva dos, para que el grupo siga
--     centrado.
--
-- Por qué ninguno queda a menos de `s` de otro: dentro de un anillo la cuerda
-- es ≥ s por construcción, y entre anillos distintos la distancia es al menos
-- la diferencia de radios, que es s. Por qué están centrados: m ≥ 2 puntos
-- repartidos por igual en una circunferencia suman cero, y el centro es (0, 0).
function Units.formation(n, spacing)
    n = math.max(0, math.floor(finite(n, 0)))
    local s = math.max(0, finite(spacing, Units.defaults.spacing))
    local out = {}
    if n == 0 then
        return out
    end
    if n == 1 then
        out[1] = { x = 0, y = 0 }
        return out
    end
    local function ring(radius, m)
        for i = 0, m - 1 do
            local a = TWO_PI * i / m - math.pi * 0.5
            out[#out + 1] = { x = math.cos(a) * radius, y = math.sin(a) * radius }
        end
    end
    if n <= 6 then
        ring(s / (2 * math.sin(math.pi / n)), n)
        return out
    end
    local counts, left, k = {}, n - 1, 1
    while left > 0 do
        local capacity = math.floor(math.pi / math.asin(1 / (2 * k)))
        counts[k] = math.min(capacity, left)
        left = left - counts[k]
        k = k + 1
    end
    local center = true
    if counts[#counts] == 1 then
        center = false
        counts[#counts] = 2
    end
    if center then
        out[1] = { x = 0, y = 0 }
    end
    for ringIndex, m in ipairs(counts) do
        ring(ringIndex * s, m)
    end
    return out
end

--- Destinos absolutos para `n` unidades alrededor de (cx, cy).
function Units.destinations(cx, cy, n, spacing)
    local list = Units.formation(n, spacing)
    for _, p in ipairs(list) do
        p.x, p.y = cx + p.x, cy + p.y
    end
    return list
end

--- Reparto de puestos: cada puesto, del centro hacia fuera, se lo queda la
-- unidad libre más cercana. `positions` y `slots` son listas de `{x, y}`;
-- devuelve `assign[i] = índice del puesto de la unidad i`.
function Units.assign(positions, slots)
    local assign, taken = {}, {}
    for slotIndex, slot in ipairs(slots) do
        local best, bestD
        for i, p in ipairs(positions) do
            if not taken[i] then
                local dx, dy = p.x - slot.x, p.y - slot.y
                local d = dx * dx + dy * dy
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

--- Semiejes del rectángulo alineado que envuelve un sprite girado.
function Units.halfExtents(w, h, angle)
    local c, s = math.abs(math.cos(angle or 0)), math.abs(math.sin(angle or 0))
    return c * w * 0.5 + s * h * 0.5, s * w * 0.5 + c * h * 0.5
end

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

--- `opts`: `role`, `playerId`, `speed`, `turn`, `arrive`, `orientacion`,
-- `spacing`, `attackRange`, `selectRadius`, `dragThreshold`, `orderDeadzone`, `tapSlop`,
-- `markerTime`, `minimap`, `colors = { marker = {r,g,b}, box = {r,g,b}, ring = {r,g,b} }`.
function Units.new(level, camera, opts)
    opts = opts or {}
    local d = Units.defaults
    local self = setmetatable({}, Units)
    self.level, self.camera = level, camera
    -- Con minimapa, un clic derecho sobre él manda las unidades a ese punto
    -- del mapa, como en OpenRA.
    self.minimap = opts.minimap
    self.role = opts.role or d.role
    self.playerId = opts.playerId
    self.speed = math.max(0, finite(opts.speed, d.speed))
    self.turn = finite(opts.turn, d.turn)
    self.arrive = math.max(0, finite(opts.arrive, d.arrive))
    self.orientacion = finite(opts.orientacion, d.orientacion)
    self.spacing = math.max(0, finite(opts.spacing, d.spacing))
    self.attackRange = math.max(0, finite(opts.attackRange, d.attackRange))
    self.selectRadius = math.max(0, finite(opts.selectRadius, d.selectRadius))
    self.dragThreshold = math.max(0, finite(opts.dragThreshold, d.dragThreshold))
    self.orderDeadzone = math.max(0, finite(opts.orderDeadzone, d.orderDeadzone))
    self.tapSlop = math.max(0, finite(opts.tapSlop, d.tapSlop))
    self.markerTime = math.max(1e-3, finite(opts.markerTime, d.markerTime))
    local colors = type(opts.colors) == 'table' and opts.colors or {}
    self.colors = {
        marker = colors.marker or { 0.35, 1, 0.35 },
        box = colors.box or { 1, 1, 1 },
        ring = colors.ring or { 1, 1, 1 },
    }
    self.navigationDebug = type(opts.navigationDebug) == 'table' and opts.navigationDebug or nil
    self.commands = nil -- CommandSystem de NV, creado al dar la primera orden
    self.navigationSelected = {} -- agentes seleccionados (buffer para el LOD de NV)
    -- LOD de NV: el nivel toma el foco de esta cámara (`camera:visibleRect()`).
    if level and camera and level.navigationCamera == nil then
        level.navigationCamera = camera
    end
    self.selection, self.selectedSet = {}, {}
    self.moving = {} -- nodo -> { x, y, heading } o { x, y, heading, agent }
    self.markers = {}
    self.shiftDown = false
    self.press, self.rightPress, self.tap = nil, nil, nil
    return self
end

local function rtsOf(node)
    local data = node.data
    return type(data) == 'table' and type(data.rts) == 'table' and data.rts or nil
end

local function alive(node)
    return node and not node:isDestroyed()
end

--- ¿Es una unidad que este jugador puede seleccionar?
function Units:isUnit(node)
    if not alive(node) then
        return false
    end
    local rts = rtsOf(node)
    if not rts or rts.role ~= self.role then
        return false
    end
    if self.playerId ~= nil and rts.playerId ~= self.playerId then
        return false
    end
    return true
end

--- Todas las unidades seleccionables, en el orden de dibujo (capas y objetos).
function Units:units()
    local list = {}
    local scene = self.level and self.level.scene
    if not scene then
        return list
    end
    for _, node in ipairs(scene:objects()) do
        if self:isUnit(node) then
            list[#list + 1] = node
        end
    end
    return list
end

-- Un número de `properties`, que el inspector puede guardar como texto.
local function property(node, key)
    local data = node.data
    local props = type(data) == 'table' and type(data.properties) == 'table' and data.properties or nil
    return props and tonumber(props[key]) or nil
end

--- Velocidad de una unidad: `properties.velocidad`, luego `rts.speed`, luego la
-- de `Units.new`.
function Units:speedOf(node)
    local rts = rtsOf(node)
    return property(node, 'velocidad') or (rts and tonumber(rts.speed)) or self.speed
end

--- Giro máximo en grados por segundo: `properties.giro`, luego `rts.turn`,
-- luego el de `Units.new`.
function Units:turnOf(node)
    local rts = rtsOf(node)
    return property(node, 'giro') or (rts and tonumber(rts.turn)) or self.turn
end

--- Grados que se suman al rumbo para dibujar: `properties.orientacion`, o el de
-- `Units.new`.
function Units:orientacionOf(node)
    return property(node, 'orientacion') or self.orientacion
end

--- Rumbo actual (radianes) deducido del ángulo del sprite.
function Units:headingOf(node)
    local state = self.moving[node]
    if state then
        return state.agent and state.agent.heading or state.heading
    end
    return (node.angle or 0) - math.rad(self:orientacionOf(node))
end

-- Copia ligera del objeto con la posición y el ángulo **vivos** (el cuerpo
-- físico manda), para que `Transform.contains` mida donde se ve la unidad.
local function liveShape(node, grow)
    local o = node.data
    local proxy = {
        x = node.x,
        y = node.y,
        rotation = node.angle or 0,
        w = o.w,
        h = o.h,
        scaleX = o.scaleX,
        scaleY = o.scaleY,
        shape = o.shape,
        polygon = o.polygon,
    }
    if grow and grow > 0 then
        local w, h = Transform.size(proxy)
        proxy.w, proxy.h = w + grow * 2, h + grow * 2
        proxy.scaleX, proxy.scaleY = 1, 1
        if proxy.shape == 'polygon' then
            proxy.shape = 'rectangle'
        end
    end
    return proxy
end

-- Píxeles de mundo por píxel de pantalla.
function Units:worldPerPixel()
    local cam = self.camera
    if not cam then
        return 1
    end
    local _, _, scale = cam:view()
    return 1 / (scale * cam.zoom)
end

function Units:toWorld(sx, sy)
    if self.camera then
        return self.camera:toWorld(sx, sy)
    end
    return sx, sy
end

--- Punto de mundo de una orden dada en la pantalla: sobre el minimapa, el
-- punto del mapa que representa; fuera, el que hay bajo el puntero.
function Units:orderPoint(sx, sy)
    local radar = self.minimap
    if radar and radar:contains(sx, sy) then
        return radar:toWorldFromScreen(sx, sy)
    end
    return self:toWorld(sx, sy)
end

--- La unidad de más arriba (la última que se dibuja) bajo el punto de mundo.
-- `grow` = px de mundo extra alrededor del sprite.
function Units:unitAt(wx, wy, grow)
    local hit
    for _, node in ipairs(self:units()) do
        if
            Transform.contains(liveShape(node), wx, wy)
            or (grow and grow > 0 and Transform.contains(liveShape(node, grow), wx, wy))
        then
            hit = node
        end
    end
    return hit
end

--- Unidades cuyo rectángulo toca el rectángulo de mundo (x1,y1)-(x2,y2).
function Units:unitsInRect(x1, y1, x2, y2)
    if x1 > x2 then
        x1, x2 = x2, x1
    end
    if y1 > y2 then
        y1, y2 = y2, y1
    end
    local list = {}
    for _, node in ipairs(self:units()) do
        local w, h = Transform.size(node.data)
        local ex, ey = Units.halfExtents(w, h, node.angle or 0)
        local nx, ny = node.x, node.y
        if nx + ex >= x1 and nx - ex <= x2 and ny + ey >= y1 and ny - ey <= y2 then
            list[#list + 1] = node
        end
    end
    return list
end

--- Unidades cuyo punto cae dentro de un rectángulo de la pantalla.
function Units:unitsInScreenRect(x1, y1, x2, y2)
    if x1 > x2 then
        x1, x2 = x2, x1
    end
    if y1 > y2 then
        y1, y2 = y2, y1
    end
    local list = {}
    for _, node in ipairs(self:units()) do
        local sx, sy = self.camera:toScreen(node.x, node.y)
        if sx >= x1 and sx <= x2 and sy >= y1 and sy <= y2 then
            list[#list + 1] = node
        end
    end
    return list
end

-- Selección --------------------------------------------------------------------

function Units:selected()
    local list = {}
    for _, node in ipairs(self.selection) do
        list[#list + 1] = node
    end
    return list
end

function Units:isSelected(node)
    return self.selectedSet[node] == true
end

function Units:clear()
    self.selection, self.selectedSet = {}, {}
    return self
end

--- Sustituye la selección. Solo entra lo que es una unidad seleccionable.
function Units:select(list)
    self:clear()
    return self:add(list)
end

function Units:add(list)
    for _, node in ipairs(list or {}) do
        if self:isUnit(node) and not self.selectedSet[node] then
            self.selectedSet[node] = true
            self.selection[#self.selection + 1] = node
        end
    end
    return self
end

function Units:remove(node)
    if not self.selectedSet[node] then
        return self
    end
    self.selectedSet[node] = nil
    for i = #self.selection, 1, -1 do
        if self.selection[i] == node then
            table.remove(self.selection, i)
        end
    end
    return self
end

function Units:toggle(node)
    if self.selectedSet[node] then
        self:remove(node)
    else
        self:add({ node })
    end
    return self
end

--- `Selection.Combine` de OpenRA: un clic con Shift alterna la unidad; sin
-- Shift la sustituye (o vacía). Una caja con Shift suma; sin Shift sustituye.
function Units:combine(list, isCombine, isClick)
    if isClick then
        local node = list[1]
        if isCombine then
            if node then
                self:toggle(node)
            end
        else
            self:select(node and { node } or {})
        end
    elseif isCombine then
        self:add(list)
    else
        self:select(list)
    end
    return self
end

-- Órdenes ----------------------------------------------------------------------

--- Separación de la formación para un grupo: `spacing`, o el tamaño de la
-- unidad más grande del grupo si es mayor (el lado mayor de su rectángulo), para
-- que dos unidades grandes no se solapen al llegar.
function Units:spacingFor(nodes)
    local s = self.spacing
    if #nodes < 2 then
        return s
    end
    for _, node in ipairs(nodes) do
        local w, h = Transform.size(node.data)
        s = math.max(s, w, h)
    end
    return s
end

--- Alcance de ataque de una unidad: `properties.attackRange`, `properties.alcance`,
-- `rts.attackRange`, o el general de `Units.new`.
function Units:attackRangeOf(node)
    local rts = rtsOf(node)
    return property(node, 'attackRange')
        or property(node, 'alcance')
        or (rts and tonumber(rts.attackRange))
        or self.attackRange
end

local function playerOf(node)
    local rts = rtsOf(node)
    return rts and rts.playerId or nil
end

function Units:isAttackTarget(target, attacker)
    if not alive(target) then
        return false
    end
    local trts = rtsOf(target)
    if not trts or trts.role ~= self.role then
        return false
    end
    if not attacker then
        return true
    end
    local aPlayer, tPlayer = playerOf(attacker), trts.playerId
    return aPlayer ~= nil and tPlayer ~= nil and aPlayer ~= tPlayer
end

function Units:attackTargetAt(wx, wy, grow)
    local hit
    local attackers = self.selection
    for _, node in ipairs((self.level and self.level.scene and self.level.scene:objects()) or {}) do
        local canAttack = false
        for _, attacker in ipairs(attackers) do
            if self:isAttackTarget(node, attacker) then
                canAttack = true
                break
            end
        end
        if
            canAttack
            and (
                Transform.contains(liveShape(node), wx, wy)
                or (grow and grow > 0 and Transform.contains(liveShape(node, grow), wx, wy))
            )
        then
            hit = node
        end
    end
    return hit
end

function Units.attackPoint(node, target, range)
    range = math.max(0, finite(range, Units.defaults.attackRange))
    local dx, dy = target.x - node.x, target.y - node.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= range or d <= 1e-9 then
        return node.x, node.y, true, d
    end
    return target.x - dx / d * range, target.y - dy / d * range, false, d
end

function Units:setMoveState(node, x, y, queue)
    self.moving[node] = { kind = 'move', x = x, y = y, heading = self:headingOf(node), queue = queue }
    node.data.orden = { x = x, y = y }
    return self.moving[node]
end

function Units:setAttackState(node, target, range, x, y, queue)
    self.moving[node] =
        { kind = 'attack', target = target, range = range, x = x, y = y, heading = self:headingOf(node), queue = queue }
    node.data.orden = { x = target.x, y = target.y, attack = true, target = target:path() }
    return self.moving[node]
end

function Units:enqueue(node, command)
    local state = self.moving[node]
    if not state then
        return false
    end
    state.queue = state.queue or {}
    state.queue[#state.queue + 1] = command
    return true
end

function Units:startQueued(node, command, queue)
    if command.kind == 'attack' then
        return self:orderAttack(command.target, { node }, { queue = queue })
    end
    return self:order(command.x, command.y, { node }, { queue = queue })
end

function Units:finishOrder(node, state)
    local queue = state and state.queue
    if queue and #queue > 0 then
        local command = table.remove(queue, 1)
        self:startQueued(node, command, queue)
    else
        self.moving[node] = nil
        if type(node.data) == 'table' then
            node.data.orden = nil
        end
    end
end

-- Navegación por rutas (NV) ------------------------------------------------------

--- El agente de navegación de una unidad, si su tag tiene red en este nivel.
function Units:agentOf(node)
    local level = self.level
    local agents = level and level.agents
    local agent = agents and agents[node.data]
    if agent and level.navigation and agent:hasNetwork() then
        return agent
    end
    return nil
end

--- El `CommandSystem` de NV (se crea con la primera orden), o nil sin redes.
function Units:commandSystem()
    if self.commands then
        return self.commands
    end
    local nav = self.level and self.level.navigation
    if not nav then
        return nil
    end
    local Commands = require('runtime.nv.commands')
    local Group = require('runtime.nv.group')
    self.commands = Commands.CommandSystem.new(nav, Group.GroupNavigation.new(nav, { spacing = self.spacing }))
    return self.commands
end

--- Manda las unidades (por defecto las seleccionadas) hacia (x, y) en el mundo,
-- repartidas en formación. Devuelve la lista `{ node, x, y }` de destinos.
--
-- Las unidades con agente de navegación van por NV en una sola orden
-- (`CommandSystem:moveUnits`): entrada `{ node, x, y, agent }` con su puesto, o
-- `{ node, x, y, agent, failed = motivo }` si su red no llega (no se mueven:
-- la orden falla limpiamente). Las demás siguen el reparto cinemático de siempre.
function Units:order(x, y, list, opts)
    opts = opts or {}
    list = list or self.selection
    local nodes = {}
    for _, node in ipairs(list) do
        if alive(node) then
            nodes[#nodes + 1] = node
        end
    end
    if #nodes == 0 then
        return {}
    end
    local append = opts.append == true
    local result = {}
    local plain = nodes
    local commands = self:commandSystem()
    if commands then
        plain = {}
        local navNodes, agents = {}, {}
        for _, node in ipairs(nodes) do
            local agent = self:agentOf(node)
            if append and self:enqueue(node, { kind = 'move', x = x, y = y }) then
                result[#result + 1] = { node = node, x = x, y = y, queued = true }
            elseif agent then
                navNodes[#navNodes + 1] = node
                agents[#agents + 1] = agent
            else
                plain[#plain + 1] = node
            end
        end
        if #agents > 0 then
            -- Orden directa del jugador a su selección: la prioridad más alta de la cola.
            commands:moveUnits(agents, x, y, { spacing = self:spacingFor(navNodes), priority = 'selected' })
            for i, node in ipairs(navNodes) do
                local agent = agents[i]
                -- 'pending': la ruta llega en los próximos cuadros (planificador); la
                -- orden queda abierta igual que si ya se moviera.
                if agent:isMoving() or agent:isPending() then
                    local dest = agent.destination
                    self.moving[node] = {
                        kind = 'move',
                        x = dest.x,
                        y = dest.y,
                        heading = agent.heading,
                        agent = agent,
                        queue = opts.queue,
                    }
                    node.data.orden = { x = dest.x, y = dest.y }
                    result[#result + 1] = { node = node, x = dest.x, y = dest.y, agent = agent }
                else
                    self.moving[node] = nil
                    node.data.orden = nil
                    result[#result + 1] =
                        { node = node, x = x, y = y, agent = agent, failed = agent.failReason or agent:getState() }
                end
            end
        end
    end
    if #plain > 0 then
        local slots = Units.destinations(x, y, #plain, self:spacingFor(plain))
        local positions = {}
        for i, node in ipairs(plain) do
            positions[i] = { x = node.x, y = node.y }
        end
        local assign = Units.assign(positions, slots)
        for i, node in ipairs(plain) do
            local slot = slots[assign[i]]
            if append and self:enqueue(node, { kind = 'move', x = slot.x, y = slot.y }) then
                result[#result + 1] = { node = node, x = slot.x, y = slot.y, queued = true }
            else
                self:setMoveState(node, slot.x, slot.y, opts.queue)
                result[#result + 1] = { node = node, x = slot.x, y = slot.y }
            end
        end
    end
    self.markers[#self.markers + 1] = { x = x, y = y, age = 0 }
    return result
end

function Units:orderAttack(target, list, opts)
    opts = opts or {}
    list = list or self.selection
    if not alive(target) then
        return {}
    end
    local append = opts.append == true
    local result = {}
    for _, node in ipairs(list) do
        if alive(node) and self:isAttackTarget(target, node) then
            local range = self:attackRangeOf(node)
            local x, y, inRange = Units.attackPoint(node, target, range)
            if append and self:enqueue(node, { kind = 'attack', target = target }) then
                result[#result + 1] = { node = node, target = target, queued = true, attack = true }
            elseif inRange then
                self.moving[node] = nil
                node.data.orden = nil
                result[#result + 1] =
                    { node = node, target = target, x = node.x, y = node.y, attack = true, inRange = true }
            else
                local ordered = self:order(x, y, { node }, { queue = opts.queue })
                local state = self.moving[node]
                if state then
                    state.kind = 'attack'
                    state.target = target
                    state.range = range
                    state.x, state.y = x, y
                    state.queue = opts.queue
                    node.data.orden = { x = target.x, y = target.y, attack = true, target = target:path() }
                end
                result[#result + 1] = {
                    node = node,
                    target = target,
                    x = x,
                    y = y,
                    attack = true,
                    agent = ordered[1] and ordered[1].agent or nil,
                }
            end
        end
    end
    return result
end

--- Detiene una unidad (o todas las que se mueven) donde esté.
function Units:stop(node)
    local function halt(n)
        local state = self.moving[n]
        if state and state.agent then
            state.agent:clearDestination()
        end
        self.moving[n] = nil
        if type(n.data) == 'table' then
            n.data.orden = nil
        end
    end
    if node then
        halt(node)
    else
        for n in pairs(self.moving) do
            halt(n)
        end
    end
    return self
end

function Units:isMoving(node)
    return self.moving[node] ~= nil
end

--- LOD de NV: las unidades seleccionadas van siempre a tope aunque estén
-- lejos de la cámara (`NavigationManager:setSelected`).
function Units:syncNavigationSelection()
    local level = self.level
    local nav = level and level.navigation
    if not nav or not nav.setSelected then
        return
    end
    local agents = level.agents
    local list = self.navigationSelected
    local n = 0
    for _, node in ipairs(self.selection) do
        local agent = agents and agents[node.data]
        if agent then
            n = n + 1
            list[n] = agent
        end
    end
    for i = #list, n + 1, -1 do
        list[i] = nil
    end
    nav:setSelected(list)
end

function Units:update(dt)
    dt = math.max(0, finite(dt, 0))
    for i = #self.selection, 1, -1 do
        local node = self.selection[i]
        if not alive(node) then
            self.selectedSet[node] = nil
            table.remove(self.selection, i)
        end
    end
    self:syncNavigationSelection()
    if self.commands then
        self.commands:update(dt)
    end
    for node, state in pairs(self.moving) do
        if not alive(node) then
            self.moving[node] = nil
        elseif state.kind == 'attack' and not alive(state.target) then
            self:finishOrder(node, state)
        elseif state.agent then
            -- La mueve su NavigationAgent en `level:update`; aquí solo se
            -- cierra la orden cuando el agente ha llegado o se ha rendido
            -- (mientras espera ruta del planificador sigue abierta).
            if state.kind == 'attack' then
                local x, y, inRange = Units.attackPoint(node, state.target, state.range)
                node.data.orden =
                    { x = state.target.x, y = state.target.y, attack = true, target = state.target:path() }
                if inRange then
                    self:finishOrder(node, state)
                elseif not state.agent:isMoving() and not state.agent:isPending() then
                    self:orderAttack(state.target, { node }, { queue = state.queue })
                else
                    state.x, state.y = x, y
                end
            elseif not state.agent:isMoving() and not state.agent:isPending() then
                self:finishOrder(node, state)
            end
        else
            if state.kind == 'attack' then
                local x, y, inRange = Units.attackPoint(node, state.target, state.range)
                node.data.orden =
                    { x = state.target.x, y = state.target.y, attack = true, target = state.target:path() }
                state.x, state.y = x, y
                if inRange then
                    self:finishOrder(node, state)
                    state = nil
                end
            end
            if state then
                local x, y, heading, arrived = Units.step(
                    node.x,
                    node.y,
                    state.heading,
                    state.x,
                    state.y,
                    dt,
                    self:speedOf(node),
                    math.rad(self:turnOf(node)),
                    self.arrive
                )
                state.heading = heading
                node.x, node.y = x, y
                node.angle = heading + math.rad(self:orientacionOf(node))
                -- La unidad la conduce la orden, no la física: un cuerpo dinámico no
                -- debe acumular velocidad de choques mientras tanto.
                local body = node.body
                if body and not body:isDestroyed() and body:getType() == 'dynamic' then
                    body:setLinearVelocity(0, 0)
                    body:setAngularVelocity(0)
                end
                if arrived then
                    self:finishOrder(node, state)
                end
            end
        end
    end
    for i = #self.markers, 1, -1 do
        local m = self.markers[i]
        m.age = m.age + dt
        if m.age >= self.markerTime then
            table.remove(self.markers, i)
        end
    end
end

-- Color del jugador de una unidad (`map.rts.players`), o el del aro por defecto.
function Units:playerColor(node)
    local rts = rtsOf(node)
    local map = self.level and self.level.data
    local players = map and map.rts and map.rts.players
    if rts and rts.playerId ~= nil and type(players) == 'table' then
        for _, p in ipairs(players) do
            if p.id == rts.playerId and type(p.color) == 'table' then
                return p.color
            end
        end
    end
    return self.colors.ring
end

-- Rectángulo de la caja de selección en pantalla, o nil si no es una caja todavía.
function Units:dragBox()
    local p = self.press
    if not p or not p.box then
        return nil
    end
    return math.min(p.x, p.cx), math.min(p.y, p.cy), math.abs(p.cx - p.x), math.abs(p.cy - p.y)
end

-- Dibujo -----------------------------------------------------------------------

--- Dentro de `camera:attach()`: aros, marcas de destino y la caja de selección.
function Units:draw()
    local g = love.graphics
    -- Aros, marcas y caja van sobre el suelo: con relieve suben con él.
    local Relief = require('runtime.terrain_relief')
    local lifted = Relief.beginLift(require('runtime.projection').current)
    local k = self:worldPerPixel()
    local r0, g0, b0, a0 = g.getColor()
    local lw = g.getLineWidth()
    for _, node in ipairs(self.selection) do
        if alive(node) then
            local w, h = Transform.size(node.data)
            local radius = math.max(w, h) * 0.5 + 4 * k
            local c = self:playerColor(node)
            g.setLineWidth(3 * k)
            g.setColor(0, 0, 0, 0.55)
            g.circle('line', node.x, node.y, radius + 1.5 * k)
            g.setLineWidth(2 * k)
            g.setColor(c[1], c[2], c[3], 1)
            g.circle('line', node.x, node.y, radius)
        end
    end
    local mc = self.colors.marker
    for _, m in ipairs(self.markers) do
        local t = m.age / self.markerTime
        local alpha = 1 - t
        local radius = (16 - 10 * t) * k
        g.setLineWidth(2 * k)
        g.setColor(mc[1], mc[2], mc[3], alpha)
        g.circle('line', m.x, m.y, radius)
        g.line(m.x - 4 * k, m.y, m.x + 4 * k, m.y)
        g.line(m.x, m.y - 4 * k, m.x, m.y + 4 * k)
    end
    local bx, by, bw, bh = self:dragBox()
    if bx then
        -- Las cuatro esquinas de la caja de pantalla llevadas al mundo: en
        -- vista desde arriba es el rectángulo de siempre y en isométrico sale
        -- recta en pantalla aunque se dibuje sobre el suelo.
        local points = {}
        for _, corner in ipairs({ { bx, by }, { bx + bw, by }, { bx + bw, by + bh }, { bx, by + bh } }) do
            local wx, wy = self:toWorld(corner[1], corner[2])
            points[#points + 1] = wx
            points[#points + 1] = wy
        end
        local bc = self.colors.box
        g.setColor(bc[1], bc[2], bc[3], 0.12)
        g.polygon('fill', points)
        g.setLineWidth(1.5 * k)
        g.setColor(bc[1], bc[2], bc[3], 0.9)
        g.polygon('line', points)
    end
    self:drawNavigationDebug(1 / k)
    if lifted then
        Relief.endLift()
    end
    g.setLineWidth(lw)
    g.setColor(r0, g0, b0, a0)
end

--- Depuración de NV (dentro de la cámara): las rutas de las unidades
-- seleccionadas y lo que pidan los flags de `opts.navigationDebug`.
function Units:drawNavigationDebug(zoom)
    local flags = self.navigationDebug
    local level = self.level
    if not flags or not level or not level.navigation then
        return
    end
    local NavigationDebug = require('runtime.nv.debug')
    if not NavigationDebug.anyActive(flags) then
        return
    end
    -- Listas reutilizadas entre cuadros (el dibujo va cada cuadro).
    local buffers = self.navigationDebugBuffers
    if not buffers then
        buffers = { agents = {}, selected = {}, extra = {} }
        self.navigationDebugBuffers = buffers
    end
    local agents, selected = buffers.agents, buffers.selected
    local na, ns = 0, 0
    for _, node in ipairs(self:units()) do
        local agent = level.agents and level.agents[node.data]
        if agent then
            na = na + 1
            agents[na] = agent
            if self.selectedSet[node] then
                ns = ns + 1
                selected[ns] = agent
            end
        end
    end
    for i = #agents, na + 1, -1 do
        agents[i] = nil
    end
    for i = #selected, ns + 1, -1 do
        selected[i] = nil
    end
    local extra = buffers.extra
    extra.agents = agents
    extra.selected = selected
    extra.zoom = zoom
    extra.groups = self.commands and self.commands:activeRequests() or nil
    NavigationDebug.draw(level.navigation, flags, extra)
end

--- Fuera de la cámara: cuántas unidades hay seleccionadas.
function Units:drawHud(x, y)
    local n = #self.selection
    if n == 0 then
        return
    end
    local g = love.graphics
    g.setColor(0, 0, 0, 0.55)
    local text = n == 1 and '1 unidad seleccionada' or (n .. ' unidades seleccionadas')
    local font = g.getFont()
    g.rectangle('fill', (x or 12) - 6, (y or 12) - 4, font:getWidth(text) + 12, font:getHeight() + 8, 4, 4)
    g.setColor(1, 1, 1)
    g.print(text, x or 12, y or 12)
end

-- Entrada ----------------------------------------------------------------------

function Units:isShift()
    if self.shiftDown then
        return true
    end
    local keyboard = love and love.keyboard
    return keyboard and keyboard.isDown and keyboard.isDown('lshift', 'rshift') or false
end

-- ¿La cámara arrastra con este botón? Entonces ese botón es suyo también.
function Units:cameraDrags(button)
    local cam = self.camera
    return cam and cam.drag and cam.drag.button == button or false
end

function Units:mousepressed(x, y, button, isTouch)
    if isTouch then
        return false
    end -- el táctil llega por touchpressed
    if button == 1 then
        self.press = { x = x, y = y, cx = x, cy = y, box = false }
        -- Si la cámara arrastra con el izquierdo, el arrastre es suyo: no hay caja.
        return not self:cameraDrags(1)
    elseif button == 2 then
        self.rightPress = { x = x, y = y, moved = 0 }
        return #self.selection > 0 and not self:cameraDrags(2)
    end
    return false
end

function Units:mousemoved(x, y, _dx, _dy, isTouch)
    if isTouch then
        return false
    end
    local consumed = false
    local p = self.press
    if p then
        p.cx, p.cy = x, y
        local dx, dy = x - p.x, y - p.y
        if not self:cameraDrags(1) and dx * dx + dy * dy > self.dragThreshold * self.dragThreshold then
            p.box = true
        end
        consumed = not self:cameraDrags(1)
    end
    local r = self.rightPress
    if r then
        local dx, dy = x - r.x, y - r.y
        r.moved = math.max(r.moved, math.sqrt(dx * dx + dy * dy))
    end
    return consumed
end

function Units:mousereleased(x, y, button, isTouch)
    if isTouch then
        return false
    end
    if button == 1 and self.press then
        local p = self.press
        self.press = nil
        p.cx, p.cy = x, y
        local shift = self:isShift()
        if self:cameraDrags(1) then
            -- Solo clic: un arrastre de cámara no selecciona.
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy <= self.orderDeadzone * self.orderDeadzone then
                local wx, wy = self:toWorld(x, y)
                local hit = self:unitAt(wx, wy)
                self:combine(hit and { hit } or {}, shift, true)
            end
            return false
        end
        if p.box then
            local camera = self.camera
            if camera and camera.projection and camera.projection.projection == 'iso' then
                -- En isométrico la caja es un rectángulo de la pantalla, no del suelo.
                self:combine(self:unitsInScreenRect(p.x, p.y, x, y), shift, false)
            else
                local x1, y1 = self:toWorld(p.x, p.y)
                local x2, y2 = self:toWorld(x, y)
                self:combine(self:unitsInRect(x1, y1, x2, y2), shift, false)
            end
        else
            local wx, wy = self:toWorld(x, y)
            local hit = self:unitAt(wx, wy)
            self:combine(hit and { hit } or {}, shift, true)
        end
        return true
    elseif button == 2 and self.rightPress then
        local r = self.rightPress
        self.rightPress = nil
        local dx, dy = x - r.x, y - r.y
        local moved = math.max(r.moved, math.sqrt(dx * dx + dy * dy))
        local ordered = false
        if moved <= self.orderDeadzone and #self.selection > 0 then
            local append = self:isShift()
            local radar = self.minimap
            local overMinimap = radar and radar.contains and radar:contains(x, y)
            if not overMinimap then
                local wx, wy = self:toWorld(x, y)
                local target = self:attackTargetAt(wx, wy, self.selectRadius * self:worldPerPixel())
                if target then
                    self:orderAttack(target, nil, { append = append })
                    ordered = true
                end
            end
            if not ordered then
                local wx, wy = self:orderPoint(x, y)
                self:order(wx, wy, nil, { append = append })
                ordered = true
            end
        end
        -- Si la cámara arrastra con el derecho tiene que recibir su suelta.
        return ordered and not self:cameraDrags(2)
    end
    return false
end

-- Táctil: un toque sobre una unidad la selecciona (tocar otra vez la única
-- seleccionada la suelta); un toque en vacío con selección es la orden de
-- mover. Un toque en vacío no se consume al pulsar: si el dedo arrastra, es la
-- cámara la que se mueve, y entonces ya no hay orden.
function Units:touchpressed(id, x, y)
    if self.tap and self.tap.id ~= id then
        self.tap.cancelled = true -- segundo dedo: es un pellizco, no un toque
        return false
    end
    self.tap = { id = id, x = x, y = y, moved = false, cancelled = false }
    local wx, wy = self:toWorld(x, y)
    local hit = self:unitAt(wx, wy, self.selectRadius * self:worldPerPixel())
    if hit then
        if #self.selection == 1 and self.selection[1] == hit then
            self:clear()
        else
            self:select({ hit })
        end
        self.tap.consumed = true
        return true
    end
    return false
end

function Units:touchmoved(id, x, y)
    local t = self.tap
    if not t or t.id ~= id then
        return false
    end
    local dx, dy = x - t.x, y - t.y
    if dx * dx + dy * dy > self.tapSlop * self.tapSlop then
        t.moved = true
    end
    return t.consumed == true
end

function Units:touchreleased(id, x, y)
    local t = self.tap
    if not t then
        return false
    end
    if t.id ~= id then
        return false
    end
    self.tap = nil
    if t.consumed then
        return true
    end
    if not t.moved and not t.cancelled and #self.selection > 0 then
        self:order(self:toWorld(x, y))
    end
    -- No se consume: la cámara tiene que soltar este dedo.
    return false
end

function Units:keypressed(key)
    if key == 'lshift' or key == 'rshift' then
        self.shiftDown = true
    end
    return false
end

function Units:keyreleased(key)
    if key == 'lshift' or key == 'rshift' then
        self.shiftDown = false
    end
    return false
end

--- La ventana pierde el foco: se suelta Shift y se cancela lo que estuviera a medias.
function Units:focus(focused)
    if focused == false then
        self.shiftDown = false
        self.press, self.rightPress, self.tap = nil, nil, nil
    end
    return self
end

return Units

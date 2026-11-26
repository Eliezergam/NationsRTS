-- Validación de puestos de destino (Destination Slots) de un grupo.
--
--   local SlotValidator = require('runtime.nv.slot_validator')
--   local v = SlotValidator.new(system, { bounds = { x=, y=, w=, h= }, blocked = fn, ringStep = 40 })
--   local ok, reason = v:validate(x, y, radius, agentProps)   -- sin tocar el estado
--   local slot, reason = v:place(x, y, radius, agentProps)     -- valida, y si no vale busca cerca
--   v:release(slot)                                            -- libera el hueco de un puesto aceptado
--
-- Un puesto generado por `DestinationSlots.generate` rodea geométricamente el
-- destino, pero eso no lo hace válido: puede caer fuera del mapa, dentro de
-- un edificio, lejos de la red o encima de otro puesto. Cada puesto pasa,
-- en este orden (el primero que falla da el motivo), por:
--
--   1. `posición inválida`  x o y no finitos;
--   2. `fuera de límites`   fuera de `bounds` (si el mapa los tiene);
--   3. `lejos de la red`    `system:projectPoint` no encuentra tramo a
--                           `maxProjectDistance` o menos (el mismo umbral que
--                           usa `requestPath`: así ningún puesto acaba en
--                           'destino lejos de la red');
--   4. `tramo no apto`      el tramo proyectado es intransitable para el agente
--                           (`segment:cost(agent) == ∞`: no cabe por ancho, o su
--                           clase tiene coste infinito);
--   5. `ocupado`            a menos de `radius + radio del otro` de un puesto ya
--                           aceptado por este validador;
--   6. `bloqueado`          `blocked(x, y, radius)` dice que hay geometría
--                           estática (el nivel lo construye con sus cuerpos de
--                           `love.physics`; sin colisiones no se comprueba).
--
-- No duplica índices: la distancia a la red la da el spatial hash de tramos
-- del propio sistema y las colisiones las consulta el nivel con su mundo.
--
-- Respaldo (`place`): si el puesto no vale se prueban anillos crecientes
-- alrededor (radio `k · ringStep`, `6k` candidatos por anillo, `k = 1..maxRings`)
-- hasta `maxAttempts` validaciones; el primero válido se acepta con
-- `fallback = true`. Si no hay ninguno, `place` devuelve `nil, 'sin puesto
-- válido'`: un estado explícito para que `group.lua` degrade la formación
-- de forma controlada en vez de mandar a nadie a un puesto imposible.

local NvUtil = require('runtime.nv.util')

local SlotValidator = NvUtil.class('SlotValidator')

SlotValidator.defaults = { maxAttempts = 24, maxRings = 3, ringStep = 40 }

local EMPTY = {}

--- `opts`: `bounds` ({x, y, w, h}), `blocked(x, y, r)`, `maxProjectDistance`
-- (por defecto la del sistema), `ringStep`, `maxRings`, `maxAttempts`.
function SlotValidator:init(system, opts)
    opts = opts or EMPTY
    local d = SlotValidator.defaults
    self.system = system
    self.bounds = type(opts.bounds) == 'table' and opts.bounds or nil
    self.blocked = type(opts.blocked) == 'function' and opts.blocked or nil
    local systemMax = system and system.options and system.options.maxProjectDistance or 400
    self.maxProjectDistance = NvUtil.atLeast(opts.maxProjectDistance, systemMax, 0)
    self.ringStep = NvUtil.atLeast(opts.ringStep, d.ringStep, 1e-3)
    self.maxRings = math.max(0, math.floor(NvUtil.finite(opts.maxRings, d.maxRings)))
    self.maxAttempts = math.max(1, math.floor(NvUtil.finite(opts.maxAttempts, d.maxAttempts)))
    self.taken = {} -- puestos aceptados: { x=, y=, radius= }
    self._proj = {}
    self.attempts, self.rejected, self.fallbacks, self.failed = 0, 0, 0, 0
end

--- Olvida los puestos aceptados (para reutilizar el validador en otra orden).
function SlotValidator:reset()
    for i = #self.taken, 1, -1 do
        self.taken[i] = nil
    end
    return self
end

--- Comprueba un punto sin cambiar nada. Devuelve true, o false y el motivo.
function SlotValidator:validate(x, y, radius, agent)
    self.attempts = self.attempts + 1
    radius = NvUtil.atLeast(radius, 0, 0)
    x, y = NvUtil.finite(x), NvUtil.finite(y)
    if not x or not y then
        return false, 'posición inválida'
    end
    local b = self.bounds
    if b and (x < b.x or y < b.y or x > b.x + b.w or y > b.y + b.h) then
        return false, 'fuera de límites'
    end
    local system = self.system
    if system then
        local proj = system:projectPoint(x, y, self.maxProjectDistance, self._proj)
        if not proj then
            return false, 'lejos de la red'
        end
        if agent and proj.segment:cost(agent) == math.huge then
            return false, 'tramo no apto'
        end
    end
    local taken = self.taken
    for i = 1, #taken do
        local t = taken[i]
        local dx, dy = t.x - x, t.y - y
        local range = radius + t.radius
        if dx * dx + dy * dy < range * range - 1e-6 then
            return false, 'ocupado'
        end
    end
    if self.blocked and self.blocked(x, y, radius) then
        return false, 'bloqueado'
    end
    return true
end

--- Reserva el hueco de un puesto válido. Devuelve la entrada de `taken`.
function SlotValidator:accept(x, y, radius)
    local entry = { x = x, y = y, radius = NvUtil.atLeast(radius, 0, 0) }
    self.taken[#self.taken + 1] = entry
    return entry
end

--- Libera un puesto aceptado (`slot` es lo que devolvió `place`, o su `taken`).
function SlotValidator:release(slot)
    local entry = slot and (slot.taken or slot) or nil
    local taken = self.taken
    for i = #taken, 1, -1 do
        if taken[i] == entry then
            table.remove(taken, i)
            return true
        end
    end
    return false
end

--- Valida (x, y) y, si no vale, busca el candidato válido más cercano en
-- anillos crecientes. Devuelve `{ x=, y=, fallback=, attempts=, taken= }` (y,
-- si hubo respaldo, el motivo por el que el puesto original no valía) o
-- nil, `'sin puesto válido'`, motivo del puesto original.
function SlotValidator:place(x, y, radius, agent)
    local ok, reason = self:validate(x, y, radius, agent)
    if ok then
        return { x = x, y = y, fallback = false, attempts = 1, taken = self:accept(x, y, radius) }
    end
    self.rejected = self.rejected + 1
    local attempts = 1
    local step = math.max(self.ringStep, radius * 2)
    for ring = 1, self.maxRings do
        local count = 6 * ring
        local r = ring * step
        for i = 0, count - 1 do
            if attempts >= self.maxAttempts then
                self.failed = self.failed + 1
                return nil, 'sin puesto válido', reason
            end
            -- Cada anillo empieza girado medio paso respecto al anterior para
            -- no alinear todos los candidatos en las mismas direcciones.
            local angle = (i + ring * 0.5) * (2 * math.pi / count)
            local cx, cy = x + math.cos(angle) * r, y + math.sin(angle) * r
            attempts = attempts + 1
            if self:validate(cx, cy, radius, agent) then
                self.fallbacks = self.fallbacks + 1
                return { x = cx, y = cy, fallback = true, attempts = attempts, taken = self:accept(cx, cy, radius) },
                    reason
            end
        end
    end
    self.failed = self.failed + 1
    return nil, 'sin puesto válido', reason
end

--- Contadores: validaciones, rechazos del puesto original, respaldos y fallos.
function SlotValidator:stats()
    return { attempts = self.attempts, rejected = self.rejected, fallbacks = self.fallbacks, failed = self.failed }
end

return SlotValidator

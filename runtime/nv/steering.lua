-- Cuentas de conducción (steering), puras y sin tablas: giro acotado,
-- velocidad por curvatura, aceleración/frenado y llegada.
--
--   local Steering = require('runtime.nv.steering')
--   heading, applied = Steering.limitTurn(heading, desired, turnRate * dt)
--   v = Steering.speedForCurvature(k, lateralAccel, maxSpeed)
--   v = Steering.arrive(dist, stoppingDistance, maxSpeed, braking)
--   speed = Steering.accelerate(speed, targetSpeed, acceleration, braking, dt)
--
-- Fórmulas:
--
--   * Giro acotado: `α = envolver(deseado − rumbo)` en (−π, π], y el rumbo cambia
--     `clamp(α, −paso, paso)`: nunca más de `turnRate·dt` por cuadro y siempre por
--     el lado corto (igual que `Units.turnToward`).
--   * Velocidad en curva: un móvil a velocidad `v` por una curva de curvatura `k`
--     sufre aceleración lateral `v²·k`. Con un tope `a_lat`, `v = sqrt(a_lat / k)`,
--     acotada por `maxSpeed`; con `k ≈ 0` (recta) es `maxSpeed`.
--   * Radio de giro: una unidad a `v` que gira a `ω` rad/s describe un círculo de
--     radio `v/ω`, así que con radio mínimo `r` el giro máximo es `ω = v / r`.
--   * Llegada: la velocidad máxima desde la que aún se puede frenar a `braking`
--     en el espacio que queda, `v = sqrt(2·braking·(dist − stoppingDistance))`;
--     dentro de `stoppingDistance` es 0. Sin `braking` se usa una rampa lineal
--     de `4·stoppingDistance`.
--   * Aceleración: la velocidad se acerca al objetivo a `acceleration` si sube y
--     a `braking` si baja, sin pasarse.

local V = require('runtime.nv.vector2')

local Steering = {}

--- Velocidad deseada (vector) hacia un punto, de módulo `maxSpeed`.
function Steering.seek(x, y, tx, ty, maxSpeed)
    local nx, ny = V.normalize(tx - x, ty - y)
    return nx * maxSpeed, ny * maxSpeed
end

--- Gira `heading` hacia `desired` sin pasar de `maxStep` radianes. Devuelve
-- el rumbo nuevo y el giro aplicado. `maxStep` negativo o infinito = instantáneo.
function Steering.limitTurn(heading, desired, maxStep)
    local diff = V.wrapAngle(desired - heading)
    if maxStep and maxStep >= 0 and maxStep ~= math.huge then
        if diff > maxStep then
            diff = maxStep
        elseif diff < -maxStep then
            diff = -maxStep
        end
    end
    return heading + diff, diff
end

--- Velocidad que aguanta una curvatura `k` (1/radio) con aceleración lateral
-- `lateralAccel`, acotada por `maxSpeed`.
function Steering.speedForCurvature(k, lateralAccel, maxSpeed)
    if not k or k <= V.EPSILON or not lateralAccel or lateralAccel <= 0 then
        return maxSpeed
    end
    local v = math.sqrt(lateralAccel / k)
    if v < maxSpeed then
        return v
    end
    return maxSpeed
end

--- Giro máximo (rad/s) de una unidad a velocidad `speed` con radio mínimo
-- `turningRadius`. `minSpeed` (opcional) evita que a velocidad 0 no pueda girar.
function Steering.maxTurnRate(speed, turningRadius, minSpeed)
    if not turningRadius or turningRadius <= V.EPSILON then
        return math.huge
    end
    local v = speed
    if minSpeed and v < minSpeed then
        v = minSpeed
    end
    return v / turningRadius
end

--- Radio de giro que describe una unidad a `speed` girando a `turnRate` rad/s.
function Steering.turningRadius(speed, turnRate)
    if not turnRate or math.abs(turnRate) <= V.EPSILON then
        return math.huge
    end
    return speed / math.abs(turnRate)
end

--- Velocidad objetivo al acercarse: 0 dentro de `stoppingDistance`; fuera, la
-- que aún permite frenar a tiempo con `braking` (o una rampa lineal sin él).
function Steering.arrive(dist, stoppingDistance, maxSpeed, braking)
    local room = dist - (stoppingDistance or 0)
    if room <= 0 then
        return 0
    end
    local v
    if braking and braking > 0 then
        v = math.sqrt(2 * braking * room)
    else
        local zone = math.max(1e-6, (stoppingDistance or 0) * 4)
        v = maxSpeed * room / zone
    end
    if v > maxSpeed then
        return maxSpeed
    end
    return v
end

--- Acerca `speed` a `target` con `acceleration` al subir y `braking` al bajar.
function Steering.accelerate(speed, target, acceleration, braking, dt)
    if target > speed then
        local next = speed + (acceleration or math.huge) * dt
        if next > target then
            return target
        end
        return next
    elseif target < speed then
        local next = speed - (braking or math.huge) * dt
        if next < target then
            return target
        end
        return next
    end
    return speed
end

return Steering

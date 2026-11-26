-- Vectores 2D como pares de números sueltos (sin tablas), para no reservar
-- memoria en `update`. Todas las funciones son puras.
--
--   local V = require('runtime.nv.vector2')
--   local nx, ny, len = V.normalize(dx, dy)      -- (0, 0, 0) si dx = dy = 0
--   local a = V.angle(dx, dy)                    -- atan2(dy, dx), Y hacia abajo
--
-- Convenio de coordenadas: píxeles de mundo, Y hacia abajo, ángulos en radianes
-- medidos con `atan2(dy, dx)` (0 = +X, π/2 = +Y, es decir "abajo" en pantalla).

local V = {}

local sqrt, atan2 = math.sqrt, math.atan2
local TWO_PI = math.pi * 2

--- Épsilon geométrico compartido por todo NV: por debajo de esta distancia dos
-- puntos se consideran el mismo.
V.EPSILON = 1e-6

--- Longitud de (x, y).
function V.length(x, y)
    return sqrt(x * x + y * y)
end

--- Longitud al cuadrado, para comparar sin raíz.
function V.lengthSq(x, y)
    return x * x + y * y
end

--- Vector unitario y longitud original. Con longitud menor que `V.EPSILON`
-- devuelve (0, 0, 0): nunca divide por cero.
function V.normalize(x, y)
    local len = sqrt(x * x + y * y)
    if len < V.EPSILON then
        return 0, 0, 0
    end
    return x / len, y / len, len
end

--- Producto escalar.
function V.dot(ax, ay, bx, by)
    return ax * bx + ay * by
end

--- Producto vectorial (componente z): positivo si b queda a la izquierda de a
-- en un sistema con Y hacia arriba; con Y hacia abajo, a la derecha visual.
function V.cross(ax, ay, bx, by)
    return ax * by - ay * bx
end

--- Distancia entre dos puntos.
function V.distance(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return sqrt(dx * dx + dy * dy)
end

--- Distancia al cuadrado entre dos puntos.
function V.distanceSq(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return dx * dx + dy * dy
end

--- Interpolación lineal de un escalar.
function V.lerp(a, b, t)
    return a + (b - a) * t
end

--- Interpolación lineal de un punto: devuelve x, y.
function V.lerp2(ax, ay, bx, by, t)
    return ax + (bx - ax) * t, ay + (by - ay) * t
end

--- Ángulo del vector, `atan2(y, x)`.
function V.angle(x, y)
    return atan2(y, x)
end

--- Ángulo llevado a (-π, π].
function V.wrapAngle(a)
    a = (a + math.pi) % TWO_PI - math.pi
    if a <= -math.pi then
        a = a + TWO_PI
    end
    return a
end

--- Gira (x, y) el ángulo `a`.
function V.rotate(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end

--- Perpendicular (giro de +90°: en pantalla, hacia la derecha del avance).
function V.perpendicular(x, y)
    return -y, x
end

--- Punto de un segmento a-b más cercano a p. Devuelve x, y, parámetro u en
-- [0, 1] y distancia. Con a = b devuelve a.
function V.closestOnSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lenSq = dx * dx + dy * dy
    local u = 0
    if lenSq > V.EPSILON * V.EPSILON then
        u = ((px - ax) * dx + (py - ay) * dy) / lenSq
        if u < 0 then
            u = 0
        elseif u > 1 then
            u = 1
        end
    end
    local x, y = ax + dx * u, ay + dy * u
    local ex, ey = px - x, py - y
    return x, y, u, sqrt(ex * ex + ey * ey)
end

--- Acota `v` a [lo, hi].
function V.clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

return V

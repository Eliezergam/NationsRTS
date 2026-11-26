-- Simplificación del trazo dibujado: muestreo por distancia y
-- Ramer-Douglas-Peucker. Funciones puras sobre listas de `{x=, y=}`.
--
--   local S = require('runtime.nv.simplify')
--   local muestras = S.sampleByDistance(trazoCrudo, 8)   -- una muestra cada 8 px como poco
--   local suaves = S.smooth(muestras, 2)                 -- quita el temblor del ratón (ventana ±2)
--   local puntos = S.rdp(suaves, 2)                      -- fuera lo que no aporta 2 px de forma
--
-- Las dos conservan siempre el primer y el último punto y nunca modifican la
-- lista de entrada: devuelven listas nuevas con tablas nuevas.

local V = require('runtime.nv.vector2')

local S = {}

local function copyPoint(p)
    return { x = p.x, y = p.y }
end

--- Añade una muestra solo cuando la distancia a la última muestra supera
-- `sampleDistance`. El primer punto siempre entra; el último entra si está
-- a más de `V.EPSILON` de la última muestra (así el trazo acaba donde acabó el
-- puntero, aunque la última muestra "regular" quede un poco antes).
function S.sampleByDistance(points, sampleDistance)
    local out = {}
    local n = points and #points or 0
    if n == 0 then
        return out
    end
    sampleDistance = math.max(0, tonumber(sampleDistance) or 0)
    local last = points[1]
    out[1] = copyPoint(last)
    for i = 2, n do
        local p = points[i]
        if V.distance(last.x, last.y, p.x, p.y) > sampleDistance then
            out[#out + 1] = copyPoint(p)
            last = p
        end
    end
    local tail = points[n]
    if n > 1 and V.distance(last.x, last.y, tail.x, tail.y) > V.EPSILON then
        out[#out + 1] = copyPoint(tail)
    end
    return out
end

-- Distancia de p a la recta que pasa por a y b. Si a y b coinciden (puntos
-- repetidos), es la distancia al punto: así RDP no divide entre cero.
local function distanceToLine(p, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local lenSq = dx * dx + dy * dy
    if lenSq <= V.EPSILON * V.EPSILON then
        return V.distance(p.x, p.y, a.x, a.y)
    end
    return math.abs(V.cross(dx, dy, p.x - a.x, p.y - a.y)) / math.sqrt(lenSq)
end

--- Ramer-Douglas-Peucker iterativo (con pila propia: sin límite de recursión).
-- Se conserva un punto cuando se aleja más de `tolerance` de la cuerda entre
-- los extremos del tramo que se está mirando. Devuelve una lista nueva.
function S.rdp(points, tolerance)
    local n = points and #points or 0
    local out = {}
    if n == 0 then
        return out
    end
    if n <= 2 then
        for i = 1, n do
            out[i] = copyPoint(points[i])
        end
        return out
    end
    tolerance = math.max(0, tonumber(tolerance) or 0)
    local keep = {}
    keep[1], keep[n] = true, true
    -- Pila de tramos [first, last] pendientes.
    local stack = { 1, n }
    while #stack > 0 do
        local last = table.remove(stack)
        local first = table.remove(stack)
        local a, b = points[first], points[last]
        local worst, worstD = nil, tolerance
        for i = first + 1, last - 1 do
            local d = distanceToLine(points[i], a, b)
            if d > worstD then
                worst, worstD = i, d
            end
        end
        if worst then
            keep[worst] = true
            stack[#stack + 1] = first
            stack[#stack + 1] = worst
            stack[#stack + 1] = worst
            stack[#stack + 1] = last
        end
    end
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = copyPoint(points[i])
        end
    end
    return out
end

--- Quita los puntos consecutivos repetidos (a menos de `V.EPSILON`). Útil antes
-- de construir la spline, que no admite dos puntos de control iguales seguidos.
--- Suaviza el temblor del ratón: media ponderada (1, 2, 3, 2, 1…) sobre una
-- ventana de `window` muestras a cada lado. El primer y el último punto no se
-- mueven, así el trazo sigue anclado a sus nodos. Sin esto, un arco dibujado
-- a mano deja picos de curvatura de radio 3 px en la spline y los agentes
-- frenan por ellos aunque el arco real tenga radio 300.
function S.smooth(points, window)
    window = math.max(0, math.floor(tonumber(window) or 0))
    local n = #points
    local out = {}

    if window == 0 or n < 3 then
        for i = 1, n do
            out[i] = copyPoint(points[i])
        end
        return out
    end

    out[1] = copyPoint(points[1])

    for i = 2, n - 1 do
        local sumX, sumY, sumW = 0, 0, 0

        for j = -window, window do
            local k = i + j

            if k >= 1 and k <= n then
                local w = window + 1 - math.abs(j)
                sumX = sumX + points[k].x * w
                sumY = sumY + points[k].y * w
                sumW = sumW + w
            end
        end

        out[i] = { x = sumX / sumW, y = sumY / sumW }
    end

    out[n] = copyPoint(points[n])
    return out
end

function S.dedupe(points)
    local out = {}
    for i = 1, points and #points or 0 do
        local p = points[i]
        local last = out[#out]
        if not last or V.distance(last.x, last.y, p.x, p.y) > V.EPSILON then
            out[#out + 1] = copyPoint(p)
        end
    end
    return out
end

--- Longitud de una polilínea.
function S.polylineLength(points)
    local total = 0
    for i = 2, points and #points or 0 do
        total = total + V.distance(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y)
    end
    return total
end

return S

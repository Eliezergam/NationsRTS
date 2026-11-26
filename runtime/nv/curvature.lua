-- Curvatura de una spline paramétrica.
--
--   local Curvature = require('runtime.nv.curvature')
--   local k = Curvature.at(spline, t)
--   local profile = Curvature.profile(spline, arc, 8, 24)   -- { {d=, k=}, ... , max=, average= }, k suavizada ±24 px
--
-- Para (x(t), y(t)):
--
--   k = |x'·y'' − y'·x''| / (x'² + y'²)^(3/2)
--
-- `k` es 1/radio: un círculo de radio r tiene k = 1/r en todos sus puntos y
-- una recta k = 0. Cuando la velocidad paramétrica es casi nula (denominador
-- por debajo de `Curvature.MIN_SPEED`) se devuelve 0 en vez de dividir por
-- algo diminuto. Como el cociente es invariante a la escala del parámetro,
-- vale con la `t` de la spline aunque ésta no sea de longitud de arco.

local Curvature = {}

Curvature.MIN_SPEED = 1e-6
Curvature.defaults = { step = 8, window = 24 }

function Curvature.at(spline, t)
    local dx, dy = spline:tangent(t)
    local ddx, ddy = spline:second(t)
    local speedSq = dx * dx + dy * dy
    if speedSq < Curvature.MIN_SPEED * Curvature.MIN_SPEED then
        return 0
    end
    return math.abs(dx * ddy - dy * ddx) / (speedSq * math.sqrt(speedSq))
end

--- Perfil a lo largo del arco: una entrada `{d=, k=}` cada `step` píxeles
-- (más la del final). También `max` y `average` (media de las muestras).
function Curvature.profile(spline, arc, step, window)
    step = math.max(1e-3, tonumber(step) or Curvature.defaults.step)
    local total = arc:length()
    local list = { max = 0, average = 0 }
    local sum, n = 0, 0
    local d = 0
    while true do
        local k = Curvature.at(spline, arc:tAtDistance(d))
        n = n + 1
        list[n] = { d = d, k = k }
        sum = sum + k
        if k > list.max then
            list.max = k
        end
        if d >= total then
            break
        end
        d = d + step
        if d > total then
            d = total
        end
    end
    list.average = n > 0 and sum / n or 0
    return Curvature.smoothProfile(list, window)
end

--- Media móvil de `k` sobre una ventana de ±`window` px (por defecto
-- `Curvature.defaults.window`). Un pico de una sola muestra (temblor del
-- ratón en un punto de control) no debe leerse como una curva cerrada: lo
-- que frena a un vehículo es la curvatura sostenida a lo largo de su propio
-- tamaño. Recalcula `max` y `average`. Con `window` 0 no cambia nada.
function Curvature.smoothProfile(profile, window)
    window = tonumber(window)

    if window == nil then
        window = Curvature.defaults.window
    end

    local n = #profile

    if window <= 0 or n < 3 then
        return profile
    end

    local smoothed = {}
    local sum, max = 0, 0
    local j0 = 1

    for i = 1, n do
        local d = profile[i].d
        local total, count = 0, 0

        while profile[j0].d < d - window do
            j0 = j0 + 1
        end

        local j = j0

        while j <= n and profile[j].d <= d + window do
            total = total + profile[j].k
            count = count + 1
            j = j + 1
        end

        smoothed[i] = count > 0 and total / count or profile[i].k
        sum = sum + smoothed[i]

        if smoothed[i] > max then
            max = smoothed[i]
        end
    end

    for i = 1, n do
        profile[i].k = smoothed[i]
    end

    profile.max = max
    profile.average = n > 0 and sum / n or 0
    return profile
end

--- Curvatura interpolada en un perfil a la distancia d.
function Curvature.lookup(profile, d)
    local n = #profile
    if n == 0 then
        return 0
    end
    if d <= profile[1].d then
        return profile[1].k
    end
    if d >= profile[n].d then
        return profile[n].k
    end
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if profile[mid].d <= d then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local a, b = profile[lo], profile[lo + 1]
    if not b or b.d - a.d < 1e-9 then
        return a.k
    end
    local u = (d - a.d) / (b.d - a.d)
    return a.k + (b.k - a.k) * u
end

--- Curvatura máxima del perfil en la ventana [d0, d1].
function Curvature.maxIn(profile, d0, d1)
    local n = #profile
    if n == 0 then
        return 0
    end
    if d1 < d0 then
        d0, d1 = d1, d0
    end
    local best = math.max(Curvature.lookup(profile, d0), Curvature.lookup(profile, d1))
    for i = 1, n do
        local p = profile[i]
        if p.d > d1 then
            break
        end
        if p.d >= d0 and p.k > best then
            best = p.k
        end
    end
    return best
end

return Curvature

-- Spline Catmull-Rom (centrípeta por defecto) que pasa por todos sus puntos de
-- control. Cada tramo entre dos puntos consecutivos se convierte al construirla
-- en un polinomio cúbico `a·u³ + b·u² + c·u + d` con `u` en [0, 1], así que
-- evaluar posición y derivadas no reserva memoria ni repite cuentas.
--
--   local CatmullRom = require('runtime.nv.catmull_rom')
--   local spline = CatmullRom.new({ {x=0,y=0}, {x=100,y=0}, {x=100,y=100} }, { alpha = .5 })
--   local x, y = spline:position(1.5)       -- t global en [0, spline:segmentCount()]
--   local dx, dy = spline:tangent(1.5)      -- derivada (no unitaria)
--   local ddx, ddy = spline:second(1.5)     -- segunda derivada
--
-- Fórmulas (tramo de puntos p0, p1, p2, p3; el tramo va de p1 a p2):
--
--   t0 = 0, t1 = t0 + |p1-p0|^α, t2 = t1 + |p2-p1|^α, t3 = t2 + |p3-p2|^α
--   m1 = (t2-t1) · ( (p1-p0)/(t1-t0) - (p2-p0)/(t2-t0) + (p2-p1)/(t2-t1) )
--   m2 = (t2-t1) · ( (p2-p1)/(t2-t1) - (p3-p1)/(t3-t1) + (p3-p2)/(t3-t2) )
--   a = 2·(p1-p2) + m1 + m2
--   b = -3·(p1-p2) - 2·m1 - m2
--   c = m1
--   d = p1
--
-- Con α = 0 es la Catmull-Rom uniforme (m1 = (p2-p0)/2), con α = 0,5 la
-- centrípeta (no hace lazos ni cúspides) y con α = 1 la cordal. Los extremos
-- de una spline abierta usan puntos fantasma reflejados (`2·p1 - p2`), que con
-- solo dos puntos dejan un tramo exactamente recto. Con un punto la spline es
-- constante y no tiene tramos.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')

local CatmullRom = NvUtil.class('CatmullRom')

CatmullRom.defaults = { alpha = 0.5, closed = false }

-- Coeficientes del tramo p1→p2 con vecinos p0 y p3.
local function coefficients(p0, p1, p2, p3, alpha, out)
    local function knot(a, b)
        local d = V.distance(a.x, a.y, b.x, b.y)
        if d < V.EPSILON then
            d = V.EPSILON
        end
        return d ^ alpha
    end
    local t0 = 0
    local t1 = t0 + knot(p0, p1)
    local t2 = t1 + knot(p1, p2)
    local t3 = t2 + knot(p2, p3)
    local dt = t2 - t1
    local m1x = dt * ((p1.x - p0.x) / (t1 - t0) - (p2.x - p0.x) / (t2 - t0) + (p2.x - p1.x) / dt)
    local m1y = dt * ((p1.y - p0.y) / (t1 - t0) - (p2.y - p0.y) / (t2 - t0) + (p2.y - p1.y) / dt)
    local m2x = dt * ((p2.x - p1.x) / dt - (p3.x - p1.x) / (t3 - t1) + (p3.x - p2.x) / (t3 - t2))
    local m2y = dt * ((p2.y - p1.y) / dt - (p3.y - p1.y) / (t3 - t1) + (p3.y - p2.y) / (t3 - t2))
    out.ax = 2 * (p1.x - p2.x) + m1x + m2x
    out.ay = 2 * (p1.y - p2.y) + m1y + m2y
    out.bx = -3 * (p1.x - p2.x) - 2 * m1x - m2x
    out.by = -3 * (p1.y - p2.y) - 2 * m1y - m2y
    out.cx, out.cy = m1x, m1y
    out.dx, out.dy = p1.x, p1.y
    return out
end

--- `points`: lista de `{x=, y=}` (se copia; los repetidos consecutivos se
-- descartan). `opts.closed` cierra la curva, `opts.alpha` es el exponente.
function CatmullRom:init(points, opts)
    opts = opts or {}
    self.alpha = tonumber(opts.alpha) or CatmullRom.defaults.alpha
    self.closed = opts.closed == true
    local pts = {}
    for i = 1, points and #points or 0 do
        local p = points[i]
        local last = pts[#pts]
        if not last or V.distance(last.x, last.y, p.x, p.y) > V.EPSILON then
            pts[#pts + 1] = { x = p.x, y = p.y }
        end
    end
    -- Cerrada: si el último repite al primero, sobra.
    if self.closed and #pts > 2 and V.distance(pts[1].x, pts[1].y, pts[#pts].x, pts[#pts].y) <= V.EPSILON then
        pts[#pts] = nil
    end
    self.points = pts
    self.segments = {}
    local n = #pts
    if n < 2 then
        self.closed = false
        return
    end
    if self.closed and n < 3 then
        self.closed = false
    end
    local count = self.closed and n or n - 1
    for i = 1, count do
        local p1, p2 = pts[i], pts[i % n + 1]
        local p0, p3
        if self.closed then
            p0 = pts[(i - 2) % n + 1]
            p3 = pts[(i + 1) % n + 1]
        else
            p0 = pts[i - 1] or { x = 2 * p1.x - p2.x, y = 2 * p1.y - p2.y }
            p3 = pts[i + 2] or { x = 2 * p2.x - p1.x, y = 2 * p2.y - p1.y }
        end
        self.segments[i] = coefficients(p0, p1, p2, p3, self.alpha, {})
    end
end

--- Número de tramos: puntos − 1 (abierta), puntos (cerrada), 0 con un punto.
function CatmullRom:segmentCount()
    return #self.segments
end

-- Tramo y parámetro local para un t global (acotado a [0, segmentCount]).
function CatmullRom:locate(t)
    local count = #self.segments
    if count == 0 then
        return nil, 0
    end
    if t ~= t then
        t = 0
    end
    if t <= 0 then
        return self.segments[1], 0
    end
    if t >= count then
        return self.segments[count], 1
    end
    local index = math.floor(t)
    return self.segments[index + 1], t - index
end

--- Posición en t.
function CatmullRom:position(t)
    local s, u = self:locate(t)
    if not s then
        local p = self.points[1]
        if p then
            return p.x, p.y
        end
        return 0, 0
    end
    return ((s.ax * u + s.bx) * u + s.cx) * u + s.dx, ((s.ay * u + s.by) * u + s.cy) * u + s.dy
end

--- Primera derivada respecto a t (dirección de avance, no unitaria).
function CatmullRom:tangent(t)
    local s, u = self:locate(t)
    if not s then
        return 0, 0
    end
    return (3 * s.ax * u + 2 * s.bx) * u + s.cx, (3 * s.ay * u + 2 * s.by) * u + s.cy
end

--- Segunda derivada respecto a t.
function CatmullRom:second(t)
    local s, u = self:locate(t)
    if not s then
        return 0, 0
    end
    return 6 * s.ax * u + 2 * s.bx, 6 * s.ay * u + 2 * s.by
end

--- Tangente unitaria en t (0, 0 si la derivada es nula).
function CatmullRom:direction(t)
    local dx, dy = self:tangent(t)
    local nx, ny = V.normalize(dx, dy)
    return nx, ny
end

return CatmullRom

-- Parametrización por longitud de arco de una spline: tabla acumulada
-- distancia → parámetro `t`, para que un agente pueda pedir "la posición a
-- 340 px del principio" y avanzar a velocidad espacial uniforme.
--
--   local ArcLength = require('runtime.nv.arc_length')
--   local arc = ArcLength.new(spline, 16)          -- 16 muestras por tramo
--   arc:length()                                   -- longitud total
--   local x, y = arc:positionAtDistance(340)
--   local tx, ty = arc:tangentAtDistance(340)      -- unitaria
--
-- La tabla se construye una vez (al editar o cargar el segmento): se recorren
-- los tramos con `samplesPerSegment` puntos cada uno y se suman las cuerdas
-- entre muestras consecutivas. `tAtDistance` busca por bisección la muestra y
-- interpola linealmente `t` dentro de ella; con 16 muestras por tramo el error
-- de longitud de una curva suave queda muy por debajo del 1 %.
--
-- Las muestras (`xs`, `ys`, `ts`, `ds`) quedan expuestas: `NavigationSegment`
-- las usa para el punto más cercano, la caja envolvente y el dibujo.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')

local ArcLength = NvUtil.class('ArcLength')

ArcLength.defaults = { samplesPerSegment = 16 }

function ArcLength:init(spline, samplesPerSegment)
    self.spline = spline
    self.samplesPerSegment =
        math.max(1, math.floor(tonumber(samplesPerSegment) or ArcLength.defaults.samplesPerSegment))
    self:rebuild()
end

function ArcLength:rebuild()
    local spline = self.spline
    local count = spline:segmentCount()
    local per = self.samplesPerSegment
    local xs, ys, ts, ds = {}, {}, {}, {}
    local x0, y0 = spline:position(0)
    xs[1], ys[1], ts[1], ds[1] = x0, y0, 0, 0
    local n = 1
    local total = 0
    local px, py = x0, y0
    for seg = 0, count - 1 do
        for k = 1, per do
            local t = seg + k / per
            local x, y = spline:position(t)
            total = total + V.distance(px, py, x, y)
            n = n + 1
            xs[n], ys[n], ts[n], ds[n] = x, y, t, total
            px, py = x, y
        end
    end
    self.xs, self.ys, self.ts, self.ds = xs, ys, ts, ds
    self.count = n
    self.total = total
    return self
end

function ArcLength:length()
    return self.total
end

function ArcLength:sampleCount()
    return self.count
end

--- Muestra i: x, y, t, d.
function ArcLength:sample(i)
    return self.xs[i], self.ys[i], self.ts[i], self.ds[i]
end

-- Índice de la última muestra con d ≤ distancia (bisección).
function ArcLength:indexAt(d)
    local ds = self.ds
    local lo, hi = 1, self.count
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if ds[mid] <= d then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo
end

--- Parámetro t de la spline a la distancia d (acotada a [0, longitud]).
function ArcLength:tAtDistance(d)
    if d ~= d then
        d = 0
    end
    if d <= 0 then
        return 0
    end
    if d >= self.total then
        return self.ts[self.count]
    end
    local i = self:indexAt(d)
    local d0, d1 = self.ds[i], self.ds[i + 1]
    if not d1 or d1 - d0 < V.EPSILON then
        return self.ts[i]
    end
    local u = (d - d0) / (d1 - d0)
    return self.ts[i] + (self.ts[i + 1] - self.ts[i]) * u
end

function ArcLength:positionAtDistance(d)
    return self.spline:position(self:tAtDistance(d))
end

--- Tangente unitaria a la distancia d. Si la derivada es nula (spline de un
-- punto) devuelve (0, 0).
function ArcLength:tangentAtDistance(d)
    local dx, dy = self.spline:tangent(self:tAtDistance(d))
    local nx, ny = V.normalize(dx, dy)
    return nx, ny
end

return ArcLength

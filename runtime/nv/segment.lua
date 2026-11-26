-- Segmento del grafo de navegación: la curva que une dos nodos.
--
--   local NavigationSegment = require('runtime.nv.segment')
--   local s = NavigationSegment.new(id, fromId, toId, points, props)
--   s:rebuild()                       -- spline, arco, longitud, caja, curvatura, coste
--   local x, y = s:positionAt(120)    -- a 120 px del nodo `from`
--   local px, py, dist, d = s:nearestPoint(x, y)
--   local c = s:cost(agentProps)
--
-- Datos editables (los que se guardan): `id`, `from`, `to`, `points` (lista
-- optimizada de `{x=, y=}` que INCLUYE los dos extremos), `rawPoints`
-- (opcional, el trazo original), `width` (ancho navegable en px), `oneWay`
-- (`false` o `'forward'`: solo de `from` a `to`), `speedLimit` (px/s, 0 = sin
-- límite), `costFactor` y `metadata`.
--
-- Datos derivados (los calcula `rebuild`, nunca se guardan): `spline`, `arc`,
-- `length`, `bounds {x, y, w, h}` (ensanchada `width/2`), `profile` de
-- curvatura, `averageCurvature`, `maxCurvature`, `recommendedSpeed` y
-- `baseCost`.
--
-- Velocidad recomendada: la que aguanta la curva más cerrada con la aceleración
-- lateral de referencia, `v = sqrt(lateralAccel / maxCurvature)`, acotada por
-- `speedLimit` y por `referenceSpeed` (para rectas, donde k ≈ 0).
--
-- Coste (modelo de la especificación, cada sumando es una función de
-- `NavigationSegment.costTerms` que se puede sustituir o ampliar sin tocar A*):
--
--   cost = costFactor · (distance + curvaturePenalty + terrainPenalty + widthPenalty + vehiclePenalty)
--
--   distance         = length
--   curvaturePenalty = length · averageCurvature · curvatureWeight (50 por defecto)
--                      + length · (maxCurvature · turningRadius − 1) si la curva más
--                        cerrada es más cerrada de lo que el agente puede girar
--   terrainPenalty   = length · metadata.terrainCost (0 por defecto)
--   widthPenalty     = ∞ si agent.width > width (no cabe); si no 0
--   vehiclePenalty   = metadata.vehiclePenalty + metadata.classCost[agent.class]
--                      + length · (agent.maxSpeed / speedLimit − 1) si hay límite y el
--                        agente es más rápido (le cuesta tiempo)
--
-- Un coste `math.huge` significa intransitable para ese agente.
--
-- Invariante para A* (ver `runtime/nv/astar.lua`): todas las penalizaciones son
-- ≥ 0 (`terrainCost`, `vehiclePenalty`, `classCost` y `curvatureWeight`
-- negativos se leen como 0), así que `cost ≥ costFactor · length`. Un tramo
-- "más barato que su longitud" se expresa con `costFactor < 1`, que el grafo
-- tiene en cuenta escalando la heurística; nunca con penalizaciones negativas.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')
local CatmullRom = require('runtime.nv.catmull_rom')
local ArcLength = require('runtime.nv.arc_length')
local Curvature = require('runtime.nv.curvature')

local NavigationSegment = NvUtil.class('NavigationSegment')

NavigationSegment.defaults = {
    width = 64, -- px navegables
    oneWay = false,
    speedLimit = 0, -- px/s; 0 = sin límite
    costFactor = 1,
    samplesPerSegment = 16, -- muestras de la tabla de arco por tramo de spline
    curvatureStep = 8, -- px entre muestras del perfil de curvatura
    curvatureWindow = 24, -- px a cada lado sobre los que se promedia la curvatura
    lateralAccel = 300, -- px/s² de referencia para la velocidad recomendada
    referenceSpeed = 240, -- px/s: tope de la velocidad recomendada en rectas
    curvatureWeight = 50,
}

local EMPTY = {}

--- Sumandos del coste. Cada función recibe (segment, agent) y devuelve un
-- número (o `math.huge`). Se pueden añadir claves nuevas desde el juego.
NavigationSegment.costTerms = {
    distance = function(seg)
        return seg.length
    end,
    curvature = function(seg, agent)
        local weight = NvUtil.atLeast(agent.curvatureWeight, NavigationSegment.defaults.curvatureWeight, 0)
        local penalty = seg.length * seg.averageCurvature * weight
        local radius = NvUtil.finite(agent.turningRadius, 0)
        if radius > 0 and seg.maxCurvature * radius > 1 then
            penalty = penalty + seg.length * (seg.maxCurvature * radius - 1)
        end
        return penalty
    end,
    terrain = function(seg)
        return seg.length * NvUtil.atLeast(seg.metadata.terrainCost, 0, 0)
    end,
    width = function(seg, agent)
        local needed = NvUtil.finite(agent.width, 0)
        if needed > 0 and needed > seg.width then
            return math.huge
        end
        return 0
    end,
    vehicle = function(seg, agent)
        local penalty = NvUtil.atLeast(seg.metadata.vehiclePenalty, 0, 0)
        local classCost = seg.metadata.classCost
        if type(classCost) == 'table' and agent.class ~= nil then
            penalty = penalty + NvUtil.atLeast(classCost[agent.class], 0, 0)
        end
        local maxSpeed = NvUtil.finite(agent.maxSpeed, 0)
        if seg.speedLimit > 0 and maxSpeed > seg.speedLimit then
            penalty = penalty + seg.length * (maxSpeed / seg.speedLimit - 1)
        end
        return penalty
    end,
}

--- `points` incluye los extremos (el grafo los ajusta a los nodos). `props`:
-- `width`, `oneWay`, `speedLimit`, `costFactor`, `metadata`, `rawPoints`.
function NavigationSegment:init(id, from, to, points, props)
    props = props or EMPTY
    local d = NavigationSegment.defaults
    self.id = id
    self.from = from
    self.to = to
    self.points = NvUtil.copyPoints(points)
    self.rawPoints = props.rawPoints ~= nil and NvUtil.copyPoints(props.rawPoints) or nil
    self.width = NvUtil.atLeast(props.width, d.width, 0)
    self.oneWay = props.oneWay == 'forward' and 'forward' or false
    self.speedLimit = NvUtil.atLeast(props.speedLimit, d.speedLimit, 0)
    self.costFactor = NvUtil.atLeast(props.costFactor, d.costFactor, 0)
    self.metadata = type(props.metadata) == 'table' and props.metadata or {}
    self.rebuilds = 0
    self.dirty = true
    self.length = 0
    self.bounds = { x = 0, y = 0, w = 0, h = 0 }
    self.averageCurvature, self.maxCurvature = 0, 0
    self.recommendedSpeed, self.baseCost = 0, 0
end

--- Recalcula todo lo derivado. `opts`: `samplesPerSegment`, `curvatureStep`, `curvatureWindow`,
-- `lateralAccel`, `referenceSpeed`.
function NavigationSegment:rebuild(opts)
    opts = opts or EMPTY
    local d = NavigationSegment.defaults
    self.spline = CatmullRom.new(self.points)
    self.arc = ArcLength.new(self.spline, NvUtil.finite(opts.samplesPerSegment, d.samplesPerSegment))
    self.length = self.arc:length()
    -- Caja: las muestras del arco más medio ancho.
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local xs, ys = self.arc.xs, self.arc.ys
    for i = 1, self.arc.count do
        local x, y = xs[i], ys[i]
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if y < minY then
            minY = y
        end
        if y > maxY then
            maxY = y
        end
    end
    if minX == math.huge then
        minX, minY, maxX, maxY = 0, 0, 0, 0
    end
    local half = self.width * 0.5
    self.bounds.x, self.bounds.y = minX - half, minY - half
    self.bounds.w, self.bounds.h = maxX - minX + self.width, maxY - minY + self.width
    -- Curvatura.
    self.profile = Curvature.profile(
        self.spline,
        self.arc,
        NvUtil.finite(opts.curvatureStep, d.curvatureStep),
        NvUtil.finite(opts.curvatureWindow, d.curvatureWindow)
    )
    self.averageCurvature = self.profile.average
    self.maxCurvature = self.profile.max
    -- Velocidad recomendada.
    local lateral = NvUtil.atLeast(opts.lateralAccel, d.lateralAccel, 0)
    local reference = NvUtil.atLeast(opts.referenceSpeed, d.referenceSpeed, 0)
    local v = reference
    if self.maxCurvature > V.EPSILON then
        v = math.min(v, math.sqrt(lateral / self.maxCurvature))
    end
    if self.speedLimit > 0 then
        v = math.min(v, self.speedLimit)
    end
    self.recommendedSpeed = v
    self.baseCost = self:cost(EMPTY)
    self.rebuilds = self.rebuilds + 1
    self.dirty = false
    return self
end

--- ¿Se puede recorrer de `to` a `from`?
function NavigationSegment:allowsReverse()
    return self.oneWay ~= 'forward'
end

--- Nodo del otro extremo (o nil si `nodeId` no es un extremo).
function NavigationSegment:otherEnd(nodeId)
    if nodeId == self.from then
        return self.to
    end
    if nodeId == self.to then
        return self.from
    end
    return nil
end

--- Posición a `d` píxeles del nodo `from` (o del `to`, si `reversed`).
function NavigationSegment:positionAt(d, reversed)
    if reversed then
        d = self.length - d
    end
    return self.arc:positionAtDistance(d)
end

--- Tangente unitaria en el sentido de recorrido.
function NavigationSegment:tangentAt(d, reversed)
    if reversed then
        local tx, ty = self.arc:tangentAtDistance(self.length - d)
        return -tx, -ty
    end
    return self.arc:tangentAtDistance(d)
end

--- Curvatura (1/radio) a `d` píxeles de `from`, del perfil precalculado.
function NavigationSegment:curvatureAt(d)
    return Curvature.lookup(self.profile, d)
end

--- Curvatura máxima entre `d0` y `d1` (medidos desde `from`).
function NavigationSegment:maxCurvatureBetween(d0, d1)
    return Curvature.maxIn(self.profile, d0, d1)
end

--- Punto del segmento más cercano a (x, y): busca la muestra del arco más
-- próxima y afina proyectando sobre las dos cuerdas vecinas. Devuelve
-- px, py, distancia, distancia a lo largo del segmento desde `from`.
function NavigationSegment:nearestPoint(x, y)
    local arc = self.arc
    local xs, ys, ds = arc.xs, arc.ys, arc.ds
    local n = arc.count
    local best, bestSq = 1, math.huge
    for i = 1, n do
        local sq = V.distanceSq(x, y, xs[i], ys[i])
        if sq < bestSq then
            best, bestSq = i, sq
        end
    end
    local px, py, dist, along = xs[best], ys[best], math.sqrt(bestSq), ds[best]
    for i = math.max(1, best - 1), math.min(n - 1, best) do
        local cx, cy, u, cd = V.closestOnSegment(x, y, xs[i], ys[i], xs[i + 1], ys[i + 1])
        if cd < dist then
            px, py, dist = cx, cy, cd
            along = ds[i] + (ds[i + 1] - ds[i]) * u
        end
    end
    return px, py, dist, along
end

--- Coste del segmento para un agente (`agent` puede ser `{}`).
function NavigationSegment:cost(agent)
    agent = agent or EMPTY
    local total = 0
    for _, term in pairs(NavigationSegment.costTerms) do
        local value = term(self, agent)
        if value == math.huge then
            return math.huge
        end
        total = total + value
    end
    return total * self.costFactor
end

--- Coste de recorrer solo una parte (`len` píxeles) del segmento.
function NavigationSegment:partialCost(agent, len)
    local full = self:cost(agent)
    if full == math.huge or self.length <= V.EPSILON then
        return full
    end
    return full * math.max(0, math.min(len, self.length)) / self.length
end

--- Extremos: x, y del nodo `from` y del `to`, según los puntos.
function NavigationSegment:endpoints()
    local a, b = self.points[1], self.points[#self.points]
    if not a then
        return 0, 0, 0, 0
    end
    return a.x, a.y, b.x, b.y
end

return NavigationSegment

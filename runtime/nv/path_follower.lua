-- Seguimiento de una ruta por distancia acumulada, con objetivo adelantado
-- (look-ahead) y ventana de curvatura por delante.
--
--   local PathFollower = require('runtime.nv.path_follower')
--   local f = PathFollower.new(route, props)
--   f:advanceTo(x, y)                    -- reproyecta la posición real cerca de la distancia actual
--   local tx, ty = f:lookAhead(48)       -- punto a 48 px por delante sobre la ruta
--   local k = f:curvatureAhead(96)       -- curvatura máxima en los próximos 96 px
--   f:remaining()                        -- lo que falta
--
-- El agente no persigue "el siguiente punto": lleva `distanceAlongPath` y en
-- cada cuadro la ajusta proyectando su posición real sobre la ruta en una
-- ventana alrededor de la distancia anterior (`backWindow` hacia atrás,
-- `aheadWindow` hacia delante). La distancia solo avanza (monótona): si la
-- esquiva lo empuja hacia atrás, el objetivo adelantado sigue por delante y la
-- unidad vuelve a la ruta en vez de perderse. `deviation` es la separación
-- respecto a la ruta; el agente la usa para el `autoRepath` por desvío.
-- La única excepción es `rewindTo`: cuando el agente ha retrocedido a
-- propósito (cediendo el paso, ver `agent.lua`) la distancia vuelve a donde
-- está de verdad, para no disparar un repath por desvío.

local NvUtil = require('runtime.nv.util')

local PathFollower = NvUtil.class('PathFollower')

PathFollower.defaults = { backWindow = 24, aheadWindow = 96, projectStep = 4 }

function PathFollower:init(route, props)
    props = props or {}
    local d = PathFollower.defaults
    self.route = route
    self.distance = 0
    self.deviation = 0
    self.backWindow = NvUtil.atLeast(props.backWindow, d.backWindow, 0)
    self.aheadWindow =
        NvUtil.atLeast(props.aheadWindow, math.max(d.aheadWindow, 2 * NvUtil.finite(props.lookAheadDistance, 0)), 1)
    self.projectStep = NvUtil.atLeast(props.projectStep, d.projectStep, 0.5)
end

--- Alias con el nombre de la especificación.
function PathFollower:distanceAlongPath()
    return self.distance
end

--- Reproyecta la posición real sobre la ruta cerca de la distancia actual.
-- Devuelve la distancia nueva y la separación.
function PathFollower:advanceTo(x, y)
    local d, dev = self.route:project(x, y, self.distance, self.backWindow, self.aheadWindow, self.projectStep)
    if d > self.distance then
        self.distance = d
    end
    self.deviation = dev
    return self.distance, dev
end

--- Reproyecta permitiendo volver atrás hasta `back` px (por defecto
-- `4·aheadWindow`): para cuando el agente retrocedió a propósito. Devuelve
-- la distancia nueva y la separación.
function PathFollower:rewindTo(x, y, back)
    back = NvUtil.atLeast(back, self.aheadWindow * 4, 0)
    local d, dev = self.route:project(x, y, self.distance, back, self.backWindow, self.projectStep)
    self.distance = d
    self.deviation = dev
    return d, dev
end

--- Punto de la ruta a `distance` px por delante (acotado al final).
function PathFollower:lookAhead(distance)
    local d = self.distance + (distance or 0)
    local total = self.route:length()
    if d > total then
        d = total
    end
    return self.route:positionAt(d)
end

--- Curvatura máxima en la ventana [distancia actual, + `distance`].
function PathFollower:curvatureAhead(distance)
    return self.route:maxCurvatureAhead(self.distance, distance or 0)
end

function PathFollower:remaining()
    return math.max(0, self.route:length() - self.distance)
end

function PathFollower:finished()
    return self.distance >= self.route:length()
end

--- Tangente de la ruta en la distancia actual.
function PathFollower:tangent()
    return self.route:tangentAt(self.distance)
end

return PathFollower

-- Esquiva local entre agentes. Dos versiones, elegibles por agente con
-- `props.avoidance = 'v2' | 'v1'` (por defecto 'v2', ver `docs/NV.md` →
-- "Congestión"). Ninguna lanza búsquedas de camino.
--
--   local LocalAvoidance = require('runtime.nv.local_avoidance')
--   local la = LocalAvoidance.new({ margin = 8, horizon = .6, timeHorizon = 0.5 })
--   local ax, ay = la:compute(agent, neighbours, dt)                -- v1: vector (módulo ≤ 1)
--   local vx, vy = la:safeVelocity(agent, neighbours, pvx, pvy, dt, maxSpeed, nx, ny, c)  -- v2: velocidad segura
--   local s = la:speedAlong(hx, hy, lo, hi, desired)                -- v2: rapidez segura a lo largo de un rumbo
--
-- `neighbours` es una lista de agentes (`NavigationAgent`) o de tablas planas
-- `{ x=, y=, radius=, vx=, vy= }` (una tabla plana es un obstáculo que no
-- esquiva: una columna, un muro hecho de círculos).
--
-- v1 (la de siempre, respaldo estable). Para cada vecino a menos de
-- `r + r_vecino + margin`:
--
--   * separación: empuje en la dirección opuesta, de peso `1 − dist/rango`;
--   * predicción: si dentro de `horizon` s la posición relativa
--     `p + (v_vecino − v)·horizon` queda dentro del rango y el vecino está por
--     delante, se añade un empuje perpendicular al rumbo, hacia el lado
--     contrario del vecino, de peso `1 − dist_futura/rango`.
--
-- El agente suma ese vector (por `avoidanceWeight`) a su dirección deseada.
--
-- v2 (velocidades seguras, idea de Velocity Obstacles / ORCA, sin
-- dependencias). En vez de sumar empujes sin límite, cada vecino recorta el
-- plano de velocidades con un SEMIPLANO: el obstáculo de velocidad de ese
-- vecino (el cono de velocidades relativas que chocarían antes de
-- `timeHorizon` s, truncado por un círculo) se aparta por el punto más
-- cercano de su borde, `u`, y el agente asume la parte `α·u` del desvío:
--
--   α = 0,5 entre dos agentes que esquivan (recíproco);
--   α = 1   ante un obstáculo que no esquiva (tabla plana, agente parado,
--           llegado o esperando ruta); un agente llegado al que un vecino en
--           marcha se le acerca a menos de `r + r_vecino + 2·margin` recibe
--           `nudged = true` y en su siguiente `update` hace sitio
--           (`makingWay`): desde entonces cuenta como uno que esquiva;
--   α = 0,8 / 0,2 si uno está cediendo el paso (`yieldState = 'yielding'`) y
--           el otro no: el que cede asume casi todo el desvío;
--   α = 0,75 / 0,25 en la misma corriente (direcciones preferidas parecidas):
--           el de detrás frena por el de delante, no al revés; y 0,1 / 0,9
--           si ya se solapan: abre hueco el de delante (si retrocediera el
--           de detrás retrocedería toda la columna).
--
-- Un obstáculo fijo (tabla plana) justo en la línea de avance tuerce antes
-- la velocidad preferida hacia un lado (`steerAroundFixed`): con el cono
-- truncado de ORCA, un poste justo delante solo frenaría al agente hasta
-- pararlo. Las rectas de obstáculos fijos van primero y son duras:
-- `linearProgram3` no cede en ellas (como en RVO2).
--
-- Semiplano i: velocidades `v` con `det(dᵢ, pᵢ − v) ≤ 0` (a la izquierda de la
-- recta que pasa por `pᵢ` con dirección `dᵢ`). La velocidad segura es la más
-- cercana a la preferida (`pvx, pvy`: la de la ruta + formación, ya acotada)
-- dentro de todos los semiplanos y del disco `|v| ≤ maxSpeed`: un programa
-- lineal 2D incremental (`linearProgram2`, que en cada semiplano violado
-- resuelve el problema 1D sobre su recta, `linearProgram1`). Si no hay
-- solución (demasiados vecinos encima) `linearProgram3` minimiza la mayor
-- penetración en los semiplanos: la respuesta menos mala, nunca NaN.
--
-- Prioridades (spec §9): 1) no chocar, 2) seguir en la red, 3) avanzar,
-- 4) formación. `opts.corridor` (normal hacia fuera `nx, ny` y holgura `c`)
-- añade el semiplano del borde del tramo, `v·n ≤ c`: primero se resuelve con
-- él; si con él no hay solución se resuelve solo con los vecinos (la colisión
-- manda sobre la red). Avanzar es el objetivo del programa (la velocidad más
-- cercana a la preferida) y la formación ya va dentro de la preferida con
-- poco peso.
--
-- Solo cuentan los `maxNeighbours` vecinos más cercanos por distancia de
-- superficie (`dist − r − r_vecino`), o `neighbourLimit` si es menor (el
-- agente lo pone en su LOD 'coarse', ver `agent.lua`). Las rectas viven en arrays planos
-- compartidos por el módulo (el cálculo es secuencial): ni una tabla por
-- agente ni por cuadro.
--
-- El agente no es holónomo (rumbo + rapidez con giro acotado), así que no
-- puede tomar cualquier velocidad al instante: gira hacia la velocidad segura
-- y después pide `speedAlong(rumbo, ...)`, la rapidez (negativa = marcha
-- atrás) más cercana a la deseada que cumple TODOS los semiplanos del último
-- cálculo sobre la recta de su rumbo real. Así lo que se mueve de verdad
-- también es seguro.
--
-- Bloqueo (las dos versiones): hay un vecino por delante (a menos de 45° del
-- rumbo) dentro del rango, ese vecino está casi parado y el agente también;
-- entonces `blockedFor` acumula `dt`; en cuanto no, vuelve a 0. El agente con
-- `props.congestion = false` repite la búsqueda con él (el comportamiento de
-- antes de la fase E); por defecto manda la detección de atascos del agente
-- (`agent.congestion`, ver `agent.lua`).

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')

local LocalAvoidance = NvUtil.class('LocalAvoidance')

local EPSILON = V.EPSILON

LocalAvoidance.defaults = {
    margin = 8,
    horizon = 0.6,
    aheadCos = math.cos(math.rad(45)),
    stillSpeed = 0.15,
    timeHorizon = 0.5, -- v2: segundos de anticipación del obstáculo de velocidad
    maxNeighbours = 16, -- v2: vecinos más cercanos que recortan velocidades
    contactTolerance = 0.15, -- v2: parte de la suma de radios que se tolera de roce
    separationTime = 0.3, -- v2: s para deshacer un solape (ya se tocan)
}

function LocalAvoidance:init(opts)
    opts = opts or {}
    local d = LocalAvoidance.defaults
    self.margin = NvUtil.atLeast(opts.margin, d.margin, 0)
    self.horizon = NvUtil.atLeast(opts.horizon, d.horizon, 0)
    self.aheadCos = NvUtil.finite(opts.aheadCos, d.aheadCos)
    self.stillSpeed = NvUtil.atLeast(opts.stillSpeed, d.stillSpeed, 0)
    self.timeHorizon = NvUtil.atLeast(opts.timeHorizon, d.timeHorizon, 1e-3)
    self.maxNeighbours = math.max(1, math.floor(NvUtil.atLeast(opts.maxNeighbours, d.maxNeighbours, 1)))
    self.contactTolerance = math.min(0.9, NvUtil.atLeast(opts.contactTolerance, d.contactTolerance, 0))
    self.separationTime = NvUtil.atLeast(opts.separationTime, d.separationTime, 0)
    self.blockedFor = 0
    self.x, self.y = 0, 0 -- último vector calculado (v1) o desvío de la velocidad segura (v2)
    self.safeX, self.safeY = 0, 0 -- v2: última velocidad segura
    self.lineCount = 0 -- v2: semiplanos que recortaron la última velocidad
    self.corridorDropped = false -- v2: el borde del tramo cedió ante la colisión
    self.infeasible = false -- v2: hizo falta `linearProgram3`
    self.nearestSurface = math.huge -- v2: distancia de superficie al vecino más cercano
    self.neighbourLimit = nil -- v2: tope extra de vecinos (lo pone el agente en LOD 'coarse')
end

local function positionOf(n)
    local t = n.target
    if t then
        return t.x, t.y
    end
    return n.x, n.y
end

-- Lecturas sin `NvUtil.finite`: van por cada vecino de cada agente en cada
-- cuadro. `props.radius` ya está saneado por el agente; las tablas planas de
-- las pruebas traen números o nada.
local function radiusOf(n)
    local props = n.props
    local r
    if props then
        r = props.radius
    else
        r = n.radius
    end
    if r == nil or r ~= r then
        return 16
    end
    return r
end

local function velocityOf(n)
    local vx, vy = n.vx or 0, n.vy or 0
    if vx ~= vx then
        vx = 0
    end
    if vy ~= vy then
        vy = 0
    end
    return vx, vy
end

function LocalAvoidance:reset()
    self.blockedFor = 0
    self.x, self.y = 0, 0
    self.safeX, self.safeY = 0, 0
    self.lineCount = 0
    self.corridorDropped = false
    self.infeasible = false
    self.nearestSurface = math.huge
end

--- Vector de esquiva para `agent` (un `NavigationAgent`). Devuelve ax, ay.
--
-- El bucle está escrito con pocas variables vivas a propósito (sin llamadas a
-- `V.*`, la quietud propia calculada fuera, comparaciones al cuadrado en vez
-- de raíces): es el bucle más caliente de NV después del índice de agentes
-- y con más registros en juego LuaJIT abortaba la traza y lo interpretaba.
function LocalAvoidance:compute(agent, neighbours, dt)
    local x, y = positionOf(agent)
    local r = radiusOf(agent)
    local vx, vy = velocityOf(agent)
    local heading = agent.heading or 0
    local hx, hy = math.cos(heading), math.sin(heading)
    local maxSpeed = agent.props and agent.props.maxSpeed or 120
    local still = self.stillSpeed * maxSpeed
    local stillSq = still * still
    local iAmStill = vx * vx + vy * vy < stillSq
    local margin, horizon, aheadCos = self.margin, self.horizon, self.aheadCos
    local sx, sy = 0, 0
    -- Dos pasadas con pocas variables vivas cada una (ver la cabecera de la
    -- función): 1) separación, 2) predicción y bloqueo.
    for i = 1, #neighbours do
        local n = neighbours[i]
        if n ~= agent then
            local nx, ny = positionOf(n)
            if nx and ny then
                local range = r + radiusOf(n) + margin
                local dx, dy = nx - x, ny - y
                local distSq = dx * dx + dy * dy
                if distSq < range * range then
                    local dist = math.sqrt(distSq)
                    if dist > EPSILON then
                        local w = (1 - dist / range) / dist
                        sx, sy = sx - dx * w, sy - dy * w
                    else
                        sx, sy = sx - hy, sy + hx
                    end
                end
            end
        end
    end
    local blocked = false
    for i = 1, #neighbours do
        local n = neighbours[i]
        if n ~= agent then
            local nx, ny = positionOf(n)
            if nx and ny then
                local dx, dy = nx - x, ny - y
                local dot = dx * hx + dy * hy
                -- Solo con el vecino por delante (el producto escalar con el rumbo es positivo).
                if dot > 0 then
                    local range = r + radiusOf(n) + margin
                    local nvx, nvy = velocityOf(n)
                    local fx, fy = dx + (nvx - vx) * horizon, dy + (nvy - vy) * horizon
                    local fdistSq = fx * fx + fy * fy
                    if fdistSq < range * range then
                        -- Perpendicular al rumbo, lado contrario al vecino.
                        local w = 1 - math.sqrt(fdistSq) / range
                        if hx * dy - hy * dx >= 0 then
                            sx, sy = sx + hy * w, sy - hx * w
                        else
                            sx, sy = sx - hy * w, sy + hx * w
                        end
                    end
                    -- Bloqueo: vecino parado por delante (a menos de 45°), y yo parado.
                    if iAmStill and nvx * nvx + nvy * nvy < stillSq then
                        local distSq = dx * dx + dy * dy
                        local limit = range * 1.2
                        if distSq < limit * limit and dot * dot >= aheadCos * aheadCos * distSq then
                            blocked = true
                        end
                    end
                end
            end
        end
    end
    if blocked then
        self.blockedFor = self.blockedFor + (dt or 0)
    else
        self.blockedFor = 0
    end
    local len = math.sqrt(sx * sx + sy * sy)
    if len > 1 then
        sx, sy = sx / len, sy / len
    end
    self.x, self.y = sx, sy
    return sx, sy
end

--------------------------------------------------------------------------------
-- v2: velocidades seguras (semiplanos tipo ORCA)
--------------------------------------------------------------------------------

-- Rectas de los semiplanos en arrays planos compartidos (el cálculo es
-- secuencial), de paso 4: la recta i ocupa `4i−3 .. 4i` = px, py, dx, dy.
-- `LINES` las del cálculo, `PROJ` las proyectadas de `linearProgram3`.
local LINES, PROJ = {}, {}
-- Vecinos elegidos (los más cercanos) y, por vecino, en arrays paralelos:
-- distancia de superficie, posición y velocidad relativas, suma de radios,
-- desvío `u` y parte que asume este agente.
local NEAR, NEAR_D = {}, {}
local RX, RY, RVX, RVY, RC = {}, {}, {}, {}, {}
local FIXED = {} -- true si el vecino es un obstáculo fijo (tabla plana)
local UX, UY, SHARE = {}, {}, {}
-- Rectas vigentes del último `safeVelocity` (las que usa `speedAlong`); las
-- `obstacleLines` primeras son de obstáculos fijos (duras, ver `linearProgram3`).
local activeLines = 0
local obstacleLines = 0
local ORDER = {} -- vecinos: obstáculos fijos primero

local LP_EPSILON = 1e-5

--- ¿El vecino esquiva por su cuenta? Un agente en marcha, o uno llegado
-- que está haciendo sitio (`makingWay`); una tabla plana o un agente parado,
-- llegado o esperando ruta es un obstáculo.
local function cooperates(n)
    return n.props ~= nil and (n.state == 'moving' or n.makingWay == true)
end

--- ¿Es un agente llegado que puede hacer sitio si se le pide? (v2 con
-- detección de atascos: ver "Hacer sitio" en `agent.lua`).
local function canMakeWay(n)
    local props = n.props
    return props ~= nil and n.state == 'arrived' and props.congestion == true and props.avoidance ~= 'v1'
end

--- Parte del desvío que asume `agent` frente a `n` (ver la cabecera);
-- (relX, relY) va de `agent` a `n`. Las dos partes de una pareja suman 1.
local function responsibility(agent, n, relX, relY, overlapping)
    if not cooperates(n) then
        return 1
    end
    local mine = agent.yieldState == 'yielding'
    local theirs = n.yieldState == 'yielding'
    if mine and not theirs then
        return 0.8
    end
    if theirs and not mine then
        return 0.2
    end
    -- Misma corriente (las dos direcciones preferidas coinciden): el de
    -- detrás frena por el de delante y el de delante no frena por los de
    -- detrás; si ya se solapan, abre hueco el de delante (el de detrás usa
    -- la recta de seguidor, ver `safeVelocity`).
    local ax, ay = agent.prefX, agent.prefY
    local bx, by = n.prefX, n.prefY
    if ax and bx and ax * bx + ay * by > 0.5 then
        local ahead = relX * ax + relY * ay > 0
        if overlapping then
            if ahead then
                return 0.1
            end
            return 0.9
        end
        if ahead then
            return 0.75
        end
        return 0.25
    end
    return 0.5
end

--- ¿`n` va delante de `agent` en la misma corriente? (cooperan los dos).
local function followsInFlow(agent, n, relX, relY)
    if not cooperates(n) or agent.yieldState == 'yielding' or n.yieldState == 'yielding' then
        return false
    end
    local ax, ay = agent.prefX, agent.prefY
    local bx, by = n.prefX, n.prefY
    return ax ~= nil and bx ~= nil and ax * bx + ay * by > 0.5 and relX * ax + relY * ay > 0
end

-- Los `k` vecinos más cercanos por distancia de superficie, ordenados, en
-- `NEAR`/`NEAR_D`. Devuelve cuántos.
local function selectNearest(agent, neighbours, x, y, r, k)
    local count = 0
    for i = 1, #neighbours do
        local n = neighbours[i]
        if n ~= agent then
            local nx, ny = positionOf(n)
            if nx and ny then
                local dx, dy = nx - x, ny - y
                local surface = math.sqrt(dx * dx + dy * dy) - r - radiusOf(n)
                if count < k or surface < NEAR_D[count] then
                    local j = count + 1
                    if count >= k then
                        j = count
                    else
                        count = count + 1
                    end
                    while j > 1 and NEAR_D[j - 1] > surface do
                        NEAR[j] = NEAR[j - 1]
                        NEAR_D[j] = NEAR_D[j - 1]
                        j = j - 1
                    end
                    NEAR[j] = n
                    NEAR_D[j] = surface
                end
            end
        end
    end
    return count
end

-- Recorta el intervalo [tLeft, tRight] de la recta `lineNo` de `A` con las
-- rectas 1..lineNo−1. Devuelve tLeft, tRight, o nil si queda vacío.
local function clipLine(A, lineNo, tLeft, tRight)
    local base = 4 * lineNo - 4
    local px, py, dx, dy = A[base + 1], A[base + 2], A[base + 3], A[base + 4]
    for i = 1, lineNo - 1 do
        local b = 4 * i - 4
        local ex, ey = A[b + 3], A[b + 4]
        local denominator = dx * ey - dy * ex
        local numerator = ex * (py - A[b + 2]) - ey * (px - A[b + 1])
        if denominator > LP_EPSILON or denominator < -LP_EPSILON then
            local t = numerator / denominator
            if denominator >= 0 then
                if t < tRight then
                    tRight = t
                end
            elseif t > tLeft then
                tLeft = t
            end
            if tLeft > tRight then
                return nil
            end
        elseif numerator < 0 then
            -- Rectas paralelas y la i ya deja fuera toda esta.
            return nil
        end
    end
    return tLeft, tRight
end

-- Problema 1D sobre la recta `lineNo` de `A`: el punto de la recta dentro del
-- disco de radio `radius` y de los semiplanos 1..lineNo−1 más cercano a
-- (optX, optY) (o el más lejano en esa dirección con `directionOpt`).
-- Devuelve ok, x, y.
local function linearProgram1(A, lineNo, radius, optX, optY, directionOpt)
    local base = 4 * lineNo - 4
    local px, py, dx, dy = A[base + 1], A[base + 2], A[base + 3], A[base + 4]
    local dot = px * dx + py * dy
    local discriminant = dot * dot + radius * radius - (px * px + py * py)
    if discriminant < 0 then
        return false, 0, 0
    end
    local root = math.sqrt(discriminant)
    local tLeft, tRight = clipLine(A, lineNo, -dot - root, -dot + root)
    if not tLeft then
        return false, 0, 0
    end
    local t
    if directionOpt then
        if optX * dx + optY * dy > 0 then
            t = tRight
        else
            t = tLeft
        end
    else
        t = dx * (optX - px) + dy * (optY - py)
        if t < tLeft then
            t = tLeft
        elseif t > tRight then
            t = tRight
        end
    end
    return true, px + t * dx, py + t * dy
end

-- Programa lineal 2D incremental sobre las rectas 1..n de `A`. Devuelve el
-- índice de la primera recta sin solución (n + 1 si todas caben) y el
-- resultado hasta ese momento.
local function linearProgram2(A, n, radius, optX, optY, directionOpt)
    local rx, ry
    if directionOpt then
        rx, ry = optX * radius, optY * radius
    else
        local lenSq = optX * optX + optY * optY
        if lenSq > radius * radius then
            local len = math.sqrt(lenSq)
            rx, ry = optX / len * radius, optY / len * radius
        else
            rx, ry = optX, optY
        end
    end
    for i = 1, n do
        local b = 4 * i - 4
        -- det(dᵢ, pᵢ − resultado) > 0: el resultado viola el semiplano i.
        if A[b + 3] * (A[b + 2] - ry) - A[b + 4] * (A[b + 1] - rx) > 0 then
            local ok, nx, ny = linearProgram1(A, i, radius, optX, optY, directionOpt)
            if not ok then
                return i, rx, ry
            end
            rx, ry = nx, ny
        end
    end
    return n + 1, rx, ry
end

-- Rectas proyectadas de `linearProgram3` para la recta i: las de obstáculos
-- fijos tal cual (siguen siendo duras) y las demás j < i vistas desde la i.
-- Devuelve cuántas escribió en `PROJ`.
local function projectLines(i, numObstacles)
    local b = 4 * i - 4
    local pix, piy, dix, diy = LINES[b + 1], LINES[b + 2], LINES[b + 3], LINES[b + 4]
    for k = 1, 4 * numObstacles do
        PROJ[k] = LINES[k]
    end
    local m = numObstacles
    for j = numObstacles + 1, i - 1 do
        local c = 4 * j - 4
        local djx, djy = LINES[c + 3], LINES[c + 4]
        local determinant = dix * djy - diy * djx
        local keep = true
        local qx, qy = 0, 0
        if determinant > LP_EPSILON or determinant < -LP_EPSILON then
            local t = (djx * (piy - LINES[c + 2]) - djy * (pix - LINES[c + 1])) / determinant
            qx, qy = pix + t * dix, piy + t * diy
        elseif dix * djx + diy * djy > 0 then
            keep = false -- misma dirección: no aporta
        else
            qx, qy = 0.5 * (pix + LINES[c + 1]), 0.5 * (piy + LINES[c + 2])
        end
        if keep then
            local ex, ey = djx - dix, djy - diy
            local len = math.sqrt(ex * ex + ey * ey)
            if len > LP_EPSILON then
                local o = 4 * m
                m = m + 1
                PROJ[o + 1], PROJ[o + 2], PROJ[o + 3], PROJ[o + 4] = qx, qy, ex / len, ey / len
            end
        end
    end
    return m
end

-- Sin solución: minimiza la mayor penetración en los semiplanos de los
-- vecinos desde `beginLine` (la velocidad "menos mala"), sin ceder nunca en
-- los de obstáculos fijos (las `numObstacles` primeras, como en RVO2).
-- Devuelve x, y.
local function linearProgram3(n, numObstacles, beginLine, radius, rx, ry)
    local distance = 0
    for i = math.max(beginLine, numObstacles + 1), n do
        local b = 4 * i - 4
        local pix, piy, dix, diy = LINES[b + 1], LINES[b + 2], LINES[b + 3], LINES[b + 4]
        if dix * (piy - ry) - diy * (pix - rx) > distance then
            local m = projectLines(i, numObstacles)
            local fail, nx, ny = linearProgram2(PROJ, m, radius, -diy, dix, true)
            if fail > m then
                rx, ry = nx, ny
            end
            distance = dix * (piy - ry) - diy * (pix - rx)
        end
    end
    return rx, ry
end

-- Paso 1 de `safeVelocity`: posición y velocidad relativas y suma de radios
-- de cada vecino elegido (por `scale`: la tolerancia de roce).
local function relativeState(count, x, y, vx, vy, r, scale)
    for i = 1, count do
        local nb = NEAR[i]
        local nx, ny = positionOf(nb)
        local nvx, nvy = velocityOf(nb)
        RX[i], RY[i] = nx - x, ny - y
        RVX[i], RVY[i] = vx - nvx, vy - nvy
        RC[i] = (r + radiusOf(nb)) * scale
        FIXED[i] = nb.props == nil
    end
end

-- Paso 1b: un obstáculo fijo justo EN el camino preferido (por delante, a
-- menos de la suma de radios de la línea de avance y al alcance en
-- `2·timeHorizon` s) tuerce la velocidad preferida hacia el lado contrario
-- al del obstáculo (a la derecha si está centrado). Con el cono truncado de
-- ORCA, un poste justo delante solo frenaría al agente hasta pararlo: el
-- semiplano queda perpendicular al avance y lo más cercano a la preferida es
-- frenar. Los obstáculos que solo bordean el camino (los muros de un puente)
-- no tuercen nada. Devuelve la preferida nueva (mismo módulo).
local function steerAroundFixed(count, pvx, pvy, tau)
    local speed = math.sqrt(pvx * pvx + pvy * pvy)
    if speed <= EPSILON then
        return pvx, pvy
    end
    local ux, uy = pvx / speed, pvy / speed
    local found, bestAlong, bestLateral, bestCombined = false, math.huge, 0, 0
    for i = 1, count do
        if FIXED[i] then
            local relX, relY = RX[i], RY[i]
            local along = relX * ux + relY * uy
            local lateral = relX * -uy + relY * ux
            local combined = RC[i]
            local reach = combined + 2 * speed * tau
            if along > 0 and along < reach and lateral < combined and lateral > -combined and along < bestAlong then
                found, bestAlong, bestLateral, bestCombined = true, along, lateral, combined
            end
        end
    end
    if not found then
        return pvx, pvy
    end
    -- Lado: el contrario al del obstáculo respecto a la línea de avance.
    local side = -1
    if bestLateral < 0 then
        side = 1
    end
    local push = (bestCombined - math.abs(bestLateral)) / bestCombined
    local nx, ny = ux - uy * side * push, uy + ux * side * push
    local len = math.sqrt(nx * nx + ny * ny)
    return nx / len * speed, ny / len * speed
end

-- Paso 2: la recta ORCA de cada vecino (dirección y desvío `u`), en
-- `LINES` (dirección) y `UX`/`UY`. `invSep`: inversa del tiempo para
-- deshacer un solape.
local function orcaGeometry(count, invTau, invSep, mySerial)
    for i = 1, count do
        local relX, relY = RX[i], RY[i]
        local rvx, rvy = RVX[i], RVY[i]
        local combined = RC[i]
        local distSq = relX * relX + relY * relY
        local combinedSq = combined * combined
        local dirX, dirY, ux, uy
        if distSq > combinedSq then
            -- Sin contacto: obstáculo de velocidad truncado a `timeHorizon`.
            local wx, wy = rvx - invTau * relX, rvy - invTau * relY
            local wLenSq = wx * wx + wy * wy
            local dot1 = wx * relX + wy * relY
            if dot1 < 0 and dot1 * dot1 > combinedSq * wLenSq then
                -- Sobre el círculo de corte.
                local wLen = math.sqrt(wLenSq)
                local wx1, wy1 = wx / wLen, wy / wLen
                dirX, dirY = wy1, -wx1
                local k = combined * invTau - wLen
                ux, uy = k * wx1, k * wy1
            else
                -- Sobre una de las dos patas del cono.
                local leg = math.sqrt(distSq - combinedSq)
                if relX * wy - relY * wx > 0 then
                    dirX = (relX * leg - relY * combined) / distSq
                    dirY = (relX * combined + relY * leg) / distSq
                else
                    dirX = -(relX * leg + relY * combined) / distSq
                    dirY = -(-relX * combined + relY * leg) / distSq
                end
                local dot2 = rvx * dirX + rvy * dirY
                ux, uy = dot2 * dirX - rvx, dot2 * dirY - rvy
            end
        else
            -- Ya se tocan: separarse en `separationTime` s.
            local wx, wy = rvx - invSep * relX, rvy - invSep * relY
            local wLen = math.sqrt(wx * wx + wy * wy)
            local wx1, wy1 = 1, 0
            if wLen > EPSILON then
                wx1, wy1 = wx / wLen, wy / wLen
            else
                -- Mismo centro y misma velocidad: un eje fijo, con el
                -- sentido según el número de serie (cada uno a un lado).
                wLen = 0
                if mySerial >= (NEAR[i].serial or 0) then
                    wx1 = -1
                end
            end
            dirX, dirY = wy1, -wx1
            local k = combined * invSep - wLen
            ux, uy = k * wx1, k * wy1
        end
        local o = 4 * i
        LINES[o - 1], LINES[o] = dirX, dirY
        UX[i], UY[i] = ux, uy
    end
end

-- Paso 3: la parte de cada desvío que asume el agente; el seguidor solapado
-- en su corriente cambia su recta por "no acercarse más rápido de lo que el
-- otro se aleja, sin retroceder" (la columna arranca junta en vez de recular
-- entera); a un llegado demasiado cerca se le pide sitio.
local function shares(agent, count, vx, vy, invSep, margin)
    local moving = agent.state == 'moving'
    for i = 1, count do
        local nb = NEAR[i]
        local relX, relY = RX[i], RY[i]
        local combined = RC[i]
        local distSq = relX * relX + relY * relY
        local overlapping = distSq <= combined * combined
        if overlapping and followsInFlow(agent, nb, relX, relY) then
            local dist = math.sqrt(distSq)
            local nx1, ny1 = 1, 0
            if dist > EPSILON then
                nx1, ny1 = relX / dist, relY / dist
            end
            local nvx, nvy = velocityOf(nb)
            local c = (nvx * nx1 + nvy * ny1) - 0.1 * (combined - dist) * invSep
            if c < 0 then
                c = 0
            end
            local o = 4 * i
            LINES[o - 1], LINES[o] = -ny1, nx1
            UX[i], UY[i] = nx1 * c - vx, ny1 * c - vy
            SHARE[i] = 1
        else
            SHARE[i] = responsibility(agent, nb, relX, relY, overlapping)
        end
        if moving and canMakeWay(nb) then
            local near = combined + 2 * margin
            if distSq < near * near then
                nb.nudged = true
            end
        end
    end
end

-- Paso 4 (bloqueo, como en v1): ¿hay un vecino parado por delante (a menos
-- de 45° del rumbo) estando el agente parado?
local function stillAhead(count, hx, hy, stillSq, margin, aheadCos)
    for i = 1, count do
        local nvx, nvy = velocityOf(NEAR[i])
        if nvx * nvx + nvy * nvy < stillSq then
            local relX, relY = RX[i], RY[i]
            local distSq = relX * relX + relY * relY
            local dot = relX * hx + relY * hy
            local limit = (RC[i] + margin) * 1.2
            if dot > 0 and distSq < limit * limit and dot * dot >= aheadCos * aheadCos * distSq then
                return true
            end
        end
    end
    return false
end

--- v2: velocidad segura para `agent` (un `NavigationAgent` o una tabla
-- plana) con velocidad preferida (pvx, pvy). `maxSpeed` acota la respuesta
-- (por defecto `props.maxSpeed`). `cnx, cny, cc` (opcionales): el borde del
-- tramo como semiplano `v·n ≤ c` (ver la cabecera). Devuelve vx, vy. No
-- reserva memoria.
function LocalAvoidance:safeVelocity(agent, neighbours, pvx, pvy, dt, maxSpeed, cnx, cny, cc)
    local x, y = positionOf(agent)
    local r = radiusOf(agent)
    local vx, vy = velocityOf(agent)
    maxSpeed = maxSpeed or (agent.props and agent.props.maxSpeed) or 120
    if not dt or dt <= 0 then
        dt = 1 / 60
    end
    -- Un solape se deshace en `separationTime` s (no en un cuadro): sin
    -- tirones cuando varios salen apelotonados.
    local invSep = 1 / math.max(dt, self.separationTime)
    local count = 0
    if neighbours then
        -- `neighbourLimit` (LOD 'coarse' del agente) recorta aún más.
        local k = self.maxNeighbours
        local limit = self.neighbourLimit
        if limit and limit < k then
            k = limit
        end
        count = selectNearest(agent, neighbours, x, y, r, k)
    end
    self.nearestSurface = count > 0 and NEAR_D[1] or math.huge
    relativeState(count, x, y, vx, vy, r, 1 - self.contactTolerance)
    pvx, pvy = steerAroundFixed(count, pvx, pvy, self.timeHorizon)
    orcaGeometry(count, 1 / self.timeHorizon, invSep, agent.serial or 0)
    shares(agent, count, vx, vy, invSep, self.margin)
    -- Obstáculos fijos (tablas planas) primero: sus rectas son duras.
    local numObstacles = 0
    for i = 1, count do
        if NEAR[i].props == nil then
            numObstacles = numObstacles + 1
            ORDER[numObstacles] = i
        end
    end
    local k = numObstacles
    for i = 1, count do
        if NEAR[i].props ~= nil then
            k = k + 1
            ORDER[k] = i
        end
    end
    -- Las direcciones de `LINES` están por índice de vecino: se copian en
    -- `PROJ` y se reescriben en el orden nuevo.
    for i = 1, count do
        local o = 4 * i
        PROJ[o - 1], PROJ[o] = LINES[o - 1], LINES[o]
    end
    for slot = 1, count do
        local i = ORDER[slot]
        local o, q = 4 * slot, 4 * i
        LINES[o - 3], LINES[o - 2] = vx + SHARE[i] * UX[i], vy + SHARE[i] * UY[i]
        LINES[o - 1], LINES[o] = PROJ[q - 1], PROJ[q]
    end
    -- Bloqueo (como en v1).
    local still = self.stillSpeed * maxSpeed
    local stillSq = still * still
    local blocked = false
    if count > 0 and vx * vx + vy * vy < stillSq then
        local heading = agent.heading or 0
        blocked = stillAhead(count, math.cos(heading), math.sin(heading), stillSq, self.margin, self.aheadCos)
    end
    for i = 1, count do
        NEAR[i] = nil -- sin referencias colgadas entre cuadros
    end
    if blocked then
        self.blockedFor = self.blockedFor + dt
    else
        self.blockedFor = 0
    end
    -- 2) seguir en la red: el borde del tramo va el último y cede si estorba.
    local m = count
    local withCorridor = cnx ~= nil and cny ~= nil and cc ~= nil
    if withCorridor then
        m = count + 1
        local o = 4 * m
        LINES[o - 3], LINES[o - 2], LINES[o - 1], LINES[o] = cnx * cc, cny * cc, -cny, cnx
    end
    local fail, sx, sy = linearProgram2(LINES, m, maxSpeed, pvx, pvy, false)
    self.corridorDropped, self.infeasible = false, false
    if fail <= m then
        if withCorridor then
            -- 1) no chocar manda sobre seguir en la red.
            self.corridorDropped = true
            m = count
            fail, sx, sy = linearProgram2(LINES, count, maxSpeed, pvx, pvy, false)
        end
        if fail <= m then
            self.infeasible = true
            sx, sy = linearProgram3(m, numObstacles, fail, maxSpeed, sx, sy)
        end
    end
    activeLines = m
    obstacleLines = numObstacles
    self.lineCount = m
    self.safeX, self.safeY = sx, sy
    -- Para depurar: el desvío respecto a la preferida, en unidades de maxSpeed.
    local ax, ay = 0, 0
    if maxSpeed > EPSILON then
        ax, ay = (sx - pvx) / maxSpeed, (sy - pvy) / maxSpeed
        local len = math.sqrt(ax * ax + ay * ay)
        if len > 1 then
            ax, ay = ax / len, ay / len
        end
    end
    self.x, self.y = ax, ay
    return sx, sy
end

-- Intervalo [sLo, sHi] de rapideces sobre la recta s·h que cumplen los
-- semiplanos first..last (acotado por el que entra).
local function speedRange(hx, hy, first, last, sLo, sHi)
    for i = first, last do
        local b = 4 * i - 4
        local dx, dy = LINES[b + 3], LINES[b + 4]
        -- Semiplano i sobre la recta s·h: det(dᵢ, pᵢ) − s·det(dᵢ, h) ≤ 0.
        local a = dx * hy - dy * hx
        local c = dx * LINES[b + 2] - dy * LINES[b + 1]
        if a > LP_EPSILON then
            local t = c / a
            if t > sLo then
                sLo = t
            end
        elseif a < -LP_EPSILON then
            local t = c / a
            if t < sHi then
                sHi = t
            end
        end
    end
    return sLo, sHi
end

--- v2: rapidez a lo largo del rumbo unitario (hx, hy) dentro de [lo, hi]
-- (lo negativo = marcha atrás) que cumple todos los semiplanos del último
-- `safeVelocity`, la más cercana a `desired`. Si ninguna los cumple (vecinos
-- encima), la más cercana que cumple al menos los de obstáculos fijos; si ni
-- eso, se fía de `desired` acotada (la proyección de la respuesta de
-- `linearProgram3`).
function LocalAvoidance:speedAlong(hx, hy, lo, hi, desired)
    local oLo, oHi = speedRange(hx, hy, 1, obstacleLines, lo, hi)
    if oLo > oHi then
        oLo, oHi = lo, hi
    end
    local sLo, sHi = speedRange(hx, hy, obstacleLines + 1, activeLines, oLo, oHi)
    if sLo > sHi then
        sLo, sHi = oLo, oHi
    end
    if desired < sLo then
        return sLo
    end
    if desired > sHi then
        return sHi
    end
    return desired
end

return LocalAvoidance

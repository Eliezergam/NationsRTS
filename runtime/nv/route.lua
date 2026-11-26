-- Ruta de un agente: la concatenación de trozos que va desde donde está hasta
-- su destino, con una sola distancia acumulada `d` de principio a fin.
--
--   route:length()                 -- longitud total
--   local x, y = route:positionAt(d)
--   local tx, ty = route:tangentAt(d)      -- unitaria
--   local k = route:curvatureAt(d)
--   local last, nextNode = route:nodeAt(d) -- último nodo dejado atrás y siguiente por delante
--   route:waypoints()                      -- lista plana {x1,y1,x2,y2,...} para dibujar
--   route.steps                            -- los pasos de A* ({segment=, reversed=}), COMPARTIDOS
--                                          -- entre agentes con el mismo origen/destino de nodo
-- Trozos (`pieces`), en orden:
--
--   1. línea recta desde la posición real hasta su proyección en la red (si hay hueco);
--   2. el trozo del segmento de origen desde la proyección hasta el nodo por el que se sale;
--   3. los segmentos completos de los pasos de A*;
--   4. el trozo del segmento de destino desde el nodo por el que se entra hasta la proyección;
--   5. línea recta desde la proyección hasta el destino pedido (el puesto de formación).
--
-- Con origen y destino en el mismo segmento, 2-4 se funden en un único trozo.
-- Cada trozo es `{ kind = 'line', x1, y1, x2, y2, ux, uy, len }` o
-- `{ kind = 'segment', segment, d0, dir (±1), len, node0, node1 }`: se recorre
-- desde la distancia `d0` del segmento en el sentido `dir`. `offsets[i]` es la
-- distancia acumulada donde empieza el trozo i; `locate(d)` usa un índice de
-- pista (`_hint`) porque un agente avanza casi siempre hacia delante.

local NvUtil = require('runtime.nv.util')
local V = require('runtime.nv.vector2')

local Route = NvUtil.class('Route')

Route.WAYPOINT_STEP = 8

function Route:init(system)
    self.system = system
    self.pieces = {}
    self.offsets = {}
    self.total = 0
    self.steps = {}
    self.nodes = {}
    self.cost = 0
    self.start, self.goal = nil, nil
    self.startProjection, self.goalProjection = nil, nil
    self._hint = 1
    self._waypoints = nil
end

--- Añade una recta (si mide algo).
function Route:addLine(x1, y1, x2, y2)
    local ux, uy, len = V.normalize(x2 - x1, y2 - y1)
    if len <= V.EPSILON then
        return self
    end
    self.pieces[#self.pieces + 1] = { kind = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, ux = ux, uy = uy, len = len }
    return self
end

--- Añade el trozo de `segment` que va de la distancia `d0` a la `d1`
-- (medidas desde `from`; `d1 < d0` = a contramano). `node0`/`node1` son los
-- nodos en los extremos del trozo, si el extremo cae en un nodo.
function Route:addSegmentPart(segment, d0, d1, node0, node1)
    d0 = V.clamp(d0, 0, segment.length)
    d1 = V.clamp(d1, 0, segment.length)
    local len = math.abs(d1 - d0)
    if len <= V.EPSILON then
        return self
    end
    self.pieces[#self.pieces + 1] = {
        kind = 'segment',
        segment = segment,
        d0 = d0,
        dir = d1 >= d0 and 1 or -1,
        len = len,
        node0 = node0,
        node1 = node1,
    }
    return self
end

--- Añade un paso de A* entero.
function Route:addStep(step)
    local seg = step.segment
    if step.reversed then
        return self:addSegmentPart(seg, seg.length, 0, seg.to, seg.from)
    end
    return self:addSegmentPart(seg, 0, seg.length, seg.from, seg.to)
end

--- Cierra la ruta: acumula desplazamientos y los nodos anterior/siguiente de
-- cada trozo.
function Route:finish()
    local total = 0
    local last = nil
    for i, piece in ipairs(self.pieces) do
        self.offsets[i] = total
        total = total + piece.len
        piece.lastNode = piece.node0 or last
        if piece.node1 then
            last = piece.node1
        elseif piece.node0 then
            last = piece.node0
        end
    end
    local nextNode = nil
    for i = #self.pieces, 1, -1 do
        local piece = self.pieces[i]
        piece.nextNode = piece.node1 or nextNode
        if piece.node0 then
            nextNode = piece.node0
        elseif piece.node1 then
            nextNode = piece.node1
        end
    end
    self.total = total
    self._hint = 1
    self._waypoints = nil
    return self
end

function Route:length()
    return self.total
end

function Route:pieceCount()
    return #self.pieces
end

-- Trozo y distancia local para una `d` global (acotada).
function Route:locate(d)
    local pieces, offsets = self.pieces, self.offsets
    local n = #pieces
    if n == 0 then
        return nil, 0
    end
    if d ~= d then
        d = 0
    end
    if d <= 0 then
        self._hint = 1
        return pieces[1], 0
    end
    if d >= self.total then
        self._hint = n
        return pieces[n], pieces[n].len
    end
    local i = self._hint
    if i < 1 or i > n then
        i = 1
    end
    while i < n and offsets[i + 1] <= d do
        i = i + 1
    end
    while i > 1 and offsets[i] > d do
        i = i - 1
    end
    self._hint = i
    return pieces[i], d - offsets[i]
end

function Route:positionAt(d)
    local piece, s = self:locate(d)
    if not piece then
        if self.start then
            return self.start.x, self.start.y
        end
        return 0, 0
    end
    if piece.kind == 'line' then
        return piece.x1 + piece.ux * s, piece.y1 + piece.uy * s
    end
    return piece.segment:positionAt(piece.d0 + piece.dir * s)
end

--- Tangente unitaria en el sentido de avance.
function Route:tangentAt(d)
    local piece, s = self:locate(d)
    if not piece then
        return 0, 0
    end
    if piece.kind == 'line' then
        return piece.ux, piece.uy
    end
    local tx, ty = piece.segment.arc:tangentAtDistance(piece.d0 + piece.dir * s)
    if piece.dir < 0 then
        return -tx, -ty
    end
    return tx, ty
end

function Route:curvatureAt(d)
    local piece, s = self:locate(d)
    if not piece or piece.kind == 'line' then
        return 0
    end
    return piece.segment:curvatureAt(piece.d0 + piece.dir * s)
end

--- Curvatura máxima en la ventana [d, d + ahead], sin reservar memoria.
function Route:maxCurvatureAhead(d, ahead)
    local d1 = math.min(self.total, d + ahead)
    local best = 0
    local pieces, offsets = self.pieces, self.offsets
    -- Empezar por el trozo de d (locate mueve la pista; no importa).
    local piece = self:locate(d)
    if not piece then
        return 0
    end
    local i = self._hint
    while i <= #pieces do
        local p = pieces[i]
        local p0, p1 = offsets[i], offsets[i] + p.len
        if p0 > d1 then
            break
        end
        if p.kind == 'segment' then
            local a = math.max(d, p0) - p0
            local b = math.min(d1, p1) - p0
            local sa, sb = p.d0 + p.dir * a, p.d0 + p.dir * b
            local k = p.segment:maxCurvatureBetween(sa, sb)
            if k > best then
                best = k
            end
        end
        i = i + 1
    end
    return best
end

--- Segmento bajo la distancia d (nil en una recta libre) y la distancia
-- dentro de él desde su nodo `from`.
function Route:segmentAt(d)
    local piece, s = self:locate(d)
    if not piece or piece.kind ~= 'segment' then
        return nil
    end
    return piece.segment, piece.d0 + piece.dir * s
end

--- Nodo que se acaba de dejar atrás y nodo siguiente (ids; pueden ser nil en
-- las rectas de entrada/salida).
function Route:nodeAt(d)
    local piece = self:locate(d)
    if not piece then
        return nil, nil
    end
    return piece.lastNode, piece.nextNode
end

--- Polilínea plana `{x1, y1, x2, y2, ...}` muestreada cada `WAYPOINT_STEP` px
-- (se calcula una vez).
function Route:waypoints()
    if self._waypoints then
        return self._waypoints
    end
    local out = {}
    local step = Route.WAYPOINT_STEP
    local d = 0
    while true do
        local x, y = self:positionAt(d)
        out[#out + 1], out[#out + 2] = x, y
        if d >= self.total then
            break
        end
        d = math.min(self.total, d + step)
    end
    self._waypoints = out
    return out
end

--- Distancia del punto a la ruta buscando cerca de `d` (ventana `back` hacia
-- atrás y `ahead` hacia delante, muestreando cada `step`). Devuelve la
-- distancia a lo largo de la ruta del punto más cercano y su separación.
function Route:project(x, y, d, back, ahead, step)
    step = step or 4
    local d0 = math.max(0, d - (back or 32))
    local d1 = math.min(self.total, d + (ahead or 64))
    local best, bestSq = d0, math.huge
    local s = d0
    while true do
        local px, py = self:positionAt(s)
        local sq = V.distanceSq(x, y, px, py)
        if sq < bestSq then
            best, bestSq = s, sq
        end
        if s >= d1 then
            break
        end
        s = math.min(d1, s + step)
    end
    -- Afinado: entre las dos muestras vecinas.
    local a, b = math.max(d0, best - step), math.min(d1, best + step)
    local ax, ay = self:positionAt(a)
    local bx, by = self:positionAt(b)
    local _, _, u, dist = V.closestOnSegment(x, y, ax, ay, bx, by)
    if dist * dist < bestSq then
        return a + (b - a) * u, dist
    end
    return best, math.sqrt(bestSq)
end

return Route

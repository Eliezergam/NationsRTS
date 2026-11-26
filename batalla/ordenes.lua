-- Órdenes del jugador en la batalla 3D (Valeria): el camino por terreno
-- transitable hasta un punto, los huecos de una formación y el punto del
-- terreno bajo el ratón.
--
--   rejilla    celdas de `celda` px dentro del límite del campo; se puede
--              pisar la que acepta un tanque al conducir (`Tropas:libre`: ni
--              agua salvo puentes y calzadas, ni pendiente ni desnivel, ni
--              árbol ni edificio) y por la que cabe un tanque entre los
--              árboles y las rocas grandes (`Ordenes.radioObstaculo`, mirado
--              en 3 x 3 puntos de la celda): la ruta larga ya rodea los
--              bosques y los árboles sueltos (el dueño, 2026-10-01: que los
--              vea desde lejos y tuerza antes; diseno/movimiento-unidades-
--              batalla.md §4.1, obstáculos rasterizados con holgura). Se
--              hace una vez, al abrir la escena.
--   ruta       A* de batalla/pasillos.lua sobre esa rejilla, recortado por
--              línea recta mientras las celdas de en medio se puedan pisar.
--   formación  los tanques delante, la infantería detrás y los lanzacohetes
--              al fondo, en filas perpendiculares a la marcha; cada hueco,
--              en el sitio libre más cercano.
--
-- Solo calcula: las unidades siguen la ruta en batalla/tropas.lua (orden
-- 'mover') con su física de siempre. No toca la simulación.

local Pasillos = require('batalla.pasillos')

local Ordenes = {}
Ordenes.__index = Ordenes

Ordenes.celda = 120 -- px de la rejilla de rutas (12 m)
Ordenes.margen = 150 -- px del borde del límite que no se pisa
-- Holgura con los árboles y las rocas grandes (px): un punto de la celda
-- está tapado si hay un tronco a menos de esto (la holgura de un tanque, 62
-- px de `Tropas.radioTransitable`, más el tronco). La celda se cierra si su
-- centro está tapado (el punto por el que pasa la ruta) o si lo están 5 de
-- sus 9 puntos (un bosque): así la ruta rodea los bosques y los árboles
-- sueltos desde el principio, y entre dos árboles a 20 m sigue habiendo paso.
Ordenes.radioObstaculo = 70
Ordenes.pasoMuestra = 40 -- px entre los 3 x 3 puntos de una celda
Ordenes.tapadosParaCerrar = 5
Ordenes.pasoCurva = 40 -- px (4 m) entre los puntos de una ruta suave
Ordenes.separacion = { tanque = 230, lanzacohetes = 320 } -- px entre huecos de una fila
Ordenes.porFila = { tanque = 8, lanzacohetes = 6 }
Ordenes.entreFilas = { tanque = 260, lanzacohetes = 340 }
Ordenes.orden = { 'tanque', 'lanzacohetes' } -- de delante hacia atrás
-- Holgura de un hueco: el sitio y un anillo de este radio (px) alrededor deben
-- poder pisarse (sin árboles, agua, pendiente ni edificios), para que la
-- unidad quepa al llegar y pueda girar. El camión necesita más.
Ordenes.holgura = { tanque = 120, lanzacohetes = 200 }
-- Un hueco no se pone a menos de esto (px) de otro hueco ni de un vehículo
-- propio parado que no va en el grupo.
Ordenes.apartado = { tanque = 170, lanzacohetes = 240 }
Ordenes.busqueda = 260 -- intentos de la espiral (hasta ~1 km)

function Ordenes.nuevas(tropas)
    local self = setmetatable({}, Ordenes)
    self.tropas = tropas
    return self
end

--- Rejilla de rutas (se hace la primera vez que se pide).
function Ordenes:rejilla()
    if self.g then
        return self.g
    end
    local inicio = love.timer.getTime()
    local suelo = self.tropas.suelo
    local lim = suelo.limite
    local celda = Ordenes.celda
    local cx, cy, r
    if lim then
        cx, cy, r = lim.cx, lim.cy, lim.radio
    else
        cx, cy, r = suelo.cx, suelo.cy, 12000
    end
    local n = math.floor(2 * r / celda) + 1
    local x0, y0 = cx - r, cy - r
    local prohibida, pend = {}, {}
    local libres = 0
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            local x, y = x0 + i * celda, y0 + j * celda
            -- La misma prueba que al conducir (agua, pendiente, desnivel,
            -- árboles, edificios), en el centro de la celda.
            local si = (not lim or lim:dentro(x, y, Ordenes.margen)) and self.tropas:libre(x, y, true, 'tanque')
            if si then
                si = not self:cerradaPorArboles(x, y)
            end
            prohibida[k] = not si
            pend[k] = 0
            if si then
                libres = libres + 1
            end
        end
    end
    self.g = {
        n = n,
        x0 = x0,
        y0 = y0,
        celda = celda,
        prohibida = prohibida,
        bloqueada = prohibida,
        aguaCelda = {},
        pend = pend,
        rio = {},
        cerca = {},
        h = {},
        nivelMar = suelo.nivelMar,
    }
    self.msRejilla = (love.timer.getTime() - inicio) * 1000
    self.libres = libres
    return self.g
end

--- ¿Cierran los árboles (o las rocas grandes) la celda centrada en (x, y)?
-- Su centro tapado, o `tapadosParaCerrar` de sus 3 x 3 puntos.
function Ordenes:cerradaPorArboles(x, y)
    local suelo = self.tropas.suelo
    local radio = Ordenes.radioObstaculo
    if suelo:plantaCerca(x, y, radio, true) then
        return true
    end
    local paso = Ordenes.pasoMuestra
    local tapados = 0
    for dj = -1, 1 do
        for di = -1, 1 do
            if (di ~= 0 or dj ~= 0) and suelo:plantaCerca(x + di * paso, y + dj * paso, radio, true) then
                tapados = tapados + 1
            end
        end
    end
    return tapados >= Ordenes.tapadosParaCerrar
end

local function celdaDe(g, x, y)
    local i = math.floor((x - g.x0) / g.celda + 0.5)
    local j = math.floor((y - g.y0) / g.celda + 0.5)
    return math.max(0, math.min(g.n - 1, i)), math.max(0, math.min(g.n - 1, j))
end

local function centro(g, i, j)
    return g.x0 + i * g.celda, g.y0 + j * g.celda
end

--- La celda que se puede pisar más cercana a (x, y), o nil.
function Ordenes:celdaLibre(x, y)
    local g = self:rejilla()
    local i, j = celdaDe(g, x, y)
    if not g.prohibida[j * g.n + i] then
        return i, j
    end
    for radio = 1, 40 do
        local mejor, mejorD
        for dj = -radio, radio do
            for di = -radio, radio do
                if math.max(math.abs(di), math.abs(dj)) == radio then
                    local a, b = i + di, j + dj
                    if a >= 0 and b >= 0 and a < g.n and b < g.n and not g.prohibida[b * g.n + a] then
                        local px, py = centro(g, a, b)
                        local d = (px - x) ^ 2 + (py - y) ^ 2
                        if not mejorD or d < mejorD then
                            mejor, mejorD = { a, b }, d
                        end
                    end
                end
            end
        end
        if mejor then
            return mejor[1], mejor[2]
        end
    end
    return nil
end

--- ¿Se pueden pisar todas las celdas de la recta de (ax, ay) a (bx, by)?
function Ordenes:recta(ax, ay, bx, by)
    local g = self:rejilla()
    local d = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local pasos = math.max(1, math.ceil(d / (g.celda * 0.5)))
    for s = 0, pasos do
        local t = s / pasos
        local i, j = celdaDe(g, ax + (bx - ax) * t, ay + (by - ay) * t)
        if g.prohibida[j * g.n + i] then
            return false
        end
    end
    return true
end

--- Camino de (x0, y0) a (x1, y1) por terreno transitable: lista de puntos {
-- x, y } (el primero, el origen; el último, el destino o, si cae en el agua
-- o en un edificio, el punto transitable más cercano). nil si no hay camino.
function Ordenes:ruta(x0, y0, x1, y1)
    local g = self:rejilla()
    local i0, j0 = self:celdaLibre(x0, y0)
    local i1, j1 = self:celdaLibre(x1, y1)
    if not (i0 and i1) then
        return nil
    end
    local fx, fy = x1, y1
    local ci, cj = celdaDe(g, x1, y1)
    if g.prohibida[cj * g.n + ci] then
        -- En el agua o en un edificio: al punto transitable más cercano.
        fx, fy = centro(g, i1, j1)
    end
    local puntos
    if self:recta(x0, y0, fx, fy) then
        puntos = { { x = x0, y = y0 }, { x = fx, y = fy } }
    else
        local camino = Pasillos.aEstrella(g, i0, j0, i1, j1, 90, false)
        if not camino then
            return nil
        end
        local todos = { { x = x0, y = y0 } }
        for q = 2, #camino - 1 do
            local k = camino[q]
            local px, py = centro(g, k % g.n, math.floor(k / g.n))
            todos[#todos + 1] = { x = px, y = py }
        end
        todos[#todos + 1] = { x = fx, y = fy }
        -- Recorta: desde cada punto, al más lejano que se vea en línea recta.
        puntos = { todos[1] }
        local a = 1
        while a < #todos do
            local b = #todos
            while b > a + 1 and not self:recta(todos[a].x, todos[a].y, todos[b].x, todos[b].y) do
                b = b - 1
            end
            puntos[#puntos + 1] = todos[b]
            a = b
        end
    end
    return puntos
end

--- Punto de la Catmull-Rom centrípeta del tramo de `p1` a `p2` (con `p0`
-- antes y `p3` después) en `u` (0 a 1). La centrípeta no hace bucles ni se
-- pasa de largo con tramos de largos muy distintos (los de una ruta tensada).
local function centripeta(p0, p1, p2, p3, u)
    local function nudo(a, b)
        return math.max(0.0001, ((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) ^ 0.25)
    end
    local t0 = 0
    local t1 = t0 + nudo(p0, p1)
    local t2 = t1 + nudo(p1, p2)
    local t3 = t2 + nudo(p2, p3)
    local t = t1 + (t2 - t1) * u
    local function mezcla(a, b, ta, tb)
        local f = (t - ta) / (tb - ta)
        return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
    end
    local a1x, a1y = mezcla(p0, p1, t0, t1)
    local a2x, a2y = mezcla(p1, p2, t1, t2)
    local a3x, a3y = mezcla(p2, p3, t2, t3)
    local fb1 = (t - t0) / (t2 - t0)
    local b1x = a1x + (a2x - a1x) * fb1
    local b1y = a1y + (a2y - a1y) * fb1
    local fb2 = (t - t1) / (t3 - t1)
    local b2x = a2x + (a3x - a2x) * fb2
    local b2y = a2y + (a3y - a2y) * fb2
    local fc = (t - t1) / (t2 - t1)
    return b1x + (b2x - b1x) * fc, b1y + (b2y - b1y) * fc
end

--- Ruta suave por `puntos` (lista de { x, y }; el primero, donde está la
-- unidad): primero tensada (de cada punto, al más lejano que se ve en línea
-- recta por celdas que se pueden pisar) y luego curva Catmull-Rom centrípeta
-- muestreada cada `pasoCurva` px. Un tramo cuya curva pisaría una celda
-- cerrada (árboles, agua) se queda recto. El primero y el último no cambian.
function Ordenes:suavizar(puntos)
    local n = #puntos
    if n < 2 then
        return puntos
    end
    local tensos = { puntos[1] }
    local a = 1
    while a < n do
        local b = n
        while b > a + 1 and not self:recta(puntos[a].x, puntos[a].y, puntos[b].x, puntos[b].y) do
            b = b - 1
        end
        tensos[#tensos + 1] = puntos[b]
        a = b
    end
    local m = #tensos
    local suave = { { x = tensos[1].x, y = tensos[1].y } }
    for i = 1, m - 1 do
        local p1, p2 = tensos[i], tensos[i + 1]
        -- En las puntas, el punto de fuera se prolonga en línea recta.
        local p0 = tensos[i - 1] or { x = 2 * p1.x - p2.x, y = 2 * p1.y - p2.y }
        local p3 = tensos[i + 2] or { x = 2 * p2.x - p1.x, y = 2 * p2.y - p1.y }
        local largo = math.sqrt((p2.x - p1.x) ^ 2 + (p2.y - p1.y) ^ 2)
        local pasos = math.max(1, math.ceil(largo / Ordenes.pasoCurva))
        local tramo = {}
        local px, py = p1.x, p1.y
        local curva = true
        for k = 1, pasos - 1 do
            local x, y = centripeta(p0, p1, p2, p3, k / pasos)
            if not self:recta(px, py, x, y) then
                curva = false
                break
            end
            tramo[#tramo + 1] = { x = x, y = y }
            px, py = x, y
        end
        if curva and not self:recta(px, py, p2.x, p2.y) then
            curva = false
        end
        if not curva then
            tramo = {}
            for k = 1, pasos - 1 do
                local f = k / pasos
                tramo[#tramo + 1] = { x = p1.x + (p2.x - p1.x) * f, y = p1.y + (p2.y - p1.y) * f }
            end
        end
        for _, q in ipairs(tramo) do
            suave[#suave + 1] = q
        end
        suave[#suave + 1] = { x = p2.x, y = p2.y }
    end
    return suave
end

--- ¿Cabe una unidad de `tipo` en (x, y)? El sitio y un anillo de
-- `Ordenes.holgura` px alrededor se pueden pisar, y la celda de la rejilla
-- de rutas también (se puede llegar).
function Ordenes:holgado(x, y, tipo)
    local tropas = self.tropas
    if not tropas:libre(x, y, true, tipo) then
        return false
    end
    local g = self:rejilla()
    local i, j = celdaDe(g, x, y)
    if g.prohibida[j * g.n + i] then
        return false
    end
    local r = Ordenes.holgura[tipo] or 0
    if r > 0 then
        for k = 0, 7 do
            local a = k * math.pi / 4
            if not tropas:libre(x + math.cos(a) * r, y + math.sin(a) * r, true, tipo) then
                return false
            end
        end
    end
    return true
end

--- ¿Hay a menos de `distancia` de (x, y) un hueco ya elegido o una unidad
-- propia (vehículo) parada que no va en `grupo`?
local function estorba(x, y, distancia, elegidos, unidades, grupo, bando)
    local d2 = distancia * distancia
    for _, h in ipairs(elegidos) do
        if (h.x - x) ^ 2 + (h.y - y) ^ 2 < d2 then
            return true
        end
    end
    for _, o in ipairs(unidades) do
        if
            not grupo[o]
            and o.bando == bando
            and not o.muerto
            and not (o.orden and o.orden.avanza)
            and (o.x - x) ^ 2 + (o.y - y) ^ 2 < d2
        then
            return true
        end
    end
    return false
end

--- Huecos de formación para `unidades` alrededor de (x, y), mirando en el
-- rumbo `rumbo`: devuelve { [unidad] = { x, y } }. Cada hueco, en el sitio
-- holgado más cercano a su sitio de la formación (`Ordenes:holgado`: lejos
-- de bosques, agua, pendientes y de otros huecos o vehículos parados), y
-- cada unidad, al hueco libre más cercano a ella (no se cruzan).
function Ordenes:formacion(unidades, x, y, rumbo)
    local tropas = self.tropas
    local ca, sa = math.cos(rumbo), math.sin(rumbo)
    local porTipo = {}
    local grupo = {}
    for _, u in ipairs(unidades) do
        porTipo[u.tipo] = porTipo[u.tipo] or {}
        table.insert(porTipo[u.tipo], u)
        grupo[u] = true
    end
    local huecos = {}
    local elegidos = {}
    local fondo = 0
    for _, tipo in ipairs(Ordenes.orden) do
        local lista = porTipo[tipo]
        if lista then
            local porFila = Ordenes.porFila[tipo]
            local sep = Ordenes.separacion[tipo]
            local filas = math.ceil(#lista / porFila)
            local sitios = {}
            for k = 1, #lista do
                local fila = math.floor((k - 1) / porFila)
                local enFila = math.min(porFila, #lista - fila * porFila)
                local columna = (k - 1) % porFila - (enFila - 1) / 2
                local d = -(fondo + fila * Ordenes.entreFilas[tipo])
                local hx = x + ca * d - sa * columna * sep
                local hy = y + sa * d + ca * columna * sep
                -- El sitio holgado más cercano: una espiral desde el ideal.
                local apartado = Ordenes.apartado[tipo] or 0
                local bando = lista[1].bando
                local px, py = hx, hy
                for intento = 0, Ordenes.busqueda do
                    local a = intento * 2.39996
                    local r = math.sqrt(intento) * 60
                    local cx, cy = hx + math.cos(a) * r, hy + math.sin(a) * r
                    if
                        self:holgado(cx, cy, tipo)
                        and not estorba(cx, cy, apartado, elegidos, tropas.unidades, grupo, bando)
                    then
                        px, py = cx, cy
                        break
                    end
                end
                local h = { x = px, y = py }
                sitios[#sitios + 1] = h
                elegidos[#elegidos + 1] = h
            end
            -- Cada unidad al sitio libre más cercano; primero las que están
            -- más lejos del destino (las de delante no tapan a las de atrás).
            table.sort(lista, function(a, b)
                return (a.x - x) ^ 2 + (a.y - y) ^ 2 > (b.x - x) ^ 2 + (b.y - y) ^ 2
            end)
            local libres = {}
            for k, h in ipairs(sitios) do
                libres[k] = h
            end
            for _, u in ipairs(lista) do
                local mejor, mejorD
                for k, h in ipairs(libres) do
                    local d = (h.x - u.x) ^ 2 + (h.y - u.y) ^ 2
                    if not mejorD or d < mejorD then
                        mejor, mejorD = k, d
                    end
                end
                huecos[u] = table.remove(libres, mejor)
            end
            fondo = fondo + filas * Ordenes.entreFilas[tipo] + 120
        end
    end
    return huecos
end

--- Punto del terreno (o del agua) bajo el píxel (sx, sy) con la `camara` de
-- la batalla, o nil si el rayo no toca el suelo. Usa su matriz de vista del
-- último cuadro (`Camara:matrices`).
function Ordenes.puntoEnPantalla(camara, suelo, sx, sy, ancho, alto, campo)
    local v = camara.vista
    if not v or not v[1] then
        return nil
    end
    local ex, ey, ez = camara:puntosVista()
    local nx = 2 * sx / ancho - 1
    local ny = 1 - 2 * sy / alto
    local t = math.tan(campo / 2)
    local asp = ancho / alto
    -- Filas de la vista: lado (en espejo), arriba y -adelante.
    local dx = nx * t * asp * v[1] + ny * t * v[5] - v[9]
    local dy = nx * t * asp * v[2] + ny * t * v[6] - v[10]
    local dz = nx * t * asp * v[3] + ny * t * v[7] - v[11]
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l, dy / l, dz / l
    local mar = suelo.nivelMar or -math.huge
    local function debajo(d)
        local x, y, z = ex + dx * d, ey + dy * d, ez + dz * d
        return z <= math.max(suelo:altura(x, y), mar)
    end
    local paso, lejos = 40, 60000
    local antes = 0
    local d = paso
    while d <= lejos do
        if debajo(d) then
            local a, b = antes, d
            for _ = 1, 12 do
                local m = (a + b) / 2
                if debajo(m) then
                    b = m
                else
                    a = m
                end
            end
            return ex + dx * b, ey + dy * b, ez + dz * b
        end
        antes = d
        paso = math.min(400, paso * 1.08)
        d = d + paso
    end
    return nil
end

return Ordenes

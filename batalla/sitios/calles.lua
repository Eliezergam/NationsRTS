-- Red de calles de una ciudad (el dueño, 19-nov: «diseña las calles muy bien
-- y proceduralmente, con ruido y lógica»).
--
-- Método de Citygen (Kelly y McCabe, «Citygen: An Interactive System for
-- Procedural City Generation», 2007) con las restricciones locales de
-- Parish y Müller («Procedural Modeling of Cities», SIGGRAPH 2001):
--   1. Avenidas (red primaria): del centro a cada portón del muro. Cada
--      tramo de 25 m prueba varias direcciones hacia su destino y se queda
--      con la de menos subida y bajada (más algo de ruido): siguen las curvas
--      de nivel como las carreteras de verdad. Luego se suavizan (Chaikin).
--   2. Ronda: un anillo por dentro del muro.
--   3. Calles (red secundaria): nacen de las avenidas y la ronda cada
--      70-110 m, en perpendicular, y crecen por tramos de 60-100 m con un
--      giro al azar de hasta 6°. Se paran al tocar otra calle (cruce en T),
--      se pegan a un cruce cercano (cruce en X), no se acercan en paralelo a
--      menos de 35 m de otra, evitan las cuestas de más del 12 % y echan
--      ramas en perpendicular al azar.
-- Medidas reales: carril de 3,5 m; avenida de 2 + 2 carriles (14 m) con
-- aceras de 3 m; ronda de 10 m; calle de 7 m con aceras de 2,2 m; bordillo
-- de 15 cm.
--
-- Todo en px de la batalla (10 px = 1 m).

local Calles = {}
Calles.__index = Calles

Calles.clases = {
    avenida = { calzada = 140, acera = 30, linea = true, orden = 1 },
    ronda = { calzada = 100, acera = 25, linea = true, orden = 2 },
    calle = { calzada = 70, acera = 22, linea = false, orden = 3 },
}
Calles.bordillo = 1.5 -- px (15 cm) que la acera queda sobre la calzada
Calles.pasoAvenida = 250 -- px por tramo al trazar una avenida
Calles.giroAvenida = math.rad(7) -- px entre las direcciones que prueba
Calles.separacion = 350 -- px: dos calles paralelas no se acercan más
Calles.pegar = 140 -- px: una calle que acaba cerca de un cruce se une a él
Calles.cuestaMaxima = 0.12
Calles.celda = 400 -- px de la rejilla de tramos

local function cruzar(ax, ay, bx, by, cx, cy, dx, dy)
    -- Intersección de los segmentos ab y cd: t en ab, u en cd, o nil.
    local rx, ry = bx - ax, by - ay
    local sx, sy = dx - cx, dy - cy
    local den = rx * sy - ry * sx
    if math.abs(den) < 1e-9 then
        return nil
    end
    local qx, qy = cx - ax, cy - ay
    local t = (qx * sy - qy * sx) / den
    local u = (qx * ry - qy * rx) / den
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
        return t, u
    end
    return nil
end

local function distSegmento(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2)) or 0
    local ex, ey = ax + dx * t - x, ay + dy * t - y
    return math.sqrt(ex * ex + ey * ey), t
end

function Calles.nueva(suelo, U, limites)
    local self = setmetatable({}, Calles)
    self.suelo = suelo
    self.U = U
    -- Rectángulo donde pueden ir las calles (dentro del muro).
    self.limites = limites
    self.nodos = {}
    self.aristas = {}
    self.rejilla = nil
    return self
end

-- Grafo ------------------------------------------------------------------------------------

function Calles:nodo(x, y)
    local n = { x = x, y = y, aristas = {} }
    self.nodos[#self.nodos + 1] = n
    return n
end

--- Arista de `a` a `b` por `puntos` ({ x1, y1, x2, y2, ... }, de a a b).
function Calles:arista(a, b, puntos, clase)
    local e = { a = a, b = b, puntos = puntos, clase = clase, datos = Calles.clases[clase] }
    self.aristas[#self.aristas + 1] = e
    a.aristas[#a.aristas + 1] = e
    b.aristas[#b.aristas + 1] = e
    self.rejilla = nil
    return e
end

local function quitar(lista, v)
    for k = #lista, 1, -1 do
        if lista[k] == v then
            table.remove(lista, k)
        end
    end
end

--- Parte la arista `e` en el punto (x, y) del tramo `k` (entre los puntos k
-- y k + 1) y devuelve el nodo nuevo.
function Calles:partir(e, k, x, y)
    local p = e.puntos
    local n = self:nodo(x, y)
    local p1, p2 = {}, {}
    for i = 1, k * 2 do
        p1[#p1 + 1] = p[i]
    end
    p1[#p1 + 1], p1[#p1 + 2] = x, y
    p2[1], p2[2] = x, y
    for i = k * 2 + 1, #p do
        p2[#p2 + 1] = p[i]
    end
    -- Sin puntos repetidos en la unión, pero cada calle con dos puntos como
    -- poco (cortada justo en su extremo se quedaba con uno y la malla de
    -- las calles fallaba: semilla 2026, el dueño, 20-nov).
    if #p1 >= 6 and math.abs(p1[#p1 - 3] - x) < 1 and math.abs(p1[#p1 - 2] - y) < 1 then
        table.remove(p1, #p1 - 2)
        table.remove(p1, #p1 - 2)
    end
    if #p2 >= 6 and math.abs(p2[3] - x) < 1 and math.abs(p2[4] - y) < 1 then
        table.remove(p2, 3)
        table.remove(p2, 3)
    end
    quitar(self.aristas, e)
    quitar(e.a.aristas, e)
    quitar(e.b.aristas, e)
    self:arista(e.a, n, p1, e.clase)
    self:arista(n, e.b, p2, e.clase)
    return n
end

--- Rejilla de tramos (para buscar cruces y distancias deprisa).
function Calles:tramos()
    if self.rejilla then
        return self.rejilla
    end
    local r = {}
    local c = Calles.celda
    for _, e in ipairs(self.aristas) do
        local p = e.puntos
        for k = 1, #p / 2 - 1 do
            local ax, ay, bx, by = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
            local t = { ax, ay, bx, by, e, k }
            for j = math.floor(math.min(ay, by) / c), math.floor(math.max(ay, by) / c) do
                for i = math.floor(math.min(ax, bx) / c), math.floor(math.max(ax, bx) / c) do
                    local clave = i * 131072 + j
                    local l = r[clave]
                    if not l then
                        l = {}
                        r[clave] = l
                    end
                    l[#l + 1] = t
                end
            end
        end
    end
    self.rejilla = r
    return r
end

--- Tramos en la caja (x0, y0)-(x1, y1), sin repetir.
function Calles:tramosEn(x0, y0, x1, y1)
    local r = self:tramos()
    local c = Calles.celda
    local vistos, salida = {}, {}
    for j = math.floor(y0 / c), math.floor(y1 / c) do
        for i = math.floor(x0 / c), math.floor(x1 / c) do
            for _, t in ipairs(r[i * 131072 + j] or {}) do
                if not vistos[t] then
                    vistos[t] = true
                    salida[#salida + 1] = t
                end
            end
        end
    end
    return salida
end

--- Primer cruce del segmento (ax, ay)-(bx, by) con la red: t, arista, tramo,
-- x, y. `ignorar`: arista que no cuenta (de la que sale).
function Calles:cruce(ax, ay, bx, by, ignorar, desdeT)
    local mejor
    for _, t in ipairs(self:tramosEn(math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by))) do
        if t[5] ~= ignorar then
            local s = cruzar(ax, ay, bx, by, t[1], t[2], t[3], t[4])
            if s and s > (desdeT or 0.001) and (not mejor or s < mejor[1]) then
                local u = select(2, cruzar(ax, ay, bx, by, t[1], t[2], t[3], t[4]))
                mejor = { s, t[5], t[6], t[1] + (t[3] - t[1]) * u, t[2] + (t[4] - t[2]) * u }
            end
        end
    end
    if mejor then
        return mejor[1], mejor[2], mejor[3], mejor[4], mejor[5]
    end
    return nil
end

--- Distancia de (x, y) a la red (px) y la arista más cercana, mirando hasta
-- `radio` px. `ignorar`: arista que no cuenta.
function Calles:distancia(x, y, radio, ignorar)
    local mejor, cual = math.huge, nil
    for _, t in ipairs(self:tramosEn(x - radio, y - radio, x + radio, y + radio)) do
        if t[5] ~= ignorar then
            local d = distSegmento(x, y, t[1], t[2], t[3], t[4])
            if d < mejor then
                mejor, cual = d, t[5]
            end
        end
    end
    return mejor, cual
end

--- ¿Cae (x, y) sobre una calle o su acera (más `margen` px)?
function Calles:sobre(x, y, margen)
    margen = margen or 0
    for _, n in ipairs(self.glorietas or {}) do
        local r = n.glorieta + 30 + margen
        if (x - n.x) ^ 2 + (y - n.y) ^ 2 < r * r then
            return true
        end
    end
    for _, t in ipairs(self:tramosEn(x - 260, y - 260, x + 260, y + 260)) do
        local d = t[5].datos
        if distSegmento(x, y, t[1], t[2], t[3], t[4]) < d.calzada / 2 + d.acera + margen then
            return true
        end
    end
    return false
end

function Calles:dentro(x, y, margen)
    local l = self.limites
    margen = margen or 0
    return x > l[1] + margen and x < l[3] - margen and y > l[2] + margen and y < l[4] - margen
end

-- Avenidas -----------------------------------------------------------------------------------

--- Puntos de una avenida de (ax, ay) a (bx, by) que sigue el terreno.
function Calles:trazar(ax, ay, bx, by)
    local s, U = self.suelo, self.U
    local paso = Calles.paso or Calles.pasoAvenida
    local pts = { ax, ay }
    local x, y = ax, ay
    for _ = 1, 400 do
        local dx, dy = bx - x, by - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= paso * 1.3 then
            break
        end
        local base = math.atan2(dy, dx)
        local h = s:altura(x, y)
        local mejor, mx, my = math.huge, nil, nil
        for k = -4, 4 do
            local a = base + k * Calles.giroAvenida
            local qx, qy = x + math.cos(a) * paso, y + math.sin(a) * paso
            local coste = math.abs(s:altura(qx, qy) - h) + math.abs(k) * paso * 0.012 + U() * paso * 0.02
            if coste < mejor then
                mejor, mx, my = coste, qx, qy
            end
        end
        x, y = mx, my
        pts[#pts + 1], pts[#pts + 2] = x, y
    end
    pts[#pts + 1], pts[#pts + 2] = bx, by
    return Calles.suavizar(pts, 2)
end

--- Chaikin: esquinas redondeadas, los extremos fijos (curvatura continua).
function Calles.suavizar(p, veces)
    for _ = 1, veces do
        if #p < 6 then
            return p
        end
        local q = { p[1], p[2] }
        for k = 1, #p / 2 - 1 do
            local ax, ay, bx, by = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
            if k > 1 then
                q[#q + 1], q[#q + 2] = ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25
            end
            if k < #p / 2 - 1 then
                q[#q + 1], q[#q + 2] = ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75
            end
        end
        q[#q + 1], q[#q + 2] = p[#p - 1], p[#p]
        p = q
    end
    return p
end

--- Mete en la red la vía de `puntos` (de `nodoA` a `nodoB`, o nodos nuevos)
-- partiendo las que cruza: cada cruce, un nodo compartido.
function Calles:insertar(puntos, clase, nodoA, nodoB)
    nodoA = nodoA or self:nodo(puntos[1], puntos[2])
    local actual, tramo = nodoA, { puntos[1], puntos[2] }
    for k = 1, #puntos / 2 - 1 do
        local ax, ay, bx, by = puntos[k * 2 - 1], puntos[k * 2], puntos[k * 2 + 1], puntos[k * 2 + 2]
        local desde = 0.001
        while true do
            local t, e, kt, x, y = self:cruce(ax, ay, bx, by, nil, desde)
            -- Los cruces junto a los extremos de la vía son sus propios nodos.
            if not t or (math.abs(x - puntos[1]) < 20 and math.abs(y - puntos[2]) < 20)
                or (math.abs(x - puntos[#puntos - 1]) < 20 and math.abs(y - puntos[#puntos]) < 20) then
                break
            end
            local n = self:partir(e, kt, x, y)
            tramo[#tramo + 1], tramo[#tramo + 2] = x, y
            self:arista(actual, n, tramo, clase)
            actual, tramo = n, { x, y }
            ax, ay = x, y
            desde = 0.01
        end
        tramo[#tramo + 1], tramo[#tramo + 2] = bx, by
    end
    nodoB = nodoB or self:nodo(puntos[#puntos - 1], puntos[#puntos])
    self:arista(actual, nodoB, tramo, clase)
    return nodoA, nodoB
end

-- Calles secundarias ---------------------------------------------------------------------------

--- Hace crecer una calle desde el nodo `n0` con rumbo `ang`; devuelve las
-- semillas de sus ramas.
function Calles:crecer(n0, ang, origen)
    local s, U = self.suelo, self.U
    local x, y = n0.x, n0.y
    local pts = { x, y }
    local ramas = {}
    local fin
    for paso = 1, 12 do
        local largo = U(600, 1000)
        local nuevoAng = ang + U(-1, 1) * math.rad(6)
        local bx, by = x + math.cos(nuevoAng) * largo, y + math.sin(nuevoAng) * largo
        -- Cuesta: probar a desviarse un poco antes de rendirse.
        local h0 = s:altura(x, y)
        if math.abs(s:altura(bx, by) - h0) / largo > Calles.cuestaMaxima then
            local ok = false
            for _, giro in ipairs({ math.rad(18), -math.rad(18) }) do
                local cx, cy = x + math.cos(nuevoAng + giro) * largo, y + math.sin(nuevoAng + giro) * largo
                if math.abs(s:altura(cx, cy) - h0) / largo <= Calles.cuestaMaxima then
                    bx, by, nuevoAng, ok = cx, cy, nuevoAng + giro, true
                    break
                end
            end
            if not ok then
                break
            end
        end
        ang = nuevoAng
        -- Choca con otra calle: cruce en T y fin.
        local t, e, kt, cx, cy = self:cruce(x, y, bx, by, paso == 1 and origen or nil, 0.02)
        if t then
            if t * largo < 120 then
                -- Demasiado cerca para un tramo nuevo: acaba aquí si hay algo.
                break
            end
            pts[#pts + 1], pts[#pts + 2] = cx, cy
            fin = self:partir(e, kt, cx, cy)
            break
        end
        -- Fuera del muro (por dentro de la ronda): fin sin salida.
        if not self:dentro(bx, by, 200) then
            break
        end
        -- No correr en paralelo pegada a otra.
        local mx, my = (x + bx) / 2, (y + by) / 2
        if self:distancia(mx, my, Calles.separacion, paso == 1 and origen or nil) < Calles.separacion
            or self:distancia(bx, by, Calles.separacion) < Calles.separacion * 0.8 then
            -- Si hay un cruce cerca del final, se une a él.
            local mejor, md = nil, Calles.pegar
            for _, n in ipairs(self.nodos) do
                local d = math.sqrt((n.x - bx) ^ 2 + (n.y - by) ^ 2)
                if d < md and n ~= n0 then
                    mejor, md = n, d
                end
            end
            if mejor and not self:cruce(x, y, mejor.x, mejor.y, nil, 0.05) then
                pts[#pts + 1], pts[#pts + 2] = mejor.x, mejor.y
                fin = mejor
            end
            break
        end
        pts[#pts + 1], pts[#pts + 2] = bx, by
        x, y = bx, by
        -- Ramas a los lados.
        for _, lado in ipairs({ 1, -1 }) do
            if U() < 0.45 then
                ramas[#ramas + 1] = { x = x, y = y, ang = ang + lado * math.pi / 2 + U(-1, 1) * math.rad(4) }
            end
        end
    end
    if #pts < 4 then
        return {}
    end
    fin = fin or self:nodo(pts[#pts - 1], pts[#pts])
    local e = self:arista(n0, fin, pts, 'calle')
    for _, r in ipairs(ramas) do
        r.arista = e
    end
    return ramas
end

--- Nodo en el punto (x, y) de la arista `e` (partiéndola), o el que ya hay.
function Calles:nodoEn(e, x, y)
    for _, n in ipairs({ e.a, e.b }) do
        if math.abs(n.x - x) < 2 and math.abs(n.y - y) < 2 then
            return n
        end
    end
    -- La arista pudo partirse después: buscar la que pasa por el punto.
    local mejor, cual, k = math.huge, nil, nil
    for _, t in ipairs(self:tramosEn(x - 5, y - 5, x + 5, y + 5)) do
        local d = distSegmento(x, y, t[1], t[2], t[3], t[4])
        if d < mejor then
            mejor, cual, k = d, t[5], t[6]
        end
    end
    if not cual or mejor > 3 then
        return nil
    end
    for _, n in ipairs({ cual.a, cual.b }) do
        if math.abs(n.x - x) < 2 and math.abs(n.y - y) < 2 then
            return n
        end
    end
    return self:partir(cual, k, x, y), cual
end

--- Siembra calles a los dos lados de las aristas de `clases` cada 70-110 m
-- y las hace crecer (con sus ramas) hasta `maximo` calles.
function Calles:sembrar(maximo)
    local U = self.U
    local cola = {}
    for _, e in ipairs(self.aristas) do
        if e.clase ~= 'calle' then
            local p = e.puntos
            local acumulado, siguiente = 0, U(500, 900)
            for k = 1, #p / 2 - 1 do
                local ax, ay, bx, by = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
                local l = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
                while acumulado + l >= siguiente do
                    local t = (siguiente - acumulado) / l
                    local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                    local a = math.atan2(by - ay, bx - ax)
                    for _, lado in ipairs({ 1, -1 }) do
                        if U() < 0.85 then
                            cola[#cola + 1] = { x = x, y = y, ang = a + lado * math.pi / 2 + U(-1, 1) * math.rad(5), arista = e }
                        end
                    end
                    siguiente = siguiente + U(700, 1100)
                end
                acumulado = acumulado + l
            end
        end
    end
    local hechas = 0
    local k = 1
    while k <= #cola and hechas < maximo do
        local semilla = cola[k]
        k = k + 1
        -- Lejos de otras calles que salgan del mismo sitio.
        local d = self:distancia(semilla.x + math.cos(semilla.ang) * 200, semilla.y + math.sin(semilla.ang) * 200, 300)
        if d > 150 and self:dentro(semilla.x, semilla.y, 250) then
            local n0, de = self:nodoEn(semilla.arista, semilla.x, semilla.y)
            if n0 then
                local ramas = self:crecer(n0, semilla.ang, de or semilla.arista)
                if #ramas > 0 then
                    hechas = hechas + 1
                end
                for _, r in ipairs(ramas) do
                    cola[#cola + 1] = r
                end
            end
        end
    end
    -- Calles sin salida de menos de 40 m (muñones que dejan los cruces), fuera.
    local quitadas = true
    while quitadas do
        quitadas = false
        for k = #self.aristas, 1, -1 do
            local e = self.aristas[k]
            if e.clase == 'calle' and (#e.a.aristas == 1 or #e.b.aristas == 1) and Calles.largo(e) < 400 then
                table.remove(self.aristas, k)
                quitar(e.a.aristas, e)
                quitar(e.b.aristas, e)
                quitadas = true
            end
        end
    end
    self.rejilla = nil
    -- Nodos sueltos (sin aristas tras partir y recortar), fuera.
    local vivos = {}
    for _, n in ipairs(self.nodos) do
        if #n.aristas > 0 then
            vivos[#vivos + 1] = n
        end
    end
    self.nodos = vivos
end

-- Alturas y explanadas -------------------------------------------------------------------------

--- Largo de la polilínea y el punto, rumbo y altura a la distancia `s`.
function Calles.punto(e, s)
    local p = e.puntos
    local acumulado = 0
    for k = 1, #p / 2 - 1 do
        local ax, ay, bx, by = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
        local l = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        if acumulado + l >= s or k == #p / 2 - 1 then
            local t = l > 0 and math.max(0, math.min(1, (s - acumulado) / l)) or 0
            return ax + (bx - ax) * t, ay + (by - ay) * t, math.atan2(by - ay, bx - ax)
        end
        acumulado = acumulado + l
    end
    return p[1], p[2], 0
end

function Calles.largo(e)
    local p, l = e.puntos, 0
    for k = 1, #p / 2 - 1 do
        l = l + math.sqrt((p[k * 2 + 1] - p[k * 2 - 1]) ^ 2 + (p[k * 2 + 2] - p[k * 2]) ^ 2)
    end
    return l
end

--- Perfil de cada arista: alturas cada 10 m, suavizadas, con los extremos
-- en la altura de su cruce; y explanada de la calzada y las aceras.
function Calles:nivelar()
    local s = self.suelo
    for _, n in ipairs(self.nodos) do
        local suma = 0
        for k = 0, 7 do
            local a = k / 8 * 2 * math.pi
            suma = suma + s:altura(n.x + math.cos(a) * 60, n.y + math.sin(a) * 60)
        end
        n.z = suma / 8
        n.radio = #n.aristas > 1 and require('batalla.dream.calles_malla').radioCruce(n) or 0
        -- Donde llegan 5 calles o más, glorieta (como en las ciudades de verdad).
        if #n.aristas >= 5 then
            n.glorieta = math.max(n.radio, 380)
            self.glorietas = self.glorietas or {}
            self.glorietas[#self.glorietas + 1] = n
            n.radio = n.glorieta
        end
    end
    -- Por orden: avenidas, ronda y calles (lo explanado antes manda).
    table.sort(self.aristas, function(a, b)
        if a.datos.orden ~= b.datos.orden then
            return a.datos.orden < b.datos.orden
        end
        return Calles.largo(a) > Calles.largo(b)
    end)
    for _, e in ipairs(self.aristas) do
        local largo = Calles.largo(e)
        e.largo = largo
        local n = math.max(2, math.ceil(largo / 100))
        local z = {}
        for i = 0, n do
            local x, y = Calles.punto(e, largo * i / n)
            z[i] = s:altura(x, y)
        end
        -- Media móvil de ±3 muestras (±30 m), dos veces.
        for _ = 1, 2 do
            local w = {}
            for i = 0, n do
                local suma, c = 0, 0
                for j = math.max(0, i - 3), math.min(n, i + 3) do
                    suma, c = suma + z[j], c + 1
                end
                w[i] = suma / c
            end
            z = w
        end
        -- Los extremos, a la altura de su cruce (fundido en 30 m).
        local da, db = e.a.z - z[0], e.b.z - z[n]
        for i = 0, n do
            local si = largo * i / n
            local fa = math.max(0, math.min(1, 1 - (si - e.a.radio) / 300))
            local fb = math.max(0, math.min(1, 1 - (largo - si - e.b.radio) / 300))
            local f = math.max(1, fa + fb)
            fa, fb = fa / f, fb / f
            z[i] = z[i] * (1 - fa - fb) + e.a.z * fa + e.b.z * fb
        end
        e.perfil, e.muestras = z, n
        local medio = e.datos.calzada / 2 + e.datos.acera + 15
        for i = 0, n - 1 do
            local x0, y0 = Calles.punto(e, largo * i / n)
            local x1, y1 = Calles.punto(e, largo * (i + 1) / n)
            s:explanarTramo(x0, y0, z[i], x1, y1, z[i + 1], medio, 160)
        end
    end
    for _, n in ipairs(self.nodos) do
        if #n.aristas > 1 then
            local r = n.radio
            s:explanarCaja(n.x, n.y, r + 30, r + 30, 0, n.z, 160)
            -- Nada del terreno asoma por encima del asfalto del cruce (la
            -- rejilla es de 4-10 m: la isleta de la glorieta lleva su propio césped).
            local ph = s.relieve.h
            local rr = r + 30
            s:vertices(n.x - rr, n.y - rr, n.x + rr, n.y + rr, function(k, x, y)
                local d2 = (x - n.x) ^ 2 + (y - n.y) ^ 2
                if d2 < rr * rr then
                    ph[k] = math.min(ph[k], n.z - 0.5)
                end
            end)
        elseif #n.aristas == 1 then
            -- Calle sin salida: explanada para el remate redondo.
            local e = n.aristas[1]
            local r = e.datos.calzada / 2 + e.datos.acera + 20
            local ph = s.relieve.h
            s:vertices(n.x - r, n.y - r, n.x + r, n.y + r, function(k, x, y)
                if (x - n.x) ^ 2 + (y - n.y) ^ 2 < r * r then
                    ph[k] = math.min(ph[k], n.z - 0.5)
                end
            end)
        end
    end
    -- El terreno, siempre por debajo de la calzada y las aceras (aunque
    -- antes lo hubiera explanado otra cosa, como una ruta de avance).
    local ph = s.relieve.h
    for _, e in ipairs(self.aristas) do
        local medio = e.datos.calzada / 2 + e.datos.acera + 5
        local p = e.puntos
        local acumulado = 0
        for k = 1, #p / 2 - 1 do
            local ax, ay, bx, by = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
            local l = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
            s:vertices(math.min(ax, bx) - medio, math.min(ay, by) - medio, math.max(ax, bx) + medio, math.max(ay, by) + medio, function(kv, x, y)
                local d, tt = distSegmento(x, y, ax, ay, bx, by)
                if d < medio then
                    local z = Calles.alturaEn(e, acumulado + tt * l) - 0.5
                    if ph[kv] > z then
                        ph[kv] = z
                    end
                end
            end)
            acumulado = acumulado + l
        end
    end
end

--- Altura de la calzada de `e` a la distancia `s` de su principio.
function Calles.alturaEn(e, s)
    local n = e.muestras
    local f = math.max(0, math.min(n, s / e.largo * n))
    local i = math.min(n - 1, math.floor(f))
    local t = f - i
    return e.perfil[i] * (1 - t) + e.perfil[i + 1] * t
end

return Calles

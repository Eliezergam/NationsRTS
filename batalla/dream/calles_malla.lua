-- Mallas de las calles de una ciudad (batalla/sitios/calles.lua): calzada de
-- asfalto con sus líneas pintadas, bordillo de 15 cm, acera de adoquín y un
-- faldón por fuera para que no se vea el hueco con el terreno.
--
-- Cada arista se recorta en sus cruces; el cruce se rellena de asfalto y sus
-- esquinas de acera se redondean con una curva (Bézier cuadrática entre los
-- bordillos de las dos calles, con el punto de control donde se cortarían
-- sus líneas), como las esquinas reales.
--
-- Texturas: asfalto y adoquín de Poly Haven (CC0; assets/base/materiales/
-- baseAsfalto y baseAcera), el bordillo de hormigón del kit.

local Calles = require('batalla.sitios.calles')

local CallesMalla = {}

CallesMalla.paso = 40 -- px entre secciones a lo largo de la calle (4 m)
CallesMalla.trozo = 1280 -- px de los trozos (para no dibujar lo que no se ve)
CallesMalla.repeticion = { kitAsfalto = 4, kitAcera = 2, kitBordillo = 1, kitLinea = 4, kitCesped = 6 }
CallesMalla.puntosEsquina = 8

local function nuevoTrozo(trozos, x, y)
    local t = CallesMalla.trozo
    local i, j = math.floor(x / t), math.floor(y / t)
    local k = i * 131072 + j
    local tr = trozos[k]
    if not tr then
        tr = { x0 = i * t, y0 = j * t, x1 = (i + 1) * t, y1 = (j + 1) * t, z = math.huge, datos = {} }
        trozos[k] = tr
    end
    return tr
end

--- Triángulo (vértices { x, y, z px, u, v m }) con la normal pedida; se
-- da la vuelta si hace falta para que su cara mire hacia ella.
local function triangulo(datos, a, b, c, nx, ny, nz, tx, ty, tz)
    local ax, ay, az = a[1] * 0.1, a[3] * 0.1, a[2] * 0.1
    local bx, by, bz = b[1] * 0.1, b[3] * 0.1, b[2] * 0.1
    local cx, cy, cz = c[1] * 0.1, c[3] * 0.1, c[2] * 0.1
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local vx, vy, vz = cx - ax, cy - ay, cz - az
    local gx, gy, gz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if gx * nx + gy * ny + gz * nz < 0 then
        b, c = c, b
    end
    for _, v in ipairs({ a, b, c }) do
        local n = #datos
        datos[n + 1], datos[n + 2], datos[n + 3] = v[1] * 0.1, v[3] * 0.1, v[2] * 0.1
        datos[n + 4], datos[n + 5], datos[n + 6] = nx, ny, nz
        datos[n + 7], datos[n + 8] = v[4], v[5]
        datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = tx, ty, tz, 1
    end
end

--- Cuadrilátero a-b-c-d (en orden alrededor) con su normal (en ejes de Dream:
-- x, arriba, y del juego).
local function cuadro(datos, a, b, c, d, nx, ny, nz, tx, ty, tz)
    triangulo(datos, a, b, c, nx, ny, nz, tx, ty, tz)
    triangulo(datos, a, c, d, nx, ny, nz, tx, ty, tz)
end

local function lista(tr, material)
    local l = tr.datos[material]
    if not l then
        l = {}
        tr.datos[material] = l
    end
    return l
end

-- Rumbo con el que la arista `e` sale del nodo `n`.
local function salida(e, n)
    local p = e.puntos
    if e.a == n then
        return math.atan2(p[4] - p[2], p[3] - p[1])
    end
    return math.atan2(p[#p - 2] - p[#p], p[#p - 3] - p[#p - 1])
end

-- Radio de un cruce: lo que ocupa la calle más ancha que llega a él, y más
-- si dos calles llegan con poco ángulo entre ellas (sus aceras no se pisan:
-- a la distancia r, el hueco entre ejes, r·sen(θ), cabe media calle de cada una).
local function radioCruce(n)
    local r = 0
    local lista = {}
    for _, e in ipairs(n.aristas) do
        local w = e.datos.calzada / 2 + e.datos.acera
        r = math.max(r, w)
        lista[#lista + 1] = { salida(e, n), w }
    end
    table.sort(lista, function(a, b)
        return a[1] < b[1]
    end)
    for i, a in ipairs(lista) do
        local b = lista[i % #lista + 1]
        local th = b[1] - a[1]
        if i == #lista then
            th = th + 2 * math.pi
        end
        if th > 0.05 and th < math.pi * 0.9 then
            r = math.max(r, math.min(600, (a[2] + b[2]) / math.sin(math.min(th, math.pi / 2)) * 0.75))
        end
    end
    return r + 20
end
CallesMalla.radioCruce = radioCruce

--- Secciones de una arista recortada: { x, y, z, nx, ny, s } cada `paso`.
local function secciones(e, s0, s1)
    local lista0 = {}
    local n = math.max(1, math.ceil((s1 - s0) / CallesMalla.paso))
    for i = 0, n do
        local s = s0 + (s1 - s0) * i / n
        local x, y = Calles.punto(e, s)
        -- Rumbo por diferencia central (suave en las curvas).
        local xa, ya = Calles.punto(e, math.max(0, s - 20))
        local xb, yb = Calles.punto(e, math.min(e.largo, s + 20))
        local dx, dy = xb - xa, yb - ya
        local l = math.sqrt(dx * dx + dy * dy)
        if l < 1e-6 then
            dx, dy, l = 1, 0, 1
        end
        lista0[#lista0 + 1] = { x = x, y = y, z = Calles.alturaEn(e, s) + 0.3, nx = -dy / l, ny = dx / l, s = s }
    end
    return lista0
end

--- Franja a lo largo de las secciones entre las distancias laterales `a` y
-- `b` (px, positivas a la izquierda) a la altura `dz` sobre la calzada.
local function franja(datos, secs, a, b, dz, repeticion)
    for i = 1, #secs - 1 do
        local p, q = secs[i], secs[i + 1]
        local m = 10 * repeticion
        local A = { p.x + p.nx * a, p.y + p.ny * a, p.z + dz, a / m, -p.s / m }
        local B = { p.x + p.nx * b, p.y + p.ny * b, p.z + dz, b / m, -p.s / m }
        local C = { q.x + q.nx * b, q.y + q.ny * b, q.z + dz, b / m, -q.s / m }
        local D = { q.x + q.nx * a, q.y + q.ny * a, q.z + dz, a / m, -q.s / m }
        cuadro(datos, A, B, C, D, 0, 1, 0, p.nx, 0, p.ny)
    end
end

--- Pared a lo largo de las secciones a la distancia lateral `a`, de dz0 a
-- dz1, mirando hacia `lado` (+1 a la izquierda).
local function pared(datos, secs, a, dz0, dz1, lado, repeticion)
    local m = 10 * repeticion
    for i = 1, #secs - 1 do
        local p, q = secs[i], secs[i + 1]
        local A = { p.x + p.nx * a, p.y + p.ny * a, p.z + dz0, p.s / m, dz0 / m }
        local B = { q.x + q.nx * a, q.y + q.ny * a, q.z + dz0, q.s / m, dz0 / m }
        local C = { q.x + q.nx * a, q.y + q.ny * a, q.z + dz1, q.s / m, dz1 / m }
        local D = { p.x + p.nx * a, p.y + p.ny * a, p.z + dz1, p.s / m, dz1 / m }
        local dx, dy = q.x - p.x, q.y - p.y
        local l = math.sqrt(dx * dx + dy * dy)
        cuadro(datos, A, B, C, D, p.nx * lado, 0, p.ny * lado, dx / l, 0, dy / l)
    end
end

--- Líneas pintadas: discontinua (trazo de 3 m cada 9 m) en el carril o
-- continua, de 15 cm, a la distancia lateral `a`.
local function linea(datos, secs, a, discontinua)
    for i = 1, #secs - 1 do
        local p, q = secs[i], secs[i + 1]
        local pinta = true
        if discontinua then
            pinta = (p.s % 90) < 30
        end
        if pinta then
            local w = 0.75
            local A = { p.x + p.nx * (a - w), p.y + p.ny * (a - w), p.z + 0.15, 0, 0 }
            local B = { p.x + p.nx * (a + w), p.y + p.ny * (a + w), p.z + 0.15, 0.1, 0 }
            local C = { q.x + q.nx * (a + w), q.y + q.ny * (a + w), q.z + 0.15, 0.1, 1 }
            local D = { q.x + q.nx * (a - w), q.y + q.ny * (a - w), q.z + 0.15, 0, 1 }
            cuadro(datos, A, B, C, D, 0, 1, 0, p.nx, 0, p.ny)
        end
    end
end

local function bezier(a, c, b, t)
    local u = 1 - t
    return a[1] * u * u + c[1] * 2 * u * t + b[1] * t * t, a[2] * u * u + c[2] * 2 * u * t + b[2] * t * t
end

-- Punto donde se cortan las rectas p + t·d y q + s·e (o nil si son paralelas).
local function corte(px, py, dx, dy, qx, qy, ex, ey)
    local den = dx * ey - dy * ex
    if math.abs(den) < 1e-4 then
        return nil
    end
    local t = ((qx - px) * ey - (qy - py) * ex) / den
    return px + dx * t, py + dy * t
end

--- Calzada, bordillos, aceras, faldón y líneas de un tramo de calle.
function CallesMalla.tramo(tr, e, secs, hw, ac)
    local B = Calles.bordillo
    franja(lista(tr, 'kitAsfalto'), secs, -hw, hw, 0, CallesMalla.repeticion.kitAsfalto)
    for _, lado in ipairs({ 1, -1 }) do
        -- Bordillo (cara y canto de 15 cm), acera y faldón.
        pared(lista(tr, 'kitBordillo'), secs, lado * hw, -0.5, B, -lado, 1)
        franja(lista(tr, 'kitBordillo'), secs, lado * hw, lado * (hw + 1.5), B, 1)
        franja(lista(tr, 'kitAcera'), secs, lado * (hw + 1.5), lado * (hw + ac), B, CallesMalla.repeticion.kitAcera)
        pared(lista(tr, 'kitBordillo'), secs, lado * (hw + ac), -6, B, lado, 1)
    end
    -- Líneas: avenida, doble continua en el centro y discontinuas entre
    -- carriles; ronda, discontinua en el centro.
    if e.clase == 'avenida' then
        linea(lista(tr, 'kitLinea'), secs, -2, false)
        linea(lista(tr, 'kitLinea'), secs, 2, false)
        linea(lista(tr, 'kitLinea'), secs, -35, true)
        linea(lista(tr, 'kitLinea'), secs, 35, true)
    elseif e.clase == 'ronda' then
        linea(lista(tr, 'kitLinea'), secs, 0, true)
    end
end

--- Glorieta en el nodo `n`: anillo de asfalto de radio `n.glorieta`, isleta
-- central con bordillo y aceras en arco entre las calles que salen.
function CallesMalla.glorieta(tr, n, ends, R, sinIsla)
    local B = Calles.bordillo
    R = R or n.glorieta
    local Ri = sinIsla and 0 or R * 0.45
    local z = n.z + 0.3
    tr.z = math.min(tr.z, z)
    local k = 64
    local asfalto, acera, bordillo = lista(tr, 'kitAsfalto'), lista(tr, 'kitAcera'), lista(tr, 'kitBordillo')
    local ma, mc = 10 * CallesMalla.repeticion.kitAsfalto, 10 * CallesMalla.repeticion.kitAcera
    local function p(r, a, dz, m)
        local x, y = n.x + math.cos(a) * r, n.y + math.sin(a) * r
        return { x, y, z + dz, x / m, y / m }
    end
    for i = 0, k - 1 do
        local a0, a1 = i / k * 2 * math.pi, (i + 1) / k * 2 * math.pi
        -- Anillo de asfalto (un poco más allá de R, bajo las aceras).
        cuadro(asfalto, p(Ri, a0, 0, ma), p(R + 10, a0, 0, ma), p(R + 10, a1, 0, ma), p(Ri, a1, 0, ma), 0, 1, 0, 1, 0, 0)
        -- Isleta: césped (leafy_grass de Poly Haven) y bordillo mirando al anillo.
        local am = (a0 + a1) / 2
        local l = Ri * (a1 - a0) / 10
        if not sinIsla then
            local mg = 10 * CallesMalla.repeticion.kitCesped
            triangulo(lista(tr, 'kitCesped'), { n.x, n.y, z + B + 2, n.x / mg, n.y / mg }, p(Ri - 3, a0, B, mg), p(Ri - 3, a1, B, mg), 0, 1, 0, 1, 0, 0)
            -- Canto de 30 cm del bordillo y su cara.
            cuadro(bordillo, p(Ri - 3, a0, B, 1), p(Ri, a0, B, 1), p(Ri, a1, B, 1), p(Ri - 3, a1, B, 1), 0, 1, 0, 1, 0, 0)
            cuadro(bordillo,
                { n.x + math.cos(a0) * Ri, n.y + math.sin(a0) * Ri, z - 0.5, 0, 0 },
                { n.x + math.cos(a1) * Ri, n.y + math.sin(a1) * Ri, z - 0.5, l, 0 },
                { n.x + math.cos(a1) * Ri, n.y + math.sin(a1) * Ri, z + B, l, 0.15 },
                { n.x + math.cos(a0) * Ri, n.y + math.sin(a0) * Ri, z + B, 0, 0.15 },
                math.cos(am), 0, math.sin(am), -math.sin(am), 0, math.cos(am))
        end
    end
    -- Aceras en arco entre cada par de calles vecinas.
    for _, x in ipairs(ends) do
        x.ang = math.atan2(x.dy, x.dx)
        x.media = math.asin(math.min(1, (x.hw + 4) / R))
    end
    table.sort(ends, function(a, b)
        return a.ang < b.ang
    end)
    for i, a in ipairs(ends) do
        local b = ends[i % #ends + 1]
        local a0 = a.ang + a.media
        local a1 = b.ang - b.media
        if i == #ends then
            a1 = a1 + 2 * math.pi
        end
        local ac = math.min(a.ac, b.ac)
        if a1 - a0 > 0.02 then
            local m = math.max(2, math.ceil((a1 - a0) / (2 * math.pi) * k))
            for j = 0, m - 1 do
                local t0, t1 = a0 + (a1 - a0) * j / m, a0 + (a1 - a0) * (j + 1) / m
                cuadro(acera, p(R, t0, B, mc), p(R + ac, t0, B, mc), p(R + ac, t1, B, mc), p(R, t1, B, mc), 0, 1, 0, 1, 0, 0)
                local am = (t0 + t1) / 2
                local l = R * (t1 - t0) / 10
                local q0, q1 = p(R, t0, 0, 1), p(R, t1, 0, 1)
                cuadro(bordillo,
                    { q0[1], q0[2], z - 0.5, 0, 0 }, { q1[1], q1[2], z - 0.5, l, 0 },
                    { q1[1], q1[2], z + B, l, 0.15 }, { q0[1], q0[2], z + B, 0, 0.15 },
                    -math.cos(am), 0, -math.sin(am), -math.sin(am), 0, math.cos(am))
                local o0, o1 = p(R + ac, t0, 0, 1), p(R + ac, t1, 0, 1)
                cuadro(bordillo,
                    { o0[1], o0[2], z - 6, 0, 0 }, { o1[1], o1[2], z - 6, l, 0 },
                    { o1[1], o1[2], z + B, l, 0.75 }, { o0[1], o0[2], z + B, 0, 0.75 },
                    math.cos(am), 0, math.sin(am), -math.sin(am), 0, math.cos(am))
            end
        end
    end
end

--- Mallas de las calles de `vias` agrupadas en trozos: { { x0, y0, x1, y1,
-- z, porMaterial = { material = datos } }, ... }.
function CallesMalla.hacer(vias)
    local trozos = {}
    local B = Calles.bordillo
    -- Recorte de cada arista en sus cruces.
    local radio = {}
    for _, n in ipairs(vias.nodos) do
        radio[n] = n.radio or (#n.aristas > 1 and radioCruce(n) or 0)
        if n.glorieta then
            -- La calle entra un poco en el anillo (sin rendija con el círculo).
            radio[n] = n.glorieta - 15
        end
    end
    local extremos = {}
    for _, e in ipairs(vias.aristas) do
        local d = e.datos
        local hw, ac = d.calzada / 2, d.acera
        local s0, s1 = radio[e.a], e.largo - radio[e.b]
        if s1 - s0 > 10 then
            local secs = secciones(e, s0, s1)
            -- Por tramos, cada uno en el trozo donde cae (si no, una calle
            -- larga desaparece entera al no verse el trozo de su punto medio).
            local T = CallesMalla.trozo
            local inicio = 1
            while inicio < #secs do
                local a = secs[inicio]
                local clave = math.floor((a.x + secs[inicio + 1].x) / 2 / T) * 131072 + math.floor((a.y + secs[inicio + 1].y) / 2 / T)
                local fin = inicio + 1
                while fin < #secs do
                    local b, c = secs[fin], secs[fin + 1]
                    if math.floor((b.x + c.x) / 2 / T) * 131072 + math.floor((b.y + c.y) / 2 / T) ~= clave then
                        break
                    end
                    fin = fin + 1
                end
                local run = {}
                for k = inicio, fin do
                    run[#run + 1] = secs[k]
                end
                local tr = nuevoTrozo(trozos, (run[1].x + run[2].x) / 2, (run[1].y + run[2].y) / 2)
                for _, sc in ipairs(run) do
                    tr.z = math.min(tr.z, sc.z)
                end
                CallesMalla.tramo(tr, e, run, hw, ac)
                inicio = fin
            end
            -- Los dos extremos, para los cruces.
            local pa, pb = secs[1], secs[#secs]
            extremos[#extremos + 1] = { nodo = e.a, x = pa.x, y = pa.y, z = pa.z, dx = pa.ny, dy = -pa.nx, hw = hw, ac = ac }
            extremos[#extremos + 1] = { nodo = e.b, x = pb.x, y = pb.y, z = pb.z, dx = -pb.ny, dy = pb.nx, hw = hw, ac = ac }
        end
    end
    -- Cruces: (dx, dy) es la dirección que sale del cruce por la calle.
    local porNodo = {}
    for _, x in ipairs(extremos) do
        local l = porNodo[x.nodo]
        if not l then
            l = {}
            porNodo[x.nodo] = l
        end
        l[#l + 1] = x
    end
    for n, ends in pairs(porNodo) do
        if n.glorieta then
            CallesMalla.glorieta(nuevoTrozo(trozos, n.x, n.y), n, ends)
        elseif #n.aristas == 1 and #ends == 1 and vias:dentro(n.x, n.y, 100) then
            -- Calle sin salida: remate redondo (como un fondo de saco).
            local x = ends[1]
            CallesMalla.glorieta(nuevoTrozo(trozos, n.x, n.y), n, ends, x.hw, true)
        elseif #ends >= 2 then
            local tr = nuevoTrozo(trozos, n.x, n.y)
            local zc = 0
            for _, x in ipairs(ends) do
                -- La izquierda mirando hacia fuera del cruce.
                x.lx, x.ly = -x.dy, x.dx
                x.ang = math.atan2(x.dy, x.dx)
                zc = zc + x.z
            end
            zc = zc / #ends
            tr.z = math.min(tr.z, zc)
            table.sort(ends, function(a, b)
                return a.ang < b.ang
            end)
            local asfalto = lista(tr, 'kitAsfalto')
            local poligono = {}
            for i, a in ipairs(ends) do
                local b = ends[i % #ends + 1]
                -- Bordillo de a (su izquierda) a b (su derecha).
                local L = { a.x + a.lx * a.hw, a.y + a.ly * a.hw }
                local R = { b.x - b.lx * b.hw, b.y - b.ly * b.hw }
                local Lo = { a.x + a.lx * (a.hw + a.ac), a.y + a.ly * (a.hw + a.ac) }
                local Ro = { b.x - b.lx * (b.hw + b.ac), b.y - b.ly * (b.hw + b.ac) }
                local cx, cy = corte(L[1], L[2], a.dx, a.dy, R[1], R[2], b.dx, b.dy)
                local ox, oy = corte(Lo[1], Lo[2], a.dx, a.dy, Ro[1], Ro[2], b.dx, b.dy)
                -- Paralelas o el corte muy lejos: control en el punto medio.
                if not cx or (cx - n.x) ^ 2 + (cy - n.y) ^ 2 > (4 * radio[n]) ^ 2 then
                    cx, cy = (L[1] + R[1]) / 2, (L[2] + R[2]) / 2
                end
                if not ox or (ox - n.x) ^ 2 + (oy - n.y) ^ 2 > (5 * radio[n]) ^ 2 then
                    ox, oy = (Lo[1] + Ro[1]) / 2, (Lo[2] + Ro[2]) / 2
                end
                local k = CallesMalla.puntosEsquina
                local curva, fuera = {}, {}
                for j = 0, k do
                    local t = j / k
                    local z = a.z * (1 - t) + b.z * t
                    local x, y = bezier(L, { cx, cy }, R, t)
                    local xo, yo = bezier(Lo, { ox, oy }, Ro, t)
                    curva[j] = { x, y, z }
                    fuera[j] = { xo, yo, z }
                end
                -- Polígono del asfalto: la derecha de a, su izquierda y la curva.
                poligono[#poligono + 1] = { a.x - a.lx * a.hw, a.y - a.ly * a.hw, a.z }
                for j = 0, k do
                    poligono[#poligono + 1] = curva[j]
                end
                -- Acera, bordillo y faldón de la esquina.
                local acera, bordillo = lista(tr, 'kitAcera'), lista(tr, 'kitBordillo')
                for j = 0, k - 1 do
                    local p, q = curva[j], curva[j + 1]
                    local po, qo = fuera[j], fuera[j + 1]
                    local m = 10 * CallesMalla.repeticion.kitAcera
                    cuadro(acera,
                        { p[1], p[2], p[3] + B, p[1] / m, p[2] / m },
                        { q[1], q[2], q[3] + B, q[1] / m, q[2] / m },
                        { qo[1], qo[2], qo[3] + B, qo[1] / m, qo[2] / m },
                        { po[1], po[2], po[3] + B, po[1] / m, po[2] / m },
                        0, 1, 0, 1, 0, 0)
                    -- Cara del bordillo, hacia el cruce.
                    local dx, dy = q[1] - p[1], q[2] - p[2]
                    local l = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
                    local hx, hy = n.x - (p[1] + q[1]) / 2, n.y - (p[2] + q[2]) / 2
                    local sgn = (-dy * hx + dx * hy) > 0 and 1 or -1
                    local fx, fy = -dy / l * sgn, dx / l * sgn
                    cuadro(bordillo,
                        { p[1], p[2], p[3] - 0.5, 0, 0 },
                        { q[1], q[2], q[3] - 0.5, l / 10, 0 },
                        { q[1], q[2], q[3] + B, l / 10, 0.15 },
                        { p[1], p[2], p[3] + B, 0, 0.15 },
                        fx, 0, fy, dx / l, 0, dy / l)
                    -- Faldón por fuera.
                    local ex, ey = qo[1] - po[1], qo[2] - po[2]
                    local lo = math.max(1e-6, math.sqrt(ex * ex + ey * ey))
                    cuadro(bordillo,
                        { po[1], po[2], po[3] - 6, 0, 0 },
                        { qo[1], qo[2], qo[3] - 6, lo / 10, 0 },
                        { qo[1], qo[2], qo[3] + B, lo / 10, 0.75 },
                        { po[1], po[2], po[3] + B, 0, 0.75 },
                        -fx, 0, -fy, ex / lo, 0, ey / lo)
                end
            end
            if os.getenv('PLANO_DEPURAR') and #n.aristas >= 5 then
                print(string.format('CRUCE %.0f,%.0f aristas %d extremos %d radio %.0f zc %.1f nz %.1f poligono %d', n.x, n.y, #n.aristas, #ends, radio[n], zc, n.z or -1, #poligono))
            end
            -- Asfalto del cruce: abanico desde el centro.
            local m = 10 * CallesMalla.repeticion.kitAsfalto
            local centro = { n.x, n.y, (n.z or zc) + 0.3, n.x / m, n.y / m }
            for i = 1, #poligono do
                local p, q = poligono[i], poligono[i % #poligono + 1]
                triangulo(asfalto, centro,
                    { p[1], p[2], p[3], p[1] / m, p[2] / m },
                    { q[1], q[2], q[3], q[1] / m, q[2] / m },
                    0, 1, 0, 1, 0, 0)
            end
        end
    end
    return trozos
end

return CallesMalla

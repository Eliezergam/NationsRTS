-- Territorio de cada nación, dibujado por sus celdas cuadradas.
--
-- El territorio ES la rejilla de la simulación: celdas de `sim.celda` px de
-- lado, cada una con su nación dueña (`sim:celdasEn`) o sin dueño. Aquí solo
-- se dibuja:
--   · relleno suave del color de la nación en cada celda suya, sin líneas
--     entre celdas de la misma nación (se ven como una sola región);
--   · el contorno de cada región por los bordes de celda: una franja oscura
--     justo en el borde (para que se lea sobre cualquier suelo) y, por dentro,
--     otra del color de la nación. Entre dos naciones cada una pone su franja
--     dentro de su celda: se ven las dos líneas, una junto a la otra;
--   · la tierra sin dueño no se pinta;
--   · «muro de luz» (el dueño, 26-nov, de las muestras de
--     tools/muestras/bordes_holograficos.html, la 4): en cada borde una
--     cortina translúcida del color de la nación que sube desde el suelo y se
--     desvanece hacia arriba, con un filo tenue en lo alto; abajo, una línea
--     clara (núcleo) sobre la franja de color.
--
-- Cada trozo de terreno tiene su propia malla de territorio, recortada a su
-- caja. Los rectángulos se parten por la rejilla del terreno y cada vértice
-- toma la altura del terreno en ese punto, así que el territorio va pegado a
-- las colinas (y sobre el agua, a su nivel).
--
-- La malla se construye en hilos aparte (`mundo/obrero_territorio.lua`, 27-nov:
-- construirla aquí era lo que más pesaba del mapa al mover la cámara en una
-- partida larga). El hilo principal junta lo poco que hace falta de cada
-- trozo (`Territorio.pedido`: dueños de las celdas, colores y alturas), el
-- hilo escribe los vértices en memoria (`Territorio.construir`) y aquí solo se
-- suben a la tarjeta (`Territorio.malla`). Sin hilos, todo aquí mismo
-- (`Territorio.mallaTrozo`).

local ffi = require('ffi')
local Terreno = require('mundo.terreno')
local Generador = require('mundo.generador')
local Iso = require('mundo.iso')

local Territorio = {}

-- Vértices con el formato por defecto de LÖVE (posición, coordenada de
-- textura y color), escritos en memoria.
ffi.cdef([[
typedef struct { float x, y, u, v; uint8_t r, g, b, a; } VerticeTerritorio;
]])
local FORMATO = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexColor', 'byte', 4 },
}
local TAMANO = ffi.sizeof('VerticeTerritorio')
-- Búfer de cada hilo para ir escribiendo (crece cuando hace falta).
local reserva, capacidad = nil, 0

Territorio.hilos = 2 -- hilos que construyen mallas

Territorio.relleno = 0.09 -- opacidad del relleno de una celda: apenas un tinte, el mapa se ve natural; la frontera de color marca el territorio
Territorio.bordeOscuro = 10 -- px de mundo de la franja oscura del borde
Territorio.bordeColor = 26 -- px de mundo de la franja de color, por dentro
Territorio.bordeInterior = 5 -- px de mundo del filo oscuro por dentro del color
Territorio.oscuro = { 0.07, 0.06, 0.05, 0.85 }
Territorio.muroAlto = 220 -- m que sube la cortina de luz sobre el borde
Territorio.muroAlfa = 0.42 -- opacidad de la cortina abajo (arriba, 0)
Territorio.muroFilo = 0.35 -- opacidad del filo de lo alto
Territorio.nucleo = 6 -- px de mundo de la línea clara del borde
Territorio.filo = { 0.07, 0.06, 0.05, 0.45 }

--- Grosor de las franjas según el zoom: de lejos más anchas (en px de mundo)
-- para que se sigan leyendo. Dos niveles, para no rehacer mallas a cada paso
-- de la rueda.
function Territorio.grosor(zoom)
    if (zoom or 1) < 0.16 then
        return 2.5
    end
    return 1
end

--- Alturas de los vértices del trozo (el mar, a su nivel), sacadas de los
-- datos de su comarca (`mundo/generador.lua`: x, y, altura, nx, ny por
-- vértice). En una lista plana, fila a fila: (n + 1)² números.
local function alturasTrozo(trozo)
    local n = Terreno.celdasPorTrozo
    local c = trozo.comarca
    local f = ffi.cast('float*', c.datos:getFFIPointer())
    local ancho = Generador.celdas + 1
    local numeros = Generador.numerosSuelo
    local z = {}
    for j = 0, n do
        for i = 0, n do
            local k = ((trozo.j0 + j) * ancho + trozo.i0 + i) * numeros + 2
            z[#z + 1] = math.max(f[k], Terreno.nivelMar)
        end
    end
    return z
end

--- Rectángulos de color de un trozo, en coordenadas del mundo y sin recortar:
-- { x0, y0, x1, y1, r, g, b, a }. Primero los rellenos, luego el filo de
-- dentro, las franjas de color y al final las oscuras (lo oscuro del borde
-- queda encima en las esquinas). Las celdas, colores y grosor salen del
-- pedido `p` (`Territorio.pedido`).
local function rectangulos(p, x0, y0, x1, y1)
    local c = p.celda
    local k = p.k
    local cx0, cy0 = math.floor(x0 / c), math.floor(y0 / c)
    local cx1, cy1 = math.floor((x1 - 0.001) / c), math.floor((y1 - 0.001) / c)
    local duenos = {}
    local lista = p.duenos
    for q = 1, #lista, 3 do
        duenos[lista[q] * 65536 + lista[q + 1]] = lista[q + 2]
    end
    local function dueno(cx, cy)
        return duenos[cx * 65536 + cy]
    end

    local rellenos, filos, colores, oscuros, nucleos = {}, {}, {}, {}, {}
    local muros = {}
    local o = Territorio.bordeOscuro * k
    local t = o + Territorio.bordeColor * k
    local f = t + Territorio.bordeInterior * k
    local sombra = Territorio.oscuro
    local filo = Territorio.filo
    local function banda(lista, ax, ay, bx, by, color, alfa)
        lista[#lista + 1] = { ax, ay, bx, by, color[1], color[2], color[3], alfa }
    end

    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            local nid = dueno(cx, cy)
            local color = nid and p.colores[nid]
            if color then
                local ax, ay = cx * c, cy * c
                local bx, by = ax + c, ay + c
                banda(rellenos, ax, ay, bx, by, color, Territorio.relleno)
                local arriba = dueno(cx, cy - 1) ~= nid
                local abajo = dueno(cx, cy + 1) ~= nid
                local izquierda = dueno(cx - 1, cy) ~= nid
                local derecha = dueno(cx + 1, cy) ~= nid
                local claro = { 0.55 + color[1] * 0.45, 0.55 + color[2] * 0.45, 0.55 + color[3] * 0.45 }
                local n = Territorio.nucleo * k
                local function muro(px, py, qx, qy)
                    muros[#muros + 1] = { px, py, qx, qy, color }
                end
                if arriba then
                    muro(ax, ay, bx, ay)
                    banda(nucleos, ax, ay, bx, ay + n, claro, 0.95)
                    banda(filos, ax, ay, bx, ay + f, filo, filo[4])
                    banda(colores, ax, ay, bx, ay + t, color, 1)
                    banda(oscuros, ax, ay, bx, ay + o, sombra, sombra[4])
                end
                if abajo then
                    muro(ax, by, bx, by)
                    banda(nucleos, ax, by - n, bx, by, claro, 0.95)
                    banda(filos, ax, by - f, bx, by, filo, filo[4])
                    banda(colores, ax, by - t, bx, by, color, 1)
                    banda(oscuros, ax, by - o, bx, by, sombra, sombra[4])
                end
                if izquierda then
                    muro(ax, ay, ax, by)
                    banda(nucleos, ax, ay, ax + n, by, claro, 0.95)
                    banda(filos, ax, ay, ax + f, by, filo, filo[4])
                    banda(colores, ax, ay, ax + t, by, color, 1)
                    banda(oscuros, ax, ay, ax + o, by, sombra, sombra[4])
                end
                if derecha then
                    muro(bx, ay, bx, by)
                    banda(nucleos, bx - n, ay, bx, by, claro, 0.95)
                    banda(filos, bx - f, ay, bx, by, filo, filo[4])
                    banda(colores, bx - t, ay, bx, by, color, 1)
                    banda(oscuros, bx - o, ay, bx, by, sombra, sombra[4])
                end
                -- Esquinas por dentro: los dos lados son suyos pero la
                -- diagonal no; el contorno dobla aquí y hay que cerrarlo.
                local esquinas = {
                    { not arriba and not izquierda and dueno(cx - 1, cy - 1) ~= nid, ax, ay, 1, 1 },
                    { not arriba and not derecha and dueno(cx + 1, cy - 1) ~= nid, bx, ay, -1, 1 },
                    { not abajo and not izquierda and dueno(cx - 1, cy + 1) ~= nid, ax, by, 1, -1 },
                    { not abajo and not derecha and dueno(cx + 1, cy + 1) ~= nid, bx, by, -1, -1 },
                }
                for _, e in ipairs(esquinas) do
                    if e[1] then
                        local px, py, sx, sy = e[2], e[3], e[4], e[5]
                        banda(filos, px, py, px + sx * f, py + sy * f, filo, filo[4])
                        banda(colores, px, py, px + sx * t, py + sy * t, color, 1)
                        banda(oscuros, px, py, px + sx * o, py + sy * o, sombra, sombra[4])
                    end
                end
            end
        end
    end

    local todos = rellenos
    for _, lista in ipairs({ filos, oscuros, colores, nucleos }) do
        for _, r in ipairs(lista) do
            todos[#todos + 1] = r
        end
    end
    return todos, muros
end

--- Firma de las celdas que tocan al trozo (y sus vecinas): si no cambia, su
-- malla sirve aunque haya cambiado el territorio en otra parte.
function Territorio.firma(sim, trozo)
    local lado = Terreno.celdasPorTrozo * Terreno.celda
    local c = sim.celda
    local x0, y0 = trozo.tx * lado, trozo.ty * lado
    local cx0, cy0 = math.floor(x0 / c) - 1, math.floor(y0 / c) - 1
    local cx1, cy1 = math.floor((x0 + lado - 0.001) / c) + 1, math.floor((y0 + lado - 0.001) / c) + 1
    return sim:firmaEn(cx0, cy0, cx1, cy1)
end

--- Lo que necesita `Territorio.construir` para la malla del trozo (en el hilo
-- principal, que tiene la simulación): las celdas de alrededor con su dueño,
-- el color de cada nación y las alturas del terreno. nil si en el trozo todo
-- es tierra de nadie (no hay malla). `k`: grosor de las franjas
-- (`Territorio.grosor`).
function Territorio.pedido(sim, trozo, k)
    local lado = Terreno.celdasPorTrozo * Terreno.celda
    local c = sim.celda
    local x0, y0 = trozo.tx * lado, trozo.ty * lado
    local cx0, cy0 = math.floor(x0 / c), math.floor(y0 / c)
    local cx1, cy1 = math.floor((x0 + lado - 0.001) / c), math.floor((y0 + lado - 0.001) / c)
    local duenos, colores = {}, {}
    local alguna = false
    for _, celda in ipairs(sim:celdasEn(cx0 - 1, cy0 - 1, cx1 + 1, cy1 + 1)) do
        local cx, cy, nid = celda[1], celda[2], celda[3]
        duenos[#duenos + 1] = cx
        duenos[#duenos + 1] = cy
        duenos[#duenos + 1] = nid
        if colores[nid] == nil then
            local nacion = sim:nacion(nid)
            colores[nid] = nacion and { nacion.color[1], nacion.color[2], nacion.color[3] } or false
        end
        if colores[nid] and cx >= cx0 and cx <= cx1 and cy >= cy0 and cy <= cy1 then
            alguna = true
        end
    end
    if not alguna then
        return nil
    end
    return { tx = trozo.tx, ty = trozo.ty, k = k or 1, celda = c, duenos = duenos, colores = colores,
        z = alturasTrozo(trozo) }
end

--- Un color de 0 a 1 en byte, como lo pasa LÖVE desde una tabla.
local function byte(c)
    c = c or 1
    return math.floor((c < 0 and 0 or c > 1 and 1 or c) * 255)
end

--- Vértices de la malla del territorio de un pedido (`Territorio.pedido`), en
-- un ByteData con el formato de `Territorio.malla`, o nil si no hay nada que
-- pintar. No toca la simulación ni la tarjeta: va en cualquier hilo.
function Territorio.construir(p)
    local n = Terreno.celdasPorTrozo
    local s = Terreno.celda
    local lado = n * s
    local x0, y0 = p.tx * lado, p.ty * lado
    local rects, muros = rectangulos(p, x0, y0, x0 + lado, y0 + lado)
    if #rects == 0 then
        return nil
    end
    local z = p.z
    local fila = n + 1

    -- Altura del terreno en (x, y) del trozo: la de la malla, interpolada.
    local function altura(x, y)
        local fx, fy = (x - x0) / s, (y - y0) / s
        local i, j = math.min(n - 1, math.floor(fx)), math.min(n - 1, math.floor(fy))
        local u, v = fx - i, fy - j
        local base = j * fila + i + 1
        local arriba = z[base] + (z[base + 1] - z[base]) * u
        local abajo = z[base + fila] + (z[base + fila + 1] - z[base + fila]) * u
        return arriba + (abajo - arriba) * v
    end

    -- Cortes de un tramo [a, b] por la rejilla del terreno (cada `s`).
    local function cortes(a, b, origen)
        local lista = { a }
        local corte = math.floor((a - origen) / s) + 1
        while origen + corte * s < b do
            lista[#lista + 1] = origen + corte * s
            corte = corte + 1
        end
        lista[#lista + 1] = b
        return lista
    end

    local cuantos = 0
    local function poner(x, y, r, g, b, a)
        if cuantos >= capacidad then
            local nueva = math.max(4096, capacidad * 2)
            local otra = ffi.new('VerticeTerritorio[?]', nueva)
            if reserva then
                ffi.copy(otra, reserva, cuantos * TAMANO)
            end
            reserva, capacidad = otra, nueva
        end
        local q = reserva[cuantos]
        q.x, q.y, q.u, q.v = x, y, 0, 0
        q.r, q.g, q.b, q.a = byte(r), byte(g), byte(b), byte(a)
        cuantos = cuantos + 1
    end
    local function vertice(x, y, r)
        local vx, vy = Iso.vista(x, y, altura(x, y))
        poner(vx, vy, r[5], r[6], r[7], r[8])
    end

    for _, r in ipairs(rects) do
        local ax = math.max(x0, math.min(r[1], r[3]))
        local bx = math.min(x0 + lado, math.max(r[1], r[3]))
        local ay = math.max(y0, math.min(r[2], r[4]))
        local by = math.min(y0 + lado, math.max(r[2], r[4]))
        if bx > ax and by > ay then
            local xs, ys = cortes(ax, bx, x0), cortes(ay, by, y0)
            for j = 1, #ys - 1 do
                for i = 1, #xs - 1 do
                    local xa, xb, ya, yb = xs[i], xs[i + 1], ys[j], ys[j + 1]
                    vertice(xa, ya, r)
                    vertice(xb, ya, r)
                    vertice(xb, yb, r)
                    vertice(xa, ya, r)
                    vertice(xb, yb, r)
                    vertice(xa, yb, r)
                end
            end
        end
    end

    -- Muros de luz: cada borde, recortado al trozo y partido por la rejilla
    -- del terreno, sube `muroAlto` m desde el suelo.
    local H = Territorio.muroAlto
    local function vistaEn(x, y, sobre)
        local vx, vy = Iso.vista(x, y, altura(x, y) + sobre)
        return vx, vy
    end
    for _, m in ipairs(muros) do
        local c = m[5]
        local horizontal = m[2] == m[4]
        local fijo = horizontal and m[2] or m[1]
        local origen = horizontal and x0 or y0
        local origenFijo = horizontal and y0 or x0
        -- Medio abierto: un borde justo entre dos trozos lo pone solo uno.
        local dentroFijo = fijo >= origenFijo and fijo < origenFijo + lado
        local lo = horizontal and math.min(m[1], m[3]) or math.min(m[2], m[4])
        local hi = horizontal and math.max(m[1], m[3]) or math.max(m[2], m[4])
        local a = math.max(origen, lo)
        local b = math.min(origen + lado, hi)
        if dentroFijo and b > a then
            local lista = cortes(a, b, origen)
            for i = 1, #lista - 1 do
                local pa, pb = lista[i], lista[i + 1]
                local ax, ay = horizontal and pa or fijo, horizontal and fijo or pa
                local bx, by = horizontal and pb or fijo, horizontal and fijo or pb
                local a0x, a0y = vistaEn(ax, ay, 0)
                local b0x, b0y = vistaEn(bx, by, 0)
                local a1x, a1y = vistaEn(ax, ay, H)
                local b1x, b1y = vistaEn(bx, by, H)
                local abajo, arriba = Territorio.muroAlfa, 0
                local function v(x, y, alfa)
                    poner(x, y, c[1], c[2], c[3], alfa)
                end
                v(a0x, a0y, abajo)
                v(b0x, b0y, abajo)
                v(b1x, b1y, arriba)
                v(a0x, a0y, abajo)
                v(b1x, b1y, arriba)
                v(a1x, a1y, arriba)
                -- Filo de lo alto: una banda fina bajo el borde de arriba.
                local fa = Territorio.muroFilo
                local ga, gb = H * 0.97, H
                local c0x, c0y = vistaEn(ax, ay, ga)
                local d0x, d0y = vistaEn(bx, by, ga)
                v(c0x, c0y, fa)
                v(d0x, d0y, fa)
                v(b1x, b1y, fa)
                v(c0x, c0y, fa)
                v(b1x, b1y, fa)
                v(a1x, a1y, fa)
            end
        end
    end

    if cuantos == 0 then
        return nil
    end
    local datos = love.data.newByteData(cuantos * TAMANO)
    ffi.copy(datos:getFFIPointer(), reserva, cuantos * TAMANO)
    return datos
end

--- La malla de unos vértices de `Territorio.construir` (suelta los datos).
function Territorio.malla(datos)
    local malla = love.graphics.newMesh(FORMATO, datos, 'triangles', 'static')
    datos:release()
    return malla
end

--- Malla del territorio del trozo, o nil si todo es tierra de nadie, hecha
-- aquí mismo (sin hilos). `k`: grosor de las franjas (`Territorio.grosor`).
function Territorio.mallaTrozo(sim, trozo, k)
    local p = Territorio.pedido(sim, trozo, k)
    local datos = p and Territorio.construir(p)
    return datos and Territorio.malla(datos)
end

-- Hilos -------------------------------------------------------------------------------------

local hilos
local pedidosHilo = love.thread and love.thread.getChannel('territorio.pedidos')

--- Arranca los hilos la primera vez. ¿Hay alguno?
function Territorio.arrancarHilos()
    if not hilos then
        hilos = {}
        for _ = 1, Territorio.hilos do
            local ok, hilo = pcall(love.thread.newThread, 'mundo/obrero_territorio.lua')
            if ok then
                hilo:start()
                hilos[#hilos + 1] = hilo
            end
        end
    end
    return #hilos > 0
end

--- Manda un pedido a los hilos. La respuesta llega por el canal `p.canal`
-- con los mismos tx, ty, firma y generacion, y `datos` (o `error`).
function Territorio.pedir(p)
    pedidosHilo:push(p)
end

return Territorio

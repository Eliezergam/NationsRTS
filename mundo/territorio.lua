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
--   · la tierra sin dueño no se pinta.
--
-- Cada trozo de terreno tiene su propia malla de territorio, recortada a su
-- caja. Los rectángulos se parten por la rejilla del terreno y cada vértice
-- toma la altura del terreno en ese punto, así que el territorio va pegado a
-- las colinas (y sobre el agua, a su nivel).

local ffi = require('ffi')
local Terreno = require('mundo.terreno')
local Generador = require('mundo.generador')
local Iso = require('mundo.iso')

local Territorio = {}

Territorio.relleno = 0.09 -- opacidad del relleno de una celda: apenas un tinte, el mapa se ve natural; la frontera de color marca el territorio
Territorio.bordeOscuro = 10 -- px de mundo de la franja oscura del borde
Territorio.bordeColor = 26 -- px de mundo de la franja de color, por dentro
Territorio.bordeInterior = 5 -- px de mundo del filo oscuro por dentro del color
Territorio.oscuro = { 0.07, 0.06, 0.05, 0.85 }
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
-- datos de su comarca (`mundo/generador.lua`: x, y, altura, nx, ny por vértice).
local function alturasTrozo(trozo)
    local n = Terreno.celdasPorTrozo
    local c = trozo.comarca
    local f = ffi.cast('float*', c.datos:getFFIPointer())
    local ancho = Generador.celdas + 1
    local numeros = Generador.numerosSuelo
    local z = {}
    for j = 0, n do
        z[j] = {}
        for i = 0, n do
            local k = ((trozo.j0 + j) * ancho + trozo.i0 + i) * numeros + 2
            z[j][i] = math.max(f[k], Terreno.nivelMar)
        end
    end
    return z
end

--- Rectángulos de color de un trozo, en coordenadas del mundo y sin recortar:
-- { x0, y0, x1, y1, r, g, b, a }. Primero los rellenos, luego el filo de
-- dentro, las franjas de color y al final las oscuras (lo oscuro del borde
-- queda encima en las esquinas). `k` multiplica el grosor de las franjas.
local function rectangulos(sim, x0, y0, x1, y1, k)
    local c = sim.celda
    local cx0, cy0 = math.floor(x0 / c), math.floor(y0 / c)
    local cx1, cy1 = math.floor((x1 - 0.001) / c), math.floor((y1 - 0.001) / c)
    local duenos = {}
    for _, celda in ipairs(sim:celdasEn(cx0 - 1, cy0 - 1, cx1 + 1, cy1 + 1)) do
        duenos[celda[1] * 65536 + celda[2]] = celda[3]
    end
    local function dueno(cx, cy)
        return duenos[cx * 65536 + cy]
    end

    local rellenos, filos, colores, oscuros = {}, {}, {}, {}
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
            local nacion = nid and sim:nacion(nid)
            if nacion then
                local color = nacion.color
                local ax, ay = cx * c, cy * c
                local bx, by = ax + c, ay + c
                banda(rellenos, ax, ay, bx, by, color, Territorio.relleno)
                local arriba = dueno(cx, cy - 1) ~= nid
                local abajo = dueno(cx, cy + 1) ~= nid
                local izquierda = dueno(cx - 1, cy) ~= nid
                local derecha = dueno(cx + 1, cy) ~= nid
                if arriba then
                    banda(filos, ax, ay, bx, ay + f, filo, filo[4])
                    banda(colores, ax, ay, bx, ay + t, color, 1)
                    banda(oscuros, ax, ay, bx, ay + o, sombra, sombra[4])
                end
                if abajo then
                    banda(filos, ax, by - f, bx, by, filo, filo[4])
                    banda(colores, ax, by - t, bx, by, color, 1)
                    banda(oscuros, ax, by - o, bx, by, sombra, sombra[4])
                end
                if izquierda then
                    banda(filos, ax, ay, ax + f, by, filo, filo[4])
                    banda(colores, ax, ay, ax + t, by, color, 1)
                    banda(oscuros, ax, ay, ax + o, by, sombra, sombra[4])
                end
                if derecha then
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
    for _, lista in ipairs({ filos, colores, oscuros }) do
        for _, r in ipairs(lista) do
            todos[#todos + 1] = r
        end
    end
    return todos
end

--- Firma de las celdas que tocan al trozo (y sus vecinas): si no cambia, su
-- malla sirve aunque haya cambiado el territorio en otra parte.
function Territorio.firma(sim, trozo)
    local lado = Terreno.celdasPorTrozo * Terreno.celda
    local c = sim.celda
    local x0, y0 = trozo.tx * lado, trozo.ty * lado
    local cx0, cy0 = math.floor(x0 / c) - 1, math.floor(y0 / c) - 1
    local cx1, cy1 = math.floor((x0 + lado - 0.001) / c) + 1, math.floor((y0 + lado - 0.001) / c) + 1
    local partes = {}
    for _, celda in ipairs(sim:celdasEn(cx0, cy0, cx1, cy1)) do
        partes[#partes + 1] = celda[1] .. ',' .. celda[2] .. '=' .. celda[3]
    end
    return table.concat(partes, ';')
end

--- Malla del territorio del trozo, o nil si todo es tierra de nadie. `k`:
-- grosor de las franjas (`Territorio.grosor`).
function Territorio.mallaTrozo(sim, trozo, k)
    local n = Terreno.celdasPorTrozo
    local s = Terreno.celda
    local lado = n * s
    local x0, y0 = trozo.tx * lado, trozo.ty * lado
    local rects = rectangulos(sim, x0, y0, x0 + lado, y0 + lado, k or 1)
    if #rects == 0 then
        return nil
    end
    local z = alturasTrozo(trozo)

    -- Altura del terreno en (x, y) del trozo: la de la malla, interpolada.
    local function altura(x, y)
        local fx, fy = (x - x0) / s, (y - y0) / s
        local i, j = math.min(n - 1, math.floor(fx)), math.min(n - 1, math.floor(fy))
        local u, v = fx - i, fy - j
        local arriba = z[j][i] + (z[j][i + 1] - z[j][i]) * u
        local abajo = z[j + 1][i] + (z[j + 1][i + 1] - z[j + 1][i]) * u
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

    local vertices = {}
    local function vertice(x, y, r)
        local vx, vy = Iso.vista(x, y, altura(x, y))
        vertices[#vertices + 1] = { vx, vy, 0, 0, r[5], r[6], r[7], r[8] }
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

    if #vertices == 0 then
        return nil
    end
    return love.graphics.newMesh(vertices, 'triangles', 'static')
end

return Territorio

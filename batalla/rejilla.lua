-- Rejilla del terreno de batalla en memoria (FFI): posición desplazada,
-- altura final y los campos que se calculan una vez por vértice (ruidos,
-- humedad, bosque, agua...). Todo lo que pisa, se planta o se colorea lee de
-- aquí, interpolado en el triángulo que toca, para que nada flote.
--
-- Los vértices se guardan fila a fila: el índice de (i, j) es j * lado + i,
-- con i y j desde 0. Las líneas sin desplazar están en `xs` y `ys` (desde 1).
-- Cada cuadro (i, j) se parte en dos triángulos por la diagonal que alterna
-- como un tablero: con (i + j) par, a-b-d y a-d-c; si no, a-b-c y b-d-c.

local ffi = require('ffi')

local Rejilla = {}
Rejilla.__index = Rejilla

Rejilla.pasoIndice = 40 -- px de la tabla que lleva de coordenada a línea

--- Array de `n` números (double) a cero.
function Rejilla.array(n)
    return ffi.new('double[?]', n)
end

--- Rejilla sobre las líneas `xs` y `ys` (tablas ordenadas de px).
function Rejilla.nueva(xs, ys)
    local self = setmetatable({}, Rejilla)
    self.xs = xs
    self.ys = ys
    self.lado = #xs
    self.total = #xs * #ys
    self.x = Rejilla.array(self.total)
    self.y = Rejilla.array(self.total)
    self.h = Rejilla.array(self.total)
    self.indiceX = Rejilla.tablaIndices(xs)
    self.indiceY = Rejilla.tablaIndices(ys)
    return self
end

--- Tabla que da, para cada tramo de `pasoIndice` px, la última línea que
-- queda a su izquierda. Así localizar un punto no necesita búsqueda binaria.
function Rejilla.tablaIndices(lineas)
    local tabla = {}
    local paso = Rejilla.pasoIndice
    local cuantos = math.ceil((lineas[#lineas] - lineas[1]) / paso) + 1
    local linea = 1
    for k = 0, cuantos do
        local x = lineas[1] + k * paso
        while linea < #lineas - 1 and lineas[linea + 1] <= x do
            linea = linea + 1
        end
        tabla[k] = linea
    end
    return tabla
end

--- Línea (desde 0) a la izquierda de `x` en un eje.
local function lineaDe(lineas, tabla, x)
    local ultimo = #lineas - 1
    if x <= lineas[1] then
        return 0
    elseif x >= lineas[ultimo + 1] then
        return ultimo - 1
    end
    local linea = tabla[math.floor((x - lineas[1]) / Rejilla.pasoIndice)]
    while linea < ultimo and lineas[linea + 1] <= x do
        linea = linea + 1
    end
    return linea - 1
end

--- Cuadro sin desplazar (i, j) que contiene (x, y).
function Rejilla:cuadro(x, y)
    return lineaDe(self.xs, self.indiceX, x), lineaDe(self.ys, self.indiceY, y)
end

--- Vértice más cercano de la rejilla sin desplazar (rápido, para filtros).
function Rejilla:cercano(x, y)
    local i, j = self:cuadro(x, y)
    if x - self.xs[i + 1] > self.xs[i + 2] - x then
        i = i + 1
    end
    if y - self.ys[j + 1] > self.ys[j + 2] - y then
        j = j + 1
    end
    return j * self.lado + i
end

--- Índice (desde 0) de la línea más cercana a `x` en el eje X (`eje` = 'x')
-- o Y. `cercano(x, y)` es `ejeY * lado + ejeX`: separable, así que un
-- recorrido por filas puede calcular cada eje una sola vez.
function Rejilla:cercanoEje(eje, x)
    local lineas = eje == 'x' and self.xs or self.ys
    local tabla = eje == 'x' and self.indiceX or self.indiceY
    local i = lineaDe(lineas, tabla, x)
    if x - lineas[i + 1] > lineas[i + 2] - x then
        i = i + 1
    end
    return i
end

--- Coordenadas baricéntricas de (x, y) en el triángulo (a, b, c). Devuelve
-- nil si cae fuera (con un margen mínimo para los bordes compartidos).
function Rejilla:baricentricas(x, y, a, b, c)
    local px, py = self.x, self.y
    local ax, ay = px[a], py[a]
    local v0x, v0y = px[b] - ax, py[b] - ay
    local v1x, v1y = px[c] - ax, py[c] - ay
    local v2x, v2y = x - ax, y - ay
    local d = v0x * v1y - v1x * v0y
    if d == 0 then
        return nil
    end
    local wb = (v2x * v1y - v1x * v2y) / d
    local wc = (v0x * v2y - v2x * v0y) / d
    local wa = 1 - wb - wc
    local e = -1e-7
    if wa < e or wb < e or wc < e then
        return nil
    end
    return wa, wb, wc
end

--- Los tres vértices de los dos triángulos del cuadro (i, j).
function Rejilla:triangulosCuadro(i, j)
    local lado = self.lado
    local a = j * lado + i
    local b = a + 1
    local c = a + lado
    local d = c + 1
    if (i + j) % 2 == 0 then
        return a, b, d, a, d, c
    end
    return a, b, c, b, d, c
end

--- Prueba el triángulo (a, b, c): si contiene (x, y), deja sus vértices y
-- pesos en `self.ta`, `tb`, `tc`, `wa`, `wb`, `wc` y devuelve true. Lo mismo
-- que `baricentricas`, sin devolver varios valores: LuaJIT no compilaba los
-- bucles que la llamaban ("register coalescing too complex").
function Rejilla:probar(x, y, a, b, c)
    local px, py = self.x, self.y
    local ax, ay = px[a], py[a]
    local v0x, v0y = px[b] - ax, py[b] - ay
    local v1x, v1y = px[c] - ax, py[c] - ay
    local v2x, v2y = x - ax, y - ay
    local d = v0x * v1y - v1x * v0y
    if d == 0 then
        return false
    end
    local wb = (v2x * v1y - v1x * v2y) / d
    local wc = (v0x * v2y - v2x * v0y) / d
    local wa = 1 - wb - wc
    local e = -1e-7
    if wa < e or wb < e or wc < e then
        return false
    end
    self.ta, self.tb, self.tc = a, b, c
    self.wa, self.wb, self.wc = wa, wb, wc
    return true
end

--- Prueba los dos triángulos del cuadro (i, j) (ver `triangulosCuadro`).
function Rejilla:probarCuadro(x, y, i, j)
    local a = j * self.lado + i
    local c = a + self.lado
    local dentro
    if (i + j) % 2 == 0 then
        dentro = self:probar(x, y, a, a + 1, c + 1)
        if not dentro then
            dentro = self:probar(x, y, a, c + 1, c)
        end
    else
        dentro = self:probar(x, y, a, a + 1, c)
        if not dentro then
            dentro = self:probar(x, y, a + 1, c + 1, c)
        end
    end
    return dentro
end

--- Los 8 cuadros vecinos de (i0, j0) y, si no, el vértice más cercano.
function Rejilla:ubicarVecinos(x, y, i0, j0)
    local ultimo = self.lado - 2
    for dj = 0, 2 do
        local j = j0 + (dj == 0 and 0 or (dj == 1 and -1 or 1))
        if j >= 0 and j <= ultimo then
            for di = 0, 2 do
                local i = i0 + (di == 0 and 0 or (di == 1 and -1 or 1))
                if (di > 0 or dj > 0) and i >= 0 and i <= ultimo and self:probarCuadro(x, y, i, j) then
                    return
                end
            end
        end
    end
    -- Fuera del área: el vértice más cercano.
    local k = self:cercano(x, y)
    self.ta, self.tb, self.tc = k, k, k
    self.wa, self.wb, self.wc = 1, 0, 0
end

--- Busca el triángulo de la malla que contiene (x, y) y deja sus vértices y
-- pesos en `self.ta` ... `self.wc`. Por el desplazamiento de los vértices,
-- el punto puede caer en un cuadro vecino del que da la rejilla sin
-- desplazar: primero el propio (casi siempre) y luego los 8 vecinos.
function Rejilla:ubicar(x, y)
    local i = lineaDe(self.xs, self.indiceX, x)
    local j = lineaDe(self.ys, self.indiceY, y)
    local px, py = self.x, self.y
    local lado = self.lado
    local a = j * lado + i
    local c = a + lado
    -- Con los vértices desplazados, el punto puede quedar en el cuadro de al
    -- lado: si está más allá de los dos vértices de un borde, se prueba
    -- primero el vecino (así casi nunca hace falta recorrer los 8).
    local ultimo = lado - 2
    if x < px[a] and x < px[c] and i > 0 then
        i = i - 1
    elseif x > px[a + 1] and x > px[c + 1] and i < ultimo then
        i = i + 1
    end
    a = j * lado + i
    c = a + lado
    if y < py[a] and y < py[a + 1] and j > 0 then
        j = j - 1
    elseif y > py[c] and y > py[c + 1] and j < ultimo then
        j = j + 1
    end
    a = j * lado + i
    c = a + lado
    local t1a, t1b, t1c, t2a, t2b, t2c
    if (i + j) % 2 == 0 then
        t1a, t1b, t1c, t2a, t2b, t2c = a, a + 1, c + 1, a, c + 1, c
    else
        t1a, t1b, t1c, t2a, t2b, t2c = a, a + 1, c, a + 1, c + 1, c
    end
    local e = -1e-7
    for vez = 1, 2 do
        local ta, tb, tc = t1a, t1b, t1c
        if vez == 2 then
            ta, tb, tc = t2a, t2b, t2c
        end
        local ax, ay = px[ta], py[ta]
        local v0x, v0y = px[tb] - ax, py[tb] - ay
        local v1x, v1y = px[tc] - ax, py[tc] - ay
        local v2x, v2y = x - ax, y - ay
        local d = v0x * v1y - v1x * v0y
        if d ~= 0 then
            local wb = (v2x * v1y - v1x * v2y) / d
            local wc = (v0x * v2y - v2x * v0y) / d
            local wa = 1 - wb - wc
            if wa >= e and wb >= e and wc >= e then
                self.ta, self.tb, self.tc = ta, tb, tc
                self.wa, self.wb, self.wc = wa, wb, wc
                return
            end
        end
    end
    self:ubicarVecinos(x, y, i, j)
end

--- Triángulo de la malla que contiene (x, y) y sus pesos: a, b, c, wa, wb, wc.
function Rejilla:localizar(x, y)
    self:ubicar(x, y)
    return self.ta, self.tb, self.tc, self.wa, self.wb, self.wc
end

--- Valor de `campo` (array por vértice) interpolado en (x, y).
function Rejilla:interpolar(campo, x, y)
    self:ubicar(x, y)
    return campo[self.ta] * self.wa + campo[self.tb] * self.wb + campo[self.tc] * self.wc
end

--- Altura y normal (de la cara) en (x, y).
function Rejilla:alturaNormal(x, y)
    self:ubicar(x, y)
    local a, b, c = self.ta, self.tb, self.tc
    local px, py, ph = self.x, self.y, self.h
    local h = ph[a] * self.wa + ph[b] * self.wb + ph[c] * self.wc
    local ux, uy, uz = px[b] - px[a], py[b] - py[a], ph[b] - ph[a]
    local vx, vy, vz = px[c] - px[a], py[c] - py[a], ph[c] - ph[a]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-9 then
        return h, 0, 0, 1
    end
    if nz < 0 then
        l = -l
    end
    return h, nx / l, ny / l, nz / l
end

return Rejilla

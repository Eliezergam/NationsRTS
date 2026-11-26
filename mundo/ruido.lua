-- Ruido simplex 2D con semilla, fBm y crestas.
--
-- Todo el mundo sale de aquí: con la misma semilla, el mismo punto da siempre
-- el mismo valor, en cualquier máquina (no se usa `math.random`).

local Ruido = {}
Ruido.__index = Ruido

local GRADIENTES = {
    { 1, 1 },
    { -1, 1 },
    { 1, -1 },
    { -1, -1 },
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local F2 = 0.5 * (math.sqrt(3) - 1)
local G2 = (3 - math.sqrt(3)) / 6

function Ruido.nuevo(semilla)
    local self = setmetatable({}, Ruido)
    local tabla = {}

    for i = 0, 255 do
        tabla[i] = i
    end

    local estado = math.floor(semilla or 0) % 4294967296

    for i = 255, 1, -1 do
        estado = (estado * 1664525 + 1013904223) % 4294967296
        local j = estado % (i + 1)
        tabla[i], tabla[j] = tabla[j], tabla[i]
    end

    self.perm = {}

    for i = 0, 511 do
        self.perm[i] = tabla[i % 256]
    end

    return self
end

local floor = math.floor
local max = math.max

--- Aporte de una esquina del simplex. Función de módulo y no cierre dentro
-- de `simplex`: crear un cierre en cada llamada impedía que LuaJIT
-- compilara el ruido (y todo lo que lo llama). Sin ramas (`max` en lugar de
-- `if tt <= 0 then return 0`), para que las trazas no se partan; da los
-- mismos valores: con tt = 0 el producto es 0.
local function esquina(gx, gy, px, py)
    local tt = max(0, 0.5 - px * px - py * py)
    tt = tt * tt
    return tt * tt * (gx * px + gy * py)
end

--- Simplex 2D en [-1, 1].
function Ruido:simplex(x, y)
    local perm = self.perm
    local s = (x + y) * F2
    local i = floor(x + s)
    local j = floor(y + s)
    local t = (i + j) * G2
    local x0 = x - (i - t)
    local y0 = y - (j - t)
    local i1, j1 = 0, 1

    if x0 > y0 then
        i1, j1 = 1, 0
    end

    local x1 = x0 - i1 + G2
    local y1 = y0 - j1 + G2
    local x2 = x0 - 1 + 2 * G2
    local y2 = y0 - 1 + 2 * G2
    local ii, jj = i % 256, j % 256
    local total = 0

    local g0 = GRADIENTES[perm[ii + perm[jj]] % 8 + 1]
    local g1 = GRADIENTES[perm[ii + i1 + perm[jj + j1]] % 8 + 1]
    local g2 = GRADIENTES[perm[ii + 1 + perm[jj + 1]] % 8 + 1]
    total = total + esquina(g0[1], g0[2], x0, y0)
    total = total + esquina(g1[1], g1[2], x1, y1)
    total = total + esquina(g2[1], g2[2], x2, y2)

    return 70 * total
end

--- Suma de octavas, normalizada: aprox. [-1, 1].
function Ruido:fbm(x, y, octavas)
    local suma, amplitud, frecuencia, total = 0, 1, 1, 0

    for _ = 1, octavas or 4 do
        suma = suma + amplitud * self:simplex(x * frecuencia, y * frecuencia)
        total = total + amplitud
        amplitud = amplitud * 0.5
        frecuencia = frecuencia * 2
    end

    return suma / total
end

--- Crestas: 1 en las cumbres afiladas, 0 lejos de ellas. Para cordilleras.
function Ruido:crestas(x, y, octavas)
    local suma, amplitud, frecuencia, total = 0, 1, 1, 0

    for _ = 1, octavas or 4 do
        local n = 1 - math.abs(self:simplex(x * frecuencia, y * frecuencia))
        suma = suma + amplitud * n * n
        total = total + amplitud
        amplitud = amplitud * 0.5
        frecuencia = frecuencia * 2
    end

    return suma / total
end

--- Número pseudoaleatorio estable para unas coordenadas enteras: la base de
-- que cada árbol y cada ciudad salga siempre igual en el mismo sitio.
function Ruido.hash(semilla, a, b, c)
    local h = (semilla or 0) * 374761393 + (a or 0) * 668265263 + (b or 0) * 2147483647 + (c or 0) * 1274126177
    h = h % 4294967296
    h = (h * 1103515245 + 12345) % 4294967296
    h = (h * 1103515245 + 12345) % 4294967296
    return h
end

--- Generador de números a partir de una semilla (para decidir las piezas de
-- una planta o de una ciudad). Devuelve una función como `math.random`.
function Ruido.azar(semilla)
    local estado = math.floor(semilla) % 2147483647

    if estado <= 0 then
        estado = estado + 2147483646
    end

    return function(a, b)
        estado = (estado * 16807) % 2147483647
        local r = estado / 2147483647

        if a and b then
            return a + (b - a) * r
        elseif a then
            return math.floor(r * a) + 1
        end

        return r
    end
end

--- Lo mismo que `Ruido.azar`, pero como tabla invocable y no como cierre:
-- LuaJIT no compila la creación de cierres (FNEW) y la vegetación de una
-- batalla crea decenas de miles. Da exactamente la misma secuencia.
local Generador = {}
Generador.__index = Generador

function Generador.__call(self, a, b)
    local estado = (self.estado * 16807) % 2147483647
    self.estado = estado
    local r = estado / 2147483647

    if a and b then
        return a + (b - a) * r
    elseif a then
        return math.floor(r * a) + 1
    end

    return r
end

function Ruido.generador(semilla)
    local estado = math.floor(semilla) % 2147483647

    if estado <= 0 then
        estado = estado + 2147483646
    end

    return setmetatable({ estado = estado }, Generador)
end

return Ruido

-- Constructor de mallas low-poly de caras planas para la escena de batalla.
--
-- Escribe los vértices directamente en memoria (FFI) con el mismo formato que
-- los modelos 3D (posición, normal, color y nación; ver mundo/modelos3d.lua):
-- el terreno de 1,5 km tiene cientos de miles de vértices y una tabla de Lua
-- por vértice sería lenta. Cada triángulo lleva su normal de cara: se ve
-- facetado, como el resto del juego.

local ffi = require('ffi')
local Modelos3d = require('mundo.modelos3d')

local Malla = {}
Malla.__index = Malla

local datosPorMalla = setmetatable({}, { __mode = 'k' })

local FLOTANTES = 10 -- x y z, nx ny nz, r g b, nacion
local BYTES = FLOTANTES * 4

function Malla.nueva(capacidad)
    local self = setmetatable({}, Malla)
    self.capacidad = math.max(64, capacidad or 1024)
    self.datos = love.data.newByteData(self.capacidad * BYTES)
    self.p = ffi.cast('float*', self.datos:getFFIPointer())
    self.n = 0
    return self
end

--- Dobla la memoria cuando no cabe un triángulo más.
function Malla:crecer()
    local capacidad = self.capacidad * 2
    local datos = love.data.newByteData(capacidad * BYTES)
    local p = ffi.cast('float*', datos:getFFIPointer())
    ffi.copy(p, self.p, self.n * BYTES)
    self.datos, self.p, self.capacidad = datos, p, capacidad
end

function Malla:vertice(x, y, z, nx, ny, nz, r, g, b, nacion)
    if self.n >= self.capacidad then
        self:crecer()
    end
    local p, k = self.p, self.n * FLOTANTES
    p[k], p[k + 1], p[k + 2] = x, y, z
    p[k + 3], p[k + 4], p[k + 5] = nx, ny, nz
    p[k + 6], p[k + 7], p[k + 8] = r, g, b
    p[k + 9] = nacion or 0
    self.n = self.n + 1
end

--- Triángulo de color plano con la normal de su cara (hacia donde gira a, b, c
-- en sentido antihorario visto desde fuera; si queda hacia abajo, se da la vuelta).
function Malla:triangulo(ax, ay, az, bx, by, bz, cx, cy, cz, color, nacion)
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local vx, vy, vz = cx - ax, cy - ay, cz - az
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-9 then
        return
    end
    nx, ny, nz = nx / l, ny / l, nz / l
    local r, g, b = color[1], color[2], color[3]
    self:vertice(ax, ay, az, nx, ny, nz, r, g, b, nacion)
    self:vertice(bx, by, bz, nx, ny, nz, r, g, b, nacion)
    self:vertice(cx, cy, cz, nx, ny, nz, r, g, b, nacion)
end

--- Triángulo con un color distinto en cada vértice. Conserva la normal plana
-- de la cara, pero permite transiciones de terreno suaves.
function Malla:trianguloColores(ax, ay, az, colorA, bx, by, bz, colorB, cx, cy, cz, colorC, normalA, normalB, normalC)
    local ux = bx - ax
    local uy = by - ay
    local uz = bz - az
    local vx = cx - ax
    local vy = cy - ay
    local vz = cz - az
    local nx = uy * vz - uz * vy
    local ny = uz * vx - ux * vz
    local nz = ux * vy - uy * vx
    local largo = math.sqrt(nx * nx + ny * ny + nz * nz)

    if largo < 0.000000001 then
        return
    end

    nx = nx / largo
    ny = ny / largo
    nz = nz / largo

    normalA = normalA or { nx, ny, nz }
    normalB = normalB or normalA
    normalC = normalC or normalA
    self:vertice(ax, ay, az, normalA[1], normalA[2], normalA[3], colorA[1], colorA[2], colorA[3])
    self:vertice(bx, by, bz, normalB[1], normalB[2], normalB[3], colorB[1], colorB[2], colorB[3])
    self:vertice(cx, cy, cz, normalC[1], normalC[2], normalC[3], colorC[1], colorC[2], colorC[3])
end

--- Triángulo cuya normal apunta hacia fuera del punto (ox, oy, oz): para los
-- sólidos, sin tener que cuidar el orden de los vértices.
function Malla:caraFuera(ox, oy, oz, ax, ay, az, bx, by, bz, cx, cy, cz, color, nacion)
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local vx, vy, vz = cx - ax, cy - ay, cz - az
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local mx, my, mz = (ax + bx + cx) / 3 - ox, (ay + by + cy) / 3 - oy, (az + bz + cz) / 3 - oz
    if nx * mx + ny * my + nz * mz < 0 then
        self:triangulo(ax, ay, az, cx, cy, cz, bx, by, bz, color, nacion)
    else
        self:triangulo(ax, ay, az, bx, by, bz, cx, cy, cz, color, nacion)
    end
end

--- Tronco de cono (o cilindro, o cono si `radioArriba` es 0) de `lados` caras,
-- con la base en (x, y, z) y alto `alto`. `giro` gira las aristas.
function Malla:prisma(x, y, z, radio, radioArriba, alto, lados, color, giro)
    giro = giro or 0
    local cz = z + alto / 2
    for k = 0, lados - 1 do
        local a0 = giro + k / lados * math.pi * 2
        local a1 = giro + (k + 1) / lados * math.pi * 2
        local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        local bx0, by0, bx1, by1 = x + c0 * radio, y + s0 * radio, x + c1 * radio, y + s1 * radio
        local tx0, ty0 = x + c0 * radioArriba, y + s0 * radioArriba
        local tx1, ty1 = x + c1 * radioArriba, y + s1 * radioArriba
        if radioArriba > 0 then
            self:caraFuera(x, y, cz, bx0, by0, z, bx1, by1, z, tx1, ty1, z + alto, color)
            self:caraFuera(x, y, cz, bx0, by0, z, tx1, ty1, z + alto, tx0, ty0, z + alto, color)
            self:caraFuera(x, y, z, x, y, z + alto, tx0, ty0, z + alto, tx1, ty1, z + alto, color)
        else
            -- Cono: cada cara llega a la punta.
            self:caraFuera(x, y, cz, bx0, by0, z, bx1, by1, z, x, y, z + alto, color)
        end
    end
end

--- Tronco o rama entre dos puntos. Los radios pueden ser distintos para que
-- la pieza se afine hacia la punta.
function Malla:prismaEntre(x0, y0, z0, x1, y1, z1, radio0, radio1, lados, color, giro)
    local dx = x1 - x0
    local dy = y1 - y0
    local dz = z1 - z0
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)

    if largo < 0.0001 then
        return
    end

    dx = dx / largo
    dy = dy / largo
    dz = dz / largo

    local horizontal = math.sqrt(dx * dx + dy * dy)
    local px
    local py
    local pz

    if horizontal > 0.0001 then
        px = -dy / horizontal
        py = dx / horizontal
        pz = 0
    else
        px = 1
        py = 0
        pz = 0
    end

    local qx = dy * pz - dz * py
    local qy = dz * px - dx * pz
    local qz = dx * py - dy * px
    local centroX = (x0 + x1) * 0.5
    local centroY = (y0 + y1) * 0.5
    local centroZ = (z0 + z1) * 0.5
    giro = giro or 0

    for indice = 0, lados - 1 do
        local angulo0 = giro + indice / lados * math.pi * 2
        local angulo1 = giro + (indice + 1) / lados * math.pi * 2
        local coseno0 = math.cos(angulo0)
        local seno0 = math.sin(angulo0)
        local coseno1 = math.cos(angulo1)
        local seno1 = math.sin(angulo1)
        local ax = x0 + (px * coseno0 + qx * seno0) * radio0
        local ay = y0 + (py * coseno0 + qy * seno0) * radio0
        local az = z0 + (pz * coseno0 + qz * seno0) * radio0
        local bx = x0 + (px * coseno1 + qx * seno1) * radio0
        local by = y0 + (py * coseno1 + qy * seno1) * radio0
        local bz = z0 + (pz * coseno1 + qz * seno1) * radio0
        local cx = x1 + (px * coseno1 + qx * seno1) * radio1
        local cy = y1 + (py * coseno1 + qy * seno1) * radio1
        local cz = z1 + (pz * coseno1 + qz * seno1) * radio1
        local ex = x1 + (px * coseno0 + qx * seno0) * radio1
        local ey = y1 + (py * coseno0 + qy * seno0) * radio1
        local ez = z1 + (pz * coseno0 + qz * seno0) * radio1

        self:caraFuera(centroX, centroY, centroZ, ax, ay, az, bx, by, bz, cx, cy, cz, color)
        self:caraFuera(centroX, centroY, centroZ, ax, ay, az, cx, cy, cz, ex, ey, ez, color)
    end
end

--- Caja de `largo` x `ancho` x `alto` con la base centrada en (x, y, z),
-- girada `rumbo` sobre z. `nacion` (0 a 1) la pinta del color del país.
function Malla:caja(x, y, z, largo, ancho, alto, rumbo, color, nacion)
    local c, s = math.cos(rumbo or 0), math.sin(rumbo or 0)
    local esquinas = {}
    for k, e in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
        local lx, ly = e[1] * largo / 2, e[2] * ancho / 2
        esquinas[k] = { x + c * lx - s * ly, y + s * lx + c * ly }
    end
    local cz = z + alto / 2
    local arriba = z + alto
    for k = 1, 4 do
        local p, q = esquinas[k], esquinas[k % 4 + 1]
        self:caraFuera(x, y, cz, p[1], p[2], z, q[1], q[2], z, q[1], q[2], arriba, color, nacion)
        self:caraFuera(x, y, cz, p[1], p[2], z, q[1], q[2], arriba, p[1], p[2], arriba, color, nacion)
    end
    local a, b, d, e = esquinas[1], esquinas[2], esquinas[3], esquinas[4]
    self:caraFuera(x, y, z, a[1], a[2], arriba, b[1], b[2], arriba, d[1], d[2], arriba, color, nacion)
    self:caraFuera(x, y, z, a[1], a[2], arriba, d[1], d[2], arriba, e[1], e[2], arriba, color, nacion)
end

-- Icosaedro unidad: 12 vértices y 20 caras.
local T = (1 + math.sqrt(5)) / 2
local ICO_V = {
    { -1, T, 0 },
    { 1, T, 0 },
    { -1, -T, 0 },
    { 1, -T, 0 },
    { 0, -1, T },
    { 0, 1, T },
    { 0, -1, -T },
    { 0, 1, -T },
    { T, 0, -1 },
    { T, 0, 1 },
    { -T, 0, -1 },
    { -T, 0, 1 },
}
local ICO_C = {
    { 1, 12, 6 },
    { 1, 6, 2 },
    { 1, 2, 8 },
    { 1, 8, 11 },
    { 1, 11, 12 },
    { 2, 6, 10 },
    { 6, 12, 5 },
    { 12, 11, 3 },
    { 11, 8, 7 },
    { 8, 2, 9 },
    { 4, 10, 5 },
    { 4, 5, 3 },
    { 4, 3, 7 },
    { 4, 7, 9 },
    { 4, 9, 10 },
    { 5, 10, 6 },
    { 3, 5, 12 },
    { 7, 3, 11 },
    { 9, 7, 8 },
    { 10, 9, 2 },
}

--- Icosaedro de radio `radio` (x, y) y `radioZ` (alto) en (x, y, z). Con `azar`
-- (función que da 0 a 1) cada vértice se mueve un poco: rocas y copas
-- irregulares, ninguna igual.
function Malla:icosaedro(x, y, z, radio, radioZ, color, azar, rumbo)
    local c, s = math.cos(rumbo or 0), math.sin(rumbo or 0)
    local puntos = {}
    local largo = math.sqrt(1 + T * T)
    for k, v in ipairs(ICO_V) do
        local d = azar and (0.8 + azar() * 0.35) or 1
        local vx, vy, vz = v[1] / largo * d, v[2] / largo * d, v[3] / largo * d
        puntos[k] = { x + (c * vx - s * vy) * radio, y + (s * vx + c * vy) * radio, z + vz * radioZ }
    end
    for _, cara in ipairs(ICO_C) do
        local a, b, d = puntos[cara[1]], puntos[cara[2]], puntos[cara[3]]
        self:caraFuera(x, y, z, a[1], a[2], a[3], b[1], b[2], b[3], d[1], d[2], d[3], color)
    end
end

--- Icosaedro con escala distinta en cada eje, giro en los tres ejes (Euler
-- XYZ, como Blender) y deformación ajustable. `azar(a, b)` es un Ruido.azar;
-- con `deformar` > 0 cada vértice se estira `1 + deformar * U(-1, 1) * 0.7`.
function Malla:icosaedroLibre(x, y, z, ex, ey, ez, gx, gy, gz, color, deformar, azar)
    local largo = math.sqrt(1 + T * T)
    local cx, sx = math.cos(gx or 0), math.sin(gx or 0)
    local cy, sy = math.cos(gy or 0), math.sin(gy or 0)
    local cz, sz = math.cos(gz or 0), math.sin(gz or 0)
    local puntos = {}
    for k, v in ipairs(ICO_V) do
        local d = 1
        if deformar and deformar > 0 and azar then
            d = 1 + deformar * (2 * azar() - 1) * 0.7
        end
        local px = v[1] / largo * d * ex
        local py = v[2] / largo * d * ey
        local pz = v[3] / largo * d * ez
        -- Giro X.
        local qy = py * cx - pz * sx
        local qz = py * sx + pz * cx
        py, pz = qy, qz
        -- Giro Y.
        local qx = px * cy + pz * sy
        qz = -px * sy + pz * cy
        px, pz = qx, qz
        -- Giro Z.
        qx = px * cz - py * sz
        qy = px * sz + py * cz
        puntos[k] = { x + qx, y + qy, z + pz }
    end
    for _, cara in ipairs(ICO_C) do
        local a, b, d = puntos[cara[1]], puntos[cara[2]], puntos[cara[3]]
        self:caraFuera(x, y, z, a[1], a[2], a[3], b[1], b[2], b[3], d[1], d[2], d[3], color)
    end
end

--- Color de una pieza: brillo U(1 - v, 1 + v) y +-3 % por canal.
function Malla.variarPieza(color, azar, v)
    local valor = azar(1 - v, 1 + v)
    return {
        color[1] * valor * azar(0.97, 1.03),
        color[2] * valor * azar(0.97, 1.03),
        color[3] * valor * azar(0.97, 1.03),
    }
end

--- Número de vértices escritos (para medir triángulos por prototipo).
function Malla:vertices()
    return self.n
end

--- Grupo pequeño de hojas con ocho caras. Es más barato que un icosaedro y
-- permite formar copas con muchas masas sin disparar el número de triángulos.
function Malla:octaedro(x, y, z, radio, radioZ, color, azar, rumbo)
    local giro = rumbo or 0
    local coseno = math.cos(giro)
    local seno = math.sin(giro)
    local puntos = {}

    for indice = 0, 3 do
        local angulo = indice * math.pi * 0.5
        local variacion = azar and 0.82 + azar() * 0.28 or 1
        local px = math.cos(angulo) * radio * variacion
        local py = math.sin(angulo) * radio * variacion
        puntos[indice + 1] = {
            x + coseno * px - seno * py,
            y + seno * px + coseno * py,
            z + (azar and (azar() - 0.5) * radioZ * 0.18 or 0),
        }
    end

    local arriba = { x, y, z + radioZ }
    local abajo = { x, y, z - radioZ * 0.72 }
    for indice = 1, 4 do
        local a = puntos[indice]
        local b = puntos[indice % 4 + 1]
        self:caraFuera(x, y, z, arriba[1], arriba[2], arriba[3], a[1], a[2], a[3], b[1], b[2], b[3], color)
        self:caraFuera(x, y, z, abajo[1], abajo[2], abajo[3], b[1], b[2], b[3], a[1], a[2], a[3], color)
    end
end

--- La malla de LÖVE con lo escrito (estática: se sube una vez).
function Malla:crear()
    if self.n == 0 then
        return nil
    end
    local datos = love.data.newByteData(self.n * BYTES)
    ffi.copy(ffi.cast('float*', datos:getFFIPointer()), self.p, self.n * BYTES)
    local malla = love.graphics.newMesh(Modelos3d.formato, datos, 'triangles', 'static')
    datosPorMalla[malla] = {
        datos = datos,
        vertices = self.n,
    }
    return malla
end

--- Datos originales de una malla creada aquí. El comparador con 3DreamEngine
-- los reutiliza una vez al cargar, sin leer vértices de vuelta desde la GPU.
function Malla.datosDe(malla)
    return datosPorMalla[malla]
end

return Malla

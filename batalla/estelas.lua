-- Estelas de humo de los misiles de la escena de batalla: una cinta continua
-- que sigue al misil por el aire, se ensancha y se desvanece con el tiempo, y
-- se queda un rato colgada después de que el misil cae.
--
-- Todas las estelas van en una sola malla que se rehace en cada cuadro (por
-- FFI, sin tablas por vértice): una cinta de dos triángulos por tramo, girada
-- hacia la cámara para que se vea igual de ancha desde cualquier lado.

local ffi = require('ffi')

local Estelas = {}
Estelas.__index = Estelas

Estelas.cadaSegundos = 0.08 -- s entre puntos de una estela
Estelas.vida = 7 -- s que tarda en desvanecerse un punto
Estelas.anchoInicial = 14 -- px de medio ancho al salir
Estelas.crecimiento = 22 -- px de medio ancho que gana por segundo
Estelas.maxTramos = 12000

local FORMATO = {
    { 'VertexPosition', 'float', 3 },
    { 'NormalModelo', 'float', 3 },
    { 'ColorModelo', 'float', 3 },
    { 'NacionModelo', 'float', 1 },
    { 'VertexColor', 'float', 4 },
}
local IDENTIDAD = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local FLOTANTES = 14
local BYTES = FLOTANTES * 4

function Estelas.nuevas()
    local self = setmetatable({}, Estelas)
    self.lista = {}
    self.vertices = Estelas.maxTramos * 6
    self.datos = love.data.newByteData(self.vertices * BYTES)
    self.p = ffi.cast('float*', self.datos:getFFIPointer())
    self.malla = love.graphics.newMesh(FORMATO, self.vertices, 'triangles', 'stream')
    return self
end

--- Estela nueva (sin puntos): se le van añadiendo con `apuntar`.
function Estelas:nueva()
    local e = { x = {}, y = {}, z = {}, t = {}, primero = 1, n = 0, siguiente = 0 }
    self.lista[#self.lista + 1] = e
    return e
end

--- Punto de la estela `e` en (x, y, z) en el instante `reloj`, si ya toca.
function Estelas:apuntar(e, x, y, z, reloj)
    if reloj < e.siguiente then
        return
    end
    e.siguiente = reloj + Estelas.cadaSegundos
    local k = e.n + 1
    e.x[k], e.y[k], e.z[k], e.t[k] = x, y, z, reloj
    e.n = k
end

--- Olvida los puntos ya desvanecidos y las estelas vacías.
function Estelas:actualizar(reloj)
    for k = #self.lista, 1, -1 do
        local e = self.lista[k]
        while e.primero <= e.n and reloj - e.t[e.primero] > Estelas.vida do
            e.primero = e.primero + 1
        end
        if e.terminada and e.primero > e.n then
            self.lista[k] = self.lista[#self.lista]
            self.lista[#self.lista] = nil
        end
    end
end

--- Dibuja todas las estelas vistas desde (ex, ey, ez).
function Estelas:dibujar(shader, reloj, ex, ey, ez)
    local p, v = self.p, 0
    local maximo = self.vertices
    local function vertice(x, y, z, nx, ny, nz, alfa)
        local k = v * FLOTANTES
        p[k], p[k + 1], p[k + 2] = x, y, z
        p[k + 3], p[k + 4], p[k + 5] = nx, ny, nz
        p[k + 6], p[k + 7], p[k + 8] = 0.93, 0.92, 0.9
        p[k + 9] = 0
        p[k + 10], p[k + 11], p[k + 12], p[k + 13] = 1, 1, 1, alfa
        v = v + 1
    end
    -- Medio ancho y lado (hacia la cámara) de la cinta en el punto k.
    local function lado(e, k, dx, dy, dz)
        local x, y, z = e.x[k], e.y[k], e.z[k]
        local cx, cy, cz = ex - x, ey - y, ez - z
        local dc = math.sqrt(cx * cx + cy * cy + cz * cz)
        local sx, sy, sz = dy * cz - dz * cy, dz * cx - dx * cz, dx * cy - dy * cx
        local ls = math.max(0.001, math.sqrt(sx * sx + sy * sy + sz * sz))
        local edad = reloj - e.t[k]
        -- De lejos, nunca más fina que un par de puntos de la pantalla.
        local ancho = math.max(Estelas.anchoInicial + edad * Estelas.crecimiento, dc * 0.0011)
        local alfa = 0.62 * (1 - edad / Estelas.vida) ^ 1.5
        return sx / ls * ancho, sy / ls * ancho, sz / ls * ancho, cx / dc, cy / dc, cz / dc, alfa
    end
    for _, e in ipairs(self.lista) do
        for k = e.primero, e.n - 1 do
            if v + 6 > maximo then
                break
            end
            local dx, dy, dz = e.x[k + 1] - e.x[k], e.y[k + 1] - e.y[k], e.z[k + 1] - e.z[k]
            local ax, ay, az, anx, any, anz, aa = lado(e, k, dx, dy, dz)
            local bx, by, bz, bnx, bny, bnz, ba = lado(e, k + 1, dx, dy, dz)
            local x0, y0, z0 = e.x[k], e.y[k], e.z[k]
            local x1, y1, z1 = e.x[k + 1], e.y[k + 1], e.z[k + 1]
            vertice(x0 - ax, y0 - ay, z0 - az, anx, any, anz, aa)
            vertice(x0 + ax, y0 + ay, z0 + az, anx, any, anz, aa)
            vertice(x1 + bx, y1 + by, z1 + bz, bnx, bny, bnz, ba)
            vertice(x0 - ax, y0 - ay, z0 - az, anx, any, anz, aa)
            vertice(x1 + bx, y1 + by, z1 + bz, bnx, bny, bnz, ba)
            vertice(x1 - bx, y1 - by, z1 - bz, bnx, bny, bnz, ba)
        end
    end
    self.tramos = v / 6
    if v == 0 then
        return
    end
    self.malla:setVertices(self.datos, 1, v)
    self.malla:setDrawRange(1, v)
    -- Los puntos ya están en el mundo: sin la matriz de lo último dibujado.
    shader:send('modelo', 'row', IDENTIDAD)
    shader:send('brillo', 0.35)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.malla)
    shader:send('brillo', 0)
end

return Estelas

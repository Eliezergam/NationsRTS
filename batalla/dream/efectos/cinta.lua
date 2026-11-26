-- Cinta de las estelas de humo en la GPU (Camila). Cada tramo son cuatro
-- vértices (dos en cada punto, uno a cada lado) y dos triángulos; el
-- sombreador (`estela_vertices.lua`) los abre hacia la cámara, los hace
-- derivar y los colorea con la edad.
--
-- Dos zonas en la misma malla:
--   cabezas  un tramo por misil en vuelo, del último punto a la tobera; se
--            reescribe cada cuadro para que la cinta llegue siempre al misil
--   anillo   los tramos ya fijos; se escriben una vez y se pliegan solos al
--            acabar su vida (todos viven lo mismo, así que el anillo va en
--            orden de edad y el más viejo es el primero en ceder su sitio)
--
-- Se dibuja todo en una llamada; los tramos muertos no ocupan píxeles.

local ffi = require('ffi')

pcall(
    ffi.cdef,
    [[
    typedef struct {
        float x, y, z, nace;
        float tx, ty, tz, lado;
        float recorrido, semilla, vida, escala;
    } efectoCintaVertice;
]]
)

local Cinta = {}
Cinta.__index = Cinta

local FORMATO = {
    { 'VertexPosition', 'float', 4 },
    { 'EstelaB', 'float', 4 },
    { 'EstelaC', 'float', 4 },
}
local TAMANO = ffi.sizeof('efectoCintaVertice')

--- Malla de `tramos` tramos (cuatro vértices y dos triángulos cada uno), a cero.
function Cinta.malla(tramos, uso)
    local malla = love.graphics.newMesh(FORMATO, tramos * 4, 'triangles', uso)
    local indices = love.data.newByteData(tramos * 6 * 4)
    local p = ffi.cast('uint32_t*', indices:getFFIPointer())
    for s = 0, tramos - 1 do
        local v = s * 4
        -- 0 y 1: el primer punto (lados -1 y 1); 2 y 3: el segundo.
        p[s * 6], p[s * 6 + 1], p[s * 6 + 2] = v, v + 1, v + 3
        p[s * 6 + 3], p[s * 6 + 4], p[s * 6 + 5] = v, v + 3, v + 2
    end
    malla:setVertexMap(indices, 'uint32')
    -- Todo a cero: tramos con vida 0, plegados.
    malla:setVertices(love.data.newByteData(tramos * 4 * TAMANO), 1, tramos * 4)
    return malla
end

--- `opciones`: cabezas (misiles en vuelo a la vez), tramos (anillo),
-- porCuadro (tramos nuevos por cuadro), vida (s), sombreador, textura y
-- parametros (uniformes).
function Cinta.nueva(dream, conversor, opciones)
    local self = setmetatable({}, Cinta)
    self.dream = dream
    self.conversor = conversor
    self.cabezas = opciones.cabezas
    self.tramos = opciones.tramos
    self.porCuadro = opciones.porCuadro or 1024
    -- El anillo es 'dynamic': LÖVE sube solo el tramo cambiado (con
    -- 'stream' subiría la malla entera en cada cuadro). Las cabezas cambian
    -- todas en cada cuadro y van en otra malla pequeña, 'stream'.
    self.malla = Cinta.malla(self.tramos, 'dynamic')
    self.mallaCabezas = Cinta.malla(self.cabezas, 'stream')
    -- Búferes de paso: cabezas (se suben enteras) y tramos nuevos del cuadro.
    self.datosCabezas = love.data.newByteData(self.cabezas * 4 * TAMANO)
    self.pCabezas = ffi.cast('efectoCintaVertice*', self.datosCabezas:getFFIPointer())
    self.datosA = love.data.newByteData(self.porCuadro * 4 * TAMANO)
    self.pA = ffi.cast('efectoCintaVertice*', self.datosA:getFFIPointer())
    self.datosB = love.data.newByteData(self.porCuadro * 4 * TAMANO)
    self.pB = ffi.cast('efectoCintaVertice*', self.datosB:getFFIPointer())
    self.libres = {}
    for k = self.cabezas - 1, 0, -1 do
        self.libres[#self.libres + 1] = k
    end
    self.cabezasUsadas = 0 -- mayor índice de cabeza en uso + 1
    self.cursor = 0
    self.nuevos = 0
    self.vida = opciones.vida or 8

    self.malla:setTexture(opciones.textura)
    self.mallaCabezas:setTexture(opciones.textura)
    self.sombreador = opciones.sombreador
    self.parametros = opciones.parametros or {}
    return self
end

--- Escribe los dos vértices del punto `q` (px del juego) en `p[k]` y `p[k + 1]`.
function Cinta:punto(p, k, q, e)
    local x, y, z = self.conversor:punto(q.x, q.y, q.z)
    for lado = 0, 1 do
        local v = p[k + lado]
        v.x, v.y, v.z, v.nace = x, y, z, q.nace
        -- Del eje Z vertical del juego al Y de Dream.
        v.tx, v.ty, v.tz, v.lado = q.tx, q.tz, q.ty, lado == 0 and -1 or 1
        v.recorrido, v.semilla, v.vida, v.escala = q.recorrido, e.semilla, self.vida, e.escala
    end
end

--- Tramo fijo del punto `a` al `b` de la estela `e`.
function Cinta:tramo(e, a, b)
    local n = self.nuevos
    if n >= self.porCuadro then
        return
    end
    self:punto(self.pA, n * 4, a, e)
    self:punto(self.pA, n * 4 + 2, b, e)
    self.nuevos = n + 1
end

--- Tramo de cabeza de la estela `e` (del último punto `a` a la tobera `b`).
function Cinta:cabeza(e, a, b)
    local indice = e.cabeza
    if not indice then
        indice = table.remove(self.libres)
        if not indice then
            return
        end
        e.cabeza = indice
        self.cabezasUsadas = math.max(self.cabezasUsadas, indice + 1)
    end
    self:punto(self.pCabezas, indice * 4, a, e)
    self:punto(self.pCabezas, indice * 4 + 2, b, e)
end

--- La estela `e` pierde su cabeza (el misil ha caído).
function Cinta:soltar(e)
    local indice = e.cabeza
    if not indice then
        return
    end
    e.cabeza = nil
    for k = 0, 3 do
        self.pCabezas[indice * 4 + k].vida = 0
    end
    self.libres[#self.libres + 1] = indice
end

--- Sube las cabezas y los tramos nuevos.
function Cinta:subir()
    if self.cabezasUsadas > 0 then
        self.mallaCabezas:setVertices(self.datosCabezas, 1, self.cabezasUsadas * 4)
        self.mallaCabezas:setDrawRange(1, self.cabezasUsadas * 6)
    end
    local n = self.nuevos
    if n == 0 then
        return
    end
    local inicio = self.cursor
    local primera = math.min(n, self.tramos - inicio)
    self.malla:setVertices(self.datosA, inicio * 4 + 1, primera * 4)
    if primera < n then
        ffi.copy(self.pB, self.pA + primera * 4, (n - primera) * 4 * TAMANO)
        self.malla:setVertices(self.datosB, 1, (n - primera) * 4)
    end
    self.cursor = (inicio + n) % self.tramos
    self.nuevos = 0
end

--- Dibuja todas las estelas con su sombreador (pase de efectos).
function Cinta:dibujar()
    local sombreador = self.sombreador
    love.graphics.setShader(sombreador)
    for nombre, valor in pairs(self.parametros) do
        if sombreador:hasUniform(nombre) then
            sombreador:send(nombre, valor)
        end
    end
    love.graphics.draw(self.malla)
    if self.cabezasUsadas > 0 then
        love.graphics.draw(self.mallaCabezas)
    end
end

return Cinta

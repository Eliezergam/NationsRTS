-- Constructor de mallas texturizadas para 3DreamEngine (de la prueba de
-- estilo de Camila, batalla/pruebas_estilo/geometria.lua). Se escriben
-- triángulos en metros, con Y hacia arriba, y al crear la malla se pasan a
-- la escala de la batalla (1 unidad de Dream = 10 m, ver
-- batalla/dream/conversor.lua), para que lo que salga de aquí se pueda
-- llevar a la batalla sin cambiar números.

local Geometria = {}
Geometria.__index = Geometria

-- Unidades de Dream por metro.
Geometria.metro = 0.1

function Geometria.nueva()
    local self = setmetatable({}, Geometria)
    self.posiciones = {}
    self.normales = {}
    self.uvs = {}
    self.cantidad = 0
    return self
end

--- Añade un vértice: posición (m), normal y UV.
function Geometria:vertice(x, y, z, nx, ny, nz, u, v)
    local k = self.cantidad
    self.posiciones[k * 3 + 1] = x
    self.posiciones[k * 3 + 2] = y
    self.posiciones[k * 3 + 3] = z
    local largo = math.sqrt(nx * nx + ny * ny + nz * nz)
    if largo < 0.000001 then
        largo = 1
        ny = 1
    end
    self.normales[k * 3 + 1] = nx / largo
    self.normales[k * 3 + 2] = ny / largo
    self.normales[k * 3 + 3] = nz / largo
    self.uvs[k * 2 + 1] = u
    self.uvs[k * 2 + 2] = v
    self.cantidad = k + 1
end

--- Triángulo de tres vértices { x, y, z, nx, ny, nz, u, v }.
function Geometria:triangulo(a, b, c)
    self:vertice(a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8])
    self:vertice(b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
    self:vertice(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
end

--- Cuadrilátero a-b-c-d (en sentido antihorario visto desde delante).
-- Con `dobleCara` se añade también la cara de atrás con las mismas normales:
-- así un plano de follaje recibe la misma luz desde los dos lados.
function Geometria:cuadrilatero(a, b, c, d, dobleCara)
    self:triangulo(a, b, c)
    self:triangulo(a, c, d)
    if dobleCara then
        self:triangulo(a, c, b)
        self:triangulo(a, d, c)
    end
end

--- Multiplica todas las posiciones por `factor` (las normales no cambian).
function Geometria:escalar(factor)
    for k = 1, self.cantidad * 3 do
        self.posiciones[k] = self.posiciones[k] * factor
    end
end

--- Caja de la geometría (m): minX, minY, minZ, maxX, maxY, maxZ.
function Geometria:caja()
    local p = self.posiciones
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for k = 0, self.cantidad - 1 do
        local x, y, z = p[k * 3 + 1], p[k * 3 + 2], p[k * 3 + 3]
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minY, maxY = math.min(minY, y), math.max(maxY, y)
        minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
    end
    return minX, minY, minZ, maxX, maxY, maxZ
end

function Geometria:triangulos()
    return self.cantidad / 3
end

--- Crea la malla de Dream con `material` y el sombreador de píxeles dado
-- (por defecto 'textured').
function Geometria:crearMalla(dream, material, sombreador)
    local cantidad = self.cantidad
    local malla = dream:newMesh(material)
    malla:setPixelShader(sombreador or 'textured')
    malla.vertices = dream:newBuffer('vec3', 'float', cantidad)
    malla.normals = dream:newBuffer('vec3', 'float', cantidad)
    malla.texCoords = dream:newBuffer('vec2', 'float', cantidad)
    malla.faces = dream:newBuffer('vec3', 'uint32_t', cantidad / 3)
    local vertices = malla.vertices.buffer
    local normales = malla.normals.buffer
    local uvs = malla.texCoords.buffer
    local escala = Geometria.metro
    for k = 0, cantidad - 1 do
        vertices[k].x = self.posiciones[k * 3 + 1] * escala
        vertices[k].y = self.posiciones[k * 3 + 2] * escala
        vertices[k].z = self.posiciones[k * 3 + 3] * escala
        normales[k].x = self.normales[k * 3 + 1]
        normales[k].y = self.normales[k * 3 + 2]
        normales[k].z = self.normales[k * 3 + 3]
        uvs[k].x = self.uvs[k * 2 + 1]
        uvs[k].y = self.uvs[k * 2 + 2]
    end
    local caras = malla.faces.buffer
    for k = 0, cantidad / 3 - 1 do
        caras[k].x = k * 3 + 1
        caras[k].y = k * 3 + 2
        caras[k].z = k * 3 + 3
    end
    malla:updateBoundingSphere()
    return malla
end

--- Material texturizado. `opciones`: textura, recorte (alpha-test),
-- rugosidad y traslucidez.
function Geometria.material(dream, nombre, opciones)
    local material = dream:newMaterial(nombre)
    material:setAlbedoTexture(opciones.textura)
    material:setRoughness(opciones.rugosidad or 0.9)
    material:setMetallic(0)
    if opciones.recorte then
        material:setCutout()
        material:setAlphaCutoff(opciones.recorte)
    end
    if opciones.particula then
        -- Luz de partícula: sin Fresnel ni caída por el ángulo de la normal.
        -- Los planos de follaje vistos de canto dejan de reflejar el cielo.
        material:setParticle(true)
    end
    if opciones.traslucidez then
        material:setTranslucency(opciones.traslucidez)
        -- Los planos ya llevan su cara de atrás (Geometria:cuadrilatero).
        material:setCullMode('back')
    end
    return material
end

return Geometria

-- Instancias de 3DreamEngine con tono por copia. El `instancedMesh` de la
-- librería solo lleva el giro y la posición de cada copia; aquí se añade un
-- atributo `InstanceTono` (vec3, por copia) que el shader de vértices de la
-- vegetación (`batalla/dream/viento.lua`) multiplica por el color. No toca
-- `lib/3DreamEngine`: sustituye tres métodos de la copia que devuelve
-- `dream:newInstancedMesh`.
--
-- Las copias se escriben de golpe desde un array FFI de 15 flotantes por
-- copia (giro en tres columnas, posición y tono), sin tablas por copia.

local ffi = require('ffi')

local InstanciasTono = {}

InstanciasTono.flotantes = 15

local FORMATO = {
    { 'InstanceRotation0', 'float', 3 },
    { 'InstanceRotation1', 'float', 3 },
    { 'InstanceRotation2', 'float', 3 },
    { 'InstancePosition', 'float', 3 },
    { 'InstanceTono', 'float', 3 },
}

--- Centro y semiejes de la caja del prototipo, en unidades de Dream. Se
-- mide una vez: las copias reutilizan esta geometría aunque cambie su giro.
local function cajaOriginal(malla)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local vertices = malla.vertices
    for indice = 0, vertices:getSize() - 1 do
        local v = vertices.buffer[indice]
        minX, maxX = math.min(minX, v.x), math.max(maxX, v.x)
        minY, maxY = math.min(minY, v.y), math.max(maxY, v.y)
        minZ, maxZ = math.min(minZ, v.z), math.max(maxZ, v.z)
    end
    return {
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2,
        (maxX - minX) / 2,
        (maxY - minY) / 2,
        (maxZ - minZ) / 2,
    }
end

--- Caja de una copia con la misma matriz que lee el shader: columnas en
-- los primeros nueve flotantes y posición en los tres siguientes. El valor
-- absoluto de cada fila cubre también escalas desiguales y árboles caídos.
-- vientoBatalla aplica esta transformación sin desplazar los vértices.
local function cajaCopia(self, datos, inicio)
    local k = inicio or 0
    local c = self.cajaOriginal
    local x = datos[k] * c[1] + datos[k + 3] * c[2] + datos[k + 6] * c[3] + datos[k + 9]
    local y = datos[k + 1] * c[1] + datos[k + 4] * c[2] + datos[k + 7] * c[3] + datos[k + 10]
    local z = datos[k + 2] * c[1] + datos[k + 5] * c[2] + datos[k + 8] * c[3] + datos[k + 11]
    local ex = math.abs(datos[k]) * c[4] + math.abs(datos[k + 3]) * c[5] + math.abs(datos[k + 6]) * c[6]
    local ey = math.abs(datos[k + 1]) * c[4] + math.abs(datos[k + 4]) * c[5] + math.abs(datos[k + 7]) * c[6]
    local ez = math.abs(datos[k + 2]) * c[4] + math.abs(datos[k + 5]) * c[5] + math.abs(datos[k + 8]) * c[6]
    return x - ex, y - ey, z - ez, x + ex, y + ey, z + ez
end

--- Rehace el buffer de copias con sitio para `cantidad` (sin conservarlas).
local function redimensionar(self, cantidad)
    cantidad = math.max(1, cantidad)
    self.instanceMesh = love.graphics.newMesh(FORMATO, cantidad, 'points', 'dynamic')
    self.capacidadTono = cantidad
    self.instancesCount = 0
end

--- La malla de LÖVE con los cinco atributos por copia enganchados.
local function obtenerMalla(self, nombre)
    nombre = nombre or 'mesh'
    local malla = self.dreamLib.classes.mesh.getMesh(self, nombre)
    if nombre == 'mesh' then
        malla:attachAttribute('InstanceRotation0', self.instanceMesh, 'perinstance')
        malla:attachAttribute('InstanceRotation1', self.instanceMesh, 'perinstance')
        malla:attachAttribute('InstanceRotation2', self.instanceMesh, 'perinstance')
        malla:attachAttribute('InstancePosition', self.instanceMesh, 'perinstance')
        malla:attachAttribute('InstanceTono', self.instanceMesh, 'perinstance')
        return malla, self.instancesCount
    end
    return malla
end

--- Pone `cantidad` copias desde `datos` (ByteData con 15 flotantes por
-- copia). `esfera` = { x, y, z, radio } en unidades de Dream: la esfera que
-- las envuelve a todas, para el recorte de la cámara.
local function ponerCopias(self, datos, cantidad, esfera)
    if cantidad > self.capacidadTono then
        redimensionar(self, math.max(cantidad, self.capacidadTono * 2))
    end
    if cantidad > 0 then
        self.instanceMesh:setVertices(datos, 1, cantidad)
    end
    self.instancesCount = cantidad
    local centro = self.dreamLib.vec3(esfera[1], esfera[2], esfera[3])
    self.boundingSphere = self.dreamLib:newBoundingSphere(centro, esfera[4])
end

--- Instancias de `malla` (una malla de Dream ya creada) con tono por copia.
function InstanciasTono.nuevas(dream, malla)
    local self = dream:newInstancedMesh(malla)
    self.dreamLib = dream
    self.cajaOriginal = cajaOriginal(malla)
    self.cajaCopia = cajaCopia
    self.resize = redimensionar
    self.getMesh = obtenerMalla
    self.ponerCopias = ponerCopias
    redimensionar(self, 16)
    return self
end

--- Memoria para `cantidad` copias: ByteData y su puntero de flotantes.
function InstanciasTono.memoria(cantidad)
    local datos = love.data.newByteData(math.max(1, cantidad) * InstanciasTono.flotantes * 4)
    return datos, ffi.cast('float*', datos:getFFIPointer())
end

return InstanciasTono

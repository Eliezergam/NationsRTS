-- Relleno por FFI de los lotes de las unidades (camiones lanzamisiles y
-- soldados) de la escena 3Dream. `addInstance` de 3Dream crea una matriz, una
-- tabla y una esfera por copia y sube cada copia con `setVertex`: con 80
-- camiones de 12 piezas y cientos de soldados eran miles de tablas por cuadro
-- (la mitad de la basura de la batalla). Aquí cada copia son 12 flotantes
-- escritos en un ByteData, que se sube con un solo `setVertices`.
--
-- Los números son los mismos que daban `Conversor:matriz` y `addInstance`:
-- el dibujo no cambia. La esfera del lote envuelve todas sus copias (con la
-- esfera de la pieza), para que 3Dream siga recortándolo.
--
-- Los lotes de las orugas de los tanques (`lote.conOruga`) llevan además, por
-- copia, `InstanceOruga` (desplazamiento y difuso; batalla/dream/oruga.lua):
-- 14 flotantes por copia en vez de 12.

local ffi = require('ffi')
local Conversor = require('batalla.dream.conversor')

local LoteUnidades = {}

local ANCHO = 12
local BYTES = ANCHO * 4
local ANCHO_ORUGA = 14

-- El de `instancedMesh:resize` de 3Dream.
local FORMATO = {
    { 'InstanceRotation0', 'float', 3 },
    { 'InstanceRotation1', 'float', 3 },
    { 'InstanceRotation2', 'float', 3 },
    { 'InstancePosition', 'float', 3 },
}

local FORMATO_ORUGA = {
    { 'InstanceRotation0', 'float', 3 },
    { 'InstanceRotation1', 'float', 3 },
    { 'InstanceRotation2', 'float', 3 },
    { 'InstancePosition', 'float', 3 },
    { 'InstanceOruga', 'float', 2 },
}

--- La malla de LÖVE de un lote de oruga con sus cinco atributos por copia
-- (sustituye a `getMesh` de las instancias de 3Dream, como instancias_tono.lua).
local function mallaOruga(self, nombre)
    nombre = nombre or 'mesh'
    local malla, cantidad = self.dreamLib.classes.instancedMesh.getMesh(self, nombre)
    if nombre == 'mesh' then
        malla:attachAttribute('InstanceOruga', self.instanceMesh, 'perinstance')
    end
    return malla, cantidad
end

--- Prepara el lote (de `Instancias.nuevas`, ya con su `resize`) para el
-- relleno por FFI. Con `activos` (una lista), el lote se apunta en ella al
-- recibir su primera copia: así quien tiene muchos lotes solo vacía y sube
-- los que se han usado.
function LoteUnidades.preparar(lote, activos)
    local capacidad = lote.instanceMesh:getVertexCount()
    local ancho = ANCHO
    if lote.conOruga then
        ancho = ANCHO_ORUGA
        lote.instanceMesh = love.graphics.newMesh(FORMATO_ORUGA, capacidad, 'points', 'dynamic')
        lote.getMesh = mallaOruga
    end
    lote.ffiAncho = ancho
    lote.ffiActivos = activos
    lote.ffiCapacidad = capacidad
    lote.ffiDatos = love.data.newByteData(capacidad * ancho * 4)
    lote.ffiPuntero = ffi.cast('float*', lote.ffiDatos:getFFIPointer())
    lote.ffiCantidad = 0
    -- Se mueven por su cuenta: el AA temporal no se fía de su historia
    -- (lib/3DreamEngine: `mesh.movil`, batalla/dream/temporal.lua).
    lote.movil = true
    LoteUnidades.vaciar(lote)
end

function LoteUnidades.vaciar(lote)
    lote.ffiCantidad = 0
    lote.ffiMinX, lote.ffiMinY, lote.ffiMinZ = math.huge, math.huge, math.huge
    lote.ffiMaxX, lote.ffiMaxY, lote.ffiMaxZ = -math.huge, -math.huge, -math.huge
    lote.ffiEscala2 = 0
end

--- Escribe en `destino` (12 flotantes) la copia de la matriz del juego `m`
-- (por filas, px, z arriba): columnas del giro en ejes de Dream y posición,
-- como Conversor:matriz seguido de addInstance.
function LoteUnidades.escribir(conversor, m, destino)
    local e = Conversor.escala
    destino[0], destino[1], destino[2] = m[1], m[9], m[5]
    destino[3], destino[4], destino[5] = m[3], m[11], m[7]
    destino[6], destino[7], destino[8] = m[2], m[10], m[6]
    destino[9], destino[10], destino[11] = (m[4] - conversor.cx) * e, m[12] * e, (m[8] - conversor.cy) * e
end

--- Añade al lote la copia escrita en `fuente` (12 flotantes). Devuelve si
-- cabía.
function LoteUnidades.anadir(lote, fuente)
    local n = lote.ffiCantidad
    if n >= lote.ffiCapacidad then
        return false
    end
    ffi.copy(lote.ffiPuntero + n * lote.ffiAncho, fuente, BYTES)
    lote.ffiCantidad = n + 1
    if n == 0 and lote.ffiActivos then
        local activos = lote.ffiActivos
        activos[#activos + 1] = lote
    end
    -- La columna más larga del giro: la escala de la pieza.
    local e2 = math.max(
        fuente[0] * fuente[0] + fuente[1] * fuente[1] + fuente[2] * fuente[2],
        fuente[3] * fuente[3] + fuente[4] * fuente[4] + fuente[5] * fuente[5],
        fuente[6] * fuente[6] + fuente[7] * fuente[7] + fuente[8] * fuente[8]
    )
    if e2 > lote.ffiEscala2 then
        lote.ffiEscala2 = e2
    end
    local x, y, z = fuente[9], fuente[10], fuente[11]
    if x < lote.ffiMinX then
        lote.ffiMinX = x
    end
    if x > lote.ffiMaxX then
        lote.ffiMaxX = x
    end
    if y < lote.ffiMinY then
        lote.ffiMinY = y
    end
    if y > lote.ffiMaxY then
        lote.ffiMaxY = y
    end
    if z < lote.ffiMinZ then
        lote.ffiMinZ = z
    end
    if z > lote.ffiMaxZ then
        lote.ffiMaxZ = z
    end
    return true
end

--- Amplía el lote a `capacidad` copias conservando las que ya tiene (y su
-- caja). Para quien no quiere perder copias cuando `anadir` devuelve false.
function LoteUnidades.crecer(lote, capacidad)
    local anterior = lote.ffiCapacidad
    if capacidad <= anterior then
        return
    end
    local ancho = lote.ffiAncho
    local formato = FORMATO
    if lote.conOruga then
        formato = FORMATO_ORUGA
    end
    lote.instanceMesh = love.graphics.newMesh(formato, capacidad, 'points', 'dynamic')
    local datos = love.data.newByteData(capacidad * ancho * 4)
    local puntero = ffi.cast('float*', datos:getFFIPointer())
    ffi.copy(puntero, lote.ffiPuntero, lote.ffiCantidad * ancho * 4)
    lote.ffiDatos = datos
    lote.ffiPuntero = puntero
    lote.ffiCapacidad = capacidad
end

--- Desplazamiento (eslabones) y difuso de la oruga de la última copia
-- añadida a un lote de oruga.
function LoteUnidades.oruga(lote, desplazamiento, difuso)
    local n = lote.ffiCantidad
    if not lote.conOruga or n == 0 then
        return
    end
    local destino = lote.ffiPuntero + (n - 1) * ANCHO_ORUGA
    destino[12] = desplazamiento
    destino[13] = difuso
end

--- Sube las copias y pone la esfera que las envuelve. Devuelve cuántas hay.
function LoteUnidades.subir(dream, lote)
    local n = lote.ffiCantidad
    lote.instancesCount = n
    if n == 0 then
        return 0
    end
    lote.instanceMesh:setVertices(lote.ffiDatos, 1, n)
    local origen = lote.originalBoundingSphere
    local c = origen.center
    -- El radio de la pieza y lo que su centro se aparta del pivote, por la
    -- mayor escala de sus copias.
    local margen = (origen.size + math.sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3])) * math.sqrt(lote.ffiEscala2)
    local dx, dy, dz = lote.ffiMaxX - lote.ffiMinX, lote.ffiMaxY - lote.ffiMinY, lote.ffiMaxZ - lote.ffiMinZ
    local centro = dream.vec3(
        (lote.ffiMinX + lote.ffiMaxX) * 0.5,
        (lote.ffiMinY + lote.ffiMaxY) * 0.5,
        (lote.ffiMinZ + lote.ffiMaxZ) * 0.5
    )
    lote.boundingSphere = dream:newBoundingSphere(centro, math.sqrt(dx * dx + dy * dy + dz * dz) * 0.5 + margen)
    return n
end

return LoteUnidades

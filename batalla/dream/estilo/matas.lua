-- Matas de hierba y arbustos de planos cruzados con textura recortada (de la
-- prueba de estilo de Camila, batalla/pruebas_estilo/matas.lua).
--
-- Mata: tres planos verticales cruzados (Texturas.mata), algo abiertos hacia
-- fuera. La normal va hacia arriba para que la mata tome la luz del suelo
-- que la rodea y no se vea como una tarjeta.
-- Arbusto: un manojo de ramas cortas de agujas (Texturas.rama) que salen del
-- centro hacia arriba y hacia fuera, como un enebro bajo.

local Geometria = require('batalla.dream.estilo.geometria')

local Matas = {}

function Matas.mata(semilla, detalle)
    local generador = love.math.newRandomGenerator(500 + semilla)
    local geometria = Geometria.nueva()
    local planos = detalle == 2 and 2 or 3
    local giro = generador:random() * math.pi
    for k = 0, planos - 1 do
        local angulo = giro + k / planos * math.pi
        local cx, cz = math.cos(angulo), math.sin(angulo)
        local ancho = 0.7 + generador:random() * 0.45
        local alto = 0.6 + generador:random() * 0.5
        local abre = 0.12
        geometria:cuadrilatero(
            { -cx * ancho, 0, -cz * ancho, 0, 1, 0, 0, 1 },
            { cx * ancho, 0, cz * ancho, 0, 1, 0, 1, 1 },
            { cx * ancho * (1 + abre), alto, cz * ancho * (1 + abre), 0, 1, 0, 1, 0 },
            { -cx * ancho * (1 + abre), alto, -cz * ancho * (1 + abre), 0, 1, 0, 0, 0 },
            true
        )
    end
    return geometria
end

-- Matas del pack StyleHex (FREE Stylized Forest Sample, de Fab; la licencia
-- de Fab permite usarlas en el juego): geometría de hojas sueltas pasada por
-- tools/blender/hierba_stylehex.py y su textura con el color del pack (verde
-- oscuro abajo, verde claro arriba). Normal hacia arriba, doble cara.
local pack, texturaPack

-- Sin el pack (la copia pública del código va sin él: licencia de Fab), la
-- hierba propia de planos cruzados (Matas.mata) con su textura pintada
-- (batalla/dream/estilo/recursos.lua).
Matas.hayPack = love.filesystem.getInfo('assets/batalla/hierba/matas_stylehex.lua', 'file') ~= nil

-- Alto de la hierba (m), a tamaño real (el dueño, 19-nov: «levanta más la
-- hierba, se ve muy bajita, de un metro»). Las matas del pack miden de 0,3 a
-- 0,7 m: cada una se lleva a este alto; de ancho crece menos (raíz del
-- factor), para que no salgan matas de 2 m de diámetro.
Matas.altoHierba = require('medidas').alto.hierba

function Matas.mataPack(variante, detalle)
    pack = pack or love.filesystem.load('assets/batalla/hierba/matas_stylehex.lua')()
    -- Cerca, el LOD0 del pack; lejos, su LOD2 (la mitad de hojas).
    local cual = pack[(variante - 1) % #pack + 1]
    local datos = cual[detalle == 1 and 1 or 3]
    local alto = 0
    for k = 2, #cual[1], 5 do
        alto = math.max(alto, cual[1][k])
    end
    local fy = Matas.altoHierba / alto
    local fx = math.sqrt(fy)
    local geometria = Geometria.nueva()
    for k = 1, #datos, 15 do
        local a = { datos[k] * fx, datos[k + 1] * fy, datos[k + 2] * fx, 0, 1, 0, datos[k + 3], datos[k + 4] }
        local b = { datos[k + 5] * fx, datos[k + 6] * fy, datos[k + 7] * fx, 0, 1, 0, datos[k + 8], datos[k + 9] }
        local c = { datos[k + 10] * fx, datos[k + 11] * fy, datos[k + 12] * fx, 0, 1, 0, datos[k + 13], datos[k + 14] }
        geometria:triangulo(a, b, c)
        geometria:triangulo(a, c, b)
    end
    return geometria
end

function Matas.texturaPack()
    if not texturaPack then
        texturaPack = love.graphics.newImage('assets/batalla/hierba/matas_stylehex.png', { mipmaps = true })
        texturaPack:setMipmapFilter('linear')
        texturaPack:setFilter('linear', 'linear', 8)
    end
    return texturaPack
end

function Matas.arbusto(semilla)
    local generador = love.math.newRandomGenerator(700 + semilla)
    local geometria = Geometria.nueva()
    local ramas = 9
    for k = 1, ramas do
        local azimut = k / ramas * math.pi * 2 + generador:random() * 0.5
        local subida = 0.5 + generador:random() * 0.6
        local largo = 1.0 + generador:random() * 0.6
        local dx, dz = math.cos(azimut), math.sin(azimut)
        local tx = dx * math.cos(subida) * largo
        local ty = math.sin(subida) * largo + 0.1
        local tz = dz * math.cos(subida) * largo
        local sx, sz = -dz * 0.4, dx * 0.4
        local nx, ny, nz = dx * 0.5, 0.85, dz * 0.5
        geometria:cuadrilatero(
            { -sx * 0.4, 0.05, -sz * 0.4, nx, ny, nz, 0, 0 },
            { tx - sx, ty, tz - sz, nx, ny, nz, 1, 0 },
            { tx + sx, ty, tz + sz, nx, ny, nz, 1, 1 },
            { sx * 0.4, 0.05, sz * 0.4, nx, ny, nz, 0, 1 },
            true
        )
    end
    return geometria
end

return Matas

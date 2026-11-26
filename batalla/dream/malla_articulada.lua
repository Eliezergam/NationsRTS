-- Mallas fundidas de un vehículo articulado (Valeria): todas las piezas de un
-- nivel de detalle con el mismo material (y la misma decisión de sombra) en
-- una sola malla de LÖVE, cada pieza en su pivote y sin mover. La w de
-- `VertexPosition` (1 en 3Dream, que no la usa) lleva la columna de la pieza
-- en la tabla de matrices (batalla/dream/tabla_piezas.lua): el sombreador
-- `piezasBatalla` (batalla/dream/piezas_lote.lua) coloca cada vértice con la
-- matriz de su pieza. Los vértices, normales, tangentes y UV son los mismos
-- que daría 3Dream pieza a pieza (se crean con su propio formato de malla).
--
-- `MallaArticulada.fundir` devuelve:
--   partes    { malla = malla de 3Dream, sombra = proyecta sombra }, una por
--             material y sombra, en el orden de `nombres`
--   usadas    columnas con alguna malla: { columna, nombre } (columna desde 0,
--             la de `nombres`)
--   radios    columna -> radio de la pieza alrededor de su pivote (unidades
--             de 3Dream): el centro de su esfera más su tamaño

local ffi = require('ffi')

local MallaArticulada = {}

--- Una malla de 3Dream con la malla de LÖVE fundida de las `mallas` del
-- grupo ({ malla, columna }), con el material de la primera.
local function fundirGrupo(dream, grupo)
    local primera = grupo.mallas[1].malla
    local formato = primera:getMeshFormat()
    local estructura = formato:getCStruct()
    local tamano = ffi.sizeof(estructura)
    local datosPorMalla = {}
    local vertices = 0
    local indices = 0
    for k, entrada in ipairs(grupo.mallas) do
        local malla = entrada.malla
        assert(malla:getMeshFormat() == formato, 'MallaArticulada: piezas con distinto formato de malla')
        assert(malla.meshDrawMode == 'triangles', 'MallaArticulada: solo mallas de triángulos')
        datosPorMalla[k] = formato:create(malla)
        vertices = vertices + malla.vertices:getSize()
        indices = indices + malla.faces:getSize() * 3
    end
    local datos = love.data.newByteData(tamano * vertices)
    local bytes = ffi.cast('uint8_t*', datos:getFFIPointer())
    local mapa = love.data.newByteData(4 * indices)
    local destinoIndices = ffi.cast('uint32_t*', mapa:getFFIPointer())
    local base = 0
    local cursor = 0
    for k, entrada in ipairs(grupo.mallas) do
        local malla = entrada.malla
        local cantidad = malla.vertices:getSize()
        ffi.copy(bytes + base * tamano, datosPorMalla[k]:getFFIPointer(), cantidad * tamano)
        local destino = ffi.cast(estructura .. '*', bytes + base * tamano)
        for v = 0, cantidad - 1 do
            destino[v].VertexPositionW = entrada.columna
        end
        local caras = malla.faces
        for c = 1, caras:getSize() do
            local cara = caras:get(c)
            destinoIndices[cursor] = base + cara.x - 1
            destinoIndices[cursor + 1] = base + cara.y - 1
            destinoIndices[cursor + 2] = base + cara.z - 1
            cursor = cursor + 3
        end
        base = base + cantidad
    end
    local malla = love.graphics.newMesh(formato.vertexFormat, datos, 'triangles', 'static')
    malla:setVertexMap(mapa, 'uint32')
    local resultado = dream:newMesh(primera:getMaterial())
    resultado.name = primera.name .. ' fundida'
    resultado.pixelShader = primera.pixelShader
    resultado.worldShader = primera.worldShader
    -- Sin setVertexShader: borraría la malla (clearMesh).
    resultado.vertexShader = dream:getShader('piezasBatalla')
    resultado.mesh = malla
    resultado.shadowVisibility = grupo.sombra
    return resultado
end

--- Radio de una pieza alrededor de su pivote: el de la esfera de cada malla
-- más lo que su centro se aparta del pivote.
local function radioPieza(pieza)
    local radio = 0
    for _, malla in ipairs(pieza.meshes) do
        local esfera = malla.boundingSphere
        if not esfera or esfera.size <= 0 then
            malla:updateBoundingSphere()
            esfera = malla.boundingSphere
        end
        local c = esfera.center
        local r = math.sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3]) + esfera.size
        radio = math.max(radio, r)
    end
    return radio
end

--- Funde las piezas `nombres` de `piezas` (cargadas con 3Dream). Opciones:
--   aparte     conjunto de piezas que no se funden (la insignia, con el
--              color de cada bando)
--   sinSombra  conjunto de piezas que no proyectan sombra
function MallaArticulada.fundir(dream, piezas, nombres, opciones)
    local aparte = opciones.aparte or {}
    local sinSombra = opciones.sinSombra or {}
    local grupos = {}
    local porClave = {}
    local usadas = {}
    local radios = {}
    for indice, nombre in ipairs(nombres) do
        local pieza = piezas[nombre]
        local columna = indice - 1
        if pieza and pieza.meshes and #pieza.meshes > 0 and not aparte[nombre] then
            usadas[#usadas + 1] = { columna = columna, nombre = nombre }
            radios[columna] = radioPieza(pieza)
            local sombra = not sinSombra[nombre]
            for _, malla in ipairs(pieza.meshes) do
                local material = malla:getMaterial()
                local porMaterial = porClave[material]
                if not porMaterial then
                    porMaterial = {}
                    porClave[material] = porMaterial
                end
                local grupo = porMaterial[sombra]
                if not grupo then
                    grupo = { sombra = sombra, mallas = {} }
                    porMaterial[sombra] = grupo
                    grupos[#grupos + 1] = grupo
                end
                grupo.mallas[#grupo.mallas + 1] = { malla = malla, columna = columna }
            end
        end
    end
    local partes = {}
    for _, grupo in ipairs(grupos) do
        partes[#partes + 1] = { malla = fundirGrupo(dream, grupo), sombra = grupo.sombra }
    end
    return { partes = partes, usadas = usadas, radios = radios }
end

return MallaArticulada

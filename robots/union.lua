-- Robots fundidos: cada robot en una malla por material (en vez de una por
-- pieza), para todas las escenas que usan robots/nucleo.lua (almacén y
-- batalla).
--
-- Un robot del almacén tiene unas 100 piezas y cada una 2-4 materiales: 3Dream
-- recorría unas 300 mallas por robot y cuadro, y otra vez en cada capa de
-- sombra, todo en el hilo de Lua. Aquí las piezas se juntan al cargar por
-- material y cada vértice guarda el número de su pieza; cada cuadro el juego
-- solo escribe una matriz por pieza (robots/sombreador_piezas.lua). Es lo que
-- hacen Unreal y Unity con sus mallas esqueléticas: un hueso rígido por pieza.
--
-- Lo de cada robot se respeta porque se funde después de `onLoad`: sus
-- materiales propios (los ojos que se ponen rojos, las siglas de su nación,
-- la sombra del suelo), qué mallas echan sombra y cuáles no. Una pieza oculta
-- (`visible = false`) va con matriz nula. La geometría fundida se comparte
-- entre los robots del mismo modelo; cada uno pone sus materiales.
--
-- ROBOTS_UNIDOS=0 vuelve al dibujo pieza a pieza (para comparar).

local ffi = require('ffi')
local dream = require('lib.3DreamEngine')

local Union = {}

Union.activa = os.getenv('ROBOTS_UNIDOS') ~= '0'

local sombreador
-- Geometría ya fundida: [clave] = Mesh de LÖVE con `VertexPieza` puesto.
local geometrias = {}

local FLOTANTES = 16
local BYTES = FLOTANTES * 4

local function getSombreador()
    if not sombreador then
        sombreador = dream:newShader('robots.sombreador_piezas')
    end
    return sombreador
end

--- Une las mallas `partes` ({ malla, indice }) en un Mesh de LÖVE con el
-- número de pieza en cada vértice.
local function fundir(partes)
    local formato = partes[1].malla:getMeshFormat()
    local estructura = formato:getCStruct()
    local tamano = ffi.sizeof(estructura)
    local totalVertices, totalIndices = 0, 0
    local datosPartes = {}
    for k, parte in ipairs(partes) do
        local datos = formato:create(parte.malla)
        datosPartes[k] = datos
        totalVertices = totalVertices + parte.malla.vertices:getSize()
        totalIndices = totalIndices + parte.malla.faces:getSize() * 3
    end
    local vertices = love.data.newByteData(tamano * totalVertices)
    local indices = love.data.newByteData(4 * totalIndices)
    local numeros = love.data.newByteData(4 * totalVertices)
    local pv = ffi.cast('uint8_t*', vertices:getFFIPointer())
    local pi = ffi.cast('uint32_t*', indices:getFFIPointer())
    local pn = ffi.cast('float*', numeros:getFFIPointer())
    local desplazamiento, i = 0, 0
    for k, parte in ipairs(partes) do
        local malla = parte.malla
        local cuantos = malla.vertices:getSize()
        ffi.copy(pv + desplazamiento * tamano, datosPartes[k]:getFFIPointer(), cuantos * tamano)
        datosPartes[k]:release()
        for v = 0, cuantos - 1 do
            pn[desplazamiento + v] = parte.indice
        end
        for _, cara in malla.faces:ipairs() do
            pi[i] = cara.x - 1 + desplazamiento
            pi[i + 1] = cara.y - 1 + desplazamiento
            pi[i + 2] = cara.z - 1 + desplazamiento
            i = i + 3
        end
        desplazamiento = desplazamiento + cuantos
    end
    local mesh = love.graphics.newMesh(formato.vertexFormat, vertices, 'triangles', 'static')
    mesh:setVertexMap(indices, 'uint32')
    local mallaNumeros = love.graphics.newMesh({ { 'VertexPieza', 'float', 1 } }, numeros, 'triangles', 'static')
    mesh:attachAttribute('VertexPieza', mallaNumeros)
    vertices:release()
    indices:release()
    numeros:release()
    return { mesh = mesh, numeros = mallaNumeros }
end

--- Las mallas del robot en el nivel `nivel` (0 de cerca, 1-2 las copias de
-- lejos), agrupadas por material y visibilidad. nil si alguna no se puede
-- fundir (sin geometría en bruto, o demasiadas piezas): entonces se dibuja
-- pieza a pieza como siempre.
local function construir(robot, nivel)
    if #robot.orden > getSombreador().maxPiezas then
        return nil
    end
    local grupos, orden = {}, {}
    local radiosLocales = {}
    for indice, p in ipairs(robot.orden) do
        local objeto = p.objeto
        if nivel > 0 then
            objeto = p.objetosLod[nivel]
        end
        if objeto then
            if next(objeto.objects or {}) then
                return nil
            end
            for _, malla in pairs(objeto.meshes or {}) do
                if not malla.vertices or not malla.faces or malla.instanceMesh or malla.vertexShader then
                    return nil
                end
                local material = malla.material
                -- Por nombre: el clon de 3Dream da a cada pieza su propia copia
                -- del material, iguales entre sí (las que cambia el robot, como
                -- los brillos de los ojos, cambian todas a la vez).
                local clave = tostring(material.name or material) .. (malla.shadowVisibility and 's' or 'n') .. (malla.renderVisibility and 'v' or 'o')
                local grupo = grupos[clave]
                if not grupo then
                    grupo = {
                        material = material,
                        sombra = malla.shadowVisibility,
                        vista = malla.renderVisibility,
                        partes = {},
                    }
                    grupos[clave] = grupo
                    orden[#orden + 1] = grupo
                end
                -- Lo que sobresale la malla del origen de su pieza (para la
                -- esfera de recorte de todo el robot).
                local esfera = malla.boundingSphere
                local c = esfera and esfera.center
                local r = c and (math.sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3]) + esfera.size) or 0
                radiosLocales[indice] = math.max(radiosLocales[indice] or 0, r)
                -- Las piezas del robot en el orden de `robot.orden` (0 la primera).
                grupo.partes[#grupo.partes + 1] = { malla = malla, indice = indice - 1, nombre = p.nombre }
            end
        end
    end
    local unido = {
        datos = love.data.newByteData(getSombreador().maxPiezas * BYTES),
        objeto = dream:newObject(),
        esferas = {},
        radiosLocales = radiosLocales,
    }
    unido.p = ffi.cast('float*', unido.datos:getFFIPointer())
    -- Se mueve: fuera de las sombras fijas de las lámparas.
    unido.objeto.dynamic = true
    for k, grupo in ipairs(orden) do
        local firma = { robot.nombreModelo, nivel, grupo.material.name or '', grupo.sombra and 's' or 'n', grupo.vista and 'v' or 'o' }
        for _, parte in ipairs(grupo.partes) do
            firma[#firma + 1] = parte.indice .. ':' .. tostring(parte.nombre) .. ':' .. tostring(parte.malla.name)
        end
        local clave = table.concat(firma, '|')
        geometrias[clave] = geometrias[clave] or fundir(grupo.partes)
        local malla = dream:newMesh(grupo.material)
        malla.name = 'robotUnido'
        malla.mesh = geometrias[clave].mesh
        malla.vertexShader = getSombreador()
        malla.shadowVisibility = grupo.sombra
        malla.renderVisibility = grupo.vista
        malla.piezasDatos = unido.datos
        malla.piezasBytes = #robot.orden * BYTES
        malla.boundingSphere = dream:newBoundingSphere(dream.vec3(0, 0, 0), 0)
        unido.objeto.meshes[k] = malla
        unido.esferas[k] = malla.boundingSphere
    end
    return unido
end

--- Funde ya todos los niveles de detalle del robot, para que no se haga en
-- mitad de la partida: la primera fusión de cada modelo y nivel tarda de 30
-- ms a más de 1 s (27-nov, guerra de 40 robots: el soldado de cerca, 1.064
-- ms, era un tirón de 1,1 s en plena batalla). La escena la llama al cargar,
-- con los robots ya creados y puestos a punto.
function Union.preparar(robot)
    if not Union.activa then
        return
    end
    robot.unidos = robot.unidos or {}
    local niveles = { 0 }
    for nivel in pairs(robot.lods or {}) do
        niveles[#niveles + 1] = nivel
    end
    for _, nivel in ipairs(niveles) do
        if robot.unidos[nivel] == nil then
            robot.unidos[nivel] = construir(robot, nivel) or false
        end
    end
end

--- Escribe la matriz de cada pieza del robot (en 3Dream) y lo pide a 3Dream.
-- false si este robot no se puede fundir (se dibuja pieza a pieza).
function Union.dibujar(robot, nivel, aDream, ...)
    if not Union.activa then
        return false
    end
    robot.unidos = robot.unidos or {}
    local unido = robot.unidos[nivel]
    if unido == nil then
        unido = construir(robot, nivel) or false
        robot.unidos[nivel] = unido
    end
    if not unido then
        return false
    end
    -- Esfera de recorte: alrededor de la primera pieza, con el radio de lo
    -- que ocupan las piezas este cuadro (medido sobre sus matrices).
    local p = unido.p
    local radiosLocales = unido.radiosLocales
    local cx, cy, cz
    local radio = 0
    for indice, pieza in ipairs(robot.orden) do
        local k = (indice - 1) * FLOTANTES
        if pieza:getVisibleArbol() then
            local m = aDream(pieza.mundo, robot, ...)
            for j = 1, FLOTANTES do
                p[k + j - 1] = m[j]
            end
            if not cx then
                cx, cy, cz = m[4], m[8], m[12]
            end
            local radioLocal = radiosLocales[indice]
            if radioLocal then
                local escala = math.sqrt(m[1] * m[1] + m[5] * m[5] + m[9] * m[9])
                local dx, dy, dz = m[4] - cx, m[8] - cy, m[12] - cz
                local d = math.sqrt(dx * dx + dy * dy + dz * dz) + radioLocal * escala
                if d > radio then
                    radio = d
                end
            end
        else
            for j = 0, FLOTANTES - 1 do
                p[k + j] = 0
            end
        end
    end
    if not cx then
        return true
    end
    for _, esfera in ipairs(unido.esferas) do
        esfera.center[1], esfera.center[2], esfera.center[3] = cx, cy, cz
        esfera.size = radio
    end
    dream:draw(unido.objeto)
    return true
end

return Union

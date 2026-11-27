-- Comparador de la escena de batalla con 3DreamEngine. Reutiliza la misma
-- simulación, terreno, cámara y controles de `batalla.escena`; solo cambia la
-- preparación de materiales y el dibujo 3D.

local Escena = require('batalla.escena')
local Simulacion = require('mundo.simulacion')
local Malla = require('batalla.malla')
local Estelas = require('batalla.estelas')
local Modelos3d = require('mundo.modelos3d')
local Tropas = require('batalla.tropas')
local Lanzamisiles = require('batalla.lanzamisiles')
-- Orugas y tren de rodaje de los tanques (batalla/orugas.lua).
local Orugas = require('batalla.orugas')
local Conversor = require('batalla.dream.conversor')
local CatalogoModelos = require('assets.modelos3d.catalogo')
-- Sol, luna y cielo según la hora del mundo (Valeria, batalla/dream/luz.lua).
local Luz = require('batalla.dream.luz')
local Carga = require('batalla.carga')
local TexturaTerreno = require('batalla.dream.textura_terreno')
local Fisica = require('batalla.fisica')
local RobotsBatalla = require('batalla.robots.robot')
local Patrulla = require('batalla.robots.patrulla')
local Union = require('robots.union')
local Mundo = require('batalla.robots.mundo')
local VistaRobots = require('batalla.robots.vista')
local Rayos = require('batalla.dream.rayos')
local Sonido = require('batalla.dream.sonido')
local VegetacionDream = require('batalla.dream.vegetacion')
local Instancias = require('batalla.dream.instancias')
local Visibilidad = require('batalla.dream.visibilidad')
local EfectosDream = require('batalla.dream.efectos')
local EstelasAvion = require('batalla.dream.estelas_avion')
-- Estilo de la prueba de Camila (batalla/pruebas_estilo): texturas, pinos,
-- rocas, matas, sombras por cascada y calidad (Valeria, batalla/dream/estilo).
local Calidad = require('batalla.dream.calidad')
local Recursos = require('batalla.dream.estilo.recursos')
local Mascara = require('batalla.dream.estilo.mascara')
local SombraCascadas = require('batalla.dream.estilo.sombra_cascadas')
local LoteUnidades = require('batalla.dream.lote_unidades')
local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
local TerrenoTrozos = require('batalla.dream.terreno_trozos')
local NivelDetalle = require('batalla.dream.nivel_detalle')
local TerrenoPBR = require('batalla.dream.terreno_pbr')
local RocaPBR = require('batalla.dream.estilo.roca_pbr')
local Viento = require('batalla.dream.viento')
local TexturasPbr = require('batalla.dream.texturas_pbr')
-- Curva tonal fílmica de la imagen final (batalla/dream/tono.lua).
local Escalado = require('batalla.dream.escalado')
local Tono = require('batalla.dream.tono')
-- AA temporal (batalla/dream/temporal.lua), según la calidad.
local Temporal = require('batalla.dream.temporal')
-- Humo del escape del camión de 4 misiles (batalla/dream/humo_escape.lua).
local HumoEscape = require('batalla.dream.humo_escape')
-- Camión de 4 misiles: piezas fundidas por material y sus matrices en una
-- textura (batalla/dream/lote_articulado.lua).
local MallaArticulada = require('batalla.dream.malla_articulada')
local LoteArticulado = require('batalla.dream.lote_articulado')
local TablaPiezas = require('batalla.dream.tabla_piezas')
local ffi = require('ffi')

local dream = require('lib.3DreamEngine')

local EscenaDream = {}
EscenaDream.__index = EscenaDream
setmetatable(EscenaDream, { __index = Escena })

local configurado = false

-- Fracción del día fija para las capturas (`--hora`); nil: la del reloj del mundo.
EscenaDream.fraccionFija = nil
-- Nivel de detalle fijo del terreno (pruebas); nil: según la distancia.
EscenaDream.nivelTerrenoFijo = nil
-- Nivel de detalle fijo de los vehículos (pruebas); nil: según su tamaño en pantalla.
EscenaDream.nivelUnidadFijo = nil
-- ¿Proyecta sombra el tren de rodaje (ruedas, piñón, guía, rodillos) de los
-- tanques de cerca (LOD0)? Desde LOD1 nunca. Su sombra cae dentro de la del
-- casco y la oruga: con y sin ella, las capturas de cerca a ras de suelo
-- difieren en 1 o 2 píxeles (batalla/pruebas_orugas) y ahorra unos 240
-- dibujos con 10 + 10 tanques.
EscenaDream.sombraTrenCerca = false

local function configurarMotor()
    if configurado then
        return
    end
    -- Cielo, luz del cielo, bruma, oclusión y resplandor según la calidad:
    -- batalla/dream/luz.lua.
    Luz.configurarMotor()
    dream:registerShader('batalla/dream/textura_terreno', 'terrenoNatural')
    -- El suelo con las texturas PBR de Camila (batalla/dream/terreno_pbr.lua).
    TerrenoPBR.registrar(dream)
    Recursos.registrar(dream)
    -- La oruga de los tanques se desplaza en su u (batalla/dream/oruga.lua).
    dream:registerShader('batalla/dream/oruga', 'orugaBatalla')
    -- Las piezas del camión de 4 misiles, cada una con su matriz de la tabla
    -- (batalla/dream/piezas_lote.lua).
    dream:registerShader('batalla/dream/piezas_lote', 'piezasBatalla')
    -- Texturas PBR horneadas de las unidades (tools/blender/pbr_unidades.py):
    -- los .glb nombran su material y 3Dream lo toma de aquí.
    BibliotecaPbr.cargar(dream, 'assets/modelos3d/materiales')
    dream:init()
    dream.camera:setFov(40)
    dream.camera:setNear(0.1)
    dream.camera:setFar(900)
    Visibilidad.instalar(dream.camera)
    configurado = true
end

local function cargarDatos(archivo)
    return love.filesystem.load(archivo)()
end

local function crearUvsDePosicion(malla)
    local cantidad = malla.vertices:getSize()
    local uvs = dream:newBuffer('vec2', 'float', cantidad)
    for indice = 1, cantidad do
        local vertice = malla.vertices:get(indice)
        local uv = uvs.buffer[indice - 1]
        uv.x = vertice.x + vertice.z * 0.37
        uv.y = vertice.y + vertice.z * 0.23
    end
    return uvs
end

--- Piezas de un modelo de vértices; con `tono` < 1, oscurecido (averiado).
local function convertirModelo(conversor, archivo, color, nombre, tono)
    local datos = cargarDatos(archivo)
    local piezas = {}
    for _, pieza in ipairs(datos.piezas) do
        piezas[pieza.nombre] = conversor:desdeVertices(pieza.vertices, color, nombre .. '_' .. pieza.nombre, tono)
    end
    return piezas
end

local function asegurarUvs(piezas)
    for _, pieza in pairs(piezas) do
        if pieza.meshes then
            for _, malla in ipairs(pieza.meshes) do
                local necesitaUvs = not malla.texCoords
                if not necesitaUvs and malla.texCoords.getSize then
                    necesitaUvs = malla.texCoords:getSize() < malla.vertices:getSize()
                end
                if necesitaUvs then
                    malla.texCoords = crearUvsDePosicion(malla)
                end
            end
        end
    end
end

--- Los .glb de los niveles 2 y 3 nombran su material con el sufijo que pone
-- Blender al duplicar (`unidadT55Lod2.001`); la biblioteca (biblioteca_pbr.lua)
-- lo tiene sin él. Sin esto, 3Dream no lo encuentra y la pieza sale blanca.
local function enlazarMateriales(piezas)
    for _, pieza in pairs(piezas) do
        for _, malla in ipairs(pieza.meshes or {}) do
            local material = malla:getMaterial()
            local base = material and material.name and material.name:match('^(.-)%.%d%d%d$')
            if base and dream.materialLibrary[base] then
                malla:setMaterial(dream.materialLibrary[base])
            end
        end
    end
end

--- El GLB conserva las UV del pack. El Lua mantiene el contrato de pivotes
-- y la malla de respaldo para el renderizador anterior. Los vehículos no
-- llevan la franja de la nación (decisión del dueño): la pieza `insignia`
-- no se carga, así que ni se dibuja ni da sombra, y los dos bandos comparten
-- los lotes de sus piezas.
local function cargarSynty(archivo)
    local ruta = archivo:gsub('%.lua$', '')
    local objeto = dream:loadObject(ruta, { decodeBlenderNames = false })
    asegurarUvs(objeto.objects)
    enlazarMateriales(objeto.objects)
    objeto.objects.insignia = nil
    return objeto.objects
end

--- Tanque con texturas horneadas (el .glb del modelo del catálogo, `ruta`
-- sin extensión, assets/modelos3d/catalogo.lua): piezas casco, torreta y
-- canon en el origen de su pivote, como el camión. Sin la franja de la
-- nación (`NacionTanque`): sus mallas no se cargan (decisión del dueño).
-- Con `tono` < 1 (averiado) queda quemado como los camiones destruidos: sin
-- brillo (sin el mapa de rugosidad y metálico) y con el color (0,6, 0,5, 0,45)
-- x tono, que con 0,3 es el mismo 0,18 / 0,15 / 0,13 de `instanciarCamion`;
-- solo oscurecer el albedo apenas se notaba con la luz del cielo (-15 %).
-- Sin el .glb, el modelo de vértices del mismo nombre.
local function cargarTanque(conversor, color, nombre, tono, ruta)
    if not love.filesystem.getInfo(ruta .. '.glb') then
        return convertirModelo(conversor, ruta .. '.lua', color, nombre, tono)
    end
    local objeto = dream:loadObject(ruta, { decodeBlenderNames = false })
    asegurarUvs(objeto.objects)
    enlazarMateriales(objeto.objects)
    for _, pieza in pairs(objeto.objects) do
        local mallas = {}
        for _, malla in ipairs(pieza.meshes or {}) do
            local material = malla:getMaterial()
            -- Sin la franja de la nación (`NacionTanque`), como el camión.
            if material.name:lower():sub(1, 6) ~= 'nacion' then
                if tono then
                    material = material:clone()
                    material.name = material.name .. ' averiado'
                    material:setMaterialTexture(nil)
                    material:setRoughness(1)
                    material:setMetallic(0.05)
                    material:setColor(0.6 * tono, 0.5 * tono, 0.45 * tono, 1)
                    malla:setMaterial(material)
                end
                mallas[#mallas + 1] = malla
            end
        end
        if pieza.meshes then
            pieza.meshes = mallas
        end
    end
    return objeto.objects
end

--- Un lote por articulación, modelo y bando: 80 camiones no requieren 960
-- dibujos. `nombres`: las piezas del modelo (las de su `Lanzamisiles`).
local function instanciarCamion(piezas, lotes, quemado, nombres)
    local resultado = {}
    for _, nombre in ipairs(nombres) do
        resultado[nombre] = {}
        for _, malla in ipairs(piezas[nombre] and piezas[nombre].meshes or {}) do
            local instancias = Instancias.nuevas(dream, malla)
            if quemado then
                local material = instancias:getMaterial():clone()
                material:setColor(0.18, 0.15, 0.13, 1)
                material:setRoughness(1)
                material:setMetallic(0.05)
                instancias:setMaterial(material)
            end
            instancias:resize(Tropas.maxPorBando)
            resultado[nombre][#resultado[nombre] + 1] = instancias
            lotes[#lotes + 1] = instancias
        end
    end
    return resultado
end

-- Piezas del contrato de los tanques (assets/modelos3d/catalogo.lua).
local PIEZAS_TANQUE = { 'casco', 'torreta', 'canon' }

--- Piezas de un tanque: las tres de siempre y, si tiene `orugas`
-- (batalla/orugas.lua), las que giran y las dos orugas. También los conjuntos
-- de los nombres de las orugas (sus lotes llevan el sombreador de la oruga) y
-- de las piezas que giran.
local function piezasTanque(orugas)
    local nombres = {}
    local deOruga = {}
    local giran = {}
    for _, nombre in ipairs(PIEZAS_TANQUE) do
        nombres[#nombres + 1] = nombre
    end
    if orugas then
        for _, nombre in ipairs(orugas.giran) do
            nombres[#nombres + 1] = nombre
            giran[nombre] = true
        end
        for _, nombre in ipairs(orugas.orugas) do
            nombres[#nombres + 1] = nombre
            deOruga[nombre] = true
        end
    end
    return nombres, deOruga, giran
end

--- Lote de una oruga: su u se desplaza por copia (batalla/dream/oruga.lua,
-- lote_unidades.lua).
local function marcarOruga(instancias)
    instancias:setVertexShader('orugaBatalla')
    instancias.conOruga = true
end

--- ¿Son iguales los búferes `a` y `b` de 3Dream: posiciones (con `conZ`) o UV?
local function mismoBufer(a, b, conZ)
    if not a or not b or a:getSize() ~= b:getSize() then
        return a == b
    end
    for i = 0, a:getSize() - 1 do
        local pa, pb = a.buffer[i], b.buffer[i]
        local d = math.abs(pa.x - pb.x) + math.abs(pa.y - pb.y)
        if conZ then
            d = d + math.abs(pa.z - pb.z)
        end
        if d > 1e-5 then
            return false
        end
    end
    return true
end

--- ¿Tienen las piezas `a` y `b` la misma forma (las mismas mallas, con los
-- mismos vértices respecto a su pivote y el mismo material)? Con `conUv`,
-- también las mismas UV (la misma imagen de cerca).
local function mismaForma(a, b, conUv)
    local ma, mb = a.meshes or {}, b.meshes or {}
    if #ma ~= #mb or #ma == 0 then
        return false
    end
    for k = 1, #ma do
        local va, vb = ma[k].vertices, mb[k].vertices
        if not va or not vb or va:getSize() ~= vb:getSize() then
            return false
        end
        if ma[k]:getMaterial() ~= mb[k]:getMaterial() then
            return false
        end
        if not mismoBufer(va, vb, true) then
            return false
        end
        if conUv and not mismoBufer(ma[k].texCoords, mb[k].texCoords) then
            return false
        end
    end
    return true
end

--- Entre las piezas `candidatas` (conjunto de nombres) de `piezas`, las que
-- tienen la forma de otra anterior en `nombres`: nombre -> la primera de su
-- forma. Y cuántas comparten cada forma. `conUv`: como en mismaForma.
local function mismasFormas(piezas, nombres, candidatas, conUv)
    local igual = {}
    local cuantas = {}
    local primeras = {}
    for _, nombre in ipairs(nombres) do
        local pieza = piezas[nombre]
        if candidatas[nombre] and pieza then
            for _, otra in ipairs(primeras) do
                if mismaForma(piezas[otra], pieza, conUv) then
                    igual[nombre] = otra
                    cuantas[otra] = cuantas[otra] + 1
                    break
                end
            end
            if not igual[nombre] then
                primeras[#primeras + 1] = nombre
                cuantas[nombre] = 1
            end
        end
    end
    return igual, cuantas
end

--- Lotes de un nivel de un tanque, uno por pieza y malla: 40 tanques de cuatro
-- modelos no piden un dibujo por pieza y tanque. `nombres`: sus piezas
-- (piezasTanque); las que el nivel no tiene quedan sin lotes. `o`:
--   alfa       de tramado: el fundido al cambiar de nivel (nivel_detalle.lua)
--   deOruga    las orugas, con la oruga que se desplaza (si no van averiadas)
--   previos    los lotes del otro bando para el mismo nivel y estado: sin la
--              franja de la nación todas las piezas son iguales en los dos
--              bandos y usan esos (un dibujo para los dos); por eso llevan
--              sitio para los dos
--   sinSombra  piezas que no proyectan sombra
--   igual      pieza -> otra anterior con su misma forma, cuyos lotes usa (las
--              ruedas de un lado de lejos: una sola malla con su horneado);
--              `cuantas` dice cuántas copian a cada una (su sitio)
--   quemado    ennegrecido (el camión destruido, como instanciarCamion)
-- También los camiones de 4 misiles (lotesCamionArticulado).
local function lotesTanque(piezas, nombres, lotes, o)
    local resultado = {}
    for _, nombre in ipairs(nombres) do
        local pieza = piezas[nombre]
        if o.igual and o.igual[nombre] then
            resultado[nombre] = resultado[o.igual[nombre]]
        elseif o.previos and o.previos[nombre] and pieza then
            resultado[nombre] = o.previos[nombre]
        else
            resultado[nombre] = {}
            for _, malla in ipairs(pieza and pieza.meshes or {}) do
                local instancias = Instancias.nuevas(dream, malla)
                if o.alfa or o.quemado then
                    local material = instancias:getMaterial():clone()
                    local c = material.color or { 1, 1, 1, 1 }
                    if o.quemado then
                        material:setColor(0.18, 0.15, 0.13, 1)
                        material:setRoughness(1)
                        material:setMetallic(0.05)
                        c = material.color
                    end
                    if o.alfa then
                        material:setColor(c[1], c[2], c[3], o.alfa)
                        material:setDither()
                    end
                    instancias:setMaterial(material)
                end
                instancias:resize(Tropas.maxPorBando * 2 * (o.cuantas and o.cuantas[nombre] or 1))
                if o.deOruga and o.deOruga[nombre] then
                    marcarOruga(instancias)
                end
                if o.sinSombra and o.sinSombra[nombre] then
                    instancias:setShadowVisibility(false)
                end
                resultado[nombre][#resultado[nombre] + 1] = instancias
                lotes[#lotes + 1] = instancias
            end
        end
    end
    return resultado
end

-- Piezas del camión de 4 misiles que no proyectan sombra: quedan dentro de
-- la del chasis y las ruedas (amortiguadores, puntas de eje y ventiladores
-- detrás de la rejilla).
-- La luz encendida (`balizaLuz`) tampoco: su sombra parpadearía con ella.
local SIN_SOMBRA_CAMION = { 'amortiguador', 'suspension', 'ventilador', 'balizaLuz' }

-- La insignia iría en sus propios lotes, por bando; cargarSynty ya no la
-- carga (los vehículos van sin franja), así que sus lotes quedan vacíos.
local INSIGNIA = { 'insignia' }

--- Lotes de un nivel del camión de 4 misiles (batalla/articulacion_camion.lua):
-- todas las piezas del mismo material en una malla y un lote por variante
-- (normal, destruido y cada paso del fundido), con las matrices de las
-- piezas en `tabla` (batalla/dream/lote_articulado.lua): un dibujo por
-- material y nivel en vez de uno por pieza. Los dos bandos comparten esos
-- lotes (`otro`: el nivel del mismo archivo del otro bando); la insignia va
-- aparte, por bando. `activos`: los lotes articulados con copias en el cuadro.
local function lotesCamionArticulado(piezas, nombres, lotes, otro, activos)
    local n = { normal = {}, destruidos = {}, fundidos = {} }
    if otro then
        n.piezasVista = otro.piezasVista
        n.normal.lote = otro.normal.lote
        n.destruidos.lote = otro.destruidos.lote
        for paso in ipairs(NivelDetalle.pasos) do
            n.fundidos[paso] = { lote = otro.fundidos[paso].lote }
        end
    else
        local sinSombra = {}
        for _, nombre in ipairs(nombres) do
            for _, prefijo in ipairs(SIN_SOMBRA_CAMION) do
                if nombre:sub(1, #prefijo) == prefijo then
                    sinSombra[nombre] = true
                end
            end
        end
        local fundida = MallaArticulada.fundir(dream, piezas, nombres, {
            aparte = { insignia = true },
            sinSombra = sinSombra,
        })
        -- Las piezas que tiene el nivel: solo esas compone la articulación
        -- mientras se dibuja con él (Lanzamisiles:verPiezas).
        n.piezasVista = { insignia = piezas.insignia and true or nil }
        for _, usada in ipairs(fundida.usadas) do
            n.piezasVista[usada.nombre] = true
        end
        local capacidad = Tropas.maxPorBando * 2
        n.normal.lote = LoteArticulado.nuevo(dream, fundida, capacidad, { activos = activos })
        n.destruidos.lote = LoteArticulado.nuevo(dream, fundida, capacidad, { activos = activos, quemado = true })
        for paso, alfa in ipairs(NivelDetalle.pasos) do
            n.fundidos[paso] = {
                lote = LoteArticulado.nuevo(dream, fundida, capacidad, { activos = activos, alfa = alfa }),
            }
        end
    end
    -- La insignia de este bando (destruido no se ve: Lanzamisiles.visible).
    n.normal.insignia = lotesTanque(piezas, INSIGNIA, lotes, {})
    n.destruidos.insignia = {}
    for paso, alfa in ipairs(NivelDetalle.pasos) do
        n.fundidos[paso].insignia = lotesTanque(piezas, INSIGNIA, lotes, { alfa = alfa })
    end
    return n
end

--- Lotes de las piezas `nombres` de un modelo cargado, uno por malla, con
-- `capacidad` copias. Las piezas que el nivel no tiene (el más sencillo va en
-- una pieza) quedan sin lotes. Con `alfa`, de tramado: el fundido al cambiar
-- de nivel (batalla/dream/nivel_detalle.lua). Con `quemado`, ennegrecido.
local function instanciarPiezas(piezas, nombres, lotes, capacidad, alfa, quemado)
    local resultado = {}
    for _, nombre in ipairs(nombres) do
        resultado[nombre] = {}
        for _, malla in ipairs(piezas[nombre] and piezas[nombre].meshes or {}) do
            local instancias = Instancias.nuevas(dream, malla)
            if alfa or quemado then
                local material = instancias:getMaterial():clone()
                local c = material.color or { 1, 1, 1, 1 }
                if quemado then
                    material:setColor(0.18, 0.15, 0.13, 1)
                    material:setRoughness(1)
                    material:setMetallic(0.05)
                    c = material.color
                end
                if alfa then
                    material:setColor(c[1], c[2], c[3], alfa)
                    material:setDither()
                end
                instancias:setMaterial(material)
            end
            instancias:resize(capacidad)
            resultado[nombre][#resultado[nombre] + 1] = instancias
            lotes[#lotes + 1] = instancias
        end
    end
    return resultado
end

--- Variantes de fundido de un nivel: una por alfa de NivelDetalle.pasos.
local function instanciarFundidos(piezas, nombres, lotes, capacidad)
    local fundidos = {}
    for paso, alfa in ipairs(NivelDetalle.pasos) do
        fundidos[paso] = instanciarPiezas(piezas, nombres, lotes, capacidad, alfa)
    end
    return fundidos
end

--- ¿Tiene mallas de 3Dream cada pieza de `nombres` que exista en `piezas`?
-- (El modelo de vértices de respaldo no las tiene: se dibuja suelto.)
local function conMallas(piezas, nombres)
    local alguna = false
    for _, nombre in ipairs(nombres) do
        if piezas[nombre] then
            if not piezas[nombre].meshes then
                return false
            end
            alguna = true
        end
    end
    return alguna
end

local function crearEsfera(conversor, cx, cy, opciones)
    opciones = opciones or {}
    local malla = Malla.nueva(60)
    malla:icosaedro(cx, cy, 0, 10, 10, opciones.color or { 1, 1, 1 })
    opciones.rugosidad = opciones.rugosidad or 0.7
    return conversor:desdeMalla(malla:crear(), opciones)
end

--- Modelos de vehículo que salen en el combate (en el campo o en la
-- reserva), por bando y tipo, en orden de catálogo: { [bando] = { tanque = {
-- id, ... }, lanzacohetes = { id, ... } } }.
local function modelosEnCombate(tropas)
    local out = {}
    for indice = 1, 2 do
        local hay = { tanque = {}, lanzacohetes = {} }
        local datos = tropas.bandos[indice]
        for _, lista in ipairs({ datos.todas, datos.cola }) do
            for _, v in ipairs(lista) do
                if hay[v.tipo] then
                    hay[v.tipo][v.modelo or Tropas.modeloPorDefecto(v.tipo)] = true
                end
            end
        end
        local r = { tanque = {}, lanzacohetes = {} }
        for tipo, tropa in pairs({ tanque = 'tanques', lanzacohetes = 'lanzacohetes' }) do
            for _, id in ipairs(Simulacion.Armamento.modelos(tropa)) do
                if hay[tipo][id] then
                    r[tipo][#r[tipo] + 1] = id
                end
            end
        end
        out[indice] = r
    end
    return out
end

local misilCargado
--- La pieza que vuela como misil (la `misil` del modelo del catálogo de
-- armamento, del .glb del camión con robot conductor) y la escala de su malla
-- en unidades de 3Dream por metro; nil si falta el modelo.
function EscenaDream.misilEnVuelo()
    if misilCargado == nil then
        misilCargado = false
        local entrada = CatalogoModelos.modelo(Tropas.modeloPorDefecto('lanzacohetes'))
        local modelo = entrada and entrada.robot and RobotsBatalla.cargarModelo(entrada.archivo)
        local pieza = modelo and modelo.base.objects[entrada.misil]
        if pieza then
            misilCargado = pieza
        else
            print('Batalla: sin el modelo del misil en vuelo (' .. tostring(entrada and entrada.archivo) .. ')')
        end
    end
    return misilCargado or nil, Conversor.escala * 10
end

function EscenaDream.nueva(mundo, combate)
    configurarMotor()
    local inicio = love.timer.getTime()
    -- Las texturas del estilo se pintan en un hilo mientras se genera el suelo.
    Recursos.empezar()
    local self = Escena.nueva(mundo, combate)
    setmetatable(self, EscenaDream)
    Carga.mostrar('Preparando colisiones físicas', 0.955, true)
    self.fisica = Fisica.nueva(self.suelo, self.tropas.unidades)
    self.tropas:usarFisica(self.fisica)
    Carga.mostrar('Preparando materiales e iluminación', 0.96, true)
    self.conversor = Conversor.nuevo(dream, combate.cx, combate.cy)
    self.calidad = Calidad.actual()
    -- Sol y luna de la extensión sky a la hora del mundo (batalla/dream/luz.lua),
    -- con las sombras de la calidad elegida.
    self.solDream, self.lunaDream = Luz.nuevas()
    self.tono = Tono.nuevo()
    -- Bordes según la calidad (Luz.configurarMotor ya quitó el MSAA si toca).
    if Luz.suavizado == 'taa' then
        self.temporal = Temporal.nuevo()
        -- La luz rebotada lee el cuadro anterior: rebotes múltiples (rebote.lua).
        if Luz.oclusion and Luz.oclusion.rebote then
            Luz.oclusion.rebote.temporal = self.temporal
        end
        Tono.afilado = self.calidad.afilado or 0
        TexturasPbr.nitidezMip = self.calidad.nitidezMip or 0
    else
        self.temporal = nil
        Tono.afilado = 0
        TexturasPbr.nitidezMip = 0
    end
    -- Escalado con nitidez (FSR 1, batalla/dream/escalado.lua): la escena a
    -- `escalaRender` de la pantalla. Afila RCAS: sin el afilado del tono.
    -- `BATALLA_ESCALA=<0..1>` la cambia (1 = sin escalado), para comparar.
    local escala = Escalado.escala(self.calidad)
    if escala < 1 then
        self.calidad = setmetatable({ escalaRender = escala }, { __index = self.calidad })
        self.escalado = Escalado.compartido()
        Tono.afilado = 0
    end
    Luz.configurarSombras({ self.solDream, self.lunaDream }, self.calidad)
    self.sombrasCascadas = SombraCascadas.unico(dream, self.solDream)
    -- El terreno por trozos con niveles de detalle (batalla/dream/terreno_trozos.lua)
    -- y el faldón hasta el horizonte aparte, todos con el mismo material.
    local opcionesTerreno = {
        nombre = 'terreno',
        rugosidad = 0.92,
        texturaTerreno = TexturaTerreno.crear(),
    }
    local materialTerreno = self.conversor:material(opcionesTerreno)
    Carga.mostrar('Cargando las texturas del suelo', 0.961, true)
    materialTerreno.texturasPbr = TexturasPbr.terreno(self.calidad)
    -- Materiales de cerca del suelo según la calidad (Fase 3 del plan de
    -- render); la mezcla por altura y el parallax necesitan las alturas.
    local materiales = self.calidad.materiales or {}
    local conAlturas = materialTerreno.texturasPbr.alturas
    TerrenoPBR.opciones = {
        altura = materiales.altura and conAlturas,
        detalle = materiales.detalle,
        pom = materiales.pom and conAlturas,
    }
    RocaPBR.opciones = { detalle = materiales.detalle }
    Carga.mostrar('Preparando el terreno por trozos', 0.962, true)
    self.terrenoTrozos = TerrenoTrozos.nuevo(dream, self.conversor, self.suelo, materialTerreno, {
        rugosidad = 0.92,
        alcanceSombra = self.calidad.sombra * 2,
    }, function(t)
        Carga.mostrar('Preparando el terreno por trozos', 0.962 + 0.02 * t)
    end)
    self.dreamFaldon = self.terrenoTrozos:mallaFaldon()
    -- Suelo del estilo: hierba verde, seca y tierra, y la máscara de pinocha.
    local recursos = Recursos.de(dream, self.suelo.terreno.semilla)
    -- Traslucidez y viento de la vegetación según la calidad (Fase 3).
    Recursos.aplicarCalidad(recursos, materiales)
    Viento.activo = materiales.viento and true or false
    materialTerreno.texVerde = recursos.texturas.hierbaVerde
    materialTerreno.texSeca = recursos.texturas.hierbaSeca
    materialTerreno.texTierra = recursos.texturas.tierra
    materialTerreno.texRoca = recursos.texturas.roca
    materialTerreno.mascaraSuelo, materialTerreno.mascaraRect = Mascara.crear(self.suelo)
    -- Vegetación y rocas por lotes FFI y celdas (Valeria, batalla/dream/vegetacion.lua).
    Carga.mostrar('Sembrando la hierba y las flores', 0.984, true)
    self.vegetacion = VegetacionDream.nueva(dream, self.conversor, self.suelo, {
        calidad = self.calidad,
        sombras = self.sombrasCascadas,
        informar = function(t)
            Carga.mostrar('Sembrando la hierba y las flores', 0.984 + 0.01 * t)
        end,
    })
    -- Ciudad o mina armada con el kit (batalla/dream/kit_sitio.lua).
    Carga.mostrar('Levantando los edificios', 0.995, true)
    self.kitSitio = require('batalla.dream.kit_sitio').nuevo(dream, self.conversor, self.suelo.plano)
    self.dreamEdificio = self.conversor:desdeMalla(self.suelo.mallaEdificio, {
        nombre = 'edificio',
        rugosidad = 0.72,
    })
    self.dreamAgua = self.conversor:desdeMalla(self.suelo.mallaAgua, {
        nombre = 'agua',
        rugosidad = 0.18,
        metalico = 0.15,
        alfa = 0.72,
    })
    self.modelosDream = {}
    self.lotesCamiones = {} -- también los de los tanques
    -- Los del camión de 4 misiles (LoteArticulado) con copias en el cuadro y
    -- cuántas piezas tiene el que más (el ancho de la tabla de matrices).
    self.lotesArticuladosActivos = {}
    self.piezasArticuladas = 0
    -- Solo los modelos que salen en este combate, cada uno con su .glb.
    local presentes = modelosEnCombate(self.tropas)
    for bando = 1, 2 do
        local color = bando == 1 and combate.atacante.color or combate.defensor.color
        local modelos = {
            tanques = {},
            camiones = {},
        }
        -- Cada modelo con sus niveles de detalle (assets/modelos3d/lod.lua):
        -- el primero es el de siempre; los demás, más sencillos, de lejos.
        for _, id in ipairs(presentes[bando].tanque) do
            local ruta = Tropas.archivoDe(id)
            local niveles, radio = NivelDetalle.niveles(ruta)
            local cargado = { niveles = {}, radio = radio, umbrales = {} }
            -- Con orugas (los modelos _orugas): ruedas y oruga con su lote. Los
            -- niveles que no tienen una pieza (LOD2 lleva el tren de rodaje
            -- fundido al casco, LOD3 va en una pieza) se quedan sin su lote.
            local nombres, deOruga, sinSombra = piezasTanque(Orugas.de(Tropas.modeloDe(id)))
            -- Los lotes del otro bando, para compartir las piezas sin su color.
            local otro = bando == 2 and self.modelosDream[1].tanques[id]
            for k, nivel in ipairs(niveles) do
                local nombre = 'tanque_' .. id .. '_' .. bando .. (k > 1 and ('_lod' .. k) or '')
                local normal = cargarTanque(self.conversor, color, nombre, nil, nivel.archivo)
                -- Averiado: el mismo tanque ennegrecido (humea aparte, batalla/efectos.lua).
                local averiado = cargarTanque(self.conversor, color, nombre .. '_averiado', 0.3, nivel.archivo)
                local n = { normal = normal, averiado = averiado }
                local previo = otro and otro.porArchivo[nivel.archivo]
                -- El tren de rodaje no proyecta sombra (de cerca, solo con
                -- EscenaDream.sombraTrenCerca): queda dentro de la del casco y
                -- la oruga.
                local sombra = (k > 1 or not EscenaDream.sombraTrenCerca) and sinSombra or nil
                -- Y las ruedas (y los rodillos) de un lado con la misma forma
                -- comparten lote: de lejos no se ve que todas lleven el
                -- horneado de la primera.
                local igual, cuantas
                if k > 1 then
                    igual, cuantas = mismasFormas(normal, nombres, sinSombra)
                end
                -- Sin las tres piezas con mallas (el modelo de vértices de
                -- respaldo) o sin ninguna, se dibuja suelto o en el nivel anterior.
                local conLotes = conMallas(normal, nombres)
                if k == 1 then
                    for _, pieza in ipairs(PIEZAS_TANQUE) do
                        conLotes = conLotes and normal[pieza] ~= nil
                    end
                end
                if conLotes then
                    n.lotes = lotesTanque(normal, nombres, self.lotesCamiones, {
                        deOruga = deOruga,
                        previos = previo and previo.lotes,
                        sinSombra = sombra,
                        igual = igual,
                        cuantas = cuantas,
                    })
                    n.lotesAveriado = lotesTanque(averiado, nombres, self.lotesCamiones, {
                        previos = previo and previo.lotesAveriado,
                        sinSombra = sombra,
                        igual = igual,
                        cuantas = cuantas,
                    })
                    n.fundidos = {}
                    for paso, alfa in ipairs(NivelDetalle.pasos) do
                        n.fundidos[paso] = lotesTanque(normal, nombres, self.lotesCamiones, {
                            alfa = alfa,
                            deOruga = deOruga,
                            previos = previo and previo.fundidos[paso],
                            sinSombra = sombra,
                            igual = igual,
                            cuantas = cuantas,
                        })
                    end
                end
                -- Sin lotes en un nivel más sencillo, se queda en el anterior.
                if k == 1 or n.lotes then
                    cargado.niveles[#cargado.niveles + 1] = n
                    cargado.umbrales[#cargado.umbrales + 1] = nivel
                end
            end
            cargado.porArchivo = {}
            for k, n in ipairs(cargado.niveles) do
                cargado.porArchivo[cargado.umbrales[k].archivo] = n
            end
            -- Los campos de siempre (nivel 1) para quien los lea.
            local primero = cargado.niveles[1]
            cargado.normal, cargado.averiado = primero.normal, primero.averiado
            cargado.lotes, cargado.lotesAveriado = primero.lotes, primero.lotesAveriado
            modelos.tanques[id] = cargado
        end
        for _, id in ipairs(presentes[bando].lanzacohetes) do
            local ruta = Tropas.archivoDe(id)
            local lanzador = self.tropas:lanzadorDe(id)
            local nombres = lanzador.piezas
            local niveles, radio = NivelDetalle.niveles(ruta)
            local cargado = { niveles = {}, radio = radio, umbrales = {} }
            -- El de 4 misiles comparte lotes con el otro bando (sin la insignia).
            local otro = bando == 2 and self.modelosDream[1].camiones[id]
            for k, nivel in ipairs(niveles) do
                local piezasCamion = cargarSynty(k == 1 and ruta or nivel.archivo)
                local n
                if lanzador.articulacion then
                    if conMallas(piezasCamion, nombres) then
                        local previo = otro and otro.porArchivo[nivel.archivo]
                        n = lotesCamionArticulado(
                            piezasCamion,
                            nombres,
                            self.lotesCamiones,
                            previo,
                            self.lotesArticuladosActivos
                        )
                        self.piezasArticuladas = math.max(self.piezasArticuladas, #nombres)
                    end
                elseif k == 1 then
                    n = {
                        normal = instanciarCamion(piezasCamion, self.lotesCamiones, false, nombres),
                        destruidos = instanciarCamion(piezasCamion, self.lotesCamiones, true, nombres),
                    }
                elseif conMallas(piezasCamion, nombres) then
                    n = {
                        normal = instanciarPiezas(piezasCamion, nombres, self.lotesCamiones, Tropas.maxPorBando),
                        destruidos = instanciarPiezas(
                            piezasCamion,
                            nombres,
                            self.lotesCamiones,
                            Tropas.maxPorBando,
                            nil,
                            true
                        ),
                    }
                end
                if n then
                    n.fundidos = n.fundidos
                        or instanciarFundidos(piezasCamion, nombres, self.lotesCamiones, Tropas.maxPorBando)
                    cargado.niveles[#cargado.niveles + 1] = n
                    cargado.umbrales[#cargado.umbrales + 1] = nivel
                end
            end
            cargado.porArchivo = {}
            for k, n in ipairs(cargado.niveles) do
                cargado.porArchivo[cargado.umbrales[k].archivo] = n
            end
            cargado.normal, cargado.destruidos = cargado.niveles[1].normal, cargado.niveles[1].destruidos
            modelos.camiones[id] = cargado
        end
        self.modelosDream[bando] = modelos
    end
    -- Matrices de las piezas de los camiones articulados: una fila por camión
    -- y lote (con el fundido, un camión va en dos).
    if self.piezasArticuladas > 0 then
        self.tablaPiezas = TablaPiezas.nueva(self.piezasArticuladas, Tropas.maxPorBando * 2 * 2)
    end
    -- El misil en vuelo: la pieza `misil` del camión de misiles con robot
    -- conductor (assets/modelos3d/catalogo.lua), en metros; se carga con el
    -- primer misil en el aire (EscenaDream.misilEnVuelo).
    self.dreamEsfera = crearEsfera(self.conversor, combate.cx, combate.cy, {
        nombre = 'particula',
    })
    self.dreamHumo = crearEsfera(self.conversor, combate.cx, combate.cy, {
        nombre = 'humo',
        alfa = 0.32,
    })
    self.dreamHumo:setShadowVisibility(false)
    self.dreamHumoQuemado = crearEsfera(self.conversor, combate.cx, combate.cy, {
        nombre = 'humoQuemado',
        alfa = 0.5,
        color = { 0.12, 0.10, 0.09 },
    })
    self.dreamHumoQuemado:setShadowVisibility(false)
    self.rayos = Rayos.nuevo(dream, self.conversor, self.fisica.mallaRayosDream, self.dreamEsfera, self.tropas.unidades)
    self.tropas:usarRayos(self.rayos)
    self.control:usarSelector(function(x, y)
        return self.rayos:unidadEnPantalla(x, y)
    end)
    self.sonido = Sonido.nuevo(dream, self.conversor)
    self.tropas:usarSonido(self.sonido)
    self.efectos = EfectosDream.nuevos(dream, self.conversor, self.tropas, self.suelo, {
        calidad = self.calidad.nombre,
        misil = EscenaDream.misilEnVuelo,
    })
    self.tropas:usarEfectos(self.efectos.sim)
    self.humoEscape = HumoEscape.nuevo(self.efectos.sim)
    self.dreamEstelas = Instancias.nuevas(dream, self.dreamHumo)
    self.lucesDream = {}
    self:ponerHora()
    self:precalentar()
    self:ponerRobots()
    -- Las mallas fundidas de cada robot en todos sus niveles de detalle, ya
    -- en la carga (robots/union.lua): fundirlas en plena batalla daba
    -- tirones de hasta 1,1 s (27-nov).
    for _, robot in ipairs(RobotsBatalla.getRobots()) do
        Union.preparar(robot)
    end
    self.segundosDream = love.timer.getTime() - inicio
    self.suelo.segundosBase = self.suelo.segundos
    self.suelo.segundos = self.segundosDream
    Carga.mostrar('Campo de batalla listo', 1, true)
    return self
end

--- Robots de la batalla (batalla/robots/robot.lua). Paso 1 (el dueño,
-- 17-nov): un robot soldado del jugador, 12 m por delante del centro de sus
-- tanques y mirando al enemigo, para pulir su movimiento.
--- Sitio y rumbo para el avión de carga cerca de (px, py) px: la mejor
-- pista (vueloAvion.lua) de ±400 m a lo largo del rumbo. Cada muestra cada
-- 50 m del eje suma faltas: agua o sin paso (bajo el eje o las puntas de
-- las alas, a 45 m), árboles a menos de 44 m del eje y lo que el terreno se
-- aparta de la recta entre los extremos (más de 4 m); y pendiente de más
-- del 6 %. Gana la de menos faltas (0: perfecta, para ahí). Prueba 12
-- rumbos en cada sitio, empezando por `rumbo`, hasta 1,5 km.
function EscenaDream:sitioAvion(px, py, rumbo)
    local s = self.suelo
    local LARGO, PASO = 4000, 500 -- px: ±400 m, cada 50 m
    local mejor, bx, by, br = math.huge, px, py, rumbo
    local function faltas(qx, qy, r, tope)
        local c, si = math.cos(r), math.sin(r)
        local h1 = s:altura(qx - c * LARGO, qy - si * LARGO)
        local h2 = s:altura(qx + c * LARGO, qy + si * LARGO)
        local f = math.max(0, math.abs(h2 - h1) / (2 * LARGO) - 0.06) * 200
        for k = -LARGO, LARGO, PASO do
            local wx, wy = qx + c * k, qy + si * k
            local recta = h1 + (h2 - h1) * (k + LARGO) / (2 * LARGO)
            if not s:transitable(wx, wy) then
                f = f + 10
            end
            f = f + math.max(0, math.abs(s:altura(wx, wy) - recta) - 40) / 20
            for _, lado in ipairs({ -450, 450 }) do
                if not s:transitable(wx - si * lado, wy + c * lado) then
                    f = f + 5
                end
            end
            -- Árboles: se quitan (despejarFranja), pero mejor si hay pocos.
            if s:plantaCerca(wx, wy, 440, true) then
                f = f + 0.3
            end
            if f >= tope then
                return f
            end
        end
        return f
    end
    for radio = 0, 15000, 500 do
        local n = radio == 0 and 1 or 20
        for k = 0, n - 1 do
            local a = k / n * 2 * math.pi
            local qx, qy = px + math.cos(a) * radio, py + math.sin(a) * radio
            if s:transitable(qx, qy) then
                for j = 0, 11 do
                    local r = rumbo + j / 12 * 2 * math.pi
                    local f = faltas(qx, qy, r, mejor)
                    if f < mejor then
                        mejor, bx, by, br = f, qx, qy, r
                        if f == 0 then
                            print(string.format('AVION: pista perfecta a %.0f m, rumbo %.0f°', radio / 10, math.deg(r)))
                            return bx, by, br
                        end
                    end
                end
            end
        end
    end
    print(string.format('AVION: la mejor pista tiene %.1f faltas (0 = perfecta)', mejor))
    return bx, by, br
end

function EscenaDream:ponerRobots()
    RobotsBatalla.vaciar()
    local combate = self.combate
    local propio = self.control.propio or 1
    local haciaEnemigo = propio == 1 and combate.angulo or combate.angulo + math.pi
    -- Paso 2 (el dueño, 18-nov): dos robots, uno contra uno, a 160 m en medio
    -- del campo; cada uno traza sus rutas hacia el otro, elige la mejor y
    -- avanza (batalla/robots/especializaciones/asalto.lua). Solo dos.
    local mitad = EscenaDream.separacionRobots / 2
    local ca, sa = math.cos(haciaEnemigo), math.sin(haciaEnemigo)
    local function sitioLibre(px, py)
        for radio = 0, 300, 20 do
            for k = 0, 11 do
                local a = k / 12 * 2 * math.pi
                local qx, qy = px + math.cos(a) * radio, py + math.sin(a) * radio
                if self.suelo:transitable(qx, qy) and not self.suelo:plantaCerca(qx, qy, 25, true) then
                    return qx, qy
                end
                if radio == 0 then
                    break
                end
            end
        end
        return px, py
    end
    -- Paso 7 (el dueño, 18-nov: «hagamos estas pruebas con el robot que
    -- tiene el cañón en la cara y quita este camión»): el cerebro de los
    -- robots (batalla/robots/especializaciones/cerebro.lua), paso 1:
    -- sentidos y memoria. El lanzamisiles rojo con cerebro, quieto, y tres
    -- soldados azules quietos de blanco: dos por delante a distinta
    -- distancia y uno a su espalda (no lo ve). El camión (paso 6) está en la
    -- historia de git (f8c88c2).
    local x, y = sitioLibre(combate.cx, combate.cy)
    -- `BATALLA_ROBOTS_LEJOS=<km>` (el dueño, 18-nov: «que corra varios
    -- kilómetros, llegue al objetivo y le dispare»): el rojo empieza a esa
    -- distancia de un solo azul y va a por él.
    local lejos = tonumber(os.getenv('BATALLA_ROBOTS_LEJOS') or '')
    local lejosAzul
    if lejos then
        local mitadLejos = lejos * 1000 * 10 / 2
        local function enTierra(px, py)
            for radio = 0, 4000, 50 do
                for k = 0, 23 do
                    local a = k / 24 * 2 * math.pi
                    local qx, qy = px + math.cos(a) * radio, py + math.sin(a) * radio
                    if self.suelo:transitable(qx, qy) and not self.suelo:plantaCerca(qx, qy, 25, true) then
                        return qx, qy
                    end
                    if radio == 0 then
                        break
                    end
                end
            end
            return px, py
        end
        x, y = enTierra(combate.cx - ca * mitadLejos, combate.cy - sa * mitadLejos)
        lejosAzul = { enTierra(combate.cx + ca * mitadLejos, combate.cy + sa * mitadLejos) }
    end
    -- `BATALLA_GUARDIA=1` con la batalla en una mina (BATALLA_LUGAR=oro,
    -- metal o petroleo): el lanzamisiles rojo, solo, custodia la mina
    -- recorriendo libre su recinto (el dueño, 19-nov).
    local plano = self.suelo.plano
    local guardia = os.getenv('BATALLA_GUARDIA') and plano and plano.recinto and self.combate.sitio
        and self.combate.sitio.tipo == 'mina'
    if guardia then
        local rc = plano.recinto
        local margenMuro = 150 -- px del muro a un destino
        local margenEdificio = 60 -- px de un edificio a un destino
        local function dentroPx(px, py)
            return px > rc[1] + margenMuro and px < rc[3] - margenMuro and py > rc[2] + margenMuro and py < rc[4] - margenMuro
                and not self.suelo:ocupado(px, py, margenEdificio)
        end
        -- Arranca en el sitio libre más cercano al centro del recinto.
        local mx, my = (rc[1] + rc[3]) / 2, (rc[2] + rc[4]) / 2
        x, y = mx, my
        for radio = 0, 1200, 20 do
            local hecho = false
            for k = 0, 15 do
                local a = k / 16 * 2 * math.pi
                local qx, qy = mx + math.cos(a) * radio, my + math.sin(a) * radio
                if dentroPx(qx, qy) and self.suelo:transitable(qx, qy) then
                    x, y, hecho = qx, qy, true
                    break
                end
            end
            if hecho then
                break
            end
        end
    end
    local r = RobotsBatalla.crear('lanzamisilesCerebro', self.suelo, x, y, haciaEnemigo)
    r.datos.asalto.bando, r.datos.asalto.nombre = 'rojo', 'ROJO'
    local guardias = {}
    if guardia then
        local rc = plano.recinto
        local cx, cy = (rc[1] + rc[3]) / 20, -(rc[2] + rc[4]) / 20
        local radio = math.sqrt((rc[3] - rc[1]) ^ 2 + (rc[4] - rc[2]) ^ 2) / 20
        local suelo = self.suelo
        local function dentro(mx, my)
            local px, py = mx * 10, -my * 10
            return px > rc[1] + 150 and px < rc[3] - 150 and py > rc[2] + 150 and py < rc[4] - 150
                and not suelo:ocupado(px, py, 60)
        end
        -- Varios robots que se reparten el recinto entero (el dueño,
        -- 27-nov: «que cubran toda la zona»): cuántos, según lo que mide;
        -- salen repartidos y cada uno va a donde lleva más rato sin
        -- mirar nadie (batalla/robots/patrulla.lua).
        local patrulla = Patrulla.nueva(rc[1] / 10, -rc[4] / 10, rc[3] / 10, -rc[2] / 10, function(mx, my)
            return dentro(mx, my) and suelo:transitable(mx * 10, -my * 10)
                and not suelo:plantaCerca(mx * 10, -my * 10, 25, true)
        end)
        self.patrulla = patrulla
        local n = patrulla:robots()
        local salidas = patrulla:salidas(n, r.x, r.y)
        local opciones = { minimo = 25, maximo = 160, dentro = dentro, patrulla = patrulla }
        -- `BATALLA_GUERRA=<n>` (pruebas de rendimiento): dos equipos de n
        -- robots, soldados y lanzamisiles mezclados; los rojos salen de la
        -- mitad sur del recinto y los azules de la norte, y cada equipo
        -- patrulla el recinto entero, así que se encuentran y se disparan.
        local guerra = tonumber(os.getenv('BATALLA_GUERRA') or '')
        local equipos = { { bando = 'rojo', nombre = 'ROJO', patrulla = patrulla, opciones = opciones, salidas = salidas } }
        if guerra then
            local medio = -(rc[2] + rc[4]) / 20
            local azul = Patrulla.nueva(rc[1] / 10, -rc[4] / 10, rc[3] / 10, -rc[2] / 10, function(mx, my)
                return dentro(mx, my) and suelo:transitable(mx * 10, -my * 10)
                    and not suelo:plantaCerca(mx * 10, -my * 10, 25, true)
            end)
            equipos[1].salidas = patrulla:salidas(guerra, r.x, r.y, function(c)
                return c.y < medio
            end)
            equipos[2] = {
                bando = 'azul', nombre = 'AZUL', patrulla = azul,
                opciones = { minimo = 25, maximo = 160, dentro = dentro, patrulla = azul },
                salidas = azul:salidas(guerra, r.x, -rc[2] / 10, function(c)
                    return c.y > medio
                end),
            }
        end
        r:setRecorrer('rojo', cx, cy, radio, 'ROJO', opciones)
        for _, equipo in ipairs(equipos) do
            local primero = equipo.bando == 'rojo' and 2 or 1
            for k = primero, #equipo.salidas do
                local s = equipo.salidas[k]
                local tipo = 'lanzamisilesCerebro'
                if guerra and k % 2 == 0 then
                    tipo = 'soldadoAsalto'
                end
                local o = RobotsBatalla.crear(tipo, suelo, s.x * 10, -s.y * 10, haciaEnemigo)
                local nombre = equipo.nombre .. k
                o.datos.asalto.bando, o.datos.asalto.nombre = equipo.bando, nombre
                o:setRecorrer(equipo.bando, cx, cy, radio, nombre, equipo.opciones)
                guardias[#guardias + 1] = o
            end
        end
        print(string.format('GUARDIA: %d robots en la mina (%d equipos), recinto de %.0f x %.0f m, %d celdas de patrulla',
            #guardias + 1, #equipos, (rc[3] - rc[1]) / 10, (rc[4] - rc[2]) / 10, #patrulla.celdas))
        -- Sin zonas de despliegue ni contador: aquí no hay tropas que
        -- colocar, y la guardia dura hasta salir con Esc.
        self.sinZonas = true
        self.guardia = true
        if self.despliegue then
            self.despliegue.restante = math.huge
        end
    end
    -- Su memoria aprendida (cerebro.lua, paso 2): la suya, y la rama de este
    -- mapa (semilla y sitio del combate).
    r.idMemoria = 'ROJO'
    r.mapaMemoria = string.format('semilla%d_%d_%d', self.suelo.terreno.semilla or 0, math.floor(combate.cx / 1000), math.floor(combate.cy / 1000))
    self.robotsAsalto = { r }
    for _, o in ipairs(guardias) do
        o.idMemoria = o.datos.asalto.nombre
        o.mapaMemoria = r.mapaMemoria
        self.robotsAsalto[#self.robotsAsalto + 1] = o
    end
    local blancos = (lejos or guardia) and {} or {
        { 40, math.rad(-30) },
        -- A un costado: solo lo ve al girar la cabeza hacia ese lado.
        { 60, math.rad(105) },
        { 60, math.pi },
    }
    for n, b in ipairs(blancos) do
        local a = haciaEnemigo + b[2]
        local bx, by = sitioLibre(x + math.cos(a) * b[1] * 10, y + math.sin(a) * b[1] * 10)
        local e = RobotsBatalla.crear('soldadoAsalto', self.suelo, bx, by, a + math.pi)
        e.datos.asalto.bando, e.datos.asalto.nombre = 'azul', 'AZUL' .. n
        self.robotsAsalto[#self.robotsAsalto + 1] = e
    end
    if lejosAzul then
        local e = RobotsBatalla.crear('soldadoAsalto', self.suelo, lejosAzul[1], lejosAzul[2], haciaEnemigo + math.pi)
        e.datos.asalto.bando, e.datos.asalto.nombre = 'azul', 'AZUL1'
        self.robotsAsalto[#self.robotsAsalto + 1] = e
        print(string.format('LEJOS: ROJO a %.0f m de AZUL1', math.sqrt((e.x - r.x) ^ 2 + (e.y - r.y) ^ 2)))
        r:setAsalto('rojo', e.x, e.y, 'ROJO')
    end
    self.robotFoco = r
    self.robotSeguible = r
    self.camara:usarRobot(r)
    -- El avión de carga (el dueño, 20-nov: «mételo al juego»): aparcado
    -- 130 m detrás del ROJO, con la cola hacia él; la abertura trasera se
    -- abre y se cierra (EscenaDream:actualizar). Sin él: BATALLA_AVION=0.
    if os.getenv('BATALLA_AVION') ~= '0' and not guardia then
        -- La pista: la del aeródromo del sitio (dentro del recinto,
        -- batalla/sitios/plano.lua) o, sin sitio, la mejor que se encuentre.
        local plano = self.suelo.plano
        local pista = plano and plano.pista
        local ax, ay, arumbo, medioLargo
        if pista then
            ax, ay, arumbo, medioLargo = pista.x, pista.y, pista.rumbo, pista.medioLargo
            print(string.format('AVION: pista del aeródromo en %.0f,%.0f px', ax, ay))
        else
            ax, ay, arumbo = self:sitioAvion(x - math.cos(haciaEnemigo) * 1300, y - math.sin(haciaEnemigo) * 1300, haciaEnemigo + math.pi)
            medioLargo = 450
        end
        -- La pista, despejada: 100 m de ancho y su largo.
        local quitadas = self.suelo:despejarFranja(ax, ay, arumbo, medioLargo * 10, 500)
        print(string.format('AVION: pista despejada, %d plantas quitadas', quitadas))
        -- Autopista improvisada como pista (el dueño, 20-nov), antes del
        -- avión: él rueda sobre ella (MundoBatalla.superficies).
        self.pistaAvion = require('batalla.dream.pista_avion').nueva(dream, self.conversor, self.suelo, ax, ay, arumbo, medioLargo)
        require('batalla.robots.mundo').superficies = { self.pistaAvion }
        -- La plataforma con la calle de rodaje y las plazas (solo con el
        -- aeródromo del sitio): los aviones ruedan sobre ella.
        if pista then
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            local quitadasP = self.suelo:despejarFranja(ax, ay - (P.desde + P.hasta) / 2 * 10, arumbo, medioLargo * 10 + 200, (P.hasta - P.desde) / 2 * 10 + 80)
            print(string.format('PLATAFORMA despejada, %d plantas quitadas', quitadasP))
            self.plataformaAvion = require('batalla.dream.plataforma_avion').nueva(dream, self.conversor, self.suelo, pista)
            table.insert(require('batalla.robots.mundo').superficies, self.plataformaAvion)
        end
        -- Aparcado en el extremo oeste (de donde despega con toda la pista
        -- por delante), con la cola a 40 m del final.
        local atras = (medioLargo - 60) * 10
        local cx, cy = ax - math.cos(arumbo) * atras, ay - math.sin(arumbo) * atras
        local function crearAvion()
            local avion = RobotsBatalla.crear('avionCarga', self.suelo, cx, cy, arumbo)
            avion:setPista(ax / 10, -ay / 10, -arumbo, medioLargo)
            self.avionCarga = avion
            print(string.format('AVION de carga en %.0f,%.0f px (BATALLA_CAMARA_PUNTO)', ax, ay))
            -- `BATALLA_SEGUIR_AVION=1`: la cámara sigue al avión (su vuelo).
            if os.getenv('BATALLA_SEGUIR_AVION') then
                self.robotFoco = avion
                self.robotSeguible = avion
                require('batalla.camara').robotDistancia = { 15, 3000 }
                self.camara:usarRobot(avion)
            end
            return avion
        end
        -- Los aviones del mapa (el dueño, 26-nov): en un sitio de la partida
        -- se ven los vuelos de la simulación que le tocan (trafico_aereo.lua).
        -- El viaje de demostración (AVION_DEMO) y BATALLA_AVION=1, como antes:
        -- un avión aparcado con su pelotón.
        local demo = os.getenv('AVION_DEMO')
        self.trafico = not demo and os.getenv('BATALLA_AVION') ~= '1' and self.plataformaAvion
            and require('batalla.dream.trafico_aereo').nuevo(self, function(modo, plaza)
                local avion = crearAvion()
                if modo == 'llegada' then
                    avion:setPlaza(plaza)
                    avion:setLlegada()
                else
                    avion:setEstacionado(plaza)
                end
                return avion
            end)
        if self.trafico then
            self.trafico:empezar()
        else
            crearAvion()
            -- Pelotón de 15 que sube y se sienta en la bodega en 3 filas de 5
            -- (embarque.lua). Esperan formados en la pista, detrás del avión y
            -- a un lado del eje (el camino a la rampa queda libre). Sin ellos:
            -- BATALLA_EMBARQUE=0.
            if os.getenv('BATALLA_EMBARQUE') ~= '0' then
                local avion = self.avionCarga
                local c, s = math.cos(avion.rumbo), math.sin(avion.rumbo)
                local pasajeros = {}
                for fila = 0, 2 do
                    for columna = 0, 4 do
                        local lx, ly = -34 - fila * 2.2, 8 + columna * 1.5
                        local xm, ym = avion.x + c * lx - s * ly, avion.y + s * lx + c * ly
                        -- (Ejes del juego: px con y al sur y rumbo al revés.)
                        pasajeros[#pasajeros + 1] = RobotsBatalla.crear('soldadoPasajero', self.suelo, xm * 10, -ym * 10, -avion.rumbo)
                    end
                end
                -- `AVION_DEMO=salida|llegada` (tools/demo_avion.sh): ya van dentro.
                avion:setPasajeros(pasajeros, demo ~= nil)
            end
            -- Viaje entre sitios (el dueño, 20-nov): `AVION_DEMO=salida` despega y
            -- se va (deja la escena en la niebla); `llegada`, aparece en la final
            -- fuera de la vista y aterriza.
            if demo == 'salida' then
                self.avionCarga:setSalida()
            elseif demo == 'llegada' then
                self.avionCarga:setLlegada()
            end
        end
    end
    -- Mundo físico de la batalla (batalla/robots/fisica.lua, Jolt), el que
    -- leen los sensores y los ojos de los robots; se hace con el primer robot.
    -- (`self.fisica` es la de los tanques, la de antes.) Con
    -- `BATALLA_FISICA_CAJAS=1` se simula y caen cajas (prueba).
    if os.getenv('BATALLA_FISICA_CAJAS') then
        self.fisicaJolt = Mundo.getFisica()
        local azar = love.math.newRandomGenerator(7)
        for k = 1, 16 do
            local a, d = azar:random() * 2 * math.pi, 4 + azar:random() * 10
            local bx, by = r.x + math.cos(a) * d, r.y + math.sin(a) * d
            local id = self.fisicaJolt:caja(bx, by, Mundo.altura(bx, by) + 4 + k * 0.8, 0.3 + azar:random() * 0.4, 0.3 + azar:random() * 0.4, 0.3 + azar:random() * 0.3, 200)
            self.fisicaJolt:empujar(id, (azar:random() - 0.5) * 400, (azar:random() - 0.5) * 400, 0)
        end
        -- Unas cajas sobre el sólido más cercano, si hay.
        local tr = Mundo.cerca(r.x, r.y, 60, 'solido')[1]
        if tr then
            local f = tr.forma
            for k = 1, 3 do
                self.fisicaJolt:caja(f.x + 0.2 * k, f.y, f.z1 + 2 + k * 1.2, 0.4, 0.4, 0.4, 150)
            end
            print(string.format('FISICA cajas también sobre el sólido de (%.1f, %.1f), %.1f m de alto', f.x, f.y, f.z1 - f.z0))
        end
    end
end
EscenaDream.separacionRobots = 1600 -- px (160 m)
EscenaDream.robotsPorBando = 10
EscenaDream.lanzamisilesPorBando = 3
EscenaDream.radioRobots = 450 -- m: el círculo por el que corren
-- `BATALLA_ROBOTS_VIDEO=<salida.mp4>`: graba a los dos (batalla/robots/video.lua).
-- `BATALLA_ROBOTS_FOTOS=<carpeta>:<s>,<s>,...`: solo capturas en esos segundos.
if os.getenv('BATALLA_ROBOTS_VIDEO') then
    EscenaDream.videoRobots = require('batalla.robots.video').nuevo(os.getenv('BATALLA_ROBOTS_VIDEO'), tonumber(os.getenv('BATALLA_ROBOTS_SEGUNDOS') or ''))
elseif os.getenv('BATALLA_ROBOTS_FOTOS') then
    EscenaDream.videoRobots = require('batalla.robots.video').fotos(os.getenv('BATALLA_ROBOTS_FOTOS'))
end
-- `BATALLA_ROBOTS_MEDIR=<segundos>`: mide el rendimiento (batalla/robots/medir.lua).
if os.getenv('BATALLA_ROBOTS_MEDIR') then
    EscenaDream.medirRobots = require('batalla.robots.medir').nuevo(tonumber(os.getenv('BATALLA_ROBOTS_MEDIR')) or 30)
end

--- Hora del cielo: el día y la fracción del reloj de la simulación (solo se leen).
function EscenaDream:horaCielo()
    local sim = self.mundo and self.mundo.sim
    local ahora = sim and sim:ahora() or 0
    local dia = math.floor(ahora)
    local fraccion = EscenaDream.fraccionFija or (ahora - dia)
    return Luz.horaCielo(dia, fraccion)
end

function EscenaDream:ponerHora()
    if not self.solDream then
        return
    end
    Luz.actualizar(self.solDream, self.lunaDream, self:horaCielo(), self.lucesDream)
end

function EscenaDream:actualizar(dt)
    Escena.actualizar(self, dt)
    -- Viento de la vegetación (batalla/dream/viento.lua): el de las partículas.
    Viento.tiempo = (Viento.tiempo + dt) % 3600
    if self.efectos then
        local v = self.efectos.sim.viento
        local largo = math.sqrt(v[1] * v[1] + v[2] * v[2])
        if largo > 0 then
            Viento.direccion[1], Viento.direccion[2] = v[1] / largo, v[2] / largo
        end
    end
    self:ponerHora()
    -- Los aviones del mapa que llegan o se van de este sitio.
    if self.trafico then
        self.trafico:actualizar(dt)
    end
    if EscenaDream.medirRobots then
        EscenaDream.medirRobots:medir('logica', RobotsBatalla.actualizar, self.pausa and 0 or dt)
    else
        RobotsBatalla.actualizar(self.pausa and 0 or dt)
    end
    if self.fisicaJolt and not self.pausa then
        -- Antes de cada paso, el control de cada cuerpo de robot.
        local robots = self.robotsAsalto or {}
        self.fisicaJolt:actualizar(dt, function(paso)
            for _, r in ipairs(robots) do
                if r.cuerpoFisico then
                    r:controlarCuerpo(paso)
                end
            end
        end)
        self.relojFisica = (self.relojFisica or 0) + dt
        if os.getenv('BATALLA_FISICA_CAJAS') and not self.informeFisica and self.relojFisica > 5 then
            self.informeFisica = true
            self.fisicaJolt:informe()
        end
    end
    if EscenaDream.videoRobots then
        EscenaDream.videoRobots:camara(self, dt)
    end
    if self.efectos then
        self.efectos:actualizar(dt)
    end
    if self.avionCarga and self.efectos then
        self.estelasAvion = self.estelasAvion or EstelasAvion.nuevas()
        self.estelasAvion:actualizar(self.avionCarga, self.efectos, self.tropas.reloj)
    end
    if self.humoEscape then
        local ex, ey, ez = self.camara:puntosVista()
        self.humoEscape:actualizar(self.tropas, ex, ey, ez)
    end
    dream:update()
end

--- Hyprland puede ampliar la ventana después de que 3Dream haya creado sus
-- lienzos. Se comprueba aquí para que nunca quede media pantalla sin dibujar.
function EscenaDream:ajustarLienzos()
    -- La escena 3D, a `escalaRender` de la pantalla; FSR 1 la sube (escalado.lua).
    Escalado.ajustar(dream, self.escalado and self.calidad.escalaRender or 1)
end

function EscenaDream:prepararCamara()
    local camara = self.camara
    -- Los aros de selección deben acompañar la misma sacudida que las mallas.
    -- La vegetación recorta sus celdas con esta misma matriz.
    self.matrizVista = camara:matrices()
    local ex, ey, ez, tx, ty, tz = camara:puntosVista()
    local dx, dy, dz = self.conversor:punto(ex, ey, ez)
    local mx, my, mz = self.conversor:punto(tx, ty, tz)
    local ojo = dream.vec3(dx, dy, dz)
    local mira = dream.vec3(mx, my, mz)
    Viento.ojo[1], Viento.ojo[2], Viento.ojo[3] = dx, dy, dz
    dream.camera:setTransform(dream:lookAt(ojo, mira):invert())
    -- A pie (batalla/caminante.lua), plano cercano de 15 cm: un casco o un
    -- tronco al lado no se recortan. Desde arriba, se aleja con la cámara.
    if camara.caminante or camara.robot then
        dream.camera:setNear(camara:planoCercano() * Conversor.escala)
    else
        dream.camera:setNear(math.max(0.1, camara.distancia * Conversor.escala * 0.01))
    end
    Luz.centrarSombras(self.lucesDream, ojo, mira)
    self.sonido:actualizarOyente(ojo, mira)
end

local function dibujarSiExiste(malla)
    if malla then
        dream:draw(malla)
    end
end

--- Estado del nivel de detalle de `unidad` (batalla/dream/nivel_detalle.lua)
-- con el ojo en (ex, ey, ez): el nivel que toca por su tamaño en pantalla y,
-- si está cambiando, el anterior y el paso del fundido.
function EscenaDream:nivelUnidad(unidad, cargado, ex, ey, ez, ahora)
    local estados = self.nivelesUnidades
    local e = estados[unidad]
    if not e then
        e = {}
        estados[unidad] = e
    end
    local deseado
    if EscenaDream.nivelUnidadFijo then
        deseado = math.min(EscenaDream.nivelUnidadFijo, #cargado.niveles)
    else
        local dx, dy, dz = unidad.x - ex, unidad.y - ey, (unidad.z or 0) + 20 - ez
        local fraccion = NivelDetalle.fraccion(cargado.radio, math.sqrt(dx * dx + dy * dy + dz * dz))
        deseado = NivelDetalle.elegir(cargado.umbrales, fraccion, e.nivel)
    end
    return NivelDetalle.actualizar(e, deseado, ahora)
end

--- Cuántos vehículos hay ahora en cada nivel de detalle (y en fundido).
function EscenaDream:resumenNiveles()
    local cuenta, fundiendo = {}, 0
    for _, e in pairs(self.nivelesUnidades or {}) do
        if e.nivel then
            cuenta[e.nivel] = (cuenta[e.nivel] or 0) + 1
        end
        if e.anterior then
            fundiendo = fundiendo + 1
        end
    end
    local partes = {}
    for n = 1, 4 do
        partes[#partes + 1] = tostring(cuenta[n] or 0)
    end
    return string.format('vehículos por nivel %s, %d en fundido', table.concat(partes, '/'), fundiendo)
end

--- Copia de una pieza (con la matriz del juego `matriz`) en sus lotes.
local function anadirPieza(piezas, conversor, copia, matriz)
    if piezas and #piezas > 0 then
        LoteUnidades.escribir(conversor, matriz, copia)
        for _, lote in ipairs(piezas) do
            LoteUnidades.anadir(lote, copia)
        end
    end
end

--- Copia de una oruga con su desplazamiento y su difuso.
local function anadirOruga(piezas, conversor, copia, matriz, desplazamiento, difuso)
    if piezas and #piezas > 0 then
        LoteUnidades.escribir(conversor, matriz, copia)
        for _, lote in ipairs(piezas) do
            if LoteUnidades.anadir(lote, copia) then
                LoteUnidades.oruga(lote, desplazamiento, difuso)
            end
        end
    end
end

-- Difuso de la oruga contra el efecto estroboscópico (batalla/dream/oruga.lua)
-- según los eslabones que avanza por cuadro: nada hasta `difusoDesde`, todo
-- desde `difusoHasta` (por encima de medio eslabón por cuadro el dibujo ya
-- parecería ir hacia atrás).
EscenaDream.difusoDesde = 0.15
EscenaDream.difusoHasta = 0.5

local function difusoOruga(eslabonesPorCuadro)
    local t = (math.abs(eslabonesPorCuadro) - EscenaDream.difusoDesde)
        / (EscenaDream.difusoHasta - EscenaDream.difusoDesde)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

--- Copia de las piezas de un tanque en `lotes` (las que tenga el nivel): las
-- tres de siempre y, con orugas, el tren de rodaje y las dos orugas.
-- `cuadro`: segundos de batalla desde el cuadro anterior.
local function anadirTanque(lotes, conversor, copia, unidad, torreta, canon, cuadro)
    anadirPieza(lotes.casco, conversor, copia, unidad.casco)
    anadirPieza(lotes.torreta, conversor, copia, torreta)
    anadirPieza(lotes.canon, conversor, copia, canon)
    local orugas = unidad.orugas
    if not orugas then
        return
    end
    local matrices = unidad.matricesOrugas
    for _, nombre in ipairs(orugas.giran) do
        anadirPieza(lotes[nombre], conversor, copia, matrices[nombre])
    end
    for indice, nombre in ipairs(orugas.orugas) do
        local difuso = difusoOruga(unidad.velocidadOrugas[indice] * cuadro)
        anadirOruga(lotes[nombre], conversor, copia, unidad.casco, unidad.desplazamientoOrugas[indice], difuso)
    end
end

--- Copia de las piezas visibles de un camión en `piezas` (las que tenga el
-- nivel).
local function anadirCamion(piezas, unidad, conversor, copia)
    local matrices = unidad.matricesLanza
    for _, nombre in ipairs(unidad.lanzador.piezas) do
        local lotes = piezas[nombre]
        if lotes and #lotes > 0 and Lanzamisiles.visible(unidad, nombre) then
            LoteUnidades.escribir(conversor, matrices[nombre], copia)
            for _, lote in ipairs(lotes) do
                LoteUnidades.anadir(lote, copia)
            end
        end
    end
end

--- Las piezas de los conjuntos `a` y `b` (los de dos niveles durante el
-- fundido), una tabla por pareja.
local uniones = setmetatable({}, { __mode = 'k' })

local function unionPiezas(a, b)
    if not a or not b or a == b then
        return a or b
    end
    local porA = uniones[a]
    if not porA then
        porA = setmetatable({}, { __mode = 'k' })
        uniones[a] = porA
    end
    local union = porA[b]
    if not union then
        union = {}
        for nombre in pairs(a) do
            union[nombre] = true
        end
        for nombre in pairs(b) do
            union[nombre] = true
        end
        porA[b] = union
    end
    return union
end

--- Un camión en una variante de su nivel (normal, destruido o un paso del
-- fundido): la del camión de 4 misiles lleva su lote articulado y la
-- insignia; la de los demás, un lote por pieza.
local function anadirVarianteCamion(variante, unidad, conversor, copia)
    if variante.lote then
        variante.lote:anadir(unidad)
        anadirCamion(variante.insignia, unidad, conversor, copia)
    else
        anadirCamion(variante, unidad, conversor, copia)
    end
end

--- Camiones por lotes rellenados por FFI (batalla/dream/lote_unidades.lua):
-- las mismas transformaciones que con addInstance, sin tablas por copia.
-- Tanques y camiones con su nivel de detalle y el fundido al cambiar. Los
-- soldados, animados y en sus propios lotes (batalla/dream/soldados_animados.lua).
function EscenaDream:dibujarUnidades()
    -- Los lotes con copias en este cuadro (LoteUnidades.anadir los apunta):
    -- con orugas hay más de mil lotes y solo se usan unas decenas.
    local activos = self.lotesActivos
    if not self.lotesPreparados then
        activos = {}
        self.lotesActivos = activos
        for _, lote in ipairs(self.lotesCamiones) do
            LoteUnidades.preparar(lote, activos)
        end
        self.copiaUnidad = ffi.new('float[12]')
        self.lotesPreparados = true
    end
    for k = #activos, 1, -1 do
        LoteUnidades.vaciar(activos[k])
        activos[k] = nil
    end
    local articulados = self.lotesArticuladosActivos
    for k = #articulados, 1, -1 do
        articulados[k]:vaciar()
        articulados[k] = nil
    end
    local copia = self.copiaUnidad
    local conversor = self.conversor
    self.nivelesUnidades = self.nivelesUnidades or setmetatable({}, { __mode = 'k' })
    local ex, ey, ez = self.camara:puntosVista()
    local ahora = love.timer.getTime()
    -- Segundos de batalla desde el cuadro anterior (0 en pausa): con ellos la
    -- velocidad de cada oruga pasa a eslabones por cuadro.
    local reloj = self.tropas.reloj or 0
    local cuadro = math.max(0, reloj - (self.relojOrugas or reloj))
    self.relojOrugas = reloj
    for _, unidad in ipairs(self.tropas.unidades) do
        local modelos = self.modelosDream[unidad.bando]
        if unidad.tipo == 'tanque' then
            local torreta, canon =
                Modelos3d.matricesTanque(unidad.casco, unidad.torreta, unidad.retroceso, unidad.modelo3d)
            local cargado = modelos.tanques[unidad.modelo]
            local e = self:nivelUnidad(unidad, cargado, ex, ey, ez, ahora)
            local nivel = cargado.niveles[e.nivel]
            if not nivel.lotes then
                -- El modelo de vértices de respaldo, sin lotes ni niveles.
                local tanque = unidad.averiado and nivel.averiado or nivel.normal
                dream:draw(tanque.casco, self.conversor:matriz(unidad.casco))
                dream:draw(tanque.torreta, self.conversor:matriz(torreta))
                dream:draw(tanque.canon, self.conversor:matriz(canon))
            elseif unidad.averiado then
                anadirTanque(nivel.lotesAveriado, conversor, copia, unidad, torreta, canon, 0)
            elseif e.anterior then
                -- Fundido: el nivel anterior entero y el nuevo apareciendo.
                anadirTanque(cargado.niveles[e.anterior].lotes, conversor, copia, unidad, torreta, canon, cuadro)
                anadirTanque(nivel.fundidos[e.paso], conversor, copia, unidad, torreta, canon, cuadro)
            else
                anadirTanque(nivel.lotes, conversor, copia, unidad, torreta, canon, cuadro)
            end
        elseif unidad.tipo == 'lanzacohetes' then
            local camion = modelos.camiones[unidad.modelo]
            local e = self:nivelUnidad(unidad, camion, ex, ey, ez, ahora)
            local nivel = camion.niveles[e.nivel]
            -- El camión de 4 misiles solo compone las piezas de lo que se dibuja.
            if nivel.piezasVista then
                local filtro = nivel.piezasVista
                if e.anterior then
                    filtro = unionPiezas(camion.niveles[e.anterior].piezasVista, filtro)
                end
                unidad.lanzador:verPiezas(unidad, filtro)
            end
            if unidad.muerto then
                anadirVarianteCamion(nivel.destruidos, unidad, conversor, copia)
            elseif e.anterior then
                anadirVarianteCamion(camion.niveles[e.anterior].normal, unidad, conversor, copia)
                anadirVarianteCamion(nivel.fundidos[e.paso], unidad, conversor, copia)
            else
                anadirVarianteCamion(nivel.normal, unidad, conversor, copia)
            end
            -- Al precalentar, también el destruido y los pasos del fundido:
            -- sus sombreadores (con piezasBatalla) no los tiene nadie más.
            if self.precalentando and nivel.piezasVista then
                anadirVarianteCamion(nivel.destruidos, unidad, conversor, copia)
                for _, variante in ipairs(nivel.fundidos) do
                    anadirVarianteCamion(variante, unidad, conversor, copia)
                end
            end
        end
    end
    for _, lote in ipairs(activos) do
        if LoteUnidades.subir(dream, lote) > 0 then
            dream:draw(lote)
        end
    end
    -- Las filas de los camiones articulados, subidas de una vez antes de
    -- mandar sus lotes.
    if #articulados > 0 then
        local tabla = self.tablaPiezas
        tabla:vaciar()
        for _, lote in ipairs(articulados) do
            lote:subir(tabla, conversor)
        end
        tabla:subir()
        for _, lote in ipairs(articulados) do
            lote:dibujar(dream)
        end
    end
    if EscenaDream.medirRobots then
        EscenaDream.medirRobots:medir('mallas', RobotsBatalla.dibujar, conversor)
    else
        RobotsBatalla.dibujar(conversor)
    end
    if self.precalentando then
        self:precalentarMisiles()
    end
end

--- Al precalentar, un misil en vuelo en el centro del combate (no se ve): su
-- material es el del camión de 4 misiles con las instancias de 3Dream, un
-- sombreador que el camión ya no compila (usa piezasBatalla) y que si no se
-- compilaría con el primer disparo (unos 15 ms en ese cuadro).
function EscenaDream:precalentarMisiles()
    local misiles = self.efectos and self.efectos.misiles
    if not misiles then
        return
    end
    for _, lote in ipairs(misiles.lotes) do
        lote.instanceMesh:setVertex(1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
        lote.instancesCount = 1
        dream:draw(lote)
    end
end

function EscenaDream:dibujarEsfera(x, y, z, tamano, malla)
    local dx, dy, dz = self.conversor:punto(x, y, z)
    dream:draw(malla or self.dreamEsfera, dx, dy, dz, tamano / 10, tamano / 10, tamano / 10)
end

function EscenaDream:dibujarEfectos()
    -- Estelas y partículas con la salida de batalla/dream/efectos.lua (Camila).
    if self.efectos then
        self.efectos:dibujar()
        return
    end
    local tropas = self.tropas
    self.dreamEstelas:clear()
    for _, estela in ipairs(tropas.estelas.lista) do
        for indice = estela.primero, estela.n, 2 do
            local edad = tropas.reloj - estela.t[indice]
            local tamano = (Estelas.anchoInicial + edad * Estelas.crecimiento) * 0.72
            local x, y, z = self.conversor:punto(estela.x[indice], estela.y[indice], estela.z[indice])
            local escala = tamano / 10
            local transformacion = dream.mat4.getTranslate(x, y, z):scale(escala)
            self.dreamEstelas:addInstance(transformacion)
        end
    end
    if self.dreamEstelas:getInstancesCount() > 0 then
        dream:draw(self.dreamEstelas)
    end
    for _, bala in ipairs(tropas.balas) do
        local t = (tropas.reloj - bala.inicio) / bala.duracion
        local x, y, z = Tropas.posicionBala(bala, t)
        self:dibujarEsfera(x, y, z, bala.grosor and 2.8 or 7)
    end
    for _, misil in ipairs(tropas.misiles) do
        local t = (tropas.reloj - misil.inicio) / misil.duracion
        local ax, ay, az = Tropas.posicionMisil(misil, math.max(0, t - 0.004))
        local objeto, escala = EscenaDream.misilEnVuelo()
        if objeto then
            local transformacion = Tropas.matrizMisil(misil, t, {})
            for _, i in ipairs({ 1, 2, 3, 5, 6, 7, 9, 10, 11 }) do
                transformacion[i] = transformacion[i] * escala
            end
            dream:draw(objeto, self.conversor:matriz(transformacion))
        end
        self:dibujarEsfera(ax, ay, az, 4)
    end
    for _, particula in ipairs(tropas.particulas) do
        local progreso = particula.t / particula.vida
        local tamano = particula.tam0 + (particula.tam1 - particula.tam0) * progreso
        local malla = particula.color[1] < 0.3 and self.dreamHumoQuemado or self.dreamEsfera
        self:dibujarEsfera(particula.x, particula.y, particula.z, tamano, malla)
    end
end

--- Compila los sombreadores antes de empezar (la primera vez tarda; luego
-- los guarda el controlador de vídeo): dibuja la escena desde el encuadre
-- normal y desde cerca con cada nivel de detalle de los vehículos, sin
-- mostrarla, y deja la cámara como estaba.
function EscenaDream:precalentar()
    Carga.mostrar('Preparando sombreadores…', 0.996, true)
    local inicio = love.timer.getTime()
    local camara = self.camara
    local guardada = {}
    for clave, valor in pairs(camara) do
        guardada[clave] = valor
    end
    local fijo = EscenaDream.nivelUnidadFijo
    self.precalentando = true
    for nivel = 1, 4 do
        EscenaDream.nivelUnidadFijo = nivel
        for _, modo in ipairs({ 'normal', 'cerca' }) do
            self:encuadrar(modo)
            self:dibujarEscena()
        end
    end
    EscenaDream.nivelUnidadFijo = fijo
    self.precalentando = false
    self.nivelesUnidades = nil
    for clave in pairs(camara) do
        camara[clave] = nil
    end
    for clave, valor in pairs(guardada) do
        camara[clave] = valor
    end
    self.seguirMisil = false
    self.segundosSombreadores = love.timer.getTime() - inicio
    Carga.mostrar('Preparando sombreadores…', 0.999, true)
end

-- Lámparas del techo de la bodega del avión de carga: x en ejes del avión
-- (m), a 5 m del suelo de la bodega, cono hacia abajo (como las campanas del
-- almacén). Sin ellas dentro no se ve a los robots formados.
EscenaDream.lamparasBodega = { 12, 4, -4, -12 }
EscenaDream.brilloBodega = 4
EscenaDream.alturaLamparas = 1.55 + 4.6

function EscenaDream:lucesBodega()
    local avion = self.avionCarga
    local v = avion and avion.datos.vueloAvion
    local m = v and v.matriz
    if not (m and m[1]) then
        return
    end
    -- Solo con la cámara cerca (a menos de 200 m del avión).
    local ex, ey, ez = self.camara:puntosVista()
    if (ex / 10 - m[4]) ^ 2 + (-ey / 10 - m[8]) ^ 2 > 200 * 200 then
        return
    end
    if not self.lamparasDream then
        self.lamparasDream = {}
        for k = 1, #EscenaDream.lamparasBodega do
            local luz = dream:newLight('point', dream.vec3(0, 0, 0), dream.vec3(1.0, 0.94, 0.84), EscenaDream.brilloBodega)
            luz:setSpot(0, -1, 0, 70, 45)
            self.lamparasDream[k] = luz
        end
    end
    local h = EscenaDream.alturaLamparas
    for k, lx in ipairs(EscenaDream.lamparasBodega) do
        local x = m[1] * lx + m[3] * h + m[4]
        local y = m[5] * lx + m[7] * h + m[8]
        local z = m[9] * lx + m[11] * h + m[12]
        local luz = self.lamparasDream[k]
        local dx, dy, dz = self.conversor:punto(x * 10, -y * 10, z * 10)
        luz:setPosition(dx, dy, dz)
        -- El cono, hacia el suelo de la bodega (abajo del avión, en Dream).
        local ax, ay, az = self.conversor:punto(-m[3] * 10 + x * 10, m[7] * 10 - y * 10, -m[11] * 10 + z * 10)
        luz:setSpot(ax - dx, ay - dy, az - dz, 70, 45)
        dream:addLight(luz)
    end
end

--- La escena 3D (con la curva tonal), sin los efectos de encima ni los rótulos.
function EscenaDream:dibujarEscena()
    self:ajustarLienzos()
    self:prepararCamara()
    dream:prepare()
    for _, luz in ipairs(self.lucesDream) do
        dream:addLight(luz)
    end
    self:lucesBodega()
    local ojoX, ojoY, ojoZ, miraX, miraY, miraZ = self.camara:puntosVista()
    self.terrenoTrozos:dibujar(
        ojoX,
        ojoY,
        ojoZ,
        self.matrizVista,
        love.graphics.getHeight(),
        EscenaDream.nivelTerrenoFijo
    )
    dibujarSiExiste(self.dreamFaldon)
    if EscenaDream.medirRobots then
        EscenaDream.medirRobots:medir('vegetacion', self.vegetacion.actualizar, self.vegetacion, ojoX, ojoY, ojoZ, self.matrizVista)
    else
        self.vegetacion:actualizar(ojoX, ojoY, ojoZ, self.matrizVista)
    end
    self.vegetacion:dibujar()
    dibujarSiExiste(self.dreamEdificio)
    if self.kitSitio then
        self.kitSitio:dibujar(ojoX, ojoY, ojoZ, miraX, miraY, miraZ)
    end
    if self.plataformaAvion then
        self.plataformaAvion:dibujar()
    end
    if self.pistaAvion then
        self.pistaAvion:dibujar()
    end
    dibujarSiExiste(self.dreamAgua)
    self:dibujarUnidades()
    self:dibujarEfectos()
    -- La escena pasa por la curva tonal (batalla/dream/tono.lua); los efectos
    -- de encima (humo, fuego, estelas) van después, con su color de siempre.
    local escalado = self.escalado
    local entrada = escalado and escalado:entrada(dream.canvases.width, dream.canvases.height)
    self.tono:empezar(dream.canvases.width, dream.canvases.height)
    local temporal = self.temporal
    if temporal then
        temporal:prepararCuadro(dream.camera)
    end
    dream:present()
    if temporal then
        local imagen = temporal:resolver(self.tono.lienzo, dream.canvases, dream.camera)
        -- Los efectos de encima usan la proyección de la cámara: sin desplazar.
        temporal:quitar(dream.camera)
        dream.camera:applyProjectionTransform(dream.canvases)
        self.tono:terminar(imagen, entrada)
    else
        self.tono:terminar(nil, entrada)
    end
    if escalado then
        escalado:subir(self.tono.anterior)
        love.graphics.setCanvas(self.tono.anterior)
    end
end

function EscenaDream:dibujar()
    self:dibujarEscena()
    if self.efectos then
        self.efectos:dibujarEncima()
    end
    if EscenaDream.medirRobots then
        EscenaDream.medirRobots:medir('capa', VistaRobots.dibujar, self)
    else
        VistaRobots.dibujar(self)
    end
    love.graphics.push('all')
    Escena.dibujarZonas(self)
    self.control:dibujar()
    Escena.dibujarAvisos(self)
    Escena.dibujarRotulo(self)
    Escena.dibujarPanelDespliegue(self)
    love.graphics.setColor(0.82, 0.92, 1, 1)
    love.graphics.print('Comparador 3DreamEngine (--dream)', 16, love.graphics.getHeight() - 28)
    love.graphics.pop()
end

return EscenaDream

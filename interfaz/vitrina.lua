-- Vitrina del Arsenal: el modelo 3D de una unidad, en vivo, con 3DreamEngine
-- y sus materiales PBR (los mismos .glb de la batalla, assets/modelos3d/
-- catalogo.lua; el camión de misiles, el .glb de su robot con sus piezas en
-- reposo), dibujado a un lienzo propio de fondo transparente y luego
-- puesto en la interfaz como una imagen más. Gira despacio solo y se gira
-- arrastrando con el ratón (el ángulo lo lleva quien llama).
--
-- 3Dream es un único motor compartido con la batalla 3D (batalla/dream/). La
-- vitrina no cambia nada suyo de forma duradera:
--   * usa su propia cámara, sus propios lienzos (modo «lite», sin el pase
--     final) y sus propias luces, que se añaden en cada cuadro;
--   * el cielo, la niebla y la oclusión de la batalla se apagan solo mientras
--     se dibuja la vitrina y se devuelven como estaban;
--   * la luz ambiente es un cubo gris claro propio, puesto en sus objetos;
--   * si la batalla aún no preparó el motor, lo prepara con lienzos mínimos
--     (la batalla, al entrar, lo prepara de nuevo a su manera).
-- Si algo falla al cargar, `dibujar` devuelve false y el Arsenal pone el
-- render del modelo.
--
-- Solo dibuja: no lee ni cambia la simulación.

local Catalogo = require('assets.modelos3d.catalogo')

local Vitrina = {}
Vitrina.__index = Vitrina

-- Lo que no está en el catálogo de armamento (la infantería, robots desde
-- el 17-nov-2026, aún no tiene modelo).
local EXTRAS = {}

local dream -- el motor, al primer uso
local fallo -- texto del error si el motor no se pudo preparar
local cubo -- cubo de luz ambiente (gris claro)
local manchaSombra -- imagen de la sombra blanda (degradado redondo)

-- Luz: sol desde arriba a la izquierda y por delante; relleno suave desde la
-- derecha y un contraluz para separar la silueta del fondo claro.
local LUCES = {
    { direccion = { -0.55, 0.75, 0.45 }, color = { 1, 0.97, 0.92 }, brillo = 3.2 },
    { direccion = { 0.7, 0.35, 0.25 }, color = { 0.85, 0.9, 1 }, brillo = 0.9 },
    { direccion = { 0.1, 0.5, -0.9 }, color = { 1, 1, 1 }, brillo = 1.1 },
}

--- Prepara el motor la primera vez. Devuelve true si se puede usar.
local function prepararMotor()
    if dream then
        return true
    end
    if fallo then
        return false
    end
    local ok, err = pcall(function()
        local motor = require('lib.3DreamEngine')
        -- Materiales PBR de las unidades (los mismos que carga la batalla).
        local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
        if not motor.materialLibrary.unidadCamion4 then
            BibliotecaPbr.cargar(motor, 'assets/modelos3d/materiales')
        end
        -- Los de los robots (el camión de misiles es uno).
        if not motor.materialLibrary.robotBlanco then
            BibliotecaPbr.cargar(motor, 'assets/almacen/materiales_robot')
        end
        -- Sin preparar (la batalla aún no entró): lienzos mínimos, que la
        -- batalla cambia por los suyos al prepararse.
        if not motor.canvases.width then
            motor:init(16, 16)
        end
        local caras = {}
        for k = 1, 6 do
            local datos = love.image.newImageData(4, 4)
            -- Arriba más claro que abajo: el cielo nublado de un hangar.
            local v = (k == 3) and 0.95 or ((k == 4) and 0.42 or 0.72)
            datos:mapPixel(function()
                return v, v, v * 1.02, 1
            end)
            caras[k] = datos
        end
        cubo = motor:newReflection(love.graphics.newCubeImage(caras, { mipmaps = true }))
        dream = motor
    end)
    if not ok then
        fallo = tostring(err)
        print('VITRINA sin 3D: ' .. fallo)
    end
    return ok
end

--- Encuadre del modelo a partir de sus vértices: centro y radio de la caja,
-- en unidades de 3Dream (100 px del juego), con el eje vertical en y.
local function medir(archivoLua)
    local datos = love.filesystem.load(archivoLua)()
    local pivotes = {}
    for _, p in ipairs(datos.piezas) do
        pivotes[p.nombre] = p
    end
    -- Posición de cada pieza: la suma de los pivotes hasta la raíz.
    local function origen(nombre)
        local x, y, z = 0, 0, 0
        local p = pivotes[nombre]
        while p do
            local v = p.pivote or { 0, 0, 0 }
            x, y, z = x + v[1], y + v[2], z + v[3]
            p = p.padre and pivotes[p.padre]
        end
        return x, y, z
    end
    local minimo = { math.huge, math.huge, math.huge }
    local maximo = { -math.huge, -math.huge, -math.huge }
    local posiciones = {}
    for _, p in ipairs(datos.piezas) do
        local ox, oy, oz = origen(p.nombre)
        posiciones[p.nombre] = { ox, oy, oz }
        for _, v in ipairs(p.vertices) do
            local x, y, z = v[1] + ox, v[2] + oy, v[3] + oz
            minimo[1], maximo[1] = math.min(minimo[1], x), math.max(maximo[1], x)
            minimo[2], maximo[2] = math.min(minimo[2], y), math.max(maximo[2], y)
            minimo[3], maximo[3] = math.min(minimo[3], z), math.max(maximo[3], z)
        end
    end
    local s = 0.01
    local cx, cy, cz = (minimo[1] + maximo[1]) / 2, (minimo[2] + maximo[2]) / 2, (minimo[3] + maximo[3]) / 2
    local radio = math.sqrt((maximo[1] - minimo[1]) ^ 2 + (maximo[2] - minimo[2]) ^ 2 + (maximo[3] - minimo[3]) ^ 2) / 2
    return {
        -- Juego (x, y, z arriba) a 3Dream (x, z arriba, y).
        centro = { cx * s, cz * s, cy * s },
        suelo = minimo[3] * s,
        radio = radio * s,
        largo = (maximo[1] - minimo[1]) * s,
        ancho = (maximo[2] - minimo[2]) * s,
        alto = (maximo[3] - minimo[3]) * s,
        posiciones = posiciones,
    }
end

--- Piezas y encuadre de un modelo de robot (`archivo` sin extensión:
-- `<archivo>.glb` y `<archivo>_piezas.lua`, en metros; robots/nucleo.lua)
-- en reposo. Cada pieza con malla lleva su matriz de 3Dream (unidades de
-- 10 m, y arriba), la misma conversión que batalla/robots/robot.lua.
local function piezasRobot(objeto, archivo)
    local PiezaRobot = require('robots.pieza')
    local Medidas = require('medidas')
    local lista = love.filesystem.load(archivo .. '_piezas.lua')()
    local e = Medidas.escalaRobot(archivo:match('([^/]+)$'))
    local raiz = { e, 0, 0, 0, 0, e, 0, 0, 0, 0, e, 0, 0, 0, 0, 1 }
    local mundo = {}
    local piezas = {}
    local minimo = { math.huge, math.huge, math.huge }
    local maximo = { -math.huge, -math.huge, -math.huge }
    local s = 0.1
    for _, p in ipairs(lista) do
        local madre = p.padre and mundo[p.padre] or raiz
        local m = PiezaRobot.multiplicar(madre, p.matriz)
        mundo[p.nombre] = m
        local pieza = p.malla and objeto.objects[p.nombre]
        if pieza then
            -- Del marco de los robots (x delante, y a la izquierda, z arriba)
            -- al de 3Dream (y arriba).
            local d = {
                m[1] * s, m[3] * s, -m[2] * s, m[4] * s,
                m[9] * s, m[11] * s, -m[10] * s, m[12] * s,
                -m[5] * s, -m[7] * s, m[6] * s, -m[8] * s,
                0, 0, 0, 1,
            }
            pieza:resetTransform()
            piezas[#piezas + 1] = { objeto = pieza, matriz = d }
            for _, malla in ipairs(pieza.meshes or {}) do
                local vertices = malla.vertices
                for i = 1, vertices and vertices:getSize() or 0 do
                    local v = vertices:getVector(i)
                    local punto = {
                        d[1] * v[1] + d[2] * v[2] + d[3] * v[3] + d[4],
                        d[5] * v[1] + d[6] * v[2] + d[7] * v[3] + d[8],
                        d[9] * v[1] + d[10] * v[2] + d[11] * v[3] + d[12],
                    }
                    for k = 1, 3 do
                        minimo[k] = math.min(minimo[k], punto[k])
                        maximo[k] = math.max(maximo[k], punto[k])
                    end
                end
            end
        end
    end
    if minimo[1] == math.huge then
        error('sin vértices en ' .. archivo .. '.glb')
    end
    local largo, alto, ancho = maximo[1] - minimo[1], maximo[2] - minimo[2], maximo[3] - minimo[3]
    local medida = {
        centro = { (minimo[1] + maximo[1]) / 2, (minimo[2] + maximo[2]) / 2, (minimo[3] + maximo[3]) / 2 },
        suelo = minimo[2],
        radio = math.sqrt(largo * largo + alto * alto + ancho * ancho) / 2,
        largo = largo,
        ancho = ancho,
        alto = alto,
    }
    return piezas, medida
end

function Vitrina.nueva()
    local self = setmetatable({}, Vitrina)
    self.modelos = {} -- clave -> { objeto, piezas, medida } o false
    self.lienzos = {} -- ranura -> { w, h, canvases }
    self.miniaturas = {} -- clave:w:h -> lienzo fijo (o false)
    self.camara = nil
    self.luces = nil
    return self
end

--- ¿Tiene modelo 3D la unidad `clave` ('scudb', 'soldados'...)?
function Vitrina.tieneModelo(clave)
    return (Catalogo.modelos[clave] or EXTRAS[clave]) ~= nil
end

--- Carga el modelo de `clave` (una vez). `color`: el de la franja de la nación.
function Vitrina:modelo(clave, color)
    local m = self.modelos[clave]
    if m ~= nil then
        return m or nil
    end
    local entrada = Catalogo.modelos[clave] or EXTRAS[clave]
    if not entrada or not love.filesystem.getInfo(entrada.archivo .. '.glb') then
        self.modelos[clave] = false
        return nil
    end
    local ok, resultado = pcall(function()
        local objeto = dream:loadObject(entrada.archivo, { decodeBlenderNames = false })
        if entrada.robot then
            local piezas, medida = piezasRobot(objeto, entrada.archivo)
            for _, p in ipairs(piezas) do
                p.objeto.reflection = cubo
            end
            return { piezas = piezas, medida = medida }
        end
        local medida = medir(entrada.archivo .. '.lua')
        local piezas = {}
        for nombre, pieza in pairs(objeto.objects) do
            pieza.reflection = cubo
            for _, malla in ipairs(pieza.meshes or {}) do
                local material = malla:getMaterial()
                local franja = nombre == 'insignia'
                if material and (franja or material.name:lower():sub(1, 6) == 'nacion') then
                    material = dream:newMaterial('Franja nacional vitrina ' .. clave)
                    -- En lineal, como en la batalla (soldados_animados.lua):
                    -- 3Dream multiplica el color del material tal cual y el
                    -- de la nación viene en sRGB (sin esto, el carmesí sale rosa).
                    material:setColor(color[1] ^ 2.2, color[2] ^ 2.2, color[3] ^ 2.2, 1)
                    material:setRoughness(0.7)
                    material:setMetallic(0)
                    malla:setMaterial(material)
                end
            end
            local p = medida.posiciones[nombre] or { 0, 0, 0 }
            piezas[#piezas + 1] = { objeto = pieza, x = p[1] * 0.01, y = p[3] * 0.01, z = p[2] * 0.01 }
        end
        return { piezas = piezas, medida = medida }
    end)
    if not ok then
        print('VITRINA sin el modelo ' .. clave .. ': ' .. tostring(resultado))
        self.modelos[clave] = false
        return nil
    end
    self.modelos[clave] = resultado
    return resultado
end

--- Lienzos de `w`×`h` de una ranura (se rehacen si cambia el tamaño). Cada
-- modelo que se ve a la vez (Comparar enseña dos) va en su ranura.
function Vitrina:lienzosDe(w, h, ranura)
    local l = self.lienzos[ranura]
    if l and l.w == w and l.h == h then
        return l
    end
    local ao = dream.AO_enabled
    dream.AO_enabled = false
    local canvases = dream:newCanvases()
    canvases:setMode('lite')
    canvases:setMSAA(4)
    canvases:init(w, h)
    dream.AO_enabled = ao
    l = { w = w, h = h, canvases = canvases }
    self.lienzos[ranura] = l
    return l
end

--- Dibuja el modelo de `clave` en el rectángulo (x, y, w, h) de la pantalla,
-- girado `angulo` radianes sobre su eje vertical. `opciones`: { color (de la
-- franja), alfa, oscuro (bloqueado: más apagado), ranura (lienzo propio si se
-- ven varios a la vez), llenar (parte del lienzo que ocupa, 0,92), elevacion
-- (grados), sombra (false: sin sombra) }. Devuelve false si no se
-- pudo (sin 3D o sin modelo): quien llama pone otra cosa.
function Vitrina:dibujar(clave, x, y, w, h, angulo, opciones)
    opciones = opciones or {}
    if w < 8 or h < 8 or not prepararMotor() then
        return false
    end
    local m = self:modelo(clave, opciones.color or { 0.75, 0.62, 0.2 })
    if not m then
        return false
    end
    w, h = math.floor(w), math.floor(h)
    local lienzos = self:lienzosDe(w, h, opciones.ranura or 'principal')
    local medida = m.medida
    local ok, err = pcall(function()
        -- Lo de la batalla que no va aquí: cielo, niebla y oclusión.
        local cielo, exposicion = dream:getSky()
        local niebla = dream.fog_enabled
        local ao = dream.AO_enabled
        local luces = dream.lighting
        local tareas = dream.renderTasks
        dream:setSky({ 0, 0, 0, 0 })
        dream.fog_enabled = false
        dream.AO_enabled = false

        -- Cámara: tres cuartos desde delante y algo de arriba, a la distancia
        -- justa para que el modelo llene el lienzo.
        local camara = self.camara or dream:newCamera()
        self.camara = camara
        local fov = 30
        camara:setFov(fov)
        local aspecto = w / h
        local tanV = math.tan(math.rad(fov / 2))
        local tanH = tanV * aspecto
        local c = medida.centro
        local elevacion = math.rad(opciones.elevacion or 14)
        -- Radio horizontal (gira sobre sí mismo: cabe en cualquier ángulo) y
        -- alto que se ve con la elevación de la cámara.
        local radio = math.sqrt(medida.largo ^ 2 + medida.ancho ^ 2) / 2
        local altoVisto = medida.alto * math.cos(elevacion) + radio * 2 * math.sin(elevacion)
        local llenar = opciones.llenar or 0.92
        local distancia = math.max(radio / (tanH * llenar), altoVisto / 2 / (tanV * llenar)) + radio
        local mira = dream.vec3(0, medida.suelo + medida.alto * 0.42, 0)
        local ojo = dream.vec3(0, mira.y + math.sin(elevacion) * distancia, math.cos(elevacion) * distancia)
        self.encuadre = { ojo = ojo, mira = mira, tanV = tanV, radio = radio, distancia = distancia }
        camara:setNear(math.max(0.01, distancia - radio * 4))
        camara:setFar(distancia + radio * 4)
        camara:setTransform(dream:lookAt(ojo, mira):invert())

        dream:prepare()
        if not self.luces then
            self.luces = {}
            for _, def in ipairs(LUCES) do
                local luz = dream:newLight('sun')
                local d = def.direccion
                luz:setDirection(d[1], d[2], d[3])
                luz:setColor(def.color[1], def.color[2], def.color[3])
                luz:setBrightness(def.brillo)
                self.luces[#self.luces + 1] = luz
            end
        end
        local tono = opciones.oscuro and 0.35 or 1
        for k, luz in ipairs(self.luces) do
            luz:setBrightness(LUCES[k].brillo * tono)
            dream:addLight(luz)
        end
        -- Giro sobre el centro de la planta del modelo.
        local giro = dream.mat4.getRotateY(angulo)
        local centrar = dream.mat4.getTranslate(-c[1], 0, -c[3])
        for _, p in ipairs(m.piezas) do
            local colocar = p.matriz and dream.mat4(p.matriz) or dream.mat4.getTranslate(p.x, p.y, p.z)
            local transformacion = giro * centrar * colocar
            dream:draw(p.objeto, transformacion)
        end
        love.graphics.push('all')
        love.graphics.setCanvas(lienzos.canvases.color)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.pop()
        dream:present(camara, lienzos.canvases, true)

        dream:setSky(cielo, exposicion)
        dream.fog_enabled = niebla
        dream.AO_enabled = ao
        dream.lighting = luces
        dream.renderTasks = tareas
    end)
    if not ok then
        print('VITRINA error al dibujar ' .. clave .. ': ' .. tostring(err))
        fallo = tostring(err)
        dream = nil
        return false
    end
    if opciones.sombra ~= false then
        self:dibujarSombra(x, y, w, h, medida, opciones.alfa or 1)
    end
    love.graphics.setColor(1, 1, 1, opciones.alfa or 1)
    love.graphics.draw(lienzos.canvases.color, x, y)
    return true
end

--- Miniatura fija de `clave` (para la tira de modelos): se dibuja una vez
-- con 3Dream en un lienzo propio de `w`×`h` y se guarda. nil si no hay 3D.
function Vitrina:miniatura(clave, w, h, color)
    w, h = math.floor(w), math.floor(h)
    local llave = clave .. ':' .. w .. ':' .. h
    local m = self.miniaturas[llave]
    if m ~= nil then
        return m or nil
    end
    local lienzo = love.graphics.newCanvas(w, h)
    love.graphics.push('all')
    -- Sin la traslación ni el fundido de quien dibuja (interfaz/vida.lua).
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setCanvas(lienzo)
    love.graphics.clear(0, 0, 0, 0)
    local ok = self:dibujar(clave, 0, 0, w, h, 2.35, { ranura = 'miniatura', color = color, llenar = 1.25 })
    love.graphics.pop()
    if not ok then
        -- Sin 3D (o el motor aún no está): no se guarda, se reintenta.
        if fallo then
            self.miniaturas[llave] = false
        end
        lienzo:release()
        return nil
    end
    self.miniaturas[llave] = lienzo
    return lienzo
end

--- Sombra blanda en el suelo bajo el modelo: una elipse que se desvanece,
-- en el punto del suelo que ve la cámara y del tamaño de la planta del modelo.
function Vitrina:dibujarSombra(x, y, w, h, medida, alfa)
    local e = self.encuadre
    -- Punto del suelo bajo el centro, visto desde la cámara (y hacia abajo).
    local dy = medida.suelo - e.ojo.y
    local dz = -e.ojo.z
    local fy, fz = e.mira.y - e.ojo.y, e.mira.z - e.ojo.z
    local largoF = math.sqrt(fy * fy + fz * fz)
    fy, fz = fy / largoF, fz / largoF
    -- Eje «arriba» de la cámara (perpendicular a la mirada, en el plano y-z).
    local uy, uz = -fz, fy
    if uy < 0 then
        uy, uz = -uy, -uz
    end
    local hondo = dy * fy + dz * fz
    local alto = dy * uy + dz * uz
    local escala = h / 2 / (e.tanV * hondo)
    local cx = x + w / 2
    local cy = y + h / 2 - alto * escala
    local ancho = e.radio * escala * 1.05
    if not manchaSombra then
        local datos = love.image.newImageData(64, 64)
        datos:mapPixel(function(px, py)
            local sx, sy = (px + 0.5) / 32 - 1, (py + 0.5) / 32 - 1
            local d = math.min(1, math.sqrt(sx * sx + sy * sy))
            local a = (1 - d) ^ 1.6
            return 1, 1, 1, a
        end)
        manchaSombra = love.graphics.newImage(datos)
        manchaSombra:setFilter('linear', 'linear')
    end
    love.graphics.setColor(0.08, 0.09, 0.1, 0.42 * alfa)
    love.graphics.draw(manchaSombra, cx - ancho, cy - ancho * 0.2, 0, ancho * 2 / 64, ancho * 0.4 / 64)
end

return Vitrina

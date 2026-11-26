-- Puente entre las mallas de NationsRTS y 3DreamEngine. Cambia el eje vertical
-- Z del juego por Y, centra el área para conservar precisión y aplica la
-- escala física de 100 px por unidad de 3Dream (10 m).

local ffi = require('ffi')
local Malla = require('batalla.malla')

local Conversor = {}
Conversor.__index = Conversor

Conversor.escala = 0.01

local FLOTANTES = 10

function Conversor.nuevo(dream, cx, cy)
    local self = setmetatable({}, Conversor)
    self.dream = dream
    self.cx = cx
    self.cy = cy
    return self
end

function Conversor:punto(x, y, z)
    local escala = Conversor.escala
    return (x - self.cx) * escala, z * escala, (y - self.cy) * escala
end

local function prepararMalla(dream, cantidad, material, pixelShader)
    local malla = dream:newMesh(material)
    malla:setPixelShader(pixelShader or 'simple')
    malla.vertices = dream:newBuffer('vec3', 'float', cantidad)
    malla.normals = dream:newBuffer('vec3', 'float', cantidad)
    malla.colors = dream:newBuffer('vec4', 'float', cantidad)
    malla.roughnesses = dream:newBuffer('scalar', 'float', cantidad)
    malla.metallics = dream:newBuffer('scalar', 'float', cantidad)
    malla.emissions = dream:newBuffer('vec3', 'float', cantidad)
    malla.faces = dream:newBuffer('vec3', 'uint32_t', cantidad / 3)
    return malla
end

local function terminarMalla(malla, cantidad)
    local caras = malla.faces.buffer
    for indice = 0, cantidad / 3 - 1 do
        caras[indice].x = indice * 3 + 1
        -- El intercambio de Y y Z cambia la orientación de las caras.
        caras[indice].y = indice * 3 + 3
        caras[indice].z = indice * 3 + 2
    end
    malla:updateBoundingSphere()
    return malla
end

--- Material de 3Dream con las `opciones` de `desdeMalla` (nombre,
-- rugosidad, metalico, alfa y los campos del terreno).
function Conversor:material(opciones)
    local material = self.dream:newMaterial(opciones.nombre or 'NationsRTS')
    material:setRoughness(opciones.rugosidad or 0.82)
    material:setMetallic(opciones.metalico or 0.02)
    if opciones.alfa then
        material:setColor(1, 1, 1, opciones.alfa)
        material:setAlpha()
    end
    material.texturaTerreno = opciones.texturaTerreno
    material.escalaTexturaTerreno = opciones.escalaTexturaTerreno
    material.fuerzaRelieveTerreno = opciones.fuerzaRelieveTerreno
    material.nivelMarTerreno = opciones.nivelMarTerreno
    return material
end

--- Malla de 3Dream de una malla de batalla/malla.lua. Con `opciones.material`,
-- usa ese material (compartido) en vez de hacer uno.
function Conversor:desdeMalla(mallaLove, opciones)
    local fuente = Malla.datosDe(mallaLove)
    if not fuente then
        return nil
    end
    opciones = opciones or {}
    local material = opciones.material or self:material(opciones)
    local resultado = prepararMalla(self.dream, fuente.vertices, material, opciones.pixelShader)
    local origen = ffi.cast('float*', fuente.datos:getFFIPointer())
    local vertices = resultado.vertices.buffer
    local normales = resultado.normals.buffer
    local colores = resultado.colors.buffer
    local rugosidades = resultado.roughnesses.buffer
    local metalicos = resultado.metallics.buffer
    local emisiones = resultado.emissions.buffer
    local escala = Conversor.escala
    for indice = 0, fuente.vertices - 1 do
        local posicion = indice * FLOTANTES
        vertices[indice].x = (origen[posicion] - self.cx) * escala
        vertices[indice].y = origen[posicion + 2] * escala
        vertices[indice].z = (origen[posicion + 1] - self.cy) * escala
        normales[indice].x = origen[posicion + 3]
        normales[indice].y = origen[posicion + 5]
        normales[indice].z = origen[posicion + 4]
        colores[indice].x = origen[posicion + 6] ^ 2.2
        colores[indice].y = origen[posicion + 7] ^ 2.2
        colores[indice].z = origen[posicion + 8] ^ 2.2
        colores[indice].w = opciones.alfa or 1
        rugosidades[indice] = opciones.rugosidad or 0.82
        metalicos[indice] = opciones.metalico or 0.02
        emisiones[indice].x = 0
        emisiones[indice].y = 0
        emisiones[indice].z = 0
    end
    return terminarMalla(resultado, fuente.vertices)
end

--- Como `desdeMalla`, pero sin restar el centro del área: para prototipos en
-- coordenadas locales (origen en su base) que luego se instancian.
function Conversor:desdeMallaLocal(mallaLove, opciones)
    local cx, cy = self.cx, self.cy
    self.cx, self.cy = 0, 0
    local resultado = self:desdeMalla(mallaLove, opciones)
    self.cx, self.cy = cx, cy
    return resultado
end

function Conversor:desdeVertices(verticesFuente, colorNacion, nombre, tono)
    local cantidad = #verticesFuente
    tono = tono or 1
    local material = self.dream:newMaterial(nombre)
    material:setRoughness(0.62)
    material:setMetallic(0.45)
    local resultado = prepararMalla(self.dream, cantidad, material)
    local vertices = resultado.vertices.buffer
    local normales = resultado.normals.buffer
    local colores = resultado.colors.buffer
    local rugosidades = resultado.roughnesses.buffer
    local metalicos = resultado.metallics.buffer
    local emisiones = resultado.emissions.buffer
    local escala = Conversor.escala
    for indice, fuente in ipairs(verticesFuente) do
        local destino = indice - 1
        local nacion = fuente[10] or 0
        vertices[destino].x = fuente[1] * escala
        vertices[destino].y = fuente[3] * escala
        vertices[destino].z = fuente[2] * escala
        normales[destino].x = fuente[4]
        normales[destino].y = fuente[6]
        normales[destino].z = fuente[5]
        local rojo = (fuente[7] * (1 - nacion) + colorNacion[1] * nacion) * tono
        local verde = (fuente[8] * (1 - nacion) + colorNacion[2] * nacion) * tono
        local azul = (fuente[9] * (1 - nacion) + colorNacion[3] * nacion) * tono
        colores[destino].x = rojo ^ 2.2
        colores[destino].y = verde ^ 2.2
        colores[destino].z = azul ^ 2.2
        colores[destino].w = 1
        rugosidades[destino] = 0.62
        metalicos[destino] = 0.45
        emisiones[destino].x = 0
        emisiones[destino].y = 0
        emisiones[destino].z = 0
    end
    return terminarMalla(resultado, cantidad)
end

--- Convierte una matriz de modelo del juego a una transformación de 3Dream.
function Conversor:matriz(matriz)
    local escala = Conversor.escala
    return self.dream.mat4({
        matriz[1],
        matriz[3],
        matriz[2],
        (matriz[4] - self.cx) * escala,
        matriz[9],
        matriz[11],
        matriz[10],
        matriz[12] * escala,
        matriz[5],
        matriz[7],
        matriz[6],
        (matriz[8] - self.cy) * escala,
        0,
        0,
        0,
        1,
    })
end

return Conversor

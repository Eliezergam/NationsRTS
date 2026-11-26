-- Mapa de campaña en 3D: el relieve real del Cáucaso y el Mar Negro
-- (tools/mapa/caucaso.py) con 3DreamEngine.
--
-- Unidades de 3Dream: 1 = 1 km. X al este, Z al sur, Y arriba; el centro del
-- mapa está en el origen. La altura va exagerada (`datos.exageracion`).
--
-- El suelo es campana/relieve.lua: las alturas del DEM (~92 m) en un árbol
-- con niveles de detalle según la distancia. El mapa de normales (~185 m)
-- trae la normal del mundo tal cual (rojo: este, verde: norte, azul: arriba)
-- y el sombreador (campana/sombreador_mapa.lua) la lee sin pasar por la de
-- los vértices, que es la de la malla (para el sesgo de la sombra del sol).
-- De cerca, el sombreador añade las texturas de detalle de la batalla.

local Relieve = require('campana.relieve')
local SombreadorMapa = require('campana.sombreador_mapa')

local Mapa3D = {}
Mapa3D.__index = Mapa3D

Mapa3D.colorMar = { 0.05, 0.13, 0.2 }
-- El plano del mar, unos metros por debajo del 0: las tierras bajas junto al
-- Caspio están a 0,5 m, y de lejos el mar a 0 se peleaba con ellas por la
-- profundidad (rayas oscuras en la vista general).
Mapa3D.alturaMar = -0.01

local CARPETA = 'assets/mapa/'

local function cargarTextura(archivo, lineal)
    local imagen = love.graphics.newImage(CARPETA .. archivo, { mipmaps = true, linear = lineal })
    imagen:setFilter('linear', 'linear', 8)
    imagen:setMipmapFilter('linear')
    imagen:setWrap('clamp', 'clamp')
    return imagen
end

function Mapa3D.nuevo(dream)
    package.loaded['campana/sombreador_mapa'] = SombreadorMapa
    dream:registerShader('campana/sombreador_mapa', 'mapaCampana')
    local self = setmetatable({}, Mapa3D)
    self.dream = dream
    self.datos = love.filesystem.load(CARPETA .. 'caucaso.lua')()
    local datos = self.datos
    self.ancho = datos.anchoMetros / 1000
    self.alto = datos.altoMetros / 1000
    self.material = dream:newMaterial('mapaCampana')
    self.material:setAlbedoTexture(cargarTextura('caucaso_color.jpg', false))
    self.material:setNormalTexture(cargarTextura('caucaso_normal.png', true))
    self.material:setRoughness(0.92)
    self.material:setMetallic(0)
    self.material.detalleCampana = SombreadorMapa.cargarDetalle()
    self.material.costaCampana = cargarTextura('caucaso_costa.png', true)
    self.relieve = Relieve.nuevo(dream, datos, self.material)
    self.mar = self:crearMar()
    return self
end

--- Altura del suelo (sin el mar) en el punto x, z del mapa.
function Mapa3D:altura(x, z)
    return self.relieve:altura(x, z)
end

--- Elige el detalle del relieve para la cámara (campana/camara.lua) y hace
-- las mallas que falten (`sinLimite`: todas, para las capturas).
function Mapa3D:actualizar(camara, sinLimite)
    local ojoX, ojoY, ojoZ = camara:puntos()
    local dream = self.dream
    self.relieve:actualizar(ojoX, ojoY, ojoZ, love.graphics.getHeight(), dream.camera:getFov(), sinLimite)
end

function Mapa3D:crearMar()
    local dream = self.dream
    local material = dream:newMaterial('marCampana')
    material:setRoughness(0.18)
    material:setMetallic(0)
    local malla = dream:newMesh(material)
    malla:setPixelShader('simple')
    malla.vertices = dream:newBuffer('vec3', 'float', 4)
    malla.normals = dream:newBuffer('vec3', 'float', 4)
    malla.colors = dream:newBuffer('vec4', 'float', 4)
    malla.roughnesses = dream:newBuffer('scalar', 'float', 4)
    malla.metallics = dream:newBuffer('scalar', 'float', 4)
    malla.emissions = dream:newBuffer('vec3', 'float', 4)
    local esquinas = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
    local color = Mapa3D.colorMar
    for indice, esquina in ipairs(esquinas) do
        local k = indice - 1
        malla.vertices.buffer[k].x = esquina[1] * self.ancho * 0.5
        malla.vertices.buffer[k].y = Mapa3D.alturaMar
        malla.vertices.buffer[k].z = esquina[2] * self.alto * 0.5
        malla.normals.buffer[k].y = 1
        malla.colors.buffer[k].x = color[1] ^ 2.2
        malla.colors.buffer[k].y = color[2] ^ 2.2
        malla.colors.buffer[k].z = color[3] ^ 2.2
        malla.colors.buffer[k].w = 1
        malla.roughnesses.buffer[k] = 0.18
        malla.metallics.buffer[k] = 0
    end
    malla.faces = dream:newBuffer('vec3', 'uint32_t', 2)
    local caras = malla.faces.buffer
    caras[0].x, caras[0].y, caras[0].z = 1, 3, 2
    caras[1].x, caras[1].y, caras[1].z = 2, 3, 4
    malla:updateBoundingSphere()
    return malla
end

function Mapa3D:dibujar()
    self.relieve:dibujar()
    self.dream:draw(self.mar)
end

return Mapa3D

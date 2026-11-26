-- Sombra de contacto (el dueño, 17-nov). Las sombras de las lámparas del
-- almacén son estáticas (solo recogen lo que no se mueve: hacerlas dinámicas
-- partía los FPS por la mitad) y sin sombra los robots parecían flotar. Como
-- las sombras de cápsula de Unreal o las manchas de contacto de muchos
-- juegos: el modelo trae bajo la base la placa `sombraSuelo` (UV de 0 a 1,
-- tools/blender/robot_almacen.py `placaSombra`) y aquí se le pone un
-- degradado negro que se desvanece hacia el borde. Va pegada a la base, así
-- que se mueve y gira con el robot. Casi no cuesta nada.

local dream = require('lib.3DreamEngine')

---@class Sombra : Robot
local Sombra = {}

Sombra.oscuridad = 0.65 -- lo negra que es en el centro (0..1)

local material -- compartido por todos los robots

local function crearMaterial()
    local n = 256
    local datos = love.image.newImageData(n, n)
    datos:mapPixel(function(x, y)
        local u, v = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
        local a = math.max(0, 1 - math.sqrt(u * u + v * v))
        a = a * a * (3 - 2 * a) -- suave hacia el borde
        return 0, 0, 0, a
    end)
    local imagen = love.graphics.newImage(datos, { mipmaps = true })
    imagen:setFilter('linear', 'linear')
    local m = dream:newMaterial('sombraContacto')
    m:setAlbedoTexture(imagen)
    m:setColor(0, 0, 0, Sombra.oscuridad)
    m:setRoughness(1)
    m:setMetallic(0)
    m:setAlpha()
    return m
end

-- En pausa (17-nov): con transparencia el motor no la dibuja. Mientras,
-- la placa se oculta (si no, sale blanca bajo las ruedas).
Sombra.activa = false

function Sombra:onLoad()
    if not self:getTienePieza('sombraSuelo') then
        return
    end
    if not Sombra.activa then
        self:getPieza('sombraSuelo').visible = false
        return
    end
    material = material or crearMaterial()
    local placa = self:getPieza('sombraSuelo')
    for _, malla in pairs(placa.objeto and placa.objeto.meshes or {}) do
        malla:setMaterial(material)
        malla:setShadowVisibility(false)
    end
end

return Sombra

-- Carga de imágenes con el filtro adecuado a cada una.
--
-- El editor y los juegos usan filtro `nearest` por defecto, que es lo correcto
-- para pixel art pequeño (32 px). Pero el arte pintado a mano en grande (256 px
-- o más) se ve dentado al reducirlo a una celda de 64 o 128 px. A partir de
-- `Images.smoothFrom` píxeles de lado, la imagen se carga con mipmaps y filtro
-- lineal: se reduce limpia y sigue nítida a zoom 1.
--
--   local Images = require('runtime.images')
--   local image = Images.load('assets/terreno/plains00.png')
--   local image = Images.fromData(imageData)

local Images = {}

-- Lado a partir del cual una imagen se trata como arte grande.
Images.smoothFrom = 128

--- Aplica el filtro según el tamaño. Devuelve la imagen.
function Images.configure(image)
    if image and math.max(image:getWidth(), image:getHeight()) >= Images.smoothFrom then
        image:setFilter('linear', 'linear')

        if image:getMipmapCount() > 1 then
            image:setMipmapFilter('linear')
        end
    end

    return image
end

--- Imagen a partir de un `ImageData`, con mipmaps si es grande.
function Images.fromData(data)
    local w, h = data:getDimensions()
    local settings = nil

    if math.max(w, h) >= Images.smoothFrom then
        settings = { mipmaps = true }
    end

    return Images.configure(love.graphics.newImage(data, settings))
end

--- Imagen desde una ruta del sistema de archivos de LÖVE. Lanza si no existe.
function Images.load(path)
    return Images.fromData(love.image.newImageData(path))
end

return Images

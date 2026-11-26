-- Biblioteca de materiales PBR para 3DreamEngine (Camila). Cada subcarpeta de
-- `carpeta` es un material con el nombre de la carpeta: albedo, normal y
-- material (R metálico, G rugosidad, B oclusión) en .jpg o .png, opcional
-- emision, y un material.lua con sus factores (y `alpha` si es
-- semitransparente). Los .glb que nombran ese material lo usan en vez del
-- suyo (loader/gltf.lua mira `dream.materialLibrary`).
--
-- Hace lo mismo que `dream:loadMaterialLibrary`, pero con rutas explícitas:
-- aquel busca las texturas en el índice de imágenes que 3Dream arma al
-- arrancar, y ese índice no entra en carpetas enlazadas (los arneses de
-- pruebas montan el juego con enlaces). Así las texturas cargan igual en el
-- juego y en las pruebas, con mipmaps y repetición (resources.lua). Se cargan
-- al momento (`getImage(ruta, true)`): con la carga en segundo plano de 3Dream
-- los primeros cuadros salían con la textura blanca por defecto.
--
-- Salen de tools/blender/pbr_unidades.py (unidades) y texturas_base.py (base).

local BibliotecaPbr = {}

local extensiones = { 'jpg', 'png' }

local function buscarImagen(carpeta, nombre)
    for _, extension in ipairs(extensiones) do
        local ruta = carpeta .. '/' .. nombre .. '.' .. extension
        if love.filesystem.getInfo(ruta, 'file') then
            return ruta
        end
    end
    return nil
end

--- El sombreador de los cristales, registrado una vez.
local function registrarCristal(dream)
    if not dream.shaderRegister.cristalBatalla then
        dream:registerShader('batalla/dream/cristal', 'cristalBatalla')
    end
    return 'cristalBatalla'
end

--- Registra en `dream` los materiales de `carpeta`. Devuelve cuántos.
function BibliotecaPbr.cargar(dream, carpeta)
    local cantidad = 0
    for _, nombre in ipairs(love.filesystem.getDirectoryItems(carpeta)) do
        local ruta = carpeta .. '/' .. nombre
        local albedo = buscarImagen(ruta, 'albedo')
        if albedo then
            local material = dream:newMaterial(nombre)
            local archivoFactores = ruta .. '/material.lua'
            local factores = {}
            if love.filesystem.getInfo(archivoFactores, 'file') then
                factores = love.filesystem.load(archivoFactores)()
                material:setRoughness(factores.roughness or 1)
                material:setMetallic(factores.metallic or 1)
            end
            material:setAlbedoTexture(dream:getImage(albedo, true))
            local normal = buscarImagen(ruta, 'normal')
            if normal then
                material:setNormalTexture(dream:getImage(normal, true))
            end
            local mapa = buscarImagen(ruta, 'material')
            if mapa then
                material:setMaterialTexture(dream:getImage(mapa, true))
            end
            -- Luces que brillan solas (faros del camión): emision.jpg.
            local emision = buscarImagen(ruta, 'emision')
            if emision then
                material:setEmissionTexture(dream:getImage(emision, true))
            end
            -- Semitransparente (cristales): `alpha` en material.lua. Vidrio
            -- dieléctrico (sin metálico) con su reflejo del cielo y el sol
            -- sin atenuar (batalla/dream/cristal.lua).
            if factores.alpha then
                material:setAlpha()
                material:setColor(1, 1, 1, factores.alpha)
                material:setMetallic(0)
                material:setWorldShader(registrarCristal(dream))
            end
            material.library = true
            dream:registerMaterial(material)
            cantidad = cantidad + 1
        end
    end
    return cantidad
end

return BibliotecaPbr

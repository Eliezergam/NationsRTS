-- Hilo de las maquetas del mapa (mundo/maquetas.lua): genera en segundo
-- plano la geometría de cada sitio (mundo/maqueta_geometria.lua) y guarda en
-- disco las imágenes ya horneadas, para no parar el cuadro del mapa.
--
-- Pedidos del canal `maquetas.pedidos`:
--   { dueno, semilla, clave, sitio }   la geometría -> `maquetas.hechos`
--   { guardar = ruta, imagen, meta }   escribe la imagen (PNG) y su .lua
--   { limpiar = raiz, version }        borra las cachés de otras versiones
--   { salir = true }

require('love.filesystem')
require('love.data')
require('love.image')
require('love.timer')

local MaquetaGeometria = require('mundo.maqueta_geometria')

local pedidos = love.thread.getChannel('maquetas.pedidos')
local hechos = love.thread.getChannel('maquetas.hechos')

local function borrar(ruta)
    local info = love.filesystem.getInfo(ruta)
    if info and info.type == 'directory' then
        for _, nombre in ipairs(love.filesystem.getDirectoryItems(ruta)) do
            borrar(ruta .. '/' .. nombre)
        end
    end
    love.filesystem.remove(ruta)
end

while true do
    local p = pedidos:demand()
    if p.salir then
        break
    end
    if p.guardar then
        pcall(function()
            local png = p.imagen:encode('png')
            love.filesystem.write(p.guardar .. '.png', png)
            png:release()
            love.filesystem.write(p.guardar .. '.lua', p.meta)
        end)
        p.imagen:release()
    elseif p.limpiar then
        for _, nombre in ipairs(love.filesystem.getDirectoryItems(p.limpiar)) do
            if nombre ~= p.version then
                borrar(p.limpiar .. '/' .. nombre)
            end
        end
    else
        local inicio = love.timer.getTime()
        local ok, r = pcall(MaquetaGeometria.hacer, p.semilla, p.sitio)
        if ok and r then
            r.clave = p.clave
            r.dueno = p.dueno
            r.ms = (love.timer.getTime() - inicio) * 1000
            hechos:push(r)
        else
            hechos:push({ clave = p.clave, dueno = p.dueno, error = tostring(r or 'sin plano') })
        end
    end
end

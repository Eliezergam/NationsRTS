-- Hilo del territorio: construye los vértices de la malla de territorio de un
-- trozo (`Territorio.construir`, `mundo/territorio.lua`) en segundo plano.
--
-- Lee pedidos del canal `territorio.pedidos` y deja cada respuesta en el canal
-- que diga el pedido (`canal`, uno por mundo), con los mismos tx, ty, firma y
-- generacion para que el mundo la reconozca, y `datos` (ByteData, o nada si no
-- hay que pintar) o `error`. `{ salir = true }` termina el hilo.

require('love.data')

local Territorio = require('mundo.territorio')

local pedidos = love.thread.getChannel('territorio.pedidos')

while true do
    local p = pedidos:demand()
    if p.salir then
        break
    end
    local ok, datos = pcall(Territorio.construir, p)
    local respuesta = { tx = p.tx, ty = p.ty, firma = p.firma, generacion = p.generacion }
    if ok then
        respuesta.datos = datos
    else
        respuesta.error = tostring(datos)
    end
    love.thread.getChannel(p.canal):push(respuesta)
    if ok and datos then
        datos:release()
    end
end

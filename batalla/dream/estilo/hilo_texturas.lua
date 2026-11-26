-- Hilo que pinta las texturas del estilo (texturas.lua) mientras la batalla
-- genera el suelo. Devuelve por el canal, para cada textura, una tabla con
-- su nombre y sus niveles de mipmap (ImageData); al final, 'fin'.

require('love.filesystem')
require('love.image')
require('love.math')
require('love.timer')

local canal = ...
local Texturas = require('batalla.dream.estilo.texturas')

local inicio = love.timer.getTime()
for nombre, niveles in pairs(Texturas.generarNiveles()) do
    local mensaje = { nombre }
    for k, nivel in ipairs(niveles) do
        mensaje[k + 1] = nivel
    end
    canal:push(mensaje)
end
print(string.format('ESTILO texturas pintadas en el hilo en %.2f s', love.timer.getTime() - inicio))
canal:push('fin')

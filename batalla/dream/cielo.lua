-- Blacksmith deja que 3Dream dibuje directamente un cielo horneado. Aquí se
-- usa el mismo camino estable con un panorama exterior, mientras la extensión
-- sky aporta la luz solar y ambiental correspondiente al mediodía.

local Cielo = {}

local cieloDinamico

function Cielo.cargar(dream)
    cieloDinamico = require('lib.3DreamEngine.extensions.sky')
    cieloDinamico:setSunOffset(0, 0)

    return love.graphics.newCubeImage('batalla/dream/cielo.png')
end

function Cielo.iluminar(sol)
    cieloDinamico:setDaytime(sol, 0.25)
end

return Cielo

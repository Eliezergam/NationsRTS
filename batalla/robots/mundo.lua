-- Lo que los robots (que viven en metros: batalla/robots/robot.lua) pueden
-- saber del mundo de la batalla. No preguntan nunca qué es cada cosa: tocan
-- colisiones (batalla/colisiones.lua) y leen sus etiquetas.
--
--   MundoBatalla.usarSuelo(suelo)                  la batalla y sus colisiones
--   MundoBatalla.usarFisica(fisica)                el mundo físico (Jolt) de la batalla
--   MundoBatalla.altura(x, y)                      m del suelo en (x, y) m
--   MundoBatalla.rayo(x, y, z, dx, dy, dz, alcance)
--       lo que toca un rayo (sensores, ojos, balas): distancia, etiquetas,
--       colisión y punto; nil si nada hasta `alcance`
--   MundoBatalla.cerca(x, y, radio, etiqueta, salida)
--       colisiones con esa etiqueta a menos de `radio` m (su contorno)

local MundoBatalla = {}

local PX = 10 -- px por metro
local suelo, colisiones, fisica

function MundoBatalla.usarSuelo(s)
    suelo = s
    colisiones = s and s:getColisiones()
end

function MundoBatalla.usarFisica(f)
    fisica = f
end

function MundoBatalla.getSuelo()
    return suelo
end

function MundoBatalla.getFisica()
    return fisica
end

--- Lo que pisan los robots: el terreno o la losa de un patio encima.
-- Superficies puestas encima del terreno (la pista del avión de carga,
-- batalla/dream/pista_avion.lua): cada una con su :altura(x, y) m o nil.
MundoBatalla.superficies = {}

--- `excluir`: una superficie que no cuenta (la bodega del avión, para él).
function MundoBatalla.altura(x, y, excluir)
    local z = suelo:alturaPisable(x * PX, -y * PX) / PX
    for _, s in ipairs(MundoBatalla.superficies) do
        local zs = s ~= excluir and s:altura(x, y)
        if zs and zs > z then
            z = zs
        end
    end
    return z
end

--- Rayo contra el mundo físico de la batalla.
function MundoBatalla.rayo(x, y, z, dx, dy, dz, alcance)
    if not fisica then
        return nil
    end
    local d, c, px, py, pz = fisica:rayo(x, y, z, dx, dy, dz, alcance or 100)
    if not d then
        return nil
    end
    return d, c.etiquetas, c, px, py, pz
end

function MundoBatalla.cerca(x, y, radio, etiqueta, salida)
    salida = salida or {}
    if not colisiones then
        for k = #salida, 1, -1 do
            salida[k] = nil
        end
        return salida
    end
    return colisiones:cerca(x, y, radio, etiqueta, salida)
end

return MundoBatalla

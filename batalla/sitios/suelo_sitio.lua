-- Suelo ligero de un sitio (ciudad o mina) para generar su plano fuera de la
-- batalla: la maqueta del mapa (mundo/maquetas.lua) sale del mismo plano
-- que se ve al entrar (batalla/sitios/plano.lua).
--
-- Es lo que el plano necesita del suelo de la batalla (batalla/suelo.lua) y
-- nada más: el terreno del mapa a tamaño real alrededor del sitio
-- (batalla/terreno_escalado.lua) en una rejilla uniforme, con las mismas
-- explanadas (desmonte y terraplén de cada edificio, calle y pista). Sin
-- agua, plantas, pasillos ni cauces: la batalla añade encima su ondulación
-- de menos de un metro, así que los edificios salen a la misma altura.
--
-- Coordenadas: las de la batalla (10 px = 1 m) con el centro en el punto del
-- sitio en el mapa: el punto (x, y) de aquí es el (cx + (x - cx) / 10, …) del
-- mapa, como en una batalla centrada en el sitio.
--
--   local suelo = SueloSitio.nuevo(terrenoDelMapa, x, y)
--   local plano = Plano.generar(suelo, sitio) -- sitio.x, sitio.y = x, y

local Rejilla = require('batalla.rejilla')
local Suelo = require('batalla.suelo')
local TerrenoEscalado = require('batalla.terreno_escalado')

local SueloSitio = {}
SueloSitio.__index = SueloSitio

SueloSitio.paso = 80 -- px (8 m) entre vértices
-- px a cada lado del sitio: el recinto de la capital con el aeródromo al
-- norte (de -7360 a 4480 px), la pista (4000 px a cada lado) y sus taludes.
SueloSitio.medio = 10400
SueloSitio.escala = 10 -- el mapa, ampliado como en la batalla

function SueloSitio.nuevo(terrenoMapa, cx, cy)
    local self = setmetatable({}, SueloSitio)
    self.terreno = TerrenoEscalado.nuevo(terrenoMapa, cx, cy, SueloSitio.escala)
    self.cx, self.cy = cx, cy
    -- El plano busca lo llano dentro de `lado` (como en la batalla).
    self.lado = Suelo.lado
    self.nivelMar = self.terreno.nivelMar
    local paso, medio = SueloSitio.paso, SueloSitio.medio
    local xs, ys = {}, {}
    for d = -medio, medio, paso do
        xs[#xs + 1] = cx + d
        ys[#ys + 1] = cy + d
    end
    local rej = Rejilla.nueva(xs, ys)
    self.relieve = rej
    local lado = rej.lado
    local px, py, ph = rej.x, rej.y, rej.h
    local terreno = self.terreno
    for j = 0, lado - 1 do
        local y = ys[j + 1]
        for i = 0, lado - 1 do
            local k = j * lado + i
            local x = xs[i + 1]
            px[k], py[k] = x, y
            ph[k] = terreno:base(x, y)
        end
    end
    return self
end

--- Altura (px) en (x, y): la de la rejilla, ya explanada. Fuera, la del mapa.
function SueloSitio:altura(x, y)
    local medio = SueloSitio.medio
    if math.abs(x - self.cx) > medio or math.abs(y - self.cy) > medio then
        return self.terreno:base(x, y)
    end
    return self.relieve:interpolar(self.relieve.h, x, y)
end

-- Las explanadas, las mismas de la batalla (trabajan sobre `relieve`).
SueloSitio.vertices = Suelo.vertices
SueloSitio.explanarCaja = Suelo.explanarCaja
SueloSitio.explanar = Suelo.explanar
SueloSitio.explanarTramo = Suelo.explanarTramo

return SueloSitio

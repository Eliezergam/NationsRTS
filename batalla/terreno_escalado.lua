-- El terreno del mundo a tamaño real, solo para la batalla 3D (el dueño,
-- 19-nov: «nuestro juego no tiene alturas ni tamaño real de las cosas»;
-- eligió «solo la batalla 3D a tamaño real»).
--
-- El mapa 2D (mundo/terreno.lua) está hecho en px de mapa: tierra y mar se
-- alternan cada ~500 m, las colinas miden 2 m y las montañas 170 m como
-- mucho. La batalla usa 10 px = 1 m, así que leído tal cual es una maqueta.
-- Aquí la batalla lee el mapa ampliado `escala` veces alrededor del sitio
-- del combate (cx, cy): el punto (x, y) de la batalla es el
-- (cx + (x - cx) / escala, …) del mapa, y las alturas sobre el nivel del mar
-- se multiplican por `escala` (las pendientes no cambian; las montañas
-- llegan a ~1,7 km y las colinas a decenas de metros). El mapa 2D, la
-- simulación y las ciudades no cambian.
--
-- Lo que decide el tipo de suelo (bioma) sale del mapa sin ampliar: si no,
-- cualquier colina ampliada sería roca o nieve.

local TerrenoEscalado = {}
TerrenoEscalado.__index = TerrenoEscalado

function TerrenoEscalado.nuevo(terreno, cx, cy, escala)
    local self = setmetatable({}, TerrenoEscalado)
    self.mapa = terreno
    self.cx, self.cy = cx, cy
    self.escala = escala
    self.semilla = terreno.semilla
    self.nivelMar = terreno.nivelMar
    -- Ruido de detalle (manchas de color de 62 m): en coordenadas de la
    -- batalla, como antes.
    self.detalle = terreno.detalle
    -- Las ciudades del mapa son de maqueta (90 m): en la batalla a tamaño
    -- real no se aplana nada por ellas.
    self.ciudades = nil
    return self
end

function TerrenoEscalado:aMapa(x, y)
    local e = self.escala
    return self.cx + (x - self.cx) / e, self.cy + (y - self.cy) / e
end

function TerrenoEscalado:ampliar(h)
    return self.nivelMar + (h - self.nivelMar) * self.escala
end

function TerrenoEscalado:altura(x, y)
    local u, v = self:aMapa(x, y)
    return self:ampliar(self.mapa:base(u, v))
end

function TerrenoEscalado:base(x, y)
    local u, v = self:aMapa(x, y)
    return self:ampliar(self.mapa:base(u, v))
end

function TerrenoEscalado:humedadEn(x, y)
    local u, v = self:aMapa(x, y)
    return self.mapa:humedadEn(u, v)
end

function TerrenoEscalado:bioma(x, y)
    local u, v = self:aMapa(x, y)
    local tipo, h = self.mapa:bioma(u, v)
    return tipo, self:ampliar(h)
end

--- Altura sin ampliar (la del mapa) en un punto de la batalla: para los
-- umbrales de color (roca y nieve), que están en alturas del mapa.
function TerrenoEscalado:alturaMapa(x, y)
    local u, v = self:aMapa(x, y)
    return self.mapa:base(u, v)
end

return TerrenoEscalado

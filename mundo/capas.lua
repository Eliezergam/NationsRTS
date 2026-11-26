-- Capas del mapa según el zoom (como Warpath, diseno/referencias-warpath/zoom_*.jpg).
--
--   cerca   del 13 % al 8 %: el mapa entero (terreno con detalle, árboles,
--           torres, instalaciones, vehículos).
--   media   del 8 % al 5,5 %: terreno liso y sencillo, sin árboles; ciudades,
--           instalaciones y yacimientos como iconos pequeños con su nombre; los
--           ejércitos, con su banderín.
--   lejos   por debajo del 5,5 %: el mapa estratégico. Terreno oscuro con
--           relieve, territorios con su borde de color, solo capitales y
--           batallas, y a la izquierda las casillas de capas.
--
-- Entre una capa y otra hay un fundido de un punto de zoom (del 8,5 % al 7,5 %
-- y del 6 % al 5 %): `pesos` dice cuánto se ve de cada una (suman 1).
-- Solo es vista: la simulación no sabe nada de esto.

local Capas = {}

Capas.cerca = 0.08 -- centro del fundido cerca → media
Capas.lejos = 0.055 -- centro del fundido media → lejos
Capas.banda = 0.01 -- ancho de cada fundido (en zoom)

local function recorte(t)
    return math.max(0, math.min(1, t))
end

--- Cuánto se ve de cada capa con este zoom: cerca, media, lejos (suman 1).
function Capas.pesos(zoom)
    local b = Capas.banda / 2
    local cerca = recorte((zoom - (Capas.cerca - b)) / Capas.banda)
    local lejos = recorte(((Capas.lejos + b) - zoom) / Capas.banda)
    return cerca, math.max(0, 1 - cerca - lejos), lejos
end

--- Casillas de capas del mapa estratégico (las que no son el territorio, que
-- va con la tecla T): qué se muestra. Las mira `Mundo:dibujar`.
function Capas.nuevas()
    -- Los yacimientos, apagados: como la «densidad de recursos» de Warpath.
    return { ejercitos = true, yacimientos = false, batallas = true }
end

return Capas

--- Explosiones de la batalla 3D (Valeria, batalla/DANO-REAL.md §6.3 y §7):
-- obuses explosivos, cohetes y misiles. Radio letal y de metralla según la
-- ojiva; la metralla se atenúa con una prueba barata de línea de visión
-- (terreno, árboles y rocas, vehículos y el edificio); la onda avería los
-- vehículos sin penetrar.

local Blindaje = require('batalla.dano.blindaje')
local Cuerpos = require('batalla.dano.cuerpos')
local Impactos = require('batalla.impactos')

local Explosiones = {}

local cerca = {}
local tapan = {}
local golpe = {}

--- ¿Hay algo entre (x0, y0, z0) y (x1, y1, z1) que pare la metralla?
-- Terreno, árboles y rocas, vehículos (también averiados) y el edificio.
function Explosiones.cubierto(tropas, x0, y0, z0, x1, y1, z1, salvo)
    local suelo = tropas.suelo
    if Impactos.terreno(suelo, x0, y0, z0, x1, y1, z1) then
        return true
    end
    if Impactos.arboles(suelo, x0, y0, z0, x1, y1, z1) then
        return true
    end
    local lista = tropas.cuerpos:candidatos(x0, y0, x1, y1, 0, salvo, tapan)
    return #lista > 0 and Cuerpos.cruzar(lista, x0, y0, z0, x1, y1, z1, golpe) ~= nil
end

--- La metralla y la onda de una explosión en (x, y, z) con la `ojiva` (de
-- Datos.ojiva o la explosiva de un cañón: letal, metralla en px, onda).
-- Lo que alcanza se apunta en las averías del vehículo.
function Explosiones.estallar(tropas, x, y, z, ojiva)
    local azar = tropas.azar
    local letal, metralla = ojiva.letal, ojiva.metralla
    local lista = tropas.cuerpos:cerca(x, y, math.max(metralla, letal), cerca)
    for _, c in ipairs(lista) do
        local u = c.u
        if u and not u.muerto then
            local dx, dy = u.x - x, u.y - y
            local dz = (u.z + 12) - z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if u.averias then
                if d < letal then
                    Blindaje.onda(u, 1 - d / letal, ojiva, azar)
                end
                if d < metralla then
                    Blindaje.metralla(u, 1 - d / metralla, azar)
                end
                tropas:revisarVehiculo(u)
            end
        end
    end
end

return Explosiones

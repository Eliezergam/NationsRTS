-- Vista isométrica 2:1, la misma del editor (runtime/projection.lua):
--   vista.x = x - y        vista.y = (x + y) / 2 - altura * 1.2247
-- El mundo es un plano (x, y) con alturas; todo se dibuja en coordenadas de vista.

local Iso = {}

Iso.escalaAltura = math.sqrt(1.5)

function Iso.vista(x, y, z)
    return x - y, (x + y) * 0.5 - (z or 0) * Iso.escalaAltura
end

--- Punto de la vista a punto del suelo (a altura 0).
function Iso.mundo(vx, vy)
    return vy + vx * 0.5, vy - vx * 0.5
end

--- Profundidad de dibujo: lo de delante (más abajo en pantalla) va después.
function Iso.profundidad(x, y)
    return x + y
end

return Iso

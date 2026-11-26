-- Límite del campo de batalla: un círculo dentro del área generada del que no
-- sale ningún vehículo ni el punto al que mira la cámara. Es el único sitio
-- donde se define: la formación, el movimiento, la física y la cámara lo leen
-- de `suelo.limite`.
--
-- Solo limita en el plano (x, y). Hacia arriba no hay techo: las balas y los
-- misiles suben lo que quieran, y si caen fuera explotan en la llanura del
-- faldón (ver Suelo:alturaFaldon).
--
-- Fuera del círculo el terreno sigue (3,5 km de mapa real y luego el faldón
-- hasta el horizonte): se ve, pero no se puede ir.

local Limite = {}
Limite.__index = Limite

Limite.radio = 12000 -- px (1,2 km) del centro del área al borde del límite

--- Límite circular de centro (cx, cy) y `radio` px.
function Limite.nuevo(cx, cy, radio)
    local self = setmetatable({}, Limite)
    self.cx = cx
    self.cy = cy
    self.radio = radio or Limite.radio
    return self
end

--- ¿Cabe entero un objeto de `radio` px con centro en (x, y)?
function Limite:dentro(x, y, radio)
    local r = self.radio - (radio or 0)
    local dx = x - self.cx
    local dy = y - self.cy
    return dx * dx + dy * dy <= r * r
end

--- (x, y) metido dentro del límite para un objeto de `radio` px: si está
-- fuera, el punto más cercano del borde (se desliza a lo largo de él).
function Limite:ajustar(x, y, radio)
    local r = math.max(0, self.radio - (radio or 0))
    local dx = x - self.cx
    local dy = y - self.cy
    local d2 = dx * dx + dy * dy
    if d2 <= r * r then
        return x, y
    end
    local d = math.sqrt(d2)
    return self.cx + dx / d * r, self.cy + dy / d * r
end

--- Distancia (px) de (x, y) al borde; negativa si está fuera.
function Limite:margen(x, y)
    local dx = x - self.cx
    local dy = y - self.cy
    return self.radio - math.sqrt(dx * dx + dy * dy)
end

return Limite

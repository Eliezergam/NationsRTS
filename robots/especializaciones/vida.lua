-- Lo que hace que el robot se vea vivo aunque esté quieto: los anillos de los
-- oídos giran (A y C en un sentido, B en el otro) y las persianas de los ojos
-- parpadean de vez en cuando.
--
-- Persianas (tools/blender/robot_soldado.py, persianas): cada ojo tiene 4
-- láminas arriba (`persianaSup{S}{k}`) y 4 abajo (`persianaInf{S}{k}`); al
-- cerrar, la lámina k baja (las de arriba) o sube (las de abajo) k pasos de
-- PASO metros y entre todas tapan el ojo.

local Vida = {}

Vida.oidos = { A = 0.8, B = -1.4, C = 2.2 } -- rad/s de cada anillo
Vida.parpadeo = 0.18 -- s que dura un parpadeo (cerrar y abrir)
Vida.entreParpadeos = { 2.5, 6.0 } -- s entre parpadeos, al azar
Vida.PASO = 0.0338 * 0.95 / 4 -- PERSIANA_R · OJO_ESCALA / PERSIANA_LAMINAS
Vida.LAMINAS = 4

function Vida:onLoad()
    local d = self.datos.vida
    d.tiempo = 0
    d.proximo = love.math.random() * 3 + 1
    d.parpado = 0 -- 0 abierto, 1 cerrado
end

--- Cierra las persianas `f` (0 abiertas, 1 cerradas).
function Vida.setParpados(self, f)
    for _, s in ipairs({ 'Izq', 'Der' }) do
        for k = 1, Vida.LAMINAS - 1 do
            local baja = k * Vida.PASO * f
            self:getPieza('persianaSup' .. s .. k):setDesplazamiento(0, 0, -baja)
            self:getPieza('persianaInf' .. s .. k):setDesplazamiento(0, 0, baja)
        end
    end
end

function Vida:onUpdate(dt)
    -- Con ojos de verdad (mirada.lua) los oídos y el parpadeo los pone ella.
    if self.datos.mirada then
        return
    end
    local d = self.datos.vida
    d.tiempo = d.tiempo + dt
    for _, s in ipairs({ 'Izq', 'Der' }) do
        for letra, w in pairs(Vida.oidos) do
            self:getPieza('oido' .. s .. letra):setGiro('y', d.tiempo * w)
        end
    end
    -- Parpadeo: cierra y abre en `parpadeo` s.
    local f = 0
    local desde = d.tiempo - d.proximo
    if desde >= 0 then
        if desde < Vida.parpadeo then
            f = math.sin(desde / Vida.parpadeo * math.pi)
        else
            local a, b = Vida.entreParpadeos[1], Vida.entreParpadeos[2]
            d.proximo = d.tiempo + a + love.math.random() * (b - a)
        end
    end
    Vida.setParpados(self, f)
end

return Vida

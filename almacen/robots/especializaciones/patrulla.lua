-- Rutina de patrulla (ejemplo de script de robot): da vueltas por el almacén
-- y hace algo en cada parada usando solo las órdenes del robot (setIrA,
-- setMirarA, setBrazo, setPinza, setAgachar...). Para otra rutina, copia este
-- archivo, cambia PARADAS y pon su nombre en almacen/robots/tipos/.
--
-- Cada parada: { x, y, rumbo al llegar, mirar = {x, y, z}, gesto = '...' }.
-- Gestos: 'pinzas' (abre y cierra las dos), 'senalar' (levanta el brazo
-- derecho hacia lo que mira), 'revisar' (se agacha y mira abajo), nil (nada).
--
-- Medidas del almacén (tools/blender/almacen_interior.py): el pasillo de los
-- racks va por y = 0 de x = -28,5 a -3; el portón del polvorín está en
-- x = -30 con el contador encima (z = 7,4); la puerta de la sala de control
-- está en (5,75, 3).

---@class Patrulla : Robot
local Patrulla = {}

Patrulla.PARADAS = {
    { 5.75, 1.6, math.pi / 2, mirar = { 5.75, 9, 1.6 }, gesto = 'pinzas' },
    { -2.0, 0.0 },
    { -25.5, 0.0, math.pi, mirar = { -29.6, 0, 7.4 }, gesto = 'senalar' },
    { -18.5, 0.6, math.pi / 2, mirar = { -18.5, 2.6, 0.4 }, gesto = 'revisar' },
    { -2.0, 0.0 },
}
Patrulla.espera = 2.0 -- segundos de cada gesto

function Patrulla:onLoad()
    local d = self.datos.patrulla
    d.parada = 1
    d.estado = 'ir'
    d.reloj = 0
    local p = Patrulla.PARADAS[1]
    self:setIrA(p[1], p[2], p[3])
end

--- Lo que hace en la parada según el tiempo `t` desde que llegó.
function Patrulla.gesto(self, nombre, t)
    if nombre == 'pinzas' then
        local ciclo = math.floor(t / 0.9)
        local abierta = ciclo % 2 == 0
        -- Apertura al azar de la pinza izquierda: se sortea una vez cada vez
        -- que abre (no en cada fotograma, que la haría temblar), entre
        -- 3 cm y 10 cm (el máximo de la pinza).
        local d = self.datos.patrulla
        if d.cicloPinza ~= ciclo then
            d.cicloPinza = ciclo
            d.aperturaPinza = 0.03 + math.random() * 0.07
        end
        local numerad = d.aperturaPinza
        self:setBrazo('izq', 0.5, 0.1, 0.4, 0)
        self:setBrazo('der', 0.5, 0.1, 0.4, abierta and 0.6 or 0)
        self:setPinza('izq', abierta and numerad or 0)
        self:setPinza('der', abierta and 0.1 or 0)
    elseif nombre == 'senalar' then
        self:setBrazo('der', 1.6, 0.15, -0.2, 0)
        self:setPinza('der', 0.02)
    elseif nombre == 'revisar' then
        -- Se agacha y adelanta las manos hacia el estante de abajo.
        self:setAgachar(1)
        self:setBrazo('izq', 0.35, 0.05, -0.25, 0)
        self:setBrazo('der', 0.35, 0.05, -0.25, 0)
        self:setPinza('izq', 0.08)
        self:setPinza('der', 0.08)
    end
end

--- Vuelve a la pose de andar.
function Patrulla.descansar(self)
    self:setBrazo('izq', 0, 0, 0, 0)
    self:setBrazo('der', 0, 0, 0, 0)
    self:setPinza('izq', 0.05)
    self:setPinza('der', 0.05)
    self:setAgachar(0)
    self:setMirarA(nil)
end

function Patrulla:onUpdate(dt)
    local d = self.datos.patrulla
    local p = Patrulla.PARADAS[d.parada]
    d.reloj = d.reloj + dt
    if d.estado == 'ir' then
        if self:getHaLlegado() then
            d.estado = 'gesto'
            d.reloj = 0
            if p.mirar then
                self:setMirarA(p.mirar[1], p.mirar[2], p.mirar[3])
            end
        end
    elseif d.estado == 'gesto' then
        if p.gesto and d.reloj < Patrulla.espera then
            Patrulla.gesto(self, p.gesto, d.reloj)
        else
            Patrulla.descansar(self)
            d.parada = d.parada % #Patrulla.PARADAS + 1
            local q = Patrulla.PARADAS[d.parada]
            self:setIrA(q[1], q[2], q[3])
            d.estado = 'ir'
            d.reloj = 0
        end
    end
end

GestorRobots.registrarEspecializacion('patrulla', Patrulla)
return Patrulla

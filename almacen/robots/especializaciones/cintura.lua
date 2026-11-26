-- Cintura del robot grande: el torso gira 360° sobre las orugas (la cabeza
-- no: solo mira a los lados, como la del robot pequeño). El torso, con la
-- cabeza, mira siempre hacia donde va el robot (el dueño, 2026-11-17); las
-- orugas van hacia delante o marcha atrás, da igual.
--   - Sin nada en las garras, solo: marcha atrás, el torso da media vuelta;
--     hacia delante, mira al frente de las orugas.
--   - Con carga o trabajando con los brazos, el torso va donde se le pide
--     (Robot:setCintura): con una caja de 9 m el trabajo decide cuándo
--     girarla y dónde hay sitio (encajado.lua).
-- El frente del robot (hacia donde mira el torso): Robot:getFrente().

---@class Cintura : Robot
local Cintura = {}
local Robot = GestorRobots.Robot

Cintura.velocidadTorso = 0.6 -- rad/s
Cintura.marcha = 0.03 -- m/s: más que esto, va hacia donde se mueve

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Cintura:onLoad()
    local d = self.datos.cintura
    d.torso, d.libre = 0, 0
end

function Cintura:onUpdate(dt)
    local d = self.datos.cintura
    if d.pedido == nil then
        -- Solo: hacia donde se mueve (parado, se queda como estaba).
        local c = self.datos.conduccion
        if c and c.destino and c.destino[1] and math.abs(self.velocidad) > Cintura.marcha then
            d.libre = c.destino.atras and math.pi or 0
        elseif self.velocidad < -Cintura.marcha then
            d.libre = math.pi
        elseif self.velocidad > Cintura.marcha then
            d.libre = 0
        end
    end
    local objetivo = d.pedido or d.libre
    local falta = angulo(objetivo - d.torso)
    local paso = Cintura.velocidadTorso * dt
    if math.abs(falta) <= paso then
        d.torso = objetivo
    else
        d.torso = angulo(d.torso + paso * (falta > 0 and 1 or -1))
    end
end

function Cintura:onPose()
    self:getPieza('torso'):setGiro('z', self.datos.cintura.torso, 'cintura')
end

--- Gira el torso a `angulo` rad respecto a las orugas y lo deja ahí (nil:
-- vuelve a ir solo hacia donde se mueve el robot).
function Robot:setCintura(angulo_)
    self.datos.cintura.pedido = angulo_
end

--- true si el torso ha llegado a `angulo` rad respecto a las orugas.
function Robot:getCinturaEn(angulo_)
    return math.abs(angulo(self.datos.cintura.torso - angulo_)) < 0.005
end

--- Hacia dónde mira el torso (rad del almacén).
function Robot:getFrente()
    return self.rumbo + self.datos.cintura.torso
end

GestorRobots.registrarEspecializacion('cintura', Cintura)
return Cintura

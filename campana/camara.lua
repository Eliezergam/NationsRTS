-- Cámara del mapa de campaña, como la de Bannerlord: mira a un punto del
-- suelo desde una distancia, con un rumbo y una inclinación. Al acercarse se
-- inclina sola hacia el horizonte; lejos mira casi desde arriba.
-- Unidades de campana/mapa3d.lua (1 = 1 km).

local Camara = {}
Camara.__index = Camara

Camara.distanciaMin = 3
Camara.distanciaMax = 700
Camara.inclinacionCerca = math.rad(32) -- sobre el horizonte, a la distancia mínima
Camara.inclinacionLejos = math.rad(72) -- a la distancia máxima
Camara.velocidad = 0.9 -- pantallas por segundo al desplazarse
Camara.pasoRueda = 1.18

function Camara.nueva(mapa, x, z, distancia, rumbo)
    local self = setmetatable({}, Camara)
    self.mapa = mapa
    self.x = x or 0
    self.z = z or 0
    self.distancia = distancia or 400
    self.rumbo = rumbo or 0
    self.ajusteInclinacion = 0
    return self
end

--- Inclinación sobre el horizonte, según lo cerca que esté y el ajuste del jugador.
function Camara:inclinacion()
    local t = math.log(self.distancia / Camara.distanciaMin) / math.log(Camara.distanciaMax / Camara.distanciaMin)
    local base = Camara.inclinacionCerca + (Camara.inclinacionLejos - Camara.inclinacionCerca) * t
    return math.max(math.rad(12), math.min(math.rad(89), base + self.ajusteInclinacion))
end

--- Ojo y punto mirado, en coordenadas de 3Dream.
function Camara:puntos()
    local mira = self.mapa:altura(self.x, self.z)
    mira = math.max(mira, 0)
    local inclinacion = self:inclinacion()
    local horizontal = math.cos(inclinacion) * self.distancia
    local ojoX = self.x - math.sin(self.rumbo) * horizontal
    local ojoZ = self.z + math.cos(self.rumbo) * horizontal
    local ojoY = mira + math.sin(inclinacion) * self.distancia
    -- Que el ojo no se meta en una montaña.
    ojoY = math.max(ojoY, math.max(self.mapa:altura(ojoX, ojoZ), 0) + 0.4)
    return ojoX, ojoY, ojoZ, self.x, mira, self.z
end

function Camara:aplicar(dream)
    local ojoX, ojoY, ojoZ, miraX, miraY, miraZ = self:puntos()
    local ojo = dream.vec3(ojoX, ojoY, ojoZ)
    local mira = dream.vec3(miraX, miraY, miraZ)
    dream.camera:setTransform(dream:lookAt(ojo, mira):invert())
    dream.camera:setNear(math.max(0.02, self.distancia * 0.01))
    dream.camera:setFar(self.distancia * 6 + 400)
end

--- Desplaza la mira (adelante y a la derecha según el rumbo), en pantallas.
function Camara:desplazar(adelante, derecha)
    local paso = self.distancia * 0.8
    local senoRumbo, cosenoRumbo = math.sin(self.rumbo), math.cos(self.rumbo)
    self.x = self.x + (senoRumbo * adelante + cosenoRumbo * derecha) * paso
    self.z = self.z + (-cosenoRumbo * adelante + senoRumbo * derecha) * paso
    local mapa = self.mapa
    self.x = math.max(-mapa.ancho / 2, math.min(mapa.ancho / 2, self.x))
    self.z = math.max(-mapa.alto / 2, math.min(mapa.alto / 2, self.z))
end

function Camara:acercar(pasos)
    local distancia = self.distancia / Camara.pasoRueda ^ pasos
    self.distancia = math.max(Camara.distanciaMin, math.min(Camara.distanciaMax, distancia))
end

function Camara:girar(rumbo, inclinacion)
    self.rumbo = self.rumbo + rumbo
    self.ajusteInclinacion = math.max(math.rad(-40), math.min(math.rad(30), self.ajusteInclinacion + inclinacion))
end

function Camara:actualizar(dt)
    local teclado = love.keyboard
    local adelante, derecha, giro = 0, 0, 0
    if teclado.isDown('w', 'up') then
        adelante = adelante + 1
    end
    if teclado.isDown('s', 'down') then
        adelante = adelante - 1
    end
    if teclado.isDown('d', 'right') then
        derecha = derecha + 1
    end
    if teclado.isDown('a', 'left') then
        derecha = derecha - 1
    end
    if teclado.isDown('q') then
        giro = giro - 1
    end
    if teclado.isDown('e') then
        giro = giro + 1
    end
    if adelante ~= 0 or derecha ~= 0 then
        self:desplazar(adelante * Camara.velocidad * dt, derecha * Camara.velocidad * dt)
    end
    if giro ~= 0 then
        self:girar(giro * 1.4 * dt, 0)
    end
end

return Camara

-- Audio posicional de la batalla mediante la extensión sound de 3Dream.
-- Todos los archivos son mono para que OpenAL pueda ubicarlos en el mundo.

local sound = require('lib.3DreamEngine.extensions.sound')

local Sonido = {}
Sonido.__index = Sonido

function Sonido.nuevo(dream, conversor)
    local self = setmetatable({}, Sonido)
    self.dream = dream
    self.conversor = conversor
    sound:addLibrary('assets/sonidos/batalla')
    return self
end

--- La extensión ordena las copias de cada sonido por `Source:tell()`, que
-- avanza mientras ordena: con muchas copias sonando (las salvas del BM-21),
-- `table.sort` puede fallar con «invalid order function». Un sonido que no
-- sale no debe tumbar la batalla: ese se pierde y sigue.
function Sonido:reproducir(nombre, x, y, z, volumen, tono)
    local dx, dy, dz = self.conversor:punto(x, y, z)
    pcall(sound.play, sound, nombre, self.dream.vec3(dx, dy, dz), volumen, tono, 0.16, 0.02)
end

function Sonido:actualizarOyente(ojo, mira)
    local direccion = (mira - ojo):normalize()
    love.audio.setPosition(ojo:unpack())
    love.audio.setOrientation(direccion.x, direccion.y, direccion.z, 0, 1, 0)
end

return Sonido

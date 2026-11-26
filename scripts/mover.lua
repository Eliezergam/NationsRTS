-- Script de ejemplo. Asignalo a un objeto desde el inspector (fila Script, boton ...).
-- Contrato: new(obj, world, params) -> entidad con update(dt) y opcionalmente draw().
--   obj    = el objeto al que pertenece este script (this / self.obj)
--   world  = acceso al resto del nivel: world.Carpeta.Nombre, world:nearest(obj,'unit',300)
--   params = los parametros que agregas en el inspector con "+ Parametro"
local Mover = {}
Mover.__index = Mover

function Mover.new(obj, world, params)
    local self = setmetatable({}, Mover)
    self.obj = obj
    self.velocidad = params.velocidad or 100 -- pixeles por segundo
    return self
end

function Mover:update(dt)
    -- se llama cada frame; multiplica por dt para no depender de los FPS
    self.obj.x = self.obj.x + self.velocidad * dt
end

return Mover

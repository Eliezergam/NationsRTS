-- El robot conductor lleva el camión de misiles (el dueño, 18-nov: «este toma
-- decisiones con el camión»). Paso 1: va al puesto de tiro (`destino`, m; la
-- escena lo pone con robot:setPuestoTiro) girando la dirección hacia él,
-- frena al llegar y se queda parado (`estado` = 'llegado'). Lo siguiente
-- (desplegar, disparar, mirar el misil) se apoya en este estado.

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local Pilotar = {}

Pilotar.velocidad = 8 -- m/s de crucero
Pilotar.frenarDesde = 25 -- m: empieza a frenar
Pilotar.llegar = 2.5 -- m
Pilotar.giroPorRad = 1.4 -- dirección por radián de error de rumbo

function Pilotar.onLoad(self)
    self.datos.pilotar.estado = 'esperando'
end

--- Adónde disparar al llegar (m).
function Robot:setBlanco(x, y)
    self.datos.pilotar.blanco = { x, y }
end

--- Adónde llevar el camión (m, en el marco de los robots).
function Robot:setPuestoTiro(x, y)
    local d = self.datos.pilotar
    d.destino = { x, y }
    d.estado = 'yendo'
    local v = self.vehiculo
    if v then
        print(('CAMION va de (%.1f, %.1f) al puesto de tiro (%.1f, %.1f) m'):format(v.x, v.y, x, y))
    end
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Pilotar.onUpdate(self, dt)
    local d = self.datos.pilotar
    local v = self.vehiculo
    if not v or not v.setConducir then
        return
    end
    if d.estado ~= 'yendo' then
        v:setConducir(0, 0)
        return
    end
    local dx, dy = d.destino[1] - v.x, d.destino[2] - v.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < Pilotar.llegar then
        d.estado = 'llegado'
        print(('CAMION llega al puesto de tiro (%.1f, %.1f) m'):format(v.x, v.y))
        v:setConducir(0, 0)
        -- Parado: despliega y dispara al blanco (si lo tiene).
        if d.blanco and v.setDisparar then
            v:setDisparar(d.blanco[1], d.blanco[2])
        end
        return
    end
    local error = angulo(math.atan2(dy, dx) - v.rumbo)
    local vel = Pilotar.velocidad * math.min(1, dist / Pilotar.frenarDesde)
    -- Muy torcido: despacio mientras gira.
    vel = vel * math.max(0.3, math.cos(error))
    v:setConducir(math.max(1.2, vel), error * Pilotar.giroPorRad)
end

Nucleo.registrarEspecializacion('pilotar', Pilotar)
return Pilotar

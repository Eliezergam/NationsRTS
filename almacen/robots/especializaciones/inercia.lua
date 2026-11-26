-- Inercia de la cabeza (animación procedural, el dueño 17-nov: «un poquito
-- para probar»). Nada grabado: cada cuadro se calcula con lo que hace el
-- robot de verdad. La cabeza cuelga del cuello como de un muelle con
-- amortiguador (oscilador de segundo orden):
--
--     aceleración = -rigidez · desvío - amortiguación · velocidad + empuje
--
-- El empuje sale del cuerpo: al girar, la cabeza se queda atrás (empuje
-- contrario a la aceleración del giro); al frenar, cabecea hacia delante, y
-- al arrancar se echa atrás (empuje contrario a la aceleración del avance).
-- El muelle la devuelve con un rebote pequeño que se apaga solo. Se suma
-- (por capas) a lo que ponen la mirada y el reposo.

---@class Inercia : Robot
local Inercia = {}

Inercia.frecuencia = 2.2 -- Hz: rapidez con la que la cabeza vuelve a su sitio
Inercia.amortiguacion = 0.28 -- 0 rebota para siempre, 1 vuelve sin rebote
Inercia.empujeGiro = 0.06 -- rad de retraso por rad/s² de aceleración de giro
Inercia.empujeAvance = 0.08 -- rad de cabeceo por m/s² de aceleración
Inercia.maximo = 0.22 -- rad: lo más que se desvía

function Inercia:onLoad()
    local d = self.datos.inercia
    d.lado, d.vLado = 0, 0 -- giro de la cabeza a los lados (rad, rad/s)
    d.cabeceo, d.vCabeceo = 0, 0 -- hacia delante (+) y atrás (-)
    d.giroAntes = self.giro or 0
    d.velocidadAntes = self.velocidad or 0
end

-- Un paso del muelle: devuelve la posición y la velocidad nuevas.
local function muelle(x, v, empuje, dt)
    local w = 2 * math.pi * Inercia.frecuencia
    local a = -w * w * x - 2 * Inercia.amortiguacion * w * v + empuje * w * w
    v = v + a * dt
    x = x + v * dt
    return math.max(-Inercia.maximo, math.min(Inercia.maximo, x)), v
end

function Inercia:onUpdate(dt)
    if dt <= 0 then
        return
    end
    local d = self.datos.inercia
    -- Aceleraciones del cuerpo en este cuadro (suavizadas un poco: las de un
    -- solo cuadro dan tirones).
    local acelGiro = ((self.giro or 0) - d.giroAntes) / dt
    local acelAvance = ((self.velocidad or 0) - d.velocidadAntes) / dt
    d.giroAntes, d.velocidadAntes = self.giro or 0, self.velocidad or 0
    d.acelGiro = (d.acelGiro or 0) + (acelGiro - (d.acelGiro or 0)) * math.min(1, dt * 12)
    d.acelAvance = (d.acelAvance or 0) + (acelAvance - (d.acelAvance or 0)) * math.min(1, dt * 12)
    -- Varios pasos pequeños: el muelle es estable aunque baje el FPS.
    local pasos = math.max(1, math.ceil(dt / 0.005))
    local h = dt / pasos
    for _ = 1, pasos do
        d.lado, d.vLado = muelle(d.lado, d.vLado, -d.acelGiro * Inercia.empujeGiro, h)
        d.cabeceo, d.vCabeceo = muelle(d.cabeceo, d.vCabeceo, -d.acelAvance * Inercia.empujeAvance, h)
    end
end

function Inercia:onPose()
    local d = self.datos.inercia
    self:getPieza('cuello'):setGiro('z', d.lado)
    -- Girar la cabeza en y positivo la baja (cabecea hacia delante).
    self:getPieza('cabeza'):setGiro('y', d.cabeceo)
end

GestorRobots.registrarEspecializacion('inercia', Inercia)
return Inercia

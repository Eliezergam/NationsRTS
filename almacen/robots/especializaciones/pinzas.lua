-- Manos de tres dedos (como la Robotiq 3-Finger): dos dedos a un lado y uno
-- enfrente. Cierran en «pinza»: la falange gira hacia dentro y la punta lo
-- contrario, así las almohadillas quedan paralelas y aprietan de frente. La
-- apertura es la distancia entre las almohadillas de los dos lados.
--
-- Órdenes que añade al robot:
--   robot:setPinza(lado, apertura)   lado 'izq' o 'der'; apertura: metros
--                                    entre las gomas, de 0 (cerrada) a
--                                    Pinzas.aperturaMaxima
--   robot:getPinza(lado)             la apertura de ahora (metros)
--   robot:getPuntoAgarre(lado)       x, y, z en el almacén del punto entre
--                                    las yemas (donde irá lo que coja)

---@class Pinzas : Robot
local Pinzas = {}
local Robot = GestorRobots.Robot

-- Medidas de la mano (tools/blender/robot_almacen.py, MANO_*).
Pinzas.nudilloY = 0.045
Pinzas.falange = 0.05
Pinzas.almohadilla = 0.008
Pinzas.reposo = 2 * (Pinzas.nudilloY - Pinzas.almohadilla) -- apertura del modelo
Pinzas.aperturaMaxima = 0.1
Pinzas.rapidez = 0.15 -- m/s (el triple desde el 21-nov: abre y cierra en un tercio del tiempo)

-- Ángulo de las falanges (hacia dentro) para una apertura.
function Pinzas.angulo(apertura)
    local s = (Pinzas.nudilloY - Pinzas.almohadilla - apertura / 2) / Pinzas.falange
    return math.asin(math.max(-1, math.min(1, s)))
end

function Pinzas:onLoad()
    local d = self.datos.pinzas
    d.izq = { ahora = Pinzas.reposo, objetivo = Pinzas.reposo }
    d.der = { ahora = Pinzas.reposo, objetivo = Pinzas.reposo }
end

function Pinzas:onUpdate(dt)
    for _, p in pairs(self.datos.pinzas) do
        local paso = Pinzas.rapidez * dt
        p.ahora = p.ahora + math.max(-paso, math.min(paso, p.objetivo - p.ahora))
    end
end

function Pinzas:onPose()
    for lado, p in pairs(self.datos.pinzas) do
        local s = lado == 'izq' and 'Izq' or 'Der'
        local a = Pinzas.angulo(p.ahora)
        -- A y B están a -y (cierran girando a +); C a +y (cierra girando a -).
        for letra, k in pairs({ A = -1, B = -1, C = 1 }) do
            self:getPieza('dedo' .. s .. letra):setGiro('z', -k * a)
            self:getPieza('punta' .. s .. letra):setGiro('z', k * a)
        end
    end
end

--- Abre o cierra la pinza `lado` ('izq' o 'der') a `apertura` metros.
function Robot:setPinza(lado, apertura)
    self.datos.pinzas[lado].objetivo = math.max(0, math.min(Pinzas.aperturaMaxima, apertura or 0))
end

--- Apertura de la pinza ahora (metros entre las gomas).
function Robot:getPinza(lado)
    return self.datos.pinzas[lado].ahora
end

--- x, y, z del punto entre las yemas de la pinza `lado`, en el almacén.
function Robot:getPuntoAgarre(lado)
    return self:getPieza(lado == 'izq' and 'agarreIzq' or 'agarreDer'):getPosicion()
end

GestorRobots.registrarEspecializacion('pinzas', Pinzas)
return Pinzas

-- Control de vuelo de la batalla: el `cameraController` del ejemplo
-- firstpersongame de 3DreamEngine, sin reescribirlo. Su `update` (aceleración,
-- resistencia del aire, A/D y Espacio) y su `mousemoved` (0,005 rad por px)
-- se usan tal cual; este archivo traduce ejes y unidades y cambia dos cosas
-- que decidió el dueño: Ctrl baja (el ejemplo usa Shift izquierdo, que aquí
-- queda para sumar a la selección) y W/S empujan hacia la mirada en 3D (el
-- ejemplo empuja solo en horizontal), con la misma aceleración e inercia.
--
-- Ejes: el ejemplo trabaja con Y hacia arriba (como 3Dream) y aquí se le dan
-- px del juego: x del controlador = x del juego, y = altura (z del juego),
-- z = y del juego. Con esos ejes, su avance (seno de ry, -coseno de ry) es la
-- mirada horizontal de la cámara cuando rumbo = ry + pi / 2, y su rx (positivo
-- hacia arriba) es la inclinación con el signo cambiado (positiva hacia abajo).

local Base = require('lib.3DreamEngine.extensions.utils.cameraController')

local Controlador = setmetatable({}, { __index = Base })
Controlador.__index = Controlador

-- La resistencia del aire del ejemplo es 5/s: la rapidez de crucero es la
-- aceleración pedida dividida entre 5. Se pide la aceleración que da la
-- rapidez de crucero que quiere la cámara.
Controlador.resistencia = 5
Controlador.teclas = { 'w', 'a', 's', 'd', 'space', 'lctrl', 'rctrl' }

--- Fracción independiente de la frecuencia de cuadros.
function Controlador.fraccion(k, dt)
    return 1 - math.exp(-k * dt)
end

--- Un controlador por cámara: el del ejemplo es un único objeto compartido,
-- así que cada cámara lleva su propio estado y hereda sus funciones.
function Controlador.nuevo()
    local self = setmetatable({}, Controlador)
    self.x = 0
    self.y = 0
    self.z = 0
    self.rx = 0
    self.ry = 0
    self:detener()
    return self
end

--- Olvida la inercia (encuadres, pérdida de foco).
function Controlador:detener()
    self.vx = 0
    self.vy = 0
    self.vz = 0
    self.impulso = false
end

--- Copia la orientación de la cámara (rumbo e inclinación del juego).
function Controlador:orientar(rumbo, inclinacion)
    self.ry = rumbo - math.pi / 2
    self.rx = -inclinacion
end

--- Rumbo e inclinación del juego para la orientación actual.
function Controlador:angulos()
    return self.ry + math.pi / 2, -self.rx
end

--- Ratón relativo, igual que en el ejemplo.
function Controlador:mirar(dx, dy)
    self:mousemoved(dx, dy)
end

--- Rueda: un impulso en la dirección de la mirada que la resistencia del
-- aire del ejemplo frena; recorre `distancia` px en total.
function Controlador:empujar(distancia)
    local rumbo, inclinacion = self:angulos()
    local horizontal = math.cos(inclinacion)
    local v = distancia * Controlador.resistencia
    self.vx = self.vx - math.cos(rumbo) * horizontal * v
    self.vz = self.vz - math.sin(rumbo) * horizontal * v
    self.vy = self.vy - math.sin(inclinacion) * v
    self.impulso = true
end

--- ¿Hay alguna tecla de vuelo pulsada?
function Controlador.teclasPulsadas()
    for _, tecla in ipairs(Controlador.teclas) do
        if love.keyboard.isDown(tecla) then
            return true
        end
    end
    return false
end

--- Un paso del `update` del ejemplo desde el ojo (x, y, z del juego).
-- Devuelve el desplazamiento pedido en ejes del juego y si hubo entrada.
function Controlador:actualizar(dt, x, y, z, rapidez)
    self.x = x
    self.y = z
    self.z = y
    -- Shift (izquierdo o derecho) multiplica por tres la rapidez de WASD,
    -- Espacio, Ctrl y la rueda (batalla/dream/README.md). Shift por sí solo
    -- no mueve: queda para la selección múltiple.
    local teclado = love.keyboard
    local isDown = teclado.isDown
    if isDown('lshift', 'rshift') then
        rapidez = rapidez * 3
    end
    local aceleracion = rapidez * Controlador.resistencia
    -- El `update` del ejemplo ve Ctrl como su Shift izquierdo y no ve W/S.
    teclado.isDown = function(tecla)
        if tecla == 'lshift' then
            return isDown('lctrl', 'rctrl')
        elseif tecla == 'w' or tecla == 's' then
            return false
        end
        return isDown(tecla)
    end
    local correcto, error = pcall(self.update, self, dt, aceleracion)
    teclado.isDown = isDown
    assert(correcto, error)
    -- W/S: el mismo empuje (aceleración · dt, frenado por la resistencia del
    -- mismo paso) pero por la mirada. Sumarlo después del `update` da el mismo
    -- resultado que si el ejemplo lo sumara junto a las demás teclas.
    local avance = 0
    if isDown('w') then
        avance = avance + 1
    end
    if isDown('s') then
        avance = avance - 1
    end
    if avance ~= 0 then
        local rumbo, inclinacion = self:angulos()
        local horizontal = math.cos(inclinacion)
        local empuje = avance * aceleracion * dt * (1 - dt * Controlador.resistencia)
        self.vx = self.vx - math.cos(rumbo) * horizontal * empuje
        self.vz = self.vz - math.sin(rumbo) * horizontal * empuje
        self.vy = self.vy - math.sin(inclinacion) * empuje
    end
    local activo = Controlador.teclasPulsadas() or self.impulso
    self.impulso = false
    return self.x - x, self.z - y, self.y - z, activo
end

--- El límite o el suelo recortaron el paso en (bx, by, bz) px (lo pedido
-- menos lo recorrido, ejes del juego). Se quita la parte de la velocidad que
-- empuja contra ellos, para que no se acumule y la cámara se deslice.
function Controlador:recortar(bx, by, bz)
    local largo = math.sqrt(bx * bx + by * by)
    if largo > 0.000001 then
        local nx = bx / largo
        local ny = by / largo
        local hacia = self.vx * nx + self.vz * ny
        if hacia > 0 then
            self.vx = self.vx - nx * hacia
            self.vz = self.vz - ny * hacia
        end
    end
    if bz < -0.000001 and self.vy < 0 then
        self.vy = 0
    end
end

--- Velocidad actual en ejes del juego.
function Controlador:velocidad()
    return self.vx, self.vz, self.vy
end

return Controlador

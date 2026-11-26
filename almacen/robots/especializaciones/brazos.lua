-- Brazos y cuerpo: lleva cada articulación hacia el ángulo pedido sin saltos
-- (como un servo), balancea los brazos al andar y agacha el cuerpo doblando
-- la pierna (cadera, rodilla y cintura a la vez, para que el torso siga
-- derecho).
--
-- Órdenes que añade al robot (ángulos en radianes):
--   robot:setBrazo(lado, hombro, abrir, codo, munieca)
--       lado 'izq' o 'der'; hombro > 0 sube el brazo hacia delante; abrir > 0
--       lo separa del cuerpo; codo > 0 dobla el codo; munieca gira la mano
--       sobre el antebrazo. nil deja ese ángulo como estaba. Todo 0 es la pose
--       de la foto.
--   robot:getBrazo(lado)          hombro, abrir, codo, munieca de ahora
--   robot:setBrazosAbajo()        los dos abajo, pegados al cuerpo (para andar)
--   robot:setAgachar(f)           0 de pie ... 1 agachado (baja ~20 cm)
--   robot:setGirarCintura(a)      gira el torso sobre la cintura

---@class Brazos : Robot
local Brazos = {}
local Robot = GestorRobots.Robot

Brazos.rapidez = 1.1 -- rad/s de cada articulación
Brazos.balanceo = 0 -- rad de vaivén por m/s al andar (0: los brazos van quietos)
Brazos.agacharMaximo = 0.32 -- rad de la cadera agachado del todo

local ANGULOS = { 'hombro', 'abrir', 'codo', 'munieca' }

-- Límites de cada articulación (radianes, desde la pose de la foto), como
-- un brazo humano: nada se dobla al revés ni da vueltas.
--   hombro   −30° atrás … +140° adelante y arriba
--   abrir    −5° hacia el cuerpo … +65° hacia fuera
--   codo     en la foto ya está doblado 64°: de casi recto (−60°) a 145°
--            en total (+80°); nunca se dobla al revés
--   muñeca   ±90° (como girar el antebrazo)
Brazos.limites = {
    { math.rad(-30), math.rad(140) },
    { math.rad(-5), math.rad(65) },
    { math.rad(-60), math.rad(80) },
    { math.rad(-90), math.rad(90) },
}

--- El ángulo `k` (1 hombro, 2 abrir, 3 codo, 4 muñeca) dentro de su límite.
function Brazos.limitar(k, v)
    local l = Brazos.limites[k]
    return math.max(l[1], math.min(l[2], v))
end

-- Brazos abajo para andar sin tocar nada, en postura natural: hombro un
-- poco adelante, brazo algo separado del cuerpo y el codo doblado unos 30°
-- (el antebrazo baja hacia delante, las manos quedan bajo las mesas).
Brazos.abajo = { math.rad(7), math.rad(8), math.rad(-34), math.rad(-12) }

function Brazos:onLoad()
    local d = self.datos.brazos
    local a = Brazos.abajo
    d.izq = { objetivo = { a[1], a[2], a[3], a[4] }, ahora = { a[1], a[2], a[3], a[4] } }
    d.der = { objetivo = { a[1], a[2], a[3], a[4] }, ahora = { a[1], a[2], a[3], a[4] } }
    d.agachar, d.agacharObjetivo = 0, 0
    d.cintura, d.cinturaObjetivo = 0, 0
    d.paso = 0
end

local function acercar(a, b, paso)
    return a + math.max(-paso, math.min(paso, b - a))
end

function Brazos:onUpdate(dt)
    local d = self.datos.brazos
    local paso = (d.rapidez or Brazos.rapidez) * dt
    for _, lado in ipairs({ 'izq', 'der' }) do
        local b = d[lado]
        for k = 1, 4 do
            b.ahora[k] = acercar(b.ahora[k], b.objetivo[k], paso)
        end
    end
    d.agachar = acercar(d.agachar, d.agacharObjetivo, dt * 0.8)
    d.cintura = acercar(d.cintura, d.cinturaObjetivo, paso)
    d.paso = d.paso + math.abs(self.velocidad) * dt * 4
end

function Brazos:onPose()
    local d = self.datos.brazos
    -- Con algo en las manos no se balancean.
    local libres = not (self.datos.manipulacion and self.datos.manipulacion.objeto)
    local vaiven = libres and math.sin(d.paso) * math.min(1, math.abs(self.velocidad)) * Brazos.balanceo or 0
    for _, lado in ipairs({ 'izq', 'der' }) do
        local s = lado == 'izq' and 'Izq' or 'Der'
        local signo = lado == 'izq' and 1 or -1
        local a = d[lado].ahora
        -- Girar en y con ángulo negativo sube hacia delante.
        self:getPieza('hombro' .. s):setGiro('y', -(a[1] + vaiven * signo))
        self:getPieza('brazo' .. s):setGiro('x', signo * a[2])
        self:getPieza('codo' .. s):setGiro('y', -a[3])
        self:getPieza('munieca' .. s):setGiro('x', a[4])
    end
    -- Agachar: la espinilla se echa atrás, el muslo adelante el doble y la
    -- cintura compensa, así el torso no se inclina.
    local g = d.agachar * Brazos.agacharMaximo
    self:getPieza('espinilla'):setGiro('y', -g, 'agachar')
    self:getPieza('muslo'):setGiro('y', 2 * g)
    self:getPieza('torso'):setGiro('y', -g, 'agachar')
    self:getPieza('torso'):setGiro('z', d.cintura, 'cintura')
end

--- Pide los ángulos de un brazo (`lado`: 'izq' o 'der'); nil deja ese igual.
function Robot:setBrazo(lado, hombro, abrir, codo, munieca)
    local o = self.datos.brazos[lado].objetivo
    local valores = { hombro, abrir, codo, munieca }
    for k = 1, 4 do
        if valores[k] then
            o[k] = Brazos.limitar(k, valores[k])
        end
    end
end

--- hombro, abrir, codo, munieca del brazo ahora (radianes).
function Robot:getBrazo(lado)
    local a = self.datos.brazos[lado].ahora
    return a[1], a[2], a[3], a[4]
end

--- Baja los dos brazos pegados al cuerpo (la pose de andar).
function Robot:setBrazosAbajo()
    local a = Brazos.abajo
    for _, lado in ipairs({ 'izq', 'der' }) do
        if self.setManoA then
            self:setManoA(lado, nil)
        end
        self:setBrazo(lado, a[1], a[2], a[3], a[4])
    end
end

--- `true` si todas las articulaciones han llegado a lo pedido.
function Robot:getBrazosQuietos()
    local d = self.datos.brazos
    for _, lado in ipairs({ 'izq', 'der' }) do
        local b = d[lado]
        for k = 1, 4 do
            if math.abs(b.ahora[k] - b.objetivo[k]) > 0.004 then
                return false
            end
        end
    end
    return math.abs(d.agachar - d.agacharObjetivo) < 0.004
end

--- Rapidez de las articulaciones (rad/s); nil vuelve a la normal.
function Robot:setRapidezBrazos(rapidez)
    self.datos.brazos.rapidez = rapidez
end

--- 0 de pie ... 1 agachado.
function Robot:setAgachar(f)
    self.datos.brazos.agacharObjetivo = math.max(0, math.min(1, f or 0))
end

--- Gira el torso sobre la cintura (radianes; > 0 a la izquierda).
function Robot:setGirarCintura(a)
    self.datos.brazos.cinturaObjetivo = a or 0
end

Brazos.ANGULOS = ANGULOS
GestorRobots.registrarEspecializacion('brazos', Brazos)
return Brazos

-- Transporte: lleva objetos de un sitio a otro usando lo demás (navegación
-- con el mapa del lidar, cinemática de los brazos, pinzas). Cada encargo es
-- «coge este objeto y déjalo en el hueco N de este mueble». Está escrito
-- como una secuencia (una corrutina): cada paso espera a que el anterior
-- acabe.
--
--   1. Va a 0,7 m del objeto (ruta A* con lo que ve el lidar).
--   2. Sube las manos a la altura de trabajo y se acerca en recto hasta
--      quedar con la base bajo el canto del mueble.
--   3. Abre las pinzas, las pone 8 cm antes de los puntos de agarre y
--      entra hasta ellos; cierra hasta tocar (el grosor del agarre).
--   4. Lo levanta 6 cm, sale marcha atrás y lo lleva recogido al otro mueble.
--   5. Lo sube sobre el hueco, se acerca, lo baja en su sitio, abre, retira
--      las manos y sale. Todo despacio.
--
-- Órdenes que añade al robot:
--   robot:setLlevar(objeto, mueble, numero)   añade un encargo a la cola
--   robot:getEncargos()                       los que quedan
--   robot:getTarea()                          texto de lo que está haciendo
--   robot:getHechos()                         cuántos encargos ha terminado

---@class Transporte : Robot
local Transporte = {}
local Robot = GestorRobots.Robot

Transporte.atraque = 0.36 -- m del centro del robot al origen del objeto
Transporte.previo = 0.7 -- m más atrás, donde acaba la ruta
Transporte.ladoUnaMano = 0.25 -- con una mano se pone a un lado
Transporte.antesDelAgarre = 0.08
Transporte.levantar = 0.06
Transporte.aperturaLibre = 0.06
Transporte.alturaLlevar = 0.50
Transporte.llevarDelante = 0.36 -- m delante del hombro al llevar algo (antebrazo adelante)
Transporte.llevarBajo = 0.32 -- m por debajo del hombro (el brazo cuelga, codo abajo)
Transporte.paciencia = 10 -- s para que un brazo llegue antes de seguir igual
Transporte.velocidadAtraque = 0.4 -- m/s al acercarse al mueble (0,0 lo dejaba parado 15 s esperando llegar)
-- Prisa al mirar, coger y soltar: las pausas se acortan y los brazos van más
-- rápidos (el dueño, 21-nov: el triple). Andar no cambia.
Transporte.prisaManos = 3.0

function Transporte:onLoad()
    local d = self.datos.transporte
    d.encargos = {}
    d.hechos = 0
    d.tarea = 'esperando encargos'
end

function Transporte:onUpdate(dt)
    local d = self.datos.transporte
    -- Mientras explora la nave, los encargos esperan.
    if not d.hilo and self.getExplorando and self:getExplorando() then
        return
    end
    if not d.hilo and #d.encargos > 0 then
        local e = table.remove(d.encargos, 1)
        d.hilo = coroutine.create(function()
            Transporte.llevar(self, e.objeto, e.mueble, e.numero)
        end)
    end
    if d.hilo then
        local ok, error = coroutine.resume(d.hilo, dt)
        if not ok then
            print('ROBOT error en el encargo: ' .. tostring(error))
            d.hilo = nil
        elseif coroutine.status(d.hilo) == 'dead' then
            d.hilo = nil
            d.hechos = d.hechos + 1
            d.tarea = 'esperando encargos'
        end
    end
end

-- Pasos ----------------------------------------------------------------------------

local function esperar(condicion, maximo)
    local t = 0
    while not condicion() do
        t = t + coroutine.yield()
        if maximo and t > maximo then
            return false
        end
    end
    return true
end

local function pausa(segundos)
    local t = 0
    while t < segundos do
        t = t + coroutine.yield()
    end
end

-- La misma pausa, acortada por la prisa de las manos.
local function pausaManos(segundos)
    pausa(segundos / Transporte.prisaManos)
end

local function tarea(self, texto)
    self.datos.transporte.tarea = texto
    print('ROBOT', texto)
end

-- Del almacén a ejes del robot (x delante, y izquierda).
local function aRobot(self, x, y, z)
    local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
    local dx, dy = x - self.x, y - self.y
    return c * dx + s * dy, -s * dx + c * dy, z
end

local function ejeARobot(self, e)
    local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
    return { c * e[1] + s * e[2], -s * e[1] + c * e[2], e[3] }
end

local function manosEn(self, manos, tolerancia)
    for _, m in ipairs(manos) do
        if not self:getManoEn(m.lado, tolerancia) then
            return false
        end
    end
    return true
end

-- 'orejetaIzq' -> 'orejeta izquierda'.
local function nombrePunto(n)
    n = n:gsub('Izq$', ' izquierda'):gsub('Der$', ' derecha')
    return (n:gsub('(%l)(%u)', function(a, b)
        return a .. ' ' .. b:lower()
    end))
end

-- Mira el objeto hasta que los ojos lo reconocen y lee lo que es: el peso y
-- dónde se agarra (mira cada punto de agarre).
local function leer(self, objeto)
    local ox, oy, oz = objeto:getPosicion()
    local alto = objeto.datos.tamano and objeto.datos.tamano[3] or 0.2
    tarea(self, 'miro qué es')
    self:setMirarA(ox, oy, oz + alto * 0.6)
    local visto = esperar(function()
        return self:getHaVisto(objeto, 0.3)
    end, 4)
    if visto == false then
        print('ROBOT AVISO no consigo ver la ' .. objeto:getNombre())
    end
    local puntos = objeto:getPuntosAgarre()
    tarea(self, string.format('es una %s: pesa %d kg', objeto:getNombre(), objeto:getPeso()))
    pausaManos(1.4)
    for k, p in ipairs(puntos) do
        tarea(self, string.format('punto de agarre %d de %d: %s', k, #puntos, nombrePunto(p.nombre)))
        self:setMirarA(p.x, p.y, p.z)
        pausaManos(0.8)
    end
    self:setMirarA(ox, oy, oz + alto * 0.5)
end

-- Brazos abajo y espera a que lleguen (no anda con los brazos moviéndose).
local function brazosAbajo(self)
    self:setBrazosAbajo()
    esperar(function()
        return self:getBrazosQuietos()
    end, 6)
end

-- Dónde se para el robot para trabajar con algo en (x, y) que mira a
-- `rumbo`, con `lateral` m a su izquierda: el punto de atraque y el previo.
local function atraque(x, y, rumbo, lateral)
    local c, s = math.cos(rumbo), math.sin(rumbo)
    local ax = x - c * Transporte.atraque - s * lateral
    local ay = y - s * Transporte.atraque + c * lateral
    return ax, ay, ax - c * Transporte.previo, ay - s * Transporte.previo
end

-- Puntos de agarre de un objeto como si estuviera en (x, y, z, rumbo).
local function puntosEn(objeto, x, y, z, rumbo)
    local c, s = math.cos(rumbo), math.sin(rumbo)
    local r = {}
    for _, p in ipairs(objeto.puntosPropios or objeto.datos.puntos) do
        r[p[1]] = { x + c * p[2] - s * p[3], y + s * p[2] + c * p[3], z + p[4], eje = { c * p.eje[1] - s * p.eje[2], s * p.eje[1] + c * p.eje[2], p.eje[3] } }
    end
    return r
end

-- Ir hasta delante de algo y atracar (las manos ya puestas a su altura).
-- `antes`: lo que hace en el punto previo antes de acercarse (subir lo que
-- lleva por encima de la balda...).
local function irYAtracar(self, x, y, rumbo, lateral, texto, antes)
    local ax, ay, px, py = atraque(x, y, rumbo, lateral)
    tarea(self, texto)
    self:setNavegarA(px, py, rumbo)
    esperar(function()
        return not self:getNavegando()
    end)
    if antes then
        antes()
    end
    tarea(self, 'atracando despacio')
    self:setVelocidadMaxima(Transporte.velocidadAtraque)
    self:setIrA(ax, ay, rumbo)
    esperar(function()
        return self:getHaLlegado()
    end, 15)
    self:setVelocidadMaxima(nil)
end

-- Mueve las manos a sus objetivos y espera a que lleguen (con calma:
-- `rapidez` rad/s en las articulaciones).
local function moverManos(self, manos, objetivos, tolerancia, rapidez)
    self:setRapidezBrazos(rapidez * Transporte.prisaManos)
    for _, m in ipairs(manos) do
        local o = objetivos[m.lado]
        if o.relativo then
            self:setManoRelativa(m.lado, o[1], o[2], o[3], o.eje)
        else
            self:setManoA(m.lado, o[1], o[2], o[3], o.eje)
        end
    end
    local llego = esperar(function()
        return manosEn(self, manos, tolerancia)
    end, Transporte.paciencia)
    if not llego then
        for _, m in ipairs(manos) do
            print(string.format('ROBOT AVISO la mano %s no llegó (le faltan %.1f cm) en «%s»', m.lado, self:getManoError(m.lado) * 100, self.datos.transporte.tarea))
        end
    end
    self:setRapidezBrazos(nil)
end

function Transporte.llevar(self, objeto, mueble, numero)
    local d = self.datos.transporte
    local manos = self:getManosPara(objeto)
    local lateral = 0
    if #manos == 1 then
        lateral = manos[1].lado == 'der' and Transporte.ladoUnaMano or -Transporte.ladoUnaMano
    end
    local nombre = objeto:getNombre()
    local ox, oy, oz = objeto:getPosicion()
    local rumbo = objeto:getRumbo()
    -- Anda con los brazos abajo y quietos; no se mueve hasta tenerlos ahí.
    brazosAbajo(self)
    self:setFoco(ox, oy, oz + 0.1, objeto.apoyadoEn or objeto)
    irYAtracar(self, ox, oy, rumbo, lateral, 'voy a por la ' .. nombre)
    -- Antes de tocarlo, lo mira: hasta que sus ojos lo reconocen.
    leer(self, objeto)
    local puede, motivo = self:getPuedeCoger(objeto)
    if not puede then
        tarea(self, 'no puedo: ' .. motivo)
        pausa(2)
        self:setMirarA(nil)
        return
    end
    -- Ya parado y con el objeto delante: sube las manos pegadas al cuerpo
    -- por encima del mueble y desde ahí va al agarre.
    tarea(self, 'subiendo las manos')
    local listas = {}
    for _, m in ipairs(manos) do
        local y = (m.lado == 'izq' and 1 or -1) * (#manos == 1 and 0.27 or 0.235)
        listas[m.lado] = { 0.12, y, oz + 0.2, eje = { 0, 1, 0 }, relativo = true }
    end
    moverManos(self, manos, listas, 0.03, 0.9)
    -- Agarre: abre, se pone antes del punto, entra despacio y cierra.
    tarea(self, 'pinzas a los puntos de agarre')
    local puntos = {}
    for _, m in ipairs(manos) do
        puntos[m.lado] = m.punto
        self:setPinza(m.lado, Transporte.aperturaLibre)
    end
    local fx, fy = math.cos(rumbo), math.sin(rumbo)
    local antes, en = {}, {}
    for _, m in ipairs(manos) do
        local p = puntos[m.lado]
        antes[m.lado] = { p.x - fx * Transporte.antesDelAgarre, p.y - fy * Transporte.antesDelAgarre, p.z + 0.03, eje = p.eje }
        en[m.lado] = { p.x, p.y, p.z, eje = p.eje }
    end
    moverManos(self, manos, antes, 0.02, 0.84)
    pausaManos(0.4)
    moverManos(self, manos, en, 0.012, 0.28)
    pausaManos(0.4)
    tarea(self, 'cerrando las pinzas')
    for _, m in ipairs(manos) do
        self:setPinza(m.lado, puntos[m.lado].grosor)
    end
    esperar(function()
        for _, m in ipairs(manos) do
            if self:getPinza(m.lado) > puntos[m.lado].grosor + 0.001 then
                return false
            end
        end
        return true
    end, 4)
    pausaManos(0.5)
    self:setCoger(objeto)
    tarea(self, 'levantando la ' .. nombre)
    local arriba = {}
    for _, m in ipairs(manos) do
        local p = puntos[m.lado]
        local x, y, z = aRobot(self, p.x, p.y, p.z + Transporte.levantar)
        arriba[m.lado] = { x, y, z, eje = ejeARobot(self, p.eje), relativo = true }
    end
    moverManos(self, manos, arriba, 0.015, 0.35)
    pausaManos(0.5)
    self:setRetroceder(0.6)
    esperar(function()
        return self:getHaLlegado()
    end, 8)
    self:setMirarA(nil)
    -- Llevarlo: recogido delante del cuerpo.
    local h = mueble:getHueco(numero)
    local destino = puntosEn(objeto, h.x, h.y, h.z, h.rumbo)
    local function manosA(alto, adelante)
        local r = {}
        for _, m in ipairs(manos) do
            local local_ = m.punto['local']
            local y = local_[3] + (#manos == 1 and -lateral or 0)
            r[m.lado] = { adelante, y, alto + local_[4], eje = { 0, 1, 0 }, relativo = true }
        end
        return r
    end
    -- Como una persona con una caja: brazo colgando y antebrazo hacia
    -- delante (codos abajo, pegados al cuerpo). Las manos, delante del
    -- hombro lo que mide el antebrazo y un poco por debajo del codo.
    local hx, _, hz = aRobot(self, self:getPieza('hombroIzq'):getPosicion())
    local adelante = hx + Transporte.llevarDelante
    local llevar = {}
    for _, m in ipairs(manos) do
        local y = m.punto['local'][3] + (#manos == 1 and -lateral or 0)
        llevar[m.lado] = { adelante, y, hz - Transporte.llevarBajo, eje = { 0, 1, 0 }, relativo = true }
    end
    moverManos(self, manos, llevar, 0.03, 0.84)
    esperar(function()
        return self:getBrazosQuietos()
    end, 4)
    -- Con la vista puesta donde la va a dejar.
    self:setFoco(h.x, h.y, h.z + 0.05, mueble)
    local donde = mueble:getNombre()
    -- Con su artículo: el rack, el depósito; la mesa, la estantería.
    donde = ((donde:match('^rack') or donde:match('^depósito')) and 'al ' or 'a la ') .. donde
    irYAtracar(self, h.x, h.y, h.rumbo, lateral, 'llevo la ' .. nombre .. ' ' .. donde, function()
        tarea(self, 'subiendo la ' .. nombre .. ' a la altura de la balda')
        moverManos(self, manos, manosA(h.z + 0.06, adelante), 0.02, 0.7)
    end)
    -- Mira el hueco antes de dejarla: que lo vea libre.
    tarea(self, 'miro el hueco ' .. ((mueble:getNombre():match('^rack') or mueble:getNombre():match('^depósito')) and 'del ' or 'de la ') .. mueble:getNombre())
    self:setMirarA(h.x, h.y, h.z + 0.05)
    esperar(function()
        return self:getHaVisto(mueble, 0.3)
    end, 3)
    pausaManos(0.6)
    tarea(self, 'dejando la ' .. nombre)
    local sobre, abajo = {}, {}
    for _, m in ipairs(manos) do
        local p = destino[m.punto.nombre]
        sobre[m.lado] = { p[1], p[2], p[3] + 0.05, eje = p.eje }
        abajo[m.lado] = { p[1], p[2], p[3], eje = p.eje }
    end
    moverManos(self, manos, sobre, 0.02, 0.56)
    pausaManos(0.3)
    moverManos(self, manos, abajo, 0.012, 0.21)
    pausaManos(0.4)
    self:setDejar(mueble, numero)
    for _, m in ipairs(manos) do
        self:setPinza(m.lado, Transporte.aperturaLibre)
    end
    pausaManos(1.2)
    tarea(self, 'retirando las manos')
    local hx, hy = math.cos(h.rumbo), math.sin(h.rumbo)
    local fuera = {}
    for _, m in ipairs(manos) do
        local p = destino[m.punto.nombre]
        fuera[m.lado] = { p[1] - hx * 0.12, p[2] - hy * 0.12, p[3] + 0.02, eje = p.eje }
    end
    moverManos(self, manos, fuera, 0.02, 0.42)
    -- Recoge las manos por encima del mueble y las baja; luego se va.
    local recogidas = {}
    for _, m in ipairs(manos) do
        local y = (m.lado == 'izq' and 1 or -1) * (#manos == 1 and 0.27 or 0.235)
        recogidas[m.lado] = { 0.12, y, h.z + 0.2, eje = { 0, 1, 0 }, relativo = true }
    end
    moverManos(self, manos, recogidas, 0.03, 0.9)
    for _, lado in ipairs({ 'izq', 'der' }) do
        self:setPinza(lado, 0.05)
    end
    self:setMirarA(nil)
    self:setFoco(nil)
    brazosAbajo(self)
    self:setRetroceder(0.6)
    esperar(function()
        return self:getHaLlegado()
    end, 8)
    pausaManos(0.4)
end

--- Añade un encargo: coger `objeto` y dejarlo en el hueco `numero` de `mueble`.
function Robot:setLlevar(objeto, mueble, numero)
    local d = self.datos.transporte
    d.encargos[#d.encargos + 1] = { objeto = objeto, mueble = mueble, numero = numero }
end

function Robot:getEncargos()
    return self.datos.transporte.encargos
end

--- Lo que está haciendo, para leer.
function Robot:getTarea()
    local d = self.datos.transporte
    if not d then
        -- Sin transporte (el soldado que entrena): lo que diga su práctica.
        return self.datos.practicaSoldado and self.datos.practicaSoldado.tarea or ''
    end
    return d.tarea
end

function Robot:getHechos()
    return self.datos.transporte.hechos
end

--- `true` si está en medio de un encargo.
function Robot:getOcupado()
    return self.datos.transporte.hilo ~= nil
end

GestorRobots.registrarEspecializacion('transporte', Transporte)
return Transporte

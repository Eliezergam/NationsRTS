-- Trabajo del robot grande con las cajas de misil (plano aprobado por
-- El dueño el 2026-11-17). Hay dos carriles, uno por pasillo del polvorín,
-- cada uno con su mesa de encajado delante del portón y su sitio de cajas
-- vacías: con una caja de 9 m atravesada el robot solo puede girar dentro de
-- los pasillos (11,4 m) o en el muelle, así que cada carril trabaja por su
-- lado. Sin caja, el robot gira en cualquier sitio y cambia de carril por la
-- fábrica, pasando entre las mesas y el muro (x = -47,7).
--
-- El torso (con la cabeza) mira siempre hacia donde va el robot (cintura.lua):
-- la caja va por delante y las orugas van hacia delante o marcha atrás según
-- convenga. Para dar la vuelta con la caja, el torso la gira por encima de
-- todo (subida) donde hay sitio.
--
-- Para cada caja llena (la grúa ha metido el misil y la tapa está cerrada):
--   1. va a la mesa de su carril y la coge con las dos garras (las uñas
--      cierran de arriba abajo), atravesada; la sube y el torso la gira hacia
--      el pasillo;
--   2. va por el pasillo (orugas marcha atrás, el torso delante) hasta la
--      bahía del primer hueco libre de ese lado, se pone de cara al rack, la
--      sube a su nivel, se acerca y la deja: el contador del polvorín sube;
--   3. va a por una caja vacía (al fondo del pasillo norte; la del sur, en el
--      muelle, saliendo por el portón), gira con ella y la deja en la mesa; la
--      línea de montaje abre la tapa y la grúa ya puede meter el siguiente.
--
-- La escena le da el trabajo con Robot:setTrabajoEncajado (ver allí).

---@class Encajado : Robot
local Encajado = {}
local Robot = GestorRobots.Robot

Encajado.adelante = 2.3 -- m del centro del robot a la caja que coge (las orugas quedan a ~20 cm)
Encajado.levantarCarga = 1.6 -- alto de las garras al llevar una caja (su fondo, a 1,1 m: pasa por encima de la mesa)
Encajado.levantarGiro = 3.0 -- alto de las garras al girar la caja con el torso (su fondo, a 2,5 m: por encima de puestos y estanterías)
Encajado.holguraRack = 0.06 -- m por encima de los brazos del rack al meterla
Encajado.mesaX = -48.3 -- donde se pone el robot para coger o dejar en la mesa (la caja, hacia -x)
Encajado.pasoX = -47.7 -- calle entre las mesas y el muro, para cambiar de carril
Encajado.esperaX = -41.0 -- dentro del pasillo, lejos de la mesa (la grúa trabaja)

local LADOS = { 'izq', 'der' }

local function esperar(condicion)
    while not condicion() do
        coroutine.yield()
    end
end

local function tarea(self, texto)
    self.datos.encajado.tarea = texto
    if os.getenv('ENCAJADO_DEPURAR') then
        local lleva = self:getLlevandoGarras()
        local extra = ''
        if lleva then
            local x, y, z = lleva:getPosicion()
            extra = string.format(' · lleva caja en %.2f, %.2f, %.2f rumbo %.2f', x, y, z, lleva:getRumbo())
        end
        print(string.format('ENCAJADO %s (robot en %.2f, %.2f rumbo %.2f frente %.2f pierna %.2f)%s', texto, self.x, self.y, self.rumbo, self:getFrente(), self.datos.brazosPesado.pierna, extra))
    end
end

-- Movimientos (dentro de la corrutina) ---------------------------------------

local function irA(self, x, y, rumbo)
    self:setIrA(x, y, rumbo)
    esperar(function() return self:getHaLlegado() end)
end

local function irAtras(self, x, y, rumbo)
    self:setIrAtras(x, y, rumbo)
    esperar(function() return self:getHaLlegado() end)
end

local function girar(self, rumbo)
    self:setIrA(self.x, self.y, rumbo)
    esperar(function() return self:getHaLlegado() end)
end

--- El torso a `angulo` respecto a las orugas (y se queda); nil: libre.
local function torso(self, angulo)
    self:setCintura(angulo)
    if angulo then
        esperar(function() return self:getCinturaEn(angulo) end)
    end
end

local function garrasListas(self)
    esperar(function() return self:getGarraLista('izq') and self:getGarraLista('der') end)
end

-- Las dos garras a `adelante` m del torso y `alto` m del suelo.
local function garrasEnRobot(self, adelante, alto)
    for _, lado in ipairs(LADOS) do
        self:setAlcanzarEnRobot(lado, adelante, alto)
    end
    garrasListas(self)
    if os.getenv('ENCAJADO_DEPURAR') then
        local x, y, z = self:getPuntoGarra('izq')
        local x2, y2, z2 = self:getPuntoGarra('der')
        print(string.format('ENCAJADO garras pedidas a %.2f, %.2f; izq en %.2f, %.2f, %.2f; der en %.2f, %.2f, %.2f', adelante, alto, x, y, z, x2, y2, z2))
    end
end

--- Coge la caja con las dos garras: cada una a su punto de agarre (el del
-- mismo lado del robot), con las uñas de arriba abajo. El torso, al frente
-- de las orugas (los brazos van a puntos del almacén).
local function coger(self, caja)
    torso(self, 0)
    local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
    local puntos = {}
    for _, p in ipairs(caja:getPuntosAgarre()) do
        if p.mano == 'garra' then
            local lateral = -s * (p.x - self.x) + c * (p.y - self.y)
            puntos[lateral > 0 and 'izq' or 'der'] = p
        end
    end
    local z = puntos.izq.z
    for _, lado in ipairs(LADOS) do
        self:setGiroGarra(lado, puntos[lado].giroGarra or 0)
        self:setGarra(lado, 1)
    end
    -- Primero a su altura un poco antes; luego adelante hasta el punto.
    garrasEnRobot(self, Encajado.adelante - 0.6, z)
    for _, lado in ipairs(LADOS) do
        local p = puntos[lado]
        self:setAlcanzar(lado, p.x, p.y, p.z)
    end
    garrasListas(self)
    for _, lado in ipairs(LADOS) do
        self:setGarra(lado, 0)
    end
    garrasListas(self)
    for _, lado in ipairs(LADOS) do
        self:setCogerConGarra(lado, caja)
    end
    return z
end

--- Con la caja cogida: la sube por encima de todo, el torso la gira a
-- `angulo` (respecto a las orugas) y la baja a la altura de llevarla.
local function girarCaja(self, angulo)
    garrasEnRobot(self, Encajado.adelante, Encajado.levantarGiro)
    torso(self, angulo)
    garrasEnRobot(self, Encajado.adelante, Encajado.levantarCarga)
end

--- Baja lo que lleva a `alto` (garras), la suelta, la deja en (x, y, z,
-- rumbo) exactos y retira los brazos; el torso queda libre.
local function dejar(self, caja, alto, x, y, z, rumbo)
    garrasEnRobot(self, Encajado.adelante, alto)
    for _, lado in ipairs(LADOS) do
        self:setGarra(lado, 1)
    end
    garrasListas(self)
    for _, lado in ipairs(LADOS) do
        self:setSoltarDeGarra(lado)
    end
    caja:setPosicion(x, y, z, rumbo)
    garrasEnRobot(self, Encajado.adelante - 0.6, alto)
    for _, lado in ipairs(LADOS) do
        self:setAlcanzar(lado, nil)
        self:setGiroGarra(lado, 0)
    end
    torso(self, nil)
end

-- Los pasos del trabajo -------------------------------------------------------

--- Va (sin carga) delante de la mesa del carril, mirando a ella.
local function irAMesa(self, carril)
    local E = Encajado
    if self.x > -45.5 then
        -- En un pasillo del polvorín: sale por su portón.
        irA(self, E.pasoX, self.y)
    elseif math.abs(self.x - E.pasoX) > 0.2 then
        -- En la fábrica: por el pasillo entre las dos mesas.
        irA(self, E.pasoX, 0)
    end
    if math.abs(self.y - carril.pasillo) > 0.1 then
        irA(self, E.pasoX, carril.pasillo)
    end
    irA(self, E.mesaX, carril.pasillo, math.pi)
end

--- Lleva la caja (cogida, el torso mirando a -x hacia la mesa) al hueco `h`
-- y la deja.
local function guardarEnHueco(self, carril, caja, h)
    local E = Encajado
    local hx, hy, hz = h[1], h[2], h[3]
    -- La caja sube por encima de la mesa y los puestos y el torso la gira
    -- hacia el pasillo (las orugas siguen mirando a la mesa).
    tarea(self, 'giro la caja hacia el pasillo')
    girarCaja(self, math.pi)
    tarea(self, string.format('la llevo al hueco de %.1f, %.1f (nivel a %.1f m)', hx, hy, hz))
    irAtras(self, hx, carril.pasillo)
    -- De cara al rack (el torso, al revés que las orugas).
    local lado = hy > carril.pasillo and 1 or -1
    girar(self, lado * math.pi / 2 - math.pi)
    local alto = hz + caja:getPuntosAgarre()[1]['local'][4]
    garrasEnRobot(self, E.adelante, alto + E.holguraRack)
    tarea(self, 'subida al nivel del hueco')
    irAtras(self, hx, hy - lado * E.adelante)
    tarea(self, 'la dejo en el rack')
    dejar(self, caja, alto, hx, hy, hz, h[4])
    tarea(self, string.format('dejada: la caja está en %.2f, %.2f, %.2f', caja:getPosicion()))
    irA(self, hx, carril.pasillo)
end

--- Trae una caja vacía de su sitio y la deja en la mesa del carril.
local function traerVacia(self, carril, trabajo)
    local E = Encajado
    local v = carril.vacias
    if not carril.cajaVacia then
        trabajo.reponerVacia(carril)
    end
    local caja = carril.cajaVacia
    local yP = carril.pasillo
    tarea(self, 'voy a por una caja vacía')
    if v[2] > 0 then
        -- Al fondo del pasillo norte, mirando a +x; la gira hacia la fábrica
        -- y vuelve con las orugas marcha atrás.
        irA(self, v[1] - E.adelante, yP, 0)
        coger(self, caja)
        carril.cajaVacia = nil
        tarea(self, 'giro la caja vacía hacia la fábrica')
        girarCaja(self, math.pi)
    else
        -- En el muelle, al oeste del portón sur: sale, la coge mirando a -x,
        -- la gira hacia el portón, vuelve marcha atrás, se pone de cara al
        -- pasillo (gira entero con ella: hay sitio) y entra.
        local px, my = trabajo.muelle.portonX, trabajo.muelle.maniobraY
        irA(self, px, yP)
        irA(self, px, my)
        irA(self, v[1] + E.adelante, my, math.pi)
        coger(self, caja)
        carril.cajaVacia = nil
        tarea(self, 'giro la caja vacía hacia el portón')
        girarCaja(self, math.pi)
        irAtras(self, px, my)
        girar(self, -math.pi / 2)
        irAtras(self, px, yP)
        girar(self, 0)
    end
    tarea(self, 'llevo la caja vacía a la mesa')
    irAtras(self, E.mesaX, yP)
    local m = carril.mesa
    dejar(self, caja, m[3] + caja:getPuntosAgarre()[1]['local'][4], m[1], m[2], m[3], m[4])
    caja:setTapa(0)
    caja:setLleno(false)
    carril.caja = caja
    print(string.format('ROBOT GRANDE caja vacía en la mesa de %.0f', yP))
    irA(self, E.esperaX, yP)
end

local function cajaLista(carril)
    local c = carril.caja
    return c and c:getLleno() and c:getTapa() == 0 and not c.llevadoPor
end

local function trabajar(self, trabajo)
    while true do
        tarea(self, 'espero una caja llena en una mesa')
        local carril
        esperar(function()
            for _, c in ipairs(trabajo.carriles) do
                if cajaLista(c) then
                    carril = c
                    return true
                end
            end
            return false
        end)
        tarea(self, 'voy a la mesa de encajado')
        irAMesa(self, carril)
        local caja = carril.caja
        tarea(self, 'cojo la caja llena')
        coger(self, caja)
        carril.caja = nil
        garrasEnRobot(self, Encajado.adelante, Encajado.levantarCarga)
        local k, h = trabajo.huecoLibre(carril.pasillo)
        if not k then
            tarea(self, 'el polvorín de este lado está lleno')
            esperar(function() return false end)
        end
        guardarEnHueco(self, carril, caja, h)
        trabajo.guardar(k, caja)
        print(string.format('ROBOT GRANDE caja guardada en el hueco %d (%.1f, %.1f, %.1f)', k, h[1], h[2], h[3]))
        traerVacia(self, carril, trabajo)
    end
end

function Encajado:onLoad()
    self.datos.encajado.tarea = 'sin trabajo'
end

function Encajado:onUpdate()
    local d = self.datos.encajado
    if not d.trabajo then
        return
    end
    if not d.vuelta then
        d.vuelta = coroutine.create(function()
            trabajar(self, d.trabajo)
        end)
    end
    local bien, fallo = coroutine.resume(d.vuelta)
    if not bien then
        error(fallo)
    end
end

--- Le da el trabajo de las cajas de misil:
--   carriles: { { pasillo = y, mesa = { x, y, z, rumbo }, vacias = { ... },
--               caja = la caja de la mesa, cajaVacia = la que espera }, ... }
--   muelle = { portonX, maniobraY }
--   huecoLibre(pasillo) -> k, { x, y, z, rumbo } (el primero libre de ese lado)
--   guardar(k, caja): la caja ya está en el hueco k (sube el contador)
--   reponerVacia(carril): pone una vacía en su sitio (provisional: hasta que
--     las traigan los camiones)
function Robot:setTrabajoEncajado(trabajo)
    self.datos.encajado.trabajo = trabajo
end

--- Qué está haciendo, en palabras.
function Robot:getTareaEncajado()
    return self.datos.encajado.tarea
end

GestorRobots.registrarEspecializacion('encajado', Encajado)
return Encajado

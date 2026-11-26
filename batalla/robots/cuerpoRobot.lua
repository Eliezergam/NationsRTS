-- El cuerpo físico del robot soldado (el dueño, 18-nov: «para que aprenda a
-- moverse tiene que tener toda la física»), en Jolt (batalla/robots/fisica.lua).
--
-- Piezas rígidas con su masa, con las medidas del modelo
-- (assets/batalla/robots/*_piezas.lua): el cuerpo (pelvis, torso, cabeza y
-- brazos en una pieza; cadera a 0,95 m), dos muslos (de la cadera a la
-- rodilla, 0,183 m delante y 0,4 m abajo), dos espinillas (de la rodilla a la
-- rueda, bajo la cadera) y dos ruedas (radio 0,15 m, 7,5 cm hacia fuera).
-- Caderas y rodillas: bisagras en y con motor de posición (sostienen la
-- postura, ceden si el golpe es grande). Ruedas: bisagras con motor de
-- velocidad.
--
-- Equilibrio como Ascento (péndulo invertido sobre ruedas): si el cuerpo se
-- inclina hacia delante, las ruedas van más deprisa para ponerse debajo; para
-- acelerar se inclina primero hacia donde quiere ir. Las piezas son de una
-- capa propia del robot: no chocan entre sí, sí con todo lo demás.
--
--   local c = CuerpoRobot.nuevo(fisica, x, y, rumbo, capa)
--   c:controlar(dt, velocidad m/s, giro rad/s)  antes de cada paso de la física
--   c:estado()   -> inclinacion, velocidad, rumbo, caido (lo que se lee)

local Fisica = require('batalla.robots.fisica')

local CuerpoRobot = {}
CuerpoRobot.__index = CuerpoRobot

CuerpoRobot.cadera = 0.95
CuerpoRobot.mitadCaderas = 0.1
CuerpoRobot.rodilla = { 0.183303, -0.4 } -- respecto a la cadera (x, z)
CuerpoRobot.radioRueda = 0.15
CuerpoRobot.ruedaFuera = 0.075
CuerpoRobot.anchoRueda = 0.06
CuerpoRobot.hombroRueda = 0.01 -- m: canto redondeado del neumático
-- Ruedas con su motor dentro (como Ascento): 6 kg. Con 2,5 kg cargando
-- 26 kg cada una, el solucionador las dejaba hundirse 4 cm al correr.
CuerpoRobot.masas = { cuerpo = 30, cadera = 1.5, muslo = 4, espinilla = 3, rueda = 6, base = 1, brazo = 3, antebrazo = 3 }
-- Brazos (lanzamisiles_piezas.lua): hombro a 0,5 m sobre la cadera y 0,295 m
-- a cada lado; brazo hasta el codo (0,08 m delante, 0,34 m abajo); antebrazo
-- y garra hacia delante, 0,43 m.
CuerpoRobot.hombro = { 0.295, 0.5 }
CuerpoRobot.codo = { 0.08, -0.34 }
CuerpoRobot.antebrazo = 0.43
-- Muelle de los brazos (más blando: pesan poco y con el de las piernas
-- vibraban).
CuerpoRobot.muelleBrazo = { 600, 30 }
CuerpoRobot.parBrazo = 250
-- Motores: caderas y rodillas, muelle de rigidez fija (N·m/rad y N·m·s/rad;
-- uno por frecuencia salía blando porque las piernas pesan poco y la cadera
-- se hundía 17 cm) y N·m como mucho; ruedas (N·m como mucho).
CuerpoRobot.muelleArticulacion = { 4000, 200 }
CuerpoRobot.parArticulacion = 800
CuerpoRobot.parRueda = 60
-- Equilibrio: péndulo invertido de largo `pendulo` m (del eje de las ruedas
-- al centro de masas). La base acelera a = g·θ + L·(ω0²·(θ - θpedida) +
-- 2·ζ·ω0·θ'), que deja la inclinación como un muelle de `omega` rad/s con
-- amortiguación `zeta` (sin rebote con 1). Para ir a una velocidad se pide
-- una inclinación hacia allí (`kVelocidad` rad por m/s que le faltan).
CuerpoRobot.pendulo = 0.7
CuerpoRobot.omega = 9
CuerpoRobot.zeta = 1
CuerpoRobot.kVelocidad = 0.2
CuerpoRobot.kIntegral = 0.1 -- rad por m de retraso acumulado (llega a la velocidad pedida)
-- Lo que deja cambiar la velocidad pedida (m/s²). Sin rampa, frenar en seco
-- desde 4,6 m/s lo tumbaba: lo que tendrá que aprender (cerebro) es cuánto.
CuerpoRobot.aceleracion = 4
CuerpoRobot.integralMaxima = 1
CuerpoRobot.inclinacionMaxima = math.rad(12)
CuerpoRobot.caido = math.rad(50) -- más inclinado: se ha caído
CuerpoRobot.vueltas = { 30, 10 } -- del solucionador (velocidad, posición)

local J, ffi

local function quatYaw(q, rumbo)
    -- Giro en z de los robots = giro en Y de Jolt (mismo ángulo).
    q.x, q.y, q.z, q.w = 0, math.sin(rumbo / 2), 0, math.cos(rumbo / 2)
end

--- Forma convexa a partir de puntos (m, ejes de los robots, respecto al
-- origen de la pieza).
local function envolvente(puntos)
    local n = #puntos
    local arr = ffi.new('JPC_Vec3[?]', n)
    for k, p in ipairs(puntos) do
        arr[k - 1].x, arr[k - 1].y, arr[k - 1].z = p[1], p[3], -p[2]
    end
    local s = ffi.new('JPC_ConvexHullShapeSettings')
    J.JPC_ConvexHullShapeSettings_default(s)
    s.Points, s.PointsLen = arr, n
    s.MaxConvexRadius = 0.01
    return Fisica.crearForma(s, J.JPC_ConvexHullShapeSettings_Create)
end

--- Caja de puntos entre dos extremos con media sección `r`.
local function barra(a, b, r)
    local p = {}
    for _, e in ipairs({ a, b }) do
        for _, dx in ipairs({ -r, r }) do
            for _, dy in ipairs({ -r, r }) do
                p[#p + 1] = { e[1] + dx, e[2] + dy, e[3] }
            end
        end
    end
    return p
end

--- Cilindro redondo de Jolt (las ruedas: uno de puntos daba golpecitos al
-- rodar y lo bamboleaba de lado hasta tumbarlo).
local function cilindro(radio, ancho)
    local s = ffi.new('JPC_CylinderShapeSettings')
    J.JPC_CylinderShapeSettings_default(s)
    s.HalfHeight, s.Radius, s.ConvexRadius = ancho / 2, radio, CuerpoRobot.hombroRueda
    return Fisica.crearForma(s, J.JPC_CylinderShapeSettings_Create)
end

local function disco(radio, ancho)
    local p = {}
    for k = 0, 23 do
        local a = k / 24 * 2 * math.pi
        for _, y in ipairs({ -ancho / 2, ancho / 2 }) do
            p[#p + 1] = { math.cos(a) * radio, y, math.sin(a) * radio }
        end
    end
    return p
end

function CuerpoRobot.nuevo(fisica, x, y, rumbo, capa)
    J, ffi = Fisica.jolt()
    local self = setmetatable({}, CuerpoRobot)
    self.fisica = fisica
    self.capa = capa or 2
    self.rumbo0 = rumbo
    local c, s = math.cos(rumbo), math.sin(rumbo)
    -- Del robot (x delante, y izquierda) al mundo.
    local function mundo(lx, ly, lz)
        return x + c * lx - s * ly, y + s * lx + c * ly, lz
    end
    self.mundo = mundo
    -- Sobre el terreno (con un poco de holgura: cae y se asienta).
    local suelo = 0
    if not fisica.plano then
        local Mundo = require('batalla.robots.mundo')
        for _, s in ipairs({ -1, 1 }) do
            local wx, wy = mundo(0, s * (CuerpoRobot.mitadCaderas + CuerpoRobot.ruedaFuera), 0)
            suelo = math.max(suelo == 0 and -math.huge or suelo, Mundo.altura(wx, wy))
        end
        suelo = suelo + 0.03
    end
    self.suelo0 = suelo
    local H, R, rod = CuerpoRobot.cadera, CuerpoRobot.radioRueda, CuerpoRobot.rodilla
    local function pieza(nombre, lx, ly, lz, forma, masa, rueda)
        local bs = ffi.new('JPC_BodyCreationSettings')
        J.JPC_BodyCreationSettings_default(bs)
        local wx, wy, wz = mundo(lx, ly, lz)
        bs.Position.x, bs.Position.y, bs.Position.z = fisica:aJolt(wx, wy, wz + suelo)
        quatYaw(bs.Rotation, rumbo)
        if rueda then
            -- El cilindro de Jolt va en su Y (arriba): tumbado 90° en su X
            -- para que su eje sea la y del robot (Z de Jolt).
            local q = bs.Rotation
            local h = math.sqrt(0.5)
            -- q · (giro de 90° en X) = (w·h, ...): producto de cuaterniones.
            local x, y, z, w = q.x, q.y, q.z, q.w
            q.x, q.y, q.z, q.w = (w * h + x * h), (y * h + z * h), (z * h - y * h), (w * h - x * h)
        end
        bs.MotionType = J.JPC_MOTION_TYPE_DYNAMIC
        bs.ObjectLayer = self.capa
        bs.Shape = forma
        bs.Friction = nombre:match('^rueda') and 1.2 or 0.5
        bs.AllowSleeping = false
        bs.AllowDynamicOrKinematic = true
        -- Jolt limita el giro a 47 rad/s por defecto: las ruedas no pasaban
        -- de 7 m/s y el robot se inclinaba para nada. Sin amortiguación
        -- inventada: el roce, del suelo.
        bs.MaxAngularVelocity = 400
        bs.LinearDamping, bs.AngularDamping = 0, 0
        -- Más vueltas del solucionador: con las piezas ligeras colgando del
        -- cuerpo pesado, las bisagras cedían (1-2°) y lo tumbaban de lado.
        bs.NumVelocityStepsOverride = CuerpoRobot.vueltas[1]
        bs.NumPositionStepsOverride = CuerpoRobot.vueltas[2]
        bs.MotionQuality = J.JPC_MOTION_QUALITY_LINEAR_CAST
        bs.OverrideMassProperties = J.JPC_OVERRIDE_MASS_PROPS_CALC_INERTIA
        bs.MassPropertiesOverride.Mass = masa
        -- La cadera es una pieza diminuta entre dos muelles muy duros: con su
        -- inercia de verdad, el solucionador la hacía saltar.
        if nombre:match('^cadera') or nombre:match('^base') then
            bs.InertiaMultiplier = CuerpoRobot.inerciaCadera
        end
        bs.ApplyGyroscopicForce = rueda or false
        local id, cuerpo = Fisica.anadir(fisica, bs, true)
        return { id = id, cuerpo = cuerpo, nombre = nombre }
    end
    local m = CuerpoRobot.masas
    self.piezas = {}
    -- El cuerpo: de la pelvis a la cabeza, con el cargador a la espalda.
    self.piezas.cuerpo = pieza('cuerpo', 0, 0, H, envolvente({
        { -0.32, -0.2, -0.05 }, { 0.15, -0.2, -0.05 }, { -0.32, 0.2, -0.05 }, { 0.15, 0.2, -0.05 },
        { -0.32, -0.22, 0.55 }, { 0.15, -0.22, 0.55 }, { -0.32, 0.22, 0.55 }, { 0.15, 0.22, 0.55 },
        { -0.1, -0.1, 0.72 }, { 0.12, -0.1, 0.72 }, { -0.1, 0.1, 0.72 }, { 0.12, 0.1, 0.72 },
    }), m.cuerpo)
    self.lados = {}
    for _, lado in ipairs({ { 'Der', -1 }, { 'Izq', 1 } }) do
        local S, sg = lado[1], lado[2]
        local yc = sg * CuerpoRobot.mitadCaderas
        -- La cadera tiene dos ejes, como la animación (piernasSoldado.lua):
        -- abrir la pierna hacia fuera (x) y adelantarla o doblarla (y). Una
        -- pieza pequeña entre los dos.
        local cadera = pieza('cadera' .. S, 0, yc, H, envolvente(barra({ 0, 0, 0.03 }, { 0, 0, -0.03 }, 0.04)), m.cadera)
        local muslo = pieza('muslo' .. S, 0, yc, H, envolvente(barra({ 0, 0, 0 }, { rod[1], 0, rod[2] }, 0.045)), m.muslo)
        local espinilla = pieza('espinilla' .. S, rod[1], yc, H + rod[2], envolvente(barra({ 0, 0, 0 }, { -rod[1], 0, rod[2] }, 0.04)), m.espinilla)
        local rueda = pieza('rueda' .. S, 0, yc + sg * CuerpoRobot.ruedaFuera, R, cilindro(R, CuerpoRobot.anchoRueda), m.rueda, true)
        self.piezas['cadera' .. S], self.piezas['muslo' .. S], self.piezas['espinilla' .. S], self.piezas['rueda' .. S] = cadera, muslo, espinilla, rueda
        self.lados[S] = {
            abrir = self:bisagra(self.piezas.cuerpo, cadera, 0, yc, H, 'posicion', 'x'),
            cadera = self:bisagra(cadera, muslo, 0, yc, H, 'posicion'),
            rodilla = self:bisagra(muslo, espinilla, rod[1], yc, H + rod[2], 'posicion'),
            rueda = self:bisagra(espinilla, rueda, 0, yc + sg * CuerpoRobot.ruedaFuera, R, 'velocidad'),
            signo = sg,
        }
    end
    -- Brazos: hombro con dos ejes (abrir, x; adelante y atrás, y, con una
    -- pieza pequeña entre los dos) y codo (y).
    self.brazosFisicos = {}
    local hb, cd = CuerpoRobot.hombro, CuerpoRobot.codo
    for _, lado in ipairs({ { 'Der', -1 }, { 'Izq', 1 } }) do
        local S, sg = lado[1], lado[2]
        local yh, zh = sg * hb[1], H + hb[2]
        local base = pieza('base' .. S, 0, yh, zh, envolvente(barra({ 0, 0, 0.03 }, { 0, 0, -0.03 }, 0.04)), m.base)
        local brazo = pieza('brazo' .. S, 0, yh, zh, envolvente(barra({ 0, 0, 0 }, { cd[1], 0, cd[2] }, 0.05)), m.brazo)
        local antebrazo = pieza('antebrazo' .. S, cd[1], yh, zh + cd[2], envolvente(barra({ 0, 0, 0 }, { CuerpoRobot.antebrazo, 0, 0 }, 0.05)), m.antebrazo)
        self.piezas['base' .. S], self.piezas['brazo' .. S], self.piezas['antebrazo' .. S] = base, brazo, antebrazo
        local muelle = CuerpoRobot.muelleBrazo
        self.brazosFisicos[S] = {
            abrir = self:bisagra(self.piezas.cuerpo, base, 0, yh, zh, 'posicion', 'x', muelle),
            hombro = self:bisagra(base, brazo, 0, yh, zh, 'posicion', nil, muelle),
            codo = self:bisagra(brazo, antebrazo, cd[1], yh, zh + cd[2], 'posicion', nil, muelle),
            signo = sg,
        }
    end
    self.matrices = {}
    self.inclinacion, self.giroInclinacion, self.velocidad = 0, 0, 0
    self.caido = false
    return self
end

--- Bisagra en y del robot (o en x, `eje` = 'x') entre dos piezas, en
-- (lx, ly, lz) del robot.
function CuerpoRobot:bisagra(a, b, lx, ly, lz, motor, eje, muelle)
    local fisica = self.fisica
    local s = ffi.new('JPC_HingeConstraintSettings')
    J.JPC_HingeConstraintSettings_default(s)
    s.ConstraintSettings.NumVelocityStepsOverride = CuerpoRobot.vueltas[1]
    s.ConstraintSettings.NumPositionStepsOverride = CuerpoRobot.vueltas[2]
    s.Space = J.JPC_CONSTRAINT_SPACE_WORLD_SPACE
    local wx, wy, wz = self.mundo(lx, ly, lz)
    local X, Y, Z = fisica:aJolt(wx, wy, wz + self.suelo0)
    s.Point1.x, s.Point1.y, s.Point1.z = X, Y, Z
    s.Point2.x, s.Point2.y, s.Point2.z = X, Y, Z
    -- Eje: y del robot (en Jolt, -Z girado); normal: x del robot.
    local c, sn = math.cos(self.rumbo0), math.sin(self.rumbo0)
    local hx, hy = -sn, c -- y del robot en el mundo
    local nx, ny = c, sn -- x del robot en el mundo
    s.HingeAxis1.x, s.HingeAxis1.y, s.HingeAxis1.z = hx, 0, -hy
    s.HingeAxis2.x, s.HingeAxis2.y, s.HingeAxis2.z = hx, 0, -hy
    s.NormalAxis1.x, s.NormalAxis1.y, s.NormalAxis1.z = nx, 0, -ny
    s.NormalAxis2.x, s.NormalAxis2.y, s.NormalAxis2.z = nx, 0, -ny
    if eje == 'x' then
        -- Eje: x del robot; normal: z (Y de Jolt).
        s.HingeAxis1.x, s.HingeAxis1.y, s.HingeAxis1.z = nx, 0, -ny
        s.HingeAxis2.x, s.HingeAxis2.y, s.HingeAxis2.z = nx, 0, -ny
        s.NormalAxis1.x, s.NormalAxis1.y, s.NormalAxis1.z = 0, 1, 0
        s.NormalAxis2.x, s.NormalAxis2.y, s.NormalAxis2.z = 0, 1, 0
    end
    if motor == 'posicion' then
        s.MotorSettings.SpringSettings.Mode = J.JPC_SPRING_MODE_STIFFNESS_AND_DAMPING
        local mu = muelle or CuerpoRobot.muelleArticulacion
        local par = muelle and CuerpoRobot.parBrazo or CuerpoRobot.parArticulacion
        s.MotorSettings.SpringSettings.FrequencyOrStiffness = mu[1]
        s.MotorSettings.SpringSettings.Damping = mu[2]
        s.MotorSettings.MinTorqueLimit, s.MotorSettings.MaxTorqueLimit = -par, par
    else
        s.MotorSettings.MinTorqueLimit, s.MotorSettings.MaxTorqueLimit = -CuerpoRobot.parRueda, CuerpoRobot.parRueda
    end
    local h = J.JPC_HingeConstraintSettings_Create(s, a.cuerpo, b.cuerpo)
    J.JPC_PhysicsSystem_AddConstraint(fisica.sistema, ffi.cast('JPC_Constraint*', h))
    if motor == 'posicion' then
        J.JPC_HingeConstraint_SetMotorState(h, J.JPC_MOTOR_STATE_POSITION)
        J.JPC_HingeConstraint_SetTargetAngle(h, 0)
    end
    -- Ruedas: con motor de velocidad (modo 'velocidad') o libres, con el
    -- par que pone controlar() (modo 'par').
    if motor == 'velocidad' and CuerpoRobot.modoRueda == 'velocidad' then
        J.JPC_HingeConstraint_SetMotorState(h, J.JPC_MOTOR_STATE_VELOCITY)
    end
    return h
end

--- Lee el cuerpo: inclinación hacia delante (rad), cómo cambia (rad/s),
-- velocidad hacia delante (m/s) y rumbo.
function CuerpoRobot:leer()
    local fisica = self.fisica
    local m = fisica:matriz(self.piezas.cuerpo.id, self.matrices.cuerpo)
    self.matrices.cuerpo = m
    local rumbo = math.atan2(m[5], m[1])
    local hx, hy = math.cos(rumbo), math.sin(rumbo)
    local inclinacion = math.atan2(m[3] * hx + m[7] * hy, m[11])
    local lateral = math.atan2(m[3] * -hy + m[7] * hx, m[11])
    -- Inclinación de verdad: la del centro de masas de todo el robot sobre el
    -- eje de las ruedas (con el cargador a la espalda, el cuerpo derecho no
    -- está en equilibrio).
    local mx, my, mz, mt = 0, 0, 0, 0
    local ex, ey, ez = 0, 0, 0
    for nombre, p in pairs(self.piezas) do
        local q = J.JPC_BodyInterface_GetCenterOfMassPosition(fisica.cuerpos, p.id)
        local x, y, z = fisica:deJolt(q.x, q.y, q.z)
        local masa = CuerpoRobot.masas[nombre:match('^%l+')]
        mx, my, mz, mt = mx + x * masa, my + y * masa, mz + z * masa, mt + masa
        if nombre:match('^rueda') then
            ex, ey, ez = ex + x / 2, ey + y / 2, ez + z / 2
        end
    end
    mx, my, mz = mx / mt, my / mt, mz / mt
    local adelante = (mx - ex) * hx + (my - ey) * hy
    inclinacion = math.atan2(adelante, mz - ez)
    self.alturaMasas = mz - ez
    local w = J.JPC_BodyInterface_GetAngularVelocity(fisica.cuerpos, self.piezas.cuerpo.id)
    -- De Jolt a los robots: (X, Y, Z) -> (X, -Z, Y).
    local wx, wy, wz = w.x, -w.z, w.y
    -- Lo rápido que cambia esa inclinación (filtrada un poco).
    local giroInclinacion = wx * -hy + wy * hx
    if self.inclinacionAntes and CuerpoRobot.derivarInclinacion then
        local d = (inclinacion - self.inclinacionAntes) / Fisica.paso
        giroInclinacion = (self.giroInclinacion or d) * 0.5 + d * 0.5
    end
    self.inclinacionAntes = inclinacion
    local v = 0
    for _, S in ipairs({ 'Der', 'Izq' }) do
        local vr = J.JPC_BodyInterface_GetLinearVelocity(fisica.cuerpos, self.piezas['rueda' .. S].id)
        v = v + (vr.x * hx + -vr.z * hy) / 2
    end
    self.rumbo, self.inclinacion, self.lateral, self.giroInclinacion, self.velocidad, self.giroRumbo = rumbo, inclinacion, lateral, giroInclinacion, v, wz
    self.caido = math.abs(inclinacion) > CuerpoRobot.caido or math.abs(lateral) > CuerpoRobot.caido
    return self
end

--- Antes de cada paso: equilibrio y marcha hacia `velocidad` m/s girando
-- `giro` rad/s.
function CuerpoRobot:controlar(velocidad, giro, dt)
    dt = dt or Fisica.paso
    self:leer()
    local C = CuerpoRobot
    local paso = (C.aceleracion or math.huge) * dt
    local vp = self.vPedida or 0
    vp = vp + math.max(-paso, math.min(paso, velocidad - vp))
    self.vPedida = vp
    local falta = vp - self.velocidad
    self.integral = math.max(-C.integralMaxima, math.min(C.integralMaxima, (self.integral or 0) + falta * dt))
    local quiere = math.max(-C.inclinacionMaxima, math.min(C.inclinacionMaxima, C.kVelocidad * falta + C.kIntegral * self.integral))
    local a = 9.81 * self.inclinacion + C.pendulo * (C.omega ^ 2 * (self.inclinacion - quiere) + 2 * C.zeta * C.omega * self.giroInclinacion)
    if self.caido then
        a = 0
    end
    self.aPedida = a
    -- El giro también entra poco a poco (le da tiempo a inclinarse).
    local gp = self.giroPedido or 0
    local tope = C.aceleracionGiro * dt
    gp = gp + math.max(-tope, math.min(tope, (giro or 0) - gp))
    self.giroPedido = gp
    giro = gp
    local giroPedido = gp
    -- Rumbo que mantener.
    self.rumboPedido = (self.rumboPedido or self.rumbo) + (giro or 0) * dt
    local perdido = (self.rumboPedido - self.rumbo + math.pi) % (2 * math.pi) - math.pi
    giro = (giro or 0) + C.kRumbo * perdido
    local errorGiro = giro - (self.giroRumbo or 0)
    -- Piernas: flexión de cada una (cadera -f, rodilla 2f: la rueda sigue
    -- bajo la cadera); la del lado que cae se estira.
    local giroLado = self.lateralAntes and (self.lateral - self.lateralAntes) / dt or 0
    self.lateralAntes = self.lateral
    -- En las curvas se inclina hacia dentro, como una moto: atan(v·ω/g).
    -- (Con el giro pedido, no el medido: el medido tiembla y las piernas
    -- se volvían locas.)
    local ladeoPedido = math.atan(self.velocidad * giroPedido / 9.81)
    ladeoPedido = math.max(-C.ladeoMaximo, math.min(C.ladeoMaximo, ladeoPedido))
    self.ladeoPedido = ladeoPedido
    -- Lo que pide la animación de las piernas (piernasSoldado.lua, por
    -- cuerpoFisico.lua): por lado { doblar, adelante, abrir } en rad. Sin
    -- ella, de pie con `flexion`.
    local anim = self.forzarPiernas or self.piernas or {}
    local lado = self.forzarPiernas and 0 or 1
    for S, l in pairs(self.lados) do
        local p = anim[S] or {}
        local f = (p.doblar or C.flexion) - lado * C.signoLado * l.signo * (C.kLado * (self.lateral - ladeoPedido) + C.kGiroLado * giroLado)
        f = math.max(0.02, math.min(0.9, f))
        -- Sin tirones: al encoger de golpe, la rueda se despegaba del suelo.
        local antes = l.flexion or f
        local tope = C.velocidadFlexion * dt
        f = antes + math.max(-tope, math.min(tope, f - antes))
        l.flexion = f
        J.JPC_HingeConstraint_SetTargetAngle(l.cadera, -f - (p.adelante or 0))
        J.JPC_HingeConstraint_SetTargetAngle(l.rodilla, 2 * f)
        J.JPC_HingeConstraint_SetTargetAngle(l.abrir, p.abrir or 0)
    end
    -- Brazos: lo que pida quien lo maneje (cuerpoFisico.lua: protegerse al
    -- caer, empujar para levantarse); si no, colgando.
    local brazos = self.brazos or {}
    for S, b in pairs(self.brazosFisicos) do
        local o = brazos[S] or {}
        J.JPC_HingeConstraint_SetTargetAngle(b.abrir, o.abrir or 0)
        J.JPC_HingeConstraint_SetTargetAngle(b.hombro, o.hombro or 0)
        J.JPC_HingeConstraint_SetTargetAngle(b.codo, o.codo or 0)
    end
    if C.modoRueda == 'velocidad' then
        -- La rueda va a la velocidad de ahora más lo que debe acelerar en
        -- este paso; su motor (fuerte) la lleva ahí.
        self.uRueda = (self.uRueda or self.velocidad) + a * dt
        self.uRueda = self.uRueda + (self.velocidad - self.uRueda) * C.seguirMedida
        if self.caido then
            self.uRueda = 0
        end
        for _, l in pairs(self.lados) do
            local ul = self.uRueda - l.signo * ((giro or 0) + C.kGiroV * errorGiro) * (C.mitadCaderas + C.ruedaFuera)
            J.JPC_HingeConstraint_SetTargetAngularVelocity(l.rueda, C.signoRueda * ul / C.radioRueda)
        end
        return
    end
    -- Par de cada rueda (como un Segway: la rueda gira libre y el motor la
    -- empuja contra la espinilla): la fuerza para esa aceleración, repartida,
    -- más la diferencia para girar.
    local masa = C.masas.cuerpo + 2 * (C.masas.muslo + C.masas.espinilla + C.masas.rueda)
    local tau = masa * a / 2 * C.radioRueda
    local lx, ly = -math.sin(self.rumbo), math.cos(self.rumbo) -- y del robot en el mundo
    local v = self.vecTorque or ffi.new('JPC_Vec3')
    self.vecTorque = v
    for S, l in pairs(self.lados) do
        local t = tau - l.signo * C.kGiro * errorGiro
        t = math.max(-C.parRueda, math.min(C.parRueda, t))
        self.par = self.par or {}
        self.par[S] = t
        local k = C.signoRueda * t
        v.x, v.y, v.z = lx * k, 0, -ly * k
        J.JPC_BodyInterface_AddTorque(self.fisica.cuerpos, self.piezas['rueda' .. S].id, v)
        v.x, v.y, v.z = -lx * k, 0, ly * k
        J.JPC_BodyInterface_AddTorque(self.fisica.cuerpos, self.piezas['espinilla' .. S].id, v)
    end
end
CuerpoRobot.signoRueda = 1
CuerpoRobot.kGiro = 3 -- N·m por rad/s de giro que falta (más, lo mece de lado)
CuerpoRobot.modoRueda = 'velocidad'
-- Rumbo: mantiene el que lleva (más lo que se le pide girar), no solo el giro.
CuerpoRobot.kRumbo = 2 -- rad/s por rad de rumbo perdido
-- De lado (como Ascento): estira la pierna del lado que cae y encoge la otra
-- (rad de flexión por rad de ladeo y por rad/s).
CuerpoRobot.inerciaCadera = 30
CuerpoRobot.flexion = 0.08 -- rad: flexión de pie (rodilla un poco doblada)
CuerpoRobot.velocidadFlexion = 1.5 -- rad/s como mucho
CuerpoRobot.aceleracionGiro = 0.5 -- rad/s²
CuerpoRobot.kLado = 0.3
CuerpoRobot.kGiroLado = 0.1
CuerpoRobot.signoLado = 1
CuerpoRobot.ladeoMaximo = math.rad(25)
CuerpoRobot.kGiroV = 3 -- rad/s de más por rad/s de giro que falta (sin esto culebreaba: ladeo → giro → ladeo, y se tumbaba a 5 m/s)
CuerpoRobot.seguirMedida = 0.05 -- lo que la velocidad pedida a la rueda se acerca a la medida en cada paso

--- Ayuda para levantarse (como Human Fall Flat: una fuerza que el jugador no
-- ve, para que nunca se quede atascado): gira el cuerpo para llevar su eje
-- `eje` (1 delante, 3 arriba) hacia `hacia` (vector del mundo) con como mucho
-- `parMaximo` N·m, y lo sube con `levantar` veces su peso.
function CuerpoRobot:ayudar(eje, hacia, parMaximo, levantar)
    local m = self:matriz('cuerpo')
    local ax, ay, az = m[eje], m[eje + 4], m[eje + 8]
    local hx, hy, hz = hacia[1], hacia[2], hacia[3]
    -- Eje de giro: a × h; ángulo entre los dos.
    local cx, cy, cz = ay * hz - az * hy, az * hx - ax * hz, ax * hy - ay * hx
    local s = math.sqrt(cx * cx + cy * cy + cz * cz)
    local angulo = math.atan2(s, ax * hx + ay * hy + az * hz)
    local w = J.JPC_BodyInterface_GetAngularVelocity(self.fisica.cuerpos, self.piezas.cuerpo.id)
    local wx, wy, wz = w.x, -w.z, w.y
    local k, d = CuerpoRobot.ayudaMuelle[1], CuerpoRobot.ayudaMuelle[2]
    local tx, ty, tz = -d * wx, -d * wy, -d * wz
    if s > 1e-4 then
        tx, ty, tz = tx + k * angulo * cx / s, ty + k * angulo * cy / s, tz + k * angulo * cz / s
    end
    local t = math.sqrt(tx * tx + ty * ty + tz * tz)
    if t > parMaximo then
        tx, ty, tz = tx * parMaximo / t, ty * parMaximo / t, tz * parMaximo / t
    end
    local v = self.vecAyuda or ffi.new('JPC_Vec3')
    self.vecAyuda = v
    v.x, v.y, v.z = tx, tz, -ty
    J.JPC_BodyInterface_AddTorque(self.fisica.cuerpos, self.piezas.cuerpo.id, v)
    if levantar and levantar > 0 then
        local masa = 0
        for n in pairs(self.piezas) do
            masa = masa + CuerpoRobot.masas[n:match('^%l+')]
        end
        v.x, v.y, v.z = 0, masa * 9.81 * levantar, 0
        J.JPC_BodyInterface_AddForce(self.fisica.cuerpos, self.piezas.cuerpo.id, v)
    end
    return angulo
end
CuerpoRobot.ayudaMuelle = { 400, 80 } -- N·m por rad y por rad/s

--- Cinemático (`true`: lo mueve la animación con moverA y empuja lo que
-- toca, pero nada lo para) o dinámico (la física de verdad).
function CuerpoRobot:setCinematico(si)
    local tipo = si and J.JPC_MOTION_TYPE_KINEMATIC or J.JPC_MOTION_TYPE_DYNAMIC
    for _, p in pairs(self.piezas) do
        J.JPC_BodyInterface_SetMotionType(self.fisica.cuerpos, p.id, tipo, J.JPC_ACTIVATION_ACTIVATE)
    end
    self.cinematico = si
    if not si then
        -- El control empieza de cero desde como va ahora.
        self:leer()
        self.vPedida, self.integral, self.rumboPedido, self.uRueda, self.giroPedido = self.velocidad, 0, nil, nil, 0
        self.inclinacionAntes, self.lateralAntes = nil, nil
        for _, l in pairs(self.lados) do
            l.flexion = nil
        end
    end
end

--- Lleva la pieza `nombre` (cinemática) a la matriz `m` (de los robots) en
-- `dt` s.
function CuerpoRobot:moverA(nombre, m, dt)
    local p = self.piezas[nombre]
    local pos = self.posJolt or ffi.new('JPC_RVec3')
    local q = self.quatJolt or ffi.new('JPC_Quat')
    self.posJolt, self.quatJolt = pos, q
    pos.x, pos.y, pos.z = self.fisica:aJolt(m[4], m[8], m[12])
    -- Ejes en Jolt: X = x del robot, Y = z, Z = -y; (vx, vy, vz) -> (vx, vz, -vy).
    local r11, r12, r13 = m[1], m[3], -m[2]
    local r21, r22, r23 = m[9], m[11], -m[10]
    local r31, r32, r33 = -m[5], -m[7], m[6]
    local traza = r11 + r22 + r33
    if traza > 0 then
        local s = math.sqrt(traza + 1) * 2
        q.w, q.x, q.y, q.z = s / 4, (r32 - r23) / s, (r13 - r31) / s, (r21 - r12) / s
    elseif r11 > r22 and r11 > r33 then
        local s = math.sqrt(1 + r11 - r22 - r33) * 2
        q.w, q.x, q.y, q.z = (r32 - r23) / s, s / 4, (r12 + r21) / s, (r13 + r31) / s
    elseif r22 > r33 then
        local s = math.sqrt(1 + r22 - r11 - r33) * 2
        q.w, q.x, q.y, q.z = (r13 - r31) / s, (r12 + r21) / s, s / 4, (r23 + r32) / s
    else
        local s = math.sqrt(1 + r33 - r11 - r22) * 2
        q.w, q.x, q.y, q.z = (r21 - r12) / s, (r13 + r31) / s, (r23 + r32) / s, s / 4
    end
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    q.w, q.x, q.y, q.z = q.w / n, q.x / n, q.y / n, q.z / n
    J.JPC_BodyInterface_MoveKinematic(self.fisica.cuerpos, p.id, pos, q, dt)
end

-- Reflejos (físico tras un golpe) -------------------------------------------
-- Como el «brace for fall» de Euphoria (NaturalMotion): al irse al suelo
-- estira los brazos hacia donde cae; en el suelo, se levanta por fases:
--   suelo     espera a que pare de rodar
--   girar     se pone boca abajo (brazos recogidos, piernas encogidas)
--   empujar   brazos estirados contra el suelo, piernas debajo; el cuerpo
--             sube hasta casi derecho
--   subir     piernas a su sitio, brazos abajo; el equilibrio de las ruedas
--             lo termina de enderezar
-- con la ayuda invisible de ayudar() para que nunca se quede atascado.
-- self.fase: 'equilibrio' (de pie) o una de esas.

CuerpoRobot.reflejo = {
    protegerDesde = math.rad(18), -- inclinación desde la que pone los brazos
    esperaSuelo = 0.8, -- s quieto en el suelo antes de levantarse
    bocaAbajo = -0.7, -- eje delante hacia abajo (z del mundo) para empujar
    casiDerecho = 0.8, -- eje arriba (z) para pasar a subir
    derecho = math.rad(8),
    atascado = 10, -- s en una fase: vuelve a empezar
}

local function fase(self, nombre)
    if self.fase ~= nombre then
        self.fase, self.relojFase = nombre, 0
        if CuerpoRobot.alCambiarFase then
            CuerpoRobot.alCambiarFase(self, nombre)
        end
    end
end

--- Un paso con reflejos: equilibrio (frenando hasta parar) o levantarse.
function CuerpoRobot:reflejos(dt)
    local R = CuerpoRobot.reflejo
    self.fase = self.fase or 'equilibrio'
    self.relojFase = (self.relojFase or 0) + dt
    local m = self:matriz('cuerpo')
    self.forzarPiernas, self.brazos = nil, nil
    if self.fase == 'equilibrio' then
        self:controlar(0, 0, dt)
        -- Se va al suelo: brazos hacia donde cae (delante: hombro adelante y
        -- codo estirado; de lado: abre el brazo de ese lado).
        local i, l = self.inclinacion, self.lateral
        if math.max(math.abs(i), math.abs(l)) > R.protegerDesde then
            local b = {}
            for S, br in pairs(self.brazosFisicos) do
                local o = { hombro = 0, codo = 0.4, abrir = 0 }
                if math.abs(i) >= math.abs(l) then
                    o.hombro = i > 0 and -1.4 or 0.9
                    o.codo = i > 0 and 1.3 or 0.4
                elseif l * br.signo > 0 then
                    o.abrir = br.signo * 1.3
                    o.codo = 1.2
                end
                b[S] = o
            end
            self.brazos = b
        end
        if self.caido then
            fase(self, 'suelo')
        end
        return
    end
    -- En el suelo: ruedas quietas (controlar con caído) y piernas encogidas.
    local encoger = { Der = { doblar = 0.8 }, Izq = { doblar = 0.8 } }
    if self.fase == 'suelo' then
        self.forzarPiernas = encoger
        self:controlar(0, 0, dt)
        local w = J.JPC_BodyInterface_GetAngularVelocity(self.fisica.cuerpos, self.piezas.cuerpo.id)
        if self.relojFase > R.esperaSuelo and math.abs(self.velocidad) < 0.5 and (w.x * w.x + w.y * w.y + w.z * w.z) < 1 then
            fase(self, m[9] < R.bocaAbajo and 'empujar' or 'girar')
        end
    elseif self.fase == 'girar' then
        self.forzarPiernas = encoger
        self.brazos = { Der = { hombro = -0.6, codo = 1.5 }, Izq = { hombro = -0.6, codo = 1.5 } }
        self:controlar(0, 0, dt)
        self:ayudar(1, { 0, 0, -1 }, 220, 0.15)
        if m[9] < R.bocaAbajo then
            fase(self, 'empujar')
        end
    elseif self.fase == 'empujar' then
        self.forzarPiernas = { Der = { doblar = 0.9, adelante = 0.5 }, Izq = { doblar = 0.9, adelante = 0.5 } }
        self.brazos = { Der = { hombro = -1.5, codo = 1.5 }, Izq = { hombro = -1.5, codo = 1.5 } }
        self:controlar(0, 0, dt)
        -- Sube poco a poco (en 1,5 s llega a toda la ayuda).
        local k = math.min(1, self.relojFase / 1.5)
        self:ayudar(3, { 0, 0, 1 }, 300 * k, 0.45 * k)
        if m[11] > R.casiDerecho then
            fase(self, 'subir')
        end
    elseif self.fase == 'subir' then
        self.brazos = { Der = { hombro = -0.3, codo = 0.6 }, Izq = { hombro = -0.3, codo = 0.6 } }
        self:controlar(0, 0, dt)
        local angulo = self:ayudar(3, { 0, 0, 1 }, 150, 0)
        if math.abs(self.inclinacion) < R.derecho and math.abs(self.lateral) < R.derecho and angulo < R.derecho * 1.5 then
            fase(self, 'equilibrio')
        elseif m[11] < 0.4 then
            fase(self, 'suelo')
        end
    end
    if self.relojFase > R.atascado then
        fase(self, 'suelo')
    end
end

--- Matriz de una pieza (m de los robots).
function CuerpoRobot:matriz(nombre)
    local m = self.fisica:matriz(self.piezas[nombre].id, self.matrices[nombre])
    self.matrices[nombre] = m
    return m
end

return CuerpoRobot

-- Brazos y garras del robot grande (cinemática inversa de dos tramos, como
-- los brazos hidráulicos de carga): para llevar la garra a un punto mueve
-- la pierna telescópica (sube o baja el torso), el hombro y el codo, y la
-- muñeca se inclina para que la garra quede siempre horizontal. Las dos uñas
-- de cada garra abren y cierran sobre su pivote. Lo que coge se cuelga del
-- punto de agarre de la garra (`agarreIzq`/`agarreDer`, el centro de las
-- uñas cerradas) y va con ella hasta que lo suelta.
--
-- Todo se mueve a velocidad limitada (los cilindros hidráulicos no saltan).
--
-- Órdenes que añade al robot:
--   robot:setAlcanzar(lado, x, y, z)  lleva la garra 'izq'/'der' a (x, y, z)
--                                     del almacén (nil: a la pose de reposo)
--   robot:setGarra(lado, apertura)    0 cerrada .. 1 abierta del todo
--   robot:setCogerConGarra(lado, objeto)  lo cuelga de la garra
--   robot:setSoltarDeGarra(lado)      lo deja (en el suelo si está a ras)
--   robot:getGarraLista(lado)         true si el brazo y la garra llegaron
--   robot:getLlevandoGarras()         lo que lleva (el primero), o nil
--   robot:getPuntoGarra(lado)         x, y, z del punto de agarre
--   robot:getAlcanceGarra(lado)       x, y (en el robot: delante, a un lado)
--                                     donde la garra trabaja más cómoda

---@class BrazosPesado : Robot
local BrazosPesado = {}
local Robot = GestorRobots.Robot
local PiezaRobot = require('almacen.robots.pieza')

BrazosPesado.velocidadGiro = 0.6 -- rad/s de cada articulación
BrazosPesado.velocidadPierna = 0.25 -- m/s de la pierna telescópica
BrazosPesado.velocidadUnas = 0.9 -- rad/s de las uñas
BrazosPesado.piernaMin, BrazosPesado.piernaMax = -0.45, 0.6
BrazosPesado.unaAbierta = 0.42 -- rad de más que abre cada uña (del modelo)
BrazosPesado.unaCerrada = -0.14 -- rad que cierra sobre algo
BrazosPesado.comodo = 2.1 -- m delante del centro donde trabaja la garra (lo que coge queda a 20 cm de las orugas)

local LADOS = { izq = 'Izq', der = 'Der' }

-- Matriz de reposo de una pieza en el robot (la cadena de padres).
local function reposo(p)
    if not p.padre then
        return p.datos.matriz
    end
    return PiezaRobot.multiplicar(reposo(p.padre), p.datos.matriz)
end

local function invertir(m)
    -- Matriz rígida (giro + traslación).
    local r = { m[1], m[5], m[9], 0, m[2], m[6], m[10], 0, m[3], m[7], m[11], 0, 0, 0, 0, 1 }
    r[4] = -(r[1] * m[4] + r[2] * m[8] + r[3] * m[12])
    r[8] = -(r[5] * m[4] + r[6] * m[8] + r[7] * m[12])
    r[12] = -(r[9] * m[4] + r[10] * m[8] + r[11] * m[12])
    return r
end

local function acercar(actual, objetivo, paso)
    return actual + math.max(-paso, math.min(paso, objetivo - actual))
end

function BrazosPesado:onLoad()
    local d = self.datos.brazosPesado
    d.pierna, d.piernaObjetivo = 0, 0
    for _, s in pairs(LADOS) do
        local hombro = reposo(self:getPieza('hombro' .. s))
        local codo = reposo(self:getPieza('codo' .. s))
        local munieca = reposo(self:getPieza('munieca' .. s))
        local agarre = reposo(self:getPieza('agarre' .. s))
        local b = {
            -- En el plano del brazo (x delante, z arriba), con la pierna en 0.
            S = { hombro[4], hombro[12] },
            C = { codo[4], codo[12] },
            W = { munieca[4], munieca[12] },
            y = agarre[8],
            largoGarra = agarre[4] - munieca[4],
            hombro = 0, codo = 0, munieca = 0, -- giros actuales
            objetivo = { 0, 0, 0 },
            una = 0, unaObjetivo = 0,
            giro = 0, giroObjetivo = 0, -- de la muñeca sobre su eje (0: uñas a los lados)
        }
        b.L1 = math.sqrt((b.C[1] - b.S[1]) ^ 2 + (b.C[2] - b.S[2]) ^ 2)
        b.L2 = math.sqrt((b.W[1] - b.C[1]) ^ 2 + (b.W[2] - b.C[2]) ^ 2)
        b.a1 = math.atan2(b.C[2] - b.S[2], b.C[1] - b.S[1])
        b.a2 = math.atan2(b.W[2] - b.C[2], b.W[1] - b.C[1])
        b.reposoZ = agarre[12]
        d[s] = b
    end
end

-- Giros de hombro, codo y muñeca para llevar la garra a (gx, gz) del robot
-- con la pierna en `pierna`. nil si no llega.
local function resolver(b, gx, gz, pierna)
    local sx, sz = b.S[1], b.S[2] + pierna
    local wx, wz = gx - b.largoGarra, gz
    local dx, dz = wx - sx, wz - sz
    local r = math.sqrt(dx * dx + dz * dz)
    local llega = r <= b.L1 + b.L2 - 0.01 and r >= math.abs(b.L1 - b.L2) + 0.01
    r = math.max(math.abs(b.L1 - b.L2) + 0.01, math.min(b.L1 + b.L2 - 0.01, r))
    local fi = math.atan2(dz, dx)
    local beta = math.acos(math.max(-1, math.min(1, (b.L1 * b.L1 + r * r - b.L2 * b.L2) / (2 * b.L1 * r))))
    -- El codo por debajo de la línea hombro-muñeca (como en el modelo).
    local a1 = fi - beta
    local cx, cz = sx + b.L1 * math.cos(a1), sz + b.L1 * math.sin(a1)
    local a2 = math.atan2(sz + r * math.sin(fi) - cz, sx + r * math.cos(fi) - cx)
    -- Girar en y positivo baja el +x: los giros van con el signo cambiado.
    return -(a1 - b.a1), -((a2 - a1) - (b.a2 - b.a1)), a2 - b.a2, llega
end

function BrazosPesado:onUpdate(dt)
    local d = self.datos.brazosPesado
    local B = BrazosPesado
    -- La pierna se mueve solo si un brazo no llega con ella donde está: a la
    -- altura más cercana a la actual con la que llegan los dos.
    local c, s_ = math.cos(self.rumbo), math.sin(self.rumbo)
    local lo, hi = B.piernaMin, B.piernaMax
    local algunDestino = false
    for _, s in pairs(LADOS) do
        local b = d[s]
        if b.destino then
            algunDestino = true
            local gx = b.destino.adelante
            if not gx then
                local qx, qy = b.destino[1] - self.x, b.destino[2] - self.y
                gx = c * qx + s_ * qy
            end
            local dx = gx - b.largoGarra - b.S[1]
            local R = b.L1 + b.L2 - 0.03
            local h = math.sqrt(math.max(0, R * R - dx * dx))
            local dz = b.destino[3] - b.S[2]
            lo, hi = math.max(lo, dz - h), math.min(hi, dz + h)
        end
    end
    if not algunDestino then
        d.piernaObjetivo = 0 -- con los brazos en reposo, a su altura
    elseif lo <= hi then
        d.piernaObjetivo = math.max(lo, math.min(hi, d.piernaObjetivo))
    end
    d.pierna = acercar(d.pierna, d.piernaObjetivo, B.velocidadPierna * dt)
    for _, s in pairs(LADOS) do
        local b = d[s]
        local h, k, w = 0, 0, 0
        b.llega = true
        if b.destino then
            local gx = b.destino.adelante
            if not gx then
                -- Del almacén al robot.
                local qx, qy = b.destino[1] - self.x, b.destino[2] - self.y
                gx = c * qx + s_ * qy
            end
            h, k, w, b.llega = resolver(b, gx, b.destino[3], d.pierna)
        end
        local paso = B.velocidadGiro * dt
        b.hombro = acercar(b.hombro, h, paso)
        b.codo = acercar(b.codo, k, paso)
        b.munieca = acercar(b.munieca, w, paso)
        b.una = acercar(b.una, b.unaObjetivo, B.velocidadUnas * dt)
        b.giro = acercar(b.giro, b.giroObjetivo, B.velocidadGiro * 2 * dt)
        b.quieto = math.abs(b.giro - b.giroObjetivo) < 0.01 and math.abs(b.hombro - h) < 0.01 and math.abs(b.codo - k) < 0.01 and math.abs(b.una - b.unaObjetivo) < 0.01 and math.abs(d.pierna - d.piernaObjetivo) < 0.005
    end
end

function BrazosPesado:onPose()
    local d = self.datos.brazosPesado
    self:getPieza('pierna'):setDesplazamiento(0, 0, d.pierna)
    self:getPieza('piernaMedia'):setDesplazamiento(0, 0, d.pierna * 0.5)
    for _, s in pairs(LADOS) do
        local b = d[s]
        self:getPieza('hombro' .. s):setGiro('y', b.hombro)
        self:getPieza('codo' .. s):setGiro('y', b.codo)
        self:getPieza('munieca' .. s):setGiro('y', b.munieca)
        self:getPieza('munieca' .. s):setGiro('x', b.giro, 'girar')
        self:getPieza('garra' .. s .. 'A'):setGiro('z', b.una)
        self:getPieza('garra' .. s .. 'B'):setGiro('z', -b.una)
    end
end

-- Órdenes ----------------------------------------------------------------------

function Robot:setAlcanzar(lado, x, y, z)
    local b = self.datos.brazosPesado[LADOS[lado]]
    b.destino = x and { x, y, z } or nil
    b.quieto = false -- hasta que el próximo cuadro diga si llegó
end

--- Lleva la garra a `adelante` m delante del centro del robot y `alto` m
-- del suelo (va con el robot al moverse: para llevar cosas).
function Robot:setAlcanzarEnRobot(lado, adelante, alto)
    local b = self.datos.brazosPesado[LADOS[lado]]
    b.destino = { 0, 0, alto, adelante = adelante }
    b.quieto = false
end

function Robot:setGarra(lado, apertura)
    local B = BrazosPesado
    local b = self.datos.brazosPesado[LADOS[lado]]
    b.unaObjetivo = B.unaCerrada + (B.unaAbierta - B.unaCerrada) * apertura
    b.quieto = false
end

--- Gira la garra sobre el eje de la muñeca (rad): 0 las uñas cierran de
-- lado a lado; pi/2, de arriba abajo (contenedores, misiles).
function Robot:setGiroGarra(lado, angulo)
    local b = self.datos.brazosPesado[LADOS[lado]]
    b.giroObjetivo = angulo or 0
    b.quieto = false
end

function Robot:getGarraLista(lado)
    local b = self.datos.brazosPesado[LADOS[lado]]
    return b.quieto
end

function Robot:getPuntoGarra(lado)
    return self:getPieza('agarre' .. LADOS[lado]):getPosicion()
end

function Robot:getAlcanceGarra(lado)
    return BrazosPesado.comodo, self.datos.brazosPesado[LADOS[lado]].y
end

function Robot:setCogerConGarra(lado, objeto)
    local b = self.datos.brazosPesado[LADOS[lado]]
    local m = self:getPieza('agarre' .. LADOS[lado]):getMatriz()
    objeto:setSoltar()
    b.llevando = objeto
    b.relativa = PiezaRobot.multiplicar(invertir(m), objeto:getMatriz())
    objeto.llevadoPor = self
end

function Robot:setSoltarDeGarra(lado)
    local b = self.datos.brazosPesado[LADOS[lado]]
    local o = b.llevando
    if not o then
        return
    end
    -- Derecho y apoyado en el suelo si queda cerca de él.
    local x, y, z = o:getPosicion()
    o:setPosicion(x, y, z < 0.15 and 0 or z, o:getRumbo())
    o.llevadoPor = nil
    b.llevando, b.relativa = nil, nil
end

function Robot:getLlevandoGarras()
    local d = self.datos.brazosPesado
    if not (d and d.Izq) then
        return nil -- aún sin cargar (el lidar barre antes en onLoad)
    end
    return d.Izq.llevando or d.Der.llevando
end

--- Pone lo que llevan las garras donde están ellas (lo llama la escena
-- después de colocar los robots).
function Robot:moverLoQueLlevan()
    local d = self.datos.brazosPesado
    if not d then
        return
    end
    for _, s in pairs(LADOS) do
        local b = d[s]
        if b.llevando then
            local m = PiezaRobot.multiplicar(self:getPieza('agarre' .. s):getMatriz(), b.relativa)
            -- Lo que cuelga de la garra no se inclina (la garra va horizontal):
            -- solo gira en z.
            local rumbo = math.atan2(m[5], m[1])
            b.llevando:setPosicion(m[4], m[8], m[12], rumbo)
        end
    end
end

GestorRobots.registrarEspecializacion('brazosPesado', BrazosPesado)
return BrazosPesado

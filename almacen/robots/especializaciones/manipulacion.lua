-- Manipulación: lleva cada pinza a un punto del almacén con cinemática
-- inversa y coge y deja objetos por sus puntos de agarre.
--
-- Cinemática inversa: el hombro (adelante y a los lados) y el codo ponen el
-- punto entre las yemas donde se pide (mínimos cuadrados amortiguados, con
-- la jacobiana numérica de la cadena de piezas de verdad: hombro → brazo →
-- codo → muñeca → agarre); la muñeca gira hasta que los dedos cierran en la
-- dirección del punto de agarre (su `eje`). Cada cuadro se vuelve a resolver
-- desde lo de antes (si el robot se mueve, la mano sigue en su sitio) y los
-- servos del script `brazos` llevan las articulaciones hasta ahí.
--
-- Lo que lleva cuelga de los puntos de agarre: se queda derecho (pinzado por
-- dos puntos, o por el asa, gira sobre ellos y el peso lo endereza).
--
-- Órdenes que añade al robot:
--   robot:setManoA(lado, x, y, z, eje)   lleva la pinza a (x, y, z) del
--                                        almacén; `eje` {x, y, z}: hacia donde
--                                        cierran los dedos; nil la suelta
--   robot:setManoRelativa(lado, x, y, z, eje)  igual, en ejes del robot
--                                        (x delante, y izquierda): va con él
--   robot:getManoEn(lado)                true si la pinza ha llegado
--   robot:getAlcanza(lado, x, y, z)      true si llega sin pasar de los
--                                        límites del brazo (y el error)
--   robot:getManoError(lado)             metros que le faltan
--   robot:getPuedeCoger(objeto)          true, o false y por qué
--   robot:setCoger(objeto)               lo coge (las pinzas en sus puntos)
--   robot:setDejar(mueble, numero)       lo deja en ese hueco
--   robot:getLlevando()                  lo que lleva, o nil
--   robot:getManosPara(objeto)           { {lado, punto}, ... } qué mano a
--                                        qué punto de agarre

---@class Manipulacion : Robot
local Manipulacion = {}
local Robot = GestorRobots.Robot
local PiezaRobot = require('almacen.robots.pieza')
local mul, rot = PiezaRobot.multiplicar, PiezaRobot.rotacion

Manipulacion.cargaPorMano = 10 -- kg
Manipulacion.iteraciones = 20
Manipulacion.amortiguado = 0.04
Manipulacion.alcanzaHasta = 0.012 -- m de error con el que da un punto por alcanzable

local LADOS = { izq = 'Izq', der = 'Der' }

function Manipulacion:onLoad()
    local d = self.datos.manipulacion
    d.izq = { q = { 0, 0, 0, 0 } }
    d.der = { q = { 0, 0, 0, 0 } }
end

-- Matriz del agarre (y la de la muñeca sin su giro) para los ángulos q.
local function cadena(self, lado, q)
    local s = LADOS[lado]
    local signo = lado == 'izq' and 1 or -1
    local m = self:getPieza('torso').mundo
    m = mul(m, self:getPieza('hombro' .. s).datos.matriz)
    m = mul(m, rot('y', -q[1]))
    m = mul(m, self:getPieza('brazo' .. s).datos.matriz)
    m = mul(m, rot('x', signo * q[2]))
    m = mul(m, self:getPieza('codo' .. s).datos.matriz)
    m = mul(m, rot('y', -q[3]))
    local muneca = mul(m, self:getPieza('munieca' .. s).datos.matriz)
    local agarre = mul(muneca, self:getPieza('agarre' .. s).datos.matriz)
    return agarre, muneca
end

-- Los mismos límites de brazos.lua (como un brazo humano).
local function limitar(q)
    local Brazos = require('almacen.robots.especializaciones.brazos')
    for k = 1, 3 do
        q[k] = Brazos.limitar(k, q[k])
    end
end

-- Resuelve q (se cambia en su sitio) para llevar el agarre a (tx, ty, tz).
-- Devuelve el error que queda (m).
local function resolver(self, lado, q, tx, ty, tz)
    local err = math.huge
    for _ = 1, Manipulacion.iteraciones do
        local m = cadena(self, lado, q)
        local ex, ey, ez = tx - m[4], ty - m[8], tz - m[12]
        err = math.sqrt(ex * ex + ey * ey + ez * ez)
        if err < 0.001 then
            break
        end
        -- Jacobiana numérica (3 x 3).
        local J = {}
        for k = 1, 3 do
            local antes = q[k]
            q[k] = antes + 1e-4
            local n = cadena(self, lado, q)
            q[k] = antes
            J[k] = { (n[4] - m[4]) / 1e-4, (n[8] - m[8]) / 1e-4, (n[12] - m[12]) / 1e-4 }
        end
        -- A = J·Jᵀ + λ²·I ; dq = Jᵀ · A⁻¹ · e
        local l2 = Manipulacion.amortiguado ^ 2
        local A = {}
        for i = 1, 3 do
            A[i] = {}
            for j = 1, 3 do
                A[i][j] = J[1][i] * J[1][j] + J[2][i] * J[2][j] + J[3][i] * J[3][j] + (i == j and l2 or 0)
            end
        end
        local det = A[1][1] * (A[2][2] * A[3][3] - A[2][3] * A[3][2]) - A[1][2] * (A[2][1] * A[3][3] - A[2][3] * A[3][1]) + A[1][3] * (A[2][1] * A[3][2] - A[2][2] * A[3][1])
        if math.abs(det) < 1e-12 then
            break
        end
        local e = { ex, ey, ez }
        -- Resuelve A·w = e (Cramer).
        local function columna(c)
            local B = { { A[1][1], A[1][2], A[1][3] }, { A[2][1], A[2][2], A[2][3] }, { A[3][1], A[3][2], A[3][3] } }
            for i = 1, 3 do
                B[i][c] = e[i]
            end
            return (B[1][1] * (B[2][2] * B[3][3] - B[2][3] * B[3][2]) - B[1][2] * (B[2][1] * B[3][3] - B[2][3] * B[3][1]) + B[1][3] * (B[2][1] * B[3][2] - B[2][2] * B[3][1])) / det
        end
        local w = { columna(1), columna(2), columna(3) }
        for k = 1, 3 do
            local dq = J[k][1] * w[1] + J[k][2] * w[2] + J[k][3] * w[3]
            q[k] = q[k] + math.max(-0.3, math.min(0.3, dq))
        end
        limitar(q)
    end
    return err
end

-- Giro de la muñeca para que los dedos cierren a lo largo de `eje`.
local function giroMuneca(self, lado, q, eje)
    local _, m = cadena(self, lado, q)
    -- Columnas y, z de la muñeca sin girar.
    local yx, yy, yz = m[2], m[6], m[10]
    local zx, zy, zz = m[3], m[7], m[11]
    local a = math.atan2(eje[1] * zx + eje[2] * zy + eje[3] * zz, eje[1] * yx + eje[2] * yy + eje[3] * yz)
    -- Los dedos son simétricos: vale a o a ± π; se queda con el que cae en
    -- ±90° (la muñeca no da vueltas).
    a = (a + math.pi / 2) % math.pi - math.pi / 2
    q[4] = a
end

-- Punto del robot (x delante, y izquierda, z arriba) al almacén.
local function delRobot(self, x, y, z)
    local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
    return self.x + c * x - s * y, self.y + s * x + c * y, z
end

local function ejeDelRobot(self, e)
    local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
    return { c * e[1] - s * e[2], s * e[1] + c * e[2], e[3] }
end

function Manipulacion:onUpdate()
    local d = self.datos.manipulacion
    for lado in pairs(LADOS) do
        local m = d[lado]
        local t = m.objetivo
        if t then
            local x, y, z, eje = t[1], t[2], t[3], t.eje
            if t.relativo then
                x, y, z = delRobot(self, x, y, z)
                eje = eje and ejeDelRobot(self, eje)
            end
            m.error = resolver(self, lado, m.q, x, y, z)
            if eje then
                giroMuneca(self, lado, m.q, eje)
            end
            m.destino = { x, y, z }
            -- Sin cambios de menos de una décima de grado (si no, las
            -- correcciones de cada cuadro hacen temblar la mano).
            local ultimo = m.enviado
            local cambia = not ultimo
            for k = 1, 4 do
                if ultimo and math.abs(m.q[k] - ultimo[k]) > 0.002 then
                    cambia = true
                end
            end
            if cambia then
                m.enviado = { m.q[1], m.q[2], m.q[3], m.q[4] }
                self:setBrazo(lado, m.q[1], m.q[2], m.q[3], m.q[4])
            end
        end
    end
    -- Lo que lleva cuelga de las pinzas (derecho).
    if d.objeto then
        local o = d.objeto
        local sx, sy, sz, n = 0, 0, 0, 0
        local lx, ly, lz = 0, 0, 0
        for _, a in ipairs(d.agarres) do
            local px, py, pz = self:getPieza('agarre' .. LADOS[a.lado]):getPosicion()
            sx, sy, sz, n = sx + px, sy + py, sz + pz, n + 1
            lx, ly, lz = lx + a.punto[2], ly + a.punto[3], lz + a.punto[4]
        end
        sx, sy, sz, lx, ly, lz = sx / n, sy / n, sz / n, lx / n, ly / n, lz / n
        local rumbo = self.rumbo + d.giro
        local c, s = math.cos(rumbo), math.sin(rumbo)
        o:setMatriz({ c, -s, 0, sx - (c * lx - s * ly), s, c, 0, sy - (s * lx + c * ly), 0, 0, 1, sz - lz, 0, 0, 0, 1 })
    end
end

-- Órdenes -------------------------------------------------------------------------

--- Lleva la pinza `lado` a (x, y, z) del almacén; `eje`: hacia donde cierran
-- los dedos. Sin x: deja de buscar (el brazo se queda donde está).
function Robot:setManoA(lado, x, y, z, eje)
    local m = self.datos.manipulacion[lado]
    m.objetivo = x and { x, y, z, eje = eje } or nil
    m.destino = nil
    m.enviado = nil
end

--- Igual que setManoA pero en ejes del robot (x delante, y izquierda, z
-- arriba desde el suelo): la mano va con el robot.
function Robot:setManoRelativa(lado, x, y, z, eje)
    local m = self.datos.manipulacion[lado]
    m.objetivo = x and { x, y, z, eje = eje, relativo = true } or nil
    m.destino = nil
    m.enviado = nil
end

--- `true` si la pinza `lado` puede llegar a (x, y, z) desde donde está el
-- robot sin pasar de los límites del brazo; y el error que quedaría (m).
function Robot:getAlcanza(lado, x, y, z)
    local q = {}
    for k = 1, 4 do
        q[k] = self.datos.manipulacion[lado].q[k]
    end
    local err = resolver(self, lado, q, x, y, z)
    -- Otra vez desde la pose de la foto, por si desde la de ahora se atasca.
    if err > Manipulacion.alcanzaHasta then
        local q2 = { 0.3, 0.05, 0.2, 0 }
        local err2 = resolver(self, lado, q2, x, y, z)
        err = math.min(err, err2)
    end
    return err <= Manipulacion.alcanzaHasta, err
end

--- Metros entre la pinza y su objetivo (lo que resolvió la cinemática).
function Robot:getManoError(lado)
    return self.datos.manipulacion[lado].error or 0
end

--- `true` si la pinza ha llegado a su objetivo (y el brazo está quieto).
function Robot:getManoEn(lado, tolerancia)
    local m = self.datos.manipulacion[lado]
    if not m.objetivo or not m.destino then
        return true
    end
    local px, py, pz = self:getPieza('agarre' .. LADOS[lado]):getPosicion()
    local t = m.destino
    local d = math.sqrt((px - t[1]) ^ 2 + (py - t[2]) ^ 2 + (pz - t[3]) ^ 2)
    return d < (tolerancia or 0.012) and self:getBrazosQuietos()
end

--- Qué mano va a qué punto de agarre: { { lado, punto }, ... }.
function Robot:getManosPara(objeto)
    local puntos = objeto:getPuntosAgarre()
    local r = {}
    if #puntos >= 2 then
        for _, p in ipairs(puntos) do
            if p.mano == 'izq' or p.mano == 'der' then
                r[#r + 1] = { lado = p.mano, punto = p }
            end
        end
    elseif #puntos == 1 then
        local p = puntos[1]
        r[1] = { lado = (p.mano == 'izq') and 'izq' or 'der', punto = p }
    end
    return r
end

--- `true` si puede llevarlo; si no, `false` y el motivo.
function Robot:getPuedeCoger(objeto)
    if not objeto:getMovible() then
        return false, objeto:getNombre() .. ' no se mueve'
    end
    local manos = self:getManosPara(objeto)
    if #manos == 0 then
        return false, objeto:getNombre() .. ' no tiene puntos de agarre para pinzas'
    end
    if objeto:getPeso() > Manipulacion.cargaPorMano * #manos then
        return false, string.format('%s pesa %d kg y este robot carga %d kg por mano', objeto:getNombre(), objeto:getPeso(), Manipulacion.cargaPorMano)
    end
    if self.datos.manipulacion.objeto then
        return false, 'ya lleva algo'
    end
    return true
end

--- Lo coge: a partir de ahora va colgado de las pinzas (que deberían estar
-- cerradas en sus puntos de agarre).
function Robot:setCoger(objeto)
    local puede, motivo = self:getPuedeCoger(objeto)
    if not puede then
        return false, motivo
    end
    local d = self.datos.manipulacion
    d.objeto = objeto
    d.agarres = {}
    for _, m in ipairs(self:getManosPara(objeto)) do
        d.agarres[#d.agarres + 1] = { lado = m.lado, punto = m.punto['local'] }
    end
    d.giro = objeto:getRumbo() - self.rumbo
    -- De dónde lo coge: si le quitan el trabajo con él en las manos, vuelve
    -- ahí (guion.lua).
    local mueble, numero = objeto:getApoyadoEn()
    d.origen = mueble and { mueble, numero } or nil
    objeto:setSoltar()
    objeto.llevadoPor = self
    return true
end

--- Lo deja en el hueco `numero` del mueble, en su sitio.
function Robot:setDejar(mueble, numero)
    local d = self.datos.manipulacion
    local o = d.objeto
    if not o then
        return
    end
    d.objeto, d.agarres, d.origen = nil, nil, nil
    o.llevadoPor = nil
    o:setApoyar(mueble, numero)
end

--- Lo que lleva, o nil.
function Robot:getLlevando()
    -- El robot grande lleva con sus garras (brazosPesado.lua).
    if not self.datos.manipulacion then
        return self.getLlevandoGarras and self:getLlevandoGarras() or nil
    end
    return self.datos.manipulacion.objeto
end

GestorRobots.registrarEspecializacion('manipulacion', Manipulacion)
return Manipulacion

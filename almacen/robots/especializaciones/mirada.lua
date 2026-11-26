-- Mirada: el cuello gira a los lados y la cabeza se inclina para mirar a un
-- punto del almacén. Sin punto, mira hacia donde va (y adelanta la mirada en
-- las curvas). Los giros van suaves y con límites, como un cuello de verdad.
--
-- Órdenes que añade al robot:
--   robot:setMirarA(x, y, z)   mira a ese punto (nil: hacia delante)
--   robot:getMirandoA()        x, y, z (nil si mira hacia delante)
--   robot:getOjos()            los dos rayos de los ojos: { x0, y0, z0, x1,
--                              y1, z1, tipo, objeto, nombre, distancia }
--   robot:getHaVisto(objeto)   true si los ojos lo han tocado hace poco
--   robot:getReconocido()      lo último que han reconocido los ojos
--   robot:getConocidos()       { [objeto] = cuándo lo vio } (lo aprendido)
--   robot:getCarteles()        los carteles leídos y dónde están
--
-- Los ojos se mueven solos dentro de la cabeza (35° de lado, 25° arriba y
-- abajo), muy deprisa: miran lo que hay sin girar la cabeza.
--
--   robot:setFoco(x, y, z)     adonde va su atención mientras anda (lo que va a
--                              coger o el hueco donde lo va a dejar); nil: delante
--
-- Prioridad: el punto de setMirarA > un obstáculo nuevo cerca (le echa un
-- vistazo un momento para saber qué es) > el foco (si queda dentro de los
-- 90° del cuello) > hacia delante. Los ojos reconocen lo que tocan.

---@class Mirada : Robot
local Mirada = {}
local Robot = GestorRobots.Robot

Mirada.limiteLado = math.rad(90)
Mirada.vistazo = 1.0 -- s que mira un obstáculo nuevo
Mirada.cercaObstaculo = 1.6 -- m: lo que esté más cerca, delante, merece un vistazo
Mirada.olvidar = 6 -- s: pasado esto, el mismo obstáculo vuelve a merecer vistazo
Mirada.parpadeo = 0.13 -- s con los párpados cerrados
Mirada.ojosCada = 1 / 15 -- s entre rayos de los ojos
Mirada.pupila = 0.003 -- m del centro del globo a la cara del núcleo (robot pequeño)
Mirada.alcanceOjos = 30
Mirada.limiteArriba = math.rad(40)
Mirada.limiteAbajo = math.rad(35)
Mirada.rapidez = 4 -- cuánto sigue la cabeza al objetivo (1/s)
-- Los ojos se mueven solos dentro de la cabeza, muy deprisa (como los de una
-- persona: ve sin girar la cabeza). La cabeza solo gira si lo que mira se
-- sale de lo que alcanzan los ojos.
Mirada.ojoLado = math.rad(35)
Mirada.ojoArriba = math.rad(25)
Mirada.ojoRapidez = 30 -- 1/s: casi un salto
Mirada.fijarOjos = 0.45 -- s que los ojos se quedan en cada cosa al curiosear
Mirada.holguraPaso = 0.2 -- m que quiere tener a cada lado al pasar un hueco
Mirada.giroAnillo = 1.2 -- rad/s del aro dentado de los ojos, en reposo
Mirada.giroEnfocar = 9 -- rad/s de más al enfocar algo nuevo
Mirada.giroGlobo = 0.6 -- el globo del ojo gira esta parte de lo que miran los ojos
-- Diafragma (18 láminas, cada una gira sobre su pivote): apertura 0..1.
Mirada.hojas = 18
Mirada.giroHojas = 0.75 -- rad de lámina de cerrado a abierto
Mirada.apertura = { normal = 0.6, enfoque = 0.22, alerta = 0.95, tenso = 0.4, combate = 0.1 }
-- Párpados blindados: cuánto bajan (+) o suben (-) desde el reposo, en
-- metros del robot pequeño (se escala con el ojo), y la inclinación.
Mirada.parpados = {
    normal = { 0, 0, 0 },
    enfoque = { 0.007, 0.006, 0 },
    alerta = { -0.012, -0.01, 0 },
    tenso = { 0.005, 0.002, 0.28 },
    -- Peleando (el dueño, 18-nov: «cara de combate»): el de arriba baja
    -- mucho y el de abajo sube algo, con el ceño fruncido: mirada dura.
    combate = { 0.012, 0.006, 0.35 },
}
-- Peleando, lo que brilla en cian (núcleo de los ojos, oídos) pasa a rojo.
Mirada.colorCombate = { 1.0, 0.08, 0.03 }
Mirada.cambioColor = 4 -- 1/s: lo rápido que cambia de color
Mirada.materialesQueBrillan = { robotNucleo = true, robotOjo = true, robotIris = true }
Mirada.cerrarParpado = 0.021 -- lo que baja cada párpado para cerrar el ojo
Mirada.curiosear = 8 -- m: lo más lejos que mira cosas con los ojos al andar

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Mirada:onLoad()
    local d = self.datos.mirada
    d.lado, d.arriba = 0, 0
    d.ojoLado, d.ojoArriba = 0, 0
    d.reloj, d.relojOjos = 0, 0
    d.ojos = {}
    d.vistos = {} -- [objeto o tipo] = momento en que lo tocaron los ojos
    d.ojeados = {} -- [objeto o tipo] = momento del último vistazo
    d.conocidos = {} -- [objeto] = la última vez que lo vio (lo que se ha aprendido)
    d.sabe = {} -- [zona de información] = cuándo la leyó (puertas, marcos, esquinas)
    d.carteles = {} -- carteles leídos: { tipo, x, y, z, n }
    d.rojo = 0
    -- Copia propia de los materiales que brillan (para ponerse rojo él
    -- solo, no todos los robots que comparten el modelo).
    d.brillos = {}
    local copias = {}
    for _, p in pairs(self.piezas) do
        for _, malla in pairs(p.objeto and p.objeto.meshes or {}) do
            local m = malla.material
            if m and Mirada.materialesQueBrillan[m.name] then
                if not copias[m] then
                    local copia = m:clone()
                    copias[m] = copia
                    d.brillos[#d.brillos + 1] = {
                        material = copia,
                        emision = { copia.emission[1], copia.emission[2], copia.emission[3] },
                        factor = { copia.emissionFactor[1], copia.emissionFactor[2], copia.emissionFactor[3] },
                        color = { copia.color[1], copia.color[2], copia.color[3], copia.color[4] },
                    }
                end
                malla.material = copias[m]
            end
        end
    end
end

-- ¿Hay algo nuevo cerca delante (según el lidar) que merezca un vistazo?
-- No cuenta lo que ya es su foco ni lo que acaba de mirar.
local function obstaculoNuevo(self, d)
    if not self.getRayos or math.abs(self.velocidad or 0) < 0.2 then
        return
    end
    local mejor
    for _, r in ipairs(self:getRayos()) do
        if r.choca and r.distancia < Mirada.cercaObstaculo then
            local a = angulo(r.angulo - self.rumbo)
            local clave = r.objeto or r.tipo
            local ultimo = d.ojeados[clave]
            if math.abs(a) < math.rad(80) and clave ~= d.focoObjeto and (not ultimo or d.reloj - ultimo > Mirada.olvidar) then
                if not mejor or r.distancia < mejor.distancia then
                    mejor = r
                end
            end
        end
    end
    return mejor
end

local apuntarCartel

local function nombreDe(tipo, objeto)
    if objeto then
        return objeto:getNombre()
    end
    if tipo == 'suelo' then
        return 'suelo'
    end
    return require('almacen.robots.vista_sensores').nombre(tipo)
end

-- Un cartel visto en (x, y, z): se junta con el del mismo tipo a menos de
-- 1,5 m (un cartel es una placa de 2,6 m) o se apunta uno nuevo.
function apuntarCartel(d, tipo, x, y, z)
    for _, c in ipairs(d.carteles) do
        if c.tipo == tipo and math.abs(c.x - x) < 1.5 and math.abs(c.y - y) < 0.6 then
            c.n = c.n + 1
            c.x, c.y = c.x + (x - c.x) / c.n, c.y + (y - c.y) / c.n
            return
        end
    end
    d.carteles[#d.carteles + 1] = { tipo = tipo, x = x, y = y, z = z, n = 1 }
    print(string.format('ROBOT veo un %s en %.1f, %.1f', tipo, x, y))
end

--- Lo que le dice una zona de información, en palabras, con lo que decide
-- (si cabe por un hueco y cuánto le sobra a cada lado).
function Mirada.describir(robot, info)
    local function m(v)
        return (string.format('%.1f', v):gsub('%.', ','))
    end
    if info.tipo == 'porton' or info.tipo == 'puerta' then
        local texto = string.format('%s: %s m de ancho y %s de alto', info.nombre, m(info.ancho), m(info.alto))
        if not info.abierto then
            return texto .. ', cerrada: no se pasa'
        end
        local cabe, sobra = robot:getCabePor(info)
        if cabe then
            return texto .. string.format(', abierto: quepo, paso por el centro a %s m de cada marco', m(sobra))
        end
        return texto .. ': no quepo'
    elseif info.tipo == 'marco' then
        local hueco = info.hueco
        if hueco and hueco.abierto then
            local cabe, sobra = robot:getCabePor(hueco)
            if cabe then
                return string.format('%s: le paso a %s m', info.nombre, m(sobra))
            end
            return info.nombre .. ': el hueco es demasiado estrecho para mí'
        end
        return info.nombre .. ': hueco cerrado'
    end
    return info.nombre
end

-- Los dos rayos de los ojos, hacia donde mira la cabeza (con su inclinación).
local function mirarConLosOjos(self, d)
    local MundoRobot = require('almacen.robots.mundo')
    local cabeza = self:getPieza('cabeza')
    local m = cabeza:getMatriz()
    if not m then
        return
    end
    -- Delante de la cabeza, girado lo que van girados los ojos.
    local cl, sl = math.cos(d.ojoLado), math.sin(d.ojoLado)
    local ca, sa = math.cos(d.ojoArriba), math.sin(d.ojoArriba)
    local dx = ca * (cl * m[1] + sl * m[2]) + sa * m[3]
    local dy = ca * (cl * m[5] + sl * m[6]) + sa * m[7]
    local dz = ca * (cl * m[9] + sl * m[10]) + sa * m[11]
    for k, s in ipairs({ 'Izq', 'Der' }) do
        -- Sale del centro de la pupila (el núcleo, delante del globo).
        local ex, ey, ez = self:getPieza('ojo' .. s):getPunto(Mirada.pupila * (d.escalaOjo or 1), 0, 0)
        local dist, tipo, objeto, info = MundoRobot.rayo3D(ex, ey, ez, dx, dy, dz, Mirada.alcanceOjos, self.getLlevando and self:getLlevando())
        local o = { ex, ey, ez, ex + dx * dist, ey + dy * dist, ez + dz * dist, tipo = tipo, objeto = objeto, distancia = dist, info = info }
        -- Una zona de información (puerta, marco, esquina): se aprende sus
        -- datos la primera vez que la ve.
        if info and not d.sabe[info] then
            d.sabe[info] = d.reloj
            d.infoNueva = true
            d.enfocando = 1
            print('ROBOT veo ' .. Mirada.describir(self, info))
        end
        if tipo then
            o.nombre = nombreDe(tipo, objeto)
            d.vistos[objeto or tipo] = d.reloj
            -- Lo que ve, se lo aprende: los objetos y dónde están los carteles.
            if objeto then
                d.conocidos[objeto] = d.reloj
            elseif tipo:sub(1, 6) == 'cartel' then
                apuntarCartel(d, tipo, o[4], o[5], o[6])
            end
            if tipo ~= 'suelo' then
                -- Algo nuevo: los aros de los ojos giran deprisa un rato
                -- (como si enfocara).
                if not d.reconocido or d.reconocido.nombre ~= o.nombre then
                    d.enfocando = 1
                end
                d.reconocido = o
            end
        end
        d.ojos[k] = o
    end
end

-- Ángulos (de lado respecto al rumbo, y hacia arriba) de un punto visto
-- desde la cabeza.
local function angulosHacia(self, p)
    local cx, cy, cz = self:getPieza('cabeza'):getPosicion()
    if not cx then
        return
    end
    local dx, dy, dz = p[1] - cx, p[2] - cy, p[3] - cz
    return angulo(math.atan2(dy, dx) - self.rumbo), math.atan2(dz, math.sqrt(dx * dx + dy * dy))
end

-- Al andar sin nada que mirar, los ojos saltan de una cosa a otra de las que
-- nota el lidar y quedan al alcance de los ojos (sin girar la cabeza), para
-- reconocerlas. Prefiere lo que hace más que no ve.
local function curiosear(self, d)
    if not self.getRayos then
        return
    end
    local mejor, mejorNota
    for _, r in ipairs(self:getRayos()) do
        if r.choca and r.distancia < Mirada.curiosear then
            local a = angulo(r.angulo - self.rumbo - d.lado)
            if math.abs(a) < Mirada.ojoLado then
                local visto = d.vistos[r.objeto or r.tipo]
                local nota = (visto and math.min(d.reloj - visto, 10) or 12) - r.distancia * 0.3 + love.math.random() * 2
                if not mejorNota or nota > mejorNota then
                    mejor, mejorNota = r, nota
                end
            end
        end
    end
    if mejor then
        return { mejor.x + math.cos(mejor.angulo) * mejor.distancia, mejor.y + math.sin(mejor.angulo) * mejor.distancia, mejor.z }
    end
end

function Mirada:onUpdate(dt)
    local d = self.datos.mirada
    d.reloj = d.reloj + dt
    -- Aros de los ojos: giran despacio siempre y deprisa al enfocar algo
    -- nuevo (se va pasando en un segundo y medio).
    d.enfocando = math.max(0, (d.enfocando or 0) - dt / 1.5)
    -- Expresión: tenso si está tapado o atascado; alerta si echa un vistazo
    -- a algo nuevo; enfoque si mira algo concreto o enfoca; si no, normal.
    local nav = self.datos.navegacion
    local combatiendo = self.getCombatiendo and self:getCombatiendo()
    d.rojo = d.rojo + ((combatiendo and 1 or 0) - d.rojo) * math.min(1, dt * Mirada.cambioColor)
    if combatiendo then
        d.expresion = 'combate'
        d.enfocando = math.max(d.enfocando, 0.6) -- el aro gira deprisa mientras pelea
    elseif nav and ((nav.tapado or 0) > 0.3 or nav.saliendo) then
        d.expresion = 'tenso'
    elseif d.ojeando then
        d.expresion = 'alerta'
    elseif d.punto or d.enfocando > 0.3 then
        d.expresion = 'enfoque'
    else
        d.expresion = 'normal'
    end
    local paso = math.min(1, dt * 6)
    local objetivo = Mirada.apertura[d.expresion] + 0.05 * math.sin(d.reloj * 0.9)
    d.apertura = (d.apertura or 0.6) + (objetivo - (d.apertura or 0.6)) * paso
    local pp = Mirada.parpados[d.expresion]
    d.parpados = d.parpados or { 0, 0, 0 }
    for k = 1, 3 do
        d.parpados[k] = d.parpados[k] + (pp[k] - d.parpados[k]) * paso
    end
    d.anillo = (d.anillo or 0) + dt * (Mirada.giroAnillo + Mirada.giroEnfocar * d.enfocando)
    d.relojOjos = d.relojOjos + dt
    -- Parpadea cada 2,5 a 6 s (a veces dos veces seguidas).
    d.siguienteParpadeo = d.siguienteParpadeo or d.reloj + 2
    if d.parpadeo and d.reloj > d.parpadeo then
        d.parpadeo = nil
    elseif not d.parpadeo and d.reloj > d.siguienteParpadeo then
        d.parpadeo = d.reloj + Mirada.parpadeo
        d.siguienteParpadeo = d.reloj + (love.math.random() < 0.2 and 0.3 or 2.5 + love.math.random() * 3.5)
    end
    -- Con los párpados cerrados no ve: los rayos se apagan y no aprende
    -- nada hasta que vuelve a abrir.
    if d.parpadeo then
        d.ojos = {}
        if os.getenv('OJOS_DEPURAR') and not d.avisoCerrado then
            d.avisoCerrado = true
            print(string.format('OJOS cerrados en %.2f s: %d rayos', d.reloj, #d.ojos))
        end
    elseif d.relojOjos >= Mirada.ojosCada then
        d.relojOjos = 0
        mirarConLosOjos(self, d)
        if os.getenv('OJOS_DEPURAR') and d.avisoCerrado then
            d.avisoCerrado = false
            print(string.format('OJOS abiertos en %.2f s: %d rayos', d.reloj, #d.ojos))
        end
    end
    -- Lo que miran los ojos y adónde va la cabeza.
    local ojo -- punto que miran los ojos
    local lado, arriba = 0, 0
    if d.punto then
        ojo = d.punto
        lado, arriba = angulosHacia(self, d.punto)
        lado, arriba = lado or 0, arriba or 0
    else
        -- ¿Algo nuevo cerca? Un vistazo para saber qué es (con los ojos; la
        -- cabeza solo si se sale de su alcance).
        if not d.ojeando or d.reloj > d.ojeando.hasta then
            d.ojeando = nil
            local r = obstaculoNuevo(self, d)
            if r then
                d.ojeados[r.objeto or r.tipo] = d.reloj
                d.ojeando = {
                    hasta = d.reloj + Mirada.vistazo,
                    r.x + math.cos(r.angulo) * r.distancia, r.y + math.sin(r.angulo) * r.distancia, r.z,
                }
            end
        end
        -- La cabeza, en su foco (si queda al alcance del cuello) o delante.
        if d.foco then
            local l, a = angulosHacia(self, d.foco)
            if l and math.abs(l) <= Mirada.limiteLado then
                lado, arriba = l, a
            end
        end
        if lado == 0 and arriba == 0 then
            lado = (self.giro or 0) * 0.35
        end
        if d.ojeando then
            ojo = d.ojeando
            local l, a = angulosHacia(self, d.ojeando)
            -- Fuera del alcance de los ojos: gira la cabeza lo que falte.
            if l and math.abs(l - lado) > Mirada.ojoLado then
                lado = l - Mirada.ojoLado * (l > lado and 1 or -1)
            end
            if a and math.abs(a - arriba) > Mirada.ojoArriba then
                arriba = a - Mirada.ojoArriba * (a > arriba and 1 or -1)
            end
        elseif d.foco and d.focoConOjos then
            -- Comprobando qué es algo (combate.lua): los ojos, ahí también.
            ojo = d.foco
        else
            -- Curiosea con los ojos: salta de una cosa a otra.
            if not d.curioso or d.reloj > d.curioso.hasta then
                local p = curiosear(self, d)
                d.curioso = { hasta = d.reloj + Mirada.fijarOjos, punto = p }
            end
            ojo = d.curioso.punto
        end
    end
    lado = math.max(-Mirada.limiteLado, math.min(Mirada.limiteLado, lado))
    arriba = math.max(-Mirada.limiteAbajo, math.min(Mirada.limiteArriba, arriba))
    local f = math.min(1, dt * Mirada.rapidez)
    d.lado = d.lado + (lado - d.lado) * f
    d.arriba = d.arriba + (arriba - d.arriba) * f
    -- Los ojos: lo que les falta a la cabeza para llegar a su punto, dentro
    -- de su alcance; casi de golpe.
    local ol, oa = 0, 0
    if ojo then
        local l, a = angulosHacia(self, ojo)
        if l then
            ol = math.max(-Mirada.ojoLado, math.min(Mirada.ojoLado, angulo(l - d.lado)))
            oa = math.max(-Mirada.ojoArriba, math.min(Mirada.ojoArriba, a - d.arriba))
        end
    end
    local g = math.min(1, dt * Mirada.ojoRapidez)
    d.ojoLado = d.ojoLado + (ol - d.ojoLado) * g
    d.ojoArriba = d.ojoArriba + (oa - d.ojoArriba) * g
end

--- Los brillos, de su color a rojo según `d.rojo` (0..1).
local function ponerColor(d)
    local k = d.rojo
    if k == d.rojoPuesto then
        return
    end
    d.rojoPuesto = k
    local r = Mirada.colorCombate
    for _, b in ipairs(d.brillos) do
        local m = b.material
        -- La fuerza del brillo se queda; cambia el color.
        local fe = math.max(b.emision[1], b.emision[2], b.emision[3])
        local ff = math.max(b.factor[1], b.factor[2], b.factor[3])
        local fc = math.max(b.color[1], b.color[2], b.color[3])
        m:setEmission(b.emision[1] + (r[1] * fe - b.emision[1]) * k, b.emision[2] + (r[2] * fe - b.emision[2]) * k, b.emision[3] + (r[3] * fe - b.emision[3]) * k)
        m:setEmissionFactor(b.factor[1] + (r[1] * ff - b.factor[1]) * k, b.factor[2] + (r[2] * ff - b.factor[2]) * k, b.factor[3] + (r[3] * ff - b.factor[3]) * k)
        m:setColor(b.color[1] + (r[1] * fc - b.color[1]) * k, b.color[2] + (r[2] * fc - b.color[2]) * k, b.color[3] + (r[3] * fc - b.color[3]) * k, b.color[4])
    end
end

function Mirada:onPose()
    local d = self.datos.mirada
    ponerColor(d)
    -- Sin cuello (el soldado), la cabeza gira a los lados ella misma.
    if self:getTienePieza('cuello') then
        self:getPieza('cuello'):setGiro('z', d.lado)
    else
        self:getPieza('cabeza'):setGiro('z', d.lado, 'lado')
    end
    -- Girar en y con ángulo positivo baja la cara: para subirla, negativo.
    self:getPieza('cabeza'):setGiro('y', -d.arriba)
    -- El globo de cada ojo gira hacia donde miran los ojos; dentro, el aro
    -- de cobre gira (más deprisa al enfocar), las láminas del diafragma
    -- abren o cierran la pupila y los párpados ponen la expresión.
    -- Tamaño del ojo respecto al del robot pequeño (sus ojos están a 7,5 cm
    -- del centro de la cara).
    if self:getTienePieza('globoIzq') then
        Mirada.poseCabezaSoldado(self, d)
        return
    end
    if not d.escalaOjo then
        d.escalaOjo = math.abs(self:getPieza('ojoIzq').datos.matriz[8]) / 0.075
    end
    local e = d.escalaOjo
    for _, s in ipairs({ 'Izq', 'Der' }) do
        local ojo = self:getPieza('ojo' .. s)
        ojo:setGiro('z', d.ojoLado * Mirada.giroGlobo, 'mirarLado')
        ojo:setGiro('y', -d.ojoArriba * Mirada.giroGlobo, 'mirarArriba')
        self:getPieza('anillo' .. s):setGiro('x', d.anillo)
        self:getPieza('diafragma' .. s):setGiro('x', -0.15 * d.anillo)
        local hoja = (d.apertura - 0.5) * Mirada.giroHojas
        for k = 0, Mirada.hojas - 1 do
            self:getPieza(string.format('hoja%s%02d', s, k)):setGiro('x', hoja)
        end
        -- Párpados: la expresión y, al parpadear, cerrados.
        local cerrar = d.parpadeo and Mirada.cerrarParpado or 0
        local signo = s == 'Izq' and 1 or -1
        local sup, inf = self:getPieza('parpadoSup' .. s), self:getPieza('parpadoInf' .. s)
        sup:setDesplazamiento(0, 0, -(d.parpados[1] + cerrar) * e)
        inf:setDesplazamiento(0, 0, (d.parpados[2] + cerrar) * e)
        sup:setGiro('x', signo * d.parpados[3])
        inf:setGiro('x', -signo * d.parpados[3] * 0.4)
    end
end

-- Cabeza del robot soldado (tools/blender/robot_soldado.py, puesta en el
-- robot pequeño el 17-nov): el ojo es una bola (`globo{S}`) que gira sobre su
-- centro, los párpados son persianas de 4 láminas (la k baja o sube k
-- pasos al cerrar) y los oídos tienen tres anillos que giran.
Mirada.globoMax = 0.35 -- rad que gira la bola como mucho
Mirada.persianaPaso = 0.0338 * 0.95 / 4 -- m: radio del ojo / láminas
Mirada.oidos = { A = 0.8, B = -1.4, C = 2.2 } -- rad/s de cada anillo
-- Tamaño de estos ojos respecto a los del robot pequeño (el grande los lleva
-- a 2,8 en vez de a 0,95: escalaOjo = 2,95 en su tipo).
Mirada.escalaOjo = 1

function Mirada.poseCabezaSoldado(self, d)
    local escala = self:getAjustes('mirada').escalaOjo
    d.escalaOjo = escala
    local lado = math.max(-Mirada.globoMax, math.min(Mirada.globoMax, d.ojoLado))
    local arriba = math.max(-Mirada.globoMax, math.min(Mirada.globoMax, d.ojoArriba))
    -- Persianas: fracción cerrada por la expresión (lo que bajaban los
    -- párpados de media luna, sobre lo que bajaban al cerrar) y al parpadear.
    local function cerrado(k)
        if d.parpadeo then
            return 1
        end
        return math.max(0, math.min(1, d.parpados[k] / Mirada.cerrarParpado))
    end
    local sup, inf = cerrado(1), cerrado(2)
    d.relojOidos = (d.relojOidos or 0) + (d.enfocando or 0) * 0.05 + 0.016
    for _, s in ipairs({ 'Izq', 'Der' }) do
        local globo = self:getPieza('globo' .. s)
        globo:setGiro('z', lado, 'mirarLado')
        globo:setGiro('y', -arriba, 'mirarArriba')
        self:getPieza('anillo' .. s):setGiro('x', d.anillo)
        self:getPieza('diafragma' .. s):setGiro('x', -0.15 * d.anillo)
        local hoja = (d.apertura - 0.5) * Mirada.giroHojas
        for k = 0, Mirada.hojas - 1 do
            self:getPieza(string.format('hoja%s%02d', s, k)):setGiro('x', hoja)
        end
        for k = 1, 3 do
            self:getPieza('persianaSup' .. s .. k):setDesplazamiento(0, 0, -k * Mirada.persianaPaso * escala * sup)
            self:getPieza('persianaInf' .. s .. k):setDesplazamiento(0, 0, k * Mirada.persianaPaso * escala * inf)
        end
        if self:getTienePieza('oido' .. s .. 'A') then
            for letra, w in pairs(Mirada.oidos) do
                self:getPieza('oido' .. s .. letra):setGiro('y', d.relojOidos * w)
            end
        end
    end
    -- El engranaje del pecho del robot grande: los anillos de los oídos, en x.
    if self:getTienePieza('engranajePechoA') then
        for letra, w in pairs(Mirada.oidos) do
            self:getPieza('engranajePecho' .. letra):setGiro('x', d.relojOidos * w)
        end
    end
end

--- Mira al punto (x, y, z) del almacén; sin punto, hacia delante.
function Robot:setMirarA(x, y, z)
    self.datos.mirada.punto = x and { x, y, z or 1.5 } or nil
end

--- x, y, z de lo que mira (nil si mira hacia delante).
function Robot:getMirandoA()
    local p = self.datos.mirada.punto
    if p then
        return p[1], p[2], p[3]
    end
end

--- Adónde va su atención mientras anda (nil: hacia delante). `objeto`: lo
-- que hay ahí (no le echa vistazos como si fuera un obstáculo). `conOjos`:
-- los ojos también miran ahí (para comprobar qué es), no curiosean.
function Robot:setFoco(x, y, z, objeto, conOjos)
    local d = self.datos.mirada
    d.foco = x and { x, y, z or 1 } or nil
    d.focoObjeto = objeto
    d.focoConOjos = x and conOjos or nil
end

--- Las zonas de información que ha leído con los ojos: { [zona] = cuándo }.
-- Cada zona: { tipo = 'porton'|'puerta'|'marco'|'esquina', nombre, caja,
-- centro, normal, ancho, alto, abierto } (assets/almacen/informacion.lua).
function Robot:getSabe()
    return self.datos.mirada.sabe
end

--- ¿Cabe por el hueco `info`? Devuelve true/false y lo que le sobra a cada
-- lado (m) pasando por el centro.
function Robot:getCabePor(info)
    local sobra = (info.ancho - self:getAncho()) / 2
    return info.abierto ~= false and sobra >= Mirada.holguraPaso and info.alto >= self:getAlto() + 0.1, sobra
end

--- Lo que ha visto alguna vez con los ojos: { [objeto] = cuándo }.
function Robot:getConocidos()
    return self.datos.mirada.conocidos
end

--- Los carteles que ha leído: { { tipo = 'cartelDinero', x, y, z, n }, ... }.
function Robot:getCarteles()
    return self.datos.mirada.carteles
end

function Robot:getOjos()
    local d = self.datos.mirada
    return d and d.ojos
end

--- `true` si los ojos han tocado `objeto` en el último `segundos` (1 s).
function Robot:getHaVisto(objeto, segundos)
    local d = self.datos.mirada
    local t = d.vistos[objeto]
    return t ~= nil and d.reloj - t <= (segundos or 1)
end

function Robot:getReconocido()
    return self.datos.mirada.reconocido
end

GestorRobots.registrarEspecializacion('mirada', Mirada)
return Mirada

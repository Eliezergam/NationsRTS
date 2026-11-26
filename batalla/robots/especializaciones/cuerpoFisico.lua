-- El robot con cuerpo físico (el dueño, 18-nov), como Euphoria en GTA y Red
-- Dead (el dueño eligió «animación + física al chocar»): corre con su
-- animación de siempre (conduccion.lua, piernasSoldado.lua: patinar, tijera,
-- abrirse, agacharse) y su cuerpo de Jolt (batalla/robots/cuerpoRobot.lua)
-- lo acompaña pieza a pieza como sólido cinemático: empuja lo que toca.
-- Si choca fuerte con un tronco o una roca, o le dan un golpe, pasa a física
-- de verdad: los motores siguen pidiendo la postura de la animación y el
-- equilibrio intenta recuperarlo (frenando); si lo consigue y se queda
-- quieto y derecho, vuelve a la animación; si no, se cae. (Levantarse, más
-- adelante.)
--
-- En física, lo dibujado sigue a Jolt: la pelvis donde está el cuerpo, las
-- piernas y ruedas donde están sus piezas; torso y cabeza, lo suyo encima.
--
-- Pruebas: `BATALLA_ROBOT_PASEO=1` da vueltas grandes a 6 m/s;
-- `BATALLA_ROBOT_EMPUJON=<s>[:<N·s>]` le da un golpe de lado a esa hora;
-- `CUERPO_TRAZA=1`, cómo va cada medio segundo.

local Nucleo = require('robots.nucleo')
local PiezaRobot = require('robots.pieza')
local CuerpoRobot = require('batalla.robots.cuerpoRobot')

local CuerpoFisico = {}

CuerpoFisico.piezas = {
    'cuerpo', 'caderaDer', 'musloDer', 'espinillaDer', 'ruedaDer', 'caderaIzq', 'musloIzq', 'espinillaIzq', 'ruedaIzq',
    'baseDer', 'brazoDer', 'antebrazoDer', 'baseIzq', 'brazoIzq', 'antebrazoIzq',
}
-- La pieza del modelo que mueve cada cuerpo físico (las piezas pequeñas de
-- cadera y hombro no tienen: van con el muslo y el brazo).
CuerpoFisico.modelo = {
    cuerpo = 'pelvis', caderaDer = 'musloDer', caderaIzq = 'musloIzq',
    baseDer = 'hombroDer', brazoDer = 'hombroDer', antebrazoDer = 'codoDer',
    baseIzq = 'hombroIzq', brazoIzq = 'hombroIzq', antebrazoIzq = 'codoIzq',
}
-- Las piezas del dibujo que pone la física (en física, sin sus capas).
CuerpoFisico.dibujadas = { 'pelvis', 'torso', 'musloDer', 'espinillaDer', 'ruedaDer', 'musloIzq', 'espinillaIzq', 'ruedaIzq', 'hombroDer', 'codoDer', 'hombroIzq', 'codoIzq' }
CuerpoFisico.capas = 1 -- capa de choque del siguiente robot (2, 3...)
CuerpoFisico.paseo = { espera = 3, velocidad = 6, radio = 40 }
CuerpoFisico.chocarDesde = 2.5 -- m/s contra un tronco o una roca: pasa a física
CuerpoFisico.empujon = 80 -- N·s del golpe de prueba
CuerpoFisico.recuperado = 1.5 -- s quieto y derecho para volver a la animación

--- Inversa de una matriz rígida (giro y traslación, por filas).
local function inversa(m, s)
    s = s or {}
    s[1], s[2], s[3] = m[1], m[5], m[9]
    s[5], s[6], s[7] = m[2], m[6], m[10]
    s[9], s[10], s[11] = m[3], m[7], m[11]
    s[4] = -(s[1] * m[4] + s[2] * m[8] + s[3] * m[12])
    s[8] = -(s[5] * m[4] + s[6] * m[8] + s[7] * m[12])
    s[12] = -(s[9] * m[4] + s[10] * m[8] + s[11] * m[12])
    s[13], s[14], s[15], s[16] = 0, 0, 0, 1
    return s
end

--- La matriz de reposo de una pieza respecto a la raíz del robot.
local function reposo(robot, nombre)
    local p = robot:getPieza(nombre)
    local m = p.datos.matriz
    local padre = p.padre
    while padre do
        m = PiezaRobot.multiplicar(padre.datos.matriz, m)
        padre = padre.padre
    end
    return m
end

local function crear(self, d)
    CuerpoFisico.capas = CuerpoFisico.capas + 1
    local c = CuerpoRobot.nuevo(self.mundoFisico, self.x, self.y, self.rumbo, CuerpoFisico.capas)
    d.cuerpo = c
    -- Lo que hay entre cada cuerpo físico y su pieza del modelo, tal como
    -- se crearon (raíz en el suelo, mismo rumbo).
    local raiz = PiezaRobot.multiplicar({ 1, 0, 0, self.x, 0, 1, 0, self.y, 0, 0, 1, c.suelo0, 0, 0, 0, 1 }, PiezaRobot.rotacion('z', self.rumbo))
    d.ajuste, d.mundo = {}, {}
    for _, n in ipairs(CuerpoFisico.piezas) do
        local modelo = CuerpoFisico.modelo[n] or n
        local fisico = c:matriz(n)
        d.ajuste[n] = PiezaRobot.multiplicar(inversa(fisico), PiezaRobot.multiplicar(raiz, reposo(self, modelo)))
    end
    d.reposoPelvis = inversa(self:getPieza('pelvis').datos.matriz)
    d.ajusteInverso = {}
    for n, a in pairs(d.ajuste) do
        d.ajusteInverso[n] = inversa(a)
    end
    self.cuerpoFisico = c
    c:setCinematico(true)
    d.modo = 'animado'
    d.reloj = 0
    d.choques = self.datos.obstaculos and self.datos.obstaculos.choques or 0
    print(string.format('CUERPO FISICO de %s en (%.1f, %.1f), capa %d', self.datos.asalto and self.datos.asalto.nombre or '?', self.x, self.y, CuerpoFisico.capas))
end

function CuerpoFisico.prerequisitos(self)
    return self:getTienePieza('pelvis') and self:getTienePieza('ruedaDer') and self:getTienePieza('ruedaIzq')
end

function CuerpoFisico.onLoad(self)
    -- Llamado por la escena antes de cada paso de la física.
    self.controlarCuerpo = function(r, paso)
        local d = r.datos.cuerpoFisico
        local c = r.cuerpoFisico
        if d.modo == 'animado' then
            -- Cada pieza física, donde está la dibujada.
            for _, n in ipairs(CuerpoFisico.piezas) do
                local p = r:getPieza(CuerpoFisico.modelo[n] or n)
                if p.mundo then
                    d.objetivo = PiezaRobot.multiplicar(p.mundo, d.ajusteInverso[n])
                    c:moverA(n, d.objetivo, paso)
                end
            end
        else
            -- Tras el golpe: reflejos (frena y se equilibra; si cae, se
            -- protege con los brazos y se levanta).
            c:reflejos(paso)
        end
    end
end

--- Centro de un círculo de `radio` m que pase por el robot y quede entero
-- en tierra (el paseo no se mete en el agua); nil si no hay.
function CuerpoFisico.circuloEnTierra(self, radio)
    -- Si no cabe, uno más pequeño (junto al mar).
    for _, r in ipairs({ radio, radio * 0.6, radio * 0.35 }) do
        local c = CuerpoFisico.circuloEnTierraDe(self, r)
        if c then
            c[3] = r
            return c
        end
    end
    print('CUERPO FISICO: no hay un círculo en tierra para el paseo; se queda quieto')
end

function CuerpoFisico.circuloEnTierraDe(self, radio)
    for k = 0, 15 do
        local a = self.rumbo + math.pi / 2 + k * math.pi / 8
        local cx, cy = self.x + math.cos(a) * radio, self.y + math.sin(a) * radio
        local bien = true
        for j = 0, 31 do
            local b = j / 32 * 2 * math.pi
            local x, y = cx + math.cos(b) * radio, cy + math.sin(b) * radio
            if not self.suelo:transitable(x * 10, -y * 10) then
                bien = false
                break
            end
        end
        if bien then
            return { cx, cy }
        end
    end
end

--- Pasa a física de verdad (con un golpe de `ix, iy` N·s, si lo hay).
local function aFisica(self, d, motivo, ix, iy)
    d.modo = 'fisico'
    d.quieto = 0
    d.cuerpo:setCinematico(false)
    d.cuerpo.fase = 'equilibrio'
    if ix then
        d.cuerpo.fisica:empujar(d.cuerpo.piezas.cuerpo.id, ix, iy, 0)
    end
    self:setParar()
    print(string.format('CUERPO FISICO %s pasa a física: %s (a %.1f m/s)', self.datos.asalto and self.datos.asalto.nombre or '?', motivo, self.velocidad or 0))
end

--- Vuelve a la animación desde donde está.
local function aAnimacion(self, d)
    d.modo = 'animado'
    d.cuerpo:setCinematico(true)
    self.raizFija = nil
    for _, n in ipairs(CuerpoFisico.dibujadas) do
        if n ~= 'pelvis' and n ~= 'torso' then
            self:getPieza(n):setMatrizLocal(nil)
        end
    end
    self.velocidad, self.giro = 0, 0
    print(string.format('CUERPO FISICO %s se ha recuperado: vuelve a la animación', self.datos.asalto and self.datos.asalto.nombre or '?'))
end

function CuerpoFisico.onUpdate(self, dt)
    local d = self.datos.cuerpoFisico
    if not self.mundoFisico then
        return
    end
    if not d.cuerpo then
        crear(self, d)
    end
    d.reloj = d.reloj + dt
    if d.modo == 'animado' then
        -- Paseo de prueba: un punto por delante en un círculo grande.
        if os.getenv('BATALLA_ROBOT_PASEO') and d.reloj > CuerpoFisico.paseo.espera then
            local P = CuerpoFisico.paseo
            if d.centro == nil then
                d.centro = CuerpoFisico.circuloEnTierra(self, P.radio) or false
            end
        end
        if d.centro and d.reloj > CuerpoFisico.paseo.espera then
            local P = CuerpoFisico.paseo
            local radio = d.centro[3]
            local a = math.atan2(self.y - d.centro[2], self.x - d.centro[1]) + 14 / radio
            self:setVelocidadMaxima(P.velocidad * math.min(1, radio / P.radio + 0.3))
            self:setIrA(d.centro[1] + math.cos(a) * radio, d.centro[2] + math.sin(a) * radio, nil, true)
        end
        -- Choque fuerte contra un tronco o una roca (obstaculos.lua).
        local o = self.datos.obstaculos
        if o and o.choques > d.choques then
            d.choques = o.choques
            if (d.velocidadAntes or 0) > CuerpoFisico.chocarDesde then
                aFisica(self, d, 'choque contra un tronco o una roca')
            end
        end
        d.velocidadAntes = self.velocidad
        -- Golpe de prueba.
        local e = os.getenv('BATALLA_ROBOT_EMPUJON')
        if e and not d.empujado then
            local cuando, fuerza = e:match('^([%d.]+):?([%d.]*)$')
            if tonumber(cuando) and d.reloj >= tonumber(cuando) then
                d.empujado = true
                local f = tonumber(fuerza) or CuerpoFisico.empujon
                local a = self.rumbo + math.pi / 2
                aFisica(self, d, string.format('golpe de lado de %.0f N·s', f), math.cos(a) * f, math.sin(a) * f)
            end
        end
        if d.modo == 'animado' then
            return
        end
    end
    -- En física: donde está y cómo va de verdad.
    local m = d.cuerpo:matriz('cuerpo')
    self.x, self.y = m[4], m[8]
    self.rumbo = math.atan2(m[5], m[1])
    self.velocidad, self.giro = d.cuerpo.velocidad, 0
    local c = d.cuerpo
    if d.faseAntes ~= c.fase then
        d.faseAntes = c.fase
        print(string.format('CUERPO FISICO %s: %s', self.datos.asalto and self.datos.asalto.nombre or '?', c.fase or '?'))
    end
    if c.fase == 'equilibrio' and not c.caido and math.abs(c.velocidad) < 0.4 and math.abs(c.inclinacion) < math.rad(5) and math.abs(c.lateral) < math.rad(5) then
        d.quieto = d.quieto + dt
        if d.quieto > CuerpoFisico.recuperado then
            aAnimacion(self, d)
            return
        end
    else
        d.quieto = 0
    end
    -- `CUERPO_TRAZA=1`: cada medio segundo, cómo va.
    if os.getenv('CUERPO_TRAZA') and math.floor(d.reloj * 2) ~= math.floor((d.reloj - dt) * 2) then
        local Mundo = require('batalla.robots.mundo')
        local c = d.cuerpo
        local rd, ri = c:matriz('ruedaDer'), c:matriz('ruedaIzq')
        print(string.format('TRAZA t=%.1f v %.2f incl %.1f° lado %.1f° cadera %.2f m sobre el suelo, ruedas %.2f %.2f, flexión %.2f %.2f', d.reloj, c.velocidad, math.deg(c.inclinacion), math.deg(c.lateral), m[12] - Mundo.altura(m[4], m[8]), rd[12] - Mundo.altura(rd[4], rd[8]), ri[12] - Mundo.altura(ri[4], ri[8]), c.lados.Der.flexion or 0, c.lados.Izq.flexion or 0))
        local p = c.piernas
        if p and p.Der then
            print(string.format('   animación: der doblar %.2f adelante %.2f abrir %.2f | izq doblar %.2f adelante %.2f abrir %.2f', p.Der.doblar, p.Der.adelante, p.Der.abrir, p.Izq.doblar, p.Izq.adelante, p.Izq.abrir))
        end
    end
    if d.cuerpo.caido and not d.avisoCaido then
        d.avisoCaido = true
        print(string.format('CUERPO FISICO %s SE HA CAÍDO a los %.1f s', self.datos.asalto and self.datos.asalto.nombre or '?', d.reloj))
    end
end

function CuerpoFisico.onPose(self)
    local d = self.datos.cuerpoFisico
    if not d.cuerpo or d.modo ~= 'fisico' then
        return
    end
    for _, n in ipairs(CuerpoFisico.piezas) do
        d.mundo[n] = PiezaRobot.multiplicar(d.cuerpo:matriz(n), d.ajuste[n])
    end
    -- La raíz, para que la pelvis quede donde está el cuerpo.
    self.raizFija = PiezaRobot.multiplicar(d.mundo.cuerpo, d.reposoPelvis)
    d.inversas = d.inversas or {}
    -- El torso, tal cual sobre la pelvis (el cuerpo físico es uno).
    d.mundo.torso = PiezaRobot.multiplicar(d.mundo.cuerpo, self:getPieza('torso').datos.matriz)
    for _, lado in ipairs({ 'Der', 'Izq' }) do
        local cadenas = {
            { 'cuerpo', 'muslo' .. lado, 'espinilla' .. lado, 'rueda' .. lado },
            { 'torso', 'brazo' .. lado, 'antebrazo' .. lado },
        }
        for _, cadena in ipairs(cadenas) do
            for k = 2, #cadena do
                local padre, hija = cadena[k - 1], cadena[k]
                local p = self:getPieza(CuerpoFisico.modelo[hija] or hija)
                d.inversas[padre] = inversa(d.mundo[padre], d.inversas[padre])
                p:setMatrizLocal(PiezaRobot.multiplicar(d.inversas[padre], d.mundo[hija]))
            end
        end
    end
    -- La animación de las piernas, para los motores (antes de borrarla del
    -- dibujo): cuánto dobla, adelanta y abre cada una.
    local ps = self.datos.piernasSoldado
    if ps then
        local phi, theta = (ps.inclinacion or 0) + (ps.vaiven or 0), ps.cabeceo or 0
        local piernas = d.cuerpo.piernas or {}
        for _, lado in ipairs({ 'Der', 'Izq' }) do
            local muslo = self:getPieza('muslo' .. lado).porClave
            local function angulo(capa)
                local c = muslo['piernasSoldado/' .. capa]
                return c and c.angulo or 0
            end
            piernas[lado] = piernas[lado] or {}
            local p = piernas[lado]
            p.doblar = -angulo('postura')
            p.adelante = -angulo('cabeceo') - theta
            p.abrir = angulo('curva') - phi
        end
        d.cuerpo.piernas = piernas
    end
    -- Lo que las piernas dibujadas hacían por su cuenta (agacharse, cabecear,
    -- girar las ruedas) ya lo hace la física: el dibujo, de ella.
    for _, n in ipairs(CuerpoFisico.dibujadas) do
        for _, c in ipairs(self:getPieza(n).capas) do
            c.angulo, c.x, c.y, c.z = 0, 0, 0, 0
        end
    end
end

Nucleo.registrarEspecializacion('cuerpoFisico', CuerpoFisico)
return CuerpoFisico

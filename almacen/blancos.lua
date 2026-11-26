-- Bloques enemigos de práctica para el soldado (el dueño, 18-nov: «ponle
-- bloques como enemigos y prográmale que dispare»). Son objetos del almacén
-- (GestorObjetos): los rayos de los ojos y el lidar los tocan como a todo lo
-- demás, y el soldado (robots/especializaciones/combate.lua) les dispara
-- cuando sus ojos los ven.
--
-- Cada bloque aguanta `Blancos.vida` balas; cada impacto lo sacude, y al
-- quedarse sin vida cae de lado (hacia donde iban las balas) como algo que
-- pesa. Al rato vuelve a estar de pie en su sitio (es práctica).
--
-- Modelo: assets/almacen/bloque_enemigo.glb (tools/blender/bloque_enemigo.py).

local dream = require('lib.3DreamEngine')
local PiezaRobot = require('robots.pieza')

local Blancos = {}

Blancos.vida = 30 -- balas
Blancos.reaparecer = 40 -- s caído antes de volver a estar de pie (con menos, el soldado no salía de la reserva: siempre había uno en pie)
Blancos.caida = 0.8 -- s que tarda en caer
Blancos.lado = 0.3 -- m del centro al canto (0,6 m de ancho)
-- Dónde están (x, y, rumbo): sitios libres (sin nada a menos de 1 m) a 3-6 m
-- del camino que hace el soldado al explorar desde la reserva hacia la
-- fábrica, para que se los encuentre; y uno en la reserva.
Blancos.sitios = {
    { -51.5, 19.0, 0.3 },
    { -58.0, 22.0, -0.4 },
    { -62.0, 16.0, 0.8 },
    { -66.5, 10.5, 0.2 },
    -- En la reserva, en fila delante de donde empieza el soldado (mirando
    -- a +x): a 13, 22 y 28 m, para la puntería de lejos.
    { -27.0, 24.3, 0.3 },
    { -18.0, 23.0, -0.4 },
    { -12.0, 24.2, 0.8 },
    -- Al fondo del pasillo de y = 25 (lo ve de lejos: ahí falla más).
    { -72.0, 25.0, 0.0 },
}

local lista = {}

local function multiplicar(a, b)
    return PiezaRobot.multiplicar(a, b)
end

-- Giro de `t` rad sobre el eje (kx, ky, 0) que pasa por (px, py, 0).
local function giroSobreCanto(px, py, kx, ky, t)
    local c, s = math.cos(t), math.sin(t)
    local C = 1 - c
    local r = {
        c + kx * kx * C, kx * ky * C, ky * s, 0,
        kx * ky * C, c + ky * ky * C, -kx * s, 0,
        -ky * s, kx * s, c, 0,
        0, 0, 0, 1,
    }
    local ida = { 1, 0, 0, px, 0, 1, 0, py, 0, 0, 1, 0, 0, 0, 0, 1 }
    local vuelta = { 1, 0, 0, -px, 0, 1, 0, -py, 0, 0, 1, 0, 0, 0, 0, 1 }
    return multiplicar(ida, multiplicar(r, vuelta))
end

--- Un impacto: resta vida y sacude; sin vida, empieza a caer hacia (dx, dy).
local function setDano(self, cantidad, _, _, _, dx, dy)
    if self.vida <= 0 then
        return
    end
    self.vida = self.vida - cantidad
    self.sacudida = 1
    self.empuje = { dx, dy }
    if self.vida <= 0 then
        local n = math.sqrt(dx * dx + dy * dy)
        n = n > 1e-6 and n or 1
        self.caer = { dx / n, dy / n, t = 0 }
        self.solido = false
        self.caido = 0
        -- Para los rayos (ojos, lidar, balas), ya tumbado: de su canto hacia
        -- donde cae, 1,5 m de largo y 0,6 de alto. Si no, seguiría tapando
        -- como si estuviera de pie lo que hay detrás.
        local m = self.matrizDePie
        local c, s = dx / n, dy / n
        local px, py = m[4] + c * Blancos.lado, m[8] + s * Blancos.lado
        self.matrizRayos = { c, -s, 0, px, s, c, 0, py, 0, 0, 1, 0, 0, 0, 0, 1 }
        self.cajasPropias = { { 0, -0.33, 0, 1.5, 0.33, 0.66 } }
    end
end

-- La torreta (robots/especializaciones/torreta.lua): x, y, rumbo. Delante
-- del soldado en la reserva, a 9 m, mirando hacia él.
Blancos.torreta = { -31.0, 23.0, math.pi }

--- La torreta y su cuerpo para los rayos (ojos, lidar, balas): un objeto
-- sin malla con sus cajas, enemigo, que pasa las balas a la torreta.
local function crearTorreta()
    local t = Blancos.torreta
    local robot = GestorRobots.crear('torreta', t[1], t[2], t[3])
    GestorObjetos.registrarTipo('torretaCuerpo', {
        nombre = 'torreta', movible = false, peso = 400, sinMalla = true,
        tamano = { 0.9, 0.9, 1.25 },
        cajas = { { -0.2, -0.2, 0, 0.2, 0.2, 0.72 }, { -0.32, -0.27, 0.72, 0.32, 0.27, 1.22 } },
        puntos = {},
    })
    local o = GestorObjetos.crear('torretaCuerpo', t[1], t[2], 0, t[3])
    o.enemigo = true
    o.solido = true
    o.altoBlanco = 1.0
    o.vida, o.vidaMax = robot:getVidaTorreta()
    o.setDano = function(self, cantidad)
        robot:setDanoTorreta(cantidad)
        self.vida = robot:getVidaTorreta()
    end
    robot.cuerpo = o
    Blancos.robotTorreta = robot
end

function Blancos.crear()
    lista = {}
    local modelo = dream:loadObject('assets/almacen/bloque_enemigo', { decodeBlenderNames = false })
    local malla = modelo.objects.bloque
    for _, m in pairs(malla.meshes or {}) do
        if m.material and m.material.name == 'bloqueVisera' then
            m.material:setEmissionFactor(6, 0.6, 0.3)
        end
    end
    GestorObjetos.setMallaExterna('bloqueEnemigo', malla)
    GestorObjetos.registrarTipo('bloqueEnemigo', {
        nombre = 'bloque enemigo', movible = false, peso = 120,
        tamano = { 0.6, 0.6, 1.5 },
        cajas = { { -0.33, -0.33, 0, 0.33, 0.33, 1.5 } },
        puntos = {},
    })
    for _, s in ipairs(Blancos.sitios) do
        local o = GestorObjetos.crear('bloqueEnemigo', s[1], s[2], 0, s[3])
        o.enemigo = true
        o.vida = Blancos.vida
        o.vidaMax = Blancos.vida
        o.altoBlanco = 0.9
        o.setDano = setDano
        -- De pie, los robots chocan con él (fisica.lua).
        o.solido = true
        o.matrizDePie = o:getMatriz()
        lista[#lista + 1] = o
    end
    crearTorreta()
end

--- ¿Hay algún robot a menos de 1,5 m de donde se levanta el bloque?
function Blancos.hayRobotCerca(o)
    local m = o.matrizDePie
    for _, r in ipairs(GestorRobots.getRobots()) do
        local x, y = r:getPosicion()
        if (x - m[4]) ^ 2 + (y - m[8]) ^ 2 < 1.5 ^ 2 then
            return true
        end
    end
    return false
end

function Blancos.actualizar(dt)
    local t = Blancos.robotTorreta
    if t then
        t.cuerpo.vida = t:getVidaTorreta()
    end
    for _, o in ipairs(lista) do
        local m = o.matrizDePie
        if o.caer then
            -- Cae como algo que pesa: cada vez más deprisa, hasta tumbado.
            local c = o.caer
            c.t = math.min(Blancos.caida, c.t + dt)
            local f = (c.t / Blancos.caida) ^ 2
            local x, y = m[4], m[8]
            local px, py = x + c[1] * Blancos.lado, y + c[2] * Blancos.lado
            -- Eje: horizontal, de lado a la caída (z × dirección).
            m = multiplicar(giroSobreCanto(px, py, -c[2], c[1], f * math.pi / 2), m)
            if c.t >= Blancos.caida then
                o.caido = o.caido + dt
                -- Se levanta cuando toca, si no hay ningún robot encima.
                if o.caido > Blancos.reaparecer and not Blancos.hayRobotCerca(o) then
                    o.caer = nil
                    o.matrizRayos, o.cajasPropias = nil, nil
                    o.solido = true
                    o.vida = Blancos.vida
                    m = o.matrizDePie
                end
            end
        elseif (o.sacudida or 0) > 0 then
            -- Cada impacto lo mueve un poco hacia donde iba la bala.
            o.sacudida = math.max(0, o.sacudida - dt * 10)
            local e = o.empuje
            local k = 0.012 * o.sacudida
            m = multiplicar({ 1, 0, 0, e[1] * k, 0, 1, 0, e[2] * k, 0, 0, 1, 0, 0, 0, 0, 1 }, m)
        end
        o:setMatriz(m)
    end
end

function Blancos.getBlancos()
    return lista
end

return Blancos

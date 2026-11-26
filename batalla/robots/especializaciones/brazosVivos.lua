-- Brazos y garras con vida (el dueño, 18-nov: «las manos están rígidas»).
-- Movimiento procedural con muelles, como las piernas (piernasSoldado.lua) y
-- como la animación procedural de Overgrowth (David Rosen, «Animation
-- Bootcamp», GDC 2014): pocas poses y muelles que las siguen, así nada cambia
-- de golpe.
--
--   * quieto: respira (hombros y codos suben y bajan un poco, lento);
--   * corriendo: los brazos se balancean al contrario que las piernas al
--     patinar; con la aceleración se quedan atrás (arranca) o se van delante
--     (frena), por la inercia; en las curvas se abren hacia fuera;
--   * garras: medio cerradas y relajadas; de vez en cuando se abren y cierran
--     un poco (cada una a su ritmo); frenando fuerte, se cierran.
--
-- El brazo que apunta (asalto.lua, hombroDer en combate) se mueve mucho
-- menos mientras apunta. Capas propias: se suman a lo que pongan los demás.

local Nucleo = require('robots.nucleo')

local Brazos = {}

Brazos.respirar = { 0.3, 0.08, 0.14 } -- Hz, rad de hombro, rad de codo
Brazos.balanceo = 0.35 -- rad de hombro al patinar a tope
Brazos.inercia = 0.05 -- rad de hombro por m/s² de aceleración
Brazos.inerciaMaxima = 0.35
Brazos.abrirCurva = 0.08 -- rad de hombro hacia fuera por m/s² de lado
Brazos.abrirMaximo = 0.3
Brazos.frecuencia = 2.2 -- Hz del muelle de los brazos
Brazos.amortiguacion = 0.35 -- algo de rebote: pesan
-- Garras: cierre de cada falange (1, 2, 3) por unidad de «cerrar».
Brazos.dedos = { 0.18, 0.45, 0.35 }
Brazos.garraRelajada = 0.35
Brazos.garraCada = { 1.2, 3.5 } -- s entre movimientos de cada garra
Brazos.garraMovimiento = 0.6 -- lo que se abre o cierra de más
Brazos.frenazo = 4 -- m/s² de frenada desde la que cierra las garras
-- Brazos caídos (el dueño, 18-nov: «las manos siguen hacia adelante, se ve
-- raro»): el modelo tiene los antebrazos hacia delante, que es la pose de
-- correr; quieto o despacio, los brazos cuelgan a los costados (hombro un
-- poco atrás, codo casi estirado hacia abajo) y vuelven adelante al correr.
Brazos.reposoHombro = 0.18
Brazos.reposoCodo = 1.1
Brazos.correrDesde = { 1.5, 4.5 } -- m/s: de brazos caídos a brazos delante
-- Postura de disparo (self.posturaDisparo): brazos abiertos y algo atrás,
-- separados del cuerpo, garras cerradas como puños; con el retroceso se
-- sacuden un poco.
Brazos.disparoAbrir = 0.32 -- rad de hombro hacia fuera
Brazos.disparoAtras = 0.12 -- rad de hombro hacia atrás
Brazos.disparoCodo = -0.35 -- rad: el codo algo doblado (garra hacia delante)
Brazos.disparoGarra = 0.9 -- cierre de la garra

local LADOS = { 'Der', 'Izq' }

local function limitar(v, a, b)
    return math.max(a, math.min(b, v))
end

local function muelle(x, v, objetivo, dt, frecuencia, amortiguacion)
    local w = 2 * math.pi * frecuencia
    v = v + (-w * w * (x - objetivo) - 2 * amortiguacion * w * v) * dt
    return x + v * dt, v
end

function Brazos.prerequisitos(self)
    return self:getTienePieza('hombroDer') and self:getTienePieza('codoDer')
end

function Brazos.onLoad(self)
    local d = self.datos.brazosVivos
    d.reloj = love.math.random() * 10
    d.antes = 0
    d.acel = 0
    d.brazo = {}
    d.garra = {}
    d.caidos = 1
    for _, s in ipairs(LADOS) do
        d.brazo[s] = { y = 0, vy = 0, x = 0, vx = 0 }
        local dedos = {}
        for _, letra in ipairs({ 'A', 'B', 'C' }) do
            for i = 1, 3 do
                local p = self.piezas['dedo' .. letra .. i .. s]
                if p then
                    dedos[#dedos + 1] = { pieza = p, k = Brazos.dedos[i] }
                end
            end
        end
        d.garra[s] = {
            dedos = dedos,
            cerrar = Brazos.garraRelajada, v = 0,
            objetivo = Brazos.garraRelajada,
            espera = 1 + love.math.random() * Brazos.garraCada[2],
        }
    end
end

function Brazos.onUpdate(self, dt)
    local d = self.datos.brazosVivos
    if dt <= 0 then
        return
    end
    d.reloj = d.reloj + dt
    local v, w = self.velocidad or 0, self.giro or 0
    local a = (v - d.antes) / dt
    d.antes = v
    d.acel = d.acel + (a - d.acel) * math.min(1, dt * 6)
    local p = self.datos.piernasSoldado
    local patinar, fase = p and p.patinar or 0, p and p.fase or 0
    local apuntando = self.datos.asalto and self.datos.asalto.estado == 'combate'
    local lateral = v * w
    -- Brazos caídos según la velocidad (suave).
    local C = Brazos.correrDesde
    local quiereCaidos = 1 - limitar((math.abs(v) - C[1]) / (C[2] - C[1]), 0, 1)
    d.caidos = d.caidos + (quiereCaidos - d.caidos) * math.min(1, dt * 3)
    local pasos = math.max(1, math.ceil(dt / 0.005))
    local h = dt / pasos
    for _, s in ipairs(LADOS) do
        local lado = s == 'Izq' and 1 or -1
        -- Hombro adelante (−) y atrás (+), como el giro y del modelo: «lleva
        -- el pie atrás» en las piernas, aquí lleva la mano atrás.
        -- Al patinar, contrario a la pierna de su lado (la izquierda va
        -- delante con sin(fase) > 0: el brazo izquierdo, atrás).
        local objetivoY = Brazos.balanceo * patinar * math.sin(fase) * lado
            + limitar(Brazos.inercia * d.acel, -Brazos.inerciaMaxima, Brazos.inerciaMaxima)
        -- En las curvas, el brazo de fuera se abre (x positivo lleva a +y).
        local fuera = (lado * w) < 0
        local objetivoX = fuera and -lado * limitar(Brazos.abrirCurva * math.abs(lateral), 0, Brazos.abrirMaximo) or 0
        if apuntando and s == 'Der' then
            objetivoY, objetivoX = objetivoY * 0.15, 0
        end
        local b = d.brazo[s]
        for _ = 1, pasos do
            b.y, b.vy = muelle(b.y, b.vy, objetivoY, h, Brazos.frecuencia, Brazos.amortiguacion)
            b.x, b.vx = muelle(b.x, b.vx, objetivoX, h, Brazos.frecuencia, Brazos.amortiguacion)
        end
        -- Garras: de vez en cuando, un poco más abiertas o cerradas.
        local g = d.garra[s]
        g.espera = g.espera - dt
        if g.espera <= 0 then
            g.espera = Brazos.garraCada[1] + love.math.random() * (Brazos.garraCada[2] - Brazos.garraCada[1])
            g.objetivo = Brazos.garraRelajada + (love.math.random() * 2 - 1) * Brazos.garraMovimiento
        end
        local objetivo = g.objetivo
        if -d.acel > Brazos.frenazo then
            objetivo = 1
        end
        for _ = 1, pasos do
            g.cerrar, g.v = muelle(g.cerrar, g.v, objetivo, h, 3, 0.7)
        end
    end
end

function Brazos.onPose(self)
    local d = self.datos.brazosVivos
    local R = Brazos.respirar
    local r = math.sin(d.reloj * 2 * math.pi * R[1])
    local apuntando = self.datos.asalto and self.datos.asalto.estado == 'combate'
    for _, s in ipairs(LADOS) do
        local b = d.brazo[s]
        local k = (apuntando and s == 'Der') and 0.2 or 1
        local hombro, codo = self:getPieza('hombro' .. s), self:getPieza('codo' .. s)
        -- El brazo del arma de asalto, en combate, no cuelga.
        local caidos = (apuntando and s == 'Der') and 0 or d.caidos
        local disparo = (self.posturaDisparo or 0) * d.caidos
        local sacudida = 0.15 * (self.retrocesoDisparo or 0)
        local lado = s == 'Izq' and 1 or -1
        if hombro then
            hombro:setGiro('y', b.y + R[2] * r * k + Brazos.reposoHombro * caidos + (Brazos.disparoAtras + sacudida) * disparo, 'vivo')
            hombro:setGiro('x', b.x + lado * Brazos.disparoAbrir * disparo, 'abrir')
        end
        if codo then
            codo:setGiro('y', -R[3] * r * k + Brazos.reposoCodo * caidos + Brazos.disparoCodo * disparo, 'vivo')
        end
        local g = d.garra[s]
        -- Respecto a la pose del modelo (la garra a medio cerrar).
        local disparoG = (self.posturaDisparo or 0) * d.caidos
        local c = g.cerrar + (Brazos.disparoGarra - g.cerrar) * disparoG - Brazos.garraRelajada
        for _, dedo in ipairs(g.dedos) do
            dedo.pieza:setGiro('y', dedo.k * c, 'vivo')
        end
    end
end

Nucleo.registrarEspecializacion('brazosVivos', Brazos)
return Brazos

-- Combate del robot soldado (el dueño, 18-nov: «ponle bloques como enemigos y
-- prográmale que dispare; tiene que verlos con los mismos rayos azules y
-- dispararles»). Solo dispara a lo que han tocado sus ojos (mirada.lua): los
-- rayos azules. Entonces:
--
-- 0. Vigila: cuando su lidar nota algo que no ha mirado (a menos de
--    `vigilar` m), vuelve la cabeza hacia allí para que los ojos comprueben
--    qué es. El lidar solo dice «ahí hay algo»; quien reconoce al enemigo
--    son los ojos. Y si no hay nada que comprobar, barre con la mirada de
--    lado a lado como un centinela, despacio para que el rayo de los ojos
--    pase por todas las direcciones (llegan a 30 m, el lidar a 12): así ve
--    también a los enemigos lejanos.
-- 1. Deja lo que hacía (explorar, practicar) y se para.
-- 2. Fija la mirada en el enemigo (cabeza y ojos) y gira el cuerpo hacia él.
-- 3. Apunta la metralleta con un lazo cerrado: cada cuadro compara hacia
--    dónde apuntan de verdad los cañones con la línea de la boca al
--    enemigo y corrige el hombro (así no importa que el arma vaya a un lado
--    del cuerpo).
-- 4. Ráfagas: el tambor de cañones acelera, dispara 15 balas por segundo
--    con un poco de dispersión, cada bala es un rayo contra el mundo de la
--    escena (Robot:getRayoMundo) y el retroceso sacude el brazo. Si no ve al
--    enemigo (algo se cruza), deja de disparar.
-- 5. Cuando lo destruye, lo mira un momento y vuelve a lo suyo.
--
-- Lo que se ve (trazadoras, fogonazo, chispas) lo dibuja la escena con
-- Robot:getDisparos() y Robot:getFogonazo().
--
-- Un objeto es enemigo si `objeto.enemigo` y `objeto.vida > 0`; recibe las
-- balas con `objeto:setDano(1, x, y, z, dx, dy, dz)`.

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local Combate = {}
local vigilar

Combate.cadencia = 15 -- balas por segundo
Combate.rafaga = { 0.55, 0.9 } -- s disparando
Combate.pausaRafaga = { 0.25, 0.45 } -- s entre ráfagas
Combate.arranqueTambor = 0.25 -- s que tarda el tambor en coger vueltas
Combate.giroTambor = 40 -- rad/s a tope
-- Dispersión (el dueño, 18-nov: «que según su distancia acierte menos; de
-- cerca, obviamente, pega mejor»): cada bala se desvía al azar (normal, en
-- los dos ejes) con una desviación que crece con la distancia al enemigo
-- (el arma vibra, el blanco se ve más pequeño y cuesta más afinar). Con un
-- bloque de 0,6 m (calculado): a 5 m casi todas; a 10 m tres de cada cuatro;
-- a 15 m la mitad; a 20 m una de cada tres; a 25 m una de cada cuatro.
Combate.dispersion = math.rad(1.2) -- rad de desviación a 0 m
Combate.dispersionPorMetro = math.rad(0.09) -- rad de más por cada metro
Combate.dispersionMaxima = math.rad(5)
Combate.alcance = 40
Combate.apuntado = math.rad(6) -- error con el que ya dispara (con 3°, si le daban y se torcía, dejaba de disparar)
Combate.perder = 2.5 -- s sin verlo: lo deja
Combate.confirmar = 1.2 -- s mirándolo tras destruirlo
Combate.ladoMax = math.rad(35) -- lo que gira el hombro a los lados
Combate.arribaMax = math.rad(40)
Combate.trazadora = 0.07 -- s que se ve cada bala
Combate.distanciaMinima = 2.5 -- m: más cerca, retrocede antes de disparar
Combate.boca = 0.32 -- m del eje del tambor a la boca de los cañones
Combate.vigilar = 25 -- m: lo que nota el lidar más cerca que esto, lo comprueba con los ojos
Combate.comprobar = 0.8 -- s mirando cada cosa que comprueba
Combate.olvidar = 15 -- s: pasado esto, lo vuelve a comprobar
Combate.barrerAngulo = math.rad(75) -- lo más a un lado que mira
Combate.barrerRapidez = math.rad(20) -- rad/s del barrido (a 15 rayos/s: 1,3° entre rayo y rayo)
Combate.barrerLejos = 25 -- m del punto que mira al barrer
Combate.barrerAltura = 1.1 -- m de ese punto (el rayo cruza un robot de pie a cualquier distancia)

function Combate:prerequisitos()
    return self:getTienePieza('canones')
end

function Combate:onLoad()
    local d = self.datos.combate
    d.estado = 'buscar'
    d.lado, d.arriba = 0, 0
    d.tambor, d.vTambor = 0, 0
    d.retroceso = 0
    d.disparos = {} -- { x0, y0, z0, x1, y1, z1, t, toca }
    d.chispas = {}
    d.reloj = 0
    d.bajas = 0
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function centroDe(objeto)
    local x, y = objeto:getPosicion()
    local m = objeto:getMatriz()
    return x, y, m[12] + (objeto.altoBlanco or 0.9)
end

--- ¿Lo tocan ahora los rayos de los ojos?
local function loVen(self, objeto)
    for _, o in ipairs(self.getOjos and self:getOjos() or {}) do
        if o.objeto == objeto then
            return true
        end
    end
    return false
end

--- Un enemigo vivo que tocan los ojos ahora.
local function enemigoALaVista(self)
    for _, o in ipairs(self.getOjos and self:getOjos() or {}) do
        local e = o.objeto
        if e and e.enemigo and (e.vida or 0) > 0 then
            return e
        end
    end
end

--- Lo que nota el lidar y no ha comprobado con los ojos: lo mira.
vigilar = function(self, d)
    d.comprobado = d.comprobado or {}
    if d.comprobando then
        if d.reloj < d.comprobando.hasta then
            return
        end
        d.comprobando = nil
        self:setFoco(nil)
    end
    if not self.getRayos then
        return
    end
    local mejor, mejorDistancia
    for _, r in ipairs(self:getRayos()) do
        local o = r.objeto
        if o and r.choca and r.distancia < Combate.vigilar and (o.vida or 1) > 0
            and (not d.comprobado[o] or d.reloj - d.comprobado[o] > Combate.olvidar) then
            if not mejorDistancia or r.distancia < mejorDistancia then
                mejor, mejorDistancia = r, r.distancia
            end
        end
    end
    if mejor then
        local o = mejor.objeto
        d.comprobado[o] = d.reloj
        local x, y = o:getPosicion()
        local m = o:getMatriz()
        d.comprobando = { hasta = d.reloj + Combate.comprobar }
        self:setFoco(x, y, m[12] + (o.altoBlanco or 0.5), o, true)
    else
        -- Barrido de lado a lado (diente de sierra de ida y vuelta).
        d.barrido = (d.barrido or 0) + Combate.barrerRapidez * (d.dt or 0)
        local vuelta = 4 * Combate.barrerAngulo
        local f = d.barrido % vuelta
        local a = f < vuelta / 2 and (f - Combate.barrerAngulo) or (3 * Combate.barrerAngulo - f)
        a = self.rumbo + a
        self:setFoco(self.x + math.cos(a) * Combate.barrerLejos, self.y + math.sin(a) * Combate.barrerLejos, Combate.barrerAltura, nil, true)
    end
end

local function dejarLoQueHacia(self)
    if self.getExplorando and self:getExplorando() then
        self:setExplorar(false)
        self.datos.combate.volverAExplorar = true
    end
    local nav = self.datos.navegacion
    if nav then
        nav.destino, nav.ruta = nil, nil
    end
    self:setParar()
end

local function volverALoSuyo(self, d)
    d.estado = 'buscar'
    d.comprobando = nil
    self:setFoco(nil)
    d.objetivo = nil
    self:setMirarA(nil)
    if d.volverAExplorar then
        d.volverAExplorar = false
        self:setExplorar(true)
    end
end

-- La boca de los cañones y hacia dónde apuntan (del tambor).
local function boca(self)
    local canones = self:getPieza('canones')
    local m = canones:getMatriz()
    if not m then
        return nil
    end
    local x, y, z = canones:getPunto(Combate.boca, 0, 0)
    return x, y, z, m[1], m[5], m[9]
end

local function disparar(self, d, objetivo)
    local bx, by, bz, gx, gy, gz = boca(self)
    if not bx then
        return
    end
    -- Hacia donde apunta el arma, desviada al azar: más cuanto más lejos.
    local distancia = 10
    if objetivo then
        local ox, oy = objetivo:getPosicion()
        distancia = math.sqrt((ox - bx) ^ 2 + (oy - by) ^ 2)
    end
    local sigma = math.min(Combate.dispersionMaxima, Combate.dispersion + Combate.dispersionPorMetro * distancia)
    local r = math.abs(love.math.randomNormal(sigma, 0))
    local a = love.math.random() * 2 * math.pi
    local ux, uy, uz = -gy, gx, 0
    local n = math.sqrt(ux * ux + uy * uy)
    if n < 1e-6 then
        ux, uy, n = 0, 1, 1
    end
    ux, uy = ux / n, uy / n
    local vx, vy, vz = gy * uz - gz * uy, gz * ux - gx * uz, gx * uy - gy * ux
    local dx = gx + (ux * math.cos(a) + vx * math.sin(a)) * r
    local dy = gy + (uy * math.cos(a) + vy * math.sin(a)) * r
    local dz = gz + (uz * math.cos(a) + vz * math.sin(a)) * r
    local dist, tipo, objeto = self:getRayoMundo(bx, by, bz, dx, dy, dz, Combate.alcance)
    dist = dist or Combate.alcance
    local n2 = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / n2, dy / n2, dz / n2
    local hx, hy, hz = bx + dx * dist, by + dy * dist, bz + dz * dist
    d.disparos[#d.disparos + 1] = { bx, by, bz, hx, hy, hz, t = 0, toca = tipo ~= nil }
    if tipo then
        d.chispas[#d.chispas + 1] = { hx, hy, hz, t = 0, enemigo = objeto ~= nil and objeto.enemigo }
    end
    if objetivo then
        d.tiros = (d.tiros or 0) + 1
        if objeto == objetivo then
            d.aciertos = (d.aciertos or 0) + 1
        end
    end
    if objeto and objeto.setDano then
        objeto:setDano(1, hx, hy, hz, dx, dy, dz)
        if objeto.vida <= 0 and objeto == objetivo then
            d.bajas = d.bajas + 1
            print(string.format('SOLDADO t=%.1f s destruido %s (%d) a %.1f m: %d aciertos de %d balas (%d %%)', d.reloj, objeto:getNombre(), d.bajas, math.sqrt((hx - self.x) ^ 2 + (hy - self.y) ^ 2), d.aciertos, d.tiros, math.floor(100 * d.aciertos / d.tiros + 0.5)))
        end
    end
    d.retroceso = 1
    d.fogonazo = 0.05
    d.balas = (d.balas or 0) + 1
end

function Combate:onUpdate(dt)
    local d = self.datos.combate
    d.reloj = d.reloj + dt
    d.dt = dt
    -- Lo que se ve se apaga.
    for _, lista in ipairs({ d.disparos, d.chispas }) do
        for k = #lista, 1, -1 do
            lista[k].t = lista[k].t + dt
            if lista[k].t > (lista == d.chispas and 0.25 or Combate.trazadora) then
                table.remove(lista, k)
            end
        end
    end
    d.fogonazo = math.max(0, (d.fogonazo or 0) - dt)
    d.retroceso = math.max(0, d.retroceso - dt * 14)
    local quiereDisparar = false

    if d.estado == 'buscar' then
        vigilar(self, d)
        local e = enemigoALaVista(self)
        if e then
            d.objetivo = e
            d.estado = 'apuntar'
            d.visto = d.reloj
            d.rafaga, d.pausa = 0, 0.15
            d.tiros, d.aciertos = 0, 0
            dejarLoQueHacia(self)
            local ex, ey = e:getPosicion()
            print(string.format('SOLDADO t=%.1f s veo %s a %.1f m: apunto', d.reloj, e:getNombre(), math.sqrt((ex - self.x) ^ 2 + (ey - self.y) ^ 2)))
        end
    elseif d.estado == 'apuntar' then
        local e = d.objetivo
        local tx, ty, tz = centroDe(e)
        self:setMirarA(tx, ty, tz)
        if loVen(self, e) then
            d.visto = d.reloj
        end
        if e.vida <= 0 then
            d.estado = 'confirmar'
            d.hasta = d.reloj + Combate.confirmar
        elseif d.reloj - d.visto > Combate.perder then
            print('SOLDADO lo he perdido de vista')
            volverALoSuyo(self, d)
        else
            -- El cuerpo, hacia él; demasiado cerca, primero se aparta
            -- marcha atrás (con el arma encima no se puede apuntar).
            local rumbo = math.atan2(ty - self.y, tx - self.x)
            local fuera = angulo(rumbo - self.rumbo)
            local cerca = math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)
            local retrocediendo = self.datos.conduccion.retroceso ~= nil
            if cerca < Combate.distanciaMinima and math.abs(fuera) < math.rad(30) then
                if not retrocediendo then
                    self:setRetroceder(Combate.distanciaMinima - cerca + 0.3)
                end
            elseif not retrocediendo and math.abs(fuera) > math.rad(4) then
                self:setIrA(self.x, self.y, rumbo)
            end
            -- El brazo: lazo cerrado sobre hacia dónde apuntan los cañones.
            local bx, by, bz, gx, gy, gz = boca(self)
            if bx then
                local ux, uy, uz = tx - bx, ty - by, tz - bz
                local horizontal = math.sqrt(ux * ux + uy * uy)
                local errorLado = angulo(math.atan2(uy, ux) - math.atan2(gy, gx))
                local errorArriba = math.atan2(uz, horizontal) - math.atan2(gz, math.sqrt(gx * gx + gy * gy))
                local k = math.min(1, dt * 10)
                d.lado = math.max(-Combate.ladoMax, math.min(Combate.ladoMax, d.lado + errorLado * k))
                d.arriba = math.max(-Combate.arribaMax, math.min(Combate.arribaMax, d.arriba + errorArriba * k))
                d.error = math.sqrt(errorLado ^ 2 + errorArriba ^ 2)
                -- Ráfagas mientras está apuntado y lo ve.
                local apuntado = d.error < Combate.apuntado and d.reloj - d.visto < 0.3
                if d.pausa > 0 then
                    d.pausa = d.pausa - dt
                    if d.pausa <= 0 then
                        d.rafaga = Combate.rafaga[1] + love.math.random() * (Combate.rafaga[2] - Combate.rafaga[1])
                    end
                elseif apuntado then
                    quiereDisparar = true
                    d.rafaga = d.rafaga - dt
                    if d.rafaga <= 0 then
                        d.pausa = Combate.pausaRafaga[1] + love.math.random() * (Combate.pausaRafaga[2] - Combate.pausaRafaga[1])
                    end
                end
            end
        end
    elseif d.estado == 'confirmar' then
        if d.reloj > d.hasta then
            print('SOLDADO objetivo destruido: vuelvo a lo mío')
            volverALoSuyo(self, d)
        end
    end
    if d.estado ~= 'apuntar' then
        -- El brazo vuelve a su sitio.
        local k = math.min(1, dt * 3)
        d.lado, d.arriba = d.lado * (1 - k), d.arriba * (1 - k)
    end

    if os.getenv('COMBATE_DEPURAR') and d.estado ~= 'buscar' then
        d.relojDepurar = (d.relojDepurar or 0) + dt
        if d.relojDepurar > 0.5 then
            d.relojDepurar = 0
            print(string.format('COMBATE x=%.2f y=%.2f v=%.2f %s error=%.1f° lado=%.1f° arriba=%.1f° visto=%.1fs tambor=%.0f balas=%d pausa=%.2f rafaga=%.2f', self.x, self.y, self.velocidad, d.estado, math.deg(d.error or -1), math.deg(d.lado), math.deg(d.arriba), d.reloj - (d.visto or 0), d.vTambor, d.balas or 0, d.pausa or 0, d.rafaga or 0))
        end
    end
    -- El tambor: acelera al disparar, frena al soltar; dispara cuando gira.
    local objetivoTambor = quiereDisparar and Combate.giroTambor or 0
    local acel = Combate.giroTambor / Combate.arranqueTambor
    d.vTambor = d.vTambor + math.max(-acel * dt * 0.5, math.min(acel * dt, objetivoTambor - d.vTambor))
    d.tambor = d.tambor + d.vTambor * dt
    if quiereDisparar and d.vTambor > Combate.giroTambor * 0.8 then
        d.cuenta = (d.cuenta or 0) + dt * Combate.cadencia
        while d.cuenta >= 1 do
            d.cuenta = d.cuenta - 1
            disparar(self, d, d.objetivo)
        end
    else
        d.cuenta = 0
    end
end

function Combate:onPose()
    local d = self.datos.combate
    local hombro = self:getPieza('hombroDer')
    -- Girar en z positivo lleva el arma a la izquierda; en y negativo, arriba.
    -- El retroceso la levanta y la echa atrás un poco en cada bala.
    -- (Una capa por eje: cada capa guarda un solo giro.)
    hombro:setGiro('z', d.lado, 'apuntarLado')
    hombro:setGiro('y', -d.arriba - 0.035 * d.retroceso * love.math.random(), 'apuntarArriba')
    self:getPieza('canones'):setGiro('x', d.tambor, 'tambor')
end

--- Le han disparado desde cerca de (x, y, z): si no está peleando, mira
-- hacia allí con los ojos para ver quién es.
function Robot:setAtacadoDesde(x, y, z)
    local d = self.datos.combate
    if not d or d.estado ~= 'buscar' then
        return
    end
    if d.comprobando and d.comprobando.atacado and d.reloj < d.comprobando.hasta then
        return
    end
    d.comprobando = { hasta = d.reloj + 1.5, atacado = true }
    self:setFoco(x, y, z, nil, true)
end

--- `true` mientras pelea (apunta, dispara o confirma la baja).
function Robot:getCombatiendo()
    local d = self.datos.combate
    return d ~= nil and d.estado ~= 'buscar'
end

--- El enemigo al que apunta (nil si ninguno).
function Robot:getObjetivo()
    local d = self.datos.combate
    return d and d.objetivo
end

--- Lo que se ve de los disparos: trazadoras { x0, y0, z0, x1, y1, z1, t }
-- y chispas { x, y, z, t, enemigo }; con la duración de cada cosa.
function Robot:getDisparos()
    -- (La torreta guarda lo mismo: robots/especializaciones/torreta.lua.)
    local d = self.datos.combate or self.datos.torreta
    if not d then
        return nil
    end
    return d.disparos, d.chispas, Combate.trazadora
end

--- Fogonazo en la boca: x, y, z y fuerza (0..1); nil si no dispara.
function Robot:getFogonazo()
    local d = self.datos.combate or self.datos.torreta
    if not d or (d.fogonazo or 0) <= 0 then
        return nil
    end
    if d.fogonazoPunto then
        local p = d.fogonazoPunto
        return p[1], p[2], p[3], d.fogonazo / 0.05
    end
    local x, y, z = boca(self)
    return x, y, z, d.fogonazo / 0.05
end

--- Balas disparadas y enemigos destruidos.
function Robot:getBalas()
    local d = self.datos.combate
    return d and d.balas or 0, d and d.bajas or 0
end

Nucleo.registrarEspecializacion('combate', Combate)
return Combate

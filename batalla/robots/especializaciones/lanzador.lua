-- Lanzamisiles del robot (el dueño, 18-nov): la cabeza se convierte pieza a
-- pieza en un cañón hueco con engranajes que giran dentro, el ojo de la mira
-- se pone rojo y tira un láser donde va a dar el misil, y dispara misiles
-- guiados por ese láser. Modelo: tools/blender/robot_lanzamisiles.py; las
-- dos formas de cada pieza, en assets/batalla/robots/lanzamisiles_canon.lua.
--
-- Va detrás de `asalto`, que es quien corre, busca al enemigo y gira el
-- torso y la cabeza hacia él; este script hace lo demás:
--   1. Lo ve: arma el cañón (la cabeza se deshace pieza a pieza; del
--      cargador de la espalda salen el tubo, los tramos y la mira).
--   2. Armado: el ojo se pone rojo, los engranajes giran, el láser marca y
--      el cañón sube o baja hasta apuntarle (lazo cerrado, como la metralleta).
--   3. Apuntado y cargado: misil. Sale del tubo, abre aletas y sigue el
--      punto del láser hasta que choca (con el robot, el suelo, un árbol).
--   4. Si lo pierde de vista unos segundos, vuelve a ser cabeza.
--
-- Los misiles se dibujan en 3D (assets/batalla/robots/misil.glb); el láser,
-- la estela y las explosiones, encima (batalla/robots/vista.lua).

local dream = require('lib.3DreamEngine')
local Nucleo = require('robots.nucleo')
local Mundo = require('batalla.robots.mundo')
local Robot = Nucleo.Robot

local Lanzador = {}

Lanzador.datos = 'assets/batalla/robots/lanzamisiles_canon.lua'
-- Lanza solo el proyectil (el dueño, 18-nov: «como la bala de un AK-47 pero
-- en grande»): un obús de 4 cm, pequeño pero fuerte.
Lanzador.modeloMisil = 'assets/batalla/robots/proyectil'
Lanzador.armarSiVe = 0.4 -- s que lleva viéndolo para armar el cañón
Lanzador.desarmarTras = 5 -- s sin verlo para volver a ser cabeza
Lanzador.alcance = 160 -- m
Lanzador.distanciaMinima = 8 -- m: más cerca no dispara (le daría a él)
Lanzador.apuntado = math.rad(4)
Lanzador.recarga = 4 -- s entre misiles
-- Ciclo (el dueño, 18-nov: «que dispare cada cierto tiempo, que saque el cañón
-- y se vuelva a convertir en cabeza»): tras una ráfaga de misiles guarda el
-- cañón y vuelve a ser cabeza un rato; si sigue viéndolo, lo saca otra vez.
Lanzador.rafaga = 2 -- misiles antes de guardar el cañón
Lanzador.descanso = { 4, 7 } -- s como cabeza entre ráfagas
Lanzador.cargar = 0.8 -- s con los engranajes a tope antes de que salga
Lanzador.arribaMax = math.rad(25)
Lanzador.ladoMax = math.rad(35) -- lo que el cañón corrige de lado sobre la cabeza
Lanzador.giroEngranajes = 1 -- veces su velocidad de Blender, en reposo armado
Lanzador.giroCargando = 4
Lanzador.velocidadSalida = 55 -- m/s: sale disparado del acelerador
Lanzador.velocidadMaxima = 60 -- que se le vea volar
Lanzador.aceleracion = 20
Lanzador.giroMisil = 2.5 -- rad/s que puede corregir el rumbo
Lanzador.vidaMisil = 5 -- s
Lanzador.fuerza = 6 -- empujón del proyectil (una bala es 1)
-- Impacto: humo (el dueño, 18-nov: «que sea humo, más puro humo»), sin
-- fuego; y el misil, sin llama: solo su estela de humo.
Lanzador.explosion = 4 -- s que dura la nube
Lanzador.bocanadas = 26
Lanzador.estela = 1.8 -- s que dura cada bocanada de la estela
Lanzador.rojo = { 1.0, 0.04, 0.02 }

local function suave(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Cuaterniones (w, x, y, z) y matrices 4x4 por filas -------------------------

local function aCuaternion(m)
    local r00, r01, r02 = m[1], m[2], m[3]
    local r10, r11, r12 = m[5], m[6], m[7]
    local r20, r21, r22 = m[9], m[10], m[11]
    local t = r00 + r11 + r22
    if t > 0 then
        local s = math.sqrt(t + 1) * 2
        return { 0.25 * s, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s }
    elseif r00 > r11 and r00 > r22 then
        local s = math.sqrt(1 + r00 - r11 - r22) * 2
        return { (r21 - r12) / s, 0.25 * s, (r01 + r10) / s, (r02 + r20) / s }
    elseif r11 > r22 then
        local s = math.sqrt(1 + r11 - r00 - r22) * 2
        return { (r02 - r20) / s, (r01 + r10) / s, 0.25 * s, (r12 + r21) / s }
    end
    local s = math.sqrt(1 + r22 - r00 - r11) * 2
    return { (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, 0.25 * s }
end

local function slerp(a, b, t)
    local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
    local bb = b
    if d < 0 then
        d = -d
        bb = { -b[1], -b[2], -b[3], -b[4] }
    end
    local ka, kb
    if d > 0.9995 then
        ka, kb = 1 - t, t
    else
        local th = math.acos(d)
        local s = math.sin(th)
        ka, kb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
    end
    local q = { a[1] * ka + bb[1] * kb, a[2] * ka + bb[2] * kb, a[3] * ka + bb[3] * kb, a[4] * ka + bb[4] * kb }
    local n = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
    return { q[1] / n, q[2] / n, q[3] / n, q[4] / n }
end

local function producto(a, b)
    return {
        a[1] * b[1] - a[2] * b[2] - a[3] * b[3] - a[4] * b[4],
        a[1] * b[2] + a[2] * b[1] + a[3] * b[4] - a[4] * b[3],
        a[1] * b[3] - a[2] * b[4] + a[3] * b[1] + a[4] * b[2],
        a[1] * b[4] + a[2] * b[3] - a[3] * b[2] + a[4] * b[1],
    }
end

local function matriz(p, q, e)
    local w, x, y, z = q[1], q[2], q[3], q[4]
    return {
        (1 - 2 * (y * y + z * z)) * e, 2 * (x * y - w * z) * e, 2 * (x * z + w * y) * e, p[1],
        2 * (x * y + w * z) * e, (1 - 2 * (x * x + z * z)) * e, 2 * (y * z - w * x) * e, p[2],
        2 * (x * z - w * y) * e, 2 * (y * z + w * x) * e, (1 - 2 * (x * x + y * y)) * e, p[3],
        0, 0, 0, 1,
    }
end

-- Carga ------------------------------------------------------------------------

local datosCanon -- lanzamisiles_canon.lua, una vez
local modeloMisil

local function cargarMisil()
    if modeloMisil then
        return modeloMisil
    end
    modeloMisil = dream:loadObject(Lanzador.modeloMisil, { decodeBlenderNames = false })
    for _, o in pairs(modeloMisil.objects) do
        for _, malla in pairs(o.meshes or {}) do
            local mat = malla.material
            local base = mat and mat.name and mat.name:match('^[^%.]+')
            if base and dream.materialLibrary[base] then
                malla.material = dream.materialLibrary[base]
            elseif base == 'misilSensor' then
                mat:setEmissionFactor(6, 6, 6)
            end
        end
    end
    -- Sin llama: solo humo.
    if modeloMisil.objects.llamaMisil then
        for _, malla in pairs(modeloMisil.objects.llamaMisil.meshes or {}) do
            malla:setVisible(false)
        end
    end
    return modeloMisil
end

function Lanzador:prerequisitos()
    return self:getTienePieza('anima') and self:getTieneEspecializacion('asalto')
end

function Lanzador:onLoad()
    local d = self.datos.lanzador
    if not datosCanon then
        datosCanon = love.filesystem.load(Lanzador.datos)()
        for _, p in ipairs(datosCanon.piezas) do
            p.qa, p.qb = aCuaternion(p.cabeza), aCuaternion(p.canon)
            p.pa = { p.cabeza[4], p.cabeza[8], p.cabeza[12] }
            p.pb = { p.canon[4], p.canon[8], p.canon[12] }
            local c, z = datosCanon.centroCabeza, datosCanon.ejeZ
            local fx = (p.pa[1] - c[1])
            local fy = (p.pa[2] - c[2]) + p.pb[2]
            local fz = (p.pa[3] - c[3]) + (p.pb[3] - z)
            local n = math.max(1e-6, math.sqrt(fx * fx + fy * fy + fz * fz))
            p.control = {
                (p.pa[1] + p.pb[1]) / 2 + fx / n * 0.12,
                (p.pa[2] + p.pb[2]) / 2 + fy / n * 0.12,
                (p.pa[3] + p.pb[3]) / 2 + fz / n * 0.12 + 0.06,
            }
        end
    end
    d.canon = datosCanon
    d.forma, d.quiere = 0, 0
    d.fase, d.vGiro = 0, 0
    d.arriba, d.lado = 0, 0
    d.recarga, d.carga = 0, 0
    d.misiles, d.explosiones = {}, {}
    d.disparados, d.aciertos = 0, 0
    d.estado = 'cabeza'
    d.reloj = 0
    -- Lo que brilla en el ojo de la mira (materiales mira_*: su color
    -- de antes, para volver a él).
    d.mira = {}
    for _, o in pairs(self.objeto.objects) do
        for _, malla in pairs(o.meshes or {}) do
            local mat = malla.material
            if mat and mat.name and mat.name:find('^mira_') and not d.mira[mat] then
                d.mira[mat] = {
                    color = { (mat.color or { 1, 1, 1 })[1], (mat.color or { 1, 1, 1 })[2], (mat.color or { 1, 1, 1 })[3] },
                    emision = { (mat.emission or { 0, 0, 0 })[1], (mat.emission or { 0, 0, 0 })[2], (mat.emission or { 0, 0, 0 })[3] },
                }
                mat:setEmissionFactor(6, 6, 6)
            end
        end
    end
    cargarMisil()
end

-- Puntos del cañón ---------------------------------------------------------------

local function boca(self, d)
    local c = self:getPieza('cabeza')
    local m = c:getMatriz()
    if not m then
        return nil
    end
    local b = d.canon.boca
    local x, y, z = c:getPunto(b[1], b[2], b[3])
    return x, y, z, m[1], m[5], m[9]
end

local function ojoMira(self)
    return self:getPieza('globoIzq'):getPosicion()
end

-- Lo primero que toca una recta de (x, y, z) hacia (dx, dy, dz): mundo o robot.
local function tocar(self, x, y, z, dx, dy, dz, alcance)
    local dist, tipo = Mundo.rayo(x, y, z, dx, dy, dz, alcance)
    dist = dist or alcance
    local robot, zona
    for _, otro in ipairs(self.gestor:getRobots()) do
        if otro ~= self and otro.getImpactoRayo then
            local t, zz = otro:getImpactoRayo(x, y, z, dx, dy, dz, dist)
            if t and t < dist then
                dist, robot, zona, tipo = t, otro, zz, 'robot'
            end
        end
    end
    return dist, tipo, robot, zona
end

-- Misiles ------------------------------------------------------------------------

local function lanzar(self, d)
    -- Retroceso: el cuerpo encaja el golpe (piernasSoldado y brazosVivos).
    self.retrocesoDisparo = 1
    local bx, by, bz, gx, gy, gz = boca(self, d)
    local v = Lanzador.velocidadSalida
    d.misiles[#d.misiles + 1] = {
        x = bx, y = by, z = bz, dx = gx, dy = gy, dz = gz, v = v, t = 0, estela = {}, objetivo = d.enemigo,
    }
    d.disparados = d.disparados + 1
    d.fogonazo = 0.12
    print(string.format('%s t=%.1f s ¡disparo! (%d)', self.datos.asalto.nombre or '?', d.reloj, d.disparados))
end

local function explotar(self, d, m, x, y, z, robot, zona)
    d.estelas = d.estelas or {}
    d.estelas[#d.estelas + 1] = m.estela
    -- Nube de humo: bocanadas que salen, crecen, suben y se abren.
    local humo = {}
    for _ = 1, Lanzador.bocanadas do
        local a = love.math.random() * 2 * math.pi
        local h = love.math.random()
        local v = 0.8 + love.math.random() * 3.2
        humo[#humo + 1] = {
            x = x, y = y, z = z,
            vx = math.cos(a) * v * (1 - h * 0.5) - m.dx * 1.5, vy = math.sin(a) * v * (1 - h * 0.5) - m.dy * 1.5, vz = 0.4 + h * 2.2,
            r = 0.25 + love.math.random() * 0.35, crece = 0.5 + love.math.random() * 0.6,
            gris = 0.12 + love.math.random() * 0.45, retraso = love.math.random() * 0.35,
        }
    end
    d.explosiones[#d.explosiones + 1] = { x, y, z, t = 0, robot = robot ~= nil, humo = humo }
    if robot then
        robot:setImpacto(x, y, z, m.dx, m.dy, m.dz, Lanzador.fuerza, zona)
        d.aciertos = d.aciertos + 1
        local o = robot.datos.asalto
        if o then
            o.recibidas = (o.recibidas or 0) + 1
            o.avisado = o.estado ~= 'combate' and self or o.avisado
            o.oido, o.oidoEn = o.reloj, { self.x, self.y }
        end
    end
    print(string.format('%s t=%.1f s el proyectil explota%s', self.datos.asalto.nombre or '?', d.reloj, robot and (' en ' .. (robot.datos.asalto and robot.datos.asalto.nombre or 'un robot')) or ''))
end

local function moverMisiles(self, d, dt)
    for k = #d.misiles, 1, -1 do
        local m = d.misiles[k]
        m.t = m.t + dt
        m.v = math.min(Lanzador.velocidadMaxima, m.v + Lanzador.aceleracion * dt)
        -- Va al robot que marcó el láser al salir (fijado en él).
        local tx, ty, tz
        if m.objetivo then
            tx, ty, tz = m.objetivo:getPieza('torso'):getPunto(0, 0, 0.25)
        elseif d.laser then
            tx, ty, tz = d.laser[4], d.laser[5], d.laser[6]
        end
        if tx and m.t > 0.08 then
            local ux, uy, uz = tx - m.x, ty - m.y, tz - m.z
            local n = math.sqrt(ux * ux + uy * uy + uz * uz)
            if n > 0.5 then
                ux, uy, uz = ux / n, uy / n, uz / n
                local c = math.max(-1, math.min(1, m.dx * ux + m.dy * uy + m.dz * uz))
                local a = math.acos(c)
                local paso = math.min(1, Lanzador.giroMisil * dt / math.max(a, 1e-6))
                m.dx, m.dy, m.dz = m.dx + (ux - m.dx) * paso, m.dy + (uy - m.dy) * paso, m.dz + (uz - m.dz) * paso
                local l = math.sqrt(m.dx ^ 2 + m.dy ^ 2 + m.dz ^ 2)
                m.dx, m.dy, m.dz = m.dx / l, m.dy / l, m.dz / l
            end
        end
        local largo = m.v * dt
        local dist, tipo, robot, zona = tocar(self, m.x, m.y, m.z, m.dx, m.dy, m.dz, largo + 0.25)
        if dist < largo + 0.25 and tipo then
            if os.getenv('LANZADOR_DEPURAR') then
                print(string.format('  choca con %s a %.2f m; misil en %.1f %.1f %.1f (suelo %.1f) dir %.2f %.2f %.2f, a %.1f m del robot',
                    tostring(tipo), dist, m.x, m.y, m.z, Mundo.altura and Mundo.altura(m.x, m.y) or -1, m.dx, m.dy, m.dz, math.sqrt((m.x - self.x) ^ 2 + (m.y - self.y) ^ 2)))
            end
            explotar(self, d, m, m.x + m.dx * dist, m.y + m.dy * dist, m.z + m.dz * dist, robot, zona)
            table.remove(d.misiles, k)
        elseif m.t > Lanzador.vidaMisil then
            explotar(self, d, m, m.x, m.y, m.z)
            table.remove(d.misiles, k)
        else
            m.x, m.y, m.z = m.x + m.dx * largo, m.y + m.dy * largo, m.z + m.dz * largo
            m.estelaReloj = (m.estelaReloj or 0) - dt
            if m.estelaReloj <= 0 then
                m.estelaReloj = 0.004
                table.insert(m.estela, 1, { m.x - m.dx * 0.08, m.y - m.dy * 0.08, m.z - m.dz * 0.08, t = 0, gris = 0.72 + love.math.random() * 0.2 })
            end
        end
        for n = #m.estela, 1, -1 do
            m.estela[n].t = m.estela[n].t + dt
            if m.estela[n].t > Lanzador.estela then
                m.estela[n] = nil
            end
        end
    end
    for k = #(d.estelas or {}), 1, -1 do
        local estela = d.estelas[k]
        for n = #estela, 1, -1 do
            estela[n].t = estela[n].t + dt
            if estela[n].t > Lanzador.estela then
                estela[n] = nil
            end
        end
        if #estela == 0 then
            table.remove(d.estelas, k)
        end
    end
    for k = #d.explosiones, 1, -1 do
        local e = d.explosiones[k]
        e.t = e.t + dt
        for _, b in ipairs(e.humo) do
            if e.t > b.retraso then
                -- Frena al abrirse y sube; el viento lo lleva un poco.
                local f = math.max(0, 1 - dt * 1.6)
                b.vx, b.vy = b.vx * f + 0.25 * dt, b.vy * f + 0.1 * dt
                b.vz = b.vz * math.max(0, 1 - dt * 0.6) + 0.15 * dt
                b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
            end
        end
        if e.t > Lanzador.explosion then
            table.remove(d.explosiones, k)
        end
    end
end

-- Pensar ---------------------------------------------------------------------------

function Lanzador:onUpdate(dt)
    local d = self.datos.lanzador
    local a = self.datos.asalto
    d.reloj = d.reloj + dt
    d.fogonazo = math.max(0, (d.fogonazo or 0) - dt)
    moverMisiles(self, d, dt)
    local loVe = a.enemigo and a.visto and a.reloj - a.visto < 0.4
    -- También lo que ve el cerebro (esperando, asalto no mira).
    local c = self.datos.cerebro
    if not loVe and c and c.memoria then
        -- El mismo de antes si lo sigue viendo (no saltar de uno a otro).
        local elegido
        for _, p in ipairs(c.memoria) do
            if p.ahora and p.robot and (not elegido or p.robot == d.enemigo) then
                elegido = p.robot
            end
        end
        if elegido then
            a.enemigo = elegido
            loVe = true
        end
    end
    if loVe then
        d.viendo = (d.viendo or 0) + dt
        d.enemigo = a.enemigo
        d.ultimaVez = d.reloj
    else
        d.viendo = 0
    end
    -- Armar o desarmar.
    d.descanso = math.max(0, (d.descanso or 0) - dt)
    if (d.disparados or 0) >= Lanzador.rafaga and d.recarga <= Lanzador.recarga - 1.2 then
        -- Ráfaga hecha (y el último misil ya fuera): guarda el cañón.
        d.disparados = 0
        d.descanso = Lanzador.descanso[1] + love.math.random() * (Lanzador.descanso[2] - Lanzador.descanso[1])
        print(string.format('%s t=%.1f s guarda el cañón %.1f s', a.nombre or '?', d.reloj, d.descanso))
    end
    if d.descanso > 0 then
        d.quiere = 0
    elseif d.viendo > Lanzador.armarSiVe then
        d.quiere = 1
    elseif not d.ultimaVez or d.reloj - d.ultimaVez > Lanzador.desarmarTras then
        d.quiere = 0
        d.enemigo = nil
    end
    -- Sin verlo un buen rato, ya no es su blanco (deja de mirarlo).
    if d.enemigo and d.ultimaVez and d.reloj - d.ultimaVez > Lanzador.desarmarTras then
        d.enemigo = nil
    end
    local antes = d.forma
    -- Postura de disparo (el dueño, 18-nov: «cuando saca el cañón debería
    -- tener una pose de disparo prepotente»): la piden las piernas y los
    -- brazos, de 0 a 1 mientras se arma.
    self.posturaDisparo = d.forma
    self.retrocesoDisparo = math.max(0, (self.retrocesoDisparo or 0) - dt * 2.5)
    local paso = dt / d.canon.cambio
    if d.quiere > d.forma then
        d.forma = math.min(d.quiere, d.forma + paso)
    elseif d.quiere < d.forma then
        d.forma = math.max(d.quiere, d.forma - paso)
    end
    if antes < 1 and d.forma >= 1 then
        print(string.format('%s t=%.1f s cañón armado', a.nombre or '?', d.reloj))
    elseif antes > 0 and d.forma <= 0 then
        print(string.format('%s t=%.1f s vuelve a ser cabeza', a.nombre or '?', d.reloj))
    end
    local armado = d.forma >= 1
    -- Láser y apuntado.
    d.laser = nil
    d.laserLlega = false
    local error = math.huge
    local horizontal
    if armado and d.enemigo then
        -- El ojo y el cañón son una sola pieza (el dueño, 18-nov): los dos
        -- cuelgan de `cabeza` y se mueven juntos; el láser sale del ojo recto
        -- en la dirección del cañón, nunca torcido. Para que dé en el blanco
        -- gira la cabeza entera (cañón y ojo a la vez), de lado y de arriba
        -- abajo, hasta que el láser cae en su pecho.
        -- Lo que se apunta es la línea del ojo (la del láser).
        local _, _, _, gx, gy, gz = boca(self, d)
        local ox, oy, oz = ojoMira(self)
        local tx, ty, tz = d.enemigo:getPieza('torso'):getPunto(0, 0, 0.25)
        local wx, wy, wz = tx - ox, ty - oy, tz - oz
        horizontal = math.sqrt(wx * wx + wy * wy)
        local errorArriba = math.atan2(wz, horizontal) - math.atan2(gz, math.sqrt(gx * gx + gy * gy))
        local errorLado = angulo(math.atan2(wy, wx) - math.atan2(gy, gx))
        local k = math.min(1, dt * 8)
        d.arriba = math.max(-Lanzador.arribaMax, math.min(Lanzador.arribaMax, d.arriba + errorArriba * k))
        d.lado = math.max(-Lanzador.ladoMax, math.min(Lanzador.ladoMax, d.lado + errorLado * k))
        error = math.sqrt(errorLado ^ 2 + errorArriba ^ 2)
        local dist, _, tocado = tocar(self, ox + gx * 0.04, oy + gy * 0.04, oz + gz * 0.04, gx, gy, gz, Lanzador.alcance + 40)
        d.laser = { ox, oy, oz, ox + gx * (dist + 0.04), oy + gy * (dist + 0.04), oz + gz * (dist + 0.04) }
        -- Marcado: el láser le ha tocado (no un árbol en medio). Como los
        -- misiles guiados por láser, el misil se fija en lo que se marcó.
        d.laserLlega = tocado == d.enemigo
        if d.laserLlega then
            d.marcado = d.reloj
        end
    else
        local k = 1 - math.min(1, dt * 3)
        d.arriba, d.lado = d.arriba * k, d.lado * k
    end
    -- Disparo: apuntado, a tiro y recargado; los engranajes aceleran antes.
    d.recarga = math.max(0, d.recarga - dt)
    local marcado = d.marcado and d.reloj - d.marcado < 0.5
    local listo = armado and loVe and marcado and error < Lanzador.apuntado and horizontal
        and horizontal < Lanzador.alcance and horizontal > Lanzador.distanciaMinima and d.recarga <= 0
    if os.getenv('LANZADOR_DEPURAR') and armado then
        d.depurar = (d.depurar or 0) - dt
        if d.depurar <= 0 then
            d.depurar = 0.5
            print(string.format('  armado: ve=%s laser=%s error=%.1f° dist=%s recarga=%.1f arriba=%.1f°', tostring(loVe and true), tostring(d.laserLlega),
                math.deg(error == math.huge and -1 or error), horizontal and string.format('%.0f', horizontal) or '-', d.recarga, math.deg(d.arriba)))
        end
    end
    if listo then
        d.carga = d.carga + dt
        if d.carga >= Lanzador.cargar then
            lanzar(self, d)
            d.disparados = (d.disparados or 0) + 1
            d.carga = 0
            d.recarga = Lanzador.recarga
        end
    else
        d.carga = math.max(0, d.carga - dt)
    end
    -- Engranajes.
    local quiereGiro = suave((d.forma - 0.8) / 0.2) * (d.carga > 0 and Lanzador.giroCargando or Lanzador.giroEngranajes)
    d.vGiro = d.vGiro + (quiereGiro - d.vGiro) * math.min(1, dt * 3)
    d.fase = d.fase + d.vGiro * dt
    -- Lo que hace, para la etiqueta.
    if d.forma <= 0 then
        d.estado = 'cabeza'
    elseif d.forma < 1 then
        d.estado = d.quiere > 0 and 'armar' or 'desarmar'
    elseif d.carga > 0 or d.fogonazo > 0 then
        d.estado = 'disparar'
    elseif d.laser then
        d.estado = 'marcar'
    else
        d.estado = 'armado'
    end
end

-- Poner las piezas -------------------------------------------------------------------

function Lanzador:onPose()
    local d = self.datos.lanzador
    local C = d.canon
    local f = d.forma
    local T = f * C.cambio
    for _, p in ipairs(C.piezas) do
        local pieza = self.piezas[p.nombre]
        if pieza then
            if f <= 0 then
                pieza:setMatrizLocal(nil)
                pieza:setVisible(not p.nace)
            else
                local retraso = (C.cambio - C.viaje) * p.orden / C.maximo
                local u = suave((T - retraso) / C.viaje)
                local v = 1 - u
                local pos = {
                    v * v * p.pa[1] + 2 * v * u * p.control[1] + u * u * p.pb[1],
                    v * v * p.pa[2] + 2 * v * u * p.control[2] + u * u * p.pb[2],
                    v * v * p.pa[3] + 2 * v * u * p.control[3] + u * u * p.pb[3],
                }
                local q = slerp(p.qa, p.qb, u)
                if p.orden % 2 == 0 and not p.esconder then
                    local g = math.pi * 4 * u * (1 - u) / 2
                    q = producto(q, { math.cos(g), math.sin(g), 0, 0 })
                end
                local e = 1
                if p.nace then
                    e = suave(u * 1.5)
                end
                if p.esconder then
                    e = 1 - suave((u - 0.5) * 2)
                end
                if p.retraer then
                    e = 1 - suave(u * 2.5)
                end
                pieza:setVisible(e > 0.02)
                pieza:setMatrizLocal(matriz(pos, q, math.max(0.02, e)))
            end
        end
    end
    -- Tapa del cargador: se abre mientras salen las piezas.
    if self.piezas.tapaCargador then
        self.piezas.tapaCargador:setGiro('y', -math.rad(100) * math.sin(math.pi * f))
    end
    -- Engranajes del tubo.
    for _, g in ipairs(C.engranajes) do
        local pieza = self.piezas[g.nombre]
        if pieza then
            pieza:setGiro(g.eje, g.giro * d.fase, 'girar')
        end
    end
    -- El cañón: de lado y arriba/abajo (encima del giro de la cabeza de asalto).
    local cabeza = self:getPieza('cabeza')
    local listo = suave((f - 0.9) / 0.1)
    cabeza:setGiro('z', d.lado * listo, 'apuntarLado')
    cabeza:setGiro('y', -d.arriba * listo, 'apuntarArriba')
    -- El ojo de la mira, de cian a rojo.
    local r = suave((f - 0.85) / 0.15)
    for mat, o in pairs(d.mira) do
        local R = Lanzador.rojo
        mat:setColor(o.color[1] + (R[1] - o.color[1]) * r, o.color[2] + (R[2] - o.color[2]) * r, o.color[3] + (R[3] - o.color[3]) * r)
        mat:setEmission(o.emision[1] + (R[1] - o.emision[1]) * r, o.emision[2] + (R[2] - o.emision[2]) * r, o.emision[3] + (R[3] - o.emision[3]) * r)
    end
end

-- Los misiles, en 3D.
function Lanzador:onDibujar(aDream, ...)
    local d = self.datos.lanzador
    if #d.misiles == 0 then
        return
    end
    local obj = cargarMisil()
    for _, m in ipairs(d.misiles) do
        local xx, xy, xz = m.dx, m.dy, m.dz
        -- y = z_mundo x x, z = x x y
        local yx, yy, yz = -xy, xx, 0
        local n = math.sqrt(yx * yx + yy * yy)
        if n < 1e-4 then
            yx, yy, yz, n = 0, 1, 0, 1
        end
        yx, yy, yz = yx / n, yy / n, yz / n
        local zx, zy, zz = xy * yz - xz * yy, xz * yx - xx * yz, xx * yy - xy * yx
        local giro = m.t * 25
        local c, s = math.cos(giro), math.sin(giro)
        yx, yy, yz, zx, zy, zz = yx * c + zx * s, yy * c + zy * s, yz * c + zz * s, zx * c - yx * s, zy * c - yy * s, zz * c - yz * s
        local mat = {
            xx, yx, zx, m.x,
            xy, yy, zy, m.y,
            xz, yz, zz, m.z,
            0, 0, 0, 1,
        }
        obj:setTransform(aDream(mat, self, ...))
        obj.dynamic = true
        dream:draw(obj)
    end
end

function Robot:getLanzador()
    return self.datos.lanzador
end

Nucleo.registrarEspecializacion('lanzador', Lanzador)
return Lanzador

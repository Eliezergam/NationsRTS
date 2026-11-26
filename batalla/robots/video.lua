-- Vídeo de los dos robots que se enfrentan en la batalla 3D, grabado en el
-- juego con el código de verdad (como almacen/video_robot.lua):
--   BATALLA_ROBOTS_VIDEO=<salida.mp4> [BATALLA_ROBOTS_SEGUNDOS=<s>]
--   love . 42 --captura 999999 nada.png 0 0 0.3 1 --batalla preparacion 999999
-- En la preparación (los tanques quietos en sus zonas) los robots avanzan
-- solos. La cámara va detrás y a un lado de uno, mirando hacia el otro, y
-- cambia de robot cada `turno` s. Cada cuadro, 1/30 s de juego.

local VideoRobots = {}
VideoRobots.__index = VideoRobots

VideoRobots.fps = 30
VideoRobots.turno = 15 -- s con cada robot
VideoRobots.distancia = 95 -- px (9,5 m)
VideoRobots.inclinacion = math.rad(13)

-- Con más de dos robots (el dueño, 18-nov: «que la cámara salga en
-- distintos lugares y trate de enfocarlos»), como un director: cada `toma`
-- s corta a otro robot, de los que están peleando si los hay, y a otro
-- plano (por encima del hombro, de lado, de frente, general).
VideoRobots.toma = 5
VideoRobots.planos = { 'hombro', 'lado', 'frente', 'general' }

--- El siguiente robot a enfocar: uno que esté peleando (ve a un enemigo),
-- distinto del de ahora; si no, el siguiente de la lista.
function VideoRobots:siguienteRobot(robots)
    local peleando = {}
    for k, r in ipairs(robots) do
        if r.datos.asalto and r.datos.asalto.enemigo and k ~= self.cual then
            peleando[#peleando + 1] = k
        end
    end
    self.ronda = (self.ronda or 0) + 1
    if #peleando > 0 then
        return peleando[self.ronda % #peleando + 1]
    end
    return (self.cual or 0) % #robots + 1
end

function VideoRobots.nuevo(ruta, segundos)
    local self = setmetatable({}, VideoRobots)
    self.ruta = ruta
    self.segundos = segundos or 90
    self.cuadros = 0
    return self
end

--- Solo capturas (el dueño, 18-nov: «no grabes vídeos, toma capturas y
-- analiza»): `<carpeta>:<s>,<s>,...` guarda <carpeta>/foto_<s>.png en cada
-- segundo de juego dado y cierra tras la última. La cámara, la misma.
function VideoRobots.fotos(texto)
    local carpeta, lista = texto:match('^(.-):(.+)$')
    local self = VideoRobots.nuevo(nil, 0)
    self.carpeta = carpeta
    self.fotos = {}
    for s in lista:gmatch('[^,]+') do
        self.fotos[#self.fotos + 1] = tonumber(s)
    end
    table.sort(self.fotos)
    self.segundos = self.fotos[#self.fotos] + 1
    return self
end

--- Con el camión de misiles (escena.robotsCamion): alrededor de él, despacio,
-- mirando al puesto del conductor.
function VideoRobots:camaraCamion(escena)
    local r = escena.robotsCamion[1]
    local x, y, z, rumbo = r:getJuego()
    local t = self.cuadros / VideoRobots.fps
    local c = escena.camara
    -- El puesto está ~4,5 m por delante del centro del camión.
    self.blanco = self.blanco or {}
    local b = self.blanco
    b.x, b.y, b.z = x + math.cos(rumbo) * 44, y + math.sin(rumbo) * 44, z + 14
    -- `BATALLA_ROBOTS_CAMARA=conductor`: a la cabeza del robot conductor.
    local conductor = escena.robotsCamion[2]
    if os.getenv('BATALLA_ROBOTS_CAMARA') == 'conductor' and conductor then
        local cx, cy, cz = conductor:getJuego()
        b.x, b.y, b.z = cx, cy, cz + 9
    end
    b.getJuego = function()
        return b.x, b.y, b.z, 0
    end
    c.robot = b
    -- `BATALLA_ROBOTS_CAMARA_RUMBO` (rad respecto al camión): fija, sin girar.
    local fijo = tonumber(os.getenv('BATALLA_ROBOTS_CAMARA_RUMBO') or '')
    c.rumbo = fijo and rumbo + fijo or rumbo + 0.8 + t * 0.3
    c.inclinacion = math.rad(16)
    c.distancia = tonumber(os.getenv('BATALLA_ROBOTS_CAMARA_DISTANCIA') or '') or 120
    require('batalla.camara').robotDistancia = { 15, 400 }
    self.cual = nil
end

--- Pone la cámara (cada paso de la escena).
function VideoRobots:camara(escena, dt)
    -- `BATALLA_CAMARA_PUNTO=x,y[,distancia]` (px): la cámara da la vuelta
    -- despacio alrededor de ese punto del suelo, para revisar de cerca lo que
    -- se pone en el terreno (restos, plantas...).
    -- `AVION_DEMO=salida|llegada` (tools/demo_avion.sh), el dueño, 20-nov:
    -- la vista de un robot de pie junto a la pista (ojos a 1,6 m) que sigue
    -- al avión con la mirada. Salida: en la cabecera este, a 20 m del eje;
    -- el avión despega de frente, le pasa por encima y se pierde en la
    -- niebla. Llegada: junto a la zona de toma, a 50 m del eje (fuera del
    -- ala), mirando hacia donde viene; lo ve salir de la niebla, tocar y
    -- frenar a su lado.
    local demo = os.getenv('AVION_DEMO')
    local avion = escena.avionCarga
    if demo and escena.camara.libreDemo then
        return
    end
    if demo and avion and not os.getenv('BATALLA_CAMARA_PUNTO') then
        local v = avion.datos.vueloAvion
        local cx, cy = v.px * 10, -v.py * 10
        local ux, uy = v.ux, -v.uy -- a lo largo, en px del juego
        local sx, sy = -uy, ux -- a la derecha (al sur si va al este)
        local c = escena.camara
        if not c.ojoFijo then
            local ox, oy
            if demo == 'salida' then
                ox, oy = cx + ux * 3300 + sx * 200, cy + uy * 3300 + sy * 200
            else
                ox, oy = cx + ux * 1000 + sx * 500, cy + uy * 1000 + sy * 500
            end
            c.ojoFijo = { ox, oy, escena.suelo:altura(ox, oy) + 16 }
        end
        -- La mirada, en el cuerpo del avión (hasta que deja la escena).
        self.blanco = self.blanco or {}
        local b = self.blanco
        if not avion.guardado then
            local x, y, z = avion:getJuego()
            b.x, b.y, b.z = x, y, z + 40
        end
        b.getJuego = function()
            return b.x, b.y, b.z, 0
        end
        c.robot = b
        require('batalla.camara').robotDistancia = { 1, 9000 }
        return
    end
    local punto = os.getenv('BATALLA_CAMARA_PUNTO')
    if punto then
        local px, py, d, inc, rumbo = punto:match('([%-%d%.]+),([%-%d%.]+),?([%d%.]*),?([%d%.]*),?([%-%d%.]*)')
        px, py, d, inc, rumbo = tonumber(px), tonumber(py), tonumber(d) or 180, tonumber(inc) or 18, tonumber(rumbo)
        local c = escena.camara
        self.blanco = self.blanco or {}
        local b = self.blanco
        b.x, b.y, b.z = px, py, escena.suelo:altura(px, py) + 10
        b.getJuego = function()
            return b.x, b.y, b.z, 0
        end
        c.robot = b
        -- Con un quinto número (grados), la cámara queda fija en ese rumbo.
        c.rumbo = rumbo and math.rad(rumbo) or (0.6 + self.cuadros / VideoRobots.fps * 0.25)
        c.inclinacion = math.rad(inc)
        c.distancia = d
        require('batalla.camara').robotDistancia = { 1, 5000 }
        return
    end
    -- `BATALLA_SEGUIR_AVION=1`: cámara de persecución del avión de carga, a
    -- 3/4 por detrás y algo por encima (vueloAvion.lua).
    if os.getenv('BATALLA_SEGUIR_AVION') and escena.avionCarga then
        local c = escena.camara
        local a = escena.avionCarga
        local _, _, _, rumbo = a:getJuego()
        -- En tierra, más alta y casi en el eje: dentro de la franja
        -- despejada de la pista (si no, se mete entre los árboles).
        local v = a.datos.vueloAvion
        local fase = v and v.fase or 'aparcado'
        local enTierra = fase == 'aparcado' or fase == 'carreteo' or fase == 'frenada' or fase == 'rampa'
        local giro, inclinacion, distancia = 0.55, 14, 1100
        if fase == 'embarque' then
            -- Por detrás y un poco a un lado: la fila subiendo la rampa.
            giro, inclinacion, distancia = 0.35, 22, 620
        elseif enTierra then
            giro, inclinacion, distancia = 0.3, 24, 850
        end
        local k = math.min(1, (dt or 1 / 30) * 1.5)
        -- Embarque: detrás del último del pelotón (ve la fila subir delante
        -- de él y, dentro, las filas ya formadas).
        local e = a.datos.embarque
        local ultimo = fase == 'embarque' and e and e.pasajeros[#e.pasajeros]
        if ultimo then
            c.robot = ultimo.robot
            c.rumbo = (c.rumbo or rumbo + math.pi) + ((rumbo + math.pi + 0.15 - (c.rumbo or 0) + math.pi) % (2 * math.pi) - math.pi) * k
            c.inclinacion = math.rad(13)
            c.distancia = 130
            require('batalla.camara').robotDistancia = { 15, 5000 }
            return
        end
        local quiere = rumbo + math.pi + giro
        local actual = c.rumbo or quiere
        local dif = (quiere - actual + math.pi) % (2 * math.pi) - math.pi
        c.robot = a
        c.rumbo = actual + dif * k
        c.inclinacion = (c.inclinacion or math.rad(inclinacion)) + (math.rad(inclinacion) - (c.inclinacion or 0)) * k
        c.distancia = (c.distancia or distancia) + (distancia - (c.distancia or distancia)) * k
        require('batalla.camara').robotDistancia = { 15, 5000 }
        return
    end
    if escena.robotsCamion then
        return self:camaraCamion(escena)
    end
    local robots = escena.robotsAsalto
    if not robots then
        return
    end
    -- Un robot en prueba (escena.robotFoco): solo a él.
    if escena.robotFoco then
        robots = { escena.robotFoco }
    end
    local t = self.cuadros / VideoRobots.fps
    local cual = math.floor(t / VideoRobots.turno) % #robots + 1
    local plano = 'hombro'
    -- Con un lanzamisiles, siempre él y sin cortes (el dueño, 18-nov: «que esa
    -- cámara no se mueva tanto»).
    local conLanzador
    for k, otro in ipairs(robots) do
        if otro.datos.lanzador then
            conLanzador = k
        end
    end
    if conLanzador then
        cual = conLanzador
    elseif #robots > 2 then
        -- Director: corta al acabar la toma (no a mitad de un disparo
        -- seguido del proyectil).
        local enVuelo = self.cual and robots[self.cual].datos.lanzador and #robots[self.cual].datos.lanzador.misiles > 0
        if not self.finToma or (t >= self.finToma and not enVuelo) then
            self.cual = self:siguienteRobot(robots)
            self.plano = VideoRobots.planos[(self.ronda or 1) % #VideoRobots.planos + 1]
            self.finToma = t + VideoRobots.toma
            self.angulo = nil
            self.lejos = nil
        end
        cual, plano = self.cual, self.plano
    else
        -- Si hay un lanzamisiles, siempre él (el dueño, 18-nov: «enfócame al
        -- robot del misil»).
        for k, otro in ipairs(robots) do
            if otro.datos.lanzador then
                cual = k
            end
        end
    end
    local r = robots[cual]
    local d = r.datos.asalto
    local rx, ry, rz = r:getJuego()
    -- Hacia el enemigo (su objetivo, o el enemigo si lo ve), en px del juego.
    -- Sin objetivo (quieto, en prueba): hacia donde mira.
    local ox, oy
    if d.objetivo then
        ox, oy = d.objetivo[1] * 10, -d.objetivo[2] * 10
    else
        local _, _, _, rumbo = r:getJuego()
        ox, oy = rx + math.cos(rumbo) * 1000, ry + math.sin(rumbo) * 1000
    end
    if d.enemigo then
        ox, oy = d.enemigo:getJuego()
    end
    local hacia = math.atan2(oy - ry, ox - rx)
    local quiere = hacia + math.pi + 0.45
    local distancia, inclinacion = VideoRobots.distancia, VideoRobots.inclinacion
    if plano == 'lado' then
        quiere, distancia, inclinacion = hacia + math.pi / 2, 75, math.rad(7)
    elseif plano == 'frente' then
        quiere, distancia, inclinacion = hacia - 0.3, 70, math.rad(8)
    elseif plano == 'general' then
        quiere, distancia, inclinacion = hacia + math.pi / 2 + 0.6, 190, math.rad(18)
    end
    local lado = os.getenv('BATALLA_ROBOTS_CAMARA') == 'lado'
    if lado then
        -- De lado, a 6 m, mirando al robot (se ven las piernas).
        local _, _, _, rumbo = r:getJuego()
        quiere = rumbo - math.pi / 2
    end
    if self.cual ~= cual or not self.angulo then
        self.angulo = quiere
        self.cual = cual
    else
        local e = (quiere - self.angulo + math.pi) % (2 * math.pi) - math.pi
        self.angulo = self.angulo + e * math.min(1, dt * 1.5)
    end
    -- Mira un poco por delante del robot, hacia el enemigo.
    local tx, ty = rx + math.cos(hacia) * 30, ry + math.sin(hacia) * 30
    if lado or plano == 'lado' or plano == 'frente' then
        tx, ty = rx, ry
    elseif plano == 'general' then
        -- Un poco por delante del enfocado, hacia el enemigo (como mucho
        -- 8 m: si no, con el enemigo lejos, el robot sale de la imagen).
        local hasta = math.min(80, 0.3 * math.sqrt((ox - rx) ^ 2 + (oy - ry) ^ 2))
        tx, ty = rx + math.cos(hacia) * hasta, ry + math.sin(hacia) * hasta
    end
    local tz = escena.suelo:altura(tx, ty)
    tz = math.max(tz, rz)
    -- Con un lanzamisiles (el dueño, 18-nov): la cámara se queda quieta a
    -- un lado del robot; con un misil en el aire solo gira la vista hacia él
    -- (y luego hacia el humo), sin seguirlo, y vuelve al robot.
    local L = r.datos.lanzador
    if L and not lado and plano == 'hombro' then
        -- El lado se elige una vez y se queda; solo cambia si el robot se
        -- va lejos (más de 15 m) de donde se eligió.
        local f = self.fijo
        -- Corriendo: detrás y a un lado, siguiéndolo (despacio).
        -- Como la cámara de seguimiento de cualquier juego (el dueño, 19-nov:
        -- «¿por qué se mueve y se empecina? ¿No puede seguirlo linealmente?»):
        -- detrás de hacia donde va, con el rumbo suavizado (al patinar el
        -- cuerpo se tuerce a cada zancada y la cámara no debe seguir eso).
        local _, _, _, rumbo = r:getJuego()
        self.rumboSuave = self.rumboSuave or rumbo
        local er = (rumbo - self.rumboSuave + math.pi) % (2 * math.pi) - math.pi
        self.rumboSuave = self.rumboSuave + er * math.min(1, dt * 1.2)
        if f and math.abs(r.velocidad or 0) > 1.5 then
            f.x, f.y, f.angulo = rx, ry, self.rumboSuave + math.pi + 0.3
        end
        if not f or (rx - f.x) ^ 2 + (ry - f.y) ^ 2 > 150 * 150 then
            f = { x = rx, y = ry, angulo = hacia + math.pi / 2, actual = self.fijo and self.fijo.actual or hacia + math.pi / 2 }
            self.fijo = f
        end
        distancia, inclinacion = 75, math.rad(7)
        -- Su propio ángulo (el de arriba sigue al enemigo que mira y gira).
        local e = (f.angulo - f.actual + math.pi) % (2 * math.pi) - math.pi
        -- Quieto, casi no se mueve; corriendo, lo sigue (que no se salga).
        local rapidez = math.abs(r.velocidad or 0) > 1.5 and 3.0 or 0.5
        f.actual = f.actual + e * math.min(1, dt * rapidez)
        self.angulo = f.actual
        tx, ty = rx, ry
        -- La altura, suave (los botes del terreno no sacuden la imagen).
        self.alturaSuave = (self.alturaSuave or rz) + (rz - (self.alturaSuave or rz)) * math.min(1, dt * 4)
        tz = self.alturaSuave
    end
    local mx, my, mz
    if L then
        local m = L.misiles[1]
        local e = L.explosiones[#L.explosiones]
        if m then
            mx, my, mz = m.x * 10, -m.y * 10, m.z * 10 - 11
            self.ultimoMisil = 0
        elseif e and e.t < 2.5 and self.ultimoMisil then
            mx, my, mz = e[1] * 10, -e[2] * 10, e[3] * 10 - 11 + e.t * 6
        else
            self.ultimoMisil = nil
        end
    end
    self.blanco = self.blanco or {}
    local b = self.blanco
    b.x, b.y, b.z = tx, ty, tz
    b.getJuego = function()
        return b.x, b.y, b.z, 0
    end
    local c = escena.camara
    c.robot = b
    c.rumbo = self.angulo
    c.inclinacion = inclinacion
    c.distancia = lado and 60 or distancia
    -- Sin troncos ni terreno entre la cámara y el robot: si los hay, se
    -- acerca (nunca dentro de un árbol).
    local Mundo = require('batalla.robots.mundo')
    local h = math.cos(c.inclinacion) * c.distancia
    local ex, ey = tx + math.cos(c.rumbo) * h, ty + math.sin(c.rumbo) * h
    local ez = tz + 11 + math.sin(c.inclinacion) * c.distancia
    local ox, oy, oz = rx / 10, -ry / 10, rz / 10 + 1.4
    local dx, dy, dz = ex / 10 - ox, -ey / 10 - oy, ez / 10 - oz
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    local choque = Mundo.rayo(ox, oy, oz, dx, dy, dz, largo + 1)
    -- Lo que lleva la etiqueta `copa` (un cilindro { z0, r } por encima del
    -- sólido: la copa de un árbol, que el rayo no toca): la cámara no entra.
    local cerca = {}
    for paso = 2, math.floor(largo) do
        local f = paso / largo
        local px, py, pz = ox + dx * f, oy + dy * f, oz + dz * f
        local dentro = false
        for _, col in ipairs(Mundo.cerca(px, py, 6, 'copa', cerca)) do
            local copa, forma = col.etiquetas.copa, col.forma
            if pz > copa.z0 and pz < forma.z1 + 0.5 and (px - forma.x) ^ 2 + (py - forma.y) ^ 2 < copa.r * copa.r then
                dentro = true
                break
            end
        end
        if dentro then
            choque = math.min(choque or math.huge, paso - 0.5)
            break
        end
    end
    local quiereLejos = c.distancia
    -- Corriendo no se acerca por troncos ni hierba (daba tirones).
    if choque and math.abs(r.velocidad or 0) <= 1.5 then
        quiereLejos = math.max(25, (choque - 1.2) * 10)
    end
    -- Se acerca enseguida y se aleja despacio (sin saltos).
    self.lejos = math.min(quiereLejos, (self.lejos or quiereLejos) + dt * 40)
    c.distancia = math.min(c.distancia, self.lejos)
    if lado then
        c.inclinacion = math.rad(6)
    end
    require('batalla.camara').robotDistancia = { 15, 400 }
    if not L then
        return
    end
    -- El ojo, quieto donde está; lo que mira gira suave hacia el misil (o el
    -- humo) y vuelve al robot.
    h = math.cos(c.inclinacion) * c.distancia
    ex, ey = tx + math.cos(c.rumbo) * h, ty + math.sin(c.rumbo) * h
    ez = tz + 11 + math.sin(c.inclinacion) * c.distancia
    -- Lo que mira, como desvío desde el robot (así, corriendo, no se queda
    -- atrás): cero, o hacia el misil y el humo.
    local qx, qy, qz = 0, 0, 0
    if mx then
        qx, qy, qz = mx - tx, my - ty, mz - tz
    end
    local mira = self.mira
    if not mira then
        mira = { qx, qy, qz }
        self.mira = mira
    end
    -- Hacia el misil, rápido (que no se escape de la imagen); de vuelta, suave.
    local k = math.min(1, dt * (mx and 5 or 2))
    mira[1] = mira[1] + (qx - mira[1]) * k
    mira[2] = mira[2] + (qy - mira[2]) * k
    mira[3] = mira[3] + (qz - mira[3]) * k
    local px, py, pz = tx + mira[1], ty + mira[2], tz + mira[3]
    local vx, vy, vz = ex - px, ey - py, ez - (pz + 11)
    local hv = math.sqrt(vx * vx + vy * vy)
    b.x, b.y, b.z = px, py, pz
    c.rumbo = math.atan2(vy, vx)
    c.distancia = math.max(1, math.sqrt(hv * hv + vz * vz))
    c.inclinacion = math.atan2(vz, hv)
    require('batalla.camara').robotDistancia = { 1, 5000 }
    if os.getenv('CAMARA_TRAZA') then
        self.traza = (self.traza or 0) - dt
        if self.traza <= 0 then
            self.traza = 0.25
            print(string.format('CAM cual=%s ang=%.0f rumbo=%.0f dist=%.0f incl=%.0f r=(%.0f,%.0f) mira=(%.0f,%.0f) misil=%s', tostring(cual), math.deg(self.angulo), math.deg(c.rumbo), c.distancia, math.deg(c.inclinacion), rx, ry, px, py, tostring(mx ~= nil)))
        end
    end
end

function VideoRobots:cuadro(escena)
    if not escena.robotsAsalto and not escena.robotsCamion then
        return
    end
    local g = love.graphics
    g.push('all')
    g.origin()
    local nombre = escena.robotsCamion and 'camión de misiles' or escena.robotsAsalto[self.cual or 1].datos.asalto.nombre
    if os.getenv('BATALLA_SEGUIR_AVION') and escena.avionCarga then
        local v = escena.avionCarga.datos.vueloAvion
        nombre = 'avión de carga · ' .. (v and v.fase or '')
    end
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', 16, 16, 320, 26, 5, 5)
    g.setColor(1, 1, 1, 1)
    g.print(string.format('Cámara: %s   %d s', nombre, math.floor(self.tiempo or self.cuadros / VideoRobots.fps)), 24, 21)
    g.pop()
    if type(self.fotos) == "table" then
        -- Segundos de juego de verdad (como la batalla con las fotos:
        -- el tiempo de cada cuadro, con tope de 1/20 s, main.lua). Antes
        -- contaba cuadros a 30 por segundo y, a 100 FPS, «60 s» eran 20.
        self.tiempo = (self.tiempo or 0) + math.min(love.timer.getDelta(), 1 / 20)
        local t = self.tiempo
        local s = self.fotos[1]
        if s and t >= s then
            table.remove(self.fotos, 1)
            local ruta = string.format('%s/foto_%05.1f.png', self.carpeta, s)
            love.graphics.captureScreenshot(function(imagen)
                local datos = imagen:encode('png')
                local f = io.open(ruta, 'wb')
                f:write(datos:getString())
                f:close()
                print('FOTO ' .. ruta)
            end)
        end
        self.cuadros = self.cuadros + 1
        if #self.fotos == 0 and not self.cerrado then
            self.cerrado = true
            self.salir = 2
        elseif self.salir then
            self.salir = self.salir - 1
            if self.salir <= 0 then
                love.event.quit()
            end
        end
        return
    end
    love.graphics.captureScreenshot(function(imagen)
        if self.cerrado then
            return
        end
        if not self.tubo then
            local w, h = imagen:getDimensions()
            local comando = string.format("ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - -vf scale=1280:-2 -c:v libx264 -preset slow -pix_fmt yuv420p -crf 30 '%s'", w, h, VideoRobots.fps, self.ruta)
            self.tubo = io.popen(comando, 'w')
            print('VIDEO grabando en ' .. self.ruta)
        end
        self.tubo:write(imagen:getString())
    end)
    self.cuadros = self.cuadros + 1
    if self.cuadros >= self.segundos * VideoRobots.fps then
        self.cerrado = true
        if self.tubo then
            self.tubo:close()
            self.tubo = nil
        end
        print('VIDEO FIN', self.ruta, self.cuadros, 'cuadros')
        love.event.quit()
    end
end

return VideoRobots

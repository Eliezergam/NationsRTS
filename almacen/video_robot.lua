-- Vídeo del robot del almacén, grabado en el juego con el código de verdad
-- (`love . <semilla> --almacen-video [salida.mp4]`): entra en el almacén,
-- sigue al robot con la cámara mientras hace sus encargos y manda cada
-- cuadro a ffmpeg. El tiempo va a pasos fijos de 1/30 s (el vídeo no depende
-- de los FPS de la máquina); mientras el robot va de un sitio a otro, x3.
-- Al acabar los encargos de la primera vuelta, cierra el vídeo y sale.

local MundoRobot = require('almacen.robots.mundo')

local VideoRobot = {}
VideoRobot.__index = VideoRobot

VideoRobot.fps = 30
VideoRobot.rapidoViajes = 3
VideoRobot.maximo = 30 * 300 -- cuadros (5 min de vídeo como mucho)
-- ALMACEN_VIDEO_SOLDADO=<s>: el vídeo sigue al soldado que entrena, a
-- velocidad real (sin x3) y dura esos segundos.
VideoRobot.soldado = tonumber(os.getenv('ALMACEN_VIDEO_SOLDADO') or '')

function VideoRobot.nuevo(ruta)
    local self = setmetatable({}, VideoRobot)
    self.ruta = ruta
    self.cuadros = 0
    self.fin = nil
    return self
end

--- Cuántos pasos de simulación y de cuánto en este cuadro.
function VideoRobot:pasos(escena)
    if VideoRobot.soldado then
        self.rapido = false
        return 1, 1 / VideoRobot.fps
    end
    local robot = escena.robotSeguido or escena.robot
    self.rapido = robot:getNavegando()
    return self.rapido and VideoRobot.rapidoViajes or 1, 1 / VideoRobot.fps
end

-- Un sitio para la cámara a `distancia` del punto (x, y) que no quede tras
-- una pared ni dentro de un rack: prueba varios ángulos alrededor de `base`.
local function sitioLibre(x, y, z, base, distancia, giros)
    for _, g in ipairs(giros) do
        local a = base + g
        local d = MundoRobot.rayo(x, y, z, a, distancia + 0.4)
        if d >= distancia + 0.4 then
            return x + math.cos(a) * distancia, y + math.sin(a) * distancia
        end
    end
    return x + math.cos(base + giros[1]) * distancia, y + math.sin(base + giros[1]) * distancia
end

-- ¿Se ve la cabeza del robot (x, y, 1,5) desde (cx, cy, cz) sin nada en
-- medio ni nada a menos de 40 cm de la cámara?
local function camaraLibre(x, y, cx, cy, cz)
    local vx, vy, vz = cx - x, cy - y, cz - 1.5
    local largo = math.sqrt(vx * vx + vy * vy + vz * vz)
    local d = MundoRobot.rayo3D(x, y, 1.5, vx, vy, vz, largo + 0.4)
    if d < largo + 0.4 then
        return false
    end
    local m = 0.4
    if #MundoRobot.cajasEn(cx - m, cy - m, cx + m, cy + m, cz - m, cz + m) > 0 then
        return false
    end
    -- Ni dentro de un robot (el grande mide 3,6 m).
    for _, r in ipairs(GestorRobots.getRobots()) do
        local rx, ry = r:getPosicion()
        local radio = r:getAncho() / 2 + 0.5
        if (cx - rx) ^ 2 + (cy - ry) ^ 2 < radio * radio and cz < r:getAlto() + 0.4 then
            return false
        end
    end
    return true
end

-- Peleando: a tres cuartos por delante, del lado de la metralleta (se le
-- ve la cara de combate y, al fondo, el enemigo); si no, otro lado libre
-- alrededor; sin ninguno, desde arriba.
-- Se queda con el lado que tenía mientras siga libre (sin saltos).
local ladosCombate = { -1.75, 1.75, -1.4, 1.4, -2.1, 2.1, math.pi + 0.5, math.pi - 0.5, math.pi }

function VideoRobot:camaraCombate(x, y, haciaEl, hasta)
    -- De lado (perpendicular a la línea de tiro) y algo atrás, lo bastante
    -- lejos para que salgan el robot y el enemigo.
    local lejos = math.max(3.2, math.min(6.5, (hasta or 6) * 0.55))
    local function sitio(g, distancia, alto)
        local a = haciaEl + g
        return x + math.cos(a) * distancia, y + math.sin(a) * distancia, alto
    end
    if self.ladoCombate then
        local cx, cy, cz = sitio(self.ladoCombate, lejos, 2.0)
        if camaraLibre(x, y, cx, cy, cz) then
            return cx, cy, cz
        end
    end
    for _, g in ipairs(ladosCombate) do
        for _, distancia in ipairs({ lejos, lejos * 0.7 }) do
            local cx, cy, cz = sitio(g, distancia, 2.0)
            if camaraLibre(x, y, cx, cy, cz) then
                self.ladoCombate = g
                return cx, cy, cz
            end
        end
    end
    self.ladoCombate = nil
    -- Desde arriba y un poco detrás.
    local cx, cy = sitio(math.pi, 1.2, 0)
    return cx, cy, 4.0
end

--- Pone la cámara: detrás y a un lado mientras viaja; de cerca, por delante
-- y de lado, mientras coge o deja algo.
function VideoRobot:camara(escena)
    local robot = escena.robotSeguido or escena.robot
    local x, y = robot:getPosicion()
    local rumbo = robot:getRumbo()
    local cx, cy, cz, tx, ty, tz
    local enemigo = robot.getObjetivo and robot:getObjetivo()
    if not enemigo then
        self.ladoCombate = nil
    end
    if enemigo then
        -- Peleando: por detrás y a la derecha (se ve la metralleta), mirando
        -- entre el robot y el enemigo para que salgan los dos.
        local ex, ey = enemigo:getPosicion()
        local haciaEl = math.atan2(ey - y, ex - x)
        local hasta = math.sqrt((ex - x) ^ 2 + (ey - y) ^ 2)
        cx, cy, cz = self:camaraCombate(x, y, haciaEl, hasta)
        if os.getenv('VIDEO_CARA') then
            -- Prueba: delante de la cara, a 0,9 m, para ver los ojos.
            local hx, hy, hz = robot:getPieza('cabeza'):getPosicion()
            local a = robot:getRumbo() + robot.datos.mirada.lado + 0.35
            local lejos = 0.9
            if os.getenv('VIDEO_CARA') == 'lado' then
                -- De lado, a 1,8 m, a la altura del pecho: se ve cómo le
                -- tuercen los impactos el torso y la cabeza.
                a, lejos = robot:getRumbo() - 1.75, 1.8
                hz = hz - 0.25
            end
            self.camaraAhora = nil
            cx, cy, cz = hx + math.cos(a) * lejos, hy + math.sin(a) * lejos, hz + 0.1
            local tx2, ty2, tz2 = hx, hy, hz
            escena.x, escena.y, escena.z = cx, cz, -cy
            local dx, dy = tx2 - cx, ty2 - cy
            escena.controlador:orientar(math.atan2(dy, -dx), math.atan2(cz - tz2, math.sqrt(dx * dx + dy * dy)))
            escena.controlador:detener()
            return
        end
        -- Mirando entre el robot y el enemigo, más cerca del robot.
        tx, ty, tz = x + (ex - x) * 0.3, y + (ey - y) * 0.3, 1.1
    elseif robot:getNavegando() or VideoRobot.soldado then
        cx, cy = sitioLibre(x, y, 1.9, rumbo, 3.6, { math.pi - 0.45, math.pi + 0.45, math.pi })
        cz = 2.4
        tx, ty, tz = x + math.cos(rumbo) * 1.2, y + math.sin(rumbo) * 1.2, 0.9
    else
        local mx, my = x + math.cos(rumbo) * 0.35, y + math.sin(rumbo) * 0.35
        cx, cy = sitioLibre(mx, my, 1.6, rumbo, 2.0, { -1.0, 1.0, -1.5, 1.5, -0.6, 0.6 })
        cz = 1.75
        tx, ty, tz = mx, my, 1.05
    end
    -- Suave (ni saltos al cambiar de plano).
    local s = self.camaraAhora
    if not s then
        s = { cx, cy, cz, tx, ty, tz }
        self.camaraAhora = s
    end
    local f = 0.06
    local nuevo = { cx, cy, cz, tx, ty, tz }
    for k = 1, 6 do
        s[k] = s[k] + (nuevo[k] - s[k]) * f
    end
    -- Nunca dentro de una pared o un rack: si algo se cruza entre la cabeza
    -- del robot y la cámara (el suavizado la deja atrás en las esquinas), se
    -- acerca al robot hasta justo antes de eso.
    local px, py, pz = s[1], s[2], s[3]
    local ox, oy, oz = x, y, 1.5
    local vx, vy, vz = px - ox, py - oy, pz - oz
    local largo = math.sqrt(vx * vx + vy * vy + vz * vz)
    if largo > 0.3 then
        local choque = MundoRobot.rayo3D(ox, oy, oz, vx, vy, vz, largo + 0.3, robot.getLlevando and robot:getLlevando())
        if choque and choque < largo + 0.3 then
            local k = math.max(0.4, choque - 0.3) / largo
            px, py, pz = ox + vx * k, oy + vy * k, oz + vz * k
        end
    end
    -- Y sin nada a menos de 30 cm (el plano cercano corta lo que roza).
    local margen = 0.3
    for _ = 1, 20 do
        if #MundoRobot.cajasEn(px - margen, py - margen, px + margen, py + margen, pz - margen, pz + margen) == 0 then
            break
        end
        px, py, pz = px + (ox - px) * 0.15, py + (oy - py) * 0.15, pz + (oz - pz) * 0.15
    end
    -- Si ha quedado pegada a la cabeza (menos de 1,5 m), mejor por encima
    -- del robot, un poco detrás, mirando abajo.
    if (px - ox) ^ 2 + (py - oy) ^ 2 + (pz - oz) ^ 2 < 1.5 ^ 2 then
        local ax, ay = x - math.cos(rumbo) * 0.9, y - math.sin(rumbo) * 0.9
        local alto = 3.6
        if camaraLibre(x, y, ax, ay, alto) then
            px, py, pz = ax, ay, alto
        end
    end
    escena.x, escena.y, escena.z = px, pz, -py
    local dx, dy = s[4] - px, s[5] - py
    local horizontal = math.sqrt(dx * dx + dy * dy)
    escena.controlador:orientar(math.atan2(dy, -dx), math.atan2(pz - s[6], horizontal))
    escena.controlador:detener()
end

--- Al final de love.draw: el rótulo de velocidad y el cuadro a ffmpeg.
function VideoRobot:cuadro(escena)
    if not escena or not escena.robot then
        return
    end
    local g = love.graphics
    if self.rapido then
        g.push('all')
        g.origin()
        g.setColor(0, 0, 0, 0.6)
        local w = g.getWidth()
        g.rectangle('fill', w / 2 - 34, 16, 68, 34, 6, 6)
        g.setColor(1, 1, 1, 1)
        g.printf('x' .. VideoRobot.rapidoViajes, w / 2 - 34, 22, 68, 'center')
        g.pop()
    end
    love.graphics.captureScreenshot(function(imagen)
        if self.cerrado then
            return
        end
        if not self.tubo then
            local w, h = imagen:getDimensions()
            local comando = string.format("ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - -vf scale=1280:-2 -c:v libx264 -preset slow -pix_fmt yuv420p -crf 30 '%s'", w, h, VideoRobot.fps, self.ruta)
            self.tubo = io.popen(comando, 'w')
            print('VIDEO grabando en ' .. self.ruta)
        end
        self.tubo:write(imagen:getString())
    end)
    self.cuadros = self.cuadros + 1
    local robot = escena.robotSeguido or escena.robot
    if os.getenv('ROBOT_DEPURAR') and self.cuadros % 30 == 0 then
        local x, y = robot:getPosicion()
        local d = robot.datos.navegacion
        print(string.format('DEPURAR t=%d x=%.2f y=%.2f v=%.2f nav=%s ruta=%d sinCamino=%s delante=%.2f destino=%s', self.cuadros / 30, x, y, robot:getVelocidad(), tostring(robot:getNavegando()), #robot:getRuta(), tostring(d.sinCamino), robot:getDistanciaDelante(0.7), robot.datos.conduccion.destino and string.format('%.2f,%.2f', robot.datos.conduccion.destino[1], robot.datos.conduccion.destino[2]) or 'nil'))
        if os.getenv('ROBOT_DEPURAR') == 'corto' and self.cuadros >= 30 * tonumber(os.getenv('ROBOT_SEGUNDOS') or 20) then
            love.event.quit()
        end
    end
    if VideoRobot.soldado then
        self.fin = self.fin or VideoRobot.soldado * VideoRobot.fps
    elseif not self.fin and robot:getHechos() >= #require('almacen.escena').encargos and not robot:getOcupado() then
        self.fin = self.cuadros + VideoRobot.fps * 2
    end
    if (self.fin and self.cuadros >= self.fin) or self.cuadros >= VideoRobot.maximo then
        self:cerrar()
        love.event.quit()
    end
end

function VideoRobot:cerrar()
    self.cerrado = true
    if self.tubo then
        self.tubo:close()
        self.tubo = nil
        print('VIDEO FIN', self.ruta, self.cuadros, 'cuadros')
    end
end

return VideoRobot

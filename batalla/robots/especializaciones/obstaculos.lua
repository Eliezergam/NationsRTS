-- Esquivar y chocar con lo que leen sus sensores (el dueño, 19-nov: «tiene
-- que tener una especie de caja o colisión todo, donde el robot lee con
-- sensores y la vista de sus ojos»). No sabe qué es nada: solo dónde ha
-- chocado un rayo y las etiquetas de lo que ha tocado. Lo que lleve la
-- etiqueta `solido` (y no sea el `suelo`: las cuestas las lleva la
-- conducción) le estorba.
--
-- 1. Esquivar, con lo que ha visto el lidar (robots/especializaciones/
--    lidar.lua) en los últimos `memoria` s: los puntos donde chocaron sus
--    rayos se recuerdan un rato (como el mapa de costes local de un robot
--    real), así un tronco fino que se cuela entre dos rayos de un barrido no
--    se olvida en el siguiente. De los rumbos posibles (toda la vuelta), se
--    queda con el más cercano al que quiere cuyo pasillo (su ancho más una
--    holgura) está libre `mirar` m; si ninguno lo está, con el que deja más
--    sitio, y frena. La conducción suma ese giro al suyo (Robot:getDesvio).
-- 2. Chocar, con el parachoques: cada cuadro, rayos cortos alrededor a dos
--    alturas; si algo está más cerca que su radio, lo saca hasta el borde y
--    pierde la velocidad que llevaba contra ello.

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local Obstaculos = {}

Obstaculos.radio = 0.32 -- m: su medio ancho (ruedas y brazos)
Obstaculos.holgura = 0.9 -- m que deja entre él y lo que rodea
Obstaculos.mirar = 9 -- m por delante que tiene que estar libre (más con velocidad)
Obstaculos.memoria = 2 -- s que recuerda dónde chocaron los rayos
Obstaculos.celdaMemoria = 0.25 -- m: un punto recordado por celda
Obstaculos.pasoRumbo = math.rad(5)
Obstaculos.cada = 0.05 -- s entre decisiones
Obstaculos.parachoques = { alturas = { 0.3, 1.1 }, rayos = 8, largo = 0.5 }

local function estorba(tipo)
    return tipo and tipo.solido and not tipo.suelo
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Obstaculos:onLoad()
    local d = self.datos.obstaculos
    d.desvio, d.reloj = 0, self:getDesfase(Obstaculos.cada)
    d.choques = 0
    d.puntos = {}
    d.recuerdo = {} -- [celda] = { x, y, hasta }
    d.ahora = 0
end

--- Lo libre (m) por delante en el rumbo `a` con un pasillo de medio ancho
-- `w`, según los puntos donde chocaron los rayos.
local function libreEn(x, y, puntos, a, w, mirar)
    local fx, fy = math.cos(a), math.sin(a)
    local libre = mirar
    for k = 1, #puntos, 2 do
        local qx, qy = puntos[k] - x, puntos[k + 1] - y
        local delante = qx * fx + qy * fy
        if delante > 0 and delante < libre and math.abs(-qx * fy + qy * fx) < w then
            libre = delante
        end
    end
    return libre
end

function Obstaculos:onUpdate(dt)
    local d = self.datos.obstaculos
    -- 2. Parachoques (cada cuadro).
    local P = Obstaculos.parachoques
    local sensor = self.gestor.opciones.sensor
    local radio = Obstaculos.radio
    for _, z in ipairs(P.alturas) do
        for k = 0, P.rayos - 1 do
            local a = self.rumbo + k * 2 * math.pi / P.rayos
            local dist, tipo, dueno = sensor(self.x, self.y, z, a, radio + P.largo)
            if estorba(tipo) and dist < radio then
                local nx, ny = -math.cos(a), -math.sin(a)
                local dentro = radio - dist
                self.x, self.y = self.x + nx * dentro, self.y + ny * dentro
                -- Lo que iba contra ello se pierde.
                local contra = -(math.cos(self.rumbo) * nx + math.sin(self.rumbo) * ny)
                if contra > 0 and self.velocidad > 0 then
                    self.velocidad = self.velocidad * (1 - contra * 0.8)
                    d.choques = d.choques + 1
                    if os.getenv('OBSTACULOS_DEPURAR') then
                        local nombres = {}
                        for k2 in pairs(tipo) do
                            nombres[#nombres + 1] = k2
                        end
                        print(string.format('CHOQUE %s a %.1f m/s contra [%s] a %.2f m (altura %.1f) en %.1f, %.1f', self:getNombreTipo(), self.velocidad,
                            table.concat(nombres, ' '), dist, z, self.x, self.y))
                    end
                end
            end
        end
    end
    -- 1. Esquivar (unas veces por segundo).
    d.ahora = d.ahora + dt
    d.reloj = d.reloj - dt
    if d.reloj > 0 then
        return
    end
    d.reloj = Obstaculos.cada
    if not self.getRayos then
        return
    end
    -- Puntos donde chocaron los rayos con lo que estorba: los del último
    -- barrido y los recordados.
    local recuerdo, c = d.recuerdo, Obstaculos.celdaMemoria
    local hasta = d.ahora + Obstaculos.memoria
    for _, r in ipairs(self:getRayos()) do
        if r.choca and estorba(r.tipo) then
            local px, py = r.x + math.cos(r.angulo) * r.distancia, r.y + math.sin(r.angulo) * r.distancia
            local k = math.floor(px / c) * 1048576 + math.floor(py / c)
            local p = recuerdo[k]
            if p then
                p[3] = hasta
            else
                recuerdo[k] = { px, py, hasta }
            end
        end
    end
    local puntos = d.puntos
    for k = #puntos, 1, -1 do
        puntos[k] = nil
    end
    for k, p in pairs(recuerdo) do
        if p[3] < d.ahora then
            recuerdo[k] = nil
        else
            puntos[#puntos + 1] = p[1]
            puntos[#puntos + 1] = p[2]
        end
    end
    -- El rumbo que quiere: hacia el destino de la conducción o el suyo.
    local destino = self.datos.conduccion and self.datos.conduccion.destino
    local quiere = self.rumbo
    local lejos = math.huge
    if destino then
        local ex, ey = destino[1] - self.x, destino[2] - self.y
        quiere = math.atan2(ey, ex)
        lejos = math.sqrt(ex * ex + ey * ey)
    end
    local mirar = math.min(lejos, Obstaculos.mirar + math.max(0, self.velocidad) * 0.4)
    local w = radio + Obstaculos.holgura
    if #puntos == 0 or libreEn(self.x, self.y, puntos, quiere, w, mirar) >= mirar then
        d.desvio = d.desvio * 0.5
        d.frenar = nil
        return
    end
    -- El rumbo libre más cercano al que quiere (a un lado y al otro, hasta
    -- dar la vuelta: de un rincón se sale por detrás).
    local elegido, mejorLibre, masLibre, rumboMasLibre
    local paso = Obstaculos.pasoRumbo
    for k = 1, math.floor(math.pi / paso) do
        for _, s in ipairs({ 1, -1 }) do
            local a = quiere + s * k * paso
            local libre = libreEn(self.x, self.y, puntos, a, w, mirar)
            if libre >= mirar and not elegido then
                elegido, mejorLibre = a, libre
            end
            if not masLibre or libre > masLibre then
                masLibre, rumboMasLibre = libre, a
            end
        end
        if elegido then
            break
        end
    end
    elegido = elegido or rumboMasLibre
    mejorLibre = mejorLibre or masLibre
    d.desvio = angulo(elegido - quiere)
    -- Muy encima: más despacio, para que le dé tiempo a girar.
    d.frenar = mejorLibre < 4 and math.max(2, mejorLibre * 1.5) or nil
end

--- Giro (rad) que suma la conducción para rodear lo que tiene delante, y la
-- velocidad a la que frenar (o nil).
function Robot:getDesvio()
    local d = self.datos.obstaculos
    return d and d.desvio or 0, d and d.frenar
end

Nucleo.registrarEspecializacion('obstaculos', Obstaculos)
return Obstaculos

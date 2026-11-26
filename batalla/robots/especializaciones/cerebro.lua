-- Cerebro del robot, paso 1 (el dueño, 18-nov: «desarrollarles un cerebro»;
-- se prueba con el lanzamisiles, el del cañón en la cara): SENTIDOS Y MEMORIA.
--
-- Como el «Target Tracks Perception» de Game AI Pro: el robot solo sabe lo
-- que ve (nada de saberlo todo). Unas veces por segundo mira con la cabeza
-- (campo de vista y alcance como el soldado, rayo contra terreno, troncos y
-- rocas); a cada enemigo que ve le abre o refresca una «pista» en la
-- memoria: dónde estaba, cuándo lo vio y lo seguro que está (1 al verlo).
-- Sin volver a verlo, la seguridad baja con el tiempo y al final lo olvida.
--
-- Sin nada que hacer (la decisión llega en el paso 2), lee el panorama
-- girando la cabeza como el soldado (batalla/robots/mirada.lua).
--
-- Lo que sabe, en robot.datos.cerebro.memoria: lista de pistas
--   { robot, nombre, x, y, z, visto (reloj), seguridad 0-1, ahora (lo ve) }
--
-- Paso 2 (el dueño, 18-nov: «que guarde información y, según lo que
-- necesite saber, busque en esa rama»): además APRENDE de una batalla a otra
-- con su memoria propia en archivos (robots/conocimiento.lua). Ramas que usa:
--   yo                 batallas jugadas, lo más lejos que ha visto a alguien
--   mundo/<mapa>       dónde ha visto enemigos en este mapa (celdas de
--                      `celda` m, cuántas veces, en qué batalla)
--   enemigos/<tipo>    cuántas veces lo ha visto y a qué distancia media
--   experiencias       cada avistamiento
-- Al empezar consulta la rama de su mapa: lo que vio otras veces son
-- «sospechas» (pesan menos cuantas más batallas hace) y, mientras no ve a
-- nadie, echa ojeadas hacia ellas. El mapa lo pone la escena
-- (robot.mapaMemoria); el nombre de su memoria, robot.idMemoria o su nombre.

local Nucleo = require('robots.nucleo')
local Mundo = require('batalla.robots.mundo')
local Mirada = require('batalla.robots.mirada')
local Conocimiento = require('robots.conocimiento')

local Cerebro = {}

Cerebro.verCada = 0.15 -- s entre miradas
Cerebro.campoVista = math.rad(70) -- a cada lado de donde mira la cabeza
Cerebro.alcance = 150 -- m
Cerebro.olvidar = 25 -- s sin verlo hasta olvidarlo del todo
Cerebro.seguro = 3 -- s sin verlo en que aún está seguro del todo
Cerebro.celda = 10 -- m de las celdas de la memoria del mapa
Cerebro.olvidoBatallas = 0.7 -- lo que pesa un avistamiento por cada batalla que pasa
Cerebro.sospechaMinima = 0.5
Cerebro.ojeadaCada = 4 -- s entre ojeadas a lo que sabe de antes
Cerebro.ojeada = 1.5 -- s mirando

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Cerebro.prerequisitos(self)
    return self:getTienePieza('cabeza') and self.datos.asalto ~= nil
end

function Cerebro.onLoad(self)
    local c = self.datos.cerebro
    c.reloj, c.verReloj = 0, 0
    c.memoria = {}
end

--- Robots del otro bando (los de asalto con bando).
local function enemigos(self, bando)
    local lista = {}
    for _, r in ipairs(self.gestor:getRobots()) do
        local o = r.datos.asalto
        if r ~= self and o and o.bando and o.bando ~= bando then
            lista[#lista + 1] = r
        end
    end
    return lista
end

local function pista(c, r)
    for _, p in ipairs(c.memoria) do
        if p.robot == r then
            return p
        end
    end
end

-- Memoria aprendida (paso 2) -----------------------------------------------

local function claveCelda(x, y)
    return string.format('%d_%d', math.floor(x / Cerebro.celda), math.floor(y / Cerebro.celda))
end

--- Al empezar: abre su memoria, cuenta la batalla y saca las sospechas de
-- la rama de su mapa.
local function despertar(self, c, a)
    c.saber = Conocimiento.abrir(self.idMemoria or a.nombre or 'robot')
    c.rutaMapa = 'mundo/' .. (self.mapaMemoria or 'general')
    local yo = c.saber:rama('yo')
    yo.batallas = (yo.batallas or 0) + 1
    c.batalla = yo.batallas
    c.saber:cambio('yo')
    local mapa = c.saber:rama(c.rutaMapa)
    c.sospechas = {}
    for clave, v in pairs(mapa.avistamientos or {}) do
        local peso = v.veces * Cerebro.olvidoBatallas ^ (c.batalla - v.ultima)
        if peso >= Cerebro.sospechaMinima then
            c.sospechas[#c.sospechas + 1] = { x = v.x, y = v.y, tipo = v.tipo, veces = v.veces, peso = peso, clave = clave }
        end
    end
    table.sort(c.sospechas, function(p, q)
        return p.peso > q.peso
    end)
    c.anotados = {}
    c.ojeadaReloj, c.ojeadaIndice = 0.5, 0
    print(string.format('%s batalla %d: sabe de antes %d sitios con enemigos en %s', a.nombre or '?', c.batalla, #c.sospechas, c.rutaMapa))
end

--- Ve a `e`: lo apunta en su mapa (una vez por enemigo, celda y batalla), en
-- su tipo y en sus experiencias.
local function aprenderAvistamiento(self, c, e, x, y, dist)
    local clave = claveCelda(x, y)
    c.anotados[e] = c.anotados[e] or {}
    if c.anotados[e][clave] then
        return
    end
    c.anotados[e][clave] = true
    local tipo = e.tipo or '?'
    local mapa = c.saber:rama(c.rutaMapa)
    mapa.avistamientos = mapa.avistamientos or {}
    local v = mapa.avistamientos[clave]
    if not v then
        v = { veces = 0, tipo = tipo, x = x, y = y }
        mapa.avistamientos[clave] = v
    end
    v.veces, v.ultima, v.tipo = v.veces + 1, c.batalla, tipo
    c.saber:cambio(c.rutaMapa)
    local ruta = 'enemigos/' .. tipo
    local t = c.saber:rama(ruta)
    t.vistos = (t.vistos or 0) + 1
    t.distanciaMedia = ((t.distanciaMedia or dist) * (t.vistos - 1) + dist) / t.vistos
    c.saber:cambio(ruta)
    local yo = c.saber:rama('yo')
    yo.vistoMasLejos = math.max(yo.vistoMasLejos or 0, dist)
    c.saber:cambio('yo')
    c.saber:episodio({ batalla = c.batalla, t = c.reloj, que = 'vio', tipo = tipo, distancia = dist, celda = clave })
end

--- Una mirada: a quién ve ahora.
local function mirar(self, c, a)
    local ox, oy, oz = self:getPieza('cabeza'):getPunto(0.08, 0, 0.12)
    local mira = self.rumbo + (a.torso or 0) + (a.cabeza or 0)
    for _, p in ipairs(c.memoria) do
        p.ahora = false
    end
    for _, e in ipairs(enemigos(self, a.bando)) do
        local tx, ty, tz = e:getPieza('torso'):getPunto(0, 0, 0.25)
        local dx, dy, dz = tx - ox, ty - oy, tz - oz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        local fuera = math.abs(angulo(math.atan2(dy, dx) - mira))
        if dist < Cerebro.alcance and fuera < Cerebro.campoVista then
            local choque = Mundo.rayo(ox, oy, oz, dx, dy, dz, dist)
            if not choque or choque >= dist - 0.5 then
                local p = pista(c, e)
                if not p then
                    p = { robot = e, nombre = e.datos.asalto.nombre or '?' }
                    c.memoria[#c.memoria + 1] = p
                    print(string.format('%s t=%.1f s VE a %s a %.0f m', a.nombre or '?', c.reloj, p.nombre, dist))
                end
                p.x, p.y, p.z, p.visto, p.ahora, p.distancia = tx, ty, tz, c.reloj, true, dist
                aprenderAvistamiento(self, c, e, tx, ty, dist)
            end
        end
    end
end

function Cerebro.onUpdate(self, dt)
    local c = self.datos.cerebro
    local a = self.datos.asalto
    if not c.saber then
        despertar(self, c, a)
    end
    c.reloj = c.reloj + dt
    c.saber:actualizar(dt)
    c.verReloj = c.verReloj - dt
    if c.verReloj <= 0 then
        c.verReloj = Cerebro.verCada
        mirar(self, c, a)
    end
    -- La memoria se borra: seguro unos segundos, luego cada vez menos.
    for k = #c.memoria, 1, -1 do
        local p = c.memoria[k]
        local hace = c.reloj - p.visto
        p.hace = hace
        p.seguridad = math.max(0, math.min(1, 1 - (hace - Cerebro.seguro) / (Cerebro.olvidar - Cerebro.seguro)))
        if p.seguridad <= 0 then
            print(string.format('%s t=%.1f s OLVIDA a %s', a.nombre or '?', c.reloj, p.nombre))
            table.remove(c.memoria, k)
        end
    end
    -- Sin órdenes (asalto en 'esperar'): lee el panorama, como el soldado.
    -- Echa ojeadas a lo que sabe de antes (de una en una) mientras no ve a
    -- nadie allí.
    if a.estado == 'esperar' then
        local mirarA = Mirada.barrido(self.rumbo, c.reloj)
        c.ojeando = nil
        if #c.sospechas > 0 then
            c.ojeadaReloj = c.ojeadaReloj - dt
            if c.ojeadaReloj <= -Cerebro.ojeada then
                c.ojeadaReloj = Cerebro.ojeadaCada
                c.sospechaOjeada = nil
            elseif c.ojeadaReloj <= 0 then
                -- La siguiente sospecha donde no ve ahora a nadie.
                if not c.sospechaOjeada then
                    for k = 1, #c.sospechas do
                        c.ojeadaIndice = c.ojeadaIndice % #c.sospechas + 1
                        local s = c.sospechas[c.ojeadaIndice]
                        local yaLoVe = false
                        for _, p in ipairs(c.memoria) do
                            if p.ahora and (p.x - s.x) ^ 2 + (p.y - s.y) ^ 2 < 15 * 15 then
                                yaLoVe = true
                            end
                        end
                        if not yaLoVe then
                            c.sospechaOjeada = s
                            break
                        end
                    end
                    c.sospechaOjeada = c.sospechaOjeada or false
                end
                local s = c.sospechaOjeada
                if s then
                    mirarA = math.atan2(s.y - self.y, s.x - self.x)
                    c.ojeando = s
                end
            end
        end
        -- Decidido (el dueño, 18-nov: «no se decide, voltea de un lado a otro
        -- con el cañón»): con un blanco elegido por el lanzamisiles, la
        -- mirada y el torso se quedan en él, sin barrer ni echar ojeadas,
        -- mientras saca el cañón, dispara y lo guarda.
        local L = self.datos.lanzador
        local torso = 0
        if L and L.enemigo then
            mirarA = math.atan2(L.enemigo.y - self.y, L.enemigo.x - self.x)
            torso = (mirarA - self.rumbo + math.pi) % (2 * math.pi) - math.pi
            c.ojeando = nil
        end
        Mirada.girar(a, self.rumbo, mirarA, torso, dt)
    end
    -- `CEREBRO_TRAZA=1`: cada segundo, el giro de la cabeza.
    if os.getenv('CEREBRO_TRAZA') and math.floor(c.reloj) ~= math.floor(c.reloj - dt) then
        print(string.format('TRAZA t=%.0f cabeza=%.0f° estado=%s', c.reloj, math.deg(a.cabeza or 0), a.estado))
    end
end

Nucleo.registrarEspecializacion('cerebro', Cerebro)
return Cerebro

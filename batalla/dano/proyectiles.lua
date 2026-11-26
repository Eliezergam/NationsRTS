--- Proyectiles vivos de la batalla 3D (Valeria, batalla/DANO-REAL.md §3):
-- cada bala, obús, cohete o misil vuela con su trayectoria
-- (batalla/dano/trayectoria.lua) y choca donde de verdad llega.
--
--   tropas.balas     tiro directo: cañonazos, rebotes y los haces de las
--                    ráfagas de infantería (una trazadora por ráfaga)
--   tropas.misiles   cohetes y misiles que se dibujan (con su estela)
--   self.ocultos     los demás proyectiles de una salva: no se dibujan,
--                    pero vuelan y chocan igual
--
-- Al disparar se calcula una vez dónde acabaría en el terreno (eso da
-- `duracion`, lo que dura el vuelo para los efectos). En cada paso, el tramo
-- recorrido se prueba contra los árboles y rocas y contra los cuerpos de las
-- unidades y el edificio (batalla/dano/cuerpos.lua). Lo que pasa en cada
-- choque lo deciden blindaje.lua y explosiones.lua; lo que se ve (chispas,
-- efectos de Camila, sonido) lo pone la escena con `tropas:impacto` y
-- `tropas.efectos`.
--
-- Ráfaga de infantería (haz equivalente, §3.2): el haz vuela por la línea
-- central; cada bala lleva su desvío, sorteado al disparar. Si la línea
-- central da en un árbol, una roca o un cuerpo antes de llegar al blanco,
-- cada bala se prueba contra eso; las que pasan siguen. A `zonaAntes` del
-- blanco, cada bala se resuelve con un rayo hasta `zonaDespues` detrás: el
-- perfil del terreno, los árboles y rocas y los cuerpos de esa zona.

local Datos = require('batalla.dano.datos')
local Trayectoria = require('batalla.dano.trayectoria')
local Cuerpos = require('batalla.dano.cuerpos')
local Blindaje = require('batalla.dano.blindaje')
local Explosiones = require('batalla.dano.explosiones')
local Impactos = require('batalla.impactos')

local Proyectiles = {}
Proyectiles.__index = Proyectiles

Proyectiles.maxVivos = 1500 -- un haz cuenta uno; por encima se resuelve en el acto
Proyectiles.altoLibre = 400 -- px sobre el suelo: más alto no hay con qué chocar (salvo el edificio)
Proyectiles.esperaArboles = 0.4 -- s que un cohete vuela antes de mirar árboles (sale de entre ellos)
Proyectiles.pasoPerfil = 12 -- px entre muestras del perfil del terreno de un haz
Proyectiles.impactosVisibles = 3 -- balas de una ráfaga con su efecto de impacto
Proyectiles.distanciaCobertura = 80 -- px: una bala parada a menos de esto del blanco, cobertura

-- Cara del golpe por eje y signo de su normal (para las cuentas).
local CARAS = {
    [2] = 'caraTrasera',
    [3] = 'caraFrente',
    [4] = 'caraCostado',
    [5] = 'caraCostado',
    [6] = 'caraBajos',
    [7] = 'caraTecho',
}

function Proyectiles.nuevos(tropas)
    local self = setmetatable({}, Proyectiles)
    self.tropas = tropas
    self.ocultos = {}
    self.golpe = {}
    self.resultado = {}
    self.candidatos = {}
    self.plantas = {}
    self.perfil = {}
    return self
end

function Proyectiles:vivos()
    return #self.tropas.balas + #self.tropas.misiles + #self.ocultos
end

--- Tramos con que se busca el terreno a lo largo de `largo` px.
local function tramos(largo)
    return math.max(2, math.min(30, math.ceil(largo / 1500)))
end

-- Tiro directo -------------------------------------------------------------------------------

--- Pone a volar la bala `b` (con `tray`, una trayectoria directa, y
-- `alcance` px): busca dónde acabaría en el terreno y la mete en
-- `tropas.balas`.
function Proyectiles:lanzarDirecto(b)
    local t = self.tropas
    local tr = b.tray
    local tMax = Trayectoria.tiempoEn(tr, b.alcance)
    local tChoque, cx, cy, cz = Trayectoria.suelo(tr, t.suelo, Impactos.terreno, 0, tMax, tramos(b.alcance))
    if tChoque then
        b.duracion = math.max(1e-4, tChoque)
        b.x1, b.y1, b.z1 = cx, cy, cz
        b.superficie = 'terreno'
    else
        b.duracion = tMax
        b.x1, b.y1, b.z1 = Trayectoria.posicion(tr, tMax)
        b.superficie = nil -- se pierde a lo lejos
    end
    b.x0, b.y0, b.z0 = tr.x, tr.y, tr.z
    b.largo = math.sqrt((b.x1 - b.x0) ^ 2 + (b.y1 - b.y0) ^ 2 + (b.z1 - b.z0) ^ 2)
    b.inicio = t.reloj
    b.visto = 0
    b.arco = 0
    t.balas[#t.balas + 1] = b
    if self:vivos() > Proyectiles.maxVivos then
        t.estadisticas.resueltosEnElActo = t.estadisticas.resueltosEnElActo + 1
        self:resolverEnElActo(b, t.balas)
    end
    return b
end

--- Una bala hecha a mano (las pruebas: { x0..z1, duracion } en línea
-- recta): se le pone una trayectoria recta de la misma duración.
function Proyectiles:adoptar(b)
    local dx, dy, dz = b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0
    local largo = math.max(1e-6, math.sqrt(dx * dx + dy * dy + dz * dz))
    b.tray = Trayectoria.directa(b.x0, b.y0, b.z0, dx / largo, dy / largo, dz / largo, largo / b.duracion, 0, 0)
    b.clase = b.clase or (b.canon and 'perforante' or 'bala')
    b.pen0 = b.pen0 or 0
    b.visto = 0
    b.superficie = b.superficie or 'terreno'
end

--- Vuela entero en este instante (demasiados proyectiles vivos).
function Proyectiles:resolverEnElActo(p, lista)
    local paso = 1 / 60
    local inicio = p.inicio
    local reloj = inicio
    local fin = false
    while not fin and reloj - inicio < p.duracion + paso do
        reloj = reloj + paso
        if p.tray.tipo == 'directa' then
            fin = self:pasoDirecto(p, reloj, true)
        else
            fin = self:pasoIndirecto(p, reloj)
        end
    end
    for k = #lista, 1, -1 do
        if lista[k] == p then
            table.remove(lista, k)
            break
        end
    end
end

--- ¿Puede chocar algo en el tramo que acaba a altura `z` sobre (x, y)?
function Proyectiles:alto(x, y, z)
    local t = self.tropas
    if z - t.suelo:altura(x, y) < Proyectiles.altoLibre then
        return false
    end
    local e = t.cuerpos.edificio
    if e and (x - e.x) ^ 2 + (y - e.y) ^ 2 < (e.radio + 200) ^ 2 then
        return false
    end
    return true
end

--- Primer choque del tramo (x0..z1) con un árbol o roca (salvo `ignorarPlanta`)
-- o un cuerpo (salvo `salvo` e `ignorar`): { t, x, y, z, planta | golpe }
-- en `self.resultado`, o nil.
function Proyectiles:tramo(x0, y0, z0, x1, y1, z1, salvo, ignorar, ignorarPlanta, sinArboles)
    local t = self.tropas
    local mejorT, planta = math.huge, nil
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    if not sinArboles then
        local lista = Impactos.plantasCerca(t.suelo, x0, y0, x1, y1, 100, self.plantas)
        if lista then
            for _, p in ipairs(lista) do
                if p ~= ignorarPlanta then
                    local tp = Impactos.cruzarPlanta(t.suelo, p, x0, y0, z0, dx, dy, dz)
                    if tp and tp < mejorT then
                        mejorT, planta = tp, p
                    end
                end
            end
        end
    end
    local candidatos = t.cuerpos:candidatos(x0, y0, x1, y1, 0, salvo, self.candidatos)
    local golpe
    if #candidatos > 0 then
        if ignorar then
            local n = 0
            for _, c in ipairs(candidatos) do
                if c ~= ignorar then
                    n = n + 1
                    candidatos[n] = c
                end
            end
            for k = n + 1, #candidatos do
                candidatos[k] = nil
            end
        end
        golpe = Cuerpos.cruzar(candidatos, x0, y0, z0, x1, y1, z1, self.golpe)
    end
    local r = self.resultado
    if golpe and golpe.t <= mejorT then
        r.t, r.golpe, r.planta = golpe.t, golpe, nil
    elseif planta then
        r.t, r.golpe, r.planta = mejorT, nil, planta
    else
        return nil
    end
    r.x, r.y, r.z = x0 + dx * r.t, y0 + dy * r.t, z0 + dz * r.t
    return r
end

--- Avanza la bala `b` hasta el instante `reloj`. Devuelve true si se acabó.
function Proyectiles:pasoDirecto(b, reloj, enElActo)
    if not b.tray then
        self:adoptar(b)
    end
    local transcurrido = reloj - b.inicio
    if b.resuelto then
        if transcurrido >= b.duracion then
            self:llegadaVisual(b)
            return true
        end
        return false
    end
    local t1 = math.min(transcurrido, b.duracion)
    local t0 = b.visto
    if t1 <= t0 then
        return false
    end
    local haz = b.haz
    if haz and t1 >= haz.tZona then
        t1 = haz.tZona
    end
    local x0, y0, z0 = Trayectoria.posicionDirecta(b.tray, t0)
    local x1, y1, z1 = Trayectoria.posicionDirecta(b.tray, t1)
    local choque
    if not (self:alto(x0, y0, z0) and self:alto(x1, y1, z1)) then
        choque = self:tramo(x0, y0, z0, x1, y1, z1, b.autor, b.ignorar, b.ignorarPlanta)
    end
    if choque then
        local tChoque = t0 + (t1 - t0) * choque.t
        if haz then
            return self:obstaculoHaz(b, choque, tChoque)
        end
        return self:chocarDirecto(b, choque, tChoque)
    end
    b.visto = t1
    if haz and t1 >= haz.tZona then
        self:resolverHaz(b)
        if enElActo then
            return true
        end
        return false
    end
    if t1 >= b.duracion then
        self:llegadaSuelo(b)
        return true
    end
    return false
end

--- Efecto visible de un impacto pequeño en (x, y, z) contra `superficie`.
function Proyectiles:verImpacto(b, x, y, z, superficie, fuerte)
    local t = self.tropas
    t:impacto(x, y, z, fuerte, false, b.escalaImpacto or 1.5)
    if t.efectos then -- Efectos (Camila)
        local x1, y1, z1 = b.x1, b.y1, b.z1
        b.x1, b.y1, b.z1 = x, y, z
        t.efectos:impactoBala(b, x, y, z, superficie)
        b.x1, b.y1, b.z1 = x1, y1, z1
    end
end

--- La bala llega a su punto en el terreno (o se pierde a lo lejos).
function Proyectiles:llegadaSuelo(b)
    local t = self.tropas
    t.estadisticas.impactoTerreno = t.estadisticas.impactoTerreno + 1
    if b.haz then
        -- La ráfaga entera da en una loma antes de llegar a su blanco.
        t.estadisticas.hazBloqueado = t.estadisticas.hazBloqueado + 1
    end
    if not b.superficie then
        return
    end
    if b.clase == 'explosiva' then
        self:explotar(b, b.x1, b.y1, b.z1, 'terreno')
        return
    end
    self:verImpacto(b, b.x1, b.y1, b.z1, 'terreno', b.fuerteImpacto or false)
end

--- La trazadora de un haz ya resuelto llega a su final: solo lo que se ve.
function Proyectiles:llegadaVisual(b)
    if b.superficie then
        self:verImpacto(b, b.x1, b.y1, b.z1, b.superficie, false)
    end
end

--- Un obús explosivo estalla en (x, y, z).
function Proyectiles:explotar(b, x, y, z, superficie)
    local t = self.tropas
    t:impacto(x, y, z, true, true, 0.9)
    if t.efectos then
        t.efectos:impactoBala(b, x, y, z, superficie)
    end
    Explosiones.estallar(t, x, y, z, b.ojiva)
end

--- Termina la bala `b` en el choque `c` (en el instante `tChoque`).
-- Devuelve true si se acabó.
function Proyectiles:chocarDirecto(b, c, tChoque)
    local t = self.tropas
    local est = t.estadisticas
    local x, y, z = c.x, c.y, c.z
    b.visto = tChoque
    if c.planta then
        local superficie = c.planta.roca and 'roca' or 'arbol'
        local clave = c.planta.roca and 'impactoRoca' or 'impactoArbol'
        est[clave] = est[clave] + 1
        if b.clase ~= 'bala' and not c.planta.roca then
            -- Un proyectil de cañón derriba el árbol que alcanza.
            local vx, vy = Trayectoria.velocidadDirecta(b.tray, tChoque)
            t.suelo:derribarArbol(c.planta, vx, vy, false)
        end
        self:terminar(b, x, y, z, tChoque)
        if b.clase == 'explosiva' then
            self:explotar(b, x, y, z, superficie)
        else
            self:verImpacto(b, x, y, z, superficie, b.clase ~= 'bala')
        end
        return true
    end
    local g = c.golpe
    local u = g.u
    if not u then
        est.impactoEdificio = est.impactoEdificio + 1
        self:terminar(b, x, y, z, tChoque)
        if b.clase == 'explosiva' then
            self:explotar(b, x, y, z, 'roca')
        else
            self:verImpacto(b, x, y, z, 'roca', b.clase ~= 'bala')
        end
        return true
    end
    -- Un vehículo.
    est.impactoVehiculo = est.impactoVehiculo + 1
    local vx, vy, vz = Trayectoria.velocidadDirecta(b.tray, tChoque)
    local v = math.sqrt(vx * vx + vy * vy + vz * vz)
    local r = self:golpeVehiculo(b, u, g, b.pen0 * (v / b.tray.v0) ^ Datos.perforante.exponente)
    self:terminar(b, x, y, z, tChoque)
    if r == 'rebote' and (b.rebotes or 0) == 0 and b.clase ~= 'bala' then
        self:rebotar(b, g, x, y, z, vx, vy, vz, v)
    end
    if b.clase == 'explosiva' then
        self:explotar(b, x, y, z, 'vehiculo')
    else
        self:verImpacto(b, x, y, z, 'vehiculo', b.clase ~= 'bala')
    end
    return true
end

--- Golpe de la bala `b` con penetración `pen` en el vehículo `u`.
function Proyectiles:golpeVehiculo(b, u, g, pen)
    local t = self.tropas
    if u.muerto or not u.averias then
        return 'nopenetra'
    end
    local clase = b.clase
    local datos = { clase = clase, pen = pen, rebote = b.rebote }
    local r = Blindaje.golpe(u, g, datos, t.azar, {})
    local est = t.estadisticas
    est[r.efecto] = est[r.efecto] + 1
    if clase ~= 'bala' then
        est['golpe' .. r.zona] = (est['golpe' .. r.zona] or 0) + 1
        local cara = CARAS[g.eje * 2 + (g.signo > 0 and 1 or 0)]
        est[cara] = (est[cara] or 0) + 1
        r.cara = cara
        r.tirador = b.autor
        t:anotarEvento(r.efecto, g.x, g.y, g.z, u, r)
    end
    t:revisarVehiculo(u)
    return r.efecto
end

--- La bala acaba en (x, y, z) en el instante `tChoque` (para los efectos).
function Proyectiles:terminar(b, x, y, z, tChoque)
    b.x1, b.y1, b.z1 = x, y, z
    b.duracion = math.max(1e-4, tChoque)
end

--- Rebote: un proyectil nuevo sale reflejado en la cara del golpe `g` con
-- parte de su velocidad, y puede dar en otra cosa.
function Proyectiles:rebotar(b, g, x, y, z, vx, vy, vz, v)
    local m = g.pieza.m
    local e = g.eje
    local nx, ny, nz = m[e] * g.signo, m[4 + e] * g.signo, m[8 + e] * g.signo
    local ux, uy, uz = vx / v, vy / v, vz / v
    local p = ux * nx + uy * ny + uz * nz
    ux, uy, uz = ux - 2 * p * nx, uy - 2 * p * ny, uz - 2 * p * nz
    local t = self.tropas
    local nueva = {
        tray = Trayectoria.directa(
            x + ux * 3,
            y + uy * 3,
            z + uz * 3,
            ux,
            uy,
            uz,
            v * Datos.rebote.velocidad,
            b.tray.k,
            b.tray.g
        ),
        alcance = 15000,
        clase = b.clase,
        pen0 = b.pen0 * 0.5,
        rebote = b.rebote,
        rebotes = 1,
        autor = g.u,
        bando = b.bando,
        canon = b.canon,
        trazador = b.trazador,
        escalaImpacto = b.escalaImpacto,
        ojiva = b.ojiva,
        rebotada = true,
    }
    t.estadisticas.rebotesVolando = t.estadisticas.rebotesVolando + 1
    self:lanzarDirecto(nueva)
end

-- Ráfagas de infantería (haz) ------------------------------------------------------------------

--- Posición en el recorrido `s` (px) de la bala `j` del haz de `b`.
local function posicionBala(b, j, s)
    local haz = b.haz
    local t = Trayectoria.tiempoEn(b.tray, s)
    local x, y, z = Trayectoria.posicionDirecta(b.tray, t)
    local lateral = haz.ex[j] * s
    return x + haz.lx * lateral, y + haz.ly * lateral, z + haz.ez[j] * s
end

--- Aplica la bala `j` del haz de `b` (con su peso) al choque `c`.
function Proyectiles:aplicarBala(b, j, c, x, y, z)
    local t = self.tropas
    local est = t.estadisticas
    local haz = b.haz
    local peso = haz.peso
    local cuantas = math.floor(peso)
    if t.azar:random() < peso - cuantas then
        cuantas = cuantas + 1
    end
    local superficie
    if c.planta then
        superficie = c.planta.roca and 'roca' or 'arbol'
        est.balaCobertura = est.balaCobertura + cuantas
        self:anotarCobertura(b, x, y, z, superficie)
    elseif c.golpe and not c.golpe.u then
        superficie = 'roca'
        est.balaCobertura = est.balaCobertura + cuantas
        self:anotarCobertura(b, x, y, z, 'edificio')
    elseif c.golpe then
        local g = c.golpe
        local u = g.u
        superficie = 'vehiculo'
        est.balaVehiculo = est.balaVehiculo + cuantas
        if u ~= haz.blanco then
            self:anotarCobertura(b, x, y, z, 'vehiculo')
        end
        local d = math.sqrt((x - b.x0) ^ 2 + (y - b.y0) ^ 2)
        local vx, vy, vz = Trayectoria.velocidadDirecta(b.tray, Trayectoria.tiempoEn(b.tray, d))
        local v = math.sqrt(vx * vx + vy * vy + vz * vz)
        local pen = b.pen0 * (v / b.tray.v0) ^ Datos.perforante.exponente
        for _ = 1, cuantas do
            self:golpeVehiculo(b, u, g, pen)
        end
    else
        superficie = 'terreno'
        est.balaTerreno = est.balaTerreno + cuantas
        self:anotarCobertura(b, x, y, z, 'terreno')
    end
    if haz.vistos < Proyectiles.impactosVisibles then
        haz.vistos = haz.vistos + 1
        self:verImpacto(b, x, y, z, superficie, false)
    end
    return superficie
end

--- Una bala parada cerca de su blanco: el blanco estaba a cubierto.
function Proyectiles:anotarCobertura(b, x, y, z, que)
    local blanco = b.haz.blanco
    if not blanco then
        return
    end
    local d = math.sqrt((blanco.x - x) ^ 2 + (blanco.y - y) ^ 2)
    if d < Proyectiles.distanciaCobertura then
        self.tropas.estadisticas.cubiertos = self.tropas.estadisticas.cubiertos + 1
        self.tropas:anotarEvento('cubierto', x, y, z, blanco, { que = que, tirador = b.autor })
    end
end

--- La línea central del haz da en un árbol, una roca o un cuerpo antes de
-- la zona del blanco: cada bala viva se prueba contra eso; las que pasan
-- siguen (y el haz ya no vuelve a chocar con ello).
function Proyectiles:obstaculoHaz(b, c, tChoque)
    local haz = b.haz
    self.tropas.estadisticas.hazObstaculo = self.tropas.estadisticas.hazObstaculo + 1
    local s = math.sqrt((c.x - b.x0) ^ 2 + (c.y - b.y0) ^ 2 + (c.z - b.z0) ^ 2)
    local planta = c.planta
    local cuerpo = c.golpe and c.golpe.cuerpo
    local unaLista = self.unaLista or {}
    self.unaLista = unaLista
    unaLista[1] = cuerpo
    local golpe = {}
    local primera
    for j = 1, haz.rayos do
        if haz.vivo[j] then
            local ax, ay, az = posicionBala(b, j, math.max(0, s - 50))
            local bx, by, bz = posicionBala(b, j, s + 50)
            local tj
            local cj = {}
            if planta then
                tj = Impactos.cruzarPlanta(self.tropas.suelo, planta, ax, ay, az, bx - ax, by - ay, bz - az)
                cj.planta = planta
            else
                local g = Cuerpos.cruzar(unaLista, ax, ay, az, bx, by, bz, golpe)
                if g then
                    tj = g.t
                    cj.golpe = g
                end
            end
            if tj then
                local x, y, z = ax + (bx - ax) * tj, ay + (by - ay) * tj, az + (bz - az) * tj
                haz.vivo[j] = false
                haz.quedan = haz.quedan - 1
                self:aplicarBala(b, j, cj, x, y, z)
                primera = primera or { x, y, z }
                golpe = {}
            end
        end
    end
    if haz.quedan <= 0 then
        local p = primera or { c.x, c.y, c.z }
        self:terminar(b, p[1], p[2], p[3], tChoque)
        return true
    end
    -- Las que quedan siguen: el haz ya no choca con esto.
    b.visto = tChoque
    if planta then
        b.ignorarPlanta = planta
    else
        b.ignorar = cuerpo
    end
    return false
end

--- Perfil del terreno a lo largo de la línea central del haz de `b`, de
-- `s0` a `s1` px: holgura de la línea sobre el suelo cada `pasoPerfil` px.
function Proyectiles:perfilHaz(b, s0, s1)
    local perfil = self.perfil
    local suelo = self.tropas.suelo
    local paso = Proyectiles.pasoPerfil
    local n = math.max(1, math.ceil((s1 - s0) / paso))
    for k = 0, n do
        local s = s0 + (s1 - s0) * k / n
        local x, y, z = Trayectoria.posicionDirecta(b.tray, Trayectoria.tiempoEn(b.tray, s))
        perfil[k * 2 + 1] = s
        perfil[k * 2 + 2] = z - suelo:altura(x, y)
    end
    perfil.n = n
    return perfil
end

--- Primer recorrido (de `s0` a `s1`) en que la bala `j` pasa bajo el perfil, o nil.
local function cortePerfil(perfil, ez)
    local anteriorS, anteriorH
    for k = 0, perfil.n do
        local s = perfil[k * 2 + 1]
        local h = perfil[k * 2 + 2] + ez * s
        if h < 0 then
            if not anteriorS then
                return s
            end
            local f = anteriorH / (anteriorH - h)
            return anteriorS + (s - anteriorS) * f
        end
        anteriorS, anteriorH = s, h
    end
    return nil
end

--- El haz de `b` llega a la zona de su blanco: cada bala viva se resuelve
-- con un rayo desde `zonaAntes` hasta `zonaDespues` detrás del blanco.
function Proyectiles:resolverHaz(b)
    local t = self.tropas
    local haz = b.haz
    haz.resuelto = true
    b.resuelto = true
    local s0, s1 = haz.sZona, haz.sFin
    local ax, ay = Trayectoria.posicionDirecta(b.tray, Trayectoria.tiempoEn(b.tray, s0))
    local bx, by = Trayectoria.posicionDirecta(b.tray, Trayectoria.tiempoEn(b.tray, s1))
    local candidatos = t.cuerpos:candidatos(ax, ay, bx, by, 60, b.autor, self.candidatos)
    if b.ignorar then
        for k = #candidatos, 1, -1 do
            if candidatos[k] == b.ignorar then
                table.remove(candidatos, k)
            end
        end
    end
    local plantas = Impactos.plantasCerca(t.suelo, ax, ay, bx, by, 100, self.plantas) or {}
    local perfil = self:perfilHaz(b, s0, s1)
    local golpe = {}
    local final
    for j = 1, haz.rayos do
        if haz.vivo[j] then
            t.estadisticas.rayosBala = t.estadisticas.rayosBala + 1
            local x0, y0, z0 = posicionBala(b, j, s0)
            local x1, y1, z1 = posicionBala(b, j, s1)
            local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
            local mejorT, c = math.huge, nil
            local sTerreno = cortePerfil(perfil, haz.ez[j])
            if sTerreno then
                mejorT = (sTerreno - s0) / (s1 - s0)
                c = { terreno = true }
            end
            for _, p in ipairs(plantas) do
                if p ~= b.ignorarPlanta then
                    local tp = Impactos.cruzarPlanta(t.suelo, p, x0, y0, z0, dx, dy, dz)
                    if tp and tp < mejorT then
                        mejorT, c = tp, { planta = p }
                    end
                end
            end
            if #candidatos > 0 then
                local g = Cuerpos.cruzar(candidatos, x0, y0, z0, x1, y1, z1, golpe)
                if g and g.t < mejorT then
                    mejorT, c = g.t, { golpe = g }
                    golpe = {}
                end
            end
            if c then
                local x, y, z = x0 + dx * mejorT, y0 + dy * mejorT, z0 + dz * mejorT
                local superficie = self:aplicarBala(b, j, c, x, y, z)
                if not final then
                    final = { x, y, z, s0 + (s1 - s0) * mejorT, superficie }
                end
            end
        end
    end
    -- La trazadora acaba donde dio la primera bala que dio en algo; si
    -- ninguna, donde cae la línea central.
    if final then
        b.x1, b.y1, b.z1 = final[1], final[2], final[3]
        b.duracion = Trayectoria.tiempoEn(b.tray, final[4])
        b.superficie = nil -- su efecto ya se puso
    end
end

-- Tiro indirecto -----------------------------------------------------------------------------

--- Pone a volar el cohete o misil `m` (con `tray`, una trayectoria
-- indirecta, y `vuelo`, su tiempo hasta el punto de caída) en `lista`;
-- `visible` si se dibuja.
function Proyectiles:lanzarIndirecto(m, vuelo, lista, visible)
    local t = self.tropas
    local tChoque, cx, cy, cz = Trayectoria.suelo(m.tray, t.suelo, Impactos.terreno, 0, vuelo * 1.3, 24)
    if tChoque then
        m.duracion = math.max(1e-3, tChoque)
        m.x1, m.y1, m.z1 = cx, cy, cz
    else
        m.duracion = vuelo
        m.x1, m.y1, m.z1 = Trayectoria.posicionIndirecta(m.tray, vuelo)
    end
    m.superficie = 'terreno'
    m.inicio = t.reloj
    m.visto = 0
    -- Mientras va por encima de todo (suelo más alto del camino más
    -- `altoLibre` y el edificio), no se buscan choques.
    local techo = (m.tray.sueloMaximo or m.z1) + Proyectiles.altoLibre + 300
    local e = t.cuerpos.edificio
    if e then
        techo = math.max(techo, t.suelo:altura(e.x, e.y) + 1200)
    end
    m.libreDesde, m.libreHasta = Trayectoria.porEncima(m.tray, techo)
    lista[#lista + 1] = m
    -- El que se dibuja (con su estela) vuela siempre.
    if not visible and self:vivos() > Proyectiles.maxVivos then
        t.estadisticas.resueltosEnElActo = t.estadisticas.resueltosEnElActo + 1
        self:resolverEnElActo(m, lista)
    end
    return m
end

--- Avanza el cohete `m` hasta `reloj`. Devuelve true si estalló.
function Proyectiles:pasoIndirecto(m, reloj)
    local t1 = math.min(reloj - m.inicio, m.duracion)
    local t0 = m.visto
    if t1 <= t0 then
        return false
    end
    m.visto = t1
    if m.libreDesde and t0 >= m.libreDesde and t1 <= m.libreHasta then
        -- Por encima de todo: nada con qué chocar.
        if t1 >= m.duracion then
            self:estallarIndirecto(m)
            return true
        end
        return false
    end
    local x0, y0, z0 = Trayectoria.posicionIndirecta(m.tray, t0)
    local x1, y1, z1 = Trayectoria.posicionIndirecta(m.tray, t1)
    local choque
    if not (self:alto(x0, y0, z0) and self:alto(x1, y1, z1)) then
        choque = self:tramo(x0, y0, z0, x1, y1, z1, m.autor, nil, nil, t0 < Proyectiles.esperaArboles)
    end
    if choque then
        local tChoque = t0 + (t1 - t0) * choque.t
        m.x1, m.y1, m.z1 = choque.x, choque.y, choque.z
        m.duracion = math.max(1e-3, tChoque)
        if choque.planta then
            m.superficie = choque.planta.roca and 'roca' or 'arbol'
            if not choque.planta.roca then
                local vx, vy = Trayectoria.velocidadIndirecta(m.tray, tChoque)
                self.tropas.suelo:derribarArbol(choque.planta, vx, vy, true)
            end
        elseif choque.golpe.u then
            m.superficie = 'vehiculo'
            self:golpeOjiva(m, choque.golpe, tChoque)
        else
            m.superficie = 'roca'
        end
        self:estallarIndirecto(m)
        return true
    end
    if t1 >= m.duracion then
        self:estallarIndirecto(m)
        return true
    end
    return false
end

--- Golpe directo de la ojiva de `m` en un vehículo: penetra como un proyectil.
function Proyectiles:golpeOjiva(m, g, tChoque)
    local u = g.u
    local t = self.tropas
    if u.muerto or not u.averias then
        return
    end
    local r = Blindaje.golpe(u, g, { clase = 'ojiva', pen = m.ojiva.pen, rebote = Datos.explosiva.rebote }, t.azar, {})
    local est = t.estadisticas
    est[r.efecto] = est[r.efecto] + 1
    est.golpeDirectoOjiva = est.golpeDirectoOjiva + 1
    t:anotarEvento(r.efecto, g.x, g.y, g.z, u, r)
    t:revisarVehiculo(u)
    m.tChoque = tChoque
end

--- El cohete o misil `m` estalla en su punto.
function Proyectiles:estallarIndirecto(m)
    local t = self.tropas
    t.estadisticas.explosiones = t.estadisticas.explosiones + 1
    t:estallarMisil(m)
    Explosiones.estallar(t, m.x1, m.y1, m.z1, m.ojiva)
end

-- Cada paso ----------------------------------------------------------------------------------

--- Avanza todos los proyectiles hasta el reloj de la pelea (después de
-- mover las unidades y rehacer los cuerpos), por `tropas:chocarBala` y
-- `tropas:chocarMisil` (las pruebas de efectos los cronometran).
function Proyectiles:avanzar()
    local t = self.tropas
    local balas = t.balas
    for k = #balas, 1, -1 do
        local b = balas[k]
        if b and t:chocarBala(b) then
            for i = k, #balas do
                if balas[i] == b then
                    table.remove(balas, i)
                    break
                end
            end
        end
    end
    for _, lista in ipairs({ t.misiles, self.ocultos }) do
        for k = #lista, 1, -1 do
            local m = lista[k]
            if t:chocarMisil(m) then
                table.remove(lista, k)
            end
        end
    end
end

return Proyectiles

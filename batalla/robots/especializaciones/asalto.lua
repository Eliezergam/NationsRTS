-- Asalto del robot soldado en la batalla 3D (el dueño, 18-nov: «dos robots
-- enfrentándose que traen rutas y tomen la mejor y avancen estratégicamente;
-- cuando se vean, se disparan; sin vida aún»).
--
-- 1. Rutas. Al recibir la orden (robot:setAsalto) traza tres rutas hacia el
--    objetivo sobre una rejilla de `celda` m: por la izquierda, por el centro
--    y por la derecha (A*, cada una obligada a pasar por su punto de paso).
--    El coste de cada tramo sube con la pendiente y, sobre todo, con lo
--    expuesto que queda: desde donde está el enemigo, ¿se ve esa celda? (un
--    rayo contra el mundo físico). Baja un poco junto a lo que tiene la
--    etiqueta `cobertura`. Elige la de menos coste y lo dice.
-- 2. Avance a saltos: corre de una cobertura a la siguiente (cualquier cosa
--    con la etiqueta `cobertura`, poniéndose detrás según de dónde viene el
--    enemigo, o un sitio que el enemigo no ve), se para unos segundos y
--    vigila hacia el enemigo girando la cabeza; luego, el siguiente salto.
-- 3. Contacto: mira con la cabeza hacia delante (`campoVista`); si ve al
--    enemigo sin nada en medio, se para, se gira hacia él, apunta la
--    metralleta con un lazo cerrado (como combate.lua) y dispara ráfagas.
--    Cada bala es un rayo contra el mundo (batalla/robots/mundo.lua) y contra
--    las zonas de los robots (impactos.lua): si le da, el otro reacciona. Tras
--    unas ráfagas, si aún está lejos, salta a la siguiente cobertura hacia él
--    y vuelve a disparar. Si lo pierde de vista, sigue su ruta.
--
-- Sin vida: las balas empujan pero no rompen.
--
-- Órdenes:
--   robot:setAsalto(bando, x, y)   avanzar hacia (x, y) m como `bando`
--   robot:getAsalto()             los datos (rutas, estado) para dibujarlos

local Nucleo = require('robots.nucleo')
local Mundo = require('batalla.robots.mundo')
local Colisiones = require('batalla.colisiones')

local cercanas = {}
local Mirada = require('batalla.robots.mirada')
local Robot = Nucleo.Robot

local Asalto = {}

Asalto.celda = 4 -- m de la rejilla de rutas
Asalto.margen = 70 -- m a cada lado de la línea recta
Asalto.celdaLejos = 8 -- m, con el objetivo a más de 400 m
Asalto.margenLejos = 0.45 -- del largo, a cada lado, de lejos
Asalto.desvio = 45 -- m: lo que se abren las rutas de los flancos
Asalto.pendienteMaxima = 24 -- grados
Asalto.costeExpuesto = 2.5 -- cada metro que el enemigo ve cuesta 1 + esto
Asalto.costePendiente = 1 / 12 -- por grado
Asalto.premioCobertura = 0.3 -- junto a algo con la etiqueta `cobertura`
Asalto.coberturaRadio = 4 -- m
-- Sin paradas (el dueño, 19-nov: «se detiene muchas veces, ¿acaso no puede
-- ir corriendo y calculando al mismo tiempo y revisando el panorama?»):
-- corre de un tirón vigilando con la cabeza; `conParadas` las vuelve a poner.
Asalto.conParadas = false
Asalto.paradaCada = 32 -- m mínimos entre paradas (corriendo tan rápido, cada 2-3 s)
Asalto.paradaTiempo = { 1.8, 3.2 } -- s parado vigilando
Asalto.velocidad = 14 -- m/s corriendo de cobertura en cobertura (50 km/h)
Asalto.alcanceVista = 120
Asalto.campoVista = math.rad(70) -- a cada lado de donde mira la cabeza
Asalto.verCada = 0.15 -- s entre miradas
Asalto.perder = 3 -- s sin verlo: sigue la ruta
Asalto.alcanceTiro = 100
Asalto.cadencia = 12
Asalto.rafaga = { 0.35, 0.7 }
Asalto.pausaRafaga = { 0.45, 0.9 }
Asalto.rafagasAntesDeMoverse = { 3, 5 }
Asalto.distanciaMinima = 20 -- m: más cerca ya no avanza
Asalto.replanificarCada = 8 -- s como poco entre rutas nuevas
Asalto.esperaAlLlegar = 3 -- s al final de la ruta antes de ir a por él
Asalto.dispersion = math.rad(0.8)
Asalto.dispersionPorMetro = math.rad(0.05)
Asalto.dispersionMaxima = math.rad(5)
Asalto.apuntado = math.rad(5)
Asalto.ladoMax = math.rad(35)
Asalto.arribaMax = math.rad(40)
Asalto.cabezaMax = math.rad(75)
Asalto.giroTambor = 40
Asalto.arranqueTambor = 0.25
Asalto.boca = 0.32
Asalto.trazadora = 0.06
-- Recorrer el campo (el dueño, 18-nov: «que corra por todo el mapa de un lado
-- a otro, por distintos lugares; que le dispare al otro pero que siga
-- corriendo»).
Asalto.destinoMinimo = 120 -- m del siguiente destino, como poco
Asalto.destinoMaximo = 380
Asalto.recordarDestinos = 4 -- los últimos destinos que evita repetir
-- Pasadas: a menudo elige un sitio al otro lado del enemigo, para pasarle
-- por al lado corriendo y dispararle al pasar (se oyen: sabe dónde anda).
Asalto.pasada = 0.6 -- probabilidad
Asalto.pasadaMas = { 60, 160 } -- m más allá de él
Asalto.pasadaLado = 45 -- m a un lado, como mucho
-- Corriendo por el campo va a buscarlo: que lo vea el enemigo apenas cuesta
-- y mira mucho más a los lados y más lejos.
Asalto.costeExpuestoRecorrer = 0.3
Asalto.campoVistaRecorrer = math.rad(110)
Asalto.alcanceVistaRecorrer = 150
Asalto.alcanceTiroRecorrer = 150
Asalto.apuntadoRecorrer = math.rad(9) -- corriendo, dispara con más error
Asalto.torsoMax = math.rad(80) -- lo que gira el torso para disparar corriendo
Asalto.dispersionCorriendo = math.rad(0.12) -- de más por cada m/s

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function azar(r)
    return r[1] + love.math.random() * (r[2] - r[1])
end

-- Sin metralleta (el lanzamisiles) corre y busca igual; dispara su arma
-- otra especialización (lanzador.lua) con lo que este averigua.
function Asalto:prerequisitos()
    return self:getTienePieza('cabeza')
end

function Asalto:onLoad()
    local d = self.datos.asalto
    d.estado = 'esperar'
    d.reloj = 0
    d.lado, d.arriba, d.cabeza = 0, 0, 0
    d.tambor, d.vTambor, d.retroceso = 0, 0, 0
    d.disparos, d.chispas = {}, {}
    d.balas, d.aciertos = 0, 0
    d.verReloj = 0
end

-- Puntos del cuerpo ----------------------------------------------------------

local function ojo(self)
    return self:getPieza('cabeza'):getPunto(0.08, 0, 0.12)
end

local function pecho(r)
    return r:getPieza('torso'):getPunto(0, 0, 0.25)
end

local function boca(self)
    local c = self.piezas.canones
    local m = c and c:getMatriz()
    if not m then
        return nil
    end
    local x, y, z = c:getPunto(Asalto.boca, 0, 0)
    return x, y, z, m[1], m[5], m[9]
end

--- ¿Ve (x, y, z) desde (ox, oy, oz) sin nada sólido en medio?
local function despejado(ox, oy, oz, x, y, z)
    local dx, dy, dz = x - ox, y - oy, z - oz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local choque = Mundo.rayo(ox, oy, oz, dx, dy, dz, dist)
    return not choque or choque >= dist - 0.5, dist
end

-- Rutas ----------------------------------------------------------------------

-- Rejilla en los ejes de la línea recta: u hacia el objetivo, v a la izquierda.
local function rejilla(self, d)
    local x0, y0 = self.x, self.y
    local x1, y1 = d.objetivo[1], d.objetivo[2]
    local fx, fy = x1 - x0, y1 - y0
    local largo = math.sqrt(fx * fx + fy * fy)
    fx, fy = fx / largo, fy / largo
    -- De lejos (kilómetros), celdas más grandes y un pasillo más ancho: si
    -- hay un lago o una montaña en medio, que pueda rodearlo.
    local c = largo > 400 and Asalto.celdaLejos or Asalto.celda
    local margen = math.max(Asalto.margen, largo * Asalto.margenLejos)
    local R = {
        x0 = x0, y0 = y0, fx = fx, fy = fy, lx = -fy, ly = fx,
        u0 = -12 - (margen - Asalto.margen), nu = math.ceil((largo + 24 + 2 * (margen - Asalto.margen)) / c) + 1,
        v0 = -margen, nv = math.ceil(2 * margen / c) + 1,
        largo = largo, celda = c,
    }
    function R.mundo(i, j)
        local u, v = R.u0 + i * c, R.v0 + j * c
        return x0 + fx * u + R.lx * v, y0 + fy * u + R.ly * v
    end
    function R.celdaDe(x, y)
        local qx, qy = x - x0, y - y0
        local u, v = qx * fx + qy * fy, qx * R.lx + qy * R.ly
        return math.floor((u - R.u0) / c + 0.5), math.floor((v - R.v0) / c + 0.5)
    end
    -- Cada celda: libre, pendiente, expuesta, cobertura que la cubre.
    local suelo = Mundo.getSuelo()
    -- Lo que ve el enemigo: desde donde está (`amenaza`) o, si no se sabe,
    -- desde el objetivo.
    local amenaza = d.amenaza or d.objetivo
    local ex, ey = amenaza[1], amenaza[2]
    local ez = Mundo.altura(ex, ey) + 1.5
    local cuenta = { libres = 0, expuestas = 0, cubiertas = 0 }
    R.c = {}
    for i = 0, R.nu - 1 do
        for j = 0, R.nv - 1 do
            local x, y = R.mundo(i, j)
            local px, py = x * 10, -y * 10
            local info = {}
            info.pendiente = suelo:pendiente(px, py)
            info.libre = suelo:transitable(px, py) and info.pendiente < Asalto.pendienteMaxima
            -- Lo sólido no deja pasar; lo que es cobertura, cubre. Lo sólido,
            -- engordado media celda y algo más (espacio de configuración):
            -- con solo 1 m, una celda a 1,5 m de una nave contaba como libre
            -- y la ruta iba rozando la pared; el robot se quedaba pegado
            -- girando (el dueño, 19-nov).
            local engorde = R.celda * 0.5 + 0.5
            for _, c in ipairs(Mundo.cerca(x, y, math.max(Asalto.coberturaRadio, engorde), nil, cercanas)) do
                local dc = Colisiones.distancia(c, x, y)
                if c.etiquetas.solido and dc < engorde then
                    info.libre = false
                end
                if c.etiquetas.cobertura and (not info.cobertura or dc < info.coberturaDist) then
                    info.cobertura, info.coberturaDist = c, dc
                end
            end
            if info.libre then
                cuenta.libres = cuenta.libres + 1
                local lejos = (x - ex) ^ 2 + (y - ey) ^ 2 > (Asalto.alcanceVista + 20) ^ 2
                if not lejos then
                    local z = Mundo.altura(x, y) + 1.2
                    info.expuesta = despejado(ex, ey, ez, x, y, z)
                end
                if info.expuesta then
                    cuenta.expuestas = cuenta.expuestas + 1
                end
                if info.cobertura then
                    cuenta.cubiertas = cuenta.cubiertas + 1
                end
            end
            R.c[i * R.nv + j] = info
        end
    end
    R.cuenta = cuenta
    R.costeExpuesto = d.recorrer and Asalto.costeExpuestoRecorrer or nil
    return R
end

local function costeCelda(info, paso, costeExpuesto)
    local k = 1 + info.pendiente * Asalto.costePendiente
    if info.expuesta then
        k = k + (costeExpuesto or Asalto.costeExpuesto)
    end
    if info.cobertura then
        k = k - Asalto.premioCobertura
    end
    return paso * k
end

-- A* de la celda (ia, ja) a la (ib, jb): lista de celdas y su coste.
local function aEstrella(R, ia, ja, ib, jb)
    local nv = R.nv
    local function clave(i, j)
        return i * nv + j
    end
    -- Montículo binario por f (las rutas largas tienen miles de celdas).
    local abiertos = { { i = ia, j = ja, f = 0 } }
    local function meter(e)
        abiertos[#abiertos + 1] = e
        local n = #abiertos
        while n > 1 do
            local p = math.floor(n / 2)
            if abiertos[p].f <= abiertos[n].f then
                break
            end
            abiertos[p], abiertos[n] = abiertos[n], abiertos[p]
            n = p
        end
    end
    local function sacar()
        local primero = abiertos[1]
        local ultimo = abiertos[#abiertos]
        abiertos[#abiertos] = nil
        if #abiertos > 0 then
            abiertos[1] = ultimo
            local n = 1
            while true do
                local a, b = 2 * n, 2 * n + 1
                local m = n
                if abiertos[a] and abiertos[a].f < abiertos[m].f then
                    m = a
                end
                if abiertos[b] and abiertos[b].f < abiertos[m].f then
                    m = b
                end
                if m == n then
                    break
                end
                abiertos[m], abiertos[n] = abiertos[n], abiertos[m]
                n = m
            end
        end
        return primero
    end
    local g = { [clave(ia, ja)] = 0 }
    local de = {}
    local cerrado = {}
    local c = R.celda
    while #abiertos > 0 do
        local mejor = sacar()
        local ck = clave(mejor.i, mejor.j)
        if not cerrado[ck] then
            cerrado[ck] = true
            if mejor.i == ib and mejor.j == jb then
                local camino = {}
                local x = ck
                while x do
                    table.insert(camino, 1, x)
                    x = de[x]
                end
                return camino, g[ck]
            end
            for di = -1, 1 do
                for dj = -1, 1 do
                    local i, j = mejor.i + di, mejor.j + dj
                    if (di ~= 0 or dj ~= 0) and i >= 0 and i < R.nu and j >= 0 and j < nv then
                        local nk = clave(i, j)
                        local info = R.c[nk]
                        -- En diagonal, sin cortar la esquina de lo ocupado.
                        local esquina = di ~= 0 and dj ~= 0
                            and not (R.c[clave(mejor.i + di, mejor.j)].libre and R.c[clave(mejor.i, mejor.j + dj)].libre)
                        if info.libre and not esquina and not cerrado[nk] then
                            local paso = (di ~= 0 and dj ~= 0) and c * 1.4142 or c
                            local ng = g[ck] + costeCelda(info, paso, R.costeExpuesto)
                            if not g[nk] or ng < g[nk] then
                                g[nk] = ng
                                de[nk] = ck
                                local h = math.sqrt((i - ib) ^ 2 + (j - jb) ^ 2) * c
                                meter({ i = i, j = j, f = ng + h })
                            end
                        end
                    end
                end
            end
        end
    end
end

-- La celda libre más cercana a (i, j).
local function libreCerca(R, i, j)
    for radio = 0, 8 do
        for di = -radio, radio do
            for dj = -radio, radio do
                local a, b = i + di, j + dj
                if a >= 0 and a < R.nu and b >= 0 and b < R.nv then
                    local info = R.c[a * R.nv + b]
                    if info.libre then
                        return a, b
                    end
                end
            end
        end
    end
    return i, j
end

-- Paradas: cada `paradaCada` m como poco, donde hay cobertura (detrás de
-- ella, según de dónde viene el enemigo) o donde el enemigo no ve.
local function paradas(R, celdas, objetivo, sinParadas)
    local puntos = {}
    local recorrido, ultima = 0, 0
    local px, py
    for n, k in ipairs(celdas) do
        local i, j = math.floor(k / R.nv), k % R.nv
        local x, y = R.mundo(i, j)
        if px then
            recorrido = recorrido + math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        end
        px, py = x, y
        local info = R.c[k]
        local p = { x = x, y = y, expuesta = info.expuesta }
        local final = n == #celdas
        if not sinParadas and not final and recorrido - ultima >= Asalto.paradaCada and (info.cobertura or not info.expuesta) then
            p.parada = true
            ultima = recorrido
            local c = info.cobertura
            if c then
                -- Detrás de la cobertura: del lado contrario al enemigo, a
                -- 0,9 m de su contorno.
                local f = c.forma
                local ax, ay = f.x - objetivo[1], f.y - objetivo[2]
                local l = math.sqrt(ax * ax + ay * ay)
                ax, ay = ax / l, ay / l
                local r = Colisiones.alcance(c, ax, ay) + 0.9
                p.x, p.y = f.x + ax * r, f.y + ay * r
                p.cobertura = c
            end
        end
        -- Un punto de paso cada dos celdas (y las paradas y el final).
        if n % 2 == 1 or p.parada or final then
            puntos[#puntos + 1] = p
        end
    end
    puntos[#puntos].final = true
    -- Sin zigzag: la rejilla da escalones de 45°; promediando cada punto con
    -- sus vecinos (tres pasadas) la ruta queda en curvas suaves y el robot no
    -- se tuerce a un lado y a otro corriendo. Las paradas no se mueven.
    for _ = 1, 3 do
        local nuevos = {}
        for n, p in ipairs(puntos) do
            local a, b = puntos[n - 1], puntos[n + 1]
            if a and b and not p.parada then
                nuevos[n] = { (a.x + 2 * p.x + b.x) / 4, (a.y + 2 * p.y + b.y) / 4 }
            end
        end
        for n, q in pairs(nuevos) do
            puntos[n].x, puntos[n].y = q[1], q[2]
        end
    end
    return puntos
end

local function medir(R, celdas)
    local largo, expuesto, pendiente, coberturas = 0, 0, 0, 0
    local px, py
    for _, k in ipairs(celdas) do
        local i, j = math.floor(k / R.nv), k % R.nv
        local x, y = R.mundo(i, j)
        local info = R.c[k]
        if px then
            local l = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            largo = largo + l
            if info.expuesta then
                expuesto = expuesto + l
            end
            pendiente = pendiente + info.pendiente * l
        end
        if info.cobertura then
            coberturas = coberturas + 1
        end
        px, py = x, y
    end
    return largo, expuesto, pendiente / math.max(1, largo), coberturas
end

local function planificar(self, d)
    local t0 = love.timer.getTime()
    local R = rejilla(self, d)
    d.rejilla = R
    local ia, ja = libreCerca(R, R.celdaDe(self.x, self.y))
    local ib, jb = libreCerca(R, R.celdaDe(d.objetivo[1], d.objetivo[2]))
    d.rutas = {}
    for _, f in ipairs({ { 'izquierda', 1 }, { 'centro', 0 }, { 'derecha', -1 } }) do
        local mx = self.x + R.fx * R.largo / 2 + R.lx * Asalto.desvio * f[2]
        local my = self.y + R.fy * R.largo / 2 + R.ly * Asalto.desvio * f[2]
        local im, jm = libreCerca(R, R.celdaDe(mx, my))
        local a, ca = aEstrella(R, ia, ja, im, jm)
        local b, cb = aEstrella(R, im, jm, ib, jb)
        if a and b then
            local celdas = {}
            for _, k in ipairs(a) do
                celdas[#celdas + 1] = k
            end
            for n = 2, #b do
                celdas[#celdas + 1] = b[n]
            end
            local largo, expuesto, pendiente, coberturas = medir(R, celdas)
            d.rutas[#d.rutas + 1] = {
                nombre = f[1], celdas = celdas, coste = ca + cb,
                largo = largo, expuesto = expuesto, pendiente = pendiente, coberturas = coberturas,
                puntos = paradas(R, celdas, d.amenaza or d.objetivo, d.recorrer ~= nil or not Asalto.conParadas),
            }
        end
    end
    table.sort(d.rutas, function(a, b)
        return a.coste < b.coste
    end)
    for n, r in ipairs(d.rutas) do
        print(string.format('%s ruta por %-9s %4.0f m, %3.0f m a la vista del enemigo, pendiente %.0f°, %d coberturas: coste %.0f%s',
            d.nombre, r.nombre, r.largo, r.expuesto, r.pendiente, r.coberturas, r.coste, n == 1 and '  <- ELIJO' or ''))
    end
    d.ruta = d.rutas[1]
    d.indice = 1
    print(string.format('%s rutas en %.2f s (%d celdas libres, %d a la vista del enemigo, %d con cobertura)',
        d.nombre, love.timer.getTime() - t0, R.cuenta.libres, R.cuenta.expuestas, R.cuenta.cubiertas))
end

-- Ver y disparar ---------------------------------------------------------------

local function enemigos(self, d)
    local lista = {}
    for _, r in ipairs(self.gestor:getRobots()) do
        local o = r.datos.asalto
        if r ~= self and o and o.bando and o.bando ~= d.bando then
            lista[#lista + 1] = r
        end
    end
    return lista
end

local function buscar(self, d)
    local ox, oy, oz = ojo(self)
    local mira = self.rumbo + (d.torso or 0) + d.cabeza
    for _, e in ipairs(enemigos(self, d)) do
        local tx, ty, tz = pecho(e)
        local fuera = math.abs(angulo(math.atan2(ty - oy, tx - ox) - mira))
        -- En contacto (o si le acaban de disparar) no hace falta que lo
        -- tenga delante: ya sabe dónde está.
        local atento = d.enemigo == e and (not d.recorrer or (d.visto and d.reloj - d.visto < Asalto.perder))
        local campo = d.recorrer and Asalto.campoVistaRecorrer or Asalto.campoVista
        local alcance = d.recorrer and Asalto.alcanceVistaRecorrer or Asalto.alcanceVista
        if fuera < campo or atento then
            local ve, dist = despejado(ox, oy, oz, tx, ty, tz)
            if ve and dist < alcance then
                return e, dist
            end
        end
    end
end

local function disparar(self, d, distancia)
    local bx, by, bz, gx, gy, gz = boca(self)
    if not bx then
        return
    end
    local sigma = math.min(Asalto.dispersionMaxima, Asalto.dispersion + Asalto.dispersionPorMetro * distancia)
        + Asalto.dispersionCorriendo * math.abs(self.velocidad)
    local r = math.abs(love.math.randomNormal(sigma, 0))
    local a = love.math.random() * 2 * math.pi
    local ux, uy = -gy, gx
    local n = math.max(1e-6, math.sqrt(ux * ux + uy * uy))
    ux, uy = ux / n, uy / n
    local vx, vy, vz = -gz * uy, gz * ux, gx * uy - gy * ux
    local dx = gx + (ux * math.cos(a) + vx * math.sin(a)) * r
    local dy = gy + (uy * math.cos(a) + vy * math.sin(a)) * r
    local dz = gz + vz * math.sin(a) * r
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l, dy / l, dz / l
    local alcance = (d.recorrer and Asalto.alcanceTiroRecorrer or Asalto.alcanceTiro) + 20
    local dist, tipo = Mundo.rayo(bx, by, bz, dx, dy, dz, alcance)
    dist = dist or alcance
    local robot, zona
    for _, otro in ipairs(self.gestor:getRobots()) do
        if otro ~= self and otro.getImpactoRayo then
            local t, z = otro:getImpactoRayo(bx, by, bz, dx, dy, dz, dist)
            if t and t < dist then
                dist, robot, zona = t, otro, z
            end
        end
    end
    local hx, hy, hz = bx + dx * dist, by + dy * dist, bz + dz * dist
    d.disparos[#d.disparos + 1] = { bx, by, bz, hx, hy, hz, t = 0 }
    if robot then
        robot:setImpacto(hx, hy, hz, dx, dy, dz, 1, zona)
        d.chispas[#d.chispas + 1] = { hx, hy, hz, t = 0, robot = true }
        d.aciertos = d.aciertos + 1
        local o = robot.datos.asalto
        if o then
            o.recibidas = (o.recibidas or 0) + 1
            -- Le disparan: ya sabe dónde está quien le dispara.
            if o.estado ~= 'combate' then
                o.avisado = self
            end
            o.oido, o.oidoEn = o.reloj, { self.x, self.y }
        end
    elseif tipo then
        d.chispas[#d.chispas + 1] = { hx, hy, hz, t = 0 }
    end
    d.balas = d.balas + 1
    d.fogonazo = 0.05
    d.retroceso = 1
end

-- Estados ----------------------------------------------------------------------

local function irAlPunto(self, d)
    local p = d.ruta and d.ruta.puntos[d.indice]
    if not p then
        return nil
    end
    self:setVelocidadMaxima(Asalto.velocidad)
    self:setIrA(p.x, p.y, nil, not p.parada and not p.final)
    return p
end

local function rumboAlEnemigo(self, d)
    return math.atan2(d.objetivo[2] - self.y, d.objetivo[1] - self.x)
end

local function seguirRuta(self, d)
    d.estado = 'avanzar'
    d.enemigo = nil
    -- El punto de la ruta que tenga más cerca por delante.
    local mejor, md = d.indice, math.huge
    for n = d.indice, math.min(#d.ruta.puntos, d.indice + 6) do
        local p = d.ruta.puntos[n]
        local dd = (p.x - self.x) ^ 2 + (p.y - self.y) ^ 2
        if dd < md then
            mejor, md = n, dd
        end
    end
    d.indice = mejor
    irAlPunto(self, d)
end

-- Rutas nuevas hacia donde está el enemigo ahora (al verlo: el objetivo
-- de antes era donde empezó, y seguirlo los haría cruzarse de largo).
local function replanificar(self, d, e)
    if d.replanificado and d.reloj - d.replanificado < Asalto.replanificarCada then
        return
    end
    d.replanificado = d.reloj
    local anterior = { d.objetivo, d.ruta, d.rutas, d.indice, d.rejilla }
    d.objetivo = { e.x, e.y }
    print(string.format('%s t=%.1f s rutas nuevas hacia donde está %s:', d.nombre, d.reloj, e.datos.asalto.nombre))
    planificar(self, d)
    if not d.ruta then
        d.objetivo, d.ruta, d.rutas, d.indice, d.rejilla = anterior[1], anterior[2], anterior[3], anterior[4], anterior[5]
    end
end

local function entrarEnCombate(self, d, e, dist)
    if d.enemigo ~= e or d.estado ~= 'combate' then
        print(string.format('%s t=%.1f s veo a %s a %.0f m: ¡contacto!', d.nombre, d.reloj, e.datos.asalto.nombre, dist))
    end
    replanificar(self, d, e)
    d.estado = 'combate'
    d.enemigo = e
    d.visto = d.reloj
    d.rafagas = 0
    d.rafagasMover = math.floor(azar(Asalto.rafagasAntesDeMoverse) + 0.5)
    d.pausa, d.rafaga = 0.3, 0
    self:setParar()
end

function Asalto:onUpdate(dt)
    local d = self.datos.asalto
    d.reloj = d.reloj + dt
    for _, lista in ipairs({ d.disparos, d.chispas }) do
        for k = #lista, 1, -1 do
            lista[k].t = lista[k].t + dt
            if lista[k].t > (lista == d.chispas and 0.3 or Asalto.trazadora) then
                table.remove(lista, k)
            end
        end
    end
    d.fogonazo = math.max(0, (d.fogonazo or 0) - dt)
    d.retroceso = math.max(0, d.retroceso - dt * 14)
    if d.estado == 'esperar' then
        return
    end
    if d.recorrer then
        Asalto.recorrer(self, d, dt)
        return
    end

    -- Mirar: unas veces por segundo.
    d.verReloj = d.verReloj - dt
    local visto, distancia
    if d.verReloj <= 0 then
        d.verReloj = Asalto.verCada
        visto, distancia = buscar(self, d)
        d.ultimaVista = visto
        d.ultimaDistancia = distancia
    else
        visto, distancia = d.ultimaVista, d.ultimaDistancia
    end
    if d.avisado and not visto then
        -- Le han dado sin verlo: mira hacia allí.
        d.enemigo = d.avisado
        d.avisado = nil
        d.verReloj = 0
    end

    local quiereDisparar = false
    local mirarA -- rumbo (absoluto) hacia donde gira la cabeza

    if d.estado == 'avanzar' or d.estado == 'parado' or d.estado == 'reposicionar' or d.estado == 'llegado' then
        if visto and d.estado ~= 'reposicionar' then
            entrarEnCombate(self, d, visto, distancia)
        end
    end

    if d.estado == 'avanzar' or d.estado == 'reposicionar' then
        local p = d.ruta.puntos[d.indice]
        if not p then
            d.estado = 'llegado'
            self:setParar()
        else
            local llegada = (p.parada or p.final) and 0.8 or 2.0
            if (p.x - self.x) ^ 2 + (p.y - self.y) ^ 2 < llegada * llegada then
                if p.final then
                    print(string.format('%s t=%.1f s llego al final de la ruta', d.nombre, d.reloj))
                    d.estado = 'llegado'
                    self:setParar()
                elseif p.parada then
                    d.indice = d.indice + 1
                    if d.estado == 'reposicionar' then
                        -- En la nueva cobertura: a disparar otra vez.
                        if d.enemigo then
                            local tx, ty, tz = pecho(d.enemigo)
                            local ox, oy, oz = ojo(self)
                            local ve, dist = despejado(ox, oy, oz, tx, ty, tz)
                            if ve then
                                entrarEnCombate(self, d, d.enemigo, dist)
                            else
                                d.estado = 'parado'
                                d.hasta = d.reloj + azar(Asalto.paradaTiempo)
                                self:setParar()
                            end
                        end
                    else
                        d.estado = 'parado'
                        d.hasta = d.reloj + azar(Asalto.paradaTiempo)
                        d.barrido = love.math.random() * 6
                        self:setParar()
                        print(string.format('%s t=%.1f s a cubierto%s, vigilo', d.nombre, d.reloj, p.cobertura and ' tras una cobertura' or ' (el enemigo no me ve aquí)'))
                    end
                else
                    d.indice = d.indice + 1
                    irAlPunto(self, d)
                end
            elseif self:getHaLlegado() then
                irAlPunto(self, d)
            end
        end
        if d.estado == 'reposicionar' and d.enemigo then
            local tx, ty = pecho(d.enemigo)
            mirarA = math.atan2(ty - self.y, tx - self.x)
        else
            -- Corriendo: mira por donde va y, de vez en cuando, hacia el enemigo.
            local haciaEnemigo = rumboAlEnemigo(self, d)
            mirarA = self.rumbo + angulo(haciaEnemigo - self.rumbo) * 0.5 + math.sin(d.reloj * 0.9) * 0.35
        end
    elseif d.estado == 'parado' then
        -- Vigila de lado a lado hacia el enemigo.
        d.barrido = (d.barrido or 0) + dt
        mirarA = rumboAlEnemigo(self, d) + math.sin(d.barrido * 0.8) * math.rad(55)
        if d.reloj > d.hasta then
            d.estado = 'avanzar'
            irAlPunto(self, d)
        end
    elseif d.estado == 'combate' then
        local e = d.enemigo
        local tx, ty, tz = pecho(e)
        if visto == e then
            d.visto = d.reloj
            distancia = distancia or math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)
        end
        mirarA = math.atan2(ty - self.y, tx - self.x)
        if d.reloj - d.visto > Asalto.perder then
            print(string.format('%s t=%.1f s lo he perdido de vista: sigo la ruta', d.nombre, d.reloj))
            seguirRuta(self, d)
        else
            -- El cuerpo, hacia él.
            local fuera = angulo(mirarA - self.rumbo)
            if math.abs(fuera) > math.rad(5) then
                self:setIrA(self.x, self.y, mirarA)
            end
            -- El brazo: lazo cerrado sobre hacia dónde apuntan los cañones.
            local bx, by, bz, gx, gy, gz = boca(self)
            if bx then
                local ux, uy, uz = tx - bx, ty - by, tz - bz
                local horizontal = math.sqrt(ux * ux + uy * uy)
                local errorLado = angulo(math.atan2(uy, ux) - math.atan2(gy, gx))
                local errorArriba = math.atan2(uz, horizontal) - math.atan2(gz, math.sqrt(gx * gx + gy * gy))
                local k = math.min(1, dt * 10)
                d.lado = math.max(-Asalto.ladoMax, math.min(Asalto.ladoMax, d.lado + errorLado * k))
                d.arriba = math.max(-Asalto.arribaMax, math.min(Asalto.arribaMax, d.arriba + errorArriba * k))
                local error = math.sqrt(errorLado ^ 2 + errorArriba ^ 2)
                local apuntado = error < Asalto.apuntado and d.reloj - d.visto < 0.4 and horizontal < Asalto.alcanceTiro
                if d.pausa > 0 then
                    d.pausa = d.pausa - dt
                    if d.pausa <= 0 then
                        d.rafaga = azar(Asalto.rafaga)
                    end
                elseif apuntado then
                    quiereDisparar = true
                    d.rafaga = d.rafaga - dt
                    if d.rafaga <= 0 then
                        d.pausa = azar(Asalto.pausaRafaga)
                        d.rafagas = d.rafagas + 1
                        -- Tras unas ráfagas, si aún está lejos, salta a la
                        -- siguiente cobertura hacia él.
                        local siguiente
                        for n = d.indice, #d.ruta.puntos do
                            if d.ruta.puntos[n].parada then
                                siguiente = n
                                break
                            end
                        end
                        if d.rafagas >= d.rafagasMover and siguiente and horizontal > Asalto.distanciaMinima then
                            d.estado = 'reposicionar'
                            print(string.format('%s t=%.1f s salto a la siguiente cobertura (a %.0f m de él; %d de %d balas le han dado)', d.nombre, d.reloj, horizontal, d.aciertos, d.balas))
                            irAlPunto(self, d)
                        end
                    end
                end
            end
        end
    elseif d.estado == 'llegado' then
        mirarA = rumboAlEnemigo(self, d) + math.sin(d.reloj * 0.7) * math.rad(60)
        -- No está donde lo esperaba: lo oye disparar y va a por él.
        d.llegado = d.llegado or d.reloj
        local e = enemigos(self, d)[1]
        if e and d.reloj - d.llegado > Asalto.esperaAlLlegar
            and (e.x - self.x) ^ 2 + (e.y - self.y) ^ 2 > Asalto.distanciaMinima ^ 2 then
            d.llegado = nil
            d.replanificado = nil
            replanificar(self, d, e)
            seguirRuta(self, d)
        end
    end

    -- Fuera de combate, el brazo vuelve a su sitio.
    if d.estado ~= 'combate' then
        local k = math.min(1, dt * 3)
        d.lado, d.arriba = d.lado * (1 - k), d.arriba * (1 - k)
    end
    -- La cabeza: hacia `mirarA`, con su límite y su rapidez.
    if mirarA then
        Mirada.girar(d, self.rumbo, mirarA, 0, dt)
    end
    -- Tambor: acelera al disparar; dispara cuando gira.
    local objetivoTambor = quiereDisparar and Asalto.giroTambor or 0
    local acel = Asalto.giroTambor / Asalto.arranqueTambor
    d.vTambor = d.vTambor + math.max(-acel * dt * 0.5, math.min(acel * dt, objetivoTambor - d.vTambor))
    d.tambor = d.tambor + d.vTambor * dt
    if quiereDisparar and d.vTambor > Asalto.giroTambor * 0.8 then
        d.cuenta = (d.cuenta or 0) + dt * Asalto.cadencia
        while d.cuenta >= 1 do
            d.cuenta = d.cuenta - 1
            disparar(self, d, distancia or 50)
        end
    else
        d.cuenta = 0
    end
end

-- Recorrer ---------------------------------------------------------------------

-- Un sitio nuevo del campo: lejos de donde está y de los últimos destinos.
local function nuevoDestino(self, d)
    local R = d.recorrer
    local suelo = Mundo.getSuelo()
    local mejor, mejorPuntos
    local e = enemigos(self, d)[1]
    local pasada = e and love.math.random() < Asalto.pasada
    for _ = 1, 60 do
        local a = love.math.random() * 2 * math.pi
        local r = R.radio * math.sqrt(love.math.random())
        local x, y = R.cx + math.cos(a) * r, R.cy + math.sin(a) * r
        if pasada then
            -- Al otro lado de él, algo apartado de la línea.
            local fx, fy = e.x - self.x, e.y - self.y
            local l = math.max(1, math.sqrt(fx * fx + fy * fy))
            fx, fy = fx / l, fy / l
            local mas = azar(Asalto.pasadaMas)
            local lado = (love.math.random() * 2 - 1) * Asalto.pasadaLado
            x, y = e.x + fx * mas - fy * lado, e.y + fy * mas + fx * lado
            if (x - R.cx) ^ 2 + (y - R.cy) ^ 2 > R.radio ^ 2 then
                x, y = nil, nil
            end
        end
        local dist = x and math.sqrt((x - self.x) ^ 2 + (y - self.y) ^ 2) or 0
        local minimo = R.minimo or Asalto.destinoMinimo
        local maximo = R.maximo or Asalto.destinoMaximo
        if x and dist > minimo and dist < maximo and suelo:transitable(x * 10, -y * 10)
            and not suelo:plantaCerca(x * 10, -y * 10, 25, true) and (not R.dentro or R.dentro(x, y)) then
            local puntos = 0
            for _, v in ipairs(R.visitados) do
                puntos = puntos + math.min(200, math.sqrt((x - v[1]) ^ 2 + (y - v[2]) ^ 2))
            end
            puntos = puntos + love.math.random() * 120
            if not mejorPuntos or puntos > mejorPuntos then
                mejor, mejorPuntos = { x, y }, puntos
            end
        end
    end
    mejor = mejor or { R.cx, R.cy }
    table.insert(R.visitados, 1, mejor)
    R.visitados[Asalto.recordarDestinos + 1] = nil
    d.objetivo = mejor
    -- Lo que ve el enemigo: desde donde lo vio u oyó por última vez (si no
    -- sabe nada, ningún sitio cuenta como expuesto).
    d.amenaza = d.enemigoEn or { self.x + 100000, self.y }
    print(string.format('%s t=%.1f s voy a otro sitio, a %.0f m%s', d.nombre, d.reloj, math.sqrt((mejor[1] - self.x) ^ 2 + (mejor[2] - self.y) ^ 2), pasada and mejorPuntos and (', pasando junto a ' .. e.datos.asalto.nombre) or ''))
    planificar(self, d)
    d.indice = 1
    if d.ruta then
        irAlPunto(self, d)
    end
end

--- Corre de un sitio a otro sin pararse; si ve al enemigo, gira el torso y
-- el brazo hacia él y le dispara corriendo.
function Asalto.recorrer(self, d, dt)
    -- Rastro para el mapa (un punto cada medio segundo; los últimos 3 min).
    d.rastroReloj = (d.rastroReloj or 0) - dt
    if d.rastroReloj <= 0 then
        d.rastroReloj = 0.5
        d.rastro = d.rastro or {}
        d.rastro[#d.rastro + 1] = { self.x, self.y }
        if #d.rastro > 360 then
            table.remove(d.rastro, 1)
        end
    end
    -- Ruta.
    local p = d.ruta and d.ruta.puntos[d.indice]
    if not p then
        nuevoDestino(self, d)
    else
        local llegada = p.final and 3 or 2.5
        if (p.x - self.x) ^ 2 + (p.y - self.y) ^ 2 < llegada * llegada then
            if p.final then
                nuevoDestino(self, d)
            else
                d.indice = d.indice + 1
                irAlPunto(self, d)
            end
        elseif self:getHaLlegado() then
            irAlPunto(self, d)
        end
    end
    -- Mirar.
    d.verReloj = d.verReloj - dt
    if d.verReloj <= 0 then
        d.verReloj = Asalto.verCada
        local e, dist = buscar(self, d)
        if e then
            if not d.visto or d.reloj - d.visto > Asalto.perder then
                print(string.format('%s t=%.1f s veo a %s a %.0f m: le disparo corriendo', d.nombre, d.reloj, e.datos.asalto.nombre, dist))
                d.rafaga, d.pausa = 0, 0.2
            end
            d.enemigo, d.visto, d.distancia = e, d.reloj, dist
            d.enemigoEn = { e.x, e.y }
        end
    end
    if d.oido and d.reloj - d.oido < 0.1 then
        d.enemigoEn = d.oidoEn
    end
    local loVe = d.enemigo and d.visto and d.reloj - d.visto < 0.4
    local sabe = d.enemigo and d.visto and d.reloj - d.visto < Asalto.perder
    -- Hacia dónde mira: al enemigo si sabe dónde está; si no, por donde va,
    -- echando ojeadas hacia donde lo vio por última vez.
    local mirarA
    if sabe then
        local tx, ty = pecho(d.enemigo)
        mirarA = math.atan2(ty - self.y, tx - self.x)
    else
        mirarA = Mirada.barrido(self.rumbo, d.reloj)
        if d.enemigoEn then
            local haciaEl = math.atan2(d.enemigoEn[2] - self.y, d.enemigoEn[1] - self.x)
            mirarA = self.rumbo + angulo(haciaEl - self.rumbo) * 0.4 + math.sin(d.reloj * 0.9) * math.rad(40)
        end
    end
    -- El torso gira hacia él solo para disparar; la cabeza hace el resto.
    local quiereTorso = 0
    if loVe then
        quiereTorso = math.max(-Asalto.torsoMax, math.min(Asalto.torsoMax, angulo(mirarA - self.rumbo)))
    end
    Mirada.girar(d, self.rumbo, mirarA, quiereTorso, dt)
    -- Apuntar y disparar, sin dejar de correr.
    local quiereDisparar = false
    local bx, by, bz, gx, gy, gz = boca(self)
    if loVe and bx then
        local tx, ty, tz = pecho(d.enemigo)
        local ux, uy, uz = tx - bx, ty - by, tz - bz
        local horizontal = math.sqrt(ux * ux + uy * uy)
        local errorLado = angulo(math.atan2(uy, ux) - math.atan2(gy, gx))
        local errorArriba = math.atan2(uz, horizontal) - math.atan2(gz, math.sqrt(gx * gx + gy * gy))
        local k = math.min(1, dt * 10)
        d.lado = math.max(-Asalto.ladoMax, math.min(Asalto.ladoMax, d.lado + errorLado * k))
        d.arriba = math.max(-Asalto.arribaMax, math.min(Asalto.arribaMax, d.arriba + errorArriba * k))
        local error = math.sqrt(errorLado ^ 2 + errorArriba ^ 2)
        if horizontal < Asalto.alcanceTiroRecorrer and error < Asalto.apuntadoRecorrer then
            if d.pausa > 0 then
                d.pausa = d.pausa - dt
                if d.pausa <= 0 then
                    d.rafaga = azar(Asalto.rafaga)
                end
            else
                quiereDisparar = true
                d.rafaga = d.rafaga - dt
                if d.rafaga <= 0 then
                    d.pausa = azar(Asalto.pausaRafaga)
                end
            end
        end
        d.estado = 'combate'
    else
        local k = math.min(1, dt * 3)
        d.lado, d.arriba = d.lado * (1 - k), d.arriba * (1 - k)
        d.estado = 'avanzar'
    end
    -- Tambor.
    local objetivoTambor = quiereDisparar and Asalto.giroTambor or 0
    local acel = Asalto.giroTambor / Asalto.arranqueTambor
    d.vTambor = d.vTambor + math.max(-acel * dt * 0.5, math.min(acel * dt, objetivoTambor - d.vTambor))
    d.tambor = d.tambor + d.vTambor * dt
    if quiereDisparar and d.vTambor > Asalto.giroTambor * 0.8 then
        d.cuenta = (d.cuenta or 0) + dt * Asalto.cadencia
        while d.cuenta >= 1 do
            d.cuenta = d.cuenta - 1
            disparar(self, d, d.distancia or 50)
        end
    else
        d.cuenta = 0
    end
end

function Asalto:onPose()
    local d = self.datos.asalto
    Mirada.poner(self, d)
    local hombro = self:getPieza('hombroDer')
    if hombro then
        hombro:setGiro('z', d.lado, 'apuntarLado')
        hombro:setGiro('y', -d.arriba - 0.035 * d.retroceso * love.math.random(), 'apuntarArriba')
    end
    if self.piezas.canones then
        self.piezas.canones:setGiro('x', d.tambor, 'tambor')
    end
end

--- Avanza hacia (x, y) m como `bando` ('azul', 'rojo'…): traza las rutas y
-- empieza por la mejor.
function Robot:setAsalto(bando, x, y, nombre)
    local d = self.datos.asalto
    d.bando = bando
    d.nombre = nombre or string.upper(bando)
    d.objetivo = { x, y }
    planificar(self, d)
    if d.ruta then
        d.estado = 'avanzar'
        irAlPunto(self, d)
    end
end

--- Corre por el campo (un círculo de `radio` m alrededor de (cx, cy)) de un
-- sitio a otro, sin pararse, disparando al enemigo cuando lo ve.
-- `opciones` (opcional): `dentro(x, y)` dice si un destino vale (p. ej.
-- dentro del muro de una mina y fuera de sus edificios); `minimo` y
-- `maximo`, los m entre un destino y el siguiente (si no, los de campo
-- abierto: Asalto.destinoMinimo y Asalto.destinoMaximo).
function Robot:setRecorrer(bando, cx, cy, radio, nombre, opciones)
    local d = self.datos.asalto
    d.bando = bando
    d.nombre = nombre or string.upper(bando)
    opciones = opciones or {}
    d.recorrer = {
        cx = cx,
        cy = cy,
        radio = radio,
        visitados = {},
        dentro = opciones.dentro,
        minimo = opciones.minimo,
        maximo = opciones.maximo,
    }
    d.estado = 'avanzar'
    nuevoDestino(self, d)
end

function Robot:getAsalto()
    return self.datos.asalto
end

Nucleo.registrarEspecializacion('asalto', Asalto)
return Asalto

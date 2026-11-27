-- Vuelo del avión de carga, pilotado por la máquina (el dueño, 20-nov:
-- «ciclo completo solo», «físico pero amable»). Cómo lo hace la industria
-- (X-Plane y FlightGear; juegos tipo Battlefield o el arcade de War
-- Thunder): un modelo de cuatro fuerzas y un piloto automático por capas.
--
-- Modelo (metros, segundos; los ejes de los robots: x, y a la izquierda,
-- z arriba):
--   - empuje a lo largo del morro (0-1 de `AvionVuelo.empuje`; en tierra,
--     reversa para frenar);
--   - sustentación perpendicular a la velocidad, en el plano de las alas:
--     ½ρV²S·CL(α), con CL = CL0 + a·α (más los flaps al despegar y
--     aterrizar), tope en CLmax (sin pérdida brusca: amable);
--   - resistencia contra la velocidad: ½ρV²S·(CD0 + K·CL²) (polar);
--   - peso.
--   Actitud: cabeceo y alabeo los pone el piloto (con un ritmo máximo, como
--   un avión de 400 t); el rumbo sigue a la velocidad (sin derrape) y el
--   giro sale de inclinar la sustentación (alabeo).
--   En tierra: sobre las ruedas, siguiendo el terreno; rodadura, frenos y
--   rueda de morro que gira.
--
-- Piloto (capas): por dentro, cabeceo y alabeo hacia lo pedido; por fuera,
-- velocidad con el empuje, altura con la senda (ángulo de trayectoria) y
-- rumbo con el alabeo (gira inclinando). Fases: aparcado → carreteo →
-- despegue → ascenso → circuito (puntos de paso) → final (senda de 3,5°
-- alineado con la pista) → toma (enderezar) → frenada → rampa abierta un
-- rato → otra vez, despegando en el sentido contrario.
--
-- La pista: la que tiene delante y detrás al aparcar (escena: sitioAvion
-- busca un pasillo llano y sin árboles de ±500 m).
--
-- Lo de ahora, en avion.datos.vueloAvion: fase, x, y, z, vx, vy, vz,
-- rumbo, cabeceo, alabeo, empuje, alto (sobre el suelo).

local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot
local PiezaRobot = require('robots.pieza')
local Mundo = require('batalla.robots.mundo')

local AvionVuelo = {}

AvionVuelo.masa = 400000 -- kg (con 4 camiones y 24 robots)
AvionVuelo.ala = 1400 -- m²
AvionVuelo.empuje = 2.4e6 -- N, los cuatro motores de energía
AvionVuelo.reversa = 0.35 -- del empuje, al frenar
AvionVuelo.rho = 1.225
AvionVuelo.cl0, AvionVuelo.clAlfa, AvionVuelo.clMax = 0.3, 5.0, 2.2
AvionVuelo.flaps = 0.9 -- CL de más con flaps
AvionVuelo.cd0, AvionVuelo.k = 0.025, 0.045
AvionVuelo.cdFlaps = 0.07 -- resistencia de más con flaps y tren (frenan en la final)
AvionVuelo.spoilers = 1.2 -- CL que quitan los spoilers al tocar suelo (no rebota)
AvionVuelo.g = 9.81
AvionVuelo.rodadura, AvionVuelo.freno = 0.02, 0.35 -- coeficientes (de la carga en ruedas)
AvionVuelo.velocidadRotacion = 47 -- m/s: levanta el morro
AvionVuelo.velocidadCircuito = 80
AvionVuelo.velocidadFinal = 52
AvionVuelo.alturaCircuito = 300 -- m sobre la pista
AvionVuelo.senda = math.rad(3.5)
AvionVuelo.ritmoCabeceo = math.rad(4) -- rad/s
AvionVuelo.ritmoAlabeo = math.rad(9)
AvionVuelo.alabeoMaximo = math.rad(30)
AvionVuelo.toque = 300 -- m de la pista (desde el centro) donde toca
AvionVuelo.rampaAbierta = 20 -- s con la rampa abierta
AvionVuelo.esperaInicio = 6 -- s aparcado antes de empezar
AvionVuelo.carreteo = 40 -- m de carreteo antes de acelerar
AvionVuelo.paso = 1 / 120
AvionVuelo.pistaLargo = 400 -- m a cada lado del centro (escena: sitioAvion)
AvionVuelo.velocidadSalida = 85 -- m/s subiendo para irse
AvionVuelo.distanciaSalida = 3500 -- m del centro de la pista: ahí deja la escena (niebla)
AvionVuelo.llegadaDesde = 3000 -- m del centro de la pista donde aparece al llegar (en la niebla: no se le ve aparecer)
AvionVuelo.velocidadLlegada = 75 -- m/s al aparecer (frena en la final)
AvionVuelo.flotarMaximo = 8 -- s enderezando sin tocar: motor y otra vuelta

-- Circuito en ejes de la pista (a lo largo, a la izquierda), metros, en el
-- sentido del despegue: sale recto, se aparta a la derecha, da la vuelta
-- en un círculo de 1300 m y entra en la final hacia la pista en el sentido
-- contrario.
AvionVuelo.circuito = {
    { 2500, 0 }, { 4800, -2600 }, { 6000, -2600 }, { 6920, -2220 },
    { 7300, -1300 }, { 6920, -380 }, { 6000, 0 },
}

local function limitar(v, a, b)
    return math.max(a, math.min(b, v))
end

local function acercar(a, b, paso)
    if a < b then
        return math.min(b, a + paso)
    end
    return math.max(b, a - paso)
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Suelo del mundo sin la bodega del propio avión (embarque.lua).
local function alturaSuelo(d, x, y)
    return Mundo.altura(x, y, d.excluir)
end

function AvionVuelo.prerequisitos(self)
    return self:getTieneEspecializacion('avionCarga')
end

function AvionVuelo.onLoad(self)
    local d = self.datos.vueloAvion
    d.px, d.py = self.x, self.y
    d.ux, d.uy = math.cos(self.rumbo), math.sin(self.rumbo)
    d.sentido = 1
    d.x, d.y = self.x, self.y
    d.z = alturaSuelo(d, self.x, self.y)
    d.vx, d.vy, d.vz = 0, 0, 0
    d.rumbo, d.cabeceo, d.alabeo = self.rumbo, 0, 0
    d.quiereCabeceo, d.quiereAlabeo = 0, 0
    d.empuje, d.flaps, d.freno = 0, 1, 1
    d.enTierra = true
    d.fase, d.reloj = 'aparcado', 0
    d.punto = 1
    d.acumulado = 0
    d.matriz = {}
    self.raizFija = d.matriz
    d.pistaLargo = AvionVuelo.pistaLargo
    d.toque = AvionVuelo.toque
    AvionVuelo.medirPista(d)
    AvionVuelo.colocar(self, d)
end

-- Pista: coordenadas (a lo largo en el sentido actual, a la izquierda) y vuelta.
local function enPista(d, x, y)
    local ux, uy = d.ux * d.sentido, d.uy * d.sentido
    local dx, dy = x - d.px, y - d.py
    return dx * ux + dy * uy, -dx * uy + dy * ux
end

local function desdePista(d, a, l)
    local ux, uy = d.ux * d.sentido, d.uy * d.sentido
    return d.px + ux * a - uy * l, d.py + uy * a + ux * l
end

-- Altura de la pista: recta entre sus extremos (a lo largo, en el sentido
-- del primer despegue).
function AvionVuelo.medirPista(d)
    d.zPistaA = alturaSuelo(d, d.px - d.ux * d.pistaLargo, d.py - d.uy * d.pistaLargo)
    d.zPistaB = alturaSuelo(d, d.px + d.ux * d.pistaLargo, d.py + d.uy * d.pistaLargo)
end

--- La pista del aeródromo del sitio (batalla/sitios/plano.lua): centro
-- (x, y) m, rumbo y medio largo (m). El avión ya está aparcado en ella (en
-- un extremo). La toma, a 170 m del final (pasa el muro con holgura).
function Robot:setPista(x, y, rumbo, medioLargo)
    local d = self.datos.vueloAvion
    d.px, d.py = x, y
    d.ux, d.uy = math.cos(rumbo), math.sin(rumbo)
    d.pistaLargo = medioLargo
    d.toque = math.min(AvionVuelo.toque, medioLargo - 170)
    AvionVuelo.medirPista(d)
end

-- Altura de la pista (la recta entre sus extremos) en `a` del sentido actual.
local function zPista(d, a)
    local a0 = limitar(a * d.sentido, -d.pistaLargo, d.pistaLargo)
    return d.zPistaA + (d.zPistaB - d.zPistaA) * (a0 + d.pistaLargo) / (2 * d.pistaLargo)
end

local function rumboPista(d)
    return math.atan2(d.uy * d.sentido, d.ux * d.sentido)
end

--- Se va a otro sitio: tras despegar, sube en recta y deja la escena
-- (fase `salida`). Sin circuito.
function Robot:setSalida()
    local d = self.datos.vueloAvion
    d.salida = true
    d.retener = false
end

--- Aparcado en la pista hasta `setSalida` (el avión de un vuelo del mapa que
-- espera en el sitio: batalla/dream/trafico_aereo.lua).
function Robot:setRetenido()
    self.datos.vueloAvion.retener = true
end

--- Llega de otro sitio: aparece en el aire en la final, a `llegadaDesde` m
-- del centro de la pista en su prolongación (del lado oeste, aterriza hacia
-- el este), en la senda de 3,5° y a `velocidadLlegada`, y aterriza; luego
-- se queda con la rampa abierta. Como el tráfico de los simuladores de
-- vuelo: aparece ya en la aproximación, lejos y fuera de la vista.
function Robot:setLlegada()
    local d = self.datos.vueloAvion
    -- Del oeste (sentido contrario al de la pista): aterriza hacia el este.
    d.sentido = -1
    d.embarcado, d.quedarse = true, true
    local a = AvionVuelo.llegadaDesde
    d.x, d.y = desdePista(d, a, 0)
    d.z = zPista(d, d.toque) + (a - d.toque) * math.tan(AvionVuelo.senda)
    d.rumbo = rumboPista(d) + math.pi
    local V = AvionVuelo.velocidadLlegada
    local g = AvionVuelo.senda
    d.vx, d.vy, d.vz = math.cos(d.rumbo) * V * math.cos(g), math.sin(d.rumbo) * V * math.cos(g), -V * math.sin(g)
    d.cabeceo, d.alabeo, d.quiereAlabeo = math.rad(2), 0, 0
    d.quiereCabeceo = d.cabeceo
    d.flaps, d.freno, d.empuje = 1, 0, 0.2
    d.enTierra = false
    d.fase, d.reloj = 'final', 0
    AvionVuelo.colocar(self, d)
end

-- Rodaje por la plataforma (el dueño, 26-nov: varios aviones en el mismo
-- sitio, cada uno a su plaza). Como el tráfico de tierra de los simuladores
-- de vuelo: en tierra y despacio el avión sigue un camino (rectas unidas por
-- arcos) con la velocidad limitada en las curvas, sin la física del vuelo;
-- hacia atrás, empujado (la salida de la plaza). Ejes de la plataforma: a a
-- lo largo de la pista (al este) y l al norte, en m
-- (batalla/sitios/plano.lua: Plano.aerodromo.plataforma).
AvionVuelo.rodaje = {
    velocidad = 8, -- m/s en recta
    curva = 3, -- m/s como mucho en las curvas
    lateral = 0.35, -- m/s² de aceleración lateral en las curvas
    atras = 2.5, -- m/s empujado hacia atrás
    acelera = 0.6, -- m/s²
    frena = 0.7, -- m/s²
    radio = 30, -- m de los arcos (como mucho)
}

local function base(d, a, l)
    return d.px + d.ux * a - d.uy * l, d.py + d.uy * a + d.ux * l
end

local function enBase(d, x, y)
    local dx, dy = x - d.px, y - d.py
    return dx * d.ux + dy * d.uy, -dx * d.uy + dy * d.ux
end

--- Muestras cada metro del camino por `puntos` ({x, y} m), con las
-- esquinas redondeadas: { x, y, rumbo, s (m recorridos), v (m/s máximos) }.
local function hacerCamino(puntos)
    local R = AvionVuelo.rodaje
    -- Sin puntos repetidos.
    local p = { puntos[1] }
    for k = 2, #puntos do
        local q = p[#p]
        if (puntos[k][1] - q[1]) ^ 2 + (puntos[k][2] - q[2]) ^ 2 > 1 then
            p[#p + 1] = puntos[k]
        end
    end
    local muestras = {}
    local function poner(x, y, v)
        local ultima = muestras[#muestras]
        if ultima and (x - ultima.x) ^ 2 + (y - ultima.y) ^ 2 < 1e-4 then
            return
        end
        muestras[#muestras + 1] = { x = x, y = y, v = v }
    end
    local function recta(x0, y0, x1, y1)
        local largo = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local n = math.max(1, math.ceil(largo))
        for k = 0, n do
            poner(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n, R.velocidad)
        end
    end
    local x, y = p[1][1], p[1][2]
    for k = 2, #p - 1 do
        local a, b, c = p[k - 1], p[k], p[k + 1]
        local l1 = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        local l2 = math.sqrt((c[1] - b[1]) ^ 2 + (c[2] - b[2]) ^ 2)
        local u1x, u1y = (b[1] - a[1]) / l1, (b[2] - a[2]) / l1
        local u2x, u2y = (c[1] - b[1]) / l2, (c[2] - b[2]) / l2
        local giro = math.atan2(u1x * u2y - u1y * u2x, u1x * u2x + u1y * u2y)
        if math.abs(giro) < math.rad(1) then
            recta(x, y, b[1], b[2])
            x, y = b[1], b[2]
        else
            local tangente = math.min(R.radio * math.tan(math.abs(giro) / 2), 0.48 * l1, 0.48 * l2)
            local radio = tangente / math.tan(math.abs(giro) / 2)
            local t1x, t1y = b[1] - u1x * tangente, b[2] - u1y * tangente
            recta(x, y, t1x, t1y)
            -- Centro a la izquierda si gira a la izquierda.
            local lado = giro > 0 and 1 or -1
            local cx, cy = t1x - u1y * radio * lado, t1y + u1x * radio * lado
            local a0 = math.atan2(t1y - cy, t1x - cx)
            local n = math.max(2, math.ceil(radio * math.abs(giro)))
            local v = math.min(R.curva, math.sqrt(R.lateral * radio))
            for j = 1, n do
                local ang = a0 + giro * j / n
                poner(cx + math.cos(ang) * radio, cy + math.sin(ang) * radio, v)
            end
            x, y = b[1] + u2x * tangente, b[2] + u2y * tangente
        end
    end
    recta(x, y, p[#p][1], p[#p][2])
    -- Recorrido, rumbo y la velocidad para poder frenar a tiempo (y parar
    -- al final).
    local s = 0
    for k, m in ipairs(muestras) do
        if k > 1 then
            s = s + math.sqrt((m.x - muestras[k - 1].x) ^ 2 + (m.y - muestras[k - 1].y) ^ 2)
        end
        m.s = s
        local a, b = muestras[math.max(1, k - 1)], muestras[math.min(#muestras, k + 1)]
        m.rumbo = math.atan2(b.y - a.y, b.x - a.x)
    end
    muestras[#muestras].v = 0
    for k = #muestras - 1, 1, -1 do
        local m, n = muestras[k], muestras[k + 1]
        m.v = math.min(m.v, math.sqrt(n.v * n.v + 2 * R.frena * (n.s - m.s)))
    end
    return muestras
end

--- Empieza a rodar por `puntos` ({a, l} de la plataforma); al acabar, la
-- fase `despues`. `atras`: empujado hacia atrás.
local function rodar(d, puntos, despues, atras)
    local xy = { { d.x, d.y } }
    for _, q in ipairs(puntos) do
        local x, y = base(d, q[1], q[2])
        xy[#xy + 1] = { x, y }
    end
    local V = math.sqrt(d.vx * d.vx + d.vy * d.vy)
    d.camino = { muestras = hacerCamino(xy), s = 0, v = atras and 0 or V, atras = atras, k = 1 }
    d.fase, d.reloj, d.despues = atras and 'remolque' or 'rodaje', 0, despues
    d.empuje, d.spoilers, d.freno = 0, 0, 0
end

--- Un paso por el camino: posición, rumbo y alto sobre el suelo.
local function moverCamino(self, d, dt)
    local c = d.camino
    local m = c.muestras
    while c.k < #m and m[c.k + 1].s <= c.s do
        c.k = c.k + 1
    end
    local a, b = m[c.k], m[math.min(#m, c.k + 1)]
    local tope = math.min(c.atras and AvionVuelo.rodaje.atras or math.huge, a.v)
    if c.v < tope then
        c.v = math.min(tope, c.v + AvionVuelo.rodaje.acelera * dt)
    else
        c.v = math.max(tope, c.v - 2 * AvionVuelo.rodaje.frena * dt)
    end
    c.s = math.min(m[#m].s, c.s + math.max(c.v, 0.05) * dt)
    local t = b.s > a.s and math.min(1, (c.s - a.s) / (b.s - a.s)) or 1
    d.x, d.y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
    local rumbo = a.rumbo + angulo(b.rumbo - a.rumbo) * t
    d.rumbo = c.atras and angulo(rumbo + math.pi) or rumbo
    local sentido = c.atras and -1 or 1
    d.vx, d.vy, d.vz = math.cos(d.rumbo) * c.v * sentido, math.sin(d.rumbo) * c.v * sentido, 0
    local cr, sr = math.cos(d.rumbo), math.sin(d.rumbo)
    local z0 = alturaSuelo(d, d.x, d.y)
    local z1 = alturaSuelo(d, d.x + cr * 19.5, d.y + sr * 19.5)
    d.z, d.cabeceo, d.alabeo = z0, math.atan2(z1 - z0, 19.5), 0
    d.quiereCabeceo, d.quiereAlabeo = d.cabeceo, 0
    d.enTierra, d.alto = true, 0
    return c.s >= m[#m].s - 1e-3
end

--- Plaza en la plataforma (a lo largo, m) donde aparcará al llegar.
function Robot:setPlaza(a)
    self.datos.vueloAvion.plaza = a
end

--- Ya aparcado en su plaza (a lo largo, m), de morro al norte, con la rampa
-- abierta.
function Robot:setEstacionado(a)
    local d = self.datos.vueloAvion
    local P = require('batalla.sitios.plano').aerodromo.plataforma
    d.plaza = a
    d.x, d.y = base(d, a, P.plaza)
    d.rumbo = math.atan2(d.ux, -d.uy)
    d.z = alturaSuelo(d, d.x, d.y)
    d.vx, d.vy, d.vz = 0, 0, 0
    d.cabeceo, d.alabeo = 0, 0
    d.enTierra, d.embarcado, d.quedarse = true, true, true
    d.fase, d.reloj = 'estacionado', 0
    AvionVuelo.colocar(self, d)
end

--- Con la pista libre (trafico_aereo.lua): el que espera en la calle entra.
function Robot:setPistaLibre()
    self.datos.vueloAvion.pistaLibre = true
end

--- Fase del vuelo y si ocupa la pista (en el aire para tomar, en ella o
-- entrando o saliendo de ella).
function Robot:getVuelo()
    local d = self.datos.vueloAvion
    local _, l = enBase(d, d.x, d.y)
    local f = d.fase
    local pista = f == 'final' or f == 'toma' or f == 'frenada' or f == 'motor' or f == 'circuito'
        or f == 'aparcado' or f == 'carreteo' or f == 'despegue' or (f == 'ascenso' and not d.salida)
        or (f == 'rodaje' and math.abs(l) < 45)
    return f, pista
end

-- Suelo bajo el avión: altura y cabeceo del terreno entre el tren de morro
-- (19,5 m delante) y los principales (0 m).
local function suelo(d)
    local c, s = math.cos(d.rumbo), math.sin(d.rumbo)
    local z0 = alturaSuelo(d, d.x, d.y)
    local z1 = alturaSuelo(d, d.x + c * 19.5, d.y + s * 19.5)
    return z0, math.atan2(z1 - z0, 19.5)
end

-- Piloto: lo que pide en cada fase (empuje, cabeceo, alabeo, frenos...).
local function pilotar(self, d, dt)
    local V = math.sqrt(d.vx * d.vx + d.vy * d.vy + d.vz * d.vz)
    local a, l = enPista(d, d.x, d.y)
    local zCentro = alturaSuelo(d, d.px, d.py)
    local gamma = V > 1 and math.asin(limitar(d.vz / V, -1, 1)) or 0

    -- Capas de fuera.
    local function velocidad(objetivo)
        d.empuje = limitar(0.45 + 0.12 * (objetivo - V), 0, 1)
    end
    local function trayectoria(gammaQuerida)
        -- Morro = trayectoria querida + el ángulo de ataque que sostiene el
        -- avión a esta velocidad, alabeo y flaps (sin él, el morro subía y
        -- bajaba sin parar), + una corrección suave de lo que falte.
        local P = AvionVuelo
        local q = 0.5 * P.rho * math.max(V, 20) ^ 2 * P.ala
        local clNecesario = P.masa * P.g * math.cos(gamma) / (q * math.max(math.cos(d.alabeo), 0.5))
        local alfa = limitar((clNecesario - P.cl0 - P.flaps * d.flaps + P.spoilers * (d.spoilers or 0)) / P.clAlfa, math.rad(-4), math.rad(12))
        d.quiereCabeceo = limitar(gammaQuerida + alfa + 0.6 * (gammaQuerida - gamma), math.rad(-8), math.rad(15))
    end
    local function altura(objetivo)
        trayectoria(limitar((objetivo - d.z) * 0.012, math.rad(-6), math.rad(10)))
    end
    local function rumbo(objetivo)
        d.quiereAlabeo = limitar(1.3 * angulo(objetivo - d.rumbo), -AvionVuelo.alabeoMaximo, AvionVuelo.alabeoMaximo)
    end
    -- Altura segura: la del circuito o 150 m sobre el terreno de debajo y
    -- de 1,5 km por delante.
    local function alturaSegura()
        local c, s = math.cos(d.rumbo), math.sin(d.rumbo)
        local h = zCentro + AvionVuelo.alturaCircuito
        for _, k in ipairs({ 0, 500, 1000, 1500 }) do
            h = math.max(h, alturaSuelo(d, d.x + c * k, d.y + s * k) + 150)
        end
        return h
    end

    d.reloj = d.reloj + dt
    local fase = d.fase
    if fase == 'aparcado' then
        d.empuje, d.freno, d.flaps = 0, 1, 1
        self:setCompuertas(0)
        -- Con pasajeros por subir (embarque.lua): rampa abajo y a esperar.
        if not d.embarcado and self.getEmbarquePendiente and self:getEmbarquePendiente() then
            d.fase, d.reloj = 'embarque', 0
        elseif d.reloj > AvionVuelo.esperaInicio and not d.retener then
            d.fase, d.reloj, d.inicioA = 'carreteo', 0, a
        end
    elseif fase == 'embarque' then
        d.empuje, d.freno = 0, 1
        local listo = not self:getEmbarquePendiente()
        self:setCompuertas(listo and 0 or 1)
        local ac = self.datos.avionCarga
        if listo and ac.puertas == 0 and ac.rampa == 0 then
            d.embarcado = true
            d.fase, d.reloj = 'aparcado', AvionVuelo.esperaInicio - 2
        end
    elseif fase == 'carreteo' then
        d.freno = V > 6 and 0.3 or 0
        d.empuje = V < 6 and 0.12 or 0
        d.rumboSuelo = rumboPista(d) - 0.004 * l
        if a - d.inicioA > AvionVuelo.carreteo then
            d.fase, d.reloj = 'despegue', 0
        end
    elseif fase == 'despegue' then
        d.empuje, d.freno, d.flaps = 1, 0, 1
        d.rumboSuelo = rumboPista(d) - 0.004 * l
        if V > AvionVuelo.velocidadRotacion then
            d.quiereCabeceo = math.rad(10)
        end
        if not d.enTierra and d.z - alturaSuelo(d, d.x, d.y) > 15 then
            d.fase, d.reloj = 'ascenso', 0
        end
    elseif d.salida and fase == 'ascenso' then
        d.fase = 'salida'
    elseif fase == 'salida' then
        -- Viaje a otro sitio (el dueño, 20-nov): sube en recta por el rumbo
        -- de la pista y, a `distanciaSalida` (en la niebla, ya no se ve),
        -- deja la escena: se guarda (ni se actualiza ni se dibuja).
        d.flaps = acercar(d.flaps, 0, dt / 8)
        velocidad(AvionVuelo.velocidadSalida)
        trayectoria(math.rad(6))
        rumbo(rumboPista(d) - 0.002 * l)
        if (d.x - d.px) ^ 2 + (d.y - d.py) ^ 2 > AvionVuelo.distanciaSalida ^ 2 then
            d.fase = 'fuera'
            self.guardado = true
            print('AVION_FUERA: el avión de carga salió de la escena')
            if os.getenv('AVION_DEMO') == 'salida' then
                love.event.quit()
            end
        end
    elseif fase == 'ascenso' or fase == 'circuito' then
        d.flaps = acercar(d.flaps, 0, dt / 8)
        velocidad(AvionVuelo.velocidadCircuito)
        altura(alturaSegura())
        local p = AvionVuelo.circuito[d.punto]
        local wx, wy = desdePista(d, p[1], p[2])
        rumbo(math.atan2(wy - d.y, wx - d.x))
        if (wx - d.x) ^ 2 + (wy - d.y) ^ 2 < 400 ^ 2 then
            d.punto = d.punto + 1
            d.fase = 'circuito'
            if d.punto > #AvionVuelo.circuito then
                d.fase, d.reloj = 'final', 0
            end
        end
    elseif fase == 'final' then
        -- Hacia la pista en el sentido contrario: `a` baja hasta el toque.
        d.flaps = acercar(d.flaps, 1, dt / 6)
        velocidad(AvionVuelo.velocidadFinal)
        local distancia = a - d.toque
        local zToque = zPista(d, d.toque)
        local zSenda = zToque + math.max(distancia, 0) * math.tan(AvionVuelo.senda)
        -- Senda: baja a 3,5° más la corrección de altura; nunca por debajo
        -- del terreno + 40 m hasta los últimos 600 m.
        local objetivo = zSenda
        if distancia > 600 then
            objetivo = math.max(zSenda, alturaSuelo(d, d.x, d.y) + 40)
        end
        trayectoria(-AvionVuelo.senda + limitar((objetivo - d.z) * 0.02, math.rad(-3), math.rad(3)))
        -- Demasiado rápido en la final: frenos de aire (spoilers a medias).
        d.spoilers = V > AvionVuelo.velocidadFinal + 6 and 0.4 or 0
        -- Alineado con el eje: rumbo de la pista (al revés) corregido por
        -- la distancia lateral.
        rumbo(rumboPista(d) + math.pi + math.atan(l / 400))
        -- Toma: a 9 m sobre la pista y ya sobre ella (no antes del umbral).
        if d.z - zPista(d, a) < 9 and a < d.toque + 250 and a > -d.pistaLargo then
            d.fase, d.reloj = 'toma', 0
        end
    elseif fase == 'toma' then
        -- Enderezar: bajar despacio (1,5 m/s más que la pista, que puede ir
        -- en cuesta), sin empuje, alas a nivel. Cuanto más alto sobre la
        -- pista, algo más deprisa (como mucho 3 m/s de más).
        d.empuje, d.spoilers = 0, 0
        local gammaPista = math.atan((zPista(d, a - 10) - zPista(d, a)) / 10)
        local sobre = d.z - zPista(d, a)
        local bajar = limitar(1.5 + 0.25 * sobre, 1.5, 3)
        trayectoria(gammaPista - math.asin(limitar(bajar / math.max(V, 1), 0, 0.2)))
        d.quiereAlabeo = 0
        rumbo(rumboPista(d) + math.pi + math.atan(l / 400))
        if d.enTierra then
            d.fase, d.reloj = 'frenada', 0
        elseif d.reloj > AvionVuelo.flotarMaximo or a < -d.pistaLargo + 150 or V < 38 then
            -- Toma fallida: motor a fondo y otra vuelta (como un avión de
            -- verdad). Ahora vuela hacia el otro lado: ese es el despegue.
            d.fase, d.reloj = 'motor', 0
            d.sentido = -d.sentido
            d.punto = 1
        end
    elseif fase == 'motor' then
        d.empuje, d.spoilers = 1, 0
        d.flaps = acercar(d.flaps, 0.5, dt / 4)
        trayectoria(math.rad(6))
        d.quiereAlabeo = 0
        if d.z - zPista(d, a) > 60 then
            d.fase, d.reloj = 'ascenso', 0
        end
    elseif fase == 'frenada' then
        d.empuje, d.freno, d.spoilers = -AvionVuelo.reversa, 1, 1
        d.quiereCabeceo = 0
        d.rumboSuelo = rumboPista(d) + math.pi + 0.004 * l
        if d.plaza and V < 9 then
            -- Sale de la pista hacia la calle de rodaje y su plaza.
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            local a0 = enBase(d, d.x, d.y)
            local hacia = (d.vx * d.ux + d.vy * d.uy) >= 0 and 1 or -1
            local aSalida = a0 + hacia * 50
            rodar(d, { { aSalida, 0 }, { aSalida, P.calle }, { d.plaza, P.calle }, { d.plaza, P.plaza } }, 'estacionado')
        elseif V < 0.3 then
            d.vx, d.vy, d.vz = 0, 0, 0
            d.empuje = 0
            d.fase, d.reloj = 'rampa', 0
        end
    elseif fase == 'rodaje' or fase == 'remolque' then
        if moverCamino(self, d, dt) then
            d.vx, d.vy = 0, 0
            d.fase, d.reloj = d.despues, 0
        end
    elseif fase == 'estacionado' then
        -- En su plaza, con la rampa abierta hasta que su vuelo se va.
        d.empuje, d.freno = 0, 1
        self:setCompuertas(d.salida and 0 or 1)
        local ac = self.datos.avionCarga
        if d.salida and ac.puertas == 0 and ac.rampa == 0 then
            -- Empujado hacia atrás hasta la calle, con la cola al este.
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            rodar(d, { { d.plaza, P.calle }, { d.plaza + 60, P.calle } }, 'calle', true)
        end
    elseif fase == 'calle' then
        -- Por la calle hasta el punto de espera de la cabecera oeste.
        local P = require('batalla.sitios.plano').aerodromo.plataforma
        rodar(d, { { P.espera, P.calle } }, 'espera')
    elseif fase == 'espera' then
        d.empuje, d.freno = 0, 1
        if d.pistaLibre then
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            rodar(d, { { P.entrada, P.calle }, { P.entrada, 0 }, { P.entrada + 65, 0 } }, 'alineado')
        end
    elseif fase == 'alineado' then
        -- En la pista, mirando al este: despega por el sentido +1.
        d.sentido = 1
        d.spoilers, d.punto = 0, 1
        d.quedarse, d.retener, d.embarcado = false, false, true
        d.vx, d.vy, d.vz = 0, 0, 0
        d.fase, d.reloj = 'aparcado', AvionVuelo.esperaInicio - 2
    elseif fase == 'rampa' then
        d.empuje, d.freno = 0, 1
        self:setCompuertas(d.reloj < AvionVuelo.rampaAbierta and 1 or 0)
        local ac = self.datos.avionCarga
        -- Llegado de otro sitio: se queda con la rampa abierta hasta que su
        -- vuelo se va en el mapa (`setSalida`).
        if d.quedarse and not d.salida then
            self:setCompuertas(1)
        elseif d.quedarse and d.salida then
            self:setCompuertas(0)
            if ac.puertas == 0 and ac.rampa == 0 then
                d.sentido = -d.sentido
                d.spoilers = 0
                d.punto = 1
                d.quedarse = false
                d.fase, d.reloj = 'aparcado', AvionVuelo.esperaInicio - 2
            end
        elseif d.reloj > AvionVuelo.rampaAbierta and ac.puertas == 0 and ac.rampa == 0 then
            -- Ahora mira al otro lado: el próximo despegue va por ahí.
            d.sentido = -d.sentido
            d.spoilers = 0
            d.punto = 1
            d.fase, d.reloj = 'aparcado', AvionVuelo.esperaInicio - 2
        end
    end
end

-- Un paso de física.
local function fisica(d, dt)
    local P = AvionVuelo
    local m = P.masa
    -- Actitud hacia lo pedido, a su ritmo.
    d.cabeceo = acercar(d.cabeceo, d.quiereCabeceo, P.ritmoCabeceo * dt)
    d.alabeo = acercar(d.alabeo, d.enTierra and 0 or d.quiereAlabeo, P.ritmoAlabeo * dt)
    local V = math.sqrt(d.vx * d.vx + d.vy * d.vy + d.vz * d.vz)
    local cr, sr = math.cos(d.rumbo), math.sin(d.rumbo)
    local cp, sp = math.cos(d.cabeceo), math.sin(d.cabeceo)
    -- Ejes del avión: morro, izquierda, arriba (con el alabeo: positivo,
    -- ala izquierda abajo, gira a la izquierda).
    local fx, fy, fz = cp * cr, cp * sr, sp
    local lx, ly = -sr, cr
    local ux0, uy0, uz0 = -sp * cr, -sp * sr, cp
    local cb, sb = math.cos(d.alabeo), math.sin(d.alabeo)
    local ux, uy, uz = ux0 * cb + lx * sb, uy0 * cb + ly * sb, uz0 * cb
    local Fx, Fy, Fz = 0, 0, -m * P.g
    -- Empuje.
    local T = d.empuje * P.empuje
    Fx, Fy, Fz = Fx + fx * T, Fy + fy * T, Fz + fz * T
    if V > 1 then
        local vx, vy, vz = d.vx / V, d.vy / V, d.vz / V
        -- Ángulo de ataque: la velocidad por debajo del morro.
        local alfa = math.atan2(-(d.vx * ux + d.vy * uy + d.vz * uz), d.vx * fx + d.vy * fy + d.vz * fz)
        local cl = limitar(P.cl0 + P.clAlfa * alfa, -0.6, P.clMax) + P.flaps * d.flaps - P.spoilers * (d.spoilers or 0)
        local q = 0.5 * P.rho * V * V * P.ala
        -- Sustentación: la parte de `arriba` perpendicular a la velocidad.
        local dot = ux * vx + uy * vy + uz * vz
        local lx2, ly2, lz2 = ux - dot * vx, uy - dot * vy, uz - dot * vz
        local n = math.sqrt(lx2 * lx2 + ly2 * ly2 + lz2 * lz2)
        if n > 1e-6 then
            local L = q * cl
            Fx, Fy, Fz = Fx + lx2 / n * L, Fy + ly2 / n * L, Fz + lz2 / n * L
        end
        local D = q * (P.cd0 + P.k * cl * cl + P.cdFlaps * d.flaps + 0.05 * (d.spoilers or 0))
        Fx, Fy, Fz = Fx - vx * D, Fy - vy * D, Fz - vz * D
        d.alfa = alfa
        d.cl = cl -- para las estelas de las alas (batalla/dream/estelas_avion.lua)
    end
    local zSuelo, pendiente = suelo(d)
    if d.enTierra then
        -- Sobre las ruedas: la carga es lo que no sostiene el ala.
        local carga = math.max(0, -Fz)
        local Vh = math.sqrt(d.vx * d.vx + d.vy * d.vy)
        local roce = (P.rodadura + P.freno * d.freno) * carga
        -- A lo largo del rumbo (la rueda de morro dirige): sin derrape.
        local adelante = Fx * cr + Fy * sr
        local signo = (d.vx * cr + d.vy * sr) >= 0 and 1 or -1
        local va = signo * Vh + adelante / m * dt
        local frena = roce / m * dt
        if math.abs(va) <= frena then
            va = 0
        else
            va = va - (va > 0 and frena or -frena)
        end
        if d.rumboSuelo then
            -- Rueda de morro: gira el avión despacio hacia lo pedido.
            d.rumbo = d.rumbo + limitar(angulo(d.rumboSuelo - d.rumbo), -0.15 * dt, 0.15 * dt) * math.min(1, Vh / 3)
        end
        d.vx, d.vy = math.cos(d.rumbo) * va, math.sin(d.rumbo) * va
        local vz = d.vz + (Fz + carga) / m * dt
        d.vz = math.max(vz, 0)
        d.cabeceo = math.max(d.cabeceo, pendiente)
        if d.quiereCabeceo <= pendiente then
            d.cabeceo = acercar(d.cabeceo, pendiente, P.ritmoCabeceo * dt)
        end
    else
        d.vx, d.vy, d.vz = d.vx + Fx / m * dt, d.vy + Fy / m * dt, d.vz + Fz / m * dt
        -- Sin derrape: el rumbo sigue a la velocidad.
        if V > 5 then
            d.rumbo = math.atan2(d.vy, d.vx)
        end
    end
    d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
    if d.z <= zSuelo then
        d.z = zSuelo
        if not d.enTierra then
            d.enTierra = true
            d.vz = 0
            d.toqueDuro = d.vzToque
        end
    elseif d.z > zSuelo + 0.3 then
        d.enTierra = false
    end
    d.vzToque = d.vz
    d.alto = d.z - zSuelo
end

--- Raíz del avión: posición, rumbo, cabeceo (morro arriba) y alabeo (ala
-- izquierda abajo).
function AvionVuelo.colocar(self, d)
    local m = PiezaRobot.multiplicar({ 1, 0, 0, d.x, 0, 1, 0, d.y, 0, 0, 1, d.z, 0, 0, 0, 1 }, PiezaRobot.rotacion('z', d.rumbo))
    m = PiezaRobot.multiplicar(m, PiezaRobot.rotacion('y', -d.cabeceo))
    m = PiezaRobot.multiplicar(m, PiezaRobot.rotacion('x', -d.alabeo))
    for k = 1, 16 do
        d.matriz[k] = m[k]
    end
    self.x, self.y, self.rumbo = d.x, d.y, d.rumbo
end

function AvionVuelo.onUpdate(self, dt)
    local d = self.datos.vueloAvion
    if dt <= 0 then
        return
    end
    pilotar(self, d, dt)
    local f = d.fase
    if f == 'rodaje' or f == 'remolque' or f == 'estacionado' or f == 'calle' or f == 'espera' then
        -- En la plataforma: lo mueve el camino, no la física.
        d.acumulado = 0
    end
    d.acumulado = math.min(d.acumulado + dt, 0.25)
    while d.acumulado >= AvionVuelo.paso do
        fisica(d, AvionVuelo.paso)
        d.acumulado = d.acumulado - AvionVuelo.paso
    end
    AvionVuelo.colocar(self, d)
    -- Ruedas: ruedan en tierra; en el aire se paran despacio.
    local Vh = math.sqrt(d.vx * d.vx + d.vy * d.vy)
    local ac = self.datos.avionCarga
    self:setRodar(d.enTierra and Vh or (ac.velocidad or 0) * math.max(0, 1 - dt * 0.5))
    if os.getenv('AVION_REGISTRO') then
        d.registro = (d.registro or 0) + dt
        if d.registro > 1 then
            d.registro = 0
            local a, l = enPista(d, d.x, d.y)
            print(string.format('VUELO %s a=%.0f l=%.0f sobrePista=%.1f V=%.1f alto=%.1f z=%.1f rumbo=%.0f cab=%.1f alab=%.1f emp=%.2f alfa=%.1f',
                d.fase, a, l, d.z - zPista(d, a), math.sqrt(d.vx ^ 2 + d.vy ^ 2 + d.vz ^ 2), d.alto or 0, d.z, math.deg(d.rumbo), math.deg(d.cabeceo),
                math.deg(d.alabeo), d.empuje, math.deg(d.alfa or 0)))
        end
    end
end

return AvionVuelo

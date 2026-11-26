--- Tropas de la escena de batalla: los tanques y lanzacohetes reales del
-- combate, formados cada bando en su lado del área a distancia real (1 px =
-- 10 cm; unos 1,7 km entre los frentes), y la pelea que se ve:
--
--   tanques        avanzan despacio en formación, apoyados en el terreno y
--                  esquivando agua, edificios y árboles; paran a disparar a
--                  1-2 km, con peor puntería cuanto más lejos, y la bala
--                  tarda lo que tarda en llegar (con su trazador)
--   lanzacohetes   se quedan en la retaguardia, detrás de sus tanques, y
--                  lanzan misiles de trayectoria alta a 2-3 km con estela
--                  continua; cayendo sobre la zona enemiga con dispersión. Con
--                  un tanque enemigo a menos de 500 m no pueden disparar (el
--                  misil necesita distancia) y son blanco fácil: los tanques
--                  enemigos los buscan primero.
--
-- Lo que pelea es exactamente lo que tiene la simulación (diseno/economia.md,
-- §3.9, F6, F10, F11):
--
--   vehículos      1:1. Entran los primeros `maxPorBando` de cada bando; el
--                  resto espera en la reserva y entra por su lado (oleadas)
--                  cada vez que un averiado se retira del campo.
--   infantería     la de la simulación (robots desde el 17-nov-2026) aún
--                  no tiene figura en la batalla 3D: no entra y sale como
--                  entró.
--   munición       cada disparo gasta de la munición del grupo de la unidad
--                  (`porDisparo`). Sin munición la unidad no dispara ni avanza:
--                  sigue en el campo y recibe daño.
--   bajas          las del combate de verdad, sin tope ni ritmo. Daño real
--                  (batalla/DANO-REAL.md, módulos de batalla/dano/): cada
--                  bala, obús, cohete o misil vuela con su balística y hace
--                  daño donde llega; los vehículos se averían por zonas
--                  (orugas, torreta, cañón, motor, tripulación) y, fuera de
--                  combate, quedan averiados (humeando, sin disparar); nunca
--                  se destruyen.
--   pasos fijos    la pelea avanza en pasos de `Tropas.pasoFijo` s con el azar
--                  de su semilla: la misma batalla da lo mismo.
--
-- Al terminar, `resultado` clasifica cada unidad (F11) en el formato de
-- `resolverBatalla` (cabecera de mundo/simulacion/batallas.lua). Solo lee el
-- combate que se le da; no cambia la simulación.
--
-- Modelos (diseno/catalogo-armamento.md, §3.6): cada vehículo es de un modelo
-- del catálogo (`u.modelo`, la clave interna), con su modelo 3D
-- (assets/modelos3d/catalogo.lua) y sus cifras (`Simulacion.fichaModelo`):
--   tanque        su cañón, munición y blindaje por zonas salen de
--                 batalla/dano/datos.lua; va a `escena.velocidad` (m/s)
--   lanzacohetes  cada salva lanza sus `proyectiles` (1 misil del Scud-B, 40
--                 cohetes del BM-21, 6 del M142 HIMARS), cada uno hacia su
--                 punto con la dispersión de juego (`escena.cep`, reparto
--                 circular normal) y con su ojiva (radio letal
--                 `escena.radio`); gasta `escena.porDisparo` misiles por
--                 proyectil (con fracción: la fuente acumula lo gastado) y
--                 llega a `escena.alcance`. Dispara lo que lleva cargado en
--                 su rampa (`escena.carga`: el Scud-B, 4 misiles de uno en
--                 uno) y recarga de su fuente (ver «Rampa de los lanzacohetes»).
--   Sin desglose (un combate de prueba), el modelo de referencia (T-72B y
--   Scud-B). Una salva de muchos proyectiles se dibuja con
--   `maxVisualesSalva` misiles como mucho; los demás vuelan igual sin
--   dibujarse (batalla/dano/proyectiles.lua).

local Simulacion = require('mundo.simulacion')
local CatalogoModelos = require('assets.modelos3d.catalogo')
local Ruido = require('mundo.ruido')
local Modelos3d = require('mundo.modelos3d')
local Matriz = require('batalla.matriz')
local Malla = require('batalla.malla')
local Suelo = require('batalla.suelo')
local Estelas = require('batalla.estelas')
local Lanzamisiles = require('batalla.lanzamisiles')
-- Orugas y tren de rodaje de los tanques (Valeria, batalla/orugas.lua).
local Orugas = require('batalla.orugas')
local Impactos = require('batalla.impactos') -- Impactos (Valeria)
local Datos = require('batalla.dano.datos') -- Daño real (Valeria, DANO-REAL.md)
local Trayectoria = require('batalla.dano.trayectoria')
local Cuerpos = require('batalla.dano.cuerpos')
local Blindaje = require('batalla.dano.blindaje')
local Proyectiles = require('batalla.dano.proyectiles')

local Armamento = Simulacion.Armamento

local Tropas = {}
Tropas.__index = Tropas

Tropas.maxPorBando = 40 -- vehículos en el campo a la vez por bando (más: oleadas)
Tropas.retiroAveriado = 12 -- s que un averiado sigue en el campo antes de dejar sitio a la reserva
Tropas.entradaReserva = 900 -- px detrás de los lanzacohetes por donde entra la reserva
Tropas.separacion = 8500 -- px del centro a la primera fila de cada bando (1,7 km entre bandos)
Tropas.lateral = 200 -- px entre tanques de una fila
Tropas.porFila = 10
Tropas.entreFilas = 260
Tropas.atrasLanzacohetes = 2200 -- px detrás de la última fila de tanques
Tropas.adelante = 4200 -- px de los tanques enemigos a los que se pone un lanzacohetes adelantado
Tropas.vida = { tanque = 3, lanzacohetes = 2 } -- vida llena de cada unidad
-- Pasos fijos (DANO-REAL.md §8.1): `actualizar` acumula el tiempo y avanza
-- la pelea en pasos de `pasoFijo` s, `maxPasos` por llamada como mucho.
Tropas.pasoFijo = 1 / 60
Tropas.maxPasos = 4

-- Munición que gasta cada tipo de unidad y tropa de la simulación que es.
local MUNICION_DE = { tanque = 'obuses', lanzacohetes = 'misiles' }
local TROPA_DE = { tanque = 'tanques', lanzacohetes = 'lanzacohetes' }
local MUNICIONES = { 'balas', 'obuses', 'misiles' }
local LADOS = { 'atacante', 'defensor' }

-- Tanques
Tropas.velocidad = 32 -- px/s en marcha (unos 11 km/h campo a través)
Tropas.velocidadOrden = 60 -- px/s con una orden del jugador (unos 21 km/h)
Tropas.giroCasco = 0.5 -- rad/s
Tropas.giroTorreta = 0.6 -- rad/s
Tropas.alcanceTanque = 21000 -- px (2,1 km): a partir de aquí abren fuego
Tropas.parada = 3000 -- px: el atacante deja de avanzar con un tanque enemigo a esta distancia
Tropas.avanceDefensor = 1500 -- px que el defensor sale al encuentro
Tropas.velocidadBala = 9000 -- px/s: solo las balas hechas a mano de las pruebas (las de verdad, dano/datos.lua)
Tropas.largoTrazador = 1300 -- px
Tropas.recarga = { 6, 11 } -- s entre disparos de un tanque
Tropas.alto = 3.5 -- s que se para un tanque para disparar

-- Fin de la pelea: un bando que en `sinFuego` s ni dispara ni avanza con
-- unidades armadas no puede alcanzar al rival y se retira (decisión de
-- El dueño); `cierre` s después del aviso la escena vuelve al mapa.
Tropas.sinFuego = 60
Tropas.cierre = 6
Tropas.radioAmenaza = 2 -- × el radio de un misil: hasta ahí se nota que cae cerca

-- Lanzacohetes
Tropas.alcanceMisil = 32000 -- px (3,2 km)
Tropas.minimoMisil = 5000 -- px (500 m): más cerca, el misil no llega a armarse
-- s que tarda en subir a la rampa una salva de su modelo (el Scud-B, un
-- misil: llenar sus cuatro, 4 veces esto; el BM-21, sus 40 cohetes de golpe).
Tropas.recargaMisil = { 13, 20 }
Tropas.entreMisilesRampa = 2.5 -- s entre dos misiles de la rampa (el Scud-B, de uno en uno)
-- s más por misil al recargar una rampa de varias salvas (el Scud-B): el
-- tiempo de subir y bajar la rampa que se ahorra al disparar los cuatro
-- seguidos. Así un camión gasta los mismos misiles por minuto que con uno
-- solo (20,8 s por misil medidos; `porDia` = 7 de la batalla simulada).
Tropas.montarMisil = 2
Tropas.cadenciaCohete = 0.5 -- s entre dos proyectiles de una salva (el BM-21: 40 en 20 s)
-- s que tardan los gatos del camión de 4 misiles en bajar hasta el suelo o
-- en recogerse (decisión del dueño, 2026-10-02: se detiene, baja los gatos,
-- sube la rampa, dispara de uno en uno, baja la rampa, sube los gatos y
-- solo entonces puede moverse; batalla/articulacion_camion.lua).
Tropas.tiempoGatos = 1.5
Tropas.maxVisualesSalva = 8 -- misiles dibujados por salva como mucho (el resto vuela sin dibujarse)
Tropas.maxParticulas = 1400
-- El misil en vuelo: el de la rampa del camión de misiles con robot conductor
-- (assets/modelos3d/catalogo.lua, `misil`); su origen es su cola, que sale
-- del riel. La batalla de 3Dream lo dibuja con la pieza del .glb del camión
-- (batalla/dream/efectos/misiles.lua); el dibujo sin 3Dream, como una vara
-- de estas medidas (px).
Tropas.misilVara = { largo = 83.2, diametro = 5 }
Tropas.radioTransitable = {
    tanque = 62,
    lanzacohetes = 86,
}
Tropas.pasilloBusqueda = 2600
Tropas.pasilloUnion = 420
Tropas.pasilloAdelante = 820
Tropas.pasilloSeparacion = 180
Tropas.pasilloSaltoBusqueda = 3
Tropas.pasilloPasoComprobacion = 40

local mallaBola -- icosaedro de radio 1, blanco: humo, polvo, fogonazos
local mallaVara -- caja de 1 x 1 x 1 centrada: trazadores y misiles
local MUESTRAS_TRANSITABLES = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local function cargar()
    if mallaBola then
        return
    end
    local m = Malla.nueva(64)
    m:icosaedro(0, 0, 0, 1, 1, { 1, 1, 1 })
    mallaBola = m:crear()
    m = Malla.nueva(64)
    m:caja(0, 0, -0.5, 1, 1, 1, 0, { 1, 1, 1 })
    mallaVara = m:crear()
end

local function entre(azar, rango)
    return rango[1] + azar:random() * (rango[2] - rango[1])
end

-- Modelos de los vehículos ------------------------------------------------------------------

--- Archivo (sin extensión) del modelo de vértices del vehículo `modelo`
-- (clave del catálogo). Los vehículos de vértices (tanques y camiones del
-- pack Synty) ya no están (el dueño, 21-nov): el camión de misiles es un
-- robot (batalla/robots/) y estas unidades viejas no salen en la batalla
-- desde el 19-nov (`Tropas.prepararBando`).
function Tropas.archivoDe(modelo)
    local entrada = CatalogoModelos.modelo(modelo)
    if entrada and not entrada.robot then
        return entrada.archivo
    end
    error('Tropas: el vehículo ' .. tostring(modelo) .. ' no tiene modelo de vértices (los vehículos viejos ya no salen)', 2)
end

--- Modelo de vértices del vehículo `modelo`, cargado una vez.
function Tropas.modeloDe(modelo)
    return Modelos3d.modelo(Tropas.archivoDe(modelo))
end

--- Modelo del vehículo de `tipo` ('tanque' o 'lanzacohetes') cuando el
-- combate no dice cuál: el de referencia (las cifras de antes).
function Tropas.modeloPorDefecto(tipo)
    return Armamento.referencia(TROPA_DE[tipo])
end

--- `n` vehículos de `tipo` ('tanques' o 'lanzacohetes') repartidos por igual
-- entre todos sus modelos (los primeros del catálogo, uno más si no sale
-- exacto): modelo -> cantidad. Para las pruebas y capturas con modelos mezclados.
function Tropas.repartoParejo(tipo, n)
    local modelos = Armamento.modelos(tipo)
    local out = {}
    for k, m in ipairs(modelos) do
        local cuantos = math.floor(n / #modelos) + (k <= n % #modelos and 1 or 0)
        if cuantos > 0 then
            out[m] = cuantos
        end
    end
    return out
end

--- s hasta subir a la rampa de `u` la siguiente salva de su modelo.
function Tropas:tiempoRecarga(u)
    local t = entre(self.azar, Tropas.recargaMisil)
    if Tropas.enRampa(u) then
        t = t + Tropas.montarMisil
    end
    return t
end

--- Ficha del modelo (`Simulacion.fichaModelo`), una vez por escena.
function Tropas:fichaDe(modelo)
    local ficha = self.fichas[modelo]
    if not ficha then
        ficha = Simulacion.fichaModelo(modelo)
        self.fichas[modelo] = ficha
    end
    return ficha
end

--- Articulaciones del camión del modelo `modelo` (una por modelo y escena).
function Tropas:lanzadorDe(modelo)
    local lanzador = self.lanzadores[modelo]
    if not lanzador then
        lanzador = Lanzamisiles.nuevo(Tropas.modeloDe(modelo), self.suelo)
        self.lanzadores[modelo] = lanzador
    end
    return lanzador
end

--- Tropas para el `combate` (ver Escena) sobre el `suelo`.
function Tropas.nuevo(suelo, combate)
    cargar()
    local self = setmetatable({}, Tropas)
    self.suelo = suelo
    self.combate = combate
    self.azar = love.math.newRandomGenerator(math.floor(math.abs(combate.cx * 7 + combate.cy * 13)) % 2147483647 + 1)
    self.reloj = 0
    self.unidades = {}
    self.balas = {}
    self.misiles = {}
    self.particulas = {}
    self.estelas = Estelas.nuevas()
    self.bajas = { 0, 0 } -- unidades fuera de combate (averiadas o caídas) por bando
    self.avance = { 0, 0 }
    self.ultimoFuego = { 0, 0 } -- reloj del último disparo de cada bando
    self.ultimoAvance = { 0, 0 } -- reloj del último paso de una unidad armada de cada bando
    self.fichas = {}
    self.lanzadores = {}
    -- Daño real (DANO-REAL.md): pasos fijos, cuerpos, proyectiles y cuentas.
    self.acumulado = 0
    self.relojVista = 0
    self.pasos = 0
    self.estadisticas = Tropas.estadisticasVacias()
    self.cuerpos = Cuerpos.nuevos(self)
    self.proyectiles = Proyectiles.nuevos(self)
    self.bandos = {
        Tropas.prepararBando(combate.atacante),
        Tropas.prepararBando(combate.defensor),
    }
    self:formar(1, combate.atacante)
    self:formar(2, combate.defensor)
    return self
end

--- Fuentes de un bando del `combate`: de dónde sale cada unidad, de qué
-- modelos (`tanquesPor`, `lanzacohetesPor`: modelo -> cantidad) y su
-- munición. Con `bando.fuentes` (una batalla de la simulación: cada grupo,
-- `clave` = su id, y la guarnición, `clave` = 'sitio'), esas; sin ellas (un
-- combate de prueba), una sola con todo, los modelos del bando (si los dice)
-- y munición sin límite.
local function fuentesDe(bando)
    local out = {}
    for _, f in ipairs(bando.fuentes or {}) do
        local municion
        if f.municion then
            municion = {}
            for _, m in ipairs(MUNICIONES) do
                municion[m] = math.max(0, math.floor(f.municion[m] or 0))
            end
        end
        out[#out + 1] = {
            clave = f.clave,
            soldados = f.soldados or 0,
            tanques = f.tanques or 0,
            lanzacohetes = f.lanzacohetes or 0,
            tanquesPor = f.tanquesPor,
            lanzacohetesPor = f.lanzacohetesPor,
            municion = municion,
            gastado = { balas = 0, obuses = 0, misiles = 0 },
            cargado = { balas = 0, obuses = 0, misiles = 0 },
        }
    end
    if #out == 0 then
        out[1] = {
            soldados = bando.soldados or 0,
            tanques = bando.tanques or 0,
            lanzacohetes = bando.lanzacohetes or 0,
            tanquesPor = bando.tanquesPor,
            lanzacohetesPor = bando.lanzacohetesPor,
            gastado = { balas = 0, obuses = 0, misiles = 0 },
            cargado = { balas = 0, obuses = 0, misiles = 0 },
        }
    end
    return out
end

--- Lo que pelea un bando: sus fuentes (munición e infantería). Sin
-- vehículos: tanques y el lanzacohetes viejo ya no salen en la batalla 3D
-- (el dueño, 19-nov: «los tanques no los usaremos, todo esto será un mundo de
-- robots»; pelean los robots de batalla/robots/, y el lanzacohetes es el
-- camión de misiles que conduce un robot).
function Tropas.prepararBando(bando)
    local fuentes = fuentesDe(bando)
    local soldados = 0
    for _, f in ipairs(fuentes) do
        soldados = soldados + f.soldados
    end
    return {
        fuentes = fuentes,
        cola = {}, -- vehículos que aún no han entrado (ninguno)
        -- La infantería de la simulación (robots desde el 17-nov) aún no tiene
        -- figura en la batalla 3D: no entra en el campo y sale como entró.
        soldados = soldados,
        vehiculos = 0,
        todas = {}, -- cada unidad que ha estado en el campo, en orden de entrada
        enCampo = 0, -- vehículos en el campo ahora (averiados sin retirar incluidos)
        entradas = 0,
    }
end

function Tropas:usarFisica(fisica)
    self.fisica = fisica
end

function Tropas:usarRayos(rayos)
    self.rayos = rayos
end

function Tropas:usarSonido(sonido)
    self.sonido = sonido
end

--- Solo la vista recibe la sacudida; los impactos no empujan los cuerpos.
function Tropas:usarCamara(camara)
    self.camara = camara
end

-- Efectos (Camila, batalla/efectos.lua): estelas, fogonazos, impactos. Solo
-- mira lo que pasa; no cambia la simulación ni su azar.
function Tropas:usarEfectos(efectos)
    self.efectos = efectos
end

function Tropas:sonar(nombre, x, y, z, volumen, tono)
    if self.sonido then
        self.sonido:reproducir(nombre, x, y, z, volumen, tono)
    end
end

function Tropas:lineaVisible(origen, destino)
    -- Impactos (Valeria): contra el relieve fino que se dibuja (una loma en
    -- medio tapa), no contra la malla gruesa de rayos.
    local s = self.suelo
    return Impactos.visible(s, origen.x, origen.y, origen.z + 22, destino.x, destino.y, destino.z + 18)
end

function Tropas:radioUnidad(tipo)
    return Tropas.radioTransitable[tipo or 'tanque'] or Tropas.radioTransitable.tanque
end

--- ¿El terreno acepta una unidad de `tipo` en (x, y)? Usa la decisión de
-- Valeria (`suelo:transitable`) y la comprueba bajo el radio de la unidad.
function Tropas:transitable(x, y, tipo)
    local s = self.suelo
    local radio = self:radioUnidad(tipo)
    if s.transitable and not s:transitable(x, y) then
        return false
    end
    if s.agua and s.agua:enAgua(x, y, radio) then
        return false
    end
    for _, muestra in ipairs(MUESTRAS_TRANSITABLES) do
        local px = x + muestra[1] * radio
        local py = y + muestra[2] * radio
        if s.transitable and not s:transitable(px, py) then
            return false
        end
    end
    return true
end

--- ¿Puede estar un vehículo en (x, y)? En tierra firme bajo todo el casco,
-- dentro del área y fuera del edificio. Con `arboles`, solo estorban los
-- árboles (para moverse); sin él, cualquier planta (para formar).
function Tropas:libre(x, y, arboles, tipo)
    local s = self.suelo
    local margen = 400
    if x < s.x0 + margen or y < s.y0 + margen then
        return false
    end
    if x > s.x0 + Suelo.lado - margen or y > s.y0 + Suelo.lado - margen then
        return false
    end
    -- Límite (Valeria): nada forma ni avanza fuera del campo de batalla.
    if s.limite and not s.limite:dentro(x, y, 60) then
        return false
    end
    if s:ocupado(x, y, 90) then
        return false
    end
    -- Agua (Valeria): ni formar ni avanzar en el agua ni en su orilla.
    if s.agua and (s.agua:enAgua(x, y) or s.agua:enAgua(x, y, 80)) then
        return false
    end
    if not self:transitable(x, y, tipo) then
        return false
    end
    if arboles then
        if s:plantaCerca(x, y, 45, true) then
            return false
        end
    elseif s:plantaCerca(x, y, 55) then
        return false
    end
    for _, d in ipairs({ { 0, 0 }, { 45, 0 }, { -45, 0 }, { 0, 25 }, { 0, -25 } }) do
        if s:altura(x + d[1], y + d[2]) < 3 then
            return false
        end
    end
    if s:desnivel(x, y, 55) > Suelo.maxDesnivelVehiculo then
        return false
    end
    return true
end

--- Comprueba todo el trayecto recto, incluida la huella de la unidad. Un
-- destino seco no basta: el atajo hasta él puede cortar agua o un árbol.
function Tropas:segmentoLibre(x0, y0, x1, y1, tipo)
    local dx, dy = x1 - x0, y1 - y0
    local pasos = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / Tropas.pasilloPasoComprobacion))
    local radio = self:radioUnidad(tipo)
    local suelo = self.suelo
    for k = 0, pasos do
        local t = k / pasos
        local x, y = x0 + dx * t, y0 + dy * t
        if not self:libre(x, y, true, tipo) then
            return false
        end
        if suelo.limite and not suelo.limite:dentro(x, y, radio) then
            return false
        end
        if suelo:plantaCerca(x, y, radio, true) then
            return false
        end
    end
    return true
end

--- ¿Hay otra unidad (viva o no) a menos de `radio` px de (x, y)? Con
-- `enMarcha`, no estorban las de ese bando que también marchan con una
-- orden (se apartan).
function Tropas:vehiculoCerca(x, y, radio, salvo, enMarcha)
    for _, o in ipairs(self.unidades) do
        local r = radio
        local marcha = enMarcha
            and o.bando == enMarcha
            and not o.muerto
            and ((o.orden and o.orden.avanza) or o.apartarse)
        if o ~= salvo and not marcha and (o.x - x) ^ 2 + (o.y - y) ^ 2 < r * r then
            return true
        end
    end
    return false
end

--- El sitio libre más cercano a (x, y), conectado a un pasillo de avance.
-- Si la formación cae en una isla, se coloca junto al extremo de su bando.
function Tropas:buscarSitio(x, y, radio, tipo, bando)
    radio = radio or 110
    local pasillos = self.suelo.pasillos or {}
    local puntos = {}
    local requiereConexion = false
    local alcance = (Tropas.pasilloBusqueda + 1600) ^ 2
    for _, pasillo in ipairs(pasillos) do
        if not pasillo.ramal and #pasillo.x > 1 then
            requiereConexion = true
            -- Solo los puntos que puede alcanzar esta espiral: evita volver
            -- a recorrer todos los pasillos por cada posición candidata.
            for indice = 1, #pasillo.x, Tropas.pasilloSaltoBusqueda do
                local px, py = pasillo.x[indice], pasillo.y[indice]
                if (px - x) ^ 2 + (py - y) ^ 2 <= alcance then
                    puntos[#puntos + 1] = { x = px, y = py }
                end
            end
        end
    end

    local function libreParaFormar(px, py)
        return self:libre(px, py, false, tipo) and not self:vehiculoCerca(px, py, radio)
    end

    local function conectado(px, py)
        if not requiereConexion then
            return true
        end
        local mejor
        local mejorD = Tropas.pasilloBusqueda ^ 2
        for _, punto in ipairs(puntos) do
            local d = (punto.x - px) ^ 2 + (punto.y - py) ^ 2
            if d < mejorD then
                mejor, mejorD = punto, d
            end
        end
        return mejor and self:segmentoLibre(px, py, mejor.x, mejor.y, tipo)
    end

    for k = 0, 400 do
        local a = k * 2.39996
        local r = math.sqrt(k) * 80
        local px, py = x + math.cos(a) * r, y + math.sin(a) * r
        if libreParaFormar(px, py) and conectado(px, py) then
            return px, py
        end
    end

    for _, pasillo in ipairs(pasillos) do
        if not pasillo.ramal and #pasillo.x > 1 then
            local direccion = bando == 2 and -1 or 1
            local indice = bando == 2 and #pasillo.x or 1
            local recorrido = 0
            while recorrido <= 1600 do
                local siguiente = indice + direccion
                if siguiente < 1 or siguiente > #pasillo.x then
                    break
                end
                local dx = pasillo.x[siguiente] - pasillo.x[indice]
                local dy = pasillo.y[siguiente] - pasillo.y[indice]
                local largo = math.sqrt(dx * dx + dy * dy)
                if largo > 0 then
                    for _, lateral in ipairs({ 0, -180, 180, -90, 90 }) do
                        local px = pasillo.x[indice] - dy / largo * lateral
                        local py = pasillo.y[indice] + dx / largo * lateral
                        if
                            libreParaFormar(px, py)
                            and self:segmentoLibre(px, py, pasillo.x[indice], pasillo.y[indice], tipo)
                        then
                            return px, py
                        end
                    end
                end
                recorrido = recorrido + largo
                indice = siguiente
            end
        end
    end
    return nil
end

--- Forma un bando (1 atacante, 2 defensor) en su lado del área, mirando al
-- otro: los tanques delante, en filas, y los lanzacohetes en la retaguardia.
-- Con `bando.adelantados`, esos lanzacohetes se ponen muy por delante de sus
-- tanques, cerca de los enemigos (lo que haría un bando que los coloca mal).
function Tropas:formar(indice, bando)
    local c = self.combate
    local datos = self.bandos[indice]
    local ca, sa = math.cos(c.angulo), math.sin(c.angulo)
    local lado = indice == 1 and -1 or 1
    -- Con preparación, el combate trae su propia separación (batalla/despliegue.lua).
    local separacionBandos = c.separacion or Tropas.separacion
    -- Frente del bando y hacia dónde mira (al otro bando): lo usan también
    -- las oleadas para entrar por su lado.
    datos.geometria = {
        fx = c.cx + ca * separacionBandos * lado,
        fy = c.cy + sa * separacionBandos * lado,
        rumbo = indice == 1 and c.angulo or c.angulo + math.pi,
        atrasX = ca * lado,
        atrasY = sa * lado,
        ca = ca,
        sa = sa,
    }
    datos.color = bando.color
    -- Los primeros `maxPorBando` de la cola forman; el resto, a la reserva.
    local primeros = { tanque = {}, lanzacohetes = {} }
    local cola = datos.cola
    for k = 1, math.min(Tropas.maxPorBando, #cola) do
        local v = cola[k]
        primeros[v.tipo][#primeros[v.tipo] + 1] = v
    end
    datos.cola = {}
    for k = Tropas.maxPorBando + 1, #cola do
        datos.cola[#datos.cola + 1] = cola[k]
    end
    local tanques = primeros.tanque
    local lanzacohetes = primeros.lanzacohetes
    local adelantados = math.min(bando.adelantados or 0, #lanzacohetes)
    -- Lo que no encuentra sitio vuelve a la cola.
    local function poner(v, k, cuantos, fondo, separacion)
        local u = self:poner(indice, v, k, cuantos, fondo, separacion)
        if not u then
            table.insert(datos.cola, 1, v)
        end
        return u
    end
    for k = 0, #tanques - 1 do
        poner(tanques[k + 1], k, #tanques, 0, Tropas.lateral)
    end
    local filasTanques = math.max(1, math.ceil(#tanques / Tropas.porFila))
    local fondo = (filasTanques - 1) * Tropas.entreFilas + Tropas.atrasLanzacohetes
    datos.fondo = fondo
    for k = 0, adelantados - 1 do
        local u = poner(lanzacohetes[k + 1], k, adelantados, -(separacionBandos * 2 - Tropas.adelante), 600)
        if u then
            u.adelantado = true
        end
    end
    local atras = #lanzacohetes - adelantados
    for k = 0, atras - 1 do
        poner(lanzacohetes[adelantados + k + 1], k, atras, fondo, Tropas.lateral * 1.6)
    end
end

--- Cifras de la escena del modelo de `u` (vida, daño, velocidad, alcance y
-- salva), de su ficha (diseno/catalogo-armamento.md, §3.6 y F10 a F12).
function Tropas:armar(u)
    u.modelo = u.modelo or Tropas.modeloPorDefecto(u.tipo)
    local ficha = self:fichaDe(u.modelo)
    local escena = ficha.escena
    local ref = self:fichaDe(Tropas.modeloPorDefecto(u.tipo))
    u.velocidadModelo = ficha.juego.velocidad
    if u.tipo == 'tanque' then
        u.vidaMax = escena.impactos
        u.danoDisparo = escena.danoImpacto
        u.alcance, u.minimo = escena.alcance * 10000, 0
        u.modelo3d = Tropas.modeloDe(u.modelo)
        u.canonDatos = Datos.canon(u.modelo)
    else
        u.vidaMax = Tropas.vida.lanzacohetes * ficha.juego.vida / ref.juego.vida
        u.alcance = escena.alcance * 10000
        u.minimo = escena.alcanceMinimo * 10000
        u.proyectiles = escena.proyectiles
        u.carga = escena.carga or escena.proyectiles
        u.cargados = 0
        u.radio = escena.radio * 10
        u.cep = escena.cep * 10
        u.porDisparo = escena.porDisparo
        -- El proyectil a escala de su radio (el misil del Scud-B mide 10 m).
        u.escalaProyectil = escena.radio / ref.escena.radio
        u.lanzador = self:lanzadorDe(u.modelo)
        u.ojiva = Datos.ojiva(u.modelo, u.radio)
    end
    u.vida = u.vidaMax
    Blindaje.iniciar(u)
end

--- Pone en el campo la unidad `v` ({ tipo, fuente, modelo }) del bando
-- `indice`, la `k`-ésima de `cuantos` en filas de `Tropas.porFila`, a `fondo`
-- px detrás del frente y a `separacion` px entre columnas, en el sitio libre
-- más cercano. Devuelve la unidad o nil si no cabe.
function Tropas:poner(indice, v, k, cuantos, fondo, separacion)
    local datos = self.bandos[indice]
    local geo = datos.geometria
    local tipo = v.tipo
    local fila = math.floor(k / Tropas.porFila)
    local enFila = math.min(Tropas.porFila, cuantos - fila * Tropas.porFila)
    local columna = k % Tropas.porFila - (enFila - 1) / 2
    local d = fondo + fila * Tropas.entreFilas
    local x = geo.fx + geo.atrasX * d - geo.sa * columna * separacion
    local y = geo.fy + geo.atrasY * d + geo.ca * columna * separacion
    local radio = 110
    x, y = self:buscarSitio(x, y, radio, tipo, indice)
    if not x then
        return nil
    end
    datos.entradas = datos.entradas + 1
    local u = {
        bando = indice,
        tipo = tipo,
        numero = datos.entradas, -- orden de entrada en su bando (para el sorteo de F11)
        fuente = v.fuente,
        modelo = v.modelo, -- clave del catálogo (los vehículos)
        entrada = self.reloj,
        x = x,
        y = y,
        rumbo = geo.rumbo + (self.azar:random() - 0.5) * 0.12,
        rumboBando = geo.rumbo,
        color = datos.color,
        torreta = 0,
        retroceso = 0,
        elevacion = 0,
        espera = 1 + self.azar:random() * 5,
        buscar = self.azar:random() * 1.5,
        alto = 0,
        quieto = 0,
        avanzado = 0,
        fase = 'espera',
        quemado = 0,
    }
    self:armar(u)
    u.z = self.suelo:altura(x, y)
    u.casco = Modelos3d.postura(self.suelo, x, y, u.z, u.rumbo, {})
    if tipo == 'lanzacohetes' then
        u.lanzador:inicializar(u)
        -- Llega al campo con lo que su grupo tenga de verdad, hasta llenar la
        -- rampa: min(carga, munición libre de su fuente); con 1 misil, 1; con 0,
        -- ninguno. Solo un combate de prueba (sin munición) llega lleno.
        Tropas.recargar(u)
    elseif tipo == 'tanque' then
        -- Con un modelo de orugas animables, sus números y matrices.
        local orugas = Orugas.de(u.modelo3d)
        if orugas then
            orugas:inicializar(u)
        end
    end
    self.unidades[#self.unidades + 1] = u
    datos.todas[#datos.todas + 1] = u
    datos.enCampo = datos.enCampo + 1
    return u
end

-- Oleadas ------------------------------------------------------------------------------------

--- Quita del campo un averiado (se lo llevan a retaguardia): deja de estar en
-- `unidades`, en la física y en los efectos, pero sigue en su bando para el
-- resultado.
function Tropas:retirar(u)
    for k = #self.unidades, 1, -1 do
        if self.unidades[k] == u then
            table.remove(self.unidades, k)
            break
        end
    end
    if u.colision then
        if self.fisica and self.fisica.unidadDe then
            self.fisica.unidadDe[u.colision:getBody()] = nil
        end
        u.colision:destroy()
        u.colision = nil
    end
    if self.efectos and self.efectos.olvidar then
        self.efectos:olvidar(u)
    end
    u.retirado = true
    local datos = self.bandos[u.bando]
    datos.enCampo = datos.enCampo - 1
end

--- Oleadas: con reserva esperando, el averiado más antiguo de cada bando que
-- lleve `retiroAveriado` s en el campo se retira y entra el siguiente de la
-- reserva por la retaguardia de su lado.
function Tropas:relevar()
    for indice = 1, 2 do
        local datos = self.bandos[indice]
        if #datos.cola > 0 then
            if datos.enCampo < Tropas.maxPorBando then
                self:entrarReserva(indice)
            else
                local viejo
                for _, u in ipairs(self.unidades) do
                    local listo = u.averiado and u.bando == indice and self.reloj - u.caida >= Tropas.retiroAveriado
                    if listo and (not viejo or u.caida < viejo.caida) then
                        viejo = u
                    end
                end
                if viejo then
                    self:retirar(viejo)
                    self:entrarReserva(indice)
                end
            end
        end
    end
end

--- Entra el siguiente vehículo de la reserva del bando `indice`, detrás de
-- sus lanzacohetes. Si no encuentra sitio, sigue esperando.
function Tropas:entrarReserva(indice)
    local datos = self.bandos[indice]
    local v = datos.cola[1]
    if not v or self.reloj < (datos.esperaEntrada or 0) then
        return nil
    end
    local k = datos.entradas % Tropas.porFila
    local u = self:poner(indice, v, k, Tropas.porFila, datos.fondo + Tropas.entradaReserva, Tropas.lateral * 1.6)
    if not u then
        -- Buscar sitio cuesta: se vuelve a probar dentro de un rato.
        datos.esperaEntrada = self.reloj + 2
        return nil
    end
    table.remove(datos.cola, 1)
    u.reserva = true
    if self.fisica then
        self.fisica:crearUnidad(u)
    end
    return u
end

-- Munición -----------------------------------------------------------------------------------

--- Lo que gasta un disparo de `u` (F6): un cañonazo, 1 obús; un proyectil de
-- una salva, los misiles de su modelo (`porDisparo`, F11: el Scud-B, 1; el
-- BM-21, una fracción por cohete).
function Tropas.gastoDisparo(u)
    local tipo = MUNICION_DE[u.tipo]
    if u.porDisparo then
        return tipo, u.porDisparo
    end
    return tipo, Simulacion.produccion.municion[tipo].porDisparo
end

--- Munición que le queda LIBRE a la fuente de `u` para su tipo: ni gastada
-- ni cargada en la rampa de un camión (infinita en un combate de prueba).
function Tropas.municionQueda(u)
    local f = u.fuente
    if not (f and f.municion) then
        return math.huge
    end
    local tipo = MUNICION_DE[u.tipo]
    local cargado = f.cargado and f.cargado[tipo] or 0
    return f.municion[tipo] - f.gastado[tipo] - cargado
end

-- Rampa de los lanzacohetes (decisión del dueño, 2026-10-02) --------------------------------------
--
-- Cada camión lleva cargados como mucho `Tropas.cargaMaxima(u)` proyectiles
-- (el Scud-B, 4 misiles; el BM-21 y el HIMARS, una salva: 40 y 6). Los
-- carga de la munición de su fuente (el grupo o, en la guarnición, el
-- polvorín de su ciudad): al entrar al campo, lleno, y luego en la fase
-- 'recarga', una salva de su modelo cada `Tropas.recargaMisil` s (el Scud-B,
-- un misil). Lo cargado queda APARTADO en la fuente (`f.cargado`): otro
-- camión no lo puede cargar. Al disparar, cada proyectil sale de la rampa
-- y entonces, y solo entonces, se GASTA: `porDisparo` misiles de munición
-- (el Scud-B, 1 misil = 1 de munición; los 4 = 4). Lo que queda cargado al
-- terminar la batalla no se ha gastado y vuelve con su grupo, salvo lo de un
-- camión destruido o averiado: explota con él y cuenta como gastado
-- (`Tropas.perderCarga`). Un camión
-- con la rampa vacía y sin nada que cargar no dispara.
--
-- API PARA LA ANIMACIÓN DE DISPARO (Valeria, batalla/lanzamisiles.lua):
--   Tropas.cargaMaxima(u)         proyectiles que caben en la rampa
--   Tropas.misilesCargados(u)     los que lleva cargados ahora (0 a cargaMaxima)
--   Tropas.ranuraCargada(u, i)    ¿sigue en la rampa el misil de la ranura i?
--                                 Salen en orden 1, 2, 3, 4: la ranura i está
--                                 cargada si i > cargaMaxima - misilesCargados
--   Tropas.siguienteRanura(u)     la ranura del próximo disparo (nil: vacía)
--   Tropas.enRampa(u)             true si dispara de uno en uno de una rampa
--                                 (el Scud-B), false con cohetes en tubos
--   lanzador:bocaDeRanura(i)      (opcional, en batalla/lanzamisiles.lua) el
--                                 índice de `modelo.bocas` por el que sale el
--                                 misil de la ranura i; sin ella, `bocas[i]`
--   tropas:dispararCargado(u)     saca un proyectil de la rampa y lo gasta
--                                 (true) o false si la rampa está vacía. Lo
--                                 llama `lanzarMisil`; la animación no
--                                 necesita llamarlo: solo leer lo de arriba.
--   Tropas.recargar(u, n)         sube a la rampa hasta `n` proyectiles (sin
--                                 `n`, hasta llenarla) de la fuente; devuelve
--                                 cuántos subió
--   u.misilCargado                true mientras la rampa no esté vacía (la
--                                 pieza `misilCarga` del modelo de un misil)

--- Munición que gasta un proyectil de la rampa de `u`.
local function porProyectil(u)
    local _, cuanto = Tropas.gastoDisparo(u)
    return cuanto
end

--- Proyectiles que caben en la rampa de `u`.
function Tropas.cargaMaxima(u)
    return u.carga or u.proyectiles or 1
end

--- ¿Lleva `u` una rampa de varios misiles que salen de uno en uno (el
-- Scud-B: 4 de 1)? Los cohetes en tubos (BM-21, HIMARS) cargan una salva.
function Tropas.enRampa(u)
    return Tropas.cargaMaxima(u) > (u.proyectiles or 1)
end

--- Proyectiles cargados ahora en la rampa de `u`.
function Tropas.misilesCargados(u)
    return u.cargados or 0
end

--- ¿Sigue en la rampa el misil de la ranura `i` (1 a cargaMaxima)? Salen en orden.
function Tropas.ranuraCargada(u, i)
    local carga = Tropas.cargaMaxima(u)
    return i >= 1 and i <= carga and i > carga - Tropas.misilesCargados(u)
end

--- Ranura del próximo disparo de `u`, o nil con la rampa vacía.
function Tropas.siguienteRanura(u)
    local cargados = Tropas.misilesCargados(u)
    if cargados <= 0 then
        return nil
    end
    return Tropas.cargaMaxima(u) - cargados + 1
end

--- Proyectiles que `u` podría subir ahora a su rampa (los huecos, sin pasar
-- de la munición libre de su fuente).
function Tropas.puedeCargar(u)
    local hueco = Tropas.cargaMaxima(u) - Tropas.misilesCargados(u)
    local libre = Tropas.municionQueda(u)
    if libre == math.huge then
        return hueco
    end
    local enteros = math.floor(libre / porProyectil(u) + 1e-9)
    return math.max(0, math.min(hueco, enteros))
end

--- Sube a la rampa de `u` hasta `n` proyectiles (sin `n`, hasta llenarla)
-- de la munición libre de su fuente. Devuelve cuántos subió.
function Tropas.recargar(u, n)
    local sube = Tropas.puedeCargar(u)
    if n then
        sube = math.min(sube, n)
    end
    if sube > 0 then
        u.cargados = Tropas.misilesCargados(u) + sube
        local f = u.fuente
        if f and f.municion then
            local tipo = MUNICION_DE[u.tipo]
            f.cargado = f.cargado or { balas = 0, obuses = 0, misiles = 0 }
            f.cargado[tipo] = f.cargado[tipo] + sube * porProyectil(u)
        end
    end
    u.misilCargado = Tropas.misilesCargados(u) > 0
    return sube
end

--- Saca un proyectil de la rampa de `u` y gasta su munición (F6). False si
-- la rampa está vacía.
function Tropas:dispararCargado(u)
    if Tropas.misilesCargados(u) <= 0 then
        return false
    end
    u.cargados = u.cargados - 1
    local f = u.fuente
    if f then
        local tipo, cuanto = Tropas.gastoDisparo(u)
        if f.municion and f.cargado then
            f.cargado[tipo] = math.max(0, f.cargado[tipo] - cuanto)
        end
        f.gastado[tipo] = f.gastado[tipo] + cuanto
    end
    u.misilCargado = u.cargados > 0
    self.ultimoFuego[u.bando] = self.reloj
    return true
end

--- El camión `u` cae (destruido o averiado) con proyectiles en la rampa:
-- explotan con él (decisión del dueño, 2026-10-02). Salen de lo apartado en
-- su fuente y cuentan como GASTADOS (suman al gasto de la batalla): no
-- vuelven al grupo ni pasan a otro camión. Devuelve la munición perdida.
function Tropas.perderCarga(u)
    local cargados = Tropas.misilesCargados(u)
    if cargados <= 0 then
        u.misilCargado = false
        return 0
    end
    local tipo = MUNICION_DE[u.tipo]
    local cuanto = cargados * porProyectil(u)
    local f = u.fuente
    if f then
        if f.municion and f.cargado then
            f.cargado[tipo] = math.max(0, f.cargado[tipo] - cuanto)
        end
        f.gastado[tipo] = f.gastado[tipo] + cuanto
    end
    u.cargados = 0
    u.misilCargado = false
    u.cargaPerdida = (u.cargaPerdida or 0) + cuanto
    return cuanto
end

--- ¿Se ha quedado `u` sin munición? Un lanzacohetes, con la rampa vacía y
-- sin munición libre para cargar un proyectil.
function Tropas.sinMunicion(u)
    if u.tipo == 'lanzacohetes' and u.carga then
        return Tropas.misilesCargados(u) <= 0 and Tropas.puedeCargar(u) <= 0
    end
    local queda = Tropas.municionQueda(u)
    if u.porDisparo then
        return queda < u.porDisparo - 1e-9
    end
    return queda <= 0
end

--- Gasta la munición de un disparo de `u`. Sin munición devuelve false y no
-- dispara; con menos de un disparo entero, gasta lo que queda. Un
-- lanzacohetes dispara de su rampa (`dispararCargado`).
function Tropas:gastar(u)
    if u.tipo == 'lanzacohetes' and u.carga then
        return self:dispararCargado(u)
    end
    local tipo, cuanto = Tropas.gastoDisparo(u)
    local queda = Tropas.municionQueda(u)
    if Tropas.sinMunicion(u) then
        return false
    end
    local f = u.fuente
    if f then
        f.gastado[tipo] = f.gastado[tipo] + math.min(queda, cuanto)
    end
    self.ultimoFuego[u.bando] = self.reloj
    return true
end

--- Munición de un bando: { balas, obuses, misiles } con lo que lleva, lo que
-- ha gastado y si es sin límite (combate de prueba).
function Tropas:municionBando(indice)
    local lleva, gastado, limitada = {}, {}, false
    for _, m in ipairs(MUNICIONES) do
        lleva[m], gastado[m] = 0, 0
    end
    for _, f in ipairs(self.bandos[indice].fuentes) do
        for _, m in ipairs(MUNICIONES) do
            gastado[m] = gastado[m] + f.gastado[m]
            if f.municion then
                lleva[m] = lleva[m] + f.municion[m]
            end
        end
        limitada = limitada or f.municion ~= nil
    end
    return { lleva = lleva, gastado = gastado, limitada = limitada }
end

--- Distancia (al cuadrado) entre dos vehículos.
local function distancia2(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

--- Blanco para el tanque `u`: primero un lanzacohetes enemigo que se haya
-- acercado (blanco fácil y peligroso), si no el enemigo más cercano a tiro
-- (con algo de azar para que no disparen todos al mismo). Apunta también en
-- `u.tanqueCerca` la distancia al tanque enemigo más cercano.
function Tropas:blancoDeTanque(u)
    local mejor, mejorD, facil, facilD
    local tanqueCerca = math.huge
    local prioridad = (Tropas.minimoMisil + 1500) ^ 2
    for _, o in ipairs(self.unidades) do
        if o.bando ~= u.bando and not o.muerto then
            local d2 = distancia2(o, u)
            if o.tipo == 'tanque' then
                tanqueCerca = math.min(tanqueCerca, d2)
            end
            if o.tipo == 'lanzacohetes' and d2 < prioridad and (not facil or d2 < facilD) then
                facil, facilD = o, d2
            end
            local d = d2 * (0.6 + self.azar:random() * 0.8)
            if d2 < (u.alcance or Tropas.alcanceTanque) ^ 2 and (not mejor or d < mejorD) then
                mejor, mejorD = o, d
            end
        end
    end
    u.tanqueCerca = math.sqrt(tanqueCerca)
    local candidato = facil or mejor
    if candidato and not self:lineaVisible(u, candidato) then
        return nil
    end
    return candidato
end

--- Tanque enemigo más cercano a `u` (distancia en px, o infinito).
function Tropas:tanqueEnemigoCerca(u)
    local cerca = math.huge
    for _, o in ipairs(self.unidades) do
        if o.bando ~= u.bando and not o.muerto and o.tipo == 'tanque' then
            cerca = math.min(cerca, distancia2(o, u))
        end
    end
    return math.sqrt(cerca)
end

--- Blanco para los misiles de `u`: un enemigo al azar entre el mínimo y el
-- alcance de su modelo (mejor tanques, que es lo que amenaza), o nil.
function Tropas:blancoDeMisil(u)
    local candidatos = {}
    local alcance, minimo = Tropas.alcanceDe(u)
    for _, o in ipairs(self.unidades) do
        if o.bando ~= u.bando and not o.muerto then
            local d2 = distancia2(o, u)
            if d2 > minimo ^ 2 and d2 < alcance ^ 2 then
                candidatos[#candidatos + 1] = o
                if o.tipo == 'tanque' then
                    candidatos[#candidatos + 1] = o
                end
            end
        end
    end
    if #candidatos == 0 then
        return nil
    end
    return candidatos[self.azar:random(1, #candidatos)]
end

-- Partículas ---------------------------------------------------------------------------------

--- Añade una partícula (si cabe): `p` con x, y, z, vx, vy, vz, vida, tam0,
-- tam1, color, brillo y gravedad.
function Tropas:particula(p)
    if #self.particulas >= Tropas.maxParticulas then
        return
    end
    p.t = 0
    p.vx, p.vy, p.vz = p.vx or 0, p.vy or 0, p.vz or 0
    p.gravedad = p.gravedad or 0
    p.brillo = p.brillo or 0
    p.alfa = p.alfa or 1
    self.particulas[#self.particulas + 1] = p
end

function Tropas:humo(x, y, z, tam, vida, gris, subida)
    local a = self.azar:random() * math.pi * 2
    local v = self.azar:random() * 12
    self:particula({
        x = x,
        y = y,
        z = z,
        vx = math.cos(a) * v + 18,
        vy = math.sin(a) * v + 10,
        vz = subida or 25,
        vida = vida,
        tam0 = tam * 0.5,
        tam1 = tam * 1.6,
        color = { gris, gris * 0.97, gris * 0.94 },
        alfa = 0.75,
    })
end

function Tropas:fogonazo(x, y, z, tam)
    self:particula({
        x = x,
        y = y,
        z = z,
        vida = 0.09,
        tam0 = tam,
        tam1 = tam * 0.4,
        color = { 1, 0.85, 0.45 },
        brillo = 1,
    })
end

--- Chispas y polvo de un impacto; con `fuego`, una bola de fuego (explosión).
-- `escala` agranda todo (los misiles hacen más que una bala). Con `mudo`, sin
-- sonido ni sacudida (los demás cohetes de una salva: suena el primero).
function Tropas:impacto(x, y, z, fuerte, fuego, escala, mudo)
    local k = escala or 1
    if self.camara and not mudo then
        self.camara:sacudir(x, y, z, k * (fuerte and 1 or 0.25))
    end
    if fuego and not mudo then
        self:sonar('explosion', x, y, z, math.min(1, 0.55 * k), 0.9 + self.azar:random() * 0.18)
    elseif fuerte and not mudo then
        self:sonar('impacto', x, y, z, 0.55, 0.9 + self.azar:random() * 0.22)
    end
    local chispas = fuerte and 10 or 4
    for _ = 1, chispas do
        local a = self.azar:random() * math.pi * 2
        local v = 80 + self.azar:random() * 200
        self:particula({
            x = x,
            y = y,
            z = z + 5,
            vx = math.cos(a) * v * k,
            vy = math.sin(a) * v * k,
            vz = (100 + self.azar:random() * 250) * k,
            gravedad = 700 * k,
            vida = 0.35 + self.azar:random() * 0.3,
            tam0 = 2.5 * k,
            tam1 = 1 * k,
            color = { 1, 0.75, 0.3 },
            brillo = 1,
        })
    end
    for _ = 1, fuerte and 6 or 3 do
        local a = self.azar:random() * math.pi * 2
        local v = 20 + self.azar:random() * 50
        self:particula({
            x = x,
            y = y,
            z = z,
            vx = math.cos(a) * v * k,
            vy = math.sin(a) * v * k,
            vz = (30 + self.azar:random() * 40) * k,
            vida = 1.4 + self.azar:random() * k,
            tam0 = 8 * k,
            tam1 = (fuerte and 34 or 22) * k,
            color = { 0.62, 0.55, 0.44 },
            alfa = 0.8,
        })
    end
    if fuego then
        self:particula({
            x = x,
            y = y,
            z = z + 15 * k,
            vida = 0.5,
            tam0 = 20 * k,
            tam1 = 70 * k,
            color = { 1, 0.55, 0.2 },
            brillo = 1,
        })
        self:particula({
            x = x,
            y = y,
            z = z + 25 * k,
            vida = 0.3,
            tam0 = 15 * k,
            tam1 = 45 * k,
            color = { 1, 0.9, 0.5 },
            brillo = 1,
        })
    end
end

--- Un vehículo cae destrozado: ennegrecido, humeando y, a veces, explota
-- (el lanzacohetes pierde ruedas). En la batalla ya no se usa (los vehículos
-- se averían, `averiar`); queda para las pruebas del lanzacohetes.
function Tropas:destruir(u)
    if u.muerto then
        return
    end
    u.muerto = true
    u.quemado = 1
    u.humoEspera = 0
    u.caida = self.reloj
    self.bajas[u.bando] = self.bajas[u.bando] + 1
    if self.efectos then -- Efectos (Camila)
        local explotaPronto = u.tipo == 'lanzacohetes' or self.azar:random() < 0.5
        self.efectos:destruccion(u, explotaPronto)
    end
    if u.tipo == 'lanzacohetes' then
        Tropas.perderCarga(u)
        u.lanzador.destruccion:iniciar(u, self.fisica)
        u.lanzador:actualizarMatrices(u)
    end
    local explota = u.tipo == 'lanzacohetes' or self.azar:random() < 0.5
    self:impacto(u.x, u.y, u.z + 10, true, explota, 1.6)
    if explota then
        u.explosion = self.reloj
    end
end

--- Un vehículo sin vida queda averiado: fuera de combate (`muerto`, para
-- todo lo que busca blancos o lo mueve), inmovilizado, humeando y sin
-- disparar. No explota ni pierde piezas: vuelve al taller con su daño.
function Tropas:averiar(u)
    if u.muerto then
        return
    end
    u.muerto = true
    u.vida = 0
    u.caida = self.reloj
    u.humoEspera = 0
    u.blanco = nil
    self.bajas[u.bando] = self.bajas[u.bando] + 1
    u.averiado = true
    u.quemado = 0.55
    if u.tipo == 'lanzacohetes' then
        -- Lo que lleva en la rampa explota con él: gastado, no vuelve al grupo.
        Tropas.perderCarga(u)
    end
    u.misilCargado = false
    if self.efectos then -- Efectos (Camila): humo y algo de fuego, sin explosión
        self.efectos:destruccion(u, false)
    end
    self:impacto(u.x, u.y, u.z + 10, true, false, 1.2)
end

--- Tras un golpe o una onda: el vehículo `u` con su vida al día y, si queda
-- fuera de combate (DANO-REAL.md §5.4), averiado.
function Tropas:revisarVehiculo(u)
    if u.muerto then
        return
    end
    u.vida = u.vidaMax * (1 - Blindaje.dano(u))
    if Blindaje.fueraDeCombate(u) then
        self:averiar(u)
    end
end

--- Cuentas del daño real (las imprime batalla/pruebas_dano).
function Tropas.estadisticasVacias()
    local e = {}
    for _, clave in ipairs({
        'rebote',
        'nopenetra',
        'penetra',
        'impactoTerreno',
        'impactoArbol',
        'impactoRoca',
        'impactoEdificio',
        'impactoVehiculo',
        'balaCobertura',
        'balaVehiculo',
        'balaTerreno',
        'rayosBala',
        'cubiertos',
        'metrallaCubierta',
        'explosiones',
        'golpeDirectoOjiva',
        'resueltosEnElActo',
        'rebotesVolando',
        'hazObstaculo',
        'hazBloqueado',
    }) do
        e[clave] = 0
    end
    return e
end

--- Apunta un suceso (`self.eventos`, solo si existe: lo pone el arnés de
-- batalla/pruebas_dano para filmar rebotes, penetraciones y coberturas).
function Tropas:anotarEvento(tipo, x, y, z, u, datos)
    local lista = self.eventos
    if not lista then
        return
    end
    lista[#lista + 1] = {
        t = self.reloj,
        tipo = tipo,
        x = x,
        y = y,
        z = z,
        u = u,
        zona = datos and datos.zona,
        angulo = datos and datos.angulo,
        que = datos and datos.que,
        tirador = datos and datos.tirador,
        cara = datos and datos.cara,
    }
end

-- Disparos -----------------------------------------------------------------------------------

local golpeLinea = {}

--- ¿Tiene `u` la línea de fuego libre hasta `blanco`? No, si el primer
-- cuerpo que la cruza es de su bando (un compañero o un averiado suyo): no
-- se dispara por la espalda a los propios.
function Tropas:lineaDeFuegoLibre(u, blanco)
    local alto = 20
    local g = self.cuerpos:rayo(u.x, u.y, u.z + alto, blanco.x, blanco.y, blanco.z + 10, u, golpeLinea)
    if not g or not g.u or g.u == blanco then
        return true
    end
    return g.u.bando ~= u.bando
end

--- Dirección (ux, uy, uz) desviada `horizontal` rad a un lado y `vertical`
-- rad hacia arriba.
local function desviar(ux, uy, uz, horizontal, vertical)
    local lx, ly = -uy, ux
    local l = math.sqrt(lx * lx + ly * ly)
    if l < 1e-9 then
        lx, ly, l = 0, 1, 1
    end
    lx, ly = lx / l, ly / l
    -- Arriba respecto a la dirección: u × lado.
    local vx, vy, vz = -uz * ly, uz * lx, ux * ly - uy * lx
    local x = ux + lx * horizontal + vx * vertical
    local y = uy + ly * horizontal + vy * vertical
    local z = uz + vz * vertical
    local n = math.sqrt(x * x + y * y + z * z)
    return x / n, y / n, z / n
end

--- Altura (px) del punto al que se apunta en `blanco`: el centro del vehículo.
local function alturaBlanco(blanco)
    return blanco.tipo == 'tanque' and 12 or 15
end

--- Cañonazo del tanque `u` a su blanco (DANO-REAL.md §3.1): perforante,
-- con el error de tiro
-- de su control de tiro, la anticipación (desde la era 2) y la dispersión
-- del arma.
function Tropas:dispararTanque(u)
    local blanco = u.blanco
    local _, canon = Modelos3d.matricesTanque(u.casco, u.torreta, 0, u.modelo3d)
    local boca = u.modelo3d.boca
    local bx, by, bz = Matriz.aplicar(canon, boca[1], boca[2], boca[3])
    local datos = u.canonDatos
    local v0, k, dispersion, pen = datos.vBoca, datos.arrastre, datos.dispersion, datos.penBoca
    local g = Datos.gravedad
    local tx, ty, tz = blanco.x, blanco.y, blanco.z + alturaBlanco(blanco)
    local _, _, _, vuelo = Trayectoria.apuntar(bx, by, bz, tx, ty, tz, v0, k, g)
    if datos.anticipa and blanco.vx then
        tx, ty = tx + blanco.vx * vuelo, ty + blanco.vy * vuelo
    end
    -- La sobreelevación sale de la distancia que mide el control de tiro.
    local f = 1 + self.azar:randomNormal(datos.errorDistancia)
    local ux, uy, uz =
        Trayectoria.apuntar(bx, by, bz, bx + (tx - bx) * f, by + (ty - by) * f, bz + (tz - bz) * f, v0, k, g)
    -- Sin la anticipación ni la sobreelevación: la línea al blanco desde la boca.
    local sigma = math.sqrt(datos.error * datos.error + dispersion * dispersion)
    ux, uy, uz = desviar(ux, uy, uz, self.azar:randomNormal(sigma), self.azar:randomNormal(sigma))
    local b = {
        tray = Trayectoria.directa(bx, by, bz, ux, uy, uz, v0, k, g),
        alcance = 40000,
        clase = 'perforante',
        pen0 = pen,
        rebote = Datos.perforante.rebote,
        autor = u,
        bando = u.bando,
        canon = true, -- Impactos (Valeria): derriba el árbol que alcance
        escalaImpacto = 1.5,
    }
    -- La penetración varía de un disparo a otro.
    b.pen0 = b.pen0 * (1 + self.azar:randomNormal(Datos.perforante.variacion))
    self.proyectiles:lanzarDirecto(b)
    self:fogonazo(bx, by, bz, 14)
    self:sonar('canon', bx, by, bz, 0.9, 0.94 + self.azar:random() * 0.12)
    for _ = 1, 3 do
        self:humo(bx, by, bz, 16, 1.6, 0.8, 10)
    end
    if self.efectos then -- Efectos (Camila)
        self.efectos:disparo('canon', bx, by, bz, ux, uy, uz)
    end
    u.retroceso = 1
end

--- Posición de una bala en la fracción `t` de su vuelo.
function Tropas.posicionBala(b, t)
    if b.tray then
        return Trayectoria.posicionDirecta(b.tray, t * b.duracion)
    end
    -- Las balas hechas a mano de las pruebas: en línea recta (con su arco).
    local arco = b.arco or 0
    return b.x0 + (b.x1 - b.x0) * t, b.y0 + (b.y1 - b.y0) * t, b.z0 + (b.z1 - b.z0) * t + 4 * arco * t * (1 - t)
end

--- Bocas del contenedor de un lanzacohetes en el mundo, y su dirección.
function Tropas:bocaLanzacohetes(u, k)
    local contenedor = self:matrizContenedor(u)
    local bocas = u.lanzador.modelo.bocas
    local b = bocas[(k - 1) % #bocas + 1]
    local x, y, z = Matriz.aplicar(contenedor, b[1], b[2], b[3])
    return x, y, z, contenedor[1], contenedor[5], contenedor[9]
end

--- La misma rampa articulada que dibujan los dos renderizadores.
function Tropas:matrizContenedor(u)
    u.lanzador:actualizarMatrices(u)
    return u.matricesLanza.contenedor
end

--- Punto donde cae un proyectil apuntado a (x, y) con la dispersión de juego
-- `cep` px (F11b): reparto circular normal, la mitad cae a menos de `cep`.
function Tropas:caida(x, y, cep)
    local sigma = cep / math.sqrt(2 * math.log(2))
    local r = sigma * math.sqrt(-2 * math.log(1 - self.azar:random() * 0.999999))
    local a = self.azar:random() * math.pi * 2
    return x + math.cos(a) * r, y + math.sin(a) * r
end

--- Reparto de una salva de `u` (lo que lleva cargado en la rampa) en lo
-- que se dibuja: `maxVisualesSalva` misiles como mucho, cada uno con su
-- parte de los proyectiles (los primeros llevan uno más si no sale exacto).
-- Devuelve la lista de cuántos lleva cada uno. El Scud-B con la rampa
-- llena: { 1, 1, 1, 1 }, cuatro misiles de uno en uno.
function Tropas.repartoSalva(u)
    local proyectiles = u.carga and Tropas.misilesCargados(u) or u.proyectiles or 1
    if proyectiles <= 0 then
        return {}
    end
    local visuales = math.min(proyectiles, Tropas.maxVisualesSalva)
    local out = {}
    for k = 1, visuales do
        out[k] = math.floor(proyectiles / visuales) + (k <= proyectiles % visuales and 1 or 0)
    end
    return out
end

--- Lanza el `k`-ésimo misil de la salva de `u`, que lleva `cuantos`
-- proyectiles (1 si no se dice). Cada proyectil se paga (`porDisparo`),
-- tiene su punto de caída (`caida`) y vuela por su cuenta (DANO-REAL.md
-- §3.3): el primero se dibuja con su estela; los demás vuelan sin dibujarse.
-- Sin blanco o sin munición para ninguno, no sale (false).
function Tropas:lanzarMisil(u, k, cuantos)
    if not u.misilCargado or Blindaje.sinArma(u) then
        return false
    end
    local blanco = u.blanco
    if not blanco or blanco.muerto then
        blanco = self:blancoDeMisil(u)
        u.blanco = blanco
    end
    if not blanco then
        return false
    end
    -- La boca: en una rampa de varios misiles (el Scud-B), la de la ranura
    -- que sale (o la que diga `lanzador:bocaDeRanura(ranura)`, si el
    -- camión la define); con cohetes en tubos, repartidas por el haz a lo
    -- largo de la salva.
    local bocas = #u.lanzador.modelo.bocas
    local ranura = Tropas.enRampa(u) and Tropas.siguienteRanura(u)
    local boca
    if ranura and u.lanzador.bocaDeRanura then
        boca = u.lanzador:bocaDeRanura(ranura)
    elseif ranura then
        boca = math.floor((ranura - 1) * bocas / Tropas.cargaMaxima(u)) + 1
    else
        local visuales = math.max(1, #(u.salva or Tropas.repartoSalva(u)))
        boca = math.floor((k - 1) * bocas / visuales) + 1
    end
    local pagados = 0
    for _ = 1, cuantos or 1 do
        if not self:gastar(u) then
            break
        end
        pagados = pagados + 1
    end
    if pagados == 0 then
        return false
    end
    local x, y, z, dx, dy, dz = self:bocaLanzacohetes(u, boca)
    local cep = u.cep or 450
    local g = Datos.gravedad
    local ojiva = u.ojiva or Datos.ojiva(Tropas.modeloPorDefecto('lanzacohetes'), u.radio or 180)
    -- El eje de lado del proyectil: el del misil cargado o, si los cohetes
    -- van en los tubos, el del contenedor.
    local lado = u.lanzador.cargaVisible and u.matricesLanza.misilCarga or u.matricesLanza.contenedor
    local m
    for j = 1, pagados do
        local ix, iy = self:caida(blanco.x, blanco.y, cep)
        local iz = self.suelo:altura(ix, iy)
        local tray, vuelo = Trayectoria.indirecta(x, y, z, dx, dy, dz, ix, iy, iz, g)
        if j == 1 then
            m = {
                tray = tray,
                ojiva = ojiva,
                autor = u,
                bando = u.bando,
                x0 = x,
                y0 = y,
                z0 = z,
                salidaX = dx,
                salidaY = dy,
                salidaZ = dz,
                ladoX = lado[2],
                ladoY = lado[6],
                ladoZ = lado[10],
                radio = u.radio or 180,
                escala = u.escalaProyectil or 1,
                estela = self.estelas:nueva(),
            }
            self.proyectiles:lanzarIndirecto(m, vuelo, self.misiles, true)
        else
            local oculto = {
                tray = tray,
                ojiva = ojiva,
                autor = u,
                bando = u.bando,
                radio = u.radio or 180,
                escala = u.escalaProyectil or 1,
                oculto = true,
            }
            self.proyectiles:lanzarIndirecto(oculto, vuelo, self.proyectiles.ocultos)
        end
    end
    self:efectosLanzamiento(m, x, y, z, dx, dy, dz)
    return true
end

--- Lo que se ve y se oye al salir el misil `m` de (x, y, z) hacia (dx, dy,
-- dz): estela, efecto de lanzamiento, fogonazo, sonido y humo. Lo usan el
-- camión viejo (lanzarMisil) y el de robot conductor (lanzarMisilRobot).
function Tropas:efectosLanzamiento(m, x, y, z, dx, dy, dz)
    self.estelas:apuntar(m.estela, x, y, z, self.reloj)
    if self.efectos then -- Efectos (Camila)
        self.efectos:lanzamiento(m, x, y, z, dx, dy, dz)
    end
    local tam = math.sqrt(m.escala)
    self:fogonazo(x, y, z, 18 * tam)
    self:sonar('cohete', x, y, z, 0.72 * tam, (0.94 + self.azar:random() * 0.12) / tam)
    for _ = 1, 4 do
        self:humo(x - dx * 30, y - dy * 30, z, 30 * tam, 3, 0.85, 20)
    end
end

--- Un misil del camión de robot conductor (batalla/robots/especializaciones/
-- rampaMisiles.lua), el mismo que el del camión viejo: sale de (x, y, z) px
-- hacia (dx, dy, dz), con el eje de lado `lado` = { x, y, z }, y cae en
-- (ix, iy). `autor`: quien no se da a sí mismo. Devuelve el misil.
function Tropas:lanzarMisilRobot(autor, bando, x, y, z, dx, dy, dz, lado, ix, iy)
    local iz = self.suelo:altura(ix, iy)
    local tray, vuelo = Trayectoria.indirecta(x, y, z, dx, dy, dz, ix, iy, iz, Datos.gravedad)
    local m = {
        tray = tray,
        ojiva = Datos.ojiva(Tropas.modeloPorDefecto('lanzacohetes'), 180),
        autor = autor,
        bando = bando,
        x0 = x,
        y0 = y,
        z0 = z,
        salidaX = dx,
        salidaY = dy,
        salidaZ = dz,
        ladoX = lado[1],
        ladoY = lado[2],
        ladoZ = lado[3],
        radio = 180,
        escala = 1,
        estela = self.estelas:nueva(),
    }
    self.proyectiles:lanzarIndirecto(m, vuelo, self.misiles, true)
    self:efectosLanzamiento(m, x, y, z, dx, dy, dz)
    -- En la preparación la pelea no corre: sus efectos sí (Escena:actualizar).
    self.efectosSueltos = true
    return m
end

--- Lo que se ve cuando el cohete o misil `m` estalla en su punto (el daño lo
-- hace batalla/dano/explosiones.lua). El que se dibuja lleva el efecto de
-- impacto de misil de Camila; los ocultos, solo las partículas de la escena
-- (las explosiones de 3Dream de 40 cohetes por salva bajan de 121 a 109 FPS).
function Tropas:estallarMisil(m)
    local escala = math.max(0.35, m.escala or 1)
    if m.oculto then
        self:impacto(m.x1, m.y1, m.z1, true, true, 1.6 * escala, true)
        return
    end
    m.estela.siguiente = 0
    self.estelas:apuntar(m.estela, m.x1, m.y1, m.z1, self.reloj)
    m.estela.terminada = true
    self:impacto(m.x1, m.y1, m.z1, true, true, 2.4 * escala)
    if self.efectos then -- Efectos (Camila)
        self.efectos:impactoMisil(m, m.superficie or 'terreno')
    end
end

--- Posición de un misil en la fracción `t` (0 a 1) de su vuelo.
function Tropas.posicionMisil(m, t)
    return Trayectoria.posicionIndirecta(m.tray, t * m.duracion)
end

-- Índices de la parte de giro de una matriz 4x4 por filas.
local GIRO_MATRIZ = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

--- Tangente hacia delante, válida también en el instante exacto del disparo.
-- Con `m.escala`, el proyectil a esa escala.
function Tropas.matrizMisil(m, t, salida)
    local x, y, z = Tropas.posicionMisil(m, t)
    local dx, dy, dz = Trayectoria.velocidadIndirecta(m.tray, t * m.duracion)
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    if largo < 1e-6 then
        dx, dy, dz, largo = m.salidaX or 1, m.salidaY or 0, m.salidaZ or 0, 1
    end
    dx, dy, dz = dx / largo, dy / largo, dz / largo
    local matriz = Matriz.orientar(x - dx, y - dy, z - dz, x, y, z, 1, salida)
    if m.ladoX then
        -- Conserva el alabeo del misil cargado, incluso en un camión inclinado.
        local proyeccion = m.ladoX * matriz[1] + m.ladoY * matriz[5] + m.ladoZ * matriz[9]
        local sx = m.ladoX - proyeccion * matriz[1]
        local sy = m.ladoY - proyeccion * matriz[5]
        local sz = m.ladoZ - proyeccion * matriz[9]
        local l = math.sqrt(sx * sx + sy * sy + sz * sz)
        if l > 0.0001 then
            matriz[2] = sx / l
            matriz[6] = sy / l
            matriz[10] = sz / l
            matriz[3] = matriz[5] * matriz[10] - matriz[9] * matriz[6]
            matriz[7] = matriz[9] * matriz[2] - matriz[1] * matriz[10]
            matriz[11] = matriz[1] * matriz[6] - matriz[5] * matriz[2]
        end
    end
    local escala = m.escala
    if escala and escala ~= 1 then
        -- Un cohete es más pequeño que el misil del Scud-B.
        for _, i in ipairs(GIRO_MATRIZ) do
            matriz[i] = matriz[i] * escala
        end
    end
    return matriz
end

--- La matriz del misil (de `Tropas.matrizMisil`) para dibujar `mallaVara`
-- (caja de 1 centrada) como su cuerpo: de la cola hacia +x. Cambia `m`.
function Tropas.matrizVaraMisil(m)
    local largo, diametro = Tropas.misilVara.largo, Tropas.misilVara.diametro
    for fila = 0, 2 do
        local i = fila * 4
        m[i + 4] = m[i + 4] + m[i + 1] * largo / 2
        m[i + 1] = m[i + 1] * largo
        m[i + 2] = m[i + 2] * diametro
        m[i + 3] = m[i + 3] * diametro
    end
    return m
end

-- Daño real (Valeria, batalla/dano/) ------------------------------------------------------------

--- La bala `b` avanza hasta este paso (batalla/dano/proyectiles.lua).
-- Devuelve true si se acabó.
function Tropas:chocarBala(b)
    return self.proyectiles:pasoDirecto(b, self.reloj)
end

--- El cohete o misil `m` avanza hasta este paso. Devuelve true si estalló.
function Tropas:chocarMisil(m)
    return self.proyectiles:pasoIndirecto(m, self.reloj)
end

-- Actualización ------------------------------------------------------------------------------

local DESVIOS = { 0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4 }
-- Con una orden de mover se rodea más: también de lado y algo hacia atrás.
local DESVIOS_ORDEN = { 0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4, 1.75, -1.75, 2.1, -2.1 }

local function limitar(valor, minimo, maximo)
    return math.max(minimo, math.min(maximo, valor))
end

local function rumboEntre(ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local largo = math.sqrt(dx * dx + dy * dy)
    if largo < 0.001 then
        return nil
    end
    return dx / largo, dy / largo, largo
end

--- ¿Sigue avanzando el tanque `u`? El atacante, hasta tener un tanque
-- enemigo cerca; el defensor sale un poco al encuentro y espera. Nadie se
-- adelanta mucho a los suyos (la formación se mantiene).
function Tropas:quiereAvanzar(u)
    if u.orden then
        -- Con una orden manda ella (ver `seguirOrden`).
        return u.orden.avanza == true
    end
    if u.avanzado > self.avance[u.bando] + 350 then
        return false
    end
    local cerca = u.tanqueCerca or math.huge
    if u.bando == 1 then
        return cerca > Tropas.parada
    end
    return u.avanzado < Tropas.avanceDefensor and cerca > Tropas.parada + 2000
end

-- Órdenes del jugador (batalla/control.lua) ----------------------------------------------------
--
-- `u.orden`, o nil (la unidad sigue su IA):
--   { tipo = 'mover', ruta = { { x, y }, ... }, paso }  va por la ruta (sin
--       pararse a disparar) y al llegar al último punto se queda en él;
--   { tipo = 'atacar', blanco }  se acerca por terreno transitable (`rutas`,
--       batalla/ordenes.lua) hasta tenerlo a tiro (y a la vista, salvo el
--       lanzacohetes) y solo le dispara a él; si cae, se queda;
--   { tipo = 'mantener' }  no se mueve y dispara a lo que tenga a su alcance.

Tropas.llegar = { tanque = 90, lanzacohetes = 260 } -- px al último punto (el camión gira ancho)
Tropas.llegarPaso = 350 -- px a un punto intermedio de la ruta
-- En una ruta suave (puntos cada 4 m, batalla/ordenes.lua `suavizar`), el
-- punto al que apunta va solo así de por delante: sigue la curva sin
-- recortarla (con 350 px recortaría las curvas 35 m, por los árboles). El
-- camión gira ancho: mira más lejos.
Tropas.llegarPasoSuave = { tanque = 110, lanzacohetes = 350 }
Tropas.atasco = 16 -- s sin desplazarse 60 px: pasa al siguiente punto
Tropas.casiLlega = 500 -- px: atascado a esta distancia del último punto, cuenta como llegado
-- Salir de un atasco (s sin desplazarse 60 px), por orden: pedir paso al
-- compañero parado de delante (se aparta `Tropas.apartarse` px), rehacer la
-- ruta A* desde donde está, recular un momento y rodear por un punto libre a
-- un lado. Si nada sirve, a los `Tropas.atasco` s se rinde como antes.
Tropas.llegarAtascado = 220 -- px: parado tan cerca de su último punto, ha llegado
Tropas.atascoPaso = 2
Tropas.atascoRuta = 4
Tropas.atascoRecula = 6.5
Tropas.atascoRodea = 9
Tropas.recular = 1.8 -- s marcha atrás
Tropas.apartarse = 200 -- px que se aparta quien cede el paso
Tropas.apartarseTiempo = 6 -- s como mucho para apartarse

--- Da a `u` la orden `orden` (nil: vuelve a su IA).
function Tropas:darOrden(u, orden)
    u.orden = orden
    u.rumboOrden = nil
    u.puntoOrden = nil
    u.recular = nil
    u.maniobra = nil
    u.ruta = 0
    u.blanco = nil
    if orden then
        orden.paso = orden.paso or 1
        orden.desde = self.reloj
        orden.avanza = false
    end
end

--- Alcance (y distancia mínima) de las armas de `u`: las de su modelo.
function Tropas.alcanceDe(u)
    if u.tipo == 'lanzacohetes' then
        return u.alcance or Tropas.alcanceMisil, u.minimo or Tropas.minimoMisil
    end
    return u.alcance or Tropas.alcanceTanque, 0
end

--- Cumple la orden de `u` este cuadro: fija `orden.avanza` y, si hay que
-- moverse, `u.rumboOrden`. Con 'atacar' devuelve su blanco si está a tiro.
function Tropas:seguirOrden(u)
    local o = u.orden
    o.avanza = false
    if o.tipo == 'mover' and Blindaje.inmovil(u) then
        -- Oruga o motor rotos: se queda donde está y pelea desde ahí.
        self:darOrden(u, { tipo = 'mantener', inmovil = true })
        return nil
    end
    if o.tipo == 'mover' then
        local p = o.ruta[o.paso]
        while p do
            local ultimo = o.paso == #o.ruta
            local radio = ultimo and Tropas.llegar[u.tipo]
                or (o.suave and Tropas.llegarPasoSuave[u.tipo] or Tropas.llegarPaso)
            if (p.x - u.x) ^ 2 + (p.y - u.y) ^ 2 > radio * radio then
                break
            end
            o.paso = o.paso + 1
            o.marcaX, o.desde = nil, self.reloj
            u.ruta = 0
            p = o.ruta[o.paso]
        end
        if p and o.paso == #o.ruta then
            -- Si ya pasó cerca del último punto y se aleja (da vueltas sin
            -- poder entrar), ha llegado.
            local d = math.sqrt((p.x - u.x) ^ 2 + (p.y - u.y) ^ 2)
            o.minimo = math.min(o.minimo or math.huge, d)
            if o.minimo < 300 and d > o.minimo + 120 then
                self:darOrden(u, { tipo = 'mantener', llego = true })
                return nil
            end
        end
        if p then
            local d = math.sqrt((p.x - u.x) ^ 2 + (p.y - u.y) ^ 2)
            -- Atasco: `atasco` s sin desplazarse (un camión que da la vuelta
            -- se aleja un rato de su punto, pero se mueve).
            local quieto = self:desatascar(u, o, p)
            if quieto > Tropas.atascoPaso and o.paso == #o.ruta and d < Tropas.llegarAtascado then
                -- Parado junto a su hueco (otro vehículo lo roza): ha llegado.
                self:darOrden(u, { tipo = 'mantener', llego = true })
                return nil
            end
            p = o.ruta[o.paso]
            if quieto > Tropas.atasco then
                -- Atascado: al siguiente punto (o, si era el último, se queda;
                -- si su hueco está ocupado y ya está cerca, ha llegado).
                if o.paso == #o.ruta then
                    self:darOrden(u, { tipo = 'mantener', llego = d < Tropas.casiLlega, atascado = true })
                    return nil
                end
                o.paso = o.paso + 1
                o.marcaX, o.desde = nil, self.reloj
                u.ruta = 0
                p = o.ruta[o.paso]
            end
        end
        if not p then
            self:darOrden(u, { tipo = 'mantener', llego = true })
            return nil
        end
        o.avanza = true
        u.rumboOrden = math.atan2(p.y - u.y, p.x - u.x)
        u.puntoOrden = p
        return nil
    elseif o.tipo == 'atacar' then
        local b = o.blanco
        if not b or b.muerto or b.retirado then
            self:darOrden(u, { tipo = 'mantener' })
            return nil
        end
        local d = math.sqrt(distancia2(u, b))
        local alcance, minimo = Tropas.alcanceDe(u)
        -- La línea de vista cuesta: se mira cada medio segundo.
        if u.tipo == 'lanzacohetes' then
            o.visible = true
        elseif not o.vistoEn or self.reloj - o.vistoEn > 0.5 then
            o.visible = self:lineaVisible(u, b)
            o.vistoEn = self.reloj
        end
        local aTiro = d <= alcance * 0.85 and d >= minimo and o.visible
        if not aTiro and d > minimo and not Blindaje.inmovil(u) then
            -- Se acerca por terreno transitable (la ruta se rehace cada 10 s,
            -- el blanco se mueve) hasta tenerlo a tiro y a la vista.
            o.avanza = true
            if self.rutas and (not o.ruta or self.reloj - o.rutaEn > 10) then
                o.ruta = self.rutas:ruta(u.x, u.y, b.x, b.y)
                o.paso, o.rutaEn = 2, self.reloj
            end
            local p = o.ruta and o.ruta[o.paso]
            while p and o.paso < #o.ruta and (p.x - u.x) ^ 2 + (p.y - u.y) ^ 2 < Tropas.llegarPaso ^ 2 do
                o.paso = o.paso + 1
                p = o.ruta[o.paso]
            end
            if not p or o.paso >= #o.ruta then
                p = b
            end
            -- También sale de atascos camino de su blanco.
            if o.ruta then
                self:desatascar(u, o, p)
                p = (o.paso < #o.ruta and o.ruta[o.paso]) or p
            end
            u.rumboOrden = math.atan2(p.y - u.y, p.x - u.x)
            u.puntoOrden = p
        end
        return aTiro and b or nil
    end
    return nil
end

--- Lleva la cuenta del atasco de la orden `o` de `u` (sin desplazarse 60
-- px) camino de `p` y prueba, por turnos, a pedir paso, rehacer la ruta,
-- recular y rodear. Devuelve los segundos que lleva sin desplazarse.
function Tropas:desatascar(u, o, p)
    if not o.marcaX or (u.x - o.marcaX) ^ 2 + (u.y - o.marcaY) ^ 2 > 60 * 60 then
        o.marcaX, o.marcaY, o.desde = u.x, u.y, self.reloj
        o.pidioPaso, o.rehecha, o.reculo, o.rodeo = nil, nil, nil, nil
        return 0
    end
    local quieto = self.reloj - o.desde
    if quieto > Tropas.atascoPaso and not o.pidioPaso then
        o.pidioPaso = true
        self:pedirPaso(u, p)
    elseif quieto > Tropas.atascoRuta and not o.rehecha then
        o.rehecha = true
        if o.tipo == 'mover' then
            self:rehacerRuta(u, o)
        else
            o.rutaEn = -math.huge -- 'atacar' la rehace al momento
        end
    elseif quieto > Tropas.atascoRecula and not o.reculo then
        o.reculo = true
        if self:libreDetras(u) then
            u.recular = self.reloj + Tropas.recular
        end
    elseif quieto > Tropas.atascoRodea and not o.rodeo then
        o.rodeo = true
        self:rodear(u, o, p)
    end
    return quieto
end

--- Pide paso: el compañero (del mismo bando) que está parado delante de `u`,
-- camino de `p`, se aparta `Tropas.apartarse` px hacia el lado que deja libre
-- el camino (`u.apartarse`, lo cumple su actualización).
function Tropas:pedirPaso(u, p)
    local rx, ry = p.x - u.x, p.y - u.y
    local largo = math.sqrt(rx * rx + ry * ry)
    if largo < 1 then
        return nil
    end
    rx, ry = rx / largo, ry / largo
    local alcance = math.min(largo, 320)
    local pedido
    for _, o in ipairs(self.unidades) do
        if
            o ~= u
            and o.bando == u.bando
            and not o.muerto
            and not o.retirado
            and not (o.orden and (o.orden.avanza or o.orden.tipo == 'atacar'))
            and not o.apartarse
            and not (o.tipo == 'lanzacohetes' and o.elevacion > 0)
        then
            local dx, dy = o.x - u.x, o.y - u.y
            local delante = dx * rx + dy * ry
            local lado = dx * ry - dy * rx
            if delante > -40 and delante < alcance and math.abs(lado) < 170 then
                -- Hacia el lado en que ya está (o el izquierdo), y si no se
                -- puede, al otro.
                local signo = lado >= 0 and 1 or -1
                for _, s in ipairs({ signo, -signo }) do
                    local ax = o.x + ry * s * Tropas.apartarse
                    local ay = o.y - rx * s * Tropas.apartarse
                    if self:libre(ax, ay, true, o.tipo) then
                        o.apartarse = { x = ax, y = ay, hasta = self.reloj + Tropas.apartarseTiempo }
                        o.ruta = 0
                        pedido = o
                        break
                    end
                end
            end
        end
    end
    return pedido
end

--- Rehace la ruta de la orden de mover de `u` desde donde está hasta su
-- destino (A* por terreno transitable, batalla/ordenes.lua). Devuelve el
-- punto al que va ahora.
function Tropas:rehacerRuta(u, o)
    local destino = o.destino or o.ruta[#o.ruta]
    if not (self.rutas and destino) then
        return nil
    end
    local ruta = self.rutas:ruta(u.x, u.y, destino.x, destino.y)
    if not ruta or #ruta < 2 then
        return nil
    end
    local puntos = {}
    for k = 2, #ruta - 1 do
        puntos[#puntos + 1] = ruta[k]
    end
    puntos[#puntos + 1] = { x = destino.x, y = destino.y }
    if o.suave and self.rutas.suavizar then
        table.insert(puntos, 1, { x = u.x, y = u.y })
        puntos = self.rutas:suavizar(puntos)
        table.remove(puntos, 1)
    end
    o.ruta, o.paso, o.minimo = puntos, 1, nil
    u.ruta = 0
    return puntos[1]
end

--- ¿Hay sitio para recular un poco? Solo cuenta el terreno (agua, pendiente,
-- borde del campo) y otros vehículos: si detrás hay un árbol, la física lo
-- para y no pasa nada.
function Tropas:libreDetras(u)
    local bx, by = u.x - math.cos(u.rumbo) * 120, u.y - math.sin(u.rumbo) * 120
    local s = self.suelo
    if s.limite and not s.limite:dentro(bx, by, 60) then
        return false
    end
    if s.agua and s.agua:enAgua(bx, by, 60) then
        return false
    end
    return self:transitable(bx, by, u.tipo) and not self:vehiculoCerca(bx, by, 80, u)
end

--- Rodea: mete en la ruta un punto libre a un lado (de 250 a 450 px), el que
-- deja más cerca de `p` y se alcanza en línea recta. Devuelve el punto.
function Tropas:rodear(u, o, p)
    local base = math.atan2(p.y - u.y, p.x - u.x)
    local mejor, mejorD
    for _, distancia in ipairs({ 260, 380, 480 }) do
        for _, giro in ipairs({ 0.8, -0.8, 1.4, -1.4, 2.0, -2.0, 2.6, -2.6 }) do
            local a = base + giro
            local x, y = u.x + math.cos(a) * distancia, u.y + math.sin(a) * distancia
            -- Desde un poco más allá de donde está: atascado, su sitio puede
            -- tocar un árbol o una piedra.
            local sx, sy = u.x + math.cos(a) * 60, u.y + math.sin(a) * 60
            if self:segmentoLibre(sx, sy, x, y, u.tipo) and not self:vehiculoCerca(x, y, 120, u, u.bando) then
                local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
                if not mejorD or d < mejorD then
                    mejor, mejorD = { x = x, y = y }, d
                end
            end
        end
        if mejor then
            break
        end
    end
    if mejor and o.ruta then
        table.insert(o.ruta, math.min(o.paso, #o.ruta + 1), mejor)
        o.minimo = nil
        u.ruta = 0
    end
    return mejor
end

--- ¿Lleva `u` gatos que apoyar antes de subir la rampa (el camión de 4 misiles)?
local function conGatos(u)
    local articulacion = u.lanzador.articulacion
    return articulacion ~= nil and #articulacion.gatos > 0
end

--- Recoge los gatos de `u` un paso; true mientras sigan bajados.
local function recogerGatos(u, dt)
    if (u.gatos or 0) <= 0 then
        return false
    end
    u.gatos = math.max(0, u.gatos - dt / Tropas.tiempoGatos)
    return true
end

--- Cumple `u.apartarse` (ceder el paso): va a su punto y lo olvida al llegar
-- o al acabarse el tiempo. Devuelve true mientras se aparta.
function Tropas:cumplirApartarse(u, dt)
    local a = u.apartarse
    if not a then
        return false
    end
    if self.reloj > a.hasta or (a.x - u.x) ^ 2 + (a.y - u.y) ^ 2 < 60 * 60 or Blindaje.inmovil(u) then
        u.apartarse = nil
        u.ruta = 0
        return false
    end
    if u.tipo == 'lanzacohetes' and u.elevacion > 0 then
        local maxima = u.lanzador.modelo.elevacion or 35
        u.elevacion = math.max(0, u.elevacion - maxima * dt / 2.5)
        return true
    end
    if u.tipo == 'lanzacohetes' and recogerGatos(u, dt) then
        return true
    end
    self:mover(u, dt)
    return true
end

function Tropas:pasilloMasCercano(u)
    local pasillos = self.suelo.pasillos or {}
    if #pasillos == 0 then
        return nil
    end
    -- Los puntos van del frente atacante al defensor. La tangente puede
    -- mirar atrás al rodear una ensenada sin invertir el destino del bando.
    local direccion = u.bando == 2 and -1 or 1
    local maximo = Tropas.pasilloBusqueda * Tropas.pasilloBusqueda
    local mejor
    for indicePasillo, pasillo in ipairs(pasillos) do
        local n = #pasillo.x
        for indice = 1, pasillo.ramal and 0 or n, Tropas.pasilloSaltoBusqueda do
            local x = pasillo.x[indice]
            local y = pasillo.y[indice]
            local dx = x - u.x
            local dy = y - u.y
            local d2 = dx * dx + dy * dy
            if d2 < maximo and (not mejor or d2 < mejor.d2) then
                local a = math.max(1, indice - 1)
                local b = math.min(n, indice + 1)
                local tx, ty = rumboEntre(pasillo.x[a], pasillo.y[a], pasillo.x[b], pasillo.y[b])
                if tx then
                    local nx = -ty
                    local ny = tx
                    local lateral = (u.x - x) * nx + (u.y - y) * ny
                    mejor = {
                        pasillo = pasillo,
                        indicePasillo = indicePasillo,
                        indice = indice,
                        d2 = d2,
                        direccion = direccion,
                        nx = nx,
                        ny = ny,
                        lateral = lateral,
                    }
                end
            end
        end
    end
    return mejor
end

function Tropas:indicePasilloAdelantado(pasillo, indice, direccion, distancia)
    local restante = distancia
    local actual = indice
    while restante > 0 do
        local siguiente = actual + direccion
        if siguiente < 1 or siguiente > #pasillo.x then
            break
        end
        local dx = pasillo.x[siguiente] - pasillo.x[actual]
        local dy = pasillo.y[siguiente] - pasillo.y[actual]
        restante = restante - math.sqrt(dx * dx + dy * dy)
        actual = siguiente
    end
    return actual
end

function Tropas:rumboDePasillo(u)
    local cercano = self:pasilloMasCercano(u)
    if not cercano then
        u.pasillo = nil
        return nil
    end
    u.pasillo = cercano.indicePasillo
    local distancia = math.sqrt(cercano.d2)
    local mirar = distancia > Tropas.pasilloUnion and 80 or Tropas.pasilloAdelante
    local pasillo = cercano.pasillo
    local indice = self:indicePasilloAdelantado(pasillo, cercano.indice, cercano.direccion, mirar)
    local lateral = limitar(cercano.lateral, -Tropas.pasilloSeparacion, Tropas.pasilloSeparacion)
    while true do
        local a = math.max(1, indice - 1)
        local b = math.min(#pasillo.x, indice + 1)
        local tx, ty = rumboEntre(pasillo.x[a], pasillo.y[a], pasillo.x[b], pasillo.y[b])
        for intento = 1, 2 do
            local desplazamiento = intento == 1 and lateral or 0
            local objetivoX = pasillo.x[indice] - (ty or 0) * desplazamiento
            local objetivoY = pasillo.y[indice] + (tx or 0) * desplazamiento
            local dx, dy = objetivoX - u.x, objetivoY - u.y
            if dx * dx + dy * dy >= 35 * 35 and self:segmentoLibre(u.x, u.y, objetivoX, objetivoY, u.tipo) then
                return math.atan2(dy, dx)
            end
        end
        if indice == cercano.indice then
            break
        end
        -- Acorta la anticipación hasta que toda la recta quepa en tierra.
        indice = indice - cercano.direccion
    end
    return nil
end

--- Rumbo libre para avanzar: el del bando o el desvío más pequeño que no
-- lleve al agua, a un edificio, a un árbol o encima de otro vehículo.
function Tropas:rumboLibre(u)
    local a = u.apartarse
    local base = (a and math.atan2(a.y - u.y, a.x - u.x))
        or (u.orden and u.orden.avanza and u.rumboOrden)
        or self:rumboDePasillo(u)
        or u.rumboBando
    local prueba = 125
    local radio = 105
    local conOrden = a or (u.orden and u.orden.avanza)
    local enMarcha = conOrden and u.bando or nil
    for _, desvio in ipairs(conOrden and DESVIOS_ORDEN or DESVIOS) do
        local r = base + desvio
        local mx, my = u.x + math.cos(r) * prueba, u.y + math.sin(r) * prueba
        if self:libre(mx, my, true, u.tipo) and not self:vehiculoCerca(mx, my, radio, u, enMarcha) then
            return r
        end
    end
    return nil
end

--- Aplica el límite del campo sin aceptar que el ajuste empuje la unidad a
-- agua o pendiente no transitable. Si pasa, vuelve al punto previo del paso.
function Tropas:mantenerTransitable(u, anteriorX, anteriorY)
    local s = self.suelo
    if s.limite then
        u.x, u.y = s.limite:ajustar(u.x, u.y, 60) -- Límite (Valeria)
    end
    if not self:transitable(u.x, u.y, u.tipo) then
        u.x = anteriorX
        u.y = anteriorY
        u.ruta = 0
        return false
    end
    return true
end

--- La unidad `u` avanza `dt` segundos. Devuelve si se ha movido. Un paso
-- de una unidad con munición cuenta como que su bando aún busca al rival.
function Tropas:mover(u, dt)
    local movido = self:moverPaso(u, dt)
    if movido and not Tropas.sinMunicion(u) then
        self.ultimoAvance[u.bando] = self.reloj
    end
    return movido
end

--- Marcha atrás a `rapidez` px/s. Los tanques, en línea recta; el camión,
-- con las ruedas giradas al revés de `diferencia` (el morro gira hacia ella).
function Tropas:marchaAtras(u, rapidez, diferencia, dt)
    if u.tipo == 'lanzacohetes' then
        local maxima = Lanzamisiles.direccionMaxima
        local objetivo = diferencia > 0 and -maxima or maxima
        u.lanzador:dirigir(u, u.rumbo + objetivo / 0.85, dt)
        if self.fisica then
            return self.fisica:conducir(u, -rapidez, u.direccionRuedas, u.lanzador.entreEjes)
        end
    elseif self.fisica then
        return self.fisica:impulsar(u, u.rumbo, -rapidez)
    end
    local anteriorX, anteriorY = u.x, u.y
    u.x = u.x - math.cos(u.rumbo) * rapidez * dt
    u.y = u.y - math.sin(u.rumbo) * rapidez * dt
    local movido = self:mantenerTransitable(u, anteriorX, anteriorY)
    u.z = self.suelo:altura(u.x, u.y)
    Modelos3d.postura(self.suelo, u.x, u.y, u.z, u.rumbo, u.casco)
    return movido
end

function Tropas:moverPaso(u, dt)
    -- Oruga, rueda o motor rotos: no se mueve (DANO-REAL.md §5.4).
    if Blindaje.inmovil(u) then
        return false
    end
    -- Con una orden del jugador, los vehículos van a su marcha, no al paso
    -- lento de la formación.
    local conOrden = (u.orden and u.orden.avanza) or u.apartarse
    local rapidez = conOrden and Tropas.velocidadOrden or Tropas.velocidad
    -- Cada modelo, a su velocidad (F4: el de referencia, 1).
    rapidez = rapidez * (u.velocidadModelo or 1)
    if u.tipo == 'lanzacohetes' and u.elevacion > 0 then
        return false
    end
    -- Atascado: recula un momento en línea recta (Tropas:seguirOrden).
    if u.recular then
        if self.reloj < u.recular and self:libreDetras(u) then
            return self:marchaAtras(u, rapidez * 0.6, 0, dt)
        end
        u.recular = nil
    end
    u.ruta = (u.ruta or 0) - dt
    if u.ruta <= 0 then
        u.ruta = 0.4 + self.azar:random() * 0.2
        u.rumboDeseado = self:rumboLibre(u)
    end
    if not u.rumboDeseado then
        return false
    end
    local s = self.suelo
    -- Con una orden, se mira el mismo punto que miró `rumboLibre` al elegir
    -- el rumbo (si no, puede elegir uno que aquí se rechaza y no moverse).
    local prueba = 110
    if conOrden then
        prueba = 125
    end
    local pruebaX = u.x + math.cos(u.rumboDeseado) * prueba
    local pruebaY = u.y + math.sin(u.rumboDeseado) * prueba
    if not self:libre(pruebaX, pruebaY, true, u.tipo) then
        u.ruta = 0
        return false
    end
    if u.tipo == 'lanzacohetes' then
        -- El camión no gira en el sitio: si su punto queda dentro de su
        -- círculo de giro y muy de lado, da marcha atrás con las ruedas al
        -- revés hasta encararlo (si no, daba vueltas alrededor sin llegar).
        local diferencia = (u.rumboDeseado - u.rumbo + math.pi) % (math.pi * 2) - math.pi
        local p = conOrden and (u.apartarse or u.puntoOrden)
        if p then
            local radioGiro = u.lanzador.entreEjes / math.tan(Lanzamisiles.direccionMaxima)
            local d = math.sqrt((p.x - u.x) ^ 2 + (p.y - u.y) ^ 2)
            if u.maniobra and (self.reloj > u.maniobra or math.abs(diferencia) < 0.45) then
                u.maniobra = nil
            elseif not u.maniobra and math.abs(diferencia) > 1.1 and d < radioGiro * 2.2 and self:libreDetras(u) then
                u.maniobra = self.reloj + 5
            end
            if u.maniobra then
                if not self:libreDetras(u) then
                    u.maniobra = nil
                else
                    return self:marchaAtras(u, rapidez * 0.7, diferencia, dt)
                end
            end
        end
        u.lanzador:dirigir(u, u.rumboDeseado, dt)
        if self.fisica then
            return self.fisica:conducir(u, rapidez, u.direccionRuedas, u.lanzador.entreEjes)
        end

        local velocidad = rapidez * dt * math.max(0.45, math.cos(u.direccionRuedas))
        local giro = velocidad / u.lanzador.entreEjes * math.tan(u.direccionRuedas)
        local anteriorX = u.x
        local anteriorY = u.y
        u.rumbo = u.rumbo + giro
        local dx = math.cos(u.rumbo) * velocidad
        local dy = math.sin(u.rumbo) * velocidad
        u.x = u.x + dx
        u.y = u.y + dy
        local movido = self:mantenerTransitable(u, anteriorX, anteriorY)
        dx = u.x - anteriorX
        dy = u.y - anteriorY
        u.avanzado = u.avanzado + dx * math.cos(u.rumboBando) + dy * math.sin(u.rumboBando)
        u.z = s:altura(u.x, u.y)
        Modelos3d.postura(s, u.x, u.y, u.z, u.rumbo, u.casco)
        return movido and (dx * dx + dy * dy > 0)
    end
    if self.fisica then
        return self.fisica:impulsar(u, u.rumboDeseado, rapidez)
    end

    local diferencia = (u.rumboDeseado - u.rumbo + math.pi) % (math.pi * 2) - math.pi
    local giro = Tropas.giroCasco * dt
    u.rumbo = u.rumbo + math.max(-giro, math.min(giro, diferencia))
    local factorAvance = math.max(0.35, math.cos(diferencia))
    local velocidad = rapidez * dt * factorAvance
    local dx = math.cos(u.rumbo) * velocidad
    local dy = math.sin(u.rumbo) * velocidad
    local anteriorX = u.x
    local anteriorY = u.y
    u.x = u.x + dx
    u.y = u.y + dy
    local movido = self:mantenerTransitable(u, anteriorX, anteriorY)
    dx = u.x - anteriorX
    dy = u.y - anteriorY
    u.avanzado = u.avanzado + dx * math.cos(u.rumboBando) + dy * math.sin(u.rumboBando)
    u.z = s:altura(u.x, u.y)
    Modelos3d.postura(s, u.x, u.y, u.z, u.rumbo, u.casco)
    return movido and (dx * dx + dy * dy > 0)
end

function Tropas:actualizarTanque(u, dt)
    u.retroceso = math.max(0, u.retroceso - dt * 2.5)
    u.espera = u.espera - dt
    u.buscar = u.buscar - dt
    if self:cumplirApartarse(u, dt) then
        u.quieto = 0
        return
    end
    local orden = u.orden
    local forzado = orden and self:seguirOrden(u)
    if Tropas.sinMunicion(u) or Blindaje.sinArma(u) then
        -- Sin obuses (o con el cañón roto): no dispara ni avanza (salvo que
        -- se le mande); aguanta.
        u.blanco = nil
        if orden and orden.avanza and self:mover(u, dt) then
            u.quieto = 0
        else
            u.quieto = u.quieto + dt
        end
        return
    end
    if orden and orden.tipo == 'atacar' then
        u.blanco = forzado
    elseif u.buscar <= 0 or (u.blanco and u.blanco.muerto) then
        u.blanco = self:blancoDeTanque(u)
        u.buscar = 1.5 + self.azar:random()
    end
    local apuntado = false
    if u.blanco then
        local deseado = math.atan2(u.blanco.y - u.y, u.blanco.x - u.x) - u.rumbo
        local diferencia = (deseado - u.torreta + math.pi) % (math.pi * 2) - math.pi
        local paso = Tropas.giroTorreta * dt
        if u.averias.torreta then
            -- Torreta atascada: apunta girando el casco (si puede moverse) y
            -- solo dispara a lo que tiene delante.
            apuntado = math.abs(diferencia) <= Datos.averias.giroLibre
            if not apuntado and self.fisica and not Blindaje.inmovil(u) then
                self.fisica:impulsar(u, u.rumbo + diferencia, 0)
                u.alto = math.max(u.alto, 0.5)
            end
        elseif math.abs(diferencia) <= paso then
            u.torreta = u.torreta + diferencia
            apuntado = true
        else
            u.torreta = u.torreta + (diferencia > 0 and paso or -paso)
        end
    end
    -- Con una orden de mover, marcha sin pararse a disparar.
    if apuntado and u.espera <= 0 and not (orden and orden.tipo == 'mover') then
        -- Para, se asienta y dispara.
        if u.quieto >= 0.7 and not self:lineaDeFuegoLibre(u, u.blanco) then
            -- Un compañero delante: no le dispara por la espalda; espera
            -- (y sigue su marcha, que puede dejarle la línea libre).
            u.espera = 1
        elseif u.quieto >= 0.7 then
            if self:gastar(u) then
                self:dispararTanque(u)
            end
            -- Con bajas en la tripulación, recarga más despacio.
            u.espera = entre(self.azar, Tropas.recarga) / math.max(0.25, Blindaje.tripulacionQueda(u))
        else
            u.alto = math.max(u.alto, Tropas.alto)
        end
    end
    u.alto = u.alto - dt
    if u.alto <= 0 and self:quiereAvanzar(u) and self:mover(u, dt) then
        u.quieto = 0
    else
        u.quieto = u.quieto + dt
    end
end

--- Despliega el camión, frena, levanta su misil, dispara y baja la rampa
-- vacía. Las ruedas se miden después de integrar la física, sin animación
-- de marcha cuando el vehículo está bloqueado o detenido.
function Tropas:actualizarLanzacohetes(u, dt)
    local maxima = u.lanzador.modelo.elevacion or 35
    u.espera = u.espera - dt
    u.buscar = u.buscar - dt
    if self:cumplirApartarse(u, dt) then
        return
    end
    local orden = u.orden
    local forzado = orden and self:seguirOrden(u)
    if orden and orden.avanza then
        -- A su puesto: primero baja la rampa (sin disparar), recoge los gatos
        -- y luego conduce.
        if u.elevacion > 0 then
            u.elevacion = math.max(0, u.elevacion - maxima * dt / 2.5)
            return
        end
        if recogerGatos(u, dt) then
            return
        end
        u.fase = 'orden'
        self:mover(u, dt)
        return
    end
    if u.fase == 'orden' or (orden and u.fase == 'despliegue') then
        -- Llegó (o se le manda quedarse): frena y se prepara para disparar.
        u.fase = 'frenando'
        u.quieto = 0
    end
    if u.fase == 'despliegue' then
        u.tiempoDespliegue = u.tiempoDespliegue + dt
        if u.avanzado < 120 and u.tiempoDespliegue < 10 and self:mover(u, dt) then
            return
        end
        u.fase = 'frenando'
        u.quieto = 0
    end
    if u.fase == 'frenando' then
        u.quieto = u.velocidadRuedas < 1 and u.quieto + dt or 0
        if u.quieto >= 0.6 then
            u.fase = 'espera'
            u.espera = math.max(0.3, u.espera)
        end
        return
    end
    if u.buscar <= 0 then
        u.buscar = 1
        u.expuesto = self:tanqueEnemigoCerca(u) < (u.minimo or Tropas.minimoMisil)
    end
    local preparando = u.fase == 'apoyando' or u.fase == 'subiendo' or u.fase == 'fuego'
    if (u.expuesto or u.velocidadRuedas > 1) and preparando then
        u.fase = 'bajando'
        u.espera = math.max(u.espera, 3)
    end
    if u.fase == 'espera' then
        u.elevacion = math.max(0, u.elevacion - maxima * dt / 2)
        if u.elevacion == 0 then
            recogerGatos(u, dt)
        end
        -- Con huecos en la rampa y munición libre en su fuente, primero recarga.
        if Tropas.misilesCargados(u) <= 0 and Tropas.puedeCargar(u) > 0 then
            u.fase = 'bajando'
            u.espera = math.max(u.espera, self:tiempoRecarga(u))
            return
        end
        -- Sin misiles no sube la rampa: se queda donde está.
        local armado = not Tropas.sinMunicion(u) and not Blindaje.sinArma(u)
        if u.espera <= 0 and not u.expuesto and u.velocidadRuedas < 1 and armado then
            if orden and orden.tipo == 'atacar' then
                u.blanco = forzado
            else
                u.blanco = self:blancoDeMisil(u)
            end
            if u.blanco then
                -- El de 4 misiles se apoya antes en sus gatos.
                u.fase = conGatos(u) and 'apoyando' or 'subiendo'
            else
                u.espera = 3
            end
        end
    elseif u.fase == 'apoyando' then
        u.gatos = math.min(1, (u.gatos or 0) + dt / Tropas.tiempoGatos)
        if u.gatos >= 1 then
            u.fase = 'subiendo'
        end
    elseif u.fase == 'subiendo' then
        u.elevacion = math.min(maxima, u.elevacion + maxima * dt / 3)
        if u.elevacion >= maxima then
            u.fase = 'fuego'
            u.espera = 0.5
            u.salva = Tropas.repartoSalva(u)
            u.salvaSiguiente = 1
        end
    elseif u.fase == 'fuego' and u.espera <= 0 then
        -- La salva: cada misil que se dibuja, con su parte de los proyectiles,
        -- a la cadencia de su modelo. Sin blanco o sin munición, se acaba.
        local k = u.salvaSiguiente or 1
        local cuantos = u.salva and u.salva[k] or 1
        local salio = self:lanzarMisil(u, k, cuantos)
        u.salvaSiguiente = k + 1
        if salio and u.salva and u.salvaSiguiente <= #u.salva then
            -- Misiles de una rampa (el Scud-B), de uno en uno; cohetes en
            -- tubos, a la cadencia de la salva.
            if Tropas.enRampa(u) then
                u.espera = Tropas.entreMisilesRampa
            else
                u.espera = Tropas.cadenciaCohete * cuantos
            end
        else
            -- Lo que no salió (sin blanco) se queda en la rampa.
            u.salva = nil
            u.fase = 'bajando'
            u.espera = self:tiempoRecarga(u)
        end
    elseif u.fase == 'bajando' then
        u.elevacion = math.max(0, u.elevacion - maxima * dt / 2.5)
        -- Con la rampa abajo, recoge los gatos (si los lleva) y recarga.
        if u.elevacion == 0 and not recogerGatos(u, dt) then
            u.fase = 'recarga'
        end
    elseif u.fase == 'recarga' and u.espera <= 0 then
        -- Sube una salva de su modelo (el Scud-B, un misil) y, si caben más
        -- y hay munición libre, sigue recargando.
        Tropas.recargar(u, u.proyectiles or 1)
        if Tropas.puedeCargar(u) > 0 then
            u.espera = self:tiempoRecarga(u)
        else
            u.fase = 'espera'
            u.espera = 1
        end
    end
end

--- Cuánto ha avanzado de media cada bando (sus tanques vivos).
function Tropas:medirAvance()
    local suma = { 0, 0 }
    local n = { 0, 0 }
    for _, u in ipairs(self.unidades) do
        if not u.muerto and u.tipo == 'tanque' then
            suma[u.bando] = suma[u.bando] + u.avanzado
            n[u.bando] = n[u.bando] + 1
        end
    end
    for b = 1, 2 do
        if n[b] > 0 then
            self.avance[b] = suma[b] / n[b]
        else
            self.avance[b] = 0
        end
    end
end

--- Avanza la pelea `dt` s en pasos fijos de `Tropas.pasoFijo` (DANO-REAL.md
-- §8.1): lo que sobra espera al siguiente cuadro. Si el cuadro va lento, la
-- pelea va más despacio (`maxPasos`), pero da lo mismo.
function Tropas:actualizar(dt)
    self.acumulado = self.acumulado + dt
    local pasos = 0
    while self.acumulado >= Tropas.pasoFijo - 1e-9 and pasos < Tropas.maxPasos do
        self.acumulado = self.acumulado - Tropas.pasoFijo
        pasos = pasos + 1
        self:paso(Tropas.pasoFijo)
    end
    if pasos == Tropas.maxPasos then
        self.acumulado = math.min(self.acumulado, Tropas.pasoFijo)
    end
    self.relojVista = self.reloj + math.max(0, self.acumulado)
end

--- Un paso fijo de la pelea.
function Tropas:paso(dt)
    self.reloj = self.reloj + dt
    self.pasos = self.pasos + 1
    self:relevar()
    self:medirAvance()
    if self.fisica then
        self.fisica:iniciarCuadro()
    end
    for _, u in ipairs(self.unidades) do
        if u.tipo == 'lanzacohetes' then
            u.lanzador:recordarPosicion(u)
            if u.averiado then
                -- Averiado con la rampa arriba: la baja vacía.
                local maxima = u.lanzador.modelo.elevacion or 35
                u.elevacion = math.max(0, u.elevacion - maxima * dt / 2.5)
            end
        elseif u.orugas then
            u.orugas:recordarPosicion(u)
        end
        if u.muerto then
            u.humoEspera = u.humoEspera - dt
            if u.humoEspera <= 0 then
                u.humoEspera = 0.3
                if u.destruccion then
                    self:humo(u.x, u.y, u.z + 18, 12, 2.6, 0.12, 30)
                else
                    self:humo(u.x, u.y, u.z + 25, 26, 4, 0.18, 55)
                end
            end
        elseif u.tipo == 'tanque' then
            self:actualizarTanque(u, dt)
        else
            self:actualizarLanzacohetes(u, dt)
        end
    end
    if self.fisica then
        self.fisica:actualizar(dt)
        for _, u in ipairs(self.unidades) do
            local cambio = u.tipo ~= 'lanzacohetes'
                or u.x ~= u.anteriorRuedasX
                or u.y ~= u.anteriorRuedasY
                or u.z ~= u.anteriorRuedasZ
                or u.rumbo ~= u.anteriorRuedasRumbo
            if cambio then
                -- El terreno es estático: el camión frenado conserva su
                -- apoyo. La rampa y las ruedas se siguen animando aparte.
                Modelos3d.postura(self.suelo, u.x, u.y, u.z, u.rumbo, u.casco)
            end
        end
    end
    for _, u in ipairs(self.unidades) do
        if u.tipo == 'lanzacohetes' then
            u.lanzador:medirMovimiento(u, dt)
        elseif u.orugas then
            -- Las orugas ruedan según lo que el tanque se ha movido de verdad.
            u.orugas:medirMovimiento(u, dt)
        end
        -- Velocidad de cada unidad (la anticipación del control de tiro).
        u.vx = (u.x - (u.previaX or u.x)) / dt
        u.vy = (u.y - (u.previaY or u.y)) / dt
        u.previaX, u.previaY = u.x, u.y
    end
    self:pasoEfectos(dt)
end

--- Fuera de la pelea (preparación), solo los proyectiles, las estelas y
-- las partículas: los misiles del camión de robot conductor.
function Tropas:actualizarEfectos(dt)
    self.acumulado = self.acumulado + dt
    local pasos = 0
    while self.acumulado >= Tropas.pasoFijo - 1e-9 and pasos < Tropas.maxPasos do
        self.acumulado = self.acumulado - Tropas.pasoFijo
        pasos = pasos + 1
        self.reloj = self.reloj + Tropas.pasoFijo
        self:pasoEfectos(Tropas.pasoFijo)
    end
    if pasos == Tropas.maxPasos then
        self.acumulado = math.min(self.acumulado, Tropas.pasoFijo)
    end
    self.relojVista = self.reloj + math.max(0, self.acumulado)
end

--- Proyectiles, estelas y partículas: un paso.
function Tropas:pasoEfectos(dt)
    -- Daño real (Valeria, batalla/dano/): los cuerpos donde están ahora y
    -- cada proyectil, el tramo que vuela en este paso.
    self.cuerpos:rehacer()
    self.proyectiles:avanzar()
    for _, m in ipairs(self.misiles) do
        local x, y, z = Tropas.posicionMisil(m, (self.reloj - m.inicio) / m.duracion)
        self.estelas:apuntar(m.estela, x, y, z, self.reloj)
    end
    self.estelas:actualizar(self.reloj)
    for k = #self.particulas, 1, -1 do
        local p = self.particulas[k]
        p.t = p.t + dt
        if p.t >= p.vida then
            self.particulas[k] = self.particulas[#self.particulas]
            self.particulas[#self.particulas] = nil
        else
            p.vz = p.vz - p.gravedad * dt
            p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
        end
    end
end

-- Dibujo -------------------------------------------------------------------------------------

local matriz = {}

function Tropas:dibujarUnidades(shader)
    local g = love.graphics
    g.setColor(1, 1, 1, 1)
    for _, u in ipairs(self.unidades) do
        shader:send('colorNacion', { u.color[1], u.color[2], u.color[3] })
        shader:send('quemado', u.quemado * 0.85)
        if u.tipo == 'tanque' then
            local tanque = u.modelo3d.piezas
            local torreta, canon = Modelos3d.matricesTanque(u.casco, u.torreta, u.retroceso, u.modelo3d)
            shader:send('modelo', 'row', u.casco)
            g.draw(tanque.casco.malla)
            shader:send('modelo', 'row', torreta)
            g.draw(tanque.torreta.malla)
            shader:send('modelo', 'row', canon)
            g.draw(tanque.canon.malla)
            if u.orugas then
                -- El tren de rodaje y las orugas (aquí sin desplazar la oruga).
                for _, nombre in ipairs(u.orugas.giran) do
                    shader:send('modelo', 'row', u.matricesOrugas[nombre])
                    g.draw(tanque[nombre].malla)
                end
                shader:send('modelo', 'row', u.casco)
                for _, nombre in ipairs(u.orugas.orugas) do
                    g.draw(tanque[nombre].malla)
                end
            end
        else
            local lanza = u.lanzador.modelo.piezas
            for _, nombre in ipairs(u.lanzador.piezas) do
                if Lanzamisiles.visible(u, nombre) then
                    shader:send('modelo', 'row', u.matricesLanza[nombre])
                    g.draw(lanza[nombre].malla)
                end
            end
        end
    end
    shader:send('quemado', 0)
end

--- Grosor mínimo para que algo fino (un trazador, un misil) se siga viendo
-- desde lejos: un par de puntos de pantalla a la distancia de la cámara.
local function grosorVisible(grosor, x, y, z, ex, ey, ez, k)
    local d = math.sqrt((x - ex) ^ 2 + (y - ey) ^ 2 + (z - ez) ^ 2)
    return math.max(grosor, d * k)
end

--- Efectos: trazadores, misiles, estelas y partículas, vistos desde (ex, ey,
-- ez). Van después de lo opaco, sin escribir profundidad (el humo se
-- transparenta).
function Tropas:dibujarEfectos(shader, ex, ey, ez)
    local g = love.graphics
    shader:send('brillo', 1)
    g.setColor(1, 0.9, 0.55, 1)
    for _, b in ipairs(self.balas) do
        local t = (self.reloj - b.inicio) / b.duracion
        local largoTrazador = b.trazador or Tropas.largoTrazador
        local t0 = math.max(0, t - largoTrazador / math.max(1, b.largo))
        local ax, ay, az = Tropas.posicionBala(b, t0)
        local bx, by, bz = Tropas.posicionBala(b, t)
        local color = b.color or { 1, 0.9, 0.55, 1 }
        g.setColor(color[1], color[2], color[3], color[4] or 1)
        local grosor = grosorVisible(b.grosor or 2.5, bx, by, bz, ex, ey, ez, 0.0014)
        shader:send('modelo', 'row', Matriz.entre(ax, ay, az, bx, by, bz, grosor, matriz))
        g.draw(mallaVara)
    end
    for _, m in ipairs(self.misiles) do
        local t = (self.reloj - m.inicio) / m.duracion
        local ax, ay, az = Tropas.posicionMisil(m, math.max(0, t - 0.004))
        local bx, by, bz = Tropas.posicionMisil(m, t)
        -- Sin 3Dream, el cuerpo es una vara de las medidas del misil.
        shader:send('brillo', 0.08)
        g.setColor(0.42, 0.5, 0.36, 1)
        shader:send('modelo', 'row', Tropas.matrizVaraMisil(Tropas.matrizMisil(m, t, matriz)))
        g.draw(mallaVara)
        shader:send('brillo', 1)
        g.setColor(1, 0.7, 0.3, 1)
        local llama = grosorVisible(2.5, ax, ay, az, ex, ey, ez, 0.0008)
        shader:send('modelo', 'row', Matriz.colocar(ax, ay, az, 0, llama, matriz))
        g.draw(mallaBola)
    end
    shader:send('brillo', 0)
    self.estelas:dibujar(shader, self.reloj, ex, ey, ez)
    local brillo = 0
    for _, p in ipairs(self.particulas) do
        local f = p.t / p.vida
        local tam = p.tam0 + (p.tam1 - p.tam0) * f
        if p.brillo ~= brillo then
            brillo = p.brillo
            shader:send('brillo', brillo)
        end
        g.setColor(p.color[1], p.color[2], p.color[3], p.alfa * (1 - f * f))
        shader:send('modelo', 'row', Matriz.colocar(p.x, p.y, p.z, 0, tam, matriz))
        g.draw(mallaBola)
    end
    shader:send('brillo', 0)
    g.setColor(1, 1, 1, 1)
end

-- Para las capturas y el rótulo -----------------------------------------------------------------

--- ¿Algún tanque a menos de `radio` px de (x, y) acaba de disparar?
function Tropas:disparoCerca(x, y, radio)
    for _, b in ipairs(self.balas) do
        local reciente = self.reloj - b.inicio < 0.06
        if reciente and (b.x0 - x) ^ 2 + (b.y0 - y) ^ 2 < radio * radio then
            return true
        end
    end
    return false
end

--- Balas en vuelo, a mitad de camino, de disparos de más de `largo` px.
function Tropas:trazadoresLejanos(largo)
    local n = 0
    for _, b in ipairs(self.balas) do
        local t = (self.reloj - b.inicio) / b.duracion
        if b.largo > largo and t > 0.3 and t < 0.7 then
            n = n + 1
        end
    end
    return n
end

--- Misiles en lo alto de su vuelo.
function Tropas:misilesAltos()
    local n = 0
    for _, m in ipairs(self.misiles) do
        local t = (self.reloj - m.inicio) / m.duracion
        if t > 0.3 and t < 0.75 then
            n = n + 1
        end
    end
    return n
end

--- El primer lanzacohetes adelantado (vivo o no).
function Tropas:adelantado()
    for _, u in ipairs(self.unidades) do
        if u.adelantado then
            return u
        end
    end
    return nil
end

--- ¿Puede seguir peleando el bando `indice`? Con algo en pie en el campo o
-- en la reserva; con `armado`, además con munición.
function Tropas:enPie(indice, armado)
    local datos = self.bandos[indice]
    for _, u in ipairs(self.unidades) do
        local desarmado = Tropas.sinMunicion(u) or Blindaje.sinArma(u)
        if u.bando == indice and not u.muerto and not (armado and desarmado) then
            return true
        end
    end
    for _, v in ipairs(datos.cola) do
        if not armado or Tropas.municionQueda(v) > 0 then
            return true
        end
    end
    return false
end

--- ¿Queda el bando `indice` fuera de la regla de `sinFuego` (decisión de
-- El dueño)? El del jugador (solo se retira sin munición o sin nada en pie) y
-- el que tiene alguna unidad armada con la orden de mantener posición.
function Tropas:exentoAlcance(indice)
    local lado = self.combate.ladoJugador
    if lado and LADOS[indice] == lado then
        return true
    end
    for _, u in ipairs(self.unidades) do
        local mantiene = u.orden and u.orden.tipo == 'mantener'
        if u.bando == indice and mantiene and not u.muerto and not Tropas.sinMunicion(u) then
            return true
        end
    end
    return false
end

--- Cómo termina la pelea, o nil si sigue (decisión del dueño): { pierde
-- (1 o 2), retira ('atacante', 'defensor' o nil), motivo }.
--   'fuera'     al bando no le queda nada en pie: pierde sin retirarse;
--   'municion'  no le queda munición con la que dañar al rival: se retira;
--   'alcance'   tiene munición, pero en `sinFuego` s no ha disparado ni
--               avanzado con ella: no alcanza al rival y se retira (salvo el
--               bando del jugador o uno con unidades que mantienen posición,
--               `exentoAlcance`).
-- Si les pasa a los dos, se retira el atacante (el defensor aguanta).
function Tropas:fin()
    -- Sin vehículos en ningún bando (la batalla es de robots): esta cuenta no
    -- la termina.
    if self.bandos[1].vehiculos == 0 and self.bandos[2].vehiculos == 0 then
        return nil
    end
    local motivo = {}
    for indice = 1, 2 do
        if not self:enPie(indice) then
            motivo[indice] = 'fuera'
        elseif not self:enPie(indice, true) then
            motivo[indice] = 'municion'
        elseif not self:exentoAlcance(indice) then
            local activo = math.max(self.ultimoFuego[indice], self.ultimoAvance[indice])
            if self.reloj - activo > Tropas.sinFuego then
                motivo[indice] = 'alcance'
            end
        end
    end
    local pierde
    if motivo[1] == 'fuera' or motivo[2] == 'fuera' then
        pierde = motivo[1] == 'fuera' and 1 or 2
    elseif motivo[1] then
        pierde = 1
    elseif motivo[2] then
        pierde = 2
    end
    if not pierde then
        return nil
    end
    local m = motivo[pierde]
    return { pierde = pierde, retira = m ~= 'fuera' and LADOS[pierde] or nil, motivo = m }
end

--- ¿Terminó la pelea? (ver `fin`)
function Tropas:terminada()
    return self:fin() ~= nil
end

--- Recuento por bando para el rótulo: { tanque, lanzacohetes = { campo (en
-- pie en el campo), averiados, reserva, total }, soldado = { enPie, total }
-- (la infantería no pelea en la batalla 3D: sigue toda en pie), sin = { balas,
-- obuses, misiles } (unidades en pie que no tienen) }.
function Tropas:recuento()
    local r = {}
    for indice = 1, 2 do
        local datos = self.bandos[indice]
        local b = {
            tanque = { campo = 0, averiados = 0, reserva = 0, total = 0 },
            lanzacohetes = { campo = 0, averiados = 0, reserva = 0, total = 0 },
            soldado = { enPie = datos.soldados, total = datos.soldados },
            sin = { balas = 0, obuses = 0, misiles = 0 },
        }
        for _, v in ipairs(datos.cola) do
            b[v.tipo].reserva = b[v.tipo].reserva + 1
            b[v.tipo].total = b[v.tipo].total + 1
        end
        for _, u in ipairs(datos.todas) do
            local t = b[u.tipo]
            t.total = t.total + 1
            if u.averiado then
                t.averiados = t.averiados + 1
            else
                t.campo = t.campo + 1
            end
            if not u.muerto and not u.retirado and Tropas.sinMunicion(u) then
                local m = MUNICION_DE[u.tipo]
                b.sin[m] = b.sin[m] + 1
            end
        end
        r[indice] = b
    end
    return r
end

--- Resultado de la escena para `resolverBatalla` (F11), por lado: {
-- atacante = bando, defensor = bando } con bando = { soldados = { muertos,
-- heridos }, averiados = { tanques = { daño, ... }, lanzacohetes = { ... },
-- modelos = { tanques = { modelo, ... }, lanzacohetes = { ... } }, zonas = {
-- tanques = { zonas, ... }, lanzacohetes = { ... } } }, municion = { [clave
-- de la fuente] = { balas, obuses, misiles } } }.
--   `averiados.modelos` y `averiados.zonas` dicen el modelo y las averías
--   de cada daño, en el mismo orden (la simulación de hoy no los lee:
--   reparte los averiados en proporción). Zonas: { orugas, torreta, canon,
--   motor = true, tripulacion = bajas, estructura = 0 a 1 } (DANO-REAL.md §5.5).
--   La munición gastada va redondeada (los proyectiles de una salva gastan
--   fracciones de misil).
--   vehículo  daño de sus averías por zona (Blindaje.dano, de 0 a 1); con
--             daño 0 no se nombra (los de la reserva que no llegaron a
--             entrar, tampoco). Con daño entra aunque siga peleando: va al taller.
--   soldados  siempre 0: la infantería no pelea en la batalla 3D.
--   tripulación  `tripulacion = { muertos, heridos }`: las bajas de las
--             tripulaciones de los vehículos del bando (DANO-REAL.md §5.6).
-- `semilla` y `batalla` se aceptan por compatibilidad: el resultado ya sale
-- de la pelea, igual en cada máquina con pasos fijos.
function Tropas:resultado(_semilla, _batalla)
    local out = {}
    for indice, lado in ipairs(LADOS) do
        local datos = self.bandos[indice]
        local r = {
            soldados = { muertos = 0, heridos = 0 },
            tripulacion = { muertos = 0, heridos = 0 },
            averiados = {
                tanques = {},
                lanzacohetes = {},
                modelos = { tanques = {}, lanzacohetes = {} },
                zonas = { tanques = {}, lanzacohetes = {} },
            },
            municion = {},
        }
        for _, u in ipairs(datos.todas) do
            local a = u.averias
            if a then
                r.tripulacion.muertos = r.tripulacion.muertos + a.tripulacionMuertos
                r.tripulacion.heridos = r.tripulacion.heridos + a.tripulacion - a.tripulacionMuertos
            end
            local dano = Blindaje.dano(u)
            if dano > 1e-6 then
                local tropa = TROPA_DE[u.tipo]
                local lista = r.averiados[tropa]
                lista[#lista + 1] = math.floor(dano * 10000 + 0.5) / 10000
                r.averiados.modelos[tropa][#lista] = u.modelo or Tropas.modeloPorDefecto(u.tipo)
                r.averiados.zonas[tropa][#lista] = Blindaje.zonas(u) or {}
            end
        end
        for _, f in ipairs(datos.fuentes) do
            if f.clave ~= nil then
                r.municion[f.clave] = {
                    balas = math.floor(f.gastado.balas + 0.5),
                    obuses = math.floor(f.gastado.obuses + 0.5),
                    misiles = math.floor(f.gastado.misiles + 0.5),
                }
            end
        end
        out[lado] = r
    end
    return out
end

return Tropas

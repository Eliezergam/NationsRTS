--- Datos del daño real de la batalla 3D (Valeria, batalla/DANO-REAL.md §4):
-- cañones y su munición, blindaje por zonas, ojivas y lo que
-- vale cada avería para la simulación.
--
-- Las cifras reales son públicas y aproximadas (Wikipedia y fichas abiertas
-- de munición), tomadas sin conexión: están marcadas «verificar». Del
-- catálogo (mundo/simulacion/catalogoArmamento.lua) salen el calibre, la
-- tripulación y el blindaje del T-55. Se suavizan como el catálogo (P4,
-- α = 0,5): la referencia (T-72B) queda igual y los demás se le acercan.
--
-- Unidades: lo real en sus unidades (m, m/s, mm, mrad); las funciones
-- `canon` y `ojiva` lo devuelven en px (1 px = 10 cm) y px/s.
-- Solo datos y cuentas; sin LÖVE.

local Catalogo = require('mundo.simulacion.catalogoArmamento')

local Datos = {}

Datos.gravedad = 98 -- px/s² (9,8 m/s²)
Datos.suavizado = 0.5 -- P4 del catálogo
Datos.referencia = 't72b'

-- Cañones con su munición perforante (verificar): velocidad de boca (m/s),
-- penetración a 2 km (mm de acero), error de tiro del tirador y el control
-- de tiro (mrad, σ), error en la distancia que mide (parte, σ) y si anticipa
-- a un blanco en marcha.
Datos.canones = {
    t55 = { municion = '3BM8', vBoca = 1415, pen2km = 275, error = 1.2, errorDistancia = 0.05, anticipa = false },
    t72b = { municion = '3BM42', vBoca = 1700, pen2km = 500, error = 0.7, errorDistancia = 0.01, anticipa = true },
    m1a1 = { municion = 'M829A1', vBoca = 1575, pen2km = 570, error = 0.45, errorDistancia = 0.01, anticipa = true },
    k2 = { municion = 'K279', vBoca = 1760, pen2km = 650, error = 0.4, errorDistancia = 0.01, anticipa = true },
}

Datos.perforante = {
    arrastre = 4.6e-5, -- 1/m: pierde unos 75 m/s por km
    dispersion = 0.25, -- mrad (σ), la del arma
    variacion = 0.05, -- σ de la penetración de un disparo a otro
    rebote = 75, -- grados: más rasante, rebota
    exponente = 1.5, -- penetración ∝ velocidad ^ exponente
}

-- Explosiva (HE-FRAG) que el tanque tira contra la infantería (verificar).
Datos.explosiva = {
    vBoca = 850,
    arrastre = 2e-4,
    dispersion = 0.4,
    letal = 6, -- m a 125 mm, proporcional al calibre
    metralla = 20, -- m a 125 mm
    rebote = 65,
    penPorCalibre = 0.25, -- mm de penetración de un golpe directo por mm de calibre
}

-- Blindaje real por zonas, mm equivalentes contra cinéticos en línea
-- horizontal (la inclinación de la chapa va dentro). T-55 del catálogo
-- (torreta 205 mm, casco 120 mm a 60°, unos 200 en línea); el resto, verificar.
Datos.blindajes = {
    t55 = { frenteCasco = 200, frenteTorreta = 205, costadoCasco = 80, costadoTorreta = 150, trasera = 45, techo = 30 },
    t72b = { frenteCasco = 480, frenteTorreta = 520, costadoCasco = 80, costadoTorreta = 250, trasera = 40, techo = 45 },
    m1a1 = { frenteCasco = 560, frenteTorreta = 600, costadoCasco = 70, costadoTorreta = 270, trasera = 40, techo = 40 },
    k2 = { frenteCasco = 600, frenteTorreta = 700, costadoCasco = 90, costadoTorreta = 300, trasera = 40, techo = 50 },
}

-- Camiones lanzacohetes: chapa (mm).
Datos.camion = { cabina = 8, resto = 5 }

-- Explosiones (DANO-REAL.md §6.3 y §7).
Datos.explosion = {
    metralla = 2.5, -- × el radio letal: más lejos no alcanza (P de Carleton < 2 %)
    -- Radio en que cae la mitad de los soldados (Carleton) × el radio de la
    -- ficha (`escena.radio`). 1: el de la ficha (DANO-REAL.md §10, P1).
    escalaLetal = 1,
    muerteLetal = 0.6, -- de los que caen dentro del radio letal, mueren
    muerteMetralla = 0.25, -- de los que caen más lejos, mueren
    cubierto = 0.15, -- la metralla contra quien está a cubierto
    -- Estructura que quita la onda al pie de la explosión de radio 18 m (la
    -- del Scud-B; las demás, proporcional al radio). 1,05 = 3 × 0,35:
    -- decisión del dueño del 2026-10-01 (DANO-REAL.md §10, D4).
    onda = 1.05,
    radioOnda = 18, -- m: el del Scud-B
    -- Probabilidad de romper la oruga al pie de la explosión por cada punto
    -- de onda (con la del Scud-B, 1,5: segura; con un cohete del BM-21, 0,42).
    ondaOruga = 1 / 0.7,
    camionTripulacion = 0.3, -- metralla contra la cabina de un camión
}

-- Calibre de los misiles (mm): el del camión de misiles con robot conductor
-- (clave 'scudb'), el del misil R-17 del Scud-B que fue, verificar.
Datos.calibreCohete = { scudb = 880 }

-- Averías (DANO-REAL.md §5.4 y §5.5).
Datos.averias = {
    -- Lo que vale cada una en el daño (0 a 1) que vuelve a la simulación.
    valor = { orugas = 0.2, torreta = 0.25, canon = 0.3, motor = 0.35, tripulante = 0.1 },
    estructuraPenetracion = 0.15, -- cada penetración: el agujero
    atascoTorreta = 0.5, -- una penetración en la torreta la atasca con esta probabilidad
    alturaOruga = 0.35, -- parte baja de los costados del casco: oruga o ruedas
    largoMotor = 0.3, -- parte trasera del casco (el frente del camión): motor
    sobrante = 0.5, -- penetración sobrante (parte) con la que caen dos tripulantes
    muerteTripulante = 0.4, -- un tripulante que cae muere con esta probabilidad (F11b)
    -- Una bala de fusil que atraviesa la chapa de un camión: probabilidad de
    -- cada avería (si no, solo estructura).
    bala = { motor = 0.1, tripulante = 0.3, orugas = 0.15, canon = 0.05, estructura = 0.01 },
    giroLibre = 0.05, -- rad: con la torreta atascada dispara a lo que tiene delante
}

Datos.rebote = { velocidad = 0.5 } -- lo que le queda al proyectil que rebota

--- Valor de juego de `valor` real respecto al de referencia `ref`.
function Datos.suavizar(valor, ref)
    if not ref or ref <= 0 then
        return valor
    end
    return ref * (valor / ref) ^ Datos.suavizado
end

local cache = { canon = {}, blindaje = {}, ojiva = {} }

--- Cañón del tanque `modelo` en unidades de juego: { vBoca (px/s), arrastre
-- (1/px), penBoca (mm, suavizada), error (rad), errorDistancia, anticipa,
-- calibre (mm), explosiva = { vBoca, arrastre, letal, metralla (px), pen } }.
function Datos.canon(modelo)
    local c = cache.canon[modelo]
    if c then
        return c
    end
    local real = Datos.canones[modelo] or Datos.canones[Datos.referencia]
    local ref = Datos.canones[Datos.referencia]
    local ficha = Catalogo.tanques[modelo] or Catalogo.tanques[Datos.referencia]
    local p = Datos.perforante
    local pen2km = Datos.suavizar(real.pen2km, ref.pen2km)
    -- La penetración en boca: la de 2 km por la velocidad que se pierde.
    local v2km = real.vBoca * math.exp(-p.arrastre * 2000)
    local penBoca = pen2km / (v2km / real.vBoca) ^ p.exponente
    local e = Datos.explosiva
    local k = ficha.calibre / 125
    c = {
        modelo = modelo,
        calibre = ficha.calibre,
        tripulacion = ficha.tripulacion,
        vBoca = real.vBoca * 10,
        arrastre = p.arrastre / 10,
        penBoca = penBoca,
        pen2km = pen2km,
        error = real.error / 1000,
        errorDistancia = real.errorDistancia,
        anticipa = real.anticipa,
        dispersion = p.dispersion / 1000,
        explosiva = {
            vBoca = e.vBoca * 10,
            arrastre = e.arrastre / 10,
            dispersion = e.dispersion / 1000,
            letal = e.letal * k * 10,
            metralla = e.metralla * k * 10,
            pen = e.penPorCalibre * ficha.calibre,
            onda = Datos.explosion.onda * e.letal * k / Datos.explosion.radioOnda,
        },
    }
    cache.canon[modelo] = c
    return c
end

--- Blindaje de juego del tanque `modelo` por zonas (mm, suavizado).
function Datos.blindaje(modelo)
    local b = cache.blindaje[modelo]
    if b then
        return b
    end
    local real = Datos.blindajes[modelo] or Datos.blindajes[Datos.referencia]
    local ref = Datos.blindajes[Datos.referencia]
    b = {}
    for zona, mm in pairs(real) do
        b[zona] = Datos.suavizar(mm, ref[zona])
    end
    cache.blindaje[modelo] = b
    return b
end

--- Ojiva de los cohetes o misiles del lanzacohetes `modelo` con radio
-- letal `radio` px (el de su ficha de escena): { letal, metralla (px), pen
-- (mm), onda (estructura al pie) }.
function Datos.ojiva(modelo, radio)
    local clave = modelo .. '|' .. radio
    local o = cache.ojiva[clave]
    if o then
        return o
    end
    local e = Datos.explosion
    local calibre = Datos.calibreCohete[modelo] or Datos.calibreCohete.scudb
    o = {
        letal = radio,
        metralla = radio * e.metralla,
        pen = Datos.explosiva.penPorCalibre * calibre,
        onda = e.onda * radio / (e.radioOnda * 10),
    }
    cache.ojiva[clave] = o
    return o
end

--- Tripulación del vehículo `modelo` (del catálogo; 3 si no la dice).
function Datos.tripulacion(modelo)
    local ficha = Catalogo.tanques[modelo] or Catalogo.lanzacohetes[modelo]
    return ficha and ficha.tripulacion or 3
end

return Datos

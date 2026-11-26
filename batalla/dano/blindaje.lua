--- Blindaje y averías de los vehículos de la batalla 3D (Valeria,
-- batalla/DANO-REAL.md §5): zona del golpe, blindaje efectivo (espesor /
-- cos θ), rebote, penetración y avería por zona. Los vehículos no se
-- destruyen (regla del dueño): se averían y vuelven al taller.
--
-- `u.averias` = { orugas, torreta, canon, motor (true o false), tripulacion
-- (bajas), estructura (0 a 1) }. En el camión, `orugas` son las ruedas y
-- `canon` el lanzador.

local Datos = require('batalla.dano.datos')

local Blindaje = {}

local PESADOS = { perforante = true, explosiva = true, ojiva = true }

--- Prepara las averías y la tripulación del vehículo `u`.
function Blindaje.iniciar(u)
    u.averias = {
        orugas = false,
        torreta = false,
        canon = false,
        motor = false,
        tripulacion = 0,
        tripulacionMuertos = 0,
        estructura = 0,
    }
    u.tripulacion = Datos.tripulacion(u.modelo)
end

--- Daño (0 a 1) que vuelve a la simulación.
function Blindaje.dano(u)
    local a = u.averias
    if not a then
        return 0
    end
    local v = Datos.averias.valor
    local d = a.estructura + a.tripulacion * v.tripulante
    for _, zona in ipairs({ 'orugas', 'torreta', 'canon', 'motor' }) do
        if a[zona] then
            d = d + v[zona]
        end
    end
    return math.min(1, d)
end

--- ¿No puede moverse? (oruga o rueda rota, o motor roto)
function Blindaje.inmovil(u)
    local a = u.averias
    return a ~= nil and (a.orugas or a.motor)
end

--- ¿No puede disparar? (cañón o lanzador roto)
function Blindaje.sinArma(u)
    local a = u.averias
    return a ~= nil and a.canon
end

--- Parte de la tripulación que queda (1 sin bajas).
function Blindaje.tripulacionQueda(u)
    local a = u.averias
    if not a or not u.tripulacion then
        return 1
    end
    return math.max(0, u.tripulacion - a.tripulacion) / u.tripulacion
end

--- ¿Queda fuera de combate? Sin tripulación, sin arma e inmovilizado, o con
-- la estructura deshecha.
function Blindaje.fueraDeCombate(u)
    local a = u.averias
    if not a then
        return false
    end
    if a.tripulacion >= (u.tripulacion or 3) then
        return true
    end
    if a.canon and (a.orugas or a.motor) then
        return true
    end
    return a.estructura >= 1
end

--- Zonas averiadas de `u` para el resultado: { orugas = true, ... } o nil.
function Blindaje.zonas(u)
    local a = u.averias
    if not a then
        return nil
    end
    local z = {}
    local alguna = false
    for _, zona in ipairs({ 'orugas', 'torreta', 'canon', 'motor' }) do
        if a[zona] then
            z[zona] = true
            alguna = true
        end
    end
    if a.tripulacion > 0 then
        z.tripulacion = a.tripulacion
        z.tripulacionMuertos = a.tripulacionMuertos
        alguna = true
    end
    if a.estructura > 0 then
        z.estructura = math.floor(a.estructura * 100 + 0.5) / 100
        alguna = true
    end
    return alguna and z or nil
end

--- `n` bajas en la tripulación: cada una muere con `Datos.averias.muerteTripulante`
-- y si no queda herida (DANO-REAL.md §5.6).
local function herirTripulacion(u, n, azar)
    local a = u.averias
    local caen = math.min(u.tripulacion or 3, a.tripulacion + n) - a.tripulacion
    for _ = 1, caen do
        if azar:random() < Datos.averias.muerteTripulante then
            a.tripulacionMuertos = a.tripulacionMuertos + 1
        end
    end
    a.tripulacion = a.tripulacion + caen
end

--- Zona y espesor (mm) de un golpe en el tanque `u`. `g` es el golpe de
-- Cuerpos.cruzar (pieza, eje, signo y punto local).
local function zonaTanque(u, g)
    local b = Datos.blindaje(u.modelo)
    local pieza = g.pieza.nombre
    local caja = g.pieza.caja
    if pieza == 'canon' then
        return 'canon', b.costadoTorreta
    end
    if pieza == 'torreta' then
        if g.eje == 1 then
            return 'torreta', g.signo > 0 and b.frenteTorreta or b.trasera
        elseif g.eje == 2 then
            return 'torreta', b.costadoTorreta
        end
        return 'torreta', b.techo
    end
    local cfg = Datos.averias
    if g.eje == 2 and g.lz < caja[5] + cfg.alturaOruga * (caja[6] - caja[5]) then
        return 'orugas', b.costadoCasco
    end
    local trasera = g.lx < caja[1] + cfg.largoMotor * (caja[2] - caja[1])
    local espesor
    if g.eje == 1 then
        espesor = g.signo > 0 and b.frenteCasco or b.trasera
    elseif g.eje == 2 then
        espesor = b.costadoCasco
    else
        espesor = b.techo
    end
    return trasera and 'motor' or 'casco', espesor
end

--- Zona y espesor (mm) de un golpe en el camión `u`.
local function zonaCamion(g)
    local pieza = g.pieza.nombre
    local caja = g.pieza.caja
    local c = Datos.camion
    if pieza == 'contenedor' then
        return 'canon', c.resto
    end
    local cfg = Datos.averias
    if g.eje == 2 and g.lz < caja[5] + cfg.alturaOruga * (caja[6] - caja[5]) then
        return 'orugas', c.resto
    end
    -- El frente: la cabina con el motor.
    if g.lx > caja[2] - 0.35 * (caja[2] - caja[1]) then
        return 'cabina', c.cabina
    end
    return 'carga', c.resto
end

--- Lo que hace una penetración en la `zona` del vehículo `u`.
local function averiarZona(u, zona, sobrante, pesado, azar)
    local a = u.averias
    local cfg = Datos.averias
    if not pesado then
        -- Una bala de fusil que atraviesa la chapa de un camión.
        local p = cfg.bala
        a.estructura = a.estructura + p.estructura
        if zona == 'cabina' then
            if azar:random() < p.tripulante then
                herirTripulacion(u, 1, azar)
            elseif azar:random() < p.motor then
                a.motor = true
            end
        elseif zona == 'orugas' and azar:random() < p.orugas then
            a.orugas = true
        elseif zona == 'canon' and azar:random() < p.canon then
            a.canon = true
        end
        return
    end
    a.estructura = a.estructura + cfg.estructuraPenetracion
    local bajas = sobrante > cfg.sobrante and 2 or 1
    if zona == 'orugas' then
        a.orugas = true
    elseif zona == 'canon' then
        a.canon = true
    elseif zona == 'motor' then
        a.motor = true
    elseif zona == 'torreta' then
        if azar:random() < cfg.atascoTorreta then
            a.torreta = true
        end
        herirTripulacion(u, bajas, azar)
    elseif zona == 'cabina' then
        if azar:random() < 0.5 then
            a.motor = true
        end
        herirTripulacion(u, bajas, azar)
    elseif zona == 'carga' then
        a.estructura = a.estructura + cfg.estructuraPenetracion
    else
        herirTripulacion(u, bajas, azar)
    end
end

--- Golpe `g` (de Cuerpos.cruzar) de un proyectil `p` = { clase
-- ('perforante', 'explosiva', 'ojiva' o 'bala'), pen (mm que le quedan),
-- rebote (grados) } contra el vehículo `u`. Aplica la avería y devuelve {
-- efecto = 'rebote' | 'nopenetra' | 'penetra', zona, angulo (grados),
-- espesor (efectivo, mm) } en `salida`.
function Blindaje.golpe(u, g, p, azar, salida)
    local zona, espesor
    if u.tipo == 'tanque' then
        zona, espesor = zonaTanque(u, g)
    else
        zona, espesor = zonaCamion(g)
    end
    local normal
    if g.eje == 1 then
        normal = g.dx
    elseif g.eje == 2 then
        normal = g.dy
    else
        normal = g.dz
    end
    local coseno = math.max(0.02, math.abs(normal))
    local angulo = math.deg(math.acos(math.min(1, coseno)))
    local efectivo = espesor / coseno
    salida.zona, salida.angulo, salida.espesor = zona, angulo, efectivo
    local pesado = PESADOS[p.clase]
    local a = u.averias
    -- Lo que está fuera del blindaje se rompe aunque no penetre.
    if pesado and zona == 'orugas' then
        a.orugas = true
    elseif pesado and zona == 'canon' and u.tipo == 'tanque' then
        a.canon = true
    end
    if pesado and angulo > (p.rebote or 90) then
        salida.efecto = 'rebote'
        return salida
    end
    if p.pen < efectivo then
        salida.efecto = 'nopenetra'
        return salida
    end
    salida.efecto = 'penetra'
    averiarZona(u, zona, (p.pen - efectivo) / efectivo, pesado, azar)
    return salida
end

--- Onda de una explosión contra el vehículo `u`: `cerca` va de 0 (en el
-- borde del radio letal) a 1 (al pie); `ojiva` la de Datos.ojiva.
function Blindaje.onda(u, cerca, ojiva, azar)
    local a = u.averias
    if not a or cerca <= 0 then
        return
    end
    a.estructura = a.estructura + ojiva.onda * cerca
    -- La oruga se rompe más cuanto más fuerte es la onda.
    if azar:random() < Datos.explosion.ondaOruga * cerca * ojiva.onda then
        a.orugas = true
    end
end

--- Metralla contra la cabina de un camión: `cerca` de 0 a 1 en el radio de metralla.
function Blindaje.metralla(u, cerca, azar)
    if u.tipo ~= 'lanzacohetes' or not u.averias then
        return
    end
    if azar:random() < Datos.explosion.camionTripulacion * cerca then
        herirTripulacion(u, 1, azar)
    end
end

return Blindaje

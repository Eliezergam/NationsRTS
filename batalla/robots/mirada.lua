-- Hacia dónde mira un robot soldado, común a todos (el dueño, 18-nov: «la
-- lógica de la cabeza, los ojos y cómo lee el panorama, la misma de los demás
-- robots soldados»): lo usan el soldado (especializaciones/asalto.lua) y el
-- conductor del camión de misiles (especializaciones/vigiaConductor.lua).
--
-- El torso gira hasta `torsoMax` cuando hace falta (solo si se le pide), la
-- cabeza hace el resto hasta `cabezaMax` de lado y `arribaMax` hacia arriba,
-- y los ojos (globo{Der,Izq}) lo que aún falta, hasta `ojosMax`, más deprisa.
-- Sin nada que mirar, barre el panorama a un lado y a otro (barrido).
--
-- Los ángulos van en `d` (los datos de quien lo use): torso, cabeza,
-- cabezaArriba, ojoLado, ojoArriba.

local Mirada = {}

Mirada.cabezaMax = math.rad(75)
Mirada.arribaMax = math.rad(40)
Mirada.abajoMax = math.rad(25)
Mirada.torsoMax = math.rad(80)
Mirada.ojosMax = math.rad(20)
Mirada.rapidezTorso = 4
Mirada.rapidezCabeza = 5
Mirada.rapidezOjos = 18
Mirada.barridoAncho = math.rad(50)
Mirada.barridoRitmo = 0.9

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function limitar(v, a, b)
    return math.max(a, math.min(b, v))
end

--- Mirando el panorama sin nada concreto: a un lado y a otro de `rumbo`.
function Mirada.barrido(rumbo, reloj, ancho)
    return rumbo + math.sin(reloj * Mirada.barridoRitmo) * (ancho or Mirada.barridoAncho)
end

--- Un paso: mirar hacia el rumbo absoluto `mirarA` (y `arriba` rad sobre el
-- horizonte, si se da) con el torso girado hacia `quiereTorso` (respecto al
-- rumbo del cuerpo `rumbo`).
function Mirada.girar(d, rumbo, mirarA, quiereTorso, dt, arriba)
    d.torso = d.torso or 0
    d.cabeza = d.cabeza or 0
    d.cabezaArriba, d.ojoLado, d.ojoArriba = d.cabezaArriba or 0, d.ojoLado or 0, d.ojoArriba or 0
    quiereTorso = limitar(quiereTorso or 0, -Mirada.torsoMax, Mirada.torsoMax)
    d.torso = d.torso + (quiereTorso - d.torso) * math.min(1, dt * Mirada.rapidezTorso)
    local lado = angulo(mirarA - rumbo - d.torso)
    local quiereCabeza = limitar(lado, -Mirada.cabezaMax, Mirada.cabezaMax)
    d.cabeza = d.cabeza + (quiereCabeza - d.cabeza) * math.min(1, dt * Mirada.rapidezCabeza)
    arriba = arriba or 0
    local quiereArriba = limitar(arriba, -Mirada.abajoMax, Mirada.arribaMax)
    d.cabezaArriba = d.cabezaArriba + (quiereArriba - d.cabezaArriba) * math.min(1, dt * Mirada.rapidezCabeza)
    -- Los ojos: lo que la cabeza aún no alcanza.
    local k = math.min(1, dt * Mirada.rapidezOjos)
    d.ojoLado = d.ojoLado + (limitar(lado - d.cabeza, -Mirada.ojosMax, Mirada.ojosMax) - d.ojoLado) * k
    d.ojoArriba = d.ojoArriba + (limitar(arriba - d.cabezaArriba, -Mirada.ojosMax, Mirada.ojosMax) - d.ojoArriba) * k
end

--- Pone los giros en las piezas (en onPose).
function Mirada.poner(robot, d)
    robot:getPieza('torso'):setGiro('z', d.torso or 0, 'apuntarCuerpo')
    local cabeza = robot:getPieza('cabeza')
    cabeza:setGiro('z', d.cabeza or 0, 'mirar')
    -- Girar en y con ángulo negativo levanta la vista.
    cabeza:setGiro('y', -(d.cabezaArriba or 0), 'mirarArriba')
    for _, nombre in ipairs({ 'globoDer', 'globoIzq' }) do
        local globo = robot.piezas[nombre]
        if globo then
            globo:setGiro('z', d.ojoLado or 0, 'mirar')
            globo:setGiro('y', -(d.ojoArriba or 0), 'mirarArriba')
        end
    end
end

--- El rumbo y la elevación desde (ox, oy, oz) hacia (x, y, z) m.
function Mirada.hacia(ox, oy, oz, x, y, z)
    local dx, dy = x - ox, y - oy
    return math.atan2(dy, dx), math.atan2(z - oz, math.sqrt(dx * dx + dy * dy))
end

return Mirada

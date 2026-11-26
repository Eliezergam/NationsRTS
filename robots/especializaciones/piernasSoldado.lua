-- Las piernas del robot soldado: dos piernas con una rueda en cada pie, como
-- el robot Ascento (ETH Zúrich, arxiv.org/abs/2005.11435), que se equilibra
-- sobre sus dos ruedas y dobla cada pierna por separado.
--
-- Cada cuadro, a partir de cómo se mueve (conduccion.lua):
--   * altura: de pie a poca velocidad; corriendo se agacha (baja la cadera)
--     para ir más estable;
--   * cabeceo: un péndulo invertido sobre ruedas se inclina hacia delante
--     para acelerar y hacia atrás para frenar (atan(a / g));
--   * curvas: se inclina hacia dentro como una moto (atan(v · w / g)); la
--     pierna de dentro se encoge y la de fuera se estira, así las dos
--     ruedas siguen en el suelo.
--   * piernas que siguen al movimiento (el dueño, 18-nov: «que las patitas se
--     muevan según para dónde vaya»), como un esquiador: en las curvas la
--     rueda de fuera va adelantada (recorre más) y se abre hacia fuera para
--     ensanchar la base; girando parado, las piernas se cruzan en tijera
--     (una delante, otra detrás); marcha atrás, al revés. Cada pierna sigue
--     lo pedido con un muelle (se pasa un poco y vuelve): no cambia de golpe.
--   * patinar (el dueño, 18-nov: «que una se adelante más según hacia dónde
--     va, que parezca que van en patines»): corriendo deprisa (más de
--     `patinarDesde` m/s), las piernas alternan como un patinador: una se
--     desliza delante mientras la otra empuja detrás y hacia fuera, y el
--     peso pasa un poco a la que desliza. El ritmo sube con la velocidad.
--   * patinar para correr (ajuste `patinador`; el dueño, 18-nov: «que él solo
--     decida cuándo patinar y cuándo ir con los pies juntos»): por encima de
--     `patinarDesde` los motores ya no lo aceleran; lo que gana de velocidad
--     sale de las zancadas (cada empujón, un impulso). Al llegar a la
--     velocidad que quiere, junta los pies y se desliza: el roce lo va
--     frenando poco a poco; cuando ha perdido bastante (`volverAPatinar`),
--     vuelve a patinar. Así nunca se para antes de llegar. Para arrancar
--     desde parado y para frenar, los motores de las ruedas, como siempre.
-- Cada pierna se resuelve con su cinemática inversa: muslo y espinilla miden
-- lo mismo (L) y la rueda queda siempre bajo la cadera.
--
-- Piezas (assets/batalla/robots/soldado_piezas.lua): pelvis (cadera a
-- 0,95 m), muslo{S}, espinilla{S} (rodilla 0,183 m delante y 0,4 m abajo)
-- y rueda{S} (0,4 m más abajo, bajo la cadera; radio 0,15 m).

local Nucleo = require('robots.nucleo')

local Piernas = {}

Piernas.largo = math.sqrt(0.183303 ^ 2 + 0.4 ^ 2) -- muslo y espinilla
Piernas.alturaReposo = 0.8 -- de la cadera al eje de la rueda, de pie
Piernas.mitadCaderas = 0.1 -- m de la pelvis a cada cadera (y)
Piernas.agacharMaximo = 0.16 -- m que baja la cadera corriendo a tope
Piernas.bajarDePie = 0.03 -- un poco flexionado al ir despacio (no con la rodilla bloqueada)
-- Quieto, recto (el dueño, 18-nov: «¿por qué está medio flexionado? Debería
-- estar recto con una pierna un poco adelante»): el modelo tiene las
-- rodillas dobladas; quieto, la cadera sube hasta casi estirar las piernas
-- y la izquierda va un poco delante. Al moverse vuelve a la de siempre.
Piernas.subirQuieto = 0.065 -- m que sube la cadera quieto
Piernas.pieDelante = { Izq = 0.11, Der = -0.03 } -- m de cada rueda, quieto
Piernas.quietoHasta = 1.2 -- m/s: más rápido, la postura de moverse
-- Postura de disparo (self.posturaDisparo, la pone el lanzamisiles): bien
-- plantado y abierto, la izquierda delante y la derecha atrás, las rodillas
-- algo dobladas y el pecho echado hacia el blanco; al disparar, encaja el
-- retroceso (self.retrocesoDisparo) echándose atrás un instante.
Piernas.disparoPies = { Izq = 0.24, Der = -0.16 } -- m de cada rueda
Piernas.disparoAbrir = math.rad(9) -- lo que se abre cada pierna
Piernas.disparoBajar = 0.06 -- m que baja la cadera (sobre la de quieto)
Piernas.disparoPecho = math.rad(6) -- hacia delante
Piernas.retroceso = math.rad(9) -- hacia atrás, en el disparo
-- (A 50 km/h el soldado de la batalla llegaba a 14° y 18° y se bamboleaba:
-- El dueño, 18-nov, «se balancean mucho».)
Piernas.cabeceoMaximo = math.rad(7)
Piernas.inclinacionMaxima = math.rad(11)
Piernas.suave = 4 -- 1/s: lo rápido que sigue lo pedido
Piernas.tijera = 0.16 -- m que adelanta la rueda de fuera en la curva más cerrada
Piernas.patinarDesde = 3 -- m/s
Piernas.patinarTope = 7 -- m/s: desde esta velocidad, la zancada entera (en las rutas van a 7-9 m/s: frenan en las curvas)
Piernas.zancada = 0.40 -- m que va cada rueda delante y detrás (el dueño, 18-nov: «pasos más largos»)
Piernas.empuje = math.rad(20) -- lo que se abre la pierna que empuja (y se cierra al volver)
Piernas.ritmo = { 0.45, 0.03 } -- Hz: base y por cada m/s (a tope, 0,9 Hz: el dueño, 18-nov, «más lento»)
Piernas.impulso = 3.5 -- m/s² de media patinando (cada empujón, más en su mitad)
Piernas.roce = 0.7 -- m/s² que pierde deslizando con los pies juntos
Piernas.volverAPatinar = 0.8 -- con menos de esto de lo que quiere ir, patina
Piernas.yaVa = 0.97 -- con esto de lo que quiere ir, deja de patinar
Piernas.deslizarMinimo = 1.5 -- s con los pies juntos como poco (salvo si pierde mucho)
Piernas.perdidaMucha = 0.6 -- con menos de esto de lo que quiere ir, patina ya
Piernas.vaiven = math.rad(7) -- el cuerpo se inclina hacia la pierna que desliza (el dueño, 18-nov: «que se balancee un poco a los lados, como al patinar»)
Piernas.tijeraParado = 0.14 -- m girando sobre sí mismo
Piernas.abrir = math.rad(9) -- lo que se abre la pierna de fuera como mucho
Piernas.abrirCorriendo = math.rad(2.5) -- las dos, a toda velocidad
Piernas.frecuencia = 4 -- Hz del muelle de cada pierna
Piernas.amortiguacion = 0.45
local G = 9.81

local alfaReposo = math.asin(0.183303 / Piernas.largo)

local function limitar(v, a, b)
    return math.max(a, math.min(b, v))
end

function Piernas:onLoad()
    local d = self.datos.piernasSoldado
    d.bajar, d.cabeceo, d.inclinacion = Piernas.bajarDePie, 0, 0
    d.antes = 0
    -- Por pierna: adelanto (m) y apertura (rad), con su velocidad.
    d.pierna = {}
    for _, s in ipairs({ 'Izq', 'Der' }) do
        d.pierna[s] = { x = 0, vx = 0, a = 0, va = 0 }
    end
end

-- Un paso del muelle con amortiguador hacia `objetivo`.
local function muelle(x, v, objetivo, dt)
    local w = 2 * math.pi * Piernas.frecuencia
    local acel = -w * w * (x - objetivo) - 2 * Piernas.amortiguacion * w * v
    v = v + acel * dt
    return x + v * dt, v
end

--- Hacia dónde llevar cada pierna según cómo se mueve el robot.
local function piernasHaciaDondeVa(self, d, dt)
    local C = self:getAjustes('conduccion')
    local v, w = self.velocidad, self.giro
    local giro = limitar(w / C.giroMaximo, -1, 1)
    local rapido = limitar(math.abs(v) / C.velocidadSinCarga, 0, 1)
    -- Parado se cruzan más; andando, la de fuera va delante en el sentido de
    -- la marcha (marcha atrás, «delante» es hacia atrás).
    local adelanto = (Piernas.tijeraParado + (Piernas.tijera - Piernas.tijeraParado) * math.min(1, math.abs(v) / 0.5)) * giro
    if v < -0.1 then
        adelanto = -adelanto
    end
    -- Abrir hacia fuera con la aceleración lateral (v · w), solo la de fuera.
    local lateral = limitar(math.abs(v * w) / 4, 0, 1)
    -- Patinar: fase de la zancada (izquierda en `fase`, derecha media vuelta
    -- después); la fuerza sube con la velocidad, suave.
    local quiere = v > 0 and limitar((v - Piernas.patinarDesde) / (Piernas.patinarTope - Piernas.patinarDesde), 0, 1) or 0
    if self:getAjustes('piernasSoldado').patinador then
        -- Decide: patinar para coger velocidad o deslizar con los pies juntos.
        local quiereIr = self.datos.conduccion.vSuave or 0
        d.enModo = (d.enModo or 0) + dt
        local antes = d.modo
        -- Una zancada entera como poco antes de dejar de patinar.
        local zancada = 1 / (Piernas.ritmo[1] + Piernas.ritmo[2] * math.abs(v))
        if quiereIr <= Piernas.patinarDesde then
            d.modo = 'deslizar'
        elseif d.modo ~= 'patinar' then
            local perdio = v < quiereIr * Piernas.volverAPatinar and d.enModo > Piernas.deslizarMinimo
            if perdio or v < quiereIr * Piernas.perdidaMucha or v < Piernas.patinarDesde + 0.5 then
                d.modo = 'patinar'
            end
        elseif v >= quiereIr * Piernas.yaVa and d.enModo > zancada then
            d.modo = 'deslizar'
        end
        if d.modo ~= antes then
            d.enModo = 0
        end
        quiere = (d.modo == 'patinar' and v > Piernas.patinarDesde * 0.8) and 1 or 0
    end
    d.patinar = (d.patinar or 0) + (quiere - (d.patinar or 0)) * math.min(1, dt * 2)
    d.fase = ((d.fase or 0) + dt * 2 * math.pi * (Piernas.ritmo[1] + Piernas.ritmo[2] * math.abs(v))) % (2 * math.pi)
    d.vaiven = Piernas.vaiven * d.patinar * math.sin(d.fase)
    local pasos = math.max(1, math.ceil(dt / 0.005))
    local h = dt / pasos
    for _, s in ipairs({ 'Izq', 'Der' }) do
        local lado = s == 'Izq' and 1 or -1
        -- Girando a la izquierda (w > 0), la de fuera es la derecha.
        local fuera = (lado * w) < 0
        local objetivoX = -lado * adelanto
        local objetivoA = Piernas.abrirCorriendo * rapido + (fuera and Piernas.abrir * lateral or 0)
        -- La zancada: delante deslizando; detrás, empujando hacia fuera.
        local onda = math.sin(d.fase + (lado > 0 and 0 or math.pi))
        objetivoX = objetivoX + Piernas.zancada * d.patinar * onda
        objetivoA = objetivoA + Piernas.empuje * d.patinar * math.max(0, -onda)
        local p = d.pierna[s]
        for _ = 1, pasos do
            p.x, p.vx = muelle(p.x, p.vx, objetivoX, h)
            p.a, p.va = muelle(p.a, p.va, objetivoA, h)
        end
    end
end

function Piernas:onUpdate(dt)
    local d = self.datos.piernasSoldado
    if dt <= 0 then
        return
    end
    local v, w = self.velocidad, self.giro
    -- Aceleración hacia delante, media de un rato (si no, tiembla).
    local a = (v - d.antes) / dt
    d.antes = v
    d.acel = (d.acel or 0) + (a - (d.acel or 0)) * math.min(1, dt * 4)
    local C = self:getAjustes('conduccion')
    local corre = limitar((math.abs(v) - C.agacharDesde) / math.max(0.1, C.velocidadSinCarga - C.agacharDesde), 0, 1)
    local bajar = Piernas.bajarDePie + Piernas.agacharMaximo * corre
    local recto = 1 - limitar(math.abs(v) / Piernas.quietoHasta, 0, 1)
    d.recto = (d.recto or recto) + (recto - (d.recto or recto)) * math.min(1, dt * 2.5)
    bajar = bajar - (Piernas.bajarDePie + Piernas.subirQuieto) * d.recto
    local disparo = (self.posturaDisparo or 0) * recto
    d.disparo = (d.disparo or 0) + (disparo - (d.disparo or 0)) * math.min(1, dt * 4)
    bajar = bajar + Piernas.disparoBajar * d.disparo
    -- Con la física del robot pequeño (fisica.lua: choques y postura), la
    -- altura sale de su postura procedural: recto quieto, más bajo al correr
    -- o con carga, y las rodillas amortiguan al frenar, arrancar o chocar.
    local fisica = self.datos.fisica
    if fisica and fisica.agachado then
        bajar = Piernas.bajarDePie + Piernas.agacharMaximo * limitar((fisica.agachado + 0.6) / 1.6, 0, 1)
    end
    local cabeceo = limitar(math.atan(d.acel / G), -Piernas.cabeceoMaximo, Piernas.cabeceoMaximo)
    local inclinacion = limitar(math.atan(v * w / G), -Piernas.inclinacionMaxima, Piernas.inclinacionMaxima)
    local k = math.min(1, dt * Piernas.suave)
    d.bajar = d.bajar + (bajar - d.bajar) * k
    d.cabeceo = d.cabeceo + (cabeceo - d.cabeceo) * k
    d.inclinacion = d.inclinacion + (inclinacion - d.inclinacion) * k
    piernasHaciaDondeVa(self, d, dt)
    if os.getenv('PIERNAS_DEPURAR') and d.modo then
        d.relojModo = (d.relojModo or 0) + dt
        if d.relojModo > 0.25 then
            d.relojModo = 0
            print(string.format('PATINAR v=%.1f quiere=%.1f %s', v, self.datos.conduccion.vSuave or 0, d.modo))
        end
    elseif os.getenv('PIERNAS_DEPURAR') then
        d.relojDepurar = (d.relojDepurar or 0) + dt
        if d.relojDepurar > 0.25 then
            d.relojDepurar = 0
            print(string.format('PIERNAS v=%.1f patinar=%.2f izq=%.2f der=%.2f', v, d.patinar or 0, d.pierna.Izq.x, d.pierna.Der.x))
        end
    end
end

--- Ángulo que se dobla una pierna para que de la cadera al eje de la rueda
-- haya `h` m (0: de pie del todo, como en el modelo).
local function doblar(h)
    h = limitar(h, 0.3, 2 * Piernas.largo * 0.999)
    local x = math.sqrt(Piernas.largo ^ 2 - (h / 2) ^ 2)
    return math.asin(x / Piernas.largo) - alfaReposo
end

function Piernas:onPose()
    local d = self.datos.piernasSoldado
    -- El vaivén del patinador: el peso hacia la pierna que desliza delante
    -- (la izquierda va delante con sin(fase) > 0: baja ese lado).
    local phi, theta = d.inclinacion + (d.vaiven or 0), d.cabeceo
    local disparo = d.disparo or 0
    theta = theta + Piernas.disparoPecho * disparo - Piernas.retroceso * (self.retrocesoDisparo or 0) ^ 2
    -- La pelvis baja lo que se agacha y se inclina (hacia dentro de la curva
    -- y hacia delante al acelerar). Girar en x positivo sube la izquierda
    -- (+y): para bajar el lado de dentro de una curva a la izquierda (w > 0),
    -- el giro es -phi.
    local pelvis = self:getPieza('pelvis')
    pelvis:setDesplazamiento(0, 0, -d.bajar, 'altura')
    pelvis:setGiro('x', -phi, 'curva')
    pelvis:setGiro('y', theta, 'cabeceo')
    for _, s in ipairs({ 'Izq', 'Der' }) do
        local lado = s == 'Izq' and 1 or -1
        -- Con la pelvis inclinada, esta cadera queda más alta o más baja.
        local h = Piernas.alturaReposo - d.bajar - lado * Piernas.mitadCaderas * math.sin(phi)
        -- La rueda adelantada `p.x` m y abierta `p.a` rad: la pierna se
        -- inclina hacia allí y se estira para que la rueda siga en el suelo.
        local p = d.pierna[s]
        local px = p.x + Piernas.pieDelante[s] * (d.recto or 0) * (1 - disparo) + Piernas.disparoPies[s] * disparo
        local pa = p.a + Piernas.disparoAbrir * disparo
        local adelante = math.atan(px / h)
        local largo = h / (math.cos(adelante) * math.cos(pa))
        local delta = doblar(largo)
        local muslo = self:getPieza('muslo' .. s)
        -- El muslo deshace la inclinación de la pelvis (la pierna sigue en
        -- vertical: la rueda, en el suelo) y se dobla. Girar en y positivo
        -- lleva el pie atrás; en x positivo, a la izquierda (+y).
        muslo:setGiro('x', phi + lado * pa, 'curva')
        muslo:setGiro('y', -theta - adelante, 'cabeceo')
        muslo:setGiro('y', -delta, 'postura')
        self:getPieza('espinilla' .. s):setGiro('y', 2 * delta, 'postura')
    end
end

--- Patinador (ajuste `patinador`): lo que puede acelerar ahora (m/s²) por
-- encima de `patinarDesde`: patinando, el empujón de cada zancada; con los
-- pies juntos, el roce (negativo). nil: los motores, como siempre.
function Nucleo.Robot:getImpulso()
    local d = self.datos.piernasSoldado
    if not d or not d.modo or self.velocidad < Piernas.patinarDesde then
        return nil
    end
    if d.modo == 'patinar' then
        -- Empuja más en el centro de cada zancada (|sin| vale 2/π de media).
        return Piernas.impulso * math.pi / 2 * math.abs(math.sin(d.fase or 0)) * (d.patinar or 0)
    end
    return -Piernas.roce
end

Nucleo.registrarEspecializacion('piernasSoldado', Piernas)
return Piernas

-- Conducción del robot: base diferencial (dos ruedas motrices y dos locas),
-- como los robots móviles reales. Para ir a un punto: si no mira hacia él,
-- gira sobre sí mismo; si mira, avanza y corrige el rumbo; frena al llegar.
-- Las ruedas giran lo que han rodado y las locas se orientan hacia donde va
-- la base. Al acelerar y frenar el cuerpo se balancea un poco (inercia).
--
-- Órdenes que añade al robot:
--   robot:setIrA(x, y, rumboFinal)   va a (x, y); con rumboFinal, al llegar
--                                    gira hasta mirar hacia ahí
--   robot:setParar()                 frena y se queda
--   robot:setRetroceder(metros)      marcha atrás en recto, despacio
--   robot:getHaLlegado()             true si no tiene adónde ir
--   robot:getDestino()               x, y (nil si no va a ningún sitio)

---@class Conduccion : Robot
local Conduccion = {}
local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

-- Números de la conducción (m, m/s, rad/s).
Conduccion.velocidadMaxima = 3.0
-- Sin nada en las manos va con impulso: más deprisa, acelera más y se
-- agacha un poco (rodilla más doblada) con el cuerpo echado adelante.
Conduccion.velocidadSinCarga = 4.5
Conduccion.aceleracionSinCarga = 2.4
Conduccion.agacharDesde = 1.8 -- m/s: más despacio va derecho (al llegar, al frenar, al atracar)
Conduccion.agacharse = 1.0 -- cuánto se agacha a toda velocidad (0: nada)
Conduccion.velocidadAtras = 0.3
Conduccion.velocidadAtrasRuta = 0.5 -- marcha atrás hacia un punto (setIrAtras)
Conduccion.aceleracion = 1.4
Conduccion.giroMaximo = 0.9
Conduccion.aceleracionGiro = 1.3 -- rad/s²: el giro empieza y acaba suave
Conduccion.giroEnMarcha = 1.2 -- siguiendo una ruta, gira parado solo con más error que esto
Conduccion.parachoques = 0.4 -- m del centro: más cerca de algo, no avanza
Conduccion.anchoParachoques = 0.66 -- m de ancho del pasillo que mira el parachoques
Conduccion.anchoFrenar = 0.8 -- m de ancho del pasillo en el que frena si hay algo
Conduccion.capaParachoques = 0.25 -- capa del lidar (altura, m) del parachoques
Conduccion.suavizado = 0.35 -- s: la velocidad pedida cambia suave, sin saltos
Conduccion.radioRueda = 0.19
Conduccion.viaRuedas = 0.535 -- entre las dos ruedas motrices
Conduccion.giroEnSitio = 0.35 -- con más error de rumbo que esto, gira parado
Conduccion.llegada = 0.08
Conduccion.cerca = 0.35 -- dentro de esto no se gira para volver atrás
Conduccion.balanceo = 0.05 -- rad de cabeceo por m/s² de aceleración

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

function Conduccion:onLoad()
    local d = self.datos.conduccion
    d.ruedaIzq, d.ruedaDer = 0, 0
    d.locas = 0
    d.cabeceo = 0
    d.antes = 0
end

function Conduccion:onUpdate(dt)
    local d = self.datos.conduccion
    local C = self:getAjustes('conduccion')
    local v, w = 0, 0
    if d.retroceso then
        -- Marcha atrás en recto, despacio, hasta recorrer lo pedido.
        if d.retroceso > 0.01 then
            v = -math.min(C.velocidadAtras, math.sqrt(2 * C.aceleracion * d.retroceso) * 0.9)
            d.retroceso = d.retroceso + math.min(0, self.velocidad) * dt
        else
            d.retroceso = nil
        end
    elseif d.destino then
        local dx, dy = d.destino[1] - self.x, d.destino[2] - self.y
        local distancia = math.sqrt(dx * dx + dy * dy)
        -- Marcha atrás (setIrAtras): la cola mira al destino.
        local atras = d.destino.atras
        local error = angulo(math.atan2(dy, dx) - self.rumbo - (atras and math.pi or 0))
        -- Rodear lo que tiene delante (batalla/robots/especializaciones/obstaculos.lua).
        local desvio, frenarObstaculo = 0, nil
        if self.getDesvio and not atras then
            desvio, frenarObstaculo = self:getDesvio()
            error = angulo(error + desvio)
        end
        -- Cerca y con el punto detrás o de lado: se ha pasado un poco; vale
        -- (si no, se quedaría dando vueltas alrededor del punto).
        if distancia <= C.llegada or (distancia < C.cerca and math.abs(error) > C.giroEnSitio) then
            distancia = 0
        end
        -- Le faltan unos centímetros y el parachoques no le deja avanzar (la
        -- mesa o el rack delante): ya ha llegado. Antes se quedaba para
        -- siempre a 10 cm del punto sin darlo por bueno (el dueño, 26-nov:
        -- «ese pendejo lleva más de 10 minutos ahí»).
        if distancia > 0 and distancia < C.cerca and not atras and self.datos.lidar
            and self:getDistanciaDelante(C.anchoParachoques, C.capaParachoques) - C.parachoques <= 0.02 then
            distancia = 0
        end
        if distancia > 0 then
            w = math.max(-C.giroMaximo, math.min(C.giroMaximo, error * 1.2))
            -- Siguiendo una ruta (setIrA con `enMarcha`) gira andando; para
            -- llegar a un sitio exacto, primero se encara.
            local limite = d.destino.enMarcha and C.giroEnMarcha or C.giroEnSitio
            if math.abs(error) < limite then
                -- Frena a tiempo: v² = 2·a·d; más despacio si se pide (al
                -- atracar) o si tiene algo cerca delante.
                local libre = not (self.getLlevando and self:getLlevando())
                local prisa = d.prisa or 1
                local tope = (libre and C.velocidadSinCarga or C.velocidadMaxima) * prisa
                if atras then
                    tope = math.min(tope, C.velocidadAtrasRuta)
                end
                local acel = (libre and C.aceleracionSinCarga or C.aceleracion) * math.sqrt(prisa)
                v = math.min(d.velocidadMaxima or tope, math.sqrt(2 * acel * (d.destino.frenarEn or distancia)) * 0.9)
                if frenarObstaculo then
                    v = math.min(v, frenarObstaculo)
                end
                if self.datos.lidar and not d.velocidadMaxima and not atras then
                    v = math.min(v, math.max(0.4, 0.4 + 0.8 * (self:getDistanciaDelante(C.anchoFrenar, C.capaParachoques) - C.parachoques - 0.4)))
                end
                -- En las curvas, más despacio (suave con el error).
                v = v * math.max(0.2, math.cos(math.min(math.abs(error), 1.4))) ^ 2
                if atras then
                    v = -v
                end
            end
        elseif d.destino[3] then
            -- Se encara frenando el giro a tiempo (ω² = 2·α·ángulo, como al
            -- avanzar): con ω = error·1,2 y la aceleración de giro limitada se
            -- pasaba, volvía y no entraba nunca en el margen; se quedaba
            -- meneándose en su sitio sin acabar (el dueño, 26-nov).
            local error = angulo(d.destino[3] - self.rumbo)
            local quieto = math.abs(self.giro) < 0.05
            if math.abs(error) > 0.02 and not (math.abs(error) < 0.05 and quieto) then
                local frenar = math.sqrt(2 * C.aceleracionGiro * math.abs(error)) * 0.8
                local signo = error > 0 and 1 or -1
                w = signo * math.min(C.giroMaximo, frenar, math.abs(error) * 3)
            else
                d.destino = nil
            end
        else
            d.destino = nil
        end
    end
    -- Lo pedido, suavizado (el lidar y la ruta lo cambian a saltos), y
    -- acelera hacia ello sin pasarse de la aceleración.
    d.vSuave = (d.vSuave or 0) + (v - (d.vSuave or 0)) * math.min(1, dt / C.suavizado)
    if v == 0 or d.retroceso then
        d.vSuave = v
    end
    local cargado = self.getLlevando and self:getLlevando()
    local paso = (cargado and C.aceleracion or C.aceleracionSinCarga) * math.sqrt(d.prisa or 1) * dt
    -- Parachoques: con algo a menos de 40 cm delante de la base (capa baja
    -- del lidar), no avanza, vaya a donde vaya.
    if self.datos.lidar and d.vSuave > 0 then
        local libre = self:getDistanciaDelante(C.anchoParachoques, C.capaParachoques) - C.parachoques
        d.vSuave = math.min(d.vSuave, math.max(0, libre * 2))
        if libre <= 0 then
            paso = C.aceleracion * 3 * dt
        end
    end
    -- Patinador (piernasSoldado.lua): por encima de cierta velocidad solo le
    -- empujan sus zancadas o, con los pies juntos, se desliza y el roce lo
    -- frena; para frenar más, los motores.
    local impulso = self.getImpulso and self:getImpulso()
    if impulso and d.vSuave > self.velocidad then
        self.velocidad = math.min(d.vSuave, self.velocidad + impulso * dt)
    else
        self.velocidad = self.velocidad + math.max(-paso, math.min(paso, d.vSuave - self.velocidad))
    end
    if d.prisa and d.maximaConPrisa then
        d.maximaConPrisa = math.max(d.maximaConPrisa, math.abs(self.velocidad))
    end
    d.ultimoV, d.ultimoW = v, w -- (para depurar atascos)
    local pasoGiro = C.aceleracionGiro * dt
    self.giro = self.giro + math.max(-pasoGiro, math.min(pasoGiro, w - self.giro))
    self.rumbo = angulo(self.rumbo + self.giro * dt)
    self.x = self.x + math.cos(self.rumbo) * self.velocidad * dt
    self.y = self.y + math.sin(self.rumbo) * self.velocidad * dt
    -- Ruedas: lo que ha rodado cada una (la izquierda va por dentro al girar
    -- a la izquierda).
    local mitad = C.viaRuedas / 2
    d.ruedaIzq = d.ruedaIzq + (self.velocidad - self.giro * mitad) / C.radioRueda * dt
    d.ruedaDer = d.ruedaDer + (self.velocidad + self.giro * mitad) / C.radioRueda * dt
    -- Locas: miran hacia donde se mueve su punto (giro en sitio: de lado).
    if math.abs(self.velocidad) > 0.02 or math.abs(self.giro) > 0.05 then
        local objetivo = math.atan2(self.giro * 0.22, math.max(0.02, self.velocidad))
        d.locas = d.locas + (objetivo - d.locas) * math.min(1, dt * 4)
    end
    -- Inercia: el cuerpo cabecea hacia atrás al acelerar y adelante al frenar
    -- (con la aceleración media de un rato, no la de cada cuadro: si no,
    -- tiembla).
    local aceleracion = dt > 0 and (self.velocidad - d.antes) / dt or 0
    d.antes = self.velocidad
    d.aceleracionMedia = (d.aceleracionMedia or 0) + (aceleracion - (d.aceleracionMedia or 0)) * math.min(1, dt * 3)
    local objetivo = math.max(-0.04, math.min(0.04, -d.aceleracionMedia * C.balanceo))
    d.cabeceo = d.cabeceo + (objetivo - d.cabeceo) * math.min(1, dt * 2.5)
    -- Agachado solo corriendo de verdad; en cuanto empieza a frenar (lo
    -- pedido es menos de lo que lleva: va llegando) se va poniendo derecho.
    local agachar = 0
    local corre = math.min(self.velocidad, d.vSuave or 0)
    if not (self.getLlevando and self:getLlevando()) and corre > C.agacharDesde then
        agachar = C.agacharse * math.min(1, (corre - C.agacharDesde) / (C.velocidadSinCarga - C.agacharDesde))
    end
    d.agachado = (d.agachado or 0) + (agachar - (d.agachado or 0)) * math.min(1, dt * 3)
end

function Conduccion:onPose()
    local d = self.datos.conduccion
    -- El robot grande no tiene ruedas ni rodillas (orugas.lua lo suyo).
    if not self:getTienePieza('ruedaIzq') then
        return
    end
    self:getPieza('ruedaIzq'):setGiro('y', d.ruedaIzq)
    self:getPieza('ruedaDer'):setGiro('y', d.ruedaDer)
    -- El soldado tiene dos piernas: su postura la pone piernasSoldado.lua.
    if not self:getTienePieza('espinilla') then
        return
    end
    self:getPieza('espinilla'):setGiro('y', d.cabeceo, 'inercia')
    -- Agachado con impulso al correr sin carga: espinilla atrás, muslo
    -- adelante (la rodilla se dobla y baja unos 10 cm) y el torso un poco
    -- menos, así queda echado adelante.
    local a = d.agachado or 0
    self:getPieza('espinilla'):setGiro('y', -0.28 * a, 'agachado')
    self:getPieza('muslo'):setGiro('y', 0.56 * a, 'agachado')
    self:getPieza('torso'):setGiro('y', -0.08 * a, 'agachado')
end

-- Órdenes ------------------------------------------------------------------------

--- Va a (x, y) del almacén; con `rumboFinal`, al llegar gira hasta él.
-- `enMarcha`: es un punto de paso de una ruta (gira sin pararse).
--- Cuánto va agachado (0 derecho .. 1 corriendo a tope sin carga).
function Robot:getAgachado()
    return self.datos.conduccion.agachado or 0
end

function Robot:setIrA(x, y, rumboFinal, enMarcha, frenarEn)
    self.datos.conduccion.destino = { x, y, rumboFinal, enMarcha = enMarcha, frenarEn = frenarEn }
end

--- Va marcha atrás (la cola por delante) a (x, y); con `rumboFinal`, al
-- llegar gira hasta él. Para salir de un sitio con la carga sin girar.
function Robot:setIrAtras(x, y, rumboFinal)
    self.datos.conduccion.destino = { x, y, rumboFinal, atras = true }
end

--- Frena y se queda donde está.
function Robot:setParar()
    self.datos.conduccion.destino = nil
    self.datos.conduccion.retroceso = nil
end

--- Con prisa: `factor` veces más rápido en los trayectos (y acelera más);
-- al atracar, igual de despacio. nil: lo normal.
function Robot:setPrisa(factor)
    self.datos.conduccion.prisa = factor
end

--- Velocidad máxima (m/s) hasta que se cambie; nil: la normal.
function Robot:setVelocidadMaxima(v)
    self.datos.conduccion.velocidadMaxima = v
end

--- Marcha atrás en recto `metros` (despacio, 0,3 m/s).
function Robot:setRetroceder(metros)
    self.datos.conduccion.destino = nil
    self.datos.conduccion.retroceso = metros
end

--- `true` si no tiene adónde ir (y casi parado).
function Robot:getHaLlegado()
    local d = self.datos.conduccion
    return d.destino == nil and d.retroceso == nil and math.abs(self.velocidad) < 0.02
end

--- x, y del destino (nil si no va a ningún sitio).
function Robot:getDestino()
    local d = self.datos.conduccion.destino
    if d then
        return d[1], d[2]
    end
end

Nucleo.registrarEspecializacion('conduccion', Conduccion)
return Conduccion

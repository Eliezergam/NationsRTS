-- Navegación con el mapa que aprende el lidar: calcula la ruta con A* por lo
-- que ha visto (lo que no conoce cuenta como libre), la sigue mirando un
-- punto 0,8 m por delante en la ruta y, cada vez que el lidar descubre algo
-- que la corta, la vuelve a calcular. Si tiene algo justo delante que no
-- estaba en el mapa, frena.
--
-- Órdenes que añade al robot:
--   robot:setNavegarA(x, y, rumboFinal)  va hasta ahí esquivando lo que vea
--   robot:getNavegando()                 true mientras va
--   robot:getRuta()                      los puntos que le quedan { {x, y}, ... }
--   robot:getReplanes()                  cuántas veces ha cambiado de ruta
--   robot:setRetroceder(metros)          marcha atrás en recto (para salir
--                                        de debajo de una mesa); ver
--                                        conduccion.lua

---@class Navegacion : Robot
local Navegacion = {}
local Robot = GestorRobots.Robot

Navegacion.adelantoCerca = 0.6 -- m: el punto de la ruta tras taparse (pasa las esquinas por la ruta)
Navegacion.tiempoDeCerca = 6 -- s que sigue la ruta de cerca
Navegacion.antesDelHueco = 1.6 -- m antes y después de un hueco en los que va en recto
Navegacion.adelanto = 2.2 -- m: el punto de la ruta al que apunta (lejos: no frena entre puntos)
Navegacion.revisar = 0.25 -- s entre comprobaciones de la ruta
Navegacion.frenoDelante = 0.45 -- m libres delante (desde el centro) para seguir
Navegacion.atascoTiempo = 4 -- s sin avanzar...
Navegacion.atascoDistancia = 0.15 -- ...más de esto: está atascado
Navegacion.atascosMaximos = 2 -- con el mismo destino, y lo deja
Navegacion.tapadosMaximos = 4 -- cuántas veces puede quedarse tapado delante
    -- con el mismo destino antes de dejarlo (si no, empuja contra la pared
    -- horas y horas: el dueño, 22-nov)

function Navegacion:onLoad()
    local d = self.datos.navegacion
    d.reloj = 0
    d.replanes = 0
end

local libreHacia
local apartarse

-- Puertas y portones que ha leído con los ojos (sus zonas de información):
-- si la ruta cruza uno, la hace pasar por el centro del hueco, en recto, con
-- un punto antes y otro después (así no roza los marcos). Si no cabe,
-- lo dice.
local function ajustarPuertas(self)
    local d = self.datos.navegacion
    if not d.ruta or not self.getSabe then
        return
    end
    for info in pairs(self:getSabe()) do
        if (info.tipo == 'porton' or info.tipo == 'puerta') and info.abierto then
            local cx, cy, nx, ny = info.centro[1], info.centro[2], info.normal[1], info.normal[2]
            local px, py = self.x, self.y
            for k, q in ipairs(d.ruta) do
                if q.puerta == info then
                    break
                end
                local a = (px - cx) * nx + (py - cy) * ny
                local b = (q[1] - cx) * nx + (q[2] - cy) * ny
                -- También cuando el punto cae justo en el plano del portón
                -- (a o b son cero): si no, el cruce no se ve y el robot va
                -- contra la pared de al lado (el dueño, 22-nov).
                if a * b <= 0 and a ~= b then
                    -- Dónde corta la pared: ¿dentro del hueco (con margen)?
                    local f = a / (a - b)
                    local ix, iy = px + (q[1] - px) * f, py + (q[2] - py) * f
                    local lateral = math.abs((ix - cx) * -ny + (iy - cy) * nx)
                    if lateral < info.ancho / 2 + 3 then
                        local cabe, sobra = self:getCabePor(info)
                        if not cabe then
                            print(string.format('ROBOT no quepo por el %s (me faltan %.1f m)', info.nombre, -sobra))
                        else
                            local s = b > 0 and 1 or -1
                            local antes = { cx - nx * s * Navegacion.antesDelHueco, cy - ny * s * Navegacion.antesDelHueco, puerta = info }
                            local despues = { cx + nx * s * Navegacion.antesDelHueco, cy + ny * s * Navegacion.antesDelHueco, puerta = info }
                            -- Los puntos de la ruta que se arrimaban a la
                            -- pared (y noaban por el hueco) sobran: el rodeo
                            -- los sustituye. Si no se quitan, el robot va
                            -- contra la pared de al lado del portón y se queda
                            -- allí empujando (el dueño, 22-nov: «atascado en el
                            -- mismo punto»).
                            local j = k
                            for m = k, 1, -1 do
                                local r = d.ruta[m]
                                local lat = math.abs((r[1] - cx) * -ny + (r[2] - cy) * nx)
                                local dist = math.abs((r[1] - cx) * nx + (r[2] - cy) * ny)
                                if lat > info.ancho / 2 and dist < 2 then
                                    j = m
                                else
                                    break
                                end
                            end
                            for m = k, j, -1 do
                                table.remove(d.ruta, m)
                            end
                            table.insert(d.ruta, j, despues)
                            table.insert(d.ruta, j, antes)
                            -- Se dice una vez cada tanto por cruce (la ruta
                            -- se replanea a menudo y callaba el paso).
                            local ahora = d.tiempo or 0
                            if not d.cruces then
                                d.cruces = {}
                            end
                            if ahora - (d.cruces[info] or -99) > 10 then
                                d.cruces[info] = ahora
                                print(string.format('ROBOT cruzo el %s por el centro (%.1f m a cada marco)', info.nombre, sobra))
                            end
                        end
                        break
                    end
                end
                px, py = q[1], q[2]
            end
        end
    end
end

local function planear(self)
    local d = self.datos.navegacion
    local ruta = self:getMapa():getRuta(self.x, self.y, d.destino[1], d.destino[2])
    d.ruta = ruta
    ajustarPuertas(self)
    d.cambiosMapa = self:getMapa().cambios
    d.replanes = d.replanes + 1
    if not ruta then
        d.sinCamino = true
    else
        d.sinCamino = false
    end
end

-- El punto de la ruta `adelanto` m por delante del robot.
local function zanahoria(self, ruta, adelanto)
    -- Quita los puntos ya alcanzados o ya dejados atrás (al apartarse de la
    -- ruta puede pasar un punto a casi un metro: si no se quitara, volvería
    -- a por él y daría vueltas).
    while #ruta > 1 do
        local p, q = ruta[1], ruta[2]
        local pasado = (self.x - p[1]) * (q[1] - p[1]) + (self.y - p[2]) * (q[2] - p[2]) > 0
        if pasado or (p[1] - self.x) ^ 2 + (p[2] - self.y) ^ 2 < 1.0 ^ 2 then
            table.remove(ruta, 1)
        else
            break
        end
    end
    local px, py = self.x, self.y
    local queda = adelanto or Navegacion.adelanto
    for k, p in ipairs(ruta) do
        local tramo = math.sqrt((p[1] - px) ^ 2 + (p[2] - py) ^ 2)
        if tramo >= queda or k == #ruta then
            local t = math.min(1, queda / math.max(tramo, 1e-6))
            return px + (p[1] - px) * t, py + (p[2] - py) * t, k == #ruta and tramo <= queda
        end
        queda = queda - tramo
        px, py = p[1], p[2]
    end
    return ruta[#ruta][1], ruta[#ruta][2], true
end

function Navegacion:onUpdate(dt)
    local d = self.datos.navegacion
    if not d.destino then
        return
    end
    d.tiempo = (d.tiempo or 0) + dt
    local mapa = self:getMapa()
    -- ¿Atascado? (sin avanzar un rato): marcha atrás y recalcula; si le
    -- vuelve a pasar con el mismo destino, lo deja (getSinCamino).
    if d.saliendo then
        if self:getHaLlegado() then
            d.saliendo = false
            planear(self)
        end
        return
    end
    d.atasco = d.atasco or { x = self.x, y = self.y, r = self.rumbo, t = 0 }
    d.atasco.t = d.atasco.t + dt
    -- Girar en el sitio (al llegar, hacia su rumbo final) también es avanzar.
    local giro = math.abs((self.rumbo - d.atasco.r + math.pi) % (2 * math.pi) - math.pi)
    local cerca = math.sqrt((d.destino[1] - self.x) ^ 2 + (d.destino[2] - self.y) ^ 2) < 1.0
    if (self.x - d.atasco.x) ^ 2 + (self.y - d.atasco.y) ^ 2 > Navegacion.atascoDistancia ^ 2 then
        d.atasco = { x = self.x, y = self.y, r = self.rumbo, t = 0 }
        d.giroTotal = 0
    else
        -- No avanza. Girar en el sitio no cuenta como avanzar (antes sí, y
        -- se quedaba horas girando delante del mismo punto: el dueño, 22-nov);
        -- pero al llegar al destino solo se encara, y eso sí vale.
        d.giroTotal = (d.giroTotal or 0) + giro
        if giro > 0.3 then
            d.atasco = { x = self.x, y = self.y, r = self.rumbo, t = 0 }
        else
            d.atasco.t = d.atasco.t + dt
        end
        if not cerca and (d.atasco.t > Navegacion.atascoTiempo or d.giroTotal > 6) then
            d.atasco = nil
            d.giroTotal = 0
            d.atascos = (d.atascos or 0) + 1
            print(string.format('ROBOT atascado en %.1f, %.1f (vez %d)', self.x, self.y, d.atascos))
            if os.getenv('ROBOT_DEPURAR') then
                local puntos = {}
                for k, p in ipairs(d.ruta or {}) do
                    if k > 5 then break end
                    puntos[#puntos + 1] = string.format('%.1f,%.1f', p[1], p[2])
                end
                print(string.format('DEPURAR atascado destino=%.1f,%.1f rumbo=%.2f ruta=[%s]',
                    d.destino[1], d.destino[2], self.rumbo, table.concat(puntos, ' ')))
            end
            if d.atascos >= Navegacion.atascosMaximos then
                d.destino, d.ruta = nil, nil
                d.sinCamino = true
                self:setParar()
                return
            end
            self:setRetroceder(0.5)
            d.saliendo = true
            return
        end
    end
    d.reloj = d.reloj + dt
    if d.reloj >= Navegacion.revisar then
        d.reloj = 0
        -- ¿El mapa ha cambiado y algún tramo de la ruta ya no está libre?
        if mapa.cambios ~= d.cambiosMapa and d.ruta then
            local px, py = self.x, self.y
            for _, p in ipairs(d.ruta) do
                if not mapa:getTramoLibre(px, py, p[1], p[2]) and (px ~= self.x or not mapa:getBloqueado(self.x, self.y)) then
                    planear(self)
                    break
                end
                px, py = p[1], p[2]
            end
            d.cambiosMapa = mapa.cambios
        end
        if not d.ruta then
            planear(self)
        end
    end
    if not d.ruta then
        self:setParar()
        return
    end
    d.apartando, d.apartandoDe = 0, nil
    -- Tras taparse, sigue la ruta de cerca un rato (con el punto lejano
    -- recortaba las esquinas de los portones y daba con la jamba).
    local corto = d.rutaDeCerca and d.rutaDeCerca > 0
    if corto then
        d.rutaDeCerca = d.rutaDeCerca - dt
    end
    -- Los ojos acaban de leer una puerta o un portón: revisa la ruta.
    local mirada = self.datos.mirada
    if mirada and mirada.infoNueva then
        mirada.infoNueva = false
        ajustarPuertas(self)
    end
    local x, y, final = zanahoria(self, d.ruta, corto and Navegacion.adelantoCerca or nil)
    if final then
        -- El último tramo se manda una sola vez: si se repitiera cada cuadro,
        -- la conducción nunca daría el viaje por acabado.
        if not d.finalEnviado then
            d.finalEnviado = true
            self:setIrA(d.destino[1], d.destino[2], d.destino[3])
        elseif self:getHaLlegado() then
            d.destino, d.ruta = nil, nil
        end
    else
        d.finalEnviado = false
        -- Esquiva con los rayos: de las direcciones parecidas a la que lleva
        -- la ruta, la más parecida que tenga sitio para el robot.
        local deseada = math.atan2(y - self.y, x - self.x)
        -- Algo cerca a un lado: se aparta hacia el otro (el punto al que va
        -- se desplaza de lado). Si hay cosas a los dos lados, no se aparta
        -- (pasa por en medio si cabe; si no cabe, lo de abajo busca otra
        -- dirección o recalcula la ruta).
        local desvio = apartarse(self, d, deseada, dt)
        if desvio ~= 0 then
            local ax, ay = x - math.sin(deseada) * desvio, y + math.cos(deseada) * desvio
            local apartada = math.atan2(ay - self.y, ax - self.x)
            -- Solo si por ahí hay sitio de verdad; si no, vuelve a la ruta.
            if libreHacia(self, apartada) >= 2.0 then
                deseada = apartada
            else
                d.desvio = 0
            end
        end
        local rumbo, libre = self:getDireccionLibre(deseada, Navegacion.espacioLibre)
        d.esquivando = rumbo and math.abs(((rumbo - deseada) + math.pi) % (2 * math.pi) - math.pi) > 0.05
        if rumbo then
            d.tapado = 0
            local paso = math.min(Navegacion.adelanto, libre - 0.3)
            -- Lo que le queda de ruta: frena para el final, no para el punto
            -- cercano al que apunta (si no, nunca pasaba de unos 2,5 m/s).
            local restante, px, py = 0, self.x, self.y
            for _, p in ipairs(d.ruta) do
                restante = restante + math.sqrt((p[1] - px) ^ 2 + (p[2] - py) ^ 2)
                px, py = p[1], p[2]
            end
            self:setIrA(self.x + math.cos(rumbo) * paso, self.y + math.sin(rumbo) * paso, nil, true, restante)
        else
            -- Tapado delante: no gira sobre sí mismo. Se para, recalcula la
            -- ruta y, si sigue tapado un rato, retrocede un poco en recto.
            self:setParar()
            d.tapado = (d.tapado or 0) + dt
            if d.reloj == 0 then
                planear(self)
            end
            if d.tapado > 2 and libreHacia(self, self.rumbo + math.pi) > 0.8 then
                print(string.format('ROBOT tapado delante en %.1f, %.1f: retrocede un poco', self.x, self.y))
                if os.getenv('ROBOT_DEPURAR') then
                    local puntos = {}
                    for k, p in ipairs(d.ruta or {}) do
                        if k > 5 then break end
                        puntos[#puntos + 1] = string.format('%.1f,%.1f', p[1], p[2])
                    end
                    print(string.format('DEPURAR tapado destino=%.1f,%.1f rumbo=%.2f ruta=[%s]',
                        d.destino[1], d.destino[2], self.rumbo, table.concat(puntos, ' ')))
                end
                d.tapado = 0
                d.rutaDeCerca = Navegacion.tiempoDeCerca
                planear(self)
                self:setRetroceder(0.4)
                d.saliendo = true
                -- Si se atasca muchas veces con el mismo destino, lo deja:
                -- si no, se queda horas empujando contra la pared (el dueño,
                -- 22-nov: «lleva horas atascado en el mismo punto»).
                d.tapados = (d.tapados or 0) + 1
                if d.tapados >= Navegacion.tapadosMaximos then
                    print(string.format('ROBOT no puedo llegar a %.1f, %.1f: lo dejo', d.destino[1], d.destino[2]))
                    d.destino, d.ruta = nil, nil
                    d.sinCamino = true
                    self:setParar()
                    return
                end
            end
        end
    end
end

-- Esquiva local -------------------------------------------------------------------

Navegacion.cercaLado = 1.6 -- m: algo más cerca que esto a un lado, se aparta

-- Lo más cerca que tiene algo a la izquierda y a la derecha (distancia de
-- lado, según los rayos del último barrido, de 25° a 135° de su rumbo), y
-- qué es.
local function cercaDeLado(self)
    local izq, der = math.huge, math.huge
    local tipoIzq, tipoDer
    for _, r in ipairs(self:getRayos()) do
        if r.choca and r.distancia < Navegacion.cercaLado / math.sin(math.rad(25)) then
            local a = (r.angulo - self.rumbo + math.pi) % (2 * math.pi) - math.pi
            local lado = math.abs(math.sin(a)) * r.distancia
            if lado < Navegacion.cercaLado then
                if a > math.rad(25) and a < math.rad(135) and lado < izq then
                    izq, tipoIzq = lado, r.tipo
                elseif a < -math.rad(25) and a > -math.rad(135) and lado < der then
                    der, tipoDer = lado, r.tipo
                end
            end
        end
    end
    return izq, der, tipoIzq, tipoDer
end

Navegacion.margenLado = 0.4 -- m de más que se aparta, para que se note
Navegacion.desvioMaximo = 0.9 -- m: lo más que se aparta de la ruta
Navegacion.desvioRapidez = 0.8 -- m/s al apartarse
Navegacion.desvioVuelta = 0.25 -- m/s al volver a la ruta (despacio: sin vaivén)

-- Cuánto se aparta de la ruta, de lado (m; positivo: a la izquierda). Va
-- deprisa hacia lo que le falta para tener `cercaLado` (+ margen) libres y
-- vuelve despacio cuando ya ha pasado.
function apartarse(self, d, deseada, dt)
    local objetivo = 0
    d.apartandoDe = nil
    local error = math.abs((deseada - self.rumbo + math.pi) % (2 * math.pi) - math.pi)
    -- Solo andando de verdad y ya encarado: mientras gira o arranca (al
    -- salir de la mesa, por ejemplo) apartarse lo liaría.
    if (self.velocidad or 0) >= 0.5 and error <= 0.6 then
        local izq, der, tipoIzq, tipoDer = cercaDeLado(self)
        local c = Navegacion.cercaLado
        if izq < c and der >= c then
            objetivo = -(c + Navegacion.margenLado - izq)
            d.apartandoDe = 'izq ' .. tostring(tipoIzq)
        elseif der < c and izq >= c then
            objetivo = c + Navegacion.margenLado - der
            d.apartandoDe = 'der ' .. tostring(tipoDer)
        end
        objetivo = math.max(-Navegacion.desvioMaximo, math.min(Navegacion.desvioMaximo, objetivo))
    end
    local actual = d.desvio or 0
    -- Si sigue teniendo el objeto al lado, mantiene lo apartado.
    if objetivo ~= 0 and objetivo * actual > 0 and math.abs(objetivo) < math.abs(actual) then
        objetivo = actual
    end
    local rapidez = math.abs(objetivo) > math.abs(actual) and Navegacion.desvioRapidez or Navegacion.desvioVuelta
    local paso = rapidez * (dt or 0)
    actual = actual + math.max(-paso, math.min(paso, objetivo - actual))
    d.desvio = actual
    d.apartando = actual
    return actual
end

--- De qué se aparta ('izq tipo' / 'der tipo') o nil.
function Robot:getApartandoDe()
    return self.datos.navegacion.apartandoDe
end

--- Cuánto se está apartando de algo que tiene a un lado (rad; 0 = nada).
function Robot:getApartando()
    return self.datos.navegacion.apartando or 0
end

Navegacion.desviacionMaxima = 3 -- ×10°: lo más que tuerce para esquivar (sin giros bruscos)
Navegacion.espacioLibre = 0.9 -- m libres que pide una dirección para ir por ella
Navegacion.anchoPaso = 0.72 -- m: lo que ocupa el robot de lado (con margen)

-- Cuánto puede avanzar en la dirección `a` sin que nada de los rayos del
-- último barrido le toque (un pasillo del ancho del robot).
function libreHacia(self, a)
    local mejor = 12
    local mitad = Navegacion.anchoPaso / 2
    for _, r in ipairs(self:getRayos()) do
        if r.choca then
            local da = r.angulo - a
            local adelante = math.cos(da) * r.distancia
            local lado = math.abs(math.sin(da) * r.distancia)
            if adelante > 0 and lado < mitad and adelante < mejor then
                mejor = adelante
            end
        end
    end
    return mejor
end

--- La dirección más parecida a `deseada` (de 10° en 10°, hasta 30° a cada
-- lado) con al menos `minimo` m libres según los rayos, y cuánto hay libre;
-- nil si ninguna.
function Robot:getDireccionLibre(deseada, minimo)
    for k = 0, Navegacion.desviacionMaxima do
        for _, s in ipairs(k == 0 and { 1 } or { 1, -1 }) do
            local a = deseada + s * math.rad(10 * k)
            local libre = libreHacia(self, a)
            if libre >= minimo then
                return a, libre
            end
        end
    end
end

--- La dirección con más sitio libre alrededor (de 15° en 15°).
function Robot:getDireccionMasAbierta()
    local mejor, mejorLibre = self.rumbo, -1
    for k = 0, 23 do
        local a = self.rumbo + math.rad(15 * k)
        local libre = libreHacia(self, a)
        if libre > mejorLibre then
            mejor, mejorLibre = a, libre
        end
    end
    return mejor
end

--- `true` si ahora mismo se está desviando de la ruta para esquivar algo.
function Robot:getEsquivando()
    return self.datos.navegacion.esquivando == true
end

--- Va a (x, y) esquivando lo que ve; con `rumboFinal`, al llegar gira hasta él.
function Robot:setNavegarA(x, y, rumboFinal)
    local d = self.datos.navegacion
    -- El mismo destino otra vez no borra la cuenta de atascos.
    local mismo = d.destino and (d.destino[1] - x) ^ 2 + (d.destino[2] - y) ^ 2 < 0.5 ^ 2
    d.destino = { x, y, rumboFinal }
    d.ruta = nil
    if not mismo then
        d.atasco, d.atascos, d.saliendo = nil, 0, false
        d.tapados = 0
    end
    d.desvio = 0
    d.finalEnviado = false
    d.reloj = Navegacion.revisar
    planear(self)
end

--- `true` mientras va a algún sitio.
function Robot:getNavegando()
    local d = self.datos.navegacion
    if not d then
        -- Sin navegación (el soldado de práctica): «navega» si va a algún sitio.
        return self.datos.conduccion ~= nil and self.datos.conduccion.destino ~= nil
    end
    return d.destino ~= nil
end

--- Los puntos de la ruta que le quedan.
function Robot:getRuta()
    local d = self.datos.navegacion
    return d and d.ruta or {}
end

function Robot:getReplanes()
    local d = self.datos.navegacion
    return d and d.replanes or 0
end

--- `true` si la última vez no encontró camino.
function Robot:getSinCamino()
    return self.datos.navegacion.sinCamino == true
end

GestorRobots.registrarEspecializacion('navegacion', Navegacion)
return Navegacion

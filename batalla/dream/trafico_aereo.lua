-- Los aviones del mapa en la escena 3D de un sitio (diseno/aviones-de-transporte.md,
-- paso 5; el dueño, 26-nov: «tienen que verse todos» y «que no se pongan uno
-- encima del otro en la pista»). La escena de una mina o una ciudad mira los
-- vuelos de la simulación (mundo/simulacion/aviones.lua) y enseña cada avión
-- que le toca al sitio, a la hora del mapa:
--
--   * aparcado    los aviones de un vuelo que espera en el sitio: cada uno en
--                 su plaza de la plataforma (batalla/dream/plataforma_avion.lua),
--                 con la rampa abierta;
--   * llegada     los de un vuelo que viene: el primero aparece en la final
--                 (fuera de la vista) cuando en el mapa le faltan `anticipo`
--                 segundos; los demás, uno detrás de otro cuando el anterior
--                 ha dejado la pista. Cada uno rueda hasta su plaza;
--   * salida      cuando su vuelo se va en el mapa: uno cada vez, lo empujan
--                 fuera de la plaza, rueda hasta la cabecera, espera a que la
--                 pista esté libre y despega.
--
-- Como el control de un aeródromo: la pista es de un avión cada vez. Si no
-- quedan plazas, los que faltan esperan (no aparecen). Solo lee la
-- simulación; no cambia nada.

local PlataformaAvion = require('batalla.dream.plataforma_avion')

local Trafico = {}
Trafico.__index = Trafico

Trafico.radio = 30 -- px del mapa: un vuelo a menos de esto del sitio está en él
Trafico.anticipo = 45 -- s reales que tarda el avión 3D desde que aparece hasta que toca
Trafico.cadaCuanto = 0.5 -- s entre dos miradas a la simulación
Trafico.separacion = 20 -- s como poco entre dos que aparecen para aterrizar

--- `escena` (EscenaDream) con `combate.sitio.mapaX/mapaY` (el sitio en el
-- mapa) y `crearAvion(modo, plaza)` ('aparcado' o 'llegada', la plaza a lo
-- largo de la plataforma) que pone un avión 3D y lo devuelve.
function Trafico.nuevo(escena, crearAvion)
    local sitio = escena.combate and escena.combate.sitio
    if not (sitio and sitio.mapaX and escena.mundo and escena.mundo.sim) then
        return nil
    end
    return setmetatable({
        escena = escena,
        sim = escena.mundo.sim,
        x = sitio.mapaX,
        y = sitio.mapaY,
        crearAvion = crearAvion,
        reloj = 0,
        tiempo = 0,
        aviones = {}, -- { robot, avion (id), vuelo (id), plaza, sale }
        cola = {}, -- { avion, vuelo } que esperan para aparecer en la final
        plazas = PlataformaAvion.plazas(),
    }, Trafico)
end

local function cerca(self, x, y)
    return x and (x - self.x) ^ 2 + (y - self.y) ^ 2 < Trafico.radio ^ 2
end

--- A dónde va el vuelo `v` ahora y a qué velocidad (px del mapa por día).
local function destino(self, v)
    local reglas = self.sim.Aviones.reglas
    if v.fase == 'llevar' then
        local g = self.sim.estado.grupos[v.grupo]
        if not g then
            return nil
        end
        return g.destinoX, g.destinoY, reglas.velocidad / (2 * v.viajes - 1), g.largo - g.recorrido
    elseif v.fase == 'buscar' or v.fase == 'aparcar' or v.fase == 'volver' then
        return v.dx, v.dy, reglas.velocidad, v.largo - v.recorrido
    end
    return nil
end

--- ¿El vuelo `v` es de este sitio (espera aquí o viene hacia aquí)?
local function deAqui(self, v)
    if not v then
        return false
    end
    if v.fase == 'esperar' then
        return cerca(self, v.x, v.y)
    end
    local dx, dy = destino(self, v)
    return dx ~= nil and cerca(self, dx, dy)
end

--- Días de juego por segundo real, medidos.
function Trafico:ritmo(dt)
    local ahora = self.sim:ahora()
    if self.antes and dt > 0 then
        local medido = (ahora - self.antes) / dt
        self.medido = self.medido and (self.medido * 0.8 + medido * 0.2) or medido
    end
    self.antes = ahora
    return self.medido or 0
end

--- Una plaza libre (la más al este primero: los que llegan no cruzan por
-- delante del punto de espera de la cabecera oeste), o nil.
function Trafico:plazaLibre()
    local ocupadas = {}
    for _, a in ipairs(self.aviones) do
        ocupadas[a.plaza] = true
    end
    for k = #self.plazas, 1, -1 do
        if not ocupadas[self.plazas[k]] then
            return self.plazas[k]
        end
    end
    return nil
end

--- ¿Se ve ya (o espera para verse) el avión `id`?
function Trafico:conocido(id)
    for _, a in ipairs(self.aviones) do
        if a.avion == id then
            return true
        end
    end
    for _, c in ipairs(self.cola) do
        if c.avion == id then
            return true
        end
    end
    return false
end

function Trafico:poner(modo, id, vuelo)
    local plaza = self:plazaLibre()
    if not plaza then
        return false
    end
    local robot = self.crearAvion(modo, plaza)
    self.aviones[#self.aviones + 1] = { robot = robot, avion = id, vuelo = vuelo, plaza = plaza }
    print(string.format('TRAFICO: avión %d (vuelo %d) %s, plaza %.0f m', id, vuelo, modo, plaza))
    return true
end

--- Lo que hay al entrar: los aviones aparcados en el sitio.
function Trafico:empezar()
    local e = self.sim.estado
    for _, id in ipairs(self.sim.ordenadas(e.vuelos or {})) do
        local v = e.vuelos[id]
        if v.fase == 'esperar' and cerca(self, v.x, v.y) then
            for _, avion in ipairs(v.aviones) do
                if not self:poner('aparcado', avion, id) then
                    -- Sin plaza: aterrizará cuando quede una.
                    self.cola[#self.cola + 1] = { avion = avion, vuelo = id }
                end
            end
        end
    end
end

function Trafico:actualizar(dt)
    local ritmo = self:ritmo(dt)
    self.tiempo = self.tiempo + dt
    self.reloj = self.reloj + dt
    if self.reloj < Trafico.cadaCuanto then
        return
    end
    self.reloj = 0
    local e = self.sim.estado
    -- Los que ya dejaron la escena: fuera (su plaza queda libre).
    local quedan = {}
    for _, a in ipairs(self.aviones) do
        if not a.robot.guardado then
            quedan[#quedan + 1] = a
        end
    end
    self.aviones = quedan
    for _, a in ipairs(self.aviones) do
        local fase = a.robot:getVuelo()
        if fase ~= a.fase then
            a.fase = fase
            print(string.format('TRAFICO: avión %d %s', a.avion, fase))
        end
    end
    -- Cómo está la pista y quién se mueve por tierra.
    local pistaOcupada, llegando, saliendo = false, false, false
    for _, a in ipairs(self.aviones) do
        local fase, enPista = a.robot:getVuelo()
        pistaOcupada = pistaOcupada or enPista
        if a.sale then
            if fase ~= 'aparcado' and fase ~= 'carreteo' and fase ~= 'despegue' and fase ~= 'ascenso' and fase ~= 'salida' and fase ~= 'fuera' then
                saliendo = true
            end
        elseif fase ~= 'estacionado' then
            llegando = true
        end
    end
    -- Salidas: los que su vuelo ya no es de aquí, de uno en uno.
    for _, a in ipairs(self.aviones) do
        local v = e.vuelos[a.vuelo]
        local sigue = deAqui(self, v)
        if sigue then
            -- El avión ya no va en ese vuelo (lo deshicieron): se va.
            sigue = false
            for _, id in ipairs(v.aviones) do
                sigue = sigue or id == a.avion
            end
        end
        if not sigue and not a.sale and not saliendo and not llegando then
            a.sale = true
            saliendo = true
            a.robot:setSalida()
            print(string.format('TRAFICO: el avión %d se va (vuelo %d)', a.avion, a.vuelo))
        end
        if a.sale and not pistaOcupada and a.robot:getVuelo() == 'espera' then
            pistaOcupada = true
            a.robot:setPistaLibre()
            print(string.format('TRAFICO: pista libre para el avión %d', a.avion))
        end
    end
    -- Llegadas: los aviones de los vuelos que vienen (o ya están aquí y aún
    -- no se ven), a la cola.
    for _, id in ipairs(self.sim.ordenadas(e.vuelos or {})) do
        local v = e.vuelos[id]
        if deAqui(self, v) then
            local listo = v.fase == 'esperar'
            if not listo then
                local _, _, velocidad, queda = destino(self, v)
                listo = ritmo > 0 and queda / velocidad / ritmo <= Trafico.anticipo
            end
            if listo then
                for _, avion in ipairs(v.aviones) do
                    if not self:conocido(avion) then
                        self.cola[#self.cola + 1] = { avion = avion, vuelo = id }
                    end
                end
            end
        end
    end
    -- Fuera de la cola los que ya no vienen.
    local cola = {}
    for _, c in ipairs(self.cola) do
        if deAqui(self, e.vuelos[c.vuelo]) then
            cola[#cola + 1] = c
        end
    end
    self.cola = cola
    -- El siguiente aparece en la final con la pista libre, nadie saliendo y
    -- una plaza para él.
    local siguiente = self.cola[1]
    if siguiente and not pistaOcupada and not saliendo and self.tiempo - (self.ultimaLlegada or -math.huge) > Trafico.separacion then
        if self:poner('llegada', siguiente.avion, siguiente.vuelo) then
            table.remove(self.cola, 1)
            self.ultimaLlegada = self.tiempo
        end
    end
end

return Trafico

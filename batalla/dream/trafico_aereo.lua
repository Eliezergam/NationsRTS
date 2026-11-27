-- Los aviones del mapa en la escena 3D de un sitio (diseno/aviones-de-transporte.md,
-- paso 5; el dueño, 26-nov). La escena de una mina o una ciudad mira los
-- vuelos de la simulación (mundo/simulacion/aviones.lua) y enseña lo que le
-- toca al sitio, a la hora del mapa:
--
--   * aparcado    un vuelo que espera en el sitio con su grupo: el avión está
--                 en la pista y no se mueve hasta que el vuelo se va;
--   * llegada     un vuelo que viene al sitio: aparece en la final (fuera de
--                 la vista) cuando en el mapa le faltan `anticipo` segundos y
--                 aterriza; si en el mapa falta un minuto, se espera un minuto;
--   * salida      el vuelo del avión de la escena se va en el mapa: despega y
--                 deja la escena.
--
-- Hay una pista por sitio: un avión cada vez (el primero que toca). Solo lee
-- la simulación; no cambia nada.

local Trafico = {}
Trafico.__index = Trafico

Trafico.radio = 30 -- px del mapa: un vuelo a menos de esto del sitio está en él
Trafico.anticipo = 45 -- s reales que tarda el avión 3D desde que aparece hasta que toca
Trafico.cadaCuanto = 0.5 -- s entre dos miradas a la simulación

--- `escena` (EscenaDream) con `combate.sitio.mapaX/mapaY` (el sitio en el
-- mapa) y `crearAvion(modo)` ('aparcado' o 'llegada') que pone el avión 3D en
-- la pista y lo devuelve.
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
    }, Trafico)
end

local function cerca(self, x, y)
    return x and (x - self.x) ^ 2 + (y - self.y) ^ 2 < Trafico.radio ^ 2
end

--- A dónde va el vuelo `v` ahora y a qué velocidad (px del mapa por día).
local function destino(self, v)
    local Aviones = self.sim.Aviones
    local reglas = Aviones.reglas
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

--- Días de juego por segundo real, medidos (con el mundo más lento en la
-- batalla o en pausa sale lo que sea).
function Trafico:ritmo(dt)
    local ahora = self.sim:ahora()
    if self.antes and dt > 0 then
        local medido = (ahora - self.antes) / dt
        self.medido = self.medido and (self.medido * 0.8 + medido * 0.2) or medido
    end
    self.antes = ahora
    return self.medido or 0
end

--- Lo que hay al entrar: el avión aparcado del sitio, si hay.
function Trafico:empezar()
    local e = self.sim.estado
    for _, id in ipairs(self.sim.ordenadas(e.vuelos or {})) do
        local v = e.vuelos[id]
        if v.fase == 'esperar' and cerca(self, v.x, v.y) then
            self.vuelo = id
            self.avion = self.crearAvion('aparcado')
            print(string.format('TRAFICO: el vuelo %d está aparcado en el sitio', id))
            return
        end
    end
end

function Trafico:actualizar(dt)
    local ritmo = self:ritmo(dt)
    self.reloj = self.reloj + dt
    if self.reloj < Trafico.cadaCuanto then
        return
    end
    self.reloj = 0
    local e = self.sim.estado
    -- El avión de la escena: si su vuelo se va del sitio en el mapa, despega.
    if self.avion then
        local v = self.vuelo and e.vuelos[self.vuelo]
        local sigue = false
        if v and v.fase == 'esperar' then
            sigue = cerca(self, v.x, v.y)
        elseif v then
            -- Aún viene hacia aquí (el que está aterrizando).
            local dx, dy = destino(self, v)
            sigue = dx ~= nil and cerca(self, dx, dy)
        end
        if not sigue and not self.saliendo then
            self.saliendo = true
            self.avion:setSalida()
            print(string.format('TRAFICO: el vuelo %s se va del sitio: despega', tostring(self.vuelo)))
        end
        if self.avion.guardado then
            -- Ya salió de la escena: la pista queda libre.
            self.avion, self.vuelo, self.saliendo = nil, nil, nil
        end
        return
    end
    -- Pista libre: el primero que llega (o el que ya espera aquí).
    for _, id in ipairs(self.sim.ordenadas(e.vuelos or {})) do
        local v = e.vuelos[id]
        if v.fase == 'esperar' and cerca(self, v.x, v.y) then
            self.vuelo = id
            self.avion = self.crearAvion('aparcado')
            return
        end
        local dx, dy, velocidad, queda = destino(self, v)
        if dx and cerca(self, dx, dy) and not cerca(self, v.x, v.y) and ritmo > 0 then
            local segundos = queda / velocidad / ritmo
            if segundos <= Trafico.anticipo then
                self.vuelo = id
                self.avion = self.crearAvion('llegada')
                print(string.format('TRAFICO: llega el vuelo %d (en el mapa faltaban %.0f s)', id, segundos))
                return
            end
        end
    end
end

return Trafico

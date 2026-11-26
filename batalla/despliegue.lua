-- Fase de preparación de la batalla 3D (diseno/batalla-despliegue-y-movimiento.md,
-- paso 1): un contador de 2:00 con el combate en pausa, una zona de
-- despliegue por bando (rectángulo sobre el terreno, con una franja neutral
-- en medio) y el «Listo» de cada bando. La batalla empieza al acabar el
-- contador o, antes, cuando los dos bandos están listos.
--
-- Solo guarda el estado de la preparación: no mueve unidades ni dibuja
-- (eso es `batalla/despliegue_vista.lua`). La escena (`batalla/escena.lua`)
-- no hace avanzar la pelea mientras dura.
--
-- Las zonas se miden en el eje del combate: `d` es la distancia a lo largo
-- de `combate.angulo` desde el centro (el atacante, bando 1, viene de las
-- `d` negativas; el defensor, de las positivas) y `l`, la distancia al lado.

local Despliegue = {}
Despliegue.__index = Despliegue

Despliegue.duracion = 120 -- s de preparación (decisión del dueño: unos 2 minutos)
-- Zonas alargadas, de frente ancho y poco fondo, como en Bannerlord (el dueño:
-- «más angosta pero más ancha» y, después, menos fondo y más lejos del
-- enemigo): 350 m de fondo por 1,6 km de ancho, de 500 a 850 m del centro,
-- con una franja neutral de 1 km. Caben en el límite del campo (1,2 km de
-- radio). Con preparación, los bandos forman con la primera fila a
-- `separacion` del centro (50 m detrás del borde delantero de su zona; 1,1 km
-- entre primeras filas); sin preparación, a 850 m (Tropas.separacion).
Despliegue.mitadNeutral = 5000 -- px del centro al borde delantero de cada zona (franja neutral de 1 km)
Despliegue.separacion = 5500 -- px del centro a la primera fila de cada bando
Despliegue.margen = 500 -- px de la zona alrededor de las unidades del bando
Despliegue.mitadAnchoMinimo = 8000 -- px: cada zona mide al menos 1,6 km de ancho
Despliegue.fondoMinimo = 3500 -- px: cada zona mide al menos 350 m de fondo
-- Cámara de la preparación (vista de comandante): el ojo no sale de la zona
-- propia, como mucho a 80 m del suelo y mirando al menos 30° hacia abajo. Así
-- lo más lejano que se ve (el borde de arriba de la pantalla, en 16:9) cae a
-- unos 540 m del ojo: desde el borde delantero no llega a la zona enemiga (a
-- 1 km) aunque se mire hacia ella.
Despliegue.alturaCamara = 800 -- px sobre el suelo
Despliegue.inclinacionCamara = math.rad(30)
Despliegue.margenLimite = 150 -- px que el fondo de la zona puede quedar detrás de su última unidad

--- Preparación de las `tropas` del `combate`. `propio` es el bando que
-- manda el jugador (1 o 2); el otro es el NPC. `segundos` (opcional) cambia
-- la duración del contador.
function Despliegue.nuevo(tropas, combate, propio, segundos)
    local self = setmetatable({}, Despliegue)
    self.combate = combate
    self.propio = propio or 1
    self.duracion = segundos or Despliegue.duracion
    self.restante = self.duracion
    self.listos = { false, false }
    self.terminada = false
    self.ca = math.cos(combate.angulo)
    self.sa = math.sin(combate.angulo)
    local limite = tropas.suelo and tropas.suelo.limite
    self.zonas = {
        self:medirZona(tropas, 1, limite),
        self:medirZona(tropas, 2, limite),
    }
    return self
end

--- (d, l) de un punto (x, y) del mundo en el eje del combate.
function Despliegue:aEje(x, y)
    local dx = x - self.combate.cx
    local dy = y - self.combate.cy
    local d = dx * self.ca + dy * self.sa
    local l = -dx * self.sa + dy * self.ca
    return d, l
end

--- (x, y) del mundo de un punto (d, l) del eje del combate.
function Despliegue:aMundo(d, l)
    local x = self.combate.cx + self.ca * d - self.sa * l
    local y = self.combate.cy + self.sa * d + self.ca * l
    return x, y
end

--- Zona del bando `indice`: el rectángulo { dMin, dMax, lMin, lMax } que
-- envuelve sus unidades con `margen`, desde la franja neutral hasta detrás
-- de su última fila, y al menos `mitadAnchoMinimo` a cada lado.
function Despliegue:medirZona(tropas, indice, limite)
    local signo = indice == 1 and -1 or 1
    local fondo = 0
    local lado = 0
    for _, u in ipairs(tropas.unidades) do
        if u.bando == indice and not u.muerto then
            local d, l = self:aEje(u.x, u.y)
            fondo = math.max(fondo, d * signo)
            lado = math.max(lado, math.abs(l))
        end
    end
    local delante = Despliegue.mitadNeutral
    local mitadAncho = math.max(Despliegue.mitadAnchoMinimo, lado + Despliegue.margen)
    local atras = math.max(delante + Despliegue.fondoMinimo, fondo + Despliegue.margen)
    if limite then
        -- El fondo no pasa del límite del campo, salvo lo justo para que
        -- quepa la última unidad.
        local radio = limite.radio
        local tope = math.sqrt(math.max(0, radio * radio - mitadAncho * mitadAncho))
        atras = math.max(math.min(atras, tope), fondo + Despliegue.margenLimite, delante + Despliegue.fondoMinimo)
    end
    local zona = {
        bando = indice,
        lMin = -mitadAncho,
        lMax = mitadAncho,
    }
    if indice == 1 then
        zona.dMin = -atras
        zona.dMax = -delante
    else
        zona.dMin = delante
        zona.dMax = atras
    end
    return zona
end

--- ¿Está (x, y) dentro de la zona del bando `indice`? Con `radio`, la
-- unidad entera.
function Despliegue:dentro(indice, x, y, radio)
    local zona = self.zonas[indice]
    local d, l = self:aEje(x, y)
    local r = radio or 0
    return d >= zona.dMin + r and d <= zona.dMax - r and l >= zona.lMin + r and l <= zona.lMax - r
end

--- (x, y) metido en la zona del bando `indice`: el punto de la zona más
-- cercano (el mismo si ya está dentro).
function Despliegue:ajustar(indice, x, y)
    local zona = self.zonas[indice]
    local d, l = self:aEje(x, y)
    d = math.max(zona.dMin, math.min(zona.dMax, d))
    l = math.max(zona.lMin, math.min(zona.lMax, l))
    return self:aMundo(d, l)
end

--- Recinto de la cámara del jugador mientras dura la preparación
-- (`Camara:usarRecinto`): su zona, techo y mirada hacia abajo.
function Despliegue:recintoCamara()
    return {
        ajustar = function(x, y)
            return self:ajustar(self.propio, x, y)
        end,
        alturaMaxima = Despliegue.alturaCamara,
        minInclinacion = Despliegue.inclinacionCamara,
    }
end

--- Las cuatro esquinas (x, y) de la zona del bando `indice`, en orden.
function Despliegue:esquinas(indice)
    local z = self.zonas[indice]
    local puntos = {}
    for _, p in ipairs({ { z.dMin, z.lMin }, { z.dMax, z.lMin }, { z.dMax, z.lMax }, { z.dMin, z.lMax } }) do
        local x, y = self:aMundo(p[1], p[2])
        puntos[#puntos + 1] = { x = x, y = y }
    end
    return puntos
end

--- El bando `indice` está listo (el jugador pulsó «Listo»; el NPC, al
-- terminar de formarse).
function Despliegue:marcarListo(indice)
    if not self.terminada then
        self.listos[indice] = true
    end
end

--- El NPC (el bando que no es el del jugador) se marca listo cuando termina
-- de formarse. Hoy forma al entrar (batalla/tropas.lua); su formación propia
-- en la zona llega en el paso 4.
function Despliegue:formarNpc()
    self:marcarListo(self.propio == 1 and 2 or 1)
end

--- ¿Están listos los dos bandos?
function Despliegue:todosListos()
    return self.listos[1] and self.listos[2]
end

--- Avanza el contador `dt` s. Devuelve true el cuadro en que termina la
-- preparación (contador a cero o los dos bandos listos).
function Despliegue:actualizar(dt)
    if self.terminada then
        return false
    end
    self.restante = math.max(0, self.restante - dt)
    if self.restante <= 0 or self:todosListos() then
        self.terminada = true
        return true
    end
    return false
end

--- Termina la preparación ya (sin esperar al contador).
function Despliegue:terminar()
    self.terminada = true
end

--- Segundos que quedan, redondeados hacia arriba (lo que enseña el contador).
function Despliegue:segundosRestantes()
    return math.ceil(self.restante - 1e-9)
end

return Despliegue

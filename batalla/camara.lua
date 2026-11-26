-- Cámara libre de la batalla con el control del ejemplo firstpersongame de
-- 3DreamEngine (batalla/controlador_camara.lua): el botón derecho mira, W/S
-- van hacia la mirada en 3D con la inercia del ejemplo, A/D a los lados,
-- Espacio sube y Ctrl baja; la
-- rueda da un impulso hacia donde se mira. Esta cámara solo añade las reglas
-- del juego: el ojo no sale del campo (x/y), no tiene techo y se mantiene por
-- encima del suelo o del agua con un colchón suave. El campo de visión es fijo.
-- x/y/objetivoZ y distancia conservan el contrato de los encuadres existentes.

local Matriz = require('batalla.matriz')
local Controlador = require('batalla.controlador_camara')

local Camara = {}
Camara.__index = Camara

Camara.campo = math.rad(40) -- campo de visión vertical
Camara.cerca = 20 -- px del plano cercano con la cámara pegada (se aleja con ella)
Camara.cercaPie = 1.5 -- px (15 cm) del plano cercano en primera persona
Camara.distanciaPie = 350 -- px de la mira por delante del ojo en primera persona
Camara.lejos = 90000
Camara.minDistancia = 350
Camara.maxDistancia = 6000
Camara.minInclinacion = math.rad(-89)
Camara.maxInclinacion = math.rad(89)
Camara.alturaMinima = 60 -- px sobre el suelo o agua: el colchón empuja hasta aquí
Camara.alturaDura = 20 -- px: por debajo de esto el ojo no baja nunca
Camara.empujeSuelo = 8 -- 1/s: rapidez con que el colchón devuelve el ojo a su altura
Camara.margenMovimiento = 5200
Camara.radioSacudida = 1200 -- 120 m desde el ojo, incluida la altura
Camara.duracionSacudida = 0.45
Camara.anguloSacudida = math.rad(0.65)
-- Suavizado del giro con el ratón (k del Controlador.fraccion): 15 → el 95 %
-- del delta se consume en ~0.2 s. Más bajo = más suave pero con lag; más alto
-- = más directo pero vuelve a sentirse a brincos.
Camara.suavizadoGiro = 15

-- Rapidez de crucero del vuelo: la altura solo la modula, nunca desplaza por
-- sí misma la cámara. El controlador la convierte en la aceleración del ejemplo.
Camara.rapidezBase = 80 -- px/s
Camara.rapidezPorAltura = 0.42
Camara.rapidezMaxima = 2000 -- px/s
Camara.pasoRueda = 160 -- px de recorrido (16 m) por paso
Camara.pasoColision = 20 -- px entre muestras del terreno al desplazarse
Camara.seguimiento = 4

--- Cámara mirando a (x, y) sobre `suelo`. El rumbo por defecto (45°) es el
-- del mapa isométrico: se ve el sitio con la misma orientación.
function Camara.nueva(suelo, x, y)
    local self = setmetatable({}, Camara)
    self.suelo = suelo
    self.x, self.y = x, y
    self.rumbo = math.pi / 4
    self.inclinacion = math.rad(28)
    self.distancia = 2200
    self.vista = {}
    self.proyeccion = {}
    self.vistaProyeccion = {}
    self.sacudidaRestante = 0
    self.sacudidaPotencia = 0
    self.relojSacudida = 0
    -- Delta del ratón aún por aplicar: cada `actualizar` consume una fracción
    -- hacia el controlador (suavizado tipo shooter, sin lag perceptible).
    self.giroPendienteX = 0
    self.giroPendienteY = 0
    self.controlador = Controlador.nuevo()
    return self
end

--- Un impacto cercano sacude la mirada, sin desplazar el ojo ni su objetivo.
function Camara:sacudir(x, y, z, intensidad)
    local ex, ey, ez = self:ojo()
    local dx = x - ex
    local dy = y - ey
    local dz = z - ez
    local distancia = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distancia >= Camara.radioSacudida then
        return
    end
    local cercania = 1 - distancia / Camara.radioSacudida
    local potencia = math.min(1, math.max(0, intensidad / 2.4)) * cercania * cercania
    if potencia <= 0 then
        return
    end
    local restante = self.sacudidaRestante / Camara.duracionSacudida
    self.sacudidaPotencia = math.min(1, self.sacudidaPotencia * restante * restante + potencia)
    self.sacudidaRestante = Camara.duracionSacudida
end

--- Ojo fijo y dirección visual temporal, compartidos por ambos renderizadores.
function Camara:puntosVista()
    local ex, ey, ez = self:ojo()
    if self.sacudidaRestante <= 0 then
        return ex, ey, ez, self.x, self.y, self.alturaMira
    end
    local restante = self.sacudidaRestante / Camara.duracionSacudida
    local amplitud = Camara.anguloSacudida * self.sacudidaPotencia * restante * restante
    local reloj = self.relojSacudida
    local rumbo = self.rumbo + math.sin(reloj * 73) * amplitud
    local inclinacion = self.inclinacion + math.sin(reloj * 91 + 0.7) * amplitud
    local horizontal = math.cos(inclinacion) * self.distancia
    return ex,
        ey,
        ez,
        ex - math.cos(rumbo) * horizontal,
        ey - math.sin(rumbo) * horizontal,
        ez - math.sin(inclinacion) * self.distancia
end

--- Posición horizontal del ojo para el objetivo y la mirada actuales.
function Camara:ojoPlano()
    local h = math.cos(self.inclinacion) * self.distancia
    return self.x + math.cos(self.rumbo) * h, self.y + math.sin(self.rumbo) * h
end

--- Superficie visible bajo el observador: terreno o agua, nunca el fondo marino.
function Camara:superficie(x, y)
    return math.max(self.suelo.nivelMar or 0, self.suelo:altura(x, y))
end

--- Altura del ojo en (x, y) con al menos `margen` px sobre la superficie
-- (por defecto, el suelo duro). Sin techo, salvo con recinto.
function Camara:limitarAltura(x, y, z, margen)
    local superficie = self:superficie(x, y)
    local r = self.recinto
    if r and r.alturaMaxima then
        z = math.min(z, superficie + r.alturaMaxima)
    end
    return math.max(superficie + (margen or Camara.alturaDura), z)
end

--- Recinto de la cámara (la preparación de la batalla, batalla/despliegue.lua):
-- `ajustar(x, y)` mete el ojo en su zona, `alturaMaxima` (px sobre el suelo)
-- es su techo y `minInclinacion` (rad) lo menos que mira hacia abajo, para no
-- ver más allá de la zona. nil: sin recinto (solo el límite del campo).
function Camara:usarRecinto(recinto)
    self.recinto = recinto
end

--- Inclinación permitida: la de siempre y, con recinto, mirando al menos
-- `minInclinacion` hacia abajo.
function Camara:limitarInclinacion(inclinacion)
    local minimo = Camara.minInclinacion
    if self.recinto and self.recinto.minInclinacion then
        minimo = math.max(minimo, self.recinto.minInclinacion)
    end
    return math.max(minimo, math.min(Camara.maxInclinacion, inclinacion))
end

--- Altura de la mira de un encuadre nuevo: el ojo empieza ya a la altura
-- mínima completa, para que el colchón no lo mueva después del corte.
function Camara:alturaInicial()
    local ex, ey = self:ojoPlano()
    local z = self:superficie(self.x, self.y)
    local ez = z + math.sin(self.inclinacion) * self.distancia
    return self:limitarAltura(ex, ey, ez, Camara.alturaMinima) - math.sin(self.inclinacion) * self.distancia
end

--- Posición permitida del ojo dentro del área generada.
function Camara:limitarOjo(x, y)
    local suelo = self.suelo
    if self.recinto then
        x, y = self.recinto.ajustar(x, y)
    end
    if suelo.limite then
        return suelo.limite:ajustar(x, y, 0)
    end
    local margen = math.min(Camara.margenMovimiento, suelo.lado * 0.25)
    return math.max(suelo.x0 + margen, math.min(suelo.x0 + suelo.lado - margen, x)),
        math.max(suelo.y0 + margen, math.min(suelo.y0 + suelo.lado - margen, y))
end

--- Recorta un encuadre nuevo por su ojo, sin restringir dónde puede mirar.
function Camara:recortar()
    local ex, ey = self:ojoPlano()
    local x, y = self:limitarOjo(ex, ey)
    self.x = self.x + x - ex
    self.y = self.y + y - ey
end

--- Primera persona (batalla/caminante.lua): desde ahora el ojo es el del
-- `caminante` y la vista RTS se guarda tal cual estaba; con nil se vuelve a
-- ella exactamente donde se dejó.
function Camara:usarCaminante(caminante)
    if caminante and not self.caminante then
        self.vistaRts = {
            x = self.x,
            y = self.y,
            rumbo = self.rumbo,
            inclinacion = self.inclinacion,
            distancia = self.distancia,
            objetivoZ = self.objetivoZ,
        }
    end
    self:detener()
    self.caminante = caminante
    if caminante then
        self:seguirCaminante()
        return
    end
    local v = self.vistaRts
    if v then
        self.x = v.x
        self.y = v.y
        self.rumbo = v.rumbo
        self.inclinacion = v.inclinacion
        self.distancia = v.distancia
        self.objetivoZ = v.objetivoZ
        self.vistaRts = nil
    end
end

--- Pone la mirada de la cámara en la del caminante: el ojo es el suyo y la
-- mira queda `distanciaPie` px por delante (sonido y sombras la usan).
function Camara:seguirCaminante()
    local c = self.caminante
    local ex, ey, ez = c:ojo()
    self.rumbo = c.rumbo
    self.inclinacion = c.inclinacion
    self.distancia = Camara.distanciaPie
    local horizontal = math.cos(self.inclinacion) * self.distancia
    self.x = ex - math.cos(self.rumbo) * horizontal
    self.y = ey - math.sin(self.rumbo) * horizontal
    self.objetivoZ = ez - math.sin(self.inclinacion) * self.distancia
end

--- Plano cercano (px): pequeño a pie para no recortar lo que se tiene al
-- lado; desde arriba se aleja con la cámara para la profundidad lejana.
function Camara:planoCercano()
    -- Ojo fijo (la vista de un robot que mira al avión de carga): 2 m, así
    -- alcanza la profundidad hasta el avión a 3 km sin recortar lo cercano
    -- (mirando al frente, el suelo a menos de 2 m no se ve).
    if self.ojoFijo then
        return 20
    end
    if self.caminante then
        return Camara.cercaPie
    end
    -- Siguiendo a un robot o al avión: 15 cm de cerca, pero si la cámara
    -- se aleja (el avión, a 110 m), el plano cercano se aleja con ella. Con
    -- 15 cm fijos y el lejano a 9 km no quedaba precisión de profundidad y
    -- el agua y la orilla temblaban desde el aire (el dueño, 20-nov).
    if self.robot then
        return math.max(Camara.cercaPie, self.distancia * 0.02)
    end
    return math.max(Camara.cerca, self.distancia * 0.01)
end

--- Posición del observador. También limita los encuadres que fijan objetivoZ
-- directamente. El rango depende de la posición del ojo, nunca de la mirada.
function Camara:ojo()
    if self.robot then
        return self:ojoRobot()
    end
    if self.caminante then
        local ex, ey, ez = self.caminante:ojo()
        self.alturaMira = ez - math.sin(self.inclinacion) * self.distancia
        self.inclinacionVista = self.inclinacion
        return ex, ey, ez
    end
    self.distancia = math.max(Camara.minDistancia, math.min(Camara.maxDistancia, self.distancia))
    self.inclinacion = self:limitarInclinacion(self.inclinacion)
    if not self.objetivoZ then
        self:recortar()
    end
    local ex, ey = self:ojoPlano()
    local objetivoZ = self:alturaObjetivo()
    local vertical = math.sin(self.inclinacion) * self.distancia
    local ez = self:limitarAltura(ex, ey, objetivoZ + vertical)
    objetivoZ = ez - vertical
    if self.objetivoZ then
        self.objetivoZ = objetivoZ
    end
    self.alturaMira = objetivoZ
    self.inclinacionVista = self.inclinacion
    return ex, ey, ez
end

-- Cámara que sigue a un robot (el dueño, 17-nov: «como en el almacén, la
-- cámara enfocando al robot»): mira a su pecho desde `distancia` px, girando
-- a su alrededor con el botón derecho (rumbo e inclinación de siempre) y
-- acercando con la rueda. El ojo no baja del suelo.
Camara.robotDistancia = { 15, 250 } -- px (1,5 m a 25 m)
Camara.robotAlturaMira = 11 -- px (1,1 m) sobre los pies del robot

--- Sigue al robot `robot` (batalla/robots/robot.lua; nil vuelve a la cámara
-- libre donde estaba).
function Camara:usarRobot(robot)
    if robot and not self.robot then
        self.vistaLibre = {
            x = self.x, y = self.y, rumbo = self.rumbo, inclinacion = self.inclinacion,
            distancia = self.distancia, objetivoZ = self.objetivoZ,
        }
        -- De lado (el dueño, 17-nov), por la derecha (la de la metralleta), algo
        -- por encima. El juego tiene la y hacia el sur: la derecha del robot
        -- es su rumbo + 90°.
        local _, _, _, rumbo = robot:getJuego()
        self.rumbo = rumbo + math.pi / 2
        self.inclinacion = math.rad(10)
        self.distancia = 55
    end
    self:detener()
    self.robot = robot
    local v = self.vistaLibre
    if not robot and v then
        self.x, self.y, self.rumbo, self.inclinacion = v.x, v.y, v.rumbo, v.inclinacion
        self.distancia, self.objetivoZ = v.distancia, v.objetivoZ
        self.vistaLibre = nil
    end
end

function Camara:ojoRobot()
    local r = self.robot
    -- `ojoFijo` = { x, y, z } px: el ojo se queda ahí y mira al robot (sigue
    -- con la mirada lo que se mueve, aunque pase por encima).
    local o = self.ojoFijo
    if o then
        local rx, ry, rz = r:getJuego()
        self.x, self.y = rx, ry
        self.alturaMira = rz
        self.objetivoZ = rz
        local h = math.max(1, math.sqrt((o[1] - rx) ^ 2 + (o[2] - ry) ^ 2))
        self.rumbo = math.atan2(o[2] - ry, o[1] - rx)
        self.inclinacion = math.atan2(o[3] - rz, h)
        self.inclinacionVista = self.inclinacion
        self.distancia = math.sqrt(h * h + (o[3] - rz) ^ 2)
        return o[1], o[2], o[3]
    end
    local d = Camara.robotDistancia
    self.distancia = math.max(d[1], math.min(d[2], self.distancia))
    self.inclinacion = math.max(math.rad(-30), math.min(math.rad(80), self.inclinacion))
    -- El robot vive en metros (batalla/robots/robot.lua): su sitio en el juego.
    local rx, ry, rz = r:getJuego()
    local tz = rz + Camara.robotAlturaMira
    self.x, self.y = rx, ry
    local h = math.cos(self.inclinacion) * self.distancia
    local ex = rx + math.cos(self.rumbo) * h
    local ey = ry + math.sin(self.rumbo) * h
    local ez = math.max(tz + math.sin(self.inclinacion) * self.distancia, self:superficie(ex, ey) + 3)
    -- La mira, en el pecho: con el ojo empujado hacia arriba se inclina más.
    self.inclinacionVista = math.atan2(ez - tz, h)
    self.objetivoZ = tz
    self.alturaMira = tz
    return ex, ey, ez
end

--- Altura de la mirada. Tras un corte vale la del suelo de debajo; desde el
-- primer cuadro se conserva en `objetivoZ` hasta el próximo movimiento.
function Camara:alturaObjetivo()
    if self.objetivoZ then
        return self.objetivoZ
    end
    return self:alturaInicial()
end

--- Derecha de la pantalla y adelante tridimensional, con Z vertical.
function Camara:ejes()
    local c = math.cos(self.rumbo)
    local s = math.sin(self.rumbo)
    local horizontal = math.cos(self.inclinacion)
    return s, -c, -c * horizontal, -s * horizontal, -math.sin(self.inclinacion)
end

--- Mueve el ojo y la mira juntos. Muestrea el trayecto para no atravesar una
-- loma entre cuadros; el borde restringe al observador, no su orientación.
function Camara:trasladar(dx, dy, dz)
    if dx == 0 and dy == 0 and dz == 0 then
        return
    end
    local ex, ey, ez = self:ojo()
    local x = ex
    local y = ey
    local z = ez
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    local pasos = math.max(1, math.ceil(largo / Camara.pasoColision))
    for _ = 1, pasos do
        x, y = self:limitarOjo(x + dx / pasos, y + dy / pasos)
        z = self:limitarAltura(x, y, z + dz / pasos)
    end
    self.objetivoZ = (self.objetivoZ or self:alturaInicial()) + z - ez
    self.x = self.x + x - ex
    self.y = self.y + y - ey
end

--- Arrastre lateral sobre el plano de la pantalla, también con vista vertical.
function Camara:desplazar(derecha, arriba)
    local rx, ry, fx, fy, fz = self:ejes()
    local ux = -fz * ry
    local uy = fz * rx
    local uz = fx * ry - fy * rx
    self:trasladar(rx * derecha + ux * arriba, ry * derecha + uy * arriba, uz * arriba)
end

--- Gira sobre el ojo: el objetivo se reubica para que el ojo no se mueva.
function Camara:girar(angulo, inclinar)
    self:orientar(self.rumbo + angulo, self.inclinacion + (inclinar or 0))
end

--- Fija rumbo e inclinación sin mover el ojo.
function Camara:orientar(rumbo, inclinacion)
    local ex, ey, ez = self:ojo()
    self.rumbo = rumbo
    self.inclinacion = self:limitarInclinacion(inclinacion)
    local horizontal = math.cos(self.inclinacion) * self.distancia
    self.x = ex - math.cos(self.rumbo) * horizontal
    self.y = ey - math.sin(self.rumbo) * horizontal
    self.objetivoZ = ez - math.sin(self.inclinacion) * self.distancia
end

--- Rueda: recorrido físico en la dirección de la mirada, sin zoom. Es un
-- impulso que frena la misma resistencia del aire del vuelo. Con Shift se
-- multiplica por tres (batalla/dream/README.md).
function Camara:avanzar(pasos)
    if self.caminante then
        return
    end
    if self.robot then
        -- La rueda acerca o aleja del robot.
        self.distancia = self.distancia * (1 - 0.12 * pasos)
        return
    end
    self.controlador:orientar(self.rumbo, self.inclinacion)
    local paso = Camara.pasoRueda * pasos
    if love.keyboard.isDown('lshift', 'rshift') then
        paso = paso * 3
    end
    self.controlador:empujar(paso)
end

--- Alias para los llamadores existentes; ahora traslada, sin cambiar distancia.
function Camara:acercar(pasos)
    self:avanzar(pasos)
end

--- Depuración en metros: altura sobre suelo/agua y altitud sobre el mar.
-- La escala del juego es 10 px por metro, independiente de la de 3Dream.
function Camara:alturas()
    local x, y, z = self:ojo()
    local superficie = self:superficie(x, y)
    local mar = self.suelo.nivelMar or 0
    return (z - superficie) / 10, (z - mar) / 10
end

--- Rapidez de vuelo según la altura actual, con un máximo para explorar.
function Camara:rapidez()
    local ex, ey, ez = self:ojo()
    local altura = math.max(0, ez - self:superficie(ex, ey))
    return math.min(Camara.rapidezMaxima, Camara.rapidezBase + Camara.rapidezPorAltura * altura)
end

--- Un paso del controlador del ejemplo; después, límite del campo y
-- colchón suave sobre el suelo. Devuelve si hubo entrada del jugador.
function Camara:actualizar(dt)
    self.relojSacudida = self.relojSacudida + dt
    self.sacudidaRestante = math.max(0, self.sacudidaRestante - dt)
    dt = math.min(dt, 0.1)
    if self.caminante then
        local activo = self.caminante:actualizar(dt)
        self:seguirCaminante()
        return activo
    end
    if not self.objetivoZ and not self.robot then
        self:ojo()
        self.objetivoZ = self:alturaInicial()
    end

    -- Giro pendiente del ratón: consume una fracción cada cuadro (k=15 → ~67 ms
    -- al 95 %, suficiente para suavizar los brincos del input crudo sin
    -- notarse lag). Lo que queda se arrastra al siguiente cuadro.
    local controlador = self.controlador
    if self.giroPendienteX ~= 0 or self.giroPendienteY ~= 0 then
        local fraccion = Controlador.fraccion(Camara.suavizadoGiro, dt)
        local dx = self.giroPendienteX * fraccion
        local dy = self.giroPendienteY * fraccion
        self.giroPendienteX = self.giroPendienteX - dx
        self.giroPendienteY = self.giroPendienteY - dy
        controlador:orientar(self.rumbo, self.inclinacion)
        controlador:mirar(dx, dy)
        self:orientar(controlador:angulos())
    end

    if self.robot then
        -- Siguiendo al robot: solo se gira con el ratón y se acerca con la rueda.
        self:ojo()
        return self.giroPendienteX ~= 0 or self.giroPendienteY ~= 0
    end
    controlador:orientar(self.rumbo, self.inclinacion)
    local ex, ey, ez = self:ojo()
    local dx, dy, dz, activo = controlador:actualizar(dt, ex, ey, ez, self:rapidez())
    self:trasladar(dx, dy, dz)
    local nx, ny, nz = self:ojo()
    controlador:recortar(dx - (nx - ex), dy - (ny - ey), dz - (nz - ez))

    -- Colchón: por debajo de la altura mínima el ojo vuelve a ella poco a poco.
    local minimo = self:superficie(nx, ny) + Camara.alturaMinima
    if nz < minimo then
        self:trasladar(0, 0, (minimo - nz) * Controlador.fraccion(Camara.empujeSuelo, dt))
        controlador:recortar(0, 0, -1)
    end
    return activo or (self.giroPendienteX ~= 0 or self.giroPendienteY ~= 0)
end

--- Seguir un punto (un misil) con suavidad: el objetivo se acerca a él sin
-- saltar aunque cambie el misil elegido.
function Camara:seguir(x, y, z, dt)
    if self.caminante then
        return
    end
    local f = Controlador.fraccion(Camara.seguimiento, math.min(dt, 0.1))
    self.controlador:detener()
    self:ojo()
    local actual = self.objetivoZ or self:alturaInicial()
    self:trasladar((x - self.x) * f, (y - self.y) * f, (z - actual) * f)
end

--- El giro del ratón acaba en este instante: consume de una vez lo que el
-- suavizado dejó pendiente, para que la mirada no derive tras soltar el botón.
function Camara:terminarGiro()
    if self.giroPendienteX == 0 and self.giroPendienteY == 0 then
        return
    end
    local controlador = self.controlador
    controlador:orientar(self.rumbo, self.inclinacion)
    controlador:mirar(self.giroPendienteX, self.giroPendienteY)
    self.giroPendienteX = 0
    self.giroPendienteY = 0
    self:orientar(controlador:angulos())
end

--- Corte: se olvida la inercia (al encuadrar).
function Camara:detener()
    self.controlador:detener()
    self.giroPendienteX = 0
    self.giroPendienteY = 0
end

--- Ratón arrastrado `dx`, `dy` px: con el derecho mira como el ejemplo
-- (`mousemoved`), con el otro desplaza. El giro se acumula y se aplica con
-- suavizado en `actualizar` (no se siente a brincos).
function Camara:arrastrar(dx, dy, girar)
    if self.caminante then
        self.caminante:mirar(dx, dy)
        self:seguirCaminante()
        return
    end
    if girar then
        self.giroPendienteX = self.giroPendienteX + dx
        self.giroPendienteY = self.giroPendienteY + dy
        return
    end
    local _, alto = love.graphics.getDimensions()
    local escala = 2 * self.distancia * math.tan(Camara.campo / 2) / alto
    self:desplazar(-dx * escala, dy * escala)
end

--- Matriz de vista y proyección del cuadro; devuelve también el ojo.
function Camara:matrices()
    local ancho, alto = love.graphics.getDimensions()
    local ex, ey, ez, tx, ty, tz = self:puntosVista()
    Matriz.mirar(ex, ey, ez, tx, ty, tz, self.vista)
    -- El plano cercano se aleja con la cámara: la profundidad alcanza para 9 km.
    local cerca = self:planoCercano()
    Matriz.perspectiva(Camara.campo, ancho / alto, cerca, Camara.lejos, self.proyeccion)
    Matriz.multiplicar(self.proyeccion, self.vista, self.vistaProyeccion)
    return self.vistaProyeccion, ex, ey, ez
end

return Camara

-- Marcas holográficas de la batalla 3D (el dueño, 2026-10-01; diseno/batalla-
-- despliegue-y-movimiento.md, «Línea de movimiento y marca de selección»):
--
--   cinta   la línea de la orden de mover: «cinta de rejilla holográfica»,
--           dos bordes de luz, un barrido de líneas transversales que avanza
--           y flechas macizas cada pocos metros hacia el destino, con un
--           anillo que late en el destino. Nace en la unidad y se acorta al
--           avanzar (la ruta pendiente que le da batalla/control.lua).
--   anillo  la marca de selección: «anillo de datos», la vida como arco
--           (menta por encima del 60 %, amarillo entre el 30 y el 60 %, rojo
--           por debajo), marcas que giran, el modelo y el número debajo y una
--           entrada corta al elegir la unidad.
--
-- Copia de la referencia animada del dueño (funciones `holoRejilla` y
-- `anilloDatosVida` de ruta-y-seleccion.html): las medidas de allí van en
-- «unidades de la referencia», que aquí pasan a px del mundo según la
-- distancia al ojo (`escalaCinta`) y el radio del anillo (`radioAnillo`). Todo
-- se apoya en el suelo punto a punto (sigue las lomas) y se proyecta a
-- pantalla; lo pintan dos shaders (batalla/cinta_holo.lua y
-- batalla/anillo_holo.lua) con los grosores en px de pantalla, como en la
-- referencia, escalados con el alto de la pantalla. Encima, los rótulos.

local CatalogoModelos = require('assets.modelos3d.catalogo')
local Camara = require('batalla.camara')
local CintaHolo = require('batalla.cinta_holo')
local AnilloHolo = require('batalla.anillo_holo')

local MarcasHolo = {}
MarcasHolo.__index = MarcasHolo

MarcasHolo.menta = { 0x6D / 255, 1, 0xC4 / 255 } -- #6DFFC4
MarcasHolo.mentaClaro = { 0xD9 / 255, 1, 0xF0 / 255 } -- #D9FFF0, el centro de las flechas y el texto
MarcasHolo.amarillo = { 1, 0xD1 / 255, 0x5C / 255 } -- #FFD15C
MarcasHolo.rojo = { 1, 0x5A / 255, 0x5A / 255 } -- #FF5A5A

-- Tamaño según la distancia al ojo (el dueño, 2026-10-01: de cerca pequeño
-- y fino, de lejos legible; juega con la cámara a ras de suelo): la cinta
-- mide `cintaPx` px de pantalla de ancho (a 1080 de alto), sin bajar de
-- `cintaMinima` ni pasar de `cintaMaxima` px del mundo; las escuadras, con
-- `factorCinta`. El anillo abraza al vehículo (`abrazo` de su largo, que
-- cuenta el cañón, más `holgura`) y en pantalla no baja de `anilloPx` px de
-- radio.
MarcasHolo.cintaPx = 40
MarcasHolo.cintaMinima = 8 -- px del mundo (0,8 m)
MarcasHolo.cintaMaxima = 40 -- px del mundo (4 m)
MarcasHolo.factorCinta = { tanque = 1, lanzacohetes = 1, soldado = 0.6 }
MarcasHolo.anchoReferencia = 18 -- la cinta de la referencia mide 18 unidades
MarcasHolo.abrazo = 0.42 -- del largo del vehículo
MarcasHolo.holgura = 4 -- px del mundo entre el vehículo y su anillo
MarcasHolo.anilloPx = 14
MarcasHolo.largoTipo = { tanque = 95, lanzacohetes = 75, soldado = 60 } -- px del mundo sin dato del catálogo
MarcasHolo.archivoFuente = 'assets/fuentes/JetBrainsMono-SemiBold.ttf'
MarcasHolo.nombreTipo = { tanque = 'Tanque', lanzacohetes = 'Lanzacohetes', soldado = 'Escuadra' }

-- Ruta: polilínea con su largo acumulado (ya viene suave de batalla/ordenes.lua) -------------------------------------------

local function medirRuta(puntos)
    local acum = { 0 }
    for k = 2, #puntos do
        local p = puntos[k - 1]
        local q = puntos[k]
        acum[k] = acum[k - 1] + math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2)
    end
    return { puntos = puntos, acum = acum, largo = acum[#acum] }
end

--- Punto a `s` px del principio de la ruta: posición, tangente y normal.
local function enS(ruta, s, salida)
    local acum = ruta.acum
    s = math.max(0, math.min(ruta.largo, s))
    -- Las cintas piden las distancias en orden: se sigue desde el último
    -- tramo usado (`ruta.tramo`) y, si `s` queda detrás, desde el principio.
    local lo = ruta.tramo or 1
    if acum[lo] > s then
        lo = 1
    end
    local ultimo = #acum
    while lo < ultimo - 1 and acum[lo + 1] < s do
        lo = lo + 1
    end
    local hi = math.min(lo + 1, ultimo)
    ruta.tramo = lo
    local a = ruta.puntos[lo]
    local b = ruta.puntos[hi]
    local d = acum[hi] - acum[lo]
    if d <= 0 then
        d = 1
    end
    local f = (s - acum[lo]) / d
    local tx = (b.x - a.x) / d
    local ty = (b.y - a.y) / d
    local n = math.sqrt(tx * tx + ty * ty)
    if n <= 0 then
        n = 1
    end
    salida.x = a.x + (b.x - a.x) * f
    salida.y = a.y + (b.y - a.y) * f
    salida.tx = tx / n
    salida.ty = ty / n
    salida.nx = -ty / n
    salida.ny = tx / n
    return salida
end

-- Marcas ------------------------------------------------------------------------------------

--- Marcas para el `control` de una escena (su cámara, su proyección y su suelo).
function MarcasHolo.nuevas(control)
    local self = setmetatable({}, MarcasHolo)
    self.control = control
    self.cintas = CintaHolo.nueva()
    self.anillos = AnilloHolo.nuevos()
    self.rotulos = {}
    self.cuantosRotulos = 0
    self.puestos = {} -- rectángulos de los rótulos ya dibujados en el cuadro
    self.punto = {}
    self.fuentes = {}
    local vacia = love.image.newImageData(1, 1)
    self.sinProfundidad = love.graphics.newImage(vacia)
    -- Lo que los dos shaders necesitan para la oclusión (`tapado`).
    self.profundidad = {
        enviar = function(shader)
            local lienzo, a, b = self:profundidadEscena()
            shader:send('profundidadEscena', lienzo or self.sinProfundidad)
            shader:send('conProfundidad', lienzo and 1 or 0)
            shader:send('rangoProfundidad', { a or 1, b or 0 })
            -- px del mundo a unidades de 3Dream (batalla/dream/conversor.lua).
            shader:send('escalaProfundidad', 0.01)
        end,
    }
    return self
end

--- Al empezar el dibujo de un cuadro: reloj, grosor de las líneas, la
-- matriz de la cámara y los ejes del suelo que en pantalla son «derecha» y
-- «abajo» (el anillo y su hueco miran siempre igual en pantalla, como en la
-- referencia).
function MarcasHolo:empezar()
    self.cintas:vaciar()
    self.anillos:vaciar()
    self.cuantosRotulos = 0
    self.t = love.timer.getTime()
    self.ancho, self.alto = love.graphics.getDimensions()
    self.ui = math.max(1, self.alto / 1080 * 1.25)
    local camara = self.control.camara
    self.m = camara.vistaProyeccion
    self.ojoX, self.ojoY, self.ojoZ = camara:ojo()
    -- px de pantalla por px del mundo a distancia 1 (la focal en px).
    self.focal = self.alto / 2 / math.tan(Camara.campo / 2)
    self.escalaPantalla = self.alto / 1080
    local suelo = self.control.tropas.suelo
    self.suelo = suelo
    self.nivelMar = suelo.nivelMar or -math.huge
    local rumbo = camara.rumbo or 0
    -- El ojo está del lado de `rumbo`: «abajo» en pantalla es hacia él.
    self.abajoX = math.cos(rumbo)
    self.abajoY = math.sin(rumbo)
    self.derechaX = -self.abajoY
    self.derechaY = self.abajoX
    local x0 = self:proyectarXY(camara.x, camara.y)
    local x1 = self:proyectarXY(camara.x + self.derechaX * 100, camara.y + self.derechaY * 100)
    if x0 and x1 and x1 < x0 then
        self.derechaX = -self.derechaX
        self.derechaY = -self.derechaY
    end
end

--- Punto del suelo (x, y) en pantalla: x, y, si cae dentro de ella y su
-- distancia al ojo en la vista (px del mundo); nil si queda detrás de la
-- cámara. Lo mismo que `Control:proyectar` sobre
-- `Control:suelo`, sin tablas (se llama cientos de veces por cuadro).
function MarcasHolo:proyectarXY(x, y)
    local z = self.suelo:altura(x, y)
    if z < self.nivelMar then
        z = self.nivelMar
    end
    z = z + 4
    local m = self.m
    local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
    if cw < 0.00001 then
        return nil
    end
    local nz = (m[9] * x + m[10] * y + m[11] * z + m[12]) / cw
    if nz > 1 then
        return nil
    end
    local nx = (m[1] * x + m[2] * y + m[3] * z + m[4]) / cw
    local ny = (m[5] * x + m[6] * y + m[7] * z + m[8]) / cw
    local visible = nx >= -1 and nx <= 1 and ny >= -1 and ny <= 1 and nz >= -1
    return (nx * 0.5 + 0.5) * self.ancho, (0.5 - ny * 0.5) * self.alto, visible, cw
end

--- La profundidad de la escena 3D para que los shaders tapen lo que queda
-- detrás del vehículo, una loma o un árbol. Es el lienzo `depth` de 3Dream
-- (la escena se dibuja con él antes que las marcas); sin 3Dream (la escena
-- 2D de pruebas), nada se tapa.
function MarcasHolo:profundidadEscena()
    local dream = package.loaded['lib.3DreamEngine']
    local lienzos = type(dream) == 'table' and dream.canvases
    if not (lienzos and lienzos.depth and dream.camera) then
        return nil
    end
    local cerca = dream.camera.near
    local lejos = dream.camera.far
    return lienzos.depth, (lejos + cerca) / (lejos - cerca), -2 * lejos * cerca / (lejos - cerca)
end

--- px del mundo que mide en pantalla un px a la distancia del ojo a (x, y).
function MarcasHolo:mundoPorPx(x, y)
    local z = self.suelo:altura(x, y)
    local d = math.sqrt((x - self.ojoX) ^ 2 + (y - self.ojoY) ^ 2 + (z - self.ojoZ) ^ 2)
    return d / self.focal
end

--- Escala de la cinta en (x, y): px del mundo por unidad de la referencia.
function MarcasHolo:escalaCinta(x, y, factor)
    local ancho = MarcasHolo.cintaPx * self.escalaPantalla * self:mundoPorPx(x, y)
    ancho = math.max(MarcasHolo.cintaMinima, math.min(MarcasHolo.cintaMaxima, ancho)) * (factor or 1)
    return ancho / MarcasHolo.anchoReferencia
end

--- Radio del anillo de `unidad` (px del mundo): abraza al vehículo y, de
-- lejos, no baja de `anilloPx` px de pantalla.
function MarcasHolo:radioAnillo(unidad)
    local entrada = unidad.modelo and CatalogoModelos.modelo(unidad.modelo)
    local largo = entrada and entrada.largo and entrada.largo * 10 or MarcasHolo.largoTipo[unidad.tipo] or 80
    local abraza = largo * MarcasHolo.abrazo + MarcasHolo.holgura
    local minimo = MarcasHolo.anilloPx * self.escalaPantalla * self:mundoPorPx(unidad.x, unidad.y)
    return math.max(abraza, minimo)
end

--- La cinta de rejilla holográfica de `unidad` por su ruta `pendiente`
-- (lista de { x, y } que empieza en la unidad) y el anillo que late en su
-- destino. `despeje`: px desde la unidad en los que no se pinta (los
-- taparía el vehículo, como en la referencia).
function MarcasHolo:cinta(unidad, pendiente, despeje)
    local ruta = medirRuta(pendiente)
    local largo = ruta.largo
    if largo < 2 then
        return
    end
    local p = self.punto
    local factor = MarcasHolo.factorCinta[unidad.tipo] or 1
    local e = self.cintas:anadir(self, ruta, enS, factor, math.min(despeje or 0, largo), p)
    enS(ruta, largo, p)
    self.anillos:anadir(self, p.x, p.y, e, 'destino', 1, 0)
end

--- Nombre visible de la unidad: «modelo · número» (T-72B · 04).
function MarcasHolo.rotulo(unidad)
    local entrada = unidad.modelo and CatalogoModelos.modelo(unidad.modelo)
    local nombre = entrada and entrada.nombre or MarcasHolo.nombreTipo[unidad.tipo] or unidad.tipo
    return string.format('%s · %02d', nombre, unidad.numero or 0)
end

--- Fracción de vida (0 a 1) de la unidad.
function MarcasHolo.vida(unidad)
    if not (unidad.vidaMax and unidad.vidaMax > 0) then
        return 1
    end
    return math.max(0, math.min(1, (unidad.vida or unidad.vidaMax) / unidad.vidaMax))
end

--- El anillo de datos de `unidad`, de radio `r` px del mundo, elegida hace
-- `edad` segundos, y su rótulo 18 px por debajo del anillo en pantalla.
function MarcasHolo:anillo(unidad, r, edad)
    local x, y = unidad.x, unidad.y
    self.anillos:anadir(self, x, y, r / 24, 'datos', MarcasHolo.vida(unidad), edad)
    local bx, by, visible = self:proyectarXY(x + self.abajoX * r, y + self.abajoY * r)
    if bx and visible then
        local n = self.cuantosRotulos + 1
        self.cuantosRotulos = n
        local rotulo = self.rotulos[n]
        if not rotulo then
            rotulo = {}
            self.rotulos[n] = rotulo
        end
        rotulo.texto = MarcasHolo.rotulo(unidad)
        rotulo.x = bx
        rotulo.y = by + 18 * self.ui
        local v = math.max(0, math.min(1, edad / 0.4))
        rotulo.alfa = 1 - (1 - v) ^ 3
    end
end

--- Fuente de los rótulos (10 px de la referencia, escalada), cargada una vez.
function MarcasHolo:fuente()
    local tam = math.max(11, math.floor(10 * self.ui + 0.5))
    local f = self.fuentes[tam]
    if not f then
        if love.filesystem.getInfo(MarcasHolo.archivoFuente) then
            f = love.graphics.newFont(MarcasHolo.archivoFuente, tam)
        else
            f = love.graphics.newFont(tam)
        end
        self.fuentes[tam] = f
    end
    return f
end

--- Dibuja lo acumulado en el cuadro: las cintas, los anillos y los rótulos.
function MarcasHolo:terminar()
    local g = love.graphics
    self.cintas:dibujar(self.t, self.ui, MarcasHolo.menta, MarcasHolo.mentaClaro, self.profundidad)
    self.anillos:dibujar(self.t, self.ui, MarcasHolo, self.profundidad)
    if self.cuantosRotulos == 0 then
        return
    end
    local fuente = self:fuente()
    g.setFont(fuente)
    local claro = MarcasHolo.mentaClaro
    local alto = fuente:getHeight()
    -- Sin solapes: el rótulo que pisaría uno ya puesto no se dibuja (con
    -- muchas unidades juntas, como todas las escuadras elegidas).
    local puestos = self.puestos
    local cuantosPuestos = 0
    for i = 1, self.cuantosRotulos do
        local r = self.rotulos[i]
        local ancho = fuente:getWidth(r.texto)
        local x = math.floor(r.x - ancho / 2 + 0.5)
        local y = math.floor(r.y - alto / 2 + 0.5)
        local libre = true
        for k = 1, cuantosPuestos do
            local o = puestos[k]
            if x < o.x + o.ancho and o.x < x + ancho and y < o.y + alto and o.y < y + alto then
                libre = false
                break
            end
        end
        if libre then
            cuantosPuestos = cuantosPuestos + 1
            local o = puestos[cuantosPuestos]
            if not o then
                o = {}
                puestos[cuantosPuestos] = o
            end
            o.x, o.y, o.ancho = x, y, ancho
            g.setColor(claro[1], claro[2], claro[3], r.alfa)
            g.print(r.texto, x, y)
        end
    end
end

return MarcasHolo

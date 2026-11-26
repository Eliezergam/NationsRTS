--- Cámara de juego al estilo OpenRA para el runtime.
--
--   local Camera = require('runtime.camera')
--   local cam = Camera.new({
--       design = { w = 1280, h = 720 },              -- ajuste a pantalla (escala fija)
--       bounds = Camera.levelBounds(level),          -- no se ve fuera del mapa
--       zoom = 1, minZoom = .5, maxZoom = 3,
--   })
--   function love.update(dt) cam:update(dt) end
--   function love.draw()
--       cam:attach(); level:draw(cam:visibleRect()); cam:detach()
--       hud:draw()                                   -- fuera de la cámara: fijo en pantalla
--   end
--
-- Por defecto **no hay bandas**: `design` fija la escala (1 unidad de diseño = 1
-- píxel de mundo a zoom 1) y el mundo se sigue dibujando hasta el borde de la
-- ventana, de modo que una pantalla más alta enseña más mapa, como en cualquier
-- RTS. Con `letterbox = true` el mundo se recorta al lienzo de diseño y salen
-- las franjas negras.
--
-- Lo que hace, copiado de OpenRA:
--
--   * **borde de pantalla**: el ratón cerca de un borde desplaza, y va más
--     rápido cuanto más pegado al borde esté;
--   * **teclas**: flechas y WASD, con las opuestas anulándose;
--   * **arrastre** con el botón central (o el derecho si se configura), que
--     **nunca es obligatorio**: todo se puede hacer con el borde y las teclas;
--   * **rueda**: zoom hacia el punto que hay bajo el cursor, no hacia el centro;
--   * **táctil**: un dedo arrastra, dos hacen pellizco y desplazan;
--   * **seguimiento** de una unidad, que se suspende solo en cuanto el jugador
--     mueve la cámara a mano;
--   * **sacudida** al impactar, que decae sola.
--
-- ## Las cuentas
--
-- La cámara guarda su **centro** en el mundo, `(x, y)`, y un `zoom` (1 = 1:1).
-- Con `design` el mundo se dibuja sobre un lienzo lógico de `design.w x design.h`
-- que se escala entero a la ventana conservando la proporción (bandas a los
-- lados o arriba y abajo), igual que hacía `examples/DemoMisil/main.lua` a mano:
--
--     escala  = min(ventanaW / diseñoW, ventanaH / diseñoH)
--     margenX = (ventanaW - diseñoW * escala) / 2
--     margenY = (ventanaH - diseñoH * escala) / 2
--
-- Sin `design` la vista **es** la ventana (escala 1, márgenes 0). Con eso, el
-- paso de mundo a pantalla es siempre el mismo:
--
--     pantallaX = margenX + escala * (vistaW/2 + zoom * (mundoX - centroX))
--
-- y `toWorld` es su inversa exacta, despejada término a término. No se redondea
-- en ningún punto intermedio, así que `toScreen(toWorld(p)) == p` a cualquier
-- zoom, con `design` y sin él.
--
-- `attach()` aplica exactamente esa misma cadena con `love.graphics`, en el
-- mismo orden, de modo que lo que se dibuja entre `attach` y `detach` cae donde
-- dice `toScreen`. Todo lo demás del módulo son cuentas puras: no hay una sola
-- llamada a `love.*` fuera de `attach`, `detach` y los manejadores de entrada,
-- así que las matemáticas se prueban sin abrir una ventana.

local Projection = require('runtime.projection')
local Camera = {}
Camera.__index = Camera

local function finite(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return fallback or 0
    end
    return n
end

local function clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

--- Normaliza `keys`: cada dirección acepta una tecla o una lista de teclas.
local function keyList(value, fallback)
    if value == nil then
        return fallback
    end
    if type(value) == 'string' then
        return { value }
    end
    if type(value) ~= 'table' then
        return fallback
    end
    local list = {}
    for _, key in ipairs(value) do
        if type(key) == 'string' then
            list[#list + 1] = key
        end
    end
    return list
end

--- Teclas por defecto: flechas **y** WASD, las dos cosas a la vez.
function Camera.defaultKeys()
    return {
        up = { 'up', 'w' },
        down = { 'down', 's' },
        left = { 'left', 'a' },
        right = { 'right', 'd' },
    }
end

Camera.defaults = {
    zoom = 1,
    minZoom = 0.25,
    maxZoom = 4,
    edgeScroll = { margin = 24, speed = 900, minFactor = 0.35 },
    drag = { button = 3 },
    wheelZoom = true,
    wheelStep = 1.2,
    touch = true,
    clamp = true,
    letterbox = false,
    smoothing = 6,
    deadZone = 0,
}

-- Caja del mundo ---------------------------------------------------------------

--- Rectángulo de mundo que la cámara debería poder recorrer en un nivel.
--
-- Es la unión de tres cosas, con el mismo criterio que el minimapa del editor:
-- el rectángulo declarado del mapa (`width x height` celdas), las celdas de
-- terreno pintadas —que el editor deja poner en coordenadas negativas— y los
-- objetos colocados. Un mapa cuyo terreno se sale del rectángulo declarado, como
-- el de `examples/DemoMisil`, sigue siendo recorrible entero.
--- Dónde debe empezar a mirar la cámara de un nivel. Nunca el centro vacío
-- de un mapa grande: primero la posición de inicio RTS del jugador (`playerId`,
-- 1 por defecto), luego el centro de sus unidades, luego el de todas las
-- unidades, luego el de todos los objetos, y solo si no hay nada, el centro del
-- mapa. Devuelve x, y en coordenadas de mundo.
function Camera.levelStart(level, playerId)
    local map = level and (level.data or level) or {}
    playerId = tonumber(playerId) or 1
    local rts = type(map.rts) == 'table' and map.rts or {}

    for _, start in ipairs(type(rts.starts) == 'table' and rts.starts or {}) do
        if
            type(start) == 'table'
            and tonumber(start.playerId) == playerId
            and tonumber(start.x)
            and tonumber(start.y)
        then
            return tonumber(start.x), tonumber(start.y)
        end
    end

    local sums = { mine = { 0, 0, 0 }, units = { 0, 0, 0 }, all = { 0, 0, 0 } }

    local function add(bucket, o)
        bucket[1] = bucket[1] + o.x
        bucket[2] = bucket[2] + o.y
        bucket[3] = bucket[3] + 1
    end

    for _, layer in ipairs(map.layers or {}) do
        for _, o in ipairs(layer.objects or {}) do
            if type(o) == 'table' and tonumber(o.x) and tonumber(o.y) and o.type ~= 'collision' then
                local role = type(o.rts) == 'table' and o.rts.role or nil
                add(sums.all, o)

                if role == 'unit' then
                    add(sums.units, o)

                    if tonumber(o.rts.playerId) == playerId then
                        add(sums.mine, o)
                    end
                end
            end
        end
    end

    for _, key in ipairs({ 'mine', 'units', 'all' }) do
        local b = sums[key]

        if b[3] > 0 then
            return b[1] / b[3], b[2] / b[3]
        end
    end

    local tile = math.max(1, finite(map.tileSize, 32))
    return finite(map.width, 100) * tile / 2, finite(map.height, 60) * tile / 2
end

function Camera.levelBounds(level, margin)
    local map = level and (level.data or level) or {}
    local tile = math.max(1, finite(map.tileSize, 32))
    local minX, minY = 0, 0
    local maxX = math.max(tile, finite(map.width, 100) * tile)
    local maxY = math.max(tile, finite(map.height, 60) * tile)
    local function include(x, y)
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if y < minY then
            minY = y
        end
        if y > maxY then
            maxY = y
        end
    end
    for _, layer in ipairs(map.layers or {}) do
        for _, cell in pairs(layer.tiles or {}) do
            if type(cell) == 'table' then
                local cx, cy = math.floor(finite(cell.x)), math.floor(finite(cell.y))
                include(cx * tile, cy * tile)
                include((cx + 1) * tile, (cy + 1) * tile)
            end
        end
        for _, object in ipairs(layer.objects or {}) do
            if type(object) == 'table' then
                local hw = math.abs(finite(object.w, 32) * finite(object.scaleX, 1)) * 0.5
                local hh = math.abs(finite(object.h, 32) * finite(object.scaleY, 1)) * 0.5
                include(finite(object.x) - hw, finite(object.y) - hh)
                include(finite(object.x) + hw, finite(object.y) + hh)
            end
        end
    end
    margin = finite(margin, 0)
    return {
        x = minX - margin,
        y = minY - margin,
        w = math.max(1, maxX - minX) + margin * 2,
        h = math.max(1, maxY - minY) + margin * 2,
    }
end

-- Construcción -------------------------------------------------------------------

function Camera.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Camera)

    local screen = opts.screen
    local sw, sh = screen and screen.w, screen and screen.h
    if (not sw or not sh) and love and love.graphics and love.graphics.getDimensions then
        sw, sh = love.graphics.getDimensions()
    end

    if type(opts.design) == 'table' then
        local dw = math.max(1, finite(opts.design.w or opts.design[1], 1280))
        local dh = math.max(1, finite(opts.design.h or opts.design[2], 720))
        self.design = { w = dw, h = dh }
    end
    self.screenW = math.max(1, finite(sw, self.design and self.design.w or 1280))
    self.screenH = math.max(1, finite(sh, self.design and self.design.h or 720))

    self.minZoom = math.max(1e-4, finite(opts.minZoom, Camera.defaults.minZoom))
    self.maxZoom = math.max(self.minZoom, finite(opts.maxZoom, Camera.defaults.maxZoom))
    self.zoom = clamp(finite(opts.zoom, Camera.defaults.zoom), self.minZoom, self.maxZoom)

    self.clamp = opts.clamp ~= false
    -- Las bandas se piden a mano. Por defecto el mundo llena la ventana y
    -- `design` solo fija la escala, que es lo que hace un RTS: en una pantalla
    -- más alta se ve más mapa, no dos franjas negras.
    self.letterbox = opts.letterbox == true
    -- El centro tiene que existir antes que los límites: `setBounds` ya acota.
    self.shakeX, self.shakeY = 0, 0
    -- Mapa cuya vista usa la cámara (`projection = 'iso'`). La cámara vive en el
    -- plano de la vista; `centerOn`, `toWorld`, `toScreen` y `visibleRect` hablan
    -- en coordenadas de mundo, como siempre.
    self.projection = type(opts.projection) == 'table' and opts.projection or nil
    self.x, self.y = finite(opts.x, 0), finite(opts.y, 0)
    self:setBounds(opts.bounds)
    if opts.x == nil and opts.y == nil and self.viewBounds then
        self.x = self.viewBounds.x + self.viewBounds.w * 0.5
        self.y = self.viewBounds.y + self.viewBounds.h * 0.5
    end

    self.edgeScroll = false
    if opts.edgeScroll ~= false then
        local e = type(opts.edgeScroll) == 'table' and opts.edgeScroll or {}
        self.edgeScroll = {
            margin = math.max(1, finite(e.margin, Camera.defaults.edgeScroll.margin)),
            speed = math.max(0, finite(e.speed, Camera.defaults.edgeScroll.speed)),
            minFactor = clamp(finite(e.minFactor, Camera.defaults.edgeScroll.minFactor), 0, 1),
        }
    end

    self.keys = false
    if opts.keys ~= false then
        local base = Camera.defaultKeys()
        local given = type(opts.keys) == 'table' and opts.keys or {}
        self.keys = {
            up = keyList(given.up, base.up),
            down = keyList(given.down, base.down),
            left = keyList(given.left, base.left),
            right = keyList(given.right, base.right),
        }
    end
    self.keySpeed = math.max(
        0,
        finite(opts.keySpeed, self.edgeScroll and self.edgeScroll.speed or Camera.defaults.edgeScroll.speed)
    )
    self.keysDown = {}

    self.drag = false
    if opts.drag ~= false then
        local d = opts.drag
        local button = 3
        if type(d) == 'table' then
            button = math.floor(finite(d.button, 3))
        elseif type(d) == 'number' then
            button = math.floor(d)
        elseif d == 'right' then
            button = 2
        elseif d == 'middle' then
            button = 3
        elseif d == 'left' then
            button = 1
        end
        self.drag = { button = button }
    end

    self.wheelZoom = opts.wheelZoom ~= false
    self.wheelStep = math.max(1.0001, finite(opts.wheelStep, Camera.defaults.wheelStep))
    self.touch = opts.touch ~= false
    self.touches, self.touchOrder, self.pinch = {}, {}, nil

    self.focused = true
    self.edgeBlocked = false
    self.mouseX, self.mouseY = nil, nil
    self.dragging = nil
    self.shakeAmount, self.shakeTotal, self.shakeLeft = 0, 0, 0
    self.seed = math.floor(finite(opts.seed, 1)) % 2147483647
    if self.seed <= 0 then
        self.seed = 1
    end

    self.followTarget = nil
    self.followSmoothing = finite(opts.smoothing, Camera.defaults.smoothing)
    self.followDeadZone = math.max(0, finite(opts.deadZone, Camera.defaults.deadZone))
    self.followRelease = true
    self.followSuspended = false

    self:_applyBounds()
    return self
end

--- Límites del mundo. `nil` los quita.
function Camera:setBounds(bounds)
    if type(bounds) == 'table' then
        self.bounds = {
            x = finite(bounds.x or bounds[1]),
            y = finite(bounds.y or bounds[2]),
            w = math.max(1e-6, finite(bounds.w or bounds[3], 1)),
            h = math.max(1e-6, finite(bounds.h or bounds[4], 1)),
        }
        if bounds.clamp ~= nil then
            self.clamp = bounds.clamp ~= false
        end
        -- `bounds` sigue siendo el rectángulo del mundo (lo leen el minimapa y el
        -- juego); para acotar se usa su caja en la vista.
        self.viewBounds = Projection.viewRect(self.projection, self.bounds)
    else
        self.bounds = nil
        self.viewBounds = nil
    end
    self:_applyBounds()
    return self
end

--- Cambia la vista (`map.projection`) sin mover el punto de mundo del centro.
function Camera:setProjection(map)
    local wx, wy = Projection.toWorld(self.projection, self.x, self.y)
    self.projection = type(map) == 'table' and map or nil
    if self.bounds then
        self.viewBounds = Projection.viewRect(self.projection, self.bounds)
    end
    return self:centerOn(wx, wy)
end

--- Tamaño de la ventana. Lo llaman `resize` y `attach`.
function Camera:setScreen(w, h)
    local nw = math.max(1, finite(w, self.screenW))
    local nh = math.max(1, finite(h, self.screenH))
    if nw == self.screenW and nh == self.screenH then
        return self
    end
    self.screenW, self.screenH = nw, nh
    self:_applyBounds()
    return self
end

-- Vista, mundo y pantalla ----------------------------------------------------------

--- Lienzo lógico y su encaje en la ventana: `vistaW, vistaH, escala, margenX, margenY`.
-- Sin `design` la vista es la ventana y la escala 1.
function Camera:view()
    if not self.design then
        return self.screenW, self.screenH, 1, 0, 0
    end
    local dw, dh = self.design.w, self.design.h
    local scale = math.min(self.screenW / dw, self.screenH / dh)
    return dw, dh, scale, (self.screenW - dw * scale) * 0.5, (self.screenH - dh * scale) * 0.5
end

--- Centro efectivo: el de la cámara más la sacudida.
function Camera:center()
    return self.x + self.shakeX, self.y + self.shakeY
end

--- Punto del mundo a punto de la pantalla (píxeles de la ventana).
function Camera:toScreen(wx, wy)
    local vw, vh, scale, ox, oy = self:view()
    local cx, cy = self:center()
    wx, wy = Projection.toViewGround(self.projection, finite(wx), finite(wy))
    return ox + scale * (vw * 0.5 + (finite(wx) - cx) * self.zoom),
        oy + scale * (vh * 0.5 + (finite(wy) - cy) * self.zoom)
end

--- Punto de la pantalla a punto del mundo. Inversa exacta de `toScreen`.
function Camera:toWorld(sx, sy)
    local vw, vh, scale, ox, oy = self:view()
    local cx, cy = self:center()
    -- Sobre el terreno: con relieve, el punto de la colina que hay bajo el ratón.
    return Projection.pick(
        self.projection,
        cx + ((finite(sx) - ox) / scale - vw * 0.5) / self.zoom,
        cy + ((finite(sy) - oy) / scale - vh * 0.5) / self.zoom
    )
end

--- Tamaño de lo que se ve de verdad, en unidades de la vista (antes del zoom).
--
-- Con `letterbox` el mundo se recorta al lienzo de diseño, así que se ve el
-- lienzo y nada más. Sin él —lo normal— el mundo sigue dibujándose fuera del
-- lienzo hasta el borde de la ventana, y lo que se ve es la ventana entera
-- medida en unidades de la vista: `ventana / escala`. Con una ventana más alta
-- que el diseño eso es **más mapa**, no bandas.
function Camera:visibleSize()
    local vw, vh, scale = self:view()
    if self.design and not self.letterbox then
        return self.screenW / scale, self.screenH / scale
    end
    return vw, vh
end

--- Rectángulo de la vista que se está viendo (en isométrico, no es el mundo).
function Camera:visibleViewRect()
    local vw, vh = self:visibleSize()
    local cx, cy = self:center()
    local w, h = vw / self.zoom, vh / self.zoom
    return { x = cx - w * 0.5, y = cy - h * 0.5, w = w, h = h }
end

--- Rectángulo del mundo que se está viendo, para recortar el dibujo. En
-- isométrico es la caja del rombo visible.
function Camera:visibleRect()
    return Projection.expandForRelief(self.projection, Projection.worldRect(self.projection, self:visibleViewRect()))
end

--- Rectángulo de la pantalla donde poner el HUD: el área de juego. Con bandas
-- es el rectángulo del diseño, para no dejar nada en una franja negra; sin
-- ellas, la ventana entera, porque el mundo la llena.
function Camera:hudRect()
    if self.design and self.letterbox then
        local vw, vh, scale, ox, oy = self:view()
        return ox, oy, vw * scale, vh * scale
    end
    return 0, 0, self.screenW, self.screenH
end

-- Movimiento -----------------------------------------------------------------------

function Camera:_applyBounds()
    if not self.viewBounds or not self.clamp then
        return
    end
    local b = self.viewBounds
    local vw, vh = self:visibleSize()
    local hw, hh = vw / (2 * self.zoom), vh / (2 * self.zoom)
    -- Mapa más pequeño que la vista: se centra. Acotarlo entre dos límites
    -- cruzados haría vibrar la cámara entre ellos en cada cuadro.
    if b.w <= hw * 2 then
        self.x = b.x + b.w * 0.5
    else
        self.x = clamp(self.x, b.x + hw, b.x + b.w - hw)
    end
    if b.h <= hh * 2 then
        self.y = b.y + b.h * 0.5
    else
        self.y = clamp(self.y, b.y + hh, b.y + b.h - hh)
    end
end

--- Centra la cámara en un punto del mundo.
function Camera:centerOn(wx, wy)
    -- Un eje que no llega (nil o no finito) conserva el del centro actual.
    local currentX, currentY = Projection.toWorld(self.projection, self.x, self.y)
    self.x, self.y = Projection.toView(self.projection, finite(wx, currentX), finite(wy, currentY))
    self:_applyBounds()
    return self
end

--- Desplaza la cámara en coordenadas de mundo.
function Camera:move(dx, dy)
    self.x = self.x + finite(dx)
    self.y = self.y + finite(dy)
    self:_applyBounds()
    return self
end

--- Marca que el jugador ha movido la cámara a mano: el seguimiento se suspende
-- hasta que se vuelva a llamar a `follow`.
function Camera:panned()
    if self.followTarget and self.followRelease then
        self.followSuspended = true
    end
    return self
end

function Camera:setZoom(zoom)
    self.zoom = clamp(finite(zoom, self.zoom), self.minZoom, self.maxZoom)
    self:_applyBounds()
    return self
end

--- Zoom manteniendo fijo el punto de mundo que hay bajo `(sx, sy)` de pantalla.
-- Sin punto, hacia el centro de la vista.
function Camera:zoomAt(factor, sx, sy)
    factor = finite(factor, 1)
    if factor <= 0 then
        return self
    end
    local target = clamp(self.zoom * factor, self.minZoom, self.maxZoom)
    if target == self.zoom then
        return self
    end
    if sx == nil or sy == nil then
        self.zoom = target
        self:_applyBounds()
        return self
    end
    -- `u` es la distancia del punto al centro de la vista, en unidades de la
    -- vista: no depende del zoom, así que basta despejar el centro nuevo.
    local vw, vh, scale, ox, oy = self:view()
    local ux = (finite(sx) - ox) / scale - vw * 0.5
    local uy = (finite(sy) - oy) / scale - vh * 0.5
    local cx, cy = self:center()
    local wx, wy = cx + ux / self.zoom, cy + uy / self.zoom
    self.zoom = target
    self.x = wx - ux / target - self.shakeX
    self.y = wy - uy / target - self.shakeY
    self:_applyBounds()
    return self
end

-- Seguimiento ------------------------------------------------------------------------

--- Sigue a un nodo de `runtime/world.lua`, a una función que devuelve `x, y`, o
-- a nada (`nil`) para dejar de seguir.
--
--   cam:follow(world.Unidades.Tanke, { smoothing = 6, deadZone = 40 })
--   cam:follow(function() return jefe.x, jefe.y end)
--   cam:follow(nil)
--
-- `smoothing` es la constante de un acercamiento exponencial: cada cuadro la
-- cámara recorre `k = 1 - exp(-smoothing * dt)` de lo que le falta. Esa forma
-- **no depende de los FPS**, porque componer dos pasos de `dt` da exactamente
-- un paso de `2·dt`: `(1-e^-s·dt)` seguido de otro deja `e^-2s·dt` del error.
-- `deadZone` es el radio en píxeles de mundo dentro del cual no se mueve nada.
function Camera:follow(target, opts)
    opts = opts or {}
    self.followTarget = target or nil
    self.followSmoothing = math.max(0, finite(opts.smoothing, Camera.defaults.smoothing))
    self.followDeadZone = math.max(0, finite(opts.deadZone, Camera.defaults.deadZone))
    self.followRelease = opts.releaseOnInput ~= false
    self.followSuspended = false
    return self
end

--- Punto que hay que seguir ahora mismo, o `nil`.
function Camera:followPoint()
    local target = self.followTarget
    if not target then
        return nil
    end
    if type(target) == 'function' then
        local x, y = target()
        if x == nil or y == nil then
            return nil
        end
        return finite(x), finite(y)
    end
    if type(target) ~= 'table' then
        return nil
    end
    if type(target.isDestroyed) == 'function' and target:isDestroyed() then
        return nil
    end
    if target.x == nil or target.y == nil then
        return nil
    end
    return finite(target.x), finite(target.y)
end

-- Sacudida -----------------------------------------------------------------------

-- Generador propio (Lehmer/MINSTD) en vez de `math.random`: la sacudida no
-- puede depender del estado global del azar del juego ni alterarlo, y así las
-- pruebas ven siempre la misma secuencia.
function Camera:_random()
    self.seed = (self.seed * 16807) % 2147483647
    return self.seed / 2147483647
end

--- Sacude la cámara `seconds` segundos con una amplitud de `intensity` píxeles
-- de mundo que decae linealmente hasta cero.
function Camera:shake(intensity, seconds)
    intensity = math.max(0, finite(intensity, 0))
    seconds = math.max(0, finite(seconds, 0.3))
    if intensity <= 0 or seconds <= 0 then
        self.shakeAmount, self.shakeTotal, self.shakeLeft = 0, 0, 0
        self.shakeX, self.shakeY = 0, 0
        return self
    end
    self.shakeAmount, self.shakeTotal, self.shakeLeft = intensity, seconds, seconds
    return self
end

-- Entrada: vectores -------------------------------------------------------------------

--- ¿Está pulsada alguna de las teclas de una dirección?
function Camera:keyDown(direction)
    if not self.keys then
        return false
    end
    for _, key in ipairs(self.keys[direction] or {}) do
        if self.keysDown[key] then
            return true
        end
    end
    return false
end

--- Desplazamiento por teclado, en píxeles de mundo por segundo. Las teclas
-- opuestas se anulan y la diagonal se normaliza.
function Camera:keyVector()
    if not self.keys or not self.focused then
        return 0, 0
    end
    local x = (self:keyDown('right') and 1 or 0) - (self:keyDown('left') and 1 or 0)
    local y = (self:keyDown('down') and 1 or 0) - (self:keyDown('up') and 1 or 0)
    if x == 0 and y == 0 then
        return 0, 0
    end
    local len = math.sqrt(x * x + y * y)
    return x / len * self.keySpeed, y / len * self.keySpeed
end

--- Desplazamiento por borde de pantalla, en píxeles de mundo por segundo.
--
-- Función pura, para poder probarla con números a mano. `mx, my` son píxeles de
-- la ventana; `margin` también. Dentro del margen la velocidad **crece con la
-- cercanía al borde**, como en OpenRA:
--
--     cercanía = (margen - distancia_al_borde) / margen      -- 0 dentro, 1 en el borde
--     factor   = minFactor + (1 - minFactor) * cercanía
--
-- La dirección es el vector de signos **normalizado**, así que una esquina
-- desplaza a la misma velocidad total que un lado y no √2 veces más rápido:
-- cada componente vale `velocidad / √2`.
function Camera.edgeScrollVector(mx, my, w, h, opts)
    if mx == nil or my == nil then
        return 0, 0
    end
    opts = opts or {}
    local margin = math.max(1, finite(opts.margin, Camera.defaults.edgeScroll.margin))
    local speed = math.max(0, finite(opts.speed, Camera.defaults.edgeScroll.speed))
    local floorFactor = clamp(finite(opts.minFactor, Camera.defaults.edgeScroll.minFactor), 0, 1)
    w = math.max(1, finite(w, 1))
    h = math.max(1, finite(h, 1))
    local function axis(v, size)
        if v < margin then
            return -1, clamp((margin - v) / margin, 0, 1)
        end
        if v > size - margin then
            return 1, clamp((v - (size - margin)) / margin, 0, 1)
        end
        return 0, 0
    end
    local ax, fx = axis(finite(mx), w)
    local ay, fy = axis(finite(my), h)
    if ax == 0 and ay == 0 then
        return 0, 0
    end
    local factor = floorFactor + (1 - floorFactor) * math.max(fx, fy)
    local len = math.sqrt(ax * ax + ay * ay)
    return ax / len * speed * factor, ay / len * speed * factor
end

--- Apaga el borde de pantalla mientras el puntero está sobre algo del HUD (el
-- minimapa, un panel...), como hace OpenRA. Sin esto, arrastrar en un radar
-- pegado a la esquina desplazaría la cámara al mismo tiempo.
function Camera:setEdgeBlocked(blocked)
    self.edgeBlocked = blocked and true or false
    return self
end

function Camera:edgeVector()
    if not self.edgeScroll or not self.focused or self.edgeBlocked then
        return 0, 0
    end
    if self.dragging or next(self.touches) ~= nil then
        return 0, 0
    end
    return Camera.edgeScrollVector(self.mouseX, self.mouseY, self.screenW, self.screenH, self.edgeScroll)
end

--- Desplazamiento pedido por el jugador. Las teclas mandan sobre el borde: si
-- hay una pulsada, el ratón cerca del borde no suma nada.
function Camera:inputVector()
    local kx, ky = self:keyVector()
    if kx ~= 0 or ky ~= 0 then
        return kx, ky
    end
    return self:edgeVector()
end

-- Actualización ---------------------------------------------------------------------

function Camera:update(dt)
    dt = math.max(0, finite(dt, 0))

    local vx, vy = self:inputVector()
    if vx ~= 0 or vy ~= 0 then
        self:move(vx * dt, vy * dt)
        self:panned()
    end

    if self.followTarget and not self.followSuspended then
        local tx, ty = self:followPoint()
        if tx then
            tx, ty = Projection.toView(self.projection, tx, ty)
            -- Lo que vuela se sigue a su altura, no a su sombra.
            local target = self.followTarget
            local z = type(target) == 'table' and tonumber(target.z) or nil
            if z then
                ty = ty - Projection.lift(self.projection, z)
            end
            local gx, gy = tx, ty
            if self.followDeadZone > 0 then
                local dx, dy = tx - self.x, ty - self.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= self.followDeadZone then
                    gx, gy = self.x, self.y
                else
                    local k = (d - self.followDeadZone) / d
                    gx, gy = self.x + dx * k, self.y + dy * k
                end
            end
            local k = 1
            if self.followSmoothing > 0 and dt > 0 then
                k = 1 - math.exp(-self.followSmoothing * dt)
            elseif dt <= 0 then
                k = 0
            end
            self.x = self.x + (gx - self.x) * k
            self.y = self.y + (gy - self.y) * k
            self:_applyBounds()
        end
    end

    if self.shakeLeft > 0 then
        self.shakeLeft = math.max(0, self.shakeLeft - dt)
        if self.shakeLeft <= 0 then
            self.shakeX, self.shakeY = 0, 0
            self.shakeAmount, self.shakeTotal = 0, 0
        else
            local amplitude = self.shakeAmount * (self.shakeLeft / self.shakeTotal)
            self.shakeX = (self:_random() * 2 - 1) * amplitude
            self.shakeY = (self:_random() * 2 - 1) * amplitude
        end
    end
    return self
end

-- Dibujo --------------------------------------------------------------------------

--- Empuja la transformación de la cámara. Lo que se dibuje hasta `detach()`
-- está en coordenadas de mundo.
function Camera:attach()
    local g = love.graphics
    self:setScreen(g.getWidth(), g.getHeight())
    local vw, vh, scale, ox, oy = self:view()
    local cx, cy = self:center()
    if self.design and self.letterbox then
        -- El recorte va en píxeles de la ventana: `setScissor` no se ve afectado
        -- por la transformación en curso (comprobado en LÖVE 11.5). Así el mundo
        -- no se sale a las bandas del ajuste a pantalla.
        self._scissor = { g.getScissor() }
        g.setScissor(ox, oy, vw * scale, vh * scale)
    end
    g.push()
    g.translate(ox, oy)
    g.scale(scale)
    g.translate(vw * 0.5, vh * 0.5)
    g.scale(self.zoom)
    g.translate(-cx, -cy)
    -- Desde aquí se dibuja en coordenadas de mundo (en isométrico, en rombo).
    Projection.apply(self.projection)
    return self
end

function Camera:detach()
    local g = love.graphics
    g.pop()
    local saved = self._scissor
    if saved then
        if saved[1] then
            g.setScissor(saved[1], saved[2], saved[3], saved[4])
        else
            g.setScissor()
        end
        self._scissor = nil
    end
    return self
end

-- Manejadores de entrada ----------------------------------------------------------
--
-- Todos devuelven `true` cuando han consumido el evento, para poder repartirlo
-- primero a la UI y después a la cámara.

--- Posición del puntero. El borde de pantalla la usa en cada cuadro, así que el
-- ratón parado en el borde sigue desplazando sin que llegue ningún evento.
function Camera:setPointer(x, y)
    self.mouseX, self.mouseY = finite(x, self.mouseX), finite(y, self.mouseY)
    return self
end

function Camera:mousepressed(x, y, button, isTouch)
    self:setPointer(x, y)
    if isTouch then
        return false
    end
    if self.drag and button == self.drag.button then
        self.dragging = button
        self.dragX, self.dragY = finite(x), finite(y)
        return true
    end
    return false
end

function Camera:mousemoved(x, y, _dx, _dy, isTouch)
    self:setPointer(x, y)
    if isTouch or not self.dragging then
        return false
    end
    self:_dragTo(finite(x), finite(y))
    return true
end

function Camera:mousereleased(x, y, button, isTouch)
    self:setPointer(x, y)
    if isTouch then
        return false
    end
    if self.dragging and button == self.dragging then
        self.dragging = nil
        return true
    end
    return false
end

--- Arrastre: el mundo sigue al cursor 1:1. Un píxel de pantalla son
-- `1 / (escala * zoom)` píxeles de mundo.
function Camera:_dragTo(x, y)
    local _, _, scale = self:view()
    local k = 1 / (scale * self.zoom)
    self:move(-(x - self.dragX) * k, -(y - self.dragY) * k)
    self:panned()
    self.dragX, self.dragY = x, y
end

function Camera:wheelmoved(_dx, dy)
    if not self.wheelZoom then
        return false
    end
    dy = finite(dy)
    if dy == 0 then
        return false
    end
    local sx = self.mouseX or (self.screenW * 0.5)
    local sy = self.mouseY or (self.screenH * 0.5)
    self:zoomAt(self.wheelStep ^ dy, sx, sy)
    return true
end

--- ¿Es una tecla de la cámara? Se mira antes de marcarla para no consumir
-- teclas que el juego necesita.
function Camera:isCameraKey(key)
    if not self.keys then
        return false
    end
    for _, direction in ipairs({ 'up', 'down', 'left', 'right' }) do
        for _, candidate in ipairs(self.keys[direction] or {}) do
            if candidate == key then
                return true
            end
        end
    end
    return false
end

function Camera:keypressed(key)
    if not self:isCameraKey(key) then
        return false
    end
    self.keysDown[key] = true
    return true
end

function Camera:keyreleased(key)
    if not self:isCameraKey(key) then
        return false
    end
    self.keysDown[key] = nil
    return true
end

--- La ventana pierde el foco: se sueltan las teclas, que si no se quedarían
-- pulsadas para siempre y la cámara se iría sola.
function Camera:focus(focused)
    self.focused = focused ~= false
    if not self.focused then
        self.keysDown = {}
    end
    return self
end

function Camera:resize(w, h)
    self:setScreen(w, h)
    return false
end

-- Táctil: un dedo arrastra, dos hacen pellizco y desplazan --------------------------

function Camera:_touchPair()
    local a = self.touches[self.touchOrder[1]]
    local b = self.touches[self.touchOrder[2]]
    if not a or not b then
        return nil
    end
    local mx, my = (a.x + b.x) * 0.5, (a.y + b.y) * 0.5
    local dx, dy = b.x - a.x, b.y - a.y
    return mx, my, math.sqrt(dx * dx + dy * dy)
end

--- Ancla del pellizco: el punto de **mundo** que hay bajo el punto medio de los
-- dos dedos y la distancia entre ellos medida en mundo. Anclar en el mundo, y no
-- en la pantalla, hace que el gesto no dependa del orden en que lleguen los
-- eventos: LÖVE manda un `touchmoved` por dedo, así que un pellizco simétrico
-- llega como dos movimientos sueltos y un ajuste incremental dejaría un resto.
function Camera:_rebase()
    local mx, my, dist = self:_touchPair()
    if mx and dist and dist > 1e-6 then
        local _, _, scale = self:view()
        local wx, wy = self:toWorld(mx, my)
        self.pinch = { wx = wx, wy = wy, worldDist = dist / (scale * self.zoom) }
    else
        self.pinch = nil
    end
end

function Camera:touchpressed(id, x, y)
    if not self.touch then
        return false
    end
    if self.touches[id] == nil then
        self.touchOrder[#self.touchOrder + 1] = id
    end
    self.touches[id] = { x = finite(x), y = finite(y) }
    self:_rebase()
    return true
end

function Camera:touchmoved(id, x, y)
    if not self.touch or not self.touches[id] then
        return false
    end
    local touch = self.touches[id]
    local px, py = touch.x, touch.y
    touch.x, touch.y = finite(x), finite(y)
    local _, _, scale = self:view()
    if self.pinch then
        local mx, my, dist = self:_touchPair()
        if mx and dist and dist > 1e-6 and self.pinch.worldDist > 1e-9 then
            -- Zoom: la separación de los dedos en pantalla vuelve a medir lo que
            -- medía en el mundo al empezar el gesto.
            self:setZoom(dist / (scale * self.pinch.worldDist))
            -- Desplazamiento: el punto de mundo anclado cae bajo el punto medio.
            local vw, vh, s, ox, oy = self:view()
            local ux = (mx - ox) / s - vw * 0.5
            local uy = (my - oy) / s - vh * 0.5
            self:centerOn(self.pinch.wx - ux / self.zoom - self.shakeX, self.pinch.wy - uy / self.zoom - self.shakeY)
            self:panned()
        end
        return true
    end
    if self.touchOrder[1] == id then
        local k = 1 / (scale * self.zoom)
        self:move(-(touch.x - px) * k, -(touch.y - py) * k)
        self:panned()
    end
    return true
end

function Camera:touchreleased(id, _x, _y)
    if not self.touch or not self.touches[id] then
        return false
    end
    self.touches[id] = nil
    for i = #self.touchOrder, 1, -1 do
        if self.touchOrder[i] == id then
            table.remove(self.touchOrder, i)
        end
    end
    self:_rebase()
    return true
end

return Camera

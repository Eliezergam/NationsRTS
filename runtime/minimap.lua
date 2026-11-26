-- Minimapa de runtime, al estilo del radar de OpenRA.
--
--   local Minimap = require('runtime.minimap')
--   local radar = Minimap.new(level, cam, { x = 20, y = 20, w = 220, h = 160 })
--   function love.update(dt) radar:update(dt) end
--   function love.draw()
--       cam:attach(); level:draw(); cam:detach()
--       radar:draw()                      -- fuera de la cámara: fijo en pantalla
--   end
--   function love.mousepressed(x, y, b) if not ui:mousepressed(x, y, b) then radar:mousepressed(x, y, b) end end
--
-- Dibuja tres capas, de abajo a arriba:
--
--   1. **el terreno**, un color por celda —el color medio de su imagen— sobre un
--      `Canvas` que se pinta una sola vez;
--   2. **los objetos**, un punto con el color de su jugador
--      (`object.rts.playerId` contra `map.rts.players`), gris si no tiene dueño;
--   3. **el rectángulo de lo que ve la cámara**, que es lo único que cambia en
--      cada cuadro.
--
-- Y hace lo que se espera de un radar: **un clic o un arrastre encima lleva la
-- cámara ahí** (`camera:centerOn`).
--
-- ## Escala
--
-- El mundo se encaja en el rectángulo que le des conservando la proporción, con
-- la misma escala en los dos ejes, y lo que sobra se reparte a partes iguales a
-- los dos lados:
--
--     escala = min((ancho - 2·margen) / anchoMundo, (alto - 2·margen) / altoMundo)
--
-- Es la misma cuenta que usa la ventana MINIMAPA del editor (`src/minimap.lua`),
-- pero este módulo no depende de nada del editor: solo de `runtime/camera.lua`,
-- para compartir el criterio de qué rectángulo del mundo hay que enseñar.
--
-- ## Qué se rehace y cuándo
--
-- El terreno se pinta una vez en un `Canvas` y se reutiliza. Los puntos de los
-- objetos se recalculan cada `refresh` segundos (0.25 por defecto), no en cada
-- cuadro: en un mapa de guerra son miles de objetos y el radar no necesita ir a
-- 60 Hz. El rectángulo de la cámara sí se dibuja siempre, porque es lo que se
-- mueve al navegar.

local Camera = require('runtime.camera')
local Projection = require('runtime.projection')
local TerrainPaint = require('runtime.terrain_paint')

local Minimap = {}
Minimap.__index = Minimap

Minimap.padding = 4
Minimap.colors = {
    background = { 0.05, 0.06, 0.08, 0.85 },
    frame = { 0.30, 0.36, 0.44 },
    terrain = { 0.26, 0.34, 0.30 },
    neutral = { 0.62, 0.70, 0.82 },
    camera = { 0.10, 0.72, 1 },
}

local function finite(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return fallback or 0
    end
    return n
end

-- Encaje ---------------------------------------------------------------------------

--- Encaja la caja del mundo en un rectángulo conservando la proporción.
-- Devuelve la escala y el rectángulo del dibujo **en coordenadas del panel**.
function Minimap.fit(world, panelW, panelH, padding)
    padding = finite(padding, Minimap.padding)
    local availW = math.max(1, finite(panelW, 1) - padding * 2)
    local availH = math.max(1, finite(panelH, 1) - padding * 2)
    local worldW = math.max(1e-6, finite(world.w, 1))
    local worldH = math.max(1e-6, finite(world.h, 1))
    local scale = math.min(availW / worldW, availH / worldH)
    local w, h = worldW * scale, worldH * scale
    return {
        scale = scale,
        x = padding + (availW - w) * 0.5,
        y = padding + (availH - h) * 0.5,
        w = w,
        h = h,
        world = { x = finite(world.x), y = finite(world.y), w = worldW, h = worldH },
    }
end

--- Punto de mundo a punto del panel. Con `fit.projection` (un mapa en
-- isométrico) el minimapa es el rombo de la vista y `fit.world` es la caja de la
-- vista, no del mundo.
function Minimap.toPanel(fit, wx, wy)
    wx, wy = Projection.toView(fit.projection, finite(wx), finite(wy))
    return fit.x + (wx - fit.world.x) * fit.scale, fit.y + (wy - fit.world.y) * fit.scale
end

--- Punto del panel a punto de mundo. Inversa exacta de `toPanel`.
function Minimap.toWorld(fit, px, py)
    return Projection.toWorld(
        fit.projection,
        fit.world.x + (finite(px) - fit.x) / fit.scale,
        fit.world.y + (finite(py) - fit.y) / fit.scale
    )
end

-- Construcción ---------------------------------------------------------------------

function Minimap.new(level, camera, rect, opts)
    opts = opts or {}
    local self = setmetatable({}, Minimap)
    self.level = level
    self.camera = camera
    self.map = level and (level.data or level) or {}
    self.padding = finite(opts.padding, Minimap.padding)
    self.refresh = math.max(0, finite(opts.refresh, 0.25))
    self.colors = setmetatable(opts.colors or {}, { __index = Minimap.colors })
    self.bounds = opts.bounds or (camera and camera.bounds) or Camera.levelBounds(level)
    self.dots, self.timer, self.dirty = {}, math.huge, true
    self.assetColors = {}
    self.dragging = false
    self:setRect(rect or { x = 0, y = 0, w = 200, h = 150 })
    return self
end

function Minimap:setRect(rect)
    local x = finite(rect.x or rect[1])
    local y = finite(rect.y or rect[2])
    local w = math.max(8, finite(rect.w or rect[3], 200))
    local h = math.max(8, finite(rect.h or rect[4], 150))
    local resized = self.w ~= w or self.h ~= h
    self.x, self.y = x, y
    self.w, self.h = w, h
    -- El encaje y el lienzo están en coordenadas del propio recuadro, así que
    -- moverlo por la pantalla no obliga a rehacer nada; cambiarlo de tamaño sí.
    if resized then
        self.fitCache = nil
        self.canvas = nil
        self.dirty = true
    end
    return self
end

--- El encaje de este minimapa, cacheado mientras no cambie de tamaño. Se llama
-- `layout` y no `fit` porque `Minimap.fit` es la función pura del encaje y las
-- dos viven en la misma tabla.
function Minimap:layout()
    if not self.fitCache then
        if Projection.isIso(self.map) then
            -- En isométrico el minimapa enseña el mapa en rombo, como la vista.
            self.fitCache = Minimap.fit(Projection.viewRect(self.map, self.bounds), self.w, self.h, self.padding)
            self.fitCache.projection = self.map
        else
            self.fitCache = Minimap.fit(self.bounds, self.w, self.h, self.padding)
        end
    end
    return self.fitCache
end

--- Rehace el terreno y los puntos en el próximo cuadro.
function Minimap:invalidate()
    self.dirty = true
    self.timer = math.huge
    return self
end

-- Conversiones con la pantalla -------------------------------------------------------

function Minimap:toScreenFromWorld(wx, wy)
    local px, py = Minimap.toPanel(self:layout(), wx, wy)
    return self.x + px, self.y + py
end

function Minimap:toWorldFromScreen(sx, sy)
    return Minimap.toWorld(self:layout(), finite(sx) - self.x, finite(sy) - self.y)
end

--- ¿Cae el punto dentro del minimapa?
function Minimap:contains(sx, sy)
    sx, sy = finite(sx), finite(sy)
    return sx >= self.x and sx <= self.x + self.w and sy >= self.y and sy <= self.y + self.h
end

-- Datos --------------------------------------------------------------------------

--- Color del jugador de un objeto, o el neutral.
function Minimap:playerColor(object)
    local rts = type(object.rts) == 'table' and object.rts or nil
    local id = rts and rts.playerId
    if id == nil then
        return self.colors.neutral
    end
    local players = type(self.map.rts) == 'table' and self.map.rts.players or nil
    for _, player in ipairs(players or {}) do
        if player.id == id and type(player.color) == 'table' then
            return player.color
        end
    end
    return self.colors.neutral
end

--- Los puntos de los objetos, en coordenadas del panel. Se rehacen cada
-- `refresh` segundos, no en cada cuadro.
function Minimap:rebuildDots()
    local fit = self:layout()
    local dots = {}
    local bodies = (self.level or {}).bodyForObject or {}
    for _, layer in ipairs(self.map.layers or {}) do
        if layer.visible ~= false then
            for _, object in ipairs(layer.objects or {}) do
                if type(object) == 'table' and object.type ~= 'collision' then
                    local ox, oy = finite(object.x), finite(object.y)
                    local body = bodies[object]
                    if body and body.isDestroyed and not body:isDestroyed() then
                        ox, oy = body:getPosition()
                    end
                    local px, py = Minimap.toPanel(fit, ox, oy)
                    if px >= fit.x and px <= fit.x + fit.w and py >= fit.y and py <= fit.y + fit.h then
                        local color = self:playerColor(object)
                        dots[#dots + 1] = { x = px, y = py, color = color }
                    end
                end
            end
        end
    end
    self.dots = dots
    return dots
end

function Minimap:update(dt)
    self.timer = self.timer + math.max(0, finite(dt, 0))
    if self.timer >= self.refresh then
        self.timer = 0
        self:rebuildDots()
    end
    return self
end

-- Terreno sobre un lienzo --------------------------------------------------------------

--- Color medio de una imagen, muestreando como mucho 16x16 píxeles. Se guarda
-- por ruta: el mismo tile se repite miles de veces en una capa.
function Minimap:assetColor(path)
    local cached = self.assetColors[path]
    if cached ~= nil then
        return cached or self.colors.terrain
    end
    local ok, data = pcall(love.image.newImageData, path)
    if not ok or not data then
        self.assetColors[path] = false
        return self.colors.terrain
    end
    local iw, ih = data:getWidth(), data:getHeight()
    local stepX = math.max(1, math.floor(iw / 16))
    local stepY = math.max(1, math.floor(ih / 16))
    local r, g, b, weight = 0, 0, 0, 0
    for py = 0, ih - 1, stepY do
        for px = 0, iw - 1, stepX do
            local pr, pg, pb, pa = data:getPixel(px, py)
            r, g, b, weight = r + pr * pa, g + pg * pa, b + pb * pa, weight + pa
        end
    end
    local color = self.colors.terrain
    if weight > 0 then
        color = { r / weight, g / weight, b / weight }
    end
    self.assetColors[path] = color
    return color
end

--- Pinta el terreno en un `Canvas` del tamaño del dibujo. Una celda que mediría
-- menos de un píxel se dibuja igualmente de un píxel, y las que caerían en un
-- píxel ya pintado se descartan: así el coste está acotado por los píxeles del
-- minimapa y no por las celdas del mapa, que pueden ser cientos de miles.
function Minimap:rebuildTerrain()
    local fit = self:layout()
    local cw = math.max(1, math.ceil(self.w))
    local ch = math.max(1, math.ceil(self.h))
    if not self.canvas then
        self.canvas = love.graphics.newCanvas(cw, ch)
    end
    local tile = math.max(1, finite(self.map.tileSize, 32))
    local side = math.max(1, tile * fit.scale)
    local dense = side < 1
    local covered = {}

    local g = love.graphics
    local previous = g.getCanvas()
    g.push('all')
    g.origin()
    g.setCanvas(self.canvas)
    g.clear(
        self.colors.background[1],
        self.colors.background[2],
        self.colors.background[3],
        self.colors.background[4] or 1
    )
    -- El terreno se dibuja en coordenadas de mundo bajo la misma transformación
    -- que el panel: en isométrico cada celda sale en rombo.
    g.translate(fit.x - fit.world.x * fit.scale, fit.y - fit.world.y * fit.scale)
    g.scale(fit.scale)
    Projection.apply(self.map)
    local cellSide = dense and (1 / fit.scale) or tile
    for _, layer in ipairs(self.map.layers or {}) do
        if layer.visible ~= false and type(layer.tiles) == 'table' then
            for _, cell in pairs(layer.tiles) do
                if type(cell) == 'table' and cell.asset then
                    local wx, wy = finite(cell.x) * tile, finite(cell.y) * tile
                    local px, py = Minimap.toPanel(fit, wx, wy)
                    local key = dense and (math.floor(px) .. ',' .. math.floor(py)) or nil
                    if not key or not covered[key] then
                        if key then
                            covered[key] = true
                        end
                        local color = self:assetColor(cell.asset)
                        g.setColor(color[1], color[2], color[3], layer.opacity or 1)
                        g.rectangle('fill', wx, wy, math.max(tile, cellSide), math.max(tile, cellSide))
                    end
                end
            end
        end
        -- La pintura suave de la capa, con el mismo sombreado que en el juego.
        if layer.visible ~= false and (layer.paint or layer.relief) then
            local level = self.level
            local function getImage(path)
                if level and level.getImage then
                    return level:getImage(path)
                end
                return nil
            end
            if layer.relief and Projection.isIso(self.map) then
                -- Las colinas, con la pintura encima, como en el mapa.
                require('runtime.terrain_relief').draw(self.map, layer, getImage)
            else
                TerrainPaint.draw(self.map, layer, getImage)
            end
        end
    end
    if previous then
        g.setCanvas(previous)
    else
        g.setCanvas()
    end
    g.pop()
    self.dirty = false
    return self.canvas
end

-- Dibujo ----------------------------------------------------------------------------

function Minimap:draw()
    local g = love.graphics
    local fit = self:layout()
    if self.dirty or not self.canvas then
        self:rebuildTerrain()
    end

    g.push('all')
    g.origin()
    g.translate(self.x, self.y)

    local bg = self.colors.background
    g.setColor(bg[1], bg[2], bg[3], bg[4] or 1)
    g.rectangle('fill', 0, 0, self.w, self.h, 4, 4)
    g.setColor(1, 1, 1)
    if self.canvas then
        g.draw(self.canvas)
    end

    for _, dot in ipairs(self.dots) do
        local c = dot.color
        g.setColor(c[1], c[2], c[3], c[4] or 1)
        g.rectangle('fill', dot.x - 1, dot.y - 1, 3, 3)
    end

    if self.camera and self.camera.projection and self.camera.projection.projection == 'iso' then
        -- En isométrico lo que se ve del suelo es un rombo: las cuatro esquinas
        -- de la pantalla llevadas al mundo y luego al minimapa.
        local points = {}
        local sw, sh = self.camera.screenW, self.camera.screenH
        for _, corner in ipairs({ { 0, 0 }, { sw, 0 }, { sw, sh }, { 0, sh } }) do
            local px, py = Minimap.toPanel(fit, self.camera:toWorld(corner[1], corner[2]))
            points[#points + 1] = px
            points[#points + 1] = py
        end
        local c = self.colors.camera
        -- Recortado al minimapa (el recorte va en píxeles de pantalla).
        g.intersectScissor(self.x, self.y, self.w, self.h)
        g.setColor(c[1], c[2], c[3], c[4] or 1)
        g.setLineWidth(1)
        g.polygon('line', points)
    elseif self.camera then
        local view = self.camera:visibleRect()
        local x1, y1 = Minimap.toPanel(fit, view.x, view.y)
        local x2, y2 = Minimap.toPanel(fit, view.x + view.w, view.y + view.h)
        -- El rectángulo se recorta al dibujo: con la vista mayor que el mapa se
        -- saldría del minimapa y pintaría encima del resto del HUD.
        local cx1 = math.max(x1, fit.x)
        local cy1 = math.max(y1, fit.y)
        local cx2 = math.min(x2, fit.x + fit.w)
        local cy2 = math.min(y2, fit.y + fit.h)
        if cx2 > cx1 and cy2 > cy1 then
            local c = self.colors.camera
            g.setColor(c[1], c[2], c[3], c[4] or 1)
            g.setLineWidth(1)
            g.rectangle('line', cx1 + 0.5, cy1 + 0.5, math.max(1, cx2 - cx1 - 1), math.max(1, cy2 - cy1 - 1))
        end
    end

    local frame = self.colors.frame
    g.setColor(frame[1], frame[2], frame[3], frame[4] or 1)
    g.setLineWidth(1)
    g.rectangle('line', 0.5, 0.5, self.w - 1, self.h - 1, 4, 4)
    g.pop()
    return self
end

-- Entrada: el clic lleva la cámara ---------------------------------------------------

--- Lleva la cámara al punto de mundo que corresponde a `(sx, sy)` de pantalla.
function Minimap:jumpTo(sx, sy)
    if not self.camera then
        return false
    end
    local wx, wy = self:toWorldFromScreen(sx, sy)
    self.camera:centerOn(wx, wy)
    -- Ir al radar es navegar a mano: el seguimiento se suspende, como al
    -- desplazar con las teclas o el borde.
    self.camera:panned()
    return true
end

function Minimap:mousepressed(sx, sy, button, isTouch)
    if isTouch then
        return false
    end
    if button ~= nil and button ~= 1 then
        return false
    end
    if not self:contains(sx, sy) then
        return false
    end
    self.dragging = true
    return self:jumpTo(sx, sy)
end

function Minimap:mousemoved(sx, sy, _dx, _dy, isTouch)
    if isTouch or not self.dragging then
        return false
    end
    return self:jumpTo(sx, sy)
end

function Minimap:mousereleased(_sx, _sy, button, isTouch)
    if isTouch then
        return false
    end
    if button ~= nil and button ~= 1 then
        return false
    end
    if not self.dragging then
        return false
    end
    self.dragging = false
    return true
end

function Minimap:touchpressed(id, sx, sy)
    if not self:contains(sx, sy) then
        return false
    end
    self.touchId = id
    return self:jumpTo(sx, sy)
end

function Minimap:touchmoved(id, sx, sy)
    if self.touchId ~= id then
        return false
    end
    return self:jumpTo(sx, sy)
end

function Minimap:touchreleased(id)
    if self.touchId ~= id then
        return false
    end
    self.touchId = nil
    return true
end

return Minimap

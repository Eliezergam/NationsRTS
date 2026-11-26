-- Adapter for the vendored MIT-licensed Gooi library. One environment per UI
-- keeps previews, Play sessions and game screens independent of each other.
local Ui = {}
Ui.__index = Ui
Ui.vendorFiles = {
    'utf8.lua',
    'gooi.lua',
    'component.lua',
    'layout.lua',
    'button.lua',
    'label.lua',
    'text.lua',
    'slider.lua',
    'checkbox.lua',
    'radio.lua',
    'bar.lua',
    'panel.lua',
}
local constructors = {
    button = 'newButton',
    label = 'newLabel',
    text = 'newText',
    slider = 'newSlider',
    check = 'newCheck',
    radio = 'newRadio',
    bar = 'newBar',
    panel = 'newPanel',
}
local passive = { label = true, panel = true, progressbar = true }

local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then
        return fallback
    end
    return value
end
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end
local function copyLibrary(library)
    return setmetatable({}, { __index = library })
end

local function loadGooi(self)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.string = copyLibrary(string)
    env.love = copyLibrary(love)
    env.love.graphics = copyLibrary(love.graphics)
    env.love.graphics.getWidth = function()
        return self.width
    end
    env.love.graphics.getHeight = function()
        return self.height
    end
    env.love.mouse = copyLibrary(love.mouse)
    env.love.mouse.getX = function()
        return self.mouseX or -100000
    end
    env.love.mouse.getY = function()
        return self.mouseY or -100000
    end
    env.love.keyboard = copyLibrary(love.keyboard)
    -- Translate Gooi's IME rectangle from design coordinates to this viewport.
    env.love.keyboard.setTextInput = function(enabled, x, y, w, h)
        if enabled and x then
            local rect = self:layout()
            love.keyboard.setTextInput(
                true,
                rect.x + x * rect.scale,
                rect.y + y * rect.scale,
                w * rect.scale,
                h * rect.scale
            )
        else
            love.keyboard.setTextInput(enabled)
        end
    end
    for _, name in ipairs(Ui.vendorFiles) do
        local chunk, err = love.filesystem.load('gooi/gooi/' .. name)
        assert(chunk, 'UI: missing Gooi dependency: ' .. tostring(err))
        setfenv(chunk, env)()
    end
    self.gooi = env.gooi
    self.utf8 = env.string
    self.gooi.desktopMode()
    self.gooi.setStyle({
        bgColor = { 0.11, 0.15, 0.21, 0.96 },
        fgColor = { 0.88, 0.94, 1 },
        borderColor = { 0.12, 0.58, 0.92 },
        showBorder = true,
        radius = 4,
        font = love.graphics.newFont(16),
    })
    self.gooi.canvas:setFilter('linear', 'linear')
end

function Ui.new(data)
    local self = setmetatable({ handlers = {}, pointers = {}, widgets = {}, names = {}, warnings = {} }, Ui)
    self:setData(data)
    return self
end

function Ui:setData(data)
    self:cancelInput()
    data = type(data) == 'table' and data or {}
    local canvas = type(data.canvas) == 'table' and data.canvas or {}
    local maxSize = math.min(4096, love.graphics.getSystemLimits().texturesize)
    local width = math.floor(clamp(finite(canvas.w, 1280), 1, maxSize))
    local height = math.floor(clamp(finite(canvas.h, 720), 1, maxSize))
    self.width, self.height = width, height
    self.widgets, self.names, self.warnings = {}, {}, {}
    local widgets = type(data.widgets) == 'table' and data.widgets or {}
    if not self.gooi and #widgets > 0 then
        loadGooi(self)
    end
    if not self.gooi then
        return
    end
    local gooi = self.gooi
    if gooi.canvas:getWidth() ~= width or gooi.canvas:getHeight() ~= height then
        gooi.canvas:release()
        gooi.canvas = love.graphics.newCanvas(width, height)
        gooi.canvas:setFilter('linear', 'linear')
    end
    gooi.components = {}
    for index, widget in ipairs(widgets) do
        local ctor = type(widget) == 'table' and constructors[widget.type]
        if ctor then
            local id = widget.id or index
            if self.widgets[id] then
                self.warnings[#self.warnings + 1] = 'UI: duplicate widget id ' .. tostring(id)
            else
                local component = gooi[ctor]({
                    x = finite(widget.x, 0),
                    y = finite(widget.y, 0),
                    w = math.max(24, finite(widget.w, 150)),
                    h = math.max(20, finite(widget.h, 34)),
                    text = tostring(widget.text or ''),
                    value = clamp(finite(widget.value, 0), 0, 1),
                    checked = widget.checked == true,
                    selected = widget.selected == true,
                    radioGroup = tostring(widget.radioGroup or 'default'),
                })
                -- A horizontal Gooi slider divides by (w-h) when dragged.
                if widget.type == 'slider' then
                    component.w = math.max(component.w, component.h + 1)
                end
                component:setVisible(widget.visible ~= false)
                component:setEnabled(widget.enabled ~= false)
                component.name, component.widgetId = tostring(widget.name or id), id
                if widget.type == 'label' then
                    component:setOpaque(false)
                    component:left()
                end
                if widget.type == 'panel' then
                    component:setOpaque(true)
                    component.title = tostring(widget.text or '')
                    component.drawSpecifics = function(panel, color)
                        love.graphics.setColor(color)
                        love.graphics.printf(panel.title, panel.x + 8, panel.y + 6, math.max(1, panel.w - 16))
                    end
                end
                component:onRelease(function(c)
                    local callback = self.handlers[id] or self.handlers[c.name]
                    if callback then
                        callback(c, self)
                    end
                end)
                self.widgets[id] = component
                self.names[component.name] = self.names[component.name] or component
                if widget.type == 'radio' and widget.selected then
                    component:select()
                end
            end
        else
            self.warnings[#self.warnings + 1] = 'UI: unsupported widget at index ' .. index
        end
    end
end

function Ui:get(idOrName)
    return self.widgets[idOrName] or self.names[idOrName]
end
function Ui:on(idOrName, callback)
    self.handlers[idOrName] = callback
    return self
end

-- Uniform scaling preserves the authored layout on different aspect ratios.
function Ui:setViewport(x, y, w, h)
    self.viewport = { x = x, y = y, w = math.max(1, w), h = math.max(1, h) }
end
function Ui:layout()
    local v = self.viewport or { x = 0, y = 0, w = love.graphics.getWidth(), h = love.graphics.getHeight() }
    local scale = math.min(v.w / self.width, v.h / self.height)
    return {
        x = v.x + (v.w - self.width * scale) / 2,
        y = v.y + (v.h - self.height * scale) / 2,
        w = self.width * scale,
        h = self.height * scale,
        scale = scale,
    }
end
function Ui:toCanvas(x, y)
    local rect = self:layout()
    return (x - rect.x) / rect.scale, (y - rect.y) / rect.scale
end

function Ui:clearFocus()
    if not self.gooi then
        return
    end
    local focused = self.gooi.focused
    if focused and focused.type == 'text' then
        love.keyboard.setTextInput(false)
    end
    for _, c in ipairs(self.gooi.components) do
        c.hasFocus = false
        c.keyToRepeat = nil
    end
    self.gooi.focused = nil
end
function Ui:cancelInput()
    self:clearFocus()
    for _, c in pairs(self.pointers or {}) do
        c.touch = nil
        c.pressed = false
    end
    self.pointers = {}
end

function Ui:pressed(id, x, y)
    if not self.gooi then
        return false
    end
    local cx, cy = self:toCanvas(x, y)
    self:clearFocus()
    if cx < 0 or cy < 0 or cx > self.width or cy > self.height then
        return false
    end
    local components = self.gooi.components
    for i = #components, 1, -1 do
        local c = components[i]
        if c.visible and c:overIt(cx, cy) then
            -- Passive/disabled overlays still block clicks through to the map.
            if not c.enabled or passive[c.type] or c.touch then
                return true
            end
            self.gooi.components = { c }
            self.gooi.pressed(id, cx, cy)
            self.gooi.components = components
            self.pointers[id] = c
            if c.type == 'slider' then
                c:updateGUI()
            end
            return true
        end
    end
    return false
end
function Ui:moved(id, x, y)
    local c = self.pointers[id]
    if not c then
        return false
    end
    local cx, cy = self:toCanvas(x, y)
    self.gooi.moved(id, cx, cy)
    if c.type == 'slider' then
        c:updateGUI()
    end
    return true
end
function Ui:released(id, x, y)
    local c = self.pointers[id]
    if not c then
        return false
    end
    self:moved(id, x, y)
    self.gooi.released(id)
    self.pointers[id] = nil
    return true
end
function Ui:mousepressed(x, y, button, isTouch)
    if button == 1 and not isTouch then
        self.mouseX, self.mouseY = self:toCanvas(x, y)
        return self:pressed('mouse', x, y)
    end
    return false
end
function Ui:mousemoved(x, y)
    self.mouseX, self.mouseY = self:toCanvas(x, y)
    return self:moved('mouse', x, y)
end
function Ui:mousereleased(x, y, button, isTouch)
    if button == 1 and not isTouch then
        return self:released('mouse', x, y)
    end
    return false
end
function Ui:touchpressed(id, x, y)
    return self:pressed(id, x, y)
end
function Ui:touchmoved(id, x, y)
    return self:moved(id, x, y)
end
function Ui:touchreleased(id, x, y)
    return self:released(id, x, y)
end
function Ui:hasTextFocus()
    local focused = self.gooi and self.gooi.focused
    return focused and focused.type == 'text' and focused.visible and focused.enabled or false
end
function Ui:keypressed(key, scancode, isRepeat)
    if not self:hasTextFocus() then
        return false
    end
    if key == 'escape' then
        self:clearFocus()
    else
        if key == 'backspace' and self.gooi.focused.indexCursor == 0 then
            return true
        end
        self.gooi.keypressed(key, scancode, isRepeat)
        -- Use the host's repeated key events; Play need not patch main.lua to
        -- forward keyreleased, and focus loss cannot leave a repeating delete.
        self.gooi.keyreleased(key, scancode)
    end
    return true
end
function Ui:keyreleased(key, scancode)
    if self.gooi then
        self.gooi.keyreleased(key, scancode)
    end
end
function Ui:textinput(text)
    if not self:hasTextFocus() then
        return false
    end
    for i = 1, self.utf8.utf8len(text) do
        self.gooi.textinput(self.utf8.utf8sub(text, i, i))
    end
    return true
end
function Ui:update(dt)
    if self.gooi then
        self.gooi.update(dt)
    end
end

function Ui:draw(rect)
    if not self.gooi or #self.gooi.components == 0 then
        return
    end
    local g = love.graphics
    local previousCanvas = g.getCanvas()
    g.push('all')
    g.setCanvas({ self.gooi.canvas, stencil = true })
    g.origin()
    g.setScissor()
    g.clear(0, 0, 0, 0)
    g.setBlendMode('alpha')
    self.gooi.draw()
    g.setCanvas(previousCanvas)
    g.pop()
    local target = rect or self:layout()
    g.push('all')
    g.setColor(1, 1, 1, 1)
    g.setBlendMode('alpha', 'premultiplied')
    g.draw(self.gooi.canvas, target.x, target.y, 0, target.w / self.width, target.h / self.height)
    g.pop()
end

function Ui:destroy()
    self:cancelInput()
    if self.gooi then
        self.gooi.canvas:release()
    end
    self.gooi = nil
    self.utf8 = nil
    self.widgets, self.names, self.handlers = {}, {}, {}
end

return Ui

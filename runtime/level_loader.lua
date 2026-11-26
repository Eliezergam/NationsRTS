local Loader = {}
local Transform = require('runtime.transform')
local Terrain = require('runtime.terrain')
local Projection = require('runtime.projection')
local Patrol = require('runtime.patrol')
local World = require('runtime.world')

-- Carga el script de un objeto. Devuelve el modulo, o nil y el motivo.
-- Se prueba tal cual, sin extension y con la raiz del proyecto por delante, porque
-- `object.script` se guarda relativo al proyecto ('scripts/torreta.lua').
local scriptCache = {}
function Loader.loadScript(path, options)
    options = options or {}
    if type(path) ~= 'string' or path:gsub('%s', '') == '' then
        return nil, 'Ruta de script vacia'
    end
    if options.scripts and options.scripts[path] then
        return options.scripts[path]
    end
    -- `scriptRoot`: carpeta del proyecto cuando el nivel se carga desde fuera de el (el Play del
    -- editor). Ahi 'scripts/misil.lua' no es relativo al juego sino a esa carpeta.
    local root = options.scriptRoot and options.scriptRoot:gsub('/+$', '') or nil
    local key = (root or '') .. '|' .. path
    if scriptCache[key] ~= nil then
        if scriptCache[key] == false then
            return nil, 'No se pudo cargar ' .. path
        end
        return scriptCache[key]
    end
    local function fromFile(absolute)
        local file = io.open(absolute, 'rb')
        if not file then
            return false
        end
        local data = file:read('*a')
        file:close()
        local chunk, err = loadstring(data, '@' .. absolute)
        if not chunk then
            return false, err
        end
        return pcall(chunk)
    end
    local ok, result = false, nil
    if root and path:sub(1, 1) ~= '/' then
        ok, result = fromFile(root .. '/' .. path)
    end
    if not ok then
        local module = ('%s'):format(path):gsub('%.lua$', ''):gsub('^%./', ''):gsub('/', '.')
        ok, result = pcall(require, module)
    end
    if not ok then
        local chunk = love and love.filesystem and love.filesystem.load and select(1, love.filesystem.load(path))
        if chunk then
            ok, result = pcall(chunk)
        end
    end
    if not ok then
        ok, result = fromFile(path)
    end -- ruta absoluta (script elegido sin proyecto)
    if not ok or type(result) ~= 'table' then
        scriptCache[key] = false
        local detail = (type(result) == 'string' and result ~= '') and (': ' .. result) or ''
        return nil, 'No se pudo cargar ' .. path .. detail
    end
    scriptCache[key] = result
    return result
end

function Loader.clearScriptCache()
    scriptCache = {}
end

local function copyValue(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copyValue(v)
    end
    return out
end

-- Los puntos del poligono ya salen girados por `collider.rot` y desplazados por
-- `collider.ox, collider.oy`; sin bloque son los de siempre.
local function polygonVertices(o)
    return Transform.colliderPoints(o)
end
local function polygonArea(points)
    local area = 0
    for i = 1, #points, 2 do
        local j = i + 2
        if j > #points then
            j = 1
        end
        area = area + points[i] * points[j + 1] - points[j] * points[i + 1]
    end
    return area / 2
end
local function isConvex(points)
    if #points < 6 then
        return false
    end
    local sign = 0
    for i = 1, #points, 2 do
        local i2 = i + 2
        if i2 > #points then
            i2 = 1
        end
        local i3 = i + 4
        if i3 > #points then
            i3 = i3 - #points
        end
        local ax, ay = points[i], points[i + 1]
        local bx, by = points[i2], points[i2 + 1]
        local cx, cy = points[i3], points[i3 + 1]
        local cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
        if math.abs(cross) > 0.0001 then
            local s = cross > 0 and 1 or -1
            if sign == 0 then
                sign = s
            elseif sign ~= s then
                return false
            end
        end
    end
    return math.abs(polygonArea(points)) > 0.0001
end
-- El cuerpo sigue en `o.x, o.y` con angulo `o.rotation`; la forma se coloca
-- dentro de el con su propio desplazamiento, giro y tamano. Sin bloque
-- `collider` sale ox=oy=rot=0 y estas llamadas equivalen exactamente a
-- `newRectangleShape(w,h)` y `newCircleShape(r)`, que es lo que habia antes.
local function makePhysicsShape(o)
    local ox, oy, rot, w, h, r = Transform.collider(o)
    if o.shape == 'circle' then
        return love.physics.newCircleShape(ox, oy, r), 'circle'
    end
    if o.shape == 'polygon' then
        local points = polygonVertices(o)
        local unpacker = unpack or table.unpack
        if #points >= 6 and #points <= 16 and isConvex(points) and love.physics.newPolygonShape then
            local ok, shape = pcall(love.physics.newPolygonShape, unpacker(points))
            if ok then
                return shape, 'polygon'
            end
        end
        if #points >= 4 and love.physics.newChainShape then
            local ok, shape = pcall(love.physics.newChainShape, true, unpacker(points))
            if ok then
                return shape, 'chain'
            end
        end
    end
    return love.physics.newRectangleShape(ox, oy, w, h, rot), 'rectangle'
end
local function loadTable(path)
    local chunk, err = love.filesystem.load(path)
    if not chunk then
        return nil, err
    end
    local ok, map = pcall(chunk)
    if not ok then
        return nil, map
    end
    return map
end
function Loader.loadData(map, options)
    options = options or {}
    if not map then
        return nil, 'Mapa invalido'
    end
    local physics = map.physics or {}
    local physicsEnabled = physics.enabled ~= false
    local gx = physics.gravityX
    if gx == nil then
        gx = (map.properties and map.properties.gravityX) or 0
    end
    local gy = physics.gravityY
    if gy == nil then
        gy = (map.properties and map.properties.gravityY) or 0
    end
    if physics.meter and love.physics and love.physics.setMeter then
        love.physics.setMeter(physics.meter)
    end
    local world = options.world
    if not world and physicsEnabled and love.physics then
        world = love.physics.newWorld(gx, gy, physics.sleep ~= false)
    end
    local result = {
        data = map,
        world = world,
        -- Humo, fuego y explosiones (runtime/effects.lua). Los scripts lo usan
        -- como `self.world.level.effects`. Sin gráficos (pruebas) no hay efectos.
        effects = (love and love.graphics and love.graphics.newParticleSystem) and require('runtime.effects').new(map)
            or nil,
        sprites = {},
        bodies = {},
        entities = {},
        bodyForObject = {},
        drawItems = {},
        images = {},
        scriptErrors = {},
    }
    local scripted = {}
    function result:getImage(path)
        -- Un sprite sin imagen asignada no debe tumbar el juego: se dibuja como
        -- nada y el resto del nivel sigue funcionando.
        if path == nil or path == '' then
            return false
        end
        if self.images[path] == nil then
            local ok, img
            if options.getImage then
                img = options.getImage(path)
                ok = img ~= nil
            else
                ok, img = pcall(require('runtime.images').load, path)
            end
            self.images[path] = ok and img or false
        end
        return self.images[path]
    end
    local function addSprite(o, layer)
        if o.type ~= 'sprite' then
            return nil
        end
        local entry = { data = o, image = result:getImage(o.asset), layer = layer }
        result.sprites[#result.sprites + 1] = entry
        result.drawItems[#result.drawItems + 1] = entry
        return entry
    end
    local function hasCollider(o)
        return o.type == 'collision' or o.collisionEnabled or (o.bodyType and o.bodyType ~= 'none')
    end
    local function addBody(o)
        if not physicsEnabled or not world or not hasCollider(o) then
            return nil
        end
        if result.bodyForObject[o] then
            return result.bodyForObject[o]
        end
        local body =
            love.physics.newBody(world, o.x, o.y, (not o.bodyType or o.bodyType == 'none') and 'static' or o.bodyType)
        body:setAngle(o.rotation or 0)
        local shape, actualShape = makePhysicsShape(o)
        local fixture = love.physics.newFixture(body, shape, o.density or 1)
        fixture:setFriction(o.friction or 0.4)
        fixture:setRestitution(o.restitution or 0)
        fixture:setSensor(o.sensor or false)
        fixture:setUserData(o)
        if fixture.setCategory and o.categoryBits then
            pcall(function()
                fixture:setCategory(o.categoryBits)
            end)
        end
        if fixture.setMask and o.maskBits then
            pcall(function()
                fixture:setMask(o.maskBits)
            end)
        end
        if fixture.setGroupIndex and o.groupIndex then
            pcall(function()
                fixture:setGroupIndex(o.groupIndex)
            end)
        end
        result.bodies[#result.bodies + 1] =
            { body = body, shape = shape, fixture = fixture, data = o, actualShape = actualShape }
        result.bodyForObject[o] = body
        return body
    end
    local function addRuntimeEntity(o)
        if o.entityType and options.factories and options.factories[o.entityType] then
            result.entities[#result.entities + 1] = options.factories[o.entityType](o)
        elseif o.entityType == 'patrol' then
            local entity = Patrol.new(o, result.bodyForObject[o])
            if entity then
                result.entities[#result.entities + 1] = entity
            end
        end
    end
    local function addScript(o)
        if not o.script then
            return nil
        end
        local module, err = Loader.loadScript(o.script, options)
        local node = result.scene and result.scene:nodeFor(o)
        if not module then
            result.scriptErrors[#result.scriptErrors + 1] = { object = o, script = o.script, message = err }
            return nil
        end
        local factory = module.new or module.load or (type(module) == 'function' and module)
        local ok, entity = pcall(factory, node, result.scene, o.scriptParams or {})
        if not ok then
            result.scriptErrors[#result.scriptErrors + 1] =
                { object = o, script = o.script, message = tostring(entity) }
            return nil
        end
        if type(entity) == 'table' then
            entity.object = entity.object or o
            result.entities[#result.entities + 1] = entity
        end
        return entity
    end
    local function firstObjectLayer()
        for _, layer in ipairs(map.layers or {}) do
            if layer.kind ~= 'tiles' and type(layer.objects) == 'table' then
                return layer
            end
        end
        return nil
    end
    local function spawnLayer(props)
        props = props or {}
        map.layers = map.layers or {}
        if type(props.layer) == 'table' then
            props.layer.objects = props.layer.objects or {}
            return props.layer
        end
        local index = tonumber(props.layerIndex)
        if index and map.layers[index] then
            local layer = map.layers[index]
            layer.objects = layer.objects or {}
            return layer
        end
        local layerName = props.layer or props.folder
        local wanted = type(layerName) == 'string' and layerName:gsub('^%s+', ''):gsub('%s+$', '') or ''
        if wanted ~= '' then
            for _, layer in ipairs(map.layers) do
                if layer.name == wanted then
                    layer.objects = layer.objects or {}
                    return layer
                end
            end
        else
            local layer = firstObjectLayer()
            if layer then
                return layer
            end
            wanted = 'Spawned'
        end
        local layer = { name = wanted, kind = 'objects', visible = true, locked = false, opacity = 1, objects = {} }
        map.layers[#map.layers + 1] = layer
        return layer
    end
    local function imageSize(asset, props)
        local w, h = tonumber(props.w), tonumber(props.h)
        if w and h then
            return w, h
        end
        local image = asset and result:getImage(asset) or nil
        if image and image.getWidth and image.getHeight then
            w = w or image:getWidth()
            h = h or image:getHeight()
        end
        return w or 32, h or 32
    end
    local function objectName(asset)
        local name = tostring(asset or 'Spawn'):match('[^/]+$') or 'Spawn'
        return (name:gsub('%.[%w_%-]+$', ''))
    end
    function result:spawnObject(asset, x, y, props)
        props = type(props) == 'table' and props or {}
        asset = asset or props.asset
        if type(asset) ~= 'string' or asset:gsub('%s', '') == '' then
            return nil, 'asset vacio'
        end
        local layer = spawnLayer(props)
        local object = {
            type = props.type or 'sprite',
            name = props.name or objectName(asset),
            asset = asset,
            x = tonumber(x) or tonumber(props.x) or 0,
            y = tonumber(y) or tonumber(props.y) or 0,
            rotation = tonumber(props.rotation or props.angle) or 0,
            scaleX = tonumber(props.scaleX) or 1,
            scaleY = tonumber(props.scaleY) or 1,
            collisionEnabled = props.collisionEnabled == true,
            bodyType = props.bodyType or 'none',
            shape = props.shape or 'rectangle',
            sensor = props.sensor == true,
            friction = tonumber(props.friction) or 0.4,
            restitution = tonumber(props.restitution) or 0,
            density = tonumber(props.density) or 1,
            categoryBits = props.categoryBits,
            maskBits = props.maskBits,
            groupIndex = props.groupIndex,
            properties = copyValue(props.properties or {}),
        }
        object.w, object.h = imageSize(asset, props)
        for key, value in pairs(props) do
            if key ~= 'layer' and key ~= 'layerIndex' and key ~= 'folder' and key ~= 'x' and key ~= 'y' then
                object[key] = copyValue(value)
            end
        end
        object.asset = asset
        layer.objects = layer.objects or {}
        layer.objects[#layer.objects + 1] = object
        addSprite(object, layer)
        addBody(object)
        addRuntimeEntity(object)
        local node
        if self.scene and self.scene.addObject then
            node = self.scene:addObject(layer, object)
        elseif self.scene then
            self.scene:rebuild()
            node = self.scene:nodeFor(object)
        end
        addScript(object)
        return node or object
    end
    for _, layer in ipairs(map.layers or {}) do
        if layer.visible ~= false then
            if layer.tiles or layer.paint then
                result.drawItems[#result.drawItems + 1] = { terrain = layer }
            end
            for _, o in ipairs(layer.objects or {}) do
                addSprite(o, layer)
                addBody(o)
                addRuntimeEntity(o)
                if o.script then
                    scripted[#scripted + 1] = o
                end
            end
        end
    end
    if physicsEnabled and world and physics.bounds then
        local tile = Terrain.size(map)
        local mw = (map.width or 100) * tile
        local mh = (map.height or 60) * tile
        local t = physics.boundsThickness or tile
        local function addBound(name, x, y, w, h)
            local data = { type = 'mapBoundary', name = name }
            local body = love.physics.newBody(world, x, y, 'static')
            local shape = love.physics.newRectangleShape(w, h)
            local fixture = love.physics.newFixture(body, shape, 1)
            fixture:setUserData(data)
            result.bodies[#result.bodies + 1] = { body = body, shape = shape, fixture = fixture, data = data }
        end
        addBound('top', mw / 2, -t / 2, mw, t)
        addBound('bottom', mw / 2, mh + t / 2, mw, t)
        addBound('left', -t / 2, mh / 2, t, mh)
        addBound('right', mw + t / 2, mh / 2, t, mh)
    end
    -- `result.world` es el mundo de love.physics; el acceso por nombre vive en `result.scene`.
    result.scene = World.new(result)
    -- Navegacion por rutas dibujadas (runtime/nv): solo si el mapa trae redes. Cada objeto
    -- con `navigation.tag` recibe un NavigationAgent (entidad con update) al que llega por
    -- `node.navigation`; `result.navigationDebug` (flags) enciende el dibujo de depuracion.
    -- Las rutas van por el planificador del manager (presupuesto por cuadro) y los vecinos
    -- de la esquiva salen del indice de agentes (`navigation.agentIndex`), que `update`
    -- sincroniza una vez por cuadro antes de mover a nadie (`navigation:beginFrame`).
    -- LOD de navegacion (fase F): el foco del manager es lo que se ve. Con
    -- `result.navigationCamera` (la pone `runtime/units.lua`) es `camera:visibleRect()`;
    -- si no, el rectangulo del ultimo `draw` (el `bounds` que se le pase, o lo que cubre la
    -- transformacion de `love.graphics` al dibujar, como en el Play del editor). Sin dibujar
    -- nunca no hay foco y todos los agentes van a tope. `options.navigation.lod = false` lo apaga.
    result.agents = {}
    result.agentList = {}
    if type(map.navigation) == 'table' and type(map.navigation.systems) == 'table' and #map.navigation.systems > 0 then
        local NV = require('runtime.nv')
        local navigation = NV.load(map, options.navigation)
        result.navigation = navigation
        -- Limites y colision estatica para validar los puestos de los grupos: los muros del
        -- mapa (`physics.bounds`) marcan el rectangulo, y los cuerpos estaticos del mundo
        -- (edificios, colisiones dibujadas) bloquean; las unidades y sus agentes no cuentan.
        if physics.bounds then
            local tile = Terrain.size(map)
            navigation.bounds = { x = 0, y = 0, w = (map.width or 100) * tile, h = (map.height or 60) * tile }
        end
        if world and world.queryBoundingBox then
            navigation.blocked = function(x, y, r)
                local hit = false
                world:queryBoundingBox(x - r, y - r, x + r, y + r, function(fixture)
                    local body = fixture:getBody()
                    local data = fixture:getUserData()
                    local unit = type(data) == 'table'
                        and (result.agents[data] or (data.rts and data.rts.role == 'unit'))
                    if body:getType() == 'static' and not fixture:isSensor() and not unit then
                        hit = true
                        return false
                    end
                    return true
                end)
                return hit
            end
        end
        local profiler = navigation.profiler
        for _, node in ipairs(result.scene:objects()) do
            local o = node.data
            local props = NV.agentProps(o)
            if props then
                local agent = NV.Agent.new(navigation, node, props)
                result.agents[o] = agent
                result.agentList[#result.agentList + 1] = agent
                result.entities[#result.entities + 1] = {
                    object = o,
                    agent = agent,
                    update = function(_, dt)
                        local t = profiler:start()
                        agent:update(dt)
                        profiler:finish('agents', t)
                    end,
                }
            end
        end
        result.entities[#result.entities + 1] = {
            navigationDebug = true,
            draw = function()
                local flags = result.navigationDebug
                if flags and NV.Debug.anyActive(flags) then
                    NV.Debug.draw(
                        result.navigation,
                        flags,
                        { agents = result.agentList, zoom = result.navigationDebugZoom }
                    )
                end
            end,
        }
    end
    for _, o in ipairs(scripted) do
        addScript(o)
    end
    function result:update(dt)
        for _, e in ipairs(self.entities) do
            if e.beforePhysics then
                e:beforePhysics(dt)
            end
        end
        if self.world then
            self.world:update(dt)
        end
        local navigation = self.navigation
        if navigation then
            self:updateNavigationFocus()
            navigation:beginFrame(self.agentList)
        end
        for _, e in ipairs(self.entities) do
            if e.update then
                e:update(dt)
            end
        end
        if navigation then
            navigation:endFrame()
        end
        if self.effects then
            self.effects:update(dt)
        end
    end
    --- Foco del LOD de navegacion para este cuadro: la camara de `navigationCamera` o el
    -- ultimo rectangulo dibujado (`navigationView`); sin ninguno, no lo toca.
    function result:updateNavigationFocus()
        local navigation = self.navigation
        if not navigation or not navigation.setFocus then
            return
        end
        local camera = self.navigationCamera
        if camera and type(camera.visibleRect) == 'function' then
            navigation:setFocus(camera:visibleRect())
        elseif self.navigationView then
            navigation:setFocus(self.navigationView)
        end
    end
    -- Rectangulo de mundo que se ve al dibujar: `bounds` si viene, o las esquinas de la zona
    -- de dibujo (el scissor, o la ventana) llevadas al mundo con la transformacion actual.
    local function rememberView(level, bounds)
        local view = level.navigationView or {}
        if type(bounds) == 'table' and tonumber(bounds.x) and tonumber(bounds.y) and tonumber(bounds.w) then
            view.x, view.y = bounds.x, bounds.y
            view.w, view.h = bounds.w, tonumber(bounds.h) or bounds.w
            level.navigationView = view
            return
        end
        local g = love and love.graphics
        if not (g and g.inverseTransformPoint and g.getDimensions and g.getScissor) then
            return
        end
        local sx, sy, sw, sh = g.getScissor()
        if not sx then
            sx, sy = 0, 0
            sw, sh = g.getDimensions()
        end
        local ax, ay = g.inverseTransformPoint(sx, sy)
        local bx, by = g.inverseTransformPoint(sx + sw, sy + sh)
        view.x, view.y = math.min(ax, bx), math.min(ay, by)
        view.w, view.h = math.abs(bx - ax), math.abs(by - ay)
        level.navigationView = view
    end
    -- `bounds` es opcional: el rectangulo de mundo que se esta viendo, normalmente
    -- `camera:visibleRect()`. Solo recorta el terreno, que es lo que se cuenta por
    -- cientos de miles de celdas; sin el se dibuja todo, como siempre. Con navegacion,
    -- tambien es el foco del LOD del cuadro siguiente.
    function result:draw(bounds)
        if self.navigation then
            rememberView(self, bounds)
        end
        local levelMap = self.data
        local iso = Projection.isIso(levelMap)
        Projection.current = levelMap
        local function spritePosition(s)
            local o = s.data
            local body = self.bodyForObject[o]
            if body then
                local x, y = body:getPosition()
                return x, y, body:getAngle()
            end
            return o.x, o.y, o.rotation or 0
        end
        local function drawSprite(s)
            local o = s.data
            local x, y, a = spritePosition(s)
            -- Lo que vuela (`o.z`) lleva su sombra en el suelo, debajo.
            if (o.z or 0) > 0.5 then
                local c = type(o.collider) == 'table' and o.collider or {}
                local radius = math.max(6, (tonumber(c.w) or tonumber(c.r) or 16) * 0.35)
                Projection.drawShadow(levelMap, x, y, radius, o.z)
            end
            love.graphics.setColor(1, 1, 1, s.layer.opacity or 1)
            Projection.drawSprite(levelMap, s.image, o.asset, x, y, a, o.scaleX or 1, o.scaleY or 1, o.z, o.pitch)
        end
        -- En isométrico lo que está de pie se ordena por profundidad cada cuadro
        -- (las unidades se mueven), dentro de cada tramo de sprites entre capas
        -- de terreno.
        local run = {}
        local function flush()
            if #run == 0 then
                return
            end
            if iso then
                Projection.sortByDepth(levelMap, run, function(s)
                    local x, y = spritePosition(s)
                    return x, y, s.data.z
                end)
            end
            for _, s in ipairs(run) do
                drawSprite(s)
            end
            run = {}
        end
        for _, s in ipairs(self.drawItems) do
            if s.terrain then
                flush()
                Terrain.draw(self.data, s.terrain, function(path)
                    return self:getImage(path)
                end, bounds)
            elseif s.image then
                run[#run + 1] = s
            end
        end
        flush()
        for _, e in ipairs(self.entities) do
            if e.draw then
                e:draw()
            end
        end
        if self.effects then
            self.effects:draw()
        end
    end
    return result
end
function Loader.load(path, options)
    options = options or {}
    local map, err = loadTable(path)
    if not map then
        return nil, err
    end
    return Loader.loadData(map, options)
end
return Loader

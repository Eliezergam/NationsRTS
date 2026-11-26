-- Efectos del nivel: humo, fuego y explosiones con partículas de LÖVE.
--
-- Cada nivel tiene su sistema (`level.effects`), que actualiza y dibuja el
-- propio nivel. Un script lo usa desde su mundo:
--
--   local efectos = self.world.level.effects
--   efectos:trail(x, y, z)        -- una bocanada de humo con chispa (estela)
--   efectos:explosion(x, y, z)    -- fogonazo, fuego, humo y restos
--   efectos:puff(x, y, z)         -- nube pequeña (algo que se apaga)
--
-- `x, y` son de mundo y `z` es la altura sobre el terreno, como la de los
-- objetos. Las partículas viven en el plano de la vista: en isométrico el humo
-- sube derecho en la pantalla, que es como se ve el humo real desde arriba.

local Projection = require('runtime.projection')

local Effects = {}
Effects.__index = Effects

local softTexture

--- Textura de partícula: un círculo de borde suave, generado una sola vez.
local function particleTexture()
    if not softTexture then
        local size = 32
        local data = love.image.newImageData(size, size)
        data:mapPixel(function(x, y)
            local dx, dy = (x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1
            local d = math.sqrt(dx * dx + dy * dy)
            local a = math.max(0, 1 - d)
            return 1, 1, 1, a * a * (3 - 2 * a)
        end)
        softTexture = love.graphics.newImage(data)
    end
    return softTexture
end

local function system(buffer, setup)
    local ps = love.graphics.newParticleSystem(particleTexture(), buffer)
    ps:setEmissionRate(0)
    ps:setEmitterLifetime(-1)
    setup(ps)
    ps:start()
    return ps
end

--- Sistema de efectos para un mapa (el nivel lo crea con `level.data`).
function Effects.new(map)
    local self = setmetatable({ map = map, flashes = {} }, Effects)
    self.smoke = system(2000, function(ps)
        ps:setParticleLifetime(1.1, 2.2)
        ps:setSizes(0.35, 0.9, 1.4)
        ps:setSizeVariation(0.5)
        ps:setColors(0.92, 0.92, 0.9, 0.55, 0.85, 0.84, 0.82, 0.35, 0.8, 0.78, 0.76, 0)
        ps:setLinearAcceleration(-4, -22, 4, -10)
        ps:setLinearDamping(1.2)
        ps:setSpread(math.pi * 2)
        ps:setSpeed(0, 10)
        ps:setSpin(-0.6, 0.6)
    end)
    self.sparks = system(600, function(ps)
        ps:setParticleLifetime(0.08, 0.2)
        ps:setSizes(0.45, 0.2)
        ps:setColors(1, 0.95, 0.6, 1, 1, 0.55, 0.15, 0.8, 1, 0.3, 0.05, 0)
        ps:setSpread(math.pi * 2)
        ps:setSpeed(0, 30)
    end)
    self.fire = system(800, function(ps)
        ps:setParticleLifetime(0.25, 0.6)
        ps:setSizes(0.5, 1.2, 0.6)
        ps:setSizeVariation(0.6)
        ps:setColors(1, 0.95, 0.55, 1, 1, 0.55, 0.12, 0.9, 0.8, 0.2, 0.05, 0.6, 0.3, 0.1, 0.05, 0)
        ps:setSpread(math.pi * 2)
        ps:setSpeed(40, 170)
        ps:setLinearDamping(3.5)
        ps:setLinearAcceleration(0, -60, 0, -20)
    end)
    self.darkSmoke = system(800, function(ps)
        ps:setParticleLifetime(1.2, 2.6)
        ps:setSizes(0.8, 1.8, 2.6)
        ps:setSizeVariation(0.5)
        ps:setColors(0.3, 0.27, 0.25, 0.75, 0.42, 0.4, 0.38, 0.45, 0.55, 0.53, 0.5, 0)
        ps:setSpread(math.pi * 2)
        ps:setSpeed(20, 80)
        ps:setLinearDamping(2.2)
        ps:setLinearAcceleration(-6, -34, 6, -18)
        ps:setSpin(-0.8, 0.8)
    end)
    self.debris = system(300, function(ps)
        ps:setParticleLifetime(0.5, 1.1)
        ps:setSizes(0.18, 0.12)
        ps:setColors(0.22, 0.18, 0.15, 1, 0.22, 0.18, 0.15, 0)
        ps:setSpread(math.pi * 2)
        ps:setSpeed(90, 220)
        ps:setLinearAcceleration(0, 280, 0, 320)
        ps:setLinearDamping(0.6)
    end)
    self.systems = { self.smoke, self.darkSmoke, self.fire, self.sparks, self.debris }
    return self
end

--- Punto de la vista de algo a altura `z` sobre el terreno en `x, y`.
function Effects:viewPoint(x, y, z)
    local vx, vy = Projection.toViewGround(self.map, x, y)
    return vx, vy - Projection.lift(self.map, z or 0)
end

local function emitAt(ps, vx, vy, count)
    ps:setPosition(vx, vy)
    ps:emit(count)
end

--- Una bocanada de estela (llamar cada cuadro mientras algo vuela).
function Effects:trail(x, y, z)
    local vx, vy = self:viewPoint(x, y, z)
    emitAt(self.smoke, vx, vy, 1)
    emitAt(self.sparks, vx, vy, 2)
end

--- Nube pequeña: algo que se apaga o se queda sin combustible.
function Effects:puff(x, y, z)
    local vx, vy = self:viewPoint(x, y, z)
    emitAt(self.darkSmoke, vx, vy, 6)
end

--- Explosión: fogonazo, bola de fuego, humo oscuro y restos.
function Effects:explosion(x, y, z, size)
    size = size or 1
    local vx, vy = self:viewPoint(x, y, z)
    emitAt(self.fire, vx, vy, math.floor(40 * size))
    emitAt(self.darkSmoke, vx, vy, math.floor(18 * size))
    emitAt(self.debris, vx, vy, math.floor(16 * size))
    emitAt(self.sparks, vx, vy, math.floor(20 * size))
    self.flashes[#self.flashes + 1] = { x = vx, y = vy, age = 0, life = 0.18, radius = 46 * size }
end

function Effects:update(dt)
    for _, ps in ipairs(self.systems) do
        ps:update(dt)
    end
    for index = #self.flashes, 1, -1 do
        local flash = self.flashes[index]
        flash.age = flash.age + dt
        if flash.age >= flash.life then
            table.remove(self.flashes, index)
        end
    end
end

--- ¿Queda algo vivo que dibujar?
function Effects:active()
    for _, ps in ipairs(self.systems) do
        if ps:getCount() > 0 then
            return true
        end
    end
    return #self.flashes > 0
end

--- Dibuja con la transformación de mundo puesta (dentro de la cámara).
function Effects:draw()
    if not self:active() then
        return
    end
    local g = love.graphics
    local shader = g.getShader()
    g.setShader()
    g.push()
    if Projection.isIso(self.map) then
        local _, inverse = Projection.isoTransform()
        g.applyTransform(inverse)
    end
    g.setColor(1, 1, 1, 1)
    g.draw(self.smoke)
    g.draw(self.darkSmoke)
    -- El fuego y las chispas suman luz.
    local mode, alpha = g.getBlendMode()
    g.setBlendMode('add')
    for _, flash in ipairs(self.flashes) do
        local t = flash.age / flash.life
        g.setColor(1, 0.8, 0.45, 0.85 * (1 - t))
        g.circle('fill', flash.x, flash.y, flash.radius * (0.6 + 0.6 * t))
    end
    g.setColor(1, 1, 1, 1)
    g.draw(self.fire)
    g.draw(self.sparks)
    g.setBlendMode(mode, alpha)
    g.draw(self.debris)
    g.pop()
    g.setShader(shader)
end

return Effects

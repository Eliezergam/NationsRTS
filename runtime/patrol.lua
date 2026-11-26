-- Small opt-in example behavior shared by editor Play and exported games.
-- Positions belong to Box2D; this controller only supplies velocity.
local Patrol = {}
Patrol.__index = Patrol

local function number(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then
        return fallback
    end
    return value
end

function Patrol.new(object, body)
    if not body or body:getType() ~= 'dynamic' or object.sensor then
        return nil
    end
    local properties = object.properties or {}
    local dx = number(properties.patrolDx, 192)
    local dy = number(properties.patrolDy, 0)
    local speed = math.max(0, number(properties.patrolSpeed, 96))
    if dx * dx + dy * dy < 0.0001 or speed == 0 then
        return nil
    end
    local x, y = body:getPosition()
    body:setFixedRotation(true)
    body:setBullet(true)
    return setmetatable({
        data = object,
        body = body,
        speed = speed,
        points = { { x = x, y = y }, { x = x + dx, y = y + dy } },
        target = 2,
        pause = math.max(0, number(properties.patrolPause, 0.35)),
        waiting = 0,
        touching = false,
        collisions = 0,
        turns = 0,
    }, Patrol)
end

function Patrol:turn()
    self.target = 3 - self.target
    self.turns = self.turns + 1
    self.waiting = self.pause
end

function Patrol:beforePhysics(dt)
    if self.body:isDestroyed() or dt <= 0 then
        return
    end
    if self.waiting > 0 then
        self.waiting = math.max(0, self.waiting - dt)
        self.body:setLinearVelocity(0, 0)
        return
    end
    local x, y = self.body:getPosition()
    local point = self.points[self.target]
    local dx, dy = point.x - x, point.y - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.5 then
        self:turn()
        self.body:setLinearVelocity(0, 0)
        return
    end
    local speed = math.min(self.speed, distance / dt)
    self.body:setLinearVelocity(dx / distance * speed, dy / distance * speed)
end

function Patrol:update()
    if self.body:isDestroyed() then
        return
    end
    local touching = false
    for _, contact in ipairs(self.body:getContacts()) do
        if contact:isTouching() and contact:isEnabled() then
            local a, b = contact:getFixtures()
            if not a:isSensor() and not b:isSensor() then
                touching = true
                break
            end
        end
    end
    -- React after the physics step has resolved the impact. Do not replace the
    -- world's callbacks: games may already use them for damage, sound or scores.
    if touching and not self.touching then
        self.collisions = self.collisions + 1
        self:turn()
    end
    self.touching = touching
end

return Patrol

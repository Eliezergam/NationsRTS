local loader = require('runtime.level_loader')
local rts = require('runtime.rts')
function love.load()
    level, err = loader.load('exports/level_01.lua')
    if level then
        game = rts.new(level)
    end
end
function love.update(dt)
    if level then
        level:update(dt)
    end
end
function love.draw()
    if level then
        level:draw()
    else
        love.graphics.print(err or 'Exporta level_01 primero', 20, 20)
    end
end

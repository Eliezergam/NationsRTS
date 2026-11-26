function love.conf(t)
    t.identity = 'nationsrts'
    t.version = '11.5'
    t.window.title = 'Nations RTS'
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.msaa = 4
    -- Buffer de profundidad para los tanques en 3D (mundo/modelos3d.lua).
    t.window.depth = 24
end

-- Modo por defecto (NationsRTS, dueño 2026-09-29): modo jugador y motor
-- 3DreamEngine para la batalla 3D. Las flags se imponen siempre en
-- `love.load` (main.lua:262) para que un agente que solo haga `love .`
-- arranque en el modo correcto sin tener que acordarse.

-- Práctica del soldado en el almacén. Lo hace como el robot pequeño: primero
-- explora la nave con su lidar (exploracion.lua) y aprende su mapa; después
-- va a sitios de la nave que conoce, cada vez uno distinto, con la misma
-- navegación (ruta por el mapa, la rehace si algo se la corta, frena ante lo
-- que no esperaba) y se para un momento al llegar.

local Practica = {}

Practica.distancia = { 6, 30 } -- m: lo cerca y lo lejos de cada destino
Practica.pausa = { 1.0, 3.0 } -- s parado al llegar
Practica.intentos = 60

function Practica:onLoad()
    local d = self.datos.practicaSoldado
    d.espera = 0
    d.destinos = 0
end

--- Un sitio libre que su mapa conoce, entre `distancia` m de donde está.
local function destinoNuevo(self)
    local mapa = self:getMapa()
    local r = mapa.resolucion or 0.1
    for _ = 1, Practica.intentos do
        local a = love.math.random() * 2 * math.pi
        local dist = Practica.distancia[1] + love.math.random() * (Practica.distancia[2] - Practica.distancia[1])
        local x, y = self.x + math.cos(a) * dist, self.y + math.sin(a) * dist
        local cx, cy = mapa:casilla(x, y)
        if mapa:dentro(cx, cy) and mapa.visto[cy * mapa.ancho + cx] ~= 0 and not mapa:getOcupado(x, y) and not mapa:getBloqueado(x, y) then
            return x, y
        end
    end
    return nil
end

function Practica:onUpdate(dt)
    local d = self.datos.practicaSoldado
    if self.getCombatiendo and self:getCombatiendo() then
        local e = self:getObjetivo()
        d.tarea = e and string.format('¡enemigo! %s, vida %d', e:getNombre(), math.max(0, e.vida)) or 'combate'
        return
    end
    -- SOLDADO_QUIETO=1: tiro desde parado (no explora; vigila y dispara
    -- desde donde está, para probar la puntería a varias distancias).
    if os.getenv('SOLDADO_QUIETO') then
        if self:getExplorando() then
            self:setExplorar(false)
        end
        -- Mirando a lo largo de la reserva (+x), donde están los bloques en
        -- fila; los ojos barren a los lados (combate.lua).
        if math.abs(((self.rumbo + math.pi) % (2 * math.pi)) - math.pi) > 0.1 and self:getHaLlegado() then
            self:setIrA(self.x, self.y, 0)
        end
        d.tarea = 'vigilo desde aquí'
        return
    end
    if self:getExplorando() then
        d.tarea = string.format('exploro la nave (me quedan %d fronteras)', self:getFronteras() or 0)
        return
    end
    if self:getNavegando() then
        d.tarea = string.format('practico: voy a %.1f, %.1f (destino %d)', d.x or 0, d.y or 0, d.destinos)
        return
    end
    if d.espera > 0 then
        d.espera = d.espera - dt
        d.tarea = 'parado, miro alrededor'
        return
    end
    local x, y = destinoNuevo(self)
    if x then
        d.x, d.y = x, y
        d.destinos = d.destinos + 1
        self:setNavegarA(x, y)
        d.espera = Practica.pausa[1] + love.math.random() * (Practica.pausa[2] - Practica.pausa[1])
    end
end

GestorRobots.registrarEspecializacion('practicaSoldado', Practica)
return Practica

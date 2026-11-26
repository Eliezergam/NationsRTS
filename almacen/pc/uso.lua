-- Usar un ordenador de la sala de control (el dueño, 26-nov): al acercarse a
-- un puesto sale «E · Usar ordenador»; con E la cámara se acerca al monitor
-- (como en Alien: Isolation) y, al llegar, la pantalla del PC pasa a ser la
-- nuestra: ratón y teclado van a su escritorio (almacen/pc/ordenador.lua).
-- Con Esc se sale al revés:
-- la pantalla se funde con la sala y la cámara vuelve a donde estaba. Lo que
-- se deja abierto sigue en el monitor.
--
-- Los monitores están donde los pone tools/blender/almacen_interior.py
-- (crearPuesto): mesas en x = 4,6 / 7,2 / 9,8 y en y = 8,6 / 11,2; la
-- pantalla, 0,18 m por delante del centro de la mesa, a 1,20 m del suelo,
-- mirando a -y. Puesto 1-3 la fila de delante, 4-6 la de atrás.

local Ordenador = require('almacen.pc.ordenador')
local Dibujo = require('almacen.pc.dibujo')

local UsoPC = {}
UsoPC.__index = UsoPC

UsoPC.puestosX = { 4.6, 7.2, 9.8 }
UsoPC.filasY = { 8.6, 11.2 }
UsoPC.adelantePantalla = 0.2 - 0.0185
UsoPC.alturaPantalla = 0.86 + 0.34
UsoPC.cerca = 1.9 -- m de la cámara a la pantalla para que salga la tecla
UsoPC.acercar = 0.75 -- s de viaje de la cámara
UsoPC.fundido = 0.25 -- s del fundido entre la sala y la pantalla
-- Distancia a la que la pantalla (0,34 m de alto) llena la vista con el
-- campo de 65° de la cámara del almacén: 0,17 / tan(32,5°) = 0,27 m.
UsoPC.distanciaFinal = 0.29
UsoPC.teclaUsar = 'e'

--- `escena`: la del almacén (cámara en x, y = altura, z = -y del almacén).
function UsoPC.nuevo(escena)
    local self = setmetatable({}, UsoPC)
    self.escena = escena
    self.estado = nil -- nil, 'entrando', 'dentro' o 'saliendo'
    self.t = 0
    local g = love.graphics
    self.letraAviso = g.newFont('assets/fuentes/BarlowCondensed-SemiBold.ttf', 26)
    return self
end

--- Centro de la pantalla del puesto `k` (metros del almacén).
function UsoPC.pantalla(k)
    local fila = math.floor((k - 1) / 3) + 1
    local columna = (k - 1) % 3 + 1
    return UsoPC.puestosX[columna], UsoPC.filasY[fila] + UsoPC.adelantePantalla, UsoPC.alturaPantalla
end

local function ordenadores(self)
    return self.escena.sala and self.escena.sala.ordenadores or {}
end

--- El puesto al que se está mirando de cerca (número), o nil.
function UsoPC:getCerca()
    local e = self.escena
    local cx, cy, cz = e.x, -e.z, e.y
    local mejor, mejorD
    for k = 1, #ordenadores(self) do
        local x, y, z = UsoPC.pantalla(k)
        -- Delante de la pantalla (que mira a -y), a menos de `cerca`.
        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2)
        if cy < y and d <= UsoPC.cerca and (not mejorD or d < mejorD) then
            mejor, mejorD = k, d
        end
    end
    return mejor
end

function UsoPC:getActivo()
    return self.estado ~= nil
end

--- `true` cuando la pantalla del PC tapa toda la vista (no hace falta pintar
-- la sala).
function UsoPC:getTapaTodo()
    return self.estado == 'dentro' and self.t >= UsoPC.fundido
end

local function suave(f)
    f = math.max(0, math.min(1, f))
    return f * f * (3 - 2 * f)
end

local function angulo(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Pone la cámara de la escena en la fracción `f` del camino entre donde
-- estaba y delante de la pantalla.
function UsoPC:colocarCamara(f)
    local e = self.escena
    local a = self.desde
    local x, y, z = UsoPC.pantalla(self.puesto)
    local bx, by, bz = x, y - UsoPC.distanciaFinal, z
    -- Mirando a +y (a la pantalla), horizontal: rumbo pi/2, inclinación 0.
    local rumbo = a.rumbo + angulo(math.pi / 2 - a.rumbo) * f
    local inclinacion = a.inclinacion * (1 - f)
    e.x = a.x + (bx - a.x) * f
    e.y = a.y + (bz - a.y) * f
    e.z = a.z + (-by - a.z) * f
    e.controlador:orientar(rumbo, inclinacion)
end

function UsoPC:entrar(k)
    local e = self.escena
    local rumbo, inclinacion = e.controlador:angulos()
    self.desde = { x = e.x, y = e.y, z = e.z, rumbo = rumbo, inclinacion = inclinacion }
    self.puesto = k
    self.pc = ordenadores(self)[k]
    self.estado = 'entrando'
    self.t = 0
    e.siguiendo = false
    e.mirando = false
    e.controlador:detener()
    self.repetir = love.keyboard.hasKeyRepeat()
    love.keyboard.setKeyRepeat(true)
    self.pc:setEnUso(true)
    self.pc.cursor = { Ordenador.ancho / 2, Ordenador.alto / 2 }
end

function UsoPC:salir()
    if self.estado == 'dentro' then
        self.estado = 'saliendo'
        self.t = 0
    end
end

local function terminar(self)
    self.estado = nil
    love.keyboard.setKeyRepeat(self.repetir or false)
    love.mouse.setVisible(true)
    self.pc:setEnUso(false)
    self.escena.sala:pintarOrdenador(self.puesto)
    self.escena.controlador:detener()
end

function UsoPC:actualizar(dt)
    if not self.estado then
        return
    end
    self.t = self.t + dt
    if self.estado == 'entrando' then
        self:colocarCamara(suave(self.t / UsoPC.acercar))
        if self.t >= UsoPC.acercar then
            self.estado = 'dentro'
            self.t = 0
            love.mouse.setVisible(false)
            self.desdeDentro = love.timer.getTime()
        end
    elseif self.estado == 'dentro' then
        self:colocarCamara(1)
    elseif self.estado == 'saliendo' then
        love.mouse.setVisible(true)
        local f = 1 - suave((self.t - UsoPC.fundido) / UsoPC.acercar)
        self:colocarCamara(f)
        if self.t >= UsoPC.fundido + UsoPC.acercar then
            terminar(self)
            return
        end
    end
    -- La pantalla del PC en uso se pinta cada cuadro (las demás, cada 0,5 s).
    self.escena.sala:pintarOrdenador(self.puesto)
end

-- Dónde va el lienzo del PC en la ventana: escala y esquina.
local function encaje()
    local W, H = love.graphics.getDimensions()
    local s = math.min(W / Ordenador.ancho, H / Ordenador.alto)
    return s, (W - Ordenador.ancho * s) / 2, (H - Ordenador.alto * s) / 2
end

--- Lo que se pinta encima de la sala: la pantalla del PC (con su fundido)
-- o, sin usar ninguno, el aviso de la tecla.
function UsoPC:dibujar()
    local g = love.graphics
    g.push('all')
    g.origin()
    local W, H = g.getDimensions()
    if self.estado then
        local alfa = 0
        if self.estado == 'entrando' then
            alfa = suave((self.t - (UsoPC.acercar - UsoPC.fundido)) / UsoPC.fundido)
        elseif self.estado == 'dentro' then
            alfa = 1
        elseif self.estado == 'saliendo' then
            alfa = 1 - suave(self.t / UsoPC.fundido)
        end
        if alfa > 0 then
            local s, ox, oy = encaje()
            g.setColor(0, 0, 0, alfa)
            g.rectangle('fill', 0, 0, W, H)
            g.setColor(1, 1, 1, alfa)
            g.draw(self.pc:getLienzo(), ox, oy, 0, s, s)
            -- Cómo salir, los primeros segundos.
            if self.estado == 'dentro' and love.timer.getTime() - (self.desdeDentro or 0) < 4 then
                local texto = 'Esc · salir del ordenador'
                g.setFont(self.letraAviso)
                local tw = self.letraAviso:getWidth(texto) + 28
                g.setColor(0, 0, 0, 0.6)
                g.rectangle('fill', W - tw - 16, 16, tw, 40, 6)
                g.setColor(1, 1, 1, 0.9)
                g.print(texto, W - tw - 2, 22)
            end
        end
    else
        local k = self:getCerca()
        if k then
            -- [E] Usar ordenador · puesto-N (como el de la fábrica).
            local texto = 'Usar ordenador · ' .. ordenadores(self)[k].nombre
            local letra = self.letraAviso
            g.setFont(letra)
            local tw = 14 + 30 + 12 + letra:getWidth(texto) + 18
            local x, y = (W - tw) / 2, H - 110
            g.setColor(0, 0, 0, 0.7)
            g.rectangle('fill', x, y, tw, 46, 8, 8)
            g.setColor(1, 0.85, 0.3, 1)
            g.setLineWidth(2)
            g.rectangle('line', x + 14, y + 8, 30, 30, 4, 4)
            g.printf('E', x + 14, y + 23 - letra:getHeight() / 2, 30, 'center')
            g.setColor(1, 1, 1, 1)
            g.print(texto, x + 56, y + 23 - letra:getHeight() / 2)
        end
    end
    g.pop()
end

-- Entrada ----------------------------------------------------------------------

--- Una tecla. Devuelve true si la ha usado.
function UsoPC:tecla(tecla)
    if self.estado == 'dentro' then
        if tecla == 'escape' then
            self:salir()
        else
            self.pc:tecla(tecla)
        end
        return true
    elseif self.estado then
        return true
    end
    if tecla == UsoPC.teclaUsar then
        local k = self:getCerca()
        if k then
            self:entrar(k)
            return true
        end
    end
    return false
end

function UsoPC:texto(t)
    if self.estado == 'dentro' then
        self.pc:texto(t)
        return true
    end
    return self.estado ~= nil
end

--- Ratón de la ventana (`accion` 'pulsar', 'soltar' o 'mover'). Devuelve
-- true si lo ha usado.
function UsoPC:raton(accion, x, y, boton)
    if self.estado == 'dentro' then
        local s, ox, oy = encaje()
        local px = math.max(0, math.min(Ordenador.ancho - 1, (x - ox) / s))
        local py = math.max(0, math.min(Ordenador.alto - 1, (y - oy) / s))
        self.pc:raton(accion, px, py, boton)
        return true
    end
    return self.estado ~= nil
end

return UsoPC

-- Menú de la fábrica de misiles (pedido del dueño, 2026-11-17): al
-- acercarse a la mesa del puesto 1 sale «E — Fábrica de misiles» abajo en la
-- pantalla; con E se abre un menú normal para elegir cuántos misiles
-- fabricar, fabricarlos o parar la fabricación. E o Esc lo cierran.
--
-- Cada misil cuesta una paca de dinero, una caja de metal y una garrafa de
-- petróleo (MenuFabrica.coste); el menú dice para cuántos alcanza lo que
-- tiene la nación y no deja pedir más de lo que cabe en el polvorín.

local MenuFabrica = {}
MenuFabrica.__index = MenuFabrica

local LETRA_TITULO = 'assets/fuentes/BarlowCondensed-SemiBold.ttf'
local LETRA_DATO = 'assets/fuentes/JetBrainsMono-SemiBold.ttf'

MenuFabrica.coste = require('almacen.fabrica').coste
MenuFabrica.cerca = 3.5 -- m (en el suelo) de la cámara a la mesa para que salga la tecla
MenuFabrica.teclaAbrir = 'e'

local VERDE = { 0.24, 0.9, 0.42 }
local AMBAR = { 1.0, 0.72, 0.2 }
local ROJO = { 1.0, 0.3, 0.2 }
local BLANCO = { 0.92, 0.94, 0.95 }
local GRIS = { 0.7, 0.78, 0.82 }

--- `escena`: la del almacén (su fábrica, su almacén y su cámara); `mesa`:
-- x, y, z de la mesa (assets/almacen/fabrica.lua).
function MenuFabrica.nuevo(escena, mesa)
    local self = setmetatable({}, MenuFabrica)
    self.escena = escena
    self.mesa = mesa
    self.letras = {
        titulo = love.graphics.newFont(LETRA_TITULO, 30),
        dato = love.graphics.newFont(LETRA_DATO, 16),
        boton = love.graphics.newFont(LETRA_TITULO, 22),
        aviso = love.graphics.newFont(LETRA_TITULO, 24),
    }
    self.cantidad = 1
    self.abierto = false
    self.botones = {}
    return self
end

-- Datos ----------------------------------------------------------------------

--- ¿Está la cámara junto a la mesa?
function MenuFabrica:getCerca()
    local e = self.escena
    local dx, dy = e.x - self.mesa[1], -e.z - self.mesa[2]
    return dx * dx + dy * dy <= MenuFabrica.cerca * MenuFabrica.cerca and e.y < 4
end

--- Para cuántos misiles alcanza lo que tiene la nación, y lo que tiene.
function MenuFabrica:alcanza()
    local r = self.escena.almacen:getRecursos()
    local n = math.huge
    for recurso, cuesta in pairs(MenuFabrica.coste) do
        n = math.min(n, math.floor((r[recurso] or 0) / cuesta))
    end
    return n, r
end

--- Cuántos se pueden pedir todavía: lo que cabe en el polvorín y lo que
-- alcanza, quitando lo pedido y el que se monta.
function MenuFabrica:maximo()
    local f = self.escena.fabrica
    local yaVa = f:getPedidos() + f:getEnCurso()
    local cabe = self.escena.almacen:getHuecosLibres() - yaVa
    return math.max(0, math.min(cabe, self:alcanza() - yaVa))
end

-- Entrada ----------------------------------------------------------------------

--- Una tecla. Devuelve true si la ha usado (E abre o cierra; Esc cierra).
function MenuFabrica:tecla(tecla)
    if tecla == MenuFabrica.teclaAbrir then
        if self.abierto then
            self.abierto = false
            return true
        elseif self:getCerca() then
            self.abierto = true
            self.cantidad = math.max(1, math.min(self.cantidad, self:maximo()))
            return true
        end
    elseif tecla == 'escape' and self.abierto then
        self.abierto = false
        return true
    end
    return false
end

local function dentro(b, x, y)
    return b and x >= b[1] and x <= b[1] + b[3] and y >= b[2] and y <= b[2] + b[4]
end

--- Un clic con el menú abierto. Devuelve true si lo ha usado.
function MenuFabrica:clic(x, y)
    if not self.abierto then
        return false
    end
    local b = self.botones
    local f = self.escena.fabrica
    if dentro(b.menos, x, y) then
        self.cantidad = math.max(1, self.cantidad - 1)
    elseif dentro(b.mas, x, y) then
        self.cantidad = math.min(math.max(1, self:maximo()), self.cantidad + 1)
    elseif dentro(b.fabricar, x, y) then
        local n = math.min(self.cantidad, self:maximo())
        if n > 0 then
            f:setPedir(n)
            print(string.format('MENU FABRICA fabricar %d misiles (pedidos: %d)', n, f:getPedidos()))
        end
    elseif dentro(b.parar, x, y) then
        f:setPedir(0)
        print('MENU FABRICA parar fabricación (termina el que está en curso)')
    elseif dentro(b.cerrar, x, y) then
        self.abierto = false
    end
    return true
end

-- Dibujo -----------------------------------------------------------------------

local function boton(self, nombre, texto, x, y, w, h, activo, color)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local encima = activo and mx >= x and mx <= x + w and my >= y and my <= y + h
    local c = color or { 0.18, 0.32, 0.4 }
    local k = activo and (encima and 1.35 or 1) or 0.45
    g.setColor(c[1] * k, c[2] * k, c[3] * k, 0.95)
    g.rectangle('fill', x, y, w, h, 6, 6)
    g.setColor(1, 1, 1, activo and 0.95 or 0.4)
    g.setFont(self.letras.boton)
    g.printf(texto, x, y + (h - self.letras.boton:getHeight()) / 2, w, 'center')
    self.botones[nombre] = activo and { x, y, w, h } or nil
end

--- El aviso de la tecla junto a la mesa, o el menú abierto.
function MenuFabrica:dibujar()
    local g = love.graphics
    g.push('all')
    g.origin()
    local W, H = g.getDimensions()
    self.botones = {}
    if not self.abierto then
        if self:getCerca() then
            -- [E] Fábrica de misiles: la tecla en su recuadro y el texto al lado.
            local texto = 'Fábrica de misiles'
            local letra = self.letras.aviso
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
        g.pop()
        return
    end
    local f = self.escena.fabrica
    local a = self.escena.almacen
    local alcanza, r = self:alcanza()
    local maximo = self:maximo()
    self.cantidad = math.max(1, math.min(self.cantidad, math.max(1, maximo)))
    local pw, ph = 560, 430
    local px, py = (W - pw) / 2, (H - ph) / 2
    g.setColor(0.03, 0.06, 0.08, 0.93)
    g.rectangle('fill', px, py, pw, ph, 10, 10)
    g.setColor(0.3, 0.5, 0.6, 0.8)
    g.setLineWidth(2)
    g.rectangle('line', px, py, pw, ph, 10, 10)
    g.setColor(BLANCO)
    g.setFont(self.letras.titulo)
    g.printf('FÁBRICA DE MISILES', px, py + 16, pw, 'center')
    g.setFont(self.letras.dato)
    local x, y = px + 30, py + 70
    local function linea(texto, color)
        g.setColor(color or BLANCO)
        g.print(texto, x, y)
        y = y + 26
    end
    local trabajando = f:getEnCurso() > 0 or f:getPedidos() > 0
    linea('Estado:   ' .. f:getEstado(), trabajando and VERDE or AMBAR)
    linea('Pedidos:  ' .. f:getPedidos() .. '      En curso: ' .. f:getEnCurso())
    linea('Polvorín: ' .. a:getMisiles() .. ' / ' .. a:getCapacidad() .. ' misiles')
    y = y + 8
    linea('Cada misil: 1 paca de dinero (200), 1 caja de', GRIS)
    linea('metal (10) y 1 garrafa de petróleo (10)', GRIS)
    linea(string.format('Hay: dinero %d · metal %d · petróleo %d', r.dinero or 0, r.metal or 0, r.petroleo or 0))
    linea('Alcanza para ' .. alcanza .. ' misiles', alcanza > 0 and VERDE or ROJO)
    y = y + 10
    g.setColor(BLANCO)
    g.setFont(self.letras.boton)
    g.print('Cantidad', x, y + 8)
    boton(self, 'menos', '−', x + 120, y, 44, 40, self.cantidad > 1)
    g.setColor(BLANCO)
    g.setFont(self.letras.titulo)
    g.printf(tostring(self.cantidad), x + 170, y + 2, 60, 'center')
    boton(self, 'mas', '+', x + 236, y, 44, 40, self.cantidad < maximo)
    y = y + 60
    boton(self, 'fabricar', maximo > 0 and ('Fabricar ' .. self.cantidad) or 'No se puede fabricar', x, y, 240, 46, maximo > 0, { 0.12, 0.45, 0.2 })
    boton(self, 'parar', 'Parar fabricación', x + 260, y, 240, 46, f:getPedidos() > 0, { 0.55, 0.15, 0.1 })
    boton(self, 'cerrar', 'Cerrar (E)', px + pw - 150, py + ph - 52, 130, 38, true)
    g.pop()
end

return MenuFabrica

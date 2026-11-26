-- Fondo de la pantalla de inicio y de la de carga (assets/ui/login/fondo):
-- la imagen entera del render de Camila, recortada para cubrir la pantalla,
-- y sus tres capas de paralaje (cielo y montes, la base y los árboles de
-- delante), que se mueven un poco con el ratón.
--
-- Las capas miden un 10 % más que el encuadre (2816 x 1584 sobre 2560 x
-- 1440): sin moverse, su recorte central es la imagen entera. Se descodifican
-- en un hilo (`love.thread`) mientras se ve la imagen entera; cuando están
-- las tres se pasa a ellas sin salto, porque coinciden en el centro.
--
-- Solo dibuja.

local Vida = require('interfaz.vida')
local Indice = require('assets.ui.login.indice')

local FondoLogin = {}
FondoLogin.__index = FondoLogin

-- Cuánto se mueve cada capa (fondo, base, primer plano) con el ratón en el
-- borde de la pantalla, en parte del margen que les sobra.
local PARALAJE = { 0.12, 0.3, 0.6 }
-- Rapidez con la que el fondo sigue al ratón (Vida.suave): lenta, para que
-- se deslice y no tiemble.
local RAPIDEZ = 2.5

local CODIGO_HILO = [[
require('love.image')
require('love.filesystem')
local canal = love.thread.getChannel('fondoLogin')
local rutas = ...
for indice, ruta in ipairs(rutas) do
    canal:push({ indice, love.image.newImageData(ruta) })
end
]]

local function imagen(fuente)
    local img = love.graphics.newImage(fuente, { mipmaps = true })
    img:setFilter('linear', 'linear')
    img:setMipmapFilter('linear')
    return img
end

function FondoLogin.nuevo()
    local fondo = setmetatable({}, FondoLogin)
    fondo.capas = {}
    fondo.listas = 0
    return fondo
end

--- La imagen entera a la medida de la pantalla (la de 2560 por encima de 1080 de alto).
function FondoLogin:imagenEntera()
    local alto = love.graphics.getHeight()
    local ruta = alto > 1080 and Indice.fondo.archivo1440 or Indice.fondo.archivo
    if self.rutaEntera ~= ruta then
        self.entera = imagen(ruta)
        self.rutaEntera = ruta
    end
    return self.entera
end

--- Empieza a cargar las capas de paralaje: en un hilo o, con `ahora` (las
-- capturas), aquí mismo.
function FondoLogin:cargarCapas(ahora)
    if self.hilo or self.listas == #Indice.fondo.capas then
        return
    end
    if ahora then
        for indice, ruta in ipairs(Indice.fondo.capas) do
            self.capas[indice] = imagen(ruta)
        end
        self.listas = #Indice.fondo.capas
        return
    end
    love.thread.getChannel('fondoLogin'):clear()
    self.hilo = love.thread.newThread(CODIGO_HILO)
    self.hilo:start(Indice.fondo.capas)
end

--- ¿Están las tres capas?
function FondoLogin:conCapas()
    return self.listas == #Indice.fondo.capas
end

--- Recoge las capas que el hilo ya ha descodificado y mueve el paralaje
-- hacia el ratón.
function FondoLogin:actualizar()
    if self.hilo then
        local canal = love.thread.getChannel('fondoLogin')
        local llegada = canal:pop()
        while llegada do
            self.capas[llegada[1]] = imagen(llegada[2])
            llegada[2]:release()
            self.listas = self.listas + 1
            llegada = canal:pop()
        end
        local fallo = self.hilo:getError()
        if fallo then
            print('FONDO del login: ' .. fallo)
            self.hilo = nil
        elseif self:conCapas() then
            self.hilo = nil
        end
    end
end

--- Suelta las capas (ya en la partida no hacen falta: unos 50 MB).
function FondoLogin:soltarCapas()
    if self.hilo then
        return
    end
    for indice, capa in pairs(self.capas) do
        capa:release()
        self.capas[indice] = nil
    end
    self.listas = 0
end

--- Dibuja el fondo cubriendo la pantalla. Con `paralaje`, las capas se
-- desplazan según el ratón (si ya están cargadas).
function FondoLogin:dibujar(paralaje)
    local g = love.graphics
    local w, h = g.getDimensions()
    g.setColor(1, 1, 1, 1)
    if not (paralaje and self:conCapas()) then
        local img = self:imagenEntera()
        local iw, ih = img:getDimensions()
        local k = math.max(w / iw, h / ih)
        g.draw(img, math.floor((w - iw * k) / 2), math.floor((h - ih * k) / 2), 0, k, k)
        return
    end
    -- Ratón de -1 a 1 desde el centro; quieto en las capturas.
    local objetivoX, objetivoY = 0, 0
    if not Vida.quieta then
        local mx, my = love.mouse.getPosition()
        objetivoX = math.max(-1, math.min(1, (mx - w / 2) / (w / 2)))
        objetivoY = math.max(-1, math.min(1, (my - h / 2) / (h / 2)))
    end
    local nx = Vida.suave('fondoLogin:x', objetivoX, RAPIDEZ)
    local ny = Vida.suave('fondoLogin:y', objetivoY, RAPIDEZ)
    local margen = Indice.fondo.margenCapas
    local cw, ch = self.capas[1]:getDimensions()
    -- Escala del encuadre (el recorte central sin el margen) para cubrir la pantalla.
    local k = math.max(w * (1 + margen) / cw, h * (1 + margen) / ch)
    local sobraX = (cw * k - w) / 2
    local sobraY = (ch * k - h) / 2
    for indice, capa in ipairs(self.capas) do
        local dx = -nx * PARALAJE[indice] * sobraX
        local dy = -ny * PARALAJE[indice] * sobraY
        g.draw(capa, w / 2 + dx, h / 2 + dy, 0, k, k, cw / 2, ch / 2)
    end
end

return FondoLogin

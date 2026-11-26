-- Sala de control del almacén (diseno/almacen.md): lo que se ve en sus
-- pantallas. El modelo sale de tools/blender/almacen_interior.py
-- (crearSalaControl) con cinco mallas que se pintan aquí:
--
--   * `pantallaMapa`: las 4 pantallas de la izquierda del muro, una sola
--     imagen: el mapa 2D de la capital (assets/almacen/mapa_capital.png,
--     una captura fija del mapa del juego).
--   * `pantallaNacion`: la nación de la partida (nombre, capital, poder,
--     nivel, día y los cuatro recursos).
--   * `pantallaArsenal`: los misiles del almacén.
--   * `pantallasPuestos`: los 18 monitores de los 6 puestos, en un atlas de
--     6 x 3 (columna = puesto, fila = monitor de izquierda a derecha):
--     polvorín, recursos y noticias, en distinto orden en cada puesto.
--   * `ledsServidores`: cada luz de los armarios es un píxel de una imagen
--     de 32 x 18 que parpadea.
--
-- Todos los datos salen de la partida en vivo por el objeto Almacen
-- (`getMisiles`, `getCapacidad` y `getPartida`): nada está inventado.

local dream = require('lib.3DreamEngine')

local SalaControl = {}
SalaControl.__index = SalaControl

local MAPA = 'assets/almacen/mapa_capital.png'
local LETRA_TITULO = 'assets/fuentes/BarlowCondensed-SemiBold.ttf'
local LETRA_DATO = 'assets/fuentes/JetBrainsMono-SemiBold.ttf'

-- Cada cuánto se vuelven a pintar las pantallas de datos (s) y las luces.
SalaControl.refresco = 0.5
SalaControl.refrescoLeds = 0.08
-- Brillo de las pantallas (factor de emisión del motor).
SalaControl.brilloMuro = 1.6
SalaControl.brilloMonitores = 1.8
SalaControl.brilloLeds = 5.0

local LEDS_ANCHO, LEDS_ALTO, LEDS = 32, 18, 560
local CELDA_ANCHO, CELDA_ALTO = 320, 192

local VERDE = { 0.24, 0.9, 0.42 }
local COLOR_ESTADO = {
    holgado = { 0.3, 0.85, 0.4 },
    justo = { 0.95, 0.8, 0.25 },
    escasez = { 1.0, 0.55, 0.15 },
    crisis = { 1.0, 0.27, 0.2 },
}
local TEXTO_ESTADO = { holgado = 'BIEN', justo = 'JUSTO', escasez = 'ESCASEZ', crisis = 'CRISIS' }
local COLOR_RECURSO = {
    metal = { 0.73, 0.77, 0.8 },
    petroleo = { 0.4, 0.45, 1.0 },
    comida = { 0.91, 0.7, 0.23 },
    dinero = { 0.35, 0.77, 0.42 },
}

local function miles(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local signo = ''
    if s:sub(1, 1) == '-' then
        signo, s = '-', s:sub(2)
    end
    return signo .. s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
end

--- Material emisivo con `textura` para todas las mallas de `pieza`.
local function ponerPantalla(pieza, nombre, textura, brillo)
    local material = dream:newMaterial(nombre)
    material:setColor(0.01, 0.01, 0.012, 1)
    material:setRoughness(0.25)
    material:setMetallic(0)
    material:setEmissionTexture(textura)
    material:setEmissionFactor(brillo, brillo, brillo)
    for _, malla in pairs(pieza and pieza.meshes or {}) do
        malla:setMaterial(material)
    end
end

--- `objeto`: el modelo del almacén ya cargado; `almacen`: el de la nación.
function SalaControl.nueva(objeto, almacen)
    local self = setmetatable({}, SalaControl)
    self.almacen = almacen
    self.objetos = objeto.objects
    local g = love.graphics
    self.letras = {
        enorme = g.newFont(LETRA_TITULO, 110),
        grande = g.newFont(LETRA_TITULO, 64),
        titulo = g.newFont(LETRA_TITULO, 40),
        medio = g.newFont(LETRA_TITULO, 30),
        dato = g.newFont(LETRA_DATO, 20),
        chico = g.newFont(LETRA_DATO, 15),
    }
    self.nacion = g.newCanvas(768, 436)
    self.arsenal = g.newCanvas(768, 436)
    self.puestos = g.newCanvas(CELDA_ANCHO * 6, CELDA_ALTO * 3)
    self.ledsDatos = love.image.newImageData(LEDS_ANCHO, LEDS_ALTO)
    self.leds = g.newImage(self.ledsDatos)
    self.leds:setFilter('nearest', 'nearest')
    self.mapa = g.newImage(MAPA, { mipmaps = true })
    self.mapa:setFilter('linear', 'linear')
    ponerPantalla(self.objetos.pantallaMapa, 'pantallaMapaViva', self.mapa, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.pantallaNacion, 'pantallaNacionViva', self.nacion, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.pantallaArsenal, 'pantallaArsenalViva', self.arsenal, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.pantallasPuestos, 'pantallasPuestosVivas', self.puestos, SalaControl.brilloMonitores)
    ponerPantalla(self.objetos.ledsServidores, 'ledsServidoresVivos', self.leds, SalaControl.brilloLeds)
    -- Vidrio de los tabiques: transparente (pasada de alfa del motor), apenas
    -- teñido y sin desviar lo de detrás. Una luna plana y fina no deforma lo
    -- que se ve a través (los dos lados se compensan); con índice 1,5 el motor
    -- lo torcía como un espejo de feria (el dueño, 17-nov). La refracción
    -- queda para lo que sí la tiene: líquidos y vidrios curvos.
    local vidrio = dream:newMaterial('vidrioSalaVivo')
    vidrio:setColor(0.9, 0.97, 0.96, 0.18)
    vidrio:setRoughness(0.03)
    vidrio:setMetallic(0)
    vidrio:setIOR(1.0)
    vidrio:setAlpha()
    for _, malla in pairs(self.objetos.vidriosSala and self.objetos.vidriosSala.meshes or {}) do
        malla:setMaterial(vidrio)
    end
    -- Cada luz: color (0 verde, 1 ámbar, 2 azul, 3 rojo), ritmo y fase.
    local azar = love.math.newRandomGenerator(4242)
    self.luces = {}
    for k = 1, LEDS do
        local columna = (k - 1) % 7
        local color = columna == 0 and 2 or (azar:random() < 0.86 and 0 or (azar:random() < 0.7 and 1 or 3))
        self.luces[k] = { color = color, ritmo = 2 + azar:random() * 10, fase = azar:random() * 10, fijo = columna == 0 or azar:random() < 0.3 }
    end
    self.reloj = 0
    self.proximo = 0
    self.proximoLeds = 0
    self:pintar()
    self:pintarLeds()
    return self
end

function SalaControl:actualizar(dt)
    self.reloj = self.reloj + dt
    if self.reloj >= self.proximo then
        self.proximo = self.reloj + SalaControl.refresco
        self:pintar()
    end
    if self.reloj >= self.proximoLeds then
        self.proximoLeds = self.reloj + SalaControl.refrescoLeds
        self:pintarLeds()
    end
end

--- Las mallas de la sala, en el pase de dibujo de la escena (el vidrio, al
-- final, va en la pasada de alfa).
function SalaControl:dibujar()
    local o = self.objetos
    for _, nombre in ipairs({ 'pantallaMapa', 'pantallaNacion', 'pantallaArsenal', 'pantallasPuestos', 'ledsServidores', 'vidriosSala' }) do
        if o[nombre] then
            dream:draw(o[nombre])
        end
    end
end

function SalaControl:cerrar()
    for _, lienzo in ipairs({ self.nacion, self.arsenal, self.puestos }) do
        lienzo:release()
    end
end

-- Pintar -----------------------------------------------------------------------

function SalaControl:pintar()
    local partida = self.almacen:getPartida()
    local misiles, capacidad = self.almacen:getMisiles(), self.almacen:getCapacidad()
    self.partida = partida
    local g = love.graphics
    g.push('all')
    g.origin()
    g.setCanvas(self.nacion)
    self:pintarNacion(partida, 768, 436)
    g.setCanvas(self.arsenal)
    self:pintarArsenal(misiles, capacidad, 768, 436)
    g.setCanvas(self.puestos)
    g.clear(0, 0, 0, 1)
    local orden = { 'polvorin', 'recursos', 'noticias' }
    for puesto = 0, 5 do
        for monitor = 0, 2 do
            local tipo = orden[(monitor + puesto) % 3 + 1]
            g.push()
            g.translate(puesto * CELDA_ANCHO, monitor * CELDA_ALTO)
            g.setScissor(puesto * CELDA_ANCHO, monitor * CELDA_ALTO, CELDA_ANCHO, CELDA_ALTO)
            if tipo == 'polvorin' then
                self:pintarPolvorin(misiles, capacidad, CELDA_ANCHO, CELDA_ALTO)
            elseif tipo == 'recursos' then
                self:pintarRecursos(partida, CELDA_ANCHO, CELDA_ALTO)
            else
                self:pintarNoticias(partida, CELDA_ANCHO, CELDA_ALTO)
            end
            g.setScissor()
            g.pop()
        end
    end
    g.pop()
end

local function fondo(w, h, r, gr, b)
    local g = love.graphics
    g.setColor(r, gr, b, 1)
    g.rectangle('fill', 0, 0, w, h)
end

--- Símbolo de radiactividad (trébol) en (x, y) de radio r sobre amarillo.
local function trebol(x, y, r)
    local g = love.graphics
    g.setColor(0.91, 0.77, 0.28)
    g.circle('fill', x, y, r * 1.18)
    g.setColor(0.05, 0.05, 0.05)
    for k = 0, 2 do
        local a = -math.pi / 2 + k * 2 * math.pi / 3 - math.pi / 6
        g.arc('fill', x, y, r, a, a + math.pi / 3)
    end
    g.setColor(0.91, 0.77, 0.28)
    g.circle('fill', x, y, r * 0.3)
    g.setColor(0.05, 0.05, 0.05)
    g.circle('fill', x, y, r * 0.18)
end

function SalaControl:pintarNacion(p, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.05, 0.055)
    if not p then
        g.setColor(1, 0.4, 0.3)
        g.setFont(L.titulo)
        g.print('SIN NACIÓN', 28, 28)
        return
    end
    g.setColor(0.91, 0.77, 0.28)
    g.setFont(L.titulo)
    g.printf(p.nacion:upper(), 28, 16, w - 56, 'left')
    g.setColor(0.62, 0.7, 0.74)
    g.setFont(L.dato)
    g.print(string.format('Capital %s · %s hab.', p.capital, miles(p.habitantes)), 28, 70)
    g.print(string.format('Poder %s · Nivel %d · Año %d, día %d', miles(p.poder), p.nivel, p.anio, p.dia), 28, 98)
    for k, r in ipairs(p.recursos) do
        local y = 140 + (k - 1) * 72
        local color = COLOR_RECURSO[r.tipo]
        g.setColor(color)
        g.rectangle('fill', 28, y, 12, 52)
        g.setColor(0.85, 0.89, 0.86)
        g.setFont(L.dato)
        g.print(r.nombre:upper(), 54, y)
        g.setColor(COLOR_ESTADO[r.estado] or VERDE)
        g.setFont(L.chico)
        g.print(TEXTO_ESTADO[r.estado] or '', 54 + L.dato:getWidth(r.nombre:upper()) + 14, y + 4)
        g.setColor(r.cantidad <= 0 and { 1, 0.35, 0.28 } or { 1, 1, 1 })
        g.setFont(L.grande)
        g.printf(miles(r.cantidad), w - 300, y - 14, 272, 'right')
        g.setColor(0.11, 0.15, 0.17)
        g.rectangle('fill', 54, y + 34, w - 360, 12)
        g.setColor(color)
        local f = r.tope and r.tope > 0 and math.min(1, r.cantidad / r.tope) or 0
        g.rectangle('fill', 54, y + 34, (w - 360) * f, 12)
    end
end

function SalaControl:pintarArsenal(misiles, capacidad, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.05, 0.055)
    trebol(56, 52, 26)
    g.setColor(0.31, 0.76, 1)
    g.setFont(L.titulo)
    g.print('ALMACÉN · MISILES', 100, 26)
    g.setColor(misiles == 0 and { 1, 0.35, 0.28 } or { 1, 1, 1 })
    g.setFont(L.enorme)
    g.print(misiles .. ' / ' .. capacidad, 28, 84)
    g.setColor(0.62, 0.7, 0.74)
    g.setFont(L.dato)
    g.print((capacidad - misiles) .. ' huecos libres en el polvorín', 28, 220)
    local columnas = 20
    local cw = (w - 56) / columnas
    for k = 0, capacidad - 1 do
        local c, f = k % columnas, math.floor(k / columnas)
        if k < misiles then
            g.setColor(0.17, 0.54, 0.24)
        else
            g.setColor(0.11, 0.15, 0.17)
        end
        g.rectangle('fill', 28 + c * cw + 2, 262 + f * 38, cw - 5, 30)
    end
    local estado, color
    if misiles == 0 then
        estado, color = '● SIN MISILES: NO SE PUEDE DISPARAR', { 1, 0.3, 0.25 }
    elseif misiles >= capacidad then
        estado, color = '● POLVORÍN LLENO', { 0.31, 0.76, 1 }
    else
        estado, color = '● LISTO PARA CARGAR CAMIONES', VERDE
    end
    local parpadeo = math.floor(self.reloj * 2) % 2 == 0 and 1 or 0.45
    g.setColor(color[1] * parpadeo, color[2] * parpadeo, color[3] * parpadeo)
    g.setFont(L.dato)
    g.print(estado, 28, h - 46)
end

function SalaControl:pintarPolvorin(misiles, capacidad, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.03, 0.06, 0.035)
    trebol(34, 34, 18)
    g.setColor(0.49, 1, 0.42)
    g.setFont(L.medio)
    g.print('POLVORÍN', 64, 14)
    g.setColor(misiles == 0 and { 1, 0.35, 0.28 } or { 1, 1, 1 })
    g.setFont(L.titulo)
    g.printf(misiles .. '/' .. capacidad, 0, 14, w - 14, 'right')
    local columnas = 10
    local cw = (w - 28) / columnas
    local ch = (h - 76) / math.ceil(capacidad / columnas)
    for k = 0, capacidad - 1 do
        local c, f = k % columnas, math.floor(k / columnas)
        g.setColor(k < misiles and { 0.17, 0.54, 0.24 } or { 0.1, 0.14, 0.12 })
        g.rectangle('fill', 14 + c * cw + 1, 64 + f * ch + 1, cw - 3, ch - 3)
    end
end

function SalaControl:pintarRecursos(p, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.045, 0.06)
    g.setColor(0.31, 0.76, 1)
    g.setFont(L.medio)
    g.print('RECURSOS', 14, 10)
    if not p then
        return
    end
    g.setColor(0.62, 0.7, 0.74)
    g.setFont(L.chico)
    g.printf('DÍA ' .. p.dia, 0, 20, w - 14, 'right')
    for k, r in ipairs(p.recursos) do
        local y = 56 + (k - 1) * 33
        g.setColor(0.85, 0.89, 0.86)
        g.setFont(L.chico)
        g.print(r.nombre:upper(), 14, y)
        g.setColor(COLOR_ESTADO[r.estado] or VERDE)
        g.printf(miles(r.cantidad), 0, y, w - 14, 'right')
        g.setColor(0.11, 0.15, 0.17)
        g.rectangle('fill', 14, y + 20, w - 28, 7)
        g.setColor(COLOR_RECURSO[r.tipo])
        local f = r.tope and r.tope > 0 and math.min(1, r.cantidad / r.tope) or 0
        g.rectangle('fill', 14, y + 20, (w - 28) * f, 7)
    end
end

function SalaControl:pintarNoticias(p, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.05, 0.045, 0.03)
    g.setColor(0.91, 0.77, 0.28)
    g.setFont(L.medio)
    g.print('NOTICIAS', 14, 10)
    if not p then
        return
    end
    g.setFont(L.chico)
    local y = 52
    local alto = L.chico:getHeight()
    for _, n in ipairs(p.noticias) do
        local _, lineas = L.chico:getWrap(n.texto, w - 70)
        if y + alto * #lineas > h - 6 then
            break
        end
        g.setColor(0.55, 0.6, 0.6)
        g.print('D' .. (n.dia or 0), 14, y)
        local c = n.color or { 1, 1, 1 }
        g.setColor(c[1], c[2], c[3])
        g.printf(n.texto, 56, y, w - 70, 'left')
        y = y + alto * #lineas + 6
    end
    if #p.noticias == 0 then
        g.setColor(0.55, 0.6, 0.6)
        g.print('Sin noticias', 14, y)
    end
end

--- Las luces de los servidores: cada una se enciende y se apaga a su ritmo.
function SalaControl:pintarLeds()
    local colores = { { 0.24, 1, 0.42 }, { 1, 0.71, 0 }, { 0.23, 0.63, 1 }, { 1, 0.24, 0.24 } }
    local t = self.reloj
    local d = self.ledsDatos
    for k, luz in ipairs(self.luces) do
        local x, y = (k - 1) % LEDS_ANCHO, math.floor((k - 1) / LEDS_ANCHO)
        local c = colores[luz.color + 1]
        local f = (luz.fijo or math.sin(t * luz.ritmo + luz.fase) > -0.2) and 1 or 0.08
        d:setPixel(x, y, c[1] * f, c[2] * f, c[3] * f, 1)
    end
    self.leds:replacePixels(d)
end

return SalaControl

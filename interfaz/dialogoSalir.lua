-- Pregunta «¿Salir del juego?» (el dueño, 2026-10-01): sale con Esc en la
-- pantalla de inicio y con la X de la ventana (`love.quit`), en el inicio y
-- en la partida. «Salir» cierra el juego; «Cancelar» o Esc vuelve; Enter
-- confirma.
--
-- Con las piezas del login (assets/ui/login/piezas) y su misma escala: el
-- lienzo de 1920 x 1080 entero en la pantalla, sin estirar.
--
-- Los textos están todos en `TEXTOS`, para traducirlos.

local Tema = require('interfaz.tema')
local Vida = require('interfaz.vida')
local Nueve = require('interfaz.nueve')
local Indice = require('assets.ui.login.indice')

local TEXTOS = {
    titulo = '¿SALIR DEL JUEGO?',
    detalle = 'Se cerrará Nations RTS.',
    salir = 'SALIR',
    cancelar = 'Cancelar',
}

local DialogoSalir = {}
DialogoSalir.__index = DialogoSalir
DialogoSalir.TEXTOS = TEXTOS

local function hex(texto)
    local r, g, b = texto:match('#(%x%x)(%x%x)(%x%x)')
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local COLORES = {
    texto = hex(Indice.disposicion.colores.texto),
    marcador = hex(Indice.disposicion.colores.marcador),
    textoBoton = hex(Indice.disposicion.colores.textoBoton),
    dorado = hex('#f2c14e'),
}

-- Medidas del diseño (a 1080p).
local CAJA = { ancho = 620, alto = 260 }
local FUENTES = {
    titulo = { 'condensada', 40 },
    detalle = { 'semi', 22 },
    boton = { 'condensada', 32 },
}
local ESPACIADO = { titulo = 2, boton = 2 }

local function color(c, alfa)
    love.graphics.setColor(c[1], c[2], c[3], alfa or 1)
end

--- `y` de un texto con su centro vertical en `centro`.
local function arribaDe(fuente, centro)
    return math.floor(centro - (fuente:getAscent() - fuente:getDescent()) / 2 + 0.5)
end

function DialogoSalir.nuevo()
    local dialogo = setmetatable({}, DialogoSalir)
    dialogo.abierto = false
    dialogo.pulsando = nil
    return dialogo
end

--- Las piezas, la primera vez que se dibuja.
function DialogoSalir:cargar()
    if self.cortes then
        return
    end
    self.cortes = {}
    for _, nombre in ipairs({ 'campo', 'botonPrincipal', 'botonSecundario' }) do
        local pieza = Indice.piezas[nombre]
        local img = love.graphics.newImage(pieza.archivo, { mipmaps = true })
        img:setFilter('linear', 'linear')
        self.cortes[nombre] = Nueve.nuevo(img, pieza.nueve)
    end
end

function DialogoSalir:abrir()
    self.abierto = true
    self.pulsando = nil
end

function DialogoSalir:cerrar()
    self.abierto = false
    self.pulsando = nil
end

--- Escala del lienzo del diseño en la pantalla.
function DialogoSalir:escala()
    local w, h = love.graphics.getDimensions()
    return math.min(w / 1920, h / 1080)
end

function DialogoSalir:fuente(estilo)
    local f = FUENTES[estilo]
    local base = f[2] * self:escala() / (Tema.escala() * Tema.TEXTO)
    return Tema.fuenteExacta(f[1], base, 10)
end

--- Caja del diálogo y de sus botones, en pantalla.
function DialogoSalir:zonas()
    local s = self:escala()
    local w, h = love.graphics.getDimensions()
    local dw = math.floor(CAJA.ancho * s)
    local dh = math.floor(CAJA.alto * s)
    local x = math.floor((w - dw) / 2)
    local y = math.floor((h - dh) / 2)
    local bw = math.floor(250 * s)
    local bh = math.floor(70 * s)
    local hueco = math.floor(24 * s)
    local by = y + dh - bh - math.floor(34 * s)
    local bx = math.floor(x + (dw - bw * 2 - hueco) / 2)
    return {
        salir = { bx, by, bw, bh },
        cancelar = { bx + bw + hueco, by, bw, bh },
    }, { x, y, dw, dh }
end

--- Botón bajo (x, y), o nil.
function DialogoSalir:bajo(x, y)
    for nombre, c in pairs(self:zonas()) do
        if Tema.dentro(x, y, c[1], c[2], c[3], c[4]) then
            return nombre
        end
    end
    return nil
end

function DialogoSalir:encima(nombre)
    if self.encimaFijo then
        return self.encimaFijo == nombre
    end
    if Vida.quieta then
        return false
    end
    return self:bajo(love.mouse.getPosition()) == nombre
end

function DialogoSalir:pulsado(nombre)
    return self.pulsando == nombre and self:encima(nombre) and love.mouse.isDown(1)
end

function DialogoSalir:pulsar(x, y, boton)
    if boton == 1 then
        self.pulsando = self:bajo(x, y)
    end
end

--- Suelta del ratón: devuelve 'salir' si se confirmó.
function DialogoSalir:soltar(x, y, boton)
    if boton ~= 1 then
        return nil
    end
    local nombre = self:bajo(x, y)
    local pulsado = self.pulsando
    self.pulsando = nil
    if nombre and nombre == pulsado then
        if nombre == 'salir' then
            return 'salir'
        end
        self:cerrar()
    end
    return nil
end

--- Tecla: Esc cierra, Enter confirma ('salir').
function DialogoSalir:tecla(tecla)
    if tecla == 'escape' then
        self:cerrar()
    elseif tecla == 'return' or tecla == 'kpenter' then
        return 'salir'
    end
    return nil
end

function DialogoSalir:dibujar()
    if not self.abierto then
        return
    end
    self:cargar()
    Tema.actualizar()
    local g = love.graphics
    local s = self:escala()
    local w, h = g.getDimensions()
    g.setColor(0, 0, 0, 0.62)
    g.rectangle('fill', 0, 0, w, h)
    local zonas, caja = self:zonas()
    Vida.entrar('dialogoSalir', 0, math.floor(14 * s))
    local x, y, dw, dh = caja[1], caja[2], caja[3], caja[4]
    g.setColor(1, 1, 1, 1)
    self.cortes.campo:dibujar(x, y, dw, dh, s)
    color(COLORES.dorado)
    g.rectangle('fill', x, y, dw, math.max(2, math.floor(3 * s)))
    local titulo = self:fuente('titulo')
    local espacio = ESPACIADO.titulo * s
    local tw = Tema.anchoEspaciado(TEXTOS.titulo, titulo, espacio)
    color(COLORES.texto)
    Tema.espaciado(TEXTOS.titulo, math.floor(x + (dw - tw) / 2), y + math.floor(30 * s), titulo, espacio)
    local detalle = self:fuente('detalle')
    g.setFont(detalle)
    color(COLORES.marcador)
    local ddw = detalle:getWidth(TEXTOS.detalle)
    g.print(TEXTOS.detalle, math.floor(x + (dw - ddw) / 2), y + math.floor(92 * s))
    -- «Salir» dorado (con su resplandor alrededor) y «Cancelar» oscuro.
    local b = zonas.salir
    local crece, hunde = Vida.boton('dialogoSalir:salir', self:encima('salir'), self:pulsado('salir'))
    local brillo = 1 - 0.14 * hunde
    local margen = math.floor(23 * s)
    g.setColor(brillo, brillo, brillo, 1)
    self.cortes.botonPrincipal:dibujar(b[1] - margen, b[2] - margen, b[3] + margen * 2, b[4] + margen * 2, s)
    if crece > 0.01 then
        local modo, alfaModo = g.getBlendMode()
        g.setBlendMode('add')
        g.setColor(1, 0.85, 0.5, 0.16 * crece)
        self.cortes.botonPrincipal:dibujar(b[1] - margen, b[2] - margen, b[3] + margen * 2, b[4] + margen * 2, s)
        g.setBlendMode(modo, alfaModo)
    end
    local fuenteBoton = self:fuente('boton')
    local eb = ESPACIADO.boton * s
    local sw = Tema.anchoEspaciado(TEXTOS.salir, fuenteBoton, eb)
    color(COLORES.textoBoton)
    Tema.espaciado(
        TEXTOS.salir,
        math.floor(b[1] + (b[3] - sw) / 2),
        arribaDe(fuenteBoton, b[2] + b[4] / 2),
        fuenteBoton,
        eb
    )
    local c = zonas.cancelar
    crece, hunde = Vida.boton('dialogoSalir:cancelar', self:encima('cancelar'), self:pulsado('cancelar'))
    local baja = math.floor(2 * s * hunde + 0.5)
    g.setColor(1, 1, 1, 1)
    self.cortes.botonSecundario:dibujar(c[1], c[2] + baja, c[3], c[4], s)
    if crece > 0.01 then
        color(COLORES.dorado, 0.55 * crece)
        g.rectangle('line', c[1] + 0.5, c[2] + baja + 0.5, c[3] - 1, c[4] - 1)
    end
    g.setFont(detalle)
    color(Tema.mezcla(COLORES.texto, COLORES.dorado, 0.35 * crece))
    local cw = detalle:getWidth(TEXTOS.cancelar)
    g.print(TEXTOS.cancelar, math.floor(c[1] + (c[3] - cw) / 2), arribaDe(detalle, c[2] + baja + c[4] / 2))
    Vida.fin()
    g.setColor(1, 1, 1, 1)
end

return DialogoSalir

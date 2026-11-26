-- Campo de texto de una línea (la pantalla de inicio, interfaz/login.lua):
-- guarda lo escrito y la posición del cursor, y sabe borrar, moverse y pegar.
-- Con `oculto`, lo que se enseña son puntos (la contraseña); el ojo del
-- campo lo alterna con `mostrar`.
--
-- Trabaja con caracteres UTF-8 (ñ, tildes), no con bytes. No dibuja: la
-- pantalla que lo usa pinta el texto que devuelve `textoVisible`.

local utf8 = require('utf8')

local CampoTexto = {}
CampoTexto.__index = CampoTexto

local PUNTO = '•'

--- Campo nuevo. `opciones`: { oculto, maximo } (`maximo`, en caracteres).
function CampoTexto.nuevo(opciones)
    opciones = opciones or {}
    local campo = setmetatable({}, CampoTexto)
    campo.texto = ''
    campo.cursor = 0 -- caracteres antes del cursor
    campo.oculto = opciones.oculto or false
    campo.mostrar = false
    campo.maximo = opciones.maximo or 64
    return campo
end

function CampoTexto:largo()
    return utf8.len(self.texto) or 0
end

--- Byte donde empieza el carácter número `n` + 1 (el que va tras `n`).
local function corte(texto, n)
    return utf8.offset(texto, n + 1) or (#texto + 1)
end

--- Escribe `texto` en el cursor (lo que llega de `love.textinput`).
function CampoTexto:escribir(texto)
    texto = texto:gsub('[%c]', '')
    if texto == '' or not utf8.len(texto) then
        return
    end
    local cabe = self.maximo - self:largo()
    if cabe <= 0 then
        return
    end
    if utf8.len(texto) > cabe then
        texto = texto:sub(1, corte(texto, cabe) - 1)
    end
    local b = corte(self.texto, self.cursor)
    self.texto = self.texto:sub(1, b - 1) .. texto .. self.texto:sub(b)
    self.cursor = self.cursor + utf8.len(texto)
end

--- Borra el carácter antes del cursor (`atras`) o el de después.
function CampoTexto:borrar(atras)
    local desde = atras and self.cursor - 1 or self.cursor
    if desde < 0 or desde >= self:largo() then
        return
    end
    local a = corte(self.texto, desde)
    local b = corte(self.texto, desde + 1)
    self.texto = self.texto:sub(1, a - 1) .. self.texto:sub(b)
    if atras then
        self.cursor = self.cursor - 1
    end
end

--- Atiende una tecla. Devuelve true si era suya.
function CampoTexto:tecla(tecla)
    local control = love.keyboard.isDown('lctrl', 'rctrl')
    if tecla == 'backspace' then
        if control then
            local b = corte(self.texto, self.cursor)
            self.texto = self.texto:sub(b)
            self.cursor = 0
        else
            self:borrar(true)
        end
    elseif tecla == 'delete' then
        self:borrar(false)
    elseif tecla == 'left' then
        self.cursor = math.max(0, self.cursor - 1)
    elseif tecla == 'right' then
        self.cursor = math.min(self:largo(), self.cursor + 1)
    elseif tecla == 'home' then
        self.cursor = 0
    elseif tecla == 'end' then
        self.cursor = self:largo()
    elseif tecla == 'v' and control then
        local pegado = love.system.getClipboardText() or ''
        self:escribir(pegado:match('^[^\r\n]*'))
    else
        return false
    end
    return true
end

--- Lo que se enseña: el texto o, si está oculto y no se muestra, puntos.
function CampoTexto:textoVisible()
    if self.oculto and not self.mostrar then
        return string.rep(PUNTO, self:largo())
    end
    return self.texto
end

--- Lo que se enseña antes del cursor (para saber dónde dibujarlo).
function CampoTexto:visibleAntesDelCursor()
    local visible = self:textoVisible()
    return visible:sub(1, corte(visible, self.cursor) - 1)
end

--- Pone el cursor al final.
function CampoTexto:alFinal()
    self.cursor = self:largo()
end

return CampoTexto

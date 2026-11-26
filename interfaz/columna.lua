-- Columna de iconos de la izquierda (diseno/interfaz-militar.md, §6.1): las
-- acciones del mapa, un hexágono de 72 de ancho con su etiqueta y, si hay algo
-- pendiente, una insignia roja. Son hexágonos de metal (`hexagono_icono`). Cada botón hace lo mismo que su tecla:
-- `pulsar` devuelve la tecla y main.lua la aplica.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local Columna = {}
Columna.__index = Columna

-- Botones, de arriba abajo: tecla, icono del kit (o `dibujar`), etiqueta, ayuda,
-- estado que lo deja encendido y contador de la insignia. `jugador`: solo si
-- se juega una nación.
local BOTONES = {
    {
        tecla = 'p',
        icono = 'bandera',
        etiqueta = 'Bandera',
        ayuda = 'Plantar bandera (P)',
        encendido = 'plantando',
        jugador = true,
    },
    {
        tecla = 'x',
        icono = 'atacar',
        etiqueta = 'Ataque',
        ayuda = 'Ir al último ataque (X)',
        cuenta = 'ataques',
    },
    { tecla = 't', icono = 'mundo', etiqueta = 'Territorio', ayuda = 'Territorios (T)', encendido = 'territorio' },
    { tecla = 'f5', icono = 'guardar', etiqueta = 'Guardar', ayuda = 'Guardar la partida (F5)' },
}

function Columna.nuevo()
    local self = setmetatable({}, Columna)
    self.zonas = {}
    self.ayuda = nil
    self.rect = nil
    return self
end

--- Ancho que ocupa la columna con su margen, para colocar lo demás a su derecha.
function Columna.ancho()
    return Tema.px(16 + 72)
end

--- Dibuja la columna bajo la barra superior (`arriba`, en píxeles). `ctx` =
-- { jugador (¿se juega?), plantando, territorio, ataques (avisos de ataque
-- que llegan) }.
function Columna:dibujar(ctx, arriba)
    self.zonas = {}
    self.ayuda = nil
    local x = Tema.px(16)
    local y = arriba + Tema.px(16)
    local w, h = Tema.px(72), Tema.px(96)
    local hueco = Tema.px(4)
    local fondo = y
    for _, b in ipairs(BOTONES) do
        if ctx.jugador or not b.jugador then
            local activo = b.encendido and ctx[b.encendido] or false
            local encima = Acero.botonIcono(x, y, w, h, {
                icono = b.icono,
                etiqueta = b.etiqueta,
                activo = activo,
                cuenta = b.cuenta and ctx[b.cuenta] or 0,
            })
            if encima then
                self.ayuda = b.ayuda
                local cuenta = b.cuenta and ctx[b.cuenta] or 0
                if cuenta > 0 then
                    self.ayuda = string.format('%s: %d en camino', b.ayuda, cuenta)
                end
            end
            self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, tecla = b.tecla }
            y = y + h + hueco
        end
    end
    self.rect = { x = x, y = fondo, w = w, h = y - fondo - hueco }
end

function Columna:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- ¿El punto cae sobre un botón de la columna?
function Columna:encima(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return true
        end
    end
    return false
end

--- Clic: devuelve la tecla del botón pulsado (o nil).
function Columna:pulsar(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.tecla
        end
    end
    return nil
end

return Columna

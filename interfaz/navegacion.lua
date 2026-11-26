-- Barra de navegación de abajo (diseno/interfaz-militar.md, §6.2): una fila
-- centrada de hexágonos de metal, uno por panel (nación, ejércitos, batallas,
-- arsenal, noticias y ajustes), con su etiqueta y su insignia roja. Cada botón devuelve una «tecla» que main.lua aplica como si se
-- hubiera pulsado.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local Navegacion = {}
Navegacion.__index = Navegacion

-- Botones, de izquierda a derecha: tecla, icono, etiqueta, ayuda, qué panel lo
-- deja encendido y contador de su insignia. `jugador`: solo si se juega.
local BOTONES = {
    {
        tecla = 'perfil',
        icono = 'perfil',
        etiqueta = 'Nación',
        ayuda = 'Perfil de la nación',
        encendido = 'perfilAbierto',
    },
    {
        tecla = 'todas',
        icono = 'ejercito',
        etiqueta = 'Ejércitos',
        ayuda = 'Elegir todos tus ejércitos (Ctrl+A)',
        cuenta = 'ejercitos',
        jugador = true,
    },
    {
        tecla = 'arsenal',
        icono = 'unidades',
        etiqueta = 'Arsenal',
        ayuda = 'Arsenal: las unidades que existen (U)',
        encendido = 'arsenalAbierto',
        jugador = true,
    },
    {
        tecla = 'almacen',
        icono = 'suministros',
        etiqueta = 'Almacén',
        ayuda = 'Entrar en el almacén: los misiles guardados',
        jugador = true,
    },
    {
        tecla = 'b',
        icono = 'batallas',
        etiqueta = 'Batallas',
        ayuda = 'Batallas en curso (B)',
        encendido = 'batallasAbiertas',
        cuenta = 'batallas',
        jugador = true,
    },
    {
        tecla = 'noticias',
        icono = 'noticias',
        etiqueta = 'Noticias',
        ayuda = 'Abrir o cerrar las noticias',
        ayudaCuenta = 'Noticias: %d sin leer',
        encendido = 'noticiasAbiertas',
        cuenta = 'noticiasNuevas',
    },
    {
        tecla = 'opciones',
        icono = 'ajustes',
        etiqueta = 'Ajustes',
        ayuda = 'Opciones del juego',
        encendido = 'opcionesAbiertas',
    },
}

function Navegacion.nuevo()
    local self = setmetatable({}, Navegacion)
    self.zonas = {}
    self.ayuda = nil
    self.rect = nil
    return self
end

--- Alto de la barra con su margen inferior, para dejar libre ese espacio.
function Navegacion.alto()
    return Tema.px(96 + 16)
end

--- Dibuja la barra al pie, centrada. `ctx` = { jugador, batallasAbiertas,
-- noticiasAbiertas, noticiasNuevas (sin leer), batallas (las tuyas en curso),
-- ejercitos (los tuyos en batalla) }.
function Navegacion:dibujar(ctx)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    self.ayuda = nil
    local visibles = {}
    for _, b in ipairs(BOTONES) do
        if ctx.jugador or not b.jugador then
            visibles[#visibles + 1] = b
        end
    end
    if #visibles == 0 then
        self.rect = nil
        return
    end
    local bw, bh = Tema.px(72), Tema.px(96)
    local hueco = Tema.px(28)
    local ancho = #visibles * bw + (#visibles - 1) * hueco
    local alto = bh
    local x = math.floor((w - ancho) / 2)
    -- Con un panel de sitio abierto a la derecha, la fila se corre a la izquierda para no pisarlo.
    if ctx.limiteDerecha and x + ancho > ctx.limiteDerecha then
        x = math.max(Tema.px(96), ctx.limiteDerecha - ancho)
    end
    local y = h - Tema.px(16) - alto
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local cx = x
    for n, b in ipairs(visibles) do
        local by = y
        local cuenta = b.cuenta and ctx[b.cuenta] or 0
        local encima = Acero.botonIcono(cx, by, bw, bh, {
            icono = b.icono,
            etiqueta = b.etiqueta,
            activo = b.encendido and ctx[b.encendido] or false,
            cuenta = cuenta,
            -- Un brillo pasa por cada botón de vez en cuando, uno tras otro.
            brillo = -n * 0.35,
        })
        if encima then
            self.ayuda = b.ayuda
            if cuenta > 0 then
                self.ayuda = string.format(b.ayudaCuenta or (b.ayuda .. ': %d'), cuenta)
            end
        end
        self.zonas[#self.zonas + 1] = { x = cx, y = by, w = bw, h = bh, tecla = b.tecla }
        cx = cx + bw + hueco
    end
end

function Navegacion:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- ¿El punto cae sobre la barra?
function Navegacion:encima(x, y)
    local r = self.rect
    return r ~= nil and Tema.dentro(x, y, r.x, r.y, r.w, r.h)
end

--- Clic: devuelve la tecla del botón pulsado (o nil).
function Navegacion:pulsar(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.tecla
        end
    end
    return nil
end

return Navegacion

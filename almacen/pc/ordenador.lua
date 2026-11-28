-- Un ordenador de la sala de control (el dueño, 26-nov): cada puesto es un PC
-- propio con su escritorio, al estilo de un Linux con escritorio (panel abajo
-- con el menú, las ventanas abiertas y el reloj; iconos en el escritorio y
-- ventanas con su barra de título). Lo pinta en su lienzo, que es la textura
-- del monitor del puesto: lo que se deja abierto se ve desde la sala.
--
-- Se usa de verdad desde almacen/pc/uso.lua (acercarse, tecla, la cámara
-- entra en la pantalla): ratón y teclado llegan por `raton`, `tecla` y
-- `texto`, en px del escritorio (1280 x 720).
--
-- Los programas son archivos de almacen/pc/programas/ (se cargan todos
-- solos): cada uno es una herramienta (hoja de cálculo, terminal...) que
-- abre archivos (almacen/pc/archivos.lua). Un programa tiene:
--   titulo, orden            nombre y posición en el menú
--   nuevo(ordenador, opc)    su estado (tabla simple: se guarda)
--   dibujar(estado, ctx, w, h)  su área de la ventana; ctx = { ordenador,
--                            partida, misiles, capacidad, reloj }
--   tituloDe(estado)         (opcional) el título de la ventana
--   icono(x, y, s)           (opcional) su icono en un cuadro de s px
--   raton(estado, ctx, accion, x, y, boton, doble)  (opcional) 'pulsar',
--                            'soltar' o 'mover' en px de su área
--   tecla(estado, ctx, tecla), texto(estado, ctx, t)  (opcional) el teclado
--                            cuando su ventana es la activa
--   Si `nuevo` o una de estas devuelve 'cerrar', se cierra su ventana.
--
-- Lo que guarda (`datos`: ventanas con su programa y estado, y la carpeta
-- personal) es una tabla simple: el almacén la conserva entre visitas.

local Dibujo = require('almacen.pc.dibujo')
local Archivos = require('almacen.pc.archivos')

local Ordenador = {}
Ordenador.__index = Ordenador

Ordenador.sistema = 'Vexar' -- nombre del sistema de los ordenadores (el dueño, 26-nov)
Ordenador.version = '1.0'
Ordenador.ancho = 1280
Ordenador.alto = 720
Ordenador.altoPanel = 44
Ordenador.altoTitulo = 34
Ordenador.dobleClic = 0.35 -- s entre dos clics para que cuenten como doble

local CARPETA = 'almacen/pc/programas'
local programas -- [nombre] = módulo

--- Todos los programas de la carpeta: { [nombre] = módulo }.
function Ordenador.programas()
    if not programas then
        programas = {}
        for _, archivo in ipairs(love.filesystem.getDirectoryItems(CARPETA)) do
            local nombre = archivo:match('^(.+)%.lua$')
            if nombre then
                programas[nombre] = require(CARPETA:gsub('/', '.') .. '.' .. nombre)
            end
        end
    end
    return programas
end

--- Los programas en el orden del menú: { { nombre, modulo }, ... }.
function Ordenador.programasEnOrden()
    local lista = {}
    for nombre, m in pairs(Ordenador.programas()) do
        lista[#lista + 1] = { nombre = nombre, m = m }
    end
    table.sort(lista, function(a, b)
        return (a.m.orden or 99) < (b.m.orden or 99)
    end)
    return lista
end

--- El ordenador `numero` (1-6). `datos`: lo que guardó la última vez, o nil.
function Ordenador.nuevo(numero, datos)
    local self = setmetatable({}, Ordenador)
    self.numero = numero
    self.nombre = 'puesto-' .. numero
    self.datos = datos or { ventanas = {} }
    self.archivos = Archivos.nuevo(self.nombre, self.datos.casa)
    self.datos.casa = self.archivos.casa
    self.lienzo = love.graphics.newCanvas(Ordenador.ancho, Ordenador.alto, { mipmaps = 'auto', dpiscale = Dibujo.densidad })
    self.lienzo:setFilter('linear', 'linear')
    self.lienzo:setMipmapFilter('linear')
    self.zonas = {}
    self.ctx = { ordenador = self }
    return self
end

--- Cada cuadro: los programas que hacen algo solos (la terminal con un
-- programa de Lua corriendo) siguen aunque no se esté mirando la pantalla.
function Ordenador:actualizar(dt)
    local programas = Ordenador.programas()
    for _, v in ipairs(self.datos.ventanas) do
        local m = programas[v.programa]
        if m and m.actualizar then
            m.actualizar(v.estado, self.ctx, dt)
        end
    end
end

--- Abre `programa` en una ventana; sin posición, en cascada. `opciones` van
-- a su `nuevo` (por ejemplo { archivo = '/red/almacen/polvorin.hoja' }).
function Ordenador:abrir(programa, x, y, w, h, opciones)
    local modulo = Ordenador.programas()[programa]
    if not modulo then
        return nil
    end
    if not x then
        local n = #self.datos.ventanas % 6
        w, h = modulo.ancho or 900, modulo.alto or 560
        x, y = 150 + n * 34, 30 + n * 28
    end
    local estado = modulo.nuevo(self, opciones)
    local ventana = { programa = programa, x = x, y = y, w = w, h = h, estado = estado }
    table.insert(self.datos.ventanas, ventana)
    self.menuAbierto = false
    return ventana
end

function Ordenador:cerrarVentana(v)
    for k, otra in ipairs(self.datos.ventanas) do
        if otra == v then
            table.remove(self.datos.ventanas, k)
            return
        end
    end
end

--- Pone `v` delante (la activa es la última).
function Ordenador:activar(v)
    self:cerrarVentana(v)
    table.insert(self.datos.ventanas, v)
    v.minimizada = false
end

function Ordenador:getActiva()
    local ventanas = self.datos.ventanas
    for k = #ventanas, 1, -1 do
        if not ventanas[k].minimizada then
            return ventanas[k]
        end
    end
end

function Ordenador:getLienzo()
    return self.lienzo
end

function Ordenador:cerrar()
    self.lienzo:release()
end

--- Mientras alguien lo usa se pinta el puntero (también se ve en el monitor).
function Ordenador:setEnUso(si)
    self.enUso = si
    if not si then
        self.arrastre = nil
        self.menuAbierto = false
    end
end

-- Entrada ----------------------------------------------------------------------

local function dentro(x, y, z)
    return z and x >= z[1] and y >= z[2] and x < z[1] + z[3] and y < z[2] + z[4]
end

local function maximizar(v)
    if v.maximizada then
        v.x, v.y, v.w, v.h = v.antes[1], v.antes[2], v.antes[3], v.antes[4]
        v.maximizada = false
    else
        v.antes = { v.x, v.y, v.w, v.h }
        v.x, v.y, v.w, v.h = 0, 0, Ordenador.ancho, Ordenador.alto - Ordenador.altoPanel
        v.maximizada = true
    end
end

-- Pasa un evento al programa de `v` (y cierra la ventana si lo pide).
function Ordenador:alPrograma(v, metodo, ...)
    local m = Ordenador.programas()[v.programa]
    if m and m[metodo] then
        -- El tamaño del área del programa (para los que colocan botones a
        -- la derecha).
        self.ctx.anchoVentana, self.ctx.altoVentana = v.w, v.h - Ordenador.altoTitulo
        if m[metodo](v.estado, self.ctx, ...) == 'cerrar' then
            self:cerrarVentana(v)
        end
    end
end

--- El ratón en px del escritorio: `accion` 'pulsar', 'soltar' o 'mover'.
function Ordenador:raton(accion, x, y, boton)
    self.cursor = { x, y }
    local doble = false
    if accion == 'pulsar' then
        local ahora = love.timer.getTime()
        local u = self.ultimoClic
        doble = u and ahora - u.t < Ordenador.dobleClic and math.abs(u.x - x) < 6 and math.abs(u.y - y) < 6
        self.ultimoClic = { t = ahora, x = x, y = y }
    end
    -- Arrastrando una ventana por su barra.
    if self.arrastre then
        local a = self.arrastre
        if accion == 'mover' then
            a.v.x = math.max(-a.v.w + 80, math.min(Ordenador.ancho - 80, x - a.dx))
            a.v.y = math.max(0, math.min(Ordenador.alto - Ordenador.altoPanel - Ordenador.altoTitulo, y - a.dy))
        elseif accion == 'soltar' then
            self.arrastre = nil
        end
        return
    end
    -- Lo que se suelta o se mueve va a la ventana activa (selecciones...).
    if accion ~= 'pulsar' then
        local v = self:getActiva()
        if v then
            self:alPrograma(v, 'raton', accion, x - v.x, y - v.y - Ordenador.altoTitulo, boton, false)
        end
        return
    end
    local z = self.zonas
    -- El menú de programas, si está abierto.
    if self.menuAbierto then
        for _, item in ipairs(z.menu or {}) do
            if dentro(x, y, item) then
                self:abrir(item.programa)
                return
            end
        end
        self.menuAbierto = false
        if not dentro(x, y, z.botonMenu) then
            return
        end
    end
    -- Panel: botón del menú y tareas.
    if dentro(x, y, z.botonMenu) then
        self.menuAbierto = not self.menuAbierto
        return
    end
    for _, t in ipairs(z.tareas or {}) do
        if dentro(x, y, t) then
            if t.v == self:getActiva() then
                t.v.minimizada = true
            else
                self:activar(t.v)
            end
            return
        end
    end
    if y >= Ordenador.alto - Ordenador.altoPanel then
        return
    end
    -- Ventanas, de la de delante a la de atrás.
    local ventanas = self.datos.ventanas
    for k = #ventanas, 1, -1 do
        local v = ventanas[k]
        if not v.minimizada and x >= v.x and y >= v.y and x < v.x + v.w and y < v.y + v.h then
            self:activar(v)
            local alto = Ordenador.altoTitulo
            if y < v.y + alto then
                -- Barra de título: botones (cerrar, maximizar, minimizar) o arrastrar.
                local bx, by = v.x + v.w - 24, v.y + alto / 2
                if (x - bx) ^ 2 + (y - by) ^ 2 < 12 ^ 2 then
                    self:cerrarVentana(v)
                elseif (x - bx + 30) ^ 2 + (y - by) ^ 2 < 12 ^ 2 then
                    maximizar(v)
                elseif (x - bx + 60) ^ 2 + (y - by) ^ 2 < 12 ^ 2 then
                    v.minimizada = true
                elseif doble then
                    maximizar(v)
                elseif not v.maximizada then
                    self.arrastre = { v = v, dx = x - v.x, dy = y - v.y }
                end
            else
                self:alPrograma(v, 'raton', 'pulsar', x - v.x, y - v.y - alto, boton, doble)
            end
            return
        end
    end
    -- Escritorio: iconos (doble clic los abre).
    for _, icono in ipairs(z.iconos or {}) do
        if dentro(x, y, icono) then
            self.iconoElegido = icono.nombre
            if doble then
                self:abrir(icono.programa, nil, nil, nil, nil, icono.opciones)
            end
            return
        end
    end
    self.iconoElegido = nil
end

--- Una tecla (love.keypressed) para la ventana activa.
function Ordenador:tecla(tecla)
    if self.menuAbierto and tecla == 'escape' then
        self.menuAbierto = false
        return
    end
    local v = self:getActiva()
    if v then
        self:alPrograma(v, 'tecla', tecla)
    end
end

--- La rueda del ratón para la ventana activa.
function Ordenador:rueda(dy)
    local v = self:getActiva()
    if v then
        self:alPrograma(v, 'rueda', dy)
    end
end

--- Texto escrito (love.textinput) para la ventana activa.
function Ordenador:texto(t)
    local v = self:getActiva()
    if v then
        self:alPrograma(v, 'texto', t)
    end
end

-- Pintar -----------------------------------------------------------------------

local function fondoEscritorio(self, w, h)
    local g = love.graphics
    -- Degradado de azul petróleo a casi negro, con un halo verde abajo a la
    -- derecha (el verde de la sala).
    local pasos = 24
    for k = 0, pasos - 1 do
        local f = k / (pasos - 1)
        g.setColor(0.035 + 0.03 * (1 - f), 0.07 + 0.05 * (1 - f), 0.09 + 0.06 * (1 - f))
        g.rectangle('fill', 0, h * k / pasos, w, h / pasos + 1)
    end
    for k = 8, 1, -1 do
        g.setColor(0.1, 0.5, 0.28, 0.025)
        g.circle('fill', w * 0.82, h * 0.78, 60 * k)
    end
    g.setColor(1, 1, 1, 0.07)
    g.setFont(Dibujo.letra('titulo', 64))
    g.printf(self.nombre:upper(), 0, h - Ordenador.altoPanel - 96, w - 40, 'right')
    g.setColor(1, 1, 1, 0.05)
    g.setFont(Dibujo.letra('dato', 18))
    g.printf(Ordenador.sistema .. ' ' .. Ordenador.version, 0, h - Ordenador.altoPanel - 28, w - 44, 'right')
end

function Ordenador.iconoCarpeta(x, y, s, color, emblema)
    require('almacen.pc.iconos').carpeta(x, y, s, color, emblema)
end

local function iconoPersonal(x, y, s)
    Ordenador.iconoCarpeta(x, y, s, { 0.88, 0.68, 0.3 }, 'casa')
end

local function iconoRed(x, y, s)
    Ordenador.iconoCarpeta(x, y, s, { 0.36, 0.62, 0.92 }, 'red')
end

-- Iconos del escritorio: carpetas y programas.
local function iconos(self, h)
    local g = love.graphics
    local lista = {
        { nombre = 'Carpeta personal', dibujar = iconoPersonal, programa = 'archivos', opciones = { ruta = '/home/operador' } },
        { nombre = 'Red del almacén', dibujar = iconoRed, programa = 'archivos', opciones = { ruta = '/red/almacen' } },
    }
    for _, p in ipairs(Ordenador.programasEnOrden()) do
        if p.m.icono and p.nombre ~= 'archivos' then
            lista[#lista + 1] = { nombre = p.m.titulo, dibujar = p.m.icono, programa = p.nombre }
        end
    end
    local letra = Dibujo.letra('titulo', 18)
    g.setFont(letra)
    self.zonas.iconos = {}
    -- En columnas de arriba abajo, como en un escritorio de verdad.
    local porColumna = math.floor((h - Ordenador.altoPanel - 24) / 104)
    for k, icono in ipairs(lista) do
        local columna = math.floor((k - 1) / porColumna)
        local x, y = 28 + columna * 124, 24 + ((k - 1) % porColumna) * 104
        if self.iconoElegido == icono.nombre then
            g.setColor(0.24, 0.7, 0.4, 0.25)
            g.rectangle('fill', x - 8, y - 6, 108, 100, 6)
        end
        icono.dibujar(x + 18, y, 56)
        g.setColor(0, 0, 0, 0.5)
        g.printf(icono.nombre, x - 10 + 1, y + 62 + 1, 112, 'center')
        g.setColor(0.94, 0.96, 0.96)
        g.printf(icono.nombre, x - 10, y + 62, 112, 'center')
        icono[1], icono[2], icono[3], icono[4] = x - 8, y - 6, 108, 100
        self.zonas.iconos[#self.zonas.iconos + 1] = icono
    end
end

local function ventana(self, v, activa, ctx)
    local g = love.graphics
    local m = Ordenador.programas()[v.programa]
    if not m then
        return
    end
    local alto = Ordenador.altoTitulo
    -- Sombra.
    if not v.maximizada then
        for k = 1, 6 do
            g.setColor(0, 0, 0, 0.06)
            g.rectangle('fill', v.x - k + 3, v.y - k + 6, v.w + 2 * k, v.h + 2 * k, 8)
        end
    end
    -- Barra de título.
    g.setColor(activa and { 0.15, 0.16, 0.18 } or { 0.11, 0.12, 0.13 })
    g.rectangle('fill', v.x, v.y, v.w, alto + 6, v.maximizada and 0 or 6)
    if m.icono then
        m.icono(v.x + 10, v.y + 7, 20)
    end
    g.setColor(activa and { 0.93, 0.95, 0.95 } or { 0.6, 0.64, 0.65 })
    g.setFont(Dibujo.letra('titulo', 20))
    local titulo = m.tituloDe and m.tituloDe(v.estado) or m.titulo
    g.printf(titulo, v.x + 40, v.y + 5, v.w - 160, 'left')
    -- Botones: cerrar (rojo), maximizar y minimizar.
    local bx, by = v.x + v.w - 24, v.y + alto / 2
    local raton = self.enUso and self.cursor
    for k, color in ipairs({ { 0.86, 0.3, 0.28 }, { 0.42, 0.45, 0.47 }, { 0.42, 0.45, 0.47 } }) do
        local cx = bx - (k - 1) * 30
        local encima = raton and (raton[1] - cx) ^ 2 + (raton[2] - by) ^ 2 < 12 ^ 2
        g.setColor(encima and { math.min(1, color[1] + 0.15), math.min(1, color[2] + 0.15), math.min(1, color[3] + 0.15) } or color)
        g.circle('fill', cx, by, 8)
        if encima then
            g.setColor(0.08, 0.08, 0.09)
            g.setLineWidth(2)
            if k == 1 then
                g.line(cx - 3.5, by - 3.5, cx + 3.5, by + 3.5)
                g.line(cx - 3.5, by + 3.5, cx + 3.5, by - 3.5)
            elseif k == 2 then
                g.rectangle('line', cx - 3.5, by - 3.5, 7, 7)
            else
                g.line(cx - 4, by, cx + 4, by)
            end
            g.setLineWidth(1)
        end
    end
    -- Contenido.
    g.push()
    g.translate(v.x, v.y + alto)
    g.intersectScissor(v.x, v.y + alto, v.w, v.h - alto)
    m.dibujar(v.estado, ctx, v.w, v.h - alto)
    g.setScissor()
    g.pop()
    -- Borde (el de la activa, verde).
    g.setLineWidth(1)
    g.setColor(activa and { 0.24, 0.7, 0.4, 0.9 } or { 0.25, 0.27, 0.28, 1 })
    g.rectangle('line', v.x + 0.5, v.y + 0.5, v.w - 1, v.h - 1, v.maximizada and 0 or 4)
end

local function panel(self, w, h)
    local g = love.graphics
    local alto = Ordenador.altoPanel
    local y = h - alto
    g.setColor(0.06, 0.07, 0.08, 0.96)
    g.rectangle('fill', 0, y, w, alto)
    g.setColor(1, 1, 1, 0.06)
    g.rectangle('fill', 0, y, w, 1)
    -- Botón del menú: 3 x 3 puntos.
    self.zonas.botonMenu = { 6, y + 4, 40, alto - 8 }
    if self.menuAbierto then
        g.setColor(1, 1, 1, 0.1)
        g.rectangle('fill', 6, y + 4, 40, alto - 8, 4)
    end
    g.setColor(0.24, 0.7, 0.4)
    for f = 0, 2 do
        for c = 0, 2 do
            g.rectangle('fill', 16 + c * 8, y + 12 + f * 8, 5, 5, 1)
        end
    end
    -- Una tarea por ventana abierta (en el orden en que se abrieron no:
    -- en el de la lista, como el panel de KDE).
    local x = 60
    local letra = Dibujo.letra('titulo', 18)
    g.setFont(letra)
    self.zonas.tareas = {}
    local activa = self:getActiva()
    for _, v in ipairs(self.datos.ventanas) do
        local m = Ordenador.programas()[v.programa]
        if m then
            local texto = m.tituloDe and m.tituloDe(v.estado) or m.titulo
            local ancho = math.min(260, letra:getWidth(texto) + 50)
            g.setColor(1, 1, 1, v == activa and 0.1 or 0.04)
            g.rectangle('fill', x, y + 5, ancho, alto - 10, 4)
            if m.icono then
                m.icono(x + 8, y + 11, 22)
            end
            g.setColor(v.minimizada and { 0.6, 0.64, 0.65 } or { 0.88, 0.91, 0.91 })
            g.intersectScissor(x, y, ancho - 6, alto)
            g.print(texto, x + 38, y + 11)
            g.setScissor()
            if v == activa then
                g.setColor(0.24, 0.7, 0.4)
                g.rectangle('fill', x + 6, y + alto - 5, ancho - 12, 3, 1)
            end
            self.zonas.tareas[#self.zonas.tareas + 1] = { x, y + 5, ancho, alto - 10, v = v }
            x = x + ancho + 6
        end
    end
    -- A la derecha: red, nombre del puesto y reloj.
    g.setFont(Dibujo.letra('dato', 16))
    g.setColor(0.92, 0.94, 0.94)
    g.printf(os.date('%H:%M'), w - 130, y + 4, 116, 'right')
    g.setColor(0.6, 0.65, 0.66)
    g.setFont(Dibujo.letra('dato', 13))
    g.printf(os.date('%d/%m/%Y'), w - 130, y + 24, 116, 'right')
    g.setFont(Dibujo.letra('dato', 15))
    g.printf(self.nombre, w - 330, y + 13, 180, 'right')
    g.setColor(0.24, 0.7, 0.4)
    for k = 1, 3 do
        g.rectangle('fill', w - 144 + k * 6, y + 30 - k * 5, 4, k * 5)
    end
end

-- El menú de programas (encima del botón del panel).
local function menu(self, h)
    local g = love.graphics
    local lista = Ordenador.programasEnOrden()
    local alto = 48
    local w = 300
    local x, y = 6, h - Ordenador.altoPanel - 16 - #lista * alto - 44
    g.setColor(0.09, 0.1, 0.11, 0.98)
    g.rectangle('fill', x, y, w, #lista * alto + 52, 8)
    g.setColor(0.24, 0.7, 0.4, 0.8)
    g.rectangle('line', x + 0.5, y + 0.5, w - 1, #lista * alto + 51, 8)
    g.setColor(0.6, 0.65, 0.66)
    g.setFont(Dibujo.letra('dato', 14))
    g.print(Ordenador.sistema:upper() .. ' · PROGRAMAS', x + 18, y + 14)
    self.zonas.menu = {}
    g.setFont(Dibujo.letra('titulo', 22))
    local raton = self.cursor
    for k, p in ipairs(lista) do
        local iy = y + 40 + (k - 1) * alto
        local zona = { x + 6, iy, w - 12, alto - 4, programa = p.nombre }
        if raton and dentro(raton[1], raton[2], zona) then
            g.setColor(0.17, 0.42, 0.26)
            g.rectangle('fill', zona[1], zona[2], zona[3], zona[4], 5)
        end
        if p.m.icono then
            p.m.icono(x + 16, iy + 8, 30)
        end
        g.setColor(0.92, 0.94, 0.94)
        g.print(p.m.titulo, x + 60, iy + 10)
        self.zonas.menu[#self.zonas.menu + 1] = zona
    end
end

local function puntero(x, y)
    local g = love.graphics
    local forma = { x, y, x, y + 22, x + 6, y + 17, x + 10, y + 26, x + 14, y + 24, x + 10, y + 15, x + 17, y + 15 }
    g.setColor(0.98, 0.98, 0.98)
    g.polygon('fill', forma[1], forma[2], forma[3], forma[4], forma[5], forma[6], forma[13], forma[14])
    g.polygon('fill', forma[5], forma[6], forma[7], forma[8], forma[9], forma[10], forma[11], forma[12])
    g.setColor(0.05, 0.05, 0.05)
    g.setLineWidth(1.5)
    g.polygon('line', forma)
    g.setLineWidth(1)
end

--- Pinta el escritorio entero en el lienzo. `ctx`: partida, misiles,
-- capacidad y reloj.
function Ordenador:pintar(ctx)
    local g = love.graphics
    local w, h = Ordenador.ancho, Ordenador.alto
    ctx.ordenador = self
    self.ctx = ctx
    g.push('all')
    g.origin()
    g.setCanvas(self.lienzo)
    g.clear(0, 0, 0, 1)
    fondoEscritorio(self, w, h)
    iconos(self, h)
    local ventanas = self.datos.ventanas
    local activa = self:getActiva()
    for _, v in ipairs(ventanas) do
        if not v.minimizada then
            ventana(self, v, v == activa, ctx)
        end
    end
    panel(self, w, h)
    if self.menuAbierto then
        menu(self, h)
    end
    if self.enUso and self.cursor then
        puntero(self.cursor[1], self.cursor[2])
    end
    g.setCanvas()
    g.pop()
end

return Ordenador

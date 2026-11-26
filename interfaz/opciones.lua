-- Opciones (diseno/interfaz-militar.md, §5.15): pantalla completa de la
-- familia clara. Una rejilla de dos columnas de botones anchos con icono,
-- desplazable con la rueda; cada botón lleva a una subpantalla: General
-- (calidad, resolución, pantalla completa, vsync, FPS, sombras, oclusión y
-- volúmenes), Ayuda, Versión, Idioma y Guardado. «Comandante» abre el perfil.
--
-- Los ajustes se editan en un borrador y solo «Aplicar» los pone en marcha y
-- los guarda (`interfaz/ajustes.lua`). `pulsar` devuelve la acción para
-- main.lua (`cerrar`, `perfil`, `guardar`, `cargar`).

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Clara = require('interfaz.clara')
local Ajustes = require('interfaz.ajustes')
local Simulacion = require('mundo.simulacion')

local Opciones = {}
Opciones.__index = Opciones

-- Botones de la rejilla en orden de lectura (izquierda, derecha, siguiente fila).
local BOTONES = {
    { id = 'general', texto = 'General', icono = 'ajustes' },
    { id = 'idioma', texto = 'Idioma', icono = 'mundo' },
    { id = 'perfil', texto = 'Comandante', icono = 'perfil' },
    { id = 'ayuda', texto = 'Ayuda y atajos', icono = 'misiones' },
    { id = 'guardado', texto = 'Guardado', icono = 'guardar' },
    { id = 'version', texto = 'Versión', icono = 'nivel' },
    { id = 'nueva', texto = 'Nueva partida', icono = 'retirar' },
    { id = 'creditos', texto = 'Créditos', icono = 'alianza' },
}

local TITULOS = {
    menu = 'Opciones',
    general = 'Opciones generales',
    idioma = 'Idioma',
    ayuda = 'Ayuda y atajos',
    nueva = 'Nueva partida',
    creditos = 'Créditos',
    guardado = 'Guardado',
    version = 'Versión',
}

-- Teclas de la ayuda: { tecla, qué hace }.
local TECLAS = {
    { 'Rueda del ratón', 'Acercar y alejar' },
    { 'Clic izquierdo', 'Elegir un ejército o abrir un sitio' },
    { 'Clic derecho', 'Quitar la selección (arrastrando: mover la cámara)' },
    { 'Arrastrar desde tu ejército elegido', 'Mandarlo adonde sueltes' },
    { 'Espacio', 'Pausa' },
    { '1 a 4', 'Velocidad del tiempo' },
    { 'P', 'Plantar bandera' },
    { 'T', 'Mostrar los territorios' },
    { 'B', 'Batallas en curso' },
    { 'X', 'Ir al último ataque' },
    { 'C', 'Ir a la ciudad más cercana' },
    { 'Ctrl + A', 'Elegir todos tus ejércitos' },
    { 'F5 / F9', 'Guardar / cargar la partida' },
    { 'Esc', 'Cerrar el panel abierto' },
}

function Opciones.nuevo()
    local self = setmetatable({}, Opciones)
    self.abierta = false
    self.pantalla = 'menu'
    self.desplazo = 0
    self.zonas = {}
    self.ayuda = nil
    self.borrador = Ajustes.copiar(Ajustes.valores)
    self.desplegado = nil -- 'calidad' o 'resolucion'
    self.arrastrando = nil
    self.aviso = nil
    return self
end

function Opciones:abrir()
    self.abierta = true
    self.pantalla = 'menu'
    self.desplazo = 0
    self.desplegado = nil
    self.borrador = Ajustes.copiar(Ajustes.valores)
    self.aviso = nil
end

function Opciones:cerrar()
    self.abierta = false
    self.desplegado = nil
    self.arrastrando = nil
end

--- Atrás: de una subpantalla al menú; del menú, cierra. Devuelve si sigue abierta.
function Opciones:atras()
    if self.desplegado then
        self.desplegado = nil
    elseif self.pantalla ~= 'menu' then
        self.pantalla = 'menu'
        self.desplazo = 0
    else
        self:cerrar()
    end
    return self.abierta
end

--- Rueda: desplaza la rejilla o la lista. Devuelve si la usó.
function Opciones:rueda(dy)
    if not self.abierta then
        return false
    end
    self.desplazo = math.max(0, math.min(self.maxDesplazo or 0, self.desplazo - dy * Tema.px(48)))
    return true
end

--- Zona que se puede pulsar en este cuadro.
function Opciones:zona(x, y, w, h, accion, dato)
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, accion = accion, dato = dato }
end

--- Rejilla del menú: dos columnas, con desplazamiento.
function Opciones:dibujarMenu(dw, dh, arriba)
    local px = Tema.px
    -- Proporciones del Warpath original (referencia del dueño, 2026-09-30):
    -- cada botón ocupa un cuarto del ancho de la pantalla, separación fija y
    -- la lista sigue hacia abajo con desplazamiento si no cabe.
    local ancho = math.floor(dw * 0.25)
    local alto = math.floor(dh * 0.083)
    local hueco = math.floor(dw * 0.05)
    local vueco = math.floor(dh * 0.034)
    local total = math.ceil(#BOTONES / 2) * (alto + vueco) - vueco
    local libre = dh - arriba - 40
    self.maxDesplazo = math.max(0, px(total - libre))
    self.desplazo = math.min(self.desplazo, self.maxDesplazo)
    local x0 = (dw - (ancho * 2 + hueco)) / 2
    arriba = arriba + 20
    -- Si caben todos, la rejilla va centrada en el alto que queda.
    if total < libre then
        arriba = arriba + math.floor((dh - arriba - total) * 0.35)
    end
    local g = love.graphics
    g.setScissor(0, px(arriba), g.getWidth(), g.getHeight() - px(arriba))
    for k, b in ipairs(BOTONES) do
        local col, fila = (k - 1) % 2, math.floor((k - 1) / 2)
        local x = px(x0 + col * (ancho + hueco))
        local y = px(arriba + fila * (alto + vueco)) - self.desplazo
        Clara.filaOpcion(x, y, px(ancho), px(alto), b.texto, b.icono)
        self:zona(x, y, px(ancho), px(alto), 'ir', b.id)
    end
    g.setScissor()
    if self.maxDesplazo > 0 then
        Acero.desplazamiento(
            px(70),
            px(arriba),
            g.getHeight() - px(arriba) - px(40),
            px(libre),
            px(total),
            self.desplazo / self.maxDesplazo
        )
    end
end

-- Ajustes de General (opciones_generales_*.jpg): secciones con su barra
-- negra y, en cada una, los ajustes en dos columnas. `tipo`: 'opciones'
-- (botones hexagonales), 'lista' (desplegable), 'interruptor' o 'deslizador'.
local SECCIONES = {
    {
        titulo = 'IMAGEN',
        ajustes = {
            {
                id = 'calidad',
                tipo = 'opciones',
                titulo = 'Calidad gráfica',
                texto = 'Distancias de detalle, sombras y oclusión de la batalla 3D.',
                opciones = { { 'Baja', 'baja' }, { 'Media', 'media' }, { 'Alta', 'alta' } },
            },
            {
                id = 'resolucion',
                tipo = 'lista',
                titulo = 'Resolución',
                texto = 'A pantalla completa, la del monitor; elegir otra pasa a ventana.',
            },
            {
                id = 'pantallaCompleta',
                tipo = 'interruptor',
                titulo = 'Pantalla completa',
                texto = 'Siempre a la resolución del monitor.',
            },
            {
                id = 'vsync',
                tipo = 'interruptor',
                titulo = 'Sincronización vertical',
                texto = 'Evita cortes en la imagen; los FPS no pasan de los del monitor.',
            },
            {
                id = 'sombras',
                tipo = 'interruptor',
                titulo = 'Sombras dinámicas',
                texto = 'Sombras del sol y de la luna en la batalla 3D.',
            },
            {
                id = 'oclusion',
                tipo = 'interruptor',
                titulo = 'Oclusión ambiental',
                texto = 'Sombra suave en los rincones de la batalla; se nota al reiniciar la escena.',
            },
        },
    },
    {
        titulo = 'VOLUMEN',
        ajustes = {
            {
                id = 'volumen',
                tipo = 'deslizador',
                titulo = 'Volumen general',
                texto = 'Desliza para ajustar el volumen de todo el juego.',
            },
            {
                id = 'efectos',
                tipo = 'deslizador',
                titulo = 'Volumen de efectos',
                texto = 'Disparos, explosiones y motores de la batalla.',
            },
        },
    },
    {
        titulo = 'PERSONALIZAR',
        ajustes = {
            {
                id = 'mostrarFps',
                tipo = 'interruptor',
                titulo = 'Mostrar FPS',
                texto = 'Los cuadros por segundo, arriba a la derecha de la pantalla.',
            },
        },
    },
}

--- Botón de opción hexagonal (Bajo / Medio / Alto): verde el elegido, gris
-- oscuro los demás; la etiqueta debajo, dorada si está elegido. Devuelve si
-- el ratón está encima.
local function opcionHex(cx, cy, r, texto, elegido, fuente)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local ancho = math.max(r * 2, fuente:getWidth(texto)) + r
    local encima = Tema.dentro(mx, my, cx - ancho / 2, cy - r, ancho, r * 2 + fuente:getHeight() + r * 0.6)
    local function hexagono(radio)
        local puntos = {}
        for k = 0, 5 do
            local a = k * math.pi / 3
            puntos[#puntos + 1] = cx + math.cos(a) * radio
            puntos[#puntos + 1] = cy + math.sin(a) * radio
        end
        return puntos
    end
    g.setColor(0.2, 0.2, 0.2, 1)
    g.polygon('fill', hexagono(r))
    if elegido then
        g.setColor(0.42, 0.78, 0.22, 1)
        g.polygon('fill', hexagono(r * 0.74))
        g.setColor(0.7, 0.95, 0.45, 0.8)
        g.polygon('line', hexagono(r * 0.74))
    else
        g.setColor(encima and 0.42 or 0.3, encima and 0.42 or 0.3, encima and 0.42 or 0.3, 1)
        g.polygon('fill', hexagono(r * 0.74))
    end
    g.setFont(fuente)
    if elegido then
        Tema.color('poderMarron')
    else
        Tema.color(encima and 'tintaTenue' or 'tinta')
    end
    g.print(texto, math.floor(cx - fuente:getWidth(texto) / 2), math.floor(cy + r + r * 0.35))
    return encima
end

--- Deslizador de Warpath: canal oscuro, relleno verde y pomo hexagonal claro.
local function deslizadorVerde(x, y, w, alto, valor)
    local g = love.graphics
    local v = math.max(0, math.min(1, valor))
    g.setColor(0.25, 0.25, 0.25, 1)
    g.rectangle('fill', x, y - alto / 2, w, alto)
    if v > 0 then
        Tema.degradado(x + 1, y - alto / 2 + 1, (w - 2) * v, alto - 2, { 0.55, 0.86, 0.3 }, { 0.32, 0.62, 0.14 })
    end
    local r = alto * 1.1
    local px = x + w * v
    local puntos = {}
    for k = 0, 5 do
        local a = k * math.pi / 3
        puntos[#puntos + 1] = px + math.cos(a) * r
        puntos[#puntos + 1] = y + math.sin(a) * r
    end
    g.setColor(0.93, 0.93, 0.93, 1)
    g.polygon('fill', puntos)
    g.setColor(0.45, 0.45, 0.45, 1)
    g.polygon('line', puntos)
end

--- Subpantalla General: las secciones en una lista que se desplaza con la
-- rueda; abajo, fijos, el aviso, «Restablecer» y «Aplicar».
function Opciones:dibujarGeneral(_, dh)
    local g = love.graphics
    local w, h = g.getDimensions()
    -- Tamaño en proporción a la pantalla (el dueño, 2026-09-30): todo crece
    -- con el alto (`k`, la misma medida de antes: una fila de 52 = 6 %).
    local k = dh * 0.06 / 52
    local function px(valor)
        return Tema.px(valor * k)
    end
    local function fuenteK(tipo, tam)
        return Acero.fuente(tipo, tam * k)
    end
    local v = self.borrador
    local mx, my = love.mouse.getPosition()
    local fTitulo = fuenteK('boton', 16.5)
    local fTexto = fuenteK('cuerpo', 11)
    local fOpcion = fuenteK('boton', 14)
    local fBarra = fuenteK('titulo', 15)
    -- Marco: el panel ocupa casi todo el ancho; las columnas, como en Warpath.
    local panelX = math.floor(w * 0.055)
    local panelW = w - panelX * 2
    local colW = math.floor(panelW * 0.38)
    local colX = { panelX + math.floor(panelW * 0.09), panelX + math.floor(panelW * 0.53) }
    local arribaPx = px(64)
    local pieH = px(46)
    local abajoPx = h - pieH - px(24)
    local barraH = px(32)
    local hueco = px(22)
    local resoluciones = Ajustes.resoluciones()
    local anchoMonitor, altoMonitor = love.window.getDesktopDimensions()
    local rw, rh = v.ancho or anchoMonitor, v.alto or altoMonitor
    local personalizada = Ajustes.personalizada(v)

    --- Alto de un ajuste (su texto y su control).
    local function altoAjuste(a)
        local anchoTexto = colW - (a.tipo == 'interruptor' and px(70) or 0)
        local _, lineas = fTexto:getWrap(a.texto, anchoTexto)
        local texto = fTitulo:getHeight() + math.min(3, #lineas) * fTexto:getHeight() + px(6)
        if a.tipo == 'opciones' then
            return texto + px(18) + px(26) + fOpcion:getHeight() + px(12)
        elseif a.tipo == 'lista' then
            return texto + px(10) + px(30) + px(12)
        elseif a.tipo == 'deslizador' then
            return texto + px(26) + px(10)
        end
        return texto + px(12)
    end

    -- Medidas de toda la lista para el desplazamiento.
    local total = 0
    for _, s in ipairs(SECCIONES) do
        total = total + barraH + px(10)
        for f = 1, #s.ajustes, 2 do
            total = total + math.max(altoAjuste(s.ajustes[f]), s.ajustes[f + 1] and altoAjuste(s.ajustes[f + 1]) or 0)
        end
        total = total + px(8) + hueco
    end
    total = total - hueco
    local visible = abajoPx - arribaPx
    self.maxDesplazo = math.max(0, total - visible)
    self.desplazo = math.max(0, math.min(self.desplazo, self.maxDesplazo))
    self.deslizadores = self.deslizadores or {}
    local listaAbierta -- { x, y, w } del desplegable abierto

    --- Zona solo si se ve (dentro de la lista desplazada).
    local function zonaVisible(x, y, zw, zh, accion, dato)
        local y0, y1 = math.max(y, arribaPx), math.min(y + zh, abajoPx)
        if y1 > y0 then
            self:zona(x, y0, zw, y1 - y0, accion, dato)
        end
        return y1 > y0
    end

    --- Un ajuste en (x, y): título, texto y su control.
    local function dibujarAjuste(a, x, y, alto)
        local anchoTexto = colW - (a.tipo == 'interruptor' and px(70) or 0)
        g.setFont(fTitulo)
        Tema.color('tinta')
        g.print(Tema.cortar(fTitulo, a.titulo, anchoTexto), x, y)
        local ty = y + fTitulo:getHeight()
        local _, lineas = fTexto:getWrap(a.texto, anchoTexto)
        local n = math.min(3, #lineas)
        g.setFont(fTexto)
        Tema.color('tintaTenue')
        for l = 1, n do
            local linea = lineas[l]
            if l == n and #lineas > n then
                linea = Tema.cortar(fTexto, linea .. ' ' .. lineas[l + 1], anchoTexto)
            end
            g.print(linea, x, ty + (l - 1) * fTexto:getHeight())
        end
        if a.id == 'calidad' and personalizada then
            -- «Personalizada»: cambiaste las sombras o la oclusión a mano.
            local aviso = 'Ahora: personalizada'
            local ultima = lineas[n] or ''
            local fin = x + fTexto:getWidth(ultima .. ' ')
            local ay = ty + (n - 1) * fTexto:getHeight()
            if fin + fTexto:getWidth(aviso) > x + anchoTexto then
                fin = x + anchoTexto - fTexto:getWidth(aviso)
                -- No cabe tras el texto: a la derecha, en la línea del título.
                ay = ty - fTexto:getHeight()
            end
            Tema.color('poderMarron')
            g.print(aviso, fin, ay)
        end
        local cy = ty + n * fTexto:getHeight() + px(6)
        if a.tipo == 'opciones' then
            local r = px(14)
            local paso = colW / #a.opciones
            for i, o in ipairs(a.opciones) do
                local ox = x + paso * (i - 1) + paso / 2
                local oy = cy + px(6) + r
                local elegido = v.calidad == o[2] and not personalizada
                opcionHex(ox, oy, r, o[1], elegido, fOpcion)
                zonaVisible(ox - paso / 2, oy - r, paso, r * 2 + fOpcion:getHeight() + px(8), 'elegirCalidad', o[2])
            end
        elseif a.tipo == 'lista' then
            local lw, lh = math.min(colW, px(200)), px(30)
            Clara.desplegable(x, cy + px(6), lw, lh, '', self.desplegado == 'resolucion')
            local fl = fuenteK('cuerpo', 12)
            g.setFont(fl)
            Tema.color('tinta')
            g.print(rw .. ' × ' .. rh, x + px(8), cy + px(6) + math.floor((lh - fl:getHeight()) / 2))
            zonaVisible(x, cy + px(6), lw, lh, 'desplegar', 'resolucion')
            if self.desplegado == 'resolucion' then
                listaAbierta = { x = x, y = cy + px(6) + lh, w = lw }
            end
        elseif a.tipo == 'deslizador' then
            local sy = cy + px(12)
            local pc = math.floor(v[a.id] * 100 + 0.5) .. ' %'
            local pcW = fOpcion:getWidth('100 %') + px(10)
            local sw = colW - pcW - px(16)
            deslizadorVerde(x + px(8), sy, sw - px(8), px(9), v[a.id])
            self.deslizadores[a.id] = { x = x + px(8), w = sw - px(8) }
            zonaVisible(x, sy - px(12), sw + px(8), px(24), 'deslizar', a.id)
            g.setFont(fOpcion)
            Tema.color('tinta')
            g.print(pc, x + colW - fOpcion:getWidth(pc), sy - fOpcion:getHeight() / 2)
        elseif a.tipo == 'interruptor' then
            local iw, ih = px(58), px(29)
            local ix = x + colW - iw
            local iy = y + math.floor((alto - px(12) - ih) / 2)
            local encima = Clara.interruptor(ix, iy, iw, ih, v[a.id])
            zonaVisible(ix, iy, iw, ih, 'conmutar', a.id)
            if encima and my > arribaPx and my < abajoPx then
                self.ayuda = a.titulo .. ': ' .. (v[a.id] and 'encendido' or 'apagado')
            end
        end
        -- Raya bajo el ajuste.
        g.setColor(0.55, 0.55, 0.55, 0.6)
        g.rectangle('fill', x, y + alto - px(6), colW, 1)
    end

    g.setScissor(0, arribaPx, w, abajoPx - arribaPx)
    local y = arribaPx - self.desplazo
    for _, s in ipairs(SECCIONES) do
        local alto = barraH + px(10)
        for f = 1, #s.ajustes, 2 do
            alto = alto + math.max(altoAjuste(s.ajustes[f]), s.ajustes[f + 1] and altoAjuste(s.ajustes[f + 1]) or 0)
        end
        alto = alto + px(8)
        -- Tarjeta clara de la sección con su barra negra.
        g.setColor(0, 0, 0, 0.18)
        g.rectangle('fill', panelX + px(3), y + px(4), panelW, alto)
        Tema.degradado(panelX, y, panelW, alto, { 0.92, 0.92, 0.92 }, { 0.87, 0.87, 0.87 })
        g.setColor(0.08, 0.08, 0.08, 0.95)
        g.rectangle('fill', panelX, y, panelW, barraH)
        g.setFont(fBarra)
        g.setColor(0.96, 0.96, 0.94, 1)
        g.print(s.titulo, panelX + px(12), y + math.floor((barraH - fBarra:getHeight()) / 2))
        local fy = y + barraH + px(10)
        for f = 1, #s.ajustes, 2 do
            local izq, der = s.ajustes[f], s.ajustes[f + 1]
            local filaH = math.max(altoAjuste(izq), der and altoAjuste(der) or 0)
            dibujarAjuste(izq, colX[1], fy, filaH)
            if der then
                dibujarAjuste(der, colX[2], fy, filaH)
            end
            fy = fy + filaH
        end
        y = y + alto + hueco
    end
    g.setScissor()
    if self.maxDesplazo > 0 then
        Acero.desplazamiento(
            panelX + panelW + px(6),
            arribaPx,
            visible,
            visible,
            total,
            self.desplazo / self.maxDesplazo
        )
    end
    -- Pie fijo: aviso, Restablecer y Aplicar.
    local by = h - pieH - px(12)
    local bw = px(150)
    local xb = panelX + panelW - bw * 2 - px(14)
    if self.aviso then
        local fuente = fuenteK('cuerpo', 11)
        g.setFont(fuente)
        Tema.color('rojo')
        g.print(Tema.cortar(fuente, self.aviso, xb - panelX - px(20)), panelX, by + (pieH - fuente:getHeight()) / 2)
    end
    Acero.boton({ texto = 'Restablecer', tipo = 'secundario' }, xb, by, bw, pieH)
    self:zona(xb, by, bw, pieH, 'restablecer')
    Acero.boton({ texto = 'Aplicar', tipo = 'principal' }, xb + bw + px(14), by, bw, pieH)
    self:zona(xb + bw + px(14), by, bw, pieH, 'aplicar')
    -- Lista de resoluciones abierta, encima de todo.
    if listaAbierta then
        local opciones = {}
        for _, r in ipairs(resoluciones) do
            opciones[#opciones + 1] = { r.ancho .. ' × ' .. r.alto, r }
        end
        local alto1 = px(26)
        local maxFilas = math.max(1, math.floor((h - listaAbierta.y - px(10)) / alto1))
        local visibles = math.min(#opciones, maxFilas)
        local lx, ly, ancho = listaAbierta.x, listaAbierta.y, listaAbierta.w
        self.zonas[#self.zonas + 1] = { x = 0, y = 0, w = w, h = h, accion = 'cerrarLista' }
        Acero.nueve('panel_contenido', 'normal', lx, ly, ancho, visibles * alto1 + px(6))
        local fuente = fuenteK('cuerpo', 11)
        for n = 1, visibles do
            local o = opciones[n]
            local yy = ly + px(3) + (n - 1) * alto1
            local encima = Tema.dentro(mx, my, lx + px(3), yy, ancho - px(6), alto1)
            local actual = rw == o[2].ancho and rh == o[2].alto
            Acero.fila(
                lx + px(3),
                yy,
                ancho - px(6),
                alto1,
                actual and 'seleccionada' or (encima and 'hover' or 'normal'),
                true
            )
            g.setFont(fuente)
            Tema.color(actual and 'textoHud' or 'tinta')
            g.print(o[1], lx + px(12), yy + (alto1 - fuente:getHeight()) / 2)
            self:zona(lx + px(3), yy, ancho - px(6), alto1, 'elegir', o[2])
        end
    end
end

--- Lista de filas «izquierda … derecha» sobre un panel claro.
function Opciones:dibujarLista(dw, arriba, filas, titulo, ancho)
    local px = Tema.px
    local g = love.graphics
    local fh = 44
    local pw = math.min(ancho or 900, dw - 200)
    local x0 = (dw - pw) / 2
    local cx, cy, cw = Acero.panelClaro(px(x0), px(arriba), px(pw), px(#filas * fh + 24 + (titulo and 40 or 0)))
    local yy = cy + px(4)
    local fuente = Acero.fuente('cuerpo', 22)
    if titulo then
        g.setFont(Acero.fuente('titulo', 24))
        Tema.color('tinta')
        g.print(titulo, cx + px(12), yy)
        yy = yy + px(40)
    end
    for k, f in ipairs(filas) do
        g.setFont(fuente)
        Tema.color('tintaTenue')
        g.print(f[1], cx + px(16), yy + (px(fh) - fuente:getHeight()) / 2)
        Tema.color('tinta')
        local valor = Tema.cortar(fuente, f[2], cw * 0.62)
        g.print(valor, cx + cw - px(16) - fuente:getWidth(valor), yy + (px(fh) - fuente:getHeight()) / 2)
        if k < #filas then
            Tema.color('papelLinea')
            g.rectangle('fill', cx + px(8), yy + px(fh) - 1, cw - px(16), 1)
        end
        yy = yy + px(fh)
    end
end

--- Dibuja las opciones. `ctx` = { sim, nacion }.
function Opciones:dibujar(ctx)
    if not self.abierta then
        return
    end
    local g = love.graphics
    local px = Tema.px
    local e = Tema.escala()
    local w, h = g.getDimensions()
    local dw, dh = w / e, h / e
    self.zonas = {}
    self.ayuda = nil
    Clara.fondo()
    local sim = ctx.sim
    local recursos = ctx.nacion and Clara.recursosDe(sim, ctx.nacion) or {}
    local logo = Clara.cabecera(Tema.mayusculas(TITULOS[self.pantalla]), recursos)
    self:zona(logo.x, logo.y, logo.w, logo.h, 'atras')
    local arriba = 100
    self.maxDesplazo = 0
    if self.pantalla == 'menu' then
        self:dibujarMenu(dw, dh, arriba)
    elseif self.pantalla == 'general' then
        self:dibujarGeneral(dw, dh, arriba)
    elseif self.pantalla == 'ayuda' then
        self:dibujarLista(dw, arriba, TECLAS)
    elseif self.pantalla == 'version' then
        self:dibujarLista(dw, arriba, {
            { 'Juego', 'Nations RTS' },
            { 'Formato de la partida', tostring(Simulacion.version) },
            { 'Semilla del mundo', tostring(ctx.semilla) },
            { 'Día de la partida', Tema.numero(sim.estado.dia) },
        }, nil, 700)
    elseif self.pantalla == 'creditos' then
        local mayor, menor = love.getVersion()
        self:dibujarLista(dw, arriba, {
            { 'Juego', 'Nations RTS' },
            { 'Motor', 'LÖVE ' .. mayor .. '.' .. menor },
            { 'Tipografías', 'Barlow (SIL OFL 1.1)' },
        }, nil, 760)
    elseif self.pantalla == 'nueva' then
        local cx = (dw - 640) / 2
        g.setFont(Acero.fuente('cuerpo', 24))
        Tema.color('tinta')
        g.printf(
            'Empieza un mundo nuevo con otra semilla. La partida de ahora se pierde si no la has guardado (F5).',
            px(cx),
            px(arriba),
            px(640),
            'left'
        )
        local bw, bh = px(300), px(64)
        local by = px(arriba + 130)
        Acero.boton({ texto = 'Cancelar', tipo = 'secundario' }, px(cx), by, bw, bh)
        self:zona(px(cx), by, bw, bh, 'atras')
        Acero.boton({ texto = 'Empezar mundo nuevo', tipo = 'peligro' }, px(cx) + bw + px(24), by, px(316), bh)
        self:zona(px(cx) + bw + px(24), by, px(316), bh, 'nueva')
    elseif self.pantalla == 'idioma' then
        local cx = (dw - 480) / 2
        Clara.filaOpcion(px(cx), px(arriba), px(480), px(76), 'Español', 'mundo')
        g.setFont(Acero.fuente('cuerpo', 20))
        Tema.color('tintaTenue')
        g.print('Por ahora es el único idioma del juego.', px(cx), px(arriba + 92))
    elseif self.pantalla == 'guardado' then
        local cx = (dw - 480) / 2
        Clara.filaOpcion(px(cx), px(arriba), px(480), px(76), 'Guardar la partida (F5)', 'guardar')
        self:zona(px(cx), px(arriba), px(480), px(76), 'guardar')
        Clara.filaOpcion(px(cx), px(arriba + 104), px(480), px(76), 'Cargar la partida (F9)', 'nivel')
        self:zona(px(cx), px(arriba + 104), px(480), px(76), 'cargar')
        if self.aviso then
            g.setFont(Acero.fuente('cuerpo', 20))
            Tema.color('tintaTenue')
            g.print(self.aviso, px(cx), px(arriba + 204))
        end
    end
end

function Opciones:dibujarAyuda()
    if self.abierta and self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- Fija el valor de un deslizador según la posición x del ratón.
function Opciones:mover(x)
    local s = self.arrastrando and self.deslizadores and self.deslizadores[self.arrastrando]
    if s then
        self.borrador[self.arrastrando] = math.max(0, math.min(1, (x - s.x) / s.w))
    end
end

--- Clic. Devuelve la acción para main.lua (`cerrar`, `perfil`, `guardar`,
-- `cargar`) o 'nada'.
function Opciones:pulsar(x, y)
    for k = #self.zonas, 1, -1 do
        local z = self.zonas[k]
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local a = z.accion
            if a == 'atras' then
                return self:atras() and 'nada' or 'cerrar'
            elseif a == 'ir' then
                if z.dato == 'perfil' then
                    return 'perfil'
                end
                self.pantalla = z.dato
                self.desplazo = 0
                self.aviso = nil
                return 'nada'
            elseif a == 'elegirCalidad' then
                Ajustes.alNivel(self.borrador, z.dato)
                return 'nada'
            elseif a == 'desplegar' then
                self.desplegado = self.desplegado ~= z.dato and z.dato or nil
                return 'nada'
            elseif a == 'cerrarLista' then
                self.desplegado = nil
                return 'nada'
            elseif a == 'elegir' then
                if self.desplegado == 'calidad' then
                    Ajustes.alNivel(self.borrador, z.dato)
                else
                    -- A pantalla completa solo vale la resolución del monitor:
                    -- elegir otra pasa a ventana de ese tamaño (ajustes.lua).
                    local anchoMonitor, altoMonitor = love.window.getDesktopDimensions()
                    if z.dato.ancho == anchoMonitor and z.dato.alto == altoMonitor then
                        self.borrador.ancho, self.borrador.alto = nil, nil
                    else
                        self.borrador.ancho, self.borrador.alto = z.dato.ancho, z.dato.alto
                        self.borrador.pantallaCompleta = false
                    end
                end
                self.desplegado = nil
                return 'nada'
            elseif a == 'conmutar' then
                self.borrador[z.dato] = not self.borrador[z.dato]
                if z.dato == 'pantallaCompleta' and self.borrador.pantallaCompleta then
                    self.borrador.ancho, self.borrador.alto = nil, nil
                end
                return 'nada'
            elseif a == 'deslizar' then
                self.arrastrando = z.dato
                self:mover(x)
                return 'nada'
            elseif a == 'restablecer' then
                self.borrador = Ajustes.copiar(Ajustes.fabrica)
                self.aviso = nil
                return 'nada'
            elseif a == 'aplicar' then
                self.aviso = Ajustes.aplicar(self.borrador, true)
                if not self.aviso then
                    Ajustes.valores = Ajustes.copiar(self.borrador)
                    Ajustes.guardar(Ajustes.valores)
                end
                return 'nada'
            elseif a == 'nueva' then
                return 'nueva'
            elseif a == 'guardar' or a == 'cargar' then
                self.aviso = a == 'guardar' and 'Partida guardada.' or 'Partida cargada.'
                return a
            end
        end
    end
    return 'nada'
end

function Opciones:soltar()
    self.arrastrando = nil
end

return Opciones

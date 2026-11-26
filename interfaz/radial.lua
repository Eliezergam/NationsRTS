-- Menú radial del mapa, al estilo Warpath (diseno/referencias-warpath/
-- radial_ciudad_propia.jpg y mapa_hud.jpg): al tocar un sitio sin un
-- ejército elegido sale, alrededor del objetivo, un círculo punteado; bajo
-- el objetivo, su nombre en una placa y su nivel en un hexágono pequeño; por
-- debajo, hexágonos de metal en arco con su etiqueta; y a la izquierda una
-- tarjeta de datos (título, coordenadas con su marca verde, favorito y filas
-- grises alternas) unida al objetivo por una línea fina con un rombo.
--
-- Qué botones y qué datos lleva lo decide main.lua (`opciones`); este módulo
-- solo los coloca, los dibuja y dice cuál se pulsó. No cambia la simulación.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local Radial = {}
Radial.__index = Radial

-- Medidas de diseño (a 1080p; `Tema.px` las escala).
local RADIO = 250 -- radio del círculo punteado
local RADIO_BOTONES = 185 -- radio del arco de los hexágonos
local PASO = math.rad(30) -- ángulo entre dos hexágonos vecinos
local ARCO_MAXIMO = math.rad(100) -- como mucho, a cada lado del botón de abajo
local HEXAGONO = 80 -- ancho de cada hexágono
local ANCHO_FICHA = 420 -- tarjeta de datos
local ALTO_FILA = 34
local BARRA_ABAJO = 136 -- alto de la barra de botones de abajo, con sus etiquetas

function Radial.nuevo()
    local self = setmetatable({}, Radial)
    self.objetivo = nil
    self.zonas = {}
    self.rect = nil
    self.ayuda = nil
    return self
end

--- Abre el menú sobre `objetivo` = { tipo = 'sitio' | 'mina', id }.
function Radial:abrir(objetivo)
    self.objetivo = objetivo
    self.zonas = {}
end

function Radial:cerrar()
    self.objetivo = nil
    self.zonas = {}
    self.rect = nil
    self.ayuda = nil
end

function Radial:abierto()
    return self.objetivo ~= nil
end

--- Ángulos (radianes; 0 a la derecha y π/2 abajo en pantalla) de `n`
-- botones en arco de izquierda a derecha, a `PASO` uno de otro, con el
-- botón `centro` justo debajo del objetivo. Con muchos botones el paso se
-- estrecha para que el arco no pase de `ARCO_MAXIMO` a cada lado.
local function angulos(n, centro)
    centro = centro or (n + 1) / 2
    local lado = math.max(centro - 1, n - centro)
    local paso = lado > 0 and math.min(PASO, ARCO_MAXIMO / lado) or PASO
    local out = {}
    for k = 1, n do
        out[k] = math.pi / 2 + (centro - k) * paso
    end
    return out
end

--- Etiqueta de un hexágono en una o dos líneas (se parte por el espacio más
-- cercano al medio si no cabe en `ancho`): la lista de líneas.
local function lineasEtiqueta(fuente, texto, ancho)
    if not texto or fuente:getWidth(texto) <= ancho then
        return { texto }
    end
    local mejor, mejorDiferencia
    local inicio = 1
    while true do
        local a = texto:find(' ', inicio, true)
        if not a then
            break
        end
        local diferencia = math.abs(fuente:getWidth(texto:sub(1, a - 1)) - fuente:getWidth(texto:sub(a + 1)))
        if not mejor or diferencia < mejorDiferencia then
            mejor, mejorDiferencia = a, diferencia
        end
        inicio = a + 1
    end
    if not mejor then
        return { Tema.cortar(fuente, texto, ancho) }
    end
    return { texto:sub(1, mejor - 1), texto:sub(mejor + 1) }
end

--- Círculo punteado del original: un disco claro translúcido, uno oscuro
-- más pequeño alrededor del objetivo y el borde en trazos.
local function circulo(g, sx, sy, radio)
    g.setColor(1, 1, 1, 0.1)
    g.circle('fill', sx, sy, radio)
    g.setColor(0, 0, 0, 0.16)
    g.circle('fill', sx, sy, radio * 0.56)
    g.setLineWidth(math.max(1, Tema.px(2.5)))
    g.setColor(0.86, 0.88, 0.86, 0.7)
    local pasos = 96
    for k = 0, pasos - 1, 2 do
        local a0 = k / pasos * math.pi * 2
        local a1 = (k + 1.2) / pasos * math.pi * 2
        g.line(
            sx + math.cos(a0) * radio,
            sy + math.sin(a0) * radio,
            sx + math.cos(a1) * radio,
            sy + math.sin(a1) * radio
        )
    end
    g.setLineWidth(1)
end

--- Hexágono pequeño (vértice arriba) centrado en (cx, cy), de radio `r`.
local function hexagonoPequeno(g, cx, cy, r)
    local puntos = {}
    for k = 0, 5 do
        local a = math.rad(-90 + k * 60)
        puntos[#puntos + 1] = cx + math.cos(a) * r
        puntos[#puntos + 1] = cy + math.sin(a) * r
    end
    Tema.color('olivaNegro', 0.92)
    g.polygon('fill', puntos)
    Tema.color('lineaOliva')
    g.setLineWidth(math.max(1, Tema.px(1.5)))
    g.polygon('line', puntos)
    g.setLineWidth(1)
end

--- Nombre del sitio en su placa (texto verde si es tuyo) y el nivel debajo
-- en un hexágono pequeño.
local function placaNombre(g, sx, ny, opciones)
    local fuente = Acero.fuente('titulo', 28)
    local nombre = opciones.nombre or ''
    local ancho = fuente:getWidth(nombre) + Tema.px(44)
    local alto = fuente:getHeight() + Tema.px(4)
    local x = sx - ancho / 2
    local inclina = Tema.px(12)
    -- Placa con los lados inclinados, oscura y translúcida.
    g.setColor(0.04, 0.06, 0.04, 0.72)
    g.polygon('fill', x + inclina, ny, x + ancho, ny, x + ancho - inclina, ny + alto, x, ny + alto)
    Tema.color('lineaOliva', 0.8)
    g.polygon('line', x + inclina, ny, x + ancho, ny, x + ancho - inclina, ny + alto, x, ny + alto)
    Acero.textoContorno(
        fuente,
        nombre,
        math.floor(sx - fuente:getWidth(nombre) / 2),
        ny + Tema.px(2),
        opciones.colorNombre or 'textoHud',
        'olivaNegro'
    )
    if opciones.nivel then
        local fuenteNivel = Acero.fuente('cifra', 20)
        local texto = tostring(opciones.nivel)
        local r = math.max(Tema.px(17), fuenteNivel:getWidth(texto) / 2 + Tema.px(8))
        local cy = ny + alto + r - Tema.px(2)
        hexagonoPequeno(g, sx, cy, r)
        g.setFont(fuenteNivel)
        Tema.color('textoHud')
        g.print(texto, math.floor(sx - fuenteNivel:getWidth(texto) / 2), math.floor(cy - fuenteNivel:getHeight() / 2))
    end
end

--- Marca de ubicación: cuadrado verde con un alfiler blanco.
local function marcaUbicacion(g, x, y, lado)
    g.setColor(0.3, 0.62, 0.24, 1)
    g.rectangle('fill', x, y, lado, lado, Tema.px(3), Tema.px(3))
    local cx, cy, r = x + lado / 2, y + lado * 0.4, lado * 0.2
    g.setColor(1, 1, 1, 1)
    g.circle('fill', cx, cy, r)
    g.polygon('fill', cx - r * 0.9, cy + r * 0.45, cx + r * 0.9, cy + r * 0.45, cx, y + lado * 0.82)
    g.setColor(0.3, 0.62, 0.24, 1)
    g.circle('fill', cx, cy, r * 0.42)
end

--- Botón cuadrado oscuro con una estrella (favorito), rellena si está marcada.
local function botonFavorito(g, x, y, lado, marcado, encima)
    local fondo = encima and { 0.3, 0.32, 0.28 } or { 0.16, 0.17, 0.15 }
    Acero.placa(x, y, lado, lado, Tema.px(4), fondo, { 0.45, 0.47, 0.42 }, 0.95)
    local cx, cy = x + lado / 2, y + lado / 2 + Tema.px(1)
    local puntos = {}
    for k = 0, 9 do
        local r = (k % 2 == 0) and lado * 0.32 or lado * 0.13
        local a = math.rad(-90 + k * 36)
        puntos[#puntos + 1] = cx + math.cos(a) * r
        puntos[#puntos + 1] = cy + math.sin(a) * r
    end
    if marcado then
        g.setColor(0.99, 0.86, 0.39, 1)
        for k = 0, 4 do
            -- La estrella es cóncava: se rellena en triángulos desde el centro.
            local i = k * 4
            local j = (i + 2) % 20
            local l = (i + 4) % 20
            g.polygon('fill', cx, cy, puntos[i + 1], puntos[i + 2], puntos[j + 1], puntos[j + 2])
            g.polygon('fill', cx, cy, puntos[j + 1], puntos[j + 2], puntos[l + 1], puntos[l + 2])
        end
    else
        g.setColor(0.93, 0.94, 0.92, 1)
        g.setLineWidth(math.max(1, Tema.px(1.5)))
        g.polygon('line', puntos)
        g.setLineWidth(1)
    end
end

--- Alto de la tarjeta de datos con sus filas.
local function altoFicha(opciones)
    local titulo = Acero.fuente('subtitulo', 20)
    local sub = Acero.fuente('etiqueta', 14)
    local cabecera = titulo:getHeight() + sub:getHeight() + Tema.px(14)
    return cabecera + #opciones.filas * (opciones.altoFila or Tema.px(ALTO_FILA)) + Tema.px(10) * 2
end

--- Tarjeta de datos (familia clara): cabecera con la marca verde, el
-- título, las coordenadas y el favorito; filas de etiqueta y valor (con
-- icono a color si lo llevan) con el fondo gris claro alterno.
function Radial:ficha(opciones, x, y, ancho)
    local g = love.graphics
    local titulo = Acero.fuente('subtitulo', 20)
    local sub = Acero.fuente('etiqueta', 14)
    local texto = Acero.fuente('cuerpo', 17)
    local negrita = Acero.fuente('cifra', 18)
    local fila = opciones.altoFila or Tema.px(ALTO_FILA)
    local relleno = Tema.px(10)
    local cabecera = titulo:getHeight() + sub:getHeight() + Tema.px(14)
    local alto = altoFicha(opciones)
    Acero.sombra(x, y, ancho, alto)
    Acero.fondoPanel(x, y, ancho, alto)
    local marca = cabecera - Tema.px(14)
    marcaUbicacion(g, x + relleno, y + relleno + Tema.px(2), marca)
    -- Favorito arriba a la derecha.
    local lado = Tema.px(34)
    local fx, fy = x + ancho - relleno - lado, y + relleno
    local mx, my = love.mouse.getPosition()
    local encima = opciones.favorito ~= nil and Tema.dentro(mx, my, fx, fy, lado, lado)
    if opciones.favorito ~= nil then
        botonFavorito(g, fx, fy, lado, opciones.favorito, encima)
        self.zonas[#self.zonas + 1] = { x = fx, y = fy, w = lado, h = lado, clave = 'favorito' }
        if encima then
            self.ayuda = opciones.favorito and 'Quitar de favoritos' or 'Marcar como favorito'
        end
    end
    local tx = x + relleno + marca + Tema.px(10)
    local tw = fx - Tema.px(8) - tx
    g.setFont(titulo)
    Tema.color('textoHud')
    g.print(Tema.cortar(titulo, opciones.titulo or '', tw), tx, y + relleno)
    g.setFont(sub)
    Tema.color('textoHudTenue')
    g.print(Tema.cortar(sub, opciones.coordenadas or '', tw), tx, y + relleno + titulo:getHeight())
    local filaY = y + relleno + cabecera
    local filaX, filaW = x + relleno, ancho - relleno * 2
    for k, f in ipairs(opciones.filas) do
        if k % 2 == 1 then
            Tema.color('caquiFila', 0.9)
            g.rectangle('fill', filaX, filaY + Tema.px(2), filaW, fila - Tema.px(4), Tema.px(2), Tema.px(2))
        end
        local valor = f[2] or ''
        local icono = f.icono and math.floor(negrita:getHeight() * 0.95) or 0
        local anchoIcono = icono > 0 and icono + Tema.px(6) or 0
        g.setFont(negrita)
        valor = Tema.cortar(negrita, valor, filaW - Tema.px(150) - anchoIcono)
        local vx = filaX + filaW - Tema.px(10) - negrita:getWidth(valor)
        local vy = filaY + math.floor((fila - negrita:getHeight()) / 2)
        Tema.color(f.color or 'textoHud')
        g.print(valor, vx, vy)
        if icono > 0 then
            Acero.iconoColor(f.icono, vx - anchoIcono, filaY + math.floor((fila - icono) / 2), icono)
        end
        g.setFont(texto)
        Tema.color('textoHudTenue')
        local libre = vx - anchoIcono - filaX - Tema.px(20)
        g.print(
            Tema.cortar(texto, f[1], libre),
            filaX + Tema.px(10),
            filaY + math.floor((fila - texto:getHeight()) / 2)
        )
        filaY = filaY + fila
    end
    return { x = x, y = y, w = ancho, h = alto }
end

--- Dibuja el menú con el objetivo en (sx, sy) de la pantalla. `opciones` =
-- { nombre, nivel, colorNombre, titulo, coordenadas, favorito (nil: sin
-- botón), filas = { { etiqueta, valor, color, icono } }, botones = { {
-- clave, icono, etiqueta, activo, ayuda, destacado } }, centro (el botón que va justo
-- debajo) }.
function Radial:dibujar(sx, sy, opciones)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    self.ayuda = nil
    self.rect = nil
    if not opciones then
        return
    end
    local radio = Tema.px(RADIO)
    circulo(g, sx, sy, radio)

    -- Hexágonos en arco por debajo.
    local ancho = Tema.px(HEXAGONO)
    local alto = math.floor(ancho * 80 / 72 + 0.5)
    local botones = opciones.botones or {}
    local mx, my = love.mouse.getPosition()
    -- Con seis o siete botones el arco se abre un poco: las etiquetas de los
    -- lados no pisan el hexágono de al lado. Con ocho, el arco no crece (para
    -- no bajar hasta la barra de abajo) sino que sube por los lados: los de
    -- los extremos quedan a la altura del objetivo (ARCO_MAXIMO).
    local arco = Tema.px(RADIO_BOTONES + math.max(0, math.min(2, #botones - 5)) * 12)
    local fuenteEtiqueta = Acero.fuente('boton', 17)
    local listaAngulos = angulos(#botones, opciones.centro)
    -- Si las etiquetas de abajo llegan a la barra de botones (pantallas
    -- bajas), el arco entero sube lo que falta, hasta 40 px de diseño (queda
    -- por debajo de la placa del nombre).
    local limite = h - Tema.px(BARRA_ABAJO)
    local subir = 0
    for k, a in ipairs(listaAngulos) do
        local lineas = #lineasEtiqueta(fuenteEtiqueta, botones[k].etiqueta, math.floor(ancho * 1.1))
        local debajo = alto / 2 - Tema.px(2) + lineas * (fuenteEtiqueta:getHeight() - Tema.px(4))
        subir = math.max(subir, sy + math.sin(a) * arco + debajo - limite)
    end
    subir = math.min(Tema.px(40), subir)
    for k, a in ipairs(listaAngulos) do
        local b = botones[k]
        local x = math.floor(sx + math.cos(a) * arco - ancho / 2)
        local y = math.floor(sy + math.sin(a) * arco - subir - alto / 2)
        Acero.hexagono(x, y, ancho, {
            icono = b.icono,
            desactivado = b.activo == false,
            -- La acción principal va resaltada (crema con aro dorado), como «Base» en el original.
            activo = b.destacado == true,
        })
        local total = alto
        -- La etiqueta, en dos líneas si no cabe («Producir / munición»).
        local fuente = fuenteEtiqueta
        local ty = y + alto - Tema.px(2)
        for _, linea in ipairs(lineasEtiqueta(fuente, b.etiqueta, math.floor(ancho * 1.1))) do
            local tx = math.floor(x + (ancho - fuente:getWidth(linea)) / 2)
            Acero.textoContorno(fuente, linea, tx, ty, b.destacado and 'amarillo' or 'textoHud')
            ty = ty + fuente:getHeight() - Tema.px(4)
            total = ty - y
        end
        if Tema.dentro(mx, my, x, y, ancho, total) then
            self.ayuda = b.ayuda
        end
        self.zonas[#self.zonas + 1] = { x = x, y = y, w = ancho, h = total, clave = b.clave, activo = b.activo }
    end

    -- Nombre y nivel bajo el objetivo, dentro del círculo (encima del arco).
    placaNombre(g, sx, sy + math.floor(radio * 0.2), opciones)

    -- Tarjeta a la izquierda del círculo (a la derecha si no cabe), unida al
    -- objetivo por una línea fina en ángulo recto con un rombo en la tarjeta.
    if opciones.filas and #opciones.filas > 0 then
        -- Con el arco ancho, la tarjeta se estrecha para caber a la izquierda.
        local anchoFicha = Tema.px(#botones > 5 and ANCHO_FICHA - 40 or ANCHO_FICHA)
        local altoF = altoFicha(opciones)
        -- Con muchos botones el arco sube por los lados: la tarjeta se aparta
        -- hasta el borde del círculo para no taparlos.
        local aparte = #botones > 5 and radio + Tema.px(6) or radio * 0.72
        local fx = sx - aparte - anchoFicha
        local izquierda = true
        if fx < Tema.px(104) then
            fx = sx + aparte
            izquierda = false
        end
        fx = math.max(Tema.px(8), math.min(w - anchoFicha - Tema.px(8), fx))
        -- La barra de botones de abajo (`barraAbajo`, su rectángulo): si la
        -- tarjeta la pisa en horizontal, a la derecha se estrecha hasta
        -- quedar al lado (si le quedan 320 px de diseño) y, si no, termina
        -- encima de ella. Si no la pisa, puede bajar hasta el borde.
        local abajo = h - Tema.px(8)
        local barra = opciones.barraAbajo
        if barra then
            local pisa = fx < barra.x + barra.w and fx + anchoFicha > barra.x
            local libre = w - Tema.px(8) - (barra.x + barra.w + Tema.px(8))
            if pisa and not izquierda and libre >= Tema.px(320) then
                anchoFicha = math.min(anchoFicha, libre)
                fx = w - Tema.px(8) - anchoFicha
            elseif pisa then
                abajo = barra.y - Tema.px(8)
            end
        else
            abajo = h - Tema.px(124)
        end
        -- A la derecha, por debajo de los avisos (`libreDesde`); si así no
        -- cabe, las filas se aprietan (hasta 26 px de diseño) y, si aun así
        -- no cabe, la tarjeta sube tapando los avisos mientras el menú está
        -- abierto (antes se metía bajo la barra de abajo).
        local arriba = Tema.px(90)
        if not izquierda and opciones.libreDesde then
            arriba = math.max(arriba, opciones.libreDesde)
        end
        local function apretar()
            if altoF > abajo - arriba then
                local sobra = altoF - (abajo - arriba)
                local fila = math.max(Tema.px(26), Tema.px(ALTO_FILA) - math.ceil(sobra / #opciones.filas))
                opciones.altoFila = fila
                altoF = altoFicha(opciones)
            end
        end
        apretar()
        if altoF > abajo - arriba then
            arriba = Tema.px(90)
            opciones.altoFila = nil
            altoF = altoFicha(opciones)
            apretar()
        end
        local fy = sy - radio * 0.1 - altoF / 2
        fy = math.max(arriba, math.min(abajo - altoF, fy))
        local py = math.floor(fy + altoF / 2)
        local px = izquierda and (fx + anchoFicha) or fx
        -- La línea va antes que la tarjeta: sale del rombo, sigue en
        -- horizontal hasta encima del objetivo y baja hasta él.
        g.setLineWidth(math.max(1, Tema.px(1.5)))
        g.setColor(0.93, 0.94, 0.92, 0.95)
        local codoY = math.min(py, sy - Tema.px(10))
        g.line(px, py, sx, py, sx, codoY)
        g.setLineWidth(1)
        Tema.modoClaro = true
        local ok, r = pcall(self.ficha, self, opciones, fx, fy, anchoFicha)
        Tema.modoClaro = false
        if not ok then
            error(r, 0)
        end
        self.rect = r
        local rombo = Tema.px(6)
        g.setColor(0.93, 0.94, 0.92, 1)
        g.polygon('fill', px, py - rombo, px + rombo, py, px, py + rombo, px - rombo, py)
        Tema.color('olivaNegro')
        g.polygon('line', px, py - rombo, px + rombo, py, px, py + rombo, px - rombo, py)
    end
end

function Radial:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- Clic: la clave del botón pulsado, 'nada' si cayó en la tarjeta o en un
-- botón apagado, o nil si cayó fuera (el menú se cierra y el clic sigue).
function Radial:pulsar(x, y)
    if not self.objetivo then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if z.activo == false then
                return 'nada'
            end
            return z.clave
        end
    end
    local r = self.rect
    if r and Tema.dentro(x, y, r.x, r.y, r.w, r.h) then
        return 'nada'
    end
    return nil
end

return Radial

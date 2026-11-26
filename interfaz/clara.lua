-- Familia clara (hormigón) de la interfaz militar (diseno/interfaz-militar.md,
-- §3.3b): fondo de hormigón, cabecera con la placa negra del logo, placas de
-- datos, botones anchos con icono y los controles de formulario (desplegable,
-- interruptor, deslizador). Texto NEGRO sobre gris claro. Es lo que usan el
-- perfil y las opciones.
--
-- Solo dibuja y devuelve si el ratón está encima: no cambia el estado del juego.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Indice = require('assets.ui.indice')
local Vida = require('interfaz.vida')

local Clara = {}

local fondoHormigon, malla, vineta, relieve

--- Texto con sombra negra de 2 px abajo y a la derecha (títulos sobre hormigón).
function Clara.textoSombra(fuente, texto, x, y, color)
    local g = love.graphics
    g.setFont(fuente)
    local d = math.max(1, Tema.px(2))
    g.setColor(0, 0, 0, 0.7)
    g.print(texto, x + d, y + d)
    Tema.color(color or 'tituloClaro')
    g.print(texto, x, y)
end

--- Fondo de pantalla completa: la textura de hormigón en mosaico, aclarada
-- para acercarla al `hormigon` del diseño.
function Clara.fondo()
    local g = love.graphics
    local w, h = g.getDimensions()
    if not fondoHormigon then
        fondoHormigon = love.graphics.newImage(Indice.carpeta .. Indice.piezas.fondo_hormigon.archivos.normal)
        fondoHormigon:setWrap('repeat', 'repeat')
        fondoHormigon:setFilter('linear', 'linear')
    end
    local lado = Tema.px(256)
    if not malla or malla.w ~= w or malla.h ~= h or malla.lado ~= lado then
        local quad = love.graphics.newQuad(0, 0, w / lado * 256, h / lado * 256, 256, 256)
        malla = { quad = quad, w = w, h = h, lado = lado }
    end
    g.setColor(1, 1, 1, 1)
    g.draw(fondoHormigon, malla.quad, 0, 0, 0, lado / 256, lado / 256)
    -- Aclarado hacia el `hormigon` del diseño.
    Tema.color('hormigon', 0.5)
    g.rectangle('fill', 0, 0, w, h)
    -- Líneas de plano de mapa, muy tenues, y viñeta en los bordes.
    g.setColor(0.25, 0.25, 0.3, 0.09)
    local paso = Tema.px(150)
    for x = paso, w, paso do
        g.rectangle('fill', x, 0, 1, h)
    end
    for y = paso, h, paso do
        g.rectangle('fill', 0, y, w, 1)
    end
    -- Mapa tenue: curvas de nivel de un ruido suave, a baja resolución.
    if not relieve then
        local datos = love.image.newImageData(480, 270)
        datos:mapPixel(function(px, py)
            local v = love.math.noise(px * 0.009 + 7.3, py * 0.014 + 2.1) * 0.8
                + love.math.noise(px * 0.03 + 40, py * 0.04 + 9) * 0.2
            local linea = math.abs((v * 7) % 1 - 0.5)
            local a = linea > 0.475 and 0.2 or 0
            return 0.25, 0.25, 0.3, a
        end)
        relieve = love.graphics.newImage(datos)
        relieve:setFilter('linear', 'linear')
    end
    g.setColor(1, 1, 1, 1)
    g.draw(relieve, 0, 0, 0, w / 480, h / 270)
    if not vineta then
        local datos = love.image.newImageData(64, 64)
        datos:mapPixel(function(px, py)
            local dx, dy = (px + 0.5) / 32 - 1, (py + 0.5) / 32 - 1
            local d = math.min(1, math.sqrt(dx * dx + dy * dy) / 1.25)
            return 0.1, 0.1, 0.14, math.max(0, d - 0.35) * 0.75
        end)
        vineta = love.graphics.newImage(datos)
        vineta:setFilter('linear', 'linear')
    end
    g.setColor(1, 1, 1, 1)
    g.draw(vineta, 0, 0, 0, w / 64, h / 64)
end

--- Ancho de la pastilla de recurso sencilla para una cifra.
function Clara.anchoPastilla(alto, cifra)
    local fuente = Acero.fuente('cifra', 34)
    local lado = math.floor(alto * 0.9)
    return math.max(Tema.px(150), Tema.px(18) + lado + Tema.px(6) + fuente:getWidth(cifra) + Tema.px(28))
end

--- Pastilla de recurso sencilla (cabecera de las pantallas): icono de color y
-- cifra blanca con contorno. Devuelve el ancho que ocupa.
function Clara.pastilla(x, y, alto, tipo, cifra)
    local fuente = Acero.fuente('cifra', 34)
    local lado = math.floor(alto * 0.9)
    local ancho = Clara.anchoPastilla(alto, cifra)
    Acero.nueve('pastilla_recurso', 'normal', x, y, ancho, alto)
    Tema.iconoRecurso(tipo, x + Tema.px(16), y + (alto - lado) / 2 - Tema.px(2), lado)
    Acero.textoContorno(
        fuente,
        cifra,
        x + Tema.px(16) + lado + Tema.px(6),
        y + (alto - fuente:getHeight()) / 2 - Tema.px(1),
        tipo == 'dinero' and 'amarilloDinero' or 'textoHud'
    )
    return ancho
end

--- Cabecera de pantalla: placa negra del logo a la izquierda (un clic vuelve),
-- el título con sombra y, a la derecha, los recursos. `recursos` = lista de
-- { tipo, cifra }. Devuelve la zona del logo { x, y, w, h } y el alto de la
-- cabecera.
function Clara.cabecera(titulo, recursos)
    local g = love.graphics
    local w = g.getWidth()
    local px = Tema.px
    local lx, ly, lw, lh = px(96), px(8), px(140), px(62)
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, lx, ly, lw, lh)
    -- La placa del kit es la del HUD (64×44, marca dorada): se estira tal cual.
    Acero.pieza('cabecera_logo', 'normal', lx, ly, lw, lh)
    if encima then
        g.setColor(1, 1, 1, 0.12)
        g.rectangle('fill', lx, ly, lw, lh)
    end
    local fuente = Acero.fuente('titulo', 42)
    Clara.textoSombra(fuente, titulo, lx + lw + px(16), ly + (lh - fuente:getHeight()) / 2)
    local x = w - px(28)
    local alto = px(58)
    for k = #recursos, 1, -1 do
        local r = recursos[k]
        -- Las cifras cuentan hacia su valor en vez de saltar (interfaz/vida.lua).
        local cifra = r.valor and Tema.numero(Vida.numero('cabecera:' .. r.tipo, r.valor)) or r.cifra
        x = x - Clara.anchoPastilla(alto, cifra)
        Clara.pastilla(x, px(12), alto, r.tipo, cifra)
        x = x - px(4)
    end
    return { x = lx, y = ly, w = lw, h = lh }, px(80)
end

--- Placa de dato: el valor grande negro arriba, la etiqueta gris debajo y, a
-- la derecha y muy tenue, un icono opcional. Devuelve si el ratón está encima.
function Clara.placaDato(x, y, w, h, valor, etiqueta, icono)
    local g = love.graphics
    Acero.nueve('placa_dato', 'normal', x, y, w, h)
    local cx, cy, cw, ch = Acero.contenido('placa_dato', x, y, w, h)
    if icono then
        local lado = math.floor(h * 0.5)
        Acero.icono(icono, x + w - lado - Tema.px(16), y + (h - lado) / 2, lado, 'papelLinea', 0.55)
    end
    local grande = Acero.fuente('cifraGrande', 46)
    local pequena = Acero.fuente('cuerpo', 23)
    local total = grande:getHeight() + pequena:getHeight() - Tema.px(4)
    local ty = cy + math.floor((ch - total) / 2)
    g.setFont(grande)
    Tema.color('tinta')
    g.print(Tema.cortar(grande, valor, cw), cx, ty)
    g.setFont(pequena)
    Tema.color('tintaTenue')
    g.print(Tema.cortar(pequena, etiqueta, cw), cx, ty + grande:getHeight() - Tema.px(4))
    local mx, my = love.mouse.getPosition()
    return Tema.dentro(mx, my, x, y, w, h)
end

--- Botón ancho de menú (`fila_opcion`): icono negro a la izquierda y texto
-- negro. `opciones` = { nuevo, desactivado, estado }. Devuelve si el ratón
-- está encima.
function Clara.filaOpcion(x, y, w, h, texto, icono, opciones)
    opciones = opciones or {}
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local encima = not opciones.desactivado and Tema.dentro(mx, my, x, y, w, h)
    local estado = 'normal'
    if opciones.desactivado then
        estado = 'desactivado'
    elseif encima and love.mouse.isDown(1) then
        estado = 'pulsado'
    elseif encima then
        estado = 'resaltado'
    end
    -- Vida: el fondo crece un poco con el ratón encima y se hunde al pulsar.
    local fx, fy, fw, fh = x, y, w, h
    if not opciones.desactivado then
        local crece, hunde = Vida.boton(Vida.claveRect('f', x, y, w, h), encima, estado == 'pulsado')
        local m = Tema.escala() * (crece * 5 - hunde * 2)
        fx, fy, fw, fh = x - m, y - m + hunde * Tema.escala() * 2, w + m * 2, h + m * 2
    end
    Acero.nueve('fila_opcion', estado, fx, fy, fw, fh)
    local baja = estado == 'pulsado' and 1 or 0
    local lado = math.min(math.floor(h * 0.56), Tema.px(44))
    local ix = x + Tema.px(32) - lado / 2
    Acero.icono(icono, ix, y + (h - lado) / 2 + baja, lado, opciones.desactivado and 'papelLinea' or 'negro')
    local fuente = Acero.fuente('boton', 30)
    g.setFont(fuente)
    Tema.color(opciones.desactivado and 'tintaTenue' or 'tinta')
    local tx = x + Tema.px(60)
    g.print(Tema.cortar(fuente, texto, w - Tema.px(72)), tx, math.floor(y + (h - fuente:getHeight()) / 2) + baja)
    if opciones.nuevo then
        Acero.insigniaNuevo(x + w + Tema.px(2), y - Tema.px(10))
    end
    return encima
end

--- Desplegable cerrado (`desplegable`) con el valor elegido. Devuelve si el
-- ratón está encima.
function Clara.desplegable(x, y, w, h, texto, abierto)
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, w, h)
    local estado = (abierto and 'pulsado') or (encima and 'resaltado') or 'normal'
    Acero.nueve('desplegable', estado, x, y, w, h)
    local cx, cy, cw, ch = Acero.contenido('desplegable', x, y, w, h)
    local fuente = Acero.fuente('cuerpo', 19)
    love.graphics.setFont(fuente)
    Tema.color('tinta')
    love.graphics.print(Tema.cortar(fuente, texto, cw), cx, math.floor(cy + (ch - fuente:getHeight()) / 2))
    return encima
end

--- Interruptor (`interruptor`) de 44×22 escalado a `w`×`h`. Devuelve si el
-- ratón está encima.
function Clara.interruptor(x, y, w, h, encendido, desactivado)
    local mx, my = love.mouse.getPosition()
    local encima = not desactivado and Tema.dentro(mx, my, x, y, w, h)
    local estado = encendido and 'encendido' or 'apagado'
    if desactivado then
        estado = 'desactivado_' .. estado
    end
    Acero.pieza('interruptor', estado, x, y, w, h)
    return encima
end

--- Deslizador de 0 a 1 con el pomo. Devuelve si el ratón está encima.
function Clara.deslizador(x, y, w, valor, desactivado)
    local pomoLado = Tema.px(22)
    local alto = Tema.px(8)
    local cy = y
    local mx, my = love.mouse.getPosition()
    local encima = not desactivado and Tema.dentro(mx, my, x - pomoLado / 2, cy - pomoLado / 2, w + pomoLado, pomoLado)
    Acero.nueve('deslizador_carril', 'normal', x, cy - alto / 2, w, alto)
    local px = x + w * math.max(0, math.min(1, valor))
    if px - x > Tema.px(8) then
        Acero.nueve('deslizador_lleno', 'normal', x, cy - alto / 2, px - x, alto)
    end
    local estado = desactivado and 'desactivado'
        or (encima and (love.mouse.isDown(1) and 'pulsado' or 'resaltado'))
        or 'normal'
    Acero.pieza('deslizador_pomo', estado, px - pomoLado / 2, cy - pomoLado / 2, pomoLado, pomoLado)
    return encima
end

--- Hexágono plano (vértice arriba) centrado en (cx, cy), de radio `r`, con
-- relleno y borde de colores de la paleta (medallas vacías).
function Clara.hexagonoPlano(cx, cy, r, relleno, borde)
    local g = love.graphics
    local puntos = {}
    for k = 0, 5 do
        local a = -math.pi / 2 + k * math.pi / 3
        puntos[#puntos + 1] = cx + math.cos(a) * r
        puntos[#puntos + 1] = cy + math.sin(a) * r
    end
    Tema.color(relleno)
    g.polygon('fill', puntos)
    g.setLineWidth(math.max(1, Tema.px(2)))
    Tema.color(borde)
    g.polygon('line', puntos)
    g.setLineWidth(1)
end

--- Los cuatro recursos de una nación para la cabecera: { tipo, cifra } de
-- metal, petróleo, comida y dinero (solo lee la simulación).
function Clara.recursosDe(sim, nid)
    local almacen = sim:almacenDe(nid)
    local lista = {}
    if not almacen then
        return lista
    end
    local comida = 0
    for _, r in ipairs(sim:reservas(nid)) do
        if r.tipo == 'comida' then
            comida = r.cantidad or 0
        end
    end
    lista[1] = { tipo = 'metal', cifra = Tema.numero(almacen.metal), valor = almacen.metal }
    lista[2] = { tipo = 'petroleo', cifra = Tema.numero(almacen.petroleo), valor = almacen.petroleo }
    lista[3] = { tipo = 'comida', cifra = Tema.numero(comida), valor = comida }
    -- Un solo dinero: el tesoro que se puede gastar (bóveda y afuera).
    local dinero = almacen.dinero + almacen.afuera.dinero
    lista[4] = { tipo = 'dinero', cifra = Tema.numero(dinero), valor = dinero }
    return lista
end

return Clara

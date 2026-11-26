-- Acero: los componentes de la interfaz militar sobre el kit gráfico de
-- `assets/ui/` (diseno/interfaz-militar.md, §4): panel 9-slice, botón con
-- estados, barra, icono teñido, pestaña, fila de lista, insignia y ayuda.
--
-- Todo se dibuja con modo inmediato: cada componente mira el ratón en el
-- momento de dibujarse y devuelve si está encima. Las medidas que se le dan
-- son ya píxeles de pantalla (`Acero.px` pasa de diseño a pantalla con la
-- escala `e` de `Tema`); las piezas del kit están dibujadas a 1080p y se
-- escalan por `e`, así que a 720p (e = 0,8) todo baja en proporción.
--
-- No cambia el estado del juego: solo pinta y devuelve lo que ve.

local Tema = require('interfaz.tema')
local Paleta = require('interfaz.paleta')
local Indice = require('assets.ui.indice')
local Vida = require('interfaz.vida')

local Acero = {}

Acero.colores = Paleta.colores

-- Estilos de texto (§3.4): tipo de fuente, tamaño de diseño y mínimo real.
local ESTILOS = {
    titulo = { 'condensada', 26 },
    subtitulo = { 'condensada', 20 },
    cuerpo = { 'semi', 18 },
    cifra = { 'semiNegrita', 22 },
    cifraGrande = { 'condensada', 36 },
    boton = { 'condensada', 22 },
    etiqueta = { 'semi', 14, 10 },
    ayuda = { 'semi', 16 },
}

--- Fuente de un estilo del diseño (`titulo`, `cuerpo`, `cifra`…). `reduccion`
-- (opcional) los baja a ese tamaño de diseño.
function Acero.fuente(estilo, tamano)
    local e = ESTILOS[estilo]
    return Tema.fuenteExacta(e[1], tamano or e[2], e[3])
end

--- Una medida de diseño en píxeles de pantalla.
function Acero.px(valor)
    return Tema.px(valor)
end

--- Pone un color de la paleta (o uno dado como tabla) con su opacidad.
function Acero.color(nombre, alfa)
    Tema.color(nombre, alfa)
end

-- Imágenes del kit -------------------------------------------------------------------------

local imagenes = {} -- ruta -> imagen
local cachesNueve = {} -- pieza:estado -> { quads, ancho, alto }

local function imagen(ruta)
    local img = imagenes[ruta]
    if not img then
        img = love.graphics.newImage(Indice.carpeta .. ruta)
        img:setFilter('linear', 'linear')
        imagenes[ruta] = img
    end
    return img
end

--- Dibuja una pieza de tamaño fijo del kit estirada al rectángulo (x, y, w, h).
function Acero.pieza(nombre, estado, x, y, w, h, alfa)
    local pieza = Indice.piezas[nombre]
    local img = imagen(pieza.archivos[estado or 'normal'])
    love.graphics.setColor(1, 1, 1, alfa or 1)
    love.graphics.draw(img, x, y, 0, w / img:getWidth(), h / img:getHeight())
end

--- Cortes 9-slice de una pieza en un estado (se calculan una vez). Cada
-- trozo: { quad, columna (1 a 3), fila (1 a 3) }.
local function cortesDe(nombre, estado)
    local clave = nombre .. ':' .. estado
    local c = cachesNueve[clave]
    if c then
        return c
    end
    local pieza = Indice.piezas[nombre]
    local img = imagen(pieza.archivos[estado] or pieza.archivos.normal)
    local iw, ih = img:getDimensions()
    local n = pieza.nueve or { izq = 0, der = 0, arr = 0, aba = 0 }
    local xs = { 0, n.izq, iw - n.der, iw }
    local ys = { 0, n.arr, ih - n.aba, ih }
    c = { img = img, trozos = {}, izq = n.izq, der = n.der, arr = n.arr, aba = n.aba, iw = iw, ih = ih }
    for fila = 1, 3 do
        for columna = 1, 3 do
            local qw = xs[columna + 1] - xs[columna]
            local qh = ys[fila + 1] - ys[fila]
            if qw > 0 and qh > 0 then
                local quad = love.graphics.newQuad(xs[columna], ys[fila], qw, qh, iw, ih)
                c.trozos[#c.trozos + 1] = { quad = quad, columna = columna, fila = fila, qw = qw, qh = qh }
            end
        end
    end
    cachesNueve[clave] = c
    return c
end

--- Dibuja una pieza 9-slice del kit en el rectángulo (x, y, w, h) de pantalla.
-- Las esquinas van a la escala de la interfaz, sin estirar más; los lados y el
-- centro se estiran.
function Acero.nueve(nombre, estado, x, y, w, h, alfa)
    local c = cortesDe(nombre, estado or 'normal')
    local e = Tema.escala()
    local izq, der = math.floor(c.izq * e + 0.5), math.floor(c.der * e + 0.5)
    local arr, aba = math.floor(c.arr * e + 0.5), math.floor(c.aba * e + 0.5)
    -- Si el rectángulo es más pequeño que las esquinas, se encogen.
    if izq + der > w then
        izq = math.floor(w / 2)
        der = w - izq
    end
    if arr + aba > h then
        arr = math.floor(h / 2)
        aba = h - arr
    end
    local anchos = { izq, w - izq - der, der }
    local altos = { arr, h - arr - aba, aba }
    local origenX = { x, x + izq, x + w - der }
    local origenY = { y, y + arr, y + h - aba }
    local g = love.graphics
    g.setColor(1, 1, 1, alfa or 1)
    for _, t in ipairs(c.trozos) do
        -- Con margen 0 a un lado, la fila o columna del medio ocupa todo.
        local dw, dh = anchos[t.columna], altos[t.fila]
        if dw > 0 and dh > 0 then
            g.draw(c.img, t.quad, origenX[t.columna], origenY[t.fila], 0, dw / t.qw, dh / t.qh)
        end
    end
end

--- Levanta un rectángulo oscuro del kit hacia el caqui del HUD: una capa de
-- `lineaOliva` con `alfa` (0,5 en los paneles).
function Acero.levantar(x, y, w, h, alfa)
    local borde = Tema.px(3)
    Tema.color('lineaOliva', alfa or 0.4)
    love.graphics.rectangle('fill', x + borde, y + borde, w - borde * 2, h - borde * 2)
end

--- Relleno interior de una pieza (su `contenido`, ya en píxeles): { x, y, w, h }.
function Acero.contenido(nombre, x, y, w, h)
    local r = Indice.piezas[nombre].contenido or { izq = 0, der = 0, arr = 0, aba = 0 }
    local e = Tema.escala()
    local izq, der = math.floor(r.izq * e + 0.5), math.floor(r.der * e + 0.5)
    local arr, aba = math.floor(r.arr * e + 0.5), math.floor(r.aba * e + 0.5)
    return x + izq, y + arr, w - izq - der, h - arr - aba
end

-- Formas procedurales -----------------------------------------------------------------------

--- Puntos de un rectángulo con esquinas cortadas en diagonal. `cortes` =
-- { arribaIzq, arribaDer, abajoDer, abajoIzq } (0: esquina recta).
function Acero.puntosCortados(x, y, w, h, cortes)
    local a, b, c, d = cortes[1], cortes[2], cortes[3], cortes[4]
    local puntos = {}
    local function punto(px, py)
        puntos[#puntos + 1] = px
        puntos[#puntos + 1] = py
    end
    if a > 0 then
        punto(x, y + a)
        punto(x + a, y)
    else
        punto(x, y)
    end
    if b > 0 then
        punto(x + w - b, y)
        punto(x + w, y + b)
    else
        punto(x + w, y)
    end
    if c > 0 then
        punto(x + w, y + h - c)
        punto(x + w - c, y + h)
    else
        punto(x + w, y + h)
    end
    if d > 0 then
        punto(x + d, y + h)
        punto(x, y + h - d)
    else
        punto(x, y + h)
    end
    return puntos
end

--- Rectángulo con las cuatro esquinas cortadas, relleno y con borde de 1 px.
function Acero.placa(x, y, w, h, corte, relleno, borde, alfa)
    local g = love.graphics
    local puntos = Acero.puntosCortados(x, y, w, h, { corte, corte, corte, corte })
    if relleno then
        Tema.color(relleno, alfa)
        g.polygon('fill', puntos)
    end
    if borde then
        Tema.color(borde, alfa)
        g.setLineWidth(1)
        g.polygon('line', puntos)
    end
end

--- Sombra de panel (§3.5): tres rectángulos negros desplazados hacia abajo.
function Acero.sombra(x, y, w, h)
    local g = love.graphics
    local capas = { { 0.22, 0 }, { 0.14, 4 }, { 0.08, 8 } }
    local desplazo = Tema.px(4)
    for _, capa in ipairs(capas) do
        local crece = Tema.px(capa[2])
        g.setColor(0, 0, 0, capa[1])
        g.rectangle('fill', x - crece / 2, y + desplazo - crece / 2, w + crece, h + crece, Tema.px(6), Tema.px(6))
    end
end

-- Paneles ------------------------------------------------------------------------------------

--- Panel de acero con sombra. Con `titulo` lleva la cabecera de 48 (título a
-- la izquierda y, si `cerrar`, el botón de cierre). Devuelve el rectángulo
-- interior libre (x, y, w, h) y, si hay cierre, su zona { x, y, w, h }.
function Acero.panel(x, y, w, h, opciones)
    opciones = opciones or {}
    Acero.sombra(x, y, w, h)
    local pieza = opciones.titulo and 'panel_acero_cabecera' or 'panel_acero'
    if Tema.modoClaro then
        -- Gris caqui claro con marco fino; la cabecera, un tono más oscuro.
        local g = love.graphics
        Tema.color('caqui', 0.95)
        g.rectangle('fill', x, y, w, h, Tema.px(3), Tema.px(3))
        if opciones.titulo then
            g.setColor(0.62, 0.62, 0.56, 0.98)
            g.rectangle('fill', x, y, w, Tema.px(46), Tema.px(3), Tema.px(3))
        end
        Tema.color('filoOliva')
        g.setLineWidth(math.max(1, Tema.px(1.5)))
        g.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1, Tema.px(3), Tema.px(3))
        g.setLineWidth(1)
    else
        Acero.nueve(pieza, 'normal', x, y, w, h)
        -- El kit trae el oliva casi negro: se levanta hacia el caqui del HUD.
        Acero.levantar(x, y, w, h, 0.5)
    end
    local cx, cy, cw, ch = Acero.contenido(pieza, x, y, w, h)
    local cierre
    if opciones.titulo then
        local ancho = Tema.px(44)
        local fuente = Acero.fuente('titulo')
        local ty = y + math.floor((Tema.px(44) - fuente:getHeight()) / 2)
        love.graphics.setFont(fuente)
        local margen = Tema.px(16)
        local libre = w - margen * 2 - (opciones.cerrar and ancho or 0)
        Tema.color('textoHud')
        love.graphics.print(Tema.cortar(fuente, opciones.titulo, libre), x + margen, ty)
        if opciones.subtitulo then
            local sub = Acero.fuente('etiqueta')
            Tema.color('textoHudTenue')
            local sx = x + margen + math.min(fuente:getWidth(opciones.titulo), libre) + Tema.px(12)
            local resto = x + w - margen - (opciones.cerrar and ancho or 0) - sx
            if resto > Tema.px(40) then
                love.graphics.setFont(sub)
                love.graphics.print(
                    Tema.cortar(sub, opciones.subtitulo, resto),
                    sx,
                    ty + fuente:getHeight() - sub:getHeight() - Tema.px(3)
                )
            end
        end
        if opciones.cerrar then
            local lado = Tema.px(32)
            local bx, by = x + w - lado - Tema.px(8), y + Tema.px(6)
            Acero.botonCerrar(bx, by, lado)
            cierre = { x = bx, y = by, w = lado, h = lado }
        end
    end
    return cx, cy, cw, ch, cierre
end

--- Fondo de un panel sin cabecera: gris caqui claro en `Tema.modoClaro` o el
-- oliva del kit levantado.
function Acero.fondoPanel(x, y, w, h)
    if Tema.modoClaro then
        local g = love.graphics
        Tema.color('caqui', 0.95)
        g.rectangle('fill', x, y, w, h, Tema.px(3), Tema.px(3))
        Tema.color('filoOliva')
        g.setLineWidth(math.max(1, Tema.px(1.5)))
        g.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1, Tema.px(3), Tema.px(3))
        g.setLineWidth(1)
    else
        Acero.nueve('panel_acero', 'normal', x, y, w, h)
        Acero.levantar(x, y, w, h, 0.5)
    end
end

--- Panel de contenido gris claro (formularios, perfil, opciones).
function Acero.panelClaro(x, y, w, h)
    Acero.nueve('panel_contenido', 'normal', x, y, w, h)
    return Acero.contenido('panel_contenido', x, y, w, h)
end

--- Placa oscura pequeña (chips de recurso, cifras, contadores).
function Acero.chip(x, y, w, h, alfa)
    if Tema.modoClaro then
        Tema.color('caquiFila', 0.85)
        love.graphics.rectangle('fill', x, y, w, h, Tema.px(3), Tema.px(3))
        Tema.color('lineaOliva', 0.6)
        love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1, Tema.px(3), Tema.px(3))
        return
    end
    Acero.nueve('chip_oscuro', 'normal', x, y, w, h, alfa or 0.6)
end

--- Rótulo translúcido (nombres sobre el mapa, avisos ligeros).
function Acero.rotulo(x, y, w, h)
    Acero.nueve('rotulo', 'normal', x, y, w, h)
end

--- Filete horizontal que separa filas de un panel.
function Acero.separador(x, y, w)
    Acero.nueve('separador', 'normal', x, y, w, Tema.px(2))
end

-- Iconos -------------------------------------------------------------------------------------

--- Icono del kit teñido con un color de la paleta, cuadrado de `lado` px.
function Acero.icono(nombre, x, y, lado, color, alfa)
    local dato = Indice.iconos[nombre]
    if not dato then
        return
    end
    local img = imagen(dato.archivos[lado > 36 and '64' or '32'])
    local iw = img:getWidth()
    Tema.color(color or 'textoHud', alfa)
    love.graphics.draw(img, math.floor(x + 0.5), math.floor(y + 0.5), 0, lado / iw, lado / iw)
end

--- Icono a color del kit (`Indice.iconosColor`: metal, petróleo, comida,
-- dinero, poder), cuadrado de `lado` px, sin teñir.
function Acero.iconoColor(nombre, x, y, lado, alfa)
    local dato = Indice.iconosColor[nombre]
    if not dato then
        return
    end
    local img = imagen(dato.archivos[lado > 36 and '64' or '32'])
    love.graphics.setColor(1, 1, 1, alfa or 1)
    love.graphics.draw(img, math.floor(x + 0.5), math.floor(y + 0.5), 0, lado / img:getWidth(), lado / img:getHeight())
end

-- Botones ------------------------------------------------------------------------------------

local TIPOS = { principal = 'dorado', secundario = 'gris', peligro = 'rojo' }

local quadsInsignia
local DIRECCIONES = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

local ROJOS = {
    normal = 'rojo',
    resaltado = { 0.76, 0.2, 0.165 },
    pulsado = { 0.56, 0.13, 0.11 },
    desactivado = { 0.23, 0.16, 0.16 },
}

--- Estado visual de un botón: desactivado, pulsado, resaltado o normal.
local function estadoDe(activo, encima)
    if activo == false then
        return 'desactivado'
    end
    if encima and love.mouse.isDown(1) then
        return 'pulsado'
    end
    return encima and 'resaltado' or 'normal'
end

--- Botón (§4). `boton` = { texto, tipo, activo, precio, icono, estado }; `estado`
-- (opcional) lo fuerza, para la galería; `tipo`:
-- 'dorado' (o 'principal'), 'gris' ('secundario'), 'oscuro' o 'rojo'
-- ('peligro'). Devuelve si el ratón está encima.
function Acero.boton(boton, x, y, w, h, compacto)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local tipo = TIPOS[boton.tipo or 'secundario'] or boton.tipo
    local dentro = Tema.dentro(mx, my, x, y, w, h)
    local encima = boton.activo ~= false and dentro
    local estado = boton.estado or estadoDe(boton.activo, encima)
    -- Vida (interfaz/vida.lua): el fondo crece un poco con el ratón encima y
    -- se hunde al pulsar; el texto no se escala (sigue nítido).
    local fx, fy, fw, fh = x, y, w, h
    if not boton.estado and boton.activo ~= false then
        local crece, hunde = Vida.boton(Vida.claveRect('b', x, y, w, h), encima, estado == 'pulsado')
        local m = Tema.escala() * (crece * 4 - hunde * 2)
        fx, fy, fw, fh = x - m, y - m + hunde * Tema.escala() * 2, w + m * 2, h + m * 2
    end
    if tipo == 'rojo' then
        Acero.placa(fx, fy, fw, fh, Tema.px(6), ROJOS[estado], estado == 'resaltado' and 'amarillo' or 'filoOliva')
        if estado ~= 'desactivado' and estado ~= 'pulsado' then
            Tema.color('rojoTexto', 0.5)
            g.rectangle('fill', fx + Tema.px(7), fy + 1, fw - Tema.px(14), 1)
        end
    else
        Acero.nueve('boton_' .. tipo, estado, fx, fy, fw, fh)
    end
    local colorTexto = Tema.colores.textoHud
    if estado == 'desactivado' then
        colorTexto = (tipo == 'gris' or tipo == 'dorado') and 'tintaTenue' or 'textoDesact'
    elseif tipo == 'dorado' then
        colorTexto = 'amarilloTinta'
    elseif tipo == 'gris' then
        -- El gris del kit es claro: el texto va oscuro para que se lea (4,5:1).
        colorTexto = 'tinta'
    end
    local fuente = compacto and Acero.fuente('boton', 18) or Acero.fuente('boton', 22)
    if boton.texto == '+' or boton.texto == '−' then
        fuente = Acero.fuente('boton', 30)
    end
    local texto = boton.texto
    local lado = math.floor(fuente:getHeight() * 0.85)
    local separa = Tema.px(6)
    local anchoIcono = boton.icono and (lado + separa) or 0
    local precio = boton.precio and Tema.numero(boton.precio)
    local anchoPrecio = precio and (separa * 2 + lado + fuente:getWidth(precio)) or 0
    local anchoTexto = fuente:getWidth(texto)
    local libre = w - Tema.px(16)
    if anchoIcono + anchoTexto + anchoPrecio > libre then
        texto = Tema.cortar(fuente, texto, math.max(Tema.px(20), libre - anchoIcono - anchoPrecio))
        anchoTexto = fuente:getWidth(texto)
    end
    local cursor = math.floor(x + (w - anchoIcono - anchoTexto - anchoPrecio) / 2)
    local baja = estado == 'pulsado' and 1 or 0
    local ty = math.floor(y + (h - fuente:getHeight()) / 2) + baja
    if boton.icono then
        Acero.icono(boton.icono, cursor, y + (h - lado) / 2 + baja, lado, colorTexto)
        cursor = cursor + anchoIcono
    end
    g.setFont(fuente)
    Tema.color(colorTexto)
    g.print(texto, cursor, ty)
    if precio then
        cursor = cursor + anchoTexto + separa * 2
        local vivo = estado ~= 'desactivado'
        Acero.icono(
            'dinero',
            cursor,
            y + (h - lado) / 2 + baja,
            lado,
            vivo and (tipo == 'dorado' and 'amarilloTinta' or 'amarillo') or 'textoDesact'
        )
        g.print(precio, cursor + lado + separa, ty)
    end
    return dentro
end

--- Ancho que pide un botón con su texto, su icono y su precio.
function Acero.anchoBoton(boton, compacto)
    local fuente = compacto and Acero.fuente('boton', 18) or Acero.fuente('boton', 22)
    local lado = math.floor(fuente:getHeight() * 0.85)
    local separa = Tema.px(6)
    local ancho = fuente:getWidth(boton.texto) + Tema.px(compacto and 24 or 32)
    if boton.icono then
        ancho = ancho + lado + separa
    end
    if boton.precio then
        ancho = ancho + separa * 2 + lado + fuente:getWidth(Tema.numero(boton.precio))
    end
    return ancho
end

--- Botón cuadrado de cierre (la X del kit). Devuelve si el ratón está encima.
function Acero.botonCerrar(x, y, lado)
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, lado, lado)
    local estado = estadoDe(true, encima)
    local img = imagen(Indice.piezas.boton_cerrar.archivos[estado])
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, lado / img:getWidth(), lado / img:getHeight())
    return encima
end

--- Texto con contorno (blanco sobre el mapa, familia oliva): se dibuja ocho
-- veces con el color del contorno, desplazado, y una con el color del texto.
-- `contorno` por defecto es `filoOliva`; `grosor` en píxeles de pantalla.
function Acero.textoContorno(fuente, texto, x, y, color, contorno, alfa, grosor)
    local g = love.graphics
    g.setFont(fuente)
    local r = grosor or math.max(1, math.floor(Tema.escala() + 0.5))
    Tema.color(contorno or 'filoOliva', (alfa or 1) * 0.9)
    for _, d in ipairs(DIRECCIONES) do
        g.print(texto, x + d[1] * r, y + d[2] * r)
    end
    Tema.color(color or 'textoHud', alfa)
    g.print(texto, x, y)
end

--- Insignia roja con un número (cuenta de avisos), centrada en (cx, cy), con
-- la pieza del kit. Con más de 99 dice «99+» (solo por ancho; el tooltip da
-- el número).
function Acero.insignia(cx, cy, cuenta)
    local g = love.graphics
    -- Late cuando cambia la cuenta (interfaz/vida.lua).
    local escala = Vida.latido(Vida.claveRect('i', cx, cy, 0, 0), cuenta)
    if escala ~= 1 then
        g.push()
        g.translate(cx, cy)
        g.scale(escala)
        g.translate(-cx, -cy)
    end
    local texto = cuenta > 99 and '99+' or tostring(cuenta)
    local fuente = Acero.fuente('etiqueta', 14)
    local d = Tema.px(cuenta > 9 and 26 or 24)
    local ancho = math.max(d, fuente:getWidth(texto) + Tema.px(10))
    local img = imagen(Indice.piezas.insignia_roja.archivos.normal)
    g.setColor(1, 1, 1, 1)
    if ancho > d then
        -- Con dos cifras o más, una píldora: dos mitades de la insignia y el medio.
        local mitad = math.floor(d / 2)
        quadsInsignia = quadsInsignia
            or { love.graphics.newQuad(0, 0, 12, 24, 24, 24), love.graphics.newQuad(12, 0, 12, 24, 24, 24) }
        local quadIzq, quadDer = quadsInsignia[1], quadsInsignia[2]
        g.draw(img, quadIzq, cx - ancho / 2, cy - d / 2, 0, mitad / 12, d / 24)
        g.draw(img, quadDer, cx + ancho / 2 - mitad, cy - d / 2, 0, mitad / 12, d / 24)
        Tema.color('rojo')
        g.rectangle('fill', cx - ancho / 2 + mitad, cy - d / 2 + 2, ancho - mitad * 2, d - 4)
    else
        g.draw(img, cx - d / 2, cy - d / 2, 0, d / img:getWidth(), d / img:getHeight())
    end
    g.setFont(fuente)
    g.setColor(1, 1, 1, 1)
    g.print(texto, math.floor(cx - fuente:getWidth(texto) / 2), math.floor(cy - fuente:getHeight() / 2))
    if escala ~= 1 then
        g.pop()
    end
end

--- Pastilla roja «Nuevo» (o un aviso de texto corto), con su esquina
-- superior derecha en (x, y).
function Acero.insigniaNuevo(x, y, texto)
    local fuente = Acero.fuente('etiqueta', 13)
    texto = texto or 'Nuevo'
    local ancho = math.max(Tema.px(44), fuente:getWidth(texto) + Tema.px(16))
    local alto = Tema.px(20)
    Acero.nueve('insignia_nuevo', 'normal', x - ancho, y, ancho, alto)
    love.graphics.setFont(fuente)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        texto,
        math.floor(x - ancho / 2 - fuente:getWidth(texto) / 2),
        math.floor(y + (alto - fuente:getHeight()) / 2)
    )
end

--- Hexágono de metal (`hexagono_icono`) de `ancho` px de ancho con su icono y,
-- debajo, la etiqueta blanca con contorno y la insignia roja. `opciones` =
-- { icono, dibujar, etiqueta, activo, desactivado, cuenta, nuevo }. Devuelve
-- si el ratón está encima y el alto total que ocupa.
function Acero.hexagono(x, y, ancho, opciones)
    local g = love.graphics
    local pieza = Indice.piezas.hexagono_icono
    local alto = math.floor(ancho * pieza.alto / pieza.ancho + 0.5)
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, ancho, alto)
    local estado = 'normal'
    if opciones.desactivado then
        estado = 'desactivado'
    elseif opciones.activo then
        estado = 'activo'
    elseif encima and love.mouse.isDown(1) then
        estado = 'pulsado'
    elseif encima then
        estado = 'resaltado'
    end
    local img = imagen(pieza.archivos[estado])
    -- Vida: crece un poco con el ratón encima y se hunde al pulsar.
    local f = 1
    if not opciones.desactivado then
        local crece, hunde = Vida.boton(Vida.claveRect('h', x, y, ancho, alto), encima, estado == 'pulsado')
        f = 1 + 0.06 * crece - 0.05 * hunde
    end
    local hx, hy, hw, hh = x + ancho * (1 - f) / 2, y + alto * (1 - f) / 2, ancho * f, alto * f
    g.setColor(1, 1, 1, 1)
    g.draw(img, hx, hy, 0, hw / img:getWidth(), hh / img:getHeight())
    local baja = estado == 'pulsado' and 1 or 0
    local lado = math.floor(ancho * 0.5 * f)
    local ix, iy = math.floor(x + (ancho - lado) / 2), math.floor(y + (alto - lado) / 2) + baja
    local color = opciones.activo and 'amarilloTinta' or (opciones.desactivado and 'textoDesact' or 'textoHud')
    if opciones.dibujar then
        opciones.dibujar(ix, iy, lado, color)
    else
        Acero.icono(opciones.icono, ix, iy, lado, color)
    end
    if opciones.brillo and not opciones.desactivado then
        -- Un brillo pasa de vez en cuando por la placa y el icono.
        Vida.brillo(img, hx, hy, hw / img:getWidth(), hh / img:getHeight(), opciones.brillo, 0.22)
        local dato = opciones.icono and Indice.iconos[opciones.icono]
        if dato then
            local ii = imagen(dato.archivos[lado > 36 and '64' or '32'])
            Vida.brillo(ii, ix, iy, lado / ii:getWidth(), lado / ii:getWidth(), opciones.brillo, 0.55)
        end
    end
    local total = alto
    if opciones.etiqueta then
        local fuente = Acero.fuente('boton', 17)
        local texto = Tema.cortar(fuente, opciones.etiqueta, math.floor(ancho * 1.5))
        local tx = math.floor(x + (ancho - fuente:getWidth(texto)) / 2)
        local ty = y + alto - Tema.px(2)
        Acero.textoContorno(fuente, texto, tx, ty, opciones.activo and 'amarillo' or 'textoHud')
        total = alto - Tema.px(2) + fuente:getHeight()
    end
    if opciones.nuevo then
        Acero.insigniaNuevo(x + ancho + Tema.px(4), y - Tema.px(2))
    elseif (opciones.cuenta or 0) > 0 then
        Acero.insignia(x + ancho - Tema.px(6), y + Tema.px(10), opciones.cuenta)
    end
    return encima, total
end

--- Botón de icono con etiqueta debajo (columna izquierda y barra de abajo):
-- un hexágono que cabe en el rectángulo (x, y, w, h) con su etiqueta.
-- `opciones` como en `hexagono`. Devuelve si el ratón está encima.
function Acero.botonIcono(x, y, w, h, opciones)
    local etiqueta = opciones.etiqueta and Acero.fuente('boton', 17):getHeight() - Tema.px(2) or 0
    local pieza = Indice.piezas.hexagono_icono
    local alto = h - etiqueta
    local ancho = math.min(w, math.floor(alto * pieza.ancho / pieza.alto))
    local encima = Acero.hexagono(x + math.floor((w - ancho) / 2), y, ancho, opciones)
    return encima
end

--- Pestaña: `activa` lleva el fondo de selección y el filete dorado.
-- Devuelve si el ratón está encima.
function Acero.pestana(x, y, w, h, texto, activa, pendiente)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, w, h)
    if Tema.modoClaro then
        if activa then
            Tema.color('papelBoton')
        else
            love.graphics.setColor(0.69, 0.69, 0.64, 1)
        end
        love.graphics.rectangle('fill', x, y, w, h, Tema.px(3), Tema.px(3))
        if activa then
            Tema.color('amarillo')
            love.graphics.rectangle('fill', x + Tema.px(4), y + h - Tema.px(4), w - Tema.px(8), Tema.px(3))
        end
    else
        Acero.nueve('pestana', activa and 'activa' or 'inactiva', x, y, w, h)
    end
    if encima and not activa then
        Tema.color('lineaOliva', 0.22)
        g.rectangle('fill', x + Tema.px(4), y + Tema.px(4), w - Tema.px(8), h - Tema.px(6))
    end
    local fuente = Acero.fuente('boton', 20)
    g.setFont(fuente)
    Tema.color(activa and 'amarillo' or (encima and 'textoHud' or 'textoHudTenue'))
    local cortado = Tema.cortar(fuente, texto, w - Tema.px(12))
    local tx = math.floor(x + (w - fuente:getWidth(cortado)) / 2)
    local ty = math.floor(y + (h - fuente:getHeight()) / 2) - Tema.px(2)
    g.print(cortado, tx, ty)
    if pendiente and not activa then
        Tema.color('rojo')
        g.circle('fill', tx + fuente:getWidth(cortado) + Tema.px(6), ty + fuente:getHeight() * 0.3, Tema.px(3.5))
    end
    return encima
end

-- Barras y listas -----------------------------------------------------------------------------

local RELLENOS = {
    recurso = 'barra_relleno_recurso',
    estadistica = 'barra_relleno_estadistica',
    experiencia = 'barra_relleno_experiencia',
    peligro = 'barra_relleno_peligro',
    energia = 'barra_relleno_energia',
}

--- Barra: canal oscuro del kit con el relleno de un tipo (`energia` verde,
-- `recurso` dorado, `peligro` rojo, `estadistica`, `experiencia`) hasta la
-- fracción `parte` (0 a 1). Con `pendiente` (0 a 1) pinta detrás lo encargado.
function Acero.barra(x, y, w, h, parte, tipo, pendiente)
    Acero.nueve('barra_fondo', 'normal', x, y, w, h)
    local margen = Tema.px(2)
    local ix, iy, iw, ih = x + margen, y + margen, w - margen * 2, h - margen * 2
    parte = math.max(0, math.min(1, parte or 0))
    if (pendiente or 0) > 0 then
        local desde = math.floor(iw * parte)
        local largo = math.floor(iw * math.min(1 - parte, pendiente))
        Tema.color('amarilloDinero', 0.5)
        love.graphics.rectangle('fill', ix + desde, iy, largo, ih)
    end
    local ancho = math.floor(iw * parte)
    if ancho > 0 then
        Acero.nueve(RELLENOS[tipo or 'energia'], 'normal', ix, iy, ancho, ih)
    end
end

--- Fila de lista: `estado` = 'normal', 'hover' o 'seleccionada'; `clara`
-- para las de contenido claro.
function Acero.fila(x, y, w, h, estado, clara)
    if Tema.modoClaro and not clara then
        if estado == 'seleccionada' then
            Tema.color('papelBoton', 0.95)
        elseif estado == 'hover' then
            Tema.color('caquiFila', 0.8)
        else
            Tema.color('caquiFila', 0.0)
        end
        love.graphics.rectangle('fill', x, y, w, h, Tema.px(2), Tema.px(2))
        return
    end
    Acero.nueve(clara and 'fila_clara' or 'fila_oscura', estado or 'normal', x, y, w, h)
    if not clara then
        Acero.levantar(x, y, w, h, 0.3)
    end
end

--- Barra de desplazamiento fina (6 px) para el tramo (x, y, alto).
function Acero.desplazamiento(x, y, alto, visible, total, posicion)
    local ancho = Tema.px(6)
    Tema.color('olivaNegro', 0.8)
    love.graphics.rectangle('fill', x, y, ancho, alto, ancho / 2, ancho / 2)
    local tirador = math.max(Tema.px(28), alto * visible / total)
    local ty = y + (alto - tirador) * posicion
    Tema.color('lineaOliva')
    love.graphics.rectangle('fill', x, ty, ancho, tirador, ancho / 2, ancho / 2)
end

-- Ayuda ----------------------------------------------------------------------------------------

--- Ayuda junto al puntero (§4): `abismo` al 96 % con borde dorado y esquinas
-- cortadas, metida en la pantalla.
function Acero.tooltip(texto, mx, my, anchoMax)
    local g = love.graphics
    local fuente = Acero.fuente('ayuda')
    local relleno = Tema.px(8)
    local ancho = math.min(anchoMax or Tema.px(420), fuente:getWidth(texto) + relleno * 2)
    local _, partes = fuente:getWrap(texto, ancho - relleno * 2)
    local alto = #partes * fuente:getHeight() + relleno * 2
    local w, h = g.getDimensions()
    local x = math.max(4, math.min(w - ancho - 4, mx + Tema.px(14)))
    local y = math.max(4, math.min(h - alto - 4, my + Tema.px(18)))
    Acero.placa(x, y, ancho, alto, Tema.px(4), 'olivaNegro', 'lineaOliva', 0.96)
    g.setFont(fuente)
    Tema.color('textoHud')
    g.printf(texto, x + relleno, y + relleno, ancho - relleno * 2, 'left')
end

return Acero

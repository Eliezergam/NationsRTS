-- Maqueta de las páginas del navegador de Vexar: coloca los bloques que
-- arma una página (almacen/pc/web/pagina.lua) en líneas ya partidas al ancho
-- de la ventana, con cada trozo en su sitio, para que el navegador
-- (almacen/pc/programas/navegador.lua) solo tenga que pintarlos.
--
-- Bloques: { tipo = 'titulo', nivel, trozos } · 'parrafo' · 'lista' · 'nota'
-- (con trozos), 'separador', 'espacio' (alto), 'tabla' (filas de celdas de
-- trozos) y 'boton' (texto, indice).
--
-- Dentro de un texto (Maqueta.trozos):
--   **negrita**
--   [texto del enlace](destino)
--   {rojo|texto en color}   rojo, verde, amarillo, azul, cian, gris, naranja,
--                           blanco
--   \*  \[  \{             el carácter tal cual (sin formato)

local Dibujo = require('almacen.pc.dibujo')

local Maqueta = {}

Maqueta.colores = {
    texto = { 0.86, 0.89, 0.9 },
    titulo = { 0.96, 0.97, 0.97 },
    enlace = { 0.38, 0.72, 1 },
    rojo = { 1, 0.4, 0.33 },
    verde = { 0.36, 0.88, 0.5 },
    amarillo = { 0.95, 0.8, 0.3 },
    azul = { 0.38, 0.6, 1 },
    cian = { 0.35, 0.88, 0.95 },
    gris = { 0.56, 0.6, 0.62 },
    naranja = { 1, 0.6, 0.25 },
    blanco = { 1, 1, 1 },
}

-- Tamaño de letra de cada clase de texto (px del escritorio).
Maqueta.tamanos = { texto = 19, titulo1 = 40, titulo2 = 30, titulo3 = 24, tabla = 18 }
Maqueta.interlineado = 1.25
Maqueta.fotoPublicacion = 48 -- px del círculo con la foto de una publicación
Maqueta.sangriaLista = 26

--- Trozos de una línea de texto: { { texto, negrita, color, enlace }, ... }.
function Maqueta.trozos(texto)
    local lista = {}
    local negrita = false
    local actual = ''
    local function cerrar()
        if actual ~= '' then
            lista[#lista + 1] = { texto = actual, negrita = negrita }
            actual = ''
        end
    end
    local i = 1
    while i <= #texto do
        local resto = texto:sub(i)
        local textoEnlace, destino = resto:match('^%[([^%]]*)%]%(([^%)]*)%)')
        local nombreColor, textoColor = resto:match('^{(%a+)|([^}]*)}')
        if resto:sub(1, 1) == '\\' and #resto > 1 then
            -- \* \[ \{ ...: el carácter tal cual, sin formato.
            local largo = resto:match('^\\([\1-\127\194-\244][\128-\191]*)')
            actual = actual .. (largo or resto:sub(2, 2))
            i = i + 1 + #(largo or resto:sub(2, 2))
        elseif resto:sub(1, 2) == '**' then
            cerrar()
            negrita = not negrita
            i = i + 2
        elseif textoEnlace then
            cerrar()
            lista[#lista + 1] = { texto = textoEnlace, negrita = negrita, enlace = destino }
            i = i + #textoEnlace + #destino + 4
        elseif nombreColor and Maqueta.colores[nombreColor] then
            cerrar()
            lista[#lista + 1] = { texto = textoColor, negrita = negrita, color = Maqueta.colores[nombreColor] }
            i = i + #nombreColor + #textoColor + 3
        else
            actual = actual .. texto:sub(i, i)
            i = i + 1
        end
    end
    cerrar()
    return lista
end

--- Trozos de un texto de red social: las @menciones y las #etiquetas en
-- azul, el resto tal cual (sin otro formato).
function Maqueta.trozosSociales(texto)
    local lista = {}
    local i = 1
    while i <= #texto do
        local desde, hasta = texto:find('[@#][%w_\128-\255]+', i)
        if not desde then
            lista[#lista + 1] = { texto = texto:sub(i) }
            break
        end
        if desde > i then
            lista[#lista + 1] = { texto = texto:sub(i, desde - 1) }
        end
        local palabra = texto:sub(desde, hasta)
        -- Las @menciones llevan al perfil; las #etiquetas, a su búsqueda.
        local destino = palabra:sub(1, 1) == '@' and ('ondix.red/' .. palabra:sub(2)) or ('ondix.red/etiqueta/' .. palabra:sub(2))
        lista[#lista + 1] = { texto = palabra, color = Maqueta.colores.enlace, enlace = destino }
        i = hasta + 1
    end
    return lista
end

local function letraDe(tamano, negrita)
    return Dibujo.letra(negrita and 'paginaNegrita' or 'pagina', tamano)
end

--- Parte los trozos en líneas de `ancho` px como mucho. Devuelve una lista
-- de líneas { alto, piezas = { { x, texto, letra, color, enlace } } }.
local function partir(trozos, ancho, tamano, colorBase, negritaBase, letraTitulo)
    local lineas = {}
    local piezas = {}
    local x = 0
    local altoLinea = math.floor(Dibujo.letra('pagina', tamano):getHeight() * Maqueta.interlineado)
    local function nuevaLinea()
        lineas[#lineas + 1] = { alto = altoLinea, piezas = piezas }
        piezas = {}
        x = 0
    end
    for _, t in ipairs(trozos) do
        local letra = letraTitulo or letraDe(tamano, t.negrita or negritaBase)
        local color = t.color or (t.enlace and Maqueta.colores.enlace) or colorBase
        -- El espacio con que empieza el trozo («hola **mundo**»).
        local inicial = t.texto:match('^%s+')
        if inicial and x > 0 then
            x = x + letra:getWidth(inicial)
        end
        -- Palabra a palabra, con el espacio que la sigue.
        for palabra in t.texto:gmatch('%S+%s*') do
            local w = letra:getWidth(palabra)
            local sinEspacio = letra:getWidth((palabra:gsub('%s+$', '')))
            if x > 0 and x + sinEspacio > ancho then
                nuevaLinea()
            end
            piezas[#piezas + 1] = { x = x, texto = palabra, letra = letra, color = color, enlace = t.enlace, ancho = w }
            x = x + w
        end
    end
    if #piezas > 0 or #lineas == 0 then
        nuevaLinea()
    end
    return lineas
end

--- Coloca los bloques en `ancho` px. Devuelve los elementos a pintar, cada
-- uno con su `y` (desde arriba de la página), y el alto total.
--   { tipo = 'linea', y, alto, x0, piezas }
--   { tipo = 'separador', y }
--   { tipo = 'nota', y, alto }            (el recuadro; su texto va en líneas)
--   { tipo = 'punto', y, x, alto }        (la viñeta de una lista)
--   { tipo = 'fila', y, alto, cabecera, par, celdas = { { x, w, lineas } } }
--   { tipo = 'boton', y, x, w, alto, texto, letra, indice }
--   { tipo = 'publicacion', y, alto, x0, b (el bloque), cabecera, lineas }
function Maqueta.colocar(bloques, ancho)
    local elementos = {}
    local y = 0
    local T = Maqueta.tamanos
    local C = Maqueta.colores
    local function ponerLineas(lineas, x0)
        for _, l in ipairs(lineas) do
            elementos[#elementos + 1] = { tipo = 'linea', y = y, alto = l.alto, x0 = x0, piezas = l.piezas }
            y = y + l.alto
        end
    end
    for k, b in ipairs(bloques) do
        if b.tipo == 'titulo' then
            local tamano = T['titulo' .. b.nivel]
            if k > 1 then
                y = y + math.floor(tamano * 0.5)
            end
            ponerLineas(partir(b.trozos, ancho, tamano, C.titulo, true, Dibujo.letra('titulo', tamano)), 0)
            y = y + 6
        elseif b.tipo == 'parrafo' then
            ponerLineas(partir(b.trozos, ancho, T.texto, C.texto), 0)
            y = y + 12
        elseif b.tipo == 'lista' then
            local lineas = partir(b.trozos, ancho - Maqueta.sangriaLista, T.texto, C.texto)
            elementos[#elementos + 1] = { tipo = 'punto', y = y, x = 9, alto = lineas[1].alto }
            ponerLineas(lineas, Maqueta.sangriaLista)
            local siguiente = bloques[k + 1]
            y = y + ((siguiente and siguiente.tipo == 'lista') and 2 or 12)
        elseif b.tipo == 'nota' then
            local lineas = partir(b.trozos, ancho - 40, T.texto, C.texto)
            local alto = 0
            for _, l in ipairs(lineas) do
                alto = alto + l.alto
            end
            elementos[#elementos + 1] = { tipo = 'nota', y = y, alto = alto + 20 }
            y = y + 10
            ponerLineas(lineas, 22)
            y = y + 10 + 14
        elseif b.tipo == 'separador' then
            y = y + 8
            elementos[#elementos + 1] = { tipo = 'separador', y = y }
            y = y + 18
        elseif b.tipo == 'publicacion' then
            -- Foto a la izquierda; nombre, @ y día arriba; «Respondiendo a»;
            -- el texto; y abajo los contadores.
            local foto = b.pequena and 36 or Maqueta.fotoPublicacion
            local x0 = foto + 14
            local tamano = b.pequena and 18 or T.texto
            local lineas = partir(b.trozos, ancho - x0, tamano, C.texto)
            local altoTexto = 0
            for _, l in ipairs(lineas) do
                altoTexto = altoTexto + l.alto
            end
            -- La publicación citada, en un recuadro debajo del texto.
            local cita, altoCita
            if b.cita then
                local lineasCita = partir(b.cita.trozos, ancho - x0 - 32, 17, C.texto)
                altoCita = 16 + 26
                for _, l in ipairs(lineasCita) do
                    altoCita = altoCita + l.alto
                end
                cita = { lineas = lineasCita, alto = altoCita + 12 }
            end
            local cabecera = 30
            local alto = 14 + cabecera + altoTexto + (cita and (cita.alto + 10) or 0) + (b.pequena and 34 or 40)
            elementos[#elementos + 1] = {
                tipo = 'publicacion',
                y = y,
                alto = alto,
                x0 = x0,
                foto = foto,
                b = b,
                cabecera = cabecera,
                lineas = lineas,
                cita = cita,
            }
            y = y + alto
        elseif b.tipo == 'espacio' then
            y = y + (b.alto or 12)
        elseif b.tipo == 'campo' then
            local letra = letraDe(T.texto)
            local alto = letra:getHeight() * b.lineas + 24
            elementos[#elementos + 1] = { tipo = 'campo', y = y, x = 0, w = ancho, alto = alto, pista = b.pista, letra = letra, indice = b.indice, limite = b.limite }
            y = y + alto + 10
        elseif b.tipo == 'boton' then
            local letra = letraDe(T.texto, true)
            local w = letra:getWidth(b.texto) + 36
            local alto = letra:getHeight() + 16
            elementos[#elementos + 1] = { tipo = 'boton', y = y, x = 0, w = w, alto = alto, texto = b.texto, letra = letra, indice = b.indice }
            y = y + alto + 12
        elseif b.tipo == 'tabla' then
            local columnas = 0
            for _, fila in ipairs(b.filas) do
                columnas = math.max(columnas, #fila)
            end
            local anchoColumna = ancho / math.max(1, columnas)
            for n, fila in ipairs(b.filas) do
                local celdasFila = {}
                local altoFila = 0
                for c = 1, columnas do
                    local lineas = partir(fila[c] or {}, anchoColumna - 20, T.tabla, C.texto, n == 1)
                    local alto = 0
                    for _, l in ipairs(lineas) do
                        alto = alto + l.alto
                    end
                    altoFila = math.max(altoFila, alto)
                    celdasFila[c] = { x = (c - 1) * anchoColumna, w = anchoColumna, lineas = lineas }
                end
                elementos[#elementos + 1] = { tipo = 'fila', y = y, alto = altoFila + 12, cabecera = n == 1, par = n % 2 == 0, celdas = celdasFila }
                y = y + altoFila + 12
            end
            y = y + 14
        end
    end
    return elementos, y
end

return Maqueta

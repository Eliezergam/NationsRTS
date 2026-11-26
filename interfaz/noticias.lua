-- Noticias: ventana emergente abajo a la izquierda, junto a la columna de
-- iconos (diseno/interfaz-militar.md, §5.12). Oculta por defecto: la abre el
-- hexágono «Noticias» de la barra de abajo (con la insignia roja de las no
-- leídas, `nuevas`) y la cierran su X, el mismo botón o Esc (`abierta`).
-- Pestañas Todas · Guerra · Diplomacia · Obras y las últimas noticias del
-- filtro, la más nueva abajo. La marca de la izquierda dice la prioridad
-- (F9): roja alta, gris media, gris oscura baja. Al pasar el ratón por una
-- noticia cortada, se lee entera.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Navegacion = require('interfaz.navegacion')

local Noticias = {}
Noticias.__index = Noticias

local FILTROS = {
    { clave = 'todas', texto = 'Todas' },
    { clave = 'guerra', texto = 'Guerra' },
    { clave = 'diplomacia', texto = 'Diplomacia' },
    { clave = 'obras', texto = 'Obras' },
}
local MAX_NOTICIAS = 8
-- Opacidad por puesto (F10): las 6 más nuevas enteras; las dos últimas, más tenues.
local OPACIDAD = { 1, 1, 1, 1, 1, 1, 0.72, 0.52 }

-- Palabras que dan la prioridad y el tipo de una noticia. La simulación solo
-- guarda texto y color (el cambio S1 añadirá el tipo); hasta entonces se
-- deduce del texto, que siempre sale de las mismas frases.
local ALTA = {
    'declara la guerra',
    'misiles contra',
    'misiles de ',
    'misiles lanzados',
    'combate',
    ' toma ',
    'destruye',
    ' saquea ',
    'una bandera',
    'su bandera',
    'cae ',
    'crimen de guerra',
    'se retira',
    'asalto',
    'rechaza el ataque',
    'a por ',
    'refuerzos',
    'se rompe',
}
local MEDIA = { 'alto el fuego', 'la paz', 'conversaciones', 'miran para otro lado', 'cede', 'acuerdan' }
local OBRAS = { 'desarrolla', 'termina ', 'convoy', 'campamento', 'levantar', 'huerto' }
local DIPLOMACIA = { 'acuerdo comercial', 'incidente fronterizo', 'alianza', 'sanci' }

local function contiene(texto, lista)
    for _, palabra in ipairs(lista) do
        if texto:find(palabra, 1, true) then
            return true
        end
    end
    return false
end

--- Prioridad ('alta', 'media' o 'baja') y tipo ('guerra', 'diplomacia' u
-- 'obras') de una noticia, según su texto.
function Noticias.clasificar(noticia)
    if noticia.prioridad then
        return noticia.prioridad, noticia.tipo
    end
    local texto = noticia.texto:lower()
    if contiene(texto, OBRAS) then
        return 'baja', 'obras'
    end
    if contiene(texto, ALTA) then
        return 'alta', 'guerra'
    end
    if contiene(texto, MEDIA) then
        return 'media', 'diplomacia'
    end
    if contiene(texto, DIPLOMACIA) then
        return 'baja', 'diplomacia'
    end
    return 'baja', 'obras'
end

function Noticias.nuevo()
    local self = setmetatable({}, Noticias)
    self.filtro = 'todas'
    self.abierta = false
    -- La noticia más nueva que ya se vio (la tabla de la simulación): las
    -- de delante son las no leídas.
    self.vista = nil
    self.rect = nil
    self.zonas = {}
    self.ayuda = nil
    return self
end

--- Cuántas noticias no se han leído (las más nuevas que la última vista).
-- Si la última vista ya no está en la lista (partida cargada), todas.
function Noticias:nuevas(noticias)
    local cuenta = 0
    for _, n in ipairs(noticias) do
        if n == self.vista then
            return cuenta
        end
        cuenta = cuenta + 1
    end
    return cuenta
end

--- Da por leídas todas las noticias de ahora.
function Noticias:leer(noticias)
    self.vista = noticias[1]
end

--- Abre o cierra la ventana; al abrirla, todo queda leído.
function Noticias:alternar(noticias)
    self.abierta = not self.abierta
    if self.abierta then
        self:leer(noticias)
    end
end

--- Parte el texto en 2 líneas como mucho; la segunda se corta con «…».
local function dosLineas(fuente, texto, ancho)
    local _, lineas = fuente:getWrap(texto, ancho)
    if #lineas <= 2 then
        return lineas, false
    end
    local resto = table.concat(lineas, ' ', 2)
    return { lineas[1], Tema.cortar(fuente, resto, ancho) }, true
end

--- Dibuja las noticias; `noticias` es la lista de la simulación (la más nueva
-- primero). `compacta` = 3 noticias (con el pendón propio a la izquierda).
-- `techo` (opcional): y de pantalla por encima de la cual no debe subir el
-- panel (la ficha de un ejército, arriba a la izquierda): muestra menos filas y,
-- si ni con una cabe, se corre a la derecha hasta `xLibre`.
function Noticias:dibujar(noticias, compacta, techo, xLibre)
    -- Gris caqui claro con texto negro, como los paneles de sitio.
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarClaro, self, noticias, compacta, techo, xLibre)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
end

function Noticias:dibujarClaro(noticias, compacta, techo, xLibre)
    local g = love.graphics
    self.zonas = {}
    self.ayuda = nil
    if not self.abierta then
        self.rect = nil
        return
    end
    -- Abierta, lo que llega se lee al momento: la insignia no crece.
    self:leer(noticias)
    local _, h = g.getDimensions()
    local ancho = Tema.px(480)
    local x = Tema.px(112)
    -- El panel queda sobre la fila de hexágonos de la barra de abajo.
    local abajo = h - Navegacion.alto() - Tema.px(4)
    local relleno = Tema.px(12)
    local cabecera = Tema.px(50)
    local pestanas = Tema.px(36)
    local fuente = Acero.fuente('cuerpo', 16)
    local negrita = Acero.fuente('cifra', 16)
    local dia = Acero.fuente('etiqueta', 14)
    local anchoDia = Tema.px(36)
    local textoX = x + relleno + Tema.px(4) + Tema.px(8) + anchoDia + Tema.px(10)
    local anchoTexto = x + ancho - relleno - textoX

    -- Las del filtro, de la más nueva a la más vieja.
    local cuantas = compacta and 3 or MAX_NOTICIAS
    if techo then
        -- Cada noticia ocupa unas dos líneas; el resto del panel es fijo.
        local fijo = cabecera + pestanas + Tema.px(8) + relleno
        local libre = abajo - techo - fijo
        local filas1 = math.floor(libre / (fuente:getHeight() * 2 + Tema.px(6)))
        if filas1 < 2 and xLibre then
            x = xLibre
            textoX = x + relleno + Tema.px(4) + Tema.px(8) + anchoDia + Tema.px(10)
            anchoTexto = x + ancho - relleno - textoX
        else
            cuantas = math.max(1, math.min(cuantas, filas1))
        end
    end
    local filas = {}
    for _, n in ipairs(noticias) do
        local prioridad, tipo = Noticias.clasificar(n)
        if self.filtro == 'todas' or self.filtro == tipo then
            local letra = prioridad == 'alta' and negrita or fuente
            local lineas, cortada = dosLineas(letra, n.texto, anchoTexto)
            filas[#filas + 1] = {
                noticia = n,
                prioridad = prioridad,
                lineas = lineas,
                cortada = cortada,
                fuente = letra,
            }
            if #filas >= cuantas then
                break
            end
        end
    end
    local altoLinea = fuente:getHeight()
    local separacion = Tema.px(6)
    local altoLista = 0
    for _, f in ipairs(filas) do
        f.alto = #f.lineas * altoLinea
        altoLista = altoLista + f.alto + separacion
    end
    if #filas == 0 then
        altoLista = altoLinea + separacion
    end
    local alto = cabecera + pestanas + Tema.px(8) + altoLista + relleno - separacion
    local y = abajo - alto
    self.rect = { x = x, y = y, w = ancho, h = alto }

    local _, _, _, _, cierre = Acero.panel(x, y, ancho, alto, { titulo = 'Noticias', cerrar = true })
    if cierre then
        self.zonas[#self.zonas + 1] = { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, cerrar = true }
    end

    -- Pestañas de filtro.
    local mx, my = love.mouse.getPosition()
    local fx = x + relleno
    local fy = y + cabecera
    for _, f in ipairs(FILTROS) do
        local fuenteFiltro = Acero.fuente('boton', 20)
        local fw = fuenteFiltro:getWidth(f.texto) + Tema.px(28)
        Acero.pestana(fx, fy, fw, pestanas, f.texto, self.filtro == f.clave)
        self.zonas[#self.zonas + 1] = { x = fx, y = fy, w = fw, h = pestanas, filtro = f.clave }
        fx = fx + fw + Tema.px(4)
    end

    -- La lista: la más nueva abajo.
    local cursor = abajo - relleno
    if #filas == 0 then
        g.setFont(fuente)
        Tema.color('textoHudTenue')
        g.print('Nada que contar todavía', textoX, cursor - altoLinea)
    end
    for k, f in ipairs(filas) do
        cursor = cursor - f.alto
        local opacidad = OPACIDAD[k] or 0.42
        local marca = f.prioridad == 'alta' and 'rojoTexto'
            or (f.prioridad == 'media' and 'caquiPestana' or 'lineaOliva')
        Tema.color(marca, opacidad)
        g.rectangle('fill', x + relleno, cursor, Tema.px(3), f.alto)
        g.setFont(dia)
        Tema.color('textoHudTenue', Tema.modoClaro and 1 or opacidad)
        g.printf(
            tostring(f.noticia.dia),
            x + relleno + Tema.px(3) + Tema.px(8),
            cursor + math.floor((altoLinea - dia:getHeight()) / 2),
            anchoDia,
            'right'
        )
        g.setFont(f.fuente)
        Tema.color(f.prioridad == 'baja' and 'textoHudTenue' or 'textoHud', Tema.modoClaro and 1 or opacidad)
        for l, linea in ipairs(f.lineas) do
            g.print(linea, textoX, cursor + (l - 1) * altoLinea)
        end
        if f.cortada and Tema.dentro(mx, my, x, cursor, ancho, f.alto) then
            self.ayuda = f.noticia.texto
        end
        cursor = cursor - separacion
    end
end

function Noticias:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Tema.ayuda(self.ayuda, mx, my)
    end
end

function Noticias:ocultar()
    self.rect = nil
    self.zonas = {}
    self.ayuda = nil
end

function Noticias:encima(x, y)
    local r = self.rect
    return r and Tema.dentro(x, y, r.x, r.y, r.w, r.h) or false
end

--- Clic: cambia de filtro. Devuelve true si el clic cayó en las noticias.
function Noticias:pulsar(x, y)
    if not self:encima(x, y) then
        return false
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if z.cerrar then
                self.abierta = false
            else
                self.filtro = z.filtro
            end
        end
    end
    return true
end

return Noticias

-- Pregón: las tarjetas de evento de la derecha (diseno/interfaz-militar.md,
-- §5.10). Salen cuando la simulación da una noticia de guerra declarada,
-- caída de una capital, saqueo de una capital, bandera atacada o arrancada, o
-- crimen de guerra, y con los avisos y preguntas que pone main.lua. Cada una
-- dura 8 s con una raya inferior que se acorta. Sin tope: bajan por la
-- columna hasta llegar a la barra de abajo y las que no caben esperan detrás
-- de una tarjeta «+N avisos» (que abre las noticias); no se pierde ninguna.
-- «Ir» (o un clic en el cuerpo) hace lo de la tecla X; el clic derecho la
-- descarta. Las capitales ya no cambian de manos
-- (diseno/territorio-y-capitales.md, 3.3): perder en la capital es un saqueo.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Vida = require('interfaz.vida')

local Pregon = {}
Pregon.__index = Pregon

local DURACION = 8 -- segundos a la vista
local A_LA_VISTA = 3 -- las que se cuentan a la vista antes del primer cuadro

-- Qué noticias merecen pregón: un trozo de su texto y el título que llevan.
-- Las de banderas (`propia`) son muchas: solo dan pregón si nombran a la
-- nación del jugador, y nunca al que solo mira.
local GRAVES = {
    { busca = 'declara la guerra', titulo = 'Guerra declarada' },
    { busca = 'cae ', titulo = 'Cae una capital', inicio = true },
    { busca = ' saquea ', titulo = 'Capital saqueada' },
    { busca = 'ataca una bandera', titulo = 'Bandera atacada', propia = true, plazo = 'cae en %d+ días?' },
    { busca = 'arranca una bandera', titulo = 'Bandera arrancada', propia = true },
    { busca = 'se pierde por falta de mantenimiento', titulo = 'Bandera perdida', propia = true },
    { busca = 'crimen de guerra', titulo = 'Crimen de guerra' },
    { busca = 'se rompe el alto el fuego', titulo = 'Se rompe el alto el fuego' },
}

function Pregon.nuevo()
    local self = setmetatable({}, Pregon)
    self.cola = {} -- pregones pendientes, el más viejo primero
    self.vistas = setmetatable({}, { __mode = 'k' }) -- noticias ya miradas
    self.primera = true
    self.zonas = {}
    self.visibles = A_LA_VISTA -- cuántas caben en la columna (lo fija `dibujar`)
    return self
end

--- Título del pregón de una noticia, o nil si no lo merece. `propia` es el
-- nombre de la nación del jugador (nil si solo se mira).
local function titular(noticia, propia)
    local texto = noticia.texto:lower()
    for _, grave in ipairs(GRAVES) do
        local donde = texto:find(grave.busca, 1, true)
        if donde and (not grave.inicio or donde == 1) then
            if grave.propia and not (propia and noticia.texto:find(propia, 1, true)) then
                return nil
            end
            -- El plazo va en el título: el detalle se corta si es largo.
            local plazo = grave.plazo and texto:match(grave.plazo)
            return plazo and (grave.titulo .. ': ' .. plazo) or grave.titulo
        end
    end
    return nil
end

--- Mira las noticias nuevas y cuenta el tiempo de los pregones a la vista.
-- Al empezar (o al cargar otra partida) las noticias viejas no dan pregón.
-- `propia`: nombre de la nación del jugador (nil si solo se mira).
function Pregon:actualizar(dt, noticias, propia)
    local nuevas = {}
    for _, n in ipairs(noticias) do
        if self.vistas[n] then
            break
        end
        nuevas[#nuevas + 1] = n
    end
    for _, n in ipairs(noticias) do
        self.vistas[n] = true
    end
    if self.primera then
        self.primera = false
        return
    end
    -- De la más vieja a la más nueva, para que salgan en orden.
    for k = #nuevas, 1, -1 do
        local titulo = titular(nuevas[k], propia)
        if titulo then
            self.cola[#self.cola + 1] = { titulo = titulo, detalle = nuevas[k].texto, queda = DURACION }
        end
    end
    for k = math.min(self.visibles, #self.cola), 1, -1 do
        local p = self.cola[k]
        p.queda = p.queda - dt
        if p.queda <= 0 then
            p.terminado = true
            table.remove(self.cola, k)
        end
    end
end

--- Pregón propio de main.lua (no sale de una noticia), el primero de la
-- cola: `boton` es el texto de su botón y `accion` lo que devuelve `pulsar`
-- al hacer clic. Dura `duracion` segundos. Devuelve el pregón: al acabar su
-- tiempo queda `terminado`; si se descarta con el clic derecho, `descartado`.
function Pregon:avisar(titulo, detalle, boton, accion, duracion)
    local p = {
        titulo = titulo,
        detalle = detalle,
        queda = duracion or DURACION,
        duracion = duracion or DURACION,
        boton = boton,
        accion = accion,
    }
    table.insert(self.cola, 1, p)
    return p
end

--- Pregón propio con varios botones (por ejemplo, «Defender» y «Atacar»):
-- `botones` = { { texto, accion, tipo }, ... }, de izquierda a
-- derecha. Un clic en un botón devuelve su acción; en el cuerpo, nada. Al
-- acabar su tiempo queda `terminado` (main.lua aplica lo que toque por
-- defecto).
function Pregon:preguntar(titulo, detalle, botones, duracion)
    local p = self:avisar(titulo, detalle, nil, nil, duracion)
    p.botones = botones
    return p
end

--- Quita de la cola un pregón propio (ya no hace falta: la batalla acabó).
function Pregon:quitar(p)
    for k, otro in ipairs(self.cola) do
        if otro == p then
            table.remove(self.cola, k)
            return
        end
    end
end

--- Olvida lo que había (mundo nuevo o partida cargada).
function Pregon:reiniciar()
    self.cola = {}
    self.vistas = setmetatable({}, { __mode = 'k' })
    self.primera = true
end

--- Icono de una tarjeta según de qué habla su título.
local function iconoDe(titulo)
    local t = titulo:lower()
    if t:find('bandera', 1, true) then
        return 'bandera'
    elseif t:find('capital', 1, true) then
        return 'escudo'
    elseif t:find('guerra', 1, true) or t:find('ataque', 1, true) or t:find('batalla', 1, true) then
        return 'atacar'
    end
    return 'alerta'
end

--- Dibuja la columna de tarjetas bajo la barra superior (`arriba`), con su
-- borde derecho en `derecha` (o a 16 px del borde de la pantalla) y, con
-- `abajo`, sin bajar de ahí.
function Pregon:dibujar(arriba, derecha, abajo)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    local compacta = Tema.compacta()
    local ancho = Tema.px(compacta and 260 or 300)
    local altoBase = Tema.px(88)
    local miniatura = Tema.px(compacta and 64 or 84)
    local x = (derecha or (w - Tema.px(16))) - ancho
    local y = arriba or Tema.px(80)
    -- Hasta encima de la barra de navegación o, si se da, hasta `abajo` (el
    -- panel de tropas).
    local limite = abajo or h - Tema.px(16 + 72 + 16)
    local titulo = Acero.fuente('boton', 20)
    local detalle = Acero.fuente('etiqueta', 15)
    local mx, my = love.mouse.getPosition()
    local dibujadas = 0
    for k, p in ipairs(self.cola) do
        local lista = p.botones
        local botonSolo = not lista and { texto = p.boton or 'Ir', tipo = p.accion and 'principal' or 'secundario' }
        local alto = altoBase + (lista and (Tema.px(36) + Tema.px(8)) or 0)
        local pendientes = #self.cola - k
        local reserva = pendientes > 0 and (Tema.px(40) + Tema.px(6)) or 0
        if y + alto + reserva > limite and dibujadas > 0 then
            break
        end
        dibujadas = k
        -- Cada aviso entra deslizándose desde la derecha con fundido.
        Vida.entrar('aviso:' .. tostring(p), Tema.px(40), 0)
        local encima = Tema.dentro(mx, my, x, y, ancho, alto)
        Acero.nueve('tarjeta_unidad', encima and 'resaltada' or 'normal', x, y, ancho, alto)
        Acero.levantar(x, y, ancho, alto, 0.4)
        -- Grave: borde izquierdo de 4 px en rojo.
        Tema.color('rojo')
        g.rectangle('fill', x + Tema.px(3), y + Tema.px(8), Tema.px(4), altoBase - Tema.px(16))
        -- Miniatura con el icono del tipo.
        local mxi, myi = x + Tema.px(12), y + Tema.px(8)
        local mh = altoBase - Tema.px(16)
        Tema.color('olivaNegro')
        g.rectangle('fill', mxi, myi, miniatura - Tema.px(12), mh, Tema.px(3), Tema.px(3))
        Tema.borde(mxi, myi, miniatura - Tema.px(12), mh, 'rojoOscuro')
        local lado = Tema.px(compacta and 32 or 40)
        Acero.icono(
            iconoDe(p.titulo),
            mxi + (miniatura - Tema.px(12) - lado) / 2,
            myi + (mh - lado) / 2,
            lado,
            'rojoTexto'
        )
        local tx = x + miniatura + Tema.px(8)
        local tw = x + ancho - tx - Tema.px(10)
        g.setFont(titulo)
        Tema.color('textoHud')
        local _, partesTitulo = titulo:getWrap(p.titulo, tw)
        local lineasTitulo = math.min(2, #partesTitulo)
        for l = 1, lineasTitulo do
            local parte = partesTitulo[l]
            if l == 2 and #partesTitulo > 2 then
                parte = Tema.cortar(titulo, table.concat(partesTitulo, ' ', 2), tw)
            end
            g.print(parte, tx, y + Tema.px(6) + (l - 1) * titulo:getHeight())
        end
        g.setFont(detalle)
        Tema.color('textoHudTenue')
        local ty = y + Tema.px(6) + lineasTitulo * titulo:getHeight()
        local anchoBoton = botonSolo and math.max(Tema.px(52), Tema.anchoBoton(botonSolo, true)) or 0
        local espacio = botonSolo and (tw - anchoBoton - Tema.px(6)) or tw
        local lineasDetalle = lineasTitulo == 1 and 2 or 1
        local _, partesDetalle = detalle:getWrap(p.detalle, espacio)
        for l = 1, math.min(lineasDetalle, #partesDetalle) do
            local parte = partesDetalle[l]
            if l == lineasDetalle and #partesDetalle > lineasDetalle then
                parte = Tema.cortar(detalle, table.concat(partesDetalle, ' ', l), espacio)
            end
            g.print(parte, tx, ty + (l - 1) * detalle:getHeight())
        end
        local botonesZona = {}
        if botonSolo then
            local bh = Tema.px(30)
            local bx, by = x + ancho - Tema.px(10) - anchoBoton, y + altoBase - bh - Tema.px(10)
            Tema.boton(botonSolo, bx, by, anchoBoton, bh, true)
            botonesZona[1] = { x = bx, y = by, w = anchoBoton, h = bh, accion = p.accion }
        else
            local bh = Tema.px(36)
            local total = 0
            for _, b in ipairs(lista) do
                b.ancho = math.max(Tema.px(80), Tema.anchoBoton(b, true))
                total = total + b.ancho
            end
            local hueco = Tema.px(6)
            total = total + hueco * (#lista - 1)
            local disponible = ancho - Tema.px(20)
            local sobra = total > disponible and (total - disponible) / #lista or 0
            local bx, by = x + Tema.px(10), y + altoBase
            for _, b in ipairs(lista) do
                local bw = math.floor(b.ancho - sobra)
                Tema.boton(b, bx, by, bw, bh, true)
                botonesZona[#botonesZona + 1] = { x = bx, y = by, w = bw, h = bh, accion = b.accion }
                bx = bx + bw + hueco
            end
        end
        -- Raya del tiempo que le queda.
        Tema.color('rojo')
        g.rectangle(
            'fill',
            x + Tema.px(8),
            y + alto - Tema.px(5),
            math.floor((ancho - Tema.px(16)) * math.max(0, p.queda) / (p.duracion or DURACION)),
            Tema.px(2)
        )
        self.zonas[#self.zonas + 1] = { x = x, y = y, w = ancho, h = alto, indice = k, botones = botonesZona }
        Vida.fin()
        y = y + alto + Tema.px(6)
    end
    self.visibles = math.max(1, dibujadas)
    -- Las que no caben, en una tarjeta que abre las noticias.
    local faltan = #self.cola - dibujadas
    if faltan > 0 then
        local alto = Tema.px(40)
        Acero.nueve(
            'tarjeta_unidad',
            Tema.dentro(mx, my, x, y, ancho, alto) and 'resaltada' or 'normal',
            x,
            y,
            ancho,
            alto
        )
        g.setFont(titulo)
        Tema.color('amarillo')
        local texto = string.format('+%d %s', faltan, faltan == 1 and 'aviso' or 'avisos')
        g.print(texto, x + Tema.px(14), y + (alto - titulo:getHeight()) / 2)
        g.setFont(detalle)
        Tema.color('textoHudTenue')
        g.printf('Ver en noticias', x, y + (alto - detalle:getHeight()) / 2, ancho - Tema.px(14), 'right')
        self.zonas[#self.zonas + 1] = { x = x, y = y, w = ancho, h = alto, mas = true }
    end
end

--- Clic en un pregón: con el izquierdo devuelve 'x' (ir al ataque) o, en los
-- de `avisar`, su acción; con el derecho lo descarta. Devuelve nil si el clic no cayó en ninguno.
function Pregon:pulsar(x, y, boton)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if z.mas then
                return boton == 2 and 'nada' or 'noticias'
            end
            local p = self.cola[z.indice]
            if boton == 2 then
                p.descartado = true
                table.remove(self.cola, z.indice)
                return 'nada'
            end
            if p.botones then
                for _, b in ipairs(z.botones) do
                    if Tema.dentro(x, y, b.x, b.y, b.w, b.h) then
                        table.remove(self.cola, z.indice)
                        p.elegido = b.accion
                        return b.accion
                    end
                end
                return 'nada'
            end
            if p.accion then
                table.remove(self.cola, z.indice)
                return p.accion
            end
            return 'x'
        end
    end
    return nil
end

return Pregon

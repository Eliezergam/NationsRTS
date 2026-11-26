-- Perfil de la nación (diseno/interfaz-militar.md, §5.14): pantalla completa
-- de la familia clara. A la izquierda la tarjeta marino (nivel, escudo,
-- nombre, poder, nivel de la capital y medallas); a la derecha seis placas de
-- datos 2×3 con datos reales de la simulación y una fila de hexágonos.
-- No hay barra de energía: la simulación no tiene esa mecánica (decisión del
-- dueño).
--
-- Solo lee la simulación. `pulsar` devuelve la acción pedida (`cerrar`,
-- `opciones`, `territorio`) y main.lua la aplica.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Clara = require('interfaz.clara')
local Estandartes = require('mundo.estandartes')
local Simulacion = require('mundo.simulacion')

local Perfil = {}
Perfil.__index = Perfil

function Perfil.nuevo()
    local self = setmetatable({}, Perfil)
    self.abierto = false
    self.detalle = nil -- 'info' o 'guerras': lista en lugar de las placas
    self.zonas = {}
    self.ayuda = nil
    self.desplazo = 0
    return self
end

function Perfil:abrir()
    self.abierto = true
    self.detalle = nil
end

function Perfil:cerrar()
    self.abierto = false
    self.detalle = nil
end

--- Estadísticas de partida de la nación (todo sale de la simulación).
local function estadisticas(sim, nid)
    local victorias, derrotas = 0, 0
    for _, l in ipairs(sim:lideresDe(nid)) do
        victorias = victorias + (l.victorias or 0)
        derrotas = derrotas + (l.derrotas or 0)
    end
    local ejercitos = 0
    for _, g in pairs(sim.estado.grupos) do
        if g.nacion == nid and Simulacion.esEjercito(g) then
            ejercitos = ejercitos + 1
        end
    end
    local ciudades = sim:ciudadesDe(nid)
    local poblacion, enFilas = 0, 0
    for _, c in ipairs(ciudades) do
        poblacion = poblacion + (c.poblacion or 0)
        local d = sim:demografiaCiudad(c.id)
        enFilas = enFilas + (d and d.enFilas or 0)
    end
    return {
        victorias = victorias,
        derrotas = derrotas,
        ejercitos = ejercitos,
        instalaciones = #sim:instalacionesDe(nid),
        ciudades = #ciudades,
        poblacion = poblacion,
        enFilas = enFilas,
        celdas = sim:celdasDe(nid),
        guerras = sim:numeroGuerras(nid),
        almacen = sim:almacen(nid),
        nivel = sim:nivelCapital(nid),
    }
end

--- Las guerras de la nación, escritas: «contra X · en tensión · 12 días».
local function textoGuerras(sim, nid)
    local filas = {}
    local fases = { tension = 'en tensión', calma = 'alto el fuego', guerra = 'en guerra' }
    for _, g in ipairs(sim:guerrasDe(nid)) do
        local otro = sim:nacion(g.atacante == nid and g.defensor or g.atacante)
        filas[#filas + 1] = {
            (g.atacante == nid and 'Ataca a ' or 'Ataca a ti: ') .. (otro and otro.nombre or '?'),
            string.format(
                '%s · %d %s',
                fases[g.fase] or g.fase,
                g.dias or 0,
                (g.dias or 0) == 1 and 'día' or 'días'
            ),
        }
    end
    return filas
end

--- Hexágono de nivel de la esquina de la tarjeta: la pieza del kit con el
-- número en el centro.
local function hexagonoNivel(x, y, ancho, nivel)
    local alto = math.floor(ancho * 80 / 72)
    Acero.pieza('hexagono_icono', 'normal', x, y, ancho, alto)
    local fuente = Acero.fuente('cifraGrande', 30)
    local texto = tostring(nivel)
    Acero.textoContorno(
        fuente,
        texto,
        x + (ancho - fuente:getWidth(texto)) / 2,
        y + (alto - fuente:getHeight()) / 2,
        'textoHud'
    )
end

--- Tarjeta de comandante (izquierda). `d` = medidas en píxeles de pantalla.
function Perfil:dibujarTarjeta(sim, nacion, semilla, x, y, w, h, vs)
    local g = love.graphics
    local px = Tema.px
    local stats = self.stats
    Acero.sombra(x, y, w, h)
    Acero.nueve('tarjeta_perfil', 'normal', x, y, w, h)
    local ix, iy, iw = Acero.contenido('tarjeta_perfil', x, y, w, h)
    ix, iy, iw = ix + px(12), iy + px(14), iw - px(24)
    hexagonoNivel(x - px(8), y - px(14), px(60), stats.nivel)
    -- Escudo en el anillo de la chapa y, a su derecha, id y nombre.
    local anillo = px(120)
    local ax, ay = ix + px(12), iy + px(14)
    local hoja = 4
    Estandartes.dibujarEscudo(
        Estandartes.escudoDe(semilla, nacion.id),
        ax + anillo / 2,
        ay + anillo / 2,
        hoja,
        px(70) / (18 * hoja)
    )
    Acero.pieza('chapa_nacion', 'normal', ax, ay, anillo, anillo)
    local tx = ax + anillo + px(20)
    local tw = ix + iw - tx
    local pequena = Acero.fuente('cuerpo', 18)
    g.setFont(pequena)
    Tema.color('tintaTenue')
    local orden = Simulacion.ordenes[nacion.orden]
    g.print(orden and orden.nombre:upper() or 'NACIÓN', tx, ay)
    local campoAlto = px(54)
    local cy = ay + pequena:getHeight() + px(4)
    Acero.nueve('campo', 'normal', tx, cy, tw, campoAlto)
    local nombre = Acero.fuente('titulo', 26)
    g.setFont(nombre)
    Tema.color('tinta')
    g.print(Tema.cortar(nombre, nacion.nombre, tw - px(20)), tx + px(10), cy + (campoAlto - nombre:getHeight()) / 2)
    local sy = cy + campoAlto + px(8)
    Acero.icono('mundo', tx, sy, pequena:getHeight(), 'tintaTenue')
    g.setFont(pequena)
    Tema.color('tintaTenue')
    g.print('Mundo: ' .. tostring(semilla), tx + pequena:getHeight() + px(6), sy)
    -- Rejilla: poder, hueco vacío y nivel de la capital.
    local gx, gy = ix, ay + anillo + px(28 * vs)
    local gw = iw
    local gh = math.max(px(190), y + h - gy - px(158))
    local mitad = math.floor(gw * 0.46)
    Tema.color('papelLinea')
    g.setLineWidth(math.max(1, px(2)))
    g.rectangle('line', gx, gy, gw, gh)
    g.line(gx + mitad, gy, gx + mitad, gy + gh)
    g.line(gx, gy + math.floor(gh * 0.56), gx + mitad, gy + math.floor(gh * 0.56))
    g.setLineWidth(1)
    -- Poder.
    local grande = Acero.fuente('cifraGrande', 54)
    local poder = Tema.numero(self.fuerza)
    g.setFont(grande)
    Tema.color('poderMarron')
    g.print(Tema.cortar(grande, poder, mitad - px(28)), gx + px(14), gy + px(14))
    g.setFont(Acero.fuente('cuerpo', 26))
    Tema.color('tintaTenue')
    g.print('Poder', gx + px(14), gy + px(14) + grande:getHeight() - px(2))
    Acero.iconoColor('poder', gx + mitad - px(70), gy + px(14), px(56))
    -- Hueco punteado (para un título o insignia, más adelante).
    local rx, ry = gx + px(14), gy + math.floor(gh * 0.56) + px(10)
    local rw, rh = mitad - px(28), math.floor(gh * 0.44) - px(20)
    Acero.nueve('ranura_vacia', 'normal', rx, ry, rw, rh)
    Acero.icono('mas', rx + (rw - px(32)) / 2, ry + (rh - px(32)) / 2, px(32), 'tintaTenue', 0.6)
    -- Nivel de la capital y lo que da.
    local nx, nw = gx + mitad, gw - mitad
    local nivel = Acero.fuente('cifraGrande', 52)
    local etiqueta = Acero.fuente('cuerpo', 26)
    local texto = 'Nv. ' .. stats.nivel
    local cyy = gy + math.floor(gh / 2) - nivel:getHeight()
    g.setFont(nivel)
    Tema.color('tinta')
    g.print(texto, nx + (nw - nivel:getWidth(texto)) / 2, cyy)
    g.setFont(etiqueta)
    Tema.color('tintaTenue')
    local capital = 'Capital'
    g.print(capital, nx + (nw - etiqueta:getWidth(capital)) / 2, cyy + nivel:getHeight() - px(2))
    local almacen = 'Almacén ' .. Tema.numero(stats.almacen)
    g.print(almacen, nx + (nw - etiqueta:getWidth(almacen)) / 2, cyy + nivel:getHeight() + etiqueta:getHeight())
    -- Medallas: cinco huecos vacíos (aún no hay logros en la simulación).
    local my = gy + gh + px(54)
    local r = px(36)
    local paso = math.floor(iw / 5)
    for k = 0, 4 do
        local cx = ix + paso * k + paso / 2
        Clara.hexagonoPlano(cx, my, r, 'papelBoton', 'papelLinea')
        Acero.icono('mas', cx - px(14), my - px(14), px(28), 'papelLinea')
    end
    local fuente = Acero.fuente('cuerpo', 19)
    g.setFont(fuente)
    Tema.color('tintaTenue')
    g.printf('Medallas: ninguna todavía', ix, my + r + px(14), iw, 'right')
end

--- Una lista de dos columnas («etiqueta … valor») en un panel claro.
local function lista(x, y, w, h, titulo, filas)
    local g = love.graphics
    local px = Tema.px
    local cx, cy, cw, ch = Acero.panelClaro(x, y, w, h)
    local fuenteTitulo = Acero.fuente('titulo', 26)
    g.setFont(fuenteTitulo)
    Tema.color('tinta')
    g.print(titulo, cx + px(8), cy + px(2))
    local fila = px(38)
    local yy = cy + fuenteTitulo:getHeight() + px(10)
    local fuente = Acero.fuente('cuerpo', 21)
    if #filas == 0 then
        g.setFont(fuente)
        Tema.color('tintaTenue')
        g.print('Nada que contar todavía.', cx + px(8), yy)
        return
    end
    for _, f in ipairs(filas) do
        if yy + fila > cy + ch then
            break
        end
        Tema.color('papelLinea')
        g.rectangle('fill', cx + px(4), yy + fila - 1, cw - px(8), 1)
        g.setFont(fuente)
        Tema.color('tintaTenue')
        g.print(Tema.cortar(fuente, f[1], cw * 0.6), cx + px(8), yy + (fila - fuente:getHeight()) / 2)
        Tema.color('tinta')
        local valor = Tema.cortar(fuente, f[2], cw * 0.5)
        g.print(valor, cx + cw - px(8) - fuente:getWidth(valor), yy + (fila - fuente:getHeight()) / 2)
        yy = yy + fila
    end
end

--- Dibuja el perfil. `ctx` = { sim, semilla, nacion (id o nil) }.
function Perfil:dibujar(ctx)
    if not self.abierto then
        return
    end
    local g = love.graphics
    local px = Tema.px
    local sim = ctx.sim
    local nacion = ctx.nacion and sim:nacion(ctx.nacion)
    self.zonas = {}
    self.ayuda = nil
    local w, h = g.getDimensions()
    Clara.fondo()
    local recursos = nacion and Clara.recursosDe(sim, nacion.id) or {}
    local logo = Clara.cabecera('Perfil de la nación', recursos)
    self.zonas[#self.zonas + 1] = { x = logo.x, y = logo.y, w = logo.w, h = logo.h, accion = 'cerrar' }
    if not nacion then
        local fuente = Acero.fuente('titulo', 30)
        Clara.textoSombra(fuente, 'Sin nación: no hay perfil que mostrar.', px(168), px(160))
        return
    end
    -- Números que cuestan: se piden al abrir y cada medio segundo.
    local ahora = love.timer.getTime()
    if not self.tiempo or ahora - self.tiempo > 0.5 or self.nid ~= nacion.id then
        self.tiempo, self.nid = ahora, nacion.id
        self.stats = estadisticas(sim, nacion.id)
        self.fuerza = sim:fuerza(nacion.id)
        self.guerras = textoGuerras(sim, nacion.id)
        self.capital = sim:ciudad(nacion.capital)
    end
    local stats = self.stats
    -- Medidas: en unidades de diseño (`w / e`), para que a 720p no se salgan.
    local e = Tema.escala()
    local dw, dh = w / e, h / e
    local margen = math.max(64, math.floor(dw * 0.0875))
    local cardW = dw >= 1800 and 560 or 500
    local cardH = math.min(800, dh - 150)
    local vs = cardH / 640 -- las filas crecen con la pantalla (hasta 1,25)
    local top = 110
    self:dibujarTarjeta(sim, nacion, ctx.semilla, px(margen), px(top + 20), px(cardW), px(cardH - 20), vs)
    -- Derecha.
    local derechaX = margen + cardW + (dw >= 1800 and 96 or 56)
    local derechaW = math.min(860, dw - derechaX - margen)
    derechaX = dw - margen - derechaW
    local placaW, placaH, hueco = math.floor((derechaW - 12) / 2), math.floor(128 * vs), 12
    local ry = top + 30
    if self.detalle == 'info' then
        lista(px(derechaX), px(ry), px(derechaW), px(placaH * 3 + hueco * 2), 'Más información', {
            {
                'Día de la partida',
                string.format(
                    '%s · año %s',
                    Tema.numero(sim.estado.dia),
                    Tema.numero(Simulacion.anioDelJuego(math.max(1, sim.estado.dia)))
                ),
            },
            { 'Victorias de tus generales', Tema.numero(stats.victorias) },
            { 'Derrotas de tus generales', Tema.numero(stats.derrotas) },
            { 'Ejércitos', Tema.numero(stats.ejercitos) },
            { 'Instalaciones', Tema.numero(stats.instalaciones) },
            { 'Población total', Tema.numero(stats.poblacion) },
            { 'Soldados en filas', Tema.numero(stats.enFilas) },
            { 'Territorio (celdas)', Tema.numero(stats.celdas) },
        })
    elseif self.detalle == 'guerras' then
        lista(px(derechaX), px(ry), px(derechaW), px(placaH * 3 + hueco * 2), 'Guerras', self.guerras)
    else
        local capital = self.capital
        local datos = {
            { 'Nv. ' .. stats.nivel, 'Nv. de la capital', 'nivel' },
            { 'Ninguna', 'Alianza', 'alianza' },
            { Tema.numero(stats.celdas), 'Territorio (celdas)', 'mundo' },
            { Tema.numero(stats.ciudades), stats.ciudades == 1 and 'Ciudad' or 'Ciudades', 'unidades' },
            { capital and capital.nombre or '—', 'Capital', 'bandera' },
            { Tema.numero(stats.guerras), stats.guerras == 1 and 'Guerra' or 'Guerras', 'atacar' },
        }
        local mx, my = love.mouse.getPosition()
        for k, d in ipairs(datos) do
            local col, fila = (k - 1) % 2, math.floor((k - 1) / 2)
            local x = px(derechaX + col * (placaW + hueco))
            local y = px(ry + fila * (placaH + hueco))
            Clara.placaDato(x, y, px(placaW), px(placaH), d[1], d[2], d[3])
            if Tema.dentro(mx, my, x, y, px(placaW), px(placaH)) then
                if k == 1 then
                    self.ayuda = string.format(
                        'Victorias %d · derrotas %d · ejércitos %d · instalaciones %d · día %d',
                        stats.victorias,
                        stats.derrotas,
                        stats.ejercitos,
                        stats.instalaciones,
                        sim.estado.dia
                    )
                elseif k == 6 and #self.guerras > 0 then
                    local partes = {}
                    for _, f in ipairs(self.guerras) do
                        partes[#partes + 1] = f[1] .. ' (' .. f[2] .. ')'
                    end
                    self.ayuda = table.concat(partes, ' · ')
                end
            end
        end
    end
    -- Fila de hexágonos.
    local botones = {
        { 'info', 'Más info', 'noticias', 'Estadísticas de la partida' },
        { 'guerras', 'Guerras', 'atacar', 'Tus guerras abiertas' },
        { 'territorio', 'Territorio', 'mundo', 'Cierra el perfil y muestra los territorios (T)' },
        { 'opciones', 'Opciones', 'ajustes', 'Opciones del juego' },
    }
    local hexW = 112
    local separa = 40
    local total = #botones * hexW + (#botones - 1) * separa
    local hx = derechaX + (derechaW - total) / 2
    local hy = ry + placaH * 3 + hueco * 2 + 36 * vs
    for k, b in ipairs(botones) do
        local x, y = px(hx + (k - 1) * (hexW + separa)), px(hy)
        local encima, alto = Acero.hexagono(x, y, px(hexW), {
            icono = b[3],
            etiqueta = b[2],
            activo = self.detalle == b[1],
        })
        if encima then
            self.ayuda = b[4]
        end
        self.zonas[#self.zonas + 1] = { x = x, y = y, w = px(hexW), h = alto, accion = b[1] }
    end
end

function Perfil:dibujarAyuda()
    if self.abierto and self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- Clic: devuelve la acción pedida (`cerrar`, `opciones`, `territorio`) o nil.
-- `info` y `guerras` los resuelve el propio perfil.
function Perfil:pulsar(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if z.accion == 'info' or z.accion == 'guerras' then
                self.detalle = self.detalle ~= z.accion and z.accion or nil
                return 'nada'
            end
            return z.accion
        end
    end
    return 'nada'
end

return Perfil

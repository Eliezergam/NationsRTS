-- Lo que se dibuja encima de la batalla 3D para los robots que se enfrentan
-- (batalla/robots/especializaciones/asalto.lua): chispas y
-- fogonazos; el nombre y lo que hace cada uno sobre su cabeza; y un mapa
-- pequeño con las tres rutas de cada uno (la elegida, gruesa), sus
-- coberturas, dónde están y, si se ven, la línea entre ellos.

local Mundo = require('batalla.robots.mundo')

local VistaRobots = {}

local COLOR = { azul = { 0.35, 0.7, 1 }, rojo = { 1, 0.35, 0.3 } }
local ESTADO = {
    avanzar = 'corre', parado = 'a cubierto, vigila', combate = '¡dispara corriendo!',
    reposicionar = 'salta a otra cobertura', llegado = 'llegó', esperar = '',
}

local proy = {}

local function pantalla(control, x, y, z)
    -- Metros del robot (y al norte) a píxeles del juego (y al sur).
    local p = control:proyectar(x * 10, -y * 10, z * 10, proy)
    if p and p.delante then
        return p.x, p.y, p.visible
    end
end

local function dibujarTiros(control, d)
    local g = love.graphics
    -- Sin trazadoras (el dueño, 18-nov: la línea se quedaba donde estaba la
    -- boca al disparar y, corriendo, parecía salir de otro sitio): solo el
    -- fogonazo en la boca y las chispas donde pega.
    for _, c in ipairs(d.chispas) do
        local sx, sy = pantalla(control, c[1], c[2], c[3])
        if sx then
            local a = 1 - c.t / 0.3
            g.setColor(1, c.robot and 0.45 or 0.75, 0.2, a)
            g.circle('fill', sx, sy, (c.robot and 5 or 3) * (0.5 + a))
        end
    end
end

local function dibujarFogonazo(control, r, d)
    if (d.fogonazo or 0) <= 0 or not r.piezas.canones then
        return
    end
    local c = r:getPieza('canones')
    local x, y, z = c:getPunto(0.36, 0, 0)
    local sx, sy = pantalla(control, x, y, z)
    if sx then
        local g = love.graphics
        g.setColor(1, 0.8, 0.4, 0.85)
        g.circle('fill', sx, sy, 5 + 6 * love.math.random())
        g.setColor(1, 1, 0.85, 1)
        g.circle('fill', sx, sy, 2.5)
    end
end

-- Lanzamisiles (lanzador.lua): láser, fogonazo, estela y explosiones.
local LANZADOR = {
    cabeza = nil, armar = 'arma el cañón', desarmar = 'vuelve a ser cabeza', armado = 'cañón listo',
    marcar = 'marca con el láser', disparar = '¡dispara!',
}

-- Textura de una bocanada: blanca, opaca en el centro y transparente en el
-- borde, con algo de irregularidad (no un círculo perfecto).
local mancha

local function manchaHumo()
    if mancha then
        return mancha
    end
    local n = 96
    local datos = love.image.newImageData(n, n)
    local semilla = love.math.random() * 100
    datos:mapPixel(function(x, y)
        local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
        local d = math.sqrt(dx * dx + dy * dy)
        local ang = math.atan2(dy, dx)
        local borde = 0.82 + 0.12 * love.math.noise(math.cos(ang) * 1.5 + semilla, math.sin(ang) * 1.5)
        local a = math.max(0, 1 - d / borde)
        a = a * a * (3 - 2 * a)
        a = a * (0.75 + 0.25 * love.math.noise(dx * 3 + semilla, dy * 3))
        return 1, 1, 1, a
    end)
    mancha = love.graphics.newImage(datos)
    mancha:setFilter('linear', 'linear')
    return mancha
end

local function dibujarLanzador(control, r)
    local d = r.datos.lanzador
    if not d then
        return
    end
    local g = love.graphics
    if d.laser then
        local l = d.laser
        local ax, ay = pantalla(control, l[1], l[2], l[3])
        local bx, by, bv = pantalla(control, l[4], l[5], l[6])
        if ax and bx then
            g.setLineWidth(3)
            g.setColor(1, 0.05, 0.03, 0.35)
            g.line(ax, ay, bx, by)
            g.setLineWidth(1)
            g.setColor(1, 0.3, 0.25, 0.95)
            g.line(ax, ay, bx, by)
            if bv then
                g.setColor(1, 0.1, 0.05, 0.9)
                g.circle('fill', bx, by, 3.5 + love.math.random())
            end
        end
    end
    -- Píxeles por metro donde está un punto.
    local function porMetro(x, y, z)
        local sx, sy = pantalla(control, x, y, z)
        local _, uy = pantalla(control, x, y, z + 1)
        if sx and uy then
            return sx, sy, math.max(0.5, math.abs(sy - uy))
        end
    end
    -- Bocanada de humo: una mancha suave (se difumina hacia el borde).
    local mancha = manchaHumo()
    local mw = mancha:getWidth()
    local function bocanada(sx, sy, r, gris, a, giro)
        g.setColor(gris, gris, gris * 0.97, a)
        g.draw(mancha, sx, sy, giro or 0, 2 * r / mw, 2 * r / mw, mw / 2, mw / 2)
    end
    local estelas = {}
    for _, m in ipairs(d.misiles) do
        estelas[#estelas + 1] = m.estela
    end
    for _, e in ipairs(d.estelas or {}) do
        estelas[#estelas + 1] = e
    end
    local vida = 1.8
    for _, estela in ipairs(estelas) do
        for n = #estela, 1, -1 do
            local e = estela[n]
            local sx, sy, pm = porMetro(e[1], e[2], e[3] + e.t * 0.35)
            if sx then
                local f = e.t / vida
                bocanada(sx, sy, pm * (0.05 + 0.4 * math.sqrt(f)), e.gris or 0.8, 0.75 * (1 - f) ^ 1.5, n * 0.7)
            end
        end
    end
    if (d.fogonazo or 0) > 0 and d.canon then
        local c = r:getPieza('cabeza')
        local b = d.canon.boca
        local sx, sy, pm = porMetro(c:getPunto(b[1] + 0.15, b[2], b[3]))
        if sx then
            bocanada(sx, sy, pm * 0.35, 0.75, 0.6)
        end
    end
    for _, e in ipairs(d.explosiones) do
        for _, b in ipairs(e.humo) do
            local t = e.t - b.retraso
            if t > 0 then
                local sx, sy, pm = porMetro(b.x, b.y, b.z)
                if sx then
                    local f = t / 4
                    local entra = math.min(1, t / 0.12)
                    local a = entra * (1 - f) ^ 1.3 * 0.85
                    bocanada(sx, sy, pm * 1.3 * (b.r + b.crece * math.sqrt(t) * 1.4), b.gris + f * 0.35, a, b.vx + t * 0.3)
                end
            end
        end
    end
end

local function dibujarEtiqueta(control, r, d, fuente)
    local x, y, z = r:getPieza('cabeza'):getPunto(0, 0, 0.45)
    local sx, sy, visible = pantalla(control, x, y, z)
    if not sx or not visible then
        return
    end
    local g = love.graphics
    local color = COLOR[d.bando] or { 1, 1, 1 }
    local lan = r.datos.lanzador
    local texto = d.nombre .. '  ' .. ((lan and LANZADOR[lan.estado]) or ESTADO[d.estado] or d.estado)
    if d.recibidas and d.recibidas > 0 then
        texto = texto .. '  (le han dado ' .. d.recibidas .. ')'
    end
    local w = fuente:getWidth(texto) + 12
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', sx - w / 2, sy - 26, w, 20, 4, 4)
    g.setColor(color[1], color[2], color[3], 1)
    g.print(texto, sx - w / 2 + 6, sy - 24)
end

--- Lo que sabe un robot con cerebro (cerebro.lua): una marca en cada pista
-- de su memoria (llena si lo ve ahora, hueca y cada vez más tenue si solo
-- lo recuerda), la línea de la mirada a quien ve, y su panel arriba.
local function dibujarCerebro(control, r, fuente)
    local c = r.datos.cerebro
    if not c then
        return
    end
    local g = love.graphics
    local ox, oy, oz = r:getPieza('cabeza'):getPunto(0.08, 0, 0.12)
    local hx, hy = pantalla(control, ox, oy, oz)
    for _, p in ipairs(c.memoria) do
        local sx, sy = pantalla(control, p.x, p.y, p.z)
        if sx then
            local s = p.seguridad or 1
            if p.ahora then
                -- (Sin línea del ojo al enemigo: el dueño, 18-nov, «se ve
                -- rara»; basta la marca encima.)
                g.setColor(1, 0.25, 0.15, 0.95)
                g.circle('fill', sx, sy, 7)
            else
                g.setColor(1, 0.85, 0.3, 0.25 + 0.7 * s)
                g.setLineWidth(2)
                g.circle('line', sx, sy, 9)
            end
            local texto = p.ahora and string.format('%s  lo ve', p.nombre)
                or string.format('%s  recuerda %d%%', p.nombre, math.floor(s * 100 + 0.5))
            local w = fuente:getWidth(texto) + 10
            g.setColor(0, 0, 0, 0.55)
            g.rectangle('fill', sx - w / 2, sy + 13, w, 18, 3, 3)
            g.setColor(1, 1, 1, 0.4 + 0.6 * s)
            g.print(texto, sx - w / 2 + 5, sy + 14)
        end
    end
    -- Lo que sabe de otras batallas: un rombo azul en cada sospecha.
    for _, s in ipairs(c.sospechas or {}) do
        local sx, sy = pantalla(control, s.x, s.y, Mundo.altura(s.x, s.y) + 1)
        if sx then
            local mirando = c.ojeando == s
            g.setColor(0.35, 0.7, 1, mirando and 1 or 0.6)
            g.setLineWidth(mirando and 3 or 2)
            g.polygon('line', sx, sy - 9, sx + 9, sy, sx, sy + 9, sx - 9, sy)
            local texto = string.format('antes: %s x%d', s.tipo, s.veces)
            local w = fuente:getWidth(texto) + 10
            g.setColor(0, 0, 0, 0.5)
            g.rectangle('fill', sx - w / 2, sy - 30, w, 18, 3, 3)
            g.setColor(0.6, 0.85, 1, 1)
            g.print(texto, sx - w / 2 + 5, sy - 29)
        end
    end
    -- Panel.
    local lineas = { 'CEREBRO de ' .. (r.datos.asalto.nombre or '?') .. string.format('  (batalla %d)', c.batalla or 0) }
    if c.saber then
        lineas[#lineas + 1] = 'ramas consultadas: ' .. table.concat(c.saber.leidas, ', ')
        lineas[#lineas + 1] = string.format('SABE DE ANTES  %d sitios con enemigos%s', #(c.sospechas or {}), c.ojeando and '   (echando una ojeada)' or '')
    end
    if #c.memoria == 0 then
        lineas[#lineas + 1] = 'no sabe de ningún enemigo'
    end
    for _, p in ipairs(c.memoria) do
        if p.ahora then
            lineas[#lineas + 1] = string.format('VE        %s a %.0f m', p.nombre, p.distancia or 0)
        else
            lineas[#lineas + 1] = string.format('RECUERDA  %s: visto hace %.0f s, seguro %d%%', p.nombre, p.hace or 0, math.floor((p.seguridad or 1) * 100 + 0.5))
        end
    end
    local W = g.getWidth()
    local ancho = 0
    for _, l in ipairs(lineas) do
        ancho = math.max(ancho, fuente:getWidth(l))
    end
    -- Arriba a la derecha (a la izquierda está la información de la batalla).
    local x0, y0 = W - ancho - 36, 16
    g.setColor(0, 0, 0, 0.6)
    g.rectangle('fill', x0, y0, ancho + 20, #lineas * 18 + 10, 5, 5)
    for k, l in ipairs(lineas) do
        g.setColor(k == 1 and 0.6 or 1, k == 1 and 0.9 or 1, 1, 1)
        g.print(l, x0 + 10, y0 + 5 + (k - 1) * 18)
    end
end

--- Los cuerpos de la física (batalla/robots/fisica.lua) que aún no tienen
-- modelo: sus aristas, en naranja.
local matrizFisica = {}
local ESQUINAS = { { -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 }, { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 } }
local ARISTAS = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
local function dibujarFisica(control, fisica)
    local g = love.graphics
    g.setLineWidth(2)
    g.setColor(1, 0.55, 0.1, 0.95)
    local px, py = {}, {}
    for _, c in ipairs(fisica.lista) do
        if c.forma == 'caja' then
            local m = fisica:matriz(c.id, matrizFisica)
            local bien = true
            for k, e in ipairs(ESQUINAS) do
                local x, y, z = e[1] * c.hx, e[2] * c.hy, e[3] * c.hz
                local sx, sy = pantalla(control, m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8], m[9] * x + m[10] * y + m[11] * z + m[12])
                if not sx then
                    bien = false
                    break
                end
                px[k], py[k] = sx, sy
            end
            if bien then
                for _, a in ipairs(ARISTAS) do
                    g.line(px[a[1]], py[a[1]], px[a[2]], py[a[2]])
                end
            end
        end
    end
end

-- Mapa pequeño de las rutas.
local function dibujarMapa(robots, fuente)
    local g = love.graphics
    local W, H = g.getDimensions()
    local lado = math.floor(math.min(W, H) * 0.34)
    local x0, y0 = W - lado - 16, 16
    -- Caja que abarca las rutas de todos.
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        for _, ruta in ipairs(d.rutas or {}) do
            for _, p in ipairs(ruta.puntos) do
                minx, maxx = math.min(minx, p.x), math.max(maxx, p.x)
                miny, maxy = math.min(miny, p.y), math.max(maxy, p.y)
            end
        end
    end
    -- Corriendo por el campo: el mapa abarca todo su círculo.
    local rec = robots[1].datos.asalto.recorrer
    if rec then
        minx, maxx = rec.cx - rec.radio, rec.cx + rec.radio
        miny, maxy = rec.cy - rec.radio, rec.cy + rec.radio
    end
    if minx == math.huge then
        return
    end
    local cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    local escala = (lado - 24) / math.max(maxx - minx, maxy - miny, 1)
    local function aMapa(x, y)
        -- Norte arriba (el robot tiene y al norte).
        return x0 + lado / 2 + (x - cx) * escala, y0 + lado / 2 - (y - cy) * escala
    end
    g.setColor(0.04, 0.06, 0.05, 0.72)
    g.rectangle('fill', x0, y0, lado, lado + 22, 6, 6)
    if rec then
        local mx, my = aMapa(rec.cx, rec.cy)
        g.setColor(1, 1, 1, 0.2)
        g.setLineWidth(1)
        g.circle('line', mx, my, rec.radio * escala)
        -- Por dónde ha ido cada uno.
        for _, r in ipairs(robots) do
            local d = r.datos.asalto
            local color = COLOR[d.bando] or { 1, 1, 1 }
            local linea = {}
            for _, p in ipairs(d.rastro or {}) do
                local ax, ay = aMapa(p[1], p[2])
                linea[#linea + 1] = ax
                linea[#linea + 1] = ay
            end
            if #linea >= 4 then
                g.setColor(color[1], color[2], color[3], 0.35)
                g.line(linea)
            end
        end
    end
    -- Troncos y rocas de la zona (las coberturas).
    local d0 = robots[1].datos.asalto
    local R = d0.rejilla
    if R and not rec then
        g.setColor(0.35, 0.55, 0.3, 0.9)
        local vistos = {}
        for _, info in pairs(R.c) do
            local t = info.tronco
            if t and not vistos[t] then
                vistos[t] = true
                local mx, my = aMapa(t.x, t.y)
                g.circle('fill', mx, my, t.roca and 2 or 1.6)
            end
        end
    end
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        local color = COLOR[d.bando] or { 1, 1, 1 }
        for _, ruta in ipairs(d.rutas or {}) do
            local elegida = ruta == d.ruta
            g.setLineWidth(elegida and 3 or 1.2)
            g.setColor(color[1], color[2], color[3], elegida and 0.95 or 0.4)
            local linea = {}
            for _, p in ipairs(ruta.puntos) do
                local mx, my = aMapa(p.x, p.y)
                linea[#linea + 1] = mx
                linea[#linea + 1] = my
            end
            if #linea >= 4 then
                g.line(linea)
            end
            if elegida then
                for _, p in ipairs(ruta.puntos) do
                    if p.parada then
                        local mx, my = aMapa(p.x, p.y)
                        g.circle('line', mx, my, 3)
                    end
                end
            end
        end
    end
    -- Línea de vista en contacto.
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        if d.estado == 'combate' and d.enemigo then
            local ax, ay = aMapa(r.x, r.y)
            local bx, by = aMapa(d.enemigo.x, d.enemigo.y)
            g.setLineWidth(1)
            g.setColor(1, 0.9, 0.3, 0.8)
            g.line(ax, ay, bx, by)
        end
    end
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        local color = COLOR[d.bando] or { 1, 1, 1 }
        local mx, my = aMapa(r.x, r.y)
        g.setColor(0, 0, 0, 1)
        g.circle('fill', mx, my, 6)
        g.setColor(color[1], color[2], color[3], 1)
        g.circle('fill', mx, my, 4.5)
        g.line(mx, my, mx + math.cos(r.rumbo) * 10, my - math.sin(r.rumbo) * 10)
    end
    g.setColor(0.85, 0.9, 0.85, 1)
    local textos = {}
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        local lan = r.datos.lanzador
        if lan then
            textos[#textos + 1] = string.format('%s: %d disparos, %d le dieron', d.nombre, lan.disparados, lan.aciertos)
        elseif d.recorrer then
            textos[#textos + 1] = string.format('%s: %d balas, %d le dieron', d.nombre, d.balas or 0, d.aciertos or 0)
        else
            textos[#textos + 1] = string.format('%s por la %s', d.nombre, d.ruta and d.ruta.nombre or '?')
        end
    end
    g.print(table.concat(textos, '   ·   '), x0 + 8, y0 + lado + 3)
end

function VistaRobots.dibujar(escena)
    local robots = escena.robotsAsalto
    if not robots then
        return
    end
    local g = love.graphics
    g.push('all')
    local fuente = g.getFont()
    for _, r in ipairs(robots) do
        local d = r.datos.asalto
        dibujarTiros(escena.control, d)
        dibujarFogonazo(escena.control, r, d)
        dibujarLanzador(escena.control, r)
    end
    for _, r in ipairs(robots) do
        dibujarEtiqueta(escena.control, r, r.datos.asalto, fuente)
    end
    for _, r in ipairs(robots) do
        dibujarCerebro(escena.control, r, fuente)
    end
    if escena.fisicaJolt and os.getenv('BATALLA_FISICA_CAJAS') then
        dibujarFisica(escena.control, escena.fisicaJolt)
    end
    dibujarMapa(robots, fuente)
    g.pop()
end

return VistaRobots

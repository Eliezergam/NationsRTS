-- Programa «Navegador» de Vexar (el dueño, 26-nov): abre las páginas web de
-- la red del juego y las propias. Las páginas son archivos `.vex` escritos en
-- Lua (almacen/pc/web/pagina.lua); la maqueta las coloca
-- (almacen/pc/web/maqueta.lua) y aquí se pintan.
--
--   barra    atrás, adelante, recargar, inicio, la dirección (clic para
--            escribir otra; Intro va) y «Editar» en las páginas propias
--   página   clic en un enlace lo abre, clic en un botón lo pulsa; la rueda
--            y las flechas la desplazan; F5 recarga
--
-- Direcciones: 'noticias.red' (las del juego, en /red/web), 'local/mibase'
-- (las de este puesto, en ~/web) o la ruta de un archivo `.vex`.

local utf8 = require('utf8')
local Dibujo = require('almacen.pc.dibujo')
local Pagina = require('almacen.pc.web.pagina')
local Maqueta = require('almacen.pc.web.maqueta')

local Navegador = {}

Navegador.titulo = 'Navegador'
Navegador.orden = 8
Navegador.ancho, Navegador.alto = 1000, 620
Navegador.inicio = '/red/web/inicio.vex'
Navegador.rehacer = 0.1 -- s entre dos vueltas de la página
Navegador.anchoMaximo = 900 -- px del texto de la página como mucho

local ALTO_BARRA = 50
local BOTON = 32
local MARGEN = 32

-- Lo que no se guarda (la página ya hecha), por estado de ventana.
local vivas = setmetatable({}, { __mode = 'k' })

local function viva(estado)
    local v = vivas[estado]
    if not v then
        v = { pulsados = {}, zonas = {}, campos = {} }
        vivas[estado] = v
    end
    return v
end

local function rutaActual(estado)
    return estado.historial[estado.posicion] or Navegador.inicio
end

local EJEMPLO = {
    '-- Tu página: un archivo .vex escrito en Lua. Ábrela en el navegador',
    '-- como «local/mibase». Las funciones están en la página de ayuda.red.',
    'nombre(\'Mi base\')',
    '',
    'titulo(\'Mi base\')',
    'texto(\'Página del puesto. Se rehace sola: los datos están siempre al día.\')',
    '',
    'titulo(\'Polvorín\', 2)',
    'texto(\'Misiles: **\' .. partida.misiles .. \'** de \' .. partida.capacidad)',
    '',
    'titulo(\'Recursos\', 2)',
    'local filas = { { \'Recurso\', \'Cantidad\' } }',
    'for _, r in ipairs(partida.recursos) do',
    '    filas[#filas + 1] = { r.nombre, miles(r.cantidad) }',
    'end',
    'tabla(filas)',
    '',
    'separador()',
    'enlace(\'Volver al inicio\', \'inicio.red\')',
}

--- La carpeta ~/web con una página de ejemplo (si aún no la tiene).
local function prepararCarpeta(ordenador)
    local fs = ordenador and ordenador.archivos
    if not fs or fs:buscar('/home/operador/web') then
        return
    end
    fs:crear('/home/operador/web', true)
    local nodo = fs:crear('/home/operador/web/mibase.vex')
    if nodo then
        nodo.contenido = {}
        for k, l in ipairs(EJEMPLO) do
            nodo.contenido[k] = l
        end
    end
end

function Navegador.nuevo(ordenador, opciones)
    prepararCarpeta(ordenador)
    local ruta = opciones and opciones.archivo or Navegador.inicio
    return { historial = { ruta }, posicion = 1, desplazar = 0, editando = false, escrito = '' }
end

function Navegador.tituloDe(estado)
    local v = vivas[estado]
    return ((v and v.nombre) or Pagina.direccion(rutaActual(estado))) .. ' — Navegador'
end

local function ir(estado, ruta)
    if not ruta then
        return
    end
    for k = #estado.historial, estado.posicion + 1, -1 do
        estado.historial[k] = nil
    end
    estado.historial[#estado.historial + 1] = ruta
    estado.posicion = #estado.historial
    estado.desplazar = 0
    estado.editando = false
    vivas[estado] = nil
end

local function moverHistorial(estado, paso)
    local nueva = estado.posicion + paso
    if estado.historial[nueva] then
        estado.posicion = nueva
        estado.desplazar = 0
        vivas[estado] = nil
    end
end

-- La página de error del navegador (sin pasar por Lua).
local function bloquesError(titulo, detalle)
    return {
        { tipo = 'titulo', nivel = 1, trozos = { { texto = titulo } } },
        { tipo = 'parrafo', trozos = { { texto = detalle, color = Maqueta.colores.gris } } },
        { tipo = 'parrafo', trozos = { { texto = 'Volver al inicio', enlace = 'inicio.red' } } },
    }
end

--- Ejecuta la página otra vez y la coloca a `ancho` px.
local function rehacer(estado, ctx, v, ancho)
    local ruta = rutaActual(estado)
    local archivo, parametro = Pagina.partes(ruta)
    local fs = ctx.ordenador.archivos
    local nodo = fs:buscar(archivo)
    local bloques, nombre, fallo
    if not nodo or nodo.carpeta then
        bloques = bloquesError('No se encuentra la página', Pagina.direccion(ruta) .. ' no existe en esta red.')
    else
        local lineas = nodo.leer and nodo.leer(ctx) or nodo.contenido or {}
        v.memoria = v.memoria or {}
        bloques, nombre, fallo = Pagina.ejecutar(table.concat(lineas, '\n'), archivo, ctx, v.pulsados, parametro, v.memoria, v.campos)
        if fallo then
            table.insert(bloques, 1, {
                tipo = 'nota',
                trozos = {
                    { texto = 'Error en la página: ', negrita = true, color = Maqueta.colores.rojo },
                    { texto = fallo },
                },
            })
        end
    end
    v.pulsados = {}
    v.nombre = nombre
    v.elementos, v.alto = Maqueta.colocar(bloques, ancho)
    v.ancho = ancho
    v.reloj = ctx.reloj or 0
end

-- Pinta las líneas de un elemento a partir de (x0, y).
local function pintarLineas(lineas, x0, y, v, raton)
    local g = love.graphics
    for _, l in ipairs(lineas) do
        for k, p in ipairs(l.piezas) do
            g.setFont(p.letra)
            local px, py = x0 + p.x, y
            local alto = p.letra:getHeight()
            local encima = p.enlace and raton and raton.x >= px and raton.x < px + p.ancho and raton.y >= py and raton.y < py + l.alto
            g.setColor(encima and { 0.6, 0.85, 1 } or p.color)
            g.print(p.texto, px, py)
            if p.enlace then
                -- Subrayado seguido entre las palabras del mismo enlace.
                local siguiente = l.piezas[k + 1]
                local w = (siguiente and siguiente.enlace == p.enlace) and p.ancho or p.letra:getWidth((p.texto:gsub('%s+$', '')))
                g.rectangle('fill', px, py + alto - 2, w, encima and 2 or 1)
                v.zonas[#v.zonas + 1] = { px, py, p.ancho, l.alto, enlace = p.enlace }
            end
        end
        y = y + l.alto
    end
end

-- Iconos de los contadores de una publicación, de `s` px.
local function iconoContador(cual, x, y, s)
    local g = love.graphics
    g.setLineWidth(1.6)
    if cual == 'respuestas' then
        g.rectangle('line', x + 1, y + 2, s - 2, s * 0.62, 4)
        g.polygon('line', x + s * 0.25, y + 2 + s * 0.62, x + s * 0.25, y + s, x + s * 0.5, y + 2 + s * 0.62)
    elseif cual == 'reenvios' then
        g.line(x + 2, y + s * 0.6, x + 2, y + s * 0.2, x + s * 0.7, y + s * 0.2)
        g.line(x + s * 0.55, y + 1, x + s * 0.72, y + s * 0.2, x + s * 0.55, y + s * 0.38)
        g.line(x + s - 2, y + s * 0.4, x + s - 2, y + s * 0.8, x + s * 0.3, y + s * 0.8)
        g.line(x + s * 0.45, y + s * 0.62, x + s * 0.28, y + s * 0.8, x + s * 0.45, y + s * 0.98)
    else
        local r = s * 0.26
        g.arc('line', 'open', x + r + 1, y + r + 2, r, math.pi * 0.75, math.pi * 2)
        g.arc('line', 'open', x + s - r - 1, y + r + 2, r, math.pi, math.pi * 2.25)
        g.line(x + 1.6, y + r * 1.6 + 2, x + s / 2, y + s - 1, x + s - 1.6, y + r * 1.6 + 2)
    end
    g.setLineWidth(1)
end

-- La foto redonda: el color con la inicial (oscura sobre colores claros).
local function pintarFoto(color, nombre, cx, cy, diametro)
    local g = love.graphics
    g.setColor(color)
    g.circle('fill', cx, cy, diametro / 2)
    g.setColor(0, 0, 0, 0.25)
    g.circle('line', cx, cy, diametro / 2)
    local inicial = (nombre:match('^@?([%z\1-\127\194-\244][\128-\191]*)') or '?'):upper()
    local letra = Dibujo.letra('titulo', math.floor(diametro * 0.54))
    g.setFont(letra)
    local claridad = 0.299 * color[1] + 0.587 * color[2] + 0.114 * color[3]
    if claridad > 0.62 then
        g.setColor(0.08, 0.09, 0.1, 0.9)
    else
        g.setColor(1, 1, 1, 0.95)
    end
    g.printf(inicial, cx - diametro / 2, cy - letra:getHeight() / 2, diametro, 'center')
end

local function pintarPublicacion(e, x0, y, ancho, v, raton)
    local g = love.graphics
    local b = e.b
    local foto = e.foto
    local encima = raton and raton.y >= y and raton.y < y + e.alto and raton.x >= x0 - 16 and raton.x < x0 + ancho + 16
    if encima and b.enlace then
        g.setColor(1, 1, 1, 0.03)
        g.rectangle('fill', x0 - 16, y, ancho + 32, e.alto)
    end
    g.setColor(0.2, 0.22, 0.24)
    g.rectangle('fill', x0 - 16, y + e.alto - 1, ancho + 32, 1)
    pintarFoto(b.color, b.usuario ~= '' and b.usuario or b.nombre, x0 + foto / 2, y + 14 + foto / 2, foto)
    -- Nombre, @ y día (en un comentario: el usuario).
    local x = x0 + e.x0
    local negrita = Dibujo.letra('paginaNegrita', b.pequena and 18 or 19)
    local normal = Dibujo.letra('pagina', b.pequena and 17 or 18)
    g.setFont(negrita)
    g.setColor(0.96, 0.97, 0.97)
    g.print(b.nombre, x, y + 14)
    local dx = x + negrita:getWidth(b.nombre) + 8
    g.setFont(normal)
    g.setColor(0.52, 0.56, 0.58)
    if b.usuario ~= '' then
        g.print(b.usuario .. (b.dia and (' · día ' .. b.dia) or ''), dx, y + 15)
    elseif b.dia then
        g.print('día ' .. b.dia, dx, y + 15)
    end
    local ty = y + 14 + e.cabecera
    local alto = 0
    for _, l in ipairs(e.lineas) do
        alto = alto + l.alto
    end
    pintarLineas(e.lineas, x, ty, v, raton)
    ty = ty + alto
    -- La publicación citada.
    if e.cita then
        local c = b.cita
        local cy = ty + 6
        local cw = ancho - e.x0
        local sobreCita = raton and raton.x >= x and raton.x < x + cw and raton.y >= cy and raton.y < cy + e.cita.alto
        g.setColor(sobreCita and { 0.13, 0.14, 0.16 } or { 0.1, 0.11, 0.12 })
        g.rectangle('fill', x, cy, cw, e.cita.alto, 10)
        g.setColor(0.25, 0.28, 0.3)
        g.rectangle('line', x + 0.5, cy + 0.5, cw - 1, e.cita.alto - 1, 10)
        pintarFoto(c.color, c.usuario, x + 26, cy + 24, 24)
        local nc = Dibujo.letra('paginaNegrita', 17)
        g.setFont(nc)
        g.setColor(0.96, 0.97, 0.97)
        g.print(c.nombre, x + 44, cy + 12)
        g.setFont(Dibujo.letra('pagina', 16))
        g.setColor(0.52, 0.56, 0.58)
        g.print(c.usuario .. (c.dia and (' · día ' .. c.dia) or ''), x + 52 + nc:getWidth(c.nombre), cy + 13)
        pintarLineas(e.cita.lineas, x + 16, cy + 42, v, raton)
        if c.enlace then
            v.zonas[#v.zonas + 1] = { x, cy, cw, e.cita.alto, enlace = c.enlace }
        end
        ty = ty + e.cita.alto + 10
    end
    -- Contadores (en un comentario, solo los me gusta).
    local fy = y + e.alto - (b.pequena and 32 or 36)
    local colores = { respuestas = { 0.52, 0.56, 0.58 }, reenvios = { 0.36, 0.82, 0.55 }, apoyos = { 0.95, 0.4, 0.55 } }
    local columnas = b.pequena and { { 'apoyos', b.apoyos } } or { { 'respuestas', b.respuestas }, { 'reenvios', b.reenvios }, { 'apoyos', b.apoyos } }
    g.setFont(normal)
    for k, c in ipairs(columnas) do
        local cxk = x + (k - 1) * 150
        g.setColor(c[2] > 0 and colores[c[1]] or { 0.52, 0.56, 0.58 })
        iconoContador(c[1], cxk, fy + 2, 18)
        g.print(c[2] > 0 and Dibujo.miles(c[2]) or '', cxk + 28, fy)
    end
    if b.enlace then
        v.zonas[#v.zonas + 1] = { x0 - 16, y, ancho + 32, e.alto, enlace = b.enlace }
    end
end

local function pintarPagina(estado, v, x0, y0, ancho, raton)
    local g = love.graphics
    v.zonas = {}
    for _, e in ipairs(v.elementos or {}) do
        local y = y0 + e.y
        if e.tipo == 'linea' then
            pintarLineas({ { alto = e.alto, piezas = e.piezas } }, x0 + e.x0, y, v, raton)
        elseif e.tipo == 'separador' then
            g.setColor(0.3, 0.33, 0.35)
            g.rectangle('fill', x0, y, ancho, 1)
        elseif e.tipo == 'nota' then
            g.setColor(0.14, 0.17, 0.2)
            g.rectangle('fill', x0, y, ancho, e.alto, 6)
            g.setColor(0.31, 0.62, 0.95)
            g.rectangle('fill', x0, y, 4, e.alto)
        elseif e.tipo == 'punto' then
            g.setColor(Maqueta.colores.texto)
            g.circle('fill', x0 + e.x, y + e.alto * 0.5, 3.5)
        elseif e.tipo == 'fila' then
            if e.cabecera then
                g.setColor(0.17, 0.2, 0.23)
            elseif e.par then
                g.setColor(0.12, 0.13, 0.145)
            else
                g.setColor(0.1, 0.105, 0.115)
            end
            g.rectangle('fill', x0, y, ancho, e.alto)
            for _, c in ipairs(e.celdas) do
                pintarLineas(c.lineas, x0 + c.x + 10, y + 6, v, raton)
            end
        elseif e.tipo == 'publicacion' then
            pintarPublicacion(e, x0, y, ancho, v, raton)
        elseif e.tipo == 'campo' then
            local activo = v.campoActivo == e.indice
            g.setColor(0.1, 0.11, 0.12)
            g.rectangle('fill', x0 + e.x, y, e.w, e.alto, 6)
            g.setColor(activo and { 0.31, 0.62, 0.95 } or { 0.27, 0.3, 0.32 })
            g.setLineWidth(activo and 2 or 1)
            g.rectangle('line', x0 + e.x, y, e.w, e.alto, 6)
            g.setLineWidth(1)
            g.setFont(e.letra)
            local escrito = v.campos[e.indice] or ''
            local _, partes = e.letra:getWrap(escrito ~= '' and escrito or ' ', e.w - 28)
            if escrito == '' then
                g.setColor(Maqueta.colores.gris)
                g.print(e.pista, x0 + e.x + 14, y + 12)
            else
                g.setColor(Maqueta.colores.texto)
                g.printf(escrito, x0 + e.x + 14, y + 12, e.w - 28)
            end
            if activo and math.floor(love.timer.getTime() * 2) % 2 == 0 then
                local ultima = escrito ~= '' and partes[#partes] or ''
                local cx = x0 + e.x + 14 + e.letra:getWidth(ultima)
                local cy = y + 12 + (math.max(1, #partes) - 1) * e.letra:getHeight()
                g.rectangle('fill', cx + 1, cy + 2, 2, e.letra:getHeight() - 4)
            end
            local cuenta = utf8.len(escrito) or #escrito
            g.setColor(cuenta >= e.limite and Maqueta.colores.rojo or Maqueta.colores.gris)
            local letraCuenta = Dibujo.letra('pagina', 14)
            g.setFont(letraCuenta)
            g.printf(cuenta .. ' / ' .. e.limite, x0 + e.x, y + e.alto - 22, e.w - 12, 'right')
            v.limites = v.limites or {}
            v.limites[e.indice] = e.limite
            v.zonas[#v.zonas + 1] = { x0 + e.x, y, e.w, e.alto, campo = e.indice }
        elseif e.tipo == 'boton' then
            local encima = raton and raton.x >= x0 + e.x and raton.x < x0 + e.x + e.w and raton.y >= y and raton.y < y + e.alto
            g.setColor(encima and { 0.27, 0.75, 0.45 } or { 0.2, 0.6, 0.36 })
            g.rectangle('fill', x0 + e.x, y, e.w, e.alto, 6)
            g.setColor(1, 1, 1)
            g.setFont(e.letra)
            g.printf(e.texto, x0 + e.x, y + (e.alto - e.letra:getHeight()) / 2, e.w, 'center')
            v.zonas[#v.zonas + 1] = { x0 + e.x, y, e.w, e.alto, boton = e.indice }
        end
    end
end

-- Los botones de la barra: { clave, x, letra o dibujo }.
local function botonesBarra(estado)
    return {
        { 'atras', 10, activo = estado.posicion > 1 },
        { 'adelante', 10 + BOTON + 4, activo = estado.historial[estado.posicion + 1] ~= nil },
        { 'recargar', 10 + (BOTON + 4) * 2, activo = true },
        { 'inicio', 10 + (BOTON + 4) * 3, activo = true },
    }
end

local function iconoBarra(clave, x, y, s)
    local g = love.graphics
    local cx, cy = x + s / 2, y + s / 2
    g.setLineWidth(2.5)
    if clave == 'atras' or clave == 'adelante' then
        local d = clave == 'atras' and -1 or 1
        g.line(cx - d * 7, cy - 8, cx + d * 3, cy, cx - d * 7, cy + 8)
    elseif clave == 'recargar' then
        g.arc('line', 'open', cx, cy, 8, -math.pi * 0.35, math.pi * 1.4)
        g.polygon('fill', cx + 4, cy - 12, cx + 11, cy - 6, cx + 3, cy - 3)
    elseif clave == 'inicio' then
        g.polygon('line', cx - 9, cy - 1, cx, cy - 9, cx + 9, cy - 1)
        g.rectangle('line', cx - 6, cy - 1, 12, 9)
    end
    g.setLineWidth(1)
end

local function zonaDireccion(w, editable)
    local x = 10 + (BOTON + 4) * 4 + 8
    return x, 9, w - x - (editable and 112 or 12), BOTON
end

function Navegador.dibujar(estado, ctx, w, h)
    local g = love.graphics
    local v = viva(estado)
    local ruta = rutaActual(estado)
    local editable = require('almacen.pc.archivos').escribible(ruta)
    local ancho = math.min(Navegador.anchoMaximo, w - MARGEN * 2)
    if not v.elementos or v.ancho ~= ancho or next(v.pulsados) or (ctx.reloj or 0) - (v.reloj or 0) >= Navegador.rehacer then
        rehacer(estado, ctx, v, ancho)
    end
    -- La página.
    Dibujo.fondo(w, h, 0.075, 0.08, 0.085)
    local visible = h - ALTO_BARRA
    local maximo = math.max(0, (v.alto or 0) + MARGEN * 2 - visible)
    estado.desplazar = math.max(0, math.min(maximo, estado.desplazar or 0))
    local x0 = math.floor((w - ancho) / 2)
    local y0 = ALTO_BARRA + MARGEN - estado.desplazar
    local raton = v.raton and v.raton.y > ALTO_BARRA and v.raton or nil
    Dibujo.recortado(0, ALTO_BARRA, w, visible, function()
        pintarPagina(estado, v, x0, y0, ancho, raton)
    end)
    if maximo > 0 then
        local alto = math.max(30, visible * visible / (visible + maximo))
        g.setColor(1, 1, 1, 0.18)
        g.rectangle('fill', w - 8, ALTO_BARRA + (visible - alto) * estado.desplazar / maximo, 5, alto, 2)
    end
    -- La barra.
    g.setColor(0.13, 0.14, 0.15)
    g.rectangle('fill', 0, 0, w, ALTO_BARRA)
    g.setColor(0.2, 0.22, 0.23)
    g.rectangle('fill', 0, ALTO_BARRA - 1, w, 1)
    for _, b in ipairs(botonesBarra(estado)) do
        local encima = v.raton and v.raton.x >= b[2] and v.raton.x < b[2] + BOTON and v.raton.y >= 9 and v.raton.y < 9 + BOTON
        if encima and b.activo then
            g.setColor(1, 1, 1, 0.08)
            g.rectangle('fill', b[2], 9, BOTON, BOTON, 6)
        end
        g.setColor(b.activo and { 0.85, 0.88, 0.9 } or { 0.36, 0.39, 0.41 })
        iconoBarra(b[1], b[2], 9, BOTON)
    end
    local dx, dy, dw, dh = zonaDireccion(w, editable)
    g.setColor(estado.editando and { 0.06, 0.07, 0.075 } or { 0.09, 0.1, 0.105 })
    g.rectangle('fill', dx, dy, dw, dh, 16)
    if estado.editando then
        g.setColor(Dibujo.verde)
        g.rectangle('line', dx + 0.5, dy + 0.5, dw - 1, dh - 1, 16)
    end
    local letra = Dibujo.letra('pagina', 18)
    g.setFont(letra)
    Dibujo.recortado(dx + 14, dy, dw - 28, dh, function()
        local ty = dy + (dh - letra:getHeight()) / 2
        if estado.editando then
            if estado.seleccion and estado.escrito ~= '' then
                g.setColor(0.2, 0.45, 0.8)
                g.rectangle('fill', dx + 14, ty, letra:getWidth(estado.escrito) + 4, letra:getHeight())
            end
            g.setColor(0.92, 0.94, 0.94)
            g.print(estado.escrito, dx + 16, ty)
            if not estado.seleccion and math.floor((ctx.reloj or 0) * 2) % 2 == 0 then
                g.setColor(Dibujo.verde)
                g.rectangle('fill', dx + 17 + letra:getWidth(estado.escrito), ty + 2, 2, letra:getHeight() - 4)
            end
        else
            local direccion = Pagina.direccion(ruta)
            local dominio, resto = direccion:match('^([^/]+)(.*)$')
            g.setColor(0.92, 0.94, 0.94)
            g.print(dominio or direccion, dx + 16, ty)
            if resto and resto ~= '' then
                g.setColor(0.55, 0.6, 0.62)
                g.print(resto, dx + 16 + letra:getWidth(dominio), ty)
            end
        end
    end)
    if editable then
        local bx = w - 104
        local encima = v.raton and v.raton.x >= bx and v.raton.x < bx + 92 and v.raton.y >= 9 and v.raton.y < 9 + BOTON
        g.setColor(encima and { 0.27, 0.75, 0.45 } or { 0.2, 0.6, 0.36 })
        g.rectangle('fill', bx, 9, 92, BOTON, 6)
        g.setColor(1, 1, 1)
        g.setFont(Dibujo.letra('paginaNegrita', 18))
        g.printf('Editar', bx, 9 + (BOTON - g.getFont():getHeight()) / 2, 92, 'center')
    end
end

function Navegador.raton(estado, ctx, accion, x, y)
    local v = viva(estado)
    v.raton = { x = x, y = y }
    if accion ~= 'pulsar' then
        return
    end
    local w = ctx.anchoVentana or Navegador.ancho
    local ruta = rutaActual(estado)
    local editable = require('almacen.pc.archivos').escribible(ruta)
    if y < ALTO_BARRA then
        for _, b in ipairs(botonesBarra(estado)) do
            if b.activo and x >= b[2] and x < b[2] + BOTON then
                if b[1] == 'atras' then
                    moverHistorial(estado, -1)
                elseif b[1] == 'adelante' then
                    moverHistorial(estado, 1)
                elseif b[1] == 'recargar' then
                    vivas[estado] = nil
                else
                    ir(estado, Navegador.inicio)
                end
                return
            end
        end
        local dx, _, dw = zonaDireccion(w, editable)
        if x >= dx and x < dx + dw then
            -- Como en cualquier navegador: la dirección entera queda
            -- seleccionada y lo que se escriba la sustituye.
            estado.editando = true
            estado.seleccion = true
            estado.escrito = Pagina.direccion(ruta)
            return
        end
        if editable and x >= w - 104 and x < w - 12 then
            ctx.ordenador:abrir('texto', nil, nil, nil, nil, { archivo = (Pagina.partes(ruta)) })
        end
        estado.editando = false
        return
    end
    estado.editando = false
    v.campoActivo = nil
    for _, z in ipairs(v.zonas) do
        if x >= z[1] and x < z[1] + z[3] and y >= z[2] and y < z[2] + z[4] then
            if z.campo then
                v.campoActivo = z.campo
            elseif z.enlace then
                ir(estado, Pagina.ruta(z.enlace, (Pagina.partes(ruta))))
            elseif z.boton then
                v.pulsados[z.boton] = true
            end
            return
        end
    end
end

function Navegador.rueda(estado, ctx, dy)
    estado.desplazar = (estado.desplazar or 0) - dy * 60
end

-- Lo escrito en el cuadro activo de la página (o nil).
local function campoActivo(estado)
    local v = vivas[estado]
    if v and v.campoActivo and not estado.editando then
        return v
    end
end

local function borrarUltima(s)
    local c = #s
    while c > 0 and s:byte(c) >= 0x80 and s:byte(c) < 0xC0 do
        c = c - 1
    end
    return s:sub(1, math.max(0, c - 1))
end

function Navegador.texto(estado, ctx, t)
    local v = campoActivo(estado)
    if v then
        local k = v.campoActivo
        local nuevo = (v.campos[k] or '') .. t
        if (utf8.len(nuevo) or #nuevo) <= ((v.limites or {})[k] or 280) then
            v.campos[k] = nuevo
        end
        return
    end
    if estado.editando then
        if estado.seleccion then
            estado.escrito, estado.seleccion = '', false
        end
        estado.escrito = estado.escrito .. t
    end
end

function Navegador.tecla(estado, ctx, tecla)
    local v = campoActivo(estado)
    if v then
        if tecla == 'escape' then
            v.campoActivo = nil
        elseif tecla == 'backspace' then
            v.campos[v.campoActivo] = borrarUltima(v.campos[v.campoActivo] or '')
        end
        return
    end
    if estado.editando then
        if tecla == 'return' or tecla == 'kpenter' then
            ir(estado, Pagina.ruta(estado.escrito, (Pagina.partes(rutaActual(estado)))))
        elseif tecla == 'escape' then
            estado.editando = false
        elseif tecla == 'backspace' and estado.seleccion then
            estado.escrito, estado.seleccion = '', false
        elseif tecla == 'left' or tecla == 'right' or tecla == 'end' or tecla == 'home' then
            estado.seleccion = false
        elseif tecla == 'backspace' then
            local s = estado.escrito
            local c = #s
            while c > 0 and s:byte(c) >= 0x80 and s:byte(c) < 0xC0 do
                c = c - 1
            end
            estado.escrito = s:sub(1, math.max(0, c - 1))
        end
        return
    end
    if tecla == 'f5' then
        vivas[estado] = nil
    elseif tecla == 'down' then
        estado.desplazar = estado.desplazar + 40
    elseif tecla == 'up' then
        estado.desplazar = estado.desplazar - 40
    elseif tecla == 'pagedown' or tecla == 'space' then
        estado.desplazar = estado.desplazar + ((ctx.altoVentana or 500) - ALTO_BARRA - 40)
    elseif tecla == 'pageup' then
        estado.desplazar = estado.desplazar - ((ctx.altoVentana or 500) - ALTO_BARRA - 40)
    elseif tecla == 'home' then
        estado.desplazar = 0
    end
end

function Navegador.icono(x, y, s)
    local g = love.graphics
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.44
    g.setColor(0.16, 0.5, 0.86)
    g.circle('fill', cx, cy, r)
    g.setColor(0.55, 0.85, 1)
    g.setLineWidth(math.max(1, s * 0.05))
    g.ellipse('line', cx, cy, r * 0.45, r)
    g.line(cx - r, cy, cx + r, cy)
    g.line(cx - r * 0.85, cy - r * 0.5, cx + r * 0.85, cy - r * 0.5)
    g.line(cx - r * 0.85, cy + r * 0.5, cx + r * 0.85, cy + r * 0.5)
    g.circle('line', cx, cy, r)
    g.setLineWidth(1)
end

return Navegador

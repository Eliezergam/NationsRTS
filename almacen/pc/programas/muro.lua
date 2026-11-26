-- Programa «Muro»: elegir qué enseña el muro de pantallas del frente de la
-- sala (el dueño, 26-nov). A la izquierda, el muro en pequeño con lo que
-- enseña ahora cada pantalla; se pincha una parte (las 4 de la izquierda,
-- la de arriba o la de abajo a la derecha) y a la derecha se elige qué
-- enseña. Con «Todo el muro», una sola cosa repartida por las 6 pantallas.
-- Lo mismo desde Lua: muro.mostrar('grande', 'robots') (almacen/pc/muro.lua).

local Dibujo = require('almacen.pc.dibujo')
local Muro = require('almacen.pc.muro')

local Programa = {}

Programa.titulo = 'Muro'
Programa.orden = 7
Programa.ancho, Programa.alto = 980, 560

local X_MURO, Y_MURO = 24, 96
local ANCHO_MURO = 560 -- el muro en pequeño (3 x 2 pantallas)
local HUECO = 6 -- marco entre pantallas
local ALTO_FILA = 36
local VERDE = { 0.17, 0.42, 0.26 }
local AZUL = { 0.36, 0.62, 0.95 }

function Programa.nuevo()
    return { zona = 'grande' }
end

local function dentro(z, x, y)
    return z and x >= z[1] and x < z[1] + z[3] and y >= z[2] and y < z[2] + z[4]
end

-- Dónde va cada parte del muro en pequeño: { x, y, ancho, alto }.
local function zonasMiniatura()
    local s = ANCHO_MURO / Muro.ancho
    local t = {}
    for clave, p in pairs(Muro.partes) do
        t[clave] = { X_MURO + p[1] * s, Y_MURO + p[2] * s, p[3] * s, p[4] * s }
    end
    return t, s
end

local function boton(z, texto, activo)
    local g = love.graphics
    g.setColor(activo and VERDE or { 0.16, 0.17, 0.18 })
    g.rectangle('fill', z[1], z[2], z[3], z[4], 5)
    g.setColor(activo and { 0.95, 0.97, 0.96 } or { 0.7, 0.73, 0.74 })
    g.setFont(Dibujo.letra('titulo', 19))
    g.printf(texto, z[1], z[2] + z[4] / 2 - 12, z[3], 'center')
end

local function botones()
    return {
        partes = { X_MURO, 40, 160, 38 },
        todo = { X_MURO + 172, 40, 160, 38 },
    }
end

-- La lista de fuentes: { x, y, ancho, alto, clave } por fila.
local function filas(w)
    local x = X_MURO + ANCHO_MURO + 28
    local lista = {}
    for k, f in ipairs(Muro.fuentes) do
        lista[k] = { x, 72 + (k - 1) * ALTO_FILA, w - x - 20, ALTO_FILA - 4, f.clave, f.titulo }
    end
    return lista
end

function Programa.dibujar(estado, ctx, w, h)
    local g = love.graphics
    estado._ancho = w
    Dibujo.fondo(w, h, 0.09, 0.095, 0.105)
    local e = Muro.estado or Muro.porDefecto()
    local b = botones()
    boton(b.partes, 'Por partes', not e.entero)
    boton(b.todo, 'Todo el muro', e.entero)
    g.setColor(0.6, 0.64, 0.66)
    g.setFont(Dibujo.letra('dato', 14))
    g.print(e.entero and 'Una sola cosa en las 6 pantallas.' or 'Pincha una parte del muro y elige qué enseña.', X_MURO, 14)
    -- El muro en pequeño, con lo que enseña de verdad ahora mismo.
    local zonas, s = zonasMiniatura()
    g.setColor(0.03, 0.03, 0.035)
    g.rectangle('fill', X_MURO - HUECO, Y_MURO - HUECO, ANCHO_MURO + HUECO * 2, Muro.alto * s + HUECO * 2, 4)
    local sala = Muro.sala
    for clave, z in pairs(zonas) do
        local lienzo = sala and sala.muro and sala.muro[clave]
        if lienzo then
            g.setColor(1, 1, 1, 1)
            g.draw(lienzo, z[1], z[2], 0, z[3] / lienzo:getWidth(), z[4] / lienzo:getHeight())
        else
            g.setColor(0.05, 0.06, 0.07)
            g.rectangle('fill', z[1], z[2], z[3], z[4])
        end
    end
    -- Los marcos entre las 6 pantallas (las 4 grandes son una imagen).
    g.setColor(0.03, 0.03, 0.035)
    local ancho, alto = ANCHO_MURO / 3, Muro.alto * s / 2
    for c = 1, 2 do
        g.rectangle('fill', X_MURO + c * ancho - HUECO / 2, Y_MURO, HUECO, alto * 2)
    end
    g.rectangle('fill', X_MURO, Y_MURO + alto - HUECO / 2, ANCHO_MURO, HUECO)
    -- La parte elegida (en «Todo el muro», el muro entero).
    g.setLineWidth(3)
    g.setColor(AZUL)
    if e.entero then
        g.rectangle('line', X_MURO - 3, Y_MURO - 3, ANCHO_MURO + 6, alto * 2 + 6, 3)
    else
        local z = zonas[estado.zona]
        g.rectangle('line', z[1] - 2, z[2] - 2, z[3] + 4, z[4] + 4, 3)
    end
    g.setLineWidth(1)
    -- Lo que enseña cada parte, debajo.
    local y = Y_MURO + alto * 2 + 24
    g.setFont(Dibujo.letra('dato', 15))
    if e.entero then
        g.setColor(0.85, 0.89, 0.86)
        g.print('Todo el muro:  ' .. Muro.tituloDe(e.todo), X_MURO, y)
    else
        for _, z in ipairs(Muro.zonas) do
            local elegida = z.clave == estado.zona
            g.setColor(elegida and AZUL or { 0.6, 0.64, 0.66 })
            g.print(z.titulo .. ':', X_MURO, y)
            g.setColor(elegida and { 1, 1, 1 } or { 0.85, 0.89, 0.86 })
            g.print(Muro.tituloDe(e[z.clave]), X_MURO + 230, y)
            y = y + 26
        end
    end
    -- Las fuentes; marcada la que enseña la parte elegida.
    local actual = e.entero and e.todo or e[estado.zona]
    g.setColor(0.6, 0.64, 0.66)
    g.setFont(Dibujo.letra('titulo', 18))
    local titulo = 'QUÉ ENSEÑA TODO EL MURO'
    if not e.entero then
        for _, z in ipairs(Muro.zonas) do
            if z.clave == estado.zona then
                titulo = 'QUÉ ENSEÑAN ' .. z.titulo:upper()
            end
        end
    end
    local xLista = X_MURO + ANCHO_MURO + 28
    g.print(titulo, xLista, 40)
    g.setFont(Dibujo.letra('dato', 15))
    for _, f in ipairs(filas(w)) do
        local marcada = f[5] == actual
        g.setColor(marcada and VERDE or { 0.13, 0.14, 0.15 })
        g.rectangle('fill', f[1], f[2], f[3], f[4], 4)
        g.setColor(marcada and { 0.95, 0.97, 0.96 } or { 0.8, 0.83, 0.84 })
        g.print(f[6], f[1] + 12, f[2] + 7)
    end
end

function Programa.raton(estado, ctx, accion, x, y)
    if accion ~= 'pulsar' then
        return
    end
    local e = Muro.estado
    if not e then
        return
    end
    local b = botones()
    if dentro(b.partes, x, y) then
        Muro.porPartes()
        return
    elseif dentro(b.todo, x, y) then
        Muro.poner('todo', e.entero and e.todo or e[estado.zona])
        return
    end
    -- Una parte del muro: se elige (y se vuelve a por partes).
    for clave, z in pairs((zonasMiniatura())) do
        if dentro(z, x, y) then
            estado.zona = clave
            if e.entero then
                Muro.porPartes()
            end
            return
        end
    end
    for _, f in ipairs(filas(estado._ancho or Programa.ancho)) do
        if dentro(f, x, y) then
            Muro.poner(e.entero and 'todo' or estado.zona, f[5])
            return
        end
    end
end

--- Icono: el muro de 3 x 2 pantallas.
function Programa.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.16, 0.2, 0.26)
    g.rectangle('fill', x, y, s, s, s * 0.18)
    local m = s * 0.12
    local cw, ch = (s - m * 2 - s * 0.08) / 3, s * 0.24
    for f = 0, 1 do
        for c = 0, 2 do
            g.setColor(c < 2 and { 0.36, 0.62, 0.95 } or { 0.3, 0.78, 0.45 })
            g.rectangle('fill', x + m + c * (cw + s * 0.04), y + s * 0.24 + f * (ch + s * 0.04), cw, ch)
        end
    end
    g.setColor(0.55, 0.58, 0.6)
    g.rectangle('fill', x + s * 0.47, y + s * 0.78, s * 0.06, s * 0.1)
end

return Programa

-- Dibujo de instalaciones de extracción, bases militares y campamentos.
--
-- Lo que se ve sale de los datos de la simulación:
--   progreso       los edificios se levantan (y hay andamios y grúa) hasta 1
--   fortificacion  un muro de sacos y hormigón que se cierra y crece con el tiempo
--   salud          humo y escombros cuando está dañada
--   guarnición     soldados, tanques, aviones y baterías de interceptores

local Iso = require('mundo.iso')
local Ondear = require('mundo.ondear')
local Simulacion = require('mundo.simulacion')

local Instalaciones = {}

-- Zoom desde el que la bandera plantada se dibuja entera en el mundo; por
-- debajo, la señal de tamaño fijo de mundo/senales.lua pone el mástil.
Instalaciones.zoomBandera = 0.6

local function oscurecer(c, k)
    return { c[1] * k, c[2] * k, c[3] * k }
end

--- Prisma de base poligonal (esquinas en mundo) entre las alturas z0 y z1:
-- las caras que miran a la cámara y la tapa.
local function prisma(esquinas, z0, z1, color)
    local g = love.graphics
    local n = #esquinas
    for k = 1, n do
        local a, b = esquinas[k], esquinas[k % n + 1]
        local nx, ny = b[2] - a[2], a[1] - b[1]
        if nx + ny > 0 then
            local luz = nx > ny and 0.68 or 0.9
            g.setColor(color[1] * luz, color[2] * luz, color[3] * luz)
            local ax, ay = Iso.vista(a[1], a[2], z0)
            local bx, by = Iso.vista(b[1], b[2], z0)
            local cx, cy = Iso.vista(b[1], b[2], z1)
            local dx, dy = Iso.vista(a[1], a[2], z1)
            g.polygon('fill', ax, ay, bx, by, cx, cy, dx, dy)
        end
    end
    local tapa = {}
    for _, p in ipairs(esquinas) do
        local vx, vy = Iso.vista(p[1], p[2], z1)
        tapa[#tapa + 1] = vx
        tapa[#tapa + 1] = vy
    end
    g.setColor(color[1] * 1.05, color[2] * 1.05, color[3] * 1.05)
    local ok, triangulos = pcall(love.math.triangulate, tapa)
    if ok then
        for _, t in ipairs(triangulos) do
            g.polygon('fill', t)
        end
    end
end
Instalaciones.prisma = prisma

local function caja(x, y, ancho, fondo, z0, z1, color)
    prisma({
        { x - ancho / 2, y - fondo / 2 },
        { x + ancho / 2, y - fondo / 2 },
        { x + ancho / 2, y + fondo / 2 },
        { x - ancho / 2, y + fondo / 2 },
    }, z0, z1, color)
end

local function cilindro(x, y, radio, z0, z1, color, lados)
    local puntos = {}
    lados = lados or 10
    for k = 0, lados - 1 do
        local a = k / lados * math.pi * 2
        puntos[#puntos + 1] = { x + math.cos(a) * radio, y + math.sin(a) * radio }
    end
    prisma(puntos, z0, z1, color)
end

local function losa(x, y, z, radio, color)
    local g = love.graphics
    local puntos = {}
    for _, p in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        local vx, vy = Iso.vista(x + p[1] * radio, y + p[2] * radio, z + 0.5)
        puntos[#puntos + 1] = vx
        puntos[#puntos + 1] = vy
    end
    g.setColor(color)
    g.polygon('fill', puntos)
end

local function linea(x0, y0, z0, x1, y1, z1, ancho, color)
    local ax, ay = Iso.vista(x0, y0, z0)
    local bx, by = Iso.vista(x1, y1, z1)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(ancho)
    love.graphics.line(ax, ay, bx, by)
    love.graphics.setLineWidth(1)
end

--- Torre de perforación (celosía) de altura `alto`.
local function torre(x, y, z, alto, color)
    local base = 12
    for _, p in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        linea(x + p[1] * base, y + p[2] * base, z, x, y, z + alto, 2, color)
    end
    for k = 1, 4 do
        local t = k / 5
        local r = base * (1 - t)
        linea(x - r, y + r, z + alto * t, x + r, y + r, z + alto * t, 1.2, color)
        linea(x + r, y + r, z + alto * t, x + r, y - r, z + alto * t, 1.2, color)
    end
end

--- Bandera en su mástil con el color de la nación, ondeando con su fase
-- (mundo/ondear.lua, reloj real de la interfaz).
local function bandera(x, y, z, color, _, escala)
    local g = love.graphics
    escala = escala or 1
    local bx, by = Iso.vista(x, y, z)
    local tx, ty = Iso.vista(x, y, z + 42 * escala)
    g.setColor(0.3, 0.3, 0.32)
    g.setLineWidth(1.5)
    g.line(bx, by, tx, ty)
    g.setLineWidth(1)
    Ondear.pano(tx, ty, 18 * escala, 11 * escala, color, Ondear.fase(x, y), 2 * escala, 1, 5)
end

--- Muro de fortificación: segmentos alrededor que se cierran y crecen con el tiempo.
local function fortificacion(x, y, z, radio, nivel)
    if nivel <= 0.01 then
        return
    end
    local segmentos = 28
    local visibles = math.floor(segmentos * math.min(1, nivel * 3))
    local alto = 4 + nivel * 14
    local color = nivel > 0.5 and { 0.62, 0.62, 0.6 } or { 0.62, 0.55, 0.4 } -- hormigón o sacos
    for k = 0, visibles - 1 do
        local a0 = k / segmentos * math.pi * 2
        local a1 = (k + 0.8) / segmentos * math.pi * 2
        -- Solo la mitad delantera tapa lo de dentro; la trasera se dibuja igual (queda detrás).
        local p0 = { x + math.cos(a0) * radio, y + math.sin(a0) * radio }
        local p1 = { x + math.cos(a1) * radio, y + math.sin(a1) * radio }
        local grosor = 5
        local nx, ny = math.cos((a0 + a1) / 2) * grosor, math.sin((a0 + a1) / 2) * grosor
        prisma({
            { p0[1] - nx, p0[2] - ny },
            { p1[1] - nx, p1[2] - ny },
            { p1[1] + nx, p1[2] + ny },
            { p0[1] + nx, p0[2] + ny },
        }, z, z + alto, color)
    end
end

--- Humo de una instalación dañada.
local function humo(x, y, z, dano, tiempo)
    local g = love.graphics
    local puffs = math.floor(dano * 8)
    for k = 1, puffs do
        local t = (tiempo * 0.35 + k * 0.37) % 1
        local ox = math.sin(k * 7.3) * 50
        local oy = math.cos(k * 3.1) * 50
        local vx, vy = Iso.vista(x + ox, y + oy, z + 10 + t * 120)
        g.setColor(0.25, 0.24, 0.23, 0.55 * (1 - t))
        g.circle('fill', vx + t * 20, vy, 8 + t * 22)
    end
    if dano > 0.5 then
        for k = 1, 3 do
            local vx, vy = Iso.vista(x + math.sin(k * 5) * 40, y + math.cos(k * 2) * 40, z + 4)
            g.setColor(1, 0.55 + 0.2 * math.sin(tiempo * 9 + k), 0.15, 0.85)
            g.circle('fill', vx, vy - 4, 5 + math.sin(tiempo * 11 + k) * 2)
        end
    end
end

--- Batería de interceptores: una caja con tubos inclinados.
local function bateria(x, y, z, color)
    caja(x, y, 26, 18, z, z + 6, { 0.34, 0.38, 0.3 })
    for k = -1, 1 do
        linea(x - 8 + k * 6, y, z + 6, x + 4 + k * 6, y - 10, z + 22, 3.2, { 0.8, 0.82, 0.8 })
    end
    local vx, vy = Iso.vista(x, y, z + 6)
    love.graphics.setColor(color)
    love.graphics.circle('fill', vx - 12, vy, 2.5)
end

-- Complejos de extracción --------------------------------------------------------------------

local function petroleo(x, y, z, p, tiempo)
    local alto = 78 * p
    for k, pos in ipairs({ { -60, -40 }, { 10, -70 }, { -20, 30 } }) do
        torre(x + pos[1], y + pos[2], z, alto, { 0.28, 0.28, 0.3 })
        local cabeceo = math.sin(tiempo * 2 + k) * 6
        linea(
            x + pos[1] + 20,
            y + pos[2] + 10,
            z + 14 * p + cabeceo,
            x + pos[1] + 44,
            y + pos[2] + 10,
            z + 14 * p - cabeceo,
            4,
            { 0.85, 0.55, 0.2 }
        )
    end
    cilindro(x + 60, y + 30, 26, z, z + 34 * p, { 0.86, 0.84, 0.8 }, 12)
    cilindro(x + 60, y - 30, 22, z, z + 28 * p, { 0.86, 0.84, 0.8 }, 12)
    linea(x - 60, y - 40, z + 2, x + 60, y + 30, z + 2, 2.5, { 0.4, 0.4, 0.42 })
    caja(x - 55, y + 70, 50, 30, z, z + 18 * p, { 0.72, 0.7, 0.62 })
end

local function metal(x, y, z, p)
    -- Castillete del pozo, naves y montones de mineral con su cinta.
    torre(x - 40, y - 30, z, 96 * p, { 0.42, 0.3, 0.22 })
    caja(x - 40, y - 30, 40, 40, z, z + 14 * p, { 0.52, 0.46, 0.4 })
    caja(x + 40, y - 20, 70, 44, z, z + 30 * p, { 0.62, 0.6, 0.56 })
    caja(x + 30, y + 50, 50, 36, z, z + 22 * p, { 0.58, 0.52, 0.46 })
    for k = 0, 2 do
        local px, py = x - 70 + k * 30, y + 60
        local ax, ay = Iso.vista(px - 16, py, z)
        local bx, by = Iso.vista(px + 16, py, z)
        local cx, cy = Iso.vista(px, py, z + 20 * p)
        love.graphics.setColor(0.46 - k * 0.04, 0.42, 0.4)
        love.graphics.polygon('fill', ax, ay, bx, by, cx, cy)
    end
    linea(x - 40, y - 30, z + 60 * p, x + 20, y - 20, z + 24 * p, 3, { 0.3, 0.3, 0.32 })
end

local function comida(x, y, z, p)
    local colores = { { 0.8, 0.72, 0.3 }, { 0.52, 0.66, 0.28 }, { 0.66, 0.54, 0.3 } }
    for k = 0, 3 do
        local ox = x - 90 + k * 34
        local puntos = {}
        for _, q in ipairs({ { 0, -80 }, { 30, -80 }, { 30, 10 }, { 0, 10 } }) do
            local vx, vy = Iso.vista(ox + q[1], y + q[2], z + 0.5)
            puntos[#puntos + 1] = vx
            puntos[#puntos + 1] = vy
        end
        love.graphics.setColor(colores[k % 3 + 1])
        love.graphics.polygon('fill', puntos)
    end
    for k = 0, 2 do
        cilindro(x + 50 + k * 22, y + 40, 10, z, z + 56 * p, { 0.82, 0.82, 0.8 }, 10)
    end
    caja(x + 60, y - 30, 50, 34, z, z + 22 * p, { 0.72, 0.28, 0.22 })
end

--- Mina de oro: canales de lavado en escalera, montones de grava dorada y
-- una caseta.
local function oro(x, y, z, p)
    for k = 0, 2 do
        local ox = x - 80 + k * 44
        caja(ox, y - 20 + k * 14, 40, 16, z, z + (18 - k * 5) * p, { 0.46, 0.36, 0.24 })
        local ax, ay = Iso.vista(ox - 18, y - 26 + k * 14, z + (18 - k * 5) * p + 0.5)
        local bx, by = Iso.vista(ox + 18, y - 26 + k * 14, z + (18 - k * 5) * p + 0.5)
        local cx, cy = Iso.vista(ox + 18, y - 14 + k * 14, z + (18 - k * 5) * p + 0.5)
        local dx, dy = Iso.vista(ox - 18, y - 14 + k * 14, z + (18 - k * 5) * p + 0.5)
        love.graphics.setColor(0.42, 0.62, 0.72)
        love.graphics.polygon('fill', ax, ay, bx, by, cx, cy, dx, dy)
    end
    for k = 0, 2 do
        local px, py = x + 10 + k * 30, y + 60
        local ax, ay = Iso.vista(px - 16, py, z)
        local bx, by = Iso.vista(px + 16, py, z)
        local cx, cy = Iso.vista(px, py, z + 18 * p)
        love.graphics.setColor(0.86 - k * 0.05, 0.68, 0.22)
        love.graphics.polygon('fill', ax, ay, bx, by, cx, cy)
    end
    caja(x + 55, y - 40, 44, 34, z, z + 24 * p, { 0.6, 0.5, 0.38 })
end

--- Bandera plantada (3.7): un mástil alto con el paño de la nación sobre un
-- montículo de piedras. En obra, el mástil sube con el progreso y hay
-- estacas alrededor. De lejos (`lejos`), solo el montículo y las estacas: el
-- mástil con el paño lo pone la señal de tamaño fijo (mundo/senales.lua).
local function banderaPlantada(inst, color, z, tiempo, lejos)
    local x, y = inst.x, inst.y
    local p = math.max(0.15, inst.progreso)
    local g = love.graphics
    local vx, vy = Iso.vista(x, y, z)
    g.setColor(0, 0, 0, 0.18)
    g.ellipse('fill', vx, vy, 34, 17)
    cilindro(x, y, 16, z, z + 8, { 0.52, 0.5, 0.46 }, 8)
    if inst.progreso < 1 then
        for k = 0, 5 do
            local a = k / 6 * math.pi * 2
            linea(
                x + math.cos(a) * 34,
                y + math.sin(a) * 34,
                z,
                x + math.cos(a) * 34,
                y + math.sin(a) * 34,
                z + 12,
                2,
                { 0.55, 0.4, 0.25 }
            )
        end
    end
    if lejos then
        return
    end
    local alto = 120 * p
    linea(x, y, z + 8, x, y, z + 8 + alto, 3, { 0.3, 0.24, 0.18 })
    if inst.progreso >= 1 then
        bandera(x, y, z + 8 + alto - 42 * 2.2, color, tiempo, 2.2)
    end
end

local function base(x, y, z, p, datos, color, tiempo, dibujos)
    local g = love.graphics
    -- Valla perimetral.
    local r = 150
    for _, lado in ipairs({ { -1, -1, 1, -1 }, { 1, -1, 1, 1 }, { 1, 1, -1, 1 }, { -1, 1, -1, -1 } }) do
        linea(x + lado[1] * r, y + lado[2] * r, z + 9, x + lado[3] * r, y + lado[4] * r, z + 9, 1.5, { 0.5, 0.5, 0.5 })
    end
    -- Helipuerto.
    local hx, hy = Iso.vista(x - 80, y + 80, z + 1)
    g.setColor(0.3, 0.3, 0.32)
    g.ellipse('fill', hx, hy, 30, 15)
    g.setColor(0.95, 0.85, 0.3)
    g.print('H', hx - 4, hy - 8)
    -- Hangares y cuartel.
    caja(x + 60, y - 70, 90, 50, z, z + 26 * p, { 0.5, 0.54, 0.44 })
    caja(x + 60, y + 10, 90, 50, z, z + 26 * p, { 0.5, 0.54, 0.44 })
    caja(x - 70, y - 70, 70, 36, z, z + 18 * p, { 0.62, 0.6, 0.46 })
    -- Radar.
    torre(x - 110, y - 10, z, 40 * p, { 0.4, 0.4, 0.42 })
    local rx, ry = Iso.vista(x - 110, y - 10, z + 40 * p)
    g.setColor(0.86, 0.86, 0.84)
    g.ellipse('fill', rx, ry, 12, 7 + math.sin(tiempo) * 3)
    if p < 1 then
        return
    end
    bandera(x - 130, y + 120, z, color, tiempo)
    for k = 1, math.min(datos.aviones or 0, 3) do
        dibujos.avion(x + 60, y - 70 + (k - 1) * 40 + 80, z, color)
    end
    if (datos.interceptores or 0) > 0 then
        bateria(x - 20, y - 110, z, color)
        if datos.interceptores > 10 then
            bateria(x + 120, y + 100, z, color)
        end
    end
end

--- Dibuja una instalación. `dibujos` trae las piezas de las ciudades
-- (soldado, tanque, avión) para no repetirlas aquí.
--- Tienda de campaña (a lo largo de x): 5 x 4 m y 2,5 m de alto.
local function tienda(x, y, z, color)
    local g = love.graphics
    local l, a, h = 25, 20, 25
    local function p(dx, dy, dz)
        return Iso.vista(x + dx, y + dy, z + dz)
    end
    local r1x, r1y = p(-l, 0, h)
    local r2x, r2y = p(l, 0, h)
    -- Faldón que mira a la cámara (+y) y la punta de delante (+x).
    local s1x, s1y = p(-l, a, 0)
    local s2x, s2y = p(l, a, 0)
    g.setColor(color[1] * 0.92, color[2] * 0.92, color[3] * 0.92)
    g.polygon('fill', r1x, r1y, r2x, r2y, s2x, s2y, s1x, s1y)
    local e1x, e1y = p(l, -a, 0)
    g.setColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7)
    g.polygon('fill', r2x, r2y, e1x, e1y, s2x, s2y)
    -- Entrada.
    local m1x, m1y = p(l, 0, h * 0.55)
    local m2x, m2y = p(l, -a * 0.35, 0)
    local m3x, m3y = p(l, a * 0.35, 0)
    g.setColor(0.18, 0.17, 0.12)
    g.polygon('fill', m1x, m1y, m2x, m2y, m3x, m3y)
end

--- Campamento: tiendas, sacos terreros y una bandera alta con el color del país.
-- `p` de 0 a 1: cuánto se ha levantado. Es también como se ve una ciudad que
-- no es capital.
function Instalaciones.dibujarCampamento(x, y, z, p, color, tiempo)
    losa(x, y, z, 95, { 0.55, 0.5, 0.38, 0.7 })
    fortificacion(x, y, z, 105, 0.3)
    local lona = { 0.42, 0.45, 0.3 }
    local tiendas = { { -45, -35 }, { 30, -50 }, { -50, 35 } }
    for k, t in ipairs(tiendas) do
        -- Mientras se levanta, van apareciendo las tiendas.
        if p >= k / (#tiendas + 1) then
            tienda(x + t[1], y + t[2], z, lona)
        end
    end
    caja(x + 45, y + 30, 30, 20, z, z + 12, { 0.5, 0.42, 0.3 }) -- cajas de munición
    bandera(x, y, z, color, tiempo, 2)
end

function Instalaciones.dibujar(inst, deposito, color, z, tiempo, dibujos)
    local x, y = inst.x, inst.y
    if inst.tipo == 'bandera' then
        banderaPlantada(inst, color, z, tiempo, dibujos and (dibujos.zoom or 1) < Instalaciones.zoomBandera)
        local dano = 1 - (inst.salud or 100) / Simulacion.saludMaxima.bandera
        if dano > 0.15 then
            humo(x, y, z, dano, tiempo)
        end
        return
    end
    if inst.tipo == 'campamento' then
        Instalaciones.dibujarCampamento(x, y, z, math.max(0.12, inst.progreso), color, tiempo)
        local dano = 1 - (inst.salud or 30) / Simulacion.saludMaxima.campamento
        if dano > 0.15 then
            humo(x, y, z, dano, tiempo)
        end
        return
    end
    local p = math.max(0.12, inst.progreso)
    losa(x, y, z, inst.tipo == 'base' and 160 or 120, { 0.62, 0.57, 0.48, 0.85 })
    fortificacion(x, y, z, inst.tipo == 'base' and 175 or 140, inst.fortificacion)
    if inst.tipo == 'base' then
        base(x, y, z, p, inst, color, tiempo, dibujos)
    elseif deposito and deposito.tipo == 'petroleo' then
        petroleo(x, y, z, p, tiempo)
    elseif deposito and deposito.tipo == 'metal' then
        metal(x, y, z, p)
    elseif deposito and deposito.tipo == 'oro' then
        oro(x, y, z, p)
    else
        comida(x, y, z, p)
    end
    if inst.progreso < 1 then
        -- Obras: andamios y una grúa que gira.
        local a = tiempo * 0.4
        torre(x + 90, y + 90, z, 110, { 0.9, 0.7, 0.2 })
        linea(
            x + 90,
            y + 90,
            z + 110,
            x + 90 + math.cos(a) * 90,
            y + 90 + math.sin(a) * 90,
            z + 110,
            3,
            { 0.9, 0.7, 0.2 }
        )
    else
        bandera(x + 100, y + 110, z, color, tiempo)
    end
    local maxima = Simulacion.saludMaxima[inst.tipo] or 100
    local dano = 1 - (inst.salud or maxima) / maxima
    if dano > 0.15 then
        humo(x, y, z, dano, tiempo)
    end
end

--- Huerto de emergencia: unas pocas parcelas pequeñas con surcos, más humilde
-- que un complejo agrícola. Mientras se planta, solo tierra removida.
function Instalaciones.dibujarHuerto(h, z, dia)
    local plantado = dia >= h.hasta
    local colores = plantado and { { 0.46, 0.62, 0.28 }, { 0.62, 0.66, 0.3 }, { 0.4, 0.55, 0.26 } }
        or { { 0.5, 0.38, 0.26 }, { 0.46, 0.35, 0.24 }, { 0.5, 0.38, 0.26 } }
    for k = 0, 2 do
        local ox = h.x - 60 + k * 42
        local ax, ay = Iso.vista(ox, h.y - 45, z)
        local bx, by = Iso.vista(ox + 36, h.y - 45, z)
        local cx, cy = Iso.vista(ox + 36, h.y + 45, z)
        local dx, dy = Iso.vista(ox, h.y + 45, z)
        love.graphics.setColor(colores[k + 1])
        love.graphics.polygon('fill', ax, ay, bx, by, cx, cy, dx, dy)
        love.graphics.setColor(0, 0, 0, 0.15)
        for surco = 1, 5 do
            local fy = h.y - 45 + surco * 15
            local lx, ly = Iso.vista(ox, fy, z)
            local rx, ry = Iso.vista(ox + 36, fy, z)
            love.graphics.line(lx, ly, rx, ry)
        end
    end
end

return Instalaciones

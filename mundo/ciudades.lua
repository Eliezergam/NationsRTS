-- Capitales de las naciones: una por país, generada en un sitio al azar.
--
-- Cada país mide 4 x 4 regiones. Cada región puede tener una candidata
-- (con probabilidad `Ciudades.probabilidad`, en tierra firme, ni mar ni
-- cumbres). De todas las candidatas del país, la de mayor `radioBase`
-- es la capital; las demás se descartan (no hay ciudades secundarias,
-- solo capitales y banderas).
--
-- El mundo no tiene casas, calles ni gente. La capital es una torre
-- sobre su base. El territorio se forma plantando banderas alrededor
-- de la capital (Instalaciones).

local Ruido = require('mundo.ruido')
local Llano = require('mundo.llano')
local Iso = require('mundo.iso')
local Ondear = require('mundo.ondear')
local Instalaciones = require('mundo.instalaciones')

local Ciudades = {}
Ciudades.__index = Ciudades

-- Mapa comprimido (1 px = 10 cm): regiones de unos 1,2 km y países de 4 x 4
-- regiones (unos 5 km). Las ciudades de un país se juntan hacia su centro:
-- quedan a uno o dos km entre sí y con campo abierto hasta el país vecino.
Ciudades.region = 12288 -- el dueño (2026-09-30): naciones a la mitad de distancia; antes 24576
Ciudades.porNacion = 4 -- regiones por lado de un país
Ciudades.agrupar = 0.7 -- cuánto se acercan las ciudades al centro de su país (1: nada)
Ciudades.escalaCasco = 5 -- la zona de la ciudad para la simulación: 5 veces el radio de la economía
Ciudades.lado = 600 -- px de lado de la base de la torre (la plaza de la capital: 60 m)
Ciudades.casco = 450 -- px del centro que ocupa la ciudad en el suelo (base o campamento)
Ciudades.probabilidad = 0.31 -- unas 2 ciudades por país (4 x 4 regiones)
Ciudades.alcanceLlano = 3000 -- px (m de la batalla) que puede moverse para caer en lo llano

local SILABAS = {
    'va',
    'lo',
    'mar',
    'ten',
    'ri',
    'sa',
    'cor',
    'bel',
    'du',
    'na',
    'que',
    'ro',
    'pal',
    'mi',
    'tor',
    'le',
    'gra',
    'nu',
    'ves',
    'ca',
    'do',
    'fi',
    'zar',
    'al',
}

function Ciudades.nuevo(terreno)
    local self = setmetatable({}, Ciudades)
    self.terreno = terreno
    self.semilla = terreno.semilla
    self.regiones = {} -- 'rx,ry' -> ciudad que sale de la semilla, o false
    self.capitales = {} -- 'rx,ry' -> la ciudad si es la capital de su país, o false
    -- Lo mismo con clave numérica, para `cercanas`: se llama cientos de miles
    -- de veces al generar el terreno de una batalla y la clave de texto de
    -- `deRegion` (una cadena nueva por llamada) era lo que más costaba.
    self.capitalesRapidas = {}
    return self
end

local function nombreCiudad(azar)
    local partes = {}

    for k = 1, math.floor(azar(2, 3.99)) do
        partes[k] = SILABAS[math.floor(azar(1, #SILABAS + 0.99))]
    end

    local nombre = table.concat(partes)
    return nombre:sub(1, 1):upper() .. nombre:sub(2)
end

--- Capital de la región (rx, ry), o nil. Cada país (zona de `porNacion` x
-- `porNacion` regiones) tiene una sola capital: la mayor de las candidatas
-- que salen de la semilla en sus regiones (a igual tamaño, la de menor
-- id). El resto de su tierra la ganan sus banderas.
function Ciudades:deRegion(rx, ry)
    local clave = rx .. ',' .. ry
    local guardada = self.capitales[clave]
    if guardada ~= nil then
        return guardada or nil
    end
    local propia = self:candidata(rx, ry)
    local capital = propia
    if propia then
        local zx, zy = math.floor(rx / Ciudades.porNacion), math.floor(ry / Ciudades.porNacion)
        for y = zy * Ciudades.porNacion, zy * Ciudades.porNacion + Ciudades.porNacion - 1 do
            for x = zx * Ciudades.porNacion, zx * Ciudades.porNacion + Ciudades.porNacion - 1 do
                local otra = self:candidata(x, y)
                if
                    otra
                    and (
                        otra.radioBase > capital.radioBase
                        or (otra.radioBase == capital.radioBase and otra.region < capital.region)
                    )
                then
                    capital = otra
                end
            end
        end
    end
    local es = propia and capital == propia and propia or false
    self.capitales[clave] = es
    return es or nil
end

--- Candidata a capital que la semilla pone en la región (rx, ry). Solo
-- se usa para elegir la capital del país (`deRegion`); las que pierden
-- ese concurso no se dibujan.
function Ciudades:candidata(rx, ry)
    local clave = rx .. ',' .. ry
    local guardada = self.regiones[clave]

    if guardada ~= nil then
        return guardada or nil
    end

    local azar = Ruido.azar(Ruido.hash(self.semilla, rx, ry, 31))
    local ciudad = false

    if azar() < Ciudades.probabilidad then
        local r = Ciudades.region
        -- Hacia el centro del país: con 0.25-0.75 dentro de la región y 0.7, dos
        -- ciudades vecinas quedan al menos a 860 m (cascos de 310 m como mucho).
        local lado = Ciudades.porNacion * r
        local centroX = (math.floor(rx / Ciudades.porNacion) + 0.5) * lado
        local centroY = (math.floor(ry / Ciudades.porNacion) + 0.5) * lado
        local x = centroX + ((rx + azar(0.25, 0.75)) * r - centroX) * Ciudades.agrupar
        local y = centroY + ((ry + azar(0.25, 0.75)) * r - centroY) * Ciudades.agrupar
        -- En lo llano (mundo/llano.lua, el dueño, 20-nov): la huella entera de
        -- la ciudad con su aeródromo, a menos de `alcanceLlano` del punto que
        -- tocaba; si no hay, en esta región no hay ciudad. Tierra firme y no
        -- demasiado alta: ni en el mar ni en una cumbre.
        -- Antes, el filtro de siempre en el punto que tocaba (así salen las
        -- mismas ciudades por país que antes).
        local t = self.terreno
        local dx = t:base(x + 400, y) - t:base(x - 400, y)
        local dy = t:base(x, y + 400) - t:base(x, y - 400)
        local h0 = t:base(x, y)
        local lx, ly
        if h0 > 18 and h0 < 170 and math.sqrt(dx * dx + dy * dy) / 800 < 0.1 then
            lx, ly = Llano.buscar(t, x, y, Llano.huellaCiudad, Ciudades.alcanceLlano)
        end
        local h = lx and t:base(lx, ly) or 0
        x, y = lx or x, ly or y

        if lx and h > 18 and h < 170 then
            -- `radioBase` mide la ciudad para la economía (población, cultivos) y
            -- su zona en la simulación; `radio` es lo que ocupa en el suelo.
            local base = azar(260, 620)
            ciudad = {
                x = x,
                y = y,
                altura = h,
                radio = Ciudades.casco,
                radioBase = base,
                nombre = nombreCiudad(azar),
                semilla = math.floor(azar() * 2147483646) + 1,
                region = clave,
            }
        end
    end

    self.regiones[clave] = ciudad
    return ciudad or nil
end

--- Distancia del centro al borde de lo que ocupa la ciudad en el suelo (px).
function Ciudades.borde(ciudad, _angulo)
    return ciudad.radio
end

--- ¿(x, y) está a menos de `margen` px por fuera de lo que ocupa la ciudad?
function Ciudades.cerca(ciudad, x, y, margen)
    local dx, dy = x - ciudad.x, y - ciudad.y
    return dx * dx + dy * dy < (ciudad.radio + margen) ^ 2
end

--- Ciudades cuyo radio de influencia puede tocar el punto (x, y).
function Ciudades:cercanas(x, y)
    local r = Ciudades.region
    local rx, ry = math.floor(x / r), math.floor(y / r)
    local lista = {}

    local rapidas = self.capitalesRapidas
    for dy = -1, 1 do
        for dx = -1, 1 do
            -- Único mientras |ry| < 2^19 regiones.
            local clave = (rx + dx) * 1048576 + (ry + dy)
            local ciudad = rapidas[clave]
            if ciudad == nil then
                ciudad = self:deRegion(rx + dx, ry + dy) or false
                rapidas[clave] = ciudad
            end
            ciudad = ciudad or nil

            if ciudad then
                local ex, ey = x - ciudad.x, y - ciudad.y

                if ex * ex + ey * ey < (ciudad.radio + 300) ^ 2 then
                    lista[#lista + 1] = ciudad
                end
            end
        end
    end

    return lista
end

--- ¿El punto cae en el casco de alguna ciudad (calles y edificios)?
function Ciudades:dentro(x, y)
    for _, ciudad in ipairs(self:cercanas(x, y)) do
        if Ciudades.cerca(ciudad, x, y, 40) then
            return true
        end
    end

    return false
end

-- Geometría de los edificios --------------------------------------------------------

local function oscurecer(c, k)
    return { c[1] * k, c[2] * k, c[3] * k }
end

local function quad(v, a, b, c, d, color)
    local r, g, bl = color[1], color[2], color[3]
    for _, p in ipairs({ a, b, c, a, c, d }) do
        v[#v + 1] = { p[1], p[2], 0, 0, r, g, bl, 1 }
    end
end

local function tri(v, a, b, c, color)
    local r, g, bl = color[1], color[2], color[3]
    for _, p in ipairs({ a, b, c }) do
        v[#v + 1] = { p[1], p[2], 0, 0, r, g, bl, 1 }
    end
end

local function punto(x, y, z)
    return { Iso.vista(x, y, z) }
end

--- Vértices de un edificio: caja con sus dos caras visibles, ventanas y tejado.
-- `e.sinSombra` y `e.sinPuerta` para los cuerpos de encima de otro (la torre).
local function verticesEdificio(v, e, z)
    local x0, y0, x1, y1 = e.x - e.ancho / 2, e.y - e.fondo / 2, e.x + e.ancho / 2, e.y + e.fondo / 2
    local top = z + e.alto
    local pared = e.pared

    -- Sombra en el suelo, hacia abajo a la derecha de la pantalla.
    if not e.sinSombra then
        local sombra = { 0.12, 0.1, 0.08 }
        local sx = e.alto * 0.35
        quad(v, punto(x0, y1, z), punto(x1, y1, z), punto(x1 + sx, y1 + sx, z), punto(x0 + sx, y1 + sx, z), sombra)
        for k = #v - 5, #v do
            v[k][8] = 0.22
        end
    end

    -- Cara sur (hacia abajo a la izquierda) y cara este (hacia abajo a la derecha).
    local sur, este = oscurecer(pared, 0.92), oscurecer(pared, 0.72)
    quad(v, punto(x0, y1, z), punto(x1, y1, z), punto(x1, y1, top), punto(x0, y1, top), sur)
    quad(v, punto(x1, y1, z), punto(x1, y0, z), punto(x1, y0, top), punto(x1, y1, top), este)

    -- Ventanas: filas por planta, en las dos caras.
    local ventana = { 0.25, 0.3, 0.38 }
    local luz = { 0.95, 0.85, 0.55 }
    -- Un piso son 3 m (30 px): una fila de ventanas de 1,3 m por piso.
    local plantas = math.max(1, math.floor(e.alto / 30))

    for p = 0, plantas - 1 do
        local wz = z + 10 + p * 30

        if wz + 13 < top - 2 then
            for k = 1, math.max(1, math.floor(e.ancho / 20)) do
                local wx = x0 + k * e.ancho / (math.floor(e.ancho / 20) + 1)
                local color = (e.luces and (k + p) % 3 == 0) and luz or ventana
                quad(
                    v,
                    punto(wx - 4, y1, wz),
                    punto(wx + 4, y1, wz),
                    punto(wx + 4, y1, wz + 13),
                    punto(wx - 4, y1, wz + 13),
                    color
                )
            end

            for k = 1, math.max(1, math.floor(e.fondo / 20)) do
                local wy = y1 - k * e.fondo / (math.floor(e.fondo / 20) + 1)
                quad(
                    v,
                    punto(x1, wy + 4, wz),
                    punto(x1, wy - 4, wz),
                    punto(x1, wy - 4, wz + 13),
                    punto(x1, wy + 4, wz + 13),
                    oscurecer(ventana, 0.8)
                )
            end
        end
    end

    -- Puerta en la cara sur.
    if not e.sinPuerta then
        quad(
            v,
            punto(e.x - 3, y1, z),
            punto(e.x + 3, y1, z),
            punto(e.x + 3, y1, z + 10),
            punto(e.x - 3, y1, z + 10),
            { 0.3, 0.22, 0.16 }
        )
    end

    if e.tejado == 'plano' then
        quad(v, punto(x0, y0, top), punto(x1, y0, top), punto(x1, y1, top), punto(x0, y1, top), oscurecer(pared, 1.05))
        -- Pretil y una caja de máquinas.
        local m = 4
        quad(
            v,
            punto(x0 + m, y0 + m, top + 0.5),
            punto(x1 - m, y0 + m, top + 0.5),
            punto(x1 - m, y1 - m, top + 0.5),
            punto(x0 + m, y1 - m, top + 0.5),
            oscurecer(pared, 0.9)
        )
    else
        -- Tejado a dos aguas con la cumbrera a lo largo del lado más largo.
        local subida = math.min(e.ancho, e.fondo) * 0.45
        local tejado = e.colorTejado
        if e.ancho >= e.fondo then
            local ym = (y0 + y1) / 2
            quad(
                v,
                punto(x0, y1, top),
                punto(x1, y1, top),
                punto(x1, ym, top + subida),
                punto(x0, ym, top + subida),
                tejado
            )
            quad(
                v,
                punto(x0, y0, top),
                punto(x1, y0, top),
                punto(x1, ym, top + subida),
                punto(x0, ym, top + subida),
                oscurecer(tejado, 1.15)
            )
            tri(v, punto(x1, y1, top), punto(x1, y0, top), punto(x1, ym, top + subida), oscurecer(pared, 0.72))
        else
            local xm = (x0 + x1) / 2
            quad(
                v,
                punto(x1, y0, top),
                punto(x1, y1, top),
                punto(xm, y1, top + subida),
                punto(xm, y0, top + subida),
                oscurecer(tejado, 0.8)
            )
            quad(
                v,
                punto(x0, y0, top),
                punto(x0, y1, top),
                punto(xm, y1, top + subida),
                punto(xm, y0, top + subida),
                oscurecer(tejado, 1.15)
            )
            tri(v, punto(x0, y1, top), punto(x1, y1, top), punto(xm, y1, top + subida), oscurecer(pared, 0.92))
        end
    end
end

-- Torre de la capital, en el centro de la plaza (px, 1 px = 10 cm): un zócalo
-- de 30 m de lado, un fuste de cristal de 16 m hasta los 90 m, una corona con
-- el color del país y una aguja: unos 128 m, más del triple que el edificio
-- más alto de la ciudad.
Ciudades.torre = {
    base = 300,
    altoBase = 60,
    fuste = 160,
    alto = 900,
    corona = 110,
    altoCorona = 80,
    aguja = 300,
}

--- Malla de la torre de la capital (sin la franja del país, que cambia de color).
local function mallaTorre(x, y, z)
    local t = Ciudades.torre
    local v = {}
    local piedra = { 0.78, 0.76, 0.72 }
    -- Sombra larga del fuste en el suelo.
    local sx = (t.alto + t.altoCorona) * 0.35
    local m = t.fuste / 2
    quad(
        v,
        punto(x - m, y + m, z),
        punto(x + m, y + m, z),
        punto(x + m + sx, y + m + sx, z),
        punto(x - m + sx, y + m + sx, z),
        { 0.12, 0.1, 0.08 }
    )
    for k = #v - 5, #v do
        v[k][8] = 0.22
    end
    verticesEdificio(v, {
        x = x,
        y = y,
        ancho = t.base,
        fondo = t.base,
        alto = t.altoBase,
        pared = piedra,
        tejado = 'plano',
        luces = true,
    }, z)
    verticesEdificio(v, {
        x = x,
        y = y,
        ancho = t.fuste,
        fondo = t.fuste,
        alto = t.alto - t.altoBase,
        pared = { 0.46, 0.56, 0.64 },
        tejado = 'plano',
        luces = true,
        sinSombra = true,
        sinPuerta = true,
    }, z + t.altoBase)
    verticesEdificio(v, {
        x = x,
        y = y,
        ancho = t.corona,
        fondo = t.corona,
        alto = t.altoCorona,
        pared = piedra,
        tejado = 'plano',
        sinSombra = true,
        sinPuerta = true,
    }, z + t.alto)
    -- Aguja: un mástil fino con sus dos caras visibles.
    local a, arriba, cima = 6, z + t.alto + t.altoCorona, z + t.alto + t.altoCorona + t.aguja
    local metal = { 0.7, 0.72, 0.75 }
    quad(
        v,
        punto(x - a, y + a, arriba),
        punto(x + a, y + a, arriba),
        punto(x + a, y + a, cima),
        punto(x - a, y + a, cima),
        metal
    )
    quad(
        v,
        punto(x + a, y + a, arriba),
        punto(x + a, y - a, arriba),
        punto(x + a, y - a, cima),
        punto(x + a, y + a, cima),
        oscurecer(metal, 0.75)
    )
    return love.graphics.newMesh(v, 'triangles', 'static')
end

--- Franja con el color del país en lo alto de la corona de la torre.
function Ciudades.dibujarFranjaTorre(x, y, z, color)
    local g = love.graphics
    local t = Ciudades.torre
    local m = t.corona / 2 + 0.5
    local z0, z1 = z + t.alto + t.altoCorona - 30, z + t.alto + t.altoCorona - 8
    local function cara(ax, ay, bx, by, luz)
        local p1x, p1y = Iso.vista(ax, ay, z0)
        local p2x, p2y = Iso.vista(bx, by, z0)
        local p3x, p3y = Iso.vista(bx, by, z1)
        local p4x, p4y = Iso.vista(ax, ay, z1)
        g.setColor(color[1] * luz, color[2] * luz, color[3] * luz)
        g.polygon('fill', p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
    end
    cara(x - m, y + m, x + m, y + m, 0.92)
    cara(x + m, y + m, x + m, y - m, 0.72)
end

--- Monumento de la plaza: un obelisco.
-- Trazado ----------------------------------------------------------------------------

--- Prepara la ciudad para dibujarla: la base cuadrada de la torre (solo se
-- ve en la capital). Nada de casas, calles ni habitantes.
function Ciudades:construir(ciudad)
    if ciudad.plaza then
        return ciudad
    end
    local z = ciudad.altura
    local h = Ciudades.lado / 2
    ciudad.plaza = { x = ciudad.x, y = ciudad.y, lado = Ciudades.lado }
    local suelo = {}
    quad(
        suelo,
        punto(ciudad.x - h, ciudad.y - h, z),
        punto(ciudad.x + h, ciudad.y - h, z),
        punto(ciudad.x + h, ciudad.y + h, z),
        punto(ciudad.x - h, ciudad.y + h, z),
        { 0.8, 0.76, 0.68 }
    )
    ciudad.suelo = love.graphics.newMesh(suelo, 'triangles', 'static')
    return ciudad
end

--- Solo el reloj de la bandera.
function Ciudades:actualizar(ciudad, dt)
    ciudad.tiempo = (ciudad.tiempo or 0) + dt
end

--- El sitio de la ciudad para su maqueta (mundo/maquetas.lua): el mismo que
-- se genera al entrar (todas las ciudades del mapa son capitales).
function Ciudades.sitioMaqueta(ciudad)
    local s = ciudad.sitioMaqueta
    if not s then
        s = { tipo = 'ciudad', capital = true, x = ciudad.x, y = ciudad.y }
        ciudad.sitioMaqueta = s
    end
    return s
end

--- Lo que hay que dibujar de una ciudad, con su profundidad: la capital, su
-- torre; las demás, su campamento. Al lado, los tanques y aviones que tenga
-- (los vehículos se ven; la gente no).
function Ciudades:piezas(ciudad, lista)
    local z = ciudad.altura
    local color = ciudad.color or { 0.8, 0.8, 0.8 }
    local datos = ciudad.datos or {}
    local x, y = ciudad.x, ciudad.y
    local borde
    -- La maqueta del sitio 3D (mundo/maquetas.lua), cuando está hecha; mientras,
    -- la torre de antes.
    local maqueta = self.maquetas and self.maquetas:de(Ciudades.sitioMaqueta(ciudad))
    if maqueta then
        lista[#lista + 1] = {
            profundidad = Iso.profundidad(x, y),
            dibujar = function()
                require('mundo.maquetas').dibujar(maqueta, x, y)
                Ciudades.dibujarBandera(x, y, z, color)
            end,
        }
        -- Sus aviones, aparcados en las plazas de la plataforma, al norte de
        -- la pista (batalla/dream/plataforma_avion.lua).
        local pista = maqueta.meta.pista
        if pista then
            local plazas = require('batalla.dream.plataforma_avion').plazas()
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            for k = 1, math.min(datos.aviones or 0, #plazas) do
                local ax, ay = x + pista.x + plazas[k], y + pista.y - P.plaza
                lista[#lista + 1] = {
                    profundidad = Iso.profundidad(ax, ay),
                    dibujar = function()
                        Ciudades.dibujarAvion(ax, ay, z, color)
                    end,
                }
            end
        end
        return
    end
    do
        -- Una torre en toda ciudad: la capital y las que se conquistan (que
        -- fueron capitales de otro país).
        self:construir(ciudad)
        ciudad.torre = ciudad.torre or mallaTorre(x, y, z)
        lista[#lista + 1] = {
            profundidad = Iso.profundidad(x, y),
            dibujar = function()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(ciudad.torre)
                Ciudades.dibujarFranjaTorre(x, y, z, color)
                local t = Ciudades.torre
                Ciudades.dibujarBandera(x, y, z + t.alto + t.altoCorona + t.aguja, color)
                Ciudades.dibujarChimenea(x, y, z, datos)
            end,
        }
        borde = Ciudades.lado / 2
    end

    -- Aviones al lado.
    for k = 1, math.min(datos.aviones or 0, 3) do
        local ax, ay = x + borde + 60, y - borde + 40 + (k - 1) * 60
        lista[#lista + 1] = {
            profundidad = Iso.profundidad(ax, ay),
            dibujar = function()
                Ciudades.dibujarAvion(ax, ay, z, color)
            end,
        }
    end
end

--- Prisma de base poligonal (esquinas en mundo, en sentido horario visto desde
-- arriba) entre las alturas z0 y z1: caras que miran a la cámara y tapa.
local function prisma(esquinas, z0, z1, color)
    local g = love.graphics
    local n = #esquinas
    for k = 1, n do
        local a, b = esquinas[k], esquinas[k % n + 1]
        -- Normal hacia fuera del lado a-b; se ve si mira hacia +x o +y (hacia la cámara).
        local nx, ny = b[2] - a[2], a[1] - b[1]
        if nx + ny > 0 then
            local luz = 0.62 + 0.25 * (nx > ny and 0 or 1)
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
    g.polygon('fill', tapa)
end

local function rectanguloGirado(x, y, ancho, fondo, angulo)
    local c, s = math.cos(angulo), math.sin(angulo)
    local puntos = {}
    for _, p in ipairs({
        { -ancho / 2, -fondo / 2 },
        { ancho / 2, -fondo / 2 },
        { ancho / 2, fondo / 2 },
        { -ancho / 2, fondo / 2 },
    }) do
        puntos[#puntos + 1] = { x + p[1] * c - p[2] * s, y + p[1] * s + p[2] * c }
    end
    return puntos
end

--- Camión de tropa (los soldados van dentro): 8 x 2,5 m, cabina delante y
-- la caja cubierta con lona; una franja con el color de su nación.
function Ciudades.dibujarCamion(x, y, z, color, angulo)
    local g = love.graphics
    local ca, sa = math.cos(angulo), math.sin(angulo)
    local vx, vy = Iso.vista(x, y, z)
    g.setColor(0, 0, 0, 0.25)
    g.ellipse('fill', vx + 8, vy + 5, 46, 18)
    prisma(rectanguloGirado(x, y, 80, 25, angulo), z + 4, z + 10, { 0.16, 0.16, 0.15 })
    prisma(rectanguloGirado(x + ca * 29, y + sa * 29, 20, 24, angulo), z + 10, z + 30, { 0.36, 0.4, 0.26 })
    prisma(rectanguloGirado(x - ca * 10, y - sa * 10, 56, 25, angulo), z + 10, z + 33, { 0.42, 0.45, 0.3 })
    prisma(rectanguloGirado(x - ca * 10, y - sa * 10, 56, 25.5, angulo), z + 26, z + 29, color)
end

--- Avión aparcado: fuselaje, alas y cola, con la escarapela de su nación.
function Ciudades.dibujarAvion(x, y, z, color)
    local g = love.graphics
    local function p(dx, dy, h)
        return Iso.vista(x + dx, y + dy, z + (h or 3))
    end
    g.setColor(0, 0, 0, 0.25)
    local sx, sy = Iso.vista(x + 3, y + 3, z)
    g.ellipse('fill', sx, sy, 22, 9)
    g.setColor(0.62, 0.64, 0.66)
    local ax, ay = p(-4, -22)
    local bx, by = p(4, -22)
    local cx, cy = p(4, 22)
    local dx, dy = p(-4, 22)
    g.polygon('fill', ax, ay, bx, by, cx, cy, dx, dy)
    g.setColor(0.72, 0.74, 0.76)
    local w1x, w1y = p(-24, 2)
    local w2x, w2y = p(24, 2)
    local w3x, w3y = p(0, -8)
    g.polygon('fill', w1x, w1y, w3x, w3y, w2x, w2y)
    local t1x, t1y = p(-9, 20)
    local t2x, t2y = p(9, 20)
    local t3x, t3y = p(0, 14)
    g.polygon('fill', t1x, t1y, t3x, t3y, t2x, t2y)
    g.setColor(color)
    local rx, ry = p(-14, 2)
    g.circle('fill', rx, ry, 2.5)
end

--- Bandera en su mástil, ondeando con su propia fase (mundo/ondear.lua).
-- `tiempo` ya no se usa: las ondas van con el reloj real de la interfaz.
function Ciudades.dibujarBandera(x, y, z, color)
    local g = love.graphics
    local bx, by = Iso.vista(x, y, z)
    local tx, ty = Iso.vista(x, y, z + 48)
    g.setColor(0.3, 0.3, 0.32)
    g.setLineWidth(1.5)
    g.line(bx, by, tx, ty)
    g.setLineWidth(1)
    Ondear.pano(tx, ty, 22, 13, color, Ondear.fase(x, y), 2.6)
end

--- Chimenea de la fábrica de la ciudad, en la esquina derecha del podio,
-- con humo leve; más humo si hay algo en fábrica.
function Ciudades.dibujarChimenea(x, y, z, datos)
    local g = love.graphics
    local t = Ciudades.torre
    local cx, cy = x + t.base / 2 - 34, y - t.base / 2 + 34
    local z0, z1 = z + t.altoBase, z + t.altoBase + 70
    local r = 9
    local function cara(ax, ay, bx, by, luz)
        local p1x, p1y = Iso.vista(ax, ay, z0)
        local p2x, p2y = Iso.vista(bx, by, z0)
        local p3x, p3y = Iso.vista(bx, by, z1)
        local p4x, p4y = Iso.vista(ax, ay, z1)
        g.setColor(0.56 * luz, 0.5 * luz, 0.46 * luz)
        g.polygon('fill', p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
    end
    cara(cx - r, cy + r, cx + r, cy + r, 0.95)
    cara(cx + r, cy + r, cx + r, cy - r, 0.72)
    -- Boca oscura y franja clara arriba.
    local bx, by = Iso.vista(cx, cy, z1)
    g.setColor(0.18, 0.17, 0.17)
    g.ellipse('fill', bx, by, r * 1.1, r * 0.55)
    local enFabrica = datos and ((#(datos.fabrica or {}) > 0) or (#(datos.fabricaMunicion or {}) > 0))
    Ondear.humo(bx, by - 2, 1, Ondear.fase(x, y), enFabrica and 1 or 0.25)
end

return Ciudades

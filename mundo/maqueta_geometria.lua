-- Geometría de la maqueta de un sitio (ciudad o mina) para el mapa: el mismo
-- plano que se ve al entrar (batalla/sitios/plano.lua), sobre un suelo ligero
-- (batalla/sitios/suelo_sitio.lua), con las mismas piezas (cada edificio en
-- el nivel lejano del kit, batalla/dream/kit_sitio.lua), las calles, la pista
-- y la plataforma de los aviones. No usa love.graphics: corre en el hilo de
-- mundo/obrero_maqueta.lua; mundo/maquetas.lua la hornea en una imagen.
--
-- Coordenadas de salida: las del mapa (1 = 1 m), relativas al punto del
-- sitio en x e y; la altura, la del mapa (en la batalla, 10 px por metro y
-- el nivel del mar en 0: Terreno.nivelMar).

local ffi = require('ffi')
local Plano = require('batalla.sitios.plano')
local SueloSitio = require('batalla.sitios.suelo_sitio')
local KitSitio = require('batalla.dream.kit_sitio')
local PistaAvion = require('batalla.dream.pista_avion')
local PlataformaAvion = require('batalla.dream.plataforma_avion')
local Terreno = require('mundo.terreno')

pcall(ffi.cdef, [[
typedef struct { float x, y, z, nx, ny, nz, u, v; } VerticeMaqueta;
]])

local MaquetaGeometria = {}

MaquetaGeometria.nivel = 3 -- nivel del kit de cada edificio: una caja con su chapa y su techo
MaquetaGeometria.margenSombra = 60 -- m de suelo alrededor de lo construido (donde caen las sombras)
MaquetaGeometria.tamano = ffi.sizeof('VerticeMaqueta')

local VISTA_Z = math.sqrt(1.5) -- Iso.escalaAltura
local PROF_XY = math.cos(math.rad(30)) / math.sqrt(2)
local PROF_Z = 0.5

--- Caja que crece con cada vértice: vista (vx, vy), profundidad y planta.
local function nuevaCaja()
    local caja = {}
    for _, eje in ipairs({ 'vx', 'vy', 'd', 'x', 'y', 'z' }) do
        caja[eje .. '0'] = math.huge
        caja[eje .. '1'] = -math.huge
    end
    return caja
end

local function crecer(caja, x, y, z)
    local vx, vy = x - y, (x + y) * 0.5 - z * VISTA_Z
    local d = (x + y) * PROF_XY + z * PROF_Z
    caja.vx0, caja.vx1 = math.min(caja.vx0, vx), math.max(caja.vx1, vx)
    caja.vy0, caja.vy1 = math.min(caja.vy0, vy), math.max(caja.vy1, vy)
    caja.d0, caja.d1 = math.min(caja.d0, d), math.max(caja.d1, d)
    caja.x0, caja.x1 = math.min(caja.x0, x), math.max(caja.x1, x)
    caja.y0, caja.y1 = math.min(caja.y0, y), math.max(caja.y1, y)
    caja.z0, caja.z1 = math.min(caja.z0, z), math.max(caja.z1, z)
end

--- Vértices de un material (lista de Lote o datos sueltos) a ByteData.
local function empaquetar(l, ox, oy, caja)
    local n = l.vertices
    local datos = love.data.newByteData(n * MaquetaGeometria.tamano)
    local v = ffi.cast('VerticeMaqueta*', datos:getFFIPointer())
    local k = 0
    for _, p in ipairs(l.piezas or {}) do
        local d, giro = p[1], p[5]
        local c, s = math.cos(giro), math.sin(giro)
        local px, py, pz = p[2] * 0.1 - ox, p[3] * 0.1 - oy, p[4] * 0.1
        for o = 1, #d, 12 do
            local X, Z = d[o], d[o + 2]
            local q = v[k]
            local x, y, z = px + X * c - Z * s, py + X * s + Z * c, pz + d[o + 1]
            q.x, q.y, q.z = x, y, z
            local nx, nz = d[o + 3], d[o + 5]
            q.nx, q.ny, q.nz = nx * c - nz * s, nx * s + nz * c, d[o + 4]
            q.u, q.v = d[o + 6], d[o + 7]
            crecer(caja, x, y, z)
            k = k + 1
        end
    end
    for _, d in ipairs(l.sueltos or {}) do
        for o = 1, #d, 12 do
            local q = v[k]
            local x, y, z = d[o] - ox, d[o + 2] - oy, d[o + 1]
            q.x, q.y, q.z = x, y, z
            q.nx, q.ny, q.nz = d[o + 3], d[o + 5], d[o + 4]
            q.u, q.v = d[o + 6], d[o + 7]
            crecer(caja, x, y, z)
            k = k + 1
        end
    end
    return datos, k
end

--- Suelo (rejilla del suelo ligero, ya explanada) dentro de la planta de lo
-- construido más `margen` m: vértices e índices de sus triángulos.
local function sueloBajo(suelo, caja, margen, ox, oy)
    local rej = suelo.relieve
    local xs, ys, lado = rej.xs, rej.ys, rej.lado
    local x0, x1 = (caja.x0 - margen + ox) * 10, (caja.x1 + margen + ox) * 10
    local y0, y1 = (caja.y0 - margen + oy) * 10, (caja.y1 + margen + oy) * 10
    local i0, i1, j0, j1 = lado, -1, lado, -1
    for i = 1, lado do
        if xs[i] >= x0 and xs[i] <= x1 then
            i0, i1 = math.min(i0, i - 1), math.max(i1, i - 1)
        end
        if ys[i] >= y0 and ys[i] <= y1 then
            j0, j1 = math.min(j0, i - 1), math.max(j1, i - 1)
        end
    end
    if i1 <= i0 or j1 <= j0 then
        return nil
    end
    local w, h = i1 - i0 + 1, j1 - j0 + 1
    local datos = love.data.newByteData(w * h * MaquetaGeometria.tamano)
    local v = ffi.cast('VerticeMaqueta*', datos:getFFIPointer())
    local ph = rej.h
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local k = (j0 + j) * lado + (i0 + i)
            local q = v[j * w + i]
            q.x, q.y, q.z = xs[i0 + i + 1] * 0.1 - ox, ys[j0 + j + 1] * 0.1 - oy, ph[k] * 0.1
            q.nx, q.ny, q.nz = 0, 0, 1
            q.u, q.v = 0, 0
        end
    end
    local caras = (w - 1) * (h - 1) * 6
    local indices = love.data.newByteData(caras * 4)
    local ind = ffi.cast('uint32_t*', indices:getFFIPointer())
    local n = 0
    for j = 0, h - 2 do
        for i = 0, w - 2 do
            local a = j * w + i
            local b, c, d = a + 1, a + w, a + w + 1
            -- Índices desde 0 (Mesh:setVertexMap con Data).
            ind[n], ind[n + 1], ind[n + 2] = a, b, d
            ind[n + 3], ind[n + 4], ind[n + 5] = a, d, c
            n = n + 6
        end
    end
    return { datos = datos, vertices = w * h, indices = indices, caras = caras }
end

-- Caminos de tierra (las calles de la mina: la batalla los pinta en el
-- terreno, batalla/color_terreno.lua, con unos 3 m de tierra a cada lado del
-- eje que se funden con la hierba hasta los 7 m).
MaquetaGeometria.medioCamino = 45 -- px
MaquetaGeometria.pasoCamino = 80 -- px entre secciones (el paso del suelo)
MaquetaGeometria.sobreCamino = 2 -- px por encima del suelo

--- Las calles del plano como cintas de tierra pegadas al suelo (datos de 12
-- números por vértice, como los sueltos del kit).
local function caminos(plano, suelo)
    local datos = {}
    local medio = MaquetaGeometria.medioCamino
    local function vertice(x, y, u, v)
        local n = #datos
        local z = suelo:altura(x, y) + MaquetaGeometria.sobreCamino
        datos[n + 1], datos[n + 2], datos[n + 3] = x * 0.1, z * 0.1, y * 0.1
        datos[n + 4], datos[n + 5], datos[n + 6] = 0, 1, 0
        datos[n + 7], datos[n + 8] = u, v
        datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = 1, 0, 0, 1
    end
    for _, c in ipairs(plano.calles) do
        local ax, ay, bx, by = c[1], c[2], c[3], c[4]
        local dx, dy = bx - ax, by - ay
        local largo = math.sqrt(dx * dx + dy * dy)
        if largo > 1 then
            local ux, uy = dx / largo, dy / largo
            local nx, ny = -uy * medio, ux * medio
            local tramos = math.max(1, math.ceil(largo / MaquetaGeometria.pasoCamino))
            for k = 0, tramos - 1 do
                local t0, t1 = k / tramos, (k + 1) / tramos
                local x0, y0 = ax + dx * t0, ay + dy * t0
                local x1, y1 = ax + dx * t1, ay + dy * t1
                local v0, v1 = largo * t0 * 0.025, largo * t1 * 0.025
                vertice(x0 - nx, y0 - ny, 0, v0)
                vertice(x1 - nx, y1 - ny, 0, v1)
                vertice(x1 + nx, y1 + ny, 1, v1)
                vertice(x0 - nx, y0 - ny, 0, v0)
                vertice(x1 + nx, y1 + ny, 1, v1)
                vertice(x0 + nx, y0 + ny, 1, v0)
            end
        end
    end
    return datos
end

local contexto


-- Dónde sale humo en el mapa (mundo/ondear.lua, Ondear.columna): de las
-- naves (la planta de la mina, los talleres) y, en la ciudad, también de
-- las azoteas de sus edificios más grandes, como sus fábricas.
MaquetaGeometria.maximoChimeneas = 6

--- Puntos de humo del plano: { { x, y, z } } en m desde el sitio (x, y), z
-- en lo alto del edificio.
function MaquetaGeometria.chimeneas(plano, x, y)
    local naves, otros = {}, {}
    for _, e in ipairs(plano.edificios) do
        if not e.patio and e.cx then
            local area = (e.hx or 0) * (e.hy or 0)
            local punto = { x = (e.cx - x) * 0.1, y = (e.cy - y) * 0.1, z = (e[5] + e[6]) * 0.1, area = area }
            if e.nave then
                naves[#naves + 1] = punto
            else
                otros[#otros + 1] = punto
            end
        end
    end
    local function mayores(a, b)
        return a.area > b.area
    end
    table.sort(naves, mayores)
    table.sort(otros, mayores)
    local lista = {}
    for _, p in ipairs(naves) do
        if #lista < MaquetaGeometria.maximoChimeneas then
            lista[#lista + 1] = { p.x, p.y, p.z }
        end
    end
    -- La ciudad: sus edificios grandes, hasta tener tres como poco.
    for _, p in ipairs(otros) do
        if #lista < 3 then
            lista[#lista + 1] = { p.x, p.y, p.z }
        end
    end
    return lista
end

--- Geometría de la maqueta de `sitio` = { tipo = 'ciudad' | 'mina', capital,
-- deposito, x, y } (punto del mapa) en el mundo de `semilla`.
function MaquetaGeometria.hacer(semilla, sitio)
    if not contexto or contexto.semilla ~= semilla then
        contexto = { semilla = semilla, terreno = Terreno.nuevo(semilla) }
    end
    local x, y = sitio.x, sitio.y
    local suelo = SueloSitio.nuevo(contexto.terreno, x, y)
    local plano = Plano.generar(suelo, {
        tipo = sitio.tipo,
        capital = sitio.capital,
        deposito = sitio.deposito,
        x = x,
        y = y,
        mapaX = x,
        mapaY = y,
    })
    if not plano then
        return nil
    end
    -- Por material: lo del kit (edificios, muro, cimientos, calles), la pista
    -- y la plataforma (sus datos, como los sueltos del kit).
    local porMaterial = KitSitio.geometria(plano, MaquetaGeometria.nivel)
    local pista = plano.pista
    local function sumar(datosPorMaterial)
        for nombre, datos in pairs(datosPorMaterial) do
            if #datos >= 36 then
                local l = porMaterial[nombre]
                if not l then
                    l = { vertices = 0, piezas = {}, sueltos = {} }
                    porMaterial[nombre] = l
                end
                l.sueltos[#l.sueltos + 1] = datos
                l.vertices = l.vertices + #datos / 12
            end
        end
    end
    if pista then
        sumar(PistaAvion.nueva(nil, nil, suelo, pista.x, pista.y, pista.rumbo, pista.medioLargo).porMaterial)
        sumar(PlataformaAvion.nueva(nil, nil, suelo, pista).porMaterial)
    end
    if #plano.calles > 0 then
        sumar({ caminoTierra = caminos(plano, suelo) })
    end
    local ox, oy = x * 0.1, y * 0.1
    local caja = nuevaCaja()
    local materiales = {}
    local total = 0
    for nombre, l in pairs(porMaterial) do
        if l.vertices >= 3 then
            local datos, n = empaquetar(l, ox, oy, caja)
            materiales[#materiales + 1] = { nombre = nombre, datos = datos, vertices = n }
            total = total + n
        end
    end
    table.sort(materiales, function(a, b)
        return a.nombre < b.nombre
    end)
    local bajo = sueloBajo(suelo, caja, MaquetaGeometria.margenSombra, ox, oy)
    if bajo then
        -- El suelo también entra en la caja (las sombras caen en él).
        local v = ffi.cast('VerticeMaqueta*', bajo.datos:getFFIPointer())
        for k = 0, bajo.vertices - 1 do
            crecer(caja, v[k].x, v[k].y, v[k].z)
        end
    end
    local resultado = {
        materiales = materiales,
        vertices = total,
        suelo = bajo,
        caja = caja,
        piezas = plano.cantidad,
        edificios = #plano.edificios,
    }
    resultado.chimeneas = MaquetaGeometria.chimeneas(plano, x, y)
    if pista then
        resultado.pista = {
            x = (pista.x - x) * 0.1,
            y = (pista.y - y) * 0.1,
            rumbo = pista.rumbo,
            medioLargo = pista.medioLargo,
        }
    end
    if plano.recinto then
        local r = plano.recinto
        resultado.recinto = { (r[1] - x) * 0.1, (r[2] - y) * 0.1, (r[3] - x) * 0.1, (r[4] - y) * 0.1 }
    end
    return resultado
end

return MaquetaGeometria

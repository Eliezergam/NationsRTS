-- Generador de comarcas: el mundo físico de un cuadrado de 8 x 8 trozos en
-- datos planos (ByteData), listos para pasar a la GPU de golpe.
--
-- No usa love.graphics: corre en los hilos de `mundo/obrero.lua` (uno por
-- núcleo) y, si no hay hilos, en el principal. Todo sale de la semilla, igual
-- que antes: las mismas alturas (`Terreno:altura`), las mismas plantas
-- (`Plantas.enTrozo`, las que ve también la batalla) y el mismo filtro de
-- plantas que `Mundo:sinPlantas`. El color del suelo y su luz los calcula la
-- GPU (`mundo/sombreado.lua`) con la altura y la pendiente de cada vértice.
--
-- Una comarca da:
--   suelo         (129 x 129 vértices) x, y, altura, nx, ny en float: la malla
--                 del suelo con todo el detalle (celdas de 32 px);
--   sueloLejos    lo mismo con un vértice de cada dos (celdas de 64 px), para
--                 los zoom bajos;
--   plantas       triángulos de todas sus plantas (x, y de la vista y color en
--                 bytes), de atrás adelante;
--   plantasLejos  las mismas plantas en su versión sencilla (`Plantas.vertices`).

local ffi = require('ffi')
local Terreno = require('mundo.terreno')
local Ciudades = require('mundo.ciudades')
local Recursos = require('mundo.recursos')
local Plantas = require('mundo.plantas')

local Generador = {}

Generador.trozos = 8 -- trozos por lado de una comarca
Generador.celdas = Terreno.celdasPorTrozo * Generador.trozos -- 128 celdas por lado
Generador.lado = Generador.celdas * Terreno.celda -- 4096 px de mundo
Generador.pasoLejos = 2 -- de lejos, un vértice de cada dos
Generador.celdasLejos = Generador.celdas / Generador.pasoLejos
Generador.numerosSuelo = 5 -- x, y, altura, nx, ny

local LADO_TROZO = Terreno.celda * Terreno.celdasPorTrozo

ffi.cdef([[
    typedef struct { float x, y; uint8_t r, g, b, a; } VerticePlanta;
]])

--- Contexto de generación de una semilla: terreno, ciudades y yacimientos
-- (cada hilo tiene el suyo; guardan su caché de regiones).
function Generador.contexto(semilla)
    local terreno = Terreno.nuevo(semilla)
    local ciudades = Ciudades.nuevo(terreno)
    terreno.ciudades = ciudades
    return { semilla = semilla, terreno = terreno, ciudades = ciudades, recursos = Recursos.nuevo(terreno, ciudades) }
end

--- Filtro de plantas del trozo (tx, ty): el mismo que `Mundo:sinPlantas`.
-- `obras` es una lista plana { x, y, r, x, y, r... } de instalaciones y
-- huertos (lo único que no sale de la semilla).
local function filtroPlantas(ctx, tx, ty, obras)
    local despejados = {}
    local cx, cy = (tx + 0.5) * LADO_TROZO, (ty + 0.5) * LADO_TROZO
    local rx0, ry0 = math.floor(cx / Recursos.region), math.floor(cy / Recursos.region)
    for dy = -1, 1 do
        for dx = -1, 1 do
            for _, d in ipairs(ctx.recursos:deRegion(rx0 + dx, ry0 + dy)) do
                despejados[#despejados + 1] = { x = d.x, y = d.y, r = 170 }
            end
        end
    end
    for k = 1, #obras, 3 do
        local x, y = obras[k], obras[k + 1]
        if math.abs(x - cx) < LADO_TROZO * 1.5 and math.abs(y - cy) < LADO_TROZO * 1.5 then
            despejados[#despejados + 1] = { x = x, y = y, r = obras[k + 2] }
        end
    end
    local ciudades = ctx.ciudades
    return function(x, y)
        for _, d in ipairs(despejados) do
            if (d.x - x) ^ 2 + (d.y - y) ^ 2 < d.r * d.r then
                return true
            end
        end
        return ciudades:dentro(x, y)
    end
end

--- Lista plana de vértices de plantas a ByteData (`VerticePlanta`).
local function empaquetarPlantas(v)
    if v.n == 0 then
        return nil
    end
    local datos = love.data.newByteData(v.n * ffi.sizeof('VerticePlanta'))
    local p = ffi.cast('VerticePlanta*', datos:getFFIPointer())
    local numeros = Plantas.numerosPorVertice
    local function byte(c)
        return math.floor(math.max(0, math.min(1, c)) * 255 + 0.5)
    end
    for k = 0, v.n - 1 do
        local i = k * numeros
        local q = p[k]
        q.x, q.y = v[i + 1], v[i + 2]
        q.r, q.g, q.b, q.a = byte(v[i + 3]), byte(v[i + 4]), byte(v[i + 5]), byte(v[i + 6])
    end
    return datos
end

--- Genera la comarca (cx, cy). Devuelve una tabla plana (se puede mandar por
-- un canal entre hilos).
function Generador.comarca(ctx, cx, cy, obras)
    local terreno = ctx.terreno
    local n = Generador.celdas
    local s = Terreno.celda
    local x0, y0 = cx * Generador.lado, cy * Generador.lado

    -- Alturas con una fila y columna de más por cada lado, para las normales.
    local ancho = n + 3
    local alturas = ffi.new('double[?]', ancho * ancho)
    local hMin, hMax = math.huge, -math.huge
    for j = -1, n + 1 do
        for i = -1, n + 1 do
            local h = terreno:altura(x0 + i * s, y0 + j * s)
            alturas[(j + 1) * ancho + i + 1] = h
            if i >= 0 and i <= n and j >= 0 and j <= n then
                hMin, hMax = math.min(hMin, h), math.max(hMax, h)
            end
        end
    end
    local function h(i, j)
        return alturas[(j + 1) * ancho + i + 1]
    end

    local function suelo(paso)
        local lado = n / paso + 1
        local datos = love.data.newByteData(lado * lado * Generador.numerosSuelo * 4)
        local f = ffi.cast('float*', datos:getFFIPointer())
        local k = 0
        for j = 0, n, paso do
            for i = 0, n, paso do
                f[k] = x0 + i * s
                f[k + 1] = y0 + j * s
                f[k + 2] = h(i, j)
                f[k + 3] = -(h(i + 1, j) - h(i - 1, j)) / (2 * s)
                f[k + 4] = -(h(i, j + 1) - h(i, j - 1)) / (2 * s)
                k = k + Generador.numerosSuelo
            end
        end
        return datos
    end

    -- Plantas, trozo a trozo en el orden en que se dibujaban (diagonales de
    -- atrás adelante) y cada trozo ordenado por dentro.
    local trozos = {}
    local t0x, t0y = cx * Generador.trozos, cy * Generador.trozos
    for ty = t0y, t0y + Generador.trozos - 1 do
        for tx = t0x, t0x + Generador.trozos - 1 do
            trozos[#trozos + 1] = { tx, ty }
        end
    end
    table.sort(trozos, function(a, b)
        if a[1] + a[2] ~= b[1] + b[2] then
            return a[1] + a[2] < b[1] + b[2]
        end
        return a[1] < b[1]
    end)
    local cerca, lejos = { n = 0 }, { n = 0 }
    local cuantas = 0
    obras = obras or {}
    for _, t in ipairs(trozos) do
        local filtro = filtroPlantas(ctx, t[1], t[2], obras)
        cuantas = cuantas + Plantas.vertices(cerca, terreno, t[1], t[2], filtro)
        Plantas.vertices(lejos, terreno, t[1], t[2], filtro, true)
    end

    return {
        cx = cx,
        cy = cy,
        semilla = ctx.semilla,
        suelo = suelo(1),
        sueloLejos = suelo(Generador.pasoLejos),
        plantas = empaquetarPlantas(cerca),
        nPlantas = cerca.n,
        plantasLejos = empaquetarPlantas(lejos),
        nPlantasLejos = lejos.n,
        cuantas = cuantas,
        hMin = hMin,
        hMax = hMax,
    }
end

-- Caché en disco -----------------------------------------------------------------------------

local CABECERA = '<c4 s4 i4 i4 i4 i4 i4 i4 d d'
local MAGIA = 'NRC1'

--- La comarca generada `r` en una cadena comprimida (con la firma de las
-- obras con que se hizo: si cambian, el archivo ya no sirve).
function Generador.empaquetar(r, firma)
    local partes = {
        love.data.pack(
            'string',
            CABECERA,
            MAGIA,
            firma,
            r.cx,
            r.cy,
            r.nPlantas,
            r.nPlantasLejos,
            r.cuantas,
            r.suelo:getSize(),
            r.hMin,
            r.hMax
        ),
        r.suelo:getString(),
        r.sueloLejos:getString(),
    }
    if r.plantas then
        partes[#partes + 1] = r.plantas:getString()
    end
    if r.plantasLejos then
        partes[#partes + 1] = r.plantasLejos:getString()
    end
    return love.data.compress('data', 'lz4', table.concat(partes))
end

--- Al revés que `empaquetar`: la comarca, o nil si el archivo es de otras
-- obras (o está roto).
function Generador.desempaquetar(datos, firma, semilla)
    local ok, texto = pcall(love.data.decompress, 'string', 'lz4', datos)
    if not ok then
        return nil
    end
    local ok2, magia, suya, cx, cy, nPlantas, nLejos, cuantas, tamSuelo, hMin, hMax, pos =
        pcall(love.data.unpack, CABECERA, texto)
    if not ok2 or magia ~= MAGIA or suya ~= firma then
        return nil
    end
    local tamPlanta = ffi.sizeof('VerticePlanta')
    local lado = Generador.celdasLejos + 1
    local tamLejos = lado * lado * Generador.numerosSuelo * 4
    local function trozo(tam)
        if tam == 0 then
            return nil
        end
        local d = love.data.newByteData(texto:sub(pos, pos + tam - 1))
        pos = pos + tam
        return d
    end
    local r = {
        cx = cx,
        cy = cy,
        semilla = semilla,
        nPlantas = nPlantas,
        nPlantasLejos = nLejos,
        cuantas = cuantas,
        hMin = hMin,
        hMax = hMax,
        disco = true,
    }
    r.suelo = trozo(tamSuelo)
    r.sueloLejos = trozo(tamLejos)
    r.plantas = trozo(nPlantas * tamPlanta)
    r.plantasLejos = trozo(nLejos * tamPlanta)
    if pos ~= #texto + 1 then
        return nil
    end
    return r
end

--- Datos de la zona (nación) (zx, zy) para la simulación: sus ciudades (la
-- más grande primero: la capital) y sus depósitos. Lo mismo que daba
-- `Mundo:datosZona`; aquí, para que lo hagan los hilos (cuesta decenas de ms).
function Generador.datosZona(ctx, zx, zy)
    local porNacion = Ciudades.porNacion
    local zona = { clave = 'z:' .. zx .. ',' .. zy, ciudades = {}, depositos = {} }
    for ry = zy * porNacion, zy * porNacion + porNacion - 1 do
        for rx = zx * porNacion, zx * porNacion + porNacion - 1 do
            local c = ctx.ciudades:deRegion(rx, ry)
            if c then
                zona.ciudades[#zona.ciudades + 1] = {
                    id = c.region,
                    nombre = c.nombre,
                    x = c.x,
                    y = c.y,
                    radio = c.radioBase or c.radio,
                    -- Su zona en la simulación (territorio): como cuando tenía calles.
                    casco = c.radioBase * Ciudades.escalaCasco,
                    altura = c.altura,
                }
            end
        end
    end
    -- Los depósitos van en regiones más pequeñas: todos los que caen dentro de la zona.
    local lado = porNacion * Ciudades.region
    local x0, y0 = zx * lado, zy * lado
    for ry = math.floor(y0 / Recursos.region), math.floor((y0 + lado - 1) / Recursos.region) do
        for rx = math.floor(x0 / Recursos.region), math.floor((x0 + lado - 1) / Recursos.region) do
            for _, d in ipairs(ctx.recursos:deRegion(rx, ry)) do
                zona.depositos[#zona.depositos + 1] = d
            end
        end
    end
    table.sort(zona.ciudades, function(a, b)
        if a.radio ~= b.radio then
            return a.radio > b.radio
        end
        return a.id < b.id
    end)
    return zona
end

return Generador

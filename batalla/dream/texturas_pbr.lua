-- Texturas PBR de la batalla (Valeria): las de Camila en assets/texturas/batalla
-- (CC0, ver su LICENCIAS.md e indice.lua), cargadas una vez por partida.
--
-- Terreno: las capas del suelo en tres ArrayImage (albedo, normal y material:
-- R metálico, G rugosidad, B oclusión), con mipmaps y filtrado anisótropo,
-- para que el sombreador (batalla/dream/terreno_pbr.lua) las lea con tres
-- muestreadores. Se guarda también el color medio (lineal) de cada capa: el
-- sombreador tiñe la textura hacia el color del mapa con él.
--
-- Rocas y árboles: cada material suelto (roca, corteza, hojas).
--
-- Altura (Fase 3 del plan de render): si está `altura.jpg` junto a los mapas
-- (tools/blender/alturas_batalla.py), va en el alfa del mapa de normales:
-- la mezcla por altura y el parallax del suelo la leen con la normal, sin
-- otro muestreador ni más memoria de vídeo. Sin el archivo, alfa 1 (plano).
--
-- Resolución: 1024 px (la de 2048 no se nota a la distancia de la cámara y
-- cuadruplica la memoria); 512 con la calidad baja.
--
-- Si faltan los archivos (una copia sin las imágenes), nada se rompe: el suelo
-- usa capas neutras (queda la paleta del mapa, sin dibujo) y `material`
-- devuelve nil (rocas, corteza y hojas siguen con sus texturas pintadas).

local ffi = require('ffi')

local TexturasPbr = {}

-- Capas del suelo, en el orden del ArrayImage (el sombreador las nombra por número).
TexturasPbr.capasTerreno = { 'hierba', 'hierbaSeca', 'barro', 'acantilado', 'arena', 'nieve', 'tierraPedregosa' }
TexturasPbr.anisotropia = 8

local indice
local guardadas = {}

local function cargarIndice()
    if not indice then
        indice = require('assets.texturas.batalla.indice')
    end
    return indice
end

--- 'media' (1024 px) o 'baja' (512 px) según la calidad de la batalla.
function TexturasPbr.resolucion(calidad)
    return (calidad and calidad.nombre == 'baja') and 'baja' or 'media'
end

--- Color medio lineal de una ImageData (en una rejilla de 64 x 64 muestras).
-- Con `conAlfa`, solo de los píxeles opacos (las hojas).
local function colorMedio(datos, conAlfa)
    local w, h = datos:getDimensions()
    local r, g, b, n = 0, 0, 0, 0
    for j = 0, 63 do
        for i = 0, 63 do
            local cr, cg, cb, ca = datos:getPixel(math.floor((i + 0.5) * w / 64), math.floor((j + 0.5) * h / 64))
            if not conAlfa or ca > 0.5 then
                r, g, b, n = r + cr ^ 2.2, g + cg ^ 2.2, b + cb ^ 2.2, n + 1
            end
        end
    end
    n = math.max(n, 1)
    return { r / n, g / n, b / n }
end

-- Nitidez de los mipmaps (sesgo negativo del nivel): con el AA temporal
-- cada píxel promedia varias posiciones, así que se puede leer un nivel más
-- fino sin que centellee, como hace Unreal con TAA y TSR. La pone
-- batalla/dream/escena.lua según la calidad (`nitidezMip`); 0 = sin sesgo.
TexturasPbr.nitidezMip = 0

local function prepararFiltro(imagen, anisotropia)
    imagen:setFilter('linear', 'linear', anisotropia or TexturasPbr.anisotropia)
    imagen:setMipmapFilter('linear', TexturasPbr.nitidezMip)
    imagen:setWrap('repeat', 'repeat')
    return imagen
end

--- Ruta del mapa de altura junto al de normales de `mapas`, si existe.
local function rutaAltura(mapas)
    local ruta = mapas.normal:gsub('normal%.jpg$', 'altura.jpg')
    if love.filesystem.getInfo(ruta, 'file') then
        return ruta
    end
    return nil
end

--- El mapa de normales de `mapas` con la altura en el alfa (si la hay).
local function normalConAltura(mapas)
    local normal = love.image.newImageData(mapas.normal)
    local ruta = rutaAltura(mapas)
    if not ruta then
        return normal, nil
    end
    local altura = love.image.newImageData(ruta)
    local ancho, alto = normal:getDimensions()
    if altura:getWidth() ~= ancho or altura:getHeight() ~= alto then
        return normal, nil
    end
    -- Las dos son rgba8 (JPEG): el rojo de la altura va al alfa de la normal.
    local n = ffi.cast('uint8_t*', normal:getFFIPointer())
    local h = ffi.cast('uint8_t*', altura:getFFIPointer())
    local suma = 0
    for k = 0, ancho * alto - 1 do
        local valor = h[k * 4]
        n[k * 4 + 3] = valor
        suma = suma + valor
    end
    altura:release()
    -- Altura media (0-1): el sombreador centra cada capa en ella.
    return normal, suma / (ancho * alto * 255)
end

--- ¿Están los tres mapas de `nombre` en la resolución `resolucion`?
local function hayMapas(nombre, resolucion)
    local ok, datos = pcall(cargarIndice)
    local m = ok and datos.materiales[nombre]
    if not m then
        return false
    end
    local mapas = m.mapas[resolucion]
    for _, ruta in pairs(mapas) do
        if not love.filesystem.getInfo(ruta, 'file') then
            return false
        end
    end
    return true
end

--- Capas neutras de 4 x 4 (albedo gris medio, normal plana, material mate):
-- el sombreador da entonces la paleta del mapa sin dibujo.
local function capasNeutras()
    local n = #TexturasPbr.capasTerreno
    local function capa(r, g, b, a)
        local datos = love.image.newImageData(4, 4)
        datos:mapPixel(function()
            return r, g, b, a
        end)
        return datos
    end
    local albedos, normales, mats, escalas, medias = {}, {}, {}, {}, {}
    for k = 1, n do
        albedos[k] = capa(0.5, 0.5, 0.5, 1)
        normales[k] = capa(0.5, 0.5, 1, 1)
        mats[k] = capa(0, 0.9, 1, 1)
        escalas[k] = 0.25
        medias[k] = { 0.5 ^ 2.2, 0.5 ^ 2.2, 0.5 ^ 2.2 }
    end
    return {
        albedo = prepararFiltro(love.graphics.newArrayImage(albedos, { mipmaps = true })),
        normal = prepararFiltro(love.graphics.newArrayImage(normales, { mipmaps = true, linear = true })),
        material = prepararFiltro(love.graphics.newArrayImage(mats, { mipmaps = true, linear = true })),
        escalas = escalas,
        medias = medias,
        neutras = true,
    }
end

--- Las capas del suelo: { albedo, normal, material (ArrayImage), escalas
-- (repeticiones por metro de cada capa), medias (color medio lineal) }.
function TexturasPbr.terreno(calidad)
    local resolucion = TexturasPbr.resolucion(calidad)
    local clave = 'terreno_' .. resolucion
    if guardadas[clave] then
        return guardadas[clave]
    end
    for _, nombre in ipairs(TexturasPbr.capasTerreno) do
        if not hayMapas(nombre, resolucion) then
            print('TEXTURAS faltan las de ' .. nombre .. ' (assets/texturas/batalla): suelo sin dibujo de foto')
            guardadas[clave] = capasNeutras()
            return guardadas[clave]
        end
    end
    local materiales = cargarIndice().materiales
    local albedos, normales, mats = {}, {}, {}
    local escalas, medias = {}, {}
    local alturas = true
    local alturasMedias = {}
    for capa, nombre in ipairs(TexturasPbr.capasTerreno) do
        local m = materiales[nombre]
        local mapas = m.mapas[resolucion]
        local datos = love.image.newImageData(mapas.albedo)
        albedos[capa] = datos
        medias[capa] = colorMedio(datos)
        normales[capa], alturasMedias[capa] = normalConAltura(mapas)
        alturas = alturas and alturasMedias[capa] ~= nil
        mats[capa] = love.image.newImageData(mapas.material)
        escalas[capa] = 1 / m.tile
    end
    local t = {
        albedo = prepararFiltro(love.graphics.newArrayImage(albedos, { mipmaps = true })),
        normal = prepararFiltro(love.graphics.newArrayImage(normales, { mipmaps = true, linear = true })),
        material = prepararFiltro(love.graphics.newArrayImage(mats, { mipmaps = true, linear = true })),
        escalas = escalas,
        medias = medias,
        -- Todas las capas traen su altura en el alfa de la normal (y su media).
        alturas = alturas,
        alturasMedias = alturas and alturasMedias or nil,
    }
    guardadas[clave] = t
    return t
end

--- Un material suelto (`roca`, `corteza`, `hojas`...): { albedo, normal,
-- material (Image), escala (repeticiones por metro), media, alfa }, o nil si
-- faltan sus archivos.
function TexturasPbr.material(nombre, calidad)
    local resolucion = TexturasPbr.resolucion(calidad)
    local clave = nombre .. '_' .. resolucion
    if guardadas[clave] ~= nil then
        return guardadas[clave] or nil
    end
    if not hayMapas(nombre, resolucion) then
        print('TEXTURAS faltan las de ' .. nombre .. ' (assets/texturas/batalla): se queda la pintada')
        guardadas[clave] = false
        return nil
    end
    local m = cargarIndice().materiales[nombre]
    local mapas = m.mapas[resolucion]
    local datos = love.image.newImageData(mapas.albedo)
    -- Los materiales sueltos (rocas, árboles) se ven pequeños: menos anisotropía.
    local aniso = 4
    local t = {
        albedo = prepararFiltro(love.graphics.newImage(datos, { mipmaps = true }), aniso),
        normal = prepararFiltro(
            love.graphics.newImage(normalConAltura(mapas), { mipmaps = true, linear = true }),
            aniso
        ),
        material = prepararFiltro(love.graphics.newImage(mapas.material, { mipmaps = true, linear = true }), aniso),
        escala = 1 / m.tile,
        media = colorMedio(datos, m.alfa),
        alfa = m.alfa,
    }
    guardadas[clave] = t
    return t
end

return TexturasPbr

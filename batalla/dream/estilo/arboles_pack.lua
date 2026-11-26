-- Árboles del pack StyleHex (FREE Stylized Forest Sample, Fab; la licencia
-- de Fab permite usarlos en el juego): los abedules y los frondosos de la
-- batalla de Unreal que le gustaron al dueño (19-nov). Geometría pasada por
-- tools/blender/arboles_stylehex.py (assets/batalla/arboles), en tres
-- detalles (LOD0, LOD2 y LOD3 del pack), con su tronco y su copa aparte.
--
-- En la batalla sustituyen a los robles (frondosos) y a los abedules de
-- antes: batalla/dream/vegetacion.lua (crearLotes) los toma de aquí.

local Geometria = require('batalla.dream.estilo.geometria')

local ArbolesPack = {}

-- Especie de la batalla -> árboles del pack (las variantes se reparten).
-- `alto`: el de medidas.lua (m); cada modelo del pack se lleva a ese alto.
local Medidas = require('medidas')
ArbolesPack.especies = {
    Roble = { tipo = 'frondoso', modelos = { 'SM_Tree_Broadleaf_1', 'SM_Tree_Broadleaf_2' }, alto = Medidas.alto.arbolFrondoso },
    Abedul = { tipo = 'abedul', modelos = { 'SM_Tree_Birch_1', 'SM_Tree_Birch_2' }, alto = Medidas.alto.abedul },
}
-- El pack mide 12-16 m; a esta escala quedan como los árboles de antes.
ArbolesPack.escala = 0.8

-- Sin el pack (la copia pública del código va sin él: licencia de Fab), los
-- árboles propios hechos por código (batalla/vegetacion.lua, PROTO.Roble y
-- PROTO.Abedul) y, sin sus arbustos y flores, el arbusto de ramas de planos
-- (Matas.arbusto) y las flores de polígonos. `respaldo`: las especies que
-- entonces se dibujan con su prototipo (batalla/dream/vegetacion.lua).
local function hay(ruta)
    return love.filesystem.getInfo(ruta, 'file') ~= nil
end
ArbolesPack.hayArboles = hay('assets/batalla/arboles/SM_Tree_Broadleaf_1.lua')
ArbolesPack.hayArbustos = hay('assets/batalla/arbustos/SM_Fol_Bush_1.lua')
ArbolesPack.respaldo = {}
if not ArbolesPack.hayArboles then
    for nombre in pairs(ArbolesPack.especies) do
        ArbolesPack.respaldo[nombre] = true
    end
    ArbolesPack.especies = {}
end

local function imagen(ruta, repetir)
    local i = love.graphics.newImage(ruta, { mipmaps = true })
    i:setMipmapFilter('linear')
    i:setFilter('linear', 'linear', 8)
    if repetir then
        i:setWrap('repeat', 'repeat')
    end
    return i
end

local function geometria(datos, dobleCara)
    local g = Geometria.nueva()
    local e = ArbolesPack.escala
    for k = 1, #datos, 24 do
        local a = { datos[k] * e, datos[k + 1] * e, datos[k + 2] * e, datos[k + 3], datos[k + 4], datos[k + 5], datos[k + 6], datos[k + 7] }
        local b = { datos[k + 8] * e, datos[k + 9] * e, datos[k + 10] * e, datos[k + 11], datos[k + 12], datos[k + 13], datos[k + 14], datos[k + 15] }
        local c = { datos[k + 16] * e, datos[k + 17] * e, datos[k + 18] * e, datos[k + 19], datos[k + 20], datos[k + 21], datos[k + 22], datos[k + 23] }
        g:triangulo(a, b, c)
        if dobleCara then
            g:triangulo(a, c, b)
        end
    end
    return g
end

--- Materiales (tronco y copa de cada tipo) con el brillo del follaje.
function ArbolesPack.materiales(dream, brillo)
    local m = {}
    if not ArbolesPack.hayArboles then
        return m
    end
    for _, tipo in ipairs({ 'abedul', 'frondoso' }) do
        m['tronco_' .. tipo] = Geometria.material(dream, 'troncoPack_' .. tipo, {
            textura = imagen('assets/batalla/arboles/tronco_' .. tipo .. '.png', true),
            rugosidad = 0.95,
        })
        m['copa_' .. tipo] = Geometria.material(dream, 'copaPack_' .. tipo, {
            textura = imagen('assets/batalla/arboles/hojas_' .. tipo .. '.png'),
            recorte = 0.5,
        })
        m['tronco_' .. tipo]:setColor(brillo, brillo, brillo, 1)
        m['copa_' .. tipo]:setColor(brillo, brillo, brillo, 1)
    end
    return m
end

--- Las mallas: [modelo][detalle 1..3] = { tronco = pieza, copa = pieza }, con
-- `malla(dream, geometria, material)` de recursos.lua.
function ArbolesPack.mallas(dream, m, malla)
    local r = {}
    for _, especie in pairs(ArbolesPack.especies) do
        for _, modelo in ipairs(especie.modelos) do
            local datos = love.filesystem.load('assets/batalla/arboles/' .. modelo .. '.lua')()
            r[modelo] = {}
            -- A su alto real (medidas.lua): el pack mide de 12 a 16 m.
            local vieja = ArbolesPack.escala
            ArbolesPack.escala = especie.alto / datos[1].alto
            for detalle = 1, 3 do
                local d = datos[detalle]
                r[modelo][detalle] = {
                    tronco = malla(dream, geometria(d.tronco, false), m['tronco_' .. especie.tipo]),
                    copa = malla(dream, geometria(d.copa, true), m['copa_' .. especie.tipo]),
                }
            end
            ArbolesPack.escala = vieja
        end
    end
    return r
end

-- Arbustos y flores del mismo pack (tools/blender/arbustos_flores_stylehex.py,
-- assets/batalla/arbustos): sustituyen a los arbustos de ramas de planos y a
-- las flores de polígonos de antes.
ArbolesPack.modelosArbusto = { 'SM_Fol_Bush_1', 'SM_Fol_Bush_2' }
ArbolesPack.modelosFlor = { 'SM_Fol_Flower_Clump_1', 'SM_Fol_Flower_Clump_2', 'SM_Fol_Flower_Clump_3' }
-- Especie de flor de la batalla -> grupo de flores del pack.
ArbolesPack.flores = { Flor1 = 1, Flor2 = 2, Flor3 = 3, Flor4 = 1 }
if not ArbolesPack.hayArbustos then
    ArbolesPack.flores = {}
end
ArbolesPack.escalaFlor = Medidas.alto.flor / 0.32 -- el pack las hace de 32 cm

local function piezas(dream, malla, modelos, material, escala)
    local r = {}
    for k, modelo in ipairs(modelos) do
        local datos = love.filesystem.load('assets/batalla/arbustos/' .. modelo .. '.lua')()
        local viejaEscala = ArbolesPack.escala
        ArbolesPack.escala = escala
        r[k] = malla(dream, geometria(datos[1], true), material)
        ArbolesPack.escala = viejaEscala
    end
    return r
end

--- Arbustos del pack: lista de piezas (malla, triangulos); nil sin el pack.
function ArbolesPack.arbustos(dream, malla, brillo)
    if not ArbolesPack.hayArbustos then
        return nil
    end
    local material = Geometria.material(dream, 'arbustoPack', {
        textura = imagen('assets/batalla/arbustos/hojas_arbusto.png'),
        recorte = 0.5,
    })
    material:setColor(brillo, brillo, brillo, 1)
    return piezas(dream, malla, ArbolesPack.modelosArbusto, material, 1), material
end

--- Flores del pack: lista de piezas (malla, triangulos); vacía sin el pack.
function ArbolesPack.floresPack(dream, malla, brillo)
    if not ArbolesPack.hayArbustos then
        return {}
    end
    local material = Geometria.material(dream, 'florPack', {
        textura = imagen('assets/batalla/arbustos/flores.png'),
        recorte = 0.5,
    })
    material:setColor(brillo, brillo, brillo, 1)
    return piezas(dream, malla, ArbolesPack.modelosFlor, material, ArbolesPack.escalaFlor), material
end

-- Restos abandonados (tools/restos_campo.py, assets/batalla/restos): especie
-- de la batalla -> modelos por variante y textura (neutra: el color lo da el
-- tono de cada copia).
-- `medida`: la de medidas.lua; `real`: lo que mide el modelo de
-- tools/restos_campo.py (largo, alto, ancho), para estirarlo a la medida.
ArbolesPack.restos = {
    Contenedor = {
        modelos = { 'contenedor', 'contenedor_abierto' }, textura = 'metal',
        escala = { Medidas.contenedor.largo / 6.058, Medidas.contenedor.alto / 2.591, Medidas.contenedor.ancho / 2.438 },
    },
    Bidon = {
        modelos = { 'bidon' }, textura = 'metal',
        escala = { Medidas.bidon.diametro / 0.585, Medidas.bidon.alto / 0.88, Medidas.bidon.diametro / 0.585 },
    },
    Caja = {
        modelos = { 'caja' }, textura = 'madera',
        escala = { Medidas.caja.largo / 1.2, Medidas.caja.alto / 0.8, Medidas.caja.ancho / 0.8 },
    },
}

--- Piezas de los restos: [especie][variante] = { malla, triangulos }.
function ArbolesPack.mallasRestos(dream, malla)
    local r = {}
    local materiales = {}
    local vieja = ArbolesPack.escala
    ArbolesPack.escala = 1
    for especie, d in pairs(ArbolesPack.restos) do
        if not materiales[d.textura] then
            materiales[d.textura] = Geometria.material(dream, 'resto_' .. d.textura, {
                textura = imagen('assets/batalla/restos/' .. d.textura .. '.png', true),
                rugosidad = d.textura == 'metal' and 0.7 or 0.95,
            })
        end
        r[especie] = {}
        for v, modelo in ipairs(d.modelos) do
            local datos = love.filesystem.load('assets/batalla/restos/' .. modelo .. '.lua')()
            -- Estirado a su medida (x largo, y alto, z ancho).
            local e = d.escala
            local copia = {}
            for k = 1, #datos, 8 do
                copia[k], copia[k + 1], copia[k + 2] = datos[k] * e[1], datos[k + 1] * e[2], datos[k + 2] * e[3]
                for f = 3, 7 do
                    copia[k + f] = datos[k + f]
                end
            end
            r[especie][v] = malla(dream, geometria(copia, false), materiales[d.textura])
        end
    end
    ArbolesPack.escala = vieja
    return r
end

return ArbolesPack

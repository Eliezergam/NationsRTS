-- Luz del cielo por imagen (IBL) de la batalla (Valeria), como el SkyLight de
-- Unreal con captura en tiempo real: el cielo (y el suelo iluminado, abajo)
-- se pinta en un cubo y de él salen
--   reflejo       cubo prefiltrado por rugosidad (GGX, split-sum de Karis), el
--                 que 3Dream lee como reflejo (nivel = rugosidad * 5)
--   irradiancia   cubo pequeño con la luz difusa (E / pi) para cada normal
--   brdf          tabla del split-sum (escala y sesgo de F0), una vez
--   horizonte     franja de rumbos con el color del cielo junto al horizonte,
--                 para la niebla (lib/3DreamEngine: setFogSky)
-- El sombreador PBR de 3Dream los usa en el suelo, las rocas, los árboles y
-- los vehículos (lib/3DreamEngine/shaders/inbuilt/PBR.lua, IBL_FISICO).
-- La fuente del cielo pinta las caras (`capturar(pintarCara)`): la atmósfera
-- de batalla/dream/atmosfera.lua.

local Atmosfera = require('batalla.dream.atmosfera')

local IBL = {}
IBL.__index = IBL

IBL.niveles = 6 -- los de 3Dream (lib.reflectionsLevels): 128, 64, 32, 16, 8 y 4 px

local enviar = Atmosfera.enviar

local function cubo(lado, mipmaps)
    local c = love.graphics.newCanvas(lado, lado, {
        type = 'cube',
        format = 'rgba16f',
        mipmaps = mipmaps and 'manual' or 'none',
        dpiscale = 1,
    })
    c:setFilter('linear', 'linear')
    if mipmaps then
        c:setMipmapFilter('linear')
    end
    return c
end

--- `opciones.lado`: px de cada cara del cubo de reflejos (128);
-- `opciones.ladoIrradiancia` (16).
function IBL.nuevo(opciones)
    opciones = opciones or {}
    local self = setmetatable({}, IBL)
    self.lado = opciones.lado or 128
    self.ladoIrradiancia = opciones.ladoIrradiancia or 16
    local cubos = { 'cubo_comun' }
    self.sombreadores = {
        prefiltro = Atmosfera.sombreador(cubos, 'ibl_prefiltro'),
        irradiancia = Atmosfera.sombreador(cubos, 'ibl_irradiancia'),
        horizonte = Atmosfera.sombreador(cubos, 'ibl_horizonte'),
        brdf = Atmosfera.sombreador(cubos, 'ibl_brdf'),
    }
    self.fuente = cubo(self.lado, true)
    self.reflejo = cubo(self.lado, true)
    self.irradiancia = cubo(self.ladoIrradiancia, false)
    self.horizonte = love.graphics.newCanvas(64, 1, { format = 'rgba16f', dpiscale = 1 })
    self.horizonte:setFilter('linear', 'linear')
    self.horizonte:setWrap('repeat', 'clamp')
    local formatos = love.graphics.getCanvasFormats()
    self.brdf = love.graphics.newCanvas(64, 64, { format = formatos.rg16f and 'rg16f' or 'rgba16f', dpiscale = 1 })
    self.brdf:setFilter('linear', 'linear')
    self.brdf:setWrap('clamp', 'clamp')
    Atmosfera.pasada(self.brdf, self.sombreadores.brdf, 64, 64)
    self.capturas = 0
    return self
end

--- Rehace todo desde la fuente: `pintarCara(cubo, cara, lado)` pinta la
-- radiancia lineal de cada cara (1 a 6) en el nivel 1 del cubo. La luz
-- difusa se multiplica por `refuerzo` (1 si no se da); los reflejos, no.
function IBL:capturar(pintarCara, refuerzo)
    local lado = self.lado
    for cara = 1, 6 do
        pintarCara(self.fuente, cara, lado)
    end
    self.fuente:generateMipmaps()
    -- Especular prefiltrado: nivel k con rugosidad k / (niveles - 1).
    local s = self.sombreadores.prefiltro
    enviar(s, 'fuente', self.fuente)
    enviar(s, 'ladoFuente', lado)
    for nivel = 1, IBL.niveles do
        local l = math.max(1, lado / 2 ^ (nivel - 1))
        enviar(s, 'rugosidad', (nivel - 1) / (IBL.niveles - 1))
        for cara = 1, 6 do
            enviar(s, 'cara', cara - 1)
            Atmosfera.pasada(self.reflejo, s, l, l, cara, nivel)
        end
    end
    -- El resto de niveles del reflejo (no se leen, pero deben existir).
    local nivelesReflejo = self.reflejo:getMipmapCount()
    for nivel = IBL.niveles + 1, nivelesReflejo do
        local l = math.max(1, lado / 2 ^ (nivel - 1))
        enviar(s, 'rugosidad', 1)
        for cara = 1, 6 do
            enviar(s, 'cara', cara - 1)
            Atmosfera.pasada(self.reflejo, s, l, l, cara, nivel)
        end
    end
    -- Irradiancia difusa desde el nivel de 8 x 8 por cara.
    s = self.sombreadores.irradiancia
    enviar(s, 'fuente', self.fuente)
    enviar(s, 'nivel', math.max(0, math.log(lado / 8) / math.log(2)))
    enviar(s, 'escala', refuerzo or 1)
    local li = self.ladoIrradiancia
    for cara = 1, 6 do
        enviar(s, 'cara', cara - 1)
        Atmosfera.pasada(self.irradiancia, s, li, li, cara, 1)
    end
    s = self.sombreadores.horizonte
    enviar(s, 'fuente', self.fuente)
    Atmosfera.pasada(self.horizonte, s, 64, 1)
    self.capturas = self.capturas + 1
end

--- Entrega a 3Dream el reflejo, la irradiancia, la tabla BRDF y la franja de
-- la niebla (antes de que se construyan sus sombreadores).
function IBL:instalar(dream)
    dream:setDefaultReflection(self.reflejo)
    dream:setIrradianceMap(self.irradiancia, self.brdf)
    dream:setFogSky(self.horizonte)
end

return IBL

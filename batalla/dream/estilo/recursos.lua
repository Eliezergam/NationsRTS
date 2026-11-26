-- Recursos del estilo de la batalla (de la prueba de Camila): texturas,
-- materiales y mallas de los pinos (completo, simplificado e impostor), las
-- rocas (tres detalles), las matas (dos detalles) y los arbustos.
--
-- Todo sale de código. Las formas de los pinos salen de la semilla del mundo
-- (`Ruido.hash`), igual en todas las máquinas; las texturas no dependen de la
-- semilla y se pintan una vez por partida en un hilo (texturas.lua). Se
-- guardan por semilla: volver a entrar en otra batalla del mismo mundo no
-- rehace nada.
--
-- Medidas de las copias (en metros, antes de la escala de cada copia): los
-- pinos miden lo que `batalla/colocacion.lua` apunta para la física
-- (ALTO_ARBOL), para que la copa dibujada y la que chocan los proyectiles
-- (batalla/impactos.lua) sean la misma.

local Ruido = require('mundo.ruido')
local Geometria = require('batalla.dream.estilo.geometria')
local Texturas = require('batalla.dream.estilo.texturas')
local Pino = require('batalla.dream.estilo.pino')
local Roca = require('batalla.dream.estilo.roca')
local Matas = require('batalla.dream.estilo.matas')
local ArbolesPack = require('batalla.dream.estilo.arboles_pack')
local Impostor = require('batalla.dream.estilo.impostor')
local TexturasPbr = require('batalla.dream.texturas_pbr')

local Recursos = {}

Recursos.variantesPino = 3 -- por especie (Pino y Abeto)
Recursos.variantesRoca = 3
-- Las 5 matas del pack StyleHex (el dueño, 19-nov: la hierba como la de
-- Unreal; Matas.mataPack).
Recursos.variantesMata = 5
Recursos.variantesArbusto = 2
-- Altura hasta la punta (m) de cada especie, la de la física.
Recursos.alturaPino = { Pino = 12.0, Abeto = 13.5 }
Recursos.brilloFollaje = 1

local registrado = false
local guardados = {}

--- Registra los sombreadores del estilo (antes de `dream:init`).
function Recursos.registrar(dream)
    if registrado then
        return
    end
    -- 3Dream hace require de las rutas con barras: que sean los mismos
    -- módulos que se configuran desde batalla/dream/escena.lua (opciones de
    -- calidad), no copias aparte.
    package.loaded['batalla/dream/estilo/follaje_sombreador'] = require('batalla.dream.estilo.follaje_sombreador')
    package.loaded['batalla/dream/estilo/roca_pbr'] = require('batalla.dream.estilo.roca_pbr')
    package.loaded['batalla/dream/viento'] = require('batalla.dream.viento')
    dream:registerShader('batalla/dream/estilo/follaje_sombreador', 'follajeEstilo')
    -- Rocas con la textura PBR de Camila, triplanar (roca_pbr.lua).
    dream:registerShader('batalla/dream/estilo/roca_pbr', 'rocaPBR')
    -- Tono por copia y viento de las instancias (batalla/dream/viento.lua).
    dream:registerShader('batalla/dream/viento', 'vientoBatalla')
    registrado = true
end

--- Empieza a pintar las texturas en un hilo (ver texturas.lua).
function Recursos.empezar()
    Texturas.empezar()
end

-- Color medio (lineal) de las texturas pintadas de antes (texturas.lua): las
-- fotos de Camila se llevan a él con el color del material (la misma paleta).
Recursos.mediaCortezaAntes = { 0.0586, 0.0163, 0.0072 }
Recursos.mediaRamaAntes = { 0.0238, 0.0355, 0.0097 }

--- Color del material que lleva una foto de media `nueva` a la media `antes`.
local function calibrar(material, antes, nueva, brillo)
    brillo = brillo or 1
    material:setColor(antes[1] / nueva[1] * brillo, antes[2] / nueva[2] * brillo, antes[3] / nueva[3] * brillo, 1)
end

--- Las dos de la hierba: con la textura del pack o, sin él, las pintadas.
local function materialesMatas(dream, texturas)
    if Matas.hayPack then
        return {
            Geometria.material(dream, 'mataSeca', { textura = Matas.texturaPack(), recorte = 0.5 }),
            Geometria.material(dream, 'mataVerde', { textura = Matas.texturaPack(), recorte = 0.5 }),
        }
    end
    return {
        Geometria.material(dream, 'mataSeca', { textura = texturas.matas[1], recorte = Texturas.corte }),
        Geometria.material(dream, 'mataVerde', { textura = texturas.matas[2], recorte = Texturas.corte }),
    }
end

local function materiales(dream, texturas)
    local brillo = Recursos.brilloFollaje
    -- Corteza de los troncos y hojas de los arbustos: las fotos PBR de Camila
    -- (assets/texturas/batalla). Las agujas de los pinos siguen pintadas: su
    -- textura de hojas es de hoja ancha.
    -- Sin sus archivos, la corteza y las hojas pintadas de siempre.
    local cortezaPbr = TexturasPbr.material('corteza')
    local hojasPbr = TexturasPbr.material('hojas')
    local m = {
        corteza = Geometria.material(dream, 'corteza', {
            textura = cortezaPbr and cortezaPbr.albedo or texturas.corteza,
            rugosidad = 0.95,
        }),
        hoja = Geometria.material(dream, 'hoja', {
            textura = hojasPbr and hojasPbr.albedo or texturas.rama,
            recorte = Texturas.corte,
            rugosidad = 1,
        }),
        rama = Geometria.material(dream, 'rama', {
            textura = texturas.rama,
            recorte = Texturas.corte,
            rugosidad = 1,
        }),
        roca = Geometria.material(dream, 'roca', { textura = texturas.roca, rugosidad = 1 }),
        matas = materialesMatas(dream, texturas),
        corte = Texturas.corte,
        brilloFollaje = brillo,
    }
    -- El tronco con la luz normal; las rocas algo hacia la cámara. En la
    -- prueba iban a 0,4 porque su cielo las blanqueaba; con la luz de la
    -- batalla (menos ambiente) salían casi negras.
    m.corteza.haciaCamara = 0
    if cortezaPbr then
        calibrar(m.corteza, Recursos.mediaCortezaAntes, cortezaPbr.media)
    end
    if hojasPbr then
        calibrar(m.hoja, Recursos.mediaRamaAntes, hojasPbr.media, brillo)
    else
        m.hoja:setColor(brillo, brillo, brillo, 1)
    end
    m.rama:setColor(brillo, brillo, brillo, 1)
    m.pack = ArbolesPack.materiales(dream, brillo)
    m.roca.haciaCamara = 0.15
    m.roca:setColor(0.72, 0.72, 0.72, 1)
    -- Roca PBR triplanar si están sus archivos; si no, la pintada de siempre.
    m.roca.texturaPbr = TexturasPbr.material('roca')
    if m.roca.texturaPbr then
        m.roca:setPixelShader('rocaPBR')
    end
    -- La textura del pack ya lleva su verde: sin el aclarado de la pintada.
    local brilloMatas = Matas.hayPack and 0.6 or 1.1
    for _, material in ipairs(m.matas) do
        material:setColor(brillo * brilloMatas, brillo * brilloMatas, brillo * brilloMatas, 1)
    end
    return m
end

-- Materiales de cerca de la vegetación (Fase 3 de PLAN-RENDER-UE.md):
-- traslucidez (la luz del sol pasa por las hojas, las agujas y la hierba al
-- contraluz: lib/3DreamEngine, TRANSLUCENCY) y viento (batalla/dream/viento.lua:
-- amplitud y alto en metros, frecuencia en radianes por segundo, aleteo de
-- las hojas en metros). Los pinos (tronco y agujas) se doblan igual.
Recursos.traslucidez = { hoja = 0.7, rama = 0.6, matas = 0.7 }
Recursos.viento = {
    rama = { clase = 1, amplitud = 0.12, alto = 12, frecuencia = 1.1, aleteo = 0.015 },
    corteza = { clase = 2, amplitud = 0.12, alto = 12, frecuencia = 1.1, aleteo = 0 },
    hoja = { clase = 3, amplitud = 0.05, alto = 1.6, frecuencia = 1.8, aleteo = 0.012 },
    matas = { clase = 4, amplitud = 0.06, alto = 0.95, frecuencia = 2.3, aleteo = 0.01 },
}
Recursos.traslucidez.matasPack = 0.6
Recursos.viento.matasPack = Recursos.viento.matas

--- La traslucidez de `material` sin cambiar su recorte de caras (los planos
-- ya llevan su cara de atrás; 3Dream la quitaría al ponerla).
local function ponerTraslucidez(material, valor)
    local caras = material.cullMode
    material:setTranslucency(valor)
    material:setCullMode(caras)
end

--- Pone la traslucidez y el viento de la calidad (`materiales` de
-- batalla/dream/calidad.lua, `opciones`) en los materiales de `r` (los de Recursos.de).
function Recursos.aplicarCalidad(r, opciones)
    opciones = opciones or {}
    local m = r.materiales
    local porNombre = {
        hoja = { m.hoja },
        rama = { m.rama, m.pack.copa_abedul, m.pack.copa_frondoso },
        matasPack = { m.pack.arbusto, m.pack.flor },
        corteza = { m.corteza, m.pack.tronco_abedul, m.pack.tronco_frondoso },
        matas = m.matas,
    }
    for nombre, lista in pairs(porNombre) do
        for _, material in ipairs(lista) do
            local traslucidez = Recursos.traslucidez[nombre]
            if traslucidez then
                ponerTraslucidez(material, opciones.translucidez and traslucidez or 0)
            end
            local viento = Recursos.viento[nombre]
            material.viento = opciones.viento and viento or nil
            material.vientoClase = viento and viento.clase or nil
        end
    end
end

--- Malla de Dream de una Geometria (en metros) y su caja en unidades de Dream.
local function malla(dream, geometria, material)
    local resultado = geometria:crearMalla(dream, material, 'follajeEstilo')
    return {
        malla = resultado,
        triangulos = geometria:triangulos(),
        caja = { geometria:caja() },
    }
end

--- Pinos de una especie: por variante, completo y simplificado (tronco y
-- follaje) e impostor.
local function pinos(dream, m, texturas, semilla, especie)
    local lista = {}
    local abeto = especie == 'Abeto'
    for v = 1, Recursos.variantesPino do
        local semillaPino = Ruido.hash(semilla, abeto and 2 or 1, v, 4111) % 100000
        local opciones = { abeto = abeto, altura = Recursos.alturaPino[especie] }
        local variante = {}
        for detalle = 1, 2 do
            local tronco, follaje = Pino.nuevo(semillaPino, detalle, opciones)
            variante[detalle] = {
                tronco = malla(dream, tronco, m.corteza),
                follaje = malla(dream, follaje, m.rama),
            }
            if detalle == 1 then
                local imagen, geometria = Impostor.hornear(tronco, follaje, texturas, m.brilloFollaje)
                local material = Geometria.material(dream, 'impostor_' .. especie .. v, {
                    textura = imagen,
                    recorte = m.corte,
                    rugosidad = 1,
                })
                material:setCullMode('none')
                material.haciaCamara = 0.8
                variante.impostor = malla(dream, geometria, material)
            end
        end
        lista[v] = variante
    end
    return lista
end

--- Los recursos de la semilla `semilla` (se hacen la primera vez).
function Recursos.de(dream, semilla)
    if guardados[semilla] then
        return guardados[semilla]
    end
    local texturas = Texturas.crear()
    local inicio = love.timer.getTime()
    local m = materiales(dream, texturas)
    local r = { texturas = texturas, materiales = m }
    r.pinos = {
        Pino = pinos(dream, m, texturas, semilla, 'Pino'),
        Abeto = pinos(dream, m, texturas, semilla, 'Abeto'),
    }
    r.arbolesPack = ArbolesPack.mallas(dream, m.pack, malla)
    r.arbustosPack, m.pack.arbusto = ArbolesPack.arbustos(dream, malla, Recursos.brilloFollaje)
    r.floresPack, m.pack.flor = ArbolesPack.floresPack(dream, malla, Recursos.brilloFollaje)
    r.restos = ArbolesPack.mallasRestos(dream, malla)
    r.rocas = {}
    for v = 1, Recursos.variantesRoca do
        r.rocas[v] = {}
        for detalle = 1, 3 do
            r.rocas[v][detalle] = malla(dream, Roca.nueva(Ruido.hash(semilla, v, 0, 4112) % 1000, 1, detalle), m.roca)
        end
    end
    r.matas = {}
    for detalle = 1, 2 do
        r.matas[detalle] = {}
        for v = 1, Recursos.variantesMata do
            if Matas.hayPack then
                local geometria = Matas.mataPack(v, detalle)
                r.matas[detalle][v] = malla(dream, geometria, m.matas[2])
            else
                local geometria = Matas.mata(Ruido.hash(semilla, v, 0, 4113) % 1000, detalle)
                r.matas[detalle][v] = malla(dream, geometria, m.matas[(v - 1) % 2 + 1])
            end
        end
    end
    r.arbustos = {}
    for v = 1, Recursos.variantesArbusto do
        if r.arbustosPack then
            -- Los del pack StyleHex (arboles_pack.lua), no los de ramas de planos.
            r.arbustos[v] = r.arbustosPack[(v - 1) % #r.arbustosPack + 1]
        else
            -- Sin el pack, los propios de ramas de planos.
            r.arbustos[v] = malla(dream, Matas.arbusto(Ruido.hash(semilla, v, 0, 4114) % 1000), m.hoja)
        end
    end
    -- Árboles muertos (Mateo): hueco temporal hasta que el módulo de Camila
    -- (`batalla/dream/estilo/arbol_seco.lua`) se enchufe aquí. Si no existe,
    -- vegetacion.lua peta en `pairs(r.muertos)`.
    r.muertos = r.muertos or {}
    print(string.format('ESTILO pinos, impostores, rocas y matas en %.2f s', love.timer.getTime() - inicio))
    guardados[semilla] = r
    return r
end

return Recursos

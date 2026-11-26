-- Oclusión ambiental y sombras de contacto de la batalla (Valeria), como en
-- Unreal: la oclusión (GTAO) solo oscurece la luz del cielo y las sombras de
-- contacto solo la del sol.
--
-- 3Dream deja en lienzos aparte la profundidad lineal y la luz del cielo de
-- cada píxel (lib/3DreamEngine: setAmbientSplit). Este módulo, llamado por
-- 3Dream tras la escena (setAOHook), calcula la GTAO a media resolución
-- (sombreadores/gtao.glsl) y la filtra (gtao_filtro.glsl). La imagen final de
-- 3Dream (shaders/code/final.glsl) hace
--   color = cielo * oclusión + (sol y demás) * contacto
-- con la oclusión escalada a resolución completa respetando los bordes y el
-- rayo de contacto hacia el sol en la profundidad de la pantalla.

local Atmosfera = require('batalla.dream.atmosfera')

local Oclusion = {}
Oclusion.__index = Oclusion

-- Por calidad (batalla/dream/calidad.lua: `oclusion`):
--   cortes, pasos   planos y muestras por lado de la GTAO
--   radio           m que mira la GTAO alrededor (Unreal: 2 m)
--   contacto        pasos del rayo de contacto (0 = sin sombras de contacto)
Oclusion.calidades = {
    media = { cortes = 1, pasos = 6, radio = 2, contacto = 0 },
    alta = { cortes = 2, pasos = 8, radio = 2, contacto = 12 },
}
Oclusion.potencia = 1 -- curva de la oclusión (XeGTAO usa 2,2; la de Unreal es suave)
Oclusion.distanciaMax = 180 -- m: más allá no hay oclusión (se apaga desde el 70 %)
Oclusion.radioMaxPx = 160
Oclusion.largoContacto = 1.5 -- m del rayo hacia el sol
Oclusion.grosorContacto = 0.6 -- m: lo que tapa más grueso que esto no cuenta
Oclusion.fuerzaContacto = 1

local enviar = Atmosfera.enviar

--- Prepara la oclusión en 3Dream (antes de `dream:init`). `nivel`: una clave
-- de `Oclusion.calidades`.
function Oclusion.nueva(dream, nivel)
    local ajustes = Oclusion.calidades[nivel]
    assert(ajustes, 'oclusión desconocida: ' .. tostring(nivel))
    local self = setmetatable({}, Oclusion)
    self.dream = dream
    self.ajustes = ajustes
    self.gtao = Atmosfera.sombreador({}, 'gtao')
    self.filtro = Atmosfera.sombreador({}, 'gtao_filtro')
    self.uniforms = {
        ao_texel = { 1, 1 },
        ao_depthParams = { 0, 1 },
        contact_light = { 0, 1, 0 },
        contact_tan = { 1, 1 },
        contact_length = Oclusion.largoContacto * 0.1,
        contact_thickness = Oclusion.grosorContacto * 0.1,
        contact_steps = math.max(1, ajustes.contacto),
        contact_strength = Oclusion.fuerzaContacto,
    }
    self.luz = { 0, 1, 0 }
    -- 3Dream reserva sus lienzos de SSAO con setAO; los de la GTAO son estos.
    dream:setAO(4, 0.5, false)
    dream:setAmbientSplit(true)
    dream:setDepthCanvasFormat('r32f')
    dream:setContactShadows(ajustes.contacto > 0)
    dream:setAOHook(function(lienzos, camara)
        self:calcular(lienzos, camara)
    end, self.uniforms)
    return self
end

--- Dirección hacia la luz principal (el sol o, de noche, la luna), Y arriba.
function Oclusion:ponerLuz(direccion, fuerza)
    self.luz[1], self.luz[2], self.luz[3] = direccion.x, direccion.y, direccion.z
    self.uniforms.contact_strength = Oclusion.fuerzaContacto * (fuerza or 1)
end

local function lienzo(ancho, alto)
    local c = love.graphics.newCanvas(ancho, alto, { format = 'rg16f', dpiscale = 1 })
    c:setFilter('linear', 'linear')
    c:setWrap('clamp', 'clamp')
    return c
end

function Oclusion:calcular(lienzos, camara)
    local ancho = math.max(1, math.floor(lienzos.width / 2))
    local alto = math.max(1, math.floor(lienzos.height / 2))
    if not self.bruto or self.bruto:getWidth() ~= ancho or self.bruto:getHeight() ~= alto then
        if self.bruto then
            self.bruto:release()
            self.filtrado:release()
        end
        self.bruto = lienzo(ancho, alto)
        self.filtrado = lienzo(ancho, alto)
    end
    local n, f = camara.near, camara.far
    local a = 2 * f * n / (f - n)
    local b = (f - n) / (f + n)
    local tanY = math.tan(camara.fov * math.pi / 360)
    local tanX = tanY * lienzos.width / lienzos.height
    local u = self.uniforms
    u.ao_texel[1], u.ao_texel[2] = 1 / ancho, 1 / alto
    u.ao_depthParams[1], u.ao_depthParams[2] = a, b
    u.contact_tan[1], u.contact_tan[2] = tanX, tanY
    -- La luz en los ejes de la vista: derecha, arriba y hacia atrás.
    local t = camara.transform
    local l = self.luz
    local cl = u.contact_light
    cl[1] = l[1] * t[1] + l[2] * t[5] + l[3] * t[9]
    cl[2] = l[1] * t[2] + l[2] * t[6] + l[3] * t[10]
    cl[3] = l[1] * t[3] + l[2] * t[7] + l[3] * t[11]

    local s = self.gtao
    local ajustes = self.ajustes
    enviar(s, 'profundidad', lienzos.depth)
    enviar(s, 'tamCompleto', { lienzos.width, lienzos.height })
    enviar(s, 'tanVista', { tanX, tanY })
    enviar(s, 'profParams', { a, b })
    enviar(s, 'radio', ajustes.radio * 0.1)
    enviar(s, 'radioMaxPx', Oclusion.radioMaxPx)
    enviar(s, 'cortes', ajustes.cortes)
    enviar(s, 'pasos', ajustes.pasos)
    enviar(s, 'potencia', Oclusion.potencia)
    enviar(s, 'distanciaMax', Oclusion.distanciaMax * 0.1)
    Atmosfera.pasada(self.bruto, s, ancho, alto)
    -- Luz rebotada (batalla/dream/rebote.lua), con la misma profundidad.
    if self.rebote then
        self.rebote:calcular(lienzos, camara, u.ao_depthParams, tanX, tanY)
    end

    love.graphics.push('all')
    love.graphics.reset()
    love.graphics.setCanvas(self.filtrado)
    love.graphics.setBlendMode('replace', 'premultiplied')
    enviar(self.filtro, 'texel', { 1 / ancho, 1 / alto })
    love.graphics.setShader(self.filtro)
    love.graphics.draw(self.bruto)
    love.graphics.pop()
    self.dream.aoTexture = self.filtrado
end

return Oclusion

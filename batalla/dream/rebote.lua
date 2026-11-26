-- Luz rebotada de pantalla de la batalla (Valeria; Fase 2 de
-- PLAN-RENDER-UE.md), un rebote de corta distancia como el de Lumen: la luz
-- que sale de lo que rodea a cada píxel (el costado al sol de un tanque, la
-- hierba iluminada) llega a sus sombras y las aclara y tiñe.
--
-- Lo calcula sombreadores/rebote.glsl a media resolución, con la integral de
-- horizontes de la GTAO, y lo filtra rebote_filtro.glsl. Lo llama
-- batalla/dream/oclusion.lua tras la GTAO (necesita la luz ambiente aparte).
-- La imagen final de 3Dream (shaders/code/final.glsl, BOUNCE) suma
-- luz ambiente * rebote, es decir, albedo * E / pi rebotada.
--
-- Rebotes múltiples, como Lumen: la luz que sale de cada punto se lee de la
-- imagen del cuadro anterior (la historia del AA temporal, que ya lleva su
-- rebote), reproyectada con la cámara de entonces como en
-- batalla/dream/temporal.lua. Así, cuadro a cuadro, la luz rebota más de una
-- vez (cada vuelta pierde el albedo: converge). Donde no coincide la
-- profundidad (lo que estaba tapado o se movió por su cuenta) o fuera de la
-- imagen anterior, se usa la escena de este cuadro (un rebote): sin estelas.

local Atmosfera = require('batalla.dream.atmosfera')

local Rebote = {}
Rebote.__index = Rebote

-- Por calidad (batalla/dream/calidad.lua: `rebote`):
--   cortes, pasos   planos y muestras por lado
--   radio           m que mira alrededor (la GTAO, 2 m; con 5 u 8 m la
--                   sombra medida apenas cambia)
--   division        resolución: 1 / division de la pantalla
Rebote.calidades = {
    media = { cortes = 1, pasos = 6, radio = 3, division = 4 },
    alta = { cortes = 2, pasos = 6, radio = 3, division = 4 },
}
Rebote.intensidad = 1 -- 1 = físico (un rebote lambertiano)
Rebote.distanciaMax = 180 -- m (como la GTAO)
Rebote.radioMaxPx = 200
-- Tope de lo rebotado respecto a la luz del cielo del píxel (evita picos
-- donde la normal de la profundidad y la del material no coinciden).
Rebote.topeRelativo = 4
-- Rebotes múltiples (con el AA temporal): tolerancia de profundidad relativa
-- y absoluta (unidades de 3Dream) para aceptar la imagen anterior.
Rebote.multiple = true
Rebote.toleranciaProf = { 0.02, 0.02 }

local enviar = Atmosfera.enviar

local function lienzo(ancho, alto)
    local c = love.graphics.newCanvas(ancho, alto, { format = 'rgba16f', dpiscale = 1 })
    c:setFilter('linear', 'linear')
    c:setWrap('clamp', 'clamp')
    return c
end

--- `nivel`: una clave de `Rebote.calidades`; `irradiancia`: el cubo de la
-- luz difusa del cielo (batalla/dream/ibl.lua); `uniforms`: los de la imagen
-- final (los de la oclusión), donde se deja la textura.
function Rebote.nuevo(dream, nivel, irradiancia, uniforms)
    local ajustes = Rebote.calidades[nivel]
    assert(ajustes, 'rebote desconocido: ' .. tostring(nivel))
    local self = setmetatable({}, Rebote)
    self.ajustes = ajustes
    self.irradiancia = irradiancia
    self.uniforms = uniforms
    self.sombreador = Atmosfera.sombreador({}, 'rebote')
    self.filtro = Atmosfera.sombreador({}, 'rebote_filtro')
    dream:setBounce(true)
    return self
end

--- La imagen anterior (`self.temporal`, el AA temporal que pone
-- batalla/dream/escena.lua) y su cámara, o la escena de este cuadro si no hay.
function Rebote:enviarHistoria(s, camara, lienzos)
    local historia, anterior
    if Rebote.multiple and self.temporal then
        historia, anterior = self.temporal:historiaPara(camara, lienzos.width, lienzos.height)
    end
    self.rebotesMultiples = historia ~= nil
    enviar(s, 'usarHistoria', historia and 1 or 0)
    enviar(s, 'historia', historia or lienzos.color)
    if anterior then
        local t = camara.transform
        enviar(s, 'camPos', { t[4], t[8], t[12] })
        enviar(s, 'antPos', anterior.pos)
        enviar(s, 'antDer', anterior.der)
        enviar(s, 'antArr', anterior.arr)
        enviar(s, 'antFre', anterior.fre)
        enviar(s, 'antTan', anterior.tan)
        enviar(s, 'toleranciaProf', Rebote.toleranciaProf)
    end
end

--- Calcula el rebote del cuadro (`profParams` y `tan`: los de la oclusión).
function Rebote:calcular(lienzos, camara, profParams, tanX, tanY)
    local division = self.ajustes.division
    local ancho = math.max(1, math.floor(lienzos.width / division))
    local alto = math.max(1, math.floor(lienzos.height / division))
    if not self.bruto or self.bruto:getWidth() ~= ancho or self.bruto:getHeight() ~= alto then
        if self.bruto then
            self.bruto:release()
            self.filtrado:release()
        end
        self.bruto = lienzo(ancho, alto)
        self.filtrado = lienzo(ancho, alto)
    end
    local t = camara.transform
    local s = self.sombreador
    local ajustes = self.ajustes
    enviar(s, 'profundidad', lienzos.depth)
    enviar(s, 'color', lienzos.color)
    enviar(s, 'irradiancia', self.irradiancia)
    enviar(s, 'tamCompleto', { lienzos.width, lienzos.height })
    enviar(s, 'tanVista', { tanX, tanY })
    enviar(s, 'profParams', profParams)
    enviar(s, 'vistaDer', { t[1], t[5], t[9] })
    enviar(s, 'vistaArr', { t[2], t[6], t[10] })
    enviar(s, 'vistaFre', { -t[3], -t[7], -t[11] })
    enviar(s, 'radio', ajustes.radio * 0.1)
    enviar(s, 'radioMaxPx', Rebote.radioMaxPx)
    enviar(s, 'cortes', ajustes.cortes)
    enviar(s, 'pasos', ajustes.pasos)
    enviar(s, 'distanciaMax', Rebote.distanciaMax * 0.1)
    enviar(s, 'intensidad', Rebote.intensidad)
    enviar(s, 'topeRelativo', Rebote.topeRelativo)
    self:enviarHistoria(s, camara, lienzos)
    Atmosfera.pasada(self.bruto, s, ancho, alto)

    love.graphics.push('all')
    love.graphics.reset()
    love.graphics.setCanvas(self.filtrado)
    love.graphics.setBlendMode('replace', 'premultiplied')
    enviar(self.filtro, 'texel', { 1 / ancho, 1 / alto })
    love.graphics.setShader(self.filtro)
    love.graphics.draw(self.bruto)
    love.graphics.pop()
    self.uniforms.canvas_bounce = self.filtrado
    self.texel = self.texel or { 0, 0 }
    self.texel[1], self.texel[2] = 1 / ancho, 1 / alto
    self.uniforms.bounce_texel = self.texel
end

return Rebote

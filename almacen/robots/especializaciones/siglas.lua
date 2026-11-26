-- Siglas de la nación en el pecho (el dueño, 17-nov: letras de plantilla de
-- su nación, en su color). El modelo trae la placa `logoPecho`, plana y con
-- UV de 0 a 1 (tools/blender/robot_almacen.py `placaSiglas`); aquí se pintan
-- las letras en un lienzo con fondo transparente y se ponen de textura con
-- recorte (lo transparente no se dibuja). Sin nación (sin partida), la placa
-- no se ve.
--
-- La escena dice de qué nación son antes de crear los robots:
-- `Siglas.nacion = { texto = 'KAL', color = { r, g, b } }`.

local dream = require('lib.3DreamEngine')

---@class Siglas : Robot
local Siglas = {}

Siglas.nacion = nil
Siglas.fuente = 'assets/fuentes/SairaStencilOne-Regular.ttf'
Siglas.ancho, Siglas.alto = 768, 256 -- px del lienzo (la placa es de 3:1)

local letras -- la fuente, cargada una vez

--- Lienzo con `texto` en `color`, centrado y llenando la placa.
local function pintar(texto, color)
    local lienzo = love.graphics.newCanvas(Siglas.ancho, Siglas.alto)
    letras = letras or love.graphics.newFont(Siglas.fuente, 230)
    local g = love.graphics
    g.push('all')
    g.origin()
    g.setCanvas(lienzo)
    g.clear(0, 0, 0, 0)
    g.setColor(color[1], color[2], color[3], 1)
    g.setFont(letras)
    local w = letras:getWidth(texto)
    local h = letras:getAscent() - letras:getDescent()
    -- Que quepa a lo ancho (con un margen) sin pasarse de alto.
    local e = math.min(1, Siglas.ancho * 0.94 / w)
    g.print(texto, Siglas.ancho / 2, Siglas.alto / 2, 0, e, e, w / 2, h / 2 + letras:getDescent() / 2)
    g.pop()
    return lienzo
end

function Siglas:onLoad()
    local placa = self:getTienePieza('logoPecho') and self:getPieza('logoPecho')
    if not placa then
        return
    end
    local nacion = Siglas.nacion
    if not (nacion and nacion.texto) then
        placa.visible = false
        return
    end
    local material = dream:newMaterial('siglasNacion')
    material:setAlbedoTexture(pintar(nacion.texto, nacion.color or { 1, 1, 1 }))
    material:setColor(1, 1, 1, 1)
    material:setRoughness(0.6)
    material:setMetallic(0)
    material:setCutout()
    for _, malla in pairs(placa.objeto and placa.objeto.meshes or {}) do
        malla:setMaterial(material)
    end
end

return Siglas

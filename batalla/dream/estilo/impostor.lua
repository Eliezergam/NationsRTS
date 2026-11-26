-- Impostor de pino: al arrancar se dibuja cada variante de pino completo en
-- proyección ortográfica a un lienzo (de lado y desde arriba) y se guarda como
-- textura recortada con mipmaps que conservan la cobertura (lienzo.lua).
--
-- La malla del impostor son dos planos verticales cruzados con la vista de
-- lado y un plano horizontal a media copa con la vista de arriba, para que
-- desde la cámara alta el bosque lejano no se vea de canto.
--
-- Textura de 256 x 256 por variante: la vista de lado ocupa la mitad
-- izquierda (128 x 256) y la de arriba el cuadro de arriba a la derecha.

local ffi = require('ffi')
local Geometria = require('batalla.dream.estilo.geometria')
local Lienzo = require('batalla.dream.estilo.lienzo')
local Texturas = require('batalla.dream.estilo.texturas')

local Impostor = {}

local ANCHO_LADO = 128
local ALTO = 256

local formato = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexNormal', 'float', 3 },
}

local sombreador

local CODIGO = [[
uniform mat4 proyeccion;
uniform float radioMaximo;
uniform float corte;
varying vec3 vNormal;
varying float vRadio;
#ifdef VERTEX
attribute vec3 VertexNormal;
vec4 position(mat4 transformacion, vec4 posicion) {
    vNormal = VertexNormal;
    vRadio = length(posicion.xz);
    return proyeccion * posicion;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla) {
    vec4 c = Texel(textura, uv);
    if (c.a < corte) {
        discard;
    }
    // Oclusión: más oscuro hacia el tronco y hacia abajo.
    float ao = 0.62 + 0.38 * clamp(vRadio / radioMaximo, 0.0, 1.0);
    float luz = 0.85 + 0.15 * clamp(vNormal.y, 0.0, 1.0);
    return vec4(c.rgb * color.rgb * ao * luz, 1.0);
}
#endif
]]

--- Malla de LÖVE de una Geometria (en metros).
local function mallaLove(geometria, textura)
    local vertices = {}
    for k = 0, geometria.cantidad - 1 do
        vertices[k + 1] = {
            geometria.posiciones[k * 3 + 1],
            geometria.posiciones[k * 3 + 2],
            geometria.posiciones[k * 3 + 3],
            geometria.uvs[k * 2 + 1],
            geometria.uvs[k * 2 + 2],
            geometria.normales[k * 3 + 1],
            geometria.normales[k * 3 + 2],
            geometria.normales[k * 3 + 3],
        }
    end
    local malla = love.graphics.newMesh(formato, vertices, 'triangles', 'static')
    malla:setTexture(textura)
    return malla
end

--- Proyección ortográfica (por filas, como la envía LÖVE con `send`).
local function ortografica(izquierda, derecha, abajo, arriba, cerca, lejos)
    local sx = 2 / (derecha - izquierda)
    local sy = 2 / (arriba - abajo)
    local sz = -2 / (lejos - cerca)
    return {
        { sx, 0, 0, -(derecha + izquierda) * sx / 2 },
        { 0, sy, 0, -(arriba + abajo) * sy / 2 },
        { 0, 0, sz, -(lejos + cerca) / (lejos - cerca) },
        { 0, 0, 0, 1 },
    }
end

--- Dibuja las mallas en un lienzo nuevo con la proyección dada y devuelve
-- su ImageData.
local function dibujar(ancho, alto, mallas, proyeccion, radio)
    local lienzo = love.graphics.newCanvas(ancho, alto, { format = 'rgba8' })
    love.graphics.push('all')
    love.graphics.setCanvas({ lienzo, depth = true })
    love.graphics.clear(0, 0, 0, 0, true, 1)
    love.graphics.setDepthMode('lequal', true)
    love.graphics.setMeshCullMode('none')
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setShader(sombreador)
    sombreador:send('proyeccion', proyeccion)
    sombreador:send('radioMaximo', radio)
    sombreador:send('corte', Texturas.corte)
    for _, m in ipairs(mallas) do
        love.graphics.setColor(m.color)
        love.graphics.draw(m.malla)
    end
    love.graphics.pop()
    return lienzo:newImageData()
end

--- Copia `datos` (ImageData) al lienzo flotante en (x0, y0). Con `voltear`,
-- da la vuelta a las filas (el lienzo de GL guarda la fila de abajo primero).
local function copiar(lienzo, datos, x0, y0, voltear)
    local ancho, alto = datos:getDimensions()
    local p = ffi.cast('uint8_t*', datos:getFFIPointer())
    for y = 0, alto - 1 do
        local fila = voltear and (alto - 1 - y) or y
        for x = 0, ancho - 1 do
            local k = (fila * ancho + x) * 4
            local d = lienzo:indice(x0 + x, y0 + y)
            lienzo.datos[d] = p[k] / 255
            lienzo.datos[d + 1] = p[k + 1] / 255
            lienzo.datos[d + 2] = p[k + 2] / 255
            lienzo.datos[d + 3] = p[k + 3] / 255
        end
    end
end

--- Medidas de la copa: radio máximo en XZ y altura máxima (m).
local function medidas(geometrias)
    local radio, altura = 0, 0
    for _, g in ipairs(geometrias) do
        for k = 0, g.cantidad - 1 do
            local x, y, z = g.posiciones[k * 3 + 1], g.posiciones[k * 3 + 2], g.posiciones[k * 3 + 3]
            radio = math.max(radio, math.sqrt(x * x + z * z))
            altura = math.max(altura, y)
        end
    end
    return radio, altura
end

--- Hornea la variante: devuelve la textura y la Geometria del impostor.
-- `tronco` y `follaje` son las Geometria del pino completo.
function Impostor.hornear(tronco, follaje, texturas, brilloFollaje)
    sombreador = sombreador or love.graphics.newShader(CODIGO)
    local radio, altura = medidas({ tronco, follaje })
    local b = brilloFollaje or 1
    local mallas = {
        { malla = mallaLove(tronco, texturas.corteza), color = { 1, 1, 1, 1 } },
        { malla = mallaLove(follaje, texturas.rama), color = { b, b, b, 1 } },
    }
    -- De lado: X a la derecha, Y arriba, se mira hacia -Z.
    local lado = dibujar(ANCHO_LADO, ALTO, mallas, ortografica(-radio, radio, 0, altura, -radio, radio), radio)
    -- Desde arriba: se gira el mundo para mirar hacia -Y (X a la derecha,
    -- -Z arriba en la imagen).
    local desdeArriba = ortografica(-radio, radio, -radio, radio, -altura - 1, 1)
    local giro = {
        { 1, 0, 0, 0 },
        { 0, 0, -1, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 0, 1 },
    }
    local proyeccionArriba = {}
    for fila = 1, 4 do
        proyeccionArriba[fila] = {}
        for columna = 1, 4 do
            local suma = 0
            for k = 1, 4 do
                suma = suma + desdeArriba[fila][k] * giro[k][columna]
            end
            proyeccionArriba[fila][columna] = suma
        end
    end
    local arriba = dibujar(ANCHO_LADO, ANCHO_LADO, mallas, proyeccionArriba, radio)

    local lienzo = Lienzo.nuevo(ANCHO_LADO * 2, ALTO, 0, 0, 0, 0)
    copiar(lienzo, lado, 0, 0, Impostor.voltear)
    copiar(lienzo, arriba, ANCHO_LADO, 0, Impostor.voltear)
    lienzo:rellenarTransparentes()
    local imagen = lienzo:imagen(Texturas.corte, false)

    -- Malla: dos planos cruzados (lado) y uno horizontal (arriba).
    local g = Geometria.nueva()
    local u1 = 0.5
    for k = 0, 1 do
        local cx, cz = math.cos(k * math.pi / 2), math.sin(k * math.pi / 2)
        g:cuadrilatero(
            { -cx * radio, 0, -cz * radio, 0, 1, 0, 0, 1 },
            { cx * radio, 0, cz * radio, 0, 1, 0, u1, 1 },
            { cx * radio, altura, cz * radio, 0, 1, 0, u1, 0 },
            { -cx * radio, altura, -cz * radio, 0, 1, 0, 0, 0 }
        )
    end
    local y = altura * 0.42
    local r = radio * 0.92
    local v1 = ANCHO_LADO / ALTO
    g:cuadrilatero(
        { -r, y, r, 0, 1, 0, 0.5, v1 },
        { r, y, r, 0, 1, 0, 1, v1 },
        { r, y, -r, 0, 1, 0, 1, 0 },
        { -r, y, -r, 0, 1, 0, 0.5, 0 }
    )
    return imagen, g, lienzo
end

-- Con la proyección propia (sin la de LÖVE para lienzos), la fila 0 del
-- ImageData es el pie del árbol: hay que dar la vuelta a las filas.
Impostor.voltear = true

return Impostor

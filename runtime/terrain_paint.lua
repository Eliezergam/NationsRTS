-- Pintura suave del terreno ("texture splatting").
--
-- Encima de las celdas de una capa de terreno puede ir una **pintura**: hasta
-- ocho texturas que se mezclan según unas máscaras de mucha más resolución que
-- la rejilla. Es lo que permite ríos, caminos y orillas con curvas en vez de
-- escalones de celda. El editor la pinta con un pincel redondo y suave; aquí
-- solo se guarda y se dibuja, y es el mismo código en el editor y en el juego.
--
-- Cómo se guarda, dentro de la capa:
--
--     layer.paint = {
--       texel = 4,                  -- píxeles de mundo por texel de máscara
--       width = 800, height = 480,  -- tamaño de la máscara en texels
--       textures = { 'assets/textures/hierba.png', 'assets/textures/agua.png' },
--       masks = { '<PNG en base64>' },   -- una máscara RGBA por cada 4 texturas
--     }
--
-- La textura `i` usa la máscara `ceil(i / 4)` y el canal `(i - 1) % 4` (r, g, b,
-- a). Cada canal es el peso de su textura en ese punto; la suma de pesos es la
-- opacidad de la pintura: donde vale 0 se ve lo que haya debajo.
--
-- Las máscaras viajan como PNG en base64 dentro del propio mapa: el mapa sigue
-- siendo un solo archivo portable, y `U.copy` las comparte sin copiarlas (las
-- cadenas de Lua no cambian), así que deshacer no cuesta memoria extra.
--
-- Las texturas se repiten por coordenada de mundo, a escala 1: la textura de
-- 256 px cubre 256 px de mundo, igual que cuando se pinta por celdas. Por eso
-- una misma textura pintada de las dos formas casa sin costura.

local Paint = {}

Paint.maxTextures = 8
Paint.channelsPerMask = 4
Paint.defaultTexel = 4

-- Lado máximo de una máscara, en texels. En mapas enormes el texel crece para
-- no pasar de aquí (2048 x 2048 x 4 bytes son 16 MB por máscara).
Paint.maxMaskSide = 2048

local SHADER = [[
uniform Image mask2;
uniform Image tex1;
uniform Image tex2;
uniform Image tex3;
uniform Image tex4;
uniform Image tex5;
uniform Image tex6;
uniform Image tex7;
uniform Image tex8;
uniform vec2 worldSize;
uniform vec2 texSize[8];

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 effect(vec4 color, Image mask1, vec2 uv, vec2 screen) {
    vec4 w1 = Texel(mask1, uv);
    vec4 w2 = Texel(mask2, uv);
    float total = dot(w1, vec4(1.0)) + dot(w2, vec4(1.0));

    if (total < 0.004) {
        discard;
    }

    vec2 world = uv * worldSize;
    vec3 c1 = Texel(tex1, world / texSize[0]).rgb;
    vec3 c2 = Texel(tex2, world / texSize[1]).rgb;
    vec3 c3 = Texel(tex3, world / texSize[2]).rgb;
    vec3 c4 = Texel(tex4, world / texSize[3]).rgb;
    vec3 c5 = Texel(tex5, world / texSize[4]).rgb;
    vec3 c6 = Texel(tex6, world / texSize[5]).rgb;
    vec3 c7 = Texel(tex7, world / texSize[6]).rgb;
    vec3 c8 = Texel(tex8, world / texSize[7]).rgb;

    // Mezcla por altura: donde dos texturas se encuentran gana la parte más
    // clara de cada una (las piedras asoman antes que la tierra entre ellas).
    // Así el borde sigue el dibujo de la textura y no es un degradado liso.
    vec4 h1 = vec4(luma(c1), luma(c2), luma(c3), luma(c4)) + 0.25;
    vec4 h2 = vec4(luma(c5), luma(c6), luma(c7), luma(c8)) + 0.25;
    vec4 b1 = w1 * h1 * h1 * h1;
    vec4 b2 = w2 * h2 * h2 * h2;
    float blended = dot(b1, vec4(1.0)) + dot(b2, vec4(1.0));

    vec3 mixed = (c1 * b1.r + c2 * b1.g + c3 * b1.b + c4 * b1.a
        + c5 * b2.r + c6 * b2.g + c7 * b2.b + c8 * b2.a) / max(blended, 0.0001);

    // El borde con lo de debajo también sigue la textura, con un poco de ruido.
    float height = (dot(w1, h1) + dot(w2, h2)) / max(total, 0.0001) - 0.25;
    float alpha = smoothstep(0.12, 0.88, min(total, 1.0) + (height - 0.5) * 0.35);

    return vec4(mixed, alpha) * color;
}
]]

local shader
local blank
local drawQuad

local function getShader()
    if shader == nil then
        local ok, result = pcall(love.graphics.newShader, SHADER)
        shader = ok and result or false
    end

    return shader or nil
end

local function blankImage()
    if not blank then
        local data = love.image.newImageData(1, 1)
        blank = love.graphics.newImage(data)
    end

    return blank
end

--- Máscara y canal de la textura número `slot` (1..8).
function Paint.slotChannel(slot)
    return math.ceil(slot / Paint.channelsPerMask), (slot - 1) % Paint.channelsPerMask + 1
end

--- Texel y tamaño de máscara para un mapa de `worldW` x `worldH` píxeles.
function Paint.sizeFor(worldW, worldH)
    local texel = Paint.defaultTexel
    local longest = math.max(worldW, worldH)

    if longest / texel > Paint.maxMaskSide then
        texel = math.ceil(longest / Paint.maxMaskSide)
    end

    return texel, math.max(1, math.ceil(worldW / texel)), math.max(1, math.ceil(worldH / texel))
end

--- Pintura vacía para un mapa.
function Paint.new(map)
    local cell = math.max(1, tonumber(map.tileSize) or 32)
    local worldW = math.max(1, tonumber(map.width) or 100) * cell
    local worldH = math.max(1, tonumber(map.height) or 60) * cell
    local texel, width, height = Paint.sizeFor(worldW, worldH)

    return { texel = texel, width = width, height = height, textures = {}, masks = {} }
end

--- PNG en base64 -> ImageData. Nil si la cadena no es una imagen.
function Paint.decodeMask(text)
    if type(text) ~= 'string' or text == '' then
        return nil
    end

    local ok, data = pcall(function()
        local bytes = love.data.decode('string', 'base64', text)
        return love.image.newImageData(love.filesystem.newFileData(bytes, 'mask.png'))
    end)

    return ok and data or nil
end

--- ImageData -> PNG en base64.
function Paint.encodeMask(data)
    return love.data.encode('string', 'base64', data:encode('png'))
end

-- Estado vivo de cada pintura: las ImageData y las Image de sus máscaras. La
-- clave es la tabla `paint` (débil), y se rehace si cambian las cadenas de las
-- máscaras, que es lo que pasa al deshacer o al cargar otro mapa.
local states = setmetatable({}, { __mode = 'k' })

local function masksKey(paint)
    local masks = paint.masks or {}
    return tostring(masks[1]) .. '|' .. tostring(masks[2])
end

local function newMaskImage(data)
    local image = love.graphics.newImage(data)
    image:setFilter('linear', 'linear')
    image:setWrap('clamp', 'clamp')
    return image
end

--- Estado vivo de una pintura: `{ data = {..}, images = {..}, dirty }`.
--
-- El editor escribe directamente en `state.data[i]` mientras pinta y marca
-- `state.dirty`; el siguiente dibujo sube los píxeles a la GPU.
function Paint.state(paint)
    local key = masksKey(paint)
    local state = states[paint]

    if state and state.key == key then
        return state
    end

    state = { key = key, data = {}, images = {}, dirty = false }
    local masks = paint.masks or {}
    local count = math.ceil(math.max(1, #(paint.textures or {})) / Paint.channelsPerMask)

    for index = 1, math.max(count, #masks) do
        local data = Paint.decodeMask(masks[index])

        if not data or data:getWidth() ~= paint.width or data:getHeight() ~= paint.height then
            data = love.image.newImageData(paint.width, paint.height)
        end

        state.data[index] = data
        state.images[index] = newMaskImage(data)
    end

    states[paint] = state
    return state
end

--- Asegura que exista la máscara número `index` (al pasar de 4 texturas).
function Paint.ensureMask(paint, index)
    local state = Paint.state(paint)

    if not state.data[index] then
        local data = love.image.newImageData(paint.width, paint.height)
        state.data[index] = data
        state.images[index] = newMaskImage(data)
    end

    return state.data[index]
end

--- Guarda las máscaras vivas en `paint.masks` (al terminar un trazo). El estado
-- se conserva: no hace falta volver a decodificar lo que ya está en memoria.
function Paint.commit(paint)
    local state = Paint.state(paint)
    paint.masks = paint.masks or {}

    for index, data in ipairs(state.data) do
        paint.masks[index] = Paint.encodeMask(data)
    end

    state.key = masksKey(paint)
end

--- Dibuja la pintura de una capa. `bounds` recorta a la vista (opcional).
function Paint.draw(map, layer, getImage, bounds)
    local paint = layer.paint

    if type(paint) ~= 'table' or type(paint.textures) ~= 'table' or #paint.textures == 0 then
        return
    end

    local program = getShader()

    if not program then
        return
    end

    local state = Paint.state(paint)

    if state.dirty then
        for index, data in ipairs(state.data) do
            state.images[index]:replacePixels(data)
        end

        state.dirty = false
    end

    local texel = paint.texel or Paint.defaultTexel
    local x0, y0, x1, y1 = 0, 0, paint.width, paint.height

    if bounds then
        x0 = math.max(0, math.floor(bounds.x / texel) - 1)
        y0 = math.max(0, math.floor(bounds.y / texel) - 1)
        x1 = math.min(paint.width, math.ceil((bounds.x + bounds.w) / texel) + 1)
        y1 = math.min(paint.height, math.ceil((bounds.y + bounds.h) / texel) + 1)
    end

    if x1 <= x0 or y1 <= y0 then
        return
    end

    local sizes = {}

    for slot = 1, Paint.maxTextures do
        local path = paint.textures[slot]
        local image = path and getImage(path)

        if image then
            image:setWrap('repeat', 'repeat')
            sizes[slot] = { image:getWidth(), image:getHeight() }
        else
            image = blankImage()
            sizes[slot] = { 1, 1 }
        end

        program:send('tex' .. slot, image)
    end

    program:send('texSize', unpack(sizes))
    program:send('worldSize', { paint.width * texel, paint.height * texel })
    program:send('mask2', state.images[2] or blankImage())

    drawQuad = drawQuad or love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    drawQuad:setViewport(x0, y0, x1 - x0, y1 - y0, paint.width, paint.height)

    local previous = love.graphics.getShader()
    love.graphics.setShader(program)
    love.graphics.setColor(1, 1, 1, layer.opacity or 1)
    love.graphics.draw(state.images[1], drawQuad, x0 * texel, y0 * texel, 0, texel, texel)
    love.graphics.setShader(previous)
    love.graphics.setColor(1, 1, 1, 1)
end

return Paint

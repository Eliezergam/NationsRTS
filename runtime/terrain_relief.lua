-- Relieve del terreno: colinas, lomas y valles con aspecto low-poly.
--
-- Una capa de terreno puede llevar un mapa de alturas (`layer.relief`). Se
-- dibuja como una malla de triángulos facetados: cada cara tiene un color plano
-- según su altura (franjas de verde a marrón) y su inclinación (las laderas
-- empinadas tiran a roca), y una luz propia según hacia dónde mira. La pintura
-- suave de la capa (caminos, ríos, arena) se pinta encima de la malla y sube y
-- baja con ella.
--
-- El juego sigue pensando en el plano: las alturas solo cambian el dibujo y el
-- ratón. Los objetos se apoyan solos en el suelo (`Relief.heightAt` se suma a
-- su `z`), y lo que va dibujado sobre el suelo (rejilla, celdas, rutas, zonas)
-- se levanta con un shader que lee la misma altura (`Relief.beginLift`).
--
-- Cómo se guarda, dentro de la capa:
--
--     layer.relief = {
--       cell = 64,          -- px de mundo entre muestras (tamaño de las facetas)
--       step = 1.5,         -- px de mundo de altura por unidad guardada
--       cols = 31, rows = 31,   -- muestras (una por esquina de faceta)
--       data = '<base64>',  -- una altura de 0 a 255 por muestra, por filas
--       seed = 1234, ...    -- lo que usó el generador (para volver a generar)
--     }
--
-- La altura en mundo es `byte * step`. Entre muestras se interpola dentro del
-- mismo triángulo que dibuja la malla, así que un objeto nunca se hunde ni
-- flota sobre una faceta.

local Projection = require('runtime.projection')

local Relief = {}

Relief.defaultCell = 48
Relief.defaultStep = 1.5

-- Franjas de color por altura (0 = valle, 1 = cima), estilo atardecer low-poly.
Relief.bands = {
    { 0.0, { 0.52, 0.64, 0.24 } },
    { 0.18, { 0.45, 0.58, 0.21 } },
    { 0.4, { 0.52, 0.53, 0.25 } },
    { 0.6, { 0.58, 0.44, 0.3 } },
    { 0.8, { 0.5, 0.35, 0.3 } },
    { 1.0, { 0.45, 0.3, 0.3 } },
}
Relief.cliff = { 0.55, 0.38, 0.28 }
-- Zócalo de los bordes del mapa (tierra) y cuánto baja por debajo del suelo.
Relief.skirt = { 0.42, 0.29, 0.24 }
Relief.skirtDepth = 48

-- Luz de la tarde: desde arriba a la izquierda de la pantalla.
local LIGHT = { -0.45, -0.55, 0.7 }
do
    local length = math.sqrt(LIGHT[1] ^ 2 + LIGHT[2] ^ 2 + LIGHT[3] ^ 2)
    LIGHT = { LIGHT[1] / length, LIGHT[2] / length, LIGHT[3] / length }
end

-- Datos ------------------------------------------------------------------------------

--- Relieve plano para un mapa.
function Relief.new(map, cell)
    cell = cell or Relief.defaultCell
    local tile = math.max(1, tonumber(map.tileSize) or 32)
    local cols = math.ceil((tonumber(map.width) or 100) * tile / cell) + 1
    local rows = math.ceil((tonumber(map.height) or 60) * tile / cell) + 1
    return {
        cell = cell,
        step = Relief.defaultStep,
        cols = cols,
        rows = rows,
        data = love.data.encode('string', 'base64', string.rep('\0', cols * rows)),
    }
end

-- Estado vivo: las alturas decodificadas (tabla de bytes) y la malla. Se rehace
-- si cambia la cadena guardada (deshacer, cargar) o la vista del mapa.
local states = setmetatable({}, { __mode = 'k' })

--- Alturas decodificadas de un relieve: `state.bytes[1 + i + j * cols]`.
function Relief.state(relief)
    local state = states[relief]
    if state and state.key == relief.data then
        return state
    end
    local raw = love.data.decode('string', 'base64', relief.data or '') or ''
    local bytes = {}
    local count = relief.cols * relief.rows
    for i = 1, count do
        bytes[i] = raw:byte(i) or 0
    end
    state = { key = relief.data, bytes = bytes, dirty = true }
    states[relief] = state
    return state
end

--- Guarda las alturas vivas en `relief.data` (al terminar de esculpir).
function Relief.commit(relief)
    local state = Relief.state(relief)
    local chars = {}
    for i, b in ipairs(state.bytes) do
        chars[i] = string.char(math.max(0, math.min(255, math.floor(b + 0.5))))
    end
    relief.data = love.data.encode('string', 'base64', table.concat(chars))
    state.key = relief.data
end

--- Marca el relieve para rehacer malla y textura en el próximo dibujo.
function Relief.touch(relief)
    Relief.state(relief).dirty = true
end

--- Primera capa del mapa con relieve, o nil.
function Relief.layerOf(map)
    if type(map) ~= 'table' then
        return nil
    end
    for _, layer in ipairs(map.layers or {}) do
        if type(layer.relief) == 'table' and layer.visible ~= false then
            return layer
        end
    end
    return nil
end

--- Altura del terreno (px de mundo) en el punto `x, y`. 0 sin relieve.
function Relief.heightAt(map, x, y)
    local layer = Relief.layerOf(map)
    if not layer then
        return 0
    end
    local relief = layer.relief
    local bytes = Relief.state(relief).bytes
    local cols, rows = relief.cols, relief.rows
    local fx, fy = x / relief.cell, y / relief.cell
    local i = math.max(0, math.min(cols - 2, math.floor(fx)))
    local j = math.max(0, math.min(rows - 2, math.floor(fy)))
    fx = math.max(0, math.min(1, fx - i))
    fy = math.max(0, math.min(1, fy - j))
    local a = bytes[1 + i + j * cols]
    local b = bytes[2 + i + j * cols]
    local c = bytes[1 + i + (j + 1) * cols]
    local d = bytes[2 + i + (j + 1) * cols]
    -- Los mismos triángulos que la malla: diagonal de a (arriba izq.) a d (abajo der.).
    local h
    if fx >= fy then
        h = a + (b - a) * fx + (d - b) * fy
    else
        h = a + (d - c) * fx + (c - a) * fy
    end
    return h * relief.step
end

--- Altura máxima del relieve del mapa (para ampliar el recorte de lo visible).
function Relief.maxHeight(map)
    local layer = Relief.layerOf(map)
    if not layer then
        return 0
    end
    local top = 0
    for _, b in ipairs(Relief.state(layer.relief).bytes) do
        if b > top then
            top = b
        end
    end
    return top * layer.relief.step
end

-- Malla ---------------------------------------------------------------------------------

local function bandColor(t)
    local bands = Relief.bands
    for k = 1, #bands - 1 do
        local a, b = bands[k], bands[k + 1]
        if t <= b[1] then
            local f = (t - a[1]) / math.max(1e-6, b[1] - a[1])
            return {
                a[2][1] + (b[2][1] - a[2][1]) * f,
                a[2][2] + (b[2][2] - a[2][2]) * f,
                a[2][3] + (b[2][3] - a[2][3]) * f,
            }
        end
    end
    return bands[#bands][2]
end

-- Variación pequeña y estable por cara, para que las facetas se distingan.
local function jitter(i, j, k)
    local n = math.sin(i * 12.9898 + j * 78.233 + k * 37.719) * 43758.5453
    return (n - math.floor(n)) * 0.08 - 0.04
end

local FORMAT = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexColor', 'byte', 4 },
    { 'Shade', 'float', 1 },
}

--- Vértices de la malla: dos triángulos por celda, con color y luz planos por cara.
-- En isométrico cada vértice va subido lo que mide su altura.
function Relief.buildVertices(map, relief, bytes, flat)
    local cols, rows, cell, step = relief.cols, relief.rows, relief.cell, relief.step
    local worldW, worldH = (cols - 1) * cell, (rows - 1) * cell
    local iso = Projection.isIso(map) and not flat
    local top = 1
    for _, b in ipairs(bytes) do
        top = math.max(top, b)
    end
    local vertices = {}
    -- Suave (por defecto): luz y color por vértice, fundidos entre triángulos.
    -- Facetas: luz y color planos por cara, el aspecto low-poly marcado.
    local smooth = relief.style ~= 'facetas'

    local function point(i, j)
        local h = bytes[1 + i + j * cols] * step
        return i * cell, j * cell, h, i, j
    end

    local function heightOf(i, j)
        i = math.max(0, math.min(cols - 1, i))
        j = math.max(0, math.min(rows - 1, j))
        return bytes[1 + i + j * cols] * step
    end

    --- Color y luz de una superficie con normal (nx, ny, nz) a una altura relativa.
    local function surface(nx, ny, nz, height, variation)
        local light = nx * LIGHT[1] + ny * LIGHT[2] + nz * LIGHT[3]
        local shade = 0.6 + 0.5 * math.max(0, light) + variation
        local color = bandColor(height)
        -- Solo las laderas de verdad empinadas tiran a roca; el resto toma el
        -- color de su franja de altura.
        local steep = math.max(0, math.min(1, (0.72 - nz) * 3))
        return color[1] + (Relief.cliff[1] - color[1]) * steep,
            color[2] + (Relief.cliff[2] - color[2]) * steep,
            color[3] + (Relief.cliff[3] - color[3]) * steep,
            shade
    end

    -- Normales por muestra (diferencias centrales), para el sombreado suave.
    local samples = {}
    if smooth then
        for j = 0, rows - 1 do
            for i = 0, cols - 1 do
                local nx = -(heightOf(i + 1, j) - heightOf(i - 1, j)) / (2 * cell)
                local ny = -(heightOf(i, j + 1) - heightOf(i, j - 1)) / (2 * cell)
                local length = math.sqrt(nx * nx + ny * ny + 1)
                local r, g, b, shade = surface(nx / length, ny / length, 1 / length, heightOf(i, j) / (top * step), 0)
                samples[1 + i + j * cols] = { r, g, b, shade }
            end
        end
    end

    local function face(i, j, k, p1, p2, p3)
        local ux, uy, uz = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
        local vx, vy, vz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]
        -- Normal hacia arriba (z) en un mundo con y hacia abajo.
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        if nz < 0 then
            nx, ny, nz = -nx, -ny, -nz
        end
        local length = math.max(1e-6, math.sqrt(nx * nx + ny * ny + nz * nz))
        nx, ny, nz = nx / length, ny / length, nz / length
        local height = (p1[3] + p2[3] + p3[3]) / 3 / (top * step)
        local r, g, b, shade = surface(nx, ny, nz, height, jitter(i, j, k))
        for _, p in ipairs({ p1, p2, p3 }) do
            local x, y = p[1], p[2]
            if iso then
                -- Subir en la vista `lift` px es mover (-lift, -lift) en el mundo.
                local lift = Projection.lift(map, p[3])
                x, y = x - lift, y - lift
            end
            local vr, vg, vb, vshade = r, g, b, shade
            if smooth then
                local sample = samples[1 + p[4] + p[5] * cols]
                vr, vg, vb, vshade = sample[1], sample[2], sample[3], sample[4]
            end
            vertices[#vertices + 1] = { x, y, p[1] / worldW, p[2] / worldH, vr, vg, vb, 1, vshade }
        end
    end

    -- Zócalo de tierra en los bordes, como una maqueta: va primero para que el
    -- terreno lo tape donde queda por detrás.
    if iso then
        local depth = Relief.skirtDepth
        local function wall(p1, p2, shade)
            local quad = {
                { p1[1], p1[2], p1[3] },
                { p2[1], p2[2], p2[3] },
                { p2[1], p2[2], -depth },
                { p1[1], p1[2], -depth },
            }
            for _, index in ipairs({ 1, 2, 3, 1, 3, 4 }) do
                local q = quad[index]
                local lift = Projection.lift(map, q[3])
                local sr, sg, sb = Relief.skirt[1], Relief.skirt[2], Relief.skirt[3]
                -- Luz negativa: el shader la toma como "sin pintura" (el zócalo es tierra).
                vertices[#vertices + 1] =
                    { q[1] - lift, q[2] - lift, q[1] / worldW, q[2] / worldH, sr, sg, sb, 1, -shade }
            end
        end
        for i = 0, cols - 2 do
            wall({ point(i, rows - 1) }, { point(i + 1, rows - 1) }, 0.8)
            wall({ point(i, 0) }, { point(i + 1, 0) }, 0.6)
        end
        for j = 0, rows - 2 do
            wall({ point(cols - 1, j) }, { point(cols - 1, j + 1) }, 0.62)
            wall({ point(0, j) }, { point(0, j + 1) }, 0.6)
        end
    end

    for j = 0, rows - 2 do
        for i = 0, cols - 2 do
            local a = { point(i, j) }
            local b = { point(i + 1, j) }
            local c = { point(i, j + 1) }
            local d = { point(i + 1, j + 1) }
            face(i, j, 1, a, b, d)
            face(i, j, 2, a, d, c)
        end
    end
    return vertices
end

local SHADER = [[
#pragma language glsl3
varying float vShade;
#ifdef VERTEX
attribute float Shade;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vShade = Shade;
    return transform_projection * vertex_position;
}
#endif
#ifdef PIXEL
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
uniform float hasPaint;

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 effect(vec4 color, Image mask1, vec2 uv, vec2 screen) {
    float shade = abs(vShade);
    vec3 base = color.rgb * shade;
    if (hasPaint < 0.5 || vShade < 0.0) {
        return vec4(base, 1.0);
    }
    vec4 w1 = Texel(mask1, uv);
    vec4 w2 = Texel(mask2, uv);
    float total = dot(w1, vec4(1.0)) + dot(w2, vec4(1.0));
    if (total < 0.004) {
        return vec4(base, 1.0);
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
    vec4 h1 = vec4(luma(c1), luma(c2), luma(c3), luma(c4)) + 0.25;
    vec4 h2 = vec4(luma(c5), luma(c6), luma(c7), luma(c8)) + 0.25;
    vec4 b1 = w1 * h1 * h1 * h1;
    vec4 b2 = w2 * h2 * h2 * h2;
    float blended = dot(b1, vec4(1.0)) + dot(b2, vec4(1.0));
    vec3 mixed = (c1 * b1.r + c2 * b1.g + c3 * b1.b + c4 * b1.a
        + c5 * b2.r + c6 * b2.g + c7 * b2.b + c8 * b2.a) / max(blended, 0.0001);
    float height = (dot(w1, h1) + dot(w2, h2)) / max(total, 0.0001) - 0.25;
    float alpha = smoothstep(0.12, 0.88, min(total, 1.0) + (height - 0.5) * 0.35);
    // La pintura toma la luz de la cara: un camino en una ladera en sombra se oscurece.
    return vec4(mix(base, mixed * shade, alpha), 1.0);
}
#endif
]]

local LIFT_SHADER = [[
#pragma language glsl3
uniform Image heightTex;
uniform vec2 heightSize;
uniform float cell;
uniform float step;
uniform float liftScale;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec2 uv = (vertex_position.xy / cell + 0.5) / heightSize;
    float h = Texel(heightTex, uv).r * 255.0 * step;
    vertex_position.xy -= vec2(h * liftScale);
    return transform_projection * vertex_position;
}
]]

local meshShader, liftShader, blank

local function getShaders()
    if meshShader == nil then
        local ok, result = pcall(love.graphics.newShader, SHADER)
        meshShader = ok and result or false
        if not ok then
            print('relieve: ' .. tostring(result))
        end
        ok, result = pcall(love.graphics.newShader, LIFT_SHADER)
        liftShader = ok and result or false
    end
    return meshShader or nil, liftShader or nil
end

local function blankImage()
    if not blank then
        blank = love.graphics.newImage(love.image.newImageData(1, 1))
    end
    return blank
end

--- Malla y textura de alturas al día para la vista pedida.
local function prepare(map, relief, flat)
    local state = Relief.state(relief)
    local mode = (Projection.isIso(map) and not flat) and 'iso' or 'top'
    if state.dirty or not state.meshes then
        state.meshes = {}
        state.dirty = false
        local data = love.image.newImageData(relief.cols, relief.rows)
        for j = 0, relief.rows - 1 do
            for i = 0, relief.cols - 1 do
                data:setPixel(i, j, state.bytes[1 + i + j * relief.cols] / 255, 0, 0, 1)
            end
        end
        state.heightImage = love.graphics.newImage(data)
        state.heightImage:setFilter('linear', 'linear')
    end
    if not state.meshes[mode] then
        local vertices = Relief.buildVertices(map, relief, state.bytes, mode == 'top')
        state.meshes[mode] = love.graphics.newMesh(FORMAT, vertices, 'triangles', 'static')
    end
    return state.meshes[mode], state
end

--- Dibuja el relieve de una capa, con su pintura encima. Con la transformación
-- de mundo puesta. `flat` lo dibuja sin subir los vértices (minimapa desde arriba).
function Relief.draw(map, layer, getImage, flat)
    local relief = layer.relief
    local shader = getShaders()
    if not shader then
        return
    end
    local mesh = prepare(map, relief, flat)
    local paint = layer.paint
    local hasPaint = type(paint) == 'table' and type(paint.textures) == 'table' and #paint.textures > 0
    shader:send('hasPaint', hasPaint and 1 or 0)
    shader:send('worldSize', { (relief.cols - 1) * relief.cell, (relief.rows - 1) * relief.cell })
    local sizes = {}
    local Paint = require('runtime.terrain_paint')
    local paintState = hasPaint and Paint.state(paint) or nil
    if paintState and paintState.dirty then
        for index, data in ipairs(paintState.data) do
            paintState.images[index]:replacePixels(data)
        end
        paintState.dirty = false
    end
    for slot = 1, 8 do
        local path = hasPaint and paint.textures[slot]
        local image = path and getImage(path)
        if image then
            image:setWrap('repeat', 'repeat')
            sizes[slot] = { image:getWidth(), image:getHeight() }
        else
            image = blankImage()
            sizes[slot] = { 1, 1 }
        end
        shader:send('tex' .. slot, image)
    end
    shader:send('texSize', unpack(sizes))
    shader:send('mask2', paintState and paintState.images[2] or blankImage())
    -- La máscara de la pintura cubre su propio tamaño: la malla usa la misma
    -- escala (UV = mundo / tamaño del relieve), así que se ajustan igual cuando
    -- el relieve y la pintura miden lo mismo; si no, la pintura manda en su
    -- tamaño a través del mundo.
    mesh:setTexture(paintState and paintState.images[1] or blankImage())
    local previous = love.graphics.getShader()
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, layer.opacity or 1)
    love.graphics.draw(mesh)
    love.graphics.setShader(previous)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Desde aquí, lo que se dibuje en coordenadas de mundo se levanta con el
-- relieve (rejilla, celdas, rutas, zonas). Devuelve true si hay relieve.
function Relief.beginLift(map)
    local layer = Projection.isIso(map) and Relief.layerOf(map)
    if not layer then
        return false
    end
    local _, lift = getShaders()
    if not lift then
        return false
    end
    local relief = layer.relief
    local _, state = prepare(map, relief)
    lift:send('heightTex', state.heightImage)
    lift:send('heightSize', { relief.cols, relief.rows })
    lift:send('cell', relief.cell)
    lift:send('step', relief.step)
    lift:send('liftScale', Projection.heightScale)
    love.graphics.setShader(lift)
    return true
end

function Relief.endLift()
    love.graphics.setShader()
end

return Relief

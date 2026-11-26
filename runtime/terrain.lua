-- Terreno por celdas, dibujado en bloques con `SpriteBatch` (fase 8, bloque 3).
--
-- Hasta la fase 8 `T.draw` recorría **todas** las celdas de la capa en cada
-- cuadro y hacía un `love.graphics.draw` por celda visible. En un mapa de guerra
-- eso son cientos de miles de iteraciones y miles de llamadas de dibujo por
-- cuadro. Ahora las celdas se agrupan en bloques de `T.chunkCells` por lado y
-- cada bloque guarda un `SpriteBatch` por imagen; dibujar un bloque es una sola
-- llamada por imagen, y solo se reconstruye el bloque que cambia al pintar.
--
-- **El resultado es idéntico al anterior**, no parecido:
--
--   * cada celda se dibuja en `(x * celda, y * celda)` con escala
--     `celda / ancho_imagen`, exactamente como antes, así que ocupa su casilla
--     y nada más;
--   * las celdas nunca se solapan, de modo que agruparlas por imagen no puede
--     cambiar lo que se ve (el código anterior las recorría con `pairs`, o sea
--     en orden imprevisible, lo que ya demostraba que el orden no importa);
--   * la opacidad de la capa se aplica igual, con el color antes de dibujar;
--   * las coordenadas negativas se reparten con `math.floor`, igual que las
--     celdas, así que la celda -1 cae en el bloque -1 y no en el 0.
--
-- La única diferencia es que un bloque se dibuja entero aunque solo se vea una
-- esquina: las celdas que sobran caen fuera del recorte de la vista y no se ven.
--
-- El caché vive aquí, en una tabla de claves débiles indexada por la capa. No se
-- guarda nada en el mapa: los `SpriteBatch` son objetos de LÖVE y el mapa tiene
-- que seguir siendo datos portables que se serializan.

local T = {}

-- Lado del bloque, en celdas. Con la celda de 32 por defecto son 512 píxeles,
-- el mismo tamaño que el cubo del índice espacial.
T.chunkCells = 16

function T.size(map)
    return math.max(1, tonumber(map.tileSize) or 32)
end
function T.cell(map, x, y)
    local s = T.size(map)
    return math.floor(x / s), math.floor(y / s)
end

--- Lado del bloque en unidades de mundo.
function T.chunkSize(map)
    return T.size(map) * T.chunkCells
end

-- Medidas del último `T.draw`, para las pruebas de rendimiento.
T.lastDraw = { chunks = 0, batches = 0, tiles = 0, rebuilt = 0, scanned = 0 }

local caches = setmetatable({}, { __mode = 'k' })

local function cellKey(cx, cy)
    return cx .. ',' .. cy
end

-- Recorte de una imagen por celdas ------------------------------------------------
--
-- Una celda puede guardar la imagen entera (`{x=,y=,asset=}`, el formato de
-- siempre) o **un trozo** de ella (`{x=,y=,asset=,col=,row=}`): la casilla
-- `col,row` de la imagen, contando en celdas desde la esquina superior
-- izquierda. Es lo que permite repartir una pieza de 3x3 en sus nueve celdas o
-- que un terreno automático saque sus bordes de una hoja de 4x4.
--
-- La rejilla de la imagen **no se guarda en la celda**: se deduce dividiendo la
-- imagen entre el tamaño de celda del mapa y redondeando al número entero de
-- columnas más cercano. Con una imagen que mide un múltiplo exacto de la celda
-- —que es lo único que la paleta admite como pieza— el resultado es exacto y el
-- trozo se dibuja a escala 1. Si después se cambia `map.tileSize`, la imagen se
-- reparte igualmente en ese mismo número de columnas y cada trozo se escala a la
-- celda nueva, que es exactamente lo que ya hacía una celda con la imagen
-- entera. Así una celda nunca depende de datos que no lleva dentro.

--- Columnas, filas y tamaño de cada trozo de `image` para una celda de `s`.
function T.grid(image, s)
    local iw, ih = image:getWidth(), image:getHeight()
    s = math.max(1, s or 1)
    local cols = math.max(1, math.floor(iw / s + 0.5))
    local rows = math.max(1, math.floor(ih / s + 0.5))
    return cols, rows, iw / cols, ih / rows
end

--- ¿La imagen mide un número entero de celdas y ocupa más de una? Es la
-- condición para ofrecerla como pieza en la paleta.
function T.isPiece(image, s)
    s = math.max(1, s or 1)
    local iw, ih = image:getWidth(), image:getHeight()
    if iw % s ~= 0 or ih % s ~= 0 then
        return false
    end
    local cols, rows = iw / s, ih / s
    if cols < 1 or rows < 1 or (cols == 1 and rows == 1) then
        return false
    end
    return true, cols, rows
end

-- Los `Quad` se reutilizan: crear uno por celda y por reconstrucción tiraría a
-- la basura miles de objetos al pintar. Claves débiles por imagen, y dentro por
-- tamaño de celda y casilla.
local quadCaches = setmetatable({}, { __mode = 'k' })

local function quadFor(image, s, col, row)
    local byImage = quadCaches[image]
    if not byImage then
        byImage = {}
        quadCaches[image] = byImage
    end
    local byCell = byImage[s]
    if not byCell then
        byCell = {}
        byImage[s] = byCell
    end
    local key = col .. ',' .. row
    local quad = byCell[key]
    if not quad then
        local cols, rows, sw, sh = T.grid(image, s)
        -- Una casilla fuera de la imagen se recorta a la más cercana que existe.
        -- Un `Quad` fuera de la textura no falla, pero dibuja lo que diga el modo
        -- de repetición, que sería basura distinta en el editor y en el juego.
        local c = math.max(0, math.min(cols - 1, math.floor(col)))
        local r = math.max(0, math.min(rows - 1, math.floor(row)))
        quad = love.graphics.newQuad(c * sw, r * sh, sw, sh, image:getWidth(), image:getHeight())
        byCell[key] = quad
    end
    return quad
end

T.quadFor = quadFor

--- Baldosa alta: una imagen más alta que ancha pintada entera en una celda.
-- La base es el cuadrado de abajo (ancho x ancho) y lo que queda encima es lo
-- que sobresale (copas, picos). Devuelve los dos `Quad` (el de arriba es nil si
-- la imagen es cuadrada) y el alto del saliente en píxeles de la imagen.
local tallQuads = setmetatable({}, { __mode = 'k' })

local function tallQuadsFor(image)
    local cached = tallQuads[image]

    if cached then
        return cached.base, cached.top, cached.topHeight
    end

    local iw, ih = image:getWidth(), image:getHeight()
    local side = math.min(iw, ih)
    local topHeight = ih - side
    local base = love.graphics.newQuad(0, topHeight, iw, side, iw, ih)
    local top = nil

    if topHeight > 0 then
        top = love.graphics.newQuad(0, 0, iw, topHeight, iw, ih)
    end

    tallQuads[image] = { base = base, top = top, topHeight = topHeight }
    return base, top, topHeight
end

T.tallQuadsFor = tallQuadsFor

-- Cuánto invade una baldosa alta a sus vecinas (fracción de la celda). Estos
-- packs pintan un reborde en cada baldosa; solapar un poco lo tapa con la
-- vecina y el terreno se lee continuo en vez de como un tablero.
T.tallOverlap = 0.07

--- ¿Esta imagen se pinta como baldosa alta? Más alta que ancha en más de un 5 %.
function T.isTallImage(image)
    return image ~= nil and image:getHeight() > image:getWidth() * 1.05
end

--- Casilla de una celda, o nil si la celda lleva la imagen entera.
function T.cellQuadIndex(tile)
    if type(tile) ~= 'table' then
        return nil
    end
    local col, row = tonumber(tile.col), tonumber(tile.row)
    if not col or not row then
        return nil
    end
    return math.floor(col), math.floor(row)
end

local function chunkOf(entry, cx, cy)
    local n = entry.chunkCells
    return math.floor(cx / n), math.floor(cy / n)
end

local function newChunk(entry, chx, chy)
    local column = entry.chunks[chx]
    if not column then
        column = {}
        entry.chunks[chx] = column
    end
    local chunk = { chx = chx, chy = chy, cells = {}, batches = {}, order = {}, dirty = true, count = 0 }
    column[chy] = chunk
    if not entry.minChx or chx < entry.minChx then
        entry.minChx = chx
    end
    if not entry.maxChx or chx > entry.maxChx then
        entry.maxChx = chx
    end
    if not entry.minChy or chy < entry.minChy then
        entry.minChy = chy
    end
    if not entry.maxChy or chy > entry.maxChy then
        entry.maxChy = chy
    end
    return chunk
end

--- Reparte las celdas de la capa en bloques. Es el único recorrido completo de
-- la lista de celdas, y solo ocurre cuando la capa es nueva, cuando el mapa se
-- sustituye entero (deshacer, cargar) o cuando cambia el tamaño de celda.
local function scan(layer, map)
    local entry = {
        tiles = layer.tiles,
        cell = T.size(map),
        chunkCells = T.chunkCells,
        chunks = {},
        count = 0,
    }
    for _, tile in pairs(layer.tiles or {}) do
        if type(tile) == 'table' then
            local cx, cy = math.floor(tonumber(tile.x) or 0), math.floor(tonumber(tile.y) or 0)
            local chx, chy = chunkOf(entry, cx, cy)
            local column = entry.chunks[chx]
            local chunk = column and column[chy]
            if not chunk then
                chunk = newChunk(entry, chx, chy)
            end
            chunk.cells[cellKey(cx, cy)] = tile
            entry.count = entry.count + 1
        end
    end
    caches[layer] = entry
    return entry
end

local function cacheFor(layer, map)
    local entry = caches[layer]
    if entry and entry.tiles == layer.tiles and entry.cell == T.size(map) and entry.chunkCells == T.chunkCells then
        return entry
    end
    return scan(layer, map)
end

--- Rehace los lotes de un bloque. Se agrupa por imagen porque un `SpriteBatch`
-- tiene una sola textura; el orden entre imágenes se fija alfabéticamente para
-- que el resultado no dependa del recorrido de la tabla.
local function rebuild(entry, chunk, getImage)
    local s = entry.cell
    -- Tres listas de lotes, dibujadas en este orden:
    --   bases     la celda (entera, recorte o base de una baldosa alta);
    --   overlays  capas encima de la celda (`tile.over`: ríos, costas);
    --   tops      lo que sobresale de las baldosas altas, en una pasada aparte
    --             (`T.draw`) para que tape la fila de arriba.
    local layers = {
        { key = 'batches', orderKey = 'order', groups = {}, order = {} },
        { key = 'overlayBatches', orderKey = 'overlayOrder', groups = {}, order = {} },
        { key = 'topBatches', orderKey = 'topOrder', groups = {}, order = {} },
    }
    local missing = false
    local count = 0

    local function push(layer, asset, image, item)
        local group = layer.groups[asset]

        if not group then
            group = { image = image, items = {} }
            layer.groups[asset] = group
            layer.order[#layer.order + 1] = asset
        end

        group.items[#group.items + 1] = item
    end

    for _, tile in pairs(chunk.cells) do
        local asset = tile.asset
        local image = asset and getImage(asset)

        if image then
            local tall = tile.tall and T.cellQuadIndex(tile) == nil and T.isTallImage(image)
            push(layers[1], asset, image, { tile = tile, part = tall and 'base' or 'cell' })

            if tall then
                push(layers[3], asset, image, { tile = tile, part = 'top' })
            end

            count = count + 1
        elseif asset then
            -- La imagen todavía no está cargada: el bloque se rehace hasta que lo esté.
            missing = true
        end

        if type(tile.over) == 'table' then
            for _, over in ipairs(tile.over) do
                local overImage = type(over) == 'table' and over.asset and getImage(over.asset)

                if overImage then
                    push(layers[2], over.asset, overImage, { tile = tile, over = over, part = 'over' })
                elseif type(over) == 'table' and over.asset then
                    missing = true
                end
            end
        end
    end

    for _, layer in ipairs(layers) do
        local batches = chunk[layer.key] or {}
        chunk[layer.key] = batches
        table.sort(layer.order)

        for asset, group in pairs(layer.groups) do
            local batch = batches[asset]
            local image = group.image

            if not batch then
                batch = love.graphics.newSpriteBatch(image, math.max(1, #group.items))
                batches[asset] = batch
            else
                batch:clear()
                batch:setTexture(image)
            end

            local iw, ih = image:getWidth(), image:getHeight()
            local sx, sy = s / iw, s / ih
            -- Un solo lote por textura aunque la capa mezcle celdas enteras y
            -- recortes: `SpriteBatch:add` acepta las dos formas y cada sprite se
            -- queda con las coordenadas de textura que le tocan.
            local _, _, qw, qh = T.grid(image, s)
            local qsx, qsy = s / qw, s / qh

            for _, item in ipairs(group.items) do
                local tile = item.tile
                local cx, cy = tile.x * s + s / 2, tile.y * s + s / 2

                if item.part == 'cell' then
                    local col, row = T.cellQuadIndex(tile)
                    -- `rot` (0/90/180/270) y `flip` giran y voltean la celda sobre su centro.
                    local r = math.rad(tonumber(tile.rot) or 0)
                    local fx = tile.flip and -1 or 1

                    if col then
                        batch:add(quadFor(image, s, col, row), cx, cy, r, qsx * fx, qsy, qw / 2, qh / 2)
                    else
                        batch:add(cx, cy, r, sx * fx, sy, iw / 2, ih / 2)
                    end
                elseif item.part == 'base' then
                    local base = tallQuadsFor(image)
                    local k = s / iw * (1 + T.tallOverlap)
                    local fx = tile.flip and -1 or 1
                    batch:add(base, cx, cy, 0, k * fx, k, iw / 2, iw / 2)
                elseif item.part == 'top' then
                    local _, top, topHeight = tallQuadsFor(image)
                    local k = s / iw * (1 + T.tallOverlap)
                    local fx = tile.flip and -1 or 1
                    -- El saliente se apoya en el borde superior de la base (que
                    -- sobresale media invasión por encima de la celda).
                    batch:add(top, cx, tile.y * s - s * T.tallOverlap / 2, 0, k * fx, k, iw / 2, topHeight)
                else
                    -- Capa encima: si la imagen es alta se usa su base; gira sobre el centro.
                    local over = item.over
                    local r = math.rad(tonumber(over.rot) or 0)
                    local fx = over.flip and -1 or 1

                    if T.isTallImage(image) then
                        local base = tallQuadsFor(image)
                        local k = s / iw
                        batch:add(base, cx, cy, r, k * fx, k, iw / 2, iw / 2)
                    else
                        batch:add(cx, cy, r, sx * fx, sy, iw / 2, ih / 2)
                    end
                end
            end
        end

        for asset in pairs(batches) do
            if not layer.groups[asset] then
                batches[asset] = nil
            end
        end

        chunk[layer.orderKey] = layer.order
    end

    chunk.count = count
    chunk.dirty = missing
    chunk.empty = next(chunk.cells) == nil
    T.lastDraw.rebuilt = T.lastDraw.rebuilt + 1
end

--- Marca una celda como cambiada. `tile` es la celda nueva, o `nil` si se borró.
-- La llama el editor al pintar: es lo que permite rehacer un bloque de 256
-- celdas en vez de los cientos de miles del mapa.
function T.invalidate(layer, cx, cy, tile)
    local entry = caches[layer]
    if not entry then
        return
    end
    if entry.tiles ~= layer.tiles then
        caches[layer] = nil
        return
    end
    local chx, chy = chunkOf(entry, cx, cy)
    local column = entry.chunks[chx]
    local chunk = column and column[chy]
    if not chunk then
        if tile == nil then
            return
        end
        chunk = newChunk(entry, chx, chy)
    end
    local key = cellKey(cx, cy)
    if chunk.cells[key] == nil and tile ~= nil then
        entry.count = entry.count + 1
    elseif chunk.cells[key] ~= nil and tile == nil then
        entry.count = entry.count - 1
    end
    chunk.cells[key] = tile
    chunk.dirty = true
    chunk.empty = false
end

--- Tira el caché entero de una capa.
function T.invalidateLayer(layer)
    caches[layer] = nil
end

function T.cacheFor(layer, map)
    return cacheFor(layer, map)
end

local function drawTiles(map, layer, getImage, bounds)
    local stats = T.lastDraw
    stats.chunks, stats.batches, stats.tiles, stats.rebuilt, stats.scanned = 0, 0, 0, 0, 0
    if type(layer.tiles) ~= 'table' then
        return
    end
    local entry = cacheFor(layer, map)
    if not entry.minChx then
        return
    end

    local side = entry.cell * entry.chunkCells
    local cx0, cx1 = entry.minChx, entry.maxChx
    local cy0, cy1 = entry.minChy, entry.maxChy
    if bounds then
        -- Un bloque entra si su caja toca la vista. Se usa el mismo criterio
        -- abierto del código anterior (`x + s > bounds.x`), solo que aplicado al
        -- bloque: dibujar un bloque de más no se ve, perderlo sí.
        cx0 = math.max(cx0, math.floor(bounds.x / side))
        cx1 = math.min(cx1, math.floor((bounds.x + bounds.w) / side))
        cy0 = math.max(cy0, math.floor(bounds.y / side))
        cy1 = math.min(cy1, math.floor((bounds.y + bounds.h) / side))
    end

    local alpha = layer.opacity or 1

    for chx = cx0, cx1 do
        local column = entry.chunks[chx]

        if column then
            for chy = cy0, cy1 do
                local chunk = column[chy]
                stats.scanned = stats.scanned + 1

                if chunk then
                    if chunk.dirty then
                        rebuild(entry, chunk, getImage)
                    end

                    if chunk.empty then
                        column[chy] = nil
                    else
                        stats.chunks = stats.chunks + 1
                        stats.tiles = stats.tiles + chunk.count
                        love.graphics.setColor(1, 1, 1, alpha)

                        for _, asset in ipairs(chunk.order) do
                            local batch = chunk.batches[asset]

                            if batch then
                                love.graphics.draw(batch)
                                stats.batches = stats.batches + 1
                            end
                        end

                        for _, asset in ipairs(chunk.overlayOrder or {}) do
                            local batch = chunk.overlayBatches[asset]

                            if batch then
                                love.graphics.draw(batch)
                                stats.batches = stats.batches + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Segunda pasada: lo que sobresale de las baldosas altas, por encima de
    -- todas las bases. Se incluye un bloque más por abajo, porque el saliente de
    -- la primera fila fuera de la vista entra en ella.
    local topRow = bounds and math.min(entry.maxChy, cy1 + 1) or cy1

    for chx = cx0, cx1 do
        local column = entry.chunks[chx]

        if column then
            for chy = cy0, topRow do
                local chunk = column[chy]

                if chunk and not chunk.empty and chunk.topOrder and #chunk.topOrder > 0 then
                    if chunk.dirty then
                        rebuild(entry, chunk, getImage)
                    end

                    love.graphics.setColor(1, 1, 1, alpha)

                    for _, asset in ipairs(chunk.topOrder) do
                        local batch = chunk.topBatches[asset]

                        if batch then
                            love.graphics.draw(batch)
                            stats.batches = stats.batches + 1
                        end
                    end
                end
            end
        end
    end
end

--- Dibuja una capa de terreno: sus celdas y, encima, su pintura suave. Con
-- relieve (en isométrico), primero la malla de colinas con la pintura encima,
-- y las celdas levantadas sobre ella.
function T.draw(map, layer, getImage, bounds)
    local Projection = require('runtime.projection')
    if type(layer.relief) == 'table' and Projection.isIso(map) then
        local Relief = require('runtime.terrain_relief')
        Relief.draw(map, layer, getImage)
        local lifted = Relief.beginLift(map)
        drawTiles(map, layer, getImage, bounds)
        if lifted then
            Relief.endLift()
        end
        return
    end

    drawTiles(map, layer, getImage, bounds)

    if layer.paint then
        require('runtime.terrain_paint').draw(map, layer, getImage, bounds)
    end
end

return T

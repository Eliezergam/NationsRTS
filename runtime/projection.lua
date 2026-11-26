-- Proyección de la vista: desde arriba (`top`, la de siempre) o isométrica (`iso`).
--
-- El juego **piensa siempre en el plano visto desde arriba**: física, colliders,
-- navegación, scripts y mapas guardados usan coordenadas de mundo `x, y` como
-- siempre. La proyección solo cambia cómo se dibuja y cómo se lee el ratón,
-- que es como lo hacen la mayoría de juegos isométricos.
--
-- Isométrica 2:1 (la de Age of Empires 2, SimCity 2000...):
--
--     vista.x = x - y
--     vista.y = (x + y) / 2
--
-- Una celda cuadrada de 32 px de mundo se ve como un rombo de 64 x 32. Es una
-- transformación afín, así que se aplica con una sola matriz: todo lo que va
-- **sobre el suelo** (celdas, pintura, rejilla, colliders, rutas, zonas) se
-- dibuja en coordenadas de mundo y sale en rombo solo.
--
-- Lo que está **de pie** (unidades, edificios, árboles) no se aplasta: se dibuja
-- derecho en su punto proyectado (`Projection.drawSprite`) y ordenado por
-- profundidad (`x + y`), para que lo de delante tape lo de detrás.
--
-- Sprites con direcciones: una imagen cuyo nombre acaba en `_dirN.png` (por
-- ejemplo `tanque_dir16.png`) es una tira horizontal de N cuadros. El cuadro
-- `k` es el objeto mirando al ángulo de mundo `k * 360 / N` grados (0 = +x, en
-- el sentido de las agujas del reloj como el resto del mundo). Al dibujarla se
-- elige el cuadro según el ángulo del objeto en vez de girar la imagen, que en
-- isométrico se vería torcida.

local Projection = {}

Projection.modes = { 'top', 'iso' }

--- ¿El mapa se ve en isométrico?
function Projection.isIso(map)
    return type(map) == 'table' and map.projection == 'iso'
end

--- Punto de mundo a punto de la vista.
function Projection.toView(map, x, y)
    if Projection.isIso(map) then
        return x - y, (x + y) * 0.5
    end

    return x, y
end

--- Punto de la vista a punto de mundo. Inversa exacta de `toView`.
function Projection.toWorld(map, vx, vy)
    if Projection.isIso(map) then
        return vy + vx * 0.5, vy - vx * 0.5
    end

    return vx, vy
end

local isoTransform
local isoInverse

--- Matriz de mundo a vista en isométrico.
function Projection.isoTransform()
    if not isoTransform then
        isoTransform = love.math.newTransform()
        isoTransform:setMatrix(1, -1, 0, 0, 0.5, 0.5, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        isoInverse = isoTransform:inverse()
    end

    return isoTransform, isoInverse
end

--- Aplica la proyección a la transformación actual: desde aquí se dibuja en
-- coordenadas de mundo. En vista desde arriba no hace nada.
function Projection.apply(map)
    if Projection.isIso(map) then
        love.graphics.applyTransform((Projection.isoTransform()))
    end
end

--- Caja de mundo que cubre un rectángulo de la vista (para recortar el dibujo).
function Projection.worldRect(map, view)
    if not Projection.isIso(map) then
        return { x = view.x, y = view.y, w = view.w, h = view.h }
    end

    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

    for _, corner in ipairs({
        { view.x, view.y },
        { view.x + view.w, view.y },
        { view.x, view.y + view.h },
        { view.x + view.w, view.y + view.h },
    }) do
        local x, y = Projection.toWorld(map, corner[1], corner[2])
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end

    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

--- Caja de la vista que cubre un rectángulo de mundo (el mapa entero, por ejemplo).
function Projection.viewRect(map, world)
    if not Projection.isIso(map) then
        return { x = world.x, y = world.y, w = world.w, h = world.h }
    end

    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

    for _, corner in ipairs({
        { world.x, world.y },
        { world.x + world.w, world.y },
        { world.x, world.y + world.h },
        { world.x + world.w, world.y + world.h },
    }) do
        local x, y = Projection.toView(map, corner[1], corner[2])
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end

    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

--- Profundidad de dibujo: lo que tiene más valor va delante.
function Projection.depth(map, x, y, z)
    if Projection.isIso(map) then
        -- Lo que vuela se dibuja por delante de lo que tiene debajo.
        return x + y + (z or 0) * 2
    end

    return y
end

--- Ángulo de mundo visto en pantalla (para girar una imagen sin direcciones).
function Projection.viewAngle(map, angle)
    if not Projection.isIso(map) then
        return angle
    end

    local c, s = math.cos(angle), math.sin(angle)
    return math.atan2((c + s) * 0.5, c - s)
end

--- Cuánto se gira en pantalla una imagen sin direcciones: lo que el objeto se
-- aparta de rotación 0, medido en la vista. Con rotación 0 la imagen sale tal
-- cual (una pared o un edificio renderizados en isométrico no se tuercen).
function Projection.imageAngle(map, angle)
    angle = angle or 0

    if not Projection.isIso(map) then
        return angle
    end

    return Projection.viewAngle(map, angle) - Projection.viewAngle(map, 0)
end

--- Rumbos e inclinaciones de una tira por su nombre: `_dir16.png` son 16
-- rumbos en una fila; `_dir16x5.png`, 16 rumbos (columnas) por 5 inclinaciones
-- (filas, de morro abajo a morro arriba). Sin sufijo: 1, 1.
function Projection.stripLayout(path)
    if type(path) ~= 'string' then
        return 1, 1
    end

    local count, rows = path:match('_dir(%d+)x(%d+)%.%a+$')

    if not count then
        count = path:match('_dir(%d+)%.%a+$')
    end

    count, rows = tonumber(count), tonumber(rows)

    if not count or count < 2 then
        return 1, 1
    end

    return math.floor(count), math.max(1, math.floor(rows or 1))
end

--- Número de rumbos de una imagen por su nombre, o 1.
function Projection.directionCount(path)
    local count = Projection.stripLayout(path)
    return count
end

--- Cuadro (0..N-1) para un ángulo de mundo.
function Projection.directionIndex(angle, count)
    local turn = (angle or 0) / (2 * math.pi)
    return math.floor(turn * count + 0.5) % count
end

-- Las filas de inclinación van de -60 a +60 grados, repartidas por igual.
Projection.pitchRange = math.rad(60)

--- Fila (0..rows-1) para una inclinación en radianes (positiva = morro arriba).
function Projection.pitchIndex(pitch, rows)
    if rows <= 1 then
        return 0
    end

    local step = 2 * Projection.pitchRange / (rows - 1)
    local index = math.floor(((pitch or 0) + Projection.pitchRange) / step + 0.5)
    return math.max(0, math.min(rows - 1, index))
end

--- Ancho y alto de un cuadro de la imagen (la imagen entera si no tiene direcciones).
function Projection.frameSize(image, path)
    local count, rows = Projection.stripLayout(path)
    return image:getWidth() / count, image:getHeight() / rows
end

local quads = setmetatable({}, { __mode = 'k' })

local function frameQuad(image, count, index, rows, row)
    rows, row = rows or 1, row or 0
    local byImage = quads[image]

    if not byImage then
        byImage = {}
        quads[image] = byImage
    end

    local key = count .. ':' .. index .. ':' .. rows .. ':' .. row
    local quad = byImage[key]

    if not quad then
        local w, h = image:getWidth(), image:getHeight()
        local fw, fh = w / count, h / rows
        quad = love.graphics.newQuad(index * fw, row * fh, fw, fh, w, h)
        byImage[key] = quad
    end

    return quad
end

--- Dibuja la imagen (o su primer cuadro si es una tira de direcciones)
-- encajada en una caja de `box` px con su esquina en `x, y`. Para miniaturas.
function Projection.drawThumb(image, path, x, y, box, alpha)
    local count, rows = Projection.stripLayout(path)
    local fw, fh = image:getWidth() / count, image:getHeight() / rows
    local scale = math.min(box / fw, box / fh)
    love.graphics.setColor(1, 1, 1, alpha or 1)

    if count > 1 then
        love.graphics.draw(
            image,
            frameQuad(image, count, 0, rows, Projection.pitchIndex(0, rows)),
            x + (box - fw * scale) / 2,
            y + (box - fh * scale) / 2,
            0,
            scale,
            scale
        )
    else
        love.graphics.draw(image, x + (box - fw * scale) / 2, y + (box - fh * scale) / 2, 0, scale, scale)
    end
end

--- Dibuja un objeto de pie en `x, y` de mundo, con la transformación de mundo
-- puesta (la de `Projection.apply`). La imagen queda centrada en el punto.
-- `z` es su altura sobre el suelo (en isométrico sube en la pantalla) y `pitch`
-- su inclinación, que elige la fila en las tiras `_dirNxM`.
function Projection.drawSprite(map, image, path, x, y, angle, sx, sy, z, pitch)
    local g = love.graphics
    local count, rows = Projection.stripLayout(path)
    local quad = nil
    local fw, fh = image:getWidth() / count, image:getHeight() / rows
    local drawAngle = angle or 0

    if count > 1 then
        quad =
            frameQuad(image, count, Projection.directionIndex(angle, count), rows, Projection.pitchIndex(pitch, rows))
        drawAngle = 0
    end

    local iso = Projection.isIso(map)

    if iso then
        -- Deshace la matriz isométrica alrededor del punto: la imagen sale
        -- derecha y a escala 1, en el sitio que le toca en la vista, y subida
        -- lo que mida su altura más la del terreno bajo ella.
        local _, inverse = Projection.isoTransform()
        g.push()
        g.translate(x, y)
        g.applyTransform(inverse)
        g.translate(0, -Projection.lift(map, (z or 0) + Projection.baseHeight(map, x, y)))

        if count == 1 then
            drawAngle = Projection.imageAngle(map, angle)
        end

        x, y = 0, 0
    end

    if quad then
        g.draw(image, quad, x, y, drawAngle, sx or 1, sy or 1, fw / 2, fh / 2)
    else
        g.draw(image, x, y, drawAngle, sx or 1, sy or 1, fw / 2, fh / 2)
    end

    if iso then
        g.pop()
    end
end

--- Sombra en el suelo de algo que vuela a altura `z`: una mancha oscura bajo
-- el punto, más tenue y algo más pequeña cuanto más alto. Con la transformación
-- de mundo puesta. Solo en isométrico y solo si está en el aire.
function Projection.drawShadow(map, x, y, radius, z)
    if not Projection.isIso(map) or (z or 0) <= 0.5 then
        return
    end

    local k = math.max(0.35, 1 - z / 400)
    local r, g, b, a = love.graphics.getColor()
    -- Sobre el terreno: subir en la vista `lift` es mover (-lift, -lift) en el mundo.
    local ground = Projection.lift(map, Projection.baseHeight(map, x, y))
    love.graphics.setColor(0, 0, 0, 0.32 * k)
    love.graphics.circle('fill', x - ground, y - ground, radius * (0.6 + 0.4 * k))
    love.graphics.setColor(r, g, b, a)
end

--- Línea entre dos puntos con altura (x, y, z), con la transformación de mundo
-- puesta. Para estelas y trayectorias de lo que vuela. Usa el mapa que se está
-- dibujando (`Projection.current`).
function Projection.line3D(x1, y1, z1, x2, y2, z2)
    local map = Projection.current

    if not Projection.isIso(map) then
        love.graphics.line(x1, y1, x2, y2)
        return
    end

    local ax, ay = Projection.toViewGround(map, x1, y1)
    local bx, by = Projection.toViewGround(map, x2, y2)
    local _, inverse = Projection.isoTransform()
    local shader = love.graphics.getShader()
    love.graphics.setShader()
    love.graphics.push()
    love.graphics.applyTransform(inverse)
    love.graphics.line(ax, ay - Projection.lift(map, z1), bx, by - Projection.lift(map, z2))
    love.graphics.pop()
    love.graphics.setShader(shader)
end

-- Píxeles de la vista que sube una altura de 1 px de mundo. Sale de la cámara
-- isométrica 2:1 (elevación 30 grados) con la que se renderiza el arte en
-- Blender: 1 celda (32 px) de altura sube 39.2 px en pantalla.
Projection.heightScale = math.sqrt(1.5)

--- Altura del terreno (relieve) en un punto de mundo; 0 si el mapa es plano.
function Projection.baseHeight(map, x, y)
    if not Projection.isIso(map) then
        return 0
    end
    return require('runtime.terrain_relief').heightAt(map, x or 0, y or 0)
end

--- Punto de la vista a punto de mundo **sobre el terreno**: con relieve, el
-- punto de la colina que se ve ahí, no el del suelo plano de debajo. Se busca
-- por aproximaciones (la altura depende del punto que se busca).
function Projection.pick(map, vx, vy)
    local x, y = Projection.toWorld(map, vx, vy)
    if not Projection.isIso(map) then
        return x, y
    end
    local Relief = require('runtime.terrain_relief')
    if not Relief.layerOf(map) then
        return x, y
    end
    for _ = 1, 6 do
        local h = Relief.heightAt(map, x, y)
        x, y = Projection.toWorld(map, vx, vy + Projection.lift(map, h))
    end
    return x, y
end

--- Punto de mundo a punto de la vista, apoyado en el terreno.
function Projection.toViewGround(map, x, y)
    local vx, vy = Projection.toView(map, x, y)
    return vx, vy - Projection.lift(map, Projection.baseHeight(map, x, y))
end

--- Amplía una caja de mundo visible para que no se recorte lo que el relieve
-- sube dentro de la pantalla desde más abajo.
function Projection.expandForRelief(map, rect)
    if not Projection.isIso(map) then
        return rect
    end
    local top = require('runtime.terrain_relief').maxHeight(map)
    if top <= 0 then
        return rect
    end
    local margin = Projection.lift(map, top) * 1.5
    return { x = rect.x, y = rect.y, w = rect.w + margin, h = rect.h + margin }
end

--- Cuánto sube en la vista una altura `z` de mundo (0 fuera de isométrico).
function Projection.lift(map, z)
    if not Projection.isIso(map) then
        return 0
    end

    return (z or 0) * Projection.heightScale
end

--- Dibuja una colisión como volumen. `points` es su contorno en el suelo
-- (mundo, lista plana), `z` su elevación y `height` su altura, en px de mundo.
-- Con la transformación del mundo puesta. Desde arriba (o sin altura) es la
-- forma plana de siempre; en isométrico sale como caja, cilindro o prisma, con
-- una sombra en el suelo si flota.
function Projection.drawVolume(map, points, z, height, color, fillAlpha)
    local g = love.graphics
    local r, gr, b = color[1], color[2], color[3]
    fillAlpha = fillAlpha or 0.25

    local function fill(list)
        if #list < 6 then
            return
        end

        local ok, triangles = pcall(love.math.triangulate, list)

        if ok then
            for _, triangle in ipairs(triangles) do
                g.polygon('fill', triangle)
            end
        end
    end

    if not Projection.isIso(map) or ((z or 0) <= 0 and (height or 0) <= 0) then
        g.setColor(r, gr, b, fillAlpha)
        fill(points)
        g.setColor(r, gr, b, 0.95)
        if #points >= 6 then
            g.polygon('line', points)
        end
        return
    end

    local _, inverse = Projection.isoTransform()
    local view = {}
    local shader = g.getShader()
    g.setShader()

    for i = 1, #points - 1, 2 do
        local vx, vy = Projection.toView(map, points[i], points[i + 1])
        view[#view + 1] = vx
        view[#view + 1] = vy
    end

    local function lifted(amount)
        local out = {}

        for i = 1, #view - 1, 2 do
            out[#out + 1] = view[i]
            out[#out + 1] = view[i + 1] - amount
        end

        return out
    end

    local bottomLift = Projection.lift(map, z)
    local topLift = Projection.lift(map, (z or 0) + (height or 0))
    local bottom, top = lifted(bottomLift), lifted(topLift)

    g.push()
    g.applyTransform(inverse)

    if bottomLift > 0 then
        g.setColor(r, gr, b, 0.3)
        g.polygon('line', view)
    end

    g.setColor(r, gr, b, fillAlpha)
    fill(top)
    g.setColor(r, gr, b, 0.95)
    g.polygon('line', bottom)
    g.polygon('line', top)

    -- Aristas verticales: todas en cajas y prismas; en un círculo solo las dos
    -- del contorno, o parecería una jaula.
    local count = #view / 2
    local function vertical(i)
        g.line(view[i * 2 - 1], view[i * 2] - bottomLift, view[i * 2 - 1], view[i * 2] - topLift)
    end

    if count > 8 then
        local left, right = 1, 1

        for i = 1, count do
            if view[i * 2 - 1] < view[left * 2 - 1] then
                left = i
            end

            if view[i * 2 - 1] > view[right * 2 - 1] then
                right = i
            end
        end

        vertical(left)
        vertical(right)
    else
        for i = 1, count do
            vertical(i)
        end
    end

    g.pop()
    g.setShader(shader)
end

-- Mapa que se está dibujando. Lo pone `runtime/level_loader.lua` al dibujar el
-- nivel, para que los scripts no tengan que conocerlo.
Projection.current = nil

--- Dibuja algo **de pie** alrededor del punto de mundo `x, y`: barras de salud,
-- rótulos, iconos. Dentro de `draw` se dibuja en píxeles de pantalla a partir
-- del punto (0, 0), que es el objeto; en isométrico sale derecho, no aplastado
-- contra el suelo.
--
--   Projection.upright(self.obj.x, self.obj.y, function()
--       love.graphics.rectangle('fill', -24, -26, 48, 5)
--   end)
function Projection.upright(x, y, draw)
    local g = love.graphics
    local map = Projection.current
    -- Lo de pie no pasa por el shader que levanta el suelo: ya va en píxeles de pantalla.
    local shader = g.getShader()
    g.setShader()
    g.push()
    g.translate(x, y)

    if Projection.isIso(map) then
        local _, inverse = Projection.isoTransform()
        g.applyTransform(inverse)
        g.translate(0, -Projection.lift(map, Projection.baseHeight(map, x, y)))
    end

    draw()
    g.pop()
    g.setShader(shader)
end

--- ¿El punto de vista `vx, vy` cae dentro de la imagen de pie de un objeto?
-- Para seleccionar con el ratón lo que se ve, no la huella en el suelo.
function Projection.spriteContains(map, image, path, o, vx, vy)
    local fw, fh = Projection.frameSize(image, path)
    local cx, cy = Projection.toViewGround(map, o.x or 0, o.y or 0)
    cy = cy - Projection.lift(map, o.z)
    local hw = math.abs(fw * (o.scaleX or 1)) * 0.5
    local hh = math.abs(fh * (o.scaleY or 1)) * 0.5

    return vx >= cx - hw and vx <= cx + hw and vy >= cy - hh and vy <= cy + hh
end

--- Píxel de la imagen (0-based, en la imagen entera) que hay bajo el punto de
-- vista `vx, vy`, o nil si cae fuera. Tiene en cuenta el cuadro de dirección
-- que se está dibujando y el giro de las imágenes sin direcciones.
function Projection.spritePixel(map, image, path, o, vx, vy)
    local count, rows = Projection.stripLayout(path)
    local fw, fh = image:getWidth() / count, image:getHeight() / rows
    local cx, cy = Projection.toViewGround(map, o.x or 0, o.y or 0)
    cy = cy - Projection.lift(map, o.z)
    local dx, dy = vx - cx, vy - cy

    if count == 1 then
        local a = Projection.imageAngle(map, o.rotation)
        local c, s = math.cos(-a), math.sin(-a)
        dx, dy = dx * c - dy * s, dx * s + dy * c
    end

    local sx, sy = o.scaleX or 1, o.scaleY or 1
    local px = dx / (sx ~= 0 and sx or 1) + fw / 2
    local py = dy / (sy ~= 0 and sy or 1) + fh / 2

    if px < 0 or py < 0 or px >= fw or py >= fh then
        return nil
    end

    local frame = count > 1 and Projection.directionIndex(o.rotation or 0, count) or 0
    local row = count > 1 and Projection.pitchIndex(o.pitch, rows) or 0
    return math.floor(frame * fw + px), math.floor(row * fh + py)
end

--- Ordena una lista de objetos por profundidad (estable: a igual profundidad
-- se respeta el orden de la capa).
function Projection.sortByDepth(map, list, position)
    local keyed = {}

    for index, item in ipairs(list) do
        local x, y, z

        if position then
            x, y, z = position(item)
        else
            x, y, z = item.x or 0, item.y or 0, item.z
        end

        keyed[index] = { item = item, depth = Projection.depth(map, x, y, z), index = index }
    end

    table.sort(keyed, function(a, b)
        if a.depth ~= b.depth then
            return a.depth < b.depth
        end

        return a.index < b.index
    end)

    for index, entry in ipairs(keyed) do
        list[index] = entry.item
    end

    return list
end

return Projection

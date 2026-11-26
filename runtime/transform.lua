-- Shared geometry for selection, collision drawing and physics export.
local T = {}
function T.size(o)
    local w = math.max(0.01, math.abs((o.w or 32) * (o.scaleX or 1)))
    local h = math.max(0.01, math.abs((o.h or 32) * (o.scaleY or 1)))
    return w, h
end
function T.localPoint(o, x, y)
    local dx, dy = x - o.x, y - o.y
    local c, s = math.cos(o.rotation or 0), math.sin(o.rotation or 0)
    return c * dx + s * dy, -s * dx + c * dy
end
function T.contains(o, x, y)
    local lx, ly = T.localPoint(o, x, y)
    local w, h = T.size(o)
    if o.shape == 'circle' then
        return lx * lx + ly * ly <= (w / 2) ^ 2
    end
    if o.shape == 'polygon' and o.polygon and #o.polygon >= 3 then
        local inside = false
        local j = #o.polygon
        for i = 1, #o.polygon do
            local a, b = o.polygon[i], o.polygon[j]
            local ax, ay = (a.x or a[1] or 0) * (o.scaleX or 1), (a.y or a[2] or 0) * (o.scaleY or 1)
            local bx, by = (b.x or b[1] or 0) * (o.scaleX or 1), (b.y or b[2] or 0) * (o.scaleY or 1)
            if ((ay > ly) ~= (by > ly)) and (lx < (bx - ax) * (ly - ay) / (by - ay) + ax) then
                inside = not inside
            end
            j = i
        end
        return inside
    end
    return math.abs(lx) <= w / 2 and math.abs(ly) <= h / 2
end

--- Geometria del collider en coordenadas del cuerpo, ya escalada.
-- El bloque `o.collider` es opcional y siempre relativo al objeto:
--   ox, oy  desplazamiento del centro de la forma en coordenadas locales del
--           objeto, en pixeles y **antes** de la escala del sprite
--   rot     giro de la forma respecto al objeto, en radianes
--   w, h    ancho y alto propios del rectangulo (antes de la escala)
--   r       radio propio del circulo (antes de la escala)
-- Sin bloque, la forma coincide con el sprite: es el comportamiento de siempre,
-- asi que un mapa antiguo devuelve exactamente lo que devolvia antes.
-- Devuelve ox, oy, rot, w, h, r ya en pixeles del cuerpo.
function T.collider(o)
    local sx, sy = o.scaleX or 1, o.scaleY or 1
    local w, h = T.size(o)
    local c = type(o.collider) == 'table' and o.collider or nil
    if not c then
        return 0, 0, 0, w, h, w / 2
    end
    local cw, ch, cr = tonumber(c.w), tonumber(c.h), tonumber(c.r)
    if cw then
        w = math.max(0.01, math.abs(cw * sx))
    end
    if ch then
        h = math.max(0.01, math.abs(ch * sy))
    end
    local r = w / 2
    if cr then
        r = math.max(0.005, math.abs(cr * sx))
        -- Un circulo con radio propio manda tambien sobre su caja, para que el
        -- dibujo y el picking midan lo mismo que la fixture.
        if o.shape == 'circle' then
            w, h = r * 2, r * 2
        end
    end
    return (tonumber(c.ox) or 0) * sx, (tonumber(c.oy) or 0) * sy, tonumber(c.rot) or 0, w, h, r
end
--- Contorno del collider en coordenadas de mundo, como lista plana
-- `{x1, y1, x2, y2, ...}`. `x, y, angle` son la posición y el giro del cuerpo
-- (por defecto los del objeto). Un círculo sale como polígono de `segments`
-- lados. Sirve para dibujar la colisión como volumen en la vista isométrica.
function T.colliderOutline(o, x, y, angle, segments)
    x, y, angle = x or o.x or 0, y or o.y or 0, angle or o.rotation or 0
    local ox, oy, rot, w, h, r = T.collider(o)
    local local_ = {}
    if o.shape == 'circle' then
        segments = segments or 24
        for i = 0, segments - 1 do
            local a = i * 2 * math.pi / segments
            local_[#local_ + 1] = { math.cos(a) * r, math.sin(a) * r }
        end
    elseif o.shape == 'polygon' and type(o.polygon) == 'table' and #o.polygon >= 3 then
        for _, p in ipairs(o.polygon) do
            local_[#local_ + 1] = { (p.x or p[1] or 0) * (o.scaleX or 1), (p.y or p[2] or 0) * (o.scaleY or 1) }
        end
    else
        local hw, hh = w / 2, h / 2
        local_ = { { -hw, -hh }, { hw, -hh }, { hw, hh }, { -hw, hh } }
    end
    local cr, sr = math.cos(rot), math.sin(rot)
    local c, s = math.cos(angle), math.sin(angle)
    local out = {}
    for _, p in ipairs(local_) do
        local px, py = ox + cr * p[1] - sr * p[2], oy + sr * p[1] + cr * p[2]
        out[#out + 1] = x + c * px - s * py
        out[#out + 1] = y + s * px + c * py
    end
    return out
end

--- Elevación y altura de la colisión (píxeles de mundo). Solo se ven en la vista
-- isométrica; la física sigue usando la huella en el suelo.
function T.colliderHeight(o)
    if type(o) ~= 'table' then
        return 0, 0
    end
    -- La elevación es la del objeto (lo que vuela, `o.z`) más la propia de la
    -- colisión, que puede ser negativa (un misil centrado en su altura).
    local c = type(o.collider) == 'table' and o.collider or {}
    local base = (tonumber(o.z) or 0) + (tonumber(c.z) or 0)
    return math.max(0, base), math.max(0, tonumber(c.alto) or 0)
end

--- Puntos del poligono del collider en coordenadas del cuerpo: escalados por el
-- objeto, girados por `rot` y desplazados por `ox, oy`. Lista plana x1,y1,x2,y2...
function T.colliderPoints(o, out)
    local ox, oy, rot = T.collider(o)
    local sx, sy = o.scaleX or 1, o.scaleY or 1
    local ca, sa = math.cos(rot), math.sin(rot)
    local points = out or {}
    for i = #points, 1, -1 do
        points[i] = nil
    end
    for _, p in ipairs(o.polygon or {}) do
        local lx, ly = (p.x or p[1] or 0) * sx, (p.y or p[2] or 0) * sy
        points[#points + 1] = ox + ca * lx - sa * ly
        points[#points + 1] = oy + sa * lx + ca * ly
    end
    return points
end
return T

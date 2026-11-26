--- Balística analítica de la batalla 3D (Valeria, batalla/DANO-REAL.md §3).
-- La posición de un proyectil sale exacta en cualquier instante, sin
-- integrar paso a paso: igual en todas las máquinas y barata.
--
--   directa    balas y cañonazos: el arrastre frena a lo largo del
--              recorrido, v(s) = v0·e^(−k·s), y la gravedad hace caer
--              g·t²/2. Recorrido en el instante t: s = ln(1 + k·v0·t) / k.
--   indirecta  cohetes y misiles: un impulso de `impulso` s que sale por el
--              eje de la rampa y empalma (Hermite, en posición y velocidad)
--              con la parábola sin aire que llega al punto de caída; después,
--              la parábola.
--
-- Todo en px y s. Sin LÖVE.

local Trayectoria = {}

Trayectoria.impulso = 1.2 -- s de impulso de un cohete
Trayectoria.angulo = math.rad(45) -- ángulo de la parábola del tiro indirecto
Trayectoria.anguloAlto = math.rad(62) -- si el blanco está demasiado alto para 45°

-- Tiro directo ---------------------------------------------------------------------------------

--- Recorrido (px) en el instante `t` de una trayectoria directa `d`.
local function recorrido(d, t)
    if d.k <= 0 then
        return d.v0 * t
    end
    return math.log(1 + d.k * d.v0 * t) / d.k
end

--- Instante en que la trayectoria directa `d` ha recorrido `s` px.
function Trayectoria.tiempoEn(d, s)
    if d.k <= 0 then
        return s / d.v0
    end
    return (math.exp(d.k * s) - 1) / (d.k * d.v0)
end

--- Trayectoria directa desde (x, y, z) por la dirección (ux, uy, uz)
-- (unitaria), con velocidad de boca `v0` px/s, arrastre `k` 1/px y gravedad `g`.
function Trayectoria.directa(x, y, z, ux, uy, uz, v0, k, g)
    return {
        tipo = 'directa',
        x = x,
        y = y,
        z = z,
        ux = ux,
        uy = uy,
        uz = uz,
        v0 = v0,
        k = k,
        g = g,
    }
end

--- Posición de la trayectoria directa `d` en el instante `t`.
function Trayectoria.posicionDirecta(d, t)
    local s = recorrido(d, t)
    return d.x + d.ux * s, d.y + d.uy * s, d.z + d.uz * s - d.g * t * t * 0.5
end

--- Velocidad (px/s) de la trayectoria directa `d` en el instante `t`.
function Trayectoria.velocidadDirecta(d, t)
    local v = d.v0 / (1 + d.k * d.v0 * t)
    return d.ux * v, d.uy * v, d.uz * v - d.g * t
end

--- Dirección unitaria para que una bala de `v0` y `k` salida de (x0, y0, z0)
-- llegue a (x1, y1, z1): apunta por encima lo que cae en el camino
-- (sobreelevación). Devuelve la dirección y el tiempo de vuelo.
function Trayectoria.apuntar(x0, y0, z0, x1, y1, z1, v0, k, g)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    if largo < 1e-6 then
        return 1, 0, 0, 0
    end
    local d = { v0 = v0, k = k }
    local t = Trayectoria.tiempoEn(d, largo)
    -- Dos vueltas: la sobreelevación alarga un poco el camino.
    local ux, uy, uz
    for _ = 1, 2 do
        local cz = dz + g * t * t * 0.5
        local l = math.sqrt(dx * dx + dy * dy + cz * cz)
        ux, uy, uz = dx / l, dy / l, cz / l
        t = Trayectoria.tiempoEn(d, l)
    end
    return ux, uy, uz, t
end

-- Tiro indirecto -------------------------------------------------------------------------------

--- Trayectoria indirecta desde la boca (x, y, z) con la rampa hacia (sx, sy,
-- sz) hasta el punto de caída (x1, y1, z1), con gravedad `g`. Devuelve la
-- trayectoria y su tiempo de vuelo hasta la altura de caída.
function Trayectoria.indirecta(x, y, z, sx, sy, sz, x1, y1, z1, g)
    local hx, hy = x1 - x, y1 - y
    local r = math.max(1, math.sqrt(hx * hx + hy * hy))
    local h = z1 - z
    local angulo = Trayectoria.angulo
    local c, s = math.cos(angulo), math.sin(angulo)
    if r * s / c - h <= r * 0.05 then
        angulo = Trayectoria.anguloAlto
        c, s = math.cos(angulo), math.sin(angulo)
    end
    -- Velocidad de la parábola sin aire que pasa por (r, h).
    local v = math.sqrt(g * r * r / (2 * c * c * math.max(r * 0.05, r * s / c - h)))
    local vx, vy, vz = hx / r * c * v, hy / r * c * v, s * v
    local disc = math.max(0, vz * vz - 2 * g * h)
    local vuelo = (vz + math.sqrt(disc)) / g
    local impulso = math.min(Trayectoria.impulso, vuelo * 0.25)
    local ls = math.sqrt(sx * sx + sy * sy + sz * sz)
    if ls < 1e-6 then
        sx, sy, sz, ls = vx, vy, vz, v
    end
    local m = {
        tipo = 'indirecta',
        x = x,
        y = y,
        z = z,
        vx = vx,
        vy = vy,
        vz = vz,
        g = g,
        impulso = impulso,
        -- Tangente de salida (Hermite): por la rampa, a la velocidad de la parábola.
        sx = sx / ls * v * impulso,
        sy = sy / ls * v * impulso,
        sz = sz / ls * v * impulso,
    }
    -- Punto y velocidad en que el impulso empalma con la parábola.
    m.bx, m.by, m.bz = x + vx * impulso, y + vy * impulso, z + vz * impulso - g * impulso * impulso * 0.5
    m.ex, m.ey, m.ez = vx * impulso, vy * impulso, (vz - g * impulso) * impulso
    return m, vuelo
end

--- Posición de la trayectoria indirecta `m` en el instante `t`.
function Trayectoria.posicionIndirecta(m, t)
    if t >= m.impulso then
        return m.x + m.vx * t, m.y + m.vy * t, m.z + m.vz * t - m.g * t * t * 0.5
    end
    local u = math.max(0, t / m.impulso)
    local u2, u3 = u * u, u * u * u
    local a = 2 * u3 - 3 * u2 + 1
    local b = u3 - 2 * u2 + u
    local c = -2 * u3 + 3 * u2
    local d = u3 - u2
    return a * m.x + b * m.sx + c * m.bx + d * m.ex,
        a * m.y + b * m.sy + c * m.by + d * m.ey,
        a * m.z + b * m.sz + c * m.bz + d * m.ez
end

--- Velocidad (px/s) de la trayectoria indirecta `m` en el instante `t`.
function Trayectoria.velocidadIndirecta(m, t)
    if t >= m.impulso then
        return m.vx, m.vy, m.vz - m.g * t
    end
    local u = math.max(0, t / m.impulso)
    local u2 = u * u
    local a = 6 * u2 - 6 * u
    local b = 3 * u2 - 4 * u + 1
    local c = -6 * u2 + 6 * u
    local d = 3 * u2 - 2 * u
    local k = 1 / m.impulso
    return (a * m.x + b * m.sx + c * m.bx + d * m.ex) * k,
        (a * m.y + b * m.sy + c * m.by + d * m.ey) * k,
        (a * m.z + b * m.sz + c * m.bz + d * m.ez) * k
end

-- Las dos -------------------------------------------------------------------------------------

function Trayectoria.posicion(tr, t)
    if tr.tipo == 'directa' then
        return Trayectoria.posicionDirecta(tr, t)
    end
    return Trayectoria.posicionIndirecta(tr, t)
end

function Trayectoria.velocidad(tr, t)
    if tr.tipo == 'directa' then
        return Trayectoria.velocidadDirecta(tr, t)
    end
    return Trayectoria.velocidadIndirecta(tr, t)
end

--- Primer instante (de `t0` a `t1`) en que la trayectoria `tr` pasa bajo el
-- terreno de `suelo`, recorriéndola en `tramos` cuerdas con `terreno`
-- (Impactos.terreno). Devuelve el instante y el punto, o nil. Apunta en
-- `tr.sueloMaximo` el suelo más alto bajo los extremos de las cuerdas.
function Trayectoria.suelo(tr, suelo, terreno, t0, t1, tramos)
    local ax, ay, az = Trayectoria.posicion(tr, t0)
    local maximo = suelo:altura(ax, ay)
    for k = 1, tramos do
        local tb = t0 + (t1 - t0) * k / tramos
        local bx, by, bz = Trayectoria.posicion(tr, tb)
        maximo = math.max(maximo, suelo:altura(bx, by))
        local f = terreno(suelo, ax, ay, az, bx, by, bz)
        if f then
            tr.sueloMaximo = maximo
            local ta = t0 + (t1 - t0) * (k - 1) / tramos
            return ta + (tb - ta) * f, ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f
        end
        ax, ay, az = bx, by, bz
    end
    tr.sueloMaximo = maximo
    return nil
end

--- Instantes entre los que la parábola de la trayectoria indirecta `m` va
-- por encima de la altura `z` (después del impulso), o nil si no llega.
function Trayectoria.porEncima(m, z)
    -- z(t) = m.z + vz·t − g·t²/2 = z  →  g/2·t² − vz·t + (z − m.z) = 0
    local a, b, c = m.g * 0.5, -m.vz, z - m.z
    local disc = b * b - 4 * a * c
    if disc <= 0 then
        return nil
    end
    local r = math.sqrt(disc)
    local t0 = (-b - r) / (2 * a)
    local t1 = (-b + r) / (2 * a)
    return math.max(t0, m.impulso), t1
end

return Trayectoria

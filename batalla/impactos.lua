-- Choques de balas y misiles con el terreno y los árboles de la batalla
-- (Valeria). Todo en px del juego (1 px = 10 cm, z hacia arriba).
--
--   terreno  el segmento se recorre contra `Suelo:altura` con pasos que
--            crecen con la holgura sobre el suelo (lejos del suelo se avanza
--            mucho; cerca, poco) y el cruce se refina por bisección
--   árboles  `suelo.plantasFisicas` (árboles y rocas grandes), buscados en la
--            rejilla de celdas de `Suelo.celdaPlantas`: tronco como cilindro
--            vertical, copa como cilindro más ancho en su parte alta y roca
--            como semiesfera
--
-- `Impactos.rayo` devuelve el primer choque del segmento o nil.

local Impactos = {}

Impactos.pasoMinimo = 12 -- px: el paso más corto contra el terreno (1,2 m)
Impactos.pasoMaximo = 600 -- px: el más largo, lejos del suelo
Impactos.holgura = 0.7 -- fracción de la altura libre que se avanza en cada paso
Impactos.refinado = 10 -- pasos de bisección en el cruce
Impactos.copaDesde = 0.35 -- fracción del alto del árbol donde empieza la copa
Impactos.copaRadio = 0.45 -- fracción del radio de ocupación del árbol que ocupa la copa

-- Medida del coste (lo lee la prueba y el rótulo de rendimiento).
Impactos.rayos = 0
Impactos.segundos = 0

--- Primera t (0 a 1) en que el segmento horizontal (x0, y0) + t (dx, dy)
-- entra en el círculo de centro (cx, cy) y radio r, o nil.
local function entradaCirculo(x0, y0, dx, dy, cx, cy, r)
    local fx, fy = x0 - cx, y0 - cy
    local a = dx * dx + dy * dy
    local c = fx * fx + fy * fy - r * r
    if c <= 0 then
        return 0
    end
    if a < 1e-9 then
        return nil
    end
    local b = 2 * (fx * dx + fy * dy)
    local disc = b * b - 4 * a * c
    if disc < 0 then
        return nil
    end
    local t = (-b - math.sqrt(disc)) / (2 * a)
    if t < 0 or t > 1 then
        return nil
    end
    return t
end

--- Primer t en que el segmento toca el cilindro vertical (cx, cy, r) entre
-- z0 y z1, o nil. Si entra por arriba o por abajo, se busca en su interior.
local function cilindro(x0, y0, z0, dx, dy, dz, cx, cy, r, zBajo, zAlto)
    local t = entradaCirculo(x0, y0, dx, dy, cx, cy, r)
    if not t then
        return nil
    end
    local z = z0 + dz * t
    if z >= zBajo and z <= zAlto then
        return t
    end
    -- Entra en el círculo por encima o por debajo: quizá cruce la tapa
    -- dentro del círculo.
    if math.abs(dz) < 1e-9 then
        return nil
    end
    local tapa = z > zAlto and zAlto or zBajo
    local tt = (tapa - z0) / dz
    if tt < t or tt > 1 then
        return nil
    end
    local x, y = x0 + dx * tt - cx, y0 + dy * tt - cy
    if x * x + y * y <= r * r then
        return tt
    end
    return nil
end

--- Primer t en que el segmento toca la esfera (cx, cy, cz, r), o nil.
local function esfera(x0, y0, z0, dx, dy, dz, cx, cy, cz, r)
    local fx, fy, fz = x0 - cx, y0 - cy, z0 - cz
    local a = dx * dx + dy * dy + dz * dz
    local c = fx * fx + fy * fy + fz * fz - r * r
    if c <= 0 then
        return 0
    end
    local b = 2 * (fx * dx + fy * dy + fz * dz)
    local disc = b * b - 4 * a * c
    if disc < 0 or a < 1e-9 then
        return nil
    end
    local t = (-b - math.sqrt(disc)) / (2 * a)
    if t < 0 or t > 1 then
        return nil
    end
    return t
end

--- Primer t (0 a 1) en que el segmento (x0, y0, z0) + t·(dx, dy, dz) toca la
-- planta `p` (árbol o roca grande de `suelo.plantasFisicas`), o nil. Tronco
-- como cilindro vertical, copa como cilindro más ancho en su parte alta y
-- roca como semiesfera.
function Impactos.cruzarPlanta(suelo, p, x0, y0, z0, dx, dy, dz)
    local base = p.z or suelo:altura(p.x, p.y)
    p.z = base
    if p.roca then
        return esfera(x0, y0, z0, dx, dy, dz, p.x, p.y, base, p.radio)
    end
    local alto = p.alto or 120
    local t = cilindro(x0, y0, z0, dx, dy, dz, p.x, p.y, math.max(p.radio, 3), base, base + alto)
    local copa = (p.copa or 40) * Impactos.copaRadio
    local tc = cilindro(x0, y0, z0, dx, dy, dz, p.x, p.y, copa, base + alto * Impactos.copaDesde, base + alto)
    if tc and (not t or tc < t) then
        t = tc
    end
    return t
end

--- Árboles y rocas grandes en pie cuyas celdas tocan el rectángulo que
-- envuelve el segmento horizontal (x0, y0)-(x1, y1) más `margen` px, en
-- `salida`; nil si son demasiadas celdas (una línea de vista larga).
function Impactos.plantasCerca(suelo, x0, y0, x1, y1, margen, salida)
    local celda = suelo.celdaPlantas or 128
    local celdas = suelo.celdasPlantas
    if not celdas then
        return nil
    end
    local i0, j0 = math.floor((math.min(x0, x1) - margen) / celda), math.floor((math.min(y0, y1) - margen) / celda)
    local i1, j1 = math.floor((math.max(x0, x1) + margen) / celda), math.floor((math.max(y0, y1) + margen) / celda)
    if (i1 - i0 + 1) * (j1 - j0 + 1) > 400 then
        return nil
    end
    local n = 0
    for j = j0, j1 do
        for i = i0, i1 do
            local lista = celdas[i * 131072 + j]
            if lista then
                for _, p in ipairs(lista) do
                    if p.arbol and not p.caido then
                        n = n + 1
                        salida[n] = p
                    end
                end
            end
        end
    end
    for k = n + 1, #salida do
        salida[k] = nil
    end
    return salida
end

local cercanas = {}

--- Choque con los árboles y rocas grandes: el menor t (y su planta) o nil.
-- Las copas se salen de su celda: se mira un margen de 10 m. Un segmento muy
-- largo (una línea de vista) no mira árboles.
function Impactos.arboles(suelo, x0, y0, z0, x1, y1, z1)
    local lista = Impactos.plantasCerca(suelo, x0, y0, x1, y1, 100, cercanas)
    if not lista then
        return nil
    end
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local mejor, mejorT = nil, math.huge
    for _, p in ipairs(lista) do
        local t = Impactos.cruzarPlanta(suelo, p, x0, y0, z0, dx, dy, dz)
        if t and t < mejorT then
            mejor, mejorT = p, t
        end
    end
    if mejor then
        return mejorT, mejor
    end
    return nil
end

--- Primer t en que el segmento pasa bajo el terreno, o nil.
function Impactos.terreno(suelo, x0, y0, z0, x1, y1, z1)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    if largo < 1e-6 then
        return nil
    end
    local t = 0
    local libre = z0 - suelo:altura(x0, y0)
    if libre < 0 then
        return 0
    end
    local anterior
    while t < 1 do
        local paso = math.max(Impactos.pasoMinimo, math.min(Impactos.pasoMaximo, libre * Impactos.holgura))
        anterior = t
        t = math.min(1, t + paso / largo)
        libre = z0 + dz * t - suelo:altura(x0 + dx * t, y0 + dy * t)
        if libre < 0 then
            -- Bisección entre el último punto libre y el primero enterrado.
            local a, b = anterior, t
            for _ = 1, Impactos.refinado do
                local m = (a + b) * 0.5
                if z0 + dz * m - suelo:altura(x0 + dx * m, y0 + dy * m) < 0 then
                    b = m
                else
                    a = m
                end
            end
            return b
        end
    end
    return nil
end

--- Primer choque del segmento (x0, y0, z0) → (x1, y1, z1) con el terreno o
-- con un árbol o roca grande: { x, y, z, t, tipo = 'terreno' | 'arbol' |
-- 'roca', planta = la de `suelo.plantasFisicas` } o nil. Con `soloTerreno`
-- no mira las plantas (líneas de vista largas).
function Impactos.rayo(suelo, x0, y0, z0, x1, y1, z1, soloTerreno)
    local inicio = love.timer.getTime()
    local t = Impactos.terreno(suelo, x0, y0, z0, x1, y1, z1)
    local tipo, planta = 'terreno', nil
    if not soloTerreno then
        local ta, p = Impactos.arboles(suelo, x0, y0, z0, x1, y1, z1)
        if ta and (not t or ta < t) then
            t, planta = ta, p
            tipo = p.roca and 'roca' or 'arbol'
        end
    end
    -- Edificios y muro de una ciudad o mina (también tapan la vista).
    if suelo.plano then
        local te, h = suelo.plano:rayo(x0, y0, z0, x1, y1, z1)
        if te and (not t or te < t) then
            t, planta = te, nil
            tipo = h.muro and 'muro' or 'edificio'
        end
    end
    Impactos.rayos = Impactos.rayos + 1
    Impactos.segundos = Impactos.segundos + love.timer.getTime() - inicio
    if not t then
        return nil
    end
    return {
        x = x0 + (x1 - x0) * t,
        y = y0 + (y1 - y0) * t,
        z = z0 + (z1 - z0) * t,
        t = t,
        tipo = tipo,
        planta = planta,
    }
end

--- ¿Se ven (x0, y0, z0) y (x1, y1, z1) sin una loma en medio?
function Impactos.visible(suelo, x0, y0, z0, x1, y1, z1)
    return Impactos.rayo(suelo, x0, y0, z0, x1, y1, z1, true) == nil
end

return Impactos

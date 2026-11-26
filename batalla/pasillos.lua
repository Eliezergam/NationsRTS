-- Pasillos de avance de la batalla (Valeria): dos o tres franjas anchas, sin
-- árboles ni rocas grandes y con pendiente suave, que unen la zona donde forma
-- un bando con la del otro (y con el objetivo, si hay ciudad o instalación).
--
-- El principal conecta los extremos reales de ambas formaciones. Primero
-- busca tierra con A*; si están separados por agua, abre una calzada de
-- terreno elevado por el cruce de menor coste. No depende de puentes visuales.
-- Su perfil y su ancho útil se comprueban sobre los triángulos finales de la
-- malla. Los pasillos adicionales solo se conservan si también son transitables.
--
-- Todo sale de la semilla y del sitio: la misma batalla da los mismos
-- pasillos en todas las máquinas.

local Pasillos = {}
Pasillos.__index = Pasillos

Pasillos.celda = 80 -- px de la rejilla del A* (8 m)
Pasillos.mitad = 500 -- px del eje al borde del pasillo (100 m de ancho)
Pasillos.transicion = 380 -- px en los que el pasillo se funde con el terreno
Pasillos.paso = 40 -- px entre muestras del eje (4 m)
Pasillos.pendientePerfil = 8 -- grados como mucho a lo largo del perfil
Pasillos.pendienteCoste = 12 -- grados de referencia del coste (ESTILO-TERRENO §6.5)
Pasillos.pendienteProhibida = 22 -- grados: el A* no pisa celdas más empinadas
Pasillos.costeRio = 1600 -- px extra por celda de río (el cruce más corto gana)
Pasillos.costeJunto = 4 -- multiplica el coste junto a un pasillo ya trazado (que no se monten)
Pasillos.lateral = 3000 -- px del centro al paso de los pasillos laterales
Pasillos.suavizadoEje = 8 -- celdas de media móvil del eje del A*
Pasillos.suavizadoPerfil = 18 -- muestras a cada lado en la media del perfil (72 m)
Pasillos.mitadUtil = 300 -- px comprobados a cada lado del eje, más el margen hasta `mitad`
Pasillos.alturaSeca = 18 -- px sobre el mar: supera la orilla física de 6 px
Pasillos.costeAgua = 5000 -- px extra por celda: primero se prefiere rodear por tierra
Pasillos.alturaPuente = 16 -- reservado para futuros puentes físicos; las calzadas son terreno

local function suavizarPaso(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

-- Curvas -------------------------------------------------------------------------------------

--- Catmull-Rom por `xs, ys` remuestreada cada `paso` px (como `curva` del
-- script de Blender). Devuelve dos listas nuevas.
function Pasillos.curva(xs, ys, paso)
    local n = #xs
    if n < 2 then
        return { xs[1] }, { ys[1] }
    end
    -- Primero una polilínea densa (8 puntos por tramo) y luego se remuestrea
    -- por longitud: así la separación es la misma en curvas y rectas.
    local dx, dy = {}, {}
    for i = 1, n - 1 do
        local p0x, p0y = xs[math.max(1, i - 1)], ys[math.max(1, i - 1)]
        local p1x, p1y = xs[i], ys[i]
        local p2x, p2y = xs[i + 1], ys[i + 1]
        local p3x, p3y = xs[math.min(n, i + 2)], ys[math.min(n, i + 2)]
        for k = 0, 7 do
            local t = k / 8
            local t2, t3 = t * t, t * t * t
            dx[#dx + 1] = 0.5
                * (
                    2 * p1x
                    + (-p0x + p2x) * t
                    + (2 * p0x - 5 * p1x + 4 * p2x - p3x) * t2
                    + (-p0x + 3 * p1x - 3 * p2x + p3x) * t3
                )
            dy[#dy + 1] = 0.5
                * (
                    2 * p1y
                    + (-p0y + p2y) * t
                    + (2 * p0y - 5 * p1y + 4 * p2y - p3y) * t2
                    + (-p0y + 3 * p1y - 3 * p2y + p3y) * t3
                )
        end
    end
    dx[#dx + 1], dy[#dy + 1] = xs[n], ys[n]
    local rx, ry = { dx[1] }, { dy[1] }
    local resto = paso
    for i = 2, #dx do
        local ax, ay = dx[i - 1], dy[i - 1]
        local bx, by = dx[i], dy[i]
        local largo = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local recorrido = 0
        while largo - recorrido >= resto do
            recorrido = recorrido + resto
            local t = recorrido / largo
            rx[#rx + 1], ry[#ry + 1] = ax + (bx - ax) * t, ay + (by - ay) * t
            resto = paso
        end
        resto = resto - (largo - recorrido)
    end
    if resto < paso * 0.999 then
        rx[#rx + 1], ry[#ry + 1] = dx[#dx], dy[#dy]
    end
    return rx, ry
end

-- Rejilla del A* -------------------------------------------------------------------------------

--- Rejilla cuadrada de `celda` px sobre el límite del campo, con la altura del
-- terreno, la pendiente (grados) y qué celdas no se pueden pisar o son río.
function Pasillos.nuevaRejilla(suelo)
    local celda = Pasillos.celda
    local limite = suelo.limite
    local r = limite.radio
    local n = math.floor(2 * r / celda) + 1
    local x0, y0 = limite.cx - r, limite.cy - r
    local rej = suelo.relieve
    local h, pend, prohibida, bloqueada, aguaCelda, rio = {}, {}, {}, {}, {}, {}
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            h[k] = rej:interpolar(rej.h, x0 + i * celda, y0 + j * celda)
        end
    end
    local agua = suelo.agua
    local nivelMar = suelo.nivelMar
    local margen = Pasillos.mitad + 150
    local dentro = (r - margen) ^ 2
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            local x, y = x0 + i * celda, y0 + j * celda
            local ka, kb = i > 0 and k - 1 or k, i < n - 1 and k + 1 or k
            local kc, kd = j > 0 and k - n or k, j < n - 1 and k + n or k
            local gx = (h[kb] - h[ka]) / (celda * ((ka ~= k and 1 or 0) + (kb ~= k and 1 or 0)))
            local gy = (h[kd] - h[kc]) / (celda * ((kc ~= k and 1 or 0) + (kd ~= k and 1 or 0)))
            pend[k] = math.deg(math.atan(math.sqrt(gx * gx + gy * gy)))
            local fuera = (x - limite.cx) ^ 2 + (y - limite.cy) ^ 2 > dentro
            local mar = h[k] < nivelMar + Pasillos.alturaSeca
            local lago = agua and agua:lagoEn(x, y)
            bloqueada[k] = fuera or suelo:ocupado(x, y, margen)
            aguaCelda[k] = mar or lago or false
            prohibida[k] = bloqueada[k] or aguaCelda[k]
            rio[k] = agua and not lago and agua:rioEn(x, y, 25) or false
        end
    end
    return {
        n = n,
        x0 = x0,
        y0 = y0,
        celda = celda,
        h = h,
        pend = pend,
        prohibida = prohibida,
        bloqueada = bloqueada,
        aguaCelda = aguaCelda,
        nivelMar = nivelMar,
        rio = rio,
        cerca = {},
    }
end

--- Marca en la rejilla del A* las celdas junto al pasillo `p` (hasta dos
-- anchos y la transición del eje): el siguiente pasillo las evita si puede.
function Pasillos.marcarCerca(g, p)
    local r = 2 * Pasillos.mitad + Pasillos.transicion
    local celdas = math.ceil(r / g.celda)
    for s = 1, #p.x, 4 do
        local ci = math.floor((p.x[s] - g.x0) / g.celda + 0.5)
        local cj = math.floor((p.y[s] - g.y0) / g.celda + 0.5)
        for j = math.max(0, cj - celdas), math.min(g.n - 1, cj + celdas) do
            for i = math.max(0, ci - celdas), math.min(g.n - 1, ci + celdas) do
                if ((i - ci) ^ 2 + (j - cj) ^ 2) * g.celda * g.celda < r * r then
                    g.cerca[j * g.n + i] = true
                end
            end
        end
    end
end

--- Celda (i, j) de (x, y), dentro de la rejilla.
local function celdaDe(g, x, y)
    local i = math.floor((x - g.x0) / g.celda + 0.5)
    local j = math.floor((y - g.y0) / g.celda + 0.5)
    return math.max(0, math.min(g.n - 1, i)), math.max(0, math.min(g.n - 1, j))
end

--- Solo los obstáculos duros pueden desplazar un ancla de formación. El agua
-- permanece en su sitio y se salva elevando terreno, sin cambiar de isla.
local function puntosSeguros(g, puntos)
    local seguros = { lateral = puntos.lateral, ramal = puntos.ramal }
    for _, punto in ipairs(puntos) do
        local i, j = celdaDe(g, punto[1], punto[2])
        local x, y = punto[1], punto[2]
        if g.bloqueada[j * g.n + i] then
            local mejor, mejorD = nil, math.huge
            for radio = 1, g.n do
                for dj = -radio, radio do
                    for di = -radio, radio do
                        if math.max(math.abs(di), math.abs(dj)) == radio then
                            local a, b = i + di, j + dj
                            if a >= 0 and b >= 0 and a < g.n and b < g.n and not g.bloqueada[b * g.n + a] then
                                local px, py = g.x0 + a * g.celda, g.y0 + b * g.celda
                                local d = (px - x) ^ 2 + (py - y) ^ 2
                                if d < mejorD then
                                    mejor, mejorD = { px, py }, d
                                end
                            end
                        end
                    end
                end
                if mejor and radio * g.celda > math.sqrt(mejorD) + g.celda then
                    break
                end
            end
            assert(mejor, 'El edificio ocupa todo el campo de batalla')
            x, y = mejor[1], mejor[2]
        end
        seguros[#seguros + 1] = { x, y }
    end
    return seguros
end

local VECINOS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

--- A* de la celda (i0, j0) a (i1, j1): coste = distancia × (1 + (pendiente /
-- 12°)²), celdas de más de `maxPend` grados prohibidas y un extra fijo por
-- celda de río. Devuelve las celdas del camino (índices) o nil.
function Pasillos.aEstrella(g, i0, j0, i1, j1, maxPend, rellenar)
    local n, celda = g.n, g.celda
    local inicio, fin = j0 * n + i0, j1 * n + i1
    local prohibida = rellenar and g.bloqueada or g.prohibida
    local function permitida(k)
        return not prohibida[k] and g.pend[k] <= maxPend
    end
    if not permitida(inicio) or not permitida(fin) then
        return nil
    end
    local coste, padre, cerrado = { [inicio] = 0 }, {}, {}
    local montonK, montonF, tamano = { inicio }, { 0 }, 1
    local ref = Pasillos.pendienteCoste
    local function subir(p)
        while p > 1 do
            local q = math.floor(p / 2)
            if montonF[q] <= montonF[p] then
                break
            end
            montonK[q], montonK[p] = montonK[p], montonK[q]
            montonF[q], montonF[p] = montonF[p], montonF[q]
            p = q
        end
    end
    local function bajar(p)
        while true do
            local a, b = p * 2, p * 2 + 1
            local menor = p
            if a <= tamano and montonF[a] < montonF[menor] then
                menor = a
            end
            if b <= tamano and montonF[b] < montonF[menor] then
                menor = b
            end
            if menor == p then
                break
            end
            montonK[menor], montonK[p] = montonK[p], montonK[menor]
            montonF[menor], montonF[p] = montonF[p], montonF[menor]
            p = menor
        end
    end
    while tamano > 0 do
        local k = montonK[1]
        montonK[1], montonF[1] = montonK[tamano], montonF[tamano]
        montonK[tamano], montonF[tamano] = nil, nil
        tamano = tamano - 1
        bajar(1)
        if k == fin then
            local camino = { k }
            while padre[k] do
                k = padre[k]
                table.insert(camino, 1, k)
            end
            return camino
        end
        if not cerrado[k] then
            cerrado[k] = true
            local i, j = k % n, math.floor(k / n)
            for _, v in ipairs(VECINOS) do
                local a, b = i + v[1], j + v[2]
                if a >= 0 and b >= 0 and a < n and b < n then
                    local m = b * n + a
                    local pend = (g.pend[k] + g.pend[m]) * 0.5
                    local diagonal = v[1] ~= 0 and v[2] ~= 0
                    local esquinaLibre = not diagonal or (permitida(j * n + a) and permitida(b * n + i))
                    if not cerrado[m] and permitida(m) and esquinaLibre then
                        local d = diagonal and celda * math.sqrt(2) or celda
                        local costeAgua = 0
                        if rellenar and g.aguaCelda[m] then
                            costeAgua = Pasillos.costeAgua + math.max(0, g.nivelMar - g.h[m]) * 4
                        end
                        local c = coste[k]
                            + d * (1 + (pend / ref) ^ 2) * (g.cerca[m] and Pasillos.costeJunto or 1)
                            + (g.rio[m] and Pasillos.costeRio or 0)
                            + costeAgua
                        if not coste[m] or c < coste[m] then
                            coste[m] = c
                            padre[m] = k
                            local hx, hy = (a - i1) * celda, (b - j1) * celda
                            tamano = tamano + 1
                            montonK[tamano] = m
                            montonF[tamano] = c + math.sqrt(hx * hx + hy * hy)
                            subir(tamano)
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- Camino de A* entre dos puntos (px), pasando por `via` si se da. Devuelve
-- las listas de x e y de los centros de celda, o nil.
function Pasillos.ruta(g, puntos, rellenar)
    local xs, ys = {}, {}
    for p = 1, #puntos - 1 do
        local a, b = puntos[p], puntos[p + 1]
        local i0, j0 = celdaDe(g, a[1], a[2])
        local i1, j1 = celdaDe(g, b[1], b[2])
        local camino = Pasillos.aEstrella(g, i0, j0, i1, j1, rellenar and 90 or Pasillos.pendienteProhibida, rellenar)
        if not camino and not rellenar then
            camino = Pasillos.aEstrella(g, i0, j0, i1, j1, 45)
        end
        if not camino then
            return nil
        end
        for q = (p == 1) and 1 or 2, #camino do
            local k = camino[q]
            xs[#xs + 1] = g.x0 + (k % g.n) * g.celda
            ys[#ys + 1] = g.y0 + math.floor(k / g.n) * g.celda
        end
    end
    -- No buscar otra isla ni mover una formación para hacer que A* tenga éxito.
    -- Se conservan los extremos reales y solo se ajusta la geometría intermedia.
    xs[1], ys[1] = puntos[1][1], puntos[1][2]
    xs[#xs], ys[#ys] = puntos[#puntos][1], puntos[#puntos][2]
    return xs, ys
end

--- Media móvil de un eje de puntos (conserva los extremos).
local function mediaMovil(xs, ys, ventana)
    local n = #xs
    local rx, ry = {}, {}
    for i = 1, n do
        local a, b = math.max(1, i - ventana), math.min(n, i + ventana)
        local w = math.min(i - a, b - i)
        a, b = i - w, i + w
        local sx, sy = 0, 0
        for k = a, b do
            sx, sy = sx + xs[k], sy + ys[k]
        end
        rx[i], ry[i] = sx / (b - a + 1), sy / (b - a + 1)
    end
    return rx, ry
end

--- Remuestreo lineal: conserva las esquinas cuando una spline corta una orilla.
local function polilinea(xs, ys)
    local rx, ry = { xs[1] }, { ys[1] }
    for i = 2, #xs do
        local ax, ay = xs[i - 1], ys[i - 1]
        local dx, dy = xs[i] - ax, ys[i] - ay
        local pasos = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / Pasillos.paso))
        for k = 1, pasos do
            rx[#rx + 1], ry[#ry + 1] = ax + dx * k / pasos, ay + dy * k / pasos
        end
    end
    return rx, ry
end

--- Eje suavizado (media móvil y Catmull-Rom) que no pisa celdas prohibidas:
-- si al suavizar una curva se come una orilla, se suaviza menos.
function Pasillos.suavizarEje(g, xs, ys, rellenar)
    local ventana = Pasillos.suavizadoEje
    local prohibida = rellenar and g.bloqueada or g.prohibida
    while true do
        local mx, my = mediaMovil(xs, ys, ventana)
        local rx, ry = Pasillos.curva(mx, my, Pasillos.paso)
        local limpio = true
        for i = 1, #rx do
            local a, b = celdaDe(g, rx[i], ry[i])
            if prohibida[b * g.n + a] then
                limpio = false
                break
            end
        end
        if limpio then
            return rx, ry
        end
        if ventana == 0 then
            return polilinea(xs, ys)
        end
        ventana = math.floor(ventana / 2)
    end
end

-- Pasillos -------------------------------------------------------------------------------------

--- Puntos de paso de cada pasillo: de la zona de formación del atacante a la
-- del defensor, uno directo y dos por los lados. El objetivo añade un ramal,
-- sin sustituir nunca el extremo de la formación defensora.
function Pasillos.puntosDePaso(suelo, combate)
    local ca, sa = math.cos(combate.angulo or 0), math.sin(combate.angulo or 0)
    local frente = combate.separacion or 8500
    local sep = math.min(frente + 3000, suelo.limite.radio - 950)
    local cx, cy = suelo.cx, suelo.cy
    local px, py = -sa, ca
    local lista = {}
    for _, lado in ipairs({ 0, -1, 1 }) do
        local o = lado * Pasillos.lateral
        local a = { cx - ca * sep + px * o * 0.25, cy - sa * sep + py * o * 0.25 }
        local m = { cx + px * o, cy + py * o }
        local b = { cx + ca * sep + px * o * 0.25, cy + sa * sep + py * o * 0.25 }
        if lado == 0 then
            lista[#lista + 1] = { a, { cx - ca * frente, cy - sa * frente }, { cx + ca * frente, cy + sa * frente }, b }
        else
            lista[#lista + 1] = { a, m, b, lateral = true }
        end
    end
    local sitio = suelo.sitio
    if sitio and suelo.limite:dentro(sitio.x, sitio.y, 600) then
        -- La puerta del objetivo: su lado que mira al atacante.
        local r = (suelo:radioEdificio() + Pasillos.mitad + 200) * math.sqrt(2)
        local dx, dy = cx - ca * sep - sitio.x, cy - sa * sep - sitio.y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        lista[#lista + 1] = { lista[1][1], { sitio.x + dx / d * r, sitio.y + dy / d * r }, ramal = true }
    end
    return lista
end

--- Traza los pasillos, hace sus perfiles y aplana el terreno debajo. Deja en
-- `suelo.pasillos` la lista { x = {}, y = {}, h = {}, puentes = {} } y en la
-- rejilla del terreno `rej.dPasillo` (px al eje más cercano).
function Pasillos.generar(suelo, combate)
    local lista = {}
    suelo.pasillos = lista
    local rej = suelo.relieve
    rej.dPasillo = rej.dPasillo or require('batalla.rejilla').array(rej.total)
    for k = 0, rej.total - 1 do
        rej.dPasillo[k] = 1e9
    end
    if not combate then
        return lista
    end
    local g = Pasillos.nuevaRejilla(suelo)
    suelo.rejillaPasillos = g
    -- El núcleo del principal queda protegido cuando se abren los laterales.
    local hecho = {}
    for indice, puntos in ipairs(Pasillos.puntosDePaso(suelo, combate)) do
        puntos = puntosSeguros(g, puntos)
        local xs, ys = Pasillos.ruta(g, puntos)
        local rellenar = false
        if not xs and indice == 1 then
            xs, ys = Pasillos.ruta(g, puntos, true)
            rellenar = true
            assert(xs, 'No se puede conectar las zonas de formación dentro del campo de batalla')
        end
        -- Si el paso lateral cae en una isla o en el agua, se prueba más
        -- cerca y más lejos del centro.
        for _, f in ipairs({ 0.6, 1.4, 0.3 }) do
            if xs or not puntos.lateral then
                break
            end
            local m = puntos[2]
            local prueba = {
                puntos[1],
                { suelo.cx + (m[1] - suelo.cx) * f, suelo.cy + (m[2] - suelo.cy) * f },
                puntos[3],
            }
            xs, ys = Pasillos.ruta(g, prueba)
        end
        if xs and #xs >= 2 then
            xs, ys = Pasillos.suavizarEje(g, xs, ys, rellenar)
            local p =
                { x = xs, y = ys, puentes = {}, garantizado = indice == 1, relleno = rellenar, ramal = puntos.ramal }
            Pasillos.perfil(suelo, p)
            local cambios = Pasillos.aplanar(suelo, p, hecho)
            local valido, validacion = Pasillos.validar(suelo, p)
            if p.garantizado then
                -- Las curvas muy cerradas pueden amplificar la pendiente en
                -- el interior. Reducir el relieve del perfil mantiene el eje
                -- natural; el último intento lo deja horizontal y seco.
                local referencia = 0
                for _, altura in ipairs(p.h) do
                    referencia = referencia + altura / #p.h
                end
                for intento = 1, 5 do
                    if valido then
                        break
                    end
                    local factor = intento == 5 and 0 or 0.5
                    for k = 1, #p.h do
                        p.h[k] = referencia + (p.h[k] - referencia) * factor
                    end
                    Pasillos.aplanar(suelo, p, hecho)
                    valido, validacion = Pasillos.validar(suelo, p)
                end
                assert(valido, 'El pasillo principal no es transitable: ' .. (validacion.motivo or 'relieve'))
            end
            p.validacion = validacion
            if valido then
                Pasillos.marcarCerca(g, p)
                lista[#lista + 1] = p
            else
                -- Un lateral opcional nunca deja un corte fallido sobre otro
                -- pasillo ni marca vegetación despejada donde no hay ruta.
                for _, cambio in ipairs(cambios) do
                    local k = cambio[1]
                    rej.h[k], rej.dPasillo[k], hecho[k] = cambio[2], cambio[3], cambio[4]
                end
            end
        end
    end
    assert(#lista > 0 and lista[1].garantizado, 'La batalla necesita al menos un pasillo entre bandos')
    return lista
end

--- Perfil seco del terreno real, suavizado y limitado en ambos sentidos.
-- Agua aún no implementa puentes físicos: ninguna ruta depende de un tablero.
function Pasillos.perfil(suelo, p)
    local rej = suelo.relieve
    local n = #p.x
    local crudo = {}
    local minimo = suelo.nivelMar + Pasillos.alturaSeca
    for i = 1, n do
        local x, y = p.x[i], p.y[i]
        crudo[i] = math.max(minimo, rej:interpolar(rej.h, x, y))
    end
    local h = {}
    local v = Pasillos.suavizadoPerfil
    for k = 1, n do
        local a, b = math.max(1, k - v), math.min(n, k + v)
        local s = 0
        for q = a, b do
            s = s + crudo[q]
        end
        h[k] = s / (b - a + 1)
    end
    local tangente = math.tan(math.rad(Pasillos.pendientePerfil))
    local ds = {}
    for k = 2, n do
        ds[k] = math.sqrt((p.x[k] - p.x[k - 1]) ^ 2 + (p.y[k] - p.y[k - 1]) ^ 2) * tangente
    end
    for k = 2, n do
        h[k] = math.max(h[k - 1] - ds[k], math.min(h[k - 1] + ds[k], h[k]))
    end
    for k = n - 1, 1, -1 do
        h[k] = math.max(h[k + 1] - ds[k + 1], math.min(h[k + 1] + ds[k + 1], h[k]))
    end
    p.h = h
end

--- Estampa el pasillo `p` en la rejilla del terreno: por vértice, la
-- distancia al eje y la altura del perfil allí; luego mezcla la del mapa con
-- la del perfil, pesada por lo dentro que queda. `hecho` (peso por vértice de
-- los pasillos ya estampados) protege su franja.
function Pasillos.aplanar(suelo, p, hecho)
    local rej = suelo.relieve
    local px, py, ph = rej.x, rej.y, rej.h
    local dPasillo = rej.dPasillo
    local alcance = Pasillos.mitad + Pasillos.transicion
    local dMin, hMin = {}, {}
    for s = 1, #p.x - 1 do
        local ax, ay, bx, by = p.x[s], p.y[s], p.x[s + 1], p.y[s + 1]
        local ha, hb = p.h[s], p.h[s + 1]
        local ux, uy = bx - ax, by - ay
        local l2 = math.max(1e-6, ux * ux + uy * uy)
        local i0, j0 = rej:cuadro(math.min(ax, bx) - alcance, math.min(ay, by) - alcance)
        local i1, j1 = rej:cuadro(math.max(ax, bx) + alcance, math.max(ay, by) + alcance)
        for j = j0, math.min(rej.lado - 1, j1 + 1) do
            for i = i0, math.min(rej.lado - 1, i1 + 1) do
                local k = j * rej.lado + i
                local t = ((px[k] - ax) * ux + (py[k] - ay) * uy) / l2
                t = math.max(0, math.min(1, t))
                local qx, qy = ax + ux * t - px[k], ay + uy * t - py[k]
                local d = math.sqrt(qx * qx + qy * qy)
                if d < alcance and (not dMin[k] or d < dMin[k]) then
                    dMin[k] = d
                    hMin[k] = ha + (hb - ha) * t
                end
            end
        end
    end
    local orden = {}
    for k in pairs(dMin) do
        orden[#orden + 1] = k
    end
    table.sort(orden)
    local cambios = {}
    for _, k in ipairs(orden) do
        local d = dMin[k]
        local w = 1 - suavizarPaso((d - Pasillos.mitad) / Pasillos.transicion)
        if not p.garantizado then
            cambios[#cambios + 1] = { k, ph[k], dPasillo[k], hecho[k] }
        end
        dPasillo[k] = math.min(dPasillo[k], d)
        -- Toda la anchura se estampa también sobre el mar. La malla elevada
        -- es a la vez lo que se dibuja, lo que pisa el vehículo y su orilla.
        local libre = p.garantizado and w or w * (1 - (hecho[k] or 0))
        if libre > 0 then
            ph[k] = ph[k] + (hMin[k] - ph[k]) * libre
        end
        hecho[k] = math.max(hecho[k] or 0, w)
    end
    return cambios
end

--- Comprueba la superficie triangulada, sin depender de normales almacenadas
-- ni del perfil ideal. Muestrea cada 20 px y cada 100 px a lo ancho del paso.
-- El margen restante hasta `mitad` protege los triángulos y el radio físico.
function Pasillos.validar(suelo, p)
    local datos = {
        valido = true,
        muestras = 0,
        pendienteMaxima = 0,
        alturaMinima = math.huge,
        anchoUtil = Pasillos.mitadUtil * 2,
    }
    local rej = suelo.relieve
    local pendienteMaxima = math.min(22, suelo.pendienteTransitable or 25)
    for i = 1, #p.x - 1 do
        local ax, ay = p.x[i], p.y[i]
        local dx, dy = p.x[i + 1] - ax, p.y[i + 1] - ay
        local largo = math.sqrt(dx * dx + dy * dy)
        if largo > 1e-6 then
            local nx, ny = -dy / largo, dx / largo
            local pasos = math.max(1, math.ceil(largo / (Pasillos.paso * 0.5)))
            for j = 0, pasos do
                local x, y = ax + dx * j / pasos, ay + dy * j / pasos
                for lateral = -Pasillos.mitadUtil, Pasillos.mitadUtil, 100 do
                    local px, py = x + nx * lateral, y + ny * lateral
                    local h, _, _, nz = rej:alturaNormal(px, py)
                    local pendiente = math.deg(math.acos(math.max(-1, math.min(1, nz))))
                    datos.muestras = datos.muestras + 1
                    datos.alturaMinima = math.min(datos.alturaMinima, h)
                    datos.pendienteMaxima = math.max(datos.pendienteMaxima, pendiente)
                    local motivo
                    if h < suelo.nivelMar + 7 then
                        motivo = 'agua'
                    elseif pendiente > pendienteMaxima then
                        motivo = 'pendiente'
                    elseif not suelo.limite:dentro(px, py) then
                        motivo = 'límite'
                    elseif suelo:ocupado(px, py) then
                        motivo = 'edificio'
                    end
                    if motivo then
                        datos.valido, datos.motivo, datos.x, datos.y = false, motivo, px, py
                        return false, datos
                    end
                end
            end
        end
    end
    return true, datos
end

--- Distancia (px) de (x, y) al eje del pasillo más cercano, por la rejilla.
function Pasillos.distancia(suelo, x, y)
    local rej = suelo.relieve
    if not rej or not rej.dPasillo then
        return math.huge
    end
    return rej:interpolar(rej.dPasillo, x, y)
end

return Pasillos

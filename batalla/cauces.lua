-- Ríos y cañones de la batalla (Valeria). Solo existen en la escena 3D: el
-- mapa 2D sigue plano y `Terreno:altura` no cambia (ciudades, yacimientos,
-- simulación y caché del mapa quedan igual).
--
-- Todo sale de la semilla y del centro de la batalla (mismo sitio, mismo
-- cauce en todas las máquinas):
--   tipo      por hash del sitio y la humedad del mapa: nada (la mayoría),
--             río, cañón o cañón con río en el fondo
--   trazado   A* sobre la altura táctica (antes de tallar): busca lo bajo,
--             rodea las explanadas de formación y el edificio, y cruza el
--             área de borde a borde hasta el faldón; luego Catmull-Rom y un
--             meandro suave. El agua baja siempre desde el extremo más alto
--   tallado   tras los pasillos (batalla/pasillos.lua, que no cambian): cauce con
--             orillas (ESTILO-TERRENO §6.2) o garganta con escalones de roca.
--             Donde un pasillo cruza, el cauce se vuelve vado (el río) o
--             rampa (el cañón) de pendiente suave: los vehículos siempre
--             pueden llegar de un bando al otro
--   agua      una cinta a lo largo del eje, a su nivel, en la misma malla
--             que el mar (batalla/suelo.lua, `construirAgua`)
--
-- El río hondo no se pisa (batalla/agua.lua): solo por los vados.

local Ruido = require('mundo.ruido')
local Terreno = require('mundo.terreno')
local Pasillos = require('batalla.pasillos')

local Cauces = {}
Cauces.__index = Cauces

-- Tipo forzado para las pruebas ('rio', 'canon', 'canonRio' o 'ninguno'); nil
-- en el juego.
Cauces.forzado = nil

Cauces.probRio = 0.24 -- base; la humedad del mapa la sube o la baja
Cauces.probCanon = 0.16
Cauces.probRioEnCanon = 0.5

Cauces.radio = 21000 -- px del centro a los extremos del trazado (el faldón llega hasta 20 500 con detalle)
Cauces.radioAgua = 20200 -- px: la cinta del agua acaba aquí (más allá el faldón es muy grueso)
Cauces.celdaRuta = 200 -- px de la rejilla del A* del trazado
Cauces.muestra = 20 -- px entre muestras del eje
Cauces.tramo = 5 -- muestras por tramo de la búsqueda de distancias (100 px)
Cauces.alcance = 2000 -- px: hasta aquí del eje puede cambiar el terreno
Cauces.celdaCubo = 500 -- px de los cubos de la búsqueda de distancias
Cauces.caida = 0.01 -- px que baja el agua como mínimo por muestra (0,05 %)
Cauces.minimoDentro = 6000 -- px de cauce dentro del área para que valga la pena

-- Río (ESTILO-TERRENO §6.2, en px).
Cauces.anchoMin = 55 -- px de ancho del agua (5,5 m)
Cauces.anchoMax = 95
Cauces.hondo = 12 -- px del agua al lecho en el centro
Cauces.taludOrilla = 0.35 -- subida de la orilla por px fuera del cauce (19°)
Cauces.valle = 30 -- px que se hunde el valle del río en su eje (3 m)
Cauces.radioValle = 420

-- Cañón.
Cauces.hondoCanonMin = 130 -- px (13 m)
Cauces.hondoCanonMax = 260
Cauces.fondoMin = 140 -- px de medio ancho del fondo
Cauces.fondoMax = 260
Cauces.paredMin = 140 -- px de ancho de cada pared
Cauces.paredMax = 260
Cauces.escalones = 3
Cauces.hondoCanonUtil = 80 -- px: menos hondo no es un cañón (llanuras junto al mar)
Cauces.largoCanon = 1500 -- px de garganta honda dentro del límite para que haya cañón
Cauces.taludBorde = 1.0 -- pendiente fuera de la pared (para fundirse con lomas)

-- Vados y rampas donde cruzan los pasillos.
Cauces.vadoHondo = 3 -- px de agua sobre el vado (0,3 m): se pisa
Cauces.rampa = 0.18 -- pendiente de la rampa (10°)

local function suave(a, b, x)
    local t = math.min(1, math.max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

--- Número de 0 a 1 por hash. Se vuelve a mezclar con la sal: con un solo
-- `Ruido.hash`, dos sales seguidas daban números muy correlacionados.
local function azar01(semilla, a, b, sal)
    return Ruido.hash(Ruido.hash(semilla, a, b, sal), sal, 0, 0) / 4294967296
end

--- ¿Qué cauce lleva la batalla de centro (cx, cy)? 'ninguno', 'rio',
-- 'canon' o 'canonRio'.
function Cauces.tipoEn(terreno, cx, cy)
    if Cauces.forzado then
        return Cauces.forzado
    end
    local semilla = terreno.semilla
    local a, b = math.floor(cx / 100), math.floor(cy / 100)
    local humedad = math.max(-1, math.min(1, terreno:humedadEn(cx, cy)))
    local pRio = Cauces.probRio + 0.15 * humedad
    local pCanon = Cauces.probCanon - 0.08 * humedad
    local u = azar01(semilla, a, b, 61)
    if u < pRio then
        return 'rio'
    elseif u < pRio + pCanon then
        return azar01(semilla, a, b, 62) < Cauces.probRioEnCanon and 'canonRio' or 'canon'
    end
    return 'ninguno'
end

--- Cauce de la batalla del suelo (después de los pasillos). Siempre devuelve
-- el objeto; sin cauce, `self.hay` es falso y nada cambia.
function Cauces.nuevo(suelo)
    local self = setmetatable({}, Cauces)
    self.suelo = suelo
    self.tipo = Cauces.tipoEn(suelo.terreno, suelo.cx, suelo.cy)
    self.hay = false
    self.rio = self.tipo == 'rio' or self.tipo == 'canonRio'
    self.canon = self.tipo == 'canon' or self.tipo == 'canonRio'
    if self.tipo ~= 'ninguno' then
        self:trazar()
    end
    if not self.hay then
        self.tipo, self.rio, self.canon = 'ninguno', false, false
    end
    return self
end

-- Trazado --------------------------------------------------------------------------------------

--- Altura táctica antes de tallar: la rejilla dentro del área y el faldón fuera.
function Cauces:alturaBase(x, y)
    local s = self.suelo
    local medio = s.lado / 2
    if math.abs(x - s.cx) <= medio and math.abs(y - s.cy) <= medio then
        return s.relieve:interpolar(s.relieve.h, x, y)
    end
    return s:alturaFaldonBase(x, y)
end

--- A* sobre una rejilla de `celdaRuta` px entre (x0, y0) y (x1, y1). El coste
-- del río sube con la altura sobre lo más bajo (el agua busca los valles); el
-- del cañón, con lo que le falta para lo alto (corta las lomas). Con un ruido
-- suave (para que no vaya recto en la llanura) y caro en el mar, la costa, las
-- explanadas y los pasillos.
function Cauces:buscarRuta(x0, y0, x1, y1)
    local celda = Cauces.celdaRuta
    local rejilla = self.rejillaRuta or self:prepararRuta()
    local n, ox, oy, coste = rejilla.n, rejilla.ox, rejilla.oy, rejilla.coste
    local function celdaDe(x, y)
        local i = math.max(0, math.min(n - 1, math.floor((x - ox) / celda + 0.5)))
        local j = math.max(0, math.min(n - 1, math.floor((y - oy) / celda + 0.5)))
        return j * n + i
    end
    local inicio, fin = celdaDe(x0, y0), celdaDe(x1, y1)
    if not coste[inicio] or not coste[fin] then
        return nil
    end
    return self:buscarRutaEn(rejilla, inicio, fin)
end

--- Rejilla del A* del trazado: coste por celda (false donde no puede ir).
function Cauces:prepararRuta()
    local s = self.suelo
    local celda = Cauces.celdaRuta
    local r = Cauces.radio + celda * 3
    local n = math.floor(2 * r / celda) + 1
    local ox, oy = s.cx - r, s.cy - r
    local h, coste = {}, {}
    local bajo = math.huge
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            h[k] = self:alturaBase(ox + i * celda, oy + j * celda)
            bajo = math.min(bajo, math.max(h[k], s.nivelMar))
        end
    end
    -- El cañón busca lo alto (corta lomas y montes); el río, lo bajo.
    local ordenadas = {}
    for k = 0, n * n - 1, 7 do
        ordenadas[#ordenadas + 1] = h[k]
    end
    table.sort(ordenadas)
    local alto = ordenadas[math.max(1, math.floor(#ordenadas * 0.92))]
    local ruido = Ruido.nuevo(s.terreno.semilla + 27201)
    local radioEdificio = s.sitio and (s:radioEdificio() + 1200) or 0
    -- Celdas de tierra junto al mar o a un lago (a dos celdas): el río no
    -- bordea la costa, va tierra adentro de lago en lago.
    local mar = s.nivelMar + 4
    local costa = {}
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            if h[k] >= mar then
                for dj = -2, 2 do
                    for di = -2, 2 do
                        local a, b = i + di, j + dj
                        if a >= 0 and b >= 0 and a < n and b < n and h[b * n + a] < mar then
                            costa[k] = true
                        end
                    end
                end
            end
        end
    end
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local k = j * n + i
            local x, y = ox + i * celda, oy + j * celda
            local altura = self.canon and math.max(0, alto - h[k]) or math.max(0, h[k] - bajo)
            local c = 1 + altura / 60 + 0.6 * (0.5 + 0.5 * ruido:simplex(x / 2600, y / 2600))
            if h[k] < mar then
                c = c * 2.5
            elseif costa[k] then
                c = c + 2.5
            end
            if s:pesoExplanada(x, y) > 0 then
                c = c + 60
            end
            -- Dentro de un pasillo de avance, caro: lo cruza por lo corto.
            if Pasillos.distancia(s, x, y) < Pasillos.mitad + Pasillos.transicion then
                c = c + 12
            end
            if s.sitio and math.abs(x - s.sitio.x) < radioEdificio and math.abs(y - s.sitio.y) < radioEdificio then
                c = false
            end
            coste[k] = c
        end
    end
    self.rejillaRuta = { n = n, ox = ox, oy = oy, coste = coste }
    return self.rejillaRuta
end

--- A* de la celda `inicio` a `fin` en la rejilla del trazado. Devuelve las
-- listas de x e y de los centros de celda, o nil.
function Cauces:buscarRutaEn(rejilla, inicio, fin)
    local celda = Cauces.celdaRuta
    local n, ox, oy, coste = rejilla.n, rejilla.ox, rejilla.oy, rejilla.coste
    local fx, fy = fin % n, math.floor(fin / n)
    local g, padre, cerrado = { [inicio] = 0 }, {}, {}
    local montonK, montonF, tamano = { inicio }, { 0 }, 1
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
            local xs, ys = {}, {}
            while k do
                table.insert(xs, 1, ox + (k % n) * celda)
                table.insert(ys, 1, oy + math.floor(k / n) * celda)
                k = padre[k]
            end
            return xs, ys
        end
        if not cerrado[k] then
            cerrado[k] = true
            local i, j = k % n, math.floor(k / n)
            for dj = -1, 1 do
                for di = -1, 1 do
                    local a, b = i + di, j + dj
                    if (di ~= 0 or dj ~= 0) and a >= 0 and b >= 0 and a < n and b < n then
                        local m = b * n + a
                        if coste[m] and not cerrado[m] then
                            local d = (di ~= 0 and dj ~= 0) and celda * 1.4142 or celda
                            local c = g[k] + d * (coste[k] + coste[m]) * 0.5
                            if not g[m] or c < g[m] then
                                g[m] = c
                                padre[m] = k
                                local hx, hy = (a - fx) * celda, (b - fy) * celda
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
    end
    return nil
end

--- Media móvil (conserva los extremos).
local function mediaMovil(xs, ys, ventana)
    local n = #xs
    local rx, ry = {}, {}
    for i = 1, n do
        local w = math.min(ventana, i - 1, n - i)
        local sx, sy = 0, 0
        for k = i - w, i + w do
            sx, sy = sx + xs[k], sy + ys[k]
        end
        rx[i], ry[i] = sx / (2 * w + 1), sy / (2 * w + 1)
    end
    return rx, ry
end

--- Extremos del trazado: dos puntos casi opuestos en el círculo de `radio`,
-- girados por hash, en tierra si se puede.
function Cauces:extremos()
    local s = self.suelo
    local semilla = s.terreno.semilla
    local a, b = math.floor(s.cx / 100), math.floor(s.cy / 100)
    local angulo = azar01(semilla, a, b, 63) * math.pi * 2
    local desvio = (azar01(semilla, a, b, 64) - 0.5) * 1.1
    local r = Cauces.radio
    local function enTierra(th)
        for k = 0, 11 do
            local t = th + (k % 2 == 0 and 1 or -1) * math.floor((k + 1) / 2) * 0.12
            local x, y = s.cx + math.cos(t) * r, s.cy + math.sin(t) * r
            if self:alturaBase(x, y) > s.nivelMar + 10 then
                return x, y
            end
        end
        return s.cx + math.cos(th) * r, s.cy + math.sin(th) * r
    end
    local x0, y0 = enTierra(angulo)
    local x1, y1 = enTierra(angulo + math.pi + desvio)
    -- Punto de paso cerca del centro, en tierra y fuera de las explanadas: el
    -- cauce cruza el campo de batalla en vez de rodearlo.
    local radio = 800 + 4500 * azar01(semilla, a, b, 70)
    local giro = azar01(semilla, a, b, 71) * math.pi * 2
    local vx, vy = s.cx, s.cy
    for k = 0, 15 do
        local t = giro + k * 0.4
        local px, py = s.cx + math.cos(t) * radio, s.cy + math.sin(t) * radio
        if self:alturaBase(px, py) > s.nivelMar + 10 and s:pesoExplanada(px, py) == 0 then
            vx, vy = px, py
            break
        end
    end
    return x0, y0, x1, y1, vx, vy
end

--- Traza el eje y le pone los datos por muestra: nivel del agua, medio ancho
-- del agua y, en el cañón, cota del borde, hondo, fondo y pared.
function Cauces:trazar()
    local s = self.suelo
    local x0, y0, x1, y1, vx, vy = self:extremos()
    local xs, ys = self:buscarRuta(x0, y0, vx, vy)
    local xs2, ys2 = self:buscarRuta(vx, vy, x1, y1)
    if not xs or not xs2 or #xs + #xs2 < 8 then
        return
    end
    for k = 2, #xs2 do
        xs[#xs + 1], ys[#ys + 1] = xs2[k], ys2[k]
    end
    xs, ys = mediaMovil(xs, ys, 3)
    xs, ys = Pasillos.curva(xs, ys, Cauces.muestra)
    -- Meandro: desplazamiento lateral con ruido, nulo en los extremos y fuera
    -- del área (el faldón es grueso y lo quiere recto).
    local semilla = s.terreno.semilla
    local ruido = Ruido.nuevo(semilla + 27202)
    local amplitud = self.canon and 120 or 220
    local n = #xs
    local mx, my = {}, {}
    for i = 1, n do
        local a, b = math.max(1, i - 1), math.min(n, i + 1)
        local tx, ty = xs[b] - xs[a], ys[b] - ys[a]
        local l = math.max(1e-6, math.sqrt(tx * tx + ty * ty))
        local dentro = math.max(math.abs(xs[i] - s.cx), math.abs(ys[i] - s.cy))
        local peso = 1 - suave(s.lado / 2 - 2500, s.lado / 2, dentro)
        local o = ruido:simplex(i * Cauces.muestra / 1800, 0.5) * amplitud * peso
        mx[i], my[i] = xs[i] - ty / l * o, ys[i] + tx / l * o
    end
    xs, ys = Pasillos.curva(mx, my, Cauces.muestra)
    n = #xs

    -- Altura del terreno en el eje y tramos en tierra.
    local hEje = {}
    for i = 1, n do
        hEje[i] = self:alturaBase(xs[i], ys[i])
    end
    -- Por el mar y los lagos no corre: el río va de lago en lago (cada tramo
    -- en tierra baja hacia su extremo más bajo, ver `datosEje`).
    local eje = { x = xs, y = ys, hTerreno = hEje, tierra = {} }
    local dentro = 0
    for i = 1, n do
        eje.tierra[i] = hEje[i] > s.nivelMar + 2
        if eje.tierra[i] and s.limite:dentro(xs[i], ys[i]) then
            dentro = dentro + 1
        end
    end
    -- Que valga la pena: bastante cauce en tierra dentro del límite.
    if dentro * Cauces.muestra < Cauces.minimoDentro then
        return
    end
    self.eje = eje
    if not self:datosEje() then
        return
    end
    self:prepararBusqueda()
    self.hay = true
end

--- Datos por muestra del eje: el río (ancho y nivel, siempre cuesta abajo) y
-- el cañón (cota del borde suavizada, hondo, fondo y pared con ruido).
function Cauces:datosEje()
    local s = self.suelo
    local e = self.eje
    local n = #e.x
    local semilla = s.terreno.semilla
    local a, b = math.floor(s.cx / 100), math.floor(s.cy / 100)
    local ruido = Ruido.nuevo(semilla + 27203)
    -- Cota del borde: media móvil larga (unos 160 m) del terreno más bajo
    -- entre el eje y los dos lados del cañón. A media ladera, el lado de abajo
    -- también tiene pared (si no, queda una repisa en vez de una garganta).
    local fondo0 = Cauces.fondoMin + (Cauces.fondoMax - Cauces.fondoMin) * azar01(semilla, a, b, 66)
    local pared0 = Cauces.paredMin + (Cauces.paredMax - Cauces.paredMin) * azar01(semilla, a, b, 67)
    local bajo = {}
    for i = 1, n do
        bajo[i] = e.hTerreno[i]
        if self.canon then
            local p, q = math.max(1, i - 1), math.min(n, i + 1)
            local tx, ty = e.x[q] - e.x[p], e.y[q] - e.y[p]
            local l = math.max(1e-6, math.sqrt(tx * tx + ty * ty))
            local r = fondo0 + pared0
            for _, lado in ipairs({ -1, 1 }) do
                local h = self:alturaBase(e.x[i] - ty / l * r * lado, e.y[i] + tx / l * r * lado)
                bajo[i] = math.min(bajo[i], h)
            end
        end
    end
    local ventana = 40
    local borde = {}
    for i = 1, n do
        local w = math.min(ventana, i - 1, n - i)
        local suma = 0
        for k = i - w, i + w do
            suma = suma + bajo[k]
        end
        borde[i] = suma / (2 * w + 1)
    end
    -- Un cañón necesita relieve que cortar: en la llanura junto al mar no
    -- cabe (sin inventar terreno) y se apaga. Si en el límite no queda un
    -- tramo hondo de `largoCanon`, queda el río o nada.
    if self.canon then
        local util = 0
        for i = 1, n do
            if s.limite:dentro(e.x[i], e.y[i]) and borde[i] - s.nivelMar - 30 >= Cauces.hondoCanonUtil then
                util = util + 1
            end
        end
        if util * Cauces.muestra < Cauces.largoCanon then
            self.canon = false
            if not self.rio then
                return false
            end
            self.tipo = 'rio'
        end
    end
    e.borde, e.hondo, e.fondo, e.pared, e.nivel, e.ancho, e.s = {}, {}, {}, {}, {}, {}, {}
    local hondo0 = Cauces.hondoCanonMin + (Cauces.hondoCanonMax - Cauces.hondoCanonMin) * azar01(semilla, a, b, 65)
    local ancho0 = Cauces.anchoMin + (Cauces.anchoMax - Cauces.anchoMin) * azar01(semilla, a, b, 68)
    local recorrido = 0
    for i = 1, n do
        if i > 1 then
            recorrido = recorrido + math.sqrt((e.x[i] - e.x[i - 1]) ^ 2 + (e.y[i] - e.y[i - 1]) ^ 2)
        end
        e.s[i] = recorrido
        local r1 = ruido:simplex(recorrido / 3000, 1.5)
        local r2 = ruido:simplex(recorrido / 2200, 7.5)
        e.borde[i] = borde[i]
        -- El fondo del cañón nunca baja hasta el mar.
        e.hondo[i] = math.max(0, math.min(hondo0 * (1 + 0.2 * r1), borde[i] - s.nivelMar - 30))
        e.fondo[i] = fondo0 * (1 + 0.3 * r2)
        e.pared[i] = pared0 * (1 + 0.3 * r1)
        -- El río crece un poco agua abajo.
        e.ancho[i] = ancho0 * (0.85 + 0.3 * i / n) * (self.canon and 0.8 or 1)
    end
    -- Nivel del agua: por debajo del suelo del eje (o del fondo del cañón) y
    -- siempre cuesta abajo, en cada tramo en tierra desde su extremo más
    -- alto; nunca bajo el mar (en el mar y los lagos, el del mar).
    local caida = Cauces.caida
    local i = 1
    while i <= n do
        if not e.tierra[i] then
            e.nivel[i] = s.nivelMar + 1
            i = i + 1
        else
            local fin = i
            while fin < n and e.tierra[fin + 1] do
                fin = fin + 1
            end
            local desde, hasta, paso = i, fin, 1
            if e.hTerreno[fin] > e.hTerreno[i] then
                desde, hasta, paso = fin, i, -1
            end
            local anterior
            for q = desde, hasta, paso do
                local suelo = self.canon and (e.borde[q] - e.hondo[q]) or e.hTerreno[q]
                local tope = suelo - Cauces.hondo
                local nivel = anterior and math.min(anterior - caida, tope) or tope
                anterior = nivel
                e.nivel[q] = math.max(nivel, s.nivelMar + 1)
            end
            i = fin + 1
        end
    end
    return true
end

--- Cubos de `celdaCubo` px con los tramos (de `tramo` muestras) que pueden
-- quedar a menos de `alcance` px: la distancia al eje se busca solo en ellos.
function Cauces:prepararBusqueda()
    local e = self.eje
    local n = #e.x
    local c = Cauces.celdaCubo
    local alcance = Cauces.alcance
    local cubos = {}
    local tramos = {}
    for a = 1, n - 1, Cauces.tramo do
        local b = math.min(n, a + Cauces.tramo)
        tramos[#tramos + 1] = a
        local t = #tramos
        local x0 = math.min(e.x[a], e.x[b]) - alcance
        local x1 = math.max(e.x[a], e.x[b]) + alcance
        local y0 = math.min(e.y[a], e.y[b]) - alcance
        local y1 = math.max(e.y[a], e.y[b]) + alcance
        for j = math.floor(y0 / c), math.floor(y1 / c) do
            for i = math.floor(x0 / c), math.floor(x1 / c) do
                local clave = i * 131072 + j
                local lista = cubos[clave]
                if not lista then
                    lista = {}
                    cubos[clave] = lista
                end
                lista[#lista + 1] = t
            end
        end
    end
    self.cubos = cubos
    self.tramos = tramos
end

--- Distancia (px) de (x, y) al eje y su posición en él (muestra `i` y
-- fracción `f` hacia la siguiente). math.huge si queda más lejos que `alcance`.
function Cauces:cercano(x, y)
    local e = self.eje
    local c = Cauces.celdaCubo
    local lista = self.cubos[math.floor(x / c) * 131072 + math.floor(y / c)]
    if not lista then
        return math.huge
    end
    local mejor, mi, mf = math.huge, 1, 0
    local n = #e.x
    local ex, ey = e.x, e.y
    for q = 1, #lista do
        local a = self.tramos[lista[q]]
        local b = math.min(n, a + Cauces.tramo)
        local ax, ay = ex[a], ey[a]
        local ux, uy = ex[b] - ax, ey[b] - ay
        local l2 = ux * ux + uy * uy
        local t = 0
        if l2 > 1e-9 then
            t = math.max(0, math.min(1, ((x - ax) * ux + (y - ay) * uy) / l2))
        end
        local dx, dy = ax + ux * t - x, ay + uy * t - y
        local d2 = dx * dx + dy * dy
        if d2 < mejor then
            -- Posición en muestras: de `a` a `b` según `t`.
            local p = a + (b - a) * t
            mejor, mi, mf = d2, math.floor(p), p - math.floor(p)
        end
    end
    if mi >= n then
        mi, mf = n - 1, 1
    end
    return math.sqrt(mejor), mi, mf
end

local function enMuestra(campo, i, f)
    return campo[i] + (campo[i + 1] - campo[i]) * f
end

--- Paso de la malla del terreno en (x, y): el perfil del cauce se ensancha
-- donde la rejilla es gruesa para que se vea entero.
function Cauces:pasoEn(x, y)
    local s = self.suelo
    local medio = s.lado / 2
    local d = math.max(math.abs(x - s.cx), math.abs(y - s.cy))
    if d > medio then
        return 320
    end
    local Suelo = getmetatable(s)
    return Suelo.pasoA(d)
end

--- Medio ancho (px) del cauce mojado y del lecho en (i, f) con la malla de `paso`.
function Cauces:perfilRio(i, f, paso)
    local ancho = enMuestra(self.eje.ancho, i, f)
    local a = math.max(0.3 * ancho, paso * 0.75)
    local b = math.max(0.5 * ancho + 8, paso * 1.5)
    -- Donde el perfil cruza el nivel del agua (de -12 a +3 entre a y b).
    local orilla = a + (b - a) * Cauces.hondo / (Cauces.hondo + 3)
    return a, b, orilla
end

--- ¿Cae (x, y) en el cauce (el agua o el cañón) con `margen` px más?
function Cauces:enCauce(x, y, margen)
    if not self.hay then
        return false
    end
    local d, i, f = self:cercano(x, y)
    if d == math.huge then
        return false
    end
    local medio
    if self.canon then
        medio = enMuestra(self.eje.fondo, i, f) + enMuestra(self.eje.pared, i, f)
    else
        local _, _, orilla = self:perfilRio(i, f, Pasillos.celda)
        medio = orilla
    end
    return d < medio + (margen or 0)
end

-- Tallado ---------------------------------------------------------------------------------------

--- Altura tallada en (x, y) a partir de `h`. `wPasillo` (0 a 1) convierte el
-- cauce en vado o rampa; `pesoExplanada` lo apaga. Devuelve la altura, la
-- distancia al eje, el nivel del agua (o nil) y el medio ancho del agua.
function Cauces:tallarPunto(x, y, h, wPasillo, pesoExplanada, paso)
    local d, i, f = self:cercano(x, y)
    if d >= Cauces.alcance then
        return h
    end
    local s = self.suelo
    local e = self.eje
    local objetivo = math.huge
    local fondoRampa, anchoRampa
    local nivel, orilla
    if self.canon then
        local hondo = enMuestra(e.hondo, i, f)
        local fondo = enMuestra(e.fondo, i, f)
        local pared = enMuestra(e.pared, i, f)
        local borde = enMuestra(e.borde, i, f)
        local suelo = borde - hondo
        local t = (d - fondo) / pared
        if t <= 0 then
            objetivo = suelo
        elseif t < 1 then
            -- Escalones: cada uno sube de golpe en su primera mitad y deja un
            -- rellano en la segunda (estratos).
            local u = t * Cauces.escalones
            local k = math.floor(u)
            local subida = (k + suave(0, 0.55, u - k)) / Cauces.escalones
            objetivo = suelo + hondo * subida
        else
            objetivo = borde + (d - fondo - pared) * Cauces.taludBorde
        end
        fondoRampa, anchoRampa = suelo, fondo
        -- En lo llano (poco hondo) la garganta se apaga.
        local pesoCanon = suave(20, Cauces.hondoCanonUtil, hondo)
        objetivo = h + (math.min(h, objetivo) - h) * pesoCanon
    end
    if self.rio then
        nivel = enMuestra(e.nivel, i, f)
        local a, b
        a, b, orilla = self:perfilRio(i, f, paso)
        local perfil
        if d < a then
            perfil = -Cauces.hondo
        elseif d < b then
            perfil = -Cauces.hondo + (d - a) / (b - a) * (Cauces.hondo + 3)
        else
            perfil = 3 + (d - b) * Cauces.taludOrilla
        end
        if not self.canon then
            -- Valle suave alrededor del río.
            local ancho = enMuestra(e.ancho, i, f)
            h = h - Cauces.valle * (ancho / Cauces.anchoMax) * suave(Cauces.radioValle, 60, d) * (1 - wPasillo)
        end
        objetivo = math.min(objetivo, nivel + perfil)
        fondoRampa = math.max(nivel - Cauces.vadoHondo, s.nivelMar + 9)
        anchoRampa = orilla
    end
    if wPasillo > 0 then
        local rampa = fondoRampa + math.max(0, d - anchoRampa) * Cauces.rampa
        objetivo = objetivo + (rampa - objetivo) * wPasillo
    end
    -- Se funde con el terreno al acercarse al alcance.
    local fuera = suave(Cauces.alcance * 0.8, Cauces.alcance, d)
    local nuevo = math.min(h, objetivo)
    nuevo = nuevo + (h - nuevo) * fuera
    h = h + (nuevo - h) * (1 - pesoExplanada)
    return h, d, nivel, orilla
end

--- Talla la rejilla del terreno (después de los pasillos) y deja por vértice
-- `dAgua` (m a la orilla) y `nivelAgua` (px) para el color y las plantas.
function Cauces:tallar()
    if not self.hay then
        return
    end
    local s = self.suelo
    local rej = s.relieve
    local lado = rej.lado
    local px, py, ph = rej.x, rej.y, rej.h
    local dPasillo = rej.dPasillo
    local dAgua, nivelAgua = rej.dAgua, rej.nivelAgua
    local mitad, transicion = Pasillos.mitad, Pasillos.transicion
    local Suelo = getmetatable(s)
    local pasoX = {}
    for i = 0, lado - 1 do
        pasoX[i] = Suelo.pasoA(math.abs(rej.xs[i + 1] - s.cx))
    end
    local tallados = 0
    for j = 0, lado - 1 do
        local pasoY = Suelo.pasoA(math.abs(rej.ys[j + 1] - s.cy))
        for i = 0, lado - 1 do
            local k = j * lado + i
            local x, y = px[k], py[k]
            local w = 0
            if dPasillo then
                w = 1 - suave(mitad, mitad + transicion, dPasillo[k])
            end
            local paso = math.max(pasoX[i], pasoY)
            local h, d, nivel, orilla = self:tallarPunto(x, y, ph[k], w, s:pesoExplanada(x, y), paso)
            if d and d < Cauces.alcance then
                tallados = tallados + 1
                ph[k] = h
                if nivel and d < orilla + 450 then
                    -- Fuera del agua, un hoyo bajo el nivel no se llena.
                    if d < orilla + 50 or h >= nivel then
                        nivelAgua[k] = nivel
                        dAgua[k] = math.max(0, d - orilla) / 10
                    end
                end
            end
        end
    end
    self.tallados = tallados
    -- Vados o rampas: tramos del eje dentro de un pasillo.
    local vados, dentro = 0, false
    for q = 1, #self.eje.x do
        local x, y = self.eje.x[q], self.eje.y[q]
        local cruza = s.limite:dentro(x, y) and Pasillos.distancia(s, x, y) < mitad
        if cruza and not dentro then
            vados = vados + 1
        end
        dentro = cruza
    end
    self.vados = vados
end

--- Altura del faldón tallada (fuera del área): sin pasillos ni explanadas.
function Cauces:alturaFaldon(x, y, h)
    if not self.hay then
        return h
    end
    return (self:tallarPunto(x, y, h, 0, 0, 320))
end

--- Nivel del agua del río en (x, y) si cae sobre su cauce, o nil.
function Cauces:nivelEn(x, y)
    if not self.rio then
        return nil
    end
    local d, i, f = self:cercano(x, y)
    if d == math.huge then
        return nil
    end
    local _, _, orilla = self:perfilRio(i, f, self:pasoEn(x, y))
    if d > orilla then
        return nil
    end
    return enMuestra(self.eje.nivel, i, f)
end

-- Agua ------------------------------------------------------------------------------------------

--- Cinta del agua a lo largo del eje, en `malla` (la del mar): cinco filas a
-- lo ancho, más clara en la orilla (poco fondo), al nivel del agua. Acaba
-- donde entra en el mar y en `radioAgua`.
function Cauces:agregarAgua(malla)
    if not self.rio then
        return 0
    end
    local s = self.suelo
    local e = self.eje
    local n = #e.x
    local agua = Terreno.colores.agua
    local filas = { -1, -0.5, 0, 0.5, 1 }
    local tonos = { 1.12, 1.02, 0.94, 1.02, 1.12 }
    local azar = Ruido.azar(Ruido.hash(s.terreno.semilla, math.floor(s.cx), math.floor(s.cy), 69))
    local paso = 2 -- muestras entre secciones (4 m)
    local anterior
    local triangulos = 0
    for i = 1, n, paso do
        local a, b = math.max(1, i - 1), math.min(n, i + 1)
        local tx, ty = e.x[b] - e.x[a], e.y[b] - e.y[a]
        local l = math.max(1e-6, math.sqrt(tx * tx + ty * ty))
        local nx, ny = -ty / l, tx / l
        local x, y = e.x[i], e.y[i]
        local radio = math.sqrt((x - s.cx) ^ 2 + (y - s.cy) ^ 2)
        -- Con mar en el área, su plano ya cubre el cauce que baja de su nivel.
        local tope = s.hayMar and (s.nivelMar + Cauces.hondo) or s.nivelMar
        local valida = radio < Cauces.radioAgua and e.nivel[i] > tope
        local seccion
        if valida then
            local _, _, orilla = self:perfilRio(math.min(i, n - 1), 0, self:pasoEn(x, y))
            local medio = orilla + 6
            local tono = azar(0.97, 1.03)
            seccion = {}
            for q, f in ipairs(filas) do
                local temblor = (q > 1 and q < #filas) and azar(-0.3, 0.3) or 0
                seccion[q] = {
                    x + nx * f * medio,
                    y + ny * f * medio,
                    e.nivel[i] + temblor,
                    tonos[q] * tono,
                }
            end
        end
        if seccion and anterior then
            for q = 1, #filas - 1 do
                local p1, p2 = anterior[q], anterior[q + 1]
                local p3, p4 = seccion[q], seccion[q + 1]
                local t1 = (p1[4] + p2[4] + p3[4]) / 3
                local t2 = (p2[4] + p4[4] + p3[4]) / 3
                malla:triangulo(
                    p1[1],
                    p1[2],
                    p1[3],
                    p2[1],
                    p2[2],
                    p2[3],
                    p3[1],
                    p3[2],
                    p3[3],
                    { agua[1] * t1, agua[2] * t1, agua[3] * t1 }
                )
                malla:triangulo(
                    p2[1],
                    p2[2],
                    p2[3],
                    p4[1],
                    p4[2],
                    p4[3],
                    p3[1],
                    p3[2],
                    p3[3],
                    { agua[1] * t2, agua[2] * t2, agua[3] * t2 }
                )
                triangulos = triangulos + 2
            end
        end
        anterior = seccion
    end
    self.triangulosAgua = triangulos
    return triangulos
end

--- Línea `CAUCE` para las pruebas y el registro.
function Cauces:resumen()
    if not self.hay then
        return string.format('CAUCE %s', self.tipo)
    end
    local e = self.eje
    local s = self.suelo
    local dentro = 0
    for i = 1, #e.x do
        if s.limite:dentro(e.x[i], e.y[i]) then
            dentro = dentro + 1
        end
    end
    return string.format(
        'CAUCE %s: %.0f m de eje (%.0f m dentro del límite), nivel %.0f a %.0f px, %d vértices tallados, %d triángulos de agua, %d vados',
        self.tipo,
        e.s[#e.s] / 10,
        dentro * Cauces.muestra / 10,
        e.nivel[1],
        e.nivel[#e.nivel],
        self.tallados or 0,
        self.triangulosAgua or 0,
        self.vados or 0
    )
end

return Cauces

-- Mapa que aprende el robot (rejilla de ocupación, como los robots de
-- almacén reales con su lidar): empieza sin saber nada y cada rayo del
-- lidar marca como libre lo que atraviesa y como ocupada la casilla donde
-- choca, con lo que es (rack, mesa, muro...). Cada casilla guarda una
-- certeza (log-odds): un rayo suelto no la cambia del todo, varios sí; si
-- algo se quita, los rayos que ahora pasan la vuelven a dejar libre.
--
-- Para planear rutas (A*) se usa otra rejilla más gruesa en la que cada
-- obstáculo se engorda con el radio del robot (así la ruta es para su
-- centro). Lo que aún no ha visto cuenta como libre: si al acercarse ve
-- algo, la ruta se vuelve a calcular.

local ffi = require('ffi')

local Mapa = {}
Mapa.__index = Mapa

Mapa.resolucion = 0.1 -- m por casilla
Mapa.resolucionRuta = 0.2
Mapa.libre = -0.4 -- lo que resta un rayo que pasa
Mapa.ocupado = 0.85 -- lo que suma un rayo que choca
Mapa.minimo, Mapa.maximo = -2.0, 3.5
Mapa.umbral = 0.6 -- por encima: ocupada
Mapa.radioRobot = 0.42 -- engorde de los obstáculos para planear
-- Margen de cortesía: pasar a menos de esto de algo cuesta más (la ruta va
-- por el centro de los pasillos, sin rozar los lados de las cosas).
Mapa.radioCerca = 1.0
Mapa.penalizacionCerca = 3.0

--- Mapa vacío de x0..x1, y0..y1 (metros del almacén).
function Mapa.nuevo(x0, y0, x1, y1)
    local self = setmetatable({}, Mapa)
    self.x0, self.y0 = x0, y0
    self.ancho = math.ceil((x1 - x0) / Mapa.resolucion)
    self.alto = math.ceil((y1 - y0) / Mapa.resolucion)
    self.celdas = ffi.new('float[?]', self.ancho * self.alto)
    self.visto = ffi.new('uint8_t[?]', self.ancho * self.alto)
    self.tipos = {} -- [indice] = 'rack'...
    -- Rejilla de rutas: cuántas casillas ocupadas engordadas la tocan.
    self.factor = math.floor(Mapa.resolucionRuta / Mapa.resolucion + 0.5)
    self.anchoRuta = math.ceil(self.ancho / self.factor)
    self.altoRuta = math.ceil(self.alto / self.factor)
    self.bloqueo = ffi.new('int16_t[?]', self.anchoRuta * self.altoRuta)
    self.cerca = ffi.new('int16_t[?]', self.anchoRuta * self.altoRuta)
    -- Desplazamientos del disco del engorde (en casillas de ruta).
    self.disco = {}
    local r = math.ceil(Mapa.radioRobot / Mapa.resolucionRuta)
    for dy = -r, r do
        for dx = -r, r do
            if (dx * dx + dy * dy) * Mapa.resolucionRuta ^ 2 <= Mapa.radioRobot ^ 2 then
                self.disco[#self.disco + 1] = { dx, dy }
            end
        end
    end
    self.discoCerca = {}
    r = math.ceil(Mapa.radioCerca / Mapa.resolucionRuta)
    for dy = -r, r do
        for dx = -r, r do
            if (dx * dx + dy * dy) * Mapa.resolucionRuta ^ 2 <= Mapa.radioCerca ^ 2 then
                self.discoCerca[#self.discoCerca + 1] = { dx, dy }
            end
        end
    end
    self.cambios = 0 -- sube cada vez que una casilla pasa de libre a ocupada o al revés
    self.ultimosCambios = {} -- casillas que cambiaron (para el dibujo)
    return self
end

function Mapa:casilla(x, y)
    return math.floor((x - self.x0) / Mapa.resolucion), math.floor((y - self.y0) / Mapa.resolucion)
end

function Mapa:dentro(cx, cy)
    return cx >= 0 and cy >= 0 and cx < self.ancho and cy < self.alto
end

--- `true` si la casilla de (x, y) está ocupada.
function Mapa:getOcupado(x, y)
    local cx, cy = self:casilla(x, y)
    if not self:dentro(cx, cy) then
        return true
    end
    return self.celdas[cy * self.ancho + cx] > Mapa.umbral
end

--- Qué hay en (x, y) según lo visto ('rack', 'mesaRecepcion'...) o nil.
function Mapa:getTipo(x, y)
    local cx, cy = self:casilla(x, y)
    if not self:dentro(cx, cy) then
        return nil
    end
    local i = cy * self.ancho + cx
    return self.celdas[i] > Mapa.umbral and self.tipos[i] or nil
end

--- Cuántas casillas ha visto (para saber cuánto conoce).
function Mapa:getVistas()
    local n = 0
    for i = 0, self.ancho * self.alto - 1 do
        if self.visto[i] ~= 0 then
            n = n + 1
        end
    end
    return n
end

-- La casilla i pasa a ocupada (s = 1) o a libre (s = -1): engorda o
-- desengorda en la rejilla de rutas.
function Mapa:marcarBloqueo(cx, cy, s)
    local rx, ry = math.floor(cx / self.factor), math.floor(cy / self.factor)
    for _, d in ipairs(self.disco) do
        local x, y = rx + d[1], ry + d[2]
        if x >= 0 and y >= 0 and x < self.anchoRuta and y < self.altoRuta then
            local j = y * self.anchoRuta + x
            self.bloqueo[j] = self.bloqueo[j] + s
        end
    end
    for _, d in ipairs(self.discoCerca) do
        local x, y = rx + d[1], ry + d[2]
        if x >= 0 and y >= 0 and x < self.anchoRuta and y < self.altoRuta then
            local j = y * self.anchoRuta + x
            self.cerca[j] = self.cerca[j] + s
        end
    end
    self.cambios = self.cambios + 1
    self.ultimosCambios[#self.ultimosCambios + 1] = cy * self.ancho + cx
end

function Mapa:sumar(cx, cy, valor, tipo)
    local i = cy * self.ancho + cx
    -- Lo que ha tocado con el cuerpo (setChoque) no lo borra un rayo que
    -- pase sin verlo (una pata fina que el lidar no ve entre rayo y rayo).
    if valor < 0 and self.tocadas and self.tocadas[i] then
        return
    end
    local antes = self.celdas[i]
    local v = math.max(Mapa.minimo, math.min(Mapa.maximo, antes + valor))
    self.celdas[i] = v
    if self.visto[i] == 0 then
        self.visto[i] = 1
        self.ultimosCambios[#self.ultimosCambios + 1] = i
    end
    if tipo then
        self.tipos[i] = tipo
    end
    local estabaOcupada, estaOcupada = antes > Mapa.umbral, v > Mapa.umbral
    if estaOcupada ~= estabaOcupada then
        self:marcarBloqueo(cx, cy, estaOcupada and 1 or -1)
    end
end

--- El cuerpo ha chocado con algo que ocupa la caja (x0, y0)-(x1, y1): sus
-- casillas pasan a ocupadas para siempre (como el parachoques de un robot
-- real). Solo las que quedan a menos de `cerca` m de (x, y).
function Mapa:setChoque(x0, y0, x1, y1, x, y, cerca, tipo)
    self.tocadas = self.tocadas or {}
    x0, y0 = math.max(x0, x - cerca), math.max(y0, y - cerca)
    x1, y1 = math.min(x1, x + cerca), math.min(y1, y + cerca)
    local ax, ay = self:casilla(x0, y0)
    local bx, by = self:casilla(x1, y1)
    for cy = ay, by do
        for cx = ax, bx do
            if self:dentro(cx, cy) then
                local i = cy * self.ancho + cx
                if not self.tocadas[i] then
                    self.tocadas[i] = true
                    self:sumar(cx, cy, Mapa.maximo, tipo)
                end
            end
        end
    end
end

--- Un rayo del lidar: de (x, y) hacia `angulo`, `distancia` m; `choca` si
-- acabó en algo (de tipo `tipo`).
function Mapa:setRayo(x, y, angulo, distancia, choca, tipo)
    local cx, cy = self:casilla(x, y)
    local fx, fy = self:casilla(x + math.cos(angulo) * distancia, y + math.sin(angulo) * distancia)
    -- Bresenham de la casilla del robot a la del choque.
    local dx, dy = math.abs(fx - cx), -math.abs(fy - cy)
    local sx, sy = cx < fx and 1 or -1, cy < fy and 1 or -1
    local e = dx + dy
    while not (cx == fx and cy == fy) do
        if self:dentro(cx, cy) then
            self:sumar(cx, cy, Mapa.libre)
        end
        local e2 = 2 * e
        if e2 >= dy then
            e = e + dy
            cx = cx + sx
        end
        if e2 <= dx then
            e = e + dx
            cy = cy + sy
        end
    end
    if choca and self:dentro(fx, fy) then
        self:sumar(fx, fy, Mapa.ocupado, tipo)
    end
end

-- Rutas ---------------------------------------------------------------------------

function Mapa:casillaRuta(x, y)
    return math.floor((x - self.x0) / Mapa.resolucionRuta), math.floor((y - self.y0) / Mapa.resolucionRuta)
end

function Mapa:centroRuta(rx, ry)
    return self.x0 + (rx + 0.5) * Mapa.resolucionRuta, self.y0 + (ry + 0.5) * Mapa.resolucionRuta
end

function Mapa:bloqueadaRuta(rx, ry)
    if rx < 0 or ry < 0 or rx >= self.anchoRuta or ry >= self.altoRuta then
        return true
    end
    return self.bloqueo[ry * self.anchoRuta + rx] > 0
end

--- `true` si el centro del robot no puede estar en (x, y) (según lo visto).
function Mapa:getBloqueado(x, y)
    return self:bloqueadaRuta(self:casillaRuta(x, y))
end

-- La casilla libre más cercana a (rx, ry) en `radio` casillas.
function Mapa:libreCerca(rx, ry, radio)
    if not self:bloqueadaRuta(rx, ry) then
        return rx, ry
    end
    for r = 1, radio do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r and not self:bloqueadaRuta(rx + dx, ry + dy) then
                    return rx + dx, ry + dy
                end
            end
        end
    end
end

-- Montículo binario para el A*.
local function meter(m, nodo, f)
    m.n = m.n + 1
    local i = m.n
    m[i] = nodo
    m.f[i] = f
    while i > 1 do
        local p = math.floor(i / 2)
        if m.f[p] <= m.f[i] then
            break
        end
        m[p], m[i] = m[i], m[p]
        m.f[p], m.f[i] = m.f[i], m.f[p]
        i = p
    end
end

local function sacar(m)
    local nodo = m[1]
    m[1], m.f[1] = m[m.n], m.f[m.n]
    m[m.n], m.f[m.n] = nil, nil
    m.n = m.n - 1
    local i = 1
    while true do
        local a, b = 2 * i, 2 * i + 1
        local menor = i
        if a <= m.n and m.f[a] < m.f[menor] then
            menor = a
        end
        if b <= m.n and m.f[b] < m.f[menor] then
            menor = b
        end
        if menor == i then
            break
        end
        m[menor], m[i] = m[i], m[menor]
        m.f[menor], m.f[i] = m.f[i], m.f[menor]
        i = menor
    end
    return nodo
end

local VECINOS = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 1, 1, 1.4142 }, { 1, -1, 1.4142 }, { -1, 1, 1.4142 }, { -1, -1, 1.4142 } }

--- Ruta de (x0, y0) a (x1, y1) por lo que sabe del almacén: lista de
-- puntos { x, y } (sin el de salida), o nil si no hay camino.
function Mapa:getRuta(x0, y0, x1, y1)
    local W = self.anchoRuta
    local sx, sy = self:casillaRuta(x0, y0)
    local gx, gy = self:casillaRuta(x1, y1)
    -- Si sale de una casilla bloqueada (pegado a un mueble) o el destino lo
    -- está, se usa la libre más cercana.
    sx, sy = self:libreCerca(sx, sy, 6)
    gx, gy = self:libreCerca(gx, gy, 6)
    if not sx or not gx then
        return nil
    end
    local inicio, meta = sy * W + sx, gy * W + gx
    local coste = { [inicio] = 0 }
    local de = {}
    local cerrado = {}
    local abiertos = { n = 0, f = {} }
    local function h(i)
        local x, y = i % W, math.floor(i / W)
        local ax, ay = math.abs(x - gx), math.abs(y - gy)
        return math.max(ax, ay) + 0.4142 * math.min(ax, ay)
    end
    meter(abiertos, inicio, h(inicio))
    local pasos = 0
    while abiertos.n > 0 do
        local i = sacar(abiertos)
        if i == meta then
            break
        end
        if not cerrado[i] then
            cerrado[i] = true
            pasos = pasos + 1
            if pasos > 60000 then
                return nil
            end
            local x, y = i % W, math.floor(i / W)
            for _, v in ipairs(VECINOS) do
                local nx, ny = x + v[1], y + v[2]
                -- En diagonal, sin cortar esquinas.
                if not self:bloqueadaRuta(nx, ny) and (v[3] == 1 or (not self:bloqueadaRuta(x + v[1], y) and not self:bloqueadaRuta(x, y + v[2]))) then
                    local j = ny * W + nx
                    local c = coste[i] + v[3] * (self.cerca[j] > 0 and (1 + Mapa.penalizacionCerca) or 1)
                    if not coste[j] or c < coste[j] then
                        coste[j] = c
                        de[j] = i
                        meter(abiertos, j, c + h(j))
                    end
                end
            end
        end
    end
    if not coste[meta] then
        return nil
    end
    local celdas = {}
    local i = meta
    while i do
        table.insert(celdas, 1, i)
        i = de[i]
    end
    -- Quita los puntos que sobran (si se ve el siguiente sin obstáculos, el
    -- de en medio no hace falta).
    -- Casillas de cortesía acumuladas a lo largo de la ruta.
    local acumulado = { [0] = 0 }
    for k, c in ipairs(celdas) do
        acumulado[k] = acumulado[k - 1] + (self.cerca[c] > 0 and 1 or 0)
    end
    local puntos = {}
    local desde = 1
    while desde < #celdas do
        local hasta = desde + 1
        for k = #celdas, desde + 1, -1 do
            if self:libreEntre(celdas[desde], celdas[k], acumulado[k] - acumulado[desde] + 1) then
                hasta = k
                break
            end
        end
        local x, y = self:centroRuta(celdas[hasta] % W, math.floor(celdas[hasta] / W))
        puntos[#puntos + 1] = { x, y }
        desde = hasta
    end
    if #puntos > 0 then
        puntos[#puntos] = { x1, y1 }
    else
        puntos[1] = { x1, y1 }
    end
    return puntos
end

--- `true` si la recta entre dos casillas de ruta no pasa por ninguna bloqueada.
--- `true` si la recta entre dos casillas de ruta no pasa por ninguna
-- bloqueada (ni por más casillas de cortesía que `maximoCerca`).
function Mapa:libreEntre(a, b, maximoCerca)
    local W = self.anchoRuta
    local ax, ay, bx, by = a % W, math.floor(a / W), b % W, math.floor(b / W)
    local pasos = math.max(math.abs(bx - ax), math.abs(by - ay))
    local n = pasos * 2
    local cerca = 0
    for k = 0, n do
        local t = n > 0 and k / n or 0
        local x, y = math.floor(ax + (bx - ax) * t + 0.5), math.floor(ay + (by - ay) * t + 0.5)
        if self:bloqueadaRuta(x, y) then
            return false
        end
        if self.cerca[y * W + x] > 0 then
            cerca = cerca + 0.5
        end
    end
    return not maximoCerca or cerca <= maximoCerca
end

--- `true` si el tramo recto de (x0, y0) a (x1, y1) está libre según el mapa.
function Mapa:getTramoLibre(x0, y0, x1, y1)
    local d = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    local n = math.max(1, math.ceil(d / (Mapa.resolucionRuta * 0.5)))
    for k = 0, n do
        local t = k / n
        if self:getBloqueado(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t) then
            return false
        end
    end
    return true
end

return Mapa

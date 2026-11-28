-- Plano de un sitio de la batalla (ciudad o mina) armado con las piezas del
-- kit (tools/blender/kit_mina.py, assets/batalla/kit), a tamaño real.
--
-- El dueño, 19-nov: las ciudades y las minas se generan en la batalla con las
-- piezas del kit (las mismas con las que construirán los robots), «a escala
-- real, por lo que pueden ser bien grandes».
--
-- Cómo lo hace la industria y qué se toma de cada uno:
--   * Kit modular sobre rejilla fija (Bethesda, «Skyrim's Modular Approach to
--     Level Design», GDC 2013): todo en módulos de 4 m; las piezas encajan
--     por sus bordes (muro entre pilares, losa y techo por celda).
--   * Calles y manzanas (Parish y Müller, «Procedural Modeling of Cities»,
--     SIGGRAPH 2001): aquí trazado en cuadrícula, como una ciudad planificada,
--     con dos avenidas en cruz y calles entre manzanas.
--   * Parcelas por partición recursiva de la manzana (Vanegas et al.,
--     «Procedural Generation of Parcels in Urban Modeling», 2012) y un
--     edificio por parcela con su fachada a la calle.
--   * Mina: recinto amurallado con portón y una calle central, y las naves,
--     oficinas, cuartel y patios a los dos lados (la disposición de los
--     campamentos mineros reales: todo cerca de la vía de acarreo).
--
-- El terreno no se toca: cada edificio se apoya en la cota más alta de su
-- huella y un cimiento de hormigón baja hasta el suelo (como en ladera).
--
-- Resultado (todo en px de la batalla, 10 px = 1 m):
--   plano.piezas[nombre] = { { x, y, z, giro }, ... }
--   plano.grupos = { { x0, y0, x1, y1, z, piezas = { [nombre] = {...} }, tono }, ... }
--     (cada edificio y cada tramo del recinto: el nivel de detalle se elige
--     por grupo; `tono` es el color de su chapa)
--   plano.cimientos = { { x0, y0, x1, y1, zArriba, zAbajo }, ... }
--   plano.edificios = { { x0, y0, x1, y1, z, alto }, ... } (para el LOD lejano)
--   plano.calles = { { x0, y0, x1, y1 }, ... } (ejes, para pintar la tierra)
--   plano.recinto = { x0, y0, x1, y1 } y plano:dentro(x, y), plano:ocupado(x, y)

local Ruido = require('mundo.ruido')
local Llano = require('mundo.llano')

local Plano = {}
Plano.__index = Plano

Plano.modulo = 40 -- px (4 m), la rejilla del kit
Plano.piso = 43 -- px (4,3 m) de un piso: losa de 0,3 m + muro de 4 m
Plano.altoMuro = 40.6 -- px hasta lo alto del remate del muro
Plano.desnivelMaximo = 300 -- px (30 m) de desnivel en una huella antes de dejarla vacía
Plano.talud = 1.2 -- px de talud por px de desmonte o terraplén (unos 40°)
Plano.taludMinimo = 60 -- px
Plano.busqueda = 3000
-- Hasta dónde se puede abrir el límite de la batalla para que quepa el
-- recinto entero (px desde el centro del área; las plantas llegan a 13 950).
Plano.limiteMaximo = 13900 -- px alrededor del sitio donde buscar el sitio más llano
Plano.celda = 160 -- px de la rejilla de huellas (para `ocupado`)

-- Aeródromo (el dueño, 20-nov: «la pista estará dentro del recinto, ya que
-- llegarán, bajarán y después harán guardia»): el muro se alarga hacia el
-- norte (el lado sin portón de la mina) con una franja de `fondo` módulos y,
-- como poco, `medioMuro` módulos a cada lado del centro; dentro, la pista
-- del avión de carga (batalla/dream/pista_avion.lua) de este a oeste, con su
-- eje a `ejeDesdeMuro` px del muro viejo. Como las bases avanzadas donde
-- operan los aviones de carga militares: pista, plataforma y todo dentro del
-- perímetro.
Plano.aerodromo = {
    -- 26-nov: de 30 a 72 módulos (288 m) para la plataforma de aparcamiento
    -- de los aviones al norte de la pista (el dueño: «que no se pongan uno
    -- encima del otro en la pista»).
    fondo = 72, -- módulos (288 m)
    medioMuro = 100, -- módulos (400 m)
    ejeDesdeMuro = 750, -- px (75 m)
    medioLargo = 370, -- m de pista a cada lado del centro
    pendiente = 0.015, -- como mucho (las pistas reales, 1-2 %)
    medioAncho = 260, -- px de explanada a cada lado del eje (pista, arcén y margen)
    talud = 250, -- px de talud de la explanada (como poco)
    -- Y más ancho cuanto más hondo el corte o el relleno: 2,5 de ancho por
    -- 1 de alto (con la curva suave, unos 30° en lo más empinado), como los
    -- desmontes de una carretera; nunca un paredón (el dueño, 20-nov).
    taludRelacion = 2.5,
    -- Plataforma (m desde el eje de la pista, hacia el norte): la calle de
    -- rodaje paralela a la pista y una fila de plazas donde los aviones
    -- aparcan de morro al norte, separadas lo que mide el ala (72 m) y 18 m
    -- más (batalla/dream/plataforma_avion.lua, trafico_aereo.lua).
    plataforma = {
        desde = 24, -- borde sur (pasado el arcén de la pista)
        hasta = 205, -- borde norte
        calle = 85, -- eje de la calle de rodaje
        plaza = 165, -- centro de los aviones aparcados (cola a 132 m)
        plazas = 8,
        separacion = 90, -- m entre plazas
        espera = -300, -- a lo largo: dónde esperan en la calle para entrar en la pista
        entrada = -345, -- a lo largo: por dónde entran en la pista (cabecera oeste)
    },
}

local M = Plano.modulo
local PI = math.pi

-- Tamaños (en módulos de 4 m) de cada clase de sitio.
Plano.ciudades = {
    -- Capital: unos 900 m de lado; ciudad: unos 600 m.
    capital = { medio = 112, pisosCentro = { 3, 6 }, calles = 160 },
    ciudad = { medio = 75, pisosCentro = { 2, 4 }, calles = 90 },
}

-- Edificios de cada mina (ancho y fondo en módulos, pisos, ventanas, nave
-- diáfana = sin forjado intermedio, patio = solo losa).
Plano.minas = {
    oro = {
        medioX = 30,
        medioY = 22,
        edificios = {
            { 'planta', 14, 8, 2, ventanas = 0.1, nave = true, puertas = 2 },
            { 'oficinas', 6, 4, 2, ventanas = 0.85 },
            { 'cuartel', 8, 4, 2, ventanas = 0.7 },
            { 'almacen', 8, 6, 1, ventanas = 0.1, puertas = 2 },
            { 'patio', 10, 7, 0, patio = true },
            { 'taller', 6, 5, 1, ventanas = 0.3, puertas = 2 },
            { 'almacen', 6, 6, 1, ventanas = 0.1 },
            { 'patio', 8, 6, 0, patio = true },
        },
    },
    metal = {
        medioX = 40,
        medioY = 30,
        edificios = {
            { 'nave', 16, 10, 2, ventanas = 0.05, nave = true, puertas = 3 },
            { 'oficinas', 8, 4, 3, ventanas = 0.85 },
            { 'nave', 16, 10, 2, ventanas = 0.05, nave = true, puertas = 3 },
            { 'cuartel', 10, 4, 2, ventanas = 0.7 },
            { 'patio', 14, 10, 0, patio = true },
            { 'taller', 8, 6, 1, ventanas = 0.3, puertas = 2 },
            { 'almacen', 10, 6, 1, ventanas = 0.1, puertas = 2 },
            { 'patio', 12, 8, 0, patio = true },
            { 'almacen', 8, 6, 1, ventanas = 0.1 },
        },
    },
}
Plano.minas.petroleo = Plano.minas.oro
Plano.minas.comida = Plano.minas.oro

--- Centro más llano para un recinto de medio lado (mx, my) px, a menos de
-- `Plano.busqueda` del sitio y dentro del área de la batalla (las
-- instalaciones de una mina se ponen en lo llano junto al yacimiento).
-- `norte`: px de más al norte (el aeródromo); el recinto va de -mx a mx y
-- de -my - norte a my alrededor del centro.
local function buscarLlano(suelo, x, y, mx, my, norte, huella)
    norte = norte or 0
    -- El mapa ya puso el sitio en lo llano (mundo/llano.lua, el mismo
    -- criterio en el 2D y el 3D): se queda ahí, donde está en el mapa.
    local t = suelo.terreno
    local u, v = x, y
    if t.aMapa then
        u, v = t:aMapa(x, y)
    end
    if huella and t.mapa and Llano.apto(t.mapa, u, v, huella) then
        return x, y
    end
    -- Si el sitio cae tan al borde que no cabe, se acerca al centro lo justo.
    local dx, dy = x - suelo.cx, y - suelo.cy
    local d = math.sqrt(dx * dx + dy * dy)
    local maximo = Plano.limiteMaximo - 300 - math.sqrt(mx * mx + my * my) - Plano.busqueda * 0.5
    if d > maximo and d > 0 then
        x, y = suelo.cx + dx / d * maximo, suelo.cy + dy / d * maximo
    end
    local mejor, mx0, my0 = math.huge, x, y
    local medio = suelo.lado / 2 - 200
    for r = 0, Plano.busqueda, 250 do
        local n = math.max(1, math.floor(2 * math.pi * r / 250))
        for k = 0, n - 1 do
            local a = k / n * 2 * math.pi
            local cx, cy = x + math.cos(a) * r, y + math.sin(a) * r
            -- El recinto entero (sus esquinas) dentro del límite de la batalla
            -- que se le puede dar sin salir de donde hay plantas.
            local esquina = math.sqrt((cx - suelo.cx) ^ 2 + (cy - suelo.cy) ^ 2) + math.sqrt(mx * mx + (my + norte) ^ 2)
            if esquina + 300 < Plano.limiteMaximo and math.abs(cx - suelo.cx) + mx < medio and math.abs(cy - suelo.cy) + my + norte < medio then
                local lo, hi = math.huge, -math.huge
                for j = -3, 3 do
                    for i = -3, 3 do
                        local h = suelo:altura(cx + i / 3 * mx, cy - norte / 2 + j / 3 * (my + norte / 2))
                        lo, hi = math.min(lo, h), math.max(hi, h)
                    end
                end
                -- Un poco de castigo por alejarse del sitio.
                local nota = hi - lo + r * 0.01
                if nota < mejor then
                    mejor, mx0, my0 = nota, cx, cy
                end
            end
        end
    end
    return mx0, my0
end

function Plano.nuevo(suelo, sitio)
    local self = setmetatable({}, Plano)
    self.suelo = suelo
    self.sitio = sitio
    self.piezas = {}
    self.cimientos = {}
    self.edificios = {}
    self.calles = {}
    self.huellas = {}
    self.grupos = {}
    self.cantidad = 0
    -- Rejilla de módulos centrada en lo más llano junto al sitio (alineada a 4 m).
    local mx, my
    if sitio.tipo == 'ciudad' then
        local t = sitio.capital and Plano.ciudades.capital or Plano.ciudades.ciudad
        mx, my = t.medio * M, t.medio * M
    else
        local t = Plano.minas[sitio.deposito or 'oro'] or Plano.minas.oro
        mx, my = t.medioX * M, t.medioY * M
    end
    -- Con el aeródromo al norte: el recinto entero, más ancho y más hondo.
    local A = Plano.aerodromo
    local huella = sitio.tipo == 'ciudad' and Llano.huellaCiudad or Llano.huellaMina
    local x, y = buscarLlano(suelo, sitio.x, sitio.y, math.max(mx, A.medioMuro * M), my, A.fondo * M, huella)
    -- El sitio sale igual en cualquier batalla y en su maqueta del mapa
    -- (mundo/maquetas.lua): la rejilla, alineada desde el sitio (no desde
    -- el origen de la batalla, que cambia con el lado del ataque), y el
    -- azar, de su punto del mapa.
    self.ox = sitio.x + math.floor((x - sitio.x) / M + 0.5) * M
    self.oy = sitio.y + math.floor((y - sitio.y) / M + 0.5) * M
    self:usarMarco(self.ox, self.oy, 0)
    local semilla = suelo.terreno.semilla or 1
    local sx, sy = sitio.mapaX or sitio.x, sitio.mapaY or sitio.y
    self.U = Ruido.generador(Ruido.hash(semilla, math.floor(sx), math.floor(sy), 9311))
    return self
end

--- Rectángulo del recinto (el muro, con el aeródromo al norte) alrededor del
-- punto del sitio, en m: x0, y0, x1, y1 (el norte es y menos). Es el del
-- sitio cuando cabe en su punto del mapa (lo llano: mundo/llano.lua). El
-- mapa 2D no planta árboles dentro (mundo/generador.lua).
function Plano.recintoRelativo(tipo, capital, deposito)
    local A = Plano.aerodromo
    local mx, my
    if tipo == 'ciudad' then
        local t = capital and Plano.ciudades.capital or Plano.ciudades.ciudad
        mx, my = t.medio, t.medio
    else
        local t = Plano.minas[deposito or 'oro'] or Plano.minas.oro
        mx, my = t.medioX, t.medioY
    end
    local W = math.max(mx, A.medioMuro)
    local m = M / 10 -- m por módulo
    return -W * m, -(my + A.fondo) * m, W * m, my * m
end

--- Genera el plano del sitio (`sitio.tipo` 'ciudad' o 'mina', con
-- `sitio.capital` y `sitio.deposito`). Nil si no es ninguno de los dos.
function Plano.generar(suelo, sitio)
    if not sitio then
        return nil
    end
    local self = Plano.nuevo(suelo, sitio)
    if sitio.tipo == 'ciudad' then
        self:ciudad(sitio.capital and Plano.ciudades.capital or Plano.ciudades.ciudad)
    elseif sitio.tipo == 'mina' then
        self:mina(Plano.minas[sitio.deposito or 'oro'] or Plano.minas.oro)
    else
        return nil
    end
    local n = 0
    for _ in pairs(self.edificios) do
        n = n + 1
    end
    print(string.format('PLANO %s %s en %.0f,%.0f: %d piezas, %d edificios', sitio.tipo, tostring(sitio.deposito or (sitio.capital and 'capital' or '')), self.ox, self.oy, self.cantidad, n))
    if self.recinto and self.pista then
        local r = self.recinto
        print(string.format('AERODROMO recinto %.0f,%.0f a %.0f,%.0f px (%.0f x %.0f m); pista en %.0f,%.0f', r[1], r[2], r[3], r[4], (r[3] - r[1]) / 10, (r[4] - r[2]) / 10, self.pista.x, self.pista.y))
    end
    return self
end

-- Utilidades -----------------------------------------------------------------------------

function Plano:poner(nombre, x, y, z, giro)
    local lista = self.piezas[nombre]
    if not lista then
        lista = {}
        self.piezas[nombre] = lista
    end
    local p = { x, y, z, giro or 0 }
    lista[#lista + 1] = p
    self.cantidad = self.cantidad + 1
    local g = self.grupo
    if g then
        local l = g.piezas[nombre]
        if not l then
            l = {}
            g.piezas[nombre] = l
        end
        l[#l + 1] = p
    end
end

-- Colores de chapa de los edificios (índices de KitSitio.tonosChapa).
Plano.tonos = 5

--- Abre un grupo (edificio o tramo de muro) en el rectángulo dado: las piezas
-- que se pongan hasta `cerrarGrupo` van a él.
function Plano:abrirGrupo(x0, y0, x1, y1, z, tono)
    self.grupo = { x0, y0, x1, y1, z, piezas = {}, tono = tono }
    self.grupos[#self.grupos + 1] = self.grupo
end

function Plano:cerrarGrupo()
    self.grupo = nil
end

--- Marco de la rejilla de módulos: origen (px) y giro. Por defecto, el
-- centro del sitio sin girar; cada edificio de ciudad pone el suyo,
-- alineado con su calle.
function Plano:usarMarco(ox, oy, ang)
    self.mox, self.moy, self.mang = ox, oy, ang or 0
    self.mc, self.ms = math.cos(self.mang), math.sin(self.mang)
end

--- x, y (px) del nodo (i, j) de la rejilla de módulos (en el marco).
function Plano:nodo(i, j)
    local u, v = i * M, j * M
    return self.mox + u * self.mc - v * self.ms, self.moy + u * self.ms + v * self.mc
end

--- Alturas mínima y máxima del suelo en un rectángulo (px), cada módulo.
function Plano:alturas(x0, y0, x1, y1)
    local s = self.suelo
    local lo, hi = math.huge, -math.huge
    local nx = math.max(1, math.floor((x1 - x0) / M + 0.5))
    local ny = math.max(1, math.floor((y1 - y0) / M + 0.5))
    for j = 0, ny do
        for i = 0, nx do
            local h = s:altura(x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny)
            lo = math.min(lo, h)
            hi = math.max(hi, h)
        end
    end
    return lo, hi
end

--- Alturas mínima y máxima del suelo en los nodos (i0..i1, j0..j1) del marco.
function Plano:alturasMarco(i0, j0, i1, j1)
    local s = self.suelo
    local lo, hi = math.huge, -math.huge
    for j = j0, j1 do
        for i = i0, i1 do
            local h = s:altura(self:nodo(i, j))
            lo = math.min(lo, h)
            hi = math.max(hi, h)
        end
    end
    return lo, hi
end

--- Huella (lo que estorba) de una caja girada: centro, medios lados, giro.
function Plano:huellaGirada(cx, cy, hx, hy, ang)
    local c, s = math.cos(ang), math.sin(ang)
    local h = { cx = cx, cy = cy, hx = hx, hy = hy, c = c, s = s, ang = ang }
    local r = math.abs(hx * c) + math.abs(hy * s)
    local q = math.abs(hx * s) + math.abs(hy * c)
    h[1], h[2], h[3], h[4] = cx - r, cy - q, cx + r, cy + q
    self:apuntarHuella(h)
    return h
end

function Plano:huella(x0, y0, x1, y1)
    return self:huellaGirada((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0)
end

function Plano:apuntarHuella(h)
    self.listaHuellas = self.listaHuellas or {}
    self.listaHuellas[#self.listaHuellas + 1] = h
    local c = Plano.celda
    local x0, y0, x1, y1 = h[1], h[2], h[3], h[4]
    for j = math.floor(y0 / c), math.floor(y1 / c) do
        for i = math.floor(x0 / c), math.floor(x1 / c) do
            local k = i * 131072 + j
            local lista = self.huellas[k]
            if not lista then
                lista = {}
                self.huellas[k] = lista
            end
            lista[#lista + 1] = h
        end
    end
end

--- ¿Cae (x, y) sobre un edificio, un patio o el muro del recinto? `margen` en px.
function Plano:ocupado(x, y, margen)
    margen = margen or 0
    local c = Plano.celda
    for j = math.floor((y - margen) / c), math.floor((y + margen) / c) do
        for i = math.floor((x - margen) / c), math.floor((x + margen) / c) do
            local lista = self.huellas[i * 131072 + j]
            if lista then
                for _, h in ipairs(lista) do
                    local dx, dy = x - h.cx, y - h.cy
                    local u, v = dx * h.c + dy * h.s, -dx * h.s + dy * h.c
                    if math.abs(u) < h.hx + margen and math.abs(v) < h.hy + margen then
                        return true, h
                    end
                end
            end
        end
    end
    return false
end

--- Sólidos (edificios y muro, cajas giradas con z0 y z1 px) cuyo
-- rectángulo toca el círculo (x, y, radio) px. `salida` se vacía y se llena.
function Plano:solidosCerca(x, y, radio, salida)
    salida = salida or {}
    for k = #salida, 1, -1 do
        salida[k] = nil
    end
    local c = Plano.celda
    local vistos = {}
    for j = math.floor((y - radio) / c), math.floor((y + radio) / c) do
        for i = math.floor((x - radio) / c), math.floor((x + radio) / c) do
            for _, h in ipairs(self.huellas[i * 131072 + j] or {}) do
                if h.solido and not vistos[h] and x > h[1] - radio and x < h[3] + radio and y > h[2] - radio and y < h[4] + radio then
                    vistos[h] = true
                    salida[#salida + 1] = h
                end
            end
        end
    end
    return salida
end

--- Primer choque del segmento (px) con un edificio o el muro: t (0..1) y
-- el sólido, o nil. Cajas giradas de z0 a z1 (método de las losas).
local tocados = {}
function Plano:rayo(x0, y0, z0, x1, y1, z1)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local largo = math.sqrt(dx * dx + dy * dy)
    local tramos = math.max(1, math.ceil(largo / 300))
    local mejor, cual = nil, nil
    local vistos = {}
    for k = 0, tramos - 1 do
        local tm = (k + 0.5) / tramos
        self:solidosCerca(x0 + dx * tm, y0 + dy * tm, largo / tramos * 0.75 + 20, tocados)
        for _, h in ipairs(tocados) do
            if not vistos[h] then
                vistos[h] = true
                local ox, oy = x0 - h.cx, y0 - h.cy
                local o = { ox * h.c + oy * h.s, -ox * h.s + oy * h.c, z0 - (h.z0 + h.z1) / 2 }
                local d = { dx * h.c + dy * h.s, -dx * h.s + dy * h.c, dz }
                local m = { h.hx, h.hy, (h.z1 - h.z0) / 2 }
                local a0, a1 = 0, 1
                for i = 1, 3 do
                    if math.abs(d[i]) < 1e-9 then
                        if math.abs(o[i]) > m[i] then
                            a0 = 2
                        end
                    else
                        local a, b = (-m[i] - o[i]) / d[i], (m[i] - o[i]) / d[i]
                        if a > b then
                            a, b = b, a
                        end
                        a0, a1 = math.max(a0, a), math.min(a1, b)
                    end
                end
                if a0 <= a1 and a0 <= 1 and (not mejor or a0 < mejor) then
                    mejor, cual = a0, h
                end
            end
        end
    end
    return mejor, cual
end

--- ¿Estorba (x, y) a la hierba y las flores? Edificios, patios, muro,
-- calles y aceras.
function Plano:estorbaPlanta(x, y)
    return self:ocupado(x, y, 8) or (self.vias ~= nil and self.vias:sobre(x, y, 5)) or self:sobreAerodromo(x, y, 0, 0)
end

--- ¿Está (x, y) sobre el aeródromo: la pista con sus arcenes y la
-- plataforma de los aviones al norte? `margen` px de más a lo largo y a lo
-- ancho y `norte` px de más al norte de la plataforma. Sobre el hormigón
-- no crece nada (27-nov: salían hierba y flores atravesando la plataforma).
function Plano:sobreAerodromo(x, y, margen, norte)
    local p = self.pista
    if not p then
        return false
    end
    local A = Plano.aerodromo
    local largo = A.medioLargo * 10 + 300 + margen
    local alNorte = A.plataforma.hasta * 10 + margen + norte
    local alSur = A.medioAncho + margen
    return math.abs(x - p.x) < largo and y > p.y - alNorte and y < p.y + alSur
end

--- ¿Estorba un árbol en (x, y) dentro del recinto? Edificios, patios y muro
-- (con 10 m de más), calles y aceras (4 m de más) y la franja del aeródromo:
-- la pista con su explanada y la plataforma de los aviones al norte. Lo
-- demás del recinto lleva árboles como el campo (el dueño, 27-nov).
function Plano:estorbaArbol(x, y)
    -- 10 m de los edificios: la copa de un roble grande mide unos 9 m de
    -- radio (con 6 m se metía por las fachadas y los tejados; 27-nov).
    if self:ocupado(x, y, 100) or (self.vias ~= nil and self.vias:sobre(x, y, 40)) then
        return true
    end
    return self:sobreAerodromo(x, y, Plano.aerodromo.talud, 150)
end

--- ¿Está (x, y) dentro del recinto del sitio (con `margen` px de más)?
function Plano:dentro(x, y, margen)
    local r = self.recinto
    margen = margen or 0
    return r and x > r[1] - margen and x < r[3] + margen and y > r[2] - margen and y < r[4] + margen
end

function Plano:calle(i0, j0, i1, j1)
    local x0, y0 = self:nodo(i0, j0)
    local x1, y1 = self:nodo(i1, j1)
    self.calles[#self.calles + 1] = { x0, y0, x1, y1 }
end

-- Muro de una fachada: `lado` 's', 'e', 'n' u 'o'; módulo k desde su
-- esquina de arranque. Las piezas del kit tienen el muro a lo largo de +x
-- con la cara exterior hacia +y (sur); el giro las lleva a cada lado.
local GIRO = { s = 0, e = -PI / 2, n = PI, o = PI / 2 }

local function arranqueMuro(x0, y0, x1, y1, lado, k)
    if lado == 's' then
        return x0 + k * M, y1
    elseif lado == 'e' then
        return x1, y1 - k * M
    elseif lado == 'n' then
        return x1 - k * M, y0
    end
    return x0, y0 + k * M
end

-- Edificio -------------------------------------------------------------------------------

--- Edificio de `w` x `d` módulos con su esquina noroeste en el nodo (i0, j0)
-- del marco actual (`usarMarco`). `e`: pisos, ventanas (probabilidad), nave
-- (diáfana), patio (solo losa), puerta (lado de la fachada principal: 's' es
-- +y del marco), puertas (cuántas en ella), z (altura del suelo ya decidida,
-- p. ej. la de la acera). Devuelve false si el suelo es demasiado empinado.
function Plano:edificio(i0, j0, w, d, e)
    local U = self.U
    local ang = self.mang
    local lo, hi = self:alturasMarco(i0, j0, i0 + w, j0 + d)
    if hi - lo > Plano.desnivelMaximo then
        if os.getenv('PLANO_DEPURAR') then
            print(string.format('PLANO descartado %dx%d en %d,%d: desnivel %.1f m', w, d, i0, j0, (hi - lo) / 10))
        end
        return false
    end
    local cx, cy = self:nodo(i0 + w / 2, j0 + d / 2)
    local hx, hy = w * M / 2, d * M / 2
    -- Explanada (desmonte arriba, terraplén abajo) a la altura pedida o a media altura.
    local zPlano = e.z or (lo + hi) / 2
    local talud = math.max(Plano.taludMinimo, math.max(hi - zPlano, zPlano - lo) * Plano.talud)
    self.suelo:explanarCaja(cx, cy, hx + 20, hy + 20, ang, zPlano, talud)
    lo, hi = self:alturasMarco(i0, j0, i0 + w, j0 + d)
    local z = e.z or (hi + 3)
    -- Cimiento de hormigón hasta el suelo; en los edificios es también su
    -- suelo (por dentro no hay nada: el dueño, 19-nov), en los patios va bajo
    -- las losas.
    if e.patio then
        if z - lo > 4 then
            self.cimientos[#self.cimientos + 1] = { cx = cx, cy = cy, hx = hx, hy = hy, ang = ang, z1 = z - 3, z0 = lo - 6 }
        end
    else
        self.cimientos[#self.cimientos + 1] = { cx = cx, cy = cy, hx = hx, hy = hy, ang = ang, z1 = z, z0 = math.min(lo - 6, z - 3) }
    end
    local huella = self:huellaGirada(cx, cy, hx, hy, ang)
    -- Color de la chapa: las naves y la mina, verde militar; en la ciudad, variado.
    local tono = 1
    if self.sitio.tipo == 'ciudad' and not e.nave then
        tono = 1 + math.floor(U() * Plano.tonos)
    end
    self:abrirGrupo(huella[1], huella[2], huella[3], huella[4], z, tono)
    local pisos = e.patio and 1 or e.pisos
    local registro = { huella[1], huella[2], huella[3], huella[4], z, 0, cx = cx, cy = cy, hx = hx, hy = hy, ang = ang, tono = tono }
    -- Losas solo en los patios (una por celda: la pieza crece hacia el norte
    -- del marco desde su esquina suroeste). Los edificios, huecos.
    if e.patio then
        for j = 0, d - 1 do
            for i = 0, w - 1 do
                local px, py = self:nodo(i0 + i, j0 + j + 1)
                self:poner('losa', px, py, z, ang)
            end
        end
        registro.patio = true
        self.edificios[#self.edificios + 1] = registro
        self.grupo.edificio = registro
        self:cerrarGrupo()
        return true
    end
    -- Pilares en todos los nodos del contorno, por piso.
    for k = 0, pisos - 1 do
        local zk = z + k * Plano.piso
        for i = 0, w do
            local ax, ay = self:nodo(i0 + i, j0)
            local bx, by = self:nodo(i0 + i, j0 + d)
            self:poner('pilar', ax, ay, zk, ang)
            self:poner('pilar', bx, by, zk, ang)
        end
        for j = 1, d - 1 do
            local ax, ay = self:nodo(i0, j0 + j)
            local bx, by = self:nodo(i0 + w, j0 + j)
            self:poner('pilar', ax, ay, zk, ang)
            self:poner('pilar', bx, by, zk, ang)
        end
    end
    -- Puertas de la fachada principal: repartidas, sin tocar las esquinas.
    local principal = e.puerta or 's'
    local puertas = {}
    local largo = (principal == 's' or principal == 'n') and w or d
    local n = math.max(1, math.min(e.puertas or 1, largo - 2))
    for p = 1, n do
        puertas[math.floor(p * largo / (n + 1))] = true
    end
    -- Arranque (nodo) de cada módulo de muro por fachada.
    local function arranque(lado, m)
        if lado == 's' then
            return self:nodo(i0 + m, j0 + d)
        elseif lado == 'e' then
            return self:nodo(i0 + w, j0 + d - m)
        elseif lado == 'n' then
            return self:nodo(i0 + w - m, j0)
        end
        return self:nodo(i0, j0 + m)
    end
    for _, lado in ipairs({ 's', 'e', 'n', 'o' }) do
        local largoLado = (lado == 's' or lado == 'n') and w or d
        for k = 0, pisos - 1 do
            local zk = z + k * Plano.piso
            for m = 0, largoLado - 1 do
                local nombre
                if k == 0 then
                    if lado == principal and puertas[m] then
                        nombre = 'muroPuerta'
                    elseif U() < (e.ventanas or 0.5) then
                        nombre = 'muroVentana'
                    else
                        nombre = 'muro'
                    end
                elseif e.nave then
                    nombre = U() < (e.ventanas or 0) * 2 and 'muroVentanaAlto' or 'muroAlto'
                else
                    nombre = U() < (e.ventanas or 0.5) + 0.15 and 'muroVentanaAlto' or 'muroAlto'
                end
                local x, y = arranque(lado, m)
                self:poner(nombre, x, y, zk, ang + GIRO[lado])
            end
        end
    end
    -- Techo por celda, sobre el último muro.
    local zt = z + (pisos - 1) * Plano.piso + Plano.altoMuro
    for j = 0, d - 1 do
        for i = 0, w - 1 do
            local px, py = self:nodo(i0 + i, j0 + j + 1)
            self:poner('techo', px, py, zt, ang)
        end
    end
    -- Forjados entre pisos: los muros miden 4,06 m y cada piso sube 4,3 m;
    -- sin el canto del forjado quedaba una raja de 24 cm en cada piso por la
    -- que se veía el cielo (el dueño, 27-nov). Una losa de acero del tamaño
    -- de la planta, que por fuera se lee como el larguero entre módulos.
    for k = 1, pisos - 1 do
        local zk = z + k * Plano.piso
        self.cimientos[#self.cimientos + 1] = {
            cx = cx,
            cy = cy,
            hx = hx,
            hy = hy,
            ang = ang,
            z0 = zk - (Plano.piso - Plano.altoMuro) - 1,
            z1 = zk + 1,
            material = 'kitAcero',
        }
    end
    registro[6] = zt + 4 - z
    -- Sólido para la física (vehículos, robots, soldados y balas).
    huella.solido, huella.z0, huella.z1 = true, math.min(lo, z) - 6, zt + 4
    self.edificios[#self.edificios + 1] = registro
    self.grupo.edificio = registro
    self:cerrarGrupo()
    return true
end

-- Aeródromo ----------------------------------------------------------------------------------

--- La pista del aeródromo (Plano.aerodromo) al norte del muro viejo, que
-- estaba a `medioNorte` módulos del centro: `self.pista` = { x, y, rumbo,
-- medioLargo } (px, rumbo del juego, m).
-- El terreno se explana como una pista de verdad: la recta que mejor se
-- ajusta al terreno a lo largo del eje (mínimos cuadrados), con la pendiente
-- limitada a `pendiente`; se corta o se rellena hasta ella, con talud.
-- Llamarla antes del muro (que se asienta en el terreno ya explanado).
function Plano:ponerPista(medioNorte)
    local A = Plano.aerodromo
    local s = self.suelo
    local x, y = self.ox, self.oy - medioNorte * M - A.ejeDesdeMuro
    local L = A.medioLargo * 10 + 300 -- px, con 30 m de más en cada cabecera
    local sa, sz, saa, saz, n = 0, 0, 0, 0, 0
    for a = -L, L, 100 do
        local z = s:altura(x + a, y)
        sa, sz, saa, saz, n = sa + a, sz + z, saa + a * a, saz + a * z, n + 1
    end
    local pendiente = (n * saz - sa * sz) / (n * saa - sa * sa)
    pendiente = math.max(-A.pendiente, math.min(A.pendiente, pendiente))
    local z0 = sz / n - pendiente * sa / n
    -- Lo más hondo que corta o rellena (m), para el registro.
    local hondo = 0
    for a = -L, L, 100 do
        for b = -A.medioAncho, A.medioAncho, 130 do
            hondo = math.max(hondo, math.abs(z0 + pendiente * a - s:altura(x + a, y + b)))
        end
    end
    print(string.format('AERODROMO explanada: pendiente %.1f %%, desmonte o relleno de hasta %.1f m', pendiente * 100, hondo / 10))
    for a = -L, L - 400, 400 do
        s:explanarTramo(x + a, y, z0 + pendiente * a, x + a + 400, y, z0 + pendiente * (a + 400), A.medioAncho, A.talud, A.taludRelacion)
    end
    -- La plataforma, al norte (y menos en px), a la misma altura que la pista.
    local P = A.plataforma
    local centro = (P.desde + P.hasta) / 2 * 10
    local medio = (P.hasta - P.desde) / 2 * 10 + 60
    for a = -L, L - 400, 400 do
        s:explanarTramo(x + a, y - centro, z0 + pendiente * a, x + a + 400, y - centro, z0 + pendiente * (a + 400), medio, A.talud, A.taludRelacion)
    end
    self.pista = {
        x = x,
        y = y,
        rumbo = 0,
        medioLargo = A.medioLargo,
        pendiente = pendiente,
    }
end

-- Recinto ------------------------------------------------------------------------------------

--- Muro de recinto en el rectángulo de nodos (i0, j0)-(i1, j1), con
-- `portones[lado][m] = true` en los módulos de entrada.
function Plano:recintoMuro(i0, j0, i1, j1, portones)
    local s = self.suelo
    self:usarMarco(self.ox, self.oy, 0)
    local x0, y0 = self:nodo(i0, j0)
    local x1, y1 = self:nodo(i1, j1)
    self.recinto = { x0, y0, x1, y1 }
    for _, lado in ipairs({ 's', 'e', 'n', 'o' }) do
        local largo = (lado == 's' or lado == 'n') and (i1 - i0) or (j1 - j0)
        local giro = GIRO[lado]
        local dx, dy = math.cos(giro), math.sin(giro)
        for m = 0, largo - 1 do
            local x, y = arranqueMuro(x0, y0, x1, y1, lado, m)
            -- Tramos de 8 módulos (32 m), cada uno su grupo.
            if m % 8 == 0 then
                local fx, fy = arranqueMuro(x0, y0, x1, y1, lado, math.min(m + 8, largo))
                self:abrirGrupo(math.min(x, fx) - 10, math.min(y, fy) - 10, math.max(x, fx) + 10, math.max(y, fy) + 10, s:altura(x, y), 1)
            end
            local ha = s:altura(x, y)
            local hb = s:altura(x + dx * M, y + dy * M)
            local z = math.min(ha, hb) - 2
            local porton = portones[lado] and portones[lado][m]
            self:poner(porton and 'portonRecinto' or 'muroRecinto', x, y, z, giro)
            local ax, ay = math.min(x, x + dx * M), math.min(y, y + dy * M)
            local bx, by = math.max(x, x + dx * M), math.max(y, y + dy * M)
            if not porton then
                local h = self:huella(ax - 6, ay - 6, bx + 6, by + 6)
                h.solido, h.z0, h.z1, h.muro = true, z - 4, z + 32, true
            end
            -- En ladera, el panel apoya en lo bajo y se cimienta.
            if math.abs(ha - hb) > 6 then
                self.cimientos[#self.cimientos + 1] = {
                    cx = (ax + bx) / 2, cy = (ay + by) / 2, hx = (bx - ax) / 2 + 2, hy = (by - ay) / 2 + 2, ang = 0, z1 = z, z0 = z - 8,
                }
            end
        end
        self:cerrarGrupo()
    end
end

-- Ciudad ---------------------------------------------------------------------------------------

local Calles = require('batalla.sitios.calles')

--- ¿Cabe un edificio (caja girada) aquí? Ni sobre una calle ni su acera, ni
-- encima de otro edificio (con `hueco` px entre medias), y dentro del muro.
function Plano:cabe(cx, cy, hx, hy, ang, hueco)
    local c, s = math.cos(ang), math.sin(ang)
    local calles = self.vias
    for v = -0.95, 0.95, 0.2375 do
        for u = -0.95, 0.95, 0.2375 do
            local x = cx + u * hx * c - v * hy * s
            local y = cy + u * hx * s + v * hy * c
            if not calles:dentro(x, y, 120) or calles:sobre(x, y, 0) or self:ocupado(x, y, hueco) then
                return false
            end
        end
    end
    return true
end

--- Edificios a lo largo de las calles, mirando a la acera, y alguno detrás
-- (patios, naves, bloques de varios pisos según lo cerca que estén del centro).
function Plano:fachadas(medioCiudad, t)
    local U = self.U
    local calles = self.vias
    for _, e in ipairs(calles.aristas) do
        local d = e.datos
        for _, lado in ipairs({ 1, -1 }) do
            -- Sin edificios en los primeros metros (el cruce y su acera).
            local s = math.max(#e.a.aristas > 1 and (d.calzada + d.acera * 2) or 0, e.a.radio or 0) + 40
            local fin = e.largo - (math.max(#e.b.aristas > 1 and (d.calzada + d.acera * 2) or 0, e.b.radio or 0) + 40)
            while s < fin do
                local w = 3 + math.floor(U() * 6)
                local largoPx = w * M
                if s + largoPx > fin then
                    break
                end
                local sm = s + largoPx / 2
                local px, py, rumbo = Calles.punto(e, sm)
                -- Normal hacia este lado y eje hacia la calle (la fachada «s»).
                local nx, ny = -math.sin(rumbo) * lado, math.cos(rumbo) * lado
                local eyx, eyy = -nx, -ny
                local ang = math.atan2(-eyx, eyy)
                local dist = math.sqrt((px - self.ox) ^ 2 + (py - self.oy) ^ 2) / (medioCiudad * M)
                local fondo = 3 + math.floor(U() * (dist < 0.4 and 5 or 4))
                local frente = d.calzada / 2 + d.acera + 12
                local cx = px + nx * (frente + fondo * M / 2)
                local cy = py + ny * (frente + fondo * M / 2)
                local hx, hy = largoPx / 2, fondo * M / 2
                self.probados = (self.probados or 0) + 1
                if not self:cabe(cx, cy, hx, hy, ang, 30) then
                    self.sinSitio = (self.sinSitio or 0) + 1
                end
                if self:cabe(cx, cy, hx, hy, ang, 30) then
                    local zAcera = Calles.alturaEn(e, sm) + Calles.bordillo
                    -- Origen del marco: esquina de atrás a la izquierda.
                    local c, si = math.cos(ang), math.sin(ang)
                    self:usarMarco(cx - hx * c + hy * si, cy - hx * si - hy * c, ang)
                    local pisos
                    if dist < 0.3 then
                        pisos = t.pisosCentro[1] + math.floor(U() * (t.pisosCentro[2] - t.pisosCentro[1] + 1))
                    elseif dist < 0.65 then
                        pisos = 2 + math.floor(U() * 2)
                    else
                        pisos = 1 + math.floor(U() * 2)
                    end
                    local r0 = U()
                    if r0 < 0.07 then
                        self:edificio(0, 0, w, fondo, { patio = true, z = zAcera })
                    elseif dist > 0.6 and r0 < 0.3 and w * fondo >= 24 then
                        self:edificio(0, 0, w, fondo, { pisos = 2, nave = true, ventanas = 0.08, puerta = 's', puertas = 2, z = zAcera })
                    else
                        self:edificio(0, 0, w, fondo, {
                            pisos = pisos,
                            ventanas = 0.65 + U() * 0.25,
                            puerta = 's',
                            puertas = w > 5 and 2 or 1,
                            z = zAcera,
                        })
                    end
                    -- Detrás, a veces otro (la manzana se llena hacia dentro).
                    local fondo2 = 3 + math.floor(U() * 4)
                    local cx2 = px + nx * (frente + fondo * M + 2 * M + fondo2 * M / 2)
                    local cy2 = py + ny * (frente + fondo * M + 2 * M + fondo2 * M / 2)
                    if U() < 0.6 and self:cabe(cx2, cy2, hx, fondo2 * M / 2, ang, 30) then
                        local hy2 = fondo2 * M / 2
                        self:usarMarco(cx2 - hx * c + hy2 * si, cy2 - hx * si - hy2 * c, ang)
                        self:edificio(0, 0, w, fondo2, {
                            pisos = math.max(1, pisos - 1),
                            ventanas = 0.6,
                            puerta = 's',
                            puertas = 1,
                        })
                    end
                end
                s = s + largoPx + 10 + math.floor(U() * 3) * M
            end
        end
    end
end

function Plano:ciudad(t)
    local U = self.U
    local medio = t.medio
    local R = medio * M
    local x0, y0, x1, y1 = self.ox - R, self.oy - R, self.ox + R, self.oy + R
    local calles = Calles.nueva(self.suelo, U, { x0, y0, x1, y1 })
    self.vias = calles
    -- Ronda por dentro del muro (30 m).
    local r = R - 300
    local esquinas = {
        calles:nodo(self.ox - r, self.oy - r),
        calles:nodo(self.ox + r, self.oy - r),
        calles:nodo(self.ox + r, self.oy + r),
        calles:nodo(self.ox - r, self.oy + r),
    }
    for k = 1, 4 do
        local a, b = esquinas[k], esquinas[k % 4 + 1]
        calles:arista(a, b, { a.x, a.y, b.x, b.y }, 'ronda')
    end
    -- Centro (algo movido) y un portón por lado, en un sitio al azar del lado;
    -- a veces un segundo portón en un lado largo.
    local centro = calles:nodo(self.ox + U(-0.08, 0.08) * R, self.oy + U(-0.08, 0.08) * R)
    local portones = {}
    local lados = { { 0, 1, 's' }, { 1, 0, 'e' }, { 0, -1, 'n' }, { -1, 0, 'o' } }
    local salidas = {}
    for _, l in ipairs(lados) do
        local n = U() < 0.3 and 2 or 1
        for k = 1, n do
            local f = n == 1 and U(-0.35, 0.35) or (k == 1 and U(-0.6, -0.25) or U(0.25, 0.6))
            -- Módulo del muro y punto del portón.
            local m = math.floor((f + 1) / 2 * medio * 2)
            local gx, gy
            if l[3] == 's' or l[3] == 'n' then
                gx, gy = x0 + (m + 0.5) * M, l[3] == 's' and y1 or y0
            else
                gx, gy = l[3] == 'e' and x1 or x0, y0 + (m + 0.5) * M
            end
            salidas[#salidas + 1] = { gx, gy, l }
        end
    end
    -- Avenidas: del centro a cada portón (y 60 m fuera, el camino que sale).
    for _, sa in ipairs(salidas) do
        local gx, gy, l = sa[1], sa[2], sa[1 + 2]
        local pts = calles:trazar(centro.x, centro.y, gx - l[1] * 50, gy - l[2] * 50)
        pts[#pts + 1], pts[#pts + 2] = gx + l[1] * 600, gy + l[2] * 600
        local _, nb = calles:insertar(pts, 'avenida', centro, nil)
        -- Portón: los módulos del muro que pisa la avenida y sus aceras.
        local ancho = Calles.clases.avenida.calzada / 2 + Calles.clases.avenida.acera + 20
        local lado = l[3]
        portones[lado] = portones[lado] or {}
        for m = 0, medio * 2 - 1 do
            local mx, my
            if lado == 's' then
                mx = x0 + (m + 0.5) * M
                if math.abs(mx - gx) < ancho + M / 2 then
                    portones[lado][m] = true
                end
            elseif lado == 'n' then
                mx = x1 - (m + 0.5) * M
                if math.abs(mx - gx) < ancho + M / 2 then
                    portones[lado][m] = true
                end
            elseif lado == 'e' then
                my = y1 - (m + 0.5) * M
                if math.abs(my - gy) < ancho + M / 2 then
                    portones[lado][m] = true
                end
            else
                my = y0 + (m + 0.5) * M
                if math.abs(my - gy) < ancho + M / 2 then
                    portones[lado][m] = true
                end
            end
        end
    end
    -- Calles secundarias, perfiles y explanadas.
    calles:sembrar(t.calles or 140)
    calles:nivelar()
    -- Edificios a lo largo de las calles.
    self:fachadas(medio, t)
    if os.getenv('PLANO_DEPURAR') then
        local largo = 0
        for _, e in ipairs(calles.aristas) do
            largo = largo + e.largo
        end
        print(string.format('CALLES %d nodos, %d aristas, %.1f km; probados %d, sin sitio %d', #calles.nodos, #calles.aristas, largo / 10000, self.probados or 0, self.sinSitio or 0))
        -- Puntos para mirar: el cruce con más calles y el medio de dos calles.
        local mejor
        for _, n in ipairs(calles.nodos) do
            if not mejor or #n.aristas > #mejor.aristas then
                mejor = n
            end
        end
        print(string.format('VISTA cruce %.0f,%.0f (%d calles)', mejor.x, mejor.y, #mejor.aristas))
        for k, e in ipairs(calles.aristas) do
            if k % 37 == 1 then
                local x, y, r = Calles.punto(e, e.largo / 2)
                print(string.format('VISTA %s %.0f,%.0f rumbo %.0f', e.clase, x, y, math.deg(r)))
            end
        end
    end
    -- El muro, al final (sobre el terreno ya explanado).
    -- Con el aeródromo: el muro se alarga al norte y, si hace falta, a los
    -- lados; los portones se corren lo que se corre el arranque de su lado
    -- (arranqueMuro) y el del norte queda dentro (da al aeródromo).
    local A = Plano.aerodromo
    local W = math.max(medio, A.medioMuro)
    local corridos = {}
    for lado, lista in pairs(portones) do
        if lado ~= 'n' then
            local corre = (lado == 's') and (W - medio) or (lado == 'o' and A.fondo or 0)
            corridos[lado] = {}
            for m in pairs(lista) do
                corridos[lado][m + corre] = true
            end
        end
    end
    self:ponerPista(medio)
    self:recintoMuro(-W, -medio - A.fondo, W, medio, corridos)
end

-- Mina -------------------------------------------------------------------------------------------

function Plano:mina(t)
    local mx, my = t.medioX, t.medioY
    -- Calle central de norte a sur y calle de ronda.
    self:calle(0, my, 0, -my + 3)
    local r = 2
    self:calle(-mx + r, -my + r, mx - r, -my + r)
    self:calle(-mx + r, my - r, mx - r, my - r)
    self:calle(-mx + r, -my + r, -mx + r, my - r)
    self:calle(mx - r, -my + r, mx - r, my - r)
    -- Edificios a los dos lados de la calle (la calle ocupa los módulos -1 y 0),
    -- de sur a norte, con la fachada principal hacia ella.
    local fin = { o = my - 4, e = my - 4 } -- hasta dónde llega cada lado (j, hacia el norte)
    for _, e in ipairs(t.edificios) do
        local w, d = e[2], e[3]
        local lado = fin.o >= fin.e and 'o' or 'e'
        local j1 = fin[lado]
        local j0 = j1 - d
        if j0 < -my + 4 then
            lado = lado == 'o' and 'e' or 'o'
            j1 = fin[lado]
            j0 = j1 - d
        end
        if j0 >= -my + 4 then
            local i0 = lado == 'o' and (-1 - 2 - w) or (1 + 2)
            if i0 >= -mx + 4 and i0 + w <= mx - 4 then
                self:edificio(i0, j0, w, d, {
                    pisos = e[4],
                    ventanas = e.ventanas,
                    nave = e.nave,
                    patio = e.patio,
                    puerta = lado == 'o' and 'e' or 'o',
                    puertas = e.puertas,
                })
                -- Acceso de la puerta a la calle.
                local jm = j0 + d / 2
                self:calle(lado == 'o' and (i0 + w) or i0, jm, 0, jm)
            end
            fin[lado] = j0 - 3
        end
    end
    -- Portón doble en el centro del lado sur; el muro, al final.
    self:ponerPista(my)
    local W = math.max(mx, Plano.aerodromo.medioMuro)
    self:recintoMuro(-W, -my - Plano.aerodromo.fondo, W, my, { s = { [W - 1] = true, [W] = true } })
end

return Plano

--- Territorio por celdas cuadradas: dueños, bloques de los sitios, fronteras y trozos.
--
-- El estado guarda solo las celdas con dueño, por nación y por fila, en tramos
-- de celdas seguidas: `e.territorio[nid][cy] = { cx0, cx1, cx0, cx1, ... }`
-- (cada par es un tramo [cx0, cx1], de izquierda a derecha).
-- `e.versionTerritorio` sube cada vez que cambia una celda. Fuera del estado,
-- y rehechos de él al cargar: un mapa celda -> nación para preguntar rápido y,
-- por cada par de naciones, cuántos lados de celda comparten (su frontera).
--
-- Módulo de `mundo/simulacion.lua`: `Territorio.instalar(Simulacion)` cuelga sus
-- funciones de la clase, así que la API pública no cambia. Diseño en
-- diseno/territorio-y-capitales.md. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')

local ordenadas = Ayudas.ordenadas
local esCiudad = Ayudas.esCiudad
local claveCelda = Ayudas.claveCelda
local VECINOS = Ayudas.VECINOS

local Territorio = {}

-- Se fijan en `instalar`: la clase y el lado de la celda.
local Simulacion
local CELDA

--- Celda (cx, cy) que contiene el punto (x, y).
function Territorio.celdaDe(x, y)
    return math.floor(x / CELDA), math.floor(y / CELDA)
end

--- Bloque de `lado` x `lado` celdas centrado en (x, y): va del vértice de la
-- rejilla más cercano `lado / 2` celdas a cada lado. Devuelve cx0, cy0, cx1, cy1.
function Territorio.bloque(x, y, lado)
    local vx = math.floor(x / CELDA + 0.5)
    local vy = math.floor(y / CELDA + 0.5)
    local medio = math.floor(lado / 2)
    return vx - medio, vy - medio, vx - medio + lado - 1, vy - medio + lado - 1
end

--- Lado del bloque que da un sitio (celdas), o nil: una ciudad siempre; una
-- instalación, del tipo que da territorio (terminada o no).
local function ladoBloque(sitio)
    if esCiudad(sitio) then
        return Simulacion.bloques.ciudad
    end
    return Simulacion.bloques[sitio.tipo]
end

--- Bloque de territorio de un sitio que lo da ya (cx0, cy0, cx1, cy1), o nil.
function Territorio.bloqueDe(sitio)
    if not esCiudad(sitio) and not Simulacion.daTerritorio(sitio) then
        return nil
    end
    return Simulacion.bloque(sitio.x, sitio.y, ladoBloque(sitio))
end

--- Mete la celda cx en la fila `cy` de `filas`, uniendo los tramos que se tocan.
local function ponerEnFila(filas, cy, cx)
    local tramos = filas[cy]
    if not tramos then
        filas[cy] = { cx, cx }
        return
    end
    local ordenados = {}
    local puesta = false
    for k = 1, #tramos, 2 do
        if not puesta and cx < tramos[k] then
            ordenados[#ordenados + 1] = cx
            ordenados[#ordenados + 1] = cx
            puesta = true
        end
        ordenados[#ordenados + 1] = tramos[k]
        ordenados[#ordenados + 1] = tramos[k + 1]
    end
    if not puesta then
        ordenados[#ordenados + 1] = cx
        ordenados[#ordenados + 1] = cx
    end
    local unidos = {}
    for k = 1, #ordenados, 2 do
        local a, b = ordenados[k], ordenados[k + 1]
        local n = #unidos
        if n > 0 and a <= unidos[n] + 1 then
            unidos[n] = math.max(unidos[n], b)
        else
            unidos[n + 1] = a
            unidos[n + 2] = b
        end
    end
    filas[cy] = unidos
end

--- Saca la celda cx de la fila `cy` de `filas`, partiendo su tramo si hace falta.
local function quitarDeFila(filas, cy, cx)
    local tramos = filas[cy]
    if not tramos then
        return
    end
    local quedan = {}
    for k = 1, #tramos, 2 do
        local a, b = tramos[k], tramos[k + 1]
        if cx < a or cx > b then
            quedan[#quedan + 1] = a
            quedan[#quedan + 1] = b
        else
            if a <= cx - 1 then
                quedan[#quedan + 1] = a
                quedan[#quedan + 1] = cx - 1
            end
            if cx + 1 <= b then
                quedan[#quedan + 1] = cx + 1
                quedan[#quedan + 1] = b
            end
        end
    end
    if #quedan == 0 then
        filas[cy] = nil
    else
        filas[cy] = quedan
    end
end

--- Suma `cuanto` a los lados de celda que comparten las naciones a y b.
local function sumarFrontera(fronteras, a, b, cuanto)
    fronteras[a] = fronteras[a] or {}
    fronteras[b] = fronteras[b] or {}
    fronteras[a][b] = (fronteras[a][b] or 0) + cuanto
    fronteras[b][a] = (fronteras[b][a] or 0) + cuanto
end

--- Mapa celda -> nación, rehecho del estado si hace falta (al cargar). El
-- orden en que se recorre no cambia el resultado: cada celda tiene un dueño y
-- las fronteras son cuentas.
function Territorio:mapaTerritorio()
    if self.mapaCeldas then
        return self.mapaCeldas
    end
    local e = self.estado
    e.territorio = e.territorio or {}
    e.versionTerritorio = e.versionTerritorio or 0
    local mapa = {}
    for nid, filas in pairs(e.territorio) do
        for cy, tramos in pairs(filas) do
            for k = 1, #tramos, 2 do
                for cx = tramos[k], tramos[k + 1] do
                    mapa[claveCelda(cx, cy)] = nid
                end
            end
        end
    end
    -- Cada lado compartido se cuenta una vez: el de la derecha y el de abajo.
    local fronteras = {}
    for nid, filas in pairs(e.territorio) do
        for cy, tramos in pairs(filas) do
            for k = 1, #tramos, 2 do
                for cx = tramos[k], tramos[k + 1] do
                    local derecha = mapa[claveCelda(cx + 1, cy)]
                    if derecha and derecha ~= nid then
                        sumarFrontera(fronteras, nid, derecha, 1)
                    end
                    local abajo = mapa[claveCelda(cx, cy + 1)]
                    if abajo and abajo ~= nid then
                        sumarFrontera(fronteras, nid, abajo, 1)
                    end
                end
            end
        end
    end
    self.mapaCeldas, self.fronterasTerritorio = mapa, fronteras
    self.trozosDe, self.trozosSucios = {}, {}
    return mapa
end

--- Nación dueña de la celda (cx, cy) (id), o nil si es tierra sin dueño.
function Territorio:duenoCelda(cx, cy)
    return self:mapaTerritorio()[claveCelda(cx, cy)]
end

--- Da la celda (cx, cy) a `nid` (o la deja sin dueño con nil). Devuelve true
-- si cambió.
function Territorio:ponerCelda(cx, cy, nid)
    local mapa = self:mapaTerritorio()
    local clave = claveCelda(cx, cy)
    local antes = mapa[clave]
    if antes == nid then
        return false
    end
    local e = self.estado
    if antes then
        quitarDeFila(e.territorio[antes], cy, cx)
        if next(e.territorio[antes]) == nil then
            e.territorio[antes] = nil
        end
    end
    if nid then
        e.territorio[nid] = e.territorio[nid] or {}
        ponerEnFila(e.territorio[nid], cy, cx)
    end
    mapa[clave] = nid
    local fronteras = self.fronterasTerritorio
    for _, v in ipairs(VECINOS) do
        local otra = mapa[claveCelda(cx + v[1], cy + v[2])]
        if otra then
            if antes and otra ~= antes then
                sumarFrontera(fronteras, antes, otra, -1)
            end
            if nid and otra ~= nid then
                sumarFrontera(fronteras, nid, otra, 1)
            end
        end
    end
    -- Los trozos de las naciones que pierden, ganan o tocan esta celda se rehacen.
    local sucios = self.trozosSucios
    if antes then
        sucios[antes] = true
    end
    if nid then
        sucios[nid] = true
    end
    for _, v in ipairs(VECINOS) do
        local otra = mapa[claveCelda(cx + v[1], cy + v[2])]
        if otra then
            sucios[otra] = true
        end
    end
    e.versionTerritorio = e.versionTerritorio + 1
    -- El borde de las banderas (banderas.lua) rehace los bloques que toca.
    self:celdaCambiada(cx, cy, antes, nid)
    return true
end

--- El territorio cambió: la vista lo vuelve a pintar (`self.cambios`, que la
-- vista de antes mira; la nueva mira `e.versionTerritorio`).
function Territorio:territorioCambiado()
    self.cambios = (self.cambios or 0) + 1
end

--- `sitio` empieza a dar territorio: toma las celdas libres de su bloque (las
-- de otra nación no se pisan). Devuelve cuántas tomó.
function Territorio:reclamarBloque(sitio)
    local cx0, cy0, cx1, cy1 = Simulacion.bloqueDe(sitio)
    if not cx0 then
        return 0
    end
    -- Un campamento que se termina empieza a cubrir: `cubre` rehace sus bloques.
    if self.indiceHecho then
        self.indiceHecho.cubren = nil
    end
    local nuevas = 0
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            if self:duenoCelda(cx, cy) == nil and self:ponerCelda(cx, cy, sitio.nacion) then
                nuevas = nuevas + 1
            end
        end
    end
    if nuevas > 0 then
        self:territorioCambiado()
    end
    -- Sus celdas dejan de ser tierra de bandera (banderas.lua).
    self:bloqueSitioCambiado(cx0, cy0, cx1, cy1, sitio.nacion)
    return nuevas
end

--- Bloques (cx0, cy0, cx1, cy1, ...) de los sitios vivos de `nid` que dan
-- territorio: sus ciudades y sus instalaciones terminadas que lo dan. Se
-- guardan en el índice (`idx.cubren`): se rehacen con él y cuando un
-- campamento se termina (`reclamarBloque`).
local function bloquesQueCubren(self, nid)
    local idx = self:indice()
    local cubren = idx.cubren
    if not cubren then
        cubren = {}
        idx.cubren = cubren
    end
    local suyos = cubren[nid]
    if suyos then
        return suyos
    end
    suyos = {}
    local function meter(sitio)
        local x0, y0, x1, y1 = Simulacion.bloqueDe(sitio)
        if x0 then
            suyos[#suyos + 1] = x0
            suyos[#suyos + 1] = y0
            suyos[#suyos + 1] = x1
            suyos[#suyos + 1] = y1
        end
    end
    for _, c in ipairs(idx.ciudades[nid] or {}) do
        meter(c)
    end
    for _, i in ipairs(idx.instalaciones[nid] or {}) do
        meter(i)
    end
    cubren[nid] = suyos
    return suyos
end

--- ¿Cubre la celda (cx, cy) el bloque de algún sitio vivo de `nid` (una
-- ciudad o una instalación que ya da territorio)?
function Territorio:cubre(nid, cx, cy)
    local b = bloquesQueCubren(self, nid)
    for k = 1, #b, 4 do
        if cx >= b[k] and cx <= b[k + 2] and cy >= b[k + 1] and cy <= b[k + 3] then
            return true
        end
    end
    return false
end

--- `sitio` dejó de dar territorio a `nid` (cayó, se abandonó o cambió de
-- manos, y ya no está en el índice como suyo): las celdas de su bloque que
-- eran de `nid` quedan sin dueño, salvo las que cubre otro sitio vivo suyo.
function Territorio:soltarBloque(sitio, nid)
    nid = nid or sitio.nacion
    local lado = ladoBloque(sitio)
    if not lado then
        return 0
    end
    local cx0, cy0, cx1, cy1 = Simulacion.bloque(sitio.x, sitio.y, lado)
    local sueltas = 0
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            if self:duenoCelda(cx, cy) == nid and not self:cubre(nid, cx, cy) then
                self:ponerCelda(cx, cy, nil)
                sueltas = sueltas + 1
            end
        end
    end
    if sueltas > 0 then
        self:territorioCambiado()
    end
    -- Lo que quede suyo en el bloque puede volver a ser tierra de bandera.
    self:bloqueSitioCambiado(cx0, cy0, cx1, cy1, nid)
    if sitio.nacion ~= nid then
        self:bloqueSitioCambiado(cx0, cy0, cx1, cy1, sitio.nacion)
    end
    return sueltas
end

--- Celdas con dueño en el rectángulo de celdas [cx0, cx1] x [cy0, cy1], en
-- orden fijo (por fila y, en cada fila, de izquierda a derecha):
-- { {cx, cy, nacion}, ... }.
function Territorio:celdasEn(cx0, cy0, cx1, cy1)
    local e = self.estado
    self:mapaTerritorio()
    local out = {}
    for _, nid in ipairs(ordenadas(e.territorio)) do
        local filas = e.territorio[nid]
        for cy = cy0, cy1 do
            local tramos = filas[cy]
            if tramos then
                for k = 1, #tramos, 2 do
                    for cx = math.max(cx0, tramos[k]), math.min(cx1, tramos[k + 1]) do
                        out[#out + 1] = { cx, cy, nid }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a[2] ~= b[2] then
            return a[2] < b[2]
        end
        return a[1] < b[1]
    end)
    return out
end

--- Celdas de una nación (cuántas).
function Territorio:celdasDe(nid)
    local filas = self.estado.territorio and self.estado.territorio[nid]
    local total = 0
    for _, tramos in pairs(filas or {}) do
        for k = 1, #tramos, 2 do
            total = total + tramos[k + 1] - tramos[k] + 1
        end
    end
    return total
end

--- ¿Comparten a y b algún lado de celda (hacen frontera)?
function Territorio:hayFrontera(a, b)
    self:mapaTerritorio()
    local suyas = self.fronterasTerritorio[a]
    return suyas ~= nil and (suyas[b] or 0) > 0
end

--- ¿Toca el bloque [cx0, cx1] x [cy0, cy1] el territorio de `nid`? Tiene que
-- tener una celda suya dentro o pegada por un lado.
function Territorio:bloqueToca(nid, cx0, cy0, cx1, cy1)
    for cy = cy0 - 1, cy1 + 1 do
        for cx = cx0 - 1, cx1 + 1 do
            local esquina = (cy == cy0 - 1 or cy == cy1 + 1) and (cx == cx0 - 1 or cx == cx1 + 1)
            if not esquina and self:duenoCelda(cx, cy) == nid then
                return true
            end
        end
    end
    return false
end

--- Nación dueña del punto (x, y), o nil (tierra sin dueño): la de su celda.
function Territorio:dueno(x, y)
    local nid = self:duenoCelda(math.floor(x / CELDA), math.floor(y / CELDA))
    return nid and self.estado.naciones[nid] or nil
end

--- Nación dueña de la celda de un yacimiento (id o nil). Las extracciones
-- no dan territorio: una extracción necesita la tierra de una ciudad, una
-- base, un campamento o una bandera (si cae la bandera, deja de producir).
function Territorio:duenoDeposito(d)
    return self:duenoCelda(math.floor(d.x / CELDA), math.floor(d.y / CELDA))
end

--- Medio lado del bloque de territorio de una ciudad (px).
function Territorio.alcance(_self, _c)
    return Simulacion.bloques.ciudad * CELDA / 2
end

--- Compatibilidad con la vista de antes (`territorio.lua`): ya no hay
-- candidatos; `duenoEntre` pregunta a la celda.
function Territorio.candidatos()
    return {}
end

function Territorio:duenoEntre(_candidatos, x, y)
    return self:dueno(x, y)
end

--- Trozos de territorio de una nación: sus celdas conectadas por un lado.
-- { de = clave de celda -> número de trozo, vecinos = trozo -> { nación que
-- lo toca por un lado = true } }. Se rehace solo cuando cambia una celda suya
-- o pegada a las suyas (`ponerCelda` lo marca), recorriendo solo sus celdas.
function Territorio:trozos(nid)
    local hecho = self.trozosDe and self.trozosDe[nid]
    if hecho and not self.trozosSucios[nid] then
        return hecho
    end
    local mapa = self:mapaTerritorio()
    local filas = self.estado.territorio[nid] or {}
    local de, vecinos = {}, {}
    local k = 0
    for _, cy in ipairs(ordenadas(filas)) do
        local tramos = filas[cy]
        for t = 1, #tramos, 2 do
            for cx = tramos[t], tramos[t + 1] do
                local clave = claveCelda(cx, cy)
                if not de[clave] then
                    -- Trozo nuevo: se llena desde esta celda.
                    k = k + 1
                    local toca = {}
                    vecinos[k] = toca
                    de[clave] = k
                    local pila = { cx, cy }
                    while #pila > 0 do
                        local py = table.remove(pila)
                        local px = table.remove(pila)
                        for _, v in ipairs(VECINOS) do
                            local nx, ny = px + v[1], py + v[2]
                            local kn = claveCelda(nx, ny)
                            local otra = mapa[kn]
                            if otra == nid then
                                if not de[kn] then
                                    de[kn] = k
                                    pila[#pila + 1] = nx
                                    pila[#pila + 1] = ny
                                end
                            elseif otra then
                                toca[otra] = true
                            end
                        end
                    end
                end
            end
        end
    end
    hecho = { de = de, vecinos = vecinos }
    self.trozosDe[nid] = hecho
    self.trozosSucios[nid] = nil
    return hecho
end

--- ¿Toca el territorio de `nid` el trozo de territorio donde está `sitio`?
-- Si la celda del sitio no es de su nación (una bandera en obra), cuenta
-- solo esa celda: su celda o una vecina por un lado tiene que ser de `nid`.
function Territorio:tocaTrozo(nid, sitio)
    local cx, cy = Simulacion.celdaDe(sitio.x, sitio.y)
    local dueno = self:duenoCelda(cx, cy)
    if dueno == sitio.nacion then
        local trozos = self:trozos(dueno)
        return trozos.vecinos[trozos.de[claveCelda(cx, cy)]][nid] == true
    end
    if dueno == nid then
        return true
    end
    for _, v in ipairs(VECINOS) do
        if self:duenoCelda(cx + v[1], cy + v[2]) == nid then
            return true
        end
    end
    return false
end

local publicas = {
    'celdaDe',
    'bloque',
    'bloqueDe',
    'mapaTerritorio',
    'duenoCelda',
    'ponerCelda',
    'territorioCambiado',
    'reclamarBloque',
    'cubre',
    'soltarBloque',
    'celdasEn',
    'celdasDe',
    'hayFrontera',
    'bloqueToca',
    'dueno',
    'duenoDeposito',
    'alcance',
    'candidatos',
    'duenoEntre',
    'trozos',
    'tocaTrozo',
}

--- Cuelga de la clase Simulacion las funciones de territorio.
function Territorio.instalar(clase)
    Simulacion = clase
    CELDA = clase.celda
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Territorio[nombre]
    end
end

return Territorio

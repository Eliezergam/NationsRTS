--- Cuerpos de la batalla 3D para el daño real (Valeria, batalla/DANO-REAL.md
-- §5.1 y §8.2): cajas orientadas de cada unidad y del edificio, en una
-- rejilla espacial que se rehace en cada paso de la pelea.
--
--   tanque     casco (con la postura del terreno), torreta (gira con ella)
--              y cañón: cajas de los vértices de su modelo 3D
--   camión     chasis (con las ruedas) y contenedor
--   edificio   las cajas de la torre de la ciudad o de la losa del sitio
--
-- Un rayo se pasa a las coordenadas locales de cada caja (las matrices son
-- giros más traslación) y se cruza por placas: sale la cara por la que
-- entra, su normal y el punto local. Antes se descarta con una esfera.

local Modelos3d = require('mundo.modelos3d')
local Ciudades = require('mundo.ciudades')

local Cuerpos = {}
Cuerpos.__index = Cuerpos

Cuerpos.celda = 256 -- px de la rejilla (25,6 m)

local CLAVE = 131072

-- Cajas por modelo 3D (en coordenadas de cada pieza), una vez.
local cajasModelo = setmetatable({}, { __mode = 'k' })

local function cajaVacia()
    return { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
end

--- Amplía la caja `c` con los vértices de la malla `malla`, desplazados (dx, dy, dz).
local function ampliar(c, malla, dx, dy, dz)
    for i = 1, malla:getVertexCount() do
        local x, y, z = malla:getVertex(i)
        x, y, z = x + dx, y + dy, z + dz
        c[1] = math.min(c[1], x)
        c[2] = math.max(c[2], x)
        c[3] = math.min(c[3], y)
        c[4] = math.max(c[4], y)
        c[5] = math.min(c[5], z)
        c[6] = math.max(c[6], z)
    end
end

--- Cajas del modelo de vértices `modelo` (Modelos3d.modelo) para `tipo`.
function Cuerpos.cajasDe(modelo, tipo)
    local cajas = cajasModelo[modelo]
    if cajas then
        return cajas
    end
    local piezas = modelo.piezas
    cajas = {}
    if tipo == 'tanque' then
        for _, nombre in ipairs({ 'casco', 'torreta', 'canon' }) do
            local c = cajaVacia()
            ampliar(c, piezas[nombre].malla, 0, 0, 0)
            cajas[nombre] = c
        end
    else
        local c = cajaVacia()
        ampliar(c, piezas.chasis.malla, 0, 0, 0)
        for nombre, p in pairs(piezas) do
            if nombre:sub(1, 5) == 'rueda' then
                -- El camión de 4 misiles lleva pivotes relativos a la
                -- suspensión: el del chasis es `pivoteAbsoluto`.
                local pivote = p.pivoteAbsoluto or p.pivote
                ampliar(c, p.malla, pivote[1], pivote[2], pivote[3])
            end
        end
        cajas.chasis = c
        local k = cajaVacia()
        ampliar(k, piezas.contenedor.malla, 0, 0, 0)
        cajas.contenedor = k
    end
    cajasModelo[modelo] = cajas
    return cajas
end

local function copiar(m, salida)
    for i = 1, 16 do
        salida[i] = m[i]
    end
    return salida
end

--- Radio de la esfera que envuelve la caja `c` desde el origen de su pieza.
local function radioCaja(c)
    local x = math.max(math.abs(c[1]), math.abs(c[2]))
    local y = math.max(math.abs(c[3]), math.abs(c[4]))
    local z = math.max(math.abs(c[5]), math.abs(c[6]))
    return math.sqrt(x * x + y * y + z * z)
end

function Cuerpos.nuevos(tropas)
    local self = setmetatable({}, Cuerpos)
    self.tropas = tropas
    self.celdas = {}
    self.usadas = {}
    self.marca = 0
    self.lista = {}
    self.edificio = Cuerpos.edificioDe(tropas.suelo)
    return self
end

--- Cuerpo del edificio del sitio (o nil): cajas alineadas con los ejes.
function Cuerpos.edificioDe(suelo)
    local s = suelo.sitio
    if not s then
        return nil
    end
    local z = suelo:altura(s.x, s.y)
    local piezas = {}
    local function caja(nombre, medio, alto, z0)
        local m = { 1, 0, 0, s.x, 0, 1, 0, s.y, 0, 0, 1, z + z0, 0, 0, 0, 1 }
        piezas[#piezas + 1] = { nombre = nombre, m = m, caja = { -medio, medio, -medio, medio, 0, alto } }
    end
    if s.tipo == 'ciudad' then
        local t = Ciudades.torre
        caja('base', t.base / 2, t.altoBase, 0)
        caja('fuste', t.fuste / 2, t.alto + t.altoCorona - t.altoBase, t.altoBase)
    else
        caja('losa', suelo:radioEdificio() * 0.6, 50, 0)
    end
    local radio = suelo:radioEdificio() * 1.5 + 100
    return { edificio = true, vigente = true, x = s.x, y = s.y, radio = radio, piezas = piezas }
end

local NOMBRES_TANQUE = { 'casco', 'torreta', 'canon' }
local NOMBRES_CAMION = { 'chasis', 'contenedor' }
local matricesTrabajo = {}

--- Cuerpo de la unidad `u` para este paso (se reutiliza la tabla): solo
-- su centro y su radio. Las cajas se colocan al probar un rayo que pasa
-- cerca (`preparar`): la mayoría de los cuerpos no se prueban en un paso.
function Cuerpos:cuerpoDe(u)
    local c = u.cuerpo
    if not c then
        c = { u = u, piezas = {} }
        u.cuerpo = c
        if u.tipo == 'tanque' then
            local cajas = Cuerpos.cajasDe(u.modelo3d, 'tanque')
            c.radio = radioCaja(cajas.casco) + radioCaja(cajas.canon) * 0.5
        else
            c.radio = radioCaja(Cuerpos.cajasDe(u.lanzador.modelo, 'lanzacohetes').chasis) + 20
        end
    end
    c.x, c.y = u.x, u.y
    c.vigente = false
    return c
end

--- Coloca las cajas del cuerpo `c` donde está su unidad ahora.
function Cuerpos.preparar(c)
    c.vigente = true
    local u = c.u
    local nombres, cajas
    local matrices = matricesTrabajo
    if u.tipo == 'tanque' then
        cajas = Cuerpos.cajasDe(u.modelo3d, 'tanque')
        local torreta, canon = Modelos3d.matricesTanque(u.casco, u.torreta, 0, u.modelo3d)
        nombres = NOMBRES_TANQUE
        matrices[1], matrices[2], matrices[3] = u.casco, torreta, canon
    else
        cajas = Cuerpos.cajasDe(u.lanzador.modelo, 'lanzacohetes')
        nombres = NOMBRES_CAMION
        matrices[1] = u.destruccion and u.destruccion.casco or u.casco
        matrices[2] = u.matricesLanza.contenedor
        matrices[3] = nil
    end
    for k = 1, #nombres do
        local p = c.piezas[k] or { nombre = nombres[k], m = {} }
        c.piezas[k] = p
        copiar(matrices[k], p.m)
        p.caja = cajas[nombres[k]]
    end
end

--- Rehace la rejilla con las unidades del campo (los vehículos averiados
-- también: siguen estorbando).
function Cuerpos:rehacer()
    for k = #self.usadas, 1, -1 do
        local clave = self.usadas[k]
        local lista = self.celdas[clave]
        for i = #lista, 1, -1 do
            lista[i] = nil
        end
        self.usadas[k] = nil
    end
    local n = 0
    for _, u in ipairs(self.tropas.unidades) do
        n = n + 1
        self:meter(self:cuerpoDe(u))
    end
    if self.edificio then
        self:meter(self.edificio)
    end
    self.cuantos = n
end

function Cuerpos:meter(c)
    local celda = Cuerpos.celda
    local i0, i1 = math.floor((c.x - c.radio) / celda), math.floor((c.x + c.radio) / celda)
    local j0, j1 = math.floor((c.y - c.radio) / celda), math.floor((c.y + c.radio) / celda)
    for i = i0, i1 do
        for j = j0, j1 do
            local clave = i * CLAVE + j
            local lista = self.celdas[clave]
            if not lista then
                lista = {}
                self.celdas[clave] = lista
            end
            if #lista == 0 then
                self.usadas[#self.usadas + 1] = clave
            end
            lista[#lista + 1] = c
        end
    end
end

--- Cuerpos cuyas celdas tocan el rectángulo que envuelve el segmento (con
-- `margen` px), salvo el de la unidad `salvo`, en `salida` (sin repetir).
function Cuerpos:candidatos(x0, y0, x1, y1, margen, salvo, salida)
    local celda = Cuerpos.celda
    local i0 = math.floor((math.min(x0, x1) - margen) / celda)
    local i1 = math.floor((math.max(x0, x1) + margen) / celda)
    local j0 = math.floor((math.min(y0, y1) - margen) / celda)
    local j1 = math.floor((math.max(y0, y1) + margen) / celda)
    self.marca = self.marca + 1
    local marca = self.marca
    local n = 0
    for i = i0, i1 do
        for j = j0, j1 do
            local lista = self.celdas[i * CLAVE + j]
            if lista then
                for _, c in ipairs(lista) do
                    if c.marca ~= marca and (not salvo or c.u ~= salvo) then
                        c.marca = marca
                        n = n + 1
                        salida[n] = c
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

--- Como `candidatos`, pero solo en las celdas que cruza el segmento (para
-- los largos, como una línea de fuego de 2 km): se recorren una a una.
function Cuerpos:candidatosLinea(x0, y0, x1, y1, salvo, salida)
    local celda = Cuerpos.celda
    self.marca = self.marca + 1
    local marca = self.marca
    local n = 0
    local i, j = math.floor(x0 / celda), math.floor(y0 / celda)
    local iFin, jFin = math.floor(x1 / celda), math.floor(y1 / celda)
    local dx, dy = x1 - x0, y1 - y0
    local pasoI, pasoJ = dx > 0 and 1 or -1, dy > 0 and 1 or -1
    local tMaxX, tMaxY, tDeltaX, tDeltaY = math.huge, math.huge, math.huge, math.huge
    if dx ~= 0 then
        local borde = (i + (dx > 0 and 1 or 0)) * celda
        tMaxX = (borde - x0) / dx
        tDeltaX = celda / math.abs(dx)
    end
    if dy ~= 0 then
        local borde = (j + (dy > 0 and 1 or 0)) * celda
        tMaxY = (borde - y0) / dy
        tDeltaY = celda / math.abs(dy)
    end
    local vueltas = math.abs(iFin - i) + math.abs(jFin - j) + 1
    for _ = 1, vueltas do
        local lista = self.celdas[i * CLAVE + j]
        if lista then
            for _, c in ipairs(lista) do
                if c.marca ~= marca and (not salvo or c.u ~= salvo) then
                    c.marca = marca
                    n = n + 1
                    salida[n] = c
                end
            end
        end
        if tMaxX < tMaxY then
            tMaxX = tMaxX + tDeltaX
            i = i + pasoI
        else
            tMaxY = tMaxY + tDeltaY
            j = j + pasoJ
        end
    end
    for k = n + 1, #salida do
        salida[k] = nil
    end
    return salida
end

--- Distancia² del punto (px, py) al segmento horizontal (x0, y0)-(x1, y1).
local function distanciaSegmento2(px, py, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local l2 = dx * dx + dy * dy
    local t = 0
    if l2 > 1e-9 then
        t = math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / l2))
    end
    local cx, cy = x0 + dx * t - px, y0 + dy * t - py
    return cx * cx + cy * cy
end

--- Cruce del segmento (x0, y0, z0) + t·(dx, dy, dz), t de 0 a 1, con la caja
-- `p` (matriz y caja): t de entrada, eje de la cara (1, 2 o 3), signo de su
-- normal y la dirección local, o nil.
local function cruzarCaja(p, x0, y0, z0, dx, dy, dz)
    local m, c = p.m, p.caja
    -- Inversa de un giro con traslación: Rᵀ (punto − traslación).
    local ox, oy, oz = x0 - m[4], y0 - m[8], z0 - m[12]
    local lx = m[1] * ox + m[5] * oy + m[9] * oz
    local ly = m[2] * ox + m[6] * oy + m[10] * oz
    local lz = m[3] * ox + m[7] * oy + m[11] * oz
    local ldx = m[1] * dx + m[5] * dy + m[9] * dz
    local ldy = m[2] * dx + m[6] * dy + m[10] * dz
    local ldz = m[3] * dx + m[7] * dy + m[11] * dz
    local entra, sale, eje, signo = 0, 1, 0, 0
    for a = 1, 3 do
        local o, d
        if a == 1 then
            o, d = lx, ldx
        elseif a == 2 then
            o, d = ly, ldy
        else
            o, d = lz, ldz
        end
        local minimo, maximo = c[a * 2 - 1], c[a * 2]
        if math.abs(d) < 1e-12 then
            if o < minimo or o > maximo then
                return nil
            end
        else
            local t1 = (minimo - o) / d
            local t2 = (maximo - o) / d
            local s = -1
            if t1 > t2 then
                t1, t2 = t2, t1
                s = 1
            end
            if t1 > entra then
                entra, eje, signo = t1, a, s
            end
            if t2 < sale then
                sale = t2
            end
            if entra > sale then
                return nil
            end
        end
    end
    if eje == 0 then
        -- Empieza dentro: cuenta como golpe en el acto, contra la cara más cercana.
        return 0, 3, 1, lx, ly, lz, ldx, ldy, ldz
    end
    return entra, eje, signo, lx + ldx * entra, ly + ldy * entra, lz + ldz * entra, ldx, ldy, ldz
end

--- Primer cuerpo de `lista` que cruza el segmento (x0, y0, z0)-(x1, y1, z1):
-- { cuerpo, u, pieza, t, eje, signo, lx, ly, lz (punto local), dx, dy, dz
-- (dirección local, unitaria) } en `golpe`, o nil.
function Cuerpos.cruzar(lista, x0, y0, z0, x1, y1, z1, golpe)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local mejorT = math.huge
    local encontrado = false
    for _, c in ipairs(lista) do
        local r = c.radio
        if distanciaSegmento2(c.x, c.y, x0, y0, x1, y1) <= r * r then
            if not c.vigente then
                Cuerpos.preparar(c)
            end
            for _, p in ipairs(c.piezas) do
                local t, eje, signo, lx, ly, lz, ldx, ldy, ldz = cruzarCaja(p, x0, y0, z0, dx, dy, dz)
                if t and t < mejorT then
                    mejorT = t
                    encontrado = true
                    local l = math.sqrt(ldx * ldx + ldy * ldy + ldz * ldz)
                    golpe.cuerpo, golpe.u, golpe.pieza = c, c.u, p
                    golpe.t, golpe.eje, golpe.signo = t, eje, signo
                    golpe.lx, golpe.ly, golpe.lz = lx, ly, lz
                    golpe.dx, golpe.dy, golpe.dz = ldx / l, ldy / l, ldz / l
                end
            end
        end
    end
    if not encontrado then
        return nil
    end
    golpe.x, golpe.y, golpe.z = x0 + dx * mejorT, y0 + dy * mejorT, z0 + dz * mejorT
    return golpe
end

local trabajo = {}

--- Primer cuerpo que cruza el segmento, salvo la unidad `salvo`: ver `cruzar`.
function Cuerpos:rayo(x0, y0, z0, x1, y1, z1, salvo, golpe)
    local lista
    local celda = Cuerpos.celda
    if math.abs(x1 - x0) + math.abs(y1 - y0) > celda * 4 then
        lista = self:candidatosLinea(x0, y0, x1, y1, salvo, trabajo)
    else
        lista = self:candidatos(x0, y0, x1, y1, 0, salvo, trabajo)
    end
    if #lista == 0 then
        return nil
    end
    return Cuerpos.cruzar(lista, x0, y0, z0, x1, y1, z1, golpe or {})
end

--- Cuerpos con su centro a menos de `radio` px de (x, y), en `salida`.
function Cuerpos:cerca(x, y, radio, salida)
    local lista = self:candidatos(x, y, x, y, radio + 100, nil, salida)
    local n = 0
    for _, c in ipairs(lista) do
        local dx, dy = c.x - x, c.y - y
        if dx * dx + dy * dy <= (radio + c.radio) ^ 2 then
            n = n + 1
            lista[n] = c
        end
    end
    for k = n + 1, #lista do
        lista[k] = nil
    end
    return lista
end

return Cuerpos

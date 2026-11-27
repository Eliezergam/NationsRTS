-- Dibujo de un sitio (ciudad o mina) armado con las piezas del kit
-- (batalla/sitios/plano.lua) en 3DreamEngine.
--
-- Las piezas no se dibujan una a una: se funden en mallas estáticas (lo que
-- hacen los motores con la arquitectura que no se mueve: «static
-- batching»). Niveles de detalle de cada pieza (tools/blender/kit_mina.py):
--   0  completa, con pernos y biseles (hasta `cerca`);
--   1  sin pernos ni biseles, la chapa con ondas solo por fuera (hasta `medio`);
--   2  la chapa como placa plana (hasta `lejos`);
--   3  cada edificio, una caja con su chapa y su techo.
-- Cerca del ojo, cada edificio (grupo del plano) lleva su propia malla en
-- el nivel 0, 1 o 2 que le toca por su distancia; más lejos, los grupos de
-- cada trozo de 64 m van fundidos en una malla de nivel 2 o 3. Las mallas se
-- hacen la primera vez que hacen falta (pocas por cuadro, sin tirones) y las
-- de cerca se olvidan al alejarse. Las piezas traen su tangente desde Blender.

local ffi = require('ffi')
local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')

local KitSitio = {}
KitSitio.__index = KitSitio

KitSitio.trozo = 640 -- px (64 m)
KitSitio.cerca = 280 -- px del ojo (en 3D) al edificio hasta los que va el nivel 0
KitSitio.medio = 1100 -- px hasta los que va el nivel 1
KitSitio.lejos = 1800 -- px hasta los que va el nivel 2 (luego, cajas)
-- Desde este nivel el muro del recinto va en una sola pieza por lado
-- (KitSitio:muroLejos): el 2 empieza a `medio` (110 m).
KitSitio.muroUnaPiezaDesde = 2
KitSitio.maxGrupos = 160 -- mallas de grupo (niveles 0 y 1) guardadas como mucho
KitSitio.hechurasPorCuadro = 3

-- Colores de la chapa (Plano.tonos): el verde militar de la textura y otras
-- pinturas de nave industrial, sacadas de la misma textura (su luz por el
-- color nuevo: conserva los desconchones y el óxido).
KitSitio.tonosChapa = {
    false, -- 1: el verde de la textura
    { 0.62, 0.63, 0.6 }, -- 2: gris claro
    { 0.66, 0.58, 0.44 }, -- 3: arena
    { 0.3, 0.4, 0.5 }, -- 4: azul acero
    { 0.5, 0.24, 0.16 }, -- 5: rojo óxido
}

-- Materiales de Blender -> materiales de la biblioteca de la casa.
KitSitio.materiales = {
    kitHormigon = 'baseHormigon',
    kitChapa = 'baseChapa',
    kitAcero = 'baseAcero',
    kitPersiana = 'baseAcero',
    kitPerno = 'baseAcero',
    kitNegro = 'baseAcero',
    kitAlambre = 'baseAcero',
    kitAviso = 'basePeligro',
    kitVidrio = 'baseVidrio',
    kitAsfalto = 'baseAsfalto',
    kitAcera = 'baseAcera',
    kitCesped = 'baseCesped',
    kitBordillo = 'baseHormigon',
    kitLinea = 'baseHormigon',
    kitLineaAmarilla = 'baseHormigon',
    kitGrava = 'baseHormigon',
}

-- Tono de cada material del kit sobre el de la biblioteca (el hormigón de
-- la biblioteca, a pleno sol en losas grandes, se leía casi blanco).
KitSitio.tonos = {
    kitHormigon = { 0.66, 0.64, 0.6 },
    kitNegro = { 0.12, 0.12, 0.12 },
    kitBordillo = { 0.8, 0.79, 0.76 },
    kitLinea = { 1.3, 1.3, 1.25 },
    kitLineaAmarilla = { 1.35, 1.0, 0.2 }, -- las de rodaje de la plataforma
    kitGrava = { 0.62, 0.56, 0.46 },
    kitCesped = { 0.5, 0.68, 0.38 },
}

local texturasChapa = {}

--- Albedo de la chapa repintado de `color` (una vez por color).
local function texturaChapa(k)
    if texturasChapa[k] then
        return texturasChapa[k]
    end
    local color = KitSitio.tonosChapa[k]
    local datos = love.image.newImageData('assets/base/materiales/baseChapa/albedo.jpg')
    -- Luz media de la textura, para que el color nuevo quede a su nivel.
    local suma, n = 0, 0
    datos:mapPixel(function(_, _, r, g, b, a)
        suma = suma + 0.3 * r + 0.59 * g + 0.11 * b
        n = n + 1
        return r, g, b, a
    end)
    local media = suma / n
    datos:mapPixel(function(_, _, r, g, b, a)
        local l = (0.3 * r + 0.59 * g + 0.11 * b) / media
        return math.min(1, color[1] * l), math.min(1, color[2] * l), math.min(1, color[3] * l), a
    end)
    local imagen = love.graphics.newImage(datos, { mipmaps = true })
    imagen:setWrap('repeat', 'repeat')
    imagen:setFilter('linear', 'linear', 8)
    texturasChapa[k] = imagen
    return imagen
end

local materialesKit = setmetatable({}, { __mode = 'k' })

--- Material de 3Dream de un material del kit (copia del de la biblioteca,
-- con su tono).
function KitSitio.material(dream, nombre)
    local porDream = materialesKit[dream]
    if not porDream then
        porDream = {}
        materialesKit[dream] = porDream
    end
    local m = porDream[nombre]
    if not m then
        -- 'kitChapa#3': la chapa del color 3.
        local raiz, k = nombre:match('^(.-)#(%d+)$')
        raiz = raiz or nombre
        local base = dream.materialLibrary[KitSitio.materiales[raiz] or raiz] or dream.materialLibrary.baseAcero
        m = base
        local tono = KitSitio.tonos[raiz]
        if tono then
            m = base:clone()
            m:setColor(tono[1], tono[2], tono[3], 1)
        end
        k = tonumber(k)
        if k and KitSitio.tonosChapa[k] then
            m = base:clone()
            m:setAlbedoTexture(texturaChapa(k))
        end
        porDream[nombre] = m
    end
    return m
end

-- Piezas que los niveles 1 y 2 no llevan (no se ven desde fuera): las
-- losas (el suelo, una placa por edificio).
local SIN_LEJOS = { losa = true }

local datosPieza = {}

local function pieza(nombre)
    local d = datosPieza[nombre]
    if not d then
        d = love.filesystem.load('assets/batalla/kit/' .. nombre .. '.lua')()
        datosPieza[nombre] = d
    end
    return d
end

--- Acumulador por material: las piezas (sus datos y dónde van) y las cajas
-- sueltas; al final se cuentan los vértices y se escriben de una vez en los
-- búferes de la malla (sin tablas intermedias).
local Lote = {}
Lote.__index = Lote

local function nuevoLote()
    return setmetatable({ porMaterial = {} }, Lote)
end

function Lote:lista(material)
    local l = self.porMaterial[material]
    if not l then
        l = { vertices = 0, piezas = {}, sueltos = {} }
        self.porMaterial[material] = l
    end
    return l
end

--- Una pieza (`datos`: 12 números por vértice, m, y arriba) girada `giro` y
-- puesta en (x, y, z) px.
function Lote:pieza(material, datos, x, y, z, giro)
    local l = self:lista(material)
    l.piezas[#l.piezas + 1] = { datos, x, y, z, giro }
    l.vertices = l.vertices + #datos / 12
end

--- Caja girada: centro (cx, cy) px, medios lados (hx, hy) px, giro `ang`,
-- de z0 a z1 px; UV en metros (`metros` por repetición). Sin la cara de
-- abajo (ni la de arriba con `sinArriba`).
function Lote:cajaGirada(material, cx, cy, hx, hy, ang, z0, z1, metros, sinArriba)
    local l = self:lista(material)
    local c, s = math.cos(ang), math.sin(ang)
    local m = metros or 2
    local h0, h1 = z0 * 0.1, z1 * 0.1
    local alto = h1 - h0
    local datos = {}
    -- Esquinas en m (x, z de Dream = x, y del juego).
    local function p(u, v)
        return (cx + u * c - v * s) * 0.1, (cy + u * s + v * c) * 0.1
    end
    local function quad(a, b, nx, nz, tx, tz, largo, arriba)
        -- Cara vertical de la arista a -> b (en planta), o la de arriba.
        local q
        if arriba then
            q = arriba
        else
            q = {
                { a[1], h0, a[2], 0, 0 },
                { b[1], h0, b[2], largo, 0 },
                { b[1], h1, b[2], largo, alto },
                { a[1], h1, a[2], 0, alto },
            }
        end
        for _, i in ipairs({ 1, 2, 3, 1, 3, 4 }) do
            local v = q[i]
            local n = #datos
            datos[n + 1], datos[n + 2], datos[n + 3] = v[1], v[2], v[3]
            datos[n + 4], datos[n + 5], datos[n + 6] = nx, arriba and 1 or 0, nz
            datos[n + 7], datos[n + 8] = v[4] / m, -v[5] / m
            datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = tx, 0, tz, 1
        end
    end
    local A = { p(-hx, -hy) }
    local B = { p(hx, -hy) }
    local C = { p(hx, hy) }
    local D = { p(-hx, hy) }
    local lx, ly = 2 * hx * 0.1, 2 * hy * 0.1
    quad(D, C, -s, c, c, s, lx) -- +v (la fachada «s» del marco)
    quad(B, A, s, -c, -c, -s, lx) -- -v
    quad(C, B, c, s, -s, c, ly) -- +u
    quad(A, D, -c, -s, s, -c, ly) -- -u
    if not sinArriba then
        quad(nil, nil, 0, 0, c, s, 0, {
            { D[1], h1, D[2], D[1], -D[2] },
            { C[1], h1, C[2], C[1], -C[2] },
            { B[1], h1, B[2], B[1], -B[2] },
            { A[1], h1, A[2], A[1], -A[2] },
        })
    end
    l.sueltos[#l.sueltos + 1] = datos
    l.vertices = l.vertices + #datos / 12
end

--- Muro continuo (px): una cinta por los puntos `puntos` ({ x, y, z } de
-- su pie, en orden), de `grosor` y `alto` px, con sus dos caras y el canto
-- de arriba. Caras planas por tramo; la UV corre seguida a lo largo (en
-- metros, `metros` por repetición), sin empezar de nuevo en cada panel.
function Lote:cinta(material, puntos, grosor, alto, metros)
    local l = self:lista(material)
    local m = metros or 2.5
    local medio = grosor / 2
    local datos = {}
    local function vertice(x, y, z, u, v, nx, ny, nz, tx, tz)
        local n = #datos
        datos[n + 1], datos[n + 2], datos[n + 3] = x * 0.1, z * 0.1, y * 0.1
        datos[n + 4], datos[n + 5], datos[n + 6] = nx, ny, nz
        datos[n + 7], datos[n + 8] = u / m, -v / m
        datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = tx, 0, tz, 1
    end
    local recorrido = 0
    for k = 1, #puntos - 1 do
        local a, b = puntos[k], puntos[k + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local largo = math.sqrt(dx * dx + dy * dy)
        if largo > 0.01 then
            local cx, cy = dx / largo, dy / largo
            local nx, ny = -cy, cx
            local u0, u1 = recorrido * 0.1, (recorrido + largo) * 0.1
            local altoA, altoB = alto * 0.1, alto * 0.1
            for _, lado in ipairs({ 1, -1 }) do
                local ox, oy = nx * medio * lado, ny * medio * lado
                local q = {
                    { a.x + ox, a.y + oy, a.z, u0, 0 },
                    { b.x + ox, b.y + oy, b.z, u1, 0 },
                    { b.x + ox, b.y + oy, b.z + alto, u1, altoB },
                    { a.x + ox, a.y + oy, a.z + alto, u0, altoA },
                }
                local orden = lado == 1 and { 1, 2, 3, 1, 3, 4 } or { 1, 3, 2, 1, 4, 3 }
                for _, i in ipairs(orden) do
                    local v = q[i]
                    vertice(v[1], v[2], v[3], v[4], v[5], nx * lado, 0, ny * lado, cx, cy)
                end
            end
            -- Canto de arriba.
            local q = {
                { a.x - nx * medio, a.y - ny * medio, a.z + alto },
                { b.x - nx * medio, b.y - ny * medio, b.z + alto },
                { b.x + nx * medio, b.y + ny * medio, b.z + alto },
                { a.x + nx * medio, a.y + ny * medio, a.z + alto },
            }
            for _, i in ipairs({ 1, 2, 3, 1, 3, 4 }) do
                local v = q[i]
                vertice(v[1], v[2], v[3], v[1] * 0.1, v[2] * 0.1, 0, 1, 0, 1, 0)
            end
            recorrido = recorrido + largo
        end
    end
    l.sueltos[#l.sueltos + 1] = datos
    l.vertices = l.vertices + #datos / 12
end

--- Caja alineada con los ejes (px).
function Lote:caja(material, x0, y0, x1, y1, z0, z1, metros, sinArriba)
    self:cajaGirada(material, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0, z0, z1, metros, sinArriba)
end

--- Mallas de 3Dream (una por material). Posiciones relativas al centro
-- (cx, cy) de la batalla, en unidades de Dream (1 = 10 m).
function Lote:mallas(dream, cx, cy)
    local resultado = {}
    local triangulos = 0
    local ocx, ocy = cx * 0.1, cy * 0.1
    for nombre, l in pairs(self.porMaterial) do
        local cantidad = l.vertices
        if cantidad >= 3 then
            local material = KitSitio.material(dream, nombre)
            local malla = dream:newMesh(material)
            malla:setPixelShader('textured')
            malla.vertices = dream:newBuffer('vec3', 'float', cantidad)
            malla.normals = dream:newBuffer('vec3', 'float', cantidad)
            malla.texCoords = dream:newBuffer('vec2', 'float', cantidad)
            malla.tangents = dream:newBuffer('vec4', 'float', cantidad)
            malla.faces = dream:newBuffer('vec3', 'uint32_t', cantidad / 3)
            local vs, ns, uvs, ts = malla.vertices.buffer, malla.normals.buffer, malla.texCoords.buffer, malla.tangents.buffer
            local k = 0
            for _, p in ipairs(l.piezas) do
                local datos, giro = p[1], p[5]
                local c, s = math.cos(giro), math.sin(giro)
                local ox, oy, oz = p[2] * 0.1 - ocx, p[4] * 0.1, p[3] * 0.1 - ocy
                for o = 1, #datos, 12 do
                    local X, Z = datos[o], datos[o + 2]
                    vs[k].x = (ox + X * c - Z * s) * 0.1
                    vs[k].y = (oy + datos[o + 1]) * 0.1
                    vs[k].z = (oz + X * s + Z * c) * 0.1
                    local nx, nz = datos[o + 3], datos[o + 5]
                    ns[k].x, ns[k].y, ns[k].z = nx * c - nz * s, datos[o + 4], nx * s + nz * c
                    uvs[k].x, uvs[k].y = datos[o + 6], datos[o + 7]
                    local tx, tz = datos[o + 8], datos[o + 10]
                    ts[k].x, ts[k].y, ts[k].z, ts[k].w = tx * c - tz * s, datos[o + 9], tx * s + tz * c, datos[o + 11]
                    k = k + 1
                end
            end
            for _, datos in ipairs(l.sueltos) do
                for o = 1, #datos, 12 do
                    vs[k].x = (datos[o] - ocx) * 0.1
                    vs[k].y = datos[o + 1] * 0.1
                    vs[k].z = (datos[o + 2] - ocy) * 0.1
                    ns[k].x, ns[k].y, ns[k].z = datos[o + 3], datos[o + 4], datos[o + 5]
                    uvs[k].x, uvs[k].y = datos[o + 6], datos[o + 7]
                    ts[k].x, ts[k].y, ts[k].z, ts[k].w = datos[o + 8], datos[o + 9], datos[o + 10], datos[o + 11]
                    k = k + 1
                end
            end
            local caras = malla.faces.buffer
            for f = 0, cantidad / 3 - 1 do
                caras[f].x, caras[f].y, caras[f].z = f * 3 + 1, f * 3 + 2, f * 3 + 3
            end
            malla:updateBoundingSphere()
            resultado[#resultado + 1] = malla
            triangulos = triangulos + cantidad / 3
        end
    end
    return resultado, triangulos
end

-- Sitio ------------------------------------------------------------------------------------------

function KitSitio.nuevo(dream, conversor, plano)
    if not plano then
        return nil
    end
    if not dream.materialLibrary.baseChapa then
        BibliotecaPbr.cargar(dream, 'assets/base/materiales')
    end
    local self = setmetatable({}, KitSitio)
    self.dream = dream
    self.cx, self.cy = conversor.cx, conversor.cy
    self.plano = plano
    self.trozos = {}
    self.conMalla = 0 -- grupos con malla propia (niveles 0 y 1)
    self.reloj = 0
    local t = KitSitio.trozo
    for _, g in ipairs(plano.grupos) do
        local i, j = math.floor((g[1] + g[3]) / 2 / t), math.floor((g[2] + g[4]) / 2 / t)
        local k = i * 131072 + j
        local tr = self.trozos[k]
        if not tr then
            tr = { i = i, j = j, x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge, z = math.huge, grupos = {}, niveles = {} }
            self.trozos[k] = tr
        end
        tr.grupos[#tr.grupos + 1] = g
        tr.x0, tr.y0 = math.min(tr.x0, g[1]), math.min(tr.y0, g[2])
        tr.x1, tr.y1 = math.max(tr.x1, g[3]), math.max(tr.y1, g[4])
        tr.z = math.min(tr.z, g[5])
        g.niveles = {}
    end
    -- Cimientos: siempre (pocos triángulos), en una malla aparte.
    local base = nuevoLote()
    for _, c in ipairs(plano.cimientos) do
        base:cajaGirada('kitHormigon', c.cx, c.cy, c.hx, c.hy, c.ang, c.z0, c.z1, 2.5)
    end
    self.base = base:mallas(dream, self.cx, self.cy)
    -- Calles de la ciudad (batalla/dream/calles_malla.lua), por trozos.
    self.calles = {}
    if plano.vias then
        for _, tr in pairs(require('batalla.dream.calles_malla').hacer(plano.vias)) do
            local lote = nuevoLote()
            for material, datos in pairs(tr.datos) do
                local l = lote:lista(material)
                l.sueltos[#l.sueltos + 1] = datos
                l.vertices = l.vertices + #datos / 12
            end
            tr.mallas = lote:mallas(dream, self.cx, self.cy)
            tr.datos = nil
            self.calles[#self.calles + 1] = tr
        end
    end
    -- Dentro del muro (el dueño, 19-nov: «lo de dentro de las minas, una vez
    -- generado, que no se vuelva a dibujar distinto»): los edificios nunca
    -- bajan del nivel 1; su malla de nivel 1 se hace aquí, una vez, y no se
    -- olvida. Los niveles 2 y 3 de cada trozo llevan solo el muro.
    for _, tr in pairs(self.trozos) do
        tr.muro = {}
        tr.interior = {}
        for _, g in ipairs(tr.grupos) do
            if g.edificio then
                tr.interior[#tr.interior + 1] = g
                g.niveles[1] = self:hacer({ g }, 1)
                g.fijo = true
            else
                tr.muro[#tr.muro + 1] = g
            end
        end
        tr.niveles[3] = self:hacer(tr.muro, 3)
    end
    return self
end

--- Añade al lote los grupos en el nivel `n`.
function KitSitio:llenar(lote, grupos, n)
    for _, g in ipairs(grupos) do
        local e = g.edificio
        local chapa = g.tono and g.tono > 1 and ('kitChapa#' .. g.tono) or 'kitChapa'
        if n == 3 then
            if e and e.patio then
                lote:cajaGirada('kitHormigon', e.cx, e.cy, e.hx, e.hy, e.ang, e[5] - 3, e[5], 2.5)
            elseif e then
                lote:cajaGirada(chapa, e.cx, e.cy, e.hx, e.hy, e.ang, e[5], e[5] + e[6] - 4, 2, true)
                lote:cajaGirada(chapa, e.cx, e.cy, e.hx, e.hy, e.ang, e[5] + e[6] - 4, e[5] + e[6] - 2, 2)
            else
                self:muroLejos(lote, g)
            end
        elseif n >= KitSitio.muroUnaPiezaDesde and not e and g.piezas.muroRecinto then
            self:muroLejos(lote, g)
        else
            for nombre, lista in pairs(g.piezas) do
                if n == 0 or not SIN_LEJOS[nombre] then
                    local d = pieza(nombre)[n + 1]
                    for material, datos in pairs(d) do
                        local m = material == 'kitChapa' and chapa or material
                        for _, p in ipairs(lista) do
                            lote:pieza(m, datos, p[1], p[2], p[3], p[4])
                        end
                    end
                end
            end
            if n > 0 and e and e.patio then
                -- Patio sin losas: una placa de hormigón.
                lote:cajaGirada('kitHormigon', e.cx, e.cy, e.hx, e.hy, e.ang, e[5] - 3, e[5], 2.5)
            end
        end
    end
end

--- Tramo del recinto de lejos (el dueño, 19-nov: «de lejos una valla se ve
-- como una sola pieza»; lo que hacen los motores con su HLOD): los paneles
-- seguidos de cada lado van fundidos en una sola cinta de hormigón, que
-- sigue el suelo en cada junta. El portón, su caja de acero.
function KitSitio:muroLejos(lote, g)
    local paneles = {}
    for _, p in ipairs(g.piezas.muroRecinto or {}) do
        paneles[#paneles + 1] = p
    end
    -- Por dirección y, en cada una, en orden a lo largo.
    local porGiro = {}
    for _, p in ipairs(paneles) do
        local clave = math.floor(((p[4] % (2 * math.pi)) * 100) + 0.5)
        porGiro[clave] = porGiro[clave] or {}
        table.insert(porGiro[clave], p)
    end
    for _, lista in pairs(porGiro) do
        local c, s = math.cos(lista[1][4]), math.sin(lista[1][4])
        table.sort(lista, function(a, b)
            return a[1] * c + a[2] * s < b[1] * c + b[2] * s
        end)
        local tramo = nil
        local function cerrar()
            if tramo and #tramo >= 2 then
                lote:cinta('kitHormigon', tramo, 2.4, 32, 2.5)
            end
            tramo = nil
        end
        for k, p in ipairs(lista) do
            local ex, ey = p[1] + c * 40, p[2] + s * 40
            local anterior = lista[k - 1]
            local seguido = anterior and math.abs(anterior[1] + c * 40 - p[1]) + math.abs(anterior[2] + s * 40 - p[2]) < 5
            if not seguido then
                cerrar()
                tramo = { { x = p[1], y = p[2], z = p[3] - 2 } }
            else
                -- Junta: entre las dos alturas (el pie, un poco enterrado).
                local j = tramo[#tramo]
                j.z = math.min(j.z, p[3] - 2)
            end
            tramo[#tramo + 1] = { x = ex, y = ey, z = p[3] - 2 }
        end
        cerrar()
    end
    for _, p in ipairs(g.piezas.portonRecinto or {}) do
        local c, s = math.cos(p[4]), math.sin(p[4])
        local x1, y1 = p[1] + c * 40, p[2] + s * 40
        local ax, bx = math.min(p[1], x1) - math.abs(s) * 1.2, math.max(p[1], x1) + math.abs(s) * 1.2
        local ay, by = math.min(p[2], y1) - math.abs(c) * 1.2, math.max(p[2], y1) + math.abs(c) * 1.2
        lote:caja('kitAcero', ax, ay, bx, by, p[3], p[3] + 28, 1)
    end
end

--- Mallas de los `grupos` en el nivel `n`.
function KitSitio:hacer(grupos, n)
    local lote = nuevoLote()
    self:llenar(lote, grupos, n)
    local mallas, tri = lote:mallas(self.dream, self.cx, self.cy)
    mallas.triangulos = tri
    return mallas
end

--- ¿Se ve el rectángulo `r` (con su alto) desde el ojo mirando hacia
-- (dx, dy, dz) (normalizado)? Cono de `KitSitio.mediaVista` más el ángulo
-- que ocupa el propio grupo; lo que está encima del ojo, siempre.
KitSitio.mediaVista = math.rad(62)

local function seVe(r, ox, oy, oz, dx, dy, dz)
    local cx, cy = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
    local cz = (r[5] or r.z or 0) + 100
    local vx, vy, vz = cx - ox, cy - oy, cz - oz
    local d = math.sqrt(vx * vx + vy * vy + vz * vz)
    local radio = math.sqrt((r[3] - r[1]) ^ 2 + (r[4] - r[2]) ^ 2) / 2 + 150
    if d <= radio then
        return true
    end
    local coseno = (vx * dx + vy * dy + vz * dz) / d
    local angulo = math.acos(math.max(-1, math.min(1, coseno)))
    return angulo < KitSitio.mediaVista + math.asin(math.min(1, radio / d))
end

local function distancia(r, x, y, z)
    local dx = math.max(r[1] - x, 0, x - r[3])
    local dy = math.max(r[2] - y, 0, y - r[4])
    local dz = math.max(0, z - (r[5] or r.z or 0))
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Elige el nivel de cada trozo y de cada edificio cercano por la distancia
-- del ojo (px) y dibuja.
function KitSitio:dibujar(ojoX, ojoY, ojoZ, miraX, miraY, miraZ)
    local dream = self.dream
    ojoZ = ojoZ or 0
    -- Hacia dónde mira la cámara: solo se hace y se dibuja lo que cae en la
    -- vista (el dueño, 19-nov: «que solo se dibuje donde enfoca la cámara»).
    local fx, fy, fz = (miraX or ojoX + 1) - ojoX, (miraY or ojoY) - ojoY, (miraZ or ojoZ) - ojoZ
    local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / fl, fy / fl, fz / fl
    self.reloj = self.reloj + 1
    for _, m in ipairs(self.base) do
        dream:draw(m)
    end
    local hechuras = KitSitio.hechurasPorCuadro
    local triangulos = 0
    for _, tr in ipairs(self.calles) do
        -- (Margen de 60 m: los cruces y glorietas salen de su trozo.)
        if seVe({ tr.x0 - 600, tr.y0 - 600, tr.x1 + 600, tr.y1 + 600, tr.z }, ojoX, ojoY, ojoZ, fx, fy, fz) then
            for _, m in ipairs(tr.mallas) do
                dream:draw(m)
            end
        end
    end
    for _, tr in pairs(self.trozos) do
        local rTrozo = { tr.x0, tr.y0, tr.x1, tr.y1, tr.z }
        local dTrozo = distancia(rTrozo, ojoX, ojoY, ojoZ)
        if not seVe(rTrozo, ojoX, ojoY, ojoZ, fx, fy, fz) then
            -- Fuera de la vista: nada.
        elseif dTrozo < KitSitio.medio then
            -- Cerca: cada grupo con su nivel (0, 1 o 2).
            for _, g in ipairs(tr.grupos) do
                local d = distancia(g, ojoX, ojoY, ojoZ)
                if seVe(g, ojoX, ojoY, ojoZ, fx, fy, fz) then
                local quiere = d < KitSitio.cerca and 0 or ((d < KitSitio.medio or g.fijo) and 1 or 2)
                if not g.niveles[quiere] and hechuras > 0 then
                    g.niveles[quiere] = self:hacer({ g }, quiere)
                    hechuras = hechuras - 1
                    if quiere < 2 then
                        self.conMalla = self.conMalla + 1
                    end
                end
                local nivel = quiere
                while nivel <= 2 and not g.niveles[nivel] do
                    nivel = nivel + 1
                end
                if nivel > 2 then
                    -- Aún sin malla propia: un nivel 2 al momento (es barato).
                    g.niveles[2] = self:hacer({ g }, 2)
                    nivel = 2
                end
                g.usado = self.reloj
                for _, m in ipairs(g.niveles[nivel]) do
                    dream:draw(m)
                end
                triangulos = triangulos + (g.niveles[nivel].triangulos or 0)
                end
            end
        else
            -- Los edificios, cada uno en su nivel 1 (hecho al cargar).
            for _, g in ipairs(tr.interior) do
                if seVe(g, ojoX, ojoY, ojoZ, fx, fy, fz) then
                    for _, m in ipairs(g.niveles[1]) do
                        dream:draw(m)
                    end
                    triangulos = triangulos + (g.niveles[1].triangulos or 0)
                end
            end
            -- El muro, fundido por trozo.
            local quiere = dTrozo < KitSitio.lejos and 2 or 3
            if not tr.niveles[quiere] and hechuras > 0 then
                tr.niveles[quiere] = self:hacer(tr.muro, quiere)
                hechuras = hechuras - 1
            end
            local nivel = tr.niveles[quiere] and quiere or 3
            for _, m in ipairs(tr.niveles[nivel]) do
                dream:draw(m)
            end
            triangulos = triangulos + (tr.niveles[nivel].triangulos or 0)
        end
    end
    self.triangulos = triangulos
    -- Olvidar las mallas de cerca de los grupos que llevan tiempo sin usarse.
    if self.conMalla > KitSitio.maxGrupos then
        for _, tr in pairs(self.trozos) do
            for _, g in ipairs(tr.grupos) do
                if (g.usado or 0) < self.reloj - 30 and (g.niveles[0] or g.niveles[1]) then
                    if g.niveles[0] then
                        g.niveles[0] = nil
                        self.conMalla = self.conMalla - 1
                    end
                    if g.niveles[1] and not g.fijo then
                        g.niveles[1] = nil
                        self.conMalla = self.conMalla - 1
                    end
                end
            end
        end
    end
end

return KitSitio

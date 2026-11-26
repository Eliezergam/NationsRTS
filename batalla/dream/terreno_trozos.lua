-- Terreno de la batalla por trozos con niveles de detalle (Valeria).
--
-- La rejilla del suelo (batalla/suelo.lua) se parte en trozos de `cuadros`
-- cuadros por lado. Cada trozo tiene, ya hechas al cargar, una malla por
-- nivel: la rejilla entera (nivel 1, la misma malla de siempre: mismos
-- vértices, colores y normales) y versiones que toman un vértice de cada 2,
-- 4, 8 y 16 (geomipmapping). Al cargar se mide el error de cada nivel: lo que
-- más se aparta su superficie (o su color, con `pesoColor`) de la rejilla
-- entera. En cada cuadro, cada trozo usa el nivel más sencillo cuyo error,
-- proyectado en la pantalla a su distancia, no pasa de `tolerancia` px.
--
-- Sin costuras: cada malla lleva un faldón vertical en su borde, que baja más
-- que lo que puede separarse de sus vecinos con otro nivel. Desde arriba
-- nunca se ve un hueco entre trozos.
--
-- Solo se dibuja lo que la cámara ve, con un margen de `margenGiro` a cada
-- lado, y además lo que está a menos de `alcanceSombra` (las cascadas del
-- sol no recortan: necesitan el terreno de alrededor, también el de detrás).
-- Las mallas están todas en memoria: al girar no hay nada que generar.

local ffi = require('ffi')
local Conversor = require('batalla.dream.conversor')
local TerrenoPBR = require('batalla.dream.terreno_pbr')

local TerrenoTrozos = {}
TerrenoTrozos.__index = TerrenoTrozos

TerrenoTrozos.cuadros = 64 -- cuadros de la rejilla por lado de un trozo
TerrenoTrozos.pasos = { 1, 2, 4, 8, 16 }
TerrenoTrozos.tolerancia = 2 -- px de pantalla (a 1080 de alto) que puede apartarse un nivel
TerrenoTrozos.pesoColor = 25 -- px de error por unidad de diferencia de color (sRGB de 0 a 1)
TerrenoTrozos.pesoOrilla = 4 -- el error de altura cuenta por tanto cerca del nivel del mar (mueve la costa)
TerrenoTrozos.orilla = 40 -- px sobre o bajo el mar en los que se aplica `pesoOrilla`
TerrenoTrozos.histeresis = 0.7 -- un trozo pasa a un nivel más sencillo con este margen
TerrenoTrozos.campo = math.rad(40) -- campo vertical de la cámara de la batalla
TerrenoTrozos.margenGiro = math.rad(25) -- grados de más a cada lado del recorte
TerrenoTrozos.normalSuave = 0.7 -- la mezcla de normales de Suelo.normalSuave

-- Trozo y nivel ------------------------------------------------------------------------------

--- Líneas (índices) del nivel de paso `paso` entre `desde` y `hasta`: una de
-- cada `paso`, y siempre la última (el borde del trozo).
local function lineasNivel(desde, hasta, paso)
    local lineas = {}
    for i = desde, hasta, paso do
        lineas[#lineas + 1] = i
    end
    if lineas[#lineas] ~= hasta then
        lineas[#lineas + 1] = hasta
    end
    return lineas
end

--- Error (px) del nivel de líneas `is`, `js` en el trozo: lo más que se
-- aparta un vértice de la rejilla de su triángulo del nivel, en altura o en
-- color. Interpola en el espacio de índices (los mismos triángulos).
local function errorNivel(rej, is, js, nivelMar)
    local lado = rej.lado
    local h, cr, cg, cb = rej.h, rej.cr, rej.cg, rej.cb
    local peso = TerrenoTrozos.pesoColor
    local orilla, pesoOrilla = TerrenoTrozos.orilla, TerrenoTrozos.pesoOrilla
    local alto, color = 0, 0
    for qj = 1, #js - 1 do
        local j0, j1 = js[qj], js[qj + 1]
        for qi = 1, #is - 1 do
            local i0, i1 = is[qi], is[qi + 1]
            local a, b = j0 * lado + i0, j0 * lado + i1
            local c, d = j1 * lado + i0, j1 * lado + i1
            local par = (qi + qj) % 2 == 0
            for j = j0, j1 do
                local v = (j - j0) / (j1 - j0)
                for i = i0, i1 do
                    local u = (i - i0) / (i1 - i0)
                    -- Pesos de a, b, c, d en el triángulo que contiene (u, v).
                    local wa, wb, wc, wd
                    if par then
                        -- Diagonal a-d: a-b-d (u >= v) y a-d-c.
                        if u >= v then
                            wa, wb, wc, wd = 1 - u, u - v, 0, v
                        else
                            wa, wb, wc, wd = 1 - v, 0, v - u, u
                        end
                    else
                        -- Diagonal b-c: a-b-c (u + v <= 1) y b-d-c.
                        if u + v <= 1 then
                            wa, wb, wc, wd = 1 - u - v, u, v, 0
                        else
                            wa, wb, wc, wd = 0, 1 - v, 1 - u, u + v - 1
                        end
                    end
                    local k = j * lado + i
                    local eh = h[a] * wa + h[b] * wb + h[c] * wc + h[d] * wd - h[k]
                    local er = cr[a] * wa + cr[b] * wb + cr[c] * wc + cr[d] * wd - cr[k]
                    local eg = cg[a] * wa + cg[b] * wb + cg[c] * wc + cg[d] * wd - cg[k]
                    local eb = cb[a] * wa + cb[b] * wb + cb[c] * wc + cb[d] * wd - cb[k]
                    -- Cerca del mar, un error pequeño mueve la línea de costa.
                    if math.abs(h[k] - nivelMar) < orilla then
                        eh = eh * pesoOrilla
                    end
                    alto = math.max(alto, math.abs(eh))
                    color = math.max(color, math.abs(er), math.abs(eg), math.abs(eb))
                end
            end
        end
    end
    return alto, color * peso
end

-- Mallas ---------------------------------------------------------------------------------------

--- Escritor de vértices del juego (px, z arriba) en el formato del suelo
-- PBR (batalla/dream/terreno_pbr.lua): posición de 3Dream (y arriba, centrada
-- y a escala), normal y color lineal en bytes, y los pesos de las capas.
local Escritor = {}
Escritor.__index = Escritor

function Escritor.nuevo(cantidad, cx, cy)
    local datos, v = TerrenoPBR.datos(cantidad)
    return setmetatable({ n = 0, cx = cx, cy = cy, datos = datos, v = v }, Escritor)
end

local function byte(x)
    return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5)
end

--- Vértice con `pesos[o .. o + 11]` (bytes de Suelo.guardarPesos).
function Escritor:vertice(x, y, z, nx, ny, nz, r, g, b, pesos, o)
    local v = self.v[self.n]
    local escala = Conversor.escala
    v.VertexPositionX, v.VertexPositionY, v.VertexPositionZ = (x - self.cx) * escala, z * escala, (y - self.cy) * escala
    v.VertexNormalX, v.VertexNormalY, v.VertexNormalZ = nx * 127.5 + 127.5, nz * 127.5 + 127.5, ny * 127.5 + 127.5
    v.VertexNormalW = 0
    v.VertexColorX, v.VertexColorY, v.VertexColorZ, v.VertexColorW = byte(r ^ 2.2), byte(g ^ 2.2), byte(b ^ 2.2), 255
    v.VertexPesoAX, v.VertexPesoAY, v.VertexPesoAZ, v.VertexPesoAW = pesos[o], pesos[o + 1], pesos[o + 2], pesos[o + 3]
    v.VertexPesoBX, v.VertexPesoBY, v.VertexPesoBZ, v.VertexPesoBW = pesos[o + 4], pesos[o + 5], pesos[o + 6], pesos[o + 7]
    v.VertexPesoCX, v.VertexPesoCY, v.VertexPesoCZ, v.VertexPesoCW = pesos[o + 8], pesos[o + 9], pesos[o + 10], pesos[o + 11]
    -- Caja para la esfera envolvente.
    local px, py, pz = v.VertexPositionX, v.VertexPositionY, v.VertexPositionZ
    if self.n == 0 then
        self.x0, self.y0, self.z0, self.x1, self.y1, self.z1 = px, py, pz, px, py, pz
    else
        self.x0, self.x1 = math.min(self.x0, px), math.max(self.x1, px)
        self.y0, self.y1 = math.min(self.y0, py), math.max(self.y1, py)
        self.z0, self.z1 = math.min(self.z0, pz), math.max(self.z1, pz)
    end
    self.n = self.n + 1
end

--- Malla de 3Dream con los vértices escritos: el formato de terreno_pbr
-- recoge `datosTerreno` tal cual; los índices son seguidos (el cambio de ejes
-- invierte el giro de cada triángulo).
function Escritor:malla(dream, material)
    local malla = dream:newMesh(material)
    malla:setPixelShader('terrenoPBR')
    local n = self.n
    if n < 3 then
        return nil
    end
    -- Recorta los datos a lo escrito (los triángulos degenerados no se escriben).
    local datos = self.datos
    if n * ffi.sizeof(TerrenoPBR.estructura) < datos:getSize() then
        local recortados, puntero = TerrenoPBR.datos(n)
        ffi.copy(puntero, self.v, n * ffi.sizeof(TerrenoPBR.estructura))
        datos = recortados
    end
    malla.datosTerreno = datos
    malla.faces = true
    function malla.createVertexMap()
        local mapa = love.data.newByteData(ffi.sizeof('uint32_t') * n)
        local indices = ffi.cast('uint32_t*', mapa:getFFIPointer())
        for t = 0, n / 3 - 1 do
            indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2] = t * 3, t * 3 + 2, t * 3 + 1
        end
        return mapa
    end
    local dx, dy, dz = self.x1 - self.x0, self.y1 - self.y0, self.z1 - self.z0
    malla.boundingSphere = dream:newBoundingSphere(
        dream.vec3((self.x0 + self.x1) / 2, (self.y0 + self.y1) / 2, (self.z0 + self.z1) / 2),
        math.sqrt(dx * dx + dy * dy + dz * dz) / 2
    )
    return malla, n / 3
end

-- Terreno ---------------------------------------------------------------------------------------

--- Trozos del suelo, con el material del terreno ya hecho. `conversor` da
-- el centro de la escena. `informar(t)` (opcional) recibe la fracción hecha
-- (0 a 1).
function TerrenoTrozos.nuevo(dream, conversor, suelo, material, opciones, informar)
    opciones = opciones or {}
    local self = setmetatable({}, TerrenoTrozos)
    self.dream = dream
    self.cx, self.cy = conversor.cx, conversor.cy
    self.suelo = suelo
    self.material = material
    self.rugosidad = opciones.rugosidad or 0.92
    self.alcanceSombra = (opciones.alcanceSombra or 240) * 10
    self.trozos = {}
    local rej = suelo.relieve
    local ultimo = rej.lado - 1
    local K = TerrenoTrozos.cuadros
    local n = math.ceil(ultimo / K)
    self.n = n
    -- 1. Líneas y error de cada nivel de cada trozo.
    for tj = 0, n - 1 do
        for ti = 0, n - 1 do
            local i0, i1 = ti * K, math.min(ultimo, (ti + 1) * K)
            local j0, j1 = tj * K, math.min(ultimo, (tj + 1) * K)
            local t = { ti = ti, tj = tj, i0 = i0, i1 = i1, j0 = j0, j1 = j1, niveles = {}, nivel = 1 }
            local bajo, alto = math.huge, -math.huge
            for j = j0, j1 do
                for i = i0, i1 do
                    local h = rej.h[j * rej.lado + i]
                    bajo, alto = math.min(bajo, h), math.max(alto, h)
                end
            end
            t.x0, t.x1 = rej.xs[i0 + 1], rej.xs[i1 + 1]
            t.y0, t.y1 = rej.ys[j0 + 1], rej.ys[j1 + 1]
            t.z0, t.z1 = bajo, alto
            local maxAlto = 0
            for nivel, paso in ipairs(TerrenoTrozos.pasos) do
                if paso <= math.max(i1 - i0, j1 - j0) then
                    local is, js = lineasNivel(i0, i1, paso), lineasNivel(j0, j1, paso)
                    local errorAlto, errorColor = 0, 0
                    if paso > 1 then
                        errorAlto, errorColor = errorNivel(rej, is, js, suelo.nivelMar)
                    end
                    -- Un nivel más sencillo nunca vale menos error que el anterior.
                    local anterior = t.niveles[nivel - 1]
                    local errorTotal = math.max(errorAlto, errorColor, anterior and anterior.error or 0)
                    t.niveles[nivel] = { paso = paso, is = is, js = js, error = errorTotal, alto = errorAlto }
                    maxAlto = math.max(maxAlto, errorAlto)
                end
            end
            t.maxAlto = maxAlto
            self.trozos[#self.trozos + 1] = t
        end
        if informar then
            informar(0.4 * (tj + 1) / n)
        end
    end
    -- 2. Faldón de cada trozo: más hondo que lo que pueden separarse él y sus
    -- vecinos con cualquier nivel.
    for _, t in ipairs(self.trozos) do
        local hondo = t.maxAlto
        for dj = -1, 1 do
            for di = -1, 1 do
                local v = self:trozo(t.ti + di, t.tj + dj)
                if v then
                    hondo = math.max(hondo, v.maxAlto)
                end
            end
        end
        t.faldon = 2 * hondo + 8
    end
    -- 3. Mallas.
    local triangulos = 0
    for k, t in ipairs(self.trozos) do
        for _, nivel in ipairs(t.niveles) do
            nivel.malla, nivel.triangulos = self:mallaNivel(t, nivel)
            triangulos = triangulos + nivel.triangulos
        end
        if informar and k % 4 == 0 then
            informar(0.4 + 0.6 * k / #self.trozos)
        end
    end
    self.triangulosTotales = triangulos
    self.planos = {}
    if os.getenv('DEPURAR_TROZOS') then
        for nivel = 2, #TerrenoTrozos.pasos do
            local altos, totales = {}, {}
            for _, t in ipairs(self.trozos) do
                if t.niveles[nivel] then
                    altos[#altos + 1] = t.niveles[nivel].alto
                    totales[#totales + 1] = t.niveles[nivel].error
                end
            end
            table.sort(altos)
            table.sort(totales)
            print(
                string.format(
                    'TROZOS nivel %d: error de altura mediana %.1f px (máx %.1f), con color mediana %.1f px (máx %.1f)',
                    nivel,
                    altos[math.ceil(#altos / 2)] or 0,
                    altos[#altos] or 0,
                    totales[math.ceil(#totales / 2)] or 0,
                    totales[#totales] or 0
                )
            )
        end
    end
    return self
end

function TerrenoTrozos:trozo(ti, tj)
    if ti < 0 or tj < 0 or ti >= self.n or tj >= self.n then
        return nil
    end
    return self.trozos[tj * self.n + ti + 1]
end

--- Malla de un nivel de un trozo: sus triángulos (la diagonal alterna como
-- en Suelo:colorearTerreno) y el faldón de su borde, por las dos caras.
function TerrenoTrozos:mallaNivel(t, nivel)
    local rej = self.suelo.relieve
    local lado = rej.lado
    local px, py, ph = rej.x, rej.y, rej.h
    local vnx, vny, vnz = rej.nx, rej.ny, rej.nz
    local cr, cg, cb = rej.cr, rej.cg, rej.cb
    local pesos = rej.pesos
    local is, js = nivel.is, nivel.js
    local ni, nj = #is - 1, #js - 1
    local perimetro = 2 * (ni + nj)
    local cantidad = ni * nj * 6 + perimetro * 12
    local w = Escritor.nuevo(cantidad, self.cx, self.cy)
    local suaveN = TerrenoTrozos.normalSuave
    local planaN = 1 - suaveN

    local function vertice(k, fx, fy, fz)
        local nx = vnx[k] * suaveN + fx * planaN
        local ny = vny[k] * suaveN + fy * planaN
        local nz = vnz[k] * suaveN + fz * planaN
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        w:vertice(px[k], py[k], ph[k], nx / l, ny / l, nz / l, cr[k], cg[k], cb[k], pesos, k * 12)
    end

    local function triangulo(a, b, c)
        local ax, ay, az = px[a], py[a], ph[a]
        local ux, uy, uz = px[b] - ax, py[b] - ay, ph[b] - az
        local vx, vy, vz = px[c] - ax, py[c] - ay, ph[c] - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l < 1e-9 then
            return
        end
        if nz < 0 then
            l = -l
            b, c = c, b
        end
        nx, ny, nz = nx / l, ny / l, nz / l
        vertice(a, nx, ny, nz)
        vertice(b, nx, ny, nz)
        vertice(c, nx, ny, nz)
    end

    for qj = 1, nj do
        for qi = 1, ni do
            local a = js[qj] * lado + is[qi]
            local b = js[qj] * lado + is[qi + 1]
            local c = js[qj + 1] * lado + is[qi]
            local d = js[qj + 1] * lado + is[qi + 1]
            if (qi + qj) % 2 == 0 then
                triangulo(a, b, d)
                triangulo(a, d, c)
            else
                triangulo(a, b, c)
                triangulo(b, d, c)
            end
        end
    end

    -- Faldón: de cada tramo del borde baja una pared de `t.faldon` px, con el
    -- color y la normal de sus vértices, por las dos caras.
    local hondo = t.faldon
    local function pared(k1, k2)
        local x1, y1, z1 = px[k1], py[k1], ph[k1]
        local x2, y2, z2 = px[k2], py[k2], ph[k2]
        local n1x, n1y, n1z = vnx[k1], vny[k1], vnz[k1]
        local n2x, n2y, n2z = vnx[k2], vny[k2], vnz[k2]
        for cara = 1, 2 do
            local p = cara == 1
            w:vertice(x1, y1, z1, n1x, n1y, n1z, cr[k1], cg[k1], cb[k1], pesos, k1 * 12)
            if p then
                w:vertice(x2, y2, z2, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
                w:vertice(x2, y2, z2 - hondo, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
            else
                w:vertice(x2, y2, z2 - hondo, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
                w:vertice(x2, y2, z2, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
            end
            w:vertice(x1, y1, z1, n1x, n1y, n1z, cr[k1], cg[k1], cb[k1], pesos, k1 * 12)
            if p then
                w:vertice(x2, y2, z2 - hondo, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
                w:vertice(x1, y1, z1 - hondo, n1x, n1y, n1z, cr[k1], cg[k1], cb[k1], pesos, k1 * 12)
            else
                w:vertice(x1, y1, z1 - hondo, n1x, n1y, n1z, cr[k1], cg[k1], cb[k1], pesos, k1 * 12)
                w:vertice(x2, y2, z2 - hondo, n2x, n2y, n2z, cr[k2], cg[k2], cb[k2], pesos, k2 * 12)
            end
        end
    end
    local jBajo, jAlto = js[1], js[#js]
    local iBajo, iAlto = is[1], is[#is]
    for q = 1, ni do
        pared(jBajo * lado + is[q], jBajo * lado + is[q + 1])
        pared(jAlto * lado + is[q], jAlto * lado + is[q + 1])
    end
    for q = 1, nj do
        pared(js[q] * lado + iBajo, js[q + 1] * lado + iBajo)
        pared(js[q] * lado + iAlto, js[q + 1] * lado + iAlto)
    end
    return w:malla(self.dream, self.material)
end

--- Malla del faldón con los triángulos que apuntó Suelo:generarFaldon
-- (`suelo.faldonTriangulos`): las mismas normales mezcladas y colores, con
-- los pesos de cada anillo.
function TerrenoTrozos:mallaFaldon()
    local registro = self.suelo.faldonTriangulos
    if not registro or #registro == 0 then
        return nil
    end
    local w = Escritor.nuevo(#registro * 3, self.cx, self.cy)
    local suaveN = TerrenoTrozos.normalSuave
    local planaN = 1 - suaveN
    local function vertice(anillo, n, fx, fy, fz)
        local nx = anillo.nx[n] * suaveN + fx * planaN
        local ny = anillo.ny[n] * suaveN + fy * planaN
        local nz = anillo.nz[n] * suaveN + fz * planaN
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        w:vertice(
            anillo.x[n],
            anillo.y[n],
            anillo.h[n],
            nx / l,
            ny / l,
            nz / l,
            anillo.r[n],
            anillo.g[n],
            anillo.b[n],
            anillo.pesos,
            (n - 1) * 12
        )
    end
    for _, t in ipairs(registro) do
        vertice(t[1], t[2], t[7], t[8], t[9])
        vertice(t[3], t[4], t[7], t[8], t[9])
        vertice(t[5], t[6], t[7], t[8], t[9])
    end
    local malla = w:malla(self.dream, self.material)
    -- Empieza a 1,5 km: fuera de las cascadas del sol.
    malla:setShadowVisibility(false)
    return malla
end

-- Cada cuadro -----------------------------------------------------------------------------------

--- Planos del frustum (px del juego, normalizados) de la matriz de vista y
-- proyección `m` (por filas), sin el lejano: como VegetacionDream:actualizarPlanos.
function TerrenoTrozos:actualizarPlanos(m)
    local planos = self.planos
    local k = 0
    for fila = 0, 2 do
        for _, signo in ipairs({ 1, -1 }) do
            if not (fila == 2 and signo == -1) then
                local a = m[13] + signo * m[fila * 4 + 1]
                local b = m[14] + signo * m[fila * 4 + 2]
                local c = m[15] + signo * m[fila * 4 + 3]
                local d = m[16] + signo * m[fila * 4 + 4]
                local largo = math.sqrt(a * a + b * b + c * c)
                if largo > 1e-12 then
                    k = k + 1
                    planos[k] = planos[k] or {}
                    local p = planos[k]
                    p[1], p[2], p[3], p[4] = a / largo, b / largo, c / largo, d / largo
                end
            end
        end
    end
    for extra = k + 1, #planos do
        planos[extra] = nil
    end
end

--- ¿Toca el trozo el frustum abierto `margenGiro` a cada lado?
function TerrenoTrozos:enVista(t, ex, ey, ez)
    local cx, cy, cz = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2, (t.z0 + t.z1) / 2
    local rx, ry, rz = (t.x1 - t.x0) / 2, (t.y1 - t.y0) / 2, (t.z1 - t.z0) / 2 + t.faldon
    local radio = math.sqrt(rx * rx + ry * ry + rz * rz)
    local dx, dy, dz = cx - ex, cy - ey, cz - ez
    radio = radio + math.sin(TerrenoTrozos.margenGiro) * math.sqrt(dx * dx + dy * dy + dz * dz)
    for _, p in ipairs(self.planos) do
        if p[1] * cx + p[2] * cy + p[3] * cz + p[4] < -radio then
            return false
        end
    end
    return true
end

--- Distancia (px) del ojo a la caja del trozo.
local function distanciaCaja(t, ex, ey, ez)
    local dx = math.max(t.x0 - ex, 0, ex - t.x1)
    local dy = math.max(t.y0 - ey, 0, ey - t.y1)
    local dz = math.max(t.z0 - ez, 0, ez - t.z1)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Elige el nivel de cada trozo y lo manda a dibujar. `matriz` es la de
-- vista y proyección del juego (Camara:matrices) y (ex, ey, ez) el ojo en px.
-- `nivelFijo` fuerza un nivel (pruebas).
function TerrenoTrozos:dibujar(ex, ey, ez, matriz, altoPantalla, nivelFijo)
    self:actualizarPlanos(matriz)
    local k = (altoPantalla or 1080) / (2 * math.tan(TerrenoTrozos.campo / 2))
    local tolerancia = TerrenoTrozos.tolerancia * (altoPantalla or 1080) / 1080
    local histeresis = TerrenoTrozos.histeresis
    local dibujados, triangulos = 0, 0
    for _, t in ipairs(self.trozos) do
        local d = distanciaCaja(t, ex, ey, ez)
        local sombra = d < self.alcanceSombra
        if sombra or self:enVista(t, ex, ey, ez) then
            local niveles = t.niveles
            local nivel = 1
            if nivelFijo then
                nivel = math.min(nivelFijo, #niveles)
            else
                local dd = math.max(d, 1)
                for n = #niveles, 2, -1 do
                    -- Para ir a un nivel más sencillo que el actual, con margen.
                    local tope = n > t.nivel and tolerancia * histeresis or tolerancia
                    if niveles[n].error * k / dd <= tope then
                        nivel = n
                        break
                    end
                end
            end
            t.nivel = nivel
            local malla = niveles[nivel].malla
            malla.shadowVisibility = sombra
            self.dream:draw(malla)
            dibujados = dibujados + 1
            triangulos = triangulos + niveles[nivel].triangulos
        end
    end
    self.dibujados, self.triangulos = dibujados, triangulos
end

--- Cuántos trozos hay en cada nivel ahora (para el rótulo y las pruebas).
function TerrenoTrozos:resumen()
    local cuenta = {}
    for _, t in ipairs(self.trozos) do
        cuenta[t.nivel] = (cuenta[t.nivel] or 0) + 1
    end
    local partes = {}
    for n = 1, #TerrenoTrozos.pasos do
        partes[#partes + 1] = tostring(cuenta[n] or 0)
    end
    return string.format(
        '%d trozos (%s por nivel), %d dibujados, %.0f mil triángulos',
        #self.trozos,
        table.concat(partes, '/'),
        self.dibujados or 0,
        (self.triangulos or 0) / 1000
    )
end

return TerrenoTrozos

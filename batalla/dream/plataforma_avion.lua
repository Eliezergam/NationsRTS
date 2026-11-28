-- Plataforma de los aviones de carga, al norte de la pista (el dueño, 26-nov:
-- «que no se pongan uno encima del otro en la pista»). Como la plataforma
-- de una base aérea: losa de hormigón con la calle de rodaje paralela a la
-- pista y una fila de plazas; las líneas amarillas marcan el eje de la calle,
-- la entrada a cada plaza y la de la pista. Las medidas, en
-- batalla/sitios/plano.lua (Plano.aerodromo.plataforma).
--
--   local plataforma = PlataformaAvion.nueva(dream, conversor, suelo, pista)
--   plataforma:dibujar()                    cada cuadro
--   PlataformaAvion.altura(plataforma, xm, ym)   m en (x, y) m de los robots, o nil fuera

local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
local KitSitio = require('batalla.dream.kit_sitio')
local Plano = require('batalla.sitios.plano')

local PlataformaAvion = {}
PlataformaAvion.__index = PlataformaAvion

PlataformaAvion.paso = 10 -- m de la rejilla
PlataformaAvion.sobre = 0.3 -- m por encima del terreno explanado
PlataformaAvion.repeticion = 6 -- m por repetición de la textura

-- Datos de la malla: { x, y, z px, u, v } por vértice, 12 flotantes (los
-- de kit_sitio y pista_avion).
local function triangulo(datos, a, b, c)
    for _, v in ipairs({ a, b, c }) do
        local n = #datos
        datos[n + 1], datos[n + 2], datos[n + 3] = v[1] * 0.1, v[3] * 0.1, v[2] * 0.1
        datos[n + 4], datos[n + 5], datos[n + 6] = 0, 1, 0
        datos[n + 7], datos[n + 8] = v[4], v[5]
        datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = 1, 0, 0, 1
    end
end

local function cuadro(datos, a, b, c, d)
    triangulo(datos, a, b, c)
    triangulo(datos, a, c, d)
end

local function mallas(dream, porMaterial, cx, cy)
    local resultado = {}
    local ocx, ocy = cx * 0.1, cy * 0.1
    for nombre, datos in pairs(porMaterial) do
        local cantidad = #datos / 12
        if cantidad >= 3 then
            local malla = dream:newMesh(KitSitio.material(dream, nombre))
            malla:setPixelShader('textured')
            malla.vertices = dream:newBuffer('vec3', 'float', cantidad)
            malla.normals = dream:newBuffer('vec3', 'float', cantidad)
            malla.texCoords = dream:newBuffer('vec2', 'float', cantidad)
            malla.tangents = dream:newBuffer('vec4', 'float', cantidad)
            malla.faces = dream:newBuffer('vec3', 'uint32_t', cantidad / 3)
            local vs, ns, uvs, ts = malla.vertices.buffer, malla.normals.buffer, malla.texCoords.buffer, malla.tangents.buffer
            local k = 0
            for o = 1, #datos, 12 do
                vs[k].x = (datos[o] - ocx) * 0.1
                vs[k].y = datos[o + 1] * 0.1
                vs[k].z = (datos[o + 2] - ocy) * 0.1
                ns[k].x, ns[k].y, ns[k].z = datos[o + 3], datos[o + 4], datos[o + 5]
                uvs[k].x, uvs[k].y = datos[o + 6], datos[o + 7]
                ts[k].x, ts[k].y, ts[k].z, ts[k].w = datos[o + 8], datos[o + 9], datos[o + 10], datos[o + 11]
                k = k + 1
            end
            local caras = malla.faces.buffer
            for f = 0, cantidad / 3 - 1 do
                caras[f].x, caras[f].y, caras[f].z = f * 3 + 1, f * 3 + 2, f * 3 + 3
            end
            malla:updateBoundingSphere()
            -- Suelo: recibe sombra pero no la proyecta (como la pista).
            malla:setShadowVisibility(false)
            resultado[#resultado + 1] = malla
        end
    end
    return resultado
end

--- `pista` = { x, y, rumbo, medioLargo } (Plano:ponerPista; px y m).
function PlataformaAvion.nueva(dream, conversor, suelo, pista)
    if dream and not dream.materialLibrary.baseHormigon then
        BibliotecaPbr.cargar(dream, 'assets/base/materiales')
    end
    local P = Plano.aerodromo.plataforma
    local self = setmetatable({}, PlataformaAvion)
    self.dream = dream
    local c, s = math.cos(pista.rumbo), math.sin(pista.rumbo)
    self.x, self.y, self.c, self.s = pista.x, pista.y, c, s
    -- a lo largo (m) y l al norte (m): el norte es -y en px del juego.
    local function px(a, l)
        return pista.x + (c * a + s * l) * 10, pista.y + (s * a - c * l) * 10
    end
    self.px = px
    local L = pista.medioLargo + 20
    local D = PlataformaAvion.paso
    self.a0, self.l0 = -L, P.desde
    self.na = math.ceil(2 * L / D)
    self.nl = math.ceil((P.hasta - P.desde) / D)
    -- Alto en cada nudo de la rejilla: el terreno (ya explanado) un poco
    -- más arriba; nunca por debajo de lo que hay en las cuatro esquinas.
    self.z = {}
    for i = 0, self.na do
        self.z[i] = {}
        for j = 0, self.nl do
            local a, l = self.a0 + i * D, self.l0 + j * D
            local zmax = -math.huge
            for _, d in ipairs({ { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }) do
                local x, y = px(a + d[1], l + d[2])
                zmax = math.max(zmax, suelo:altura(x, y))
            end
            self.z[i][j] = zmax + PlataformaAvion.sobre * 10
        end
    end
    local porMaterial = { kitHormigon = {}, kitLineaAmarilla = {} }
    local R = PlataformaAvion.repeticion
    local function punto(a, l, dz)
        local x, y = px(a, l)
        return { x, y, self:alturaPx(a, l) + (dz or 0), a / R, l / R }
    end
    -- Losa: celdas de la rejilla.
    for i = 0, self.na - 1 do
        for j = 0, self.nl - 1 do
            local a, l = self.a0 + i * D, self.l0 + j * D
            cuadro(porMaterial.kitHormigon, punto(a, l), punto(a + D, l), punto(a + D, l + D), punto(a, l + D))
        end
    end
    -- Líneas amarillas (15 cm de ancho a cada lado del eje), a trozos de
    -- 5 m siguiendo el suelo.
    local function linea(a0, l0, a1, l1)
        local largo = math.sqrt((a1 - a0) ^ 2 + (l1 - l0) ^ 2)
        local n = math.max(1, math.ceil(largo / 5))
        local ua, ul = (a1 - a0) / largo, (l1 - l0) / largo
        local na, nl = -ul * 0.15, ua * 0.15
        for k = 0, n - 1 do
            local t0, t1 = k / n, (k + 1) / n
            local pa, pl = a0 + (a1 - a0) * t0, l0 + (l1 - l0) * t0
            local qa, ql = a0 + (a1 - a0) * t1, l0 + (l1 - l0) * t1
            cuadro(porMaterial.kitLineaAmarilla, punto(pa - na, pl - nl, 1), punto(qa - na, ql - nl, 1),
                punto(qa + na, ql + nl, 1), punto(pa + na, pl + nl, 1))
        end
    end
    linea(-L + 5, P.calle, L - 5, P.calle)
    for _, a in ipairs(PlataformaAvion.plazas()) do
        linea(a, P.calle, a, P.plaza + 22)
        -- Barra de parada donde queda el tren de morro.
        linea(a - 4, P.plaza + 20, a + 4, P.plaza + 20)
    end
    -- De la calle a la cabecera de la pista.
    linea(P.entrada, P.calle, P.entrada, P.desde + 0.5)
    -- Sin `dream` (la maqueta del mapa, mundo/maquetas.lua): solo los datos.
    if dream then
        self.mallas = mallas(dream, porMaterial, conversor.cx, conversor.cy)
    else
        self.porMaterial = porMaterial
    end
    print(string.format('PLATAFORMA %d x %d m, %d plazas', 2 * L, P.hasta - P.desde, P.plazas))
    return self
end

--- A lo largo (m) de cada plaza, de oeste a este.
function PlataformaAvion.plazas()
    local P = Plano.aerodromo.plataforma
    local lista = {}
    for k = 1, P.plazas do
        lista[k] = (k - (P.plazas + 1) / 2) * P.separacion
    end
    return lista
end

--- Alto (px) en (a, l) m de la plataforma, bilineal en la rejilla, o nil fuera.
function PlataformaAvion:alturaPx(a, l)
    local fi, fj = (a - self.a0) / PlataformaAvion.paso, (l - self.l0) / PlataformaAvion.paso
    if fi < 0 or fj < 0 or fi > self.na or fj > self.nl then
        return nil
    end
    local i, j = math.min(self.na - 1, math.floor(fi)), math.min(self.nl - 1, math.floor(fj))
    local u, v = fi - i, fj - j
    local z = self.z
    return (z[i][j] * (1 - u) + z[i + 1][j] * u) * (1 - v) + (z[i][j + 1] * (1 - u) + z[i + 1][j + 1] * u) * v
end

--- Alto (m) en (xm, ym) m de los ejes de los robots (y al norte), o nil fuera.
function PlataformaAvion.altura(self, xm, ym)
    local dx, dy = xm * 10 - self.x, -ym * 10 - self.y
    local a = (dx * self.c + dy * self.s) / 10
    local l = (dx * self.s - dy * self.c) / 10
    local z = self:alturaPx(a, l)
    return z and z / 10
end

function PlataformaAvion:dibujar()
    for _, m in ipairs(self.mallas) do
        self.dream:draw(m)
    end
end

return PlataformaAvion

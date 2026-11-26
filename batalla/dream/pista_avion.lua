-- Pista improvisada del avión de carga (el dueño, 20-nov: «crea una
-- autopista improvisada para que la uses»): un tramo recto de autopista de
-- cuatro carriles usado como pista, como las pistas de carretera de
-- Finlandia o Suiza: calzada de asfalto de 30 m con sus líneas de carril,
-- líneas de borde continuas, marcas de umbral (barras) en los dos extremos
-- y arcén de hormigón; un talud de grava por los lados hasta el terreno.
--
-- La superficie: el terreno a lo largo del eje, suavizado (media de 80 m) y
-- nunca por debajo del terreno en todo el ancho, para que no lo atraviese.
-- El avión rueda sobre ella (vueloAvion.lua: PistaAvion.altura).
--
-- Materiales: los de las calles de las ciudades (batalla/dream/kit_sitio.lua,
-- texturas de Poly Haven en assets/base/materiales).
--
--   local pista = PistaAvion.nueva(dream, conversor, suelo, x, y, rumbo)
--   pista:dibujar()                      cada cuadro
--   PistaAvion.altura(pista, xm, ym)     m de la superficie en (x, y) m
--                                        (ejes de los robots), o nil fuera

local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
local KitSitio = require('batalla.dream.kit_sitio')

local PistaAvion = {}
PistaAvion.__index = PistaAvion

PistaAvion.medioLargo = 450 -- m
PistaAvion.calzada = 15 -- m de medio ancho del asfalto
PistaAvion.arcen = 3 -- m de hormigón a cada lado
PistaAvion.paso = 10 -- m entre secciones
PistaAvion.suavizado = 4 -- secciones a cada lado en la media (80 m)
PistaAvion.sobre = 0.25 -- m por encima del terreno, como poco
PistaAvion.repeticion = 4 -- m por repetición de la textura del asfalto

--- Triángulo { x, y, z px, u, v } con la normal pedida (ejes de Dream: x,
-- arriba, y del juego), en el formato de kit_sitio (12 flotantes).
local function triangulo(datos, a, b, c, nx, ny, nz, tx, ty, tz)
    local ax, ay, az = a[1] * 0.1, a[3] * 0.1, a[2] * 0.1
    local bx, by, bz = b[1] * 0.1, b[3] * 0.1, b[2] * 0.1
    local cx, cy, cz = c[1] * 0.1, c[3] * 0.1, c[2] * 0.1
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local vx, vy, vz = cx - ax, cy - ay, cz - az
    local gx, gy, gz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if gx * nx + gy * ny + gz * nz < 0 then
        b, c = c, b
    end
    for _, v in ipairs({ a, b, c }) do
        local n = #datos
        datos[n + 1], datos[n + 2], datos[n + 3] = v[1] * 0.1, v[3] * 0.1, v[2] * 0.1
        datos[n + 4], datos[n + 5], datos[n + 6] = nx, ny, nz
        datos[n + 7], datos[n + 8] = v[4], v[5]
        datos[n + 9], datos[n + 10], datos[n + 11], datos[n + 12] = tx, ty, tz, 1
    end
end

local function cuadro(datos, a, b, c, d, nx, ny, nz, tx, ty, tz)
    triangulo(datos, a, b, c, nx, ny, nz, tx, ty, tz)
    triangulo(datos, a, c, d, nx, ny, nz, tx, ty, tz)
end

--- Mallas de 3Dream (una por material) con los datos de cada material.
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
            -- La pista es suelo: no proyecta sombra (las líneas, 15 cm sobre el
            -- asfalto, dejaban una raya oscura al lado, el dueño, 20-nov), como
            -- los trozos del terreno (terreno_trozos.lua). Sí la recibe.
            malla:setShadowVisibility(false)
            resultado[#resultado + 1] = malla
        end
    end
    return resultado
end

--- Pista centrada en (x, y) px con rumbo del juego `rumbo` (y al sur).
function PistaAvion.nueva(dream, conversor, suelo, x, y, rumbo, medioLargo)
    if not dream.materialLibrary.baseAsfalto then
        BibliotecaPbr.cargar(dream, 'assets/base/materiales')
    end
    local self = setmetatable({}, PistaAvion)
    self.dream = dream
    local c, s = math.cos(rumbo), math.sin(rumbo)
    -- Ejes en px del juego: a lo largo (c, s) y a un lado (-s, c).
    self.x, self.y, self.c, self.s = x, y, c, s
    self.medioLargo = medioLargo or PistaAvion.medioLargo
    local L, P = self.medioLargo, PistaAvion.paso
    local W = PistaAvion.calzada + PistaAvion.arcen
    local n = math.floor(2 * L / P)
    self.n = n
    -- Perfil: alto del terreno en el eje y el máximo en el ancho (px).
    local eje, maximo = {}, {}
    for i = 0, n do
        local a = (-L + i * P) * 10
        local zmax = -math.huge
        for _, l in ipairs({ -W, -W / 2, 0, W / 2, W }) do
            zmax = math.max(zmax, suelo:altura(x + c * a - s * l * 10, y + s * a + c * l * 10))
        end
        eje[i] = suelo:altura(x + c * a, y + s * a)
        maximo[i] = zmax
    end
    -- Suavizado, y nunca por debajo del terreno (dos pasadas).
    local perfil = {}
    for i = 0, n do
        local suma, cuenta = 0, 0
        for k = math.max(0, i - PistaAvion.suavizado), math.min(n, i + PistaAvion.suavizado) do
            suma, cuenta = suma + eje[k], cuenta + 1
        end
        perfil[i] = math.max(suma / cuenta, maximo[i] + PistaAvion.sobre * 10)
    end
    for _ = 1, 2 do
        local nuevo = {}
        for i = 0, n do
            local a, b = perfil[math.max(0, i - 1)], perfil[math.min(n, i + 1)]
            nuevo[i] = math.max((a + 2 * perfil[i] + b) / 4, maximo[i] + PistaAvion.sobre * 10)
        end
        perfil = nuevo
    end
    self.perfil = perfil -- px
    local alto, bajo = 0, 0
    for i = 0, n do
        alto = math.max(alto, perfil[i] - eje[i])
        bajo = math.min(bajo, perfil[i] - eje[i])
    end
    print(string.format('PISTA %d m: terraplén de hasta %.1f m sobre el terreno (y %.1f m por debajo)', 2 * L, alto / 10, bajo / 10))
    -- Mallas.
    local porMaterial = { kitAsfalto = {}, kitLinea = {}, kitHormigon = {}, kitGrava = {} }
    local function punto(i, l, dz, u, v)
        local a = (-L + i * P) * 10
        return { x + c * a - s * l * 10, y + s * a + c * l * 10, perfil[i] + (dz or 0), u or 0, v or 0 }
    end
    local tx, tz = c, s
    local R = PistaAvion.repeticion
    local Wc = PistaAvion.calzada
    for i = 0, n - 1 do
        local v0, v1 = i * P / R, (i + 1) * P / R
        -- Calzada.
        cuadro(porMaterial.kitAsfalto, punto(i, -Wc, 0, -Wc / R, v0), punto(i, Wc, 0, Wc / R, v0),
            punto(i + 1, Wc, 0, Wc / R, v1), punto(i + 1, -Wc, 0, -Wc / R, v1), 0, 1, 0, tx, 0, tz)
        -- Arcenes de hormigón y faldón hasta el terreno.
        for _, lado in ipairs({ -1, 1 }) do
            local a0, a1 = lado * Wc, lado * W
            cuadro(porMaterial.kitHormigon, punto(i, a0, -0.05, 0, v0), punto(i, a1, -0.05, 1, v0),
                punto(i + 1, a1, -0.05, 1, v1), punto(i + 1, a0, -0.05, 0, v1), 0, 1, 0, tx, 0, tz)
            -- Talud de grava 1:2 hacia fuera hasta el terreno (un
            -- terraplén, no una pared).
            local A, B = punto(i, a1, -0.05, 0, v0), punto(i + 1, a1, -0.05, 0, v1)
            local function pie(P0, ai2)
                local alto = 0
                local px, py = P0[1], P0[2]
                for _ = 1, 3 do
                    alto = math.max(0, P0[3] - suelo:altura(px, py))
                    px = P0[1] - s * lado * alto * 2
                    py = P0[2] + c * lado * alto * 2
                end
                return { px, py, suelo:altura(px, py) - 3, alto / 10 / R * 2, ai2 }
            end
            local C, D = pie(B, v1), pie(A, v0)
            local hx, hy = -s * lado, c * lado
            cuadro(porMaterial.kitGrava, A, B, C, D, hx * 0.45, 0.9, hy * 0.45, tx, 0, tz)
        end
        -- Líneas: borde continuo, carriles discontinuos (3 m cada 9 m) y la
        -- mediana continua doble.
        local function linea(l, ancho)
            cuadro(porMaterial.kitLinea, punto(i, l - ancho, 1.5), punto(i, l + ancho, 1.5),
                punto(i + 1, l + ancho, 1.5), punto(i + 1, l - ancho, 1.5), 0, 1, 0, tx, 0, tz)
        end
        for _, l in ipairs({ -Wc + 0.4, Wc - 0.4, -0.3, 0.3 }) do
            linea(l, 0.12)
        end
        if (i % 3) == 0 then
            for _, l in ipairs({ -7.5, 7.5 }) do
                linea(l, 0.08)
            end
        end
    end
    -- Umbrales: barras a lo largo en los dos extremos (como las pistas).
    for _, i0 in ipairs({ 1, n - 4 }) do
        for k = -6, 6 do
            if k ~= 0 then
                local l = k * 2.1
                for i = i0, i0 + 2 do
                    cuadro(porMaterial.kitLinea, punto(i, l - 0.7, 1.6), punto(i, l + 0.7, 1.6),
                        punto(i + 1, l + 0.7, 1.6), punto(i + 1, l - 0.7, 1.6), 0, 1, 0, tx, 0, tz)
                end
            end
        end
    end
    self.mallas = mallas(dream, porMaterial, conversor.cx, conversor.cy)
    return self
end

--- Alto de la superficie (m) en (xm, ym) m de los ejes de los robots (y al
-- norte), o nil fuera de la pista (y de 6 m de margen a los lados).
function PistaAvion.altura(self, xm, ym)
    local px, py = xm * 10 - self.x, -ym * 10 - self.y
    local a = (px * self.c + py * self.s) / 10
    local l = (-px * self.s + py * self.c) / 10
    local L = self.medioLargo
    if math.abs(a) > L or math.abs(l) > PistaAvion.calzada + PistaAvion.arcen + 6 then
        return nil
    end
    local f = (a + L) / PistaAvion.paso
    local i = math.min(self.n - 1, math.floor(f))
    local t = f - i
    return (self.perfil[i] * (1 - t) + self.perfil[i + 1] * t) / 10
end

function PistaAvion:dibujar()
    for _, m in ipairs(self.mallas) do
        self.dream:draw(m)
    end
end

return PistaAvion

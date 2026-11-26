-- Rocas de la batalla (Valeria, a partir de la prueba de estilo de Camila):
-- cantos partidos en vez de bolas. Una esfera de meridianos y paralelos
-- deformada con ruido 3D a tres escalas, estirada de forma desigual (más
-- larga que ancha, más o menos alta) y cortada por entre 3 y 6 planos de
-- fractura que dejan caras planas; medio enterrada. Las normales mezclan las
-- suaves de la rejilla con las de cada cara: aristas marcadas sin perder el
-- volumen. Todo sale de `semilla` (Ruido.azar y love.math.noise): igual en
-- todas las máquinas. El material es el PBR de roca triplanar
-- (batalla/dream/estilo/roca_pbr.lua); las UV esféricas solo las pide el
-- formato de malla.

local Ruido = require('mundo.ruido')
local Geometria = require('batalla.dream.estilo.geometria')

local Roca = {}

local function normalizar(x, y, z)
    local largo = math.sqrt(x * x + y * y + z * z)
    return x / largo, y / largo, z / largo
end

--- Roca de radio medio `radio` (m) y semilla `semilla`. Detalle 1 cerca, 2
-- a media distancia y 3 lejos (la misma forma con menos caras).
function Roca.nueva(semilla, radio, detalle)
    local meridianos = ({ 18, 10, 7 })[detalle or 1]
    local paralelos = ({ 11, 6, 4 })[detalle or 1]
    local azar = Ruido.azar(semilla * 7919 + 13)
    local desplazamiento = semilla * 7.31
    -- Proporciones desiguales.
    local largo, ancho = azar(0.9, 1.35), azar(0.7, 1.05)
    local aplastado = azar(0.45, 0.78)
    -- Planos de fractura: sobre todo de lado y por arriba (abajo está enterrada).
    local cortes = {}
    for k = 1, 3 + math.floor(azar() * 4) do
        local rumbo = azar() * math.pi * 2
        local alto = azar(-0.25, 0.95)
        local plano = math.sqrt(1 - alto * alto)
        cortes[k] = { math.cos(rumbo) * plano, alto, math.sin(rumbo) * plano, azar(0.55, 0.82) }
    end
    local puntos = {}
    for j = 0, paralelos do
        puntos[j] = {}
        local polar = j / paralelos * math.pi
        for i = 0, meridianos do
            local azimut = (i % meridianos) / meridianos * math.pi * 2
            local dx = math.sin(polar) * math.cos(azimut)
            local dy = math.cos(polar)
            local dz = math.sin(polar) * math.sin(azimut)
            local r = 1
                + (love.math.noise(dx * 0.9 + desplazamiento, dy * 0.9, dz * 0.9) - 0.5) * 0.45
                + (love.math.noise(dx * 2.4, dy * 2.4 + desplazamiento, dz * 2.4) - 0.5) * 0.18
                + (love.math.noise(dx * 5.3, dy * 5.3, dz * 5.3 + desplazamiento) - 0.5) * 0.06
            local x, y, z = dx * r * largo, dy * r * aplastado, dz * r * ancho
            for _, c in ipairs(cortes) do
                local fuera = x * c[1] + y * c[2] + z * c[3] - c[4]
                if fuera > 0 then
                    x, y, z = x - c[1] * fuera, y - c[2] * fuera, z - c[3] * fuera
                end
            end
            -- Medio enterrada: la parte de abajo se aplana contra el suelo.
            if y < -0.15 then
                y = -0.15 + (y + 0.15) * 0.2
            end
            puntos[j][i] = { x * radio, (y + 0.15) * radio, z * radio }
        end
    end
    -- Normales suaves de la rejilla (diferencias centradas), hacia fuera.
    local normales = {}
    for j = 0, paralelos do
        normales[j] = {}
        for i = 0, meridianos do
            local p = puntos[j][i]
            local a = puntos[j][(i + 1) % meridianos]
            local b = puntos[j][(i - 1) % meridianos]
            local c = puntos[math.min(paralelos, j + 1)][i]
            local d = puntos[math.max(0, j - 1)][i]
            local tx, ty, tz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
            local sx, sy, sz = c[1] - d[1], c[2] - d[2], c[3] - d[3]
            local nx = ty * sz - tz * sy
            local ny = tz * sx - tx * sz
            local nz = tx * sy - ty * sx
            if nx * p[1] + ny * (p[2] - radio * 0.3) + nz * p[3] < 0 then
                nx, ny, nz = -nx, -ny, -nz
            end
            if j == 0 then
                nx, ny, nz = 0, 1, 0
            elseif j == paralelos then
                nx, ny, nz = 0, -1, 0
            end
            normales[j][i] = { normalizar(nx, ny, nz) }
        end
    end
    local geometria = Geometria.nueva()
    local repeticion = math.max(1, math.floor(radio * 1.5 + 0.5))
    local suave = 0.45
    for j = 0, paralelos - 1 do
        for i = 0, meridianos - 1 do
            -- Normal de la cara (por sus diagonales), hacia fuera.
            local a, b = puntos[j][i], puntos[j + 1][i + 1]
            local c, d = puntos[j][i + 1], puntos[j + 1][i]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local vx, vy, vz = d[1] - c[1], d[2] - c[2], d[3] - c[3]
            local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            local mx, my, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 - radio * 0.3, (a[3] + b[3]) / 2
            if fx * mx + fy * my + fz * mz < 0 then
                fx, fy, fz = -fx, -fy, -fz
            end
            local largoCara = math.sqrt(fx * fx + fy * fy + fz * fz)
            if largoCara > 1e-9 then
                fx, fy, fz = fx / largoCara, fy / largoCara, fz / largoCara
            else
                fx, fy, fz = 0, 1, 0
            end
            local function vertice(jj, ii)
                local p = puntos[jj][ii]
                local n = normales[jj][ii]
                local nx, ny, nz = normalizar(
                    n[1] * suave + fx * (1 - suave),
                    n[2] * suave + fy * (1 - suave),
                    n[3] * suave + fz * (1 - suave)
                )
                return { p[1], p[2], p[3], nx, ny, nz, ii / meridianos * 2 * repeticion, jj / paralelos * repeticion }
            end
            geometria:cuadrilatero(vertice(j, i), vertice(j, i + 1), vertice(j + 1, i + 1), vertice(j + 1, i))
        end
    end
    return geometria
end

return Roca

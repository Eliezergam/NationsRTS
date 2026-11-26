-- Cielo de un panorama HDRI (Valeria), alternativa a la atmósfera física
-- (batalla/dream/atmosfera.lua) para compararlas: el panorama es el fondo y,
-- sin su sol, la fuente de la luz del cielo (batalla/dream/ibl.lua). El sol
-- de la batalla se pone donde está el del panorama y con su energía: la
-- escala del panorama hace que su sol recortado ilumine lo mismo que el de
-- 3Dream, así el cielo y el sol guardan la proporción de la foto.

local ffi = require('ffi')
local Atmosfera = require('batalla.dream.atmosfera')

local CieloHDRI = {}
CieloHDRI.__index = CieloHDRI

-- Lo que pasa de `umbral` veces la mediana del cielo es el sol.
CieloHDRI.umbral = 60

local enviar = Atmosfera.enviar

--- Analiza el panorama en la CPU: dirección del sol, su iluminancia (lo que
-- sobra del umbral) e irradiancia del cielo sin él sobre el suelo horizontal.
local function analizar(datos)
    local ancho, alto = datos:getDimensions()
    local p = ffi.cast('float *', datos:getFFIPointer())
    local muestras = {}
    local paso = 4
    for y = 0, alto / 2 - 1, paso do
        for x = 0, ancho - 1, paso * 2 do
            local k = (y * ancho + x) * 4
            muestras[#muestras + 1] = 0.2126 * p[k] + 0.7152 * p[k + 1] + 0.0722 * p[k + 2]
        end
    end
    table.sort(muestras)
    local mediana = muestras[math.floor(#muestras / 2)]
    local tope = mediana * CieloHDRI.umbral
    local sol = { 0, 0, 0 }
    local eSol = 0
    local cielo = { 0, 0, 0 }
    local dPhi = 2 * math.pi / ancho
    local dTheta = math.pi / alto
    for y = 0, alto / 2 - 1 do
        local theta = (y + 0.5) * dTheta
        local st, ct = math.sin(theta), math.cos(theta)
        local w = dPhi * dTheta * st
        for x = 0, ancho - 1 do
            local k = (y * ancho + x) * 4
            local r, g, b = p[k], p[k + 1], p[k + 2]
            local l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            local f = 1
            if l > tope then
                local sobra = (l - tope) * w
                local phi = ((x + 0.5) / ancho - 0.5) * 2 * math.pi
                sol[1] = sol[1] + sobra * st * math.cos(phi)
                sol[2] = sol[2] + sobra * ct
                sol[3] = sol[3] + sobra * st * math.sin(phi)
                eSol = eSol + sobra
                f = tope / l
            end
            local c = ct * w * f
            cielo[1] = cielo[1] + r * c
            cielo[2] = cielo[2] + g * c
            cielo[3] = cielo[3] + b * c
        end
    end
    local largo = math.sqrt(sol[1] ^ 2 + sol[2] ^ 2 + sol[3] ^ 2)
    if largo > 0 then
        sol = { sol[1] / largo, sol[2] / largo, sol[3] / largo }
    else
        sol = { 0, 1, 0 }
    end
    return {
        sol = sol,
        eSol = eSol,
        cielo = cielo,
        tope = tope,
    }
end

function CieloHDRI.nuevo(ruta)
    local self = setmetatable({}, CieloHDRI)
    local datos = love.image.newImageData(ruta)
    self.analisis = analizar(datos)
    local imagen = love.graphics.newImage(datos)
    datos:release()
    -- Al formato de la GPU de 16 bits por canal y con niveles de detalle.
    local ancho, alto = imagen:getDimensions()
    self.panorama = love.graphics.newCanvas(ancho, alto, { format = 'rgba16f', mipmaps = 'manual', dpiscale = 1 })
    self.panorama:setFilter('linear', 'linear')
    self.panorama:setMipmapFilter('linear')
    self.panorama:setWrap('repeat', 'clamp')
    love.graphics.push('all')
    love.graphics.reset()
    love.graphics.setCanvas(self.panorama)
    love.graphics.setBlendMode('replace', 'premultiplied')
    -- El sol del panorama pasa de lo que cabe en 16 bits (65 504).
    love.graphics.setShader(love.graphics.newShader([[
        vec4 effect(vec4 color, Image t, vec2 uv, vec2 sc) {
            return vec4(min(Texel(t, uv).rgb, vec3(60000.0)), 1.0);
        }
    ]]))
    love.graphics.draw(imagen)
    love.graphics.pop()
    imagen:release()
    self.panorama:generateMipmaps()
    self.sombreadores = {
        cielo = Atmosfera.sombreador({ 'hdri_comun' }, 'hdri_cielo'),
        cara = Atmosfera.sombreador({ 'hdri_comun', 'cubo_comun' }, 'hdri_cara'),
    }
    self.irradiancia = love.graphics.newCanvas(1, 1, { format = 'rgba16f', dpiscale = 1 })
    self.giro = 0
    self.escala = 1
    return self
end

--- Dirección del sol del panorama girado `giro` radianes (Y arriba).
function CieloHDRI:solGirado(giro)
    local s = self.analisis.sol
    local c, n = math.cos(giro), math.sin(giro)
    return { s[1] * c - s[3] * n, s[2], s[1] * n + s[3] * c }
end

--- Gira el panorama `giro` radianes y lo escala para que su sol dé `luzSol`
-- de iluminancia (la del sol de 3Dream de cara a él).
function CieloHDRI:ajustar(giro, luzSol)
    self.giro = giro
    self.escala = luzSol / math.max(self.analisis.eSol, 1e-6)
    local c = self.analisis.cielo
    local e = self.escala
    love.graphics.push('all')
    love.graphics.setCanvas(self.irradiancia)
    love.graphics.clear(c[1] * e, c[2] * e, c[3] * e, 1)
    love.graphics.pop()
end

local function enviarPanorama(self, s)
    enviar(s, 'panorama', self.panorama)
    enviar(s, 'giro', self.giro)
    enviar(s, 'escalaPanorama', self.escala)
    enviar(s, 'topePanorama', self.analisis.tope)
end

function CieloHDRI:pintarCara(destino, cara, lado, luzSuelo, albedoSuelo)
    local s = self.sombreadores.cara
    enviarPanorama(self, s)
    enviar(s, 'cara', cara - 1)
    local c = self.analisis.cielo
    local e = self.escala
    enviar(s, 'cieloSuelo', { c[1] * e, c[2] * e, c[3] * e })
    enviar(s, 'luzSuelo', luzSuelo)
    enviar(s, 'albedoSuelo', albedoSuelo)
    Atmosfera.pasada(destino, s, lado, lado, cara, 1)
end

function CieloHDRI:dibujar(dream, transformProj)
    local s = self.sombreadores.cielo
    love.graphics.setShader(s)
    enviarPanorama(self, s)
    enviar(s, 'transformProj', transformProj)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(dream.cubeObject.meshes.Cube:getMesh())
end

return CieloHDRI

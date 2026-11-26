-- Lienzo de píxeles en memoria (flotantes RGBA de 0 a 1) para generar
-- texturas en código: ruido que se repite sin costura, trazos con grosor y
-- paso a una Image de LÖVE con mipmaps que conservan la cobertura del alfa.

local ffi = require('ffi')

local Lienzo = {}
Lienzo.__index = Lienzo

function Lienzo.nuevo(ancho, alto, r, g, b, a)
    local self = setmetatable({}, Lienzo)
    self.ancho = ancho
    self.alto = alto
    self.datos = ffi.new('float[?]', ancho * alto * 4)
    for k = 0, ancho * alto - 1 do
        self.datos[k * 4] = r or 0
        self.datos[k * 4 + 1] = g or 0
        self.datos[k * 4 + 2] = b or 0
        self.datos[k * 4 + 3] = a or 1
    end
    return self
end

--- Ruido fractal que se repite en u y v (de 0 a 1): se recorre un toro en
-- el ruido 4D de LÖVE, así el borde derecho empalma con el izquierdo.
-- Devuelve un valor en [0, 1].
function Lienzo.ruidoCiclico(u, v, frecuencia, octavas, semilla)
    local total = 0
    local peso = 1
    local suma = 0
    local dosPi = math.pi * 2
    local f = frecuencia
    for octava = 1, octavas do
        local radio = f / dosPi
        local desplazamiento = semilla * 17.13 + octava * 31.7
        local x = math.cos(u * dosPi) * radio + desplazamiento
        local y = math.sin(u * dosPi) * radio + desplazamiento
        local z = math.cos(v * dosPi) * radio - desplazamiento
        local w = math.sin(v * dosPi) * radio - desplazamiento
        total = total + love.math.noise(x, y, z, w) * peso
        suma = suma + peso
        peso = peso * 0.5
        f = f * 2
    end
    return total / suma
end

function Lienzo:indice(x, y)
    return (y * self.ancho + x) * 4
end

--- Mezcla un color sobre el píxel (x, y) con opacidad `a`. Con `envolver`,
-- las coordenadas que se salen entran por el otro lado.
function Lienzo:mezclar(x, y, r, g, b, a, envolver)
    if envolver then
        x = x % self.ancho
        y = y % self.alto
    elseif x < 0 or y < 0 or x >= self.ancho or y >= self.alto then
        return
    end
    local k = self:indice(x, y)
    local d = self.datos
    d[k] = d[k] + (r - d[k]) * a
    d[k + 1] = d[k + 1] + (g - d[k + 1]) * a
    d[k + 2] = d[k + 2] + (b - d[k + 2]) * a
end

--- Como `mezclar`, pero también acumula el alfa (para texturas recortadas).
function Lienzo:pintar(x, y, r, g, b, a, envolver)
    if not envolver and (x < 0 or y < 0 or x >= self.ancho or y >= self.alto) then
        return
    end
    self:mezclar(x, y, r, g, b, a, envolver)
    local k = self:indice(x % self.ancho, y % self.alto)
    self.datos[k + 3] = math.max(self.datos[k + 3], a)
end

--- Trazo de (x0, y0) a (x1, y1) con grosor que pasa de `ancho0` a `ancho1`
-- píxeles y color { r, g, b } que va de `color0` a `color1`.
function Lienzo:trazo(x0, y0, x1, y1, ancho0, ancho1, color0, color1, opciones)
    opciones = opciones or {}
    local largo = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    local pasos = math.max(1, math.ceil(largo * 1.5))
    for paso = 0, pasos do
        local t = paso / pasos
        local cx = x0 + (x1 - x0) * t
        local cy = y0 + (y1 - y0) * t
        local radio = (ancho0 + (ancho1 - ancho0) * t) * 0.5
        local r = color0[1] + (color1[1] - color0[1]) * t
        local g = color0[2] + (color1[2] - color0[2]) * t
        local b = color0[3] + (color1[3] - color0[3]) * t
        local alcance = math.ceil(radio + 1)
        for dy = -alcance, alcance do
            for dx = -alcance, alcance do
                local px = math.floor(cx) + dx
                local py = math.floor(cy) + dy
                local distancia = math.sqrt((px + 0.5 - cx) ^ 2 + (py + 0.5 - cy) ^ 2)
                local cubre = math.max(0, math.min(1, radio + 0.5 - distancia))
                if cubre > 0 then
                    if opciones.alfa then
                        self:pintar(px, py, r, g, b, cubre, opciones.envolver)
                    else
                        self:mezclar(px, py, r, g, b, cubre * (opciones.opacidad or 1), opciones.envolver)
                    end
                end
            end
        end
    end
end

--- Pinta el color de los píxeles transparentes con el promedio de los
-- opacos: el filtrado no mete bordes negros alrededor del follaje.
function Lienzo:rellenarTransparentes()
    local d = self.datos
    local sr, sg, sb, peso = 0, 0, 0, 0
    for k = 0, self.ancho * self.alto - 1 do
        local a = d[k * 4 + 3]
        sr = sr + d[k * 4] * a
        sg = sg + d[k * 4 + 1] * a
        sb = sb + d[k * 4 + 2] * a
        peso = peso + a
    end
    peso = math.max(peso, 0.0001)
    for k = 0, self.ancho * self.alto - 1 do
        local a = d[k * 4 + 3]
        d[k * 4] = d[k * 4] * a + sr / peso * (1 - a)
        d[k * 4 + 1] = d[k * 4 + 1] * a + sg / peso * (1 - a)
        d[k * 4 + 2] = d[k * 4 + 2] * a + sb / peso * (1 - a)
    end
end

--- ImageData RGBA8 del lienzo (o de un nivel reducido).
local function aImagenDatos(ancho, alto, datos)
    local imagenDatos = love.image.newImageData(ancho, alto, 'rgba8')
    local salida = ffi.cast('uint8_t*', imagenDatos:getFFIPointer())
    for k = 0, ancho * alto * 4 - 1 do
        salida[k] = math.max(0, math.min(255, math.floor(datos[k] * 255 + 0.5)))
    end
    return imagenDatos
end

--- Reduce a la mitad (promedio de 2 x 2).
local function reducir(ancho, alto, datos)
    local nuevoAncho = math.max(1, math.floor(ancho / 2))
    local nuevoAlto = math.max(1, math.floor(alto / 2))
    local nuevos = ffi.new('float[?]', nuevoAncho * nuevoAlto * 4)
    for y = 0, nuevoAlto - 1 do
        for x = 0, nuevoAncho - 1 do
            for canal = 0, 3 do
                local suma = 0
                for dy = 0, 1 do
                    for dx = 0, 1 do
                        local sx = math.min(ancho - 1, x * 2 + dx)
                        local sy = math.min(alto - 1, y * 2 + dy)
                        suma = suma + datos[(sy * ancho + sx) * 4 + canal]
                    end
                end
                nuevos[(y * nuevoAncho + x) * 4 + canal] = suma / 4
            end
        end
    end
    return nuevoAncho, nuevoAlto, nuevos
end

--- Fracción de píxeles con alfa * escala >= corte.
local function cobertura(ancho, alto, datos, escala, corte)
    local cubiertos = 0
    for k = 0, ancho * alto - 1 do
        if datos[k * 4 + 3] * escala >= corte then
            cubiertos = cubiertos + 1
        end
    end
    return cubiertos / (ancho * alto)
end

--- Niveles de mipmap (ImageData) del lienzo. Si `corte` existe (textura
-- recortada), cada nivel escala su alfa para cubrir la misma fracción que el
-- nivel 0: sin esto las ramas se van quedando calvas a lo lejos. No usa
-- love.graphics: se puede llamar desde un hilo (batalla/dream/estilo/hilo.lua).
function Lienzo:niveles(corte)
    local ancho, alto, datos = self.ancho, self.alto, self.datos
    local niveles = { aImagenDatos(ancho, alto, datos) }
    local objetivo = corte and cobertura(ancho, alto, datos, 1, corte)
    while ancho > 1 or alto > 1 do
        ancho, alto, datos = reducir(ancho, alto, datos)
        if corte then
            local bajo, arriba = 1, 8
            for _ = 1, 12 do
                local medio = (bajo + arriba) / 2
                if cobertura(ancho, alto, datos, medio, corte) < objetivo then
                    bajo = medio
                else
                    arriba = medio
                end
            end
            local escala = (bajo + arriba) / 2
            for k = 0, ancho * alto - 1 do
                datos[k * 4 + 3] = math.min(1, datos[k * 4 + 3] * escala)
            end
        end
        niveles[#niveles + 1] = aImagenDatos(ancho, alto, datos)
    end
    return niveles
end

--- Image con mipmaps de unos niveles (`Lienzo:niveles`), con filtro
-- anisótropo y repetida o recortada en los bordes.
function Lienzo.imagenDeNiveles(niveles, repetir)
    local imagen = love.graphics.newImage(niveles, { mipmaps = true })
    imagen:setFilter('linear', 'linear', 8)
    imagen:setMipmapFilter('linear')
    if repetir then
        imagen:setWrap('repeat', 'repeat')
    else
        imagen:setWrap('clamp', 'clamp')
    end
    return imagen
end

--- Image con mipmaps (ver `Lienzo:niveles`).
function Lienzo:imagen(corte, repetir)
    return Lienzo.imagenDeNiveles(self:niveles(corte), repetir)
end

return Lienzo

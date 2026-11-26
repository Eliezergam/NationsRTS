-- AA temporal de la batalla 3D (Valeria; Fase 2 de PLAN-RENDER-UE.md), en
-- lugar del MSAA 4: cada cuadro se dibuja con la cámara desplazada un
-- subpíxel distinto (camera:setJitter de lib/3DreamEngine) y
-- sombreadores/taa.glsl lo junta con la historia reproyectada. Así, como el
-- TSR de Unreal, los bordes, la hierba y las ramas finas quedan estables en
-- movimiento sin el coste del MSAA y sin emborronar.
--
-- Uso (batalla/dream/escena.lua):
--   temporal:prepararCuadro(camara)  -- antes de dream:present()
--   local imagen = temporal:resolver(lienzoDeLaEscena, dream.canvases, camara)
--   tono:terminar(imagen)
--
-- Lo que se mueve por su cuenta no tiene vectores de movimiento. Los lotes de
-- unidades y los misiles van marcados (`mesh.movil`, en un lienzo r8 de
-- 3Dream: setMotionMask) y allí pesa más el cuadro nuevo; además, la historia se
-- descarta si su profundidad no es la de la superficie de ahora, y la caja de
-- color de los vecinos recorta el resto (hierba con viento): sin estelas.
-- Con la cámara quieta, la imagen se compara con una referencia renderizada
-- a 3840 x 2160 y reducida (batalla/pruebas_rendimiento, TAM=3840x2160).

local Atmosfera = require('batalla.dream.atmosfera')

local Temporal = {}
Temporal.__index = Temporal

-- Peso del cuadro nuevo: con la imagen quieta (más historia, más estable) y
-- con mucho movimiento (al remuestrear la historia cada cuadro se emborrona:
-- con 0,16, girando a 10°/s y avanzando a 5 m/s, el error frente a la
-- referencia sobremuestreada era mayor que con MSAA; con 0,4, menor). Se pasa
-- de una a otra entre `rampaMovil` px de movimiento por cuadro.
Temporal.mezcla = 0.08
Temporal.mezclaMovil = 0.4
Temporal.rampaMovil = { 0.5, 3 }
-- Reconstrucción: gaussiano exp(-k d^2) entre el centro del píxel y lo que vio
-- cada vecino. Con 6 el núcleo es más estrecho que el de Unreal (2,29): con
-- 3 la imagen quieta quedaba más suave que la referencia sobremuestreada.
Temporal.filtro = 6
-- Desviaciones de la caja de recorte con la imagen quieta (con movimiento, 1).
Temporal.caja = 1.25
-- Peso del cuadro nuevo sobre lo que se mueve por su cuenta (marcado con
-- `mesh.movil`: lotes de unidades y misiles).
Temporal.mezclaObjeto = 0.5
-- Tolerancia del rango de profundidad con el que se reconoce la misma
-- superficie en la historia: relativa y absoluta (unidades de 3Dream, 10 m).
Temporal.toleranciaProf = { 0.03, 0.02 }
-- Exposición aproximada de batalla/dream/tono.lua, para la curva de Karis.
Temporal.exposicion = 1.7
-- Corte de cámara: más de esto en un cuadro y se empieza sin historia.
Temporal.saltoMax = 5 -- unidades de 3Dream (50 m)
Temporal.giroMax = 0.85 -- coseno entre las miradas (~32°)

-- Secuencia de Halton (2, 3) de 8 posiciones, centrada en el píxel.
local function halton(indice, base)
    local f = 1
    local r = 0
    local i = indice
    while i > 0 do
        f = f / base
        r = r + f * (i % base)
        i = math.floor(i / base)
    end
    return r
end

local SECUENCIA = {}
for k = 1, 8 do
    SECUENCIA[k] = { halton(k, 2) - 0.5, halton(k, 3) - 0.5 }
end

local enviar = Atmosfera.enviar

local function lienzo(ancho, alto)
    local c = love.graphics.newCanvas(ancho, alto, { format = 'rgba16f', dpiscale = 1 })
    c:setFilter('linear', 'linear')
    c:setWrap('clamp', 'clamp')
    return c
end

function Temporal.nuevo()
    local self = setmetatable({}, Temporal)
    self.sombreador = Atmosfera.sombreador({}, 'taa')
    self.indice = 0
    self.base = {
        pos = { 0, 0, 0 },
        der = { 1, 0, 0 },
        arr = { 0, 1, 0 },
        fre = { 0, 0, -1 },
        tan = { 1, 1 },
    }
    self.anterior = nil
    self.jitter = { 0, 0 }
    return self
end

--- Base de la cámara de 3Dream (posición, derecha, arriba, delante y
-- tangentes del medio campo), como la de la imagen final.
local function baseDe(camara, ancho, alto)
    local t = camara.transform
    local tanY = math.tan(camara.fov * math.pi / 360)
    return {
        pos = { t[4], t[8], t[12] },
        der = { t[1], t[5], t[9] },
        arr = { t[2], t[6], t[10] },
        fre = { -t[3], -t[7], -t[11] },
        tan = { tanY * ancho / alto, tanY },
    }
end

--- Imagen de 1 x 1 negra (sin marca de lo móvil).
function Temporal:negro()
    if not self.imagenNegra then
        local datos = love.image.newImageData(1, 1)
        datos:setPixel(0, 0, 0, 0, 0, 1)
        self.imagenNegra = love.graphics.newImage(datos)
    end
    return self.imagenNegra
end

--- Desplaza la cámara para el cuadro que se va a dibujar.
function Temporal:prepararCuadro(camara)
    self.indice = self.indice % #SECUENCIA + 1
    local j = SECUENCIA[self.indice]
    self.jitter[1], self.jitter[2] = j[1], j[2]
    camara:setJitter(j[1], j[2])
end

--- Quita el desplazamiento (para lo que se dibuje fuera del AA temporal).
function Temporal:quitar(camara)
    camara:setJitter(0, 0)
end

local function corte(a, b)
    if not a then
        return true
    end
    local dx = a.pos[1] - b.pos[1]
    local dy = a.pos[2] - b.pos[2]
    local dz = a.pos[3] - b.pos[3]
    if dx * dx + dy * dy + dz * dz > Temporal.saltoMax * Temporal.saltoMax then
        return true
    end
    local c = a.fre[1] * b.fre[1] + a.fre[2] * b.fre[2] + a.fre[3] * b.fre[3]
    return c < Temporal.giroMax
end

--- La imagen del cuadro anterior (ya con su luz rebotada) para la luz
-- rebotada de este (batalla/dream/rebote.lua: rebotes múltiples): el lienzo
-- de la historia (rgb con la gamma de 3Dream; alfa, la profundidad lineal,
-- negativa sobre lo móvil) y la base de la cámara con que se vio. Nada si
-- no hay historia, si cambió el tamaño o si este cuadro es un corte de cámara.
function Temporal:historiaPara(camara, ancho, alto)
    if not self.historias or not self.anterior then
        return nil
    end
    local historia = self.historias[self.cual]
    if historia:getPixelWidth() ~= ancho or historia:getPixelHeight() ~= alto then
        return nil
    end
    if corte(self.anterior, baseDe(camara, ancho, alto)) then
        return nil
    end
    return historia, self.anterior
end

--- Junta `actual` (la escena de este cuadro, con la gamma de 3Dream) con la
-- historia y devuelve el lienzo resultante, que es la historia del siguiente.
function Temporal:resolver(actual, lienzos, camara)
    local ancho, alto = actual:getPixelWidth(), actual:getPixelHeight()
    if
        not self.historias
        or self.historias[1]:getPixelWidth() ~= ancho
        or self.historias[1]:getPixelHeight() ~= alto
    then
        if self.historias then
            self.historias[1]:release()
            self.historias[2]:release()
        end
        self.historias = { lienzo(ancho, alto), lienzo(ancho, alto) }
        self.cual = 1
        self.anterior = nil
    end
    local base = baseDe(camara, ancho, alto)
    local reiniciar = corte(self.anterior, base)
    local anterior = self.anterior or base
    local n, f = camara.near, camara.far
    local origen = self.historias[self.cual]
    self.cual = 3 - self.cual
    local destino = self.historias[self.cual]

    local s = self.sombreador
    enviar(s, 'historia', origen)
    enviar(s, 'profundidad', lienzos.depth)
    enviar(s, 'movilTex', lienzos.movil or self:negro())
    enviar(s, 'texel', { 1 / ancho, 1 / alto })
    enviar(s, 'jitter', self.jitter)
    enviar(s, 'profParams', { 2 * f * n / (f - n), (f - n) / (f + n) })
    enviar(s, 'camPos', base.pos)
    enviar(s, 'camDer', base.der)
    enviar(s, 'camArr', base.arr)
    enviar(s, 'camFre', base.fre)
    enviar(s, 'camTan', base.tan)
    enviar(s, 'antPos', anterior.pos)
    enviar(s, 'antDer', anterior.der)
    enviar(s, 'antArr', anterior.arr)
    enviar(s, 'antFre', anterior.fre)
    enviar(s, 'antTan', anterior.tan)
    enviar(s, 'mezcla', Temporal.mezcla)
    enviar(s, 'mezclaMovil', Temporal.mezclaMovil)
    enviar(s, 'rampaMovil', Temporal.rampaMovil)
    enviar(s, 'reiniciar', reiniciar and 1 or 0)
    enviar(s, 'exposicion', Temporal.exposicion)
    enviar(s, 'filtro', Temporal.filtro)
    enviar(s, 'caja', Temporal.caja)
    enviar(s, 'toleranciaProf', Temporal.toleranciaProf)
    enviar(s, 'mezclaObjeto', Temporal.mezclaObjeto)

    love.graphics.push('all')
    love.graphics.reset()
    love.graphics.setCanvas(destino)
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setShader(s)
    actual:setFilter('nearest', 'nearest')
    love.graphics.draw(actual)
    actual:setFilter('linear', 'linear')
    love.graphics.pop()
    self.anterior = base
    return destino
end

return Temporal

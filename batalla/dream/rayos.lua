-- Consultas geométricas de la batalla mediante la extensión raytrace de
-- 3Dream: selección precisa, visibilidad contra el relieve e impactos.

local Conversor = require('batalla.dream.conversor')

local raytrace = require('lib.3DreamEngine.extensions.raytrace')

local Rayos = {}
Rayos.__index = Rayos

-- Volumen de selección de cada tipo de unidad, en metros: medio largo (en
-- el rumbo de la unidad), medio ancho, medio alto y altura del centro sobre
-- el suelo. `mallaUnidad` es una esfera de 10 px (1 m) de radio, así que la
-- escala en cada eje es la medida en metros. Un poco holgados: se pulsa
-- sobre la silueta, no sobre su centro exacto.
--   tanque         T-55: 9 m de largo con el cañón, 3,3 m de ancho, 2,4 m de alto
--   lanzacohetes   camión Synty de 11 m
Rayos.volumen = {
    tanque = { largo = 4.5, ancho = 2.2, alto = 1.6, centro = 1.4 },
    lanzacohetes = { largo = 6.0, ancho = 2.2, alto = 2.2, centro = 2.0 },
}

function Rayos.nuevo(dream, conversor, mallaTerreno, mallaUnidad, unidades)
    local self = setmetatable({}, Rayos)
    self.dream = dream
    self.conversor = conversor
    self.unidades = unidades
    self.mallaUnidad = mallaUnidad
    self.objetoTerreno = dream:newObject()
    self.objetoTerreno.meshes.terreno = mallaTerreno
    self.objetosUnidad = {}
    for _, unidad in ipairs(unidades) do
        local objeto = dream:newObject()
        objeto.meshes.volumen = mallaUnidad
        self.objetosUnidad[unidad] = objeto
    end
    return self
end

function Rayos:actualizarUnidad(unidad)
    local objeto = self.objetosUnidad[unidad]
    if not objeto then
        -- Una unidad de la reserva que entró después (oleadas).
        objeto = self.dream:newObject()
        objeto.meshes.volumen = self.mallaUnidad
        self.objetosUnidad[unidad] = objeto
    end
    local v = Rayos.volumen[unidad.tipo] or Rayos.volumen.tanque
    local x, y, z = self.conversor:punto(unidad.x, unidad.y, unidad.z + v.centro * 10)
    local mat4 = self.dream.mat4
    -- Girado con el rumbo de la unidad (X de 3Dream es la X del mundo; Z, la Y).
    local transformacion = mat4.getTranslate(x, y, z)
        * mat4.getRotateY(unidad.rumbo or 0)
        * mat4.getScale(v.largo, v.alto, v.ancho)
    objeto:setTransform(transformacion)
end

function Rayos:rayoDePantalla(x, y)
    local dream = self.dream
    -- Del píxel de la pantalla al del lienzo de 3Dream (más pequeño con el
    -- escalado, batalla/dream/escalado.lua).
    local ancho, alto = love.graphics.getDimensions()
    x, y = x * dream.canvases.width / ancho, y * dream.canvases.height / alto
    local cerca = dream:pixelToPoint(dream.vec3(x, y, dream.camera.near))
    local lejos = dream:pixelToPoint(dream.vec3(x, y, dream.camera.far))
    return cerca, lejos - cerca
end

function Rayos:unidadEnPantalla(x, y)
    local origen, direccion = self:rayoDePantalla(x, y)
    local mejor
    local mejorDistancia = math.huge
    for _, unidad in ipairs(self.unidades) do
        if not unidad.muerto then
            self:actualizarUnidad(unidad)
            local resultado = raytrace:cast(self.objetosUnidad[unidad], origen, direccion)
            if resultado and resultado:getDistance() < mejorDistancia then
                mejor = unidad
                mejorDistancia = resultado:getDistance()
            end
        end
    end
    return mejor
end

function Rayos:segmento(x0, y0, z0, x1, y1, z1)
    local ax, ay, az = self.conversor:punto(x0, y0, z0)
    local bx, by, bz = self.conversor:punto(x1, y1, z1)
    local origen = self.dream.vec3(ax, ay, az)
    local direccion = self.dream.vec3(bx - ax, by - ay, bz - az)
    return origen, direccion
end

function Rayos:lineaVisible(origen, destino)
    local rayo, direccion = self:segmento(origen.x, origen.y, origen.z + 22, destino.x, destino.y, destino.z + 18)
    local resultado = raytrace:cast(self.objetoTerreno, rayo, direccion)
    return not resultado or resultado:getDistance() >= 0.995
end

function Rayos:impacto(x0, y0, z0, x1, y1, z1)
    local origen, direccion = self:segmento(x0, y0, z0, x1, y1, z1)
    local resultado = raytrace:cast(self.objetoTerreno, origen, direccion)
    if not resultado then
        return x1, y1, z1
    end
    local posicion = resultado:getPosition()
    return self.conversor.cx + posicion.x / Conversor.escala,
        self.conversor.cy + posicion.z / Conversor.escala,
        posicion.y / Conversor.escala
end

return Rayos

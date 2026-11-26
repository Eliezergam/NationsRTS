-- Tabla de las matrices de las piezas de los vehículos articulados (Valeria):
-- la textura `matricesPiezas` que lee batalla/dream/piezas_lote.lua. Una fila
-- por copia de lote y seis texeles rgba32f por pieza: tres con su matriz de
-- este cuadro y tres con la del anterior (para el movimiento que usa el AA
-- temporal, batalla/dream/temporal.lua).
--
-- La textura es un lienzo rgba32f que escribe la GPU: cada cuadro se rellenan
-- por FFI los datos de las filas usadas (cuatro flotantes por texel, en un
-- ByteData), se suben a una malla dinámica y se pintan como puntos, uno por
-- texel, con un sombreador que copia el dato tal cual. Subir los datos con
-- `Image:replacePixels` paraba la CPU hasta 8 ms en algunos cuadros (los del
-- primer y el segundo disparo, siempre los mismos): el controlador esperaba
-- a la GPU. Con la malla, como los demás lotes, no espera.

local ffi = require('ffi')

local TablaPiezas = {}
TablaPiezas.__index = TablaPiezas

local SOMBREADOR = [[
varying vec4 datoPieza;

#ifdef VERTEX
attribute vec4 Dato;

vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    datoPieza = Dato;
    return transformProjection * vertexPosition;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla)
{
    return datoPieza;
}
#endif
]]

local sombreador

--- Tabla para vehículos de hasta `piezas` piezas y `filas` copias por cuadro.
function TablaPiezas.nueva(piezas, filas)
    local self = setmetatable({}, TablaPiezas)
    self.ancho = piezas * 6
    self.flotantesPorFila = self.ancho * 4
    self.filas = filas
    local texeles = self.ancho * filas
    self.imagen = love.graphics.newCanvas(self.ancho, filas, { format = 'rgba32f' })
    self.imagen:setFilter('nearest', 'nearest')
    -- Un punto en el centro de cada texel, fila a fila.
    self.puntos = love.graphics.newMesh({ { 'VertexPosition', 'float', 2 } }, texeles, 'points', 'static')
    local posiciones = love.data.newByteData(texeles * 8)
    local p = ffi.cast('float*', posiciones:getFFIPointer())
    for fila = 0, filas - 1 do
        for x = 0, self.ancho - 1 do
            local k = (fila * self.ancho + x) * 2
            p[k] = x + 0.5
            p[k + 1] = fila + 0.5
        end
    end
    self.puntos:setVertices(posiciones)
    self.datos = love.data.newByteData(texeles * 16)
    self.puntero = ffi.cast('float*', self.datos:getFFIPointer())
    self.mallaDatos = love.graphics.newMesh({ { 'Dato', 'float', 4 } }, texeles, 'points', 'dynamic')
    self.puntos:attachAttribute('Dato', self.mallaDatos)
    sombreador = sombreador or love.graphics.newShader(SOMBREADOR)
    self.usadas = 0
    self.cuadro = 0
    -- Matrices de cada pieza de cada vehículo en este cuadro y en el anterior.
    self.previas = setmetatable({}, { __mode = 'k' })
    return self
end

--- Empieza un cuadro: ninguna fila usada.
function TablaPiezas:vaciar()
    self.usadas = 0
    self.cuadro = self.cuadro + 1
end

--- Guarda la matriz de esta pieza (12 flotantes en `actual`) y escribe en
-- `destino` la que tenía en el cuadro anterior. Si no se dibujó en el cuadro
-- anterior (acaba de aparecer, o la pieza estaba oculta), la de ahora: sin
-- movimiento. Un vehículo que sale dos veces en el mismo cuadro (el fundido
-- entre niveles) recibe la misma.
function TablaPiezas:anterior(unidad, nombre, actual, destino)
    local porPieza = self.previas[unidad]
    if not porPieza then
        porPieza = {}
        self.previas[unidad] = porPieza
    end
    local e = porPieza[nombre]
    if not e then
        -- [0..11]: la del cuadro anterior; [12..23]: la de este.
        e = { datos = ffi.new('float[24]'), cuadro = -1, valida = false }
        porPieza[nombre] = e
    end
    local datos = e.datos
    if e.cuadro ~= self.cuadro then
        local seguida = e.cuadro == self.cuadro - 1
        ffi.copy(datos, datos + 12, 48)
        ffi.copy(datos + 12, actual, 48)
        local oculta = datos[0] == 0 and datos[1] == 0 and datos[2] == 0
        e.valida = seguida and not oculta
        e.cuadro = self.cuadro
    end
    if e.valida then
        ffi.copy(destino, datos, 48)
    else
        ffi.copy(destino, actual, 48)
    end
end

--- La siguiente fila libre: su número (desde 0) y el puntero a su primer
-- flotante; nil si la tabla está llena.
function TablaPiezas:reservar()
    local fila = self.usadas
    if fila >= self.filas then
        return nil
    end
    self.usadas = fila + 1
    return fila, self.puntero + fila * self.flotantesPorFila
end

--- Pinta en el lienzo las filas usadas en este cuadro.
function TablaPiezas:subir()
    local texeles = self.usadas * self.ancho
    if texeles == 0 then
        return
    end
    self.mallaDatos:setVertices(self.datos, 1, texeles)
    self.puntos:setDrawRange(1, texeles)
    love.graphics.push('all')
    love.graphics.reset()
    love.graphics.setCanvas(self.imagen)
    love.graphics.setShader(sombreador)
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setPointSize(1)
    love.graphics.draw(self.puntos)
    love.graphics.pop()
end

return TablaPiezas

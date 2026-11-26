-- Misiles en vuelo por instancias (Camila): el mismo modelo que lleva el
-- camión (la pieza `misil` del camión de misiles con robot conductor,
-- assets/modelos3d/catalogo.lua), todos en una llamada por malla. Cada cuadro
-- se escriben sus matrices por FFI (tres columnas de giro y la posición, el
-- formato de las instancias de 3Dream) y se suben de una vez: sin una tarea,
-- una matriz y una tabla de 3Dream por misil.

local ffi = require('ffi')
local Tropas = require('batalla.tropas')
local Conversor = require('batalla.dream.conversor')

local Misiles = {}
Misiles.__index = Misiles

local FLOTANTES = 12

--- `cargar`: función que da el modelo del misil en 3Dream (con sus mallas) y
-- la escala de sus mallas en unidades de 3Dream por unidad de la malla (0,1
-- si está en metros); se llama con el primer misil en el aire, así la
-- batalla sin camiones no lo carga. `capacidad`: los misiles en el aire a la
-- vez como mucho.
function Misiles.nuevos(dream, conversor, cargar, capacidad)
    local self = setmetatable({}, Misiles)
    self.dream = dream
    self.conversor = conversor
    self.capacidad = capacidad
    self.cargar = cargar
    self.escalaMalla = 1
    self.lotes = {}
    self.datos = love.data.newByteData(capacidad * FLOTANTES * 4)
    self.p = ffi.cast('float*', self.datos:getFFIPointer())
    self.matriz = {}
    self.cuenta = 0
    return self
end

--- Los lotes de instancias, uno por malla del modelo (la primera vez).
function Misiles:prepararLotes()
    if not self.cargar then
        return
    end
    local objeto, escala = self.cargar()
    self.cargar = nil
    if not objeto then
        return
    end
    self.escalaMalla = escala or 1
    local dream = self.dream
    for _, malla in pairs(objeto.meshes or {}) do
        local lote = dream:newInstancedMesh(malla)
        lote:resize(self.capacidad)
        -- Sin recorte: los misiles cruzan todo el cielo del campo.
        lote.boundingSphere = dream:newBoundingSphere(dream.vec3(0, 0, 0), 0)
        lote:setShadowVisibility(false)
        -- Se mueven por su cuenta (AA temporal: batalla/dream/temporal.lua).
        lote.movil = true
        self.lotes[#self.lotes + 1] = lote
    end
end

--- Escribe las matrices de los misiles de `tropas` y los pide a 3Dream.
function Misiles:dibujar(tropas)
    if #tropas.misiles == 0 then
        self.cuenta = 0
        return
    end
    self:prepararLotes()
    local p, n = self.p, 0
    local matriz = self.matriz
    local e = self.escalaMalla
    local escala = Conversor.escala
    local cx, cy = self.conversor.cx, self.conversor.cy
    for _, m in ipairs(tropas.misiles) do
        if n >= self.capacidad then
            break
        end
        local t = (tropas.reloj - m.inicio) / m.duracion
        Tropas.matrizMisil(m, t, matriz)
        -- Como `Conversor:matriz`: la Z del juego pasa a ser la Y de Dream.
        local k = n * FLOTANTES
        p[k], p[k + 1], p[k + 2] = matriz[1] * e, matriz[9] * e, matriz[5] * e
        p[k + 3], p[k + 4], p[k + 5] = matriz[3] * e, matriz[11] * e, matriz[7] * e
        p[k + 6], p[k + 7], p[k + 8] = matriz[2] * e, matriz[10] * e, matriz[6] * e
        p[k + 9], p[k + 10], p[k + 11] = (matriz[4] - cx) * escala, matriz[12] * escala, (matriz[8] - cy) * escala
        n = n + 1
    end
    self.cuenta = n
    if n == 0 or #self.lotes == 0 then
        return
    end
    for _, lote in ipairs(self.lotes) do
        lote.instanceMesh:setVertices(self.datos, 1, n)
        lote.instancesCount = n
        self.dream:draw(lote)
    end
end

return Misiles

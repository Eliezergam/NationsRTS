-- Copias de objetos de 3Dream en una sola llamada por malla (instancing),
-- para cualquier escena (almacén, batalla, campaña).
--
-- Cuando muchos objetos son clones del mismo modelo (las cajas del almacén,
-- los misiles de la línea de montaje...), dibujarlos uno a uno cuesta una
-- tarea de 3Dream por malla y por copia, y otra vez en cada capa de sombra:
-- todo en el hilo de Lua. Aquí cada malla distinta es un lote de instancias
-- (`batalla/dream/instancias.lua`) y las copias solo escriben su matriz.
--
--   local lote = LoteCopias.nuevo(dream)
--   -- cada cuadro:
--   lote:empezar()
--   lote:anadir(objeto, matrizDream)   -- clon de 3Dream y su mat4 de mundo
--   lote:dibujar()
--
-- Las mallas se agrupan por identidad: los clones de 3Dream
-- (`object:clone()`) comparten sus mallas. Los hijos del objeto van con su
-- propia transformación encima de la del padre.

local ffi = require('ffi')
local Instancias = require('batalla.dream.instancias')

local LoteCopias = {}
LoteCopias.__index = LoteCopias

-- Por copia: tres columnas de giro y la posición (formato de 3Dream).
local FLOTANTES = 12
local BYTES = FLOTANTES * 4

function LoteCopias.nuevo(dream)
    local self = setmetatable({}, LoteCopias)
    self.dream = dream
    -- malla de origen -> grupo { lote, datos, p, capacidad, cuenta }
    self.grupos = {}
    self.orden = {}
    self.esfera = {}
    -- Los lotes van dentro de un objeto marcado `dynamic`: así 3Dream los deja
    -- fuera de las sombras fijas de las lámparas (que se hacen una vez y
    -- dejarían la sombra de una caja donde estaba al empezar).
    self.contenedor = dream:newObject()
    self.contenedor.dynamic = true
    return self
end

local function nuevoGrupo(self, malla)
    local lote = Instancias.nuevas(self.dream, malla)
    -- Se mueven: fuera de las sombras estáticas de las lámparas.
    lote.dynamic = true
    local grupo = {
        lote = lote,
        capacidad = 0,
        cuenta = 0,
    }
    self.grupos[malla] = grupo
    self.orden[#self.orden + 1] = grupo
    return grupo
end

local function ampliar(grupo)
    local capacidad = math.max(16, grupo.capacidad * 2)
    local datos = love.data.newByteData(capacidad * BYTES)
    if grupo.datos then
        ffi.copy(datos:getFFIPointer(), grupo.datos:getFFIPointer(), grupo.cuenta * BYTES)
        grupo.datos:release()
    end
    grupo.datos = datos
    grupo.p = ffi.cast('float*', datos:getFFIPointer())
    grupo.capacidad = capacidad
end

local function escribir(self, malla, m)
    local grupo = self.grupos[malla] or nuevoGrupo(self, malla)
    if grupo.cuenta >= grupo.capacidad then
        ampliar(grupo)
    end
    local p = grupo.p
    local k = grupo.cuenta * FLOTANTES
    p[k], p[k + 1], p[k + 2] = m[1], m[5], m[9]
    p[k + 3], p[k + 4], p[k + 5] = m[2], m[6], m[10]
    p[k + 6], p[k + 7], p[k + 8] = m[3], m[7], m[11]
    p[k + 9], p[k + 10], p[k + 11] = m[4], m[8], m[12]
    grupo.cuenta = grupo.cuenta + 1
end

--- Vacía las copias del cuadro anterior.
function LoteCopias:empezar()
    for _, grupo in ipairs(self.orden) do
        grupo.cuenta = 0
    end
end

--- Una copia de `objeto` (objeto de 3Dream) con la matriz de mundo `matriz`
-- (mat4 de 3Dream). Sus hijos, con la suya encima.
function LoteCopias:anadir(objeto, matriz)
    for _, malla in pairs(objeto.meshes or {}) do
        escribir(self, malla, matriz)
    end
    for _, hijo in pairs(objeto.objects or {}) do
        self:anadir(hijo, hijo.transform and matriz * hijo.transform or matriz)
    end
end

--- Sube las matrices y pide a 3Dream un lote por malla con copias.
function LoteCopias:dibujar()
    local esfera = self.esfera
    local mallas = self.contenedor.meshes
    for k in pairs(mallas) do
        mallas[k] = nil
    end
    for indice, grupo in ipairs(self.orden) do
        local n = grupo.cuenta
        if n > 0 then
            local lote = grupo.lote
            if lote.instanceMesh:getVertexCount() < n then
                lote:resize(grupo.capacidad)
            end
            lote.instanceMesh:setVertices(grupo.datos, 1, n)
            lote.instancesCount = n
            -- Esfera de todas las copias, para el recorte de 3Dream.
            lote:clear()
            lote.instancesCount = n
            local p = grupo.p
            for i = 0, n - 1 do
                local k = i * FLOTANTES
                for j = 1, FLOTANTES do
                    esfera[j] = p[k + j - 1]
                end
                lote:extendBoundingSphere(esfera)
            end
            mallas[indice] = lote
        end
    end
    self.dream:draw(self.contenedor)
end

return LoteCopias

-- Adaptador de los lotes móviles de la batalla. Conserva la esfera local
-- al ampliar el buffer y calcula sus límites con las mismas columnas que
-- recibe el shader de instancias de 3DreamEngine.

local Instancias = {}

local function limpiar(self)
    self.instancesCount = 0
    self.boundingSphere.size = 0
end

local function redimensionar(self, cantidad)
    local esferaLocal = self.originalBoundingSphere
    self.dreamLib.classes.instancedMesh.resize(self, cantidad)
    self.originalBoundingSphere = esferaLocal
end

--- Cota de la escala máxima mediante AᵀA. Es exacta para las rotaciones
-- y escalas sin cizalla del juego, y conservadora si aparece cizalla.
local function escalaMaxima(m)
    local xx = m[1] * m[1] + m[2] * m[2] + m[3] * m[3]
    local yy = m[4] * m[4] + m[5] * m[5] + m[6] * m[6]
    local zz = m[7] * m[7] + m[8] * m[8] + m[9] * m[9]
    local xy = math.abs(m[1] * m[4] + m[2] * m[5] + m[3] * m[6])
    local xz = math.abs(m[1] * m[7] + m[2] * m[8] + m[3] * m[9])
    local yz = math.abs(m[4] * m[7] + m[5] * m[8] + m[6] * m[9])
    return math.sqrt(math.max(xx + xy + xz, yy + xy + yz, zz + xz + yz))
end

--- `m` contiene tres columnas de rotación y después la traslación.
-- Interpretarlas como filas gira el centro de la esfera al lado contrario
-- de la pieza: el error se nota en fusiles, ruedas y rampas articuladas.
local function ampliarEsfera(self, m)
    local origen = self.originalBoundingSphere
    local c = origen.center
    local x = m[1] * c[1] + m[4] * c[2] + m[7] * c[3] + m[10]
    local y = m[2] * c[1] + m[5] * c[2] + m[8] * c[3] + m[11]
    local z = m[3] * c[1] + m[6] * c[2] + m[9] * c[3] + m[12]
    local radio = origen.size * escalaMaxima(m)
    local esfera = self.boundingSphere
    local centro = esfera.center
    if esfera.size <= 0 then
        centro[1] = x
        centro[2] = y
        centro[3] = z
        esfera.size = radio
        return
    end

    local dx = x - centro[1]
    local dy = y - centro[2]
    local dz = z - centro[3]
    local distancia = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distancia + radio <= esfera.size then
        return
    end
    if distancia + esfera.size <= radio then
        centro[1] = x
        centro[2] = y
        centro[3] = z
        esfera.size = radio
        return
    end

    local nuevoRadio = (esfera.size + distancia + radio) / 2
    local avance = (nuevoRadio - esfera.size) / distancia
    centro[1] = centro[1] + dx * avance
    centro[2] = centro[2] + dy * avance
    centro[3] = centro[3] + dz * avance
    esfera.size = nuevoRadio
end

local function actualizarEsfera(self)
    self.dreamLib.classes.mesh.updateBoundingSphere(self)
    self.originalBoundingSphere = self.boundingSphere:clone()
    self.boundingSphere.size = 0
    for indice = 1, self.instancesCount do
        ampliarEsfera(self, { self.instanceMesh:getVertex(indice) })
    end
end

function Instancias.nuevas(dream, malla)
    local self = dream:newInstancedMesh(malla)
    self.dreamLib = dream
    self.clear = limpiar
    self.resize = redimensionar
    self.extendBoundingSphere = ampliarEsfera
    self.updateBoundingSphere = actualizarEsfera
    limpiar(self)
    return self
end

return Instancias

-- Orugas y tren de rodaje de los tanques: la oruga se desplaza y las ruedas,
-- el piñón, la rueda guía y los rodillos ruedan según lo que el tanque se ha
-- movido de verdad. Hermana de batalla/lanzamisiles.lua, pero solo con lo de
-- rodar: un tanque no orienta nada, gira por la diferencia de velocidad
-- entre sus orugas (al girar sobre sí mismo, en sentidos opuestos).
--
-- El contrato sale de la tabla `orugas` del .lua del modelo
-- (tools/blender/orugas_exportar.py), en px (1 px = 10 cm):
--   paso       largo de un eslabón; la tesela de la oruga repite cada eslabón
--              en la u (u = recorrido / paso).
--   izquierda, derecha = { oruga, y, giran = { { pieza, radio }, ... } }
--              `y` es la del lado en el juego (la izquierda, negativa).
--
-- Por lado, el recorrido es avance - y * giro del rumbo (como las ruedas del
-- camión): en recta las dos orugas avanzan igual, en curva la de fuera más y
-- girando sobre sí mismo cada una hacia un lado. Cada pieza que gira suma
-- recorrido / radio; la oruga, recorrido / paso a su desplazamiento (en
-- eslabones, de 0 a 1: la tesela se repite). La escena 3D lo pasa por copia
-- al sombreador de la oruga (batalla/dream/oruga.lua).
--
-- Hay un `Orugas` por modelo (`Orugas.de`); por tanque solo números y matrices
-- que se crean una vez.

local Matriz = require('batalla.matriz')

local Orugas = {}
Orugas.__index = Orugas

-- s: suavizado de la velocidad de cada oruga (para el filtro de la escena).
Orugas.suavizado = 0.12

local LADOS = { 'izquierda', 'derecha' }

local porModelo = setmetatable({}, { __mode = 'k' })

--- Las orugas del modelo de vértices `modelo` (Modelos3d.modelo), una vez por
-- modelo; nil si el modelo no tiene orugas animables.
function Orugas.de(modelo)
    if not modelo or not modelo.orugas then
        return nil
    end
    local orugas = porModelo[modelo]
    if not orugas then
        orugas = Orugas.nuevo(modelo)
        porModelo[modelo] = orugas
    end
    return orugas
end

function Orugas.nuevo(modelo)
    local self = setmetatable({}, Orugas)
    local datos = modelo.orugas
    self.modelo = modelo
    self.paso = datos.paso
    self.lados = {}
    -- Las piezas que giran, de los dos lados, en orden: las recorre la escena.
    self.giran = {}
    -- Las dos orugas, en el orden de LADOS.
    self.orugas = {}
    for indice, nombre in ipairs(LADOS) do
        local lado = datos[nombre]
        local piezas = {}
        for _, g in ipairs(lado.giran) do
            local pieza = modelo.piezas[g.pieza]
            if pieza then
                piezas[#piezas + 1] = {
                    nombre = g.pieza,
                    radio = g.radio,
                    pivote = pieza.pivote,
                }
                self.giran[#self.giran + 1] = g.pieza
            end
        end
        self.lados[indice] = {
            y = lado.y,
            oruga = lado.oruga,
            piezas = piezas,
        }
        self.orugas[indice] = lado.oruga
    end
    self.localPieza = {}
    return self
end

--- Números y matrices del tanque `unidad`, la primera vez.
function Orugas:inicializar(unidad)
    unidad.orugas = self
    unidad.desplazamientoOrugas = { 0, 0 }
    unidad.velocidadOrugas = { 0, 0 }
    unidad.giroOrugas = {}
    unidad.matricesOrugas = {}
    for _, nombre in ipairs(self.giran) do
        unidad.giroOrugas[nombre] = 0
        unidad.matricesOrugas[nombre] = {}
    end
    self:recordarPosicion(unidad)
    self:actualizarMatrices(unidad)
end

--- Guarda la posición anterior a la integración física.
function Orugas:recordarPosicion(unidad)
    unidad.anteriorOrugasX = unidad.x
    unidad.anteriorOrugasY = unidad.y
    unidad.anteriorOrugasZ = unidad.z
    unidad.anteriorOrugasRumbo = unidad.rumbo
end

--- Avance con signo a lo largo del casco desde la posición recordada (la
-- subida cuenta: en una cuesta la oruga recorre la pendiente) y giro del
-- rumbo. Lo mismo que Lanzamisiles:medirMovimiento.
local function medir(unidad)
    local dx = unidad.x - unidad.anteriorOrugasX
    local dy = unidad.y - unidad.anteriorOrugasY
    local dz = unidad.z - unidad.anteriorOrugasZ
    local avance = dx * math.cos(unidad.rumbo) + dy * math.sin(unidad.rumbo)
    local distancia = math.sqrt(avance * avance + dz * dz)
    if math.abs(avance) < 0.00001 then
        distancia = 0
    elseif avance < 0 then
        distancia = -distancia
    end
    local giro = (unidad.rumbo - unidad.anteriorOrugasRumbo + math.pi) % (math.pi * 2) - math.pi
    return distancia, giro
end

--- Rodadura de las dos orugas tras la física. Un tanque bloqueado no mueve
-- sus orugas por tener el motor encendido: tiene que desplazarse.
function Orugas:medirMovimiento(unidad, dt)
    local distancia, giro = medir(unidad)
    local mezcla = dt > 0 and math.min(1, dt / Orugas.suavizado) or 0
    local cambio = unidad.x ~= unidad.anteriorOrugasX
        or unidad.y ~= unidad.anteriorOrugasY
        or unidad.z ~= unidad.anteriorOrugasZ
        or unidad.rumbo ~= unidad.anteriorOrugasRumbo
    for indice, lado in ipairs(self.lados) do
        local recorrido = distancia - lado.y * giro
        local eslabones = recorrido / self.paso
        unidad.desplazamientoOrugas[indice] = (unidad.desplazamientoOrugas[indice] + eslabones) % 1
        local velocidad = dt > 0 and eslabones / dt or 0
        local anterior = unidad.velocidadOrugas[indice]
        unidad.velocidadOrugas[indice] = anterior + (velocidad - anterior) * mezcla
        if recorrido ~= 0 then
            for _, pieza in ipairs(lado.piezas) do
                local nombre = pieza.nombre
                unidad.giroOrugas[nombre] = (unidad.giroOrugas[nombre] + recorrido / pieza.radio) % (math.pi * 2)
            end
        end
    end
    -- Parado no cambia nada; empujado de lado, el casco sí aunque no ruede.
    if cambio then
        self:actualizarMatrices(unidad)
    end
end

--- Cada pieza que gira, sobre su pivote y relativa al casco. Tras moverse el
-- casco (Modelos3d.postura) hay que rehacerlas aunque no rueden.
function Orugas:actualizarMatrices(unidad)
    local casco = unidad.casco
    local matrices = unidad.matricesOrugas
    for _, lado in ipairs(self.lados) do
        for _, pieza in ipairs(lado.piezas) do
            local p = pieza.pivote
            Matriz.cabecear(unidad.giroOrugas[pieza.nombre], p[1], p[2], p[3], self.localPieza)
            Matriz.multiplicar(casco, self.localPieza, matrices[pieza.nombre])
        end
    end
end

return Orugas

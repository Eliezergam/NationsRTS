-- Rampa, gatos, pistón y misiles del camión de robot conductor (el dueño,
-- 18-nov: «la animación de la rampa del lanzamisiles, la misma del anterior
-- camión»). Los mismos tiempos y la misma secuencia que el camión viejo
-- (Tropas:actualizarLanzacohetes): apoya los gatos (Tropas.tiempoGatos),
-- sube la rampa hasta su elevación en 3 s, dispara los misiles de uno en uno
-- (Tropas.entreMisilesRampa) en el orden de ArticulacionCamion.ordenMisiles,
-- baja la rampa en 2,5 s y recoge los gatos. Los misiles salen con
-- Tropas:lanzarMisilRobot: el mismo misil, estela, humo y sonido.
--
-- El conductor decide (pilotar.lua):
--   camion:setDisparar(x, y)  despliega y dispara a (x, y) m
-- Lo de ahora, en camion.datos.rampaMisiles: estado ('recogido',
-- 'apoyando', 'subiendo', 'fuego', 'bajando', 'recogiendo'), elevacion
-- (grados), gatos (0-1), cargados, y `ultimo`: el último misil lanzado
-- (el de batalla/tropas.lua, para seguirlo con la mirada).
--
-- El camión necesita `camion.tropas` (lo pone la escena) para lanzar.

local Nucleo = require('robots.nucleo')
local ArticulacionCamion = require('batalla.articulacion_camion')
local Tropas = require('batalla.tropas')
local Robot = Nucleo.Robot

local RampaMisiles = {}

-- Los números del contrato del camión viejo (camion_misiles_synty4.lua,
-- demasiado grande para cargarlo solo por esto): elevación en grados y los
-- cuatro gatos, que bajan de 17,6 a 9,6 px (0,8 m).
RampaMisiles.elevacion = 35
RampaMisiles.gatos = { 'gatoDelanteraIzquierda', 'gatoDelanteraDerecha', 'gatoTraseraIzquierda', 'gatoTraseraDerecha' }
RampaMisiles.bajadaGatos = -0.8 -- m
RampaMisiles.subir = 3 -- s hasta arriba
RampaMisiles.bajar = 2.5
RampaMisiles.esperaPrimero = 0.5 -- s arriba antes del primer misil
-- Dirección de reposo de las dos piezas del pistón (las del contrato viejo).
RampaMisiles.pistonBase = { 0.90374, 0.42809 }
RampaMisiles.pistonUnion = 3.2 -- m a lo largo de la rampa

local PX_POR_M = 10

function RampaMisiles.prerequisitos(self)
    return self:getTienePieza('rampaLanzador')
end

function RampaMisiles.onLoad(self)
    local d = self.datos.rampaMisiles
    d.maxima = RampaMisiles.elevacion
    d.estado, d.elevacion, d.gatos, d.espera = 'recogido', 0, 0, 0
    d.rampa = self:getPieza('rampaLanzador')
    local m = d.rampa.datos.matriz
    d.rampaX, d.rampaZ = m[4], m[12]
    d.base = self:getPieza('pistonRampaBase')
    d.vastago = self:getPieza('pistonRampaVastago')
    m = d.base.datos.matriz
    d.baseX, d.baseZ = m[4], m[12]
    d.listaGatos = {}
    for _, nombre in ipairs(RampaMisiles.gatos) do
        if self:getTienePieza(nombre) then
            d.listaGatos[#d.listaGatos + 1] = { pieza = self:getPieza(nombre), bajada = RampaMisiles.bajadaGatos }
        end
    end
    d.misiles = {}
    for _, nombre in ipairs(ArticulacionCamion.ordenMisiles) do
        if self:getTienePieza(nombre) then
            d.misiles[#d.misiles + 1] = self:getPieza(nombre)
        end
    end
    d.cargados = #d.misiles
end

--- Despliega y dispara a (x, y) m todo lo que lleva.
function Robot:setDisparar(x, y)
    local d = self.datos.rampaMisiles
    d.blanco = { x, y }
    if d.estado == 'recogido' and d.cargados > 0 then
        d.estado = 'apoyando'
    end
end

local function lanzar(self, d)
    local k = #d.misiles - d.cargados + 1
    local pieza = d.misiles[k]
    d.cargados = d.cargados - 1
    local t = self.tropas
    local m = pieza:getMatriz()
    if not t or not m or not d.blanco then
        return
    end
    -- Del marco de los robots (m, y al norte) al del juego (px, y al sur).
    local x, y, z = m[4] * PX_POR_M, -m[8] * PX_POR_M, m[12] * PX_POR_M
    local dx, dy, dz = m[1], -m[5], m[9]
    local lado = { m[2], -m[6], m[10] }
    d.ultimo = t:lanzarMisilRobot(self, self.bando or 1, x, y, z, dx, dy, dz, lado, d.blanco[1] * PX_POR_M, -d.blanco[2] * PX_POR_M)
    d.disparos = (d.disparos or 0) + 1
    print(('CAMION misil %d de %d'):format(k, #d.misiles))
end

function RampaMisiles.onUpdate(self, dt)
    local d = self.datos.rampaMisiles
    d.espera = d.espera - dt
    if d.estado == 'apoyando' then
        d.gatos = math.min(1, d.gatos + dt / Tropas.tiempoGatos)
        if d.gatos >= 1 then
            d.estado = 'subiendo'
        end
    elseif d.estado == 'subiendo' then
        d.elevacion = math.min(d.maxima, d.elevacion + d.maxima * dt / RampaMisiles.subir)
        if d.elevacion >= d.maxima then
            d.estado = 'fuego'
            d.espera = RampaMisiles.esperaPrimero
        end
    elseif d.estado == 'fuego' and d.espera <= 0 then
        if d.cargados > 0 then
            lanzar(self, d)
            d.espera = Tropas.entreMisilesRampa
        else
            d.estado = 'bajando'
        end
    elseif d.estado == 'bajando' then
        d.elevacion = math.max(0, d.elevacion - d.maxima * dt / RampaMisiles.bajar)
        if d.elevacion <= 0 then
            d.estado = 'recogiendo'
        end
    elseif d.estado == 'recogiendo' then
        d.gatos = math.max(0, d.gatos - dt / Tropas.tiempoGatos)
        if d.gatos <= 0 then
            d.estado = 'recogido'
        end
    end
end

function RampaMisiles.onPose(self)
    local d = self.datos.rampaMisiles
    local e = math.rad(d.elevacion)
    d.rampa:setGiro('y', -e, 'elevar')
    -- Pistón: la base apunta a la unión en la rampa y el vástago a la base.
    local ux = d.rampaX + math.cos(e) * RampaMisiles.pistonUnion - d.baseX
    local uz = d.rampaZ + math.sin(e) * RampaMisiles.pistonUnion - d.baseZ
    local reposo = math.atan2(RampaMisiles.pistonBase[2], RampaMisiles.pistonBase[1])
    local ahora = math.atan2(uz, ux)
    d.base:setGiro('y', -(ahora - reposo), 'apuntar')
    d.vastago:setGiro('y', -(ahora - reposo - e), 'apuntar')
    local g = d.gatos
    local suave = g * g * (3 - 2 * g)
    for _, gato in ipairs(d.listaGatos) do
        gato.pieza:setDesplazamiento(0, 0, gato.bajada * suave, 'bajar')
    end
    local salieron = #d.misiles - d.cargados
    for k, p in ipairs(d.misiles) do
        p:setVisible(k > salieron)
    end
end

Nucleo.registrarEspecializacion('rampaMisiles', RampaMisiles)
return RampaMisiles

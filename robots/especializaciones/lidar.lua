-- Lidar del robot: cada 0,1 s lanza 120 rayos alrededor (cada 3°) en cinco
-- capas de altura, como un lidar 3D de pocas capas: a 0,08 m (bajos), a 0,25 m (la base), a 0,4 m, a
-- 0,9 m (mesas, baldas) y a 1,6 m (largueros de los racks, que la base no
-- ve pero chocarían con el cuerpo). De cada rayo sabe a qué distancia choca
-- y lo que toca (en el almacén, su tipo: rack, muro, mesa, caja...; en la
-- batalla, las etiquetas de su colisión), y con eso aprende el mapa del sitio
-- si el tipo de robot le da sus `limites` (almacen/robots/mapa.lua).
--
-- Es de todos los robots: cada escena pone en su gestor la opción `sensor`,
-- function(x, y, z, angulo, alcance, ignorar) -> distancia, tipo, objeto: un
-- rayo horizontal a `z` m sobre el suelo (tipo nil si no toca nada).
--
-- Órdenes que añade al robot:
--   robot:getRayos()          los del último barrido: { angulo, distancia,
--                             choca, tipo, objeto, z } por rayo y capa
--   robot:getVisto()          lo que tiene alrededor, por tipo:
--                             { tipo = { distancia, angulo, veces } }
--   robot:getMapa()           el mapa aprendido (mapa.lua: getOcupado,
--                             getTipo, getRuta...)
--   robot:getDistanciaDelante(ancho, capa)  lo más cerca que tiene delante en
--                             un pasillo de `ancho` m (solo esa capa si se da)

---@class Lidar : Robot
local Lidar = {}
local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

Lidar.rayos = 120
-- 18-nov: una capa a ras de suelo (0,08 m, como el sensor de bajos de un
-- robot real): las cajas de munición del suelo de la fábrica miden 15-20 cm,
-- la capa de 0,25 pasaba por encima y el soldado se atascaba contra ellas.
-- Y otra a 0,4 m: la balda baja de las estanterías (0,32-0,42 m) choca con
-- la base (fisica.lua: de 0,03 a 0,45 m) y ninguna capa la veía.
-- 21-nov: una a 1,05 m, por encima del tablero de las mesas de recepción
-- (0,90 m): así ve de una pasada las cajas que hay encima (0,90-1,15 m) sin
-- que el tablero se las tape (el dueño: «que las vea en un segundo»).
Lidar.capas = { 0.08, 0.25, 0.4, 0.9, 1.05, 1.6 }
Lidar.alcance = 12
-- Con `alternar`, cada barrido va desplazado medio paso respecto al anterior
-- (como el desfase de un lidar que gira): lo que cabe entre dos rayos de un
-- barrido lo toca el siguiente.
Lidar.alternar = false
Lidar.periodo = 0.1
-- Del centro de la base al sensor (está en el frente de la base).
Lidar.adelante = 0.0
-- Límites del mapa que aprende (m); sin ellos no hace mapa (los pone cada
-- tipo de robot: almacen/robots/tipos/).
Lidar.limites = nil

function Lidar:onLoad()
    local d = self.datos.lidar
    d.reloj = 0
    d.rayos = {}
    d.visto = {}
    local L = self:getAjustes('lidar').limites
    if L then
        d.mapa = require('almacen.robots.mapa').nuevo(L[1], L[2], L[3], L[4])
    end
    self:barrer()
end

function Lidar:onUpdate(dt)
    local d = self.datos.lidar
    d.reloj = d.reloj + dt
    local periodo = self:getAjustes('lidar').periodo
    if d.reloj >= periodo then
        d.reloj = d.reloj - periodo
        self:barrer()
    end
end

--- Un barrido entero: rayos, lo visto y el mapa.
function Robot:barrer()
    local d = self.datos.lidar
    local L = self:getAjustes('lidar')
    local llevando = self.getLlevando and self:getLlevando()
    local sensor = self.gestor.opciones.sensor
    local x = self.x + math.cos(self.rumbo) * L.adelante
    local y = self.y + math.sin(self.rumbo) * L.adelante
    local rayos = {}
    local visto = {}
    local desfase = 0
    if L.alternar then
        d.vuelta = not d.vuelta
        desfase = d.vuelta and math.pi / L.rayos or 0
    end
    for k = 0, L.rayos - 1 do
        local angulo = self.rumbo + desfase + k * 2 * math.pi / L.rayos
        -- Para el mapa vale el choque más cercano de las capas.
        local cerca, tipoCerca
        for _, z in ipairs(L.capas) do
            local distancia, tipo, objeto = sensor(x, y, z, angulo, L.alcance, llevando)
            local choca = tipo ~= nil
            rayos[#rayos + 1] = { angulo = angulo, distancia = distancia, choca = choca, tipo = tipo, objeto = objeto, z = z, x = x, y = y }
            if choca then
                if objeto then
                    d.objetos = d.objetos or {}
                    d.objetos[objeto] = true
                end
                if not cerca or distancia < cerca then
                    cerca, tipoCerca = distancia, tipo
                end
                local v = visto[tipo]
                if not v then
                    visto[tipo] = { distancia = distancia, angulo = angulo, veces = 1, objeto = objeto }
                else
                    v.veces = v.veces + 1
                    if distancia < v.distancia then
                        v.distancia, v.angulo = distancia, angulo
                    end
                end
            end
        end
        if d.mapa then
            d.mapa:setRayo(x, y, angulo, cerca or L.alcance, cerca ~= nil, tipoCerca)
        end
    end
    d.rayos = rayos
    d.visto = visto
end

--- Los objetos (muebles, cajas...) que ha tocado el lidar alguna vez:
-- { [objeto] = true }.
function Robot:getObjetosLidar()
    return self.datos.lidar.objetos or {}
end

function Robot:getRayos()
    return self.datos.lidar.rayos
end

function Robot:getVisto()
    return self.datos.lidar.visto
end

function Robot:getMapa()
    return self.datos.lidar.mapa
end

--- Lo más cerca que hay delante en un pasillo de `ancho` m (por los
-- rayos del último barrido); `alcance` si nada.
function Robot:getDistanciaDelante(ancho, capa)
    local mejor = self:getAjustes('lidar').alcance
    for _, r in ipairs(self.datos.lidar.rayos) do
        if r.choca and (not capa or math.abs(r.z - capa) < 0.01) then
            local a = r.angulo - self.rumbo
            local adelante = math.cos(a) * r.distancia
            local lado = math.abs(math.sin(a) * r.distancia)
            if adelante > 0 and lado < ancho / 2 and adelante < mejor then
                mejor = adelante
            end
        end
    end
    return mejor
end

Nucleo.registrarEspecializacion('lidar', Lidar)
return Lidar

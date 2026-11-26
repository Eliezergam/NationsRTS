-- Lote de un vehículo articulado (Valeria): las mallas fundidas de un nivel
-- de detalle (batalla/dream/malla_articulada.lua), una copia por vehículo y
-- las matrices de sus piezas en la tabla del cuadro
-- (batalla/dream/tabla_piezas.lua). Un lote por variante: normal, destruido
-- (quemado) y cada paso del fundido entre niveles (tramado). Las partes del
-- lote (una por material y sombra) comparten la lista de vehículos y sus
-- filas: van en el mismo orden de copia.
--
-- Por cuadro: `anadir` apunta el vehículo, `subir` escribe sus filas y la
-- esfera que envuelve todas sus piezas (para el recorte de 3Dream) y
-- `dibujar` manda las partes.

local Conversor = require('batalla.dream.conversor')
local Instancias = require('batalla.dream.instancias')
local Lanzamisiles = require('batalla.lanzamisiles')

local LoteArticulado = {}
LoteArticulado.__index = LoteArticulado

--- Lote de las mallas fundidas `fundida` con sitio para `capacidad`
-- vehículos. Opciones:
--   activos   lista donde se apunta el lote al recibir su primer vehículo
--   quemado   ennegrecido (el vehículo destruido, como instanciarCamion)
--   alfa      de tramado: el fundido al cambiar de nivel
function LoteArticulado.nuevo(dream, fundida, capacidad, opciones)
    local self = setmetatable({}, LoteArticulado)
    self.usadas = fundida.usadas
    self.radios = fundida.radios
    self.activos = opciones.activos
    self.capacidad = capacidad
    self.unidades = {}
    self.cantidad = 0
    self.partes = {}
    for _, parte in ipairs(fundida.partes) do
        local lote = Instancias.nuevas(dream, parte.malla)
        if opciones.alfa or opciones.quemado then
            local material = lote:getMaterial():clone()
            local c = material.color or { 1, 1, 1, 1 }
            if opciones.quemado then
                -- Con su textura, como el tanque averiado; sin brillo
                -- (`piezasBatalla`, batalla/dream/piezas_lote.lua).
                material:setColor(0.18, 0.15, 0.13, c[4])
                material:setRoughness(1)
                material:setMetallic(0.05)
                material.quemado = true
                -- Los faros, apagados.
                material:setEmissionTexture(nil)
                material:setEmission(0, 0, 0)
                c = material.color
            end
            if opciones.alfa then
                material:setColor(c[1], c[2], c[3], opciones.alfa)
                material:setDither()
            end
            lote:setMaterial(material)
        end
        lote:resize(capacidad)
        lote:setShadowVisibility(parte.sombra)
        -- Se mueven por su cuenta, pero cada pieza lleva su matriz del cuadro
        -- anterior (TablaPiezas:anterior): el AA temporal sabe cuánto se movió
        -- cada píxel y reproyecta su historia como la del suelo
        -- (batalla/dream/temporal.lua). Con `movil`, la mezcla con la historia
        -- bajaba a la mitad y el subpíxel del AA se veía temblar en la chapa.
        lote.movil = false
        lote.filaPiezas = 0
        self.partes[#self.partes + 1] = lote
    end
    return self
end

--- Apunta el vehículo `unidad` (con `matricesLanza`) para este cuadro.
function LoteArticulado:anadir(unidad)
    local n = self.cantidad
    if n >= self.capacidad then
        return false
    end
    n = n + 1
    self.cantidad = n
    self.unidades[n] = unidad
    if n == 1 and self.activos then
        self.activos[#self.activos + 1] = self
    end
    return true
end

--- Sin vehículos (empieza el cuadro).
function LoteArticulado:vaciar()
    for k = self.cantidad, 1, -1 do
        self.unidades[k] = nil
    end
    self.cantidad = 0
end

--- Escribe en `tabla` las filas de los vehículos del cuadro y pone en cada
-- parte su primera fila, su número de copias y su esfera. Devuelve cuántos
-- vehículos caben.
function LoteArticulado:subir(tabla, conversor)
    local e = Conversor.escala
    local cx, cy = conversor.cx, conversor.cy
    local usadas = self.usadas
    local radios = self.radios
    local primera
    local copias = 0
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for k = 1, self.cantidad do
        local unidad = self.unidades[k]
        local fila, puntero = tabla:reservar()
        if not fila then
            break
        end
        primera = primera or fila
        copias = copias + 1
        local matrices = unidad.matricesLanza
        for _, usada in ipairs(usadas) do
            local nombre = usada.nombre
            -- Seis texeles por pieza: la matriz de ahora y la del cuadro anterior.
            local o = puntero + usada.columna * 24
            local m
            if Lanzamisiles.visible(unidad, nombre) then
                m = matrices[nombre]
            end
            if m and m[1] then
                local x, y, z = (m[4] - cx) * e, m[12] * e, (m[8] - cy) * e
                o[0], o[1], o[2], o[3] = m[1], m[9], m[5], x
                o[4], o[5], o[6], o[7] = m[3], m[11], m[7], y
                o[8], o[9], o[10], o[11] = m[2], m[10], m[6], z
                tabla:anterior(unidad, nombre, o, o + 12)
                -- La columna más larga del giro: la escala de la pieza.
                local escala2 = math.max(
                    m[1] * m[1] + m[5] * m[5] + m[9] * m[9],
                    m[2] * m[2] + m[6] * m[6] + m[10] * m[10],
                    m[3] * m[3] + m[7] * m[7] + m[11] * m[11]
                )
                local r = radios[usada.columna] * math.sqrt(escala2)
                minX, maxX = math.min(minX, x - r), math.max(maxX, x + r)
                minY, maxY = math.min(minY, y - r), math.max(maxY, y + r)
                minZ, maxZ = math.min(minZ, z - r), math.max(maxZ, z + r)
            else
                for c = 0, 23 do
                    o[c] = 0
                end
            end
        end
    end
    local radio = 0
    if copias > 0 and minX <= maxX then
        local dx, dy, dz = maxX - minX, maxY - minY, maxZ - minZ
        radio = math.sqrt(dx * dx + dy * dy + dz * dz) * 0.5
    end
    for _, lote in ipairs(self.partes) do
        lote.instancesCount = copias
        lote.filaPiezas = primera or 0
        lote.matricesPiezas = tabla.imagen
        local esfera = lote.boundingSphere
        local centro = esfera.center
        if radio > 0 then
            centro[1] = (minX + maxX) * 0.5
            centro[2] = (minY + maxY) * 0.5
            centro[3] = (minZ + maxZ) * 0.5
        end
        esfera.size = radio
    end
    return copias
end

--- Manda a 3Dream las partes con copias (tras TablaPiezas:subir).
function LoteArticulado:dibujar(dream)
    for _, lote in ipairs(self.partes) do
        if lote.instancesCount > 0 and lote.boundingSphere.size > 0 then
            dream:draw(lote)
        end
    end
end

return LoteArticulado

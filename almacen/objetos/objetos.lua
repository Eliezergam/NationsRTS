-- Objetos del almacén: lo que el robot puede coger (cajas con puntos de
-- agarre), los muebles donde se apoyan (huecos) y lo que es demasiado pesado
-- para él pero ya tiene sus puntos de agarre (los contenedores de misiles,
-- para el robot pesado). Global, como GestorRobots.
--
--   local caja = GestorObjetos.crear('cajaRobot', x, y, z, rumbo)
--   caja:getPuntosAgarre()   -- dónde pone las pinzas, en el almacén
--   mesa:getHuecos()         -- dónde se apoyan las cosas
--
-- Medidas: metros, ejes del almacén (z arriba), rumbo en radianes. Los
-- datos de cada tipo: assets/almacen/objetos_datos.lua
-- (tools/blender/objetos_almacen.py --glb). API: almacen/robots/API.md.

local dream = require('lib.3DreamEngine')
local PiezaRobot = require('almacen.robots.pieza')
local LoteCopias = require('batalla.dream.lote_copias')

local MODELO = 'assets/almacen/objetos'
local DATOS = 'assets/almacen/objetos_datos.lua'

GestorObjetos = GestorObjetos or {}
local lista = {}
local modeloBase
local tipos
local mallasExternas = {}
-- Todas las copias en una llamada por malla (batalla/dream/lote_copias.lua).
local copias
-- Modelo de origen de cada tipo, guardado la primera vez: `object:clone()`
-- de 3Dream le cambia las piezas al modelo que se clona en cada copia.
local fuentes = {}

-- Contenedor de misil: sin malla aquí (lo dibuja la escena). Cuatro
-- orejetas de izado arriba, cerca de las puntas (ejes del contenedor: x a lo
-- ancho, y a lo largo). Pesa demasiado para el robot del almacén.
local TIPOS_FIJOS = {
    -- La caja de un misil (concha de 9 x 0,85 x 0,85 m a lo largo de su y,
    -- origen en el suelo de los patines); la malla viene del modelo del
    -- almacén (setMallaExterna). Puntos de agarre: para las garras del robot
    -- grande, el cuerpo a la distancia entre sus dos garras (2,44 m),
    -- cerrando de arriba abajo (giroGarra: la muñeca gira 90°), y las dos
    -- orejetas de izado de la tapa (grúa).
    contenedorMisil = {
        nombre = 'caja de misil', movible = true, peso = 1100, sinMalla = true,
        tamano = { 0.85, 9.0, 0.97 },
        cajas = { { -0.47, -4.5, 0, 0.47, 4.5, 0.97 } },
        puntos = {
            { 'costadoA', 0, -1.22, 0.485, eje = { 0, 0, 1 }, grosor = 0.85, mano = 'garra', giroGarra = math.pi / 2 },
            { 'costadoB', 0, 1.22, 0.485, eje = { 0, 0, 1 }, grosor = 0.85, mano = 'garra', giroGarra = math.pi / 2 },
            { 'cancamoA', 0, -2.2, 1.0, eje = { 1, 0, 0 }, grosor = 0.06, mano = 'grua' },
            { 'cancamoB', 0, 2.2, 1.0, eje = { 1, 0, 0 }, grosor = 0.06, mano = 'grua' },
        },
    },
    -- El misil (8,32 m a lo largo de su y, la ojiva hacia +y, origen en el
    -- centro de su eje): la malla de su etapa la pone la línea de montaje
    -- (almacen/fabrica.lua, Objeto:setMalla). Puntos: las bandas de manejo
    -- para las eslingas de la grúa y, para las garras del robot grande, el
    -- cuerpo a la distancia entre ellas.
    misil = {
        nombre = 'misil', movible = true, peso = 2100, sinMalla = true,
        tamano = { 0.45, 8.32, 0.45 },
        cajas = { { -0.23, -4.16, -0.23, 0.23, 4.16, 0.23 } },
        puntos = {
            { 'bandaA', 0, -1.6, 0.24, eje = { 1, 0, 0 }, grosor = 0.45, mano = 'grua' },
            { 'bandaB', 0, 1.6, 0.24, eje = { 1, 0, 0 }, grosor = 0.45, mano = 'grua' },
            { 'cuerpoA', 0, -1.22, 0, eje = { 0, 0, 1 }, grosor = 0.45, mano = 'garra', giroGarra = math.pi / 2 },
            { 'cuerpoB', 0, 1.22, 0, eje = { 0, 0, 1 }, grosor = 0.45, mano = 'garra', giroGarra = math.pi / 2 },
        },
    },
}

---@class ObjetoAlmacen
local Objeto = {}
Objeto.__index = Objeto

local function cargar()
    if tipos then
        return
    end
    tipos = love.filesystem.load(DATOS)()
    for k, v in pairs(TIPOS_FIJOS) do
        tipos[k] = v
    end
    modeloBase = dream:loadObject(MODELO, { decodeBlenderNames = false })
    fuentes = {}
end

local function matrizDe(x, y, z, rumbo)
    local c, s = math.cos(rumbo), math.sin(rumbo)
    return { c, -s, 0, x, s, c, 0, y, 0, 0, 1, z, 0, 0, 0, 1 }
end

--- Crea un objeto de tipo `tipo` (cajaRobot, cajaMunicion, mesaRecepcion,
-- estanteriaRobot) con su origen en (x, y, z) mirando a `rumbo`.
---@return ObjetoAlmacen
function GestorObjetos.crear(tipo, x, y, z, rumbo)
    cargar()
    local datos = tipos[tipo]
    if not datos then
        error('no hay objetos de tipo ' .. tostring(tipo), 2)
    end
    local self = setmetatable({}, Objeto)
    self.tipo = tipo
    self.datos = datos
    self.matriz = matrizDe(x, y, z or 0, rumbo or 0)
    self.huecosOcupados = {}
    local externa = mallasExternas[tipo]
    if externa then
        self.malla = externa.cuerpo:clone()
        self.mallaTapa = externa.tapa and externa.tapa:clone()
        -- Los modelos de origen (compartidos por todas las copias): se
        -- dibujan por lotes (los clones de 3Dream copian sus mallas).
        self.fuente = externa.cuerpo
        self.fuenteTapa = externa.tapa
        self.tapa = 0 -- rad que está abierta
    elseif not datos.sinMalla then
        fuentes[tipo] = fuentes[tipo] or modeloBase.objects[tipo]
        self.fuente = fuentes[tipo]
        self.modelo = modeloBase:clone()
        self.malla = self.modelo.objects[tipo]
    end
    lista[#lista + 1] = self
    self.id = #lista
    return self
end

--- Mallas de un tipo que vienen de otro modelo (la caja de misil está en
-- el del almacén: `plantillaCaja` y `plantillaCajaTapa`). `tapa` y
-- `bisagra` ({ x, z } del eje, en ejes del objeto) para las que se abren.
function GestorObjetos.setMallaExterna(tipo, cuerpo, tapa, bisagra)
    mallasExternas[tipo] = { cuerpo = cuerpo, tapa = tapa, bisagra = bisagra }
end

--- Un tipo de objeto nuevo desde el código (los bloques enemigos de
-- práctica: almacen/blancos.lua). `datos` como los de objetos_datos.lua.
function GestorObjetos.registrarTipo(tipo, datos)
    cargar()
    tipos[tipo] = datos
end

function GestorObjetos.getObjetos()
    return lista
end

--- Los objetos a menos de `radio` m de (x, y).
function GestorObjetos.getCercanos(x, y, radio)
    local r = {}
    for _, o in ipairs(lista) do
        local ox, oy = o:getPosicion()
        if (ox - x) ^ 2 + (oy - y) ^ 2 <= radio * radio then
            r[#r + 1] = o
        end
    end
    return r
end

--- Lo quita del almacén (y de su hueco).
function GestorObjetos.quitar(objeto)
    objeto:setSoltar()
    for k, o in ipairs(lista) do
        if o == objeto then
            table.remove(lista, k)
            return
        end
    end
end

function GestorObjetos.vaciar()
    lista = {}
end

-- De ejes del almacén (z arriba) a los de 3Dream (y arriba): x, z, -y.
local function aDream(m)
    return dream.mat4({
        m[1], m[3], -m[2], m[4],
        m[9], m[11], -m[10], m[12],
        -m[5], -m[7], m[6], -m[8],
        0, 0, 0, 1,
    })
end
GestorObjetos.aDream = aDream

function GestorObjetos.dibujar()
    copias = copias or LoteCopias.nuevo(dream)
    copias:empezar()
    for _, o in ipairs(lista) do
        if o.malla then
            copias:anadir(o.fuente or o.malla, aDream(o.matriz))
        end
        if o.mallaTapa then
            -- La tapa gira sobre su eje (a lo largo de y del objeto).
            local b = mallasExternas[o.tipo].bisagra
            local m = o.matriz
            if o.tapa ~= 0 then
                local c, s = math.cos(-o.tapa), math.sin(-o.tapa)
                local giro = { c, 0, s, b[1] - c * b[1] - s * b[2], 0, 1, 0, 0, -s, 0, c, b[2] + s * b[1] - c * b[2], 0, 0, 0, 1 }
                m = Objeto.multiplicar(m, giro)
            end
            copias:anadir(o.fuenteTapa or o.mallaTapa, aDream(m))
        end
    end
    copias:dibujar()
end

-- Qué es -------------------------------------------------------------------------

function Objeto:getTipo()
    return self.tipo
end

--- Nombre para leer: 'caja de plástico'...
function Objeto:getNombre()
    return self.datos.nombre
end

--- Kilos.
function Objeto:getPeso()
    return self.datos.peso or 0
end

--- `true` si se puede llevar (aunque quizá no este robot: mira el peso).
function Objeto:getMovible()
    return self.datos.movible == true
end

--- x, y, z de su origen (el suelo bajo su centro).
function Objeto:getPosicion()
    local m = self.matriz
    return m[4], m[8], m[12]
end

--- Hacia dónde mira su +x (radianes).
function Objeto:getRumbo()
    return math.atan2(self.matriz[5], self.matriz[1])
end

--- Su matriz en el almacén (4x4 por filas; solo leer).
function Objeto:getMatriz()
    return self.matriz
end

--- Quién lo lleva (un robot) o nil.
function Objeto:getLlevadoPor()
    return self.llevadoPor
end

--- El mueble y el número de hueco donde está apoyado, o nil.
function Objeto:getApoyadoEn()
    return self.apoyadoEn, self.huecoNumero
end

--- Un punto (x, y, z) del objeto, en el almacén.
function Objeto:getPunto(x, y, z)
    local m = self.matriz
    return m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8], m[9] * x + m[10] * y + m[11] * z + m[12]
end

--- Una dirección del objeto, en el almacén.
function Objeto:getDireccion(x, y, z)
    local m = self.matriz
    return m[1] * x + m[2] * y + m[3] * z, m[5] * x + m[6] * y + m[7] * z, m[9] * x + m[10] * y + m[11] * z
end

--- Los puntos de agarre en el almacén: { nombre, x, y, z, eje = {x, y, z}
-- (hacia donde cierran los dedos), grosor (m), mano, local = el dato }.
function Objeto:getPuntosAgarre()
    local r = {}
    for _, p in ipairs(self.puntosPropios or self.datos.puntos or {}) do
        local x, y, z = self:getPunto(p[2], p[3], p[4])
        local ex, ey, ez = self:getDireccion(p.eje[1], p.eje[2], p.eje[3])
        r[#r + 1] = { nombre = p[1], x = x, y = y, z = z, eje = { ex, ey, ez }, grosor = p.grosor, mano = p.mano, redondo = p.redondo, giroGarra = p.giroGarra, ['local'] = p }
    end
    return r
end

--- Los huecos de apoyo en el almacén: { x, y, z, rumbo, numero, ocupado }.
function Objeto:getHuecos()
    local r = {}
    local rumbo = self:getRumbo()
    for k, h in ipairs(self.datos.huecos or {}) do
        local x, y, z = self:getPunto(h[1], h[2], h[3])
        r[k] = { x = x, y = y, z = z, rumbo = rumbo, numero = k, ocupado = self.huecosOcupados[k], mueble = self }
    end
    return r
end

--- Un hueco (ver getHuecos).
function Objeto:getHueco(numero)
    return self:getHuecos()[numero]
end

--- El primer hueco libre (o nil).
function Objeto:getHuecoLibre()
    for _, h in ipairs(self:getHuecos()) do
        if not h.ocupado then
            return h
        end
    end
end

--- Cajas de colisión en el almacén (alineadas con los ejes):
-- { x0, y0, z0, x1, y1, z1 }.
function Objeto:getCajasColision()
    local r = {}
    for _, c in ipairs(self.cajasPropias or self.datos.cajas or {}) do
        local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
        for i = 0, 7 do
            local px = (i % 2 == 0) and c[1] or c[4]
            local py = (math.floor(i / 2) % 2 == 0) and c[2] or c[5]
            local pz = (i < 4) and c[3] or c[6]
            local x, y, z = self:getPunto(px, py, pz)
            x0, y0, z0 = math.min(x0, x), math.min(y0, y), math.min(z0, z)
            x1, y1, z1 = math.max(x1, x), math.max(y1, y), math.max(z1, z)
        end
        r[#r + 1] = { x0, y0, z0, x1, y1, z1 }
    end
    return r
end

-- Cambiar -----------------------------------------------------------------------

--- Le pone esta malla (objeto de 3DreamEngine; se copia): el misil
-- cambia de malla en cada etapa de la línea de montaje.
function Objeto:setMalla(malla)
    self.malla = malla and malla:clone() or nil
    self.fuente = malla
end

--- Abre la tapa `angulo` rad (0: cerrada). Solo las cajas con tapa.
function Objeto:setTapa(angulo)
    self.tapa = angulo
end

function Objeto:getTapa()
    return self.tapa or 0
end

--- Lleva un misil dentro (true) o está vacía.
function Objeto:setLleno(lleno)
    self.lleno = lleno and true or nil
end

function Objeto:getLleno()
    return self.lleno == true
end

--- Lo pone de golpe con esta matriz (lo usa el robot al llevarlo).
function Objeto:setMatriz(m)
    self.matriz = m
end

--- Lo pone en (x, y, z) mirando a `rumbo`.
function Objeto:setPosicion(x, y, z, rumbo)
    self.matriz = matrizDe(x, y, z, rumbo or self:getRumbo())
end

--- Lo apoya en el hueco `numero` del mueble `mueble`.
function Objeto:setApoyar(mueble, numero)
    self:setSoltar()
    local h = mueble:getHueco(numero)
    self:setPosicion(h.x, h.y, h.z, h.rumbo)
    mueble.huecosOcupados[numero] = self
    self.apoyadoEn, self.huecoNumero = mueble, numero
end

--- Deja libre el hueco donde estaba.
function Objeto:setSoltar()
    if self.apoyadoEn then
        self.apoyadoEn.huecosOcupados[self.huecoNumero] = nil
        self.apoyadoEn, self.huecoNumero = nil, nil
    end
end

Objeto.multiplicar = PiezaRobot.multiplicar
GestorObjetos.Objeto = Objeto
return GestorObjetos

-- El almacén de una nación, para los scripts: el mismo estilo que los
-- vehículos (batalla/vehiculos/API.md). `get...` devuelve algo y no cambia
-- nada; `set...` cambia algo y no devuelve nada. Todo con `:`.
--
--   local almacen = Almacen.getDelJugador()
--   if almacen and almacen:getMisiles() == 0 then
--       -- sin misiles en el almacén: no se dispara
--   end
--
-- Los datos son de la simulación (mundo/simulacion/almacen.lua): cada cambio
-- va como una orden (`ejecutar`), igual que las del jugador, para que se
-- guarde y valga en línea. Ver almacen/API.md y diseno/almacen.md.

-- Global, como GestorVehiculos: cualquier script lo usa sin `require`.
---@class Almacen
---@field nacion integer nación dueña (interno: usa getNacion)
Almacen = Almacen or {}
Almacen.__index = Almacen

-- De dónde sale la partida en curso: dos funciones que pone main.lua
-- (Almacen.instalar). Se preguntan en cada uso, así que al cargar o empezar
-- otra partida no queda nada viejo.
local simulacionDe = function() return nil end
local jugadorDe = function() return nil end
-- Un objeto por nación y partida (se reutiliza: comparar con == funciona).
local porNacion = {}
local simDeLaCache

--- Engancha la partida. Lo llama main.lua una vez.
---@param getSim fun(): table|nil la simulación en curso (mundo/simulacion.lua)
---@param getJugador fun(): integer|nil la nación del jugador (nil si solo se mira)
function Almacen.instalar(getSim, getJugador)
    simulacionDe = getSim
    jugadorDe = getJugador
end

local function simulacion()
    local sim = simulacionDe()
    if sim ~= simDeLaCache then
        simDeLaCache = sim
        porNacion = {}
    end
    return sim
end

--- El almacén de la nación `nid` (nil si no existe la nación o no hay partida).
---@param nid integer
---@return Almacen|nil
function Almacen.getDeNacion(nid)
    local sim = simulacion()
    if not (sim and nid and sim:almacenDeMisiles(nid)) then
        return nil
    end
    local almacen = porNacion[nid]
    if not almacen then
        almacen = setmetatable({ nacion = nid }, Almacen)
        porNacion[nid] = almacen
    end
    return almacen
end

--- Siglas de la nación dueña y su color, para el pecho de los robots
-- (almacen/robots/especializaciones/siglas.lua): las tres primeras letras de
-- su nombre en mayúsculas. nil si no hay partida.
---@return string|nil, table|nil
function Almacen:getSiglas()
    local sim = simulacion()
    local n = sim and sim.estado and sim.estado.naciones[self.nacion]
    if not (n and n.nombre) then
        return nil
    end
    local utf8 = require('utf8')
    local fin = utf8.offset(n.nombre, 4)
    local siglas = (fin and n.nombre:sub(1, fin - 1) or n.nombre):upper()
    return siglas, n.color
end

--- El almacén del jugador (nil si solo se mira el mundo).
---@return Almacen|nil
function Almacen.getDelJugador()
    return Almacen.getDeNacion(jugadorDe())
end

--- Los datos guardados (interno).
function Almacen:datos()
    return simulacion():almacenDeMisiles(self.nacion)
end

-- Qué es ----------------------------------------------------------------

--- La nación dueña.
---@return integer
function Almacen:getNacion()
    return self.nacion
end

-- Misiles ---------------------------------------------------------------

--- Misiles guardados ahora.
---@return integer
function Almacen:getMisiles()
    return self:datos().misiles
end

--- Huecos de misiles que tiene el polvorín (contenedores: 60).
---@return integer
function Almacen:getCapacidad()
    return simulacion():capacidadDeMisiles()
end

--- Huecos libres: capacidad menos misiles.
---@return integer
function Almacen:getHuecosLibres()
    return self:getCapacidad() - self:getMisiles()
end

--- `true` si no queda ningún misil.
---@return boolean
function Almacen:getEstaVacio()
    return self:getMisiles() == 0
end

--- `true` si no cabe ninguno más.
---@return boolean
function Almacen:getEstaLleno()
    return self:getMisiles() >= self:getCapacidad()
end

--- Pone los misiles (se recorta a 0..capacidad).
---@param misiles integer
function Almacen:setMisiles(misiles)
    simulacion():ejecutar({ tipo = 'misilesAlmacen', nacion = self.nacion, misiles = misiles })
end

--- Mete `cantidad` misiles (hasta llenar).
---@param cantidad integer
function Almacen:setAgregarMisiles(cantidad)
    simulacion():ejecutar({ tipo = 'sumarMisilesAlmacen', nacion = self.nacion, cantidad = math.abs(cantidad) })
end

--- Saca `cantidad` misiles (hasta vaciar).
---@param cantidad integer
function Almacen:setSacarMisiles(cantidad)
    simulacion():ejecutar({ tipo = 'sumarMisilesAlmacen', nacion = self.nacion, cantidad = -math.abs(cantidad) })
end

--- Paga lo que gasta la fábrica de misiles (`{ dinero, metal, petroleo }`).
-- Devuelve true, o false y el motivo ('noAlcanza').
---@param coste table
function Almacen:setPagar(coste)
    return simulacion():ejecutar({ tipo = 'pagarAlmacen', nacion = self.nacion, coste = coste })
end

-- La partida ------------------------------------------------------------

--- Los datos de la nación dueña ahora mismo (los de la barra de arriba del
-- mapa): { nacion, capital, habitantes, poder, nivel, dia, anio, ciudades,
-- recursos = { { tipo, nombre, cantidad, tope, estado } x4 }, noticias }.
-- Los pinta la sala de control (almacen/partida.lua).
---@return table|nil
--- Recursos de la nación que llegan al almacén (solo leer): el dinero del
-- tesoro, la comida de todas sus ciudades, la munición de sus polvorines
-- (`{ balas, obuses, misiles }`), el metal y el petróleo.
function Almacen:getRecursos()
    local sim = simulacion()
    local n = sim.estado.naciones[self.nacion]
    -- Dinero y petróleo: lo guardado más lo que no cabía (afuera), como lo
    -- que puede gastar (Simulacion.disponible).
    local afuera = n.afuera or {}
    local r = {
        dinero = (n.tesoro or 0) + (afuera.dinero or 0),
        petroleo = ((n.recursos and n.recursos.petroleo) or 0) + (afuera.petroleo or 0),
        metal = ((n.recursos and n.recursos.metal) or 0) + (afuera.metal or 0),
        comida = 0, balas = 0, obuses = 0, misiles = 0,
    }
    for _, c in ipairs(sim:ciudadesDe(self.nacion)) do
        r.comida = r.comida + (c.comida or 0)
        local m = c.municion or {}
        r.balas, r.obuses, r.misiles = r.balas + (m.balas or 0), r.obuses + (m.obuses or 0), r.misiles + (m.misiles or 0)
    end
    return r
end

--- La semilla de la partida (para saber si lo guardado es de esta partida).
function Almacen:getSemilla()
    local sim = simulacion()
    return sim and sim.estado.semilla
end

function Almacen:getPartida()
    return require('almacen.partida').leer(simulacion(), self.nacion)
end

return Almacen

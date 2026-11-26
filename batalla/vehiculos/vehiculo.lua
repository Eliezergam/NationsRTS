-- Un vehículo de la batalla con sus especializaciones
-- (batalla/vehiculos/gestorVehiculos.lua). Lo crea el gestor. En una
-- especialización es `self` (function MiScript:onUpdate(dt)); desde
-- cualquier otro script, GestorVehiculos.getVehiculos(). Referencia completa:
-- batalla/vehiculos/API.md. Aquí, `vehiculo` es el vehículo:
--
-- Lo que es:
--   vehiculo.unidad               la unidad de Tropas (todos sus datos)
--   vehiculo.tipo                 el tipo registrado (nombre, modelo...)
--   vehiculo.modelo               el modelo cargado (piezas y contrato)
--   vehiculo:getNombreTipo()         'camionLanzamisiles'...
--   vehiculo:getContrato(nombre)     una tabla del contrato del modelo:
--                                 'gatos', 'rampa', 'ruedas', 'misiles'...
--
-- Sus piezas (batalla/vehiculos/pieza.lua):
--   vehiculo:getPieza('rampaLanzador')   la pieza (leer, girar, mover, ocultar)
--   vehiculo:getTienePieza(nombre)
--   vehiculo:getNombresPiezas()          todos los nombres, en orden
--   vehiculo:getPiezas()                 todas las piezas, en orden
--
-- Su estado (de la simulación; solo para leer):
--   vehiculo:getPosicion()           x, y, z en el mundo (px)
--   vehiculo:getRumbo()              hacia dónde mira (radianes)
--   vehiculo:getBando()              1 o 2
--   vehiculo:getNumero()             orden de entrada en su bando
--   vehiculo:getVivo()
--   vehiculo:getVelocidad()          px por segundo
--   vehiculo:getFase()               'espera', 'apoyando', 'subiendo', 'fuego'...
--   vehiculo:getElevacion()          grados de la rampa que pide la simulación
--   vehiculo:getGatos()              0 recogidos ... 1 apoyados
--   vehiculo:getMisilesCargados()
--   vehiculo:getOrdenMisiles()       nombres de los misiles en orden de disparo
--   vehiculo:getSeHaMovido()         ¿se movió o giró desde el paso anterior?
--   vehiculo:getCasco()              matriz del casco de la física en el mundo
--   vehiculo:getPuntoMundo(x, y, z)  un punto del vehículo (en reposo) en el
--                                 mundo, con el casco
--   vehiculo:getAlturaSuelo(x, y)    altura del terreno en ese punto del mundo
--
-- Su chasis (lo que se dibuja encima del casco de la física):
--   vehiculo:setInclinacionChasis(altura, cabeceo, balanceo, capa)
--                                 sube (px) y gira (rad) el chasis con todo lo
--                                 que lleva encima; como las piezas, cada
--                                 especialización tiene su capa y se suman
--   vehiculo:getChasis()             altura, cabeceo y balanceo de todas las capas
--   vehiculo:getChasisDeOtros()      lo mismo sin la capa de quien llama
--   vehiculo:getCentroChasis()       x del punto sobre el que cabecea (px)
--
-- Sus especializaciones:
--   vehiculo:getTieneEspecializacion('rampa')
--   vehiculo.datos.rampa, vehiculo.datos.baliza...   lo que guarda cada una
--
-- Cada especialización guarda sus datos en `vehiculo.datos` con su propio
-- nombre (en Farming Simulator, `spec_nombre`): así no tapan las funciones
-- del vehículo (`vehiculo.gatos` taparía `vehiculo:getGatos()`).

local Matriz = require('batalla.matriz')
local Pieza = require('batalla.vehiculos.pieza')

--- Una especialización (como en Farming Simulator): una tabla con las
-- funciones que el motor llama, escritas con `:`. Dentro, `self` es el
-- vehículo. Al declarar la tuya con
-- `---@class MiScript : Especializacion, Vehiculo` el editor lo sabe.
---@class Especializacion
---@field nombre string su nombre registrado (lo pone el gestor)
---@field prerequisitos? fun(self: Vehiculo): boolean ¿puede ir en este vehículo?
---@field onLoad? fun(self: Vehiculo) al crear el vehículo
---@field onUpdate? fun(self: Vehiculo, dt: number) en cada paso de la batalla
---@field onPose? fun(self: Vehiculo) antes de calcular las matrices de las piezas

---@class Vehiculo
---@field unidad table la unidad de Tropas
---@field tipo table el tipo registrado
---@field modelo table el modelo cargado (piezas y contrato)
---@field datos table<string, any> lo que guarda cada especialización
---@field lanzador table? el lanzador del camión
---@field actual string? la especialización que se está llamando
---@field matrices table<string, number[]> matriz de cada pieza en el mundo
---@field especializaciones Especializacion[]
---@field porNombre table<string, Especializacion>
---@field piezasCreadas table<string, Pieza>
---@field capasChasis table<string, table>
---@field ordenChasis string[]
---@field movido boolean?
---@field posicionAnterior number[]?
local Vehiculo = {}
Vehiculo.__index = Vehiculo

--- Vehículo de la unidad `unidad`, del tipo `tipo`. `fuente` dice de dónde
-- salen sus piezas: { modelo, matrices (nombre -> matriz en el mundo),
-- lanzador (el del camión, si es uno) }.
---@param unidad table
---@param tipo table
---@param fuente table
---@return Vehiculo
function Vehiculo.nuevo(unidad, tipo, fuente)
    local self = setmetatable({}, Vehiculo)
    self.unidad = unidad
    self.tipo = tipo
    self.modelo = fuente.modelo
    self.matrices = fuente.matrices
    self.lanzador = fuente.lanzador
    self.datos = {}
    self.especializaciones = {}
    self.porNombre = {}
    self.piezasCreadas = {}
    self.capasChasis = {}
    self.ordenChasis = {}
    return self
end

--- Añade la especialización `especializacion` (la llama el gestor).
---@param especializacion Especializacion
function Vehiculo:agregarEspecializacion(especializacion)
    self.especializaciones[#self.especializaciones + 1] = especializacion
    self.porNombre[especializacion.nombre] = especializacion
end

--- ¿Lleva la especialización `nombre`?
---@param nombre string
---@return boolean
function Vehiculo:getTieneEspecializacion(nombre)
    return self.porNombre[nombre] ~= nil
end

--- Llama `evento` (onLoad, onUpdate...) en cada especialización que lo
-- tenga. Mientras, `self.actual` es su nombre: lo que mueva u oculte va a su
-- capa de la pieza (batalla/vehiculos/pieza.lua).
---@param evento string
---@param ... any
function Vehiculo:llamar(evento, ...)
    for _, especializacion in ipairs(self.especializaciones) do
        local funcion = especializacion[evento]
        if funcion then
            self.actual = especializacion.nombre
            funcion(self, ...)
        end
    end
    self.actual = nil
end

--- El nombre de su tipo.
---@return string nombre
function Vehiculo:getNombreTipo()
    return self.tipo.nombre
end

--- La tabla `nombre` del contrato del modelo (nil si no la tiene).
---@param nombre TablaContrato|string
---@return any tabla la tabla, o nil si el modelo no la tiene
function Vehiculo:getContrato(nombre)
    return self.modelo[nombre]
end

--- ¿Se recompone la pieza `nombre` en cada cuadro aunque el vehículo esté
-- quieto? (los ventiladores del camión: ArticulacionCamion:matricesVentiladores)
---@param nombre string
---@return boolean
function Vehiculo:recomponeSiempre(nombre)
    local articulacion = self.lanzador and self.lanzador.articulacion
    local tipo = articulacion and articulacion.tipos[nombre]
    return tipo ~= nil and tipo.tipo == 'ventilador'
end

--- ¿Tiene el modelo la pieza `nombre`?
---@param nombre PiezaCamion|string
---@return boolean
function Vehiculo:getTienePieza(nombre)
    return self.modelo.piezas[nombre] ~= nil
end

--- La pieza `nombre` (la misma cada vez). Error si el modelo no la tiene.
---@param nombre PiezaCamion|string
---@return Pieza
function Vehiculo:getPieza(nombre)
    local pieza = self.piezasCreadas[nombre]
    if not pieza then
        assert(self:getTienePieza(nombre), 'Vehiculo: el modelo no tiene la pieza ' .. nombre)
        pieza = Pieza.nueva(self, nombre)
        self.piezasCreadas[nombre] = pieza
    end
    return pieza
end

--- Los nombres de todas sus piezas, en orden alfabético.
---@return string[] nombres
function Vehiculo:getNombresPiezas()
    local nombres = {}
    local piezas = self.modelo.piezas
    for nombre, datos in pairs(piezas) do
        -- `contenedor` es otro nombre de la rampa (ArticulacionCamion.nuevo,
        -- para el código de los otros lanzacohetes): no es una pieza más.
        local alias = nombre == 'contenedor' and datos == piezas.rampaLanzador
        if not alias then
            nombres[#nombres + 1] = nombre
        end
    end
    table.sort(nombres)
    return nombres
end

--- Todas sus piezas, en el orden de `nombresPiezas`.
---@return Pieza[] piezas
function Vehiculo:getPiezas()
    local lista = {}
    for indice, nombre in ipairs(self:getNombresPiezas()) do
        lista[indice] = self:getPieza(nombre)
    end
    return lista
end

--- x, y, z en el mundo (px).
---@return number x
---@return number y
---@return number z
function Vehiculo:getPosicion()
    local unidad = self.unidad
    return unidad.x, unidad.y, unidad.z
end

--- Hacia dónde mira (radianes).
---@return number rumbo radianes
function Vehiculo:getRumbo()
    return self.unidad.rumbo
end

--- Su bando (1 o 2).
---@return integer bando
function Vehiculo:getBando()
    return self.unidad.bando
end

--- Su orden de entrada en el bando.
---@return integer numero
function Vehiculo:getNumero()
    return self.unidad.numero
end

--- ¿Sigue vivo?
---@return boolean
function Vehiculo:getVivo()
    return not self.unidad.muerto
end

--- Velocidad (px por segundo).
---@return number velocidad px por segundo
function Vehiculo:getVelocidad()
    return self.unidad.velocidadRuedas or 0
end

--- Fase de la simulación ('espera', 'apoyando', 'subiendo', 'fuego'...).
---@return FaseVehiculo fase
function Vehiculo:getFase()
    return self.unidad.fase
end

--- Grados de la rampa que pide la simulación.
---@return number elevacion grados
function Vehiculo:getElevacion()
    return self.unidad.elevacion or 0
end

--- Gatos: 0 recogidos ... 1 apoyados.
---@return number gatos de 0 a 1
function Vehiculo:getGatos()
    return self.unidad.gatos or 0
end

--- Los nombres de los misiles de la rampa, en el orden en que se disparan.
---@return string[] nombres
function Vehiculo:getOrdenMisiles()
    local lista = {}
    local articulacion = self.lanzador and self.lanzador.articulacion
    for indice, entrada in ipairs(articulacion and articulacion.ordenMisiles or {}) do
        lista[indice] = entrada.nombre
    end
    return lista
end

--- Misiles que quedan en la rampa.
---@return integer cargados
function Vehiculo:getMisilesCargados()
    local articulacion = self.lanzador and self.lanzador.articulacion
    if articulacion then
        return articulacion:cargados(self.unidad)
    end
    return 0
end

--- Anota si se movió desde el paso anterior (la llama el gestor antes de
-- cada onUpdate).
function Vehiculo:anotarMovimiento()
    local unidad = self.unidad
    local antes = self.posicionAnterior
    if not antes then
        antes = {}
        self.posicionAnterior = antes
        self.movido = true
    else
        self.movido = antes[1] ~= unidad.x or antes[2] ~= unidad.y or antes[3] ~= unidad.z or antes[4] ~= unidad.rumbo
    end
    antes[1], antes[2], antes[3], antes[4] = unidad.x, unidad.y, unidad.z, unidad.rumbo
end

--- ¿Se movió o giró desde el paso anterior?
---@return boolean
function Vehiculo:getSeHaMovido()
    return self.movido or false
end

--- Matriz del casco de la física en el mundo (solo para leer).
---@return number[] matriz 4x4 por filas
function Vehiculo:getCasco()
    return self.unidad.casco
end

--- El punto (x, y, z) del vehículo, en reposo, en el mundo (con el casco).
---@param x number
---@param y number
---@param z number
---@return number x
---@return number y
---@return number z
function Vehiculo:getPuntoMundo(x, y, z)
    return Matriz.aplicar(self.unidad.casco, x, y, z)
end

--- Altura del terreno en el punto (x, y) del mundo.
---@param x number
---@param y number
---@return number z
function Vehiculo:getAlturaSuelo(x, y)
    return self.lanzador.destruccion.suelo:altura(x, y)
end

--- x (px) del punto del chasis sobre el que cabecea: entre los ejes extremos.
---@return number x
function Vehiculo:getCentroChasis()
    local articulacion = self.lanzador and self.lanzador.articulacion
    return articulacion and articulacion.centroX or 0
end

--- Sube `altura` px y gira `cabeceo` (sobre y; negativo sube el frente) y
-- `balanceo` (sobre x) radianes el chasis, con todo lo que lleva. Sustituye
-- lo anterior de la capa de quien llama (`nombreCapa`, opcional, para tener
-- varias); las capas se suman.
---@param altura number px
---@param cabeceo number radianes
---@param balanceo number radianes
---@param nombreCapa? string
function Vehiculo:setInclinacionChasis(altura, cabeceo, balanceo, nombreCapa)
    local clave = self.actual or 'fuera'
    if nombreCapa then
        clave = clave .. '/' .. nombreCapa
    end
    local capa = self.capasChasis[clave]
    if not capa then
        capa = { altura = 0, cabeceo = 0, balanceo = 0 }
        self.capasChasis[clave] = capa
        self.ordenChasis[#self.ordenChasis + 1] = clave
    end
    if capa.altura == altura and capa.cabeceo == cabeceo and capa.balanceo == balanceo then
        return
    end
    capa.altura, capa.cabeceo, capa.balanceo = altura, cabeceo, balanceo
    local total = self.unidad.chasisScript or {}
    total.altura, total.cabeceo, total.balanceo = self:getChasis()
    self.unidad.chasisScript = total
    -- Para las pruebas (batalla/pruebas_camion_misiles).
    self.unidad.cabeceoChasis = total.cabeceo
    self.unidad.balanceoChasis = total.balanceo
    -- Las matrices se recalculan aunque el camión esté quieto.
    self.unidad.versionAjustes = (self.unidad.versionAjustes or 0) + 1
end

--- Suma de las capas del chasis cuyas claves pasan `incluir` (todas si nil).
---@param incluir? fun(clave: string): boolean
---@return number altura
---@return number cabeceo
---@return number balanceo
function Vehiculo:sumaChasis(incluir)
    local altura, cabeceo, balanceo = 0, 0, 0
    for _, clave in ipairs(self.ordenChasis) do
        if not incluir or incluir(clave) then
            local capa = self.capasChasis[clave]
            altura = altura + capa.altura
            cabeceo = cabeceo + capa.cabeceo
            balanceo = balanceo + capa.balanceo
        end
    end
    return altura, cabeceo, balanceo
end

--- Altura, cabeceo y balanceo del chasis: todas las capas.
---@return number altura
---@return number cabeceo
---@return number balanceo
function Vehiculo:getChasis()
    return self:sumaChasis()
end

--- Lo mismo sin las capas de quien llama.
---@return number altura
---@return number cabeceo
---@return number balanceo
function Vehiculo:getChasisDeOtros()
    local propia = self.actual or 'fuera'
    return self:sumaChasis(function(clave)
        return clave ~= propia and clave:sub(1, #propia + 1) ~= propia .. '/'
    end)
end

return Vehiculo

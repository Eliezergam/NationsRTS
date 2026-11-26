-- Librería común de los robots (el dueño, 18-nov: «crear una lib para los
-- soldados, así usan funciones comunes y no se escribe casi el mismo código
-- para todos los robots»). Como las especializaciones de Farming Simulator:
-- un robot es un modelo con piezas que se mueven por capas (robots/pieza.lua)
-- y una lista de scripts, las especializaciones, que lo hacen moverse y
-- pensar. Cada tipo de robot dice su modelo, sus medidas, sus
-- especializaciones en orden y sus `ajustes` (los números propios que
-- cambian los de cada especialización).
--
-- Lo que cambia de una escena a otra (almacén, batalla) lo pone su gestor
-- (`Nucleo.nuevoGestor`): dónde buscar los tipos, las especializaciones y los
-- modelos, qué hacer al cargar un modelo, dónde está la raíz del robot y
-- cómo se pasa a 3Dream para dibujarlo. Todo lo demás es común.
--
-- `get...` devuelve algo y no cambia nada; `set...` cambia algo y no
-- devuelve nada. Todo con `:`. Medidas del robot: metros; ejes: x delante,
-- y izquierda, z arriba; ángulos en radianes, rumbo 0 = hacia +x.

local dream = require('lib.3DreamEngine')
local PiezaRobot = require('robots.pieza')
local Union = require('robots.union')

local Nucleo = {}

---@class Robot
---@field tipo string
---@field datos table lo que guarda cada especialización: self.datos.miScript
local Robot = {}
Robot.__index = Robot
Nucleo.Robot = Robot

-- Las especializaciones, por nombre, para todas las escenas (cada archivo de
-- especialización se registra al cargarse).
local especializaciones = {}

--- Registra una especialización.
function Nucleo.registrarEspecializacion(nombre, tabla)
    especializaciones[nombre] = tabla
end

local function existe(modulo)
    return love.filesystem.getInfo(modulo:gsub('%.', '/') .. '.lua', 'file') ~= nil
end

--- La especialización `nombre`: ya registrada o del primer módulo que exista
-- en `carpetas` (módulos de Lua: 'robots.especializaciones', ...).
local function buscarEspecializacion(nombre, carpetas)
    if especializaciones[nombre] then
        return especializaciones[nombre]
    end
    for _, carpeta in ipairs(carpetas) do
        local modulo = carpeta .. '.' .. nombre
        if existe(modulo) then
            local e = require(modulo)
            especializaciones[nombre] = especializaciones[nombre] or e
            return especializaciones[nombre]
        end
    end
    error('no hay especialización ' .. nombre .. ' en ' .. table.concat(carpetas, ', '), 3)
end

local function buscarTipo(tipo, carpetas)
    for _, carpeta in ipairs(carpetas) do
        local modulo = carpeta .. '.' .. tipo
        if existe(modulo) then
            return require(modulo)
        end
    end
    error('no hay tipo de robot ' .. tipo .. ' en ' .. table.concat(carpetas, ', '), 3)
end

--- Un tipo con `base = 'otroTipo'` hereda lo de aquel: su modelo y medidas
-- si no dice otros, sus especializaciones (las suyas van detrás) y sus
-- ajustes (los suyos mandan).
local function heredar(propio, base)
    local t = {}
    for k, v in pairs(base) do
        if type(k) ~= 'number' and k ~= 'ajustes' then
            t[k] = v
        end
    end
    for k, v in pairs(propio) do
        if type(k) ~= 'number' and k ~= 'ajustes' and k ~= 'base' then
            t[k] = v
        end
    end
    for _, nombre in ipairs(base) do
        t[#t + 1] = nombre
    end
    for _, nombre in ipairs(propio) do
        t[#t + 1] = nombre
    end
    t.ajustes = {}
    for _, origen in ipairs({ base.ajustes or {}, propio.ajustes or {} }) do
        for especializacion, valores in pairs(origen) do
            t.ajustes[especializacion] = t.ajustes[especializacion] or {}
            for k, v in pairs(valores) do
                t.ajustes[especializacion][k] = v
            end
        end
    end
    return t
end

-- Gestor de una escena -------------------------------------------------------------

---@class GestorRobots
local Gestor = {}
Gestor.__index = Gestor

--- Un gestor para una escena. `opciones`:
--   tipos             módulos donde buscar los tipos ({ 'almacen.robots.tipos', 'robots.tipos' })
--   especializaciones módulos donde buscar las especializaciones
--   modelos           carpeta de los modelos sin ruta ('assets/almacen/')
--   modeloPorDefecto  el modelo del tipo que no dice ninguno
--   alCargarModelo    function(objeto): retoques al cargar un modelo (brillos)
--   raiz              function(robot): matriz 4x4 por filas de la raíz
--   aDream            function(m, robot): de una matriz de pieza a la de 3Dream
--   rayo              function(x, y, z, dx, dy, dz, alcance, ignorar): lo que toca
--                     un rayo en el mundo de la escena: distancia, tipo, objeto
function Nucleo.nuevoGestor(opciones)
    local self = setmetatable({}, Gestor)
    self.opciones = opciones
    self.lista = {}
    self.modelos = {} -- [ruta] = { base = objeto de 3DreamEngine, piezas = lista }
    return self
end

function Gestor:cargarModelo(nombre)
    if self.modelos[nombre] then
        return self.modelos[nombre]
    end
    -- Con carpeta (`assets/batalla/robots/soldado`), de ahí; si no, de la
    -- carpeta de modelos de la escena.
    local ruta = nombre:find('/') and nombre or (self.opciones.modelos .. nombre)
    local piezas = love.filesystem.load(ruta .. '_piezas.lua')()
    local base = dream:loadObject(ruta, { decodeBlenderNames = false })
    if self.opciones.alCargarModelo then
        self.opciones.alCargarModelo(base)
    end
    -- Copias para de lejos (<modelo>_lod1.glb, _lod2.glb: menos triángulos
    -- y las piezas que no se mueven unidas a su madre), si las hay.
    local lods = {}
    for nivel = 1, 2 do
        if love.filesystem.getInfo(ruta .. '_lod' .. nivel .. '.glb') then
            lods[nivel] = dream:loadObject(ruta .. '_lod' .. nivel, { decodeBlenderNames = false })
            if self.opciones.alCargarModelo then
                self.opciones.alCargarModelo(lods[nivel])
            end
            -- A la tarjeta ya: si no, se sube al verla por primera vez (un
            -- tirón cuando un robot cruza la distancia de cambio).
            lods[nivel]:preload(true)
        end
    end
    base:preload(true)
    self.modelos[nombre] = { base = base, piezas = piezas, lods = lods }
    return self.modelos[nombre]
end

--- La definición del tipo `tipo`, con lo que herede de su base.
function Gestor:getDefinicion(tipo)
    local definicion = buscarTipo(tipo, self.opciones.tipos)
    if definicion.base then
        return heredar(definicion, self:getDefinicion(definicion.base))
    end
    return definicion
end

--- Crea un robot de tipo `tipo` en (x, y) con rumbo `rumbo`. `extra`: campos
-- que el robot tiene antes de cargar sus especializaciones (el suelo de la
-- batalla, por ejemplo).
---@return Robot
function Gestor:crear(tipo, x, y, rumbo, extra)
    local o = self.opciones
    local definicion = self:getDefinicion(tipo)
    -- Sin su modelo (la copia pública del código va sin los de pago, como el
    -- chasis del camión de misiles): no se crea, con un aviso en la consola.
    local nombreModelo = definicion.modelo or o.modeloPorDefecto
    local rutaModelo = nombreModelo:find('/') and nombreModelo or (o.modelos .. nombreModelo)
    if not love.filesystem.getInfo(rutaModelo .. '.glb', 'file') then
        print('Robots: falta el modelo ' .. rutaModelo .. '.glb; no se crea un ' .. tostring(tipo))
        return nil
    end
    local modelo = self:cargarModelo(nombreModelo)
    local robot = setmetatable({}, Robot)
    for k, v in pairs(extra or {}) do
        robot[k] = v
    end
    robot.gestor = self
    robot.tipo = tipo
    robot.x, robot.y, robot.rumbo = x or 0, y or 0, rumbo or 0
    robot.velocidad = 0
    robot.giro = 0
    robot.datos = {}
    robot.nombreModelo = definicion.modelo or o.modeloPorDefecto
    robot.objeto = modelo.base:clone()
    robot.lods = {}
    for nivel, base in pairs(modelo.lods) do
        robot.lods[nivel] = base:clone()
        -- De lejos, sin sombra propia: no se distingue y cuesta otra pasada.
        if nivel == 2 then
            robot.lods[nivel]:setShadowVisibility(false)
        end
    end
    robot.nivel = 0
    robot.piezas = {}
    robot.orden = {}
    for _, d in ipairs(modelo.piezas) do
        local p = PiezaRobot.nueva(robot, d)
        p.objeto = d.malla and robot.objeto.objects[d.nombre] or nil
        -- La misma pieza en cada copia de lejos (nil si se unió a su madre
        -- o, de muy lejos, es diminuta).
        p.objetosLod = {}
        for nivel, copia in pairs(robot.lods) do
            p.objetosLod[nivel] = copia.objects[d.nombre]
        end
        robot.piezas[d.nombre] = p
        robot.orden[#robot.orden + 1] = p
        if d.padre then
            p.padre = robot.piezas[d.padre]
            table.insert(p.padre.hijas, p)
        end
    end
    robot.especializaciones = {}
    -- Medidas del robot (para saber por dónde cabe).
    robot.ancho, robot.alto = definicion.ancho or 0.8, definicion.alto or 1.8
    -- Vehículos: `inclinar = { largo, ancho }` m, se apoyan en el terreno
    -- por sus cuatro lados (lo usa la raíz de cada escena).
    robot.inclinar = definicion.inclinar
    -- Las especializaciones de su trabajo (`trabajo = { ... }` en el tipo):
    -- las que un guion de la sala sustituye (almacen/robots/especializaciones/
    -- guion.lua).
    robot.trabajo = definicion.trabajo
    -- Distancias de las copias de lejos propias (m): un avión de 87 m no
    -- cambia de copia donde un robot de 1,85 m.
    robot.lodDistancias = definicion.lodDistancias
    -- Números propios del tipo para cada especialización (`ajustes` en el
    -- tipo); lo que no cambia, el de la especialización.
    robot.ajustes = {}
    for _, nombre in ipairs(definicion) do
        local e = buscarEspecializacion(nombre, o.especializaciones)
        robot.actual = nombre
        if not e.prerequisitos or e.prerequisitos(robot) ~= false then
            robot.datos[nombre] = robot.datos[nombre] or {}
            local propios = {}
            for k, v in pairs(definicion.ajustes and definicion.ajustes[nombre] or {}) do
                propios[k] = v
            end
            robot.ajustes[nombre] = setmetatable(propios, { __index = e })
            robot.especializaciones[#robot.especializaciones + 1] = { nombre = nombre, tabla = e }
        end
    end
    robot.actual = nil
    robot:llamar('onLoad')
    self.lista[#self.lista + 1] = robot
    robot:colocar()
    return robot
end

--- Todos los robots de la escena.
---@return Robot[]
function Gestor:getRobots()
    return self.lista
end

--- Quita todos (al salir de la escena).
function Gestor:vaciar()
    self.lista = {}
end

--- Un robot `guardado` (dentro de algo cerrado: la bodega del avión de
-- carga con la rampa subida, embarque.lua) ni se actualiza ni se dibuja: no
-- se ve y no gasta. Quien lo guarda lo vuelve a sacar.
function Gestor:actualizar(dt)
    for _, r in ipairs(self.lista) do
        if not r.guardado then
            self:actualizarUno(r, dt)
        end
    end
end

function Gestor:actualizarUno(r, dt)
    r:llamar('onUpdate', dt)
    r:llamar('onPose')
    r:colocar()
    -- Lo que lleva en las garras, donde están ellas (robot grande).
    if r.moverLoQueLlevan then
        r:moverLoQueLlevan()
    end
end

function Gestor:dibujar(...)
    for _, r in ipairs(self.lista) do
        if not r.guardado then
            r:dibujar(...)
        end
    end
end

-- Robot: lo común ------------------------------------------------------------------

-- Medir (almacén con ALMACEN_FPS): segundos por especialización y tipo,
-- `Robot.tiempos[tipo .. '.' .. especialización]`; nil = no se mide.
Robot.tiempos = nil

function Robot:llamar(evento, ...)
    local tiempos = Robot.tiempos
    -- El robot que está corriendo su código ahora (lo que escriba con print
    -- va a su depuración: almacen/pc/depuracion.lua).
    local antes = Robot.enCurso
    Robot.enCurso = self
    for _, e in ipairs(self.especializaciones) do
        local f = e.tabla[evento]
        if f then
            self.actual = e.nombre
            if tiempos then
                local t0 = love.timer.getTime()
                f(self, ...)
                local clave = tostring(self.tipo) .. '.' .. e.nombre
                tiempos[clave] = (tiempos[clave] or 0) + love.timer.getTime() - t0
            else
                f(self, ...)
            end
        end
    end
    self.actual = nil
    Robot.enCurso = antes
end

--- Calcula la matriz de cada pieza (la raíz la pone la escena).
function Robot:colocar()
    local raiz = self.gestor.opciones.raiz(self)
    for _, p in ipairs(self.orden) do
        p:colocarEn(p.padre and p.padre.mundo or raiz)
    end
end

--- Qué copia toca por la distancia a la cámara: 0 la de cerca, 1 y 2 las
-- de lejos (opciones.lod = { distancias = { 15, 45 }, ojo = function()
-- return x, y, z end (en 3Dream), metrosPorUnidad = 10 }).
function Robot:elegirNivel(aDream, ...)
    local lod = self.gestor.opciones.lod
    if not lod or not next(self.lods) then
        return 0
    end
    -- Para revisar las copias de cerca: ROBOTS_LOD=1 o 2 las pone siempre.
    if lod.forzar and self.lods[lod.forzar] then
        return lod.forzar
    end
    local t = aDream(self.orden[1].mundo, self, ...)
    local ox, oy, oz = lod.ojo()
    local dx, dy, dz = t[4] - ox, t[8] - oy, t[12] - oz
    local metros = math.sqrt(dx * dx + dy * dy + dz * dz) * lod.metrosPorUnidad
    local nivel = 0
    for k, d in ipairs(self.lodDistancias or lod.distancias) do
        if metros > d and self.lods[k] then
            nivel = k
        end
    end
    return nivel
end

function Robot:dibujar(...)
    local aDream = self.gestor.opciones.aDream
    local nivel = self:elegirNivel(aDream, ...)
    self.nivel = nivel
    -- Todo el robot en una malla por material (robots/union.lua); si no se
    -- puede, pieza a pieza.
    if Union.dibujar(self, nivel, aDream, ...) then
        self:llamar('onDibujar', aDream, ...)
        return
    end
    for _, p in ipairs(self.orden) do
        local objeto = p.objeto
        if nivel > 0 then
            objeto = p.objetosLod[nivel]
        end
        if objeto and p:getVisibleArbol() then
            objeto:setTransform(aDream(p.mundo, self, ...))
            -- Se mueve: fuera de las sombras estáticas (que lo dejarían
            -- quieto donde estaba al empezar), dentro de las dinámicas.
            objeto.dynamic = true
            dream:draw(objeto)
        end
    end
    -- Lo que dibuja cada especialización aparte (los misiles en vuelo).
    self:llamar('onDibujar', aDream, ...)
end

--- Visible si ella y todas sus madres lo son.
function PiezaRobot:getVisibleArbol()
    local p = self
    while p do
        if not p.visible then
            return false
        end
        p = p.padre
    end
    return true
end

--- Los números de la especialización `nombre` para este robot: los de su
-- tipo (`ajustes`) y, si no los cambia, los de la especialización.
function Robot:getAjustes(nombre)
    return self.ajustes[nombre]
end

--- Ancho (m) del robot con los brazos abajo, de lado a lado.
function Robot:getAncho()
    return self.ancho
end

--- Alto (m) del robot.
function Robot:getAlto()
    return self.alto
end

--- El nombre de su tipo (`'robotAlmacen'`...).
function Robot:getNombreTipo()
    return self.tipo
end

--- x, y del centro de la base (metros).
function Robot:getPosicion()
    return self.x, self.y
end

--- Hacia dónde mira (radianes; 0 = +x).
function Robot:getRumbo()
    return self.rumbo
end

--- Metros por segundo hacia delante (negativo: marcha atrás).
function Robot:getVelocidad()
    return self.velocidad
end

--- Radianes por segundo que gira.
function Robot:getGiroVelocidad()
    return self.giro
end

--- `true` si lleva ese script.
function Robot:getTieneEspecializacion(nombre)
    return self.datos[nombre] ~= nil
end

--- `true` si el robot tiene la pieza `nombre` (los tipos no tienen todos
-- las mismas).
function Robot:getTienePieza(nombre)
    return self.piezas[nombre] ~= nil
end

--- La pieza (error si no existe).
---@return PiezaRobot
function Robot:getPieza(nombre)
    local p = self.piezas[nombre]
    if not p then
        error('el robot no tiene la pieza ' .. tostring(nombre), 2)
    end
    return p
end

function Robot:getNombresPiezas()
    local nombres = {}
    for _, p in ipairs(self.orden) do
        nombres[#nombres + 1] = p.nombre
    end
    return nombres
end

--- Lo que toca un rayo en el mundo de su escena (opción `rayo` del gestor):
-- distancia, tipo, objeto; nil si la escena no tiene.
function Robot:getRayoMundo(x, y, z, dx, dy, dz, alcance, ignorar)
    local rayo = self.gestor.opciones.rayo
    if rayo then
        return rayo(x, y, z, dx, dy, dz, alcance, ignorar)
    end
end

--- Lo pone en (x, y) con `rumbo` (sin conducir: se teletransporta).
function Robot:setPosicion(x, y, rumbo)
    self.x, self.y = x, y
    if rumbo then
        self.rumbo = rumbo
    end
end

return Nucleo

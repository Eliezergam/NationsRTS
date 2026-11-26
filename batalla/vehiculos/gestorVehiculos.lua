-- Gestor de vehículos: especializaciones como en Farming Simulator.
--
-- Es el del camión de vértices de antes: desde el 21-nov no queda ningún tipo
-- (sus modelos eran del pack Synty). Los vehículos de hoy son robots
-- (robots/nucleo.lua, batalla/robots/tipos/).
--
-- Cada especialización es un archivo de batalla/vehiculos/especializaciones/
-- con una tabla de funciones que se registra sola:
--
--     GestorVehiculos.registrarEspecializacion('rampa', Rampa)
--
-- Cada tipo de vehículo es un archivo de batalla/vehiculos/tipos/ que dice
-- con qué modelo va y qué especializaciones lleva:
--
--     GestorVehiculos.registrarTipo('camionLanzamisiles', {
--         modelo = 'assets/modelos3d/<modelo>',
--         especializaciones = { 'rampa', 'baliza' },
--     })
--
-- El gestor carga las dos carpetas la primera vez que se crea un vehículo.
-- Al crear un vehículo de un tipo registrado (Lanzamisiles:inicializar) le
-- llama `onLoad` de cada especialización y, cada paso de la batalla
-- (Lanzamisiles:medirMovimiento), `onUpdate(dt)`; en ese orden, el de la
-- lista del tipo. Se escriben con `:` y `self` es el vehículo, como en
-- Farming Simulator. Funciones que puede tener una especialización:
--
--     MiScript:prerequisitos()  true si puede ir en ese vehículo (si falta,
--                               se da por buena)
--     MiScript:onLoad()         al crearse el vehículo
--     MiScript:onUpdate(dt)     cada paso de la batalla (dt en segundos)
--     MiScript:onPose()         justo antes de calcular las matrices de las
--                               piezas (también fuera del paso, p. ej. al
--                               lanzar un misil): para colocar piezas que
--                               dependen del estado de la simulación
--
-- Para encontrar vehículos desde cualquier script:
--     GestorVehiculos.getVehiculos()           todos los vivos y muertos de la
--                                           batalla, por bando y número
--     GestorVehiculos.getPorTipo('camionLanzamisiles')
--     GestorVehiculos.getDeUnidad(unidad)      el de una unidad de Tropas
--
-- Las piezas del vehículo se manejan con `vehiculo:getPieza(nombre)`
-- (batalla/vehiculos/pieza.lua): setGiro, setDesplazamiento, setVisible... La
-- simulación (Tropas: cuándo despliega, sube la rampa o dispara) sigue
-- donde estaba; las especializaciones leen su estado en `vehiculo.unidad`.

local Vehiculo = require('batalla.vehiculos.vehiculo')

---@class GestorVehiculos
GestorVehiculos = GestorVehiculos or {}

GestorVehiculos.especializaciones = GestorVehiculos.especializaciones or {}
GestorVehiculos.tipos = GestorVehiculos.tipos or {}

local CARPETA_ESPECIALIZACIONES = 'batalla/vehiculos/especializaciones'
local CARPETA_TIPOS = 'batalla/vehiculos/tipos'

local cargado = false

-- Los vehículos creados (se olvidan solos al acabar su batalla).
local creados = setmetatable({}, { __mode = 'k' })

--- Registra la especialización `nombre` (una tabla de funciones).
---@param nombre string el mismo que el nombre del archivo
---@param especializacion Especializacion
function GestorVehiculos.registrarEspecializacion(nombre, especializacion)
    assert(type(especializacion) == 'table', 'GestorVehiculos: la especialización ' .. nombre .. ' no es una tabla')
    especializacion.nombre = nombre
    GestorVehiculos.especializaciones[nombre] = especializacion
end

--- Registra el tipo de vehículo `nombre`: { modelo, especializaciones }.
---@param nombre string
---@param datos table { modelo = 'assets/...', especializaciones = { 'nombre', ... } }
function GestorVehiculos.registrarTipo(nombre, datos)
    assert(datos.modelo, 'GestorVehiculos: el tipo ' .. nombre .. ' no dice su modelo')
    datos.nombre = nombre
    datos.especializaciones = datos.especializaciones or {}
    GestorVehiculos.tipos[nombre] = datos
end

--- Carga (con require) cada .lua de `carpeta`, en orden alfabético.
local function cargarCarpeta(carpeta)
    local archivos = love.filesystem.getDirectoryItems(carpeta)
    table.sort(archivos)
    for _, archivo in ipairs(archivos) do
        local nombre = archivo:match('^(.+)%.lua$')
        if nombre then
            require((carpeta .. '/' .. nombre):gsub('/', '.'))
        end
    end
end

--- Carga las especializaciones y los tipos (una vez).
function GestorVehiculos.cargar()
    if cargado then
        return
    end
    cargado = true
    cargarCarpeta(CARPETA_ESPECIALIZACIONES)
    cargarCarpeta(CARPETA_TIPOS)
end

--- El tipo registrado con el modelo `archivo` (con o sin .lua), o nil.
---@param archivo string
---@return table? tipo
function GestorVehiculos.tipoDeModelo(archivo)
    if not archivo then
        return nil
    end
    local ruta = archivo:gsub('%.lua$', '')
    for _, tipo in pairs(GestorVehiculos.tipos) do
        if tipo.modelo == ruta then
            return tipo
        end
    end
    return nil
end

--- Crea el vehículo de la unidad `unidad` con el modelo `archivo` y el
-- lanzador `lanzador` (batalla/lanzamisiles.lua). Sin tipo registrado, nil.
---@param unidad table
---@param archivo string
---@param lanzador table
---@return Vehiculo?
function GestorVehiculos.crear(unidad, archivo, lanzador)
    GestorVehiculos.cargar()
    local tipo = GestorVehiculos.tipoDeModelo(archivo)
    if not tipo then
        return nil
    end
    local vehiculo = Vehiculo.nuevo(unidad, tipo, {
        modelo = lanzador.modelo,
        matrices = unidad.matricesLanza,
        lanzador = lanzador,
    })
    for _, nombre in ipairs(tipo.especializaciones) do
        local especializacion = GestorVehiculos.especializaciones[nombre]
        assert(especializacion, 'GestorVehiculos: el tipo ' .. tipo.nombre .. ' pide la especialización ' .. nombre .. ', que no existe')
        if not especializacion.prerequisitos or especializacion.prerequisitos(vehiculo) then
            vehiculo:agregarEspecializacion(especializacion)
        end
    end
    unidad.vehiculo = vehiculo
    creados[vehiculo] = true
    vehiculo:llamar('onLoad')
    return vehiculo
end

--- Todos los vehículos creados, por bando y número de entrada.
---@return Vehiculo[]
function GestorVehiculos.getVehiculos()
    local lista = {}
    for vehiculo in pairs(creados) do
        lista[#lista + 1] = vehiculo
    end
    table.sort(lista, function(a, b)
        local ua, ub = a.unidad, b.unidad
        if (ua.bando or 0) ~= (ub.bando or 0) then
            return (ua.bando or 0) < (ub.bando or 0)
        end
        return (ua.numero or 0) < (ub.numero or 0)
    end)
    return lista
end

--- Los vehículos del tipo `nombre`, en el mismo orden.
---@param nombre string
---@return Vehiculo[]
function GestorVehiculos.getPorTipo(nombre)
    local lista = {}
    for _, vehiculo in ipairs(GestorVehiculos.getVehiculos()) do
        if vehiculo.tipo.nombre == nombre then
            lista[#lista + 1] = vehiculo
        end
    end
    return lista
end

--- El vehículo de la unidad `unidad` (nil si no tiene).
---@param unidad table
---@return Vehiculo?
function GestorVehiculos.getDeUnidad(unidad)
    return unidad.vehiculo
end

--- Antes de calcular las matrices de las piezas de `unidad` (si tiene vehículo).
---@param unidad table
function GestorVehiculos.posar(unidad)
    local vehiculo = unidad.vehiculo
    if vehiculo then
        vehiculo:llamar('onPose')
    end
end

--- Un paso de la batalla del vehículo de `unidad` (si tiene).
---@param unidad table
---@param dt number
function GestorVehiculos.actualizar(unidad, dt)
    local vehiculo = unidad.vehiculo
    if vehiculo then
        vehiculo:anotarMovimiento()
        vehiculo:llamar('onUpdate', dt)
    end
end

return GestorVehiculos

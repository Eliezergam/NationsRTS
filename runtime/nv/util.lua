-- Utilidades compartidas por los módulos de NV: la clase con constructor
-- "doble" y saneado de números y booleanos que llegan de datos guardados.
--
--   local NvUtil = require('runtime.nv.util')
--   local Ruta = NvUtil.class('Ruta')          -- una clase de runtime/class.lua
--   Ruta.new(a, b)  ==  Ruta:new(a, b)         -- las dos formas llaman a init
--
-- `runtime/class.lua` define `Clase:new(...)`; la especificación de NV y el
-- resto del runtime (`Units.new`, `Camera.new`) usan `Modulo.new(...)`. Aquí
-- `new` mira si el primer argumento es la propia clase y acepta ambas.

local Class = require('runtime.class')

local NvUtil = {}

--- Crea una clase (`Class(name, parent)`) cuyo `new` vale con punto y con
-- dos puntos.
function NvUtil.class(name, parent)
    local cls = Class(name, parent)
    local construct = cls.new
    cls.new = function(first, ...)
        if first == cls then
            return construct(cls, ...)
        end
        return construct(cls, first, ...)
    end
    return cls
end

local serial = 0

--- Número de serie creciente (órdenes, grupos, agentes): el orden de
-- creación desempata prioridades de forma reproducible.
function NvUtil.nextSerial()
    serial = serial + 1
    return serial
end

--- Número finito, o `fallback` si no es un número utilizable (texto que no
-- parsea, NaN, ±inf, nil).
function NvUtil.finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

--- Número finito acotado por abajo: `max(lo, finite(value, fallback))`.
function NvUtil.atLeast(value, fallback, lo)
    return math.max(lo or 0, NvUtil.finite(value, fallback))
end

--- Booleano tolerante: `false`/`'false'`/`0` → false; nil → `fallback`.
function NvUtil.bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == false or value == 'false' or value == 0 or value == '0' then
        return false
    end
    return true
end

--- Copia de una tabla plana (un nivel), o `{}`.
function NvUtil.shallowCopy(t)
    local out = {}
    if type(t) == 'table' then
        for k, v in pairs(t) do
            out[k] = v
        end
    end
    return out
end

--- Copia profunda de un valor de datos (tablas anidadas, sin ciclos).
function NvUtil.deepCopy(v)
    if type(v) ~= 'table' then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = NvUtil.deepCopy(x)
    end
    return out
end

--- Lista de `{x=, y=}` copiada y saneada: entradas sin números se saltan.
-- Admite también pares `{x, y}` y listas planas `{x1, y1, x2, y2, ...}`.
function NvUtil.copyPoints(points)
    local out = {}
    if type(points) ~= 'table' then
        return out
    end
    if #points > 0 and type(points[1]) == 'number' then
        for i = 1, #points - 1, 2 do
            local x, y = NvUtil.finite(points[i]), NvUtil.finite(points[i + 1])
            if x and y then
                out[#out + 1] = { x = x, y = y }
            end
        end
        return out
    end
    for i = 1, #points do
        local p = points[i]
        if type(p) == 'table' then
            local x, y = NvUtil.finite(p.x or p[1]), NvUtil.finite(p.y or p[2])
            if x and y then
                out[#out + 1] = { x = x, y = y }
            end
        end
    end
    return out
end

return NvUtil

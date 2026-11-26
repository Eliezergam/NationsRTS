-- Clases sencillas para el editor y el runtime.
--
--   local Class = require('runtime.class')
--   local Animal = Class('Animal')
--   function Animal:init(nombre) self.nombre = nombre end
--   function Animal:hablar() return '...' end
--
--   local Perro = Class('Perro', Animal)      -- hereda de Animal
--   function Perro:init(nombre) Animal.init(self, nombre) end
--   function Perro:hablar() return 'guau' end
--
--   local p = Perro:new('Rex')                -- llama a init
--   p:is(Animal)                              -- true
--   Perro.super == Animal                     -- true
--
-- Sin dependencias: el runtime se copia entero a los juegos generados, así que
-- este archivo tiene que valer igual dentro del editor y dentro de un juego.

local Class = {}

local function newInstance(cls, ...)
    local instance = setmetatable({}, cls)
    if cls.init then
        cls.init(instance, ...)
    end
    return instance
end

local function isInstanceOf(instance, cls)
    local mt = getmetatable(instance)
    while mt do
        if mt == cls then
            return true
        end
        mt = mt.super
    end
    return false
end

--- Crea una clase. `parent` es opcional.
function Class.new(name, parent)
    local cls = {}
    cls.__index = cls
    cls.__name = name or 'Class'
    cls.super = parent
    cls.new = newInstance
    cls.is = isInstanceOf
    cls.extend = function(_, childName)
        return Class.new(childName, cls)
    end
    cls.__tostring = function(self)
        return (rawget(getmetatable(self), '__name') or 'Class') .. ' instance'
    end
    if parent then
        setmetatable(cls, { __index = parent, __call = newInstance })
    else
        setmetatable(cls, { __call = newInstance })
    end
    return cls
end

--- Nombre de la clase de una instancia (o de una clase).
function Class.nameOf(value)
    local mt = type(value) == 'table' and getmetatable(value) or nil
    if type(value) == 'table' and rawget(value, '__name') then
        return rawget(value, '__name')
    end
    return mt and rawget(mt, '__name') or type(value)
end

return setmetatable(Class, {
    __call = function(_, name, parent)
        return Class.new(name, parent)
    end,
})

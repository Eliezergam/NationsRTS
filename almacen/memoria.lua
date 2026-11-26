-- Lo del almacén 3D de cada nación que no es simulación: dónde quedó cada
-- caja (almacen/disposicion.lua), los ordenadores de la sala con sus
-- carpetas personales y lo que enseña el muro (almacen/pc/). Es una sección
-- de la partida (partida/guardado.lua): se guarda y se carga con ella.
--
--   Memoria.de(nacion)  la tabla de esa nación: { cajas, ordenadores, muro }

local Memoria = {}

local porNacion = {}

function Memoria.de(nacion)
    local m = porNacion[nacion]
    if not m then
        m = {}
        porNacion[nacion] = m
    end
    return m
end

--- Para la partida: todo, por nación.
function Memoria.guardar()
    return porNacion
end

--- De la partida (nil: partida nueva, todo vacío).
function Memoria.cargar(datos)
    porNacion = type(datos) == 'table' and datos or {}
end

return Memoria

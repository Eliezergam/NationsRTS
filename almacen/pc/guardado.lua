-- Lo de los ordenadores de la sala (las ventanas abiertas de cada puesto con
-- lo que tenía cada programa, la carpeta personal con lo que se escribió y
-- lo que enseña el muro) va en la memoria del almacén de la nación
-- (almacen/memoria.lua), dentro de la partida (partida/guardado.lua).
--
-- Antes iba en su propio archivo, `almacen_ordenadores.lua`: aquí solo se lee
-- una vez, para traer lo que tenía si es de la misma partida y nación.
--
-- Lo que no es dato (un programa de Lua corriendo, cosas de pantalla) no se
-- guarda: las claves que empiezan por '_' y las funciones se saltan.

local Guardado = {}

Guardado.archivo = 'almacen_ordenadores.lua'

--- Lo del archivo de antes para esta partida y nación (ordenadores, muro),
-- o nil.
function Guardado.leerViejo(almacen, semilla)
    if not love.filesystem.getInfo(Guardado.archivo) then
        return nil
    end
    local bien, datos = pcall(function()
        return love.filesystem.load(Guardado.archivo)()
    end)
    if bien and type(datos) == 'table' and datos.semilla == semilla and datos.nacion == almacen:getNacion() then
        return datos.ordenadores, datos.muro
    end
    return nil
end

return Guardado

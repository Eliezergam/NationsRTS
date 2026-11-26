-- Lo de los ordenadores de la sala, en disco (el dueño, 26-nov: «que se
-- guarde lo que abres»): las ventanas abiertas de cada puesto, con lo que
-- tenía cada programa (la terminal con su texto, la hoja en su celda...), y
-- la carpeta personal con lo que se escribió. Se guarda con las cajas del
-- almacén (cada 30 s, al salir y al cerrar el juego) y se lee al entrar si es
-- la misma partida y nación.
--
-- Lo que no es dato (un programa de Lua corriendo, cosas de pantalla) no se
-- guarda: las claves que empiezan por '_' y las funciones se saltan.

local Guardado = {}

Guardado.archivo = 'almacen_ordenadores.lua'

local function serializar(v, sangria)
    sangria = sangria or ''
    local t = type(v)
    if t == 'table' then
        local partes = { '{\n' }
        local otra = sangria .. '    '
        for k, x in pairs(v) do
            local tk = type(k)
            local valida = (tk == 'number' or (tk == 'string' and k:sub(1, 1) ~= '_'))
            local tx = type(x)
            if valida and (tx == 'table' or tx == 'string' or tx == 'number' or tx == 'boolean') then
                local clave = tk == 'number' and ('[' .. k .. ']') or ('[' .. string.format('%q', k) .. ']')
                partes[#partes + 1] = otra .. clave .. ' = ' .. serializar(x, otra) .. ',\n'
            end
        end
        partes[#partes + 1] = sangria .. '}'
        return table.concat(partes)
    elseif t == 'string' then
        return string.format('%q', v)
    elseif t == 'number' then
        -- inf y nan no se leen de vuelta.
        if v ~= v or v == math.huge or v == -math.huge then
            return '0'
        end
        return string.format('%.17g', v)
    else
        return tostring(v)
    end
end

--- Guarda `ordenadores` (la lista de `datos` de cada puesto).
function Guardado.guardar(almacen, semilla, ordenadores)
    local datos = { semilla = semilla, nacion = almacen:getNacion(), ordenadores = ordenadores }
    local bien, texto = pcall(serializar, datos)
    if bien then
        love.filesystem.write(Guardado.archivo, 'return ' .. texto .. '\n')
    else
        print('ORDENADORES no se pudieron guardar: ' .. tostring(texto))
    end
end

--- Lo guardado de esta partida y nación, o nil.
function Guardado.leer(almacen, semilla)
    if not love.filesystem.getInfo(Guardado.archivo) then
        return nil
    end
    local bien, datos = pcall(function()
        return love.filesystem.load(Guardado.archivo)()
    end)
    if bien and type(datos) == 'table' and datos.semilla == semilla and datos.nacion == almacen:getNacion() then
        return datos.ordenadores
    end
    return nil
end

return Guardado

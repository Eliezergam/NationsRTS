--- Perfil del hilo principal de Lua en el juego real (cualquier escena):
--
--   PERFIL_LUA=<segundos> love . 42 --almacen --seguir
--
-- Con el perfilador de muestreo de LuaJIT (jit.profile, una muestra por
-- milisegundo) cuenta en qué función está el hilo, con su pila de 3
-- niveles, y en qué estado de la máquina virtual (compilado, interpretado,
-- en C, recogiendo basura o compilando). Espera `PERFIL_LUA_ESPERA` s a que
-- cargue (12 por defecto), mide `segundos`, imprime las líneas `PERFIL` con
-- lo que más tiempo se lleva y cierra el juego.

local Perfil = {}

local ESTADOS = { N = 'compilado', I = 'interpretado', C = 'en C', G = 'basura (GC)', J = 'compilando' }

function Perfil.empezar(segundos)
    local perfil = require('jit.profile')
    local espera = tonumber(os.getenv('PERFIL_LUA_ESPERA') or '') or 12
    local porFuncion, porPila, porEstado = {}, {}, {}
    local total = 0
    local midiendo = false
    local inicio = love.timer.getTime()

    local function muestra(hilo, cuantas, estado)
        if not midiendo then
            return
        end
        total = total + cuantas
        porEstado[estado] = (porEstado[estado] or 0) + cuantas
        local f = perfil.dumpstack(hilo, 'pF', 1)
        porFuncion[f] = (porFuncion[f] or 0) + cuantas
        local p = perfil.dumpstack(hilo, 'pF;', -3)
        porPila[p] = (porPila[p] or 0) + cuantas
    end

    local function ordenar(tabla)
        local lista = {}
        for clave, n in pairs(tabla) do
            lista[#lista + 1] = { clave, n }
        end
        table.sort(lista, function(a, b)
            return a[2] > b[2]
        end)
        return lista
    end

    local function informe()
        perfil.stop()
        print(string.format('PERFIL %d muestras en %d s', total, segundos))
        for _, e in ipairs(ordenar(porEstado)) do
            print(string.format('PERFIL estado %-13s %5.1f %%', ESTADOS[e[1]] or e[1], e[2] * 100 / total))
        end
        for k, e in ipairs(ordenar(porFuncion)) do
            if k > 25 then
                break
            end
            print(string.format('PERFIL función %5.1f %%  %s', e[2] * 100 / total, e[1]))
        end
        for k, e in ipairs(ordenar(porPila)) do
            if k > 15 then
                break
            end
            print(string.format('PERFIL pila %5.1f %%  %s', e[2] * 100 / total, e[1]))
        end
    end

    perfil.start('fi1', muestra)
    -- Lo mueve el bucle del juego: empezar tras la espera y cerrar al final.
    local actualizar = love.update
    love.update = function(...)
        local ahora = love.timer.getTime() - inicio
        if not midiendo and ahora > espera then
            midiendo = true
        elseif midiendo and ahora > espera + segundos then
            informe()
            love.event.quit(0)
        end
        return actualizar(...)
    end
end

return Perfil

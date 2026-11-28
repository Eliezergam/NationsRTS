-- El recolector de basura de Lua a pasos, en un momento fijo del cuadro y con
-- tiempo tope.
--
-- El recolector de LuaJIT es incremental, pero trabaja dentro de cualquier
-- línea que pida memoria, y con 40 robots en guerra eran parones de 0,2-0,3 s
-- (27-nov). Aquí, como hacen los juegos con Lua: entre un paso y otro el
-- recolector automático no actúa salvo que la memoria se doble (red de
-- seguridad), y al empezar cada cuadro se le da el trabajo que le habría
-- tocado por lo que se pidió en el cuadro anterior (`step` con esos KB: el
-- mismo ritmo que el automático), sin pasar de `presupuesto` s. Lo que no
-- quepa se queda de deuda para el siguiente; si la deuda pasa de un cuarto de
-- lo vivo, el tope se cuadruplica, y si pasa de todo lo vivo (una carga que
-- pide memoria a chorro) vuelve a trabajar también el automático, como
-- siempre. Una vuelta nueva empieza cuando la memoria pasa de `pausa` veces
-- lo que quedó vivo en la anterior. Va en love.update: todas las escenas,
-- desde `desde` KB. En el mapa de campaña (20-45 MB vivos) también: el 27-nov
-- el cierre de una vuelta del automático (su fase atómica, que no se parte)
-- caía donde se pedía memoria, sobre todo al pedir comarcas, y daba cuadros
-- de 20-35 ms; a pasos, en la partida del día 38 perdían el refresco de la
-- pantalla de 157 Hz 115-135 cuadros de 3000 en vez de 149-160, y en una del
-- día 1047, 286-324 en vez de 349-374. (Antes de los arreglos del mapa de
-- ese día salía al revés: el paso añadía trabajo y por eso se usaba solo
-- con más de 256 MB.)
--
-- RECOLECTOR_DEPURAR=1 apunta cada paso que tarde más de 10 ms y cada vuelta
-- (líneas `RECOLECTOR`). Un paso no se puede partir, y el cierre de cada
-- vuelta (la fase atómica) va entero en uno.

local Recolector = {}

Recolector.presupuesto = 0.002 -- s por cuadro
Recolector.pausa = 1.5
Recolector.trozo = 64 -- KB de trabajo por llamada
Recolector.desde = 0 -- KB de memoria desde los que toma el mando
Recolector.depurar = os.getenv('RECOLECTOR_DEPURAR') ~= nil
-- true mientras alguien lo tiene parado a propósito (batalla/robots/medir.lua
-- cuenta así la basura de cada cuadro).
Recolector.parado = false
-- RECOLECTOR=0 lo deja como venía (el automático de LuaJIT), para comparar.
Recolector.activo = os.getenv('RECOLECTOR') ~= '0'

-- KB vivos al acabar la última vuelta, si hay una a medias, KB de trabajo
-- pendiente y la memoria al acabar el paso anterior.
local vivo
local enVuelta = false
local deuda = 0
local ultima
-- Con RECOLECTOR_DEPURAR: cuadros, tiempo y pico de memoria de la vuelta.
local cuadros, tiempo, pico = 0, 0, 0

--- Un cuadro de trabajo del recolector.
function Recolector.paso()
    if Recolector.parado or not Recolector.activo then
        return
    end
    local memoria = collectgarbage('count')
    if not enVuelta and memoria < Recolector.desde then
        -- Poca memoria: que siga el automático, como siempre.
        vivo, ultima = nil, nil
        return
    end
    vivo = vivo or memoria
    -- Entre un paso y otro no se libera nada: lo que ha subido es lo pedido.
    if enVuelta and ultima and memoria > ultima then
        deuda = deuda + memoria - ultima
    end
    if not enVuelta and memoria > vivo * Recolector.pausa then
        enVuelta = true
        deuda = Recolector.trozo
    end
    if enVuelta then
        local ahora = love.timer.getTime
        local presupuesto = Recolector.presupuesto
        if deuda > vivo * 0.25 then
            presupuesto = presupuesto * 4
        end
        local inicio = ahora()
        local fin = inicio + presupuesto
        cuadros = cuadros + 1
        pico = math.max(pico, memoria)
        repeat
            local antes = Recolector.depurar and ahora()
            local acaba = collectgarbage('step', Recolector.trozo)
            deuda = deuda - Recolector.trozo
            if antes and ahora() - antes > 0.01 then
                print(string.format('RECOLECTOR paso de %.0f ms (%.0f MB)%s', (ahora() - antes) * 1000,
                    collectgarbage('count') / 1024, acaba and ', fin de vuelta' or ''))
            end
            if acaba then
                enVuelta = false
                deuda = 0
                vivo = collectgarbage('count')
                if Recolector.depurar then
                    print(string.format('RECOLECTOR vuelta en %d cuadros, %.0f ms de trabajo; pico %.0f MB, quedan %.0f MB',
                        cuadros, (tiempo + ahora() - inicio) * 1000, pico / 1024, vivo / 1024))
                end
                cuadros, tiempo, pico = 0, 0, 0
                inicio = ahora()
            end
        until not enVuelta or deuda <= 0 or ahora() >= fin
        tiempo = tiempo + ahora() - inicio
    end
    if deuda > vivo then
        -- Muy por detrás: el automático también, al ritmo de lo que se pida.
        collectgarbage('restart')
    else
        -- Sin trabajo automático hasta que la memoria se doble desde aquí.
        collectgarbage('restart', -1)
    end
    ultima = collectgarbage('count')
end

return Recolector

-- Inteligencia: lo que el jugador sabe del poder y del arsenal de lo ajeno
-- (decisión del dueño: el poder de lo enemigo está oculto). Lo propio se ve
-- siempre; de una ciudad, instalación o ejército de otra nación solo se ve lo
-- que diga el último informe de sus exploradores, con su antigüedad («hace 3
-- días»). Sin informe: «Desconocido · Explorar». El observador (sin nación
-- que mire) lo ve todo.
--
-- Solo lee la simulación: `sim:informe(nacion, objetivo)` (Andrés) da nil o
-- { dia, poder, tropas = { soldados, lanzacohetes }, defensas, vida,
-- vidaMax }. Lo ajeno sin informe (poder, arsenal y vida) queda desconocido.
-- Si esa consulta aún no existe, todo lo ajeno queda desconocido.

local Tema = require('interfaz.tema')
local Simulacion = require('mundo.simulacion')

local Inteligencia = {}

Inteligencia.textoDesconocido = 'Desconocido · Explorar'

--- ¿Lo de la nación `duena` está oculto para la nación `mira`? (nil: observador).
function Inteligencia.oculto(mira, duena)
    return mira ~= nil and duena ~= nil and duena ~= mira
end

--- Último informe de `mira` sobre `objetivo` (id de sitio o de grupo), o nil.
function Inteligencia.informe(sim, mira, objetivo)
    if not (sim.informe and mira and objetivo) then
        return nil
    end
    return sim:informe(mira, objetivo)
end

--- «hoy», «hace 1 día», «hace 5 días» desde el día `dia` del informe.
function Inteligencia.hace(sim, dia)
    local dias = math.max(0, sim.estado.dia - (dia or sim.estado.dia))
    if dias == 0 then
        return 'hoy'
    end
    return string.format('hace %d %s', dias, dias == 1 and 'día' or 'días')
end

--- Vida de 0 a 100 de un informe (la de una instalación viene en salud,
-- sobre su máximo `vidaMax`).
function Inteligencia.vidaInforme(inf)
    local maxima = inf.vidaMax or 100
    if maxima <= 0 then
        return 0
    end
    return math.max(0, math.min(100, (inf.vida or 0) / maxima * 100))
end

--- Poder de `objetivo` (de la nación `duena`, con poder real `poder`) tal como
-- lo ve `mira`. Devuelve el texto, si se conoce y el informe (o nil).
function Inteligencia.textoPoder(sim, mira, objetivo, duena, poder)
    if not Inteligencia.oculto(mira, duena) then
        return Tema.numero(Simulacion.poderRedondeado(poder or 0)), true, nil
    end
    local inf = Inteligencia.informe(sim, mira, objetivo)
    if not inf then
        return Inteligencia.textoDesconocido, false, nil
    end
    local cifra = Tema.numero(Simulacion.poderRedondeado(inf.poder or 0))
    return cifra .. ' · ' .. Inteligencia.hace(sim, inf.dia), true, inf
end

--- Poder corto para los rótulos del mapa: la cifra, «1 240 (3 d)» con
-- informe viejo o «?» si se desconoce.
function Inteligencia.poderCorto(sim, mira, objetivo, duena, poder)
    if not Inteligencia.oculto(mira, duena) then
        return Tema.numero(Simulacion.poderRedondeado(poder or 0))
    end
    local inf = Inteligencia.informe(sim, mira, objetivo)
    if not inf then
        return '?'
    end
    local cifra = Tema.numero(Simulacion.poderRedondeado(inf.poder or 0))
    local dias = math.max(0, sim.estado.dia - (inf.dia or sim.estado.dia))
    if dias == 0 then
        return cifra
    end
    return string.format('%s (%d d)', cifra, dias)
end

--- Ficha de un grupo vista por `mira` (la de `sim:fichaGrupo`, copiada): si
-- es ajeno, su poder y su composición salen del informe o quedan ocultos
-- (`poderOculto`; `informeDia` si hay informe).
function Inteligencia.ficha(sim, gid, mira)
    local ficha = sim:fichaGrupo(gid, mira)
    if not ficha or not Inteligencia.oculto(mira, ficha.nacion) then
        return ficha
    end
    local copia = {}
    for k, v in pairs(ficha) do
        copia[k] = v
    end
    copia.poder, copia.poderRedondeado, copia.composicion = nil, nil, nil
    local inf = Inteligencia.informe(sim, mira, gid)
    if inf then
        copia.poder = inf.poder
        copia.poderRedondeado = Simulacion.poderRedondeado(inf.poder or 0)
        copia.informeDia = inf.dia
        copia.diasInforme = math.max(0, sim.estado.dia - (inf.dia or sim.estado.dia))
        local t = inf.tropas or {}
        copia.composicion = {
            soldados = t.soldados or 0,
            lanzacohetes = t.lanzacohetes or 0,
            heridos = { soldados = 0, lanzacohetes = 0 },
        }
    else
        copia.poderOculto = true
    end
    return copia
end

--- Poder del bando rival de una batalla (`b` de `sim:batallasEnCurso`)
-- visto por `mira`: si el rival defiende un sitio y hay informe de ese sitio,
-- el del informe; si no, desconocido. `rival` = 'atacante' o 'defensor'.
function Inteligencia.poderRival(sim, mira, b, rival)
    local bando = b[rival]
    local naciones = bando.naciones or {}
    local duena = naciones[1]
    if not Inteligencia.oculto(mira, duena) then
        return Tema.numero(Simulacion.poderRedondeado(bando.poder or 0)), true
    end
    local sitio = bando.sitio
    local inf = sitio and Inteligencia.informe(sim, mira, sitio.id)
    if not inf then
        return 'desconocido', false
    end
    return Tema.numero(Simulacion.poderRedondeado(inf.poder or 0)) .. ' (' .. Inteligencia.hace(sim, inf.dia) .. ')',
        true
end

return Inteligencia

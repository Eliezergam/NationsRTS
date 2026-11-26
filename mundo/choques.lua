-- Choques entre ejércitos en campo abierto (solo vista y entrada a la batalla)
-- y el enganche de las batallas de la simulación con la escena 3D
-- (`deBatalla` arma el combate con lo sano, su munición y su escuadra;
-- `resultadoDeEscena` recoge unidad por unidad lo que pasó para
-- `resolverBatalla`).
--
-- Un choque es un encuentro de dos ejércitos de naciones en guerra fuera de
-- cualquier sitio. Los decide la simulación (`sim:choques()`: lista de
-- `{ a, b, x, y, jugador, batalla }`: el primer grupo de cada bando de una
-- batalla en 'campo'; cada grupo apunta a su batalla en `g.batalla`). La
-- vista solo los lee.
--
-- En el mapa, las dos fichas de un choque se dibujan juntas y enfrentadas
-- (ver `Mundo:dibujarFichas`); aquí se arma también la tabla `combate` para la
-- escena 3D (GUIA-3D.md, §4.1).

local Simulacion = require('mundo.simulacion')

local Choques = {}

Choques.separacion = 50 -- px de pantalla entre las astas de las dos fichas trabadas

-- La escena 3D de hoy (batalla/escena.lua) lee `combate.sitio.color` al
-- dibujar y falla con `sitio = nil`. Mientras sea así, se le da un sitio de
-- tipo 'campo' fuera del área de la batalla (su edificio queda en la niebla).
-- Cuando Codex lo arregle, basta con poner esto a true.
Choques.escenaAceptaSinSitio = true

--- Choques de ahora (de la simulación), solo los que tienen sus dos grupos
-- vivos. Sin `sim:choques()` (una partida de otra versión), ninguno.
function Choques.lista(mundo)
    local sim = mundo.sim
    if type(sim.choques) ~= 'function' then
        return {}
    end
    local grupos = sim.estado.grupos
    local out = {}
    for _, c in ipairs(sim:choques()) do
        if grupos[c.a] and grupos[c.b] then
            out[#out + 1] = c
        end
    end
    return out
end

--- Índice grupo -> choque en que está.
function Choques.indice(lista)
    local por = {}
    for _, c in ipairs(lista) do
        por[c.a], por[c.b] = c, c
    end
    return por
end

--- Clave estable de un choque (para los pregones).
function Choques.clave(c)
    return c.a .. ':' .. c.b
end

--- Un bando de la tabla `combate` a partir de un grupo.
local function bando(sim, gr)
    local n = sim:nacion(gr.nacion)
    return {
        nombre = n and n.nombre or '?',
        color = n and n.color or { 1, 1, 1 },
        lanzacohetes = gr.lanzacohetes or 0,
        lanzacohetesPor = gr.lanzacohetesPor,
        soldados = gr.soldados or 0,
        fuerza = Simulacion.vidaGrupo(gr),
    }
end

--- Tabla `combate` (GUIA-3D.md, §4.1) de un choque en campo abierto: centro en
-- el punto del choque, ángulo de a hacia b, a ataca y b defiende, sin sitio.
function Choques.combate(mundo, c)
    local sim = mundo.sim
    local ga, gb = sim.estado.grupos[c.a], sim.estado.grupos[c.b]
    if not (ga and gb) then
        return nil
    end
    -- Los dos se quedan quietos en su (x, y) mientras están trabados.
    local ax, ay = ga.x or c.x, ga.y or c.y
    local bx, by = gb.x or c.x, gb.y or c.y
    local angulo = 0
    if (bx - ax) ^ 2 + (by - ay) ^ 2 > 1 then
        angulo = math.atan2(by - ay, bx - ax)
    end
    local combate = {
        grupo = c.a,
        choque = { a = c.a, b = c.b },
        cx = c.x,
        cy = c.y,
        angulo = angulo,
        atacante = bando(sim, ga),
        defensor = bando(sim, gb),
        sitio = nil, -- campo abierto: no hay edificio
    }
    if not Choques.escenaAceptaSinSitio then
        -- Protección hasta que la escena acepte `sitio = nil` (ver arriba):
        -- un 'campo' a un área de distancia, que no se ve ni ocupa sitio.
        local lejos = 60000
        local x, y = c.x + lejos, c.y + lejos
        combate.sitio = {
            tipo = 'campo',
            x = x,
            y = y,
            z = mundo.terreno:altura(x, y),
            color = combate.defensor.color,
        }
    end
    return combate
end

--- Copia de una tabla de munición.
local function copiaMunicion(m)
    m = m or {}
    return { balas = m.balas or 0, misiles = m.misiles or 0 }
end

--- Bando de la tabla `combate` a partir del resumen de un bando de
-- `sim:estadoBatalla`: solo lo sano pelea (con la guarnición, en el
-- defensor), exactamente. `fuentes` dice de qué grupo (`clave` = su id) o de
-- la guarnición (`clave` = 'sitio') sale cada unidad, de qué modelos
-- (`lanzacohetesPor`) y con qué munición; `escuadra`, cuántos
-- soldados es cada figura (F10).
local function bandoDeResumen(sim, resumen)
    local nid = resumen.naciones[1] or (resumen.sitio and resumen.sitio.nacion)
    local n = nid and sim:nacion(nid)
    local fuentes = {}
    for _, g in ipairs(resumen.grupos) do
        fuentes[#fuentes + 1] = {
            clave = g.id,
            soldados = g.soldados or 0,
            lanzacohetes = g.lanzacohetes or 0,
            lanzacohetesPor = g.lanzacohetesPor,
            municion = copiaMunicion(g.municion),
        }
    end
    local s = resumen.sitio
    if s then
        fuentes[#fuentes + 1] = {
            clave = 'sitio',
            soldados = s.soldados or 0,
            lanzacohetes = s.lanzacohetes or 0,
            lanzacohetesPor = s.lanzacohetesPor,
            municion = copiaMunicion(s.municion),
        }
    end
    return {
        nombre = n and n.nombre or '?',
        color = n and n.color or { 1, 1, 1 },
        lanzacohetes = resumen.sanos.lanzacohetes or 0,
        soldados = resumen.sanos.soldados or 0,
        sanosPor = resumen.sanosPor,
        fuerza = math.max(1, resumen.poder or 0),
        fuentes = fuentes,
        escuadra = resumen.escuadra,
    }
end

--- Tabla `combate` (GUIA-3D.md, §4.1) de una batalla de la simulación, a
-- partir de su `estado` (`sim:estadoBatalla`): los dos bandos con lo sano de
-- ese momento (se puede entrar a mitad; cada bando se despliega de nuevo en
-- su lado) y, si se defiende un sitio, el sitio. `describir` es
-- `Escena.describir` (se pasa para no cargar la escena desde el mapa). Con
-- `nid` (la nación del jugador), `ladoJugador` dice en qué bando pelea: la
-- escena solo enseña la munición de ese bando (lo ajeno, sin informe).
function Choques.deBatalla(mundo, estado, describir, nid)
    local sim = mundo.sim
    local primero = estado.atacante.grupos[1]
    local g = primero and sim.estado.grupos[primero.id]
    -- De dónde viene el atacante: su punto de salida, o el lugar mismo.
    local origen = g and (sim:sitio(g.origen or g.desde) or (g.ruta and { x = g.ruta[1], y = g.ruta[2] }))
    local angulo = 0
    if origen and (estado.x - origen.x) ^ 2 + (estado.y - origen.y) ^ 2 > 1 then
        angulo = math.atan2(estado.y - origen.y, estado.x - origen.x)
    end
    local sitio = estado.lugar.tipo == 'sitio' and estado.defensor.sitio and sim:sitio(estado.defensor.sitio.id)
    local combate
    if sitio then
        combate = describir(mundo, g or { nacion = estado.atacante.naciones[1] }, sitio, angulo)
    else
        combate = { cx = estado.x, cy = estado.y, angulo = angulo, sitio = nil }
    end
    combate.grupo = primero and primero.id or nil
    combate.batalla = estado.id
    combate.atacante = bandoDeResumen(sim, estado.atacante)
    combate.defensor = bandoDeResumen(sim, estado.defensor)
    for _, lado in ipairs({ 'atacante', 'defensor' }) do
        local r = estado[lado]
        for _, n in ipairs(r.naciones) do
            if n == nid then
                combate.ladoJugador = lado
            end
        end
        if nid and r.sitio and r.sitio.nacion == nid then
            combate.ladoJugador = lado
        end
    end
    return combate
end

--- Resultado de una escena para `resolverBatalla` (formato de la cabecera
-- de mundo/simulacion/batallas.lua): la clasificación de cada unidad de la
-- escena (`Tropas:resultado`, F11), 1:1, sin proporciones. El sorteo de los
-- muertos sale de la semilla del mundo y del id de la batalla.
function Choques.resultadoDeEscena(tropas, semilla, bid)
    return tropas:resultado(semilla, bid)
end

return Choques

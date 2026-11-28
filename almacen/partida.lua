-- Los datos de la partida de una nación, tal como los enseña la barra de
-- arriba del mapa (interfaz/barrasuperior.lua): nombre, capital, poder,
-- nivel, día, los cuatro recursos y las últimas noticias. Los usan las
-- pantallas de la sala de control del almacén (almacen/sala.lua) por
-- `Almacen:getPartida()`.
--
-- Solo lee la simulación; no cambia nada.

local Partida = {}

local NOMBRES = { metal = 'Metal', petroleo = 'Petróleo', comida = 'Comida', dinero = 'Dinero' }

-- Cuántas noticias se copian.
Partida.NOTICIAS = 8
-- Cuántas publicaciones de los presidentes en Ondix (la red social) se copian.
Partida.ONDIX = 60
-- Cuántas publica la gente cada día como mucho (se generan, no se guardan).
Partida.GENTE_DIA = 45

--- Foto de los datos de la nación `nid` ahora mismo, o nil si no existe.
-- {
--   nacion, capital, habitantes, poder, nivel, dia, anio, ciudades,
--   recursos = { { tipo, nombre, cantidad, tope, estado } x4 },
--   noticias = { { dia, texto, color } },
--   ondix = { { id, dia, tipo, nacion, usuario, presidente, color, texto,
--               sobre, apoyos, reenvios, comentarios, aFavor, semilla,
--               cita = (otra igual, sin cita) } },
--   perfiles = { { usuario, presidente, nacion, color, capital, orden,
--                  habitantes, seguidores, tono, jugador } },
-- }
-- Las cifras son las mismas que las de la barra de arriba: el dinero es todo
-- el tesoro (bóveda más lo de afuera) y la comida la de la ciudad peor
-- alimentada.
function Partida.leer(sim, nid)
    local nacion = sim and sim:nacion(nid)
    if not nacion then
        return nil
    end
    local almacen = sim:almacenDe(nid)
    local reservas = {}
    for _, r in ipairs(sim:reservas(nid)) do
        reservas[r.tipo] = r
    end
    local capital = sim:ciudad(nacion.capital)
    local dia = math.max(1, sim.estado.dia or 1)
    local recursos = {
        { tipo = 'metal', cantidad = almacen.metal, tope = almacen.almacen },
        { tipo = 'petroleo', cantidad = almacen.petroleo, tope = almacen.almacen },
        { tipo = 'comida' },
        { tipo = 'dinero', cantidad = almacen.dinero + (almacen.afuera.dinero or 0), tope = almacen.boveda },
    }
    for _, d in ipairs(recursos) do
        local r = reservas[d.tipo]
        if d.tipo == 'comida' then
            d.cantidad, d.tope = r and r.cantidad or 0, r and r.tope or 0
        end
        d.nombre = NOMBRES[d.tipo]
        d.estado = r and r.estado or 'holgado'
    end
    local noticias = {}
    for k = 1, math.min(Partida.NOTICIAS, #sim.estado.noticias) do
        local n = sim.estado.noticias[k]
        noticias[k] = { dia = n.dia, texto = n.texto, color = n.color }
    end
    local ondix, perfiles = {}, {}
    if sim.publicacionesOndix then
        local Ondix = sim.Ondix
        local e = sim.estado
        local todas = sim:publicacionesOndix()
        local porId = {}
        for _, p in ipairs(todas) do
            porId[p.id] = p
        end
        local function datos(p)
            local autor = sim:nacion(p.autor)
            local apoyos, reenvios, comentarios = Ondix.alcanceEn(p, e.dia)
            return {
                id = p.id,
                dia = p.dia,
                tipo = p.tipo,
                nacion = autor and autor.nombre or '?',
                usuario = Ondix.usuario(sim, p.autor),
                presidente = autor and autor.gobernante and autor.gobernante.nombre or '',
                color = autor and autor.color or { 1, 1, 1 },
                texto = p.texto,
                sobre = p.sobre and Ondix.usuario(sim, p.sobre) or nil,
                apoyos = apoyos,
                reenvios = reenvios,
                comentarios = comentarios,
                aFavor = p.aFavor,
                semilla = p.semilla,
                hora = p.hora or ((p.semilla or 0) % 1000) / 1000,
            }
        end
        for k = 1, math.min(Partida.ONDIX, #todas) do
            local p = todas[k]
            local d = datos(p)
            local citada = p.cita and porId[p.cita]
            d.cita = citada and datos(citada) or nil
            ondix[k] = d
        end
        -- La gente también publica (mundo/simulacion/ondix_gente.lua): lo de
        -- los últimos días, generado de la semilla, sin guardarse.
        local Gente = require('mundo.simulacion.ondix_gente')
        local mundo = { naciones = {}, presidentes = ondix, dia = e.dia, hora = (e.paso or 0) / sim.pasosDia }
        local habitantesTotal = 0
        local idsNaciones = {}
        for id in pairs(e.naciones) do
            idsNaciones[#idsNaciones + 1] = id
        end
        table.sort(idsNaciones, function(x, y)
            return tostring(x) < tostring(y)
        end)
        for _, id in ipairs(idsNaciones) do
            local n = e.naciones[id]
            if #sim:ciudadesDe(id) > 0 then
                local capital = sim:ciudad(n.capital)
                local gente = Ondix.habitantes(sim, id)
                habitantesTotal = habitantesTotal + gente
                mundo.naciones[#mundo.naciones + 1] = { nombre = n.nombre, capital = capital and capital.nombre or '', habitantes = gente }
            end
        end
        -- Cada día publica más gente cuanto más pasa en el mundo.
        local delDia = {}
        for _, p in ipairs(ondix) do
            delDia[p.dia] = (delDia[p.dia] or 0) + 1
        end
        local deLaGente = {}
        for dia = math.max(1, e.dia - 2), e.dia do
            local porDia = math.min(Partida.GENTE_DIA, 8 + math.floor(habitantesTotal / 8000) + 3 * (delDia[dia] or 0))
            mundo.usados = {}
            for k = 1, porDia do
                deLaGente[#deLaGente + 1] = Gente.publicacion(e.semilla, dia, k, mundo)
            end
        end
        for _, p in ipairs(deLaGente) do
            ondix[#ondix + 1] = p
        end
        table.sort(ondix, function(x, y)
            if x.dia ~= y.dia then
                return x.dia > y.dia
            end
            if x.hora ~= y.hora then
                return x.hora > y.hora
            end
            return tostring(x.id) < tostring(y.id)
        end)
        -- Los perfiles: un presidente por nación, en orden fijo.
        local ids = {}
        for id in pairs(e.naciones) do
            ids[#ids + 1] = id
        end
        table.sort(ids, function(x, y)
            return tostring(x) < tostring(y)
        end)
        for _, id in ipairs(ids) do
            local n = e.naciones[id]
            if #sim:ciudadesDe(id) > 0 then
                local capital = sim:ciudad(n.capital)
                local gente = Ondix.habitantes(sim, id)
                perfiles[#perfiles + 1] = {
                    usuario = Ondix.usuario(sim, id),
                    presidente = n.gobernante and n.gobernante.nombre or '',
                    nacion = n.nombre,
                    color = n.color,
                    capital = capital and capital.nombre or '-',
                    orden = n.orden and Ondix.nombreOrden(sim, n.orden) or '',
                    habitantes = gente,
                    seguidores = math.floor(gente * 0.6),
                    tono = Ondix.tono(n),
                    jugador = n.jugador and true or false,
                }
            end
        end
    end
    return {
        ondix = ondix,
        perfiles = perfiles,
        nacion = nacion.nombre,
        capital = capital and capital.nombre or '-',
        habitantes = capital and capital.poblacion or 0,
        poder = sim:fuerza(nid),
        nivel = sim:nivelCapital(nid),
        dia = dia,
        anio = sim.anioDelJuego(dia),
        ciudades = #sim:ciudadesDe(nid),
        recursos = recursos,
        noticias = noticias,
    }
end

return Partida

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

--- Foto de los datos de la nación `nid` ahora mismo, o nil si no existe.
-- {
--   nacion, capital, habitantes, poder, nivel, dia, anio, ciudades,
--   recursos = { { tipo, nombre, cantidad, tope, estado } x4 },
--   noticias = { { dia, texto, color } },
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
    return {
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

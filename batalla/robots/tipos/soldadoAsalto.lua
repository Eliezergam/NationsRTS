-- El soldado de la batalla que avanza por la mejor ruta y dispara al enemigo
-- (batalla/robots/especializaciones/asalto.lua). Corre casi como un coche
-- (el dueño, 18-nov): 14 m/s (50 km/h), acelera y gira mucho más que el del
-- almacén.
return {
    base = 'soldado',
    ajustes = {
        conduccion = {
            velocidadSinCarga = 14,
            aceleracionSinCarga = 7,
            giroMaximo = 2.6,
            aceleracionGiro = 7,
            agacharDesde = 3,
            -- El freno ante lo que tiene delante mira la capa baja de su
            -- lidar (0,4 m): la de 0,25 del robot del almacén no la tiene, y
            -- sin ella nunca frenaba (27-nov).
            capaParachoques = 0.4,
        },
        -- Patina para coger velocidad y se desliza con los pies juntos
        -- cuando ya va (robots/especializaciones/piernasSoldado.lua).
        piernasSoldado = { patinador = true },
        -- Lidar (robots/especializaciones/lidar.lua) de 72 rayos (cada 5°,
        -- alternando medio paso) a la altura de la rueda y del pecho; a 14 m/s
        -- mira 25 m. Sin mapa.
        lidar = { rayos = 72, capas = { 0.4, 1.2 }, alcance = 25, limites = false, alternar = true },
    },
    'asalto',
    -- Sus sensores: lo que tiene alrededor, sin saber qué es.
    'lidar',
    -- Rodea lo sólido que ve el lidar y, si lo toca, choca (parachoques).
    'obstaculos',
    -- Brazos y garras con vida (respiran, se balancean, abren y cierran).
    'brazosVivos',
}

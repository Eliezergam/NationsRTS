-- El robot de ruedas con brazos del almacén: sus scripts, en este orden
-- cada cuadro (almacen/robots/especializaciones/). `patrulla` (la vuelta de
-- ejemplo) y `exploracion` (explorar la nave por fronteras antes de
-- trabajar) siguen ahí para quien los quiera.
return {
    ancho = 0.72, -- m de lado a lado (ruedas y brazos abajo)
    alto = 1.75,
    ajustes = {
        -- La postura (agacharse, ponerse recto) y el cabeceo los calcula la
        -- física (fisica.lua): la conducción ya no los pone.
        conduccion = { agacharse = 0, balanceo = 0 },
        lidar = {
            -- Toda la nave (con la fábrica: el robot pequeño lleva allí los
            -- recursos de los misiles), el anexo y el patio.
            limites = { -75.5, -15.5, 64.5, 32.5 },
        },
    },
    'conduccion',
    'fisica',
    'lidar',
    'navegacion',
    'mirada',
    'siglas',
    'sombra', -- sombra de contacto (en pausa: solo oculta la placa)
    'inercia',
    'manipulacion',
    'brazos',
    'pinzas',
    'reposo',
    'transporte',
    'almacenaje',
}

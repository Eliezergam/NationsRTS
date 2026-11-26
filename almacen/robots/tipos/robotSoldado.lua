-- El robot soldado (robots/tipos/soldado.lua) entrenando en el almacén antes
-- de ir a la batalla (el dueño, 18-nov: «lo vamos a entrenar en un lugar
-- aparte como en el almacén, paso a paso: primero que camine»; «que sea
-- igual que el robot pequeño, la forma en que analiza y lo procedural, para
-- que lo que agreguemos sean pocas cosas»).
--
-- Lo mismo que el soldado común y, además, todo lo del robot pequeño que no
-- es de llevar cosas, en el mismo orden: física (choques y postura), lidar,
-- navegación con el mapa que aprende, ojos y exploración por fronteras.
-- Cuando ha explorado, practica yendo a sitios de la nave
-- (practicaSoldado.lua).
return {
    base = 'soldado',
    ajustes = {
        lidar = {
            -- Toda la nave (con la fábrica: el robot pequeño lleva allí los
            -- recursos de los misiles), el anexo y el patio.
            limites = { -75.5, -15.5, 64.5, 32.5 },
        },
    },
    'fisica',
    'lidar',
    'navegacion',
    'mirada',
    'exploracion',
    'practicaSoldado',
    -- Dispara a los enemigos que ven sus ojos (bloques de práctica:
    -- almacen/blancos.lua).
    'combate',
    -- Órdenes y guiones desde los ordenadores de la sala (va el último).
    'guion',
    -- Lo que un guion de la sala sustituye (el resto es su cuerpo).
    trabajo = { 'exploracion', 'practicaSoldado', 'combate' },
}

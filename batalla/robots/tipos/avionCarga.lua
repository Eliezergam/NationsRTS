-- Avión de carga de los robots (el dueño, 20-nov): ala tipo B-2, motores
-- enterrados, cara de vidrio ahumado con una consola de código verde y
-- radares por dentro, y abertura trasera de pétalos y rampa para 4 camiones
-- de misiles y unos 24 robots (tools/blender/avion_carga*.py). Raíz: el
-- cuerpo, con las ruedas en el suelo.
return {
    modelo = 'assets/batalla/robots/avionCarga',
    ancho = 87.0,
    alto = 15.0,
    -- Se apoya en el terreno: largo y vía del tren de aterrizaje.
    inclinar = { 24.0, 11.2 },
    -- Copias de lejos a partir de 150 m y 400 m.
    lodDistancias = { 150, 400 },
    'avionCarga',
    -- Vuela solo: carreteo, despegue, circuito, aterrizaje y rampa.
    'vueloAvion',
    -- Pasajeros que suben y se sientan en filas (el dueño, 20-nov).
    'embarque',
}

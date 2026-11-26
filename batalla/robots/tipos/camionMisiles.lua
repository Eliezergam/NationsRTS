-- El camión de 4 misiles con robot conductor (el dueño, 18-nov), con la misma
-- lógica que los robots (robots/nucleo.lua): sin cabina, un robot soldado
-- sentado al aire agarrado a dos palancas y con los pies hechos engranajes
-- sobre el puesto que mueve el camión (tools/blender/camion_robot_puesto.py,
-- camion_robot_exportar.py). Raíz: el chasis, en el suelo.
return {
    modelo = 'assets/batalla/robots/camionMisiles',
    ancho = 3.74,
    alto = 4.0,
    -- Se apoya en el terreno: largo entre ejes extremos y vía.
    inclinar = { 8.0, 2.4 },
    'ruedasCamion',
    'rampaMisiles',
}

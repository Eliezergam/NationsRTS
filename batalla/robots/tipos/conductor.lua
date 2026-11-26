-- El robot conductor del camión de misiles (el dueño, 18-nov): el soldado sin
-- metralleta, con una garra en cada brazo agarrada a las palancas y las
-- ruedas de los pies hechas engranajes sobre el puesto
-- (tools/blender/robot_conductor.py). Va sentado (sentado.lua) y se le ve
-- vivo (vida.lua: oídos que giran y parpadeo).
return {
    modelo = 'assets/batalla/robots/conductor',
    ancho = 0.6,
    alto = 1.4,
    'sentado',
    'pilotar',
    'vigiaConductor',
    'vida',
}

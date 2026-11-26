"""El robot conductor del camión de misiles (el dueño, 18-nov): el soldado sin
metralleta, con una garra en cada brazo (robot_lanzamisiles.etapaGarra) y
las ruedas de los pies que se convierten en engranajes
(camion_robot_puesto.engranajePie) al sentarse en el puesto.

    blender -b --factory-startup --python tools/blender/robot_conductor.py

Exporta assets/batalla/robots/conductor.glb + conductor_piezas.lua en la pose
de reposo SENTADO (la de la maqueta: muslos -45°, espinillas +15°, garras
cerradas en las palancas), así el juego solo lo coloca en el asiento
(batalla/robots/especializaciones/sentado.lua). Piezas nuevas:
engranajePie{Der,Izq}, colgadas de la espinilla, en el centro de la rueda
(giran en su y, igual que la rueda).
"""

import math
import os

import bpy

_DIR = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(_DIR, '..', '..'))
_L = {'__name__': 'lanza', '__file__': os.path.join(_DIR, 'robot_lanzamisiles.py')}
with open(_L['__file__'], encoding='utf8') as archivo:
    exec(archivo.read(), _L)
_S = _L['_S']
bpy.app.driver_namespace['soldado'] = _S
_P = {'__name__': 'puesto', '__file__': os.path.join(_DIR, 'camion_robot_puesto.py')}
with open(_P['__file__'], encoding='utf8') as archivo:
    exec(archivo.read(), _P)

MUSLO = math.radians(-45)
ESPINILLA = math.radians(15)
DEDOS = (0.25, 0.9, 0.7)


def principal():
    _S['construir'](brazoDerecho=lambda: _L['etapaGarra'](-1), brazoIzquierdo=lambda: _L['etapaGarra'](1))
    O = bpy.data.objects
    for s in ('Der', 'Izq'):
        O['muslo' + s].rotation_euler.y = MUSLO
        O['espinilla' + s].rotation_euler.y = ESPINILLA
        for d in 'ABC':
            for i, v in enumerate(DEDOS):
                O['dedo%s%d%s' % (d, i + 1, s)].rotation_euler.y = v
    bpy.context.view_layer.update()
    m = _S['materiales']()
    for s, lado in (('Der', -1), ('Izq', 1)):
        c = O['rueda' + s].matrix_world.translation.copy()
        g = _S['pieza']('engranajePie' + s, _P['engranajePie']('engranajePie' + s, c, lado, m), c)
        bpy.context.view_layer.update()
        mundo = g.matrix_world.copy()
        g.parent = O['espinilla' + s]
        g.matrix_world = mundo
    # La pose ya está puesta: sin la de pie de exportarJuego (que además
    # busca la metralleta).
    _S['poseSoldado'] = lambda *a, **k: None
    _S['exportarJuego'](os.path.join(RAIZ, 'assets', 'batalla', 'robots', 'conductor.glb'))


if __name__ == '__main__' and bpy.app.background:
    principal()

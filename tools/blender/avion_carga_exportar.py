"""Avión de carga al juego, como un robot más (robots/nucleo.lua, tipo
`avionCarga`):

    blender -b ~/NationsRTS-assets/avion_carga/avion_carga.blend \\
        --python tools/blender/avion_carga_exportar.py

No guarda el .blend. Deja:
    assets/batalla/robots/avionCarga.glb + avionCarga_piezas.lua
    (+ _lod1/_lod2 con avionCarga_moviles.lua)
    assets/batalla/robots/avionCarga_hud.png, avionCarga_placa.png

Piezas (raíz `cuerpo`, el suelo en z = 0, x delante, y izquierda):
    cuerpo                todo lo fijo, unido
    puertaI, puertaD      pétalos: giran en z (0 cerrada, -90° / +90° abierta)
    rampa                 gira en y (0 cerrada, -26,55° apoyada en la pista)
    rueda<I/D><1-4><a/b>, ruedaProa<a-d>   giran en y
    pantallaCodigo        la pantalla verde de la cara (su textura, el HUD)
    placaCircuitos        el fondo de la cara (su textura, la placa)
    vidrioCabina          el vidrio ahumado
    luces<Color>, luzDestello, luzPosicionRoja, luzPosicionVerde   luces
"""

import os
import shutil

import bpy
from mathutils import Matrix

_DIR = os.path.expanduser('~/NationsRTS/tools/blender')
RAIZ = os.path.abspath(os.path.join(_DIR, '..', '..'))
SALIDA = os.path.join(RAIZ, 'assets', 'batalla', 'robots', 'avionCarga.glb')
O = bpy.data.objects

_S = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_S['__file__'], encoding='utf8') as _f:
    exec(_f.read(), _S)
_D = {'__name__': 'detalle'}
with open(os.path.join(_DIR, 'avion_carga_detalle.py'), encoding='utf8') as _f:
    exec(_f.read(), _D)

SUELTAS = ('pantallaCodigo', 'placaCircuitos', 'lucesVerde', 'lucesAmbar', 'lucesRoja', 'lucesAzul', 'lucesCian',
           'lucesMagenta', 'luzDestello', 'luzPosicionRoja', 'luzPosicionVerde')
GIRAN = ('puertaI', 'puertaD', 'rampa')


def enMalla(o):
    """Malla con modificadores aplicados, en coordenadas del mundo."""
    grafo = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(grafo))
    me.transform(o.matrix_world)
    return me


def unir(nombre, objetos, origen):
    """Un objeto nuevo `nombre` con todas las mallas de `objetos` (con sus
    materiales), con el origen en `origen` (mundo)."""
    import bmesh
    bm = bmesh.new()
    materiales = []
    for o in objetos:
        me = enMalla(o)
        base = len(materiales)
        for mat in me.materials:
            materiales.append(mat)
        for p in me.polygons:
            p.material_index += base
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(nombre)
    bm.transform(Matrix.Translation(-origen))
    bm.to_mesh(me)
    bm.free()
    # Una ranura por material distinto.
    unicos = []
    for mat in materiales:
        if mat not in unicos:
            unicos.append(mat)
    for mat in unicos:
        me.materials.append(mat)
    for p in me.polygons:
        p.material_index = unicos.index(materiales[p.material_index]) if materiales else 0
    nuevo = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(nuevo)
    nuevo.matrix_world = Matrix.Translation(origen)
    return nuevo


def principal():
    _D['poseCarga'](0, 0)
    bpy.context.view_layer.update()
    for n in [o.name for o in O['carga'].children_recursive] + ['carga']:
        if O.get(n):
            O.remove(O[n])
    visor = O['visor']
    visor.name = 'vidrioCabina'
    mallas = [o for o in O if o.type == 'MESH' and not o.hide_render]
    usadas = set()
    piezas = {}
    # Lo que se mueve: cada vacío (puertas, rampa, ruedas) con lo suyo.
    moviles = [O[n] for n in GIRAN] + [o for o in O if o.type == 'EMPTY' and o.name.startswith(('rueda', 'ventilador'))]
    for e in moviles:
        hijas = [o for o in e.children_recursive if o.type == 'MESH']
        piezas[e.name] = unir(e.name + '_n', hijas, e.matrix_world.to_translation())
        usadas.update(o.name for o in hijas)
    for n in SUELTAS + ('vidrioCabina',):
        if O.get(n):
            piezas[n] = unir(n + '_n', [O[n]], O[n].matrix_world.to_translation())
            usadas.add(n)
    fijas = [o for o in mallas if o.name not in usadas and o.name not in [p.name for p in piezas.values()] and not o.name.startswith('bodegaUtil')]
    cuerpo = unir('cuerpo_n', fijas, O['fuselaje'].matrix_world.to_translation() * 0)
    # Todo lo viejo fuera; las piezas nuevas con su nombre.
    nuevas = {cuerpo.name} | {p.name for p in piezas.values()}
    for o in list(O):
        if o.name not in nuevas:
            O.remove(o)
    cuerpo.name = 'cuerpo'
    for n, o in piezas.items():
        o.name = n
        mundo = o.matrix_world.copy()
        o.parent = cuerpo
        o.matrix_world = mundo
    print('PIEZAS', len(piezas) + 1, 'fijas unidas', len(fijas))
    # Texturas de la cara (el .glb va sin imágenes; el juego las carga).
    for nombre, destino in (('hud_codigo.png', 'avionCarga_hud.png'), ('placa_circuitos.png', 'avionCarga_placa.png')):
        shutil.copy(os.path.expanduser('~/NationsRTS-assets/avion_carga/' + nombre), os.path.join(os.path.dirname(SALIDA), destino))
    _S['exportarJuego'](SALIDA, raiz='cuerpo', conservarUv=('pantallaCodigo', 'placaCircuitos'))


principal()

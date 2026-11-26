# Maqueta (solo volúmenes) del soldado lanzamisiles de Nations RTS
# (el dueño, 18-nov: «que el robot no tenga manos, que vaya corriendo y,
# cuando ve un objetivo, lo marca y la cabeza se le convierte en un
# lanzamisiles, de forma procedural»).
#
# Idea: el soldado de siempre (robot_soldado.py) sin manos (los antebrazos
# acaban en una tapa blindada) y con una mochila de la que salen, de pie
# detrás de la cabeza, dos tubos lanzamisiles apuntando al cielo. Al ver un
# objetivo:
#   1. lo marca: un láser rojo desde el ojo;
#   2. el casco se abre en dos mitades, como dos puertas con la bisagra
#      detrás (los ojos van en ellas);
#   3. los tubos (guardados inclinados atrás, como un carcaj) giran 125°
#      desde la mochila hacia delante y pasan por el
#      hueco de la cabeza;
#   4. las mitades se cierran sobre los tubos: los ojos quedan a los lados,
#      de mira.
# Tubos: un misil antitanque portátil ronda 1,1 m y 12-13 cm (Javelin:
# 1,08 m, 127 mm); aquí 0,8 m y 0,13 m.
#
#     blender -b --factory-startup --python tools/blender/robot_cabeza_lanzador_maqueta.py -- <carpeta>
#
# Deja paso0..paso4.png (de tres cuartos) y lado0/lado4.png (de perfil).

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

_DIR = os.path.dirname(os.path.abspath(__file__))
_ns = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_ns['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _ns)

ARCILLA = (0.72, 0.68, 0.62)
TUBO_R = 0.065
TUBO_LARGO = 0.8
TUBO_Y = 0.072
PIVOTE = Vector((-0.3, 0.0, 1.66))  # bisagra de los tubos, en lo alto de la mochila
CASCO = ((-0.11, 0.135), 0.105, (1.6, 1.86))  # x, medio ancho, z de cada mitad
BISAGRA_X = -0.1
ABRIR = math.radians(75)
GUARDADO = math.radians(-35)  # en reposo, inclinados hacia atrás como un carcaj


def material(nombre, color, rugosidad=0.6, emision=None):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rugosidad
    if emision:
        p.inputs['Emission Color'].default_value = (*emision, 1)
        p.inputs['Emission Strength'].default_value = 8
    return m


def borrarConHijos(nombre):
    o = bpy.data.objects.get(nombre)
    if not o:
        return
    for h in list(o.children_recursive):
        bpy.data.objects.remove(h, do_unlink=True)
    bpy.data.objects.remove(o, do_unlink=True)


def vacio(nombre, lugar, padre=None):
    o = bpy.data.objects.new(nombre, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = lugar
    if padre:
        o.parent = padre
        o.matrix_parent_inverse = padre.matrix_world.inverted()
    return o


def colgar(o, padre):
    mundo = o.matrix_world.copy()
    o.parent = padre
    o.matrix_world = mundo


def tubo(nombre, a, b, r, mat, padre=None, lados=48):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=lados, radius=r, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.name = nombre
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if padre:
        colgar(o, padre)
    return o


def bloque(nombre, centro, medida, mat, padre=None, bisel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centro)
    o = bpy.context.active_object
    o.name = nombre
    o.scale = medida
    bpy.ops.object.transform_apply(scale=True)
    o.modifiers.new('bisel', 'BEVEL').width = bisel
    o.data.materials.append(mat)
    if padre:
        colgar(o, padre)
    return o


def bola(nombre, centro, r, mat, padre=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=centro, segments=48, ring_count=24)
    o = bpy.context.active_object
    o.name = nombre
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if padre:
        colgar(o, padre)
    return o


def montar(mats):
    """Sobre el soldado ya construido: sin manos, mochila con los tubos y la
    cabeza partida en dos mitades (maqueta)."""
    O = bpy.data.objects
    torso = O['torso']
    # Sin manos: fuera la metralleta y la garra; antebrazos con tapa.
    borrarConHijos('metralleta')
    borrarConHijos('codoIzq')
    y = _ns['PECHO'][1] / 2 + 0.065
    for lado, nombre in ((1, 'hombroIzq'), (-1, 'hombroDer')):
        x0, z = _ns['CODO_IZQ']
        tubo('antebrazo', (x0, lado * y, z), (x0 + 0.24, lado * y, z), 0.058, mats['arcilla'], O[nombre])
        bola('tapaAntebrazo', (x0 + 0.24, lado * y, z), 0.058, mats['arcilla'], O[nombre])
    # Mochila (cargador) a la espalda.
    bloque('mochila', (-0.3, 0, 1.38), (0.2, 0.3, 0.42), mats['arcilla'], torso, 0.03)
    # Tubos: cuelgan de la bisagra; de pie (apuntando arriba) en reposo.
    bisagra = vacio('bisagraTubos', PIVOTE, torso)
    bloque('soporteBisagra', PIVOTE + Vector((0, 0, -0.02)), (0.08, 0.26, 0.06), mats['arcilla'], torso, 0.01)
    for s in (-1, 1):
        a = PIVOTE + Vector((0, s * TUBO_Y, 0))
        b = a + Vector((0, 0, TUBO_LARGO))
        tubo('tubo', a, b, TUBO_R, mats['arcilla'], bisagra)
        tubo('boca', b, b + Vector((0, 0, 0.01)), TUBO_R * 0.8, mats['hueco'], bisagra)
        tubo('punta', b - Vector((0, 0, 0.05)), b + Vector((0, 0, 0.004)), TUBO_R * 0.5, mats['punta'], bisagra, 24)
    bloque('abrazaderaTubos', PIVOTE + Vector((0, 0, 0.35)), (0.16, 0.3, 0.05), mats['arcilla'], bisagra, 0.01)
    # Cabeza: la de verdad fuera; dos mitades de casco con un ojo cada una.
    cabeza = O['cabeza']
    for h in list(cabeza.children_recursive):
        h.hide_render = True
    cabeza.hide_render = True
    (x0, x1), my, (z0, z1) = CASCO
    for s, nombre in ((1, 'Izq'), (-1, 'Der')):
        bisagraCasco = vacio('bisagraCasco' + nombre, (BISAGRA_X, s * my, (z0 + z1) / 2), cabeza)
        bloque('casco' + nombre, ((x0 + x1) / 2, s * my / 2, (z0 + z1) / 2), (x1 - x0, my, z1 - z0), mats['arcilla'], bisagraCasco, 0.035)
        ojo = bola('ojo' + nombre, (x1 - 0.005, s * 0.052, 1.752), 0.03, mats['ojo'], bisagraCasco)
        if s > 0:
            # El láser de marcar sale de este ojo.
            laser = tubo('laser', (x1 + 0.02, s * 0.052, 1.752), (x1 + 6, s * 0.052, 1.6), 0.004, mats['laser'], bisagraCasco, 12)
            laser.hide_render = True
    bloque('mandibula', (0.04, 0, 1.56), (0.12, 0.13, 0.08), mats['arcilla'], cabeza, 0.02)


def pose(paso):
    """0 reposo · 1 marca · 2 casco abierto · 3 tubos bajados · 4 cerrado."""
    O = bpy.data.objects
    abrir = {0: 0, 1: 0, 2: 1, 3: 1, 4: 0.3}[paso]
    bajar = {0: 0, 1: 0, 2: 0.35, 3: 1, 4: 1}[paso]
    O['laser'].hide_render = paso not in (1, 4)
    for s, nombre in ((1, 'Izq'), (-1, 'Der')):
        O['bisagraCasco' + nombre].rotation_euler.z = s * ABRIR * abrir
    # Bajar: de apuntar arriba a apuntar al frente (giro en y de 90°).
    O['bisagraTubos'].rotation_euler.y = GUARDADO + (math.radians(90) - GUARDADO) * bajar
    bpy.context.view_layer.update()


def persona(mats):
    y = -1.35
    tubo('personaPiernas', (0, y, 0), (0, y, 0.9), 0.13, mats['persona'])
    tubo('personaTorso', (0, y, 0.9), (0, y, 1.5), 0.19, mats['persona'])
    bola('personaCabeza', (0, y, 1.68), 0.12, mats['persona'])


def escenario():
    s = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            s.render.engine = motor
            break
        except TypeError:
            pass
    s.render.resolution_x, s.render.resolution_y = 900, 900
    s.view_settings.view_transform = 'Standard'
    mundo = bpy.data.worlds.new('fondo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.55, 0.6, 0.66, 1)
    fondo.inputs['Strength'].default_value = 0.8
    s.world = mundo
    bpy.ops.mesh.primitive_plane_add(size=20)
    bpy.context.active_object.data.materials.append(material('sueloMaqueta', (0.36, 0.37, 0.35), 0.9))
    bpy.ops.object.light_add(type='SUN', location=(3, 2, 6))
    sol = bpy.context.active_object
    sol.data.energy = 3.5
    sol.rotation_euler = (math.radians(40), math.radians(20), math.radians(130))
    bpy.ops.object.camera_add()
    camara = bpy.context.active_object
    camara.data.lens = 50
    s.camera = camara
    return camara


def foto(camara, desde, hacia, ruta):
    camara.location = desde
    camara.rotation_euler = (Vector(hacia) - Vector(desde)).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = ruta
    bpy.ops.render.render(write_still=True)


def principal():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    carpeta = args[0] if args else '/tmp'
    _ns['construir']()
    mats = {
        'arcilla': material('arcilla', ARCILLA),
        'hueco': material('hueco', (0.03, 0.03, 0.03), 0.8),
        'punta': material('puntaMisil', (0.6, 0.06, 0.04), 0.4),
        'ojo': material('ojoMaqueta', (0.05, 0.3, 0.35), 0.3, (0.1, 0.9, 1.0)),
        'laser': material('laserMaqueta', (1, 0.05, 0.03), 0.3, (1, 0.05, 0.02)),
        'persona': material('persona', (0.45, 0.47, 0.5), 0.7),
    }
    bpy.context.view_layer.update()
    montar(mats)
    persona(mats)
    camara = escenario()
    for paso in range(5):
        pose(paso)
        foto(camara, (3.1, 2.5, 2.1), (-0.05, -0.1, 1.2), os.path.join(carpeta, 'paso%d.png' % paso))
        if paso in (0, 4):
            foto(camara, (0.0, 4.4, 1.4), (-0.1, 0.0, 1.15), os.path.join(carpeta, 'lado%d.png' % paso))


if bpy.app.background:
    principal()

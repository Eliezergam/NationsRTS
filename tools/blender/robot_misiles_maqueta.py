# Maqueta (solo volúmenes) del soldado lanzamisiles de Nations RTS
# (el dueño, 18-nov: «otro robot igual, pero en vez de metralleta dispara
# misiles antitanque que puedan darle a otros robots; la mano que no lleva
# arma no les sirve: busca cómo se vería el lanzamisiles»). Tres propuestas
# sobre el soldado de verdad (robot_soldado.py), lo nuevo en gris arcilla:
#
#   A  brazo lanzador: el antebrazo izquierdo (donde iba la garra) es un
#      lanzador de dos tubos.
#   B  mochila: un cargador de misiles a la espalda y una cápsula de cuatro
#      tubos que sube por encima del hombro izquierdo; el antebrazo izquierdo,
#      un designador láser corto.
#   C  cañón en la cara: la máscara se abre en dos y por el centro sale un
#      tubo lanzador; los misiles vienen de la mochila por detrás de la
#      cabeza. (Idea de un cañón en la cara; el diseño es propio.)
#
# Medidas de los tubos: un misil antitanque portátil ronda 1,1 m y 12-13 cm de
# diámetro (Javelin: 1,08 m, 127 mm); aquí, tubos de 0,14 m.
#
#     blender -b --factory-startup --python tools/blender/robot_misiles_maqueta.py -- <carpeta>
#
# Deja maqueta_A.png, maqueta_B.png y maqueta_C.png (3/4 delante) y
# maqueta_*_lado.png (de perfil) en <carpeta>.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

_DIR = os.path.dirname(os.path.abspath(__file__))
_ns = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_ns['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _ns)

TUBO_R = 0.07
ARCILLA = (0.72, 0.68, 0.62)


def material(nombre, color, rugosidad=0.6, emision=None):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rugosidad
    if emision:
        p.inputs['Emission Color'].default_value = (*emision, 1)
        p.inputs['Emission Strength'].default_value = 6
    return m


def borrarConHijos(nombre):
    o = bpy.data.objects.get(nombre)
    if not o:
        return
    for h in list(o.children_recursive):
        bpy.data.objects.remove(h, do_unlink=True)
    bpy.data.objects.remove(o, do_unlink=True)


def tubo(nombre, a, b, r, mat, padre=None, lados=48):
    """Cilindro de a a b (mundo)."""
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
        mundo = o.matrix_world.copy()
        o.parent = padre
        o.matrix_world = mundo
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
        mundo = o.matrix_world.copy()
        o.parent = padre
        o.matrix_world = mundo
    return o


def lanzaTubos(prefijo, centro, largo, filas, columnas, paso, mats, padre):
    """Grupo de tubos a lo largo de x con su marco, centrado en `centro`."""
    cx, cy, cz = centro
    ancho = columnas * paso
    alto = filas * paso
    bloque(prefijo + 'Marco', (cx, cy, cz), (largo * 0.9, ancho + 0.03, alto + 0.03), mats['arcilla'], padre, 0.02)
    for f in range(filas):
        for c in range(columnas):
            y = cy - ancho / 2 + paso * (c + 0.5)
            z = cz - alto / 2 + paso * (f + 0.5)
            tubo(prefijo + 'Tubo', (cx - largo / 2, y, z), (cx + largo / 2 + 0.01, y, z), TUBO_R * 0.95, mats['arcilla'], padre)
            # Boca: la tapa oscura y la punta roja del misil dentro.
            tubo(prefijo + 'Boca', (cx + largo / 2 + 0.005, y, z), (cx + largo / 2 + 0.015, y, z), TUBO_R * 0.8, mats['hueco'], padre)
            tubo(prefijo + 'Punta', (cx + largo / 2 - 0.04, y, z), (cx + largo / 2 + 0.004, y, z), TUBO_R * 0.5, mats['punta'], padre, 24)


def antebrazoCorto(mats, designador=True):
    """Antebrazo izquierdo sin garra: muñón con un designador láser."""
    torso = bpy.data.objects['torso']
    brazo = bpy.data.objects['hombroIzq']
    y = _ns['PECHO'][1] / 2 + 0.065
    x0, z = _ns['CODO_IZQ']
    tubo('antebrazoMaqueta', (x0, y, z), (x0 + 0.26, y, z), 0.06, mats['arcilla'], brazo)
    if designador:
        bloque('designador', (x0 + 0.2, y, z + 0.07), (0.16, 0.06, 0.05), mats['arcilla'], brazo, 0.01)
        tubo('lenteDesignador', (x0 + 0.28, y, z + 0.07), (x0 + 0.29, y, z + 0.07), 0.018, mats['laser'], brazo, 24)
    return torso


def propuestaA(mats):
    """Antebrazo izquierdo = lanzador de dos tubos (uno sobre otro), con la
    mira encima; el codo del soldado de siempre."""
    borrarConHijos('codoIzq')
    brazo = bpy.data.objects['hombroIzq']
    y = _ns['PECHO'][1] / 2 + 0.065
    x0, z = _ns['CODO_IZQ']
    # El tubo va del codo hacia delante, algo más corto por detrás.
    lanzaTubos('lanzaA', (x0 + 0.24, y + 0.02, z + 0.02), 0.95, 2, 1, 0.15, mats, brazo)
    bloque('miraA', (x0 + 0.3, y + 0.02, z + 0.2), (0.18, 0.05, 0.06), mats['arcilla'], brazo, 0.01)
    tubo('lenteMiraA', (x0 + 0.39, y + 0.02, z + 0.2), (x0 + 0.4, y + 0.02, z + 0.2), 0.02, mats['laser'], brazo, 24)


def propuestaB(mats):
    """Mochila cargador a la espalda y cápsula de 2x2 tubos que sube por
    encima del hombro izquierdo apuntando al frente."""
    borrarConHijos('codoIzq')
    torso = antebrazoCorto(mats)
    zt = _ns['CINTURA_Z']
    bloque('mochilaB', (-0.27, 0, zt + 0.3), (0.22, 0.36, 0.44), mats['arcilla'], torso, 0.03)
    # Brazo de la cápsula: de la mochila sube por detrás del hombro izquierdo.
    # (Al lado de la cabeza, sobre el hombro: el soporte sale de lo alto de
    # la mochila y la sujeta por debajo.)
    bloque('soporteB', (-0.24, 0.3, zt + 0.55), (0.1, 0.1, 0.12), mats['arcilla'], torso, 0.02)
    tubo('pilarB', (-0.24, 0.3, zt + 0.5), (-0.1, 0.36, zt + 0.66), 0.045, mats['arcilla'], torso)
    lanzaTubos('capsulaB', (0.02, 0.4, zt + 0.73), 0.8, 2, 2, 0.15, mats, torso)


def propuestaC(mats):
    """La máscara se abre en dos y del centro de la cara sale un tubo; los
    misiles vienen de la mochila por detrás de la cabeza."""
    borrarConHijos('codoIzq')
    torso = antebrazoCorto(mats)
    cabeza = bpy.data.objects['cabeza']
    zt = _ns['CINTURA_Z']
    bpy.context.view_layer.update()
    # Centro de la cara: del cuadro que ocupa la cabeza.
    puntos = [o.matrix_world @ Vector(c) for o in [cabeza] + list(cabeza.children_recursive) if o.type == 'MESH' for c in o.bound_box]
    xf = max(p.x for p in puntos)
    zc = (min(p.z for p in puntos) + max(p.z for p in puntos)) / 2
    zb = zc - 0.03
    # Las dos mitades de la máscara, abiertas a los lados (sobre la cara).
    for s in (-1, 1):
        o = bloque('mascaraAbiertaC', (xf - 0.02, s * 0.1, zb), (0.04, 0.05, 0.12), mats['arcilla'], cabeza, 0.01)
        o.rotation_euler.z = s * 0.6
    tubo('canonCaraC', (xf - 0.3, 0, zb), (xf + 0.38, 0, zb), TUBO_R, mats['arcilla'], cabeza)
    tubo('bocaCaraC', (xf + 0.38, 0, zb), (xf + 0.39, 0, zb), TUBO_R * 0.8, mats['hueco'], cabeza)
    tubo('puntaCaraC', (xf + 0.34, 0, zb), (xf + 0.385, 0, zb), TUBO_R * 0.5, mats['punta'], cabeza, 24)
    tubo('anilloCaraC', (xf + 0.02, 0, zb), (xf + 0.06, 0, zb), TUBO_R + 0.025, mats['arcilla'], cabeza)
    # Mochila con el cargador y el conducto que sube detrás del cuello.
    bloque('mochilaC', (-0.27, 0, zt + 0.28), (0.22, 0.34, 0.42), mats['arcilla'], torso, 0.03)
    tubo('conductoC', (-0.3, 0, zt + 0.48), (xf - 0.3, 0, zb), 0.06, mats['arcilla'], torso)


def persona(mats):
    """Referencia de 1,80 m (a la derecha del robot)."""
    y = -1.35
    tubo('personaPiernas', (0, y, 0), (0, y, 0.9), 0.13, mats['persona'])
    tubo('personaTorso', (0, y, 0.9), (0, y, 1.5), 0.19, mats['persona'])
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, y, 1.68))
    bpy.context.active_object.data.materials.append(mats['persona'])
    bpy.context.active_object.name = 'personaCabeza'


def escenario():
    s = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            s.render.engine = motor
            break
        except TypeError:
            pass
    s.render.resolution_x, s.render.resolution_y = 1100, 1100
    s.view_settings.view_transform = 'Standard'
    mundo = bpy.data.worlds.new('fondo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.55, 0.6, 0.66, 1)
    fondo.inputs['Strength'].default_value = 0.9
    s.world = mundo
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
    suelo = bpy.context.active_object
    suelo.data.materials.append(material('sueloMaqueta', (0.36, 0.37, 0.35), 0.9))
    bpy.ops.object.light_add(type='SUN', location=(3, 2, 6))
    sol = bpy.context.active_object
    sol.data.energy = 4
    sol.rotation_euler = (math.radians(40), math.radians(20), math.radians(130))
    bpy.ops.object.camera_add()
    camara = bpy.context.active_object
    camara.data.lens = 50
    s.camera = camara
    return camara


def fotografiar(camara, desde, hacia, ruta):
    camara.location = desde
    d = Vector(hacia) - Vector(desde)
    camara.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = ruta
    bpy.ops.render.render(write_still=True)


def principal():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    carpeta = args[0] if args else '/tmp'
    for nombre, hacer in (('A', propuestaA), ('B', propuestaB), ('C', propuestaC)):
        _ns['construir']()
        mats = {
            'arcilla': material('arcilla', ARCILLA),
            'hueco': material('hueco', (0.03, 0.03, 0.03), 0.8),
            'punta': material('puntaMisil', (0.6, 0.06, 0.04), 0.4),
            'laser': material('laser', (0.1, 0.02, 0.02), 0.3, (1, 0.1, 0.05)),
            'persona': material('persona', (0.45, 0.47, 0.5), 0.7),
        }
        bpy.context.view_layer.update()
        hacer(mats)
        persona(mats)
        camara = escenario()
        fotografiar(camara, (3.0, 2.2, 1.7), (0.1, 0.0, 1.0), os.path.join(carpeta, 'maqueta_%s.png' % nombre))
        fotografiar(camara, (0.2, 4.2, 1.2), (0.1, 0.0, 1.0), os.path.join(carpeta, 'maqueta_%s_lado.png' % nombre))


if bpy.app.background:
    principal()

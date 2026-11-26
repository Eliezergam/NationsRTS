# Mano izquierda del robot soldado: garra de tres dedos (el dueño,
# 2026-11-17, referencia ~/NationsRTS-assets/robots/referencias/
# mano_garra_3_dedos_robotiq.jpg, una pinza de tres dedos tipo Robotiq 3F).
# De la foto solo se toma la forma: base redondeada con la tapa atornillada
# arriba, dos dedos a un lado y uno enfrente, cada uno de tres falanges
# anchas con bisagras de placas a los lados y la punta de aluminio. El
# acabado es el de la casa (skill vehiculo-detallado y robots del almacén):
# negro mate biselado, articulaciones oscuras, tornillos de acero, puntas
# de aluminio. Sin marcas.
#
# Sin ventana:
#
#     blender -b --factory-startup --python tools/blender/robot_soldado_mano.py -- \
#         <salida.blend> [carpeta de renders] [--cerrada]
#
# Metros. La muñeca en el origen, los dedos hacia +z. Los dedos A y B van a
# -x y el C (enfrente) a +x; todos cierran hacia el centro. Cada falange es
# un objeto con el origen en su eje, cuelga de la anterior y cierra girando
# en su y: mano -> dedoA1 -> dedoA2 -> dedoA3 (igual B y C).

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# Utilidades de los robots del almacén (misma familia).
_RUTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'robot_almacen.py')
with open(_RUTA, encoding='utf8') as _archivo:
    _fuente = _archivo.read()
exec(_fuente[_fuente.index('def argumentos():'):_fuente.index('# El robot ---')])
exec(_fuente[_fuente.index('def prepararRender():'):_fuente.index('def renderizar(carpeta):')])

# Medidas (m).
BASE_Z = 0.1  # alto de la base (los dedos salen de arriba)
DEDO_X = 0.04  # |x| de las filas de dedos
DEDO_Y = 0.03  # |y| de los dedos A y B
DEDO = (0.022, 0.042)  # fondo (grueso de la placa) y ancho de la falange
FALANGES = (0.052, 0.042, 0.034)
ARTICULACION = 0.0085  # radio de los cilindros de las articulaciones


def articulacion(nombre, centro, ancho, m):
    """Cilindro oscuro a lo ancho (y) con una tapa plateada a cada lado."""
    p = [cilindro(nombre, centro, ARTICULACION, ancho, m['articulacion'], eje='y', bisel=0.0015)]
    for s in (-1, 1):
        c = (centro[0], centro[1] + s * (ancho / 2 + 0.0008), centro[2])
        p.append(cilindro(nombre + 'Tapa', c, ARTICULACION * 0.5, 0.0016, m['acero'], lados=24, eje='y', bisel=0.0004))
    return p


def tornillo(nombre, centro, normal, m, radio=0.0022):
    """Tornillo de cabeza de botón con arandela (a la escala de la mano)."""
    n = Vector(normal).normalized()
    giro = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    p = [
        cilindro(nombre + 'Arandela', (0, 0, 0.0004), radio * 1.4, 0.0008, m['acero'], lados=24),
        esfera(nombre, (0, 0, 0.0008), radio, m['acero'], (1, 1, 0.45)),
    ]
    for o in p:
        o.data.transform(Matrix.Translation(Vector(centro)) @ giro)
    return p


def falange(nombre, largo, m, ultima=False):
    """Falange de `largo` sobre su eje en el origen, hacia +z; su cara de
    agarre mira a +x. Placa negra ancha, una placa de bisagra a cada lado
    que tapa la articulación (como en la referencia), tornillos en las
    bisagras y, en la última, la punta de aluminio con el chaflán hacia
    dentro."""
    f, w = DEDO
    p = []
    if ultima:
        cuerpo = largo * 0.45
        p.append(caja(nombre, (0, 0, cuerpo / 2 + 0.003), (f, w * 0.9, cuerpo), m['negro'], bisel=0.004))
        # Punta de aluminio: más ancha, con el chaflán en la cara de agarre.
        bm = bmesh.new()
        alto = largo - cuerpo
        z0 = cuerpo
        perfil = [(-f / 2 - 0.002, z0), (f / 2 + 0.003, z0), (f / 2 + 0.003, z0 + alto * 0.55), (f / 2 - 0.006, z0 + alto), (-f / 2 - 0.002, z0 + alto)]
        for y in (-w / 2 - 0.001, w / 2 + 0.001):
            for x, z in perfil:
                bm.verts.new((x, y, z))
        bm.verts.ensure_lookup_table()
        n = len(perfil)
        bm.faces.new([bm.verts[k] for k in range(n)][::-1])
        bm.faces.new([bm.verts[n + k] for k in range(n)])
        for k in range(n):
            a, b = k, (k + 1) % n
            bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[n + b], bm.verts[n + a]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.0018, segments=3, affect='EDGES', profile=0.5)
        p.append(objetoDe(nombre + 'Punta', bm, m['plata']))
    else:
        p.append(caja(nombre, (0, 0, largo / 2 + 0.002), (f, w * 0.9, largo - 0.006), m['negro'], bisel=0.004))
        # Nervio del dorso.
        p.append(caja(nombre + 'Nervio', (-f / 2 - 0.0015, 0, largo / 2), (0.003, w * 0.42, largo * 0.62), m['negro'], bisel=0.0012))
    # Placas de bisagra a los lados, sobre el eje de abajo, con su tornillo.
    for s in (-1, 1):
        p.append(caja(nombre + 'Bisagra', (0, s * (w / 2 + 0.0018), 0.006), (f + 0.004, 0.0034, 0.024), m['negro'], bisel=0.0012))
        p += tornillo(nombre + 'Tornillo', (0.0, s * (w / 2 + 0.0036), 0.0), (0, s, 0), m, 0.0019)
        p += tornillo(nombre + 'Tornillo', (0.0, s * (w / 2 + 0.0036), 0.012), (0, s, 0), m, 0.0016)
    p += articulacion(nombre + 'Eje', (0, 0, 0), w * 0.8, m)
    return p


def cadena(prefijo, base, giroBase, largos, m, padre, curvas):
    """Falanges encadenadas desde `base` con la orientación `giroBase`
    (matriz 3x3: su z hacia la punta, su x hacia la cara de agarre). Cada
    una cuelga de la anterior con el origen en su eje y cierra girando
    `curvas[k]` en su y (positivo: hacia la cara de agarre)."""
    padreF = padre
    base = Vector(base)
    giro = giroBase.copy()
    for k, largo in enumerate(largos):
        o = unir(falange(prefijo + str(k + 1), largo, m, ultima=k == len(largos) - 1), prefijo + str(k + 1))
        o.data.name = o.name
        giro = giro @ Matrix.Rotation(curvas[k], 3, 'Y')
        o.matrix_world = Matrix.Translation(base) @ giro.to_4x4()
        bpy.context.view_layer.update()
        mundo = o.matrix_world.copy()
        o.parent = padreF
        o.matrix_world = mundo
        base = base + giro @ Vector((0, 0, largo))
        padreF = o
    return padreF


def base(m):
    p = []
    # Brida de la muñeca, abajo.
    p.append(cilindro('brida', (0, 0, 0.006), 0.026, 0.012, m['articulacion'], bisel=0.002))
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        p += tornillo('tornilloBrida', (math.cos(a) * 0.02, math.sin(a) * 0.02, 0.012), (0, 0, 1), m, 0.0018)
    # Cuerpo: abajo redondeado (como un cuenco) y arriba en caja biselada.
    p.append(esfera('cuerpoBajo', (0, 0, 0.05), 0.056, m['negro'], (1.0, 1.05, 0.8)))
    p.append(caja('cuerpoAlto', (0, 0, 0.075), (0.108, 0.118, 0.05), m['negro'], bisel=0.016))
    # Tapa de arriba en cruz, con su canto y cinco tornillos.
    p.append(caja('tapaX', (0, 0, BASE_Z + 0.002), (0.066, 0.034, 0.005), m['articulacion'], bisel=0.0015))
    p.append(caja('tapaY', (0, 0, BASE_Z + 0.002), (0.034, 0.084, 0.005), m['articulacion'], bisel=0.0015))
    for x, y in ((0, 0), (0.026, 0), (-0.026, 0), (0, 0.034), (0, -0.034)):
        p += tornillo('tornilloTapa', (x, y, BASE_Z + 0.0045), (0, 0, 1), m, 0.0018)
    # Soportes de los dedos: orejas a cada lado del eje de la primera falange.
    for x, y in ((-DEDO_X, -DEDO_Y), (-DEDO_X, DEDO_Y), (DEDO_X, 0.0)):
        for s in (-1, 1):
            p.append(caja('soporte', (x, y + s * (DEDO[1] / 2 + 0.006), BASE_Z - 0.004), (0.026, 0.006, 0.026), m['negro'], bisel=0.002))
    # Dos conectores redondos delante (+y), sin marcas.
    for x in (-0.018, 0.018):
        p.append(cilindro('conector', (x, -0.057, 0.04), 0.0065, 0.012, m['acero'], eje='y', lados=32, bisel=0.001))
        p.append(cilindro('conectorBoca', (x, -0.0635, 0.04), 0.0045, 0.002, m['negroMate'], eje='y', lados=32))
    return p


def crearMano(pose='abierta'):
    m = crearMateriales()
    mano = pieza('mano', base(m), (0, 0, 0))
    if pose == 'cerrada':
        # Las puntas se juntan en el centro sin cruzarse: con la primera
        # falange recta, 0,042·sen(0,33) + 0,034·sen(0,6) = 0,033 de los
        # 0,04 que hay de cada fila de dedos al centro.
        curvas = (0.0, 0.33, 0.27)
    else:
        # Abierta como en la referencia: la primera falange hacia fuera y
        # las otras volviendo hacia dentro.
        curvas = (-0.45, 0.42, 0.18)
    z = BASE_Z - 0.004
    # A y B a -x con la cara de agarre hacia +x; C a +x mirando a -x.
    cadena('dedoA', (-DEDO_X, -DEDO_Y, z), Matrix.Identity(3), FALANGES, m, mano, curvas)
    cadena('dedoB', (-DEDO_X, DEDO_Y, z), Matrix.Identity(3), FALANGES, m, mano, curvas)
    cadena('dedoC', (DEDO_X, 0.0, z), Matrix.Rotation(math.pi, 3, 'Z'), FALANGES, m, mano, curvas)
    materialesReales(m)
    return mano


def renderizarMano(carpeta, mano, pose):
    escena = bpy.context.scene
    # Renders de revisión: rápidos (32 muestras con eliminación de ruido).
    escena.cycles.samples = 32
    escena.render.resolution_x, escena.render.resolution_y = 800, 800
    c = Vector((0.0, 0, 0.12))
    vistas = [
        ('frente', (0.3, -0.5, 0.26), c, 50),
        ('lado', (0.0, -0.6, 0.15), c, 50),
        ('atras', (-0.45, 0.3, 0.3), c, 50),
        ('dedos_cerca', (0.12, -0.22, 0.24), Vector((0.0, 0.0, 0.17)), 60),
    ]
    for nombre, posicion, objetivo, lente in vistas:
        datos = bpy.data.cameras.new(nombre)
        datos.lens = lente
        cam = bpy.data.objects.new(nombre, datos)
        cam.location = posicion
        cam.rotation_euler = (Vector(objetivo) - Vector(posicion)).to_track_quat('-Z', 'Y').to_euler()
        escena.collection.objects.link(cam)
        escena.camera = cam
        escena.render.filepath = os.path.join(carpeta, 'mano_' + pose + '_' + nombre + '.png')
        bpy.ops.render.render(write_still=True)


def principal():
    args = argumentos()
    salida = args[0] if args else '/tmp/robot_soldado_mano.blend'
    pose = 'cerrada' if '--cerrada' in args else 'abierta'
    args = [a for a in args if a != '--cerrada']
    limpiarEscena()
    mano = crearMano(pose)
    prepararRender()
    # A la escala de la mano: el suelo y las luces del robot entero quedan
    # lejos; se acercan las luces.
    for o in bpy.data.objects:
        if o.type == 'LIGHT':
            o.location = Vector(o.location) * 0.25 + Vector((0, 0, 0.1))
            o.data.energy *= 0.08
            o.data.size *= 0.3
            o.rotation_euler = (Vector((0, 0, 0.1)) - o.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.wm.save_as_mainfile(filepath=salida)
    if len(args) > 1:
        renderizarMano(args[1], mano, pose)
    print('MANO lista', pose)


principal()

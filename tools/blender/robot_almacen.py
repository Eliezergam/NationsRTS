# Robot del almacén: base con dos ruedas grandes, una pierna de dos tramos
# (rodilla) que sube del chasis, torso con dos brazos y pinzas, y cabeza
# plana con cámaras. Se corre sin ventana:
#
#     blender -b --factory-startup --python tools/blender/robot_almacen.py -- \
#         <salida.blend> [carpeta de renders]
#
# Al juego (assets/almacen/robot.glb y robot_piezas.lua):
#
#     blender -b --factory-startup --python tools/blender/robot_almacen.py -- --glb
#
# Referencia: la foto que pasó el dueño el 2026-11-16 (robot semihumanoide
# sobre base de ruedas, en blanco, plata y negro) y los robots reales de ese
# tipo (Galbot G1: base diferencial con pierna plegable y dos brazos).
#
# Medidas en metros, z arriba, el frente hacia +x, el origen en el suelo bajo
# el centro de la base. Alto: 1,68 m.
#
# Cada pieza que se mueve es un objeto con su origen en el eje de giro y
# cuelga de la anterior (como las piezas del lanzamisiles). Con giro 0 está
# en la pose de la foto:
#   robot (base)
#     ruedaIzq, ruedaDer             giran en y
#     espinilla                      gira en y (cadera, sobre la base)
#       muslo                        gira en y (rodilla)
#         torso                      gira en z (cintura)
#           cuello                   gira en z (mirar a los lados)
#             cabeza                 gira en y (mirar arriba y abajo)
#               ojoIzq/Der           el globo: gira hacia donde miran los ojos
#                 anilloIzq/Der      aro dentado con luces: gira en x (por código)
#                 diafragmaIzq/Der   diafragma de 8 hojas: gira en x al revés
#               parpadoIzq/Der       oculto; se enseña al parpadear
#           hombroIzq/Der            giran en y (adelante y atrás)
#             brazoIzq/Der           gira en x (abrir el brazo)
#               codoIzq/Der          gira en y
#                 muniecaIzq/Der     gira en x (su x es el eje del antebrazo)
#                   dedo{Izq,Der}{A,B,C}  giran en z (cerrar la mano)
#                     punta{Izq,Der}{A,B,C}  giran en z lo contrario (punta paralela)
#                   agarreIzq/Der    punto vacío entre las yemas

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

RADIO_RUEDA = 0.19
ANCHO_RUEDA = 0.085
BASE = (0.62, 0.42, 0.2)  # largo, ancho, alto del chasis
Z_BASE = 0.07  # hueco bajo el chasis
# Articulaciones en la pose de la foto: (x, z).
CADERA = (0.06, 0.31)
RODILLA = (-0.12, 0.64)
CINTURA = (0.0, 0.99)
HOMBRO_Z = 1.37
HOMBRO_Y = 0.235
CODO = (0.02, 1.11)
MUNIECA = (0.25, 1.02)


def argumentos():
    if '--' in sys.argv:
        return sys.argv[sys.argv.index('--') + 1:]
    return []


def limpiarEscena():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def nodoPrincipled(material):
    return next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def materialLiso(nombre, color, rugosidad, metalico=0.0, emision=0.0):
    material = bpy.data.materials.new(nombre)
    material.use_nodes = True
    bsdf = nodoPrincipled(material)
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rugosidad
    bsdf.inputs['Metallic'].default_value = metalico
    if emision > 0:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emision
    return material


def crearMateriales():
    return {
        'blanco': materialLiso('robotBlanco', (0.8, 0.81, 0.83), 0.32, 0.05),
        'plata': materialLiso('robotPlata', (0.62, 0.64, 0.67), 0.28, 0.75),
        'negro': materialLiso('robotNegro', (0.012, 0.012, 0.014), 0.42, 0.05),
        'negroMate': materialLiso('robotNegroMate', (0.04, 0.04, 0.045), 0.7),
        'articulacion': materialLiso('robotArticulacion', (0.05, 0.052, 0.056), 0.3, 0.6),
        'gris': materialLiso('robotGris', (0.35, 0.36, 0.38), 0.4, 0.3),
        'goma': materialLiso('robotGoma', (0.02, 0.02, 0.02), 0.85),
        'rojo': materialLiso('robotRojo', (0.7, 0.05, 0.04), 0.4),
        'visor': materialLiso('robotVisor', (0.008, 0.01, 0.012), 0.06, 0.4),
        'ojo': materialLiso('robotOjo', (0.25, 0.8, 1.0), 0.2, 0.0, 12.0),
        'iris': materialLiso('robotIris', (0.05, 0.45, 1.0), 0.2, 0.0, 2.5),
        'piloto': materialLiso('robotPiloto', (0.2, 1.0, 0.35), 0.3, 0.0, 10.0),
        'acero': materialLiso('robotAcero', (0.6, 0.61, 0.63), 0.3, 1.0),
        'laton': materialLiso('robotLaton', (0.78, 0.56, 0.22), 0.28, 1.0),
        'vidrio': materialLiso('robotVidrio', (0.6, 0.85, 1.0), 0.03, 0.0, 0.6),
        'nucleo': materialLiso('robotNucleo', (0.1, 0.75, 1.0), 0.2, 0.0, 5.0),
        'cobre': materialLiso('robotCobre', (0.72, 0.4, 0.2), 0.32, 1.0),
        'hoja': materialLiso('robotHoja', (0.05, 0.06, 0.07), 0.35, 0.7),
        # Placa de las siglas: transparente (el juego le pone el lienzo) y
        # la muestra de Blender en un rojo de nación.
        'logo': materialLiso('robotLogo', (1.0, 1.0, 1.0), 0.6, 0.0),
        'logoMuestra': materialLiso('robotLogoMuestra', (0.75, 0.12, 0.08), 0.6, 0.0),
    }


# Geometría ---------------------------------------------------------------------

def suave(objeto):
    """Sombreado suave con bordes vivos por ángulo (30°)."""
    for cara in objeto.data.polygons:
        cara.use_smooth = True
    try:
        objeto.data.set_sharp_from_angle(angle=math.radians(30))
    except AttributeError:
        objeto.data.use_auto_smooth = True
        objeto.data.auto_smooth_angle = math.radians(30)


def objetoDe(nombre, bm, material):
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    bpy.context.scene.collection.objects.link(objeto)
    suave(objeto)
    return objeto


def caja(nombre, centro, tamano, material, bisel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tamano), verts=bm.verts)
    if bisel > 0:
        bisel = min(bisel, min(tamano) * 0.45)
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bisel, segments=3, affect='EDGES', profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def cilindro(nombre, centro, radio, largo, material, eje='z', lados=32, bisel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=radio, radius2=radio, depth=largo)
    if bisel > 0:
        bordes = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6 and len(e.link_faces) == 2]
        bmesh.ops.bevel(bm, geom=bordes, offset=min(bisel, largo * 0.4, radio * 0.4), segments=2, affect='EDGES', profile=0.5)
    if eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def esfera(nombre, centro, radio, material, escala=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=14, radius=radio)
    bmesh.ops.scale(bm, vec=Vector(escala), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def segmento(nombre, a, b, ancho, fondo, material, bisel=0.0, extra=0.0):
    """Caja de `a` a `b` con sección `fondo` x `ancho` (el ancho va en y),
    alargada `extra` por cada punta."""
    a, b = Vector(a), Vector(b)
    eje = b - a
    largo = eje.length + 2 * extra
    objeto = caja(nombre, (0, 0, 0), (fondo, ancho, largo), material, bisel)
    giro = eje.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    objeto.data.transform(Matrix.Translation((a + b) / 2) @ giro)
    return objeto


def unir(objetos, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for objeto in objetos:
        objeto.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    bpy.ops.object.join()
    objetos[0].name = nombre
    objetos[0].data.name = nombre
    return objetos[0]


def pieza(nombre, piezas, pivote, padre=None):
    """Une `piezas` en un objeto con el origen en `pivote` (mundo) y lo
    cuelga de `padre` sin moverlo."""
    objeto = unir(piezas, nombre)
    pivote = Vector(pivote)
    objeto.data.transform(Matrix.Translation(-pivote))
    objeto.location = pivote
    if padre:
        objeto.parent = padre
        objeto.matrix_parent_inverse = padre.matrix_world.inverted()
    return objeto


# Siglas de la nación (el dueño, 17-nov: letras de plantilla de su nación,
# en su color): una placa plana con UV de 0 a 1 (u a lo ancho, hacia +y; v
# hacia arriba) que mira a +x. El juego pinta las siglas en un lienzo y lo
# pone de textura (almacen/robots/especializaciones/siglas.lua). En Blender
# se ve una muestra (`vistaSiglas`, no se exporta).
SIGLAS_FUENTE = os.path.join(os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.expanduser('~/NationsRTS/tools/blender'), '..', '..', 'assets', 'fuentes', 'SairaStencilOne-Regular.ttf')
SIGLAS_MUESTRA = 'KAL'


def placaSiglas(centro, ancho, alto, padre, m):
    x, y, z = centro
    bm = bmesh.new()
    vs = [bm.verts.new((x, y + dy, z + dz)) for dy, dz in ((-ancho / 2, -alto / 2), (ancho / 2, -alto / 2), (ancho / 2, alto / 2), (-ancho / 2, alto / 2))]
    cara = bm.faces.new(vs)
    capa = bm.loops.layers.uv.verify()
    for bucle, uv in zip(cara.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        bucle[capa].uv = uv
    placa = objetoDe('logoPecho', bm, m['logo'])
    principled = nodoPrincipled(m['logo'])
    principled.inputs['Alpha'].default_value = 0.0
    pieza_ = pieza('logoPecho', [placa], centro, padre)
    # Muestra para Blender.
    try:
        fuente = bpy.data.fonts.load(os.path.abspath(SIGLAS_FUENTE), check_existing=True)
        texto = bpy.data.curves.new('vistaSiglas', 'FONT')
        texto.body = SIGLAS_MUESTRA
        texto.font = fuente
        texto.size = alto * 2.2  # las mayúsculas miden ~0,45 del cuerpo
        texto.align_x = 'CENTER'
        texto.align_y = 'CENTER'
        texto.materials.append(m['logoMuestra'])
        vista = bpy.data.objects.new('vistaSiglas', texto)
        bpy.context.scene.collection.objects.link(vista)
        vista.rotation_euler = (math.pi / 2, 0, math.pi / 2)
        vista.location = (x + 0.0005, y, z)
        bpy.context.view_layer.update()
        vista.parent = pieza_
        vista.matrix_parent_inverse = pieza_.matrix_world.inverted()
    except Exception as error:
        print('SIGLAS sin muestra:', error)
    return pieza_


def placaSombra(largo, ancho, padre, m):
    """Sombra de contacto (el dueño, 17-nov): un cuadrado en el suelo bajo la
    base, de `largo` (x) por `ancho` (y), con UV de 0 a 1. El juego le pone
    un degradado negro que se desvanece hacia el borde
    (almacen/robots/especializaciones/sombra.lua): las sombras de las
    lámparas son estáticas y sin esto el robot parecía flotar."""
    bm = bmesh.new()
    vs = [bm.verts.new((dx * largo / 2, dy * ancho / 2, 0.006)) for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    cara = bm.faces.new(vs)
    capa = bm.loops.layers.uv.verify()
    for bucle, uv in zip(cara.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        bucle[capa].uv = uv
    placa = objetoDe('sombraSuelo', bm, m['logo'])
    return pieza('sombraSuelo', [placa], (0, 0, 0), padre)


TEXTURAS = os.path.expanduser('~/NationsRTS-assets/robots/texturas')


# Detalle (skill vehiculo-detallado), compartido con robot_pesado.py ---------

def perno(nombre, centro, normal, m, radio=0.016, hexagonal=True, material='laton'):
    """Tornillo con arandela: cabeza hexagonal (o redonda, de botón) y
    arandela fina debajo, mirando hacia `normal`."""
    n = Vector(normal).normalized()
    giro = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    c = Vector(centro)
    piezas = [
        cilindro(nombre + 'Arandela', (0, 0, 0.002), radio * 1.45, 0.004, m['acero'], lados=24),
        cilindro(nombre, (0, 0, 0.004 + radio * 0.35), radio, radio * 0.7, m[material], lados=6 if hexagonal else 24, bisel=radio * 0.15),
    ]
    if not hexagonal:
        piezas[1] = esfera(nombre, (0, 0, 0.004), radio, m[material], (1, 1, 0.45))
        piezas.append(caja(nombre + 'Ranura', (0, 0, 0.004 + radio * 0.45), (radio * 1.4, radio * 0.22, radio * 0.12), m['negro']))
    for o in piezas:
        o.data.transform(Matrix.Translation(c) @ giro)
    return piezas


def filaRemaches(a, b, n, normal, m, radio=0.011):
    """`n` remaches de cabeza redonda en línea de `a` a `b`."""
    a, b = Vector(a), Vector(b)
    p = []
    nn = Vector(normal).normalized()
    giro = nn.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    for k in range(n):
        c = a + (b - a) * (k / max(1, n - 1))
        r = esfera('remache', (0, 0, 0), radio, m['acero'], (1, 1, 0.5))
        r.data.transform(Matrix.Translation(c) @ giro)
        p.append(r)
    return p


def junta(centro, tamano, m):
    """Ranura oscura entre dos paneles (una tira negra mate apenas saliente)."""
    return caja('junta', centro, tamano, m['negroMate'])


def perfilExtruido(nombre, puntos, grosor, material, bisel=0.008, z=0.0):
    """Placa con el contorno `puntos` (x, y) y `grosor` en z, centrada en z,
    con los cantos biselados (2 segmentos)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z - grosor / 2)) for x, y in puntos]
    cara = bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=[cara])
    if cara.normal.z > 0:
        cara.normal_flip()
    salida = bmesh.ops.extrude_face_region(bm, geom=[cara])
    nuevos = [e for e in salida['geom'] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, grosor)), verts=nuevos)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bisel > 0:
        bordes = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=bordes, offset=bisel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    return objetoDe(nombre, bm, material)


def manguera(nombre, puntos, radio, material):
    """Manguera hidráulica: curva suave por `puntos` con sección redonda."""
    curva = bpy.data.curves.new(nombre, 'CURVE')
    curva.dimensions = '3D'
    curva.bevel_depth = radio
    curva.bevel_resolution = 6
    curva.resolution_u = 16
    s = curva.splines.new('BEZIER')
    s.bezier_points.add(len(puntos) - 1)
    for bp, pt in zip(s.bezier_points, puntos):
        bp.co = Vector(pt)
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    curva.use_fill_caps = True
    objeto = bpy.data.objects.new(nombre, curva)
    objeto.data.materials.append(material)
    bpy.context.scene.collection.objects.link(objeto)
    bpy.ops.object.select_all(action='DESELECT')
    objeto.select_set(True)
    bpy.context.view_layer.objects.active = objeto
    bpy.ops.object.convert(target='MESH')
    suave(objeto)
    return objeto


def materialPBR(nombre, color, rugosidad, metalico, textura, escala=1.0, fuerzaNormal=0.6, usarColor=False):
    """Material con textura real (Poly Haven / ambientCG, CC0) en proyección
    de caja: el color base es la pintura limpia (`color`); de la textura
    entran la rugosidad (alrededor de `rugosidad`) y la normal. Con
    `usarColor` el color sale de la propia textura (acero, goma)."""
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nodoPrincipled(mat)
    bsdf.inputs['Metallic'].default_value = metalico
    coord = nt.nodes.new('ShaderNodeTexCoord')
    mapa = nt.nodes.new('ShaderNodeMapping')
    mapa.inputs['Scale'].default_value = (escala, escala, escala)
    nt.links.new(coord.outputs['Object'], mapa.inputs['Vector'])

    def imagen(ruta, color=False):
        nodo = nt.nodes.new('ShaderNodeTexImage')
        nodo.image = bpy.data.images.load(ruta, check_existing=True)
        nodo.image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
        nodo.projection = 'BOX'
        nodo.projection_blend = 0.25
        nt.links.new(mapa.outputs['Vector'], nodo.inputs['Vector'])
        return nodo

    rutas = textura
    if usarColor and rutas.get('color'):
        col = imagen(rutas['color'], True)
        mezcla = nt.nodes.new('ShaderNodeMix')
        mezcla.data_type = 'RGBA'
        mezcla.blend_type = 'MULTIPLY'
        mezcla.inputs['Factor'].default_value = 1.0
        nt.links.new(col.outputs['Color'], mezcla.inputs['A'])
        mezcla.inputs['B'].default_value = (*color, 1)
        nt.links.new(mezcla.outputs['Result'], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = (*color, 1)
    if rutas.get('rugosidad'):
        rug = imagen(rutas['rugosidad'])
        rango = nt.nodes.new('ShaderNodeMapRange')
        rango.inputs['To Min'].default_value = max(0.0, rugosidad - 0.12)
        rango.inputs['To Max'].default_value = min(1.0, rugosidad + 0.12)
        nt.links.new(rug.outputs['Color'], rango.inputs['Value'])
        nt.links.new(rango.outputs['Result'], bsdf.inputs['Roughness'])
    else:
        bsdf.inputs['Roughness'].default_value = rugosidad
    if rutas.get('normal'):
        nor = imagen(rutas['normal'])
        mapaN = nt.nodes.new('ShaderNodeNormalMap')
        mapaN.inputs['Strength'].default_value = fuerzaNormal
        nt.links.new(nor.outputs['Color'], mapaN.inputs['Color'])
        nt.links.new(mapaN.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def materialesReales(m):
    """Cambia los materiales lisos por los PBR con texturas reales, si se
    han bajado (tools: ver TEXTURAS)."""
    t = TEXTURAS
    placa2 = {'rugosidad': t + '/metal_plate_02_rough.jpg', 'normal': t + '/metal_plate_02_nor.jpg'}
    goma = {'color': t + '/Rubber004/Rubber004_4K-JPG_Color.jpg', 'rugosidad': t + '/Rubber004/Rubber004_4K-JPG_Roughness.jpg', 'normal': t + '/Rubber004/Rubber004_4K-JPG_NormalGL.jpg'}
    if not os.path.exists(placa2['normal']):
        print('SIN TEXTURAS en', t)
        return
    nuevos = {
        'blanco': materialPBR('pesadoBlanco', (0.8, 0.81, 0.83), 0.35, 0.05, placa2, 1.0, 0.35),
        'negro': materialPBR('pesadoNegro', (0.014, 0.014, 0.016), 0.45, 0.1, placa2, 1.0, 0.4),
        # Acero limpio: gris de acero de base (la chapa estriada de
        # metal_plate salía oxidada y con rombos), con la rugosidad y la
        # normal suaves de metal_plate_02.
        'plata': materialPBR('pesadoPlata', (0.72, 0.73, 0.75), 0.22, 1.0, placa2, 1.0, 0.25),
        'acero': materialPBR('pesadoAcero', (0.56, 0.57, 0.59), 0.3, 1.0, placa2, 2.0, 0.25),
        # Goma negra mate (albedo ~0,16 como pide la skill): la textura
        # de ambientCG multiplicada por un gris oscuro.
        'goma': materialPBR('pesadoGoma', (0.32, 0.32, 0.32), 0.8, 0.0, goma, 1.5, 0.8, True),
        'garra': materialPBR('pesadoGarra', (0.02, 0.02, 0.022), 0.5, 0.2, placa2, 1.5, 0.5),
    }
    for clave, mat in nuevos.items():
        if clave not in m:
            continue
        viejo = m.get(clave)
        if viejo:
            viejo.user_remap(mat)
        m[clave] = mat


def aro(nombre, centro, rInt, rExt, grosor, material, lados=128, eje='x', bisel=0.0):
    """Aro plano (corona) con su agujero, de `grosor` a lo largo de `eje`."""
    bm = bmesh.new()
    frente, atras = [], []
    for r in (rExt, rInt):
        anillo = []
        for z in (grosor / 2, -grosor / 2):
            anillo.append([bm.verts.new((r * math.cos(2 * math.pi * k / lados), r * math.sin(2 * math.pi * k / lados), z)) for k in range(lados)])
        (frente if r == rExt else atras).append(anillo)
    (ef, et), (inf, intr) = frente[0], atras[0]
    for k in range(lados):
        j = (k + 1) % lados
        bm.faces.new((ef[k], ef[j], inf[j], inf[k]))       # cara de delante
        bm.faces.new((et[j], et[k], intr[k], intr[j]))     # cara de atrás
        bm.faces.new((ef[j], ef[k], et[k], et[j]))         # canto de fuera
        bm.faces.new((inf[k], inf[j], intr[j], intr[k]))   # canto de dentro
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bisel > 0:
        bordes = [e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.dot(e.link_faces[1].normal)) < 0.5]
        bmesh.ops.bevel(bm, geom=bordes, offset=bisel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    if eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def enDisco(objeto, centro, angulo, radio):
    """Lleva una malla hecha en el origen (mirando a +x) a `radio` del centro
    de un disco que mira a +x, a `angulo` (en el plano y-z), girada con él."""
    c = Vector(centro)
    pos = c + Vector((0, math.cos(angulo) * radio, math.sin(angulo) * radio))
    objeto.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(angulo, 4, 'X'))
    return objeto


# Ojos: óptica binocular mecánica (las capturas del dueño del 2026-11-17,
# diseño propio). Cada ojo, de fuera a dentro:
#   carcasa saliente con bisel dentado (48 dientes) y 8 tornillos;
#   aro de cobre con 24 ranuras (`anillo{S}`, gira por código);
#   diafragma de 18 láminas curvas con el borde cian (`diafragma{S}` gira
#   entero despacio; cada lámina `hoja{S}NN` gira sobre su pivote para
#   abrir y cerrar la pupila);
#   núcleo cian que brilla con el centro blanco, dentro del globo (`ojo{S}`,
#   gira hacia donde mira);
#   párpados blindados arriba y abajo (`parpadoSup{S}`, `parpadoInf{S}`:
#   bajan y suben en z para las expresiones y el parpadeo).
# `e` escala todo (1: el robot pequeño).
OJO_SALIENTE = 0.02
OJO_RADIO = 0.044  # carcasa
OJO_HOJAS = 18
OJO_PIVOTE = 0.0235  # radio de los pivotes de las láminas
PARPADO_CUBRE = 0.014  # lo que tapa cada párpado de la abertura en reposo


def contornoHoja(e):
    """Lámina del diafragma con el pivote en el origen: un arco que sale
    hacia el centro del ojo y se curva (ancha en la raíz, fina en la punta).
    Coordenadas del plano del ojo; el centro del ojo queda hacia -x."""
    pts_fuera, pts_dentro = [], []
    n = 14
    for k in range(n + 1):
        f = k / n
        a = math.radians(200) - f * math.radians(70)  # sale hacia el centro y se curva
        r = 0.021 * e
        cx, cy = 0.012 * e, -0.017 * e
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        # Normal hacia fuera del arco.
        nx, ny = math.cos(a), math.sin(a)
        ancho = (0.0095 - 0.0065 * f) * e
        pts_fuera.append((x + nx * ancho / 2, y + ny * ancho / 2))
        pts_dentro.append((x - nx * ancho / 2, y - ny * ancho / 2))
    return pts_fuera + pts_dentro[::-1]


# Las láminas se montan como en un diafragma de verdad (el dueño, 18-nov: una
# sobresalía): en vez de apilarlas una delante de otra (la última quedaba
# encima de la primera y rompía la espiral), cada una va inclinada a lo
# ancho: el filo de dentro (el del hilo cian) LAMINA_SUBE más adelante que el
# de fuera. Así cada filo queda encima de la lámina vecina, igual en todo el
# círculo y sin costura.
LAMINA_SUBE = 0.003


def inclinarLamina(objeto, e):
    """Sube cada vértice de una lámina (en su plano, antes de `enOjo`) según
    lo cerca que está de su filo de dentro (el arco de contornoHoja: centro
    (0,012, -0,017) y radio 0,021, por `e`; la lámina mide hasta ~1 cm de
    ancho)."""
    cx, cy, r, medio = 0.012 * e, -0.017 * e, 0.021 * e, 0.005 * e
    for v in objeto.data.vertices:
        dc = math.hypot(v.co.x - cx, v.co.y - cy)
        v.co.z += LAMINA_SUBE * e * min(1.0, max(0.0, (r + medio - dc) / (2 * medio)))
    objeto.data.update()


def enOjo(objeto, cx, y, zc, angulo):
    """Lleva una malla hecha en el plano x-y (grosor en z) al plano del ojo
    (normal +x), girada `angulo` alrededor del eje del ojo y centrada en
    (cx, y, zc)."""
    plano = Matrix.Rotation(math.pi / 2, 4, 'Y')  # z -> x
    objeto.data.transform(Matrix.Translation((cx, y, zc)) @ Matrix.Rotation(angulo, 4, 'X') @ plano)
    return objeto


def ojoCuenca(m, xf, y, zc, e, lado):
    """Lo fijo de un ojo (va en la cabeza): carcasa saliente, bisel dentado,
    tornillos y el fondo oscuro."""
    xCara = xf
    xf = xf + OJO_SALIENTE * e
    R = OJO_RADIO * e
    p = [
        # Carcasa: tubo corto (el ojo va dentro, se ve por el agujero).
        aro('carcasa', ((xCara + xf) / 2, y, zc), 0.034 * e, R, xf - xCara + 0.002 * e, m['negro'], bisel=0.0015 * e),
        aro('bisel', (xf + 0.001 * e, y, zc), 0.035 * e, R - 0.001 * e, 0.004 * e, m['acero'], bisel=0.0006 * e),
        aro('fondoBisel', (xf + 0.0035 * e, y, zc), 0.0335 * e, 0.0355 * e, 0.002 * e, m['negro']),
        cilindro('fondo', (xf - 0.009 * e, y, zc), 0.034 * e, 0.003 * e, m['visor'], eje='x', lados=128),
    ]
    # Bisel dentado: 48 dientes en el canto de fuera.
    for k in range(48):
        a = k * 2 * math.pi / 48
        diente = caja('dienteBisel', (0, 0, 0), (0.003 * e, 0.0028 * e, 0.0028 * e), m['acero'], 0.0004 * e)
        diente.data.transform(Matrix.Rotation(math.pi / 4, 4, 'X'))
        p.append(enDisco(diente, (xf + 0.0035 * e, y, zc), a, 0.0405 * e))
    # Tornillos de la carcasa.
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        tornillo = cilindro('tornilloOjo', (0, 0, 0), 0.0018 * e, 0.0025 * e, m['acero'], eje='x', lados=6)
        p.append(enDisco(tornillo, (xf + 0.0035 * e, y, zc), a, 0.0365 * e))
    return p


def ojoPiezas(m, xf, y, zc, e, s, cabeza):
    """Lo que se mueve de un ojo (ver arriba). Devuelve el globo."""
    xf = xf + OJO_SALIENTE * e
    cx = xf - 0.006 * e
    p = [
        cilindro('fondoIris', (cx - 0.002 * e, y, zc), 0.025 * e, 0.002 * e, m['articulacion'], eje='x', lados=128),
        aro('halo', (cx - 0.0005 * e, y, zc), 0.006 * e, 0.0125 * e, 0.001 * e, m['iris'], lados=96),
        cilindro('nucleo', (cx, y, zc), 0.0075 * e, 0.0025 * e, m['nucleo'], eje='x', lados=96),
        cilindro('centroNucleo', (cx + 0.0013 * e, y, zc), 0.0035 * e, 0.001 * e, m['ojo'], eje='x', lados=64),
        aro('aroInterior', (cx + 0.001 * e, y, zc), 0.0245 * e, 0.0265 * e, 0.002 * e, m['negro'], lados=128),
    ]
    ojo = pieza('ojo' + s, p, (cx, y, zc), cabeza)
    # Aro de cobre con 24 ranuras oscuras (gira).
    q = [aro('aroCobre', (cx + 0.002 * e, y, zc), 0.0268 * e, 0.0325 * e, 0.0022 * e, m['cobre'], lados=128, bisel=0.0003 * e)]
    for k in range(24):
        a = k * 2 * math.pi / 24
        ranura = caja('ranura', (0, 0, 0), (0.0006 * e, 0.0022 * e, 0.0018 * e), m['negroMate'])
        q.append(enDisco(ranura, (cx + 0.0033 * e, y, zc), a, 0.0297 * e))
    pieza('anillo' + s, q, (cx, y, zc), ojo)
    # Diafragma: 18 láminas, cada una gira sobre su pivote.
    diafragma = pieza('diafragma' + s, [aro('baseDiafragma', (cx + 0.0005 * e, y, zc), 0.0225 * e, 0.0255 * e, 0.0012 * e, m['articulacion'], lados=128)], (cx, y, zc), ojo)
    contorno = contornoHoja(e)
    for k in range(OJO_HOJAS):
        a = k * 2 * math.pi / OJO_HOJAS
        # Todas a la misma altura: el solape lo da su inclinación.
        xk = cx + 0.0012 * e
        hoja = perfilExtruido('hoja', contorno, 0.0005 * e, m['hoja'], 0.00012 * e)
        borde = perfilExtruido('bordeHoja', contorno[:15], 0.0002 * e, m['nucleo'], 0.0)  if False else None
        piezas = [hoja]
        # Borde cian: un hilo que brilla a lo largo del filo de dentro.
        filo = contorno[15:]
        for i in range(len(filo) - 1):
            (x0, y0), (x1, y1) = filo[i], filo[i + 1]
            hilo = segmento('filo', (x0, y0, 0.0004 * e), (x1, y1, 0.0004 * e), 0.0006 * e, 0.0004 * e, m['nucleo'])
            piezas.append(hilo)
        # El pivote: un remache diminuto.
        piezas.append(cilindro('pivoteHoja', (0, 0, 0.0004 * e), 0.0009 * e, 0.0008 * e, m['acero'], lados=12))
        for o in piezas:
            inclinarLamina(o, e)
        # Del plano de la lámina al del ojo: el pivote en su sitio del aro
        # (radio OJO_PIVOTE, ángulo a) y la lámina mirando hacia el centro.
        py, pz = math.cos(a) * OJO_PIVOTE * e, math.sin(a) * OJO_PIVOTE * e
        for o in piezas:
            enOjo(o, xk, y + py, zc + pz, a)
        pieza('hoja%s%02d' % (s, k), piezas, (xk, y + py, zc + pz), diafragma)
    # Párpados blindados: un segmento del círculo del ojo (canto en recta,
    # lomo en arco) de acero gris con un nervio y dos tornillos. El juego los
    # baja y sube en z (expresiones y parpadeo) y los inclina (tenso).
    r = 0.0352 * e
    h = PARPADO_CUBRE * e
    for nombre, signo in (('parpadoSup', 1), ('parpadoInf', -1)):
        a0 = math.asin((r - h) / r)
        puntos = []
        for k in range(33):
            a = a0 + (math.pi - 2 * a0) * k / 32
            puntos.append((math.cos(a) * r, signo * math.sin(a) * r))
        if signo < 0:
            puntos.reverse()
        placa = perfilExtruido('parpado', puntos, 0.0025 * e, m['gris'], 0.0005 * e)
        zCanto = signo * (r - h)
        canto = segmento('cantoParpado', (-math.cos(a0) * r, zCanto, 0.0012 * e), (math.cos(a0) * r, zCanto, 0.0012 * e), 0.0016 * e, 0.0016 * e, m['negro'], 0.0004 * e)
        nervio = segmento('nervioParpado', (-0.016 * e, zCanto + signo * 0.005 * e, 0.0016 * e), (0.016 * e, zCanto + signo * 0.005 * e, 0.0016 * e), 0.0012 * e, 0.0012 * e, m['acero'], 0.0003 * e)
        piezas = [placa, canto, nervio]
        for sy in (-1, 1):
            piezas.append(cilindro('tornilloParpado', (sy * 0.022 * e, zCanto + signo * 0.0085 * e, 0.0015 * e), 0.0015 * e, 0.0012 * e, m['acero'], lados=6))
        # Del plano (x a lo ancho, y arriba) al del ojo: x -> y, y -> z, z -> x.
        giro = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        for o in piezas:
            o.data.transform(Matrix.Translation((xf + 0.0045 * e, y, zc)) @ giro)
        pieza(nombre + s, piezas, (xf + 0.0045 * e, y, zc + zCanto), cabeza)
    return ojo


def frenteCabeza(m, xf, zc, e):
    """Lo de la cara entre los ojos: placa de frente con tornillos y raya, y
    la rejilla de la nariz."""
    p = [
        caja('placaFrente', (xf + 0.004 * e, 0, zc + 0.04 * e), (0.008 * e, 0.05 * e, 0.03 * e), m['blanco'], 0.002 * e),
        caja('rayaFrente', (xf + 0.0085 * e, 0, zc + 0.04 * e), (0.001 * e, 0.003 * e, 0.02 * e), m['negro']),
        cilindro('nariz', (xf + 0.004 * e, 0, zc - 0.028 * e), 0.011 * e, 0.008 * e, m['negro'], eje='x', lados=64, bisel=0.001 * e),
        aro('aroNariz', (xf + 0.008 * e, 0, zc - 0.028 * e), 0.009 * e, 0.0115 * e, 0.0015 * e, m['cobre'], lados=64),
    ]
    for sy in (-1, 1):
        p.append(cilindro('tornilloFrente', (xf + 0.0085 * e, sy * 0.016 * e, zc + 0.044 * e), 0.0025 * e, 0.0015 * e, m['acero'], eje='x', lados=6))
    for k in range(5):
        p.append(caja('rejillaNariz', (xf + 0.0085 * e, (k - 2) * 0.0035 * e, zc - 0.028 * e), (0.0012 * e, 0.0014 * e, 0.014 * e), m['negroMate']))
    return p


# El robot ----------------------------------------------------------------------

def crearBase(m):
    """Sin chasis: un eje entre las dos ruedas con sus motores y, encima, el
    cubo de la cadera de donde sale la pierna (el robot se sostiene sobre las
    dos ruedas, como uno de equilibrio)."""
    yr = BASE[1] / 2 + ANCHO_RUEDA / 2 + 0.015
    yInterior = yr - ANCHO_RUEDA / 2
    z = RADIO_RUEDA
    p = [
        cilindro('eje', (0, 0, z), 0.032, 2 * yInterior - 0.02, m['articulacion'], eje='y', bisel=0.006),
        # Cubo central: une el eje con la cadera.
        caja('cuboCadera', (0.03, 0, (z + CADERA[1]) / 2 + 0.01), (0.2, 0.2, CADERA[1] - z + 0.12), m['blanco'], 0.06),
        caja('cuboCaderaPlaca', (0.03, 0, (z + CADERA[1]) / 2), (0.205, 0.12, 0.06), m['negro'], 0.012),
        cilindro('lidar', (0.135, 0, z + 0.03), 0.028, 0.03, m['visor'], eje='x', bisel=0.004),
        cilindro('piloto', (0.11, -0.07, z + 0.07), 0.009, 0.02, m['piloto'], eje='x'),
        caja('asientoCadera', (CADERA[0], 0, CADERA[1] - 0.05), (0.18, 0.22, 0.07), m['articulacion'], 0.02),
    ]
    # Cubo de la cadera: pernos en la placa negra y remaches en los cantos.
    zc = (z + CADERA[1]) / 2
    for sy in (-1, 1):
        p += perno('pernoPlaca', (0.1325, sy * 0.045, zc), (1, 0, 0), m, 0.005, material='acero')
        p += filaRemaches((-0.05, sy * 0.1, z + 0.04), (-0.05, sy * 0.1, CADERA[1] + 0.03), 5, (0, sy, 0), m, 0.0035)
        p += filaRemaches((0.11, sy * 0.1, z + 0.04), (0.11, sy * 0.1, CADERA[1] + 0.03), 5, (0, sy, 0), m, 0.0035)
    p.append(junta((0.131, 0, zc + 0.06), (0.004, 0.16, 0.004), m))
    for lado in (-1, 1):
        # Motor de cada rueda, pegado a su cara de dentro.
        p.append(cilindro('motor', (0, lado * (yInterior - 0.03), z), 0.075, 0.05, m['negro'], eje='y', bisel=0.012))
        p.append(cilindro('motorTapa', (0, lado * (yInterior - 0.058), z), 0.05, 0.008, m['gris'], eje='y', bisel=0.002))
        for k in range(6):
            a = k * math.pi / 3
            p.append(cilindro('motorTornillo', (math.cos(a) * 0.062, lado * (yInterior - 0.056), z + math.sin(a) * 0.062), 0.005, 0.006, m['plata'], eje='y', lados=8))
    return pieza('robot', p, (0, 0, 0))


def alrededorDelEje(objeto, centro, angulo, radio):
    """Lleva una malla hecha en el origen (su x hacia fuera) a `radio` del
    eje y de la rueda, a `angulo` (en el plano x-z)."""
    c = Vector(centro)
    pos = c + Vector((math.cos(angulo) * radio, 0, math.sin(angulo) * radio))
    objeto.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(-angulo, 4, 'Y'))
    return objeto


def crearRueda(m, nombre, centro, radio, ancho, padre):
    """Rueda motriz: goma con dos filas de tacos al tresbolillo, llanta con
    5 radios y tapacubos con 5 tornillos. Los tacos y los radios hacen que se
    vea girar."""
    hacia = math.copysign(1, centro[1])
    cara = centro[1] + hacia * ancho / 2
    p = [
        cilindro(nombre + 'Goma', centro, radio - 0.01, ancho, m['goma'], eje='y', lados=128, bisel=0.016),
    ]
    tacos = 22
    for fila, dy in enumerate((-ancho * 0.24, ancho * 0.24)):
        for k in range(tacos):
            a = (k + 0.5 * fila) * 2 * math.pi / tacos
            taco = caja(nombre + 'Taco', (0, 0, 0), (0.016, ancho * 0.42, 0.03), m['goma'], 0.004)
            taco.data.transform(Matrix.Translation((0, dy, 0)))
            p.append(alrededorDelEje(taco, centro, a, radio - 0.008))
    # Llanta: plato negro mate hundido y 5 radios grises encima.
    p.append(cilindro(nombre + 'Llanta', (centro[0], cara - hacia * 0.002, centro[2]), radio * 0.68, 0.012, m['negroMate'], eje='y', lados=128))
    p.append(cilindro(nombre + 'Aro', (centro[0], cara + hacia * 0.003, centro[2]), radio * 0.7, 0.006, m['gris'], eje='y', lados=128))
    p.append(cilindro(nombre + 'AroHueco', (centro[0], cara + hacia * 0.004, centro[2]), radio * 0.62, 0.006, m['negroMate'], eje='y', lados=128))
    for k in range(5):
        a = k * 2 * math.pi / 5 + 0.3
        largo = radio * (0.66 - 0.28)
        radioPieza = caja(nombre + 'Radio', (0, 0, 0), (largo, 0.012, 0.03), m['gris'], 0.004)
        radioPieza.data.transform(Matrix.Translation((0, hacia * 0.009, 0)))
        p.append(alrededorDelEje(radioPieza, (centro[0], cara, centro[2]), a, radio * 0.28 + largo / 2))
    p.append(cilindro(nombre + 'Tapacubos', (centro[0], cara + hacia * 0.012, centro[2]), radio * 0.3, 0.014, m['gris'], eje='y', bisel=0.003))
    for k in range(5):
        a = k * 2 * math.pi / 5
        p.append(cilindro(nombre + 'Tornillo', (centro[0] + math.cos(a) * radio * 0.18, cara + hacia * 0.02, centro[2] + math.sin(a) * radio * 0.18), 0.009, 0.008, m['negro'], eje='y', lados=6))
    return pieza(nombre, p, centro, padre)


def crearRuedaLoca(m, nombre, x, padre):
    radio = 0.04
    p = [
        caja(nombre + 'Horquilla', (x, 0, radio + 0.04), (0.05, 0.06, 0.05), m['articulacion'], 0.01),
        cilindro(nombre + 'Rueda', (x - 0.015, 0, radio), radio, 0.03, m['goma'], eje='y', lados=24, bisel=0.005),
    ]
    return pieza(nombre, p, (x, 0, radio + 0.065), padre)


def articulacion(nombre, x, z, radio, ancho, m):
    """Eje de una articulación a lo largo de y, con sus tapas grises."""
    p = [cilindro(nombre, (x, 0, z), radio, ancho, m['articulacion'], eje='y', bisel=0.01)]
    for lado in (-1, 1):
        p.append(cilindro(nombre + 'Tapa', (x, lado * (ancho / 2 + 0.003), z), radio * 0.6, 0.008, m['gris'], eje='y', bisel=0.002))
        for k in range(6):
            a = k * math.pi / 3
            p += perno(nombre + 'Perno', (x + math.cos(a) * radio * 0.42, lado * (ancho / 2 + 0.007), z + math.sin(a) * radio * 0.42), (0, lado, 0), m, 0.0045, material='acero')
    return p


def crearPierna(m, padre):
    """Espinilla (de la cadera a la rodilla) y muslo (de la rodilla a la
    cintura): carcasa blanca y plata con placas negras a los lados."""
    c = (CADERA[0], 0, CADERA[1])
    r = (RODILLA[0], 0, RODILLA[1])
    w = (CINTURA[0], 0, CINTURA[1])
    p = articulacion('cadera', CADERA[0], CADERA[1], 0.075, 0.2, m)
    p.append(segmento('espinillaCarcasa', c, r, 0.15, 0.12, m['plata'], 0.045))
    for lado in (-1, 1):
        p.append(segmento('espinillaPlaca', (c[0], lado * 0.077, c[2]), (r[0], lado * 0.077, r[2]), 0.012, 0.085, m['negro'], 0.005, -0.06))
        for f in (0.22, 0.78):
            q = Vector(c).lerp(Vector(r), f)
            p += perno('pernoEspinilla', (q.x, lado * 0.084, q.z), (0, lado, 0), m, 0.005, material='acero')
    espinilla = pieza('espinilla', p, c, padre)
    p = articulacion('rodilla', RODILLA[0], RODILLA[1], 0.085, 0.19, m)
    p.append(segmento('musloCarcasa', r, w, 0.16, 0.13, m['blanco'], 0.05))
    for lado in (-1, 1):
        p.append(segmento('musloPlaca', (r[0], lado * 0.082, r[2]), (w[0], lado * 0.082, w[2]), 0.012, 0.095, m['negro'], 0.005, -0.07))
        for f in (0.22, 0.78):
            q = Vector(r).lerp(Vector(w), f)
            p += perno('pernoMuslo', (q.x, lado * 0.089, q.z), (0, lado, 0), m, 0.005, material='acero')
    # Cable de la pierna al torso (por detrás).
    p.append(manguera('cablePierna', [(r[0] - 0.07, 0.03, r[2] + 0.02), (r[0] - 0.09, 0.03, (r[2] + w[2]) / 2), (w[0] - 0.08, 0.03, w[2] - 0.03)], 0.007, m['negroMate']))
    return pieza('muslo', p, r, espinilla)


def crearTorso(m, padre):
    z0 = CINTURA[1]
    zc = z0 + 0.25
    p = [
        cilindro('cintura', (0, 0, z0 + 0.03), 0.095, 0.1, m['articulacion'], bisel=0.01),
        caja('vientre', (0, 0, z0 + 0.11), (0.2, 0.26, 0.1), m['negro'], 0.04),
        # Pecho blanco arriba y negro abajo, como la foto, y placa gris.
        caja('pecho', (0, 0, zc + 0.045), (0.26, 0.38, 0.23), m['blanco'], 0.07),
        caja('pechoBajo', (0, 0, zc - 0.105), (0.245, 0.35, 0.11), m['negro'], 0.045),
        caja('placaPecho', (0.128, 0, zc + 0.07), (0.012, 0.12, 0.035), m['gris'], 0.005),
        # Mochila con la batería, detrás.
        caja('mochila', (-0.15, 0, zc - 0.02), (0.08, 0.26, 0.24), m['negro'], 0.03),
        caja('cuelloBase', (0, 0, zc + 0.16), (0.1, 0.12, 0.03), m['negro'], 0.012),
    ]
    # Juntas de los paneles del pecho, remaches alrededor de la placa y
    # pernos en las esquinas del pecho y de la mochila.
    p.append(junta((0.131, 0, zc - 0.04), (0.004, 0.3, 0.004), m))
    for y in (-0.11, 0.11):
        p.append(junta((0.131, y, zc + 0.05), (0.004, 0.004, 0.16), m))
    p += filaRemaches((0.135, -0.055, zc + 0.095), (0.135, 0.055, zc + 0.095), 6, (1, 0, 0), m, 0.003)
    p += filaRemaches((0.135, -0.055, zc + 0.045), (0.135, 0.055, zc + 0.045), 6, (1, 0, 0), m, 0.003)
    for sy in (-1, 1):
        for sz in (-1, 1):
            p += perno('pernoPecho', (0.131, sy * 0.15, zc + 0.045 + sz * 0.075), (1, 0, 0), m, 0.005, material='acero')
            p += perno('pernoMochila', (-0.19, sy * 0.11, zc - 0.02 + sz * 0.1), (-1, 0, 0), m, 0.005, material='acero')
    for k in range(5):
        p.append(caja('rejilla', (-0.191, 0, zc - 0.07 + k * 0.025), (0.003, 0.16, 0.008), m['negroMate'], 0.001))
    # Cables de la mochila a los hombros.
    for sy in (-1, 1):
        p.append(manguera('cableHombro', [(-0.17, sy * 0.1, zc + 0.08), (-0.12, sy * 0.17, zc + 0.15), (-0.05, sy * 0.2, zc + 0.14)], 0.006, m['negroMate']))
    torso = pieza('torso', p, (0, 0, z0), padre)
    placaSiglas((0.1345, 0, zc + 0.07), 0.096, 0.032, torso, m)
    return torso


LARGO_CUELLO = 0.13


def crearCabeza(m, padre):
    """Cuello largo de dos tramos con anillos y, encima, la cabeza del robot
    soldado entera (el dueño, 17-nov: «la cabeza y los ojos, los mismos del
    robot soldado»): casco con ojos esféricos de diafragma en punta,
    persianas, oídos de anillos que giran y máscara con mentón
    (robot_soldado.py etapaCabeza). Piezas: `cuello` (gira en z) ->
    `cabeza` (gira en y) -> globo{S}, persianas, oido{S}A/B/C..."""
    z0 = CINTURA[1] + 0.25 + 0.16
    cuello = pieza('cuello', [
        cilindro('cuello', (0, 0, z0 + LARGO_CUELLO / 2), 0.034, LARGO_CUELLO, m['articulacion'], bisel=0.006),
        cilindro('anilloCuello', (0, 0, z0 + LARGO_CUELLO * 0.3), 0.042, 0.016, m['gris'], bisel=0.004),
        cilindro('anilloCuello', (0, 0, z0 + LARGO_CUELLO * 0.7), 0.042, 0.016, m['gris'], bisel=0.004),
    ], (0, 0, z0), padre)
    ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.expanduser('~/NationsRTS/tools/blender'), 'robot_soldado.py')
    soldado = {'__name__': 'cabezaSoldado', '__file__': ruta}
    with open(ruta, encoding='utf8') as archivo:
        exec(archivo.read(), soldado)
    return soldado['etapaCabeza'](m, cuello, cx=0.0, zc=z0 + LARGO_CUELLO, conCuello=False)


# Pinza ------------------------------------------------------------------------

# Mano de tres dedos como la Robotiq 3-Finger (la foto del dueño del
# 2026-11-17): palma redonda negra, dos dedos a un lado y uno enfrente. Cada
# dedo: falange con sus pernos y punta con almohadilla de aluminio. Cierra en
# «pinza»: la falange gira hacia dentro y la punta gira lo contrario, así las
# almohadillas quedan paralelas y aprietan de frente.
#
# Ejes de la mano (los locales de `munieca` y de los dedos): x hacia la punta
# de los dedos, y hacia donde se abren (los dedos A y B a -y, el C a +y),
# z arriba. Las falanges (`dedo…A/B/C`) giran en z; las puntas
# (`punta…A/B/C`) cuelgan de ellas y giran en z lo contrario.
MANO_NUDILLO_X = 0.1  # x de los nudillos
MANO_NUDILLO_Y = 0.045  # |y| de los nudillos
MANO_FALANGE = 0.05  # del nudillo a la punta
MANO_ALMOHADILLA = 0.008  # de la línea del dedo a la cara de la almohadilla
MANO_PUNTA_X = 0.02  # de la articulación de la punta al centro de la almohadilla


def marcoMano(f):
    """Matriz 3x3 con x = f (hacia la punta), y = lado de apertura, z arriba."""
    s = Vector((0, 1, 0))
    u = f.cross(s).normalized()
    s = u.cross(f).normalized()
    return Matrix((f, s, u)).transposed()


def enMarco(objeto, origen, giro, desplazamiento=(0, 0, 0)):
    """Lleva una malla hecha en ejes de la mano al mundo."""
    T = Matrix.Translation(Vector(origen) + giro @ Vector(desplazamiento)) @ giro.to_4x4()
    objeto.data.transform(T)
    return objeto


def piezaOrientada(nombre, piezas, pivote, giro, padre):
    """Como `pieza`, pero los ejes locales del objeto son los de `giro`."""
    objeto = unir(piezas, nombre)
    M = Matrix.Translation(Vector(pivote)) @ giro.to_4x4()
    objeto.data.transform(M.inverted())
    objeto.matrix_world = M
    if padre:
        objeto.parent = padre
        objeto.matrix_parent_inverse = padre.matrix_world.inverted()
    return objeto


def crearPinza(m, sufijo, lado, munieca, f, padre):
    giro = marcoMano(f)
    o = munieca
    p = []
    # Brida de la muñeca con sus tornillos.
    p.append(enMarco(cilindro('brida', (0, 0, 0), 0.036, 0.016, m['articulacion'], eje='x', bisel=0.003), o, giro, (0.008, 0, 0)))
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        p.append(enMarco(cilindro('tornilloBrida', (0, 0, 0), 0.004, 0.006, m['plata'], eje='x', lados=8), o, giro, (0.0165, math.cos(a) * 0.027, math.sin(a) * 0.027)))
    # Palma: cuenco redondo negro y la tapa plana de delante, con el canto
    # plateado.
    p.append(enMarco(esfera('palma', (0, 0, 0), 0.058, m['negro'], (0.85, 1.0, 0.82)), o, giro, (0.043, 0, 0)))
    p.append(enMarco(caja('tapaPalma', (0, 0, 0), (0.016, 0.11, 0.084), m['negro'], 0.012), o, giro, (0.092, 0, 0)))
    for k in (-1, 1):
        p.append(enMarco(cilindro('pernoPalma', (0, 0, 0), 0.0035, 0.004, m['plata'], eje='y', lados=8), o, giro, (0.072, k * 0.05, 0.02)))
    # Cámara de muñeca encima, mirando a la punta.
    p.append(enMarco(caja('camaraMunieca', (0, 0, 0), (0.022, 0.05, 0.018), m['negro'], 0.005), o, giro, (0.07, 0, 0.05)))
    for dy, radio, material in ((-0.014, 0.005, 'visor'), (0.0, 0.0035, 'ojo'), (0.014, 0.005, 'visor')):
        p.append(enMarco(cilindro('lente', (0, 0, 0), radio, 0.003, m[material], eje='x', lados=16), o, giro, (0.0815, dy, 0.05)))
    mano = piezaOrientada('munieca' + sufijo, p, o, giro, padre)
    # Dedos: A y B a -y (arriba y abajo), C a +y en el medio.
    for letra, k, zDedo in (('A', -1, 0.022), ('B', -1, -0.022), ('C', 1, 0.0)):
        nudillo = (MANO_NUDILLO_X, k * MANO_NUDILLO_Y, zDedo)
        q = []
        q.append(enMarco(cilindro('nudillo', (0, 0, 0), 0.011, 0.03, m['articulacion'], eje='z', bisel=0.002), o, giro, nudillo))
        falange = caja('falange', (0, 0, 0), (MANO_FALANGE + 0.012, 0.014, 0.024), m['negro'], 0.005)
        q.append(enMarco(falange, o, giro, (nudillo[0] + MANO_FALANGE / 2, nudillo[1], zDedo)))
        for e in (0.012, MANO_FALANGE - 0.012):
            for s in (-1, 1):
                q.append(enMarco(cilindro('perno', (0, 0, 0), 0.0035, 0.002, m['plata'], eje='y', lados=10), o, giro, (nudillo[0] + e, nudillo[1] + s * 0.0075, zDedo + 0.006)))
        q.append(enMarco(caja('franja', (0, 0, 0), (MANO_FALANGE - 0.02, 0.0145, 0.004), m['plata'], 0.001), o, giro, (nudillo[0] + MANO_FALANGE / 2, nudillo[1], zDedo - 0.007)))
        dedo = piezaOrientada('dedo' + sufijo + letra, q, o + giro @ Vector(nudillo), giro, mano)
        # Punta: articulación, cuerpo y almohadilla de aluminio estriada en
        # la cara de dentro.
        articulacion = (nudillo[0] + MANO_FALANGE, nudillo[1], zDedo)
        r = []
        r.append(enMarco(cilindro('articulacionPunta', (0, 0, 0), 0.009, 0.028, m['articulacion'], eje='z', bisel=0.002), o, giro, articulacion))
        r.append(enMarco(caja('cuerpoPunta', (0, 0, 0), (0.036, 0.016, 0.026), m['negro'], 0.005), o, giro, (articulacion[0] + 0.016, articulacion[1] + k * 0.002, zDedo)))
        r.append(enMarco(caja('almohadilla', (0, 0, 0), (0.03, 0.006, 0.026), m['plata'], 0.002), o, giro, (articulacion[0] + MANO_PUNTA_X, nudillo[1] - k * (MANO_ALMOHADILLA - 0.003), zDedo)))
        for e in range(4):
            r.append(enMarco(caja('estria', (0, 0, 0), (0.003, 0.0015, 0.022), m['negroMate']), o, giro, (articulacion[0] + MANO_PUNTA_X - 0.011 + e * 0.0073, nudillo[1] - k * MANO_ALMOHADILLA, zDedo)))
        piezaOrientada('punta' + sufijo + letra, r, o + giro @ Vector(articulacion), giro, dedo)
    # Punto de agarre: entre las almohadillas con la mano cerrada sobre algo
    # fino (12 mm), donde se cuelga lo que coja.
    s = (MANO_NUDILLO_Y - MANO_ALMOHADILLA - 0.006) / MANO_FALANGE
    xAgarre = MANO_NUDILLO_X + MANO_FALANGE * math.sqrt(1 - s * s) + MANO_PUNTA_X
    agarre = bpy.data.objects.new('agarre' + sufijo, None)
    agarre.empty_display_type = 'SPHERE'
    agarre.empty_display_size = 0.01
    bpy.context.scene.collection.objects.link(agarre)
    agarre.matrix_world = Matrix.Translation(o + giro @ Vector((xAgarre, 0, 0))) @ giro.to_4x4()
    agarre.parent = mano
    agarre.matrix_parent_inverse = mano.matrix_world.inverted()
    return mano


def crearBrazo(m, lado, padre):
    sufijo = 'Izq' if lado > 0 else 'Der'
    y0 = lado * HOMBRO_Y
    z0 = HOMBRO_Z
    hombro = pieza('hombro' + sufijo, [
        esfera('hombro', (0, y0 + lado * 0.01, z0), 0.08, m['negro'], (1.0, 0.95, 0.9)),
        cilindro('ejeHombro', (0, y0 - lado * 0.065, z0), 0.06, 0.04, m['articulacion'], eje='y'),
    ], (0, y0, z0), padre)
    yb = y0 + lado * 0.04
    codo = (CODO[0], yb, CODO[1])
    brazo = pieza('brazo' + sufijo, [
        segmento('brazoSuperior', (0, yb, z0 - 0.05), codo, 0.08, 0.085, m['plata'], 0.035),
        segmento('brazoFranja', (0, yb, z0 - 0.09), (CODO[0], yb, CODO[1] + 0.08), 0.084, 0.03, m['blanco'], 0.01, -0.02),
        cilindro('codo', codo, 0.05, 0.095, m['articulacion'], eje='y', bisel=0.008),
    ] + [x for k in range(6) for x in perno('pernoCodo', (CODO[0] + math.cos(k * math.pi / 3) * 0.032, yb + lado * 0.0485, CODO[1] + math.sin(k * math.pi / 3) * 0.032), (0, lado, 0), m, 0.005, material='acero')]
      + filaRemaches((0.0, yb + lado * 0.043, z0 - 0.1), (CODO[0], yb + lado * 0.043, CODO[1] + 0.09), 5, (0, lado, 0), m, 0.0035)
      + [manguera('cableBrazo', [(-0.03, yb - lado * 0.035, z0 - 0.06), (-0.04, yb - lado * 0.04, (z0 + CODO[1]) / 2), (CODO[0] - 0.04, yb - lado * 0.035, CODO[1] + 0.03)], 0.005, m['negroMate'])], (0, yb, z0), hombro)
    munieca = (MUNIECA[0], yb, MUNIECA[1])
    antebrazo = pieza('codo' + sufijo, [
        segmento('antebrazo', codo, munieca, 0.075, 0.075, m['negro'], 0.03, -0.01),
        segmento('antebrazoTapa', (codo[0], yb + lado * 0.039, codo[2]), (munieca[0], yb + lado * 0.039, munieca[2]), 0.006, 0.045, m['gris'], 0.002, -0.04),
    ] + [x for f in (0.25, 0.75) for x in perno('pernoTapa', tuple(Vector(codo).lerp(Vector(munieca), f) + Vector((0, lado * 0.043, 0))), (0, lado, 0), m, 0.004, material='acero')], codo, brazo)
    crearPinza(m, sufijo, lado, Vector(munieca), (Vector(munieca) - Vector(codo)).normalized(), antebrazo)
    return hombro


def crearRobot():
    m = crearMateriales()
    base = crearBase(m)
    yr = BASE[1] / 2 + ANCHO_RUEDA / 2 + 0.015
    crearRueda(m, 'ruedaIzq', (0.0, yr, RADIO_RUEDA), RADIO_RUEDA, ANCHO_RUEDA, base)
    crearRueda(m, 'ruedaDer', (0.0, -yr, RADIO_RUEDA), RADIO_RUEDA, ANCHO_RUEDA, base)
    muslo = crearPierna(m, base)
    torso = crearTorso(m, muslo)
    crearCabeza(m, torso)
    crearBrazo(m, 1, torso)
    crearBrazo(m, -1, torso)
    placaSombra(0.8, 0.85, base, m)
    return base


# Render ------------------------------------------------------------------------

def prepararRender():
    escena = bpy.context.scene
    import addon_utils
    addon_utils.enable('cycles', default_set=True)
    preferencias = bpy.context.preferences.addons['cycles'].preferences
    for tipo in ('HIP', 'OPTIX', 'CUDA'):
        try:
            preferencias.compute_device_type = tipo
            preferencias.get_devices()
            if any(d.type == tipo for d in preferencias.devices):
                for dispositivo in preferencias.devices:
                    dispositivo.use = dispositivo.type == tipo
                escena.cycles.device = 'GPU'
                break
        except TypeError:
            continue
    try:
        escena.render.engine = 'CYCLES'
    except TypeError as error:
        print('SIN CYCLES', error)
    escena.cycles.samples = 128
    escena.cycles.use_denoising = True
    escena.render.resolution_x = 1200
    escena.render.resolution_y = 1200
    mundo = bpy.data.worlds.new('cielo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.5, 0.55, 0.6, 1)
    fondo.inputs['Strength'].default_value = 0.25
    escena.world = mundo
    # Suelo de baldosa gris y tres luces de estudio.
    caja('suelo', (0, 0, -0.01), (14, 14, 0.02), materialLiso('suelo', (0.3, 0.29, 0.27), 0.6))
    for nombre, posicion, energia, tamano in (('clave', (2.5, -2.0, 3.5), 900, 2.0), ('relleno', (-2.0, 2.5, 2.0), 300, 3.0), ('contra', (-2.5, -1.5, 3.0), 500, 1.5)):
        luz = bpy.data.lights.new(nombre, 'AREA')
        luz.energy = energia
        luz.size = tamano
        objeto = bpy.data.objects.new(nombre, luz)
        objeto.location = posicion
        objeto.rotation_euler = (Vector((0, 0, 0.9)) - Vector(posicion)).to_track_quat('-Z', 'Y').to_euler()
        escena.collection.objects.link(objeto)
    escena.view_settings.view_transform = 'AgX' if 'AgX' in [i.identifier for i in escena.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'
    escena.view_settings.exposure = -0.7
    for look in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        try:
            escena.view_settings.look = look
            break
        except TypeError:
            continue
    print('VISTA', escena.view_settings.view_transform, escena.view_settings.look, escena.view_settings.exposure)


def renderizar(carpeta):
    escena = bpy.context.scene
    vistas = [
        ('robot_frente', (2.6, -1.6, 1.4), (0, 0, 0.85), 50),
        ('robot_lado', (0.0, -3.3, 1.0), (0, 0, 0.85), 50),
        ('robot_atras', (-2.5, 1.7, 1.6), (0, 0, 0.85), 50),
        ('robot_cerca', (1.0, -0.6, 1.5), (0, 0, 1.25), 40),
    ]
    ojo = bpy.data.objects['ojoIzq'].matrix_world.translation
    vistas.append(('ojos_cerca', tuple(ojo + Vector((0.32, -0.2, 0.06))), tuple(ojo + Vector((0, -0.065, 0))), 60))
    mano = bpy.data.objects['muniecaDer'].matrix_world.translation
    vistas.append(('pinza_abierta', tuple(mano + Vector((0.32, -0.22, 0.12))), tuple(mano + Vector((0.07, 0, -0.02))), 60))
    for nombre, posicion, objetivo, lente in vistas:
        datos = bpy.data.cameras.new(nombre)
        datos.lens = lente
        camara = bpy.data.objects.new(nombre, datos)
        camara.location = posicion
        camara.rotation_euler = (Vector(objetivo) - Vector(posicion)).to_track_quat('-Z', 'Y').to_euler()
        escena.collection.objects.link(camara)
        escena.camera = camara
        escena.render.filepath = os.path.join(carpeta, nombre + '.png')
        bpy.ops.render.render(write_still=True)


# Exportar al juego ---------------------------------------------------------------

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GLB_JUEGO = os.path.join(RAIZ, 'assets', 'almacen', 'robot.glb')


def exportarJuego(ruta):
    """Exporta `ruta` (.glb) y, al lado, robot_piezas.lua: cada pieza con su
    padre y su matriz de reposo respecto a él (filas, ejes del juego: x
    delante, y izquierda, z arriba, metros). En el .glb cada pieza va en el
    origen con la malla en sus ejes locales: el juego la coloca
    (almacen/robots/robot.lua). Los vacíos (`agarreIzq`/`Der`) solo van en la
    lista."""
    # Las matrices de lo último que se creó (la garra derecha y su punto de
    # agarre) no están calculadas hasta que se actualiza la escena: sin esto
    # salían mal en el .lua (17-nov: la garra derecha no llegaba a nada).
    bpy.context.view_layer.update()
    orden = []

    def visitar(objeto):
        if objeto.name.startswith('vista'):
            return  # muestras que solo se ven en Blender (vistaSiglas)
        orden.append(objeto)
        for hija in sorted(objeto.children, key=lambda o: o.name):
            visitar(hija)

    visitar(bpy.data.objects['robot'])
    lineas = []
    for objeto in orden:
        padre = objeto.parent.name if objeto.parent else None
        local = objeto.parent.matrix_world.inverted() @ objeto.matrix_world if objeto.parent else objeto.matrix_world.copy()
        filas = ', '.join('%.6f' % local[i][j] for i in range(4) for j in range(4))
        lineas.append("    { nombre = '%s', padre = %s, malla = %s, matriz = { %s } }," % (
            objeto.name, ("'%s'" % padre) if padre else 'nil', 'true' if objeto.type == 'MESH' else 'false', filas))
    # robot.glb -> robot_piezas.lua; robot_pesado.glb -> robot_pesado_piezas.lua
    rutaPiezas = os.path.splitext(ruta)[0] + '_piezas.lua'
    with open(rutaPiezas, 'w') as archivo:
        archivo.write('-- Piezas de un robot del almacén (tools/blender/robot_almacen.py o\n')
        archivo.write('-- robot_pesado.py, con --glb), de\n')
        archivo.write('-- la raíz a las puntas: padre y matriz de reposo respecto a él (por filas,\n')
        archivo.write('-- ejes del juego, metros). `malla`: si tiene malla en robot.glb.\n')
        archivo.write('return {\n' + '\n'.join(lineas) + '\n}\n')
    # Cada malla en el origen, con sus vértices en sus ejes locales.
    for objeto in orden:
        objeto.parent = None
    for objeto in orden:
        objeto.matrix_world = Matrix.Identity(4)
    nombres = {o.name for o in orden}
    for objeto in list(bpy.data.objects):
        if objeto.type != 'MESH' or objeto.name not in nombres:
            bpy.data.objects.remove(objeto)
    for objeto in bpy.data.objects:
        if objeto.name not in ('logoPecho', 'sombraSuelo'):  # placas con su UV de 0 a 1
            uvCaja(objeto)
    opciones = dict(filepath=ruta, export_format='GLB', use_selection=False, export_apply=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
    except TypeError:
        bpy.ops.export_scene.gltf(**opciones)
    print('EXPORTADO', ruta, len(orden), 'piezas')


def uvCaja(objeto):
    """UV por proyección de caja (3DreamEngine las necesita para las tangentes)."""
    malla = objeto.data
    bm = bmesh.new()
    bm.from_mesh(malla)
    capa = bm.loops.layers.uv.verify()
    for cara in bm.faces:
        n = cara.normal
        ejes = (abs(n.x), abs(n.y), abs(n.z))
        d = ejes.index(max(ejes))
        for bucle in cara.loops:
            p = bucle.vert.co
            bucle[capa].uv = (p.y, p.z) if d == 0 else ((p.x, p.z) if d == 1 else (p.x, p.y))
    bm.to_mesh(malla)
    bm.free()


def principal():
    args = argumentos()
    rutaGlb = None
    if '--glb' in args:
        k = args.index('--glb')
        rutaGlb = args[k + 1] if len(args) > k + 1 else GLB_JUEGO
        del args[k:k + 2]
    salida = args[0] if args else '/tmp/robot_almacen.blend'
    limpiarEscena()
    crearRobot()
    if rutaGlb:
        exportarJuego(rutaGlb)
        return
    materialesReales({k: bpy.data.materials[n] for k, n in (('blanco', 'robotBlanco'), ('negro', 'robotNegro'), ('plata', 'robotPlata'), ('acero', 'robotAcero'), ('goma', 'robotGoma'))})
    prepararRender()
    bpy.ops.wm.save_as_mainfile(filepath=salida)
    if len(args) > 1:
        renderizar(args[1])


principal()

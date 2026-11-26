# Objetos del almacén que el robot sabe manejar y los muebles donde los coge y
# los deja. Se corre sin ventana:
#
#     blender -b --factory-startup --python tools/blender/objetos_almacen.py -- \
#         [salida.blend] [carpeta de renders]
#
# Al juego (assets/almacen/objetos.glb y objetos_datos.lua):
#
#     blender -b --factory-startup --python tools/blender/objetos_almacen.py -- --glb
#
# Cada objeto es una malla con el origen en el suelo bajo su centro. Su +x es
# hacia donde mira el robot cuando lo coge: el frente del objeto está en -x.
#
#   cajaRobot      caja de plástico apilable con tapa y dos orejetas
#                  amarillas a los lados: los puntos de agarre de las dos
#                  pinzas (se pinzan por su grosor, 12 mm).
#   cajaMunicion   caja de munición metálica con asa arriba: un punto de
#                  agarre en el asa, para una pinza.
#   mesaRecepcion  mesa de 0,9 m con el tablero volado 25 cm por delante de
#                  las patas: la base del robot entra debajo y llega más cerca.
#                  Tres huecos donde se apoyan las cosas.
#   estanteriaRobot  estantería en voladizo (puntales solo detrás): baldas a
#                  0,85 y 1,30 m (y una alta a 1,75), tres huecos por balda.
#   rackRobot      rack largo en voladizo (5,4 m) para el anexo de
#                  suministros: puntales azules detrás, brazos y largueros
#                  naranjas, baldas a 0,85 y 1,30 m con ocho huecos cada una
#                  (16 por rack), marcados en el canto con su número.
#
# Los datos para el juego (medidas, peso, puntos de agarre, huecos y cajas de
# colisión) salen de las mismas constantes de aquí: objetos_datos.lua.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GLB = os.path.join(RAIZ, 'assets', 'almacen', 'objetos.glb')
DATOS = os.path.join(RAIZ, 'assets', 'almacen', 'objetos_datos.lua')

# Caja de plástico: fondo (x), ancho (y), alto (z).
CAJA = (0.30, 0.40, 0.24)
OREJETA = (0.08, 0.012, 0.05)  # placa de agarre (pinzada por su grosor y)
OREJETA_X = -0.10  # centro de la placa, hacia el frente
OREJETA_Z = 0.14
OREJETA_SEPARACION = 0.035  # de la pared al centro de la placa
# Caja de munición.
MUNICION = (0.28, 0.14, 0.18)
ASA_Z = 0.225  # centro de la barra del asa
ASA_LARGO = 0.13
ASA_GROSOR = 0.012
# Mesa de recepción.
MESA = (0.70, 1.50, 0.90)  # fondo, ancho, alto del tablero
MESA_VUELO = 0.25  # tablero por delante de las patas delanteras
MESA_HUECOS_Y = (-0.45, 0.0, 0.45)
# Estantería en voladizo.
ESTANTE = (0.50, 1.96)  # fondo y ancho de las baldas
ESTANTE_BALDAS = (0.85, 1.30, 1.75)
ESTANTE_ALTO = 1.95
ESTANTE_HUECOS_Y = (-0.62, 0.0, 0.62)
ESTANTE_NIVELES_HUECOS = (0.85, 1.30)
# Rack del robot (anexo de suministros): igual que la estantería pero largo.
# Depósito del misil (fábrica): banco de acero con dos zonas, DINERO y
# PETRÓLEO, cuatro huecos cada una; el robot deja ahí lo que pide el misil.
DEPOSITO = (0.70, 4.80, 0.90)  # fondo, ancho, alto del tablero
# Tres zonas de 1,6 m (2026-11-17: cada misil, una paca, una caja de metal y
# una garrafa): (recurso, rótulo, centro en y); dos huecos en cada una.
DEPOSITO_ZONAS = (('dinero', 'DINERO', 1.6), ('metal', 'METAL', 0.0), ('petroleo', 'PETRÓLEO', -1.6))
DEPOSITO_HUECO_Y = 0.38  # de cada hueco al centro de su zona
DEPOSITO_PANEL = 0.75  # alto del panel trasero sobre el tablero
RACK = (0.50, 5.40)  # fondo y ancho
RACK_BALDAS = (0.85, 1.30, 1.75)
RACK_ALTO = 1.95
RACK_HUECOS_Y = tuple(-2.17 + k * 0.62 for k in range(8))
RACK_NIVELES_HUECOS = (0.85, 1.30)
RACK_PUNTALES_Y = (-2.67, -1.335, 0.0, 1.335, 2.67)


def argumentos():
    return sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []


def limpiar():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def principled(material):
    return next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def material(nombre, color, rugosidad, metalico=0.0):
    m = bpy.data.materials.get(nombre)
    if m:
        return m
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    b = principled(m)
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rugosidad
    b.inputs['Metallic'].default_value = metalico
    return m


def materiales():
    return {
        'plastico': material('objPlasticoAzul', (0.09, 0.2, 0.36), 0.55),
        'tapa': material('objPlasticoTapa', (0.05, 0.11, 0.2), 0.5),
        'etiqueta': material('objEtiqueta', (0.85, 0.85, 0.8), 0.6),
        'tinta': material('objTinta', (0.02, 0.02, 0.02), 0.6),
        'agarre': material('objAgarreAmarillo', (0.95, 0.68, 0.02), 0.4, 0.2),
        'acero': material('objAcero', (0.55, 0.56, 0.58), 0.35, 1.0),
        'oliva': material('objOliva', (0.16, 0.18, 0.09), 0.55, 0.3),
        'pintura': material('objLetraAmarilla', (0.85, 0.7, 0.1), 0.6),
        'tablero': material('objTablero', (0.62, 0.6, 0.55), 0.5),
        'gris': material('objGrisMueble', (0.22, 0.23, 0.25), 0.45, 0.5),
        'azul': material('objAzulPuntal', (0.05, 0.2, 0.55), 0.45, 0.4),
        'balda': material('objBaldaGalvanizada', (0.6, 0.62, 0.64), 0.4, 0.9),
        'goma': material('objGoma', (0.03, 0.03, 0.03), 0.8),
        'naranja': material('objNaranjaRack', (0.85, 0.32, 0.04), 0.45, 0.3),
        # Suministros: billetes, oro de la faja, cartón, cinta, madera oliva.
        'billete': material('objBillete', (0.42, 0.55, 0.38), 0.7),
        'billeteClaro': material('objBilleteClaro', (0.78, 0.8, 0.68), 0.7),
        'oro': material('objOro', (0.9, 0.66, 0.16), 0.3, 1.0),
        'fleje': material('objFleje', (0.08, 0.08, 0.09), 0.5, 0.6),
        'carton': material('objCarton', (0.55, 0.38, 0.2), 0.85),
        'cinta': material('objCinta', (0.72, 0.6, 0.4), 0.5),
        'verdeEtiqueta': material('objVerdeEtiqueta', (0.08, 0.4, 0.12), 0.6),
        'madera': material('objMaderaOliva', (0.24, 0.26, 0.14), 0.75),
        'maderaOscura': material('objMaderaOscura', (0.16, 0.17, 0.09), 0.8),
        'bidon': material('objBidonAzul', (0.05, 0.14, 0.38), 0.4, 0.5),
        'blancoLetra': material('objLetraBlanca', (0.9, 0.9, 0.88), 0.6),
        'verdePanel': material('objVerdePanel', (0.03, 0.3, 0.1), 0.5),
        'negroPanel': material('objNegroPanel', (0.03, 0.03, 0.035), 0.45),
        'chapa': material('objChapaLagrimada', (0.42, 0.43, 0.45), 0.35, 0.9),
        'rojoGarrafa': material('objRojoGarrafa', (0.55, 0.06, 0.03), 0.4, 0.3),
        'aceroOscuro': material('objAceroOscuro', (0.2, 0.21, 0.22), 0.4, 0.8),
    }


def objetoDe(nombre, bm, mat):
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    malla.materials.append(mat)
    objeto = bpy.data.objects.new(nombre, malla)
    bpy.context.scene.collection.objects.link(objeto)
    return objeto


def caja(nombre, centro, tamano, mat, bisel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tamano), verts=bm.verts)
    if bisel > 0:
        bisel = min(bisel, min(tamano) * 0.45)
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bisel, segments=2, affect='EDGES', profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, mat)


def cilindro(nombre, centro, radio, largo, mat, eje='z', lados=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=radio, radius2=radio, depth=largo)
    if eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, mat)


def unir(objetos, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objetos:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    bpy.ops.object.join()
    objeto = bpy.context.view_layer.objects.active
    objeto.name = nombre
    objeto.data.name = nombre
    return objeto


def uvCaja(objeto):
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    capa = bm.loops.layers.uv.verify()
    for cara in bm.faces:
        n = cara.normal
        ejes = (abs(n.x), abs(n.y), abs(n.z))
        d = ejes.index(max(ejes))
        for bucle in cara.loops:
            p = bucle.vert.co
            bucle[capa].uv = (p.y, p.z) if d == 0 else ((p.x, p.z) if d == 1 else (p.x, p.y))
    bm.to_mesh(objeto.data)
    bm.free()


# Objetos -----------------------------------------------------------------------


def crearCajaRobot(m):
    fx, fy, fz = CAJA
    p = []
    # Cuerpo un poco más estrecho abajo (apilable) y con nervios verticales.
    p.append(caja('cuerpo', (0, 0, 0.02 + (fz - 0.05) / 2), (fx - 0.012, fy - 0.012, fz - 0.05), m['plastico'], 0.008))
    p.append(caja('pie', (0, 0, 0.012), (fx - 0.03, fy - 0.03, 0.024), m['tapa'], 0.004))
    for sx in (-1, 1):
        for k in range(5):
            y = -fy / 2 + 0.06 + k * (fy - 0.12) / 4
            p.append(caja('nervio', (sx * (fx / 2 - 0.004), y, fz / 2 - 0.01), (0.008, 0.012, fz - 0.07), m['plastico'], 0.002))
    # Tapa con borde y asas de tapa.
    p.append(caja('tapa', (0, 0, fz - 0.015), (fx + 0.006, fy + 0.006, 0.03), m['tapa'], 0.006))
    p.append(caja('tapaCentro', (0, 0, fz + 0.002), (fx - 0.08, fy - 0.08, 0.008), m['tapa'], 0.003))
    # Etiqueta delante (en -x) con un código de barras.
    p.append(caja('etiqueta', (-fx / 2 - 0.002, 0, 0.12), (0.003, 0.16, 0.08), m['etiqueta']))
    for k in range(14):
        ancho = 0.002 + (k * 7 % 3) * 0.0015
        p.append(caja('barra', (-fx / 2 - 0.004, -0.06 + k * 0.0085, 0.11), (0.002, ancho, 0.04), m['tinta']))
    # Orejetas de agarre: placa amarilla separada de la pared por un tope
    # al fondo de la placa (la pinza entra desde delante sin tocarlo).
    for sy in (-1, 1):
        yPlaca = sy * (fy / 2 + OREJETA_SEPARACION)
        p.append(caja('orejeta', (OREJETA_X, yPlaca, OREJETA_Z), OREJETA, m['agarre'], 0.003))
        xTope = OREJETA_X + OREJETA[0] / 2 - 0.008
        p.append(caja('tope', (xTope, sy * (fy / 2 + OREJETA_SEPARACION / 2), OREJETA_Z), (0.016, OREJETA_SEPARACION, 0.03), m['agarre'], 0.002))
        p.append(caja('placaBase', (OREJETA_X + 0.01, sy * (fy / 2 + 0.003), OREJETA_Z), (0.1, 0.006, 0.07), m['agarre'], 0.002))
    return unir(p, 'cajaRobot')


def letras(contenido, tamano, mat, centro, giro):
    """Texto en malla (para el .glb): centrado en `centro`, girado `giro`."""
    curva = bpy.data.curves.new('letras', 'FONT')
    curva.body = contenido
    curva.size = tamano
    curva.align_x = 'CENTER'
    curva.align_y = 'CENTER'
    curva.extrude = 0.0015
    objeto = bpy.data.objects.new('letras', curva)
    objeto.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(objeto)
    objeto.location = centro
    objeto.rotation_euler = giro
    bpy.ops.object.select_all(action='DESELECT')
    objeto.select_set(True)
    bpy.context.view_layer.objects.active = objeto
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objeto


# Delante (-x) mirando hacia fuera, y encima mirando arriba.
FRENTE = (math.pi / 2, 0, -math.pi / 2)


def orejetas(m, p, fy):
    """Las dos orejetas amarillas de agarre, como las de la caja de plástico."""
    for sy in (-1, 1):
        yPlaca = sy * (fy / 2 + OREJETA_SEPARACION)
        p.append(caja('orejeta', (OREJETA_X, yPlaca, OREJETA_Z), OREJETA, m['agarre'], 0.003))
        xTope = OREJETA_X + OREJETA[0] / 2 - 0.008
        p.append(caja('tope', (xTope, sy * (fy / 2 + OREJETA_SEPARACION / 2), OREJETA_Z), (0.016, OREJETA_SEPARACION, 0.03), m['agarre'], 0.002))
        p.append(caja('placaBase', (OREJETA_X + 0.01, sy * (fy / 2 + 0.003), OREJETA_Z), (0.1, 0.006, 0.07), m['agarre'], 0.002))


def crearPacaDinero(m):
    """Paca de 200 billetes de banco: fajos apilados (capas de billete verde
    y canto claro), dos flejes negros alrededor, faja dorada y placa delante
    con «$ 200». Las orejetas van en un bastidor de acero."""
    fx, fy, fz = CAJA
    p = []
    capas = 8
    for k in range(capas):
        z0 = 0.01 + k * (fz - 0.02) / capas
        alto = (fz - 0.02) / capas
        p.append(caja('fajo', (0, 0, z0 + alto / 2), (fx - 0.01, fy - 0.01, alto - 0.003), m['billete'], 0.004))
        p.append(caja('canto', (-fx / 2 + 0.003, 0, z0 + alto / 2), (0.006, fy - 0.03, alto * 0.55), m['billeteClaro'], 0.001))
    for y in (-fy * 0.28, fy * 0.28):
        p.append(caja('flejeV', (0, y, fz / 2), (fx + 0.006, 0.02, fz + 0.006), m['fleje'], 0.002))
    p.append(caja('faja', (0, 0, fz * 0.55), (fx + 0.008, fy + 0.008, 0.035), m['oro'], 0.003))
    p.append(caja('placa', (-fx / 2 - 0.006, 0, 0.09), (0.004, 0.17, 0.07), m['oro'], 0.002))
    p.append(letras('$ 200', 0.045, m['tinta'], (-fx / 2 - 0.009, 0, 0.09), FRENTE))
    p.append(letras('$', 0.12, m['oro'], (0, 0, fz + 0.004), (0, 0, -math.pi / 2)))
    # Bastidor de acero de las orejetas (abraza la paca por los lados).
    for sy in (-1, 1):
        p.append(caja('bastidor', (OREJETA_X + 0.03, sy * (fy / 2 + 0.002), OREJETA_Z), (0.16, 0.004, 0.09), m['acero'], 0.002))
    orejetas(m, p, fy)
    return unir(p, 'pacaDinero')


def crearCajaComida(m):
    """Caja de cartón de 20 raciones: cinta de embalar arriba, etiqueta verde
    delante con «COMIDA 20» y las orejetas en un cinturón de plástico."""
    fx, fy, fz = CAJA
    p = []
    p.append(caja('carton', (0, 0, fz / 2), (fx - 0.01, fy - 0.01, fz - 0.004), m['carton'], 0.006))
    p.append(caja('cinta', (0, 0, fz - 0.001), (fx + 0.002, 0.05, 0.006), m['cinta'], 0.001))
    p.append(caja('cintaFrente', (-fx / 2 + 0.001, 0, fz - 0.03), (0.006, 0.05, 0.06), m['cinta'], 0.001))
    p.append(caja('etiqueta', (-fx / 2 - 0.002, 0, 0.1), (0.004, 0.24, 0.1), m['verdeEtiqueta'], 0.002))
    p.append(letras('COMIDA', 0.04, m['blancoLetra'], (-fx / 2 - 0.005, 0, 0.115), FRENTE))
    p.append(letras('20 raciones', 0.022, m['blancoLetra'], (-fx / 2 - 0.005, 0, 0.073), FRENTE))
    p.append(caja('cinturon', (0, 0, OREJETA_Z), (fx + 0.004, fy + 0.004, 0.03), m['tapa'], 0.003))
    orejetas(m, p, fy)
    return unir(p, 'cajaComida')


def crearCajaObuses(m):
    """Caja de madera oliva de munición de tanque (100 obuses): tablas con
    juntas, cantoneras de acero, franja amarilla de munición y letras
    estarcidas «OBUSES 100» delante."""
    fx, fy, fz = CAJA
    p = []
    p.append(caja('cuerpo', (0, 0, fz / 2), (fx - 0.01, fy - 0.01, fz - 0.004), m['madera'], 0.004))
    for k in range(1, 4):
        z = k * fz / 4
        p.append(caja('junta', (0, 0, z), (fx - 0.006, fy - 0.006, 0.004), m['maderaOscura']))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(caja('cantonera', (sx * (fx / 2 - 0.01), sy * (fy / 2 - 0.01), fz / 2), (0.03, 0.03, fz + 0.004), m['acero'], 0.003))
    p.append(caja('franja', (-fx / 2 - 0.002, 0, fz - 0.04), (0.004, fy - 0.04, 0.025), m['pintura']))
    p.append(letras('OBUSES', 0.045, m['pintura'], (-fx / 2 - 0.005, 0, 0.13), FRENTE))
    p.append(letras('100', 0.04, m['pintura'], (-fx / 2 - 0.005, 0, 0.08), FRENTE))
    orejetas(m, p, fy)
    return unir(p, 'cajaObuses')


def crearCajaMetal(m):
    """Caja de acero abierta con 10 lingotes de metal (dos capas de cinco,
    cruzadas como se apilan de verdad): cantoneras, etiqueta gris delante
    con «METAL 10» y las orejetas en un cinturón de plástico."""
    fx, fy, fz = CAJA
    pared = 0.012
    gris = material('aceroCaja', (0.30, 0.31, 0.32), 0.45, 0.8)
    lingote = material('lingote', (0.72, 0.73, 0.75), 0.35, 0.6)
    p = []
    # Fondo y cuatro paredes (caja abierta: se ven los lingotes).
    p.append(caja('fondo', (0, 0, 0.01), (fx - 0.004, fy - 0.004, 0.02), gris, 0.004))
    for sx in (-1, 1):
        p.append(caja('pared', (sx * (fx / 2 - pared / 2), 0, fz / 2), (pared, fy - 0.004, fz - 0.004), gris, 0.003))
    for sy in (-1, 1):
        p.append(caja('pared', (0, sy * (fy / 2 - pared / 2), fz / 2), (fx - 0.004, pared, fz - 0.004), gris, 0.003))
        p.append(caja('borde', (0, sy * (fy / 2 - pared / 2), fz - 0.006), (fx + 0.004, pared + 0.008, 0.012), m['aceroOscuro'], 0.003))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(caja('cantonera', (sx * (fx / 2 - 0.012), sy * (fy / 2 - 0.012), fz / 2), (0.028, 0.028, fz + 0.004), m['aceroOscuro'], 0.004))
    # Lingotes: troncos de pirámide (más estrechos arriba), 0,25 x 0,055 x 0,05.
    def lingoteEn(x, y, z, giro):
        bm = bmesh.new()
        largo, ancho, alto = 0.25, 0.055, 0.05
        abajo = [(-largo / 2, -ancho / 2), (largo / 2, -ancho / 2), (largo / 2, ancho / 2), (-largo / 2, ancho / 2)]
        vs = [bm.verts.new((px, py, 0)) for px, py in abajo]
        vs += [bm.verts.new((px * 0.88, py * 0.75, alto)) for px, py in abajo]
        bm.faces.new(vs[3::-1])
        bm.faces.new(vs[4:])
        for k in range(4):
            bm.faces.new((vs[k], vs[(k + 1) % 4], vs[4 + (k + 1) % 4], vs[4 + k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.004, segments=2, affect='EDGES', profile=0.5)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(giro, 3, 'Z'))
        bmesh.ops.translate(bm, vec=Vector((x, y, z)), verts=bm.verts)
        return objetoDe('lingote', bm, lingote)
    # Falso fondo (los lingotes quedan arriba, a la vista) y dos capas: la de
    # abajo a lo largo de y, la de arriba cruzada, a lo largo de x.
    p.append(caja('falsoFondo', (0, 0, 0.065), (fx - 2 * pared - 0.004, fy - 2 * pared - 0.004, 0.09), gris, 0.004))
    for k in range(5):
        p.append(lingoteEn(-0.11 + k * 0.055, 0, 0.11, math.pi / 2))
    for k in range(5):
        p.append(lingoteEn(0, -0.13 + k * 0.065, 0.16, 0))
    p.append(caja('etiqueta', (-fx / 2 - 0.002, 0, 0.1), (0.004, 0.24, 0.1), m['gris'], 0.002))
    p.append(letras('METAL', 0.04, m['blancoLetra'], (-fx / 2 - 0.005, 0, 0.115), FRENTE))
    p.append(letras('10 lingotes', 0.022, m['blancoLetra'], (-fx / 2 - 0.005, 0, 0.073), FRENTE))
    # Cinturón de las orejetas: cuatro tiras por fuera (la caja va abierta).
    for sx in (-1, 1):
        p.append(caja('cinturon', (sx * (fx / 2 + 0.001), 0, OREJETA_Z), (0.006, fy + 0.004, 0.03), m['tapa'], 0.002))
    for sy in (-1, 1):
        p.append(caja('cinturon', (0, sy * (fy / 2 + 0.001), OREJETA_Z), (fx + 0.004, 0.006, 0.03), m['tapa'], 0.002))
    orejetas(m, p, fy)
    return unir(p, 'cajaMetal')


# Garrafa de petróleo de 10 l (tipo jerrycan): se lleva con una mano por el
# asa de arriba (a lo largo de x, como la caja de munición).
GARRAFA = (0.28, 0.14, 0.33)  # largo x, grueso y, alto
GARRAFA_ASA_Z = 0.37


def crearGarrafa(m):
    """Garrafa roja de 10 l: cuerpo con aristas redondeadas y la X
    estampada en los costados, asa triple arriba (la central es la de
    agarre, amarilla), boca con tapón delante y «PETRÓLEO 10 l»."""
    fx, fy, fz = GARRAFA
    p = [caja('cuerpo', (0, 0, fz / 2), (fx, fy, fz), m['rojoGarrafa'], 0.02)]
    # X estampada en cada costado (dos barras en diagonal) y su marco.
    for sy in (-1, 1):
        ys = sy * (fy / 2 + 0.003)
        for giro in (1, -1):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            largo = math.hypot(fx - 0.08, fz - 0.1)
            bmesh.ops.scale(bm, vec=Vector((largo, 0.008, 0.025)), verts=bm.verts)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(giro * math.atan2(fz - 0.1, fx - 0.08), 3, 'Y'))
            bmesh.ops.translate(bm, vec=Vector((0, ys, fz / 2)), verts=bm.verts)
            p.append(objetoDe('xEstampada', bm, m['rojoGarrafa']))
        p.append(caja('marco', (0, ys, fz / 2), (fx - 0.04, 0.006, fz - 0.05), m['rojoGarrafa'], 0.01))
    # Asa triple: tres barras a lo largo de x con patas; la del centro, amarilla.
    for k, y in enumerate((-0.04, 0.0, 0.04)):
        for x in (-0.07, 0.07):
            p.append(caja('pataAsa', (x, y, (fz + GARRAFA_ASA_Z) / 2), (0.014, 0.014, GARRAFA_ASA_Z - fz + 0.01), m['rojoGarrafa'], 0.003))
        mat = m['agarre'] if k == 1 else m['rojoGarrafa']
        p.append(cilindro('asa', (0, y, GARRAFA_ASA_Z), ASA_GROSOR / 2 + 0.002, 0.15, mat, eje='x', lados=12))
    # Boca inclinada con tapón y su cierre, en la esquina delantera.
    p.append(cilindro('boca', (-fx / 2 + 0.04, 0, fz + 0.02), 0.022, 0.05, m['rojoGarrafa'], lados=16))
    p.append(cilindro('tapon', (-fx / 2 + 0.04, 0, fz + 0.05), 0.026, 0.02, m['aceroOscuro'], lados=16))
    p.append(caja('palanca', (-fx / 2 + 0.07, 0, fz + 0.05), (0.04, 0.012, 0.008), m['aceroOscuro']))
    # Etiqueta delante.
    p.append(caja('etiqueta', (-fx / 2 - 0.002, 0, fz * 0.5), (0.004, fy - 0.03, 0.11), m['etiqueta'], 0.002))
    p.append(letras('PETRÓLEO', 0.022, m['tinta'], (-fx / 2 - 0.005, 0, fz * 0.5 + 0.022), FRENTE))
    p.append(letras('10 L', 0.03, m['tinta'], (-fx / 2 - 0.005, 0, fz * 0.5 - 0.022), FRENTE))
    return unir(p, 'garrafaPetroleo')


def crearCajaCaudales(m):
    """Caja de caudales abierta (bandeja honda de acero) para llevar el
    dinero justo del rack al depósito: mismo tamaño y orejetas que las
    pacas, fondo verde de fieltro, refuerzos en las esquinas y placa
    «DINERO» delante."""
    fx, fy, fz = CAJA
    alto = 0.2
    g = 0.012
    p = [caja('fondo', (0, 0, 0.01), (fx, fy, 0.02), m['aceroOscuro'], 0.004)]
    p.append(caja('fieltro', (0, 0, 0.022), (fx - 2 * g, fy - 2 * g, 0.004), m['verdePanel']))
    for sx in (-1, 1):
        p.append(caja('paredX', (sx * (fx / 2 - g / 2), 0, alto / 2), (g, fy, alto), m['aceroOscuro'], 0.003))
    for sy in (-1, 1):
        p.append(caja('paredY', (0, sy * (fy / 2 - g / 2), alto / 2), (fx, g, alto), m['aceroOscuro'], 0.003))
        p.append(caja('bordeY', (0, sy * (fy / 2 - g / 2), alto), (fx + 0.004, g + 0.008, 0.012), m['acero'], 0.003))
    for sx in (-1, 1):
        p.append(caja('bordeX', (sx * (fx / 2 - g / 2), 0, alto), (g + 0.008, fy + 0.004, 0.012), m['acero'], 0.003))
        for sy in (-1, 1):
            p.append(caja('esquina', (sx * (fx / 2 - 0.004), sy * (fy / 2 - 0.004), alto / 2), (0.03, 0.03, alto + 0.006), m['acero'], 0.004))
    p.append(caja('placa', (-fx / 2 - 0.004, 0, 0.1), (0.004, 0.2, 0.06), m['oro'], 0.002))
    p.append(letras('DINERO', 0.035, m['tinta'], (-fx / 2 - 0.007, 0, 0.1), FRENTE))
    orejetas(m, p, fy)
    return unir(p, 'cajaCaudales')


BIDON_RADIO = 0.29
BIDON_ALTO = 0.88


def crearBidonPetroleo(m):
    """Bidón de 200 l de petróleo, azul con aros y «PETRÓLEO»: llega al patio
    pero no es del robot (pesa demasiado)."""
    p = [cilindro('bidon', (0, 0, BIDON_ALTO / 2), BIDON_RADIO, BIDON_ALTO, m['bidon'], lados=32)]
    for z in (0.02, BIDON_ALTO * 0.33, BIDON_ALTO * 0.66, BIDON_ALTO - 0.02):
        p.append(cilindro('aro', (0, 0, z), BIDON_RADIO + 0.008, 0.018, m['bidon'], lados=32))
    p.append(cilindro('tapon', (0.15, 0, BIDON_ALTO + 0.008), 0.03, 0.016, m['acero']))
    p.append(letras('PETRÓLEO', 0.08, m['blancoLetra'], (-BIDON_RADIO - 0.006, 0, BIDON_ALTO * 0.5), FRENTE))
    return unir(p, 'bidonPetroleo')


def crearCajaMunicion(m):
    fx, fy, fz = MUNICION
    p = []
    p.append(caja('cuerpo', (0, 0, fz / 2 - 0.01), (fx, fy, fz - 0.02), m['oliva'], 0.006))
    p.append(caja('tapa', (0, 0, fz - 0.012), (fx + 0.008, fy + 0.008, 0.025), m['oliva'], 0.004))
    # Refuerzos laterales estampados.
    for sy in (-1, 1):
        for k in (-1, 1):
            p.append(caja('estampado', (k * 0.08, sy * (fy / 2 + 0.002), fz / 2 - 0.01), (0.07, 0.004, fz - 0.06), m['oliva'], 0.003))
    # Cierre de palanca delante.
    p.append(caja('cierre', (-fx / 2 - 0.008, 0, fz - 0.03), (0.016, 0.05, 0.05), m['acero'], 0.003))
    # Rótulo amarillo en el costado.
    for k in range(6):
        p.append(caja('letra', (-0.07 + k * 0.028, -fy / 2 - 0.005, fz / 2 + 0.02), (0.018, 0.003, 0.03), m['pintura']))
    # Asa levantada: barra a lo largo de x con dos patas.
    for k in (-1, 1):
        x = k * ASA_LARGO / 2
        p.append(caja('pataAsa', (x, 0, (fz + ASA_Z) / 2), (0.01, 0.01, ASA_Z - fz + 0.01), m['acero']))
        p.append(caja('bisagra', (x, 0, fz + 0.004), (0.03, 0.03, 0.01), m['acero'], 0.002))
    p.append(cilindro('asa', (0, 0, ASA_Z), ASA_GROSOR / 2 + 0.002, ASA_LARGO + 0.01, m['agarre'], eje='x', lados=12))
    return unir(p, 'cajaMunicion')


def crearMesa(m):
    fx, fy, alto = MESA
    p = []
    p.append(caja('tablero', (0, 0, alto - 0.02), (fx, fy, 0.04), m['tablero'], 0.004))
    p.append(caja('canto', (-fx / 2 + 0.005, 0, alto - 0.02), (0.012, fy + 0.004, 0.044), m['gris'], 0.002))
    xDelante = -fx / 2 + MESA_VUELO
    xDetras = fx / 2 - 0.05
    for x in (xDelante, xDetras):
        for sy in (-1, 1):
            p.append(caja('pata', (x, sy * (fy / 2 - 0.05), (alto - 0.04) / 2), (0.05, 0.05, alto - 0.04), m['gris'], 0.004))
            p.append(caja('nivelador', (x, sy * (fy / 2 - 0.05), 0.01), (0.07, 0.07, 0.02), m['goma']))
        p.append(caja('larguero', (x, 0, alto - 0.07), (0.04, fy - 0.1, 0.06), m['gris'], 0.003))
    for sy in (-1, 1):
        p.append(caja('travesano', ((xDelante + xDetras) / 2, sy * (fy / 2 - 0.05), alto - 0.07), (xDetras - xDelante, 0.04, 0.06), m['gris'], 0.003))
    # Balda baja (no sale por delante de las patas).
    p.append(caja('baldaBaja', ((xDelante + xDetras) / 2, 0, 0.16), (xDetras - xDelante + 0.04, fy - 0.1, 0.02), m['gris']))
    # Raya amarilla en el canto: «aquí se recoge».
    p.append(caja('raya', (-fx / 2 - 0.002, 0, alto - 0.02), (0.003, fy * 0.9, 0.012), m['agarre']))
    return unir(p, 'mesaRecepcion')


def crearEstanteria(m):
    fx, fy = ESTANTE
    p = []
    xPuntal = fx / 2 - 0.04
    puntalesY = (-fy / 2 + 0.03, 0.0, fy / 2 - 0.03)
    for y in puntalesY:
        p.append(caja('puntal', (xPuntal, y, ESTANTE_ALTO / 2), (0.07, 0.06, ESTANTE_ALTO), m['azul'], 0.006))
        # Pie hacia atrás (delante queda libre para la base del robot).
        p.append(caja('pie', (xPuntal + 0.1, y, 0.03), (0.3, 0.07, 0.06), m['azul'], 0.006))
        for z in ESTANTE_BALDAS:
            # Brazo en voladizo, más alto junto al puntal.
            p.append(caja('brazo', (0.0, y, z - 0.045), (fx - 0.04, 0.04, 0.05), m['azul'], 0.004))
            p.append(caja('cartela', (xPuntal - 0.08, y, z - 0.1), (0.1, 0.03, 0.08), m['azul'], 0.004))
    for z in ESTANTE_BALDAS:
        p.append(caja('balda', (0, 0, z - 0.012), (fx, fy, 0.024), m['balda'], 0.003))
        p.append(caja('frente', (-fx / 2 + 0.006, 0, z - 0.025), (0.012, fy, 0.05), m['balda'], 0.002))
        p.append(caja('raya', (-fx / 2 - 0.001, 0, z - 0.025), (0.003, fy * 0.95, 0.012), m['agarre']))
    # Arriostrado en cruz detrás.
    for k in range(2):
        y0, y1 = puntalesY[k], puntalesY[k + 1]
        for z0, z1 in ((0.2, 1.6), (1.6, 0.2)):
            bm = bmesh.new()
            largo = math.hypot(y1 - y0, z1 - z0)
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=Vector((0.015, largo, 0.025)), verts=bm.verts)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.atan2(z1 - z0, y1 - y0), 3, 'X'))
            bmesh.ops.translate(bm, vec=Vector((xPuntal + 0.04, (y0 + y1) / 2, (z0 + z1) / 2)), verts=bm.verts)
            p.append(objetoDe('cruz', bm, m['azul']))
    return unir(p, 'estanteriaRobot')


def crearRack(m):
    """Rack largo en voladizo: puntales azules solo detrás (la base del robot
    entra por delante), brazos naranjas, baldas galvanizadas con larguero
    naranja delante y el número de cada hueco en el canto."""
    fx, fy = RACK
    p = []
    xPuntal = fx / 2 - 0.04
    for y in RACK_PUNTALES_Y:
        p.append(caja('puntal', (xPuntal, y, RACK_ALTO / 2), (0.08, 0.07, RACK_ALTO), m['azul'], 0.006))
        p.append(caja('pie', (xPuntal + 0.1, y, 0.03), (0.32, 0.08, 0.06), m['azul'], 0.006))
        for z in RACK_BALDAS:
            p.append(caja('brazo', (0.0, y, z - 0.05), (fx - 0.04, 0.045, 0.06), m['naranja'], 0.004))
            p.append(caja('cartela', (xPuntal - 0.08, y, z - 0.11), (0.1, 0.035, 0.09), m['naranja'], 0.004))
    for z in RACK_BALDAS:
        p.append(caja('balda', (0, 0, z - 0.012), (fx, fy, 0.024), m['balda'], 0.003))
        p.append(caja('larguero', (-fx / 2 + 0.01, 0, z - 0.04), (0.02, fy, 0.07), m['naranja'], 0.003))
    # Marcas de cada hueco en el larguero: raya blanca a cada lado del hueco.
    for z in RACK_NIVELES_HUECOS:
        for y in RACK_HUECOS_Y:
            for lado in (-1, 1):
                p.append(caja('marca', (-fx / 2 - 0.001, y + lado * 0.25, z - 0.04), (0.003, 0.012, 0.05), m['etiqueta']))
    # Arriostrado en cruz detrás, entre cada par de puntales.
    for k in range(len(RACK_PUNTALES_Y) - 1):
        y0, y1 = RACK_PUNTALES_Y[k], RACK_PUNTALES_Y[k + 1]
        for z0, z1 in ((0.2, 1.7), (1.7, 0.2)):
            bm = bmesh.new()
            largo = math.hypot(y1 - y0, z1 - z0)
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=Vector((0.015, largo, 0.025)), verts=bm.verts)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.atan2(z1 - z0, y1 - y0), 3, 'X'))
            bmesh.ops.translate(bm, vec=Vector((xPuntal + 0.045, (y0 + y1) / 2, (z0 + z1) / 2)), verts=bm.verts)
            p.append(objetoDe('cruz', bm, m['azul']))
    return unir(p, 'rackRobot')


def crearDeposito(m):
    """Depósito del misil: banco de acero robusto (chapa lagrimada encima,
    patas de perfil y travesaños), canto delantero con franjas de peligro y
    tres zonas separadas por pletinas: DINERO (verde, +y), METAL (en medio) y
    PETRÓLEO (negro y naranja, -y), con dos huecos marcados en blanco en el
    tablero de cada una.
    Detrás, un panel con el rótulo DEPÓSITO MISIL y el nombre de cada zona."""
    fx, fy, alto = DEPOSITO
    p = []
    p.append(caja('tablero', (0, 0, alto - 0.025), (fx, fy, 0.05), m['chapa'], 0.004))
    xDelante, xDetras = -fx / 2 + 0.12, fx / 2 - 0.06
    for x in (xDelante, xDetras):
        for y in (-fy / 2 + 0.06, -fy / 4, 0.0, fy / 4, fy / 2 - 0.06):
            p.append(caja('pata', (x, y, (alto - 0.05) / 2), (0.07, 0.07, alto - 0.05), m['gris'], 0.005))
            p.append(caja('pie', (x, y, 0.01), (0.12, 0.12, 0.02), m['goma']))
        p.append(caja('larguero', (x, 0, alto - 0.09), (0.05, fy - 0.12, 0.08), m['gris'], 0.003))
        p.append(caja('largueroBajo', (x, 0, 0.18), (0.05, fy - 0.12, 0.05), m['gris'], 0.003))
    # Canto delantero: franjas amarillas y negras de 10 cm.
    n = int(fy / 0.1)
    for k in range(n):
        y = -fy / 2 + 0.05 + k * 0.1
        p.append(caja('franja', (-fx / 2 - 0.003, y, alto - 0.025), (0.006, 0.1, 0.05), m['agarre'] if k % 2 == 0 else m['goma']))
    # Pletinas que separan las zonas, bandas de color y huecos marcados.
    colores = {'dinero': m['verdePanel'], 'metal': m['gris'], 'petroleo': m['naranja']}
    paneles = {'dinero': m['verdePanel'], 'metal': m['aceroOscuro'], 'petroleo': m['negroPanel']}
    for y in (-0.8, 0.8):
        p.append(caja('separador', (0, y, alto + 0.04), (fx - 0.04, 0.03, 0.08), m['acero'], 0.003))
    hx = -fx / 2 + 0.15
    xp = fx / 2 - 0.02
    zp = alto + DEPOSITO_PANEL / 2
    frente = (math.pi / 2, 0, -math.pi / 2)
    xl = xp - 0.018
    for recurso, rotulo, yz in DEPOSITO_ZONAS:
        p.append(caja('banda', (fx / 2 - 0.09, yz, alto + 0.002), (0.1, 1.5, 0.004), colores[recurso]))
        for signo in (1, -1):
            yc = yz + signo * DEPOSITO_HUECO_Y
            for dy in (-0.23, 0.23):
                p.append(caja('marca', (hx, yc + dy, alto + 0.002), (0.32, 0.02, 0.004), m['etiqueta']))
            for dx in (-0.16, 0.16):
                p.append(caja('marca', (hx + dx, yc, alto + 0.002), (0.02, 0.46, 0.004), m['etiqueta']))
        # Panel trasero de la zona con su nombre.
        p.append(caja('panel', (xp, yz, zp), (0.03, 1.56, DEPOSITO_PANEL), paneles[recurso], 0.004))
        color = m['naranja'] if recurso == 'petroleo' else m['blancoLetra']
        p.append(letras(rotulo, 0.17, color, (xl, yz, zp + 0.14), frente))
    p.append(caja('marcoPanel', (xp + 0.005, 0, alto + DEPOSITO_PANEL + 0.02), (0.05, fy, 0.04), m['gris'], 0.003))
    for y in (-fy / 2 + 0.03, -0.8, 0.8, fy / 2 - 0.03):
        p.append(caja('montante', (xp + 0.005, y, zp), (0.05, 0.05, DEPOSITO_PANEL + 0.04), m['gris'], 0.003))
    # Iconos: $ del dinero, un lingote del metal y la gota del petróleo.
    p.append(letras('$', 0.26, m['oro'], (xl, 1.6, zp - 0.14), frente))
    bm = bmesh.new()
    abajo = [(-0.13, -0.05), (0.13, -0.05), (0.13, 0.05), (-0.13, 0.05)]
    vs = [bm.verts.new((0, px, pz)) for px, pz in ((-0.13, -0.05), (0.13, -0.05), (0.09, 0.05), (-0.09, 0.05))]
    bm.faces.new(vs)
    bmesh.ops.translate(bm, vec=Vector((xl - 0.002, 0.0, zp - 0.14)), verts=bm.verts)
    p.append(objetoDe('iconoLingote', bm, m['acero']))
    zg = zp - 0.2
    p.append(cilindro('gota', (xl + 0.004, -1.6, zg), 0.075, 0.006, m['naranja'], eje='x', lados=24))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((0.006, 0.112, 0.112)), verts=bm.verts)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 4, 3, 'X'))
    bmesh.ops.scale(bm, vec=Vector((1.0, 0.95, 1.5)), verts=bm.verts)  # estirado hacia arriba
    bmesh.ops.translate(bm, vec=Vector((xl + 0.004, -1.6, zg + 0.06)), verts=bm.verts)
    p.append(objetoDe('puntaGota', bm, m['naranja']))
    # Rótulo de arriba: DEPÓSITO MISIL, amarillo sobre negro.
    p.append(caja('rotulo', (xp, 0, alto + DEPOSITO_PANEL + 0.2), (0.03, 1.8, 0.3), m['negroPanel'], 0.004))
    p.append(caja('rotuloBorde', (xp + 0.004, 0, alto + DEPOSITO_PANEL + 0.2), (0.025, 1.86, 0.36), m['agarre'], 0.004))
    p.append(letras('DEPÓSITO MISIL', 0.15, m['agarre'], (xl - 0.01, 0, alto + DEPOSITO_PANEL + 0.2), frente))
    for y in (-0.8, 0.8):
        p.append(caja('soporteRotulo', (xp + 0.005, y, alto + DEPOSITO_PANEL + 0.04), (0.04, 0.04, 0.08), m['gris']))
    return unir(p, 'depositoMisil')


def renderDeposito(ruta, m, objetos):
    """Foto del depósito con dos pacas de dinero puestas en sus huecos."""
    escena = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            escena.render.engine = motor
            break
        except TypeError:
            pass
    escena.render.resolution_x = 1600
    escena.render.resolution_y = 1000
    mundo = bpy.data.worlds.new('mundo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.3, 0.32, 0.35, 1)
    fondo.inputs['Strength'].default_value = 0.9
    escena.world = mundo
    caja('suelo', (0, 0, -0.01), (14, 14, 0.02), material('sueloHormigon', (0.45, 0.45, 0.43), 0.8))
    sol = bpy.data.objects.new('sol', bpy.data.lights.new('sol', 'SUN'))
    sol.data.energy = 3.2
    sol.rotation_euler = (math.radians(45), 0, math.radians(-35))
    escena.collection.objects.link(sol)
    for nombre, o in objetos.items():
        o.location = (0, 0, -50) if nombre != 'depositoMisil' else (0, 0, 0)
    fx, fy, alto = DEPOSITO
    hx = -fx / 2 + 0.15
    for y in (1.6 - DEPOSITO_HUECO_Y, 1.6 + DEPOSITO_HUECO_Y):
        copia = objetos['pacaDinero'].copy()
        escena.collection.objects.link(copia)
        copia.location = (hx, y, alto)
    camaraDatos = bpy.data.cameras.new('camara')
    camaraDatos.lens = 30
    camara = bpy.data.objects.new('camara', camaraDatos)
    escena.collection.objects.link(camara)
    escena.camera = camara
    pos, mira = Vector((-4.6, -0.9, 2.1)), Vector((0, 0.0, 1.05))
    camara.location = pos
    camara.rotation_euler = (mira - pos).to_track_quat('-Z', 'Y').to_euler()
    escena.render.filepath = ruta
    bpy.ops.render.render(write_still=True)


def renderNuevos(ruta, m, objetos):
    """Foto de cerca: garrafa (vacía y otra), caja de caudales vacía y otra
    con fajos dentro, y una paca de 200 al lado para comparar."""
    escena = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            escena.render.engine = motor
            break
        except TypeError:
            pass
    escena.render.resolution_x = 1600
    escena.render.resolution_y = 1000
    mundo = bpy.data.worlds.new('mundo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.3, 0.32, 0.35, 1)
    fondo.inputs['Strength'].default_value = 0.9
    escena.world = mundo
    caja('suelo', (0, 0, -0.01), (14, 14, 0.02), material('sueloHormigon', (0.45, 0.45, 0.43), 0.8))
    sol = bpy.data.objects.new('sol', bpy.data.lights.new('sol', 'SUN'))
    sol.data.energy = 3.2
    sol.rotation_euler = (math.radians(45), 0, math.radians(-35))
    escena.collection.objects.link(sol)
    for o in objetos.values():
        o.location = (0, 0, -50)
    objetos['garrafaPetroleo'].location = (0, -0.75, 0)
    objetos['garrafaPetroleo'].rotation_euler = (0, 0, math.radians(60))
    objetos['cajaCaudales'].location = (0, -0.2, 0)
    llena = objetos['cajaCaudales'].copy()
    escena.collection.objects.link(llena)
    llena.location = (0, 0.35, 0)
    for i in range(2):
        for k in range(4):
            alto = 0.08 + 0.025 * ((k + i) % 3)
            x, y = -0.06 + i * 0.13, 0.35 + (k - 1.5) * 0.085
            caja('fajo', (x, y, 0.024 + alto / 2), (0.12, 0.075, alto), m['billete'], 0.004)
            caja('faja', (x, y, 0.024 + alto / 2), (0.03, 0.078, alto + 0.002), m['oro'], 0.002)
    objetos['pacaDinero'].location = (0, 0.9, 0)
    camaraDatos = bpy.data.cameras.new('camara')
    camaraDatos.lens = 40
    camara = bpy.data.objects.new('camara', camaraDatos)
    escena.collection.objects.link(camara)
    escena.camera = camara
    pos, mira = Vector((-1.6, -1.25, 1.3)), Vector((0, -0.12, 0.12))
    camara.location = pos
    camara.rotation_euler = (mira - pos).to_track_quat('-Z', 'Y').to_euler()
    escena.render.filepath = ruta
    bpy.ops.render.render(write_still=True)


# Datos para el juego ------------------------------------------------------------


def f(v):
    return '%.3f' % v


def caja_lua(x0, y0, z0, x1, y1, z1):
    return '{ %s, %s, %s, %s, %s, %s }' % tuple(f(v) for v in (x0, y0, z0, x1, y1, z1))


def escribirDatos(ruta):
    fx, fy, fz = CAJA
    yPlaca = fy / 2 + OREJETA_SEPARACION
    mx, my, mz = MUNICION
    tx, ty, alto = MESA
    ex, ey = ESTANTE
    xPuntal = ex / 2 - 0.04
    lineas = [
        '-- Objetos del almacén que maneja el robot y sus muebles',
        '-- (tools/blender/objetos_almacen.py --glb). Metros, ejes del objeto:',
        '-- +x hacia donde mira el robot al cogerlo (el frente en -x), z arriba,',
        '-- origen en el suelo bajo el centro.',
        '--   puntos: puntos de agarre { nombre, x, y, z, eje de cierre, grosor, mano }',
        "--           mano: 'izq', 'der' o 'cualquiera'; las dos manos si hay dos.",
        '--   huecos: sitios de apoyo { x, y, z } (el objeto se pone con su origen ahí',
        '--           y mirando como el mueble).',
        '--   cajas:  cajas de colisión { x0, y0, z0, x1, y1, z1 }.',
        'return {',
        '    cajaRobot = {',
        "        nombre = 'caja de plástico', movible = true, peso = 6,",
        '        tamano = { %s, %s, %s },' % (f(fx), f(fy), f(fz)),
        '        puntos = {',
        "            { 'orejetaIzq', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'izq' }," % (f(OREJETA_X), f(yPlaca), f(OREJETA_Z), f(OREJETA[1])),
        "            { 'orejetaDer', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'der' }," % (f(OREJETA_X), f(-yPlaca), f(OREJETA_Z), f(OREJETA[1])),
        '        },',
        '        cajas = { %s },' % caja_lua(-fx / 2, -yPlaca - 0.006, 0, fx / 2, yPlaca + 0.006, fz + 0.006),
        '    },',
        '    cajaMunicion = {',
        "        nombre = 'caja de munición', movible = true, peso = 9,",
        '        tamano = { %s, %s, %s },' % (f(mx), f(my), f(mz)),
        '        puntos = {',
        "            { 'asa', 0, 0, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'cualquiera' }," % (f(ASA_Z), f(ASA_GROSOR)),
        '        },',
        '        cajas = { %s },' % caja_lua(-mx / 2 - 0.016, -my / 2 - 0.005, 0, mx / 2, my / 2 + 0.005, ASA_Z + 0.01),
        '    },',
        '    mesaRecepcion = {',
        "        nombre = 'mesa de recepción', movible = false,",
        '        tamano = { %s, %s, %s },' % (f(tx), f(ty), f(alto)),
        '        huecos = {',
    ]
    for y in MESA_HUECOS_Y:
        lineas.append('            { %s, %s, %s },' % (f(-tx / 2 + 0.15), f(y), f(alto)))
    xDelante = -tx / 2 + MESA_VUELO
    lineas += [
        '        },',
        '        cajas = {',
        '            %s,' % caja_lua(-tx / 2, -ty / 2, alto - 0.08, tx / 2, ty / 2, alto),
        '            %s,' % caja_lua(xDelante - 0.025, -ty / 2, 0, tx / 2, -ty / 2 + 0.075, alto),
        '            %s,' % caja_lua(xDelante - 0.025, ty / 2 - 0.075, 0, tx / 2, ty / 2, alto),
        '            %s,' % caja_lua(xDelante - 0.025, -ty / 2, 0.15, tx / 2, ty / 2, 0.17),
        '        },',
        '    },',
        '    estanteriaRobot = {',
        "        nombre = 'estantería', movible = false,",
        '        tamano = { %s, %s, %s },' % (f(ex), f(ey), f(ESTANTE_ALTO)),
        '        huecos = {',
    ]
    for z in ESTANTE_NIVELES_HUECOS:
        for y in ESTANTE_HUECOS_Y:
            lineas.append('            { %s, %s, %s },' % (f(-ex / 2 + 0.15), f(y), f(z)))
    lineas += ['        },', '        cajas = {']
    for z in ESTANTE_BALDAS:
        lineas.append('            %s,' % caja_lua(-ex / 2, -ey / 2, z - 0.12, ex / 2, ey / 2, z))
    lineas.append('            %s,' % caja_lua(xPuntal - 0.04, -ey / 2, 0, xPuntal + 0.25, ey / 2, ESTANTE_ALTO))
    # Suministros: mismas medidas y orejetas que la caja de plástico.
    for tipo, nombre, peso, recurso, cantidad in (
            ('pacaDinero', 'paca de dinero', 8, 'dinero', 200),
            ('cajaComida', 'caja de comida', 9, 'comida', 20),
            ('cajaObuses', 'caja de obuses', 18, 'obuses', 100),
            ('cajaMetal', 'caja de metal', 20, 'metal', 10)):
        lineas += [
            '        },' if tipo == 'pacaDinero' else '    },',
            '    },' if tipo == 'pacaDinero' else '    %s = {' % tipo,
        ] + (['    %s = {' % tipo] if tipo == 'pacaDinero' else []) + [
            "        nombre = '%s', movible = true, peso = %d, recurso = '%s', cantidad = %d," % (nombre, peso, recurso, cantidad),
            '        tamano = { %s, %s, %s },' % (f(fx), f(fy), f(fz)),
            '        puntos = {',
            "            { 'orejetaIzq', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'izq' }," % (f(OREJETA_X), f(yPlaca), f(OREJETA_Z), f(OREJETA[1])),
            "            { 'orejetaDer', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'der' }," % (f(OREJETA_X), f(-yPlaca), f(OREJETA_Z), f(OREJETA[1])),
            '        },',
            '        cajas = { %s },' % caja_lua(-fx / 2, -yPlaca - 0.006, 0, fx / 2, yPlaca + 0.006, fz + 0.006),
        ]
    lineas += [
        '    },',
        '    bidonPetroleo = {',
        "        nombre = 'bidón de petróleo', movible = true, peso = 180, recurso = 'petroleo', cantidad = 50,",
        '        tamano = { %s, %s, %s },' % (f(2 * BIDON_RADIO), f(2 * BIDON_RADIO), f(BIDON_ALTO)),
        # Garra del robot grande: abraza el cuerpo entre los dos aros de
        # rodadura; es redondo, vale desde cualquier lado (el eje de cierre
        # es el de la garra).
        '        puntos = {',
        "            { 'cuerpo', 0.000, 0.000, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'garra', redondo = true }," % (f(BIDON_ALTO * 0.6), f(2 * BIDON_RADIO)),
        '        },',
        '        cajas = {',
        '            %s,' % caja_lua(-BIDON_RADIO, -BIDON_RADIO, 0, BIDON_RADIO, BIDON_RADIO, BIDON_ALTO + 0.02),
    ]
    rx, ry = RACK
    xp = rx / 2 - 0.04
    lineas += [
        '        },',
        '    },',
        '    rackRobot = {',
        "        nombre = 'rack', movible = false,",
        '        tamano = { %s, %s, %s },' % (f(rx), f(ry), f(RACK_ALTO)),
        '        huecos = {',
    ]
    for z in RACK_NIVELES_HUECOS:
        for y in RACK_HUECOS_Y:
            lineas.append('            { %s, %s, %s },' % (f(-rx / 2 + 0.15), f(y), f(z)))
    lineas += ['        },', '        cajas = {']
    for z in RACK_BALDAS:
        lineas.append('            %s,' % caja_lua(-rx / 2, -ry / 2, z - 0.12, rx / 2, ry / 2, z))
    lineas.append('            %s,' % caja_lua(xp - 0.04, -ry / 2, 0, xp + 0.26, ry / 2, RACK_ALTO))
    lineas += ['        },', '    },']
    # Caja de caudales: lleva el dinero justo del rack al depósito.
    lineas += [
        '    cajaCaudales = {',
        "        nombre = 'caja de dinero', movible = true, peso = 4, recurso = 'dinero', cantidad = 0, recipiente = true,",
        '        tamano = { %s, %s, %s },' % (f(fx), f(fy), f(0.2)),
        '        puntos = {',
        "            { 'orejetaIzq', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'izq' }," % (f(OREJETA_X), f(yPlaca), f(OREJETA_Z), f(OREJETA[1])),
        "            { 'orejetaDer', %s, %s, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'der' }," % (f(OREJETA_X), f(-yPlaca), f(OREJETA_Z), f(OREJETA[1])),
        '        },',
        '        cajas = { %s },' % caja_lua(-fx / 2, -yPlaca - 0.006, 0, fx / 2, yPlaca + 0.006, 0.212),
        '    },',
    ]
    gx, gy, gz = GARRAFA
    lineas += [
        '    garrafaPetroleo = {',
        "        nombre = 'garrafa de petróleo', movible = true, peso = 9, recurso = 'petroleo', cantidad = 0, capacidad = 10, recipiente = true,",
        '        tamano = { %s, %s, %s },' % (f(gx), f(gy), f(gz)),
        '        puntos = {',
        "            { 'asa', 0, 0, %s, eje = { 0, 1, 0 }, grosor = %s, mano = 'cualquiera' }," % (f(GARRAFA_ASA_Z), f(ASA_GROSOR)),
        '        },',
        '        cajas = { %s },' % caja_lua(-gx / 2, -gy / 2, 0, gx / 2, gy / 2, GARRAFA_ASA_Z + 0.01),
        '    },',
    ]
    # Depósito del misil: huecos de DINERO (+y) y de PETRÓLEO (-y).
    dx, dy, dalto = DEPOSITO
    lineas += [
        '    depositoMisil = {',
        "        nombre = 'depósito del misil', movible = false,",
        '        tamano = { %s, %s, %s },' % (f(dx), f(dy), f(dalto + DEPOSITO_PANEL + 0.35)),
        "        zonas = { dinero = { 1, 2 }, metal = { 3, 4 }, petroleo = { 5, 6 } },",
        '        huecos = {',
    ]
    for _, _, yz in DEPOSITO_ZONAS:
        for signo in (1, -1):
            lineas.append('            { %s, %s, %s },' % (f(-dx / 2 + 0.15), f(yz + signo * DEPOSITO_HUECO_Y), f(dalto)))
    lineas += [
        '        },',
        '        cajas = {',
        '            %s,' % caja_lua(-dx / 2, -dy / 2, dalto - 0.12, dx / 2, dy / 2, dalto),
        '            %s,' % caja_lua(-dx / 2 + 0.08, -dy / 2, 0, -dx / 2 + 0.16, dy / 2, dalto),
        '            %s,' % caja_lua(dx / 2 - 0.1, -dy / 2, 0, dx / 2, dy / 2, dalto + DEPOSITO_PANEL + 0.38),
        '        },',
        '    },',
        '}',
        '',
    ]
    with open(ruta, 'w') as archivo:
        archivo.write('\n'.join(lineas))


# Render de comprobación ----------------------------------------------------------


def renderizar(carpeta, objetos):
    os.makedirs(carpeta, exist_ok=True)
    escena = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            escena.render.engine = motor
            break
        except TypeError:
            pass
    escena.render.resolution_x = 1400
    escena.render.resolution_y = 900
    mundo = bpy.data.worlds.new('mundo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.3, 0.32, 0.35, 1)
    fondo.inputs['Strength'].default_value = 0.8
    escena.world = mundo
    suelo = caja('suelo', (0, 0, -0.01), (12, 12, 0.02), material('suelo', (0.5, 0.5, 0.48), 0.8))
    sol = bpy.data.objects.new('sol', bpy.data.lights.new('sol', 'SUN'))
    sol.data.energy = 3
    sol.rotation_euler = (math.radians(50), 0, math.radians(-30))
    escena.collection.objects.link(sol)
    # Colocados en fila para verlos juntos, con las cajas en los huecos.
    objetos['mesaRecepcion'].location = (0, 0, 0)
    objetos['estanteriaRobot'].location = (0, 2.4, 0)
    objetos['cajaRobot'].location = (-MESA[0] / 2 + 0.15, 0, MESA[2])
    objetos['cajaMunicion'].location = (-MESA[0] / 2 + 0.15, 0.45, MESA[2])
    camaraDatos = bpy.data.cameras.new('camara')
    camaraDatos.lens = 35
    camara = bpy.data.objects.new('camara', camaraDatos)
    escena.collection.objects.link(camara)
    escena.camera = camara
    for nombre, pos, mira in (('objetos_conjunto', (-3.2, -1.6, 2.0), (0, 1.2, 0.9)), ('objetos_caja', (-0.95, -0.55, 1.35), (-0.2, 0.15, 1.0))):
        camara.location = pos
        direccion = Vector(mira) - Vector(pos)
        camara.rotation_euler = direccion.to_track_quat('-Z', 'Y').to_euler()
        escena.render.filepath = os.path.join(carpeta, nombre + '.png')
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(suelo)


def principal():
    args = argumentos()
    limpiar()
    m = materiales()
    objetos = {
        'cajaRobot': crearCajaRobot(m),
        'cajaMunicion': crearCajaMunicion(m),
        'mesaRecepcion': crearMesa(m),
        'estanteriaRobot': crearEstanteria(m),
        'rackRobot': crearRack(m),
        'pacaDinero': crearPacaDinero(m),
        'cajaComida': crearCajaComida(m),
        'cajaObuses': crearCajaObuses(m),
        'cajaMetal': crearCajaMetal(m),
        'bidonPetroleo': crearBidonPetroleo(m),
        'depositoMisil': crearDeposito(m),
        'garrafaPetroleo': crearGarrafa(m),
        'cajaCaudales': crearCajaCaudales(m),
    }
    for o in objetos.values():
        uvCaja(o)
    if '--nuevos' in args:
        renderNuevos(args[args.index('--nuevos') + 1], m, objetos)
        return
    if '--deposito' in args:
        renderDeposito(args[args.index('--deposito') + 1], m, objetos)
        return
    if '--glb' in args:
        os.makedirs(os.path.dirname(GLB), exist_ok=True)
        opciones = dict(filepath=GLB, export_format='GLB', use_selection=False, export_apply=True)
        try:
            bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
        except TypeError:
            bpy.ops.export_scene.gltf(**opciones)
        escribirDatos(DATOS)
        print('EXPORTADO', GLB, DATOS)
        return
    if args:
        bpy.ops.wm.save_as_mainfile(filepath=args[0])
    if len(args) > 1:
        renderizar(args[1], objetos)


principal()

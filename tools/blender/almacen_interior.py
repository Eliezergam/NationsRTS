# Interior del almacén (nave industrial militar), paso 1: estructura y
# distribución. Se corre sin ventana:
#
#     blender -b --factory-startup --python tools/blender/almacen_interior.py -- \
#         <salida.blend> [carpeta de renders]
#
# Medidas (en metros; 1 unidad de Blender = 1 m, el juego usa 10 px por m):
#   nave de 60 x 30 m, pórticos de acero cada 7,5 m (luz de 30 m, alero a
#   9 m, cubierta a dos aguas con 6°: cumbrera a 10,58 m), correas cada
#   1,5 m, largueros de fachada cada 1,8 m, zócalo de hormigón de 1,2 m.
#   Fuentes: SteelConstruction.info (pórticos de 15-50 m de luz, 8-18 m de
#   alto, 5-10° de pendiente, 6-8 m entre pórticos); racks de palés de
#   largueros de 2,7 m y 1,1 m de fondo, pasillos de 3,5 m.
#
# Ejes: x a lo largo de la nave (los portones en x = +30), y a lo ancho,
# z arriba; el origen en el centro del suelo.
#
# Zonas: x de -75 a -45, fábrica de misiles; x de -45 a -30, polvorín de
# misiles (sala blindada de hormigón, entre dos muros cortafuegos con
# portón); x de -30 a 0, racks de palés (suministros); x de 0 a +30, plazas
# de vehículos (5 por lado, 5 x 12 m) a los dos lados de un carril central.
#
# Fábrica, como las naves de montaje de misiles reales (Lockheed Martin MAB 4,
# Sandia MAB): nave alta separada, puente grúa, suelo de epoxi conductor
# (contra la electricidad estática) y red de toma de tierra.
#
# Materiales: los del kit de la Base (assets/base/materiales), con las
# texturas reales de ambientCG (assets/base/LICENCIAS.md).

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MATERIALES = os.path.join(RAIZ, 'assets', 'base', 'materiales')

XMIN = -75.0
XMAX = 30.0
LARGO = XMAX - XMIN
XCENTRO = (XMIN + XMAX) / 2
# Muros cortafuegos: fábrica | polvorín y polvorín | racks.
XFABRICA = -45.0
XMURO = -30.0
# ANCHO: las zonas de trabajo (fábrica, polvorín, nave), de y = -15 a 15.
# La nave entera es más ancha (17-nov, para el robot grande): de Y_SUR a
# Y_NORTE, con la calle principal (CALLE_Y) a lo largo de todo el norte y una
# reserva detrás; la cumbrera, en el centro (Y_EJE).
ANCHO = 30.0
Y_SUR = -15.0
Y_NORTE = 27.0
ANCHO_NAVE = Y_NORTE - Y_SUR
Y_EJE = (Y_SUR + Y_NORTE) / 2
CALLE_Y = (15.5, 21.5)  # calle principal del robot grande, de la fábrica al patio
PORTON_CALLE = (15.4, 22.4, 6.0)  # portones de 7 x 6 m de la calle en cada muro
ALERO = 9.0
PENDIENTE = math.radians(6)
CUMBRERA = ALERO + (ANCHO_NAVE / 2) * math.tan(PENDIENTE)
ENTRE_PORTICOS = 7.5
ZOCALO = 1.2

# Perfiles de los pórticos (m): pilar y dintel HEA/IPE de unos 50 cm.
PILAR_CANTO = 0.5
PILAR_ALA = 0.3
DINTEL_CANTO = 0.6
DINTEL_ALA = 0.25
ESPESOR_ALA = 0.025
ESPESOR_ALMA = 0.015

# Racks: largueros de 2,7 m, fondo de 1,1 m, tres niveles.
RACK_HUECO = 2.7
RACK_FONDO = 1.1
RACK_NIVELES = (1.6, 3.2, 4.8)
RACK_ALTO = 6.0
PASILLO = 3.5

# Anexo de suministros (sala nueva pegada al testero de +x, al sur) y patio
# de descarga al aire libre (al norte), los dos detrás de los portones.
ANEXO_X1 = 64.0
ANEXO_Y0 = -ANCHO / 2
ANEXO_Y1 = -1.5
ANEXO_ALTO = 6.0
PATIO_X1 = 64.0
PATIO_Y0 = -1.5
PATIO_Y1 = 32.0
# Filas de racks del robot en el anexo (cinco racks de 5,4 m por fila):
# (y de la fila, lado en y donde se pone el robot, carteles: (nombre,
# letrero, cuántos racks) de la entrada al fondo, numerados por letrero).
# Los racks los pone el juego (almacen/escena.lua, EscenaAlmacen.filas) con
# estas mismas y; la de munición y la de comida van espalda con espalda, y
# la del muro sur (metal y petróleo, 2026-11-17) comparte pasillo con la de
# comida.
FILAS_ANEXO = (
    (-2.4, -1, (('Dinero', 'DINERO', 5),)),
    (-8.6, 1, (('Municion', 'MUNICIÓN', 5),)),
    (-9.4, -1, (('Comida', 'COMIDA', 5),)),
    (-14.45, 1, (('Metal', 'METAL', 3), ('Petroleo', 'PETRÓLEO', 2))),
)


def cartelesFila(carteles):
    """(nombre, letrero numerado) de cada rack de la fila, de la entrada al fondo."""
    lista = []
    for nombre, letrero, cuantos in carteles:
        for k in range(cuantos):
            lista.append((nombre, '%s %d' % (letrero, k + 1)))
    return lista
FILA_RACKS_X = (36.0, 41.6, 47.2, 52.8, 58.4)  # centros de los racks
RACK_LARGO = 5.4

# Zona de descarga pintada en el patio: x0, x1, y0, y1.
EXTREMOS_DESCARGA = (37.0, 61.0, 1.0, 20.0)

# Plazas de vehículos.
PLAZA_ANCHO = 5.0
PLAZA_FONDO = 12.0
PLAZAS_POR_LADO = 5


def argumentos():
    if '--' in sys.argv:
        return sys.argv[sys.argv.index('--') + 1:]
    return []


def limpiarEscena():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'


# Materiales ---------------------------------------------------------------

def nodoPrincipled(material):
    return next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def materialKit(nombre, metalico):
    """Material del kit de la Base: albedo, normal y material.jpg con los
    canales de 3DreamEngine: R metálico, G rugosidad, B oclusión."""
    material = bpy.data.materials.new(nombre)
    material.use_nodes = True
    nodos = material.node_tree.nodes
    enlaces = material.node_tree.links
    bsdf = nodoPrincipled(material)
    carpeta = os.path.join(MATERIALES, nombre)

    albedo = nodos.new('ShaderNodeTexImage')
    albedo.image = bpy.data.images.load(os.path.join(carpeta, 'albedo.jpg'))
    enlaces.new(albedo.outputs['Color'], bsdf.inputs['Base Color'])

    datos = nodos.new('ShaderNodeTexImage')
    datos.image = bpy.data.images.load(os.path.join(carpeta, 'material.jpg'))
    datos.image.colorspace_settings.name = 'Non-Color'
    separar = nodos.new('ShaderNodeSeparateColor')
    enlaces.new(datos.outputs['Color'], separar.inputs['Color'])
    enlaces.new(separar.outputs['Green'], bsdf.inputs['Roughness'])
    enlaces.new(separar.outputs['Red'], bsdf.inputs['Metallic'])

    normal = nodos.new('ShaderNodeTexImage')
    normal.image = bpy.data.images.load(os.path.join(carpeta, 'normal.jpg'))
    normal.image.colorspace_settings.name = 'Non-Color'
    mapaNormal = nodos.new('ShaderNodeNormalMap')
    enlaces.new(normal.outputs['Color'], mapaNormal.inputs['Color'])
    enlaces.new(mapaNormal.outputs['Normal'], bsdf.inputs['Normal'])
    return material


def materialAtlas():
    """El atlas de Synty de la Base (assets/base/materiales/AtlasSyntyBase)."""
    material = bpy.data.materials.new('AtlasSyntyBase')
    material.use_nodes = True
    nodos = material.node_tree.nodes
    bsdf = nodoPrincipled(material)
    imagen = nodos.new('ShaderNodeTexImage')
    imagen.image = bpy.data.images.load(os.path.join(MATERIALES, 'AtlasSyntyBase', 'albedo.png'))
    imagen.interpolation = 'Closest'
    material.node_tree.links.new(imagen.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.7
    return material


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


def materialVidrio():
    material = materialLiso('vidrioSala', (0.62, 0.78, 0.76), 0.05)
    nodoPrincipled(material).inputs['Alpha'].default_value = 0.16
    for propiedad, valor in (('blend_method', 'BLEND'), ('surface_render_method', 'BLENDED')):
        try:
            setattr(material, propiedad, valor)
        except (AttributeError, TypeError):
            pass
    return material


def crearMateriales():
    return {
        'hormigon': materialKit('baseHormigon', 0.0),
        'chapa': materialKit('baseChapa', 0.6),
        'acero': materialKit('baseAcero', 1.0),
        'peligro': materialKit('basePeligro', 0.5),
        # Pintura de la estructura: gris acero oscuro (el de los pilares del kit).
        'estructura': materialLiso('estructura', (0.16, 0.18, 0.2), 0.55, 0.6),
        # Pintura del suelo y de los racks.
        'lineaAmarilla': materialLiso('lineaAmarilla', (0.85, 0.62, 0.05), 0.6),
        'rackAzul': materialLiso('rackAzul', (0.05, 0.16, 0.42), 0.45, 0.3),
        'rackNaranja': materialLiso('rackNaranja', (0.85, 0.32, 0.04), 0.45, 0.3),
        'lucernario': materialLiso('lucernario', (0.92, 0.95, 0.98), 0.2, 0.0, 8.0),
        'foco': materialLiso('foco', (1.0, 0.96, 0.88), 0.3, 0.0, 25.0),
        'portonPanel': materialLiso('portonPanel', (0.42, 0.45, 0.4), 0.5, 0.4),
        # Fábrica: epoxi conductor gris verdoso, satinado (no espejo).
        'epoxi': materialLiso('epoxi', (0.2, 0.26, 0.23), 0.42),
        'lineaBlanca': materialLiso('lineaBlanca', (0.85, 0.85, 0.82), 0.5),
        'cobre': materialLiso('cobre', (0.72, 0.38, 0.2), 0.35, 1.0),
        'tierra': materialLiso('tierra', (0.1, 0.45, 0.12), 0.5),
        'gruaAmarilla': materialLiso('gruaAmarilla', (0.88, 0.62, 0.04), 0.45, 0.3),
        'cable': materialLiso('cable', (0.05, 0.05, 0.05), 0.5, 0.8),
        # Imprimación del misil sin pintar (verde gris mate) y goma de las cunas.
        'imprimacion': materialLiso('imprimacion', (0.33, 0.37, 0.33), 0.55, 0.2),
        'goma': materialLiso('goma', (0.03, 0.03, 0.03), 0.8),
        'electronica': materialLiso('electronica', (0.05, 0.25, 0.1), 0.4),
        'eslinga': materialLiso('eslinga', (0.9, 0.45, 0.05), 0.7),
        'madera': materialKit('baseMadera', 0.0),
        'atlasSynty': materialAtlas(),
        # Mobiliario de taller: armarios rojos de herramientas, gris del banco,
        # panel perforado y mangos.
        'rojoTaller': materialLiso('rojoTaller', (0.5, 0.04, 0.03), 0.4, 0.3),
        'grisBanco': materialLiso('grisBanco', (0.3, 0.32, 0.33), 0.45, 0.6),
        'panelPerforado': materialLiso('panelPerforado', (0.55, 0.57, 0.56), 0.6, 0.3),
        'mango': materialLiso('mango', (0.75, 0.06, 0.04), 0.5),
        'cromo': materialLiso('cromo', (0.8, 0.8, 0.82), 0.2, 1.0),
        'azulTornillo': materialLiso('azulTornillo', (0.05, 0.15, 0.4), 0.4, 0.4),
        # Polvorín: contenedores verde oliva, franja amarilla de explosivo,
        # placa de serie, rociadores rojos y pantalla del contador.
        'contenedor': materialLiso('contenedor', (0.17, 0.2, 0.12), 0.55, 0.35),
        'contenedorTapa': materialLiso('contenedorTapa', (0.12, 0.14, 0.09), 0.5, 0.4),
        'placaSerie': materialLiso('placaSerie', (0.85, 0.85, 0.8), 0.5),
        'letraNegra': materialLiso('letraNegra', (0.02, 0.02, 0.02), 0.6),
        'rojoIncendios': materialLiso('rojoIncendios', (0.6, 0.03, 0.02), 0.45, 0.2),
        'pantalla': materialLiso('pantalla', (0.01, 0.015, 0.012), 0.3),
        'textoPantalla': materialLiso('textoPantalla', (0.2, 1.0, 0.35), 0.4, 0.0, 6.0),
        'naranjaExplosivo': materialLiso('naranjaExplosivo', (0.95, 0.4, 0.02), 0.5),
        # Sala de control: suelo técnico, vidrio de los tabiques, mesas,
        # carcasas negras de monitores y servidores, tapizado y cables.
        'sueloTecnico': materialLiso('sueloTecnico', (0.2, 0.22, 0.24), 0.55, 0.1),
        'juntaSuelo': materialLiso('juntaSuelo', (0.05, 0.055, 0.06), 0.7),
        'vidrioSala': materialVidrio(),
        'mesaSala': materialLiso('mesaSala', (0.52, 0.55, 0.57), 0.5, 0.1),
        'carcasa': materialLiso('carcasa', (0.025, 0.027, 0.03), 0.45, 0.2),
        'armario': materialLiso('armario', (0.03, 0.033, 0.038), 0.4, 0.5),
        'tapizado': materialLiso('tapizado', (0.04, 0.045, 0.05), 0.85),
        'cableNaranja': materialLiso('cableNaranja', (0.8, 0.28, 0.05), 0.55),
        'cableAzul': materialLiso('cableAzul', (0.08, 0.25, 0.65), 0.55),
        'ledFijo': materialLiso('ledFijo', (0.2, 1.0, 0.4), 0.4, 0.0, 6.0),
    }


# Geometría ----------------------------------------------------------------

def mallaCaja(nombre, centro, tamano, material, coleccion):
    malla = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tamano), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    coleccion.objects.link(objeto)
    return objeto


def cajaOrientada(nombre, inicio, fin, ancho, alto, material, coleccion, arriba=(0, 0, 1), desplazamiento=(0, 0)):
    """Caja de `inicio` a `fin` con sección `ancho` x `alto`; `arriba` da la
    dirección del alto; `desplazamiento` mueve la sección (lado, arriba)."""
    a = Vector(inicio)
    b = Vector(fin)
    eje = (b - a)
    largo = eje.length
    x = eje.normalized()
    z = Vector(arriba)
    z = (z - x * z.dot(x)).normalized()
    y = z.cross(x)
    giro = Matrix((x, y, z)).transposed().to_4x4()
    centro = a + eje / 2 + y * desplazamiento[0] + z * desplazamiento[1]
    objeto = mallaCaja(nombre, (0, 0, 0), (largo, ancho, alto), material, coleccion)
    objeto.matrix_world = Matrix.Translation(centro) @ giro
    return objeto


def perfilI(nombre, inicio, fin, canto, ala, material, coleccion, arriba=(0, 0, 1)):
    """Viga en I de `inicio` a `fin`: alma en el plano de `arriba`."""
    piezas = [
        cajaOrientada(nombre + '_alma', inicio, fin, ESPESOR_ALMA, canto - 2 * ESPESOR_ALA, material, coleccion, arriba),
        cajaOrientada(nombre + '_alaA', inicio, fin, ala, ESPESOR_ALA, material, coleccion, arriba, (0, (canto - ESPESOR_ALA) / 2)),
        cajaOrientada(nombre + '_alaB', inicio, fin, ala, ESPESOR_ALA, material, coleccion, arriba, (0, -(canto - ESPESOR_ALA) / 2)),
    ]
    return unir(piezas, nombre)


def unir(objetos, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for objeto in objetos:
        objeto.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    bpy.ops.object.join()
    objetos[0].name = nombre
    return objetos[0]


def coleccionNueva(nombre):
    coleccion = bpy.data.collections.new(nombre)
    bpy.context.scene.collection.children.link(coleccion)
    return coleccion


def uvMundo(objeto, tamano=2.0):
    """UV por proyección de caja en coordenadas del mundo: la textura mide
    `tamano` m en cualquier cara (la misma escala en toda la nave)."""
    malla = objeto.data
    bm = bmesh.new()
    bm.from_mesh(malla)
    capa = bm.loops.layers.uv.verify()
    matriz = objeto.matrix_world
    giro = matriz.to_3x3()
    for cara in bm.faces:
        n = giro @ cara.normal
        ejes = (abs(n.x), abs(n.y), abs(n.z))
        dominante = ejes.index(max(ejes))
        for bucle in cara.loops:
            p = matriz @ bucle.vert.co
            if dominante == 0:
                u, v = p.y, p.z
            elif dominante == 1:
                u, v = p.x, p.z
            else:
                u, v = p.x, p.y
            bucle[capa].uv = (u / tamano, v / tamano)
    bm.to_mesh(malla)
    bm.free()


# La nave ------------------------------------------------------------------

def alturaCubierta(y):
    return ALERO + (ANCHO_NAVE / 2 - abs(y - Y_EJE)) * math.tan(PENDIENTE)


def yLado(lado, d):
    """y a `d` m hacia dentro de la fachada del lado `lado` (-1 sur, +1
    norte); `d` negativo, hacia fuera."""
    return Y_NORTE - d if lado > 0 else Y_SUR + d


def crearSuelo(m):
    col = coleccionNueva('suelo')
    suelo = mallaCaja('losa', (XCENTRO, Y_EJE, -0.15), (LARGO, ANCHO_NAVE, 0.3), m['hormigon'], col)
    uvMundo(suelo, 4.0)
    # Líneas de las plazas: a cada lado, de y = ±(ANCHO / 2) hacia dentro.
    lineas = []
    inicioX = 2.0
    for lado in (-1, 1):
        yBorde = lado * (ANCHO / 2 - PLAZA_FONDO)
        # En el lado +y, la sala de control ocupa las primeras plazas.
        primera = 3 if lado == 1 else 0
        for k in range(primera, PLAZAS_POR_LADO + 1):
            x = inicioX + k * PLAZA_ANCHO
            yc = lado * (ANCHO / 2 - PLAZA_FONDO / 2)
            lineas.append(mallaCaja('linea', (x, yc, 0.003), (0.12, PLAZA_FONDO, 0.006), m['lineaAmarilla'], col))
        x0 = inicioX + primera * PLAZA_ANCHO
        largoFila = (PLAZAS_POR_LADO - primera) * PLAZA_ANCHO
        lineas.append(mallaCaja('linea', (x0 + largoFila / 2, yBorde, 0.003), (largoFila, 0.12, 0.006), m['lineaAmarilla'], col))
    # Pasillo peatonal entre las dos zonas (x = 0) y borde de la zona de racks.
    for y in (-ANCHO / 2 + 1.0, ANCHO / 2 - 1.0):
        lineas.append(mallaCaja('linea', (-15, y, 0.003), (30, 0.12, 0.006), m['lineaAmarilla'], col))
    for x in (-0.75, 0.75):
        lineas.append(mallaCaja('linea', (x, 0, 0.003), (0.12, ANCHO - 2, 0.006), m['lineaAmarilla'], col))
    # Calle principal: bordes continuos y eje discontinuo, de punta a punta.
    for y in CALLE_Y:
        lineas.append(mallaCaja('lineaCalle', (XCENTRO, y, 0.004), (LARGO - 0.6, 0.15, 0.006), m['lineaAmarilla'], col))
    yEje = (CALLE_Y[0] + CALLE_Y[1]) / 2
    x = XMIN + 1.0
    while x + 3.0 < XMAX:
        lineas.append(mallaCaja('ejeCalle', (x + 1.5, yEje, 0.004), (3.0, 0.12, 0.006), m['lineaBlanca'], col))
        x += 6.0
    unir(lineas, 'lineasSuelo')


def crearPorticos(m):
    col = coleccionNueva('estructura')
    n = int(LARGO / ENTRE_PORTICOS)
    piezas = []
    for k in range(n + 1):
        x = XMIN + k * ENTRE_PORTICOS
        # Los pórticos de los testeros van por dentro de la fachada.
        x = max(XMIN + 0.3, min(XMAX - 0.3, x))
        for lado in (-1, 1):
            y = yLado(lado, PILAR_CANTO / 2)
            if lado < 0 and MUELLE_PORTON[0] - 0.4 < x < MUELLE_PORTON[1] + 0.4:
                # Sin pilar en el portón del muelle: el pórtico apoya en la
                # viga de transferencia de encima del hueco.
                piezas.append(perfilI('pilar', (x, y, MUELLE_PORTON_ALTO + 1.2), (x, y, ALERO), PILAR_CANTO, PILAR_ALA, m['estructura'], col, (0, 1, 0)))
            else:
                piezas.append(perfilI('pilar', (x, y, 0), (x, y, ALERO), PILAR_CANTO, PILAR_ALA, m['estructura'], col, (0, 1, 0)))
                piezas.append(mallaCaja('placa', (x, y, 0.02), (0.7, 0.8, 0.04), m['estructura'], col))
            # Dintel del alero a la cumbrera.
            inicio = (x, yLado(lado, PILAR_CANTO), ALERO - DINTEL_CANTO / 2)
            fin = (x, Y_EJE, CUMBRERA - DINTEL_CANTO / 2)
            piezas.append(perfilI('dintel', inicio, fin, DINTEL_CANTO, DINTEL_ALA, m['estructura'], col, (0, -lado * math.sin(PENDIENTE), math.cos(PENDIENTE))))
            # Cartela del nudo de esquina (refuerzo triangular, como chapa).
            cartela = cajaOrientada(
                'cartela',
                (x, yLado(lado, PILAR_CANTO), ALERO - DINTEL_CANTO - 0.9),
                (x, yLado(lado, PILAR_CANTO + 1.6), ALERO - DINTEL_CANTO + 0.15),
                ESPESOR_ALMA * 2, 0.35, m['estructura'], col, (0, -lado, 1))
            piezas.append(cartela)
    # Viga de transferencia sobre el portón del muelle, de pilar a pilar.
    xa = XMIN + math.floor((MUELLE_PORTON[0] - XMIN) / ENTRE_PORTICOS) * ENTRE_PORTICOS
    xb = XMIN + math.ceil((MUELLE_PORTON[1] - XMIN) / ENTRE_PORTICOS) * ENTRE_PORTICOS
    yv = yLado(-1, PILAR_CANTO / 2)
    piezas.append(perfilI('vigaTransferencia', (xa, yv, MUELLE_PORTON_ALTO + 0.6), (xb, yv, MUELLE_PORTON_ALTO + 0.6), 1.2, 0.4, m['estructura'], col, (0, 0, 1)))
    unir(piezas, 'porticos')
    # Correas (perfiles en C a lo largo de la nave) cada 1,5 m por faldón.
    correas = []
    paso = 1.5
    k = 0
    while True:
        d = 0.4 + k * paso
        if d > ANCHO_NAVE / 2 - 0.3:
            break
        for lado in (-1, 1):
            y = Y_EJE + lado * d
            z = alturaCubierta(y) + 0.1
            correas.append(mallaCaja('correa', (XCENTRO, y, z), (LARGO - 0.2, 0.08, 0.2), m['acero'], col))
        k += 1
    # Largueros de fachada cada 1,8 m por encima del zócalo.
    z = ZOCALO + 0.6
    while z < ALERO - 0.5:
        for lado in (-1, 1):
            tramos = [(XMIN + 0.1, XMAX - 0.1)]
            if lado < 0 and z < MUELLE_PORTON_ALTO + 0.2:
                tramos = [(XMIN + 0.1, MUELLE_PORTON[0] - 0.2), (MUELLE_PORTON[1] + 0.2, XMAX - 0.1)]
            for xa, xb in tramos:
                correas.append(mallaCaja('larguero', ((xa + xb) / 2, yLado(lado, 0.05), z), (xb - xa, 0.1, 0.16), m['acero'], col))
        z += 1.8
    # Arriostramiento en cruz de San Andrés en los recuadros de los extremos.
    for x0 in (XMIN + 0.3, XMAX - 0.3 - ENTRE_PORTICOS):
        for lado in (-1, 1):
            y = yLado(lado, 0.15)
            correas.append(cajaOrientada('cruz', (x0, y, ZOCALO), (x0 + ENTRE_PORTICOS, y, ALERO - 0.6), 0.04, 0.04, m['acero'], col))
            correas.append(cajaOrientada('cruz', (x0 + ENTRE_PORTICOS, y, ZOCALO), (x0, y, ALERO - 0.6), 0.04, 0.04, m['acero'], col))
    unir(correas, 'correas')


def crearCerramiento(m):
    col = coleccionNueva('cerramiento')
    piezas = []
    # Zócalo de hormigón y chapa encima, en los laterales.
    # Tramos de fachada a lo largo de x: la sur, cortada por el portón del
    # muelle (encima del hueco, solo chapa).
    def tramos(lado):
        if lado > 0:
            return [(XMIN, XMAX)]
        return [(XMIN, MUELLE_PORTON[0]), (MUELLE_PORTON[1], XMAX)]

    for lado in (-1, 1):
        y = yLado(lado, -0.1)
        for xa, xb in tramos(lado):
            piezas.append(mallaCaja('zocalo', ((xa + xb) / 2, y, ZOCALO / 2), (xb - xa, 0.2, ZOCALO), m['hormigon'], col))
    zocalo = unir(piezas, 'zocalo')
    uvMundo(zocalo, 4.0)
    chapas = []
    for lado in (-1, 1):
        y = yLado(lado, -0.03)
        for xa, xb in tramos(lado):
            chapas.append(mallaCaja('chapa', ((xa + xb) / 2, y, (ZOCALO + ALERO) / 2), (xb - xa, 0.04, ALERO - ZOCALO), m['chapa'], col))
        if lado < 0:
            xa, xb = MUELLE_PORTON
            chapas.append(mallaCaja('chapa', ((xa + xb) / 2, y, (MUELLE_PORTON_ALTO + ALERO) / 2), (xb - xa, 0.04, ALERO - MUELLE_PORTON_ALTO), m['chapa'], col))
    # Testeros: chapa hasta el alero (en tiras, dejando los huecos) y el
    # hastial triangular hasta la cumbrera. El de +x lleva los huecos de los
    # portones (5 x 5,5 m) y de la puerta (1 x 2,1 m).
    for extremo in (-1, 1):
        x = XMAX + 0.03 if extremo == 1 else XMIN - 0.03
        huecos = []
        if extremo == 1:
            huecos = [(-9.0, -4.0, 5.5), (-0.5, 0.5, 2.1), (4.0, 9.0, 5.5), PORTON_CALLE]
        y = Y_SUR
        for y0, y1, alto in huecos + [(Y_NORTE, Y_NORTE, 0)]:
            if y0 > y:
                chapas.append(mallaCaja('testero', (x, (y + y0) / 2, ALERO / 2), (0.04, y0 - y, ALERO), m['chapa'], col))
            if y1 > y0:
                chapas.append(mallaCaja('testero', (x, (y0 + y1) / 2, (alto + ALERO) / 2), (0.04, y1 - y0, ALERO - alto), m['chapa'], col))
            y = y1
        malla = bpy.data.meshes.new('hastial')
        bm = bmesh.new()
        puntos = [(Y_SUR, ALERO), (Y_NORTE, ALERO), (Y_EJE, CUMBRERA)]
        verts = [bm.verts.new((x, py, pz)) for py, pz in puntos]
        bm.faces.new(verts)
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.04)
        bm.to_mesh(malla)
        bm.free()
        hastial = bpy.data.objects.new('hastial', malla)
        hastial.data.materials.append(m['chapa'])
        col.objects.link(hastial)
        chapas.append(hastial)
    chapa = unir(chapas, 'chapaFachada')
    uvMundo(chapa, 2.0)
    # Cubierta: chapa por dentro y una franja de lucernario por faldón.
    cubierta = []
    for lado in (-1, 1):
        inicio = (0, Y_EJE, CUMBRERA + 0.22)
        fin = (0, yLado(lado, -0.3), ALERO + 0.22 - 0.3 * math.tan(PENDIENTE))
        largo = Vector(fin) - Vector(inicio)
        normal = (0, lado * math.sin(PENDIENTE), math.cos(PENDIENTE))
        faldon = cajaOrientada('faldon', (XMIN - 0.3, 0, 0), (XMAX + 0.3, 0, 0), largo.length, 0.04, m['chapa'], col, normal)
        faldon.location = Vector(inicio) + largo / 2 + Vector((XCENTRO, 0, 0))
        cubierta.append(faldon)
    techo = unir(cubierta, 'cubierta')
    uvMundo(techo, 2.0)
    lucernarios = []
    for lado in (-1, 1):
        for k in range(int(LARGO / (2 * ENTRE_PORTICOS))):
            xc = XMIN + ENTRE_PORTICOS * (2 * k + 1)
            yc = Y_EJE + lado * 8.0
            zc = alturaCubierta(yc) + 0.2
            luz = mallaCaja('lucernario', (xc, yc, zc), (ENTRE_PORTICOS - 1.0, 1.4, 0.03), m['lucernario'], col)
            luz.rotation_euler = (lado * -PENDIENTE, 0, 0)
            luz.location = (xc, yc, zc)
            lucernarios.append(luz)
    unir(lucernarios, 'lucernarios')


def cortar(objeto, huecos):
    for centro, tamano in huecos:
        cortador = mallaCaja('cortador', centro, tamano, objeto.data.materials[0], bpy.context.scene.collection)
        modificador = objeto.modifiers.new('hueco', 'BOOLEAN')
        modificador.operation = 'DIFFERENCE'
        modificador.object = cortador
        bpy.context.view_layer.objects.active = objeto
        bpy.ops.object.modifier_apply(modifier=modificador.name)
        bpy.data.objects.remove(cortador)


def crearPortones(m):
    col = coleccionNueva('portones')
    piezas = []
    x = XMAX - 0.05
    for yc in (-6.5, 6.5):
        # Portón seccional de 5 x 5,5 m, abierto: los paneles recogidos bajo
        # el techo, dentro (el robot pasa por debajo al anexo y al patio).
        for k in range(10):
            piezas.append(mallaCaja('panel', (x - 0.35 - k * 0.55, yc, 5.75), (0.53, 5.0, 0.06), m['portonPanel'], col))
        for lado in (-1, 1):
            piezas.append(mallaCaja('guiaTecho', (x - 2.9, yc + lado * 2.55, 5.8), (5.6, 0.06, 0.08), m['acero'], col))
        # Guías y marco con franjas de peligro.
        for lado in (-1, 1):
            piezas.append(mallaCaja('jamba', (x - 0.1, yc + lado * 2.6, 2.75), (0.2, 0.2, 5.5), m['peligro'], col))
        piezas.append(mallaCaja('dintelPorton', (x - 0.1, yc, 5.6), (0.2, 5.4, 0.2), m['estructura'], col))
    # Portón de la calle principal (7 x 6 m), abierto igual.
    y0, y1, alto = PORTON_CALLE
    yc = (y0 + y1) / 2
    for k in range(12):
        piezas.append(mallaCaja('panel', (x - 0.35 - k * 0.55, yc, alto + 0.25), (0.53, y1 - y0, 0.06), m['portonPanel'], col))
    for lado in (-1, 1):
        piezas.append(mallaCaja('guiaTecho', (x - 3.4, yc + lado * (y1 - y0 + 0.1) / 2, alto + 0.3), (6.6, 0.06, 0.08), m['acero'], col))
        piezas.append(mallaCaja('jamba', (x - 0.1, yc + lado * (y1 - y0 + 0.2) / 2, alto / 2), (0.2, 0.2, alto), m['peligro'], col))
    piezas.append(mallaCaja('dintelPorton', (x - 0.1, yc, alto + 0.1), (0.2, y1 - y0 + 0.4, 0.2), m['estructura'], col))
    # Puerta peatonal.
    piezas.append(mallaCaja('puerta', (x, 0, 1.05), (0.05, 1.0, 2.1), m['acero'], col))
    portones = unir(piezas, 'portones')
    uvMundo(portones, 1.0)


def crearRacks(m):
    col = coleccionNueva('racks')
    # Filas dobles a lo largo de x, dos a cada lado de un pasillo central de
    # 3,5 m alineado con el portón del polvorín; pasillos de 3,5 m entre
    # filas y contra los laterales.
    filas = []
    doble = 2 * RACK_FONDO + 0.2
    for k in range(2):
        desde = PASILLO / 2 + k * (doble + PASILLO)
        filas.append((desde, 2))
        filas.append((-desde - doble, 2))
    bastidores = []
    largueros = []
    xInicio = XMURO + 1.5
    huecos = 9
    for yFila, profundidad in filas:
        for p in range(profundidad):
            y0 = yFila + p * (RACK_FONDO + 0.2)
            for k in range(huecos + 1):
                x = xInicio + k * (RACK_HUECO + 0.1)
                for dy in (0, RACK_FONDO):
                    bastidores.append(mallaCaja('puntal', (x, y0 + dy, RACK_ALTO / 2), (0.1, 0.08, RACK_ALTO), m['rackAzul'], col))
                # Diagonales del bastidor.
                for j in range(4):
                    z0 = 0.3 + j * 1.4
                    bastidores.append(cajaOrientada('diagonal', (x, y0, z0), (x, y0 + RACK_FONDO, z0 + 1.4), 0.03, 0.04, m['rackAzul'], col))
                bastidores.append(mallaCaja('pie', (x, y0 + RACK_FONDO / 2, 0.01), (0.16, RACK_FONDO + 0.1, 0.02), m['acero'], col))
            for k in range(huecos):
                xc = xInicio + k * (RACK_HUECO + 0.1) + (RACK_HUECO + 0.1) / 2
                for z in RACK_NIVELES:
                    for dy in (0, RACK_FONDO):
                        largueros.append(mallaCaja('larguero', (xc, y0 + dy, z), (RACK_HUECO, 0.05, 0.12), m['rackNaranja'], col))
    unir(bastidores, 'racksBastidores')
    unir(largueros, 'racksLargueros')


def crearFocos(m):
    col = coleccionNueva('focos')
    piezas = []
    n = int(LARGO / ENTRE_PORTICOS)
    for k in range(n):
        x = XMIN + ENTRE_PORTICOS * (k + 0.5)
        # Tres filas sobre las zonas de trabajo y una sobre la calle principal.
        for y in (-9.0, 0.0, 9.0, (CALLE_Y[0] + CALLE_Y[1]) / 2):
            z = alturaCubierta(y) - 1.6
            piezas.append(mallaCaja('cable', (x, y, z + 0.8), (0.02, 0.02, 1.6), m['estructura'], col))
            piezas.append(mallaCaja('campana', (x, y, z), (0.55, 0.55, 0.18), m['estructura'], col))
            piezas.append(mallaCaja('difusor', (x, y, z - 0.1), (0.48, 0.48, 0.02), m['foco'], col))
            luz = bpy.data.lights.new('foco', 'AREA')
            luz.size = 0.5
            luz.energy = 2500
            luz.color = (1.0, 0.95, 0.86)
            objeto = bpy.data.objects.new('foco', luz)
            objeto.location = (x, y, z - 0.12)
            objeto.rotation_euler = (math.pi, 0, 0)
            col.objects.link(objeto)
    unir(piezas, 'lamparas')


# Fábrica de misiles --------------------------------------------------------

# Puestos de montaje (rectángulos de 12 x 4,5 m a lo largo de x, en dos
# filas), puente grúa de 25 t y su camino de rodadura a 7 m.
PUESTO_LARGO = 11.0
PUESTO_ANCHO = 4.5
PUESTOS_X = (-69.0, -57.5)  # 17-nov: hacia el fondo, sitio para la mesa de encajado
PUESTOS_Y = (-6.0, 6.0)
PORTON_FABRICA = 6.0
CARRIL_GRUA_Z = 7.0


def crearMuroCortafuegos(m, xMuro, nombre, cara=-1, huecos=None):
    """Muro de hormigón de 30 cm en x = `xMuro`, de suelo a cubierta, con sus
    huecos `(y0, y1, alto)` (por defecto un portón de 6 x 6 m en el centro y
    una puerta peatonal en y = +10). El muro queda hacia `cara` (-1, hacia
    -x) y el marco de los portones en la otra cara."""
    col = coleccionNueva(nombre)
    x = xMuro + cara * 0.2
    piezas = []
    huecos = huecos or [(-PORTON_FABRICA / 2, PORTON_FABRICA / 2, 6.0), (9.5, 10.5, 2.1)]
    y = Y_SUR
    for y0, y1, alto in huecos + [(Y_NORTE, Y_NORTE, 0)]:
        if y0 > y:
            piezas.append(mallaCaja('muro', (x, (y + y0) / 2, ALERO / 2), (0.3, y0 - y, ALERO), m['hormigon'], col))
        if y1 > y0:
            piezas.append(mallaCaja('muro', (x, (y0 + y1) / 2, (alto + ALERO) / 2), (0.3, y1 - y0, ALERO - alto), m['hormigon'], col))
        y = y1
    malla = bpy.data.meshes.new('muroHastial')
    bm = bmesh.new()
    puntos = [(Y_SUR, ALERO), (Y_NORTE, ALERO), (Y_EJE, CUMBRERA)]
    verts = [bm.verts.new((x - 0.15, py, pz)) for py, pz in puntos]
    bm.faces.new(verts)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.3)
    bm.to_mesh(malla)
    bm.free()
    hastial = bpy.data.objects.new('muroHastial', malla)
    hastial.data.materials.append(m['hormigon'])
    col.objects.link(hastial)
    piezas.append(hastial)
    muro = unir(piezas, nombre)
    uvMundo(muro, 4.0)
    # Marco de cada portón (más de 3 m) con franjas de peligro y su dintel
    # de acero; las puertas peatonales, con su hoja cerrada.
    marco = []
    for y0, y1, alto in huecos:
        if y1 - y0 > 3:
            for yj in (y0 - 0.1, y1 + 0.1):
                marco.append(mallaCaja('jamba', (x - cara * 0.2, yj, alto / 2), (0.12, 0.2, alto), m['peligro'], col))
            marco.append(mallaCaja('dintel', (x - cara * 0.2, (y0 + y1) / 2, alto + 0.1), (0.12, y1 - y0 + 0.4, 0.2), m['estructura'], col))
        else:
            marco.append(mallaCaja('puerta', (x, (y0 + y1) / 2, alto / 2), (0.06, y1 - y0, alto), m['acero'], col))
    unir(marco, nombre + 'Marco')


def rectanguloLineas(xc, yc, largo, ancho, grosor, material, coleccion):
    z = 0.009
    return [
        mallaCaja('linea', (xc, yc - ancho / 2, z), (largo, grosor, 0.006), material, coleccion),
        mallaCaja('linea', (xc, yc + ancho / 2, z), (largo, grosor, 0.006), material, coleccion),
        mallaCaja('linea', (xc - largo / 2, yc, z), (grosor, ancho, 0.006), material, coleccion),
        mallaCaja('linea', (xc + largo / 2, yc, z), (grosor, ancho, 0.006), material, coleccion),
    ]


def crearSueloFabrica(m):
    col = coleccionNueva('sueloFabrica')
    largo = XFABRICA - 0.35 - XMIN
    xc = XMIN + largo / 2
    mallaCaja('epoxi', (xc, 0, 0.003), (largo, ANCHO, 0.006), m['epoxi'], col)
    lineas = []
    # Pasillos peatonales junto a las paredes (blanco, como en las naves de
    # montaje) y el carril central desde el portón.
    for y in (-ANCHO / 2 + 1.5, ANCHO / 2 - 1.5):
        lineas.append(mallaCaja('linea', (xc, y, 0.009), (largo, 0.1, 0.006), m['lineaBlanca'], col))
    # Calles del robot grande entre la mesa de encajado, la pila de cajas y
    # los dos portones del polvorín.
    for y0, y1 in POLVORIN_PORTONES:
        for y in (y0 + 0.3, y1 - 0.3):
            lineas.append(mallaCaja('linea', (XFABRICA - 4.0, y, 0.009), (8.0, 0.12, 0.006), m['lineaAmarilla'], col))
    # Puestos de montaje: rectángulo amarillo y, dentro, el blanco del misil.
    for x in PUESTOS_X:
        for y in PUESTOS_Y:
            lineas += rectanguloLineas(x, y, PUESTO_LARGO, PUESTO_ANCHO, 0.15, m['lineaAmarilla'], col)
            lineas += rectanguloLineas(x, y, 9.0, 1.2, 0.06, m['lineaBlanca'], col)
    unir(lineas, 'lineasFabrica')
    # Toma de tierra: pletina de cobre por las paredes y un borne verde en
    # cada puesto (los soportes del misil se conectan a ella).
    tierra = []
    # (Al norte la fábrica da a la calle principal, sin pared: allí la
    # pletina va por el suelo, al borde del epoxi.)
    tierra.append(mallaCaja('pletina', (xc, -(ANCHO / 2 - 0.08), 0.35), (largo, 0.01, 0.05), m['cobre'], col))
    tierra.append(mallaCaja('pletina', (xc, ANCHO / 2 - 0.3, 0.008), (largo, 0.05, 0.01), m['cobre'], col))
    tierra.append(mallaCaja('pletina', (XMIN + 0.35, 0, 0.35), (0.01, ANCHO - 0.2, 0.05), m['cobre'], col))
    for x in PUESTOS_X:
        for y in PUESTOS_Y:
            bx = x + PUESTO_LARGO / 2 - 0.4
            by = y + (PUESTO_ANCHO / 2 - 0.4) * (1 if y > 0 else -1)
            tierra.append(mallaCaja('borne', (bx, by, 0.15), (0.12, 0.12, 0.3), m['tierra'], col))
            tierra.append(mallaCaja('placaBorne', (bx, by, 0.01), (0.3, 0.3, 0.02), m['cobre'], col))
    unir(tierra, 'tomaTierra')


def crearPuenteGrua(m):
    """Puente grúa birraíl de 25 t: carriles sobre ménsulas en los pilares
    (de XMIN a XFABRICA), viga cajón amarilla entre testeros, carro con polipasto
    y gancho."""
    col = coleccionNueva('puenteGrua')
    estructura = []
    yCarril = ANCHO / 2 - PILAR_CANTO - 0.35
    for lado in (-1, 1):
        y = lado * yCarril
        estructura.append(cajaOrientada('carril', (XMIN + 0.3, y, CARRIL_GRUA_Z), (XFABRICA - 0.4, y, CARRIL_GRUA_Z), 0.3, 0.6, m['estructura'], col))
        estructura.append(mallaCaja('rail', (XCENTRO_FABRICA, y, CARRIL_GRUA_Z + 0.33), (XFABRICA - 0.4 - XMIN - 0.3, 0.08, 0.06), m['acero'], col))
        k = 0
        while True:
            x = XMIN + k * ENTRE_PORTICOS
            if x > XFABRICA + 0.01:
                break
            x = max(XMIN + 0.3, min(XFABRICA - 0.4, x))
            # Ménsula: del pilar al carril, con su cartela. Al norte no hay
            # fachada (la nave sigue hasta la calle principal): columnas
            # propias del camino de rodadura, como en las naves con grúa.
            yPilar = lado * (ANCHO / 2 - PILAR_CANTO)
            if lado > 0:
                estructura.append(perfilI('columnaGrua', (x, yPilar + PILAR_CANTO / 2, 0), (x, yPilar + PILAR_CANTO / 2, CARRIL_GRUA_Z + 0.3), PILAR_CANTO, PILAR_ALA, m['estructura'], col, (0, 1, 0)))
                estructura.append(mallaCaja('placaColumnaGrua', (x, yPilar + PILAR_CANTO / 2, 0.02), (0.7, 0.8, 0.04), m['estructura'], col))
            estructura.append(cajaOrientada('mensula', (x, yPilar, CARRIL_GRUA_Z - 0.4), (x, y, CARRIL_GRUA_Z - 0.4), 0.3, 0.2, m['estructura'], col))
            estructura.append(cajaOrientada('cartelaMensula', (x, yPilar, CARRIL_GRUA_Z - 1.4), (x, y + lado * 0.1, CARRIL_GRUA_Z - 0.45), 0.03, 0.25, m['estructura'], col, (0, -lado, 1)))
            k += 1
    unir(estructura, 'caminoRodadura')
    # Lo que se mueve va como plantillas en el origen: el juego las pone
    # donde está la grúa (almacen/fabrica.lua). El puente (vigas y testeros)
    # en x = 0; el carro con el polipasto en x = y = 0; el gancho con su
    # motón, el balancín y las eslingas, con el punto donde llegan los cables
    # en el origen; los dos cables, de 1 m (el juego los estira).
    grua = []
    for dx in (-0.6, 0.6):
        grua.append(mallaCaja('vigaPuente', (dx, 0, CARRIL_GRUA_Z + 0.9), (0.5, 2 * yCarril + 0.4, 1.0), m['gruaAmarilla'], col))
        for k in range(12):
            yr = -yCarril + 0.6 + k * (2 * yCarril - 1.2) / 11
            grua.append(mallaCaja('rigidizador', (dx, yr, CARRIL_GRUA_Z + 0.9), (0.52, 0.04, 0.9), m['gruaAmarilla'], col))
    for lado in (-1, 1):
        grua.append(mallaCaja('testeroGrua', (0, lado * yCarril, CARRIL_GRUA_Z + 0.55), (3.2, 0.5, 0.45), m['gruaAmarilla'], col))
        for dx in (-1.2, 1.2):
            grua.append(cajaOrientada('ruedaGrua', (dx, lado * yCarril - 0.1, CARRIL_GRUA_Z + 0.45), (dx, lado * yCarril + 0.1, CARRIL_GRUA_Z + 0.45), 0.3, 0.3, m['acero'], col))
    unir(grua, 'plantillaGruaPuente')
    carro = [
        mallaCaja('carro', (0, 0, CARRIL_GRUA_Z + 1.6), (1.9, 1.6, 0.4), m['gruaAmarilla'], col),
        mallaCaja('polipasto', (0, 0, CARRIL_GRUA_Z + 1.1), (1.2, 0.7, 0.7), m['estructura'], col),
        mallaCaja('tambor', (0, 0, CARRIL_GRUA_Z + 1.1), (1.0, 0.5, 0.5), m['acero'], col),
    ]
    unir(carro, 'plantillaGruaCarro')
    cables = [mallaCaja('cable', (dx, 0, 0.5), (0.03, 0.03, 1.0), m['cable'], col) for dx in (-0.12, 0.12)]
    unir(cables, 'plantillaGruaCable')
    gancho = [
        mallaCaja('moton', (0, 0, -0.275), (0.45, 0.25, 0.55), m['gruaAmarilla'], col),
        mallaCaja('gancho', (0, 0, -0.75), (0.08, 0.12, 0.4), m['acero'], col),
        # Balancín (viga de izado) a lo largo de y, colgado del gancho con
        # dos eslingas en V, y una eslinga vertical en cada punta hasta la
        # banda de manejo del misil.
        mallaCaja('balancin', (0, 0, -GRUA_BALANCIN_Z), (0.16, 2 * GRUA_BANDA_Y + 0.3, 0.2), m['gruaAmarilla'], col),
    ]
    for s in (-1, 1):
        gancho.append(cajaOrientada('eslingaV', (0, 0, -0.95), (0, s * GRUA_BANDA_Y, -GRUA_BALANCIN_Z + 0.1), 0.05, 0.012, m['eslinga'], col, (1, 0, 0)))
        gancho.append(mallaCaja('eslinga', (0, s * GRUA_BANDA_Y, -(GRUA_BALANCIN_Z + GRUA_CUELGA - MISIL_RADIO) / 2), (0.012, 0.06, GRUA_CUELGA - MISIL_RADIO - GRUA_BALANCIN_Z), m['eslinga'], col))
    unir(gancho, 'plantillaGruaGancho')


# Grúa: el punto de los cables (arriba del motón) cuelga el eje del misil
# GRUA_CUELGA m más abajo; las bandas de manejo del misil, a ±GRUA_BANDA_Y
# de su centro.
GRUA_BALANCIN_Z = 1.15
GRUA_BANDA_Y = 1.6
GRUA_CUELGA = 1.874
GRUA_CABLE_Z = CARRIL_GRUA_Z + 0.8  # donde salen los cables del polipasto


XCENTRO_FABRICA = (XMIN + XFABRICA) / 2

# Misiles a medio montar. El del juego (assets/modelos3d/misil_synty4.glb, en
# décimas: x 10 a metros) mide 8,32 m con el origen en la cola; sus
# secciones: cola con aletas de 0 a 1,1 m, motor de 1,1 a 3,9, guiado y carga
# de 3,9 a 7,0 y ojiva de 7,0 a 8,32.
MISIL = os.path.join(RAIZ, 'assets', 'modelos3d', 'misil_synty4.glb')
MISIL_LARGO = 8.32
MISIL_RADIO = 0.224
X_MOTOR = 3.9
X_OJIVA = 7.0
X_OJIVA_CENTRO = 7.66
EJE_Z = 1.15
Z_GANCHO = 4.2
# Los puestos en el orden de la línea (en U): 1 y 2 en -y, 3 y 4 en +y.
ORDEN_PUESTOS = [
    (PUESTOS_X[0], PUESTOS_Y[0]),
    (PUESTOS_X[1], PUESTOS_Y[0]),
    (PUESTOS_X[1], PUESTOS_Y[1]),
    (PUESTOS_X[0], PUESTOS_Y[1]),
]


def importarMisil():
    """El misil del juego en metros, con el origen en la cola, a lo largo de +x."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=MISIL)
    nuevos = [o for o in bpy.data.objects if o not in antes]
    misil = next(o for o in nuevos if o.type == 'MESH')
    for o in nuevos:
        if o is not misil:
            bpy.data.objects.remove(o)
    misil.parent = None
    misil.scale = (10, 10, 10)
    bpy.ops.object.select_all(action='DESELECT')
    misil.select_set(True)
    bpy.context.view_layer.objects.active = misil
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return misil


def piezaMisil(base, nombre, coleccion, desde=None, hasta=None, sinAletas=False, material=None):
    """Copia del misil cortada con planos limpios en x = `desde` y x = `hasta`
    (en metros desde la cola), con el corte tapado; sin las aletas si se
    pide."""
    objeto = base.copy()
    objeto.data = base.data.copy()
    objeto.name = nombre
    coleccion.objects.link(objeto)
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    if sinAletas:
        aletas = []
        for cara in bm.faces:
            c = cara.calc_center_median()
            if esAleta(c.x, math.hypot(c.y, c.z)):
                aletas.append(cara)
        bmesh.ops.delete(bm, geom=aletas, context='FACES')
    for x, quitarFuera in ((hasta, True), (desde, False)):
        if x is None:
            continue
        geometria = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geometria, dist=0.0001, plane_co=(x, 0, 0), plane_no=(1, 0, 0), clear_outer=quitarFuera, clear_inner=not quitarFuera)
        # Tapa del corte: las aristas abiertas que quedan en el plano.
        borde = [e for e in bm.edges if e.is_boundary and all(abs(v.co.x - x) < 0.002 for v in e.verts)]
        if borde:
            bmesh.ops.holes_fill(bm, edges=borde, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(objeto.data)
    bm.free()
    if material:
        objeto.data.materials.clear()
        objeto.data.materials.append(material)
    return objeto


def anillo(nombre, x, y, z, radio, ancho, material, coleccion):
    """Brida de junta: cilindro corto a lo largo de x."""
    malla = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=radio, radius2=radio, depth=ancho)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    bmesh.ops.translate(bm, vec=Vector((x, y, z)), verts=bm.verts)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    coleccion.objects.link(objeto)
    for cara in objeto.data.polygons:
        cara.use_smooth = True
    return objeto


def esAleta(x, radio):
    return x < 1.1 and radio > MISIL_RADIO + 0.012


def colocar(objeto, puesto):
    """Misil centrado en el puesto, a la altura del eje de las cunas."""
    objeto.location = (puesto[0] - MISIL_LARGO / 2, puesto[1], EJE_Z)


def crearCunas(m, coleccion, puesto, posiciones=(1.6, 5.6)):
    """Cunas de montaje: base con ruedas, columna amarilla y silla con dos
    mejillas y goma, a la medida del misil; cable verde a la toma de tierra."""
    piezas = []
    bajo = EJE_Z - MISIL_RADIO
    for px in posiciones:
        x = puesto[0] - MISIL_LARGO / 2 + px
        y = puesto[1]
        piezas.append(mallaCaja('baseCuna', (x, y, 0.09), (0.6, 1.1, 0.1), m['estructura'], coleccion))
        for dy in (-0.45, 0.45):
            for dx in (-0.22, 0.22):
                piezas.append(mallaCaja('rueda', (x + dx, y + dy, 0.06), (0.14, 0.07, 0.12), m['goma'], coleccion))
        alto = bajo - 0.12 - 0.14
        piezas.append(mallaCaja('columna', (x, y, 0.14 + alto / 2), (0.16, 0.16, alto), m['gruaAmarilla'], coleccion))
        piezas.append(mallaCaja('silla', (x, y, bajo - 0.08), (0.24, 0.62, 0.08), m['gruaAmarilla'], coleccion))
        for lado in (-1, 1):
            piezas.append(mallaCaja('mejilla', (x, y + lado * (MISIL_RADIO + 0.05), EJE_Z - 0.12), (0.24, 0.04, 0.3), m['gruaAmarilla'], coleccion))
            piezas.append(mallaCaja('gomaLado', (x, y + lado * (MISIL_RADIO + 0.015), EJE_Z - 0.12), (0.22, 0.03, 0.22), m['goma'], coleccion))
        piezas.append(mallaCaja('gomaBajo', (x, y, bajo - 0.025), (0.22, 0.3, 0.03), m['goma'], coleccion))
    return piezas


def crearMisiles(m):
    """Cunas de los 4 puestos (fijas) y las 4 etapas del misil como
    plantillas (`plantillaMisil1`..4, a lo largo de y con el centro en el
    origen: el juego pone una en el puesto donde está el misil):
      1 cuerpo (motor y guiado), sin aletas ni pintar (ya llega a las dos
        bandas de manejo: la grúa lo coge desde el primer puesto);
      2 con las aletas;
      3 entero en imprimación (ya con la ojiva);
      4 entero con la pintura del juego.
    Cada una con las dos bandas de manejo amarillas donde se enganchan las
    eslingas de la grúa."""
    col = coleccionNueva('misiles')
    base = importarMisil()
    cunas = []
    for puesto in ORDEN_PUESTOS:
        cunas += crearCunas(m, col, puesto)
    unir(cunas, 'cunasYDetalles')
    etapas = [
        dict(hasta=X_OJIVA, sinAletas=True, material=m['imprimacion']),
        dict(hasta=X_OJIVA, material=m['imprimacion']),
        dict(material=m['imprimacion']),
        dict(),
    ]
    giro = Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation((-MISIL_LARGO / 2, 0, 0))
    for k, opciones in enumerate(etapas, start=1):
        o = piezaMisil(base, 'cuerpoMisil', col, **opciones)
        piezas = [o]
        for s in (-1, 1):
            banda = anillo('banda', MISIL_LARGO / 2 + s * GRUA_BANDA_Y, 0, 0, MISIL_RADIO + 0.018, 0.12, m['gruaAmarilla'], col)
            piezas.append(banda)
        for o in piezas:
            o.location = (0, 0, 0)
        unir(piezas, 'plantillaMisil%d' % k)
        bpy.data.objects['plantillaMisil%d' % k].data.transform(giro)
    bpy.data.objects.remove(base)


def exportarFabrica(ruta):
    """assets/almacen/fabrica.lua: lo que necesita la línea de montaje del
    juego (almacen/fabrica.lua)."""
    def f(v):
        return '%.3f' % v
    lineas = ['    puestos = {']
    for x, y in ORDEN_PUESTOS:
        lineas.append('        { %s, %s },' % (f(x), f(y)))
    lineas += [
        '    },',
        '    ejeZ = %s, -- alto del eje del misil en las cunas' % f(EJE_Z),
        '    cuelga = %s, -- del punto de los cables al eje del misil colgado' % f(GRUA_CUELGA),
        '    cableZ = %s, -- donde salen los cables del polipasto' % f(GRUA_CABLE_Z),
        '    ejeEnCaja = %s, -- del suelo de la caja al eje del misil en sus cunas' % f(CAJA_PATIN + 0.28 + MISIL_RADIO),
        '    puenteX = { %s, %s }, -- recorrido del puente' % (f(XMIN + 2.0), f(XFABRICA - 2.0)),
        # Mesa del menú de la fábrica: al acercarse, E lo abre.
        '    mesaMenu = { %s, %s, %s },' % (f(MESA_MENU[0]), f(MESA_MENU[1]), f(MESA_MENU[2])),
    ]
    with open(ruta, 'w') as archivo:
        archivo.write('-- Línea de montaje de misiles (tools/blender/almacen_interior.py --glb):\n')
        archivo.write('-- puestos en orden, alturas de la grúa. Metros, ejes del almacén.\n')
        archivo.write('return {\n' + '\n'.join(lineas) + '\n}\n')
    print('FABRICA', ruta)


# Bancos y estanterías ------------------------------------------------------

KIT = os.path.join(RAIZ, 'assets', 'base', 'kit_base.glb')
# Cajas de Synty (SIMPLE Military, comprado por el dueño): se sacan del zip a
# una carpeta temporal la primera vez.
ZIP_SYNTY = os.path.join(RAIZ, 'assets', 'source_packs', 'SIMPLE_Military_SourceFiles.zip')
CARPETA_SYNTY = os.path.join(bpy.app.tempdir or '/tmp', 'synty_almacen')


def importarKit(nombre, m, coleccion):
    """La pieza `nombre` del kit de la Base, en metros (el kit va en décimas)."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=KIT)
    nuevos = [o for o in bpy.data.objects if o not in antes]
    pieza = next(o for o in nuevos if o.name.split('.')[0] == nombre)
    for o in nuevos:
        if o is not pieza:
            bpy.data.objects.remove(o)
    for c in pieza.users_collection:
        c.objects.unlink(pieza)
    coleccion.objects.link(pieza)
    pieza.parent = None
    pieza.scale = (10, 10, 10)
    pieza.rotation_euler = (0, 0, 0)
    # La textura del atlas no va dentro del .glb: el material de la Base.
    pieza.data.materials.clear()
    pieza.data.materials.append(m['atlasSynty'])
    bpy.ops.object.select_all(action='DESELECT')
    pieza.select_set(True)
    bpy.context.view_layer.objects.active = pieza
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return pieza


def nivelesEstante(estante):
    """Alturas (m) de las baldas: caras horizontales grandes que miran arriba."""
    alturas = set()
    for cara in estante.data.polygons:
        if cara.normal.z > 0.95 and cara.area > 0.3:
            alturas.add(round(cara.center.z, 2))
    return sorted(alturas)


def importarSynty(nombre, m, coleccion, largo=0.7):
    import zipfile
    ruta = os.path.join(CARPETA_SYNTY, nombre + '.fbx')
    if not os.path.exists(ruta):
        os.makedirs(CARPETA_SYNTY, exist_ok=True)
        with zipfile.ZipFile(ZIP_SYNTY) as archivo:
            with archivo.open('SourceFiles/Fbx/' + nombre + '.fbx') as origen, open(ruta, 'wb') as destino:
                destino.write(origen.read())
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=ruta)
    nuevos = [o for o in bpy.data.objects if o not in antes]
    pieza = next(o for o in nuevos if o.type == 'MESH')
    for o in nuevos:
        if o is not pieza:
            bpy.data.objects.remove(o)
    for c in pieza.users_collection:
        c.objects.unlink(pieza)
    coleccion.objects.link(pieza)
    pieza.data.materials.clear()
    pieza.data.materials.append(m['atlasSynty'])
    bpy.ops.object.select_all(action='DESELECT')
    pieza.select_set(True)
    bpy.context.view_layer.objects.active = pieza
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Del tamaño real: lo más largo de la caja mide `largo` m.
    dimensiones = pieza.dimensions
    escala = largo / max(dimensiones.x, dimensiones.y)
    pieza.scale = (escala, escala, escala)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # Origen en el centro de la base.
    caja = [Vector(c) for c in pieza.bound_box]
    centro = Vector(((min(c.x for c in caja) + max(c.x for c in caja)) / 2, (min(c.y for c in caja) + max(c.y for c in caja)) / 2, min(c.z for c in caja)))
    pieza.data.transform(Matrix.Translation(-centro))
    return pieza


def girarEnSitio(objetos, x, y, rumbo):
    """Coloca piezas hechas alrededor del origen en (x, y) girando `rumbo`."""
    giro = Matrix.Rotation(rumbo, 4, 'Z')
    for objeto in objetos:
        objeto.matrix_world = Matrix.Translation((x, y, 0)) @ giro @ objeto.matrix_world


def crearBanco(m, coleccion):
    """Banco de trabajo de 2,0 x 0,8 m y 0,9 m de alto alrededor del origen,
    mirando a -y: patas de tubo, tablero de madera con canto de acero, balda
    baja, cajonera de 4 cajones a la derecha, panel perforado detrás con
    herramientas, tornillo de banco y lámpara."""
    piezas = []
    largo, fondo, alto = 2.0, 0.8, 0.9
    for px in (-largo / 2 + 0.05, largo / 2 - 0.05):
        for py in (-fondo / 2 + 0.05, fondo / 2 - 0.05):
            piezas.append(mallaCaja('pata', (px, py, alto / 2), (0.05, 0.05, alto - 0.04), m['grisBanco'], coleccion))
            piezas.append(mallaCaja('nivelador', (px, py, 0.012), (0.07, 0.07, 0.025), m['cable'], coleccion))
    for py in (-fondo / 2 + 0.05, fondo / 2 - 0.05):
        piezas.append(mallaCaja('travesano', (0, py, 0.15), (largo - 0.1, 0.04, 0.04), m['grisBanco'], coleccion))
    piezas.append(mallaCaja('balda', (0, 0, 0.18), (largo - 0.12, fondo - 0.12, 0.02), m['grisBanco'], coleccion))
    piezas.append(mallaCaja('canto', (0, 0, alto - 0.02), (largo + 0.02, fondo + 0.02, 0.04), m['grisBanco'], coleccion))
    # Cajonera bajo el lado derecho (+x).
    xc = largo / 2 - 0.35
    piezas.append(mallaCaja('cajonera', (xc, 0.02, 0.52), (0.55, fondo - 0.1, 0.62), m['rojoTaller'], coleccion))
    for k in range(4):
        z = 0.3 + k * 0.145
        piezas.append(mallaCaja('frenteCajon', (xc, -fondo / 2 + 0.035, z), (0.5, 0.012, 0.13), m['rojoTaller'], coleccion))
        piezas.append(mallaCaja('tirador', (xc, -fondo / 2 + 0.025, z + 0.03), (0.3, 0.02, 0.018), m['cromo'], coleccion))
    tablero = mallaCaja('tablero', (0, 0, alto + 0.02), (largo, fondo, 0.04), m['madera'], coleccion)
    uvMundo(tablero, 1.0)
    # Panel perforado detrás, con su marco y unas herramientas colgadas.
    yPanel = fondo / 2 - 0.02
    piezas.append(mallaCaja('panel', (0, yPanel, alto + 0.6), (largo, 0.02, 1.0), m['panelPerforado'], coleccion))
    for px in (-largo / 2, largo / 2):
        piezas.append(mallaCaja('marcoPanel', (px, yPanel, alto + 0.6), (0.04, 0.04, 1.04), m['grisBanco'], coleccion))
    piezas.append(mallaCaja('marcoPanel', (0, yPanel, alto + 1.1), (largo + 0.04, 0.04, 0.04), m['grisBanco'], coleccion))
    for k in range(7):
        x = -0.8 + k * 0.13
        largoLlave = 0.18 + 0.03 * k
        piezas.append(mallaCaja('llave', (x, yPanel - 0.02, alto + 0.95 - largoLlave / 2), (0.025, 0.01, largoLlave), m['cromo'], coleccion))
    for k in range(4):
        x = 0.15 + k * 0.16
        piezas.append(mallaCaja('mangoDestornillador', (x, yPanel - 0.03, alto + 0.85), (0.03, 0.03, 0.1), m['mango'], coleccion))
        piezas.append(mallaCaja('punta', (x, yPanel - 0.03, alto + 0.74), (0.008, 0.008, 0.13), m['cromo'], coleccion))
    piezas.append(mallaCaja('martillo', (0.85, yPanel - 0.03, alto + 0.8), (0.03, 0.03, 0.3), m['madera'], coleccion))
    piezas.append(mallaCaja('cabezaMartillo', (0.85, yPanel - 0.03, alto + 0.95), (0.11, 0.035, 0.035), m['grisBanco'], coleccion))
    # Tornillo de banco en la esquina izquierda.
    xt = -largo / 2 + 0.25
    piezas.append(mallaCaja('baseTornillo', (xt, -fondo / 2 + 0.12, alto + 0.07), (0.16, 0.2, 0.06), m['azulTornillo'], coleccion))
    for dy in (-0.05, 0.05):
        piezas.append(mallaCaja('mordaza', (xt, -fondo / 2 + 0.12 + dy, alto + 0.15), (0.18, 0.04, 0.1), m['azulTornillo'], coleccion))
    piezas.append(cajaOrientada('husillo', (xt, -fondo / 2 + 0.02, alto + 0.12), (xt, -fondo / 2 - 0.12, alto + 0.12), 0.025, 0.025, m['cromo'], coleccion))
    piezas.append(mallaCaja('palanca', (xt, -fondo / 2 - 0.12, alto + 0.12), (0.2, 0.015, 0.015), m['cromo'], coleccion))
    # Lámpara de brazo sobre el lado izquierdo del panel.
    piezas.append(cajaOrientada('brazo', (-0.3, yPanel - 0.03, alto + 1.0), (-0.3, -0.05, alto + 0.75), 0.02, 0.02, m['grisBanco'], coleccion))
    piezas.append(mallaCaja('pantalla', (-0.3, -0.08, alto + 0.7), (0.18, 0.12, 0.08), m['grisBanco'], coleccion))
    piezas.append(mallaCaja('bombilla', (-0.3, -0.08, alto + 0.655), (0.14, 0.08, 0.01), m['foco'], coleccion))
    return piezas + [tablero]


def crearCarroHerramientas(m, coleccion):
    """Carro de herramientas rojo de 0,7 x 0,45 x 1,0 m con 6 cajones,
    asa lateral y ruedas, alrededor del origen, mirando a -y."""
    piezas = []
    ancho, fondo, alto = 0.7, 0.45, 1.0
    piezas.append(mallaCaja('cuerpo', (0, 0, 0.12 + (alto - 0.12) / 2), (ancho, fondo, alto - 0.12), m['rojoTaller'], coleccion))
    piezas.append(mallaCaja('tapa', (0, 0, alto + 0.01), (ancho + 0.02, fondo + 0.02, 0.02), m['cable'], coleccion))
    for k in range(6):
        z = 0.2 + k * 0.13
        piezas.append(mallaCaja('cajon', (0, -fondo / 2 - 0.004, z + 0.06), (ancho - 0.06, 0.008, 0.115), m['rojoTaller'], coleccion))
        piezas.append(mallaCaja('tirador', (0, -fondo / 2 - 0.015, z + 0.1), (ancho - 0.12, 0.015, 0.012), m['cromo'], coleccion))
    piezas.append(cajaOrientada('asa', (ancho / 2 + 0.06, -0.15, alto - 0.08), (ancho / 2 + 0.06, 0.15, alto - 0.08), 0.025, 0.025, m['cromo'], coleccion))
    for dy in (-0.15, 0.15):
        piezas.append(mallaCaja('soporteAsa', (ancho / 2 + 0.03, dy, alto - 0.08), (0.06, 0.02, 0.02), m['cromo'], coleccion))
    for px in (-ancho / 2 + 0.06, ancho / 2 - 0.06):
        for py in (-fondo / 2 + 0.06, fondo / 2 - 0.06):
            piezas.append(mallaCaja('horquillaRueda', (px, py, 0.1), (0.04, 0.05, 0.04), m['grisBanco'], coleccion))
            piezas.append(cajaOrientada('rueda', (px - 0.015, py, 0.05), (px + 0.015, py, 0.05), 0.09, 0.09, m['goma'], coleccion))
    return piezas


# Mesa del menú de la fábrica (2026-11-17): el banco del puesto 1. Al
# acercarse sale «E — Fábrica de misiles» y con E se abre el menú para pedir
# misiles o parar la línea (almacen/menu_fabrica.lua).
MESA_MENU = (-72.0, -9.55, 0.94)


# Lo que va junto a cada puesto, hacia la pared: banco, carro de
# herramientas y estantería de piezas del kit con cajas de Synty.
CAJAS_ESTANTE = ('SM_Prop_Metal_Box_01', 'SM_Prop_Ammo_Box_02', 'SM_Prop_Metal_Box_03', 'SM_Prop_Ammo_Box_04')


def crearMobiliario(m):
    col = coleccionNueva('mobiliario')
    for k, (px, py) in enumerate(ORDEN_PUESTOS):
        lado = 1 if py > 0 else -1
        # Mirando al puesto (el banco mira a -y en su origen).
        rumbo = math.pi if lado < 0 else 0.0
        yBanco = py + lado * (PUESTO_ANCHO / 2 + 1.3)
        banco = crearBanco(m, col)
        girarEnSitio(banco, px - 3.0, yBanco, rumbo)
        carro = crearCarroHerramientas(m, col)
        girarEnSitio(carro, px - 1.3, yBanco + lado * 0.1, rumbo)
        unir(banco + carro, 'puesto%dBanco' % (k + 1))
        estante = importarKit('estanteria', m, col)
        xEstante = px + 2.6
        yEstante = py + lado * (PUESTO_ANCHO / 2 + 1.5)
        if px == PUESTOS_X[1]:
            # Los puestos de al lado de las mesas de encajado: la estantería
            # quedaba pegada a la mesa y la tapa de la caja, al abrirse, la
            # atravesaba (el dueño, 17-nov). Va 3,6 m más hacia la pared, fuera del largo de la caja.
            yEstante += lado * 3.6 + (0.25 if lado > 0 else 0.0)  # al norte la mesa llega hasta 12,0
        estante.location = (xEstante, yEstante, 0)
        # El kit tiene el origen en la esquina de la celda: el centro real.
        esquinas = [estante.location + Vector(c) for c in estante.bound_box]
        xEstante = (min(c.x for c in esquinas) + max(c.x for c in esquinas)) / 2
        yEstante = (min(c.y for c in esquinas) + max(c.y for c in esquinas)) / 2
        # Cajas de Synty en las baldas (a su tamaño real) y dos en el suelo.
        anchoEstante = estante.dimensions.x
        niveles = nivelesEstante(estante)
        n = 0
        for nivel, z in enumerate(niveles[:3]):
            for j in range(3):
                if (k + nivel + j) % 4 == 3:
                    continue
                nombre = CAJAS_ESTANTE[(k + nivel * 3 + j) % len(CAJAS_ESTANTE)]
                caja = importarSynty(nombre, m, col, 0.75 if 'Metal' in nombre else 0.6)
                caja.location = (xEstante + (j - 1) * anchoEstante / 3.3, yEstante, z + 0.005)
                caja.rotation_euler = (0, 0, 0.05 * (j - 1) * lado)
                n += 1
        for j in range(2):
            caja = importarSynty(CAJAS_ESTANTE[(k + j) % 2], m, col, 0.75)
            caja.location = (px + 0.6 + j * 0.85, py + lado * (PUESTO_ANCHO / 2 + 0.7), 0)
            caja.rotation_euler = (0, 0, 0.12 * (j - 0.5))


# Polvorín de misiles --------------------------------------------------------

# Polvorín nuevo (plano aprobado por el dueño el 2026-11-17), en el sitio de
# los racks azules de la nave, de XFABRICA a x = -3: el robot grande lleva
# cada caja atravesada con sus dos garras, así que las cajas van paralelas a
# los pasillos, en racks cantiléver (los de las cargas largas: tubos,
# perfiles). Tres filas a lo largo de x (una en cada pared y una doble en
# medio) con dos pasillos de 11,4 m entre ellas; cada fila con 4 bahías de
# 9,6 m y 4 niveles: 64 huecos. Se entra desde la fábrica por dos portones
# blindados de 10,8 m (puertas enrollables, subidas). Cada caja llena es un
# objeto suelto del juego (almacen/objetos: `contenedorMisil`), que el
# robot grande mueve; aquí solo los huecos (assets/almacen/polvorin.lua).
POLVORIN_X1 = -3.0  # muro del lado de la nave
POLVORIN_PORTONES = ((-12.4, -1.6), (1.6, 12.4))  # y de los dos portones del muro de la fábrica
POLVORIN_PORTON_ALTO = 6.0
# Muelle de misiles (17-nov): portón blindado de 10,8 m en la fachada sur
# del polvorín (donde estaba la última bahía de la fila sur: 60 huecos) y
# patio exterior para 3 semirremolques con 4 cajas cada uno.
MUELLE_PORTON = (-14.4, -3.6)  # x del hueco en la fachada sur (y = Y_SUR)
MUELLE_PORTON_ALTO = 6.0
MUELLE = (-62.0, 0.0, -42.0)  # x0, x1, y del fondo del patio del muelle
MUELLE_MANIOBRA = 12.0  # m de calle de maniobra pegada a la fachada
MUELLE_CAMIONES_X = (-50.0, -30.0, -9.0)  # centro de la plataforma de cada camión
MUELLE_CAMION_Y = -30.5
POLVORIN_BAHIAS = 4
POLVORIN_BAHIA = 9.6
POLVORIN_X0_RACKS = XFABRICA + 1.0
POLVORIN_NIVELES = (0.3, 1.4, 2.5, 3.6)  # alto de los brazos
POLVORIN_BRAZO = 1.3  # largo de los brazos desde la cara de la columna
POLVORIN_COLUMNA = (0.3, 0.25)  # canto y ala del perfil de las columnas
POLVORIN_FILA_PARED = ANCHO / 2 - 0.8  # |y| de las columnas de las filas de pared
CONTENEDOR_LARGO = 9.0
CONTENEDOR_LADO = 0.85
# La mesa de encajado y la pila de cajas vacías, en la fábrica junto a los
# portones (las cajas a lo largo de y, como las lleva el robot).
ENCAJADO_X = XFABRICA - 5.6  # 17-nov: sitio para que el robot grande gire entre la mesa y el muro
ENCAJADO_ALTO = 0.8  # alto del tablero de la mesa


def texto(nombre, contenido, tamano, material, coleccion, ubicacion, giro):
    curva = bpy.data.curves.new(nombre, 'FONT')
    curva.body = contenido
    curva.size = tamano
    curva.align_x = 'CENTER'
    curva.align_y = 'CENTER'
    curva.extrude = 0.004
    objeto = bpy.data.objects.new(nombre, curva)
    objeto.data.materials.append(material)
    objeto.location = ubicacion
    objeto.rotation_euler = giro
    coleccion.objects.link(objeto)
    return objeto


def tornillo(nombre, centro, normal, radio, material, coleccion):
    """Tornillo de cabeza hexagonal con arandela, mirando hacia `normal`."""
    n = Vector(normal).normalized()
    giro = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    piezas = []
    for r, alto, lados, dz in ((radio * 1.5, radio * 0.3, 16, radio * 0.15), (radio, radio * 0.8, 6, radio * 0.7)):
        malla = bpy.data.meshes.new(nombre)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=r, radius2=r, depth=alto)
        bmesh.ops.translate(bm, vec=Vector((0, 0, dz)), verts=bm.verts)
        bm.to_mesh(malla)
        bm.free()
        objeto = bpy.data.objects.new(nombre, malla)
        objeto.data.materials.append(material)
        coleccion.objects.link(objeto)
        objeto.matrix_world = Matrix.Translation(Vector(centro)) @ giro
        piezas.append(objeto)
    return piezas


CAJA_PATIN = 0.06  # alto de los patines: el cuerpo empieza ahí
CAJA_BISAGRA = (-CONTENEDOR_LADO / 2 - 0.02, CAJA_PATIN + CONTENEDOR_LADO / 2)  # x, z del eje de la tapa


def crearContenedorAbierto(m, coleccion, nombre, x, y, z, abierta=math.radians(115)):
    """Caja de un misil (concha), a lo largo de y, con su suelo (los
    patines) en z: la mitad de abajo con las dos cunas de goma donde se
    apoya el misil, patines y franja de explosivo; la de arriba (`nombre` +
    'Tapa') girada `abierta` sobre las 4 bisagras del lado -x, con los 6
    cierres de palanca y los cáncamos de izado. Con abierta = 0, cerrada."""
    largo, lado, g = CONTENEDOR_LARGO - 0.2, CONTENEDOR_LADO, 0.03
    mitad = lado / 2
    z = z + CAJA_PATIN
    abajo = [
        mallaCaja('fondo', (x, y, z + g / 2), (lado, largo, g), m['contenedor'], coleccion),
        mallaCaja('costado', (x - mitad + g / 2, y, z + mitad / 2), (g, largo, mitad), m['contenedor'], coleccion),
        mallaCaja('costado', (x + mitad - g / 2, y, z + mitad / 2), (g, largo, mitad), m['contenedor'], coleccion),
        mallaCaja('junta', (x, y - largo / 2 + 0.01, z + mitad), (lado, 0.02, 0.02), m['goma'], coleccion),
    ]
    for extremo in (-1, 1):
        ye = y + extremo * (largo / 2 + 0.02)
        abajo.append(mallaCaja('tapaExtremo', (x, ye, z + mitad / 2), (lado + 0.06, 0.16, mitad), m['contenedorTapa'], coleccion))
    # Nervios por fuera (la caja abierta está hueca: nada cruza por dentro).
    for k in range(5):
        yn = y - largo / 2 + 0.9 + k * (largo - 1.8) / 4
        for s in (-1, 1):
            abajo.append(mallaCaja('nervio', (x + s * (mitad + 0.01), yn, z + mitad / 2), (0.02, 0.08, mitad), m['contenedorTapa'], coleccion))
        abajo.append(mallaCaja('nervio', (x, yn, z - 0.01), (lado + 0.04, 0.08, 0.02), m['contenedorTapa'], coleccion))
    # Cunas: media luna de goma sobre su soporte, a 1/4 y 3/4 del largo.
    for dy in (-largo / 4, largo / 4):
        abajo.append(mallaCaja('soporteCuna', (x, y + dy, z + 0.12), (lado - 2 * g, 0.2, 0.18), m['acero'], coleccion))
        for dx in (-0.16, 0.16):
            abajo.append(mallaCaja('cuna', (x + dx, y + dy, z + 0.24), (0.14, 0.2, 0.08), m['goma'], coleccion))
        abajo.append(mallaCaja('patin', (x, y + dy, z - CAJA_PATIN / 2), (lado + 0.02, 0.3, CAJA_PATIN), m['contenedorTapa'], coleccion))
    abajo.append(mallaCaja('franja', (x, y + largo / 2 - 0.6, z + mitad / 2), (lado + 0.005, 0.12, mitad), m['naranjaExplosivo'], coleccion))
    abajo.append(mallaCaja('placa', (x, y + largo / 2 + 0.105, z + 0.25), (0.5, 0.01, 0.22), m['placaSerie'], coleccion))
    for k in range(4):
        yb = y - largo / 2 + 1.4 + k * (largo - 2.8) / 3
        abajo.append(mallaCaja('bisagra', (x - mitad - 0.02, yb, z + mitad), (0.04, 0.22, 0.09), m['acero'], coleccion))
    cuerpo = unir(abajo, nombre)
    # La tapa: hecha cerrada y girada sobre el eje de las bisagras.
    arriba = [
        mallaCaja('techo', (x, y, z + lado - g / 2), (lado, largo, g), m['contenedor'], coleccion),
        mallaCaja('costadoTapa', (x - mitad + g / 2, y, z + mitad + mitad / 2), (g, largo, mitad), m['contenedor'], coleccion),
        mallaCaja('costadoTapa', (x + mitad - g / 2, y, z + mitad + mitad / 2), (g, largo, mitad), m['contenedor'], coleccion),
    ]
    for k in range(5):
        yn = y - largo / 2 + 0.9 + k * (largo - 1.8) / 4
        for s in (-1, 1):
            arriba.append(mallaCaja('nervio', (x + s * (mitad + 0.01), yn, z + mitad + mitad / 2), (0.02, 0.08, mitad), m['contenedorTapa'], coleccion))
        arriba.append(mallaCaja('nervio', (x, yn, z + lado + 0.01), (lado + 0.04, 0.08, 0.02), m['contenedorTapa'], coleccion))
    for extremo in (-1, 1):
        ye = y + extremo * (largo / 2 + 0.02)
        arriba.append(mallaCaja('tapaExtremo', (x, ye, z + mitad + mitad / 2), (lado + 0.06, 0.16, mitad), m['contenedorTapa'], coleccion))
    for k in range(6):
        yb = y - largo / 2 + 0.75 + k * (largo - 1.5) / 5
        arriba.append(mallaCaja('cierre', (x + mitad + 0.02, yb, z + mitad + 0.05), (0.035, 0.08, 0.14), m['acero'], coleccion))
    for dy in (-largo / 4, largo / 4):
        arriba.append(mallaCaja('cancamo', (x, y + dy, z + lado + 0.04), (0.06, 0.12, 0.08), m['acero'], coleccion))
    arriba.append(mallaCaja('franja', (x, y + largo / 2 - 0.6, z + mitad + mitad / 2), (lado + 0.005, 0.12, mitad), m['naranjaExplosivo'], coleccion))
    tapa = unir(arriba, nombre + 'Tapa')
    bisagra = Vector((x - mitad - 0.02, y, z + mitad))
    tapa.data.transform(Matrix.Translation(bisagra) @ Matrix.Rotation(-abierta, 4, 'Y') @ Matrix.Translation(-bisagra))
    return cuerpo, tapa


def crearRackCantilever(m, col, yColumna, caras, bahias=None):
    """Una fila de racks cantiléver a lo largo de x con las columnas en
    `yColumna` y brazos hacia `caras` (+1, -1 o los dos). Por bahía, tres
    columnas en I con su base atornillada al suelo, brazos con almohadilla de
    goma y tope amarillo en la punta, atornillados a la columna, y
    arriostrado en cruz entre columnas. Devuelve los huecos (x, y, z de la
    base de la caja)."""
    piezas = []
    canto, ala = POLVORIN_COLUMNA
    alto = POLVORIN_NIVELES[-1] + 1.2
    huecos = []
    columnas = []
    for b in (bahias if bahias is not None else range(POLVORIN_BAHIAS)):
        xc = POLVORIN_X0_RACKS + b * POLVORIN_BAHIA + POLVORIN_BAHIA / 2
        for dx in (-3.2, 0.0, 3.2):
            columnas.append(xc + dx)
        for z in POLVORIN_NIVELES:
            for cara in caras:
                yCaja = yColumna + cara * (canto / 2 + POLVORIN_BRAZO - CONTENEDOR_LADO / 2 - 0.12)
                huecos.append((xc, yCaja, z + 0.03, cara))
    for xk in columnas:
        piezas.append(perfilI('columna', (xk, yColumna, 0), (xk, yColumna, alto), canto, ala, m['rackAzul'], col, (0, 1, 0)))
        # Base: pletina a lo largo de los brazos, cartelas y 4 pernos de
        # anclaje por cara.
        largoBase = canto + sum(1.0 for _ in caras) * 0.9
        yBase = yColumna + (sum(caras) * 0.45)
        piezas.append(mallaCaja('base', (xk, yBase, 0.015), (ala + 0.2, largoBase, 0.03), m['rackAzul'], col))
        for cara in caras:
            piezas.append(cajaOrientada('cartelaBase', (xk, yColumna + cara * canto / 2, 0.03), (xk, yColumna + cara * (canto / 2 + 0.7), 0.03), 0.012, 0.25, m['rackAzul'], col, (0, 0, 1), (0, 0.125)))
            for dxb in (-0.13, 0.13):
                for dyb in (0.3, 0.7):
                    piezas += tornillo('anclaje', (xk + dxb, yColumna + cara * (canto / 2 + dyb), 0.03), (0, 0, 1), 0.016, m['acero'], col)
            for z in POLVORIN_NIVELES:
                y0 = yColumna + cara * canto / 2
                y1 = y0 + cara * POLVORIN_BRAZO
                # Brazo: perfil en I tumbado; placa de unión atornillada.
                piezas.append(perfilI('brazo', (xk, y0, z - 0.09), (xk, y1, z - 0.09), 0.16, 0.1, m['rackAzul'], col, (0, 0, 1)))
                piezas.append(mallaCaja('placaBrazo', (xk, y0 + cara * 0.012, z - 0.12), (ala + 0.04, 0.024, 0.34), m['rackAzul'], col))
                for dxb in (-0.09, 0.09):
                    for dzb in (-0.25, 0.01):
                        piezas += tornillo('tornilloBrazo', (xk + dxb, y0 + cara * 0.026, z + dzb), (0, cara, 0), 0.012, m['acero'], col)
                piezas.append(mallaCaja('almohadilla', (xk, (y0 + y1) / 2 + cara * 0.05, z - 0.004), (0.12, POLVORIN_BRAZO - 0.25, 0.012), m['goma'], col))
                piezas.append(mallaCaja('tope', (xk, y1 - cara * 0.04, z + 0.05), (0.1, 0.06, 0.12), m['gruaAmarilla'], col))
    # Arriostrado: en cruz entre las columnas de cada bahía, en el plano de
    # las columnas.
    for k in range(len(columnas) - 1):
        a, b = columnas[k], columnas[k + 1]
        if b - a > 4:
            continue
        for za, zb in ((0.4, alto - 0.4), (alto - 0.4, 0.4)):
            piezas.append(cajaOrientada('cruz', (a, yColumna, za), (b, yColumna, zb), 0.05, 0.05, m['rackAzul'], col))
        piezas.append(cajaOrientada('travesano', (a, yColumna, alto - 0.1), (b, yColumna, alto - 0.1), 0.12, 0.12, m['rackAzul'], col))
    unir(piezas, 'racksPolvorin')
    return huecos


def crearPolvorin(m):
    col = coleccionNueva('polvorin')
    # Muro del lado de la nave, con una puerta peatonal; el de la fábrica
    # (con los dos portones) lo pone crearFabrica.
    crearMuroCortafuegos(m, POLVORIN_X1, 'muroPolvorin', cara=1, huecos=[(9.5, 10.5, 2.1), PORTON_CALLE])
    # Muro norte (y = 15), de suelo a cubierta: separa el polvorín de la
    # calle principal, que pasa por detrás.
    yMuro = ANCHO / 2 + 0.15
    muroNorte = mallaCaja('muroNorte', ((XFABRICA + POLVORIN_X1) / 2, yMuro, alturaCubierta(yMuro + 0.15) / 2), (POLVORIN_X1 - XFABRICA - 0.3, 0.3, alturaCubierta(yMuro + 0.15)), m['hormigon'], col)
    uvMundo(muroNorte, 4.0)
    x0 = XFABRICA + 0.1
    x1 = POLVORIN_X1 - 0.1
    xc = (x0 + x1) / 2
    largoSala = x1 - x0
    # Suelo y líneas de los dos pasillos.
    suelo = mallaCaja('sueloPolvorin', (xc, 0, 0.003), (largoSala, ANCHO - 0.6, 0.006), m['epoxi'], col)
    uvMundo(suelo, 4.0)
    lineas = []
    yPared = POLVORIN_FILA_PARED - POLVORIN_COLUMNA[0] / 2 - POLVORIN_BRAZO
    yMedio = POLVORIN_COLUMNA[0] / 2 + POLVORIN_BRAZO
    for s in (-1, 1):
        for y in (s * (yPared - 0.15), s * (yMedio + 0.15)):
            lineas.append(mallaCaja('linea', (xc, y, 0.009), (largoSala - 0.4, 0.12, 0.006), m['lineaAmarilla'], col))
        # Flecha de marcha atrás del robot en cada pasillo.
        for k in range(4):
            xf = x0 + 5 + k * 9.0
            lineas.append(cajaOrientada('flecha', (xf, s * 7.0 - 0.5, 0.009), (xf + 0.8, s * 7.0, 0.009), 0.15, 0.006, m['lineaBlanca'], col))
            lineas.append(cajaOrientada('flecha', (xf, s * 7.0 + 0.5, 0.009), (xf + 0.8, s * 7.0, 0.009), 0.15, 0.006, m['lineaBlanca'], col))
    unir(lineas, 'lineasPolvorin')
    # Racks: filas de pared (brazos hacia dentro) y la doble del medio.
    huecos = []
    # (La fila sur sin su última bahía: por ahí sale el robot al muelle.)
    huecos += crearRackCantilever(m, col, -POLVORIN_FILA_PARED, (1,), range(POLVORIN_BAHIAS - 1))
    huecos += crearRackCantilever(m, col, 0.0, (-1, 1))
    huecos += crearRackCantilever(m, col, POLVORIN_FILA_PARED, (-1,))
    # Orden de llenado: de abajo arriba, de la fábrica hacia la nave.
    huecos.sort(key=lambda h: (round(h[2], 2), round(h[0], 2), round(h[1], 2)))
    POLVORIN_HUECOS[:] = huecos
    # Las cajas las pone el juego (objetos sueltos que mueve el robot): aquí
    # solo los huecos, que van a assets/almacen/polvorin.lua.
    # Puertas blindadas enrollables (subidas) en los dos portones: cajón
    # del tambor encima y guías a los lados, por la cara del polvorín.
    puertas = []
    xp = XFABRICA + 0.35
    for y0, y1 in POLVORIN_PORTONES:
        yc = (y0 + y1) / 2
        puertas.append(mallaCaja('cajonPuerta', (xp + 0.2, yc, POLVORIN_PORTON_ALTO + 0.45), (0.7, y1 - y0 + 0.5, 0.7), m['portonPanel'], col))
        for yg in (y0 - 0.12, y1 + 0.12):
            puertas.append(mallaCaja('guiaPuerta', (xp, yg, POLVORIN_PORTON_ALTO / 2), (0.2, 0.14, POLVORIN_PORTON_ALTO), m['acero'], col))
        puertas.append(mallaCaja('bordePuerta', (xp + 0.2, yc, POLVORIN_PORTON_ALTO - 0.02), (0.12, y1 - y0, 0.1), m['peligro'], col))
    # La del muelle, en la fachada sur.
    x0p, x1p = MUELLE_PORTON
    xcp = (x0p + x1p) / 2
    yp = Y_SUR + 0.35
    puertas.append(mallaCaja('cajonPuerta', (xcp, yp + 0.2, MUELLE_PORTON_ALTO + 0.45), (x1p - x0p + 0.5, 0.7, 0.7), m['portonPanel'], col))
    for xg in (x0p - 0.12, x1p + 0.12):
        puertas.append(mallaCaja('guiaPuerta', (xg, yp, MUELLE_PORTON_ALTO / 2), (0.14, 0.2, MUELLE_PORTON_ALTO), m['acero'], col))
        puertas.append(mallaCaja('jambaMuelle', (xg, Y_SUR - 0.05, MUELLE_PORTON_ALTO / 2), (0.2, 0.12, MUELLE_PORTON_ALTO), m['peligro'], col))
    puertas.append(mallaCaja('bordePuerta', (xcp, yp + 0.2, MUELLE_PORTON_ALTO - 0.02), (x1p - x0p, 0.12, 0.1), m['peligro'], col))
    unir(puertas, 'puertasBlindadas')
    # Rociadores contra incendios sobre los pasillos.
    rociadores = []
    for y in (-7.0, 7.0):
        rociadores.append(cajaOrientada('tubo', (x0 + 0.3, y, 7.6), (x1 - 0.3, y, 7.6), 0.1, 0.1, m['rojoIncendios'], col))
        for k in range(9):
            xr = x0 + 1.5 + k * (largoSala - 3.0) / 8
            rociadores.append(mallaCaja('rociador', (xr, y, 7.49), (0.06, 0.06, 0.12), m['cromo'], col))
    unir(rociadores, 'rociadores')
    # Contador en el muro de la nave, por fuera (se ve al llegar desde la
    # entrada de la nave).
    xPantalla = POLVORIN_X1 + 0.45
    yPantalla = 0.0
    zPantalla = 7.4
    mallaCaja('pantallaContador', (xPantalla, yPantalla, zPantalla), (0.08, 3.0, 1.4), m['pantalla'], col)
    mallaCaja('marcoContador', (xPantalla - 0.02, yPantalla, zPantalla), (0.06, 3.15, 1.55), m['estructura'], col)
    giro = (math.pi / 2, 0, math.pi / 2)
    texto('contadorTitulo', 'MISILES', 0.32, m['textoPantalla'], col, (xPantalla + 0.05, yPantalla, zPantalla + 0.35), giro)
    texto('contadorValor', '%d / %d' % (len(huecos), len(huecos)), 0.5, m['textoPantalla'], col, (xPantalla + 0.05, yPantalla, zPantalla - 0.25), giro)
    rombo = mallaCaja('rombo', (0, 0, 0), (0.04, 0.9, 0.9), m['naranjaExplosivo'], col)
    rombo.location = (POLVORIN_X1 + 0.43, 2.6, zPantalla)
    rombo.rotation_euler = (math.radians(45), 0, 0)
    texto('rombo11', '1.1', 0.35, m['letraNegra'], col, (POLVORIN_X1 + 0.46, 2.6, zPantalla - 0.05), giro)


POLVORIN_HUECOS = []  # (x, y, z de la base de la caja, cara), en orden de llenado


def crearMesaEncajado(m, col, x, yc, nombre):
    """Mesa de encajado (donde la grúa mete el misil en su caja), a lo largo
    de y: bancada amarilla con largueros en I, patas atornilladas, topes de
    centrado, apoyos de goma y su cartel."""
    largo = CONTENEDOR_LARGO + 0.6
    a = ENCAJADO_ALTO
    p = []
    for dx in (-0.45, 0.45):
        p.append(perfilI('larguero', (x + dx, yc - largo / 2, a - 0.1), (x + dx, yc + largo / 2, a - 0.1), 0.2, 0.15, m['gruaAmarilla'], col, (0, 0, 1)))
    for k in range(4):
        yk = yc - largo / 2 + 0.3 + k * (largo - 0.6) / 3
        for dx in (-0.45, 0.45):
            p.append(mallaCaja('pata', (x + dx, yk, (a - 0.2) / 2), (0.12, 0.12, a - 0.2), m['gruaAmarilla'], col))
            p.append(mallaCaja('pie', (x + dx, yk, 0.012), (0.26, 0.26, 0.024), m['gruaAmarilla'], col))
            for ex in (-0.09, 0.09):
                for ey in (-0.09, 0.09):
                    p += tornillo('anclajeMesa', (x + dx + ex, yk + ey, 0.024), (0, 0, 1), 0.012, m['acero'], col)
        p.append(mallaCaja('travesano', (x, yk, a - 0.1), (0.9, 0.12, 0.12), m['gruaAmarilla'], col))
    for extremo in (-1, 1):
        yt = yc + extremo * (largo / 2 - 0.1)
        for dx in (-0.55, 0.55):
            p.append(mallaCaja('topeCentrado', (x + dx, yt, a + 0.12), (0.08, 0.12, 0.24), m['peligro'], col))
    for dy in (-CONTENEDOR_LARGO / 4, CONTENEDOR_LARGO / 4):
        p.append(mallaCaja('apoyoGoma', (x, yc + dy, a + 0.01), (0.95, 0.35, 0.02), m['goma'], col))
    # Cartel en el extremo de fuera (lejos del pasillo del robot).
    yCartel = yc + math.copysign(largo / 2 - 0.4, yc)
    p.append(mallaCaja('cartelMesa', (x - 0.6, yCartel, 1.6), (0.04, 1.2, 0.4), m['gruaAmarilla'], col))
    p.append(mallaCaja('posteCartel', (x - 0.6, yCartel, 0.7), (0.06, 0.06, 1.4), m['acero'], col))
    unir(p, nombre)
    texto('texto' + nombre, 'ENCAJADO', 0.22, m['letraNegra'], col, (x - 0.625, yCartel, 1.58), (math.pi / 2, 0, -math.pi / 2))
    return (x, yc, a + 0.02)


def crearCaballetes(m, col, x, y, nombre):
    """Dos caballetes de 30 cm donde esperan las cajas vacías (a lo largo de
    y): la garra del robot grande las coge a esa altura."""
    p = []
    for dy in (-CONTENEDOR_LARGO / 4, CONTENEDOR_LARGO / 4):
        p.append(mallaCaja('caballete', (x, y + dy, 0.27), (1.0, 0.3, 0.06), m['gruaAmarilla'], col))
        for dx in (-0.4, 0.4):
            p.append(mallaCaja('pataCaballete', (x + dx, y + dy, 0.12), (0.08, 0.25, 0.24), m['gruaAmarilla'], col))
    unir(p, nombre)
    return (x, y, 0.3)


def crearEncajado(m):
    """Las dos mesas de encajado, una delante de cada portón del polvorín
    (cada pasillo, su mesa: con la caja de 9 m atravesada el robot grande
    solo gira en los pasillos), y dónde esperan las cajas vacías de cada
    carril: al fondo del pasillo norte y, la del sur, en el muelle (las
    traerán los camiones)."""
    col = coleccionNueva('encajado')
    ENCAJADO_SITIOS['mesas'] = [
        crearMesaEncajado(m, col, ENCAJADO_X, (y0 + y1) / 2, 'mesaEncajado%d' % k)
        for k, (y0, y1) in enumerate(POLVORIN_PORTONES)
    ]
    ENCAJADO_SITIOS['vacias'] = [
        crearCaballetes(m, col, VACIAS_SUR[0], VACIAS_SUR[1], 'caballetesSur'),
        crearCaballetes(m, col, VACIAS_NORTE[0], VACIAS_NORTE[1], 'caballetesNorte'),
    ]
    # Plantilla de la caja para el juego (en el origen, cerrada): cuerpo y
    # tapa; el juego la copia para cada caja y gira la tapa.
    crearContenedorAbierto(m, col, 'plantillaCaja', 0.0, 0.0, 0.0, abierta=0.0)


# Cajas vacías, las dos a lo largo de y: al fondo del pasillo norte (a 3,3 m
# del muro: el robot gira la caja con el torso sin tocarlo) y en el muelle,
# al oeste del portón (al este, la valla no deja girarla).
VACIAS_NORTE = (POLVORIN_X1 - 3.3, 7.0)
VACIAS_SUR = (-20.0, Y_SUR - 6.0)
ENCAJADO_SITIOS = {}


def exportarPolvorin(ruta):
    """assets/almacen/polvorin.lua: los huecos del polvorín (en orden de
    llenado), el sitio de la caja en la mesa de encajado y los de la pila de
    vacías, y el eje de la tapa de la caja."""
    def f(v):
        return '%.3f' % v
    filas = ['    huecos = {']
    for x, y, z, cara in POLVORIN_HUECOS:
        filas.append('        { %s, %s, %s, %s },' % (f(x), f(y), f(z), f(math.pi / 2)))
    filas.append('    },')
    # Por carril (pasillo sur y norte): la mesa de encajado, dónde esperan
    # las vacías y el y del pasillo; el sur sale al muelle.
    filas.append('    carriles = {')
    for k, yPasillo in enumerate((-7.0, 7.0)):
        mx, my, mz = ENCAJADO_SITIOS['mesas'][k]
        vx, vy, vz = ENCAJADO_SITIOS['vacias'][k]
        filas.append('        { pasillo = %s, mesa = { %s, %s, %s, 0 }, vacias = { %s, %s, %s, 0 } },' % (f(yPasillo), f(mx), f(my), f(mz), f(vx), f(vy), f(vz)))
    filas.append('    },')
    filas.append('    muelle = { portonX = %s, maniobraY = %s }, -- el robot sale por el centro del portón' % (f((MUELLE_PORTON[0] + MUELLE_PORTON[1]) / 2), f(Y_SUR - 6.0)))
    filas.append('    bisagra = { %s, %s }, -- x, z del eje de la tapa (ejes de la caja: y a lo largo)' % (f(CAJA_BISAGRA[0]), f(CAJA_BISAGRA[1])))
    filas.append('    abierta = %s, -- rad que abre la tapa' % f(math.radians(115)))
    with open(ruta, 'w') as archivo:
        archivo.write('-- Polvorín y encajado (tools/blender/almacen_interior.py --glb): sitios de\n')
        archivo.write('-- las cajas de misil (x, y, z del suelo de la caja, rumbo), metros y ejes del almacén.\n')
        archivo.write('return {\n' + '\n'.join(filas) + '\n}\n')
    print('POLVORIN', ruta, len(POLVORIN_HUECOS), 'huecos')


def crearFabrica(m):
    crearMuroCortafuegos(m, XFABRICA, 'muroFabrica', huecos=[(y0, y1, POLVORIN_PORTON_ALTO) for y0, y1 in POLVORIN_PORTONES] + [PORTON_CALLE])
    crearSueloFabrica(m)
    crearPuenteGrua(m)
    crearMisiles(m)
    crearMobiliario(m)
    crearPolvorin(m)
    crearEncajado(m)


# Sala de control --------------------------------------------------------------

# Sala acristalada de 12 x 11,5 m en las primeras plazas del lado +y (la
# maqueta aprobada por el dueño el 2026-11-16): 6 puestos con 3 monitores,
# muro de 6 pantallas (3 x 2), 4 armarios de servidores y bandeja de cables a
# 4,2 m. Lo que se ve en las pantallas lo pinta el juego (almacen/sala.lua):
#   * `pantallaMapa`: las 4 pantallas de la izquierda del muro, una sola
#     imagen (UV de cuartos);
#   * `pantallaNacion` y `pantallaArsenal`: las dos de la derecha;
#   * `pantallasPuestos`: los 18 monitores en un atlas de 6 x 3 (columna =
#     puesto, fila = monitor de izquierda a derecha);
#   * `ledsServidores`: cada luz de los armarios es un píxel de un lienzo de
#     LEDS_ANCHO x LEDS_ALTO.
SALA_X0 = 2.0
SALA_X1 = 14.0
SALA_Y0 = 3.0
SALA_Y1 = 14.4
SALA_ALTO = 3.0
SALA_SUELO = 0.12
SALA_PUERTA_X = 5.75
SALA_FILAS = (8.6, 11.2)
SALA_PUESTOS_X = (4.6, 7.2, 9.8)
MURO_Y = 14.15
MURO_X = 8.0
PANTALLA_ANCHO = 2.2
PANTALLA_ALTO = 1.25
SERVIDORES_X = 13.25
BANDEJA_Z = 4.2
LEDS_ANCHO = 32
LEDS_ALTO = 18


def mallaPantallas(nombre, quads, material, coleccion):
    """Quads con su UV: cada uno ((4 esquinas: abajo-izq, abajo-der,
    arriba-der, arriba-izq), (u0, v0, u1, v1)). La cara mira hacia quien la
    ve con la derecha en la segunda esquina."""
    bm = bmesh.new()
    capa = bm.loops.layers.uv.new('UVMap')
    for esquinas, (u0, v0, u1, v1) in quads:
        verts = [bm.verts.new(Vector(e)) for e in esquinas]
        cara = bm.faces.new(verts)
        for bucle, uv in zip(cara.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            bucle[capa].uv = uv
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    coleccion.objects.link(objeto)
    return objeto


def esquinasPantalla(centro, mira, ancho, alto, adelante=0.0):
    """Las 4 esquinas de una pantalla vertical en `centro` cuya cara mira en
    la dirección horizontal `mira` (x, y)."""
    d = Vector((mira[0], mira[1], 0)).normalized()
    derecha = Vector((-d.y, d.x, 0))
    c = Vector(centro) + d * adelante
    a = derecha * (ancho / 2)
    h = Vector((0, 0, alto / 2))
    return (tuple(c - a - h), tuple(c + a - h), tuple(c + a + h), tuple(c - a + h))


def tubo(nombre, puntos, radio, material, coleccion):
    """Cable o manguera por `puntos` (sección redonda), ya como malla."""
    curva = bpy.data.curves.new(nombre, 'CURVE')
    curva.dimensions = '3D'
    curva.bevel_depth = radio
    curva.bevel_resolution = 2
    curva.use_fill_caps = True
    tramo = curva.splines.new('NURBS')
    tramo.points.add(len(puntos) - 1)
    for punto, p in zip(tramo.points, puntos):
        punto.co = (p[0], p[1], p[2], 1)
    tramo.use_endpoint_u = True
    tramo.order_u = 3
    tramo.resolution_u = 6
    objeto = bpy.data.objects.new(nombre, curva)
    objeto.data.materials.append(material)
    coleccion.objects.link(objeto)
    bpy.ops.object.select_all(action='DESELECT')
    objeto.select_set(True)
    bpy.context.view_layer.objects.active = objeto
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def colgando(a, b, caida, pasos=10):
    """Puntos de `a` a `b` que cuelgan `caida` m en el medio."""
    a, b = Vector(a), Vector(b)
    puntos = []
    for k in range(pasos + 1):
        f = k / pasos
        p = a.lerp(b, f)
        p.z -= caida * math.sin(math.pi * f)
        puntos.append(tuple(p))
    return puntos


def bajada(a, b, caida=0.15):
    """Cable que sale horizontal de una bandeja y cae vertical a `b`."""
    a, b = Vector(a), Vector(b)
    codo = Vector((b.x, b.y, a.z - 0.3))
    return [tuple(a), tuple(a.lerp(codo, 0.5) - Vector((0, 0, caida))), tuple(codo), tuple(codo.lerp(b, 0.5)), tuple(b)]


def crearTabique(m, piezas, vidrios, coleccion, x0, y0, x1, y1, puertaX=None):
    """Tabique de vidrio de (x0, y0) a (x1, y1) con montantes cada ~1,5 m y,
    si se da `puertaX`, el hueco de una puerta de 1,4 m."""
    largo = math.hypot(x1 - x0, y1 - y0)
    paneles = max(1, round(largo / 1.5))
    zb = SALA_SUELO
    for k in range(paneles):
        f0, f1 = k / paneles, (k + 1) / paneles
        a = (x0 + (x1 - x0) * f0, y0 + (y1 - y0) * f0)
        b = (x0 + (x1 - x0) * f1, y0 + (y1 - y0) * f1)
        centro = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        if puertaX is not None and abs(centro[0] - puertaX) < 0.1:
            # Hueco con su dintel y el marco de la puerta.
            piezas.append(cajaOrientada('dintelPuerta', (a[0], a[1], zb + 2.2), (b[0], b[1], zb + 2.2), 0.1, 0.1, m['estructura'], coleccion))
            vidrios.append(cajaOrientada('vidrioAlto', (a[0], a[1], zb + 2.25 + 0.35), (b[0], b[1], zb + 2.25 + 0.35), 0.02, 0.6, m['vidrioSala'], coleccion))
            continue
        vidrios.append(cajaOrientada('vidrio', (a[0], a[1], zb + SALA_ALTO / 2), (b[0], b[1], zb + SALA_ALTO / 2), 0.02, SALA_ALTO - 0.16, m['vidrioSala'], coleccion))
    for k in range(paneles + 1):
        f = k / paneles
        x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
        piezas.append(mallaCaja('montante', (x, y, zb + SALA_ALTO / 2), (0.08, 0.08, SALA_ALTO), m['estructura'], coleccion))
    for z in (zb + 0.06, zb + SALA_ALTO - 0.04):
        piezas.append(cajaOrientada('perfil', (x0, y0, z), (x1, y1, z), 0.1, 0.1, m['estructura'], coleccion))


def crearPuesto(m, piezas, coleccion, x, y, indice, monitores):
    """Mesa de 1,8 x 0,8 m mirando a +y (el operador en y - 0,75), torre, tres
    monitores (el del centro de frente y los laterales girados) y silla."""
    zm = SALA_SUELO + 0.74
    piezas.append(mallaCaja('tablero', (x, y, zm), (1.8, 0.8, 0.04), m['mesaSala'], coleccion))
    for dx in (-0.87, 0.87):
        piezas.append(mallaCaja('pataMesa', (x + dx, y, (SALA_SUELO + zm) / 2), (0.05, 0.72, zm - SALA_SUELO), m['grisBanco'], coleccion))
    piezas.append(mallaCaja('faldon', (x, y + 0.36, zm - 0.25), (1.7, 0.02, 0.4), m['grisBanco'], coleccion))
    # Torre bajo la mesa, con el piloto encendido.
    piezas.append(mallaCaja('torre', (x + 0.6, y - 0.02, SALA_SUELO + 0.24), (0.2, 0.45, 0.46), m['carcasa'], coleccion))
    piezas.append(mallaCaja('piloto', (x + 0.6, y - 0.246, SALA_SUELO + 0.4), (0.02, 0.004, 0.02), m['ledFijo'], coleccion))
    # Monitores 24": 0,55 x 0,33 de imagen.
    for k in (-1, 0, 1):
        angulo = -k * 0.35
        mira = (math.sin(angulo), -math.cos(angulo))
        cx = x + k * 0.58
        cy = y + 0.22 - abs(k) * 0.08
        cz = zm + 0.32
        carcasa = mallaCaja('monitor', (0, 0, 0), (0.58, 0.035, 0.36), m['carcasa'], coleccion)
        carcasa.rotation_euler = (0, 0, angulo)
        carcasa.location = (cx, cy, cz)
        piezas.append(carcasa)
        brazo = mallaCaja('pieMonitor', (0, 0, 0), (0.05, 0.04, 0.28), m['carcasa'], coleccion)
        brazo.rotation_euler = (0, 0, angulo)
        brazo.location = (cx - mira[0] * 0.05, cy - mira[1] * 0.05, zm + 0.15)
        piezas.append(brazo)
        base = mallaCaja('baseMonitor', (0, 0, 0), (0.22, 0.16, 0.015), m['carcasa'], coleccion)
        base.rotation_euler = (0, 0, angulo)
        base.location = (cx - mira[0] * 0.05, cy - mira[1] * 0.05, zm + 0.028)
        piezas.append(base)
        fila = k + 1
        uv = (indice / 6, 1 - (fila + 1) / 3, (indice + 1) / 6, 1 - fila / 3)
        monitores.append((esquinasPantalla((cx, cy, cz), mira, 0.55, 0.33, 0.0185), uv))
    # Teclado y ratón.
    piezas.append(mallaCaja('teclado', (x, y - 0.18, zm + 0.03), (0.45, 0.15, 0.02), m['carcasa'], coleccion))
    piezas.append(mallaCaja('raton', (x + 0.32, y - 0.18, zm + 0.03), (0.06, 0.1, 0.03), m['carcasa'], coleccion))
    # Silla de oficina: asiento, respaldo, columna y estrella de 5 patas.
    ys = y - 0.75
    piezas.append(mallaCaja('asiento', (x, ys, SALA_SUELO + 0.48), (0.5, 0.48, 0.08), m['tapizado'], coleccion))
    piezas.append(mallaCaja('respaldo', (x, ys - 0.25, SALA_SUELO + 0.8), (0.46, 0.06, 0.55), m['tapizado'], coleccion))
    piezas.append(mallaCaja('columna', (x, ys, SALA_SUELO + 0.27), (0.05, 0.05, 0.38), m['cromo'], coleccion))
    for k in range(5):
        a = k * 2 * math.pi / 5
        fin = (x + math.cos(a) * 0.3, ys + math.sin(a) * 0.3, SALA_SUELO + 0.06)
        piezas.append(cajaOrientada('pata', (x, ys, SALA_SUELO + 0.08), fin, 0.04, 0.03, m['carcasa'], coleccion))
        piezas.append(mallaCaja('rueda', (fin[0], fin[1], SALA_SUELO + 0.03), (0.05, 0.05, 0.05), m['goma'], coleccion))


def crearBandeja(m, piezas, coleccion, a, b):
    """Bandeja de rejilla de 0,4 m a BANDEJA_Z de `a` a `b` (x, y), con su
    mazo de cables y las varillas que la cuelgan de la cubierta."""
    p0 = (a[0], a[1], BANDEJA_Z)
    p1 = (b[0], b[1], BANDEJA_Z)
    for lado in (-0.2, 0.2):
        piezas.append(cajaOrientada('bandejaLado', p0, p1, 0.015, 0.08, m['cromo'], coleccion, desplazamiento=(lado, 0)))
    largo = math.hypot(b[0] - a[0], b[1] - a[1])
    direccion = Vector((b[0] - a[0], b[1] - a[1], 0)).normalized()
    normal = Vector((-direccion.y, direccion.x, 0))
    for k in range(int(largo / 0.3) + 1):
        c = Vector(p0) + direccion * (k * 0.3)
        piezas.append(cajaOrientada('peldano', tuple(c - normal * 0.2 - Vector((0, 0, 0.04))), tuple(c + normal * 0.2 - Vector((0, 0, 0.04))), 0.012, 0.012, m['cromo'], coleccion))
    for material, d in (('cableNaranja', -0.1), ('cable', 0.0), ('cableAzul', 0.1)):
        piezas.append(cajaOrientada('mazo', p0, p1, 0.08, 0.06, m[material], coleccion, desplazamiento=(d, -0.005)))
    for k in range(int(largo / 2) + 1):
        c = Vector(p0) + direccion * min(largo, k * 2)
        piezas.append(mallaCaja('varilla', (c.x, c.y, (BANDEJA_Z + alturaCubierta(c.y)) / 2), (0.015, 0.015, alturaCubierta(c.y) - BANDEJA_Z), m['acero'], coleccion))


def crearSalaControl(m):
    col = coleccionNueva('salaControl')
    piezas = []
    vidrios = []
    cables = []
    cx = (SALA_X0 + SALA_X1) / 2
    cy = (SALA_Y0 + SALA_Y1) / 2
    # Suelo técnico de losetas de 60 cm.
    piezas.append(mallaCaja('sueloTecnico', (cx, cy, SALA_SUELO / 2), (SALA_X1 - SALA_X0, SALA_Y1 - SALA_Y0, SALA_SUELO), m['sueloTecnico'], col))
    x = SALA_X0 + 0.6
    while x < SALA_X1 - 0.05:
        piezas.append(mallaCaja('junta', (x, cy, SALA_SUELO + 0.001), (0.012, SALA_Y1 - SALA_Y0, 0.002), m['juntaSuelo'], col))
        x += 0.6
    y = SALA_Y0 + 0.6
    while y < SALA_Y1 - 0.05:
        piezas.append(mallaCaja('junta', (cx, y, SALA_SUELO + 0.001), (SALA_X1 - SALA_X0, 0.012, 0.002), m['juntaSuelo'], col))
        y += 0.6
    # Tabiques: el del pasillo (con la puerta) y los dos laterales; el fondo es
    # la fachada de la nave.
    crearTabique(m, piezas, vidrios, col, SALA_X0, SALA_Y0, SALA_X1, SALA_Y0, SALA_PUERTA_X)
    crearTabique(m, piezas, vidrios, col, SALA_X0, SALA_Y0, SALA_X0, SALA_Y1)
    crearTabique(m, piezas, vidrios, col, SALA_X1, SALA_Y0, SALA_X1, SALA_Y1)
    # Rótulo sobre la puerta, por fuera.
    zr = SALA_SUELO + SALA_ALTO + 0.3
    piezas.append(mallaCaja('rotuloSala', (SALA_PUERTA_X, SALA_Y0 - 0.03, zr), (2.4, 0.04, 0.45), m['gruaAmarilla'], col))
    texto('textoSala', 'SALA DE CONTROL', 0.26, m['letraNegra'], col, (SALA_PUERTA_X, SALA_Y0 - 0.055, zr - 0.08), (math.pi / 2, 0, 0))
    # Puestos.
    monitores = []
    indice = 0
    for yf in SALA_FILAS:
        for xp in SALA_PUESTOS_X:
            crearPuesto(m, piezas, col, xp, yf, indice, monitores)
            indice += 1
    mallaPantallas('pantallasPuestos', monitores, m['pantalla'], col)
    # Muro de pantallas: bastidor de acero delante del pilar y 6 pantallas.
    zc = SALA_SUELO + 2.3
    piezas.append(mallaCaja('bastidorMuro', (MURO_X, MURO_Y + 0.12, zc), (3 * (PANTALLA_ANCHO + 0.06) + 0.2, 0.1, 2 * (PANTALLA_ALTO + 0.06) + 0.2), m['estructura'], col))
    for dx in (-3.5, 3.5):
        piezas.append(mallaCaja('posteMuro', (MURO_X + dx, MURO_Y + 0.12, (SALA_SUELO + zc + PANTALLA_ALTO + 0.2) / 2), (0.12, 0.12, zc + PANTALLA_ALTO + 0.2 - SALA_SUELO), m['estructura'], col))
    mapa = []
    for f in range(2):
        for c in range(3):
            xs = MURO_X + (c - 1) * (PANTALLA_ANCHO + 0.06)
            zs = zc + (f - 0.5) * (PANTALLA_ALTO + 0.06)
            piezas.append(mallaCaja('marcoPantalla', (xs, MURO_Y + 0.03, zs), (PANTALLA_ANCHO + 0.05, 0.06, PANTALLA_ALTO + 0.05), m['carcasa'], col))
            esquinas = esquinasPantalla((xs, MURO_Y, zs), (0, -1), PANTALLA_ANCHO, PANTALLA_ALTO, 0.002)
            if c < 2:
                mapa.append((esquinas, (c / 2, f / 2, (c + 1) / 2, (f + 1) / 2)))
            else:
                mallaPantallas('pantallaNacion' if f == 1 else 'pantallaArsenal', [(esquinas, (0, 0, 1, 1))], m['pantalla'], col)
    mallaPantallas('pantallaMapa', mapa, m['pantalla'], col)
    # Servidores: 4 armarios de 42U contra el tabique x = SALA_X1, la cara
    # delantera hacia -x, con 20 equipos y 7 luces cada uno.
    leds = []
    numero = 0
    for r in range(4):
        ya = SALA_Y0 + 1.6 + r * 0.62
        zb = SALA_SUELO
        piezas.append(mallaCaja('armario', (SERVIDORES_X, ya, zb + 1.0), (1.07, 0.6, 2.0), m['armario'], col))
        piezas.append(mallaCaja('marcoArmario', (SERVIDORES_X - 0.54, ya, zb + 1.0), (0.02, 0.6, 2.0), m['estructura'], col))
        for u in range(20):
            z = zb + 0.2 + u * 0.085
            piezas.append(mallaCaja('equipo', (SERVIDORES_X - 0.545, ya, z), (0.012, 0.5, 0.075), m['cromo'] if u % 4 == 0 else m['carcasa'], col))
            for k in range(7):
                yl = ya - 0.2 + k * 0.03 + (0.08 if k > 3 else 0)
                c, f = numero % LEDS_ANCHO, numero // LEDS_ANCHO
                u0 = (c + 0.5) / LEDS_ANCHO
                v0 = 1 - (f + 0.5) / LEDS_ALTO
                esquinas = esquinasPantalla((SERVIDORES_X - 0.552, yl, z + 0.015), (-1, 0), 0.014, 0.014)
                leds.append((esquinas, (u0, v0, u0, v0)))
                numero += 1
    mallaPantallas('ledsServidores', leds, m['pantalla'], col)
    # Bandeja de cables: de los servidores al muro y a lo ancho, con un ramal
    # sobre cada fila de puestos.
    xb = SERVIDORES_X
    yFondo = MURO_Y - 0.35
    crearBandeja(m, piezas, col, (xb, SALA_Y0 + 1.3), (xb, yFondo))
    crearBandeja(m, piezas, col, (xb, yFondo), (SALA_X0 + 1.0, yFondo))
    ramales = [yf + 0.4 for yf in SALA_FILAS]
    for yr in ramales:
        crearBandeja(m, piezas, col, (xb, yr), (SALA_X0 + 1.0, yr))
    # Cables que suben de cada armario a la bandeja.
    for r in range(4):
        ya = SALA_Y0 + 1.6 + r * 0.62
        cables.append(tubo('subida', colgando((SERVIDORES_X + 0.2, ya, SALA_SUELO + 2.0), (xb + 0.1, SALA_Y0 + 1.4 + r * 0.05, BANDEJA_Z - 0.04), 0.25, 8), 0.035, m['cableNaranja' if r % 2 else 'cableAzul'], col))
    # Bajadas detrás de las pantallas del muro.
    for c in range(3):
        xs = MURO_X + (c - 1) * (PANTALLA_ANCHO + 0.06)
        for dx, material, caida in ((0.0, 'cable', 0.06), (0.15, 'cableAzul', 0.1)):
            cables.append(tubo('bajadaMuro', colgando((xs + dx, yFondo, BANDEJA_Z - 0.04), (xs + dx, MURO_Y + 0.2, zc + PANTALLA_ALTO + 0.12), caida, 8), 0.035, m[material], col))
    # A los puestos: un mazo por fila baja junto al tabique, va por una
    # canaleta en el suelo detrás de las mesas y sube por cada mesa.
    for yf, yr in zip(SALA_FILAS, ramales):
        yc = yf + 0.5
        xBajada = SALA_X0 + 0.35
        cables.append(tubo('bajadaFila', bajada((SALA_X0 + 1.0, yr, BANDEJA_Z - 0.04), (xBajada, yc, SALA_SUELO + 0.05)), 0.05, m['cable'], col))
        cables.append(tubo('bajadaFila', bajada((SALA_X0 + 1.05, yr + 0.1, BANDEJA_Z - 0.04), (xBajada + 0.06, yc, SALA_SUELO + 0.05)), 0.03, m['cableNaranja'], col))
        xFin = SALA_PUESTOS_X[-1] + 0.7
        piezas.append(mallaCaja('canaleta', ((xBajada + xFin) / 2, yc, SALA_SUELO + 0.03), (xFin - xBajada, 0.14, 0.06), m['estructura'], col))
        for xp in SALA_PUESTOS_X:
            cables.append(tubo('subidaMesa', [(xp + 0.6, yc, SALA_SUELO + 0.06), (xp + 0.6, yc - 0.05, SALA_SUELO + 0.4), (xp + 0.6, yf + 0.36, SALA_SUELO + 0.72)], 0.025, m['cable'], col))
    unir(piezas, 'salaControl')
    unir(vidrios, 'vidriosSala')
    unir(cables, 'cablesSala')


# Render -------------------------------------------------------------------

def prepararRender():
    escena = bpy.context.scene
    # Con --factory-startup, Cycles viene apagado.
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
    motores = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    try:
        escena.render.engine = 'CYCLES'
    except TypeError as error:
        print('SIN CYCLES', error, motores)
    print('MOTOR', escena.render.engine, getattr(escena.cycles, 'device', ''))
    if escena.render.engine == 'CYCLES':
        escena.cycles.samples = 128
        escena.cycles.use_denoising = True
    escena.render.resolution_x = 1600
    escena.render.resolution_y = 900
    mundo = bpy.data.worlds.new('cielo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.55, 0.65, 0.8, 1)
    fondo.inputs['Strength'].default_value = 0.6
    escena.world = mundo
    # Sol: entra por los lucernarios (son emisivos) y por fuera ilumina el cielo.
    sol = bpy.data.lights.new('sol', 'SUN')
    sol.energy = 3.0
    objeto = bpy.data.objects.new('sol', sol)
    objeto.rotation_euler = (math.radians(40), 0, math.radians(30))
    escena.collection.objects.link(objeto)
    escena.view_settings.view_transform = 'AgX' if 'AgX' in [i.identifier for i in escena.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'
    escena.view_settings.exposure = 0.4
    try:
        escena.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass


def camara(nombre, posicion, objetivo, lente=20):
    datos = bpy.data.cameras.new(nombre)
    datos.lens = lente
    datos.clip_start = 0.05
    objeto = bpy.data.objects.new(nombre, datos)
    objeto.location = posicion
    direccion = Vector(objetivo) - Vector(posicion)
    objeto.rotation_euler = direccion.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.collection.objects.link(objeto)
    return objeto


def renderizar(carpeta):
    vistas = [
        ('polvorin_pasillo', (POLVORIN_X1 - 1.5, 7.2, 2.0), (XFABRICA, 6.6, 1.6), 18),
        ('polvorin_alto', (POLVORIN_X1 - 1.0, -13.0, 7.2), (XFABRICA + 12, 2.0, 0.5), 16),
        ('polvorin_contador', (POLVORIN_X1 + 12.0, -0.6, 1.7), (POLVORIN_X1, 0.4, 5.2), 22),
        ('polvorin_brazos', (-33.0, 4.2, 1.9), (-36.8, 0.7, 1.2), 28),
        ('encajado', (ENCAJADO_X - 7.0, 0.5, 4.2), (ENCAJADO_X, 6.5, 0.8), 20),
        ('fabrica_portones', (XMIN + 8.0, -2.0, 5.0), (XFABRICA, 0.0, 2.2), 16),
    ]
    escena = bpy.context.scene
    for nombre, posicion, objetivo, lente in vistas:
        escena.camera = camara(nombre, posicion, objetivo, lente)
        escena.render.filepath = os.path.join(carpeta, nombre + '.png')
        bpy.ops.render.render(write_still=True)


# Exportar al juego -----------------------------------------------------------

GLB_JUEGO = os.path.join(RAIZ, 'assets', 'almacen', 'almacen.glb')


def uvPantalla(objeto):
    """UV de 0 a 1 en la cara que mira a +x (la que se ve): u a lo largo de
    y, v hacia arriba. El juego le pone una textura con el contador."""
    malla = objeto.data
    capa = malla.uv_layers[0] if malla.uv_layers else malla.uv_layers.new()
    ys = [v.co.y for v in malla.vertices]
    zs = [v.co.z for v in malla.vertices]
    y0, y1, z0, z1 = min(ys), max(ys), min(zs), max(zs)
    for cara in malla.polygons:
        for indice in cara.loop_indices:
            v = malla.vertices[malla.loops[indice].vertex_index].co
            capa.data[indice].uv = ((v.y - y0) / (y1 - y0), (v.z - z0) / (z1 - z0))


# Qué es cada objeto para los sensores del robot (por el principio de su
# nombre): lo que no está aquí se llama como el objeto.
TIPOS_COLISION = (
    ('racks', 'rack'), ('racksPolvorin', 'rackPolvorin'),
    ('portones', 'porton'), ('puertasBlindadas', 'puertaBlindada'), ('vidriosSala', 'vidrio'),
    ('salaControl', 'salaControl'), ('salaBlindada', 'muro'), ('muro', 'muro'), ('cerramiento', 'pared'),
    ('zocalo', 'pared'), ('porticos', 'pilar'), ('estanteria', 'estanteria'), ('SM_Prop', 'caja'),
    ('puesto', 'banco'), ('puente', 'grua'),
    ('cartelDinero', 'cartelDinero'), ('cartelMunicion', 'cartelMunicion'), ('cartelComida', 'cartelComida'),
    ('cartelMetal', 'cartelMetal'), ('cartelPetroleo', 'cartelPetroleo'),
    ('valla', 'valla'), ('anexo', 'pared'), ('muelleFarolas', 'farola'),
)


def tipoColision(nombre):
    for prefijo, tipo in TIPOS_COLISION:
        if nombre.startswith(prefijo):
            return tipo
    return nombre.split('.')[0].rstrip('0123456789_')


def exportarColisiones(ruta):
    """Cajas de colisión para los sensores del robot (assets/almacen/
    colisiones.lua): cada trozo suelto de cada malla (las piezas que se
    unieron) da su caja alineada con los ejes, en metros y ejes del almacén.
    Solo lo que está entre 5 cm y 2 m de alto (lo que puede tocar el
    robot)."""
    import bmesh
    filas = []
    for objeto in bpy.data.objects:
        if objeto.type != 'MESH':
            continue
        if objeto.name.startswith('plantilla'):
            continue  # las plantillas de las cajas están en el origen
        tipo = tipoColision(objeto.name)
        bm = bmesh.new()
        bm.from_mesh(objeto.data)
        bm.transform(objeto.matrix_world)
        bm.verts.ensure_lookup_table()
        padre = list(range(len(bm.verts)))

        def raiz(i):
            while padre[i] != i:
                padre[i] = padre[padre[i]]
                i = padre[i]
            return i

        for arista in bm.edges:
            a, b = raiz(arista.verts[0].index), raiz(arista.verts[1].index)
            if a != b:
                padre[a] = b
        cajas = {}
        for v in bm.verts:
            r = raiz(v.index)
            c = cajas.get(r)
            p = v.co
            if c is None:
                cajas[r] = [p.x, p.y, p.z, p.x, p.y, p.z]
            else:
                c[0], c[1], c[2] = min(c[0], p.x), min(c[1], p.y), min(c[2], p.z)
                c[3], c[4], c[5] = max(c[3], p.x), max(c[4], p.y), max(c[5], p.z)
        bm.free()
        for c in cajas.values():
            # El suelo y lo pintado en él (por debajo de 5 cm) no estorba; las
            # paredes, aunque sean muy largas, sí.
            # Los carteles sí aunque estén altos: el robot los lee con los ojos.
            if c[5] < 0.05 or (c[2] > 2.0 and not tipo.startswith('cartel')):
                continue
            filas.append("    { '%s', %.2f, %.2f, %.2f, %.2f, %.2f, %.2f }," % (tipo, c[0], c[1], max(0.0, c[2]), c[3], c[4], c[5]))
    with open(ruta, 'w') as archivo:
        archivo.write('-- Cajas de colisión del almacén para los sensores del robot\n')
        archivo.write('-- (tools/blender/almacen_interior.py --glb): tipo, x0, y0, z0, x1, y1, z1\n')
        archivo.write('-- en metros y ejes del almacén (z arriba).\n')
        archivo.write('return {\n' + '\n'.join(filas) + '\n}\n')
    print('COLISIONES', ruta, len(filas), 'cajas')


# Dibujar solo lo que se ve (el dueño, 17-nov): con todo el edificio en una
# sola pieza, el motor no podía descartar nada (su recorte va pieza a pieza)
# y dibujaba la nave entera cada cuadro, también detrás de la cámara y en la
# sombra del sol. Como las celdas de los motores grandes: el estático se parte
# en cuadrados de este lado; el motor descarta los que no ve.
# MEDIDO (17-nov, cámara quieta en el inicio): una pieza 66-69 FPS, celdas de
# 20 m 34-54 FPS. Cada celda lleva sus ~15 materiales y las llamadas de
# dibujo (también en las sombras) pesan más que lo que se ahorra. Apagado
# (0) hasta probar otra cosa (juntar por material, celdas mayores, menos
# materiales).
CELDA_ESTATICO = 0


def partirEnCeldas(objeto, lado):
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    celdas = {}
    for cara in bm.faces:
        c = cara.calc_center_median()
        celdas.setdefault((math.floor(c.x / lado), math.floor(c.y / lado)), set()).add(cara.index)
    bm.free()
    colecciones = list(objeto.users_collection)
    for (i, j), caras in sorted(celdas.items()):
        nuevo = objeto.copy()
        nuevo.data = objeto.data.copy()
        for coleccion in colecciones:
            coleccion.objects.link(nuevo)
        bm = bmesh.new()
        bm.from_mesh(nuevo.data)
        fuera = [cara for cara in bm.faces if cara.index not in caras]
        bmesh.ops.delete(bm, geom=fuera, context='FACES')
        bm.to_mesh(nuevo.data)
        bm.free()
        nuevo.name = 'estatico_%d_%d' % (i, j)
        nuevo.data.name = nuevo.name
    bpy.data.objects.remove(objeto)
    print('ESTATICO en', len(celdas), 'celdas de', lado, 'm')


def exportarJuego(ruta):
    """Deja la escena lista para 3DreamEngine y la exporta a `ruta` (.glb,
    en metros, y arriba). Quedan tres clases de objeto:
      * `plantillaCaja` y `plantillaCajaTapa`: la caja de un misil en el
        origen (el juego hace una por caja, assets/almacen/polvorin.lua);
      * `pantallaContador`, con UV de 0 a 1 en su cara: el juego le pinta los
        misiles en vivo;
      * la sala de control: `pantallaMapa`, `pantallaNacion`,
        `pantallaArsenal`, `pantallasPuestos` y `ledsServidores` (con su UV,
        las pinta el juego) y `vidriosSala` (transparente);
      * `estatico`: todo lo demás junto (o `estatico_<i>_<j>`, en celdas de
        CELDA_ESTATICO m, si se activa; ver allí lo medido).
    Sin texturas dentro: los materiales con imagen (baseHormigon, baseChapa,
    AtlasSyntyBase, unidadCamion4...) los pone el juego por su nombre
    (batalla/dream/biblioteca_pbr.lua); los lisos van con su color."""
    # Los textos fijos del contador los pinta el juego.
    for nombre in ('contadorTitulo', 'contadorValor'):
        objeto = bpy.data.objects.get(nombre)
        if objeto:
            bpy.data.objects.remove(objeto)
    # Las luces van aparte (assets/almacen/luces.lua), en ejes de 3Dream
    # (x, z, -y de Blender), con su potencia en vatios de Blender.
    luces = []
    for objeto in bpy.data.objects:
        if objeto.type == 'LIGHT' and objeto.data.type in ('AREA', 'POINT'):
            p = objeto.matrix_world.translation
            c = objeto.data.color
            luces.append('    { %.3f, %.3f, %.3f, %.0f, %.3f, %.3f, %.3f },' % (p.x, p.z, -p.y, objeto.data.energy, c[0], c[1], c[2]))
    rutaLuces = os.path.join(os.path.dirname(ruta), 'luces.lua')
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(rutaLuces, 'w') as archivo:
        archivo.write('-- Luces del almacén (tools/blender/almacen_interior.py --glb): x, y, z\n')
        archivo.write('-- en ejes de 3Dream (metros, y arriba), vatios en Blender y color.\n')
        archivo.write('return {\n' + '\n'.join(luces) + '\n}\n')
    for objeto in list(bpy.data.objects):
        if objeto.type in ('LIGHT', 'CAMERA'):
            bpy.data.objects.remove(objeto)
    bpy.ops.object.select_all(action='DESELECT')
    textos = [o for o in bpy.data.objects if o.type == 'FONT']
    for o in textos:
        o.select_set(True)
    if textos:
        bpy.context.view_layer.objects.active = textos[0]
        bpy.ops.object.convert(target='MESH')
    # Todo en el mundo: sin padres y con las transformaciones aplicadas.
    mallas = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in mallas:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mallas[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # 3DreamEngine necesita UV en todas las mallas (calcula tangentes con
    # ellas): las cajas hechas aquí sin UV llevan la proyección del mundo.
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.data.uv_layers:
            uvMundo(o, 2.0)
    exportarColisiones(os.path.join(os.path.dirname(ruta), 'colisiones.lua'))
    exportarPolvorin(os.path.join(os.path.dirname(ruta), 'polvorin.lua'))
    exportarFabrica(os.path.join(os.path.dirname(ruta), 'fabrica.lua'))
    pantalla = bpy.data.objects['pantallaContador']
    uvPantalla(pantalla)
    pantalla.data.materials.clear()
    pantalla.data.materials.append(materialLiso('pantallaContador', (0.02, 0.03, 0.025), 0.3))
    # Pantallas de la sala de control: cada una con su material, que el juego
    # cambia por el suyo con la imagen viva (almacen/sala.lua).
    vivas = ('pantallaMapa', 'pantallaNacion', 'pantallaArsenal', 'pantallasPuestos', 'ledsServidores')
    for nombre in vivas:
        objeto = bpy.data.objects.get(nombre)
        if objeto:
            objeto.data.materials.clear()
            objeto.data.materials.append(materialLiso(nombre, (0.02, 0.03, 0.025), 0.3))
    # Aparte: los lucernarios (el juego los quita de las sombras del sol para
    # que entre por ellos), el vidrio de la sala (transparente) y las pantallas.
    aparte = ('plantilla', 'lucernarios', 'vidriosSala') + vivas
    resto = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith(aparte) and o is not pantalla]
    estatico = unir(resto, 'estatico')
    if CELDA_ESTATICO > 0:
        partirEnCeldas(estatico, CELDA_ESTATICO)
    # Nombres de material sin el «.001» de Blender: el juego los busca por nombre.
    for material in bpy.data.materials:
        base = material.name.split('.')[0]
        if base != material.name and base not in bpy.data.materials:
            material.name = base
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    opciones = dict(filepath=ruta, export_format='GLB', use_selection=False, export_apply=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
    except TypeError:
        bpy.ops.export_scene.gltf(**opciones)
    print('EXPORTADO', ruta, len([o for o in bpy.data.objects if o.type == 'MESH']), 'objetos')


def crearAnexo(m):
    """Sala de suministros del robot: nave baja de chapa (6 m) pegada al
    testero de +x, al sur, con el portón sur de la nave como entrada. Tres
    filas de estanterías del robot con un cartel grande colgado encima de
    cada una (DINERO, MUNICIÓN, COMIDA): el robot los lee con los ojos."""
    col = coleccionNueva('anexo')
    x0, x1, y0, y1 = XMAX, ANEXO_X1, ANEXO_Y0, ANEXO_Y1
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    largo, ancho = x1 - x0, y1 - y0
    suelo = mallaCaja('anexoSuelo', (xc, yc, -0.15), (largo, ancho, 0.3), m['hormigon'], col)
    uvMundo(suelo, 4.0)
    muros = []
    # Zócalo de hormigón y chapa encima: este, norte y sur.
    for nombre, centro, tamano in (
            ('este', (x1 + 0.1, yc, 0), (0.2, ancho + 0.2, 0)),
            ('norte', (xc, y1 + 0.1, 0), (largo, 0.2, 0)),
            ('sur', (xc, y0 - 0.1, 0), (largo, 0.2, 0))):
        muros.append(mallaCaja('anexoZocalo', (centro[0], centro[1], ZOCALO / 2), (tamano[0], tamano[1], ZOCALO), m['hormigon'], col))
        muros.append(mallaCaja('anexoChapa', (centro[0], centro[1], (ZOCALO + ANEXO_ALTO) / 2), (max(tamano[0] - 0.12, 0.04), max(tamano[1] - 0.12, 0.04), ANEXO_ALTO - ZOCALO), m['chapa'], col))
    pared = unir(muros, 'anexoParedes')
    uvMundo(pared, 2.0)
    techo = mallaCaja('anexoTecho', (xc, yc, ANEXO_ALTO + 0.1), (largo + 0.4, ancho + 0.4, 0.2), m['chapa'], col)
    uvMundo(techo, 2.0)
    vigas = []
    for k in range(1, 6):
        x = x0 + k * largo / 6
        vigas.append(mallaCaja('anexoViga', (x, yc, ANEXO_ALTO - 0.2), (0.25, ancho, 0.4), m['estructura'], col))
    unir(vigas, 'anexoVigas')
    # Líneas del suelo: un rectángulo amarillo delante de cada fila (donde
    # se para el robot) y la entrada desde la nave.
    lineas = []
    for y, hacia, _ in FILAS_ANEXO:
        yl = y + hacia * 0.75
        xm = (FILA_RACKS_X[0] + FILA_RACKS_X[-1]) / 2
        lineas += rectanguloLineas(xm, yl, FILA_RACKS_X[-1] - FILA_RACKS_X[0] + RACK_LARGO, 0.9, 0.08, m['lineaAmarilla'], col)
    lineas.append(mallaCaja('linea', (x0 + 1.0, -6.5, 0.003), (0.12, 5.0, 0.006), m['lineaAmarilla'], col))
    unir(lineas, 'anexoLineas')
    # Carteles: uno colgado encima de cada rack, del lado del pasillo, con dos
    # cables, color de la fila y letras blancas por las dos caras.
    colores = {
        'Dinero': materialLiso('cartelVerde', (0.05, 0.38, 0.12), 0.5),
        'Municion': materialLiso('cartelRojo', (0.55, 0.07, 0.04), 0.5),
        'Comida': materialLiso('cartelAzul', (0.04, 0.18, 0.5), 0.5),
        'Metal': materialLiso('cartelGris', (0.22, 0.24, 0.26), 0.5),
        'Petroleo': materialLiso('cartelNaranja', (0.75, 0.32, 0.03), 0.5),
    }
    blanco = materialLiso('letraBlanca', (0.92, 0.92, 0.9), 0.5)
    for y, hacia, carteles in FILAS_ANEXO:
        yc = y + hacia * 0.45
        z = 2.45
        for xCartel, (nombre, letrero) in zip(FILA_RACKS_X, cartelesFila(carteles)):
            placa = [mallaCaja('cartel' + nombre, (xCartel, yc, z), (2.6, 0.06, 0.6), colores[nombre], col)]
            for dx in (-1.1, 1.1):
                placa.append(mallaCaja('cartel' + nombre + 'Cable', (xCartel + dx, yc, (z + 0.3 + ANEXO_ALTO - 0.4) / 2), (0.015, 0.015, ANEXO_ALTO - 0.4 - z - 0.3), m['acero'], col))
            unir(placa, 'cartel' + nombre)
            for cara in (-1, 1):
                texto('cartel' + nombre + 'Letras', letrero, 0.34, blanco, col, (xCartel, yc + cara * 0.035, z - 0.02), (math.pi / 2, 0, 0 if cara < 0 else math.pi))
    # Luces: cuatro campanas.
    piezas = []
    for x in (x0 + largo * 0.15, x0 + largo * 0.38, x0 + largo * 0.62, x0 + largo * 0.85):
        for y in (-5.5, -12.3):
            piezas.append(mallaCaja('campana', (x, y, ANEXO_ALTO - 0.6), (0.55, 0.55, 0.18), m['estructura'], col))
            piezas.append(mallaCaja('difusor', (x, y, ANEXO_ALTO - 0.7), (0.48, 0.48, 0.02), m['foco'], col))
            luz = bpy.data.lights.new('foco', 'AREA')
            luz.size = 0.5
            luz.energy = 1500
            luz.color = (1.0, 0.95, 0.86)
            objeto = bpy.data.objects.new('foco', luz)
            objeto.location = (x, y, ANEXO_ALTO - 0.75)
            objeto.rotation_euler = (math.pi, 0, 0)
            col.objects.link(objeto)
    unir(piezas, 'anexoLamparas')


def crearPatio(m):
    """Patio de descarga al aire libre, al norte del anexo y delante del
    portón norte de la nave: losa de hormigón, zona de descarga pintada,
    valla de malla con su puerta para los camiones (lado este) y el suelo de
    fuera. Las mesas de descarga las pone el juego (EscenaAlmacen.descarga)."""
    col = coleccionNueva('patio')
    x0, x1, y0, y1 = XMAX, PATIO_X1, PATIO_Y0, PATIO_Y1
    losa = mallaCaja('patioLosa', ((x0 + x1) / 2, (y0 + y1) / 2, -0.15), (x1 - x0, y1 - y0, 0.3), m['hormigon'], col)
    uvMundo(losa, 4.0)
    fuera = mallaCaja('exterior', (0, 0, -0.17), (220, 140, 0.3), materialLiso('tierraExterior', (0.28, 0.27, 0.22), 0.9), col)
    uvMundo(fuera, 8.0)
    xm = (EXTREMOS_DESCARGA[0] + EXTREMOS_DESCARGA[1]) / 2
    ym = (EXTREMOS_DESCARGA[2] + EXTREMOS_DESCARGA[3]) / 2
    lineas = rectanguloLineas(xm, ym, EXTREMOS_DESCARGA[1] - EXTREMOS_DESCARGA[0], EXTREMOS_DESCARGA[3] - EXTREMOS_DESCARGA[2], 0.15, m['lineaAmarilla'], col)
    for k in range(10):
        lineas.append(cajaOrientada('rayado', (x0 + 1.0 + k * 1.0, 0.0, 0.003), (x0 + 1.6 + k * 1.0, -0.8, 0.003), 0.12, 0.006, m['lineaAmarilla'], col))
    unir(lineas, 'patioLineas')
    rotulo = texto('patioRotulo', 'ZONA DE DESCARGA', 1.1, m['lineaBlanca'], col, (xm, EXTREMOS_DESCARGA[3] + 1.4, 0.006), (0, 0, 0))
    rotulo.data.extrude = 0.002
    # Valla de malla: postes cada 2,5 m, malla y travesaño, con puerta abierta
    # al este (de y = 2 a 11).
    postes, mallas = [], []
    malla = materialLiso('mallaValla', (0.45, 0.47, 0.48), 0.5, 0.8)
    tramos = [((x0, Y_NORTE + 0.3), (x0, y1)), ((x0, y1), (x1, y1)), ((x1, y1), (x1, 16.0)), ((x1, 6.0), (x1, y0))]
    for (ax, ay), (bx, by) in tramos:
        largo = math.hypot(bx - ax, by - ay)
        n = max(1, round(largo / 2.5))
        for k in range(n + 1):
            px, py = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
            postes.append(mallaCaja('vallaPoste', (px, py, 1.1), (0.06, 0.06, 2.2), m['acero'], col))
        mallas.append(cajaOrientada('vallaMalla', (ax, ay, 1.125), (bx, by, 1.125), 0.02, 1.95, malla, col))
        mallas.append(cajaOrientada('vallaTravesano', (ax, ay, 2.15), (bx, by, 2.15), 0.05, 0.05, m['acero'], col))
    unir(postes, 'vallaPostes')
    unir(mallas, 'vallaMallas')
    # Farolas del patio.
    piezas = []
    for px, py in ((x1 - 0.5, 1.0), (x1 - 0.5, y1 - 1.5), (x0 + 12, y1 - 0.5), (x0 + 26, y1 - 0.5)):
        piezas.append(mallaCaja('farola', (px, py, 3.0), (0.12, 0.12, 6.0), m['estructura'], col))
        piezas.append(mallaCaja('farolaBrazo', (px - 0.6, py, 6.0), (1.2, 0.1, 0.1), m['estructura'], col))
        piezas.append(mallaCaja('farolaLuz', (px - 1.1, py, 5.92), (0.5, 0.25, 0.08), m['foco'], col))
    unir(piezas, 'patioFarolas')


def crearValla(m, col, nombre, tramos):
    """Valla de malla por los tramos ((x, y), (x, y)): postes cada 2,5 m,
    malla y travesaño (como la del patio)."""
    postes, mallas = [], []
    malla = materialLiso('mallaValla', (0.45, 0.47, 0.48), 0.5, 0.8)
    for (ax, ay), (bx, by) in tramos:
        largo = math.hypot(bx - ax, by - ay)
        n = max(1, round(largo / 2.5))
        for k in range(n + 1):
            px, py = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
            postes.append(mallaCaja('vallaPoste', (px, py, 1.1), (0.06, 0.06, 2.2), m['acero'], col))
        mallas.append(cajaOrientada('vallaMalla', (ax, ay, 1.125), (bx, by, 1.125), 0.02, 1.95, malla, col))
        mallas.append(cajaOrientada('vallaTravesano', (ax, ay, 2.15), (bx, by, 2.15), 0.05, 0.05, m['acero'], col))
    unir(postes, nombre + 'Postes')
    unir(mallas, nombre + 'Mallas')


def crearMuelle(m):
    """Muelle de misiles: patio exterior al sur de la fábrica y el
    polvorín. Pegada a la fachada, la calle de maniobra del robot grande
    (aquí gira con una caja de 9 m atravesada); detrás, tres plazas para
    semirremolques en fila (la cabeza hacia el oeste: entran por el este y
    salen por el oeste), con su número pintado. Rayado de peligro delante del
    portón, valla con dos puertas para los camiones y farolas."""
    col = coleccionNueva('muelle')
    x0, x1, yFondo = MUELLE
    losa = mallaCaja('muelleLosa', ((x0 + x1) / 2, (Y_SUR + yFondo) / 2, -0.15), (x1 - x0, Y_SUR - yFondo, 0.3), m['hormigon'], col)
    uvMundo(losa, 4.0)
    lineas = []
    z = 0.004
    # Borde de la calle de maniobra.
    yManiobra = Y_SUR - MUELLE_MANIOBRA
    lineas.append(mallaCaja('linea', ((x0 + x1) / 2, yManiobra, z), (x1 - x0 - 1.0, 0.15, 0.006), m['lineaAmarilla'], col))
    # Plazas de los camiones: 18 x 4 m, la cabeza al oeste.
    for k, xc in enumerate(MUELLE_CAMIONES_X):
        xPlaza = xc - 1.5
        lineas += rectanguloLineas(xPlaza, MUELLE_CAMION_Y, 18.0, 4.0, 0.15, m['lineaBlanca'], col)
        # Se lee desde la calle de maniobra (mirando al sur).
        rotulo = texto('numeroPlaza%d' % (k + 1), str(k + 1), 1.6, m['lineaBlanca'], col, (xPlaza + 7.2, MUELLE_CAMION_Y + 3.3, 0.006), (0, 0, math.pi))
        rotulo.data.extrude = 0.002
    # Rayado de peligro delante del portón (zona del robot).
    xa, xb = MUELLE_PORTON
    for k in range(int((xb - xa) / 0.9)):
        xr = xa + 0.3 + k * 0.9
        lineas.append(cajaOrientada('rayado', (xr, Y_SUR - 0.3, z), (xr + 0.6, Y_SUR - 1.5, z), 0.18, 0.006, m['lineaAmarilla'], col))
    unir(lineas, 'muelleLineas')
    rotulo = texto('muelleRotulo', 'MUELLE DE MISILES', 1.1, m['lineaBlanca'], col, ((x0 + x1) / 2, yFondo + 2.0, 0.006), (0, 0, math.pi))
    rotulo.data.extrude = 0.002
    # Valla: fondo y laterales, con una puerta de 8 m en cada lateral.
    crearValla(m, col, 'vallaMuelle', [
        ((x0, Y_SUR - 0.3), (x0, yFondo + 10.0)), ((x0, yFondo + 2.0), (x0, yFondo)), ((x0, yFondo), (x1, yFondo)),
        ((x1, yFondo), (x1, yFondo + 2.0)), ((x1, yFondo + 10.0), (x1, Y_SUR - 0.3)),
    ])
    piezas = []
    for px in (x0 + 8.0, x0 + 24.0, x1 - 24.0, x1 - 8.0):
        py = yFondo + 0.5
        piezas.append(mallaCaja('farola', (px, py, 4.0), (0.14, 0.14, 8.0), m['estructura'], col))
        piezas.append(mallaCaja('farolaBrazo', (px, py + 0.6, 8.0), (0.1, 1.2, 0.1), m['estructura'], col))
        piezas.append(mallaCaja('farolaLuz', (px, py + 1.1, 7.92), (0.25, 0.5, 0.08), m['foco'], col))
    unir(piezas, 'muelleFarolas')


# Información para los robots (assets/almacen/informacion.lua) -------------
#
# Como los «smart objects» de Unreal o los volúmenes con datos de los
# juegos: cajas que no paran a nadie (disparadores) y que, cuando los rayos
# de los ojos del robot las cruzan, le dicen qué es eso y sus medidas.
#   porton / puerta: el hueco de paso con su ancho, alto, centro, hacia
#     dónde se cruza (normal) y si está abierto;
#   marco: cada jamba de un hueco (el robot sabe a qué distancia pasarle);
#   esquina: las esquinas de las paredes.
INFO_GROSOR = 1.2  # m de la caja del hueco a lo largo del paso


def huecosDePaso():
    """Los huecos de paso del almacén: nombre, tipo, eje de la pared ('x':
    pared en x = cte, se cruza a lo largo de x), posición de la pared, de
    dónde a dónde va el hueco, alto y si está abierto."""
    return [
        ('portón del anexo', 'porton', 'x', XMAX, -9.0, -4.0, 5.5, True),
        ('puerta peatonal de la nave', 'puerta', 'x', XMAX, -0.5, 0.5, 2.1, False),
        ('portón del patio', 'porton', 'x', XMAX, 4.0, 9.0, 5.5, True),
        ('puerta del polvorín', 'puerta', 'x', POLVORIN_X1, 9.5, 10.5, 2.1, False),
        ('portón sur del polvorín', 'porton', 'x', XFABRICA, POLVORIN_PORTONES[0][0], POLVORIN_PORTONES[0][1], POLVORIN_PORTON_ALTO, True),
        ('portón norte del polvorín', 'porton', 'x', XFABRICA, POLVORIN_PORTONES[1][0], POLVORIN_PORTONES[1][1], POLVORIN_PORTON_ALTO, True),
        ('puerta de la sala de control', 'puerta', 'y', SALA_Y0, SALA_PUERTA_X - 0.7, SALA_PUERTA_X + 0.7, 2.2, True),
        ('puerta de los camiones', 'porton', 'x', PATIO_X1, 6.0, 16.0, 4.5, True),
        ('portón del muelle de misiles', 'porton', 'y', Y_SUR, MUELLE_PORTON[0], MUELLE_PORTON[1], MUELLE_PORTON_ALTO, True),
        ('portón de la calle a la fábrica', 'porton', 'x', XFABRICA, PORTON_CALLE[0], PORTON_CALLE[1], PORTON_CALLE[2], True),
        ('portón de la calle a la nave', 'porton', 'x', POLVORIN_X1, PORTON_CALLE[0], PORTON_CALLE[1], PORTON_CALLE[2], True),
        ('portón de la calle al patio', 'porton', 'x', XMAX, PORTON_CALLE[0], PORTON_CALLE[1], PORTON_CALLE[2], True),
    ]


def esquinas():
    """Esquinas de las paredes por dentro: (nombre, x, y)."""
    r = 0.3
    return [
        ('esquina de la nave', XMIN + r, Y_SUR + r), ('esquina de la nave', XMIN + r, Y_NORTE - r),
        ('esquina de la nave', XMAX - r, Y_SUR + r), ('esquina de la nave', XMAX - r, Y_NORTE - r),
        ('esquina del anexo', XMAX + r, ANEXO_Y0 + r), ('esquina del anexo', ANEXO_X1 - r, ANEXO_Y0 + r),
        ('esquina del anexo', XMAX + r, ANEXO_Y1 - r), ('esquina del anexo', ANEXO_X1 - r, ANEXO_Y1 - r),
        ('esquina del patio', XMAX + r, PATIO_Y1 - r), ('esquina del patio', PATIO_X1 - r, PATIO_Y1 - r),
        ('esquina del patio', PATIO_X1 - r, PATIO_Y0 + r),
    ]


def exportarInformacion(ruta):
    def f(v):
        return '%.2f' % v

    filas = []
    g = INFO_GROSOR / 2
    for nombre, tipo, eje, pared, a, b, alto, abierto in huecosDePaso():
        centro = (a + b) / 2
        if eje == 'x':
            caja = (pared - g, a, 0, pared + g, b, alto)
            c, n = (pared, centro), (1, 0)
            jambas = ((pared - 0.35, a - 0.25, 0, pared + 0.35, a + 0.02, alto), (pared - 0.35, b - 0.02, 0, pared + 0.35, b + 0.25, alto))
        else:
            caja = (a, pared - g, 0, b, pared + g, alto)
            c, n = (centro, pared), (0, 1)
            jambas = ((a - 0.25, pared - 0.35, 0, a + 0.02, pared + 0.35, alto), (b - 0.02, pared - 0.35, 0, b + 0.25, pared + 0.35, alto))
        filas.append("    { tipo = '%s', nombre = '%s', caja = { %s }, centro = { %s, %s }, normal = { %d, %d }, ancho = %s, alto = %s, abierto = %s }," % (
            tipo, nombre, ', '.join(f(v) for v in caja), f(c[0]), f(c[1]), n[0], n[1], f(b - a), f(alto), 'true' if abierto else 'false'))
        for k, jamba in enumerate(jambas):
            filas.append("    { tipo = 'marco', nombre = 'marco de%s %s', de = '%s', lado = %d, caja = { %s } }," % (
                'l' if nombre.startswith('portón') else ' la', nombre, nombre, k + 1, ', '.join(f(v) for v in jamba)))
    for nombre, x, y in esquinas():
        filas.append("    { tipo = 'esquina', nombre = '%s', caja = { %s, %s, 0, %s, %s, 3.00 }, centro = { %s, %s } }," % (nombre, f(x - 0.4), f(y - 0.4), f(x + 0.4), f(y + 0.4), f(x), f(y)))
    with open(ruta, 'w') as archivo:
        archivo.write('-- Información del almacén para los robots (tools/blender/almacen_interior.py\n')
        archivo.write('-- --info): cajas disparador (no paran a nadie) que los rayos de los ojos\n')
        archivo.write('-- leen. Metros y ejes del almacén. Ver almacen/robots/mundo.lua.\n')
        archivo.write('return {\n' + '\n'.join(filas) + '\n}\n')
    print('INFORMACION', ruta, len(filas), 'zonas')


INFO_JUEGO = os.path.join(RAIZ, 'assets', 'almacen', 'informacion.lua')


def principal():
    args = argumentos()
    if '--info' in args:
        exportarInformacion(INFO_JUEGO)
        return
    if '--glb' in args:
        k = args.index('--glb')
        rutaGlb = args[k + 1] if len(args) > k + 1 else GLB_JUEGO
        del args[k:k + 2]
    else:
        rutaGlb = None
    salida = args[0] if args else os.path.join(RAIZ, 'tools', 'blender', 'almacen_interior.blend')
    limpiarEscena()
    m = crearMateriales()
    crearSuelo(m)
    crearPorticos(m)
    crearCerramiento(m)
    crearPortones(m)
    # Los racks azules de la nave se quitaron (17-nov): ahí va el polvorín.
    crearFocos(m)
    crearFabrica(m)
    crearSalaControl(m)
    crearAnexo(m)
    crearPatio(m)
    crearMuelle(m)
    prepararRender()
    bpy.ops.wm.save_as_mainfile(filepath=salida)
    if rutaGlb:
        exportarJuego(rutaGlb)
        exportarInformacion(INFO_JUEGO)
    elif len(args) > 1:
        renderizar(args[1])


principal()

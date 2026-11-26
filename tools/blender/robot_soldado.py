# Robot soldado de Nations RTS (el dueño, 2026-11-17): torso humano con
# cabeza y dos brazos sobre dos piernas con una rueda en cada pie (juntas, una
# al lado de la otra: se equilibra como un Segway y corre como en patinete,
# con las rodillas dobladas y el torso echado hacia delante). Silueta
# aprobada en tools/blender/robot_soldado_silueta.py.
#   - Brazo derecho: el antebrazo es una metralleta de tres cañones, parte
#     del cuerpo (sin gatillo ni cargador, nada de armas reales).
#   - Brazo izquierdo: la garra de tres dedos (robot_soldado_mano.py).
# Acabado de la casa (skill vehiculo-detallado y robots del almacén): negro
# biselado, articulaciones de cilindro oscuro, franjas blancas, acero y
# tornillos con arandela.
#
# Se construye por etapas (para verlo montarse en el Blender del dueño por
# MCP, o todo de una vez sin ventana):
#
#     blender -b --factory-startup --python tools/blender/robot_soldado.py -- <salida.blend>
#
# Metros, z arriba, frente hacia +x, izquierda hacia +y, el origen en el
# suelo entre las ruedas. Pose de reposo: de pie, rodillas algo dobladas.
# Jerarquía (cada pieza con el origen en su eje):
#   pelvis
#     musloIzq/Der        gira en y (cadera)
#       espinillaIzq/Der  gira en y (rodilla)
#         ruedaIzq/Der    gira en y (rueda)
#     torso               gira en z (cintura) y en y (inclinarse)
#       cabeza            gira en z (mirar a los lados)
#       hombroIzq/Der     gira en y (adelante y atrás)
#         codoIzq/Der     gira en y
#           metralleta    (der) y canones: giran en x al disparar
#           munecaIzq     -> la garra (mano, dedoA1...)

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.path.expanduser('~/NationsRTS/tools/blender')
with open(os.path.join(_DIR, 'robot_almacen.py'), encoding='utf8') as _archivo:
    _fuente = _archivo.read()
exec(_fuente[_fuente.index('def argumentos():'):_fuente.index('# El robot ---')])

# Medidas (m) ------------------------------------------------------------------
RUEDA_R = 0.15
RUEDA_ANCHO = 0.07
RUEDA_Y = 0.175  # centro de cada rueda (por fuera de la espinilla)
CADERA_Y = 0.1
MUSLO = 0.44
ESPINILLA = 0.44
CADERA = (0.0, RUEDA_R + 0.8)  # x, z de la cadera de pie
CINTURA_Z = CADERA[1] + 0.15
PECHO = (0.3, 0.46, 0.34)  # fondo, ancho, alto
HOMBRO_Y = 0.255
HOMBRO_Z = CADERA[1] + 0.5
CUELLO_Z = CADERA[1] + 0.58
CODO_DER = (0.08, 1.11)  # x, z
CODO_IZQ = (0.08, 1.11)
MUNECA_IZQ = (0.34, 1.11)
ESCALA_GARRA = 1.4  # la garra de robot_soldado_mano.py, a la medida del brazo metralleta


def materiales():
    """Los de los robots del almacén, más el visor naranja (los crea una
    vez; en el Blender del dueño se guardan para las etapas siguientes)."""
    ns = bpy.app.driver_namespace
    if ns.get('soldadoMateriales'):
        return ns['soldadoMateriales']
    m = crearMateriales()
    m['visorLuz'] = materialLiso('soldadoVisorLuz', (1.0, 0.45, 0.08), 0.3, 0.0, 8.0)
    materialesReales(m)
    ns['soldadoMateriales'] = m
    return m


def placaFrente(a, b, fondo, desde, hasta, ancho, m):
    """Placa plateada pegada al frente de la pieza que va de `a` a `b`
    (x, y, z) con su `fondo`: sigue su eje entre las fracciones `desde` y
    `hasta`."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    n = Vector((-d.z, 0, d.x))  # perpendicular hacia delante (+x)
    if n.x < 0:
        n = -n
    off = n * (fondo / 2 + 0.004)
    return segmento('placa', a.lerp(b, desde) + off, a.lerp(b, hasta) + off, ancho, 0.01, m['plata'], 0.004)


def rodilla(cadera, pie):
    """Rodilla hacia delante entre la cadera y el pie (x, z)."""
    cx, cz = cadera
    px, pz = pie
    d = min(math.hypot(cx - px, cz - pz), MUSLO + ESPINILLA - 1e-4)
    a = math.acos((MUSLO ** 2 + d ** 2 - ESPINILLA ** 2) / (2 * MUSLO * d))
    base = math.atan2(pz - cz, px - cx)
    return cx + math.cos(base + a) * MUSLO, cz + math.sin(base + a) * MUSLO


# Rueda ---------------------------------------------------------------------------

def rueda(nombre, centro, lado, m, padre):
    """Rueda con motor en el buje: neumático de goma con hombro redondeado y
    tacos, llanta plateada de cinco radios y el motor oscuro atornillado por
    fuera."""
    cx, cy, cz = centro
    p = []
    p.append(cilindro(nombre + 'Neumatico', centro, RUEDA_R, RUEDA_ANCHO, m['goma'], eje='y', lados=128, bisel=0.022))
    # Tacos en espiga: dos filas desfasadas.
    n = 40
    for k in range(n):
        a = 2 * math.pi * k / n
        for fila, desfase in ((-1, 0.0), (1, 0.5)):
            b = a + desfase * 2 * math.pi / n
            r = RUEDA_R + 0.003
            t = caja(nombre + 'Taco', (0, 0, 0), (0.016, RUEDA_ANCHO * 0.36, 0.008), m['goma'], bisel=0.002)
            giro = Matrix.Rotation(-b, 4, 'Y') @ Matrix.Rotation(fila * 0.35, 4, 'X')
            t.data.transform(Matrix.Translation((cx + math.cos(b) * r, cy + fila * RUEDA_ANCHO * 0.2, cz + math.sin(b) * r)) @ giro)
            p.append(t)
    # Llanta y radios en la cara de fuera.
    yf = cy + lado * RUEDA_ANCHO / 2
    p.append(cilindro(nombre + 'Llanta', (cx, cy + lado * 0.004, cz), 0.1, RUEDA_ANCHO * 0.9, m['plata'], eje='y', lados=128, bisel=0.006))
    p.append(cilindro(nombre + 'Pestana', (cx, yf, cz), 0.104, 0.008, m['plata'], eje='y', lados=128, bisel=0.002))
    for k in range(5):
        a = 2 * math.pi * k / 5
        p.append(segmento(nombre + 'Radio', (cx + math.cos(a) * 0.045, yf + lado * 0.004, cz + math.sin(a) * 0.045), (cx + math.cos(a) * 0.095, yf + lado * 0.004, cz + math.sin(a) * 0.095), 0.012, 0.022, m['plata'], bisel=0.004))
    # Motor del buje y sus tornillos.
    p.append(cilindro(nombre + 'Motor', (cx, yf + lado * 0.006, cz), 0.05, 0.03, m['articulacion'], eje='y', lados=64, bisel=0.006))
    for k in range(6):
        a = 2 * math.pi * k / 6
        p += perno(nombre + 'Perno', (cx + math.cos(a) * 0.036, yf + lado * 0.021, cz + math.sin(a) * 0.036), (0, lado, 0), m, 0.006, material='acero')
    p.append(cilindro(nombre + 'Tapa', (cx, yf + lado * 0.022, cz), 0.018, 0.006, m['plata'], eje='y', lados=48, bisel=0.002))
    return pieza(nombre, p, centro, padre)


# Piernas ---------------------------------------------------------------------------

def pierna(lado, m, padre):
    sufijo = 'Izq' if lado > 0 else 'Der'
    y = lado * CADERA_Y
    cx, cz = CADERA
    kx, kz = rodilla(CADERA, (0.0, RUEDA_R))
    cadera = (cx, y, cz)
    rod = (kx, y, kz)
    eje = (0.0, y, RUEDA_R)
    # Muslo: carcasa negra con la franja blanca por fuera, remaches y la
    # articulación de la cadera.
    q = [
        segmento('muslo', cadera, rod, 0.12, 0.14, m['negro'], 0.04, -0.03),
        segmento('musloFranja', (cx, y + lado * 0.061, cz - 0.08), (kx, y + lado * 0.061, kz + 0.1), 0.006, 0.05, m['blanco'], 0.002),
        placaFrente(cadera, rod, 0.14, 0.25, 0.75, 0.08, m),
        cilindro('cadera', cadera, 0.07, 0.15, m['articulacion'], eje='y', lados=64, bisel=0.008),
    ]
    q += filaRemaches((cx, y + lado * 0.064, cz - 0.14), (kx, y + lado * 0.064, kz + 0.06), 5, (0, lado, 0), m, 0.006)
    for k in range(6):
        a = 2 * math.pi * k / 6
        q += perno('pernoCadera', (cx + math.cos(a) * 0.045, y + lado * 0.076, cz + math.sin(a) * 0.045), (0, lado, 0), m, 0.006, material='acero')
    muslo = pieza('muslo' + sufijo, q, cadera, padre)
    # Espinilla: más fina abajo, con la rodillera plateada y el eje de la
    # rueda saliendo hacia fuera.
    q = [
        segmento('espinilla', rod, (0.0, y, RUEDA_R + 0.04), 0.1, 0.12, m['negro'], 0.035, -0.02),
        placaFrente(rod, (0.0, y, RUEDA_R + 0.04), 0.12, 0.22, 0.72, 0.07, m),
        cilindro('rodilla', rod, 0.062, 0.14, m['articulacion'], eje='y', lados=64, bisel=0.008),
        esfera('rodillera', (kx + 0.05, y, kz), 0.05, m['negro'], (0.6, 1.0, 1.0)),
        cilindro('ejeRueda', (0.0, y + lado * (RUEDA_Y - CADERA_Y) / 2, RUEDA_R), 0.035, RUEDA_Y - CADERA_Y, m['articulacion'], eje='y', lados=48, bisel=0.004),
        cilindro('pie', (0.0, y, RUEDA_R), 0.055, 0.11, m['negro'], eje='y', lados=64, bisel=0.01),
    ]
    for s in (-1, 1):
        q.append(cilindro('tapaRodilla', (kx, y + s * 0.071, kz), 0.034, 0.006, m['plata'], eje='y', lados=48, bisel=0.002))
    espinilla = pieza('espinilla' + sufijo, q, rod, muslo)
    rueda('rueda' + sufijo, (0.0, lado * RUEDA_Y, RUEDA_R), lado, m, espinilla)
    return muslo


def etapaPiernas():
    m = materiales()
    cx, cz = CADERA
    q = [
        caja('pelvis', (cx, 0, cz + 0.04), (0.2, 0.3, 0.14), m['negro'], 0.04),
        caja('pelvisFranja', (cx + 0.101, 0, cz + 0.04), (0.006, 0.14, 0.08), m['blanco'], 0.002),
    ]
    for s in (-1, 1):
        q += perno('pernoPelvis', (cx + 0.102, s * 0.1, cz + 0.07), (1, 0, 0), m, 0.007, material='acero')
    pelvis = pieza('pelvis', q, (cx, 0, cz))
    for lado in (1, -1):
        pierna(lado, m, pelvis)
    return pelvis


# Torso y cabeza ---------------------------------------------------------------------

def etapaTorso():
    """Cintura giratoria, abdomen, pecho blindado con placa plateada y franja
    blanca, mochila de baterías con rejillas y los soportes de los hombros;
    encima, el cuello y la cabeza con el visor."""
    m = materiales()
    pelvis = bpy.data.objects['pelvis']
    cx = CADERA[0]
    z0 = CINTURA_Z
    f, w, h = PECHO
    zp = z0 + 0.05 + h / 2 + 0.07  # centro del pecho
    q = [
        cilindro('cintura', (cx, 0, z0), 0.095, 0.07, m['articulacion'], lados=64, bisel=0.008),
        caja('abdomen', (cx, 0, z0 + 0.09), (0.2, 0.28, 0.12), m['negro'], 0.035),
        caja('pecho', (cx, 0, zp), (f, w, h), m['negro'], 0.07),
        caja('placaPecho', (cx + f / 2 + 0.004, 0, zp + 0.03), (0.012, w * 0.62, h * 0.5), m['plata'], 0.005),
        caja('franjaPecho', (cx + f / 2 + 0.003, 0, zp - h * 0.33), (0.008, w * 0.5, 0.025), m['blanco'], 0.003),
        caja('mochila', (cx - f / 2 - 0.05, 0, zp), (0.11, w * 0.7, h * 0.85), m['articulacion'], 0.03),
    ]
    for k in range(8):
        a = 2 * math.pi * k / 8
        q += perno('pernoCintura', (cx + math.cos(a) * 0.075, math.sin(a) * 0.075, z0 + 0.036), (0, 0, 1), m, 0.006, material='acero')
    for sy in (-1, 1):
        for sz in (-1, 1):
            q += perno('pernoPlaca', (cx + f / 2 + 0.01, sy * w * 0.26, zp + 0.03 + sz * h * 0.19), (1, 0, 0), m, 0.007, material='acero')
    # Rejillas de la mochila.
    for k in range(6):
        q.append(caja('rejilla', (cx - f / 2 - 0.106, 0, zp - h * 0.25 + k * h * 0.1), (0.006, w * 0.5, 0.012), m['negroMate'], 0.002))
    # Soportes de los hombros (los hombros giran en ellos).
    for lado in (-1, 1):
        q.append(cilindro('soporteHombro', (cx, lado * (w / 2 + 0.005), HOMBRO_Z), 0.07, 0.04, m['articulacion'], eje='y', lados=64, bisel=0.006))
    q += filaRemaches((cx + f / 2 - 0.01, -w * 0.4, zp + h / 2 - 0.012), (cx + f / 2 - 0.01, w * 0.4, zp + h / 2 - 0.012), 9, (0, 0, 1), m, 0.006)
    torso = pieza('torso', q, (cx, 0, z0), pelvis)
    etapaCabeza(m, torso)
    return torso


CUELLO = 0.13  # alto del cuello (el dueño, 17-nov: «el cuello más largo»)
OJO_Y = 0.052  # |y| de cada ojo
OJO_HUNDIDO = 0.012  # lo que se mete el ojo en la cara
OJO_ESCALA = 0.95  # los ojos del robot pequeño, a esta escala


def etapaCabeza(m=None, torso=None, cx=None, zc=None, conCuello=True):
    """Cuello de articulación con dos anillos plateados y la cabeza encima:
    casco negro con los dos ojos mecánicos. El cuello gira con ella.
    Es la cabeza de toda la familia de robots: otro robot (el pequeño del
    almacén) la pone sobre su propio cuello con `conCuello=False`, `torso`
    = su pieza del cuello y `zc` = lo alto de su cuello."""
    m = m or materiales()
    torso = torso or bpy.data.objects['torso']
    cx = CADERA[0] if cx is None else cx
    zc = CUELLO_Z if zc is None else zc
    hc = zc + CUELLO + 0.08 if conCuello else zc + 0.1
    q = []
    if conCuello:
        q += [
            cilindro('cuello', (cx, 0, zc + CUELLO / 2), 0.042, CUELLO + 0.02, m['articulacion'], lados=48, bisel=0.006),
            cilindro('baseCuello', (cx, 0, zc + 0.012), 0.065, 0.024, m['negro'], lados=64, bisel=0.006),
        ]
        for k in range(2):
            q.append(cilindro('anilloCuello', (cx, 0, zc + 0.05 + k * 0.045), 0.05, 0.012, m['plata'], lados=48, bisel=0.003))
        for s in (-1, 1):
            q.append(segmento('cableCuello', (cx - 0.035, s * 0.03, zc + 0.02), (cx - 0.035, s * 0.03, hc - 0.07), 0.012, 0.012, m['negroMate'], 0.005))
    q += [
        caja('casco', (cx, 0, hc), (0.22, 0.2, 0.2), m['negro'], 0.045),
        caja('cascoCresta', (cx - 0.01, 0, hc + 0.1), (0.16, 0.05, 0.02), m['negro'], 0.008),
    ]
    for s in (-1, 1):
        q.append(cilindro('antena', (cx - 0.03, s * 0.104, hc + 0.12), 0.004, 0.12, m['acero'], lados=12))
    q += mascara(m, cx + 0.11, hc)
    # Ojos (los del robot pequeño del almacén, robot_almacen.py): carcasa
    # con bisel dentado, aro de cobre que gira, diafragma de 18 láminas,
    # núcleo cian y párpados blindados que se cierran hacia el centro.
    xf = cx + 0.11 - OJO_HUNDIDO
    zo = hc + 0.012
    for lado in (-1, 1):
        q += cuencaPersiana(m, xf, lado * OJO_Y, zo, OJO_ESCALA)
        # Cuenca: el tubo del ojo viene desde dentro del casco (sin hueco
        # detrás donde la cara se curva) y un collar donde sale de la chapa.
        rc = OJO_RADIO * OJO_ESCALA + 0.003
        q.append(cilindro('cuencaOjo', ((cx + 0.04 + xf) / 2, lado * OJO_Y, zo), rc, xf - cx - 0.04, m['negro'], eje='x', lados=96, bisel=0.002))
        q.append(aro('collarOjo', (cx + 0.11 - 0.002, lado * OJO_Y, zo), rc - 0.001, rc + 0.006, 0.006, m['articulacion'], lados=96, bisel=0.0015))
    cabeza = pieza('cabeza', q, (cx, 0, zc), torso)
    for lado, s in ((1, 'Izq'), (-1, 'Der')):
        globoOjo(m, xf, lado * OJO_Y, zo, s, cabeza)
        oido(m, cx, hc, lado, s, cabeza)
        # Los párpados de media luna del robot pequeño no tapan el ojo
        # entero: aquí, persianas de láminas.
        for n in ('parpadoSup', 'parpadoInf'):
            viejo = bpy.data.objects.get(n + s)
            if viejo:
                bpy.data.objects.remove(viejo, do_unlink=True)
        persianas(m, xf, lado * OJO_Y, zo, OJO_ESCALA, s, cabeza)
    return cabeza


def mandibula(nombre, cx, xf, hc, material):
    """Volumen de la mandíbula: sale de la parte de abajo del casco (mismo
    ancho y fondo) y se estrecha hacia el mentón; envoltura convexa con los
    cantos redondeados, para que casco y cara sean una sola cabeza."""
    bm = bmesh.new()
    arriba, abajo = hc - 0.05, hc - 0.14
    puntos = []
    for x in (cx - 0.1, xf):
        for y in (-0.1, 0.1):
            puntos.append((x, y, arriba))
    for x in (cx - 0.01, xf):
        for y in (-0.05, 0.05):
            puntos.append((x, y, abajo))
    vs = [bm.verts.new(v) for v in puntos]
    bmesh.ops.convex_hull(bm, input=vs)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.018, segments=4, affect='EDGES', profile=0.5, clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return objetoDe(nombre, bm, material)


def mascara(m, xf, hc):
    """Cara bajo los ojos (el dueño, 17-nov: «que tenga su mentón», y que no
    parezca una pieza pegada): la mandíbula negra sale del casco y se
    estrecha hasta el mentón; la máscara es un panel a ras de ella con su
    junta oscura, la boca redonda con aro dentado de cobre y lamas, el
    mentón plateado que sobresale, y rejillas en las mejillas. Diseño propio."""
    giro = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # x->y, y->z, z->x
    cx = xf - 0.11

    def placa(nombre, puntos, grosor, x, material, bisel=0.002):
        o = perfilExtruido(nombre, puntos, grosor, material, bisel)
        o.data.transform(Matrix.Translation((x, 0, 0)) @ giro)
        return o

    p = [mandibula('mandibula', cx, xf, hc, m['negro'])]
    # Panel en escudo a ras del frente (sobresale 2 mm) y la junta oscura
    # un poco más grande por debajo.
    escudo = [(-0.075, hc - 0.04), (0.075, hc - 0.04), (0.068, hc - 0.075), (0.04, hc - 0.122), (-0.04, hc - 0.122), (-0.068, hc - 0.075)]
    junta = [(-0.08, hc - 0.036), (0.08, hc - 0.036), (0.072, hc - 0.076), (0.042, hc - 0.126), (-0.042, hc - 0.126), (-0.072, hc - 0.076)]
    p.append(placa('juntaMascara', junta, 0.002, xf + 0.0005, m['negroMate'], 0.0))
    p.append(placa('mascara', escudo, 0.004, xf + 0.001, m['articulacion'], 0.0012))
    xs = xf + 0.003  # superficie del panel
    for s in (-1, 1):
        p.append(segmento('nervioMascara', (xs + 0.001, s * 0.06, hc - 0.05), (xs + 0.001, s * 0.03, hc - 0.072), 0.005, 0.004, m['plata'], 0.0015))
        p += perno('pernoMascara', (xs, s * 0.06, hc - 0.068), (1, 0, 0), m, 0.004, material='acero')
    # Boca redonda.
    zb = hc - 0.084
    p.append(cilindro('fondoBoca', (xs, 0, zb), 0.024, 0.002, m['negroMate'], eje='x', lados=64))
    p.append(aro('aroBoca', (xs + 0.002, 0, zb), 0.024, 0.03, 0.004, m['cobre'], lados=96, bisel=0.0008))
    for k in range(36):
        a = 2 * math.pi * k / 36
        diente = caja('dienteBoca', (0, 0, 0), (0.003, 0.0024, 0.0024), m['cobre'], 0.0004)
        diente.data.transform(Matrix.Rotation(math.pi / 4, 4, 'X'))
        p.append(enDisco(diente, (xs + 0.002, 0, zb), a, 0.031))
    for k in range(5):
        y = -0.016 + k * 0.008
        alto = 2 * math.sqrt(max(0.0, 0.022 ** 2 - y * y))
        p.append(caja('lamaBoca', (xs + 0.002, y, zb), (0.003, 0.0045, alto), m['acero'], 0.001))
    # Mentón: arranca dentro de la mandíbula, baja de la boca y sobresale.
    p.append(caja('menton', (xf + 0.008, 0, hc - 0.128), (0.03, 0.036, 0.034), m['plata'], 0.008))
    p.append(caja('travesanoMenton', (xf + 0.022, 0, hc - 0.134), (0.008, 0.044, 0.01), m['articulacion'], 0.003))
    for s in (-1, 1):
        p.append(cilindro('tornilloMenton', (xf + 0.0235, s * 0.011, hc - 0.118), 0.003, 0.003, m['acero'], eje='x', lados=6))
    # Rejillas de las mejillas, en los lados del casco.
    for s in (-1, 1):
        y = s * 0.1
        p.append(caja('mejilla', (cx + 0.06, y, hc - 0.045), (0.06, 0.008, 0.06), m['negro'], 0.006))
        for k in range(4):
            p.append(caja('lamaMejilla', (cx + 0.039 + k * 0.014, y + s * 0.0045, hc - 0.045), (0.006, 0.003, 0.046), m['negroMate'], 0.0012))
    return p

# Ojo esférico (el dueño, 17-nov): el ojo es una bola en la cuenca que gira
# sobre su centro (`globo{S}`: en z mira a los lados, en y arriba y abajo,
# hasta unos 20°); las piezas del ojo del robot pequeño (diafragma, núcleo,
# aro de cobre) van a GLOBO_IRIS de su tamaño en un corte plano delante.
GLOBO_R = 0.0335  # radio de la bola (a OJO_ESCALA 1); el agujero es 0,034
GLOBO_IRIS = 0.8
GLOBO_ATRAS = 0.01  # el centro de la bola, detrás de la base del ojo
DIAFRAGMA_PUNTA = 0.009  # lo que sale hacia delante el centro del diafragma (cono)
GLOBO_CORTE = 0.0211  # del centro al corte plano: ahí la bola mide lo que el aro de cobre


def globoOjo(m, xf, y, zo, s, cabeza):
    e = OJO_ESCALA
    ei = e * GLOBO_IRIS
    xc = xf - GLOBO_ATRAS * e
    xCorte = xc + GLOBO_CORTE * e
    rCorte = 0.0325 * ei
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=GLOBO_R * e)
    bmesh.ops.translate(bm, vec=Vector((xc, y, zo)), verts=bm.verts)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(xCorte, y, zo), plane_no=(1, 0, 0), clear_outer=True)
    bola = objetoDe('globo', bm, m['articulacion'])
    tapa = cilindro('tapaGlobo', (xCorte - 0.0006 * e, y, zo), rCorte, 0.0012 * e, m['negroMate'], eje='x', lados=96)
    globo = pieza('globo' + s, [bola, tapa], (xc, y, zo), cabeza)
    # ojoPiezas pone el fondo del iris en xf2 + 0,012·ei: justo en el corte.
    ojoPiezas(m, xCorte - 0.012 * ei, y, zo, ei, s, globo)
    # Diafragma en punta (el dueño, 17-nov): cada lámina se levanta hacia
    # delante según se acerca al centro; entre todas forman un cono.
    rPivote = OJO_PIVOTE * ei
    alto = DIAFRAGMA_PUNTA * e
    for k in range(OJO_HOJAS):
        o = bpy.data.objects['hoja%s%02d' % (s, k)]
        mw = o.matrix_world.copy()
        inv = mw.inverted()
        for v in o.data.vertices:
            w = mw @ v.co
            r = math.hypot(w.y - y, w.z - zo)
            w.x += alto * max(0.0, 1.0 - r / rPivote)
            v.co = inv @ w
        o.data.update()
    return globo


# Oídos (el dueño, 17-nov): en cada sien, una pieza redonda metida en la
# cabeza como los ojos (carcasa, bisel dentado, collar) con tres anillos
# dentados uno dentro de otro que giran en sentidos opuestos: `oido{S}A`
# (fuera, acero), `oido{S}B` (medio, cobre) y `oido{S}C` (centro, acero).
# Giran en y: A y C en un sentido, B en el otro.
OIDO_ESCALA = 0.9


def oido(m, cx, hc, lado, s, cabeza, lleva=None, nombre='oido'):
    """Los tres anillos dentados que giran (oídos). `lleva` (opcional) pone
    el conjunto en otro sitio y a otra escala, modelado mirando a +x con
    x = 0 en la chapa: el robot grande lo lleva en el pecho
    (robot_pesado.py). Piezas `<nombre><s>` y `<nombre><s>A/B/C`."""
    E = OIDO_ESCALA
    if lleva is None:
        centro = Vector((cx - 0.01, lado * 0.1, hc + 0.015))
        # Se modela mirando a +x en el origen (x = 0 en la chapa de la sien) y
        # se lleva a la sien: +x pasa a ser ±y.
        lleva = Matrix.Translation(centro) @ Matrix.Rotation(lado * math.pi / 2, 4, 'Z')
    else:
        centro = lleva.to_translation()

    def dientes(nombre, x, r, n, tam, material):
        lista = []
        for k in range(n):
            d = caja(nombre, (0, 0, 0), tam, material, 0.0004)
            lista.append(enDisco(d, (x, 0, 0), 2 * math.pi * k / n, r))
        return lista

    def colocar(lista):
        for o in lista:
            o.data.transform(lleva)
        return lista

    fijo = [
        aro('carcasaOido', (0.0045, 0, 0), 0.032 * E, 0.04 * E, 0.017, m['negro'], bisel=0.0015),
        aro('biselOido', (0.0135, 0, 0), 0.033 * E, 0.039 * E, 0.003, m['acero'], bisel=0.0005),
        aro('collarOido', (0.0005, 0, 0), 0.0395 * E, 0.046 * E, 0.004, m['articulacion'], bisel=0.0012),
        cilindro('fondoOido', (0.0008, 0, 0), 0.032 * E, 0.002, m['negroMate'], eje='x', lados=96),
        aro('brilloOido', (0.0022, 0, 0), 0.0195 * E, 0.022 * E, 0.001, m['nucleo'], lados=96),
        aro('brilloOido', (0.0022, 0, 0), 0.0095 * E, 0.0118 * E, 0.001, m['nucleo'], lados=96),
    ]
    fijo += dientes('dienteBiselOido', 0.0152, 0.036 * E, 36, (0.0025, 0.0024, 0.0024), m['acero'])
    for k in range(6):
        tornillo = cilindro('tornilloOido', (0, 0, 0), 0.0016, 0.002, m['acero'], eje='x', lados=6)
        fijo.append(enDisco(tornillo, (0.003, 0, 0), k * math.pi / 3 + math.pi / 6, 0.0428 * E))
    pieza(nombre + s, colocar(fijo), tuple(centro), cabeza)

    anillos = (
        ('A', 0.004, 0.022, 0.0285, 30, m['acero']),
        ('B', 0.0065, 0.012, 0.0185, 22, m['cobre']),
        ('C', 0.009, 0.0, 0.0085, 12, m['acero']),
    )
    for letra, x, rIn, rOut, n, material in anillos:
        if rIn > 0:
            partes = [aro('anilloOido', (x, 0, 0), rIn * E, rOut * E, 0.003, material, lados=128, bisel=0.0005)]
        else:
            partes = [cilindro('ruedaOido', (x, 0, 0), rOut * E, 0.003, material, eje='x', lados=96, bisel=0.0005)]
            partes.append(cilindro('cuboOido', (x + 0.002, 0, 0), 0.0042 * E, 0.002, m['articulacion'], eje='x', lados=48, bisel=0.0005))
            partes.append(cilindro('tuercaOido', (x + 0.0035, 0, 0), 0.0022 * E, 0.0015, m['acero'], eje='x', lados=6))
        partes += dientes('dienteOido', x, (rOut + 0.0012) * E, n, (0.0028, 0.0026 * E, 0.0026 * E), material)
        # Ranuras oscuras en la cara, para que se vea girar.
        for k in range(6 if rIn > 0 else 3):
            a = 2 * math.pi * k / (6 if rIn > 0 else 3)
            r = (rIn + rOut) / 2 if rIn > 0 else rOut * 0.72
            ranura = caja('ranuraOido', (0, 0, 0), (0.0008, 0.0012, 0.0035 * E), m['negroMate'])
            partes.append(enDisco(ranura, (x + 0.0015, 0, 0), a, r * E))
        pieza('%s%s%s' % (nombre, s, letra), colocar(partes), tuple(centro), cabeza)

# Párpados de persiana (el dueño, 17-nov: «solo se unen las dos piezas en
# medio»): cada párpado son PERSIANA_LAMINAS láminas finas detrás del bisel.
# En reposo (abierto) están apiladas en el borde del ojo y solo se ve la
# franja de la primera; al cerrar, la lámina k baja (o sube) k alturas y
# entre todas tapan el ojo entero hasta el centro. El juego mueve
# `persianaSup{S}{k}` en -z y `persianaInf{S}{k}` en +z: k · PERSIANA_PASO
# por la fracción cerrada.
PERSIANA_LAMINAS = 4
PERSIANA_TUBO = 0.007  # lo que se alarga el tubo del ojo hacia delante para que quepan
PERSIANA_R = 0.0338  # radio que tapan (el agujero del ojo es de 0,034)
PERSIANA_PASO = PERSIANA_R / PERSIANA_LAMINAS


def cuencaPersiana(m, xf, y, zo, e):
    """La cuenca del robot pequeño con el tubo alargado: el bisel, sus
    dientes y tornillos van PERSIANA_TUBO más adelante y en medio queda el
    hueco de las láminas."""
    ext = PERSIANA_TUBO * e
    p = ojoCuenca(m, xf, y, zo, e, 1)
    for o in p:
        if o.name.startswith(('bisel', 'fondoBisel', 'dienteBisel', 'tornilloOjo')):
            o.data.transform(Matrix.Translation((ext, 0, 0)))
    xFrente = xf + OJO_SALIENTE * e
    p.append(aro('tuboPersiana', (xFrente + ext / 2, y, zo), 0.034 * e, OJO_RADIO * e, ext + 0.002 * e, m['negro']))
    return p


def persianas(m, xf, y, zo, e, s, cabeza):
    R = PERSIANA_R * e
    h = PERSIANA_PASO * e
    Rtubo = (OJO_RADIO - 0.0012) * e  # lo que tapa la pared del tubo
    xFrente = xf + (OJO_SALIENTE + PERSIANA_TUBO - 0.0012) * e
    giro = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # x->y, y->z, z->x
    for nombre, signo, extra in (('persianaSup', 1, 0.0), ('persianaInf', -1, 0.00055)):
        for k in range(PERSIANA_LAMINAS):
            # Franja que tapa cerrada (desde el borde hacia el centro, con
            # un poco de solape); de pie se apila k pasos hacia el borde.
            z1 = R - k * h
            z0 = max(-0.0006 * e, R - (k + 1.3) * h)
            sube = k * h
            borde = []
            n = 16
            for i in range(n + 1):
                z = z0 + (z1 - z0) * i / n
                # Dentro del agujero cerrada y dentro de la pared del tubo apilada.
                a = R * R - z * z
                b = Rtubo * Rtubo - (z + sube) ** 2
                xl = math.sqrt(max(0.0, min(a, b)))
                borde.append((xl, z))
            puntos = [(x, z) for x, z in borde] + [(-x, z) for x, z in reversed(borde)]
            puntos = [(x, signo * z) for x, z in puntos]
            if signo < 0:
                puntos.reverse()
            # Quita puntos repetidos (las puntas de ancho 0).
            limpios = []
            for pt in puntos:
                if not limpios or (abs(pt[0] - limpios[-1][0]) > 1e-7 or abs(pt[1] - limpios[-1][1]) > 1e-7):
                    limpios.append(pt)
            lamina = perfilExtruido('lamina', limpios, 0.0007 * e, m['gris'], 0.00015 * e)
            zCanto = signo * z0
            xCanto = math.sqrt(max(0.0, min(R * R - z0 * z0, Rtubo * Rtubo - (z0 + sube) ** 2)))
            canto = segmento('cantoLamina', (-xCanto * 0.96, zCanto + signo * 0.0006 * e, 0.0006 * e), (xCanto * 0.96, zCanto + signo * 0.0006 * e, 0.0006 * e), 0.0009 * e, 0.0005 * e, m['negro'])
            x = xFrente - (k * 0.0011 + extra) * e
            for o in (lamina, canto):
                o.data.transform(Matrix.Translation((x, y, zo + signo * sube)) @ giro)
            pieza('%s%s%d' % (nombre, s, k), [lamina, canto], (x, y, zo + signo * sube), cabeza)


# Brazos ------------------------------------------------------------------------------

def brazoSuperior(lado, codo, m, torso):
    """Hombro y brazo: articulación de cilindro (gira en y) con la hombrera
    encima, brazo de carcasa negra con la tapa plateada por fuera y un
    pistón hidráulico por detrás (del hombro al codo), y el codo."""
    sufijo = 'Izq' if lado > 0 else 'Der'
    y = lado * (PECHO[1] / 2 + 0.065)
    hombro = (CADERA[0], y, HOMBRO_Z)
    cod = (codo[0], y, codo[1])
    q = [
        cilindro('hombro', hombro, 0.07, 0.1, m['articulacion'], eje='y', lados=64, bisel=0.008),
        cilindro('tapaHombro', (hombro[0], y + lado * 0.052, hombro[2]), 0.045, 0.008, m['plata'], eje='y', lados=48, bisel=0.002),
        caja('hombrera', (CADERA[0] - 0.005, y + lado * 0.01, HOMBRO_Z + 0.075), (0.16, 0.12, 0.035), m['negro'], 0.015),
        caja('hombreraFranja', (CADERA[0] - 0.005, y + lado * 0.071, HOMBRO_Z + 0.075), (0.12, 0.004, 0.016), m['blanco'], 0.001),
        segmento('brazo', (hombro[0], y, hombro[2] - 0.05), cod, 0.085, 0.095, m['negro'], 0.035, -0.03),
        segmento('brazoTapa', (hombro[0] + 0.005, y + lado * 0.045, hombro[2] - 0.09), (cod[0] - 0.005, y + lado * 0.045, cod[2] + 0.07), 0.006, 0.05, m['plata'], 0.002),
        cilindro('codo', cod, 0.05, 0.11, m['articulacion'], eje='y', lados=64, bisel=0.006),
    ]
    for k in range(6):
        a = 2 * math.pi * k / 6
        q += perno('pernoHombro', (hombro[0] + math.cos(a) * 0.055, y + lado * 0.051, hombro[2] + math.sin(a) * 0.055), (0, lado, 0), m, 0.005, material='acero')
    for s in (-1, 1):
        q.append(cilindro('tapaCodo', (cod[0], y + s * 0.056, cod[2]), 0.028, 0.006, m['plata'], eje='y', lados=48, bisel=0.002))
    # Pistón por detrás: camisa negra arriba, vástago de acero abajo, con
    # sus rótulas.
    pa = Vector((hombro[0] - 0.06, y, hombro[2] - 0.06))
    pb = Vector((cod[0] - 0.06, y, cod[2] + 0.02))
    pm = pa.lerp(pb, 0.55)
    q.append(segmento('camisaPiston', pa, pm, 0.026, 0.026, m['articulacion'], 0.012))
    q.append(segmento('vastagoPiston', pm, pb, 0.012, 0.012, m['acero'], 0.005))
    for c in (pa, pb):
        q.append(cilindro('rotulaPiston', tuple(c), 0.014, 0.034, m['plata'], eje='y', lados=32, bisel=0.003))
    brazo = pieza('hombro' + sufijo, q, hombro, torso)
    return brazo, cod


def etapaBrazoArma():
    """Brazo derecho: el antebrazo es la metralleta (carcasa con rejillas
    y el tambor de tres cañones, que gira aparte)."""
    m = materiales()
    torso = bpy.data.objects['torso']
    brazo, cod = brazoSuperior(-1, CODO_DER, m, torso)
    x0, y, z = cod
    largo = 0.36
    q = [
        segmento('carcasaArma', (x0, y, z), (x0 + largo, y, z + 0.01), 0.13, 0.14, m['negro'], 0.04, -0.02),
        segmento('placaArma', (x0 + 0.05, y - 0.068, z + 0.005), (x0 + largo - 0.04, y - 0.068, z + 0.01), 0.006, 0.09, m['plata'], 0.003),
        cilindro('collarin', (x0 + largo + 0.01, y, z + 0.01), 0.062, 0.05, m['articulacion'], eje='x', lados=64, bisel=0.006),
    ]
    for k in range(5):
        q.append(caja('rejillaArma', (x0 + 0.08 + k * 0.045, y, z + 0.081), (0.022, 0.09, 0.006), m['negroMate'], 0.002))
    for k in range(6):
        a = 2 * math.pi * k / 6
        q += perno('pernoCollarin', (x0 + largo + 0.036, y + math.cos(a) * 0.047, z + 0.01 + math.sin(a) * 0.047), (1, 0, 0), m, 0.005, material='acero')
    q += filaRemaches((x0 + 0.05, y + 0.066, z - 0.04), (x0 + largo - 0.04, y + 0.066, z - 0.035), 5, (0, 1, 0), m, 0.005)
    arma = pieza('metralleta', q, cod, brazo)
    # Tambor de tres cañones: gira en x al disparar.
    eje = (x0 + largo + 0.035, y, z + 0.01)
    q = [cilindro('ejeCanones', (eje[0] + 0.15, y, eje[2]), 0.012, 0.3, m['acero'], eje='x', lados=24)]
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        dy, dz = math.cos(a) * 0.028, math.sin(a) * 0.028
        q.append(cilindro('canon', (eje[0] + 0.16, y + dy, eje[2] + dz), 0.013, 0.32, m['acero'], eje='x', lados=32, bisel=0.002))
        q.append(cilindro('bocaCanon', (eje[0] + 0.32, y + dy, eje[2] + dz), 0.007, 0.004, m['negroMate'], eje='x', lados=24))
    for xa in (0.04, 0.2, 0.3):
        q.append(cilindro('abrazadera', (eje[0] + xa, y, eje[2]), 0.05, 0.016, m['negro'], eje='x', lados=64, bisel=0.004))
    pieza('canones', q, eje, arma)
    return brazo


def etapaBrazoGarra():
    """Brazo izquierdo: antebrazo con la muñeca, y la garra
    (robot_soldado_mano.py) colgada de ella, apuntando hacia delante."""
    m = materiales()
    torso = bpy.data.objects['torso']
    brazo, cod = brazoSuperior(1, CODO_IZQ, m, torso)
    x0, y, z = cod
    mun = (MUNECA_IZQ[0], y, MUNECA_IZQ[1])
    q = [
        segmento('antebrazo', cod, mun, 0.085, 0.09, m['negro'], 0.03, -0.01),
        segmento('antebrazoTapa', (x0 + 0.03, y + 0.046, z), (mun[0] - 0.04, y + 0.046, mun[2]), 0.006, 0.05, m['plata'], 0.002),
        cilindro('muneca', mun, 0.035, 0.03, m['articulacion'], eje='x', lados=48, bisel=0.004),
    ]
    q += filaRemaches((x0 + 0.04, y - 0.044, z + 0.02), (mun[0] - 0.05, y - 0.044, mun[2] + 0.02), 4, (0, -1, 0), m, 0.005)
    antebrazo = pieza('codoIzq', q, cod, brazo)
    mano = bpy.data.objects.get('mano')
    if mano:
        # La garra se hizo con los dedos hacia +z: se tumba hacia +x.
        mano.parent = None
        mano.matrix_world = Matrix.Translation((mun[0] + 0.015, y, mun[2])) @ Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Scale(ESCALA_GARRA, 4)
        bpy.context.view_layer.update()
        mundo = mano.matrix_world.copy()
        mano.parent = antebrazo
        mano.matrix_world = mundo
    return brazo


# Poses (el dueño, 17-nov). `poseSoldado(nombre, f)` mezcla de pie (0) a la
# pose (1); el Lua del juego hace lo mismo con estos números.
#   patinar:  solo al correr, como en patinete: cadera baja y atrás, rodillas
#             dobladas, torso adelante; el arma al frente y la garra relajada
#             algo atrás para equilibrar.
#   disparar: de pie y firme, rodillas apenas dobladas, torso casi recto, la
#             metralleta a la altura del pecho apuntando al frente.
# En las dos la garra va relajada al costado con los dedos medio cerrados
# («la mano que no tiene arma, normal, no como si fuera a agarrar algo»).
# Ángulos en rad, giros en y (positivo: hacia delante para el torso, hacia
# atrás para el brazo). `brazoArma` y `brazoGarra`: ángulo del brazo
# superior respecto a la vertical del mundo (negativo = adelantado);
# `antebrazoGarra`: del antebrazo bajo la horizontal.
POSES = {
    'de_pie': {'caderaX': CADERA[0], 'caderaZ': CADERA[1], 'torso': 0.0,
               'brazoArma': 0.0, 'brazoGarra': 0.0, 'antebrazoGarra': 0.0, 'dedos': (-0.45, 0.42, 0.18)},
    'patinar': {'caderaX': -0.1, 'caderaZ': RUEDA_R + 0.6, 'torso': math.radians(38),
                'brazoArma': -0.1, 'brazoGarra': 0.3, 'antebrazoGarra': 1.15, 'dedos': (-0.1, 0.5, 0.35)},
    'disparar': {'caderaX': -0.03, 'caderaZ': CADERA[1] - 0.05, 'torso': math.radians(8),
                 'brazoArma': -0.75, 'brazoGarra': 0.08, 'antebrazoGarra': 1.25, 'dedos': (-0.1, 0.5, 0.35)},
}


def _angulo(v):
    """Ángulo en el plano x-z medido desde +z hacia +x (lo que suma un giro
    positivo en y)."""
    return math.atan2(v[0], v[1])


def poseSoldado(nombre, f=1.0):
    O = bpy.data.objects
    A, B = POSES['de_pie'], POSES[nombre]

    def mezcla(k):
        return A[k] + (B[k] - A[k]) * f

    hx, hz = mezcla('caderaX'), mezcla('caderaZ')
    O['pelvis'].location = (hx, 0, hz)
    rueda = (0.0, RUEDA_R)
    k0 = rodilla(CADERA, rueda)
    k1 = rodilla((hx, hz), rueda)
    muslo0 = _angulo((k0[0] - CADERA[0], k0[1] - CADERA[1]))
    espinilla0 = _angulo((rueda[0] - k0[0], rueda[1] - k0[1]))
    muslo = _angulo((k1[0] - hx, k1[1] - hz)) - muslo0
    espinilla = _angulo((rueda[0] - k1[0], rueda[1] - k1[1])) - espinilla0 - muslo
    for s in ('Izq', 'Der'):
        O['muslo' + s].rotation_euler.y = muslo
        O['espinilla' + s].rotation_euler.y = espinilla
        O['rueda' + s].rotation_euler.y = -(muslo + espinilla)
    torso = mezcla('torso')
    O['torso'].rotation_euler.y = torso
    O['cabeza'].rotation_euler.y = -torso
    # Brazo del arma: el superior a su ángulo y el antebrazo horizontal.
    # (El brazo superior en reposo baja del hombro al codo algo adelantado;
    # el giro se cuenta desde ahí.)
    hombroArma = mezcla('brazoArma') - torso
    O['hombroDer'].rotation_euler.y = hombroArma
    O['metralleta'].rotation_euler.y = -(torso + hombroArma)
    # Garra: brazo colgando y antebrazo hacia abajo, relajado.
    hombroGarra = mezcla('brazoGarra') - torso
    O['hombroIzq'].rotation_euler.y = hombroGarra
    O['codoIzq'].rotation_euler.y = mezcla('antebrazoGarra') - (torso + hombroGarra)
    dedos = [A['dedos'][i] + (B['dedos'][i] - A['dedos'][i]) * f for i in range(3)]
    for d in ('A', 'B', 'C'):
        for i in range(3):
            o = O.get('dedo%s%d' % (d, i + 1))
            if o:
                o.rotation_euler.y = dedos[i]


def crearGarra():
    """La garra de robot_soldado_mano.py (sin su principal(), que renderiza)."""
    ruta = os.path.join(_DIR, 'robot_soldado_mano.py')
    with open(ruta, encoding='utf8') as archivo:
        fuente = archivo.read()
    ns = {'__name__': 'garra', '__file__': ruta}
    exec(fuente[:fuente.index('def renderizarMano(')], ns)
    return ns['crearMano']('abierta')


def construir(brazoDerecho=None, brazoIzquierdo=None, limpiar=True):
    """El robot entero: piernas con rueda, torso, cabeza (ojos, oídos,
    mentón) y los dos brazos. Es la base de toda la familia de robots: un
    robot nuevo (reconocimiento, zapador, médico…) llama a esto y solo
    cambia el brazo (o lo que haga falta) pasando su propia etapa:

        construir(brazoDerecho=etapaBrazoSensor)

    Cada etapa de brazo recibe nada y cuelga lo suyo de `torso` con
    brazoSuperior(lado, codo, materiales(), torso)."""
    if limpiar:
        limpiarEscena()
    etapaPiernas()
    etapaTorso()
    (brazoDerecho or etapaBrazoArma)()
    if brazoIzquierdo is None:
        crearGarra()
        etapaBrazoGarra()
    else:
        brazoIzquierdo()
    return bpy.data.objects['pelvis']


RAIZ = os.path.abspath(os.path.join(_DIR, '..', '..'))
GLB_JUEGO = os.path.join(RAIZ, 'assets', 'batalla', 'robots', 'soldado.glb')


def exportarJuego(ruta=GLB_JUEGO, raiz='pelvis', conservarUv=()):
    """Al juego, como el robot del almacén (robot_almacen.py exportarJuego):
    `ruta` (.glb) con cada pieza en el origen y su malla en sus ejes locales,
    y al lado <nombre>_piezas.lua con cada pieza, su padre y su matriz de
    reposo respecto a él (filas; ejes del juego = los del modelo: x delante,
    y izquierda, z arriba, metros). Antes se deja en la pose de pie."""
    if bpy.data.objects.get('torso'):
        poseSoldado('de_pie', 0.0)
    bpy.context.view_layer.update()
    orden = []

    def visitar(objeto):
        orden.append(objeto)
        for hija in sorted(objeto.children, key=lambda o: o.name):
            visitar(hija)

    visitar(bpy.data.objects[raiz])
    lineas = []
    locales = {}
    padres = {}
    nombresOrden = []
    for objeto in orden:
        padre = objeto.parent.name if objeto.parent else None
        local = objeto.parent.matrix_world.inverted() @ objeto.matrix_world if objeto.parent else objeto.matrix_world.copy()
        locales[objeto.name] = local.copy()
        nombresOrden.append(objeto.name)
        padres[objeto.name] = padre
        filas = ', '.join('%.6f' % local[i][j] for i in range(4) for j in range(4))
        lineas.append("    { nombre = '%s', padre = %s, malla = %s, matriz = { %s } }," % (
            objeto.name, ("'%s'" % padre) if padre else 'nil', 'true' if objeto.type == 'MESH' else 'false', filas))
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    rutaPiezas = os.path.splitext(ruta)[0] + '_piezas.lua'
    with open(rutaPiezas, 'w', encoding='utf8') as archivo:
        archivo.write('-- Piezas del robot soldado (tools/blender/robot_soldado.py --glb), de la\n')
        archivo.write('-- raíz a las puntas: padre y matriz de reposo respecto a él (por filas,\n')
        archivo.write('-- ejes del juego, metros). `malla`: si tiene malla en el .glb.\n')
        archivo.write('return {\n' + '\n'.join(lineas) + '\n}\n')
    for objeto in orden:
        objeto.parent = None
    for objeto in orden:
        objeto.matrix_world = Matrix.Identity(4)
    nombres = {o.name for o in orden}
    for objeto in list(bpy.data.objects):
        if objeto.type != 'MESH' or objeto.name not in nombres:
            bpy.data.objects.remove(objeto)
    # Los materiales con texturas reales (pesado*) salen sin sus imágenes y
    # con el color de base de la textura (la goma casi blanca, 17-nov): al
    # juego van los lisos del robot del almacén con el mismo nombre.
    for objeto in bpy.data.objects:
        for ranura in objeto.material_slots:
            mat = ranura.material
            if mat and mat.name.startswith('pesado'):
                liso = bpy.data.materials.get('robot' + mat.name.split('.')[0][len('pesado'):])
                if liso:
                    ranura.material = liso
    for objeto in bpy.data.objects:
        uvCaja(objeto, conservarUv)
    opciones = dict(filepath=ruta, export_format='GLB', use_selection=False, export_apply=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
    except TypeError:
        bpy.ops.export_scene.gltf(**opciones)
    triangulos = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
    print('EXPORTADO', ruta, len(orden), 'piezas', triangulos, 'triángulos')
    exportarLods(ruta, nombresOrden, padres, locales)


# Copias de lejos (el dueño, 18-nov: con 10 robots por bando el juego iba a
# 14 FPS; «LOD + unir piezas»). Las mismas piezas con el mismo nombre, para
# que el juego las mueva igual (robots/nucleo.lua Robot:elegirNivel):
#   _lod1.glb (15-45 m): ~30 % de los triángulos y las piezas que ninguna
#     especialización mueve ni oculta unidas a su madre (menos llamadas de
#     dibujo); cuáles se mueven lo dice <modelo>_moviles.lua, que apunta el
#     juego (BATALLA_ROBOTS_MOVILES=1, batalla/robots/medir.lua);
#   _lod2.glb (más de 45 m): ~9 % de los triángulos, tres materiales (negro,
#     metal y brillo; los de la mira se quedan, el juego los cambia de
#     color) y sin las piezas sueltas de menos de 5 cm.
LOD_RATIOS = (0.3, 0.3)
LOD_DIMINUTA = 0.05
LOD_GRUPOS = {
    'robotNegro': ('robotNegro', 'robotNegroMate', 'robotArticulacion', 'robotGoma', 'robotHoja', 'robotGris', 'robotVisor'),
    'robotAcero': ('robotAcero', 'robotPlata', 'robotLaton', 'robotCobre', 'robotBlanco'),
    'robotNucleo': ('robotNucleo', 'robotOjo', 'robotIris'),
}


def _aplicarModificadores(objeto):
    grafo = bpy.context.evaluated_depsgraph_get()
    malla = bpy.data.meshes.new_from_object(objeto.evaluated_get(grafo))
    objeto.modifiers.clear()
    objeto.data = malla


def _diezmar(objeto, ratio):
    if len(objeto.data.polygons) < 48:
        return
    m = objeto.modifiers.new('lod', 'DECIMATE')
    m.ratio = ratio
    m.use_collapse_triangulate = True
    _aplicarModificadores(objeto)


def _agruparMateriales(objeto):
    destino = {}
    for grupo, nombres in LOD_GRUPOS.items():
        for n in nombres:
            destino[n] = bpy.data.materials.get(grupo)
    antes = [r.material for r in objeto.material_slots]
    nuevos = []
    for mat in antes:
        base = mat.name.split('.')[0] if mat else None
        nuevo = destino.get(base) or mat
        nuevos.append(nuevo)
    unicos = []
    for mat in nuevos:
        if mat not in unicos:
            unicos.append(mat)
    indices = [unicos.index(nuevos[p.material_index]) if p.material_index < len(nuevos) else 0 for p in objeto.data.polygons]
    objeto.data.materials.clear()
    for mat in unicos:
        objeto.data.materials.append(mat)
    for p, i in zip(objeto.data.polygons, indices):
        p.material_index = i


def _exportarGlb(ruta):
    opciones = dict(filepath=ruta, export_format='GLB', use_selection=False, export_apply=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
    except TypeError:
        bpy.ops.export_scene.gltf(**opciones)


def exportarLods(ruta, nombres, padres, locales):
    """Tras exportarJuego (piezas ya en el origen): _lod1.glb y _lod2.glb."""
    rutaMoviles = os.path.splitext(ruta)[0] + '_moviles.lua'
    if not os.path.exists(rutaMoviles):
        print('LOD sin', rutaMoviles, '(BATALLA_ROBOTS_MOVILES=1 en el juego): no se hacen copias de lejos')
        return
    import re
    with open(rutaMoviles, encoding='utf8') as archivo:
        moviles = set(re.findall(r"'([^']+)'", archivo.read()))
    moviles.add(nombres[0])
    objetos = bpy.data.objects
    for nombre in nombres:
        if objetos.get(nombre):
            _aplicarModificadores(objetos[nombre])
    # A qué pieza móvil va cada una y con qué matriz respecto a ella.
    ancla, relativa = {}, {}
    for nombre in nombres:
        padre = padres[nombre]
        if nombre in moviles or padre is None:
            ancla[nombre], relativa[nombre] = nombre, Matrix.Identity(4)
        else:
            ancla[nombre] = ancla[padre]
            relativa[nombre] = relativa[padre] @ locales[nombre]
    for nombre in nombres:
        o = objetos.get(nombre)
        destino = ancla[nombre]
        if o is None or destino == nombre:
            continue
        o.data.transform(relativa[nombre])
        madre = objetos.get(destino)
        if madre is None:
            # La pieza móvil no tiene malla: la primera que le llega la pone.
            o.name = destino
            continue
        with bpy.context.temp_override(active_object=madre, selected_editable_objects=[madre, o], selected_objects=[madre, o]):
            bpy.ops.object.join()
    base = os.path.splitext(ruta)[0]
    for nivel, ratio in enumerate(LOD_RATIOS, start=1):
        for o in list(objetos):
            if o.type != 'MESH':
                continue
            _diezmar(o, ratio)
            if nivel == 2:
                _agruparMateriales(o)
                if max(o.dimensions) < LOD_DIMINUTA and o.name != nombres[0]:
                    objetos.remove(o)
        destino = '%s_lod%d.glb' % (base, nivel)
        _exportarGlb(destino)
        mallas = [o for o in objetos if o.type == 'MESH']
        triangulos = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in mallas)
        primitivas = sum(len({p.material_index for p in o.data.polygons}) for o in mallas)
        print('LOD', destino, len(mallas), 'piezas', primitivas, 'primitivas', triangulos, 'triángulos')


def uvCaja(objeto, conservarUv=()):
    """UV por proyección de caja (3DreamEngine las necesita para las tangentes).
    Las caras con un material de `conservarUv` (los de atlas con textura,
    como el del camión de misiles) guardan sus UV."""
    conservar = {i for i, r in enumerate(objeto.material_slots) if r.material and r.material.name.split('.')[0] in conservarUv}
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    capa = bm.loops.layers.uv.verify()
    for cara in bm.faces:
        if cara.material_index in conservar:
            continue
        n = cara.normal
        ejes = (abs(n.x), abs(n.y), abs(n.z))
        d = ejes.index(max(ejes))
        for bucle in cara.loops:
            p = bucle.vert.co
            bucle[capa].uv = (p.y, p.z) if d == 0 else ((p.x, p.z) if d == 1 else (p.x, p.y))
    bm.to_mesh(objeto.data)
    bm.free()


def principal():
    """Sin ventana: `-- <salida.blend>` guarda la escena; `-- --glb` exporta
    al juego (assets/batalla/robots/soldado.glb y soldado_piezas.lua)."""
    args = argumentos()
    construir()
    if '--glb' in args:
        exportarJuego()
    elif args:
        bpy.ops.wm.save_as_mainfile(filepath=args[0])


if __name__ == '__main__' and bpy.app.background:
    principal()

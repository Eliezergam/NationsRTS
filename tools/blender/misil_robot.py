# Misil del robot lanzamisiles de Nations RTS (el dueño, 18-nov: «diseña el
# proyectil que lanzará el cañón»). Diseño propio con el estilo de la casa.
#
# Medidas: 0,50 m de largo y 8 cm de diámetro. Cabe por el tubo del cañón
# (hueco libre de unos 9,6 cm) con las aletas plegadas.
# Ejes: +x hacia delante, origen en el centro del misil.
#
# De delante a atrás:
#   - cabeza buscadora: cúpula de cristal con el sensor rojo (brilla como el
#     láser de la mira) y aro de cobre;
#   - ojiva negra con franja roja (carga);
#   - 4 canards que salen del cuerpo;
#   - cuerpo negro con franja blanca, banda plateada y remaches;
#   - 4 aletas de cola curvas, plegadas sobre el cuerpo (como en los cohetes
#     que salen de un tubo);
#   - tobera con su llama.
#
# Piezas que se mueven (hijas de `misil`):
#   aletaMisil{k}   eje x local en su bisagra; 0 plegada, -90° abierta
#                   (propiedad `abierta` en radianes)
#   canardMisil{k}  sale en línea recta hacia fuera `sale` m (0 dentro)
#   llamaMisil      solo en vuelo; escala x = largo de la llama
#
# Uso: construirMisil(S) con S el espacio de nombres de robot_soldado.py.

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

LARGO = 0.5
R = 0.04
COLA = -0.2  # x donde acaba el cuerpo (empieza la tobera)
OJIVA = 0.13  # x donde empieza la ojiva
PUNTA = 0.235  # x del centro de la cúpula
CUPULA_R = 0.021
ALETAS = 4
ALETA_ARCO = 1.25  # rad que abrazan plegadas
ALETA_X = (-0.198, -0.12)
CANARD_X = (0.06, 0.105)
CANARD_SALE = 0.024


def torno(S, nombre, perfil, material, lados=96):
    """Superficie de revolución alrededor de x con `perfil` [(x, r)]; si el
    primer o el último radio es 0, se cierra en punta."""
    bm = bmesh.new()
    anillos = []
    for x, r in perfil:
        if r <= 1e-6:
            anillos.append([bm.verts.new((x, 0, 0))])
        else:
            anillos.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / lados), r * math.sin(2 * math.pi * k / lados))) for k in range(lados)])
    for a, b in zip(anillos, anillos[1:]):
        if len(a) == 1:
            for k in range(lados):
                bm.faces.new((a[0], b[(k + 1) % lados], b[k]))
        elif len(b) == 1:
            for k in range(lados):
                bm.faces.new((a[k], a[(k + 1) % lados], b[0]))
        else:
            for k in range(lados):
                j = (k + 1) % lados
                bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = S['objetoDe'](nombre, bm, material)
    S['suave'](o)
    return o


def aletaCurva(S, nombre, a0, material):
    """Aleta de cola plegada: chapa curva sobre el cuerpo desde el ángulo a0
    (la bisagra) en sentido positivo; la cuerda se acorta hacia la punta."""
    bm = bmesh.new()
    pasos = 14
    rIn, rOut = R + 0.0008, R + 0.0042
    x0, x1 = ALETA_X
    filas = []
    for i in range(pasos + 1):
        t = i / pasos
        a = a0 + ALETA_ARCO * t
        xa = x0
        xb = x1 - (x1 - x0) * 0.45 * t  # borde de ataque en flecha
        fila = []
        for r in (rIn, rOut):
            for x in (xa, xb):
                fila.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
        filas.append(fila)
    # fila: [in-xa, in-xb, out-xa, out-xb]
    for f0, f1 in zip(filas, filas[1:]):
        for p, q in ((0, 1), (3, 2), (1, 3), (2, 0)):
            bm.faces.new((f0[p], f0[q], f1[q], f1[p]))
    for fila, signo in ((filas[0], 1), (filas[-1], -1)):
        caras = (fila[0], fila[1], fila[3], fila[2])
        bm.faces.new(caras if signo > 0 else tuple(reversed(caras)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.0008, segments=1, affect='EDGES', clamp_overlap=True)
    o = S['objetoDe'](nombre, bm, material)
    S['suave'](o)
    return o


def construirMisil(S):
    m = S['materiales']()
    if 'misilSensor' not in m:
        m['misilSensor'] = S['materialLiso']('misilSensor', (1.0, 0.06, 0.03), 0.2, 0.0, 4.0)
        m['misilCupula'] = S['materialLiso']('misilCupula', (0.12, 0.02, 0.02), 0.04, 0.0, 0.0)
        m['misilLlama'] = S['materialLiso']('misilLlama', (1.0, 0.45, 0.1), 0.5, 0.0, 30.0)
    caja, cilindro, aro, segmento, perno, filaRemaches, pieza = (S[k] for k in ('caja', 'cilindro', 'aro', 'segmento', 'perno', 'filaRemaches', 'pieza'))
    q = []
    # Cuerpo y ojiva en un solo perfil (negro), sin escalones.
    perfil = [(COLA, 0.0), (COLA, R - 0.006), (COLA + 0.004, R), (OJIVA, R)]
    for i in range(1, 9):
        t = i / 8
        perfil.append((OJIVA + (PUNTA - OJIVA) * t, CUPULA_R + 0.002 + (R - CUPULA_R - 0.002) * math.cos(t * math.pi / 2)))
    perfil.append((PUNTA, 0.0))
    q.append(torno(S, 'cuerpoMisil', perfil, m['negro']))
    # Cabeza buscadora: cúpula de cristal, aro de cobre, sensor rojo dentro.
    bpy.ops.mesh.primitive_uv_sphere_add(radius=CUPULA_R, location=(PUNTA, 0, 0), segments=64, ring_count=32)
    cupula = bpy.context.active_object
    cupula.data.materials.append(m['misilCupula'])
    bpy.ops.object.shade_smooth()
    q.append(cupula)
    q.append(aro('aroCupula', (PUNTA - 0.002, 0, 0), CUPULA_R - 0.001, CUPULA_R + 0.0045, 0.006, m['cobre'], lados=96, bisel=0.001))
    q.append(cilindro('sensorMisil', (PUNTA + 0.004, 0, 0), 0.009, 0.004, m['misilSensor'], eje='x', lados=48))
    q.append(aro('aroSensor', (PUNTA + 0.006, 0, 0), 0.009, 0.013, 0.002, m['acero'], lados=48))
    # Franjas: roja en la ojiva (carga), blanca y plateada en el cuerpo.
    q.append(torno(S, 'franjaCarga', [(OJIVA + 0.012, R * 0.985 + 0.0008), (OJIVA + 0.03, R * 0.93 + 0.0008)], m['rojo']))
    q.append(cilindro('franjaMisil', (0.025, 0, 0), R + 0.0006, 0.022, m['blanco'], eje='x', lados=96))
    q.append(cilindro('bandaMisil', (-0.06, 0, 0), R + 0.0012, 0.012, m['plata'], eje='x', lados=96, bisel=0.001))
    q.append(cilindro('juntaMisil', (-0.1, 0, 0), R + 0.0004, 0.003, m['negroMate'], eje='x', lados=96))
    # Ranuras de los canards y remaches.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        n = Vector((0, math.cos(a), math.sin(a)))
        ranura = caja('ranuraCanard', ((CANARD_X[0] + CANARD_X[1]) / 2, 0, R - 0.0006), (0.05, 0.004, 0.004), m['negroMate'], 0.0005)
        ranura.data.transform(Matrix.Rotation(a - math.pi / 2, 4, 'X'))
        q.append(ranura)
        a2 = k * math.pi / 2 + math.pi / 8
        q += filaRemaches((-0.09, math.cos(a2) * R, math.sin(a2) * R), (-0.02, math.cos(a2) * R, math.sin(a2) * R), 4, (0, math.cos(a2), math.sin(a2)), m, 0.0028)
    # Anillo de cola (bisagras de las aletas) y tobera.
    q.append(aro('aroCola', (COLA + 0.012, 0, 0), R - 0.004, R + 0.0035, 0.016, m['articulacion'], lados=96, bisel=0.0015))
    q.append(torno(S, 'tobera', [(COLA, R - 0.008), (COLA - 0.02, R - 0.012), (COLA - 0.04, R - 0.006), (COLA - 0.042, R - 0.004)], m['articulacion']))
    q.append(torno(S, 'interiorTobera', [(COLA - 0.04, R - 0.009), (COLA - 0.02, R - 0.016), (COLA - 0.002, 0.008), (COLA - 0.002, 0.0)], m['acero']))
    q.append(aro('bocaTobera', (COLA - 0.041, 0, 0), R - 0.009, R - 0.003, 0.003, m['cobre'], lados=96))
    misil = pieza('misil', q, (0, 0, 0))
    # Canards (salen hacia fuera).
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        n = Vector((0, math.cos(a), math.sin(a)))
        x0, x1 = CANARD_X
        bm = bmesh.new()
        pts = [(x0, 0.0), (x1, 0.0), (x1 - 0.006, 0.022), (x0 + 0.018, 0.022)]
        vs = []
        for dz in (-0.0015, 0.0015):
            for x, h in pts:
                vs.append(bm.verts.new((x, dz, R - 0.004 + h)))
        bm.faces.new(vs[0:4])
        bm.faces.new(list(reversed(vs[4:8])))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((vs[i], vs[4 + i], vs[4 + j], vs[j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        c = S['objetoDe']('canard', bm, m['acero'])
        c.data.transform(Matrix.Rotation(a - math.pi / 2, 4, 'X'))
        o = pieza('canardMisil%d' % k, [c], (0, 0, 0), misil)
        o['sale'] = CANARD_SALE
        o['dir'] = list(n)
    # Aletas de cola (plegadas).
    for k in range(ALETAS):
        a0 = k * 2 * math.pi / ALETAS
        ale = aletaCurva(S, 'aleta', a0, m['negro'] if k % 2 else m['plata'])
        bis = Vector((ALETA_X[0], R * math.cos(a0), R * math.sin(a0)))
        o = pieza('aletaMisil%d' % k, [ale], tuple(bis), misil)
        o.rotation_mode = 'XYZ'
        o['abierta'] = -math.pi / 2
    # Llama: cono naranja que sale de la tobera (escala x = largo).
    llama = torno(S, 'llamaMisil', [(0.0, R - 0.012), (-0.06, R - 0.016), (-0.2, 0.012), (-0.32, 0.0)], m['misilLlama'], lados=48)
    o = pieza('llamaMisil', [llama], (COLA - 0.04, 0, 0), misil)
    o.hide_render = True
    return misil


def poseMisil(misil, abrir, canards, llama):
    """abrir 0..1 las aletas, canards 0..1 fuera, llama 0 (apagada)..1."""
    for o in misil.children:
        n = o.name
        if n.startswith('aletaMisil'):
            o.rotation_euler.x = o['abierta'] * abrir
        elif n.startswith('canardMisil'):
            if 'base' not in o.keys():
                o['base'] = list(o.location)
            o.location = Vector(o['base']) + Vector(o['dir']) * (o['sale'] * (canards - 1))
        elif n.startswith('llamaMisil'):
            o.hide_render = llama <= 0.01
            o.scale = (max(0.01, llama), 1, 1)


# Proyectil (el dueño, 18-nov: «que lance solo el proyectil, como la bala de
# un AK-47 pero en grande», con una foto de un obús de 155 mm): ojiva verde
# oliva, espoleta de latón en la punta, banda de cobre cerca de la cola y la
# cola que se estrecha. Sin aletas ni motor. 4 cm de grueso y 15 cm de largo;
# +x hacia delante, origen en el centro.
OBUS_R = 0.02
OBUS_LARGO = 0.15


def construirObus(S):
    m = S['materiales']()
    if 'obusOliva' not in m:
        m['obusOliva'] = S['materialLiso']('obusOliva', (0.16, 0.19, 0.09), 0.45, 0.1)
    cilindro, aro = S['cilindro'], S['aro']
    R = OBUS_R
    cola, cuerpo, ojiva, punta = -0.075, -0.058, 0.0, 0.075
    perfil = [(cola, 0.0), (cola, R * 0.66), (cola + 0.002, R * 0.7), (cuerpo, R * 0.98), (cuerpo + 0.003, R)]
    perfil.append((ojiva, R))
    for i in range(1, 11):
        t = i / 10
        # Ojiva tangente hasta la espoleta.
        perfil.append((ojiva + 0.052 * t, 0.0085 + (R - 0.0085) * math.cos(t * math.pi / 2)))
    q = [torno(S, 'cuerpoObus', perfil, m['obusOliva'])]
    # Espoleta de latón: cono con su escalón y la punta.
    q.append(torno(S, 'espoleta', [(0.0515, 0.0), (0.0515, 0.0088), (0.054, 0.0088), (0.068, 0.0042), (punta - 0.002, 0.0018), (punta, 0.0)], m['laton']))
    q.append(aro('aroEspoleta', (0.0525, 0, 0), 0.0075, 0.0094, 0.002, m['negroMate'], lados=64))
    # Banda de cobre (la que agarra el estriado) y su ranura.
    q.append(cilindro('bandaObus', (-0.044, 0, 0), R + 0.0007, 0.011, m['cobre'], eje='x', lados=96, bisel=0.0006))
    q.append(cilindro('ranuraObus', (-0.035, 0, 0), R + 0.0002, 0.0015, m['negroMate'], eje='x', lados=96))
    return S['pieza']('misil', q, (0, 0, 0))

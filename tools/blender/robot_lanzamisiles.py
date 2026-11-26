# Robot soldado lanzamisiles de Nations RTS (el dueño, 18-nov). Maqueta
# aprobada: tools/blender/robot_cabeza_canon_maqueta.py.
#
# Es el soldado de siempre (robot_soldado.py: piernas con rueda, torso, la
# misma cabeza con sus ojos, oídos y mentón) con tres cambios:
#   - una garra de 3 dedos en cada brazo (la del soldado);
#   - a la espalda, un cargador de misiles con una tapa arriba que se abre;
#   - la cabeza se convierte en un cañón lanzamisiles de 1 m, pieza por
#     pieza: la cabeza de verdad está partida en 24 trozos (8 alrededor x 3
#     de alto; el corte se cierra) y cada trozo tiene su sitio en el cañón.
#     La cabeza es casi un cilindro de pie y el cañón un cilindro tumbado
#     del mismo grueso: cada trozo gira 90° (la coronilla a la boca, la
#     cara abajo) y queda de blindaje del tramo de delante. El resto sale
#     del cargador: el ánima (tubo de acero con la boca), el soporte sobre
#     el cuello, 8 tramos de cañón y la tobera de atrás, y la caja de la
#     mira. El ojo izquierdo (el de todos los robots) sube a la mira; el
#     derecho se mete en el cañón y se esconde. El cuello no se mueve.
#
# Cada pieza que cambia guarda sus dos sitios (propiedades `poseCabeza` y
# `poseCanon`: matriz 4x4 en el espacio de `cabeza`, por filas) y si nace
# del cargador (`nace`, con `poseCabeza` en la tapa del cargador). El juego
# (Lua) hace el cambio procedural igual que `pose()` aquí: cada pieza con su
# retraso en cascada, un arco hacia fuera, media vuelta por el camino, y las
# que nacen crecen mientras vuelan.
#
#     blender -b --factory-startup --python tools/blender/robot_lanzamisiles.py -- <carpeta> [--video]
#
# Deja en <carpeta> las fotos de las dos formas (cabeza y cañón, de tres
# cuartos y de perfil) y, con --video, lanzamisiles.mp4 con el cambio.

import math
import os
import subprocess
import sys
import tempfile

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

_DIR = os.path.dirname(os.path.abspath(__file__))
_S = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_S['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _S)
caja, cilindro, segmento, pieza, perno, filaRemaches, aro = (_S[k] for k in ('caja', 'cilindro', 'segmento', 'pieza', 'perno', 'filaRemaches', 'aro'))
materiales, brazoSuperior, construir = _S['materiales'], _S['brazoSuperior'], _S['construir']
_M = {'__name__': 'misil', '__file__': os.path.join(_DIR, 'misil_robot.py')}
with open(_M['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _M)

# Medidas (m) ------------------------------------------------------------------
CX = _S['CADERA'][0]
HC = _S['CUELLO_Z'] + _S['CUELLO'] + 0.08  # centro del casco (1,74)
CENTRO_CABEZA = Vector((CX, 0.0, HC))
SECTORES = 8
BANDAS_Z = (1.68, 1.76)  # cortes de alto: mandíbula | medio | arriba
CUELLO_ARRIBA = 1.655  # lo de debajo, cerca del eje, es el cuello (no se mueve)
EJE_Z = 1.8  # altura del eje del cañón (por encima del cuello)
# El cañón apunta adelante (el dueño, 18-nov: «¿por qué tiene el cañón para
# atrás?»): la cabeza hecha recámara queda sobre el cuello y los tramos salen
# hacia delante hasta la boca; detrás de la recámara, solo la tobera.
FRENTE = Vector((0.0, 0.0, EJE_Z))  # adonde va el centro de la cabeza
TRAMOS_X = FRENTE.x + 0.144  # donde acaba la recámara y empiezan los tramos
# Arma (el dueño, 18-nov, con la foto del cañón de cara de Lockdown como
# idea: «que se vea como un arma, sigues creando un tubo»; luego «más ancha
# hacia abajo»): la boca del freno, delante del cañón a la vista.
BOCA_X = 1.0
ANILLOS_X = (1.016, 1.036, 1.056)  # aros que giran en la punta
ANILLO_R = 0.05
ANILLO_GIRO = 30.0  # rad/s con el cañón formado (en el juego, por su velocidad)
PUNTA_X = ANILLOS_X[-1] + 0.01  # por donde sale el proyectil
COLA_X = FRENTE.x - 0.2
# Hueco del cañón (el dueño, 18-nov: proyectil «más pequeñito pero fuerte»
# y «el hueco más pequeño»): el proyectil (misil_robot.py construirObus) es
# de 4 cm; el tubo, de 4,8 cm por dentro. Los engranajes siguen dentro, en
# pequeño: se hacen a la medida de antes (ANIMA_VIEJO) y se encogen a
# INTERIOR.
ANIMA_R = 0.032
ANIMA_VIEJO = 0.068
INTERIOR = (ANIMA_R - 0.002) / (ANIMA_VIEJO - 0.004)
TRAMO = 0.088  # largo de cada tramo de detrás
TRAMOS = 8
TRAMO_R = 0.112  # (radio del tubo redondo de antes; ya no se usa en los tramos)
# Carcasa del cañón (el dueño, 18-nov, con una foto de referencia: «se vería
# mejor así y no como el que tenemos, que se ve un tubo rollizo»): larga,
# delgada y angulosa, de lados planos con chaflanes, ventanas en los costados
# por donde se ven los engranajes, un cañón fino encima, quilla debajo y
# pistones a los lados. Diseño propio (de la foto, solo la idea).
CANON_W = 0.052  # medio ancho
CANON_H = 0.06  # medio alto
CANON_C = 0.018  # chaflán de las esquinas
CANON_T = 0.006  # grosor de la chapa
CARGADOR = Vector((-0.37, 0.0, 1.4))
CARGADOR_MEDIDA = (0.22, 0.36, 0.44)
TAPA_CARGADOR = Vector((CARGADOR.x, 0.0, CARGADOR.z + CARGADOR_MEDIDA[2] / 2))
MIRA = Vector((0.2, 0.0, EJE_Z + 0.2))  # centro del ojo en la mira (el alza del arma)


# Garras en los dos brazos (el dueño, 18-nov: «agrégale las garras del otro
# robot a las dos manos»): la garra de 3 dedos del soldado
# (robot_soldado_mano.py) en cada antebrazo. Nombres con el lado al final:
# codoIzq/codoDer, manoIzq/manoDer, dedoA1Izq…dedoC3Der (mismos ejes y
# rangos que la garra del soldado).

def etapaGarra(lado):
    m = materiales()
    torso = bpy.data.objects['torso']
    s = 'Izq' if lado > 0 else 'Der'
    codo = _S['CODO_IZQ'] if lado > 0 else _S['CODO_DER']
    brazo, cod = brazoSuperior(lado, codo, m, torso)
    x0, y, z = cod
    mun = (_S['MUNECA_IZQ'][0], y, _S['MUNECA_IZQ'][1])
    q = [
        segmento('antebrazo', cod, mun, 0.085, 0.09, m['negro'], 0.03, -0.01),
        segmento('antebrazoTapa', (x0 + 0.03, y + lado * 0.046, z), (mun[0] - 0.04, y + lado * 0.046, mun[2]), 0.006, 0.05, m['plata'], 0.002),
        caja('antebrazoFranja', ((x0 + mun[0]) / 2, y + lado * 0.0495, z + 0.033), (0.11, 0.003, 0.008), m['blanco'], 0.001),
        cilindro('muneca', mun, 0.035, 0.03, m['articulacion'], eje='x', lados=48, bisel=0.004),
    ]
    q += filaRemaches((x0 + 0.04, y - lado * 0.044, z + 0.02), (mun[0] - 0.05, y - lado * 0.044, mun[2] + 0.02), 4, (0, -lado, 0), m, 0.005)
    antebrazo = pieza('codo' + s, q, cod, brazo)
    mano = _S['crearGarra']()
    # La garra se hizo con los dedos hacia +z: se tumba hacia +x.
    mano.parent = None
    mano.matrix_world = Matrix.Translation((mun[0] + 0.015, y, mun[2])) @ Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Scale(_S['ESCALA_GARRA'], 4)
    bpy.context.view_layer.update()
    mundo = mano.matrix_world.copy()
    mano.parent = antebrazo
    mano.matrix_world = mundo
    for o in [mano] + list(mano.children_recursive):
        o.name = o.name + s
    return brazo


# Cargador de misiles ----------------------------------------------------------

def etapaCargador():
    """A la espalda, detrás de la mochila de baterías: caja negra biselada
    con placas plateadas a los lados, franja blanca, rejillas, correas al
    torso y remaches; arriba, la tapa (pieza aparte, bisagra detrás, gira en
    y) por donde salen las piezas del cañón."""
    m = materiales()
    torso = bpy.data.objects['torso']
    c = CARGADOR
    f, w, h = CARGADOR_MEDIDA
    q = [
        caja('cargador', tuple(c), (f, w, h), m['negro'], 0.04),
        caja('franjaCargador', (c.x - f / 2 - 0.002, 0, c.z + h * 0.3), (0.006, w * 0.6, 0.03), m['blanco'], 0.002),
        caja('marcoTapa', (c.x, 0, c.z + h / 2 + 0.004), (f * 0.86, w * 0.86, 0.012), m['articulacion'], 0.004),
    ]
    for s in (-1, 1):
        q.append(caja('placaCargador', (c.x, s * (w / 2 + 0.004), c.z), (f * 0.7, 0.01, h * 0.62), m['plata'], 0.004))
        for dx in (-1, 1):
            for dz in (-1, 1):
                q += perno('pernoCargador', (c.x + dx * f * 0.28, s * (w / 2 + 0.01), c.z + dz * h * 0.25), (0, s, 0), m, 0.006, material='acero')
        # Correas al torso (por encima y por debajo de la mochila de baterías).
        for zc in (c.z + h * 0.36, c.z - h * 0.36):
            q.append(caja('correa', (c.x + f / 2 + 0.03, s * w * 0.32, zc), (0.08, 0.04, 0.018), m['articulacion'], 0.004))
    for k in range(5):
        q.append(caja('rejillaCargador', (c.x - f / 2 - 0.004, 0, c.z - h * 0.32 + k * 0.03), (0.006, w * 0.5, 0.012), m['negroMate'], 0.002))
    q += filaRemaches((c.x - f / 2 - 0.002, -w * 0.38, c.z + h / 2 - 0.02), (c.x - f / 2 - 0.002, w * 0.38, c.z + h / 2 - 0.02), 8, (-1, 0, 0), m, 0.005)
    cargador = pieza('cargador', q, tuple(c), torso)
    # La tapa: bisagra en su canto de atrás.
    t = TAPA_CARGADOR
    q = [
        caja('tapaCargador', (t.x, 0, t.z + 0.014), (f * 0.82, w * 0.82, 0.016), m['negro'], 0.006),
        caja('placaTapa', (t.x, 0, t.z + 0.024), (f * 0.5, w * 0.5, 0.004), m['plata'], 0.0015),
        cilindro('bisagraTapa', (t.x - f * 0.41, 0, t.z + 0.012), 0.009, w * 0.7, m['articulacion'], eje='y', lados=32, bisel=0.002),
    ]
    for sy in (-1, 1):
        for sx in (-1, 1):
            q += perno('pernoTapa', (t.x + sx * f * 0.2, sy * w * 0.2, t.z + 0.026), (0, 0, 1), m, 0.0045, material='acero')
    pieza('tapaCargador', q, (t.x - f * 0.41, 0, t.z + 0.012), cargador)
    return cargador


# Partir la cabeza -------------------------------------------------------------

def _seleccionarSolo(objeto):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    objeto.select_set(True)
    bpy.context.view_layer.objects.active = objeto


def _caja(o):
    ps = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in ps), min(p.y for p in ps), min(p.z for p in ps)))
    hi = Vector((max(p.x for p in ps), max(p.y for p in ps), max(p.z for p in ps)))
    return lo, hi


def _celda(p):
    """Sector (0..7, el 0 de frente) y banda (0 mandíbula, 1, 2 arriba)."""
    a = math.atan2(p.y, p.x - CX)
    sector = int(((a + math.pi / SECTORES) % (2 * math.pi)) // (2 * math.pi / SECTORES))
    banda = 0 if p.z < BANDAS_Z[0] else (1 if p.z < BANDAS_Z[1] else 2)
    return sector, banda


def _recortar(bm, co, no):
    """Deja lo que queda del lado de -no del plano y cierra el corte."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    borde = [e for e in bm.edges if e.is_boundary]
    if borde:
        bmesh.ops.holes_fill(bm, edges=borde, sides=0)


def _trozo(objeto, sector, banda):
    """Copia de `objeto` recortada a la celda (cuña del sector x banda), o None."""
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    bm.transform(objeto.matrix_world)
    ancho = 2 * math.pi / SECTORES
    a0 = sector * ancho - ancho / 2
    a1 = a0 + ancho
    eje = Vector((CX, 0, 0))
    # Cuña: lado de a0 hacia dentro y lado de a1 hacia dentro.
    _recortar(bm, eje, Vector((math.sin(a0), -math.cos(a0), 0)))
    _recortar(bm, eje, Vector((-math.sin(a1), math.cos(a1), 0)))
    if banda == 0:
        _recortar(bm, Vector((0, 0, BANDAS_Z[0])), Vector((0, 0, 1)))
    elif banda == 1:
        _recortar(bm, Vector((0, 0, BANDAS_Z[0])), Vector((0, 0, -1)))
        _recortar(bm, Vector((0, 0, BANDAS_Z[1])), Vector((0, 0, 1)))
    else:
        _recortar(bm, Vector((0, 0, BANDAS_Z[1])), Vector((0, 0, -1)))
    if len(bm.faces) == 0:
        bm.free()
        return None
    malla = bpy.data.meshes.new(objeto.name + '_t')
    bm.to_mesh(malla)
    bm.free()
    for mat in objeto.data.materials:
        malla.materials.append(mat)
    o = bpy.data.objects.new(objeto.name + '_t', malla)
    bpy.context.scene.collection.objects.link(o)
    return o


def partirCabeza():
    """La cabeza del soldado en 24 trozos (`cabezaPieza{sector}{banda}`,
    hijos de `cabeza`) y el cuello aparte (`cuelloFijo`). Los oídos se
    cuelgan de su trozo; las persianas, de su ojo."""
    O = bpy.data.objects
    cab = O['cabeza']
    hijos = list(cab.children)
    torso = cab.parent
    for h in hijos:
        mundo = h.matrix_world.copy()
        h.parent = None
        h.matrix_world = mundo
    _seleccionarSolo(cab)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    islas = list(bpy.context.selected_objects)
    # Cada isla, en coordenadas del mundo (si no, al unirlas se descoloca).
    for isla in islas:
        isla.data.transform(isla.matrix_world)
        isla.parent = None
        isla.matrix_world = Matrix.Identity(4)
    cuello, celdas, antenas = [], {}, []
    for isla in islas:
        lo, hi = _caja(isla)
        centro = (lo + hi) / 2
        radio = max(abs(lo.x - CX), abs(hi.x - CX), abs(lo.y), abs(hi.y))
        if os.environ.get('LANZAMISILES_DEPURAR'):
            print('ISLA %-28s centro=(%.3f %.3f %.3f) radio=%.3f alto=%.3f' % (isla.name, centro.x, centro.y, centro.z, radio, hi.z - lo.z))
        if centro.z < CUELLO_ARRIBA and radio < 0.07:
            cuello.append(isla)
            continue
        if hi.x - lo.x < 0.012 and hi.y - lo.y < 0.012 and hi.z - lo.z > 0.08:
            antenas.append(isla)
            continue
        grande = (hi - lo).length > 0.07
        if grande:
            for sector in range(SECTORES):
                for banda in range(3):
                    t = _trozo(isla, sector, banda)
                    if t:
                        celdas.setdefault((sector, banda), []).append(t)
            bpy.data.objects.remove(isla, do_unlink=True)
        else:
            celdas.setdefault(_celda(centro), []).append(isla)
    pivote = CENTRO_CABEZA.copy()
    pivote.z = _S['CUELLO_Z']
    nueva = pieza('cabeza', cuello, tuple(pivote), torso)
    nueva.name = 'cabeza'
    trozos = {}
    for (sector, banda), lista in sorted(celdas.items()):
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for o in lista:
            a, b = _caja(o)
            lo = Vector(map(min, lo, a))
            hi = Vector(map(max, hi, b))
        centro = (lo + hi) / 2
        o = pieza('cabezaPieza%d%d' % (sector, banda), lista, tuple(centro), nueva)
        # Sombreado: suave con aristas vivas por ángulo (el corte las borra).
        _S['suave'](o)
        o['sector'], o['banda'] = sector, banda
        trozos[(sector, banda)] = o
    # Antenas: pieza aparte (origen en su base) que se recoge en el casco.
    for isla in antenas:
        lo, hi = _caja(isla)
        lado = 'Izq' if lo.y > 0 else 'Der'
        o = pieza('antena' + lado, [isla], ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z), nueva)
        o['retraer'] = 1
        o['celda'] = list(_celda((lo + hi) / 2))
    # Oídos con su trozo; ojos y persianas, aparte (los ojos se mueven solos).
    for h in hijos:
        n = h.name
        if n.startswith('oido'):
            lo, hi = _caja(h)
            destino = trozos.get(_celda((lo + hi) / 2)) or nueva
        elif n.startswith('persiana'):
            destino = O['globo' + ('Izq' if 'Izq' in n else 'Der')]
        else:
            destino = nueva
        mundo = h.matrix_world.copy()
        h.parent = destino
        h.matrix_world = mundo
    return nueva, trozos


# Lo que sale del cargador -----------------------------------------------------

def losa(nombre, puntos, ancho, mat, bisel=0.006, y=0.0):
    """Pieza de lados planos: el polígono (x, z) del perfil, extruido `ancho`
    en y (centrada en `y`), con los cantos biselados."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y - ancho / 2, z)) for x, z in puntos]
    b = [bm.verts.new((x, y + ancho / 2, z)) for x, z in puntos]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    n = len(puntos)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[j], a[i], b[i], b[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bisel, segments=3, affect='EDGES', profile=0.5)
    return _S['objetoDe'](nombre, bm, mat)


def recortarX(puntos, x0, x1):
    """El polígono (x, z) recortado a x0 <= x <= x1."""
    def corte(pts, dentro, cruce):
        salida = []
        for i in range(len(pts)):
            p, q = pts[i - 1], pts[i]
            if dentro(q):
                if not dentro(p):
                    salida.append(cruce(p, q))
                salida.append(q)
            elif dentro(p):
                salida.append(cruce(p, q))
        return salida

    def cruceEn(xc):
        return lambda p, q: (xc, p[1] + (q[1] - p[1]) * (xc - p[0]) / (q[0] - p[0]))
    pts = corte(list(puntos), lambda p: p[0] >= x0, cruceEn(x0))
    return corte(pts, lambda p: p[0] <= x1, cruceEn(x1))


# Perfiles del arma (x, z sobre el eje del cañón), de la maqueta aprobada.
PERFIL_ALTO = [(0.12, 0.035), (0.6, 0.035), (0.64, 0.06), (0.64, 0.095), (0.5, 0.115), (0.25, 0.13), (0.12, 0.135)]
ANCHO_ALTO = 0.075
PERFIL_LOSA = [(0.16, 0.125), (0.5, 0.11), (0.5, 0.131), (0.2, 0.149), (0.16, 0.149)]
PERFIL_BAJO = [(0.12, 0.035), (0.62, 0.035), (0.645, 0.0), (0.625, -0.06), (0.5, -0.09), (0.2, -0.105), (0.12, -0.105)]
ANCHO_BAJO = 0.13
PERFIL_QUILLA = [(0.18, -0.1), (0.46, -0.085), (0.42, -0.135), (0.22, -0.14)]
PERFIL_FRENO = [(0.88, -0.05), (0.985, -0.045), (BOCA_X, 0.0), (0.985, 0.045), (0.88, 0.05)]
RIEL_Z = 0.156


def _subir(puntos):
    return [(x, EJE_Z + z) for x, z in puntos]


def etapaCanon(cabeza):
    """El arma: cuerpo de arriba (corredera) y de abajo (más ancho, envuelve
    el cañón), riel con dientes, cañón a la vista con bloque de gas, freno
    de boca con puertos, varilla guía, soporte sobre el cuello, tobera y la
    mira en el sitio del alza. Todo sale del cargador; los trozos de la
    cabeza hacen la recámara de detrás. Colgado de `cabeza`."""
    m = materiales()
    z = EJE_Z
    piezas = []
    # Ánima: el tubo de dentro de todo, con la corona de la boca y lo que va
    # sobre el cañón a la vista (bloque de gas, collar).
    largo = BOCA_X - 0.03 - COLA_X
    medio = (BOCA_X - 0.03 + COLA_X) / 2
    q = [
        aro('anima', (medio, 0, z), ANIMA_R - 0.004, ANIMA_R, largo, m['articulacion'], lados=96, bisel=0.001),
        aro('bloqueGas', (0.72, 0, z), ANIMA_R - 0.001, ANIMA_R + 0.011, 0.035, m['negro'], lados=96, bisel=0.003),
        aro('collarCanon', (0.81, 0, z), ANIMA_R - 0.001, ANIMA_R + 0.008, 0.02, m['acero'], lados=96, bisel=0.002),
        aro('collarCanon2', (0.66, 0, z), ANIMA_R - 0.001, ANIMA_R + 0.006, 0.012, m['acero'], lados=96, bisel=0.002),
        cilindro('tuboGas', (0.675, 0, z + ANIMA_R + 0.016), 0.008, 0.08, m['acero'], eje='x', lados=32, bisel=0.002),
        caja('bloqueGasArriba', (0.72, 0, z + ANIMA_R + 0.012), (0.035, 0.026, 0.03), m['negro'], 0.004),
    ]
    q += perno('pernoGas', (0.72, 0, z + ANIMA_R + 0.028), (0, 0, 1), m, 0.004, material='acero')
    anima = pieza('anima', q, (FRENTE.x, 0, z), cabeza)
    piezas.append(anima)
    interiorCanon(anima, m)
    # Soporte sobre el cuello: horquilla con dos placas y el eje.
    zc = CUELLO_ARRIBA + 0.02
    q = [
        cilindro('baseSoporte', (CX, 0, zc), 0.058, 0.03, m['articulacion'], lados=64, bisel=0.006),
        cilindro('ejeSoporte', (CX, 0, z - 0.09), 0.024, 0.16, m['acero'], eje='y', lados=48, bisel=0.003),
    ]
    for s in (-1, 1):
        q.append(segmento('placaSoporte', (CX, s * 0.07, zc + 0.01), (CX, s * 0.07, z - 0.07), 0.07, 0.014, m['negro'], 0.006))
        q += perno('pernoSoporte', (CX, s * 0.078, z - 0.09), (0, s, 0), m, 0.006, material='acero')
    piezas.append(pieza('soporteCanon', q, (CX, 0, zc), cabeza))
    # Cuerpo de abajo, en dos mitades (salen una tras otra): ranuras de
    # ventilación inclinadas, franja blanca, pernos y la junta de arriba.
    yb = ANCHO_BAJO / 2
    for k, (x0, x1) in enumerate(((0.12, 0.38), (0.38, 0.7))):
        q = [losa('cuerpoBajo', _subir(recortarX(PERFIL_BAJO, x0, x1)), ANCHO_BAJO, m['negro'], 0.008)]
        q.append(caja('juntaBajo', ((x0 + x1) / 2, 0, z + 0.035), (min(x1, 0.62) - x0 - 0.004, ANCHO_BAJO + 0.002, 0.005), m['negroMate'], 0.001))
        for sy in (-1, 1):
            for j in range(6):
                xv = x0 + 0.04 + j * 0.035
                if xv < min(x1, 0.58) - 0.02:
                    v = caja('ventBajo', (0, 0, 0), (0.012, 0.005, 0.05), m['negroMate'], 0.0015)
                    v.data.transform(Matrix.Translation((xv, sy * (yb - 0.0015), z - 0.035)) @ Matrix.Rotation(0.35, 4, 'Y'))
                    q.append(v)
            if k == 0:
                q.append(caja('franjaBajo', (0.25, sy * (yb + 0.001), z + 0.012), (0.17, 0.003, 0.01), m['blanco'], 0.0008))
            for xp in (x0 + 0.03, x1 - 0.05):
                if xp < 0.6:
                    q += perno('pernoBajo', (xp, sy * yb, z - 0.075), (0, sy, 0), m, 0.0045, material='acero')
        piezas.append(pieza('cuerpoBajo%d' % k, q, ((x0 + x1) / 2, 0, z - 0.03), cabeza))
    # Quilla de debajo con nervios.
    q = [losa('quilla', _subir(PERFIL_QUILLA), 0.065, m['articulacion'], 0.005)]
    for xn in (0.25, 0.32, 0.39):
        q.append(caja('nervioQuilla', (xn, 0, z - 0.118), (0.008, 0.07, 0.03), m['negro'], 0.002))
    piezas.append(pieza('quillaArma', q, (0.32, 0, z - 0.11), cabeza))
    # Cuerpo de arriba (la corredera), en dos mitades: lumbrera y palanca de
    # carga a la derecha, placa plateada a los lados, pernos.
    ya = ANCHO_ALTO / 2
    for k, (x0, x1) in enumerate(((0.12, 0.4), (0.4, 0.7))):
        q = [losa('corredera', _subir(recortarX(PERFIL_ALTO, x0, x1)), ANCHO_ALTO, m['negro'], 0.006)]
        if k == 0:
            q.append(caja('lumbrera', (0.24, -(ya + 0.0005), z + 0.085), (0.075, 0.004, 0.03), m['negroMate'], 0.001))
            q.append(cilindro('palanca', (0.17, -(ya + 0.018), z + 0.085), 0.007, 0.04, m['acero'], eje='y', lados=32, bisel=0.002))
            q.append(caja('pomoPalanca', (0.17, -(ya + 0.042), z + 0.085), (0.018, 0.014, 0.018), m['articulacion'], 0.004))
        for sy in (-1, 1):
            if k == 1:
                q.append(losa('placaArma', _subir([(0.42, 0.06), (0.56, 0.06), (0.56, 0.09), (0.44, 0.1)]), 0.004, m['plata'], 0.001, y=sy * (ya + 0.001)))
            for xp in (x0 + 0.03, x1 - 0.06):
                if xp < 0.6:
                    q += perno('pernoAlto', (xp, sy * ya, z + 0.055), (0, sy, 0), m, 0.0035, material='acero')
        piezas.append(pieza('corredera%d' % k, q, ((x0 + x1) / 2, 0, z + 0.08), cabeza))
    # Losa de encima con el riel dentado y el guion con su capucha.
    q = [losa('losaAlta', _subir(PERFIL_LOSA), 0.05, m['negro'], 0.004),
         caja('riel', (0.33, 0, z + RIEL_Z - 0.004), (0.32, 0.026, 0.008), m['acero'], 0.0015)]
    for j in range(14):
        q.append(caja('dienteRiel', (0.185 + j * 0.022, 0, z + RIEL_Z + 0.002), (0.009, 0.028, 0.005), m['acero'], 0.0008))
    q.append(caja('baseGuion', (0.49, 0, z + RIEL_Z + 0.008), (0.024, 0.028, 0.012), m['negro'], 0.002))
    q.append(aro('capuchaGuion', (0.49, 0, z + RIEL_Z + 0.028), 0.012, 0.017, 0.016, m['articulacion'], lados=48, bisel=0.002))
    q.append(caja('posteGuion', (0.49, 0, z + RIEL_Z + 0.022), (0.004, 0.003, 0.016), m['blanco'], 0.0005))
    piezas.append(pieza('rielArma', q, (0.33, 0, z + RIEL_Z), cabeza))
    # Freno de boca: puertos a los lados y arriba, corona de acero y la luz.
    q = [losa('frenoBoca', _subir(PERFIL_FRENO), 0.09, m['negro'], 0.007),
         aro('coronaBoca', (BOCA_X + 0.002, 0, z), ANIMA_R - 0.008, ANIMA_R + 0.004, 0.008, m['acero'], lados=96, bisel=0.002)]
    for j in range(4):
        for sy in (-1, 1):
            q.append(caja('puertoBoca', (0.9 + j * 0.022, sy * 0.045, z), (0.011, 0.006, 0.05), m['negroMate'], 0.0))
        q.append(caja('puertoArriba', (0.9 + j * 0.022, 0, z + 0.043), (0.011, 0.04, 0.006), m['negroMate'], 0.0))
    for sy in (-1, 1):
        q += perno('pernoBoca', (0.885, sy * 0.045, z - 0.03), (0, sy, 0), m, 0.0035, material='acero')
    freno = pieza('frenoArma', q, (0.94, 0, z), cabeza)
    piezas.append(freno)
    # Aros de la punta (el dueño, 18-nov: «unos aros en la punta del cañón
    # que giren súper rápido en direcciones contrarias»): tres coronas
    # dentadas por fuera, con muescas cian para que se vea el giro, sobre
    # un manguito oscuro que no gira. Giran con el cañón formado (como los
    # engranajes de dentro), cada uno al revés que el de al lado.
    q = [aro('manguitoPunta', ((ANILLOS_X[0] + ANILLOS_X[-1]) / 2, 0, z), ANIMA_R - 0.008, ANIMA_R + 0.004,
             ANILLOS_X[-1] - ANILLOS_X[0] + 0.016, m['negroMate'], lados=96, bisel=0.001)]
    manguito = pieza('manguitoPunta', q, (ANILLOS_X[0], 0, z), freno)
    for k, x in enumerate(ANILLOS_X):
        mat = m['cobre'] if k % 2 else m['acero']
        q = [aro('aroPunta', (0, 0, 0), ANIMA_R + 0.004, ANILLO_R, 0.011, mat, lados=128, bisel=0.0012)]
        for d in range(28):
            a = 2 * math.pi * d / 28
            diente = caja('dienteAroPunta', (0, 0, 0), (0.009, 0.0045, 0.006), mat, 0.0007)
            diente.data.transform(Matrix.Rotation(a, 4, 'X') @ Matrix.Translation((0, ANILLO_R + 0.002, 0)))
            q.append(diente)
        for d in range(3):
            a = 2 * math.pi * d / 3
            muesca = caja('muescaAroPunta', (0, 0, 0), (0.0125, 0.008, 0.004), m['nucleo'], 0.0005)
            muesca.data.transform(Matrix.Rotation(a, 4, 'X') @ Matrix.Translation((0, (ANIMA_R + ANILLO_R) / 2 + 0.002, 0)))
            q.append(muesca)
        _girable('aroPunta%d' % k, q, Vector((x, 0, z)), manguito, (1, 0, 0), ANILLO_GIRO * (1 if k % 2 else -1))
    # Varilla guía con su soporte delantero.
    q = [cilindro('varilla', (0.75, 0, z - 0.075), 0.007, 0.22, m['acero'], eje='x', lados=32, bisel=0.002),
         caja('soporteVarilla', (0.85, 0, z - 0.06), (0.022, 0.018, 0.045), m['negro'], 0.003)]
    piezas.append(pieza('varillaArma', q, (0.75, 0, z - 0.075), cabeza))
    # Tobera de atrás (el escape del proyectil).
    xt = COLA_X + 0.03
    q = [
        aro('tobera', (xt, 0, z), ANIMA_R, CANON_W, 0.06, m['articulacion'], lados=96, bisel=0.008),
        aro('bocaTobera', (xt - 0.032, 0, z), ANIMA_R, CANON_W + 0.008, 0.012, m['acero'], lados=96, bisel=0.003),
        cilindro('fondoTobera', (xt - 0.02, 0, z), ANIMA_R, 0.004, m['negroMate'], eje='x', lados=64),
    ]
    piezas.append(pieza('toberaCanon', q, (xt, 0, z), cabeza))
    # Mira: la cuenca del ojo en el sitio del alza, sobre el riel.
    rc = _S['OJO_RADIO'] * _S['OJO_ESCALA'] + 0.003
    mx = MIRA.x
    q = [
        cilindro('cuencaMira', (mx - 0.01, 0, MIRA.z), rc + 0.008, 0.07, m['negro'], eje='x', lados=96, bisel=0.006),
        aro('collarMira', (mx + 0.026, 0, MIRA.z), rc - 0.001, rc + 0.01, 0.008, m['articulacion'], lados=96, bisel=0.0015),
        segmento('pieMira', (mx - 0.01, 0, z + RIEL_Z), (mx - 0.01, 0, MIRA.z - rc), 0.03, 0.05, m['negro'], 0.006),
        caja('placaMira', (mx - 0.01, rc + 0.009, MIRA.z), (0.05, 0.003, 0.025), m['plata'], 0.001),
    ]
    for s in (-1, 1):
        q += perno('pernoMira', (mx - 0.03, s * (rc + 0.009), MIRA.z), (0, s, 0), m, 0.004, material='acero')
    piezas.append(pieza('cajaMira', q, (mx - 0.01, 0, MIRA.z), cabeza))
    return piezas


# Por dentro del cañón ----------------------------------------------------------
# El dueño, 18-nov: «que el cañón sea hueco y tenga engranajes girando en todos
# los sentidos, que se vea como un acelerador de partículas por dentro».
# Todo cuelga de `anima` y gira solo con el cañón formado. Cada pieza que
# gira guarda `eje` (su eje, local) y `giro` (rad/s, con signo; en el juego,
# por la velocidad del cañón):
#   coronaCanon{k}  corona dentada pegada al tubo, gira en x; sentidos alternos
#   pinonCanon{k}_{j} piñón entre dos coronas, gira sobre su eje (radial)
#   cardanCanonA/B  dos aros cardán alrededor del núcleo (en z y en y)
#   nucleoCanon     esfera cian del fondo, gira en x
# Las bobinas cian (bobinaCanon) no giran.
CORONAS = 8
CORONA_R = ANIMA_VIEJO - 0.004  # radio de fuera (toca el tubo), antes de encoger
NUCLEO_X = TRAMOS_X + 0.065  # al fondo del tubo, delante de la recámara (que es maciza)


def _girable(nombre, q, centro, padre, eje, giro, base=None):
    o = pieza(nombre, q, (0, 0, 0))
    o.rotation_mode = 'QUATERNION'
    o.matrix_world = Matrix.Translation(centro) @ (base or Matrix.Identity(4))
    bpy.context.view_layer.update()
    mundo = o.matrix_world.copy()
    o.parent = padre
    o.matrix_world = mundo
    o['eje'] = list(eje)
    o['giro'] = giro
    o['base'] = list(o.rotation_quaternion)
    return o


def interiorCanon(anima, m):
    x0, x1 = NUCLEO_X + 0.09, BOCA_X - 0.06
    # Fondo del tubo: placa oscura con un aro de cobre y 8 radios cian.
    antes = set(bpy.data.objects)
    q = [cilindro('fondoCanon', (TRAMOS_X + 0.006, 0, EJE_Z), ANIMA_VIEJO - 0.004, 0.006, m['negroMate'], eje='x', lados=96),
         aro('aroFondo', (TRAMOS_X + 0.01, 0, EJE_Z), 0.03, 0.036, 0.004, m['cobre'], lados=96, bisel=0.0008)]
    for d in range(8):
        a = 2 * math.pi * d / 8
        q.append(segmento('radioFondo', (TRAMOS_X + 0.01, math.cos(a) * 0.038, EJE_Z + math.sin(a) * 0.038), (TRAMOS_X + 0.01, math.cos(a) * 0.058, EJE_Z + math.sin(a) * 0.058), 0.003, 0.003, m['nucleo']))
    o = pieza('fondoCanon', q, (TRAMOS_X, 0, EJE_Z))
    bpy.context.view_layer.update()
    mundo = o.matrix_world.copy()
    o.parent = anima
    o.matrix_world = mundo
    # Luz cian dentro (en el juego, una luz puntual que sigue al cañón).
    datos = bpy.data.lights.new('luzCanon', 'POINT')
    datos.color = (0.3, 0.85, 1.0)
    datos.shadow_soft_size = 0.02
    luz = bpy.data.objects.new('luzCanon', datos)
    bpy.context.scene.collection.objects.link(luz)
    luz.location = ((NUCLEO_X + BOCA_X) / 2, 0, EJE_Z)
    bpy.context.view_layer.update()
    mundo = luz.matrix_world.copy()
    luz.parent = anima
    luz.matrix_world = mundo
    paso = (x1 - x0) / (CORONAS - 1)
    for k in range(CORONAS):
        x = x0 + paso * k
        # Corona: aro de acero o cobre con 30 dientes hacia dentro.
        dientes = 30
        q = [aro('corona', (0, 0, 0), CORONA_R - 0.01, CORONA_R, 0.01, m['cobre'] if k % 2 else m['acero'], lados=96, bisel=0.001)]
        for d in range(dientes):
            a = 2 * math.pi * d / dientes
            t = caja('dienteCorona', (0, 0, 0), (0.008, 0.0035, 0.006), m['cobre'] if k % 2 else m['acero'], 0.0006)
            t.data.transform(Matrix.Rotation(a, 4, 'X') @ Matrix.Translation((0, CORONA_R - 0.012, 0)))
            q.append(t)
        for d in range(6):
            a = 2 * math.pi * d / 6
            q += perno('pernoCorona', (0.006, math.cos(a) * (CORONA_R - 0.005), math.sin(a) * (CORONA_R - 0.005)), (1, 0, 0), m, 0.0025, material='laton')
        _girable('coronaCanon%d' % k, q, Vector((x, 0, EJE_Z)), anima, (1, 0, 0), 3.0 * (1 if k % 2 else -1))
        if k == CORONAS - 1:
            break
        # Bobina cian entre coronas.
        xm = x + paso / 2
        q = [aro('bobina', (xm, 0, EJE_Z), CORONA_R - 0.006, CORONA_R, 0.006, m['nucleo'], lados=96)]
        o = pieza('bobinaCanon%d' % k, q, (xm, 0, EJE_Z))
        bpy.context.view_layer.update()
        mundo = o.matrix_world.copy()
        o.parent = anima
        o.matrix_world = mundo
        # Tres piñones con el eje hacia el centro (giran «de canto»).
        for j in range(3):
            a = 2 * math.pi * j / 3 + (k % 2) * math.pi / 3
            nd = 10
            q = [cilindro('pinon', (0, 0, 0), 0.011, 0.006, m['acero'] if j % 2 else m['laton'], lados=48, bisel=0.001),
                 cilindro('ejePinon', (0, 0, 0.003), 0.003, 0.01, m['articulacion'], lados=16)]
            for d in range(nd):
                b = 2 * math.pi * d / nd
                t = caja('dientePinon', (0, 0, 0), (0.004, 0.003, 0.006), m['acero'] if j % 2 else m['laton'], 0.0005)
                t.data.transform(Matrix.Rotation(b, 4, 'Z') @ Matrix.Translation((0.012, 0, 0)))
                q.append(t)
            radial = Vector((0, math.cos(a), math.sin(a)))
            base = radial.to_track_quat('Z', 'X').to_matrix().to_4x4()
            centro = Vector((xm + paso * 0.25, 0, EJE_Z)) + radial * (CORONA_R - 0.012)
            _girable('pinonCanon%d_%d' % (k, j), q, centro, anima, (0, 0, 1), 9.0 * (1 if (j + k) % 2 else -1), base)
    # Núcleo con dos aros cardán.
    c = Vector((NUCLEO_X, 0, EJE_Z))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=(0, 0, 0), segments=48, ring_count=24)
    esfera = bpy.context.active_object
    esfera.data.materials.append(m['nucleo'])
    q = [esfera]
    for s in (-1, 1):
        q.append(cilindro('polo', (s * 0.02, 0, 0), 0.006, 0.006, m['cobre'], eje='x', lados=32, bisel=0.001))
    _girable('nucleoCanon', q, c, anima, (1, 0, 0), 4.0)
    for nombre, r, eje, giro in (('cardanCanonA', 0.045, (0, 0, 1), 2.2), ('cardanCanonB', 0.034, (0, 1, 0), -3.1)):
        q = [aro(nombre, (0, 0, 0), r - 0.005, r, 0.006, m['acero'] if eje[2] else m['cobre'], lados=96, bisel=0.001)]
        for d in range(12):
            a = 2 * math.pi * d / 12
            q.append(cilindro('marcaCardan', (0, math.cos(a) * (r - 0.0025), math.sin(a) * (r - 0.0025)), 0.0018, 0.008, m['nucleo'], eje='x', lados=12))
        # Pivotes del aro sobre su eje.
        for s in (-1, 1):
            q.append(cilindro('pivoteCardan', tuple(Vector(eje) * s * r), 0.004, 0.008, m['laton'], eje='z' if eje[2] else 'y', lados=16))
        _girable(nombre, q, c, anima, eje, giro)
    # Todo a la medida del tubo fino: cada pieza encoge y se acerca al eje.
    bpy.context.view_layer.update()
    for o in set(bpy.data.objects) - antes:
        if o.type != 'MESH':
            continue
        mw = o.matrix_world.copy()
        p = mw.to_translation()
        o.data.transform(Matrix.Scale(INTERIOR, 4))
        nuevo = Vector((p.x, p.y * INTERIOR, EJE_Z + (p.z - EJE_Z) * INTERIOR))
        o.matrix_world = Matrix.LocRotScale(nuevo, mw.to_quaternion(), Vector((1, 1, 1)))


def girarInterior(fase):
    """Pone cada pieza que gira del interior a `fase` segundos de giro."""
    for o in bpy.data.objects:
        if 'giro' in o.keys() and 'eje' in o.keys():
            base = Quaternion(o['base'])
            o.rotation_quaternion = base @ Quaternion(Vector(o['eje']), o['giro'] * fase)


# Mira roja y láser -------------------------------------------------------------
# El dueño, 18-nov: «que el ojo, al estar en modo mira, se ponga rojo y tire
# un láser rojo que apunte donde impacta el proyectil». El ojo de la mira
# (globoIzq) lleva sus propias copias de los materiales que brillan; el
# juego les cambia el color igual que colorMira(). El láser (laserMira) es
# un cilindro de 1 m en z (origen en la base) que se orienta y estira hasta
# el impacto, con un punto rojo (puntoLaser) donde da.
ROJO = (1.0, 0.04, 0.02)
OBJETIVO = Vector((6.48, 0.0, 1.55))  # donde da el láser en el vídeo (la placa de blanco)


def prepararMira():
    m = materiales()
    cambios = {}
    for clave in ('nucleo', 'ojo', 'iris'):
        if clave in m:
            copia = m[clave].copy()
            copia.name = 'mira_' + clave
            p = _S['nodoPrincipled'](copia)
            copia['base'] = list(p.inputs['Base Color'].default_value)[:3]
            copia['emision'] = list(p.inputs['Emission Color'].default_value)[:3]
            cambios[m[clave]] = copia
    ojo = bpy.data.objects['globoIzq']
    for o in [ojo] + list(ojo.children_recursive):
        if o.type != 'MESH':
            continue
        for ranura in o.material_slots:
            if ranura.material in cambios:
                ranura.material = cambios[ranura.material]
    return list(cambios.values())


def colorMira(r):
    for mat in bpy.data.materials:
        if not mat.name.startswith('mira_'):
            continue
        p = _S['nodoPrincipled'](mat)
        for entrada, clave in (('Base Color', 'base'), ('Emission Color', 'emision')):
            c = mat[clave]
            p.inputs[entrada].default_value = tuple(c[i] + (ROJO[i] - c[i]) * r for i in range(3)) + (1.0,)


def escenaDisparo():
    """Láser, punto del láser, placa de blanco y la explosión del vídeo."""
    m = materiales()
    laserMat = _S['materialLiso']('laserMira', ROJO, 0.3, 0.0, 6.0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.0025, depth=1.0, location=(0, 0, 0.5))
    laser = bpy.context.active_object
    laser.name = 'laserMira'
    laser.data.transform(Matrix.Translation((0, 0, 0.5)))
    laser.location = (0, 0, 0)
    laser.data.materials.append(laserMat)
    laser.hide_render = True
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, location=tuple(OBJETIVO))
    punto = bpy.context.active_object
    punto.name = 'puntoLaser'
    punto.data.materials.append(laserMat)
    punto.hide_render = True
    # Placa de blanco: chapa de acero con marco, remaches y patas.
    x = OBJETIVO.x + 0.04
    q = [_S['caja']('placaBlanco', (x, 0, 1.35), (0.05, 1.3, 1.1), m['gris'], 0.01),
         _S['caja']('marcoBlanco', (x + 0.03, 0, 1.35), (0.02, 1.36, 1.16), m['negro'], 0.006)]
    for s in (-1, 1):
        q.append(segmento('pataBlanco', (x + 0.1, s * 0.5, 0.0), (x + 0.03, s * 0.5, 1.0), 0.06, 0.06, m['negro'], 0.01))
        q.append(_S['caja']('franjaBlanco', (x - 0.027, s * 0.4, 1.35), (0.004, 0.08, 0.9), m['blanco'], 0.001))
    pieza('blanco', q, (x, 0, 0))
    explosion = _S['materialLiso']('explosion', (1.0, 0.35, 0.05), 0.5, 0.0, 5.0)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0, location=tuple(OBJETIVO))
    bola = bpy.context.active_object
    # Bola de fuego abollada (no una esfera lisa).
    import random
    azar = random.Random(7)
    for v in bola.data.vertices:
        v.co *= 0.75 + 0.5 * azar.random()
    bola.name = 'explosion'
    bola.data.materials.append(explosion)
    bpy.ops.object.shade_smooth()
    bola.hide_render = True
    return laser, punto, bola


def ponerLaser(encendido):
    laser = bpy.data.objects['laserMira']
    punto = bpy.data.objects['puntoLaser']
    laser.hide_render = punto.hide_render = not encendido
    if not encendido:
        return
    bpy.context.view_layer.update()
    ojo = bpy.data.objects['globoIzq'].matrix_world.to_translation()
    d = OBJETIVO - ojo
    inicio = ojo + d.normalized() * 0.035
    laser.matrix_world = Matrix.LocRotScale(inicio, d.to_track_quat('Z', 'Y'), Vector((1, 1, (OBJETIVO - inicio).length)))


# Las dos formas ---------------------------------------------------------------

GIRO = Matrix.Rotation(math.radians(90), 4, 'Y')  # coronilla a la boca, cara abajo


def _local(cabeza, mundo):
    return cabeza.matrix_world.inverted() @ mundo


def _guardar(o, clave, matriz):
    o[clave] = [matriz[i][j] for i in range(4) for j in range(4)]


def _leer(o, clave):
    v = o[clave]
    return Matrix([v[0:4], v[4:8], v[8:12], v[12:16]])


def formas(cabeza, trozos, piezasCanon):
    """Guarda en cada pieza su sitio en la cabeza y en el cañón (y deja el
    robot con la cabeza puesta). Devuelve la lista de las que se mueven,
    con su orden en la cascada."""
    O = bpy.data.objects
    bpy.context.view_layer.update()
    lista = []
    # Trozos de la cabeza: cada uno gira con la cabeza entera a su sitio
    # del cañón y se aparta un poco hacia fuera (deja sitio al ánima).
    base = Matrix.Translation(FRENTE) @ GIRO @ Matrix.Translation(-CENTRO_CABEZA)
    for (sector, banda), o in trozos.items():
        mundo = o.matrix_world.copy()
        canon = base @ mundo
        c = canon.to_translation()
        radial = Vector((0, c.y, c.z - EJE_Z))
        if radial.length > 1e-4:
            canon = Matrix.Translation(radial.normalized() * 0.004) @ canon
        _guardar(o, 'poseCabeza', _local(cabeza, mundo))
        _guardar(o, 'poseCanon', _local(cabeza, canon))
        o['nace'] = 0
        # Cascada: primero los de arriba y de frente.
        o['orden'] = (2 - banda) * SECTORES + min(sector, SECTORES - sector)
        lista.append(o)
    # Antenas: van con su trozo pero se recogen (crecen al volver).
    for lado in ('Izq', 'Der'):
        o = O.get('antena' + lado)
        if not o:
            continue
        mundo = o.matrix_world.copy()
        sector, banda = o['celda']
        _guardar(o, 'poseCabeza', _local(cabeza, mundo))
        _guardar(o, 'poseCanon', _local(cabeza, base @ mundo))
        o['nace'] = 0
        o['orden'] = (2 - banda) * SECTORES + min(sector, SECTORES - sector)
        lista.append(o)
    # Lo que sale del cargador: en la cabeza está dentro, en la tapa.
    tapa = Matrix.Translation(TAPA_CARGADOR)
    for k, o in enumerate(piezasCanon):
        canon = o.matrix_world.copy()
        _guardar(o, 'poseCabeza', _local(cabeza, tapa @ Matrix(canon.to_3x3()).to_4x4()))
        _guardar(o, 'poseCanon', _local(cabeza, canon))
        o['nace'] = 1
        o['orden'] = 6 + k * 2
        lista.append(o)
    # Ojos: el izquierdo a la mira, el derecho dentro del cañón (y se esconde).
    for lado in ('Izq', 'Der'):
        o = O['globo' + lado]
        mundo = o.matrix_world.copy()
        if lado == 'Izq':
            canon = Matrix.Translation(MIRA - mundo.to_translation()) @ mundo
        else:
            canon = Matrix.Translation(Vector((FRENTE.x - 0.05, 0, EJE_Z)) - mundo.to_translation()) @ mundo
        _guardar(o, 'poseCabeza', _local(cabeza, mundo))
        _guardar(o, 'poseCanon', _local(cabeza, canon))
        o['nace'] = 0
        o['esconder'] = 1 if lado == 'Der' else 0
        # El de la mira llega cuando ya está su caja (la última del cargador).
        o['orden'] = 6 + 2 * len(piezasCanon) if lado == 'Izq' else 2
        mundoPadre = o.matrix_world.copy()
        o.parent = cabeza
        o.matrix_world = mundoPadre
        lista.append(o)
    return lista


def _suave(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


CAMBIO = 2.2  # s de toda la transformación
VIAJE = 0.6  # s de cada pieza


def pose(cabeza, lista, f):
    """f: 0 cabeza, 1 cañón. Lo mismo que hará el Lua del juego."""
    maximo = max(o['orden'] for o in lista)
    T = f * CAMBIO
    for o in lista:
        a = cabeza.matrix_world @ _leer(o, 'poseCabeza')
        b = cabeza.matrix_world @ _leer(o, 'poseCanon')
        retraso = (CAMBIO - VIAJE) * o['orden'] / maximo
        u = _suave((T - retraso) / VIAJE)
        pa, qa = a.to_translation(), a.to_quaternion()
        pb, qb = b.to_translation(), b.to_quaternion()
        fuera = (pa - CENTRO_CABEZA) + (pb - Vector((pb.x, 0, EJE_Z)))
        if fuera.length > 1e-6:
            fuera.normalize()
        control = (pa + pb) / 2 + fuera * 0.12 + Vector((0, 0, 0.06))
        p = (1 - u) ** 2 * pa + 2 * (1 - u) * u * control + u ** 2 * pb
        q = qa.slerp(qb, u)
        if o['orden'] % 2 == 0 and not o.get('esconder'):
            q = q @ Quaternion((1, 0, 0), math.pi * 4 * u * (1 - u))
        e = 1.0
        if o['nace']:
            e = max(0.001, _suave(u * 1.5))
        if o.get('esconder'):
            e = max(0.001, 1 - _suave((u - 0.5) * 2))
        if o.get('retraer'):
            e = max(0.001, 1 - _suave(u * 2.5))
        o.matrix_world = Matrix.LocRotScale(p, q, Vector((e, e, e)))
    colorMira(_suave((f - 0.85) / 0.15))
    luz = bpy.data.objects.get('luzCanon')
    if luz:
        luz.data.energy = 6.0 * _suave((f - 0.75) / 0.25)
    # La tapa del cargador se abre mientras salen las piezas.
    tapa = bpy.data.objects['tapaCargador']
    abrir = math.sin(math.pi * max(0.0, min(1.0, f)))
    tapa.rotation_euler.y = -math.radians(100) * abrir


# Al juego ----------------------------------------------------------------------
RAIZ_JUEGO = os.path.abspath(os.path.join(_DIR, '..', '..', 'assets', 'batalla', 'robots'))


def _filas(mat):
    return '{ ' + ', '.join('%.6f' % mat[i][j] for i in range(4) for j in range(4)) + ' }'


def exportarCanon(cabeza, lista, ruta):
    """<ruta>: las dos formas de cada pieza que cambia (matriz respecto a
    `cabeza`, su madre), cómo se mueve y los engranajes de dentro. El Lua
    (batalla/robots/especializaciones/lanzador.lua) hace lo mismo que pose()."""
    pivote = cabeza.matrix_world.to_translation()
    maximo = max(o['orden'] for o in lista)
    L = ['-- Cabeza -> cañón del robot lanzamisiles (tools/blender/robot_lanzamisiles.py --glb).',
         '-- Matrices por filas respecto a la pieza cabeza (metros, ejes del juego).',
         'return {',
         '    cambio = %.3f, viaje = %.3f, maximo = %d,' % (CAMBIO, VIAJE, maximo),
         '    centroCabeza = { %.4f, %.4f, %.4f },' % tuple(CENTRO_CABEZA - pivote),
         '    ejeZ = %.4f,' % (EJE_Z - pivote.z),
         '    boca = { %.4f, %.4f, %.4f },' % tuple(Vector((PUNTA_X, 0, EJE_Z)) - pivote),
         '    mira = { %.4f, %.4f, %.4f },' % tuple(MIRA - pivote),
         '    piezas = {']
    for o in sorted(lista, key=lambda o: o['orden']):
        L.append("        { nombre = '%s', orden = %d, nace = %s, esconder = %s, retraer = %s,\n          cabeza = %s,\n          canon = %s }," % (
            o.name, o['orden'], 'true' if o['nace'] else 'false', 'true' if o.get('esconder') else 'false',
            'true' if o.get('retraer') else 'false', _filas(_leer(o, 'poseCabeza')), _filas(_leer(o, 'poseCanon'))))
    L.append('    },')
    L.append('    -- Giran con el cañón formado: eje local y rad/s.')
    L.append('    engranajes = {')
    for o in bpy.data.objects:
        if 'giro' in o.keys() and 'eje' in o.keys():
            e = Vector(o['eje'])
            eje = 'x' if abs(e.x) > 0.5 else ('y' if abs(e.y) > 0.5 else 'z')
            L.append("        { nombre = '%s', eje = '%s', giro = %.3f }," % (o.name, eje, o['giro'] * (1 if (e.x + e.y + e.z) > 0 else -1)))
    L.append('    },')
    L.append('}')
    with open(ruta, 'w', encoding='utf8') as archivo:
        archivo.write('\n'.join(L) + '\n')
    print('CANON', ruta, len(lista), 'piezas')


def exportarMisil(ruta):
    """El misil solo, con las aletas abiertas y la llama (llamaMisil), en un .glb."""
    _S['limpiarEscena']()
    bpy.app.driver_namespace.pop('soldadoMateriales', None)
    misil = _M['construirObus'](_S)
    _M['poseMisil'](misil, 1, 1, 1)
    bpy.context.view_layer.update()
    for o in [misil] + list(misil.children_recursive):
        mundo = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mundo
    for o in list(bpy.data.objects):
        if o.type == 'MESH':
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
            o.hide_render = False
        else:
            bpy.data.objects.remove(o)
    for o in bpy.data.objects:
        _S['uvCaja'](o)
    opciones = dict(filepath=ruta, export_format='GLB', use_selection=False, export_apply=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **opciones)
    except TypeError:
        bpy.ops.export_scene.gltf(**opciones)
    print('MISIL', ruta, len(bpy.data.objects), 'piezas')


# Fotos y vídeo ----------------------------------------------------------------

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
    fondo.inputs['Strength'].default_value = 1.0
    s.world = mundo
    bpy.ops.mesh.primitive_plane_add(size=20)
    suelo = bpy.context.active_object
    mat = bpy.data.materials.new('sueloFoto')
    mat.use_nodes = True
    next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value = (0.36, 0.37, 0.35, 1)
    suelo.data.materials.append(mat)
    bpy.ops.object.light_add(type='SUN')
    sol = bpy.context.active_object
    sol.data.energy = 4
    sol.rotation_euler = (math.radians(40), math.radians(15), math.radians(140))
    bpy.ops.object.light_add(type='AREA', location=(1.5, -1.5, 2.2))
    luz = bpy.context.active_object
    luz.data.energy = 120
    luz.data.size = 2
    luz.rotation_euler = (Vector((0, 0, 1.6)) - luz.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.object.camera_add()
    camara = bpy.context.active_object
    camara.data.lens = 50
    s.camera = camara
    return camara


def foto(camara, desde, hacia, ruta, lente=50):
    camara.location = desde
    camara.data.lens = lente
    camara.rotation_euler = (Vector(hacia) - Vector(desde)).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = ruta
    bpy.ops.render.render(write_still=True)


def principal():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    carpeta = args[0] if args else '/tmp'
    construir(brazoDerecho=lambda: etapaGarra(-1), brazoIzquierdo=lambda: etapaGarra(1))
    etapaCargador()
    bpy.context.view_layer.update()
    cabeza, trozos = partirCabeza()
    piezasCanon = etapaCanon(cabeza)
    lista = formas(cabeza, trozos, piezasCanon)
    prepararMira()
    print('PIEZAS', len(trozos), 'trozos de cabeza,', len(piezasCanon), 'del cargador,', len(lista), 'en total')
    if '--glb' in args:
        pose(cabeza, lista, 0.0)
        girarInterior(0.0)
        exportarCanon(cabeza, lista, os.path.join(RAIZ_JUEGO, 'lanzamisiles_canon.lua'))
        # El soldado deja su pose de pie antes de exportar; este no tiene
        # metralleta: ya está de pie.
        _S['poseSoldado'] = lambda *a, **k: None
        _S['exportarJuego'](os.path.join(RAIZ_JUEGO, 'lanzamisiles.glb'))
        exportarMisil(os.path.join(RAIZ_JUEGO, 'proyectil.glb'))
        return
    camara = escenario()
    escenaDisparo()
    for nombre, f in (('cabeza', 0.0), ('canon', 1.0)):
        pose(cabeza, lista, f)
        foto(camara, (2.0, 1.5, 2.1), (0.0, 0.0, 1.45), os.path.join(carpeta, 'lanzamisiles_%s.png' % nombre))
        foto(camara, (0.0, 3.2, 1.7), (-0.1, 0.0, 1.4), os.path.join(carpeta, 'lanzamisiles_%s_lado.png' % nombre))
        foto(camara, (0.9, 0.75, 2.0), (0.0, 0.0, 1.72), os.path.join(carpeta, 'lanzamisiles_%s_cerca.png' % nombre), 60)
        if f == 1.0:
            girarInterior(0.7)
            if os.environ.get('LANZAMISILES_DEPURAR'):
                dg = bpy.context.evaluated_depsgraph_get()
                for dy, dz in ((0, 0), (0.03, 0), (0, 0.03)):
                    p0 = Vector((BOCA_X + 0.2, dy, EJE_Z + dz))
                    for _ in range(6):
                        ok, loc, nor, idx, ob, mat = bpy.context.scene.ray_cast(dg, p0, Vector((-1, 0, 0)))
                        if not ok:
                            break
                        print('RAYO', dy, dz, ob.name, round(loc.x, 3))
                        p0 = loc + Vector((-0.002, 0, 0))
            foto(camara, (BOCA_X + 0.42, 0.1, EJE_Z + 0.05), (NUCLEO_X, 0, EJE_Z), os.path.join(carpeta, 'lanzamisiles_boca.png'), 40)
            foto(camara, (BOCA_X + 0.12, 0.03, EJE_Z + 0.01), (NUCLEO_X, 0, EJE_Z), os.path.join(carpeta, 'lanzamisiles_boca_cerca.png'), 35)
            ponerLaser(True)
            foto(camara, (MIRA.x + 0.5, 0.45, MIRA.z + 0.12), tuple(MIRA), os.path.join(carpeta, 'lanzamisiles_mira.png'), 50)
            foto(camara, (3.2, 5.6, 2.4), (3.2, 0.0, 1.3), os.path.join(carpeta, 'lanzamisiles_laser.png'), 24)
            ponerLaser(False)
    # Láminas del misil (aparte, delante del robot): abierto y plegado.
    misil = _M['construirObus'](_S)
    sitio = Vector((0.0, -3.0, 1.0))
    for nombre, abrir, lente, desde in (('abierto', 1, 70, (0.55, -2.45, 1.22)), ('plegado', 0, 60, (0.0, -2.2, 1.05))):
        misil.matrix_world = Matrix.Translation(sitio)
        _M['poseMisil'](misil, abrir, abrir, 0)
        foto(camara, desde, tuple(sitio), os.path.join(carpeta, 'misil_%s.png' % nombre), lente)
    misil.hide_render = True
    for h in misil.children_recursive:
        h.hide_render = True
    if '--video' in args:
        s = bpy.context.scene
        s.render.resolution_x, s.render.resolution_y = 960, 720
        fps = 30

        def cam(desde, hacia, lente):
            desde = Vector(desde)
            return (desde, (Vector(hacia) - desde).to_track_quat('-Z', 'Y').to_euler(), lente)
        general = cam((1.9, 1.45, 2.15), (-0.05, 0.0, 1.55), 50)
        boca = cam((BOCA_X + 0.42, 0.1, EJE_Z + 0.05), (NUCLEO_X, 0, EJE_Z), 40)
        ancha = cam((3.2, 5.6, 2.4), (3.2, 0.0, 1.3), 24)
        # Vuelo: del tubo a la placa por una curva suave, acelerando.
        salida0 = Vector((BOCA_X - 0.1, 0, EJE_Z))
        dirFin = (OBJETIVO - Vector((2.6, 0, EJE_Z))).normalized()
        llegada = OBJETIVO - dirFin * 0.075
        VUELO = 0.55

        def curva(u):
            p0, p1, p2 = salida0, Vector((2.6, 0, EJE_Z)), llegada
            p = (1 - u) ** 2 * p0 + 2 * (1 - u) * u * p1 + u ** 2 * p2
            d = 2 * (1 - u) * (p1 - p0) + 2 * u * (p2 - p1)
            return p, d.normalized()

        def misilEn(p, d, giro):
            q = d.to_track_quat('X', 'Z') @ Quaternion((1, 0, 0), giro)
            misil.matrix_world = Matrix.LocRotScale(p, q, Vector((1, 1, 1)))

        def verMisil(si):
            misil.hide_render = not si
            for h in misil.children:
                if not h.name.startswith('llamaMisil'):
                    h.hide_render = not si

        bola = bpy.data.objects['explosion']
        bolaMat = bola.data.materials[0]
        cuadros = []

        def tramo(duracion, camara_, estado):
            n = int(duracion * fps)
            for c in range(n):
                cuadros.append((camara_, estado(c / max(1, n - 1), c / fps)))
        tramo(1.0, general, lambda u, t: {'f': 0})
        tramo(CAMBIO + 0.3, general, lambda u, t: {'f': min(1.0, u * 1.13)})
        tramo(0.8, general, lambda u, t: {'f': 1})
        tramo(1.3, ancha, lambda u, t: {'f': 1, 'laser': u > 0.2})
        tramo(2.4, boca, lambda u, t: {'f': 1, 'laser': True, 'dentro': u, 'giro': 1 + 3 * u})
        tramo(1.6, ancha, lambda u, t: {'f': 1, 'laser': t < VUELO, 'vuelo': t, 'giro': 4})
        tramo(0.4, ancha, lambda u, t: {'f': 1, 'giro': 4 - 3 * u})
        tramo(CAMBIO + 0.3, general, lambda u, t: {'f': max(0.0, 1 - u * 1.13)})
        tramo(0.8, general, lambda u, t: {'f': 0})
        fase = 0.0
        tmp = tempfile.mkdtemp(prefix='lanzamisiles_')
        k = 0
        for (lugar, giro, lente), e in cuadros:
            camara.location, camara.rotation_euler, camara.data.lens = lugar, giro, lente
            f = e['f']
            pose(cabeza, lista, f)
            fase += e.get('giro', 1) * _suave((f - 0.8) / 0.2) / fps
            girarInterior(fase)
            ponerLaser(e.get('laser', False))
            verMisil(False)
            _M['poseMisil'](misil, 0, 0, 0)
            bola.hide_render = True
            if 'dentro' in e:
                verMisil(True)
                misilEn(Vector((BOCA_X - 0.2 + 0.06 * e['dentro'], 0, EJE_Z)), Vector((1, 0, 0)), 0)
            if 'vuelo' in e:
                t = e['vuelo']
                if t < VUELO:
                    verMisil(True)
                    u = (t / VUELO) ** 1.5
                    p, d = curva(u)
                    misilEn(p, d, t * 25)
                    fuera = max(0.0, (p.x - BOCA_X - 0.25) / 0.3)
                    _M['poseMisil'](misil, _suave(fuera), _suave(fuera * 1.5), 0.6 + 0.4 * min(1.0, t / 0.1))
                else:
                    b = (t - VUELO) / (1.6 - VUELO)
                    bola.hide_render = False
                    r = 0.1 + 0.7 * _suave(b * 2.5)
                    bola.scale = (r, r, r)
                    _S['nodoPrincipled'](bolaMat).inputs['Emission Strength'].default_value = 5 * (1 - _suave(b))
                    bola.rotation_euler = (b * 2, b * 3, 0)
            s.render.filepath = os.path.join(tmp, 'c%04d.png' % k)
            bpy.ops.render.render(write_still=True)
            k += 1
        salida = os.path.join(carpeta, 'lanzamisiles.mp4')
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(fps), '-i', os.path.join(tmp, 'c%04d.png'),
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '23', salida], check=True)
        for nombre in os.listdir(tmp):
            os.remove(os.path.join(tmp, nombre))
        os.rmdir(tmp)
        print('VIDEO', salida, k)
    pose(cabeza, lista, 0.0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(carpeta, 'lanzamisiles.blend'))


# Solo al ejecutarlo (no al cargarlo desde otro script: robot_conductor.py).
if __name__ == '__main__' and bpy.app.background:
    principal()

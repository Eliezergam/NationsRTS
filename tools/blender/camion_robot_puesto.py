"""Puesto del robot conductor del camión de 4 misiles (el dueño, 18-nov).

Sin cabina: el robot soldado (con una garra en cada brazo) va sentado al aire
como en un cortacésped de montar, agarrado a dos palancas curvas, y con las
ruedas de los pies sobre unos rodillos: al girar sus ruedas mueve el camión
(acelera, frena y da marcha atrás). El dueño: «que se vean las llantas
completamente» y «una estructura compleja futurista con muchos cables,
engranajes, cintas, piezas moviéndose» (nada de un cajón sencillo).

Este archivo hace solo la máquina de los pies, en su sitio respecto a las
ruedas del robot (centro `cx`, `cz`; ruedas en y = ±RUEDA_Y):

  rodillos     dos ejes de lado a lado (delante y detrás de las ruedas), con
               un tambor de acero bajo cada rueda y bandas de cobre;
  bastidores   a cada lado, de barras con chaflanes, cojinetes y pernos;
  engranajes   en el eje trasero, uno intermedio y uno grande abajo, en los
               dos lados, engranados de verdad (distancia = suma de radios);
  cintas       dentadas, del eje de delante al de detrás (los dos giran igual);
  transmisión  eje del engranaje grande, con aros cian, y un árbol hacia atrás
               que entra en el chasis con su junta;
  pistones     que sujetan los bastidores a la plataforma;
  cables       mazos de goma y cobre con sus conectores.

Piezas móviles (objeto aparte, origen en su eje, propiedades `eje` y `giro`:
radianes por radián de la rueda del robot): rodilloDelantero/Trasero,
engranaje{Rodillo,Intermedio,Grande}{Der,Izq}, arbolTransmision.

En el Blender del dueño:
    exec(open('tools/blender/camion_robot_puesto.py').read(), ns)
    ns['construirPuesto'](cx, cz)
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.expanduser('~/NationsRTS/tools/blender')
_S = bpy.app.driver_namespace.get('soldado')
if _S is None:
    _S = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
    with open(_S['__file__'], encoding='utf8') as _archivo:
        exec(_archivo.read(), _S)
caja, cilindro, segmento, pieza, perno, aro = (_S[k] for k in ('caja', 'cilindro', 'segmento', 'pieza', 'perno', 'aro'))
materiales, objetoDe = _S['materiales'], _S['objetoDe']

RUEDA_R = 0.15
RUEDA_Y = 0.175
RODILLO_R = 0.045
RODILLO_DX = 0.115  # delante y detrás del centro de la rueda
BASTIDOR_Y = 0.27
ENGRANAJE_Y = 0.305
CINTA_Y = 0.345
POLEA_R = 0.035
MODULO = 0.0066  # paso de los dientes: radio = MODULO * dientes / 2
# Las ruedas de los pies se convierten en engranajes (el dueño, 18-nov: «las
# llantas deberían convertirse en unos engranajes que se conecten al
# sistema»): 44 dientes (radio de paso ~ el de la rueda) que engranan con un
# piñón de 18 en cada eje, en vez de los rodillos.
PIE_DIENTES = 44
PINON_DIENTES = 18


def engranaje(nombre, centro, dientes, ancho, material, eje='y', agujero=0.0):
    """Rueda dentada de `dientes` dientes (radio de paso MODULO·dientes/2),
    de grosor `ancho` a lo largo de `eje`, hecha en el origen y llevada a
    `centro`. Dientes trapeciales de verdad en el perfil."""
    r = MODULO * dientes / 2
    alto = MODULO * 1.1
    bm = bmesh.new()
    perfil = []
    for k in range(dientes):
        a0 = 2 * math.pi * k / dientes
        paso = 2 * math.pi / dientes
        for f, rr in ((0.0, r - alto), (0.18, r + alto * 0.9), (0.42, r + alto * 0.9), (0.6, r - alto)):
            a = a0 + paso * f
            perfil.append((rr * math.cos(a), rr * math.sin(a)))
    arriba = [bm.verts.new((x, y, ancho / 2)) for x, y in perfil]
    abajo = [bm.verts.new((x, y, -ancho / 2)) for x, y in perfil]
    bm.faces.new(arriba)
    bm.faces.new(list(reversed(abajo)))
    n = len(perfil)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((abajo[k], abajo[j], arriba[j], arriba[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    elif eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    o = objetoDe(nombre, bm, material)
    o['dientes'] = dientes
    return o


def radioEngranaje(dientes):
    return MODULO * dientes / 2


def detalleEngranaje(nombre, centro, dientes, ancho, m, material, eje='y', lado=1):
    """Engranaje con cubo, radios calados (6 ventanas) y pernos: las piezas,
    sin unir."""
    c = Vector(centro)
    r = radioEngranaje(dientes)
    n = Vector((0, lado, 0)) if eje == 'y' else Vector((lado, 0, 0))
    q = [engranaje(nombre, c, dientes, ancho, material, eje)]
    q.append(cilindro(nombre + 'Cubo', c + n * (ancho / 2 + 0.006), r * 0.32, 0.012, m['articulacion'], eje=eje, lados=48, bisel=0.002))
    q.append(aro(nombre + 'Luz', c + n * (ancho / 2 + 0.001), r * 0.5, r * 0.56, 0.003, m['nucleo'], lados=96, eje=eje))
    for k in range(6):
        a = 2 * math.pi * k / 6
        d = Vector((math.cos(a), 0, math.sin(a))) if eje == 'y' else Vector((0, math.cos(a), math.sin(a)))
        q += perno(nombre + 'Perno', c + n * (ancho / 2 + 0.012) + d * r * 0.2, n, m, 0.004, material='acero')
        # Ventana entre radios: un hueco oscuro marcado (ranura).
        q.append(caja(nombre + 'Ventana', (0, 0, 0), (r * 0.28, 0.003, r * 0.14), m['negroMate'], 0.001))
        v = q[-1]
        giro = Matrix.Rotation(-a, 4, 'Y') if eje == 'y' else Matrix.Rotation(a, 4, 'X')
        v.data.transform(Matrix.Translation(c + n * (ancho / 2 + 0.0005) + d * r * 0.7) @ giro)
    return q


def cinta(nombre, c1, c2, r, y, ancho, grosor, m):
    """Cinta dentada cerrada alrededor de dos poleas iguales de radio `r`
    (centros `c1`, `c2` en el plano x-z, a la altura y = `y`)."""
    c1, c2 = Vector((c1[0], c1[1])), Vector((c2[0], c2[1]))
    d = (c2 - c1).normalized()
    nrm = Vector((-d.y, d.x))
    camino = []
    pasos = 24
    ang0 = math.atan2(nrm.y, nrm.x)
    for c, a_ini in ((c2, ang0), (c1, ang0 + math.pi)):
        for k in range(pasos + 1):
            a = a_ini - math.pi * k / pasos
            camino.append(c + Vector((math.cos(a), math.sin(a))) * (r + grosor / 2))
    bm = bmesh.new()
    anillos = []
    for p in camino:
        cen = p
        rad = (p - (c1 if (p - c1).length < (p - c2).length else c2)).normalized()
        dentro = cen - rad * grosor / 2
        fuera = cen + rad * grosor / 2
        anillos.append([bm.verts.new((v.x, y + s * ancho / 2, v.y)) for v in (dentro, fuera) for s in (-1, 1)])
    n = len(anillos)
    for k in range(n):
        a, b = anillos[k], anillos[(k + 1) % n]
        # 0 dentro-, 1 dentro+, 2 fuera-, 3 fuera+
        for i, j in ((0, 1), (1, 3), (3, 2), (2, 0)):
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    q = [objetoDe(nombre, bm, m['goma'])]
    # Dientes por fuera, cada pocos puntos del camino, y franja cian.
    for k in range(0, n, 2):
        p = camino[k]
        rad = (p - (c1 if (p - c1).length < (p - c2).length else c2)).normalized()
        t = p + rad * (grosor / 2 + 0.002)
        diente = caja(nombre + 'Diente', (0, 0, 0), (0.006, ancho * 0.9, 0.004), m['negroMate'], 0.0008)
        diente.data.transform(Matrix.Translation((t.x, y, t.y)) @ Matrix.Rotation(-math.atan2(rad.y, rad.x) + math.pi / 2, 4, 'Y'))
        q.append(diente)
    return q


def cable(nombre, puntos, radio, material):
    """Cable curvo por `puntos` (Bézier automática), ya como malla."""
    cu = bpy.data.curves.new(nombre, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = radio
    cu.bevel_resolution = 4
    cu.resolution_u = 12
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(puntos) - 1)
    for bp, p in zip(sp.bezier_points, puntos):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    o = bpy.data.objects.new(nombre, cu)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    bpy.context.view_layer.update()
    malla = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(o)
    nuevo = bpy.data.objects.new(nombre, malla)
    bpy.context.collection.objects.link(nuevo)
    return nuevo


def conector(nombre, centro, direccion, m, radio=0.012):
    """Conector del cable: casquillo de acero con un aro de cobre."""
    d = Vector(direccion).normalized()
    giro = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    q = [cilindro(nombre, (0, 0, 0), radio * 1.4, radio * 3, m['acero'], lados=24, bisel=0.002),
         cilindro(nombre + 'Aro', (0, 0, radio * 1.2), radio * 1.6, radio * 0.6, m['cobre'], lados=24)]
    for o in q:
        o.data.transform(Matrix.Translation(Vector(centro)) @ giro)
    return q


def piston(nombre, a, b, m, r=0.016):
    """Pistón hidráulico de `a` (cuerpo) a `b` (vástago), con sus ojos."""
    a, b = Vector(a), Vector(b)
    medio = a + (b - a) * 0.55
    q = [segmento(nombre + 'Cuerpo', a, medio, r * 2, r * 2, m['negro'], r * 0.6),
         segmento(nombre + 'Vastago', medio, b, r * 1.1, r * 1.1, m['plata'], r * 0.3),
         caja(nombre + 'Franja', (0, 0, 0), (r * 2.1, r * 2.1, 0.008), m['blanco'], 0.001)]
    giro = (b - a).normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    q[2].data.transform(Matrix.Translation(a + (b - a) * 0.4) @ giro)
    for p in (a, b):
        q.append(cilindro(nombre + 'Ojo', p, r * 1.3, r * 2.2, m['articulacion'], eje='y', lados=24, bisel=0.002))
    return q


def engranajePie(nombre, centro, lado, m):
    """Lo que sale de la rueda del pie al sentarse: engranaje de
    PIE_DIENTES dientes del ancho de la rueda, con buje de cobre, seis radios,
    aro cian y pernos. Hecho en `centro` (el de la rueda)."""
    c = Vector(centro)
    r = radioEngranaje(PIE_DIENTES)
    q = [engranaje(nombre, c, PIE_DIENTES, 0.05, m['negro'], 'y')]
    q.append(aro(nombre + 'Llanta', c, r * 0.62, r * 0.78, 0.056, m['articulacion'], lados=96, eje='y', bisel=0.003))
    q.append(cilindro(nombre + 'Buje', c, r * 0.24, 0.07, m['cobre'], eje='y', lados=48, bisel=0.004))
    for s in (-1, 1):
        q.append(aro(nombre + 'Luz', c + Vector((0, s * 0.029, 0)), r * 0.66, r * 0.7, 0.003, m['nucleo'], lados=96, eje='y'))
    for k in range(6):
        a = 2 * math.pi * k / 6
        d = Vector((math.cos(a), 0, math.sin(a)))
        q.append(segmento(nombre + 'Radio', c + d * r * 0.22, c + d * r * 0.64, 0.03, 0.022, m['plata'], 0.004))
        q += perno(nombre + 'Perno', c + d * r * 0.16 + Vector((0, lado * 0.036, 0)), (0, lado, 0), m, 0.005, material='acero')
    return q


def _movil(nombre, q, centro, eje, giro):
    o = pieza(nombre, q, centro)
    o['eje'] = eje
    o['giro'] = giro
    return o


def construirPuesto(cx, cz, padre=None):
    """Toda la máquina de los pies alrededor de las ruedas del robot (centro
    de las ruedas en `cx`, `cz`). Devuelve los objetos que se mueven."""
    m = materiales()
    distancia = radioEngranaje(PIE_DIENTES) + radioEngranaje(PINON_DIENTES)
    zr = cz - math.sqrt(distancia ** 2 - RODILLO_DX ** 2)
    xd, xt = cx + RODILLO_DX, cx - RODILLO_DX
    moviles = []
    rodillo = PIE_DIENTES / PINON_DIENTES  # vueltas del piñón por vuelta del pie
    # Ejes de lado a lado con un piñón bajo cada pie y poleas fuera.
    for nombre, x in (('rodilloDelantero', xd), ('rodilloTrasero', xt)):
        q = [cilindro(nombre + 'Eje', (x, 0, zr), 0.014, 2 * CINTA_Y + 0.03, m['acero'], eje='y', lados=32)]
        for s in (-1, 1):
            y = s * RUEDA_Y
            q += detalleEngranaje(nombre + 'Pinon', (x, y, zr), PINON_DIENTES, 0.05, m, m['acero'], 'y', s)
            q.append(cilindro(nombre + 'Polea', (x, s * CINTA_Y, zr), POLEA_R, 0.03, m['articulacion'], eje='y', lados=48, bisel=0.003))
            q.append(aro(nombre + 'PoleaLuz', (x, s * (CINTA_Y + 0.016), zr), POLEA_R * 0.4, POLEA_R * 0.5, 0.002, m['nucleo'], lados=48, eje='y'))
        moviles.append(_movil(nombre, q, (x, 0, zr), 'y', -rodillo))
    # Engranajes del eje trasero, intermedio y grande (a los dos lados).
    d1, d2, d3 = 18, 12, 30
    r1, r2, r3 = radioEngranaje(d1), radioEngranaje(d2), radioEngranaje(d3)
    a12 = math.radians(235)
    c1 = Vector((xt, zr))
    c2 = c1 + Vector((math.cos(a12), math.sin(a12))) * (r1 + r2)
    a23 = math.radians(175)
    c3 = c2 + Vector((math.cos(a23), math.sin(a23))) * (r2 + r3)
    giro1 = -rodillo
    giro2 = -giro1 * d1 / d2
    giro3 = -giro2 * d2 / d3
    for s, lado in ((-1, 'Der'), (1, 'Izq')):
        y = s * ENGRANAJE_Y
        for nombre, c, d, giro, mat in (('engranajeRodillo', c1, d1, giro1, m['cobre']), ('engranajeIntermedio', c2, d2, giro2, m['acero']), ('engranajeGrande', c3, d3, giro3, m['cobre'])):
            q = detalleEngranaje(nombre + lado, (c.x, y, c.y), d, 0.016, m, mat, 'y', s)
            moviles.append(_movil(nombre + lado, q, (c.x, y, c.y), 'y', giro))
    # Ejes fijos del intermedio.
    fijos = []
    for s in (-1, 1):
        fijos.append(cilindro('ejeIntermedio', (c2.x, s * (BASTIDOR_Y + 0.02), c2.y), 0.01, 0.06, m['acero'], eje='y', lados=24))
    # Árbol del engranaje grande: de lado a lado, aros cian, y una caja de
    # reenvío en el centro con el árbol hacia atrás.
    q = [cilindro('arbolEje', (c3.x, 0, c3.y), 0.02, 2 * ENGRANAJE_Y + 0.02, m['acero'], eje='y', lados=32)]
    for k in range(-3, 4):
        q.append(aro('arbolLuz', (c3.x, k * 0.07, c3.y), 0.021, 0.027, 0.006, m['nucleo'] if k % 2 else m['cobre'], lados=48, eje='y'))
    moviles.append(_movil('arbolTransmision', q, (c3.x, 0, c3.y), 'y', giro3))
    fijos.append(caja('cajaReenvio', (c3.x, 0, c3.y), (0.1, 0.12, 0.1), m['negro'], 0.012))
    fijos += perno('pernoReenvio', (c3.x + 0.05, 0.04, c3.y + 0.03), (1, 0, 0), m, 0.005, material='acero')
    fijos += perno('pernoReenvio', (c3.x + 0.05, -0.04, c3.y + 0.03), (1, 0, 0), m, 0.005, material='acero')
    fijos.append(caja('placaReenvio', (c3.x, 0, c3.y + 0.051), (0.07, 0.08, 0.003), m['plata'], 0.001))
    xa = c3.x - 0.05
    fijos.append(cilindro('arbolAtras', (xa - 0.2, 0, c3.y), 0.022, 0.4, m['articulacion'], eje='x', lados=32, bisel=0.003))
    fijos.append(cilindro('juntaArbol', (xa - 0.02, 0, c3.y), 0.034, 0.04, m['acero'], eje='x', lados=32, bisel=0.004))
    for k in range(3):
        fijos.append(aro('arbolAtrasLuz', (xa - 0.1 - k * 0.1, 0, c3.y), 0.023, 0.029, 0.006, m['nucleo'], lados=48, eje='x'))
    # Cintas dentadas de delante a detrás.
    for s in (-1, 1):
        fijos += cinta('cintaRodillos', (xd, zr), (xt, zr), POLEA_R, s * CINTA_Y, 0.022, 0.006, m)
    # Bastidores: barras con chaflanes, cojinetes en cada eje, pernos.
    x0, x1 = c3.x - r3 - 0.02, xd + 0.08
    zb, zt = c3.y - r3 - 0.02, zr + 0.025
    for s in (-1, 1):
        y = s * BASTIDOR_Y
        barras = [((x0, zb), (x1, zb)), ((x0 + 0.05, zt), (x1, zt)), ((x1, zb), (x1, zt)), ((x0, zb), (x0 + 0.05, zt)),
                  ((xt, zb), (xt, zt)), ((xt, zb), (x1, zt)), ((xd, zb), (xd, zt)), ((x0 + 0.05, zt), (c3.x, c3.y + r3 * 0.4))]
        for (ax, az), (bx, bz) in barras:
            fijos.append(segmento('barraBastidor', (ax, y, az), (bx, y, bz), 0.016, 0.022, m['negro'], 0.005))
        fijos.append(segmento('franjaBastidor', (x0 + 0.06, y + s * 0.0085, zb + 0.002), (x1 - 0.03, y + s * 0.0085, zb + 0.002), 0.002, 0.006, m['blanco']))
        for x, z, rc in ((xd, zr, 0.03), (xt, zr, 0.03), (c3.x, c3.y, 0.04), (c2.x, c2.y, 0.022)):
            fijos.append(cilindro('cojinete', (x, y, z), rc, 0.03, m['articulacion'], eje='y', lados=48, bisel=0.004))
            fijos.append(aro('cojineteAro', (x, y + s * 0.016, z), rc * 0.55, rc * 0.95, 0.004, m['plata'], lados=48, eje='y'))
            for k in range(4):
                a = math.pi / 4 + k * math.pi / 2
                fijos += perno('pernoCojinete', (x + math.cos(a) * rc * 0.75, y + s * 0.018, z + math.sin(a) * rc * 0.75), (0, s, 0), m, 0.0035, material='acero')
        for (px, pz) in ((x0, zb), (x1, zb), (x1, zt), (xt, zb)):
            fijos += perno('pernoBastidor', (px, y + s * 0.012, pz), (0, s, 0), m, 0.005, material='acero')
    # Travesaños entre bastidores.
    for x, z in ((x1, zb), (x0, zb), (x1, zt)):
        fijos.append(segmento('travesano', (x, -BASTIDOR_Y, z), (x, BASTIDOR_Y, z), 0.02, 0.02, m['articulacion'], 0.004))
    # Pistones: del bastidor a la plataforma (delante y detrás).
    plataforma = 2.11
    for s in (-1, 1):
        fijos += piston('pistonDelantero', (x1, s * BASTIDOR_Y, zb + 0.02), (x1 + 0.16, s * 0.42, plataforma - 0.03), m)
        fijos += piston('pistonTrasero', (x0 + 0.02, s * BASTIDOR_Y, zb + 0.02), (x0 - 0.12, s * 0.42, plataforma - 0.03), m)
    # Cables: de los cojinetes a la plataforma y al asiento, en mazos.
    colores = (m['goma'], m['cobre'], m['goma'], m['negroMate'])
    for s in (-1, 1):
        y = s * (BASTIDOR_Y + 0.03)
        rutas = [
            [(xd, y, zr), (xd + 0.05, y + s * 0.05, zr - 0.1), (x1 + 0.1, y + s * 0.1, zb - 0.02), (x1 + 0.22, s * 0.48, plataforma - 0.05)],
            [(xt, y, zr - 0.02), (xt - 0.05, y + s * 0.06, zb - 0.04), (x0 - 0.05, s * 0.36, zb + 0.02), (x0 - 0.18, s * 0.33, plataforma - 0.04)],
            [(c3.x, y, c3.y - 0.03), (c3.x + 0.05, y + s * 0.04, zb - 0.05), (c3.x - 0.1, s * 0.22, zb - 0.06), (x0 - 0.2, s * 0.12, plataforma - 0.06)],
            [(c2.x, y, c2.y), (c2.x + 0.03, y + s * 0.08, c2.y + 0.05), (x0 + 0.02, s * 0.4, zt + 0.06), (x0 - 0.1, s * 0.46, plataforma - 0.02)],
        ]
        for k, ruta in enumerate(rutas):
            fijos.append(cable('cablePuesto', [Vector(p) for p in ruta], 0.007 if k % 2 else 0.009, colores[k]))
            a, b = Vector(ruta[0]), Vector(ruta[1])
            fijos += conector('conectorCable', a, a - b, m, 0.007)
            a, b = Vector(ruta[-1]), Vector(ruta[-2])
            fijos += conector('conectorCable', a, a - b, m, 0.007)
    estructura = pieza('puestoEstructura', fijos, (cx, 0, zr))
    bpy.context.view_layer.update()
    for o in moviles:
        mundo = o.matrix_world.copy()
        o.parent = estructura
        o.matrix_world = mundo
    if padre:
        mundo = estructura.matrix_world.copy()
        estructura.parent = padre
        estructura.matrix_world = mundo
    return estructura, moviles, {'zr': zr, 'x0': x0, 'x1': x1, 'zb': zb}

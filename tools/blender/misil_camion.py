# Misil del camión de misiles con robot conductor (el dueño, 21-nov: la copia
# pública va sin nada del pack de Synty; los cuatro misiles de la maqueta
# eran la malla de misil_synty4.glb, medido: los 544 vértices coinciden).
# Diseño propio con el acabado de la casa (biselado, sombreado suave, sin
# facetas), con las medidas del de antes para que encaje en la rampa:
#
#   8,32 m de largo, origen en la cola, +x hacia la punta, eje en y = z = 0;
#   cuerpo de 0,224 m de radio; cuatro aletas en X (a 45°) que llegan a
#   0,335 m del eje (los misiles van a 0,64 m uno de otro: no se tocan).
#
# De atrás a delante:
#   - tobera de acero y faldón negro de cola;
#   - cuatro aletas trapezoidales en flecha, con el canto biselado;
#   - cuerpo pintado de camuflaje (material `camionMisil`,
#     tools/texturas_camion_robot.py) con dos juntas de sección de acero y
#     dos argollas de izado arriba;
#   - franja blanca y junta de acero antes de la ojiva;
#   - ojiva ojival de camuflaje y punta negra redondeada.
#
# Las caras de `camionMisil` llevan UV propias en metros / LADO_M (u a lo
# largo, v alrededor), con un desplazamiento por misil para que los cuatro no
# tengan las mismas manchas; el resto, las de caja de exportarJuego.
#
# Uso (desde camion_robot_exportar.py): construirMisilCamion(S, m, desfase)
# con S el espacio de nombres de robot_soldado.py y m los materiales
# {'camuflaje', 'negro', 'blanco', 'acero'}; devuelve un objeto de malla en
# metros con el origen en la cola.

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

LARGO = 8.32
R = 0.224
LADO_M = 4.0  # m que cubre la imagen del camuflaje (texturas_camion_robot.py)
LADOS = 32  # lados de las piezas de revolución (1 mm de cuerda en el cuerpo)
COLA = 0.14  # x donde acaba el faldón de cola
JUNTAS = (2.9, 5.0)  # x de las juntas de sección
FRANJA = (6.55, 6.72)  # franja blanca
CUELLO = (6.84, 6.9)  # junta de acero antes de la ojiva
PUNTA = 8.0  # x donde empieza la punta negra
ALETA_SPAN = 0.335  # radio de la punta de las aletas
ALETA_RAIZ = (0.08, 1.02)  # cuerda en la raíz (x)
ALETA_PUNTA = (0.08, 0.42)  # cuerda en la punta (x)
ALETA_GROSOR = 0.026
ARGOLLAS = (2.2, 5.7)


def torno(S, nombre, perfil, material, uvCamuflaje=None):
    """Pieza de revolución alrededor de x con `perfil` [(x, r)]; un radio 0
    cierra en punta (o en tapa plana si la x se repite). Con `uvCamuflaje`
    (desfase en m), UV en metros / LADO_M: u = x, v = ángulo x R."""
    bm = bmesh.new()
    capa = bm.loops.layers.uv.verify()
    anillos = []
    for x, r in perfil:
        if r <= 1e-6:
            anillos.append([bm.verts.new((x, 0, 0))])
        else:
            anillos.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / LADOS), r * math.sin(2 * math.pi * k / LADOS))) for k in range(LADOS)])
    for a, b in zip(anillos, anillos[1:]):
        for k in range(LADOS):
            j = (k + 1) % LADOS
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[j], b[0]))
            else:
                bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if uvCamuflaje is not None:
        for cara in bm.faces:
            # Ángulo de cada vértice (los del eje, el medio de la cara); en
            # la costura (0 = 2π) los del principio pasan a 2π.
            angulos = []
            for bucle in cara.loops:
                p = bucle.vert.co
                angulos.append(None if p.y * p.y + p.z * p.z < 1e-12 else math.atan2(p.z, p.y) % (2 * math.pi))
            validos = [a for a in angulos if a is not None]
            if max(validos) - min(validos) > math.pi:
                angulos = [None if a is None else (a + 2 * math.pi if a < math.pi else a) for a in angulos]
                validos = [a for a in angulos if a is not None]
            medio = sum(validos) / len(validos)
            for bucle, angulo in zip(cara.loops, angulos):
                angulo = medio if angulo is None else angulo
                bucle[capa].uv = ((bucle.vert.co.x + uvCamuflaje) / LADO_M, angulo * R / LADO_M)
    objeto = S['objetoDe'](nombre, bm, material)
    S['suave'](objeto)
    return objeto


def ojiva(x0, x1, r0, pasos):
    """Perfil de ojiva tangente de x0 (radio r0) a x1 (punta)."""
    largo = x1 - x0
    rho = (r0 * r0 + largo * largo) / (2 * r0)
    puntos = []
    for i in range(pasos + 1):
        x = x0 + largo * i / pasos
        d = x1 - x
        r = math.sqrt(max(0.0, rho * rho - (largo - d) ** 2)) + r0 - rho
        puntos.append((x, max(0.0, r)))
    return puntos


def radioOjiva(x, x0, x1, r0):
    largo = x1 - x0
    rho = (r0 * r0 + largo * largo) / (2 * r0)
    d = x1 - x
    return math.sqrt(max(0.0, rho * rho - (largo - d) ** 2)) + r0 - rho


def aleta(S, nombre, angulo, material, desfase):
    """Aleta trapezoidal en el plano que pasa por el eje a `angulo`, de la
    raíz (dentro del cuerpo) a ALETA_SPAN, con los cantos biselados."""
    bm = bmesh.new()
    capa = bm.loops.layers.uv.verify()
    rRaiz = R - 0.02
    medio = ALETA_GROSOR / 2
    contorno = [(ALETA_RAIZ[0], rRaiz), (ALETA_RAIZ[1], rRaiz), (ALETA_PUNTA[1], ALETA_SPAN), (ALETA_PUNTA[0], ALETA_SPAN)]
    abajo = [bm.verts.new((x, r, -medio)) for x, r in contorno]
    arriba = [bm.verts.new((x, r, medio)) for x, r in contorno]
    bm.faces.new(list(reversed(abajo)))
    bm.faces.new(arriba)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((abajo[i], abajo[j], arriba[j], arriba[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Cantos biselados, menos el de la raíz (va dentro del cuerpo).
    bordes = [e for e in bm.edges if not all(abs(v.co.y - rRaiz) < 1e-6 for v in e.verts)]
    bmesh.ops.bevel(bm, geom=bordes, offset=0.008, segments=3, affect='EDGES', profile=0.5, clamp_overlap=True)
    for cara in bm.faces:
        for bucle in cara.loops:
            p = bucle.vert.co
            bucle[capa].uv = ((p.x + desfase) / LADO_M, (p.y + 2.0) / LADO_M)
    # Del plano xy (y = radio) a su ángulo alrededor de x.
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(angulo, 3, 'X'))
    objeto = S['objetoDe'](nombre, bm, material)
    S['suave'](objeto)
    return objeto


def argolla(S, nombre, x, material):
    """Argolla de izado arriba del cuerpo: base biselada y aro."""
    base = S['caja'](nombre + 'Base', (x, 0, R + 0.008), (0.12, 0.07, 0.03), material, 0.008)
    aro = S['aro'](nombre + 'Aro', (x, 0, R + 0.055), 0.022, 0.034, 0.016, material, lados=20, eje='y', bisel=0.004)
    return [base, aro]


def construirMisilCamion(S, m, desfase=0.0):
    piezas = []
    # Tobera (acero) y faldón de cola (negro).
    piezas.append(torno(S, 'misilTobera', [(-0.035, 0.0), (-0.035, 0.125), (-0.03, 0.14), (0.0, 0.15), (0.02, 0.15), (0.02, 0.0)], m['acero']))
    piezas.append(torno(S, 'misilTapa', [(-0.04, 0.0), (-0.04, 0.09), (-0.034, 0.096), (-0.034, 0.0)], m['negro']))
    piezas.append(torno(S, 'misilCola', [(0.0, 0.0), (0.0, 0.18), (0.006, 0.19), (0.12, 0.218), (COLA, R)], m['negro']))
    # Cuerpo de camuflaje, partido por las juntas (las juntas, de acero). Los
    # tramos van abiertos: sus bocas quedan bajo las juntas o siguen a la
    # pieza de al lado con el mismo radio.
    tramos = [COLA] + [v for j in JUNTAS for v in (j - 0.01, j + 0.01)] + [FRANJA[0] + 0.01]
    for i in range(0, len(tramos), 2):
        piezas.append(torno(S, 'misilCuerpo', [(tramos[i], R), (tramos[i + 1], R)], m['camuflaje'], desfase))
    for j in JUNTAS:
        piezas.append(torno(S, 'misilJunta', [(j - 0.022, 0.0), (j - 0.022, R - 0.004), (j - 0.018, R + 0.002), (j + 0.018, R + 0.002), (j + 0.022, R - 0.004), (j + 0.022, 0.0)], m['acero']))
    # Franja blanca algo levantada, tramo corto de camuflaje y junta de acero.
    piezas.append(torno(S, 'misilFranja', [(FRANJA[0], 0.0), (FRANJA[0], R - 0.002), (FRANJA[0] + 0.004, R + 0.0025), (FRANJA[1] - 0.004, R + 0.0025), (FRANJA[1], R - 0.002), (FRANJA[1], 0.0)], m['blanco']))
    piezas.append(torno(S, 'misilCuerpo', [(FRANJA[1] - 0.01, R), (CUELLO[0] + 0.01, R)], m['camuflaje'], desfase))
    piezas.append(torno(S, 'misilCuello', [(CUELLO[0], 0.0), (CUELLO[0], R - 0.003), (CUELLO[0] + 0.006, R + 0.003), (CUELLO[1] - 0.006, R + 0.003), (CUELLO[1], R - 0.003), (CUELLO[1], 0.0)], m['acero']))
    # Ojiva tangente hasta LARGO; de camuflaje hasta PUNTA, luego negra y
    # redondeada (una esfera tangente cierra la punta sin pico).
    perfil = ojiva(CUELLO[1], LARGO, R, 20)
    rPunta = radioOjiva(PUNTA, CUELLO[1], LARGO, R)
    camuflaje = [(CUELLO[1] - 0.01, R)] + [p for p in perfil if p[0] < PUNTA - 1e-6] + [(PUNTA, rPunta)]
    piezas.append(torno(S, 'misilOjiva', camuflaje, m['camuflaje'], desfase))
    # Punta: la ojiva hasta donde su radio es 2 cm y un casquete redondo.
    negra = [(PUNTA, rPunta)] + [p for p in perfil if PUNTA + 1e-6 < p[0] and p[1] > 0.03]
    xb, rb = negra[-1]
    hueco = LARGO - xb
    # Casquete (cuarto de elipse) de (xb, rb) a la punta en LARGO.
    for i in range(1, 7):
        a = math.pi / 2 * i / 6
        negra.append((xb + hueco * math.sin(a), rb * math.cos(a)))
    piezas.append(torno(S, 'misilPunta', negra, m['negro']))
    # Aletas en X y argollas.
    for k in range(4):
        piezas.append(aleta(S, 'misilAleta', math.radians(45 + 90 * k), m['camuflaje'], desfase))
    for x in ARGOLLAS:
        piezas.extend(argolla(S, 'misilArgolla', x, m['acero']))
    misil = S['unir'](piezas, 'misilCamion')
    return misil

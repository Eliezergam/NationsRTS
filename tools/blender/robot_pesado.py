# Robot pesado del almacén: el hermano grande del robot pequeño
# (robot_almacen.py), para lo que pesa demasiado para aquel: los contenedores
# de misil (9 m, varias toneladas) y los bidones de petróleo (180 kg).
# Humanoide de unos 3,2 m sobre una base de orugas, con dos brazos
# hidráulicos y mordazas de dos garras paralelas. Se corre sin ventana:
#
#     blender -b --factory-startup --python tools/blender/robot_pesado.py -- \
#         <salida.blend> [carpeta de renders]
#
# Referencias (2026-11-17): los vehículos omnidireccionales de carga de
# munición (patente US 6668950, hasta 3 200 kg), los brazos hidráulicos de
# carga pesada sobre plataforma móvil (Industrial Robot, 1998) y los robots
# de dos brazos sobre orugas para explosivos (FC-EODR). Familia visual del
# robot pequeño: blanco, plata y negro, la misma cabeza plana con dos ojos.
#
# Medidas en metros, z arriba, el frente hacia +x, el origen en el suelo bajo
# el centro de la base. Las orugas caben con holgura en los pasillos de 4 m
# del polvorín (2,75 m de ancho).
#
# Piezas que se mueven (origen en su eje, cuelgan de la anterior):
#   robot (base y orugas)
#     pierna                        se desplaza en z (columna telescópica:
#                                   sube el torso para llegar a lo alto)
#       torso                       gira en z (cintura)
#       cuello                      gira en z
#         cabeza                    gira en y
#           ojoIzq/Der, parpadoIzq/Der
#       hombroIzq/Der               gira en y
#         brazoIzq/Der              gira en x (abrir)
#           codoIzq/Der             gira en y
#             muniecaIzq/Der        gira en x
#               garra{Izq,Der}{A,B} giran en z sobre su pivote (abrir y cerrar)

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# Las mismas utilidades de geometría, materiales y luces que el robot
# pequeño (para que sean de la misma familia): se toman de su script.
_RUTA_PEQUENO = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'robot_almacen.py')
with open(_RUTA_PEQUENO, encoding='utf8') as _archivo:
    _fuente = _archivo.read()
_utilidades = _fuente[_fuente.index('def argumentos():'):_fuente.index('# El robot ---')]
_render = _fuente[_fuente.index('def prepararRender():'):_fuente.index('def renderizar(carpeta):')]
_exportar = _fuente[_fuente.index('def exportarJuego(ruta):'):_fuente.index('def principal():')]
exec(_utilidades + _render + _exportar)

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
# Orugas y chasis.
ORUGA_LARGO = 3.2
ORUGA_ANCHO = 0.55
ORUGA_ALTO = 0.75
ORUGA_Y = 1.1
CHASIS = (2.8, 1.62, 0.62)  # largo, ancho, alto
CHASIS_Z = 0.28  # hueco bajo el chasis
PIERNA = 0.55  # columna telescópica entre la base y la cintura (sube el torso)
PIERNA_SUBE, PIERNA_BAJA = 0.6, 0.45  # lo que la sube y la baja el juego (brazosPesado.lua: piernaMax, -piernaMin)
CINTURA_Z = CHASIS_Z + CHASIS[2] + 0.12 + PIERNA
# Torso, cabeza y brazos (en la pose de trabajo: brazos adelante).
PECHO = (1.15, 1.9, 0.95)
PECHO_Z = CINTURA_Z + 0.55
HOMBRO_Y = 1.1
HOMBRO_Z = PECHO_Z + 0.35
CODO = (0.3, 1.45)  # x, z
MUNIECA = (1.35, 1.45)
LARGO_CUELLO = 0.32


ESLABON_PASO = 0.12  # m entre ejes de las tejas de la oruga


def caminoOruga(xPunta, radio, s):
    """Punto (x, z) y ángulo de la tangente a `s` metros a lo largo del
    camino de la oruga (recta de abajo, vuelta delantera, recta de arriba,
    vuelta trasera), con el eje de las ruedas a la altura `radio`."""
    recta = 2 * xPunta
    curva = math.pi * radio
    total = 2 * recta + 2 * curva
    s = s % total
    if s < recta:
        return (-xPunta + s, 0.0, 0.0)
    s -= recta
    if s < curva:
        a = -math.pi / 2 + s / radio
        return (xPunta + radio * math.cos(a), radio + radio * math.sin(a), a + math.pi / 2)
    s -= curva
    if s < recta:
        return (xPunta - s, 2 * radio, math.pi)
    s -= recta
    a = math.pi / 2 + s / radio
    return (-xPunta + radio * math.cos(a), radio + radio * math.sin(a), a + math.pi / 2)


def crearOruga(m, lado):
    """Oruga de eslabones de acero con teja de goma (cada eslabón con su
    nervio y sus dos pasadores), rueda dentada motriz detrás, rueda tensora
    delante, cinco rodillos de apoyo con sus tuercas, bastidor con los
    soportes y guardabarros blanco con remaches."""
    y = lado * ORUGA_Y
    r = ORUGA_ALTO / 2
    xPunta = ORUGA_LARGO / 2 - r
    radioCamino = r - 0.035
    p = []
    total = 4 * xPunta + 2 * math.pi * radioCamino
    n = int(total / ESLABON_PASO)
    paso = total / n
    sufijo = 'Izq' if lado > 0 else 'Der'
    # Lo que se mueve: cada teja (el juego la lleva por el camino de la
    # oruga) y cada rueda (gira en y). (nombre, piezas, pivote, giro en y).
    moviles = []
    ORUGA_DATOS.update(n=n, paso=paso, xPunta=xPunta, radio=radioCamino, alto=0.035)
    ORUGA_DATOS.setdefault('y', {})[sufijo] = y
    for k in range(n):
        x, zc, ang = caminoOruga(xPunta, radioCamino, k * paso)
        z = zc + 0.035
        piezas = [
            caja('eslabon', (0, 0, 0), (paso * 0.82, ORUGA_ANCHO, 0.045), m['acero'], 0.008),
            caja('teja', (0, 0, -0.04), (paso * 0.7, ORUGA_ANCHO - 0.04, 0.035), m['goma'], 0.01),
            caja('nervio', (0, 0, -0.065), (0.03, ORUGA_ANCHO - 0.08, 0.02), m['goma'], 0.006),
            cilindro('pasador', (paso * 0.45, 0, 0.0), 0.016, ORUGA_ANCHO + 0.03, m['acero'], eje='y', lados=24),
            caja('guia', (0, 0, 0.04), (paso * 0.5, 0.05, 0.05), m['acero'], 0.008),
        ]
        giro = Matrix.Rotation(-ang, 4, 'Y')
        for o in piezas:
            o.data.transform(Matrix.Translation((x, y, z)) @ giro)
        moviles.append(('teja%s%02d' % (sufijo, k), piezas, (x, y, z), -ang))
    # Rueda motriz dentada (detrás) y tensora (delante).
    for x, dentada in ((-xPunta, True), (xPunta, False)):
        q = p
        p = []
        rr = radioCamino - 0.03
        ORUGA_DATOS['radioRueda'] = rr
        p.append(cilindro('rueda', (x, y, r), rr, ORUGA_ANCHO * 0.35, m['negro'], eje='y', lados=128, bisel=0.012))
        for sy in (-1, 1):
            p.append(cilindro('aroRueda', (x, y + sy * ORUGA_ANCHO * 0.2, r), rr + 0.005, 0.03, m['acero'], eje='y', lados=128, bisel=0.006))
        if dentada:
            for k in range(14):
                a = k * 2 * math.pi / 14
                diente = caja('diente', (0, 0, 0), (0.05, 0.05, 0.07), m['acero'], 0.008)
                diente.data.transform(Matrix.Translation((x + math.cos(a) * rr, y, r + math.sin(a) * rr)) @ Matrix.Rotation(-a + math.pi / 2, 4, 'Y'))
                p.append(diente)
        cara = y + lado * (ORUGA_ANCHO * 0.175 + 0.01)
        # Aligeramientos: seis agujeros (fondo negro y aro de acero).
        for k in range(6):
            a = k * math.pi / 3 + math.pi / 6
            hx, hz = x + math.cos(a) * 0.2, r + math.sin(a) * 0.2
            p.append(cilindro('agujero', (hx, cara - lado * 0.004, hz), 0.055, 0.012, m['negroMate'], eje='y', lados=48))
            p.append(cilindro('aroAgujero', (hx, cara - lado * 0.006, hz), 0.062, 0.006, m['acero'], eje='y', lados=48, bisel=0.002))
        p.append(cilindro('cubo', (x, cara, r), 0.13, 0.04, m['gris'], eje='y', lados=64, bisel=0.01))
        for k in range(8):
            a = k * math.pi / 4
            p += perno('tuercaRueda', (x + math.cos(a) * 0.095, cara + lado * 0.02, r + math.sin(a) * 0.095), (0, lado, 0), m, 0.014, material='acero')
        moviles.append((('ruedaMotriz' if dentada else 'ruedaTensora') + sufijo, p, (x, y, r), 0))
        p = q
    # Rodillos de apoyo, con su soporte al bastidor.
    p.append(caja('bastidor', (0, y, r), (2 * xPunta - 0.3, 0.16, 0.24), m['negro'], 0.03))
    for k in range(5):
        x = -xPunta + 0.42 + k * (2 * xPunta - 0.84) / 4
        rodillo = [cilindro('rodillo', (x, y, 0.16), 0.115, ORUGA_ANCHO * 0.3, m['negro'], eje='y', lados=96, bisel=0.012)]
        ORUGA_DATOS['radioRodillo'] = 0.115
        p.append(caja('soporteRodillo', (x, y, 0.26), (0.08, 0.12, 0.16), m['negro'], 0.015))
        cara = y + lado * (ORUGA_ANCHO * 0.15 + 0.005)
        rodillo.append(cilindro('tapaRodillo', (x, cara, 0.16), 0.06, 0.02, m['acero'], eje='y', lados=48, bisel=0.004))
        rodillo += perno('tuercaRodillo', (x, cara + lado * 0.01, 0.16), (0, lado, 0), m, 0.018, material='acero')
        moviles.append(('rodillo%s%d' % (sufijo, k + 1), rodillo, (x, y, 0.16), 0))
    # Guardabarros con su faldón y remaches.
    zg = ORUGA_ALTO + 0.1
    p.append(caja('guardabarros', (0, y, zg), (ORUGA_LARGO + 0.05, ORUGA_ANCHO + 0.08, 0.035), m['blanco'], 0.012))
    yf = y + lado * (ORUGA_ANCHO / 2 + 0.04)
    p.append(caja('faldon', (0, yf, zg - 0.07), (ORUGA_LARGO, 0.012, 0.14), m['blanco'], 0.004))
    p.append(caja('franjaFaldon', (0, yf + lado * 0.007, zg - 0.07), (ORUGA_LARGO - 0.1, 0.004, 0.03), m['negro']))
    p += filaRemaches((-ORUGA_LARGO / 2 + 0.06, yf + lado * 0.007, zg - 0.115), (ORUGA_LARGO / 2 - 0.06, yf + lado * 0.007, zg - 0.115), 24, (0, lado, 0), m, 0.008)
    p += filaRemaches((-ORUGA_LARGO / 2 + 0.06, yf + lado * 0.007, zg - 0.025), (ORUGA_LARGO / 2 - 0.06, yf + lado * 0.007, zg - 0.025), 24, (0, lado, 0), m, 0.008)
    return p, moviles


# Camino de la oruga para el juego (assets/almacen/robot_pesado_oruga.lua).
ORUGA_DATOS = {}


def piezaGirada(nombre, piezas, pivote, giroY, padre):
    """Como `pieza`, con los ejes locales girados `giroY` en y (las tejas:
    su malla queda recta en sus ejes; el juego la coloca en el camino)."""
    objeto = unir(piezas, nombre)
    M = Matrix.Translation(Vector(pivote)) @ Matrix.Rotation(giroY, 4, 'Y')
    objeto.data.transform(M.inverted())
    objeto.matrix_world = M
    objeto.parent = padre
    objeto.matrix_parent_inverse = padre.matrix_world.inverted()
    return objeto


def crearBase(m):
    cx, cy, cz = CHASIS
    z0 = CHASIS_Z
    pIzq, movIzq = crearOruga(m, 1)
    pDer, movDer = crearOruga(m, -1)
    p = pIzq + pDer
    p += [
        caja('chasis', (0, 0, z0 + cz / 2), (cx, cy, cz), m['negro'], 0.08),
        caja('chasisTapa', (0, 0, z0 + cz - 0.03), (cx - 0.1, cy - 0.06, 0.08), m['blanco'], 0.04),
        cilindro('asientoCintura', (0, 0, z0 + cz + 0.06), 0.62, 0.12, m['articulacion'], bisel=0.02),
        cilindro('lidar', (cx / 2 + 0.01, 0, z0 + cz * 0.45), 0.07, 0.07, m['visor'], eje='x', bisel=0.01),
    ]
    # Franjas de peligro delante y detrás, y balizas naranjas en las esquinas.
    for sx in (-1, 1):
        for k in range(8):
            y = -cy / 2 + 0.12 + k * (cy - 0.24) / 7
            mat = m['amarillo'] if k % 2 == 0 else m['negro']
            p.append(caja('franja', (sx * (cx / 2 + 0.005), y, z0 + 0.16), (0.012, (cy - 0.24) / 7, 0.14), mat))
        for sy in (-1, 1):
            p.append(cilindro('baliza', (sx * (cx / 2 - 0.15), sy * (cy / 2 - 0.12), z0 + cz + 0.07), 0.05, 0.12, m['baliza'], lados=20))
    for sy in (-1, 1):
        p.append(cilindro('piloto', (cx / 2 + 0.005, sy * 0.4, z0 + cz * 0.45), 0.03, 0.02, m['piloto'], eje='x'))
    # Paneles del chasis: juntas verticales, remaches en los bordes de la
    # tapa y tapas de registro atornilladas en los costados.
    zt = z0 + cz
    for sy in (-1, 1):
        ys = sy * (cy / 2 + 0.003)
        for x in (-0.7, 0.0, 0.7):
            p.append(junta((x, ys, z0 + cz / 2), (0.012, 0.006, cz - 0.16), m))
        for x0, x1 in ((-1.3, -0.75), (-0.65, -0.05), (0.05, 0.65), (0.75, 1.3)):
            p.append(caja('registro', ((x0 + x1) / 2, ys + sy * 0.006, z0 + cz * 0.5), (x1 - x0 - 0.06, 0.012, 0.26), m['negro'], 0.006))
            for bx in (x0 + 0.06, x1 - 0.06):
                for bz in (z0 + cz * 0.5 - 0.1, z0 + cz * 0.5 + 0.1):
                    p += perno('pernoRegistro', (bx, ys + sy * 0.012, bz), (0, sy, 0), m, 0.011, material='acero')
        p += filaRemaches((-cx / 2 + 0.1, sy * (cy / 2 - 0.05), zt + 0.012), (cx / 2 - 0.1, sy * (cy / 2 - 0.05), zt + 0.012), 22, (0, 0, 1), m, 0.009)
    for sx in (-1, 1):
        p += filaRemaches((sx * (cx / 2 - 0.08), -cy / 2 + 0.12, zt + 0.012), (sx * (cx / 2 - 0.08), cy / 2 - 0.12, zt + 0.012), 12, (0, 0, 1), m, 0.009)
    # Corona de pernos del asiento de la cintura.
    for k in range(24):
        a = k * 2 * math.pi / 24
        p += perno('pernoCorona', (math.cos(a) * 0.56, math.sin(a) * 0.56, zt + 0.12), (0, 0, 1), m, 0.016, material='acero')
    # Cáncamos de izado en las cuatro esquinas.
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cilindro('cancamo', (sx * (cx / 2 - 0.3), sy * (cy / 2 - 0.28), zt + 0.07), 0.045, 0.02, m['amarillo'], eje='x', lados=32, bisel=0.008))
            p.append(caja('baseCancamo', (sx * (cx / 2 - 0.3), sy * (cy / 2 - 0.28), zt + 0.02), (0.08, 0.06, 0.03), m['amarillo'], 0.006))
    base = pieza('robot', p, (0, 0, 0))
    for nombre, piezas, pivote, giroY in movIzq + movDer:
        piezaGirada(nombre, piezas, pivote, giroY, base)
    return base


def crearPierna(m, padre):
    """Columna telescópica de la base a la cintura, de verdad telescópica
    (el juego la sube hasta PIERNA_SUBE y la baja hasta PIERNA_BAJA):
      - piernaFija: los collares de la corona por donde salen los tramos;
        no se mueven;
      - piernaMedia: el tramo de abajo (blanco y ancho) y las camisas de los
        dos cilindros hidráulicos; sale la mitad que la pierna y por debajo
        sigue escondido dentro del chasis;
      - pierna: el tramo de arriba (plateado) y los vástagos; sale entero y
        por debajo sigue escondido dentro del tramo de abajo y de las
        camisas: nunca se ve un hueco."""
    z0 = CHASIS_Z + CHASIS[2] + 0.12
    sube, baja = PIERNA_SUBE, PIERNA_BAJA
    # Tramo de abajo: su borde queda bajo la cintura aun con la pierna abajo
    # del todo; por debajo, escondido en el chasis lo que haga falta.
    arribaBajo = z0 + PIERNA - baja * 0.5 - 0.06
    abajoBajo = z0 - sube * 0.5 - 0.08
    media = [
        cilindro('tramoBajo', (0, 0, (arribaBajo + abajoBajo) / 2), 0.4, arribaBajo - abajoBajo, m['blanco'], bisel=0.05),
        cilindro('anilloTramo', (0, 0, arribaBajo - 0.025), 0.42, 0.05, m['negro'], bisel=0.015),
    ]
    # Tramo de arriba: dentro del de abajo aun con la pierna arriba del todo.
    arribaAlto = z0 + PIERNA
    abajoAlto = arribaBajo - sube * 0.5 - 0.12
    alta = [cilindro('tramoAlto', (0, 0, (arribaAlto + abajoAlto) / 2), 0.32, arribaAlto - abajoAlto, m['plata'], bisel=0.03)]
    fija = [cilindro('collarPierna', (0, 0, z0 + 0.02), 0.46, 0.04, m['negro'], bisel=0.012)]
    # Cilindros hidráulicos rectos a los lados: la camisa sale con el tramo
    # de abajo y el vástago, que llega a la cintura, sale de ella.
    for sy in (-1, 1):
        y = sy * 0.56
        abajoCamisa = z0 - sube * 0.5 - 0.06
        media += [
            cilindro('cilindroPiernaCamisa', (0, y, (arribaBajo + abajoCamisa) / 2), 0.085, arribaBajo - abajoCamisa, m['negro'], bisel=0.02),
            cilindro('cilindroPiernaTapa', (0, y, arribaBajo - 0.015), 0.095, 0.03, m['negro'], bisel=0.008),
        ]
        abajoVastago = arribaBajo - sube * 0.5 - 0.1
        alta += [
            cilindro('cilindroPiernaVastago', (0, y, (arribaAlto + abajoVastago) / 2), 0.04, arribaAlto - abajoVastago, m['plata'], bisel=0.01),
            esfera('cilindroPiernaRotula', (0, y, arribaAlto - 0.02), 0.06, m['articulacion']),
        ]
        fija.append(cilindro('collarCamisa', (0, y, z0 + 0.02), 0.11, 0.04, m['negro'], bisel=0.01))
    pieza('piernaFija', fija, (0, 0, z0), padre)
    pieza('piernaMedia', media, (0, 0, z0), padre)
    return pieza('pierna', alta, (0, 0, z0), padre)


def crearTorso(m, padre):
    """Cintura giratoria, vientre negro, pecho blanco con placa de peligro y
    la central hidráulica detrás (con su rejilla)."""
    z0 = CINTURA_Z
    fx, fy, fz = PECHO
    zc = PECHO_Z
    p = [
        cilindro('cintura', (0, 0, z0 + 0.1), 0.45, 0.2, m['articulacion'], bisel=0.03),
        caja('vientre', (0, 0, z0 + 0.32), (0.9, 1.25, 0.3), m['negro'], 0.1),
        caja('pecho', (0, 0, zc + 0.05), (fx, fy, fz - 0.15), m['blanco'], 0.18),
        caja('pechoBajo', (0, 0, zc - 0.36), (fx - 0.06, fy - 0.12, 0.22), m['negro'], 0.08),
        caja('placaPecho', (fx / 2 + 0.005, 0, PLACA_Z), (0.02, 0.5, 0.1), m['gris'], 0.02),
        caja('mochila', (-fx / 2 - 0.2, 0, zc), (0.42, 1.3, 0.8), m['negro'], 0.08),
        caja('cuelloBase', (0, 0, zc + fz / 2 - 0.04), (0.32, 0.36, 0.1), m['negro'], 0.04),
    ]
    for k in range(5):
        p.append(caja('rejilla', (-fx / 2 - 0.415, 0, zc - 0.22 + k * 0.11), (0.012, 1.0, 0.04), m['negroMate'], 0.005))
    # Juntas de los paneles del pecho y remaches alrededor de la placa.
    for y in (-0.55, 0.55):
        p.append(junta((fx / 2 + 0.002, y, zc + 0.05), (0.006, 0.012, fz - 0.35), m))
    p.append(junta((fx / 2 + 0.002, 0, zc - 0.2), (0.006, fy - 0.4, 0.012), m))
    for zr in (PLACA_Z - 0.065, PLACA_Z + 0.065):
        p += filaRemaches((fx / 2 + 0.012, -0.28, zr), (fx / 2 + 0.012, 0.28, zr), 8, (1, 0, 0), m)
    for sy in (-1, 1):
        # Pernos de la tapa lateral del pecho (donde va el hombro).
        for k in range(8):
            a = k * math.pi / 4
            p += perno('pernoTapa', (math.cos(a) * 0.2, sy * (fy / 2 + 0.005), zc + 0.35 + math.sin(a) * 0.2 - 0.0), (0, sy, 0), m, 0.016, material='acero')
        # Mangueras de la central hidráulica a cada hombro.
        for dz in (-0.05, 0.07):
            p.append(manguera('manguera', [(-fx / 2 - 0.15, sy * 0.55, zc + 0.25 + dz), (-fx / 2 - 0.05, sy * 0.85, zc + 0.5 + dz), (-0.25, sy * (fy / 2 + 0.06), zc + 0.45 + dz), (-0.05, sy * (fy / 2 + 0.12), zc + 0.38 + dz)], 0.022, m['negroMate']))
    for k in range(5):
        y = -0.2 + k * 0.1
        p.append(caja('chevron', (fx / 2 + 0.017, y, PLACA_Z), (0.006, 0.05, 0.07), m['amarillo'] if k % 2 == 0 else m['negro']))
    torso = pieza('torso', p, (0, 0, z0), padre)
    engranajePecho(m, torso)
    # Siglas de la nación, entre el engranaje y la junta del panel.
    placaSiglas((fx / 2 + 0.003, 0.385, ENGRANAJE_Z), 0.27, 0.09, torso, m)
    return torso


# Engranaje del pecho (el dueño, 17-nov: «el mismo engranaje que tiene en las
# orejas el robot pequeño pero en el pecho, más grande»): los tres anillos
# dentados de los oídos (robot_soldado.py `oido`) a ENGRANAJE_ESCALA, en el
# centro del pecho mirando adelante. Piezas `engranajePecho` (la carcasa) y
# `engranajePechoA/B/C` (giran en x, como los oídos en y).
ENGRANAJE_ESCALA = 5.0  # 0,41 m de diámetro: cabe en lo plano del pecho (el bisel empieza 0,18 antes del borde)
ENGRANAJE_Z = PECHO_Z + 0.05
PLACA_Z = PECHO_Z - 0.28  # la placa de peligro, debajo del engranaje


def piezasSoldado():
    """robot_soldado.py cargado aparte (ojos, oídos…), una vez."""
    if 'soldado' not in _SOLDADO:
        ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.expanduser('~/NationsRTS/tools/blender'), 'robot_soldado.py')
        soldado = {'__name__': 'piezasSoldado', '__file__': ruta}
        with open(ruta, encoding='utf8') as archivo:
            exec(archivo.read(), soldado)
        _SOLDADO['soldado'] = soldado
    return _SOLDADO['soldado']


_SOLDADO = {}


def engranajePecho(m, torso):
    soldado = piezasSoldado()
    centro = (PECHO[0] / 2 - 0.012, 0.0, ENGRANAJE_Z)
    lleva = Matrix.Translation(centro) @ Matrix.Scale(ENGRANAJE_ESCALA, 4)
    soldado['oido'](m, 0, 0, 1, '', torso, lleva=lleva, nombre='engranajePecho')


def crearCabeza(m, padre):
    """La cabeza del robot pequeño a casi tres veces su tamaño: plana y
    negra. Los ojos (el dueño, 17-nov: «los mismos ojos del robot pequeño,
    solo los ojos») son los del robot pequeño y el soldado
    (robot_soldado.py): bola que gira con el diafragma en punta, aro de
    cobre, núcleo cian y persianas de láminas; piezas globo{S},
    persianaSup/Inf{S}{k}, hoja{S}NN..."""
    z0 = PECHO_Z + PECHO[2] / 2 + 0.01
    cuello = pieza('cuello', [
        cilindro('cuello', (0, 0, z0 + LARGO_CUELLO / 2), 0.09, LARGO_CUELLO, m['articulacion'], bisel=0.015),
        cilindro('anilloCuello', (0, 0, z0 + LARGO_CUELLO * 0.3), 0.11, 0.04, m['gris'], bisel=0.01),
        cilindro('anilloCuello', (0, 0, z0 + LARGO_CUELLO * 0.7), 0.11, 0.04, m['gris'], bisel=0.01),
    ], (0, 0, z0), padre)
    e = 2.8
    zc = z0 + LARGO_CUELLO + 0.045 * e
    xf = 0.085 * e
    p = [
        caja('cabeza', (0, 0, zc), (0.17 * e, 0.28 * e, 0.11 * e), m['negro'], 0.03 * e),
        caja('ventilacion', (-xf + 0.01, 0, zc), (0.016, 0.16 * e, 0.04 * e), m['negroMate'], 0.006),
    ]
    soldado = piezasSoldado()
    soldado['OJO_ESCALA'] = e  # globoOjo lee la escala de ahí
    for lado in (-1, 1):
        p += soldado['cuencaPersiana'](m, xf, lado * 0.075 * e, zc, e)
    p += frenteCabeza(m, xf, zc, e)
    for sy in (-1, 1):
        for sz in (-1, 1):
            p += perno('tornilloCabeza', (xf + 0.002, sy * 0.122 * e, zc + sz * 0.038 * e), (1, 0, 0), m, 0.01, hexagonal=False, material='acero')
    cabeza = pieza('cabeza', p, (0, 0, zc - 0.03 * e), cuello)
    for lado, s in ((1, 'Izq'), (-1, 'Der')):
        soldado['globoOjo'](m, xf, lado * 0.075 * e, zc, s, cabeza)
        # Las persianas tapan el ojo entero (los párpados de media luna no).
        for n in ('parpadoSup', 'parpadoInf'):
            viejo = bpy.data.objects.get(n + s)
            if viejo:
                bpy.data.objects.remove(viejo, do_unlink=True)
        soldado['persianas'](m, xf, lado * 0.075 * e, zc, e, s, cabeza)
    return cabeza


def hidraulico(nombre, a, b, m, radio=0.07):
    """Cilindro hidráulico de `a` a `b`: camisa negra con su tapa y vástago
    de acero brillante que sale de ella."""
    a, b = Vector(a), Vector(b)
    medio = a + (b - a) * 0.55
    return [
        segmento(nombre + 'Camisa', a, medio, radio * 2, radio * 2, m['negro'], radio * 0.8),
        segmento(nombre + 'Vastago', medio, b, radio, radio, m['plata'], radio * 0.45),
        esfera(nombre + 'Rotula', tuple(b), radio * 0.8, m['articulacion']),
        esfera(nombre + 'RotulaA', tuple(a), radio * 0.9, m['articulacion']),
    ]


# Garra (la foto del dueño del 2026-11-17): dos uñas curvas de placa negra
# con dientes de sierra por dentro, entre dos placas de base, con pernos de
# latón en los pivotes y eslabones que las cierran desde un cilindro central.
# A este tamaño abraza un bidón (Ø 0,58 m) y abierta coge un contenedor de
# misil (0,85 m). Ejes de la mano: x hacia la punta, y hacia la uña A, z
# arriba; las uñas (`garra{Izq,Der}{A,B}`) giran en z sobre su pivote.
GARRA_PIVOTE = (0.3, 0.17)  # x, |y| del pivote de cada uña desde la muñeca
GARRA_CENTRO = (0.42, -0.17)  # centro del arco de dentro, desde el pivote
GARRA_RADIO = 0.33
GARRA_AGARRE = 0.68  # m de la muñeca al centro de lo que coge la garra
GARRA_ABIERTA = math.radians(28)  # cuánto está abierta en la pose del modelo


def contornoUna():
    """Contorno de la uña A (la de +y) con el pivote en el origen: talón con
    el ojo del eslabón detrás, arco de dentro con 7 dientes de sierra que
    miran hacia la muñeca, punta afilada y lomo curvo por fuera."""
    cx, cy = GARRA_CENTRO
    r = GARRA_RADIO
    p = [(-0.15, 0.09), (-0.17, 0.02), (-0.13, -0.05), (-0.02, -0.06)]
    a0, a1 = math.radians(132), math.radians(8)
    dientes = 9
    # Arco de dentro con dientes (de la base hacia la punta).
    pasos = dientes * 2
    for k in range(pasos + 1):
        a = a0 + (a1 - a0) * k / pasos
        if 0 < k < pasos and k % 2 == 1:
            # Punta del diente: hacia dentro y adelantada hacia la base.
            a = a0 + (a1 - a0) * (k - 0.6) / pasos
            rr = r - 0.05
        else:
            rr = r
        p.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    # Punta y lomo de fuera (radio que crece hacia el talón).
    p.append((cx + (r + 0.04) * math.cos(math.radians(-2)), cy + (r + 0.04) * math.sin(math.radians(-2))))
    for k in range(1, 15):
        f = k / 14
        a = math.radians(5) + (math.radians(128) - math.radians(5)) * f
        rr = r + 0.07 + 0.13 * f
        p.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    p += [(0.0, 0.17), (-0.09, 0.15)]
    return p


def crearGarra(m, sufijo, lado, munieca, padre):
    x, y, z = munieca
    px, py = GARRA_PIVOTE
    # Placa de base: arriba y abajo (las uñas van en medio), con el cilindro
    # que las cierra y sus eslabones.
    base = [(-0.12, 0.13), (0.1, 0.27), (px + 0.1, py + 0.08), (px + 0.14, 0.0), (px + 0.1, -py - 0.08), (0.1, -0.27), (-0.12, -0.13)]
    p = [cilindro('muniecaEje', (x, y, z), 0.13, 0.14, m['articulacion'], eje='x', lados=64, bisel=0.02)]
    for zz in (0.075, -0.075):
        placa = perfilExtruido('placaBase', base, 0.03, m['garra'], 0.006, z=zz)
        placa.data.transform(Matrix.Translation((x, y, z)))
        p.append(placa)
        # Pernos de latón: pivotes, separadores y esquinas.
        for bx, by in ((px, py), (px, -py), (0.0, 0.18), (0.0, -0.18), (-0.08, 0.0), (0.2, 0.0), (px + 0.08, 0.0)):
            p += perno('perno', (x + bx, y + by, z + zz + math.copysign(0.015, zz)), (0, 0, math.copysign(1, zz)), m, 0.02 if (bx, abs(by)) == (px, py) else 0.014)
    for bx, by in ((0.0, 0.18), (0.0, -0.18), (-0.08, 0.0), (px + 0.08, 0.0)):
        p.append(cilindro('separador', (x + bx, y + by, z), 0.022, 0.12, m['acero'], lados=32))
    # Cilindro de cierre (a lo largo de x, en medio de las placas).
    p.append(cilindro('cilindroCierre', (x + 0.02, y, z), 0.045, 0.2, m['negro'], eje='x', lados=48, bisel=0.01))
    p.append(cilindro('vastagoCierre', (x + 0.15, y, z), 0.02, 0.1, m['plata'], eje='x', lados=32))
    p.append(caja('cruceta', (x + 0.2, y, z), (0.05, 0.1, 0.07), m['acero'], 0.01))
    palma = pieza('munieca' + sufijo, p, (x, y, z), padre)
    contorno = contornoUna()
    for letra, sy in (('A', 1), ('B', -1)):
        puntos = [(cx, sy * cy) for cx, cy in contorno]
        if sy < 0:
            puntos.reverse()
        una = perfilExtruido('una', puntos, 0.09, m['garra'], 0.01)
        piezasUna = [una]
        # Pernos de latón en la cara de arriba de la uña, como en la foto.
        for bx, by in ((0.25, 0.1), (0.45, 0.2), (0.62, 0.13)):
            piezasUna += perno('pernoUna', (bx, sy * by, 0.046), (0, 0, 1), m, 0.013, hexagonal=False)
        # Casquillo del pivote y ojo del eslabón en el talón.
        piezasUna.append(cilindro('casquillo', (0, 0, 0), 0.05, 0.1, m['acero'], lados=48, bisel=0.006))
        piezasUna.append(cilindro('ojoEslabon', (-0.12, sy * 0.03, 0), 0.025, 0.1, m['laton'], lados=32))
        # Eslabón al cilindro de cierre (de la cruceta al talón).
        piezasUna.append(segmento('eslabon', (-0.12, sy * 0.03, 0.06), (0.2 - px - 0.0, sy * (0.04 - py) , 0.06), 0.035, 0.018, m['acero'], 0.006))
        giro = Matrix.Rotation(sy * GARRA_ABIERTA, 4, 'Z')
        sitio = Matrix.Translation((x + px, y + sy * py, z))
        for o in piezasUna:
            o.data.transform(sitio @ giro)
        pieza('garra' + sufijo + letra, piezasUna, (x + px, y + sy * py, z), palma)
    # Punto de agarre: el centro de las dos uñas cerradas (donde queda lo
    # que coge; el juego cuelga ahí el objeto).
    agarre = bpy.data.objects.new('agarre' + sufijo, None)
    bpy.context.scene.collection.objects.link(agarre)
    agarre.location = (x + GARRA_AGARRE, y, z)
    agarre.parent = palma
    agarre.matrix_parent_inverse = palma.matrix_world.inverted()
    return palma


def crearBrazo(m, lado, padre):
    sufijo = 'Izq' if lado > 0 else 'Der'
    y0 = lado * HOMBRO_Y
    z0 = HOMBRO_Z
    hombro = pieza('hombro' + sufijo, [
        esfera('hombro', (0, y0 + lado * 0.03, z0), 0.25, m['negro'], (1.0, 0.95, 0.9)),
        cilindro('ejeHombro', (0, y0 - lado * 0.2, z0), 0.19, 0.12, m['articulacion'], eje='y'),
    ], (0, y0, z0), padre)
    yb = y0 + lado * 0.12
    codo = Vector((CODO[0], yb, CODO[1]))
    hombroV = Vector((0, yb, z0))
    p = [
        segmento('brazoSuperior', hombroV + Vector((0, 0, -0.12)), codo, 0.26, 0.28, m['plata'], 0.1),
        segmento('brazoFranja', hombroV + Vector((0, 0, -0.2)), codo + Vector((0, 0, 0.22)), 0.27, 0.1, m['blanco'], 0.03),
        cilindro('codo', tuple(codo), 0.17, 0.32, m['articulacion'], eje='y', bisel=0.025),
    ]
    # Cilindro hidráulico por delante del brazo, del hombro al antebrazo.
    p += hidraulico('cilindroBrazo', (0.2, yb, z0 - 0.15), (codo.x + 0.22, yb, codo.z + 0.12), m)
    for k in range(10):
        a = k * 2 * math.pi / 10
        p += perno('pernoCodo', (codo.x + math.cos(a) * 0.12, yb + lado * 0.165, codo.z + math.sin(a) * 0.12), (0, lado, 0), m, 0.014, material='acero')
    p.append(manguera('mangueraBrazo', [(0.1, yb + lado * 0.16, z0 - 0.05), (0.2, yb + lado * 0.18, (z0 + codo.z) / 2), (codo.x + 0.1, yb + lado * 0.17, codo.z + 0.2)], 0.018, m['negroMate']))
    p += filaRemaches(hombroV + Vector((0.14, lado * 0.142, -0.3)), codo + Vector((-0.05, lado * 0.142, 0.3)), 6, (0, lado, 0), m)
    brazo = pieza('brazo' + sufijo, p, (0, yb, z0), hombro)
    munieca = Vector((MUNIECA[0], yb, MUNIECA[1]))
    p = [
        segmento('antebrazo', codo, munieca, 0.24, 0.24, m['negro'], 0.09, -0.02),
        segmento('antebrazoTapa', codo + Vector((0, lado * 0.123, 0)), munieca + Vector((0, lado * 0.123, 0)), 0.02, 0.14, m['gris'], 0.006, -0.12),
    ]
    p += hidraulico('cilindroMunieca', (codo.x + 0.15, yb, codo.z + 0.17), (munieca.x - 0.12, yb, munieca.z + 0.16), m, 0.05)
    antebrazo = pieza('codo' + sufijo, p, tuple(codo), brazo)
    crearGarra(m, sufijo, lado, tuple(munieca), antebrazo)
    return hombro


def crearRobot():
    m = crearMateriales()
    m['amarillo'] = materialLiso('robotAmarillo', (0.95, 0.68, 0.02), 0.4, 0.1)
    m['baliza'] = materialLiso('robotBaliza', (1.0, 0.45, 0.02), 0.3, 0.0, 6.0)
    m['garra'] = materialLiso('robotGarra', (0.02, 0.02, 0.022), 0.5, 0.2)
    materialesReales(m)
    base = crearBase(m)
    pierna = crearPierna(m, base)
    torso = crearTorso(m, pierna)
    crearCabeza(m, torso)
    crearBrazo(m, 1, torso)
    crearBrazo(m, -1, torso)
    placaSombra(4.2, 3.6, base, m)  # orugas: 3,3 x 2,75 m, con el borde difuso
    return base


def ponerReferencias():
    """Para comparar tamaños: el robot pequeño (su .glb del juego), un bidón
    de petróleo y un contenedor de misil de 9 m."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAIZ, 'assets', 'almacen', 'robot.glb'))
    pequeno = [o for o in bpy.data.objects if o not in antes and o.parent is None]
    # En el .glb cada pieza está en su propio origen: se colocan con las
    # matrices de robot_piezas.lua (cada una relativa a su padre).
    import re
    piezas = {}
    with open(os.path.join(RAIZ, 'assets', 'almacen', 'robot_piezas.lua'), encoding='utf8') as archivo:
        for linea in archivo:
            r = re.search(r"nombre = '(\w+)'(?:, padre = '(\w+)')?.*matriz = \{([^}]*)\}", linea)
            if r:
                v = [float(x) for x in r.group(3).split(',')]
                piezas[r.group(1)] = (r.group(2), Matrix([v[0:4], v[4:8], v[8:12], v[12:16]]))

    def mundo(nombre):
        padre, matriz = piezas[nombre]
        return (mundo(padre) if padre else Matrix.Identity(4)) @ matriz

    sitio = Matrix.Translation((2.6, -2.9, 0)) @ Matrix.Rotation(math.radians(25), 4, 'Z')
    for o in pequeno:
        nombre = o.name.split('.')[0]
        if nombre in piezas:
            o.matrix_world = sitio @ mundo(nombre)
        else:
            bpy.data.objects.remove(o)
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAIZ, 'assets', 'almacen', 'objetos.glb'))
    for o in [o for o in bpy.data.objects if o not in antes]:
        if o.name.startswith('bidonPetroleo'):
            o.location = (2.25, 0.0, 0)
        else:
            bpy.data.objects.remove(o)
    oliva = materialLiso('contenedor', (0.17, 0.2, 0.12), 0.55, 0.35)
    caja('contenedorMisil', (4.2, 3.0, 0.75), (0.85, 9.0, 0.85), oliva, 0.03)
    caja('apoyoContenedor', (4.2, 0.2, 0.16), (1.0, 0.25, 0.32), materialLiso('apoyo', (0.3, 0.3, 0.3), 0.6))
    caja('apoyoContenedor', (4.2, 5.8, 0.16), (1.0, 0.25, 0.32), materialLiso('apoyo2', (0.3, 0.3, 0.3), 0.6))


def renderizarPesado(carpeta):
    escena = bpy.context.scene
    escena.cycles.samples = 64
    escena.render.resolution_x = 1600
    escena.render.resolution_y = 1000
    for objeto in [o for o in bpy.data.objects if o.type == 'LIGHT']:
        objeto.data.energy *= 6
        objeto.location = Vector(objeto.location) * 2.2
        objeto.rotation_euler = (Vector((1.2, 0, 1.6)) - Vector(objeto.location)).to_track_quat('-Z', 'Y').to_euler()
    garra = bpy.data.objects['garraDerA'].matrix_world.translation
    ojo = bpy.data.objects['ojoIzq'].matrix_world.translation
    for nombre, posicion, objetivo, lente in (
            ('pesado_frente', (6.5, -7.5, 3.4), (0.9, -0.6, 1.7), 30),
            ('pesado_atras', (-6.0, 6.5, 3.6), (0.2, 0, 1.6), 30),
            ('pesado_garra', tuple(garra + Vector((1.6, -0.9, 0.45))), tuple(garra + Vector((0.2, 0.2, -0.02))), 40),
            ('pesado_oruga', (1.8, -3.6, 0.9), (0.4, -1.1, 0.45), 35),
            ('pesado_ojos', tuple(ojo + Vector((0.95, -0.55, 0.15))), tuple(ojo + Vector((0, -0.18, 0))), 60)):
        datos = bpy.data.cameras.new(nombre)
        datos.lens = lente
        camara = bpy.data.objects.new(nombre, datos)
        camara.location = posicion
        camara.rotation_euler = (Vector(objetivo) - Vector(posicion)).to_track_quat('-Z', 'Y').to_euler()
        escena.collection.objects.link(camara)
        escena.camera = camara
        escena.render.filepath = os.path.join(carpeta, nombre + '.png')
        bpy.ops.render.render(write_still=True)


GLB_PESADO = os.path.join(RAIZ, 'assets', 'almacen', 'robot_pesado.glb')


def principal():
    args = argumentos()
    salida = args[0] if args else '/tmp/robot_pesado.blend'
    limpiarEscena()
    crearRobot()
    # Al juego: blender -b --factory-startup --python tools/blender/robot_pesado.py -- --glb
    if '--glb' in args:
        exportarJuego(GLB_PESADO)
        d = ORUGA_DATOS
        with open(os.path.splitext(GLB_PESADO)[0] + '_oruga.lua', 'w') as archivo:
            archivo.write('-- Camino de las orugas del robot grande (tools/blender/robot_pesado.py\n')
            archivo.write('-- --glb): las tejas tejaIzq00.. van por él (almacen/robots/especializaciones/orugas.lua).\n')
            archivo.write('return { n = %d, paso = %.6f, xPunta = %.6f, radio = %.6f, alto = %.4f, radioRueda = %.4f, radioRodillo = %.4f, y = { Izq = %.4f, Der = %.4f } }\n' % (
                d['n'], d['paso'], d['xPunta'], d['radio'], d['alto'], d['radioRueda'], d['radioRodillo'], d['y']['Izq'], d['y']['Der']))
        return
    prepararRender()
    bpy.data.objects['suelo'].scale = (3, 3, 1)
    ponerReferencias()
    bpy.ops.wm.save_as_mainfile(filepath=salida)
    if len(args) > 1:
        renderizarPesado(args[1])


principal()

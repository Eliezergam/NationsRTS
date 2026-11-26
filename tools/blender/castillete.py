"""Castillete (torre de extracción) de la mina de metal de Nations RTS.

Silueta (solo volúmenes a escala real, en metros; Z arriba, el pozo en el
origen, la casa del cabrestante hacia +X). Se modela por etapas, como los
robots: borrar el objeto de una etapa con sus hijos y volver a ejecutar solo
esa etapa.

Proporciones (castillete de acero en A para una mina mediana; Firgelli,
«Elevator Tower Mechanism», y Wikipedia, «Pit head»):
- torre de 28 m (los de acero van de 20 a 90 m);
- dos poleas de 4 m (de 3 a 6 m), una por jaula, con el eje a lo ancho (Y);
- patas traseras inclinadas hacia el cabrestante, en la dirección de los
  cables, para aguantar su tiro;
- la jaula vuelca el mineral en una tolva a media altura, de donde sale la
  cinta hacia la nave 1.

Ejecutar dentro de Blender: exec(open(ruta).read()) y luego construir().
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

COLECCION = 'castillete'

ALTO_TORRE = 28.0
BASE_TORRE = 7.0 # m de lado abajo
CIMA_TORRE = 4.5 # m de lado arriba
ALTO_POLEAS = 27.0 # eje de las poleas
RADIO_POLEA = 2.0
SEPARACION_POLEAS = 1.6 # m entre los dos planos de polea (Y)
PIE_PATAS_TRASERAS = 17.0 # m hacia +X
CASA_CABRESTANTE = (42.0, 0.0) # centro
CASA_MEDIDAS = (16.0, 12.0, 10.0)
ALTO_VOLCADO = 10.0 # m: donde la jaula vuelca en la tolva


def coleccion():
    c = bpy.data.collections.get(COLECCION)
    if not c:
        c = bpy.data.collections.new(COLECCION)
        bpy.context.scene.collection.children.link(c)
    return c


def enlazar(objeto, padre=None):
    for c in objeto.users_collection:
        c.objects.unlink(objeto)
    coleccion().objects.link(objeto)
    if padre:
        objeto.parent = padre
    return objeto


def vacio(nombre, padre=None):
    o = bpy.data.objects.new(nombre, None)
    return enlazar(o, padre)


def malla(nombre, construir, padre=None):
    """Objeto con una malla hecha por `construir(bm)` (bmesh, sin bpy.ops:
    funciona sin ventana activa)."""
    bm = bmesh.new()
    construir(bm)
    m = bpy.data.meshes.new(nombre)
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.new(nombre, m)
    return enlazar(o, padre)


def caja(nombre, centro, medidas, padre=None):
    def hacer(bm):
        bmesh.ops.create_cube(bm, size=1, matrix=Matrix.Translation(centro) @ Matrix.Diagonal((*medidas, 1)))

    return malla(nombre, hacer, padre)


def viga(nombre, a, b, grosor, padre=None):
    """Barra de sección cuadrada `grosor` m de `a` a `b`."""
    a, b = Vector(a), Vector(b)
    giro = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) / 2) @ giro @ Matrix.Diagonal((grosor, grosor, (b - a).length, 1))

    def hacer(bm):
        bmesh.ops.create_cube(bm, size=1, matrix=m)

    return malla(nombre, hacer, padre)


def cilindro(nombre, centro, radio, largo, eje='Z', padre=None, vertices=48):
    giro = Matrix.Identity(4)
    if eje == 'Y':
        giro = Matrix.Rotation(math.pi / 2, 4, 'X')
    elif eje == 'X':
        giro = Matrix.Rotation(math.pi / 2, 4, 'Y')

    def hacer(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=vertices, radius1=radio, radius2=radio, depth=largo,
                              matrix=Matrix.Translation(centro) @ giro)

    return malla(nombre, hacer, padre)


def embudo(nombre, centro, abajo, arriba, alto, padre=None):
    """Tolva de base cuadrada: `abajo` y `arriba` m de medio lado."""
    def hacer(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=abajo * math.sqrt(2), radius2=arriba * math.sqrt(2),
                              depth=alto, matrix=Matrix.Translation(centro) @ Matrix.Rotation(math.pi / 4, 4, 'Z'))

    return malla(nombre, hacer, padre)


def borrar(nombre):
    o = bpy.data.objects.get(nombre)
    if not o:
        return
    for h in list(o.children_recursive):
        bpy.data.objects.remove(h, do_unlink=True)
    bpy.data.objects.remove(o, do_unlink=True)


# Etapas ---------------------------------------------------------------------


def etapaPozo():
    """Brocal de hormigón del pozo con su boca de 4 × 3 m."""
    raiz = vacio('pozo')
    caja('brocalN', (0, 2.75, 0.5), (7, 1.5, 1.0), raiz)
    caja('brocalS', (0, -2.75, 0.5), (7, 1.5, 1.0), raiz)
    caja('brocalE', (2.75, 0, 0.5), (1.5, 4.0, 1.0), raiz)
    caja('brocalO', (-2.75, 0, 0.5), (1.5, 4.0, 1.0), raiz)
    return raiz


def etapaTorre():
    """Las cuatro patas de la torre (de BASE_TORRE a CIMA_TORRE), sus
    arriostramientos cada 7 m, la plataforma de las poleas y las dos patas
    traseras hacia el cabrestante."""
    raiz = vacio('torre')
    b, c, h = BASE_TORRE / 2, CIMA_TORRE / 2, ALTO_TORRE

    def esquina(sx, sy, z):
        f = z / h
        m = b + (c - b) * f
        return (sx * m, sy * m, z)

    esquinas = [(1, 1), (1, -1), (-1, -1), (-1, 1)]
    for k, (sx, sy) in enumerate(esquinas):
        viga('pata%d' % k, esquina(sx, sy, 0), esquina(sx, sy, h - 1), 0.5, raiz)
    for n, z in enumerate((7.0, 14.0, 21.0)):
        for k in range(4):
            a, s = esquinas[k], esquinas[(k + 1) % 4]
            viga('anillo%d_%d' % (n, k), esquina(a[0], a[1], z), esquina(s[0], s[1], z), 0.3, raiz)
    caja('plataformaPoleas', (0.5, 0, h - 0.5), (CIMA_TORRE + 3, CIMA_TORRE + 1, 0.6), raiz)
    # Patas traseras: de la cima, en la línea de los cables, al suelo.
    for sy in (1, -1):
        viga('pataTrasera%s' % ('I' if sy > 0 else 'D'), (c, sy * c, h - 1.5), (PIE_PATAS_TRASERAS, sy * 3.5, 0), 0.6, raiz)
    return raiz


def etapaPoleas():
    """Dos poleas de 4 m, una por jaula, con el eje en Y."""
    raiz = vacio('poleas')
    for k, sy in enumerate((SEPARACION_POLEAS / 2, -SEPARACION_POLEAS / 2)):
        cilindro('polea%d' % k, (0, sy, ALTO_POLEAS), RADIO_POLEA, 0.3, 'Y', raiz, 96)
    return raiz


def etapaCabrestante():
    """Casa del cabrestante y los cables de las poleas al tambor."""
    raiz = vacio('cabrestante')
    cx, cy = CASA_CABRESTANTE
    w, d, alto = CASA_MEDIDAS
    caja('casa', (cx, cy, alto / 2), (w, d, alto), raiz)
    tambor = (cx - w / 2 + 3, 0, 3.0)
    for k, sy in enumerate((SEPARACION_POLEAS / 2, -SEPARACION_POLEAS / 2)):
        viga('cable%d' % k, (RADIO_POLEA * 0.6, sy, ALTO_POLEAS + RADIO_POLEA * 0.8), (tambor[0], sy, tambor[2]), 0.06, raiz)
        viga('cableJaula%d' % k, (-RADIO_POLEA, sy, ALTO_POLEAS), (-RADIO_POLEA, sy, ALTO_VOLCADO + 4.2), 0.06, raiz)
    return raiz


def etapaJaula():
    """Una jaula arriba, volcando en la tolva."""
    raiz = vacio('jaula')
    caja('cuerpo', (-1.0, 0, ALTO_VOLCADO + 2), (2.0, 1.5, 4.0), raiz)
    return raiz


def etapaTolva():
    """Tolva de mineral junto a la torre (lado -X) y el arranque de la cinta
    hacia la nave 1."""
    raiz = vacio('tolva')
    z = ALTO_VOLCADO - 1
    embudo('embudo', (-6.5, 0, z - 2.5), 0.6, 2.4, 5, raiz)
    for k, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, -1), (-1, 1))):
        viga('apoyo%d' % k, (-6.5 + sx * 2, sy * 2, 0), (-6.5 + sx * 2, sy * 2, z - 2.5), 0.35, raiz)
    viga('cinta', (-6.5, 0, z - 5.2), (-46.5, 0, 4.0), 1.0, raiz)
    return raiz


def etapaPersona():
    """Referencia: persona de 1,80 m."""
    return cilindro('persona', (4.5, -6, 0.9), 0.25, 1.8)


ETAPAS = (etapaPozo, etapaTorre, etapaPoleas, etapaCabrestante, etapaJaula, etapaTolva, etapaPersona)


def construir():
    for e in ETAPAS:
        e()


if __name__ == '__main__':
    construir()

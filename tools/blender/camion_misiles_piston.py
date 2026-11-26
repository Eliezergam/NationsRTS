# Pistón de la rampa del lanzamisiles: anclajes de verdad en los dos extremos.
#
# Antes el cilindro arrancaba en su pivote apoyado sobre el bloque en T del
# chasis, sin orejas ni pasador, y el vástago llegaba a la rampa entre las dos
# vigas, sin nada a lo que unirse. Ahora (como una horquilla de cilindro
# hidráulico: orejas soldadas a una placa, pasador y placa de retención):
#   chasis          orejas con cartelas sobre la placa de la T, pasador con
#                   cabeza y placa de retención atornillada, cordones de
#                   soldadura y tornillos en la placa
#   rampaLanzador   travesaño soldado entre las dos vigas, orejas con cartelas,
#                   pasador, retención y soldaduras
#   pistonRampaBase cilindro rehecho de 24 lados: tapa trasera con ojo, collar
#                   trasero, camisa y collar delantero (prensaestopas)
#   pistonRampaVastago vástago de 24 lados con su ojo en la unión
# Los pivotes y el recorrido no cambian (batalla/articulacion_camion.lua):
# el ojo de cada pieza queda centrado en su pivote, que es el eje del
# pasador. Con la rampa a 35° el vástago sigue 12 cm dentro del cilindro.
#
# Uso: blender -b camion_misiles_synty4.blend --python camion_misiles_piston.py -- <salida.blend>
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform, closest_point_on_tri

args = sys.argv[sys.argv.index('--') + 1:]
CM = 0.001
Y = Vector((0, 1, 0))
# Eje del pistón en reposo (de la base a la unión), en ejes de Blender.
EJE = Vector((0.90374, 0, 0.42809))
UV_ACERO = Vector((0.5955, 0.9335))

# ---------------------------------------------------------------- piezas --

def objeto(nombre):
    return next(o for o in bpy.data.objects if o.type == 'MESH' and o.name.split('.')[0] == nombre)


class Pieza:
    """Geometría nueva en cm (en los ejes de la malla de su objeto)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.acero = set()

    def caras(self, puntos, indices, acero=False, liso=False):
        vs = [self.bm.verts.new(p * CM) for p in puntos]
        nuevas = []
        for idx in indices:
            f = self.bm.faces.new([vs[i] for i in idx])
            f.smooth = liso
            nuevas.append(f)
            if acero:
                self.acero.add(f)
        return nuevas

    def caja(self, centro, medida, acero=False, bisel=0.5):
        cx, cy, cz = centro
        hx, hy, hz = (m / 2 for m in medida)
        p = [Vector((cx + sx * hx, cy + sy * hy, cz + sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        nuevas = self.caras(p, [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)], acero)
        self.biselar(nuevas, bisel)

    def biselar(self, caras, ancho):
        if ancho <= 0:
            return
        aristas = list({e for f in caras for e in f.edges})
        res = bmesh.ops.bevel(self.bm, geom=aristas, offset=ancho * CM, segments=2, affect='EDGES', profile=0.5)
        if any(f in self.acero for f in caras):
            self.acero.update(res['faces'])

    def prisma(self, perfil, y0, y1, acero=False, bisel=0.4):
        """Perfil (x, z) en cm extruido de y0 a y1 (en y)."""
        n = len(perfil)
        p = [Vector((x, y0, z)) for x, z in perfil] + [Vector((x, y1, z)) for x, z in perfil]
        indices = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        indices += [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
        nuevas = self.caras(p, indices, acero)
        bmesh.ops.recalc_face_normals(self.bm, faces=nuevas)
        self.biselar(nuevas, bisel)

    def torno(self, origen, eje, perfil, lados=24, acero=False):
        """Sólido de revolución: perfil (radio, distancia por el eje) en cm."""
        eje = eje.normalized()
        a = eje.orthogonal().normalized()
        b = eje.cross(a)
        anillos = []
        for r, t in perfil:
            anillos.append([origen + eje * t + (a * math.cos(2 * math.pi * k / lados) + b * math.sin(2 * math.pi * k / lados)) * r for k in range(lados)])
        puntos = [p for an in anillos for p in an]
        indices = []
        for i in range(len(anillos) - 1):
            for k in range(lados):
                j = (k + 1) % lados
                indices.append((i * lados + k, i * lados + j, (i + 1) * lados + j, (i + 1) * lados + k))
        indices.append(tuple(reversed(range(lados))))
        ultimo = (len(anillos) - 1) * lados
        indices.append(tuple(range(ultimo, ultimo + lados)))
        nuevas = self.caras(puntos, indices, acero, liso=True)
        bmesh.ops.recalc_face_normals(self.bm, faces=nuevas)
        # Las tapas y los escalones, planos; los costados, lisos.
        for f in nuevas:
            f.smooth = abs(f.normal.dot(eje)) < 0.7

    def cilindroY(self, centro, radio, y0, y1, lados=16, acero=False):
        perfil = [(radio, 0), (radio, y1 - y0)]
        self.torno(Vector((centro[0], y0, centro[2])), Y, perfil, lados, acero)

    def cordon(self, a, b, radio=0.8):
        """Cordón de soldadura de a a b (cm): media caña de acero oscuro."""
        eje = b - a
        self.torno(a, eje, [(radio, 0), (radio, eje.length)], 6, acero=True)

    def tornillo(self, centro, normal, radio=2.0):
        """Cabeza hexagonal con arandela, apoyada en `centro`, mirando a `normal`."""
        self.torno(centro, normal, [(radio * 1.35, 0), (radio * 1.35, 0.4)], 16, acero=True)
        self.torno(centro + normal * 0.4, normal, [(radio, 0), (radio, radio * 0.7)], 6, acero=True)


# ------------------------------------------------------------ camuflaje --

class Camuflaje:
    """Copia el camuflaje de las caras viejas cercanas que miran igual."""

    def __init__(self, malla, filtro=None, materialIndice=0):
        me = malla.data
        uv = me.uv_layers.active.data
        self.caras = []
        for p in me.polygons:
            if p.material_index != materialIndice or p.area < (4 * CM) ** 2:
                continue
            vs = [me.vertices[i].co / CM for i in p.vertices]
            c = sum(vs, Vector()) / len(vs)
            if filtro and not filtro(c):
                continue
            us = [uv[l].uv.copy() for l in p.loop_indices]
            for k in range(1, len(vs) - 1):
                self.caras.append(((vs[0], vs[k], vs[k + 1]), (us[0], us[k], us[k + 1]), p.normal.copy(), p.area / CM ** 2))
        self.arbol = BVHTree.FromPolygons([v for t in self.caras for v in t[0]], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(self.caras))])

    def aplicar(self, cara, capa, radio=60):
        c = cara.calc_center_median() / CM
        nrm = cara.normal
        mejor, puntos = None, -1e9
        for _, _, idx, dist in self.arbol.find_nearest_range(c, radio):
            valor = self.caras[idx][2].dot(nrm) * 100 - dist + 10 * math.log(self.caras[idx][3] + 1)
            if valor > puntos:
                mejor, puntos = idx, valor
        if mejor is None:
            mejor = self.arbol.find_nearest(c)[2]
        (a, b, d), (ua, ub, ud), nv = self.caras[mejor][:3]
        for l in cara.loops:
            p = l.vert.co / CM
            # Al punto más cercano DENTRO de la cara vieja: extender su
            # proyección por el plano se salía de su parche del atlas (negro).
            p = closest_point_on_tri(p, a, b, d)
            w = barycentric_transform(p, a, b, d, ua.to_3d(), ub.to_3d(), ud.to_3d())
            l[capa].uv = (w.x, w.y)


def ponerAcero(cara, capa):
    # Cada vértice con su UV algo distinta (tangentes no degeneradas).
    for k, l in enumerate(cara.loops):
        a = 2 * math.pi * k / max(3, len(cara.loops))
        l[capa].uv = UV_ACERO + Vector((0.0003 * math.cos(a), 0.0002 * math.sin(a)))


def unir(pieza, malla, camuflaje, reemplazar=False):
    """Mete la geometría de `pieza` en el objeto `malla` (o la sustituye)."""
    bm = bmesh.new()
    if not reemplazar:
        bm.from_mesh(malla.data)
    capa = bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
    nuevas = pieza.bm
    capaNueva = nuevas.loops.layers.uv.new('UVMap')
    for f in nuevas.faces:
        if f in pieza.acero:
            ponerAcero(f, capaNueva)
        else:
            camuflaje.aplicar(f, capaNueva)
    bmesh.ops.triangulate(nuevas, faces=nuevas.faces[:])
    temporal = bpy.data.meshes.new('temporal')
    nuevas.to_mesh(temporal)
    antes = len(bm.faces)
    bm.from_mesh(temporal)
    bpy.data.meshes.remove(temporal)
    bm.to_mesh(malla.data)
    for p in malla.data.polygons[antes:]:
        p.material_index = 0
    bm.free()
    return len(nuevas.faces)


# ------------------------------------------------------- pivotes (cm) --
# Base: pivote del cilindro en el chasis. Unión: pivote del vástago en la rampa.
BASE = Vector((-339.2, 0, 252.8))
UNION = Vector((320, 0, 0))

chasis = objeto('chasis')
rampa = objeto('rampaLanzador')
cilindro = objeto('pistonRampaBase')
vastago = objeto('pistonRampaVastago')

# Los camuflajes se toman antes de tocar nada.
# Del bloque en T (poste y placa); con todo lo cercano copiaba el negro del bastidor.
camChasis = Camuflaje(chasis, lambda c: -372 < c.x < -300 and abs(c.y) < 36 and 170 < c.z < 247)
# De las dos vigas de la rampa.
camRampa = Camuflaje(rampa, lambda c: 38 < abs(c.y) < 58 and c.z < 17)
camCilindro = Camuflaje(cilindro)
camVastago = Camuflaje(vastago)

# ------------------------------------------------ horquilla del chasis --
# La placa de la T: x -370..-303, y ±34, arriba en z 245. Orejas a y ±11..±15.
h = Pieza()
# Más grandes que la tapa del cilindro (10,2 cm), como en una horquilla real.
R_OJO = 13.0
for lado in (-1, 1):
    y0, y1 = sorted((lado * 11, lado * 16))
    perfil = [(BASE.x - R_OJO, 245), (BASE.x + R_OJO, 245)]
    perfil += [(BASE.x + R_OJO * math.cos(math.pi * k / 12), BASE.z + R_OJO * math.sin(math.pi * k / 12)) for k in range(13)]
    h.prisma(perfil, y0, y1)
    # Cartelas por fuera, delante y detrás del ojo.
    for x in (BASE.x - 9, BASE.x + 9):
        yA, yB = lado * 16, lado * 23
        tri = [(x - 1, yA, 245), (x - 1, yB, 245), (x - 1, yA, 254), (x + 1, yA, 245), (x + 1, yB, 245), (x + 1, yA, 254)]
        caras = h.caras([Vector(t) for t in tri], [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)])
        bmesh.ops.recalc_face_normals(h.bm, faces=caras)
    # Soldaduras de la oreja a la placa, por los dos lados.
    for yc in (lado * 10.6, lado * 16.4):
        h.cordon(Vector((BASE.x - R_OJO, yc, 245.4)), Vector((BASE.x + R_OJO, yc, 245.4)))
# Pasador: cabeza a un lado, placa de retención con tornillo al otro.
h.cilindroY(BASE, 3.2, -20, 20, acero=True)
h.torno(Vector((BASE.x, -20, BASE.z)), -Y, [(4.8, 0), (4.8, 1.8)], 6, acero=True)
h.caja((BASE.x + 7, 16.7, BASE.z), (20, 1.4, 7.5), acero=True, bisel=0.3)
h.tornillo(Vector((BASE.x + 14, 17.4, BASE.z)), Y, 1.5)
# Tornillos de la placa de la T y soldadura del poste a la placa.
for x in (-364, -309):
    for y in (-28, 28):
        h.tornillo(Vector((x, y, 245)), Vector((0, 0, 1)), 2.0)
for a, b in (((-351, -15.4), (-322, -15.4)), ((-351, 15.4), (-322, 15.4)), ((-351.4, -15), (-351.4, 15)), ((-321.6, -15), (-321.6, 15))):
    h.cordon(Vector((a[0], a[1], 228.6)), Vector((b[0], b[1], 228.6)))
n = unir(h, chasis, camChasis)
print('CHASIS +%d caras' % n)

# -------------------------------------------------- horquilla de la rampa --
# Las vigas de la rampa van a y ±40..56, z 0..16. Travesaño entre ellas.
r = Pieza()
r.caja((UNION.x, 0, 10), (24, 80, 12), bisel=0.6)
for y in (-40, 40):
    for x in (UNION.x - 12, UNION.x + 12):
        r.cordon(Vector((x, y, 4.4)), Vector((x, y, 15.6)))
R_OJO_R = 7.0
for lado in (-1, 1):
    y0, y1 = sorted((lado * 6.2, lado * 9.6))
    perfil = [(UNION.x + R_OJO_R, 4), (UNION.x - R_OJO_R, 4)]
    perfil += [(UNION.x + R_OJO_R * math.cos(math.pi + math.pi * k / 12), UNION.z + R_OJO_R * math.sin(math.pi + math.pi * k / 12)) for k in range(13)]
    r.prisma(perfil, y0, y1)
    for x in (UNION.x - 4.5, UNION.x + 4.5):
        yA, yB = lado * 9.6, lado * 14
        tri = [(x - 0.8, yA, 4), (x - 0.8, yB, 4), (x - 0.8, yA, -1), (x + 0.8, yA, 4), (x + 0.8, yB, 4), (x + 0.8, yA, -1)]
        caras = r.caras([Vector(t) for t in tri], [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)])
        bmesh.ops.recalc_face_normals(r.bm, faces=caras)
    for yc in (lado * 5.8, lado * 10.0):
        r.cordon(Vector((UNION.x - R_OJO_R, yc, 3.6)), Vector((UNION.x + R_OJO_R, yc, 3.6)), 0.6)
r.cilindroY(UNION, 2.2, -13, 13, acero=True)
r.torno(Vector((UNION.x, -13, UNION.z)), -Y, [(3.4, 0), (3.4, 1.3)], 6, acero=True)
r.caja((UNION.x - 4.5, 10.3, UNION.z), (13, 1.2, 5.2), acero=True, bisel=0.25)
r.tornillo(Vector((UNION.x - 9.5, 10.9, UNION.z)), Y, 1.1)
n = unir(r, rampa, camRampa)
print('RAMPA +%d caras' % n)

# ------------------------------------------------------------ cilindro --
# Relativo a su pivote (el pasador). Ojo trasero, lengüeta, tapa con collar,
# camisa y collar delantero (prensaestopas) con el agujero del vástago.
c = Pieza()
O = Vector()
c.torno(O, EJE, [(0, 5.5), (9.0, 5.5), (10.2, 6.3), (10.2, 11.0), (9.6, 11.6), (9.6, 119.5), (10.5, 120.3), (10.5, 126.2), (9.9, 126.8), (6.3, 126.8)], 24)
c.cilindroY(O, 7.0, -8, 8, 20)
lateral = Y.cross(EJE).normalized()
esquinas = [O + EJE * t + Y * s + lateral * u for t in (0, 6) for s in (-8, 8) for u in (-6, 6)]
# Lengüeta del ojo a la tapa (caja orientada por el eje).
idx = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
caras = c.caras(esquinas, idx)
bmesh.ops.recalc_face_normals(c.bm, faces=caras)
# Toma de aceite junto al collar delantero.
c.torno(O + EJE * 116 + lateral * 9.4, lateral, [(1.6, 0), (1.6, 2.6), (2.2, 2.6), (2.2, 3.6)], 8, acero=True)
n = unir(c, cilindro, camCilindro, reemplazar=True)
print('CILINDRO %d caras' % n)

# ------------------------------------------------------------- vástago --
# Desde la unión hacia la base (-EJE): ojo en el pivote y vástago de acero.
v = Pieza()
v.torno(O, -EJE, [(0, 5.0), (5.8, 5.0), (5.8, 133.4), (5.2, 134.0), (0, 134.0)], 24, acero=True)
v.cilindroY(O, 5.2, -5.6, 5.6, 20, acero=True)
esquinas = [O - EJE * t + Y * s + lateral * u for t in (0, 5.5) for s in (-5.6, 5.6) for u in (-4.2, 4.2)]
caras = v.caras(esquinas, idx, acero=True)
bmesh.ops.recalc_face_normals(v.bm, faces=caras)
n = unir(v, vastago, camVastago, reemplazar=True)
print('VASTAGO %d caras' % n)

bpy.ops.wm.save_as_mainfile(filepath=args[0])

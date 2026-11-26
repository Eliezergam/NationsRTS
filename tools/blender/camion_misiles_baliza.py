# Baliza naranja del techo: de cilindro de 12 lados plano a una redonda con cúpula y base oscura.
import bpy, bmesh, math, sys
from mathutils import Vector
CM = 0.001
UV_NEGRO = Vector((0.366, 0.973))
o = bpy.data.objects['chasis']
bm = bmesh.new(); bm.from_mesh(o.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
capa = bm.loops.layers.uv.active
bm.faces.ensure_lookup_table()
vistos = set(); baliza = None
for f in bm.faces:
    if f.index in vistos: continue
    pila = [f]; g = []; vistos.add(f.index)
    while pila:
        x = pila.pop(); g.append(x)
        for e in x.edges:
            for h in e.link_faces:
                if h.index not in vistos: vistos.add(h.index); pila.append(h)
    vs = {v for q in g for v in q.verts}
    c = sum((v.co for v in vs), Vector()) / len(vs) / CM
    if 314 < c.z < 330 and 370 < c.x < 400 and abs(c.y) > 60 and len(g) < 80:
        baliza = (g, c, min(v.co.z for v in vs) / CM, max(v.co.z for v in vs) / CM)
g, c, zMin, zMax = baliza
# El naranja: la uv de la cara de arriba.
arriba = max(g, key=lambda f: f.calc_center_median().z)
uvs = [l[capa].uv for f in g for l in f.loops if f.normal.z > 0.9]
# Las mismas zonas del atlas que la luz vieja: arriba y lados.
uvNaranja = Vector((0.8429, 0.909))
# Naranja sin emisión (como la mitad de los lados de la luz vieja): con
# emisión, en el juego salía casi blanco.
uvLado = Vector((0.8429, 0.909))
print('UV naranja', uvNaranja, 'de', len(uvs))
material = arriba.material_index
bmesh.ops.delete(bm, geom=list(set(g)), context='FACES')
LADOS = 32
def anillo(r, z):
    return [bm.verts.new(Vector((c.x + r * math.cos(2 * math.pi * k / LADOS), c.y + r * math.sin(2 * math.pi * k / LADOS), z)) * CM) for k in range(LADOS)]
def unir(a, b, uv, liso):
    for k in range(LADOS):
        f = bm.faces.new((a[k], a[(k + 1) % LADOS], b[(k + 1) % LADOS], b[k]))
        f.smooth = liso; f.material_index = material
        ponerUv(f, uv)
def ponerUv(f, uv):
    # Cada vértice con su uv un poco distinta (como la luz vieja): con todas
    # iguales las tangentes del mapa de normales quedan degeneradas.
    for l in f.loops:
        a = math.atan2(l.vert.co.y / CM - c.y, l.vert.co.x / CM - c.x)
        r = 0.0003 + 0.0001 * (l.vert.co.z / CM - zMin) / alto
        l[capa].uv = uv + Vector((r * math.cos(a), r * math.sin(a)))
def tapa(a, z, uv):
    centro = bm.verts.new(Vector((c.x, c.y, z)) * CM)
    for k in range(LADOS):
        f = bm.faces.new((a[k], a[(k + 1) % LADOS], centro))
        f.smooth = True; f.material_index = material
        ponerUv(f, uv)
alto = zMax - zMin
# Base oscura con chaflán, cuerpo naranja y cúpula.
perfilBase = [(9.0, zMin), (9.0, zMin + 1.6), (8.2, zMin + 2.4)]
perfilLuz = [(7.2, zMin + 2.4), (7.6, zMin + 3.0), (7.6, zMin + alto - 2.0), (7.4, zMin + alto - 1.0), (6.9, zMin + alto - 0.3), (6.2, zMin + alto)]
anillos = [anillo(r, z) for r, z in perfilBase]
for i in range(len(anillos) - 1): unir(anillos[i], anillos[i + 1], UV_NEGRO, False)
tapa(anillos[-1], zMin + 2.4, UV_NEGRO)
luz = [anillo(r, z) for r, z in perfilLuz]
for i in range(len(luz) - 1): unir(luz[i], luz[i + 1], uvLado, True)
tapa(luz[-1], zMin + alto + 0.1, uvNaranja)
bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.is_valid and f.index == -1] or bm.faces[-LADOS * 9:])
bm.to_mesh(o.data); bm.free()
print('BALIZA rehecha en (%.0f %.0f), %.1f-%.1f cm, %d lados' % (c.x, c.y, zMin, zMax, LADOS))
bpy.ops.wm.save_as_mainfile(filepath=sys.argv[sys.argv.index('--') + 1])

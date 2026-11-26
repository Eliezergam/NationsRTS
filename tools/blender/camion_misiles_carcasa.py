# Carcasa de la cabina rediseñada (mismo estilo, medida y camuflaje): perfil lateral extruido,
# esquinas redondeadas de verdad, huecos del parabrisas y de las puertas, pared de 4 cm.
# Sustituye en `chasis` la isla de la carcasa vieja (334 caras). Medidas en cm (1 unidad = 1000 cm).
import bpy, bmesh, sys, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform, closest_point_on_tri
CM = 0.001
args = sys.argv[sys.argv.index('--') + 1:]
RADIO = float(args[1]) if len(args) > 1 else 14.0
chasis = bpy.data.objects['chasis']
capaVieja = None

# --- 1. Separar la carcasa vieja (para el camuflaje) y quitarla del chasis.
bm = bmesh.new(); bm.from_mesh(chasis.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
bm.faces.ensure_lookup_table()
vistos = set(); carcasa = None
for f in bm.faces:
    if f.index in vistos: continue
    pila = [f]; g = []; vistos.add(f.index)
    while pila:
        x = pila.pop(); g.append(x)
        for e in x.edges:
            for h in e.link_faces:
                if h.index not in vistos: vistos.add(h.index); pila.append(h)
    vs = {v for q in g for v in q.verts}
    if len(g) > 300 and min(v.co.x for v in vs) > 0.33 and max(v.co.z for v in vs) > 0.31:
        carcasa = g
assert carcasa, 'sin carcasa'
capa = bm.loops.layers.uv.active
viejas = []   # (triángulo en cm, uvs, normal)
for f in carcasa:
    pts = [l.vert.co / CM for l in f.loops]; uvs = [l[capa].uv.copy() for l in f.loops]
    for k in range(1, len(pts) - 1):
        viejas.append(((pts[0], pts[k], pts[k + 1]), (uvs[0], uvs[k], uvs[k + 1]), f.normal.copy()))
materialCuerpo = carcasa[0].material_index
bmesh.ops.delete(bm, geom=list(set(carcasa)), context='FACES')
bm.to_mesh(chasis.data); bm.free()
arbol = BVHTree.FromPolygons([v for t in viejas for v in t[0]], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(viejas))])

# --- 2. Perfil lateral (x, z) y extrusión a lo ancho.
Y = 134.4
perfil = [(339.2, 141.0), (536.9, 141.0), (536.9, 214.0), (520.5, 314.0), (339.2, 314.0)]
bm = bmesh.new()
izq = [bm.verts.new((x, -Y, z)) for x, z in perfil]
der = [bm.verts.new((x, Y, z)) for x, z in perfil]
n = len(perfil)
bm.faces.new(izq[::-1]); bm.faces.new(der)
for k in range(n):
    bm.faces.new((izq[k], izq[(k + 1) % n], der[(k + 1) % n], der[k]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
# Fuera la cara de abajo (la cabina se apoya en el suelo).
abajo = [f for f in bm.faces if f.normal.z < -0.9]
bmesh.ops.delete(bm, geom=abajo, context='FACES')
def aristasDe(cond):
    return [e for e in bm.edges if len(e.link_faces) == 2 and cond(e)]
medio = lambda e: (e.verts[0].co + e.verts[1].co) / 2
# Radios: esquinas verticales y del techo grandes, el quiebro del frente más suave.
grupos = [
    (RADIO, aristasDe(lambda e: abs(e.verts[0].co.y - e.verts[1].co.y) < 1 and medio(e).z > 150)),   # aristas del contorno (laterales)
    (RADIO, aristasDe(lambda e: abs(e.verts[0].co.y - e.verts[1].co.y) > 100 and medio(e).z > 300)),  # techo: delantera y trasera
    (RADIO * 0.6, aristasDe(lambda e: abs(e.verts[0].co.y - e.verts[1].co.y) > 100 and 200 < medio(e).z < 230)),  # quiebro del frente
    (RADIO, aristasDe(lambda e: abs(e.verts[0].co.y - e.verts[1].co.y) > 100 and medio(e).x < 340 and medio(e).z < 300 and medio(e).z > 150)),
]
todas = set()
for radio, aristas in grupos:
    todas.update(aristas)
r = bmesh.ops.bevel(bm, geom=list(todas), offset=RADIO, offset_type='OFFSET', segments=4, profile=0.5, affect='EDGES', clamp_overlap=True)
for f in bm.faces:
    f.smooth = False
for f in r['faces']:
    f.smooth = True
for v in bm.verts:
    v.co *= CM
me = bpy.data.meshes.new('carcasaNueva'); bm.to_mesh(me); bm.free()
nueva = bpy.data.objects.new('carcasaNueva', me); bpy.context.scene.collection.objects.link(nueva)

# --- 3. Huecos: parabrisas y puertas (las puertas van por fuera y tapan el borde).
def cortador(nombre, centro, medida):
    bpy.ops.mesh.primitive_cube_add(size=1, location=Vector(centro) * CM)
    c = bpy.context.active_object; c.name = nombre; c.scale = Vector(medida) * CM
    return c
s = nueva.modifiers.new('grueso', 'SOLIDIFY'); s.thickness = 4 * CM; s.offset = -1; s.use_even_offset = True; s.use_rim = True
with bpy.context.temp_override(object=nueva, active_object=nueva, selected_objects=[nueva]):
    bpy.ops.object.modifier_apply(modifier='grueso')
cortes = [
    cortador('parabrisas', (530, 0, 256), (60, 236, 82)),
    cortador('rejilla', (536, 0, 182.5), (14, 212, 39)),
    cortador('puertaI', (459, Y, 222), (106, 30, 140)),
    cortador('puertaD', (459, -Y, 222), (106, 30, 140)),
]
for c in cortes:
    m = nueva.modifiers.new(c.name, 'BOOLEAN'); m.object = c; m.operation = 'DIFFERENCE'; m.solver = 'EXACT'
with bpy.context.temp_override(object=nueva, active_object=nueva, selected_objects=[nueva]):
    for m in list(nueva.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
for c in cortes:
    bpy.data.objects.remove(c)

# --- 3b. Cortar la carcasa por las líneas de los paneles viejos (cada panel tiene su sitio en el atlas).
def cortes1d(eje, lo, hi):
    vals = sorted({round(p[eje], 0) for t in viejas for p in t[0]})
    res = []
    for v in vals:
        if lo + 6 < v < hi - 6 and (not res or v - res[-1] > 4):
            res.append(v)
    return res
planos = [(0, v) for v in cortes1d(0, 339.2, 536.9)] + [(1, v) for v in cortes1d(1, -134.4, 134.4)] + [(2, v) for v in cortes1d(2, 141, 314)]
bm = bmesh.new(); bm.from_mesh(nueva.data)
for eje, v in planos:
    nrm = Vector((0, 0, 0)); nrm[eje] = 1
    co = Vector((0, 0, 0)); co[eje] = v * CM
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-7, plane_co=co, plane_no=nrm)
bm.to_mesh(nueva.data); bm.free()
print('PLANOS', len(planos), [(e, v) for e, v in planos])

# --- 4. Camuflaje: cada cara copia el de UNA cara vieja (la cercana que mira igual, por fuera o por dentro),
# extendiendo su proyección por el plano: sin rayas en los redondeos ni camuflaje en las paredes de dentro.
CENTRO = Vector((440, 0, 228))
bm = bmesh.new(); bm.from_mesh(nueva.data)
uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
def haciaFuera(c, nrm):
    return (c - CENTRO).dot(nrm) > 0
areas = [((t[0][1] - t[0][0]).cross(t[0][2] - t[0][0])).length / 2 for t in viejas]
fuera = [haciaFuera(sum(t[0], Vector()) / 3, t[2]) for t in viejas]
for f in bm.faces:
    c = f.calc_center_median() / CM
    nrm = f.normal
    lado = haciaFuera(c, nrm)
    mejor, puntos = None, -1e9
    for loc, nor, idx, dist in arbol.find_nearest_range(c, 40):
        if fuera[idx] != lado or areas[idx] < 800:
            continue
        valor = viejas[idx][2].dot(nrm) * 100 - dist + 15 * math.log(areas[idx] + 1)
        if valor > puntos:
            mejor, puntos = idx, valor
    if mejor is None:
        loc, nor, mejor, dist = arbol.find_nearest(c)
    (a, b2, d), (ua, ub, ud), nv = viejas[mejor]
    for l in f.loops:
        p = l.vert.co / CM
        p = p - nv * (p - a).dot(nv)   # al plano de la cara vieja
        w = barycentric_transform(p, a, b2, d, Vector((ua.x, ua.y, 0)), Vector((ub.x, ub.y, 0)), Vector((ud.x, ud.y, 0)))
        l[uv].uv = (w.x, w.y)
    f.material_index = 0
bmesh.ops.triangulate(bm, faces=bm.faces[:])
bm.to_mesh(nueva.data); bm.free()
nueva.data.uv_layers.active = nueva.data.uv_layers[0]
# Mismo material que la carcasa vieja.
nueva.data.materials.clear(); nueva.data.materials.append(chasis.material_slots[materialCuerpo].material)
tris = len(nueva.data.polygons)

# --- 5. Unir al chasis.
nombreUV = chasis.data.uv_layers.active.name
nueva.data.uv_layers[0].name = nombreUV
with bpy.context.temp_override(active_object=chasis, selected_editable_objects=[chasis, nueva], object=chasis):
    bpy.ops.object.join()
print('CARCASA triángulos', tris, 'chasis ahora', len(chasis.data.polygons), 'capas uv', [u.name for u in chasis.data.uv_layers])
bpy.ops.wm.save_as_mainfile(filepath=args[0])

# Ya aplicado el 2026-11-16 (sobre la rueda vieja de Synty): volver a ejecutarlo rehace las ruedas pero necesita el disco viejo para el camuflaje.
# Uso: blender -b tools/blender/camion_misiles_synty4.blend --python tools/blender/camion_misiles_rueda.py -- tools/blender/camion_misiles_synty4.blend
# Necesita las ruedas viejas (los discos del rin de Synty) para copiar su camuflaje: ya aplicado el 2026-11-16.
# Rueda nueva del lanzamisiles (mismo estilo low poly y colores del atlas, misma medida y pivote):
# neumático torneado con hombro redondo y tacos en V, rin con disco en escalón y reborde grueso,
# buje con brida, 8 tuercas con arandela, tapa abombada y válvula del inflado central.
# Medidas en metros; al final se pasa al modelo (1 unidad = 10 m). El eje de giro es Y; +s es la cara de fuera.
import bpy, bmesh, sys, math
import numpy as np
from mathutils import Vector

M = 0.1
UV_RIN = (0.261, 0.722)
UV_METAL = (0.883, 0.511)
UV_GOMA = (0.817, 0.185)
UV_NEGRO = (0.366, 0.973)
PROYECCION = None  # (x, z) del modelo -> uv del camuflaje del anillo del rin viejo, por rueda
PROYECCION_CENTRO = None  # lo mismo para el centro del disco viejo (otra isla del atlas)
SEG = 40

def uvDe(uv, co, radioCara):
    # 'camuflaje': proyección plana del disco viejo (en metros: se pasa a unidades del modelo).
    if uv != 'camuflaje':
        return uv
    # Dentro de 0,40 m el disco viejo quedaba tapado por el buje y el atlas no tiene camuflaje ahí.
    r = max(math.hypot(co.x, co.z), 1e-6)
    # El disco viejo: un anillo (0,378-0,432 m) y un centro (< 0,378 m), cada uno en su sitio del atlas.
    # Lo que sale de esos radios se proyecta como si estuviera en su borde.
    if radioCara < 0.40:
        p, f = PROYECCION_CENTRO, min(1.0, 0.37 / r)
    else:
        p, f = PROYECCION, min(1.0, 0.425 / r)
        f = max(f, 0.385 / r)
    x, z = co.x * f * M, co.z * f * M
    return (p[0][0] * x + p[0][1] * z + p[0][2], p[1][0] * x + p[1][1] * z + p[1][2])

def torno(bm, perfil, uv, seg=SEG, liso=True):
    # perfil: lista de (radio, y). Gira alrededor de Y.
    capa = bm.loops.layers.uv.active
    anillos = []
    for r, y in perfil:
        anillos.append([bm.verts.new((r * math.cos(2 * math.pi * k / seg), y, r * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
    for i in range(len(anillos) - 1):
        a, b = anillos[i], anillos[i + 1]
        for k in range(seg):
            f = bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
            f.smooth = liso
            # La zona del camuflaje (anillo o centro) se decide por cara, no por vértice:
            # una cara con un vértice en cada zona estiraría el atlas entre las dos.
            centro = f.calc_center_median()
            for l in f.loops:
                l[capa].uv = uvDe(uv, l.vert.co, math.hypot(centro.x, centro.z))
    return anillos

def tapaCentro(bm, anillo, y, uv, liso=True):
    capa = bm.loops.layers.uv.active
    c = bm.verts.new((0, y, 0))
    n = len(anillo)
    for k in range(n):
        f = bm.faces.new((anillo[k], anillo[(k + 1) % n], c))
        f.smooth = liso
        for l in f.loops:
            l[capa].uv = uv

def prisma(bm, base, normal, u, v, ancho, largo, alto, lados, uv, chaflan=0.0, liso=False):
    # Prisma de `lados` (6 = tuerca, 4 = taco) sobre `base`, hacia `normal`; u, v: ejes del plano.
    capa = bm.loops.layers.uv.active
    def anillo(escala, h):
        pts = []
        for k in range(lados):
            a = 2 * math.pi * k / lados + (math.pi / lados if lados != 4 else math.pi / 4)
            x = math.cos(a) * ancho * escala * (1 if lados != 4 else math.sqrt(2))
            z = math.sin(a) * largo * escala * (1 if lados != 4 else math.sqrt(2))
            pts.append(bm.verts.new(base + u * x + v * z + normal * h))
        return pts
    anillos = [anillo(1.0, 0.0), anillo(1.0, alto - chaflan)]
    if chaflan:
        anillos.append(anillo(1.0 - chaflan / max(ancho, largo), alto))
    for i in range(len(anillos) - 1):
        a, b = anillos[i], anillos[i + 1]
        for k in range(lados):
            f = bm.faces.new((a[k], a[(k + 1) % lados], b[(k + 1) % lados], b[k]))
            f.smooth = liso
            for l in f.loops:
                l[capa].uv = uv
    f = bm.faces.new(anillos[-1])
    for l in f.loops:
        l[capa].uv = uv

def disco(bm, centro, u, w, radio, lados, uv):
    capa = bm.loops.layers.uv.active
    vs = [bm.verts.new(centro + u * radio * math.cos(2 * math.pi * k / lados) + w * radio * math.sin(2 * math.pi * k / lados)) for k in range(lados)]
    f = bm.faces.new(vs)
    for l in f.loops:
        l[capa].uv = uv

def construir(bm, s):
    # --- Neumático: flanco abombado, hombro redondo, banda.
    perfil = [(0.445, -0.185), (0.53, -0.204), (0.615, -0.202), (0.655, -0.185), (0.670, -0.150),
              (0.672, 0.0), (0.670, 0.150), (0.655, 0.185), (0.615, 0.202), (0.53, 0.204), (0.445, 0.185)]
    torno(bm, perfil, UV_GOMA)
    # Tacos en V: dos por paso, uno a cada lado del centro, inclinados.
    pasos = 22
    for k in range(pasos):
        for lado in (-1, 1):
            a = 2 * math.pi * (k + (0.5 if lado > 0 else 0.0)) / pasos
            ang = a + lado * 0.05
            radial = Vector((math.cos(ang), 0, math.sin(ang)))
            tangente = Vector((-math.sin(ang), 0, math.cos(ang)))
            # El taco va del centro hacia el hombro, inclinado en la dirección de giro.
            eje = (Vector((0, lado, 0)) * 0.9 + tangente * 0.45).normalized()
            otro = eje.cross(radial).normalized()
            base = radial * 0.670 + Vector((0, lado * 0.072, 0))
            prisma(bm, base, radial, otro, eje, 0.026, 0.068, 0.028, 4, UV_GOMA, chaflan=0.006)
    # --- Rin: reborde grueso, barril, disco en escalón hacia dentro y cara de apoyo.
    rin = [(0.445, s * 0.170), (0.466, s * 0.185), (0.458, s * 0.203), (0.432, s * 0.196),
           (0.415, s * 0.170), (0.400, s * 0.148), (0.360, s * 0.130), (0.235, s * 0.130),
           (0.205, s * 0.168), (0.130, s * 0.172)]
    torno(bm, rin, 'camuflaje')
    # Lado de dentro del rin (casi no se ve): barril y disco plano.
    dentro = [(0.415, s * 0.170), (0.415, -s * 0.170), (0.44, -s * 0.18), (0.44, -s * 0.19), (0.40, -s * 0.19), (0.13, -s * 0.10)]
    torno(bm, dentro, UV_RIN, seg=20, liso=False)
    # --- Buje: brida, cuerpo achaflanado y tapa abombada.
    buje = [(0.130, s * 0.172), (0.150, s * 0.172), (0.150, s * 0.190), (0.112, s * 0.192), (0.108, s * 0.250),
            (0.098, s * 0.258), (0.085, s * 0.260), (0.085, s * 0.272), (0.075, s * 0.286), (0.055, s * 0.296), (0.030, s * 0.301)]
    anillos = torno(bm, buje, UV_METAL, seg=16)
    tapaCentro(bm, anillos[-1], s * 0.303, UV_METAL)
    eje = Vector((0, s, 0)); u = Vector((1, 0, 0)); w = Vector((0, 0, 1))
    # 8 pernos de la brida.
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        p = Vector((0.132 * math.cos(a), s * 0.190, 0.132 * math.sin(a)))
        prisma(bm, p, eje, u, w, 0.009, 0.009, 0.010, 6, UV_METAL)
    # 8 tuercas de la rueda con arandela, en la cara de apoyo del disco.
    for k in range(8):
        a = 2 * math.pi * k / 8
        p = Vector((0.185 * math.cos(a), s * 0.172, 0.185 * math.sin(a)))
        prisma(bm, p, eje, u, w, 0.024, 0.024, 0.005, 8, UV_METAL, liso=True)
        prisma(bm, p + eje * 0.005, eje, u, w, 0.017, 0.017, 0.022, 6, UV_METAL, chaflan=0.004)
    # 8 agujeros de ventilación en el fondo del disco, en negro (como los que tenía).
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        p = Vector((0.300 * math.cos(a), s * 0.1295, 0.300 * math.sin(a)))
        disco(bm, p + eje * 0.001, u, w, 0.034, 10, UV_NEGRO)
    # Válvula del inflado central y su manguera.
    prisma(bm, Vector((0.0, s * 0.301, 0.0)), eje, u, w, 0.011, 0.011, 0.028, 10, UV_METAL, chaflan=0.003, liso=True)
    prisma(bm, Vector((0.0, s * 0.329, 0.0)), eje, u, w, 0.007, 0.007, 0.012, 8, UV_GOMA, liso=True)

def ajustarProyeccion(bm):
    # El disco viejo es la isla de 64 caras: su uv es una proyección plana exacta de (x, z).
    global PROYECCION, PROYECCION_CENTRO
    PROYECCION = PROYECCION_CENTRO = None
    capa = bm.loops.layers.uv.active
    vistos = set()
    for f in bm.faces:
        if f.index in vistos:
            continue
        pila = [f]; g = []; vistos.add(f.index)
        while pila:
            x = pila.pop(); g.append(x)
            for e in x.edges:
                for h in e.link_faces:
                    if h.index not in vistos:
                        vistos.add(h.index); pila.append(h)
        if len(g) in (64, 30):
            A = np.array([(l.vert.co.x, l.vert.co.z, 1.0) for c in g for l in c.loops])
            U = np.array([tuple(l[capa].uv) for c in g for l in c.loops])
            coef = np.linalg.lstsq(A, U, rcond=None)[0].T
            assert np.abs(A @ coef.T - U).max() < 1e-3
            if len(g) == 64:
                PROYECCION = coef.tolist()
            else:
                PROYECCION_CENTRO = coef.tolist()
    if PROYECCION is None or PROYECCION_CENTRO is None:
        raise RuntimeError('sin disco viejo para el camuflaje')

def rehacer(o):
    bm = bmesh.new(); bm.from_mesh(o.data)
    cerca = [v.co.y for v in bm.verts if abs(v.co.x) < 0.012 and abs(v.co.z) < 0.012]
    s = 1 if max(cerca, key=abs) > 0 else -1
    antes = len(bm.faces)
    ajustarProyeccion(bm)
    bmesh.ops.delete(bm, geom=list(bm.verts), context='VERTS')
    construir(bm, s)
    for v in bm.verts:
        v.co *= M
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(o.data); bm.free()
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    return antes, tris

for o in bpy.data.objects:
    if o.type == 'MESH' and o.name.startswith('rueda'):
        print('RUEDA', o.name, 'caras antes %d, triángulos ahora %d' % rehacer(o))
args = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.save_as_mainfile(filepath=args[0])

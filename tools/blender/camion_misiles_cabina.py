# Uso: blender -b tools/blender/camion_misiles_synty4.blend --python tools/blender/camion_misiles_cabina.py -- tools/blender/camion_misiles_synty4.blend
# Ya aplicado el 2026-11-16: volver a ejecutarlo duplicaría las piezas.
# Detalle de la cabina del lanzamisiles, mismo estilo low poly y colores del atlas:
# montante central y limpiaparabrisas, cristal y brazo de los retrovisores, escalones y asideros,
# escotilla redonda, canalones y antena en el techo. Todo va en la malla `chasis` (pivote en el origen).
# Medidas en cm reales (1 unidad del modelo = 10 m = 1000 cm).
import bpy, bmesh, sys, math
from mathutils import Vector

CM = 0.001
UV_METAL = (0.883, 0.511)   # gris del buje
UV_GOMA = (0.817, 0.185)    # goma oscura
UV_NEGRO = (0.366, 0.973)

o = bpy.data.objects['chasis']
bm = bmesh.new(); bm.from_mesh(o.data)
capa = bm.loops.layers.uv.active
cristal = next(i for i, s in enumerate(o.material_slots) if 'Cristal' in s.name)
cuerpo = next(i for i, s in enumerate(o.material_slots) if 'Cristal' not in s.name and 'Nacion' not in s.name)
antes = len(bm.faces)

def uvTecho(p):
    # El color del techo en ese punto: la uv del vértice del techo más cercano.
    # Solo la chapa del techo (caras grandes hacia arriba a esa altura), no la visera ni los canalones.
    techo = [f for f in bm.faces if f.normal.z > 0.9 and abs(f.calc_center_median().z * 1000 - 313.6) < 0.5 and f.calc_area() * 1e6 > 2000]
    mejor = min(((l, f) for f in techo for l in f.loops), key=lambda lf: (lf[0].vert.co - p * CM).length)
    return mejor[0][capa].uv.copy()

def cara(vs, uv, liso=False, material=None):
    f = bm.faces.new(vs)
    f.smooth = liso
    f.material_index = cuerpo if material is None else material
    for l in f.loops:
        l[capa].uv = uv
    return f

def caja(centro, ejes, medio, uv, material=None):
    # Caja orientada: centro (cm), ejes (3 vectores unitarios), medio (3 medias medidas en cm).
    c = Vector(centro); a, b, d = (Vector(e) for e in ejes)
    vs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                vs.append(bm.verts.new((c + a * sx * medio[0] + b * sy * medio[1] + d * sz * medio[2]) * CM))
    i = lambda sx, sy, sz: vs[(sx > 0) * 4 + (sy > 0) * 2 + (sz > 0)]
    for k in (-1, 1):
        cara([i(k, -1, -1), i(k, 1, -1), i(k, 1, 1), i(k, -1, 1)][::k], uv, material=material)
        cara([i(-1, k, -1), i(-1, k, 1), i(1, k, 1), i(1, k, -1)][::k], uv, material=material)
        cara([i(-1, -1, k), i(1, -1, k), i(1, 1, k), i(-1, 1, k)][::k], uv, material=material)

def tubo(p0, p1, radio, uv, lados=8, tapas=True):
    p0, p1 = Vector(p0), Vector(p1)
    eje = (p1 - p0).normalized()
    u = eje.orthogonal().normalized(); w = eje.cross(u)
    anillos = []
    for p in (p0, p1):
        anillos.append([bm.verts.new((p + (u * math.cos(2 * math.pi * k / lados) + w * math.sin(2 * math.pi * k / lados)) * radio) * CM) for k in range(lados)])
    for k in range(lados):
        cara([anillos[0][k], anillos[0][(k + 1) % lados], anillos[1][(k + 1) % lados], anillos[1][k]], uv, liso=True)
    if tapas:
        cara(anillos[0][::-1], uv); cara(anillos[1], uv)

def cilindro(centro, radio, alto, uv, lados=16, chaflan=0.0):
    # Vertical (z), base en centro.
    c = Vector(centro)
    def anillo(r, h):
        return [bm.verts.new((c + Vector((r * math.cos(2 * math.pi * k / lados), r * math.sin(2 * math.pi * k / lados), h))) * CM) for k in range(lados)]
    anillos = [anillo(radio, 0), anillo(radio, alto - chaflan)]
    if chaflan:
        anillos.append(anillo(radio - chaflan, alto))
    for i in range(len(anillos) - 1):
        for k in range(lados):
            a, b = anillos[i], anillos[i + 1]
            cara([a[k], a[(k + 1) % lados], b[(k + 1) % lados], b[k]], uv, liso=True)
    cara(anillos[-1], uv)

# --- Parabrisas: plano de la cara de fuera del cristal (esquinas medidas).
vid = [f for f in bm.faces if f.material_index == cristal and f.normal.x > 0.9 and f.calc_center_median().x > 0.52]
pts = [v.co / CM for f in vid for v in f.verts]
zMin, zMax = min(p.z for p in pts), max(p.z for p in pts)
yMax = max(abs(p.y) for p in pts)
def xCristal(z):
    abajo = max((p for p in pts if abs(p.z - zMin) < 0.5), key=lambda p: p.x).x
    arriba = max((p for p in pts if abs(p.z - zMax) < 0.5), key=lambda p: p.x).x
    return abajo + (arriba - abajo) * (z - zMin) / (zMax - zMin)
normal = vid[0].normal.copy()
subida = Vector((xCristal(zMax) - xCristal(zMin), 0, zMax - zMin)).normalized()
print('PARABRISAS y ±%.1f z %.1f-%.1f x %.1f-%.1f' % (yMax, zMin, zMax, xCristal(zMin), xCristal(zMax)))
# Montante central: goma de 6 cm por 2 de grueso.
zc = (zMin + zMax) / 2
caja((xCristal(zc) + 1.0, 0, zc), (normal, (0, 1, 0), subida), (1.0, 3.0, (zMax - zMin) / 2), UV_GOMA)
# Limpiaparabrisas aparcados abajo: eje, brazo y escobilla, uno por mitad.
for lado in (-1, 1):
    eje = Vector((xCristal(zMin + 4) + 1.5, lado * 18, zMin + 4))
    cilindro(eje - normal * 1.0 + Vector((0, 0, -1.5)), 2.2, 0.1, UV_NEGRO, lados=10)
    ang = math.radians(12)
    dirBrazo = Vector((0, lado * math.cos(ang), 0)) + subida * math.sin(ang)
    dirBrazo.normalize()
    fin = eje + dirBrazo * 72
    tubo(eje + normal * 1.2, fin + normal * 1.2, 0.9, UV_NEGRO, lados=6)
    centroEscobilla = eje + dirBrazo * 40 + normal * 2.2
    caja(centroEscobilla, (normal, dirBrazo, normal.cross(dirBrazo).normalized()), (0.8, 34, 0.9), UV_GOMA)

# --- Retrovisores: cristal en la cara de atrás y brazo tubular de abajo.
for lado in (-1, 1):
    y0, y1 = 159.5, 171.5
    caja((521.0, lado * (y0 + y1) / 2, 275.0), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (0.6, 5.2, 27.0), UV_METAL)
    tubo((527, lado * 125.5, 232), (530, lado * 163, 250), 1.4, UV_NEGRO)
    tubo((530, lado * 163, 250), (530, lado * 163, 247), 2.0, UV_NEGRO)

# --- Asideros junto a la puerta (detrás, en la cabina) y escalones bajo ella.
for lado in (-1, 1):
    yAsa = lado * 140.5
    tubo((404, yAsa, 170), (404, yAsa, 262), 1.6, UV_NEGRO)
    for z in (170, 262):
        tubo((404, lado * 137.6, z), (404, yAsa, z), 1.2, UV_NEGRO)
    # Escalones: dos peldaños de chapa con soportes.
    for z in (118, 88):
        caja((465, lado * 133, z), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (34, 9, 1.2), UV_METAL)
    for x in (433, 497):
        caja((x, lado * 138.5, 103), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (1.2, 2.5, 44), UV_NEGRO)

# --- Techo: canalones, escotilla redonda y antena.
for lado in (-1, 1):
    caja((430, lado * 127.5, 314.6), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (82, 1.2, 1.0), UV_NEGRO)
uvTapa = uvTecho(Vector((440, -45, 313.6)))
cilindro((440, -45, 313.6), 34, 3.0, UV_METAL, lados=24)
cilindro((440, -45, 316.6), 31, 3.5, uvTapa, lados=24, chaflan=1.5)
caja((440, -45 - 33, 318), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (8, 2.5, 2.0), UV_NEGRO)   # bisagra
tubo((440 - 18, -45 + 18, 320), (440 + 18, -45 + 18, 320), 1.2, UV_NEGRO)                # asa de la tapa
cilindro((500, 112, 313.6), 4.5, 6, UV_NEGRO, lados=12, chaflan=1.0)                       # base de la antena
tubo((500, 112, 319), (500, 112, 380), 1.0, UV_NEGRO, lados=6)                             # látigo: tramo grueso
tubo((500, 112, 380), (500, 112, 440), 0.7, UV_NEGRO, lados=6)                             # y punta
bm.normal_update()
bm.to_mesh(o.data); bm.free()
print('CABINA caras nuevas', len(o.data.polygons) - antes, 'triángulos totales chasis', sum(len(p.vertices) - 2 for p in o.data.polygons))
args = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.save_as_mainfile(filepath=args[0])

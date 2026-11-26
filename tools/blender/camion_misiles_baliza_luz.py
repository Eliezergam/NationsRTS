# Pieza `balizaLuz` del lanzamisiles: la cubierta encendida de la luz del
# techo (naranja con emisión del atlas), 4 mm por fuera de la luz apagada que
# va en `chasis` (camion_misiles_baliza.py). El juego la enseña y la oculta
# según el parpadeo de batalla/vehiculos/especializaciones/baliza.lua.
#
# Uso: blender -b camion_misiles_synty4.blend --python camion_misiles_baliza_luz.py -- <salida.blend> <pieza.lua>
# Escribe en <pieza.lua> la entrada de `piezas` para assets/modelos3d/camion_misiles_synty4.lua.
import bpy, bmesh, math, sys
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
CM = 0.001
# Centro de la base de la luz apagada (cm de Blender) y su alto.
CX, CY, Z0 = 384.0, 80.0, 313.6
ALTO = 12.8
LADOS = 32
# Naranja con emisión del atlas (el sin emisión es el de la luz apagada).
UV_ENCENDIDA = Vector((0.6183, 0.9091))
# Perfil (radio, alto sobre la base) en cm: 4 mm por fuera de la luz apagada.
PERFIL = [(8.0, 2.8), (8.0, ALTO - 2.0), (7.8, ALTO - 0.8), (7.3, ALTO - 0.1), (6.6, ALTO + 0.4)]

viejo = bpy.data.objects.get('balizaLuz')
if viejo:
    bpy.data.objects.remove(viejo)
malla = bpy.data.meshes.new('Malla_balizaLuz')
objeto = bpy.data.objects.new('balizaLuz', malla)
bpy.context.scene.collection.objects.link(objeto)
objeto.data.materials.append(bpy.data.materials['unidadCamion4'])

bm = bmesh.new()
capa = bm.loops.layers.uv.new('UVMap')

def anillo(r, z):
    # Relativo al pivote (centro de la base).
    return [bm.verts.new(Vector((r * math.cos(2 * math.pi * k / LADOS), r * math.sin(2 * math.pi * k / LADOS), z)) * CM) for k in range(LADOS)]

def ponerUv(cara):
    # Cada vértice con su UV algo distinta: con todas iguales las tangentes del
    # mapa de normales quedan degeneradas.
    for l in cara.loops:
        a = math.atan2(l.vert.co.y, l.vert.co.x)
        r = 0.0003 + 0.0001 * l.vert.co.z / CM / ALTO
        l[capa].uv = UV_ENCENDIDA + Vector((r * math.cos(a), r * math.sin(a)))

anillos = [anillo(r, z) for r, z in PERFIL]
for i in range(len(anillos) - 1):
    a, b = anillos[i], anillos[i + 1]
    for k in range(LADOS):
        cara = bm.faces.new((a[k], a[(k + 1) % LADOS], b[(k + 1) % LADOS], b[k]))
        cara.smooth = True
        ponerUv(cara)
centro = bm.verts.new(Vector((0, 0, (ALTO + 0.5))) * CM)
for k in range(LADOS):
    cara = bm.faces.new((anillos[-1][k], anillos[-1][(k + 1) % LADOS], centro))
    cara.smooth = True
    ponerUv(cara)
bmesh.ops.triangulate(bm, faces=bm.faces[:])
bm.normal_update()
bm.to_mesh(malla)

# Entrada del .lua: px del juego (1 px = 10 cm), y del juego = -y de Blender,
# triángulos sueltos {x, y, z, nx, ny, nz, r, g, b, nacion}.
filas = []
for cara in bm.faces:
    n = cara.normal
    for v in cara.verts:
        p = v.co / CM / 10
        filas.append('{%g,%g,%g,%g,%g,%g,1,0.72,0.25,0},' % (round(p.x, 2), round(-p.y, 2), round(p.z, 2), round(n.x, 2), round(-n.y, 2), round(n.z, 2)))
bm.free()
pivote = '{ %g, %g, %g }' % (CX / 10, -CY / 10, Z0 / 10)
with open(args[1], 'w') as f:
    f.write("        { nombre = 'balizaLuz', padre = 'chasis', pivote = %s, vertices = {\n" % pivote)
    f.write('\n'.join(filas) + '\n        } },\n')
# Como las demás piezas, la malla va relativa a su pivote (en Blender queda en el origen).
print('BALIZA_LUZ', len(malla.polygons), 'triángulos, pivote', pivote)
bpy.ops.wm.save_as_mainfile(filepath=args[0])

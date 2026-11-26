# Maqueta del soldado lanzamisiles de Nations RTS: la cabeza se convierte en
# un cañón pieza por pieza (el dueño, 18-nov: «la cabeza deja de existir y se
# genera un cañón, pieza por pieza, proceduralmente; después, con las piezas
# del cañón, se vuelve a generar la cabeza»).
#
# La cabeza está hecha de placas (12 alrededor x 4 de alto, más 4 de tapa) y
# los dos ojos. Cada placa tiene dos sitios: el suyo en la cabeza y el suyo
# en el cañón (8 duelas alrededor x 6 a lo largo; la tapa, aletas de la boca;
# los ojos, mira a los lados). El cambio es procedural, igual que lo hará el
# Lua del juego:
#   - cada placa sale con un retraso (en cascada, de delante a atrás);
#   - va por un arco hacia fuera (curva de Bézier con el punto de control
#     empujado desde el centro) y gira sobre sí misma mientras viaja
#     (interpola la orientación y suma media vuelta a algunas);
#   - el tubo interior (ánima oscura) sale del cuello a la vez.
# Al revés, lo mismo desde el cañón.
# Con las piezas de la cabeza el cañón solo da para 45 cm; para llegar a un
# metro (un misil antitanque ronda 1,1 m) salen 56 piezas más de la mochila
# (el dueño, 18-nov: «que se alargue con piezas de otro lado que aparezcan»):
# nacen pequeñas dentro de ella, crecen mientras vuelan y forman la parte de
# atrás del cañón; al volver a ser cabeza se meten otra vez y desaparecen.
# Los ojos son los de todos los robots (globo con aro de cobre, diafragma y
# núcleo cian de robot_soldado.py): en el cañón van a los lados, de mira.
#
#     blender -b --factory-startup --python tools/blender/robot_cabeza_canon_maqueta.py -- <salida.mp4>

import math
import os
import subprocess
import sys
import tempfile

import bpy
from mathutils import Matrix, Quaternion, Vector

_DIR = os.path.dirname(os.path.abspath(__file__))
_ns = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_ns['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _ns)

CABEZA = Vector((0.01, 0.0, 1.73))  # centro
SEMI = (0.125, 0.11)  # semiejes de la cabeza (x, y)
FILAS_Z = (1.61, 1.69, 1.77, 1.85)
PLACA = 0.074  # lado de cada placa
GRUESO = 0.016
CANON_EJE = Vector((0.28, 0.0, 1.71))  # centro de la parte de delante (la de la cabeza)
CANON_R = 0.098
CANON_ANILLOS = 6
CANON_DUELAS = 8
EXTRA_ANILLOS = 7  # los de detrás, con piezas que salen de la mochila
MOCHILA = Vector((-0.3, 0.0, 1.5))
FPS = 30
CAMBIO = 1.8  # s que tarda la transformación entera
VIAJE = 0.55  # s que viaja cada placa


def material(nombre, color, rugosidad=0.5, metal=0.0, emision=None):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rugosidad
    p.inputs['Metallic'].default_value = metal
    if emision:
        p.inputs['Emission Color'].default_value = (*emision, 1)
        p.inputs['Emission Strength'].default_value = 6
    return m


def borrarConHijos(nombre):
    o = bpy.data.objects.get(nombre)
    if not o:
        return
    for h in list(o.children_recursive):
        bpy.data.objects.remove(h, do_unlink=True)
    bpy.data.objects.remove(o, do_unlink=True)


def placa(nombre, mats, franja):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = nombre
    o.scale = (GRUESO, PLACA * 0.94, PLACA * 0.94)
    bpy.ops.object.transform_apply(scale=True)
    o.modifiers.new('bisel', 'BEVEL').width = 0.006
    o.data.materials.append(mats['negro'])
    if franja:
        # Una franja blanca para que se lea cada pieza al moverse.
        bpy.ops.mesh.primitive_cube_add(size=1, location=(GRUESO / 2 + 0.001, 0, 0))
        f = bpy.context.active_object
        f.scale = (0.002, PLACA * 0.7, 0.008)
        f.data.materials.append(mats['blanco'])
        f.parent = o
    o.rotation_mode = 'QUATERNION'
    return o


def marco(normal, arriba):
    """Orientación de una placa: su x hacia `normal`, su z hacia `arriba`."""
    x = Vector(normal).normalized()
    z = Vector(arriba)
    z = (z - x * z.dot(x)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed().to_quaternion()


def sitiosCabeza():
    """48 placas alrededor (12 x 4) y 4 de tapa: (posición, orientación)."""
    s = []
    a, b = SEMI
    for z in FILAS_Z:
        # Más estrecha arriba y abajo (casco redondeado).
        k = 1 - 0.18 * abs(z - 1.73) / 0.12
        for i in range(12):
            t = 2 * math.pi * i / 12
            p = Vector((CABEZA.x + a * k * math.cos(t), b * k * math.sin(t), z))
            n = Vector((math.cos(t) / a, math.sin(t) / b, 0))
            s.append((p, marco(n, (0, 0, 1))))
    for i in range(4):
        t = 2 * math.pi * (i + 0.5) / 4
        p = Vector((CABEZA.x + 0.045 * math.cos(t), 0.045 * math.sin(t), 1.9))
        s.append((p, marco((0, 0, 1), (math.cos(t), math.sin(t), 0))))
    return s


def anillo(x, j):
    s = []
    for i in range(CANON_DUELAS):
        t = 2 * math.pi * (i + 0.5 * (j % 2)) / CANON_DUELAS
        n = Vector((0, math.cos(t), math.sin(t)))
        s.append((Vector((x, 0, CANON_EJE.z)) + n * CANON_R, marco(n, (1, 0, 0))))
    return s


def sitiosExtra():
    """Los anillos de detrás (de la mochila), del más cercano al más lejano."""
    s = []
    x0 = CANON_EJE.x - CANON_ANILLOS * PLACA / 2
    for j in range(EXTRA_ANILLOS):
        s += anillo(x0 - PLACA * (j + 0.5), j + 1)
    return s


def sitiosCanon():
    """48 duelas (8 alrededor x 6 a lo largo) y 4 aletas en la boca."""
    s = []
    largo = CANON_ANILLOS * PLACA
    for j in range(CANON_ANILLOS):
        x = CANON_EJE.x - largo / 2 + PLACA * (j + 0.5)
        s += anillo(x, j)
    boca = CANON_EJE.x + largo / 2 + 0.02
    for i in range(4):
        t = 2 * math.pi * i / 4 + math.pi / 4
        n = Vector((0, math.cos(t), math.sin(t)))
        p = Vector((boca, 0, CANON_EJE.z)) + n * (CANON_R + 0.03)
        s.append((p, marco(n, (1, 0, 0))))
    return s


def emparejar(cabeza, canon):
    """Cada placa de la cabeza a un sitio del cañón: las de delante van a la
    boca; dentro de cada tanda, por ángulo (así no se cruzan tanto)."""
    def angulo(p, centro):
        return math.atan2(p.z - centro.z, p.y - centro.y)

    orden = sorted(range(len(cabeza)), key=lambda i: (-round(cabeza[i][0].x, 2), angulo(cabeza[i][0], CABEZA)))
    sitios = sorted(range(len(canon)), key=lambda j: (-round(canon[j][0].x, 2), angulo(canon[j][0], CANON_EJE)))
    pareja = {}
    for rango, (i, j) in enumerate(zip(orden, sitios)):
        pareja[i] = (j, rango)
    return pareja


def suave(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def colocar(o, a, b, centroA, centroB, t, giro):
    """Placa entre su sitio a (cabeza) y b (cañón) en el instante t (0..1):
    arco hacia fuera y media vuelta sobre sí misma por el camino."""
    pa, qa = a
    pb, qb = b
    # Punto de control: el medio, empujado hacia fuera de los dos centros.
    medio = (pa + pb) / 2
    fuera = (pa - centroA) + (pb - centroB)
    if fuera.length > 1e-6:
        fuera.normalize()
    control = medio + fuera * 0.14 + Vector((0, 0, 0.05))
    u = suave(t)
    p = (1 - u) ** 2 * pa + 2 * (1 - u) * u * control + u ** 2 * pb
    q = qa.slerp(qb, u)
    if giro:
        q = q @ Quaternion((0, 0, 1), math.pi * 2 * u * (1 - u) * 2)
    o.location = p
    o.rotation_quaternion = q


def montar(mats):
    O = bpy.data.objects
    borrarConHijos('metralleta')
    borrarConHijos('codoIzq')
    y = _ns['PECHO'][1] / 2 + 0.065
    x0, z = _ns['CODO_IZQ']
    for lado, nombre in ((1, 'hombroIzq'), (-1, 'hombroDer')):
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.058, depth=0.24, location=(x0 + 0.12, lado * y, z), rotation=(0, math.pi / 2, 0))
        o = bpy.context.active_object
        o.data.materials.append(mats['negro'])
        bpy.ops.object.shade_smooth()
        o.parent = O[nombre]
        o.matrix_parent_inverse = O[nombre].matrix_world.inverted()
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.058, location=(x0 + 0.24, lado * y, z))
        o = bpy.context.active_object
        o.data.materials.append(mats['negro'])
        bpy.ops.object.shade_smooth()
        o.parent = O[nombre]
        o.matrix_parent_inverse = O[nombre].matrix_world.inverted()
    # Mochila con los misiles.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-0.3, 0, 1.36))
    o = bpy.context.active_object
    o.scale = (0.2, 0.3, 0.4)
    o.modifiers.new('bisel', 'BEVEL').width = 0.03
    o.data.materials.append(mats['negro'])
    # La cabeza de verdad no se ve: la maqueta la hace de placas.
    cabeza = O['cabeza']
    cabeza.hide_render = True
    for h in cabeza.children_recursive:
        h.hide_render = True
    sc, sn = sitiosCabeza(), sitiosCanon()
    pareja = emparejar(sc, sn)
    placas = []
    for i, (p, q) in enumerate(sc):
        o = placa('placa%02d' % i, mats, franja=(i % 3 == 0))
        j, rango = pareja[i]
        placas.append({'o': o, 'a': sc[i], 'b': sn[j], 'rango': rango, 'giro': i % 2 == 0})
    # Núcleo: dentro de la cabeza, una bola oscura; en el cañón, el ánima.
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085, location=CABEZA)
    nucleo = bpy.context.active_object
    nucleo.data.materials.append(mats['oscuro'])
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=CANON_R - 0.012, depth=1, location=CANON_EJE, rotation=(0, math.pi / 2, 0))
    anima = bpy.context.active_object
    anima.data.materials.append(mats['oscuro'])
    # Los ojos de todos los robots (globo{S} con sus piezas): en la cara,
    # asomando de las placas; en el cañón, de mira a los lados.
    ojos = []
    for s, lado in ((1, 'Izq'), (-1, 'Der')):
        o = O['globo' + lado]
        mundo = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mundo
        o.rotation_mode = 'QUATERNION'
        for h in [o] + list(o.children_recursive):
            h.hide_render = False
        reposo = o.location.copy()
        a = (reposo + Vector((0.04, 0, 0)), o.rotation_quaternion.copy())
        b = (Vector((CANON_EJE.x + 0.08, s * (CANON_R + 0.04), CANON_EJE.z + 0.035)), o.rotation_quaternion.copy())
        ojos.append({'o': o, 'a': a, 'b': b, 'rango': 10, 'giro': False})
    # Piezas de la mochila: nacen pequeñas dentro y crecen volando.
    extra = []
    for k, (p, q) in enumerate(sitiosExtra()):
        o = placa('extra%02d' % k, mats, franja=(k % 3 == 0))
        sitio = (MOCHILA + Vector((0, 0.04 * math.sin(k), 0.03 * math.cos(k))), q)
        extra.append({'o': o, 'a': sitio, 'b': (p, q), 'rango': k, 'giro': k % 2 == 1})
    return placas, ojos, nucleo, anima, extra


def pose(placas, ojos, nucleo, anima, extra, f):
    """f: 0 cabeza, 1 cañón (tiempo de la transformación, 0..1)."""
    n = len(placas)
    T = f * CAMBIO
    for pl in placas + ojos:
        retraso = (CAMBIO - VIAJE) * pl['rango'] / n
        t = (T - retraso) / VIAJE
        colocar(pl['o'], pl['a'], pl['b'], CABEZA, CANON_EJE, t, pl['giro'])
    # Las de la mochila salen algo después, de la más cercana a la más lejana,
    # y crecen mientras vuelan.
    ne = len(extra)
    for pl in extra:
        retraso = 0.25 + (CAMBIO - VIAJE - 0.25) * pl['rango'] / ne
        t = (T - retraso) / VIAJE
        colocar(pl['o'], pl['a'], pl['b'], MOCHILA, CANON_EJE, t, pl['giro'])
        e = max(0.001, suave(t * 1.6))
        pl['o'].scale = (e, e, e)
    # El núcleo se encoge y el ánima sale del cuello hacia la boca.
    u = suave(f * 1.4)
    nucleo.scale = Vector((1, 1, 1)) * max(0.001, 1 - u)
    largo = (CANON_ANILLOS + EXTRA_ANILLOS) * PLACA + 0.06
    frente = CANON_EJE.x + CANON_ANILLOS * PLACA / 2 + 0.03
    k = suave((f - 0.2) / 0.8)
    anima.scale = (1, 1, max(0.001, largo * k))
    # Sin salir del todo no se ve (si no, queda un disco plano flotando).
    anima.hide_render = k < 0.02
    anima.location = (frente - largo * k / 2, 0, CANON_EJE.z)


def escenario():
    s = bpy.context.scene
    for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            s.render.engine = motor
            break
        except TypeError:
            pass
    s.render.resolution_x, s.render.resolution_y = 960, 720
    s.view_settings.view_transform = 'Standard'
    mundo = bpy.data.worlds.new('fondo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.55, 0.6, 0.66, 1)
    fondo.inputs['Strength'].default_value = 0.9
    s.world = mundo
    bpy.ops.mesh.primitive_plane_add(size=20)
    bpy.context.active_object.data.materials.append(material('suelo', (0.36, 0.37, 0.35), 0.9))
    bpy.ops.object.light_add(type='SUN', location=(3, 2, 6))
    sol = bpy.context.active_object
    sol.data.energy = 3.5
    sol.rotation_euler = (math.radians(40), math.radians(20), math.radians(130))
    bpy.ops.object.camera_add(location=(2.2, 1.7, 2.15))
    camara = bpy.context.active_object
    camara.data.lens = 50
    camara.rotation_euler = (Vector((0.05, 0.0, 1.55)) - camara.location).to_track_quat('-Z', 'Y').to_euler()
    s.camera = camara


def principal():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    salida = args[0] if args else '/tmp/cabeza_canon.mp4'
    _ns['construir']()
    mats = {
        'negro': material('placaNegra', (0.03, 0.03, 0.035), 0.35, 0.3),
        'blanco': material('placaFranja', (0.9, 0.9, 0.88), 0.4),
        'oscuro': material('anima', (0.01, 0.01, 0.01), 0.8),
        'ojo': material('ojoMaqueta', (0.05, 0.3, 0.35), 0.3, 0.0, (0.1, 0.9, 1.0)),
    }
    bpy.context.view_layer.update()
    placas, ojos, nucleo, anima, extra = montar(mats)
    escenario()
    # Guion: cabeza 1 s, a cañón, cañón 1,2 s, a cabeza, cabeza 0,8 s.
    tramos = [(1.0, 0, 0), (CAMBIO + 0.2, 0, 1), (1.2, 1, 1), (CAMBIO + 0.2, 1, 0), (0.8, 0, 0)]
    carpeta = tempfile.mkdtemp(prefix='cabeza_canon_')
    k = 0
    for duracion, a, b in tramos:
        cuadros = int(duracion * FPS)
        for c in range(cuadros):
            f = a + (b - a) * min(1, c / max(1, cuadros - 1) * (duracion / (duracion - 0.2) if a != b else 1))
            pose(placas, ojos, nucleo, anima, extra, f)
            bpy.context.scene.render.filepath = os.path.join(carpeta, 'c%04d.png' % k)
            bpy.ops.render.render(write_still=True)
            k += 1
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(FPS), '-i', os.path.join(carpeta, 'c%04d.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '24', salida], check=True)
    for nombre in os.listdir(carpeta):
        os.remove(os.path.join(carpeta, nombre))
    os.rmdir(carpeta)
    print('VIDEO', salida, k)


if bpy.app.background:
    principal()

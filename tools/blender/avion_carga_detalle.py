"""Avión de carga de Nations RTS: fase de detalle (el dueño, 20-nov: «usa el
.md y la misma temática de los robots para detallarlo»).

La silueta aprobada está en avion_carga.py y no se copia: aquí se ejecuta y
cada etapa de detalle rehace su etapa de silueta y le cuelga encima el
detalle con el acabado de la casa (skills robot-detallado y
vehiculo-detallado): carcasa negra biselada y semibrillante, juntas de panel
hundidas y oscuras, placas plateadas, franjas blancas, pernos de acero con
arandela, cobre en los aros y brillo cian (la energía de los robots).
Los materiales son los mismos de los robots (robot_almacen.py, con las
texturas PBR reales de metal_plate_02).

Escala: el avión mide 59 m; un perno de chapa estructural de avión es de
unos 10-12 cm de cabeza (aquí radio 0,06 m) y las juntas, de 5 cm, para que
se lean desde la cámara cercana del juego. Lo diminuto va en la normal.

Todo lo pequeño se funde en un objeto por material y sector (regla de la
casa, GUIA-3D §5.1): `pernosMorro`, `placasMorro`...

En el Blender del dueño (por MCP):
    g = {'__name__': 'detalle'}; exec(open(ruta).read(), g); g['etapaMorroDetalle']()
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

_DIR = os.path.expanduser('~/NationsRTS/tools/blender')

# La silueta (sus etapas y medidas, en este mismo espacio de nombres).
with open(os.path.join(_DIR, 'avion_carga.py'), encoding='utf8') as _f:
    exec(_f.read().replace("if __name__ == '__main__':", 'if False:'))

# Las herramientas y materiales de los robots, aparte (tienen otra caja y
# otro cilindro con la misma palabra).
ROBOT = {'__name__': 'robotAlmacen'}
with open(os.path.join(_DIR, 'robot_almacen.py'), encoding='utf8') as _f:
    _fuente = _f.read()
exec('import math, os, sys\nimport bmesh, bpy\nfrom mathutils import Matrix, Vector\n' + _fuente[_fuente.index('def argumentos():'):_fuente.index('# El robot ---')], ROBOT)

PERNO = 0.06 # radio de la cabeza de un perno de chapa
JUNTA = 0.05 # ancho de una junta de panel
JUNTA_FONDO = 0.03


def materialesCasa():
    """Los materiales de los robots (una vez por sesión de Blender)."""
    ns = bpy.app.driver_namespace
    m = ns.get('avionMateriales')
    if m and all(mat.name in bpy.data.materials for mat in m.values()):
        return m
    m = ROBOT['crearMateriales']()
    ROBOT['materialesReales'](m)
    for mat in m.values():
        mat.use_fake_user = True
    ns['avionMateriales'] = m
    return m


# Lo provisional de la silueta → los materiales de la casa.
EQUIVALENCIAS = {
    'carcasa': 'negro',
    'acero': 'plata',
    'ojoCian': 'nucleo',
    'hueco': 'negroMate',
    'visor': 'visor',
    'cobre': 'cobre',
    'globo': 'negro',
}


def colorearCasa():
    etapaColores()
    m = materialesCasa()
    for viejo, nuevo in EQUIVALENCIAS.items():
        mat = bpy.data.materials.get(viejo)
        if mat and mat != m[nuevo]:
            mat.user_remap(m[nuevo])


def marcar(o, padre=None):
    o['detalle'] = 1
    enlazar(o, padre)
    return o


# Herramientas de detalle -------------------------------------------------------

def arbol(objeto):
    """BVH de la malla en el mundo (con modificadores)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = objeto.evaluated_get(dg)
    m = ev.to_mesh()
    vs = [objeto.matrix_world @ v.co for v in m.vertices]
    caras = [p.vertices[:] for p in m.polygons]
    ev.to_mesh_clear()
    return BVHTree.FromPolygons(vs, caras)


def sobre(bvh, punto, direccion):
    """(punto, normal) donde un rayo desde `punto` hacia `direccion` toca la
    superficie, o None."""
    p, n, i, d = bvh.ray_cast(Vector(punto), Vector(direccion).normalized())
    if p is None:
        return None
    if n.dot(Vector(direccion)) > 0:
        n = -n
    return p, n


def ranuras(objeto, planos, m, ancho=JUNTA, fondo=JUNTA_FONDO, limite=None):
    """Juntas de panel hundidas en la malla de `objeto`: por cada plano
    (punto, normal), una ranura de `ancho` (solo donde `limite(centro)`, si
    se da) con paredes verticales (4 cortes:
    el borde y 5 mm más allá a cada lado) y el fondo `fondo` hacia dentro,
    con el material negro mate."""
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    for punto, normal in planos:
        punto, normal = Vector(punto), Vector(normal).normalized()
        for d in (-ancho / 2 - 0.005, -ancho / 2, ancho / 2, ancho / 2 + 0.005):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=punto + normal * d, plane_no=normal)
    bm.normal_update()
    if m['negroMate'].name not in [mat.name for mat in objeto.data.materials]:
        objeto.data.materials.append(m['negroMate'])
    indice = [mat.name for mat in objeto.data.materials].index(m['negroMate'].name)
    hundir = set()
    for cara in bm.faces:
        c = cara.calc_center_median()
        for punto, normal in planos:
            if abs((c - Vector(punto)).dot(Vector(normal).normalized())) < ancho / 2 and (limite is None or limite(c)):
                cara.material_index = indice
                hundir.update(cara.verts)
                break
    # Los vértices del fondo bajan; los de 5 mm más allá no se mueven y
    # hacen la pared de la ranura.
    normales = {v: v.normal.copy() for v in hundir}
    for v in hundir:
        v.co -= normales[v] * fondo
    bm.to_mesh(objeto.data)
    bm.free()
    objeto.data.update()
    # Aristas vivas en las paredes de la ranura: si no, el sombreado suave
    # se reparte por las caras largas y los tramos se ven hinchados.
    ROBOT['suave'](objeto)


def chapa(nombre, fuente, cortes, desplazar, grosor, material, padre, bisel=0.02):
    """Placa que sigue la superficie de `fuente`: el trozo que dejan los
    `cortes` (punto, normal: se quita el lado de la normal), despegado
    `desplazar` por su normal, con `grosor` y los cantos biselados."""
    bm = bmesh.new()
    bm.from_mesh(fuente.data)
    bm.transform(fuente.matrix_world)
    for punto, normal in cortes:
        cortar(bm, punto, normal)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * desplazar
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=grosor)
    bm.normal_update()
    vivas = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(50)]
    if bisel:
        bmesh.ops.bevel(bm, geom=vivas, offset=bisel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    me = bpy.data.meshes.new(nombre)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nombre, me)
    me.materials.append(material)
    ROBOT['suave'](o)
    return marcar(o, padre)


def fundir(nombre, objetos, padre):
    """Une piezas sueltas (de las herramientas de los robots, en la escena)
    en un objeto por material; lo cuelga de `padre`."""
    porMaterial = {}
    for o in objetos:
        porMaterial.setdefault(o.data.materials[0].name, []).append(o)
    salida = []
    for nombreMat, grupo in porMaterial.items():
        bm = bmesh.new()
        for o in grupo:
            me = o.data.copy()
            me.transform(o.matrix_world)
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        me = bpy.data.meshes.new(nombre)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(bpy.data.materials[nombreMat])
        u = bpy.data.objects.new('%s_%s' % (nombre, nombreMat), me)
        ROBOT['suave'](u)
        salida.append(marcar(u, padre))
        for o in grupo:
            malla_ = o.data
            bpy.data.objects.remove(o)
            if malla_.users == 0:
                bpy.data.meshes.remove(malla_)
    return salida


def pernosEn(bvh, puntos, direccion, m, sueltos, radio=PERNO):
    """Pernos de la casa (cabeza hexagonal de acero y arandela) donde caen
    los rayos desde `puntos` hacia `direccion`."""
    for k, p in enumerate(puntos):
        golpe = sobre(bvh, p, direccion)
        if golpe:
            punto, normal = golpe
            sueltos += ROBOT['perno']('perno', punto, normal, m, radio=radio, material='acero')
    return sueltos


# Morro ------------------------------------------------------------------------

def etapaMorroDetalle():
    """El morro con el acabado de los robots:

    - juntas de panel: cuadernas en x y una línea de mentón;
    - el marco del visor con pernos arriba y abajo;
    - vidrio ahumado y, detrás, la consola de código verde (etapaCaraConsola);
    - una placa plateada en cada mejilla, bajo el visor, con pernos;
    - franja blanca a lo largo de la arista del lomo (la línea de la cara);
    - pernos en fila en la placa del mentón."""
    m = materialesCasa()
    raiz = etapaMorro()
    etapaLomo()
    casco = bpy.data.objects['morroCasco']
    casco.data.materials.clear()
    casco.data.materials.append(m['negro'])
    for n in ('ojoVisorI', 'ojoVisorD'):
        bpy.data.objects.remove(bpy.data.objects[n])
    for n, clave in (('visorMarco', 'plata'),):
        o = bpy.data.objects[n]
        o.data.materials.clear()
        o.data.materials.append(m[clave])
        o['detalle'] = 1
    for n in ('aristaI', 'aristaD', 'carenadoRaiz'):
        o = bpy.data.objects[n]
        o.data.materials.clear()
        o.data.materials.append(m['negro'])
    vx0, vx1, vz0, vz1 = VISOR
    oy, oz, ol, oa = OJOS_VISOR

    # Juntas: cuadernas delante y detrás del visor y la línea del mentón.
    ranuras(casco, [((17.6, 0, 0), (1, 0, 0)), ((19.2, 0, 0), (1, 0, 0)), ((22.6, 0, 0), (1, 0, 0)),
                    ((0, 0, 3.3), (0, 0, 1))], m)

    # Cabina: vidrio oscuro y el rostro mecánico detrás (el dueño, 20-nov).
    etapaCaraConsola(raiz, casco, m)

    # Placas de las mejillas (bajo el visor, por delante de la rueda de proa).
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        chapa('mejilla' + s, casco, [((19.6, 0, 0), (-1, 0, 0)), ((22.4, 0, 0), (1, 0, 0)),
                                    ((0, 0, 3.55), (0, 0, -1)), ((0, 0, vz0 - VISOR_MARCO - 0.12), (0, 0, 1)),
                                    ((0, 0, 0), (0, -lado, 0))], 0.035, 0.04, m['plata'], raiz)

    # Franja blanca por la arista del lomo: de la punta a donde entra en el
    # ala, en la cara de arriba de la arista (0,3 m de ancho).
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        arista = bpy.data.objects['arista' + s]
        vs = [v.co.copy() for v in arista.data.vertices]
        tiras = []
        for k in range(len(vs) // 3):
            tope, filo = vs[3 * k], vs[3 * k + 1]
            hacia = (tope - filo).normalized()
            normal = hacia.cross(Vector((1, 0, 0)))
            if normal.z < 0:
                normal = -normal
            a = filo + hacia * 0.12 + normal * 0.015
            b = filo + hacia * 0.42 + normal * 0.015
            tiras.append((a, b))

        def franja(bm, tiras=tiras):
            pares = [(bm.verts.new(a), bm.verts.new(b)) for a, b in tiras]
            for (a1, b1), (a2, b2) in zip(pares, pares[1:]):
                bm.faces.new((a1, b1, b2, a2))
            bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.02)

        o = malla('franjaLomo' + s, franja)
        o.data.materials.append(m['blanco'])
        marcar(o, raiz)

    # Pernos: marco del visor (arriba y abajo), mejillas y mentón.
    bpy.context.view_layer.update()
    sueltos = []
    marco = arbol(bpy.data.objects['visorMarco'])
    for lado in (1, -1):
        xs = [vx0 + 0.35 + 0.7 * k for k in range(int((vx1 - vx0 - 1.2) / 0.7))]
        for z in (vz1 + VISOR_MARCO / 2, vz0 - VISOR_MARCO / 2):
            pernosEn(marco, [(x, lado * 8, z) for x in xs], (0, -lado, 0), m, sueltos, radio=0.045)
        mejilla = arbol(bpy.data.objects['mejilla' + ('I' if lado > 0 else 'D')])
        puntos = [(x, lado * 8, z) for x in (19.85, 21.0, 22.15) for z in (3.8, 4.45)]
        pernosEn(mejilla, puntos, (0, -lado, 0), m, sueltos)
    menton = arbol(casco)
    pernosEn(menton, [(x, y, -2) for x in (17.9, 18.5, 19.1) for y in (-3.6, -2.4, -1.2, 0, 1.2, 2.4, 3.6)], (0, 0, 1), m, sueltos, radio=0.05)
    fundir('pernosMorro', sueltos, raiz)
    return raiz


# Cara de consola (el dueño, 20-nov, con la foto de Lockdown: «quítale esos
# ojos; que se vea como la cara de este: un vidrio y adentro tipo consola con
# códigos en verde y luces de todo tipo, pero no una cabina»).
#
# Detrás del vidrio ahumado, en capas (lo que da la profundidad):
#   1. `pantallaCodigo`: una pantalla curva que sigue la cara, PANTALLA m
#      dentro de la piel, verde y transparente donde no hay trazo (retículas
#      de mira, rejilla, columnas de código, trazas de circuito, barras).
#      Su textura (hud_codigo.png) se desplaza en el juego para que corra.
#   2. `placaCircuitos`: al fondo (FONDO m), placa oscura con pistas de
#      cobre; encima chips, condensadores y luces de muchos colores.
# Las paredes de la cavidad bajan por la normal de la piel. En la punta, donde
# el morro es fino, el vidrio queda sobre la piel (de x = HUECO_HASTA en adelante).
#
# Para Lua: `luces<Color>` (un objeto por color: verde, ámbar, roja, azul,
# cian, magenta) se encienden y apagan en grupo; el desplazamiento de la UV
# de `pantallaCodigo` hace correr el código.
PANTALLA = 0.28
FONDO = 0.62
HUECO_HASTA = 25.3
COLORES_LUCES = (
    ('lucesVerde', (0.15, 1.0, 0.3)),
    ('lucesAmbar', (1.0, 0.55, 0.05)),
    ('lucesRoja', (1.0, 0.06, 0.04)),
    ('lucesAzul', (0.1, 0.35, 1.0)),
    ('lucesCian', (0.1, 0.85, 1.0)),
    ('lucesMagenta', (0.9, 0.1, 0.8)),
)
HUD_RUTA = os.path.expanduser('~/NationsRTS-assets/avion_carga/hud_codigo.png')
PCB_RUTA = os.path.expanduser('~/NationsRTS-assets/avion_carga/placa_circuitos.png')


def materialLuz(nombre, color, fuerza=10.0):
    mat = bpy.data.materials.get(nombre)
    if not mat:
        mat = ROBOT['materialLiso'](nombre, color, 0.3, 0.0, fuerza)
        mat.use_fake_user = True
    return mat


def materialVidrio():
    """Vidrio ahumado medio oscuro."""
    mat = bpy.data.materials.get('vidrioCabina')
    if not mat:
        mat = bpy.data.materials.new('vidrioCabina')
        mat.use_nodes = True
        b = ROBOT['nodoPrincipled'](mat)
        b.inputs['Base Color'].default_value = (0.02, 0.025, 0.03, 1)
        b.inputs['Roughness'].default_value = 0.03
        b.inputs['IOR'].default_value = 1.5
        b.inputs['Alpha'].default_value = 0.55
        mat.use_fake_user = True
    for prop, valor in (('surface_render_method', 'BLENDED'), ('use_backface_culling', False)):
        try:
            setattr(mat, prop, valor)
        except (AttributeError, TypeError):
            pass
    return mat


# Texturas hechas por programa (numpy) ------------------------------------------

def _lienzo(ancho, alto):
    import numpy as np
    return np.zeros((alto, ancho, 4), dtype=np.float32)


def _punto(img, x, y, color, r=1):
    alto, ancho = img.shape[:2]
    x0, x1 = max(int(x) - r + 1, 0), min(int(x) + r, ancho)
    y0, y1 = max(int(y) - r + 1, 0), min(int(y) + r, alto)
    if x0 < x1 and y0 < y1:
        img[y0:y1, x0:x1] = color


def _linea(img, a, b, color, r=1):
    pasos = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
    for k in range(pasos + 1):
        f = k / pasos
        _punto(img, a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, color, r)


def _circulo(img, c, radio, color, r=1, desde=0.0, hasta=2 * math.pi):
    pasos = int(radio * (hasta - desde)) + 8
    for k in range(pasos + 1):
        a = desde + (hasta - desde) * k / pasos
        _punto(img, c[0] + math.cos(a) * radio, c[1] + math.sin(a) * radio, color, r)


def _guardar(img, nombre, ruta):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    alto, ancho = img.shape[:2]
    imagen = bpy.data.images.get(nombre)
    if imagen:
        bpy.data.images.remove(imagen)
    imagen = bpy.data.images.new(nombre, ancho, alto, alpha=True)
    imagen.pixels.foreach_set(img.ravel())
    imagen.filepath_raw = ruta
    imagen.file_format = 'PNG'
    imagen.save()
    imagen.pack()
    return imagen


def texturaHud():
    """HUD verde: rejilla tenue, dos retículas de mira, columnas de código,
    trazas de circuito con nodos y barras de medida (alfa 0 donde no hay
    nada). 2048 x 512: u da la vuelta a la cara, v de abajo arriba."""
    import random
    rnd = random.Random(7)
    img = _lienzo(2048, 512)
    verde = (0.25, 1.0, 0.35, 1.0)
    tenue = (0.15, 0.7, 0.25, 0.2)
    claro = (0.7, 1.0, 0.7, 1.0)
    for x in range(0, 2048, 64):
        _linea(img, (x, 0), (x, 511), tenue)
    for y in range(0, 512, 64):
        _linea(img, (0, y), (2047, y), tenue)
    # Dos radares (el dueño, 20-nov: «más bien tipo radares»): anillos de
    # distancia, ejes y radiales, el barrido con su estela que se apaga y
    # ecos (los de la estela, más vivos). En el juego el barrido gira (se
    # dibuja en un lienzo cada cuadro); aquí, quieto en un ángulo.
    import numpy as np
    yy, xx = np.mgrid[0:512, 0:2048]
    for cx, barrido in ((820, 0.9), (1228, 2.6)):
        c = (cx, 270)
        radio = 150
        for k in (1, 2, 3):
            _circulo(img, c, radio * k / 3, verde if k == 3 else tenue[:3] + (0.7,), 2 if k == 3 else 1)
        for k in range(36):
            a = 2 * math.pi * k / 36
            l = 12 if k % 3 else 22
            _linea(img, (c[0] + math.cos(a) * radio, c[1] + math.sin(a) * radio), (c[0] + math.cos(a) * (radio + l), c[1] + math.sin(a) * (radio + l)), verde)
        for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
            _linea(img, c, (c[0] + math.cos(a) * radio, c[1] + math.sin(a) * radio), tenue[:3] + (0.6,))
        # Barrido: cuña de 70° detrás de la línea, que se apaga hacia atrás.
        dx, dy = xx - c[0], yy - c[1]
        r = np.sqrt(dx * dx + dy * dy)
        a = np.mod(barrido - np.arctan2(dy, dx), 2 * math.pi)
        estela = np.where((r < radio) & (a < math.radians(70)), 1 - a / math.radians(70), 0.0) ** 1.6 * 0.55
        img[..., 0] = np.maximum(img[..., 0], 0.2 * estela)
        img[..., 1] = np.maximum(img[..., 1], 1.0 * estela)
        img[..., 2] = np.maximum(img[..., 2], 0.3 * estela)
        img[..., 3] = np.maximum(img[..., 3], estela)
        _linea(img, c, (c[0] + math.cos(barrido) * radio, c[1] + math.sin(barrido) * radio), claro, 2)
        # Ecos: puntos con su halo; los recién barridos, más grandes.
        for _ in range(9):
            ae = rnd.uniform(0, 2 * math.pi)
            re = rnd.uniform(0.2, 0.9) * radio
            reciente = (barrido - ae) % (2 * math.pi) < math.radians(70)
            p = (c[0] + math.cos(ae) * re, c[1] + math.sin(ae) * re)
            _punto(img, p[0], p[1], claro if reciente else verde, 5 if reciente else 3)
            if reciente:
                _circulo(img, p, 10, verde, 1)
        _punto(img, c[0], c[1], claro, 3)
    # Columnas de código: líneas de «caracteres» (rayitas de 3-9 px).
    for x0 in list(range(40, 640, 150)) + list(range(1420, 2010, 150)):
        for fila in range(rnd.randint(10, 22)):
            y = 470 - fila * 16
            x = x0
            for _ in range(rnd.randint(3, 12)):
                largo = rnd.randint(3, 9)
                _linea(img, (x, y), (x + largo, y), verde if rnd.random() > 0.15 else claro, 2)
                x += largo + rnd.randint(3, 6)
    # Trazas de circuito entre las retículas y el código.
    for _ in range(40):
        x, y = rnd.randint(300, 1750), rnd.randint(30, 480)
        for _ in range(rnd.randint(2, 4)):
            if rnd.random() < 0.5:
                nx, ny = x + rnd.choice((-1, 1)) * rnd.randint(30, 140), y
            else:
                nx, ny = x, y + rnd.choice((-1, 1)) * rnd.randint(20, 90)
            nx, ny = min(max(nx, 0), 2047), min(max(ny, 0), 511)
            _linea(img, (x, y), (nx, ny), verde)
            x, y = nx, ny
        _circulo(img, (x, y), 4, verde, 1)
    # Barras de medida abajo.
    for k in range(18):
        h = rnd.randint(10, 60)
        x = 900 + k * 14
        img[30:30 + h, x:x + 9] = verde
    return _guardar(img, 'hudCodigo', HUD_RUTA)


def texturaPlaca():
    """Placa de circuitos: fondo verde muy oscuro con pistas de cobre en
    ángulos de 45° y pads."""
    import random
    rnd = random.Random(11)
    img = _lienzo(2048, 512)
    img[:, :] = (0.012, 0.03, 0.018, 1.0)
    cobre = (0.55, 0.32, 0.12, 1.0)
    for _ in range(260):
        x, y = rnd.randint(0, 2047), rnd.randint(0, 511)
        for _ in range(rnd.randint(2, 5)):
            d = rnd.choice(((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)))
            l = rnd.randint(15, 90)
            nx, ny = min(max(x + d[0] * l, 0), 2047), min(max(y + d[1] * l, 0), 511)
            _linea(img, (x, y), (nx, ny), cobre, 2)
            x, y = nx, ny
        _circulo(img, (x, y), 5, cobre, 2)
    return _guardar(img, 'placaCircuitos', PCB_RUTA)


def materialImagen(nombre, imagen, emision=0.0, transparente=False, rugosidad=0.5):
    mat = bpy.data.materials.get(nombre)
    if mat:
        bpy.data.materials.remove(mat)
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    nt = mat.node_tree
    b = ROBOT['nodoPrincipled'](mat)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = imagen
    b.inputs['Roughness'].default_value = rugosidad
    if emision:
        b.inputs['Base Color'].default_value = (0, 0, 0, 1)
        nt.links.new(tex.outputs['Color'], b.inputs['Emission Color'])
        b.inputs['Emission Strength'].default_value = emision
    else:
        nt.links.new(tex.outputs['Color'], b.inputs['Base Color'])
    if transparente:
        nt.links.new(tex.outputs['Alpha'], b.inputs['Alpha'])
        for prop, valor in (('surface_render_method', 'BLENDED'), ('use_backface_culling', False)):
            try:
                setattr(mat, prop, valor)
            except (AttributeError, TypeError):
                pass
    mat.use_fake_user = True
    return mat


def cajaLocal(bm, centro, tamano, bisel=0.0, giroZ=0.0):
    """Caja biselada añadida a `bm` (hecha aparte, para biselar solo ella)."""
    caja_ = bmesh.new()
    bmesh.ops.create_cube(caja_, size=1.0)
    bmesh.ops.scale(caja_, vec=Vector(tamano), verts=caja_.verts)
    if bisel:
        bmesh.ops.bevel(caja_, geom=caja_.edges[:], offset=min(bisel, min(tamano) * 0.45), segments=2, affect='EDGES', profile=0.5)
    bmesh.ops.rotate(caja_, verts=caja_.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(giroZ, 3, 'Z'))
    bmesh.ops.translate(caja_, vec=Vector(centro), verts=caja_.verts)
    me = bpy.data.meshes.new('tmp')
    caja_.to_mesh(me)
    caja_.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def cilindroLocal(bm, a, b, radio, lados=24):
    a, b = Vector(a), Vector(b)
    eje = b - a
    nuevo = bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=radio, radius2=radio, depth=eje.length)['verts']
    giro = eje.normalized().to_track_quat('Z', 'Y').to_matrix()
    bmesh.ops.rotate(bm, verts=nuevo, cent=(0, 0, 0), matrix=giro)
    bmesh.ops.translate(bm, vec=(a + b) / 2, verts=nuevo)


# Geometría --------------------------------------------------------------------

def regionCara(bm, hasta=HUECO_HASTA):
    """Deja en `bm` solo el trozo de la cara detrás del vidrio."""
    vx0, vx1, vz0, vz1 = VISOR
    for punto, normal in (((vx0, 0, 0), (-1, 0, 0)), ((hasta, 0, 0), (1, 0, 0)), ((0, 0, vz0), (0, 0, -1)), ((0, 0, vz1), (0, 0, 1))):
        cortar(bm, punto, normal)


def uvCara(objeto):
    """u: vuelta alrededor de la cara (ángulo desde x = 18), v: alto del vidrio."""
    vx0, vx1, vz0, vz1 = VISOR
    me = objeto.data
    capa = me.uv_layers.new(name='UV')
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            a = math.atan2(co.y, co.x - 18.0)
            capa.data[li].uv = (0.5 + a / math.radians(150), (co.z - vz0) / (vz1 - vz0))


def abrirCara(casco, m):
    """Agujero en la piel detrás del vidrio (hasta HUECO_HASTA) y paredes que
    bajan FONDO por la normal."""
    vx0, vx1, vz0, vz1 = VISOR
    bm = bmesh.new()
    bm.from_mesh(casco.data)
    for punto, normal in (((vx0, 0, 0), (1, 0, 0)), ((HUECO_HASTA, 0, 0), (1, 0, 0)), ((0, 0, vz0), (0, 0, 1)), ((0, 0, vz1), (0, 0, 1))):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=punto, plane_no=normal)
    bm.normal_update()
    normales = {v: v.normal.copy() for v in bm.verts}
    fuera = [f for f in bm.faces if (lambda c: vx0 < c.x < HUECO_HASTA and vz0 < c.z < vz1)(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=fuera, context='FACES')
    borde = [e for e in bm.edges if e.is_boundary]
    salida = bmesh.ops.extrude_edge_only(bm, edges=borde)
    nuevos = [g for g in salida['geom'] if isinstance(g, bmesh.types.BMVert)]
    paredes = [g for g in salida['geom'] if isinstance(g, bmesh.types.BMFace)]
    for v in nuevos:
        origen = next((e.other_vert(v) for e in v.link_edges if e.other_vert(v) in normales), None)
        v.co -= (normales[origen] if origen else Vector((0, 0, 1))) * (FONDO + 0.02)
    nombres = [mat.name for mat in casco.data.materials]
    if m['negroMate'].name not in nombres:
        casco.data.materials.append(m['negroMate'])
        nombres.append(m['negroMate'].name)
    for f in paredes:
        f.material_index = nombres.index(m['negroMate'].name)
    bm.to_mesh(casco.data)
    bm.free()
    casco.data.update()


def etapaCaraConsola(raiz, casco, m):
    for n in [o.name for o in raiz.children if o.name.startswith(('pantallaCodigo', 'placaCircuitos', 'componentes', 'luces'))]:
        bpy.data.objects.remove(bpy.data.objects[n])
    abrirCara(casco, m)
    # El marco del visor: solo el aro de alrededor del vidrio.
    vx0, vx1, vz0, vz1 = VISOR
    marco = bpy.data.objects['visorMarco']
    bm = bmesh.new()
    bm.from_mesh(marco.data)
    for punto, normal in (((vx0, 0, 0), (1, 0, 0)), ((0, 0, vz0), (0, 0, 1)), ((0, 0, vz1), (0, 0, 1))):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=punto, plane_no=normal)
    dentro = [f for f in bm.faces if (lambda c: c.x > vx0 and vz0 < c.z < vz1)(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=dentro, context='FACES')
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.04)
    bm.to_mesh(marco.data)
    bm.free()
    visor = bpy.data.objects['visor']
    visor.data.materials.clear()
    visor.data.materials.append(materialVidrio())
    visor['detalle'] = 1
    # 1. Pantalla de código.
    def pantalla(bm):
        cascoMorro(bm, -PANTALLA)
        regionCara(bm, HUECO_HASTA - 0.15)

    o = malla('pantallaCodigo', pantalla)
    uvCara(o)
    o.data.materials.append(materialImagen('pantallaCodigo', texturaHud(), emision=3.5, transparente=True))
    marcar(o, raiz)
    # 2. Placa de circuitos al fondo.
    def placa(bm):
        cascoMorro(bm, -FONDO)
        regionCara(bm, HUECO_HASTA + 0.3)

    o = malla('placaCircuitos', placa)
    uvCara(o)
    o.data.materials.append(materialImagen('placaCircuitos', texturaPlaca(), rugosidad=0.45))
    marcar(o, raiz)
    bpy.context.view_layer.update()
    fondo = arbol(o)
    # Componentes sobre la placa: chips, condensadores y luces.
    import random
    rnd = random.Random(3)
    chips, conds, luces = [], [], {n: [] for n, _ in COLORES_LUCES}
    for _ in range(900):
        # Puntos de la cara, disparados desde fuera hacia el eje del morro.
        x = rnd.uniform(vx0 + 0.3, HUECO_HASTA - 0.2)
        z = rnd.uniform(vz0 + 0.15, vz1 - 0.15)
        a = rnd.uniform(-1.3, 1.3)
        desde = Vector((x + math.cos(a) * 8, math.sin(a) * 8, z))
        hacia = Vector((x, 0, z)) - desde
        g = sobre(fondo, desde, hacia)
        if not g:
            continue
        punto, normal = g
        tipo = rnd.random()
        mt = Matrix.Translation(punto) @ normal.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        if tipo < 0.25:
            chips.append((mt, rnd.uniform(0.08, 0.22), rnd.uniform(0.06, 0.16)))
        elif tipo < 0.4:
            conds.append((mt, rnd.uniform(0.025, 0.05), rnd.uniform(0.05, 0.12)))
        elif tipo < 0.52:
            # Sobre todo verdes (la cara de la foto es verde); el resto, pocas.
            color = 'lucesVerde' if rnd.random() < 0.45 else rnd.choice(COLORES_LUCES)[0]
            luces[color].append((mt, rnd.uniform(0.018, 0.032)))

    def ponerCajas(lista, alto):
        def hacer(bm):
            for mt, a, b in lista:
                tmp = bmesh.new()
                cajaLocal(tmp, (0, 0, alto / 2), (a, b, alto), 0.006)
                tmp.transform(mt)
                me = bpy.data.meshes.new('tmp')
                tmp.to_mesh(me)
                tmp.free()
                bm.from_mesh(me)
                bpy.data.meshes.remove(me)
        return hacer

    o = malla('componentesChips', ponerCajas(chips, 0.025))
    o.data.materials.append(m['negro'])
    marcar(o, raiz)

    def cilindros(bm):
        for mt, r, h in conds:
            tmp = bmesh.new()
            cilindroLocal(tmp, (0, 0, 0), (0, 0, h), r, 12)
            tmp.transform(mt)
            me = bpy.data.meshes.new('tmp')
            tmp.to_mesh(me)
            tmp.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)

    o = malla('componentesCondensadores', cilindros)
    o.data.materials.append(m['plata'])
    marcar(o, raiz)
    for nombre, color in COLORES_LUCES:
        lista = [(mt, r, r) for mt, r in luces[nombre]]

        def esferas(bm, lista=lista):
            for mt, r, _ in lista:
                tmp = bmesh.new()
                bmesh.ops.create_uvsphere(tmp, u_segments=10, v_segments=6, radius=r)
                bmesh.ops.translate(tmp, vec=(0, 0, r * 0.5), verts=tmp.verts)
                tmp.transform(mt)
                me = bpy.data.meshes.new('tmp')
                tmp.to_mesh(me)
                tmp.free()
                bm.from_mesh(me)
                bpy.data.meshes.remove(me)

        o = malla(nombre, esferas)
        o.data.materials.append(materialLuz('luz' + nombre[6:], color, 12.0))
        marcar(o, raiz)


# Fuselaje ---------------------------------------------------------------------

def etapaFuselajeDetalle():
    """El fuselaje como cuerpo de robot (el dueño, 20-nov: «eso no es
    robótico, parece instalación humana»; eligió «cuerpo de placas
    encajadas»): el casco pasa a ser el cuerpo interior (metal oscuro) y
    encima van los segmentos de blindaje (etapaPlacasFuselaje). Quedan las
    bisagras de acero de las puertas de pétalo."""
    m = materialesCasa()
    raiz = etapaFuselaje()
    for o in [raiz] + list(raiz.children_recursive):
        if o.type == 'MESH':
            o.data.materials.clear()
            o.data.materials.append(m['negro'])
    sueltos = []
    for lado in (1, -1):
        for z in (2.6, 4.4, 6.2):
            sueltos.append(ROBOT['cilindro']('bisagra', (-BODEGA_DELANTE, lado * (FUSELAJE_MEDIO + 0.2), z), 0.13, 0.5, m['acero'], lados=24, bisel=0.02))
    fundir('bisagrasPuertas', sueltos, raiz)
    # Las placas encajadas (etapaPlacasFuselaje) se quitaron: al dueño le
    # parecieron horribles (20-nov). El código queda para no repetirlo.
    return raiz


# Cuerpo de placas encajadas ---------------------------------------------------
#
# La piel se cubre de segmentos de blindaje: cuadriláteros irregulares (las
# esquinas movidas al azar, en filas al tresbolillo) con alguna esquina en
# chaflán, separados por una rendija oscura. Cada placa sigue la curva del
# casco (sus puntos se proyectan con rayos sobre él), tiene grosor y canto
# biselado, y su borde de atrás se levanta un poco sobre la siguiente, como
# escamas. Algunas faltan: en ese hueco se ve la mecánica. Por las rendijas
# corren cables y pistones. Se construye todo en una malla por material.

RENDIJA = 0.09


class Malla:
    """Acumula geometría en un bmesh por material y la vuelca al final."""

    def __init__(self):
        self.bms = {}

    def bm(self, material):
        return self.bms.setdefault(material, bmesh.new())

    def volcar(self, nombre, padre, recalcular=True):
        """`recalcular`: normales de bmesh (solo en cerrados; las
        superficies abiertas ya traen la suya)."""
        salida = []
        for material, bm in self.bms.items():
            if recalcular:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            me = bpy.data.meshes.new('%s_%s' % (nombre, material.name))
            bm.to_mesh(me)
            bm.free()
            o = bpy.data.objects.new(me.name, me)
            me.materials.append(material)
            ROBOT['suave'](o)
            salida.append(marcar(o, padre))
        return salida


def placaCurva(bm, poligono, mapa, alto, grosor, levantar, bisel=0.05, pasos=4):
    """Placa sólida sobre la piel: `poligono` en coordenadas de la piel
    (u, v en metros), `mapa(u, v)` -> (punto, normal). La cara de arriba
    está `alto + grosor` sobre la piel (más `levantar` en el borde de
    atrás, el de u menor) y algo encogida (`bisel`): canto inclinado."""
    c = Vector((sum(p[0] for p in poligono) / len(poligono), sum(p[1] for p in poligono) / len(poligono)))
    borde = []
    for a, b in zip(poligono, poligono[1:] + poligono[:1]):
        for k in range(pasos):
            borde.append(Vector(a).lerp(Vector(b), k / pasos))
    umin = min(p[0] for p in poligono)
    umax = max(p[0] for p in poligono)
    tam = max(umax - umin, 0.3)

    def punto(q, h):
        g = mapa(q.x, q.y)
        if not g:
            return None
        p, n = g
        extra = levantar * (umax - q.x) / tam
        return p + n * (h + extra)

    def anillo(f, h):
        return [punto(c.lerp(q, f), h) for q in borde]

    capas = [
        (anillo(1.0, alto), anillo(1.0 - bisel * 2.2 / tam if tam > 0 else 1.0, alto + grosor)),
    ]
    abajo, arriba = capas[0]
    medio = anillo(0.5, alto + grosor)
    centro = punto(c, alto + grosor)
    centroAbajo = punto(c, alto)
    if None in abajo or None in arriba or None in medio or centro is None or centroAbajo is None:
        return False
    va = [bm.verts.new(p) for p in abajo]
    vr = [bm.verts.new(p) for p in arriba]
    vm = [bm.verts.new(p) for p in medio]
    vc = bm.verts.new(centro)
    vca = bm.verts.new(centroAbajo)
    n = len(borde)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((va[i], va[j], vr[j], vr[i]))     # canto
        bm.faces.new((vr[i], vr[j], vm[j], vm[i]))     # arriba, fuera
        bm.faces.new((vm[i], vm[j], vc))               # arriba, centro
        bm.faces.new((va[j], va[i], vca))              # abajo
    return True


def poligonoPlaca(u0, u1, v0, v1, rnd, rendija):
    """Cuadrilátero irregular entre (u0..u1, v0..v1) con la rendija y
    alguna esquina en chaflán (formas de blindaje, nunca rectángulos)."""
    def mover(u, v):
        return (u + rnd.uniform(-0.18, 0.18), v + rnd.uniform(-0.12, 0.12))
    esquinas = [mover(u0, v0), mover(u1, v0), mover(u1, v1), mover(u0, v1)]
    # Rendija: encoger hacia el centro.
    cu = sum(p[0] for p in esquinas) / 4
    cv = sum(p[1] for p in esquinas) / 4
    pts = []
    for k, (u, v) in enumerate(esquinas):
        du, dv = u - cu, v - cv
        l = math.hypot(du, dv)
        f = max(l - rendija, 0.05) / l
        pts.append((cu + du * f, cv + dv * f))
    salida = []
    for k, p in enumerate(pts):
        if rnd.random() < 0.45:
            a, b, c = Vector(pts[k - 1]), Vector(p), Vector(pts[(k + 1) % 4])
            ch = rnd.uniform(0.15, 0.4)
            salida.append(tuple(b.lerp(a, min(ch / max((a - b).length, 0.01), 0.45))))
            salida.append(tuple(b.lerp(c, min(ch / max((c - b).length, 0.01), 0.45))))
        else:
            salida.append(p)
    return salida


def revestir(nombre, mapa, uRango, vRango, m, padre, semilla, filas, largos=(1.6, 3.0), hueco=0.1, sombra=None):
    """Cubre la piel con placas en filas (v) al tresbolillo (u). `mapa` da
    (punto, normal) en la piel; `sombra(u, v)` dice dónde no poner (tapado).
    Devuelve los objetos (uno por material)."""
    import random
    rnd = random.Random(semilla)
    malla_ = Malla()
    sueltos = []
    alto = (vRango[1] - vRango[0]) / filas
    for f in range(filas):
        v0 = vRango[0] + f * alto
        v1 = v0 + alto
        u = uRango[0] - rnd.uniform(0, largos[0])
        while u < uRango[1]:
            l = rnd.uniform(*largos)
            u0, u1 = max(u, uRango[0]), min(u + l, uRango[1])
            u += l
            if u1 - u0 < 0.4:
                continue
            uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
            if sombra and sombra(uc, vc):
                continue
            if rnd.random() < hueco:
                # Hueco: la mecánica a la vista.
                g = mapa(uc, vc)
                if g:
                    p, n = g
                    t, b = marcoEn(p, n)
                    mecanica(p + n * 0.02, n, t, b, (u1 - u0) * 0.8, alto * 0.8, rnd, m, sueltos)
                continue
            r = rnd.random()
            mat = m['negro'] if r < 0.75 else m['articulacion'] if r < 0.93 else m['plata']
            poli = poligonoPlaca(u0, u1, v0, v1, rnd, RENDIJA)
            # Alturas muy distintas entre vecinas: relieve en capas, no baldosas.
            base = rnd.choice((0.03, 0.03, 0.08, 0.16, 0.26))
            grosor = rnd.uniform(0.08, 0.2)
            placaCurva(malla_.bm(mat), poli, mapa, base, grosor, rnd.uniform(0.04, 0.18))
            # Las altas dejan ver por debajo el canto: un pistón o un cable.
            if base > 0.1 and rnd.random() < 0.6:
                g1, g2 = mapa(u0 + 0.2, vc + rnd.uniform(-0.2, 0.2)), mapa(u0 - 0.4, vc)
                if g1 and g2:
                    tmp = bmesh.new()
                    cilindroLocal(tmp, g1[0] + g1[1] * (base * 0.6), g2[0] + g2[1] * 0.05, 0.05, 12)
                    me = bpy.data.meshes.new('tmp')
                    tmp.to_mesh(me)
                    tmp.free()
                    malla_.bm(m['plata']).from_mesh(me)
                    bpy.data.meshes.remove(me)
            # A veces, una placa más pequeña encima (segunda capa).
            if rnd.random() < 0.45:
                cu, cv = uc + rnd.uniform(-0.2, 0.2), vc + rnd.uniform(-0.1, 0.1)
                w, h = (u1 - u0) * rnd.uniform(0.3, 0.5), alto * rnd.uniform(0.3, 0.55)
                poli2 = poligonoPlaca(cu - w / 2, cu + w / 2, cv - h / 2, cv + h / 2, rnd, 0.02)
                placaCurva(malla_.bm(m['negro'] if mat != m['negro'] else m['articulacion']), poli2, mapa, base + grosor, rnd.uniform(0.05, 0.12), 0.06, bisel=0.03, pasos=3)
            # Pernos en dos esquinas del borde de delante.
            if rnd.random() < 0.5:
                for vv in (v0 + 0.25, v1 - 0.25):
                    g = mapa(u1 - 0.3, vv)
                    if g:
                        p, n = g
                        sueltos += ROBOT['perno']('perno', p + n * (base + grosor + 0.01), n, m, radio=0.045, material='laton' if rnd.random() < 0.3 else 'acero')
    return malla_.volcar(nombre, padre) + fundir(nombre + 'Mecanica', sueltos, padre)


def etapaPlacasFuselaje(raiz, m):
    """Placas sobre el fuselaje fijo (x de -16,5 a 16,5): la piel se
    recorre con (u = x, v = arco alrededor de la sección); el punto sale de
    un rayo desde el eje hacia fuera. Cables por algunas rendijas."""
    fus = bpy.data.objects['fuselaje']
    bpy.context.view_layer.update()
    bvh = arbol(fus)
    zc = (SECCIONES[0][1] + SECCIONES[0][2]) / 2
    radio = 4.6 # para pasar arco (m) a ángulo

    def mapa(u, v):
        a = v / radio
        g = sobre(bvh, (u, 0, zc), (0, math.cos(a), math.sin(a)))
        if not g:
            return None
        p, n = g
        return p, -n if n.dot(Vector((0, math.cos(a), math.sin(a)))) < 0 else n

    ocluyentes = [arbol(bpy.data.objects[n]) for n in ('alaI', 'alaD', 'carenadoRaiz', 'carenadoI', 'carenadoD') if n in bpy.data.objects]

    def sombra(u, v):
        g = mapa(u, v)
        if not g:
            return True
        p, n = g
        fuera = p + n * 4
        return any(sobre(o, fuera, -n) and (sobre(o, fuera, -n)[0] - fuera).length < 3.9 for o in ocluyentes)

    vuelta = 2 * math.pi * radio
    revestir('placasFuselaje', mapa, (-16.4, 16.4), (-vuelta / 2, vuelta / 2), m, raiz, 21, 22, sombra=sombra)
    # Cables por las rendijas largas (bajo el borde de las placas).
    cables = Malla()
    for k in range(0, 22, 3):
        v = -vuelta / 2 + k * vuelta / 22
        pts = []
        for x in [16.0 - 1.0 * i for i in range(33)]:
            g = mapa(x, v)
            if g:
                pts.append(g[0] + g[1] * 0.06)
        if len(pts) > 2:
            tubo(cables.bm(m['negroMate'] if k % 2 else m['cobre']), pts, 0.045, 8)
    cables.volcar('cablesFuselaje', raiz)


# Ala y motores ----------------------------------------------------------------

def etapaAlaDetalle():
    """El ala: juntas de costillas (en y) y la bisagra de los elevones,
    1,6 m por delante de cada tramo recto del borde de salida en W; franja
    blanca cerca de cada punta (la de la casa)."""
    m = materialesCasa()
    raiz = etapaAla()
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        ala = bpy.data.objects['ala' + s]
        ala.data.materials.clear()
        ala.data.materials.append(m['negro'])
        ranuras(ala, [((0, lado * y, 0), (0, 1, 0)) for y in (6.5, 13.2, 19.5, 26.0, 32.0)], m)
        for a, b in zip(ALA, ALA[1:]):
            if a[0] < 4:
                continue # junto al fuselaje, sin elevón
            pa, pb = Vector((a[2], lado * a[0], 0)), Vector((b[2], lado * b[0], 0))
            d = (pb - pa).normalized()
            n = Vector((-d.y, d.x, 0))
            if n.x < 0:
                n = -n # hacia el borde de ataque
            y0, y1 = sorted((lado * a[0], lado * b[0]))
            ranuras(ala, [(pa + n * 1.6, n)], m, limite=lambda c, y0=y0, y1=y1: y0 + 0.3 < c.y < y1 - 0.3)
        chapa('franjaAla' + s, ala, [((0, lado * 33.2, 0), (0, -lado, 0)), ((0, lado * 33.9, 0), (0, lado, 0))], 0.015, 0.015, m['blanco'], ala, bisel=0.004)
    return raiz


def ventilador(nombre, centro, radio, m, padre):
    """Ventilador de motor (pieza móvil): vacío en `centro` con el eje en x
    (gira en x); cono negro con espiral blanca, 22 álabes de acero torcidos
    y estator."""
    vent = marcar(bpy.data.objects.new(nombre, None), padre)
    vent.location = centro
    mv = Malla()
    # Cono negro con la espiral blanca pintada (el dueño, 20-nov, foto de
    # un Rolls-Royce: al girar hace el efecto de remolino; en los aviones
    # reales avisa en tierra de que el motor está en marcha).
    R, largoCono = radio * 0.35, radio * 0.65
    xPunta = radio * 0.24 + largoCono / 2
    conoBm = mv.bm(m['negro'])
    cono = bmesh.ops.create_cone(conoBm, cap_ends=True, segments=64, radius1=R, radius2=0.02, depth=largoCono)['verts']
    bmesh.ops.rotate(conoBm, verts=cono, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    bmesh.ops.translate(conoBm, vec=(radio * 0.24, 0, 0), verts=cono)
    blanco = mv.bm(m['blanco'])
    pasos = 72
    bordes = []
    for i in range(pasos + 1):
        u = i / pasos
        rho = 0.02 + (R - 0.02) * u + 0.006
        x = xPunta - largoCono * u
        giro = u * 1.15 * 2 * math.pi
        media = 0.12 + 0.55 * u # media anchura (rad): fina en la punta, ancha en la base
        bordes.append([blanco.verts.new((x, rho * math.cos(giro + s * media), rho * math.sin(giro + s * media))) for s in (-1, 1)])
    for a_, b_ in zip(bordes, bordes[1:]):
        f = blanco.faces.new((a_[0], a_[1], b_[1], b_[0]))
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.dot(Vector((0, c.y, c.z))) < 0:
            f.normal_flip()
    alabes = mv.bm(m['acero'])
    for j in range(22):
        a0 = 2 * math.pi * j / 22
        vs = []
        for r, giro in ((radio * 0.3, 0.75), (radio * 0.94, 0.35)):
            for lado in (-1, 1):
                for grueso in (-0.012, 0.012):
                    cx = lado * radio * 0.13 * math.cos(giro)
                    ct = lado * radio * 0.13 * math.sin(giro) + grueso
                    aa = a0 + ct / r
                    vs.append(alabes.verts.new((cx, r * math.cos(aa), r * math.sin(aa))))
        orden = (0, 1, 3, 2)
        q0 = [vs[:4][i] for i in orden]
        q1 = [vs[4:][i] for i in orden]
        alabes.faces.new(q0)
        alabes.faces.new(list(reversed(q1)))
        for i in range(4):
            alabes.faces.new((q0[i], q0[(i + 1) % 4], q1[(i + 1) % 4], q1[i]))
    estator = mv.bm(m['articulacion'])
    aro = bmesh.ops.create_cone(estator, cap_ends=True, segments=48, radius1=radio * 0.99, radius2=radio * 0.99, depth=0.08)['verts']
    bmesh.ops.rotate(estator, verts=aro, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    bmesh.ops.translate(estator, vec=(-0.25, 0, 0), verts=aro)
    for o in mv.volcar(nombre, vent):
        o.matrix_parent_inverse.identity()
    return vent


def materialBrasa(m):
    """El fondo de las salidas: el cian de la energía, apagado (un
    resplandor al fondo de la ranura, no una lámpara)."""
    mat = bpy.data.materials.get('brasaMotor')
    if not mat:
        mat = m['nucleo'].copy()
        mat.name = 'brasaMotor'
        for n in mat.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                n.inputs['Emission Strength'].default_value = 1.2
                n.inputs['Base Color'].default_value = (0.0, 0.02, 0.03, 1)
            elif n.type == 'EMISSION':
                n.inputs['Strength'].default_value = 1.2
    return mat


def etapaMotoresDetalle():
    """Motores enterrados como el B-2 (el dueño, 20-nov: las rejillas de
    detrás «se ven feas»; eligió boca en dientes de sierra y canal plano):

    - Boca: la joroba abierta por delante; el labio, una corona que va de la
      joroba a la boca y avanza en dientes de sierra por arriba. Dentro, un
      conducto negro que se estrecha y se redondea hasta el ventilador
      (`ventilador1..4`: vacío en su eje, gira en x; álabes de acero
      torcidos, cono de cobre y estator detrás).
    - Salida: la joroba acaba en una ranura plana de 0,5 m con su marco
      hundido y, al fondo, el brillo de la energía; de ahí al borde de
      salida del ala, un canal de losetas de metal oscuro entre dos bordes
      bajos que se abre y se apaga hacia atrás.
    """
    m = materialesCasa()
    raiz = etapaMotores()
    # La joroba se rehace aquí (abierta por delante y por detrás).
    for o in list(raiz.children):
        bpy.data.objects.remove(o)
    malla_ = Malla()
    negro, oscuro, metal = malla_.bm(m['negro']), malla_.bm(m['negroMate']), malla_.bm(m['articulacion'])
    nucleo = malla_.bm(materialBrasa(m))

    def cara(bm, verts, hacia):
        """Cara con su normal hacia `hacia(centro)` (vector)."""
        f = bm.faces.new(verts)
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.dot(hacia(c)) < 0:
            f.normal_flip()
        return f

    def unirAnillos(bm, a, b, hacia):
        n = len(a)
        for i in range(n):
            cara(bm, (a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]), hacia)

    N = 48
    for k, y in enumerate((MOTORES_Y[1], MOTORES_Y[0], -MOTORES_Y[0], -MOTORES_Y[1])):
        ataque, z, cuerda = estacionAla(y)
        x0 = ataque - 0.1 * cuerda
        x1 = ataque - 0.85 * cuerda

        def seccion(bm, u, escala=1.0, dx=0.0):
            x = x0 + (x1 - x0) * u
            alto = TOMA_ALTO * (1 - u) ** 0.6 + 0.12 + 0.38 * u
            medio = TOMA_ANCHO / 2 * (1 - 0.35 * u)
            base = encimaAla(x, y) - 0.3
            arriba = base + 0.3 + alto
            cz = (base + arriba) / 2
            vs = anillo(bm, x + dx, cz - (cz - base) * escala, cz + (arriba - cz) * escala, medio * escala, n=N, exponente=3)
            for v in vs:
                v.co.y += y
            return vs, (x + dx, y, cz)

        # Joroba sin tapas.
        anillos, centros = [], []
        for i in range(13):
            vs, c = seccion(negro, i / 12)
            anillos.append(vs)
            centros.append(Vector(c))
        for a, b, ca, cb in zip(anillos, anillos[1:], centros, centros[1:]):
            eje = (ca + cb) / 2
            unirAnillos(negro, a, b, lambda p, eje=eje: Vector((0, p.y - eje.y, p.z - eje.z)))
        # Boca: corona del borde de la joroba a la boca en sierra.
        frente, cf = anillos[0], centros[0]
        boca, _ = seccion(negro, 0, 0.8)
        dientes = 4
        for i, v in enumerate(boca):
            a = 2 * math.pi * i / N
            if 0 < a < math.pi:
                # Sierra limpia a lo largo del arco de arriba: 4 dientes de
                # 0,6 m (6 vértices cada uno, rectos de punta a valle).
                s = (a / math.pi * dientes) % 1.0
                v.co.x += 0.6 * (1 - abs(2 * s - 1))
        unirAnillos(negro, frente, boca, lambda p: Vector((1, 0, 0)))
        # Canto de plata en el filo de la boca (tubo fino).
        tubo(malla_.bm(m['plata']), [v.co.copy() for v in boca] + [boca[0].co.copy()], 0.035, 8)
        # Suelo plano de la boca sobre el ala (que no se vea la piel del ala
        # dentro del conducto): forma de D, como las tomas del B-2.
        for v in boca:
            v.co.z = max(v.co.z, encimaAla(v.co.x, v.co.y) + 0.08)
        # Conducto: de la boca a un estadio (dos círculos de 0,85 m unidos),
        # 2,6 m adentro, donde van los dos ventiladores (dos motores por
        # góndola, como el B-2).
        rc, sep = 0.85, 0.85
        zf = encimaAla(x0, y) + 0.95

        def estadio(a):
            d = Vector((math.cos(a), math.sin(a)))
            lo, hi = 0.0, 3.0
            for _ in range(30):
                mid = (lo + hi) / 2
                p_ = d * mid
                qx = max(-sep, min(sep, p_.x))
                if (p_ - Vector((qx, 0))).length <= rc:
                    lo = mid
                else:
                    hi = mid
            return d * lo

        conducto = []
        bocaCo = [v.co.copy() for v in boca]
        for paso in range(1, 7):
            f = paso / 6
            anilloC = []
            for i in range(N):
                a = 2 * math.pi * i / N
                e = estadio(a)
                fin_ = Vector((x0 - 2.6 * f, y + e.x, zf + e.y))
                ini = bocaCo[i].copy()
                ini.x = x0 - 0.05
                anilloC.append(oscuro.verts.new(ini.lerp(fin_, f ** 0.8)))
            conducto.append(anilloC)
        bocaO = [oscuro.verts.new(c) for c in bocaCo]
        todos = [bocaO] + conducto
        for a, b in zip(todos, todos[1:]):
            unirAnillos(oscuro, a, b, lambda p: Vector((0, y - p.y, zf - p.z)))
        cara(oscuro, conducto[-1], lambda p: Vector((1, 0, 0)))
        for letra, dy in (('a', sep), ('b', -sep)):
            ventilador('ventilador%d%s' % (k + 1, letra), (x0 - 2.35, y + dy, zf), rc, m, raiz)
        # Salida: marco hundido 0,3 m y brillo al fondo.
        fin, cfin = anillos[-1], centros[-1]
        dentro, _ = seccion(oscuro, 1, 0.82, 0.0)
        hondo, _ = seccion(oscuro, 1, 0.82, 0.3)
        finO = [oscuro.verts.new(v.co) for v in fin]
        unirAnillos(oscuro, finO, dentro, lambda p: Vector((-1, 0, 0)))
        unirAnillos(oscuro, dentro, hondo, lambda p: Vector((0, cfin.y - p.y, cfin.z - p.z)))
        brillo = [nucleo.verts.new(v.co + Vector((0.01, 0, 0))) for v in hondo]
        cara(nucleo, brillo, lambda p: Vector((-1, 0, 0)))
        # Canal de salida hasta el borde del ala: losetas entre dos bordes.
        ancho0 = TOMA_ANCHO * (1 - 0.35) * 0.82
        largo = cuerda * 0.15
        filas = max(3, int(largo / 0.55))
        for fila in range(filas):
            u0, u1 = fila / filas, (fila + 1) / filas
            xa, xb = x1 - largo * u0 - 0.015, x1 - largo * u1 + 0.015
            anchoF = ancho0 * (1 + 0.25 * (u0 + u1) / 2)
            cols = 4
            for col in range(cols):
                ya = y - anchoF / 2 + anchoF * col / cols + 0.015
                yb = y - anchoF / 2 + anchoF * (col + 1) / cols - 0.015
                if xb < estacionAla(ya)[0] - estacionAla(ya)[2] + 0.05 or xb < estacionAla(yb)[0] - estacionAla(yb)[2] + 0.05:
                    continue
                esq = [(xa, ya), (xb, ya), (xb, yb), (xa, yb)]
                bm_ = metal
                arriba_ = [bm_.verts.new((px, py, encimaAla(px, py) + 0.03)) for px, py in esq]
                abajo_ = [bm_.verts.new((px, py, encimaAla(px, py) - 0.02)) for px, py in esq]
                cara(bm_, arriba_, lambda p: Vector((0, 0, 1)))
                for i in range(4):
                    j = (i + 1) % 4
                    cara(bm_, (arriba_[i], arriba_[j], abajo_[j], abajo_[i]), lambda p, c=Vector(((xa + xb) / 2, (ya + yb) / 2, 0)): Vector((p.x - c.x, p.y - c.y, 0)))
        # Bordes bajos del canal: de 0,25 m en la ranura a nada en el borde.
        for lado in (-1, 1):
            pts = []
            for i in range(9):
                u = i / 8
                x = x1 - largo * u
                yy = y + lado * ancho0 / 2 * (1 + 0.25 * u)
                if x < estacionAla(yy)[0] - estacionAla(yy)[2] + 0.1:
                    break
                pts.append((x, yy, encimaAla(x, yy), 0.25 * (1 - u) + 0.03))
            for a_, b_ in zip(pts, pts[1:]):
                q = [negro.verts.new(v) for v in (
                    (a_[0], a_[1], a_[2] - 0.02), (b_[0], b_[1], b_[2] - 0.02),
                    (b_[0], b_[1] + lado * 0.12, b_[2] + b_[3]), (a_[0], a_[1] + lado * 0.12, a_[2] + a_[3]))]
                cara(negro, q, lambda p, l=lado: Vector((0, -l, 0.3)))
    malla_.volcar('motoresCuerpo', raiz, recalcular=False)
    return raiz


# Bodega ----------------------------------------------------------------------

def barrido(bm, puntos, haciaDentro, ancho, alto):
    """Viga de sección rectangular (`ancho` a lo largo de x, `alto` hacia
    dentro) por `puntos`, con la cara de dentro hacia `haciaDentro(p)`."""
    anillos = []
    for p in puntos:
        n = haciaDentro(p).normalized()
        a = Vector((1, 0, 0)) * (ancho / 2)
        anillos.append([bm.verts.new(p + s * a + n * h) for s, h in ((-1, 0), (1, 0), (1, alto), (-1, alto))])
    for a, b in zip(anillos, anillos[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(anillos[0])
    bm.faces.new(list(reversed(anillos[-1])))


def recortarBodega():
    """Quita de las piezas de fuera (carenados del tren, raíz del ala,
    lomo...) las caras que quedan dentro del casco del fuselaje: desde la
    bodega abierta se veían como bultos en las paredes y el techo. Dentro =
    rayos desde el vértice hacia los dos lados y hacia arriba tocan el casco."""
    fus = bpy.data.objects['fuselaje']
    bpy.context.view_layer.update()
    bvh = arbol(fus)
    propios = {fus.name} | {o.name for o in fus.children_recursive}
    carga = bpy.data.objects.get('carga')
    if carga:
        propios |= {carga.name} | {o.name for o in carga.children_recursive}
    lejos = BODEGA_DELANTE - 0.05

    def dentro(p):
        if not (-lejos < p.x < lejos) or p.z < ALTO_SUELO - 0.3:
            return False
        for d in ((0, 1, 0), (0, -1, 0), (0, 0, 1)):
            if not bvh.ray_cast(p, Vector(d), 20)[0]:
                return False
        return True

    quitadas = 0
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in propios]:
        mw = o.matrix_world
        bm = bmesh.new()
        bm.from_mesh(o.data)
        # Dentro: todos sus vértices, o su centro y la mayoría (las que
        # cruzan el casco dejaban picos sueltos en el techo).
        malas = []
        for f in bm.faces:
            n = sum(dentro(mw @ v.co) for v in f.verts)
            if n == len(f.verts) or (n * 2 > len(f.verts) and dentro(mw @ f.calc_center_median())):
                malas.append(f)
        if malas:
            bmesh.ops.delete(bm, geom=malas, context='FACES')
            bm.to_mesh(o.data)
            quitadas += len(malas)
        bm.free()
    print('BODEGA: quitadas', quitadas, 'caras de dentro del casco')


def etapaBodega():
    """La bodega por dentro, como un carguero de robots (el dueño, 20-nov:
    con la rampa abierta se veía vacía): suelo de chapas sobre metal oscuro
    con cuatro calles de rodillos, costillas de sección cajón que siguen el
    casco cada 1,65 m, largueros, mazos de cables por el techo, tiras de luz
    entre costillas, mamparo delantero con compuerta y núcleo, y peldaños
    antideslizantes en la rampa (cuelgan de `rampa`: se mueven con ella)."""
    m = materialesCasa()
    fus = bpy.data.objects['fuselaje']
    for o in [c for c in fus.children if c.name.startswith('bodega')]:
        for h in [o] + list(o.children_recursive):
            bpy.data.objects.remove(h)
    rampa = bpy.data.objects['rampa']
    for o in [c for c in rampa.children if c.name.startswith('peldanos')]:
        bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    bvh = arbol(fus)
    zc = 4.4
    x0, x1 = -BODEGA_DELANTE + 0.05, BODEGA_DELANTE - 0.15
    suelo = ALTO_SUELO
    malla_ = Malla()
    negro, oscuro, metal = malla_.bm(m['negro']), malla_.bm(m['negroMate']), malla_.bm(m['articulacion'])
    acero = malla_.bm(m['acero'])
    luz = malla_.bm(materialLuz('luzBodega', (0.75, 0.95, 1.0), 6.0))

    def pared(x, grados):
        a = math.radians(grados)
        d = Vector((0, math.cos(a), math.sin(a)))
        g = bvh.ray_cast(Vector((x, 0, zc)), d, 20)
        return g[0] if g[0] else None

    # Ancho del suelo: donde el casco corta z = suelo.
    def anchoSuelo(x):
        g = bvh.ray_cast(Vector((x, 0, suelo + 0.02)), Vector((0, 1, 0)), 20)
        return (g[0].y if g[0] else 4.6) - 0.03

    w = anchoSuelo(0)
    # Suelo: losa oscura y chapas de 2,2 x 1,5 m con junta de 3 cm.
    cajaLocal(oscuro, ((x0 + x1) / 2, 0, suelo - 0.06), (x1 - x0, 2 * w, 0.12))
    nx, ny = int((x1 - x0) / 2.2), 6
    for i in range(nx):
        for j in range(ny):
            xa = x0 + (x1 - x0) * i / nx
            xb = x0 + (x1 - x0) * (i + 1) / nx
            ya = -w + 2 * w * j / ny
            yb = -w + 2 * w * (j + 1) / ny
            cajaLocal(metal, ((xa + xb) / 2, (ya + yb) / 2, suelo - 0.005), (xb - xa - 0.03, yb - ya - 0.03, 0.03), bisel=0.008)
    # Calles de rodillos: dos rieles de acero y rodillos cada 0,6 m.
    for yc in (-3.3, -1.15, 1.15, 3.3):
        for dy in (-0.2, 0.2):
            cajaLocal(acero, ((x0 + x1) / 2, yc + dy, suelo + 0.04), (x1 - x0, 0.05, 0.1), bisel=0.01)
        x = x0 + 0.4
        while x < x1 - 0.3:
            cilindroLocal(negro, (x, yc - 0.17, suelo + 0.05), (x, yc + 0.17, suelo + 0.05), 0.06, 16)
            x += 0.6
    # Anillas de amarre entre las calles.
    for yc in (-2.25, 0.0, 2.25):
        x = x0 + 1.0
        while x < x1 - 0.5:
            cilindroLocal(acero, (x, yc, suelo), (x, yc, suelo + 0.025), 0.07, 16)
            x += 1.65
    # Forro: el casco es de una capa con las caras hacia fuera y el juego no
    # dibuja las caras de espaldas (desde la rampa se veía el ala a través de
    # las paredes). Copia del casco del trozo de la bodega, vuelta hacia
    # dentro y 3 cm más adentro.
    forro = bmesh.new()
    forro.from_mesh(fus.data)
    forro.transform(fus.matrix_world)
    fuera = [f for f in forro.faces if not (x0 - 0.3 < f.calc_center_median().x < x1 + 0.3)]
    bmesh.ops.delete(forro, geom=fuera, context='FACES')
    # Cada cara mirando al eje de la bodega (el casco las tiene mezcladas),
    # y luego 3 cm hacia dentro.
    for f in forro.faces:
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.dot(Vector((0, -c.y, zc - c.z))) < 0:
            f.normal_flip()
    for v in forro.verts:
        hacia = Vector((0, -v.co.y, zc - v.co.z))
        if hacia.length > 0:
            v.co += hacia.normalized() * 0.03
    me = bpy.data.meshes.new('tmp')
    forro.to_mesh(me)
    forro.free()
    mallaForro = Malla()
    mallaForro.bm(m['negroMate']).from_mesh(me)
    bpy.data.meshes.remove(me)
    # Costillas: viga cajón que sigue el casco, de suelo a suelo.
    angulos = [-12 + k * 6 for k in range(35)] # -12..192
    x = x0 + 0.5
    while x < x1:
        pts = [pared(x, a) for a in angulos]
        pts = [p for p in pts if p and p.z > suelo + 0.05]
        if len(pts) > 3:
            barrido(negro, pts, lambda p: Vector((0, -p.y, zc - p.z)), 0.16, 0.22)
        x += 1.65
    # Largueros y cables a lo largo (por fuera de las costillas, pegados al casco).
    for a, radio, bm_ in ((15, 0.05, acero), (45, 0.05, acero), (135, 0.05, acero), (165, 0.05, acero),
                          (68, 0.06, malla_.bm(m['cobre'])), (72, 0.05, oscuro), (76, 0.05, oscuro),
                          (104, 0.05, oscuro), (108, 0.05, oscuro), (112, 0.06, malla_.bm(m['cobre']))):
        pts = []
        for k in range(23):
            xx = x0 + 0.2 + (x1 - x0 - 0.4) * k / 22
            p = pared(xx, a)
            if p:
                pts.append(p + Vector((0, -p.y, zc - p.z)).normalized() * (radio + 0.03))
        tubo(bm_, pts, radio, 10)
    # Tiras de luz en el techo, entre costillas.
    for a in (82, 98):
        x = x0 + 0.5 + 0.2
        while x + 1.25 < x1:
            pa, pb = pared(x, a), pared(x + 1.25, a)
            if pa and pb:
                n = Vector((0, -pa.y, zc - pa.z)).normalized()
                c = (pa + pb) / 2 + n * 0.06
                cajaLocal(luz, c, (1.2, 0.18, 0.05))
            x += 1.65
    # Mamparo delantero: chapa que llena la sección, compuerta y núcleo.
    xm = x1 + 0.1
    pts = [pared(xm, a) for a in range(-12, 193, 4)]
    pts = [p for p in pts if p and p.z > suelo - 0.1]
    plato = [negro.verts.new((xm, p.y, p.z)) for p in pts]
    plato.append(negro.verts.new((xm, pts[-1].y, suelo - 0.1)))
    plato.append(negro.verts.new((xm, pts[0].y, suelo - 0.1)))
    f = negro.faces.new(plato)
    f.normal_update()
    if f.normal.x > 0:
        f.normal_flip()
    cajaLocal(oscuro, (xm - 0.04, 0, suelo + 1.6), (0.06, 2.4, 3.2), bisel=0.02)
    for dz in (-1.63, 1.63):
        cajaLocal(malla_.bm(m['plata']), (xm - 0.08, 0, suelo + 1.6 + dz), (0.06, 2.6, 0.1), bisel=0.02)
    for dy in (-1.25, 1.25):
        cajaLocal(malla_.bm(m['plata']), (xm - 0.08, dy, suelo + 1.6), (0.06, 0.1, 3.36), bisel=0.02)
    cilindroLocal(malla_.bm(m['nucleo']), (xm - 0.1, 2.3, suelo + 1.9), (xm - 0.04, 2.3, suelo + 1.9), 0.22, 32)
    cilindroLocal(malla_.bm(m['plata']), (xm - 0.08, 2.3, suelo + 1.9), (xm - 0.03, 2.3, suelo + 1.9), 0.3, 32)
    raiz = marcar(bpy.data.objects.new('bodega', None), fus)
    raiz.matrix_parent_inverse = fus.matrix_world.inverted()
    for o in malla_.volcar('bodega', raiz):
        o.matrix_parent_inverse = raiz.matrix_world.inverted()
    # El forro ya trae sus normales (hacia dentro): sin recalcular.
    for o in mallaForro.volcar('bodegaForro', raiz, recalcular=False):
        o.matrix_parent_inverse = raiz.matrix_world.inverted()
    # Peldaños de la rampa: con la rampa abierta (en la pista), rayos hacia
    # abajo sobre su piel; luego cuelgan de la rampa y vuelve la pose.
    poseCarga(1, 1)
    bpy.context.view_layer.update()
    piel = bpy.data.objects['rampaPiel']
    bvhR = arbol(piel)

    def pielEn(x, y):
        g = bvhR.ray_cast(Vector((x, y, 10)), Vector((0, 0, -1)), 20)
        return g[0].z if g[0] else None

    # Piso de la rampa: recta del suelo de la bodega (bisagra) a la punta,
    # sin bajar nunca de la piel curva (por los lados sube).
    xs = [-BODEGA_DELANTE - 0.02 - k * 0.3 for k in range(40)]
    xs = [x for x in xs if pielEn(x, 0) is not None]
    xPunta = xs[-1] + 0.15
    zPunta = pielEn(xs[-1], 0) + 0.05
    anchoR = 4.3

    def piso(x, y):
        u = (-BODEGA_DELANTE - x) / (-BODEGA_DELANTE - xPunta)
        z = suelo + (zPunta - suelo) * u
        zp = pielEn(x, y)
        return max(z, (zp + 0.04) if zp is not None else z)

    mr = Malla()
    deck = mr.bm(m['articulacion'])
    def anchoEn(x):
        # Hasta donde hay piel a los lados (la punta es más estrecha).
        y = 0.0
        while y < anchoR and pielEn(x, y + 0.1) is not None and pielEn(x, -y - 0.1) is not None:
            y += 0.1
        return max(y - 0.1, 0.5)

    filas = []
    for x in xs:
        w = anchoEn(x)
        filas.append([deck.verts.new((x, y, piso(x, y))) for y in [-w + 2 * w * j / 10 for j in range(11)]])
    for a, b in zip(filas, filas[1:]):
        for j in range(10):
            f = deck.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
    # Peldaños sobre el piso: listones de acero cruzados cada 0,55 m.
    pasos = mr.bm(m['acero'])
    x = -BODEGA_DELANTE - 0.6
    while x > xPunta + 0.3:
        pendiente = math.atan2(piso(x + 0.05, 0) - piso(x - 0.05, 0), 0.1)
        w = anchoEn(x)
        for yc in (-3.3, -1.15, 1.15, 3.3):
            if abs(yc) + 0.65 > w:
                continue
            caja_ = bmesh.new()
            bmesh.ops.create_cube(caja_, size=1.0)
            bmesh.ops.scale(caja_, vec=(0.08, 1.3, 0.05), verts=caja_.verts)
            bmesh.ops.rotate(caja_, verts=caja_.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-pendiente, 3, 'Y'))
            bmesh.ops.translate(caja_, vec=(x, yc, max(piso(x, yc - 0.6), piso(x, yc + 0.6), piso(x, yc)) + 0.025), verts=caja_.verts)
            me = bpy.data.meshes.new('tmp')
            caja_.to_mesh(me)
            caja_.free()
            pasos.from_mesh(me)
            bpy.data.meshes.remove(me)
        x -= 0.55
    for o in mr.volcar('peldanosRampa', None):
        mundo = o.matrix_world.copy()
        o.parent = rampa
        o.matrix_world = mundo
    poseCarga(0, 0)
    bpy.context.view_layer.update()
    return raiz


# Tren y cola -----------------------------------------------------------------

def torneado(bm, perfil, lados=128):
    """Sólido de revolución alrededor del eje Y local: `perfil` = [(r, y)]
    de un lado al otro (abierto: se cierra con las tapas en el eje)."""
    vs = [bm.verts.new((r, y, 0)) for r, y in perfil]
    aristas = [bm.edges.new((a, b)) for a, b in zip(vs, vs[1:])]
    bmesh.ops.spin(bm, geom=vs + aristas, cent=(0, 0, 0), axis=(0, 1, 0), angle=2 * math.pi, steps=lados, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def perfilNeumatico(radio, ancho, llanta):
    """Neumático de avión: flancos rectos, hombro redondo (superelipse) y
    tres surcos en la banda (los de los neumáticos de avión, en línea)."""
    w = ancho / 2
    puntos = []
    n = 40
    for k in range(n + 1):
        y = -w + 2 * w * k / n
        u = abs(y) / w
        r = llanta + (radio - llanta) * max(1 - u ** 6, 0.0) ** (1 / 6)
        for g in (-0.33, 0.0, 0.33):
            if abs(y / w - g) < 0.06 and r > radio - 0.03:
                r -= 0.03
        puntos.append((r, y))
    return [(llanta, -w)] + puntos + [(llanta, w)]


def rueda(nombre, centro, radio, ancho, m, padre, haciaFuera):
    """Rueda con su eje en `centro` (gira en Y): neumático, llanta plateada
    con 10 tuercas y tapacubos. Un objeto por material, colgados de un
    vacío `nombre` en el eje (eso es lo que gira desde Lua)."""
    eje = vacio(nombre, padre)
    eje.location = centro
    llanta = radio * 0.62
    goma = bpy.data.objects.new(nombre + 'Goma', bpy.data.meshes.new(nombre + 'Goma'))
    bm = bmesh.new()
    torneado(bm, perfilNeumatico(radio, ancho, llanta - 0.02))
    bm.to_mesh(goma.data)
    bm.free()
    goma.data.materials.append(m['goma'])
    ROBOT['suave'](goma)
    marcar(goma, eje)
    piezas = []
    cara = haciaFuera * (ancho / 2 - 0.03)
    # Llanta: disco con la cara hundida y el aro saliente.
    llantaO = bpy.data.objects.new(nombre + 'Llanta', bpy.data.meshes.new(nombre + 'Llanta'))
    bm = bmesh.new()
    torneado(bm, [(0.0, -ancho / 2 + 0.04), (llanta * 0.98, -ancho / 2 + 0.04), (llanta, -ancho / 2 + 0.07), (llanta, ancho / 2 - 0.07), (llanta * 0.98, ancho / 2 - 0.04), (llanta * 0.4, ancho / 2 - 0.08), (0.0, ancho / 2 - 0.08)], 64)
    if haciaFuera < 0:
        bmesh.ops.scale(bm, vec=(1, -1, 1), verts=bm.verts)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(llantaO.data)
    bm.free()
    llantaO.data.materials.append(m['plata'])
    ROBOT['suave'](llantaO)
    marcar(llantaO, eje)
    for k in range(10):
        a = 2 * math.pi * k / 10
        piezas += ROBOT['perno']('tuerca', (math.cos(a) * llanta * 0.62, cara - haciaFuera * 0.03, math.sin(a) * llanta * 0.62), (0, haciaFuera, 0), m, radio=0.035, material='acero')
    piezas.append(ROBOT['cilindro']('tapacubos', (0, cara - haciaFuera * 0.03, 0), llanta * 0.3, 0.08, m['acero'], eje='y', lados=48, bisel=0.02))
    # Hechas alrededor del origen: colgadas del eje quedan en su sitio.
    fundir(nombre + 'Tuercas', piezas, eje)
    return eje


def etapaTrenDetalle():
    """El tren con ruedas de verdad (radio 0,8 m las principales, 0,65 la
    de proa), patas amortiguadoras (cilindro de acero y vástago plateado)
    del eje al carenado y ejes. Para Lua: cada rueda es un vacío
    `rueda<Lado><Eje><a/b>` / `ruedaProa<a-d>` en su eje, gira en Y."""
    m = materialesCasa()
    raiz = etapaTren()
    for o in list(raiz.children):
        if o.name.startswith(('rueda', 'pataProa')):
            bpy.data.objects.remove(o)
        else:
            o.data.materials.clear()
            o.data.materials.append(m['negro'])
    sueltos = []
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        for k, x in enumerate((-5.1, -1.7, 1.7, 5.1)):
            for j, dy in enumerate((-0.42, 0.42)):
                y = lado * (5.6 + dy)
                rueda('rueda%s%d%s' % (s, k + 1, 'ab'[j]), (x, y, RUEDA_RADIO), RUEDA_RADIO, 0.42, m, raiz, 1 if lado * dy > 0 else -1)
            sueltos.append(ROBOT['cilindro']('eje', (x, lado * 5.6, RUEDA_RADIO), 0.09, 0.5, m['acero'], eje='y', lados=24))
            sueltos.append(ROBOT['cilindro']('pata', (x, lado * 5.6, RUEDA_RADIO + 0.25 + 0.2), 0.13, 0.4, m['plata'], lados=32, bisel=0.02))
            sueltos.append(ROBOT['cilindro']('pataCilindro', (x, lado * 5.6, RUEDA_RADIO + 0.75), 0.17, 0.6, m['articulacion'], lados=32, bisel=0.03))
    for j, dy in enumerate((-1.2, -0.4, 0.4, 1.2)):
        rueda('ruedaProa' + 'abcd'[j], (19.5, dy, 0.65), 0.65, 0.38, m, raiz, 1 if dy > 0 else -1)
    sueltos.append(ROBOT['cilindro']('ejeProa', (19.5, 0, 0.65), 0.08, 2.4, m['acero'], eje='y', lados=24))
    sueltos.append(ROBOT['cilindro']('pataProa', (19.5, 0, 0.65 + 0.45), 0.12, 0.6, m['plata'], lados=32, bisel=0.02))
    sueltos.append(ROBOT['cilindro']('pataProaCilindro', (19.5, 0, 1.55), 0.16, 0.5, m['articulacion'], lados=32, bisel=0.03))
    fundir('patasTren', sueltos, raiz)
    return raiz


def etapaColaDetalle():
    """Garras de la cola: juntas (en z) y franja blanca cerca de la punta;
    luces de posición del avión (roja en la punta del ala izquierda, verde
    en la derecha, destello blanco arriba de cada garra). Para Lua:
    `luzPosicionRoja`, `luzPosicionVerde`, `luzDestello` (parpadeo)."""
    m = materialesCasa()
    raiz = etapaCola()
    for o in raiz.children:
        o.data.materials.clear()
        o.data.materials.append(m['negro'])
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        garra = bpy.data.objects['garra' + s]
        ranuras(garra, [((0, 0, 9.6), (0, 0, 1)), ((0, 0, 11.6), (0, 0, 1))], m)
        chapa('franjaGarra' + s, garra, [((0, 0, 13.0), (0, 0, -1)), ((0, 0, 13.5), (0, 0, 1))], 0.015, 0.015, m['blanco'], garra, bisel=0.004)
        ranuras(bpy.data.objects['estabilizador' + s], [((0, lado * 5.0, 0), (0, 1, 0))], m)
    # Luces de posición.
    puntaAla = estacionAla(ALA_PUNTA_Y)
    for nombre, y, color in (('luzPosicionRoja', ALA_PUNTA_Y, (1.0, 0.05, 0.03)), ('luzPosicionVerde', -ALA_PUNTA_Y, (0.1, 1.0, 0.25))):
        x = puntaAla[0] - puntaAla[2] * 0.3
        o = ROBOT['esfera'](nombre, (x, y + math.copysign(0.05, y), puntaAla[1] + 0.05), 0.12, materialLuz(nombre, color, 14.0), (1.4, 1, 0.7))
        marcar(o, raiz)
    destellos = []
    for lado in (1, -1):
        g = GARRA[-1]
        destellos.append(ROBOT['esfera']('destello', (COLA_X - 2.4 + g[1] - 0.2, lado * (ESTABILIZADOR_Y - g[3]), COLA_ALTO + 0.05), 0.1, materialLuz('luzDestello', (1.0, 1.0, 1.0), 16.0)))
    for o in fundir('luzDestello', destellos, raiz):
        o.name = 'luzDestello'
    return raiz


# Blindaje y mecánica a la vista -----------------------------------------------
#
# El dueño, 20-nov, con una foto de Lockdown: «más robótico, tiene miles de
# cosas». Lo que da ese aspecto (solo la idea): placas de blindaje angulosas
# en capas que siguen la piel, huecos con la mecánica a la vista (pistones,
# mazos de cables, engranajes, un núcleo que brilla) rodeados de placas más
# altas, rejillas, púas de latón y pernos en las esquinas. Se reparte al azar
# (semilla fija) por zonas, sin solaparse y sin poner nada donde lo tapa otra
# pieza (ala, carenados). Todo es fijo: se funde por material y zona.

def marcoEn(p, n, adelante=Vector((1, 0, 0))):
    """Ejes en un punto de la piel: t (hacia delante sobre la piel), b, n."""
    t = adelante - n * adelante.dot(n)
    if t.length < 1e-3:
        t = Vector((0, 1, 0)) - n * n.y
    t.normalize()
    b = n.cross(t)
    return t, b


def tubo(bm, puntos, radio, lados=10):
    for a, c in zip(puntos, puntos[1:]):
        cilindroLocal(bm, a, c, radio, lados)
        bola = bmesh.new()
        bmesh.ops.create_uvsphere(bola, u_segments=lados, v_segments=5, radius=radio)
        bmesh.ops.translate(bola, vec=c, verts=bola.verts)
        me = bpy.data.meshes.new('tmp')
        bola.to_mesh(me)
        bola.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)


def mecanica(p, n, t, b, largo, ancho, rnd, m, piezas):
    """La mecánica de un hueco (plana sobre la piel, que en 2-3 m apenas se
    curva): base oscura, dos pistones, mazo de cables, engranaje y núcleo."""
    def en(u, v, h):
        return p + t * u + b * v + n * h

    def obj(nombre, hacer, mat):
        bm = bmesh.new()
        hacer(bm)
        me = bpy.data.meshes.new(nombre)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(nombre, me)
        me.materials.append(mat)
        bpy.context.scene.collection.objects.link(o)
        piezas.append(o)

    L, A = largo * 0.4, ancho * 0.4
    for v in (-A * 0.55, A * 0.55):
        a, c = en(-L, v, 0.09), en(L * 0.3, v, 0.09)
        obj('piston', lambda bm, a=a, c=c: cilindroLocal(bm, a, c, 0.07, 16), m['articulacion'])
        obj('vastago', lambda bm, c=c, v=v: cilindroLocal(bm, c, en(L * 0.85, v, 0.09), 0.04, 12), m['plata'])
    cables = [en(-L, 0, 0.06), en(-L * 0.3, rnd.uniform(-0.1, 0.1), 0.12), en(L * 0.4, rnd.uniform(-0.1, 0.1), 0.1), en(L, 0, 0.06)]
    for k, dv in enumerate((-0.09, 0.0, 0.09)):
        pts = [q + b * dv + n * 0.01 * k for q in cables]
        obj('cable', lambda bm, pts=pts: tubo(bm, pts, 0.035), m['negroMate'] if k != 1 else m['cobre'])
    g = en(rnd.uniform(-L * 0.5, L * 0.5), rnd.uniform(-A * 0.2, A * 0.2), 0.05)
    giro = Matrix((t, b, n)).transposed()

    def engr(bm):
        engranaje(bm, (0, 0, 0), rnd.uniform(0.18, 0.3), 24, 0.05)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=giro)
        bmesh.ops.translate(bm, vec=g, verts=bm.verts)
    obj('engranaje', engr, m['laton'])
    nucleo = en(-L * 0.6, A * 0.0, 0.05)

    def nuc(bm):
        cajaLocal(bm, (0, 0, 0), (0.22, 0.14, 0.06), 0.02)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=giro)
        bmesh.ops.translate(bm, vec=nucleo, verts=bm.verts)
    obj('nucleo', nuc, m['nucleo'])


def engranaje(bm, centro, radio, dientes, grosor):
    """Rueda dentada recta en el plano XY local, con cubo."""
    modulo = 2 * radio / dientes
    rRaiz, rPunta = radio - 1.1 * modulo, radio + modulo
    contorno_ = []
    paso = 2 * math.pi / dientes
    for k in range(dientes):
        a = paso * k
        for f, r in ((0.0, rRaiz), (0.18, rPunta), (0.45, rPunta), (0.62, rRaiz)):
            contorno_.append((math.cos(a + f * paso) * r, math.sin(a + f * paso) * r))
    rueda_ = bmesh.new()
    vs = [rueda_.verts.new((centro[0] + x, centro[1] + y, centro[2])) for x, y in contorno_]
    cara = rueda_.faces.new(vs)
    salida = bmesh.ops.extrude_face_region(rueda_, geom=[cara])
    arriba = [g for g in salida['geom'] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(rueda_, vec=(0, 0, grosor), verts=arriba)
    bmesh.ops.recalc_face_normals(rueda_, faces=rueda_.faces[:])
    cilindroLocal(rueda_, (centro[0], centro[1], centro[2] - 0.01), (centro[0], centro[1], centro[2] + grosor * 1.8), rRaiz * 0.3, 20)
    me = bpy.data.meshes.new('tmp')
    rueda_.to_mesh(me)
    rueda_.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def puas(puntos, m, piezas, largo=0.7, radio=0.13):
    """Púas de latón con su base oscura: `puntos` = [(punto, dirección)]."""
    for p, d in puntos:
        d = Vector(d).normalized()
        giro = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        for nombre, r1, r2, h, z, mat in (('puaBase', radio * 1.5, radio * 1.2, 0.12, 0.06, m['articulacion']), ('pua', radio, 0.01, largo, 0.12 + largo / 2, m['laton'])):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=r1, radius2=r2, depth=h)
            bmesh.ops.translate(bm, vec=(0, 0, z), verts=bm.verts)
            bm.transform(Matrix.Translation(p) @ giro)
            me = bpy.data.meshes.new(nombre)
            bm.to_mesh(me)
            bm.free()
            o = bpy.data.objects.new(nombre, me)
            me.materials.append(mat)
            bpy.context.scene.collection.objects.link(o)
            piezas.append(o)


def construirDetalle():
    construir()
    colorearCasa()
    etapaMorroDetalle()
    etapaFuselajeDetalle()
    etapaBodega()
    etapaAlaDetalle()
    etapaMotoresDetalle()
    etapaTrenDetalle()
    etapaColaDetalle()
    recortarBodega()

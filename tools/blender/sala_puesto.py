# Un puesto de la sala de control del almacén con todo el detalle (el dueño,
# 26-nov: «al teclado agrégale teclas y el ratón hazlo detallado... las PC,
# pantallas, escritorio y silla bien detallados»), con el estándar de la
# skill vehiculo-detallado: medidas reales, biseles de 2-3 segmentos con
# normales ponderadas, lo redondo con muchos segmentos y texturas reales
# (tools/blender/texturas_sala.py). Lo llama crearPuesto de
# almacen_interior.py.
#
# Medidas (silueta aprobada por el dueño el 26-nov, con el monitor a 32"):
#   * teclado español ISO de 105 teclas (Intro en L, Mayús izquierdo corto
#     con la tecla < al lado, Ñ y Ç), paso de 19,05 mm (Deskthority, «Key
#     pitch»; MonsGeek, «Spanish keyboard layout»), 22,5 x 6,5 unidades,
#     caja de 441 x 136 mm, 18 mm delante y 30 detrás (5° de inclinación);
#   * ratón de 120 x 63 x 38 mm (Perixx 11168: 120 x 63), botones partidos,
#     rueda de goma, dos botones laterales y cable; alfombrilla de 30 x 25;
#   * monitor de 32" (31,5" de panel: 697,3 x 392,2 mm de imagen), marco de
#     8 mm y barbilla de 22 mm, carcasa trasera en tronco de pirámide, VESA,
#     bisagra, columna y base redondeada (proporciones de los de 27" de Dell
#     S2719DC y ViewSonic VA2719 escaladas);
#   * torre ATX media de 210 x 450 x 460 mm con frontal, rejillas, botón con
#     aro de luz, USB-A, USB-C, audio y patas de goma;
#   * mesa de 1,8 x 0,8 m de laminado gris con canto redondeado, pasacables,
#   * marco de acero con niveladores, faldón y bandeja de cables;
#   * silla de oficina con respaldo de malla curvo y apoyo lumbar inclinado
#     12°, asiento de tela a 0,48 m (46-56 cm, Office Depot/Balt), brazos en
#     T, mecanismo con palanca y pomo, pistón con funda telescópica y base de
#     5 radios de aluminio de 0,64 m (≥ 58 cm, Baylor) con ruedas dobles de
#     50 mm (2", UNICOR usa 3").
#
# Ejes: el operador mira a +y (la pantalla está en +y); z arriba; metros.

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

U = 0.01905  # paso de las teclas

# Lo que hay que convertir a malla al acabar (las letras de las teclas).
_textos = []
# Mallas de teclas ya hechas, por forma (se comparten entre los 6 puestos).
_plantillas = {}


# Utilidades --------------------------------------------------------------------

def _suavizar(malla, angulo=32):
    """Caras suaves y aristas duras donde el ángulo pasa de `angulo`."""
    bm = bmesh.new()
    bm.from_mesh(malla)
    limite = math.radians(angulo)
    for cara in bm.faces:
        cara.smooth = True
    for arista in bm.edges:
        arista.smooth = len(arista.link_faces) == 2 and arista.calc_face_angle(0) < limite
    bm.to_mesh(malla)
    bm.free()


def _aplicar(objeto):
    """Aplica los modificadores de `objeto` (su malla pasa a ser la evaluada)."""
    dg = bpy.context.evaluated_depsgraph_get()
    nueva = bpy.data.meshes.new_from_object(objeto.evaluated_get(dg))
    vieja = objeto.data
    objeto.modifiers.clear()
    objeto.data = nueva
    if vieja.users == 0:
        bpy.data.meshes.remove(vieja)


def biselar(objeto, ancho, segmentos=3, angulo=30):
    """Bisel redondo en las aristas de más de `angulo` grados y normales
    ponderadas por el área (los planos grandes quedan planos)."""
    if ancho > 0:
        mod = objeto.modifiers.new('bisel', 'BEVEL')
        mod.width = ancho
        mod.segments = segmentos
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(angulo)
        mod.profile = 0.5
        mod.use_clamp_overlap = True
        _aplicar(objeto)
    _suavizar(objeto.data)
    mod = objeto.modifiers.new('normales', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    mod.mode = 'FACE_AREA'
    _aplicar(objeto)
    return objeto


def _objeto(bm, nombre, material, ctx):
    bm.normal_update()
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    ctx['col'].objects.link(objeto)
    return objeto


def _uv(objeto, tamano):
    """UV por proyección de caja en el mundo (la textura mide `tamano` m),
    escrita en la malla sin pasar por bmesh: así no se pierden las normales
    ponderadas."""
    malla = objeto.data
    capa = malla.uv_layers.new(name='UVMap')
    matriz = objeto.matrix_world
    giro = matriz.to_3x3()
    for cara in malla.polygons:
        n = giro @ cara.normal
        ejes = (abs(n.x), abs(n.y), abs(n.z))
        dominante = ejes.index(max(ejes))
        for k in cara.loop_indices:
            p = matriz @ malla.vertices[malla.loops[k].vertex_index].co
            if dominante == 0:
                u, v = p.y, p.z
            elif dominante == 1:
                u, v = p.x, p.z
            else:
                u, v = p.x, p.y
            capa.data[k].uv = (u / tamano, v / tamano)


def _poner(ctx, objeto, tamanoUV=0.5):
    """Lo deja en la lista del puesto con su UV (proyección del mundo)."""
    if not objeto.data.uv_layers:
        _uv(objeto, tamanoUV)
    ctx['piezas'].append(objeto)
    return objeto


def caja(ctx, nombre, centro, tamano, material, radio=0.0, segmentos=3, giro=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tamano), verts=bm.verts)
    o = _objeto(bm, nombre, ctx['m'][material], ctx)
    biselar(o, radio, segmentos)
    o.matrix_world = Matrix.Translation(Vector(centro)) @ (giro or Matrix.Identity(4))
    return o


def cilindro(ctx, nombre, centro, radio, alto, material, eje=(0, 0, 1), segmentos=64, bisel=0.0, radioArriba=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segmentos, radius1=radio,
                          radius2=radio if radioArriba is None else radioArriba, depth=alto)
    o = _objeto(bm, nombre, ctx['m'][material], ctx)
    biselar(o, bisel, 2)
    giro = Vector((0, 0, 1)).rotation_difference(Vector(eje).normalized()).to_matrix().to_4x4()
    o.matrix_world = Matrix.Translation(Vector(centro)) @ giro
    return o


def anillo(ctx, nombre, centro, radioFuera, radioDentro, alto, material, eje=(0, 0, 1), segmentos=64):
    """Arandela: tubo corto de pared `radioFuera - radioDentro`."""
    bm = bmesh.new()
    aros = []
    for r, z in ((radioFuera, -alto / 2), (radioFuera, alto / 2), (radioDentro, alto / 2), (radioDentro, -alto / 2)):
        aros.append([bm.verts.new((r * math.cos(2 * math.pi * k / segmentos), r * math.sin(2 * math.pi * k / segmentos), z)) for k in range(segmentos)])
    for a, b in zip(aros, aros[1:] + aros[:1]):
        for k in range(segmentos):
            j = (k + 1) % segmentos
            bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _objeto(bm, nombre, ctx['m'][material], ctx)
    biselar(o, 0)
    giro = Vector((0, 0, 1)).rotation_difference(Vector(eje).normalized()).to_matrix().to_4x4()
    o.matrix_world = Matrix.Translation(Vector(centro)) @ giro
    return o


def rectRedondeado(ancho, fondo, radio, segmentos=10):
    """Contorno (x, y) de un rectángulo con las esquinas redondeadas, en
    sentido antihorario, centrado en el origen."""
    puntos = []
    for cx, cy, a0 in ((ancho / 2 - radio, fondo / 2 - radio, 0), (-ancho / 2 + radio, fondo / 2 - radio, 90),
                       (-ancho / 2 + radio, -fondo / 2 + radio, 180), (ancho / 2 - radio, -fondo / 2 + radio, 270)):
        for k in range(segmentos + 1):
            a = math.radians(a0 + 90 * k / segmentos)
            puntos.append((cx + radio * math.cos(a), cy + radio * math.sin(a)))
    return puntos


def placa(ctx, nombre, centro, contorno, grueso, material, bisel=0.003, segmentos=3):
    """Placa del `contorno` (x, y) con `grueso` en z, centrada en `centro`."""
    bm = bmesh.new()
    abajo = [bm.verts.new((x, y, -grueso / 2)) for x, y in contorno]
    arriba = [bm.verts.new((x, y, grueso / 2)) for x, y in contorno]
    n = len(contorno)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((abajo[k], abajo[j], arriba[j], arriba[k]))
    bm.faces.new(arriba)
    bm.faces.new(list(reversed(abajo)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _objeto(bm, nombre, ctx['m'][material], ctx)
    biselar(o, bisel, segmentos)
    o.matrix_world = Matrix.Translation(Vector(centro))
    return o


def solido(ctx, nombre, anillos, material, bisel=0.0, segmentos=3, cerrar=True):
    """Sólido que une `anillos` (listas de puntos 3D del mismo número, en
    orden) con caras laterales; tapas en el primero y el último."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in a] for a in anillos]
    n = len(anillos[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((a[k], a[j], b[j], b[k]))
    if cerrar:
        bm.faces.new(vs[0])
        bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _objeto(bm, nombre, ctx['m'][material], ctx)
    biselar(o, bisel, segmentos)
    return o


def barrido(ctx, nombre, puntos, radio, material, segmentos=16, pasos=6):
    """Tubo redondo (cable, barra) que pasa suave por `puntos`."""
    p = [Vector(x) for x in puntos]
    # Catmull-Rom para que sea una curva continua.
    curva = []
    for i in range(len(p) - 1):
        p0, p1, p2, p3 = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]
        for k in range(pasos):
            t = k / pasos
            curva.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    curva.append(p[-1])
    anillos = []
    normal = None
    for i, c in enumerate(curva):
        tangente = (curva[min(i + 1, len(curva) - 1)] - curva[max(i - 1, 0)]).normalized()
        if normal is None:
            normal = tangente.orthogonal().normalized()
        normal = (normal - tangente * normal.dot(tangente)).normalized()
        binormal = tangente.cross(normal)
        anillos.append([tuple(c + (normal * math.cos(a) + binormal * math.sin(a)) * radio) for a in (2 * math.pi * k / segmentos for k in range(segmentos))])
    o = solido(ctx, nombre, anillos, material)
    return o


def mover(objetos, matriz):
    for o in objetos:
        o.matrix_world = matriz @ o.matrix_world


def texto(ctx, contenido, tamano, matriz):
    curva = bpy.data.curves.new('leyenda', 'FONT')
    curva.body = contenido
    curva.size = tamano
    curva.align_x = 'CENTER'
    curva.align_y = 'CENTER'
    curva.resolution_u = 4
    o = bpy.data.objects.new('leyenda', curva)
    o.data.materials.append(ctx['m']['leyenda'])
    ctx['col'].objects.link(o)
    o.matrix_world = matriz
    _textos.append(o)
    return o


# Teclado -------------------------------------------------------------------------

def _encoger(contorno, d):
    """Contorno ortogonal (antihorario) metido `d` hacia dentro."""
    n = len(contorno)
    salida = []
    for k in range(n):
        a, b, c = Vector(contorno[k - 1]), Vector(contorno[k]), Vector(contorno[(k + 1) % n])
        e1, e2 = (b - a).normalized(), (c - b).normalized()
        n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))
        salida.append(tuple(b + (n1 + n2) * d))
    return salida


def _tecla(contorno, material):
    """Malla de una tecla con ese contorno en unidades (forma de casquete:
    18 mm abajo, 12,7 arriba, 8 mm de alto), compartida por forma."""
    clave = tuple(contorno)
    if clave in _plantillas:
        return _plantillas[clave]
    m = [(x * U, y * U) for x, y in contorno]
    abajo = _encoger(m, 0.0006)
    arriba = _encoger(m, 0.0006 + 0.0026)
    bm = bmesh.new()
    va = [bm.verts.new((x, y, 0)) for x, y in abajo]
    vb = [bm.verts.new((x, y, 0.008)) for x, y in arriba]
    n = len(m)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((va[k], va[j], vb[j], vb[k]))
    bm.faces.new(vb)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    malla = bpy.data.meshes.new('tecla')
    bm.to_mesh(malla)
    bm.free()
    malla.materials.append(material)
    plantilla = bpy.data.objects.new('teclaPlantilla', malla)
    bpy.context.scene.collection.objects.link(plantilla)
    biselar(plantilla, 0.0009, 2, 25)
    datos = plantilla.data
    bpy.data.objects.remove(plantilla)
    _plantillas[clave] = datos
    return datos


def _rect(x, y, w, h):
    """Contorno de una tecla rectangular: (x, y) arriba a la izquierda en
    unidades, y hacia abajo (fila), centrado luego por el teclado."""
    return ((x, -y - h), (x + w, -y - h), (x + w, -y), (x, -y))


# (texto, ancho) por fila; None = hueco. Español ISO.
FILAS = [
    (0, [('Esc', 1), (None, 1), ('F1', 1), ('F2', 1), ('F3', 1), ('F4', 1), (None, 0.5), ('F5', 1), ('F6', 1), ('F7', 1), ('F8', 1),
         (None, 0.5), ('F9', 1), ('F10', 1), ('F11', 1), ('F12', 1)]),
    (1.5, [('ª\nº', 1), ('!\n1', 1), ('"\n2', 1), ('·\n3', 1), ('$\n4', 1), ('%\n5', 1), ('&\n6', 1), ('/\n7', 1), ('(\n8', 1), (')\n9', 1),
           ('=\n0', 1), ('?\n\'', 1), ('¿\n¡', 1), ('⇦', 2)]),
    (2.5, [('Tab', 1.5)] + [(c, 1) for c in 'QWERTYUIOP'] + [('^\n`', 1), ('*\n+', 1)]),
    (3.5, [('Bloq Mayús', 1.75)] + [(c, 1) for c in 'ASDFGHJKLÑ'] + [('¨\n´', 1), ('Ç', 1)]),
    (4.5, [('⇧', 1.25), ('>\n<', 1)] + [(c, 1) for c in 'ZXCVBNM'] + [(';\n,', 1), (':\n.', 1), ('_\n-', 1), ('⇧', 2.75)]),
    (5.5, [('Ctrl', 1.25), ('', 1.25), ('Alt', 1.25), ('', 6.25), ('Alt Gr', 1.25), ('', 1.25), ('Menú', 1.25), ('Ctrl', 1.25)]),
]
# Teclas sueltas: (texto, x, fila, ancho, alto) en unidades.
SUELTAS = [
    ('Impr', 15.25, 0, 1, 1), ('Bloq\nDespl', 16.25, 0, 1, 1), ('Pausa', 17.25, 0, 1, 1),
    ('Insert', 15.25, 1.5, 1, 1), ('Inicio', 16.25, 1.5, 1, 1), ('Re\nPág', 17.25, 1.5, 1, 1),
    ('Supr', 15.25, 2.5, 1, 1), ('Fin', 16.25, 2.5, 1, 1), ('Av\nPág', 17.25, 2.5, 1, 1),
    ('↑', 16.25, 4.5, 1, 1), ('←', 15.25, 5.5, 1, 1), ('↓', 16.25, 5.5, 1, 1), ('→', 17.25, 5.5, 1, 1),
    ('Bloq\nNum', 18.5, 1.5, 1, 1), ('/', 19.5, 1.5, 1, 1), ('*', 20.5, 1.5, 1, 1), ('-', 21.5, 1.5, 1, 1),
    ('7', 18.5, 2.5, 1, 1), ('8', 19.5, 2.5, 1, 1), ('9', 20.5, 2.5, 1, 1), ('+', 21.5, 2.5, 1, 2),
    ('4', 18.5, 3.5, 1, 1), ('5', 19.5, 3.5, 1, 1), ('6', 20.5, 3.5, 1, 1),
    ('1', 18.5, 4.5, 1, 1), ('2', 19.5, 4.5, 1, 1), ('3', 20.5, 4.5, 1, 1), ('Intro', 21.5, 4.5, 1, 2),
    ('0', 18.5, 5.5, 2, 1), ('.', 20.5, 5.5, 1, 1),
]
# Las flechas: la fuente de Blender no trae ← ↑ → ↓; se usa ⇧ girada.
FLECHAS = {'↑': 0, '←': 90, '↓': 180, '→': 270, '⇦': 90}


def _leyenda(ctx, contenido, cx, cy, ancho, alto, matrizPlaca):
    """Las letras de una tecla en su cara de arriba (a 8 mm de la placa)."""
    if not contenido:
        return
    z = 0.0082
    if contenido in FLECHAS:
        giro = Matrix.Rotation(math.radians(FLECHAS[contenido]), 4, 'Z')
        texto(ctx, '⇧', 0.0055, matrizPlaca @ Matrix.Translation((cx, cy, z)) @ giro)
        return
    if contenido == '⇧':
        texto(ctx, '⇧', 0.0055, matrizPlaca @ Matrix.Translation((cx - ancho * U / 2 + 0.0065, cy, z)))
        return
    partes = contenido.split('\n')
    if len(partes) == 2 and len(partes[0]) == 1 and len(partes[1]) == 1:
        # Dos símbolos: el de Mayús arriba, el normal abajo, a la izquierda.
        texto(ctx, partes[0], 0.0036, matrizPlaca @ Matrix.Translation((cx - 0.0022, cy + 0.0022, z)))
        texto(ctx, partes[1], 0.0036, matrizPlaca @ Matrix.Translation((cx - 0.0022, cy - 0.0022, z)))
        return
    if len(contenido) == 1:
        texto(ctx, contenido, 0.0042, matrizPlaca @ Matrix.Translation((cx, cy, z)))
        return
    tamano = 0.0024 if (len(contenido) > 4 or len(partes) > 1) else 0.0028
    texto(ctx, contenido, tamano, matrizPlaca @ Matrix.Translation((cx, cy, z)))


def teclado(ctx, centro, giro=0.0):
    """Teclado español ISO de 105 teclas con su caja inclinada."""
    m = ctx['m']
    hecho = []
    ancho, fondo = 22.5 * U + 0.012, 6.5 * U + 0.012
    alturaDelante, alturaDetras = 0.018, 0.030
    # Caja: cuña de plástico (perfil en y-z barrido a lo ancho).
    perfil = [(-fondo / 2, 0.0), (fondo / 2, 0.0), (fondo / 2, alturaDetras), (-fondo / 2, alturaDelante)]
    anillos = [[(x, y, z) for y, z in perfil] for x in (-ancho / 2, ancho / 2)]
    hecho.append(solido(ctx, 'tecladoCaja', anillos, 'salaPlastico', bisel=0.004, segmentos=3))
    # La placa de las teclas: la cara de arriba de la caja.
    inclinacion = math.atan2(alturaDetras - alturaDelante, fondo)
    placa_ = Matrix.Translation((0, 0, (alturaDelante + alturaDetras) / 2)) @ Matrix.Rotation(inclinacion, 4, 'X')
    origen = Vector((-11.25, 3.25))  # centro del bloque de teclas en unidades
    teclas = []
    for fila, lista in FILAS:
        x = 0.0
        for contenido, w in lista:
            if contenido is not None:
                teclas.append((contenido, x, fila, w, 1))
            x += w
    teclas += SUELTAS
    # Intro en L de la ISO: arriba 1,5 u en la fila 2,5; abajo 1,25 en la 3,5.
    intro = ((13.75, -4.5), (15, -4.5), (15, -2.5), (13.5, -2.5), (13.5, -3.5), (13.75, -3.5))
    for contenido, x, fila, w, h in teclas + [('Intro', None, None, None, None)]:
        if x is None:
            contorno = intro
            cx, cy = 14.4, -3.3
            w = 1.25
        else:
            contorno = _rect(x, fila, w, h)
            cx, cy = x + w / 2, -fila - h / 2
        # La forma respecto a su centro: las teclas iguales comparten malla.
        datos = _tecla(tuple((round(px - cx, 4), round(py - cy, 4)) for px, py in contorno), m['salaPlastico'])
        o = bpy.data.objects.new('tecla', datos)
        ctx['col'].objects.link(o)
        o.matrix_world = placa_ @ Matrix.Translation(((cx + origen.x) * U, (cy + origen.y) * U, 0))
        hecho.append(o)
        _leyenda(ctx, contenido, (cx + origen.x) * U, (cy + origen.y) * U, w, h, placa_)
    # Pilotos de Bloq Num (encendido), Bloq Mayús y Bloq Despl, sobre el
    # teclado numérico.
    for k, material in enumerate(('ledFijo', 'ledApagado', 'ledApagado')):
        px = (19.0 + k * 1.2 + origen.x) * U
        py = (-0.5 + origen.y) * U
        led = cilindro(ctx, 'piloto', (px, py, 0.0008), 0.0016, 0.0016, material, segmentos=24)
        led.matrix_world = placa_ @ led.matrix_world
        hecho.append(led)
    matriz = Matrix.Translation(Vector(centro)) @ Matrix.Rotation(giro, 4, 'Z')
    mover(hecho, matriz)
    for t in _textos[-200:]:
        if t.get('movido') is None:
            t.matrix_world = matriz @ t.matrix_world
            t['movido'] = True
    for o in hecho:
        _poner(ctx, o)
    # Dónde sale el cable (detrás, en el centro).
    return matriz @ Vector((0, fondo / 2 + 0.002, alturaDetras - 0.008))


# Ratón ---------------------------------------------------------------------------

LARGO_RATON, ANCHO_RATON, ALTO_RATON = 0.120, 0.063, 0.038


def _superficieRaton(u, v):
    """Punto de la carcasa: u de -1 (izquierda) a 1, v de -1 (detrás) a 1
    (delante). Huevo más ancho atrás, joroba a 1/3 desde atrás."""
    y = v * LARGO_RATON / 2
    mitad = ANCHO_RATON / 2 * (1 - 0.13 * v) * max(0.0, 1 - v * v) ** 0.42
    x = u * mitad
    joroba = 0.012 + (ALTO_RATON - 0.012) * math.exp(-((y + 0.016) / 0.052) ** 2)
    z = joroba * max(0.0, 1 - u * u) ** 0.36 * max(0.0, 1 - v * v) ** 0.22
    return Vector((x, y, z))


def raton(ctx, centro, giro=0.0):
    hecho = []
    nu, nv = 40, 64
    bm = bmesh.new()
    rejilla = []
    for j in range(nv + 1):
        v = -math.cos(math.pi * j / nv)
        rejilla.append([bm.verts.new(_superficieRaton(-math.cos(math.pi * i / nu), v)) for i in range(nu + 1)])
    for j in range(nv):
        for i in range(nu):
            try:
                bm.faces.new((rejilla[j][i], rejilla[j][i + 1], rejilla[j + 1][i + 1], rejilla[j + 1][i]))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00005)
    bmesh.ops.dissolve_degenerate(bm, dist=0.00001, edges=bm.edges)
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    carcasa = _objeto(bm, 'raton', ctx['m']['salaPlastico'], ctx)
    biselar(carcasa, 0)
    hecho.append(carcasa)

    def normalRaton(u, v):
        e = 0.002
        du = _superficieRaton(u + e, v) - _superficieRaton(u - e, v)
        dv = _superficieRaton(u, v + e) - _superficieRaton(u, v - e)
        n = du.cross(dv).normalized()
        return n if n.x * u > 0 or n.z > 0 else -n

    def tira(nombre, puntos, ancho, material='ranura'):
        """Cinta oscura pegada a la carcasa (la junta entre piezas)."""
        anillos = []
        for k, (u, v) in enumerate(puntos):
            p = _superficieRaton(u, v)
            a = _superficieRaton(*puntos[min(k + 1, len(puntos) - 1)]) - _superficieRaton(*puntos[max(k - 1, 0)])
            lado = Vector((-a.y, a.x, 0)).normalized() * (ancho / 2)
            fuera = normalRaton(u, v) * 0.00025
            anillos.append([tuple(p - lado + fuera), tuple(p + lado + fuera)])
        bm = bmesh.new()
        vs = [[bm.verts.new(q) for q in a] for a in anillos]
        for a, b in zip(vs, vs[1:]):
            bm.faces.new((a[0], a[1], b[1], b[0]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = _objeto(bm, nombre, ctx['m'][material], ctx)
        for cara in o.data.polygons:
            if cara.normal.z < 0:
                o.data.flip_normals()
                break
        hecho.append(o)

    vBotones = 0.18
    tira('juntaBotones', [(-0.93 + 1.86 * k / 30, vBotones) for k in range(31)], 0.0009)
    tira('juntaCentro', [(0.0, vBotones + (0.985 - vBotones) * k / 24) for k in range(25)], 0.0009)
    # Hueco y rueda (goma, 48 dientes de agarre en la textura).
    vRueda = 0.5
    pr = _superficieRaton(0, vRueda)
    tira('huecoRueda', [(0.0, vRueda - 0.18 + 0.36 * k / 8) for k in range(9)], 0.0095)
    hecho.append(cilindro(ctx, 'rueda', (0, pr.y, pr.z - 0.0062), 0.0095, 0.0068, 'salaGoma', eje=(1, 0, 0), segmentos=64, bisel=0.0012))
    # Dos botones laterales (pulgar, a la izquierda).
    # Dos botones laterales (pulgar, a la izquierda): trozos de la propia
    # carcasa que asoman 0,7 mm, con su junta oscura alrededor.
    def parche(nombre, u0, u1, v0, v1, fuera, grueso, material, bisel):
        anillos = []
        bm = bmesh.new()
        n = 8
        filas = []
        for j in range(n + 1):
            v = v0 + (v1 - v0) * j / n
            filas.append([bm.verts.new(_superficieRaton(u0 + (u1 - u0) * i / n, v) + normalRaton(u0 + (u1 - u0) * i / n, v) * fuera) for i in range(n + 1)])
        for j in range(n):
            for i in range(n):
                bm.faces.new((filas[j][i], filas[j][i + 1], filas[j + 1][i + 1], filas[j + 1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = _objeto(bm, nombre, ctx['m'][material], ctx)
        mod = o.modifiers.new('grueso', 'SOLIDIFY')
        mod.thickness = grueso
        mod.offset = 0
        _aplicar(o)
        biselar(o, bisel, 2)
        hecho.append(o)

    for v in (0.08, -0.12):
        parche('juntaLateral', -0.97, -0.84, v - 0.085, v + 0.085, 0.0002, 0.0006, 'ranura', 0)
        parche('botonLateral', -0.96, -0.85, v - 0.075, v + 0.075, 0.0007, 0.0012, 'salaPlastico', 0.0005)
    # Patines de teflón debajo (se ven de lado como una línea).
    matriz = Matrix.Translation(Vector(centro)) @ Matrix.Rotation(giro, 4, 'Z')
    mover(hecho, matriz)
    for o in hecho:
        _poner(ctx, o, 0.2)
    return matriz @ _superficieRaton(0, 1.0) + Vector((0, 0, 0.004))


# Monitor -------------------------------------------------------------------------

PANTALLA_ANCHO, PANTALLA_ALTO = 0.6973, 0.3922  # 31,5" de panel 16:9
MARCO, BARBILLA = 0.008, 0.022


def monitor(ctx, cx, cy, cz, mesa):
    """Monitor de 32" con la imagen centrada en (cx, cz), a ras de su marco
    en y = cy - 0,0185 (la pantalla viva la pone esquinasPantalla). `mesa`:
    altura de la cara de arriba del tablero. Devuelve el punto de salida
    de los cables (detrás, abajo de la columna)."""
    hecho = []
    ancho = PANTALLA_ANCHO + 2 * MARCO
    alto = PANTALLA_ALTO + MARCO + BARBILLA
    zMarco = cz + (MARCO - BARBILLA) / 2
    frente = cy - 0.018
    # Marco frontal (la imagen queda 0,5 mm por delante: cristal a ras).
    contorno = rectRedondeado(ancho, alto, 0.004, 4)
    marco = placa(ctx, 'marcoMonitor', (0, 0, 0), contorno, 0.010, 'salaPlastico', bisel=0.0015, segmentos=2)
    marco.matrix_world = Matrix.Translation((cx, frente + 0.005, zMarco)) @ Matrix.Rotation(math.pi / 2, 4, 'X')
    hecho.append(marco)
    # Carcasa trasera: tronco de pirámide redondeado de 0,69 x 0,40 a 0,46 x 0,26.
    delante = [(cx + x, frente + 0.0101, zMarco + y) for x, y in rectRedondeado(ancho - 0.012, alto - 0.012, 0.01, 4)]
    detras = [(cx + x * 0.68, cy + 0.032, zMarco - 0.01 + y * 0.66) for x, y in rectRedondeado(ancho - 0.012, alto - 0.012, 0.01, 4)]
    hecho.append(solido(ctx, 'carcasaMonitor', [delante, detras], 'salaPlastico', bisel=0.006, segmentos=3))
    # Rejillas de ventilación en la cara de atrás, arriba: 14 ranuras.
    for k in range(14):
        hecho.append(caja(ctx, 'rejillaMonitor', (cx - 0.13 + k * 0.02, cy + 0.0324, zMarco + 0.075), (0.005, 0.0012, 0.04), 'ranura', radio=0.0004, segmentos=1))
    # VESA y bisagra a la columna.
    hecho.append(caja(ctx, 'vesa', (cx, cy + 0.037, cz - 0.005), (0.12, 0.012, 0.12), 'salaPlastico', radio=0.004))
    hecho.append(caja(ctx, 'bisagra', (cx, cy + 0.052, cz - 0.01), (0.085, 0.028, 0.05), 'salaPlastico', radio=0.006))
    # Columna (perfil redondeado de 65 x 35) con el hueco de los cables.
    zc0, zc1 = mesa + 0.012, cz + 0.06
    columna = placa(ctx, 'columna', (0, 0, 0), rectRedondeado(0.065, 0.035, 0.012, 6), zc1 - zc0, 'salaPlastico', bisel=0.003)
    columna.matrix_world = Matrix.Translation((cx, cy + 0.075, (zc0 + zc1) / 2))
    hecho.append(columna)
    hecho.append(caja(ctx, 'pasoCables', (cx, cy + 0.0925, mesa + 0.12), (0.034, 0.002, 0.05), 'ranura', radio=0.0008, segmentos=2))
    # Base redondeada.
    hecho.append(placa(ctx, 'baseMonitor', (cx, cy + 0.06, mesa + 0.007), rectRedondeado(0.30, 0.22, 0.06, 10), 0.014, 'salaPlastico', bisel=0.004))
    # Botones bajo la barbilla (5) y piloto blanco delante, abajo a la derecha.
    zBajo = zMarco - alto / 2
    for k in range(5):
        hecho.append(caja(ctx, 'botonMonitor', (cx + 0.26 + k * 0.013, frente + 0.008, zBajo - 0.0012), (0.007, 0.005, 0.0024), 'salaPlastico', radio=0.0008, segmentos=2))
    hecho.append(caja(ctx, 'pilotoMonitor', (cx + 0.33, frente - 0.0004, zBajo + 0.006), (0.004, 0.0012, 0.0015), 'ledBlanco'))
    for o in hecho:
        _poner(ctx, o)
    return Vector((cx, cy + 0.0935, mesa + 0.1))


# Torre ---------------------------------------------------------------------------

def torre(ctx, tx, ty, suelo):
    hecho = []
    w, d, h = 0.21, 0.45, 0.46
    zc = suelo + 0.012 + h / 2
    hecho.append(caja(ctx, 'torre', (tx, ty, zc), (w, d, h), 'salaPlastico', radio=0.006))
    frente = ty - d / 2
    # Frontal: panel 4 mm por delante con dos columnas de ranuras.
    hecho.append(caja(ctx, 'frontalTorre', (tx, frente - 0.003, zc - 0.005), (w - 0.016, 0.008, h - 0.03), 'salaPlastico', radio=0.003))
    for lado in (-1, 1):
        for k in range(16):
            hecho.append(caja(ctx, 'rejillaTorre', (tx + lado * 0.07, frente - 0.0072, zc - 0.17 + k * 0.019), (0.04, 0.001, 0.005), 'ranura'))
    # Arriba del frontal: botón con aro de luz, 2 USB-A, USB-C y audio.
    zIo = zc + h / 2 - 0.04
    yCara = frente - 0.007
    hecho.append(cilindro(ctx, 'botonTorre', (tx, yCara - 0.002, zIo), 0.009, 0.004, 'salaPlastico', eje=(0, -1, 0), segmentos=48, bisel=0.001))
    hecho.append(anillo(ctx, 'aroTorre', (tx, yCara - 0.0012, zIo), 0.0108, 0.0094, 0.0026, 'ledFijo', eje=(0, -1, 0), segmentos=48))
    for dx in (-0.06, -0.04):
        hecho.append(caja(ctx, 'usbA', (tx + dx, yCara - 0.0003, zIo), (0.0135, 0.002, 0.0058), 'ranura', radio=0.0005, segmentos=1))
        hecho.append(caja(ctx, 'usbLengua', (tx + dx, yCara - 0.0008, zIo + 0.001), (0.011, 0.0012, 0.0018), 'cableAzul'))
    hecho.append(caja(ctx, 'usbC', (tx + 0.035, yCara - 0.0003, zIo), (0.009, 0.002, 0.0034), 'ranura', radio=0.0012, segmentos=2))
    for dx in (0.052, 0.064):
        hecho.append(anillo(ctx, 'jack', (tx + dx, yCara - 0.0006, zIo), 0.0032, 0.0018, 0.0016, 'cromo', eje=(0, -1, 0), segmentos=24))
        hecho.append(cilindro(ctx, 'jackHueco', (tx + dx, yCara - 0.0002, zIo), 0.0019, 0.0006, 'ranura', eje=(0, -1, 0), segmentos=24))
    # Rejilla del lateral que da al operador (-x): 6 filas de ranuras largas.
    for fila in range(6):
        for col in range(2):
            hecho.append(caja(ctx, 'rejillaLado', (tx - w / 2 - 0.0004, ty - 0.08 + col * 0.13, zc + 0.05 + fila * 0.022), (0.001, 0.1, 0.006), 'ranura', radio=0.0004, segmentos=1))
    # Patas de goma.
    for sx in (-1, 1):
        for sy in (-1, 1):
            hecho.append(cilindro(ctx, 'pataTorre', (tx + sx * (w / 2 - 0.03), ty + sy * (d / 2 - 0.04), suelo + 0.006), 0.016, 0.012, 'salaGoma', segmentos=32, bisel=0.002))
    for o in hecho:
        _poner(ctx, o)


# Mesa ----------------------------------------------------------------------------

def mesa(ctx, x, y, suelo, zm):
    """Tablero de 1,8 x 0,8 (cara de arriba a zm + 0,02), marco de acero,
    faldón, bandeja de cables y pasacables. Devuelve el pasacables."""
    hecho = []
    tablero = placa(ctx, 'tablero', (x, y, zm), rectRedondeado(1.8, 0.8, 0.025, 8), 0.04, 'salaLaminado', bisel=0.005, segmentos=3)
    hecho.append(tablero)
    # Pasacables: aro y tapa con su ranura, detrás a la derecha.
    px, py = x + 0.5, y + 0.3
    arriba = zm + 0.02
    hecho.append(anillo(ctx, 'pasacables', (px, py, arriba + 0.001), 0.034, 0.028, 0.002, 'salaPlastico'))
    hecho.append(cilindro(ctx, 'tapaPasacables', (px, py, arriba + 0.0006), 0.0285, 0.0012, 'salaPlastico', segmentos=48))
    hecho.append(caja(ctx, 'ranuraPasacables', (px, py + 0.012, arriba + 0.0013), (0.04, 0.008, 0.0004), 'ranura', radio=0.0001, segmentos=1))
    # Marco de acero: dos laterales de tubo rectangular con niveladores.
    zAbajo = zm - 0.02
    for lado in (-1, 1):
        xl = x + lado * 0.82
        for sy in (-1, 1):
            hecho.append(caja(ctx, 'poste', (xl, y + sy * 0.3, (suelo + 0.05 + zAbajo) / 2), (0.06, 0.03, zAbajo - suelo - 0.05), 'salaAluminio', radio=0.004))
        hecho.append(caja(ctx, 'pie', (xl, y, suelo + 0.032), (0.07, 0.76, 0.035), 'salaAluminio', radio=0.006))
        hecho.append(caja(ctx, 'travesanoAlto', (xl, y, zAbajo - 0.016), (0.05, 0.72, 0.03), 'salaAluminio', radio=0.004))
        for sy in (-1, 1):
            hecho.append(cilindro(ctx, 'nivelador', (xl, y + sy * 0.34, suelo + 0.0075), 0.02, 0.015, 'salaGoma', segmentos=32, bisel=0.002))
    hecho.append(caja(ctx, 'vigaMesa', (x, y + 0.3, zAbajo - 0.025), (1.58, 0.04, 0.05), 'salaAluminio', radio=0.004))
    # Faldón de chapa con su pliegue arriba.
    hecho.append(caja(ctx, 'faldon', (x, y + 0.36, zm - 0.25), (1.56, 0.012, 0.4), 'grisBanco', radio=0.003))
    # Bandeja de cables de varilla bajo el tablero, detrás.
    zb = zm - 0.13
    for dy in (-0.05, 0.05):
        hecho.append(cilindro(ctx, 'varilla', (x - 0.05, y + 0.27 + dy, zb), 0.003, 1.1, 'cromo', eje=(1, 0, 0), segmentos=12))
    for dy in (-0.05, 0.05):
        hecho.append(cilindro(ctx, 'varilla', (x - 0.05, y + 0.27 + dy, zb + 0.05), 0.0025, 1.1, 'cromo', eje=(1, 0, 0), segmentos=12))
    for k in range(12):
        xv = x - 0.6 + k * 0.1
        hecho.append(barrido(ctx, 'varilla', [(xv, y + 0.22, zb + 0.05), (xv, y + 0.22, zb), (xv, y + 0.32, zb), (xv, y + 0.32, zb + 0.05)], 0.0022, 'cromo', segmentos=10, pasos=2))
    for o in hecho:
        _poner(ctx, o, 1.0)
    return Vector((px, py, arriba + 0.0016))


# Silla ---------------------------------------------------------------------------

def _respaldo(u, v, ancho=0.47, alto=0.56, radio=0.55):
    """Punto del respaldo curvo: u de -1 a 1, v de 0 (abajo) a 1 (arriba).
    Hacia +y es hacia el que se sienta (los lados le abrazan)."""
    a = u * ancho / 2 / radio
    x = radio * math.sin(a)
    y = radio * (1 - math.cos(a)) + 0.028 * math.exp(-((v - 0.27) / 0.16) ** 2)
    ancho_v = 1 - 0.12 * (v - 0.5) ** 2  # algo más estrecho arriba y abajo
    return Vector((x * ancho_v, y, v * alto))


def silla(ctx, x, y, suelo, giro):
    hecho = []
    # Asiento (cojín de tela redondeado) y su concha de plástico.
    hecho.append(caja(ctx, 'asiento', (0, 0.02, 0.45), (0.50, 0.48, 0.075), 'salaTela', radio=0.03, segmentos=5))
    hecho.append(caja(ctx, 'conchaAsiento', (0, 0.02, 0.405), (0.46, 0.44, 0.018), 'salaPlastico', radio=0.008))
    # Mecanismo, pomo de tensión y palanca de altura.
    hecho.append(caja(ctx, 'mecanismo', (0, 0.0, 0.365), (0.22, 0.26, 0.05), 'salaPlastico', radio=0.01))
    hecho.append(cilindro(ctx, 'pomo', (0, 0.15, 0.355), 0.024, 0.03, 'salaPlastico', eje=(0, 1, 0), segmentos=48, bisel=0.004))
    hecho.append(barrido(ctx, 'palanca', [(0.11, 0.05, 0.37), (0.17, 0.07, 0.37), (0.2, 0.09, 0.375)], 0.0045, 'cromo', segmentos=16))
    hecho.append(caja(ctx, 'paleta', (0.215, 0.1, 0.376), (0.05, 0.026, 0.008), 'salaPlastico', radio=0.003))
    # Pistón: vástago cromado, funda telescópica de 3 tramos y buje.
    hecho.append(cilindro(ctx, 'piston', (0, 0, 0.318), 0.014, 0.05, 'cromo', segmentos=48))
    for k, (r, z0, z1) in enumerate(((0.032, 0.11, 0.18), (0.029, 0.178, 0.24), (0.026, 0.238, 0.296))):
        hecho.append(cilindro(ctx, 'funda', (0, 0, (z0 + z1) / 2), r, z1 - z0, 'salaPlastico', segmentos=64, bisel=0.002))
    hecho.append(cilindro(ctx, 'buje', (0, 0, 0.095), 0.045, 0.05, 'salaAluminio', segmentos=64, bisel=0.004))
    # Base de 5 radios (de 0,64 m) con ruedas dobles de 50 mm.
    for k in range(5):
        a = math.pi / 2 + k * 2 * math.pi / 5
        d = Vector((math.cos(a), math.sin(a), 0))
        lado = Vector((-d.y, d.x, 0))
        anillos = []
        for t, r, ancho, alto, z in ((0.0, 0.03, 0.05, 0.042, 0.1), (0.5, 0.17, 0.044, 0.036, 0.09), (1.0, 0.30, 0.036, 0.028, 0.073)):
            c = d * r + Vector((0, 0, z))
            anillos.append([tuple(c + lado * (ancho / 2) * sx + Vector((0, 0, alto / 2 * sz))) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
        hecho.append(solido(ctx, 'radio', anillos, 'salaAluminio', bisel=0.006, segmentos=3))
        punta = d * 0.31
        hecho.append(cilindro(ctx, 'tapaRadio', (punta.x, punta.y, 0.075), 0.02, 0.03, 'salaAluminio', segmentos=32, bisel=0.004))
        # Rueda doble: vástago, cuerpo y dos ruedas que miran a un lado.
        hecho.append(cilindro(ctx, 'vastago', (punta.x, punta.y, 0.058), 0.006, 0.012, 'cromo', segmentos=24))
        giroRueda = a + math.radians((k * 47) % 90 - 45)
        rueda = Matrix.Translation((punta.x, punta.y, 0)) @ Matrix.Rotation(giroRueda, 4, 'Z')
        partes = [caja(ctx, 'horquilla', (0.008, 0, 0.034), (0.028, 0.05, 0.03), 'salaPlastico', radio=0.009, segmentos=3)]
        for sx in (-1, 1):
            partes.append(cilindro(ctx, 'ruedaSilla', (0.01, sx * 0.0175, 0.025), 0.025, 0.015, 'salaGoma', eje=(0, 1, 0), segmentos=48, bisel=0.003))
            partes.append(cilindro(ctx, 'tapaRueda', (0.01, sx * 0.0255, 0.025), 0.011, 0.0012, 'salaAluminio', eje=(0, 1, 0), segmentos=48))
        mover(partes, rueda)
        hecho += partes
    # Espina del respaldo y respaldo de malla con su marco.
    hecho.append(barrido(ctx, 'espina', [(0, -0.1, 0.36), (0, -0.2, 0.37), (0, -0.27, 0.46), (0, -0.29, 0.6)], 0.018, 'salaAluminio', segmentos=24))
    respaldo = Matrix.Translation((0, -0.26, 0.55)) @ Matrix.Rotation(math.radians(12), 4, 'X')
    nu, nv = 28, 22
    for nombre, encoge, grueso, material, delante in (('marcoRespaldo', 0.0, 0.026, 'salaPlastico', 0.0), ('mallaRespaldo', 0.07, 0.004, 'salaMalla', 0.006)):
        bm = bmesh.new()
        rej = []
        for j in range(nv + 1):
            v = encoge / 2 + (1 - encoge) * j / nv
            rej.append([bm.verts.new(_respaldo(-1 + encoge + (2 - 2 * encoge) * i / nu, v) + Vector((0, delante, 0))) for i in range(nu + 1)])
        for j in range(nv):
            for i in range(nu):
                bm.faces.new((rej[j][i], rej[j][i + 1], rej[j + 1][i + 1], rej[j + 1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # Las caras hacia el que se sienta (+y): el grueso crece hacia atrás.
        bm.faces.ensure_lookup_table()
        if bm.faces[len(bm.faces) // 2].normal.y < 0:
            for cara in bm.faces:
                cara.normal_flip()
        o = _objeto(bm, nombre, ctx['m'][material], ctx)
        if nombre == 'marcoRespaldo':
            # Hueco en el centro: solo queda el marco de 3,5 cm.
            bm = bmesh.new()
            bm.from_mesh(o.data)
            borrar = []
            for cara in bm.faces:
                c = cara.calc_center_median()
                u = c.x / (0.47 / 2)
                v = c.z / 0.56
                if abs(u) < 0.83 and 0.07 < v < 0.93:
                    borrar.append(cara)
            bmesh.ops.delete(bm, geom=borrar, context='FACES')
            bm.to_mesh(o.data)
            bm.free()
        mod = o.modifiers.new('grueso', 'SOLIDIFY')
        mod.thickness = grueso
        mod.offset = -1
        _aplicar(o)
        biselar(o, 0.004 if nombre == 'marcoRespaldo' else 0.001, 2)
        o.matrix_world = respaldo
        hecho.append(o)
    # Brazos en T: escuadra bajo el asiento, poste y almohadilla.
    for sx in (-1, 1):
        hecho.append(caja(ctx, 'escuadra', (sx * 0.2, 0.0, 0.388), (0.15, 0.06, 0.016), 'salaPlastico', radio=0.005))
        hecho.append(caja(ctx, 'posteBrazo', (sx * 0.27, -0.01, 0.53), (0.035, 0.055, 0.29), 'salaPlastico', radio=0.01))
        hecho.append(caja(ctx, 'almohadilla', (sx * 0.27, 0.02, 0.682), (0.085, 0.25, 0.028), 'salaPlastico', radio=0.012, segmentos=4))
    matriz = Matrix.Translation((x, y, suelo)) @ Matrix.Rotation(giro, 4, 'Z')
    mover(hecho, matriz)
    for o in hecho:
        _poner(ctx, o)


# El puesto -------------------------------------------------------------------------

# Cada silla un poco girada, como se quedan al levantarse (grados).
GIROS_SILLA = (-7, 4, 10, -3, 8, -11)


def puesto(ctx, x, y, indice, monitores, suelo, esquinasPantalla):
    """Un puesto completo con la mesa centrada en (x, y); la pantalla viva
    de su monitor va a `monitores` (UV de 0 a 1)."""
    zm = suelo + 0.74
    arriba = zm + 0.02
    pasacables = mesa(ctx, x, y, suelo, zm)
    torre(ctx, x + 0.6, y - 0.02, suelo)
    cx, cy, cz = x, y + 0.2, zm + 0.34
    salidaMonitor = monitor(ctx, cx, cy, cz, arriba)
    monitores.append((esquinasPantalla((cx, cy, cz), (0.0, -1.0), PANTALLA_ANCHO, PANTALLA_ALTO, 0.0185), (0, 0, 1, 1)))
    salidaTeclado = teclado(ctx, (x - 0.02, y - 0.17, arriba))
    # Alfombrilla y ratón.
    _poner(ctx, placa(ctx, 'alfombrilla', (x + 0.4, y - 0.15, arriba + 0.0016), rectRedondeado(0.30, 0.25, 0.02, 8), 0.003, 'salaTela', bisel=0.0012, segmentos=2), 0.3)
    salidaRaton = raton(ctx, (x + 0.4, y - 0.17, arriba + 0.0031), math.radians(-4))
    # Cables por la mesa hasta el pasacables (tendidos, con algo de holgura).
    a = arriba + 0.0025
    barridos = [
        ('cableTeclado', [tuple(salidaTeclado), (salidaTeclado.x, salidaTeclado.y + 0.03, a), (salidaTeclado.x + 0.03, y + 0.06, a), (x + 0.19, y + 0.13, a), (x + 0.26, y + 0.27, a), (pasacables.x - 0.03, pasacables.y - 0.005, a), tuple(pasacables)], 0.0021),
        ('cableRaton', [tuple(salidaRaton), (salidaRaton.x + 0.01, salidaRaton.y + 0.06, a), (x + 0.47, y + 0.1, a), (pasacables.x + 0.012, pasacables.y - 0.03, a), tuple(pasacables)], 0.0016),
        ('cableMonitor', [tuple(salidaMonitor), (salidaMonitor.x, salidaMonitor.y + 0.02, a + 0.02), (x + 0.2, y + 0.33, a), (pasacables.x - 0.02, pasacables.y + 0.004, a), tuple(pasacables)], 0.003),
        ('cableCorriente', [tuple(salidaMonitor + Vector((0.015, 0, 0))), (salidaMonitor.x + 0.02, salidaMonitor.y + 0.03, a + 0.015), (x + 0.22, y + 0.36, a), (pasacables.x - 0.01, pasacables.y + 0.012, a), tuple(pasacables)], 0.0034),
    ]
    for nombre, puntos, radio in barridos:
        _poner(ctx, barrido(ctx, nombre, puntos, radio, 'cable', segmentos=12, pasos=8))
    silla(ctx, x, y - 0.75, suelo, math.radians(GIROS_SILLA[indice % len(GIROS_SILLA)]))


def terminar(ctx):
    """Convierte las letras de las teclas en malla y las deja en el puesto."""
    if not _textos:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for t in _textos:
        t.select_set(True)
    bpy.context.view_layer.objects.active = _textos[0]
    bpy.ops.object.convert(target='MESH')
    for t in list(bpy.context.selected_objects):
        _poner(ctx, t, 0.2)
    _textos.clear()

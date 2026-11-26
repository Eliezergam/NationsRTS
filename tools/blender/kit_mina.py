"""kit_mina.py - Kit de piezas de las instalaciones de mina (el dueño, 19-nov:
ciudades y minas armadas proceduralmente con piezas, y los robots construyen
con las mismas piezas). Estilo industrial militar: hormigón, chapa ondulada y
acero con pernos y franjas de aviso, como el robot y los contenedores.

blender -b --python tools/blender/kit_mina.py -- [--render <dir>] [--blend <ruta>]

Método (Bethesda, «Skyrim's Modular Approach to Level Design», GDC 2013; los
asentamientos de Fallout 4): todas las piezas sobre una rejilla fija de
MODULO = 4 m (medidas.lua), con el origen en una esquina de su celda y sus
puntos de unión como vacíos `union_<lado>` (n, s, e, o, arriba), para que las
reglas de la mina y los robots las encajen.

Piezas (paso 1):
  losa       losa de hormigón 4 x 4 x 0,3 m, cantos achaflanados, juntas y pernos de anclaje
  pilar      pilar de acero en H de 4,3 m con placa base, cartelas y pernos
  muro       muro de 4 m: zócalo de hormigón de 0,6 m, chapa trapezoidal, largueros y remate
  muroPuerta muro con puerta enrollable de 3 x 3,2 m, marco con franjas de aviso
  techo      techo de chapa de 4 x 4 m con correas, a un agua (5°)
"""
import bpy
import bmesh
import math
import sys
from mathutils import Vector

MODULO = 4.0
ALTO = 4.0

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
RENDER = argv[argv.index('--render') + 1] if '--render' in argv else None
BLEND = argv[argv.index('--blend') + 1] if '--blend' in argv else None
EXPORTAR = argv[argv.index('--exportar') + 1] if '--exportar' in argv else None


# Materiales -----------------------------------------------------------------------------------
def material(nombre, color, rug=0.6, metal=0.0):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rug
    b.inputs['Metallic'].default_value = metal
    return m


# Texturas PBR de la biblioteca de la casa (assets/base/materiales/<nombre>:
# albedo, normal y material = metal R, rugosidad G, oclusión B), con el
# tamaño real (m) que cubre cada repetición.
BASE = '~/NationsRTS/assets/base/materiales/'
REPETICION = {}


def materialPbr(nombre, carpeta, metros, tinte=(1, 1, 1)):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    arbol = m.node_tree
    b = next(n for n in arbol.nodes if n.type == 'BSDF_PRINCIPLED')
    def imagen(archivo, color):
        n = arbol.nodes.new('ShaderNodeTexImage')
        n.image = bpy.data.images.load(BASE + carpeta + '/' + archivo, check_existing=True)
        n.image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
        return n
    alb = imagen('albedo.jpg', True)
    mix = arbol.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1
    mix.inputs['B'].default_value = (*tinte, 1)
    arbol.links.new(alb.outputs['Color'], mix.inputs['A'])
    arbol.links.new(mix.outputs['Result'], b.inputs['Base Color'])
    mat = imagen('material.jpg', False)
    sep = arbol.nodes.new('ShaderNodeSeparateColor')
    arbol.links.new(mat.outputs['Color'], sep.inputs['Color'])
    arbol.links.new(sep.outputs['Red'], b.inputs['Metallic'])
    arbol.links.new(sep.outputs['Green'], b.inputs['Roughness'])
    nor = imagen('normal.jpg', False)
    nm = arbol.nodes.new('ShaderNodeNormalMap')
    arbol.links.new(nor.outputs['Color'], nm.inputs['Color'])
    arbol.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    REPETICION[nombre] = metros
    return m


def materiales():
    return {
        'hormigon': materialPbr('kitHormigon', 'baseHormigon', 2.5),
        'chapa': materialPbr('kitChapa', 'baseChapa', 2.0),
        'acero': materialPbr('kitAcero', 'baseAcero', 1.0, (0.45, 0.47, 0.5)),
        'perno': material('kitPerno', (0.55, 0.55, 0.55), 0.35, 1.0),
        'amarillo': materialPbr('kitAviso', 'basePeligro', 0.8),
        'negro': material('kitNegro', (0.03, 0.03, 0.03), 0.6),
        'persiana': materialPbr('kitPersiana', 'baseAcero', 1.0, (1.1, 1.1, 1.1)),
        'vidrio': material('kitVidrio', (0.12, 0.16, 0.18), 0.08, 0.0),
        'alambre': material('kitAlambre', (0.6, 0.6, 0.6), 0.35, 1.0),
    }


def uvCaja(bm, metros, plano=None):
    """UV por proyección de caja en metros reales: cada cara toma el plano de
    su normal dominante; una repetición de textura = `metros`."""
    capa = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for l in f.loops:
            c = l.vert.co
            if plano == 'xz':
                u, v = c.x, c.z
            elif az >= ax and az >= ay:
                u, v = c.x, c.y
            elif ax >= ay:
                u, v = c.y, c.z
            else:
                u, v = c.x, c.z
            l[capa].uv = (u / metros, v / metros)


# Primitivas -----------------------------------------------------------------------------------
def objeto(nombre, bm, mat, padre=None, bisel=0.0, plano=None):
    bm.normal_update()
    uvCaja(bm, REPETICION.get(mat.name, 1.0), plano)
    me = bpy.data.meshes.new(nombre)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    if bisel > 0:
        b = o.modifiers.new('bisel', 'BEVEL')
        b.width = bisel
        b.segments = 2
        b.limit_method = 'ANGLE'
        o.modifiers.new('normales', 'WEIGHTED_NORMAL')
    for p in o.data.polygons:
        p.use_smooth = True
    if padre:
        o.parent = padre
    return o


def caja(nombre, centro, tam, mat, padre=None, bisel=0.01):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * tam[0], v.co.y * tam[1], v.co.z * tam[2])) + Vector(centro)
    return objeto(nombre, bm, mat, padre, bisel)


def cilindro(nombre, centro, r, alto, mat, padre=None, lados=24, eje='z'):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=r, radius2=r, depth=alto)
    for v in bm.verts:
        x, y, z = v.co
        if eje == 'x':
            x, z = z, x
        elif eje == 'y':
            y, z = z, y
        v.co = Vector((x, y, z)) + Vector(centro)
    return objeto(nombre, bm, mat, padre)


def perno(centro, padre, m, eje='z', r=0.022):
    """Tuerca hexagonal con arandela."""
    d = {'z': (0, 0, 1), 'x': (1, 0, 0), 'y': (0, 1, 0)}[eje]
    c = Vector(centro)
    cilindro('arandela', c, r * 1.6, 0.006, m['perno'], padre, 8, eje)
    cilindro('tuerca', c + Vector(d) * 0.012, r, 0.018, m['perno'], padre, 6, eje)


def chapaOndulada(nombre, x0, x1, z0, z1, y, mat, padre, fondo=0.035, paso=0.25, haciaY=-1):
    """Chapa trapezoidal en el plano xz (a la altura y), ondas verticales."""
    bm = bmesh.new()
    pts = []
    x = x0
    tramos = [(0.0, 0.0), (0.06, 0.0), (0.125, fondo), (0.185, fondo), (0.25, 0.0)]
    while x < x1 - 1e-6:
        for a, p in tramos:
            xx = min(x + a * paso / 0.25, x1)
            if not pts or xx > pts[-1][0] + 1e-6:
                pts.append((xx, p))
        x += paso
    abajo = [bm.verts.new((px, y + haciaY * p, z0)) for px, p in pts]
    arriba = [bm.verts.new((px, y + haciaY * p, z1)) for px, p in pts]
    for k in range(len(pts) - 1):
        bm.faces.new((abajo[k], abajo[k + 1], arriba[k + 1], arriba[k]))
    # Grosor de chapa (1,5 mm hacia dentro): se ve por los dos lados.
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.0015)
    o = objeto(nombre, bm, mat, padre, plano='xz')
    # De lejos (LOD1), una placa plana a media onda con la misma textura.
    o['lod1'] = 'placa'
    o['placa'] = (x0, x1, z0, z1, y + haciaY * fondo / 2)
    return o


def vacio(nombre, pos, padre):
    o = bpy.data.objects.new(nombre, None)
    o.empty_display_type = 'ARROWS'
    o.empty_display_size = 0.4
    o.location = pos
    o.parent = padre
    bpy.context.scene.collection.objects.link(o)
    return o


def raiz(nombre):
    o = bpy.data.objects.new(nombre, None)
    o.empty_display_type = 'CUBE'
    o.empty_display_size = 0.1
    bpy.context.scene.collection.objects.link(o)
    o['kit'] = 'mina'
    o['modulo'] = MODULO
    return o


def recortar(poli, x0, x1, z0, z1):
    """Sutherland-Hodgman: el polígono (u, v) recortado al rectángulo."""
    for borde in ((0, x0, 1), (0, x1, -1), (1, z0, 1), (1, z1, -1)):
        eje, lim, sig = borde
        salida = []
        for k in range(len(poli)):
            a, b = poli[k - 1], poli[k]
            da, db = (a[eje] - lim) * sig, (b[eje] - lim) * sig
            if db >= 0:
                if da < 0:
                    f = da / (da - db)
                    salida.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
                salida.append(b)
            elif da >= 0:
                f = da / (da - db)
                salida.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
        poli = salida
        if not poli:
            return []
    return poli


def franjas(nombre, x0, x1, z0, z1, y, m, padre, ancho=0.12):
    """Placa de aviso (textura amarilla y negra a 45°) en el marco."""
    caja(nombre, ((x0 + x1) / 2, y, (z0 + z1) / 2), (x1 - x0, 0.012, z1 - z0), m['amarillo'], padre, 0.002)


# Piezas -------------------------------------------------------------------------------------
def losa(m, x=0.0):
    r = raiz('losa')
    r.location = (x, 0, 0)
    caja('losaCuerpo', (2, 2, -0.15), (MODULO - 0.02, MODULO - 0.02, 0.3), m['hormigon'], r, 0.04)
    # Juntas de dilatación en cruz.
    caja('junta', (2, 2, 0.001), (MODULO - 0.1, 0.02, 0.004), m['negro'], r, 0)
    caja('junta', (2, 2, 0.001), (0.02, MODULO - 0.1, 0.004), m['negro'], r, 0)
    for px in (0.35, MODULO - 0.35):
        for py in (0.35, MODULO - 0.35):
            perno((px, py, 0.0), r, m)
    for nombre, p in (('n', (2, MODULO, 0)), ('s', (2, 0, 0)), ('e', (MODULO, 2, 0)), ('o', (0, 2, 0)), ('arriba', (2, 2, 0))):
        vacio('union_' + nombre, p, r)
    return r


def pilar(m, x=0.0):
    r = raiz('pilar')
    r.location = (x, 0, 0)
    alto = ALTO + 0.3
    a = 0.22
    caja('placaBase', (0, 0, 0.015), (0.42, 0.42, 0.03), m['acero'], r, 0.004)
    caja('alaA', (0, -a / 2 + 0.01, alto / 2), (a, 0.02, alto), m['acero'], r, 0.004)
    caja('alaB', (0, a / 2 - 0.01, alto / 2), (a, 0.02, alto), m['acero'], r, 0.004)
    caja('alma', (0, 0, alto / 2), (0.014, a, alto), m['acero'], r, 0.002)
    for sx in (-1, 1):
        o = caja('cartela', (sx * 0.08, 0, 0.1), (0.12, 0.012, 0.14), m['acero'], r, 0.002)
    for px in (-0.16, 0.16):
        for py in (-0.16, 0.16):
            perno((px, py, 0.03), r, m)
    caja('placaCima', (0, 0, alto - 0.01), (0.3, 0.3, 0.02), m['acero'], r, 0.003)
    franjas('aviso', -a / 2, a / 2, 0.25, 1.25, -a / 2 - 0.012, m, r)
    vacio('union_abajo', (0, 0, 0), r)
    vacio('union_arriba', (0, 0, alto), r)
    return r


def muro(m, x=0.0, conPuerta=False, ventana=False, arriba=False):
    """Muro de un módulo. `ventana`: hueco de 1,6 x 1,3 m con marco y
    vidrio; `arriba`: muro de un piso alto (sin zócalo, la chapa baja hasta
    el forjado)."""
    nombre = 'muroPuerta' if conPuerta else ('muroVentana' if ventana else 'muro')
    r = raiz(nombre + ('Alto' if arriba else ''))
    r.location = (x, 0, 0)
    L = MODULO
    P = 0.12  # medio pilar: el muro empieza y acaba en su ala
    Z0 = 0.0 if arriba else 0.6  # donde empieza la chapa
    VX0, VX1, VZ0, VZ1 = 1.2, 2.8, 1.1, 2.4  # hueco de la ventana
    # Zócalo de hormigón.
    if arriba:
        pass
    elif conPuerta:
        caja('zocalo', ((P + 0.5) / 2, 0, 0.3), (0.5 - P, 0.3, 0.6), m['hormigon'], r, 0.02)
        caja('zocalo', (L - (P + 0.5) / 2, 0, 0.3), (0.5 - P, 0.3, 0.6), m['hormigon'], r, 0.02)
    else:
        caja('zocalo', (L / 2, 0, 0.3), (L - 2 * P, 0.3, 0.6), m['hormigon'], r, 0.02)
    # Largueros de acero (abajo, medio y arriba) y remate.
    largueros = (0.65 if not arriba else 0.1, 2.3 if not ventana else 2.55, ALTO - 0.1)
    for z in largueros:
        if conPuerta and z < 3.3:
            for (a, b) in ((P, 0.5), (L - 0.5, L - P)):
                caja('larguero', ((a + b) / 2, -0.05, z), (b - a, 0.08, 0.1), m['acero'], r, 0.004)
        else:
            caja('larguero', (L / 2, -0.05, z), (L - 2 * P, 0.08, 0.1), m['acero'], r, 0.004)
    caja('remate', (L / 2, 0, ALTO + 0.03), (L - 2 * P, 0.32, 0.06), m['acero'], r, 0.005)
    # Chapa ondulada.
    if conPuerta:
        chapaOndulada('chapa', P, 0.5, 0.6, ALTO, -0.1, m['chapa'], r)
        chapaOndulada('chapa', L - 0.5, L - P, 0.6, ALTO, -0.1, m['chapa'], r)
        chapaOndulada('chapa', 0.5, L - 0.5, 3.4, ALTO, -0.1, m['chapa'], r)
        # Puerta enrollable: tambor, guías y lamas.
        cilindro('tambor', (L / 2, -0.28, 3.55), 0.2, 3.1, m['acero'], r, 24, 'x')
        for gx in (0.52, L - 0.52):
            caja('guia', (gx, -0.13, 1.7), (0.06, 0.08, 3.4), m['acero'], r, 0.004)
        for k in range(32):
            z = 0.05 + k * 0.1
            caja('lama', (L / 2, -0.12, z + 0.045), (L - 1.06, 0.03, 0.085), m['persiana'], r, 0.008)['lod1'] = 'quitar'
        p = caja('persianaLejos', (L / 2, -0.12, 1.65), (L - 1.06, 0.03, 3.2), m['persiana'], r, 0)
        p['lod1'] = 'solo'
        caja('tirador', (L / 2, -0.15, 0.25), (0.4, 0.04, 0.04), m['acero'], r, 0.008)
        franjas('aviso', 0.5, 0.56, 0.05, 3.3, -0.175, m, r, 0.1)
        franjas('aviso', L - 0.56, L - 0.5, 0.05, 3.3, -0.175, m, r, 0.1)
        franjas('avisoDintel', 0.5, L - 0.5, 3.3, 3.4, -0.175, m, r, 0.1)
    elif ventana:
        chapaOndulada('chapa', P, VX0, Z0, ALTO, -0.1, m['chapa'], r)
        chapaOndulada('chapa', VX1, L - P, Z0, ALTO, -0.1, m['chapa'], r)
        chapaOndulada('chapa', VX0, VX1, Z0, VZ0, -0.1, m['chapa'], r)
        chapaOndulada('chapa', VX0, VX1, VZ1, ALTO, -0.1, m['chapa'], r)
        # Marco de acero, vidrio con un parteluz, vierteaguas y premarco.
        g = 0.07
        caja('marco', ((VX0 + VX1) / 2, -0.1, VZ1 + g / 2), (VX1 - VX0 + 2 * g, 0.12, g), m['acero'], r, 0.006)
        caja('marco', ((VX0 + VX1) / 2, -0.1, VZ0 - g / 2), (VX1 - VX0 + 2 * g, 0.12, g), m['acero'], r, 0.006)
        caja('marco', (VX0 - g / 2, -0.1, (VZ0 + VZ1) / 2), (g, 0.12, VZ1 - VZ0), m['acero'], r, 0.006)
        caja('marco', (VX1 + g / 2, -0.1, (VZ0 + VZ1) / 2), (g, 0.12, VZ1 - VZ0), m['acero'], r, 0.006)
        caja('parteluz', ((VX0 + VX1) / 2, -0.07, (VZ0 + VZ1) / 2), (0.05, 0.06, VZ1 - VZ0), m['acero'], r, 0.004)
        caja('vidrio', ((VX0 + VX1) / 2, -0.06, (VZ0 + VZ1) / 2), (VX1 - VX0, 0.012, VZ1 - VZ0), m['vidrio'], r, 0)
        caja('vierteaguas', ((VX0 + VX1) / 2, -0.2, VZ0 - g - 0.02), (VX1 - VX0 + 0.3, 0.2, 0.04), m['acero'], r, 0.008)
    else:
        chapaOndulada('chapa', P, L - P, Z0, ALTO, -0.1, m['chapa'], r)
    # Tornillos de la chapa a los largueros.
    for z in largueros:
        for k in range(9):
            px = 0.25 + k * (L - 0.5) / 8
            if conPuerta and 0.5 < px < L - 0.5 and z < 3.3:
                continue
            if ventana and VX0 - 0.1 < px < VX1 + 0.1 and VZ0 - 0.1 < z < VZ1 + 0.2:
                continue
            perno((px, -0.16, z), r, m, 'y', 0.012)
    vacio('union_izq', (0, 0, 0), r)
    vacio('union_der', (L, 0, 0), r)
    vacio('union_arriba', (L / 2, 0, ALTO), r)
    return r


def concertina(nombre, x0, x1, zc, r, m, padre, vueltas_por_m=3.0):
    """Alambre de cuchillas en espiral (concertina), un tubo fino de 6 lados."""
    bm = bmesh.new()
    n = int((x1 - x0) * vueltas_por_m * 24)
    radio = 0.004
    anillos = []
    for k in range(n + 1):
        f = k / n
        a = f * (x1 - x0) * vueltas_por_m * 2 * math.pi
        c = Vector((x0 + f * (x1 - x0), math.cos(a) * r, zc + math.sin(a) * r))
        t = Vector(((x1 - x0) / n, -math.sin(a) * r * 0.4, math.cos(a) * r * 0.4)).normalized()
        u = t.cross(Vector((0, 0, 1))).normalized() if abs(t.z) < 0.9 else Vector((1, 0, 0))
        v = t.cross(u)
        anillos.append([bm.verts.new(c + (u * math.cos(b) + v * math.sin(b)) * radio)
                        for b in [j / 6 * 2 * math.pi for j in range(6)]])
    for a, b in zip(anillos, anillos[1:]):
        for j in range(6):
            bm.faces.new((a[j], a[(j + 1) % 6], b[(j + 1) % 6], b[j]))
    return objeto(nombre, bm, m['alambre'], padre)


def muroRecinto(m, x=0.0):
    """Muro de recinto: panel prefabricado de hormigón en T invertida de
    3,2 m (como los «T-wall» de las bases militares), con ganchos de izado,
    postes inclinados y concertina arriba. Exterior hacia -y."""
    r = raiz('muroRecinto')
    r.location = (x, 0, 0)
    L = MODULO
    H = 3.2
    caja('panel', (L / 2, 0, H / 2), (L - 0.03, 0.24, H), m['hormigon'], r, 0.025)
    caja('pie', (L / 2, 0.25, 0.15), (L - 0.03, 0.9, 0.3), m['hormigon'], r, 0.025)
    caja('pie', (L / 2, -0.15, 0.1), (L - 0.03, 0.2, 0.2), m['hormigon'], r, 0.02)
    for gx in (0.8, L - 0.8):
        cilindro('gancho', (gx, 0, H + 0.04), 0.03, 0.08, m['acero'], r, 12)
    # Franja de aviso abajo, por fuera.
    franjas('aviso', 0.05, L - 0.05, 0.25, 0.55, -0.125, m, r)
    for px in (0.3, L / 2, L - 0.3):
        # Sin la concertina (nivel 1 en adelante), los postes solos parecían
        # varillas sueltas (el dueño, 19-nov): se van con ella.
        p = caja('poste', (px, -0.12, H + 0.35), (0.04, 0.04, 0.8), m['acero'], r, 0.004)
        p.rotation_euler = (math.radians(-25), 0, 0)
        p['lod1'] = 'quitar'
        caja('brida', (px, -0.13, H - 0.12), (0.08, 0.02, 0.2), m['acero'], r, 0.003)['lod1'] = 'quitar'
    for k in range(3):
        caja('hilo', (L / 2, -0.2 - k * 0.1, H + 0.15 + k * 0.22), (L, 0.006, 0.006), m['alambre'], r, 0)
    concertina('concertina', 0.0, L, H + 0.45, 0.3, m, r)
    vacio('union_izq', (0, 0, 0), r)
    vacio('union_der', (L, 0, 0), r)
    return r


def portonRecinto(m, x=0.0):
    """Portón corredero de acero de un módulo (4 m) entre dos machones de
    hormigón: marco, barrotes, carril y franjas de aviso. Para la entrada
    de un recinto (dos seguidos = 8 m)."""
    r = raiz('portonRecinto')
    r.location = (x, 0, 0)
    L = MODULO
    H = 2.8
    for mx in (0.2, L - 0.2):
        caja('machon', (mx, 0, 1.7), (0.4, 0.4, 3.4), m['hormigon'], r, 0.03)
        caja('remateMachon', (mx, 0, 3.43), (0.46, 0.46, 0.06), m['acero'], r, 0.008)
    x0, x1 = 0.42, L - 0.42
    caja('carril', ((x0 + x1) / 2, 0, 0.02), (x1 - x0, 0.12, 0.04), m['acero'], r, 0.004)
    for z in (0.12, H - 0.06):
        caja('travesano', ((x0 + x1) / 2, 0, z), (x1 - x0, 0.08, 0.12), m['acero'], r, 0.006)
    caja('travesanoMedio', ((x0 + x1) / 2, 0, 1.2), (x1 - x0, 0.06, 0.08), m['acero'], r, 0.005)
    for gx in (x0 + 0.04, x1 - 0.04):
        caja('larguero', (gx, 0, H / 2), (0.08, 0.08, H), m['acero'], r, 0.006)
    n = int((x1 - x0) / 0.14)
    for k in range(1, n):
        bx = x0 + k * (x1 - x0) / n
        caja('barrote', (bx, 0, H / 2), (0.025, 0.025, H - 0.2), m['acero'], r, 0.003)
    for k in range(2):
        cilindro('rueda', (x0 + 0.4 + k * (x1 - x0 - 0.8), 0, 0.09), 0.07, 0.05, m['acero'], r, 16, 'y')
    franjas('aviso', x0, x1, 0.2, 0.5, -0.05, m, r)
    vacio('union_izq', (0, 0, 0), r)
    vacio('union_der', (L, 0, 0), r)
    return r


def techo(m, x=0.0):
    r = raiz('techo')
    r.location = (x, 0, ALTO)
    L = MODULO
    pend = math.radians(5)
    # Correas de acero (perfiles en C) a lo ancho.
    for k in range(4):
        y = 0.15 + k * (L - 0.3) / 3
        caja('correa', (L / 2, y, math.tan(pend) * y + 0.04), (L, 0.06, 0.12), m['acero'], r, 0.004)
    # Chapa: plano ondulado que sube hacia +y (ondas pendiente abajo), sobre las correas.
    t = chapaOndulada('chapaTecho', 0.0, L, 0.0, L / math.cos(pend), 0.0, m['chapa'], r, 0.035, 0.25, -1)  # ondas hacia arriba, valles sobre las correas
    t.rotation_euler = (-(math.radians(90) - pend), 0, 0)
    t.location = (0, 0, 0.12)
    caja('canalon', (L / 2, -0.05, 0.12), (L, 0.12, 0.1), m['acero'], r, 0.01)
    vacio('union_abajo', (L / 2, L / 2, 0), r)
    return r


def escena(m):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    # Fila de piezas sueltas, separadas.
    losa(m, 0)
    pilar(m, 6)
    muro(m, 8)
    muro(m, 13, True)
    techo(m, 19)
    muro(m, 24, ventana=True)
    muroRecinto(m, 29)
    portonRecinto(m, 34)
    # Un módulo armado detrás: losa, 4 pilares, 2 muros, muro con puerta y techo.
    oy = 9.0
    l = losa(m, 0)
    l.location = (4, oy, 0)
    for (px, py) in ((4, oy), (8, oy), (4, oy + 4), (8, oy + 4)):
        p = pilar(m, 0)
        p.location = (px, py, 0)
    a = muro(m, 0, True)
    a.location = (4, oy, 0)
    b = muro(m, 0)
    b.location = (8, oy, 0)
    b.rotation_euler = (0, 0, math.radians(90))
    c = muro(m, 0)
    c.location = (8, oy + 4, 0)
    c.rotation_euler = (0, 0, math.radians(180))
    t = techo(m, 0)
    t.location = (4, oy, ALTO)
    # Persona de referencia (1,8 m).
    cilindro('persona', (2.5, oy - 1.0, 0.9), 0.22, 1.8, material('referencia', (0.9, 0.3, 0.1)), None, 16)


def render(dir_):
    s = bpy.context.scene
    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x, s.render.resolution_y = 1600, 900
    s.view_settings.view_transform = 'Standard'
    mundo = bpy.data.worlds.new('cielo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.55, 0.65, 0.8, 1)
    fondo.inputs['Strength'].default_value = 0.8
    s.world = mundo
    sol = bpy.data.lights.new('sol', 'SUN')
    sol.energy = 4
    so = bpy.data.objects.new('sol', sol)
    so.rotation_euler = (math.radians(50), 0, math.radians(35))
    s.collection.objects.link(so)
    suelo = bpy.data.meshes.new('suelo')
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    bm.to_mesh(suelo)
    so2 = bpy.data.objects.new('suelo', suelo)
    so2.location = (10, 8, -0.3)
    so2.data.materials.append(material('tierra', (0.25, 0.3, 0.15), 1))
    s.collection.objects.link(so2)
    cam = bpy.data.cameras.new('cam')
    co = bpy.data.objects.new('cam', cam)
    s.collection.objects.link(co)
    s.camera = co
    for nombre, pos, mira in (('kit_piezas', (11, -13, 6), (11, 0, 1.8)),
                              ('kit_modulo', (-2, 2, 6.5), (6, 11, 2))):
        co.location = pos
        d = Vector(mira) - Vector(pos)
        co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        s.render.filepath = '%s/%s.png' % (dir_, nombre)
        bpy.ops.render.render(write_still=True)


# Exportación al juego -------------------------------------------------------------------------
# Cada pieza a assets/batalla/kit/<pieza>.lua: por nivel de detalle y por
# material, triángulos con 12 números por vértice (x, y, z, nx, ny, nz, u, v,
# tx, ty, tz, signo de la bitangente)
# en metros y ejes de 3Dream: x igual, y arriba (z de Blender), z = -y de
# Blender (giro, sin espejo). Niveles: 0 completo; 1 (medio) sin biseles,
# sin piezas de menos de 18 cm (pernos, tuercas, ganchos, alambre) y la
# chapa solo por fuera; 2 (lejos) además la chapa como placa plana.
PIEZAS = (
    ('losa', lambda m: losa(m)),
    ('pilar', lambda m: pilar(m)),
    ('muro', lambda m: muro(m)),
    ('muroAlto', lambda m: muro(m, arriba=True)),
    ('muroVentana', lambda m: muro(m, ventana=True)),
    ('muroVentanaAlto', lambda m: muro(m, ventana=True, arriba=True)),
    ('muroPuerta', lambda m: muro(m, conPuerta=True)),
    ('techo', lambda m: techo(m)),
    ('muroRecinto', lambda m: muroRecinto(m)),
    ('portonRecinto', lambda m: portonRecinto(m)),
)


def exportar(dir_, m):
    import os
    os.makedirs(dir_, exist_ok=True)
    for nombre, hacer in PIEZAS:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        r = hacer(m)
        r.location = (0, 0, 0)
        bpy.context.view_layer.update()
        inversa = r.matrix_world.inverted()
        niveles = []
        for lod in (0, 1, 2):
            porMaterial = {}
            for o in bpy.data.objects:
                if o.type != 'MESH':
                    continue
                marca = o.get('lod1')
                if lod == 0 and marca == 'solo':
                    continue
                if lod >= 1:
                    d = o.dimensions
                    if marca == 'quitar' or max(d) < 0.18 or o.data.materials[0].name == 'kitAlambre':
                        continue
                    if lod == 2 and marca == 'placa':
                        # Placa plana (dos caras) en el plano de la chapa.
                        x0, x1, z0, z1, yy = o['placa']
                        mw = inversa @ o.matrix_world
                        mt = REPETICION.get(o.data.materials[0].name, 1.0)
                        lista = porMaterial.setdefault(o.data.materials[0].name, [])
                        esq = [mw @ Vector((x0, yy, z0)), mw @ Vector((x1, yy, z0)), mw @ Vector((x1, yy, z1)), mw @ Vector((x0, yy, z1))]
                        uvs = [(x0 / mt, z0 / mt), (x1 / mt, z0 / mt), (x1 / mt, z1 / mt), (x0 / mt, z1 / mt)]
                        n = (mw.to_3x3() @ Vector((0, -1, 0))).normalized()
                        tg = (mw.to_3x3() @ Vector((1, 0, 0))).normalized()
                        for orden, s in (((0, 1, 2, 0, 2, 3), 1), ((0, 2, 1, 0, 3, 2), -1)):
                            for i in orden:
                                c = esq[i]
                                u, v = uvs[i]
                                lista.extend((c.x, c.z, -c.y, n.x * s, n.z * s, -n.y * s, u, 1 - v, tg.x, tg.z, -tg.y, -s))
                        continue
                for mod in o.modifiers:
                    mod.show_viewport = lod == 0
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                e = o.evaluated_get(dg)
                me = bpy.data.meshes.new_from_object(e)
                tb = bmesh.new()
                tb.from_mesh(me)
                bmesh.ops.triangulate(tb, faces=tb.faces[:])
                tb.to_mesh(me)
                tb.free()
                me.calc_loop_triangles()
                tieneUv = bool(me.uv_layers.active)
                if tieneUv:
                    me.calc_tangents()
                mw = inversa @ o.matrix_world
                nm = mw.to_3x3().inverted().transposed()
                uv = me.uv_layers.active.data if me.uv_layers.active else None
                lista = porMaterial.setdefault(o.data.materials[0].name, [])
                soloFrente = lod == 1 and marca == 'placa'
                # Sin el bisel (niveles 1 y 2), una caja con sombreado suave
                # se ilumina como un cojín (claro en medio, oscuro en los
                # bordes: los paneles del muro parecían bidones, el dueño
                # 19-nov). Esas piezas van con la normal de cada cara.
                plana = lod >= 1 and any(md.type == 'BEVEL' for md in o.modifiers)
                for tri in me.loop_triangles:
                    # Nivel medio: de la chapa, solo la cara de fuera (con sus ondas).
                    if soloFrente and tri.normal.y > -0.2:
                        continue
                    for li in tri.loops:
                        lp = me.loops[li]
                        c = mw @ me.vertices[lp.vertex_index].co
                        n = (nm @ (tri.normal if plana else lp.normal)).normalized()
                        u, v = (uv[li].uv if uv else (0, 0))
                        if tieneUv:
                            tg = (mw.to_3x3() @ lp.tangent).normalized()
                            sg = -lp.bitangent_sign  # la v va volteada (1 - v)
                        else:
                            tg, sg = Vector((1, 0, 0)), 1
                        lista.extend((c.x, c.z, -c.y, n.x, n.z, -n.y, u, 1 - v, tg.x, tg.z, -tg.y, sg))
                bpy.data.meshes.remove(me)
            niveles.append(porMaterial)
        ruta = '%s/%s.lua' % (dir_, nombre)
        with open(ruta, 'w') as f:
            f.write('-- Generado por tools/blender/kit_mina.py --exportar: no editar a mano.\n')
            f.write('-- Pieza «%s»: [nivel][material] = { x, y, z, nx, ny, nz, u, v, tx, ty, tz, s, ... } (m, y arriba).\n' % nombre)
            f.write('return {\n')
            for porMaterial in niveles:
                f.write('    {\n')
                for mat, datos in sorted(porMaterial.items()):
                    f.write('        %s = {' % mat)
                    f.write(','.join('%.4g' % d for d in datos))
                    f.write('},\n')
                f.write('    },\n')
            f.write('}\n')
        print('PIEZA', nombre, ' '.join('n%d=%d' % (k, sum(len(d) for d in n.values()) // 36) for k, n in enumerate(niveles)))


bpy.ops.wm.read_factory_settings(use_empty=True)
mats = materiales()
if EXPORTAR:
    exportar(EXPORTAR, mats)
    sys.exit(0)
escena(mats)
if RENDER:
    render(RENDER)
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)

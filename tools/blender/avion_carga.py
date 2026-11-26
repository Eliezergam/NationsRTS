"""Avión de carga de Nations RTS: silueta (solo volúmenes, escala real).

Lleva a las batallas de minas y ciudades 4 camiones de misiles en 2 filas de 2
(el dueño, 20-nov) y unos 24 robots: «no lo hagas larguísimo, si es posible más
gordo». Todo se dimensiona desde la carga: el camión real del juego
(assets/batalla/robots/camionMisiles.glb) mide 14,0 x 3,5 x 5,0 m. Aterriza en la pista
del sitio y baja la rampa trasera. Diseño propio en la clase de los
turbohélices pesados:

- An-22 (la referencia de tamaño, el turbohélice de carga mayor): 57,9 m de
  largo, 64,4 m de envergadura, 80 t, bodega de 4,4 x 4,4 m con unos 26 m de
  suelo, hélices contrarrotatorias de 6,2 m (Wikipedia «Antonov An-22»,
  GlobalSecurity «An-22 design», aerospaceweb).
- Carga que lo dimensiona: el camión de misiles, 14 m de largo, unos 3,0 m
  de ancho y 3,5 m de alto en marcha, 37-42 t cargado (MAZ-543: American
  Heritage Museum, missilery.info).

Ejes: X hacia delante, Z arriba, el origen en el suelo bajo el centro del
avión, metros. Por etapas, como los robots y el castillete: borrar el objeto
de una etapa con sus hijos y volver a ejecutar solo esa etapa.

Ejecutar dentro de Blender: exec(open(ruta).read()) y luego construir().
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

COLECCION = 'avionCarga'

# Proporciones (m) ------------------------------------------------------------


# Bodega: 2 carriles de 3,52 m con 0,64 m a cada pared y 0,68 entre ellos;
# 2 camiones de 14 m por carril, 0,6 m entre ellos y, delante, 3,6 m para los
# robots. Alto: 5,0 m del camión + 0,6 de holgura.
CAMION = (14.02, 3.52, 4.96)
BODEGA_ANCHO = 9.0
BODEGA_ALTO = 5.6
BODEGA_SUELO = 33.0 # m de suelo plano, sin la rampa (de x = 16,5 a -16,5)
BODEGA_DELANTE = 16.5
ALTO_SUELO = 1.55 # el suelo de la bodega sobre la pista (rampa corta)
FUSELAJE_MEDIO = 5.4 # medio ancho por fuera
# Sección casi cuadrada (exponente 4): con 2,6 las esquinas del suelo de la
# bodega (y = 4,5, z = 1,55) quedaban fuera de la piel.
FUSELAJE_ARRIBA = 7.75 # techo de la bodega (7,15) + 0,6 de estructura

# Fuselaje: secciones (x, z de abajo, z de arriba, medio ancho), de morro a cola.
# La bodega ocupa de x = 16,5 a x = -16,5; la cola sube desde ahí para dejar
# hueco a la rampa. El morro (etapaMorro) sigue desde x = 16,5.
# La panza de la cola sube 18° desde la bisagra de la rampa (x = -16,5).
SECCIONES = (
    (16.5, 0.95, 7.75, 5.4, 4.0),
    (-16.5, 0.95, 7.75, 5.4, 4.0),
    (-20.0, 2.2, 7.75, 5.2, 3.6),
    (-24.0, 3.5, 7.65, 4.5, 3.2),
    (-27.5, 5.6, 7.55, 2.9, 2.8),
    (-30.0, 6.9, 7.45, 0.5, 2.6),
)

# Ala (el dueño, 20-nov): primero «alas de águila, curvadas hacia atrás, un
# poco caídas y levantadas de las puntas»; luego, con la foto del B-2, «que
# se vea más como este», sin plumas. Del ala volante se toma: borde de ataque
# recto con mucha flecha (30°), puntas cortadas limpias, borde de salida en
# dientes de sierra (en W) y una raíz muy ancha que se funde con el lomo. De
# antes se queda la caída suave y la punta un poco levantada.
# Estaciones: (y, x del borde de ataque, x del borde de salida, z); entre
# ellas, rectas (aristas vivas, como el B-2); la z, curva suave.
ALA_FLECHA = math.radians(30)
ALA_RAIZ_X = 11.0 # el centro del ala sobre la carga (centro de la bodega)
ALA_PUNTA_Y = 36.0
ALA = (
    (0.0, None, -11.4, 7.95),
    (5.4, None, -7.2, 7.65),
    (13.2, None, -13.4, 7.1),
    (22.8, None, -7.9, 6.7),
    (28.8, None, -11.2, 6.7),
    (ALA_PUNTA_Y, None, -15.1, 7.25),
)
ALA_GROSOR_RAIZ = 0.12
ALA_GROSOR_PUNTA = 0.08


# Motores enterrados en el ala, como el B-2 (el dueño, 20-nov). Los robots no
# usan combustible: energía avanzada de antes de que se extinguiera la
# humanidad. Por eso no hay escapes calientes: cuatro soplantes carenados
# dentro del ala, cada uno con su toma de aire encima (joroba con la boca
# oscura) y su salida plana en el borde de salida, con el brillo cian de la
# energía (el de los ojos y los núcleos de los robots).
MOTORES_Y = (7.4, 12.4)
TOMA_ANCHO = 4.2
TOMA_ALTO = 1.8 # lo que sube la joroba sobre el ala


# Tren: proa doble y 3 parejas de ruedas por lado en carenados bajo el fuselaje.
RUEDA_RADIO = 0.8



# Herramientas ------------------------------------------------------------------

def coleccion():
    c = bpy.data.collections.get(COLECCION)
    if not c:
        c = bpy.data.collections.new(COLECCION)
        bpy.context.scene.collection.children.link(c)
    return c


def enlazar(objeto, padre=None):
    for c in objeto.users_collection:
        c.objects.unlink(objeto)
    coleccion().objects.link(objeto)
    if padre:
        objeto.parent = padre
    return objeto


def vacio(nombre, padre=None):
    o = bpy.data.objects.new(nombre, None)
    return enlazar(o, padre)


def malla(nombre, construir, padre=None):
    """Objeto con una malla hecha por `construir(bm)` (bmesh, sin bpy.ops)."""
    bm = bmesh.new()
    construir(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = bpy.data.meshes.new(nombre)
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.new(nombre, m)
    for p in m.polygons:
        p.use_smooth = True
    return enlazar(o, padre)


def caja(nombre, centro, medidas, padre=None):
    def hacer(bm):
        bmesh.ops.create_cube(bm, size=1, matrix=Matrix.Translation(centro) @ Matrix.Diagonal((*medidas, 1)))

    return malla(nombre, hacer, padre)


def cilindro(nombre, centro, radio, largo, eje='X', padre=None, vertices=64, tapas=True):
    giro = {
        'X': Matrix.Rotation(math.pi / 2, 4, 'Y'),
        'Y': Matrix.Rotation(math.pi / 2, 4, 'X'),
        'Z': Matrix.Identity(4),
    }[eje]

    def hacer(bm):
        bmesh.ops.create_cone(bm, cap_ends=tapas, segments=vertices, radius1=radio, radius2=radio, depth=largo, matrix=Matrix.Translation(centro) @ giro)

    return malla(nombre, hacer, padre)


def anillo(bm, x, abajo, arriba, medio, n=48, exponente=2.6):
    """Sección redondeada (superelipse) del fuselaje en x."""
    cz = (abajo + arriba) / 2
    rz = (arriba - abajo) / 2
    puntos = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        # Exponente 2,6: lados casi rectos (bodega cuadrada) y esquinas
        # redondas; más alto, más cuadrado (la cabeza, de aristas duras).
        e = 2 / exponente
        y = medio * math.copysign(abs(c) ** e, c)
        z = cz + rz * math.copysign(abs(s) ** e, s)
        puntos.append(bm.verts.new((x, y, z)))
    return puntos


def loft(bm, anillos):
    for a, b in zip(anillos, anillos[1:]):
        n = len(a)
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(anillos[0])
    bm.faces.new(list(reversed(anillos[-1])))


def superficie(nombre, raiz, punta, cuerdaRaiz, cuerdaPunta, grosor, padre=None, n=24):
    """Ala o cola: de `raiz` a `punta` (bordes de ataque), perfil simétrico
    redondeado en el plano XZ (o XY si la superficie es vertical)."""
    def perfil(bm, origen, cuerda, normal):
        puntos = []
        for i in range(n):
            t = i / (n - 1)
            # NACA 00xx aproximado: espesor por la cuerda.
            x = t
            e = 5 * grosor * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
            puntos.append((x, e))
        anillo_ = []
        for x, e in puntos:
            anillo_.append(Vector(origen) + Vector((-x * cuerda, 0, 0)) + normal * e * cuerda)
        for x, e in reversed(puntos[1:-1]):
            anillo_.append(Vector(origen) + Vector((-x * cuerda, 0, 0)) - normal * e * cuerda)
        return [bm.verts.new(p) for p in anillo_]

    raiz, punta = Vector(raiz), Vector(punta)
    lado = (punta - raiz)
    lado.x = 0
    normal = lado.cross(Vector((1, 0, 0))).normalized()

    def hacer(bm):
        loft(bm, [perfil(bm, raiz, cuerdaRaiz, normal), perfil(bm, punta, cuerdaPunta, normal)])

    return malla(nombre, hacer, padre)


def borrar(nombre):
    o = bpy.data.objects.get(nombre)
    if not o:
        return
    for h in list(o.children_recursive):
        bpy.data.objects.remove(h)
    bpy.data.objects.remove(o)


# Etapas -----------------------------------------------------------------------

def cascoFuselaje(bm):
    loft(bm, [anillo(bm, x, abajo, arriba, medio, n=64, exponente=e) for x, abajo, arriba, medio, e in SECCIONES])


def tapar(bm):
    """Cierra los huecos que deja un corte (caras nuevas en triángulos)."""
    bordes = [e for e in bm.edges if e.is_boundary]
    nuevas = bmesh.ops.holes_fill(bm, edges=bordes, sides=0)['faces']
    bmesh.ops.triangulate(bm, faces=nuevas)


def pieza(nombre, cortes, padre=None, cerrar=False, grosor=0.0):
    """Trozo del casco del fuselaje: `cortes` = [(punto, normal)], se quita
    lo que queda del lado de cada normal. `grosor`: chapa (Solidify) para
    las piezas que se abren y dejan ver el canto."""
    def hacer(bm):
        cascoFuselaje(bm)
        for punto, normal in cortes:
            cortar(bm, punto, normal)
        if cerrar:
            tapar(bm)

    o = malla(nombre, hacer)
    if grosor:
        m = o.modifiers.new('chapa', 'SOLIDIFY')
        m.thickness = grosor
        m.offset = -1
    if padre:
        bpy.context.view_layer.update() # la matriz del vacío recién movido
        o.parent = padre
        o.matrix_parent_inverse = padre.matrix_world.inverted()
    return o


# Abertura trasera, como la del C-5 (dos puertas de pétalo con bisagra
# vertical en los costados y la rampa debajo, con bisagra en el borde del
# suelo). Para que salga un camión de 5,0 m: hueco de 10,8 m de ancho y del
# suelo (1,55) al techo de la bodega (7,15).
PUERTA_ABIERTA = math.radians(90) # cada pétalo, hacia fuera
RAMPA_CERRADA = math.radians(18) # sube hacia atrás siguiendo la panza
# Abierta: la panza de la punta apoya en la pista (z = 0, medido en
# Blender); la cubierta queda a 8,55° de bajada y su borde a 0,43 m del suelo.
RAMPA_ABIERTA = math.radians(-26.55)


def etapaFuselaje():
    """Fuselaje fijo, techo de la cola y las piezas que se abren (para Lua):

    - `puertaI`, `puertaD`: vacíos en la bisagra (x = -16,5, y = +-5,4),
      giran sobre Z. 0 cerrada; abierta `puertaI` -90° y `puertaD` +90°
      (hacia fuera). Sus mallas cuelgan de ellos.
    - `rampa`: vacío en la bisagra (x = -16,5, z = 1,55, borde del suelo),
      gira sobre Y. 0 cerrada; abierta -26,55° (apoya en la pista).
    Primero las puertas, luego la rampa; para cerrar, al revés."""
    for n in ('fuselaje', 'colaTecho', 'puertaI', 'puertaD', 'rampa'):
        borrar(n)
    bx = -BODEGA_DELANTE
    techo = ALTO_SUELO + BODEGA_ALTO
    a = RAMPA_CERRADA
    xr = bx - 7.5 * math.cos(a) # punta de la rampa
    sobreRampa = Vector((math.sin(a), 0, math.cos(a))) # normal del plano de la rampa
    bisagraRampa = (bx, 0, ALTO_SUELO)
    # El fuselaje fijo: hasta la bisagra (abierto por detrás: es la puerta).
    raiz = pieza('fuselaje', [((bx, 0, 0), (-1, 0, 0))])
    # Techo de la cola (con la cola encima), por encima del hueco.
    pieza('colaTecho', [((bx, 0, 0), (1, 0, 0)), ((0, 0, techo), (0, 0, -1))], raiz, cerrar=True)
    # Rampa: la panza bajo su plano, de la bisagra a su punta; la cara de
    # arriba del corte es la cubierta por la que bajan los camiones.
    rampa = vacio('rampa', raiz)
    rampa.location = bisagraRampa
    pieza('rampaPiel', [((bx, 0, 0), (1, 0, 0)), ((xr, 0, 0), (-1, 0, 0)), (bisagraRampa, sobreRampa)], rampa, cerrar=True)
    # Pétalos: lo demás bajo el techo, partido por la mitad.
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        puerta = vacio('puerta' + s, raiz)
        puerta.location = (bx, lado * FUSELAJE_MEDIO, 0)
        mitad = ((0, 0, 0), (0, -lado, 0))
        bajoTecho = ((0, 0, techo), (0, 0, 1))
        # Detrás de la punta de la rampa: todo.
        pieza('puerta%sCola' % s, [((xr, 0, 0), (1, 0, 0)), bajoTecho, mitad], puerta, grosor=0.15)
        # Sobre la rampa.
        pieza('puerta%sLado' % s, [((bx, 0, 0), (1, 0, 0)), ((xr, 0, 0), (-1, 0, 0)), bajoTecho, mitad, (bisagraRampa, -sobreRampa)], puerta, grosor=0.15)
    return raiz


def poseCarga(puertas, rampa):
    """Pose de la abertura trasera (0 cerrada, 1 abierta) como la pondrá
    Lua: `puertas` y `rampa` por separado."""
    bpy.data.objects['puertaI'].rotation_euler.z = -PUERTA_ABIERTA * puertas
    bpy.data.objects['puertaD'].rotation_euler.z = PUERTA_ABIERTA * puertas
    bpy.data.objects['rampa'].rotation_euler.y = RAMPA_ABIERTA * rampa


# Morro con visor de máquina (el dueño, 20-nov: la cabeza cuadrada «no
# combina nada con el avión»; eligió «visor de máquina»). El fuselaje sigue
# sin cortes hasta una punta afilada de sección en rombo, como las aristas
# del lomo (que ahora llegan hasta ella): todo es una pieza. Cruza la cara
# una banda oscura de visor que envuelve los costados y, detrás, dos
# rendijas cian (los ojos).
MORRO = (
    # x, z abajo, z arriba, medio ancho, exponente (2,6 = fuselaje; menos,
    # rombo de aristas vivas)
    (16.5, 0.95, 7.75, 5.4, 4.0),
    (19.0, 1.25, 7.6, 5.1, 2.8),
    (21.5, 2.0, 7.15, 4.2, 1.8),
    (23.6, 2.9, 6.45, 3.1, 1.55),
    (25.2, 3.8, 5.65, 1.8, 1.4),
    (26.2, 4.4, 5.1, 0.6, 1.3),
    (26.6, 4.65, 4.85, 0.06, 1.3),
)
VISOR = (19.6, 26.0, 5.1, 6.55) # x de, x a, z de, z a (banda horizontal)
VISOR_MARCO = 0.18 # m de marco de acero alrededor de la banda
OJOS_VISOR = (1.55, 5.75, 2.1, 0.4) # |y| del centro, z, largo, alto de cada rendija


def seccionMorro(x):
    """(z abajo, z arriba, medio ancho, exponente) del morro en x (lineal)."""
    if x <= MORRO[0][0]:
        return MORRO[0][1:]
    for a, b in zip(MORRO, MORRO[1:]):
        if a[0] <= x <= b[0]:
            u = (x - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * u for i in range(1, 5))
    return MORRO[-1][1:]


def cascoMorro(bm, desplazar=0.0):
    """La superficie del morro (anillos de MORRO); `desplazar` la separa
    tanto hacia fuera por su normal (para el visor y lo que va encima)."""
    anillos = []
    pasos = 60
    x0, x1 = MORRO[0][0], MORRO[-1][0]
    for k in range(pasos + 1):
        x = x0 + (x1 - x0) * k / pasos
        abajo, arriba, medio, e = seccionMorro(x)
        anillos.append(anillo(bm, x, abajo, arriba, medio, n=128, exponente=e))
    loft(bm, anillos)
    if desplazar:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * desplazar


def cortar(bm, punto, normal):
    """Quita de la malla lo que queda del lado de `normal` del plano."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=punto, plane_no=normal, clear_outer=True)


def etapaMorro():
    borrar('cabeza')
    borrar('morro')
    raiz = vacio('morro')
    vx0, vx1, vz0, vz1 = VISOR
    oy, oz, ol, oa = OJOS_VISOR
    malla('morroCasco', cascoMorro, raiz)

    # Visor y su marco: copias del casco despegadas y cortadas por planos
    # (bordes rectos y limpios), cada una una pieza.
    def banda(z0, z1, x0, desplazar):
        def hacer(bm):
            cascoMorro(bm, desplazar)
            cortar(bm, (0, 0, z1), (0, 0, 1))
            cortar(bm, (0, 0, z0), (0, 0, -1))
            cortar(bm, (x0, 0, 0), (-1, 0, 0))
        return hacer

    m = VISOR_MARCO
    malla('visorMarco', banda(vz0 - m, vz1 + m, vx0 - m, 0.02), raiz)
    malla('visor', banda(vz0, vz1, vx0, 0.04), raiz)
    # Ojos: rendijas cian sobre el visor, inclinadas hacia el centro (más
    # bajas por dentro: mirada dura). Piezas `ojoVisorI/D` (brillo desde Lua).
    inclinacion = math.radians(9)
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'

        def rendija(bm, lado=lado):
            cascoMorro(bm, 0.06)
            # Arriba y abajo: planos inclinados (sube hacia fuera).
            arriba = Vector((0, -lado * math.sin(inclinacion), math.cos(inclinacion)))
            cortar(bm, (0, lado * oy, oz + oa / 2), arriba)
            cortar(bm, (0, lado * oy, oz - oa / 2), -arriba)
            # A los lados: de |y| = oy - ol/2 a oy + ol/2.
            cortar(bm, (0, lado * (oy + ol / 2), 0), (0, lado, 0))
            cortar(bm, (0, lado * (oy - ol / 2), 0), (0, -lado, 0))
            cortar(bm, (vx0, 0, 0), (-1, 0, 0))

        malla('ojoVisor' + s, rendija, raiz)
    return raiz


def prisma(nombre, contornos, padre=None):
    """Sólido que une contornos con el mismo número de puntos (cada uno
    una lista de (x, y, z)), con tapas en los extremos."""
    def hacer(bm):
        loft(bm, [[bm.verts.new(p) for p in c] for c in contornos])
        # Las tapas pueden no ser planas: en triángulos, sin caras raras.
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])

    return malla(nombre, hacer, padre)



def catmull(p0, p1, p2, p3, u):
    return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)


def estacionAla(y):
    """(x del borde de ataque, z, cuerda) del ala a `y` m del centro."""
    y = min(abs(y), ALA_PUNTA_Y)
    ataque = ALA_RAIZ_X - y * math.tan(ALA_FLECHA)
    for k in range(len(ALA) - 1):
        if ALA[k][0] <= y <= ALA[k + 1][0]:
            u = (y - ALA[k][0]) / (ALA[k + 1][0] - ALA[k][0])
            salida = ALA[k][2] + (ALA[k + 1][2] - ALA[k][2]) * u
            a = ALA[max(k - 1, 0)]
            d = ALA[min(k + 2, len(ALA) - 1)]
            z = catmull(a[3], ALA[k][3], ALA[k + 1][3], d[3], u)
            return ataque, z, max(ataque - salida, 0.3)
    return ataque, ALA[-1][3], 0.3


def perfil(bm, origen, cuerda, grosor, normal, n=24):
    """Perfil simétrico (NACA 00xx) con el borde de ataque en `origen`,
    hacia -X, de espesor a lo largo de `normal`."""
    puntos = []
    for i in range(n):
        x = i / (n - 1)
        e = 5 * grosor * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        puntos.append((x, e))
    anillo_ = [Vector(origen) + Vector((-x * cuerda, 0, 0)) + normal * e * cuerda for x, e in puntos]
    anillo_ += [Vector(origen) + Vector((-x * cuerda, 0, 0)) - normal * e * cuerda for x, e in reversed(puntos[1:-1])]
    return [bm.verts.new(p) for p in anillo_]


def etapaAla():
    borrar('ala')
    raiz = vacio('ala')
    # Estaciones: en cada quiebro del borde de salida (aristas vivas) y
    # entre ellos, para la caída suave.
    ys = sorted(set([e[0] for e in ALA] + [ALA_PUNTA_Y * k / 40 for k in range(41)]))
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'

        def hacer(bm):
            anillos = []
            for y in ys:
                x, z, c = estacionAla(y)
                f = y / ALA_PUNTA_Y
                grosor = ALA_GROSOR_RAIZ + (ALA_GROSOR_PUNTA - ALA_GROSOR_RAIZ) * f
                # La punta, cortada limpia: la última estación casi sin grosor.
                if y >= ALA_PUNTA_Y:
                    grosor = 0.02
                anillos.append(perfil(bm, (x, lado * y, z), c, grosor, Vector((0, 0, 1))))
            loft(bm, anillos)

        malla('ala' + s, hacer, raiz)
    return raiz


def alturaAla(y):
    return estacionAla(y)[1]


def bordeAtaque(y):
    return estacionAla(y)[0]


def encimaAla(x, y):
    """z de la cara de arriba del ala en (x, y)."""
    ataque, z, cuerda = estacionAla(y)
    u = min(max((ataque - x) / cuerda, 0.0), 1.0)
    f = abs(y) / ALA_PUNTA_Y
    grosor = ALA_GROSOR_RAIZ + (ALA_GROSOR_PUNTA - ALA_GROSOR_RAIZ) * f
    e = 5 * grosor * (0.2969 * math.sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u ** 3 - 0.1036 * u ** 4)
    return z + e * cuerda


def etapaMotores():
    borrar('motores')
    raiz = vacio('motores')
    for k, y in enumerate((MOTORES_Y[1], MOTORES_Y[0], -MOTORES_Y[0], -MOTORES_Y[1])):
        ataque, z, cuerda = estacionAla(y)
        x0 = ataque - 0.1 * cuerda # la boca de la toma
        x1 = ataque - 0.85 * cuerda # la salida

        # Joroba: secciones de x0 a x1, alta delante (la boca) y que se funde
        # con el ala detrás.
        def joroba(bm, y=y):
            anillos = []
            pasos = 12
            for i in range(pasos + 1):
                u = i / pasos
                x = x0 + (x1 - x0) * u
                alto = TOMA_ALTO * (1 - u) ** 0.6 + 0.12
                medio = TOMA_ANCHO / 2 * (1 - 0.35 * u)
                base = encimaAla(x, y) - 0.3
                seccion = anillo(bm, x, base, base + 0.3 + alto, medio, n=32, exponente=3)
                for v in seccion:
                    v.co.y += y
                anillos.append(seccion)
            loft(bm, anillos)

        malla('toma%d' % (k + 1), joroba, raiz)
        # Boca oscura de la toma y salida plana con el brillo de la energía.
        zb = encimaAla(x0, y)
        caja('bocaToma%d' % (k + 1), (x0 + 0.05, y, zb + TOMA_ALTO * 0.45), (0.12, TOMA_ANCHO * 0.82, TOMA_ALTO * 0.7), raiz)
        zs = encimaAla(x1, y)
        caja('salida%d' % (k + 1), (x1 - 0.1, y, zs + 0.2), (0.2, TOMA_ANCHO * 0.8, 0.3), raiz)
    return raiz


def desplazar(seccion, dy):
    for v in seccion:
        v.co.y += dy
    return seccion


def etapaTren():
    """Tren de un carguero de unas 180 t de carga (clase C-5): a cada lado
    un carenado redondeado y fundido con la panza, con 4 ejes de 2 ruedas;
    delante, tren de proa de 4 ruedas bajo el morro."""
    borrar('tren')
    raiz = vacio('tren')
    # Carenado: secciones a lo largo de x (centro y, abajo, arriba, medio ancho).
    SECCIONES_CARENADO = (
        (9.5, 5.3, 1.9, 3.4, 0.3),
        (7.0, 5.6, 1.05, 4.0, 1.0),
        (-7.0, 5.6, 1.05, 4.0, 1.0),
        (-9.5, 5.3, 1.6, 3.6, 0.35),
    )
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'

        def carenado(bm, lado=lado):
            loft(bm, [desplazar(anillo(bm, x, abajo, arriba, medio, n=32, exponente=2.4), lado * y) for x, y, abajo, arriba, medio in SECCIONES_CARENADO])

        malla('carenado' + s, carenado, raiz)
        for k, x in enumerate((-5.1, -1.7, 1.7, 5.1)):
            for j, dy in enumerate((-0.42, 0.42)):
                cilindro('rueda%s%d%s' % (s, k + 1, 'ab'[j]), (x, lado * (5.6 + dy), RUEDA_RADIO), RUEDA_RADIO, 0.46, 'Y', raiz)
    for j, dy in enumerate((-1.2, -0.4, 0.4, 1.2)):
        cilindro('ruedaProa' + 'abcd'[j], (19.5, dy, 0.65), 0.65, 0.4, 'Y', raiz)
    # Pata de proa (dentro del morro, que en x = 19,5 acaba en z = 1,5).
    cilindro('pataProa', (19.5, 0, 1.2), 0.22, 1.2, 'Z', raiz, 24)
    return raiz


def etapaLomo():
    """Aristas vivas del lomo (chines), como el B-2: a cada lado una arista
    afilada que nace en los pómulos de la cabeza, se abre hacia atrás y se
    funde con el borde de ataque del ala. Une la cabeza (más ancha) con el
    fuselaje y el fuselaje con el ala; da el corte facetado de todo el
    avión. Secciones: (x, y de la arista, z de la arista)."""
    borrar('lomo')
    raiz = vacio('lomo')
    # La arista va por la esquina del rombo del morro (mitad de su alto) y,
    # detrás, se abre y sube hasta entrar en el borde de ataque del ala.
    aristas = []
    x0, punta = MORRO[0][0], MORRO[-1][0]
    medio = FUSELAJE_MEDIO
    zMedio = (MORRO[0][1] + MORRO[0][2]) / 2
    # Donde la arista (a medio ancho + 0,3) entra en el borde de ataque.
    fin = ALA_RAIZ_X - (medio + 0.6) * math.tan(ALA_FLECHA)
    xs = [punta - 0.2] + [x0 + (punta - 0.2 - x0) * k / 5 for k in range(4, -1, -1)][1:]
    xs += [x0 - (x0 - fin) * k / 6 for k in range(1, 7)]
    for x in xs:
        if x >= x0:
            abajo, arriba, ancho, e = seccionMorro(x)
            y = ancho + 0.3 * (punta - x) / (punta - x0)
            z = (abajo + arriba) / 2
            tope = arriba
            # Alto del filo: no más que un cuarto del alto del morro (en la
            # punta, que es fina, no puede sobresalir arriba ni abajo).
            filo = min(0.4, (arriba - abajo) * 0.25)
        else:
            u = (x0 - x) / (x0 - fin)
            borde = (ALA_RAIZ_X - x) / math.tan(ALA_FLECHA) if x < ALA_RAIZ_X else 0.0
            y = max(medio + 0.3 + 0.6 * u ** 1.4, borde + 0.2)
            z = zMedio + (FUSELAJE_ARRIBA - 0.2 - zMedio) * u ** 1.5
            tope = FUSELAJE_ARRIBA
            filo = 0.4
        aristas.append((x, y, z, tope, filo))
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        contornos = []
        for x, y, z, tope, filo in aristas:
            # Triángulo: arriba, arista, abajo. En el morro, un filo bajo
            # (±0,4 m, por debajo del visor y metido en la piel aunque la
            # punta se estreche); detrás se abre hasta el hombro del lomo
            # en 3 m.
            u = min(max((x0 - x) / 3.0, 0.0), 1.0)
            dentro = max(y - 0.55, 0.0)
            arriba = ((1 - u) * dentro + u * y * 0.5, (1 - u) * (z + filo) + u * (tope - 0.08))
            abajo = ((1 - u) * dentro + u * y * 0.82, (1 - u) * (z - filo) + u * (z - 0.9))
            contornos.append([(x, lado * arriba[0], arriba[1]), (x, lado * y, z), (x, lado * abajo[0], abajo[1])])
        prisma('arista' + s, contornos, raiz)
    # Carenado de la raíz del ala sobre el lomo: de la arista al ala, para que
    # no quede posada encima.
    def carenadoRaiz(bm):
        secciones = []
        for x in (11.5, 7.5, 1.5, -4.5, -10.0):
            arriba = encimaAla(x, 3.4) if x <= ALA_RAIZ_X else FUSELAJE_ARRIBA
            secciones.append(anillo(bm, x, 6.2, max(arriba, FUSELAJE_ARRIBA + 0.1), 4.6, n=40, exponente=3.5))
        loft(bm, secciones)

    malla('carenadoRaiz', carenadoRaiz, raiz)
    return raiz


# Cola en garras: estabilizador con una deriva en cada punta, curvada hacia
# atrás y con la punta hacia dentro, como una garra (la idea de las garras de
# la nave de la foto del dueño, con diseño propio). Estaciones de la deriva:
# (fracción de la altura, x del borde de ataque, cuerda, cuánto se mete hacia
# dentro).
COLA_X = -22.5
COLA_Z = 7.7
COLA_ALTO = 14.6
ESTABILIZADOR_Y = 10.5
GARRA = (
    (0.0, -0.7, 7.0, 0.0),
    (0.3, -1.85, 5.8, 0.12),
    (0.6, -3.45, 4.2, 0.4),
    (0.85, -4.6, 2.5, 0.85),
    (1.0, -4.7, 0.8, 1.25),
)


def etapaCola():
    borrar('cola')
    raiz = vacio('cola')
    for lado in (1, -1):
        s = 'I' if lado > 0 else 'D'
        superficie('estabilizador' + s, (COLA_X - 0.5, 0, COLA_Z + 0.2), (COLA_X - 4.0, lado * ESTABILIZADOR_Y, COLA_Z + 0.45), 7.5, 4.8, 0.11, raiz)
        z0 = COLA_Z + 0.4

        def garra(bm, lado=lado):
            anillos = []
            for f, x, c, dentro in GARRA:
                z = z0 + f * (COLA_ALTO - z0)
                anillos.append(perfil(bm, (COLA_X - 2.4 + x, lado * (ESTABILIZADOR_Y - dentro), z), c, 0.12, Vector((0, 1, 0))))
            loft(bm, anillos)

        malla('garra' + s, garra, raiz)
    return raiz


CAMION_GLB = '~/NationsRTS/assets/batalla/robots/camionMisiles.glb'


def importarCamion(nombre, x, y, padre):
    """El camión de misiles del juego (el .glb real), con el morro hacia +X
    y las ruedas en el suelo de la bodega. Sus piezas llevan `carga` = 1
    para que etapaColores no les cambie el material."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=CAMION_GLB)
    nuevos = [o for o in bpy.data.objects if o not in antes]
    caja = vacio(nombre, padre)
    for o in nuevos:
        o['carga'] = 1
        enlazar(o)
        if o.parent is None:
            o.parent = caja
    # El .glb: de x = -5,5 a 8,51 y las ruedas en z = -0,96.
    caja.location = (x - (8.51 - 5.5) / 2, y, ALTO_SUELO + 0.96)
    return caja


def etapaCarga():
    """La carga de verdad: 4 camiones de misiles (el modelo del juego) en 2
    filas de 2 y, delante, 24 robots de 1,85 m de pie."""
    borrar('carga')
    raiz = vacio('carga')
    largo, ancho, alto = CAMION
    carril = ancho / 2 + 0.34 # centro de cada carril
    delante = BODEGA_DELANTE - 3.6 - 0.3 # morro del primer camión
    for fila in range(2):
        frente = delante - fila * (largo + 0.6)
        for k, lado in enumerate((1, -1)):
            importarCamion('camion%d%s' % (fila + 1, 'ID'[k]), frente - largo / 2, lado * carril, raiz)
    for i in range(3):
        for j in range(8):
            cilindro('robot%d_%d' % (i, j), (BODEGA_DELANTE - 0.7 - i * 1.1, -3.85 + j * 1.1, ALTO_SUELO + 0.925), 0.3, 1.85, 'Z', raiz, 16)
    caja('bodegaUtil', (0.0, 0, ALTO_SUELO + BODEGA_ALTO / 2), (BODEGA_SUELO, BODEGA_ANCHO, BODEGA_ALTO), raiz)
    bpy.data.objects['bodegaUtil'].display_type = 'WIRE'
    bpy.data.objects['bodegaUtil'].hide_render = True
    return raiz


def material(nombre, color, rugosidad=0.4, metal=0.6, brillo=None):
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rugosidad
    bsdf.inputs['Metallic'].default_value = metal
    if brillo:
        bsdf.inputs['Emission Color'].default_value = (*brillo, 1)
        bsdf.inputs['Emission Strength'].default_value = 8.0
    m.diffuse_color = (*color, 1)
    return m


def etapaColores():
    """Colores provisionales de la casa para juzgar la silueta (las texturas
    PBR van con el detalle): carcasa negra semibrillante, cuencas y boca
    negras mate, ojos cian que brillan."""
    carcasa = material('carcasa', (0.03, 0.03, 0.035), 0.35, 0.7)
    hueco = material('hueco', (0.005, 0.005, 0.005), 0.9, 0.0)
    ojo = material('ojoCian', (0.1, 0.8, 1.0), 0.2, 0.0, (0.15, 0.85, 1.0))
    acero = material('acero', (0.35, 0.36, 0.38), 0.3, 1.0)
    cobre = material('cobre', (0.75, 0.38, 0.2), 0.3, 1.0)
    globo = material('globo', (0.02, 0.02, 0.025), 0.25, 0.8)
    visor = material('visor', (0.002, 0.004, 0.008), 0.02, 0.0)
    for o in bpy.data.collections[COLECCION].objects:
        if o.type != 'MESH' or o.get('carga') or o.get('detalle'):
            continue
        o.data.materials.clear()
        if o.name.startswith(('nucleo', 'diafragma', 'salida')):
            o.data.materials.append(ojo)
        elif o.name.startswith('anillo'):
            o.data.materials.append(cobre)
        elif o.name.startswith('globo'):
            o.data.materials.append(globo)
        elif o.name.startswith('collar'):
            o.data.materials.append(acero)
        elif o.name.startswith(('cuenca', 'fondoCuenca', 'lama', 'bocaToma')):
            o.data.materials.append(hueco)
        elif o.name.startswith(('helice', 'rueda')):
            o.data.materials.append(acero)
        elif o.name == 'bodegaUtil' or o.name.startswith('robot'):
            o.data.materials.append(acero)
        elif o.name == 'visor':
            o.data.materials.append(visor)
        elif o.name == 'visorMarco':
            o.data.materials.append(acero)
        elif o.name.startswith('ojoVisor'):
            o.data.materials.append(ojo)
        else:
            o.data.materials.append(carcasa)


def construir():
    etapaFuselaje()
    etapaMorro()
    etapaLomo()
    etapaAla()
    etapaMotores()
    etapaTren()
    etapaCola()
    etapaCarga()
    etapaColores()


if __name__ == '__main__':
    construir()

# Encargo: recrear el ojo mecánico de los robots de Nations RTS

Recrea en Blender, exactamente igual, el ojo mecánico de los robots del juego. Abajo tienes la descripción, las
medidas, los nombres que espera el juego y **el script completo que lo genera**.

Probado con Blender 5.3: el script se ejecuta sin errores y genera los dos ojos de la imagen de referencia,
`ojo-robot-referencia.png`.

```sh
blender --python ojo_robot.py              # con ventana
blender -b --python ojo_robot.py           # sin ventana
```

**No cambies medidas, nombres ni la jerarquía:** el juego mueve cada pieza buscándola por su nombre.

## 1. Convenciones

- **Unidades:** metros. Todo se modela a escala 1 y cada robot pasa su escala `e` (robot pequeño 1; soldado 0,95;
  robot grande 2,8).
- **Ejes:** el ojo mira hacia **+X**; Z es arriba e Y va a lo ancho.
- **Posición:** `xf` es la X de la cara del robot y `(y, zc)` es el centro del ojo.
- **Piezas:** cada pieza que se mueve es **un objeto unido** con su **origen en el pivote** y emparentado a su padre.
- **Sombreado:** suave, con bordes vivos a partir de 30°.
- **Nombres:** `{S}` es el lado del ojo, `Izq` o `Der`.

## 2. Dos variantes

| Variante | Robot | Partes |
|---|---|---|
| **Ojo plano** (`ojoPlano`) | Robot pequeño | Cuenca fija, ojo móvil con iris, aro de cobre, diafragma plano de 18 láminas y dos párpados blindados |
| **Ojo globo** (`ojoGlobo`) | Soldado y robot grande | Cuenca con el tubo alargado 7 mm, globo esférico cortado por delante con las piezas del ojo a ×0,8, diafragma en punta (cono) y párpados de persiana de 4 láminas por lado |

## 3. Las piezas, de fuera a dentro

### Cuenca fija (`cuenca{S}`, hija de la cabeza)

| Pieza | Medidas | Material |
|---|---|---|
| Carcasa | Tubo de radio interior 3,4 cm y exterior 4,4 cm; sobresale 2 cm de la cara; cantos biselados | `negro` |
| Bisel | Aro de 3,5 a 4,3 cm de radio, 4 mm de grueso | `acero` |
| Dientes del bisel | 48 cubitos de 3 mm girados 45°, en círculo a 4,05 cm del centro | `acero` |
| Tornillos | 8 hexagonales, a 3,65 cm del centro, uno cada 45° (desfase de 22,5°) | `acero` |
| Fondo | Disco de radio 3,4 cm, 9 mm detrás del frente de la carcasa | `visor` |

### Ojo móvil (`ojo{S}`, hijo de la cabeza; en la variante globo, hijo del globo)

| Pieza | Medidas | Material |
|---|---|---|
| Fondo del iris | Disco de radio 2,5 cm | `articulacion` |
| Halo | Aro de 0,6 a 1,25 cm de radio | `iris` (emite luz) |
| Núcleo | Disco de radio 0,75 cm | `nucleo` (emite luz) |
| Centro del núcleo | Disco de radio 0,35 cm: es la pupila | `ojo` (emite mucha luz) |
| Aro interior | Aro de 2,45 a 2,65 cm de radio | `negro` |

### Aro de cobre (`anillo{S}`, hijo del ojo)

- **Aro:** de 2,68 a 3,25 cm de radio.
- **Ranuras:** 24, de material `negroMate`, en círculo a 2,97 cm del centro.

### Diafragma (`diafragma{S}`, hijo del ojo)

- **Base:** un aro de 2,25 a 2,55 cm de radio.
- **Láminas** (`hoja{S}00` a `hoja{S}17`, hijas del diafragma): 18 láminas, cada una con su origen en su pivote.
  - **Pivotes:** en círculo a 2,35 cm del centro.
  - **Contorno:** un arco con centro en (1,2 cm, −1,7 cm) del pivote y 2,1 cm de radio, que va de 200° a 130°.
  - **Ancho:** 9,5 mm en la raíz y 3 mm en la punta.
  - **Grueso:** 0,5 mm.
  - **Filo interior:** un hilo de material `nucleo` que brilla.
  - **Remache:** cada lámina lleva uno en su pivote.
  - **Solape:** todas van a la misma altura, pero cada lámina está **inclinada a lo ancho**. El filo de dentro
    (el del hilo cian) queda 3 mm más adelante que el de fuera (`LAMINA_SUBE`, función `inclinarLamina`). Así cada
    filo queda encima de la lámina vecina por igual en todo el círculo.
  - **No apilarlas una delante de otra:** si cada lámina va un poco más adelante que la anterior, la última queda
    encima de la primera y sobresale, rompiendo la espiral.
  - **Variante globo:** cada vértice se adelanta `DIAFRAGMA_PUNTA · (1 − r / r_pivote)`, con 9 mm en el centro,
    de modo que entre todas forman un cono.

### Párpados blindados (`parpadoSup{S}` y `parpadoInf{S}`, hijos de la cabeza; solo en el ojo plano)

- **Forma:** un segmento del círculo de 3,52 cm de radio que tapa 1,4 cm, de material `gris`.
- **Detalles:** un canto recto `negro`, un nervio de `acero` y 2 tornillos.
- **Pivote:** en el centro del canto.

### Globo (`globo{S}`, hijo de la cabeza; solo en la variante globo)

- **Bola:** esfera UV de 96 × 48 segmentos y 3,35 cm de radio, con el centro 1 cm detrás de la cara del robot.
  Material `articulacion`.
- **Corte:** la bola se corta con un plano a 2,11 cm del centro; una tapa `negroMate` cierra el corte.
- **Interior:** el ojo, el aro de cobre y el diafragma, a escala `e · 0,8`, con el fondo del iris justo en el corte.

### Párpados de persiana (`persianaSup{S}{k}` y `persianaInf{S}{k}`, con k de 0 a 3, hijos de la cabeza)

- **Láminas:** 4 por párpado, de material `gris`, de 0,7 mm de grueso, cada una con un canto `negro`.
- **Contorno:** recortado a la vez con dos círculos, el del agujero del ojo (3,38 cm) y el de la pared del tubo.
  Así ninguna lámina asoma por fuera.
- **En reposo (abierto):** las 4 están apiladas contra el borde y solo se ve la primera.
- **Cerrado:** la lámina k se desplaza `k · PERSIANA_PASO` (3,38 / 4 cm) hacia el centro. Entre las 4 tapan el ojo
  entero y se juntan en el centro.

## 4. Materiales (Principled BSDF)

| Nombre | Color base (lineal) | Rugosidad | Metálico | Emisión |
|---|---|---|---|---|
| `robotNegro` | 0,012 · 0,012 · 0,014 | 0,42 | 0,05 | — |
| `robotNegroMate` | 0,04 · 0,04 · 0,045 | 0,7 | 0 | — |
| `robotArticulacion` | 0,05 · 0,052 · 0,056 | 0,3 | 0,6 | — |
| `robotGris` | 0,35 · 0,36 · 0,38 | 0,4 | 0,3 | — |
| `robotVisor` | 0,008 · 0,01 · 0,012 | 0,06 | 0,4 | — |
| `robotAcero` | 0,6 · 0,61 · 0,63 | 0,3 | 1 | — |
| `robotCobre` | 0,72 · 0,4 · 0,2 | 0,32 | 1 | — |
| `robotHoja` | 0,05 · 0,06 · 0,07 | 0,35 | 0,7 | — |
| `robotIris` | 0,05 · 0,45 · 1 | 0,2 | 0 | 2,5 (mismo color) |
| `robotNucleo` | 0,1 · 0,75 · 1 | 0,2 | 0 | 5 (mismo color) |
| `robotOjo` | 0,25 · 0,8 · 1 | 0,2 | 0 | 12 (mismo color) |

## 5. Cómo se anima

El juego mueve las piezas por su nombre; esto es lo que hace con cada una. Sirve para que las piezas queden con el
pivote donde hace falta.

| Pieza | Movimiento |
|---|---|
| `ojo{S}` o `globo{S}` | Gira en Z (lado) y en Y (arriba y abajo) hacia lo que mira. Hasta 35° a los lados y 25° arriba y abajo, casi de un salto. |
| `anillo{S}` | Gira sin parar sobre X a 1,2 rad/s, y más rápido mientras enfoca. |
| `diafragma{S}` | Gira despacio sobre X en sentido contrario (−0,15 del giro del aro). |
| `hoja{S}NN` | Gira sobre X en su pivote para abrir o cerrar la pupila: 0,75 rad de cerrada a abierta. |
| `parpadoSup` / `parpadoInf` | Bajan o suben en Z (parpadeo: cierran 2,1 cm durante 0,13 s) y se inclinan para la cara de «tenso». |
| `persiana…{k}` | Bajan o suben en Z: `k · PERSIANA_PASO · e`, por la fracción cerrada. |

| Expresión | Apertura de la pupila (0 a 1) | Párpados |
|---|---|---|
| Normal | 0,6 | En reposo |
| Enfoque | 0,22 | Bajan 7 y 6 mm |
| Alerta | 0,95 | Suben 12 y 10 mm |
| Tenso | 0,4 | Bajan 5 y 2 mm y se inclinan 0,28 rad |

## 6. El script completo (`ojo_robot.py`)

Genera los dos ojos uno al lado del otro: a la izquierda el plano y a la derecha el globo. Para meterlo en un robot,
llama a `ojoPlano(...)` o a `ojoGlobo(...)` con la X de la cara, el centro del ojo, la escala, el lado (`'Izq'` o
`'Der'`) y el objeto de la cabeza.

```python
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# Medidas en metros a escala 1; cada robot pasa su escala `e`.
OJO_SALIENTE = 0.02   # lo que sobresale la carcasa de la cara
OJO_RADIO = 0.044     # radio exterior de la carcasa
OJO_HOJAS = 18        # láminas del diafragma
OJO_PIVOTE = 0.0235   # radio del círculo de pivotes de las láminas
PARPADO_CUBRE = 0.014 # lo que tapa cada párpado blindado en reposo
# Variante globo (soldado y robot grande)
GLOBO_R = 0.0335
GLOBO_IRIS = 0.8
GLOBO_ATRAS = 0.01
DIAFRAGMA_PUNTA = 0.009
GLOBO_CORTE = 0.0211
# Párpados de persiana (soldado y robot grande)
PERSIANA_LAMINAS = 4
PERSIANA_TUBO = 0.007
PERSIANA_R = 0.0338
PERSIANA_PASO = PERSIANA_R / PERSIANA_LAMINAS


def nodoPrincipled(material):
    return next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def materialLiso(nombre, color, rugosidad, metalico=0.0, emision=0.0):
    material = bpy.data.materials.new(nombre)
    material.use_nodes = True
    bsdf = nodoPrincipled(material)
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rugosidad
    bsdf.inputs['Metallic'].default_value = metalico
    if emision > 0:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emision
    return material


def suave(objeto):
    """Sombreado suave con bordes vivos por ángulo (30°)."""
    for cara in objeto.data.polygons:
        cara.use_smooth = True
    try:
        objeto.data.set_sharp_from_angle(angle=math.radians(30))
    except AttributeError:
        objeto.data.use_auto_smooth = True
        objeto.data.auto_smooth_angle = math.radians(30)


def objetoDe(nombre, bm, material):
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    objeto = bpy.data.objects.new(nombre, malla)
    objeto.data.materials.append(material)
    bpy.context.scene.collection.objects.link(objeto)
    suave(objeto)
    return objeto


def caja(nombre, centro, tamano, material, bisel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tamano), verts=bm.verts)
    if bisel > 0:
        bisel = min(bisel, min(tamano) * 0.45)
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bisel, segments=3, affect='EDGES', profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def cilindro(nombre, centro, radio, largo, material, eje='z', lados=32, bisel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=lados, radius1=radio, radius2=radio, depth=largo)
    if bisel > 0:
        bordes = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6 and len(e.link_faces) == 2]
        bmesh.ops.bevel(bm, geom=bordes, offset=min(bisel, largo * 0.4, radio * 0.4), segments=2, affect='EDGES', profile=0.5)
    if eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def segmento(nombre, a, b, ancho, fondo, material, bisel=0.0, extra=0.0):
    """Caja de `a` a `b` con sección `fondo` x `ancho` (el ancho va en y),
    alargada `extra` por cada punta."""
    a, b = Vector(a), Vector(b)
    eje = b - a
    largo = eje.length + 2 * extra
    objeto = caja(nombre, (0, 0, 0), (fondo, ancho, largo), material, bisel)
    giro = eje.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    objeto.data.transform(Matrix.Translation((a + b) / 2) @ giro)
    return objeto


def unir(objetos, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for objeto in objetos:
        objeto.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    bpy.ops.object.join()
    objetos[0].name = nombre
    objetos[0].data.name = nombre
    return objetos[0]


def pieza(nombre, piezas, pivote, padre=None):
    """Une `piezas` en un objeto con el origen en `pivote` (mundo) y lo
    cuelga de `padre` sin moverlo."""
    objeto = unir(piezas, nombre)
    pivote = Vector(pivote)
    objeto.data.transform(Matrix.Translation(-pivote))
    objeto.location = pivote
    if padre:
        objeto.parent = padre
        objeto.matrix_parent_inverse = padre.matrix_world.inverted()
    return objeto


def perfilExtruido(nombre, puntos, grosor, material, bisel=0.008, z=0.0):
    """Placa con el contorno `puntos` (x, y) y `grosor` en z, centrada en z,
    con los cantos biselados (2 segmentos)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z - grosor / 2)) for x, y in puntos]
    cara = bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=[cara])
    if cara.normal.z > 0:
        cara.normal_flip()
    salida = bmesh.ops.extrude_face_region(bm, geom=[cara])
    nuevos = [e for e in salida['geom'] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, grosor)), verts=nuevos)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bisel > 0:
        bordes = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=bordes, offset=bisel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    return objetoDe(nombre, bm, material)


def aro(nombre, centro, rInt, rExt, grosor, material, lados=128, eje='x', bisel=0.0):
    """Aro plano (corona) con su agujero, de `grosor` a lo largo de `eje`."""
    bm = bmesh.new()
    frente, atras = [], []
    for r in (rExt, rInt):
        anillo = []
        for z in (grosor / 2, -grosor / 2):
            anillo.append([bm.verts.new((r * math.cos(2 * math.pi * k / lados), r * math.sin(2 * math.pi * k / lados), z)) for k in range(lados)])
        (frente if r == rExt else atras).append(anillo)
    (ef, et), (inf, intr) = frente[0], atras[0]
    for k in range(lados):
        j = (k + 1) % lados
        bm.faces.new((ef[k], ef[j], inf[j], inf[k]))       # cara de delante
        bm.faces.new((et[j], et[k], intr[k], intr[j]))     # cara de atrás
        bm.faces.new((ef[j], ef[k], et[k], et[j]))         # canto de fuera
        bm.faces.new((inf[k], inf[j], intr[j], intr[k]))   # canto de dentro
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bisel > 0:
        bordes = [e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.dot(e.link_faces[1].normal)) < 0.5]
        bmesh.ops.bevel(bm, geom=bordes, offset=bisel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    if eje == 'x':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif eje == 'y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    return objetoDe(nombre, bm, material)


def enDisco(objeto, centro, angulo, radio):
    """Lleva una malla hecha en el origen (mirando a +x) a `radio` del centro
    de un disco que mira a +x, a `angulo` (en el plano y-z), girada con él."""
    c = Vector(centro)
    pos = c + Vector((0, math.cos(angulo) * radio, math.sin(angulo) * radio))
    objeto.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(angulo, 4, 'X'))
    return objeto


def contornoHoja(e):
    """Lámina del diafragma con el pivote en el origen: un arco que sale
    hacia el centro del ojo y se curva (ancha en la raíz, fina en la punta).
    Coordenadas del plano del ojo; el centro del ojo queda hacia -x."""
    pts_fuera, pts_dentro = [], []
    n = 14
    for k in range(n + 1):
        f = k / n
        a = math.radians(200) - f * math.radians(70)  # sale hacia el centro y se curva
        r = 0.021 * e
        cx, cy = 0.012 * e, -0.017 * e
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        # Normal hacia fuera del arco.
        nx, ny = math.cos(a), math.sin(a)
        ancho = (0.0095 - 0.0065 * f) * e
        pts_fuera.append((x + nx * ancho / 2, y + ny * ancho / 2))
        pts_dentro.append((x - nx * ancho / 2, y - ny * ancho / 2))
    return pts_fuera + pts_dentro[::-1]


# Las láminas se montan como en un diafragma de verdad (el dueño, 18-nov: una
# sobresalía): en vez de apilarlas una delante de otra (la última quedaba
# encima de la primera y rompía la espiral), cada una va inclinada a lo
# ancho: el filo de dentro (el del hilo cian) LAMINA_SUBE más adelante que el
# de fuera. Así cada filo queda encima de la lámina vecina, igual en todo el
# círculo y sin costura.
LAMINA_SUBE = 0.003


def inclinarLamina(objeto, e):
    """Sube cada vértice de una lámina (en su plano, antes de `enOjo`) según
    lo cerca que está de su filo de dentro (el arco de contornoHoja: centro
    (0,012, -0,017) y radio 0,021, por `e`; la lámina mide hasta ~1 cm de
    ancho)."""
    cx, cy, r, medio = 0.012 * e, -0.017 * e, 0.021 * e, 0.005 * e
    for v in objeto.data.vertices:
        dc = math.hypot(v.co.x - cx, v.co.y - cy)
        v.co.z += LAMINA_SUBE * e * min(1.0, max(0.0, (r + medio - dc) / (2 * medio)))
    objeto.data.update()


def enOjo(objeto, cx, y, zc, angulo):
    """Lleva una malla hecha en el plano x-y (grosor en z) al plano del ojo
    (normal +x), girada `angulo` alrededor del eje del ojo y centrada en
    (cx, y, zc)."""
    plano = Matrix.Rotation(math.pi / 2, 4, 'Y')  # z -> x
    objeto.data.transform(Matrix.Translation((cx, y, zc)) @ Matrix.Rotation(angulo, 4, 'X') @ plano)
    return objeto


def ojoCuenca(m, xf, y, zc, e, lado):
    """Lo fijo de un ojo (va en la cabeza): carcasa saliente, bisel dentado,
    tornillos y el fondo oscuro."""
    xCara = xf
    xf = xf + OJO_SALIENTE * e
    R = OJO_RADIO * e
    p = [
        # Carcasa: tubo corto (el ojo va dentro, se ve por el agujero).
        aro('carcasa', ((xCara + xf) / 2, y, zc), 0.034 * e, R, xf - xCara + 0.002 * e, m['negro'], bisel=0.0015 * e),
        aro('bisel', (xf + 0.001 * e, y, zc), 0.035 * e, R - 0.001 * e, 0.004 * e, m['acero'], bisel=0.0006 * e),
        aro('fondoBisel', (xf + 0.0035 * e, y, zc), 0.0335 * e, 0.0355 * e, 0.002 * e, m['negro']),
        cilindro('fondo', (xf - 0.009 * e, y, zc), 0.034 * e, 0.003 * e, m['visor'], eje='x', lados=128),
    ]
    # Bisel dentado: 48 dientes en el canto de fuera.
    for k in range(48):
        a = k * 2 * math.pi / 48
        diente = caja('dienteBisel', (0, 0, 0), (0.003 * e, 0.0028 * e, 0.0028 * e), m['acero'], 0.0004 * e)
        diente.data.transform(Matrix.Rotation(math.pi / 4, 4, 'X'))
        p.append(enDisco(diente, (xf + 0.0035 * e, y, zc), a, 0.0405 * e))
    # Tornillos de la carcasa.
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        tornillo = cilindro('tornilloOjo', (0, 0, 0), 0.0018 * e, 0.0025 * e, m['acero'], eje='x', lados=6)
        p.append(enDisco(tornillo, (xf + 0.0035 * e, y, zc), a, 0.0365 * e))
    return p


def ojoPiezas(m, xf, y, zc, e, s, cabeza):
    """Lo que se mueve de un ojo (ver arriba). Devuelve el globo."""
    xf = xf + OJO_SALIENTE * e
    cx = xf - 0.006 * e
    p = [
        cilindro('fondoIris', (cx - 0.002 * e, y, zc), 0.025 * e, 0.002 * e, m['articulacion'], eje='x', lados=128),
        aro('halo', (cx - 0.0005 * e, y, zc), 0.006 * e, 0.0125 * e, 0.001 * e, m['iris'], lados=96),
        cilindro('nucleo', (cx, y, zc), 0.0075 * e, 0.0025 * e, m['nucleo'], eje='x', lados=96),
        cilindro('centroNucleo', (cx + 0.0013 * e, y, zc), 0.0035 * e, 0.001 * e, m['ojo'], eje='x', lados=64),
        aro('aroInterior', (cx + 0.001 * e, y, zc), 0.0245 * e, 0.0265 * e, 0.002 * e, m['negro'], lados=128),
    ]
    ojo = pieza('ojo' + s, p, (cx, y, zc), cabeza)
    # Aro de cobre con 24 ranuras oscuras (gira).
    q = [aro('aroCobre', (cx + 0.002 * e, y, zc), 0.0268 * e, 0.0325 * e, 0.0022 * e, m['cobre'], lados=128, bisel=0.0003 * e)]
    for k in range(24):
        a = k * 2 * math.pi / 24
        ranura = caja('ranura', (0, 0, 0), (0.0006 * e, 0.0022 * e, 0.0018 * e), m['negroMate'])
        q.append(enDisco(ranura, (cx + 0.0033 * e, y, zc), a, 0.0297 * e))
    pieza('anillo' + s, q, (cx, y, zc), ojo)
    # Diafragma: 18 láminas, cada una gira sobre su pivote.
    diafragma = pieza('diafragma' + s, [aro('baseDiafragma', (cx + 0.0005 * e, y, zc), 0.0225 * e, 0.0255 * e, 0.0012 * e, m['articulacion'], lados=128)], (cx, y, zc), ojo)
    contorno = contornoHoja(e)
    for k in range(OJO_HOJAS):
        a = k * 2 * math.pi / OJO_HOJAS
        # Todas a la misma altura: el solape lo da su inclinación.
        xk = cx + 0.0012 * e
        hoja = perfilExtruido('hoja', contorno, 0.0005 * e, m['hoja'], 0.00012 * e)
        borde = perfilExtruido('bordeHoja', contorno[:15], 0.0002 * e, m['nucleo'], 0.0)  if False else None
        piezas = [hoja]
        # Borde cian: un hilo que brilla a lo largo del filo de dentro.
        filo = contorno[15:]
        for i in range(len(filo) - 1):
            (x0, y0), (x1, y1) = filo[i], filo[i + 1]
            hilo = segmento('filo', (x0, y0, 0.0004 * e), (x1, y1, 0.0004 * e), 0.0006 * e, 0.0004 * e, m['nucleo'])
            piezas.append(hilo)
        # El pivote: un remache diminuto.
        piezas.append(cilindro('pivoteHoja', (0, 0, 0.0004 * e), 0.0009 * e, 0.0008 * e, m['acero'], lados=12))
        for o in piezas:
            inclinarLamina(o, e)
        # Del plano de la lámina al del ojo: el pivote en su sitio del aro
        # (radio OJO_PIVOTE, ángulo a) y la lámina mirando hacia el centro.
        py, pz = math.cos(a) * OJO_PIVOTE * e, math.sin(a) * OJO_PIVOTE * e
        for o in piezas:
            enOjo(o, xk, y + py, zc + pz, a)
        pieza('hoja%s%02d' % (s, k), piezas, (xk, y + py, zc + pz), diafragma)
    # Párpados blindados: un segmento del círculo del ojo (canto en recta,
    # lomo en arco) de acero gris con un nervio y dos tornillos. El juego los
    # baja y sube en z (expresiones y parpadeo) y los inclina (tenso).
    r = 0.0352 * e
    h = PARPADO_CUBRE * e
    for nombre, signo in (('parpadoSup', 1), ('parpadoInf', -1)):
        a0 = math.asin((r - h) / r)
        puntos = []
        for k in range(33):
            a = a0 + (math.pi - 2 * a0) * k / 32
            puntos.append((math.cos(a) * r, signo * math.sin(a) * r))
        if signo < 0:
            puntos.reverse()
        placa = perfilExtruido('parpado', puntos, 0.0025 * e, m['gris'], 0.0005 * e)
        zCanto = signo * (r - h)
        canto = segmento('cantoParpado', (-math.cos(a0) * r, zCanto, 0.0012 * e), (math.cos(a0) * r, zCanto, 0.0012 * e), 0.0016 * e, 0.0016 * e, m['negro'], 0.0004 * e)
        nervio = segmento('nervioParpado', (-0.016 * e, zCanto + signo * 0.005 * e, 0.0016 * e), (0.016 * e, zCanto + signo * 0.005 * e, 0.0016 * e), 0.0012 * e, 0.0012 * e, m['acero'], 0.0003 * e)
        piezas = [placa, canto, nervio]
        for sy in (-1, 1):
            piezas.append(cilindro('tornilloParpado', (sy * 0.022 * e, zCanto + signo * 0.0085 * e, 0.0015 * e), 0.0015 * e, 0.0012 * e, m['acero'], lados=6))
        # Del plano (x a lo ancho, y arriba) al del ojo: x -> y, y -> z, z -> x.
        giro = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        for o in piezas:
            o.data.transform(Matrix.Translation((xf + 0.0045 * e, y, zc)) @ giro)
        pieza(nombre + s, piezas, (xf + 0.0045 * e, y, zc + zCanto), cabeza)
    return ojo


def cuencaPersiana(m, xf, y, zo, e):
    """La cuenca del robot pequeño con el tubo alargado: el bisel, sus
    dientes y tornillos van PERSIANA_TUBO más adelante y en medio queda el
    hueco de las láminas."""
    ext = PERSIANA_TUBO * e
    p = ojoCuenca(m, xf, y, zo, e, 1)
    for o in p:
        if o.name.startswith(('bisel', 'fondoBisel', 'dienteBisel', 'tornilloOjo')):
            o.data.transform(Matrix.Translation((ext, 0, 0)))
    xFrente = xf + OJO_SALIENTE * e
    p.append(aro('tuboPersiana', (xFrente + ext / 2, y, zo), 0.034 * e, OJO_RADIO * e, ext + 0.002 * e, m['negro']))
    return p


def persianas(m, xf, y, zo, e, s, cabeza):
    R = PERSIANA_R * e
    h = PERSIANA_PASO * e
    Rtubo = (OJO_RADIO - 0.0012) * e  # lo que tapa la pared del tubo
    xFrente = xf + (OJO_SALIENTE + PERSIANA_TUBO - 0.0012) * e
    giro = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # x->y, y->z, z->x
    for nombre, signo, extra in (('persianaSup', 1, 0.0), ('persianaInf', -1, 0.00055)):
        for k in range(PERSIANA_LAMINAS):
            # Franja que tapa cerrada (desde el borde hacia el centro, con
            # un poco de solape); de pie se apila k pasos hacia el borde.
            z1 = R - k * h
            z0 = max(-0.0006 * e, R - (k + 1.3) * h)
            sube = k * h
            borde = []
            n = 16
            for i in range(n + 1):
                z = z0 + (z1 - z0) * i / n
                # Dentro del agujero cerrada y dentro de la pared del tubo apilada.
                a = R * R - z * z
                b = Rtubo * Rtubo - (z + sube) ** 2
                xl = math.sqrt(max(0.0, min(a, b)))
                borde.append((xl, z))
            puntos = [(x, z) for x, z in borde] + [(-x, z) for x, z in reversed(borde)]
            puntos = [(x, signo * z) for x, z in puntos]
            if signo < 0:
                puntos.reverse()
            # Quita puntos repetidos (las puntas de ancho 0).
            limpios = []
            for pt in puntos:
                if not limpios or (abs(pt[0] - limpios[-1][0]) > 1e-7 or abs(pt[1] - limpios[-1][1]) > 1e-7):
                    limpios.append(pt)
            lamina = perfilExtruido('lamina', limpios, 0.0007 * e, m['gris'], 0.00015 * e)
            zCanto = signo * z0
            xCanto = math.sqrt(max(0.0, min(R * R - z0 * z0, Rtubo * Rtubo - (z0 + sube) ** 2)))
            canto = segmento('cantoLamina', (-xCanto * 0.96, zCanto + signo * 0.0006 * e, 0.0006 * e), (xCanto * 0.96, zCanto + signo * 0.0006 * e, 0.0006 * e), 0.0009 * e, 0.0005 * e, m['negro'])
            x = xFrente - (k * 0.0011 + extra) * e
            for o in (lamina, canto):
                o.data.transform(Matrix.Translation((x, y, zo + signo * sube)) @ giro)
            pieza('%s%s%d' % (nombre, s, k), [lamina, canto], (x, y, zo + signo * sube), cabeza)


def globoOjo(m, xf, y, zo, s, cabeza, e):
    ei = e * GLOBO_IRIS
    xc = xf - GLOBO_ATRAS * e
    xCorte = xc + GLOBO_CORTE * e
    rCorte = 0.0325 * ei
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=GLOBO_R * e)
    bmesh.ops.translate(bm, vec=Vector((xc, y, zo)), verts=bm.verts)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(xCorte, y, zo), plane_no=(1, 0, 0), clear_outer=True)
    bola = objetoDe('globo', bm, m['articulacion'])
    tapa = cilindro('tapaGlobo', (xCorte - 0.0006 * e, y, zo), rCorte, 0.0012 * e, m['negroMate'], eje='x', lados=96)
    globo = pieza('globo' + s, [bola, tapa], (xc, y, zo), cabeza)
    # ojoPiezas pone el fondo del iris en xf2 + 0,012·ei: justo en el corte.
    ojoPiezas(m, xCorte - 0.012 * ei, y, zo, ei, s, globo)
    # Diafragma en punta (el dueño, 17-nov): cada lámina se levanta hacia
    # delante según se acerca al centro; entre todas forman un cono.
    rPivote = OJO_PIVOTE * ei
    alto = DIAFRAGMA_PUNTA * e
    for k in range(OJO_HOJAS):
        o = bpy.data.objects['hoja%s%02d' % (s, k)]
        mw = o.matrix_world.copy()
        inv = mw.inverted()
        for v in o.data.vertices:
            w = mw @ v.co
            r = math.hypot(w.y - y, w.z - zo)
            w.x += alto * max(0.0, 1.0 - r / rPivote)
            v.co = inv @ w
        o.data.update()
    return globo


def materialesOjo():
    return {
        'negro': materialLiso('robotNegro', (0.012, 0.012, 0.014), 0.42, 0.05),
        'negroMate': materialLiso('robotNegroMate', (0.04, 0.04, 0.045), 0.7),
        'articulacion': materialLiso('robotArticulacion', (0.05, 0.052, 0.056), 0.3, 0.6),
        'gris': materialLiso('robotGris', (0.35, 0.36, 0.38), 0.4, 0.3),
        'visor': materialLiso('robotVisor', (0.008, 0.01, 0.012), 0.06, 0.4),
        'ojo': materialLiso('robotOjo', (0.25, 0.8, 1.0), 0.2, 0.0, 12.0),
        'iris': materialLiso('robotIris', (0.05, 0.45, 1.0), 0.2, 0.0, 2.5),
        'acero': materialLiso('robotAcero', (0.6, 0.61, 0.63), 0.3, 1.0),
        'nucleo': materialLiso('robotNucleo', (0.1, 0.75, 1.0), 0.2, 0.0, 5.0),
        'cobre': materialLiso('robotCobre', (0.72, 0.4, 0.2), 0.32, 1.0),
        'hoja': materialLiso('robotHoja', (0.05, 0.06, 0.07), 0.35, 0.7),
    }


def ojoPlano(xf, y, zc, e, s, cabeza, m):
    """Ojo del robot pequeño: cuenca fija (unida a la cabeza) + ojo móvil
    con párpados blindados. `xf` = x de la cara, (y, zc) = centro del ojo."""
    cuenca = ojoCuenca(m, xf, y, zc, e, 1)
    pieza('cuenca' + s, cuenca, (xf, y, zc), cabeza)
    return ojoPiezas(m, xf, y, zc, e, s, cabeza)


def ojoGlobo(xf, y, zc, e, s, cabeza, m):
    """Ojo del soldado / robot grande: cuenca con tubo + globo con el
    diafragma en punta + párpados de persiana."""
    cuenca = cuencaPersiana(m, xf, y, zc, e)
    pieza('cuenca' + s, cuenca, (xf, y, zc), cabeza)
    globo = globoOjo(m, xf, y, zc, s, cabeza, e)
    persianas(m, xf, y, zc, e, s, cabeza)
    return globo


if __name__ == '__main__':
    # Ejemplo: una cabeza vacía con los dos tipos de ojo, uno al lado del otro.
    m = materialesOjo()
    cabeza = bpy.data.objects.new('cabeza', None)
    bpy.context.scene.collection.objects.link(cabeza)
    ojoPlano(0.0, 0.06, 0.0, 1.0, 'Izq', cabeza, m)
    ojoGlobo(0.0, -0.06, 0.0, 1.0, 'Der', cabeza, m)
```

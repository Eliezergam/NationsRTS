# El avión de transporte para el mapa 2D (diseno/aviones-de-transporte.md,
# paso 2): el modelo 3D del juego (assets/batalla/robots/avionCarga_lod2.glb)
# visto con el ángulo de la vista isométrica del mapa (mundo/iso.lua: 2:1,
# elevación 30°, a 45°), en 16 rumbos, y una hoja con los 16.
#
#     blender -b --factory-startup --python tools/blender/avion_mapa.py
#
# Deja assets/mapa/avion/avion.png (4 x 4 cuadros de TAM px, el rumbo k en
# la fila k // 4 y la columna k % 4) y assets/mapa/avion/indice.lua. El rumbo
# k es el ángulo k * 22,5° en el plano del mapa (x a la derecha y abajo en la
# vista, y a la izquierda y abajo), como math.atan2(dy, dx).

import math
import os
import sys

import bpy
import mathutils

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MODELO = os.path.join(RAIZ, 'assets', 'batalla', 'robots', 'avionCarga_lod2.glb')
DESTINO = os.path.join(RAIZ, 'assets', 'mapa', 'avion')
TAM = 256  # px por cuadro
RUMBOS = 16
TEMPORAL = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'avion_mapa')


def preparar():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=MODELO)
    # Todo el avión colgado de un vacío en su centro, para girarlo.
    piezas = [o for o in bpy.context.scene.objects if o.parent is None]
    mn = mathutils.Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            for v in o.bound_box:
                w = o.matrix_world @ mathutils.Vector(v)
                mn = mathutils.Vector(map(min, mn, w))
                mx = mathutils.Vector(map(max, mx, w))
    centro = (mn + mx) / 2
    eje = bpy.data.objects.new('eje', None)
    bpy.context.scene.collection.objects.link(eje)
    eje.location = (centro.x, centro.y, 0)
    for o in piezas:
        o.parent = eje
        o.matrix_parent_inverse = eje.matrix_world.inverted()
    eje.location = (0, 0, 0)
    radio = max(mx.x - mn.x, mx.y - mn.y) / 2
    return eje, radio, mx.z - mn.z


def camara(radio, alto):
    escena = bpy.context.scene
    datos = bpy.data.cameras.new('cam')
    datos.type = 'ORTHO'
    # El avión cabe girado entero (su radio) con un poco de margen.
    datos.ortho_scale = radio * 2.15
    cam = bpy.data.objects.new('cam', datos)
    escena.collection.objects.link(cam)
    # Mira desde el lado (+x, +y del mapa) = (+X, -Y de Blender), 30° arriba.
    elev = math.radians(30)
    d = 200
    h = d * math.cos(elev)
    cam.location = (h / math.sqrt(2), -h / math.sqrt(2), d * math.sin(elev) + alto / 2)
    direccion = mathutils.Vector((0, 0, alto / 2)) - cam.location
    cam.rotation_euler = direccion.to_track_quat('-Z', 'Y').to_euler()
    escena.camera = cam


def luz():
    sol = bpy.data.lights.new('sol', 'SUN')
    sol.energy = 4.0
    sol.angle = math.radians(8)
    o = bpy.data.objects.new('sol', sol)
    bpy.context.scene.collection.objects.link(o)
    # La luz del mapa viene de arriba a la izquierda de la pantalla.
    o.rotation_euler = (math.radians(40), 0, math.radians(-120))
    mundo = bpy.data.worlds.new('cielo')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs[0].default_value = (0.55, 0.6, 0.68, 1)
    fondo.inputs[1].default_value = 0.6
    bpy.context.scene.world = mundo


def render():
    escena = bpy.context.scene
    motores = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    escena.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in motores else 'BLENDER_EEVEE'
    escena.render.resolution_x = TAM
    escena.render.resolution_y = TAM
    escena.render.film_transparent = True
    escena.render.image_settings.file_format = 'PNG'
    escena.render.image_settings.color_mode = 'RGBA'
    escena.view_settings.view_transform = 'Standard'


def main():
    eje, radio, alto = preparar()
    camara(radio, alto)
    luz()
    render()
    os.makedirs(TEMPORAL, exist_ok=True)
    os.makedirs(DESTINO, exist_ok=True)
    rutas = []
    for k in range(RUMBOS):
        rumbo = k * 2 * math.pi / RUMBOS
        # El morro del modelo mira a +X de Blender; el mapa tiene la y al revés.
        eje.rotation_euler = (0, 0, -rumbo)
        ruta = os.path.join(TEMPORAL, 'avion_%02d.png' % k)
        bpy.context.scene.render.filepath = ruta
        bpy.ops.render.render(write_still=True)
        rutas.append(ruta)
    # La hoja: 4 x 4.
    hoja = bpy.data.images.new('hoja', TAM * 4, TAM * 4, alpha=True)
    pix = [0.0] * (TAM * 4 * TAM * 4 * 4)
    for k, ruta in enumerate(rutas):
        img = bpy.data.images.load(ruta)
        datos = list(img.pixels)
        col, fila = k % 4, k // 4
        for y in range(TAM):
            # Blender guarda las filas de abajo arriba.
            yh = (3 - fila) * TAM + y
            inicio = (yh * TAM * 4 + col * TAM) * 4
            pix[inicio:inicio + TAM * 4] = datos[y * TAM * 4:(y + 1) * TAM * 4]
    hoja.pixels = pix
    hoja.filepath_raw = os.path.join(DESTINO, 'avion.png')
    hoja.file_format = 'PNG'
    hoja.save()
    with open(os.path.join(DESTINO, 'indice.lua'), 'w') as f:
        f.write('-- Generado por tools/blender/avion_mapa.py: no editar a mano.\n')
        f.write('return {\n')
        f.write("    hoja = 'assets/mapa/avion/avion.png',\n")
        f.write('    cuadro = %d, -- px por cuadro\n' % TAM)
        f.write('    rumbos = %d, -- el k-ésimo, en la fila k // 4 y la columna k %% 4\n' % RUMBOS)
        f.write('    metros = %.2f, -- lo que mide de ancho un cuadro, en metros\n' % (radio * 2.15))
        f.write('}\n')
    print('AVION MAPA listo', DESTINO)


main()

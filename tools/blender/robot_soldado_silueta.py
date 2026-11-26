# Maqueta de silueta del robot soldado (el dueño, 2026-11-17): torso humano
# con brazos y cabeza sobre dos piernas, y una rueda en el pie de cada
# pierna. Corre como quien va en patinete: los pies casi juntos, uno al
# lado del otro, las rodillas dobladas y el cuerpo echado hacia delante.
#
# Solo volúmenes (cajas y cilindros) para aprobar proporciones antes del
# detalle (skill vehiculo-detallado: «silueta primero»). Sin ventana:
#
#     blender -b --factory-startup --python tools/blender/robot_soldado_silueta.py -- <carpeta>
#
# Saca en <carpeta> las vistas lateral, frontal y 3/4 de dos poses (de pie y
# patinando) junto a una persona de 1,80 m.
#
# Referencias de robots reales con rueda en el pie: Ascento (ETH Zúrich),
# DIABLO (arXiv 2407.21500), LimX TRON 1 (pie de rueda, 3 m/s) y el Unitree
# G1 con ruedas en lugar de pies.
#
# Metros, z arriba, frente hacia +x, el origen en el suelo entre las ruedas.

import math
import os
import sys

import bpy
from mathutils import Vector

RADIO_RUEDA = 0.15
ANCHO_RUEDA = 0.07
MUSLO = 0.44
ESPINILLA = 0.44
CADERA_Y = 0.10  # media separación de las caderas
RUEDA_Y = 0.165  # rueda por fuera de la espinilla: entre los pies quedan ~12 cm
TORSO = 0.56  # de la cadera a la base del cuello
HOMBRO_Y = 0.24
BRAZO = 0.3
ANTEBRAZO = 0.28

POSES = {
    # x de la cadera respecto a la rueda, altura de la cadera, inclinación
    # del torso (rad, hacia delante).
    'de_pie': {'caderaX': 0.0, 'caderaZ': RADIO_RUEDA + 0.84, 'torso': math.radians(6)},
    'patinando': {'caderaX': -0.1, 'caderaZ': RADIO_RUEDA + 0.6, 'torso': math.radians(38)},
}


def argumentos():
    resto = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return resto[0] if resto else '/tmp/robot_soldado'


def material(nombre, color):
    m = bpy.data.materials.new(nombre)
    m.diffuse_color = (*color, 1)
    return m


def colocar(objeto, mat):
    objeto.data.materials.append(mat)
    return objeto


def segmento(a, b, ancho, fondo, mat):
    """Caja de `a` a `b` (en el plano x-z o con y) de sección ancho × fondo."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
    o = bpy.context.object
    o.scale = (fondo, ancho, d.length)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return colocar(o, mat)


def caja(centro, tamano, mat, giroY=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centro, rotation=(0, giroY, 0))
    o = bpy.context.object
    o.scale = tamano
    return colocar(o, mat)


def cilindroY(centro, radio, ancho, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radio, depth=ancho, location=centro, rotation=(math.pi / 2, 0, 0))
    return colocar(bpy.context.object, mat)


def esfera(centro, radio, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radio, location=centro)
    return colocar(bpy.context.object, mat)


def rodilla(cadera, pie):
    """Rodilla hacia delante entre la cadera y el pie (x, z)."""
    cx, cz = cadera
    px, pz = pie
    d = math.hypot(cx - px, cz - pz)
    d = min(d, MUSLO + ESPINILLA - 1e-4)
    a = math.acos((MUSLO ** 2 + d ** 2 - ESPINILLA ** 2) / (2 * MUSLO * d))
    base = math.atan2(pz - cz, px - cx)
    angulo = base + a  # dobla la rodilla hacia +x
    return cx + math.cos(angulo) * MUSLO, cz + math.sin(angulo) * MUSLO


def robot(pose, desplazamientoY, m, arma='fusil'):
    p = POSES[pose]
    cx, cz = p['caderaX'], p['caderaZ']
    rx, rz = 0.0, RADIO_RUEDA
    kx, kz = rodilla((cx, cz), (rx, rz))
    for lado in (-1, 1):
        y = desplazamientoY + lado * CADERA_Y
        segmento((cx, y, cz), (kx, y, kz), 0.12, 0.15, m['chapa'])
        segmento((kx, y, kz), (rx, y, rz), 0.1, 0.12, m['chapa'])
        esfera((kx, y, kz), 0.07, m['junta'])
        # La rueda por fuera del pie, con su buje.
        cilindroY((rx, desplazamientoY + lado * RUEDA_Y, rz), RADIO_RUEDA, ANCHO_RUEDA, m['goma'])
        cilindroY((rx, desplazamientoY + lado * (RUEDA_Y + 0.001), rz), RADIO_RUEDA * 0.55, ANCHO_RUEDA + 0.004, m['junta'])
    # Pelvis.
    caja((cx, desplazamientoY, cz + 0.04), (0.2, 0.3, 0.14), m['chapa'], p['torso'] * 0.5)
    # Torso inclinado desde la cadera.
    t = p['torso']
    ux, uz = math.sin(t), math.cos(t)
    cuello = (cx + ux * TORSO, desplazamientoY, cz + uz * TORSO)
    segmento((cx + ux * 0.08, desplazamientoY, cz + uz * 0.08), (cx + ux * 0.25, desplazamientoY, cz + uz * 0.25), 0.22, 0.16, m['junta'])
    segmento((cx + ux * 0.22, desplazamientoY, cz + uz * 0.22), cuello, 0.44, 0.28, m['chapa'])
    # Cabeza: casco con visor, mirando al frente (no se inclina con el torso).
    hx, hz = cuello[0] + 0.03, cuello[2] + 0.13
    caja((hx, desplazamientoY, hz), (0.2, 0.17, 0.2), m['chapa'])
    caja((hx + 0.1, desplazamientoY, hz + 0.01), (0.02, 0.15, 0.05), m['visor'])
    # Brazos. El derecho (y < 0) es el arma: el antebrazo entero es el
    # cañón, sin gatillo ni cargador (el dueño, 17-nov). El izquierdo tiene
    # mano. `arma`: 'metralleta' (tres cañones cortos) o 'fusil' (uno largo).
    hombro = (cx + ux * (TORSO - 0.06), cz + uz * (TORSO - 0.06))
    for lado in (-1, 1):
        y = desplazamientoY + lado * HOMBRO_Y
        codo = (hombro[0] + 0.1, y + lado * 0.02, hombro[1] - 0.27)
        esfera((hombro[0], y, hombro[1]), 0.08, m['junta'])
        segmento((hombro[0], y, hombro[1]), codo, 0.09, 0.1, m['chapa'])
        esfera(codo, 0.06, m['junta'])
        if lado < 0:
            # Antebrazo arma: carcasa gruesa hacia delante y los cañones.
            cuerpo = (codo[0] + 0.42, codo[1], codo[2] + 0.02)
            segmento(codo, cuerpo, 0.12, 0.13, m['chapa'])
            if arma == 'metralleta':
                for k in range(3):
                    a = k * 2 * math.pi / 3
                    dy, dz = math.cos(a) * 0.03, math.sin(a) * 0.03
                    segmento((cuerpo[0], cuerpo[1] + dy, cuerpo[2] + dz), (cuerpo[0] + 0.28, cuerpo[1] + dy, cuerpo[2] + dz), 0.025, 0.025, m['arma'])
            else:
                segmento(cuerpo, (cuerpo[0] + 0.55, cuerpo[1], cuerpo[2]), 0.035, 0.035, m['arma'])
                caja((cuerpo[0] + 0.5, cuerpo[1], cuerpo[2]), (0.08, 0.05, 0.05), m['arma'])
        else:
            mano = (codo[0] + 0.24, codo[1] - 0.06, codo[2] + 0.06)
            segmento(codo, mano, 0.07, 0.08, m['chapa'])
            caja((mano[0] + 0.05, mano[1], mano[2]), (0.1, 0.05, 0.09), m['junta'])


def persona(y, m):
    """Persona de 1,80 m, de referencia."""
    for lado in (-1, 1):
        segmento((0, y + lado * 0.1, 0), (0, y + lado * 0.1, 0.9), 0.13, 0.15, m['persona'])
    segmento((0, y, 0.9), (0, y, 1.52), 0.4, 0.24, m['persona'])
    esfera((0, y, 1.67), 0.12, m['persona'])


def camara(nombre, posicion, mira, orto=None):
    datos = bpy.data.cameras.new(nombre)
    if orto:
        datos.type = 'ORTHO'
        datos.ortho_scale = orto
    else:
        datos.lens = 50
    o = bpy.data.objects.new(nombre, datos)
    bpy.context.scene.collection.objects.link(o)
    o.location = posicion
    o.rotation_euler = (Vector(mira) - Vector(posicion)).to_track_quat('-Z', 'Y').to_euler()
    return o


def main():
    salida = argumentos()
    os.makedirs(salida, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = {
        'chapa': material('chapa', (0.42, 0.45, 0.38)),
        'junta': material('junta', (0.12, 0.12, 0.13)),
        'goma': material('goma', (0.05, 0.05, 0.05)),
        'visor': material('visor', (0.9, 0.35, 0.1)),
        'arma': material('arma', (0.08, 0.08, 0.09)),
        'persona': material('persona', (0.75, 0.75, 0.78)),
    }
    bpy.ops.mesh.primitive_plane_add(size=30)
    colocar(bpy.context.object, material('suelo', (0.6, 0.62, 0.6)))
    figuras = {}
    for nombre, hacer in (
        ('persona', lambda: persona(-1.0, m)),
        ('de_pie', lambda: robot('de_pie', 0.0, m, 'metralleta')),
        ('patinando', lambda: robot('patinando', 1.1, m, 'fusil')),
    ):
        antes = set(bpy.data.objects)
        hacer()
        figuras[nombre] = [o for o in bpy.data.objects if o not in antes]
    escena = bpy.context.scene
    escena.render.engine = 'BLENDER_WORKBENCH'
    escena.display.shading.light = 'STUDIO'
    escena.display.shading.color_type = 'MATERIAL'
    escena.display.shading.show_shadows = True
    escena.display.shading.show_cavity = True
    escena.render.resolution_x, escena.render.resolution_y = 1600, 1000
    escena.render.film_transparent = False
    world = bpy.data.worlds.new('mundo')
    escena.world = world
    world.color = (0.85, 0.87, 0.9)
    # De lado, cada figura sola (puestas en fila a lo ancho, se taparían).
    escena.render.resolution_x, escena.render.resolution_y = 800, 1000
    for nombre, objetos in figuras.items():
        y = {'persona': -1.0, 'de_pie': 0.0, 'patinando': 1.1}[nombre]
        for otro, lista in figuras.items():
            for o in lista:
                o.hide_render = otro != nombre
        escena.camera = camara('lateral_' + nombre, (0.15, y - 9, 1.0), (0.15, y, 1.0), orto=2.4)
        escena.render.filepath = os.path.join(salida, 'lateral_' + nombre + '.png')
        bpy.ops.render.render(write_still=True)
    for lista in figuras.values():
        for o in lista:
            o.hide_render = False
    escena.render.resolution_x, escena.render.resolution_y = 1600, 1000
    vistas = {
        'frontal': camara('frontal', (9, 0.05, 1.0), (0, 0.05, 1.0), orto=3.6),
        'tres_cuartos': camara('tres_cuartos', (4.2, -3.6, 2.2), (0, 0.1, 0.85)),
    }
    for nombre, cam in vistas.items():
        escena.camera = cam
        escena.render.filepath = os.path.join(salida, nombre + '.png')
        bpy.ops.render.render(write_still=True)
    print('SILUETA lista en', salida)


main()

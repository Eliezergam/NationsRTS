"""Torreta enemiga de práctica para el soldado (el dueño, 18-nov: «crea una
torreta y que esa torreta le dispare»). Tres piezas que se mueven aparte,
cada una con su pivote en el origen (el juego las coloca: almacen/robots/
tipos/torreta.lua y robots/especializaciones/torreta.lua):

    base     pedestal: placa octogonal atornillada al suelo, columna y collar
    cabezal  gira a los lados (z) sobre el collar, a 0,72 m: plato giratorio,
             horquilla de dos placas, caja de electrónica detrás y el sensor
             rojo encima
    canon    sube y baja (y) entre las placas, a 0,28 m del plato: muñones,
             cuerpo del arma, caja de munición, cañón con anillos de
             refrigeración y freno de boca (la boca a 0,95 m del pivote)

Ejes: x delante (donde apunta), y izquierda, z arriba, metros.

    blender -b --factory-startup --python tools/blender/torreta.py

Escribe assets/almacen/torreta.glb (objetos base, cabezal y canon).
"""
import math
import os
import bpy

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(RAIZ, 'assets', 'almacen', 'torreta.glb')


def material(nombre, color, rugosidad, metal=0.0, emision=0.0):
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rugosidad
    p.inputs['Metallic'].default_value = metal
    if emision > 0:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emision
    return m


M = {}


def materiales():
    M['negro'] = material('torretaNegro', (0.16, 0.17, 0.18), 0.4, 0.5)
    M['acero'] = material('torretaAcero', (0.62, 0.63, 0.65), 0.28, 0.85)
    M['rojo'] = material('torretaRojo', (0.62, 0.07, 0.04), 0.35, 0.2)
    M['goma'] = material('torretaGoma', (0.02, 0.02, 0.02), 0.85, 0.0)
    M['sensor'] = material('torretaSensor', (1.0, 0.06, 0.03), 0.15, 0.0, 10.0)


def biselar(o, ancho, segmentos=3):
    if ancho <= 0:
        return o
    bpy.context.view_layer.objects.active = o
    mod = o.modifiers.new('bisel', 'BEVEL')
    mod.width = ancho
    mod.segments = segmentos
    mod.limit_method = 'ANGLE'
    bpy.ops.object.modifier_apply(modifier='bisel')
    return o


def caja(centro, medidas, mat, bisel=0.01):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centro)
    o = bpy.context.object
    o.scale = medidas
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return biselar(o, bisel)


def cilindro(centro, radio, largo, mat, eje='z', lados=64, bisel=0.004):
    bpy.ops.mesh.primitive_cylinder_add(vertices=lados, radius=radio, depth=largo, location=centro)
    o = bpy.context.object
    if eje == 'x':
        o.rotation_euler = (0, math.pi / 2, 0)
    elif eje == 'y':
        o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(mat)
    return biselar(o, bisel, 2)


def unir(nombre, partes):
    bpy.ops.object.select_all(action='DESELECT')
    for o in partes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = partes[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = nombre
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=0.6)
    except Exception:
        pass
    return o


def base():
    q = [
        cilindro((0, 0, 0.03), 0.45, 0.06, M['negro'], lados=8, bisel=0.012),
        cilindro((0, 0, 0.075), 0.2, 0.03, M['acero'], lados=64),
        cilindro((0, 0, 0.38), 0.11, 0.6, M['negro'], lados=64, bisel=0.01),
        cilindro((0, 0, 0.69), 0.17, 0.06, M['acero'], lados=96, bisel=0.008),
        cilindro((0, 0, 0.42), 0.125, 0.04, M['rojo'], lados=64),
    ]
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        q.append(cilindro((math.cos(a) * 0.36, math.sin(a) * 0.36, 0.07), 0.022, 0.025, M['acero'], lados=6, bisel=0.003))
    # Cartelas de la columna.
    for k in range(4):
        a = 2 * math.pi * k / 4
        o = caja((math.cos(a) * 0.17, math.sin(a) * 0.17, 0.17), (0.14, 0.025, 0.2), M['negro'], 0.006)
        o.rotation_euler = (0, 0, a)
        bpy.ops.object.transform_apply(rotation=True)
        q.append(o)
    return unir('base', q)


def cabezal():
    q = [
        cilindro((0, 0, 0.025), 0.24, 0.05, M['negro'], lados=96, bisel=0.008),
        cilindro((0, 0, 0.055), 0.2, 0.012, M['acero'], lados=96),
        caja((-0.17, 0, 0.16), (0.2, 0.32, 0.2), M['rojo'], 0.02),
        caja((-0.275, 0, 0.16), (0.015, 0.24, 0.12), M['negro'], 0.004),
    ]
    for lado in (-1, 1):
        q.append(caja((0.0, lado * 0.19, 0.2), (0.32, 0.04, 0.34), M['negro'], 0.012))
        q.append(cilindro((0.0, lado * 0.215, 0.28), 0.06, 0.02, M['acero'], eje='y', lados=64))
    # Sensor: caja con una lente roja que brilla, encima de la electrónica.
    q.append(caja((-0.13, 0, 0.3), (0.14, 0.12, 0.08), M['negro'], 0.01))
    q.append(cilindro((-0.055, 0, 0.3), 0.032, 0.02, M['sensor'], eje='x', lados=48, bisel=0.003))
    q.append(cilindro((-0.06, 0, 0.3), 0.042, 0.012, M['acero'], eje='x', lados=48, bisel=0.002))
    q.append(cilindro((-0.22, 0.08, 0.42), 0.004, 0.18, M['acero'], lados=12, bisel=0))
    return unir('cabezal', q)


def canon():
    q = [
        cilindro((0, 0, 0), 0.05, 0.36, M['acero'], eje='y', lados=64),
        caja((0.08, 0, 0), (0.36, 0.22, 0.17), M['negro'], 0.025),
        caja((0.08, 0, 0.088), (0.26, 0.14, 0.012), M['rojo'], 0.004),
        caja((0.03, 0.155, -0.02), (0.18, 0.09, 0.13), M['negro'], 0.012),
        caja((0.03, 0.2, -0.02), (0.12, 0.006, 0.07), M['acero'], 0.002),
        cilindro((0.6, 0, 0.01), 0.032, 0.6, M['acero'], eje='x', lados=64, bisel=0.003),
        cilindro((0.29, 0, 0.01), 0.055, 0.06, M['negro'], eje='x', lados=64, bisel=0.006),
        cilindro((0.93, 0, 0.01), 0.048, 0.07, M['negro'], eje='x', lados=64, bisel=0.006),
    ]
    for xa in (0.42, 0.5, 0.58):
        q.append(cilindro((xa, 0, 0.01), 0.042, 0.018, M['negro'], eje='x', lados=64, bisel=0.003))
    # Ranuras del freno de boca.
    for lado in (-1, 1):
        q.append(caja((0.93, lado * 0.045, 0.01), (0.03, 0.01, 0.05), M['goma'], 0.002))
    return unir('canon', q)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materiales()
    base()
    cabezal()
    canon()
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_yup=True)
    print('EXPORTADO', GLB)


main()

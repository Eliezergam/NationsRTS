"""Bloque enemigo de práctica para el soldado (el dueño, 18-nov: «ponle
bloques como enemigos y prográmale que dispare»). Un bloque de 0,6 x 0,6 x
1,5 m (del tamaño de un robot de pie) de chapa roja con cantos biselados,
zócalo negro y una visera que brilla en rojo, para que se lea como enemigo.

    blender -b --factory-startup --python tools/blender/bloque_enemigo.py

Escribe assets/almacen/bloque_enemigo.glb (objeto `bloque`, origen en el
suelo, en el centro).
"""
import os
import bpy
import bmesh

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(RAIZ, 'assets', 'almacen', 'bloque_enemigo.glb')


def material(nombre, color, rugosidad, metal=0.0, emision=None):
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rugosidad
    p.inputs['Metallic'].default_value = metal
    if emision:
        p.inputs['Emission Color'].default_value = (*emision, 1)
        p.inputs['Emission Strength'].default_value = 4.0
    return m


def caja(nombre, centro, medidas, mat, bisel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centro)
    o = bpy.context.object
    o.name = nombre
    o.scale = medidas
    bpy.ops.object.transform_apply(scale=True)
    if bisel > 0:
        mod = o.modifiers.new('bisel', 'BEVEL')
        mod.width = bisel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier='bisel')
    o.data.materials.append(mat)
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rojo = material('bloqueRojo', (0.42, 0.045, 0.035), 0.45, 0.3)
    negro = material('bloqueNegro', (0.025, 0.025, 0.028), 0.6, 0.2)
    visera = material('bloqueVisera', (0.3, 0.0, 0.0), 0.2, 0.0, emision=(1.0, 0.08, 0.04))
    partes = [
        caja('cuerpo', (0, 0, 0.8), (0.6, 0.6, 1.3), rojo, 0.025),
        caja('zocalo', (0, 0, 0.075), (0.66, 0.66, 0.15), negro, 0.015),
        caja('tapa', (0, 0, 1.47), (0.56, 0.56, 0.06), negro, 0.012),
        # Visera: una ranura que brilla, delante y detrás (se ve venga de
        # donde venga), y una franja negra a cada lado.
        caja('visera', (0, 0, 1.25), (0.62, 0.42, 0.07), visera, 0.008),
        caja('visera2', (0, 0, 1.25), (0.42, 0.62, 0.07), visera, 0.008),
        caja('franja', (0, 0, 0.55), (0.615, 0.615, 0.05), negro, 0.006),
    ]
    bpy.ops.object.select_all(action='DESELECT')
    for o in partes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = partes[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = 'bloque'
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=0.6)
    except Exception:
        pass
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=False, export_yup=True)
    print('EXPORTADO', GLB)


main()

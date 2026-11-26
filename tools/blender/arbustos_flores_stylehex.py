"""arbustos_flores_stylehex.py - Arbustos y flores del pack StyleHex (FREE
Stylized Forest Sample, Fab; FBX exportados de Unreal en
NationsRTS-UE-assets/stylehex_export) a tablas Lua para la batalla:
assets/batalla/arbustos/<modelo>.lua.

blender -b --python tools/blender/arbustos_flores_stylehex.py

Por detalle (LOD0, LOD1 del pack): lista plana {x, y, z, nx, ny, nz, u, v} por
vértice, metros, Y arriba, v desde arriba. Arbustos: normal esférica desde el
centro y u a una de las 4 BANDAS de su textura por la altura (verde oscuro
abajo, claro arriba, como el «Local Gradient» del pack). Flores: normal arriba.
"""
import bpy
from mathutils import Vector
ORIGEN = '~/games/NationsRTS-UE-assets/stylehex_export/%s.fbx'
SALIDA = '~/NationsRTS/assets/batalla/arbustos/%s.lua'
BANDAS = 4
MODELOS = [('SM_Fol_Bush_1', True), ('SM_Fol_Bush_2', True),
           ('SM_Fol_Flower_Clump_1', False), ('SM_Fol_Flower_Clump_2', False), ('SM_Fol_Flower_Clump_3', False)]
for nombre, arbusto in MODELOS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=ORIGEN % nombre)
    lineas = ['-- Generado por tools/blender/arbustos_flores_stylehex.py (pack StyleHex, Fab).', 'return {']
    for lod in (0, 1):
        o = next(o for o in bpy.data.objects if o.name.endswith('_LOD%d' % lod) and not o.name.startswith('UCX'))
        m = o.data
        m.calc_loop_triangles()
        uv = m.uv_layers[0].data
        W = o.matrix_world
        puntos = [W @ v.co for v in m.vertices]
        zmin, zmax = min(p.z for p in puntos), max(p.z for p in puntos)
        centro = sum(puntos, Vector()) / len(puntos)
        datos = []
        for t in m.loop_triangles:
            ps = [W @ m.vertices[m.loops[li].vertex_index].co for li in t.loops]
            uvs = [uv[li].uv for li in t.loops]
            medio = (ps[0] + ps[1] + ps[2]) / 3
            banda = min(BANDAS - 1, int((medio.z - zmin) / (zmax - zmin + 1e-6) * BANDAS))
            for p, (u, v) in zip(ps, uvs):
                if arbusto:
                    n = p - centro; n.z += 0.4 * n.length; n.normalize()
                    u = (min(max(u, 0), 1) + banda) / BANDAS
                else:
                    n = Vector((0, 0, 1))
                datos += [p.x, p.z, -p.y, n.x, n.z, -n.y, u, 1 - v]
        lineas.append('  {' + ','.join('%.4f' % x for x in datos) + '},')
        print('PIEZA', nombre, 'LOD', lod, len(datos) // 24, 'triangulos', 'alto', round(zmax, 2))
    lineas.append('}')
    open(SALIDA % nombre, 'w').write('\n'.join(lineas) + '\n')

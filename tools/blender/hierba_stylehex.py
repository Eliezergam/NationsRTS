"""hierba_stylehex.py - Pasa las matas de hierba del pack StyleHex (FREE Stylized
Forest Sample, Fab; exportadas de Unreal a FBX en NationsRTS-UE-assets/stylehex_export)
a una tabla Lua para la batalla: assets/batalla/hierba/matas_stylehex.lua.

blender -b --python tools/blender/hierba_stylehex.py

Por mata y detalle (LOD0, LOD1, LOD2): lista plana de vértices de triángulos
{x, y, z, u, v} en metros, Y arriba (Blender x, z, -y), v desde arriba (LÖVE).
"""
import bpy
ORIGEN = '~/games/NationsRTS-UE-assets/stylehex_export/SM_Fol_Grass_Clump_%d.fbx'
SALIDA = '~/NationsRTS/assets/batalla/hierba/matas_stylehex.lua'
lineas = ['-- Generado por tools/blender/hierba_stylehex.py: matas de hierba del pack',
          '-- StyleHex (Fab). [mata][detalle] = { x, y, z, u, v, ... } por vértice.', 'return {']
for i in range(1, 6):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=ORIGEN % i)
    lineas.append('  {')
    for lod in (0, 1, 2):
        o = next(o for o in bpy.data.objects if o.name.endswith('_LOD%d' % lod))
        m = o.data
        m.calc_loop_triangles()
        uv = m.uv_layers[0].data
        nums = []
        for t in m.loop_triangles:
            for li in t.loops:
                p = o.matrix_world @ m.vertices[m.loops[li].vertex_index].co
                u, v = uv[li].uv
                nums += [p.x, p.z, -p.y, u, 1 - v]
        lineas.append('    {' + ','.join('%.4f' % n for n in nums) + '},')
        print('MATA', i, 'LOD', lod, len(nums) // 15, 'triangulos')
    lineas.append('  },')
lineas.append('}')
open(SALIDA, 'w').write('\n'.join(lineas) + '\n')

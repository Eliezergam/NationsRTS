"""arboles_stylehex.py - Pasa los árboles del pack StyleHex (FREE Stylized Forest
Sample, Fab; exportados de Unreal a FBX en NationsRTS-UE-assets/stylehex_export)
a tablas Lua para la batalla: assets/batalla/arboles/<arbol>.lua.

blender -b --python tools/blender/arboles_stylehex.py

Por LOD (0, 2, 3 del pack): `tronco` = {x, y, z, nx, ny, nz, u, v} por vértice
y `copa` = {x, y, z, nx, ny, nz, u, v}. Metros, Y arriba (Blender x, z, -y),
v desde arriba (LÖVE). La copa lleva la normal esférica desde el centro de la
copa (luz suave y redonda, como en el pack) y su u va a una de las BANDAS de
la textura de hojas según la altura (verde oscuro abajo, claro arriba: el
«Local Gradient» del material del pack).
"""
import bpy
from mathutils import Vector
ORIGEN = '~/games/NationsRTS-UE-assets/stylehex_export/%s.fbx'
SALIDA = '~/NationsRTS/assets/batalla/arboles/%s.lua'
BANDAS = 4
for nombre in ['SM_Tree_Birch_1', 'SM_Tree_Birch_2', 'SM_Tree_Broadleaf_1', 'SM_Tree_Broadleaf_2']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=ORIGEN % nombre)
    lineas = ['-- Generado por tools/blender/arboles_stylehex.py (pack StyleHex, Fab).', 'return {']
    for lod in (0, 2, 3):
        o = next(o for o in bpy.data.objects if o.name.endswith('_LOD%d' % lod) and not o.name.startswith('UCX'))
        m = o.data
        m.calc_loop_triangles()
        uv = m.uv_layers[0].data
        W = o.matrix_world
        hoja = [i for i, mat in enumerate(m.materials) if 'Leaves' in mat.name]
        # Centro y alto de la copa.
        puntos = [W @ m.vertices[v].co for t in m.loop_triangles if t.material_index in hoja for v in t.vertices]
        zmin, zmax = min(p.z for p in puntos), max(p.z for p in puntos)
        centro = sum(puntos, Vector()) / len(puntos)
        tronco, copa = [], []
        umin = vmin = 1e9; umax = vmax = -1e9
        for t in m.loop_triangles:
            ps = [W @ m.vertices[m.loops[li].vertex_index].co for li in t.loops]
            uvs = [uv[li].uv for li in t.loops]
            if t.material_index in hoja:
                medio = (ps[0] + ps[1] + ps[2]) / 3
                banda = min(BANDAS - 1, int((medio.z - zmin) / (zmax - zmin + 1e-6) * BANDAS))
                for p, (u, v) in zip(ps, uvs):
                    n = (p - centro); n.z *= 0.6; n.z += 0.35 * n.length; n.normalize()
                    copa += [p.x, p.z, -p.y, n.x, n.z, -n.y, (min(max(u, 0), 1) + banda) / BANDAS, 1 - v]
            else:
                ns = [W.to_3x3() @ m.loops[li].normal for li in t.loops]
                for p, n, (u, v) in zip(ps, ns, uvs):
                    tronco += [p.x, p.z, -p.y, n.x, n.z, -n.y, u, 1 - v]
                    umin, umax, vmin, vmax = min(umin, u), max(umax, u), min(vmin, v), max(vmax, v)
        f = lambda xs: '{' + ','.join('%.4f' % x for x in xs) + '}'
        lineas.append('  { tronco = %s, copa = %s, alto = %.2f },' % (f(tronco), f(copa), zmax))
        print('ARBOL', nombre, 'LOD', lod, 'tronco', len(tronco) // 24, 'copa', len(copa) // 24, 'uv tronco', round(umin, 2), round(umax, 2), round(vmin, 2), round(vmax, 2))
    lineas.append('}')
    open(SALIDA % nombre, 'w').write('\n'.join(lineas) + '\n')

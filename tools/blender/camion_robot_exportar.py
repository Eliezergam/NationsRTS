"""Camión de 4 misiles con robot conductor, al juego como un robot más
(el dueño, 18-nov: «usar la misma lógica de los robots y la programación que
llevamos»): robots/nucleo.lua, tipo `camionMisiles`.

    blender -b ~/NationsRTS-assets/camion_misiles_robot/maqueta.blend \\
        --python tools/blender/camion_robot_exportar.py

Fuente: la maqueta (el camión sin cabina con los colores de los robots y los
misiles verdes, el asiento, las palancas y el puesto de los pies de
camion_robot_puesto.py; el chasis a escala 10 porque las piezas del .glb
viejo están en unidades de 10 m). Esto lo pasa todo a metros con el chasis
como raíz (x delante, y izquierda, z arriba, suelo en z = 0), une al chasis
lo fijo nuevo, quita el robot (en el juego es un robot aparte: tipo
`conductor`), las puertas y la franja de la nación, y lo exporta con
robot_soldado.exportarJuego:

    assets/batalla/robots/camionMisiles.glb + camionMisiles_piezas.lua
    (y _lod1/_lod2 cuando exista camionMisiles_moviles.lua)
    assets/batalla/robots/camionMisiles_puesto.lua: qué piezas del puesto
    giran y cuánto por radián del engranaje del pie del robot.

Piezas sin malla: `asientoConductor` (donde va la pelvis del robot
sentado, con su orientación).

Sin nada del pack de Synty (el dueño, 21-nov, copia pública): los cuatro
misiles de la maqueta (la malla de misil_synty4) se cambian aquí por el misil
propio de misil_camion.py, y lo que usaba `unidadCamion4` (el atlas horneado
con el de Synty: baliza y luces del chasis) pasa a `camionBaliza`. Sus
texturas, en assets/almacen/materiales_robot (tools/texturas_camion_robot.py).
"""

import os

import bpy
from mathutils import Matrix, Vector

_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.expanduser('~/NationsRTS/tools/blender')
RAIZ = os.path.abspath(os.path.join(_DIR, '..', '..'))
SALIDA = os.path.join(RAIZ, 'assets', 'batalla', 'robots', 'camionMisiles.glb')
O = bpy.data.objects

_S = {'__name__': 'soldado', '__file__': os.path.join(_DIR, 'robot_soldado.py')}
with open(_S['__file__'], encoding='utf8') as _archivo:
    exec(_archivo.read(), _S)
_M = {'__name__': 'misilCamion'}
with open(os.path.join(_DIR, 'misil_camion.py'), encoding='utf8') as _archivo:
    exec(_archivo.read(), _M)

MISILES = ('misilExteriorDerecho', 'misilInteriorDerecho', 'misilInteriorIzquierdo', 'misilExteriorIzquierdo')


def aMalla(o):
    """Copia en malla (curvas y modificadores aplicados), en su sitio."""
    grafo = bpy.context.evaluated_depsgraph_get()
    malla = bpy.data.meshes.new_from_object(o.evaluated_get(grafo))
    nuevo = bpy.data.objects.new(o.name + '_m', malla)
    bpy.context.scene.collection.objects.link(nuevo)
    nuevo.matrix_world = o.matrix_world.copy()
    for k in o.keys():
        nuevo[k] = o[k]
    return nuevo


def colgar(hija, madre):
    mundo = hija.matrix_world.copy()
    hija.parent = madre
    hija.matrix_world = mundo


def materialPropio(nombre, color, emision=0.0):
    """Material de Blender con el nombre de la biblioteca del juego (el .glb
    va sin texturas: el juego pone las de assets/almacen/materiales_robot)."""
    material = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    material.use_nodes = True
    bsdf = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 0.5
    if emision > 0:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emision
    return material


def misilesPropios():
    """Los cuatro misiles, con la malla de misil_camion.py en su sitio (la
    maqueta los tiene a escala 10, con el origen en la cola), y la baliza y
    las luces del chasis con `camionBaliza`."""
    camuflaje = materialPropio('camionMisil', (0.15, 0.19, 0.075))
    baliza = materialPropio('camionBaliza', (0.87, 0.34, 0.03), 4.0)
    m = {
        'camuflaje': camuflaje,
        'negro': bpy.data.materials['robotNegro'],
        'blanco': bpy.data.materials.get('robotBlanco') or bpy.data.materials['pesadoBlanco'],
        'acero': bpy.data.materials.get('robotAcero') or bpy.data.materials['pesadoAcero'],
    }
    for k, nombre in enumerate(MISILES):
        objeto = O[nombre]
        nuevo = _M['construirMisilCamion'](_S, m, desfase=k * 1.1)
        malla = nuevo.data
        escala = objeto.matrix_world.to_scale()
        malla.transform(Matrix.Diagonal((1 / escala.x, 1 / escala.y, 1 / escala.z, 1)))
        viejo = objeto.data
        objeto.data = malla
        malla.name = nombre
        bpy.data.objects.remove(nuevo)
        if viejo.users == 0:
            bpy.data.meshes.remove(viejo)
    for objeto in O:
        if objeto.type != 'MESH':
            continue
        for ranura in objeto.material_slots:
            if ranura.material and ranura.material.name.split('.')[0] == 'unidadCamion4':
                ranura.material = baliza
    viejo = bpy.data.materials.get('unidadCamion4')
    if viejo and viejo.users == 0:
        bpy.data.materials.remove(viejo)


def principal():
    bpy.context.view_layer.update()
    misilesPropios()
    # El robot: solo se apunta dónde va sentado.
    pelvis = O['pelvis']
    asiento = pelvis.matrix_world.copy()
    for o in [pelvis] + list(pelvis.children_recursive):
        bpy.data.objects.remove(o)
    for o in list(O):
        if o.name.startswith('engranajePie') or o.type in ('LIGHT', 'CAMERA') or o.name in ('insignia', 'puertaIzquierda', 'puertaDerecha'):
            bpy.data.objects.remove(o)
    chasis = O['chasis']
    # Piezas del camión (las del .glb viejo, colgadas del chasis): a metros.
    camion = [chasis] + list(chasis.children_recursive)
    padres = {o.name: (o.parent.name if o.parent else None) for o in camion}
    mundos = {o.name: o.matrix_world.copy() for o in camion}
    for o in camion:
        o.parent = None
    for o in camion:
        m = mundos[o.name]
        lineal = m.to_3x3().to_4x4()
        o.data.transform(lineal)
        o.matrix_world = Matrix.Translation(m.to_translation())
    bpy.context.view_layer.update()
    for o in camion:
        if padres[o.name]:
            colgar(o, O[padres[o.name]])
    # Baliza: del techo que ya no está al respaldo del asiento.
    baliza = O.get('balizaLuz')
    if baliza:
        baliza.hide_set(False)
        baliza.hide_viewport = False
        baliza.matrix_world = Matrix.Translation((3.95, -0.25, 3.24))
    # Puesto: las piezas que giran, colgadas del chasis; lo fijo, unido a él.
    estructura = O['puestoEstructura']
    moviles = [o for o in estructura.children if 'giro' in o]
    giros = [(o.name, o['eje'], float(o['giro'])) for o in moviles]
    for o in moviles:
        colgar(o, chasis)
    fijos = [estructura] + [o for o in O if o.name.startswith('maqueta')]
    unir = []
    for o in fijos:
        if o.type in ('MESH', 'CURVE'):
            m = aMalla(o)
            m.data.transform(m.matrix_world)
            m.matrix_world = Matrix.Identity(4)
            unir.append(m)
    for o in fijos:
        bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    lineal = chasis.matrix_world.inverted()
    for m in unir:
        m.data.transform(lineal)
        m.matrix_world = chasis.matrix_world.copy()
    with bpy.context.temp_override(active_object=chasis, selected_editable_objects=[chasis] + unir, selected_objects=[chasis] + unir):
        bpy.ops.object.join()
    # Modificadores aplicados en todo lo que queda.
    for o in [o for o in O if o.type == 'MESH' and o.modifiers]:
        grafo = bpy.context.evaluated_depsgraph_get()
        malla = bpy.data.meshes.new_from_object(o.evaluated_get(grafo))
        o.modifiers.clear()
        o.data = malla
    # Dónde va sentado el robot (pieza sin malla).
    vacio = bpy.data.objects.new('asientoConductor', None)
    bpy.context.scene.collection.objects.link(vacio)
    vacio.matrix_world = asiento
    colgar(vacio, chasis)
    # Qué gira del puesto.
    ruta = os.path.splitext(SALIDA)[0] + '_puesto.lua'
    with open(ruta, 'w', encoding='utf8') as f:
        f.write('-- Piezas del puesto del conductor que giran (tools/blender/camion_robot_exportar.py):\n')
        f.write('-- eje de la pieza y radianes por radián del engranaje del pie del robot.\n')
        f.write('return {\n')
        for nombre, eje, giro in sorted(giros):
            f.write("    { pieza = '%s', eje = '%s', giro = %.5f },\n" % (nombre, eje, giro))
        f.write('}\n')
    print('PUESTO', ruta, len(giros))
    _S['exportarJuego'](SALIDA, raiz='chasis', conservarUv=('camionMisil',))


if __name__ == '__main__':
    principal()

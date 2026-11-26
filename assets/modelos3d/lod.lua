-- Generado por tools/blender/lod_modelos.py (lod_laminas.py): no editar a mano.
--
-- Niveles de detalle de los modelos de la batalla 3D. Láminas con los cuatro
-- niveles y el impostor en assets/modelos3d/previews/lod/<modelo>.jpg.
--
-- niveles[1..4] = LOD0..LOD3:
--   archivo      sin extensión: .glb para 3Dream y, en vehículos, .lua con el
--                contrato de piezas (el soldado solo tiene .glb).
--   triangulos   del .glb (lo que se dibuja), franjas de la nación incluidas.
--   material     el de assets/modelos3d/materiales. LOD0 y LOD1 usan el del
--                modelo; LOD2 y LOD3 llevan uno horneado propio (<material>Lod2,
--                <material>Lod3) porque su UV es nueva.
--   pantalla     el nivel vale mientras el diámetro de la esfera envolvente
--                (2 * radio) ocupe al menos esta fracción del alto de la
--                pantalla; por debajo de la del último nivel, el impostor.
--   distancia    lo mismo en metros de cámara con el FOV vertical de 40 de la
--                batalla (fov abajo): el nivel vale hasta esa distancia.
--   esqueleto    (soldado) LOD0-LOD2 con el mismo esqueleto y los mismos clips;
--                LOD3 es una malla fija en la pose del primer cuadro de 'quieto'.
--   unaPieza     (vehículos, LOD3) torreta, cañón, contenedor y ruedas unidos
--                en reposo a la pieza raíz (casco o chasis). El .lua trae
--                pivotesLod0 para la boca. El camión lanzamisiles de 4 misiles
--                (Scud-B) está en lod_camiones.lua.
--
-- LOD1 y LOD2 tienen las mismas piezas, pivotes y extras (boca, bocas,
-- elevacion) que LOD0: la torreta gira y el contenedor se eleva igual.
--
-- impostor: atlas RGBA de `columnas` x `filas` celdas de `celda` px.
--   Columna c: cámara a c * 360 / columnas grados alrededor del modelo,
--   empezando delante (+x del modelo) y girando hacia su izquierda (+y de
--   Blender, -y del juego). Fila f: cámara a elevaciones[f + 1] grados sobre
--   el horizonte (fila 0 arriba en la imagen). Vista ortográfica: cada celda
--   abarca `lado` metros y su centro es el punto `centro` del modelo (metros;
--   x adelante, y a la izquierda, z arriba; el origen es el del .glb, en el
--   suelo). Color con luz neutra (cielo blanco y sol cenital); las franjas
--   de la nación salen en gris. `normal`: normal en espacio de la cámara,
--   R derecha, G arriba, B hacia la cámara (128 = 0), del mapa de normales
--   del material incluido.
--
-- radio: de la esfera envolvente de LOD0 en reposo, en metros.

return {
    fov = 40,
    modelos = {
    },
}

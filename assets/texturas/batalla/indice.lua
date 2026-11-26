-- Generado por tools/blender/texturas_batalla.py: no editar a mano.
-- Texturas PBR del mapa 3D de la batalla (CC0, ver LICENCIAS.md).
-- Cada material: albedo (sRGB), normal (OpenGL, verde hacia +V) y
-- material (R metálico, G rugosidad, B oclusión), a 2048 px en la
-- carpeta del material y a 1024 y 512 en 1k/ y 512/. `tile` son los
-- metros de suelo que cubre una repetición. Todas se repiten sin costura.
-- La carpeta sirve de biblioteca de 3Dream: BibliotecaPbr.cargar(dream,
-- 'assets/texturas/batalla') registra cada material a 2K con su nombre.
local carpeta = 'assets/texturas/batalla'

local function mapas(nombre, alfa)
    local resultado = {}
    for _, calidad in ipairs({ 'alta', 'media', 'baja' }) do
        local sub = ({ alta = '', media = '/1k', baja = '/512' })[calidad]
        local ruta = carpeta .. '/' .. nombre .. sub .. '/'
        resultado[calidad] = {
            albedo = ruta .. (alfa and 'albedo.png' or 'albedo.jpg'),
            normal = ruta .. 'normal.jpg',
            material = ruta .. 'material.jpg',
        }
    end
    return resultado
end

return {
    carpeta = carpeta,
    lados = { alta = 2048, media = 1024, baja = 512 },
    materiales = {
        hierba = {
            uso = 'terreno',
            descripcion = 'Hierba verde densa (prados, valles)',
            tile = 1.4,
            alfa = false,
            fuente = 'https://ambientcg.com/view?id=Grass004',
            mapas = mapas('hierba', false),
        },
        hierbaSeca = {
            uso = 'terreno',
            descripcion = 'Hierba rala con hojas y tierra (bordes, bosque, verano)',
            tile = 2.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/leafy_grass',
            mapas = mapas('hierbaSeca', false),
        },
        barro = {
            uso = 'terreno',
            descripcion = 'Tierra húmeda y barro (caminos de tierra, orillas, huellas)',
            tile = 1.3,
            alfa = false,
            fuente = 'https://polyhaven.com/a/brown_mud_02',
            mapas = mapas('barro', false),
        },
        acantilado = {
            uso = 'terreno',
            descripcion = 'Roca estratificada gris con algo de musgo (pendientes)',
            tile = 4.0,
            alfa = false,
            fuente = 'https://ambientcg.com/view?id=Rock028',
            mapas = mapas('acantilado', false),
        },
        arena = {
            uso = 'terreno',
            descripcion = 'Arena de orilla con chinas (playas, ríos)',
            tile = 6.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/coast_sand_01',
            mapas = mapas('arena', false),
        },
        nieve = {
            uso = 'terreno',
            descripcion = 'Nieve asentada (alturas)',
            tile = 2.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/snow_01',
            mapas = mapas('nieve', false),
        },
        tierraPedregosa = {
            uso = 'terreno',
            descripcion = 'Tierra seca con piedras (estepa, desierto, laderas secas)',
            tile = 4.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/dry_ground_rocks',
            mapas = mapas('tierraPedregosa', false),
        },
        roca = {
            uso = 'rocas',
            descripcion = 'Roca de peñascos y piedras sueltas (proyección triplanar)',
            tile = 2.0,
            alfa = false,
            fuente = 'https://ambientcg.com/view?id=Rock060',
            mapas = mapas('roca', false),
        },
        corteza = {
            uso = 'arboles',
            descripcion = 'Corteza parda de árbol de hoja ancha',
            tile = 1.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/bark_brown_02',
            mapas = mapas('corteza', false),
        },
        asfalto = {
            uso = 'caminos',
            descripcion = 'Asfalto gastado (carreteras y alrededores de ciudades)',
            tile = 3.0,
            alfa = false,
            fuente = 'https://polyhaven.com/a/asphalt_02',
            mapas = mapas('asfalto', false),
        },
        hojas = {
            uso = 'arboles',
            descripcion = 'Racimo de hojas con alfa para tarjetas de copa (compuesto aquí con Leaf001)',
            tile = 1.0,
            alfa = true,
            fuente = 'https://ambientcg.com/view?id=Leaf001',
            mapas = mapas('hojas', true),
        },
    },
}

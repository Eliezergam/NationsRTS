# Texturas PBR de los robots para el juego (el dueño, 17-nov: que se vean como
# el ejemplo AlphaBlending de 3DreamEngine, con texturas reales y no colores
# lisos). En Blender los robots usan texturas de Poly Haven / ambientCG (CC0)
# en proyección de caja (robot_almacen.py `materialPBR`); eso no viaja en el
# glb. Aquí se hacen las mismas a 1024 para la biblioteca de materiales del
# juego (batalla/dream/biblioteca_pbr.lua): una carpeta por material con el
# nombre que trae el glb, con
#   albedo.png   el color de la pintura limpia (con una variación leve de la
#                luminancia de la chapa real) o, en la goma, la textura real
#   material.png R metálico, G rugosidad (la de la textura, alrededor de la
#                del material), B oclusión (1)
#   normal.png   la normal real (OpenGL), suavizada a la fuerza del material
# Las UV de los robots son la posición en metros (uvCaja): la imagen cubre
# 1 m, con la textura repetida `escala` veces como en Blender.
#
#     python3 tools/texturas_robots.py

import os

from PIL import Image, ImageOps

TEXTURAS = os.path.expanduser('~/NationsRTS-assets/robots/texturas')
RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SALIDA = os.path.join(RAIZ, 'assets', 'almacen', 'materiales_robot')
LADO = 1024

PLACA = {'color': 'metal_plate_02_diff.jpg', 'rugosidad': 'metal_plate_02_rough.jpg', 'normal': 'metal_plate_02_nor.jpg'}
GOMA = {'color': 'Rubber004/Rubber004_4K-JPG_Color.jpg', 'rugosidad': 'Rubber004/Rubber004_4K-JPG_Roughness.jpg', 'normal': 'Rubber004/Rubber004_4K-JPG_NormalGL.jpg'}

# nombre: (color lineal, rugosidad, metálico, textura, escala, fuerza de la
# normal, color de la textura). Los mismos números que en Blender.
MATERIALES = {
    'Blanco': ((0.8, 0.81, 0.83), 0.35, 0.05, PLACA, 1.0, 0.35, False),
    'Negro': ((0.014, 0.014, 0.016), 0.45, 0.1, PLACA, 1.0, 0.4, False),
    'Plata': ((0.72, 0.73, 0.75), 0.22, 1.0, PLACA, 1.0, 0.25, False),
    'Acero': ((0.56, 0.57, 0.59), 0.3, 1.0, PLACA, 2.0, 0.25, False),
    'Goma': ((0.32, 0.32, 0.32), 0.8, 0.0, GOMA, 1.5, 0.8, True),
    'Garra': ((0.02, 0.02, 0.022), 0.5, 0.2, PLACA, 1.5, 0.5, False),
    # Las que en Blender son lisas: con la chapa, para que no sean plástico.
    'NegroMate': ((0.04, 0.04, 0.045), 0.7, 0.0, PLACA, 1.0, 0.3, False),
    'Articulacion': ((0.05, 0.052, 0.056), 0.3, 0.6, PLACA, 1.5, 0.25, False),
    'Gris': ((0.35, 0.36, 0.38), 0.4, 0.3, PLACA, 1.0, 0.3, False),
    'Amarillo': ((0.95, 0.68, 0.02), 0.4, 0.1, PLACA, 1.0, 0.3, False),
}
# El robot grande nombra pesado* las que tienen textura en Blender.
PESADO = ('Blanco', 'Negro', 'Plata', 'Acero', 'Goma', 'Garra')


def aSrgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


_cache = {}


def cargar(nombre, escala, modo):
    clave = (nombre, escala, modo)
    if clave not in _cache:
        imagen = Image.open(os.path.join(TEXTURAS, nombre)).convert(modo)
        lado = max(16, round(LADO / escala))
        tesela = imagen.resize((lado, lado), Image.LANCZOS)
        mosaico = Image.new(modo, (LADO, LADO))
        for x in range(0, LADO, lado):
            for y in range(0, LADO, lado):
                mosaico.paste(tesela, (x, y))
        _cache[clave] = mosaico
    return _cache[clave]


def hacer(nombre, datos):
    color, rugosidad, metalico, textura, escala, fuerza, usarColor = datos
    carpeta = os.path.join(SALIDA, nombre)
    os.makedirs(carpeta, exist_ok=True)
    # Albedo.
    if usarColor:
        base = cargar(textura['color'], escala, 'RGB')
        albedo = base.point(lambda v: round(255 * aSrgb((v / 255) ** 2.2 * color[0])))
    else:
        luz = ImageOps.autocontrast(cargar(textura['color'], escala, 'L'))
        # Variación leve (0,9-1,08) de la luminancia de la chapa real.
        canales = []
        for c in color:
            canales.append(luz.point(lambda v, c=c: round(255 * min(1.0, aSrgb(c * (0.9 + 0.18 * v / 255))))))
        albedo = Image.merge('RGB', canales)
    albedo.save(os.path.join(carpeta, 'albedo.png'))
    # Metálico, rugosidad, oclusión.
    rug = cargar(textura['rugosidad'], escala, 'L')
    lo, hi = max(0.0, rugosidad - 0.12), min(1.0, rugosidad + 0.12)
    g = rug.point(lambda v: round(255 * (lo + (hi - lo) * v / 255)))
    r = Image.new('L', (LADO, LADO), round(255 * metalico))
    b = Image.new('L', (LADO, LADO), 255)
    Image.merge('RGB', (r, g, b)).save(os.path.join(carpeta, 'material.png'))
    # Normal, hacia la plana según la fuerza.
    nor = cargar(textura['normal'], escala, 'RGB')
    plana = Image.new('RGB', (LADO, LADO), (128, 128, 255))
    Image.blend(plana, nor, fuerza).save(os.path.join(carpeta, 'normal.png'))
    with open(os.path.join(carpeta, 'material.lua'), 'w') as archivo:
        archivo.write('-- Generado por tools/texturas_robots.py: no editar a mano.\n')
        archivo.write('return {\n    roughness = 1,\n    metallic = 1,\n}\n')


def principal():
    for clave, datos in MATERIALES.items():
        hacer('robot' + clave, datos)
        print('robot' + clave)
    for clave in PESADO:
        hacer('pesado' + clave, MATERIALES[clave])
        print('pesado' + clave)


principal()

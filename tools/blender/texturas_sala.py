# Texturas de los puestos de la sala de control del almacén (el dueño,
# 26-nov: «teclado con teclas, ratón, PC, pantallas, escritorio y silla bien
# detallados», con el estándar de la skill vehiculo-detallado: texturas
# reales, nada pintado). Todas CC0 de ambientCG (https://ambientcg.com),
# descargas 2K-JPG en ~/.cache/nations-texturas (no van en el repositorio).
#
#     python3 tools/blender/texturas_sala.py
#
# Deja cada material en assets/base/materiales/<nombre>/ con el formato de
# batalla/dream/biblioteca_pbr.lua: albedo.jpg (sRGB), normal.jpg (OpenGL),
# material.jpg (R metálico, G rugosidad, B oclusión) y material.lua. El
# juego los pone por nombre a las piezas del .glb del almacén.
#
# El color de cada uno es el de la pieza real (laminado gris claro, plástico
# negro mate, tela antracita...): se toma la textura real y se lleva su
# mediana al color buscado, conservando la variación de la propia foto
# (la regla de la skill: la mediana de la textura real, no un color liso).

import io
import os
import urllib.request
import zipfile

import numpy as np
from PIL import Image

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DESTINO = os.path.join(RAIZ, 'assets', 'base', 'materiales')
CACHE = os.path.expanduser('~/.cache/nations-texturas')
TAMANO = 1024  # px de cada textura (una baldosa de `metros` en el juego)

# nombre: (asset de ambientCG, color lineal buscado o None, rugosidad
# (factor sobre la de la textura), metálico, fuerza de la normal)
MATERIALES = {
    # Tablero de laminado gris claro de la mesa.
    'salaLaminado': ('Plastic011', (0.42, 0.44, 0.45), 1.0, 0.0, 0.6),
    # Plástico negro mate texturizado: monitor, teclado, ratón, torre, silla.
    'salaPlastico': ('Plastic012A', (0.022, 0.023, 0.026), 1.45, 0.0, 0.8),
    # Tela del asiento, antracita.
    'salaTela': ('Fabric030', (0.03, 0.033, 0.038), 1.0, 0.0, 0.35),
    # Malla del respaldo: tejido fino y abierto, negro.
    'salaMalla': ('Fabric082A', (0.015, 0.016, 0.018), 1.0, 0.0, 1.4),
    # Aluminio cepillado de la base de la silla y las patas de la mesa.
    'salaAluminio': ('Metal009', None, 0.9, 1.0, 0.5),
    # Goma de las ruedas, los pies y la alfombrilla.
    'salaGoma': ('Rubber004', (0.02, 0.02, 0.022), 1.0, 0.0, 0.6),
}


def bajar(asset):
    os.makedirs(CACHE, exist_ok=True)
    zipRuta = os.path.join(CACHE, asset + '_2K-JPG.zip')
    if not os.path.exists(zipRuta):
        url = 'https://ambientcg.com/get?file=%s_2K-JPG.zip' % asset
        peticion = urllib.request.Request(url, headers={'User-Agent': 'texturas-sala'})
        with urllib.request.urlopen(peticion) as r, open(zipRuta, 'wb') as f:
            f.write(r.read())
    archivos = {}
    with zipfile.ZipFile(zipRuta) as z:
        for nombre in z.namelist():
            for clave in ('Color', 'NormalGL', 'Roughness', 'Metalness', 'AmbientOcclusion'):
                if nombre.endswith('_%s.jpg' % clave):
                    archivos[clave] = Image.open(io.BytesIO(z.read(nombre))).convert('RGB' if clave in ('Color', 'NormalGL') else 'L')
    return archivos


def lineal(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def escalar(imagen):
    return imagen.resize((TAMANO, TAMANO), Image.LANCZOS)


def hacer(nombre, asset, color, rugosidad, metalico, fuerzaNormal):
    t = bajar(asset)
    carpeta = os.path.join(DESTINO, nombre)
    os.makedirs(carpeta, exist_ok=True)
    albedo = lineal(np.asarray(escalar(t['Color']), dtype=np.float64) / 255)
    if color is not None:
        mediana = np.median(albedo.reshape(-1, 3), axis=0)
        # Solo la variación de luz de la foto (0,85-1,15), con el color buscado.
        luz = albedo.mean(axis=2) / max(np.median(albedo.mean(axis=2)), 1e-4)
        luz = np.clip(1 + (luz - 1) * 0.5, 0.85, 1.15)
        albedo = luz[..., None] * np.array(color)[None, None, :]
        print(nombre, 'mediana original', np.round(mediana, 3), '→', color)
    Image.fromarray((srgb(albedo) * 255 + 0.5).astype(np.uint8)).save(os.path.join(carpeta, 'albedo.jpg'), quality=92)
    # Normal: de vuelta a [-1, 1], fuerza en x e y, renormalizada.
    n = np.asarray(escalar(t['NormalGL']), dtype=np.float64) / 255 * 2 - 1
    n[..., 0] *= fuerzaNormal
    n[..., 1] *= fuerzaNormal
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n + 1) / 2 * 255 + 0.5).astype(np.uint8)).save(os.path.join(carpeta, 'normal.jpg'), quality=95)
    rug = np.asarray(escalar(t['Roughness']), dtype=np.float64) / 255 if 'Roughness' in t else np.full((TAMANO, TAMANO), 0.6)
    rug = np.clip(rug * rugosidad, 0.05, 1)
    met = np.asarray(escalar(t['Metalness']), dtype=np.float64) / 255 if 'Metalness' in t else np.full((TAMANO, TAMANO), metalico)
    ao = np.asarray(escalar(t['AmbientOcclusion']), dtype=np.float64) / 255 if 'AmbientOcclusion' in t else np.ones((TAMANO, TAMANO))
    mat = np.stack([met, rug, ao], axis=2)
    Image.fromarray((mat * 255 + 0.5).astype(np.uint8)).save(os.path.join(carpeta, 'material.jpg'), quality=95)
    with open(os.path.join(carpeta, 'material.lua'), 'w') as f:
        f.write('-- Generado por tools/blender/texturas_sala.py (ambientCG %s, CC0): no editar a mano.\n' % asset)
        f.write('return {\n    roughness = 1,\n    metallic = 1,\n}\n')
    print(nombre, asset, 'rugosidad media %.2f' % rug.mean(), 'metálico %.2f' % met.mean())


if __name__ == '__main__':
    for nombre, datos in MATERIALES.items():
        hacer(nombre, *datos)

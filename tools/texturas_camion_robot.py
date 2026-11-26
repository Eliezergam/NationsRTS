# Materiales propios del camión de misiles con robot conductor (el dueño,
# 21-nov: la copia pública va sin nada del pack de Synty; antes los misiles y
# la baliza usaban `unidadCamion4`, horneado con el atlas de Synty). Van a la
# biblioteca de materiales de los robots (assets/almacen/materiales_robot,
# batalla/dream/biblioteca_pbr.lua), con el nombre que traen las piezas del
# .glb (tools/blender/misil_camion.py, camion_robot_exportar.py):
#
#   camionMisil   pintura verde militar de camuflaje en tres tonos sobre la
#                 chapa real: la máscara del camuflaje es procedural (ruido
#                 periódico, se repite sin costura) y la chapa, de Poly Haven
#                 (metal_plate_02, CC0): su luminancia varía el color y su
#                 rugosidad y su normal van debajo de la pintura. La imagen
#                 cubre LADO_M x LADO_M metros (las UV del misil están en
#                 metros / LADO_M).
#   camionBaliza  lente ámbar de la baliza y de las luces del chasis, que
#                 brilla sola (emision.png), con la misma chapa debajo.
#
# Fuentes y licencias: assets/almacen/materiales_robot/LICENCIAS.md.
#
#     python3 tools/texturas_camion_robot.py

import os

import numpy as np
from PIL import Image

TEXTURAS = os.path.expanduser('~/NationsRTS-assets/robots/texturas')
RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SALIDA = os.path.join(RAIZ, 'assets', 'almacen', 'materiales_robot')

LADO = 2048  # px de la imagen del camuflaje
LADO_M = 4.0  # m que cubre (misil_camion.py usa el mismo número)
CHAPA_M = 1.0  # m que cubre una vez la chapa (como en los robots)

# Camuflaje (sRGB): verde militar de base, manchas de oliva oscuro y de caqui.
BASE = (108, 120, 76)
OSCURO = (64, 76, 46)
CAQUI = (142, 136, 96)
CORTE_OSCURO = 0.35  # fracción del ruido por debajo: oliva oscuro
CORTE_CAQUI = 0.82  # por encima: caqui
BORDE_PX = 1.5  # ancho del borde suavizado de cada mancha (px)
RUGOSIDAD = 0.55
METALICO = 0.1
FUERZA_NORMAL = 0.35

BALIZA = (240, 158, 46)  # ámbar (sRGB), el de la baliza de antes
BALIZA_EMISION = (250, 204, 80)
LADO_BALIZA = 256


def chapa(nombre, modo, lado, metros):
    """La imagen de la chapa repetida para cubrir `metros` m en `lado` px."""
    imagen = Image.open(os.path.join(TEXTURAS, nombre)).convert(modo)
    tesela = round(lado * CHAPA_M / metros)
    imagen = imagen.resize((tesela, tesela), Image.LANCZOS)
    mosaico = Image.new(modo, (lado, lado))
    for x in range(0, lado, tesela):
        for y in range(0, lado, tesela):
            mosaico.paste(imagen, (x, y))
    return mosaico


def ruidoPeriodico(lado, semilla):
    """Ruido de 0 a 1 que se repite sin costura (filtrado en frecuencia):
    manchas de 0,5 a 1,5 m en una imagen de LADO_M m."""
    azar = np.random.default_rng(semilla)
    f = np.fft.fftfreq(lado) * lado / LADO_M  # ciclos por metro
    fx, fy = np.meshgrid(f, f)
    radio = np.sqrt(fx * fx + fy * fy)
    amplitud = np.where(radio > 0, np.maximum(radio, 1e-9) ** -1.6, 0) * np.exp(-(radio / 2.2) ** 2)
    fase = azar.uniform(0, 2 * np.pi, (lado, lado))
    campo = np.real(np.fft.ifft2(amplitud * np.exp(1j * fase)))
    # Al rango 0-1 por percentiles: la fracción de cada tono es la del corte.
    orden = np.argsort(campo, axis=None)
    rango = np.empty(campo.size)
    rango[orden] = np.linspace(0, 1, campo.size)
    return rango.reshape(campo.shape), campo


def mascara(campo, rango, corte):
    """1 donde el ruido pasa de `corte` (en fracción), con el borde suavizado
    BORDE_PX px según la pendiente del ruido."""
    umbral = np.quantile(campo, corte)
    gy, gx = np.gradient(campo)
    pendiente = np.sqrt(gx * gx + gy * gy) + 1e-12
    distancia = (campo - umbral) / pendiente
    return np.clip(distancia / BORDE_PX + 0.5, 0, 1)


def guardarFactores(carpeta, comentario):
    with open(os.path.join(carpeta, 'material.lua'), 'w') as archivo:
        archivo.write('-- Generado por tools/texturas_camion_robot.py: no editar a mano.\n')
        archivo.write('-- %s\n' % comentario)
        archivo.write('return {\n    roughness = 1,\n    metallic = 1,\n}\n')


def mapaMaterial(lado, metros, rugosidad, metalico):
    rug = np.asarray(chapa('metal_plate_02_rough.jpg', 'L', lado, metros), dtype=np.float64) / 255
    lo, hi = max(0.0, rugosidad - 0.12), min(1.0, rugosidad + 0.12)
    g = lo + (hi - lo) * rug
    r = np.full((lado, lado), metalico)
    b = np.ones((lado, lado))
    return Image.fromarray((np.dstack((r, g, b)) * 255 + 0.5).astype(np.uint8), 'RGB')


def mapaNormal(lado, metros, fuerza):
    nor = chapa('metal_plate_02_nor.jpg', 'RGB', lado, metros)
    plana = Image.new('RGB', (lado, lado), (128, 128, 255))
    return Image.blend(plana, nor, fuerza)


def luminanciaChapa(lado, metros):
    """Variación leve (0,9-1,08) de la luminancia de la chapa real, como en
    los robots (tools/texturas_robots.py)."""
    luz = np.asarray(chapa('metal_plate_02_diff.jpg', 'L', lado, metros), dtype=np.float64)
    luz = (luz - luz.min()) / max(1.0, luz.max() - luz.min())
    return 0.9 + 0.18 * luz


def aLineal(c):
    c = np.asarray(c, dtype=np.float64) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def aSrgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)


def hacerMisil():
    carpeta = os.path.join(SALIDA, 'camionMisil')
    os.makedirs(carpeta, exist_ok=True)
    rango, campo = ruidoPeriodico(LADO, 21)
    oscuro = mascara(-campo, rango, 1 - CORTE_OSCURO)
    # El caqui, con otro ruido (manchas que no siguen a las oscuras) y solo
    # fuera del oliva oscuro.
    rango2, campo2 = ruidoPeriodico(LADO, 1121)
    caqui = mascara(campo2, rango2, CORTE_CAQUI) * (1 - oscuro)
    color = aLineal(BASE)[None, None, :] * (1 - oscuro - caqui)[..., None]
    color = color + aLineal(OSCURO)[None, None, :] * oscuro[..., None]
    color = color + aLineal(CAQUI)[None, None, :] * caqui[..., None]
    color = color * luminanciaChapa(LADO, LADO_M)[..., None]
    albedo = (aSrgb(color) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(albedo, 'RGB').save(os.path.join(carpeta, 'albedo.png'))
    mapaMaterial(LADO, LADO_M, RUGOSIDAD, METALICO).save(os.path.join(carpeta, 'material.png'))
    mapaNormal(LADO, LADO_M, FUERZA_NORMAL).save(os.path.join(carpeta, 'normal.png'))
    guardarFactores(carpeta, 'Camuflaje de los misiles del camión robot: %g x %g m por imagen.' % (LADO_M, LADO_M))
    print('camionMisil', 'oscuro %.2f caqui %.2f' % (oscuro.mean(), caqui.mean()))


def hacerBaliza():
    carpeta = os.path.join(SALIDA, 'camionBaliza')
    os.makedirs(carpeta, exist_ok=True)
    lado = LADO_BALIZA
    color = aLineal(BALIZA)[None, None, :] * luminanciaChapa(lado, 1.0)[..., None]
    Image.fromarray((aSrgb(color) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(carpeta, 'albedo.png'))
    Image.new('RGB', (lado, lado), BALIZA_EMISION).save(os.path.join(carpeta, 'emision.png'))
    mapaMaterial(lado, 1.0, 0.3, 0.0).save(os.path.join(carpeta, 'material.png'))
    mapaNormal(lado, 1.0, 0.15).save(os.path.join(carpeta, 'normal.png'))
    guardarFactores(carpeta, 'Lente ámbar de la baliza y de las luces del chasis del camión robot.')
    print('camionBaliza')


hacerMisil()
hacerBaliza()

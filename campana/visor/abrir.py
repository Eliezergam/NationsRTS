"""Abre el visor del mapa de campaña con el juego montado alrededor.

    python3 campana/visor/abrir.py                      # ventana
    python3 campana/visor/abrir.py --captura a.png 0,0,450,0 ...   # sin pantalla
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def abrir():
    carpetaVisor = Path(__file__).resolve().parent
    carpetaJuego = carpetaVisor.parents[1]
    argumentos = sys.argv[1:]
    captura = '--captura' in argumentos
    if captura:
        indice = argumentos.index('--captura') + 1
        argumentos[indice] = str(Path(argumentos[indice]).resolve())
    with tempfile.TemporaryDirectory(prefix='nations-mapa-campana-') as temporal:
        carpetaTemporal = Path(temporal)
        for origen in carpetaJuego.iterdir():
            if origen.name not in ('main.lua', 'conf.lua'):
                (carpetaTemporal / origen.name).symlink_to(origen)
        for nombre in ('main.lua', 'conf.lua'):
            (carpetaTemporal / nombre).symlink_to(carpetaVisor / nombre)
        entorno = os.environ.copy()
        if captura:
            entorno['SDL_VIDEODRIVER'] = 'offscreen'
        resultado = subprocess.run(['love', str(carpetaTemporal), *argumentos], cwd=carpetaJuego, env=entorno, check=False)
    return resultado.returncode


if __name__ == '__main__':
    raise SystemExit(abrir())

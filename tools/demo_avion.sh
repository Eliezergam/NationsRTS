#!/usr/bin/env bash
# Viaje del avión de carga entre dos sitios (el dueño, 20-nov): en la escena
# de salida (tu capital) la cámara mira a la ciudad y el avión despega y se
# va; en la de llegada (una mina de metal) aparece fuera de la vista y
# aterriza en unos 25 s. Entre una y otra, la carga hace de viaje.
#
#   tools/demo_avion.sh            capital → mina de metal
#   ORIGEN=metal DESTINO=nuestra tools/demo_avion.sh
#   SEMILLA=2026 tools/demo_avion.sh    otro mundo (otra partida)
set -u
cd "$(dirname "$0")/.."
ORIGEN=${ORIGEN:-nuestra}
DESTINO=${DESTINO:-metal}
SEMILLA=${SEMILLA:-42} # otra semilla: otro mundo, como otra partida
TMP=${TMPDIR:-/tmp}/demo_avion
mkdir -p "$TMP"
# Las cámaras las pone la escena según la pista del sitio (batalla/robots/video.lua).
lanzar() {
    local lugar=$1 modo=$2
    env BATALLA_LUGAR="$lugar" AVION_DEMO="$modo" \
        BATALLA_ROBOTS_FOTOS="$TMP:9999" \
        love . "$SEMILLA" --captura 999999 "$TMP/nada.png" 0 0 0.3 1 --batalla preparacion 999999
}
lanzar "$ORIGEN" salida
lanzar "$DESTINO" llegada

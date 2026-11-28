#!/bin/bash
# Material baseLosa: el hormigón de baseHormigon (Poly Haven, CC0) como una
# losa de plataforma de aeropuerto con su junta de dilatación sellada en el
# borde. La textura entera es una losa (se repite cada 5 m): la junta va en
# la textura y no como geometría fina, para que de lejos se funda con los
# mipmaps en vez de hacer rayas.
set -e
cd "$(dirname "$0")/../.."
de=assets/base/materiales/baseHormigon
a=assets/base/materiales/baseLosa
mkdir -p "$a"
# Junta: 8 px de 1024 (4 cm en 5 m), oscura, con el canto algo gastado.
magick -size 1024x1024 xc:white -fill gray30 \
    -draw "rectangle 0,0 1023,3" -draw "rectangle 0,1020 1023,1023" \
    -draw "rectangle 0,0 3,1023" -draw "rectangle 1020,0 1023,1023" \
    -blur 0x1.2 /tmp/junta_losa.png
magick "$de/albedo.jpg" /tmp/junta_losa.png -compose multiply -composite -quality 92 "$a/albedo.jpg"
# Normal: plana en la junta (el sellado).
# Normal con la mitad de relieve (el de la biblioteca, en losas grandes al
# sol, parecía yeso arrugado) y plana en la junta (el sellado).
magick "$de/normal.jpg" \( -size 1024x1024 xc:"rgb(128,128,255)" \) -compose blend -define compose:args=50 -composite /tmp/normal_losa.png
magick /tmp/normal_losa.png \( -size 1024x1024 xc:"rgb(128,128,255)" \) \( /tmp/junta_losa.png -negate \) \
    -compose over -composite -quality 92 "$a/normal.jpg"
rm -f /tmp/normal_losa.png
cp "$de/material.jpg" "$a/material.jpg"
cat > "$a/material.lua" <<'FIN'
-- Hecho por tools/texturas/losa_hormigon.sh desde baseHormigon (Poly Haven,
-- CC0): una losa de 5 m con su junta. material.jpg: R metal, G rugosidad, B oclusión.
return {
    roughness = 1,
    metallic = 1,
}
FIN
rm -f /tmp/junta_losa.png
echo "$a"

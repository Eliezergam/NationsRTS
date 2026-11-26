# Licencias de las texturas de la batalla

Todo lo de `assets/texturas/batalla/` sale de `tools/blender/texturas_batalla.py`
(texturas) y `tools/blender/preview_texturas_batalla.py` (vistas previas). Las
fuentes a 2K se descargan a `~/.cache/nations-texturas/batalla` y no van en el
repositorio.

Todas las fuentes son **CC0 1.0 Universal** (dominio público): uso comercial
libre, sin obligación de atribución (se apunta igual). Comprobado el
2026-09-30 en <https://polyhaven.com/license> y <https://ambientcg.com/license>.

| Material | Uso | Fuente | Autor | Tile | Ajustes propios |
|---|---|---|---|---|---|
| `hierba` | terreno | [ambientCG Grass004](https://ambientcg.com/view?id=Grass004) | ambientCG (Lennart Demes) | 1,4 m | Color fiel; rugosidad +0,5 (venía satinada) |
| `hierbaSeca` | terreno | [Poly Haven leafy_grass](https://polyhaven.com/a/leafy_grass) | Charlotte Baglioni | 2 m | Color fiel salvo el tinte hacia oliva (la fuente sale rosada) |
| `barro` | terreno | [Poly Haven brown_mud_02](https://polyhaven.com/a/brown_mud_02) | Rob Tuytel | 1,3 m | Color fiel |
| `acantilado` | terreno (pendientes) | [ambientCG Rock028](https://ambientcg.com/view?id=Rock028) | ambientCG (Lennart Demes) | 4 m (estimado) | Color fiel |
| `arena` | terreno (orillas, ríos) | [Poly Haven coast_sand_01](https://polyhaven.com/a/coast_sand_01) | Rob Tuytel | 6 m (la fuente mide 15 m) | Color fiel |
| `nieve` | terreno (alturas) | [Poly Haven snow_01](https://polyhaven.com/a/snow_01) | Rob Tuytel | 2 m | Color fiel |
| `tierraPedregosa` | terreno (seco) | [Poly Haven dry_ground_rocks](https://polyhaven.com/a/dry_ground_rocks) | Rob Tuytel | 4 m | Color fiel |
| `roca` | peñascos y piedras | [ambientCG Rock060](https://ambientcg.com/view?id=Rock060) | ambientCG (Lennart Demes) | 2 m (estimado) | Color fiel |
| `corteza` | troncos | [Poly Haven bark_brown_02](https://polyhaven.com/a/bark_brown_02) | Rob Tuytel | 1 m | Color fiel |
| `asfalto` | caminos y ciudades | [Poly Haven asphalt_02](https://polyhaven.com/a/asphalt_02) | Rob Tuytel | 3 m | Color fiel |
| `hojas` | copas (tarjetas con alfa) | [ambientCG Leaf001](https://ambientcg.com/view?id=Leaf001) | ambientCG (Lennart Demes) | 1 m por tarjeta | Racimo propio: 229 copias de la hoja escaneada (anverso y reverso), giradas y escaladas, con la normal girada, variación de tono, sombra de las hojas de encima y color extendido fuera del alfa (sin halos en los mipmaps). Color fiel de la hoja |

Alturas (`altura.jpg`, en la carpeta de cada material de terreno y de
`roca`, y en `1k/` y `512/`): las saca `tools/blender/alturas_batalla.py`
del mapa de desplazamiento de la misma fuente (Poly Haven `_disp_2k.jpg`,
ambientCG `_Displacement.jpg`; CC0), llevado a todo el rango (percentiles
0,5 y 99,5). Las usan la mezcla por altura y el parallax del suelo
(`batalla/dream/terreno_pbr.lua`).

Color fiel a la fuente (el dueño, 2026-10-01: «no sé para qué lavas las
imágenes»): desde ese día no se baja la saturación ni el contraste, no se
aplanan las manchas grandes de luz y no se rebajan el brillo, el relieve ni la
oclusión. Solo quedan las correcciones reales de la tabla. La cohesión con los
modelos Synty la dan la luz y el mapeo tonal de la batalla. El entonado de
antes (saturación de 0,72 a 0,95, contraste de 0,8 a 0,95 y manchas de luz
aplanadas por FFT) sigue en `materiales` de `texturas_batalla.py` y se repite
con `--apagado`. Medido en los albedos de 1K: el entonado quitaba entre un 5 y
un 23 % de saturación y entre un 8 y un 29 % de contraste.

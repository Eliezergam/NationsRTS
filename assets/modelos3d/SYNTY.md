# Lo que queda del pack Synty en assets/modelos3d

En el juego solo hay robots y lo hecho por el estudio (el dueño, 21-nov). Los
vehículos con tripulación humana sacados del pack **SIMPLE Military** de Synty
(los tanques T-55, T-72B, M1A1, K2 y `tanque_synty`, el BM-21, el HIMARS y el
camión Scud de cabina humana `camion_misiles_synty4` con su `misil_synty4`)
se quitaron ese día; su historia, sus contratos y sus pruebas están en git
(antes del commit que los quita).

Queda de ellos:

- `materiales/unidadCamion4`, `unidadCamion4Cristal` y `unidadCamion4Lod3`:
  el atlas horneado del camión de 4 misiles (camuflaje, metal, goma) a partir
  del atlas Synty del chasis. Los usa el camión de misiles con robot conductor
  (`assets/batalla/robots/camionMisiles.glb`, tipo `camionMisiles` de
  robots/nucleo.lua), que se hizo a partir de aquel camión sin su cabina.
- `tools/blender/camion_misiles_synty4.blend` y los scripts
  `tools/blender/camion_misiles_*.py`: la fuente del camión de antes (no se
  carga en el juego).

Licencia de Synty: uso en juegos del comprador; no redistribuir el pack
suelto. Por eso `materiales/` no va en la copia pública
(`tools/publico/excluir.txt`).

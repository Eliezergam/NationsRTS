# Licencias del kit del modo Base

Todo lo de `assets/base/` sale de `tools/blender/kit_base.py` (geometría) y
`tools/blender/texturas_base.py` (texturas). Las texturas de origen se
descargan a `~/.cache/nations-texturas` y no van en el repositorio.

## Texturas CC0 (ambientCG)

Licencia **CC0 1.0 Universal** (dominio público): uso comercial libre, sin
obligación de atribución. Fuente: <https://ambientcg.com>, descargas `1K-JPG`.

| Material | Assets de ambientCG | Qué se toma |
|---|---|---|
| `baseHormigon` | [Concrete034](https://ambientcg.com/view?id=Concrete034), [Concrete040](https://ambientcg.com/view?id=Concrete040) | Color, normal, rugosidad y AO del 034; poros de la altura del 040 |
| `baseChapa` | [CorrugatedSteel005](https://ambientcg.com/view?id=CorrugatedSteel005), [PaintedMetal004](https://ambientcg.com/view?id=PaintedMetal004), [PaintedMetal006](https://ambientcg.com/view?id=PaintedMetal006) | Greca (normal, a media fuerza), acero y AO del 005; máscara de desconchones del 004; manchas de óxido del 006. Pintura oliva propia |
| `baseAcero` | [Metal032](https://ambientcg.com/view?id=Metal032) | Color, normal y rugosidad (subida para que no haga de espejo) |
| `basePeligro` | [Metal032](https://ambientcg.com/view?id=Metal032), [PaintedMetal004](https://ambientcg.com/view?id=PaintedMetal004), [PaintedMetal006](https://ambientcg.com/view?id=PaintedMetal006) | Franjas amarillas y negras propias sobre ese acero, con desconchones y óxido |
| `baseMadera` | [WoodFloor043](https://ambientcg.com/view?id=WoodFloor043) | Color, normal, rugosidad y AO |
| `baseVidrio` | — | Procedural (texturas_base.py), sin fuente externa |

## Atlas de las estaciones (Synty)

`materiales/AtlasSyntyBase/albedo.png` es `Textures_Props.png` del pack
**SIMPLE Military de Synty Studios**, comprado por el dueño
(`assets/source_packs/SIMPLE_Military_SourceFiles.zip`). Licencia de Synty
(uso en juegos del comprador; no redistribuir el pack suelto). Los props que
van dentro de las estaciones (cajas, bidones, cajas de munición y metálicas,
sacos terreros) son mallas de ese mismo pack.

**Cielo del almacén** (`assets/almacen/cielo.hdr`): «Kloofendal 48d Partly Cloudy
(Pure Sky)» de Poly Haven, 1k, CC0 (https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky).
Se ve desde el patio de descarga y por los portones abiertos.

# 3DreamEngine incluido en NationsRTS

Esta copia procede del repositorio oficial de 3DreamEngine:
https://github.com/3dreamengine/3DreamEngine

- Revisión: `bdaa095a38be91107647966851eb3dd5379e0e61`
- Fecha de la revisión: 25 de mayo de 2023
- Licencia: MIT, conservada en `LICENSE`

Se mantiene como dependencia vendorizada para que la comparación `--dream`
sea reproducible y no dependa de una instalación externa.

## Cambios locales

- `extensions/sky/init.lua`: sol y luna más pequeños en el cielo.
- Niebla con distancia de inicio: `dream:setFogStart(distancia)` (unidades de
  3Dream). `shaders/code/fog.glsl` solo cuenta el tramo de rayo más allá de
  `fog_start`, y `render.lua` lo envía con el resto de la niebla. Si no se llama,
  vale 0 y la niebla es la original.
- Sombra del sol (`shaders/light/sun_shadow.lua`, `jobs/sunShadow.lua`,
  `classes/shadow.lua`, `settings.lua`):
  - PCF bilineal de 2 x 2 con el texel real del mapa (el original desplazaba
    1/ancho de pantalla y tramaba por bloques de 2 x 2 píxeles: damero).
  - Sesgo con la normal del vértice y escalable: `dream:setShadowBias(escala)`
    (1 = el original, pensado para 1 unidad = 1 m).
  - `shadow:setCenter(vec3)`: centro de las cascadas (por defecto, la cámara).
  - `dream:setShadowFormat(formato)`: formato de los mapas (por defecto r16f).
  - `shadow.depthRange`: profundidad de las cámaras de sombra (por defecto 100
    unidades, la original); el mapa de campaña (1 unidad = 1 km) la sube con
    el radio de las cascadas (`campana/luz_campana.lua`). Las cámaras de
    sombra se rehacen también cuando cambian el radio de su cascada o esta
    profundidad (el original solo al moverse el centro o el sol).
- Luz del cielo física y oclusión solo en ella (Fase 1 del plan de render,
  `batalla/dream/PLAN-RENDER-UE.md`; el juego pone las texturas en
  `batalla/dream/ibl.lua`, `atmosfera.lua` y `oclusion.lua`):
  - `shaders/inbuilt/PBR.lua`: con `dream:setIrradianceMap(cubo, brdf)` define
    `IBL_FISICO`: difusa = albedo * irradiancia del cubo (E / pi), especular =
    reflejo prefiltrado * (F0 * A + B) de la tabla BRDF (el original multiplicaba
    por el Fresnel de la vista y daba brillo de cielo a lo rugoso de canto), más
    la energía de las dispersiones múltiples y el horizonte del reflejo. Sin
    llamarlo, el código original.
  - `shaders/code/base.glsl`: `ambientOut`, la parte de luz ambiente del color;
    con `AMBIENT_SPLIT` va a un tercer lienzo (`love_Canvases[2]`).
  - `classes/canvases.lua`: lienzo `ambient` (rg11b10f) con
    `dream:setAmbientSplit(true)` y formato de la profundidad lineal con
    `dream:setDepthCanvasFormat` (r32f en la batalla; por defecto r16f).
  - `render.lua`: el tercer lienzo en la pasada opaca; `dream:setAOHook(f,
    uniforms)` sustituye la SSAO por la del juego (`dream.aoTexture`) y envía
    sus uniforms a la imagen final; la niebla solo envía los uniforms que usa
    el sombreador; base de la cámara (`view_*`) para el rayo de cada píxel.
  - `shader.lua`: defines `AMBIENT_SPLIT`, `AO_SPLIT`, `CONTACT_SHADOWS` y
    `FOG_SKY`; el bit 3 del identificador global marca la luz ambiente aparte
    (solo se usaba en la pasada alfa).
  - `shaders/code/final.glsl`: con `AO_SPLIT`, color = ambiente * oclusión +
    (resto) * contacto; la oclusión de media resolución se escala con los
    vecinos de profundidad parecida; con `CONTACT_SHADOWS`, rayo corto hacia el
    sol en la profundidad (`dream:setContactShadows`); el rayo de la niebla sale
    de la base de la cámara (el `viewVec` del vértice no dividía por w y cambiaba
    de signo al dibujar en un lienzo).
  - `shaders/code/fog.glsl`: con `dream:setFogSky(franja)` (`FOG_SKY`), el color
    de la niebla es el del cielo junto al horizonte en el rumbo de la mirada.
  - `settings.lua`: los ajustes anteriores.
- AA temporal (Fase 2 del plan de render; el juego lo hace en
  `batalla/dream/temporal.lua`):
  - `classes/camera.lua`: `camera:setJitter(x, y)` desplaza la proyección
    `x` px a la derecha e `y` px hacia abajo (el cielo también, porque
    `transformProjOrigin` sale de ella). Sin llamarlo, 0 y nada cambia.
  - Lienzo de movimiento, `dream:setMotionMask(true)` (`settings.lua`, con la
    luz ambiente aparte): `classes/canvases.lua` crea `canvases.movil`
    (rgba16f, filtro nearest), `render.lua` lo pone de cuarto lienzo y envía
    `objetoMovil` = 1 en las mallas con `mesh.movil = true`.
    `shaders/code/base.glsl` (`MOTION_MASK`; en `shader.lua`, el bit 3 del
    identificador, el de la luz ambiente aparte) escribe en él cuánto se movió
    el punto desde el cuadro anterior (`desplazaMovimiento`, cero por defecto;
    lo pone un módulo de vértices que conoce la posición anterior, como
    `batalla/dream/piezas_lote.lua`) o 10000 en rojo en lo `movil` sin vector.
    Sin llamarlo, nada cambia.
- Luz rebotada de pantalla (Fase 2 del plan de render; el juego la calcula en
  `batalla/dream/rebote.lua`): `dream:setBounce(true)` (`settings.lua`) define
  `BOUNCE` en la imagen final (`shader.lua`), y `shaders/code/final.glsl` suma
  luz ambiente × `canvas_bounce` (escalado como la oclusión, con su
  `bounce_texel`). Los uniforms llegan con los de `setAOHook`.
- Follaje de dos caras (Fase 3 del plan de render; el juego pone la
  traslucidez de las hojas, las agujas y la hierba en
  `batalla/dream/estilo/recursos.lua`): con `material:setTranslucency(t)`
  (`TRANSLUCENCY`), `shaders/inbuilt/PBR.lua` (`getLight`) suma la luz que
  atraviesa la hoja como el «Two Sided Foliage» de Unreal: albedo × luz (con
  su sombra) × t × 0,5 × un lóbulo GGX de rugosidad 0,6 entre la vista y la
  luz, que solo se ve al contraluz. El original reflejaba la luz por la normal
  cuando llegaba por detrás. `setTranslucency` sigue poniendo el recorte de
  caras a `none`; el juego lo devuelve al suyo.
- Orugas de los tanques (`batalla/dream/oruga.lua`, `orugaBatalla`): módulo de
  sombreador de vértices como `shaders/inbuilt/wind.lua`, pero registrado
  desde el juego (`dream:registerShader` en `batalla/dream/escena.lua`), así
  que no cambia ningún archivo de la librería. Suma a la u de la oruga el
  desplazamiento de cada copia (atributo por copia `InstanceOruga`, que
  engancha `batalla/dream/lote_unidades.lua` sustituyendo el `getMesh` de esos
  lotes, como `batalla/dream/instancias_tono.lua`) y lleva el color, el
  material y la normal hacia su media a lo largo de un eslabón según la
  velocidad (contra el efecto estroboscópico). Usa lo que la librería ya da:
  `VaryingTexCoord` se puede reescribir en `position()` (lo hace el
  `SPRITE_INSTANCING` de `base.glsl`) y el `buildPixel` del sombreador de
  vértices va después del de píxel (`albedo`, `normal`, `TBN` ya puestos).
- Niebla de lo transparente (`shader.lua`, `shaders/code/final.glsl`): con el
  paso alfa en su lienzo (refracciones, el modo de la batalla) cada objeto
  transparente lleva la niebla de su propia distancia (`FOG_ENABLED` en el paso
  alfa) y la imagen final empaña lo opaco antes de componer encima lo
  transparente; el resplandor se empaña con la niebla de lo opaco, como antes.
  El original empañaba lo transparente con la profundidad de lo de detrás: un
  cristal delante del cielo (niebla entera) desaparecía. El juego pone el
  vidrio en `batalla/dream/cristal.lua` (sombreador de mundo `cristalBatalla`).
- Recorte en las cascadas de la sombra del sol (`jobs/sunShadow.lua`,
  `render.lua`): cada cascada descarta lo que queda fuera de los cuatro lados
  de su caja (planos normalizados, en unidades del mundo; `cam.forceFrustumCheck`
  recorta aunque el recorte general esté apagado). El original dibujaba la
  escena entera en cada cascada (unas 4900 mallas por cuadro en el almacén).
- Aviso: `object:clone()` (`classes/object.lua`) le da al clon las piezas del
  modelo y al modelo unas copias nuevas, y copia en profundidad mallas y
  materiales. No se ha tocado (hay código que cuenta con ello); quien agrupe
  copias por su malla guarda el modelo de origen antes de clonar
  (`almacen/objetos/objetos.lua`). Los robots fundidos (`robots/union.lua`)
  agrupan por el nombre del material.

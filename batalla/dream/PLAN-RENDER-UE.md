# Plan: la batalla 3D con el aspecto de Unreal

Referencia: Unreal Engine 5.8 con Lumen, TSR y la luz por defecto (SkyAtmosphere,
SkyLight con captura en tiempo real, DirectionalLight a 49,5° y ExponentialHeightFog),
con nuestros modelos (`ue_ref/render/ue_cerca|media|lejana.png` y sus EXR lineales).

## Qué da a Unreal ese aspecto

Medido en el EXR lineal de `ue_cerca` y en nuestra batalla con las mismas
cámaras (15 m y 22°, 60 m y 35°, 200 m y 50°; sol a 49,5° de altura):

| | Unreal | Nosotros (2026-10-01) |
| --- | ---: | ---: |
| Suelo en sombra / suelo al sol (lineal) | 0,17 | 0,34 |
| Color de la sombra (B/R) | 1,0 (azul y verde del cielo y del suelo) | gris, sin tinte |
| Oclusión en huecos y bajo los vehículos | GTAO, solo en la luz del cielo | SSAO simple que oscurece también el sol |

1. **La luz del cielo es el propio cielo.** El SkyLight captura la atmósfera (y el
   suelo iluminado por el sol en el hemisferio de abajo) y de ahí salen la
   irradiancia difusa y los reflejos prefiltrados por rugosidad (split-sum). Las
   caras en sombra reciben azul desde arriba y verde desde el suelo; las
   superficies de arriba, más luz que las verticales. Nosotros usamos un cielo
   pintado en textura, multiplicado por 0,3, con un desenfoque gaussiano como
   irradiancia.
2. **La oclusión ambiental solo toca la luz del cielo** y es de horizontes (GTAO).
   El sol queda entero, así que el contraste sol/sombra es alto sin aplastar la
   cara iluminada. Las sombras de contacto pegan la sombra a los pies y a las cadenas.
3. **La atmósfera es una sola** para el cielo, la luz del cielo, el color del sol
   (más naranja al atardecer) y la bruma lejana.
4. **TSR**: bordes estables y una imagen fina sin el coste del MSAA.
5. **Exposición automática por histograma** y la curva fílmica (esta ya la tenemos).

## Fases

Coste medido con `batalla/pruebas_rendimiento` (1920 × 1080, sin vsync, RX 6600,
tiempo de GPU con consultas GL). Objetivo: 90 FPS o más en calidad alta, medidos con el 1 % peor.

| Fase | Qué | Coste esperado (alta) | Baja / media |
| --- | --- | ---: | --- |
| 1 | Atmósfera física de Hillaire (tablas de transmitancia, multidispersión y vista del cielo). La luz del cielo sale de un cubo capturado de ella: irradiancia difusa, especular GGX prefiltrado y tabla BRDF propia. GTAO solo en la luz del cielo y sombras de contacto del sol. Todo en el sombreador PBR común: suelo, rocas, árboles y vehículos | GPU +0,8 a 1,5 ms; el cielo y su cubo se rehacen solo cuando el sol se mueve (<0,3 ms esa vez) | baja: IBL sí, sin GTAO ni contacto; media: GTAO de 1 corte, sin contacto |
| 2 | AA temporal (jitter, reproyección, recorte por vecindad, afilado suave) frente al MSAA 4 | Sin MSAA: −1 a −2 ms. TAA: +0,6 a 1 ms | baja: FXAA; media: TAA sin afilado |
| 3 | Materiales de cerca: normales de detalle y mezcla por altura (hierba, tierra y roca) o parallax en el suelo, microsombras, triplanar con detalle en rocas y montañas, translucidez y viento en las hojas | +0,5 a 1,5 ms, solo hasta ~70 m | se apagan por distancia o por calidad |
| 4 | Niebla de altura con perspectiva aérea de la misma atmósfera, exposición automática por histograma y, si cabe, nubes con sombra | +0,3 a 0,8 ms | baja: niebla actual y exposición fija |

Cada fase se mide antes y después con las mismas cámaras: contraste sombra/sol
en lineal (objetivo ≈ 0,15 a 0,17), saturación, nitidez (varianza del laplaciano
en el suelo), FPS medios y del 1 % peor en los encuadres d, f, g, h e i.
Sin lavar la imagen: no se baja la saturación ni el contraste y no se añade
bruma de estilo.

## C y C++, si el rendimiento lo pide

Regla: de cerca no se toca la calidad; se ahorra en lo lejano y en la CPU.
Lo medido hoy (calidad alta, 1920 × 1080) apunta a la CPU, no a la GPU:

| Medida | Valor |
| --- | ---: |
| GPU por cuadro | 3,2 a 7,9 ms |
| CPU por cuadro (media) | 3,6 a 7,9 ms |
| Relleno de vegetación (selección y lotes, Lua) | 1,7 a 4,6 ms de media |
| Cuadros lentos | 14 a 30 ms, casi todo en `dibujar` (hasta 18,8 ms) |
| Memoria de Lua durante la medida | oscila entre 180 y 365 MB (recolector) |

El 1 % peor (46 a 87 FPS) lo marcan esos picos de CPU. Candidatas, por orden:

1. **Selección y relleno de la vegetación y de los impostores** (`vegetacion.lua`):
   recorte por celdas, elección de nivel de detalle y escritura de los búferes de
   instancias. Ya usa FFI; en C se haría en un hilo sin pausar Lua ni producir basura.
2. **Lotes de unidades y matrices** (`lote_unidades.lua`, `escena.lua:dibujarUnidades`):
   tablas por cuadro, ahora generan basura y llaman al recolector.
3. **Recorrido de la escena de 3Dream** (`render.lua`, `scene`): orden por
   sombreador, material y reflejo, y envío de uniforms. En C++ (módulo nativo
   o en el propio LÖVE) se agrupan los dibujos y se usa instancing indirecto.

Antes de tocar C se mide con el perfilador (`PERFIL=Fi1`) el tramo concreto. La
Fase 1 es GLSL y no necesita C.

## Resultado de la Fase 1 (2026-10-01)

Ver la sección «Luz del cielo física» de `README.md`. En resumen: el cielo pone
el 13–15 % de la luz del suelo al sol (antes, el 34–38 %; Unreal, el 17 %), y
cuesta unos +1 ms de GPU por cuadro en calidad alta. Atmósfera frente a
panorama HDRI: el coste por cuadro es el mismo. El HDRI carga en 0,3 s, ocupa
20 MB en disco y 85 MB de vídeo, no sigue la hora y deja la sombra en 0,20–0,25
y lo lejano más blanco. Se queda la atmósfera; el HDRI queda como opción.

## Resultado de la Fase 2 (2026-10-01)

Ver «AA temporal» y «Luz rebotada» en `README.md`. En resumen:

- **AA temporal** (media y alta; baja, FXAA): con la cámara quieta queda más
  cerca de la referencia sobremuestreada que el MSAA 4 (error 11,2 frente a
  17,7 junto a la hierba; 4,45 frente a 5,28 con soldados andando), en
  movimiento rápido también (6,27 frente a 6,49) y la hierba parpadea un 61 %
  menos en un paneo lento. La pasada cuesta 0,53 ms; en esta GPU el MSAA 4
  era barato, así que el cuadro sale de 0 a +0,7 ms (no los −1 a −2 ms
  esperados). Sin vectores de movimiento: las unidades van marcadas.
- **Luz rebotada** (media y alta): la sombra junto a lo iluminado pasa de
  0,107 a 0,144 en el encuadre cercano (Unreal, 0,17), con 0,12 a 0,44 ms.
  Lo que falta hasta 0,17 no es rebote de corta distancia: con más radio no
  cambia.

Ideas para fases siguientes:
- **Efectos con niveles de detalle:** de lejos, las explosiones, el humo y las
  estelas serían una imagen o una secuencia (flipbook) en un billboard. De cerca
  seguirían como ahora.
- **Rehacer el cubo del cielo en varios cuadros:** ahora son 1,6 ms de golpe.

## Resultado de la Fase 3 (2026-10-01)

Ver «Rebotes múltiples» y «Materiales de cerca» en `README.md`. En resumen:

- **Rebotes múltiples:** la luz rebotada lee el cuadro anterior reproyectado
  (con su rebote). Sombra/sol en el encuadre cercano de Unreal: 0,144 → 0,150
  (Unreal, 0,17), +0,05 a 0,09 ms. Lo que falta hasta 0,17 sigue sin ser
  rebote cercano.
- **Materiales de cerca:** mezcla por altura con las alturas reales de las
  texturas, normales de detalle en el suelo, la roca y las montañas, parallax
  del suelo hasta 16 m (alta), translucidez de agujas, hojas y hierba, y viento
  en los vértices. En alta, de +0,4 a +1,2 ms por cuadro según lo cerca que
  esté el suelo; todos los encuadres siguen por encima de 90 FPS de media (el
  más caro, el suelo a 2,5 m, 100 de mediana y 84 en la peor ronda).

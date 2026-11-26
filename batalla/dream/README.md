# Comparación con 3DreamEngine

Esta ruta mantiene intacto el renderizador de batalla actual y activa el
comparador únicamente con `--dream`:

```sh
cd NationsRTS
love . 42 --batalla-vivo 32 8 --dream
```

Para comparar otro lugar del mismo mundo con 5 lanzacohetes por bando:

```bash
love . 42 --dream --batalla-vivo 0 5 53000 4000
```

Las dos coordenadas opcionales están en px del mundo (10 px = 1 m).
Conserva la semilla y los bandos; genera un combate de prueba en campo
abierto, sin trasladar una ciudad ni cambiar la simulación. El rótulo indica
la semilla y el centro en metros. Sin coordenadas conserva el arranque habitual.

Verificación del cambio de lugar (2026-09-27): semilla 42, centro anterior
(-50294,84; 15068,30) px frente a (53000; 4000) px. La firma de 625 muestras
del relieve cambia entre lugares; al repetir el nuevo centro coincide, al
igual que el total de 87.229 plantas. Generación nueva: 2,50 s y 2,38 s sin ventana.
Se comprobó también el arranque visible en pantalla completa.

Cada generación debe conectar las formaciones con al menos un pasillo
transitable. A* busca primero un recorrido por tierra; cuando no existe,
construye un terraplén sobre el agua, elevado en la propia malla del terreno.
La superficie visible y las colisiones usan esa misma geometría. No son
puentes: sus tableros y soportes siguen pendientes.

La generación comprueba el perfil y el ancho útil antes de plantar los
árboles y crear las paredes de las orillas. El camino se distingue por su
centro de tierra despejado. Las unidades forman con acceso al pasillo y lo
siguen hacia el otro bando, comprobando los tramos para no cortar curvas
por agua o árboles. El rótulo muestra cuántas rutas se generaron.

Pruebas independientes del terreno y del avance:

```bash
python3 batalla/pruebas_rutas/ejecutar.py
```

Verificación de rutas (2026-09-27): siete escenarios de terreno, incluidas
las semillas 42/123/7, islas, una ciudad y agua completa; 80 vehículos
conectados por escenario. Determinismo comprobado en procesos independientes,
nueve casos de navegación correctos y cruce físico de 54.225 cuadros a
1/60 s sin posiciones inválidas ni restauraciones. En el lugar nuevo,
el camino mide 2,77 km. La regresión del camión también pasa (27.595
comprobaciones); se completó su suelo simulado con la rejilla de plantas
que necesita el sistema de derribo.

La escena reutiliza la misma semilla, sitio, terreno procedural, tropas,
simulación, cámara y controles. `batalla/dream/conversor.lua` cambia las mallas
del eje Z vertical de NationsRTS al eje Y vertical de 3Dream y conserva los
colores de vértice. Las estelas se dibujan con instancias.

## Visibilidad al mover la cámara

La batalla conserva el recorte de lo que queda fuera de la cámara, pero
comprueba el volumen completo de cada objeto o lote antes de descartarlo:

- `visibilidad.lua` normaliza los seis planos de la cámara para comparar
  distancias y radios en las mismas unidades. El factor fijo del motor
  descartaba geometría todavía visible con el campo de visión de 40°.
- `instancias.lua` calcula el centro de cada pieza con las mismas columnas
  de rotación que recibe el shader. Conserva la esfera local al ampliar el
  buffer y reconstruye el volumen del lote al comenzar cada cuadro,
  incluidas las estelas. Así no mezcla límites locales y de mundo.
- La vegetación incluye la copa y el resto del prototipo en sus límites,
  con su escala e inclinación. Los árboles derribados también quedan
  dentro del volumen de recorte; antes solo se medían las bases.

Son adaptadores de la batalla: la copia de 3DreamEngine queda intacta.
El detalle por distancia de la vegetación se conserva. Las unidades y
los proyectiles siguen simulándose aunque la cámara mire hacia otro lado.

Regresión del dibujo real, comparado con el mismo encuadre sin recorte:

```bash
python3 batalla/pruebas_render/ejecutar.py
```

Regresión en movimiento, con la batalla real de la semilla 42: 17 s de
vuelo por guion (W A S D, Q E, Espacio, Ctrl y giro con el ratón) que cada
10 cuadros compara el cuadro con y sin recorte, y mide los ms por cuadro y
los rehechos de los lotes de vegetación:

```bash
python3 batalla/pruebas_terreno/ejecutar.py vuelo 42 [sin-recorte]
```

Los píxeles sueltos (hasta unos 30 por cuadro, en copas lejanas) no son
huecos: son empates de profundidad que cambian con el orden de dibujo. La
prueba solo falla si el recorte quita una mancha de píxeles vecinos.

## Impactos y cámara

Las balas y los misiles conservan el daño, las partículas y el sonido, pero
no aplican impulsos a los vehículos. Una unidad viva mantiene su marcha u
orden; si estaba parada, la explosión no la desplaza. Las colisiones físicas
con terreno, árboles y otros vehículos siguen activas.

Solo se sacude la mirada cuando el ojo de la cámara está a menos de 120 m
del impacto, contando también la altura. El efecto disminuye con la
distancia y termina en 0,45 s; las salvas tienen una intensidad máxima.
No cambia la posición, el campo de visión ni los ángulos elegidos con los controles.
La misma dirección visual se usa para el dibujo y la selección en ambos
renderizadores.

Comprobación: `python3 batalla/pruebas_lanzamisiles/ejecutar.py` compara
la trayectoria y velocidad físicas de unidades con y sin impactos, tanto
en marcha como paradas. `python3 batalla/pruebas_camara/ejecutar.py` comprueba
la distancia, la altura, el límite de intensidad y el regreso exacto del
encuadre tras la sacudida.

Verificación del 2026-09-27: ambas pruebas y luacheck del juego sin librerías
externas pasan. Se inspeccionaron `impacto-sin-empuje-durante.png` y
`impacto-sin-empuje-despues.png` en `~/.local/share/love/nationsrts/`, con un
misil real de la semilla 123 y cinco lanzadores por bando. El rótulo marcó
129 FPS en las capturas a 1280 × 720; al guardar las imágenes, la muestra
final bajó a 46 FPS. Había Blender trabajando simultáneamente: estas cifras
no son una comparativa de rendimiento. Generación: 3,87 s. No se midió una
partida completa ni se repitió el benchmark de 40 contra 40 en esta tarea.

## Cámara libre

- Mantener el botón derecho y mover el ratón gira desde la posición del
  observador, con respuesta directa y sin inercia al soltar. Admite vueltas
  completas y mirar casi verticalmente arriba o abajo, sin invertir los ejes.
- W/S y la rueda avanzan o retroceden hacia donde se mira, incluida la altura.
  A/D se desplazan a los lados de la vista. La rueda recorre 16 m por paso;
  el campo de visión sigue fijo en 40° y no hay zoom.
- Mantener Shift (izquierdo o derecho) multiplica por tres la rapidez de
  WASD, Espacio, Ctrl y el recorrido de la rueda. Al soltar vuelve a la rapidez normal;
  la sensibilidad del ratón no cambia. Shift+clic conserva la selección múltiple.
- Mantener Espacio eleva la cámara verticalmente; Ctrl (izquierdo o derecho)
  la baja sin cambiar la mirada. Al soltar se detiene; Espacio y Ctrl juntos
  se cancelan. P conserva la pausa del combate.
- El techo es **31,7 m de altitud sobre el nivel del mar**, fijo en todo el mapa:
  no aumenta sobre una montaña. Todas las entradas respetan ese máximo.
  Se conserva el margen mínimo de 6 m sobre suelo/agua; las laderas donde no
  cabe la cámara bajo el techo bloquean su avance. Un encuadre inicial sobre
  una cumbre se recoloca en un punto cercano que sí deje espacio.
- El rótulo de depuración muestra primero la altitud y su techo de 31,7 m;
  después, la altura vertical sobre el suelo/agua. Ambas están en metros con
  un decimal (10 px = 1 m). También indica la rapidez activa, ×1 o ×3.
- El límite del mapa restringe la posición del observador. Mirar fuera del
  límite no mueve la cámara. Al desplazarse se comprueba el terreno para no
  atravesarlo; mirar no activa correcciones de altura.
- El botón derecho captura el movimiento relativo para que los bordes de la
  pantalla no corten el giro. Soltarlo, pulsar Escape o cambiar de ventana
  libera el cursor. El clic izquierdo sigue seleccionando unidades.

`python3 batalla/pruebas_camara/ejecutar.py` comprueba la posición del ojo,
la transformación de 3Dream y el oyente de audio, además del movimiento 3D,
los límites y la entrada relativa del ratón.

Verificación del 2026-09-27: 87.014 comprobaciones de cámara correctas a
30/60/144 FPS, 603 pruebas generales sin fallos y luacheck sin avisos en el
código del juego. Se revisaron `camara-fps-inicio.png`, `camara-fps-arriba.png`,
`camara-fps-giro.png` y `camara-fps-recorrido.png` en el directorio de guardado
`nationsrts` de LÖVE. La captura usa los callbacks de `main.lua`, semilla 42,
5 lanzadores por bando y los soldados existentes. La ejecución terminó a
105 FPS a 1280 × 720; es una muestra de comprobación, no un benchmark. El
ratón y el teclado se inyectaron por código; falta la valoración de comodidad
del jugador con su ratón físico.

Verificación del ascenso, descenso y techo global: Espacio, ambos Ctrl y
ambos Shift a 30/60/144 FPS, todas las entradas de movimiento, giro inmóvil
al alcanzar el máximo, pendientes, agua y bloqueo ante montañas altas.
Las capturas `camara-ctrl-descenso.png` y `camara-techo-global.png` del juego
real muestran altitudes de 18,7 y 31,7 m. En la segunda, el despeje local es
24,8 m: el techo permanece fijo aunque cambie el suelo. Espacio no pausa
la pelea. La entrada se comprobó por código con los callbacks reales.

## Imagen: luz, sombra, curva tonal y bruma

Pasada de nitidez del 2026-10-01, medida a 1920 × 1080 con
`batalla/pruebas_rendimiento` (encuadres f cerca, b media, e lejos y d dentro):

- **Resolución y AA:** 3Dream dibuja a la resolución de la ventana (lienzos de
  1920 × 1080, MSAA 4, sin FXAA ni desenfoque). No había reescalado.
- **Curva tonal** (`tono.lua`): 3Dream no tiene; la escena pasa por un lienzo
  rgba16f y la curva fílmica de Unreal (pendiente 0,88, pie 0,55, hombro 0,26,
  recortes 0 y 0,04). Exposición 2,4 con adaptación parcial a la luz que llega
  (ver «Luz del cielo física»). Sin nitidez añadida.
- **Luz** (`luz.lua`): ver «Luz del cielo física». Sin resplandor: no se veía y
  costaba 0,4 ms.
- **Sombra del sol** (`luz.lua` y cambios locales de `lib/3DreamEngine`, ver su
  `ORIGEN.md`): sesgo a escala de 1 unidad = 10 m, PCF bilineal sin tramado,
  mapas r32f y cascadas centradas por delante del ojo hasta `calidad.sombra`
  (200 m en alta).
- **Bruma:** empieza a 250 m (`setFogStart`); su color es el del cielo junto al
  horizonte en cada rumbo.
- **Texturas:** color fiel a la fuente (`tools/blender/texturas_batalla.py`);
  anisotropía 8 (la 16 costaba ~2,3 ms y no ganaba nitidez medible).

| Encuadre | FPS medio | Varianza del laplaciano (suelo) | Saturación |
| --- | ---: | ---: | ---: |
| cerca | 174 -> 163 | 284 -> 735 | 0,26 -> 0,39 |
| media | 164 -> 154 | 154 -> 395 | 0,22 -> 0,37 |
| lejos | 172 -> 158 | 238 -> 488 | 0,32 -> 0,28 |
| dentro | 147 -> 135 | 915 -> 1928 | 0,20 -> 0,26 |

Medianas de cuatro rondas alternas; el ruido entre rondas es de ±15 FPS.

## Luz del cielo física (Fase 1 de `PLAN-RENDER-UE.md`)

- `atmosfera.lua`: atmósfera de Hillaire, como el Sky Atmosphere de Unreal. De
  ella salen el cielo, el color del sol y la luz del cielo. Los aerosoles están
  a ×12 de los de Unreal (`Atmosfera.escalaMie`).
- `ibl.lua`: el cielo, y abajo el suelo iluminado, en un cubo. Da el especular
  GGX prefiltrado, la irradiancia, la tabla BRDF y la franja de la niebla. Solo
  se rehace cuando el sol se mueve 0,25°.
- `oclusion.lua`: GTAO solo sobre la luz del cielo y sombras de contacto del
  sol (calidad alta). Baja no tiene oclusión; media no tiene contacto.
- `cielo_hdri.lua`: con `Luz.panorama`, un panorama HDRI sustituye a la
  atmósfera, para comparar. Los panoramas no están en el repositorio.
- Medidas con `batalla/pruebas_rendimiento` (encuadres g, h, i = cámaras de
  Unreal, hora 0,409) y `medir.py`. La parte del cielo en el suelo al sol
  pasa de 0,34–0,38 a 0,13–0,15 (Unreal: 0,17 en la sombra). La saturación
  pasa de 0,36–0,42 a 0,43–0,51. Coste en GPU por pasada, a 1920 × 1080:
  GTAO 0,44 ms (la SSAO de antes, 0,10), contacto 0,23 ms, imagen final
  0,24 ms (antes, 0,09) y pasada principal +0,1 a 0,3 ms. En total, unos
  +1 ms por cuadro. Rehacer el cielo y su cubo cuesta 1,6 ms, solo cuando se
  mueve el sol. «Preparando sombreadores…»: 0,9 s.

## AA temporal (Fase 2 de `PLAN-RENDER-UE.md`)

- `temporal.lua` y `sombreadores/taa.glsl`: en media y alta, el MSAA 4 se
  sustituye por un AA temporal como el TAA/TSR de Unreal. Cada cuadro se
  dibuja desplazado un subpíxel (Halton de 8, `camera:setJitter` de
  `lib/3DreamEngine`); la historia se reproyecta con la cámara anterior y la
  profundidad, se lee con Catmull-Rom, se recorta a la caja de color de los
  vecinos (YCoCg con la curva de Karis) y se mezcla al 8 % (40 % con más de
  3 px de movimiento por cuadro). La reconstrucción del cuadro nuevo es un
  gaussiano estrecho (k = 6) centrado en lo que vio cada vecino.
- Lo que se mueve por su cuenta no tiene vectores de movimiento: los lotes de
  unidades y los misiles van marcados (`mesh.movil`, lienzo r8 de 3Dream con
  `setMotionMask`) y allí el cuadro nuevo pesa el 50 %; la historia también
  se descarta si su profundidad no es la de la superficie de ahora. Sin esto,
  los soldados que andan salían emborronados.
- Con el AA temporal, las texturas del suelo y de los materiales leen un
  mipmap más fino (`TexturasPbr.nitidezMip` = 1, como el sesgo de Unreal con
  TAA/TSR) y alta añade un afilado suave limitado a los vecinos
  (`Tono.afilado` = 0,3). Baja usa FXAA, sin MSAA.
- Cómo se midió (`batalla/pruebas_rendimiento`, 1920 × 1080, semilla 42, hora
  0,409): con la cámara quieta se compara con la misma imagen renderizada a
  3840 × 2160 y reducida (`TAM=3840x2160`), en el suelo de abajo; en
  movimiento, con secuencias (`SECUENCIA=60`, `medir.py mov`): giro de 10°/s y
  avance de 5 m/s para la nitidez, y paneo de 0,5°/s para el parpadeo
  (|L(k+1) − 2 L(k) + L(k−1)| medio).

| Medida | MSAA 4 | AA temporal |
| --- | ---: | ---: |
| Error frente a la referencia 4K, cerca de la hierba (g, quieta) | 17,7 | 11,2 |
| Error frente a la referencia 4K, suelo y soldados (f, quieta) | 5,28 | 4,45 |
| Error frente a la referencia 4K en movimiento (f, 10°/s y 5 m/s) | 6,49 | 6,27 |
| Parpadeo con paneo lento, cerca (g) | 4,60 | 1,78 |
| Parpadeo con paneo lento, cámara alta (f) | 1,68 | 1,30 |
| Pasada principal, GPU (d, f, g, h, i) | 6,47 · 5,31 · 3,27 · 2,45 · 2,35 ms | 5,65 · 5,10 · 2,95 · 2,41 · 2,00 ms |
| Pasada del AA temporal, GPU | — | 0,53 a 0,55 ms |
| Curva tonal con afilado, GPU | 0,14 ms | 0,16 a 0,17 ms |

La varianza del laplaciano ya no sirve para la nitidez con MSAA: la sube el
centelleo de la hierba recortada (la referencia 4K da 3926 en g; el MSAA,
8437; el AA temporal, 1660; Unreal, 871). En esta GPU el MSAA 4 cuesta poco
en la pasada principal, así que en alta el AA temporal sale de 0 a +0,7 ms
de GPU por cuadro (FPS medios de dos rondas: g 230 → 199, h 254 → 239,
d 137 → 137); en baja, el FXAA ahorra 0,7 a 2,1 ms en la pasada principal.

## Luz rebotada (Fase 2 de `PLAN-RENDER-UE.md`)

- `rebote.lua` y `sombreadores/rebote.glsl`: un rebote de pantalla como el de
  Lumen a corta distancia. Es la integral de horizontes de la GTAO (1 o 2
  cortes, 6 pasos, 3 m de radio, a un cuarto de resolución): cada punto que
  sube el horizonte tapa una franja de cielo y aporta su propia luz (el color
  de la escena allí). Sale la irradiancia rebotada respecto a la del cielo
  para la normal del píxel, y la imagen final de 3Dream suma luz ambiente ×
  rebote (= albedo × E / π). Un rebote, intensidad física 1; con 5 u 8 m de
  radio la sombra medida apenas cambia.
- `medir.py` saca la sombra con el sol quitado; con rebote, la sombra junto a
  lo iluminado también pierde luz al quitar el sol, así que se da además con
  el umbral 1,6 («sombra/sol 1,6»).

| Encuadre | Sombra/sol antes | Con rebote | Unreal |
| --- | ---: | ---: | ---: |
| g cerca (15 m) | 0,107 | 0,144 | 0,17 |
| h media (60 m) | 0,119 | 0,123 | — |
| d dentro de la batalla | 0,155 | 0,210 | — |
| f cerca de un vehículo | 0,082 | 0,105 | — |

Coste en GPU: 0,12 a 0,44 ms en alta y 0,09 a 0,26 ms en media; baja no lo
tiene (tampoco tiene oclusión). La saturación no baja (g 0,44 → 0,45).

## Rebotes múltiples (Fase 3 de `PLAN-RENDER-UE.md`)

- `rebote.lua` y `sombreadores/rebote.glsl`: la luz que sale de cada punto ya
  no es la escena de este cuadro sino la imagen del anterior (la historia del
  AA temporal, que lleva su propio rebote), reproyectada con la cámara de
  entonces como en `temporal.lua` (`Temporal:historiaPara`). Cuadro a cuadro
  la luz rebota más de una vez, como en Lumen. Si la profundidad guardada no
  es la del punto (algo que estaba tapado o que se movió por su cuenta: la
  historia la guarda negativa sobre lo móvil), cae fuera de la imagen o hay un
  corte de cámara, se usa la escena de este cuadro (un rebote): sin estelas.
  `MULTIPLE=0` en `batalla/pruebas_rendimiento` lo quita para comparar.
- Medido con `medir.py` (umbral 1,6), mismo árbol, un rebote → múltiples:
  g 0,144 → 0,150 (Unreal, 0,17); h 0,123 → 0,137; d 0,212 → 0,255;
  j 0,167 → 0,182; en k (roca) baja, 0,277 → 0,254, porque la cara al sol
  también recibe más rebote. Saturación igual (g 0,446). La pasada cuesta +0,05 a
  0,09 ms (g, alta: 0,45 → 0,53 ms). En movimiento (giro de 10°/s y 5 m/s),
  el error frente a la referencia 4K en f queda en 6,21 → 6,27.
- En la medida «sin sol», la historia todavía lleva el sol del cuadro
  anterior: la columna «cielo» de `medir.py` sube un poco (g 0,134 → 0,145)
  por eso, no porque el cielo dé más luz.

## Materiales de cerca (Fase 3 de `PLAN-RENDER-UE.md`)

Según `calidad.materiales` (`calidad.lua`): baja, nada (como antes); media,
mezcla por altura, normales de detalle, translucidez y viento; alta, además
el parallax. Todo se apaga con la distancia: de lejos manda el nivel de detalle.

- **Alturas** (`tools/blender/alturas_batalla.py`): `altura.jpg` de cada
  material de suelo y de `roca`, del mapa de desplazamiento de su misma fuente
  CC0. `texturas_pbr.lua` la pone en el alfa del mapa de normales (sin otro
  muestreador) y guarda su media; sin el archivo, alfa 1 y todo como antes.
- **Suelo** (`terreno_pbr.lua`): de cerca, la hierba, la hierba seca, la
  tierra, las piedras y la roca se reparten por altura (la que sobresale gana,
  con un borde de 0,18) y la normal es la de todas las capas con esos pesos;
  de lejos, el reparto de antes. Normal de detalle: la capa dominante a 3,7
  veces su escala. Parallax occlusion mapping (alta) hasta 16 m: de 6 a 12
  pasos y un ajuste lineal, con la altura de la capa dominante. Las normales y
  alturas se leen a la escala principal de cada capa (con la segunda, 2,7
  veces más grande, el relieve de luz salía borroso) y solo de las capas que
  pueden asomar.
- **Rocas y montañas** (`estilo/roca_pbr.lua` y la roca del terreno): triplanar
  con una segunda normal de la misma roca a 3,3 veces su escala, girada,
  sumada con «whiteout»; entera hasta 15 m y nada desde 30 m en las rocas,
  y de 35 a 70 m en la roca del terreno.
- **Translucidez** (`lib/3DreamEngine`, `TRANSLUCENCY`, ver su `ORIGEN.md`):
  agujas 0,6, hojas de los arbustos 0,7 y hierba 0,7 (`Recursos.traslucidez`).
  La luz que atraviesa la hoja sale hacia delante como en el «Two Sided
  Foliage» de Unreal: solo se nota al contraluz. Con el sol bajo (atardecer)
  y la cámara hacia él, las copas se encienden mucho más que a mediodía.
- **Viento** (`viento.lua`): las agujas, los troncos de los pinos, los arbustos
  y la hierba se doblan según la altura sobre su base (de 5 cm en la hierba a
  12 cm en la punta de un pino) en la dirección del viento de las partículas,
  con ráfagas que recorren el campo y un temblor de las hojas. Entero hasta
  50 m y nada desde 80 m. Los parámetros van como constantes en el sombreador
  de cada material, así la sombra se mueve igual que la planta.

Medidas (1920 × 1080, RX 6600, semilla 42, hora 0,409; encuadres nuevos de
`pruebas_rendimiento`: j suelo a 2,5 m, k roca a 6 m, l pino al contraluz).
FPS: medianas de seis rondas alternas en el mismo árbol, sin la Fase 3
(`MATERIALES=ninguno MULTIPLE=0`) → con ella, calidad alta:

| Encuadre | FPS medios | 1 % peor |
| --- | ---: | ---: |
| d dentro de la batalla | 130 → 123 | 54 → 54 |
| f cerca de un vehículo | 143 → 133 | 61 → 52 |
| g UE cerca | 169 → 154 | 62 → 65 |
| j suelo de cerca | 114 → 100 (de 84 a 105) | 50 → 46 |
| k roca de cerca | 159 → 143 | 73 → 64 |
| l pino al contraluz | 267 → 257 | 89 → 73 |

En media (tres rondas): g 191 → 183, j 117 → 98, k 183 → 179. El 1 % peor
lo marcan los picos de CPU de siempre. Coste por pieza en la pasada principal
(alta, j): mezcla por altura y detalle ≈ +0,5 ms, parallax ≈ +0,4 ms,
translucidez y viento por debajo del ruido (±1 ms entre rondas).

| Medida | Antes | Fase 3 |
| --- | ---: | ---: |
| Saturación g · j · k | 0,446 · 0,448 · 0,345 | 0,446 · 0,448 · 0,346 |
| Error frente a su referencia 4K, quieta, mismo par de ejecuciones (g · j) | 11,3 · 7,0 | 12,8 · 8,4 |
| Error frente a la referencia 4K en movimiento (f · j) | 6,21 · 8,35 | 6,27 · 10,29 |
| Parpadeo con paneo lento j (sin viento · con viento) | 1,00 | 1,13 · 1,46 |
| Parpadeo con paneo lento l | 0,375 | 0,398 |

El error sube sobre todo por el viento: la hierba que se mueve no tiene
vectores de movimiento y el AA temporal la recorta a sus vecinos (solo con
viento, g 11,3 → 12,4 y j 7,0 → 7,8). El parpadeo «con viento» incluye el
propio vaivén. Noche (hora 0,81): luminancia media g 40,6 → 39,4, j 45,0 →
43,6, l 15,1 → 15,3. Atardecer: g y j igual; en l, la copa al contraluz se
ilumina (saturación 0,052 → 0,089).

## Resultados

Medición hecha con LÖVE 11.5, ventana de 1280 × 720, VSync desactivado, semilla
42 y captura sin ventana mediante `SDL_VIDEODRIVER=offscreen`. Es una muestra
de una ejecución, no un benchmark estadístico.

| Encuadre | Composición por bando | Actual | 3Dream | Generación actual | Generación 3Dream |
| --- | --- | ---: | ---: | ---: | ---: |
| normal | 40 tanques | 117 FPS | 101 FPS | 0,92 s | 1,17 s |
| cerca | 40 tanques | 80 FPS | 106 FPS | 0,92 s | 1,17 s |
| misiles | 32 tanques + 8 lanzacohetes | 117 FPS | 127 FPS | 0,94 s | 1,19 s |

Las capturas emparejadas ponen el renderizador actual a la izquierda y
3DreamEngine a la derecha:

- `capturas/comparacion_normal.png`
- `capturas/comparacion_cerca.png`
- `capturas/comparacion_misiles.png`

## Qué aporta 3DreamEngine

- Sombras proyectadas por el sol sobre terreno, árboles y vehículos.
- Materiales con rugosidad, metal y canal de emisión, además del color por
  vértice que ya usa NationsRTS.
- Oclusión ambiental, bloom, niebla por distancia y altura, y cielo constante
  o programable.
- Mallas instanciadas para estelas y partículas repetidas.
- Cargador GLB/GLTF. La prueba Blender 5.2.2 → GLB → 3Dream cargó un modelo de
  29 piezas en 0,0054 s sin errores del cargador.

## Problemas encontrados con LÖVE 11.5

- El cambio de eje invierte el orden de los triángulos. Sin corregirlo, el
  descarte de caras elimina el terreno.
- La extensión de cielo dinámico incluida por el proyecto produjo triángulos
  gigantes cerca del horizonte en estos encuadres. El comparador usa el cielo
  constante estable; la extensión queda copiada para investigarla.
- 3DreamEngine interpreta los colores de vértice como lineales. El adaptador
  convierte los colores sRGB del proyecto para evitar una escena lavada.
- La ruta GLB funciona, pero el exportador de Blender avisó que MeshOptimizer
  no estaba instalado. La exportación normal, sin esa compresión opcional,
  funcionó.
- La dependencia usa una variable global `_3DreamEngine` y código de 2023. No
  falló bajo LuaJIT/LÖVE 11.5, pero requiere aislarla si se adopta como motor
  definitivo.

3DreamEngine y su licencia MIT están vendorizados en
`NationsRTS/lib/3DreamEngine/`. `ORIGEN.md` fija la revisión exacta.

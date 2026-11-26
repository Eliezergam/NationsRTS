# Revisión de la interfaz (2026-10-01)

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

> **Estado: PROPUESTA de Lucía para que el dueño elija.** Aquí no se ha cambiado
> nada del juego: es una lista de ajustes para hacer uno a uno, en el orden que
> El dueño quiera. Revisa el estado del repositorio en `7d7c9ed` (interfaz al
> 60 %, texto ×1,5, Opciones y Arsenal al estilo de Warpath, panel de tropas,
> Población, fundidos, zoom del 4 % al 13 % y la «vida» de la interfaz).
>
> Capturas: `diseno/revision-interfaz/` (JPG, sacadas de las PNG del juego).
> Referencias: `diseno/referencias-warpath/` (las 23 imágenes, todas vistas).
> Documento de estilo: `diseno/interfaz-militar.md`.

## Resumen (10 líneas)

1. Lo que más se parece a Warpath ya está bien: Opciones, Opciones generales, Arsenal (Ficha, Producir, Comparar) y la tarjeta del radial.
2. Los fallos graves son de **solapes y textos cortados**, no de estilo: aparecen sobre todo en el mapa con varias cosas abiertas a la vez.
3. A 1280×720 la **ficha de ejército** se rompe: las cifras pisan sus rótulos y el título queda cortado por el borde.
4. El **panel de Recolectores** tapa la columna izquierda y su subtítulo de dos líneas pisa la primera fila.
5. Los **avisos de la derecha** esconden su texto bajo sus propios botones y quedan pegados a «Batallas en curso».
6. Las **etiquetas de los estandartes** se pisan entre sí y con el nombre de la ciudad cuando salen varios grupos juntos.
7. El **radial de la ciudad propia** lleva 7 botones apiñados en un lado; las etiquetas de dos líneas chocan con el hexágono vecino.
8. Tamaños incoherentes: **Perfil** se dibuja a la mitad y deja media pantalla vacía, mientras Opciones y Arsenal la llenan.
9. Con la interfaz al 60 %, las piezas que más se usan (radial, panel de tropas, barra de abajo) quedan en la mitad del tamaño que tienen en Warpath. El dueño decide si se agrandan solo esas.
10. Faltan dos cosas de Warpath que harían el juego más cómodo: noticias siempre a la vista abajo a la izquierda (como el chat) y la barra de botones abajo a la derecha, bajo las tarjetas de tropas.

## Cómo se hicieron las capturas

Todas sin ventana (`SDL_VIDEODRIVER=offscreen`), semilla 12345, modo jugador,
a 1920×1080 y a 1280×720, con los modos de captura de `main.lua`. Ejemplo:

```
SDL_VIDEODRIVER=offscreen love NationsRTS 12345 --jugador --tam 1920x1080 \
    --captura 300 rv_radialpropia_1080.png 0 0 0.10 - radialpropia 60 20
```

Modos usados: mapa a zoom 0,13 / 0,10 / 0,07 / 0,04; `radialpropia`,
`radialrival`, `poblacion`, `explorar`, `sacar` (Envío), `tropas`,
`tropasradial` (panel de tropas con la ficha del ejército), `noticias`,
`perfil`, `opciones`, `general`, `arsenal` con `--arsenal t55 terrestres
ficha|producir|comparar`, `batallas` y la escena `economia` (ventanas de
Fábrica: crear soldados y munición).

Límites de lo capturado:

- **El modo `ficha`** no encontró ningún estandarte a la vista el cuadro 60 y
  sacó solo el mapa; la ficha del ejército sale en `tropasradial`.
- **La pantalla de carga** no tiene modo de captura (mientras carga,
  `love.update` no cuenta cuadros). Las fotos `carga_*.jpg` salen de un
  programa aparte que copia línea a línea `dibujarCarga` de `main.lua` con
  `Tema` real y una fracción fija del 42 %; el aspecto es el del juego, las
  cifras («1 234 de 2 900 comarcas») son de relleno.
- La escena `economia` paró tras la foto 04; Taller y Reparar no se capturaron.
- Las medidas «en px» salen de las constantes del código multiplicadas por la
  escala (`Tema.FACTOR` 0,6 → e = 0,6 a 1080 y 0,48 a 720). Las proporciones
  de Warpath están medidas a ojo sobre las referencias (son de móvil,
  3120×1440): sirven para comparar, no son exactas.

---

## 1. Mapa: barra superior, columna, barra de abajo y medidor de zoom

Capturas: `mapa13_1080.jpg`, `mapa04_1080.jpg`, `mapa13_720.jpg`,
`mapa04_720.jpg`. Referencias: `mapa_hud.jpg`, `zoom_1.5.jpg` a `zoom_5.5.jpg`.

**Está bien**

- Cuatro recursos con icono y cifra grande, dinero en amarillo
  (`interfaz-militar.md` 5.1).
- Los botones de velocidad (II, 1x a 4x) con el activo en amarillo se leen bien.
- La vista lejana (4 %) copia bien a Warpath `zoom_5.5.jpg`: mapa apagado,
  casillas de capas (Territorios, Ejércitos, Yacimientos, Batallas) bajo la
  columna y el aviso «Vista lejana: acércate al 10 % para dar órdenes».
- La placa de lugar arriba al centro («Doquefi · 6 466 habitantes») no estorba.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| M1 | **Alta** | El nombre de la nación del mapa no debe quedar bajo la barra de recursos con zoom alto (ya conocido). Opción: que las etiquetas del mapa no se dibujen en la franja de la barra (se apartan hacia abajo) o que la barra tape con fondo opaco y la etiqueta se mueva. | Ya se sabe que pasa; en estas capturas no salió porque la cámara estaba centrada en la capital. | En Warpath los nombres del mapa nunca pasan bajo la barra. |
| M2 | **Media** | La cifra del medidor de zoom se corta en el borde derecho («13 %» y «4 %» medio fuera, a 1080 y a 720). Meter el medidor 1 margen (16 de diseño) hacia dentro. | Texto cortado. | Warpath no tiene medidor; si se mantiene, que entre entero. |
| M3 | **Media** | Barra superior en la misma posición en todas las pantallas. En el mapa va al centro; en Perfil, Opciones y Arsenal va arriba a la derecha. Opciones: (A) arriba a la derecha también en el mapa, como Warpath, con el día y la velocidad a su izquierda; (B) dejarla al centro y moverla también al centro en las pantallas claras. | Hoy salta de sitio al cambiar de pantalla. | `mapa_hud.jpg` y `perfil.jpg`: arriba a la derecha en las dos. |
| M4 | **Media** | Bloque de la nación arriba a la izquierda más grande y con lo de Warpath: escudo redondo grande con el nivel, poder y coordenadas de la cámara (X, Y). Hoy son 935 y «Nv. 2» en letra pequeña. | Es el acceso al Perfil y apenas se ve. | `mapa_hud.jpg`: avatar con anillo verde, nivel, poder y «X:38179 Y:27349». |
| M5 | **Media** | Icono de «Ataque» de la columna: es una X igual a la de cerrar. Cambiarlo por dos espadas cruzadas o una mira. | Se confunde con «cerrar». | Warpath usa iconos distintos para cerrar y atacar. |
| M6 | **Baja** | «Guardar» en la columna duplica Opciones › Guardado. El dueño decide si se queda (atajo útil) o se quita (columna más limpia). | Duplicado. | La columna de Warpath solo tiene buscar, lista, radar, tareas y correo. |
| M7 | **Baja** | Falta el radar (minimapa redondo) y el botón «Mapa del mundo» en la vista media y lejana. | Orientarse en un mundo infinito. | `zoom_2.5.jpg` a `zoom_5.5.jpg`: radar arriba a la derecha y «Mapa del mundo» abajo a la derecha. |
| M8 | **Baja** | La línea de frontera propia (cian, gruesa) domina la imagen a 10–13 %. Afinarla o bajarle la opacidad cuando no se está en la capa de territorio. | Tapa la costa y los yacimientos que pisa. | `zoom_5.5.jpg`: frontera fina y con brillo suave. |

## 2. Radial de ciudad propia y enemiga, con su tarjeta

Capturas: `radialpropia_1080.jpg`, `radialpropia_720.jpg`,
`detalle_radial_propio_1080.jpg`, `radialrival_espera_1080.jpg`,
`radialrival_1080.jpg`. Referencias: `mapa_hud.jpg`, `radial_ciudad_propia.jpg`.

**Está bien**

- La tarjeta copia bien la de Warpath: icono verde de ubicación, «Capital
  nv. 2», coordenadas, estrella de favorito y filas alternas grises.
- La línea de la tarjeta al edificio, el círculo punteado, el nombre en verde
  (propia) o en rojo (enemiga) con el nivel debajo.
- «Base» destacado en amarillo, como el «Base» de Warpath.
- En la enemiga, lo desconocido dice «Desconocido · Explorar»: no se inventa.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| R1 | **Alta** | La etiqueta del estandarte pisa «Base» (ya conocido). | Solape conocido. | En Warpath el radial se dibuja encima de todo lo del mapa. |
| R2 | **Alta** | Las etiquetas de dos líneas chocan con el hexágono de al lado: «Ejército» toca «Crear soldados» y «Crear soldados» toca «Producir munición» (1080 y 720). Repartir los botones por todo el arco de abajo, de izquierda a derecha, con el mismo hueco, en vez de apiñarlos en la mitad izquierda con «Base» solo a la derecha. | Solape y lectura difícil. | `mapa_hud.jpg`: 5 botones repartidos simétricos bajo el nombre (Emoticones, Reubicar, Regresar, Base, Cajas). |
| R3 | **Alta** | Rótulos cortados en la tarjeta: «Población (reclutabl…», «Balas · obuses · m…», «Poder terr…», «Vida de la …» y el nombre de la nación en la cabecera («Mancomunidad…»). Opciones: (A) tarjeta más ancha (hoy 420 de diseño = 252 px a 1080; la de Warpath ocupa cerca del 23 % del ancho, unas 440 px); (B) rótulos cortos («Reclutables», «Munición»), y en la enemiga «?» con un botón «Explorar» al final, en lugar de repetir «Desconocido · Explorar» en tres filas; (C) la nación en una fila propia. | Lo cortado no se puede leer. | La tarjeta de Warpath no corta nada. |
| R4 | **Media** | Siete botones en la ciudad propia (Ejército, Crear soldados, Producir munición, Población, Arsenal, Regresar, Base). Opción: juntar «Crear soldados» y «Producir munición» en un solo «Producir» que abra una ventana con dos pestañas. Así quedan 6 y caben repartidos. El dueño decide si se juntan. | Menos botones, menos choques. | Warpath tiene 5 botones en el radial propio. |
| R5 | **Media** | Distancia con dos unidades: la placa de arriba dice «a 5 318 m» y la tarjeta dice «5,3 km». Usar siempre km con un decimal a partir de 1 km. | Incoherencia. | — |
| R6 | **Media** | Los hexágonos del radial miden 48 px a 1080 y 38 px a 720 (80 de diseño × 0,6 / 0,48); en Warpath rondan el 4 % del ancho (unos 80 px a 1920). Ver «Decisión 1» abajo. | Es el botón que más se pulsa. | `mapa_hud.jpg`. |
| R7 | **Baja** | Al saltar a una ciudad lejana, durante unos 20 cuadros (≈0,3 s) el suelo sale en color salmón (sin generar) o negro detrás de la ventana de Explorar (`radialrival_1080.jpg`, `explorar_1080.jpg`); con 300 cuadros de espera se ve bien (`radialrival_espera_1080.jpg`). Opción para Valeria: deslizar la cámara en vez de saltar, o un fundido hasta que el sitio esté generado. | Se ve el mundo «roto» un instante. | — |
| R8 | **Baja (dato, no interfaz)** | La tarjeta propia marca «Lanzacohetes (tope) 6 / 5» en rojo: hay más que el tope. Para Andrés: comprobar si el tope se puede superar al empezar el escenario de prueba. | Puede ser un fallo de la simulación. | — |

## 3. Ventanas de Población, Fábrica, Envío y Explorar

Capturas: `poblacion_1080.jpg`, `poblacion_720.jpg`,
`fabrica_soldados_1080.jpg`, `fabrica_municion_1080.jpg`,
`fabrica_soldados_720.jpg`, `envio_1080.jpg`, `envio_720.jpg`,
`explorar_1080.jpg`, `explorar_720.jpg`.
Referencias: `suministros_1.jpg`, `suministros_2.jpg` (pantalla clara con
botones a la izquierda y detalle a la derecha).

**Está bien**

- Las cuatro piden confirmación con «Cancelar» y un botón amarillo con el coste
  («Producir ⓢ 50»), y el fondo del mapa se oscurece.
- Población está muy completa: pirámide por edades con civiles y en filas,
  nacidos y muertos del año, política de natalidad.
- Envío dice lo que sale («Salen los mejores: 3 T-55») y avisa en rojo si no
  hay munición para los días pedidos.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| V1 | **Alta** | En Población, «Habitantes / plazas de vivienda» se pisa con la cifra «6 466 / 14 745» (1080 y 720). Partir en dos filas o acortar a «Habitantes / plazas». | Solape. | — |
| V2 | **Media** | La frase de cabecera de cada ventana se corta con «…» («cada caído es un habitant…», «la ciudad sigue pagand…», «los ejércitos se la llev…», «Polvorín de la ciudad: … · 9…»). Permitir dos líneas o acortar la frase. | Texto cortado en las cuatro. | — |
| V3 | **Media** | Cuatro anchos distintos (a 1080: Población ≈525 px, Fábrica ≈345, Envío ≈335, Explorar ≈320) y dos alturas de cabecera. Usar dos anchos fijos: «ventana» (Fábrica, Envío, Explorar) y «ventana ancha» (Población). | Coherencia entre pantallas. | Warpath usa una sola caja de detalle (`suministros_1.jpg`). |
| V4 | **Media** | En Munición las filas van muy juntas: «lotes de 10 000» casi toca «Obuses». Dar a cada fila el alto de la fila de Envío. | Se lee mal. | — |
| V5 | **Baja** | Hueco vacío entre el último texto y los botones en Envío y Crear soldados. Ajustar el alto al contenido. | Sobra espacio. | — |
| V6 | **Baja** | Las flechas ‹ › de «Salen desde» (Explorar) y «Fábrica de» (Arsenal › Producir) miden unos 20 px; a 720, unos 16. Hacerlas del alto de la fila. | Cuesta acertarles. | `interfaz-militar.md` 3.1: zona táctil mínima 44 de diseño. |

## 4. Panel de tropas y ficha de un ejército

Capturas: `tropas_1080.jpg`, `tropasradial_1080.jpg`, `tropasradial_720.jpg`,
`detalle_panel_tropas_1080.jpg`, `detalle_ficha_y_radial_tropas_1080.jpg`,
`detalle_ficha_ejercito_720.jpg`. Referencias: `tropas_1_barra.jpg` a
`tropas_4_regresando.jpg`.

**Está bien**

- Las tarjetas copian las de Warpath: foto del vehículo, número de era arriba a
  la izquierda, icono de estado abajo a la izquierda (parado, en marcha,
  recolectando) y cantidad abajo a la derecha. La seleccionada lleva borde
  amarillo.
- Fila de pestañas encima (regresar, todos, tierra, mar, bandera) con la activa
  en amarillo, como en Warpath.
- El grupo elegido se marca en el mapa con círculo verde y anillo punteado.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| T1 | **Alta** | A 720 la ficha del ejército se rompe: «40», «2» y «293» pisan «SOLDADOS», «TANQUES» y «PODER», y el título «Pdte. Osric Tordo» y «En posición» quedan cortados por el borde de arriba (`detalle_ficha_ejercito_720.jpg`). A 1080 «En posición» también toca el borde. | Ilegible a 720. | — |
| T2 | **Alta** | Las etiquetas de los estandartes se pisan cuando hay varios grupos juntos: «Cnel. Lune Valco[r]» queda bajo «Cnel. Brisa Morrow · 659», que pisa «[Osr]ic Tordo · 293», y todas pisan el «★ Doquefi» de la ciudad (1080 y 720). Opciones: (A) como Warpath, nombre pequeño y poder encima de cada grupo, y los grupos parados se colocan separados en el anillo de la ciudad; (B) si se tocan, se juntan en una sola etiqueta «3 ejércitos». | Solape. | `tropas_1_barra.jpg`: cada grupo con su nombre verde y su poder, sin pisarse. |
| T3 | **Media** | La etiqueta del radial pequeño de la tarjeta se corta: «Regre…» en vez de «Regresar». | Texto cortado. | `tropas_2_grupo_regresar.jpg`: «Regresar» entero junto a «Emoticones». |
| T4 | **Media** | La ficha del ejército sale abajo al centro, lejos de la tarjeta elegida (abajo a la derecha). Opción: que salga justo encima de las tarjetas, alineada con ellas. | El ojo salta de un lado a otro. | En Warpath las órdenes salen junto al grupo o junto a su tarjeta. |
| T5 | **Media** | Tarjetas de 60×48 px a 1080 (100×80 de diseño × 0,6) y 48×38 a 720; las de Warpath ocupan cerca del 7 % del ancho (unas 130 px a 1920). Ver «Decisión 1». | Es el control principal de los ejércitos. | `tropas_1_barra.jpg`. |
| T6 | **Baja** | En la ficha, «Recolectar» desactivado no dice por qué (falta un tooltip con el motivo, como pide `interfaz-militar.md` 3.3). | Comodidad. | — |

## 5. Arsenal (Ficha, Producir y Comparar)

Capturas: `arsenal_ficha_1080.jpg`, `arsenal_producir_1080.jpg`,
`arsenal_comparar_1080.jpg`, `arsenal_ficha_720.jpg`.
Referencias: `unidad_1_modelo.jpg` a `unidad_6_ascender.jpg`.

**Está bien**

- Es la pantalla más parecida a Warpath: botones oscuros a la izquierda con el
  activo en claro, modelo 3D en el centro sobre suelo gris, chapa de poder
  inclinada arriba, categorías con contador (0/4, 2/3), tarjetas de modelos
  abajo y detalle a la derecha.
- Comparar copia «Mejorar» de Warpath: dos modelos, flecha verde, cifras
  mejores en verde y peores en rojo.
- Se ve igual de bien a 720.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| A1 | **Media** | En Ficha, «Producir» sale amarillo (activo) aunque arriba diga «Falta la tecnología»; en Producir el mismo botón sí sale gris. Que en Ficha salga gris con el motivo. | Dos estados distintos para lo mismo. | `unidad_4_soldado.jpg`: los botones bloqueados llevan candado. |
| A2 | **Media** | «Falta la tecnología» en el T-55 y a la vez «Tienes de este modelo: 13 sanos». Si ya se tienen, el rótulo debería decir «No puedes fabricar más: falta la tecnología» o similar. Puede ser un dato del escenario de prueba (para Andrés). | Parece una contradicción. | — |
| A3 | **Baja** | En Producir, la mitad baja del panel derecho queda vacía con la cola sin nada. Poner ahí el coste total y lo que ya hay en fábrica de otras ciudades, o acortar el panel. | Espacio muerto. | `suministros_1.jpg`: el panel de detalle también es alto, así que puede quedarse si el dueño lo prefiere. |
| A4 | **Baja** | El buscador y el desplegable «Poder» son pequeños frente a las tarjetas (unos 20 px de alto a 1080). | Comodidad. | `unidad_5_categorias.jpg`: «Estrellas ↓» es un botón grande. |

## 6. Perfil

Capturas: `perfil_1080.jpg`, `perfil_720.jpg`. Referencia: `perfil.jpg`.

**Está bien**

- Estructura copiada: tarjeta de la nación a la izquierda con marco azul
  marino, escudo, nombre editable, poder en marrón, nivel, medallas vacías con
  «+», placas de datos a la derecha y hexágonos (Más info, Guerras, Territorio,
  Opciones).
- Sin barra de energía, como recomendaba `interfaz-militar.md` §13 (opción A).

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| P1 | **Alta** | Perfil ocupa solo la mitad de arriba (la tarjeta va de 80 a 545 px de alto a 1080) y deja la mitad de abajo y el centro vacíos, mientras Opciones y Arsenal llenan la pantalla. Que Perfil use la misma escala que Opciones y Arsenal (pantalla completa), no la del HUD. | Tamaños incoherentes entre pantallas de la misma familia. | `perfil.jpg`: la tarjeta va de arriba abajo (≈85 % del alto). |
| P2 | **Baja** | Los rótulos de los hexágonos («Más info», «Guerras»…) son de unos 12 px a 1080. Subirlos al tamaño de las etiquetas de la barra de abajo. | Se lee mal. | `perfil.jpg`: rótulos grandes. |

## 7. Opciones (menú y General)

Capturas: `opciones_1080.jpg`, `opciones_720.jpg`, `general_1080.jpg`,
`general_720.jpg`. Referencias: `opciones_1.jpg`, `opciones_2.jpg`,
`opciones_generales_1.jpg`, `opciones_generales_2.jpg`.

**Está bien**

- Menú: dos columnas de botones anchos claros con doble borde negro, como
  Warpath.
- General: secciones con cabecera negra (IMAGEN, VOLUMEN, PERSONALIZAR),
  hexágonos de calidad con el elegido en verde, interruptores verdes,
  deslizadores verdes con porcentaje, «Restablecer» y «Aplicar» abajo.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| O1 | **Media** | Los iconos del menú miden unos 22 px dentro de botones de 88 de alto; en Warpath el icono ocupa más de la mitad del alto del botón. | Botones con aire vacío. | `opciones_1.jpg`. |
| O2 | **Media** | Resolución muestra «1024 × 768» con la ventana a 1920×1080 (y a 1280×720). Puede ser solo de la captura (con `--tam` no se aplican los ajustes guardados); comprobarlo en la ventana real. | Si pasa en el juego, el desplegable miente. | — |
| O3 | **Media** | PERSONALIZAR tiene una sola opción (Mostrar FPS). Candidatas, para que el dueño elija: «Tamaño de la interfaz» (hoy fijo en `Tema.FACTOR` 0,6), «Tamaño del texto» (hoy `Tema.TEXTO` 1,5), «Mostrar nombres de ejércitos», «Mostrar poder de los ejércitos», «Indicar alcance de ataque». | Las dos primeras dejarían a cada jugador elegir el tamaño sin tocar código. | `opciones_generales_2.jpg`: «Habilitar poder de ejército», «Indicar alcance de ataque», «Mostrar nombre de edificio». |
| O4 | **Baja** | Hueco grande entre PERSONALIZAR y los botones de abajo. Se llenará solo si se añade O3. | — | — |

## 8. Noticias

Capturas: `noticias_1080.jpg`, `noticias_720.jpg`. Referencia: el chat de
`mapa_hud.jpg` (abajo a la izquierda).

**Está bien**

- Pestañas (Todas, Guerra, Diplomacia, Obras) con la activa subrayada; la
  noticia grave en negrita con raya roja a la izquierda.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| N1 | **Media** | Noticias siempre a la vista: una franja de 3 líneas abajo a la izquierda con las últimas (como el chat de Warpath) que se abre a la ventana completa al tocarla. Hoy hay que pulsar «Noticias» para ver algo. | Enterarse sin abrir nada. | `mapa_hud.jpg`, `tropas_1_barra.jpg`: chat de 3 líneas fijo abajo a la izquierda con el escudo encima. |
| N2 | **Media** | El número de la izquierda (1, 2) es el día, pero no lo dice. Ponerlo como «Día 1» o agrupar por día con un separador. | No se entiende. | — |
| N3 | **Media** | Al tocar una noticia con lugar (una declaración de guerra, una batalla) llevar la cámara allí. | Comodidad. | En Warpath los mensajes llevan coordenadas que se pueden tocar. |
| N4 | **Baja** | La ventana es estrecha (≈285 px a 1080) y corta noticias con «…» («Motivo: esce…»). Ensancharla o dejar que la noticia ocupe tres líneas. | Texto cortado. | — |

## 9. Lista de batallas, avisos y panel de Recolectores

Capturas: `batallas_1080.jpg`, `batallas_720.jpg`.

**Está bien**

- «Batallas en curso» con el sitio, el día, quién defiende, «Ir» y «Defender».
- Los avisos graves en rojo con el botón al lado («Defender», «No defender»,
  «Ir»), como pide `interfaz-militar.md` §2.
- El botón «Batallas» de abajo se ilumina y lleva el contador rojo.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| B1 | **Alta** | El panel de Recolectores (arriba a la izquierda) tapa la columna: a 1080 cubre «Bandera» y «Ataque»; a 720 queda pegado a ella. Colocarlo a la derecha de la columna, como los demás paneles. | Tapa botones. | En Warpath ningún panel tapa la columna. |
| B2 | **Alta** | En ese panel, «Batalla en un campo petrolífero» ocupa dos líneas y la segunda pisa «Carga de petróleo»; las filas siguientes van tan juntas que el texto toca las rayas. | Solape. | — |
| B3 | **Alta** | En los avisos, el texto queda bajo sus botones: el subtítulo de «¡Atacan a tus recolectores!» desaparece tras «Defender / No defender», «llega en 1 día» se corta con «Ir» y «El ejército de…» se corta abajo. Poner los botones en su propia fila, debajo del texto. | Texto oculto. | `mapa_hud.jpg`: los avisos de Warpath llevan el texto arriba y el botón aparte. |
| B4 | **Media** | Los avisos y «Batallas en curso» quedan pegados en la misma franja de arriba a la derecha. Que los avisos vayan debajo de la lista, en una sola columna. | Apiñado. | `mapa_hud.jpg`: los eventos de la derecha van en columna. |
| B5 | **Baja** | En la lista, «Contra Mancomunidad de …» se corta y «Ir» es un botón de unos 20 px. | Texto cortado y botón pequeño. | — |

## 10. Barra de abajo (navegación)

Capturas: todas las del mapa.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| D1 | **Media** | Mover la barra (Nación, Ejércitos, Arsenal, Batallas, Noticias, Ajustes) abajo a la derecha, debajo de las tarjetas de tropas, con botones rectangulares claros con icono y texto. Hoy son hexágonos pequeños (unos 30 px) al centro, y el panel de tropas queda suelto en la esquina. | Todo lo de mandar, junto, como en Warpath. | `mapa_hud.jpg`: Oficiales, Unidades, Suministros, Alianza y Ejército en botones caqui bajo las tarjetas. |
| D2 | **Baja** | La ficha del ejército (abajo al centro) toca la barra de abajo. Si se hace D1, el problema desaparece. | Casi solape. | — |

## 11. Pantalla de carga

Capturas: `carga_1080.jpg`, `carga_720.jpg` (ver «Límites»).

**Está bien**

- Sobria y legible: «Generando el mundo… 42 %», barra amarilla y una línea con
  las comarcas y el radio.

**Ajustes**

| # | Prioridad | Ajuste | Por qué | Warpath |
|---|---|---|---|---|
| C1 | **Baja** | La barra mide 432 px a 1080 (`Tema.px(720)` × 0,6) y 10 de diseño de alto (6 px): queda pequeña en una pantalla vacía. Hacerla más ancha (40 % del ancho, que ya es el otro tope del código) y más alta. | Se ve muy poca cosa. | No hay referencia de la pantalla de carga de Warpath en `referencias-warpath/`; si el dueño quiere copiarla, haría falta una captura. |
| C2 | **Baja** | Fondo plano casi negro. Opciones: hormigón de las pantallas claras, o una vista del mapa ya generado detrás. | Coherencia con la familia clara. | Sin referencia. |

---

## Decisiones para el dueño

**Decisión 1. Tamaño de lo que más se usa con la interfaz al 60 %.**
El dueño pidió la interfaz a la mitad (`Tema.FACTOR` 0,6). Con eso, el radial
(hexágonos de 48 px), las tarjetas de tropas (60×48 px) y la barra de abajo
(iconos de unos 30 px) miden a 1080 cerca de la mitad que en Warpath. Opciones:

- **A.** Dejarlo así: el mapa se ve más.
- **B.** Subir solo esas tres piezas (por ejemplo a la escala de las pantallas
  claras) y dejar el resto del HUD al 60 %.
- **C.** Un ajuste «Tamaño de la interfaz» en Opciones › General (O3) para que
  cada jugador elija.

**Decisión 2. Dónde va la barra de recursos (M3):** arriba a la derecha en
todas las pantallas, como Warpath, o al centro en todas.

**Decisión 3. Botones del radial propio (R4):** juntar «Crear soldados» y
«Producir munición» en un solo «Producir» o mantener los siete.

**Decisión 4. «Guardar» en la columna (M6):** se queda o se quita.

## Los 10 ajustes más importantes (orden propuesto)

1. **T1** Ficha del ejército a 720: cifras sobre rótulos y título cortado.
2. **B1 + B2** Panel de Recolectores: tapa la columna y su subtítulo pisa la primera fila.
3. **B3** Avisos: texto escondido bajo sus botones.
4. **T2 + R1** Etiquetas de estandartes que se pisan entre sí, con la ciudad y con «Base».
5. **R2** Radial propio: botones repartidos por todo el arco, sin choques de etiquetas.
6. **R3** Tarjeta del radial: rótulos cortados (más ancha, rótulos cortos o «?»).
7. **P1** Perfil a pantalla completa como Opciones y Arsenal.
8. **V1 + V2** Población: rótulo pisado; frases de cabecera cortadas en las cuatro ventanas.
9. **M1** Nombre de la nación bajo la barra de recursos con zoom alto (conocido).
10. **D1 + N1** Barra de abajo bajo las tarjetas de tropas y noticias siempre a la vista, como Warpath.

## Dependencias

- **Valeria** (`interfaz/`): todos los ajustes de dibujo. Archivos más tocados:
  `ficha.lua` (T1), `pendon.lua` (B1, B2), `pregon.lua` (B3), `radial.lua`
  (R1–R6), `poblacion.lua`, `fabrica.lua`, `envio.lua`, `explorar.lua`
  (V1–V6), `perfil.lua` (P1), `navegacion.lua` y `tropas.lua` (D1, T3–T5),
  `noticias.lua` (N1–N4), `opciones.lua` (O1–O3), `barrasuperior.lua` (M3, M4).
- **Camila**: iconos de «Ataque» (M5) y, si se hace D1, botones rectangulares
  caqui de la barra de abajo.
- **Andrés**: R8 (lanzacohetes por encima del tope) y A2 (tienes 13 T-55 sin la
  tecnología); son datos, no dibujo.
- **Elena**: repetir estas capturas a 1080 y 720 tras cada ajuste; añadir un
  modo de captura para la pantalla de carga y arreglar el modo `ficha`.
- `interfaz-militar.md` sigue siendo la referencia de colores y formas; esta
  revisión no cambia ningún token.

## Criterios de aceptación (para cada ajuste hecho)

- Con los mismos comandos de captura, a 1920×1080 y a 1280×720, ningún texto
  de la pantalla tocada termina en «…» salvo nombres propios de más de 24
  letras, y ningún texto pisa a otro ni a un botón.
- Ningún panel del mapa tapa la columna izquierda ni la barra de abajo.
- El medidor de zoom se ve entero a 4 % y a 13 %.
- Perfil, Opciones y Arsenal tienen el mismo alto de cabecera y la misma
  escala de botones.

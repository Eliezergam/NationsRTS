# Encargo de diseño: botones e iconos de la pantalla principal y de los menús radiales

> **Para el diseñador gráfico externo** (el autor del login de `assets/ui/login/`).
> Este documento explica qué piezas hay hoy en la pantalla principal del juego
> (el mapa 2D) y en los menús radiales: qué hace cada una, en qué estados está
> y qué tamaño tiene. Todo sale del código actual del juego (1 de octubre de 2026). Donde
> algo está a medias, lo indica la marca **[a medias]**. Lo que el juego hoy
> dibuja con código, sin imagen, lleva la marca **[por código]**: son las piezas
> que no existen como imagen y que conviene diseñar.
>
> Capturas: `diseno/encargo-hud/` (están numeradas y se citan como **[C01]**, **[C02]**…). Están
> sacadas del juego sin ventana, con la semilla 12345 en modo jugador. Los recortes
> (del 10 al 27) están ampliados al 200 % para que se vean los detalles.

---

## 1. Contexto

1. **Nations RTS** es un juego de estrategia en tiempo real (PC) sobre un mapa 2D isométrico del mundo. El jugador dirige una nación: ciudades, recursos, ejércitos y guerras. Todo lo que se ve es ficticio.
2. **Estilo de referencia:** el de Warpath (capturas en `diseno/referencias-warpath/`, sobre todo `mapa_hud.jpg`, `radial_ciudad_propia.jpg`, `tropas_*.jpg` y `zoom_5.5.jpg`) y el propio login (`assets/ui/login/previews/login_completo.jpg`): militar oscuro, metal con bisel, filos dorados y gris claro para el texto.
3. **Resolución de trabajo: 1920×1080.** La interfaz es escalable: el juego multiplica cada medida por un factor de escala, que hoy es **0,6 a 1080p** y **0,48 a 720p**. Por eso cada pieza tiene dos medidas: la **de diseño** (la del lienzo de 1920×1080, que es la de las imágenes) y la **de pantalla** (lo que mide hoy en el monitor).
4. **Textos:** todos van en español y los escribe el juego con la fuente **Barlow** (Condensed y SemiCondensed, en `assets/fuentes/`, con licencia OFL). **Las imágenes no llevan ningún texto**, ni letras ni cifras, porque el juego se va a traducir.
5. **Qué se sustituye:** el kit actual (`assets/ui/botones`, `iconos`, `paneles`, `listas` y `barras`) es provisional: lo generó un script. El encargo es rediseñarlo con la calidad del login, **con los mismos nombres de archivo** para que el programador solo tenga que cambiar las imágenes.

---

## 2. Inventario de la pantalla principal

Vista general: **[C01]** (1920×1080), **[C02]** (1280×720) y **[C03]** (vista lejana).
Las medidas van como `diseño → pantalla a 1080p`. Cuando el texto dice «encima», se refiere al ratón sobre la pieza.

### 2.1 Barra superior (`interfaz/barrasuperior.lua`)

Mide 74 de alto en diseño, que son 44 px en pantalla. **No tiene franja de fondo:** las piezas flotan sobre el mapa.

| Pieza | Qué hace | Estados | Tamaño (diseño → pantalla) | Imagen actual | Icono |
|---|---|---|---|---|---|
| **Chapa de la nación** [C10] | Muestra el escudo de la nación del jugador, su nombre, su poder (icono y cifra) y el nivel de la capital («Nv. 2»). Un clic abre el perfil de la nación. | Normal. Encima solo aparece la ayuda: la imagen no cambia. Sin nación sale «Sin nación»; en modo observador, un rótulo con «OBSERVADOR» y el estado del mundo. | Bloque de 300×70 → 180×42 (270 en pantallas compactas y 228 en estrechas). Anillo de 64 → 38. | Anillo `listas/chapa_nacion.png` (80×80, **fijo**) sobre un rótulo `paneles/rotulo.png` (32×32, **9-slice** de 6/6/6/6). | El **escudo de la nación lo dibuja el juego** (cambia en cada partida), así que el anillo debe dejar un hueco redondo: hoy el hueco es de 54 de cada 80. Junto al poder va el icono a color `poder`. |
| **Recursos ×4** [C11] | Metal, petróleo, comida y dinero: muestran el icono, la cifra grande, una minibarra con lo lleno que está el almacén y, si falta, la palabra JUSTO, ESCASEZ o CRISIS. Encima, la ayuda da el detalle (entra y gasta al día, días que le quedan). No se pueden pulsar. | **Holgado** (barra verde), **justo** (cifra y barra amarillas), **escasez** (rojas) y **crisis** (barra rayada en rojo y cifra a 0). La cifra del dinero va siempre en amarillo. | Pastilla de 196×60 → 118×36 (172 en pantallas estrechas). Icono de 50 → 30. Minibarra de 90×4 → 54×2. | `paneles/pastilla_recurso.png` (96×32, **9-slice** de 16/16/0/0: se estira a lo ancho). La minibarra es **[por código]**. | Iconos **a color** `metal` (lingotes), `petroleo` (gota), `comida` (espiga) y `dinero` (billete), en `assets/ui/iconos_color/`. |
| **Año y día** [C12] | Muestra «Año 1  Día 2». Solo es texto. | — | Cifras de 24 → 22 px de alto aprox. | Ninguna. | — |
| **Velocidades ×5** [C12] | Pausa («II») y las velocidades 1x, 2x, 3x y 4x. Un clic equivale a su tecla (espacio y 1 a 4). | **Normal** (oscuro), **encima** (resaltado), **pulsado** y **activo** (dorado: la velocidad actual o la pausa). No tienen estado desactivado. | 40×36 → 24×22 (34 de ancho en pantallas estrechas). | `botones/boton_oscuro_*.png` (96×36, **9-slice** de 10) y `botones/boton_dorado_*.png` (96×40, **9-slice** de 12). | **Hoy no llevan icono:** «II» y «1x»… son texto. Ver la propuesta P3 del apartado 5. |

### 2.2 Placa de lugar (`interfaz/placa.lua`) [C13]

Arriba en el centro, bajo los recursos. Muestra una franja del color de la nación, una
estrella si es capital, el nombre de la ciudad más cercana y «6 466 habitantes»
o «a 353 m». Un clic abre el panel de esa ciudad. Mide 40 de alto en diseño (24 px en pantalla) y su
ancho depende del texto. El fondo es `paneles/chip_oscuro.png` (64×32, **9-slice** de
12/12/10/10, al 60 % de opacidad). La franja y la estrella son **[por código]**.

### 2.3 Columna izquierda (`interfaz/columna.lua`) [C14]

Cuatro botones hexagonales en vertical, con la etiqueta debajo. El hueco de cada botón mide 72×96 en diseño. El
**hexágono** que se ve mide **36×41 px** a 1080p y el icono va dentro, a la mitad del ancho
(**unos 18 px**).

| Botón | Qué hace (tecla) | Estados que usa | Icono actual (`assets/ui/iconos/`) |
|---|---|---|---|
| Bandera | Entra en el modo «plantar bandera» (P). Solo aparece si se juega una nación. | normal, encima, pulsado y **activo** mientras se planta | `bandera` (banderín) |
| Ataque | Lleva la cámara al último ataque que llega (X). | normal, encima, pulsado y **contador** rojo con los ataques en camino | `atacar` (dos espadas cruzadas) |
| Territorio | Muestra u oculta los territorios (T). | normal, encima, pulsado y **activo** si se ven | `mundo` (globo) |
| Guardar | Guarda la partida (F5). | normal, encima y pulsado | `guardar` (disquete) |

La pieza de todos los hexágonos es `botones/hexagono_icono_<estado>.png` (72×80,
**fijo**), con los estados `normal`, `resaltado` (encima), `pulsado`, `activo` (placa
crema con aro dorado: el icono pasa a tinta oscura y la etiqueta a amarillo) y
`desactivado`. Al pasar el ratón, el hexágono crece un 6 % y al pulsarlo se hunde
(es una animación del juego, no hace falta dibujarla).

### 2.4 Barra de abajo (`interfaz/navegacion.lua`) [C16]

Es una fila centrada de seis hexágonos, iguales a los de la columna (36×41 px), con 28 de
separación en diseño. De vez en cuando pasa un brillo por cada uno; ese brillo lo hace el juego.

| Botón | Qué hace | Estados | Icono actual |
|---|---|---|---|
| Nación | Abre el perfil de la nación. | normal, encima, pulsado y **activo** con el perfil abierto | `perfil` (busto) |
| Ejércitos | Elige todos tus ejércitos (Ctrl+A). Solo si se juega una nación. | normal, encima, pulsado y **contador** de ejércitos en batalla | `ejercito` (galones) |
| Arsenal | Abre el Arsenal, con las unidades (U). Solo si se juega una nación. | normal, encima, pulsado y **activo** | `unidades` (vehículo) |
| Batallas | Abre la lista de batallas en curso (B). Solo si se juega una nación. | normal, encima, pulsado, **activo** y **contador** | `batallas` (mira) |
| Noticias | Abre o cierra las noticias. | normal, encima, pulsado, **activo** y **contador** de las noticias sin leer (en [C01] marca 16) | `noticias` (periódico) |
| Ajustes | Abre las opciones del juego. | normal, encima, pulsado y **activo** | `ajustes` (engranaje) |

**Insignia o contador:** es `botones/insignia_roja.png` (24×24, **fijo**) y se dibuja a 24 en diseño (14 px en pantalla).
Con dos cifras o más, el juego la parte en dos mitades y pinta el centro
en rojo **[por código]**. Con más de 99 pone «99+». Cada vez que cambia el número, la insignia late.

### 2.5 Panel de tropas, abajo a la derecha (`interfaz/tropas.lua`) [C17] [C18]

Hay una tarjeta por cada grupo de tropas del jugador que está fuera de la ciudad. Si no hay ninguno fuera, el panel no
aparece.

| Pieza | Qué hace | Estados | Tamaño | Imagen actual | Icono |
|---|---|---|---|---|---|
| **Tarjeta de grupo** | Muestra la miniatura de su unidad principal, su era en números romanos (I a IV, que escribe el juego), un icono de estado y la cantidad. Un clic elige el grupo, centra la cámara en él y abre el radial pequeño (2.6). | **normal**, **resaltada** (encima) y **activa** (borde dorado: elegido en el mapa) | 100×80 → 60×48. Icono de estado de 18 → **11 px**. | `listas/tarjeta_unidad_<estado>.png` (64×64, **9-slice** de 6) | La **miniatura** es un render 3D del Arsenal: no entra en este encargo. Iconos de estado: `batallas` (en batalla), `retirar` (regresando), `bandera` (guarnición), `recolectar` (recolectando), `construir` (en obra), `suministros` (convoy), `mover` (en marcha) y `defender` (en posición). |
| **Regresar** | Hace volver a la ciudad a los grupos elegidos o, si no hay ninguno elegido, a todos los del filtro que no están en batalla. | normal, encima, pulsado y desactivado (sin grupos) | Botón cuadrado de 44 → 26 px, con un icono de 25 → 14 px | `boton_oscuro` | `retirar` (flecha curva) |
| **Seleccionar todos** | Elige o suelta todos los grupos del filtro. | normal, encima, pulsado, desactivado y **dorado** si ya están todos elegidos | igual | `boton_oscuro` y `boton_dorado` | Una marca ✓ **[por código]**: no hay icono. |
| **Filtro Tierra** | Muestra los grupos de tierra. | normal, encima, pulsado y **dorado** si es el filtro activo | igual | igual | `tanque` |
| **Filtro Agua** | Mostrará los grupos de mar. **[a medias]:** todavía no hay barcos, así que el botón siempre está desactivado. | desactivado | igual | igual | `cat_marina` (barco) |
| **Filtro Banderas** | Muestra las guarniciones de las banderas. | como Tierra | igual | igual | `bandera` |
| **Flechas ‹ ›** | Pasan las tarjetas cuando no caben (hasta 560 de diseño). | normal y desactivado | 20×40 → 12×24 | `botones/boton_franja_izquierda` y `boton_franja_derecha` (26×56, **fijo**) | La flecha está dentro de la imagen. |
| Franja vacía | Muestra «Nada fuera en este filtro» o «Todavía no hay barcos». | — | Alto de 30 → 18 | **[por código]** | — |
| Aviso de orden | Muestra «2 grupos regresan» durante 4 s, a la izquierda de los botones. | — | Alto de 44 → 26 | **[por código]** (fondo oscuro con borde amarillo) | — |

### 2.6 Radial pequeño de un grupo (`interfaz/tropas.lua`) [C18]

Sale encima de la tarjeta que se toca: es un medio disco oscuro y translúcido **[por código]** de 74 → 44 px de
radio, con **un solo botón hexagonal** de 64×84 → 38×50: «Regresar», que pasa a «Retirarse» si el grupo está en
batalla (entonces pierde la carga). Lleva el icono `retirar` y tiene los estados normal, encima, pulsado y **desactivado**
cuando el grupo no puede volver (ya vuelve, lleva una obra o es un convoy).
**[a medias]:** la etiqueta se corta («Regre…» en [C18]) porque el botón es estrecho.

### 2.7 Panel del ejército elegido (`interfaz/ejercito.lua`) [C19]

No está en la lista del encargo, pero aparece en la pantalla principal cuando hay tropas
elegidas. Es un panel claro **[por código]** con la cabecera (líder y estado), una tarjeta por
tipo de tropa (Soldados, Tanques, Cohetes y Poder, con los iconos `soldado`, `tanque` y `lanzacohetes`
monocromos y `poder` a color, de 34 → 20 px) y cinco botones de texto de 28 → 17 px de alto:
Mover (gris), Atacar (**rojo, [por código]**: no existe una imagen de botón rojo),
Recolectar (**[a medias]:** siempre desactivado), Retirar y Soltar.

### 2.8 Medidor de zoom (`main.lua`, `dibujarMedidorZoom`) [C20]

Es una barra vertical en el borde derecho, centrada, que ocupa el 25 % del alto de la pantalla (10 → 6 px de ancho y 270 px
de alto a 1080p). Va de alejado (abajo) a cerca (arriba) y encima lleva el porcentaje («10 %»).
Solo informa: no se puede arrastrar. **Todo es [por código]**: el carril oscuro, el relleno amarillo y el
pomo blanco. **[a medias]:** el porcentaje se corta en el borde derecho de la pantalla ([C01], [C20]).

### 2.9 Casillas de capas (`interfaz/casillasCapas.lua`) [C15] [C03]

Solo salen en la **vista lejana** (con el zoom al mínimo, como en Warpath `zoom_5.5.jpg`), bajo la
columna izquierda, y aparecen con un fundido. Son cuatro casillas con su texto: Territorios, Ejércitos,
Yacimientos y Batallas. Cada una muestra u oculta esa capa del mapa.
Cada casilla mide 26 → 16 px y hay 14 → 8 px entre una y otra. Sus estados son **marcada** (marca dorada) y **sin
marcar**; encima no cambian. **Todo es [por código]** (cuadro oscuro, borde gris y marca dorada).
El login ya tiene una casilla dibujada (`assets/ui/login/piezas/casilla.png`, 25×25).

### 2.10 Avisos (`interfaz/pregon.lua`) [C21] [C22] [C08]

Es una columna de tarjetas a la derecha, bajo la barra superior. Salen con los hechos graves (guerra declarada,
capital saqueada, bandera atacada o arrancada, ataque en camino…) y duran 8 s.

| Parte | Detalle |
|---|---|
| Tarjeta | 300×88 → **180×53** (260 en pantallas compactas). Si lleva una fila de botones, crece 44 → 26. Usa `listas/tarjeta_unidad`, **normal** o **resaltada** (encima). Un clic derecho la descarta. |
| Borde izquierdo rojo | Mide 4 de ancho y marca que el aviso es grave. **[por código]** |
| Miniatura | Es un cuadro oscuro con borde rojo oscuro **[por código]** y lleva dentro un icono **rojo** de 40 → 24 px: `alerta` (triángulo con exclamación), `atacar` (espadas), `bandera` o `escudo` (si habla de una capital). |
| Título y detalle | Texto del juego, en dos líneas como mucho. |
| Botón | Uno solo, «Ir»: **dorado** si lleva una acción propia y gris si no. Mide 30 → 18 de alto. Otras veces hay dos botones, como «Defender» (dorado) y «No defender» (gris), de 36 → 22 de alto ([C21]). |
| Raya del tiempo | Raya roja de 2 px al pie que se acorta en los 8 s. **[por código]** |
| «+N avisos» | Es la tarjeta de 40 de alto que agrupa los que no caben y abre las noticias. |

**[a medias]:** el detalle queda tapado por el botón «Ir» o cortado («Ataque en
camino: llega…» en [C21]). Ya está apuntado en la revisión de la interfaz.

### 2.11 Noticias (`interfaz/noticias.lua`) [C24] [C09]

Es una ventana abajo a la izquierda que se abre con el hexágono «Noticias». Mide 480 → **288 px** de ancho y su alto depende del número de noticias.
Es un **panel claro** (gris caqui con texto negro) **[por código]**: la pieza oscura del kit no se usa aquí.
Tiene una cabecera de 50 → 30 con el título «Noticias» y el botón **cerrar** (`botones/boton_cerrar_<estado>.png`,
32×32 **fijo**, de 32 → 19 px, con los estados normal, resaltado, pulsado y desactivado). Lleva **cuatro pestañas** (Todas, Guerra,
Diplomacia y Obras), de 36 → 22 de alto, con los estados **activa** (con un filete amarillo) e **inactiva**. En los paneles claros
también son **[por código]**; la pieza `botones/pestana_*` del kit solo se usa en los paneles oscuros.
Cada fila de noticia lleva una marca de prioridad de 3 px **[por código]** (roja si es alta, caqui si es media y
oliva si es baja), el día y el texto.

### 2.12 Ficha de grupo (`interfaz/ficha.lua`) [C23] [C08]

Sale al hacer clic en el estandarte de un grupo del mapa, arriba a la izquierda, junto a la columna.
Mide 400 → **240 px** de ancho (340 en pantallas compactas) y su alto depende del contenido. Es un **panel claro [por código]** con
una cabecera de 50 → 30 (el nombre del líder, o «Recolectores», «Convoy de munición» o «Remolque») y el botón cerrar.

- Escudo de la nación, de 56 → 34 px, **dibujado por el juego**, con la nación y lo que hace el grupo.
- PODER en cifra grande (o «Desconocido · Explorar» si es de otra nación y no hay informe).
- Filas de etiqueta y valor: carga, recolecta al día, tanques, lanzacohetes, soldados y munición.
- Botones de texto a todo el ancho, de 40 → 24 de alto. Según el caso: **Entrar en la batalla** (rojo
  **[por código]**), **Retirar** y **Redirigir a…** (gris), **Abastecer · munición** (dorado). Si el grupo es de otra
  nación: **Atacar a los recolectores** (rojo) y **Explorar** (gris). Todos tienen los estados normal, encima, pulsado y desactivado.

### 2.13 Tarjeta del radial

Se describe en el apartado 3.1, junto a los menús radiales.

### 2.14 Ayuda emergente

Es la ayuda que aparece junto al ratón, en todas las piezas anteriores: un rectángulo oliva casi negro, al 96 % de opacidad, con borde
oliva y esquinas cortadas, de 420 → 252 px de ancho como mucho. **[por código]**: el kit tiene
`paneles/panel_tooltip.png` (64×64, **9-slice** de 8), pero no se usa.

---

## 3. Menús radiales (`interfaz/radial.lua`; los botones los decide `main.lua`)

### 3.1 Cómo se abre y cómo es

Se abre con un clic izquierdo en un sitio del mapa (una ciudad, una instalación o una bandera) o en una mina, cuando no hay tropas
elegidas y se juega una nación (`main.lua`, `abrirRadial`). Mientras el radial está abierto, el panel de tropas y el panel
lateral de la ciudad se ocultan. La cámara se desliza si el objetivo queda muy cerca de un borde.

Partes (medidas: diseño → pantalla a 1080p):

| Parte | Detalle | Imagen hoy |
|---|---|---|
| **Círculo** | Es un disco claro translúcido de radio **250 → 150 px**, con un disco oscuro más pequeño alrededor del objetivo (el 56 % del radio) y un **borde a trazos** blanco. | **[por código]** |
| **Placa del nombre** | Es una placa oscura de lados inclinados, bajo el objetivo, con el nombre en grande: **verde** si es tuyo, **rojo** si es de otra nación y **amarillo** si es una mina. | **[por código]** |
| **Nivel** | Es un hexágono pequeño (con un vértice arriba, de 17 → 10 px de radio como mínimo) con la cifra del nivel de la ciudad. Solo sale en las ciudades. | **[por código]** |
| **Botones** | Son **hexágonos** de 80 de ancho en diseño (**48×53 px**), con un icono de 24 px y la etiqueta debajo (en dos líneas si no cabe: «Producir / munición»). Se colocan **en arco por debajo del objetivo**, a 185 → 111 px del centro y a 30° uno de otro. Si hay seis o más, el arco se abre y sube por los lados. | `hexagono_icono` con los estados normal, resaltado, pulsado, **activo** (la acción destacada: placa crema con aro dorado y etiqueta amarilla, como «Base») y **desactivado** |
| **Tarjeta de información** | Va a la izquierda del círculo (o a la derecha si no cabe) y está unida al objetivo por una **línea fina en ángulo recto que acaba en un rombo**. Mide 420 → **252 px** de ancho (380 si hay más de cinco botones). Tiene una cabecera con una **marca de ubicación** (un cuadro verde con un alfiler blanco), el título, las coordenadas y el botón **favorito** (una estrella, de 34 → 20 px: hueca o rellena en amarillo). Debajo van filas de etiqueta y valor de 34 → 20 px de alto, con el fondo gris alterno; algunas llevan el icono a color `poder`. Es de la familia **clara** (gris con texto negro). | Todo **[por código]**: el panel, la marca, la estrella, la línea y el rombo |

Las etiquetas, los nombres y las cifras las escribe el juego.

### 3.2 Ciudad propia [C04] [C25]

| Botón | Función | Icono actual | Estados |
|---|---|---|---|
| Ejército | Saca tropas de la ciudad como un ejército. | `ejercito` | normal; **desactivado** si no hay tropas |
| Crear soldados | Recluta soldados: cuántos, el coste y los días. | `refuerzo` | normal |
| Producir munición | Balas, obuses y misiles para el polvorín. | `suministros` (caja) | normal |
| Población | La gente por edades, la vivienda y los nacimientos. | `alianza` (grupo de personas) | normal |
| Arsenal | Produce tanques y lanzacohetes y muestra la cola de la fábrica. | `unidades` | normal |
| Regresar | Cierra el menú. | `retirar` (flecha curva) | normal |
| Base | Entra en la ciudad por dentro. **[a medias]:** solo dice «en construcción». | `construir` (martillo) | **activo** (destacado) |
| Reparar | Repara la vida de la ciudad o lo que hay en el taller. **Solo sale** si falta vida o hay algo en el taller (no sale en [C04]). | `reparar` | normal |

Tarjeta: «Capital nv. 2» o «Ciudad nv. N». Filas: Comandante, Poder, Poder terrestre,
Alianza (**[a medias]:** siempre «Ninguna»), Vida de la ciudad, Población (reclutables),
Soldados, Tanques y Lanzacohetes con su tope, Balas · obuses · misiles y, si hay, En fábrica y En el taller.

### 3.3 Ciudad enemiga (o de otra nación) [C05] [C26]

| Botón | Función | Icono actual | Estados |
|---|---|---|---|
| Atacar | Elige tropas y ataca (si hay paz, declara la guerra). | `atacar` | normal; **desactivado** si no hay frontera o no hay tropas desde donde salir |
| Regresar | Cierra el menú (es el botón del centro). | `retirar` | normal |
| Explorar | Manda exploradores para saber su poder, sus tropas y sus defensas. | `busqueda` (lupa) | normal; **desactivado** si ya van |

Tarjeta: Comandante, Poder y Poder terrestre (con «Desconocido · Explorar» si no hay informe),
Tropas (con informe), Alianza, Vida, Relación (en rojo «En guerra», en amarillo «Alto el fuego»
o en verde «En paz · +N»), Distancia y Exploradores (si van de camino).

### 3.4 Mina o yacimiento [C06] [C27]

| Botón | Función | Icono actual | Estados |
|---|---|---|---|
| Recolectar | Manda un grupo a recolectar. | `recolectar` (pico) | normal; **desactivado** si la mina está agotada o si no hay un puesto propio cerca |
| Regresar | Cierra el menú. | `retirar` | normal |
| Atacar | Ataca a los recolectores de otra nación. **Solo sale** si los hay. | `atacar` | normal o desactivado |
| Plantar | Planta una bandera cerca. **Solo sale** si la tierra no tiene dueño. | `bandera` | normal |
| Info | Abre el panel de la mina. | `misiones` (portapapeles) | normal |

La placa del nombre es amarilla y no hay nivel. Tarjeta: Queda («750 de 750» o «cerrada · N días»),
Riqueza, Recolectan y Distancia.
**[a medias]:** «Recolectar» se corta como «Recolec…» en [C27].

### 3.5 Bandera (y otras instalaciones: base, campamento…)

Usa el mismo menú que cualquier sitio que no es una ciudad. **No hay captura:** no existe un modo de
captura que abra este radial, así que no lo he visto en pantalla y lo describo a partir del código.

- **Bandera propia:** Info (`misiones`, abre su panel) y Regresar (`retirar`).
  **[a medias]:** no tiene acciones propias, como reforzar la guarnición.
- **Bandera de otra nación:** Atacar, Regresar, Explorar e Info (los mismos estados que en 3.3).
- La placa del nombre va sin nivel y el título de la tarjeta es «Bandera». Las filas son las de 3.3 (o, si es propia: Comandante, Poder,
  Poder terrestre, Alianza y Vida).

### 3.6 Ejército

**No hay un radial grande para los ejércitos.** Al hacer clic en el estandarte de un grupo sale su **ficha** (2.12); con
tropas elegidas, el clic en el mapa da órdenes. El único radial de ejército es el **pequeño del panel de tropas** (2.6), con
el botón Regresar o Retirarse.

---

## 4. Lista de entregables

**Reglas comunes a todas las piezas:**

- **Formato:** PNG de 32 bits con alfa.
- **Medidas:** 1x es la medida de diseño (el lienzo de 1920×1080); 2x es el doble y se usa en 4K y si se agranda la interfaz.
- **Nombres:** los mismos que tienen hoy en `assets/ui/` (así el cambio es directo). La versión 2x lleva el sufijo `@2x`, como `logo_nations@2x.png` en el login.
- **9-slice:** los márgenes van en píxeles de la imagen 1x, en el orden izquierda/derecha/arriba/abajo, y en 2x se doblan. Las esquinas no se deforman; los lados y el centro se estiran.

**Estados:** recomiendo **la opción A**.

- **A (recomendada): un archivo por estado**, como hoy: `hexagono_icono_normal.png`, `_resaltado`, `_pulsado`, `_activo` y `_desactivado`. El juego ya lee las piezas así y no hay que tocar código.
- **B: una tira horizontal por pieza**, con los estados en ese mismo orden. Es más cómoda para el diseñador, pero el programador tendría que cortarla.

### 4.1 Marcos y paneles

| Archivo (1x) | 1x | 2x | 9-slice (1x) | Estados | Uso |
|---|---|---|---|---|---|
| `paneles/pastilla_recurso.png` | 96×32 | 192×64 | 16/16/0/0 | normal | Casilla de cada recurso (se estira hasta 196×60) |
| `paneles/rotulo.png` | 32×32 | 64×64 | 6/6/6/6 | normal | Fondo del texto de la chapa y del modo observador |
| `paneles/chip_oscuro.png` | 64×32 | 128×64 | 12/12/10/10 | normal | Placa de lugar |
| `listas/chapa_nacion.png` | 80×80 | 160×160 | fijo | normal | Anillo de la nación, con un **hueco redondo transparente** de unos 54 de 80 para el escudo |
| `listas/tarjeta_unidad_*.png` | 64×64 | 128×128 | 6/6/6/6 | normal, resaltada, activa | Tarjetas del panel de tropas y fondo de los avisos |
| `paneles/panel_tooltip.png` | 64×64 | 128×128 | 8/8/8/8 | normal | Ayuda emergente (hoy **[por código]**) |
| **Nuevo** `paneles/panel_claro.png` | 96×96 | 192×192 | 12/12/12/12 | normal | Panel gris claro de las noticias, la ficha, la tarjeta del radial y el panel del ejército (hoy **[por código]**) |
| **Nuevo** `paneles/panel_claro_cabecera.png` | 96×112 | 192×224 | 12/12/50/12 | normal | El mismo panel con una cabecera de 50 |
| **Nuevo** `paneles/aviso.png` | 96×88 | 192×176 | 12/12/12/12 | normal, resaltado | Tarjeta de aviso con el borde rojo integrado (hoy son una tarjeta y una raya **[por código]**) |

### 4.2 Botones

| Archivo (1x) | 1x | 2x | 9-slice (1x) | Estados | Uso |
|---|---|---|---|---|---|
| `botones/hexagono_icono_*.png` | 72×80 | 144×160 | fijo | normal, resaltado, pulsado, activo, desactivado | Columna, barra de abajo y los dos radiales. El hueco del icono es el 50 % central del ancho |
| `botones/boton_oscuro_*.png` | 96×36 | 192×72 | 10/10/10/10 | normal, resaltado, pulsado, desactivado | Velocidades y botones cuadrados del panel de tropas |
| `botones/boton_dorado_*.png` | 96×40 | 192×80 | 12/12/12/12 | ídem | Acción principal («Abastecer», «Defender», «Ir»), la velocidad activa y el filtro activo |
| `botones/boton_gris_*.png` | 96×36 | 192×72 | 10/10/10/10 | ídem | Acción secundaria («Retirar», «Redirigir a…», «No defender») |
| **Nuevo** `botones/boton_rojo_*.png` | 96×36 | 192×72 | 10/10/10/10 | ídem | Acción peligrosa («Atacar», «Entrar en la batalla»; hoy **[por código]**) |
| `botones/boton_cerrar_*.png` | 32×32 | 64×64 | fijo | ídem | La X de los paneles (la X va dentro de la imagen) |
| `botones/boton_franja_izquierda_*.png` y `_derecha_*` | 26×56 | 52×112 | fijo | ídem | Flechas ‹ › del panel de tropas |
| **Nuevo** `botones/casilla_*.png` | 26×26 | 52×52 | fijo | marcada, sin_marcar, resaltada | Casillas de capas (hoy **[por código]**) |
| **Nuevo** `botones/favorito_*.png` | 34×34 | 68×68 | fijo | apagado, encendido, resaltado | La estrella de la tarjeta del radial (hoy **[por código]**) |
| `botones/pestana_*.png` (y **nuevo** `pestana_clara_*`) | 96×36 | 192×72 | 12/12/12/6 | activa, inactiva | Pestañas de las noticias (la clara hoy es **[por código]**) |

### 4.3 Iconos

**Monocromos** (`iconos/<nombre>_32.png`, `_64.png` y **nuevo** `_128.png`): blancos sobre
transparente, porque el juego los tiñe (gris claro, amarillo cuando están activos, rojo en los avisos, gris
apagado cuando están desactivados). Deben leerse a **32 px** y también a **18 px**, que es lo que miden hoy dentro de
los hexágonos de la columna (11 px el icono de estado de las tarjetas).

| Grupo | Iconos que hay hoy (nombre: qué representa) |
|---|---|
| Columna | `bandera`: plantar bandera · `atacar`: ataques · `mundo`: territorio · `guardar`: guardar |
| Barra de abajo | `perfil`: nación · `ejercito`: ejércitos · `unidades`: arsenal · `batallas`: batallas · `noticias`: noticias · `ajustes`: ajustes |
| Radial de ciudad propia | `ejercito`: sacar tropas · `refuerzo`: crear soldados · `suministros`: producir munición · `alianza`: población · `unidades`: arsenal · `retirar`: regresar o cerrar · `construir`: base · `reparar`: reparar |
| Radial de ciudad de otra nación, bandera y mina | `atacar` · `busqueda`: explorar · `misiones`: info · `recolectar`: recolectar · `bandera`: plantar |
| Panel de tropas | `retirar`: regresar · `tanque`: filtro tierra · `cat_marina`: filtro agua · `bandera`: filtro banderas · estados: `batallas`, `retirar`, `bandera`, `recolectar`, `construir`, `suministros`, `mover` y `defender` |
| Panel del ejército | `soldado`, `tanque` y `lanzacohetes` |
| Avisos | `alerta`, `atacar`, `bandera` y `escudo` |

**Iconos nuevos que propongo** (hoy se toma prestado un icono que no encaja o se dibuja con código): `seleccionar_todos`
(✓), `poblacion` (hoy `alianza`), `municion` (hoy `suministros`), `info` (hoy `misiones`),
`regresar` (hoy `retirar`, que también se usa para «Retirarse»), `base` (hoy `construir`) y
`pausa` (hoy es el texto «II»). Ver P3.

**A color** (`iconos_color/<nombre>_32.png` y `_64.png`, más **nuevo** `_128.png`): `metal`, `petroleo`,
`comida`, `dinero` y `poder`. El juego los pinta sin teñir: en la barra superior a 30 px, en las tarjetas a unos 18 px y
en el panel del ejército a 20 px.

**Marcas nuevas** (hoy **[por código]**): `marca_ubicacion` (el cuadro verde con el alfiler de la tarjeta del radial, 32×32 y 64×64)
y `estrella_capital` (la de la placa de lugar, 16×16 y 32×32).

### 4.4 Insignias y contadores

| Archivo (1x) | 1x | 2x | 9-slice (1x) | Uso |
|---|---|---|---|---|
| `botones/insignia_roja.png` | 24×24 | 48×48 | **pasar a 9-slice** de 12/12/0/0 | El contador rojo de los hexágonos. Con dos cifras o más se estira en píldora (hoy el centro es **[por código]**) |
| `botones/insignia_nuevo.png` | 44×20 | 88×40 | 10/10/0/0 | Pastilla roja «Nuevo» (el texto lo pone el juego) |
| **Nuevo** `radial/nivel.png` | 36×40 | 72×80 | fijo | Hexágono pequeño del nivel bajo el nombre del sitio (hoy **[por código]**) |

### 4.5 El radial

| Archivo (1x) | 1x | 2x | 9-slice (1x) | Uso |
|---|---|---|---|---|
| **Nuevo** `radial/circulo.png` | 500×500 | 1000×1000 | fijo | Disco translúcido con el borde a trazos y el disco interior oscuro (hoy **[por código]**). El juego lo dibuja a 300 px a 1080p |
| **Nuevo** `radial/placa_nombre.png` | 96×40 | 192×80 | 16/16/8/8 | Placa oscura de lados inclinados para el nombre (el texto y su color los pone el juego) |
| **Nuevo** `radial/rombo.png` | 12×12 | 24×24 | fijo | El remate de la línea que une la tarjeta con el objetivo |
| **Nuevo** `radial/medio_disco.png` | 148×74 | 296×148 | fijo | El fondo del radial pequeño del panel de tropas |
| `botones/hexagono_icono_*` | — | — | — | Los botones (4.2): son los mismos de la columna, dibujados a 80 de ancho |

### 4.6 Barras de progreso

| Archivo (1x) | 1x | 2x | 9-slice (1x) | Uso |
|---|---|---|---|---|
| `barras/barra_fondo.png` | 64×14 | 128×28 | 5/5/0/0 | Canal oscuro |
| `barras/barra_relleno_recurso.png` (dorado), `_energia` (verde), `_peligro` (rojo), `_estadistica` y `_experiencia` | 64×10 | 128×20 | 4/4/0/0 (la de energía, 8/8/0/0) | Rellenos |
| **Nuevo** `barras/minibarra_*.png` | 64×4 | 128×8 | 2/2/0/0 | Minibarra de los recursos: canal, verde, amarillo, rojo y rayado de crisis (hoy **[por código]**) |
| **Nuevo** `barras/zoom_carril.png`, `zoom_relleno.png` y `zoom_pomo.png` | 10×64 (carril y relleno) y 18×18 (pomo) | el doble | 0/0/5/5 (carril y relleno) | Medidor de zoom (hoy **[por código]**) |
| **Nuevo** `barras/raya_tiempo.png` | 64×2 | 128×4 | 1/1/0/0 | Raya roja que se acorta en los avisos |

---

## 5. Reglas para el diseñador

1. **Sin texto dentro de las imágenes:** ni letras, ni cifras, ni «II», ni «1x». Todo lo escribe el juego en Barlow.
2. **Legible sobre el mapa claro y sobre el oscuro.** Las piezas flotan sobre el terreno verde y el agua azul ([C01]), y sobre el mapa oscuro de la vista lejana ([C03]). Pon un borde o una sombra oscura que separe la pieza del fondo, sin velo ni desenfoque.
3. **Contraste:** el texto que pone el juego encima (gris muy claro o tinta oscura sobre el dorado) debe leerse con un contraste de 4,5:1 o más. El activo, el desactivado y el normal tienen que distinguirse también sin color (por el brillo o el aro).
4. **Iconos reconocibles a 32 px**, y también a 18 px, que es su tamaño real dentro de los hexágonos a 1080p. Forma clara y trazo grueso, sin detalle fino.
5. **Entregar el PSD con capas** (o el archivo editable equivalente), con una capa por estado y los cortes 9-slice marcados con guías.
6. **Sin imágenes hechas con IA.** El PSD del login traía capas generadas con ChatGPT y no se usaron. Todo debe estar dibujado a mano o hecho con recursos de licencia libre; indica la fuente y la licencia de cada uno.
7. **Todo ficticio:** sin banderas, escudos ni símbolos de países, partidos o ejércitos reales.

---

## 6. Para el estudio (no hace falta pasárselo al diseñador)

**Hecho:**

- Capturas: 9 completas y 18 recortes en `diseno/encargo-hud/`, de la semilla 12345 con `--jugador`.
- Modos de captura: `tropas`, `tropasradial`, `radialpropia`, `radialrival`, `radialmina`, `noticias`, `tropasciudad`, `fichareco` y `defender`, más la vista lejana a zoom 0,04.
- Medidas en pantalla: calculadas con `Tema` real (con el factor de escala e = 0,6 a 1080p y 0,48 a 720p). No están medidas a ojo.

**No verificado:**

- El radial de una bandera: no hay modo de captura que lo abra.
- El botón «Reparar» del radial propio: la capital estaba entera.
- El aviso «+N avisos».

**[a medias], vistos en el código o en las capturas:**

- El filtro Agua está siempre desactivado.
- El radial «Base» solo dice «en construcción».
- La fila «Alianza» siempre dice «Ninguna».
- «Recolectar» está siempre desactivado en el panel del ejército.
- Etiquetas cortadas: «Regre…» y «Recolec…».
- El texto de los avisos queda bajo el botón.
- El porcentaje del zoom se corta en el borde derecho.

**Decisiones del dueño:**

- **P1. Medida de entrega.**
  - **A (recomendada):** 1x = la medida de diseño, y 2x. Hoy el juego las dibuja al 60 %, así que hay margen si se agranda la interfaz.
  - **B:** entregar al tamaño de pantalla actual. Las piezas son más pequeñas, pero se ven borrosas si la interfaz crece.
- **P2. Piezas [por código] que pasan a imagen** (panel claro, botón rojo, casillas, círculo del radial, medidor de zoom, minibarras, favorito…).
  - **A (recomendada):** encargarlas todas ahora. El estilo queda uniforme, pero luego Valeria tiene que cambiar el dibujo en cada módulo.
  - **B:** encargar solo las del kit actual. Es menos trabajo para el diseñador y nada de código, pero conviven dos estilos.
- **P3. Iconos nuevos** (`seleccionar_todos`, `poblacion`, `municion`, `info`, `regresar`, `base` y `pausa`).
  - **A (recomendada):** pedirlos. Cada botón tendrá un icono que diga lo que hace, y el cambio de nombres en el código es pequeño.
  - **B:** mantener los iconos prestados.
- **P4. Tamaño en pantalla.** A 1080p los hexágonos miden 36×41 px y los iconos unos 18 px, la mitad que en Warpath (ya apuntado en `revision-interfaz-2026-10-01.md`). El diseñador debería saber si la interfaz va a crecer antes de afinar los iconos para 18 px.

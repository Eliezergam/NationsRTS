# Interfaz militar (estilo Warpath original)

> **Estado: PROPUESTO; corregido el 2026-09-30 por el dueño.** Al ver la
> primera interfaz programada dijo que «no se ve militar» y que los colores son
> de otro tipo de juego: el estilo y los colores son los de **Warpath
> ORIGINAL**. Este documento sustituye la paleta de «acero azulado y dorado»
> (versión de b250fd6) por dos familias: **hormigón claro** y **oliva/caqui
> oscuro**. Sigue vigente que esta interfaz **sustituye por completo** al
> «Estandarte colgante» (pergamino y bronce); el Estandarte queda solo en las
> fichas de ejército del mapa.
>
> Referencias, por orden de autoridad: `diseno/referencias-warpath/`
> (`perfil.jpg`, `opciones_1.jpg`, `opciones_2.jpg`, `mapa_hud.jpg`, 3120×1440)
> para color, forma y estructura; `diseno/referencia-interfaz-militar.png`
> (6 pantallas) y `diseno/referencias-arsenal/` solo para la **estructura** de
> pantallas que aún no existen (Unidades, Arsenal, Manual, mapa mundial); su
> color azul acero ya **no vale**.
> Para quién: **Camila** (recursos gráficos) y **Valeria** (programarlo en
> `NationsRTS/interfaz/`).
>
> Notas de método:
> - Los colores salen de un script que toma el color más frecuente de zonas de
>   las capturas Warpath (marcados «muestra», cuantizados a pasos de 8).
>   Los que las capturas no enseñan están **derivados** y marcados «derivado».
> - Las medidas son de diseño a 1920×1080. Las capturas son de móvil
>   (3120×1440): se copian **proporciones y formas**, no píxeles.
> - `diseno/interfaz.md` (que citan los comentarios del código) **no existe**.
> - Nada de esto está programado. Lo que sí existe se cita como «hoy».
> - Decisiones ya tomadas que siguen: oro y dinero son el mismo recurso (cuatro
>   recursos en la barra), tipografía Barlow.

---

## 1. Resumen

El estilo tiene **dos familias** que nunca se mezclan en la misma superficie:

1. **Familia clara (hormigón), para menús a pantalla completa:** perfil,
   opciones, listas y formularios. Fondo de hormigón gris claro con veta,
   placas y botones gris muy claro con **doble borde negro** (un filo negro
   exterior grueso y otro fino interior separado por una línea gris), **texto
   negro** condensado y esquinas rectas.
2. **Familia oliva/caqui oscura translúcida, para el HUD sobre el mapa:**
   barra de recursos, columna de botones izquierda, paneles de sitio, tooltips
   de información, chat/noticias y barra de acciones. Fondo verde oliva casi
   negro al 78 % de opacidad, texto claro, botones **hexagonales de metal
   gris** con **insignias rojas** de aviso, acentos **amarillos**
   (selección, pestaña activa, cifra de dinero) y **barra de energía verde con
   galones (chevrons)**.

Sobre el mapa hay: barra superior (nación, cuatro recursos, día y velocidad),
columna de botones a la izquierda, barra inferior de acciones, tarjetas de
evento a la derecha y paneles de sitio a la derecha. Además hay dos pantallas
nuevas de familia clara: **Perfil** y **Opciones**. Todo en español, dibujado
con LÖVE/Lua sobre recursos 9-slice y dibujo procedural, con la escala de hoy
(`Tema.escala`).

## 2. Fantasía del jugador

Estar en el puesto de mando de una nación: paneles sobrios, legibles de un
vistazo, con los números que importan siempre a la vista (recursos, poder,
vida de la ciudad). Lo urgente (una bandera atacada, una ciudad sitiada, un
ejército enemigo que llega) sale en rojo y con el botón que hace falta al lado
(«Defender», «Atacar», «Ir»). Lo demás no estorba.

## 3. Tokens de diseño

### 3.1 Escala y rejilla

- Unidad base **4 px** de diseño. Espaciados: `4, 8, 12, 16, 24, 32`.
- Escala `e` como hoy (`Tema.actualizar`): `e = max(0,8; alto/1080)`, con tope
  `ancho/1920 × 1,25` si la pantalla es más estrecha que 16:9. **1920×1080 →
  e = 1** (lienzo de diseño 1920×1080). **1280×720 → e = 0,8** (lienzo de
  diseño 1600×900). `Tema.px(v)` redondea a entero.
- Margen a los bordes de pantalla: **16**. Separación entre paneles: **8**.
- Zona táctil mínima de cualquier botón: **44×44** de diseño (35 px reales a
  0,8).

### 3.2 Paleta (hex)

**Familia clara: hormigón** (perfil, opciones, listas, formularios)

| Nombre | Hex | Uso | Origen |
|---|---|---|---|
| `hormigon` | `#c4c4cc` | fondo de pantalla, zona alta | muestra `perfil.jpg` |
| `hormigonSombra` | `#9c9ca4` | fondo de pantalla, zonas bajas y viñeta | muestra |
| `papel` | `#e4e4e4` | placas de datos, tarjeta de perfil por dentro | muestra |
| `papelBoton` | `#dcdcdc` | botones anchos, campos, desplegables | muestra `opciones_1.jpg` |
| `papelLinea` | `#a4a4a4` | línea gris entre los dos bordes negros y separadores | muestra |
| `negro` | `#181818` | borde doble, cabecera con logo, iconos | muestra (`#1c1c1c` en la cabecera) |
| `tinta` | `#080808` | texto principal (15,8:1 sobre `papel`, 11,6:1 sobre `hormigon`) | muestra |
| `tintaTenue` | `#4a4a4a` | texto secundario, etiquetas de placa (7,0:1 sobre `papel`) | derivado |
| `marino` | `#242c3c` | marco de la tarjeta de comandante | muestra |
| `marinoOscuro` | `#1c2434` | sombra del marco marino | muestra |
| `poderMarron` | `#886848` | cifra de poder (solo tamaño grande, 4,0:1) | muestra |
| `cabecera` | `#1c1c1c` | placa negra del logo y del título de pantalla | muestra |
| `tituloClaro` | `#e8e8e8` | título de pantalla sobre el hormigón (con sombra negra de 2 px) | muestra |

**Familia oliva/caqui (HUD sobre el mapa)**

| Nombre | Hex | Uso | Origen |
|---|---|---|---|
| `olivaNegro` | `#242c14` | fondo de chat/noticias y pie de pantalla (opacidad 0,85) | muestra `mapa_hud.jpg` |
| `oliva` | `#343c2c` | barra de recursos, columna izquierda, paneles (opacidad 0,78) | muestra |
| `olivaClaro` | `#3c4424` | botones cuadrados de la columna izquierda | muestra |
| `caqui` | `#bcbcb4` | botones inferiores y tooltip de información (fondo claro con tinte caqui) | muestra |
| `caquiFila` | `#cccccc` | filas alternas del tooltip | muestra |
| `hexMetal` | `#444444` | cuerpo del botón hexagonal oscuro | muestra `perfil.jpg` |
| `hexMetalClaro` | `#b4b4b4` | cuerpo del hexágono claro (menú radial del mapa) | muestra `mapa_hud.jpg` |
| `hexBorde` | `#242424` | contorno del hexágono | muestra |
| `textoHud` | `#f0f0e8` | texto sobre `oliva` (10,0:1) y sobre `olivaNegro` (12,7:1) | derivado |
| `textoHudTenue` | `#b8b8a8` | texto secundario del HUD | derivado |

**Acentos (comunes a las dos familias)**

| Nombre | Hex | Uso | Origen |
|---|---|---|---|
| `amarillo` | `#fcdc64` | pestaña activa, selección, borde de tarjeta seleccionada, «+» de compra/mejora (10,8:1 sobre `olivaNegro`) | muestra |
| `amarilloDinero` | `#ecb434` | cifra y tapa de la casilla de dinero (6,1:1 sobre `oliva`) | muestra |
| `caquiPestana` | `#c4ac6c` | pestaña no activa del HUD | muestra |
| `amarilloTinta` | `#181818` | texto sobre `amarillo` (13,2:1) | derivado |
| `rojo` | `#c43434` | insignia de aviso y «Nuevo» (con cifra blanca 5,4:1) | muestra |
| `rojoOscuro` | `#7a1e1e` | fondo de aviso grave, pulsado | derivado |
| `rojoTexto` | `#f07060` | texto de aviso sobre `olivaNegro` (5,0:1; **no** sobre `oliva`, 3,9:1) | derivado |
| `verde` | `#84c444` | barra de energía, relleno «holgado» | muestra |
| `verdeOscuro` | `#74b434` | segunda franja de los galones | muestra |
| `verdeGalon` | `#5a9a24` | galones (chevrons) sobre la barra | derivado |
| `verdeNombre` | `#74ec6c` | nombre propio sobre el mapa | muestra |

**Estados de reserva** (los cuatro de hoy, `Simulacion:reservas`): `holgado` =
`verde`; `justo` = `amarillo`; `escasez` = `rojo`; `crisis` = rayado `rojoOscuro`
y `rojo` (como `Tema.rayado`). Siempre con el texto «JUSTO», «ESCASEZ» o
«CRISIS» además del color.

### 3.3 Estados de cada familia de color

Regla única para cada botón o control:

- **Normal:** la base de la tabla.
- **Resaltado (ratón encima):** +6 % de luminosidad; en la familia clara el
  filo interior pasa de `papelLinea` a `amarillo`; en el HUD, un halo amarillo
  suave de 4 px (como el círculo de brillo que rodea al hexágono destacado).
- **Pulsado:** −12 % de luminosidad, contenido 1 px hacia abajo, sin halo.
- **Desactivado:** el fondo a gris plano (`#b0b0b0` en la clara, `#2c2c24` en
  el HUD), el texto y el icono a 40 % de opacidad, sin filos brillantes. Su
  tooltip dice el motivo.
- **Foco de teclado:** contorno de 2 px `amarillo` a 2 px de distancia.

| Control | Normal | Resaltado | Pulsado | Desactivado |
|---|---|---|---|---|
| Botón ancho claro | fondo `#dcdcdc` | `#e8e8e8` + filo `amarillo` | `#c4c4c4` | `#b0b0b0` |
| Botón hexagonal | cuerpo `#444444` | `#565656` + halo `amarillo` | `#303030` | `#2c2c2c`, icono al 40 % |
| Botón amarillo (principal) | `#fcdc64` | `#ffe888` | `#d4b444` | `#8c8460` |
| Botón cuadrado del HUD | `#3c4424` | `#4c5630` | `#2a3018` | `#2c2c24` |
| Pestaña HUD | `#c4ac6c` inactiva | `#d4bc7c` | — | — |
| Pestaña activa | `#fcdc64` | `#fcdc64` | — | — |

## 3.3b Familias por pantalla

| Pantalla | Familia |
|---|---|
| Perfil, Opciones, Noticias (lista completa), lista de Ejércitos, Envío, Armar ejército | clara (hormigón) |
| Barra superior, columna izquierda, barra inferior, tarjetas de evento, paneles de ciudad / instalación / mina / bandera, ficha de ejército, batallas en curso, plantar bandera, tooltips de información | oliva/caqui |
| Arsenal, Manual, mapa mundial (fase posterior) | clara para formularios y tablas; oliva para listas de tarjetas y detalle |

### 3.4 Tipografías

**DECIDIDO:** **Barlow Condensed** (títulos) y **Barlow Semi Condensed**
(texto y cifras), licencia OFL, ya en `assets/fuentes/` (`BarlowCondensed-`
`Medium`/`SemiBold`, `BarlowSemiCondensed-Medium`/`SemiBold`, `Barlow-*`).
No hay peso Bold de las variantes condensadas: donde antes decía Bold se usa
SemiBold. Alegreya se retira en la fase 7.
Tamaños en px de diseño; el mínimo real es 12 px de texto y 10 px de etiqueta
(`Tema.fuente`), así que a 0,8 los 14 quedan en 12.

| Estilo | Fuente | Tamaño | Color | Uso |
|---|---|---|---|---|
| `titulo` | Barlow Condensed SemiBold | 30 (pantalla) / 24 (panel HUD) | `tituloClaro` con sombra / `textoHud` | cabecera |
| `subtitulo` | Barlow Condensed SemiBold | 20 | `amarillo` (HUD) / `tinta` (claro) | secciones («Reservas», «Defensas») |
| `cuerpo` | Barlow Semi Condensed Medium | 18 | `tinta` (claro) / `textoHud` (HUD) | filas y párrafos |
| `cifra` | Barlow Semi Condensed SemiBold | 22 | `textoHud` (`amarilloDinero` en dinero) | barra de recursos |
| `cifraGrande` | Barlow Condensed SemiBold | 40 | `tinta`; `poderMarron` en el poder | placas de dato, poder, nivel |
| `boton` | Barlow Condensed SemiBold | 24 | `tinta` (claro) / `amarilloTinta` (amarillo) / `textoHud` | botones |
| `etiqueta` | Barlow Semi Condensed Medium | 14 | `tintaTenue` / `textoHudTenue` | rótulos pequeños, insignias |
| `ayuda` | Barlow Semi Condensed Medium | 16 | `textoHud` | tooltip corto |

Los números siguen el formato de hoy (`Tema.numero`: «19 039», «123 k»,
«1,2 M»; `Tema.decimal`: «+18,3»).

### 3.5 Formas, bordes y sombras

- **Familia clara: esquinas rectas.** Nada de cortes ni redondeos en placas y
  botones anchos. **Doble borde negro:** filo exterior de **3 px** `negro`, luego
  **2 px** `papelLinea`, luego filo interior de **1 px** `negro` (en el original
  se ve como un marco grueso y otro fino por dentro). Total 6 px por lado.
- **Tarjeta de comandante:** marco `marino` de 8 px con biselado (claro arriba
  y a la izquierda `#3c4660`, oscuro abajo y a la derecha `marinoOscuro`) y
  esquina inferior derecha cortada 16 px; por dentro `papel` con veta.
- **Familia oliva: rectángulos con corte de 8 px** en las esquinas superior
  izquierda e inferior derecha de paneles y tarjetas, y un filo de 1 px
  `#1c1c14` por fuera y otro de 1 px `#6c7448` por dentro. Opacidad de fondo
  0,78 (paneles) o 0,85 (pie de pantalla y chat).
- **Hexágono de metal:** hexágono de vértice arriba (lado 1 : ancho 1,73 de
  alto 2), cuerpo `hexMetal` con degradado vertical a `#303030`, bisel de 2 px
  claro arriba, contorno 2 px `hexBorde`, icono blanco lineal en el centro y
  etiqueta debajo en `textoHud` con sombra de texto. Tamaños: 88 (perfil),
  72 (columna y menú radial), 56 (barra).
- **Insignia roja:** círculo de 24 `rojo` con contorno 1 px blanco y cifra
  blanca; la variante «Nuevo» es una píldora de 44×22 con el mismo rojo.
- **Barra de energía:** pista `#3a3a30` de 22 de alto con contorno negro de
  2 px; relleno `verde` con galones (chevrons `>`) `verdeGalon` de 22 px de
  paso, texto «460/200» centrado en blanco con sombra negra; a la izquierda un
  disco de 40 con el rayo, a la derecha un botón amarillo de 44×44 con «+».
- **Radios redondos:** solo insignias, disco de la barra de energía y asa del
  deslizador.
- **Sombra de panel:** dos rectángulos negros desplazados 3 px hacia abajo,
  opacidad 0,25 y 0,12. **Sombra de texto** (títulos sobre hormigón y texto
  sobre mapa): 2 px abajo y a la derecha, negro al 70 %.
- **Fondo de hormigón:** textura tileable de hormigón con cuadrícula fina
  (líneas de plano de mapa al 6 %), de Camila.

## 4. Componentes

`9s` = 9-slice de imagen; `proc` = dibujo procedural con `love.graphics`.
Las imágenes se entregan a 1× y a 2× (el juego usa 2× si `e ≥ 1,5`). Insets en
px de diseño. Cada componente dice su familia: **C** clara, **O** oliva.

| Componente | Fam. | Medidas (diseño) | Estados | Se compone de |
|---|---|---|---|---|
| **Panel claro** | C | ancho libre; marco de 6 px; relleno 16 | fijo | `9s` `marco_doble` 48×48, inset 12 (doble borde negro con `papelLinea`) sobre `papel` |
| **Panel HUD** | O | ancho libre, mínimo 240; corte 8; relleno 12 | fijo | `9s` `panel_hud` 48×48, inset 12 (translúcido) + fondo `oliva` al 0,78 |
| **Cabecera de pantalla** | C | alto 72 a ancho completo; placa negra de logo 120×56 a la izquierda (`cabecera`), título `titulo` en `tituloClaro` a 32 px de ella | fijo | `9s` `placa_logo` 120×56 + texto con sombra; a la derecha va la barra de recursos (5.1) |
| **Cabecera de panel HUD** | O | alto 40, título a 12, cierre 32×32 | cierre: normal, resaltado (rojo), pulsado | `proc` sobre `olivaNegro` |
| **Botón ancho de menú** | C | 480×76 (cuadrícula de 2 columnas, ver 5.15); icono negro 40 a 12 del borde, texto `boton` `tinta` alineado a la izquierda; puede llevar insignia | los 4 de 3.3 | `9s` `boton_menu_{normal,resaltado,pulsado,desact}` 48×48 inset 12 |
| **Botón amarillo (principal)** | ambas | alto 48 (compacto 40), ancho = texto + 48, mínimo 120; texto `boton` `amarilloTinta`; recto en C, corte 6 en O | los 4 | `9s` `boton_amarillo_*` 48×48 inset 12 |
| **Botón gris (secundario)** | ambas | mismas medidas; texto `tinta` en C, `textoHud` en O | los 4 | `9s` `boton_gris_*` (`#dcdcdc` con doble filo en C; `hexMetal` liso en O) |
| **Botón rojo (peligro)** | O | mismas; solo para destruir o declarar guerra | los 4 | `9s` `boton_rojo_*` |
| **Botón hexagonal** | ambas | 88 / 72 / 56; icono blanco 50 %; etiqueta debajo | los 4 + **destacado** (halo `amarillo`) | `9s`/imagen `hex_metal_*` + icono `proc` |
| **Botón cuadrado de HUD** | O | 56×56 (columna izquierda), icono 32; etiqueta «Nuevo» opcional encima | los 4 | `9s` `boton_hud_*` 24×24 inset 8 |
| **Insignia roja** | ambas | círculo 24 (28 si 2 cifras), esquina superior derecha, a −8/−8; cifra `etiqueta` blanca; sin tope, «99+» solo por ancho | visible si cuenta ≥ 1 | `proc` |
| **Insignia «Nuevo»** | ambas | píldora 44×22, texto blanco 13 | visible o no | `proc` |
| **Pestañas** | O | alto 44, ancho = icono 32 + 24; el conjunto es una tira | inactiva `caquiPestana`, resaltada, **activa** (`amarillo`, icono negro), desactivada | `proc` |
| **Barra de estadística** | C | fila 32: icono 20, etiqueta 150, barra 160×10, valor 56 | valor real | `proc`: pista `hormigonSombra` con filo `negro` 1 px, relleno `tintaTenue`; en O, pista `olivaNegro` y relleno `textoHudTenue` |
| **Barra de energía** | ambas | 700×22 (ancho libre) con disco 40 y botón «+» 44 | lleno, medio, vacío; sin tope: si supera el máximo (460/200) el texto lo dice y la barra se llena entera | `proc` (3.5) |
| **Barra de recurso** | O | 176×44: icono 32, cifra `cifra` `textoHud` (`amarilloDinero` en dinero), mini barra 4 px debajo | por estado de reserva; «+N afuera» en `amarillo` | fondo `oliva`, forma de paralelogramo inclinado 12 px (como la barra de la referencia) `proc`; icono |
| **Interruptor** | C | 52×26 | apagado (`#8c8c8c`), encendido (`verde`), resaltado, desactivado | `proc`: píldora con contorno negro 2 px, asa `#f4f4f4` |
| **Deslizador** | C | pista 200×8, asa 20 | normal, resaltado (asa con filo `amarillo`), arrastrando, desactivado | `proc`: pista `hormigonSombra` con contorno negro, tramo lleno `verde`, asa disco `#f4f4f4` |
| **Desplegable** | C | alto 36, ancho libre, flecha ▼ | cerrado, abierto, resaltado, desactivado | `proc` con doble filo delgado (2 px `negro` + 1 px `papelLinea`) |
| **Placa de dato** | C | 250×84: valor grande `cifraGrande` `tinta` arriba, etiqueta `cuerpo` `tintaTenue` debajo; icono tenue a la derecha opcional; sin borde, fondo `papel` sobre el hormigón | única | `proc` |
| **Lista con selección** | O | fila 40; icono 24, texto, contador redondeado | normal `oliva`, resaltada `#444c34`, **seleccionada** `#5a6238` + barra `amarillo` 3 px, desactivada; sin límite de filas | `proc` |
| **Lista clara** | C | fila 44; línea `papelLinea` entre filas; seleccionada = fondo `#d0d0d8` y filo `amarillo` | los 4 | `proc` |
| **Tarjeta de unidad** | O | 176×184: imagen 176×112 (con velo rojo oscuro si es artillería, como en el original), nivel arriba a la izquierda en números romanos, cantidad abajo a la derecha | normal, resaltada, **seleccionada** (borde `amarillo` 2 px), desactivada | `9s` `tarjeta_hud` 48×48 inset 12 + imagen |
| **Tarjeta de evento** | O | 300×88: miniatura 84×88, título 18, plazo `amarillo`, botón pequeño «Ir»; insignia roja con la cuenta | normal, resaltada; barra fina inferior que se acorta (8 s); grave = filo izquierdo 4 px `rojo` | `9s` `tarjeta_evento_hud` 48×88 inset 12 |
| **Tooltip de información** | O/C | 440 de ancho: cabecera con icono de lugar y nombre, hasta N filas de «etiqueta … valor», filas alternas `caqui` / `caquiFila`, texto `tinta` | único; aparece a los 300 ms o al tocar un edificio | `proc` |
| **Tooltip corto** | O | ancho máx. 420, relleno 8, `ayuda`, `textoHud` | único | `proc` sobre `olivaNegro` 0,96 con filo 1 px `#6c7448` |
| **Insignia de nivel** | ambas | escudo hexagonal de 48 con el número (Nv. 27) en `cifra` | única | `9s`/imagen `insignia_nivel` 48×52 |
| **Medalla** | C | disco de 64 con relieve; hueco vacío = hexágono gris con «+» | ganada, vacía | imagen `medalla_*` |
| **Selector de cantidad** | ambas | 176×44: «−» 44, valor 88, «+» 44 | −/+ desactivados en 0 y en lo que hay (nunca un tope inventado) | dos botones grises + campo `proc` |
| **Campo de búsqueda / filtro** (posterior) | C | alto 32, lupa 20 | normal, foco, desactivado | `proc` |
| **Tabla de dos columnas** (posterior) | C/O | filas 26 | única | `proc` |
| **Franja de miniaturas** (posterior) | O | miniatura 96×56, flechas ‹ › 40×56 | seleccionada con borde `amarillo` | `9s` + flechas |
| **Insignia chevron (Arsenal)** (posterior) | O | 20×20 en la esquina de la tarjeta de unidad | nivel alto/bajo | imagen `chevron_nivel` |
| **Tarjeta de doctrina** (posterior) | O | 300×88 con imagen, escudo y flecha › | normal, resaltada | como tarjeta de evento |

## 5. Pantallas de ahora

**Familia de cada pantalla:** ver 3.3b. Los bocetos ASCII de 5.1 a 5.13 son de
estructura; los colores y formas son los de 3.2 y 3.5 (oliva/caqui para el
HUD).

Convenciones: las consultas de la simulación van entre comillas de código;
`nid` es la nación del jugador. **Sin topes artificiales:** toda lista se
desplaza con la rueda (hoy hay topes de 8 batallas en `batallas.lua`, 6
noticias en `noticias.lua` y 3 pregones a la vez en `pregon.lua`; la propuesta
los quita, ver 5.12). A 1280×720 el lienzo es 1600×900: las medidas no cambian,
pero los anchos se recortan como se dice en cada pantalla.

### 5.1 Barra superior (hoy: `travesano.lua`)

Alto **64** (72 la chapa). Familia oliva: fondo `oliva` al 0,78 con filo
inferior de 1 px `#1c1c14`; la casilla de recurso va inclinada como en la
referencia (paralelogramo de 12 px). El dinero lleva su cifra en
`amarilloDinero`. La chapa de nación es un escudo hexagonal con el nivel y,
al lado, nombre y poder.

```
+---------------+-------------------------------------------------+-------------------------+
| [escudo] Nación|[metal][petróleo][comida][dinero]              | Día 132  II 1x 2x 3x 4x [Pf][Aj]|
| Poder 12,4 M Nv.3|  cada una 176×44                              |                         |
+---------------+-------------------------------------------------+-------------------------+
```
(Pf = Perfil y Aj = Ajustes: botones de icono de 48×48.)

- **Chapa de nación** (x 0–320): escudo 56×56 (el de `mundo/estandartes`),
  nombre de la nación, «Poder» (`sim:fuerza(nid)`) y «Nv. N»
  (`sim:nivelCapital(nid)`). Clic: abre Perfil (5.14).
- **Recursos** (centrados, 4 × 176 + 3 × 8 = 728):
  - **Metal, petróleo, dinero:** `sim:almacenDe(nid)` → `metal`,
    `petroleo`, `dinero`; mini barra = `cantidad / almacen` (dinero /
    `boveda`); «+N afuera» si `afuera.X > 0` (lo que no cabe en el almacén).
    Estado y color: `sim:reservas(nid)` (`estado`, `dias`).
  - **Comida:** la reserva de la ciudad peor alimentada
    (`sim:reservas(nid)`, tercera entrada; su cifra es `c.comida` y su tope
    `Simulacion.granero(c)`).
  - **Oro:** **DECIDIDO**: oro y dinero son el mismo recurso; no hay casilla
    de oro. Lo que se saca de una mina de oro entra como dinero
    (`entregarCarga`, `precioOro` = 8).
  - Tooltip de cada recurso: «Metal 351 de 500 · entra 12 al día · le dura 29
    días» (`reservas`).
- **Tiempo:** «Día N» (`sim.estado.dia`) y cuatro botones de velocidad + pausa
  (hoy teclas 1 a 4 y espacio, `VELOCIDADES` = 1/60, 1/20, 1/5 y 1 día por
  segundo); el activo va en `amarillo`.
- **Botones de la derecha:** Perfil (abre 5.14) y Ajustes (abre 5.15). Las
  acciones de mapa que hoy están en el travesaño pasan a la columna izquierda
  (6.1).
- **1280×720:** los recursos pasan a 144×44 (icono 28, cifra 20), se ocultan
  «+N afuera» y la mini barra (siguen en el tooltip) y la chapa baja a 260.
  Suma: 4 × 144 + 3 × 8 = 600 dentro de los 1600 − 260 − 220 disponibles.

### 5.2 Ciudad (hoy: `pendon.lua`, `dibujarCiudad`)

Panel a la derecha, x = 1920 − 16 − **480**, y = 80, alto libre hasta 1064 con
desplazamiento. Cabecera: nombre de la ciudad y «Capital de X»/«Ciudad de X»
(`sim:ciudad(id)`, `sim:nacion`), cierre. Las cuatro pestañas de hoy
(Resumen, Ejército, Nación, Relaciones) pasan a pestañas de 3.4.

```
+--- Puerto Águila · Capital de Voltex ------------[X]+
| [Resumen][Ejército][Nación][Relaciones]              |
| Aviso: ! Ciudad sitiada · sin curas                  |
| VIDA  [██████████░░░░] 72/100  (+12 en 6 días)      |
| Población 19 039   Nv. 3   Soldados 300              |
| RESERVAS  metal  ████░ 351   petróleo ███░ 210       |
|           comida ███░ 84 · JUSTO 9 días              |
| DEFENSAS  [■■■■■■□□▨▨] soldados / tanques / lanz.    |
| REPARAR   [−] 20 [+]   metal 40 · petr. 20 · $300    |
|           dura 4 días          [ Reparar ]           |
| [Plantar bandera] [Armar ejército] [Acelerar]        |
+------------------------------------------------------+
```

Contenido y consultas:
- **Vida:** `c.vida` (0–100, `Simulacion.vidaCiudad.maxima`), reparación en
  curso `c.reparacion`, días `Simulacion.diasReparacion(c)`; «sitiada» =
  `sim:sitiada(c)` (la reparación se para). Color de la barra según
  `Simulacion.efectoVida`.
- **Reservas:** `sim:reservas(nid)` (metal, petróleo), `sim:reservaComida(c)`
  (comida de esta ciudad) → barra de recurso 3.4 con estado y días escritos.
- **Defensas:** casillas por plaza como `Tema.casillas`: listas (`verde`),
  recuperándose (rayado `amarillo`), fuera (rayas), vacías. Datos: `c.soldados`,
  `c.tanques`, `c.lanzacohetes`; recuperación `Simulacion.diasRecuperacion(c,
  tropa)`, `Simulacion.precioRecuperacion`.
- **Reparar:** selector de cantidad (1 a `100 − vida − reparacion`, el
  máximo real), coste `Simulacion.costeReparacion(puntos)` con cada cifra en
  `rojoTexto` si falta (`Simulacion.alcanza(n, coste)`); botón amarillo
  «Reparar» → `sim:ejecutar{ tipo='reparar', nacion=nid, ciudad=cid,
  puntos=N }`. Desactivado si `puntos < 1`, con el motivo de `reparar`
  (`pasaDelMaximo`, `coste`, `noEsSuya`) en el tooltip.
- **Plantar bandera:** botón gris que entra en el modo de 5.11.
- **Armar ejército:** hoy «Armar grupo» (`Pendon:armarGrupoDesde`, `sacarTropas`
  con − y +): abre 5.8. **Acelerar recuperación:** `acelerarRecuperacion` con
  su precio.
- Solo los botones de una ciudad **propia** (`jugadorEsPropio`); en las ajenas
  se ven los datos que el jugador conoce y el botón «Atacar» (5.8).
- **1280×720:** panel de 420; la fila de tres botones pasa a dos filas.

### 5.3 Instalación (hoy: `dibujarInstalacion`)

Mismo panel de 480. Cabecera: tipo (`campamento`, `base`, `bandera`… de
`sim:instalacion(id)`) y nación. Contenido: barra de **vida**
(`Simulacion.vidaSitio(i)`), **guarnición** (soldados, tanques, lanzacohetes),
**obra** (`progreso` 0–1 si está en obra), **mantenimiento** de un
campamento (`sim:mantenimientoCampamento(i)`: petróleo al día), estado de
batalla (`sim:batallaEn('instalacion', id)`). Botones (solo si es propia y hay
tropas): «Retirar guarnición» (gris) y «Atacar» (amarillo, si es enemiga).

### 5.4 Mina (hoy: `dibujarYacimiento`)

Panel 480. Cabecera: «Mina de metal» (`tipo`, nombres de `Simulacion.yacimientos`)
y dueño. Consulta única: `sim:mina(id)`.

```
+--- Mina de petróleo · de Voltex ---------[X]+
| RESERVA [████████░░░░] 412 de 750 (riqueza 3)|
| Abierta   · 3 grupos recolectando            |
| RECOLECTORES                                 |
|  Voltex   ejército #12  ida     28/60 +8/día |
|  Voltex   ejército #15  recolecta 40/60 +6   |
| [ Recolectar ]  [ Atacar recolectores ]      |
+----------------------------------------------+
```
- **Reserva:** `queda` sobre `reserva` (la barra); estado: si `cerrada`,
  rayado y «Agotada: cerrada N días» (`diasCerrada`); si `batalla`, aviso
  rojo «Batalla en la mina».
- **Recolectores:** `recolectores` de `sim:mina` (nación, grupo, fase `ida` /
  `recolectando` / `vuelta`, `carga`/`capacidad`, `ritmo` al día); los propios
  con `sim:recolectores(nid)`. Bono de territorio: etiqueta «×1,25 en su
  tierra» si `bonus == dueno` (`ventajaTerritorio`).
- **Botones:** «Recolectar» (amarillo; solo si no está `cerrada`) abre 5.8 en
  modo recolectar; «Atacar recolectores» (rojo; solo si hay ajenos) abre 5.8
  en modo atacar; si hay `batalla`, «Defender» o «Atacar» según el lado
  (5.9).
- **Yacimientos de comida u oro:** igual; el recurso lleva su icono y el oro
  dice «se vende a 8 por unidad» (`precioOro`).

### 5.5 Bandera (hoy: `contenidoBandera`)

Panel 480 corto. `sim:banderas(nid)` → `vida` (0–100), `enObra` y `progreso`,
`atacada`/`atacadaPor` (aviso rojo «Atacada por X»), días que le quedan por
falta de mantenimiento (`mantenerBanderas`). Sin botones para la propia;
«Atacar» (rojo) si es ajena y hay guerra o «Declarar guerra y atacar».

### 5.6 Ficha de ejército y selección/movimiento (hoy: `ficha.lua`; movimiento en rehecho estilo Warpath)

**Ficha:** panel 400×auto, arriba a la izquierda (x = 112 para no tapar la
columna, y = 80). Aquí, y solo aquí, **sigue el Estandarte** (pendón del
ejército 64×96, `mundo/estandartes`).

```
+--- Ejército de Voltex ----------------[X]+
| [Estandarte]  Gral. Kaelen · Cauteloso   |
|               PODER 4 200  (cifraGrande)  |
| Estado: En marcha a Puerto Sol · 3 días  |
| Soldados 120   Tanques 6   Lanzacoh. 2   |
| [ Atacar ] [ Mover ] [ Retirar ]          |
+------------------------------------------+
```
- Datos: `sim:fichaGrupo(gid, nid)`: `nombreNacion`, `lider` (`etiqueta`,
  `caracter`, `victorias`, `derrotas`), `poderRedondeado`, `mision`,
  `retirada`, `batalla`, y `composicion` **solo si es propio**; en ajenos:
  «Composición desconocida».
- Recolector: recurso, `carga`/`capacidad`, ritmo (`sim:recolectores`).
- Botones (los ya existentes en `main.lua`): «Atacar» (amarillo; abre 5.8),
  «Mover» (gris; entra en el modo de colocar destino), «Retirar»
  (gris), y si `batalla`: «Defender»/«Atacar» (5.9) e «Ir».
- **Selección y movimiento (propuesta, hay que confirmar con la rehecha
  estilo Warpath de Valeria; hoy hay varios ejércitos seleccionables,
  `gruposSeleccionados`):** al seleccionar, anillo `amarillo` de 3 px en el mapa y
  chapa «N ejércitos» sobre el mapa abajo (el panel muestra el principal). Con
  «Mover» o clic derecho en el mapa se traza la **ruta** (línea `amarillo` de
  3 px con flecha) y un tooltip al puntero con **días** (`(largo −
  recorrido) / Simulacion.velocidadEjercito`) y el objetivo: «Mover a X · 3
  días» o «Atacar X · tu poder 4 200 contra 3 100» (el poder rival solo si se
  conoce; si no, «desconocido»). Esc cancela.
- **1280×720:** panel de 340; la composición pasa a dos líneas.

### 5.7 Envío y recolección (hoy: `envio.lua`)

Panel central 560×auto (480 a 720p), con fondo `papel` sobre `hormigon` para la parte de
formulario. Dos modos con el mismo diseño:

```
+--- Recolectar en mina de metal ---------------[X]+
| Desde: Puerto Águila                              |
|  Soldados   [−] 100 [+]   hay 300                 |
|  Tanques    [−]   4 [+]   hay  12                 |
|  Lanzacoh.  [−]   0 [+]   hay   4                 |
| Lleva 88 de carga · saca 7,6 al día · ida 3 d,    |
| llenarse 12 d, vuelta 3 d                         |
|                       [ Cancelar ] [ Recolectar ] |
+---------------------------------------------------+
```
- Modo **recolectar:** título «Recolectar en mina de X»; cálculo de carga
  `Simulacion.capacidad`, ritmo `sim:ritmoRecoleccion`, tiempos de ida/vuelta;
  botón amarillo «Recolectar» → `sim:ejecutar{ tipo='enviarGrupo', mision=
  'recolectar', … }`.
- Modo **atacar:** título «Atacar X»; si no hay guerra, el botón dice
  «Declarar guerra y atacar» (rojo); si no, «Atacar» (amarillo). Muestra
  `sim:puedeAtacar(nid, objetivo)`.
- Cada fila: selector de cantidad 3.4; máximo = lo que hay en la ciudad
  (`c.soldados`…); el error de la simulación se muestra en rojo bajo los
  botones. «Cancelar» (gris) o Esc.

### 5.8 Armar ejército (hoy: `Pendon:armarGrupoDesde`)

Igual que 5.7, con título «Armar ejército en X», líder elegible
(`sim:liderLibre`, `sim:lideresDe(nid)`), poder total previsto
(`Simulacion.poderUnidad`) y botón amarillo «Armar». Al armar, el ejército
queda seleccionado y se abre su ficha.

### 5.9 Batallas en curso (hoy: `batallas.lua`, tecla B)

Panel a la derecha bajo la barra, 480 de ancho, tarjetas de fila 72 (sin tope
de filas; rueda). Consulta: `sim:batallasEnCurso(nid)`.

```
+--- Batallas en curso ---------------[X]+
| Puerto Sol           día 4   Ataca      |
|   Voltex 4 200  vs  Karesh 3 100        |
|                    [ Ir ]  [ Atacar ]   |
| Mina de petróleo     día 1   Defiende    |
|   Karesh 900  vs  Voltex 1 100          |
|                    [ Ir ]  [ Defender ]  |
+-----------------------------------------+
```
- Campos: `nombre`, `dias`, `lado` (`atacante`/`defensor`), `atacante.poder`
  y `defensor.poder`, `decidido`, `puedeEntrar`.
- El botón amarillo dice **«Defender»** si `lado == 'defensor'`, **«Atacar»** si
  `lado == 'atacante'` (si `puedeEntrar`); «Ir» (gris) lleva la cámara al
  sitio. Al pulsarlo se abre la batalla (misma acción de hoy, `entrarBatalla`).
- Insignia roja en el botón de la barra inferior con el número de batallas
  propias (la de hoy, `cuenta = 'batallas'`).

### 5.10 Avisos y pregones (hoy: `pregon.lua`, `avisosAtaque`)

Columna de **tarjetas de evento** a la derecha (x = 1920 − 16 − 300 = 1604,
desde y = 80). Si un panel de sitio está abierto, la columna se desplaza 496 a
la izquierda (animación 120 ms). Una tarjeta por aviso, la más nueva arriba.

- **Origen:** los pregones de hoy (`GRAVES`: guerra declarada, cae una
  capital, capital saqueada, bandera atacada / arrancada / perdida, crimen de
  guerra, se rompe el alto el fuego) más `sim:avisosAtaque(nid)` («Ejército
  de X va hacia Y, llega en N días, poder P»).
- **Tarjeta:** miniatura con el icono del tipo (lista de avisos de 7.2),
  título («Bandera atacada»), subtítulo con plazo («cae en 2 días»), botón
  «Ir» (mismo efecto que la tecla X); clic derecho la descarta.
- **Duración:** 8 s a la vista con la barra fina inferior (como hoy).
- **Sin tope:** hoy salen 3 a la vez y 6 en cola. Propuesta: todos los
  avisos salen y la columna baja hasta llegar a la barra inferior; los que no
  caben se acumulan en una tarjeta «+N avisos» que se abre en la lista de
  noticias. No se pierde ninguno.
- **1280×720:** tarjeta de 260 de ancho, miniatura de 64.

### 5.11 Plantar bandera (hoy: `plantar.lua`)

Modo de colocación sobre el mapa (no es un panel):
- Bloque de 6×6 celdas: verde `#6bdc4c` si `sim:puedePlantarBandera(nid, x,
  y)`, rojo `rojo` si no, celdas ajenas rayadas (`sim:duenoCelda`).
- Tooltip junto al puntero (3.4): coste en tres cifras con icono, y si no se
  puede, el motivo en `rojoTexto`. Barra de modo en la parte inferior central
  (alto 48): «Plantar bandera · clic izquierdo planta · clic derecho o Esc
  cancela» con botón gris «Cancelar».
- Clic: `sim:ejecutar{ tipo='bandera', nacion=nid, x=…, y=… }`.

### 5.12 Noticias (hoy: `noticias.lua`)

Panel abajo a la izquierda (x = 112, y = 1080 − 16 − 300, 460×300), abre con
el botón «Noticias» de la barra inferior (hoy tecla N). Cabecera con
pestañas **Todas · Guerra · Diplomacia · Obras**; lista con selección, fila
44, más nueva abajo, **desplazable sin límite de filas** (hoy son 6). Marca a
la izquierda de 4 px por prioridad: `rojo` alta, `amarillo` media, `textoHudTenue`
baja (la clasificación de hoy, `Noticias.clasificar`). Fila cortada: el
tooltip la lee entera. Fuente: `sim.estado.noticias`.

### 5.13 Reparar

Es la sección «Reparar» de la ciudad (5.2), no una ventana aparte: selector
de cantidad, coste por recurso, días y botón amarillo. Detalle de los tres
números: vida que sube `ritmoReparacion(c)` = 2 + nivel al día; coste por
punto `metal 2, petróleo 1, dinero 15` (`Simulacion.vidaCiudad.coste`).
Confirmación: al pulsar «Reparar» la fila de vida muestra `+N` en verde y
la barra se anima 400 ms. Si está sitiada, se avisa «La reparación espera al
final del asedio».

### 5.14 Perfil (nación o comandante) — **nuevo**, familia clara

Estructura tomada de `perfil.jpg`. Pantalla completa (1920×1080; a 1280×720
todo se escala con `e`). Se abre con la chapa de la barra superior o con
«Nación» de la barra inferior. Cabecera clara (72): placa negra de logo,
título «Perfil de la nación» con sombra, y a la derecha la barra de recursos
(metal, petróleo, comida, dinero; sin oro). Esc o el botón de la cabecera
cierran.

```
+[logo] Perfil de la nación --------------------- [metal][petr.][comida][dinero]+
|                                                                                |
|  +====== tarjeta marino (560×640) ======+    Energía (i)                       |
|  | (Nv 8 escudo)     [compartir] [pincel]|    [(rayo)>>>>>>>>>>>>>>>>>>>>][+]  |
|  | [Escudo 120]  ID DE NACIÓN: 42979876   |    +-------------+-------------+    |
|  |   [ Nombre de la nación         ✎ ]    |    | Nv. 3       | Ninguna     |    |
|  |   Servidor / semilla: 165              |    | Capital     | Alianza     |    |
|  | +--------------+------------------+    |    +-------------+-------------+    |
|  | | 12,4 M       |                  |    |    | 1 240       | 48          |    |
|  | | Poder   [E]  |   Nv. 3          |    |    | Territorio  | Ciudades    |    |
|  | +--------------+  Capital         |    |    +-------------+-------------+    |
|  | | [ + guerra ] |                  |    |    | Puerto Águila| 2          |    |
|  | +--------------+------------------+    |    | Capital     | Guerras     |    |
|  |  (M)  (M)  ( + ) ( + ) ( + )           |    +-------------+-------------+    |
|  |                        Medallas [->]   |                                    |
|  +----------------------------------------+   [Más info][Guerras][Territorio][Ajustes]|
+--------------------------------------------------------------------------------+
```

**Tarjeta de comandante** (izquierda, x 168–728, y 140–780; corte 16 abajo a la
derecha, marco `marino`): 
- Arriba, escudo hexagonal con el **nivel de la capital** (`sim:nivelCapital(nid)`)
  a la izquierda y dos botones hexagonales de 56 a la derecha: *Compartir*
  (copia el texto del perfil, fase posterior) y *Personalizar escudo* (fase
  posterior; ocultos hasta entonces).
- **Escudo** de la nación en un disco de 120 (`mundo/estandartes`,
  `sim:colorNacion`), botón pequeño de cambiar (posterior).
- **Identificador de nación** (id de la nación, `sim:nacion(nid).id`) y
  **nombre** en un campo gris `#c8c8c8` de 60 de alto (editable en una
  fase posterior; hoy solo lectura) con su lápiz apagado.
- **Semilla del mundo** en la línea «Servidor» (`sim.estado.semilla`), con la
  «i» que explica que es el mundo compartido.
- **Poder** (`sim:fuerza(nid)`, formato `Tema.numero`) en `cifraGrande`
  `poderMarron`, con el escudo de estrella tenue a la derecha. Debajo, el hueco
  punteado con «+» (fase posterior: título o insignia).
- **Nivel de capital** y su nombre de grado: «Nv. 3 · Capital» (`nivelCapital`);
  el almacén que da (`sim:almacen(nid)`) en `tintaTenue`.
- **Medallas:** cinco huecos; las ganadas (hoy ninguna, no hay logros en la
  simulación) se dibujan como medalla; el resto, hexágono gris con «+».
  Enlace «Medallas →» inactivo hasta que existan.

**Derecha** (x 980–1820):
- **Energía:** rótulo «Energía» + «i» y la barra de energía de 3.5. **Hoy la
  simulación no tiene energía**: se dibuja oculta hasta que el dueño decida
  qué es (**pregunta 1**).
- **Placas de datos 2×3** (250×128 cada una con hueco de 12): datos reales que
  ya existen, orden de lectura:
  1. «Nv. N» — Nivel de la capital (`sim:nivelCapital`).
  2. «Ninguna» — Alianza (fase posterior; hoy siempre «Ninguna»).
  3. Territorio en celdas (`sim:celdasDe(nid)`).
  4. Ciudades (`#sim:ciudadesDe(nid)`).
  5. Nombre de la capital («Puerto Águila»; `sim:ciudad(sim:nacion(nid).capital)`)
     con etiqueta «Capital».
  6. Guerras (`sim:numeroGuerras(nid)`; al pasar el ratón, la lista de
     `sim:guerrasDe(nid)`).
  Lo que Warpath trae y hoy no existe se queda fuera hasta que Andrés lo
  cuente: puntos de batalla, eliminaciones. Estadísticas de partida que sí
  existen y van en el tooltip de la placa 1: victorias y derrotas (suma en
  `sim:lideresDe(nid)`), ejércitos (grupos con `sim.esEjercito(g)`),
  instalaciones (`sim:instalacionesDe(nid)`) y el día (`sim.estado.dia`).
- **Fila de botones hexagonales** (88 cada uno, separación 32, etiqueta debajo,
  insignia roja si hay algo nuevo): **Más info** (lista de estadísticas de
  partida completa, con las de arriba), **Guerras** (lista de guerras con el
  motivo y los días), **Territorio** (cierra el perfil y conmuta la vista de
  territorios, como la tecla T) y **Opciones** (abre 5.15). El botón que se
  acaba de estrenar puede llevar el halo `amarillo` y una flecha amarilla que
  rebota (ayuda de primera vez).
- **1280×720:** la tarjeta baja a 480 de ancho y las placas a 200; los
  botones hexagonales a 72.

### 5.15 Opciones — **nuevo**, familia clara

Estructura tomada de `opciones_1.jpg` y `opciones_2.jpg`: pantalla completa
sobre hormigón; **cuadrícula de dos columnas de botones anchos con icono**
(480×76, separación 32 horizontal y 28 vertical, columnas centradas en
x = 720 y x = 1200), desplazable con la rueda (la barra fina de la izquierda
de la referencia). Cabecera igual a la del perfil, título «Opciones». Cada botón
lleva a una subpantalla; el botón de la cabecera y Esc vuelven.

```
+[logo] OPCIONES --------------------------- [metal][petr.][comida][dinero]+
|      +---------------------------+   +---------------------------+     |
|      | [eng] General          (7)|   | [+] Idiomas               |     |
|      +---------------------------+   +---------------------------+     |
|      | [pers] Comandante        |   | [carita] Emoticones       |     |
|      ...                                                               |
+------------------------------------------------------------------------+
```

**Botones de hoy** (con icono negro de 40, texto `boton` `tinta`):

| Columna izquierda | Columna derecha |
|---|---|
| **General** (pantalla, calidad, sonido) | **Idioma** (solo «Español» hoy) |
| **Comandante** (ver el perfil, 5.14) | **Ayuda y soporte** (lista de teclas y manual corto) |
| **Guardado** (guardar F5, cargar F9) | **Versión** (versión del juego y del estado de la simulación) |

La referencia trae más botones (Roles, Regalos, Eliminar cuenta, Contraseña
secundaria, Cuentas, Emoticones, Términos y privacidad, Prueba de conexión,
Inicio con QR). **Quedan para el juego en línea** (Cuentas, Prueba de
conexión, Términos, Eliminar cuenta) o para cuando exista su mecánica; no se
dibujan hasta entonces. La cuadrícula no tiene tope: si hay más botones, sigue
hacia abajo con desplazamiento.

**Subpantalla General** (filas de formulario sobre `papel`, ancho 1040,
centradas; cada fila 64 con etiqueta a la izquierda y control a la derecha,
separadas por líneas `papelLinea`; pie con «Restablecer» gris y «Aplicar»
amarillo):

```
| Calidad gráfica          [ Alta        ▼]  |
| Resolución               [ 1920 × 1080 ▼]  |
| Pantalla completa        [ (●─) ]          |
| Sincronización vertical  [ (─●) ]          |
| Mostrar FPS              [ (─●) ]          |
| Sombras dinámicas        [ (●─) ]          |
| Oclusión ambiental       [ (●─) ]          |
| Volumen general     ──────●───  70 %       |
| Volumen de efectos  ────────●─  80 %       |
| Volumen de música   (solo si hay música)   |
|                 [ Restablecer ] [ Aplicar ] |
```

- *Calidad gráfica:* baja / media / alta (mismo valor que `--calidad`; niveles
  de `batalla/dream/calidad.lua`: distancias de detalle, sombras y oclusión
  del dibujo de la batalla). Elegirla rellena sombras y oclusión con los
  valores del nivel; tocarlos a mano deja «Personalizada».
- *Resolución:* `love.window.getFullscreenModes`, por defecto la actual.
- *Pantalla completa* y *Sincronización vertical:* `love.window.setMode`.
- *Mostrar FPS:* texto de 16 px arriba a la derecha bajo la barra
  (`love.timer.getFPS()`).
- *Sombras* (`sombra` y `resolucion` del nivel) y *Oclusión ambiental* (`ao`,
  solo al reiniciar: el tooltip lo dice).
- *Volúmenes:* `love.audio.setVolume` (general) y el de efectos; *música* solo
  se dibuja cuando haya música (`assets/sonidos` hoy no la trae).
- **Guardado de ajustes:** `ajustes.lua` en `love.filesystem`, leído al
  arrancar; el argumento `--calidad` gana sobre el archivo. «Aplicar» guarda y
  aplica al momento; «Restablecer» vuelve a los valores de fábrica sin
  aplicar. Si el cambio de resolución falla, vuelve a la anterior y avisa.
- No se dibujan «efectos climáticos» (no hay clima).

## 6. Navegación

### 6.1 Columna de iconos izquierda

x = 16, desde y = 80, botones **72×64**, separación 8, insignia roja cuando
hay aviso pendiente. **Hoy** (cada botón hace lo que su tecla):

| Botón | Tecla | Acción | Insignia |
|---|---|---|---|
| Plantar bandera | P | modo 5.11 (conmutador) | — |
| Último ataque | X | cámara al último ataque | avisos de `avisosAtaque` sin mirar |
| Territorios | T | conmuta la vista de territorios | — |
| Guardar | F5 | guarda la partida | — |

**Fase posterior** (no se dibujan hasta que exista la mecánica): Construir,
Investigación, Misiones, Eventos, Correo. Boceto mínimo: mismo botón de icono
con etiqueta debajo e insignia roja con el número de pendientes, y al pulsar
un panel de lista con selección (izquierda) y detalle (derecha) como 5.9.

### 6.2 Barra inferior

Estilo de `mapa_hud.jpg`: cinco botones rectangulares `caqui` con icono negro
y etiqueta `tinta`, filo negro de 1 px e insignia roja. Centrada, y = 1080 − 16 − 72, alto **72**, botones **120×64** (icono 32 +
etiqueta), separación 8, corte 12; a 720p botones de 104.

| Botón | Abre hoy | Insignia |
|---|---|---|
| Nación | Perfil (5.14) | — |
| Ejércitos | lista de ejércitos propios (`gruposOrdenados` con `esEjercito` de la nación): fila con líder, poder, estado y botón «Ir»; clic selecciona | nº de ejércitos en batalla |
| Batallas | 5.9 (B) | nº de batallas propias |
| Noticias | 5.12 (N) | nº de noticias de prioridad alta sin leer |
| Ajustes | 5.15 | — |

**Fase posterior:** Alianzas (sin mecánica de alianzas), Suministros, Oficiales,
Mapa mundial con minimapa (esquina superior derecha, 264×176, leyenda de 6
colores: tu base, aliado, enemigo, neutral, recurso, evento) y Manual de
tácticas (lista de categorías a la izquierda, imagen y texto a la derecha,
selector «3 / 8»). El **Arsenal** (referencias `arsenal_*.png`) es también de
fase posterior: pestañas anchas con icono (Árbol tecnológico, Producción,
Arsenal, Mejoras, Doctrina), lista de categorías con contador, cuadrícula de
tarjetas de unidad (4 por fila, 176×184), panel de detalle con barras de
estadística, tabla de dos columnas, franja de miniaturas, coste de producción,
selector de cantidad y botón amarillo grande «Producir». Los componentes ya
están en el kit (4); las pantallas se diseñan cuando haya producción.

## 7. Recursos gráficos para Camila

Todo en `assets/interfaz/` (propuesta), a 1× y 2×, con un `indice.lua` que
dé nombre, tamaño, insets y estados (como `assets/estandarte/indice.lua`).
Los iconos son **blancos y lineales** (trazo 2 px a 48) para tintarse por
estado; las imágenes de unidades no se hacen ahora.

### 7.1 9-slice y piezas

| Archivo | Tamaño 1× | Inset | Estados |
|---|---|---|---|
| `marco_doble` (claro) | 48×48 | 12 | 1 |
| `boton_menu` (claro, ancho) | 48×48 | 12 | normal, resaltado, pulsado, desactivado |
| `placa_logo` | 120×56 | 8 | 1 |
| `tarjeta_marino` (perfil) | 96×96 | 24 | 1 (con esquina inferior derecha cortada) |
| `panel_hud` (oliva translúcido) | 48×48 | 12 | 1 |
| `boton_amarillo` | 48×48 | 12 | los 4 |
| `boton_gris` | 48×48 | 12 | los 4 (claro y oliva) |
| `boton_rojo` | 48×48 | 12 | los 4 |
| `boton_hud` (cuadrado oliva) | 24×24 | 8 | los 4 |
| `hex_metal` | 88×100 (y 72, 56) | — | los 4 + destacado con halo |
| `insignia_nivel` (escudo hexagonal) | 48×52 | — | 1 |
| `medalla` | 64×64 | — | ganada (águila) y hueco «+» |
| `insignia_roja`, `insignia_nuevo` | 24×24 y 44×22 | — | 1 |
| `casilla_recurso` (paralelogramo) | 176×44 | 16 | 1 |
| `tarjeta_hud` | 48×48 | 12 | normal, resaltada, seleccionada (`amarillo`) |
| `tarjeta_evento_hud` | 48×88 | 12 | normal, resaltada |
| `barra_energia` (disco, galones, botón «+») | 40 y 44 | — | disco con rayo, galón repetible 22 px |
| `textura_hormigon` | 256×256 tileable | — | 1 (con cuadrícula fina) |
| `textura_oliva` | 128×128 tileable | — | 1 (veta, al 6 %) |
| `chevron_nivel` | 20×20 | — | 1 (posterior) |

Interruptor, deslizador, barras, tooltip, casillas de defensa, rayado y
campos son **dibujo procedural** (los hace Valeria con los colores de 3.2).

### 7.2 Iconos (48×48; blancos lineales sobre el HUD y negros sobre el hormigón; se tintan por código)

- **Recursos (4):** metal, petróleo, comida, dinero (el icono de oro solo
  marca las minas de oro en el mapa y sus paneles).
- **Unidades (7):** soldado, tanque, lanzacohetes, batería, ejército
  (estandarte pequeño), general, escudo de nación (genérico).
- **Órdenes (11):** atacar, defender, mover, retirar, recolectar, plantar
  bandera, reparar, armar ejército, enviar, acelerar, ir (cámara).
- **Avisos (9):** guerra declarada, ciudad sitiada, hambre, bandera atacada,
  alto el fuego, mina agotada, capital saqueada, crimen de guerra, ataque que
  llega.
- **Iconos negros de menú (para los botones anchos de 5.15):** general, comandante,
  guardado, idioma, ayuda, versión, y los posteriores (roles, regalos,
  cuentas, emoticones, conexión, términos).
- **Navegación y sistema (12):** perfil, ejércitos, batallas, noticias,
  territorios, guardar, ajustes, cierre (X), flecha ‹ ›, lupa, filtro, reloj.
- **Categorías del Arsenal (13, fase posterior):** infantería, blindados,
  artillería, misiles, defensa aérea, aviación, helicópteros, drones, marina,
  logística, ingeniería, mando, defensa estratégica.
- **Fase posterior (sin prisa):** construir, investigación, misiones, eventos,
  correo, alianza.

## 8. Fases de implementación

| Fase | Quién | Qué | Jugable cuando… |
|---|---|---|---|
| 1. Cimientos | Camila: `marco_doble`, `panel_hud`, `placa_logo`, `hex_metal`, botones amarillo/gris/rojo, `boton_menu`, texturas, iconos de recursos y de sistema, fuentes. Valeria: `interfaz/tema.lua` nuevo (paleta 3.2, escala igual, `Tema.panel`, `Tema.boton`, `Tema.pestanas`, tooltip) sin quitar el viejo | se ve una prueba de todos los componentes con `--screenshot` | |
| 2. Barra y navegación | Camila: `chapa_nacion`, `casilla_recurso`, `insignia_nivel`, iconos de órdenes | Valeria: barra superior, columna izquierda, barra inferior | se puede jugar con la interfaz nueva arriba |
| 3. Sitios | Camila: `tarjeta`, iconos de avisos | Valeria: ciudad, instalación, mina, bandera, reparar | se ve y repara la ciudad, se manda recolectar |
| 4. Ejércitos y batallas | Valeria: ficha, selección/movimiento (con la rehecha estilo Warpath), envío, armar, batallas en curso, plantar bandera | se juega una guerra completa | |
| 5. Avisos y noticias | Camila: `tarjeta_evento`; Valeria: tarjetas de evento (sin topes), noticias, «+N avisos» | | |
| 6. Perfil y Opciones | Valeria: perfil, opciones, `ajustes.lua`; Andrés: contadores de partida si el dueño los quiere | | |
| 7. Retirada de lo viejo | Valeria: quitar `pendon.lua` (colgante), colores de cuero y bronce y fuentes Alegreya de `tema.lua`; Elena: revisión | no queda pergamino en ninguna pantalla | |
| Después | Diseño (Lucía) + Camila + Valeria | investigación, misiones, eventos, correo, alianzas, manual, mapa mundial, Arsenal | cuando exista la mecánica |

## 9. Casos límite

- **Sin recurso o en crisis:** cifra en 0 y barra rayada (`estado ==
  'crisis'`), nunca un número negativo.
- **Texto que no cabe:** se corta con «…» (`Tema.cortar`) y el tooltip lo dice
  entero; nunca se sale del panel.
- **Panel que no cabe en 720p:** el contenido se desplaza con rueda; la
  cabecera y las pestañas quedan fijas; nada se recorta sin barra de
  desplazamiento.
- **Insignia con más de 99:** «99+» solo por ancho; el tooltip da el número
  exacto.
- **Dos paneles a la vez:** el de sitio y la ficha conviven (ficha a la
  izquierda, sitio a la derecha); Perfil y Opciones son modales: bajo ellos el
  mapa se oscurece al 55 % y no recibe clics; Esc cierra el de arriba.
- **Nación sin capital viva** (nación destruida): la chapa dice «Sin nación»,
  los recursos en 0 y solo se puede mirar.
- **Modo observador (sin jugador):** no hay botones de orden, la barra muestra
  la nación que se mira.
- **Ventana cambiada de tamaño:** todo se recoloca en el mismo cuadro con la
  nueva `e`.

## 10. Dependencias

- **Economía:** [economia.md](economia.md) (decidido el 2026-09-30) da al
  Arsenal la orden `producir`, los costos y días (`Simulacion.produccion`),
  los motivos de rechazo (`puedeProducir`) y la munición; al envío, la
  munición que se lleva un grupo; a la barra, un solo dinero (el tesoro).
- **Lee** (solo consultas, no cambia reglas): `mundo/simulacion.lua`
  (`almacenDe`, `reservas`, `reservaComida`, `mina`, `recolectores`,
  `banderas`, `batallasEnCurso`, `avisosAtaque`, `fichaGrupo`, `guerrasDe`,
  `fuerza`, `nivelCapital`, `celdasDe`, `lideresDe`, `costeReparacion`,
  `puedePlantarBandera`). Documentos que la interfaz muestra y que deben
  nombrarla: `territorio-y-capitales.md`, `recoleccion-y-batallas.md`,
  `ejercitos-en-el-mapa.md`, `instalaciones-y-economia.md`,
  `naciones-y-politica.md`. Ellos no cambian.
- **Catálogo de armamento:** [catalogo-armamento.md](catalogo-armamento.md)
  (propuesto el 2026-09-30) da al Arsenal la ficha real y la de juego de cada
  modelo, su era y la categoría «Misiles» (§3.8 de ese documento).
- **Sustituye** al «Estandarte colgante» (`interfaz/pendon.lua`,
  `travesano.lua`, `placa.lua`, y los colores y fuentes de `tema.lua`).
  `placa.lua` (nombre de la ciudad en la que estás) se convierte en una
  etiqueta pequeña bajo la barra superior, centrada.
- **Opciones** depende de `batalla/dream/calidad.lua` y de `--calidad` de
  `main.lua`.
- **Camila** depende de esta lista; **Valeria** depende de los recursos de
  Camila fase por fase.

## 11. Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `e` mínimo | 0,8 | 0,7–1 | tamaño de todo a 720p; bajo 0,7 el texto de 14 queda en menos de 10 px |
| Alto de barra superior | 64 | 56–72 | espacio del mapa |
| Ancho de panel de sitio | 480 | 420–560 | cuánto mapa tapa |
| Duración de la tarjeta de evento | 8 s | 5–15 s | cuánto tarda en irse un aviso |
| Retardo del tooltip | 300 ms | 150–600 | comodidad |
| Opacidad de sombra | 0,22 / 0,14 / 0,08 | ×0,5–×1,5 | peso visual de los paneles |
| Corte de esquina | 12 / 6 / 4 | 8–16 / 4–8 / 2–6 | carácter del estilo; mayor de 16 se come el contenido |
| Duración de animaciones | 120 ms | 0–250 | 0 = sin animación |

## 12. Criterios de aceptación

Con `love . --screenshot ruta.png N` a **1920×1080 y a 1280×720** (dos
capturas por pantalla), y un script que calcule contraste y mida cajas:

1. **Barra superior:** las cuatro cifras (metal, petróleo, comida, dinero) visibles y con igual valor que `sim:almacenDe` /
   `sim:reservas`, la del dinero en `amarilloDinero`; alto de la cifra ≥ 14 px reales.
2. **Contraste:** todo texto ≥ **4,5:1** contra su fondo real (medido en la
   captura); los cuatro estados de reserva se distinguen también sin color
   (verde, texto «JUSTO», «ESCASEZ», rayado).
3. **Sin recortes:** en ninguna pantalla hay texto fuera de su caja ni panel
   fuera de la ventana, en ninguna de las dos resoluciones.
4. **Sin colores viejos:** ninguna captura contiene los del pergamino
   (`#eadcb8`, `#b08a4f`, `#2b1e15`) ni los del acero azulado anterior
   (`#141c24`, `#1c242c`, `#cca45c`), salvo el Estandarte de la ficha de ejército.
4b. **Dos familias:** en la captura del perfil y de opciones, el 70 % o más de
   los píxeles del fondo están a menos de 12 pasos (por canal) de `hormigon` o
   `hormigonSombra`; en la del HUD sobre el mapa, cada panel mide entre `oliva`
   y `olivaNegro` con opacidad 0,78 ± 0,05; los botones anchos del menú
   tienen el doble borde negro (3 + 2 + 1 px) en las esquinas.
4c. **Forma militar:** los botones de perfil, columna y menú radial son
   hexágonos de metal (`hexMetal`) y las insignias de aviso son rojas
   (`rojo`); la barra de energía tiene los galones (`verdeGalon`).
5. **Botones:** ninguno menor de 35×35 px reales; los cuatro estados de cada
   botón se ven distintos (diferencia de luminosidad ≥ 8 %).
6. **Ciudad de prueba** (escenario `sim:escenarioPrueba`): la captura de la
   ciudad muestra vida, tres reservas, defensas, coste de reparar y los
   botones «Reparar» y «Plantar bandera»; tras pulsar «Reparar» con 20 puntos,
   `c.reparacion == 20` en la simulación.
7. **Mina:** la captura muestra `queda`/`reserva` y una fila por cada grupo
   de `sim:mina(id).recolectores`.
8. **Batallas:** con N batallas propias hay N filas (probar con 12, más que
   los 8 de hoy) y se llega a la última con la rueda.
9. **Avisos:** con 5 avisos simultáneos salen 5 tarjetas (no 3) y ninguna se
   pierde.
10. **Perfil y Opciones:** el perfil tiene la tarjeta marino con id, nombre y
    poder a la izquierda y seis placas 2×3 más la fila de cuatro hexágonos a
    la derecha, con los datos reales (guerras = `sim:numeroGuerras`,
    territorio = `sim:celdasDe`); Opciones muestra una cuadrícula de 2 columnas
    de botones anchos con icono; en Opciones, cambiar
    calidad a «baja», aplicar y reiniciar deja la misma calidad que
    `--calidad baja`.
11. **Botones de batalla:** ningún texto de botón ni de aviso describe cómo se
    dibuja la batalla; solo dicen «Defender», «Atacar», «Ir», etc.
12. **Rendimiento:** con todos los paneles abiertos la interfaz cuesta menos
    de 1 ms por cuadro (medido con `love.timer`); **falta medirlo**, no hay
    cifra hoy.

## 13. Decisiones del dueño y preguntas abiertas

**Decidido:**
1. **DECIDIDO, el oro:** oro y dinero son el mismo recurso; cuatro recursos en
   la barra (metal, petróleo, comida, dinero); ni casilla de oro ni «oro en
   camino».
2. **DECIDIDO, contenido mixto:** claro en perfil, opciones y formularios;
   oscuro en listas de tarjetas y detalle. Tras la corrección de Warpath, lo
   claro es el **hormigón** con texto negro y lo oscuro es el **oliva/caqui**
   translúcido (ya no el azul acero del Arsenal).
3. **DECIDIDO, fuente:** Barlow Condensed y Barlow Semi Condensed, ya en
   `assets/fuentes/` (las condensadas no tienen Bold: se usa SemiBold).
4. **DECIDIDO (2026-09-30), estilo y colores de Warpath original**, con las
   capturas de `diseno/referencias-warpath/`.

**Pregunta abierta (1):**
1. **La barra de energía del perfil.** Warpath tiene energía (460/200) y la
   simulación de Nations RTS **no tiene ninguna**. Opciones:
   (A) no dibujarla hasta que haya una mecánica que la use; (B) mostrar
   una barra con un dato que sí exista, por ejemplo la **fracción de ciudades
   con comida holgada** o el **poder disponible** del ejército, con galones y
   el mismo aspecto; (C) que Andrés añada una energía de mando (recurso que
   gasta cada orden de ejército y se recupera con el tiempo), sin tope
   artificial: si pasa del máximo, la barra dice «460/200» como en la
   referencia. **Recomiendo A**: una barra que no significa nada es
   decoración, y C es una regla nueva de juego que decide el dueño.

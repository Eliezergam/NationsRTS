# Interfaz de la batalla 3D: inventario para rehacerla en UMG

Lucía, 2026-10-03. Encargo de Bruno para el paso B5 de `plan-traspaso-ue5.md`
(«Interfaz de batalla») y la parte de interfaz del B6 (despliegue).

Qué es este documento: la lista de todo lo que se ve y se maneja hoy en la
batalla 3D de LÖVE (etiqueta `love-final-2026-10-03`), de qué datos sale y en
qué archivo y línea está, para que Valeria la rehaga en UMG con el mismo estilo
militar (`interfaz-militar.md`). Se marca así:

- **[Hoy]**: lo que hace el código de LÖVE. Es la referencia del traspaso.
- **[Nuevo, aún no está en LÖVE]**: viene de `VISION.md` §4 y no existe en
  ningún archivo de hoy.
- **[Propuesta]**: idea de Lucía; espera el visto bueno del dueño.

Las rutas son relativas a `NationsRTS/`. Las capturas de referencia (sin
pantalla, mirada cada una con Read) están en la carpeta temporal de la sesión,
`…/scratchpad/lucia_ui_batalla_*.png` (lista en el §9).

---

## 1. Resumen

La batalla de hoy tiene poca interfaz y casi toda es texto. Son cinco cosas
en pantalla y dos marcas sobre el terreno:

| # | Elemento | Cuándo se ve | Dónde está hoy |
|---|---|---|---|
| E1 | Pantalla de carga «Generando campo de batalla» | al entrar, mientras se genera | `batalla/carga.lua:18-95` |
| E2 | Rótulo de la batalla (arriba a la izquierda) | siempre | `batalla/escena.lua:728-879` |
| E3 | Panel de preparación (contador y «Listo») | en la preparación | `batalla/despliegue_vista.lua:270-358` |
| E4 | Zonas de despliegue sobre el terreno, con su nombre | en la preparación y 0,6 s después | `batalla/despliegue_vista.lua:118-256` |
| E5 | Selección: anillo de datos, rótulo de la unidad, cinta de ruta, destino, blanco en rojo, cuadro | con unidades elegidas | `batalla/control.lua:436-492`, `batalla/marcas_holo.lua`, `anillo_holo.lua`, `cinta_holo.lua` |
| E6 | Avisos «Sin balas / obuses / misiles» sobre las unidades | si a una unidad propia le falta munición | `batalla/escena.lua:895-953` |
| E7 | Aviso de fin de batalla (centro) | cuando un bando pierde, 6 s hasta volver | `batalla/escena.lua:589-624` |

**No hay hoy:** minimapa, barra de órdenes con botones, retrato o tarjeta de
la unidad elegida, barras de vida flotantes (la vida solo se ve en el arco
del anillo de la elegida), barra de munición por unidad, cursor que cambie
según la orden, resaltado al pasar el ratón sobre una unidad ni pantalla de
resultados (el resultado solo se imprime en la consola, `main.lua:2808-2850`).
Tampoco hay menú de pausa: P congela la pelea y lo dice el rótulo.

El orden de dibujo es `EscenaDream:dibujar` (`batalla/dream/escena.lua:1323-1337`):
escena 3D, efectos, zonas (E4), selección (E5), avisos (E6), rótulo (E2, que
dibuja dentro el fin, E7) y panel de preparación (E3). Encima va la marca de
depuración «Comparador 3DreamEngine (--dream)» abajo a la izquierda
(`batalla/dream/escena.lua:1334-1335`), que no se pasa a UE.

---

## 2. Fantasía del jugador

Un comandante que mira el campo desde arriba, como en Bannerlord o Total War,
y luego baja a pie entre sus tanques. La interfaz debe quedarse fuera del
paso: poca cosa en pantalla, la información sobre las propias unidades
(anillo, cinta y avisos) y una sola placa de mando con el estilo del resto del
juego (acero oscuro, dorado y gris claro). Con el soldado del jugador
(**[Nuevo]**, §3.4) la fantasía pasa a ser la de un sargento que pelea y da
órdenes a su tropa con F1-F3, sin soltar el arma.

---

## 3. Reglas: inventario de lo que hay hoy

### 3.1 Elementos de pantalla

#### E1. Pantalla de carga **[Hoy]**
- **Qué muestra:** fondo casi negro con dos sierras de montañas en polígonos
  planos, el título «GENERANDO CAMPO DE BATALLA», la etapa en curso
  («Desplegando los ejércitos», «Preparando colisiones físicas»,
  «Preparando materiales e iluminación», «Preparando las rutas de las
  órdenes», «Campo de batalla listo»…), una barra de progreso redondeada y el
  porcentaje.
- **Datos:** `Carga.mostrar(etapa, progreso)` que llaman `Escena.nueva`
  (`batalla/escena.lua:169-204`) y `EscenaDream.nueva`
  (`batalla/dream/escena.lua:554-…`); progreso de 0 a 1.
- **Medidas:** barra de `min(620, 62 % del ancho)` × `max(10, 1,4 % del alto)`
  al 68 % del alto; título al 55 %, etapa al 60 %.
- **Aviso:** no usa la paleta ni Barlow (colores propios y la fuente por
  defecto de LÖVE). En UE debe pasar al estilo militar (§8, ajuste A4).
- **Captura:** no se pudo sacar (se dibuja y se presenta dentro de la carga, antes
  del primer cuadro que captura el arnés). Descrita por el código.

#### E2. Rótulo de la batalla **[Hoy]**
Placa `olivaNegro` al 82 % con filo `lineaOliva`, arriba a la izquierda a 16
de diseño del borde, ancho según la línea más larga. Fuente Barlow Semi
Condensed Medium (`Tema.fuente('sans', 12)`: 13 px reales a 1080, 12 a 720).
Líneas, en orden (`batalla/escena.lua:776-879`):

1. Estado, en tenue: «Batalla 3D · el mundo sigue al 25 %» y, si toca,
   «· unidades forzadas para la prueba», «· combate de prueba (no está en la
   simulación)», «· PREPARACIÓN: combate en pausa», «· PAUSA».
2. Por cada bando (`lineasBando`, `escena.lua:728-773`), en el color de su
   nación: «Ataca|Defiende  <nación>: <en pie>/<total> soldados (escuadras de
   N) · N tanques en pie[, N averiados][, N en reserva] · N lanzacohetes en
   pie[…]».
3. Debajo de cada bando: «Munición: N balas · N obuses · N misiles» o «sin
   límite (combate de prueba)», o «sin informe» si es el bando ajeno (lo ajeno
   no se sabe sin informe, decisión del dueño). Detrás, en `rojoTexto`, los
   avisos «Sin obuses (3 tanques)», etc.
4. Si la batalla acabó: «<nación> se retira: sin munición…» en `amarillo`.
5. Depuración, en tenue: «Terreno procedural · semilla · centro X/Y · rutas de
   avance N»; «Pelea m:ss · fuera de combate A y B · triángulos · plantas ·
   generado en s · FPS»; «Cámara · Altitud … · Altura sobre suelo/agua …».
6. Ayuda de controles, en tenue: 3 líneas en vista RTS o 2 a pie (§3.3).

- **Datos:** `self.combate` (nombres, colores, `ladoJugador`, `forzado`,
  `provocado`), `Tropas:recuento()` (`batalla/tropas.lua:3329`),
  `Tropas:municionBando(k)` (`limitada`, `lleva`, `gastado`), `tropas.reloj`,
  `tropas.bajas`, `self.suelo` (triángulos, plantas, segundos, pasillos),
  `camara:alturas()`, `love.timer.getFPS()`, `self.fin`.
- **Guarda** `self.altoRotulo`, que usan los avisos (E6) para no pisarlo.
- **Capturas:** todas; 13 líneas a 1080 ocupan 680 × 195 px.

#### E3. Panel de preparación **[Hoy]**
Abajo en el centro, a 28 de diseño del borde inferior, ancho mínimo 440 de
diseño (`DespliegueVista.ancho`), con `Acero.panel` (9-slice `panel_acero`
levantado hacia el caqui) y entrada deslizada de 24 px (`Vida.entrar`).
(`batalla/despliegue_vista.lua:270-358`.)

- Fila 1: «PREPARACIÓN» (`subtitulo`, `textoHud`) y debajo «Combate en pausa:
  nadie dispara ni avanza» (`etiqueta`, tenue); a la derecha el contador
  «m:ss» en `cifraGrande`, `amarillo`, que pasa a `rojoTexto` con 10 s o menos.
- Separador (`Acero.separador`).
- Fila 2: dos columnas, cada una con un cuadradito del color de la nación y
  «Tú: organizando|listo» y «Rival: organizando|listo» (`verde` si listo).
- Botón dorado «Listo» de 260 × 46 de diseño; tras pulsarlo, desactivado con
  «Esperando al rival».
- **Datos:** `Despliegue` (`batalla/despliegue.lua`): `duracion` 120 s,
  `segundosRestantes()`, `listos[1..2]`, `propio`, `terminada`; colores de
  `combate.atacante/defensor`.
- **Clic:** `DespliegueVista:sobreListo` (`:361`) desde `Escena:pulsar`
  (`batalla/escena.lua:1017-1045`).
- **Capturas:** `lucia_ui_batalla_preparacion_1080.png` y `_720.png`.

#### E4. Zonas de despliegue sobre el terreno **[Hoy]**
- Borde de cada zona en el color de su nación, pegado al suelo punto a punto
  (cada 150 px de mundo, 15 m), con una franja por dentro de 30 m que se
  desvanece (opacidad 0,32 junto al borde). El interior no se tiñe.
- Nombre en el centro de la zona: «TU ZONA DE DESPLIEGUE» / «ZONA ENEMIGA»,
  `subtitulo` en el color de la nación con contorno `olivaNegro`
  (`Acero.textoContorno`); no se dibuja si pisaría el panel E3.
- Se funden en 0,6 s al empezar el combate.
- **Datos:** `Despliegue.zonas[i]` (`dMin`, `dMax`, `lMin`, `lMax` en ejes de
  la batalla), `combate.angulo`, la altura del suelo.
- **En UE es una marca del mundo, no UMG** (decal o malla sobre el terreno,
  como dice el B6); solo el nombre podría ir en UMG.
- **Captura:** en `lucia_ui_batalla_preparacion_*.png` se ve el borde (la
  línea verde que cruza la pantalla), pero no el nombre: con el encuadre de
  la preparación el centro de la zona queda fuera de la vista.

#### E5. Selección y órdenes **[Hoy]**
Todo se dibuja sobre el terreno, proyectado, con dos shaders
(`batalla/marcas_holo.lua`, cabecera 1-21). Colores holográficos propios, que
**no** son los de la paleta: menta `#6DFFC4`, menta claro `#D9FFF0`, amarillo
`#FFD15C` y rojo `#FF5A5A` (`marcas_holo.lua:31-34`).

| Marca | Qué es | Datos | Archivo |
|---|---|---|---|
| Anillo de datos | Arco de 270° con la vida (menta > 60 %, amarillo 30-60 %, rojo < 30 %), 24 marcas que giran a 1,2 rad/s, entrada de 0,4 s (0,7 s el arco de vida). Abraza al vehículo (0,42 de su largo + 0,4 m), nunca menos de 14 px de radio en pantalla | `unidad.vida / vidaMax`, `modelo`, segundos desde que se eligió | `marcas_holo.lua:266-285`, `anillo_holo.lua` |
| Rótulo de la unidad | «T-72B · 04» (modelo del catálogo y número) en JetBrains Mono SemiBold, menta claro, 18 px bajo el anillo; si pisa otro rótulo, no se dibuja | `CatalogoModelos.modelo(u.modelo).nombre`, `u.numero` | `marcas_holo.lua:250-254`, `:302-342` |
| Cinta de ruta | «Rejilla holográfica»: dos bordes de luz, líneas transversales que avanzan, flechas hacia el destino; nace en la unidad y se acorta al avanzar; anillo que late en el destino | `unidad.orden.ruta`, `orden.paso` | `control.lua:417-434`, `cinta_holo.lua` |
| Marcador de destino | Dos anillos que laten (17 m de radio) y un punto, verdes 1,6 s; rojos si no hay ruta | `Control.marcas` | `control.lua:399-414`, `:466-483` |
| Blanco atacado | Anillo rojo `#F56B52` alrededor del enemigo que ataca la selección; al dar la orden se abre y se apaga en 1,6 s | `orden.blanco` | `control.lua:459-482` |
| Cuadro de selección | Rectángulo menta al 12 % con borde al 90 % | `Control.caja` | `control.lua:484-491` |

- **En UE son materiales y decals sobre el terreno, no UMG** (el plan lo
  dice así en B5). Solo los rótulos de unidad pueden ir en UMG.
- **Capturas:** `lucia_ui_batalla_seleccion_mover_1080.png` (cintas, destinos
  y rótulos), `_atacar_1080.png` (blanco en rojo), `_lanzacohetes_1080.png` y
  el recorte `lucia_ui_batalla_seleccion_recorte.png`. Salen del arnés
  `batalla/pruebas_control`, que solo hace 1920 × 1080.

#### E6. Avisos de munición sobre las unidades **[Hoy]**
- Encima de cada unidad propia en pie sin munición: un rombo `rojo` con filo
  `olivaNegro` y, si cabe sin pisar otro aviso ni el rótulo E2, una placa
  `olivaNegro` al 80 % con «Sin balas», «Sin obuses» o «Sin misiles» en
  `rojoTexto` (12 px). Los más cercanos a la cámara van primero.
- Solo las propias cuando se juega un bando; todas si se mira sin bando.
- **Datos:** `Tropas.sinMunicion(u)`, `Tropas.gastoDisparo(u)`, la cámara.
  (`batalla/escena.lua:895-953`.)
- **Captura:** no sale. Los combates de prueba van con munición sin límite y
  no encontré un arnés que deje a una unidad sin munición.

#### E7. Aviso de fin de batalla **[Hoy]**
- Placa centrada al 30 % del alto, `olivaNegro` al 90 % con borde `amarillo`
  de 2 px: título «<nación> se retira: sin munición con la que dañar al
  rival» / «…: no alcanza al rival» / «<nación> queda fuera de combate» en
  `amarillo` (21 px a 1080) y debajo «Gana <nación> · la batalla termina ·
  vuelta al mapa en N s (Esc, ya)» en `textoHud` (14 px).
- La misma frase sale también como línea amarilla del rótulo E2.
- **Datos:** `Tropas:fin()` → `{ pierde, retira, motivo }`; `Tropas.cierre`
  = 6 s (`batalla/tropas.lua:132`); `Escena:vigilarFin` (`escena.lua:568-583`).
- **Capturas:** `lucia_ui_batalla_fin_1080.png` y `_720.png`.

### 3.2 Lo que ocurre al salir
Tras los 6 s del fin, o con Esc sin selección, `main.lua` vuelve al mapa y
manda el resultado a la simulación (`salirDeBatalla`, `main.lua:2808`). El
jugador no ve ninguna pantalla de resultados.

### 3.3 Controles **[Hoy]**

Sacados de los callbacks reales: `love.mousepressed` (`main.lua:4398`, pasa a
`Escena:pulsar` en `:4407`), `love.mousemoved` (`:4502` → `Escena:mover`),
`love.mousereleased` (`:4533` → `Escena:soltar`), `love.wheelmoved`
(`:2716` → `Escena:rueda`), `love.keypressed` (`:4594` → `Escena:tecla`) y
`love.focus` (`:4576` → `Escena:foco`). En la batalla, ningún evento llega al
mapa.

**Vista RTS (cámara libre)**

| Entrada | Efecto | Código |
|---|---|---|
| Clic izquierdo sobre unidad propia | La elige sola (radio de clic 28 px) | `Escena:soltar` `escena.lua:1099`; `Control:click` `control.lua:187` |
| Clic izquierdo en el vacío o en un enemigo | Vacía la selección | ídem |
| Mayús + clic | Suma o quita esa unidad (con Mayús no hay doble clic) | ídem |
| Doble clic (≤ 0,35 s) | Todas las propias de ese tipo que se ven | `Control:tipoAVista` `:213` |
| Arrastrar con el izquierdo (> 6 px) | Cuadro; al soltar elige las propias de dentro (con Mayús, suma) | `Escena:mover` `:1071`; `Control:elegirCaja` `:247` |
| Clic derecho corto (sin arrastrar) sobre enemigo | ATACAR con toda la selección | `Control:ordenar` `:278` |
| Clic derecho corto sobre el terreno | MOVER en formación por terreno transitable; marcador rojo si no hay ruta | `Control:moverA` `:300` |
| Derecho mantenido y arrastrar | Mirar: gira la cámara (ratón capturado, 0,005 rad por px) | `Escena:pulsar` `:1017`, `Camara:arrastrar` |
| Rueda | Avanza o retrocede 16 m por paso hacia la mirada, con inercia; Shift × 3 | `Camara:avanzar` `camara.lua:328` |
| W / S | Vuela hacia donde mira (en 3D) / hacia atrás | `controlador_camara.lua:92-130` |
| A / D | A los lados | ídem |
| Espacio / Ctrl | Sube / baja | ídem |
| Shift | × 3 la rapidez de WASD, Espacio, Ctrl y rueda | `controlador_camara.lua:101` |
| T / L / I | Todos los tanques / lanzacohetes / escuadras propios (con Mayús, se suman) | `Escena:tecla` `escena.lua:974-1014` |
| H | MANTENER POSICIÓN a la selección (no en la preparación) | ídem; `Control:mantener` `:357` |
| P | Pausa (también para el contador de la preparación) | ídem |
| V | Bajar a pie donde mira la cámara / volver | `Escena:entrarPie` `:956` |
| Esc | Si se está girando, suelta; si hay selección, la vacía; si no, vuelve al mapa | `Escena:tecla` |
| Clic izquierdo en «Listo» | Marca listo al jugador (preparación) | `Escena:pulsar` |
| Perder el foco (Alt+Tab) | Cancela el gesto, suelta el ratón y para la cámara | `Escena:foco` `:1059` |

Rapidez de vuelo: 8 m/s + 0,42 × altura sobre el suelo, hasta 200 m/s
(`camara.lua:39-41`). En la preparación la cámara no sale de la zona propia.
Clic derecho en la preparación: no da órdenes (la colocación de unidades del
diseño, `batalla-despliegue-y-movimiento.md` §4, aún no está).

**A pie (V)** (`batalla/caminante.lua:1-34`, `:100-135`)

| Entrada | Efecto |
|---|---|
| Ratón (sin botón, capturado) | Mira (0,003 rad por px, ± 85°) |
| W/S/A/D o flechas | Caminar 1,4 m/s |
| Shift | Correr 4,5 m/s |
| Espacio | Saltar (0,5 m) |
| V o Esc | Vuelve a la vista RTS como estaba |
| T/L/I, H, P | Igual que en RTS |
| Clics | No hacen nada |

El caminante es un observador: no encarna a ninguna unidad, no tiene arma ni
retícula y no le disparan. No hay HUD propio a pie; el rótulo E2 cambia sus
líneas de ayuda. Captura: `lucia_ui_batalla_a_pie_1080.png`.

### 3.4 Lo nuevo de VISION **[Nuevo, aún no está en LÖVE]**

De `VISION.md` §4 y `decisiones.md` (2026-10-02); las órdenes, del GDD
(«Órdenes tácticas»). Es la etapa C6 del plan, después de B1-B7.

- **El soldado del jugador en tercera persona.** Cámara detrás del hombro por
  defecto. Pide en UMG: retícula, munición del arma (cargador y reserva),
  vida del soldado y un indicador de daño.
- **Primera persona con una tecla.** Misma interfaz, sin el cuerpo.
- **Órdenes F1-F3 a su tropa** (GDD):
  - **F1 Movimiento:** ir a posición; mantener / cobertura; avanzar
    disparando; retirada táctica.
  - **F2 Formación y espaciado:** línea de tiradores; cuña táctica;
    dispersión antiaérea; cobertura urbana.
  - **F3 Reglas de enfrentamiento:** fuego a discreción; alto el fuego;
    fuego de supresión; priorizar blindados / infantería.

**[Propuesta]** de cómo se ve, copiando Bannerlord (la referencia de la
batalla): al pulsar F1, F2 o F3 aparece abajo en el centro una tira de
botones numerados («1 Ir a posición», «2 Mantener»…), que se eligen con 1-4
o con el ratón; Esc o la misma F cierran la tira. Mientras está abierta, el
juego no pausa y el jugador puede seguir moviéndose. Una línea arriba dice la
orden vigente de cada grupo. No hay referencia visual del dueño para esto;
antes de construirlo hay que enseñarle variantes (`forma-de-trabajar.md`).

**Conflictos de teclas que hay que resolver:** hoy, en el mapa, F1 centra la
cámara en la primera tropa propia (`main.lua:4684`). En la
batalla F1-F3 están libres. V hoy baja a pie; con el soldado propio no hace
falta bajar (ya está en el campo). Ver la decisión D2 (§10).

---

## 4. Fórmulas: escala, tamaños y colores

### 4.1 Escala de la interfaz de hoy
`e = Tema.FACTOR × max(0,8; alto / 1080)`, con tope `ancho / 1920 × 1,25` si
la pantalla es más estrecha que 16:9 (`interfaz/tema.lua:56-70`).
`Tema.FACTOR = 0,6` (el dueño pidió la interfaz a la mitad el 2026-09-30).

- Medidas: `px(v) = round(v × e)`.
- Texto: `tam = max(mínimo; round(base × e × 1,5))`, mínimo 12 (10 en
  etiquetas).

| Pantalla | e | Panel de 440 de diseño | Texto de diseño 20 |
|---|---|---|---|
| 1920 × 1080 | 0,60 | 264 px | 18 px |
| 1280 × 720 | 0,48 | 211 px | 14 px |

Ejemplo: el contador de la preparación (`cifraGrande`, 36) sale a
`round(36 × 0,6 × 1,5) = 32 px` a 1080 y `round(36 × 0,48 × 1,5) = 26 px` a
720.

### 4.2 Tamaños reales a 1080 (lo que debe medir en UE)

| Estilo | Fuente | Diseño | px a 1080 | px a 720 |
|---|---|---|---|---|
| `titulo` | Barlow Condensed SemiBold | 26 | 23 | 19 |
| `subtitulo` | Barlow Condensed SemiBold | 20 | 18 | 14 |
| `cuerpo` | Barlow Semi Condensed Medium | 18 | 16 | 13 |
| `cifra` | Barlow Semi Condensed SemiBold | 22 | 20 | 16 |
| `cifraGrande` | Barlow Condensed SemiBold | 36 | 32 | 26 |
| `boton` | Barlow Condensed SemiBold | 22 | 20 | 16 |
| `etiqueta` | Barlow Semi Condensed Medium | 14 | 13 | 10 |
| `ayuda` | Barlow Semi Condensed Medium | 16 | 14 | 12 |
| rótulo E2 (`sans` 12) | Barlow Semi Condensed Medium | 14,4 | 13 | 12 |
| fin E7 título / detalle | Barlow Semi Condensed Medium | 24 / 15,6 | 22 / 14 | 17 / 12 |
| rótulo de unidad (E5) | JetBrains Mono SemiBold | 10 × ui | 13 | 11 |

(`ui = max(1; alto / 1080 × 1,25)`, `marcas_holo.lua`; por eso el rótulo de
unidad no baja igual que el resto.)

**Trampa de UE (a comprobar con una captura en UE):** el tamaño de fuente de
UMG va en puntos a 96 ppp, así que 1 punto son 1,33 px. Para que un texto
mida 18 px hay que poner 13,5 en UMG. Si no se convierte, todo sale un tercio
más grande.

### 4.3 Colores de la vida en el anillo
`f = vida / vidaMax`; menta si `f > 0,6`, amarillo si `0,3 ≤ f ≤ 0,6`, rojo si
`f < 0,3`. Ejemplo: un T-72B con 410 de 1000 → 0,41 → amarillo.

### 4.4 Contador de la preparación
`restante = 120 − tiempo con el combate sin pausa`; `amarillo` si
`restante > 10`, `rojoTexto` si `≤ 10`. Empieza el combate cuando los dos
bandos están listos o `restante = 0`.

---

## 5. Casos límite (lo que hace hoy)

- **Muchas unidades elegidas:** los rótulos de unidad que se pisarían no se
  dibujan (`marcas_holo.lua:315-330`); los anillos sí.
- **Avisos E6 que no caben:** se dibuja el rombo y se omite el texto.
- **Unidad que muere o se retira estando elegida:** sale de la selección en el
  siguiente cuadro (`Control:actualizar`, `control.lua:364`).
- **Orden de mover sin ruta posible:** marcador rojo durante 1,6 s y la unidad
  no se mueve.
- **Esc con el derecho pulsado (girando):** solo suelta el ratón, no sale.
- **Alt+Tab a pie:** el ratón queda libre fuera de la ventana y se vuelve a
  capturar al volver.
- **Pausa en la preparación:** el contador también para.
- **Nombre de zona tapado por el panel:** no se dibuja.
- **Bando ajeno:** su munición sale como «sin informe»; sus unidades sin
  munición no llevan aviso.
- **Mirar sin bando (observador):** no hay «sin informe» y los avisos salen en
  los dos bandos.
- **Fin de batalla a pie:** al cerrarse la batalla se sale de a pie primero
  (`escena.lua:540-543`).
- **Texto que no cabe en un botón:** se corta con «…» (`Acero.boton`).

---

## 6. Dependencias

**De qué depende la interfaz de la batalla en UE:**
- La simulación de batalla en Mass (Andrés y Valeria, B1-B4): recuento por
  bando, munición por bando, vida y orden de cada unidad, fin de batalla.
  Hoy son `Tropas:recuento`, `Tropas:municionBando`, `Tropas:fin`,
  `Tropas.sinMunicion`.
- El despliegue (B6): zonas, contador, listos.
- El kit de UMG (§7.2) y las piezas de `assets/ui/` (Camila).
- El catálogo de modelos para el nombre de cada unidad.
- **[Propuesta]** Un único objeto «vista de la batalla» (subsistema o
  `UObject`) que copie en cada cuadro lo que la interfaz necesita, para que
  los widgets no lean Mass directamente. Lo decide quien programe B5.

**Qué depende de ella:**
- Las pruebas de automatización que inyectan Enhanced Input (lo que hoy hace
  `batalla/prueba_raton.lua`) necesitan conocer el rectángulo de «Listo».
- Elena (`pruebas-aceptacion-batalla.md`, en curso) y Andrés
  (`referencia-batalla.md`, en curso) describen el comportamiento; este
  documento solo cubre lo que se ve y se maneja.
- Todas las pantallas de UMG posteriores (mapa de campaña, C2-C4) heredan el
  kit que se fije aquí.

---

## 7. Perillas de ajuste y kit de piezas

### 7.1 Perillas de hoy (valores a conservar en UE)

| Constante | Valor | Rango seguro | Efecto | Dónde |
|---|---|---|---|---|
| `Tema.FACTOR` | 0,6 | 0,5-0,8 | Tamaño de toda la interfaz | `interfaz/tema.lua:61` |
| `Tema.TEXTO` | 1,5 | 1,3-1,7 | Texto más grande que los paneles | `:65` |
| `Control.radioClick` | 28 px | 20-40 | Holgura del clic sobre una unidad | `control.lua:27` |
| `Control.tiempoDoble` | 0,35 s | 0,25-0,5 | Ventana del doble clic | `:28` |
| Umbral de arrastre | 6 px | 4-10 | Cuándo un clic pasa a ser cuadro o giro | `escena.lua:1082` |
| `Control.duracionMarca` | 1,6 s | 1-3 | Vida del marcador de orden | `:29` |
| `Despliegue.duracion` | 120 s | decisión del dueño | Preparación | `despliegue.lua:18` |
| `DespliegueVista.fundido` | 0,6 s | 0,3-1 | Salida de las zonas | `despliegue_vista.lua:23` |
| `Tropas.cierre` | 6 s | 3-10 | Del fin a la vuelta | `tropas.lua:132` |
| `MarcasHolo.anilloPx` | 14 px | 10-20 | Radio mínimo del anillo en pantalla | `marcas_holo.lua:50` |
| `MarcasHolo.cintaPx` | 40 px | 24-60 | Ancho de la cinta a 1080 | `:43` |
| Vida: crecer al pasar el ratón | 4 × e px por lado, rapidez 16/s | 2-6 px | Movimiento sutil de los botones | `interfaz/vida.lua:68-72`, `acero.lua:390-392` |
| Vida: hundirse al pulsar | 2 × e px, rapidez 28/s | 1-3 px | ídem | ídem |
| Vida: entrada de paneles | 0,22 s, 24 px | 0,15-0,3 s | Panel que entra deslizándose | `vida.lua:119`, `despliegue_vista.lua:303` |

### 7.2 Kit modular de UMG **[Propuesta]**

Para que Valeria lo monte una vez en `Content/UI/Kit/` y se reutilice en todas
las pantallas. Nombres en español con los prefijos de UE (decisión del
2026-10-03). Cada pieza copia un componente de `interfaz/acero.lua`, que a su
vez sigue `interfaz-militar.md` §4.

**Datos compartidos**

| Pieza | Qué es | Sale de |
|---|---|---|
| `DA_PaletaMilitar` (Data Asset) | Los colores de `interfaz/paleta.lua` por nombre (`olivaNegro`, `textoHud`, `amarillo`, `rojoTexto`…), más los cuatro holográficos | `interfaz/paleta.lua:31-71`, `marcas_holo.lua:31-34` |
| `F_Barlow` (fuente compuesta) | Caras: Título = BarlowCondensed-SemiBold; Rótulo = BarlowCondensed-Medium; Cuerpo = BarlowSemiCondensed-Medium; Cuerpo negrita = BarlowSemiCondensed-SemiBold. Aparte, `F_JetBrainsMono` (SemiBold) para los rótulos de unidad | `assets/fuentes/` (OFL) |
| `DT_EstilosTexto` | Las filas de la tabla del §4.2 (fuente, tamaño en puntos = px × 0,75, color) | `acero.lua:23-32` |
| Escala | Regla de DPI de UE por lado corto: 720 → 0,8; 1080 → 1,0; 1440 → 1,33; 2160 → 2,0. Los widgets se diseñan a 1920 × 1080 con las medidas reales (diseño × 0,6) | `tema.lua:56-70` |

**Trampa de color:** los hex de la paleta son sRGB. En C++ van con
`FLinearColor::FromSRGBColor(FColor(…))` o como `FColor`; un `FLinearColor`
escrito a mano con los mismos números sale lavado. Ya pasó en LÖVE con el
color de la nación (commit 955a6c0: «el carmesí salía rosa»).

**Widgets**

| Widget | Copia de | Qué lleva | Estados |
|---|---|---|---|
| `WBP_Panel` | `Acero.panel` | `Border` con Box Brush de `panel_acero` (96 × 96, márgenes 20 px → 0,208) y, opcional, cabecera con título, subtítulo y botón de cerrar (`panel_acero_cabecera`); sombra de dos rectángulos negros 3 px abajo al 25 % y 12 %. **[Propuesta]** Camila hornea el «levantado» (capa `lineaOliva` al 50 %) en la imagen, para no apilar dos capas | uno |
| `WBP_Boton` | `Acero.boton` | Tipos dorado (principal), gris (secundario), oscuro y rojo (peligro); texto con `boton` (20 px), icono opcional a la izquierda y precio opcional; corta con «…» | normal, resaltado, pulsado, desactivado (las cuatro imágenes de `assets/ui/botones/boton_<tipo>_<estado>.png`); crece 4 px por lado al pasar el ratón y se hunde 2 px al pulsar (§7.1), el texto sin escalar; color de texto: `amarilloTinta` sobre dorado, `tinta` sobre gris, `textoHud` sobre oscuro y rojo, tenue si está desactivado |
| `WBP_Barra` | `Acero.barra` | Canal `barra_fondo` (64 × 14) con margen de 2 px y relleno 9-slice del tipo: energía (verde), recurso (dorado), peligro (rojo), estadística, experiencia; capa opcional de «pendiente» en `amarilloDinero` al 50 % | uno |
| `WBP_Icono` | `Acero.icono` | `Image` con los iconos blancos de `assets/ui/iconos/` (32 y 64) teñidos con un color de la paleta | normal y apagado (40 %) |
| `WBP_Ayuda` (tooltip) | `Acero.tooltip` | Placa `olivaNegro` al 96 % con filo `lineaOliva` y esquinas cortadas de 4, texto `ayuda` (14 px) hasta 420 de ancho, a +14/+18 del puntero y metida en la pantalla | uno |
| `WBP_Separador` | `Acero.separador` | Pieza `separador` de 2 px | uno |
| `WBP_TextoContorno` | `Acero.textoContorno` | Texto con contorno `olivaNegro` (el contorno de fuente de UMG) | uno |
| `WBP_Chip` | `Acero.chip` | Placa oscura pequeña (`chip_oscuro`) para cifras | uno |

**Pantallas de la batalla con el kit**

| Pantalla | Se monta con |
|---|---|
| E1 carga | `WBP_Panel` sin cabecera, `WBP_Barra` (energía), título `titulo` |
| E2 rótulo | `WBP_Panel` (o la placa translúcida actual) y filas de texto; ver la decisión D1 |
| E3 preparación | `WBP_Panel`, `cifraGrande`, `WBP_Separador`, `WBP_Boton` dorado |
| E6 avisos | un `CanvasPanel` que coloca cada aviso con `ProjectWorldLocationToScreen` en cada cuadro y evita solapes como hoy. **No** un `WidgetComponent` por unidad: con 2000 soldados sería muy caro (sin medir en UE) |
| E7 fin | `WBP_Panel` con borde `amarillo` de 2 px |
| Rótulos de unidad (E5) | el mismo `CanvasPanel` que E6, con `F_JetBrainsMono` |
| F1-F3 **[Nuevo]** | fila de `WBP_Boton` oscuros con número y `WBP_Icono` |

---

## 8. Revisión de la interfaz de hoy: ajustes priorizados para UE **[Propuesta]**

Mirando las capturas a 1920 × 1080 y 1280 × 720. Que se copie tal cual o se
corrija al pasar lo decide el dueño (D1).

| # | Prioridad | Qué se ve | Propuesta |
|---|---|---|---|
| A1 | Alta | El nombre del atacante en carmesí sobre el `olivaNegro` del rótulo casi no se lee (`seleccion_mover_1080`: «Ataca Principado de Quefial…») | Nombre en `textoHud` con un cuadradito del color de la nación delante, como ya hace el panel E3 |
| A2 | Alta | El rótulo mezcla juego y depuración: 13 líneas y 680 × 195 px a 1080, con triángulos, semilla, FPS y altitud de la cámara | En UE, separar: placa de bandos (fuerzas, munición, avisos) visible siempre; depuración y ayuda de teclas tras una tecla |
| A3 | Alta | Los rótulos de unidad («T-72B · 11») van en menta claro sin contorno ni placa y se pierden sobre la tierra; las cintas los tapan (`seleccion_recorte`) | Contorno oscuro o placa al 60 %, y dibujarlos encima de las cintas |
| A4 | Media | La carga no usa el estilo (fuente por defecto, verde propio, fondo azul-negro) | Rehacerla con el kit (`WBP_Panel` + `WBP_Barra`) |
| A5 | Media | El nombre de la zona de despliegue no aparece con el encuadre de la preparación (el centro de la zona queda fuera de la vista) | Ponerlo en el borde delantero de la zona, el que mira al enemigo |
| A6 | Media | El fin dice «vuelta al mapa»; en las etapas B no hay mapa | Texto según destino; y una pantalla de resultados (bajas, averiados, munición gastada, lo que hoy va a la consola). Es la C7 del plan |
| A7 | Media | A 720 el rótulo de unidad sale a 11 px (menos del mínimo de 12) | Mínimo 12 px también aquí |
| A8 | Baja | No hay cursor según la orden (mover / atacar / sin ruta) | Cursor de mover y de atacar al pasar sobre terreno o enemigo con selección |
| A9 | Baja | No hay resaltado al pasar el ratón sobre una unidad | Anillo tenue al pasar el ratón |
| A10 | Baja | La marca «Comparador 3DreamEngine (--dream)» abajo a la izquierda (a 720, «--» sale como «—») | No se pasa a UE |

---

## 9. Criterios de aceptación (comprobables en UE)

1. **Capturas a 1920 × 1080 y 1280 × 720** de: carga, preparación,
   preparación con «Listo» pulsado, combate con selección y cintas, ataque
   con el blanco en rojo, unidad sin munición con su aviso, fin y a pie. Cada
   una al lado de la de LÖVE: mismos textos, mismos colores (hex del
   `DA_PaletaMilitar` medidos en la captura con ± 3 por canal) y mismas
   posiciones relativas (± 8 px).
2. **Texto:** ninguno por debajo de 12 px a 720; ningún texto cortado; el
   contraste de cada texto con su fondo ≥ 4,5:1 (los pares de
   `interfaz-militar.md` §3.2).
3. **Controles por Enhanced Input inyectado** (la versión UE de
   `prueba_raton.lua`): pasan las mismas comprobaciones que hoy da
   `batalla/pruebas_control` (clic, Mayús + clic, doble clic, cuadro, T/L/I,
   mover, mantener, atacar, «Listo»).
4. **Botones:** los cuatro estados con sus imágenes; crecen y se hunden con
   los valores del §7.1 (medido en la captura: 4 px ± 1 de crecimiento a 1080).
5. **El kit se reutiliza:** E1, E3 y E7 están hechas solo con widgets del
   §7.2, sin estilos copiados a mano.
6. **Rendimiento:** con 2000 soldados y 50 avisos E6 a la vez, la interfaz no
   pasa de 0,5 ms por cuadro (Unreal Insights). Es un objetivo propuesto:
   no hay medida en UE todavía.

### Capturas de referencia de LÖVE (2026-10-03)
En `<carpeta temporal>`:

| Archivo | Cómo se sacó |
|---|---|
| `lucia_ui_batalla_preparacion_1080.png`, `_720.png` | `love . 42 --batalla preparacion 120 6 3 --captura 5000 x.png 0 0 1 1000 guerra --tam <tam>` |
| `lucia_ui_batalla_combate_1080.png`, `_720.png` | lo mismo con `--batalla cerca 240 6 3` |
| `lucia_ui_batalla_fin_1080.png`, `_720.png` | lo mismo con `--batalla duracion 60 2 1` (9:46 de pelea) |
| `lucia_ui_batalla_seleccion_mover_1080.png`, `_atacar_1080.png`, `_lanzacohetes_1080.png`, `_recorte.png` | `python3 batalla/pruebas_control/ejecutar.py <carpeta> 42` |
| `lucia_ui_batalla_a_pie_1080.png` | `python3 batalla/pruebas_caminante/ejecutar.py <carpeta> 42 1920x1080` |

Sin captura: la carga (E1) y los avisos de munición (E6). La selección solo a
1080, porque el arnés de control no admite otro tamaño. Ojo: el arnés de
control dibuja la interfaz más grande que el juego (su rótulo mide 1140 px de
ancho frente a 680 en el juego), así que esas capturas valen para las marcas
del terreno, no para medir el rótulo.

---

## 10. Decisiones para el dueño

**D1. ¿Qué se copia en el B5?**
1. *(Recomendada)* **Igual que hoy, con los ajustes A1-A3.** Fiel a LÖVE, más
   legible; la depuración pasa a una tecla. Coste: poco más que copiarla.
2. **Exactamente igual que hoy**, rótulo de 13 líneas incluido. Lo más
   rápido; arrastra los problemas de lectura.
3. **Igual, más todo el §8 (A1-A10)**, pantalla de resultados incluida. Más
   completo; añade un paso mediano.

**D2. Teclas cuando llegue el soldado propio (C6)**
1. *(Recomendada)* **F1-F3 para las órdenes (GDD) y V para cambiar entre
   tercera y primera persona.** La vista RTS se queda en otra tecla (por
   ejemplo Tab). Respeta el GDD y no choca con nada de la batalla de hoy.
2. **F1-F3 para las órdenes y una tecla nueva para la primera persona; V
   sigue bajando y subiendo de la vista RTS.** Tres modos de cámara; más que
   aprender.

**D3. Órdenes F1-F3: cómo se ven**
1. *(Recomendada)* **Tira de botones abajo, como en Bannerlord**, elegida con
   1-4 o con el ratón y sin pausar. Copia la referencia de la batalla.
2. **Menú radial alrededor del puntero.** Va mejor con mando; en Bannerlord no
   es así.
   (En los dos casos, antes de construirlo se le enseñan variantes animadas.)

# Modo Base: la ciudad por dentro y la construcción modular

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Documento para Andrés (simulación: piezas, órdenes, guardado, IA de los NPC),
Valeria (escena 3D, modo construir y paneles), Camila (el kit de piezas y
estaciones) y Elena (mediciones y pruebas). Estado: **propuesta, sin
programar.** Lo marcado «hoy» es lo que hay en el código (HEAD 9b1c5b2); lo
marcado «propuesta» es lo nuevo (HEAD 369e4e5 para el radial).

Sale de dos peticiones del dueño del 2026-09-30:

1. Desde el menú radial de su ciudad en el mapa, un botón «Base» entra a ver la
   ciudad por dentro en 3D, como en Warpath
   (`diseno/referencias-warpath/radial_ciudad_propia.jpg`).
2. Sus respuestas a la primera versión de este documento (sección 10): la base
   se **construye libremente** con un **sistema modular al estilo de No Man's
   Sky** (suelos, paredes, paredes con ventana, con puerta o con portón,
   techos, escaleras, rampas…) y **dentro** de los edificios se colocan
   **estaciones de trabajo**. **La función la dan las estaciones, no el
   edificio.**
3. Sus decisiones sobre la segunda versión (sección 10, marcadas
   **DECIDIDO**): la construcción vive **solo en la escena 3D**; las piezas se
   colocan **al instante** al pagarlas; líneas de soldados y de vehículos
   **separadas**; las estaciones mandan desde la fase 2.

Las cifras salen de dos scripts sin LÖVE (ver «Cómo se midió»): semillas 1, 7,
42 y 1234, 500 días, 20 a 22 naciones por semilla, con las reglas de **hoy**.
Las de dinero y metal por día son de `economia.md` §9 (prototipo con lo
decidido).

---

## 0. Estado de hoy

| Pieza | Hoy | Dónde |
|---|---|---|
| Radial de un sitio | **Sí**: en la ciudad propia, Ejército, Reparar, Arsenal, Regresar y Base | `interfaz/radial.lua`, `opcionesSitio` en `main.lua` |
| Botón «Base» | **Sí, vacío**: `abrirBase` solo avisa «en construcción» | `main.lua` |
| Ciudad por dentro | **No existe.** En el mapa la capital es una torre sobre una plaza de 60 m (`Ciudades.lado` = 600 px) | `mundo/ciudades.lua` |
| Edificios o piezas en la simulación | **No hay.** La ciudad es un registro de números (`nivel`, `mejora`, `vida`, `soldados`, `tanques`, `lanzacohetes`, `baterias`, `recuperando`…) | `mundo/simulacion.lua` |
| Lo que hoy decide la capacidad de una ciudad | El **nivel**: líneas de fábrica = nivel, taller = `ritmo × nivel`, almacén y bóveda por nivel, tope de defensas por nivel, tope de ejército por nivel | `economia.md` §3.4, F3, F12; `territorio-y-capitales.md` F1, F1b |
| Órdenes útiles en la base | `mejorarCiudad`, `reparar`, `enviarDefensas`, `acelerarRecuperacion` | `Simulacion:ejecutar` |
| Órdenes que no existen | `producir` (unidades y munición), `cancelarProduccion`, `abastecer` (`economia.md`, sin programar); `construir` y `derribar` (este documento) | — |
| Motor 3D | 3DreamEngine con luz, cielo, terreno, vegetación, cámara libre, instancias con tono por copia y consultas de rayo | `batalla/dream/`, `GUIA-3D.md` |
| Duración de un día | 1 minuto real a velocidad 1 (`Mundo.velocidad = 1/60`); la simulación solo cambia al cerrar cada día | `mundo/mundo.lua`, `Simulacion:actualizar` |
| Modelos Synty útiles (sin importar) | Atlas `Tex_Military_*`, cajas de munición, cajas metálicas, barriles, bidones, depósitos de combustible, sacos terreros, cercas, muros, focos, escombros, carreteras | `~/Downloads/SourceFiles/Fbx` |

### Lo medido: qué tiene dentro una capital (reglas de hoy)

Mediana por capital [mínimo – máximo], rango entre las 4 semillas:

| Qué | Día 100 | Día 300 | Día 500 |
|---|---|---|---|
| Nivel | 2 [2 – 3] | 4 [2 – 4] | 5 [3 – 5] |
| Soldados en la ciudad | 1 065 – 1 738 [62 – 2 708] | 1 877 – 2 861 [688 – 4 234] | 2 902 – 4 397 [350 – 6 313] |
| Tanques en la ciudad | 3 – 5 [0 – 25] | 20 – 24 [1 – 94] | 42 – 50 [3 – 180] |
| Lanzacohetes | 5 [4 – 10] | 18 [5 – 18] | 30 [10 – 30] |
| Baterías | 5 [5 – 10] | 18 [5 – 18] | 30 [10 – 30] |
| En el taller (`recuperando`) | 0 | 0 [hasta 40 soldados y 2 tanques] | 0 |
| `casco` (radio de la ciudad en la simulación) | 1 883 – 2 596 px de mediana; mínimo 1 325 px; máximo 3 069 px | | |

| Guardado y costo del día | Día 100 | Día 500 |
|---|---|---|
| Tamaño de `guardar()` (semillas 1 y 42) | 1,82 – 1,85 MB | 4,10 – 4,18 MB |
| Tiempo de `guardar()` | 63 – 73 ms | 118 – 137 ms |
| Tiempo de un día simulado (22 naciones) | 25 – 27 ms | 48 – 49 ms |

Con el tope de ejército de `economia.md` F3 (tanques 8 / 20 / 35 / 55 / 80 por
nivel) los 180 tanques del peor caso desaparecen: como mucho 80 tanques y 30
lanzacohetes en una capital de nivel 5.

---

## 1. Resumen

El modo Base es la ciudad propia vista por dentro en 3D, y el sitio donde se
construye. Se entra con «Base» en el radial de la ciudad y se vuelve con «Mapa»
(o Esc). Usa la misma pila 3D que la batalla (3DreamEngine, luz, cielo, suelo,
estilo de Camila) sobre el terreno real, dentro de un **recinto** aplanado cuyo
tamaño crece con el nivel. Dentro del recinto, el jugador **monta edificios con
piezas modulares** que encajan en una rejilla de 4 m (suelos, paredes,
ventanas, puertas, portones, techos; escaleras y rampas en una fase posterior)
y coloca dentro **estaciones de trabajo**: foso de reparación, línea de
montaje, mesa de reclutamiento, enfermería, banco de munición, estantería de
almacén y caja fuerte. **La función la dan las estaciones**: una ciudad tiene
tantas líneas de fábrica como líneas de montaje funcionando, y su taller
repara según sus fosos, siempre con el nivel de la ciudad como techo. Las
piezas y las estaciones se pagan en recursos, **aparecen al instante** al
pagarlas y se guardan en la simulación (deterministas, como todo el estado). Los NPC
construyen con **las mismas piezas y la misma orden `construir`**, colocando
**plantillas** de edificios prediseñados. Lo que no se construye (tanques,
lanzacohetes, baterías, soldados, pilas de recursos) se ve 1:1 según el estado
de la simulación.

**Todo el sistema de construcción vive solo en la escena 3D de la ciudad.**
En el mapa 2D no se ve ningún edificio ni pieza: la capital sigue siendo su
torre. En el 2D, el radial de la ciudad propia solo añade dos botones,
«Producir munición» y «Crear soldados», que dan la orden `producir` de
`economia.md` sin entrar en la base (DECIDIDO).

## 2. Fantasía del jugador

- «Tiro doce losas, levanto las paredes, dejo un portón al patio y techo la
  nave. Meto un foso dentro: ya tengo taller. Pago y está.»
- «Subí a nivel 3 y la ciudad me deja una línea de montaje más, pero no la
  tengo hasta que no le haga sitio y la construya.»
- «Mi fábrica es mía: la nave larga junto a la puerta norte, con las tres
  líneas en fila. Los tanques salen por el portón y aparcan en el patio.»
- «Si derribo el techo del taller, los fosos se paran. Primero construyo el
  taller nuevo, luego tiro el viejo.»
- «Veo mis 35 tanques aparcados, las plataformas del muro llenas y dos tanques
  averiados en los fosos. Es lo que tengo, ni uno más.»
- «El vecino tiene las naves típicas del presidente: las mismas plantillas de
  siempre. Yo diseño las mías.»

## 3. Reglas

### 3.1 Entrar y salir

1. El radial de una ciudad **propia** muestra «Base». En ciudades ajenas no
   aparece: la base ajena solo se ve en la foto del informe de un explorador
   o, en persona, al atacarla (DECIDIDO, fase 5).
2. Pulsar «Base» cierra el radial y abre la escena Base; mientras se genera se
   ve la pantalla de carga de la batalla (`batalla/carga.lua`).
3. Dentro siguen la barra superior y el pregón de avisos. Un botón «Mapa» (y
   Esc) vuelve al mapa centrado en la ciudad.
4. **El mundo sigue a su velocidad normal** (provisional, 10.P1): no
   hay turnos ni pausa.
5. **Cámara:** vuelo libre, la misma de la batalla (`batalla/camara.lua` y
   `controlador_camara.lua`, WASD hacia donde mira), con el límite en el borde
   de la escena (decisión del dueño).
6. **Ciudad atacada** (decisión del dueño): se puede entrar y mirar. Arriba
   sale «Ciudad sitiada» y un botón «Ir a la batalla» que abre la escena de
   batalla de ese combate. La defensa dentro de la base es una fase posterior
   (fase 5).
7. Una sola escena 3D a la vez: si hay una batalla abierta, se sale de ella
   antes.
8. **Mapa 2D** (DECIDIDO): no muestra nada de la base. El radial de la ciudad
   propia lleva, además de «Base», «Producir munición» y «Crear soldados»:
   abren un selector de cantidad y mandan `producir` (munición o `tropa =
   'soldados'`). Desde la fase 2, si la ciudad no tiene la estación que hace
   falta funcionando (banco de munición, mesa de reclutamiento), el botón sale
   desactivado con el motivo (`sinBanco`, `sinMesa`) y la ayuda «Constrúyela
   en la Base».

### 3.2 El recinto y la rejilla

1. **Recinto:** disco de radio `R` (F1) centrado en `(c.x, c.y)`. El suelo se
   aplana a `z0 = terreno:altura(c.x, c.y)`, con un talud hasta el terreno
   real. Fuera, hasta el borde de la escena, terreno y vegetación de la
   batalla.
2. **Rejilla:** celdas cuadradas de `celda = 40 px` (4 m), alineadas con los
   ejes del mundo y con el origen en `(c.x, c.y)`. La celda `(i, j)` cubre
   `x ∈ [c.x + 40 i, c.x + 40 (i + 1))` y lo mismo en `y`.
3. **Pisos:** `p = 0` en la fase 1 (solo planta baja). La altura del suelo del
   piso `p` es `z0 + 3 + 40 p` px (el cimiento mide 0,3 m y cada piso 4 m).
4. **Ranuras de una celda** (dónde puede ir una pieza):
   - `s`: el suelo de la celda;
   - `t`: el techo de la celda;
   - `o` y `n`: sus aristas oeste (`x = i`) y norte (`y = j`). La arista este
     de `(i, j)` es la `o` de `(i + 1, j)`, y la sur es la `n` de
     `(i, j + 1)`: cada arista tiene **una sola** clave.
   - `e`: el ancla de una estación (su celda de menor `i` y `j`).
5. **Clave de una pieza:** `p:i:j:ranura` (por ejemplo `0:-4:7:o`). Los
   recorridos que afecten a un resultado van en orden fijo: `p`, luego `j`,
   luego `i`, luego la ranura en el orden `s, t, o, n, e`.
6. **Celdas válidas** para construir:
   - su centro está a menos de `R − 80 px` del centro (se reserva un anillo de
     8 m para la cerca y las defensas);
   - no están en la **plaza del centro de mando**: el cuadrado de 80 m (la
     plaza de 60 m más una calle de 10 m a cada lado), es decir, las 400
     celdas con `−10 ≤ i ≤ 9` y `−10 ≤ j ≤ 9`;
   - no caen en el agua (en la fase 1; los muelles, más adelante).

### 3.3 Las piezas de la fase 1

Medidas en metros; en px del juego, ×10.

| Pieza | Ranura | Medidas | Apoyo que necesita |
|---|---|---|---|
| Cimiento (suelo) | `s` | 4 × 4 m, 0,3 m de grueso | Celda válida (3.2.6) |
| Pared | `o` o `n` | 4 m de ancho × 4 m de alto × 0,2 m | Cimiento en al menos una de las dos celdas que separa |
| Pared con ventana | `o` o `n` | igual; ventana de 1,6 × 1,2 m | Igual que la pared |
| Pared con puerta | `o` o `n` | igual; hueco de 1,2 × 2,4 m | Cimiento en **las dos** celdas (se entra y se sale) |
| Portón | dos aristas seguidas, alineadas | 8 m × 4 m, hueco de 7 × 3,8 m | Cimiento en las cuatro celdas que toca |
| Techo plano | `t` | 4 × 4 m | Cimiento en su celda y, además, al menos una pared, ventana, puerta o portón en alguna de sus cuatro aristas, **o** un techo vecino (4 direcciones) que sí tenga pared (vuelo de una celda como mucho) |

- **Las esquinas no son piezas:** donde se juntan dos paredes, la vista pone
  sola un pilar de remate.
- **Colisión:** una pieza por ranura. Una estación ocupa las ranuras `s` de su
  huella (encima de un cimiento ya puesto) y no puede tener pared en las
  aristas interiores de su huella.
- **Acceso libre:** la celda de dentro de una puerta y las dos de dentro de un
  portón no pueden tener estación.
- **Orientación:** las paredes no llevan rumbo (lo da la arista); las ventanas
  y puertas llevan un bit `fuera` (qué cara es la exterior, para el marco). Las
  estaciones llevan `rot` = 0, 1, 2 o 3 (×90°); con 1 y 3, ancho y fondo se
  cambian.

**Fase 3 (pisos y más piezas):** escalera (1 × 2 celdas, sube un piso), rampa
de vehículos (2 × 3 celdas), techo inclinado a una y dos aguas, suelo de piso
alto (sobre techo plano), barandilla, columna, valla, muro del recinto y
puertas del recinto. Sus reglas de apoyo se añaden entonces.

### 3.4 Estaciones

| Estación | Huella | Acceso que pide su edificio | Qué hace (desde la fase 2) | Máximo por ciudad |
|---|---|---|---|---|
| Foso de reparación | 3 × 2 celdas (12 × 8 m) | portón | Cada foso funcionando aporta un «nivel» de taller: `puntos = ritmo[tipo] × min(fosos, nivel)` (F12 de `economia.md`) | `nivel` |
| Línea de montaje | 4 × 2 (16 × 8 m) | portón | Una línea de fábrica de vehículos: `lineasVehiculos = min(líneas, nivel)` | `nivel` |
| Mesa de reclutamiento | 1 × 1 | puerta o portón | Una línea de soldados: `lineasSoldados = min(mesas, nivel)` | `nivel` |
| Enfermería | 2 × 1 | puerta o portón | Cura soldados heridos: `25 × min(enfermerías, nivel)` al día (el ritmo de hoy) | `nivel` |
| Banco de munición | 2 × 1 | puerta o portón | Con uno funcionando, la ciudad acepta `producir` munición; sin él, motivo `sinBanco`. **No limita cuántos lotes** (decisión de la economía: munición sin tope) | `nivel` |
| Estantería de almacén | 1 × 1 | puerta o portón | +`estanteria` de tope de metal y de petróleo (F5) | `4 × nivel` |
| Caja fuerte | 1 × 1 | puerta o portón | +`cajaFuerte` de tope de bóveda (F5) | `2 × nivel` |
| Centro de mando | fijo (la torre del mapa en la plaza central) | — | Mejorar la ciudad (`mejorarCiudad`) y repararla (`reparar`). No se construye ni se derriba | 1 |

**Cuándo funciona una estación** (se recalcula al cambiar las piezas; la
simulación lo usa al cerrar cada día):

1. cada celda de su huella tiene cimiento **y** techo;
2. todas esas celdas pertenecen al mismo **edificio**: un grupo de celdas con
   cimiento y techo unidas por sus lados (4 direcciones), en el mismo piso;
3. ese edificio tiene en su borde el acceso que pide la tabla: una puerta o un
   portón en una arista entre una celda del edificio y una celda sin techo.

Una estación que deja de cumplirlo (porque se derriba un techo, por ejemplo)
queda **parada**: no se pierde nada, lo que dependía de ella se congela (como
con una ciudad sitiada) y vuelve a correr el día que se arregla.

**Relación con el tope de ejército** (`economia.md` F3): las estaciones **no
lo cambian**; lo fija el nivel. Una ciudad de nivel 2 con cinco líneas de
montaje sigue sin poder pasar de 20 tanques (y solo dos de esas líneas
cuentan, por el máximo de la tabla).

**Qué limita el nivel de la ciudad** (DECIDIDO):

- cuántas estaciones de cada tipo cuentan y se pueden construir (tabla);
- cuántas piezas estructurales puede tener la ciudad (F3);
- el radio del recinto (F1).

### 3.5 Construir y derribar: órdenes

**Construir** (la misma orden para el jugador y los NPC):

```lua
ejecutar({ tipo = 'construir', nacion, ciudad, piezas = {
    { pieza = 'cimiento', p = 0, i = 12, j = -3 },
    { pieza = 'pared', p = 0, i = 12, j = -3, arista = 'o' },
    { pieza = 'porton', p = 0, i = 12, j = -3, arista = 'n' },  -- ocupa (12,-3,n) y (13,-3,n)
    { pieza = 'techo', p = 0, i = 12, j = -3 },
    { pieza = 'foso', p = 0, i = 12, j = -3, rot = 0 },
} })
```

1. **Comprobaciones**, en este orden; si falla una, se devuelve `false,
   motivo, indice` (la pieza que falló) y **no se construye nada**:
   - `noEsSuya`: la ciudad no es de esa nación;
   - `pieza`: tipo desconocido, o una pieza de una fase aún no disponible;
   - `fueraDelRecinto`: alguna celda no es válida (3.2.6);
   - `ocupado`: la ranura ya tiene pieza o la repite otra pieza del mismo
     lote;
   - `sinApoyo`: no cumple su apoyo (3.3). **Las piezas anteriores del mismo
     lote cuentan como apoyo**: un edificio entero se pide en una sola orden,
     en el orden cimientos → paredes → techos → estaciones;
   - `bloqueaAcceso`: una estación delante de una puerta o un portón;
   - `limitePiezas`: pasaría de `piezasMax(nivel)` (F3);
   - `limiteEstaciones`: pasaría del máximo de su tipo (tabla 3.4);
   - `dinero`, `metal`, `petroleo`: el primero que no alcance para el lote
     entero (guardado más afuera).
2. **Al instante** (DECIDIDO): se paga el lote entero, primero de afuera, y
   las piezas quedan puestas en ese mismo momento, sin obra ni espera. No hay
   cola de obra ni ritmo diario.
3. **Sin turnos:** se pueden dar tantas órdenes como se puedan pagar.
4. **Ciudad sitiada** (combatió hoy o ayer): se puede construir igual
   (DECIDIDO). Hasta la fase 5 las piezas no intervienen en las batallas.

**Derribar:**

```lua
ejecutar({ tipo = 'derribar', nacion, ciudad, claves = { '0:12:-3:t', ... } })
```

1. Comprobaciones: `noEsSuya`; `noExiste` (clave sin pieza); `sostiene`: al
   quitarlas, alguna pieza que **no** está en la lista se quedaría sin apoyo
   (por ejemplo, quitar un cimiento con una pared encima). Se derriba de arriba
   abajo en una sola orden.
2. **Devolución** (DECIDIDO: derribar es gratis): se devuelve **todo** lo
   que costó (100 %), con `ingresar` (lo que no quepa va afuera). Como todo
   es instantáneo, la base se puede rehacer o «mover» sin costo: lo único que
   frena es tener el dinero y el metal para el lote nuevo antes de devolver el
   viejo (se derriba y se construye en órdenes separadas).
3. Es instantáneo.
4. Si se derriba la última estación de algo que tenía trabajo en cola (una
   línea de montaje con tanques en fábrica), la cola se congela como en 3.4; no
   se pierde lo pagado.

**Nombre de la orden:** hoy `construir` ya es el nombre de una **misión** de
grupo (`g.mision == 'construir'`, el convoy que levanta una extracción o una
base). No chocan (una es `tipo` de `ejecutar`, la otra un campo del grupo),
pero quien lea el código puede confundirlas; si Andrés lo prefiere, la orden
puede llamarse `construirBase` sin cambiar nada de este documento.

### 3.6 Lo que no se construye: se ve 1:1

| Qué | Dónde se ve |
|---|---|
| Tanques sanos de la ciudad (`c.tanques`) y lanzacohetes del parque | **Patio automático:** plazas de 12 × 6 m en las celdas válidas **sin** cimiento más cercanas a los portones de las líneas de montaje (o al centro, si no hay); se recalcula cada vez que cambian las piezas. Si no caben, siguen fuera de la cerca junto a la puerta principal |
| Vehículos averiados (`c.recuperando`) | En los fosos (uno por foso); los que no caben, aparcados delante del portón del taller |
| Vehículo en fábrica | En la línea de montaje que lo fabrica, a medio montar según sus días |
| Lanzacohetes en plataforma, baterías | Plataformas y emplazamientos **automáticos** en el anillo del perímetro, tantos como el tope de su nivel (2 / 5 / 10 / 18 / 30), alternados; ocupados según `c.lanzacohetes` y `c.baterias`. Colocables a mano desde la fase 4 |
| Soldados | Escuadras (F10 de `economia.md`): como mucho 48 figuras, en la celda libre más cercana a las mesas de reclutamiento, con un rótulo con la cifra |
| Metal y petróleo guardados | Cajas y bidones sobre las estanterías, en proporción al llenado; sin estanterías, pilas sueltas junto al centro de mando |
| Lo de afuera (`n.afuera`) | Pilas fuera de la cerca, junto a la puerta principal (F5 de la primera versión: una pila cada 25, como mucho 40) |
| Munición del polvorín | Cajas junto a los bancos de munición, en proporción a las existencias |
| Vida de la ciudad | Piezas con humo y escombros al pie: una pieza está dañada si `hash(semilla, id, clave) < 1 − vida / 100` (con vida 9, un 91 %). Es solo visual: las piezas no pierden vida (hasta la fase 5) |

### 3.7 Guardado

- Cada ciudad guarda `c.base = { piezas = { [clave] = codigo } }`, donde
  `codigo` es una cadena corta: el tipo y, si hacen falta, `rot` y `fuera`
  (por ejemplo `'pv'` pared con ventana; `'fo2'` foso con `rot = 2`). No hay
  obra que guardar: las piezas aparecen al pagarlas.
- **No se guarda** nada que se pueda recalcular: la ocupación de las ranuras,
  los edificios (grupos de celdas), qué estaciones funcionan, el patio, la
  segunda arista de cada portón. Se reconstruyen al cargar y al cambiar las
  piezas.
- Todo se recorre en el orden de claves de 3.2.5: la misma lista de órdenes da
  el mismo `c.base` en cualquier máquina.
- Sube la versión del guardado (la siguiente a la de la economía). **Migración
  desde la versión anterior:** a cada ciudad se le coloca, gratis,
  su **plantilla de arranque** (3.8), la misma que recibe una ciudad nueva al
  nacer. Así nadie pierde capacidad al cargar.
- **Tamaño estimado:** unas 20 letras por pieza en el texto. Con 22 capitales
  de unas 300 piezas, unos 130 KB: un 3 % del guardado del día 500 (4,1 MB,
  medido). **Sin medir** con piezas reales.

### 3.8 Los NPC: plantillas y la misma orden

Los presidentes NPC no «tienen» edificios por arte de magia: construyen con
`ejecutar({ tipo = 'construir', ... })`, como el jugador.

1. **Plantillas:** edificios prediseñados con las mismas piezas, guardados
   como datos (`mundo/simulacion/plantillas.lua`): una lista de piezas
   relativas a un origen, que se puede girar 90°, 180° y 270°. Las mismas
   plantillas se ofrecen al jugador en el modo construir («Planos»), que las
   coloca con un clic y paga lo mismo. Una plantilla colocada son piezas
   normales: se pueden derribar una a una.
2. **Plantillas de la fase 2** (tamaños en celdas; costos en F2):

   | Plantilla | Huella | Estaciones | Acceso |
   |---|---|---|---|
   | Taller pequeño | 4 × 3 | 1 foso | 1 portón, 1 puerta |
   | Taller doble | 4 × 5 | 2 fosos | 1 portón, 1 puerta |
   | Nave de montaje | 5 × 3 | 1 línea | 1 portón, 1 puerta |
   | Cuartel | 3 × 3 | 2 mesas, 1 enfermería | 1 puerta |
   | Polvorín | 3 × 2 | 1 banco de munición | 1 puerta |
   | Almacén | 3 × 3 | 4 estanterías | 1 puerta |
   | Tesoro | 2 × 2 | 2 cajas fuertes | 1 puerta |

3. **Plantilla de arranque** de una ciudad de nivel `N` (N de 1 a 5; por
   encima, la de 5): las plantillas necesarias para tener `N` fosos, `N`
   líneas, `N` mesas, `N` enfermerías y 1 banco de munición, colocadas con la
   regla del paso 5. Reproduce la capacidad de hoy (`lineas = nivel`,
   `ritmo × nivel`), así que la migración no cambia ningún número de la
   economía. Sin estanterías ni cajas fuertes: los topes de almacén y bóveda
   quedan como hoy.
4. **Qué decide el NPC** (`planearBase(n)`, una vez al día y por ciudad,
   después de `planearProduccion`):
   - el **faltante**, en este orden de prioridad: banco de munición si no hay
     ninguno; líneas de montaje < nivel; fosos < nivel; mesas < nivel;
     enfermerías < nivel; y, si el almacén se llenó `diasLleno` días de los
     últimos 10, estanterías;
   - elige la plantilla más pequeña que cubre el primer faltante;
   - solo encarga si puede pagarla sin bajar de `reservaTesoro` de dinero ni de
     su reserva de metal, y sin tocar lo que ahorra para la mejora de la
     ciudad (`n.plan`);
   - como mucho **un lote por ciudad y día** (es el ritmo de la IA, no un
     límite del juego: el jugador encarga cuantos quiera).
5. **Dónde la coloca:** recorre los orígenes candidatos en espiral cuadrada
   desde la plaza central hacia fuera, empezando por el lado que marca
   `hash(semilla, id, 13)`, con las cuatro rotaciones en orden 0, 1, 2, 3, y
   se queda con el primero en el que la orden sería aceptada (se valida con la
   misma función que `construir`, sin ejecutar) y deja una calle de una celda
   libre alrededor. Si no hay sitio, no encarga y lo anota en el registro.
6. **NPC = jugador:** la misma orden, las mismas plantillas, los mismos
   costos, todo al instante. La única diferencia es que el jugador puede además
   diseñar lo suyo pieza a pieza.

### 3.9 Bases ajenas (fase posterior)

- **Fases 1 a 4:** no se puede entrar en la base de otra nación.
- **Fase 5, foto del explorador (DECIDIDO):** el informe de un explorador
  sobre una capital guarda una copia de su `c.base.piezas` de ese día; «Ver
  base» del informe abre esa foto, fechada, sin unidades (el poder ajeno sigue
  oculto salvo lo que diga el informe). La foto no cambia aunque el dueño
  construya después: envejece como el resto del informe.
- **Fase 5, en persona solo al atacarla (DECIDIDO):** la batalla en una
  capital se juega dentro de su recinto: las piezas son obstáculos y
  cobertura (las paredes paran balas con `Impactos.rayo`), las plataformas
  disparan desde su sitio y el atacante entra por las puertas del recinto.
- **Las piezas no se rompen en batalla** (provisional, 10.P2): solo se ven dañadas
  según la vida de la ciudad (3.6). Lo que se pierde es el saqueo de afuera,
  como ya está decidido.

### 3.10 Qué no hace la base

- No cambia el estado por mirar: entrar y salir no ejecuta nada.
- Las estaciones no cambian el tope de ejército ni los costos de producir.
- Las piezas no pierden vida en las batallas simuladas; el daño de la ciudad es
  `c.vida` (visual, 3.6).
- La cerca y las defensas del perímetro no se construyen hasta la fase 4.

## 4. Fórmulas

**F1. Radio del recinto.**
`R = min(0,9 × casco, R0 + k × (nivel − 1), Rmax)`, con `R0 = 1 000 px`,
`k = 250 px`, `Rmax = 3 000 px`.

- Nivel 2, casco 2 491 px: 1 250 px (125 m). Celdas válidas: `π × (125 − 8)²
  / 16 − 400` ≈ **2 290** (unos 36 600 m²).
- Nivel 5, casco 2 491 px: 2 000 px (200 m): ≈ **6 840 celdas**.
- Nivel 5 en la capital más pequeña medida (casco 1 325 px): 1 193 px: ≈ 2 000
  celdas.

**F2. Costos de cada pieza** (DECIDIDO: estructura barata en dinero; el
metal lo piden las estaciones; todo aparece al pagar).

| Pieza | Dinero | Metal | Petróleo |
|---|---|---|---|
| Cimiento | 2 | 0 | 0 |
| Pared | 2 | 0 | 0 |
| Pared con ventana | 3 | 0 | 0 |
| Pared con puerta | 3 | 0 | 0 |
| Portón | 8 | 1 | 0 |
| Techo plano | 2 | 0 | 0 |
| Foso de reparación | 60 | 10 | 0 |
| Línea de montaje | 120 | 25 | 5 |
| Mesa de reclutamiento | 30 | 2 | 0 |
| Enfermería | 40 | 3 | 0 |
| Banco de munición | 60 | 8 | 2 |
| Estantería | 20 | 4 | 0 |
| Caja fuerte | 40 | 6 | 0 |

Razón: el dinero es lo que sobra (entran 128 al día por nación, sobran unos 12
y otros 11,5 se pierden por merma; `economia.md` §9) y el metal es lo escaso
(entran 7,6 al día y se gasta todo). La estructura cuesta casi solo dinero;
las estaciones, que dan capacidad, cuestan metal. Como no hay tiempo de obra,
**lo único que frena construir es el costo**: por eso las estaciones cuestan
metal, que es lo que tarda en juntarse.

Ejemplo, **taller pequeño** (4 × 3 celdas): 12 cimientos (24), 12 techos (24),
14 aristas de borde = 1 portón (8 + 1 de metal, 2 aristas), 1 puerta (3), 2
ventanas (6) y 9 paredes (18): estructura **83 de dinero y 1 de metal**; más
el foso (60 y 10): **143 de dinero y 11 de metal**, al instante. Son unos 1,1
días de dinero y 1,4 días de metal de una nación media.

Ejemplo, **subir de nivel 2 a 3** y aprovecharlo: un foso, una línea de
montaje (nave), una mesa y una enfermería más ≈ 143 + 217 + 30 + 40 + unas 20
piezas de cuartel ampliado ≈ **470 de dinero, 42 de metal y 5 de petróleo**.
La mejora de nivel 3 cuesta 150 de metal y 60 de petróleo: construir añade
algo menos de un tercio del metal. **Sin medir** en la simulación.

**F3. Piezas estructurales por nivel.**
`piezasMax(nivel) = min(2 000, 300 + 150 × (nivel − 1))`: 300, 450, 600, 750,
900… hasta 2 000 en el nivel 13. Las estaciones no cuentan aquí (tienen su
máximo por tipo, tabla 3.4).

- El taller pequeño son 37 piezas (12 + 12 + 13 aristas con el portón como una).
- Arranque estimado de nivel 2 (2 talleres pequeños, 2 naves, 1 cuartel, 1
  polvorín): unas 230 piezas, el 51 % de 450. Nivel 5: unas 500, el 56 % de
  900. **Estimación a mano**, sin plantillas hechas.

**F4. Capacidad que dan las estaciones** (fase 2).

| Capacidad | Hoy | Propuesta |
|---|---|---|
| Líneas de vehículos | `nivel` (compartidas con soldados) | `min(líneas de montaje funcionando, nivel)` (DECIDIDO: separadas) |
| Líneas de soldados | (las mismas) | `min(mesas funcionando, nivel)` (DECIDIDO: separadas) |
| Taller (puntos al día) | `ritmo × nivel` | `ritmo × min(fosos funcionando, nivel)` |
| Curación de soldados | `25 × nivel` | `25 × min(enfermerías funcionando, nivel)` |
| Munición | sin límite | sin límite, pero pide ≥ 1 banco funcionando |

- Ejemplo: nivel 3 con 2 líneas de montaje, 3 fosos y 1 mesa: 2 líneas de
  vehículos, 1 de soldados y 1,5 puntos de tanque al día en el taller.
- **Diferencia con `economia.md` (DECIDIDO: separadas):** allí las `nivel`
  líneas se comparten entre soldados y vehículos; aquí son dos colas. Con
  todo construido, una ciudad tiene el doble de líneas. Medido con el
  prototipo de la economía: ver «Líneas separadas: lo medido» al final de esta
  fórmula.

**Líneas separadas: lo medido.** El prototipo de `economia.md`
(`tools/medir_economia_nationsrts.lua decidido-sueldos`, hoy retirado y en el
historial en 9b1c5b2; 500 días, semillas 1,
7, 42 y 1234) con un solo cambio, `nivel` líneas para soldados **y** otras
`nivel` para vehículos (la fase 2 con todo construido), frente al mismo
prototipo con las líneas compartidas:

| Qué | Compartidas (`economia.md`) | Separadas |
|---|---|---|
| Soldados producidos al día (todas las naciones, media por semilla) | 246,50 | 246,49 |
| Tanques producidos al día | 2,91 | 2,87 |
| Soldados por nación el día 500 (mediana, rango de semillas) | 4 532 – 6 000 | 4 685 – 5 534 |
| Tanques por nación el día 500 | 64 – 80 | 60 – 80 |
| Naciones-día en el tope de ejército | 50,9 % | 52,1 % |
| Días-nación con metal < 5 | 4,3 – 6,9 % | 4,4 – 6,7 % |
| Golpe perdido por falta de munición | 14,3 % | 14,7 % |
| Naciones vivas el día 500 | todas | todas |

Lectura: **no cambia nada relevante.** Lo que frena la producción de los NPC
es el tope por nivel, el metal y el dinero, no las líneas; las diferencias
entre las dos columnas son del tamaño del ruido entre semillas (la mediana de
soldados sube en unas semillas y baja en otras). Las cifras de `economia.md`
siguen valiendo. La columna «compartidas» reproduce la tabla de
`economia.md` §9 (4 532 – 6 000 soldados, 64 – 80 tanques).

**F5. Almacén y bóveda con estaciones** (fase 2; DECIDIDO: amplían sobre la
base del nivel).
`almacen = almacenNivel[nivel] + estanteria × estanterías`, con
`estanteria = 25`; `boveda = 10 × almacenNivel[nivel] + cajaFuerte × cajas`,
con `cajaFuerte = 200`.

- Nivel 5 con todo: almacén 1 000 + 20 × 25 = **1 500**; bóveda 10 000 + 10 ×
  200 = **12 000**.
- Efecto esperado: menos afuera, menos merma y botines más pequeños en los
  saqueos. **Sin medir.**

**F6. Presupuesto de dibujo** (estimación; nada medido).

| Parte | Tope | Cómo |
|---|---|---|
| Piezas estructurales (≤ 2 000) | 100 000 triángulos | cimiento y techo 12, pared 12 – 24, ventana y puerta ≈ 60, portón ≈ 100; **un lote de instancias por tipo de pieza** |
| Estaciones (≤ 5 × nivel + 6 × nivel) | 150 000 | 500 – 2 500 cada una; LOD 1 a más de 150 m |
| Vehículos (≤ 80 tanques + 30 lanzacohetes + 30 baterías + taller) | 300 000 | los de la batalla, instancias con tono de nación, LOD 1 lejos |
| Soldados (48 figuras) | 50 000 | los de la batalla |
| Terreno y vegetación fuera de la cerca | 420 000 | `ESTILO-TERRENO.md` §5, área pequeña |
| **Total** | **≈ 1 000 000** | la batalla admite 1,8 millones |

- Llamadas de dibujo: una por tipo de pieza y material (≈ 12 en la fase 1,
  ≈ 25 en la 3) más las de estaciones y vehículos, en cada una de las tres
  cascadas de sombra.
- Las matrices de las piezas se escriben al entrar y cuando cambian las
  piezas, no en cada cuadro.
- Objetivo: **≥ 90 FPS a 1080p en una RX 6600** con 2 000 piezas y el ejército
  máximo de nivel 5, y generar la escena en ≤ 1,5 s. **Sin medir.**

## 5. Casos límite

1. **Lote con una pieza mala:** se rechaza entero; el motivo lleva el índice
   de la pieza para marcarla en rojo.
2. **Pared entre dos celdas de dueños distintos:** no puede pasar; todas las
   celdas son del recinto de una ciudad.
3. **Techo sin paredes que solo se apoya en un techo vecino con pared:** vale
   (vuelo de una celda). El techo que se apoyara en ese techo volado no vale.
4. **Derribar una pared que sostiene un techo:** `sostiene`, salvo que el techo
   vaya en la misma orden o tenga otra pared o un vecino apoyado.
5. **Estación sin techo o sin acceso:** se construye (valida la colocación)
   pero queda parada; el panel dice por qué («Sin techo», «Falta un portón»).
6. **Más estaciones funcionando que el nivel:** no se puede (`limiteEstaciones`).
   Si el nivel bajara (hoy no ocurre), las que sobran se paran por orden de
   clave, sin derribarse.
7. **Construir en plena batalla de la capital:** se puede (DECIDIDO); las
   piezas no cuentan en la batalla hasta la fase 5.
8. **Capital saqueada** (pierde su batalla): las piezas no se tocan; solo el
   saqueo de afuera. El daño se ve (3.6).
9. **Patio sin sitio** (todo el recinto construido): los vehículos aparcan
   fuera de la cerca junto a la puerta principal; nunca se deja de dibujar
   uno.
10. **Plantilla del NPC que no cabe** en ninguna rotación: no encarga ese día;
    prueba al día siguiente con la siguiente plantilla del faltante, si hay.
11. **Jugador que derriba el arranque entero:** puede; se queda sin líneas, sin
    taller ni banco (en la fase 2, sin fabricar ni reparar) hasta que
    construya. Recupera todo lo que costó.
12. **Sin dinero para el lote entero:** se rechaza entero (`dinero`); la
    barra del modo construir enseña el total antes de confirmar para que no
    pase por sorpresa.
13. **En línea:** `construir` y `derribar` viajan como cualquier `ejecutar`; la
    vista de otro jugador que tenga abierta la misma base (hoy no se puede:
    solo el dueño) vería los cambios al siguiente refresco.
14. **Pieza en celda que el agua ocupa:** no válida en la fase 1
    (`fueraDelRecinto`).
15. **Ciudad nueva que nace** (hoy solo al registrar zonas): recibe su arranque
    el mismo día, antes de su primera `economia`.

## 6. Dependencias

**Depende de:**

- `economia.md`: `producir` (unidades y munición), líneas de fábrica, taller
  (F12), tope por nivel (F3), costos, decisiones del 2026-09-30. La fase 2
  cambia su «`lineas = nivel`» y su «`ritmo × nivel`» por F4 de aquí.
- `territorio-y-capitales.md`: almacén, bóveda, afuera, saqueo, vida y
  reparación de la ciudad (F1 y F1b, que F5 amplía).
- `rebeldes-y-niveles.md`: niveles 1 a 50 y tope de defensas.
- `retirada-y-recuperacion.md`: la cola del taller y la curación de soldados.
- `recoleccion-y-batallas.md`: escuadras, escena de batalla, «Ir a la
  batalla».
- `interfaz-militar.md`: radial (con «Producir munición» y «Crear soldados»
  en el 2D), paneles, barra superior, pregón.
- `diseno-de-armamento.md`: el modelo de cada vehículo del patio.
- `GUIA-3D.md` y `batalla/ESTILO-TERRENO.md`: motor, escala, estilo,
  presupuesto.

**Dependen de este documento** (hoy no lo nombran; conviene añadirlo al
tocarlos):

- `economia.md`: líneas, taller, curación y munición pasan a depender de las
  estaciones (F4); el NPC suma `planearBase` a su día (§3.12 de allí).
- `territorio-y-capitales.md`: F1 y F1b suman estanterías y cajas fuertes; su
  §3.12 («vista 3D interior», futuro) pasa a este documento.
- `interfaz-militar.md`: botón «Base», «Producir munición» y «Crear soldados»
  en el radial 2D, modo construir, «Planos», panel de estación.
- `economia.md` §9 y F2: sus cifras son con líneas compartidas; con líneas
  separadas (DECIDIDO) hay que tomar las de F4 de aquí.
- Exploradores e informes (código de c65851a): el informe de una capital
  guardará la foto de su base (fase 5).

## 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `celda` | 4 m | 3 – 6 m | Todo el kit se modela a esta medida: cambiarla obliga a rehacer las piezas. Por debajo de 4 m el portón no deja pasar un camión (2,9 m de ancho) con holgura |
| Alto de piso | 4 m | 3,5 – 6 m | Por debajo de 4 m el camión con el misil podría no caber (su alto está sin medir) |
| `R0`, `k`, `Rmax` | 1 000 / 250 / 3 000 px | 800 – 1 500 / 150 – 400 / 2 000 – 4 000 | Espacio para construir por nivel |
| `piezasMax` (300 + 150 por nivel, tope 2 000) | — | tope 1 000 – 4 000 | Libertad frente a FPS y guardado |
| Máximo de estaciones por tipo | `nivel` (estanterías 4 ×, cajas 2 ×) | — | Si se sube por encima del nivel, el nivel deja de ser el techo de la capacidad |
| Costos de F2 | tabla | × 0,5 – × 2 | Cuánto frena construir; el metal de las estaciones es lo que más pesa |
| `devolucion` al derribar | 1 (DECIDIDO) | — | Fijado por el dueño: derribar es gratis |
| Vuelo del techo | 1 celda | 0 – 2 | Porches y aleros frente a techos flotando |
| `estanteria`, `cajaFuerte` | 25 / 200 | 10 – 50 / 100 – 500 | Cuánto crece el almacén y la bóveda; más alto, menos botín |
| IA: lotes por ciudad y día | 1 | 1 – 3 | Lo rápido que el NPC se pone al día tras subir de nivel |
| IA: `diasLleno` (estanterías) | 5 de 10 | 3 – 8 | Cuándo el NPC amplía su almacén |
| Distancia de LOD de estaciones | 150 m | 80 – 250 m | Triángulos frente a calidad de lejos |

## 8. Criterios de aceptación

Los de 1 a 7 se comprueban con `luajit`, sin LÖVE; los de 8 a 10, con la escena.

1. **Determinismo:** la misma lista de órdenes `construir`/`derribar` en dos
   simulaciones da el mismo texto de `guardar()`; guardar después de construir,
   cargar y seguir da lo mismo que no parar.
2. **Reglas de apoyo** (pruebas unitarias sobre `mundo/simulacion/base.lua`):
   pared sin cimiento → `sinApoyo`; techo sin pared ni vecino apoyado →
   `sinApoyo`; dos piezas en la misma ranura → `ocupado`; celda en la plaza
   central o fuera de `R − 80 px` → `fueraDelRecinto`; estación delante de una
   puerta → `bloqueaAcceso`; un edificio completo pedido en un solo lote en
   orden → aceptado; derribar un cimiento con pared encima → `sostiene`.
3. **NPC = jugador:** la misma orden dada por la IA y por el jugador desde el
   mismo estado da el mismo resultado.
4. **Migración sin cambios:** tras cargar una partida anterior, cada capital
   tiene fosos = líneas de montaje = mesas = enfermerías = nivel (hasta 5) y un
   banco; en la fase 2, 500 días en las 4 semillas dan tanques, soldados y
   munición producidos dentro del ±3 % de lo que da la economía con líneas
   separadas y sin estaciones (F4, lo medido).
5. **La IA se pone al día:** en la fase 2, el día 500, al menos el 90 % de las
   capitales tiene líneas de montaje y fosos funcionando = nivel; y lo que
   gastan los NPC en construir queda entre 3 y 15 de dinero al día por nación
   (`economia.md` deja unos 12 de sobra). **Sin medir.**
6. **Costo por día:** `planearBase` y el recálculo de estaciones suman menos de 1 ms al día
   simulado con 22 naciones (hoy un día cuesta 25 – 49 ms).
7. **Guardado:** las piezas suman menos del 10 % del texto de `guardar()` el
   día 500 (hoy 4,1 MB).
8. **Rendimiento:** ≥ 90 FPS a 1080p en la RX 6600 con 2 000 piezas, todas las
   estaciones de nivel 5, 80 tanques, 30 lanzacohetes, 30 baterías y 48
   figuras, en el peor encuadre. **Sin medir.**
9. **Carga:** la escena se genera en ≤ 1,5 s en ese caso. **Sin medir.**
10. **La vista no decide:** el fantasma verde/rojo del modo construir usa la
    misma función de validación que la simulación; en 1 000 colocaciones al
    azar, verde ⇔ la orden se acepta.

## 9. Fases

### Fase 1: construir al instante y ver (pequeña, sin tocar la economía)

Qué entra:

- El botón «Base» del radial (ya existe) abre la escena en `abrirBase`;
  «Mapa» para volver; cámara libre de la batalla; «Ciudad sitiada» con «Ir a
  la batalla».
- Recinto y rejilla (3.2), las **6 piezas** de 3.3 y las **7 estaciones** de
  3.4, con sus costos (F2), límites (F3 y tabla 3.4), órdenes `construir` y
  `derribar` **al instante** (sin obra, sin cola, sin ritmo diario), guardado
  y migración con la plantilla de arranque.
- **Las estaciones se ven y se construyen, pero en la fase 1 aún no mandan**
  (DECIDIDO): la capacidad sigue saliendo del nivel, como hoy. Su panel dice
  qué hará y si cumpliría las condiciones (techo, acceso), para que el
  jugador aprenda a montarlas antes de que cuenten.
- Nada nuevo en el mapa 2D salvo lo que ya hace «Base». «Producir munición» y
  «Crear soldados» del radial 2D llegan con la orden `producir` de
  `economia.md`, cuando Andrés la programe (no dependen de esta fase).
- Modo construir: barra de piezas abajo, fantasma que encaja en la rejilla
  (verde o rojo con el motivo), R para girar, arrastrar para hacer filas de
  cimientos o paredes, total del lote a la vista, «Confirmar» manda una sola
  orden; modo «Derribar».
- Lo que se ve 1:1 (3.6), con defensas automáticas en el perímetro.
- Los NPC: solo su plantilla de arranque (no construyen más hasta la fase 2).

Archivos probables (ubicación según `MAPA-DEL-CODIGO.md`):

| Archivo | Quién | Qué |
|---|---|---|
| `mundo/simulacion/base.lua` (nuevo) | Andrés | Rejilla, claves, apoyo, colisión, validación, edificios y estaciones funcionando, costos (`Simulacion.base`). Puro: lo usan la simulación y la vista |
| `mundo/simulacion/plantillas.lua` (nuevo) | Andrés | Plantillas (en la fase 1, las del arranque) y la regla de colocación de 3.8.5 |
| `mundo/simulacion.lua` | Andrés | `construir` y `derribar` en `ejecutar` (pago y colocación en el mismo paso); arranque al nacer una ciudad |
| `mundo/simulacion/guardado.lua` | Andrés | Versión nueva y migración |
| `mundo/simulacion/consultas.lua` | Andrés | `Consultas:base(cid)`: foto de solo lectura (piezas, estaciones y su estado, lo de 3.6) |
| `base/escena.lua` (nuevo) | Valeria | Escena Base con el contrato de `batalla/escena.lua` |
| `base/construccion.lua` (nuevo) | Valeria | Modo construir y derribar: rayo del cursor al plano del piso con `batalla/dream/rayos.lua`, fantasma, lote, confirmación |
| `base/piezas.lua` (nuevo) | Valeria | Lotes de instancias por tipo de pieza (`batalla/dream/instancias_tono.lua`, `lote_rapido.lua`) |
| Reutilizados de `batalla/` | Valeria | `rejilla.lua`, `suelo.lua`, `color_terreno.lua`, `colocacion.lua`, `dream/vegetacion.lua`, `dream/luz.lua`, `dream/cielo.lua`, `dream/textura_terreno.lua`, `camara.lua`, `controlador_camara.lua`, `carga.lua`, `dream/lote_unidades.lua` |
| `main.lua` (`abrirBase`) | Valeria | Abrir y cerrar la escena como hoy la batalla |
| `interfaz/base.lua` (nuevo) | Valeria | Barra de piezas, panel de estación, «Mapa», «Ir a la batalla» |
| `tools/blender/kit_base.py` (nuevo) y `assets/modelos3d/base/` | Camila | Kit modular con el atlas y la paleta Synty: 6 piezas y 7 estaciones (las estaciones pueden montarse con props del pack: cajas, barriles, bidones, herramientas), `.glb` para 3Dream |

Datos de la simulación que usa: `c.x`, `c.y`, `c.casco`, `c.nivel`,
`c.mejora`, `c.vida`, `c.reparacion`, `c.soldados`, `c.tanques`,
`c.lanzacohetes`, `c.baterias`, `c.recuperando`, `n.recursos`, `n.tesoro`,
`n.afuera`, `sitiada(c)`, `topeLanzacohetes(c)`, `Simulacion.niveles`, y lo
nuevo: `c.base`, `Simulacion.base`.

Riesgo conocido: los soldados con `--dream` caen por el material `MaderaFusil`
sin UV (`GUIA-3D.md` §7).

### Fase 2: las estaciones mandan (con la economía programada)

- F4 y F5 en vigor: líneas de soldados y de vehículos separadas, taller,
  curación, banco de munición, estanterías y cajas fuertes. Los botones
  «Producir munición» y «Crear soldados» del radial 2D pasan a pedir su
  estación (3.1.8).
- `planearBase(n)` y las 7 plantillas de 3.8.2; «Planos» para el jugador.
- La fábrica y el taller se ven trabajando: el vehículo a medio montar en su
  línea, los averiados en los fosos.
- Datos: `c.fabrica`, `c.recuperando` con daño, polvorín (`c.balas`,
  `c.obuses`, `c.misiles`), `sim:puedeProducir`, tope F3.

### Fase 3: pisos y más piezas

Escaleras, rampas, techos inclinados, suelos de piso alto, barandillas,
columnas, vallas. Estaciones en pisos altos (solo las de «puerta o portón»;
fosos y líneas, solo en planta baja o con rampa). Presupuesto de piezas
revisado con medidas reales.

### Fase 4: el perímetro

Muro y puertas del recinto construibles; plataformas de lanzacohetes y
emplazamientos de baterías como estaciones exteriores (máximo: el tope de
defensas del nivel), que sustituyen a las automáticas. Ciudad viva: convoyes y
ejércitos que salen y entran por las puertas, recolectores que descargan.

### Fase 5: bases ajenas y defensa dentro

Foto de la base en el informe del explorador; batalla de capital dentro del
recinto (3.9): foto del explorador y, en persona, solo al atacarla
(DECIDIDO); piezas que no se rompen (provisional).

## 10. Decisiones y preguntas

### DECIDIDO por el dueño (2026-09-30)

Primera ronda:

1. **Construcción libre y modular**, tipo No Man's Sky: piezas para montar
   edificios y estaciones dentro; **la función la dan las estaciones**. Las
   piezas las hace Camila como un kit con el estilo y la textura Synty.
2. **Ciudad atacada:** ahora solo mirar, con «Ir a la batalla»; defender
   dentro de la base, más adelante.
3. **Cámara:** vuelo libre, como la batalla.

Segunda ronda:

4. **Todo el sistema de construcción vive solo en la escena 3D** de la
   ciudad. En el mapa 2D no se ve nada de edificios; en el radial 2D de la
   ciudad solo salen «Producir munición» y «Crear soldados» (3.1.8).
5. **Las piezas se colocan al instante al pagarlas:** sin obra por puntos ni
   ritmo diario (3.5).
6. **Estructura barata en dinero; el metal lo piden las estaciones** (F2).
7. **El nivel limita estaciones, piezas y recinto** (3.4, F1, F3).
8. **Líneas de soldados y de vehículos separadas** (F4). `economia.md` se
   midió con líneas compartidas: ver «Líneas separadas: lo medido».
9. **Estanterías y cajas fuertes amplían almacén y bóveda** sobre la base del
   nivel (F5).
10. **Las estaciones mandan desde la fase 2**; en la fase 1 se construyen y se
    ven.
11. **Base ajena:** foto del informe de explorador; en persona, solo al
    atacarla (3.9).

Tercera ronda:

12. **Se puede construir con la ciudad sitiada** (3.5.4).
13. **Derribar es gratis:** se devuelve el 100 % (3.5, derribar).

### Provisionales (sin respuesta; se usa la recomendación)

- **P1.** El mundo sigue a velocidad normal dentro de la base.
- **P2.** Las piezas no se rompen en batalla: solo se ven dañadas según la
  vida de la ciudad.
- **P3.** Techos: una tecla los muestra u oculta todos, y en el modo construir
  se ocultan solos los del piso en el que se trabaja.

### Preguntas abiertas

Ninguna en este momento.

---

## Cómo se midió

- **Contenido de las capitales:** script de un solo uso en el scratchpad de la
  sesión (fuera del repositorio). Crea el mundo con
  `depurar/mundo_prueba.lua` (5 × 5 zonas alrededor del origen), llama a
  `sim:avanzarDia()` 500 veces sin tocar ninguna regla y anota, los días 100,
  300 y 500, `nivel`, `soldados`, `tanques`, `lanzacohetes`, `baterias`,
  `recuperando` y `casco` de cada capital. Semillas 1, 7, 42 y 1234; de 13,8
  a 16,3 s por semilla. Se corrió sobre HEAD 6b21686 con los cambios sin
  commit de ese momento.
- **Guardado y costo del día:** otro script igual, semillas 1 y 42: los días
  100 y 500 mide la longitud de `sim:guardar()`, lo que tarda, y la media de
  los 20 días siguientes con `os.clock()` (por eso la segunda foto es del día
  520, no del 500).
- **Dinero y metal por día:** de `economia.md` §9 (prototipo con las
  decisiones del 2026-09-30).
- **Líneas separadas:** una copia del script de la economía en el scratchpad
  de la sesión, idéntica salvo `avanzarFabrica`, que reparte `nivel` líneas a
  las órdenes de soldados y otras `nivel` a las de vehículos; corrida junto a
  la copia sin cambios, las dos con `decidido-sueldos 500 1 7 42 1234` sobre
  HEAD 5a0158d.
- **Falta medir:** todo lo de la construcción (no hay nada programado): costo
  real de las plantillas, piezas del arranque, tamaño del guardado con piezas,
  gasto de los NPC, FPS y tiempo de carga de la escena, y el alto del camión
  lanzamisiles para el portón.

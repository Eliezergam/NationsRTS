# Movimiento de unidades en la batalla 3D: rutas, evitación, órdenes y formaciones

Diseño propio (2026-10-01) inspirado en el estudio de 0 A.D., para el paso 3 de
[batalla-despliegue-y-movimiento.md](batalla-despliegue-y-movimiento.md).
Decisión del dueño: **estudiar 0 A.D. y reescribirlo nosotros**, en palabras
propias y con nuestros datos. Aquí no hay código de 0 A.D., ni traducido: solo
lo que hace, con cifras citadas por archivo, y lo que proponemos para Nations RTS.

Lo que ya existe en nuestro código está en §9 marcado como **hoy**; lo que se
propone, como **propuesta**. Las cifras de 0 A.D. van en metros (sus unidades)
y las nuestras en px (1 px = 10 cm).

## 0. Licencia de 0 A.D. (confirmada)

Clon ligero en la carpeta temporal de la sesión (`scratchpad/0ad`, sparse
checkout de `source/simulation2`, `binaries/data/mods/public/simulation`,
`gui/session` y `LICENSE.txt`).

- `LICENSE.txt`: `source/` → **GPL versión 2 o posterior**; `binaries/data/`
  (incluye los scripts de simulación `UnitAI.js`, `Formation.js` y la interfaz
  `unit_actions.js`) → **GPL versión 2 o posterior**; el arte y el audio de
  los mods → CC BY-SA 3.0.
- Cada `.cpp`/`.h` lleva la cabecera «This file is part of 0 A.D. … GNU General
  Public License … version 2 … or any later version» (por ejemplo
  `helpers/LongPathfinder.cpp:1-16`). Los `.js` no llevan cabecera: los cubre
  `binaries/data/`.

Consecuencia: **no se puede copiar ni traducir** nada de 0 A.D. a Nations RTS
(nuestro código no es GPL). Sí se pueden estudiar sus ideas y sus números y
reescribir el sistema desde cero, que es lo que describe este documento.

## 1. Resumen

Hoy una orden de mover calcula un A* sobre una rejilla gruesa (12 m) y la
unidad sigue la ruta con un rumbo «libre» que prueba desvíos cada medio
segundo; si se atasca, hay una escalera de remedios por tiempo (pedir paso,
rehacer ruta, recular, rodear). Funciona en las pruebas (25/25 en el arnés de
control), pero se atasca de verdad en bosques y entre compañeros, no sabe si
un destino es alcanzable sin explorar toda la rejilla, no tiene cola de
órdenes y las formaciones solo existen al llegar.

La propuesta copia la **arquitectura** de 0 A.D., no su código:

1. Una **cuadrícula de pasabilidad** fina (4 m) con un bit por clase de unidad
   (soldado, tanque, lanzacohetes), ensanchada por la holgura de cada clase.
2. Un **buscador de larga distancia** (A* en 8 direcciones sobre la cuadrícula,
   con cola de prioridad y atajos por línea de vista) y un **índice jerárquico**
   por trozos que responde al instante si dos puntos están conectados y lleva
   el destino al punto alcanzable más cercano.
3. Un **buscador de corta distancia** por vértices (esquinas de los obstáculos
   cercanos, incluidas las otras unidades), con un dominio pequeño que crece
   con cada fallo. Es lo que saca a una unidad de un apuro sin recalcular
   toda la ruta.
4. Un **seguimiento de ruta** con contadores de obstrucción y remedios
   escalonados (saltar el punto, alternar buscadores, recular, rendirse).
5. **Empujones** entre unidades por cuadrícula de vecinos, con «presión» que
   frena a quien va apretado, para que los grupos fluyan sin solaparse.
6. Una **cola de órdenes** por unidad con órdenes contextuales según lo que se
   pulsa (suelo → mover; enemigo → atacar; H → mantener; R → retroceder) y
   posturas al terminar.
7. Dos **formaciones**, «cuadrado» y «esparcidos» (decididas por el dueño), con
   una sola ruta del grupo, huecos relativos y reasignación solo al girar más
   de 45°.

Y un plan en 9 pasos pequeños para Valeria, con la parte que iría a C por FFI
si Lua no alcanza (A*/JPS y empujones) y a partir de cuántas unidades.

## 2. Fantasía del jugador

Señalo un punto detrás de aquel bosque y mis tanques **salen al momento**,
rodean los árboles y el lago por el camino lógico y llegan en bloque, mirando
hacia donde quería. Si un camión se cruza, se apartan y siguen; nadie se queda
dando vueltas contra un pino. Si pulso sobre un tanque enemigo, van a por él
por terreno firme y, si cae, se quedan donde están, vigilando. Puedo encadenar
«ve ahí, luego ahí, y ataca eso» con Mayús y olvidarme. Con decenas de
escuadras y vehículos moviéndose a la vez el juego no se arrastra.

## 3. Qué hace 0 A.D. (estudio, con cifras y archivos)

Pyrogenesis (el motor de 0 A.D.) simula por **turnos de 200 ms**
(`system/TurnManager.h:55`); el movimiento se decide por turno y la vista
interpola. Esto explica muchos de sus números (los contadores «de fallos»
están en turnos).

### 3.1 Cuadrícula de pasabilidad

- Celda de navegación de **1 m** (`helpers/Pathfinding.h:143`); la baldosa de
  terreno mide 4 m (`graphics/Terrain.h:40`), así que hay 4×4 celdas por
  baldosa. Un mapa de 1 024 baldosas son 4 096² ≈ 16,8 M de celdas: por eso
  cada celda es un `u16` con **un bit por clase de pasabilidad** (hasta 16
  clases; `Pathfinding.h:125-129`).
- Clases (`mods/mod/simulation/data/pathfinder.xml`): `default` (holgura
  0,8 m, agua ≤ 2 m, pendiente ≤ 1,0), `large` (holgura 3,0 m), `ship`
  (holgura 10 m, agua ≥ 1 m), más clases de construcción. Una unidad pertenece
  a una sola clase.
- La pasabilidad de terreno sale de la **profundidad del agua, la pendiente
  por baldosa y la distancia a la orilla** (`components/CCmpPathfinder.cpp:632-668`).
  El borde del mapa se marca impasable (`:671-717`).
- Luego se **ensancha lo impasable** por la holgura de cada clase, en celdas
  (distancia de Chebyshev, con una ventana deslizante en dos pasadas;
  `:291-360`), más **1 celda extra** para que el buscador largo sea más
  estricto que el corto (`Pathfinding.h:157`).
- Obstáculos: las unidades son **cuadrados alineados a los ejes** de lado
  2×holgura; los edificios, **rectángulos girados** (`CCmpObstructionManager.cpp:59-82`).
  Solo se rasterizan sobre la cuadrícula los que tienen `BlockPathfinding`:
  los edificios sí, **las unidades no** (`template_unit.xml:47-57`,
  `BlockMovement` sí, `BlockPathfinding` no). A las unidades las esquiva el
  buscador corto y los empujones, no la cuadrícula.
- Índice espacial de obstáculos por cuadrados de 32 m (`:56`).
- Actualización incremental: una rejilla de «suciedad» marca qué celdas
  cambiaron; si cambió el terreno se recalcula la cuadrícula de terreno,
  si no se parte de ella y se vuelven a rasterizar los obstáculos
  (`CCmpPathfinder.cpp:524-567`).

### 3.2 Buscador de larga distancia (JPS sobre la cuadrícula)

- A* en 8 direcciones con coste entero (recto 65 536, diagonal 92 682 ≈
  √2×65 536; `Pathfinding.h:82`) y heurística octil; cola de prioridad en
  montículo; cada celda guarda estado (2 bits) y el delta a su predecesor
  (`LongPathfinder.h:66-125`).
- Es **Jump Point Search**: al sacar una celda no mira a sus 8 vecinas sino
  que «salta» en cada dirección permitida hasta el siguiente punto de salto
  (`LongPathfinder.cpp:467-476`). Los puntos de salto horizontales y
  verticales se **cachean por clase** en intervalos (árbol binario
  equilibrado por fila) y se invalidan al cambiar la cuadrícula
  (`:35-63`, `LongPathfinder.h:184-200`); los diagonales no se cachean porque
  son demasiado frecuentes (`:661-663`).
- Si el destino no se alcanza devuelve el camino a la **mejor celda vista**
  según la heurística (`LongPathfinder.h:154-155`).
- Los puntos de paso se **mejoran**: se quitan los que se pueden saltar en
  línea recta y se intercalan puntos para que no disten más de un máximo
  (`:921-970`); ese máximo lo fija el que mueve: 11 m, justo por debajo del
  dominio mínimo del buscador corto (`CCmpUnitMotion.h:1791-1794`).

### 3.3 Índice jerárquico (¿se puede llegar?)

- La cuadrícula se parte en **trozos de 96×96 celdas**
  (`HierarchicalPathfinder.h:165`). Dentro de cada trozo, cada conjunto de
  celdas pasables conectadas es una **región** (relleno por inundación con
  unión de etiquetas; `.cpp:50-130`). Las regiones de trozos vecinos
  conectadas por celdas adyacentes forman **aristas**; por diseño no hay
  aristas dentro de un trozo (`.h:36-42`). Inundando ese grafo salen las
  **regiones globales**: dos puntos están conectados si comparten región
  global (`.h:44-46`).
- Uso principal: **hacer alcanzable el destino**. Si el destino (punto,
  círculo o cuadrado) no es alcanzable, se sustituye por la celda alcanzable
  más cercana al centro del destino; si es alcanzable pero no es un punto, por
  la celda alcanzable del destino más cercana al origen (`.h:121-133`).
  También da «la celda pasable más cercana» a una impasable (`.h:141-145`).
- Actualización parcial: solo se rehacen los trozos sucios, pero las regiones
  globales pueden necesitar una inundación completa (`.cpp:446-457`).

### 3.4 Buscador de corta distancia (vértices)

- Grafo de **visibilidad** entre las esquinas de los rectángulos cercanos
  (obstáculos estáticos, unidades si se pide `avoidMovingUnits`, y los bordes
  entre celdas pasables e impasables del terreno), con A* euclídeo
  (`VertexPathfinder.cpp:18-30`, `:263-267`). **No se precalcula nada**: el
  grafo se rehace en cada petición, por eso «escala muy mal con el número de
  obstáculos» y debe usarse con rango limitado y poca frecuencia (`:25-30`).
- Poda por **cuadrantes**: una esquina solo se puede continuar hacia el
  cuadrante opuesto al que se llegó (`:56-86`). Las esquinas se expanden por
  la holgura de la unidad más 1/16 m (`:99`, `:612-616`).
- **Dominio**: un cuadrado de radio `rango` alrededor de la unidad, con bordes
  impasables; si el destino cae fuera, el cuadrado se desplaza hacia él
  min(d/2, 3/5·rango), salvo con rangos ≥ 46 m (`:540-564`). El rango lo
  fija el que mueve: **12 m** mínimo, **+4 m por cada turno fallido**, **56 m**
  máximo (`CCmpUnitMotion.h:61-64`, `:721-728`).
- A* **ponderado**: heurística ×4/3, o ×5/3 si hay más de 100 aristas
  («preferimos velocidad a optimalidad»; `:719-733`). Aristas ordenadas
  parcialmente por cercanía para descartar rayos pronto (`:761-779`).

### 3.5 Peticiones asíncronas y presupuesto

- Las rutas se piden con un **ticket** y se calculan **entre turnos en hilos
  de trabajo** (un buscador de vértices por hilo); dentro del turno solo se
  calculan como mucho **20** («MaxSameTurnMoves», `pathfinder.xml`;
  `CCmpPathfinder.cpp:81-89`, `:780-835`). Se espera a los hilos con
  `CancelOrWait` para mantener el determinismo (`:800-801`).

### 3.6 UnitMotion: seguir la ruta sin atascarse

Constantes (`components/CCmpUnitMotion.h:56-126`): rango de ruta directa
24 m; mínimo para pedir ruta larga 16 m; reenganche a un punto de la ruta
larga por un círculo de 4 m; incertidumbre del blanco +1 m por cada 8 m de
distancia; ruta imperfecta conocida se rehace cada 12 turnos; **35 turnos
fallidos** (7 s) para declarar el fallo; alternar buscadores en el fallo 3 y
cada 6; recular en el fallo 10; «muy obstruido» a partir de 10.

Plantilla de unidad (`template_unit.xml:123-131`): velocidad 9, correr ×1,67,
aceleración 35, giro instantáneo 1,5 rad, peso 10, clase `default`.

- **Elegir ruta** (`:1747-1783`): si el destino está a menos de 24 m y la recta
  está libre, va recto (y pide una ruta larga de todas formas por si falla);
  si está a menos de 16 m pide **solo** ruta corta (extendiendo el dominio
  hasta el destino); si no, ruta larga. En ciertos fallos se invierte la
  elección («el corto desatasca al largo y al revés»).
- **Mover por turno** (`PerformMove`, `:1140-1310`): mientras quede tiempo,
  mira al siguiente punto (primero los de la ruta corta, luego los de la
  larga). Si la diferencia de rumbo supera el giro instantáneo, **para y
  gira** a la velocidad de giro; si no, gira y escala la velocidad por
  cos(diferencia). Acelera con `aceleración`; si llega al punto en el tiempo
  que queda lo salta y sigue; cada tramo se comprueba con `CheckMovement`
  contra terreno y obstáculos y, si falla, el turno se marca **obstruido**.
  La presión de empujones baja la velocidad (desde presión 10 hasta un suelo
  de 1,5 m/s; `:1161-1180`).
- **Obstruido** (`HandleObstructedMove`, `:1330-1405`): suma el contador de
  fallos (avisa a otros componentes al 2.º fallo; al 35.º declara que no
  puede). Luego, por orden: si el destino está cerca, ruta corta directa; en
  el fallo 10, **recula 1 m** (desajuste conocido entre el buscador corto y
  `CheckMovement` en las esquinas); si el siguiente punto largo está a menos
  de max(rango/3, 8 m) lo **borra** (puede estar tapado por unidades); si toca
  alternar, **rehace la ruta larga**; si no, pide una **ruta corta hasta un
  círculo** de radio clamp(rango/9, 4 m, 12 m) alrededor del siguiente punto
  largo («avanzar en la dirección correcta, no ser exacto»).
- **Blanco móvil** (`PathingUpdateNeeded`, `:1560-1587`): solo se rehace la ruta
  si el final de la ruta ya no está a tiro del blanco, con una tolerancia que
  crece con la distancia. Si se persigue y el blanco está cerca y a la vista,
  se tira la ruta y se va recto (`TryGoingStraightToTarget`, `:1460-1520`).
- Resultado de ruta (`PathResult`, `:901-1030`): se **rechaza** una ruta que
  aleje del destino (evita el «baile» entre dos posiciones); si la larga no
  llega, se mete un punto falso en el destino para que el corto lo intente;
  si el primer punto está muy cerca, se intenta ir directo al segundo (los
  giros de una celda frenan a las unidades que tardan en girar).

### 3.7 Empujones (UnitMotionManager)

`components/CCmpUnitMotion_System.cpp` y `pathfinder.xml` (`Pushing`):

- Cuadrícula de vecinos de **20 m**; cada unidad empuja a las de su casilla y
  las cuatro vecinas, en pares (`:43-50`, `:530-540`).
- **Las que se mueven empujan a las que se mueven y las paradas a las
  paradas**, nunca cruzado (`:647-658`): así una columna no arrastra a los
  parados ni los parados frenan la columna; a los parados se los rodea con el
  buscador corto. Excepción: dentro de la misma formación se empujan todas,
  pero solo hasta su propio radio.
- Alcance del empujón: (ha + hb) × 5/7 × 1,4 + 4,0 m si se mueven (0,5 m si
  paradas); «spread» 0,4 en marcha, 0,9 paradas (`pathfinder.xml`, `:664-667`).
- Se compara la **posición media del turno** de cada par; si parece que se
  han cruzado (producto escalar < −0,1), un **empujón perpendicular fuerte**
  (×3) para que parezca que se esquivaron (`:669-720`). Si están encima, una
  dirección arbitraria por paridad del id (`:724-733`).
- Fuerza = dirección × factor de distancia (hasta 2,5 si se solapan) ×
  dt/2 × relación de pesos (máximo ×4) (`:740-763`). Fuerzas menores de 0,2 se
  ignoran (`MinimalForce`). Un empujón **nunca mete a nadie en terreno
  impasable**: se comprueba con `CheckMovement` y, si no, se anula y se marca
  obstruida (`:602-616`).
- **Presión**: cada par suma (2 + (factor − 2/3) × 5) × 0,5, tope 255, decae
  ×0,6 por turno (`:96-99`, `:766-770`). La presión amortigua los empujones
  (tope 160) y frena a la unidad; si la empujan en contra de su rumbo con
  presión > 30 se la marca obstruida (`:580-600`).

### 3.8 UnitAI: máquina de estados y cola de órdenes

`simulation/components/UnitAI.js` (6 530 líneas). Una **máquina de estados
jerárquica**: `INDIVIDUAL.{IDLE, WALKING, WALKINGANDFIGHTING, PATROL, GUARD,
FLEEING, COMBAT.{APPROACHING, ATTACKING, FINDINGNEWTARGET, CHASING}, GATHER.{…},
HEAL…}`, `FORMATIONCONTROLLER.{…}` y `FORMATIONMEMBER.{WALKING, …}` (`:690-2860`).

- **Cola**: una lista `orderQueue`; la primera es la orden en curso.
  `PushOrder` añade al final (y la ejecuta si estaba vacía), `PushOrderFront`
  la pone delante y la ejecuta ya, `ReplaceOrder` vacía y pone (`:3941-4120`).
  `AddOrder(tipo, datos, encolar, alFrente)` elige entre las tres (`:5297-5311`).
  La interfaz manda `queued` con la tecla «session.queue» (Mayús) y
  `pushFront` con «session.pushorderfront» (`gui/session/input.js:1244-1245`).
- **Terminar** (`FinishOrder`, `:3884-3935`): saca la primera; si queda otra,
  la ejecuta; si no, estado IDLE. Un miembro de formación avisa a su
  controlador.
- Cada orden entra por `Order.<Tipo>` (`:306-690`): `Walk` fija la **posición
  de guardia** (`SetHeldPosition`) y pasa a WALKING; `Attack` elige el tipo de
  ataque, recuerda la última posición del blanco, pasa a ATTACKING si está a
  tiro o a APPROACHING si no (y una unidad con postura «no te muevas» lo
  descarta); `Gather` comprueba que puede recolectar, si debe matar primero
  (caza) empuja un `Attack` al frente, si va lleno vuelve al depósito, y si no
  APPROACHING/GATHERING; `Garrison` igual con su alcance; `Stop` termina.
- **WALKING** termina cuando está a tiro del punto, cuando el movimiento
  «probablemente falla» o cuando está obstruido pero ya a menos de **12 m**
  (`DefaultRelaxedMaxRange`, `:4925`, `:1766-1770`).
- **COMBAT.APPROACHING** pide ir al alcance del blanco; cada **1 s** evalúa
  abandonar la persecución (`ShouldAbandonChase`, `:5105-5135`: blanco
  invisible, o fuera de la distancia permitida desde el puesto en postura
  defensiva, o fuera de la visión salvo postura violenta). Si falla el
  movimiento y la orden era forzada, va a la última posición conocida con
  `WalkAndFight` (`:2090-2130`).
- **IDLE** (`:1597-1705`): al entrar arma un temporizador de 100 ms (evita
  bucles infinitos) y luego busca blancos a tiro y enemigos a la vista; una
  unidad en postura defensiva que se ha alejado **más de 10 m** de su puesto
  vuelve a él. Las consultas de alcance las hace el RangeManager por eventos
  (`LosAttackRangeUpdate`), no por sondeo.
- **Posturas** (`g_Stances`, `:80-130`): violent, aggressive (persigue dentro
  de la visión), defensive (no persigue, vuelve al puesto), passive (huye),
  standground. Cada una son 8 banderas (atacar a la vista, perseguir, más allá
  de la visión, volver al puesto…).

### 3.9 Formaciones (Formation.js)

- La formación es una **entidad controladora** con su propio UnitMotion:
  velocidad = la mínima de los miembros × multiplicador, aceleración mínima,
  holgura = la máxima (`Formation.js:892-925`). Los miembros reciben la
  orden `FormationWalk` con su **desplazamiento** relativo y lo siguen con
  `MoveToFormationOffset` (`:483-576`, `UnitAI.js:1463-1480`); **corren**
  (×1,67) para no quedarse atrás (`CCmpUnitMotion.h:1157-1159`). Dentro del
  grupo de control no colisionan entre sí.
- **Huecos** (`ComputeFormationOffsets`, `:648-833`): filas de `cols`
  columnas, con cols = ceil(n / ceil(√(n / anchoEntreFondo))), limitadas por
  mínimo y máximo de columnas; cada fila alterna izquierda y derecha para ser
  simétrica; separación = huella media × multiplicador; «sloppiness»
  aleatoria; el centro de los huecos se recentra a cero. La forma `box` (lo
  que el dueño llama «cuadrado») usa relación 1 y llena hacia el centro
  (`special/formations/box.xml`); `scatter` («esparcidos») reparte al azar en
  un cuadrado de lado √n × (ancho + fondo) × 2,5 (`:716-728`).
- **Asignación**: los huecos se ordenan por tipo (héroes y caballería
  delante…) y cada unidad toma el **hueco libre más cercano** a donde está
  (`:812-832`, `:841-857`).
- **Columna** automática si el camino que queda supera **128 m**
  (`g_ColumnDistanceThreshold`, `:71`; `:522-528`): 3 columnas.
- **Giro**: al recibir una orden el controlador se recoloca en el centro de
  sus miembros mirando al destino; si el cambio de rumbo supera
  `MaxTurningAngle` (**0,785 rad** en box, 1 por defecto, 0 en scatter) se
  **recalculan y reasignan** los huecos; si no, se conservan y la formación
  gira como un bloque (`:505-520`, `:883-887`).
- Si el controlador queda **muy obstruido** (su holgura es la mayor), manda a
  los miembros moverse por su cuenta **3 s** y vuelve a intentarlo
  (`UnitAI.js:1043-1061`). Un miembro que no consigue su hueco **termina la
  orden antes que insistir** (demasiadas rutas cortas atascan el turno;
  `:1494-1504`).
- Una orden de atacar a una formación: si el blanco está a tiro, cada
  miembro ataca por su cuenta (estado `MEMBER`); si no, el bloque se acerca
  (`:770-792`).

### 3.10 El cursor: qué orden al pulsar sobre cada cosa

`gui/session/unit_actions.js` y `input.js`:

- Hay una tabla de acciones (`g_UnitActions`, `:50-1334`); cada una tiene
  `getActionInfo` (¿posible?, cursor, tooltip), `actionCheck` (sin tecla),
  `hotkeyActionCheck` (con tecla forzada), `preSelectedActionCheck` (botón
  pulsado antes) y un número de **especificidad**: cuanto más bajo, antes se
  elige. Se ordenan por él (`:1336`): gather 1, returnresource 2,
  setup-trade-route 0, heal 7, **attack 9**, capture 10, repair 11, **move
  12**, garrison 20, occupy-turret 21, patrol 37, guard 40, none 100.
- `determineAction(x, y)` (`input.js:221-282`): toma la selección, busca la
  **entidad bajo el ratón** (`PickEntityAtPoint`) y recorre las acciones en
  ese orden: primero las preseleccionadas, luego las forzadas por tecla
  (`session.attack`, `session.move`…), luego las normales. La primera posible
  gana; `move` es posible siempre que haya UnitAI, así que es el **comodín**
  cuando no hay nada más específico.
- `getActionInfo` mira **la primera entidad bajo el ratón** y la **primera
  unidad seleccionada que pueda** hacer la acción (`:1936-1965`): basta un
  recolector en la selección para que el clic en un árbol sea «talar» para
  todos (cada uno hace lo que puede; `FinishOrder` descarta lo imposible).
- El cursor cambia según la acción (`"cursor": "action-attack"`,
  `"action-gather-wood"`), se actualiza cada cuadro (`input.js:99-111`).
- Clic derecho con una acción y la tecla de cola → `queued`; con la de
  frente → `pushFront` (`:1244-1245`).

### 3.11 Los cinco hallazgos que importan para nosotros

1. **Dos buscadores con dominios distintos y un seguidor que alterna.** El
   largo es barato y estricto (cuadrícula ensanchada); el corto es caro pero
   exacto y ve a las unidades. Lo que evita los atascos no es ninguno de los
   dos, sino la **escalera de remedios por contador** de UnitMotion.
2. **Las unidades no se rasterizan en la cuadrícula.** Se evitan con empujones
   (en marcha contra en marcha, paradas contra paradas) y con el buscador
   corto. Si las metiéramos en la cuadrícula habría que rehacerla cada paso.
3. **Alcanzabilidad en O(1)** con regiones por trozos, y destino movido al
   punto alcanzable más cercano. Sin esto, un destino en una isla obliga al
   A* a explorar toda la cuadrícula.
4. **La formación es una unidad más** con la holgura mayor y la velocidad
   menor; los miembros persiguen un desplazamiento y solo se reasignan huecos
   al girar más de 45°. Y «si no llegas a tu hueco, deja de intentarlo».
5. **La orden la decide la tabla de acciones por especificidad**, mirando lo
   que hay bajo el ratón y lo que puede la selección; «mover» es el comodín.
   La cola de órdenes es una lista con tres operaciones (añadir, al frente,
   sustituir) y una regla: al terminar, siguiente o reposo con postura.

## 4. Reglas (propuesta para Nations RTS)

### 4.1 Cuadrícula de pasabilidad

1. Al abrir la escena se construye **una** cuadrícula sobre el círculo del
   límite (`Limite.radio` = 12 000 px): celdas de `celda` px (propuesta: 40 px
   = 4 m), n = ⌊2·12 000 / 40⌋ + 1 = 601 por lado, **361 201 celdas**, en un
   array FFI de `uint8_t` (361 KB).
2. Cada celda lleva **3 bits**, uno por clase: `soldado`, `tanque`,
   `lanzacohetes` (bit a 1 = **no** se pasa). Quedan 5 bits libres (futuro:
   `aviación en tierra`, `construcción`).
3. Pasabilidad base de terreno por celda (centro de la celda): fuera del
   límite (margen `Ordenes.margen` = 150 px) → todas; agua u orilla
   (`agua:enAgua(x, y)` y a 80 px) → todas salvo donde una calzada de
   `pasillos.lua` aplanó el terreno (se lee la altura final: seca = pasable);
   desnivel bajo el casco (`suelo:desnivel(x, y, 55)` > `Suelo.maxDesnivelVehiculo`
   = 42 px) → tanque y lanzacohetes (el soldado pasa hasta 2× ese desnivel;
   perilla); edificio (`suelo:ocupado`) → todas.
4. Obstáculos estáticos rasterizados: **troncos** de árbol (radio
   `RADIO_TRONCO` de `colocacion.lua`, 0,22-0,55 m: una celda), **rocas**
   (su radio), **edificios** (su rectángulo). Los arbustos y la hierba no
   estorban.
5. Ensanche por holgura, en celdas: soldado **0**, tanque **2**
   (`radioTransitable.tanque` = 62 px → ⌈62/40⌉), lanzacohetes **3**
   (86 px → ⌈86/40⌉). Como en 0 A.D., el ensanche hace al buscador largo más
   estricto que el corto: un vehículo nunca recibe una ruta que roce un árbol.
6. **Las unidades no se rasterizan.** Un vehículo inmóvil (oruga o motor
   rotos, `Blindaje.inmovil`) o averiado se trata como obstáculo **para el
   buscador corto** y para los empujones (parado), no para la cuadrícula.
7. La cuadrícula es inmutable durante la batalla salvo que se derribe un
   árbol o se destruya un edificio (hoy los vehículos solo se averían); en
   ese caso se rehace solo el **trozo** afectado (§4.2) y se invalida la caché
   de saltos si la hay.

### 4.2 Índice jerárquico

1. Trozos de **64×64 celdas** (256 m): ⌈601/64⌉ = 10 → **100 trozos** por clase.
2. Por trozo y clase, regiones conexas (relleno por inundación con unión de
   etiquetas); por par de trozos vecinos, aristas entre regiones que comparten
   celdas pasables adyacentes; región global = componente conexa del grafo.
3. `alcanzable(x0, y0, x1, y1, clase)` = misma región global, en O(1) tras
   localizar celdas.
4. `hacerAlcanzable(origen, destino, clase)`: si la celda del destino es
   impasable o de otra región global, se devuelve la celda pasable **de la
   región global del origen** más cercana al destino (se recorren las regiones
   de los trozos por distancia creciente al destino y se para cuando ningún
   trozo más cercano puede mejorar). Si el origen está en celda impasable
   (una unidad metida en un árbol tras un empujón de la física), primero se
   le busca la celda pasable más cercana.
5. Toda orden de mover o atacar pasa por `hacerAlcanzable` **antes** de pedir
   ruta: el marcador «sinRuta» desaparece; la unidad va **lo más cerca
   posible** y termina allí.

### 4.3 Buscador de larga distancia

1. A* en **8 direcciones** sobre la cuadrícula de la clase, coste recto 10,
   diagonal 14 (enteros), heurística octil, montículo binario con arrays FFI
   (`int32_t` para coste g y predecesor como delta empaquetado, `uint8_t` para
   estado), reutilizados entre peticiones con un **número de época** para no
   limpiarlos (como la rejilla de suciedad de 0 A.D. pero más simple).
2. Las diagonales no cortan esquinas: solo si las dos celdas ortogonales son
   pasables (hoy `Pasillos.aEstrella` ya lo hace, `pasillos.lua:270-274`).
3. El destino puede ser **punto**, **círculo** (atacar: «a menos de
   alcance×0,85 del blanco») o **cuadrado** (edificio). Se termina al sacar
   del montículo una celda dentro del destino.
4. Si se agota el montículo sin llegar (no debería pasar tras
   `hacerAlcanzable`), se devuelve el camino a la **mejor celda vista**.
5. Los puntos de paso se **adelgazan**: desde cada punto, al más lejano que se
   vea en línea recta sobre la cuadrícula (hoy `Ordenes:recta`), y se
   **intercalan** puntos para que ninguno diste más de `espaciadoLargo`
   (propuesta: 440 px) del anterior; así el buscador corto siempre tiene un
   punto largo dentro de su dominio mínimo.
6. **Presupuesto**: las peticiones entran en una cola ordenada por id de
   unidad y se atienden como mucho `rutasPorPaso` (propuesta: 8) por paso
   fijo; el resto espera al siguiente paso (la unidad sigue con lo que tenía o
   se queda quieta un paso). Determinista: mismo orden, mismo resultado, sin
   hilos. Si una ruta tarda más de `presupuestoMs`, se mide y se pasa a C (§8).
7. Opción posterior (paso 9 del plan): **JPS** con caché de saltos por clase
   (como 0 A.D.) solo si la medida de A* en C no basta con cientos de unidades.

### 4.4 Buscador de corta distancia

1. Dominio: cuadrado de radio `rangoCorto` alrededor de la unidad, con cuatro
   aristas impasables; `rangoCorto` = 480 px (48 m) + 160 px por intento
   fallido, máximo 2 240 px (224 m). Si el destino cae fuera, el cuadrado se
   desplaza hacia él min(d/2, 3/5·rango) salvo en los rangos mayores.
2. Obstáculos del grafo: rectángulos (y cuadrados) dentro del dominio ampliado
   por la holgura: troncos, rocas, edificios, **bordes entre celdas pasables e
   impasables del terreno** (de la cuadrícula de la clase **sin** ensanchar,
   porque la holgura se aplica aquí a cada esquina) y, si se pide
   `evitarUnidades`, los cuadrados de las unidades **paradas** (y de las en
   marcha de otro bando). Las del propio grupo se ignoran.
3. Vértices = esquinas expandidas por la holgura + 4 px, con sus cuadrantes
   permitidos (poda como en 0 A.D.: se entra por un cuadrante y se sale por el
   opuesto). A* euclídeo **ponderado ×4/3** (×5/3 con más de 100 aristas),
   visibilidad perezosa (se comprueba la recta solo cuando se abre un vértice).
4. Se llama **solo** cuando el seguimiento lo pide (obstrucción o destino
   cercano), nunca cada cuadro. Devuelve pocos puntos; la unidad los recorre
   y, al acabarlos, vuelve a la ruta larga por el siguiente punto largo.

### 4.5 Seguimiento de ruta (por unidad, cada paso fijo de 1/60 s)

Un «**turno**» de decisión son 12 pasos fijos (0,2 s). Los contadores de abajo
cuentan turnos.

1. Si no hay puntos: obstruido (ir al punto 5).
2. Punto objetivo = primero de la ruta corta si la hay; si no, de la larga.
3. **Giro**: tanque y soldado giran sobre sí mismos (`giroCasco` 0,5 rad/s,
   `giroSoldado` 1,8 rad/s). Si la diferencia de rumbo supera `giroInstantaneo`
   (tanque 0,6 rad, soldado 1,5 rad) la unidad **para y gira**; si no, gira
   mientras avanza y la velocidad se escala por cos(diferencia). El
   lanzacohetes no gira en el sitio: va por `Fisica:conducir` con dirección de
   ruedas (ya existe) y, si el punto queda dentro de su círculo de giro, da
   **marcha atrás** con las ruedas al revés (hoy `maniobra`, `tropas.lua:2335-2360`).
4. **Avance**: velocidad objetivo = `velocidadOrden` (60 px/s) × velocidad del
   modelo × (1 − frenado por presión); aceleración `aceleracion` (tanque
   30 px/s², soldado 80 px/s²). Antes de mover se comprueba el tramo
   (`segmentoLibre` contra cuadrícula de la clase + unidades según §4.6); si
   el punto cae dentro del tramo se consume y se sigue con el resto del paso.
   Si el tramo falla → obstruido.
5. **Obstruido** (una vez por turno, no por paso):
   - `fallos += 1`. Al 2.º se avisa a la orden (puede cambiar de blanco o
     cerrar); al **35.º** (7 s) la orden **falla** y se cierra (la unidad se
     queda donde está, estado «en puesto»).
   - Si el destino está a menos de `distanciaCorta` (640 px): ruta corta
     directa al destino.
   - En el fallo **10**: recular 40 px (una celda) marcha atrás si hay sitio
     (hoy `libreDetras`).
   - Si el siguiente punto largo está a menos de max(rango/3, 320 px): se
     **borra** (puede estar tapado por unidades).
   - En el fallo 3 y luego cada 6: **rehacer la ruta larga** desde aquí.
   - Si no: pedir **ruta corta hasta un círculo** de radio clamp(rango/9,
     160, 480 px) alrededor del siguiente punto largo.
6. **Cada turno sin obstrucción** `fallos = 0`.
7. **Destino móvil** (atacar): solo se rehace la ruta si el último punto ya no
   deja al blanco a tiro, con tolerancia +40 px por cada 320 px de distancia;
   si el blanco está a menos de `rutaDirecta` (960 px) y la recta está libre,
   se tira la ruta y se va recto.
8. **Llegada**: punto intermedio consumido a `llegarPaso` (hoy 350 px → con
   puntos cada 440 px, bajar a 160 px); último punto a `llegar[tipo]` (hoy
   90/260/40 px). Obstruida y a menos de `llegadaRelajada` (120 px) del
   último → llegada.

### 4.6 Empujones y colisión entre unidades

1. Cuadrícula de vecinos de **200 px** (20 m) por bando y para todos; cada
   paso de decisión (cada turno, 0,2 s; no cada paso fijo) se calculan los
   pares dentro de la casilla y las cuatro vecinas.
2. **En marcha empuja a en marcha; parada empuja a parada**; nunca cruzado.
   Dentro de un mismo grupo (formación) se empujan todas pero solo hasta la
   suma de radios.
3. Alcance = (ra + rb) × 1,4 + 200 px si ambas en marcha (40 px si paradas);
   la fuerza es 1 en la «separación extendida» (alcance × 0,4 en marcha, ×0,9
   paradas) y sube hasta 2,5 si se solapan; se multiplica por 0,1 s (dt/2) y
   por la relación de **pesos** (tanque 40, lanzacohetes 25, soldado 1; tope
   ×4): un tanque aparta a una escuadra, nunca al revés.
4. Si dos unidades parecen haberse cruzado en el turno, un empujón
   perpendicular fuerte (×3) en el lado que las separa.
5. **Presión**: cada par suma (2 + (factor − 2/3) × 5) × 0,5 (tope 255,
   decae ×0,6 por turno); amortigua el empujón (tope 160) y frena la
   velocidad desde 10 hasta un suelo de **10 px/s**. Con presión > 30 y
   empujón contrario al rumbo: obstruida (entra en §4.5.5).
6. Empujones menores de 1 px por turno se ignoran. **Nunca** empujan a terreno
   impasable: se comprueba el tramo contra la cuadrícula (soldado) o se deja
   a Box2D (vehículos, que ya chocan con árboles y agua por `fisica.lua`).
7. Vehículos: el empujón es una **velocidad deseada** que se suma a la de
   marcha antes de `Fisica:impulsar`/`conducir`; Box2D sigue resolviendo el
   contacto real. Soldados (cinemáticos): el empujón se aplica a la posición
   directamente (como en 0 A.D.).

### 4.7 Órdenes: cola, órdenes contextuales y fin de orden

1. Cada unidad tiene una **cola** `u.ordenes` (lista); `u.orden` es la
   primera. Operaciones: `anadir` (al final; si estaba vacía, se ejecuta),
   `alFrente` (delante y se ejecuta ya), `sustituir` (vacía y añade).
2. Teclas: clic derecho → `sustituir`; **Mayús + clic derecho** → `anadir`;
   **Alt + clic derecho** → `alFrente` (perilla; decisión pendiente, §11).
3. **Qué orden según lo pulsado** (tabla por especificidad, la más baja gana;
   mira la unidad bajo el ratón y la primera seleccionada que pueda):

   | Especificidad | Bajo el ratón | Selección que puede | Orden | Cursor |
   |---|---|---|---|---|
   | 1 | unidad enemiga viva (no retirada) | cualquiera con arma | **atacar** (blanco fijo) | mira roja |
   | 5 | suelo transitable, con Ctrl | cualquiera | **atacar avanzando** (va al punto y dispara a lo que vea; persigue hasta 1 alcance) — decidido: sí | mira + flecha |
   | 12 | suelo (cualquiera) | cualquiera móvil | **mover** (en formación activa) | flecha verde |
   | 100 | nada / fuera del suelo | — | ninguna | prohibido |

   Teclas sin ratón: **H** mantener posición (`sustituir`; con Mayús,
   `anadir`); **R** retroceder (marcha atrás `retroceso` = 400 px hacia su
   propio lado del campo, mirando al enemigo, por terreno transitable; con
   Mayús se encola); **Esc** vacía la cola (`sustituir` nada).
   Sin talar ni recolectar: en nuestra batalla no hay recursos.
4. **Al terminar una orden** (`terminarOrden`): se saca de la cola; si hay
   otra, se ejecuta; si no, la unidad queda **en puesto**: fija su posición de
   guardia donde está y su **postura** decide (elegible por unidad; decidido
   por el dueño: por defecto **defensiva**):
   - *agresiva*: dispara a lo que tenga a tiro y, si el blanco se aleja, lo
     persigue hasta `persecucion` = 1 alcance desde el puesto; luego vuelve
     al puesto.
   - *defensiva* (por defecto): dispara sin moverse; si un empujón la aleja
     más de 100 px del puesto, vuelve.
   - *mantener* (orden H): como defensiva y además no se aparta ni cede el paso.
5. **Cuándo termina cada orden**:
   - mover: llegada (§4.5.8) o fallo a los 35 turnos (se queda donde está).
   - atacar: el blanco muere, se retira o deja de ser alcanzable 5 s seguidos
     (se cierra y pasa a la siguiente); si está a tiro y a la vista, dispara
     y **no** termina hasta que caiga.
   - mantener: nunca sola; la quita otra orden.
   - retroceder: llegada o fallo.
   - atacar avanzando: llegada al punto (dispara por el camino a lo que vea y
     persigue hasta 1 alcance de su posición actual; luego sigue al punto).
6. Una unidad **inmóvil** (`Blindaje.inmovil`) que recibe mover/retroceder la
   descarta al momento y pasa a la siguiente (hoy ya pasa a mantener).
7. Un lanzacohetes **elevado** no se mueve: la orden de mover espera a que
   baje el contenedor (hoy `elevacion > 0` lo bloquea) y luego sigue.

### 4.8 Formaciones

1. Dos formaciones, elegidas por el jugador (botones o teclas F1/F2; perilla):
   **cuadrado** y **esparcidos**. La selección actual recuerda la última.
2. Un grupo con orden de mover es una **unidad virtual** («guía») con:
   posición = centro de los miembros, rumbo = hacia el primer punto de la
   ruta, holgura = la mayor de sus miembros (clase = la más restrictiva),
   velocidad = la menor × 1,0. **Una sola ruta larga** para la guía (hoy ya:
   `Control:moverA` calcula desde el centroide).
3. **Huecos** (desplazamientos relativos a la guía, eje x = lateral, eje y =
   hacia atrás), por tipo y en este orden de delante hacia atrás: tanques,
   escuadras, lanzacohetes (hoy `Ordenes.orden`):
   - *cuadrado*: para `n` unidades de un tipo, filas de `cols` columnas con
     cols = ⌈n / ⌈√(n / `anchoEntreFondo`)⌉⌉ (propuesta `anchoEntreFondo` =
     2: más ancho que hondo), separación lateral `Ordenes.separacion[tipo]`
     (230/320/80 px) y entre filas `Ordenes.entreFilas[tipo]` (260/340/90);
     cada fila alterna izquierda y derecha; el bloque de cada tipo va detrás
     del anterior con 120 px de margen; los huecos se recentran a media cero.
   - *esparcidos*: los mismos huecos del cuadrado con separación ×2,5 y un
     **desorden determinista** de ±25 % de la separación por `Ruido.hash`
     (semilla, índice del hueco): ni azar ni `math.random`.
4. **Asignación**: cada unidad toma el hueco libre **más cercano** a donde
   está, dentro de su tipo, empezando por las más lejanas al destino (hoy ya,
   `Ordenes:formacion`). Un hueco que cae en celda impasable para su clase se
   lleva a la pasable más cercana (hoy la espiral `Ordenes:holgado`).
5. **Giro**: la guía mira hacia donde va. Si el rumbo cambia menos de
   `maxGiro` = 0,785 rad respecto al que tenían los huecos, se conservan y la
   formación gira como un bloque; si cambia más, se recalculan y reasignan
   (nadie cruza a nadie). Al llegar, todos quedan mirando el rumbo final de la
   ruta, o el rumbo que arrastró el jugador: decidido por el dueño, igual que
   en la preparación (clic mira al enemigo, arrastrar fija el rumbo; §13.7).
6. **Miembros**: cada uno persigue su hueco (posición de la guía + hueco
   girado) con el seguimiento de §4.5 y clase propia; **corre** (×1,25) si se
   queda a más de 1 separación detrás; dentro del grupo no colisionan por
   cuadrícula (solo empujones hasta la suma de radios).
7. **Guía muy obstruida** (10 fallos): los miembros van 3 s por su cuenta
   hasta el siguiente punto largo de la guía y luego se reagrupan. Un miembro
   que no alcanza su hueco en 35 turnos **termina su orden** y se queda (no
   insiste: lo mismo que 0 A.D. y lo que hoy hace `llego` por atasco).
8. Al **atacar** con un grupo: el grupo se acerca en formación hasta que el
   blanco está a tiro del miembro más retrasado; entonces cada uno ataca por
   su cuenta.
9. **Columna** en pasillos estrechos: *opción*. 0 A.D. pasa a 3 columnas si el
   camino supera 128 m. Nuestros pasillos de avance miden 100 m de ancho
   (`Pasillos.mitad` = 500 px); un cuadrado de 8 tanques mide 7 × 230 =
   1 610 px (161 m) de ancho y **no cabe**. Opciones en §11.

## 5. Fórmulas

| Fórmula | Variables | Rango esperado | Ejemplo |
|---|---|---|---|
| Celdas por lado n = ⌊2R / c⌋ + 1 | R = 12 000 px, c = 40 px | 401 (c = 60) … 601 (c = 40) | c = 40 → n = 601; 361 201 celdas; 361 KB en uint8 |
| Ensanche e = ⌈radio / c⌉ | radio 22/62/86 px | 0 … 3 celdas | tanque: ⌈62/40⌉ = 2 |
| Trozos t = ⌈n / 64⌉² | n = 601 | 49 (n = 401) … 100 | 10² = 100 trozos por clase |
| Coste A* (entero) | recto 10, diagonal 14 | — | 5 rectos + 2 diagonales = 78 |
| Heurística octil h = 10·max(dx, dy) + 4·min(dx, dy) | dx, dy en celdas | admisible | dx = 10, dy = 3 → 112 |
| Rango corto r = 480 + 160·max(0, fallos − 1), tope 2 240 px | fallos 0 … 35 | 480 … 2 240 px | 5 fallos → 1 120 px |
| Desplazamiento del dominio = min(d/2, 3r/5) si d ≥ r y r < 1 840 | d = distancia al destino | 0 … 1 104 px | r = 480, d = 2 000 → 288 px |
| Velocidad con giro v = vMax · cos(Δrumbo) si Δ ≤ giroInstantáneo; 0 si no | Δ en rad | 0 … vMax | Δ = 0,5 → 0,88·vMax |
| Distancia por paso con aceleración d = v·t + a·t²/2 | a = 30 px/s², t = 1/60 | — | v = 0 → 0,004 px; v = 60 → 1,0 px |
| Alcance de empujón A = (ra + rb)·1,4 + ext | ext 200 (marcha) / 40 (paradas) px | 2 escuadras paradas: 102 px; 2 tanques en marcha: 374 px | tanque-escuadra en marcha: (62 + 22)·1,4 + 200 = 318 px |
| Factor de distancia f = clamp((A − d) / (A − A·s), 0, 2,5) | s = 0,4 marcha / 0,9 paradas | 0 … 2,5 | A = 374, s = 0,4, d = 200 → 0,78 |
| Empujón = f · 0,1 s · min(pb/pa, 4) | pesos 40/25/1 | — | escuadra empujada por tanque: ×4 (tope); tanque por escuadra: ×1/40 |
| Presión añadida = ⌊(2 + (f − 2/3)·5)·0,5⌋ | f | 0 … 10 por par | f = 0,78 → 1 |
| Frenado v' = v·(165 − min(165, max(0, p − 10)))/165, mínimo 10 px/s | p = presión 0 … 255 | 10 … v | p = 90 → 0,52·v |
| Tolerancia de blanco móvil = 40·(d / 320) px | d | 0 … 300 px | d = 1 600 → 200 px |
| Columnas del cuadrado cols = ⌈n / ⌈√(n / 2)⌉⌉ | n por tipo | — | 12 tanques: ⌈√6⌉ = 3 filas → 4 columnas; 8 → 2 filas → 4; 40 → ⌈√20⌉ = 5 filas → 8 |
| Ancho del cuadrado = (cols − 1)·sep | sep 230 px | — | 8 tanques: 690 px (69 m); 40: 1 610 px |
| Lado de esparcidos = √n · (sep + entreFilas) · 2,5 | — | — | 12 tanques: 3,46·490·2,5 = 4 243 px (424 m) — **demasiado**; por eso se propone separación ×2,5 y no el lado de 0 A.D. |
| Rutas por paso = 8 → latencia máxima = ⌈peticiones / 8⌉ pasos | — | — | 88 unidades a la vez → 11 pasos = 0,18 s |

## 6. Casos límite

| Caso | Qué pasa exactamente |
|---|---|
| Destino en el agua o en un edificio | `hacerAlcanzable` lo lleva a la celda pasable de la región del origen más cercana; el marcador se dibuja en el punto real y la ruta termina en el corregido. |
| Destino en una isla (otra región global) | Igual: la celda más cercana **de este lado**; la unidad llega a la orilla y termina. Nunca «sin ruta». |
| Unidad dentro de un árbol o en celda impasable (empujón físico) | Se le busca la celda pasable más cercana como origen; la física (Box2D) la saca del tronco; si en 35 turnos no se ha movido, la orden falla. |
| Vehículo inmóvil en medio del pasillo | No está en la cuadrícula; los demás lo ven como obstáculo **parado** en el buscador corto y lo rodean; nadie lo empuja (parado contra en marcha no se empujan). |
| Dos columnas se cruzan de frente | Empujón perpendicular (×3) al detectar cruce; presión frena a los apretados; si alguien queda contra un árbol, recula en el fallo 10. |
| Formación que no cabe en el pasillo (bosque a los lados) | Los huecos exteriores caen en celdas impasables y se llevan a la pasable más cercana (se estrecha solo al llegar); en marcha, los exteriores se obstruyen, van por su cuenta 3 s hacia el siguiente punto largo de la guía y se reagrupan. Decisión de columna en §11. |
| Blanco que cruza un río | Tolerancia de blanco móvil; al quedar fuera de la región alcanzable, atacar lo lleva a la orilla más cercana a él (círculo de alcance); si está a tiro desde allí, dispara. |
| Blanco muere a mitad de camino | `terminarOrden`: siguiente de la cola o en puesto donde está (no sigue avanzando). |
| Unidad del grupo se avería en marcha | Se saca del grupo; los huecos se reasignan solo si cambia el rumbo (> 45°) o al recibir otra orden; su hueco queda vacío. |
| Cola con 10 órdenes y Esc | Se vacía entera; la unidad queda en puesto donde está. |
| Orden de mover en preparación | No se calcula ruta: colocación instantánea (paso 2 del despliegue). Las órdenes encoladas durante la preparación (Mayús) se guardan y se ejecutan al empezar el combate (decidido, §13.8). |
| Pausa (P) | No avanzan los pasos fijos: nada se recalcula; las peticiones pendientes esperan. |
| Lanzacohetes con el contenedor elevado | La orden de mover espera (baja el contenedor en 2,5 s y luego arranca); si está lanzando una salva, termina la salva. |
| 35 turnos obstruida a 120 px del hueco | Llegada relajada: cuenta como llegada. |
| Más de 8 peticiones de ruta en un paso | Se atienden por id; las demás en el paso siguiente; nadie se mueve «mal» mientras espera: sigue su ruta anterior o está parada. |
| Unidad sin munición | Hoy no avanza ni dispara: con cola, descarta atacar; mover y retroceder se cumplen igual (decidido, §13.9). |
| Red (Tomás) | Una orden es un comando `{unidad, tipo, x, y, blanco, modo}` aplicado en un paso fijo concreto; rutas y empujones son deterministas (sin hilos, arrays FFI, orden por id). |

## 7. Dependencias

**Este sistema lee de:**
- `batalla/suelo.lua`: altura, desnivel, `ocupado`, `plantaCerca`, `limite`, `pasillos`, `nivelMar`.
- `batalla/agua.lua`: `enAgua(x, y, radio)`.
- `batalla/colocacion.lua`: árboles y rocas con sus radios (`RADIO_TRONCO`, rocas).
- `batalla/limite.lua`: círculo del campo.
- `batalla/tropas.lua`: unidades, tipos, `radioTransitable`, velocidades, `Blindaje.inmovil`, `elevacion`, bando, reloj, `pasoFijo`.
- `batalla/fisica.lua`: `impulsar`, `conducir`, Box2D para vehículos.
- `mundo/ruido.lua`: `Ruido.hash` para el desorden de «esparcidos».

**De este sistema dependen:**
- `batalla/control.lua` (selección y órdenes del jugador): tabla de acciones, cola, cursores.
- `batalla/despliegue.lua` paso 4: el **NPC** avanza con un plan usando las mismas órdenes y formaciones (regla del dueño: NPC y jugador, las mismas acciones).
- `batalla/ordenes.lua`: hoy la rejilla y la ruta; se sustituye por los módulos nuevos (§8).
- `batalla/pasillos.lua`: se mantiene para la IA «de siempre» y para aplanar calzadas; sus celdas de 80 px no se usan para rutas de órdenes.
- Camila: cursores (mira, flecha, escudo, prohibido) e iconos de las dos formaciones y posturas.
- Tomás: comandos de orden serializables y determinismo del paso fijo.
- Elena: arneses `pruebas_control` y uno nuevo `pruebas_movimiento` (§10).
- La simulación (Andrés) **no cambia**: el resultado de la batalla sigue saliendo de `Tropas:resultado`.

## 8. Perillas de ajuste

Todas son propuestas de partida, **sin medir** salvo donde se indica. Rango
seguro = donde no rompe la lógica; el efecto, en una línea.

| Perilla | Propuesta | Rango seguro | Efecto |
|---|---|---|---|
| `Cuadricula.celda` | 40 px | 30 … 80 | Más fina: rutas más fieles entre árboles y 2,25× más celdas por cada paso de 40→30 (tiempo y memoria). Hoy 120 px: 40 401 celdas en 50,8 ms (medido). |
| `Cuadricula.holgura[tipo]` (celdas) | 0 / 2 / 3 | 0 … 4 | Más holgura: menos atascos contra árboles, más bosques cerrados al vehículo. |
| `Cuadricula.desnivelSoldado` | 2× `maxDesnivelVehiculo` (84 px) | 1 … 3× | Hasta qué pendiente sube la infantería donde no sube un tanque. |
| `Jerarquico.trozo` | 64 celdas | 32 … 128 | Trozos grandes: menos aristas, inundaciones más caras al rehacer un trozo. |
| `Largo.espaciado` | 440 px | 320 … 600 | Debe ser < `Corto.rangoMinimo`: si no, el corto no ve el siguiente punto largo. |
| `Largo.rutasPorPaso` | 8 | 2 … 32 | Más: menos latencia al mandar a muchos, picos de ms en el paso. |
| `Corto.rangoMinimo` / `incremento` / `maximo` | 480 / 160 / 2 240 px | 320-800 / 80-320 / 1 600-3 200 | Dominio grande: encuentra salidas lejanas pero cuesta mucho más (grafo completo por petición). |
| `Corto.peso` | 4/3 (5/3 con > 100 aristas) | 1 … 2 | Más peso: más rápido, rutas hasta ese factor peores. |
| `Seguir.turno` | 12 pasos (0,2 s) | 6 … 30 | Define todos los contadores; más corto reacciona antes y recalcula más. |
| `Seguir.maxFallos` | 35 turnos (7 s) | 15 … 60 | Bajo: unidades que se rinden en multitudes; alto: parecen tontas más tiempo. |
| `Seguir.alternarEn` / `alternarCada` | 3 / 6 | 2-5 / 4-10 | Cuándo probar el otro buscador. |
| `Seguir.recularEn` | 10 | 5 … 20 | Cuándo dar marcha atrás una celda. |
| `Seguir.distanciaCorta` | 640 px | 400 … 1 200 | Por debajo, solo ruta corta: más barata y más exacta. |
| `Seguir.rutaDirecta` | 960 px | 400 … 1 600 | Por debajo y con recta libre, sin ruta: suaviza persecuciones. |
| `Seguir.giroInstantaneo[tipo]` | 0,6 / — / 1,5 rad | 0,2 … 1,6 | Alto: no para a girar (rápido, feo en tanques). |
| `Seguir.aceleracion[tipo]` | 30 / 20 / 80 px/s² | 10 … 200 | Arranques y frenadas; con `velocidadOrden` 60 px/s un tanque llega a su velocidad en 2 s. |
| `Seguir.llegarPaso` / `llegadaRelajada` | 160 / 120 px | 80-350 / 60-200 | Cuándo se da por consumido un punto o por llegada un atasco cercano. |
| `Empuje.casilla` | 200 px | 100 … 800 | Casi no cambia el coste (0 A.D. probó de 10 a 80 m). |
| `Empuje.radio` / `extParada` / `extMarcha` | 1,4 / 40 / 200 px | 1-2 / 0-100 / 0-400 | Distancia máxima de empujón; alto: huecos exagerados en marcha. |
| `Empuje.spreadMarcha` / `spreadParada` | 0,4 / 0,9 | 0,2-0,9 / 0,5-1 | A qué parte del alcance la fuerza es «completa». |
| `Empuje.minimo` | 1 px/turno | 0,5 … 4 | Por debajo se ignora (evita temblores). Si ≥ 1/4 del alcance, pares que se solapan. |
| `Empuje.peso[tipo]` | 40 / 25 / 1 | 1 … 100 | Quién aparta a quién (tope ×4). |
| `Empuje.presionFuerza` / `presionDecaimiento` | 0,5 / 0,6 | 0,2-1 / 0,3-0,9 | Cuánto frena ir apretado y cuánto dura. |
| `Empuje.velocidadSuelo` | 10 px/s | 5 … 30 | Por debajo no frena más (evita «fluido viscoso»). |
| `Ordenes.persecucion` | 1 alcance | 0,5 … 2 | Hasta dónde persigue una unidad agresiva desde su puesto. |
| `Ordenes.retroceso` | 400 px | 200 … 1 000 | Cuánto recula R sin clic. |
| `Ordenes.abandonarAtacar` | 5 s | 2 … 15 | Blanco inalcanzable: cuándo pasar a la siguiente orden. |
| `Formacion.anchoEntreFondo` | 2 | 1 … 4 | 1 = cuadrado real; 4 = línea. |
| `Formacion.separacion[tipo]` / `entreFilas[tipo]` | 230/320/80 · 260/340/90 px (hoy) | ≥ 2 radios | Densidad del cuadrado. |
| `Formacion.esparcidosFactor` / `desorden` | 2,5 / 0,25 | 1,5-4 / 0-0,4 | Cuánto se abren y cuánto se desordenan los esparcidos. |
| `Formacion.maxGiro` | 0,785 rad | 0,3 … 1,6 | Giro a partir del cual se reasignan huecos (0 = siempre, como scatter en 0 A.D.). |
| `Formacion.correr` | ×1,25 | 1 … 1,67 | Cuánto acelera un miembro rezagado. |
| `Formacion.sueltos` | 3 s | 1 … 10 | Cuánto van por su cuenta si la guía se bloquea. |

## 9. Qué tenemos hoy y qué falta

**Hoy** (`batalla/`; medido con `python3 batalla/pruebas_control/ejecutar.py <carpeta> 42`, sin ventana, 2026-10-01; 25 comprobaciones, 0 fallos; 12 tanques y 6 lanzacohetes por bando, infantería de prueba):

- **Rejilla** (`ordenes.lua:45-94`): celdas de **120 px** (12 m) sobre el
  límite, 201² = 40 401 celdas, `prohibida[k]` según `Tropas:libre(x, y,
  true, 'tanque')` en el centro: **una sola clase** (tanque) para todos,
  infantería incluida. Construida una vez al abrir la escena: **50,8 ms**,
  14 400 celdas libres (medido).
- **Ruta** (`Ordenes:ruta`, `:154-198`): `Pasillos.aEstrella` (A* 8
  direcciones, montículo binario en tablas Lua, coste con pendiente y río,
  `pasillos.lua:219-312`) y recorte por línea recta (`Ordenes:recta`). Sin
  índice de alcanzabilidad: destino inalcanzable → A* explora **toda** la
  rejilla y devuelve `sinRuta` (marcador rojo). La orden completa de mover a 3
  tanques (ruta del grupo + huecos + rutas individuales) tardó **3,9 ms**
  (medido).
- **Formación** (`Ordenes:formacion`, `:251-323`): solo **al llegar**: huecos
  por tipo (tanques delante, escuadras, lanzacohetes), espiral hasta un sitio
  holgado, cada unidad al hueco libre más cercano. En marcha no hay guía: cada
  unidad sigue los puntos intermedios de la ruta del grupo por su cuenta
  (`Control:moverA`, `control.lua:293-343`).
- **Seguimiento** (`Tropas:seguirOrden`, `tropas.lua:1859-1965`): puntos a
  350 px intermedios y 90/260/40 px finales; «ya pasó cerca y se aleja» cuenta
  como llegada; `desatascar` (`:1970-2000`) escalona por **segundos sin
  moverse 60 px**: 2 s pedir paso (`pedirPaso`, el compañero parado se aparta
  200 px), 4 s rehacer ruta A*, 6,5 s recular 1,8 s, 9 s rodear por un punto
  lateral a 260-480 px, 16 s rendirse (siguiente punto o llegada si < 500 px).
- **Rumbo libre** (`rumboLibre`, `:2228-2250`): cada 0,4-0,6 s prueba desvíos
  de 0 a ±2,1 rad a 125 px (65 el soldado) contra `libre` y `vehiculoCerca`
  (105 px; el soldado 90 a vehículos y 35 a soldados). `vehiculoCerca` recorre
  **todas** las unidades: O(n²) por bando y medio segundo.
- **Movimiento** (`moverPaso`, `:2299-2418`): `velocidadOrden` 60 px/s con
  orden (32 px/s la IA), sin aceleración; tanques giran sobre sí (0,5 rad/s);
  el camión con Ackermann y marcha atrás (`maniobra`) si el punto cae en su
  círculo de giro; vehículos por Box2D (`fisica.lua`), soldados cinemáticos
  con `mantenerTransitable`.
- **Órdenes** (`control.lua`): `mover`, `atacar`, `mantener`; **sin cola**
  (cada orden sustituye); clic derecho suelo → mover, enemigo → atacar, H →
  mantener (`Control:ordenar`, `:271-291`). Al llegar: `mantener` (no se
  mueve, dispara a lo que tenga a tiro; no persigue).
- **Pasos fijos** de 1/60 s, hasta 4 por cuadro (`Tropas.pasoFijo`,
  `maxPasos`); azar por semilla.
- **Unidades**: hasta 40 vehículos (`Tropas.maxPorBando`) y 48 figuras de
  infantería (`produccion.figuras`) por bando: **176** en el campo como mucho.
- Arneses: `pruebas_control` (órdenes, 25 comprobaciones) y `pruebas_rutas`
  (pasillos, cruce de calzada con física real).

**Falta** respecto a §4: cuadrícula por clase y fina; alcanzabilidad y destino
corregido; puntos de ruta espaciados; buscador corto por vértices (hoy
`rodear` prueba 24 puntos fijos); contadores por turno en vez de temporizadores
por orden; empujones con presión (hoy `pedirPaso` + Box2D); cola de órdenes,
retroceder, posturas, atacar avanzando; formación en marcha con guía,
giro con reasignación, esparcidos; presupuesto de rutas por paso; vecinos por
casillas (hoy O(n²)); cursores por acción.

## 10. Criterios de aceptación (comprobables sin ventana)

Arnés nuevo `batalla/pruebas_movimiento/` (Elena/Valeria), semillas 42, 7 y
123, salida por texto, sin ventana. Cada criterio con su cifra:

1. **Cuadrícula**: con celda 40 px, construir las 3 clases en **< 400 ms**
   (hoy 50,8 ms para 1 clase a 120 px; 9× celdas y 3 clases ≈ 1,4 s si se
   hiciera igual: hay que recorrer el suelo una vez y derivar las 3 clases, no
   llamar a `Tropas:libre` por celda y clase). Memoria < 1 MB.
2. **Alcanzabilidad**: 1 000 pares origen-destino al azar por semilla:
   `alcanzable` responde en **< 0,05 ms** cada uno y coincide con el A*
   completo en el 100 %.
3. **Ruta larga**: 200 rutas de 500 a 2 000 m entre puntos alcanzables, media
   **< 2 ms** y 1 % peor **< 10 ms** en Lua (umbral de C: §12); 100 % de las
   rutas pisan solo celdas pasables de su clase (comprobación cada 40 px con
   el casco, como en `pruebas_rutas`).
4. **Destino inalcanzable**: 100 destinos en agua/isla: 0 marcadores
   «sinRuta»; la unidad termina a **< 1 celda** de la celda alcanzable más
   cercana en el 100 %.
5. **Llegada**: 40 vehículos + 96 escuadras (los dos bandos) con orden de
   mover a 1 km por terreno con bosque: el **100 %** llega (llegada o
   relajada) en **≤ 1,5× el tiempo ideal** (distancia / velocidad) y ninguna
   pasa más de **8 s** sin desplazarse 60 px teniendo camino libre a 200 px.
6. **Cruce**: dos grupos de 20 tanques de frente por un pasillo de 100 m: 0
   solapes (distancia entre centros ≥ 0,8·(ra + rb)) al final; ≤ 2 unidades
   rinden la orden (fallo a los 35 turnos).
7. **Formación**: cuadrado de 12 tanques, orden con giro de 30°: 0 huecos
   reasignados y 0 cruces; con giro de 120°: reasignación y 0 cruces; al
   llegar, el 100 % a < `llegar[tipo]` de su hueco y rumbo final ± 0,1 rad.
8. **Cola**: 5 órdenes encoladas (mover, mover, atacar, retroceder, mantener)
   se ejecutan en orden; con Esc se vacía; al morir el blanco pasa a la
   siguiente en ≤ 1 turno.
9. **Rendimiento**: con 176 unidades en marcha, el paso fijo (movimiento +
   empujones) cuesta **< 2 ms de media y < 5 ms el 1 % peor**; con 500
   unidades sintéticas (arnés), **< 5 ms / < 12 ms** (si no, C vía FFI).
10. **Determinismo**: dos procesos con la misma semilla y la misma secuencia
    de órdenes (archivo de comandos con paso fijo) dan el mismo SHA256 de
    posiciones y rumbos de todas las unidades cada segundo durante 120 s.
11. **Arnés de control** actual: sigue en 25/25.

## 11. Plan por pasos pequeños (para Valeria)

Cada paso se mide, se enseña al dueño y se espera su visto bueno antes del
siguiente. Módulos nuevos propuestos en `batalla/navegacion/`:
`cuadricula.lua`, `jerarquico.lua`, `largo.lua`, `corto.lua`, `seguidor.lua`,
`empujones.lua`, `cola.lua`, `formacion.lua`.

1. **Cuadrícula por clase** (`cuadricula.lua`): FFI `uint8_t[n*n]`, 3 bits,
   ensanche por holgura, una sola pasada por el suelo. Sustituye `g.prohibida`
   de `Ordenes:rejilla` (que pasa a leerla). Captura de depuración: una
   imagen PNG de 601×601 por clase (`--captura cuadricula`) para mirarla con
   Read. Medir: ms de construcción y celdas libres por clase.
2. **A* nuevo + adelgazado + espaciado** (`largo.lua`): arrays FFI, época,
   destino punto/círculo, mejor celda vista. `Ordenes:ruta` lo usa. Medir: ms
   medio y 1 % peor en 200 rutas; comparar con `Pasillos.aEstrella`.
3. **Jerárquico** (`jerarquico.lua`): trozos, regiones, aristas, regiones
   globales, `alcanzable` y `hacerAlcanzable`. Quitar `sinRuta`. Medir: ms de
   construcción y de 1 000 consultas.
4. **Seguidor con contadores** (`seguidor.lua`): turno de 12 pasos, fallos,
   saltar punto, recular, alternar, llegada relajada, aceleración y giro con
   cos. Sustituye `seguirOrden`/`desatascar`/`rodear` para `mover` y `atacar`
   (la IA «de siempre» no se toca). Medir: criterio 5 con lo de hoy
   (`vehiculoCerca`) como evitación provisional.
5. **Buscador corto** (`corto.lua`): vértices, cuadrantes, dominio creciente,
   A* ponderado; obstáculos de cuadrícula, árboles, rocas, edificios y
   unidades paradas. Medir: ms por petición según número de aristas; criterio 6.
6. **Empujones y vecinos por casillas** (`empujones.lua`): casillas de 200 px,
   pares, presión, frenado; vehículos por velocidad deseada antes de Box2D,
   soldados por posición. Quitar el O(n²) de `vehiculoCerca`. Medir: criterio 9.
7. **Cola de órdenes y órdenes contextuales** (`cola.lua`, `control.lua`):
   lista por unidad, Mayús/Alt, tabla de acciones por especificidad, R
   retroceder, posturas, cursores (Camila). Medir: criterio 8 y arnés de control.
8. **Formaciones** (`formacion.lua`): guía virtual, huecos cuadrado y
   esparcidos (desorden por `Ruido.hash`), asignación, giro con reasignación,
   corredor, sueltos 3 s. Botones de formación en el HUD (interfaz militar).
   Medir: criterio 7.
9. **C vía FFI** (solo si los umbrales de §12 se superan): un módulo
   `batalla/navegacion/c/navegacion.c` compilado a `.so` y cargado con
   `ffi.load`, con tres funciones: `rutaLarga(cuadricula, n, clase, origen,
   destino, salida)`, `empujar(unidades, n, casillas, salida)` y, si hace
   falta, `jps` con caché de saltos. Los datos ya viven en arrays FFI: C los
   lee sin copiar. Determinismo: enteros y el mismo orden por id.

## 12. Cuándo ir a C (FFI) y con cuántas unidades

No está medido en Lua aún: las cifras son el umbral de decisión que se
comprobará en los pasos 2, 5 y 6. Base real: hoy el A* en Lua sobre 40 401
celdas (120 px) resuelve una orden de 3 unidades en 3,9 ms; con 361 201
celdas y A* sin índice, el peor caso (explorar todo) sería unas 9× más
(estimación, no medida): 30-40 ms por ruta. El jerárquico evita ese peor
caso; el presupuesto de 8 rutas por paso acota el pico.

| Parte | Se queda en Lua si… | Va a C si… |
|---|---|---|
| A* largo | media < 2 ms y 1 % peor < 10 ms (criterio 3) | con **≥ 200 unidades** mandadas a la vez la latencia de cola supera 0,5 s (= 200/8 pasos) o una ruta media pasa de 2 ms |
| Buscador corto | < 1 ms por petición con ≤ 100 aristas | en bosques densos (> 300 aristas en 2 240 px) pasa de 5 ms |
| Empujones | 176 unidades en < 1 ms por turno (son pares por casilla: con 10 por casilla, ~50 pares por unidad) | **≥ 400 unidades** o > 3 ms por turno |
| Cuadrícula | construcción < 400 ms | > 1 s (por ejemplo, celda de 30 px o campo mayor) |

Con cientos de unidades (el objetivo del dueño), lo esperable es que A* y
empujones acaben en C en el paso 9 y que el resto (seguidor, cola,
formaciones, cursor) siga en Lua: es lógica de juego, no cálculo pesado.

## 13. Decisiones del dueño (2026-10-01)

Tomadas sobre las opciones de §14 (que se conserva como registro de lo que
se le presentó). Mandan sobre cualquier otra cifra de este documento:

1. **Celda**: la que salga de la medición en el paso 1 del plan. Se empieza
   por **40 px**; si cuesta demasiado (criterio 1: > 400 ms o > 1 MB), **60 px**.
2. **Colisión de vehículos**: **empujones + Box2D** (§4.6.7: el empujón es
   velocidad deseada antes de `Fisica:impulsar`/`conducir`; Box2D resuelve el
   contacto real).
3. **Órdenes extra**: **sí «atacar avanzando»** (Ctrl + clic en el suelo,
   especificidad 5); **no «cubrir»** por ahora: la infantería ya se agacha
   sola bajo fuego. Se quita de la tabla de §4.7.3.
4. **Posturas**: **agresiva o defensiva, elegible por unidad; por defecto
   defensiva**. Cambia la recomendación de §4.7.4: una unidad recién llegada
   no persigue salvo que el jugador la ponga en agresiva. Efecto: menos
   unidades que se desperdigan solas; el jugador tiene que dar la orden de
   atacar o cambiar la postura para que avancen.
5. **Alt + clic derecho «al frente de la cola»**: **sí**. Coincide con la
   opción recomendada (§14.5a).
6. **Columna automática en pasillos estrechos**: **sí** (§14.6a): modo de
   marcha interno a 2-3 columnas donde el cuadrado no cabe; no es una
   formación elegible.
7. **Rumbo al llegar**: **clic mira al enemigo; arrastrar fija el rumbo**,
   igual que en la preparación (§4.8.5).
8. **Encolar órdenes durante la preparación**: **sí**; se ejecutan al empezar
   el combate (§6, fila «Orden de mover en preparación»).
9. **Sin munición**: **mover y retroceder se cumplen igual**; atacar se
   descarta (§4.7, §6).
10. **C vía FFI**: **solo al superar los umbrales medidos** de §12.

## 14. Opciones que se presentaron al dueño (registro)

1. **Tamaño de celda.** (a, recomendada) **40 px / 4 m**: la infantería pasa
   entre árboles a 8 m, los vehículos tienen rutas fieles; 361 k celdas, hay
   que medir el coste. (b) 60 px / 6 m: 161 k celdas (2,2× menos coste),
   bosques algo más cerrados a pie. (c) 120 px como hoy: barato, pero la
   infantería navega como un tanque.
2. **Colisión de vehículos: ¿empujones o Box2D?** (a, recomendada) Empujones
   de 0 A.D. como velocidad deseada **y** Box2D para el contacto real con
   árboles, agua y otros vehículos: un solo comportamiento para todos y la
   física sigue dando el tacto de hoy. (b) Solo empujones y Box2D únicamente
   contra el terreno: más determinista entre máquinas, hay que rehacer el
   choque entre vehículos. (c) Solo Box2D: lo de hoy; no fluye en grupos.
3. **Órdenes extra.** ¿Entran `cubrir` (clic sobre un propio averiado) y
   `atacar avanzando` (Ctrl + clic en el suelo)? (a, recomendada) Sí las dos:
   son las que dan sentido a la batalla sin recolección y son baratas sobre la
   cola. (b) Solo las cuatro pedidas: mover, atacar, mantener, retroceder.
4. **Posturas al terminar una orden.** (a, recomendada) Dos: agresiva (por
   defecto; persigue hasta 1 alcance y vuelve) y defensiva (H: no se mueve).
   (b) Tres, con pasiva (no dispara sin orden: para emboscadas). (c) Ninguna:
   al llegar, mantener como hoy (no persigue nunca).
5. **Tecla para «al frente de la cola».** (a, recomendada) Alt + clic derecho,
   como 0 A.D. (Mayús encola al final). (b) Sin «al frente»: solo Mayús.
6. **Columna en pasillos estrechos.** El cuadrado de 8 tanques mide 69 m y el
   de 40, 161 m; nuestros pasillos, 100 m. (a, recomendada) Modo de **marcha
   automático**: si la guía va a cruzar celdas donde el cuadrado no cabe, los
   huecos pasan a 2-3 columnas y se reabren al llegar (no es una tercera
   formación: el jugador sigue viendo «cuadrado»). (b) Dejar que los
   exteriores se apañen (sueltos 3 s y reagrupar): más feo, más simple.
   (c) Añadir «columna» como formación elegible.
7. **Rumbo al llegar.** (a, recomendada) Como en la preparación: clic deja al
   grupo mirando al enemigo; arrastrar fija el rumbo. (b) Mirar el rumbo
   final de la ruta, como 0 A.D.
8. **Órdenes durante la preparación.** (a) Se pueden encolar (Mayús) y se
   ejecutan al empezar la batalla: permite planear el primer avance.
   (b) No: en la preparación solo colocación instantánea.
9. **Sin munición.** (a, recomendada) Cumple mover y retroceder, descarta
   atacar. (b) Como hoy: no se mueve ni dispara.
10. **Ir a C.** (a, recomendada) Solo cuando se superen los umbrales de §12,
    medidos en Lua primero. (b) Escribir A* y empujones directamente en C en
    los pasos 2 y 6.

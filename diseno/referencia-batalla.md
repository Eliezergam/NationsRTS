# Referencia de la batalla 3D para rehacerla en UE5

Cómo funciona hoy la batalla 3D de LÖVE, con sus reglas, cifras y orden de
actualización, para rehacerla igual en C++ con MassEntity. Escrito por
Andrés el 2026-10-03.

- **Referencia de comportamiento:** la etiqueta git `love-final-2026-10-03`.
  Las rutas son relativas a `NationsRTS/` y las líneas, de esa etiqueta.
- **Partes del documento:**
  - de la 1 a la 15, cómo funciona hoy (hechos leídos en el código o medidos);
  - la 16 es una **[Propuesta]** de arquitectura;
  - la 17, las pruebas de aceptación;
  - la 18, las dudas para el dueño.
- **Más detalle del daño:** `batalla/DANO-REAL.md`. Este documento resume lo
  que hay que portar y corrige lo que el código hace distinto de lo escrito.

---

## 1. Unidades, ejes y escala

- **Distancias:** 1 px = 10 cm. En UE se trabaja en cm, así que UE = px × 10.
- **Ejes:** el plano del suelo es (x, y) y z va hacia arriba, igual que en UE.
- **Ángulos:**
  - en radianes;
  - `rumbo` = `atan2(dy, dx)`, es decir, 0 mira a +x;
  - `torreta` es relativa al casco.
- **Gravedad:** 98 px/s² (`dano/datos.lua:20`).
- **Área:**
  - 3 × 3 km (`Suelo.lado = 30000`, `suelo.lua:37`);
  - límite circular de 1,2 km de radio (`limite.lua:16`).
- **Física de Box2D:** 1 unidad = 100 px = 10 m (`dream/conversor.lua:11`).

## 2. Ciclo de la escena y orden de actualización

### 2.1 Escena (`batalla/escena.lua`)

`Escena.nueva` (`escena.lua:169`) hace esto, en orden:

1. `Suelo.nuevo`: relieve, agua, pasillos de avance (que **aplanan el
   terreno**), plantas y la rejilla de tránsito.
2. `Tropas.nuevo`: forma los dos bandos.
3. Crea la cámara y el `Control`.
4. Construye la rejilla de rutas (`ordenes:rejilla()`). Con la semilla 42
   tardó 323 ms y dejó 12 862 celdas libres.
5. Si el combate trae `preparacion`, abre el despliegue (§13).

**La física de los vehículos la crea la vista 3Dream**
(`dream/escena.lua:562`, `Fisica.nueva`), no la simulación. Sin la vista
(algunos arneses), los vehículos se mueven por la vía cinemática de
`moverPaso` y la pelea **da otro resultado**. Ver §15.

Cada cuadro, `Escena:actualizar(dt)` (`escena.lua:526`) hace lo siguiente:

- en la preparación, solo corre el contador (§13);
- si no hay pausa (tecla P), llama a `tropas:actualizar(min(dt, 0.05))` y
  después a `vigilarFin()`.

### 2.2 Pasos fijos (`tropas.lua:2991`)

- **Acumulador:** `acumulado += dt`. Mientras `acumulado ≥ 1/60` y van menos
  de `maxPasos = 4` pasos, ejecuta `paso(1/60)`.
- **Si se llega a 4 pasos,** el acumulado se recorta a 1/60. Por debajo de
  unos 15 FPS, la pelea va más lenta que el tiempo real, pero da lo mismo.
- **`relojVista` = `reloj + acumulado`.** Solo lo usa el dibujo.

### 2.3 Un paso (`Tropas:paso`, `tropas.lua:3006`), en este orden

1. `reloj += dt` y `pasos += 1`.
2. `relevar()`: oleadas (§4.3).
3. `medirAvance()`: avance medio por bando. Es la media de `u.avanzado` de
   los tanques vivos o, si no quedan, de las escuadras (`:2961`).
4. `fisica:iniciarCuadro()`: `movimientoFisico = false` en todas.
5. **Cada unidad de `self.unidades`, en orden de entrada.** Primero todo el
   bando 1 de la formación inicial, luego el bando 2 y después las que
   entran de la reserva, al final.
   - Camión: `recordarPosicion`. Si está averiado, baja la rampa.
   - Muerta: el humo cada 0,3 s.
   - Viva, según su tipo:
     - `actualizarTanque` (§8);
     - `actualizarSoldado` (§7);
     - `actualizarLanzacohetes` (§9).
6. `fisica:actualizar(dt)` (§6.5). Después, la postura de cada unidad sobre
   el terreno (`Modelos3d.postura`).
7. Ruedas y orugas: `medirMovimiento` mide lo que se movió de verdad y da
   `u.velocidadRuedas` en px/s, **que la simulación lee** (§9).
8. Velocidad de cada unidad: `u.vx` y `u.vy` = desplazamiento / dt. Es la
   anticipación del control de tiro.
9. `cuerpos:rehacer()`: rejilla espacial de cajas (§11.1).
10. `proyectiles:avanzar()`:
    - primero las balas, **de la última lanzada a la primera**;
    - luego los misiles que se dibujan y los ocultos, también hacia atrás.
11. Estelas y partículas, que también consumen el azar (§15).

Un disparo lanzado en el punto 5 empieza a volar en el paso siguiente: en su
primer `avanzar`, `t1 = 0`.

## 3. Estado

### 3.1 La batalla (`Tropas.nuevo`, `tropas.lua:286`)

| Campo | Qué es |
|---|---|
| `azar` | `love.math.newRandomGenerator(floor(abs(cx·7 + cy·13)) % 2147483647 + 1)`. La semilla sale **del centro del combate**, no de un número aparte |
| `reloj`, `pasos`, `acumulado` | Reloj de la pelea en s, pasos dados y tiempo pendiente |
| `unidades` | Las unidades en el campo, en orden de entrada. Las retiradas salen de la lista |
| `balas`, `misiles`, `proyectiles.ocultos` | Proyectiles en vuelo (§10) |
| `bandos[1..2]` | `fuentes`, `cola` (la reserva), `figuras`, `escuadra`, `soldados`, `todas` (todas las que han entrado), `enCampo`, `entradas`, `geometria`, `fondo`, `esperaEntrada` |
| `bajas[2]`, `avance[2]` | Bajas y avance medio por bando |
| `ultimoFuego[2]`, `ultimoAvance[2]` | Reloj del último disparo y del último paso de una unidad armada (§14) |
| `cuerpos`, `proyectiles`, `estadisticas` | Daño real |
| `rutas` | El `Ordenes` del control, para rehacer rutas |

### 3.2 Cada unidad (`Tropas:poner`, `tropas.lua:806`, y `armar`, `:765`)

| Campo | Tipo | Qué es |
|---|---|---|
| `bando` | 1 o 2 | 1 es el atacante y 2 el defensor |
| `tipo` | `'tanque'`, `'lanzacohetes'`, `'soldado'` | |
| `numero` | entero | Orden de entrada en su bando: el id estable |
| `fuente` | tabla | Grupo o guarnición de donde sale. De ahí se toma la munición |
| `modelo` | clave | `t55`, `t72b`, `m1a1`, `k2`, `scudb`, `bm21`, `himars` |
| `soldados`, `muertos`, `heridos` | entero | Solo las escuadras |
| `x`, `y`, `z`, `rumbo` | px y rad | `rumbo` empieza en el rumbo del bando ± 0,06 rad al azar |
| `rumboBando` | rad | Hacia el enemigo. `avanzado` se mide en esa dirección |
| `torreta`, `retroceso` | | Tanque |
| `elevacion`, `gatos`, `fase`, `cargados`, `salva`, `salvaSiguiente`, `direccionRuedas`, `velocidadRuedas` | | Camión |
| `espera` | s | Hasta poder disparar. Empieza en 1 + U(0, 5) |
| `buscar` | s | Hasta volver a buscar blanco. Empieza en U(0, 1,5) |
| `alto`, `quieto`, `avanzado` | | Tiempo parado a disparar, tiempo sin moverse y avance hacia el enemigo |
| `vida`, `vidaMax` | | En las escuadras, los soldados en pie. En los vehículos, `vidaMax·(1 − daño)` (§11) |
| `averias` | tabla | `orugas`, `torreta`, `canon`, `motor`, `tripulacion`, `tripulacionMuertos`, `estructura` |
| `tripulacion` | entero | Del catálogo |
| `alcance`, `minimo`, `proyectiles`, `carga`, `radio`, `cep`, `porDisparo`, `ojiva`, `canonDatos` | | Las cifras de su modelo (§12) |
| `blanco` | unidad | El blanco actual |
| `orden` | tabla o nil | Ver §5 |
| `apartarse`, `recular`, `maniobra`, `ruta`, `rumboDeseado`, `rumboOrden`, `puntoOrden` | | Movimiento |
| `fuego`, `agachado`, `agachadoMarcha`, `enemigoCerca`, `tanqueCerca` | | Bajo fuego (§7) |
| `muerto`, `averiado`, `caida`, `retirado`, `reserva`, `expuesto` | | Estado |
| `vx`, `vy` | px/s | Medidas en cada paso |

## 4. Bandos, escuadras, formación inicial y oleadas

### 4.1 Lo que pelea (`prepararBando`, `tropas.lua:403`)

- **Fuentes.** Cada fuente es un grupo o la guarnición. Lleva sus vehículos
  por modelo y su munición, o munición sin límite si es un combate de
  prueba (`fuentesDe`, `:328`).
- **Cola de vehículos.**
  - Los modelos de cada fuente se intercalan (`modelosFuente`, `:368`).
  - Después se intercalan tanques y lanzacohetes en su proporción: entra el
    tipo que va más atrasado respecto a su parte.
- **Escuadras.**
  - Tamaño: `escuadra = bando.escuadra` o `ceil(soldados / 48)`, donde 48 es
    `produccion.figuras`.
  - Cada figura lleva `escuadra` soldados y la última, el resto.
  - La fuente de una figura es la de su primer soldado.

### 4.2 Formación inicial (`formar`, `:698`; `poner`, `:806`)

**Geometría:**

- frente del bando = centro ± `angulo` × `separacion`;
- `separacion` vale 8500 px (850 m) o, con preparación, 5500 px;
- el bando 1 está en −, el 2 en +, y cada uno mira al otro.

**Qué forma:**

- los primeros `maxPorBando = 40` vehículos de la cola; el resto va a la
  reserva;
- todas las escuadras.

**Dónde va cada unidad:**

| Qué | Fondo detrás del frente | Separación entre columnas | Filas |
|---|---|---|---|
| Tanques | 0 | 200 px | 10 por fila, 260 px entre filas |
| Escuadras | 420 px | 75 px | Las mismas 10 por fila y 260 px |
| Lanzacohetes | `(filasTanques − 1)·260 + 2200` px | 320 px | |
| Lanzacohetes adelantados (`bando.adelantados`, solo pruebas) | `−(2·separacion − 4200)` | 600 px | |

**Cómo se busca sitio (`buscarSitio`, `:613`):**

- una espiral de 400 intentos (ángulo k·2,39996 y radio √k·80 px) desde el
  sitio ideal;
- el punto debe:
  - estar libre (`libre`, `:529`);
  - no tener un vehículo a menos de 110 px, o de 42 px si es una escuadra;
  - unirse en recta libre a un pasillo de avance a menos de 2600 px;
- si no lo encuentra, lo busca a lo largo del pasillo desde el extremo de su
  bando, en laterales de 0 y ±90 y ±180 px;
- si tampoco, el vehículo vuelve a la cola y la escuadra no pelea (sus
  soldados se cuentan en pie).

### 4.3 Oleadas (`relevar`, `:902`; `entrarReserva`, `:927`)

- **Con reserva y menos de 40 vehículos en el campo:** entra el siguiente de
  la cola.
- **Si ya hay 40:**
  - se retira el averiado más antiguo del bando que lleve al menos
    `retiroAveriado = 12` s caído (`retirar`, `:877`: sale de `unidades` y de
    la física);
  - y entra el siguiente.
- **Dónde entra:** en el hueco `entradas % 10` de una fila a
  `fondo + 900` px, con 320 px entre columnas.
- **Sin sitio:** vuelve a probar a los 2 s.

## 5. Órdenes y control

### 5.1 Entrada (`control.lua`, `escena.lua:974–1122`)

**Selección:**

- clic izquierdo: elige una;
- Mayús + clic: la suma o la quita;
- arrastre con el izquierdo: cuadro, en pantalla;
- doble clic (0,35 s): todas las de ese tipo a la vista;
- T, L e I: todos los tanques, lanzacohetes o escuadras (con Mayús, se suman).

**El clic de pantalla:**

- toca la unidad del rayo del selector 3D;
- si no, la más cercana a menos de 28 px en pantalla (`unidadEn`,
  `control.lua:95`).

**Órdenes:**

- clic derecho corto (menos de 6 px de arrastre) sobre un enemigo: `atacar`;
- clic derecho corto sobre el terreno: `mover` (`ordenar`, `:278`);
- H: `mantener`;
- en la preparación no hay órdenes.

**Hacia la simulación,** todo entra por `Tropas:darOrden(u, orden)`
(`tropas.lua:2059`). Borra `rumboOrden`, `puntoOrden`, `recular`,
`maniobra`, `ruta` y `blanco`, y pone `orden.paso = 1`,
`orden.desde = reloj` y `orden.avanza = false`.

**Las órdenes no se sellan con el número de paso.** Se aplican entre cuadros
(DANO-REAL §8.1).

### 5.2 Mover en formación (`Control:moverA`, `control.lua:300`)

1. **Centro del grupo:** la media de sus posiciones.
2. **Ruta del grupo** desde el centro: `Ordenes:ruta` (§5.4).
3. **Rumbo de la formación:** del penúltimo al último punto de la ruta.
4. **Huecos** (`Ordenes:formacion`, `ordenes.lua:378`):
   - filas perpendiculares a la marcha, de delante atrás: tanques,
     soldados y lanzacohetes;
   - cifras por tipo:

     | Tipo | Separación | Por fila | Entre filas | Holgura | Apartado |
     |---|---|---|---|---|---|
     | Tanque | 230 px | 8 | 260 px | 120 px | 170 px |
     | Soldado | 80 px | 12 | 90 px | 0 | 50 px |
     | Lanzacohetes | 320 px | 6 | 340 px | 200 px | 240 px |

   - después de cada tipo, 120 px más de fondo;
   - cada hueco va al sitio «holgado» más cercano al ideal: espiral de 260
     intentos, √k·60 px;
   - «holgado» quiere decir:
     - el punto está libre;
     - su celda de la rejilla de rutas no está cerrada (salvo soldados);
     - los 8 puntos del anillo de holgura están libres;
     - no hay otro hueco ni un vehículo propio parado de fuera del grupo a
       menos de la distancia de «apartado».
5. **Reparto:** se ordenan las unidades de la más lejana al destino a la más
   cercana, y cada una toma el hueco libre más cercano a ella.
6. **Ruta de cada unidad:**
   - los puntos de la ruta del grupo desde el más cercano a ella;
   - si no ve en recta el primero, antes su propia ruta A* hasta él;
   - al final, su hueco;
   - todo suavizado con `Ordenes:suavizar`.
7. **Orden que recibe:** `{tipo='mover', ruta, destino=hueco, grupo=rutaGrupo,
   suave=true}`.

### 5.3 Atacar y mantener

- **`{tipo='atacar', blanco}`:** se acerca hasta tenerlo a tiro y solo le
  dispara a él. Si el blanco cae o se retira, pasa a `mantener`.
- **`{tipo='mantener'}`:** no se mueve y dispara a lo que tenga a su
  alcance. Además exime a su bando de retirarse por no alcanzar al rival
  (§14).

### 5.4 Rutas (`ordenes.lua`)

**Rejilla** (`Ordenes:rejilla`, `:61`):

- celdas de 120 px dentro del límite, menos 150 px de margen;
- una celda está abierta si:
  - `Tropas:libre(x, y, true, 'tanque')` acepta su centro;
  - y no la cierran los árboles: con un árbol a menos de 70 px del centro,
    o en 5 de sus 3 × 3 puntos (separados 40 px), se cierra.
- se calcula una vez al abrir la escena.

**Ruta** (`Ordenes:ruta`, `:193`):

- el destino va a la celda libre más cercana, buscada en anillos de hasta
  40 celdas;
- si el segmento recto pisa solo celdas abiertas (muestreado cada 60 px),
  la ruta es la recta;
- si no, A* (`Pasillos.aEstrella`, `pasillos.lua:219`) con:
  - 8 vecinos y sin cortar esquinas;
  - coste d·(1 + (pendiente/12)²);
  - montículo binario;
  - y luego un recorte: desde cada punto, al más lejano que se vea en recta.

**Suavizado** (`:270`):

- primero se tensa;
- luego una Catmull-Rom centrípeta muestreada cada 40 px;
- un tramo cuya curva pise una celda cerrada se queda recto.

### 5.5 Seguir una orden (`Tropas:seguirOrden`, `tropas.lua:2086`)

**`mover`:**

- **Inmóvil** (oruga o motor roto): la orden pasa a `mantener`.
- **Avance de punto:** pasa al siguiente punto al acercarse a menos de este
  radio:

  | Punto | Tanque | Lanzacohetes | Soldado |
  |---|---|---|---|
  | El último (`llegar`) | 90 px | 260 px | 40 px |
  | Uno intermedio de una ruta suave | 110 px | 350 px | 60 px |
  | Uno intermedio sin suavizar | 350 px | 350 px | 350 px |

- **Último punto:** si ya pasó a menos de 300 px y se aleja más de 120 px de
  ese mínimo, ha llegado y pasa a `mantener` con `llego`.
- **Atasco:** `desatascar` (`:2198`) cuenta el tiempo sin desplazarse 60 px y
  prueba, por turnos:

  | A los | Qué hace |
  |---|---|
  | 2 s | Pide paso (`pedirPaso`, `:2230`): el compañero parado delante (−40 a 320 px por delante y menos de 170 px de lado) se aparta 200 px hacia un lado durante 6 s como mucho |
  | 4 s | Rehace la ruta con A* desde donde está |
  | 6,5 s | Recula 1,8 s si está libre detrás (120 px): marcha atrás a 0,6 de su rapidez |
  | 9 s | Rodea (`rodear`, `:2316`): mete un punto lateral libre a 260, 380 o 480 px (giros de ±0,8, ±1,4, ±2,0 y ±2,6 rad), el que quede más cerca del destino |

  Además:

  - parado más de 2 s a menos de 220 px del último punto: ha llegado;
  - más de 16 s sin moverse: salta al siguiente punto; si era el último,
    `mantener`, con `llego` si estaba a menos de 500 px.

**`atacar`:**

- la línea de vista se mira cada 0,5 s (el camión la da siempre por buena);
- **a tiro** = d ≤ 0,85·alcance, d ≥ mínimo y blanco visible;
- si no está a tiro y no está inmóvil:
  - avanza por una ruta A* hacia el blanco, rehecha cada 10 s;
  - cuando le queda el último tramo, va directo al blanco;
  - también se desatasca.

## 6. Movimiento

### 6.1 Terreno transitable

**`Tropas:transitable(x, y, tipo)`** (`tropas.lua:507`):

- `suelo:transitable` en el centro y en 4 puntos a la distancia del radio:
  pendiente ≤ 25° y sin agua (rejilla de tránsito de 20 px, `suelo.lua:353`);
- `agua:enAgua(x, y, radio)`;
- radios: soldado 22 px, tanque 62 px, lanzacohetes 86 px.

**`Tropas:libre(x, y, arboles, tipo)`** (`:529`) pide además:

- que esté a 400 px o más del borde del área;
- `limite:dentro(x, y, 60)`;
- que no esté en el edificio + 90 px;
- que no haya agua a 80 px;
- que no haya planta cerca:
  - con `arboles`, un árbol a menos de 45 px (para moverse);
  - sin él, cualquier planta a menos de 55 px (para formar);
- altura ≥ 3 px en 5 puntos;
- `desnivel(55)` ≤ 42 px (`Suelo.maxDesnivelVehiculo`).

**`segmentoLibre`** (`:572`): muestrea el segmento cada 40 px con `libre`, el
límite y las plantas a la distancia del radio.

### 6.2 Rumbo (`rumboLibre`, `:2479`)

**Rumbo base,** el primero que exista de estos:

1. el punto de `apartarse`;
2. el de la orden (si avanza);
3. el del pasillo (`rumboDePasillo`, `:2443`);
4. el del bando.

**Rumbo del pasillo:**

- el punto más cercano de los pasillos principales, buscado cada 3 muestras
  hasta 2600 px;
- se mira 820 px más adelante en el sentido de su bando (80 px si está a más
  de 420 px del eje);
- se conserva el lateral de la unidad, recortado a ±180 px;
- se acorta la mirada hasta que el segmento quepa libre.

**Desvíos:**

- se prueban sobre el rumbo base:
  - sin orden: 0, ±0,35, ±0,7, ±1,05 y ±1,4 rad;
  - con orden: además ±1,75 y ±2,1;
- distancia de prueba: 65 px el soldado, 125 px los vehículos;
- el punto debe estar `libre` y sin unidades cerca:
  - un soldado esquiva vehículos a 90 px y soldados a 35 px;
  - un vehículo esquiva a 105 px;
  - con orden, no estorban las del propio bando que también marchan;
- el rumbo se recalcula cada U(0,4, 0,6) s (`u.ruta`).

### 6.3 Paso de movimiento (`moverPaso`, `:2550`)

- **Inmóvil:** no se mueve. Un camión con la rampa alzada tampoco.
- **Rapidez:**
  - vehículos: `velocidad = 32` px/s, o `velocidadOrden = 60` px/s con
    orden o apartándose;
  - todo × `velocidadModelo` (§12);
  - soldados: 25 px/s, o 4 px/s agachado (con orden o sin ella).
- **Comprobación:** el punto a 110 px en el rumbo deseado (con orden, el
  mismo de `rumboLibre`) debe estar `libre`; si no, se para y recalcula.
- **Soldado (cinemático):**
  - gira a 1,8 rad/s;
  - avanza velocidad·dt·max(0, cos(diferencia));
  - si cae en terreno no transitable o fuera del límite, vuelve al punto
    anterior (`mantenerTransitable`, `:2504`).
- **Tanque:**
  - con física, `fisica:impulsar` (§6.5);
  - sin física, cinemático: gira a 0,5 rad/s y avanza con factor
    max(0,35, cos).
- **Camión** (dirección de bicicleta):
  - `lanzador:dirigir`: las ruedas van a ±0,45 rad como mucho
    (0,85·diferencia), a 1,6 rad/s;
  - con física, `fisica:conducir`;
  - sin ella, `giro = v·dt/entreEjes·tan(dirección)`;
  - **maniobra:** si el punto queda de lado (más de 1,1 rad) y dentro de 2,2
    radios de giro, da marcha atrás con las ruedas al revés hasta 5 s o
    hasta quedar a menos de 0,45 rad.
- **`avanzado`** suma el desplazamiento proyectado en `rumboBando`.
- **`mover`** (`:2520`) apunta `ultimoAvance[bando] = reloj` si se movió y
  tiene munición.

### 6.4 Medido en LÖVE

Arnés `batalla/pruebas_control`, semilla 42, vista 3Dream con física,
traza de un segundo a otro. Los modelos salen del desglose de la ciudad. El
tanque que registró el arnés era un T-72B; el de cada traza no se apunta.

- con orden de mover: 3,2–3,6 m/s, cuando la cifra nominal es de 5,1 a
  7,2 según el modelo (6 en el T-72B);
- con su IA: 1,8 m/s, cuando la nominal es de 2,7 a 3,8 (3,2 en el T-72B);
- si son T-72B, los vehículos van a **0,56–0,58 de la velocidad nominal**,
  por el amortiguamiento lineal de Box2D (3,5) contra la ganancia del motor
  (8) y por el factor de giro. Antes de fijar la cifra hay que repetir la
  medida con un solo modelo;
- tres tanques mandados a unos 106 m en línea recta cumplieron la orden en
  38 s (el que no tenía avería quedó a 86 px de su hueco).

Hay que copiar lo **efectivo**, no la cifra nominal (§17, PA-MOV).

### 6.5 Física de los vehículos (`batalla/fisica.lua`)

**Motor:** Box2D 2D (`love.physics`) en el plano (x, y) a través de la
extensión de 3Dream.

**Cuerpo de cada vehículo** (`crearUnidad`, `:279`):

| Dato | Tanque | Camión |
|---|---|---|
| Cilindro (radio) | 3,8 m | 5,8 m |
| Densidad | 3200 | 2400 |

En los dos: rozamiento 0,82, amortiguamiento lineal 3,5, angular 5 y escalón
de 1,6 m.

**La altura no la da Box2D:** `apoyar` (`:488`) pone z = `suelo:altura`. Los
vehículos no chocan con la malla del terreno (máscara 4).

**`impulsar`** (tanque, `:377`):

- par = (diferencia·12 − ω·5)·masa;
- fuerza = (objetivo − v)·masa·8, donde objetivo = rapidez·max(0,25,
  cos(diferencia)) en la dirección del casco.

**`conducir`** (camión, `:406`):

- fuerza hacia delante = (objetivo − v_delante)·masa·8;
- agarre lateral = −v_lado·masa·10;
- par = (v_delante/entreEjes·tan(dirección) − ω)·masa·18.

**`frenar`** (sin movimiento pedido o muerto): fuerza −v·masa·8 y par
−ω·masa·6.

**Seguridad:** si el vehículo acaba en un sitio no transitable (radio de 68
o 96 px), vuelve a su última posición segura con velocidad 0
(`sincronizar`, `:456`).

**Estáticos:**

- árboles: círculos de 1,8 m;
- límite: una cadena de 128 lados;
- orillas: aristas;
- el límite y las orillas, sin rozamiento.

**Derribo** (`derribo.lua`):

- tumba los arbustos y los árboles con tronco ≤ 30 cm y altura ≤ 12,5 m;
- el contacto se desactiva y el vehículo conserva 0,7 de su velocidad;
- los arbustos caen por proximidad: 45 px el tanque, 60 px el camión;
- los cañonazos y los cohetes también tumban el árbol que alcanzan (§10).

### 6.6 IA sin orden (`quiereAvanzar`, `:2005`)

- **Escuadra:** avanza mientras el enemigo más cercano esté a más de
  0,35·600 m = 210 m y no tenga blanco. Con blanco, se para a disparar.
- **Vehículo:** no avanza si va más de 350 px por delante de la media de su
  bando. Además:
  - **atacante:** avanza mientras el tanque enemigo más cercano esté a más
    de 3000 px;
  - **defensor:** sale 1500 px como mucho y solo si no hay tanque enemigo a
    menos de 5000 px.

## 7. Infantería (`actualizarSoldado`, `:2677`; `avanzarSoldado`, `:2685`)

**Bajo fuego** (`bajoFuego`, `:2670`):

- le dispararon, le cayó algo cerca en los últimos 4 s, o tiene un enemigo
  a ≤ 600 m;
- `agachadoMarcha` = bajo fuego y se ha movido en este paso. Su caja baja a
  1,15 m (§11).

**Orden de decisión en cada paso:**

1. Apartarse, si se le pidió.
2. Sin munición, o con orden de mover: no dispara; solo marcha con la orden.
3. Con `atacar`: su blanco es el de la orden si está a tiro.
4. Sin orden, el blanco:
   - lo pierde si muere o pasa de 600 m;
   - lo busca cada U(0,45, 0,9) s (`blancoDeSoldado`, `:1235`): el más
     cercano a ≤ 600 m y visible, con la distancia² × 1 para soldados y × 4
     para vehículos;
   - de paso apunta `enemigoCerca` y `tanqueCerca`.
5. Con blanco:
   - gira hacia él a 2,88 rad/s;
   - dispara si la diferencia es menor de 0,22 rad, `espera ≤ 0`, la línea
     de fuego está libre y `gastar` da munición;
   - si un compañero tapa la línea, espera 0,5 s.
6. Sin blanco: avanza según §6.6.

**Ráfaga** (`dispararSoldado`, `:1626`):

- 5 balas por cada soldado en pie;
- la boca sale de la animación horneada (`Soldados.boca`, `soldados.lua:339`).
  **El reloj de la animación cuenta para la simulación.**
- a qué apunta (`alturaBlanco`):

  | Blanco | Altura |
  |---|---|
  | Soldado | el pecho: 11 px, o 7 px si va agachado |
  | Tanque | 12 px |
  | Camión | 15 px |

- **Error común de la ráfaga:** σ = (bajo fuego ? 7 : 4)/1000 + 0,4·10/max(100, d)
  rad, en horizontal y en vertical.

  **Nota:** el blanco siempre está a ≤ 600 m, así que el tirador siempre
  está «bajo fuego» y en la práctica siempre vale 7 mrad. `apunte.marcha =
  9` no se usa.

- **Cada bala:** su desvío N(0, 2,5 mrad) en los dos ejes; como mucho 40
  rayos, cada uno con peso balas/rayos (§10.3).

**Ritmo:**

- entre ráfagas, U(1,1, 2,0) s;
- cada 6 ráfagas (un cargador), 3,3 s más si le queda munición;
- de media, un ciclo de 2,1 s: unas 143 balas por soldado y minuto.

## 8. Tanques (`actualizarTanque`, `tropas.lua:2753`)

- **Sin munición o con el cañón roto:** no dispara. Solo se mueve con una
  orden.
- **Blanco** (`blancoDeTanque`, `:1193`), cada U(1,5, 2,5) s o al caer el
  anterior:
  1. un lanzacohetes enemigo a menos de 650 m (`minimoMisil + 1500`), si lo
     hay;
  2. si no, el que tenga menor distancia² × prioridad × U(0,6, 1,4), con
     prioridad 3 para los soldados y 1 para los vehículos, dentro de su
     alcance (2,1 km);
  3. el elegido debe ser visible (`Impactos.visible`, desde 2,2 m de altura
     hasta 1,8 m del blanco); si no, no hay blanco.
- **Torreta:** gira a 0,6 rad/s.
  - Sana: está apuntada cuando la diferencia cabe en el giro de un paso.
  - Atascada: apunta girando el casco si puede moverse, y cuenta como
    apuntada si el blanco está a menos de 0,05 rad del frente.
- **Disparo** (sin orden de mover):
  1. apuntado y con `espera ≤ 0`, se para (`alto = 3,5` s);
  2. cuando lleva `quieto ≥ 0,7` s, comprueba la línea de fuego (si la tapa
     un compañero, espera 1 s) y dispara;
  3. recarga U(6, 11) s / max(0,25, tripulación que queda / tripulación).
- **Cañonazo** (`dispararTanque`, `:1701`):
  - contra vehículos, perforante; contra soldados, explosiva, apuntada a
    0,4 m de los pies;
  - el control de tiro mide la distancia con un error × (1 + N(0,
    errorDistancia));
  - desde la era 2 anticipa: suma `blanco.v·vuelo` al punto;
  - desvío con σ = √(error² + dispersión²);
  - la penetración varía × (1 + N(0, 0,05));
  - cifras por modelo en §12.
- **Avance:** cuando acaba `alto`, si `quiereAvanzar` y se movió, `quieto =
  0`.

## 9. Lanzacohetes (`actualizarLanzacohetes`, `tropas.lua:2828`)

### 9.1 Máquina de fases

| Fase | Qué hace | Pasa a |
|---|---|---|
| `orden` | Con una orden que avanza: baja la rampa (máx/2,5 s), recoge los gatos (1,5 s) y conduce | `frenando` al acabar la orden |
| `frenando` | Espera a `velocidadRuedas < 1` px/s durante 0,6 s | `espera` (con `espera ≥ 0,3`) |
| `espera` | Baja la rampa (máx/2 s) y recoge los gatos. Con la rampa vacía y munición libre, se va a recargar. Si `espera ≤ 0`, no está expuesto, está quieto y armado, busca blanco | `apoyando` (camión de gatos) o `subiendo`. Sin blanco, `espera = 3` |
| `apoyando` | Baja los gatos: 1,5 s | `subiendo` |
| `subiendo` | Sube la rampa a máx/3 s (máx = `modelo.elevacion`, 35 si no la dice) | `fuego` con `espera = 0,5`. Calcula la salva |
| `fuego` | Lanza el k-ésimo misil que se dibuja con su parte de la salva. Entre misiles: 2,5 s en rampa (Scud-B) o `0,5·cuántos` s en tubos | Al acabar o sin blanco: `bajando`, con `espera = tiempoRecarga` |
| `bajando` | Baja la rampa (máx/2,5 s) y luego los gatos | `recarga` |
| `recarga` | Cuando `espera ≤ 0`, sube una salva (el Scud-B, 1 misil). Si caben más, otra espera | `espera` con `espera = 1` |

- **`tiempoRecarga`** = U(13, 20) s, más 2 s si es de rampa.
- **Expuesto** (mirado cada 1 s): hay un tanque enemigo a menos de su mínimo
  (500 m). Expuesto, o con las ruedas a más de 1 px/s, mientras se prepara:
  pasa a `bajando` con `espera ≥ 3`.
- **Blanco** (`blancoDeMisil`, `:1263`): uno al azar entre los enemigos entre
  el mínimo y el alcance. Los tanques cuentan doble.
- **Averiado** con la rampa arriba: la baja en `paso`.
- La fase `despliegue` (`:2856`) no se asigna en ningún sitio: es código
  muerto.

### 9.2 Rampa y munición (`:1019–1165`)

| Modelo | Carga | Proyectiles por salva | Forma |
|---|---|---|---|
| Scud-B | 4 misiles | 1 | De uno en uno (`enRampa`) |
| BM-21 | 40 | 40 | Tubos: una salva |
| HIMARS | 6 | 6 | Tubos: una salva |

- **Al entrar** se carga hasta llenar, con min(huecos, munición libre de su
  fuente / porDisparo).
- **Lo cargado queda apartado** en `f.cargado` y solo se **gasta** al salir:
  `dispararCargado`.
- **Si el camión cae,** lo que lleva en la rampa cuenta como gastado
  (`perderCarga`).
- **Salva visible:** como mucho 8 misiles dibujados (`repartoSalva`,
  `:1792`); cada uno lleva su parte de los proyectiles. El BM-21 lleva 5
  cohetes en cada uno.
- **`lanzarMisil`** (`:1810`), por proyectil pagado:
  - punto de caída = blanco + dispersión circular normal con σ = cep/√(2 ln 2)
    (`caida`, `:1780`);
  - trayectoria indirecta (§10.2);
  - el primero se dibuja y los demás vuelan ocultos, pero chocan igual.

**Ciclos medios** (de las cifras, sin medir):

- Scud-B: unos 90 s por 4 misiles;
  - 1,5 + 3 + 0,5 + 3·2,5 + 2,5 + 1,5 = 16,5 s de disparo;
  - más 4·(16,5 + 2) = 74 s de recarga;
  - el comentario del código da 20,8 s por misil medidos.
- BM-21: unos 40 s por salva de 40.
- HIMARS: unos 25 s por salva de 6.

## 10. Proyectiles (`dano/trayectoria.lua`, `dano/proyectiles.lua`)

### 10.1 Tiro directo (analítico)

**Trayectoria:**

- recorrido s(t) = ln(1 + k·v₀·t)/k;
- t(s) = (e^{k·s} − 1)/(k·v₀);
- posición = origen + u·s(t) − (0, 0, g·t²/2);
- velocidad = v₀/(1 + k·v₀·t).

**`apuntar`** (`trayectoria.lua:71`): dos vueltas de sobreelevación.

**Choque con el terreno al disparar** (`lanzarDirecto`, `proyectiles.lua:79`):

- la curva se recorre en `clamp(ceil(alcance/1500), 2, 30)` cuerdas con
  `Impactos.terreno`;
- de ahí salen `duracion` y el punto final.

**En cada paso** se mira el tramo [visto, t] contra árboles, rocas,
edificio y cuerpos (`tramo`, `:156`). No se mira si los dos extremos van a
más de 40 m del suelo y lejos del edificio.

**Contra un soldado:**

- una bala: 1 baja (§11.4);
- un perforante: lo atraviesa y sigue;
- una explosiva: estalla.

**Contra un vehículo:** `golpeVehiculo` con pen = pen₀·(v/v₀)^1,5.

**Rebote:**

- solo una vez y nunca una bala;
- sale reflejado en la cara, con 0,5 de velocidad y 0,5 de penetración,
  alcance de 1,5 km y como autor la unidad golpeada.

**Contra un árbol:** el cañonazo lo tumba.

**Límite:** con más de 1500 proyectiles vivos, el nuevo se resuelve entero
en el acto.

### 10.2 Tiro indirecto

- **Parábola sin aire:** de 45° hasta el punto de caída, o de 62° si el
  blanco está demasiado alto. Su velocidad es
  v = √(g·r²/(2c²·max(0,05r, r·tan − h))).
- **Impulso:** durante min(1,2 s, vuelo/4) es una curva de Hermite desde la
  boca, por el eje de la rampa, que empalma con la parábola en posición y
  velocidad.
- **Choque con el terreno al lanzar:** en 24 cuerdas hasta 1,3·vuelo.
- **Mientras va alto:** cuando está por encima del suelo más alto del camino
  más 70 m (y del edificio más 120 m), no se buscan choques.
- **Árboles:** no se miran los primeros 0,4 s.
- **Golpe directo en un vehículo:** se resuelve como penetración de la
  ojiva. Después estalla siempre (`Explosiones.estallar`).

### 10.3 Haz de infantería

**Cómo vuela:**

- una trazadora por la línea central;
- cada bala j lleva su desvío (ex_j, ez_j);
- su posición a recorrido s = centro(s) + lado·ex_j·s + z·ez_j·s.

**Obstáculo antes de la zona** (`obstaculoHaz`, `:521`):

- cada bala viva se prueba contra ese obstáculo en ±5 m;
- las que dan se aplican y las demás siguen;
- el haz ya no vuelve a chocar con ese obstáculo.

**En la zona** (`resolverHaz`, `:610`), desde 30 m antes del blanco hasta
60 m detrás:

- un rayo por bala contra:
  - el perfil del terreno, muestreado cada 12 px;
  - las plantas;
  - los cuerpos;
- gana el primer choque;
- cada rayo vale `peso` balas, redondeando la parte decimal al azar.

## 11. Daño

### 11.1 Cuerpos (`dano/cuerpos.lua`)

**Rejilla:** celdas de 25,6 m, rehecha en cada paso con los vivos y los
averiados.

**Cajas orientadas** sacadas de los vértices del modelo:

- tanque: casco (con la postura del terreno), torreta y cañón;
- camión: chasis y contenedor;
- soldado: 0,5 × 0,3 × 1,8 m (1,15 m si va agachado), girada con su rumbo;
- el edificio.

**Cruce:** por placas, en coordenadas locales. Da la cara de entrada (eje y
signo) y el punto local.

**Esto se porta con los modelos de UE:** cajas sacadas de las mallas
importadas, con las mismas medidas.

### 11.2 Vehículos (`dano/blindaje.lua`)

**Zona** (`zonaTanque`, `:124`):

- cañón: espesor `costadoTorreta`;
- torreta: frente, trasera, costado o techo según la cara;
- casco:
  - con la cara a ±y y z < 35 % del alto: **orugas** (espesor `costadoCasco`);
  - en el 30 % trasero del largo: **motor**;
  - si no, casco.

**Zona en el camión** (`zonaCamion`, `:156`):

- contenedor: `canon` (el lanzador, 5 mm);
- ruedas: las mismas reglas que las orugas;
- el 35 % delantero: cabina (8 mm);
- el resto: carga (5 mm).

**Ángulo y penetración:**

- θ = acos|n|;
- blindaje efectivo = espesor/max(0,02, cos θ);
- rebota si θ > 75° (perforante) o 65° (explosiva y ojiva);
- penetra si pen ≥ efectivo.

**Golpe pesado** (cañón u ojiva) en la oruga o en el cañón de un tanque: los
rompe **aunque no penetre**.

**Penetración** (`averiarZona`, `:175`):

- estructura + 0,15;
- bajas: 1, o 2 con un sobrante mayor del 50 %;
- según la zona:

  | Zona | Qué pasa |
  |---|---|
  | Orugas | Rotas |
  | Cañón | Roto |
  | Motor | Roto |
  | Torreta | Atascada con 0,5 de probabilidad, más bajas |
  | Cabina | Motor roto con 0,5 de probabilidad, más bajas |
  | Carga | Estructura + 0,15 más |
  | Casco | Bajas |

**Bala de fusil que atraviesa la chapa del camión:**

- estructura + 0,01;
- según la zona:
  - cabina: un tripulante con 0,3 de probabilidad; si no, el motor con 0,1;
  - ruedas: 0,15;
  - lanzador: 0,05.

**Tripulante que cae:** muere con 0,4 de probabilidad; si no, queda herido.

**Onda** (`:267`):

- estructura += onda·(1 − d/letal);
- la oruga se rompe con probabilidad 1,4286·onda·(1 − d/letal).

**Metralla:** solo contra el camión. Hiere a un tripulante con probabilidad
0,3·(1 − d/metralla).

**Daño que vuelve** (`Blindaje.dano`, `:31`):

- min(1, estructura + 0,1·tripulación + 0,2 orugas + 0,25 torreta + 0,3
  cañón + 0,35 motor);
- `vida = vidaMax·(1 − daño)`.

**Fuera de combate** (`fueraDeCombate`, `:69`):

- sin tripulación;
- o cañón roto e inmóvil;
- o estructura ≥ 1.

Entonces queda **averiado** (`averiar`, `tropas.lua:1438`): muerto para la
IA, humea y no explota. **Los vehículos nunca se destruyen** (regla de
El dueño). `destruir` (`:1406`) solo lo usan las pruebas del camión.

### 11.3 Explosiones (`dano/explosiones.lua`)

**A quién alcanza:** a los cuerpos a menos de max(metralla, 2·letal) + 8 m.
Todos quedan amenazados (bajo fuego).

**Escuadra** (`:55`):

- sus n soldados en pie están en un disco de 8 m:
  r_i = 80·√((i − 0,5)/n) y ángulo i·ángulo áureo + rumbo;
- distancia en 3D con dz = u.z + 10 − z;
- P = 2^−(d/letal)², hasta el radio de metralla;
- más allá de 0,5·letal:
  - × 1,15/1,8 si va agachado;
  - × 0,15 si está a cubierto: la línea de la explosión (+1 m) a la
    escuadra (+1,2 m) cruza terreno, árbol o roca, vehículo o edificio
    (se mira una vez por escuadra y explosión);
- de los que caen, mueren 0,6 dentro del radio letal y 0,25 fuera.

**Vehículo:** la onda dentro del radio letal y la metralla dentro del de
metralla; después, `revisarVehiculo`.

### 11.4 Bala contra un soldado (`balaEnSoldado`, `tropas.lua:1496`)

- cada bala que toca la caja es un soldado caído;
- la primera bala, si da en los 0,25 m de arriba, mata;
- las demás matan con 0,3 de probabilidad; si no, hieren;
- `bajasEscuadra` recorta a los que quedan en pie. Sin nadie, la figura cae.

## 12. Cifras por modelo

Salen de `Simulacion.fichaModelo` y de `dano/datos.lua`. Las calculé con
LuaJIT sobre la etiqueta.

### 12.1 Tanques

| | T-55 | T-72B | M1A1 | K2 |
|---|---|---|---|---|
| `velocidadModelo` (× 32 o × 60 px/s) | 0,85 | 1 | 1,2 | 1,167 |
| Alcance | 2,1 km | 2,1 km | 2,1 km | 2,1 km |
| Velocidad de boca, perforante | 1415 m/s | 1700 m/s | 1575 m/s | 1760 m/s |
| Penetración en boca / a 2 km (mm) | 425,7 / 370,8 | 574 / 500 | 612,9 / 533,9 | 654,4 / 570,1 |
| Error / error de distancia (σ) | 1,2 mrad / 0,05 | 0,7 / 0,01 | 0,45 / 0,01 | 0,4 / 0,01 |
| Anticipa | no | sí | sí | sí |
| Explosiva: letal / metralla / onda | 4,8 m / 16 m / 0,28 | 6 / 20 / 0,35 | 5,76 / 19,2 / 0,336 | 5,76 / 19,2 / 0,336 |
| Blindaje (mm): frente del casco / frente de la torreta / costado del casco / costado de la torreta / trasera / techo | 309,8 / 326,5 / 80 / 193,6 / 42,4 / 36,7 | 480 / 520 / 80 / 250 / 40 / 45 | 518,5 / 558,6 / 74,8 / 259,8 / 40 / 42,4 | 536,7 / 603,3 / 84,8 / 273,9 / 40 / 47,4 |
| Tripulación | 4 | 3 | 4 | 3 |

En todos los cañones: arrastre 4,6e-5 /m, dispersión 0,25 mrad y explosiva a
850 m/s.

### 12.2 Lanzacohetes

| | Scud-B | BM-21 | HIMARS |
|---|---|---|---|
| Alcance / mínimo | 3,9 km / 0,5 km | 2,842 km / 0,5 km | 3,438 km / 0,5 km |
| Carga / por salva | 4 / 1 | 40 / 40 | 6 / 6 |
| Radio letal / metralla | 18 m / 45 m | 5,06 m / 12,65 m | 8,39 m / 20,96 m |
| CEP | 45 m | 74,8 m | 37 m (provisional) |
| Munición por proyectil | 1 | 0,03016 | 0,3333 |
| Penetración de la ojiva / onda | 220 mm / 1,05 | 30,5 mm / 0,295 | 56,75 mm / 0,489 |
| Tripulación | 7 | 3 | 3 |
| `velocidadModelo` | 1 | 1,3 | 1,3 |

`Tropas.alcanceMisil = 32000` ("3,2 km") solo se usa si el modelo no trae
alcance. Las cifras de verdad son las de la tabla.

### 12.3 Fusil y soldado

**Fusil:**

- 900 m/s;
- arrastre 1,1e-3 /m;
- penetración de 8 mm a 100 m;
- alcance de juego 600 m y balístico 1 km.

**Soldado:**

- caja de 0,5 × 0,3 × 1,8 m;
- agachado, 1,15 m;
- la cabeza son los 0,25 m de arriba;
- una bala en el cuerpo mata con 0,3 de probabilidad.

**Munición:** 5 balas por soldado y ráfaga, 1 obús por cañonazo y 1 misil
de munición por cada «porDisparo».

## 13. Despliegue (`batalla/despliegue.lua`)

**Cuándo:** solo con `combate.preparacion`, es decir, al entrar desde el
juego.

**Contador:** 120 s con la pelea parada. Termina al llegar a cero o cuando
los dos bandos están listos. El NPC está listo enseguida (`formarNpc`).

**Separación:** los bandos forman a 5500 px del centro (1,1 km entre las
primeras filas).

**Zonas** (`medirZona`, `:80`), en el eje del combate (d a lo largo y l de
lado):

- del borde delantero, a 5000 px del centro (franja neutral de 1 km), hasta
  detrás de la última unidad + 500 px;
- al menos 3500 px de fondo y 8000 px de medio ancho;
- recortadas por el límite, salvo lo justo para que quepa la última unidad
  (150 px).

**Cámara del jugador** en la preparación:

- dentro de su zona;
- a 80 m como mucho;
- mirando al menos 30° hacia abajo.

**Hoy no se pueden recolocar unidades ni dar órdenes en la preparación.**
`escena.lua:1115` lo dice: «la colocación llega en el paso 2».

## 14. Final y resultado

**Final** (`Tropas:fin`, `tropas.lua:3291`). Por bando:

| Motivo | Cuándo | Qué pasa |
|---|---|---|
| `fuera` | No le queda nada en pie, ni en el campo ni en la reserva | Pierde |
| `municion` | Todo lo que tiene en pie está sin munición o sin arma, y la reserva tampoco tiene munición | Pierde y se retira |
| `alcance` | En 60 s (`sinFuego`) ni ha disparado ni ha avanzado una unidad armada | Pierde y se retira |

- **Exentos de `alcance`:**
  - el bando del jugador;
  - un bando con alguna unidad armada que mantiene posición.
- **Varios a la vez:** `fuera` gana sobre los demás; si no, pierde el
  atacante.

**Cierre:** `Escena:vigilarFin` fija el final la primera vez y 6 s de pelea
después marca `cerrar`.

**Resultado** (`Tropas:resultado`, `:3392`; formato en DANO-REAL §5.6), por
lado:

- soldados: muertos y heridos;
- tripulación: muertos y heridos;
- averiados por tipo: daño redondeado a 4 decimales, modelo y zonas;
- munición gastada por fuente, redondeada.

**Lo que se ve en pantalla** sale de `recuento` (`:3329`).

## 15. Determinismo y azar: lo que hay que saber al portar

1. **Hay un solo azar para todo:** `tropas.azar`, un RandomGenerator de LÖVE
   (xorshift64* de LÖVE 11.5; el detalle hay que mirarlo en su fuente,
   `RandomGenerator.cpp`).
   - `randomNormal` guarda el segundo valor de Box-Muller.
   - **Las partículas de la escena también lo consumen:** `Tropas:impacto`,
     `humo` y `fogonazo` (`:1299–1404`). DANO-REAL §8.1 dice que los efectos
     tienen el suyo, pero eso solo vale para los de Camila
     (`batalla/efectos.lua`).
   - Por eso **no se puede reproducir LÖVE bit a bit** si en UE los efectos
     usan otro azar (y deben usarlo). La comparación tiene que ser
     estadística, sobre varias semillas.
2. **Box2D en coma flotante** decide el movimiento de los vehículos, y solo
   existe si está la vista 3Dream (§2.1). En UE: un movimiento propio,
   determinista, que copie las velocidades y los giros **efectivos** (§6.4).
3. **El orden importa:**
   - una unidad tras otra, en orden de entrada, consumiendo azar, munición y
     líneas de fuego dentro del mismo paso;
   - el bando 1 actúa antes que el 2;
   - los proyectiles avanzan del último al primero.
4. **Las órdenes no se sellan con el número de paso.** En UE: comandos con
   el paso en que se aplican.
5. **`table.sort`** en `Ordenes:formacion` no es estable con empates; en la
   misma máquina da lo mismo. En C++: `std::stable_sort` con desempate por
   `numero`.
6. **La boca del fusil sale de la animación horneada:** el reloj del clip es
   estado de la simulación.

## 16. Arquitectura en C++ y Mass **[Propuesta]**

### 16.1 Principios

- **La simulación de la batalla es C++ sin render.**
  - Mismo contrato que `NationsSim`: determinista, por comandos, con estado
    como datos y capaz de correr en un servidor sin pantalla.
  - La vista solo lee el estado y una cola de eventos.
- **Paso fijo de 1/60 s.** Lo da un subsistema que ejecuta la tubería de
  procesadores de Mass a mano, k veces por cuadro, en un solo hilo y en
  orden fijo. No se registra en las fases del tick del mundo.
- **Azar por flujos.** Un PCG32 con semilla = hash(semilla del combate,
  flujo):
  - flujos: `Blancos`, `Tiro`, `Dano`, `Formacion`…;
  - los efectos visuales, aparte y sin influir en la pelea.
- **Matemática en `double`,** con funciones propias para `sin`, `cos`,
  `atan2`, `exp` y `log` si se quiere la misma pelea en Windows y Linux (el
  servidor). La alternativa es aceptar diferencias entre sistemas, como hoy.
- **Ids estables** = (bando, `numero`). Lo que consume azar o recursos se
  recorre ordenado por id, no en el orden de los trozos (chunks) de Mass.

### 16.2 Módulos

Propuesta: un plugin `Batalla` con un módulo por área. Las dependencias van
solo hacia abajo en la tabla:

| Módulo | Contenido | Sin UE | Equivale a |
|---|---|---|---|
| `BatallaNucleo` | Tipos (`FIdUnidad`, `FBando`), reloj de paso fijo, RNG por flujos, comandos (`FCmdMover`, `FCmdAtacar`, `FCmdMantener`, `FCmdListo`, cada uno con su paso), cola de eventos (`FEvDisparo`, `FEvImpacto`, `FEvBaja`, `FEvAveria`, `FEvFin`), fragmentos comunes (posición y rumbo, bando y tipo, vida, munición y fuente), resultado JSON y datos de armas (`Datos/armas.json`) | C++ puro y fragmentos | `dano/datos.lua`, formato §5.6, `pasoFijo` |
| `BatallaTerreno` | Consultas: altura, desnivel, `transitable`, `libre`, agua, límite, plantas en rejilla y su derribo, pasillos de avance, rejilla de rutas, A* y suavizado | C++ puro | `suelo` (consultas), `agua`, `limite`, `pasillos`, `ordenes` (rutas) |
| `BatallaDano` | Cajas, rejilla de cuerpos, cruce rayo-caja, zonas, penetración, averías, explosiones (Carleton) y cobertura | C++ puro | `dano/cuerpos`, `blindaje`, `explosiones`, `impactos` |
| `BatallaProyectiles` | Balística directa e indirecta (analítica), haz de infantería, paso de proyectiles, rebote, límite de vivos | C++ puro y fragmentos de proyectil | `dano/trayectoria`, `dano/proyectiles` |
| `BatallaTropas` | Infantería: fragmentos (escuadra, ráfaga, bajo fuego, animación lógica) y procesadores (blanco, fuego, marcha) | Mass | `tropas.lua` (soldados), `soldados.lua` (reloj y boca) |
| `BatallaVehiculos` | Tanques y camiones: fragmentos (torreta, averías, fases de la rampa, gatos, ruedas) y procesadores (blanco, torreta, fuego, máquina de la rampa) y movimiento de vehículo propio | Mass | `tropas.lua` (tanques y camiones), `fisica.lua` (efecto), `lanzamisiles.lua` (lógica) |
| `BatallaOrdenes` | Selección (en el cliente), formación de huecos, seguir la orden y desatasco. Un comando entra y una orden sale en el fragmento `FOrden` | Mass y C++ | `control.lua` (parte lógica), `ordenes.lua` (formación), `seguirOrden` y siguientes |
| `BatallaFlujo` | Formación inicial, oleadas, despliegue, final y resultado | Mass y C++ | `formar`, `relevar`, `despliegue.lua`, `fin`, `resultado` |
| `BatallaVista` (solo cliente) | Representación: ISM y animación por textura, articulaciones, Niagara (que lee los eventos), audio, decals de selección y ruta, cámara (Pawn), UMG | UE | `dream/*`, `efectos`, `marcas_holo`, `camara`, interfaz |

- **Quién habla con quién.** Los módulos de lógica no se llaman entre sí en
  círculo. Usan funciones puras de los de abajo (`Terreno`, `Dano`,
  `Proyectiles`) y la cola de eventos del núcleo.
  - **Ejemplo:** `BatallaTropas` pide un disparo metiendo `FSolicitudDisparo`;
    `BatallaProyectiles` lo pone a volar; el impacto llama a `BatallaDano`,
    que deja `FEvBaja` y `FEvAveria`.
- **Quién lo hace.** Cada módulo tiene su cabecera de interfaz (`I*.h`) y
  sus pruebas de automatización con los nombres de la §17. Así Codex puede
  hacer `BatallaDano` o `BatallaProyectiles` (C++ puro, con pruebas
  numéricas cerradas) mientras otro hace `BatallaTropas` o
  `BatallaVehiculos`.

### 16.3 Orden de los procesadores en cada paso

Copia el de §2.3:

1. Aplicar los comandos de este paso.
2. Oleadas.
3. Avance medio.
4. Por unidad, ordenadas por id. Para parecerse a LÖVE, un procesador por
   tipo dentro de la misma pasada ordenada:
   - órdenes;
   - blanco;
   - apuntar;
   - disparar, que mete solicitudes;
   - pedir el movimiento.
5. Integrar el movimiento.
6. Postura sobre el terreno, ruedas y orugas (con `velocidadRuedas`).
7. Velocidades.
8. Rejilla de cuerpos.
9. Proyectiles, impactos y daño.
10. Final.

### 16.4 Lo que no va en Mass

- La cámara, la interfaz, la selección con el ratón y el selector por rayo:
  actores y UMG.
- Los árboles derribados y los restos: Chaos solo para lo que cae, sin
  influir en la pelea. El árbol tumbado deja de estorbar en la consulta de
  plantas de `BatallaTerreno`, no en Chaos.

## 17. Pruebas de aceptación

Se proponen nombres `PA-<SISTEMA>-<nn>` para que coincidan con
`diseno/pruebas-aceptacion-batalla.md` de Elena, y en UE la prueba de
automatización `NationsRTS.Batalla.<Sistema>.PA_<SIS>_<nn>`.

**Origen de cada cifra:**

- **A:** analítica. Calculada con LuaJIT y los módulos puros de la etiqueta.
  Tolerancia de 0,1 %.
- **M:** medida en LÖVE (el arnés y la semilla se indican). Tolerancia de
  ±10 % salvo que se diga otra.
- **C:** regla del código. Debe cumplirse exacta.

### 17.1 Balística (BAL)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-BAL-01 | Perforante del T-72B a 1000 / 2000 m, sin gravedad en el recorrido: tiempo de vuelo | 0,602 / 1,232 s | A |
| PA-BAL-02 | Velocidad que le queda al perforante del T-72B a 2000 m | 1550,6 m/s | A |
| PA-BAL-03 | Sobreelevación para 2000 m en llano: T-55 / T-72B / M1A1 / K2 | 5,37 / 3,72 / 4,33 / 3,47 mrad | A |
| PA-BAL-04 | Explosiva (850 m/s) a 1000 m: tiempo de vuelo | 1,302 s | A |
| PA-BAL-05 | Fusil a 100 / 300 / 600 m: tiempo de vuelo | 0,117 / 0,395 / 0,944 s | A |
| PA-BAL-06 | Tiro indirecto en llano a 1 / 2 / 3 / 3,9 km: vuelo a 45° | 14,29 / 20,20 / 24,74 / 28,21 s | A |
| PA-BAL-07 | Ápice del tiro indirecto a 3 km | 750 m | A |
| PA-BAL-08 | El impulso dura min(1,2 s, vuelo/4) y empalma con la parábola sin salto de posición ni de velocidad | diferencia < 1e-6 | C |
| PA-BAL-09 | Dispersión de caída: de 10 000 proyectiles con un CEP de 45 m, la mitad cae a menos de 45 m | 50 % ± 1 % | C |

### 17.2 Penetración y averías (DAN)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-DAN-01 | Penetración del perforante del T-72B a 1 km / 2 km (sin variación) | 535,7 / 500,0 mm | A |
| PA-DAN-02 | T-72B contra T-72B, de frente (θ = 0) a 2 km: el casco penetra (500 ≥ 480) y la torreta no (500 < 520) | sí / no | A |
| PA-DAN-03 | T-55 contra cualquier otro tanque de frente a 1 km: no penetra; de costado del casco: penetra | no / sí | A |
| PA-DAN-04 | K2 contra cualquier tanque de frente a 1 km: penetra el casco y la torreta | sí | A |
| PA-DAN-05 | Perforante a θ = 76° en cualquier cara: rebota; la explosiva y la ojiva, a θ = 66° | rebote | C |
| PA-DAN-06 | Golpe pesado en el tercio bajo del costado del casco, sin penetrar: oruga rota e inmóvil, pero sigue disparando | sí | C |
| PA-DAN-07 | Golpe pesado en el cañón sin penetrar: cañón roto y no dispara | sí | C |
| PA-DAN-08 | Cañón roto + oruga rota = fuera de combate (averiado, no destruido) | sí | C |
| PA-DAN-09 | Una penetración en el casco: estructura 0,15, 1 baja (2 si el sobrante es > 50 %). Daño = 0,15 + 0,1 por baja | exacto | C |
| PA-DAN-10 | T-72B (3 de tripulación) con 1 baja: recarga × 1,5 (de 6–11 s a 9–16,5 s) | exacto | C |
| PA-DAN-11 | Scud-B que estalla en el suelo bajo el centro de un tanque, sin golpe directo. La distancia es de 1,2 m, porque la onda se mide a `u.z + 12` px. Estructura + 0,980 y oruga rota segura. **No queda fuera de combate por sí solo:** le falta 0,02 de estructura | 0,980 | A |
| PA-DAN-12 | Igual con otras ojivas (estructura / P de oruga rota): cohete del BM-21, HIMARS, explosiva del T-72B | 0,225 / 0,322 · 0,419 / 0,599 · 0,280 / 0,400 (P ± 0,02 en 10 000 tiradas) | A |
| PA-DAN-13 | Un vehículo nunca desaparece ni explota por daño: tras cualquier batalla, `todas` conserva todos los vehículos que entraron | sí | C |

### 17.3 Explosiones contra infantería (EXP)

Escuadra de 10 de pie, sin cobertura, rumbo 0. Esperanza sobre 10 000
tiradas, tolerancia de ±3 %.

| Id | Prueba | LÖVE (caen / mueren) | Origen |
|---|---|---|---|
| PA-EXP-01 | Carleton: P a r/letal = 0,5 / 1 / 2 / 2,5 | 0,841 / 0,500 / 0,062 / 0,013 | A |
| PA-EXP-02 | Scud-B a 0 / 10 / 20 / 40 m del centro | 9,33/5,60 · 7,65/4,59 · 4,21/1,67 · 0,37/0,09 | A |
| PA-EXP-03 | Cohete del BM-21 a 0 / 10 / 20 m | 4,62/2,14 · 1,37/0,55 · 0/0 | A |
| PA-EXP-04 | HIMARS a 0 / 10 / 20 m | 7,34/4,41 · 3,63/1,46 · 0,38/0,09 | A |
| PA-EXP-05 | Explosiva del T-72B a 0 / 10 m | 5,64/2,69 · 1,99/0,94 | A |
| PA-EXP-06 | A cubierto: la parte de más allá de 0,5·letal × 0,15; agachado en marcha: × 0,639 | exacto | C |

### 17.4 Infantería (INF)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-INF-01 | Escuadra sin enemigos a menos de 600 m en llano: avanza a 2,5 m/s (100 m en 40 s ± 2 s, una vez encarada) | 2,5 m/s | C |
| PA-INF-02 | Escuadra bajo fuego (le dispararon hace menos de 4 s) que avanza: 0,4 m/s y caja de 1,15 m | exacto | C |
| PA-INF-03 | Escuadra sin orden con un enemigo a 650 m y visible: no dispara y sigue avanzando; con él a 590 m y visible: se para y dispara | sí | C |
| PA-INF-04 | Se para a 210 m del enemigo más cercano si no tiene blanco visible | 210 m | C |
| PA-INF-05 | Ráfaga de una escuadra de 8 en pie: 40 balas y 40 rayos de peso 1; de 12 en pie: 60 balas, 40 rayos y peso 1,5 | exacto | C |
| PA-INF-06 | Gasto: 5 balas por soldado en pie y ráfaga; 6 ráfagas y luego 3,3 s de recarga; ciclo medio de 2,1 s (143 balas/min por soldado) | ± 5 % | C |
| PA-INF-07 | Bala en el cuerpo: muere con 0,3; la primera bala en la cabeza (0,25 m de arriba): muere | exacto | C |
| PA-INF-08 | No dispara si el primer cuerpo de la línea de fuego es propio; vuelve a mirar a los 0,5 s | sí | C |
| PA-INF-09 | Escuadra con orden de mover: no dispara hasta llegar | sí | C |

### 17.5 Tanques (TAN)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-TAN-01 | Gira la torreta a 0,6 rad/s: 180° en 5,24 s | exacto | C |
| PA-TAN-02 | De apuntado a disparo: se para y dispara cuando lleva 0,7 s quieto; después, `espera` U(6, 11) s | exacto | C |
| PA-TAN-03 | Prefiere un lanzacohetes enemigo a menos de 650 m antes que cualquier otro blanco | sí | C |
| PA-TAN-04 | Abre fuego a ≤ 2,1 km con línea de vista; a 2,2 km no | sí | C |
| PA-TAN-05 | Contra infantería tira explosiva; contra vehículos, perforante | sí | C |
| PA-TAN-06 | Tanque sin orden en llano, a lo largo de un pasillo: velocidad efectiva (modelo por confirmar, §6.4) | 1,8 m/s | M (pruebas_control, semilla 42) |
| PA-TAN-07 | Atacante sin orden: deja de avanzar con un tanque enemigo a menos de 300 m; defensor: sale como mucho 150 m | sí | C |
| PA-TAN-08 | Ningún tanque sin orden se adelanta más de 35 m a la media de su bando | sí | C |

### 17.6 Lanzacohetes (LAN)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-LAN-01 | Scud-B parado y con blanco a 2 km: gatos 1,5 s, rampa arriba 3 s, primer misil a los 0,5 s y los siguientes cada 2,5 s. Los 4 salen en 12,5 s ± 0,1 desde que empieza a apoyarse | exacto | C |
| PA-LAN-02 | BM-21: 40 cohetes en 8 grupos de 5, cada 2,5 s (17,5 s del primero al último) | exacto | C |
| PA-LAN-03 | Con un tanque enemigo a menos de 500 m no dispara y baja la rampa (como mucho, 1 s para notarlo) | sí | C |
| PA-LAN-04 | Recarga del Scud-B: un misil cada U(13, 20) + 2 s; rampa llena en 74 s de media | ± 5 % | C |
| PA-LAN-05 | Munición: lo cargado se aparta y no se gasta hasta salir; un camión averiado con 3 cargados suma 3 al gasto | exacto | C |
| PA-LAN-06 | No dispara en marcha: con las ruedas a más de 0,1 m/s mientras se prepara, baja la rampa | sí | C |
| PA-LAN-07 | Blanco al azar entre el mínimo y el alcance, con los tanques dos veces más probables: con 1 tanque y 1 camión a tiro, el tanque sale 2/3 de las veces | 0,667 ± 0,02 | C |

### 17.7 Movimiento y órdenes (MOV, ORD)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-MOV-01 | Tanque con orden de mover en terreno abierto: velocidad efectiva en recta (modelo por confirmar, §6.4) | 3,2–3,6 m/s | M (pruebas_control, semilla 42) |
| PA-MOV-02 | Tres tanques mandados juntos a unos 106 m en línea recta, con rutas suaves de 15 a 35 puntos y la pelea en marcha: los tres cumplen la orden (pasan a mantener). Los dos que la pelea dejó inmóviles o averiados no cuentan en la medida de distancia | Los tres a los 38 s; el que no tiene avería, a 8,6 m de su hueco | M (pruebas_control, semilla 42) |
| PA-MOV-03 | Ninguna unidad pisa agua, pendientes de más de 25° ni el exterior del límite (radio − 60 px) en 600 s de batalla | 0 casos | C |
| PA-MOV-04 | Camión con su punto de lado (> 1,1 rad) y cerca: maniobra marcha atrás en lugar de dar vueltas; llega a menos de 260 px | sí | C (pruebas_control: «el lanzacohetes llega a su puesto», a 259 px) |
| PA-MOV-05 | Atasco: a los 2 / 4 / 6,5 / 9 / 16 s sin moverse 6 m: pedir paso / rehacer la ruta / recular 1,8 s / rodear / rendirse | exacto | C |
| PA-ORD-01 | Clic derecho sobre el terreno: el destino del grupo queda a menos de 15 m del punto bajo el ratón | 12,4 m | M (pruebas_control) |
| PA-ORD-02 | Cada tramo de la ruta pisa solo celdas transitables de 12 m | sí | C |
| PA-ORD-03 | Formación: tanques delante, escuadras y lanzacohetes detrás; huecos a 23 / 8 / 32 m y filas de 8 / 12 / 6 | exacto en llano | C |
| PA-ORD-04 | Mantener: la escuadra con H no se mueve en 15 s | 0 m | M (pruebas_control) |
| PA-ORD-05 | Atacar: se acerca hasta 0,85·alcance con línea de vista y solo dispara a su blanco. **En LÖVE falla** con la semilla 42 (el tanque a 674 m no tiene la vista despejada y no dispara) | Ver §18 | M |
| PA-ORD-06 | Orden de mover a un vehículo con la oruga rota: pasa a mantener | sí | C |

### 17.8 Flujo de batalla (DES, OLE, FIN, DET)

| Id | Prueba | LÖVE | Origen |
|---|---|---|---|
| PA-DES-01 | Preparación: 120 s, o menos si los dos están listos; nadie se mueve, dispara ni recibe daño | exacto | C |
| PA-DES-02 | Zonas: borde delantero a 500 m del centro; al menos 350 m de fondo × 1,6 km de ancho; primera fila a 550 m | exacto | C |
| PA-OLE-01 | Con 40 vehículos en el campo y reserva: el averiado más antiguo sale a los 12 s y entra uno de la reserva por la retaguardia | exacto | C |
| PA-FIN-01 | Bando que en 60 s ni dispara ni avanza con unidades armadas (y no es el del jugador ni mantiene posición): se retira por `alcance`; el cierre llega 6 s después | exacto | C (pruebas_control) |
| PA-FIN-02 | Sin munición en todo lo que está en pie y en la reserva: se retira por `municion` | sí | C |
| PA-FIN-03 | Si les pasa a los dos a la vez, pierde el atacante, salvo que uno quede `fuera` | sí | C |
| PA-FIN-04 | Batalla de la simulación (`pruebas_economia`, semilla 42: 60 tanques, 8 lanzacohetes y 400 soldados contra 25, 6 y 300): dura unos 311 s y el atacante se retira sin munición. Atacante: 188 muertos y 212 heridos. Defensor: 34/60 y 7/25 tanques averiados | ± 20 % en la media de 10 semillas | M (DANO-REAL §10.5) |
| PA-FIN-05 | 30 tanques y 10 lanzacohetes por bando, sin límite de munición, semillas 42 / 7 / 1234: tanques en pie a los 300 s (A/D) | 15/21 · 13/10 · 6/2 | M (DANO-REAL §10.5) |
| PA-DET-01 | Misma semilla y mismos comandos sellados: la misma huella del resultado en dos procesos | igual | C |
| PA-DET-02 | Misma batalla con pasos de 1/20, 1/30 y 1/60 s de cuadro (el paso fijo sigue en 1/60): la misma huella | igual | C (LÖVE lo cumple) |
| PA-DET-03 | Con la vista apagada (servidor): el mismo resultado que con ella | igual | C (**LÖVE no lo cumple**, §15.2) |
| PA-DET-04 | Coste: un paso de la simulación con 40 + 40 vehículos y unas 76 escuadras | LÖVE: 1,33 ms de media y 3,5 ms en el 1 % peor | M (DANO-REAL §9.2) |

**Para comparar UE con LÖVE** en las pruebas M y en las de batalla
completa, se corre la misma composición de bandos en 10 semillas en las dos
y se comparan las medias. Bit a bit no se puede (§15.1).

## 18. Dudas para el dueño

1. **¿Copiamos la velocidad de los vehículos que se ve hoy o la nominal del
   catálogo?** Hoy van más despacio de lo nominal: con orden se midieron
   3,2–3,6 m/s, cuando la cifra nominal es de 5,1 a 7,2 (6 en el T-72B).
   La medida está por confirmar con un solo modelo (§6.4).
   - **a) Copiar la efectiva** (recomendada): se ve igual que en LÖVE.
   - **b) Usar la nominal:** casi el doble de rápidos, y cambian el
     equilibrio y los tiempos.
2. **Orden de atacar sin línea de vista.** En LÖVE, la prueba de control
   falla con la semilla 42: el tanque no dispara a un blanco a 674 m porque
   no tiene la vista despejada, y no se mueve para conseguirla.
   - **a) Corregirlo en UE** (recomendada): si está a tiro pero sin vista,
     se acerca o busca una posición con vista.
   - **b) Copiarlo tal cual.**
3. **Comparar con LÖVE.** No se puede repetir LÖVE bit a bit: el azar es el
   de LÖVE, las partículas lo gastan y los vehículos dependen de Box2D.
   - **a) Comparación estadística** sobre 10 semillas (recomendada).
   - **b) Además, portar el generador de LÖVE** y un modo «LÖVE» para
     comparar al detalle las pruebas analíticas. Cuesta más y no vale para
     las batallas enteras.
4. **¿La misma batalla en Windows y en Linux** (servidor y repeticiones)?
   - **a) Sí:** matemática propia (sin, cos, exp, log) en el núcleo. Algo
     más de trabajo al principio.
   - **b) No por ahora:** basta con el mismo resultado en el mismo binario,
     como hoy.
5. **Infantería con orden de mover bajo fuego.** Hoy, una escuadra con orden
   de mover que está bajo fuego (con un enemigo a menos de 600 m) marcha
   agachada a 0,4 m/s, aunque sea para retirarse.
   - **a) Copiarlo.**
   - **b) Con orden, a 2,5 m/s** (o corriendo).

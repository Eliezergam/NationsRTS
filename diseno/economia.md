# Economía cerrada

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Documento para Andrés (simulación), Valeria y Camila (escena 3D y Arsenal) y
Elena (mediciones). Estado: **decidido por el dueño el 2026-09-30, sin
programar.** Lo marcado «hoy» es lo que hace el código en HEAD c65851a
(versión 20 del guardado, con exploradores). Las líneas citadas son de ese
commit.

Sale de la petición del dueño del 2026-09-30: «Los recursos tienen que estar
conectados a las batallas 3D: si tengo 10 tanques y 10 lanzamisiles, esos son
los que puedo usar en el campo 3D. Agrega un sistema de economía muy lógico,
muy centrado, que todo funcione perfectamente.» La primera versión de este
documento (commit b0179cb) proponía opciones; el dueño eligió el mismo día (ver
§11) y cambió partes clave: los vehículos no se destruyen, lo que se gasta es
la munición y el ejército tiene un tope por nivel de ciudad.

También recoge el pedido de Valeria: la pantalla Arsenal
(`interfaz/arsenal.lua`) existe con «Producir» desactivado porque la
simulación no tiene orden de producir ni publica costos, tiempos ni motivos de
rechazo.

Relacionado y ya programado aparte: el poder enemigo es oculto salvo informe
de explorador (`mundo/simulacion/exploracion.lua`). Este documento no lo
cambia; los exploradores son un gasto más de dinero (20 cada uno).

Las cifras salen de `tools/medir_economia_nationsrts.lua` (ver «Cómo se
midió»): 4 semillas (1, 7, 42, 1234), 500 días, 20 a 22 naciones por semilla.
Ese prototipo se retiró el 2026-09-30, cuando la economía cerrada quedó
programada (454050d): sustituía a `fabricarEnCiudad`, que ya no existe. Sigue
en el historial (commit 9b1c5b2). La economía programada se mide ahora con
`tools/auditar_economia_nationsrts.lua` (de Andrés).

---

## 0. Estado de hoy: qué está conectado y qué no

Cada nación tiene hoy una sola ciudad, su capital (`mundo/ciudades.lua`: «una
por país»). Donde abajo dice «ciudad», en la práctica es la capital.

| Pieza del ciclo | Hoy | Evidencia (HEAD c65851a) |
|---|---|---|
| Recursos entran solo por recolección, talleres, tierras e impuestos | **Sí** | `producirRecursos` (l.2069) solo cobra mantenimiento; `entregarCarga` (recoleccion.lua l.184); talleres (l.2237); impuestos (l.2293) |
| Almacén, bóveda, afuera y merma | **Sí** | `ingresar` (l.538), `pagar` (l.571), `mermar` (l.584) |
| Saqueo de lo de afuera; botín en la mina | **Sí** | `saquearCapital` (l.3482), botín al llegar (l.3526), `repartirCarga` (l.4124) |
| Sacar unidades de un sitio las resta; al volver se suman | **Sí** | `enviarGrupo` (l.1716), `recolectar` (recoleccion.lua l.141-143), `llegada` (l.3520) |
| El jugador puede ordenar producir | **No** | Sin comando en `ejecutar` (l.1200); `interfaz/arsenal.lua` l.9-11 lo dice |
| Soldados con costo | **No: gratis** | `economia` l.2263 suma `floor(parte × 0,5)` sin cobrar; `fabricarEnCiudad` l.2370 regala soldados a las bases |
| Soldados que desaparecen sin combate | **Sí, y muchos** | El mismo `math.min(floor(poblacion × 0,2), …)` de l.2263 **recorta** a los soldados de la ciudad que pasan del 20 % de la población. Medido: 183,6 soldados borrados al día (todas las naciones, media por semilla) |
| Tanques con costo | **Parcial** | Cobra (`COSTES` l.115) pero aparecen al instante, solos, con un 40 % diario (l.2414) |
| Lanzacohetes con costo | **Parcial** | Cobra (`defensasCiudad.coste` l.232) sin tiempo de fabricación; solo lo compra la IA de defensa (`enviarDefensas` l.1390) |
| Munición | **No existe** | Los misiles de las ciudades (`arsenalInicial` l.312) ya no se usan: no hay salvas (decisión 4 de recoleccion-y-batallas.md) |
| Un solo dinero | **No** | Cada ciudad tiene su `c.dinero` aparte del tesoro, sin tope y sin mostrarse (la barra enseña el tesoro, `barrasuperior.lua` l.302) |
| Combustible | **Parcial** | 0,03 por tanque al día, parado o no (l.134, `gastoCombustible` l.1890); los lanzacohetes no gastan; sin petróleo los tanques no salen (l.1678) |
| Trabajo civil | **Con agujero** | `trabajadores = poblacion − c.soldados` (l.2230): los soldados que están fuera cuentan como trabajadores |
| Hambre sin muertes de golpe | **Parcial** | Deserción del 1 % diario (l.2225): los soldados desaparecen |
| Bajas: unos mueren, otros quedan heridos | **No** | `recuperable = 1` (l.275): en un grupo todo lo que cae queda herido; en la guarnición todo muere (`danarSitio` l.4194, `quitarTropa` l.4399) |
| Vehículos de guarnición | **Al azar** | Un tanque al día con probabilidad 0,4 si las bajas pasan de 15 (l.4200); un lanzacohetes con 0,3 si pasan de 40 (l.4203) |
| Reparar cuesta | **No** | La cola devuelve gratis `ritmo × nivel` al día (`recuperar` l.3444); solo acelerar cuesta (l.3382) |
| Nada desaparece fuera de producción y combate | **No** | Desguace de lanzacohetes que no caben (`recibirHeridos` l.3332); entrega recortada al tope (l.3573); heridos de un grupo caído se pierden (`caerEnBatalla` l.4149); campamento abandonado pierde sus lanzacohetes (`retirarGuarnicion` l.2158); grupo sin casa borrado (`volver` l.3228); el recorte al 20 % (arriba) |
| La escena 3D recibe las unidades de la batalla | **Parcial** | `Choques.deBatalla` (choques.lua l.133) pasa lo sano; `Tropas.formar` dibuja como mucho 40 vehículos y 48 soldados por bando (tropas.lua l.33-34) |
| Las bajas de la escena salen del combate | **No** | Tope visual por bando según la fuerza (tropas.lua l.134) y un ritmo en 210 s (`permitidas` l.692, `golpear` l.699) |
| Las bajas de la escena vuelven 1:1 | **Parcial** | `bajasDeEscena` (choques.lua l.164) escala por proporción; `resolverBatalla` (l.4455) las vuelve heridas en grupos y muertes en la guarnición |
| NPC y jugador con la misma regla de producción | **No** | `economia` corre para todas las naciones (l.4540), también la del jugador, sin pasar por `ejecutar` |

### Lo medido hoy (500 días, 4 semillas)

Por nación, mediana del día 100 → mediana del día 500 (rango de las 4
semillas):

| Qué | Día 100 | Día 500 |
|---|---|---|
| Dinero de la ciudad (no se ve) | 1 941 – 2 925 | **25 287 – 39 559** |
| Tesoro (bóveda + afuera) | 733 – 1 093 | 776 – 4 109 |
| Metal | 53 – 69 | 63 – 109 |
| Soldados (sanos, en todas partes) | 1 910 – 2 526 | **9 211 – 12 669** |
| Tanques | 14 – 16 | 125 – 142 |
| Lanzacohetes | 17 | 42 |

- Días-nación con metal por debajo de 5: 5,4 – 7,0 %. Petróleo por debajo de
  5: 2,0 – 2,2 %. Sin combustible: 0,1 – 0,2 %. Hambre: 0,0 – 0,1 %.
- Todas las naciones vivas el día 500 en las 4 semillas.
- Al día, sumando todas las naciones (media por semilla): nacen gratis 502
  soldados netos (358 de ellos, soldados regalados a las bases) y 5,5
  tanques; el recorte al 20 % borra 183,6 soldados; en combate pasan de
  sanos a heridos 39,0 soldados y 0,68 tanques, y mueren unos 12 soldados de
  guarnición; se pierden 1,7 soldados y 0,019 tanques heridos de grupos
  caídos; se desguazan 0,006 lanzacohetes.
- Batallas: 1 658. Vehículos por bando al empezar: mediana 2, p90 15, máximo
  82; 17 bandos (1,0 %) pasan de 40. Soldados por bando: mediana 108, p90
  832, máximo 4 079; 1 137 bandos (68,6 %) pasan de 48.

Lectura: el metal es lo único que frena. El dinero de las ciudades se
dispara porque nadie lo gasta. Los soldados nacen gratis y se borran sin
combate.

---

## 1. Resumen

Cuatro recursos (metal, petróleo, comida y dinero; el oro se cambia por dinero
al entregarlo) entran solo por la recolección, los talleres, las tierras, los
impuestos y el botín. Hay **un solo dinero**, el tesoro de la nación. Todo se
**encarga a mano** con la orden `producir`: el jugador desde el Arsenal y los
NPC con la misma orden. Los soldados cuestan dinero y un civil; los tanques y
los lanzacohetes, dinero, metal y petróleo. Todos tardan unos días y caben
hasta un **tope por nivel de su ciudad**. Lo que se gasta de verdad en la
guerra es la **munición**: balas, obuses y misiles, que se fabrican por lotes
sin tope, viajan con el ejército y se consumen al disparar, igual en la
escena 3D que en la batalla simulada. Sin munición, una unidad deja de
disparar pero sigue en el campo. **Los vehículos nunca se destruyen**: los
que caen van al taller y se reparan pagando metal y dinero, en un tiempo que
depende del daño. **Los soldados sí mueren**: una parte de los que caen muere
y el resto queda herido y se recupera. La escena 3D recibe exactamente las
unidades del grupo (vehículos 1:1, infantería por escuadras, más de 40
vehículos por oleadas) y devuelve el resultado unidad por unidad.

## 2. Fantasía del jugador

- «Tengo 10 tanques y 10 lanzacohetes. Los meto en un ejército y en el campo
  3D aparecen 10 tanques y 10 lanzacohetes.»
- «Mis tanques no se pierden: vuelven destrozados y el taller me cobra metal
  para ponerlos a punto. Si pierdo, me quedo semanas sin blindados.»
- «Mis soldados sí mueren. Cada batalla me cuesta reclutas.»
- «La batalla dura tres días y mis tanques se quedaron sin obuses el
  segundo. Los traigo o les mando un convoy.»
- «Mi capital es de nivel 3: no puedo tener más de 35 tanques. Para tener más
  tengo que mejorarla.»
- «Todo sale del mismo tesoro. Lo que ves arriba es lo que tienes.»

## 3. Reglas

### 3.1 Los recursos y dónde se guardan

| Recurso | Dónde vive | Tope |
|---|---|---|
| Metal, petróleo | Almacén de la nación + afuera | F1 de territorio-y-capitales.md (200 a 1 000 según nivel de la capital) |
| Dinero | **Tesoro de la nación** (bóveda) + afuera | 10 × almacén. **Ya no hay dinero de ciudad** (`c.dinero` desaparece) |
| Comida | Granero de cada ciudad | Como hoy |
| Oro | No se guarda: al entregarse vale 8 de dinero | — |
| Munición | **Polvorín** de cada ciudad (`c.balas`, `c.obuses`, `c.misiles`) y la que lleva cada grupo | Sin tope |

Lo que no cabe en el almacén o la bóveda queda **afuera**: se gasta primero,
pierde el 3 % al día y se lo lleva el enemigo que gana en la capital. Como
hoy.

### 3.2 Fuentes: lo único que hace entrar recursos

| Fuente | Qué da | Regla |
|---|---|---|
| Recolección | metal, petróleo, comida, oro | Como hoy (recoleccion-y-batallas.md) |
| Talleres | 0,3 de metal por ciudad y día | Como hoy |
| Tierras y huerto | comida | Como hoy |
| Trabajo | dinero, todo al tesoro | F2b: sale de los civiles que trabajan, no de la agresividad ni de la guerra |
| Botín | lo de afuera de una capital vencida; carga de recolectores | Como hoy |

### 3.3 Sumideros: lo único que los gasta

| Sumidero | Recurso |
|---|---|
| Producir unidades (§3.4) | dinero, metal, petróleo, civiles |
| Producir munición (§3.6) | dinero, metal, petróleo |
| Sueldos (§3.7) | dinero |
| Combustible (§3.7) | petróleo |
| Reparar vehículos (§3.9) | dinero, metal |
| Acelerar la recuperación de heridos | dinero (como hoy) |
| Obras: campamentos, banderas, bases, mejoras, reparar la ciudad | como hoy |
| Mantenimiento de campamentos y banderas | como hoy |
| Exploradores | 20 de dinero cada uno (exploracion.lua) |
| Comida de la población (soldados incluidos) | comida, como hoy |
| Merma y saqueo de lo de afuera | como hoy |

### 3.4 Producción de unidades

1. **Una sola orden, solo a mano:**
   `ejecutar({ tipo = 'producir', nacion, ciudad, tropa, cantidad })`, con
   `tropa` = `'soldados'`, `'tanques'` o `'lanzacohetes'`. El jugador la da
   desde el Arsenal; el presidente NPC da la misma orden (§3.12). **Nada se
   fabrica solo**, ni para el jugador ni para nadie.
2. **Comprobaciones, en este orden.** Si falla una, se devuelve `false,
   motivo`, que el Arsenal enseña en su aviso:
   - `noEsSuya`: la ciudad no es de esa nación.
   - `sitiada`: la ciudad combatió hoy o ayer.
   - `tecnologia`: los tanques piden la tecnología `tanques` (como hoy).
   - `cantidad`: no es un entero ≥ 1.
   - `tope`: la cantidad pasaría del tope de su ciudad (F3).
   - `poblacion`: los soldados dejarían menos civiles de los que pide F1b.
   - `dinero`, `metal`, `petroleo`: el primero que no alcance para la orden
     entera (lo guardado más lo de afuera).
3. **Se paga al encargar**, todo de una vez, primero de afuera. Los soldados
   dejan de trabajar desde ese momento («en instrucción»); siguen contando en
   la población.
4. **Cola de fábrica** de la ciudad (`c.fabrica`), en orden de encargo, con
   `lineas = nivel de la ciudad`. Cada día avanzan las primeras `lineas`
   órdenes; una orden termina una **tanda** (F2) cada tantos días. Lo
   terminado entra ese mismo día en el inventario de la ciudad.
   **Cambio decidido (2026-09-30, `modo-base.md` F4):** hay dos colas, una de
   soldados y otra de vehículos, cada una con `nivel` líneas como máximo; con
   las estaciones de la base (fase 2), las líneas son las mesas de
   reclutamiento y las líneas de montaje que funcionan. Medido con este mismo
   prototipo: las cifras de §9 no cambian de forma relevante (soldados
   producidos 246,49 al día frente a 246,50; tanques 2,87 frente a 2,91).
5. **Ciudad sitiada:** la cola de unidades no avanza (no se pierde). La
   capital vencida conserva su cola, su taller y su polvorín.
6. **Cancelar** (`ejecutar({ tipo = 'cancelarProduccion', nacion, ciudad,
   orden })`): se devuelve el 50 % de lo que aún no salió (con `ingresar`: lo
   que no quepa va afuera); los soldados en instrucción vuelven a trabajar.
7. **Lanzacohetes.** Se producen con la misma orden. Los que caben en las
   plataformas de la ciudad o de sus bases (`topeLanzacohetes`) defienden;
   el resto espera en el **parque** de la ciudad (se pueden sacar en un
   grupo). `enviarDefensas` pasa a ser «colocar lanzacohetes que ya tienes».
   Las baterías antiaéreas siguen como hoy.
8. **Misiles antiaéreos, interceptores y aviones** siguen pausados (decisión
   4 de recoleccion-y-batallas.md). Los «misiles» de este documento son la
   munición de los lanzacohetes.

### 3.5 Inventario y tope

Toda unidad está en **uno y solo un** estado:

| Estado | Dónde | Pelea | Cuenta en el tope | Cobra sueldo |
|---|---|---|---|---|
| En fábrica | `c.fabrica` | No | Sí | No |
| Sana en un sitio | ciudad, base o campamento | Sí (guarnición) | Sí | Sí |
| En un grupo | `g.soldados`, `g.tanques`, `g.lanzacohetes` | Sí | Sí | Sí |
| Herida o averiada en un grupo | `g.heridos` | No | Sí | Sí |
| En el taller | `c.recuperando` | No | Sí | Sí |
| En camino a una plataforma | grupo `entrega` | No | Sí | Sí |
| Soldado muerto | ya no existe | — | — | — |

Los vehículos no tienen estado «destruido». **Invariante** (lo comprueba
Elena cada día): por nación y tipo, `Σ estados` = `iniciales + terminadas en
fábrica − soldados muertos en combate − soldados licenciados`. Para los
vehículos: `Σ estados` = `iniciales + terminados`.

**Tope por ciudad** (F3): cada tipo tiene un máximo según el nivel de su
ciudad, y cuenta todo lo que es de ella, esté donde esté (en casa, fuera, en
el taller o en fábrica). Las unidades de las bases y los campamentos cuentan
en la ciudad que los abastece (`ciudadDuena`). Si la ciudad baja de nivel (no
ocurre hoy) no se pierde nada: solo no se puede encargar más hasta estar por
debajo.

### 3.6 Munición

1. **Tres tipos:** balas (soldados), obuses (tanques) y misiles
   (lanzacohetes).
2. **Se fabrica por lotes** con `ejecutar({ tipo = 'producir', nacion,
   ciudad, municion, lotes })`. Costo y días por lote en F4. **Sin tope de
   fabricación:** no ocupa líneas y todos los lotes encargados salen a la vez
   al cumplirse sus días; la ciudad sitiada sigue fabricando munición (son
   sus talleres, dentro de la ciudad). Va al polvorín de la ciudad.
3. **Guarnición:** las unidades de una ciudad disparan del polvorín de esa
   ciudad; las de una base o un campamento, del polvorín de la ciudad que los
   abastece.
4. **Un grupo se lleva su munición.** Al salir elige cuánta (el jugador en el
   panel de envío; por defecto, `dotacion` días de batalla, F5). La munición
   sale del polvorín. Al volver, lo que sobra vuelve al polvorín.
5. **Se gasta disparando.** Cada unidad gasta `porSegundo` en la escena 3D
   por cada disparo que hace, y `porDia` por cada día de batalla simulada
   (F6). Los dos números son el mismo ritmo: un día de batalla simulada
   equivale a los 210 s de combate de referencia de la escena.
6. **Sin munición** un tipo de unidad deja de disparar: su golpe es 0 en la
   batalla simulada y en la escena no dispara. Sigue en el campo, recibe
   daño y se puede retirar. La ficha del ejército y la batalla avisan
   («Tanques sin obuses»). Con munición a medias, golpea en proporción (F6).
7. **Abastecer:** `ejecutar({ tipo = 'abastecer', nacion, desde, grupo,
   balas, obuses, misiles })` saca munición del polvorín y la manda al grupo;
   llega en lo que tarda un ejército en recorrer la distancia (al menos un
   día). Si al llegar el grupo ya no existe, vuelve al polvorín.
8. **Grupo que cae entero:** su munición se pierde.

### 3.7 Mantenimiento y qué pasa si falta

**Sueldos (se quedan, como gasto; no son el límite del ejército).** Cada día
la nación paga del tesoro F7 por cada unidad que tiene (salvo en fábrica). El
límite del ejército es el tope por nivel (§3.5). Los sueldos se quedan porque
sin ellos, con el tope alcanzado, el dinero se acumula y se evapora afuera
(medido en §9: sin sueldos se pierden por merma 33 de dinero al día por
nación; con sueldos, 11,5). Si no alcanza:

- los soldados de la guarnición se **licencian** con F8 (vuelven a ser
  civiles, siguen en la población);
- la nación queda en **impago** ese día: se rechazan encargos (motivo
  `impago`).

**Combustible (petróleo).** F9 según lo que hace el vehículo. Si no alcanza
(`n.sinCombustible`): los vehículos no salen de sus sitios, los grupos que ya
están fuera van a media velocidad y en batalla sus vehículos no avanzan
(disparan desde donde están si tienen munición). Nada se destruye.

**Comida.** Como hoy: los soldados comen como habitantes de su ciudad, estén
donde estén. Con hambre, los soldados de la guarnición se licencian con F8 en
lugar de desaparecer, y el taller no cura soldados (como hoy).

### 3.8 Ejércitos

1. Sacar unidades de un sitio las resta del sitio y las suma al grupo en el
   mismo paso, con la munición que se lleven. **Ya es así para las unidades.**
2. Al volver, las sanas vuelven al inventario, los heridos y averiados al
   taller y la munición al polvorín. **Sin desguace:** lo que no cabe en las
   plataformas queda en el parque.
3. Entregas de lanzacohetes a un sitio lleno: el sobrante queda en el parque
   (hoy se pierde).
4. Un campamento abandonado devuelve **toda** su guarnición, lanzacohetes
   incluidos.
5. **Un grupo que cae entero** (nada sano): sus **vehículos** (los averiados)
   vuelven al taller de su ciudad de origen (`g.origen`, o la capital si ya
   no es suya) remolcados: salen como un convoy de regreso que tarda lo que
   tarda un ejército y **no se puede atacar** (como hoy los grupos en
   retirada, que no chocan). Sus **soldados heridos mueren** (el vencedor no
   los recoge) y su munición se pierde.
6. **Instalación perdida:** sus vehículos vuelven igual, remolcados, al
   taller de la ciudad que la abastecía; sus soldados caen en la batalla que
   la perdió.
7. El recorte de hoy al 20 % de la población desaparece: el tope de soldados
   es F3 y F1b se comprueba al encargar.

### 3.9 Batalla: la misma cuenta en 3D y simulada

**Entrada.** Pelea exactamente lo sano de los grupos del bando (y la
guarnición del sitio que se defiende), con su munición. `estadoBatalla`
publica la lista por tipo (y por modelo cuando exista el armamento), con la
munición de cada grupo.

**Escena 3D.**

- **Vehículos 1:1.** Entran los primeros 40 por bando (`Tropas.maxPorBando`).
  Si hay más, el resto espera en **oleadas**: cada vez que uno queda fuera de
  combate o se retira, entra otro de la reserva por el borde de su lado. Todos
  pelean.
- **Infantería por escuadras** (F10): cada figura es una escuadra de `N`
  soldados. Una figura que cae son `N` soldados que caen.
- **Munición:** cada disparo descuenta del grupo de la unidad (F6); sin
  munición, la unidad no dispara (con un icono sobre ella).
- **Bajas del combate de verdad:** se quitan el tope y el ritmo visual de hoy
  (`tope`, `permitidas`).
- **Al terminar** (o al salir el jugador) se clasifica cada unidad (F11):
  - vehículo con toda la vida: operativo; con menos, **averiado** con un
    daño de 0 a 1 que decide cuánto cuesta y tarda repararlo;
  - escuadra: la vida perdida se reparte en soldados caídos; de ellos,
    `muertos` mueren (sorteado con la semilla de la batalla) y el resto queda
    herido.

**Salida.** La escena devuelve, por bando: soldados muertos y heridos,
vehículos averiados con su daño, y munición gastada por grupo.
`resolverBatalla` lo aplica 1:1. Si el jugador sale a mitad, se aplica lo
ocurrido y la batalla sigue simulada con lo que queda (como hoy).

**Simulada.** F8 de hoy (golpe × azar × ventaja), con dos cambios: el golpe
de cada tipo se multiplica por la parte que tiene munición (F6), y lo que cae
se reparte así: soldados, `muertos` mueren y el resto heridos; vehículos,
todos averiados con daño 1 (F11b). En la guarnición igual (hoy todo muere y
los vehículos caen al azar).

**Equivalencia.** La misma batalla jugada en 3D sin que el jugador intervenga
y resuelta simulada debe dar de media las mismas bajas, la misma munición
gastada y el mismo daño total (criterio 8.6). Si no, se ajustan `golpeMin` /
`golpeMax` y `fuego` (F6), no la escena.

### 3.10 Botín y saqueo

Sin cambios de regla: la capital nunca cambia de manos; si pierde su batalla,
queda a 9 de vida y el vencedor se lleva todo lo de afuera (el almacén y la
bóveda no se tocan). Tampoco se tocan la cola de fábrica, el taller ni el
polvorín. En una mina, el vencedor se lleva la carga que le quepa y el resto
vuelve a la mina. Las unidades no se capturan.

### 3.11 Reparación

Todo vehículo averiado entra en el taller de su ciudad al volver. El taller
repara `puntos` de daño al día por nivel (F12). Cuando un vehículo termina,
se paga su reparación (F12) y vuelve al inventario. Si no alcanza el metal o
el dinero, espera en el taller (no pierde lo reparado). Los soldados heridos
se recuperan como hoy (gratis y con tiempo; acelerar cuesta dinero).

### 3.12 NPC: las mismas órdenes

El presidente NPC decide cada día y llama a las mismas órdenes que el jugador
(`producir`, `abastecer`, `enviarDefensas` para colocar). Su política
(`planearProduccion(n)`, sustituye a la parte de reclutar de `economia` y a
`fabricarEnCiudad`):

1. **Munición primero:** quiere en el polvorín `reservaMunicion` días de
   batalla de todo su ejército sano (contando la que llevan sus grupos y la
   que está en fábrica), y encarga los lotes que pueda pagar hoy.
2. **Soldados y tanques:** quiere `parte` del tope, con `parte = 0,6 + 0,4 ×
   agresividad` en paz y 1 en guerra. Encarga lo que pueda pagar sin bajar
   de su reserva de dinero (`recuperacion.reservaTesoro`), de su reserva de
   metal y de lo que ahorra para mejoras (`n.plan`), como hoy.
3. **Abastece:** a cada grupo suyo en batalla con menos de `umbralAbasto`
   días de alguna munición le manda un convoy con `dotacion` días.
4. **Coloca** lanzacohetes y repara como hoy.

La nación del jugador no hace nada de esto sola.

### 3.13 Sin turnos

Solo limitan los recursos, el tiempo y el tope. Se encargan tantas órdenes
como se puedan pagar; la cola solo ordena qué termina antes.

---

## 4. Fórmulas

### F1. Costo de producir una unidad

| Tropa | Dinero | Metal | Petróleo | Civiles | Razón |
|---|---|---|---|---|---|
| Soldado | 1 | 0 | 0 | 1 | Hoy es gratis; 1 lo hace barato pero con costo. Los soldados mueren: reponerlos es un gasto constante |
| Tanque | 30 | 3 | 1 | 0 | `COSTES.tanques` de hoy. No se destruye: se paga una vez |
| Lanzacohetes | 40 | 6 | 2 | 0 | `defensasCiudad.coste` de hoy |

Ejemplo: 10 tanques = 300 de dinero, 30 de metal, 10 de petróleo. Con el
diseño de armamento, el costo del tanque es el de su modelo.

### F1b. Civiles mínimos

`soldadosMax = poblacion × (1 − minimoCiviles) − soldadosDeLaCiudad −
enInstruccion`, con `minimoCiviles = 0,8`. Ejemplo: población 9 000, 1 200
soldados, 100 en instrucción: 1 800 − 1 300 = 500 más. Se comprueba al
encargar; ya no se recorta a nadie.

### F2. Tiempo de fabricación de unidades

`dias(orden) = ceil(cantidad / tanda) × dias[tropa]`, una línea por orden,
`lineas = nivel` para soldados y otras `nivel` para vehículos (colas
separadas, decidido en `modo-base.md` F4).

| Tropa | Tanda | Días por tanda |
|---|---|---|
| Soldado | 50 | 2 |
| Tanque | 1 | 4 |
| Lanzacohetes | 1 | 6 |

Ejemplo: capital de nivel 3 (3 líneas), 5 tanques en una orden: 20 días; en
tres órdenes (2, 2 y 1): 8 días.

### F2b. Dinero del trabajo

`gana = trabajadores × 0,01 × (1 + 0,15 × tecnología) × hambre × f(vida) ×
0,6 × 0,65`, todo al tesoro, con `trabajadores = poblacion − soldados de la
ciudad − soldados fuera que salieron de ella − en instrucción`. El 0,6 es el
factor de presupuesto de hoy con la agresividad media (0,55) y sin guerra;
hoy la agresividad y la guerra suben lo que se gana (l.2256), lo que no
tiene sentido. **No medido:** el prototipo dejó la regla de hoy (medido: unos
116 de dinero al día por nación, contando todo).

### F3. Tope por nivel de la ciudad

| Nivel | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Soldados | 1 000 | 2 000 | 3 000 | 4 500 | 6 000 |
| Tanques | 8 | 20 | 35 | 55 | 80 |
| Lanzacohetes | plataformas de la ciudad (2 / 5 / 10 / 18 / 30) + 6 por base | | | | |

Razón: con el nivel 2 inicial, 2 000 soldados es la mediana de hoy el día
100 (1 910 – 2 526); el nivel 5 queda por debajo de lo que hoy se acumula sin
techo el día 500 (9 211 – 12 669 soldados, 125 – 142 tanques). Medido: las
naciones llegan al nivel 5 hacia el día 500 (mediana 5 en las 4 semillas).

### F4. Munición: lotes

| Munición | Lote | Dinero | Metal | Petróleo | Días |
|---|---|---|---|---|---|
| Balas | 10 000 | 1 | 0 | 0 | 1 |
| Obuses | 100 | 8 | 1 | 0 | 1 |
| Misiles | 10 | 12 | 1 | 1 | 1 |

Razón: el metal es el recurso escaso (hoy por debajo de 5 en el 5 – 7 % de
los días); las balas no piden metal para no dejar a la infantería sin
munición por culpa de los tanques. Un día de batalla de 1 000 soldados, 20
tanques y 10 lanzacohetes cuesta: balas 55 lotes (55), obuses 3,4 lotes
(27 + 3,4 de metal), misiles 7 lotes (84 + 7 + 7). Hoy un misil suelto
costaba 8 de dinero (`COSTES.misiles`); ahora 1,2.

### F5. Dotación de un grupo

`lleva[m] = unidades[tropa] × porDia[m] × dias`, con `dias = dotacion` (5 al
atacar, 2 al recolectar) y como mucho lo que haya en el polvorín. Ejemplo:
300 soldados y 10 tanques a atacar: 300 × 550 × 5 = 825 000 balas y 10 × 17
× 5 = 850 obuses.

### F6. Gasto y efecto de la munición

- **Escena 3D:** cada disparo gasta: ráfaga de una figura = 5 balas × `N` de
  su escuadra; disparo de tanque = 1 obús; lanzamiento = 1 misil.
- **Simulada:** `gasto[m] = unidades × porDia[m]` al día, con `porDia` =
  `disparos por segundo × 210 × fuego`, `fuego = 0,8` (la parte del combate
  que una unidad está disparando; **Elena debe medirla en la escena**):

| Unidad | Disparos por segundo en la escena | porDia |
|---|---|---|
| Soldado | 0,65 ráfagas (una cada 1,1 – 2,0 s, `recargaSoldado`) × 5 balas | 550 balas |
| Tanque | 0,1 (recarga 6 – 11 s + 3,5 s parado, `Tropas.recarga`, `Tropas.alto`) | 17 obuses |
| Lanzacohetes | 0,044 (ciclo de ~22,5 s: subir 3, fuego 0,5, recarga 13 – 20, bajar 2,5) | 7 misiles |

- **Golpe con munición a medias:** `f[tipo] = min(1, municion / (unidades ×
  porDia))`; el golpe del bando se multiplica por `Σ unidades × peso × f /
  Σ unidades × peso` (peso: soldado 1, tanque 9, lanzacohetes 40).

Ejemplo: 10 tanques con 85 obuses (la mitad de un día): su golpe es la mitad;
gastan los 85.

### F7. Sueldos

`sueldo = Σ unidades × sueldo[tropa]` al día, con soldado 0,01, tanque 0,15,
lanzacohetes 0,2 (heridos y averiados incluidos; en fábrica no). Ejemplo: 4
500 soldados, 55 tanques y 42 lanzacohetes: 45 + 8,25 + 8,4 = 61,65 al día.

### F8. Licencia por impago o hambre

`licenciados = floor(soldadosGuarnicion × 0,02 × faltante / debido + 0,5)`
al día; con hambre, `faltante / debido = 1`. Ejemplo: 2 000 soldados, se
deben 40 y faltan 10: 10 soldados vuelven a ser civiles. Nunca muere nadie
por esto.

### F9. Combustible

| Estado | Tanque | Lanzacohetes |
|---|---|---|
| Parado en un sitio o recolectando | 0,01 | 0,01 |
| En marcha o en batalla | 0,1 | 0,15 |

Ejemplo: 10 tanques y 10 lanzacohetes en un viaje de 5 días: 12,5 de
petróleo; los mismos en casa: 0,2 al día.

### F10. Escuadra

`N = max(1, ceil(soldadosDelBando / 48))`. Ejemplo: 469 soldados (mediana
medida con lo decidido) → escuadras de 10; 2 761 (p90) → de 58. Si Camila
sube el número de figuras, `48` pasa a ser ese número.

### F11. Clasificación al salir de la escena

- Vehículo: `dano = 1 − vida / vidaMax`. Con `dano = 0`, operativo; si no,
  averiado con ese daño.
- Escuadra: `caidos = round(N × (1 − vida / vidaMax))`; `muertos =
  round(caidos × muertos)` con el resto sorteado por
  `hash(semilla, batalla, figura)`; `heridos = caidos − muertos`.

Ejemplo: escuadra de 10 que termina a 0,3 de vida: caen 7; con `muertos =
0,4` salen 2,8 muertos: mueren 2 seguros y un tercero con probabilidad 0,8;
el resto de los 7 queda herido.

### F11b. Bajas simuladas

Lo que cae en un día (F8 de hoy): soldados, `round(caen × muertos)` mueren
(el resto de redondeo se guarda por grupo) y el resto van heridos; vehículos,
todos averiados con daño 1. `muertos = 0,4`.

Ejemplo: caen 50 soldados y 3 tanques: 20 muertos, 30 heridos, 3 tanques al
taller con daño 1.

### F12. Reparación

`puntos` al día del taller = `ritmo[tipo] × nivel` (tanque 0,5, lanzacohetes
0,4: los de hoy), en puntos de daño. Al terminar un vehículo se paga
`costo[tipo] × dano`: tanque 12 de dinero + 2 de metal; lanzacohetes 16 + 3.

Ejemplo: taller de nivel 3 (1,5 puntos de tanque al día) con 4 tanques a
daño 1 y 2 a daño 0,2: los dos leves salen el primer día (0,4 puntos) y
pagan 4,8 de dinero y 0,8 de metal; los otros cuatro, en unos 2 días más.
Razón: reparar un tanque destrozado cuesta el 40 % de su dinero y el 67 % de
su metal; como no se destruye, la reparación es su verdadero costo de
guerra.

**Por zona (versión 28):** para los vehículos, el cobro `costo[tipo] ×
dano` lo sustituye el coste de sus zonas (orugas, torreta, cañón, motor y
casco). Reglas, valores y medidas en `taller-por-zona.md`.

**Diferencia con el prototipo:** el prototipo midió todo daño como 1
(la simulada no da daños parciales) y el ritmo de hoy en unidades, no en
puntos.

---

## 5. Casos límite

- **Encargo por encima del tope:** se rechaza entero (`tope`). La interfaz
  puede ofrecer el máximo con `puedeProducir`.
- **Encargo que no se puede pagar:** se rechaza entero con el primer motivo.
- **Ciudad sitiada:** no acepta encargos de unidades (`sitiada`), su cola de
  unidades se congela; sí fabrica y entrega munición.
- **Capital vencida:** conserva cola, taller, polvorín e inventario que
  sobrevivió; pierde lo de afuera.
- **Grupo que se queda sin munición en marcha:** nada; solo importa en
  batalla.
- **Grupo sin munición en batalla:** recibe daño sin devolverlo; la IA NPC lo
  retira con su umbral de siempre (su vida baja) y además pide un convoy.
- **Convoy de munición que llega tarde:** si el grupo ya no existe, la
  munición vuelve al polvorín; si el grupo volvió a casa, también.
- **Grupo que cae con vehículos:** vuelven averiados, remolcados, a su ciudad
  de origen; si la nación ya no tiene esa ciudad, a la capital.
- **Taller lleno de vehículos sin dinero para repararlos:** esperan; cuentan
  en el tope y cobran sueldo. Es la trampa de perder muchas batallas.
- **Impago con la guarnición a 0:** los soldados fuera no se licencian; la
  nación sigue en impago y no acepta encargos.
- **Sin combustible con un grupo en marcha:** media velocidad; en batalla
  dispara sin avanzar.
- **La escena devuelve más bajas de las que había sanas:** se rechaza, como
  hoy, y la batalla sigue simulada.
- **Más de 40 vehículos y la escena se cierra a mitad:** los de la reserva
  que no llegaron a entrar vuelven operativos.
- **Nación que desaparece:** todo lo suyo desaparece con ella; es el único
  borrado fuera de combate.
- **Partida de la versión 20:** al cargar, `c.dinero` pasa al tesoro con
  `ingresar`, `c.fabrica = {}`, polvorín con `reservaMunicion` días de su
  ejército (arsenal inicial), los misiles de hoy (`c.misiles`) se quedan como
  munición de lanzacohetes, y los soldados por encima del tope se quedan
  (solo no se pueden encargar más).

## 6. Dependencias

**Este documento depende de:**

- `recoleccion-y-batallas.md`: fuentes, F8 de las batallas, botín en la
  mina, decisión 4.
- `territorio-y-capitales.md`: almacén, bóveda, afuera, merma, saqueo de la
  capital, niveles de ciudad.
- `retirada-y-recuperacion.md`: cola de recuperación (el taller), umbral de
  retirada, acelerar.
- `diseno-de-armamento.md`: el costo, el consumo y la vida de cada modelo
  sustituyen a las cifras fijas de F1, F9 y F11.
- `ejercitos-en-el-mapa.md`: poder de una unidad y de un grupo.
- `mundo/simulacion/exploracion.lua`: exploradores como gasto.

**Dependen de este documento** (cada uno lo nombra):

- `interfaz-militar.md`: Arsenal (producir, costos, tiempos, motivos),
  barra superior (un solo dinero), envío (munición que se lleva).
- `recoleccion-y-batallas.md` §3.7: la escena y la simulada devuelven
  muertos, heridos, averiados y munición gastada.
- `retirada-y-recuperacion.md` §3.6: el taller cobra la reparación.
- `instalaciones-y-economia.md`: su economía (fábrica, reclutamiento) queda
  sustituida por esta.
- `poblacion.md` (decidido el 2026-09-30, sin programar): sustituye F1b por los aptos de
  18 a 49 años, cambia los trabajadores de F2b (solo de 15 a 64) y añade
  `retirados` al invariante de §3.5.
- `diseno-de-armamento.md`: sus costos y consumos entran por F1 y F9.
- `catalogo-armamento.md` (propuesto el 2026-09-30): coste, días, sueldo,
  combustible, taller y munición por modelo real (sus F5 a F11) sustituyen a
  las cifras fijas de F1, F2, F7, F9 y F12; el tope por nivel no cambia.
- `README.md` del diseño: índice.

## 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `produccion.coste.soldados.dinero` | 1 | 0,5 – 3 | Más: reponer muertos cuesta más |
| `produccion.coste.tanques` | 30 / 3 / 1 | ±50 % | Como no se destruyen, solo frena llegar al tope |
| `produccion.dias` | 2 / 4 / 6 | 1 – 10 | Más: llegar al tope tras una mejora tarda más |
| `produccion.tanda.soldados` | 50 | 20 – 200 | Más: reclutar masivo es rápido |
| `tope` (F3) | tabla | ±30 % | Tamaño máximo de los ejércitos y de las batallas |
| `minimoCiviles` | 0,8 | 0,7 – 0,9 | Más bajo: más soldados posibles, menos trabajo |
| `municion.*.lote` / costo | F4 | ×0,5 – ×2 | Más caro: las guerras largas se pagan; menos golpe por falta de munición en pobres |
| `municion.*.porDia` | 550 / 17 / 7 | ×0,5 – ×1,5 | Más: batallas más caras y más convoyes |
| `fuego` | 0,8 | 0,5 – 1 | Iguala la simulada con la escena |
| `dotacion` | 5 / 2 días | 2 – 10 | Más: los grupos aguantan más sin convoy, pero vacían el polvorín |
| `reservaMunicion` (NPC) | 5 días | 2 – 10 | Más: NPC con más munición guardada, menos dinero libre |
| `umbralAbasto` (NPC) | 2 días | 1 – 3 | Más: convoyes antes |
| `muertos` | 0,4 | 0,2 – 0,6 | Más: cada batalla cuesta más reclutas |
| `reparacion` | 12+2 / 16+3 | 20 – 60 % del costo | Más: perder vehículos duele más (es su único costo de guerra) |
| `ritmo` del taller | 0,5 / 0,4 | 0,25 – 1 | Más bajo: tras una derrota, semanas sin blindados |
| `sueldo` | 0,01 / 0,15 / 0,2 | 0 – ×2 | 0: el dinero se acumula y se evapora afuera |
| `desercion` | 0,02 | 0,005 – 0,05 | Más: el impago se nota antes |
| `combustible` | 0,01 / 0,1 / 0,15 | 0 – 0,3 | Más en marcha: atacar lejos se paga |

## 8. Criterios de aceptación

Comprobables con `tools/auditar_economia_nationsrts.lua` (y los de la escena,
con el arnés de batalla de Elena). Los rangos salen de lo medido con el
prototipo (§9); se revisan con el código de verdad.

1. **Conservación:** el invariante de §3.5 se cumple todos los días en 500
   días y 4 semillas.
2. **Nada gratis ni borrado:** unidades nacidas fuera de `producir` = 0 (hoy
   502 soldados netos al día); soldados borrados por el recorte = 0 (hoy
   183,6); desguaces = 0; vehículos destruidos = 0.
3. **El dinero no se dispara ni se hunde:** mediana del tesoro por nación el
   día 500 entre 300 y 12 000 (prototipo: 490 – 10 632; hoy, dinero de
   ciudad: 25 287 – 39 559); días-nación con dinero por debajo de 10, menos
   del 6 % (prototipo: 1,7 – 5,4 %).
4. **Nadie colapsa:** todas las naciones vivas el día 500; hambre en menos
   del 1 % de los días-nación (prototipo: 0,0 – 0,1 %); licenciados por
   impago menos de 10 al día sumando todas las naciones (prototipo: 4,9).
5. **La munición cuenta pero no manda:** golpe perdido por falta de munición
   entre el 5 y el 20 % de media por bando-día (prototipo: 14,3 %).
6. **3D = simulada:** 50 batallas iguales (10 tanques, 10 lanzacohetes y 200
   soldados por bando) en 3D sin jugador y otras 50 simuladas: medias de
   muertos, heridos, daño total de vehículos y munición gastada de cada tipo
   a menos del 20 % entre sí. **Sin medir.**
7. **1:1 en la escena:** vehículos que pelean (con oleadas) = vehículos
   sanos del bando; muertos + heridos + sanos de la escena = soldados que
   entraron.
8. **Arsenal:** «Producir» activo, con costo y días de
   `Simulacion.produccion` y motivo de `puedeProducir`.

## 9. Cifras del prototipo (medido)

El prototipo monta lo decidido encima de la simulación real **sin tocar el
juego** (ver el comentario del script): un solo dinero, producción NPC
pagada con cola y tope por nivel, vehículos que nunca se destruyen (todo lo
que cae al taller, también de grupos caídos e instalaciones perdidas), 40 %
de muertos entre los soldados que caen, munición con dotación, gasto diario
y convoyes, reparación pagada, combustible por actividad, sin desguaces ni
recorte al 20 %. Se midió **con sueldos** (lo que este documento propone) y
**sin sueldos**. No monta: el jugador (el arnés no tiene), F2b, la
reparación por puntos de daño, la media velocidad sin combustible, la
escena 3D.

500 días, 4 semillas; por nación, mediana del día 500 (rango de semillas):

| Qué | Con sueldos | Sin sueldos | Hoy |
|---|---|---|---|
| Tesoro (todo el dinero) | 490 – 10 632 | 7 290 – 12 364 | 776 – 4 109 (+ 25 287 – 39 559 en la ciudad) |
| Metal | 158 – 232 | 166 – 208 | 63 – 109 |
| Petróleo | 136 – 187 | 170 – 212 | 181 – 191 |
| Soldados | 4 532 – 6 000 | 4 500 – 6 000 | 9 211 – 12 669 |
| Tanques | 64 – 80 | 80 | 125 – 142 |
| Lanzacohetes | 42 | 42 | 42 |
| Nivel de la capital | 5 | 5 | 5 |

| Días-nación con… | Con sueldos | Sin sueldos | Hoy |
|---|---|---|---|
| Dinero < 10 | 1,7 – 5,4 % | 0,7 – 1,2 % | 0,3 – 0,4 % |
| Dinero afuera (bóveda llena) | 1,1 – 30,0 % | 22,2 – 52,1 % | 0,0 – 6,1 % |
| Metal < 5 | 4,3 – 6,9 % | 5,2 – 7,4 % | 5,4 – 7,0 % |
| Petróleo < 5 | 3,3 – 3,7 % | 3,5 – 4,1 % | 2,0 – 2,2 % |
| Sin combustible | 0,7 – 1,1 % | 0,9 – 1,5 % | 0,1 – 0,2 % |
| Hambre | 0,0 – 0,1 % | 0,0 – 0,2 % | 0,0 – 0,1 % |
| En el tope (soldados o tanques) | 50,9 % | 64,2 % | — |

Todas las naciones vivas en las 4 semillas, en los tres casos.

**Dinero por nación y día, con sueldos** (suma de todas las naciones entre
21,25 naciones de media por semilla):

| Entra | | Sale | |
|---|---|---|---|
| Trabajo e impuestos | 115,6 | Sueldos | 44,0 |
| Oro | 12,7 | Producir unidades | 16,4 |
| | | Mantenimiento de campamentos y banderas | 14,4 |
| | | Munición | 11,7 |
| | | Merma de lo de afuera | 11,5 |
| | | Obras (expansión) | 8,5 |
| | | Lanzacohetes de defensa | 5,4 |
| | | Reparar y acelerar | 2,7 |
| | | Exploradores | 1,4 |
| **Total** | **128,3** | **Total** | **≈ 116** (sobran ≈ 12) |

Sin sueldos la merma sube a 33,4 al día por nación: el dinero que no se usa
se evapora. Por eso los sueldos se quedan (§3.7).

**Metal y petróleo por nación y día, con sueldos:** entran 7,6 de metal
(recolección 7,3 + talleres 0,3) y 7,2 de petróleo. El metal va a mejoras
1,9, expansión 1,8, reparación de instalaciones 1,5, defensas 0,8, munición
0,6, tanques 0,4 y reparación de vehículos 0,1; el petróleo, a campamentos
4,0, combustible 1,1, mejoras 0,8, munición 0,4 y tanques 0,1.

**Unidades y munición al día, sumando todas las naciones (media por
semilla), con sueldos:**

| Qué | Con sueldos | Hoy |
|---|---|---|
| Soldados producidos (pagados) | 246,5 | 502 netos, gratis |
| Tanques producidos | 2,91 | 5,52 |
| Soldados que caen en combate | 89,3 | 51,2 |
| Soldados muertos | 37,5 | ≈ 12 (guarnición) + 1,7 (grupos caídos) |
| Soldados borrados por el recorte al 20 % | 0 | 183,6 |
| Tanques que caen (al taller) | 0,94 | 0,73 |
| Tanques destruidos | 0 | ≈ 0,06 |
| Tanques reparados | 0,84 | 0,65 |
| Balas gastadas / hechas | 574 849 / 1 123 275 | — |
| Obuses gastados / hechos | 233,7 / 476,4 | — |
| Misiles gastados / hechos | 26,0 / 80,8 | — |
| Golpe perdido por falta de munición | 14,3 % por bando-día | — |
| Convoyes de munición | 0,12 | — |

**Tamaño de los bandos al empezar cada batalla:**

| | Con sueldos (974 batallas) | Hoy (1 658) |
|---|---|---|
| Vehículos: mediana / p90 / máximo | 7 / 45 / 93 | 2 / 15 / 82 |
| Bandos con más de 40 vehículos (oleadas) | 113 (11,6 %) | 17 (1,0 %) |
| Soldados: mediana / p90 / máximo | 469 / 2 761 / 5 501 | 108 / 832 / 4 079 |
| Escuadra (F10) en la mediana / p90 / máximo | 10 / 58 / 115 | 3 / 18 / 85 |

Lectura: con lo decidido el dinero circula y queda acotado por la bóveda, el
ejército crece hasta el tope de su nivel y se para, los tanques se acumulan
porque no se destruyen (el taller es su costo) y la munición quita de media
un 14 % del golpe: pesa sin decidirlo todo. Hay menos batallas y más grandes
que hoy (no sé aún por qué; falta medirlo aparte). Con el p90 de soldados,
una figura son 58 soldados: si parece poco fiel, Camila puede subir las 48
figuras.

**Cómo se llegó a los valores.** Primero, con la munición pagando metal por
las balas y sin convoyes, el 68,7 % del golpe se perdía por falta de
munición y había hambre (el metal no alcanzaba para huertos). Se quitó el
metal de las balas, se subió la dotación de 3 a 5 días, la munición se
fabrica también en asedio y la NPC manda convoyes con menos de 2 días: el
golpe perdido bajó al 14,3 %.

## 10. Cambios necesarios en el código

Para Andrés (simulación):

- **`mundo/simulacion.lua`**
  1. `Simulacion.produccion` pública: `coste`, `dias`, `tanda`,
     `minimoCiviles`, `tope`, `municion` (lote, costo, días, `porDia`),
     `fuego`, `dotacion`, `reservaMunicion`, `umbralAbasto`, `muertos`,
     `reparacion`, `sueldo`, `desercion`, `combustible`, `devolucion`.
     Sustituye al `COSTES` local (l.115) para las tres tropas y a
     `defensasCiudad.coste.lanzacohetes` (l.232).
  2. Órdenes nuevas en `ejecutar` (l.1200): `producir` (unidades o
     munición), `cancelarProduccion`, `abastecer`. Consulta sin efectos
     `puedeProducir(nid, cid, tropa, cantidad)` → `true, costo, dias` o
     `false, motivo`. Colas `c.fabrica` y `c.fabricaMunicion`, polvorín
     `c.balas`, `c.obuses`, `c.misiles`.
  3. Un solo dinero: quitar `c.dinero`; en `economia` lo ganado va al tesoro
     con `ingresar` (l.2290-2296). Lo que hoy paga la ciudad (`enviarDefensas`
     l.1390, `acelerarRecuperacion` l.3382, `mercadoComida`) paga la nación.
     F2b.
  4. Quitar el reclutamiento gratis y el recorte al 20 % (l.2259-2265), los
     soldados regalados a las bases (l.2370) y la fabricación automática de
     tanques (l.2414). `fabricarEnCiudad` pasa a ser `planearProduccion(n)`
     (§3.12), solo para NPC, por `ejecutar`.
  5. Tope por nivel (F3) comprobado en `producir`.
  6. Munición en la batalla: en `diaBatalla` (l.4255) el golpe de cada bando
     por F6 y el gasto diario; dotación en `enviarGrupo` (l.1659) y
     `recolectar`; vuelta al polvorín en `llegada` (l.3511).
  7. Bajas: soldados con F11b en `herirGrupo` (l.3248), `quitarTropa`
     (l.4399) y `danarSitio` (l.4194, sin las probabilidades de l.4200 y
     l.4203); vehículos siempre al taller.
  8. `caerEnBatalla` (l.4149): vehículos remolcados al taller de origen
     (grupo `regreso` sin choque); soldados heridos muertos; munición
     perdida. `destruirInstalacion`: vehículos remolcados.
  9. `resolverBatalla` (l.4455) acepta muertos, heridos, averiados con daño
     y munición gastada.
  10. Taller por puntos de daño y cobro de F12 en `recuperar` (l.3444).
  11. Sin desguaces: `recibirHeridos` (l.3332), entrega (l.3573),
      `retirarGuarnicion` (l.2158, con los lanzacohetes), `volver` sin casa
      (l.3228).
  12. Sueldos F7 y licencia F8 (también con hambre, l.2225).
  13. `gastoCombustible` (l.1890) con F9; media velocidad sin combustible.
  14. Guardado versión 21 con migración desde la 20 (§5, último caso).
- **`mundo/simulacion/consultas.lua`**: `estadoBatalla` con lo sano por tipo
  y la munición de cada grupo; `colaFabrica(cid)`; `polvorin(cid)`.
- **`mundo/simulacion/recoleccionIA.lua`**: `libresEn` y la IA de ataque
  cuentan la munición (no mandar grupos sin dotación).
- **`mundo/simulacion/guardado.lua`**: versión 21.

Para Valeria y Camila (escena y vista):

- **`mundo/choques.lua`**: `deBatalla` (l.133) con cantidades exactas,
  munición y tamaño de escuadra; `bajasDeEscena` (l.164) devuelve muertos,
  heridos, averiados con daño y munición gastada, sin proporción.
- **`batalla/tropas.lua`**: quitar `tope` y `permitidas` (l.134-135,
  l.692-714); oleadas por encima de `maxPorBando` (l.33); escuadras
  (`maxSoldadosPorBando`, l.34); vida desde la simulación; disparo que
  descuenta munición y no dispara sin ella (con icono); clasificación F11.
- **`main.lua`**: `salirDeBatalla` (l.1936) manda el resultado nuevo.
- **`interfaz/arsenal.lua`**: activar «Producir» con `Simulacion.produccion`,
  `sim:puedeProducir` (motivo en el aviso, l.581) y `sim:colaFabrica`;
  pestaña de munición.
- **`interfaz/envio.lua`**: cuánta munición se lleva el grupo; aviso «sin
  munición» en la ficha.
- **`interfaz/barrasuperior.lua`** (l.302): el dinero ya es uno solo (no
  cambia lo que muestra: el tesoro).

Para Elena: invariante de conservación (8.1) como prueba diaria, `fuego` y
la equivalencia 3D / simulada (8.6).

## 11. Decisiones del dueño (2026-09-30)

Sustituyen a las preguntas de la primera versión.

1. **Producción solo manual.** El jugador produce desde el Arsenal; los NPC
   usan la misma orden `producir`. Nada se fabrica solo.
2. **Infantería en 3D por escuadras** (cada figura, N soldados); vehículos
   1:1.
3. **Más de 40 vehículos: oleadas.**
4. **Un solo dinero:** el tesoro de la nación.
5. **Los vehículos nunca se destruyen:** solo se averían (operativo / en el
   taller) y se reparan al terminar la batalla pagando metal y dinero, con un
   tiempo según el daño. Si un grupo cae entero, sus vehículos vuelven
   averiados al taller: propuesta de §3.8.5 (remolcados a la ciudad de
   origen, sin poder ser atacados).
6. **Los soldados sí mueren** en combate; una parte queda herida y se
   recupera. Se reponen reclutando.
7. **Tope de ejército por ciudad según su nivel.** Los sueldos no son el
   límite. Lucía propone **mantenerlos como gasto** (§3.7, medido en §9).
8. **Lo que se fabrica y se gasta es la munición**, sin tope de fabricación:
   balas, obuses y misiles; va con el ejército, se gasta disparando al mismo
   ritmo en 3D y en simulada, y sin ella la unidad deja de disparar (sigue en
   el campo, con aviso).
9. **Los soldados comen como hoy.**

**Preguntas que quedan abiertas** (el dueño elige):

- **Convoyes de munición del jugador.**
  - A. **Recomendada:** a mano, con la orden `abastecer` desde la ficha del
    ejército, y un aviso cuando un grupo en batalla baje de 2 días.
  - B. Automáticos, con la regla del NPC (§3.12.3).
- **Soldados heridos de un grupo que cae entero.**
  - A. **Recomendada:** mueren (§3.8.5): retirarse a tiempo vale la pena.
  - B. Vuelven con los vehículos remolcados.
- **Lo que cuesta en munición un día de batalla** (F4). Con los valores de
  ahora, 1 000 soldados, 20 tanques y 10 lanzacohetes gastan unos 166 de
  dinero y 10 de metal al día.
  - A. **Recomendada:** dejarlo así (medido: la munición es el 10 % del gasto
    y quita el 14 % del golpe).
  - B. Más barata, para que la guerra larga no empobrezca.
  - C. Más cara, para que la guerra larga se note mucho.

---

## Cómo se midió

- Script: `tools/medir_economia_nationsrts.lua` (LuaJIT, sin LÖVE; retirado
  el 2026-09-30, en el historial en 9b1c5b2). Crea el
  mundo con `depurar/mundo_prueba.lua` (5 × 5 zonas) y corre `avanzarDia` de
  la simulación real, en HEAD c65851a.
- `hoy`: envuelve las fases del día y funciones interiores y anota la
  diferencia de recursos y unidades antes y después de cada una. No cambia
  ninguna regla.
- `decidido` y `decidido-sueldos`: montan además lo decidido (D1 a D7 en el
  script) sustituyendo, solo dentro del proceso del script, `economia`,
  `fabricarEnCiudad`, `mercadoComida`, `gastoCombustible`, `enviarGrupo`,
  `recolectar`, `llegada`, `caerEnBatalla`, `destruirInstalacion`,
  `retirarGuarnicion`, `ventajaBando`, `diaBatalla`, `danarSitio`,
  `recuperar` y `recibirHeridos`.
- Órdenes: `luajit tools/medir_economia_nationsrts.lua <modo> 500 1 7 42
  1234`.
- El recorte al 20 % se midió aparte: la bajada de `c.soldados` dentro de
  `economia` en ciudades sin hambre (es un mínimo: el mismo día puede
  reclutar y recortar).
- «Por nación y día» divide la suma de todas las naciones entre 21,25.
- Las cifras de «hoy» de esta versión son de HEAD c65851a (con
  exploradores); las de la primera versión (b0179cb) eran de antes y no se
  mezclan.
- Falta medir: F2b, la reparación por puntos, la media velocidad sin
  combustible, `fuego` en la escena, la equivalencia 3D / simulada y por qué
  hay menos batallas y más grandes.

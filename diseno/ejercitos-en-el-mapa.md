# Ejércitos en el mapa (estilo Bannerlord)

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

> **Estado: PROPUESTO.** No hay nada programado. El dueño lo decidió el
> 2026-09-26: «ya no caminarán los tanques ni nada por el mapa, tiene que ser
> como en Bannerlord, que caminas en un caballo por el mapa… una silueta que
> nada más muestra por dónde vas, con el icono del presidente o su bandera…
> el presidente lleva un total de poder… si hacemos clic encima se ve el poder
> que lleva; si el del otro es más, entonces ataca… antes de salir de su
> ciudad elige qué llevar; cada cosa suma números de poder, por ejemplo 10
> tanques pueden ser 500 de poder… ya en el campo de batalla se colocan todo lo
> que lleva y comienza la pelea».
>
> **Decisiones del dueño ya tomadas (2026-09-26):**
> 1. Ficha en el mapa: un **estandarte** colgante con el color y el escudo de
>    la nación, y debajo el nombre del líder y su poder. Una ficha por
>    ejército. Nada de tanques, camiones ni modelos 3D en el mapa.
> 2. Líderes: **el presidente y generales**, con nombre y carácter. Una nación
>    puede tener varios ejércitos a la vez.
> 3. El ejército **se arma en la ciudad antes de salir** con lo que la ciudad
>    tiene. No aparece nada de la nada y la ciudad queda más débil.
> 4. **Poder = suma del valor de cada unidad según su diseño.** Al hacer clic
>    se ve el poder; la composición, solo si tus exploradores la vieron.
> 5. Encuentros: los NPC comparan poderes según su carácter; si pelea el
>    jugador se abre la batalla 3D con exactamente lo que lleva cada uno; entre
>    NPC resuelve la simulación; el mando del jugador cambia el resultado; el
>    mundo sigue, más lento, mientras el jugador pelea.
> 6. Se mantienen la retirada y la recuperación en la ciudad
>    (`retirada-y-recuperacion.md`).
>
> **Decisiones del dueño sobre las preguntas de este documento
> (2026-09-26)**, ya metidas en el texto:
> 7. **Soldados:** su poder queda como hoy (soldado 5,5; 10 tanques 495) en
>    las fases 1 y 2. Si se baja, se decide con números cuando haya choques de
>    ejércitos medidos (3.4).
> 8. **Presidente:** sale al campo, pero **nunca muere**. Si pierde, queda
>    preso y vuelve con la paz o con un rescate (3.2).
> 9. **Batalla en línea:** en la fase 3 la resuelve la máquina del jugador y el
>    servidor comprueba los límites. La meta en línea es que la calcule el
>    servidor con las órdenes del jugador como comandos (3.7).
> 10. **Agua:** solo frena, nunca corta el paso (3.5, F4).
>
> **Nota:** la escena de batalla sí puede usar librerías externas de Lua o
> LÖVE (`GUIA-3D.md`, sección 5). Solo van fuera de la simulación:
> `mundo/simulacion.lua` no depende de ninguna.
>
> Fuentes: `mundo/simulacion.lua` (versión 13 del estado, HEAD e3076fc),
> `batalla/escena.lua`, `VISION.md`, `diseno-de-armamento.md`, `guerra.md` y
> `retirada-y-recuperacion.md`. Las cifras «medidas» salen de un arnés sin
> ventana (ver «Cómo se midió»). Lo que no está medido lo dice.

---

## 1. Resumen

Cada fuerza que se mueve por el mapa es un **ejército**: una ficha con forma
de estandarte que lleva un **líder** (el presidente o un general con nombre y
carácter) y un **poder**, la suma del valor de cada unidad que lleva según su
diseño. El ejército se forma en una ciudad propia con lo que esa ciudad tiene
de verdad (soldados, tanques, lanzacohetes y, más adelante, aviones e
interceptores), gasta petróleo por el camino y anda en línea recta, más lento
por el agua y el monte. Cuando dos ejércitos enemigos se cruzan, los NPC
comparan poderes y deciden, según su carácter, si atacan, esperan o huyen. Si
pelean dos NPC, la simulación resuelve el combate día a día con las reglas de
hoy (bajas según el golpe, retirada por umbral). Si pelea un jugador, se abre la
batalla 3D con las unidades exactas de los dos bandos y su resultado vuelve a la
simulación como un comando. El mapa deja de dibujar vehículos, camiones y
disparos: todo eso pasa a la batalla 3D.

## 2. Fantasía del jugador

- **Mirar el mapa y leer la guerra de un vistazo**: estandartes de colores
  avanzando, cada uno con un nombre («Gral. Mira Oriel · 2 140») que ya
  significa algo porque lo has visto antes.
- **Decidir antes de salir**: vaciar la capital para un golpe fuerte o dejarla
  guardada y salir con poco. Lo que te llevas no defiende casa.
- **La tensión del encuentro**: ver acercarse un estandarte enemigo, hacer clic,
  leer su poder y decidir: plantar cara, esquivar o pedir ayuda a otro
  ejército propio.
- **Que tu mando cuente**: en la batalla 3D una buena posición gana contra un
  poder algo mayor.
- **Rivales con cara**: el general enemigo que te ganó dos veces, el que huye
  siempre, el que capturaste y soltaste en la paz.

## 3. Reglas

### 3.1 La ficha en el mapa

1. Cada ejército en el mapa se dibuja como **una sola ficha**: un estandarte
   colgante (asta y paño) con el color de su nación (`Simulacion.colorNacion`)
   y su escudo. Debajo, una etiqueta con el **nombre del líder** y el
   **poder** redondeado (ver 3.4).
2. La ficha mira hacia donde va (el paño ondea hacia atrás) y se desplaza
   interpolando entre el día anterior y el actual, como hoy
   `Simulacion.posicionGrupo`.
3. Estados que se leen en la ficha (sin texto extra):
   - **en marcha**: paño ondeando;
   - **combatiendo o asediando**: dos espadas cruzadas encima;
   - **en retirada**: estandarte inclinado y más pálido;
   - **sin petróleo**: icono de bidón vacío;
   - **ejército unido** (fase 4): estandarte mayor con los escudos de los que
     lo forman.
4. Los **convoyes** que no son ejércitos (misión `construir`, `entrega`) se
   dibujan como un **banderín pequeño sin líder** y sin poder.
5. **Qué se ve al hacer clic**, según lo que sabe tu nación:

   | Lo que se ve | Propio o aliado | Enemigo a la vista | Enemigo visto por un explorador (últimos `diasInforme` días) |
   |---|---|---|---|
   | Nación, escudo, líder y carácter a grandes rasgos («prudente», «agresivo») | sí | sí | sí |
   | Poder total | exacto | exacto | exacto |
   | Composición (cuántos de cada tipo) | exacta | no («desconocida») | la del informe, con su fecha |
   | Modelos (diseños) | sí | no | solo los que el explorador identificó (`diseno-de-armamento.md` §3.8) |
   | Petróleo que lleva, heridos, umbral de retirada | sí | no | no |
   | Destino | sí | no | no |

   *A la vista* significa: dentro de `radioVista` de un sitio o ejército
   propio. Fuera de eso, el ejército enemigo **no se dibuja** (niebla de
   guerra). Mientras no haya exploradores (fase 4), no hay composición
   enemiga en ningún caso.
6. El poder es **público** para quien ve la ficha, NPC o jugador por igual:
   los NPC deciden con el mismo dato que ve el jugador.

### 3.2 Líderes

**Quiénes.** Cada nación tiene su **presidente** (el `gobernante` de hoy) y
**generales**. Solo un líder puede mandar un ejército que sale a combatir
(misiones `atacar`, `refuerzo`, `patrulla`). Un líder manda como mucho un
ejército a la vez.

**Cuántos generales, sin cupo fijo.** Nombrar un general es una acción
(`nombrarGeneral`) con coste en dinero (`costeGeneral`) y un **sueldo
diario** (`sueldoGeneral`). No hay tope: los frena el tesoro y, sobre todo,
que cada ejército necesita tropas reales para salir (3.3). El NPC nombra uno
nuevo cuando se cumplen las tres cosas:

- no tiene ningún líder libre (todos mandan un ejército o están presos);
- alguna ciudad suya podría formar un ejército de al menos `poderMinimoSalida`
  sin bajar de su guarnición mínima (3.3);
- su tesoro cubre `costeGeneral + 30 × sueldoGeneral` por encima de su
  reserva de tesoro.

Si deja de poder pagar el sueldo, el general menos veterano se **licencia**
(desaparece; si estaba en campaña, lo sustituye el siguiente líder libre o el
ejército vuelve a casa al terminar el combate del día).

**Nombre y carácter.** Nombre y apellido salen de las listas de hoy
(`NOMBRES`, `APELLIDOS`) con `Ruido.hash(semilla, nación, contador de
líderes)`; se añaden listas por orden político para que suenen distinto
(ficticias). Rango según veteranía: Coronel (0-2 victorias), General (3-7),
Mariscal (8 o más). Carácter:

- `agresividad` y `prudencia`, de 0,1 a 1, como el presidente;
- los generales **heredan un poco del presidente que los nombra**:
  `valor = 0,5 × presidente + 0,5 × azar(0,1; 1)`, para que cada nación tenga
  un estilo;
- `victorias` y `derrotas` (cuentan para el rango y la ficha).

**Si un líder cae o lo capturan.** Solo puede pasarle cuando su ejército es
**aniquilado** (hoy: `g.soldados <= 0` en `combatir` o `combatirCiudad`) o
cuando el ejército pierde un combate sin poder retirarse (sin petróleo y
alcanzado). Si se retira, el líder vuelve con él, sano.

- Un **general**, con probabilidad `pCaptura` (azar de `Ruido.hash`), queda
  **preso** del vencedor; si no, **muere**.
- **El presidente nunca muere** (decisión del dueño): si cae su ejército,
  queda **siempre preso**.
- **Preso**: no manda nada. Sale libre (a) al firmar la paz o un alto el fuego
  (se canjean todos los presos), (b) si su nación paga un rescate
  (`pagarRescate`, `rescate × rango`) y el captor lo acepta (el NPC acepta si
  su relación no es de guerra total o si le falta dinero), o (c) se fuga con
  probabilidad `pFuga` al día.
- **Muere un general**: se pierde; la nación puede nombrar otro.
- **Presidente preso**: gobierna un **regente** con el mismo carácter hasta
  que vuelva (paz, alto el fuego o rescate; también puede fugarse con
  `pFuga`). La nación suma `cansancio + capturaPresidente` una vez. Las
  decisiones de gobierno siguen igual; el presidente no puede mandar
  ejércitos mientras está preso. No hay sucesión por muerte.

### 3.3 Armar un ejército

Comando nuevo, igual para NPC y jugador:

```
ejecutar({ tipo = 'formarEjercito', nacion, lider, desde, mision, objetivo,
           llevar = { soldados, tanquesPor = { [modelo] = n }, lanzacohetes,
                      aviones, interceptores },
           petroleo, retirada })
```

1. `desde` es una **ciudad** propia (las bases también pueden, con lo que
   tengan: son sitios militares; hoy `enviarGrupo` ya sale de bases).
2. Solo se lleva lo que **hay** en ese sitio y está sano (no lo que está en la
   cola de recuperación ni en camino). Se resta del sitio en el momento.
3. Qué se puede llevar:
   - soldados (van en camiones, que no son unidad aparte);
   - tanques, por modelo;
   - lanzacohetes (los fijos de la ciudad; se llevan hasta
     `parteLanzacohetes` como hoy en el NPC, cualquier cantidad el jugador);
   - aviones e interceptores (**fase 4**): mientras tanto siguen en su sitio y
     actúan como hoy en salvas e incursiones.
4. Mínimo para salir: 10 soldados o 1 vehículo (hoy exige 10 soldados; un
   ejército solo de tanques debe poder salir).
5. **Coste de salir**: el petróleo que se carga (`petroleo`), del almacén de la
   nación. El NPC carga `petroleoIda × 2 × margenPetroleo` (ida y vuelta, ver
   F5); el jugador elige. No hay otro coste: el tiempo de marcha y lo que deja
   de defender la ciudad ya son el precio.
6. **Lo que queda defendiendo.** Lo que no sale se queda y defiende la ciudad
   con las reglas de hoy (`combatirCiudad`, baterías, interceptores). El NPC
   deja una **guarnición mínima** de su poder de ciudad:
   `reserva = 0,2 + 0,4 × prudencia` (0,24–0,6), y `+ 0,15` si la ciudad está
   en la frontera (`enFrontera`). El jugador no tiene mínimo: si vacía la
   capital, es su riesgo.
7. Desaparece la regla de hoy «un solo grupo de ataque por nación a la vez»
   (`grupoEnCamino(self, nid, 'atacar')` en `ofensiva`), porque es un tope
   artificial: una nación saca tantos ejércitos como líderes y tropas tenga.

### 3.4 Poder

1. Cada unidad vale `poder = escalaPoder × (vida + golpe) / 2` (F1). Con las
   cifras de hoy (vida = golpe = `FUERZA`), un soldado vale 5,5, un tanque de
   referencia 49,5, un lanzacohetes 220 y un avión 82,5.
2. El poder de un ejército es la **suma** de sus unidades **sanas**
   (los heridos no cuentan), redondeada al entero al mostrarla.
3. **No cambia el equilibrio**: con las reglas de hoy, `poder = 5,5 ×
   vidaGrupo` exactamente, una escala fija de lo que ya decide el combate.
   Comparar poderes es comparar lo mismo que pelea. Cuando entre el diseño de
   armamento (golpe y vida por modelo), el poder sigue siendo la media de las
   dos, así que un modelo de mucha vida y poco golpe vale igual que uno al
   revés con la misma suma.
   **Decidido por el dueño:** el soldado vale como hoy (5,5) en las fases 1 y
   2, aunque los soldados sean el 83–91 % del poder (sección 10). Si se baja
   su peso, se decide con números cuando haya choques de ejércitos medidos.
4. `Simulacion:fuerza(nid)` (la fuerza de la nación para declarar guerras y
   negociar) **no se toca**: sigue sumando `FUERZA` en ciudades, bases y
   grupos. Si más adelante se quiere mostrar en «poder», es `5,5 ×` lo mismo.

### 3.5 Movimiento

1. Sin rutas: cada día el ejército avanza en línea recta hacia su destino
   actual (un sitio, un punto o **otro ejército**, que puede moverse).
2. **Velocidad por la unidad más lenta** (F3): `velocidadEjercito` (9 000
   px/día) × el factor del modelo más lento que lleve; los soldados solos, a
   9 000.
3. **Agua y terreno, barato** (F4): el paso del día se parte en tramos de
   `pasoMuestreo` px; en cada tramo se mira la altura del terreno (una llamada
   a la altura del mundo físico, que no se guarda) y el tramo cuesta más si es
   agua o monte. **Nada es infranqueable** (decidido por el dueño: el agua solo
   frena, nunca corta el paso): se vadea o se tienden pontones, pero
   despacio. Motivo medido: la línea recta entre un sitio y su objetivo pasa
   por agua en el 85–100 % de los ataques y un 30–33 % de su largo es agua
   (sección 10): si el agua cortara el paso, casi ningún ataque llegaría.
4. **Petróleo por el camino**: cada día, el ejército gasta de lo que carga el
   consumo de sus vehículos (el de hoy, `petroleoTanque` 0,03 y
   `petroleoAvion` 0,1, o el del modelo) × `factorMarcha` si se movió ese día,
   × 1 si estuvo parado o combatiendo. **Deja de contar en el gasto de la
   nación** (`gastoCombustible`) mientras está fuera: lo paga lo cargado.
5. **Sin petróleo**: los vehículos se arrastran. El ejército va a
   `velocidadSinPetroleo` y sus tanques, lanzacohetes y aviones pelean con
   `golpeSinPetroleo` de su golpe. El NPC da la vuelta a casa en cuanto le
   queda petróleo para menos de la vuelta. Si llega a una ciudad o base
   propia, recarga de ahí (almacén de la nación).
6. Al llegar a casa, el petróleo sobrante vuelve al almacén.

### 3.6 Decisiones de los NPC

Todas salen por `Simulacion:ejecutar`. Cada día, en el orden fijo de las
naciones y de los ejércitos (`ordenadas`):

1. **Cuándo sale un ejército.** En un día de tensión de una guerra
   (`Simulacion:guerra`, como hoy `ofensiva` con su tirada de 0,35), por cada
   líder libre, si alguna ciudad o base puede formar un ejército de al menos
   `poderMinimoSalida` dejando su guarnición mínima. También sale uno de
   **refuerzo** cuando una instalación propia es atacada (hoy `refuerzos`), y
   uno de **intercepción** cuando un ejército enemigo entra en `radioVista` de
   una ciudad propia y la regla de ataque (punto 3) lo aprueba.
2. **A qué objetivo va.** El de hoy (`objetivo`: instalación enemiga más
   cercana ponderada por lo que le falta, o una ciudad según su nivel), con dos
   cambios: (a) se descartan objetivos cuyo poder defensor conocido supere
   `poder propio × umbralAtaque`, y (b) dos ejércitos de la misma nación no
   van al mismo objetivo salvo que uno solo no alcance.
3. **Cuándo ataca.** Cuando ve (dentro de `radioVista`) un ejército enemigo,
   calcula `r = poderPropio / poderEnemigo` (F6). Si `r ≥ umbralAtaque`,
   cambia su destino a ese ejército (lo **persigue**).
4. **Cuándo huye.** Si `r < umbralHuida` y el enemigo va hacia él (su destino
   es él o la distancia bajó desde ayer), da media vuelta hacia su sitio propio
   más cercano. Entre los dos umbrales, sigue su misión; si le alcanzan, se
   defiende.
5. **Persecución.** Sigue al enemigo mientras lo vea y no pasen
   `diasPersecucion` días; si el perseguido es más rápido, desiste antes (el
   día que la distancia no baja).
6. **Unirse a un ejército aliado (fase 4).** Si un ejército propio o de un
   aliado está a menos de un día de marcha y juntos pasan `umbralAtaque` contra
   un enemigo que ninguno podría atacar solo, el de líder de menor rango se une
   al otro (comando `unirEjercito`): sus unidades pasan al mayor y su líder
   queda como segundo (vuelve a mandar si se separan).
7. **Retirada en combate**: la de hoy (`debeRetirarse`, umbral según
   prudencia **del líder**, no del presidente).

### 3.7 Encuentros y resolución

**Detección.** Tras mover todos los ejércitos del día, para cada par de
ejércitos de naciones en guerra (fase `tension`; en alto el fuego se ignoran)
se calcula la distancia mínima entre sus dos trayectos del día (los dos se
mueven a la vez, F7). Si baja de `radioEncuentro`, hay **choque** si al
menos uno de los dos quiere atacar (3.6.3) o si uno de ellos no puede huir
(sin petróleo o más lento que su perseguidor). Si los dos quieren evitarse,
cada uno sigue. Los convoyes enemigos (banderín) alcanzados por un ejército
se capturan o destruyen sin combate si no llevan escolta.

**Resolución NPC contra NPC (determinista).** Los dos quedan **trabados** en
el punto del choque. Cada día, mientras sigan trabados:

1. Bajas que causa cada bando al otro (F8):
   `floor(golpe × azar(0,06; 0,12) × ventaja)`, repartidas con
   `herirGrupo` (la regla de hoy: lanzacohetes, tanques y soldados según su
   peso; lo que cae queda herido y viaja con el ejército).
2. `ventaja` del bando: `1 + ventajaAltura` si está más alto que el otro por
   más de `difAltura`, `× (1 − penaAgua)` si el choque cae en agua, `+
   ventajaDefensa` si pelea dentro de su territorio.
3. Después, cada bando comprueba su retirada (`debeRetirarse`). El que se
   retira vuelve a casa como hoy; si el otro es más rápido y agresivo, puede
   perseguirlo al día siguiente (nuevo choque).
4. Aniquilado (sin soldados ni vehículos sanos): sus heridos quedan en manos
   del enemigo (como hoy) y su líder cae o es capturado (3.2).
5. Un tercer ejército que llega a `radioEncuentro` de un combate se suma a su
   bando si es aliado de uno de los dos.

El azar sale de `Ruido.azar(Ruido.hash(semilla, día, 91))` en el orden fijo de
siempre; así es igual en todas las máquinas.

**Batalla del jugador.** Si uno de los dos ejércitos del choque es de un
jugador:

1. Los dos quedan trabados (`g.enBatalla = batallaId`) en la simulación: no se
   mueven, no los resuelve la simulación y nadie más puede unirse salvo
   llegando a `radioEncuentro` (entran como refuerzo en la escena).
2. Se abre `batalla/escena.lua` con **exactamente** las unidades sanas de los
   dos ejércitos (por modelo), en el terreno del punto del choque.
3. Mientras dura, en local **el mundo sigue a `ritmoBatalla` de su velocidad**
   (hoy el prototipo lo pausa: cambio para Valeria). En línea, el mundo sigue a
   su ritmo y la batalla tiene un tope de `diasBatallaMax` días de mundo;
   al llegar, lo que quede sin decidir se resuelve con la regla NPC.
4. Al terminar, la escena manda un comando:
   `ejecutar({ tipo = 'resolverBatalla', batalla, caidos = { [bando] = {
   soldados, tanquesPor, lanzacohetes, ... } }, retira = bando o nil })`.
   La simulación comprueba que nadie pierde más de lo que tenía y que no se
   gana nada; aplica las bajas con `herirGrupo` (lo destruido en la escena
   cuenta como caído: `recuperable` decide cuánto queda herido), aplica la
   retirada y la caída o captura de líderes como en el caso NPC.
5. El mando del jugador cambia el resultado porque lo decide la escena, no la
   fórmula. La IA del bando NPC dentro de la escena usa la prudencia de su
   líder para su retirada.
6. **Quién calcula la batalla** (decidido por el dueño):
   - **Fase 3:** la escena corre en la máquina del jugador y manda
     `resolverBatalla`. En línea, el servidor solo comprueba los límites del
     punto 4 (nadie gana unidades y nadie pierde más de lo que tenía).
   - **Meta en línea:** el servidor calcula la batalla y la máquina del
     jugador solo le manda sus órdenes como comandos. Para eso la batalla
     tendrá que ser determinista; es trabajo de Tomás y Valeria después de la
     fase 3.
7. La escena puede usar **librerías externas de Lua o LÖVE** (`GUIA-3D.md`,
   sección 5), pero nunca dentro de la simulación.

**Asedios a ciudades y ataques a campamentos.** Al llegar a su objetivo, el
ejército combate cada día con las reglas de hoy: `combatirCiudad` (con
`c.asediadaDia`: una ciudad sitiada no recluta ni recibe defensas) y
`combatir` para instalaciones y campamentos (el campamento sin guarnición se
destruye). Si el atacante es un jugador, cada día de asedio o ataque puede
entrar a la batalla 3D contra la guarnición del sitio y sus defensas fijas.
Un ejército de refuerzo que llega a una ciudad sitiada choca primero con el
sitiador.

### 3.8 Qué cambia en el código y en el guardado

**Simulación (`mundo/simulacion.lua`, Andrés).**

- El grupo de hoy sigue en `e.grupos` (no se renombra la tabla: menos cambios),
  con campos nuevos: `lider` (id de líder o nil en convoyes), `clase`
  (`'ejercito'` o `'convoy'`), `petroleo` (lo que carga), `destinoEjercito`
  (id del ejército que persigue), `trabado` (id del combate o de la batalla del
  jugador), `tanquesPor` (por modelo, cuando entre el armamento).
- Tabla nueva `e.lideres[id] = { id, nacion, nombre, rango, agresividad,
  prudencia, victorias, derrotas, estado = 'libre'|'campo'|'preso',
  ejercito, captor, desde }`. El presidente es un líder más (`n.lider`), y
  `n.gobernante` se queda como hoy para no romper diplomacia.
- Comandos nuevos en `ejecutar`: `formarEjercito`, `nombrarGeneral`,
  `moverEjercito` (cambiar destino a un punto, sitio o ejército), `resolverBatalla`,
  `unirEjercito`, `pagarRescate`. `enviarGrupo` se queda para convoyes y como
  atajo interno.
- `moverGrupos`: destino móvil, tramos con coste de terreno (F4), petróleo
  cargado, detección de choques (F7) y combate de ejército contra ejército.
- `ofensiva`: fuera `grupoEnCamino(..., 'atacar')` como tope; un ejército por
  líder libre.
- `opciones.alturaEn(x, y)`: el mundo le pasa a la simulación la altura
  natural (`Terreno:base`), como hoy `sitioValido`. Sale de la semilla y no se
  guarda.

**Guardado: versión 14.** Migración en `Simulacion.cargar`:

1. Cada grupo con misión `atacar`, `refuerzo` o `regreso` pasa a
   `clase = 'ejercito'`; los de `construir` y `entrega`, a `'convoy'`.
2. Cada nación recibe su presidente como líder. El primer ejército de la
   nación (por `id`) lo manda el presidente; los demás, generales nuevos
   creados con `Ruido.hash(semilla, nación, contador)` sin coste (como en la
   migración 11 → 12, que ya crea cosas «sin coste»).
3. `petroleo` de cada ejército en marcha: lo que le haga falta para volver a
   casa (F5), sin cobrarlo.
4. `e.siguienteLider = 1` y `n.lideres = {}` donde no existan.

**Lo que se retira del dibujo del mapa (Valeria).** En `mundo/mundo.lua`:
`piezasGrupos` (tanques y camiones de los grupos), `posicionRetirada` y
`posicionVisible` de los grupos, `dibujarBarras` de los grupos (la vida pasa al
panel de la ficha), `tanqueEnCombate`, `dispararTanque`,
`actualizarCombate`, `dibujarCombate` y `posturaTanque` (el disparo en el
mapa), y el modo F4/`--3d` de tanques en el mapa. **Se quedan**: los
lanzacohetes y defensas fijos de ciudades y bases (son parte del sitio), y
las salvas de misiles y las incursiones aéreas entre sitios, que no son
ejércitos. Si el dueño quiere también fuera los lanzacohetes fijos, es un
cambio aparte.

## 4. Fórmulas

Constantes de referencia de hoy: `FUERZA` soldado 1, tanque 9, avión 15,
interceptor 1, misil 2; lanzacohetes en tierra 40 (`fuerzaLanzacohetes`);
`velocidadEjercito` 9 000 px/día; `petroleoTanque` 0,03; `petroleoAvion` 0,1;
bajas diarias `azar(0,06; 0,12)` del golpe.

### F1. Poder de una unidad

`poderUnidad = escalaPoder × (vida + golpe) / 2`, con `escalaPoder = 5,5`.

| Unidad (cifras de hoy) | vida = golpe | Poder |
|---|---|---|
| Soldado | 1 | 5,5 |
| Tanque de referencia (casco medio, cuña, cañón largo) | 9 | 49,5 |
| Lanzacohetes (en tierra) | 40 | 220 |
| Avión | 15 | 82,5 |
| Interceptor | 1 | 5,5 |

**Por qué 5,5**: es el entero y medio que hace que 10 tanques de referencia
den 495, casi exactamente los «500» del dueño, sin tocar ningún peso de
combate. Con el armamento: tanque pesado + cúpula + largo (vida 13, golpe
8,5) → 5,5 × 10,75 = 59,1; ruedas + baja + corto (vida 3,5, golpe 6) → 26,1.
Rango de un tanque con las 48 combinaciones: vida 3,5–13 y golpe 6–11,5
(`diseno-de-armamento.md` F1), así que el poder de un tanque queda entre unos
26 y unos 60 (los extremos exactos dependen de qué combinación tiene a la vez
la mayor suma; no calculado combinación a combinación).

**Aviones e interceptores (fase 4, sin medir).** El avión usa la F9 del
armamento: `FUERZA = 15 × (carga / 8 + combate) / 2`. El interceptor vale
poco en poder porque su papel es restar: en el combate NPC, cada interceptor
anula `anulaInterceptor` del golpe aéreo enemigo de ese día.

### F2. Poder de un ejército

`poder = Σ poderUnidad` de sus unidades sanas; se muestra `floor(poder + 0,5)`.
Hoy equivale a `5,5 × vidaGrupo(g)`.
Ejemplo: 300 soldados, 10 tanques de referencia y 1 lanzacohetes →
1 650 + 495 + 220 = 2 365.
Rango medido de los grupos de ataque de hoy al salir (500 días, 6 semillas):
mínimo 248–644, mediana 1 960–3 540, p90 6 860–12 700, máximo 16 900–23 000.

### F3. Velocidad

`velocidad = velocidadEjercito × min(factor de los modelos que lleva)` px/día;
el factor es F3 del armamento (0,81–1,5; 1 con las cifras de hoy). Soldados
solos: factor 1. Ejemplo: con un tanque pesado + caja + doble (0,81), todo el
ejército anda 7 290 px/día.

### F4. Coste del terreno en la marcha

El día se parte en tramos de `pasoMuestreo` = 1 000 px. En el punto de inicio
de cada tramo se mira `h = alturaEn(x, y)` y el tramo cuesta
`1 / factorTerreno(h)` px de marcha por px recorrido:

| Terreno | Condición | factorTerreno |
|---|---|---|
| Agua honda | `h < −40` | 0,25 |
| Agua (vado, pontones) | `−40 ≤ h < 0` | 0,5 |
| Llano | `0 ≤ h < 200` | 1 |
| Monte | `200 ≤ h < 300` | 0,5 |
| Cumbre | `h ≥ 300` | 0,25 |

Se avanza tramo a tramo hasta gastar la velocidad del día. Coste: con 9 000
px/día son unas 9–18 consultas de altura por ejército y día; medido a
3,1–3,8 µs por consulta, unos 30–70 µs por ejército y día.
Efecto esperado (calculado con las medianas medidas de los caminos de ataque
de hoy: 22,5 % agua, 7,5 % agua honda, 2,2 % monte): factor medio
`1 / (0,225 / 0,5 + 0,075 / 0,25 + 0,022 / 0,5 + 0,678) ≈ 0,68`. Un ataque de
60 000 px pasa de 6,7 a unos 9,8 días. **No medido en simulación.**

### F5. Petróleo de la marcha

`gastoDia = Σ consumo de cada vehículo × (factorMarcha si se movió; 1 si no)`,
con `factorMarcha = 2`.
`petroleoIda = gastoDia × largo / velocidad` (con `factorMarcha`).
El NPC carga `petroleoIda × 2 × margenPetroleo` (`margenPetroleo` = 1,3) más
`diasCombate` = 5 días de gasto parado.
Ejemplo: 10 tanques de referencia a 60 000 px → gastoDia en marcha 0,6;
ida 60 000 / 9 000 × 0,6 = 4; carga 4 × 2 × 1,3 + 5 × 0,3 = 11,9.
Contexto medido (armamento): petróleo del almacén, mediana por nación, 2–3 el
día 15 y 0–108 el día 60. Al principio, sacar 10 tanques lejos **no se puede
pagar**; eso es la economía frenando, no un tope.

### F6. Decisión de atacar o huir (NPC)

`r = poderPropio / max(1, poderEnemigo)`.
`umbralAtaque = 1,5 − 0,8 × agresividad + 0,4 × prudencia` (0,74–1,82).
`umbralHuida = 0,5 + 0,4 × prudencia − 0,2 × agresividad` (0,34–0,88).
Ejemplo: general agresivo (0,9) y poco prudente (0,2): ataca con r ≥ 0,86 y
huye con r < 0,4. General prudente (0,9) y tranquilo (0,2): ataca con
r ≥ 1,7, huye con r < 0,82.
La ventaja del sitio (F8) entra en `poderEnemigo` si el enemigo está en una
posición mejor que la propia (más alto o en su territorio).

### F7. Detección del choque

Dos ejércitos A y B se mueven a la vez del punto de ayer al de hoy. Con
`r = A0 − B0` y `v = (A1 − A0) − (B1 − B0)`:
`t = clamp(−(r · v) / (v · v); 0; 1)` y `d = |r + v × t|`.
Choque posible si `d < radioEncuentro` (3 000 px, 300 m).
Coste: pares de ejércitos en guerra; con 1–28 grupos a la vez medidos, como
mucho unos 380 pares al día. Si crecen mucho, se usa la rejilla de
`indice()` (celdas de 16 384 px) para mirar solo vecinos.

### F8. Combate de ejército contra ejército (NPC)

`bajasQueCausa(A) = floor(golpe(A) × azar(0,06; 0,12) × ventaja(A))`.
`ventaja = (1 + ventajaAltura si h(A) − h(B) > difAltura) × (1 − penaAgua si
el punto es agua) + ventajaDefensa si dentro de su territorio`.
Con `ventajaAltura` 0,15, `difAltura` 30, `penaAgua` 0,25, `ventajaDefensa`
0,1.
Ejemplo: A = 2 365 de poder (golpe 430 con las cifras de hoy) en su
territorio y más alto; B = 1 800 (golpe 327) en llano: A causa entre
`floor(430 × 0,06 × 1,25) = 32` y `floor(430 × 0,12 × 1,25) = 64` bajas; B,
entre 19 y 39.

### F9. Guarnición mínima (NPC)

`reserva = 0,2 + 0,4 × prudencia (+ 0,15 en frontera)` del poder del sitio;
el ejército puede llevarse hasta `(1 − reserva)`.
Medido hoy: la parte del sitio que sale en un ataque tiene mediana
0,31–0,34, p90 0,60–0,75, máximo 0,75–0,80. Con la reserva propuesta, lo
máximo que saldría es 0,76 (prudencia 0,1, fuera de la frontera): encaja.

## 5. Casos límite

- **La ciudad de origen cae mientras el ejército está fuera**: vuelve al sitio
  propio más cercano (hoy `volver`); si la nación no tiene sitios, el ejército
  se disuelve y su líder queda libre sin nación (desaparece).
- **Cae la capital (la nación entera)**: hoy se borran sus grupos. Propuesta:
  igual, y sus líderes presos de otros quedan presos de por vida
  (desaparecen).
- **Dos choques el mismo día para un ejército**: se atiende primero el de menor
  distancia `d`; empate, el de `id` de ejército menor.
- **Choque de tres naciones**: cada par en guerra combate por separado; el
  ejército reparte su golpe entre sus enemigos a partes iguales.
- **Poder 0 (solo heridos)**: no puede atacar; si le alcanzan, es aniquilado y
  el líder cae o lo capturan.
- **Alto el fuego a mitad de combate**: los trabados se separan al día
  siguiente y quedan `detenido` como hoy.
- **El jugador cierra la batalla sin terminar o se desconecta**: se resuelve
  con la regla NPC desde el estado en que estaba la escena (lo destruido
  cuenta).
- **La batalla del jugador llega al tope `diasBatallaMax` en línea**: igual
  que el anterior.
- **El jugador intenta devolver más unidades de las que tenía**
  (`resolverBatalla`): el comando se rechaza (`false`) y se resuelve con la
  regla NPC.
- **Sin petróleo en territorio enemigo**: va a `velocidadSinPetroleo` hacia
  casa; si le alcanzan, no puede huir (choque obligado).
- **Destino en el agua** (ejército enemigo sobre un lago): se llega igual, más
  lento; el combate en agua lleva `penaAgua` a los dos.
- **Líder preso cuya nación desaparece**: se libera y desaparece.
- **Sueldo impagado del presidente**: el presidente no cobra sueldo; nunca se
  licencia.
- **El presidente está en campaña y se decide algo de gobierno**: las
  decisiones de gobierno (diplomacia, economía) siguen igual; el presidente no
  necesita estar en la capital.
- **Un ejército de refuerzo alcanza al sitiador de su propia instalación**:
  choque normal; si el sitiador gana, sigue su asedio.

## 6. Dependencias

- **Depende de:**
  - `diseno-de-armamento.md`: vida, golpe, velocidad y consumo por modelo (F1,
    F3, F5). Hasta que exista, se usan las cifras de hoy.
  - `retirada-y-recuperacion.md`: `herirGrupo`, `debeRetirarse`, umbral,
    cola de recuperación; aquí el umbral sale de la prudencia del líder.
  - `guerra.md`: `objetivo`, `ofensiva`, `refuerzos`, `combatir`,
    `combatirCiudad`, días de tensión y alto el fuego.
  - `naciones-y-politica.md`: carácter del presidente, relaciones, regente mientras el presidente está preso.
  - `instalaciones-y-economia.md`: almacén de petróleo, tesoro (sueldos),
    fabricación.
  - `mundo-fisico.md`: altura del terreno y nivel del mar (F4).
  - `interfaz.md`: estilo «Estandarte colgante» de la ficha y del panel.
  - `diplomacia.md`: canje de presos en la paz o el alto el fuego.
  - Exploradores (sin documento aún): composición enemiga en la ficha.
- **Lo necesitan** (cada uno de esos documentos debería nombrar este cuando se
  actualice; no los he tocado por encargo):
  - `guerra.md`: los grupos terrestres pasan a ser ejércitos con líder.
  - `retirada-y-recuperacion.md`: umbral por líder; heridos que vuelven con el
    ejército.
  - `diseno-de-armamento.md`: el poder se calcula de golpe y vida del modelo.
  - `interfaz.md`: panel de la ficha y del armado del ejército.
  - `diplomacia.md`: presos y rescates en las negociaciones.
  - La escena de batalla (`batalla/`) y la red (Tomás).

## 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `escalaPoder` | 5,5 | 1–10 | Solo el número que se muestra; no cambia el combate. |
| `radioEncuentro` | 3 000 px | 1 000–6 000 | Más alto, más choques (medido hoy: 0,03–0,16 al día con 3 000; 0,05–0,43 con 6 000). |
| `radioVista` | 20 000 px | 10 000–40 000 | Hasta dónde se ve y se decide perseguir o huir; más alto, menos sorpresas. |
| `diasInforme` | 10 | 5–30 | Cuánto vale un informe de explorador. |
| `pasoMuestreo` | 1 000 px | 400–2 000 | Precisión del terreno contra coste (3–4 µs por consulta). |
| `factorTerreno` agua / honda / monte / cumbre | 0,5 / 0,25 / 0,5 / 0,25 | 0,2–0,8 | Cuánto frena el terreno; con agua a 0,2 los ataques tardan casi el doble. |
| `factorMarcha` | 2 | 1–3 | Cuánto cuesta moverse frente a estar parado. |
| `margenPetroleo` | 1,3 | 1,1–2 | Petróleo de sobra que carga el NPC. |
| `velocidadSinPetroleo` | 0,25 | 0,1–0,5 | Castigo por quedarse seco. |
| `golpeSinPetroleo` | 0,5 | 0,2–0,8 | Golpe de los vehículos sin petróleo. |
| `umbralAtaque` (1,5; −0,8; +0,4) | ver F6 | base 1,2–1,8 | Más bajo, más choques y más desiguales. |
| `umbralHuida` (0,5; +0,4; −0,2) | ver F6 | base 0,3–0,7 | Más alto, más huidas y persecuciones. |
| `diasPersecucion` | 3 | 1–6 | Cuánto dura una persecución. |
| `ventajaAltura` / `difAltura` | 0,15 / 30 | 0–0,3 / 10–80 | Peso del terreno en la resolución NPC. |
| `penaAgua` | 0,25 | 0–0,5 | Castigo por combatir vadeando. |
| `ventajaDefensa` | 0,1 | 0–0,25 | Ventaja de pelear en casa. |
| `reserva` (0,2 + 0,4 × prudencia; +0,15 frontera) | ver F9 | base 0,1–0,4 | Cuánto deja el NPC en casa. |
| `poderMinimoSalida` | 300 | 100–1 000 | Ejército más pequeño que forma un NPC. |
| `costeGeneral` / `sueldoGeneral` | 100 / 2 al día | 50–300 / 0,5–5 | Cuántos generales se pueden pagar al principio. |
| `pCaptura` | 0,6 | 0,3–0,9 | Presos contra muertos. |
| `pFuga` | 0,02 al día | 0–0,05 | Cuánto dura un preso sin rescate (media 50 días). |
| `rescate` | 150 × rango (1–3) | 50–500 | Precio de recuperar un líder. |
| `capturaPresidente` | 10 | 0–20 | Cansancio de guerra que suma una nación cuando capturan a su presidente. |
| `ritmoBatalla` | 0,25 | 0,1–0,5 | Velocidad del mundo mientras el jugador pelea (local). |
| `diasBatallaMax` | 1 | 0,5–2 | Tope en línea de una batalla del jugador, en días de mundo. |
| `anulaInterceptor` | 8 | 4–15 | Golpe aéreo que anula cada interceptor (fase 4, sin medir). |

## 8. Criterios de aceptación

Comprobables con el arnés sin ventana (16 zonas, 500 días, 6 semillas), salvo
los de vista:

1. **Determinismo**: dos simulaciones iguales y guardar/cargar a mitad acaban
   con el mismo estado, con ejércitos, líderes, presos y combates de ejército
   contra ejército.
2. **Poder**: con las cifras de hoy, `poder(g) == 5,5 × vidaGrupo(g)` para
   todo ejército; 10 tanques de referencia solos dan 495.
3. **Nada de la nada**: en cada `formarEjercito`, lo que sale del sitio es
   igual a lo que entra en el ejército (soldados, tanques por modelo,
   lanzacohetes), y la suma de unidades de la nación no cambia ese día.
4. **Migración 13 → 14**: una partida de la versión 13 carga, todos sus grupos
   de ataque tienen líder y la simulación sigue 100 días sin errores.
5. **Varios ejércitos**: el máximo de ejércitos de ataque de una nación a la vez
   pasa de 1 (hoy, medido) a 2 o más en al menos la mitad de las naciones en
   algún momento de los días 101–500 (objetivo propuesto; sin medir).
6. **Encuentros**: entre 0,1 y 1 choque de ejército contra ejército al día en
   el mapa de 16 zonas (hoy, con un ejército de ataque por nación y
   `radioEncuentro` 3 000: 0,03–0,16; objetivo propuesto).
7. **Huidas**: al menos el 20 % de los ejércitos que ven a un enemigo con
   `r < 0,5` escapan sin combatir (objetivo propuesto).
8. **Terreno**: la duración media de un ataque de ida sube entre un 25 y un
   60 % frente a la versión 13 (el cálculo con las medianas da +47 %).
9. **Petróleo**: ningún ejército tiene `petroleo < 0`; los días-ejército sin
   petróleo son menos del 10 %.
10. **Equilibrio general** (contra los números del README): guerras declaradas,
    tomas y cesiones de ciudad dentro de ±30 % de los de la versión 13.
11. **Rendimiento**: mediana de tiempo por día simulado sin subir más de 1 ms
    sobre la versión 13 (hoy 2,9–5,3 ms).
12. **Vista (Valeria, con captura)**: en el mapa no se dibuja ningún tanque,
    camión ni disparo de grupo; cada ejército es un estandarte con líder y
    poder; al hacer clic en uno enemigo sin informe, la composición sale como
    «desconocida».
13. **Batalla (Valeria/Elena)**: la escena abre con exactamente las unidades
    sanas de los dos ejércitos y, al terminar, `resolverBatalla` deja en la
    simulación las mismas bajas que se vieron.

## 9. Fases y quién hace qué

**Fase 1: la ficha (lo mínimo jugable).** Los grupos de hoy se ven como
estandartes con líder y poder; nada más cambia en las reglas.
- Andrés: `e.lideres` con el presidente y generales creados al salir cada
  grupo de ataque (sin coste aún), `poder(g)`, versión 14 y migración.
- Valeria: ficha estandarte, etiqueta, clic con panel (poder; composición
  solo si es propio), quitar tanques, camiones, barras y disparos de grupos del
  mapa.
- Camila: estandarte colgante (asta, paño, 3 poses: marcha, combate,
  retirada) y un kit de escudos de nación (formas, cargas y esmaltes que se
  combinan por semilla, ficticios).
- Tomás: nada nuevo (el estado nuevo viaja con el que ya se reparte).
- Elena: criterios 1, 2, 4 y 12.

**Fase 2: ejércitos que se cruzan.** Varios ejércitos por nación, líderes con
carácter y sueldo, choques, atacar/huir/perseguir, combate NPC, captura,
terreno y petróleo de marcha.
- Andrés: 3.2, 3.5, 3.6 (sin unirse), 3.7 NPC, F4–F9.
- Valeria: estados de la ficha (combate, retirada, sin petróleo) y niebla de
  guerra con `radioVista`.
- Camila: iconos de estado y rangos.
- Tomás: que los comandos nuevos pasen por el servidor.
- Elena: criterios 3, 5–11.

**Fase 3: armar y pelear en 3D.** Pantalla de armado en la ciudad para el
jugador, `formarEjercito` con composición, batalla 3D con las unidades exactas,
mando del jugador y `resolverBatalla`; el mundo a `ritmoBatalla`.
- Andrés: `formarEjercito`, `resolverBatalla`, trabado de ejércitos.
- Valeria: enlace ficha → escena (hoy la escena busca «el combate más cercano»
  con B), escena con los ejércitos del choque, mundo más lento en vez de
  pausa, informe de bajas al terminar.
- Camila: panel de armado según `interfaz.md`.
- Tomás: en línea, el servidor comprueba los límites de `resolverBatalla`
  (decidido). La batalla calculada en el servidor queda como meta posterior.
- Elena: criterio 13 y una partida de prueba guiada.

**Fase 4: el resto.** Aviones e interceptores en el ejército, unirse a
ejércitos aliados, rescates y canje de presos, exploradores y composición
enemiga en la ficha.

## 10. Números medidos (simulación de hoy, versión 13)

Arnés sin ventana, 16 zonas (−2..1), 500 días, semillas 4242, 1, 7, 99, 12345
y 2026. Mide la simulación **tal como es hoy**; no simula las reglas nuevas.

| Medida | Rango en 6 semillas |
|---|---|
| Grupos de ataque enviados en 500 días | 20–94 |
| Poder al salir (5,5 × vidaGrupo): mínimo / mediana / p90 / máximo | 248–644 / 1 960–3 540 / 6 860–12 700 / 16 900–23 000 |
| Parte del poder que son soldados, mediana | 83–91 % |
| Parte del poder que son tanques, mediana | 4,5–11 % |
| Tanques por ejército: mediana / máximo | 2–4 / 19–25 |
| Parte del poder del sitio que sale, mediana / máximo | 0,31–0,34 / 0,75–0,80 |
| Largo del camino de ataque, mediana | 52 000–70 000 px (5,2–7 km) |
| Ataques cuya línea recta cruza agua | 85–100 % |
| Parte del camino en agua, mediana | 30–33 % (agua honda, `h < −40`: 7–9 %) |
| Tramo de agua seguido más largo, mediana / máximo | 3 600–4 000 / 6 400–9 200 px |
| Parte del camino en monte (`h ≥ 200`), mediana | 1,6–2,8 % (cumbre `h ≥ 300`: 0 %) |
| Coste de una consulta de altura | 3,1–3,8 µs |
| Grupos de ataque a la vez (días 101–500): mediana / máximo | 0–3 / 4–10 |
| Máximo por nación a la vez | 1 (el tope de `grupoEnCamino`) |
| Grupos militares a la vez (ataque, refuerzo, regreso): mediana / máximo | 0–5 / 6–15 |
| Todos los grupos a la vez, con convoyes: mediana / máximo | 10–12 / 18–28 |
| Choques posibles ejército-ejército al día (naciones en guerra), `radioEncuentro` 1 000 / 3 000 / 6 000 px | 0,01–0,06 / 0,03–0,16 / 0,05–0,43 |
| Ídem contando convoyes, con 3 000 px | 0,04–0,18 |
| Llegadas con combate (`combatir` + `combatirCiudad`) al día | 0,09–0,42 |
| Soldados por nación, mediana, día 100 / día 500 | 1 090–1 470 / 8 060–9 460 |
| Tiempo de 500 días de simulación con el arnés | 4,8–5,2 s |

Lectura:

- Hoy casi no hay encuentros porque cada nación manda **un** grupo de ataque a
  la vez y los grupos se dirigen a sitios, no a ejércitos. Con varios
  ejércitos y persecución subirán; cuánto, está **sin medir** (hace falta la
  fase 2 programada).
- Los soldados son el 83–91 % del poder. «10 tanques = 500» se cumple, pero un
  ejército típico lleva unos 300–600 soldados (1 650–3 300 de poder), así que
  en la ficha los tanques pesarán poco. El dueño decidió dejarlo así en las
  fases 1 y 2 y volver a mirarlo con choques medidos.
- El agua cubre un tercio de cada línea recta: por eso el agua frena y no
  corta el paso.

## 11. Preguntas abiertas para el dueño

Ninguna. Las cuatro que había (peso de los soldados, si el presidente puede
caer, quién calcula la batalla en línea y si el agua corta el paso) las
decidió el dueño el 2026-09-26: ver la cabecera del documento.

## Cómo se midió

Arnés fuera del repo, en la carpeta temporal de la sesión
(`scratchpad/ejercitos/medir.lua`), sobre la simulación de hoy (versión 13,
HEAD e3076fc). Crea el mundo con `Mundo.nuevo(semilla)` con un sustituto de
`love`, registra 16 zonas (−2..1) y avanza 500 días. Envuelve `enviarGrupo`
(misión `atacar`: composición, poder = 5,5 × vida, parte del sitio que sale y
muestreo de `Terreno:base` cada 400 px de la línea recta), `combatir` y
`combatirCiudad` (llegadas con combate). Tras cada día cuenta grupos por
misión y, para cada par de grupos de naciones en guerra, la distancia mínima
entre sus trayectos del día (F7) con 1 000, 3 000 y 6 000 px. No cambia
ninguna regla. Se corre con `luajit medir.lua <semilla> 500`.

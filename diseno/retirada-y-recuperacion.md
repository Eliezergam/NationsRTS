# Retirada y recuperación de ejércitos

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

> **Implementado en la simulación** (`mundo/simulacion.lua`, formato de
> partida 12) con las decisiones del dueño: lanzacohetes opción A,
> `recuperable = 1`, retirada preventiva, daño repartido entre soldados,
> tanques y lanzacohetes, los defensores no se retiran, precios y ritmos de
> este documento. **Falta lo visual** (barra, rótulo "En retirada", líneas del
> panel y botón de acelerar: §3.9), que sigue PROPUESTO. Sale de una idea de
> El dueño ("una barrita de vida; al casi quedar exterminados regresan a la
> ciudad; un presidente que mandó 10 lanzacohetes queda con uno, pero se
> regeneran con el tiempo; para acelerar la recuperación, gasto dinero"). Las
> cifras son del código real (ver "Cómo se midió", al final).

Fuentes del código actual en las que se apoya: `mundo/simulacion.lua`:
`enviarGrupo`, `combatir`, `combatirCiudad`, `volver`, `llegada`,
`moverGrupos`, `ofensiva`, `enviarDefensas`, `enCamino`, `sitiada`,
`tomarCiudad`, `Simulacion.defensasCiudad`, `Simulacion.conquista`
(`fuerzaLanzacohetes = 40`), `FUERZA` (tanque = 9). Dibujo:
`mundo/mundo.lua` (`posicionVisible`, `piezasGrupos`); panel: `main.lua`.

## 1. Resumen

Cada grupo que sale a atacar (misión `atacar`) lleva una **barra de vida**: la
suma de lo que lleva, con el mismo peso que tiene en combate (soldado 1,
tanque 9, lanzacohetes 40). El daño del enemigo se reparte entre sus
soldados, tanques y lanzacohetes en proporción a lo que pesa cada uno; lo que
cae no muere: queda **herido o averiado** y viaja con el grupo. Cuando la
vida baja del **umbral de retirada** (según la prudencia de quien manda), el
grupo **se retira solo** a su ciudad. Allí los vivos vuelven a su puesto y los
heridos y averiados entran en una **cola de recuperación** que devuelve cada
día unos cuantos, más rápido cuanto más nivel tiene la ciudad, sin coste. El
dueño de la ciudad (presidente NPC o jugador) puede **pagar dinero para
acelerar**: cada unidad pagada vuelve al momento. Solo se pierde todo si el
grupo cae entero en un mismo día. Los grupos que salen de una ciudad pueden
llevarse parte de sus **lanzacohetes**, que luchan en el campo.

## 2. Fantasía del jugador

"Mandé diez lanzacohetes y mil seiscientos hombres contra Nualtor. Vi la barra
bajar día a día; al quinto día, en rojo, dieron media vuelta. Volvió uno. Los
otros nueve están en el taller de Vescapal: en ocho días los tengo otra vez, o
pago 264 y los tengo hoy." Perder una batalla duele y cuesta tiempo o dinero,
pero no borra un ejército de un plumazo; y el jugador ve venir la derrota en
la barra antes de que llegue.

## 3. Reglas

Todo §3 está implementado salvo §3.9 (lo que ve el jugador).

### 3.1 Qué llevan los grupos (lanzacohetes en campaña)

> Con P7 de [guerra.md](guerra.md#p7-lanzacohetes-en-las-bases-implementado)
> (implementado, formato 13) las bases tienen lanzacohetes y los prestan a sus
> grupos con la misma fórmula (opción L1, regla 12 de P7).

1. `enviarGrupo` acepta un octavo valor, `lanzacohetes`, y un noveno,
   `retirada` (y el comando `enviarGrupo` los campos `lanzacohetes` y
   `retirada`). Salen de la ciudad o la base de origen (con P7 las bases
   también tienen): se restan de sus `lanzacohetes` y van en
   `g.lanzacohetes`. El grupo apunta su sitio de origen en `g.origen` (hasta
   el formato 12, `g.origenCiudad`, solo ciudades).
2. En combate cada lanzacohetes suma 40 de fuerza (`fuerzaLanzacohetes`, el
   mismo valor con el que ya defiende una ciudad). Representa sus salvas de
   campo; no gasta misiles del arsenal.
3. Mientras están fuera la ciudad los echa en falta: dispara menos
   (`misilesListos = lanzacohetes × 4`) y defiende menos en un asalto.
4. Los lanzacohetes que están fuera o en la cola de recuperación **cuentan
   para el tope** de la ciudad: `enCamino(ciudad, 'lanzacohetes')` los suma.
   En una base solo cuentan los sanos que tiene fuera: los averiados se
   reparan en una ciudad y no vuelven a ella.
   Así el presidente no compra repuestos para huecos que se van a llenar solos
   y, al volver, la ciudad nunca pasa del tope.
5. El NPC se lleva lanzacohetes de la ciudad o la base de la que sale:
   `floor(lanzacohetes del sitio × parte × (1 − 0,5 × prudencia))`, con
   `parte = 0,5` si va a por una ciudad y `0,25` si va a por una instalación.

### 3.2 Vida del grupo

1. Al salir: `g.vidaMax = soldados + 9 × tanques + 40 × lanzacohetes`.
   `g.umbral` se fija al salir (ver 3.4). `g.heridos = {0, 0, 0}`,
   `g.resto = {0, 0, 0}`.
2. `vida = soldados + 9 × tanques + 40 × lanzacohetes` en cada momento. La
   barra es `vida / vidaMax`. La vida es también la fuerza con la que golpea:
   un grupo mermado pega menos.

### 3.3 Combate de cada día (sustituye la parte del grupo en `combatir` y `combatirCiudad`)

1. `nuestra = vida`. La fuerza del defensor y sus bajas se calculan **igual
   que hoy** (instalación: `(soldados + 9 × tanques) × (1 + fortificación)`;
   ciudad: `soldados + 9 × tanques + 40 × lanzacohetes`).
2. Daño al grupo: `D = floor(suya × azar(0,05; 0,1))`, recortado a `vida`.
3. Reparto, sin azar, en orden fijo (lanzacohetes, tanques, soldados): cada
   tipo recibe `D × (n_tipo × peso_tipo) / vida` puntos; eso son
   `puntos / peso_tipo` unidades, que se suman a `g.resto[tipo]`; caen
   `floor(g.resto[tipo])` unidades (como mucho las que hay) y el resto
   fraccionario se guarda para el día siguiente.
4. De las unidades que caen, `floor(caen × recuperable + 0,5)` pasan a
   `g.heridos[tipo]`; las demás mueren. Con `recuperable = 1` (la idea de
   el dueño) no muere nadie mientras el grupo exista.
5. **Sustituye** a la regla actual del grupo atacante "con > 15 bajas, 40 %
   de perder un tanque": los tanques caen por el reparto. El lado defensor no
   cambia.
6. Tras el combate, en este orden:
   - el defensor queda sin soldados ni tanques → toma (como hoy). Los vivos
     del grupo quedan de guarnición (instalación) o de ciudad conquistada; los
     lanzacohetes vivos se quedan en la ciudad conquistada o, si era una
     instalación, vuelven a su ciudad de origen con los heridos en un grupo de
     misión `regreso`;
   - `g.soldados = 0` → **aniquilado**: el grupo desaparece con sus tanques,
     sus lanzacohetes **y sus heridos** (quedan en manos del enemigo);
   - si no, **retirada** si se cumple cualquiera de las dos:
     a. `vida < g.umbral × g.vidaMax`;
     b. (retirada preventiva) `vida ≤ floor(suya × 0,1)`: el peor día posible
        del enemigo acabaría con él.

### 3.4 Umbral de retirada

- NPC: `umbral = 0,15 + 0,2 × prudencia` (prudencia 0,1–1 → 0,17–0,35).
- Jugador: lo elige al mandar el grupo (campo `retirada` del comando, de 0 a
  0,5). Con `retirada = 0` lucha hasta el final: no hay retirada de ningún
  tipo, tampoco la preventiva. Sin `retirada`, el grupo lleva el umbral del
  presidente de su nación (`Simulacion:umbralRetirada`); se guarda en
  `g.umbral`. Aún no hay interfaz para elegirlo.

### 3.5 La retirada

1. El grupo pasa a misión `regreso` con `g.retirada = true` (usa `volver`,
   así que va a su sitio de origen o, si cayó, al sitio propio más cercano).
2. Viaja a `velocidadEjercito` (9 000 px/día), como cualquier regreso.
3. Noticia: "El ejército de A se retira de X: vuelven S soldados, T tanques
   y L lanzacohetes; H heridos y averiados".
4. Al llegar (en `llegada`, rama `regreso`): los vivos se suman al sitio como
   hoy; los lanzacohetes vivos, al sitio al que vuelve (una base, hasta 6; lo
   que no quepa, a la ciudad propia más cercana); los heridos entran en la
   cola de recuperación de la **ciudad**: la de origen si era una ciudad; si
   salió de una base, la ciudad propia más cercana a esa base.
5. Todo grupo que vuelve por otra causa (objetivo destruido, paz, blanco ya
   propio) lleva igualmente sus heridos y lanzacohetes a casa por el mismo
   camino.

### 3.6 Cola de recuperación (por ciudad)

1. `c.recuperando = { soldados, tanques, lanzacohetes, avance = {…} }`. Las
   llegadas se suman a lo que ya haya.
2. Cada día, al final de `avanzarDia` (después de `moverGrupos`), en el orden
   de `ordenadas(ciudades)`:
   - si la ciudad está **sitiada** (combatió hoy o ayer), no avanza nada;
   - por cada tipo con algo en cola: `avance += ritmo[tipo] × nivel`;
     vuelven `min(cola, floor(avance))` unidades a la ciudad
     (`c[tipo] += k`) y `avance −= k`;
   - los **soldados** no se curan si la ciudad pasa **hambre**; tanques y
     lanzacohetes, sí;
   - cola vacía → `c.recuperando = nil`.
3. Recuperar no cuesta nada: solo tiempo.
4. Lo que está en la cola **no combate, no defiende, no cuenta en la fuerza**
   de la nación (`fuerza`) y los tanques no gastan combustible.

### 3.7 Acelerar la recuperación (comando nuevo, NPC y jugador)

`ejecutar({ tipo = 'acelerarRecuperacion', nacion, ciudad, tropa = 'soldados' |
'tanques' | 'lanzacohetes', cantidad, pagaTesoro })` (el campo se llama
`tropa` porque `tipo` ya es el nombre del comando):

1. Falla si la ciudad no es de `nacion`, no tiene cola o está sitiada.
2. Por cada unidad hasta `min(cantidad, cola[tipo])` (sin `cantidad`: toda la
   cola de ese tipo): paga `precio[tipo]` con el dinero de la ciudad; si no le
   alcanza y `pagaTesoro`, del tesoro del presidente; si tampoco, para.
3. Las pagadas vuelven **al momento** a la ciudad. El dinero desaparece (paga
   médicos y mecánicos): es un sumidero de dinero.
4. Devuelve cuántas se aceleraron, o `false`.

### 3.8 Cuándo paga el presidente NPC

Cada día, para cada ciudad propia con cola, si la nación tiene alguna guerra
**o** la ciudad está en la frontera (`enFrontera`):

- en orden lanzacohetes, tanques, soldados; solo los tipos a los que les
  queden **más de 3 días** de cola;
- `presupuesto = 0,5 × dinero de la ciudad + max(0, tesoro − 60) × (0,2 + 0,5 ×
  agresividad)`;
- acelera `floor(presupuesto / precio)` unidades con `pagaTesoro = true`.

Un presidente agresivo paga antes y más; uno en paz y lejos de la frontera
espera.

### 3.9 Lo que ve el jugador (PROPUESTO: aún sin dibujar)

- **Barra encima de la bandera** de todo grupo `atacar` que se vea (formado
  junto a su ciudad o combatiendo en el objetivo): 60 px de ancho en pantalla
  a cualquier zoom, relleno `vida / vidaMax`; verde por encima del 50 %,
  amarillo del 50 % al umbral × 2, rojo por debajo; una muesca en el umbral de
  retirada. Debajo, en pequeño, la vida en número.
- **"En retirada"**: el día que se retira se sigue viendo donde combatía, con
  la barra en rojo y ese rótulo; después desaparece como cualquier regreso y
  vuelve a verse formado junto a su ciudad, en el punto de despliegue
  (`Mundo.despliegue`), el último día de viaje antes de entrar.
- **Panel de la ciudad**, bajo "Defensas":
  - `Defensas: lanzacohetes 1/18 (+8 recuperándose, +1 fuera)`;
  - `Recuperándose: 1 398 soldados (24 días) · 7 tanques (4 días) · 8
    lanzacohetes (3 días)`; si está sitiada o con hambre, "(parada: sitiada)"
    o "(soldados parados: hambre)";
  - para la ciudad del jugador, un botón por tipo "Acelerar: 264" con el coste
    de acelerar toda esa cola.
- "Grupos en marcha" del panel de nación distingue "atacando", "en
  retirada" y "volviendo".

## 4. Fórmulas

**Vida.** `vida = S + 9·T + 40·L`. Rango: de ~130 (grupo mínimo de 120
soldados y 1 tanque) a unos 4 000 (asalto con 3 000 soldados, 20 tanques y 10
lanzacohetes). Ejemplo medido (semilla 4242, día 300): 1 659 soldados, 11
tanques y 10 lanzacohetes → `1 659 + 99 + 400 = 2 158`.

**Daño diario y reparto.** `D = floor(suya × azar(0,05; 0,1))`. Ejemplo: vida
2 149 (77,2 % soldados, 4,2 % tanques, 18,6 % lanzacohetes), `D = 339` →
lanzacohetes `339 × 0,186 / 40 = 1,58` (cae 1, resto 0,58), tanques `339 ×
0,042 / 9 = 1,58` (cae 1), soldados 261. Así las tres barras bajan juntas: con
el grupo al 11 % quedan ~11 % de cada tipo.

**Umbral.** `0,15 + 0,2 × prudencia`, rango 0,17–0,35. Ejemplo: prudencia 0,25
→ 0,20.

**Retirada preventiva.** `vida ≤ floor(suya × 0,1)`. Ejemplo: contra una
ciudad de 3 807 soldados, 18 tanques y 10 lanzacohetes (`suya = 4 369`), el
grupo se retira en cuanto su vida baja de 437, aunque su umbral le permitiera
seguir.

**Caso del dueño, medido** (código real, semilla 4242, desde el día 300; la
capital de Vescapal manda 1 659 soldados, 11 tanques y 10 lanzacohetes
contra Nualtor por el comando `enviarGrupo`; vida 2 158, umbral 0,20; 14 días
de ida, combate del día 15 al 20):

| Día | Vida | Soldados | Tanques | Lanzacohetes | Heridos (S/T/L) |
|---|---|---|---|---|---|
| 14 (llega) | 100 % | 1 659 | 11 | 10 | 0/0/0 |
| 15 | 86 % | 1 422 | 10 | 9 | 237/1/1 |
| 16 | 69 % | 1 140 | 8 | 7 | 519/3/3 |
| 17 | 56 % | 926 | 6 | 6 | 733/5/4 |
| 18 | 41 % | 683 | 5 | 4 | 976/6/6 |
| 19 | 28 % | 459 | 3 | 3 | 1 200/8/7 |
| 20 (se retira) | 15 % | 241 | 2 | 2 | 1 418/9/8 |

Llega a casa el día 35 con 2 lanzacohetes. Sin pagar, los 8 averiados vuelven
en 5 días (del 35 al 39: la ciudad ya había subido a nivel 4, 1,6 al día; el
primero vuelve el mismo día de llegar), los 9 tanques también en 5 y los
1 418 heridos en 24 (60 al día; con el ritmo actual de 25, en 15 a 100 al
día, calculado sin volver a medir). Mientras los 10 lanzacohetes estaban fuera,
la ciudad compró 8 para su nuevo tope (18): con los que volvieron quedó en
18/18, sin pasarse. Pagando el día 35: 7 lanzacohetes (uno ya había vuelto)
por 231 (7 × 33), con un tesoro de 19 236.

**Ritmo de recuperación.** `unidades al día = ritmo × nivel de la ciudad`:
soldados 25 × nivel (25–125; era 15 hasta P7), tanques 0,5 × nivel (0,5–2,5),
lanzacohetes 0,4 × nivel (0,4–2). Días para vaciar una cola de `k` unidades:
`ceil(k / (ritmo × nivel))`. Ejemplo: 9 lanzacohetes en nivel 3 → 8 días; 300
heridos en nivel 1 → 12 días.

**Precio de acelerar**, por unidad = mitad de lo que cuesta una nueva en
dinero (dinero + metal × 3 + petróleo × 4, los precios de
`Simulacion.dinero.precio`):

| Tipo | Nueva | Acelerar |
|---|---|---|
| Lanzacohetes | 40 + 6×3 + 2×4 = 66 | 33 |
| Tanque | 30 + 3×3 + 1×4 = 43 | 22 |
| Soldado | ~2 del presupuesto (reclutar da `parte × 0,5`) | 1 |

Ejemplo: acelerar 9 lanzacohetes, 7 tanques y 1 398 soldados = 297 + 154 +
1 398 = 1 849.

**Presupuesto del NPC.** `0,5 × dinero ciudad + max(0, tesoro − 60) × (0,2 +
0,5 × agresividad)`. Ejemplo: ciudad con 7 884, tesoro 19 925, agresividad 0,6
→ `3 942 + 19 865 × 0,5 = 13 874`: lo acelera todo. Medido: el tesoro mediano
de una nación es 549 el día 50, 1 485 el día 100, 5 741 el día 200 y 28 092 el
día 500 (semilla 4242). De ahí se deduce, sin haberlo medido aparte, que al
principio el NPC acelera a medias y que entre los días 100 y 200 ya puede
acelerar entero un asalto típico (1 849).

## 5. Casos límite

- **Cae entero en un día** (vida a 0 de golpe, o sin soldados): aniquilado; se
  pierden vivos, heridos y lanzacohetes. Con la retirada preventiva solo pasa
  si el primer día de combate ya lo borra.
- **Grupo sin soldados pero con tanques o lanzacohetes:** aniquilado, como hoy
  (sin infantería no se sostiene). Con el reparto proporcional los soldados
  llegan a 0 a la vez que lo demás, así que casi no ocurre.
- **Toma de una instalación:** los vivos se quedan de guarnición; heridos y
  lanzacohetes vuelven a la ciudad de origen en un grupo `regreso`.
- **Toma de una ciudad:** vivos, tanques y lanzacohetes se quedan en ella (la
  conquista hoy deja `lanzacohetes = 0`; los del grupo pasan a ser sus
  defensas); los heridos vuelven a la ciudad de origen.
- **Se retira y su casa cae o cambia de manos por el camino:** `volver` lo
  manda al sitio propio más cercano; los heridos, a la ciudad propia más
  cercana a ese sitio. Sin ciudades propias, el grupo y sus heridos se
  pierden (como hoy en `volver`).
- **Ciudad con cola que cambia de manos** (conquista, cesión en un tratado o
  caída de la capital): la cola se borra. Los heridos no cambian de bando.
- **Ciudad sitiada:** la cola se detiene y no se puede acelerar (igual que no
  se pueden instalar defensas en una ciudad sitiada).
- **Ciudad con hambre:** los soldados de la cola no avanzan; tanques y
  lanzacohetes sí. Si dura, los soldados sanos desertan (1 %/día, regla actual)
  pero los de la cola no.
- **Pagar sin dinero suficiente:** se aceleran las unidades que alcancen, de
  una en una; con 0, el comando devuelve `false` y no cambia nada.
- **Pagar con la ciudad y el tesoro:** primero la ciudad; el tesoro solo con
  `pagaTesoro`. El NPC siempre pone `pagaTesoro = true`.
- **Tope de lanzacohetes:** lo que está fuera o en cola cuenta para el tope,
  así que al volver no se pasa. Si aun así se pasara (por ejemplo una ciudad
  cedida y recuperada), se recorta al tope, como hace hoy `llegada` con las
  entregas.
- **Alto el fuego:** el grupo detenido no combate; su barra se congela. La cola
  sigue avanzando (no hay asedio).
- **Paz firmada con el grupo en combate:** `volver` como hoy; no cuenta como
  retirada, pero sus heridos van a la cola.
- **Umbral 0 elegido por el jugador:** sin retirada, ni por umbral ni
  preventiva: lucha hasta caer o tomar.
- **Grupos de refuerzo, obra y entrega:** no combaten; no tienen barra ni
  retirada.
- **Defensores** (guarniciones de instalaciones y de ciudades): no se retiran
  y sus bajas mueren, como hoy. Ver "Qué decide el dueño".
- **Partidas guardadas antes del cambio:** un grupo sin `vidaMax` toma como
  `vidaMax` su vida al cargar (barra llena) y el umbral de su nación.
- **Determinismo:** las reglas nuevas no usan azar (el único azar es el del
  daño, que ya existía) y recorren las ciudades con `ordenadas`. Todos los
  campos nuevos son datos (`g.vidaMax`, `g.umbral`, `g.resto`, `g.heridos`,
  `g.lanzacohetes`, `g.origenCiudad`, `g.retirada`, `c.recuperando`): se
  guardan con `guardar()` sin cambios.

## 6. Dependencias

- **Economía:** [economia.md](economia.md) (decidido el 2026-09-30): la cola
  de recuperación de §3.6 pasa a ser el taller, que repara los vehículos por
  puntos de daño y cobra metal y dinero (su F12); los soldados heridos siguen
  como aquí. El dinero de la ciudad desaparece: todo paga el tesoro.
- **Depende de:** [guerra.md](guerra.md) (combate terrestre, `combatir`,
  `combatirCiudad`, `volver`, `ofensiva`, alto el fuego y paz),
  [instalaciones-y-economia.md](instalaciones-y-economia.md) (dinero de las
  ciudades y tesoro, niveles de ciudad, hambre, defensas de ciudad y su tope,
  precios de `Simulacion.dinero`), [naciones-y-politica.md](naciones-y-politica.md)
  (prudencia y agresividad del presidente, guerras abiertas),
  [diplomacia.md](diplomacia.md) (cesiones de ciudades, alto el fuego).
- **Lo usan:** [guerra.md](guerra.md) (los grupos de ataque ya no se
  aniquilan casi nunca; menos cansancio por bajas definitivas),
  [instalaciones-y-economia.md](instalaciones-y-economia.md) (nuevo gasto de
  dinero; lanzacohetes fuera de la ciudad; soldados que vuelven sin pasar por
  el reclutamiento), [naciones-y-politica.md](naciones-y-politica.md) (la
  fuerza de una nación baja mientras tiene tropas en la cola, y eso pesa al
  decidir guerras). El jugador, cuando exista, usa los comandos
  `enviarGrupo` (con `lanzacohetes` y `retirada`) y `acelerarRecuperacion`.

## 7. Perillas de ajuste

| Constante (`Simulacion.recuperacion`) | Valor | Rango seguro | Efecto al moverla |
|---|---|---|---|
| Peso en la vida (soldado / tanque / lanzacohetes) | 1 / 9 / 40 | fijo | Mismos pesos que el combate; cambiarlos rompe "vida = fuerza". |
| `umbralBase` | 0,15 | 0,05–0,3 | Más alto: se retiran antes, vuelven más y toman menos. |
| `umbralPrudencia` | 0,2 | 0–0,3 | Cuánto distingue un presidente prudente de uno temerario. |
| Retirada preventiva (`suya × 0,1`) | sí | sí / no | Sin ella, 2–17 aniquilados por semilla; con ella, 0–4. |
| `recuperable` | 1,0 | 0,5–1,0 | Parte de las bajas que vuelve. Con 0,6 muere el 40 %. |
| `ritmo.soldados` | 25 × nivel/día (era 15) | 5–30 | Días de convalecencia; valor de mejorar la ciudad. Con 25, un asalto de 1 000–1 400 heridos tarda 14–28 días en una ciudad de nivel 2–3; con 15 tardaba 20–32 (ver §8). |
| `ritmo.tanques` | 0,5 × nivel/día | 0,2–1 | Ídem para tanques. |
| `ritmo.lanzacohetes` | 0,4 × nivel/día | 0,2–1 | 9 lanzacohetes: 8 días en nivel 3 (con 0,2, 15). |
| `precio` (soldado / tanque / lanzacohetes) | 1 / 22 / 33 | 25–100 % del precio nuevo | Por encima del 100 % nadie paga; muy bajo, esperar no tiene sentido. |
| `parteLanzacohetes` (asalto a ciudad / a instalación) | 0,5 / 0,25 | 0–1 | Cuántos lanzacohetes saca el NPC de su ciudad. |
| Presupuesto del NPC (`0,5` ciudad; `0,2 + 0,5 × agr` tesoro) | — | 0–1 | Cuánto acelera; hoy, con tesoros de miles, casi todo. |
| `diasMinimos` del NPC | 3 | 0–10 | No paga lo que llega solo en pocos días. |
| `reservaTesoro` | 60 (la de campamentos) | 0–500 | Lo que el presidente no toca. |

## 8. Criterios de aceptación

16 zonas (4 × 4), 500 días, semillas 4242, 1, 7, 99, 12345 y 2026. Entre
paréntesis, lo medido con el **código real** (antes, con el prototipo, si
cambia):

- Grupos aniquilados ≤ 10 % de los grupos de ataque (0–9 %: 3/60, 3/47, 0/48,
  3/35, 4/89, 2/60). Antes del cambio: 20–39 % (21/68, 10/41, 18/67, 19/52,
  36/93, 10/50). **Cumple.**
- Entre 5 y 40 retiradas por semilla (6–39). **Cumple.**
- Vida mediana al retirarse entre 0,15 y 0,35 (0,19–0,27). **Cumple.**
- Entre 3 y 20 instalaciones tomadas por tierra (4–15). Antes: 9–16. **Cumple.**
- Soldados totales (ciudades e instalaciones) el día 500 dentro de ±10 % de
  antes (−1,6 % a +0,6 %). **Cumple.**
- Sin acelerar, el p90 de lo que tarda en vaciarse una cola ≤ 15 días y el
  máximo ≤ 30. Con `ritmo.soldados = 15` no cumplía: p90 8–31 (4242: 31, 99:
  18, 7: 16) y máximo 19–32; las colas largas eran asaltos grandes que
  volvían a ciudades de nivel 2–3 (1 402 heridos en Lonu, nivel 3, 32 días).
  **Con 25 y P7** (código real): p90 6–12 y máximo 11–19 en cinco semillas;
  **la 99 no cumple el p90** (26): en 500 días solo tiene 6 colas, así que el
  p90 es la más larga, 256 heridos en una ciudad de nivel 2 (6 días de
  ritmo) parados 21 días por hambre. El máximo (26) cumple en todas. Con el
  NPC acelerando, p90 2 y máximo 2–16, salvo la 99 (26: el presidente no
  paga porque ni está en guerra ni la ciudad está en la frontera).
- El NPC gasta en acelerar en todas las semillas (2 590–5 554 por semilla;
  máximo por nación 1 527–3 357). **Cumple.**
- Caso del dueño: un grupo con 10 lanzacohetes que se retira vuelve con 1–3
  (vuelve con 2 en la semilla 4242), y los averiados vuelven en
  `ceil(averiados / (0,4 × nivel))` días (8 en nivel 4: 5 días). **Cumple.**
- Determinismo: dos ejecuciones iguales dan el mismo `guardar()`, y guardar a
  mitad (día 150), cargar y seguir da lo mismo (semillas 4242, 1, 7, 99,
  12345 y 2026, 300 días). También guardando justo con colas, retiradas y
  heridos en viaje en el estado (4242 día 65; 99 días 138, 139 y 176). Una
  partida de la versión 11 carga en la 12 y sigue. **Cumple.**
- Sin cambios en lo ya aprobado (arnés a 300 días): campamentos 123–155
  (antes 133–155), guerras 5–13 (antes 5–15), días con acción en los últimos
  200: 81–159 (antes 82–152). A 500 días: guerras declaradas 12–26 (antes
  11–28), días con acción 204–371 (antes 209–357).
- Coste: ~5 ms por día simulado a 300 días, igual que antes (medido en serie,
  alternando las dos versiones; la máquina tenía otra carga).

**No medido:** cómo se ve la barra en pantalla (falta dibujarla); cuántos
lanzacohetes pierde una ciudad defendiendo mientras los suyos están fuera;
efecto en el número de paces. La cesión de una ciudad en un tratado no se
puede dar hoy (desde la versión 11 solo hay capitales y la capital no se
cede): el borrado de la cola está programado pero no se ha visto en partida;
el de la toma de una capital, sí (probado a mano).

## Decisiones del dueño

1. **Lanzacohetes:** opción A. Los grupos que salen de una ciudad se llevan
   parte de sus lanzacohetes; cada uno lucha como 40 soldados y no gasta
   misiles; la ciudad dispara y defiende menos mientras están fuera; los de
   fuera y los que se reparan cuentan para el tope. Medido: 3–16 grupos por
   semilla llevan lanzacohetes (6–33 en total).
2. **Recuperable = 1:** vuelve todo lo perdido.
3. **Retirada preventiva:** sí.
4. **Reparto proporcional del daño** entre soldados, tanques y lanzacohetes:
   sí (sustituye la regla del 40 % de perder un tanque del atacante).
5. **Precio de acelerar:** 1 / 22 / 33; ritmos de este documento.
6. **Los defensores no se retiran:** las guarniciones de ciudades, bases y
   campamentos luchan hasta el final, como antes.
7. **Umbral del jugador:** campo `retirada` del comando; sin él, el del
   presidente. Aún sin interfaz.

## Cambios para el programador de simulación

Hechos (1–9). Detalles que las reglas no decían y se resolvieron así:

- El comando de acelerar usa `tropa` (no `tipo`).
- Tras una toma, el mismo grupo vuelve a casa como `regreso` con 0 soldados
  sanos, sus heridos y (si era una instalación) sus lanzacohetes; si no lleva
  nada, desaparece.
- Al llegar, los lanzacohetes (sanos y averiados) que no quepan en el tope de
  la ciudad que los recibe se desguazan: solo pasa si la ciudad de origen cayó
  y vuelven a otra.
- Sin nación del jugador en la simulación, el presidente decide pagar en todas
  las naciones.

Pendiente (10): dibujo en `mundo/mundo.lua` y `main.lua`: barra, rótulo "En
retirada", líneas del panel y botón de acelerar.

## Cómo se midió

Primero, un prototipo (`retirada.lua` en el scratchpad de la sesión) que carga el juego como el
arnés habitual (LuaJIT con un `love` vacío, 16 zonas de −2 a 1) y sobrescribe
desde fuera `enviarGrupo`, `enCamino`, `combatir`, `combatirCiudad`, `llegada`,
`tomarCiudad` y `avanzarDia`. `escenario.lua` reproduce el caso de los 10
lanzacohetes. Diferencias con estas reglas: en el prototipo los heridos y los
lanzacohetes de una toma llegan a casa al momento (no viajan), no se impide
acelerar una ciudad sitiada y no se borra la cola al ceder una ciudad.

Después, con el código real y sin cambiar reglas: `medirRet.lua` (cuenta
desde fuera grupos, aniquilados, retiradas, tomas, colas y gasto; con
`SINACELERAR=1` rechaza el comando de acelerar), `escenarioReal.lua` (el caso
de los 10 lanzacohetes por el comando `enviarGrupo`), `det16.lua` y
`detRet.lua` (determinismo y guardar/cargar), `migrar.lua` (partida de la
versión 11) e `invariantes.lua` (tope y colas sin negativos, día a día, 500
días: sin fallos).

| Variante (500 días) | Grupos de ataque | Aniquilados | Retiradas | Tomas | Vida mediana al retirarse | Cola sin acelerar, p90 / máx. (días) | Gasto NPC por semilla |
|---|---|---|---|---|---|---|---|
| Antes del cambio (código real) | 41–93 | 10–36 | 0 | 9–16 | — | — | — |
| **Implementado** (código real, NPC acelera) | 35–89 | 0–4 | 6–39 | 4–15 | 0,19–0,27 | con acelerar 2–10 / 2–16 | 2 590–5 554 |
| **Implementado**, sin acelerar | 37–83 | 0–3 | 6–21 | 4–15 | 0,19–0,29 | 8–31 / 19–32 | 0 |
| Umbral, recuperable 1, NPC acelera | 37–95 | 2–17 | 5–17 | 9–18 | 0,05–0,22 | — | 1 858–9 244 |
| Umbral + preventiva, NPC acelera (**propuesta**) | 35–89 | 0–4 | 6–39 | 3–13 | 0,19–0,27 | — | 2 590–5 554 |
| Umbral + preventiva, sin acelerar | 37–83 | 0–3 | 6–21 | 4–15 | 0,19–0,29 | 3–13 / 19–29 | 0 |
| Umbral, sin acelerar | 37–87 | 2–14 | 6–16 | 8–15 | 0,05–0,21 | 4–12 / 10–26 | 0 |
| Umbral, recuperable 0,6, NPC acelera | 40–93 | 0–16 | 6–18 | 8–15 | 0,05–0,20 | — | 1 820–4 330 |

Lanzacohetes: los grupos del NPC salen casi siempre de bases (de 8–17 asaltos a
ciudades por semilla, solo 0–6 salen de una ciudad), así que en 500 días solo
3–16 grupos por semilla llevaban lanzacohetes, 1–4 de media. Con P7 las bases
también prestan (opción L1): 11–51 grupos por semilla llevan lanzacohetes en
500 días (6–40 de ellos salen de una base). El caso "10
lanzacohetes" lo vivirá sobre todo el jugador; si se quiere verlo entre NPC,
la perilla es `parteLz` o dejar que los asaltos a ciudades salgan de la
capital.

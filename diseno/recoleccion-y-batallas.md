# Recolección y batallas

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Documento para Andrés (simulación) y Valeria (mundo y vista). Estado:
**propuesta, sin programar.** Lo marcado "hoy" es lo que hace el código en la
versión 18 del guardado (HEAD 83aaf4c). Lo marcado "propuesta" es lo que cambia.

Sale de la redefinición del dueño del 2026-09-27: los recursos no se producen
solos, sino que se recolectan con tropas; las minas se agotan; nadie patrulla; en
el mapa 2D no hay ataques a distancia, y toda batalla es de campo (en 3D si el
jugador entra y simulada si no). Añadido del dueño del mismo día: el
territorio y las banderas dan un bonus de recolección (3.3), y los **templos**
quedan anotados como objetivo de una fase posterior (sección 10).

Afecta a: `ejecutar`, `enviarGrupo`, `moverGrupos`, `llegada`,
`detectarChoques`, `combatirChoque`, `combatirCiudad`, `producirRecursos`,
`construirExtraccion`, `planearCampamento`, `mantenerCampamentos`, `guerra`,
`ofensiva`, `escaramuza`, `refuerzos`, `salva`, `incursion`, `golpeCiudad`,
`resolverImpactos`, `fabricarEnCiudad`, `yacimientosEn`, `guardar` y
`cargar`. En la vista: `main.lua` (`vigilarBatallas`), `Recursos.dibujar` y
`estandartes.lua`.

---

## 1. Resumen

Un yacimiento ya no da nada por estar en tu territorio: hay que mandar un
**grupo a recolectar**. El grupo viaja hasta la mina, recolecta cada día según
cuánta gente y cuántos vehículos lleva, vuelve a casa cuando se llena, cuando se
agota la mina o cuando lo retiras, y entrega la carga al llegar. Cada mina tiene
una **cantidad finita**; al agotarse, se cierra un tiempo y después vuelve a
estar llena. Mientras un grupo recolecta, su icono ocupa la mina y **cualquiera
que esté en guerra con él puede atacarlo allí**, sea o no su territorio. Si
pierde, pierde la carga. En el mapa 2D solo se mueve lo que alguien manda, y
desaparecen los misiles, las incursiones y los golpes a ciudades: **toda batalla
es de campo**. El jugador elige si la pelea en 3D o si se resuelve sola con una
regla determinista, y puede entrar a mitad.

## 2. Fantasía del jugador

- "Mando 300 soldados y 4 tanques a la mina de metal del valle. En seis días
  vuelven cargados: eso es mi metal del mes."
- "Su bandera está sobre la mina de petróleo del vecino. Si me pillan, pierdo la
  carga, pero si no, me ahorro diez días de viaje."
- "Veo el escudo de otra nación sobre una mina de oro. Tiene 80 soldados.
  Mando 200 a quitársela."
- "Me atacan la capital con todo el ejército fuera. Retiro a los mineros, los
  traigo a casa y entro a la batalla en 3D con lo que llegue."
- "Mi capital está a 0 de vida, pero la batalla sigue: si mis tanques ganan en
  la plaza, no me saquean."

## 3. Reglas

### 3.1 Recolectar

1. **Comando nuevo:** `ejecutar({ tipo = 'recolectar', nacion, desde,
   yacimiento, soldados, tanques, lanzacohetes })`. `desde` es una ciudad propia
   (o un campamento, ver 3.3). Es la misma entrada para el NPC y para el
   jugador.
2. **Validación.** Si falla algo, devuelve `false` y no sale nadie:
   - el yacimiento existe (`e.depositos[id]`) y **no está cerrado**
     (`agotadaHasta` ≤ día de hoy);
   - hay camino por tierra (`trazar`), como en `enviarGrupo`;
   - al menos una unidad sana (no hay mínimo, como en `enviarGrupo` hoy);
   - **no importa de quién sea la tierra**: se puede recolectar en tierra
     propia, de nadie o de otra nación;
   - no hace falta líder (es un banderín, como un convoy).
3. **Grupo:** `mision = 'recolectar'`, `yacimiento = id`, `fase = 'ida'`,
   `carga = 0` y `tipoCarga = tipo del yacimiento`. Tiene vida, umbral de
   retirada y heridos, como un grupo de ataque (`vidaMax`, `umbral`,
   `heridos`), porque se le puede atacar.
4. **Ida:** viaja a `velocidadEjercito` (9 000 px al día, como hoy).
5. **En la mina** (`fase = 'recolectando'`): no se mueve. Cada día, después de
   mover a todos los grupos, recolecta F1, sin pasar de su hueco de carga (F2)
   ni de lo que queda en la mina (F3). Si la mina tiene varios grupos, se
   reparte lo que queda en proporción al trabajo de cada uno (F4).
6. **Vuelta automática** (`fase = 'vuelta'`, se usa `volver`) en cuanto pase
   una de estas cosas:
   - el grupo está lleno (`carga ≥ capacidad`);
   - la mina se agota;
   - pierde una batalla (con la carga perdida, ver 3.5).
7. **Retirar:** `ejecutar({ tipo = 'retirar', nacion, grupo })` pone al grupo
   en vuelta con la carga que lleve. Vale en cualquier fase (en la ida, vuelve
   vacío).
8. **Entrega:** al llegar a casa (la llegada `regreso` de hoy), la carga entra
   en la nación con `ingresar` (almacén o bóveda hasta el tope y el resto
   afuera):
   - metal y petróleo al almacén;
   - **oro:** `carga × precioOro` (8) de dinero;
   - **comida:** al granero de la ciudad a la que llega, hasta su tope (lo que no
     cabe se pierde, como hoy).
9. **Redirigir:** `ejecutar({ tipo = 'redirigir', nacion, grupo, destino })`
   manda a un grupo propio que está fuera a otro sitio propio (por ejemplo, a
   defender la capital). Conserva su carga y la entrega al llegar si el destino
   es una ciudad o un campamento.

### 3.2 Yacimientos finitos

- Cada yacimiento tiene una **reserva** (F5) que depende de su tipo y de su
  riqueza. Nace llena.
- **Estado guardado:** solo se guardan los yacimientos que alguien tocó:
  `e.minas[id] = { queda, agotadaHasta }`. Sin entrada, está llena y abierta.
  Así el guardado no crece con el mundo.
- **Agotada:** cuando `queda` llega a 0, la mina se **cierra** durante
  `enfriamiento` días (F6). Cerrada, no admite órdenes `recolectar`. Al
  terminar, vuelve con la reserva completa y su entrada se borra de `e.minas`.
- **Regeneración:** una mina a medias que nadie recolecta recupera el 1 % de su
  reserva al día (F7) hasta llenarse. Llena, se borra su entrada.

### 3.3 Qué pasa con lo que había (propuesta; ver pregunta 1)

- **Extracciones:** desaparecen. Su papel (sacar recursos de un yacimiento) lo
  hacen ahora los grupos. En la carga de partidas viejas, su guarnición vuelve a
  la ciudad propia más cercana y la extracción se borra.
- **Campamentos:** dejan de producir (se quita `campamento.produce` y la
  explotación del yacimiento cercano). Pasan a ser **puestos de acopio**: dan
  territorio como hoy y un grupo puede salir de él y entregar en él. Lo que se
  entrega en un campamento entra en el almacén nacional en ese momento (no hay
  transporte aparte). Así acortan el viaje hacia minas lejanas.
- **Mantenimiento del campamento:** hoy cuesta
  `1,0 × (d / 5000)²` de petróleo al día. Con campamentos lejos, eso ya son
  **61–95 de petróleo al día por nación** entre los días 301 y 500 (medido),
  imposible de recolectar. Propuesta: pasa a una cuota fija de
  **0,5 de petróleo al día** por campamento, sin distancia.
- **Talleres de la ciudad** (`metalCiudad`, 0,3 de metal al día) y los cultivos
  de la ciudad (`cultivoRadio`) **se quedan**: son la ciudad, no una mina, y
  evitan que una nación sin nadie fuera quede bloqueada a 0. Los impuestos se
  quedan igual. Es una diferencia con "nada produce solo" que dejo marcada.
- **Territorio y banderas (decisión del dueño, 2026-09-27: dan bonus de
  recolección).** Siguen igual (celdas, bloques, `dueno`). Ahora sirven para:
  - **recolectar más:** si la celda del yacimiento es de tu nación (la cubre tu
    capital, tu campamento o tu bandera), tus recolectores sacan un **+25 %**
    (`ventajaTerritorio` = 1,25 en F1);
  - pelear mejor ahí (`ventajaDefensa` = +10 %, que ya existe en los choques y
    ahora vale también en las minas);
  - que la IA prefiera sus minas (F10).
- **A quién se aplica el bonus (propuesta):** **solo a los recolectores del
  dueño del territorio.** Un extranjero que recolecta en tu tierra saca el ritmo
  normal (× 1). Así:
  - plantar una bandera sobre una mina te da ventaja a ti, no al vecino;
  - recolectar en tierra ajena sigue permitido (lo pidió el dueño), pero sale
    peor que en la propia.
  Se descartan dos alternativas:
  - que cualquiera que recolecte en tu tierra tenga el bonus: la bandera
    beneficiaría también a quien te roba;
  - que el extranjero tenga una penalización: sería un castigo que el dueño no
    ha pedido.
  Si se quiere algo más fuerte, la perilla es `ventajaTerritorio` (1,1–1,5).
  La regla "la extracción deja de producir si cae la bandera" (decisión 1 de
  `territorio-y-capitales.md`, §9) deja de tener objeto: ya no hay extracciones.

### 3.4 Sin patrullas

- En el mapa 2D solo existe un grupo si alguien lo ha mandado con `ejecutar`
  (`recolectar`, `enviarGrupo`, `redirigir`, `campamento`, `enviarDefensas`).
- Lo único que se mueve sin una orden nueva es la **consecuencia de una orden**:
  la vuelta al llenarse o agotarse la mina, el regreso tras ganar y la retirada
  tras perder.
- Hoy la IA manda refuerzos llamando directamente a `enviarGrupo`
  (`refuerzos`). Propuesta: pasa por `ejecutar`, como toda decisión NPC. El
  jugador ya no tiene nada automático hoy (`refuerzos` y `ofensiva` miran
  `n.jugador`).

### 3.5 Ataque a recolectores

1. **Orden:** `ejecutar({ tipo = 'enviarGrupo', mision = 'atacar', objetivo =
   <id de yacimiento> })`. La validación de hoy (`puedeAtacar`) acepta un
   yacimiento como objetivo **sin mirar fronteras**.
2. **Requisito:** las dos naciones están en guerra abierta (fase `tension`), la
   misma regla que los choques de hoy (`enGuerraAbierta`). Con quien estás en
   paz se comparte la mina (ver pregunta 3).
3. **Al llegar:** si en la mina hay grupos recolectando de naciones en guerra
   abierta con el atacante, empieza una **batalla** (3.7) entre el atacante y
   todos ellos. Mientras dura, nadie recolecta en esa mina.
4. Si no hay nadie contra quien pelear, el atacante vuelve a casa (`volver`).
   No se queda esperando: eso sería patrullar.
5. Un grupo que ya recolecta en la mina también puede recibir la orden `atacar`
   contra ella: la batalla empieza al día siguiente sin moverse.
6. **Si pierden los recolectores** (aniquilados o en retirada): pierden toda su
   carga. **Propuesta:** el ganador se lleva lo que quepa en su hueco de carga
   (F2) y el resto vuelve a la mina (`queda` sube). Ver pregunta 2.
7. **Si gana el recolector:** sigue recolectando al día siguiente con lo que le
   quede sano.
8. Un grupo en ida o en vuelta puede chocar con un ejército enemigo por el
   camino con la regla de choques de hoy: `puedeChocar` admite también
   `mision = 'recolectar'` y el choque se da si al menos uno de los dos va a
   atacar, como hoy.

**Icono de la mina (Valeria y Camila).** Encima del icono del yacimiento:

- nadie: el icono de hoy;
- recolectando: el **escudo de la nación del grupo** (el de
  `estandartes.lua`) y una barra de lo que queda en la mina;
- varias naciones: el escudo de la que más trabajo tiene, con el número de
  naciones al lado;
- en batalla: dos espadas cruzadas;
- cerrada: el icono en gris con los días que faltan.

Para eso, `yacimientosEn` devuelve además `queda`, `reserva`, `agotadaHasta` y
`recolectores = { { nacion, trabajo } }`.

### 3.6 Guerra: qué se quita

Se quitan del mapa 2D **todos los ataques a distancia**:

- los comandos `salva` e `incursion`;
- `escaramuza`, `golpeCiudad`, `impactarCiudad`, `crimenDeGuerra`,
  `interceptar`, `programarImpacto` y `resolverImpactos`;
- en `ofensiva`, la salva y la incursión (se queda solo la misión terrestre);
- `danarInstalacion` por misiles (una instalación solo pierde vida en una
  batalla de campo o por desabasto).

Medido hoy, en 500 días por semilla (1 / 4242 / 12345), desaparecen 454 / 333 /
330 salvas, 149 / 107 / 108 incursiones y 17 / 12 / 16 golpes a ciudades.

**Lo que se queda:** misiles, interceptores y aviones siguen en el estado
porque los usará la batalla 3D. Mientras no los use, `fabricarEnCiudad` deja de
fabricarlos (no sirven para nada y gastan metal y petróleo). Los lanzacohetes y
las baterías de las ciudades siguen pesando en la defensa (F3 de
`territorio-y-capitales.md`).

### 3.7 Batallas: una sola regla

**Batalla** es un objeto nuevo: `e.batallas[id] = { lugar, x, y, bandos = {
atacante = { grupos }, defensor = { grupos, sitio } }, dia, enEscena }`.

- Se crea al llegar un ataque a un sitio (capital, campamento, bandera) o a una
  mina, o al trabarse dos grupos (el `choque` de hoy pasa a ser una batalla de
  dos).
- Un grupo propio que llega al lugar se **suma a su bando** (un aliado, lo
  mismo).
- Termina cuando un bando no tiene nada sano o se ha retirado entero.

**Resolución sin ver (NPC contra NPC o jugador que no entra).** Es la regla F8
de los choques de hoy, extendida a bandos (F8 de este documento). Cada día:

1. Cada bando golpea con la suma de la vida de sus grupos, más la guarnición y
   las defensas del sitio si defiende uno (`suya` de `combatirCiudad`).
2. Las bajas al otro bando se reparten entre sus grupos en proporción a su vida
   y se aplican con `herirGrupo`. Las del sitio, como hoy.
3. Cada grupo comprueba `debeRetirarse` y se va por su cuenta.
4. El azar sale de `Ruido.azar(Ruido.hash(semilla, día, 91))` en el orden fijo
   de siempre (batallas por id y grupos por id).

**Por qué no usar la IA de la escena 3D para las batallas que nadie ve.**

- La escena usa `love.*`, pasos de tiempo variables, coma flotante con
  físicas y su propio azar. No da el mismo resultado en dos máquinas ni corre
  en un servidor sin LÖVE.
- Tampoco escala: con decenas de batallas NPC a la vez, simular cada una
  unidad por unidad cuesta cientos de veces más que la regla (hoy la
  simulación entera tarda unos 30 ms por día en el arnés).
- Si la simulación dependiera de ella, se rompería el determinismo y el
  guardado/carga daría otro mundo.

**Solución propuesta (en tres pasos).**

1. **Autoridad:** la regla F8 decide toda batalla que nadie ve. Es la única que
   corre en el servidor.
2. **Alinear:** Valeria prepara un modo sin ventana de la escena, IA contra IA,
   con paso fijo y semilla fija. Con 200 batallas de composiciones variadas se
   ajustan `golpeMin`, `golpeMax` y los pesos de F8 hasta que la regla y la
   escena coincidan en el ganador en al menos el 80 % de los casos y en las
   bajas con un margen de ±25 % (criterio 9). Si la IA 3D cambia, se repite.
3. **Batalla vista:** es la que ya decidió el dueño
   (`ejercitos-en-el-mapa.md`, 3.7): la escena corre en la máquina del jugador
   y manda `resolverBatalla`. El servidor comprueba los límites. La meta sigue
   siendo una lógica de batalla determinista y sin dibujo que el servidor pueda
   correr con las órdenes del jugador.

### 3.8 Aviso y defensa del jugador

1. **Aviso previo** (solo informativo): cuando un grupo enemigo con misión
   `atacar` hacia algo tuyo (sitio, mina con tus recolectores o grupo) está a
   `avisoDias` (1) día de llegar: "El ejército de X va hacia Y: llega en N
   días, poder P".
2. **Al empezar la batalla**, un pregón con dos botones:
   - **Defender en 3D:** se abre la escena con tus unidades sanas en el lugar;
   - **No defender (se resuelve sola):** sigue con F8.
   Si no eliges en `ESPERA_BATALLA` segundos, se toma **No defender**. Hoy
   `vigilarBatallas` entra solo a la escena: eso cambia.
3. **Entrar a mitad:** la batalla sigue en la lista de "Batallas en curso" del
   panel con el botón "Entrar". Al entrar:
   - la simulación marca `enEscena = jugador` y deja de aplicar F8 a esa
     batalla desde ese día (se congela en su estado);
   - la escena se genera con lo **sano de ese momento** en cada bando. Los
     caídos ya no están y los heridos no pelean;
   - la simulación no guarda posiciones, así que cada bando se despliega de
     nuevo en su lado;
   - al acabar, `resolverBatalla` aplica las bajas y la batalla se cierra;
   - el mundo sigue a `ritmoBatalla`, y en línea hay un tope de
     `diasBatallaMax`, como ya dice `ejercitos-en-el-mapa.md`.
4. **Traer tropas:** con `redirigir` (3.1.9) se llama a los recolectores o a
   cualquier grupo propio. Al llegar al lugar de la batalla se suman al bando
   defensor. Si estás dentro de la escena, entran como refuerzo por el borde más
   cercano a su llegada.
5. **Elegir enemigo:** si hay varias batallas contra ti a la vez, la lista
   permite elegir en cuál entrar. Dentro de una batalla, todos los atacantes
   del lugar están en la escena.

### 3.9 Capital a 0 de vida durante la batalla

- **Hoy:** `combatirCiudad` da la batalla por perdida si `c.vida` llega a 0 **o**
  si la guarnición se queda sin soldados ni tanques.
- **Propuesta:** la vida a 0 **no termina** la batalla, ni en 3D ni simulada.
  A 0:
  - las defensas fijas (lanzacohetes y baterías) dejan de golpear, porque la
    ciudad está en ruinas;
  - la guarnición y los grupos defensores siguen peleando.
- La batalla termina cuando un bando no tiene nada sano o se retira entero.
- **Si gana el atacante:** se aplica la derrota de la capital ya diseñada:
  - `c.vida = 9` (sube a 9 si estaba a 0);
  - saqueo de todo lo de afuera (`saquearCapital`);
  - el atacante vuelve con el botín.
- **Si gana el defensor:** la vida se queda donde esté, aunque sea 0, y no hay
  saqueo. Con 0, la capital produce y defiende al 40 % (`f(0) = 0,4`, F6 de
  `territorio-y-capitales.md`) hasta que la repare con `reparar`.

### 3.10 IA de los NPC

Todo pasa por `ejecutar`. El presidente piensa cada día y no hay tope de
grupos: solo manda a los soldados que le sobran.

**Mandar a recolectar** (`planearRecoleccion`, cada día):

1. **Necesidad por recurso:** `faltan = reservaObjetivo − (disponible + en
   camino)`, con `reservaObjetivo` = el consumo diario del recurso × 20 días (F9).
   El consumo diario es la media de los últimos 10 días. El oro solo cuenta si el
   tesoro está por debajo de `10 × reservaTesoro`.
2. **Soldados libres:** los de la capital (y de los campamentos) por encima de
   la **guarnición mínima** (F9 de `ejercitos-en-el-mapa.md`). Con una guerra
   abierta, la guarnición mínima se multiplica por 1,5.
3. **Mina:** la de mayor valor F10 entre las abiertas que conoce (a menos de
   `alcanceMeta`, 60 000 px, de la capital).
4. **Tamaño:** los soldados justos para cargar `faltan` en un viaje (F11), sin
   pasar de los libres. Si con los libres no llega, manda lo que haya.
   Tanques solo si le sobran por encima de su guarnición.
5. Repite con el siguiente recurso y la siguiente mina mientras queden libres y
   algo que falte.

**Atacar recolectores** (dentro de `ofensiva`, en guerra abierta):

- Candidatas: las minas con recolectores enemigos a menos de `alcanceAtaque`
  (130 000 px) de un sitio propio.
- Ataca si su ejército disponible cumple
  `poder propio ≥ poder recolectores × (1,6 − agresividad)` (F12). Así un
  presidente agresivo (0,9) ataca con 0,7 veces el poder del rival y uno
  prudente (0,1), con 1,5 veces.
- Prefiere la mina con más carga enemiga y la más cercana.
- Solo "ve" el poder de los recolectores si están a menos de `alcanceCodicia`
  (80 000 px) de un sitio suyo (lo que ven sus fronteras).

**Defender lo suyo:**

- **Recolectores amenazados** (un enemigo con `atacar` hacia su mina, a 1 día o
  menos): si `poder recolectores < poder atacante × (0,8 + prudencia)`, los
  retira (`retirar`). Si no, se quedan. Si tiene un ejército libre con más poder
  que el atacante y llega antes, lo manda a la mina.
- **Capital atacada:** redirige a casa a todos sus grupos que lleguen antes de
  3 días. Los demás siguen con lo suyo.

### 3.11 Reglas de la casa

- **Sin turnos ni topes:**
  - no hay tope de grupos recolectando, ni de soldados por mina, ni de minas por
    nación;
  - lo único que frena es la reserva de la mina, el viaje y los soldados que
    dejas sin defender la ciudad;
  - el "un convoy a la vez" de `construirExtraccion` desaparece con las
    extracciones;
  - la IA piensa cada día: es su ritmo, no un límite.
- **NPC = jugador:** los comandos `recolectar`, `retirar`, `redirigir`,
  `atacar` sobre una mina y `resolverBatalla` son los mismos para los dos. La
  única diferencia es quién decide si una batalla se ve.
- **Determinismo:**
  - F1 a F7 no usan azar;
  - F8 usa el azar del día en orden fijo;
  - `e.minas` y `e.batallas` se recorren con `ordenadas`;
  - el reparto de la mina entre grupos (F4) va en orden de id y el sobrante de
    redondeo va al de id menor;
  - la escena 3D nunca escribe en la simulación más que por `resolverBatalla`.

### 3.12 Qué cambia en el código y en el guardado

| Hoy | Propuesta |
|---|---|
| `producirRecursos`: campamentos (fijo + yacimiento) y extracciones producen solos | Solo mantenimiento. La entrada viene de la llegada de recolectores (3.1.8) |
| `construirExtraccion`, misión `construir` de extracciones | Se borran |
| `campamento.produce`, `yacimientoLibreCerca` en `llegada` | Se quitan. El campamento pasa a puesto de acopio (3.3) |
| Mantenimiento `1,0 × (d/5000)²` de petróleo | 0,5 fijo (3.3) |
| — | `ejecutar`: `recolectar`, `retirar`, `redirigir`. `atacar` acepta un yacimiento |
| — | `recolectarDia()` tras `moverGrupos` en `avanzarDia` |
| `detectarChoques`/`combatirChoque` (dos grupos) | `e.batallas` con bandos. El choque es una batalla de dos (3.7) |
| `combatirCiudad`: pierde a vida 0 | La vida a 0 no termina la batalla (3.9) |
| `salva`, `incursion`, `escaramuza`, `golpeCiudad`, impactos | Se borran (3.6) |
| `refuerzos` llama a `enviarGrupo` | Pasa por `ejecutar` (3.4) |
| `fabricarEnCiudad` hace misiles, interceptores y aviones | Solo tanques mientras la 3D no use el resto |
| `yacimientosEn` devuelve dueño y explotación | Además `queda`, `reserva`, `agotadaHasta`, `recolectores` |
| `vigilarBatallas` entra solo a los N segundos | Por defecto "No defender" + lista de batallas en curso (3.8) |

**Guardado: versión 19.** En `cargar`, desde la 18:

- `e.minas = {}` y `e.batallas = {}`;
- cada extracción se borra, y su guarnición (soldados y tanques) se suma a la
  ciudad propia más cercana;
- los campamentos se conservan (sin producción);
- los choques abiertos (`g.choque`) pasan a batallas de dos, en orden de id;
- los impactos pendientes se borran;
- los grupos `construir` de extracciones vuelven a casa (`volver`).

Grupo `recolectar` nuevo: `yacimiento`, `fase`, `carga`, `tipoCarga`, más los
campos de vida de los grupos de ataque.

---

## 4. Fórmulas

Constantes en `Simulacion.recoleccion` salvo que se diga otra cosa.

**F1. Ritmo de recolección de un grupo (unidades al día).**
`R = kRitmo × trabajo × minas × ventajaTerritorio × bonusTemplo`

- `trabajo = soldados × 1 + tanques × 3 + lanzacohetes × 2` (solo lo sano);
- `kRitmo = 0,03`;
- `minas` = `niveles[nivel de la capital].minas` (1 a 2), el mismo multiplicador
  que hoy tienen las extracciones;
- `ventajaTerritorio` = 1,25 si la celda del yacimiento es de la nación del
  grupo (`duenoCelda`) y 1 si es de nadie o de otra nación;
- `bonusTemplo` = 1 hasta que existan los templos (ver "Objetivos: templos").
- Rango: de 0,03 (1 soldado, nivel 1, tierra ajena) a cientos (sin tope).
- Ejemplo: 300 soldados, 4 tanques y 1 lanzacohetes, capital de nivel 3
  (`minas` 1,5), en tierra propia → trabajo 314 → R = 314 × 0,03 × 1,5 × 1,25 =
  **17,7 al día**.
- Ejemplo del dueño: 10 soldados, nivel 2, tierra ajena → R = 10 × 0,03 × 1,25
  = **0,375 al día**.

**F2. Capacidad de carga.**
`capacidad = soldados × 0,3 + tanques × 2 + lanzacohetes × 5` (lo sano al salir;
si hay bajas, baja y lo que sobra de carga se pierde).

- Los soldados cavan y cargan poco; los vehículos cargan mucho y cavan poco. Un
  grupo mezclado llena antes.
- Días para llenarse: `capacidad / R`. Con solo soldados es
  `0,3 / (0,03 × minas × ventaja)`, es decir, **8 días** en nivel 2 y tierra
  ajena y **4,6 días** en nivel 4 y tierra propia. No depende del número de
  soldados: más soldados cargan más en los mismos días.
- Ejemplo de F1: capacidad = 90 + 8 + 5 = 103 → 103 / 17,7 = **5,8 días**.
- Ejemplo del dueño: 10 soldados → 3 de carga, en 8 días.

**F3. Lo recolectado hoy por un grupo.**
`hoy = min(R, capacidad − carga, parte de la mina)`

**F4. Reparto de la mina entre varios grupos.**
Si `Σ R > queda`, cada grupo recibe `queda × R_i / Σ R` (en orden de id; el
sobrante de redondeo va al de id menor). Si no, cada uno recibe su `R`.

**F5. Reserva de un yacimiento.**
`reserva = riqueza × reservaBase[tipo]`, con `reservaBase = { metal 250,
petroleo 250, comida 250, oro 60 }`.

- Metal de riqueza 2 = 500. Oro de riqueza 2 = 120, que dan 960 de dinero.
- Contra el consumo medido de metal entre los días 301 y 500 (6,4–8,2 al día
  por nación, ver "Números medidos"), una mina de metal de riqueza 2 da para
  unos 60–80 días.

**F6. Enfriamiento al agotarse.**
`enfriamiento = 20 + 10 × riqueza` días (30, 40 o 50). Una mina rica tarda más
en volver.

**F7. Regeneración de una mina a medias sin recolectores.**
`queda ← min(reserva, queda + 0,01 × reserva)` al día. De 0 a lleno,
100 días. Solo si nadie recolecta ni hay batalla en ella ese día.

**F8. Batalla sin ver (un día).**
Para cada bando B contra el bando O:
`bajasEnO = floor(golpe(B) × azar(golpeMin, golpeMax) × ventaja(B))`

- `golpe(B) = Σ vidaGrupo` de sus grupos, más `suya` del sitio si lo defiende
  (soldados + 9·tanques + 40·lanzacohetes; con vida > 0, también las
  baterías con peso 20);
- `golpeMin = 0,06` y `golpeMax = 0,12` (los de hoy; se ajustan con la
  alineación de 3.7);
- `ventaja(B) = 1 + ventajaDefensa` (0,1) si pelea en su territorio y
  `× efectoVida(c.vida)` si defiende una capital (como hoy).
- Reparto en O: cada grupo recibe `bajasEnO × vida_i / Σ vida`. La guarnición
  del sitio cuenta como un grupo más.
- Ejemplo (cuenta de la fórmula con el azar fijo en 0,09, no una medición): 400
  soldados atacan a 300 soldados recolectores en tierra de nadie.
  - Día 1: los atacantes causan 36 bajas y reciben 27. Quedan 373 contra 264.
  - Días 2 a 7: 350–231, 330–200, 312–171, 297–143, 285–117 y 275–92.
  - Día 8: 267 contra 68. Los recolectores bajan del umbral de un presidente
    medio (0,15 + 0,2 × 0,5 = 0,25, es decir, 75 soldados) y se retiran sin la
    carga.
  - Una batalla igualada dura **alrededor de una semana**. Con el azar real,
    la duración **no está medida**.

**F9. Reserva objetivo del NPC.**
`reservaObjetivo[r] = consumoDiario[r] × diasReserva`, con `diasReserva = 20`.

- Ejemplo: gasto medido de metal de 7 al día → quiere 140 de metal entre
  almacén, afuera y en camino.

**F10. Valor de una mina para el NPC.**
`valor = necesidad[tipo] × min(1, queda / cargaDeseada) × ventajaTerritorio /
(1 + viajeDias) × seguridad`

- `viajeDias = distancia / 9000`;
- `seguridad = 0` si un ejército enemigo en guerra con más poder que el grupo
  que mandaría está a menos de 1 día de la mina, y 1 si no;
- `necesidad`: la de `necesidades` de hoy; el oro, como en F12 de
  `territorio-y-capitales.md`.
- Ejemplo: metal con necesidad 1,5, llena, en tierra propia, a 9 000 px →
  1,5 × 1 × 1,25 / 2 = 0,94. La misma mina en tierra ajena a 4 500 px →
  1,5 / 1,5 = 1,0: gana la ajena, más cerca.

**F11. Soldados que manda el NPC.**
`soldados = ceil(faltan / 0,3)`, sin pasar de los libres.

- Ejemplo: le faltan 60 de metal → 200 soldados.

**F12. Umbral del NPC para atacar recolectores.**
`atacar si poderPropio ≥ poderRecolectores × (1,6 − agresividad)`.

---

## 5. Casos límite

- **La mina se agota el mismo día que llega un grupo nuevo:** recolecta 0, la
  mina se cierra y el grupo vuelve vacío.
- **Orden `recolectar` a una mina cerrada:** devuelve `false`. Un grupo que ya
  iba hacia ella cuando se cerró llega, no recolecta y vuelve.
- **Grupo lleno el mismo día que se agota la mina:** vuelve una sola vez; la
  mina se cierra.
- **Dos naciones en paz en la misma mina:** comparten con F4. No pelean.
- **Dos naciones en guerra en la misma mina, sin orden de atacar:** siguen
  recolectando las dos. La batalla solo empieza con una orden `atacar` (NPC o
  jugador). No hay combate automático: eso sería una patrulla.
- **Se firma la paz en mitad de una batalla en la mina:** la batalla se cierra
  sin ganador y los dos vuelven a recolectar al día siguiente.
- **El atacante llega y los recolectores se acaban de ir:** vuelve a casa. Si
  se cruza con ellos por el camino, choca con la regla de choques.
- **Grupo cargado redirigido a un sitio que no es ciudad ni campamento:**
  conserva la carga y la entrega cuando por fin llegue a casa.
- **Grupo cargado que se retira de una batalla que no es en su mina** (por
  ejemplo, lo llamaron a defender y pierde allí): pierde la carga, igual que en
  la mina.
- **Grupo cargado cuya ciudad ya no existe:** no pasa, porque la capital nunca se
  pierde. Si la llegada es a un campamento destruido, sigue hacia el sitio
  propio más cercano (`volver`).
- **Grupo sin nada sano en la mina** (lo aniquilan): desaparece con la carga,
  como hoy los grupos aniquilados.
- **Capital a 0 de vida sin guarnición, pero con un grupo propio en la
  batalla:** la batalla sigue. Si ese grupo gana, no hay saqueo.
- **Capital a 0 sin guarnición y sin grupos:** pierde ese día (no queda nada
  sano). Vida 9 y saqueo.
- **El jugador entra a una batalla que acaba de terminar ese mismo día:** el
  botón ya no aparece. La batalla cerrada no se reabre.
- **El jugador sale de la escena sin terminar:** la batalla sigue con F8 desde
  el estado que devuelva la escena (`resolverBatalla` con las bajas hasta ese
  momento y sin ganador).
- **Recolección con 0 soldados y solo tanques:** vale. Trabajo 3 y carga 2 por
  tanque: 2 / (3 × 0,0375) = 17,8 días para llenarse en nivel 2.

## 6. Dependencias

- **Economía:** [economia.md](economia.md) (decidido el 2026-09-30) cambia lo
  que devuelven las batallas de §3.7, en 3D y simuladas: soldados muertos y
  heridos, vehículos averiados (nunca destruidos) y munición gastada; la
  munición también decide el golpe de cada bando.
- **Depende de:**
  - [territorio-y-capitales.md](territorio-y-capitales.md): yacimientos (3.8,
    F10), `dueno`, `ingresar`, afuera, vida y saqueo de la capital;
  - [ejercitos-en-el-mapa.md](ejercitos-en-el-mapa.md): grupos, choques, poder,
    guarnición mínima (F9), `resolverBatalla` y quién calcula la batalla;
  - [retirada-y-recuperacion.md](retirada-y-recuperacion.md): `herirGrupo`,
    umbral de retirada y heridos;
  - [instalaciones-y-economia.md](instalaciones-y-economia.md): consumo,
    fabricación y niveles (`minas`).
- **Lo usan / hay que actualizar:**
  - `territorio-y-capitales.md`: las extracciones desaparecen (3.8 "Explotar",
    F11 y decisión 1 del §9 pierden objeto) y la vida 0 ya no termina la
    batalla (3.3);
  - `ejercitos-en-el-mapa.md`: el choque pasa a ser una batalla de bandos (3.7);
  - `guerra.md`: se quitan salvas, incursiones, escaramuzas y golpes a
    ciudades;
  - `instalaciones-y-economia.md`: los campamentos dejan de producir;
  - `naciones-y-politica.md`: `necesidades` y la IA de recolección (3.10);
  - `interfaz.md`: orden "Recolectar", "Retirar", "Llamar a casa", icono de la
    mina, pregón "Defender en 3D / No defender" y lista de batallas en curso;
  - `GUIA-3D.md`: entrar con el estado a mitad de batalla y el modo sin ventana
    IA contra IA para alinear F8;
  - [rebeldes-y-niveles.md](rebeldes-y-niveles.md): las batallas contra
    campamentos rebeldes usan F8, la carga (F2) y "lo que le quepa".

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `kRitmo` | 0,03 | 0,015–0,06 | Días en llenarse y soldados fuera. Doble: la mitad de días en la mina |
| `trabajo` (soldado/tanque/lanzacohetes) | 1 / 3 / 2 | 0,5–5 cada uno | Lo que conviene llevar vehículos |
| `carga` (soldado/tanque/lanzacohetes) | 0,3 / 2 / 5 | 0,1–10 | Cuánto trae un viaje. Más carga con el mismo ritmo alarga la estancia en la mina (más riesgo) |
| `ventajaTerritorio` | 1,25 (solo al dueño de la tierra) | 1,1–1,5 | Lo que vale tener tu bandera sobre la mina. Por debajo de 1,1 casi no se nota |
| Bonus de templos | +10 a +25 % según tipo | +5 a +30 % | Lo que decide un templo (fase posterior, sección 10) |
| `reservaBase` | 250 (oro 60) | 100–600 | Cada cuánto hay que cambiar de mina |
| `enfriamiento` | 20 + 10 × riqueza | 10–90 días | Lo que dura una mina muerta |
| `regeneracion` | 1 %/día | 0–3 % | Si una mina a medias vale la pena dejarla descansar |
| `precioOro` | 8 | 4–15 | Dinero por unidad de oro (ya existe) |
| Mantenimiento de campamento | 0,5 de petróleo al día | 0–2 | Cuántos puestos de acopio sostiene una nación |
| `golpeMin` / `golpeMax` | 0,06 / 0,12 | Según la alineación con la 3D | Duración de las batallas sin ver |
| `avisoDias` | 1 | 0,5–3 | Tiempo para reaccionar al aviso |
| `diasReserva` (IA) | 20 | 10–40 | Lo acaparadora que es la IA: más alto = más soldados fuera |
| Umbral F12 | 1,6 − agresividad | 1,2–2,0 base | Cuánto atacan los NPC a recolectores |

## 8. Criterios de aceptación

Medir con 500 días, semillas 1, 4242 y 12345, con el arnés de "Cómo se midió"
cambiado a la regla nueva:

1. **Nada produce solo:** fuera de la llegada de recolectores, del botín, de
   `metalCiudad`, de los impuestos y de las ventas, ninguna llamada a `ingresar`
   añade metal, petróleo ni oro.
2. **Cero ataques a distancia:** 0 salvas, 0 incursiones y 0 golpes a ciudades
   (hoy, 330–454, 107–149 y 12–17).
3. **Soldados fuera:** entre los días 301 y 500, la mediana por nación de
   soldados en grupos `recolectar` está entre el 5 y el 25 % de sus soldados.
   **Objetivo sin medir.**
4. **Economía sostenida:** ninguna nación pasa más del 10 % de los días con
   metal disponible por debajo de `reservaMetal` (40), ni más del 10 % con
   hambre. **Sin medir con la regla nueva.**
5. **Minas vivas:** el día 500 hay entre 20 y 200 minas cerradas por semilla y
   ninguna con `queda < 0` ni `queda > reserva`.
6. **Disputa:** al menos 20 batallas en minas por semilla en 500 días. Si da 0,
   hay que bajar F12.
7. **Carga perdida:** en toda batalla perdida por recolectores, su carga pasa a
   0 el mismo día. Lo que se lleva el ganador más lo que vuelve a la mina es
   igual a la carga perdida.
8. **Capital a 0:** en una prueba con una capital a 0 de vida y un grupo propio
   más fuerte que el atacante en la batalla, la batalla sigue, gana el defensor
   y no hay saqueo.
9. **Alineación 3D:** con 200 batallas IA contra IA en la escena sin ventana, F8
   acierta el ganador en al menos el 80 % de los casos y las bajas totales con
   un margen de ±25 %.
10. **NPC = jugador:** la misma orden `recolectar` por `ejecutar` en dos copias
    del mismo estado da el mismo resultado.
11. **Determinismo:** guardar el día 250, cargar y seguir da el mismo texto de
    `guardar()` que no parar. Una partida de la versión 18 carga sin perder
    soldados: los de las extracciones vuelven a la ciudad.
12. **Rendimiento:** menos de 10 ms por día simulado de media (el criterio de
    `instalaciones-y-economia.md`). Hoy el arnés tarda unos 17 s en 500 días
    por semilla (unos 34 ms por día **con** el arnés, que añade medidas).

## 9. Decisiones del dueño (2026-09-27)

Estas decisiones mandan sobre cualquier punto anterior del documento que diga
otra cosa.

1. **Campamentos y extracciones:** las extracciones desaparecen. Los
   campamentos pasan a ser **puestos de acopio**: dan territorio, las tropas
   salen de ellos y entregan en ellos (viaje más corto) y cuestan 0,5 de
   petróleo al día.
2. **Botín en la mina:** el ganador se lleva **lo que le quepa** de la carga del
   perdedor; el resto vuelve a la mina.
3. **Recolectores de una nación en paz:** **sí se pueden atacar, y atacar
   declara la guerra automáticamente** (por la vía normal de `declararGuerra`,
   con su noticia).
4. **Misiles, interceptores y aviones:** se **pausa su fabricación** mientras
   la batalla 3D no los use. Por ahora solo hay soldados, tanques y
   lanzacohetes.

## 10. Objetivos: templos (fase posterior)

Anotado por petición del dueño. **No se programa ahora**: es una propuesta
breve para que encaje con lo de arriba. Ninguna cifra de esta sección está
medida.

**Qué son.** Lugares especiales, más escasos que los yacimientos, que salen de
la semilla como ellos. Cada uno da un bonus a la nación que lo controla. Son
objetivos que tomar: con ellos, las banderas y el territorio valen todavía
más.

**Cómo se controlan (propuesta: con territorio).**

- Controla un templo la nación dueña de la **celda** donde está
  (`duenoCelda`), igual que el bonus de las minas. Hace falta que lo cubra la
  capital, un campamento o una bandera.
- Para quitárselo a otro: tirar la bandera o el campamento que lo cubre
  (batalla de campo, como ya existe) y plantar la tuya. No hace falta ninguna
  regla nueva de combate.
- **Disputado:** mientras haya una batalla a menos de 3 000 px del templo, no
  da bonus a nadie. Así atacar sirve aunque todavía no lo hayas ganado.
- Se descartan dos alternativas:
  - un ejército que lo ocupa: obligaría a tener tropas quietas ahí, y eso se
    parece a una patrulla;
  - una bandera encima como objeto especial: duplica lo que ya hace el
    territorio.

**Rareza.** Una prueba por celda de 49 152 px (4 por zona de nación de
98 304 px), con probabilidad 0,25. Con un 33 % del suelo en agua, sale
**alrededor de 0,6–0,7 templos por zona de nación** (cuenta, sin medir), frente
a los 320–350 yacimientos por nación que hay hoy registrados (medido: de 7 663 a
7 734 en 25 zonas). Mismo método que
F10: `Ruido.hash(semilla, cx, cy, 92)`. Se descartan el agua, las ciudades y
los sitios a menos de 10 000 px de una capital, para que ninguno nazca ya
controlado.

**Tipos y bonus** (el tipo se sortea con el mismo azar de la celda):

| Templo | Bonus para quien lo controla | Magnitud |
|---|---|---|
| de la Cosecha | ritmo de recolección (`bonusTemplo` en F1) | +15 % |
| del Camino | velocidad de los grupos en el mapa | +10 % |
| del Trueno | golpe de los lanzacohetes | +15 % |
| del Acero | golpe de los tanques | +10 % |
| de la Lanza | golpe de los soldados | +10 % |
| del Halcón | golpe de los aviones (cuando haya aviones en batalla) | +15 % |
| del Bálsamo | ritmo de recuperación de heridos | +25 % |

**Cómo encaja sin romper el equilibrio.**

- **Bonus pequeños**, del orden de la ventaja de pelear en tu territorio
  (+10 %). Tener un templo ayuda, pero no decide una guerra.
- **Varios del mismo tipo:** cada templo extra de ese tipo da la mitad que el
  anterior (+10 %, +5 %, +2,5 %…), así que la suma nunca pasa del doble del
  primero. No es un tope: siempre suma algo, pero cada vez menos.
- En F8 el bonus de golpe se aplica **solo a la parte de la vida del bando que
  es de ese tipo**. Por ejemplo, +10 % a tanques en un ejército con un 10 % de
  su vida en tanques da un +1 % al golpe total.
- En la batalla 3D se aplica el mismo multiplicador al daño de esas unidades.
  Así la regla sin ver y la escena siguen alineadas.
- **La IA** valora un templo como un yacimiento (F10), con `necesidad` = 2 si
  el bonus sirve a lo que más usa (por ejemplo, el del Acero si más del 20 % de
  su vida está en tanques) y 1 si no.
- **Visibilidad:** se ve en el mapa como los yacimientos (icono propio, con el
  escudo del dueño) y sale en las noticias al cambiar de manos. Es información
  pública, no secreta como los diseños de armamento.

**Guardado cuando se programe:** nada nuevo. El templo sale de la semilla y el
control se calcula del territorio, que ya se guarda.

---

## Números medidos (simulación de hoy, versión 18)

Por nación y día, en tres ventanas (días 1–100 / 101–300 / 301–500). Rangos
entre las semillas 1, 4242 y 12345. **Gasto** = entra − cambio de lo guardado y
de afuera − merma. Es lo que la economía usa de verdad; lo demás se pierde
por merma.

| Medida | Días 1–100 | Días 101–300 | Días 301–500 |
|---|---|---|---|
| Metal producido por instalaciones | 1,0–1,6 | 8,3–14,1 | 21,8–32,7 |
| Metal gastado | 1,3–1,7 | 4,4–6,8 | 6,4–8,2 |
| Petróleo producido por instalaciones | 3,0–4,2 | 21–34 | 84–130 |
| Petróleo gastado | 0,5–1,0 | 15–27 | 67–102 |
| … de él, mantenimiento de campamentos | 0,2–0,7 | 13–24 | 61–95 |
| … de él, combustible de tanques y aviones | 0,06–0,08 | 0,7–1,1 | 2,8–3,8 |
| Petróleo gastado sin mantenimiento | 0,2–0,3 | 1,8–3,1 | 5,3–7,1 |
| Comida de granjas y yacimientos | 1,2–2,4 | 5,3–9,8 | 14,0–25,6 |
| Comida que falta a las ciudades tras sus cultivos | 0,4–0,6 | 2,2–2,5 | 5,3–6,2 |
| Dinero de impuestos (sin minas) | 13,0–14,7 | 19,5–22,3 | 26,4–30,6 |
| Dinero gastado | 1,7–3,5 | 7,8–13,6 | 18,7–27,5 |
| Dinero perdido por merma (bóveda llena) | 0–0,04 | 37–63 | 162–250 |

| Medida | Día 100 | Día 300 | Día 500 |
|---|---|---|---|
| Soldados por nación, mediana | 1 563–1 840 | 2 479–5 401 | 4 645–10 593 |
| Explotaciones (extracciones y campamentos con yacimiento) en total | 120–183 | 523–864 | 1 189–1 713 |
| Distancia capital–explotación, mediana | 5 200–8 100 px | 22 000–25 900 px | 30 800–33 900 px |

Distancia de cada capital a su 1.º / 3.º / 5.º yacimiento más cercano de cada
tipo (mediana entre capitales, día 0):

- metal: 5 300–5 800 / 10 100–11 000 / 13 600–15 600 px;
- petróleo: 3 400–4 400 / 7 200–8 500 / 9 700–11 000 px;
- comida: 3 500–5 400 / 9 000–9 500 / 11 900–12 900 px;
- oro: 8 100–9 500 / 16 700–18 300 / 23 000–24 200 px.

**Lectura:**

1. **Hoy sobra casi todo.** Entre los días 301 y 500 se produce de 3 a 4 veces
   el metal que se gasta, y el dinero de impuestos ya cubre el gasto sin minas
   de oro. La recolección va a apretar la economía, y eso es lo que da motivo
   para pelear por las minas.
2. **Lo que hay que recolectar** para sostener lo de hoy (metal + petróleo sin
   mantenimiento + comida que falta), por nación y día: **1,9–2,6** en los días
   1–100, **8,4–12,4** en los 101–300 y **17–21,5** en los 301–500. Con el
   mantenimiento propuesto de 0,5 por campamento se suman unos 1–3 más.
3. **Tropas que implica (estimación con F1 y F2, no medida con la regla
   programada).** Rendimiento de un soldado que va y vuelve sin parar:
   `carga / (viaje de ida y vuelta + días para llenarse)`.
   - A 9 000 px (1 día de ida, cerca del 3.º yacimiento más cercano), nivel 2 y
     tierra ajena: 0,3 / (2 + 8) = **0,030 al día por soldado**.
   - Nivel 4 y tierra propia: 0,3 / (2 + 4,6) = **0,046**.
   - Días 1–100: de 63 a 87 soldados fuera, un 4–6 % de la mediana.
   - Días 101–300: de 280 a 410 soldados fuera, un 6–17 %.
   - Días 301–500: de 370 (nivel 4, propia) a 720 (nivel 2, ajena) soldados
     fuera, un 4–15 %.
   Sale dentro del objetivo del criterio 3. Si la IA gasta distinto con
   escasez, estas cifras cambian: **hay que volver a medir con la regla
   programada**.
4. **El mantenimiento de campamentos de hoy no se puede recolectar:** 61–95 de
   petróleo al día por nación serían de 2 000 a 3 200 soldados solo para eso.
   Por eso se propone la cuota fija (3.3).

## Cómo se midió

Arnés fuera del repositorio, en la carpeta temporal de la sesión
(`scratchpad/lucia/medir.lua` y `scratchpad/lucia/distancias.lua`), sobre la
simulación de hoy (versión 18, HEAD 83aaf4c), con `luajit` y sin LÖVE.

- Crea el mundo con `Terreno`, `Ciudades` y `Recursos` reales y registra las
  25 zonas de −2..2, como el banco de pruebas de la sesión.
- Avanza 500 días en las semillas 1, 4242 y 12345.
- Envuelve `ingresar` para anotar de dónde entra cada recurso (instalaciones,
  ciudad, ventas, botín) y `mermar` para lo perdido.
- Cuenta la comida que entra en los graneros durante `producirRecursos`, el
  combustible (`gastoCombustible`) y el mantenimiento de los campamentos
  (`mantenimientoCampamento`), y lo que falta a cada ciudad tras sus cultivos.
- Cuenta las llamadas con éxito a `salva`, `incursion`, `golpeCiudad` y
  `enviarGrupo` por misión.
- No cambia ninguna regla.
- `distancias.lua` mide, el día 0, la distancia de cada capital a sus cinco
  yacimientos más cercanos de cada tipo.
- Tarda unos 17 s por semilla.

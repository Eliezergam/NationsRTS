# Guerra

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Fuentes: `mundo/simulacion.lua` — `guerra` :1601, `ofensiva` :1457, `objetivo`
:1406, `salva` :690, `interceptar` :675, `defensas` :608, `programarImpacto`
:747, `resolverImpactos` :756, `incursion` :787, `combatir` :1200, `llegada`
:1241, `refuerzos` :1422, `golpeCiudad` :863, `crimenDeGuerra` :906,
`danarInstalacion` :645, `destruirInstalacion` :658. Dibujo de misiles y vuelos:
`mundo/mundo.lua` (`nuevaSalva` :516, `nuevaIncursion` :731).

## 1. Resumen

La guerra se hace contra **instalaciones** (extracciones y bases), no contra
ciudades. En cada día de tensión cada bando puede lanzar una **salva de
misiles** (el defensor gasta interceptores), una **incursión aérea** (el
defensor despega cazas) y mandar un **grupo terrestre** a tomar una
instalación. El atacado manda **refuerzos** a lo que le atacan. Misiles y bombas
tardan en llegar: el daño se aplica el día del impacto. Cada 2 a 20 días hay una
tirada de **golpe a una ciudad** con 1–4 misiles; si alguno pasa, es un
**crimen de guerra** con castigo diplomático. Las ciudades nunca se conquistan.

## 2. Fantasía del jugador

Un frente que se ve desde el cielo: estelas de decenas de misiles que salen en
oleadas y chocan contra la cortina de interceptores, duelos de cazas sobre una
mina, columnas que avanzan por carretera a por una base y otras que llegan a
socorrerla. Las ciudades son sagradas: tocarlas escandaliza al mundo.

## 3. Reglas

### El día de guerra (`Simulacion:guerra`)

1. `dias + 1`. Si algún bando no tiene ciudades, la guerra se borra.
2. En fase `calma`: solo baja el cansancio (ver [diplomacia.md](diplomacia.md)).
   No hay ataques, ni refuerzos, ni golpes, ni negociación.
3. En fase `tension`: `intensidad = azar()`. Si > 0,35: `ofensiva(atacante,
   intensidad)` y, con probabilidad `0,4 + 0,4 × agresividad_defensor`,
   `ofensiva(defensor, intensidad × 0,8)`.
4. `refuerzos` de los dos bandos.
5. Si toca (`dia >= proximoGolpeCiudad`): nuevo plazo de 2–20 días y tirada de
   golpe a ciudad para cada bando.
6. `negociar` (ver [diplomacia.md](diplomacia.md)).

### Objetivo (`objetivo`)

La instalación enemiga más cercana a algún sitio propio (ciudad o base
terminada) que tenga el arma pedida, a menos de `alcanceAtaque = 130 000` (13 km: al vecino, no a medio mapa). Las
extracciones cuentan con la distancia × 0,8 (se prefieren).

### Ofensiva (`ofensiva`), cada una con su tirada

| Acción | Probabilidad | Tamaño | Desde |
|---|---|---|---|
| Salva | 55 % | `floor(azar(3, 12) + intensidad² × agresividad × 100)`, limitado a los misiles del sitio | Sitio con misiles más cercano al objetivo |
| Incursión | 40 % | 2–5 aviones, limitado a los del sitio | Sitio con aviones más cercano |
| Grupo terrestre | 35 %, si no tiene ya un grupo de ataque en camino | 35 % de los soldados y 60 % de los tanques del sitio | Sitio con ≥ 120 soldados más cercano al objetivo |

### Salva (`salva`) e interceptores (`interceptar`)

1. Resta los misiles lanzados al sitio.
2. Defensas: sitios del defensor con interceptores a menos de
   `alcanceDefensa = 30 000` del objetivo (más extracciones con interceptores a
   menos de 500, que hoy nunca tienen).
3. Cada interceptor gastado acierta con 72 %. Se siguen gastando hasta
   interceptar todo o vaciar las defensas (un fallo también gasta).
4. Impactos = lanzados − interceptados. Daño programado: impactos × 3,5 (× 5
   con tecnología de precisión), para el día del impacto.
5. Cansancio: defensor + 0,05 por impacto; atacante + 0,01 por misil.
   Relación −min(8; 1 + 0,1 × lanzados).
6. Noticia solo si se lanzan ≥ 15.

### Impactos diferidos (`programarImpacto`, `resolverImpactos`)

- Vuelo del misil: `distancia / 160 000` días + `ventanaOleadas = 0,3` (la salva
  sale en oleadas). Avión: `distancia / 120 000` días.
- Día del impacto: `max(día + 1, ceil(ahora + vuelo))`; `ahora` incluye la
  fracción del día en curso (un comando puede darse a media jornada).
- Al empezar ese día, antes de nada: si la instalación sigue existiendo y no es
  del atacante, recibe el daño. Si es contra una ciudad, ver golpes.

### Daño a instalaciones (`danarInstalacion`, `destruirInstalacion`)

- `efectivo = daño × (1 − 0,8 × fortificación) × (1,5 si está en obras)`.
- Salud −efectivo; bajas en la guarnición `floor(efectivo × 0,2..0,5)`; si
  efectivo > 8, 30 % de perder un tanque. Marca `atacadaDia`.
- Salud 0: se destruye (desaparece con su carretera), el dueño suma 3 de
  cansancio y, si era base, `n.bases − 1`.

### Incursión aérea (`incursion`)

1. Atacantes = min(aviones del sitio, 2–5).
2. Despega el primer sitio defensor con aviones a menos de 30 000: cazas =
   min(sus aviones, atacantes + 1).
3. Por cada caza: 45 % derriba un atacante y 30 % es derribado (limitado a los
   que hay).
4. Supervivientes × 8 de daño al llegar (`distancia / 120 000` días).
5. Cansancio: defensor + 0,1 × supervivientes + 0,3 × cazas perdidos; atacante
   + 0,3 × aviones perdidos. **No cambia la relación.**

### Grupo terrestre (`enviarGrupo` misión `atacar`, `combatir`)

1. Viaja a 1 600 px/día. Si el objetivo ya no existe o ya es suyo, vuelve.
2. Al llegar combate **cada día** hasta que un lado cae:
   - nuestra = soldados + 9 × tanques;
     suya = (soldados + 9 × tanques) × (1 + fortificación);
   - bajas suyas `floor(nuestra × 0,06..0,12)`; nuestras
     `floor(suya × 0,05..0,1)`; con > 15 bajas, 40 % de perder un tanque.
3. Toma: si la guarnición queda sin soldados ni tanques, la instalación pasa al
   atacante con el grupo de guarnición, salud ≥ 25, fortificación a la mitad y
   sin carretera. El perdedor suma 4 de cansancio.
4. Rechazo: si el grupo se queda sin soldados, desaparece (con sus tanques).

### Refuerzos (`refuerzos`)

Cada día de tensión, para cada instalación de los dos bandos atacada ayer u hoy
y sin refuerzo en camino: el sitio propio más cercano (no ella misma) con ≥ 60
soldados manda el 30 % de sus soldados y el 40 % de sus tanques. Al llegar se
suman a la guarnición; si ya no es suya, vuelven a casa.

### Golpes a ciudades y crímenes de guerra

1. Cada 2–20 días (se sortea al declarar y tras cada golpe), en tensión, cada
   bando tira `azar < 0,1 + 0,35 × agresividad − 0,15 × prudencia`.
2. `golpeCiudad`: el par (sitio propio con misiles, ciudad enemiga) más cercano
   a menos de 130 000. Lanza 1–4 misiles; interceptan las defensas del
   defensor a menos de 30 000 de la ciudad.
3. Al impactar, si pasa ≥ 1 misil: población − impactos × (15..60) (mínimo 10),
   `crimenDeGuerra`, cansancio de la víctima + 0,6 × impactos. Si no pasa
   ninguno: noticia "las defensas interceptan".
4. `crimenDeGuerra`: noticia; todas las naciones vivas de **otro** orden bajan
   su relación con el agresor −14 (la víctima −30). Las del mismo orden "miran
   para otro lado" (sin cambio). El agresor no suma cansancio.

## 4. Fórmulas

**Salva típica.** Intensidad 0,8, agresividad 0,5:
`azar(3,12) + 0,64 × 0,5 × 100 = 35–44` misiles pedidos; digamos 40. Contra
50 interceptores se gastan los 50 y paran ~36 (72 %). Impactan ~4 × 5 = 20 de
daño. Con fortificación 1: 4 efectivos (una extracción de 100 aguanta ~25
salvas así, y se repara +2/día). En obras: 30. Contra 20 interceptores: paran
~14, impactan ~26 × 5 = 130 (26 con fortificación 1): cae una extracción en
obras de un golpe.

**Tamaño medido (500 días).** Mediana 8–9 misiles, p90 24–27, máximo 59–90 (el máximo
teórico es 111; lo corta el arsenal del sitio).

**Combate terrestre.** Grupo de 700 soldados + 10 tanques (790) contra base de
2 000 soldados + 5 tanques con fortificación 1 (4 090): bajas nuestras 204–409
por día, suyas 47–95. El grupo cae en 2–3 días. Una base madura es casi
intomable por tierra; las tomas son de instalaciones jóvenes o ya desangradas.

**Duelo aéreo.** 4 atacantes contra 5 cazas: se esperan 2,25 atacantes y 1,5
cazas derribados; 1,75 supervivientes × 8 = 14 de daño.

**Golpe a ciudad.** Probabilidad por bando y plazo: −0,05 a 0,435. Con
agresividad 0,5 y prudencia 0,5: 0,2.

**Medido (500 días):**

| Semilla | Salvas | Misiles | Interceptados | Incursiones | Atac. derribados | Grupos de ataque | Tomas | Rechazos | Destruidas (bases) | Refuerzos | Golpes | Crímenes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4242 | 543 | 6 782 | 64,7 % | 352 | 320 / 779 | 154 | 10 | 31 | 46 (3) | 329 | 31 | 5 |
| 1 | 754 | 9 091 | 62,9 % | 532 | 423 / 1 115 | 241 | 18 | 46 | 70 (2) | 495 | 57 | 10 |
| 7 | 931 | 10 496 | 57,4 % | 581 | 360 / 1 185 | 273 | 14 | 48 | 106 (2) | 505 | 89 | 12 |
| 99 | 741 | 8 247 | 62,2 % | 525 | 383 / 1 035 | 219 | 15 | 39 | 54 (0) | 461 | 59 | 9 |
| 12345 | 547 | 6 690 | 54,5 % | 353 | 284 / 769 | 172 | 12 | 40 | 72 (3) | 332 | 40 | 10 |
| 2026 | 666 | 8 037 | 62,3 % | 436 | 332 / 918 | 194 | 16 | 41 | 62 (2) | 372 | 45 | 9 |

- Incursiones con cazas defensores: 78–88 %.
- Días de guerra en tensión: 40–46 % del total de días de guerra.
- Casi todo lo destruido son extracciones: bases destruidas 0–3 por semilla.

## 5. Casos límite

- **Alto el fuego o paz con misiles en vuelo:** caen igual (`resolverImpactos`
  no mira el estado de la guerra). Solo se retiran los grupos de ataque.
- **Objetivo que cambia de manos antes del impacto:** si ahora es del
  atacante, el daño se pierde; si es de un tercero, se lo come el tercero.
- **Sin interceptores ni cazas:** todo impacta; ningún caza despega.
- **Salva que se gasta interceptores de varias defensas:** se vacían en orden de
  `sitiosDe` (ciudades primero, luego bases), no por cercanía.
- **Grupo sin soldados pero con tanques:** desaparece entero.
- **Toma de una base:** pasa a ser sitio y posible fábrica del ganador, con su
  arsenal de misiles, interceptores, aviones y lanzacohetes intacto.
- **Refuerzo cuyo destino cae o cambia de manos:** vuelve a su sitio, o al sitio
  propio más cercano si el suyo ya no existe; si no hay ninguno, desaparece.
- **Crimen de guerra entre naciones del mismo orden:** nadie cambia su
  relación, **ni siquiera la víctima**.
- **Relación ya en −100:** el castigo por crimen o por salva no tiene efecto.
- **Golpe sin misiles a alcance:** no se lanza nada; el plazo ya se ha
  renovado.
- **Ciudad a 10 habitantes:** no baja de ahí.

## 6. Dependencias

- **Depende de:** [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (arsenales, fábricas, guarniciones, fortificación, `velocidadGrupo`),
  [naciones-y-politica.md](naciones-y-politica.md) (quién está en guerra,
  agresividad, prudencia, órdenes), [mundo-fisico.md](mundo-fisico.md)
  (distancias).
- **Lo usan:** [diplomacia.md](diplomacia.md) (todo el cansancio sale de aquí),
  [naciones-y-politica.md](naciones-y-politica.md) (salvas y crímenes bajan
  relaciones), [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (instalaciones destruidas o tomadas, población perdida),
  [retirada-y-recuperacion.md](retirada-y-recuperacion.md) (PROPUESTO: combate terrestre de los grupos de ataque, `volver`,
  alto el fuego y paz; con P7, también los lanzacohetes que salen de una base).
- **P7 (implementado)** cambia `misilesListos`, que también usan las escaramuzas
  y los golpes a ciudades, y añade a [instalaciones-y-economia.md](instalaciones-y-economia.md)
  el coste de obra de la base y la compra de lanzacohetes para bases.

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| Umbral de intensidad | 0,35 | 0,2–0,7 | Días de tensión sin ataques (hoy 35 %). |
| Tamaño de salva | 3–12 + i²·agr·100 | — | Espectáculo; el arsenal lo corta. |
| Prob. salva / incursión / grupo | 0,55 / 0,4 / 0,35 | 0,1–0,8 | Frecuencia de cada tipo de ataque. |
| Acierto de interceptor | 0,72 | 0,5–0,9 | Hoy 54–65 % de misiles parados. |
| `alcanceDefensa` | 30 000 | 15 000–45 000 | Cuántas defensas cubren un punto. |
| `alcanceAtaque` | 130 000 | 80 000–200 000 | Profundidad de los ataques. |
| Daño por misil | 3,5 / 5 | 2–10 | Rapidez de destrucción. |
| Daño por avión | 8 | 4–20 | Valor de la aviación. |
| Duelo aéreo | 45 % / 30 % | — | Ventaja del defensor. |
| Reducción por fortificación | 80 % | 50–90 % | Cuánto protege un año de obra. |
| Multiplicador de defensa en tierra | 1 + fort | 1–3 | Hoy una base madura es casi intomable. |
| Bajas en combate | 6–12 % / 5–10 % | — | Duración de los asedios. |
| Soldados mínimos para atacar | 120 | 60–500 | — |
| Refuerzos | 30 % soldados, 40 % tanques | 10–50 % | Cuánto se desangran las retaguardias. |
| `velocidadMisil` / `velocidadAvion` | 160 000 / 120 000 px/día | — | A 60 s/día, 2 700 y 2 000 px/s en pantalla. |
| `velocidadEjercito` | 9 000 px/día | — | Ejércitos, refuerzos y entregas: 8 km en unos 9 días. |
| `ventanaOleadas` | 0,3 días | 0,05–0,5 | Duración visual de una salva (18 s a 60 s/día). |
| Plazo de golpes a ciudad | 2–20 días | 5–60 | Frecuencia de crímenes. |
| Castigo por crimen | −14 / −30 | — | Poco efectivo si ya están en −100. |

## 8. Criterios de aceptación

16 zonas, 500 días (medido entre paréntesis):

- Entre 500 y 1 000 salvas (543–931); mediana de 7 a 10 misiles (8–9).
- Entre el 50 % y el 70 % de misiles interceptados (54,5–64,7 %).
- Entre 300 y 600 incursiones (352–581); más del 75 % con cazas (78–88 %).
- Entre 8 y 20 instalaciones tomadas por tierra (10–18).
- Más rechazos que tomas (31–48 frente a 10–18).
- Entre 40 y 110 instalaciones destruidas, casi todas extracciones (46–106;
  bases 0–3).
- Entre 3 y 15 crímenes de guerra (5–12).
- Ningún impacto contra una ciudad fuera de un golpe (por construcción).

No medido: cuántos misiles caen durante un alto el fuego; tiempo medio de
supervivencia de una instalación; efecto de la ventana de oleadas en pantalla.

## Propuestas (no implementadas)

- **P1. Cancelar o no los impactos al firmar un alto el fuego.** Hoy siguen
  cayendo. Opción: se cancelan los que aún no han llegado; o se mantienen y
  cuentan como violación (sube el riesgo de ruptura).
- **P2. Las incursiones deberían bajar la relación** como las salvas.
- **P3. Crímenes de guerra con consecuencias reales**: además de relación,
  cansancio para el agresor, sanciones (menos producción) o que naciones de
  otro orden entren en la guerra. Y que la víctima siempre reaccione, sea del
  orden que sea.
- **P4. Hacer tomables las bases maduras**: por ejemplo, defensa ×(1 + 0,5·fort)
  en vez de ×(1 + fort), o que los misiles previos reduzcan la fortificación.
- **P5. Cumplir "hasta un centenar"** si se quiere ese espectáculo: más
  misiles por fábrica o salvas desde varios sitios a la vez.
- **P6. Retirada y recuperación de ejércitos** (PROPUESTO): barra de vida en
  los grupos de ataque, retirada automática al casi caer, heridos que se
  recuperan en su ciudad y pago para acelerar. Ver
  [retirada-y-recuperacion.md](retirada-y-recuperacion.md).
- **P7. Lanzacohetes en las bases** (implementado en la simulación; falta lo
  visual): las bases disparan con la misma regla que las ciudades (sin
  lanzacohetes no disparan) y sus lanzacohetes se compran, se entregan y se
  ven. Ver la sección siguiente.

## P7. Lanzacohetes en las bases (implementado)

> **Implementado en la simulación** (`mundo/simulacion.lua`, formato de
> partida 13) con las decisiones del dueño: tope fijo de 6 por base (A),
> salvas de hasta 24 por sitio sin salva conjunta (E1), las bases prestan
> lanzacohetes a sus grupos (L1) y sin fuerza en tierra extra por ellos en la
> defensa de una base. **Falta lo visual** (regla 10 y el panel de la base),
> que sigue PROPUESTO. Las tablas de variantes son del prototipo (sobre el
> commit `118e820`); la fila "Implementado" y los criterios, del código real
> (ver "Cómo se midió").

### Lo que hacía el código antes de P7

- `Simulacion.misilesListos(s)`: si `s.tipo == 'base'` devuelve **todos** sus
  misiles; si es una ciudad, `min(misiles, lanzacohetes × misilesLanzacohetes)`
  con `misilesLanzacohetes = 4`.
- El límite es **por salva**, no por día: cada llamada a `salva`,
  `golpeCiudad` o `escaramuza` vuelve a calcular `misilesListos`, y disparar
  no gasta ni ocupa los lanzacohetes. En la práctica casi equivale a "por
  día": medido con la regla propuesta, un mismo sitio lanza más de una salva
  el mismo día 0–5 veces en 300 días (sobre 123–329 pares sitio-día con
  salva), y solo 0–2 veces supera ese día `lanzacohetes × 4` misiles en total.
  No hace falta una regla de recarga (sería un contador por día encubierto).
- Las bases nacen con `lanzacohetes` sin definir (0) y nadie les compra:
  `enviarDefensas` y `entregar` solo aceptan ciudades (`e.ciudades[...]`), y
  la llegada de una `entrega` solo instala en ciudades.
- En pantalla, `Mundo:lanzacohetesVisibles` dibuja siempre
  `Mundo.lanzacohetesPorBase = 2` en una base terminada, tenga los que tenga
  (sigue así hasta que se haga lo visual).
- La fábrica manda los misiles a las bases ("son las que disparan"). Medido
  hoy a 300 días: las bases guardan 1 883–3 292 misiles por mundo y lanzan
  89–287 de las 120–321 salvas (74–89 %).
- Asimetría parecida con los interceptores (`interceptar`: una base dispara
  `math.huge`, una ciudad `baterías × 3`). Fuera del alcance de P7; se anota
  para que el dueño decida si la trata igual más adelante.

### 1. Resumen

Una base militar solo dispara misiles si tiene **lanzacohetes**, igual que una
ciudad: en cada salva lanza como mucho `lanzacohetes × 4`. Nace con 2, que paga
la obra; admite hasta **6** (tope fijo de la instalación, capacidad física de
sus plataformas); el presidente o el jugador le compra el resto con el mismo
comando que a las ciudades (`enviarDefensas`), y llegan por tierra desde la
capital en un grupo de entrega. Los impactos fuertes pueden destruir alguno;
si la base cae en manos enemigas, sus lanzacohetes pasan al ganador. Se ven
en pantalla los que tiene de verdad.

### 2. Fantasía del jugador

"Esa base del paso tiene seis rampas: si me pongo a tiro me cae una salva de
veinticuatro. Si le revientan dos, dispara menos hasta que le llegue el
convoy." Las rampas se cuentan con la vista, se compran, se pierden y se
reponen: el arsenal de una base deja de ser un número invisible y pasa a ser
algo que se puede leer, atacar y proteger.

### 3. Reglas

1. **Regla única de disparo.** `misilesListos(s) = min(s.misiles,
   s.lanzacohetes × misilesLanzacohetes)` para **todo** sitio (ciudad o
   base). Se borra la excepción de `tipo == 'base'`. Siguen usándola
   `salva`, `golpeCiudad`, `escaramuza`, `objetivo` y `ofensiva`, sin más
   cambios.
2. **Nacimiento.** Al salir el convoy de obra (`construirBase`) se pagan,
   además de lo de hoy (tesoro 60, metal 30), los `lanzacohetesIniciales = 2`
   al precio de las ciudades (`defensasCiudad.coste.lanzacohetes`: 40 de
   dinero, 6 de metal, 2 de petróleo cada uno). Total de la obra: tesoro 140,
   metal 42, petróleo 4. El requisito de `construirBase` pasa a ser
   `tesoro ≥ 140`, `metal ≥ 42`, `petróleo ≥ 4`. El convoy los lleva en
   `construye.lanzacohetes = 2` y la base nace (`llegada`, misión
   `construir`) con `lanzacohetes = 2`. En obras no disparan porque
   `sitiosDe` solo incluye bases terminadas. Constantes:
   `Simulacion.defensasBase = { lanzacohetesIniciales = 2, topeLanzacohetes =
   6, perdidaImpacto = 0.3 }`.
3. **Tope.** `topeLanzacohetesBase = 6` por base, fijo (no depende del nivel
   de ninguna ciudad). Lo que va de camino cuenta, como en las ciudades
   (`enCamino(base.id, 'lanzacohetes')`).
4. **Compra (comando compartido NPC/jugador).** `enviarDefensas` acepta como
   destino una base propia **terminada** (`e.instalaciones[id]`,
   `tipo == 'base'`, `progreso ≥ 1`), solo con `defensa = 'lanzacohetes'`
   (las bases no llevan baterías). Mismo precio y mismo orden de pago que en
   una ciudad, con una diferencia: paga su **ciudad proveedora**, la ciudad
   propia más cercana a la base (la misma que ya le fabrica los misiles en
   `economia`, tabla `basesDe`); si no le alcanza y `pagaTesoro`, el tesoro.
   Metal y petróleo, del almacén del país. Límite:
   `min(cantidad, 6 − lanzacohetes − enCamino)`. En el comando la base va en
   el campo `base` en vez de `ciudad`: `ejecutar({ tipo = 'enviarDefensas',
   nacion, base = id, defensa = 'lanzacohetes', cantidad, pagaTesoro })`.
   `Simulacion.topeLanzacohetes(sitio)` da el tope de una ciudad o de una base.
5. **Entrega.** `entregar` crea el grupo `entrega` desde la capital hasta la
   base (misma velocidad y ruta por tierra que hoy). Al llegar (`llegada`,
   misión `entrega`): si el destino es una base que sigue siendo de la misma
   nación, `lanzacohetes = min(6, lanzacohetes + carga)`; si la base ya no
   existe o es de otro, la carga se pierde (como hoy con las ciudades).
6. **El presidente NPC** repone sus bases justo después de `protegerCiudades`
   (`protegerBases`; primero ciudades, luego bases, en el orden de
   `instalacionesDe`): a cada
   base terminada le pide `6 − lanzacohetes − enCamino` con
   `pagaTesoro = true` (una base siempre es "importante": está orientada al
   vecino). Es un `ejecutar({ tipo = 'enviarDefensas', ... })` como el del
   jugador.
7. **Pérdidas.** En `danarInstalacion`, si la instalación es una base, el
   daño efectivo supera 8 y le quedan lanzacohetes, con probabilidad 0,3
   pierde uno (la misma regla que ya tienen sus tanques).
8. **Toma.** Una base tomada conserva sus lanzacohetes, que pasan al ganador
   con el resto del arsenal. **Destrucción:** se pierden con la base.
9. **Obra que no llega a levantarse** (el sitio ya estaba ocupado y el convoy
   vuelve con `volver`): los 2 lanzacohetes van con él y, al llegar, se suman
   al sitio al que vuelve hasta su tope (base: 6; ciudad: el de su nivel); lo
   que no quepa se desguaza.
10. **Dibujo.** `Mundo:lanzacohetesVisibles(base) = min(base.lanzacohetes,
    6)` si está terminada, 0 si no. `Mundo.lanzacohetesPorBase` pasa a 6 (6
    puestos en el anillo de la base; hoy el radio es 190 px: que el artista
    compruebe que caben sin solaparse).
11. **Partidas guardadas.** Una base sin el campo `lanzacohetes` lo toma como
    2 al cargar, sin coste, para que no se quede muda.
12. **Grupos que salen de una base** (encaje con
    [retirada-y-recuperacion.md](retirada-y-recuperacion.md), opción L1
    elegida): prestan con la misma fórmula que las ciudades
    (`parteLanzacohetes`); el grupo apunta su sitio de origen en `g.origen`
    (antes `g.origenCiudad`, solo ciudades). Los sanos que tiene fuera cuentan
    para el tope de la base (`enCamino`) y al volver se suman a ella (hasta 6;
    lo que no quepa, a la ciudad propia más cercana, hasta su tope). Los
    averiados van a la cola de la ciudad propia más cercana, igual que los
    heridos que vuelven a una base; no cuentan para el tope de la base, al
    repararse quedan en esa ciudad y el presidente vuelve a llenar la base
    comprando (regla 6). Una base no suma fuerza en tierra por sus
    lanzacohetes cuando la atacan.

### 4. Fórmulas

**Misiles por salva.** `listos = min(misiles, L × 4)`, L ∈ [0, 6] → 0–24.
Ejemplo: base con 2 380 misiles y 6 lanzacohetes, salva de ofensiva pedida
con intensidad 0,9 y agresividad 0,7: `floor(azar(3,12) + 0,81 × 0,7 × 100)
= 59–68` pedidos → salen 24. La misma base tras perder 2 lanzacohetes: 16.
Una escaramuza (3–8 pedidos) sale entera con L ≥ 2.

**Coste de la obra.** `60 + 2 × 40 = 140` de tesoro, `30 + 2 × 6 = 42` de
metal, `2 × 2 = 4` de petróleo.

**Coste de llenar una base.** 4 lanzacohetes × (40 + 6 × precio.metal + 2 ×
precio.petroleo) de dinero de la ciudad. Medido (6 semillas, 300 días):
104–137 lanzacohetes comprados por mundo, 6 864–9 042 de dinero de ciudades
y 0–80 del tesoro. Casi todo es el llenado inicial de 2 a 6 (≈ 4 × 30 bases);
las pérdidas por daño son 0–10 por mundo.

**Tiempo hasta el tope.** Desde que la base se termina hasta tener 6: mediana
2 días, p90 2–4 días (lo que tarda la entrega desde la capital).

**Pérdida por daño.** Por impacto con efectivo > 8: 0,3. Una base con
fortificación 1 recibe `daño × 0,2`: hace falta un golpe de > 40 de daño
(12 misiles sin precisión o 9 con precisión pasando las defensas) para
arriesgar un lanzacohetes. Por eso casi solo se pierden en bases jóvenes.

### Medido (300 días, 16 zonas; "días con acción" = días 101–300 con alguna salva, incursión o golpe, métrica del arnés de los criterios aprobados)

Seis semillas oficiales. Cada celda: días con acción / guerras declaradas /
campamentos terminados a los 300 días / salva más grande.

| Variante | 4242 | 1 | 7 | 99 | 12345 | 2026 | Mediana de días |
|---|---|---|---|---|---|---|---|
| Hoy (bases sin límite) | 146/12/133/85 | 82/5/155/73 | 117/10/142/88 | 152/11/142/93 | 133/15/135/112 | 130/9/139/54 | 131,5 |
| **Propuesta: nace con 2, tope 6** | 134/10/139/24 | 83/5/151/24 | 133/11/143/24 | 151/11/140/24 | 128/15/132/24 | 132/8/135/24 | **132,5** |
| Nace con 2, sin reponer nunca | 134/9/135/8 | 89/5/154/8 | 109/12/150/8 | 145/12/136/16 | 135/12/126/12 | 155/9/132/20 | 134,5 |
| Nace con 0, sin reponer | 72/11/145/10 | 43/6/162/12 | 68/11/140/16 | 59/10/145/16 | 59/13/140/12 | 53/9/144/8 | 59 |
| Tope 4 | 109/11/129/16 | 74/6/150/16 | 111/11/146/16 | 168/10/136/16 | 129/13/138/16 | 138/8/132/20 | 120 |
| Tope 8 | 115/13/141/32 | 83/6/150/32 | 104/11/143/32 | 142/11/140/32 | 136/14/134/32 | 131/8/136/32 | 123 |
| Tope 12 | 107/13/139/48 | 82/6/148/35 | 114/10/140/48 | 133/10/142/48 | 119/13/127/48 | 132/8/128/48 | 116,5 |
| Tope por nivel de la proveedora, tabla 4/6/8/10/12 | 125/11/138/32 | 84/5/151/32 | 108/11/151/35 | 158/10/141/32 | 116/13/131/32 | 128/9/132/32 | 120,5 |
| Tope = el de la ciudad proveedora (2/5/10/18/30) | 125/13/142/40 | 84/5/149/23 | 118/11/149/47 | 163/8/133/39 | 119/13/117/40 | 135/8/136/40 | 122 |
| Tope 6 + salva conjunta (ver opción E2) | 107/12/134/50 | 77/7/157/48 | 93/12/152/48 | 162/10/138/48 | 120/13/131/68 | 139/7/134/48 | 113,5 |
| Código real antes de P7 (commit `0d7005c`) | 149/13/123/106 | 81/5/155/73 | 103/8/142/77 | 159/9/128/123 | 131/13/138/83 | 149/8/132/65 | 140 |
| **Implementado** (código real: tope 6, L1, `ritmo.soldados` 25) | 144/13/139/24 | 84/6/154/24 | 97/11/146/24 | 143/8/138/24 | 125/14/132/24 | 139/8/124/24 | **132** |

En la fila de la salva conjunta la salva más grande es la suma de la conjunta.
Las dos últimas filas salen del código real (`medirP7.lua`, ver "Cómo se
midió"); las demás, del prototipo sobre `118e820`, que no tenía retirada.

Treinta semillas más (101–130), para separar la regla del ruido (cambiar el
azar de un día mueve una semilla ±20 días):

| Variante | Mediana de días | Semillas < 80 | Guerras fuera de 5–20 | Campamentos fuera de 110–175 | Mediana de la salva más grande |
|---|---|---|---|---|---|
| Hoy | 140,5 | 4 | 2 | 5 | 71,5 |
| **Propuesta: nace con 2, tope 6** | **134,5** | 2 | 2 | 2 | 24 |
| Nace con 2, sin reponer | 139 | 3 | 2 | 3 | 12 |
| Nace con 0, sin reponer | 53 | 29 | 3 | 1 | 12 |
| Tope 4 | 139,5 | 3 | 2 | 1 | 16 |
| Tope 8 | 133,5 | 3 | 1 | 2 | 32 |
| Tope 12 | 124,5 | 2 | 2 | 3 | 48 |
| Tabla 4/6/8/10/12 | 132 | 2 | 2 | 2 | 32 |
| Tope de la proveedora | 133 | 3 | 2 | 2 | 40 |
| Tope 6 + salva conjunta | 135,5 | 2 | 2 | 4 | 24 por salva (conjunta: mediana 48, máx. 60) |
| Código real antes de P7 (`0d7005c`) | 139,5 | 3 | 2 | 4 | — |
| **Implementado** (código real) | **138,5** | 2 | 1 | 2 | 24 |

Medido con el código real (6 semillas oficiales; 300 días salvo que se diga):

- Salvas: 297, 125, 143, 296, 275, 296 (antes 300, 121, 161, 343, 302, 329);
  desde bases 252, 91, 112, 260, 231, 256. Salva más grande: 24 en todas
  (antes 65–123).
- Bases a los 300 días: 28, 32, 30, 32, 32, 30 (antes 27, 32, 30, 30, 32,
  30; +1,7 %). Media en 30 semillas: 29,5 (antes 29,5). Bases terminadas sin
  lanzacohetes al final: 0.
- Lanzacohetes comprados para bases en 500 días: 122–149 por mundo. Grupos que
  salen de una base con lanzacohetes (L1), en 500 días: 30, 11, 30, 6, 40, 30
  (7–46 lanzacohetes prestados por mundo).
- Ninguna base terminada pasó de 6 en ningún día (500 días); ninguna salva
  pasó de `L × 4`.
- A 500 días, antes → después: convoyes de obra 668–732 → 668–785;
  extracciones 386–482 → 396–497; bases 28–32 → 28–32; combates por tierra
  77–176 → 47–209; instalaciones tomadas 4–15 → 2–18; crímenes de guerra 0–2
  → 0 en las seis semillas.
- Coste: ~5 ms por día simulado, igual que antes (en serie, 300 días,
  semillas 4242, 1 y 7: 4,4–6,4 antes, 5,0–6,2 después).

Otras medidas del prototipo (6 semillas oficiales, 300 días):

- Días con misiles (solo salvas y golpes) en 101–300: 127, 76, 125, 146,
  122, 128 (hoy 139, 75, 108, 149, 126, 126). Mediana en 30 semillas: 126,5
  (hoy 138).
- Salvas: 247, 124, 220, 333, 257, 288 (hoy 275, 120, 207, 321, 309, 270); de
  ellas desde bases 201, 90, 175, 293, 214, 249. Mediana de tamaño 5–6 (hoy
  5–6); p90 15–23 (hoy 8–18); máximo 24 (hoy 54–112).
- Bases a los 300 días: 28, 32, 30, 30, 32, 30 (hoy 28, 32, 28, 30, 32, 29);
  media en 30 semillas 29,6 (hoy 29,4). El coste mayor de la obra no frena
  las bases.
- Bases terminadas sin lanzacohetes al final: 0 en todas las semillas.
- Determinista: dos corridas iguales de la semilla 7 dan el mismo resultado.

Lectura:

1. **Lo que sostiene la acción es que toda base nazca con al menos un
   lanzacohetes.** Con 0, los días con acción caen a 43–72 (29 de 30
   semillas por debajo de 80). Con 2 fijos y sin reponer, la acción es la de
   hoy.
2. **El tope apenas mueve la frecuencia**: entre 4 y 8 las medianas de 30
   semillas (133,5–139,5) están dentro del ruido de hoy (140,5). Las salvas
   grandes tienden a restar días (tope 12: 124,5 en 30 semillas y 116,5 en
   las 6 oficiales, que **no cumple** la mediana ≥ 120): más misiles por
   salva, más cansancio y relaciones que se hunden antes.
3. **Lo que se pierde es el espectáculo de salvas de ~100**: pasan a 24 como
   mucho con tope 6. Si el dueño quiere volver a ver 50–70, la vía que menos
   cuesta es la salva conjunta (opción E2), no subir el tope.
4. **La semilla 1 va justa hoy y con la propuesta** (82 y 83): tiene 5
   guerras en 300 días. No lo causa P7.

### 5. Casos límite

- **Base con misiles y sin lanzacohetes** (se los destruyeron todos): no
  dispara salvas, ni escaramuzas, ni golpes; sigue guardando misiles y siendo
  fábrica. `objetivo(..., 'misiles')` la ignora como origen. El presidente le
  compra en su siguiente pasada diaria de reposición (regla 6).
- **Base con lanzacohetes y sin misiles:** no dispara (`misilesListos = 0`).
- **Ciudad proveedora sin dinero y tesoro < 40:** no se compra nada ese día;
  el comando devuelve `false`.
- **Almacén sin 6 de metal o 2 de petróleo:** no se compra (como en ciudades).
- **La nación pierde la ciudad proveedora:** la proveedora pasa a ser la
  siguiente ciudad propia más cercana; el tope no cambia (es fijo).
- **Base tomada con entrega en camino:** la entrega llega, ve que la base es
  de otro y la carga se pierde.
- **Base destruida con entrega en camino:** igual, se pierde.
- **Base tomada con 6 lanzacohetes:** el ganador recibe 6 y ya no compra
  hasta que pierda alguno.
- **Salva de ofensiva que pide más de 24:** salen 24 (o `misiles` si hay
  menos); el resto no se dispara ese día.
- **"Ablandar una ciudad"** (`ofensiva` con un asalto en camino pide
  `misilesListos(desde)`): con una base de origen salen como mucho 24.
- **Dos salvas del mismo sitio el mismo día** (dos guerras, o guerra y
  escaramuza): cada una hasta 24. Medido: 0–5 veces en 300 días.
- **Partida guardada con bases sin campo `lanzacohetes`:** 2 al cargar.
- **Base en obras atacada:** tiene sus 2 lanzacohetes pero no dispara (no es
  sitio hasta terminarse); los puede perder por daño (regla 7).

### 6. Dependencias

- **Depende de:** [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (obra de bases, fábrica y reparto de misiles, dinero de ciudades, tesoro,
  almacén), `defensasCiudad` (precio y `misilesLanzacohetes`), `entregar` y
  `enCamino`.
- **La usan:** esta misma guerra (salvas, golpes a ciudades, escaramuzas),
  [retirada-y-recuperacion.md](retirada-y-recuperacion.md) (grupos que salen
  de una base con lanzacohetes, regla 12), el dibujo (`mundo/mundo.lua`,
  `lanzacohetesVisibles`, `puestosLanzacohetes`) y el panel de la base en
  `main.lua` (debería mostrar "lanzacohetes 4/6 (+2 en camino)").

### 7. Perillas de ajuste

| Constante | Propuesto | Rango seguro | Qué cambia |
|---|---|---|---|
| `lanzacohetesIniciales` (base) | 2 | 1–4 | Con 0 la acción se hunde (mediana 53–59). Más de 2 encarece la obra sin ganar días. |
| `topeLanzacohetesBase` | 6 | 4–8 | Tamaño máximo de salva desde una base (× 4). 12 ya no cumple la mediana en las 6 semillas. |
| `misilesLanzacohetes` | 4 (hoy) | 4 | Compartida con las ciudades: moverla cambia también sus salvas. |
| Coste por lanzacohetes | 40 dinero, 6 metal, 2 petróleo (hoy, ciudades) | igual que ciudades | Un precio distinto para bases rompería "la misma regla". |
| Pérdida por impacto (base) | 0,3 si efectivo > 8 | 0–0,5 | Medido: 0–10 perdidos por mundo en 300 días. Más alto hace valer la pena atacar bases jóvenes. |
| `Mundo.lanzacohetesPorBase` (puestos visibles) | 6 | = tope | Si es menor que el tope, hay rampas que disparan y no se ven. |

### 8. Criterios de aceptación

Con `arnes.lua` (16 zonas, 300 días; días con acción contados en 101–300) y
las semillas 4242, 1, 7, 99, 12345 y 2026:

Entre paréntesis, lo medido con el **código real** (antes, el prototipo):

- Días con acción ≥ 80 en cada semilla y mediana ≥ 120 (84–144, mediana 132;
  prototipo 83–151, mediana 132,5). **Cumple.**
- Guerras declaradas entre 5 y 20 por semilla (6–14; prototipo 5–15).
  **Cumple.**
- Campamentos terminados a los 300 días entre 110 y 175 (124–154; prototipo
  132–151). **Cumple.**
- Ninguna salva desde un sitio lanza más de `lanzacohetes × 4` misiles
  (0 salvas por encima, envolviendo `salva`). Suma del mismo sitio en un día
  por encima de `L × 4`: como mucho 2 días en 300 (0–2; prototipo 0–2).
  **Cumple.**
- Ninguna base terminada con `lanzacohetes > 6` en ningún día (máximo 6, 500
  días). **Cumple.**
- Ninguna base terminada sin lanzacohetes al final de los 300 días, salvo que
  la nación no tenga metal o dinero para reponer (0). **Cumple.**
- El número de bases a los 300 días cambia menos del 5 % respecto a antes
  (+1,7 % en las 6 semillas; 29,5 frente a 29,5 de media en 30). **Cumple.**
- Los días con acción de las semillas 101–130 tienen mediana ≥ 125 y como
  mucho 3 semillas por debajo de 80 (138,5 y 2; prototipo 134,5 y 2).
  **Cumple.**
- Determinismo: dos simulaciones iguales acaban en el mismo estado, y
  guardar a mitad, cargar y seguir da lo mismo (semillas 4242, 1, 7, 99,
  12345 y 2026, 300 días, guardando el día 150). Una partida de la versión 12
  carga en la 13 con sus bases a 2 lanzacohetes y sigue. **Cumple.**
- En pantalla, una base con L lanzacohetes muestra `min(L, 6)` rampas
  (comprobación visual del artista o captura). **Pendiente** (falta lo
  visual).

No medido: la salva conjunta a 500 días (no se programó). Las tomas de
instalaciones por tierra pasan de 4–15 a 2–18 en 500 días (dentro de los
3–20 de retirada-y-recuperacion.md salvo la semilla 99, con 2; antes 4); no
se ha separado cuánto viene del préstamo de las bases y cuánto del azar
desplazado.

### Decisiones del dueño

1. Tope por base: **A, fijo 6.** La base nace con 2 y la obra cuesta tesoro
   140, metal 42 y petróleo 4.
2. Espectáculo: **E1**, salvas de hasta 24 por sitio; sin salva conjunta.
3. Préstamo: **L1**, integrado con la retirada del commit `0d7005c`.
4. Fuerza en tierra de los lanzacohetes de base: **no se suma**.
5. Interceptores de base sin límite: fuera de P7, sin tocar.

Con P7 se subió también `recuperacion.ritmo.soldados` de 15 a 25 por nivel y
día (ver [retirada-y-recuperacion.md](retirada-y-recuperacion.md)).

### Opciones que se plantearon

1. **Tope por base** (el resto de P7 no depende de esto):
   - **A. Fijo 6 (recomendado).** Salva de base hasta 24. Cumple todos los
     criterios en las 6 semillas (mediana 132,5).
   - B. Fijo 8: hasta 32; mediana 123 en las 6 semillas, 133,5 en 30.
   - C. Por nivel de la ciudad proveedora, tabla 4/6/8/10/12: mejorar ciudades
     hace más fuertes sus bases; mediana 120,5 (justo). Pega con los niveles
     "a lo Bannerlord", pero el tope de una base cambia si cambia su
     proveedora.
   - D. El mismo tope que la ciudad (2/5/10/18/30): mediana 122; una base de
     una ciudad de nivel 1 quedaría en 2 (8 misiles), menos que su propia
     dotación.
2. **Espectáculo de salvas grandes:**
   - E1. Aceptar salvas de hasta 24 por sitio (recomendado para empezar).
   - E2. **Salva conjunta** (ya en la lista como P5): si la salva pedida
     supera lo que puede el sitio, disparan también los demás sitios propios
     a alcance del blanco, del más cercano al más lejano, cada uno hasta su
     límite. Medido con tope 6: la mayor salva conjunta de cada semilla es de
     48–68 (mediana 48 en 30 semillas), con 9–35 salvas conjuntas por mundo
     en 300 días; mediana de días 113,5 en las 6 oficiales (no
     cumple, arrastrada por la 7 y la 1) y 135,5 en 30 semillas. Cada tramo es
     una salva aparte ante las defensas y en la relación, así que castiga más
     la relación que una salva única.
   - E3. Subir el tope a 12: salvas de 48, pero no cumple la mediana en las 6
     semillas (116,5).
3. **Bases que prestan lanzacohetes a sus grupos** (encaje con retirada):
   - **L1 (recomendado).** Prestan con la misma fórmula que las ciudades; los
     sanos vuelven a la base y los averiados se reparan en la ciudad dueña
     del terreno (lo que ya hace `recibirHeridos`); el presidente repone la
     base comprando. Coherente con "la misma regla que las ciudades".
   - L2. No prestan: la base conserva siempre su fuerza de fuego mientras su
     grupo ataca. Más simple, pero es otra excepción de base.
4. **Fuerza en tierra de los lanzacohetes de base.** En una ciudad cada uno
   defiende como 40 soldados (`fuerzaLanzacohetes`). Sumarlo en `combatir`
   para bases sería coherente, pero las bases maduras ya son casi intomables
   (ver P4). Propuesta: no sumarlo por ahora. **No medido.**
5. **Interceptores de base sin límite de baterías** (fuera de P7): dejarlo o
   aplicar también "misma regla que las ciudades" en otra propuesta.

### Cambios para el programador de simulación

Hechos todos los de la simulación (lo de `mundo/mundo.lua` y `main.lua` queda
para lo visual). Detalles que las reglas no decían y se resolvieron así:

- Formato de partida 13. `cargar` pone 2 lanzacohetes a las bases de la
  versión 12 y a las obras de base en camino, y pasa `g.origenCiudad` a
  `g.origen`.
- `enCamino(sitio, 'lanzacohetes')` sirve para ciudades y bases; en una base
  solo cuenta las entregas y los sanos que tiene fuera.
- `huecoLanzacohetes(sitio)`: lo que le cabe a un sitio contando lo que tiene
  fuera o de camino. Lo usan `recibirHeridos` y la vuelta de una obra.
- La pérdida por impacto (regla 7) usa `defensasBase.perdidaImpacto` y tira
  después de la de los tanques.

Lista original:

- `Simulacion.misilesListos`: quitar la rama `tipo == 'base'`.
- Nuevas constantes (junto a `defensasCiudad`): `lanzacohetesIniciales = 2`,
  `topeLanzacohetesBase = 6`. Función `topeLanzacohetes(sitio)` que devuelva
  el tope de ciudad por nivel o 6 si es base, para usarla en `enviarDefensas`,
  `llegada` (entrega) y `recibirHeridos`.
- `construirBase`: comprobar y cobrar el coste de los 2 lanzacohetes; guardar
  `construye.lanzacohetes = 2`.
- `llegada`, misión `construir`: crear la base con `lanzacohetes =
  construye.lanzacohetes or 0`. Misión `entrega`: aceptar destino base (en
  `e.instalaciones`).
- `volver`/`llegada` misión `regreso` de un convoy de obra que no construyó:
  sumar sus lanzacohetes al sitio hasta su tope (regla 9).
- `enviarDefensas`: aceptar una base propia terminada solo para
  `lanzacohetes`; paga la ciudad proveedora (la más cercana) o el tesoro.
- Presidente: tras `protegerCiudades`, reponer bases (regla 6).
- `danarInstalacion`: regla 7.
- `cargar`: bases sin campo `lanzacohetes` → 2.
- `mundo/mundo.lua`: `lanzacohetesVisibles` de base = `min(lanzacohetes, 6)`
  si está terminada; `lanzacohetesPorBase = 6`.
- `main.lua`: mostrar los lanzacohetes de la base en su panel y permitir al
  jugador el mismo comando de compra.
- Si se elige L1: en `ofensiva`, calcular también la parte de lanzacohetes
  cuando `sitio` es una base, y en `recibirHeridos`, devolver los sanos a la
  base cuando `casa` es una base (hasta 6).

### Cómo se midió

Código real (commit de la implementación): `p7/medirP7.lua` en el
scratchpad de la sesión (días con acción en 101–300, guerras, campamentos,
salvas por origen y tamaño, salvas y días por encima de `L × 4`, tope de las
bases, compras y préstamos de las bases, conteos a 500 días y ms por día),
sobre copias congeladas del código antes (`0d7005c`) y después, para no
depender de `mundo/mundo.lua` mientras otro agente lo cambiaba. Además
`det16.lua` (determinismo y guardar/cargar a mitad), `p7/migrar12.lua`
(partida de la versión 12), `p7/invariantes13.lua` (topes y negativos día a
día, 500 días) y `medirRet.lua` (colas de recuperación).

Prototipo:

Prototipo en el scratchpad de la sesión: `lc/arnesLc.lua` (el arnés de los
criterios con más contadores: salvas por origen y por causa, tamaños, bases,
lanzacohetes y misiles al final), `lc/protoLc.lua` (P7 aplicado desde fuera,
con variables de entorno `LC_INI`, `LC_TOPE`, `LC_COSTE`, `LC_DANO`,
`LC_COMPRA`, `LC_TESORO`, `LC_CONJUNTA`), `lc/protoRepite.lua` (salvas
repetidas por sitio y día) y `lc/protoLlenado.lua` (días hasta el tope). Se
midió sobre una copia congelada del commit `118e820`, porque
`simulacion.lua` cambiaba mientras tanto (retirada en curso); el parche no
depende de líneas, solo de nombres de funciones, y también corre sobre el
código en curso.

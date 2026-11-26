# Instalaciones y economía

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Fuentes: `mundo/simulacion.lua` — `producirRecursos` :929, `economia` :941,
`expansion` :1053, `construirExtraccion` :1061, `construirBase` :1104, `obras`
:1165, `enviarGrupo` :567, `moverGrupos` :1296, `llegada` :1241, `alcance` :492,
`dueno` :499. Dibujo: `mundo/instalaciones.lua`.

## 1. Resumen

Las ciudades crecen y producen. La producción paga investigación (7
tecnologías en cadena), soldados en las ciudades y una **fábrica** que rota
entre las bases terminadas y convierte ahorro + recursos en interceptores,
misiles, tanques y aviones. Para crecer, cada nación manda **convoyes**: abren
una carretera a su paso y levantan **complejos de extracción** sobre los
depósitos (producen metal, petróleo o comida) o **bases militares** hacia el
vecino más cercano. Una obra tarda 14–20 días y después se **fortifica** durante
un año. Las instalaciones también dan territorio.

## 2. Fantasía del jugador

Ver cómo un país se extiende: columnas de camiones saliendo de la ciudad,
carreteras que se dibujan sobre el mapa, andamios y grúas, y con el tiempo
muros que se cierran alrededor de minas y bases. Saber que una mina recién
levantada es frágil y que un año después es una fortaleza.

## 3. Reglas

Orden dentro de `avanzarDia` (`:1651`): impactos → `producirRecursos` → por
cada nación viva: `economia`, `expansion`, cansancio × 0,995 → `obras` →
diplomacia → guerras → `moverGrupos`.

### Recursos (`producirRecursos`)

Cada extracción terminada suma a su nación, por día:
`riqueza × 1,2 × (0,3 + 0,7 × salud / 100)` del tipo de su depósito.

### Economía de la nación (`economia`)

Por cada ciudad:

1. Población: `floor(pob × 1,002 + 1)` si la nación tiene comida > 1; si no,
   `× 1,0003`.
2. Producción: `pob × 0,01 × (1 + 0,15 × tecnología)`.
3. Metal +0,15 y comida +0,15.

Después:

4. Comida −0,25 por ciudad (mínimo 0). Neto sin granjas: −0,1 por ciudad y día.
5. Investigación += producción × 0,3. Si llega al coste de la siguiente
   tecnología, la compra (resta el coste); como mucho una por día.
6. Presupuesto = producción × (0,35 + 0,45 × agresividad + 0,6 si está en
   alguna guerra). Tesoro += producción × 0,15.
7. Soldados de cada ciudad += `floor(presupuesto × 0,35 / nºciudades × 0,5)`,
   con techo del 20 % de su población.
8. Fábrica del día: la base terminada nº `1 + día mod nºbases`; si no hay bases,
   la capital. Si es una base, recibe `floor(presupuesto × 0,1)` soldados (sin
   techo). Su `ahorro` += presupuesto × 0,65.
9. Fabricación (cada tirada con el mismo `azar` del día), si tiene la
   tecnología: interceptores 60 % (hasta 3), misiles 70 % (hasta 4), tanques
   40 % (1), aviones 30 % (1). Cada unidad exige ahorro de la fábrica y
   recursos de la nación:

| Unidad | Ahorro | Metal | Petróleo | Fuerza |
|---|---|---|---|---|
| Interceptor | 10 | 1 | — | 1 |
| Misil | 8 | 1 | — | 2 |
| Tanque | 30 | 3 | 1 | 9 |
| Avión | 55 | 4 | 3 | 15 |
| Soldado | (presupuesto) | — | — | 1 |

### Tecnologías (`Simulacion.tecnologias`)

| Nº | Id | Coste | Qué desbloquea en el código |
|---|---|---|---|
| 1 | armas | 40 | Construir bases (`tecnologia >= 1`) |
| 2 | explosivos | 110 | Nada (solo +12 de fuerza y +15 % de producción, como todas) |
| 3 | tanques | 220 | Fabricar tanques |
| 4 | misiles | 380 | Fabricar misiles (y con ellos salvas y golpes a ciudades) |
| 5 | interceptores | 520 | Fabricar interceptores |
| 6 | aviones | 700 | Fabricar aviones (incursiones y cazas) |
| 7 | precision | 1000 | Daño por misil 5 en vez de 3,5 |

Tras la 7 la investigación sigue sumando sin uso.

### Territorio

- Alcance de una ciudad: `4200 + 2·radio + 25·√fuerza(ciudad)`.
- Alcance fijo: extracción 900, base 1 400 (`ALCANCE_INSTALACION`).
- `dueno(x, y)`: de todas las ciudades e instalaciones que cubren el punto
  (`d / alcance < 1`), gana la de menor `d / alcance`. Si ninguna, tierra de nadie.

### Convoyes y carreteras

- `expansion`: cada día intenta una base; la extracción solo cuando
  `(día + turno) mod 3 == 0` (`turno` = posición de la nación en `vivas()`).
- **Un convoy de cada tipo a la vez** por nación (`grupoEnCamino`).
- El convoy es un grupo (`enviarGrupo`, misión `construir`) que sale del sitio
  propio más cercano con suficientes soldados: los resta de allí. Mínimo 10
  soldados para cualquier grupo.
- **Ruta por tierra** (`mundo/rutas.lua`): el convoy y su carretera rodean el
  mar. Si no hay camino por tierra, o daría un rodeo de más de 1,8 veces la
  línea recta (`Rutas.rodeo`), el convoy no sale y la nación prueba otro
  depósito (hasta `Simulacion.intentosRuta = 6` por día). Lo mismo vale para
  bases, refuerzos, ataques y regresos. Con esto los depósitos al otro lado del
  agua quedan fuera de alcance: en la semilla 4242 las extracciones a 500 días
  bajan de 440 a 334 y las bases de 127 a 109 (las cifras de este documento se
  midieron antes de este cambio).
- Avanza `velocidadGrupo = 1600` px/día a lo largo de su ruta; la carretera
  (`estado.carreteras[id]`) crece con él (`progreso` 0→1). Llega cuando le
  queda menos de un día.
- Al llegar crea la instalación: `progreso 0`, `fortificacion 0`, salud máxima
  (extracción 100, base 180), guarnición = el convoy. Si otra nación ya la
  construyó ahí, el convoy vuelve a casa.

### Extracción (`construirExtraccion`)

1. Candidatos: depósitos sin instalación cuyo dueño territorial es nadie o la
   propia nación, a menos de `2,4 × alcance` de una ciudad propia.
2. Elige el más cercano a cualquiera de sus ciudades.
3. Sale del sitio (ciudad o base terminada) más cercano con ≥ 50 soldados;
   manda 40 soldados y 0 tanques.

### Bases (`construirBase`)

1. Requisitos: tecnología ≥ 1, tesoro ≥ 60, contador `n.bases < 4 × nºciudades`
   (`basesPorCiudad = 4`).
2. Ciudad de origen: la que tenga menos bases propias dentro de su alcance
   (menos de 4).
3. Rumbo hacia la ciudad extranjera más cercana, desplazado
   `(bases_que_ya_tiene − 1,5) × 0,9` rad para abrirlas en abanico.
4. Hasta 8 intentos: ángulo ±0,5 rad, distancia `alcance × (0,35..0,8)`. El
   punto debe ser territorio propio y `sitioValido` (altura 18–200, fuera de
   ciudades).
5. En el primer punto válido: sale del sitio más cercano con ≥ 60 soldados,
   con 60 soldados y 1 tanque; tesoro −60; `n.bases + 1`. Se hace `return` tanto
   si sale el convoy como si no.
6. **Implementado (P7 de [guerra.md](guerra.md#p7-lanzacohetes-en-las-bases-implementado)):**
   la obra paga además 2 lanzacohetes (tesoro 140, metal 42, petróleo 4 en
   total; hace falta tenerlo todo para empezarla) y la base nace con ellos;
   admite hasta 6, que se compran con `enviarDefensas` (campo `base`) pagando
   la ciudad propia más cercana (la que le fabrica los misiles) o el tesoro.
   Sin lanzacohetes, la base no dispara. Medido con el código real: el número
   de bases no cambia (29,5 de media en 30 semillas, igual que antes).

### Obras y fortificación (`obras`)

- En obras: `progreso += 0,05 × min(1,5; soldados / 40)`.
- Terminada: `fortificacion += 1/365` (máximo 1) y, si no la atacaron en los
  últimos 3 días, `salud += 2` hasta el máximo.
- La fortificación reduce el daño (`× (1 − 0,8·fort)`) y multiplica la defensa
  en combate (`× (1 + fort)`): ver [guerra.md](guerra.md). En obras recibe
  ×1,5 de daño.

## 4. Fórmulas

**Producción.** Nación de 2 ciudades de 5 000 hab., tecnología 3:
`10 000 × 0,01 × 1,45 = 145/día`. Investigación +43,5/día. Presupuesto con
agresividad 0,5 en paz: `145 × 0,575 = 83`; en guerra `145 × 1,175 = 170`.
Soldados por ciudad `floor(83 × 0,35 / 2 × 0,5) = 7/día`. Ahorro de la fábrica
+54/día (≈ 5 interceptores o 6 misiles de ahorro).

**Población.** `× 1,002/día` ≈ ×2,07 por año de juego. Medido (semilla 4242):
mediana 5 365 el día 1, 14 985 el día 500, 41 124 el día 1000. Sin techo.

**Tecnología (día en que llega, 6 semillas, mediana por semilla):** armas día
2–3, misiles día 12–19, precisión día 34–55. La más lenta en llegar a precisión:
día 158.

**Extracción.** Riqueza 2, salud 100: 2,4/día. Con salud 0: 0,72/día.

**Obra.** 40 soldados → 20 días; ≥ 60 soldados → 14 días. Medido: mediana 20,
mínimo 14, máximo 100 (guarnición diezmada por ataques).

**Convoy.** Medido: mediana 3 días de viaje, máximo 17.

**Fortificación.** 365 días para el máximo. Medido el día 500: mediana 1,0,
media 0,91.

**Crecimiento de instalaciones (semilla 4242):**

| Día | Extracción | Bases |
|---|---|---|
| 100 | 264 | 124 |
| 200 | 392 | 128 |
| 300 | 420 | 127 |
| 500 | 440 | 127 |
| 1000 | 512 | 131 |

**Día 500, 6 semillas:**

| Medida | Valor |
|---|---|
| Extracciones | 426–537 (11,2–14,2 por ciudad) |
| Depósitos explotados | 69–87 % |
| Bases | 127–202 (4,0–4,2 por ciudad) |
| Soldados por base, mediana | 1 622–2 266 (máx. ~4 070) |
| Soldados en ciudades | 20 % de la población (el techo) casi siempre |
| Metal final por nación, mediana | 2 192–6 030 (mínimo 0,75–2 557) |
| Alcance de ciudad | 5 071–6 181 (día 1) → 5 690–7 327 (día 500) |
| Unidades totales (4242) | 12 381 misiles, 6 342 interceptores, 2 415 tanques, 1 336 aviones, 376 555 soldados |
| Partida guardada | 1,2–1,6 MB (1,8 MB a 1000 días) |

## 5. Casos límite

- **Sin comida:** población casi estancada (×1,0003). Con ~41 % de depósitos
  de comida es raro; las reservas medidas son de miles.
- **Sin metal:** no se fabrica nada; en 3 de 6 semillas alguna nación acaba con
  < 12 de metal (1 de ellas con 0,75): queda sin misiles ni interceptores
  nuevos.
- **Nación sin bases terminadas:** la capital es la fábrica (y guarda misiles
  e interceptores: defiende la capital, no el frente).
- **Sitio sin 50/60 soldados:** no sale convoy ese día; se reintenta.
- **Primer punto válido de base sin sitio con soldados:** se abandona el intento
  del día, sin gastar tesoro.
- **Dos naciones al mismo depósito:** el primero en llegar construye; el otro
  vuelve a casa.
- **Base tomada por otra nación:** el contador `n.bases` del antiguo dueño no
  baja y el del nuevo no sube. El perdedor no puede reponerla; el ganador puede
  pasar de 4 por ciudad (medido: nación con 1 ciudad y 8 bases).
- **Base destruida:** `n.bases − 1`, se puede volver a levantar.
- **Extracción tomada o cedida:** produce para el nuevo dueño desde el día
  siguiente; su carretera se borra.
- **Soldados de las bases:** crecen sin techo (+10 % del presupuesto cada vez
  que son fábrica).
- **Tras la tecnología 7:** la investigación se acumula sin uso.
- **Tesoro:** solo se gasta en bases (60 cada una); después se acumula.

## 6. Dependencias

- **Sustituido en parte:** la economía de este documento (fábricas,
  reclutamiento, presupuesto, dinero de las ciudades) la sustituye
  [economia.md](economia.md), decidido el 2026-09-30. El crecimiento de la
  población (×1,002 al día) lo sustituye [poblacion.md](poblacion.md)
  (decidido, sin programar).
- **Depende de:** [mundo-fisico.md](mundo-fisico.md) (depósitos, radio,
  `sitioValido`), [naciones-y-politica.md](naciones-y-politica.md) (agresividad,
  si hay guerra), [guerra.md](guerra.md) (daño, salud, tomas y destrucción),
  [diplomacia.md](diplomacia.md) (cesiones).
- **Lo usan:** [guerra.md](guerra.md) (sitios, arsenales, fortificación,
  guarniciones), [naciones-y-politica.md](naciones-y-politica.md) (fuerza,
  disputa por recursos, reservas → necesidad; campamentos como punto de
  codicia y necesidad de expansión), [diplomacia.md](diplomacia.md)
  (qué se cede), [retirada-y-recuperacion.md](retirada-y-recuperacion.md) (PROPUESTO: dinero de
  ciudades y tesoro, niveles, hambre, tope de defensas de ciudad).
- **Implementado:** P7 de [guerra.md](guerra.md) (lanzacohetes en las bases) usa
  el coste de obra de las bases, el dinero de la ciudad proveedora, el tesoro
  y el almacén para comprarlos.

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| Crecimiento de población | 1,002 / 1,0003 | 1,0005–1,002 | Hoy exponencial sin techo; manda en todo lo demás. |
| Producción por habitante | 0,01 | 0,005–0,02 | Ritmo global de la economía. |
| Bonus por tecnología | +15 % | 5–20 % | Ventaja de ir por delante. |
| Parte a investigación | 0,3 | 0,05–0,3 | Con 0,3 todo está investigado a los ~45 días. |
| Costes de tecnología | 40…1000 | ×1–×20 | Duración de la carrera tecnológica. |
| Presupuesto | 0,35 + 0,45·agr + 0,6 guerra | — | Tamaño de los arsenales. |
| Techo de soldados en ciudad | 20 % pob. | 5–25 % | Alcance de ciudad y fuerza. |
| Costes de unidades | tabla | — | Qué se fabrica. Hoy el ahorro limita más que los recursos. |
| Producción de extracción | riqueza × 1,2 | 0,2–1,2 | Si se añade consumo, esto decide la escasez. |
| `basesPorCiudad` | 4 | 2–6 | Techo de bases; hoy se alcanza hacia el día 100. |
| Coste de base (tesoro) | 60 | 60–500 | Ritmo de construcción de bases. |
| `velocidadGrupo` | 1 600 px/día | 800–4 000 | Convoyes, refuerzos y ataques terrestres. |
| Convoy de extracción | cada 3 días, 40 soldados | — | Ritmo de expansión. |
| Radio de extracción | 2,4 × alcance | 1,5–3 | Hasta dónde se estiran las naciones. |
| Obra | 0,05 × min(1,5; sold/40) | — | 14–20 días hoy. |
| Fortificación | 1/365 por día | 1/90–1/730 | Cuánto tarda una instalación en ser dura. |
| Reparación | +2/día tras 3 días sin ataques | 1–5 | Resistencia a desgaste. |
| `ALCANCE_INSTALACION` | 900 / 1 400 | — | Territorio que dan. |

## 8. Criterios de aceptación

16 zonas, 500 días (valores medidos entre paréntesis):

- Entre 10 y 15 extracciones por ciudad (11,2–14,2).
- Entre 3,8 y 4,5 bases por ciudad (4,0–4,2).
- Obra: mediana 20 días, mínimo 14 (idéntico en las 6 semillas).
- Convoy: mediana ≤ 4 días de viaje (3).
- Fortificación mediana el día 500 = 1 (1,0).
- Menos de 6 ms por día simulado con ~15 naciones y ~600 instalaciones
  (mediana 2,9–5,3 ms; máximo 11,5 ms).
- Guardar a mitad y cargar da el mismo estado que no parar (comprobado, 4242).

No medido: coste de repintar el territorio (`Territorio.mallaTrozo`), ni de
dibujar cientos de instalaciones.

## Propuestas (no implementadas)

- **P1. Dar sentido a los recursos.** Hoy se acumulan miles. Opciones:
  (a) mantenimiento diario por unidad (petróleo por tanque/avión, comida por
  soldado); (b) techo de almacén por nación; (c) consumo de comida por
  población, no por ciudad. Efecto: las extracciones pasarían a ser vitales y
  la guerra por ellas tendría consecuencias.
- **P2. Techo de población** (logística hacia un máximo según radio) para que
  la economía no sea exponencial.
- **P3. Carrera tecnológica más larga**: multiplicar costes ×10 o bajar la
  parte de investigación a 0,05. Hoy todo está investigado en ~1 hora de juego.
- **P4. Corregir el contador `n.bases`** al tomar o ceder bases (restar al que
  pierde, sumar al que gana), o contar las bases reales con `instalacionesDe`.
- **P5. Techo de soldados por base.**
- **P6. Uso del tesoro** más allá de bases (sobornos, reconstrucción, ayuda).

## Campamentos

### Cómo era antes del mantenimiento (commit eb5bd72)

Este apartado describe el código hasta el commit eb5bd72 y sus medidas; lo que
cambia (mantenimiento, sin topes ocultos) está en el apartado siguiente, ya
programado.

Cada país tiene una sola ciudad, su capital. El resto de su tierra la gana
con campamentos: banderas que hacen suyo el terreno de alrededor, como en
Warpath, y que producen. No son ciudades: no tienen gente, ni comida, ni
nivel.

- **Acción:** `Simulacion:ejecutar({ tipo = 'campamento', nacion, x, y })`, la
  misma para un presidente NPC y para un jugador (`levantarCampamento`).
- **Dónde:** solo dentro del territorio propio (siempre conectado a él), en
  tierra construible y a más de `separacion = 2 400` px de otro campamento
  suyo o de su capital.
- **Coste:** 40 de dinero (tesoro del presidente), 10 de metal y 6 de petróleo
  (almacén del país). Sale una tropa de 15 soldados; no se ve por el camino:
  tarda el viaje y aparece allí.
- **Obra:** 6 días desde que llega. Su territorio (`alcance = 3 000`, 300 m,
  con el borde tipo mapa) cuenta solo cuando está terminado.
- **Produce** cada día, terminado: 0,3 de metal y 0,15 de petróleo al almacén
  del país y 1,5 de dinero al tesoro del presidente. No cuesta nada mantenerlo.
- **Destrucción:** 30 de salud y no se fortifica. Se repara +2 al día tras 3
  días sin ataques, pagando 0,5 de metal (`obras`). Las escaramuzas y las
  guerras lo atacan con misiles; un ejército que vence a su guarnición arranca
  la bandera (no se toma). Al caer, su terreno y su producción se pierden.
- **NPC (`planearCampamento`):** cada `cadaDias = 4` días (desfasado por
  nación), si tesoro ≥ 100 (40 + `reservaTesoro` 60), metal ≥ 30 (10 + la
  mitad de `reservaMetal`) y petróleo ≥ 16, **y no tiene otro campamento en
  camino**, busca la meta (el depósito sin dueño más cercano a menos de
  `alcanceCodicia` = 60 000 px de su capital o, si no hay, la ciudad extranjera
  más cercana a menos de 110 000) y planta en el último punto propio de un rayo
  desde su capital hacia la meta (5 rumbos: 0, ±0,4, ±0,8 rad), **de 40 pasos
  de 250 px como mucho**.

**Dos topes ocultos en el NPC** (el comando del jugador no los tiene):

1. *Uno a la vez:* no planta si ya tiene una tropa de campamento en camino.
   Choca con la regla del juego (sin turnos; solo recursos y tiempo).
2. *Rayo de 10 000 px:* 40 × 250 = 10 000 px desde la capital. Es un tope
   geométrico: el campamento más lejano está a **10 000 px exactos en las 6
   semillas**, y a 500 días el total se queda en 296–299 (4242 y 12345).

**Qué frenaba entonces** (4242, motivo cuando el presidente piensa):

| Días | Motivo más frecuente |
|---|---|
| 1–100 | Falta metal: 273 de 347 veces (planta 29) |
| 101–200 | Planta 157; uno en camino 64; falta metal 93 |
| 201–300 | **No encuentra sitio: 171**; uno en camino 60; planta 97 |

El coste no frena nunca: el día 300 el tesoro está entre 8 044 y 20 505, y
metal y petróleo topados en 349–350 (el almacén) en 13 de 14 países. Un
campamento (10 de metal) cuesta menos que medio día de ingresos de metal: el
día 300 entran 23–64 de metal al día en 13 de 14 países. La cadena no viene de lo que produce el campamento (0,3 de metal),
sino de que nada cuesta mantenerlo.

**Medido entonces** (arnés sin ventana, LuaJIT, 16 zonas, 300 días, semillas 4242,
1, 7, 99, 12345 y 2026):

| Medida | Rango |
|---|---|
| Campamentos terminados | 248–317 (mediana por país 16–21) |
| Serie 4242 (días 50/100/150/200/250/300) | 0 / 21 / 81 / 170 / 240 / 277 |
| Días con necesidad > 0 (días 201–300, % nación-día) | 11–33 % |
| Tiempo de simulación por día | 8,7–10,7 ms |

### Freno solo económico (implementado)

**Resumen.** Mantener un campamento cuesta petróleo cada día, y cuesta más
cuanto más lejos está de su ciudad (la línea de suministro). El país crece
mientras su petróleo lo sostenga; cuando no le da para el siguiente
campamento, lo necesita, y ese petróleo lo tiene el vecino. No hay ningún tope
de cantidad ni de ritmo: el límite es lo que entra de petróleo, y crece al
subir el nivel de la capital y al ganar pozos.

**Fantasía.** "Mis banderas llegan hasta donde llegan mis camiones de
combustible. Para ir más lejos necesito los pozos del vecino."

#### Reglas

- **C1. Mantenimiento.** Cada campamento *terminado* cuesta cada día
  `mant(i)` de petróleo (fórmula abajo). Los que están en obra o con la tropa
  en camino no pagan.
- **C2. Pago.** En `producirRecursos`, justo después de producir (todos los
  campamentos terminados producen ese día, se paguen o no), cada nación paga
  sus campamentos **del más cercano al más lejano** a su ciudad (empate: por
  `id`). Si su petróleo no alcanza para el siguiente, ese y todos los que quedan
  por pagar ese día quedan *desabastecidos*.
- **C3. Desabasto.** Un campamento desabastecido pierde 5 de salud ese día. Con
  la reparación de hoy (+2 tras 3 días sin ataques) pierde 3 netos al día: de 30
  a 0 en 10 días seguidos sin pagar. A 0 se **abandona**: se borra, pierde su
  territorio, noticia "X abandona un campamento por falta de suministro", sin
  cansancio de guerra (no lo ha destruido nadie). Su guarnición (soldados y
  tanques) no se pierde: sale como un grupo en misión `regreso` hacia la ciudad
  propia más cercana (`ciudadDuena`, la misma que fija su mantenimiento) y, al
  llegar, se suma a ella. Si la nación no tiene ciudad, la guarnición se pierde.
  Esto es solo del abandono: si el enemigo destruye el campamento
  (`destruirInstalacion`), la guarnición muere con él. El día que vuelve a
  pagarse deja de perder salud.
- **C4. Reservas.** `reservas(nid)` suma el mantenimiento al gasto de petróleo
  (`gasta` = combustible de tanques y aviones + Σ `mant`). Así el estado
  (holgado, justo, escasez, crisis) y la necesidad lo reflejan.
- **C5. Decisión del NPC.** Además de las condiciones de hoy (tesoro ≥ 100,
  metal ≥ 30, petróleo ≥ 16), el presidente solo planta si su petróleo aguanta
  el nuevo y los que ya están en obra o en camino:
  `balance − (enObra + 1) × mantSiguiente ≥ margen`. Si no, no planta. Esta
  comprobación es del NPC; el jugador puede plantar sin ella y pagar las
  consecuencias (C3).
- **C6. Quitar los dos topes ocultos.** Sin "uno a la vez" (se borra la
  condición `grupoEnCamino` de `planearCampamento`) y el rayo sin límite de
  pasos (sigue hasta salir del territorio propio o pasar la meta, como ya hace).
  `cadaDias = 4` se queda como el ritmo al que piensa el NPC, no como límite:
  medido con `cadaDias = 1`, el total sube entre un 4 y un 26 % (145–176 frente a
  133–155; ver tabla).
- **C7. Necesidad de expansión.** Si `balance < mantSiguiente` (no le da para
  el siguiente campamento), la necesidad de petróleo del país es al menos
  `necesidadExpansion = 0,3` (como la de "fábrica" que ya existe). Es lo que le
  hace codiciar los pozos del vecino (ver
  [naciones-y-politica.md](naciones-y-politica.md), codicia).

#### Fórmulas

- `mant(i) = mP × (d(i) / dRef)²`, con `d(i)` = distancia en px del campamento a
  la ciudad propia más cercana (`ciudadDuena`; hoy, la capital), `mP = 1,0` y
  `dRef = 5 000`. El campamento está a 2 400 px como mínimo (`separacion`) y
  hasta unos 13 000 medidos. Rango: 0,23–6,8 de petróleo al día.
  Ejemplos: d = 2 400 → 0,23; 5 000 → 1,0; 7 500 → 2,25; 10 000 → 4,0;
  13 000 → 6,76. Lo neto de un campamento es 0,15 − `mant`: pierde petróleo
  desde el primero; lo que gana es territorio, metal (0,3) y dinero (1,5).
- `balance = entra − gasta`, con `entra` = petróleo que entra al día (pozos y
  campamentos) y `gasta` = combustible + Σ `mant` (C4).
- `mantSiguiente = mP × ((dMax + separacion) / dRef)²`, con `dMax` = distancia a
  su ciudad del campamento propio más lejano (terminado o en obra; 0 si no
  tiene). Sin campamentos: (2 400 / 5 000)² = 0,23.
- Condición del NPC (C5): `balance − (enObra + 1) × mantSiguiente ≥ margen`,
  con `margen = 0,5` al día.

**Ejemplo.** Entran 30 de petróleo; gasta 2 de combustible y 20 de
mantenimiento: `balance` = 8. Su campamento más lejano está a 9 000:
`mantSiguiente` = ((9 000 + 2 400) / 5 000)² = 5,2. No tiene ninguno en obra:
8 − 5,2 = 2,8 ≥ 0,5, así que planta. Cuando ese está terminado, a 11 400:
`balance` = 8 − 5,2 = 2,8 y `mantSiguiente` = (13 800 / 5 000)² = 7,6.
2,8 − 7,6 < 0,5: no planta, y como 2,8 < 7,6 su necesidad de petróleo pasa a
ser 0,3 (C7).

Por qué es cuadrática: el número de campamentos de un anillo crece con el
radio y el coste de cada uno, con el cuadrado del radio. El total crece mucho
más deprisa que lo que da el territorio, así que hay un radio de equilibrio que
se amplía cuando entra más petróleo (nivel de la capital, pozos ganados).
Medido con una fórmula lineal (`mant = mP × d / dRef`), no frena: con `mP` = 0,5
salen 389 campamentos (4242), más que antes (277).

#### Casos límite

- **País sin petróleo:** su `balance` es ≤ 0 desde el principio. El NPC no
  planta nunca (C5) y su necesidad de petróleo es ≥ 0,3 (C7): será agresor.
  Medido: con las reglas programadas hay países con 0–2 campamentos (semillas
  7, 99 y 2026). Los dos que se revisaron (Tentor, 7, y Quenu, 99) tienen el
  día 300 el petróleo lleno (348 y 350) y gasto 0: no los frena el petróleo.
  En la versión anterior (eb5bd72) les frenaba la **falta de metal** (69 de 75
  y 75 de 75 veces que lo piensan), así que ya les pasaba sin el
  mantenimiento.
- **Pierde un pozo en la guerra:** baja `entra`, el `balance` puede quedar
  negativo y se vacía el almacén. Después caen desabastecidos los más lejanos
  (C2) y, tras 10 días seguidos, se abandonan. El país se encoge por el borde
  hasta donde su petróleo llega.
- **Almacén vacío y campamentos en obra:** los que están en obra no pagan
  (C1). Al terminar entran en la cola de pago; si no llega, quedan
  desabastecidos desde su primer día.
- **Campamento atacado y desabastecido a la vez:** pierde por las dos cosas y
  no se repara (lleva menos de 3 días sin ataques). Se pierde antes.
- **Nación con más de una ciudad** (por una cesión): `d(i)` se mide a la ciudad
  propia más cercana, así que una ciudad nueva abarata los campamentos de
  alrededor.
- **Nación sin ciudades** (muerta, no está en `vivas`): no paga ni se le
  abandona nada por suministro. Qué pasa con sus campamentos no está definido
  hoy (no medido).
- **Jugador que se estira de más:** puede (C5 es solo del NPC). Paga con C3:
  pierde los más lejanos primero.

#### Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `campamento.mantenimiento` (`mP`) | 1,0 | 0,8–1,5 | Tamaño del país. Medido: 0,5 → 192–266 campamentos; 1,0 → 133–155; 1,5 → 87–104. |
| `campamento.distanciaRef` (`dRef`) | 5 000 | 4 000–6 000 | Igual que `mP` pero cambia la forma: más bajo castiga más los lejanos. No medido aparte. |
| Exponente de la distancia | 2 | 2 | Con 1 no frena (medido). Más de 2, no medido. |
| `campamento.margen` | 0,5 | 0–2 | Colchón del NPC. Más alto: menos campamentos y menos desabasto. |
| `campamento.desabasto` | 5 de salud al día | 3–10 | Con 3 y la reparación de +2 casi no se pierden; con 10 caen en 4 días. |
| `necesidad.expansion` | 0,3 | 0–0,5 | Codicia del que ya no puede crecer. Medido: 0 → 52 guerras en 6 semillas; 0,3 → 62. |
| `campamento.cadaDias` | 4 | 1–4 | Ritmo al que piensa el NPC. Medido: 1 → 145–176 campamentos (4 → 133–155). |

Coste de construcción (40 / 10 / 6) y producción (0,3 / 0,15 / 1,5): sin
cambios. El dinero no frena porque el tesoro se desborda por otras vías (ver
P6): cobrar mantenimiento en dinero no serviría hasta arreglar eso (no medido).

#### Criterios de aceptación

Arnés sin ventana, 16 zonas, semillas 4242, 1, 7, 99, 12345 y 2026. Entre
paréntesis, lo medido con las reglas ya programadas en `simulacion.lua` (da
exactamente lo mismo que el prototipo del arnés):

- A 300 días, entre 110 y 175 campamentos terminados en cada semilla (133–155),
  con la mediana por país entre 6 y 12 (8–10) y ningún país por encima de 25
  (máximo 19).
- Se frena sin parar: en todas las semillas se plantan menos entre los días
  201 y 300 que entre el 101 y el 200 (0,57 a 0,94 veces), y a 500 días el
  total es como mucho 1,4 veces el del día 300 (4242, 12345 y 1: 1,24–1,29).
- Ningún tope oculto: el campamento más lejano pasa de 10 000 px en todas las
  semillas (11 249–13 000).
- Con `cadaDias = 1` el total sube menos de un 30 % (entre +4 y +26 %): lo
  limita la economía, no el ritmo al que piensa el NPC.
- Abandonos por desabasto: como mucho 5 por partida de 300 días (0; días de
  desabasto 0–3).
- Escasez: entre el 50 y el 90 % de los días nación de los días 201–300 con
  alguna necesidad > 0 (65–79 %; hoy 11–33 %).
- Menos de 10 ms por día simulado (4,9–5,6 ms de media, cada semilla sola;
  antes 8,7–10,7).
- Guardar a mitad y cargar da el mismo estado (medido: 300 días, guardar el
  día 150, cargar y seguir da el mismo texto de `guardar()` que no parar, y dos
  partidas con la misma semilla dan el mismo texto, en las 6 semillas).
- A 500 días los abandonos siguen siendo raros (12345: 2, con 37
  campamento-día de desabasto; 4242 y 1: 0).
  En 12345 esos 2 abandonos devuelven 30 soldados (0 tanques) a su ciudad.

#### Variantes medidas (300 días, 6 semillas)

| Variante | Campamentos | Guerras (suma de 6) | Guerras por semilla |
|---|---|---|---|
| Antes (eb5bd72) | 248–317 | 14 | 1–4 |
| Solo mantenimiento cuadrático, `mP` 1,0 | 112–158 | 18 | 1–6 |
| + codicia desde campamentos a 60 000 + expansión 0,3 | 115–158 | 24 | 1–6 |
| **Programada:** mantenimiento 1,0 + expansión 0,3 + codicia a 80 000 desde capital y campamentos | **133–155** | **62** | **5–15** |
| La programada con `cadaDias = 1` | 145–176 | 60 | 6–14 |

#### En el código

- `mantenimientoCampamento(i)`, `mantenimientoCampamentos(nid)` y
  `mantenimientoSiguiente(nid)`: `mant(i)`, Σ `mant` y `mantSiguiente`.
- `producirRecursos` → `mantenerCampamentos(n)`: tras producir, cobra por
  nación viva en el orden de C2 y aplica C3.
- `reservas`: suma Σ `mant` al `gasta` del petróleo (C4).
- `necesidades`: aplica C7 después de calcular el estado.
- `planearCampamento`: sin `grupoEnCamino`, rayo sin límite de pasos y con la
  condición de C5; la meta usa `campamento.alcanceMeta = 60 000`.
- Constantes en `Simulacion.campamento`: `mantenimiento = 1.0`,
  `distanciaRef = 5000`, `margen = 0.5`, `desabasto = 5`, `alcanceMeta =
  60000`; y `Simulacion.necesidad.expansion = 0.3`.
- No añade estado guardado (solo cambia la salud); no hay marca
  `desabastecido` para la interfaz. Las partidas de la versión 11 se cargan
  igual.

**Dependencias.** Depende de [naciones-y-politica.md](naciones-y-politica.md)
(la necesidad alimenta la codicia) y de [guerra.md](guerra.md) (perder pozos
baja el `balance`). Lo usa [naciones-y-politica.md](naciones-y-politica.md): la
necesidad de expansión (C7) y los campamentos como punto desde donde se
codicia.

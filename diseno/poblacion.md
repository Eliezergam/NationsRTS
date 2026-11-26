# Población: demografía por edades y sexo

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Documento para Andrés (simulación), Valeria (vista) y Elena (mediciones).
Estado: **decidido por el dueño el 2026-09-30 (§11), sin programar.** Lo
marcado «hoy» es lo que hace el
código en HEAD 17600fc (guardado versión 22, economía cerrada ya programada
en 454050d y 975c9a8). Las cifras salen de `tools/medir_poblacion_nationsrts.lua`
(ver «Cómo se midió»): 4 semillas (1, 7, 42 y 1234), 500 días y, para ver si
explota, 1 000 días; 20 a 22 naciones por semilla.

Sale de la pregunta sobre la economía cerrada «¿un soldado muerto resta
población?» y de la respuesta del dueño (2026-09-30): «Sí, restan de la
población, pero entonces agregarías parejas de mujeres y hombres para que se
reproduzca y tengan edades y sean reclutamiento».

Todo es ficticio: las ciudades, sus nombres y sus habitantes son inventados.

---

## 0. Estado de hoy

Cada nación tiene hoy una sola ciudad, su capital (medido: 22 de 22 naciones
con 1 ciudad en la semilla 1). Una ciudad puede cambiar de dueño cedida en una
paz (`cederCiudad`, produccion.lua l.661).

| Pieza | Hoy | Dónde |
|---|---|---|
| Población | Un número por ciudad, `c.poblacion`, sin edades ni sexo | `registrarZona`, simulacion.lua l.998 |
| Población inicial | `floor(radio × azar(8, 14) × 1,4)` en la capital. Medido (semilla 1): 3 645 a 11 047, mediana 6 661 | l.998 |
| Crecimiento | `floor(poblacion × 1,002 + 1)` al día, sin techo | `economia`, l.2313 |
| Hambre | `poblacion × (1 − 0,003)` al día, nunca por debajo de 10 | l.2310 |
| Soldados | Forman parte de la población (`trabajadores = poblacion − soldados`) | `trabajoCiudad`, produccion.lua l.606 |
| Soldado muerto | **No resta población.** Solo se anota `muertos` | batallas.lua l.147, l.165, l.417, l.821; simulacion.lua l.1868 |
| Cuántos soldados caben | F1b de economia.md: `floor(poblacion × 0,2) − soldados de la ciudad` | `maximoSoldados`, produccion.lua l.345 |
| Dinero del trabajo | `(poblacion − soldados) × 0,01 × …` | `trabajoCiudad`, l.606 |

**Lo medido hoy** (500 días, 4 semillas; por nación, mediana del día 500 con
el rango entre semillas):

| Qué | Día 500 | Día 1 000 |
|---|---|---|
| Población | 16 438 – 22 197 (×2,75 – ×2,78 desde el día 0) | 45 070 – 60 708 (×6,94 – ×7,53) |
| Soldados | 3 260 – 4 317 (19 – 20 % de la población) | 6 000 en las 4 semillas (el tope de nivel 5) |
| Aún reclutables por F1b | 0 – 98 | 3 013 – 6 141 |
| Tesoro (dinero) | 67 – 582 | 11 699 – 16 868 |
| Dinero del trabajo, por nación y día | 63,5 – 83,3 | 122,3 – 161,0 |
| Muertos en combate, por nación y día | 1,03 – 1,44 | 1,57 – 1,94 |

Lectura: hasta el día 500 el ejército lo limita **la población** (F1b está
casi siempre al máximo), no el tope por nivel. Después la población crece sin
techo, el ejército se queda en el tope y el tesoro se dispara.

---

## 1. Resumen

Cada ciudad guarda a su gente en **cohortes**: cuántos hombres y cuántas
mujeres tienen cada edad, de 0 a 89 años (90 números por sexo), y de cada
cohorte cuántos están **en filas**. Un año de juego dura `anio` = 10 días: ese
día todas las cohortes cumplen un año. Cada día nacen niños según las
**parejas** (mujeres de 15 a 49 y hombres de 15 a 64, también los soldados,
estén donde estén), con menos nacimientos si falta comida, si la ciudad está
llena o si está sitiada, y con un factor por nación que fijará el futuro
sistema de política (hijos por pareja); muere gente de causas naturales según su
edad, y más con hambre. Solo se reclutan **adultos en edad militar** (18 a 49
años) y como mucho la mitad de ellos; al encargar soldados salen de sus
cohortes. Los **muertos en combate** salen de la población, de la cohorte de
donde vinieron; los heridos siguen vivos y vuelven. Al cumplir 60, el soldado
que está en casa se **retira** y vuelve a ser civil. Trabajan los civiles de 15
a 64 años. No hay individuos: son recuentos enteros, iguales en cualquier
máquina.

## 2. Fantasía del jugador

- «Mis soldados son mi gente. Cada uno que muere es un hijo de mi ciudad que
  no vuelve.»
- «Cada soldado que cae es un padre o una madre menos: la guerra larga se nota
  en la cuna.»
- «Los chicos que nacieron cuando fundé la ciudad ya tienen edad de alistarse:
  mi ejército crece con mi pueblo.»
- «Mi ciudad está llena: si quiero más gente, tengo que subirla de nivel.»
- «En la pirámide veo cuántos jóvenes tengo, cuántos están en filas y cuántos
  veteranos se me retiran este año.»

## 3. Reglas

### 3.1 Qué se guarda

Por ciudad, `c.demografia`:

| Campo | Qué es |
|---|---|
| `H[1..90]`, `M[1..90]` | Hombres y mujeres de cada edad (índice = edad + 1), enteros ≥ 0 |
| `RH[1..90]`, `RM[1..90]` | De esa cohorte, cuántos están en filas (`0 ≤ RH ≤ H`) |
| `resto[1..180]`, `restoH`, `restoM` | Fracciones acumuladas de muertes y nacimientos (ver 3.9) |

`c.poblacion` sigue existiendo como **total calculado** (`Σ H + Σ M`), para el
granero, la comida, la placa y el pendón, que ya lo leen.

«En filas» es todo soldado de la ciudad en cualquier estado del inventario de
la economía: en instrucción, en la guarnición, en un grupo, en una base o un
campamento que la ciudad abastece, herido en un grupo o en el taller.
**Invariante:** `Σ RH + Σ RM = inventarioCiudad(c).soldados`, todos los días.

### 3.2 El año

1. Un año de juego dura `anio` = 10 días (F1).
2. El día en que `dia % anio == 0`, antes de los nacimientos, todas las
   cohortes (`H`, `M`, `RH`, `RM`) avanzan una edad. Los de 89 que cumplen 90
   mueren (vejez).
3. Ese mismo día se retiran los soldados que cumplen `retiro` (3.6).

### 3.3 Nacimientos

Cada día, en cada ciudad, después de comer (el hambre del día ya está
decidida):

1. **Parejas** = el menor entre mujeres de 15 a 49 años y hombres de 15 a 64
   años de la ciudad, civiles y soldados por igual, estén en casa o fuera con
   el ejército (F2; **DECIDIDO**, §11.5).
2. **Nacimientos** del día = parejas × `natalidad` × `politica` / `anio` ×
   comida × vivienda × asedio (F3). El 51,2 % son niños. Entran en la edad 0.
3. `politica` es `n.natalidad` de la nación, 1 hoy. **Fase posterior:** el
   sistema de política que anunció el dueño fijará cuántos hijos puede tener
   cada pareja y lo escribirá aquí (por ejemplo 0,5 con un límite estricto, 1
   sin reglas, más de 1 si la política los premia).

### 3.4 Mortalidad natural y hambre

Cada día, en cada cohorte, mueren civiles según la tasa anual de su edad
dividida entre `anio` (F4). Con hambre (`c.hambre`, como hoy) muere además
`hambre` = 0,3 % de los civiles al día, igual que hoy (F5), y no nace nadie.
Los soldados no mueren de causas naturales mientras están en filas: con la
tasa de su edad (0,4 – 1 % al año) serían de 1,6 a 4 al día en un ejército de
4 000, tantos como los muertos en combate, y serían soldados que desaparecen
sin combatir. Mueren en combate o, ya retirados, como civiles.

### 3.5 Reclutamiento

1. **Aptos:** hombres y mujeres (**DECIDIDO**, §11.1) de 18 a 49 años,
   estén en filas o no.
2. **Tope por población** (sustituye a F1b de economia.md): la ciudad puede
   tener en filas como mucho `parte` = la mitad de sus aptos (F6). El tope por
   nivel (F3 de economia.md) sigue igual; manda el más bajo.
3. Al **encargar** soldados (`producir`), salen de los civiles aptos de sus
   cohortes, en proporción a los civiles aptos de cada cohorte (reparto por
   restos mayores, 3.9). Desde ese momento están en filas (en instrucción).
4. **Cancelar** una orden: los que aún no salieron vuelven a ser civiles,
   quitándolos de filas en proporción a los que están en filas en cada cohorte.
5. **Licencia** por impago o hambre (F8 de economia.md): igual que cancelar,
   vuelven a casa.

### 3.6 Retiro

El día del año nuevo, los soldados en filas con `retiro` = 60 años o más
vuelven a ser civiles si hay tantos en la guarnición de la ciudad
(`c.soldados`): salen de la guarnición y de filas. Los que están fuera (en un
grupo, una base o el taller) se retiran el año siguiente, si ya volvieron. Se
anota `retirados` por nación, que entra en el invariante de conservación de
la economía (§6).

### 3.7 Muertos y heridos en combate

1. Cada soldado que muere (en la batalla simulada, en la escena 3D, en la
   caída de un grupo, en una instalación perdida) sale de filas **y** de la
   población, de la cohorte de la ciudad a la que pertenece (la del
   inventario: `ciudadDeGrupo(g)` o `ciudadDeSitio(nid, s)`), en proporción a
   los que están en filas en cada edad y sexo.
2. Los **heridos** no cambian nada: siguen vivos y en filas; al curarse
   vuelven a la guarnición como hoy.

### 3.8 Trabajo

Trabajan las personas de 15 a 64 años que no están en filas (F8). Los niños,
los mayores de 64 y los soldados no trabajan. El dinero del trabajo (F2b de
economia.md) se calcula con ellos y con una base más alta, para que una ciudad
normal gane lo mismo que hoy.

### 3.9 Enteros y reparto

- Muertes y nacimientos del día son fracciones: se suma la fracción al
  `resto` de su cohorte y sale el entero (como `q.resto` en batallas.lua). Así
  el resultado es entero, exacto y determinista, sin azar.
- Todo reparto de una cantidad entre cohortes (reclutar, morir en combate,
  licenciar, retirar) es **proporcional con restos mayores**: cada cohorte
  recibe la parte entera de su proporción y lo que sobra va, de uno en uno, a
  las de mayor fracción; a igual fracción, a la de menor edad y antes los
  hombres. Nunca se pasa del tope de una cohorte.

### 3.10 Ciudad cedida

Hoy (`cederCiudad`) la guarnición, el taller y la fábrica de una ciudad
cedida vuelven a la capital del que cede y la ciudad pasa vacía. Con la
demografía:

- Los **civiles** se quedan: la ciudad pasa con su gente al nuevo dueño.
- Los **en filas** (todas sus cohortes `RH`, `RM`, con sus personas en `H`,
  `M`) se mudan a la capital del que cede, con su edad y su sexo.

### 3.11 Migración

**DECIDIDO: sin migración por ahora** (§11.7). Hoy cada nación tiene una
sola ciudad. Queda como idea para cuando haya varias: el día del año nuevo, si
una ciudad pasa del 95 % de ocupación y otra de la misma nación está por
debajo del 70 %, el 2 % de los civiles de 15 a 39 años de la llena se muda a
la vacía. Sin medir.

## 4. Fórmulas

### F1. Año

`anio = 10` días (**DECIDIDO**). Edad de una cohorte = su índice − 1. Un
solo calendario para todo el juego (**DECIDIDO**): año del juego = `1 +
floor((dia − 1) / anio)`, también en `diseno-de-armamento.md` §3.7.

Ejemplo: el día 500 es el año 50; quien nace el día 1 tiene 18 años el día
180 y ya se puede reclutar.

Razón: con 10 días por año, la tasa de hoy de +0,2 % al día es un +2 % al año
(un pueblo que crece de forma razonable) y en 500 días hay 50 años de
historia: los nacidos en la partida llegan a alistarse (día 180) y a
retirarse. Con 30 días, los nacidos el día 1 se alistan el día 540; con 365,
nunca (medido en §9).

### F2. Parejas

`parejas = min( Σ_{15..49} M, Σ_{15..64} H )`, contando a los que están en
filas (en casa o fuera: **DECIDIDO**).

Ejemplo: 10 000 habitantes, 2 400 mujeres de 15 a 49 (500 en filas) y 3 100
hombres de 15 a 64 (520 en filas): parejas 2 400. Los soldados muertos sí
bajan las parejas: si mueren 200 de esas mujeres soldado, 2 200.

Antes de la decisión se midió la otra regla (los soldados fuera de casa no
forman pareja): nacían un 6 – 8 % menos.

### F3. Nacimientos

`nacen = parejas × natalidad × politica / anio × fComida × fVivienda × fAsedio`

| Factor | Fórmula | Rango |
|---|---|---|
| `natalidad` | 0,22 hijos por pareja y año | 0,18 – 0,26 |
| `politica` | `n.natalidad` de la nación: 1 hoy; lo fijará el sistema de política (fase posterior) | 0 – 1,5 |
| `fComida` | 0 con hambre; si no, `min(1, 0,5 + 0,5 × (comida / granero) / 0,25)` | 0 – 1 |
| `fVivienda` | `clamp((1 − ocupacion) / (1 − 0,8), 0, 1)`, `ocupacion = poblacion / (radio × viviendas[nivel])` | 0 – 1 |
| `viviendas[nivel]` | 20 / 26 / 34 / 42 / 50 habitantes por px de radio | — |
| `fAsedio` | 0,5 si la ciudad está sitiada (`sitiada(c)`), 1 si no | 0,5 – 1 |

Ejemplo: las 2 400 parejas de F2, `politica` 1, granero al 40 %, ocupación
0,9, sin asedio: `2 400 × 0,22 × 1 / 10 × 1 × 0,5 × 1 = 26,4` al día: 13,52
niños y 12,88 niñas (los enteros salen de los restos, 3.9). Con una política
de `politica` 0,5, 13,2.

Razón de `viviendas`: hoy la población por px de radio empieza en 11 – 20 y
llega a unos 37 el día 500 (semilla 1: población mediana 18 510 entre radio
mediano 498); con 50 en el nivel 5 caben unas 25 000
personas en la ciudad mediana (radio 498), lo que basta para el tope de 6 000
soldados con aptos de sobra, y frena el crecimiento sin techo de hoy.

Razón de `natalidad`: con 0,22 y esta mortalidad, la población crece de
media un 2,0 – 2,1 % cada 10 días en 500 días (medido), como hoy (2,04 –
2,07 %).

### F4. Mortalidad natural

Tasa anual por edad; al día, `civiles × tasa / anio`:

| Edad | 0 | 1 – 4 | 5 – 14 | 15 – 49 | 50 – 59 | 60 – 69 | 70 – 79 | 80 – 89 | 90 |
|---|---|---|---|---|---|---|---|---|---|
| Tasa anual | 4 % | 1 % | 0,3 % | 0,4 % | 1 % | 2,5 % | 6 % | 15 % | mueren todos |

Esperanza de vida al nacer: 62,2 años (calculado de la tabla); llegan a 15
años el 89,5 %, a 65 el 62,0 % y a 90 el 5,8 %.

Ejemplo: 1 000 civiles de 72 años: `1 000 × 0,06 / 10 = 6` mueren al día.

### F5. Hambre

Con `c.hambre`: `fComida = 0` y mueren además `civiles × 0,003` al día en cada
cohorte (el 0,3 % de hoy). Ejemplo: 15 000 civiles, un día de hambre: 45
muertos más y ningún nacimiento.

### F6. Aptos y tope por población

`aptos = Σ_{18..49} H (+ Σ_{18..49} M si reclutan ambos sexos)`

`maximoSoldados = floor(aptos × parte) − soldados de la ciudad`, con `parte =
0,5`.

Rango medido el día 500: aptos 7 368 – 9 373 por nación (mediana); soldados
21 – 22 % de la población. Ejemplo: 18 000 habitantes con 8 100 aptos y 3 900
soldados: `4 050 − 3 900 = 150` más.

### F7. Retiro

El día del año nuevo: `salen = min(Σ_{edad ≥ retiro} (RH + RM), c.soldados)`,
`retiro = 60`. Ejemplo: 520 soldados cumplen 60, 300 en la guarnición: se
retiran 300 y 220 esperan al año siguiente.

### F8. Trabajo

`trabajadores = Σ_{15..64} (H + M) − soldados de la ciudad`

`gana = trabajadores × 0,022 × (1 + 0,15 × tecnología) × hambre × f(vida) ×
0,6 × 0,65` (F2b de economia.md con la base 0,022 en lugar de 0,01).

Razón: hoy trabaja `poblacion − soldados` (unos 10 300 por nación de media en
500 días); con edades, trabajan unos 4 200 – 5 400 (medido). Con 0,022 el
dinero del trabajo queda en 69,5 – 88,0 por nación y día frente a 63,5 – 83,3
de hoy (+4 a +10 %).

Ejemplo: 18 000 habitantes, 11 700 de 15 a 64 y 3 900 soldados, tecnología 3,
sin hambre, vida 100: `7 800 × 0,022 × 1,45 × 0,39 = 97,0` al día.

### F9. Muertos en combate

`de cada cohorte = reparto proporcional (3.9) de los muertos entre RH y RM`;
sale de `R` y de `H` o `M`. Ejemplo: mueren 30 soldados de una ciudad con 400
en filas de 20 a 29 años y 200 de 30 a 39: salen 20 y 10.

### F10. Mínimo de población

Si una ciudad baja de `minimo` = 200 habitantes, llegan colonos de 21 a 30
años, mitad hombres y mitad mujeres, hasta 200. Medido: no ocurrió nunca (0
colonos en todas las pruebas, también con hambre fuerte).

### F11. Pirámide inicial

La de una población estable que crece un 2 % al año con la mortalidad de F4:
`n(edad) ∝ supervivientes(edad) × e^(−0,02 × edad)`, 51,2 % hombres,
repartida con restos mayores sobre la población inicial de hoy. Los soldados
iniciales salen de los aptos (3.5).

## 5. Casos límite

- **Una ciudad sin mujeres de 15 a 49 o sin hombres de 15 a 64** (por
  ejemplo, tras perder muchos soldados de un sexo): no nace nadie; la
  población baja solo por mortalidad. Si baja de 200, llegan colonos (F10).
- **Todo el ejército fuera:** no cambia los nacimientos (decisión 5).
- **Política con `politica` = 0:** no nace nadie en esa nación; la población
  envejece y baja. Si una ciudad baja de 200, llegan colonos (F10). El
  sistema de política decidirá si eso se permite.
- **Se encarga más de lo que hay aptos civiles:** no puede pasar: F6 lo
  rechaza con el motivo `poblacion` (el mismo de hoy).
- **Muertos de una ciudad sin nadie en filas** (no debería pasar; sería un
  error de atribución): se quitan de la capital; si tampoco, se anotan como
  error para Elena. Medido: 0 en todas las pruebas.
- **Hambre larga:** con 3 veces el consumo de comida (prueba de estrés),
  hambre en el 4,6 – 7,7 % de los días-nación y 1,10 – 2,18 muertos por hambre
  al día por nación; ninguna nación se extingue y la población crece ×2,46 –
  ×2,78 en 500 días.
- **Ciudad llena:** con la ocupación en 1, `fVivienda = 0` y no nace nadie;
  la mortalidad la baja y vuelve a nacer gente. A los 1 000 días, las ciudades
  pasan el 61,5 – 68,3 % de los días con la vivienda frenando los nacimientos
  y la pirámide envejece (65 años o más: 17,1 – 18,2 %).
- **Soldados que cumplen 60 fuera de casa:** siguen en filas hasta que vuelvan
  a la guarnición y llegue otro año nuevo.
- **Ciudad sitiada:** no recluta (como hoy) y la natalidad es la mitad.
- **Ciudad cedida:** 3.10. Además los grupos que salieron de ella deben pasar
  a pertenecer a la capital (hoy su `g.origen` sigue siendo la ciudad cedida y
  el inventario los atribuye a la ciudad propia más cercana): ver §10.
- **Guarnición que llega a 0 por licencias:** los soldados fuera no se
  licencian (como hoy); en filas se quedan.
- **Partida de la versión 22:** al cargar, cada ciudad recibe la pirámide
  inicial (F11) sobre su `c.poblacion` y sus soldados salen de los aptos. Si
  no alcanzan (una ciudad con más soldados que la mitad de sus aptos), se toman de 15 a 17 y de 50 a 59 años; los
  que aún falten se quedan en filas y la ciudad no puede encargar más hasta
  bajar del tope (como con el tope por nivel).
- **Nación que desaparece:** su gente desaparece con ella (único borrado).
- **Año nuevo y nacimiento el mismo día:** primero se envejece, después nacen
  (los recién nacidos tienen edad 0 un año entero).

## 6. Dependencias

**Este documento depende de:**

- `economia.md`: inventario de soldados por ciudad (§3.5), producir y cancelar
  (§3.4), licencia F8, F1b (que sustituye), F2b (que cambia), tope F3,
  invariante de conservación (§3.5, al que añade `retirados`).
- `territorio-y-capitales.md`: nivel de la ciudad (vivienda), granero y
  hambre, `sitiada`.
- `recoleccion-y-batallas.md` y `retirada-y-recuperacion.md`: dónde mueren y
  se curan los soldados (F11b de economia.md).
- `diplomacia.md` y `cederCiudad`: ciudades cedidas (3.10).
- `diseno-de-armamento.md`: su «año» pasa a ser el de 10 días (un solo
  calendario, decisión 3); ese documento ya lo dice.
- `instalaciones-y-economia.md`: la regla de crecimiento de hoy (×1,002 al
  día, sin techo) que este documento sustituye.

**Dependen de este documento:**

- `economia.md` (F1b y F2b; invariante con `retirados`).
- `interfaz-militar.md`: pestaña de población y fila de reclutables (§10).
- `modo-base.md`: si las viviendas pasan a ser piezas de la base, sustituyen a
  la tabla `viviendas` por nivel.
- El futuro **sistema de política**: fija `n.natalidad` (hijos por pareja).
  Cuando tenga documento, debe nombrar este.
- `README.md` del diseño: índice.

## 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `anio` | 10 días | 8 – 15 | Más: todo más lento (medido con 30: población ×1,49 – ×1,59 en 500 días y ejércitos de 1 489 – 2 210) |
| `natalidad` | 0,22 | 0,18 – 0,26 | Más: crece más rápido y llena antes la vivienda (semilla 1, con la regla anterior de parejas y retiro a los 50: 0,20 → ×2,36; 0,22 → ×2,54) |
| `n.natalidad` (política) | 1 | 0 – 1,5 | Lo fijará el sistema de política de cada nación (fase posterior) |
| `viviendas` | 20 / 26 / 34 / 42 / 50 por px de radio | ×0,8 – ×1,3 | Más: techo más alto; menos: pirámide más vieja antes |
| `viviendaLlena` | 0,8 | 0,7 – 0,9 | Ocupación desde la que bajan los nacimientos |
| `edadMin`, `edadMax` | 18, 49 | 16 – 20, 45 – 55 | Aptos: más años, más ejército posible |
| `parte` | 0,5 | 0,3 – 0,6 (ambos sexos); 0,6 – 0,8 (solo hombres) | Ejército máximo por población |
| `retiro` | 60 | 50 – 65 | Con 60: se retiran 3,76 – 4,84 al día por nación; con 50 (regla anterior de parejas): 6,51 – 8,22 |
| `trabajo` (base) | 0,022 | 0,018 – 0,026 | Dinero del trabajo: con 0,022, +9 a +16 % sobre hoy; 0,016 (con natalidad 0,16) dio 52,5 al día en la semilla 1 (hoy 74,9) |
| Edades de trabajar | 15 – 64 | — | Más estrecho: menos dinero |
| `hambre` | 0,003 al día | 0,001 – 0,005 | Muertes por hambre (la de hoy) |
| `asedio` | 0,5 | 0,3 – 1 | Natalidad de una ciudad sitiada |
| Tasas de F4 | tabla | ×0,5 – ×1,5 | Esperanza de vida y peso de los viejos |
| `minimo` | 200 | 50 – 500 | Suelo de población (colonos) |

## 8. Criterios de aceptación

Comprobables con `tools/medir_poblacion_nationsrts.lua` hasta que esté
programado, y después con la misma herramienta adaptada al código real (o la
auditoría de Andrés). Los rangos salen de §9 (reglas decididas).

1. **Nadie se extingue:** en 500 y 1 000 días y 4 semillas, todas las naciones
   vivas y ninguna ciudad por debajo de 200 (medido: 0 colonos).
2. **No explota:** población total el día 500 entre ×2,2 y ×3,0 la del día 0
   (medido: ×2,68 – ×2,87) y el día 1 000 menos de ×3,5 (medido: ×2,76 –
   ×2,96; hoy ×6,94 – ×7,53).
3. **Pirámide razonable el día 500:** 0 – 14 años entre el 25 y el 35 %
   (medido: 27,7 – 29,7 %), 65 o más entre el 4 y el 10 % (5,9 – 6,3 %),
   hombres entre mujeres de 15 a 49 entre 1,0 y 1,1 (1,05).
4. **Hay soldados:** mediana de soldados por nación el día 500 entre 3 000 y
   5 500 (medido: 3 910 – 5 064; hoy 3 260 – 4 317) y entre el 18 y el 25 % de
   la población (22 – 23 %).
5. **La economía no cambia de forma:** dinero del trabajo por nación y día
   como mucho un 20 % por encima del de hoy (medido: +9 a +16 %; **DECIDIDO**,
   §11.8); tesoro mediano el día
   500 entre 300 y 12 000 (medido: 508 – 895; es el criterio 8.3 de
   economia.md, que hoy falla en la semilla 1234 con 67).
6. **Muertos que restan:** cada muerto en combate sale de una cohorte (medido:
   0 muertos sin cohorte).
7. **Conservación:** cada día, `Σ en filas = inventarioCiudad(c).soldados`
   por ciudad, ninguna cohorte negativa ni con más en filas que personas, y
   el invariante de economia.md §3.5 con `retirados` (medido: se cumplen todos
   los días en todas las pruebas).
8. **Hambre fuerte sin colapso:** con 3 veces el consumo de comida, todas las
   naciones vivas y menos de 3 muertos por hambre al día por nación (medido:
   1,10 – 2,18).
9. **Determinismo:** dos corridas con la misma semilla dan las mismas
   cohortes; guardar el día 250, cargar y seguir da la misma población el día
   500. **Sin medir** (lo comprueba Elena con el código real).
10. **Costo:** la demografía de todas las ciudades cuesta menos de 2 ms por
    día con 22 ciudades (medido en el prototipo: 0,62 – 1,66 ms con 5
    corridas a la vez en la máquina).
11. **Política preparada:** con `n.natalidad` = 0,5 en una nación, sus
    nacimientos son la mitad que con 1 en las mismas condiciones. **Sin
    medir** (el factor está en el prototipo, a 1).

## 9. Cifras medidas

Prototipo encima de la simulación real, sin tocar el juego (ver «Cómo se
midió»), con **lo decidido**: ambos sexos, `parte` 0,5, retiro a los 60, año
de 10 días, soldados que forman pareja estén donde estén, techo de vivienda,
sin migración, `n.natalidad` = 1. 500 días, 4 semillas; por nación, mediana
del día 500 (rango entre semillas):

| Qué | Hoy | Decidido |
|---|---|---|
| Población | 16 438 – 22 197 | 15 829 – 22 333 |
| Crecimiento total en 500 días | ×2,75 – ×2,78 | ×2,68 – ×2,87 |
| Soldados | 3 260 – 4 317 | 3 910 – 5 064 |
| Soldados / población | 19 – 20 % | 22 – 23 % |
| Aptos (18 a 49, ambos sexos) | — | 8 091 – 10 497 |
| Tesoro | 67 – 582 | 508 – 895 |
| Días-nación con hambre | 0,0 – 0,3 % | 0,0 – 0,8 % |
| Naciones vivas | todas | todas |

La semilla 1 tiene hambre el 0,8 % de los días-nación (hoy 0,1 %): hay más
gente que comer. Está por debajo del 1 % del criterio 4 de economia.md.

**Por nación y día (media de 500 días), decidido:**

| Flujo | Valor |
|---|---|
| Nacimientos | 32,97 – 39,88 |
| Muertes naturales | 8,99 – 11,49 |
| Muertes por hambre | 0,00 – 0,19 |
| Muertes de vejez (a los 90) | 0,36 – 0,47 |
| **Muertos en combate** | **0,91 – 1,76** (hoy 1,03 – 1,44) |
| Retirados | 3,76 – 4,84 |
| Soldados producidos | 11,56 – 14,31 (hoy 6,17 – 8,81) |
| Trabajadores | 4 394 – 5 648 (hoy 8 667 – 11 207) |
| Dinero del trabajo | 73,6 – 94,0 (hoy 63,5 – 83,3) |
| Ocupación media de la vivienda | 0,73 – 0,76 |
| Días-ciudad con la vivienda frenando | 27,8 – 37,9 % |

**Pirámide el día 500** (% de toda la población, las 4 semillas): 0 – 14 años
27,7 – 29,7 %; 15 – 49, 53,4 – 54,4 %; 50 – 64, 10,8 – 11,6 %; 65 o más, 5,9 –
6,3 %. Hombres / mujeres de 15 a 49: 1,05.

Ciudad mediana de la semilla 1 el día 500 (Duna, 20 341 habitantes), por
decenios; entre paréntesis, en filas:

| Edad | Hombres | Mujeres |
|---|---|---|
| 80 – 89 | 103 | 99 |
| 70 – 79 | 226 | 230 |
| 60 – 69 | 462 | 453 |
| 50 – 59 | 900 (564) | 864 (536) |
| 40 – 49 | 1 162 (650) | 1 107 (606) |
| 30 – 39 | 1 431 (667) | 1 369 (630) |
| 20 – 29 | 1 513 (145) | 1 440 (138) |
| 10 – 19 | 2 149 (6) | 2 049 (6) |
| 0 – 9 | 2 450 | 2 334 |

Lectura: el ejército es sobre todo de 30 a 59 años porque la NPC lo llenó en
los primeros 100 días (los que tenían 18 – 49 entonces) y ahora solo repone.

**Lo que pesan los muertos en combate.** Restan de la población y de las
parejas, pero hoy son el 3 – 5 % de los nacimientos. Con el doble de muertos
(`muertos` 0,8 en lugar de 0,4): 1,92 – 3,52 muertos al día por nación y
crecimiento ×2,60 – ×2,81 (frente a ×2,68 – ×2,87).

**A los 1 000 días:** población 16 319 – 22 883 (×2,76 – ×2,96; hoy 45 070 –
60 708, ×6,94 – ×7,53); soldados 2 991 – 4 322 (18 – 19 %; hoy 6 000, el
tope); tesoro 884 – 9 961 (hoy 11 699 – 16 868); vivienda frenando el 61,5 –
68,3 % de los días; hambre 0,0 – 0,5 % de los días-nación; pirámide más vieja:
0 – 14 años 17,4 – 18,7 %, 65 o más 17,1 – 18,2 %. En la ciudad mediana
(semilla 1, Duna, 22 487 habitantes) la cohorte de 50 a 59 es la mayor (los
nacidos en los primeros años) y el ejército envejece: 2 224 de sus 4 042
soldados tienen 50 a 59. Todas las naciones vivas; 0 colonos.

**Variantes medidas antes de las decisiones** (500 días, 4 semillas, mediana
por nación el día 500; todas con la regla anterior de parejas, en la que los
soldados fuera de casa no las forman). Quedan como referencia de lo que se
descartó:

| Variante | Soldados | % población | Tesoro | Dinero del trabajo / día | Nacimientos / día | Crecimiento |
|---|---|---|---|---|---|---|
| Ambos, `parte` 0,5, retiro 60 | 3 685 – 4 583 | 21 – 22 % | 350 – 525 | 69,5 – 88,0 | 30,4 – 37,6 | ×2,54 – ×2,70 |
| Solo hombres, `parte` 0,8 | 3 117 – 3 928 | 18 % | 615 – 2 810 | 77,1 – 95,9 | 31,0 – 37,8 | ×2,55 – ×2,73 |
| Solo hombres, `parte` 0,5 | 1 976 – 2 519 | 12 % | 6 905 – 9 545 | 91,1 – 111,6 | 30,9 – 36,7 | ×2,46 – ×2,70 |
| Retiro a los 50 | 3 369 – 4 197 | 21 – 22 % | 61 – 371 | 68,4 – 85,5 | 29,5 – 36,0 | ×2,42 – ×2,59 |
| Año de 30 días | 1 489 – 2 210 | 17 – 18 % | 47 – 450 | 44,7 – 57,2 | 9,8 – 11,5 | ×1,49 – ×1,59 |
| Año de 365 días | 1 107 – 1 567 | 18 – 19 % | 30 – 222 | 37,0 – 47,7 | 0,64 – 0,80 | ×0,99 – ×1,02 |

## 10. Cambios necesarios en el código

Para Andrés (simulación):

- **`mundo/simulacion/poblacion.lua` (nuevo):** `Simulacion.poblacion` con
  las reglas (F1 a F11 y §7) y las funciones: `crearDemografia(c, soldados)`
  (F11), `diaDemografico(c, n, inv)` (3.2 a 3.4, F2 a F5, F10; las parejas
  cuentan a todos los soldados, sin calcular quién está fuera), `aptos(c)`,
  `trabajadores(c, soldados)`, `reclutar(c, cantidad)`, `quitarDeFilas(c,
  cantidad, mueren)`, `retirar(c)` (F7) y `resumenDemografia(c)` para la vista
  (por decenios y sexo, en filas, aptos, nacidos y muertos del último año).
  Los recuentos del último año (`nacidos`, `muertos` por causa, `retirados`)
  se guardan en `c.demografia.anio` y se vacían cada año nuevo.
- **Natalidad por nación (preparada para la política):** `n.natalidad`
  (número, 1 si falta) entra en F3. Hoy nadie la cambia; no hace falta
  guardarla hasta que el sistema de política la fije (si falta, vale 1). No
  subir la versión del guardado solo por esto.
- **`mundo/simulacion/ayudas.lua`:** un `repartirRestos(pesos, total, topes)`
  (restos mayores, 3.9). El `repartir` de batallas.lua (l.715) da el sobrante
  al primero con sitio: para cohortes cargaría siempre a los más jóvenes.
- **`mundo/simulacion.lua`**
  1. `registrarZona` (l.996 – 1027): tras crear la ciudad, `c.demografia =
     crearDemografia(c, c.soldados)`.
  2. `economia` (l.2305 – 2314): quitar el crecimiento (l.2313) y la bajada
     por hambre (l.2310) de `c.poblacion`; después de decidir `c.hambre`,
     llamar a `diaDemografico` con el inventario que ya calcula (l.2297) y
     dejar `c.poblacion` como total.
  3. `destruirInstalacion` (l.1868): los muertos salen de la población (ver
     batallas).
- **`mundo/simulacion/batallas.lua`:** donde hoy se anota `medir('muertos',
  …)` (l.147, l.165, l.417, l.821), llamar a una sola función
  `morirSoldados(nid, ciudad, cantidad)` que anota y quita de filas y de la
  población (F9), con `ciudad = ciudadDeGrupo(g)` o `ciudadDeSitio(nid, s)`.
- **`mundo/simulacion/produccion.lua`**
  1. `maximoSoldados` (l.345): F6.
  2. `producir` (l.448): al encargar soldados, `reclutar`.
  3. `cancelarProduccion` (l.488): los soldados que no salieron vuelven a
     casa (`quitarDeFilas` sin morir).
  4. `licenciar` (l.624): `quitarDeFilas` sin morir.
  5. `trabajoCiudad` (l.606): F8 (trabajadores de 15 a 64 y base 0,022 en
     `reglas.trabajo.base`).
  6. `cederCiudad` (l.661): 3.10 (los en filas se mudan a la capital) y
     `g.origen` de los grupos que salieron de la ciudad pasa a la capital.
  7. Retiro (F7): `medir('retirados', n, nid)`.
- **`mundo/simulacion/guardado.lua`:** versión 23; migración desde la 22
  (§5, «Partida de la versión 22»). `c.demografia` son 4 listas de 90 enteros
  y 182 fracciones por ciudad.
- **`mundo/simulacion/consultas.lua`:** `demografiaCiudad(cid)` → el
  `resumenDemografia` y `reclutables` (lo que da `maximoProducible` de
  soldados).
- **`tools/auditar_economia_nationsrts.lua`:** el invariante resta también
  `retirados`; añadir las comprobaciones del criterio 7 (en filas =
  inventario por ciudad, cohortes ≥ 0). El prototipo de este documento ya las
  hace y se pueden copiar.

Para Valeria (vista), con el estilo de `interfaz-militar.md`:

- **Radial de una ciudad propia** (`main.lua`, filas del radial, l.2423 –
  2480): dos filas nuevas, «Población» (`c.poblacion`) y «Reclutables» (lo que
  da `maximoProducible` de soldados, con «de N aptos» en gris). En una ciudad
  ajena, solo «Población» (hoy ya es pública en la placa y el pendón).
- **Pendón de ciudad propia** (`interfaz/pendon.lua`): pestaña «Población»
  con la pirámide por decenios en barras horizontales, hombres a la izquierda
  y mujeres a la derecha en gris claro, la parte en filas de cada barra en
  dorado; debajo, «Nacidos», «Muertos» (natural, hambre, combate) y
  «Retirados» del último año, la ocupación de la vivienda con su barra y lo
  que frena hoy los nacimientos («Ciudad llena», «Hambre», «Sitiada» y, cuando
  exista, la política de la nación). En ciudades ajenas, la pirámide no se ve.
- **Perfil** (`interfaz/perfil.lua`, l.291): junto a «Población total», «En
  filas» y «Caídos en combate» (total de la partida).
- **Motivo `poblacion`** (`interfaz/fabrica.lua`, l.104): el texto de hoy dice
  que «el 80 % de la ciudad tiene que trabajar»; pasaría a «No quedan aptos:
  en filas X de Y (la mitad de los de 18 a 49 años)».
- **Aviso de retiro** (privado, no en las noticias comunes): «Año 37: 120
  veteranos de Duna se retiran».

- **Año en la interfaz:** donde se muestre la fecha, «Año N» con `1 +
  floor((dia − 1) / 10)` (el mismo año que la población y el armamento).

Para Elena: criterios 7, 9 y 11 como pruebas; el costo por día con el código
real.

## 11. Decisiones del dueño (2026-09-30)

1. **DECIDIDO: se reclutan hombres y mujeres** de 18 a 49 años, hasta la
   mitad de los aptos.
2. **DECIDIDO: un año dura 10 días.**
3. **DECIDIDO: un solo calendario para todo el juego:** año = `1 + floor((dia
   − 1) / 10)`, también en `diseno-de-armamento.md` (antes, años de 365
   días). La fortificación sigue tardando 365 días; solo cambia cómo se
   nombra el tiempo.
4. **DECIDIDO: retiro a los 60.**
5. **DECIDIDO: los soldados fuera de casa sí cuentan como parejas** y tienen
   hijos. El dueño anuncia un futuro **sistema de política** con reglas de
   cuántos hijos puede tener cada pareja: la natalidad queda preparada con
   `n.natalidad` por nación (F3), a 1 hasta entonces. **Fase posterior.**
6. **DECIDIDO: techo de vivienda por nivel de ciudad** (tabla de F3).
7. **DECIDIDO: sin migración por ahora** (3.11).

8. **DECIDIDO: la base del dinero del trabajo (F8) se queda en 0,022**, con el
   criterio 5 en «como mucho un 20 % por encima de hoy» (medido: +9 a +16 %;
   tesoro 508 – 895). Lo eligió el jefe de estudio con la recomendación de
   Lucía; el dueño puede cambiarlo.

---

## Cómo se midió

- Script: `tools/medir_poblacion_nationsrts.lua` (LuaJIT, sin LÖVE), en HEAD
  17600fc. Crea el mundo con `depurar/mundo_prueba.lua` (5 × 5 zonas) y corre
  `avanzarDia` de la simulación real. En modo `hoy` solo mide; en `ambos` y
  `hombres` monta la demografía de este documento sustituyendo, solo dentro del
  proceso, `economia` (añade el día demográfico después), `trabajoCiudad`,
  `producir`, `licenciar`, `medir` (para quitar a los muertos de su cohorte) y
  `Produccion.maximoSoldados`. La demografía se guarda fuera del estado.
- Órdenes (los valores de A son los de por defecto):
  - `luajit tools/medir_poblacion_nationsrts.lua hoy 500 1 7 42 1234`
  - `luajit tools/medir_poblacion_nationsrts.lua ambos 500 1 7 42 1234`
    (lo decidido es el valor por defecto)
  - `luajit tools/medir_poblacion_nationsrts.lua ambos 1000 1 7 42 1234`
  - Las variantes de antes de las decisiones se midieron con `ausencia=1`
    (hoy el valor por defecto es 0, decidido): `hombres … parte=0.8`,
    `hombres …`, `ambos … retiro=50`, `ambos … anio=30`, `ambos … anio=365`.
  - Estrés: `ambos … come=3` y `hoy … come=3` (3 veces el consumo de comida),
    `ambos … muertos=0.8` (el doble de muertos entre los caídos).
- «Por nación y día» divide entre el número de naciones del día 0 y los días.
  Las medianas son por nación el último día.
- El costo de la demografía se midió con `os.clock` alrededor del día
  demográfico; incluye un recuento del inventario por ciudad que en el código
  real sobra (la economía ya lo tiene).
- La misma herramienta, en modo `hoy`, da el mismo tesoro por semilla que la
  auditoría de Andrés (`tools/auditar_economia_nationsrts.lua`: 362, 424, 582
  y 67).
- Falta medir: el determinismo con guardar y cargar, la migración (3.11),
  ciudades cedidas con demografía (no se comprobó si hubo cesiones en estas
  semillas) y el efecto en el jugador (el arnés no lo tiene).

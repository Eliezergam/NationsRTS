# Naciones y política

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Fuentes: `mundo/simulacion.lua` (`registrarZona` :341, `diplomacia` :1350,
`fuerza` :276, `guerra` :1601), `mundo/mundo.lua` (`datosZona` :98,
`registrarNacionDe` :129).

## 1. Resumen

Cada zona de 3×3 regiones con al menos una ciudad es una nación NPC. Su ciudad
de mayor radio es la capital. Al nacer recibe al azar (de la semilla y la
posición de la capital) un orden político, un nombre, un color y un presidente
con dos rasgos: agresividad y prudencia. Cada día, cada par de naciones mueve
su relación según el orden, la cercanía y los recursos en disputa; cuando la
relación es muy mala y el presidente se ve más fuerte, declara la guerra. Una
guerra alterna días de **tensión** (hay ataques) y periodos de **calma** (alto
el fuego).

## 2. Fantasía del jugador

Un mapa político vivo: bloques ideológicos que se odian, vecinos que se miran
con codicia por una mina en la frontera, presidentes con carácter (el halcón
que abre dos frentes, el prudente que negocia pronto). Leer el diario y
entender por qué estalló cada guerra.

## 3. Reglas

### Nacimiento (`Simulacion:registrarZona`)

1. `Mundo:datosZona(zx, zy)` junta las ciudades de las 9 regiones (ordenadas por
   radio descendente, desempate por id) y todos los depósitos que caen dentro.
2. Los depósitos se registran siempre. Si la zona no tiene ciudades, o la nación
   ya existe (partida cargada), no se hace nada más.
3. Azar: `Ruido.hash(semilla, floor(capital.x), floor(capital.y), 57)`.
   - Orden: uniforme entre `alba`, `estandarte`, `concordia`.
   - Nombre: título del orden + nombre de la capital (p. ej. "Comuna de Valo",
     "Liga Soberana de Nualtor", "Federación de Cana").
   - Presidente: nombre + apellido de listas ficticias; `agresividad` y
     `prudencia` uniformes en 0,1–1.
   - Id de la nación: `'z:zx,zy'`.
4. Estado inicial: tecnología 0, recursos metal 12, petróleo 6, comida 12,
   tesoro 0, cansancio 0, bases 0.
5. Cada ciudad: población `radio × (8..14)` (×1,4 la capital), soldados 5–9 %
   de la población, 1–4 tanques, sin misiles, interceptores ni aviones.
6. Relación inicial con cada nación ya registrada: `azar(−30, 30)`, +30 si
   comparten orden, −25 si son órdenes opuestos. Es simétrica.
7. El mundo registra la zona de cada ciudad vista y sus 8 vecinas
   (`registrarNacionDe`), así que aparecen naciones que aún no se ven.

### Órdenes políticos (`Simulacion.ordenes`)

| Id | Nombre | Opuesto | Títulos |
|---|---|---|---|
| `alba` | Orden del Alba | `estandarte` | República Popular de, Comuna de, Unión del Alba de |
| `estandarte` | Liga del Estandarte | `alba` | Principado de, Liga Soberana de, Estado de |
| `concordia` | Concordia | — | Federación de, Mancomunidad de, Cantón de |

El orden pesa en: relación inicial, deriva diaria y reacción a crímenes de
guerra (los del mismo orden "miran para otro lado", ver [guerra.md](guerra.md)).

### Deriva diaria de relaciones (`Simulacion:diplomacia(a, b)`)

Se llama para **cada par ordenado** de naciones vivas cada día (A→B y B→A, así
que la deriva se aplica dos veces por par). En orden:

1. `cambio` = +0,5 si mismo orden; −0,4 si opuestos.
2. Si el frente (par de ciudades más cercanas, `frente`) está a menos de
   `alcanceGuerra = 110 000`: `cambio −= 0,25 × (1 − d / 110 000)`.
3. Codicia: `cambio −= 0,15 × disputa × (0,5 + agresividad_A)`, con
   `disputa = recursosEnDisputa(A, B)` = suma, sobre las extracciones de B a
   menos de `alcanceCodicia = 80 000` px de alguna **ciudad** de A (hoy, solo su
   capital) **o de algún campamento terminado** suyo, de `riqueza ×
   necesidad_A[tipo]`. Cada mina cuenta una vez. La
   necesidad sale del estado de la reserva de A (`necesidades`): holgado 0,
   justo 0,5, escasez 0,8, crisis 1; metal o petróleo por debajo del 20 % del
   almacén, al menos 0,3 ("fábrica"); petróleo, al menos 0,3 si no le da para
   mantener el siguiente campamento ("expansión", ver
   [instalaciones-y-economia.md](instalaciones-y-economia.md)). Quien va
   holgado no codicia nada.
   `codiciado` = el tipo que más pesa (en empate: petróleo, comida, metal).
4. Si ya están en guerra, `cambio = 0` (mandan los hechos).
5. Suceso: con 0,2 % "incidente fronterizo" (−15), con 0,2 % "acuerdo
   comercial" (+15). Se aplican también en guerra.
6. La relación se limita a −100..100.

### Declarar la guerra

A declara a B si **todo** se cumple:

- A tiene menos guerras abiertas que sus frentes posibles (1; 2 si
  agresividad > 0,85) y B tiene menos de 2.
- No están ya en guerra, la relación es < −60, el frente está a menos de
  110 000 px y no hay tregua vigente (90 días tras una paz).
- `fuerza(A) > fuerza(B) × umbral`, con
  `umbral = 1,3 − 0,5·agresividad + 0,25·prudencia − min(0,3; 0,05·disputa)
  − 0,25·apuro`, donde `apuro` = necesidad de A del recurso `codiciado` (0 si
  no hay).
- Tirada diaria: `azar < (0,05 + 0,08·agresividad) × (1 si hay codiciado; si
  no, guerraSinMotivo = 0)`. **Sin codicia no hay guerra.**

Motivo en la noticia: "el metal / el petróleo / la comida de B" si hay
codiciado; "diferencias irreconciliables" solo si `guerraSinMotivo` > 0.

### Fuerza (`Simulacion:fuerza`)

`fuerza = 12·tecnología + Σ fuerzaDe(ciudades, instalaciones, grupos)`, con
`fuerzaDe = soldados·1 + tanques·9 + misiles·2 + interceptores·1 + aviones·15`.

### Tensión y calma

Una guerra nace en fase `tension`. Cada día de tensión se tira la intensidad
(`azar`); si es > 0,35 hay ofensiva (detalle en [guerra.md](guerra.md)). Un alto
el fuego la pasa a `calma` durante 5–29 días; al acabar, o se rompe (vuelve a
tensión) o se firma la paz (detalle en [diplomacia.md](diplomacia.md)).

### Vida y muerte de una nación

`Simulacion:vivas()` = naciones con al menos una ciudad. Como la capital nunca
se cede y las ciudades no se conquistan, **ninguna nación desaparece** hoy.

## 4. Fórmulas

**Deriva de un par vecino.** A (Alba, agresividad 0,5) y B (Estandarte), frente
a 20 000 px, disputa 4:
`−0,4 − 0,25·(1 − 0,4) − 0,15·4·1,0 = −1,15` por llamada, y hay dos llamadas
por día (A→B y B→A, con la agresividad de cada uno). De 0 a −60 en ~26 días.
Rango típico por llamada: +0,5 (aliados lejanos sin disputa) a −2 o menos.

**Umbral de guerra.** Agresividad 0,5, prudencia 0,5, disputa 4:
`1,3 − 0,25 + 0,125 − 0,2 = 0,975`: basta con ser casi igual de fuerte. Rango:
0,5 (halcón con mucha disputa) a 1,55 (paloma sin disputa). Probabilidad diaria
si se cumple: 0,058–0,13.

**Sucesos.** Esperado por 500 días = pares ordenados × 500 × 0,002. Con 15
naciones: 210 × 1 = 210 de cada. Medido: 200–255 incidentes y 212–255 acuerdos.

**Medido (500 días, 6 semillas):**

| Medida | Valor |
|---|---|
| Naciones | 13–16 (una zona sin ciudades no tiene nación) |
| Reparto de órdenes (4242) | Alba 7, Estandarte 5, Concordia 3 |
| Agresividad (4242) | 0,22–0,93, mediana 0,45 |
| Relación inicial (4242) | −55 a 59, mediana 1 |
| Pares a menos de `alcanceGuerra` | 25–50 de 78–120 (29–42 %) |
| Relación final de pares vecinos, mediana | −57 a −100 |
| Relación final de pares lejanos, mediana | −31 a +11 |
| Primera guerra | día 7–34 |
| Guerras declaradas | 33–68 (2,5–4,3 por nación) |

En las 6 semillas hay pares en +100 y en −100 al final: el orden político
empuja la relación a los extremos y ahí se queda.

## 5. Casos límite

- **Zona sin ciudades:** no hay nación; sus depósitos quedan de nadie.
- **Partida cargada y zona ya registrada:** `registrarZona` no toca la nación ni
  sus ciudades (se enlazan por id).
- **Nación registrada después:** su relación con las ya existentes se tira al
  registrarla; las anteriores no se recalculan.
- **Dos naciones del mismo orden:** +1 por día (dos llamadas) hasta +100. Solo
  un incidente (−15) o la codicia les puede llevar a la guerra; con +100 no
  llegan a −60 salvo codicia muy fuerte.
- **Halcón (agresividad > 0,85):** puede tener 2 guerras a la vez. El defensor
  no puede ser atacado si ya tiene 2.
- **Ciudades cedidas:** cambian la nación dueña; el frente, la fuerza y el
  territorio se recalculan al día siguiente.
- **Tregua:** 90 días tras firmar la paz, en los dos sentidos. Durante la tregua
  la relación puede volver a caer, pero no se declara guerra.

## 6. Dependencias

- **Depende de:** [mundo-fisico.md](mundo-fisico.md) (zonas, ciudades, radio),
  [instalaciones-y-economia.md](instalaciones-y-economia.md) (fuerza, extracciones →
  disputa, reservas → necesidad; campamentos como punto de codicia y
  necesidad de expansión por su mantenimiento), [guerra.md](guerra.md) (salvas y crímenes bajan relaciones),
  [diplomacia.md](diplomacia.md) (alto el fuego +18, paz +35, treguas).
- **Lo usan:** [guerra.md](guerra.md) (quién pelea), [diplomacia.md](diplomacia.md)
  (rasgos del presidente), [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (agresividad → presupuesto; guerra abierta → +0,6 de presupuesto).

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| Deriva mismo orden / opuestos | +0,5 / −0,4 | ±0,05–0,5 | Hoy dominan: llevan a ±100. Bajarlas da peso a cercanía y codicia. |
| Cercanía | −0,25 × (1 − d/110 000) | 0–0,5 | Hostilidad entre vecinos. |
| Codicia | −0,15 × disputa × (0,5 + agr) | 0,05–0,3 | Guerras por recursos. Con disputa ~10 es la fuerza principal. |
| `alcanceCodicia` | 80 000 (desde ciudades y campamentos terminados) | 60 000–110 000 | Qué minas rivales se codician. Es la perilla que más mueve las guerras: 60 000 → 24 guerras en 6 semillas; 80 000 → 62; 110 000 desde la capital → 102. |
| `campamento.alcanceMeta` | 60 000 | — | Hasta dónde busca el NPC depósitos sin dueño hacia los que plantar campamentos (antes era `alcanceCodicia`). |
| `necesidad.guerraSinMotivo` | 0 | 0–0,05 | Guerras sin codicia. En 0 toda guerra es por recursos. |
| Umbral relación para guerra | −60 | −40 a −80 | Más alto (−40) = más guerras. |
| `alcanceGuerra` | 110 000 | 80 000–150 000 | Quién puede chocar (hoy 29–42 % de pares). |
| Umbral de fuerza | 1,3 − 0,5·agr + 0,25·prud − ... | — | Cuánta ventaja pide el presidente. |
| Tirada de guerra | 0,05 + 0,08·agr | 0,01–0,15 | Retraso entre "ya se odian" y "declaran". |
| Frentes de un halcón | agr > 0,85 → 2 | 0,7–1 | Guerras simultáneas. |
| Sucesos | 0,2 % cada uno | 0–0,5 % | Ruido diplomático y spam de noticias (crece con n²). |
| Relación inicial | ±30, +30 / −25 | — | Arranque de bloques. |
| Tregua | 90 días | 30–365 | Pausa entre guerras del mismo par. |

## 8. Criterios de aceptación

16 zonas, 500 días:

- Todas las zonas con ciudad tienen exactamente una nación; la capital es la
  ciudad de mayor radio.
- La primera guerra llega entre el día 5 y el 40 (medido 7–34).
- Entre 2 y 5 guerras declaradas por nación (medido 2,5–4,3 en una versión
  anterior; **ya no se cumple**: con el commit eb5bd72 había 1–4 guerras en
  total en 300 días y 4–5 en 500, medido con 6 y 2 semillas; con la codicia
  desde campamentos hay 5–15 en total en 300 días y 11–28 en 500, medido con 6
  y 3 semillas: 0,7–1,8 por nación).
- Ninguna guerra entre naciones con el frente a más de 110 000 px.
- Codicia: solo cuentan las minas del rival a menos de `alcanceCodicia = 80 000`
  (8 km) de una ciudad propia o un campamento propio terminado, pesadas por la
  necesidad. Sin codicia no hay
  guerra.
- Ninguna guerra declarada durante una tregua.
- Ninguna nación con más de 2 guerras abiertas (no medido explícitamente; se
  deduce del código).

## Propuestas (no implementadas)

- **P1. Relaciones menos binarias.** Hoy el orden decide casi todo (±100). Opción
  A: deriva por orden solo hasta ±50. Opción B: la deriva tiende a un valor
  objetivo (p. ej. +40 mismo orden, −40 opuestos) en vez de sumar sin fin. Efecto:
  cercanía, codicia y hechos pesarían más; habría alianzas que se rompen.
- **P2. Sucesos por par, no por par ordenado, y proporcionales a la cercanía.**
  Hoy un incidente entre naciones a 150 000 px es igual de probable que entre
  vecinas, y salen ~200 por cada 500 días.
- **P3. Alianzas.** Nada obliga hoy a un aliado a entrar en una guerra. Si se
  quiere, hace falta un sistema nuevo.
- **P4. Naciones que mueren o se reparten.** Hoy es imposible; si se quiere, la
  capital debería poder cederse o caer.
- **P5. Codicia desde todo el territorio y con escasez.** Ya implementada
  (opción B); ver el apartado siguiente.

## Codicia: por qué había tan pocas guerras y qué se hizo

### Diagnóstico (medido con el commit eb5bd72)

Arnés sin ventana, 16 zonas, 300 días, semillas 4242, 1, 7, 99, 12345 y 2026:
**1–4 guerras declaradas por semilla**, la primera entre el día 61 y el 232.

Cada día y par ordenado de vecinos (frente a menos de 110 000) sin guerra, la
primera condición que falla (4242, 300 días, 8 125 pares-día):

| Condición que falla | Pares-día |
|---|---|
| Relación ≥ −60 | 6 001 |
| **Se odian (< −60) pero no codician nada** | **1 586** |
| A es más débil que lo que pide su umbral | 200 |
| Tregua | 186 |
| A (o B) ya tiene sus guerras | 105 |
| Llegan a la tirada | 47 |

Los pares-día que se odian y no codician se dividen así (4242, contados
aparte, 1 798):

- Sin ninguna necesidad (reservas holgadas) y con minas rivales al alcance
  (a menos de 60 000 de su capital o de sus campamentos): 853.
- Sin necesidad y sin minas al alcance: 467.
- Con necesidad pero sin minas rivales a menos de 60 000 de su capital ni de
  sus campamentos: 358.
- Con necesidad y minas, pero de otro tipo: 120.

Dos causas:

1. **Nadie necesita nada.** En los días 201–300 solo el 11–33 % de los días
   nación hay alguna necesidad > 0. El almacén está lleno (349–350 de 350) en
   13 de 14 países el día 300 (4242). Sin necesidad, el peso de cada mina es 0.
2. **Las minas rivales quedan lejos.** Las capitales están a 52 150–121 904 px
   de su vecina más cercana (4242). El territorio de una capital llega a
   5 385–7 577 px y el de los campamentos, a 13 000 como mucho (el campamento
   más lejano está a 10 000 de su capital). Los territorios no se tocan, y las
   minas del rival están cerca de su capital, a más de 60 000 de la nuestra.

Contar solo las minas cerca de los campamentos con el mismo alcance de 60 000
**casi no cambia nada**, porque los campamentos están a 10–14 km de su capital
en un mundo en que los vecinos están a 50–120 km. Medido con el mantenimiento
cuadrático (`mP` 1,0): sin la codicia desde campamentos y con ella dan exactamente las
mismas guerras (12, 5, 10, 10, 13 y 9).

### Regla (implementada, opción B)

- **K1. Codicia desde cualquier sitio propio.** Una extracción de B cuenta
  para A si está a menos de `alcanceCodicia` de **cualquier sitio propio de A:
  sus ciudades y sus campamentos terminados**. Cada mina cuenta una vez. El
  peso sigue siendo `riqueza × necesidad_A[tipo]`.
- **K2. `alcanceCodicia` = 80 000** (hoy 60 000). La búsqueda de meta de
  `planearCampamento` sigue usando 60 000: pasa a una constante propia,
  `campamento.alcanceMeta = 60 000` (así se midió).
- **K3. Escasez de verdad.** Viene del mantenimiento de los campamentos y de la
  necesidad de expansión (0,3 de petróleo cuando no le da para el siguiente
  campamento), descritos en
  [instalaciones-y-economia.md](instalaciones-y-economia.md), sección
  Campamentos. Sin esa escasez, K1 y K2 no sirven de nada: quien va holgado no
  codicia.

Fórmula (igual que hoy salvo el conjunto de puntos):
`disputa(A, B) = Σ_{extracción e de B, ∃ s ∈ sitios(A): dist(s, e) < 80 000}
riqueza(e) × necesidad_A[tipo(e)]`.
Ejemplo: A necesita petróleo (0,3, expansión) y tiene un campamento a 75 000
de dos pozos de B de riqueza 2 y 3. `disputa` = (2 + 3) × 0,3 = 1,5. Deriva por
llamada: −0,15 × 1,5 × (0,5 + 0,6) = −0,25 con agresividad 0,6. Umbral de fuerza:
−min(0,3; 0,075) − 0,25 × 0,3 = −0,15 respecto al de un país sin disputa.

Casos límite:

- **Campamento en obra:** no cuenta (solo los terminados, como el territorio).
- **Campamento destruido o abandonado:** deja de contar ese mismo día; la
  disputa puede bajar a la mitad de una guerra. No cambia nada de la guerra ya
  declarada.
- **Mina de B a menos de 80 000 de un campamento de A, pero el frente (entre
  ciudades) a más de 110 000:** hay codicia (baja la relación) pero no guerra,
  porque la guerra sigue exigiendo el frente a menos de `alcanceGuerra`.
- **País sin necesidades:** disputa 0 aunque tenga mil minas rivales cerca.

### Opciones que se midieron (300 días, 6 semillas; el dueño eligió la B)

Todas con el mantenimiento de campamentos (`mP` 1,0 cuadrático) y la
necesidad de expansión 0,3, salvo "Antes". "Acción" = días con al menos una
salva, incursión aérea o golpe a ciudad entre los días 101 y 300 (de 200).

| Opción | Codicia desde | Guerras por semilla | Suma de 6 | Primera guerra | Acción | Campamentos |
|---|---|---|---|---|---|---|
| Antes (eb5bd72) | capital, 60 000 | 1–4 | 14 | día 61–232 | 94–171 | 248–317 |
| A (lo pedido) | capital y campamentos, 60 000 | 1–6 | 24 | día 61–188 | 103–172 | 115–158 |
| **B (programada)** | capital y campamentos, 80 000 | **5–15** | **62** | **día 25–95** | 82–152 | 133–155 |
| C | capital 110 000, campamentos 60 000 | 9–26 | 102 | no anotada | 78–157 | 130–155 |

- **A** cumple lo que se pidió, pero sube muy poco: a 60 000 los campamentos
  apenas acercan las minas del vecino.
- **B** triplica las guerras sin tocar ninguna otra regla de la guerra. A 500
  días (4242, 12345 y 1): 25, 28 y 11 guerras. Sin la necesidad de expansión
  baja a 52 guerras en 6 semillas; sin contar los campamentos, a 59.
- **C** hace codiciable todo lo que ya se puede atacar (110 000 =
  `alcanceGuerra`). Es la que más guerras da, con una semilla en 26 (casi una
  cada 11 días).

La acción baja un poco en las semillas más tranquilas (la 1 pasa de 94 a 82 en
B), porque las escaramuzas solo se tiran entre países que no están en guerra y
el petróleo que se va en mantenimiento ya no está para misiles. No se midió si
entre los pares que se odian vuelan misiles casi a diario: **falta esa medida**
(salvas por par enemistado y día).

### Criterios de aceptación (opción B)

16 zonas, semillas 4242, 1, 7, 99, 12345 y 2026 (entre paréntesis, lo medido
con las reglas ya programadas en `simulacion.lua`; da lo mismo que el
prototipo del arnés):

- En 300 días, entre 5 y 20 guerras declaradas por semilla (5–15), y entre 45
  y 90 en la suma de las 6 (62).
- Primera guerra antes del día 100 en todas las semillas (25–95).
- En 500 días, entre 10 y 35 guerras por semilla (11–28; 3 semillas).
- Ninguna guerra con el frente a más de 110 000 px ni durante una tregua (se
  deduce del código, no medido).
- Días con acción entre el 101 y el 300: al menos 80 en todas las semillas y
  mediana de al menos 120 (82–152; mediana 131,5).
- Días nación con alguna necesidad > 0 en los días 201–300: entre el 50 y el
  90 % (65–79 %).
- Prueba de que la regla está enchufada: con `alcanceCodicia` = 60 000 (opción
  A) la suma de las 6 semillas baja de 30 guerras (24).

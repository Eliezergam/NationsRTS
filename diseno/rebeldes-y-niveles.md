# Rebeldes y niveles de ciudad

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Estado: **propuesta, nada programado.** Pedido del dueño (2026-09-27). Extiende
[recoleccion-y-batallas.md](recoleccion-y-batallas.md) (batallas y F8) y
[territorio-y-capitales.md](territorio-y-capitales.md) (celdas, bloques,
almacén y bóveda). Mediciones con la simulación de hoy (versión 18) y cuentas
de la regla F8 fuera del juego. Las cifras sin medir llevan la etiqueta
**(cuenta)**.

---

## 1. Resumen

Los **campamentos rebeldes** son un enemigo neutral (no son una nación): salen
de la semilla, unos 3 por cada bloque de bandera (6 × 6 celdas de 500 px, es
decir, 3 000 px o 300 m de lado), en tierra sin dueño. Cada uno tiene un
**nivel del 1 al 50**, que sale del nivel de la capital de su zona, y una
guarnición que crece con él: solo soldados en el nivel 1, tanques desde el 2 y
lanzacohetes desde el 3. Vencerlo da **un solo tipo de recurso**. Después
vuelve a salir, al cabo de un tiempo y en otro punto de su bloque. Solo se
defienden. El jugador pelea en 3D junto al campamento; los NPC, con F8. Las
**ciudades suben hasta el nivel 50**. Cada nivel da más almacén, más bóveda,
más resistencia y un **bonus de golpe** a las tropas. El bonus es el mismo que
tienen los rebeldes de ese nivel, así que se anula entre iguales.

## 2. Fantasía del jugador

- "Siempre tengo algo que atacar cerca: mando un destacamento, gano metal y
  vuelvo."
- "Ese campamento rojo de nivel +5 me tienta, pero necesito el triple de tropa."
- "Subir la ciudad de nivel hace más fuertes a mis tropas, pero los rebeldes de
  alrededor también suben: siempre hay un reto a mi altura."

## 3. Reglas

### 3.1 Dónde salen (determinista, sin guardar nada)

1. El mundo se parte en **bloques rebeldes** de `ladoBloque = 6` celdas
   (3 000 px), alineados a la rejilla de celdas: `bx = floor(cx / 6)`.
2. Cada bloque tiene `porBloque = 3` **huecos** (k = 1, 2, 3). Para que no se
   amontonen, el bloque se parte en 3 × 3 sub-cuadros de 1 000 px, y cada hueco
   toma uno distinto, sorteado con `Ruido.hash(semilla, bx, by, 93)`.
3. Cada hueco tiene una **encarnación** `gen` (ver 3.5). Su posición dentro del
   sub-cuadro, su recurso y su desviación de nivel salen de
   `Ruido.hash(semilla, bx, by, 94, k, gen)`.
4. **Hueco vacío** si el punto no pasa `sitioValido` (agua, casco de ciudad), si
   su celda tiene dueño (`duenoCelda ~= nil`) o si está a menos de
   `distanciaCapital = 10 000` px de una capital (como los templos). Se
   comprueba al nacer cada encarnación; ver 5 para una celda que cambia de dueño
   con el campamento vivo.
5. **Nada se recorre entero:** la simulación solo mira los bloques cerca de
   donde busca (la IA, a menos de 1,5 días de marcha de su territorio; la vista,
   lo que se ve en pantalla).

### 3.2 Nivel

1. `nivelRef` = nivel que tenía la **capital de la zona** del bloque (una por
   zona de 98 304 px) el día en que nació la encarnación. Para eso cada ciudad
   guarda `c.subidas[nivel] = día` (como mucho 49 números).
2. Si la zona no tiene nación registrada (mundo lejano): `nivelRef = 1 +
   floor(día / diasPorNivelLibre)`, con `diasPorNivelLibre = 90`.
3. `nivel = clamp(nivelRef + desviación, 1, 50)`. La desviación sale del hash
   (u de 0 a 1):

   | u | < 0,10 | < 0,30 | < 0,80 | < 0,90 | < 0,95 | < 0,98 | < 0,995 | resto |
   |---|---|---|---|---|---|---|---|---|
   | desviación | −2 | −1 | 0 | +1 | +2 | +3 | +4 | +5 |

   Así, cuando la capital sube de nivel, los campamentos no suben todos a la
   vez. Suben a medida que renacen, por derrota o por renovación (3.5).
4. El nivel **no cambia** mientras la encarnación vive.

### 3.3 Guarnición por nivel

- **Vida total** `VR(N)` (F1). Los tipos se reparten por **parte de la vida**,
  con los pesos de hoy (soldado 1, tanque 9, lanzacohetes 40):
  - N = 1: todo soldados;
  - N = 2: 15 % en tanques;
  - N ≥ 3: tanques `min(0,45, 0,20 + 0,01·(N−3))` y lanzacohetes
    `min(0,35, 0,10 + 0,01·(N−3))`; el resto, soldados (nunca menos del 20 %).
- Cada tipo desbloqueado tiene **al menos 1 unidad**. Se redondea hacia abajo
  en tanques y lanzacohetes, y lo que sobra de vida se da en soldados.
- **Tipos futuros** (aviones y otros): cuando la escena 3D los use (decisión 4
  del §9 de `recoleccion-y-batallas.md`), cada uno tendrá su nivel de
  desbloqueo y le quitará parte a los soldados. Esos niveles están sin fijar.
- Los rebeldes golpean con el bonus de su nivel, `B(N)` (F3), y con
  `fortificacion = 1,1`: es su casa, como `ventajaDefensa`.

| N | Soldados | Tanques | Lanzacohetes | Vida VR | Poder (5,5·VR·B) |
|---|---|---|---|---|---|
| 1 | 200 | 0 | 0 | 200 | 1 100 |
| 2 | 194 | 3 | 0 | 221 | 1 255 |
| 3 | 160 | 5 | 1 | 245 | 1 433 |
| 5 | 198 | 7 | 1 | 301 | 1 866 |
| 10 | 288 | 15 | 2 | 503 | 3 612 |
| 15 | 419 | 29 | 4 | 840 | 6 993 |
| 20 | 530 | 57 | 9 | 1 403 | 13 538 |
| 30 | 799 | 195 | 34 | 3 914 | 50 737 |
| 40 | 2 211 | 545 | 95 | 10 916 | 190 149 |
| 50 | 6 104 | 1 522 | 266 | 30 442 | 712 631 |

### 3.4 Batalla

1. Un grupo con misión `atacar` sobre un campamento rebelde crea una
   **batalla** (3.7 de `recoleccion-y-batallas.md`). El bando defensor es la
   guarnición rebelde y el lugar, el campamento.
2. **Jugador:** el pregón de siempre ("Entrar en 3D / Se resuelve sola"). La
   escena se genera alrededor del campamento: tiendas y parapetos en el centro,
   los rebeldes desplegados alrededor y el jugador entrando por el lado por el
   que llega. Al acabar, `resolverBatalla`.
3. **Sin ver (NPC o jugador que no entra):** F8, con `golpe(rebeldes) =
   vidaRebelde × B(N) × fortificacion`. El golpe de un bando de nación
   también se multiplica por el `B` del nivel de su capital (F3).
4. **Victoria:** cuando a los rebeldes les queda menos del 10 % de `VR`, se
   dispersan y el campamento queda vencido. **Derrota:** el atacante se retira
   por su umbral, como siempre.
5. **Los rebeldes no se retiran** ni persiguen a nadie.
6. **Tras un ataque fallido**, la guarnición recupera un 10 % de `VR` al día
   hasta llenarse. Varios ataques seguidos la desgastan, pero no para siempre.
7. **Varias naciones a la vez:** todas son bando atacante contra los rebeldes.
   No se pelean entre sí dentro de esa batalla, aunque estén en guerra; eso va
   por choque, fuera. El golpe rebelde se reparte entre ellas en proporción a
   la vida de cada una. El botín se reparte en proporción a las bajas rebeldes
   que causó cada nación.

### 3.5 Botín, reaparición y renovación

1. **Un solo recurso** por encarnación, sorteado entre metal, petróleo, comida
   y oro (pesos 0,35 / 0,30 / 0,25 / 0,10). La cantidad sale de F2.
2. El ganador **carga lo que le quepa** (capacidad de F2 de
   `recoleccion-y-batallas.md`). El resto queda en el sitio como **alijo** hasta
   que renace el campamento, y cualquier grupo puede ir a cargarlo, sin batalla
   si no hay nadie. Es la misma idea que la decisión 2 ("lo que le quepa").
3. **Enfriamiento** tras la derrota: `vuelve = día + 15 + floor(u × 11)`, es
   decir, de **15 a 25 días**. Entonces `gen` sube en 1: **otro punto** de su
   bloque, quizá otro recurso y el nivel de ese día.
4. **Renovación** de los que nadie ataca: cada `ciclo = 60` días, con una fase
   propia de cada hueco (hash), `gen` sube solo si no hay batalla ahí. Así los
   niveles altos van apareciendo poco a poco, sin tener que ganar batallas.
   `gen = floor((día + fase) / ciclo) + derrotas`.
5. **Guardado:** solo los huecos tocados: `e.rebeldes[clave] = { derrotas,
   vuelve, bajas, alijo }`. Los demás salen de la semilla y de `c.subidas`.

### 3.6 IA de los NPC

1. Cada 2 días, por nación: mira los campamentos a menos de 1,5 días de marcha
   de su territorio (`viajeDias = distancia / 9 000`).
2. `valor = necesidad[tipo] × botin / (1 + viajeDias)`. El valor vale 0 si hay
   un ejército enemigo en guerra a menos de 1 día (como `seguridad` en F10).
3. Ataca el de más valor si tiene tropas libres (por encima de la guarnición
   mínima) para `A ≥ factorIA × VR(N) × √(B(N) × 1,1 / B(propio))`, con
   `factorIA = 2,2 − agresividad` (de 1,2 a 2,2). Manda justo eso.
4. No hay tope de ataques a la vez: solo tropas libres y camino. Atacar
   rebeldes no declara guerra a nadie.
5. El jugador usa el mismo comando: `ejecutar({ tipo = 'atacarRebeldes',
   nacion, bloque, hueco, grupo })`.

### 3.7 Mapa 2D

- Icono de campamento (tienda con bandera negra), con el **número de nivel** y
  un icono pequeño del recurso.
- El color depende del nivel de tu capital (C): gris si es ≤ C−3, blanco de
  C−2 a C, amarillo de C+1 a C+2, naranja de C+3 a C+4 y rojo si es ≥ C+5.
- Al pasar el ratón se ve el poder (5,5·VR·B), el recurso, el botín y el alijo
  si lo hay.
- Enfriamiento: ruinas sin número y "vuelve en N días".
- **Densidad en pantalla:** hay uno cada ~1 730 px. Con el zoom lejano, la vista
  muestra solo los que están a C+1 o más, o los agrupa. La decisión es de la
  interfaz (Valeria).

### 3.8 Niveles de ciudad del 1 al 50

1. Los niveles 1 a 5 **no cambian** (`Simulacion.niveles` de hoy).
2. Del 6 al 50 se sube con el mismo comando `mejorarCiudad`, con el coste y los
   días de F4. **Novedad:** pagan dinero, que hoy se pierde por la merma de la
   bóveda (medido: de 162 a 250 al día por nación entre los días 301 y 500).
3. Cada nivel da `minas`, almacén, bóveda, resistencia (F5), bonus de golpe
   (F3), el tope de defensas y el ritmo de reparación (este ya depende del
   nivel: `2 + nivel`).

### 3.9 Reglas de la casa

- **Sin turnos ni topes:** no hay límite de ataques a rebeldes ni de
  campamentos por jugador. Frenan el camino, las bajas (heridos que tardan en
  volver) y la carga. La mejora de ciudad sigue siendo una por ciudad, porque
  los niveles van en orden.
- **NPC = jugador:** el mismo comando, las mismas fórmulas y el mismo bonus. La
  única diferencia es que el jugador puede entrar en 3D.
- **Determinismo:** la posición, el nivel y el recurso salen de hash y
  `c.subidas`; F8 usa el azar del día en orden fijo (batallas por id).

## 4. Fórmulas

**F1. Vida de la guarnición.** `VR(N) = V1 × g^(N−1)`, con `V1 = 200` y
`g = 1,108`. Va de 200 a 30 442 (tabla 3.3). Cada 5 niveles, ×1,67.
Ejemplo: N = 10 → 200 × 1,108⁹ = 503.

**F2. Botín.** `botin = base[tipo] × g^(N−1)`, con `base = { metal 12,
petroleo 12, comida 20, oro 3 }` (el oro vale 8 de dinero cada uno).
Ejemplos: metal N = 1 → 12; N = 10 → 30; N = 20 → 84; N = 50 → 1 827.
Carga: 12 de metal caben en 40 soldados (0,3 cada uno), y el ejército típico
para N = 1 es de 300.

**F3. Bonus de golpe por nivel.** `B(N) = 1,03^(N−1)`: 1,00 / 1,13 (N = 5) /
1,30 (10) / 1,75 (20) / 2,36 (30) / 4,26 (50). Multiplica el golpe en F8 y el
daño en la escena 3D de todas las tropas de la nación (el nivel de su capital)
y de los rebeldes de nivel N. Entre dos naciones: de nivel 10 contra nivel 5,
×1,16.

**F4. Subir al nivel L (L ≥ 6).**
`metal = 500 × 1,1^(L−5)`, `petroleo = 0,4 × metal`, `dinero = 10 × metal`,
`dias = 60`.

| L | Metal / petróleo / dinero | Almacén (F1 cap.) | Bóveda | minas | Resistencia |
|---|---|---|---|---|---|
| 5 | 500 / 200 / 0 (hoy) | 1 000 | 10 000 | 2,00 | 1,16 |
| 6 | 550 / 220 / 5 500 | 1 100 | 11 000 | 2,05 | 1,20 |
| 10 | 805 / 322 / 8 053 | 1 611 | 16 105 | 2,25 | 1,36 |
| 20 | 2 089 / 835 / 20 886 | 4 177 | 41 772 | 2,75 | 1,76 |
| 30 | 5 417 / 2 167 / 54 174 | 10 835 | 108 347 | 3,25 | 2,16 |
| 40 | 14 051 / 5 620 / 140 512 | 28 102 | 281 024 | 3,75 | 2,56 |
| 50 | 36 445 / 14 578 / 364 452 | 72 890 | 728 905 | 4,25 | 2,96 |

- **Almacén** (extiende F1 de capitales): `1 000 × 1,1^(L−5)` desde L = 6.
  **Bóveda** = 10 × almacén (F1b). El coste de subir es siempre el 55 % del
  almacén del nivel anterior, así que **siempre cabe** (no se repite el error
  del nivel 5).
- `minas = 2 + 0,05 × (L−5)`; `granero = 4 + 0,5 × (L−5)`; tope de defensas
  `30 + 3 × (L−5)` (165 en L = 50).
- **Ritmo:** hoy, la mediana del primer día en cada nivel es: nivel 3, días
  211–259; nivel 4, días 313–321; nivel 5, días 447–472 (medido, semillas 1,
  4242 y 12345; el día 500, entre 5 y 10 capitales de 22–24 están en nivel 5).
  Con 60 días por nivel, llegar a 50 lleva **como mínimo** ~3 150 días (cuenta;
  unas 52 h a 60 s por día). El freno de recursos **no está medido**.

**F5. Resistencia de la capital.** `R(L) = 1 + 0,04 × (L−1)`, en F3 de
capitales: `ΔV = 100 × G / (G + D × R(L))`. La vida sigue en la escala de 0 a
100. Ejemplo: el asalto de F3 (G = 246, D = 6 616) da ΔV = 3,6 en L = 1 y
100 × 246 / (246 + 6 616 × 1,76) = **2,1** en L = 20.

**F6. Ejército razonable.** Por la ley de F8 (bajas ∝ golpe enemigo), para
ganar con pocas bajas hace falta `A ≈ 1,5 × VR(M) × √(B(M) × 1,1 / B(N))`
(jugador de nivel N contra rebeldes de nivel M).

## 5. Equilibrio (cuenta de F8 con su azar real, 1 000 batallas por fila)

Regla F8 exacta (golpe × azar 0,06–0,12, `floor`). El atacante se retira al
bajar del 25 % (presidente medio); los rebeldes, a 0 (en la regla final es el
10 %, así que las cifras reales serán algo mejores). "Bajas" = vida perdida por
el atacante; todo queda herido (`recuperable = 1`) y vuelve con la cola de
recuperación.

| Jugador N | Rebeldes | Ejército (× VR(N)) | Gana | Bajas medias | Días |
|---|---|---|---|---|---|
| 1 | N | 1,5 (300) | 100 % | 31 % | 9,8 |
| 5 | N | 1,5 (452) | 100 % | 31 % | 8,7 |
| 10 | N | 1,5 (755) | 100 % | 32 % | 7,6 |
| 20 | N | 1,5 (2 105) | 100 % | 34 % | 5,7 |
| 45 | N | 1,5 (27 344) | 100 % | 40 % | 3,0 |
| 10 | N | 2,0 | 100 % | 18 % | 5,2 |
| 10 | N+2 | 1,5 | 96 % | 58 % | 11,7 |
| 5 | N+5 | 1,5 | 0 % | 80 % | 7,2 |
| 10 | N+5 | 2,0 | 62 % | 69 % | 12,0 |
| 10 | N+5 | 3,0 | 100 % | 26 % | 6,1 |
| 30 | N+5 | 3,0 | 100 % | 30 % | 3,6 |
| 45 | N+5 | 3,0 | 100 % | 34 % | 2,4 |

- **Mismo nivel:** con 1,5 veces su vida se gana siempre, perdiendo (heridos)
  un 31–40 %. Con el doble, un 18–25 %.
- **N+5:** con el ejército de siempre se pierde siempre. Con el doble es una
  moneda al aire (48–65 %) y con el triple se gana perdiendo un 25–34 %. Es el
  "reto serio" que se pedía.
- **Peso en la nación (medido: vida militar total por nación, mediana).** Día
  100 (todas en nivel 2): de 2 043 a 2 106. Día 500: de 8 837 a 13 959. El
  ejército para un rebelde de nivel 2 (333) es el **16 %** de la nación el día
  100. Para uno de nivel 5 (452), un **3–5 %** el día 500: una nación mediana
  puede tener unos 10 ataques a la vez. Se buscaba justo eso ("atacarlos todo
  el tiempo"). Si resulta demasiado fácil, se sube `g` (perillas).
- **Economía (cuenta, sin medir):** 10 ataques a la vez de ~12 días
  ida-batalla-vuelta con botín 18 dan unos 15 de un recurso al día. Es del
  orden de lo que producen las instalaciones entre los días 301 y 500 (medido:
  metal 21,8–32,7; petróleo 84–130 al día). Pesa, pero no lo reemplaza. Hay que
  medirlo (criterio 5).

### Densidad (pregunta 1)

- Bloque de 3 000 × 3 000 px con 3 huecos: **uno cada 3 millones de px²**; entre
  vecinos hay ~1 730 px (173 m).
- Tierra válida medida en bloques de 3 000 px a menos de 27 000 px de cada
  capital: **55,4–55,9 %** (semillas 1, 4242 y 12345).
- A 1 día de marcha (9 000 px): 85 huecos × 0,56 = **~47 campamentos** (cuenta,
  sin restar el territorio). Por zona de nación (98 304 px de lado): 1 074
  bloques → **~1 800** (cuenta), frente a los 320–350 yacimientos medidos por
  nación.
- **Jugable:** nunca falta un objetivo y la IA solo mira unos ~100 huecos (el
  coste es pequeño). **Los problemas:** se llena el mapa 2D y en una escena 3D
  de más de ~170 m se verían campamentos vecinos. Con 3 por bloque, el
  enfriamiento casi no importa (siempre hay otro al lado).

## 6. Casos límite

- **La celda pasa a tener dueño con el campamento vivo** (bandera nueva): el
  campamento sigue hasta que lo vencen o se renueva; entonces el hueco queda
  vacío mientras la celda tenga dueño. La bandera se puede plantar igual.
- **Batalla en curso al renovarse:** no se renueva; la renovación espera al
  final de la batalla.
- **Alijo sin recoger al renacer:** se pierde.
- **El atacante vence pero no le cabe nada** (carga llena): todo va al alijo.
- **La capital de la zona sube de nivel durante la batalla:** el nivel rebelde
  no cambia (3.2.4). El `B` del atacante se lee cada día.
- **Nación destruida o zona sin capital:** se usa la regla de los días (3.2.2).
- **Jugador que sale de la escena a mitad:** sigue con F8, como las demás
  batallas.
- **Nivel > 50 o < 1:** `clamp`. Un nivel 50 con desviación +5 queda en 50.
- **Capital nace en nivel 2** (`nivelInicial`): al empezar, los campamentos de
  su zona son de nivel 1 (30 %), 2 (50 %) o 3–7 (20 %).

## 7. Dependencias

- **Depende de:**
  - [recoleccion-y-batallas.md](recoleccion-y-batallas.md): la batalla por
    bandos, F8, `resolverBatalla`, la capacidad de carga (F2) y "lo que le
    quepa" (decisión 2);
  - [territorio-y-capitales.md](territorio-y-capitales.md): celdas, bloques,
    `duenoCelda`, almacén (F1), bóveda (F1b) y vida de la capital (F3);
  - [ejercitos-en-el-mapa.md](ejercitos-en-el-mapa.md): grupos, poder
    (`escalaPoder`) y choques;
  - [retirada-y-recuperacion.md](retirada-y-recuperacion.md): umbral de
    retirada y heridos;
  - [instalaciones-y-economia.md](instalaciones-y-economia.md): `niveles`,
    `minas` y `granero`.
- **Lo usan / hay que actualizar:**
  - `recoleccion-y-batallas.md` y `territorio-y-capitales.md` (ya nombran este
    documento en su §6);
  - `instalaciones-y-economia.md`: la tabla de niveles hasta 50;
  - `naciones-y-politica.md`: la IA de ataque a rebeldes (3.6);
  - `interfaz.md`: icono, colores y filtro por zoom (3.7);
  - `GUIA-3D.md`: la escena de campamento rebelde;
  - `diseno-de-armamento.md`: el nivel de desbloqueo de los tipos futuros.

## 8. Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `porBloque` | 3 | 1–3 | Densidad: 1 = ~16 a un día de marcha |
| `V1` | 200 | 120–400 | Dureza del nivel 1 |
| `g` | 1,108 | 1,08–1,15 | Dureza a nivel alto y el salto de N+5 (1,15 → ×2 cada 5 niveles) |
| `b` (en B) | 1,03 | 1,02–1,04 | Bonus por nivel; con más de 1,04, el nivel pesa más que el tamaño en guerras entre naciones |
| `fortificacion` | 1,1 | 1,0–1,25 | Ventaja rebelde en su casa |
| `base` del botín | 12/12/20/3 | ×0,5–×2 | Peso de los rebeldes en la economía |
| enfriamiento | 15–25 días | 5–40 | Poco efecto con 3 por bloque |
| `ciclo` | 60 | 30–120 | Rapidez con que aparecen los de nivel nuevo |
| desviación | −2…+5 | — | Cuántos retos rojos hay (hoy ~2 % a +4/+5) |
| `diasPorNivelLibre` | 90 | 60–150 | Nivel en zonas sin nación |
| `dias` por nivel (L ≥ 6) | 60 | 30–120 | Duración de la partida hasta 50 |
| crecimiento del coste | 1,1 | 1,05–1,15 | Freno de recursos por nivel |
| `R(L)` | 0,04 | 0,02–0,06 | Aguante de la capital |

## 9. Criterios de aceptación

1. **Determinismo:** en una zona, la lista de campamentos (posición, nivel,
   recurso) el día 200 es idéntica al calcularla dos veces y tras guardar y
   cargar.
2. **Densidad:** en un cuadrado de 30 000 px alrededor de cada capital, el día
   0, hay entre 120 y 180 campamentos (cuenta: 300 huecos × 0,56 menos el
   bloque de la capital).
3. **F8:** con 1 000 batallas por fila, mismo nivel y 1,5 × VR: gana ≥ 95 % con
   bajas del 25–45 %; N+5 con 1,5 × VR: gana ≤ 5 %; N+5 con 3 × VR: gana ≥ 95 %.
4. **Niveles:** en 500 días, entre el 3 % y el 7 % de las encarnaciones nacen a
   `nivelRef + 3` o más.
5. **Economía:** entre los días 301 y 500, el botín rebelde por nación está
   entre el 10 % y el 60 % de lo que producen las instalaciones de ese recurso.
6. **IA:** desde el día 50, cada nación ataca al menos 1 campamento cada 20
   días; ninguna pierde más del 20 % de su vida militar por culpa de los
   rebeldes en 100 días.
7. **Ritmo:** en 3 000 días, la primera capital en nivel 10 llega entre los
   días 800 y 1 400, y ninguna llega a 50 antes del día 3 000.
8. **Rendimiento:** el día simulado no cuesta más de un 10 % más que hoy
   (~30 ms en el arnés).
9. **3D:** la alineación de F8 con la escena (criterio 9 de
   `recoleccion-y-batallas.md`) se cumple también con rebeldes de nivel 1, 10
   y 30.

## 10. Decisiones del dueño (2026-09-27)

Mandan sobre lo anterior del documento.

1. **Densidad: como mucho 3 por bloque de bandera (3 000 px), rellenando.**
   el dueño: "aparecen si no hay más: si ya hay 3 no aparecen más, pero si
   falta 1 aparece, o si no hay nada aparecen". Cada bloque tiende a tener 3
   campamentos vivos. Cuando uno se vence, su hueco se rellena al acabar el
   cooldown (15-25 días), y nunca hay más de 3.
2. **Salen en cualquier sitio,** también dentro del territorio de una nación
   (incluido el de la capital). Se mantiene la distancia mínima a la capital
   si el documento la justifica por jugabilidad; si no, se quita.
3. **Nivel:** el de la capital de la zona, con la desviación de −2 a +5 (lo
   recomendado).

## Cómo se midió

Arnés fuera del repositorio (`scratchpad/lucia/rebeldes.lua` y
`scratchpad/lucia/f8reb.lua`), con `luajit` y sin LÖVE, sobre la simulación de
hoy (versión 18, HEAD c90aa0a), sin cambiar ninguna regla.

- **`rebeldes.lua`:** crea el mundo como el arnés de
  `recoleccion-y-batallas.md` (25 zonas) y avanza 500 días con las semillas 1,
  4242 y 12345. Anota los niveles de las capitales, la vida militar por nación
  cada 100 días y el primer día en cada nivel, y mide la tierra válida en
  bloques de 3 000 px a menos de 27 000 px de cada capital.
- **`f8reb.lua`:** aplica la regla F8 con azar uniforme de 0,06 a 0,12 y
  `floor`, 1 000 batallas por fila. Es una cuenta de la fórmula propuesta, no
  una medición del juego.

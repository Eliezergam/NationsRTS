# Taller por zona

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Diseño de Lucía del 2026-10-01. Documenta lo que hace el código del commit
f0e3286 de Andrés (versión 28 del guardado; `mundo/simulacion/averias.lua` y
`mundo/simulacion/taller.lua`) y, aparte (§9), lo que propongo con cifras
medidas.

Decisión del dueño que lo origina (D2 de `batalla/DANO-REAL.md` §10.5): el
taller repara por zona, «una oruga, rápido y barato; un motor, caro».

## 1. Resumen

Un vehículo averiado ya no trae solo un número de daño: trae **qué se le
rompió**. Hay cuatro zonas (orugas, torreta, cañón y motor) más el **casco**
(agujeros, de 0 a 1). Cada zona tiene su trabajo de taller, su dinero y su
metal. El taller suma las zonas del vehículo y lo repara a su ritmo de
siempre. Al terminar, cobra.

Las bajas de la tripulación no se reparan en el taller. Son personas: los
muertos salen de la población de su ciudad y los heridos se curan al ritmo de
los soldados.

Sustituye, para los vehículos, el cobro `reparacion × daño` de
`economia.md` F12. Lo demás de F12 (ritmo por nivel y pago al terminar) sigue
igual.

## 2. Fantasía del jugador

- «Me rompieron la oruga: el tanque está de vuelta mañana y casi gratis».
- «Le dieron en el motor: dos días de taller y bastante dinero».
- «Me cambian el tubo del cañón: lo que más metal pide».
- «La batalla me dejó los cascos agujereados: eso es lo que de verdad me
  cuesta».
- «Perdí tripulantes. Los heridos vuelven en unos días; los muertos no
  vuelven».

## 3. Reglas (lo que hace el código)

1. **Al salir de la batalla,** cada vehículo averiado lleva un código de
   averías (`averias.zonas[tipo][k]`), junto a su daño y su modelo:
   - en la batalla 3D, el código sale de las zonas que manda la escena
     (`DANO-REAL.md` §5.6);
   - en la batalla simulada, se sortea con las probabilidades de §4.4, que
     se midieron en la batalla 3D.
2. **Código** = máscara de zonas + 16 × casco en milésimas. Máscara: orugas
   1, torreta 2, cañón 4 y motor 8. Ejemplo: oruga y motor rotos con 0,3 de
   casco = 1 + 8 + 16 × 300 = 4 809.
3. **Trabajo** del vehículo = la suma del trabajo de sus zonas más el casco
   × el trabajo del casco (§4.1). Ese número sustituye al «daño» de la lista
   del taller.
4. **El vehículo viaja con su grupo** y entra en el taller de su ciudad al
   volver. Si el grupo cae entero, vuelve remolcado (como antes).
5. **Cola.** El taller ordena los vehículos de menor a mayor trabajo, sin
   mover al que ya se está reparando.
6. **Cada día** el taller repara `ritmo(modelo) × nivel` puntos. Lo que
   sobra de un vehículo pasa al siguiente.
7. **Al terminar un vehículo** se paga el coste de sus zonas (§4.2). Si no
   alcanza el dinero o el metal, el vehículo espera reparado hasta que
   alcance.
8. **Ciudad sitiada:** no repara ni cura. **Con hambre:** repara vehículos,
   pero no cura soldados ni tripulantes.
9. **Acelerar.** Se puede pagar para sacar ya vehículos de la cola: el
   precio de siempre por unidad (22 un tanque y 33 un lanzacohetes) más el
   coste de sus zonas. Los NPC lo hacen en guerra o en la frontera, igual que
   antes.
10. **Tripulación:**
    - Cada tripulante que cae muere con 0,4 de probabilidad; si no, queda
      herido.
    - Los muertos salen de la población civil en edad militar de su ciudad
      (no son soldados en filas).
    - Los heridos viajan con las averías del grupo y, en la ciudad, se curan
      al ritmo de los soldados (25 al día por nivel) en su propia cuenta.
11. **Partidas viejas** (versión 27): cada avería de antes pasa a «casco d».
    Cuesta y tarda lo mismo que antes.

## 4. Fórmulas

### 4.1 Trabajo de taller

```
trabajo = Σ trabajo(zona rota) + casco × trabajo(casco)
días    = trabajo / (ritmo(modelo) × nivel)
```

- `ritmo(modelo)` = 0,5 × 9 / vida en los tanques y 0,4 × 40 / vida en los
  lanzacohetes (`catalogo-armamento.md` F8). T-72B: 0,5. Scud-B: 0,4.
- `casco` va de 0 a 1 (`estructuraMaxima = 1`).

### 4.2 Coste

```
dinero = reparacion(modelo).dinero × (Σ dinero(zona rota) + casco × dinero(casco))
metal  = reparacion(modelo).metal  × (Σ metal(zona rota)  + casco × metal(casco))
```

`reparacion(modelo)`: la de daño 1 del catálogo. T-72B: 12 de dinero y 2 de
metal. Scud-B: 16 y 3.

### 4.3 Valores por zona

Partes de la reparación de daño 1 y, entre paréntesis, lo que da en un T-72B
y en un Scud-B en un taller de nivel 1.

| Zona | Trabajo | Dinero | Metal | T-72B: días / dinero / metal | Scud-B: días / dinero / metal | Razón |
|---|---|---|---|---|---|---|
| Orugas (ruedas en el camión) | 0,15 | 0,15 | 0,1 | 0,3 / 1,8 / 0,2 | 0,375 / 2,4 / 0,3 | Eslabones y ruedas se cambian en el sitio. Rápida y barata |
| Torreta | 0,5 | 0,5 | 0,3 | 1 / 6 / 0,6 | (no tiene) | Anillo y mecanismo de giro: piezas pequeñas y mucho ajuste |
| Cañón (lanzador en el camión) | 0,8 | 0,9 | 1,5 | 1,6 / 10,8 / 3 | 2 / 14,4 / 4,5 | Tubo nuevo: una pieza grande de acero. Lo más caro en metal |
| Motor | 1,0 | 1,2 | 1,0 | 2 / 14,4 / 2 | 2,5 / 19,2 / 3 | Cambio del grupo motor: lo más largo y lo más caro en dinero |
| Casco, por cada 1,0 | 1 | 1 | 1 | 2 / 12 / 2 | 2,5 / 16 / 3 | Igual que el daño 1 de antes, para que las partidas viejas no cambien |

Las razones son del juego, no de fuentes: no he buscado tiempos reales de
reparación (**no recogido**).

### 4.4 Avería de la batalla simulada

Probabilidad de cada avería por vehículo que cae (`Averias.reglas.simulada`),
medida en la batalla 3D: 180 tanques y 58 lanzacohetes averiados en las
semillas 42, 7 y 1234, a 900 s y con la onda × 3.

| | Orugas | Torreta | Cañón | Motor | Casco | Casco medio | Bajas de tripulación | Toda la tripulación |
|---|---|---|---|---|---|---|---|---|
| Tanques | 0,74 | 0,04 | 0,08 | 0,06 | 1 | 0,83 × (0,5 a 1,5), tope 1 | 0,39 | 0,7 |
| Lanzacohetes | 0,59 | 0 | 0,12 | 0,21 | 0,97 | 0,59 × (0,5 a 1,5) | 0,83 | 0,25 |

### 4.5 Ejemplo: el tanque medio que cae

Un T-72B que cae en la batalla simulada (esperanza, calculada con §4.3 y
§4.4; el casco medio con el tope es 0,794):

- **trabajo** = 0,74 × 0,15 + 0,04 × 0,5 + 0,08 × 0,8 + 0,06 × 1 + 0,794
  = 1,05 → **2,1 días** en un taller de nivel 1;
- **dinero** = 12 × 1,07 = **12,8**, el 43 % de los 30 de un T-72B nuevo;
- **metal** = 2 × 1,06 = **2,1**, el 71 % de los 3 de uno nuevo;
- **el casco es el 74 % del dinero y el 76 % del trabajo.** Las zonas
  pesan poco porque casi todo vehículo que cae trae el casco agujereado
  (de la onda y de las penetraciones).

Un Scud-B medio: 2,4 días, 16,3 de dinero y 3,1 de metal (el 41 % y el 51 %
de uno nuevo, 40 y 6).

**Medido** (auditor, 500 días, semillas 1, 7, 42 y 1234; media de todos los
vehículos reparados, de todos los modelos): 11,7 de dinero y 2,10 de metal por
vehículo. Cuadra con el cálculo.

## 5. Casos límite

- **Sin dinero o sin metal al terminar:** el vehículo espera reparado; no
  pierde lo hecho y sale el día que se pueda pagar.
- **Avería sin zonas** (la escena manda `{}`, o solo bajas de tripulación,
  por ejemplo la metralla en la cabina de un camión): código 0, trabajo 0 y
  coste 0. Sale del taller el mismo día y gratis. La tripulación herida va
  aparte.
- **En la batalla simulada nunca sale un código vacío:** sin nada roto, se
  apunta casco 0,15 (lo mínimo de una penetración).
- **Casco por encima de 1:** se recorta a 1. Un casco deshecho no cuesta más
  que rehacerlo.
- **Ciudad sitiada:** la cola se congela entera.
- **Hambre:** los vehículos se reparan; los heridos (soldados y tripulantes)
  no se curan.
- **Ciudad perdida:** la cola va con la ciudad (`economia.md`, casos
  límite).
- **Partida vieja (versión 27):** cada avería pasa a casco d, con el mismo
  coste y los mismos días que antes.
- **Modelo sin ficha:** se usa el de referencia (T-72B o Scud-B).

## 6. Dependencias

**De qué depende:**

- `batalla/DANO-REAL.md` §5.4 a §5.6: zonas, tripulación y formato que manda
  la escena 3D.
- `mundo/simulacion/averias.lua`: código, trabajo, coste y la avería
  simulada.
- `catalogo-armamento.md` F8: ritmo y reparación de daño 1 de cada modelo.
- `economia.md` §3.11 y F12: ritmo por nivel y pago al terminar.
- `retirada-y-recuperacion.md`: cola de la ciudad, remolque y acelerar.
- `poblacion.md`: de dónde salen los tripulantes muertos.

**Qué depende de esto:**

- El panel del taller de la ciudad (días que faltan, `diasRecuperacion`; y
  precio de acelerar, `precioRecuperacion`).
- La decisión de los NPC de acelerar (`acelerarSiHaceFalta`).
- El auditor (`tools/auditar_economia_nationsrts.lua`): talleres, zonas
  reparadas y tripulantes muertos.
- Las pruebas de economía y de simulación (huellas).

## 7. Perillas de ajuste

Todas en `Averias.reglas` salvo el ritmo (`Simulacion.recuperacion.ritmo`).
El efecto medido está en §9.

| Perilla | Hoy | Rango seguro | Efecto |
|---|---|---|---|
| `zonas.orugas` (trabajo / dinero / metal) | 0,15 / 0,15 / 0,1 | 0,1 – 0,3 | Lo que cuesta un vehículo inmovilizado. Pesa poco: casi siempre va con casco |
| `zonas.torreta` | 0,5 / 0,5 / 0,3 | 0,3 – 0,8 | Rara (4 % de los tanques): casi no se nota |
| `zonas.canon` | 0,8 / 0,9 / 1,5 | 0,5 – 1,2 / 0,6 – 1,5 / 1 – 2,5 | El metal: con 2,5 no se vio cambio por encima del ruido |
| `zonas.motor` | 1,0 / 1,2 / 1,0 | 0,7 – 1,5 / 0,8 – 2,4 / 0,7 – 1,5 | Lo más largo; con trabajo 1,5, sin cambio medible |
| `casco` | 1 / 1 / 1 | 0,5 – 1 | **La perilla que más pesa** (unos tres cuartos del coste). Por debajo de 1, las partidas viejas pagan menos que antes |
| `estructuraMaxima` | 1 | 1 | Tope del casco |
| `ritmo` del taller (tanques / lanzacohetes) | 0,5 / 0,4 | 0,4 – 1 / 0,3 – 0,8 | Más bajo: colas largas. Con la mitad, el 1,8 % de los días-ciudad con más de 10 días de cola |
| `simulada.*` | §4.4 | Las medidas | No es de ajuste: se vuelve a medir en la batalla 3D cuando cambie el daño real |
| `muerteTripulante` | 0,4 | 0,2 – 0,6 | Como `muertos` de F11b |

## 8. Criterios de aceptación

Con `luajit tools/auditar_economia_nationsrts.lua 500 1 7 42 1234`:

1. **Invariante:** «se cumple todos los días» en las cuatro semillas.
2. **Talleres saturados:** «saturados (> 10 días)» ≤ 1 % en cada semilla.
   Hoy: de 0 a 0,63 %.
3. **Cola media** ≤ 5 días en cada semilla. Hoy: de 2,5 a 3,8 días.
4. **Coste por vehículo** (pagado ÷ reparados, de la línea «reparados»):
   - dinero entre 9 y 18 (del 30 al 60 % de un T-72B nuevo). Hoy: 11,7;
   - metal entre 1,2 y 2,4. Hoy: 2,10.
5. **Las zonas se ven:** en «zonas reparadas al día», orugas > torreta +
   cañón + motor en cada semilla (como en la batalla 3D). Hoy: orugas de
   0,53 a 0,84; las otras tres juntas, de 0,14 a 0,28.
6. **Tesoro:** «dinero < 10» y «metal < 5» no suben más de 2 puntos frente a
   la tabla de §9.1 al tocar una perilla del taller.
7. **Determinismo:** dos corridas con las mismas semillas dan la misma
   salida.

## 9. Medidas y propuestas

### 9.1 Cómo se midió

- **Copia congelada** del commit b318b8f (`git archive`) en la carpeta
  temporal: Andrés tenía el auditor y `batallas.lua` a medio cambiar en el
  árbol.
- **Perillas** cambiadas en memoria con un envoltorio que modifica
  `Averias.reglas` y `Simulacion.recuperacion.ritmo` antes de correr el
  auditor. No se tocó el código.
- **Corrida:** 500 días, semillas 1, 7, 42 y 1234. Cifras: la media de las
  cuatro semillas (entre corchetes, la peor y la mejor).
- **Base** (el código de hoy), por nación y día: 83 a 87 de dinero del
  trabajo. Todas las naciones juntas pagan 10,6 de dinero y 1,89 de metal al
  día en reparaciones. Es **un 0,6 % del dinero del trabajo**: el taller no
  pesa en el tesoro.

| Escenario | Reparados al día (todas) | Pagado al día: dinero / metal | Por vehículo: dinero / metal | Días-ciudad con cola | Saturados (> 10 días) | Cola media / máx. | Metal < 5 | Dinero < 10 |
|---|---|---|---|---|---|---|---|---|
| **Base (el código)** | 0,90 [0,75–1,16] | 10,6 / 1,89 | 11,7 / 2,10 | 6,6 % | 0,18 % [0–0,63] | 3,0 / 18 días | 11,4 % | 3,2 % |
| Casco a la mitad (0,5 / 0,5 / 0,5) | 0,85 [0,66–1,16] | 6,5 / 1,16 | 7,6 / 1,37 | 4,3 % | 0,00 % | 2,0 / 9 | 10,5 % | 2,9 % |
| Dinero de todas las zonas × 2 | 0,74 [0,65–0,85] | 17,3 / 1,55 | 23,4 / 2,09 | 5,9 % | 0,10 % | 2,3 / 18 | 11,0 % | 3,0 % |
| Motor trabajo 1,5 y cañón metal 2,5 | 0,77 [0,61–0,88] | 9,1 / 1,75 | 11,8 / 2,28 | 5,0 % | 0,03 % | 2,6 / 16 | 10,9 % | 3,0 % |
| Ritmo del taller a la mitad (0,25 / 0,2) | 0,69 [0,56–0,83] | 8,1 / 1,43 | 11,6 / 2,06 | 8,3 % | 1,81 % [0,33–2,70] | 6,9 / 34 | 13,3 % | 3,4 % |

**Comprobación con el commit siguiente** (10f8316, que cambia los soldados
heridos de un grupo que cae entero; sin perillas): saturados de 0,01 a
0,13 %, cola media de 2,6 a 4,6 días (máximo 19) y de 11,6 a 12,4 de dinero
por vehículo. Las conclusiones no cambian.

**Cómo leerlo:**

- **Ruido.** Cualquier cambio altera las guerras de las 500 jornadas. Por
  eso los vehículos reparados al día van de 0,74 a 0,90 aunque el taller
  trabaje igual, y la mediana del tesoro el día 500 salta de 556 a 788 sin
  razón del taller.
- **Lo que sí es señal:** el coste por vehículo, la cola y la saturación.
- **Tesoro y metal** («dinero < 10», «metal < 5»): ningún escenario los mueve
  fuera del ruido. El taller cuesta muy poco frente a lo que entra.

### 9.2 Propuestas (para el dueño)

- **T1. Valores de las zonas.**
  1. **Recomendada: dejarlos como están.** Cumplen los criterios de §8: el
     taller no se satura (0,18 %), la cola media es de 3 días y un vehículo
     cuesta el 43 % del dinero y el 71 % del metal de uno nuevo. Encaja con
     F12: la reparación es el coste de la guerra, pero no ahoga.
  2. **Casco a la mitad** (trabajo, dinero y metal 0,5). Las zonas se notan
     más: la oruga pasa a ser una parte visible de la factura. Un tanque
     medio sale en 1,3 días y cuesta 8 de dinero y 1,3 de metal. Medido:
     −35 % de coste por vehículo, sin saturación y cola media de 2 días.
     Contra: las partidas viejas (casco d) pagan la mitad que antes, y la
     guerra cuesta todavía menos.
  3. **Dinero × 2 en todas las zonas.** Perder un vehículo duele más
     (23 de dinero, el 78 % de uno nuevo), sin efecto medible en el tesoro.
     Es la opción si el dueño quiere que la reparación se note en la caja.
- **T2. Ritmo del taller.** No recomiendo bajarlo. Con la mitad, el 1,8 %
  de los días-ciudad tienen más de 10 días de cola (hasta 34) y salen un
  23 % menos de vehículos reparados al día (parte de eso es ruido; la
  saturación y la cola, no). Va contra la regla del dueño:
  con el avance, se prefieren los blindados. Un taller lento los castiga.
- **T3. Vehículo que sale gratis** (§5, avería sin zonas). Lo dejo así: si
  la escena no rompió nada, no hay nada que pagar. Si el dueño quiere que
  todo paso por el taller cueste algo, la opción es un mínimo de casco 0,15
  también en la escena 3D, como ya hace la simulada. Sin medir.

Ninguna propuesta abarata la infantería ni la protege de la artillería.

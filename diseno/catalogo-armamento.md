# Catálogo de armamento real

> **Estado: DECIDIDO por el dueño el 2026-09-30 (§11), en programación**
> (Andrés). Queda una pregunta nueva, P9, que sale de medir la primera
> versión (§9.1). Sale de la petición del dueño del
> 2026-09-30: «Deberíamos llamar a los tanques por nombres reales y aplicar sus
> características, o sea la fuerza de un tanque real y todo; y a los misiles las
> mismas características de la vida real dependiendo del misil.»
>
> Los datos reales salen de fuentes públicas (Wikipedia, consultada el
> 2026-09-30; lista al final). Donde un dato no aparece en esas fuentes, la
> tabla dice **«no recogido»**: no se completa de memoria. Las cifras de juego
> salen de fórmulas (§4) y las de equilibrio se midieron con la simulación real
> sin ventana (§9, «Cómo se midió»). Lo que no está medido lo dice.
>
> **Primera versión (P2):** cuatro tanques (T-55, T-72B, M1A1, K2) y tres
> lanzadores (Scud-B, BM-21, M142 HIMARS), llamados **solo por su designación**
> (P1). El resto de modelos de §3.1 y §3.2 queda como **reserva**: datos y
> cifras calculadas, fuera del juego hasta que el dueño los pida. Las
> designaciones de la reserva que llevan apodo («Leopard», «Merkava»,
> «Armata», «Grad», «Smerch», «Tochka», «Iskander»…) se escriben aquí como
> referencia de la fuente; si algún día entran, será con la regla de P1.

## 0. Lo que hay hoy en el código

Simulación (`mundo/simulacion.lua`, `mundo/simulacion/produccion.lua`,
`batallas.lua`; copia congelada de HEAD 30b2dda con los cambios sin guardar
del árbol a las 15:23 del 2026-09-30):

| Unidad | Peso en combate (vida = golpe) | Coste | Días | Sueldo | Petróleo parado / en marcha | Munición |
|---|---|---|---|---|---|---|
| Tanque (uno solo) | 9 (`FUERZA.tanques`, `vidaCiudad.pesos.tanques`) | 30 dinero, 3 metal, 1 petróleo | 4 | 0,15 | 0,01 / 0,1 | 17 obuses por día de batalla, 1 por disparo |
| Lanzacohetes (uno solo) | 40 (`conquista.fuerzaLanzacohetes`) | 40, 6, 2 | 6 | 0,2 | 0,01 / 0,15 | 7 misiles por día, 1 por disparo |

Poder de una unidad = 5,5 × (vida + golpe) / 2: tanque 49,5, lanzacohetes 220.
La simulación tiene **un solo peso** por tipo: vida y golpe son el mismo número.

Escena 3D (`batalla/tropas.lua`): el tanque aguanta 3 impactos de obús (daño 1
cada uno), abre fuego a 2,1 km, va a 3,2 m/s (6 m/s con orden), recarga en
6–11 s y se para 3,5 s para disparar. El lanzacohetes lanza un misil cada
ciclo de unos 22,5 s, a entre 0,5 y 3,2 km, con dispersión de 25 m + 2,5 % de
la distancia y daño 2 al 60 % de lo que esté a menos de 18 m.

Modelos 3D:

- Tanque: `SK_Veh_Tank_01` del pack SIMPLE Military de Synty (7,4 × 4,0 m,
  2,98 m de alto), elegido por el dueño para todo el juego (commit eb4f481).
- Camión lanzamisiles: `SK_Veh_ScudTruck_01` del mismo pack: 11 m, ocho
  ruedas y **un** misil de 10,32 m (`assets/modelos3d/SYNTY.md`). Es la
  silueta de un lanzador Scud real (camión MAZ-543 con misil R-17). Las reglas
  de hoy («4 tubos», un misil cada 22,5 s) no son las de un Scud.
- El pack trae más vehículos sin importar: `SK_Veh_tank_02`, dos transportes
  blindados, un coche blindado, un cañón de campaña, camiones de tropas,
  combustible y ambulancia. No los he mirado por dentro.

## 1. Resumen

Cada tanque y cada lanzacohetes del juego pasa a ser un **modelo real** con su
nombre y su ficha de datos públicos: calibre, masa, potencia, velocidad,
tripulación, munición, alcance, precisión, ojiva, año y precio. Unas fórmulas
convierten esa ficha en las cifras del juego (vida, golpe, velocidad, consumo,
coste, días de fábrica, sueldo, taller, poder y, en la escena 3D, impactos que
aguanta, radio de daño, dispersión y alcance). **Lo real manda en las
proporciones; el juego fija la escala**: el T-72B y el Scud-B valen
exactamente lo de hoy y todo lo demás se mide contra ellos, con las
diferencias comprimidas para que ningún modelo rompa el equilibrio. Los
modelos se desbloquean por **eras** (tres tecnologías nuevas), se fabrican con
la orden `producir` de la economía cerrada y son la base sobre la que el
sistema de diseño deriva, más adelante, variantes propias y secretas. La
primera versión trae un tanque por era (T-55, T-72B, M1A1, K2) y tres
lanzadores (Scud-B, BM-21, M142 HIMARS); cualquier nación fabrica todo lo de
su era.

## 2. Fantasía del jugador

- «Mis T-55 son viejos y lentos, pero baratos; cuando investigue el blindaje
  compuesto pasaré a T-72B.»
- «El enemigo trae M1A1: cada uno aguanta casi un impacto más que mis T-72B.
  Necesito más tanques o mejores.»
- «El BM-21 tapa el cielo de cohetes pero reparte; el M142 HIMARS cae casi
  donde apunto.»
- «En el Arsenal leo la ficha real: 125 mm, 44,5 t, 60 km/h, 3 tripulantes.»
- «El M1A1 gasta casi el doble de petróleo que el T-72B. Con poco petróleo me
  conviene otro.»

## 3. Reglas

### 3.1 Datos reales: tanques

Cifras tal como las dan las fuentes (§ Fuentes). «Año» es el de entrada en
servicio que da la ficha para la familia o para la variante indicada. Cuando la
masa o el motor son de otra variante, se dice. En negrita, los de la primera
versión (P2); el resto es reserva, fuera del juego.

| Modelo (variante que se usa) | Año | Cañón | Masa (t) | Potencia | Velocidad carretera / campo (km/h) | Tripulación | Munición a bordo | Autonomía (km) | Blindaje (lo público) | Precio (año) |
|---|---|---|---|---|---|---|---|---|---|---|
| **T-55** (familia T-54/55) | 1948 | 100 mm rayado D-10T | 36 | 14,6 hp/t (500–800 hp según versión) | 51 / no recogido | 4 | 43 | 325 (610 con depósitos extra) | Torreta: 205 mm de frente, 130 de costado, 60 detrás y 30 de techo. Casco: 120 mm a 60° de frente (100 mm desde 1949), 79 de costado arriba y 20 abajo, 60 detrás | 200 000 US$ (exportación, 1956–1972) |
| M60 | 1959 | 105 mm M68 | 47,7 | 750 bhp | 48 / 19 | 4 | no recogido | 500 | Glacis 109 mm a 65° (258 mm en línea de mira); torreta frontal equivale a 250 mm | 481 911 US$ (1962); M60A3: 1,292 M (1990) |
| Leopard 1 | 1965 | 105 mm L7A3 rayado | 42,2 | 830 PS (820 hp) | 65 / no recogido | 4 | 55 (13 + 42) | 600 / 450 campo | Acero 10–70 mm | no recogido |
| **T-72B** | 1969 (familia) | 125 mm 2A46 de ánima lisa | 44,5 | 840 hp (V-84-1) | 60 / no recogido | 3 | no recogido | 500 (650–700 con bidones) | Acero y compuesto con blindaje reactivo. Equivalente contra flecha (Zaloga), con Kontakt-1: torreta 520–540 mm, casco 480–530 mm; con Kontakt-5: 770–800 y 690 | 0,5–1,2 M US$ (1994–1996) |
| T-80U | 1976 (familia) | 125 mm 2A46M-1 | 46 | 1 250 hp (turbina) | 70 / 48 | 3 | 45 + 6 misiles | 335 (415 con depósitos) | 780 mm contra flecha con Kontakt-5 | 3 M US$ (sin año) |
| **M1A1** | 1980 (familia) | 120 mm M256 de ánima lisa | 57 | 1 500 shp (turbina) | 72 (limitada) / 40 | 4 | 40 | 426 (M1A2) / 150–200 campo | Compuesto. Estimación soviética citada por Zaloga (2009): 600 mm contra flecha de frente; M1A1HA (con uranio): casco 600 y torreta 800 | 4,3 M US$ (1989) |
| Leopard 2A6 | 1979 (familia) | 120 mm Rh-120 | 62,3 | 1 500 hp | 70 / no recogido | 4 | 42 | 340 / 220 campo | Compuesto de 3.ª generación (sin cifra) | 5,74 M € de segunda mano (2007) |
| Merkava IV | 1979 (familia) | 120 mm MG251-LR | 65 | 1 501 hp | 64 / 55 | 4 | no recogido | 500 | Clasificado | 3,5 M US$ (2003) |
| Leclerc (Serie 2) | 1992 | 120 mm CN120-26/52 | 56,3 | 27,52 hp/t (1 549 hp calculado) | 71 / 55 | 3 | 40 | 550 (650 con depósitos) | Compuesto modular (sin cifra) | 16 M € (2022) |
| T-90A | 1992 (familia; T-90A desde 2004) | 125 mm 2A46M-2 | 46,5 | 1 000 hp | 60 / no recogido | 3 | 42 | 550 | 800–830 mm contra flecha con Kontakt-5 (T-90) | 2,5 M US$ (1999); T-90SM 4,5 M (2016) |
| Challenger 2 | 1998 | 120 mm L30A1 rayado | 64 | 1 200 bhp | 59 / 40 | 4 | 47 | 550 / 250 campo | Chobham/Dorchester (clasificado) | 4,217 M £ (1999) |
| Type 99A | 2011 | 125 mm ZPT-98 | 55 | 1 500 hp | 76 / 54 | 3 | 42 | 600–650 | Clasificado | 2,5 M US$ (sin año) |
| Type 10 | 2012 | 120 mm L/44 | 44 (carga normal) | 1 200 hp | 70 / no recogido | 3 | 22 | 500 | Compuesto cerámico modular (sin cifra) | 11,3 M US$ (2022) |
| **K2** | 2014 | 120 mm CN08 L/55 | 56 | 1 500 hp | 70 / 50 | 3 | 40 | 450 | Acero, cerámica y reactivo. Contra flecha, sin cifra; contra carga hueca, 900 mm de frente y 330 de costado con reactivo (Comisión de Defensa, 2024) | 8,5 M US$ (dólares de 2009) |
| T-14 | producción en serie anunciada en 2021 | 125 mm 2A82-1M | 55 | 1 500 hp | 75–80 (estimada) | 3 | 45 | 500 como mínimo | Sin cifra | 3,7–4,6 M US$ (2015) |

No recogido para ningún tanque: **alcance eficaz del cañón y cadencia** (las
fichas no los dan, salvo el T-14, cuyo fabricante dice 5 km de alcance eficaz)
y **consumo** de combustible. Los precios son de años y monedas distintos y no
se han corregido por inflación.

### 3.2 Datos reales: lanzacohetes y lanzamisiles

En negrita, los de la primera versión (P2); el resto es reserva.

| Modelo | Año | Tipo | Calibre | Proyectiles por carga | Alcance | Precisión | Ojiva | Cadencia / recarga | Vehículo: masa, velocidad, autonomía, tripulación | Precio |
|---|---|---|---|---|---|---|---|---|---|---|
| **Scud-B** (misil R-17 en camión MAZ-543): **el camión que ya usamos** | 1962 (R-17) | Misil balístico | 885 mm (diámetro del R-17) | 1 | 300 km | CEP 450 m (soviético) / 900 m (occidental) | Explosivo, racimo, químico o nuclear; **masa de la ojiva convencional no recogida** (la ficha rusa cita un requisito de diseño de al menos 900 kg de carga útil) | no recogida | MAZ-543 cargado 37,4 t, 55 km/h, 650 km (texto) o 45 km/h y 450 km (ficha del R-17); tripulación 7; misil 5 682–5 950 kg, 11,2–11,4 m | 1 M US$ (1988) |
| **BM-21** | 1963 | Cohetes de saturación | 122 mm | 40 | 0,5–52 km (20 km los primeros explosivos; 30 km o más los nuevos) | No recogida («menos precisión que la artillería de tubo») | ~20 kg | 40 cohetes en 20 s; recarga no recogida | 13,71 t, 75 km/h, 405 km, 3 | no recogido |
| OTR-21 Tochka | 1976 (Tochka-U, 1989) | Misil balístico táctico | no recogido | 1 | 70 km (Tochka-U, 120 km) | CEP 150 m (Tochka-U, 95 m) | 420 kg explosivo (9M123F) | no recogida | Lanzador BAZ-5921: datos no recogidos; tripulación 3; misil 2 000 kg | 300 000 US$ (sin año) |
| M270 MLRS | 1983 | Cohetes de saturación (y misiles) | 227 mm | 12 cohetes (o 2 ATACMS o 4 PrSM) | M26: 32 km; M30/M31 guiados: 92 km; ATACMS 165–300 km | M26 sin guiar (no recogida) | M26: 644 submuniciones; M31: 91 kg | ~3 s por cohete M26; ~30 s por ATACMS | 24,04 t cargado, 64,4 km/h, 483 km, 3 | 2,3 M US$ el lanzador (1990); cohete M31: 168 000 US$ (2023) |
| TOS-1 | 1988 | Cohetes termobáricos de corto alcance | 220 mm | 30 (TOS-1A: 24) | 0,5–3 km (TOS-1A: 10 km) | No recogida | Termobárica; masa no recogida | 30 cohetes en 15 s | 45,3 t, 60 km/h, 550 km, 3 | no recogido |
| BM-30 Smerch | 1989 | Cohetes de saturación | 300 mm | 12 | 70–90 km (primeros cohetes); 120 km (9M542); 200 km (9M544) | No recogida | Masa no recogida | 12 en 38 s; recarga 20 min | 43,7 t, 60 km/h, 850 km, 3 | no recogido |
| **M142 HIMARS** | 2005 | Cohetes guiados (y misiles) | 227 mm | 6 cohetes (o 1 ATACMS o 2 PrSM) | GMLRS: 15–92 km; ER: 150 km | La ficha da «a 300 km, a menos de 1 m» (se refiere al PrSM); **CEP del GMLRS no recogido** | M31: 91 kg (23 kg de explosivo) | no recogida | 16,25 t, 94 km/h, 480 km, 3 | 3,5 M US$ lanzador y camión (2014); 4,9 M solo lanzador (2024) |
| Iskander-M | 2006 | Misil balístico | no recogido | no recogido por lanzador | 400–500 km (exportación 280 km) | 5–7 m con guiado óptico final; 1–30 m | 480–700 kg | Menos de 1 min entre lanzamientos; listo en 4 min (16 desde la marcha) | Lanzador: datos no recogidos; misil 3 800 kg, 7,3 m | 3 M US$ por misil |

### 3.3 Principio: lo real manda en proporciones, el juego fija la escala

1. **Referencias.** El T-72B (era 2, la del medio; se fabricaron unos 25 000)
   vale exactamente el tanque de hoy: vida 9, golpe 9,
   30 / 3 / 1, 4 días, 0,15 de sueldo. El Scud-B, que es el camión que ya
   existe, vale exactamente el lanzacohetes de hoy: peso 40, 40 / 6 / 2, 6
   días, 7 misiles al día. Así, **con todas las unidades como T-72B y Scud-B,
   el mundo es idéntico al de hoy** (criterio A1).
2. **Cada cifra de juego sale de una o dos cifras reales**, en proporción a la
   referencia, y la diferencia se **comprime** con un exponente (`α`) para que
   un tanque de 65 t no valga el doble que uno de 36 t en la batalla (§4).
3. **El valor por moneda es el mismo para todos los modelos del mismo tipo**:
   el dinero se paga en proporción a vida + golpe. Lo que distingue a un modelo
   es su era, su velocidad, su consumo de petróleo, su metal, su tripulación y
   su tamaño en la escena.
4. **Lo que no es público no se inventa.** Si falta un dato que una fórmula
   necesita, se usa el de la referencia y la tabla del juego lo marca.

### 3.4 Eras y tecnología

La era de un modelo sale de su año (F1). Hay cuatro. Primera versión (P2):

| Era | Años | Tanques | Lanzacohetes | Se desbloquea con |
|---|---|---|---|---|
| 1 | hasta 1968 | T-55 | Scud-B, BM-21 | tanques: la tecnología `tanques` (como hoy); lanzacohetes: nada (como hoy) |
| 2 | 1969–1978 | T-72B | (ninguno nuevo) | tecnología nueva **blindaje compuesto** (coste 1 500) |
| 3 | 1979–1999 | M1A1 | (ninguno nuevo) | tecnología nueva **control de tiro digital** (4 500) |
| 4 | desde 2000 | K2 | M142 HIMARS | tecnología nueva **nueva generación** (9 000) |

Reserva, por era (fuera del juego): 1, M60, Leopard 1; 2, T-80U, Tochka; 3,
Leopard 2A6, Merkava IV, Leclerc, T-90A, Challenger 2, M270, TOS-1, Smerch;
4, Type 99A, Type 10, T-14, Iskander.

**Quién fabrica (P3):** toda nación fabrica todo lo de su era y de las
anteriores; no hay escuelas ni reparto por orden político.

Las tres tecnologías nuevas van **al final** de `Simulacion.tecnologias`,
después de «guiado de precisión», en ese orden (la investigación es una fila:
se compra la siguiente cuando se junta su coste). Medido con la primera
versión (§9.1): la era 2 llega en mediana entre el día 105 y el 143, la 3
entre el 187 y el 238 y la 4 entre el 302 y el 373; el día 500 están en la
era 4 entre el 85 y el 100 % de las naciones.

Hoy el dinero del trabajo se multiplica por `1 + 0,15 × tecnologías`
(`trabajo.tecnologia`). **Decidido (P7): las tres tecnologías de era no
cuentan** para ese multiplicador; solo cuentan las siete de hoy. (Si
contaran, el tesoro del día 500 casi se triplicaría: medido, §9.)

Una nación nace con modelos de la era 1: sus tanques iniciales son T-55 y sus
lanzacohetes iniciales, Scud-B.

### 3.5 Modelos en el estado y en la producción

1. Cada unidad de vehículo es de un modelo. Se guarda como en
   `diseno-de-armamento.md` §3.3: `tanquesPor[modelo]` y `lanzacohetesPor[modelo]`
   junto al total, en sitios, grupos, taller y cola de fábrica, con la
   invariante `tanques == Σ tanquesPor`.
2. **Producir.** La orden `producir` (economía cerrada) lleva además
   `modelo`. Se rechaza con el motivo nuevo `era` si la nación no tiene la
   tecnología de su era. Coste y días, los del modelo (F6).
3. **Tope por nivel sin cambios:** cuenta unidades, de cualquier modelo.
   Tener modelos mejores es la forma de ser más fuerte con el mismo tope.
4. **Taller:** cada vehículo se repara con el ritmo y el coste de su modelo (F8).
5. **Munición:** una sola munición de lanzacohetes, la de hoy (`misiles`, lote
   de 10 por 12 dinero, 1 metal y 1 petróleo). Cada modelo gasta al día lo que
   dice F11 y cada proyectil que lanza en la escena descuenta `porDisparo`
   misiles (puede ser fracción: el grupo acumula el resto). Los obuses no
   cambian: 17 por día y uno por disparo para todos los tanques.
6. **Un grupo con modelos distintos** va a la velocidad del más lento.
7. **Poder** de cada unidad: F9, la misma cuenta de hoy con la vida y el golpe
   del modelo.

### 3.6 En la batalla

**Simulada.** Cada modelo aporta su golpe y su vida por separado (hoy la
simulación usa un solo peso: hace falta separarlos, como ya pide
`diseno-de-armamento.md` §3.4). Todo lo demás (F8 de la economía, munición a
medias, retirada) no cambia.

**Escena 3D, tanques.** Aguanta `3 × vida / 9` impactos; cada impacto suyo
quita `golpe / 9`; velocidad `3,2 × velocidad` m/s (con orden, `6 ×`). Alcance
2,1 km, cadencia y puntería iguales para todos: el alcance eficaz y la cadencia
reales no se recogieron (§3.1).

**Escena 3D, lanzacohetes.** Cada salva lanza sus proyectiles reales (40 del
BM-21, 6 del M142 HIMARS, 1 del Scud-B); el daño por impacto sigue siendo 2 al 60 % de lo que caiga
dentro de su **radio** (F10), y el proyectil cae con una **dispersión de
juego** calculada para que una salva haga de media lo que dice su golpe
(F11b). Alcance en la escena por F12. Si una salva tiene muchos proyectiles, la
vista puede dibujar menos y repartir el daño entre ellos (tope visual a decidir
por Valeria y Camila; no cambia la cuenta).

### 3.7 Convivencia con el diseño de armamento

`diseno-de-armamento.md` (aprobado en idea el 2026-09-26) hace que NPC y
jugador diseñen sus armas con un kit de piezas, con estilos que se heredan,
diseños secretos y nombres de familia inventados. **Decidido (P5):** el
catálogo es la base y el kit deriva variantes secretas. El kit llega **más
adelante**: la primera versión solo trae los modelos del catálogo. Encaje
previsto:

1. **Los modelos del catálogo son los diseños base.** Toda nación los tiene a
   mano según su era; no hace falta diseñarlos ni son secretos (son públicos en
   el mundo real).
2. **Una variante** es un modelo base con piezas del kit cambiadas. Las piezas
   pasan de ser sumandos a ser **modificadores** sobre la base (por ejemplo,
   casco pesado: vida × 1,15, velocidad × 0,9, consumo × 1,2, metal × 1,2;
   cifras por medir). La variante recibe el nombre de familia inventado de
   §3.7 de ese documento («Lince M2») y su ficha dice «base: T-72B».
3. **El secreto y la copia siguen igual para las variantes**: solo se copia lo
   que se ha visto. Los modelos base no cuentan como secretos.
4. **El «modelo inicial» de cada escuela** deja de sortearse entre
   combinaciones del kit: es el modelo de era 1 que mejor puntúa con el gusto
   de la nación (F11 de ese documento, con las cifras de §4 de este).

### 3.8 Qué se ve en el Arsenal

- **Tarjeta:** nombre del modelo, era, miniatura, existencias y poder.
- **Categorías:** los tanques en «Blindados»; el BM-21 (saturación) en
  «Artillería»; el Scud-B y el M142 HIMARS (balístico y guiado) en «Misiles»,
  que hoy sale vacía. Si entra la reserva: M270, TOS-1 y Smerch en
  «Artillería»; Tochka e Iskander en «Misiles».
- **Detalle, dos bloques.** «Ficha real»: las columnas de §3.1 o §3.2, con
  «no recogido» donde falte. «En el juego»: vida, golpe, velocidad, consumo,
  coste, días, sueldo y, para lanzacohetes, misiles por día, proyectiles por
  salva, radio y alcance en la escena.
- **Sin país de origen.** Las naciones del juego son ficticias: la ficha no
  nombra países, ejércitos ni fabricantes reales.
- **Bloqueado:** los modelos de una era que no se tiene salen en gris con
  «Requiere: control de tiro digital».

### 3.9 Nombres

**Decidido (P1): solo la designación.** Los siete nombres del juego son
«T-55», «T-72B», «M1A1», «K2», «Scud-B», «BM-21» y «M142 HIMARS». Sin apodos
comerciales («Abrams», «Grad», «Black Panther»…) ni nombres de personas.

1. **Un único archivo de datos** guarda todos los nombres de armas reales.
   Ningún otro archivo (interfaz, noticias, avisos, batalla, guardado) escribe
   un nombre a mano: todos lo leen de ahí.
2. **El guardado y la red usan una clave interna** (`t55`, `t72b`, `m1a1`,
   `k2`, `scudb`, `bm21`, `himars`), nunca el nombre visible. Así, cambiar un
   nombre en el archivo de datos no rompe partidas ni la red.
3. **Motivo:** las designaciones y los apodos pueden ser marcas registradas si
   el juego se vende. Antes de vender, el dueño consultará a un abogado; si
   hace falta cambiar un nombre, solo cambia ese archivo.
4. **Variantes** (cuando llegue el kit): siguen con los nombres de familia
   inventados de `diseno-de-armamento.md` §3.7; la regla de ese documento
   («ningún nombre coincide con un arma real») se aplica a ellas, no a los
   modelos base del catálogo.
5. La ficha no nombra países, ejércitos ni fabricantes reales (§3.8).

### 3.10 Modelos 3D

**Decidido (P8):** los tanques son **variantes del Synty**
(`SK_Veh_Tank_01`) que se distingan claramente entre sí por torreta, cañón,
blindaje reactivo y faldones; el BM-21 y el M142 HIMARS tienen **modelos
nuevos**; más adelante, modelos propios para otros. **Decidido (P6):** el
camión de hoy (`SK_Veh_ScudTruck_01`) es el Scud-B real.

Longitudes públicas para escalar (cañón adelante / casco): T-55 9,00 m / no
recogido; M60 9,31 / 6,95; Leopard 1 9,54 (con el cañón atrás, 8,29); T-72 9,73 /
6,67–6,86; M1 9,77 / 7,93; Leopard 2A6 10,97 / no recogido; Merkava IV 9,04 /
7,60; Type 99 11 / 7,6; K2 10,8 / 7,5; Type 10 9,485 (total); T-14 10,7
(total). Lanzadores: BM-21 7,35 m; M270 6,97; M142 HIMARS 6,94; TOS-1 9,5; Smerch 12.

Orden de trabajo para Camila:

1. **Nada que modelar:** el tanque de hoy es el T-72B y el camión, el
   Scud-B. Solo cambia el nombre.
2. **Tres variantes del Synty** que se lean distintas a la distancia de la
   escena. Qué cambia en cada una (guía de silueta, no dato real salvo las
   longitudes de arriba):

   | Modelo | Torreta | Cañón | Blindaje reactivo | Faldones | Longitud total real |
   |---|---|---|---|---|---|
   | T-55 | redonda y baja, más pequeña | corto y fino | no | no | 9,00 m |
   | T-72B (el Synty de hoy) | la de hoy | el de hoy | bloques en torreta y frente del casco | los de hoy | 9,73 m |
   | M1A1 | angulosa, plana y ancha | largo | no | anchos y lisos | 9,77 m |
   | K2 | angulosa, alta atrás | el más largo | módulos en los costados de la torreta | anchos, con módulos | 10,8 m |

   El Synty mide 7,4 m de largo total; escalarlo a 9–11 m con cañón es cosa de
   probar en Blender. Si la escala real hace que no quepan en la escena,
   manda la legibilidad.
3. **BM-21:** modelo nuevo (camión 6×6 con el paquete de 40 tubos, 7,35 m).
4. **M142 HIMARS:** modelo nuevo (camión con un contenedor de 6, 6,94 m).
5. El resto (reserva), cuando el dueño quiera más variedad.

## 4. Fórmulas

Referencias: T-72B (44,5 t, 125 mm, 60 km/h, 840 hp, 3 tripulantes, era 2) y
Scud-B (37,4 t, 525 hp del motor D-12A-525A, 7 tripulantes, era 1, ojiva de
juego 900 kg, CEP 450 m). La potencia del motor del Scud-B está deducida del
nombre del motor, que es el mismo que la ficha del Smerch da con 525 hp.

**Decidido (P4):** proporciones reales suavizadas, `α = 0,5` (tanques) y
`β = 1/3` (lanzacohetes). Las fórmulas valen para todo el catálogo; los
ejemplos usan los modelos de la primera versión.

### F1. Era y factor de era

`era = 1` si año ≤ 1968; `2` si 1969–1978; `3` si 1979–1999; `4` si ≥ 2000.
`k(era) = 0,75 / 1 / 1,2 / 1,35`. El factor **no es un dato real**: resume lo
que no está en las fichas (blindaje compuesto, control de tiro, munición).
Ejemplo: M1A1 (1980) → era 3, k = 1,2.

### F2. Vida de un tanque

`vida = 9 × (masa / 44,5 × k / 1)^α`, con `α = 0,5`. Rango en la primera
versión 7,0 (T-55) a 11,7 (K2); con la reserva, hasta 11,9 (Merkava IV). Ejemplo: M1A1, 57 t, era 3: 9 × (1,281 × 1,2)^0,5 = 9 × 1,240 =
11,2.

### F3. Golpe de un tanque

`golpe = 9 × ((calibre / 125)² × k)^α`. Rango en la primera versión 6,2
(T-55) a 10,0 (K2); con la reserva, hasta 10,5 (T-14 y Type 99A). Ejemplo: T-55, 100 mm, era 1: 9 × (0,64 × 0,75)^0,5 = 9 × 0,693 = 6,2.
El calibre al cuadrado es una aproximación del estudio a la energía del
disparo, no un dato de penetración.

### F4. Velocidad

`velocidad = clamp(vCarretera / vRef; 0,75; 1,3)`, con `vRef` = la velocidad
del modelo de referencia de su tipo: **60 km/h (T-72B) para los tanques y
45 km/h (Scud-B, ficha del R-17) para los lanzacohetes**. En el mapa, un grupo
con vehículos va a 9 000 × la velocidad de su modelo más lento (px/día); en la
escena, 3,2 m/s × velocidad (6 m/s × velocidad con orden). Ejemplos: K2,
70 km/h: 70 / 60 = 1,17 → 10 500 px/día y 3,73 m/s. BM-21, 75 km/h: 75 / 45 =
1,67 → tope 1,3. Scud-B: 45 / 45 = 1, el camión de hoy va como hoy.

**Cambio del 2026-09-30 (Andrés, revisado por Lucía).** La primera versión de
este documento medía también los lanzacohetes contra 60 km/h, y eso dejaba al
Scud-B en 0,75: el camión de hoy iría más lento que hoy y el criterio A1
(«hoy intacto») no se cumpliría. El código mide contra el Scud-B
(`factoresLanza` en `mundo/simulacion/armamento.lua`). Estoy de acuerdo: A1
manda. Consecuencias que hay que saber:

- **Todos los lanzacohetes con velocidad recogida tocan el tope de 1,3**
  (BM-21 1,67, M270 1,43, TOS-1 y Smerch 1,33, HIMARS 2,09 antes del tope). En
  velocidad no se distinguen entre sí; solo el Scud-B va más lento.
- **Las dos escalas no son la misma.** Un Scud-B (45 km/h) vale 1, igual que un
  T-72B (60 km/h), y más que un T-55 (51 km/h, 0,85). En un grupo mixto de T-55
  y Scud-B marca el paso el T-55. Es el precio de no mover el camión de hoy.
- Si el dueño prefiere que los lanzacohetes se distingan en velocidad, la
  perilla es el tope de velocidad **solo para lanzacohetes** (por ejemplo
  0,75–1,7): no toca el Scud-B ni a los tanques. Sin medir.

### F5. Consumo de petróleo

`consumo = potencia / 840` (tanques) o `potencia / 525` (lanzacohetes);
petróleo al día parado = `0,01 × consumo`, en marcha o en batalla = `0,1 ×
consumo` (lanzacohetes `0,15 ×`). Rango tanques en la primera versión 0,63
(T-55) a 1,79 (M1A1 y K2); con la reserva, hasta 1,84 (Leclerc).
Ejemplo: 20 M1A1 en un viaje de 5 días: 20 × 0,179 × 5 = 17,9 de petróleo
(con T-72B, 10).

### F6. Coste y días de fábrica

Tanque: `dinero = 30 × (vida + golpe) / 18`; `metal = 3 × masa / 44,5`;
`petróleo = 1`; `días = max(2; redondeo(4 × dinero / 30))`.
Lanzacohetes: `dinero = peso` (F11); `metal = 6 × clamp(masa / 37,4; 0,4; 1,5)`;
`petróleo = 2`; `días = max(3; redondeo(6 × dinero / 40))`.
Ejemplo: K2 (vida 11,73, golpe 10,04 sin redondear): 30 × 21,77 / 18 = 36,3
dinero; 3 × 56 / 44,5 = 3,8 metal; redondeo(4 × 36,3 / 30) = 5 días. El
precio real en dólares **no entra** (decidido en P4: sin la opción C).

### F7. Sueldo

`sueldo = 0,15 × tripulación / 3` (tanques) y `0,2 × tripulación / 7`
(lanzacohetes). Ejemplo: M1A1, 4 tripulantes: 0,20 al día; BM-21, 3:
0,086. Sin dato de tripulación, el de la referencia.

### F8. Taller

Puntos de daño al día y por nivel: `0,5 × 9 / vida` (tanques), `0,4 × 40 /
vida` (lanzacohetes). Coste de reparar daño 1: tanques `12 × dinero / 30` +
`2 × metal / 3`; lanzacohetes `16 × dinero / 40` + `3 × metal / 6`. Ejemplo:
M1A1 (vida 11,2): 0,40 puntos al día por nivel y 13,7 dinero + 2,6 metal.

### F9. Poder

`poder = 5,5 × (vida + golpe) / 2`. Tanques de la primera versión 36,4
(T-55) a 59,9 (K2); poder entre dinero = 1,65 para todos. Lanzacohetes 211
(BM-21) a 413 (M142 HIMARS); poder entre dinero = 5,5 para todos.

### F10. Radio de daño y precisión de un lanzacohetes

- Ojiva: la pública; si no lo es, estimada desde el BM-21: `20 kg × (calibre /
  122)³` (marcado «estimada»). Scud-B: 900 kg de juego (ver §3.2).
- Radio de daño en la escena: `r = 18 m × (ojiva / 900)^(1/3)` (el radio de
  una explosión crece con la raíz cúbica de su carga: aproximación del
  estudio, sin fuente citada aquí).
- CEP en la escena: `clamp(CEP real / 10; 2; 90)` m; sin guiar o sin dato,
  62 m (la dispersión de hoy a 2,5 km).
- Probabilidad de que un proyectil caiga dentro del radio (reparto circular
  normal, definición del CEP): `P = 1 − 2^(−(r / CEP)²)`.
- Efecto de una salva: `E = proyectiles × P`.

Ejemplo: M142 HIMARS, cohete M31 de 91 kg, 6 por salva, CEP provisional 50 m
(§ tabla): r = 18 × 0,101^(1/3) = 8,4 m; CEP 5 m; P = 1 − 2^(−2,82) = 0,86;
E = 6 × 0,86 = 5,15. Scud-B: r = 18, CEP 45, P = 0,105, E = 0,105.

### F11. Golpe, vida, munición y dispersión de juego de un lanzacohetes

- `golpe = 40 × clamp((E / E_Scud)^β; 0,75; 3)`, con `β = 1/3`.
- `vida = 40 × (masa / 37,4)^(1/3)` (sin masa, 40).
- `peso` en la simulación de hoy (un solo número) `= (vida + golpe) / 2`.
- Misiles por día de batalla: `porDia = 7 × golpe / 40`.
- Misiles por proyectil en la escena: `porDisparo = golpe / (40 × proyectiles)`
  (a unas 7 salvas por día de batalla, da `porDia`).
- **F11b, dispersión de juego:** la escena usa el CEP que hace que una salva
  valga su golpe: `CEP_juego = r / √(−log₂(1 − E_Scud × golpe / 40 /
  proyectiles))`. Así la escena y la batalla simulada dan lo mismo, el daño
  por impacto es 2 para todos y el orden de precisión se conserva.

Ejemplo: BM-21: E = 40 × 0,0046 = 0,184; E / E_Scud = 1,76; golpe = 40 ×
1,76^(1/3) = 40 × 1,21 = 48,3; vida = 40 × (13,71 / 37,4)^(1/3) = 28,6;
porDia = 8,4; porDisparo = 48,3 / (40 × 40) = 0,030; CEP de juego 74,8 m.

### F12. Alcance en la escena

`alcance = clamp(2,1 + 0,9 × log₁₀(alcance real en km / 3); 1,5; 4,0)` km;
mínimo 0,5 km para todos (como hoy). Referencias: 3 km reales → 2,1 km, lo
mismo que un tanque; 500 km o más → 4,0. Ejemplo: BM-21, 20 km: 2,1 +
0,9 × 0,824 = 2,84 km.

### Resultado: tanques en el juego

| Modelo | Era | Vida | Golpe | Poder | Velocidad | Dinero / metal / petróleo | Días | Sueldo | Petróleo parado / en marcha | Taller (puntos/día y nivel) | Reparar daño 1 | Impactos que aguanta en 3D | Daño por impacto en 3D |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **T-55** | 1 | 7,0 | 6,2 | 36,4 | 0,85 | 22,1 / 2,4 / 1 | 3 | 0,20 | 0,006 / 0,063 | 0,64 | 8,8 + 1,6 | 2,3 | 0,69 |
| M60 (reserva) | 1 | 8,1 | 6,5 | 40,2 | 0,80 | 24,4 / 3,2 / 1 | 3 | 0,20 | 0,009 / 0,089 | 0,56 | 9,7 + 2,1 | 2,7 | 0,73 |
| Leopard 1 (reserva) | 1 | 7,6 | 6,5 | 38,9 | 1,08 | 23,6 / 2,8 / 1 | 3 | 0,20 | 0,010 / 0,098 | 0,59 | 9,4 + 1,9 | 2,5 | 0,73 |
| **T-72B** | 2 | **9,0** | **9,0** | **49,5** | **1,00** | **30 / 3 / 1** | **4** | **0,15** | **0,010 / 0,100** | **0,50** | **12 + 2** | **3,0** | **1,00** |
| T-80U (reserva) | 2 | 9,2 | 9,0 | 49,9 | 1,17 | 30,3 / 3,1 / 1 | 4 | 0,15 | 0,015 / 0,149 | 0,49 | 12,1 + 2,1 | 3,1 | 1,00 |
| **M1A1** | 3 | 11,2 | 9,5 | 56,7 | 1,20 | 34,4 / 3,8 / 1 | 5 | 0,20 | 0,018 / 0,179 | 0,40 | 13,7 + 2,6 | 3,7 | 1,05 |
| Leopard 2A6 (reserva) | 3 | 11,7 | 9,5 | 58,1 | 1,17 | 35,2 / 4,2 / 1 | 5 | 0,20 | 0,018 / 0,179 | 0,39 | 14,1 + 2,8 | 3,9 | 1,05 |
| Merkava IV (reserva) | 3 | 11,9 | 9,5 | 58,8 | 1,07 | 35,6 / 4,4 / 1 | 5 | 0,20 | 0,018 / 0,179 | 0,38 | 14,3 + 2,9 | 4,0 | 1,05 |
| Leclerc (reserva) | 3 | 11,1 | 9,5 | 56,5 | 1,18 | 34,3 / 3,8 / 1 | 5 | 0,15 | 0,018 / 0,184 | 0,41 | 13,7 + 2,5 | 3,7 | 1,05 |
| T-90A (reserva) | 3 | 10,1 | 9,9 | 54,8 | 1,00 | 33,2 / 3,1 / 1 | 4 | 0,15 | 0,012 / 0,119 | 0,45 | 13,3 + 2,1 | 3,4 | 1,10 |
| Challenger 2 (reserva) | 3 | 11,8 | 9,5 | 58,5 | 0,98 | 35,5 / 4,3 / 1 | 5 | 0,20 | 0,014 / 0,143 | 0,38 | 14,2 + 2,9 | 3,9 | 1,05 |
| Type 99A (reserva) | 4 | 11,6 | 10,5 | 60,7 | 1,27 | 36,8 / 3,7 / 1 | 5 | 0,15 | 0,018 / 0,179 | 0,39 | 14,7 + 2,5 | 3,9 | 1,16 |
| Type 10 (reserva) | 4 | 10,4 | 10,0 | 56,2 | 1,17 | 34,1 / 3,0 / 1 | 5 | 0,15 | 0,014 / 0,143 | 0,43 | 13,6 + 2,0 | 3,5 | 1,12 |
| **K2** | 4 | 11,7 | 10,0 | 59,9 | 1,17 | 36,3 / 3,8 / 1 | 5 | 0,15 | 0,018 / 0,179 | 0,38 | 14,5 + 2,5 | 3,9 | 1,12 |
| T-14 (reserva) | 4 | 11,6 | 10,5 | 60,7 | 1,29 | 36,8 / 3,7 / 1 | 5 | 0,15 | 0,018 / 0,179 | 0,39 | 14,7 + 2,5 | 3,9 | 1,16 |

En negrita, los de la primera versión; la fila entera en negrita es la
referencia (las cifras de hoy).

### Resultado: lanzacohetes en el juego

| Modelo | Era | Golpe | Vida | Poder | Velocidad | Dinero / metal / petróleo | Días | Sueldo | Misiles por día | Proyectiles por salva | Radio (m) | CEP real / 10 (m) | CEP de juego F11b (m) | Misiles por proyectil | Alcance en 3D (km) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Scud-B** | 1 | **40** | **40** | **220** | **1,00** | **40 / 6 / 2** | **6** | **0,20** | **7** | 1 | 18,0 | 45 | 45,0 | 1,00 | 3,90 |
| **BM-21** | 1 | 48,3 | 28,6 | 211,4 | 1,30 | 38,4 / 2,4 / 2 | 6 | 0,086 | 8,4 | 40 | 5,1 | sin guiar | 74,8 | 0,030 | 2,84 |
| Tochka (reserva) | 2 | 65,0 | 40 (masa no recogida) | 288,9 | 1 (no recogida) | 52,5 / 6 / 2 | 8 | 0,086 | 11,4 | 1 | 14,0 | 15 | 26,9 | 1,63 | 3,33 |
| M270 (reserva) | 3 | 48,8 | 34,5 | 229,1 | 1,30 | 41,6 / 3,9 / 2 | 6 | 0,086 | 8,5 | 12 | 9,4 (ojiva estimada) | sin guiar | 75,7 | 0,10 | 3,03 |
| TOS-1 (reserva) | 3 | 64,8 | 42,6 | 295,6 | 1,30 | 53,7 / 7,3 / 2 | 8 | 0,086 | 11,3 | 30 | 9,1 (estimada) | sin guiar | 100,7 | 0,054 | 2,10 |
| Smerch (reserva) | 3 | 58,6 | 42,1 | 277,1 | 1,30 | 50,4 / 7,0 / 2 | 8 | 0,086 | 10,3 | 12 | 12,4 (estimada) | sin guiar | 91,2 | 0,12 | 3,43 |
| **M142 HIMARS** | 4 | 120 (tope ×3) | 30,3 | 413,3 | 1,30 | 75,1 / 2,6 / 2 | 11 | 0,086 | 21,0 | 6 | 8,4 | 5 (provisional) | 30,1 | 0,50 | 3,44 |
| Iskander (reserva) | 4 | 84,8 | 40 (no recogida) | 343,2 | 1 (no recogida) | 62,4 / 6 / 2 | 9 | 0,20 (no recogida) | 14,8 | 1 | 15,6 | 2 | 25,9 | 2,12 | 4,00 |

En negrita, los de la primera versión; el Scud-B es la referencia (cifras
de hoy en negrita). La velocidad va contra el Scud-B (45 km/h, F4); la del
Scud-B, el BM-21 y el M142 HIMARS es la que da el código (1, 1,3 y 1,3). El CEP del M142 HIMARS (50 m reales, 5 m en la escena) es
**provisional**: el del cohete M31 no se recogió. Con ese valor llega al tope
de ×3 (ver P9, §11). El
«Poder» y el «Dinero» usan el peso de hoy, `(vida + golpe) / 2`.

## 5. Casos límite

- **Catálogo apagado** (perilla `catalogo = false`): todos los tanques son
  T-72B y todos los lanzacohetes Scud-B, sin tecnologías nuevas; el estado es
  idéntico campo a campo al de hoy.
- **Partida guardada anterior:** sus tanques pasan a T-72B y sus lanzacohetes
  a Scud-B (mismas cifras que hoy: nada cambia de golpe) y sus naciones tienen
  la era que les dé su tecnología.
- **Nación sin la era de un modelo:** `producir` lo rechaza con `era`. Las
  unidades que ya tenga de ese modelo (capturadas o de antes) siguen, se
  reparan y pelean.
- **Ciudad cedida o conquistada con modelos de una era que el nuevo dueño no
  tiene:** los usa y los repara, no los fabrica.
- **Modelo obsoleto:** se sigue pudiendo fabricar (el T-55 es barato y bebe
  poco). Nada se retira solo.
- **Grupo mixto:** velocidad del más lento; cada modelo recibe su parte de
  daño en orden de id (como `diseno-de-armamento.md` §5).
- **Sin petróleo:** como hoy (media velocidad, no salen de casa); los modelos
  que más gastan se quedan antes.
- **`porDisparo` con fracción:** el grupo lleva un resto de misiles; si no
  llega a lo que pide un proyectil, ese proyectil no sale.
- **Eras 2 y 3 sin lanzador nuevo** (primera versión): la nación sigue
  fabricando Scud-B y BM-21 hasta la era 4. No es un fallo.
- **Dato real que falta** (en la primera versión, solo el CEP del cohete del
  M142 HIMARS): se usa el provisional de la tabla y la ficha dice «no
  recogido». En la reserva faltan además masa, potencia, velocidad o
  tripulación de Tochka e Iskander: la fórmula usa el de la referencia.
- **Golpe de un lanzacohetes fuera de sus límites** (por encima de ×3 o por
  debajo de ×0,75): se recorta; hoy solo el M142 HIMARS toca el tope (P9).
- **Nombre cambiado en el archivo de datos** (por ejemplo, tras la consulta
  legal): las partidas y la red no cambian, porque guardan la clave interna
  (§3.9).
- **Nombre que falta en el archivo de datos** para una clave: la interfaz
  muestra la clave interna tal cual; una prueba de datos lo detecta antes
  (A9).

## 6. Dependencias

**Este documento depende de:**

- `economia.md`: orden `producir`, tope por nivel, munición (`porDia`,
  `porDisparo`, lotes), sueldos, combustible, taller.
- `diseno-de-armamento.md`: modelos por unidad (`tanquesPor`), vida y golpe
  separados, variantes, secreto y nombres de familia.
- `instalaciones-y-economia.md`: la fila de tecnologías y el dinero del
  trabajo.
- `ejercitos-en-el-mapa.md`: poder (F1, F2) y velocidad de los grupos.
- `retirada-y-recuperacion.md`: taller y ritmo de reparación.
- `recoleccion-y-batallas.md`: la escena 3D y la batalla simulada.

**Dependen de este documento** (y lo nombran):

- `diseno-de-armamento.md`: sus modelos base y el modelo inicial de cada
  escuela salen de aquí.
- `economia.md`: el coste, el consumo y la vida de cada modelo salen de F2 a
  F8.
- `interfaz-militar.md`: el Arsenal enseña la ficha real y la de juego (§3.8).
- Arte (Camila, `tools/blender/`): variantes y modelos de §3.10.
- `escala-del-mundo.md`: el guardado por modelo (`tanquesPor`,
  `lanzacohetesPor`) entra en la meta de unos 18 KB por nación (decisión 13
  de ese documento).

## 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `catalogo` | sí | sí / no | No: el mundo de hoy |
| `α` (tanques) | 0,5 (decidido, P4) | 0,3–1 | Más alto: más diferencia entre eras (1 = proporción real sin comprimir; medido estable, §9) |
| `β` (lanzacohetes) | 1/3 (decidido, P4) | 0,25–0,5 | Más alto: los guiados se separan más de los de saturación |
| `limiteLanza` | 0,75–3 | 0,5–4 | Techo del golpe de un lanzacohetes (hoy lo toca el M142 HIMARS). Con tope ×2, la mediana del tesoro del día 500 pasa de 117–678 a 314–805 (§9.1, P9) |
| `k(era)` | 0,75 / 1 / 1,2 / 1,35 | ±0,15 cada uno | Cuánto pesa la era frente a la masa y el calibre |
| Costes de las tecnologías nuevas | 1 500 / 4 500 / 9 000 | ×0,5–×2 | Día de llegada de cada era (medido con los de la tabla) |
| `eraCuentaEnTrabajo` | no (decidido, P7) | sí / no | Sí: el tesoro del día 500 sube de 237–805 a 686–1 975 (medido con el catálogo completo) |
| Modelos activos | los 7 de la primera versión (P2) | 7 a 23 | Más modelos: más variedad; cifras de la reserva en §4 |
| Referencia de velocidad | 60 km/h (tanques, T-72B) y 45 km/h (lanzacohetes, Scud-B) | fija | Cambiarla mueve a todos los de su tipo y rompe A1 |
| Tope de velocidad | 0,75–1,3 | 0,6–1,5 | Cuánto antes llegan los rápidos. Hoy lo tocan todos los lanzacohetes salvo el Scud-B |
| `radioRef` | 18 m | 12–25 m | Letalidad de todos los lanzacohetes en la escena |
| `cepEscala` | 1/10 | 1/20–1/5 | Solo cambia el «CEP real / 10»; el de juego (F11b) no se mueve |
| Tope visual de proyectiles por salva | sin fijar | 8–40 | Rendimiento de la escena; no cambia la cuenta |

## 8. Criterios de aceptación

Con `tools/auditar_economia_nationsrts.lua`, 500 días, semillas 1, 7, 42 y 1234:

- **A1. Hoy intacto.** Con el catálogo apagado, o con todo T-72B y Scud-B, el
  estado final es idéntico al de hoy.
- **A2. Referencias exactas.** Una prueba de datos da, para T-72B y Scud-B,
  las constantes de hoy (§0).
- **A3. Mismo valor por moneda.** Poder / dinero = 1,65 ± 2 % en todos los
  tanques y 5,5 ± 2 % en todos los lanzacohetes.
- **A4. Economía estable.** Todas las naciones vivas; invariante de
  conservación cumplido todos los días; mediana del tesoro el día 500 entre
  200 y 1 000 en cada semilla (hoy 269–776); metal por debajo de 5 en menos
  del 8 % de los días-nación (hoy 4,6–6,8 %); sin combustible, menos del
  1,5 % (hoy 0,2–0,9 %); hambre, menos del 1 %.
- **A5. Eras.** Día mediano de la era 2 entre 90 y 160, de la 3 entre 170 y
  250, de la 4 entre 280 y 400; al menos el 80 % de las naciones en la era 4
  el día 500.
- **A6. Batallas.** Entre 420 y 560 batallas en las 4 semillas (hoy 472).
- **A7. 3D = simulada por modelo.** 50 batallas en la escena sin jugador y 50
  simuladas con 10 lanzacohetes de un modelo contra 10 tanques: daño medio a
  menos del 20 % entre sí, para cada lanzacohetes. **Sin medir** (necesita la
  escena).
- **A8. Determinismo.** Dos corridas iguales y guardar/cargar a mitad dan el
  mismo estado; el tiempo por día sube como mucho un 10 %.
- **A9. Nombres en un solo sitio.** Una prueba recorre el código de
  `NationsRTS/` y no encuentra ninguno de los siete nombres visibles fuera del
  archivo de datos (salvo comentarios y pruebas); cada clave interna tiene
  nombre; el guardado no contiene ningún nombre visible, solo claves.
- **A10. Guardado.** Con los modelos por unidad, el guardado se queda en unos
  18 KB por nación completa (`escala-del-mundo.md`, decisión 13).

**Estado con la primera versión (§9.1):** A4 **no se cumple** en dos de las
cuatro semillas (mediana del tesoro 180 y 117, por debajo de 200); A5 y A6 sí.
Ver P9.

## 9. Mediciones

Arnés: `tools/medir_catalogo_armamento_nationsrts.lua` (nuevo, de este
documento). **Obsoleto desde que el catálogo está programado (f01cacd):** hoy
el auditor (`tools/auditar_economia_nationsrts.lua`) mide el catálogo real y,
con `CATALOGO=0`, el mundo de antes. Las cifras de esta sección son las de la
aproximación y no se han vuelto a medir con el auditor. Monta las cifras de §4 encima de la simulación real **solo en su
proceso** y corre el auditor de la economía. La simulación de hoy tiene un
solo peso por tipo, así que el arnés usa `(vida + golpe) / 2`; los pesos son
globales, así que en «progresión» cada día se pone la media de la serie de
todas las naciones (su era), sin el retraso de las unidades viejas que
conviven. Es una aproximación: mide la economía y el tamaño de las guerras,
no quién gana a quién.

Escenarios (500 días, 4 semillas; rango entre semillas de la mediana por
nación del día 500, o del total):

| Medida | Hoy | Era 1 siempre (T-55 + BM-21) | Máximo desde el día 1 (T-14 + HIMARS) | Progresión, eras sin subir el dinero | Progresión, eras suben el dinero | Progresión con α = β = 1 | Máximo con α = β = 1 |
|---|---|---|---|---|---|---|---|
| Naciones vivas | todas | todas | todas | todas | todas | todas | todas |
| Invariante de conservación | se cumple | se cumple | se cumple | se cumple | se cumple | se cumple | se cumple |
| Tesoro | 269–776 | 474–961 | 220–813 | 237–805 | **686–1 975** | 252–687 | 140–814 |
| Metal | 135–231 | 105–193 | 121–155 | 121–202 | 79–175 | 139–184 | 108–193 |
| Petróleo | 128–162 | 126–174 | 161–197 | 160–204 | 161–220 | 194–246 | 173–216 |
| Soldados | 3 752–4 803 | 3 260–4 633 | 3 750–4 610 | 3 774–4 390 | 3 752–4 559 | 3 752–4 498 | 3 739–4 679 |
| Tanques | 61–80 | 62–80 | 60–75 | 56–71 | 68–75 | 63–73 | 61–73 |
| Lanzacohetes | 38–42 | 38–42 | 32–36 | 31–39 | 35–42 | 30–42 | 30–37 |
| Misiles en el polvorín | 1 058–1 470 | 1 487–1 774 | 3 262–3 679 | 2 530–3 320 | 3 013–3 763 | 3 157–4 122 | 3 158–3 684 |
| Días-nación sin combustible | 0,2–0,9 % | 0,1–0,6 % | 0,4–0,8 % | 0,1–1,2 % | 0,2–1,5 % | 0,2–0,8 % | 0,5–1,2 % |
| Metal < 5 | 4,6–6,8 % | 3,6–6,0 % | 4,3–6,4 % | 4,0–7,6 % | 3,7–7,3 % | 4,2–7,1 % | 4,6–9,1 % |
| Dinero < 10 | 1,1–2,5 % | 1,1–2,2 % | 1,1–1,9 % | 1,0–2,0 % | 0,8–2,1 % | 1,1–1,6 % | 1,2–1,8 % |
| Hambre | 0,0–0,2 % | 0,1–0,2 % | 0,0–0,2 % | 0,0–0,2 % | 0,0–0,3 % | 0,0–0,1 % | 0,0–0,1 % |
| Golpe perdido por falta de munición | 15,9–25,2 % | 17,2–21,5 % | 11,1–28,9 % | 16,8–21,0 % | 14,9–23,4 % | 12,9–24,3 % | 15,2–27,3 % |
| Soldados muertos al día (todas las naciones) | 22,1–51,3 | 20,7–47,4 | 17,8–35,6 | 17,2–43,4 | 19,6–35,7 | 9,4–43,3 | 18,9–36,7 |
| Tanques fabricados al día (todas) | 2,6–2,9 | 2,6–3,0 | 2,6–3,0 | 2,6–2,8 | 2,6–3,0 | 2,4–3,0 | 2,6–2,9 |
| Misiles gastados al día (todas) | 20,0–34,8 | 18,0–41,1 | 42,4–67,1 | 32,1–57,3 | 34,2–54,1 | 18,4–70,0 | 39,8–77,9 |
| Batallas (4 semillas) | 472 | 494 | 524 | 475 | 461 | 491 | 491 |
| Vehículos por bando: mediana / p90 | 9 / 46 | 8 / 44 | 6 / 38 | 9 / 43 | 9 / 45 | 5 / 36 | 7 / 37 |
| Soldados por bando, mediana | 496 | 467 | 287 | 463 | 417 | 263 | 435 |

Días de llegada de cada era (mediana por semilla): sin subir el dinero,
era 2 en 105–143, era 3 en 187–238, era 4 en 308–365 (18 a 22 naciones de
20 a 22); subiendo el dinero, 105–143, 184–232 y 287–374.

Investigación acumulada por nación (mediana, hoy): día 100, 2 879–4 306; día
200, 6 864–9 957; día 300, 11 284–17 600; día 500, 26 324–38 028. Las siete
tecnologías de hoy (2 970 en total) se tienen entre el día 75 y el 102.

Lectura:

- **La economía aguanta en todos los casos**, también con los modelos más
  caros desde el primer día y sin comprimir las proporciones: nadie muere, la
  invariante se cumple, el metal, el petróleo y la comida no se hunden.
- **Lo que más se mueve es el polvorín de misiles** (de 1 058–1 470 a
  2 530–3 763): los lanzacohetes de era alta gastan más misiles al día y la
  NPC guarda 5 días de reserva. Los misiles gastados al día suben de 20–35 a
  32–57 (progresión).
- **Con los modelos caros hay algo menos de lanzacohetes** (31–39 frente a
  38–42): cuestan más dinero.
- **Si las eras suben el dinero del trabajo**, el tesoro del día 500 casi se
  triplica: es el único efecto grande medido, y no viene de las armas sino de
  tener diez tecnologías.
- La población (medida con `tools/medir_poblacion_nationsrts.lua`, modo
  `hoy`) no cambia de forma apreciable: ×2,65–2,85 en 500 días en los cuatro
  escenarios; muertos en combate 0,89–2,33 por nación y día.
- **Sin medir:** quién gana las guerras según su modelo (la simulación de hoy
  no distingue modelos dentro de un mismo mundo), la escena 3D (A7) y el
  retraso de las unidades viejas.

### 9.1 Primera versión (P2), medida el 2026-09-30 tras las decisiones

Mismo arnés y método, pero cada era usa solo los modelos de la primera
versión: tanques T-55 / T-72B / M1A1 / K2; lanzadores, media de Scud-B y
BM-21 en las eras 1 a 3 y M142 HIMARS solo en la era 4. Eras sin subir el
dinero del trabajo (P7). Código: HEAD d88da08 (la simulación sin cambios sin
guardar). El control «hoy» dio las mismas cifras que en §9.

| Medida (4 semillas) | Hoy | Primera versión, tope ×3 (el documento) | Primera versión, tope ×2 |
|---|---|---|---|
| Naciones vivas | todas | todas | todas |
| Invariante de conservación | se cumple | se cumple | se cumple |
| Tesoro (mediana del día 500) | 269–776 | **117–678** | 314–805 |
| Metal | 135–231 | 88–143 | 97–164 |
| Petróleo | 128–162 | 164–226 | 170–209 |
| Soldados | 3 752–4 803 | 3 398–4 455 | 3 660–4 616 |
| Tanques | 61–80 | 55–75 | 67–78 |
| Lanzacohetes | 38–42 | 30–40 | 30–42 |
| Misiles en el polvorín | 1 058–1 470 | 2 321–4 018 | 2 066–2 747 |
| Días-nación sin combustible | 0,2–0,9 % | 0,1–0,9 % | 0,4–1,0 % |
| Metal < 5 | 4,6–6,8 % | 5,0–6,6 % | 6,1–7,6 % |
| Dinero < 10 | 1,1–2,5 % | 1,1–2,1 % | 1,3–2,4 % |
| Hambre | 0,0–0,2 % | 0,0–0,1 % | 0,0–0,3 % |
| Golpe perdido por falta de munición | 15,9–25,2 % | 13,0–23,2 % | 17,0–25,4 % |
| Misiles gastados al día (todas) | 20,0–34,8 | 26,6–49,9 | 20,0–40,8 |
| Batallas (4 semillas) | 472 | 517 | 502 |
| Vehículos por bando: mediana / p90 | 9 / 46 | 9 / 38 | 8 / 39 |
| Soldados por bando, mediana | 496 | 414 | 402 |
| Era 2 / 3 / 4, día mediano | — | 105–143 / 187–238 / 302–373 | 105–143 / 187–236 / 305–371 |
| En la era 4 el día 500 | — | 81 de 85 naciones (17 de 20 a 22 de 22) | 80 de 85 |

Lectura:

- La economía aguanta: nadie muere, la invariante se cumple, el metal, el
  petróleo y la comida no se hunden.
- **El tesoro baja** con la primera versión y tope ×3: en las semillas 1 y
  1234 la mediana del día 500 queda en 180 y 117, por debajo del mínimo de A4
  (200). La causa probable es el M142 HIMARS, único lanzador de la era 4, que
  cuesta 75 de dinero y 11 días (con la media de dos lanzadores de era 4, en
  §9, el tesoro quedaba en 237–805). Con tope ×2 (golpe 80, peso 55,2) el
  tesoro vuelve a 314–805. Es **una corrida por caso**: la mediana del tesoro
  varía mucho entre semillas (p10–p90 de 9 a 5 087), así que la diferencia
  es indicio, no prueba.
- El polvorín de misiles sube a 2 321–4 018, como ya pasaba en §9.

## 10. Cambios necesarios en el código

Para Andrés (simulación):

1. `mundo/armamento.lua` (el de `diseno-de-armamento.md` §3.2) con el
   catálogo: datos reales de §3.1 y §3.2 y las fórmulas F1 a F12; prueba de
   que T-72B y Scud-B dan las constantes de hoy (A2). Solo los siete modelos
   de la primera versión activos; la reserva puede quedarse en los datos,
   desactivada.
1b. **Un único archivo de datos con los nombres visibles** (§3.9), clave
   interna → nombre; guardado y red solo con claves; prueba A9.
2. Vida y golpe separados en `vidaGrupo`, `golpeGrupo`, `golpeSitio` y
   `poderUnidad`, por modelo.
3. `tanquesPor` / `lanzacohetesPor` en sitios, grupos, taller y fábrica, con
   su invariante; migración de partidas viejas (§5).
4. Orden `producir` con `modelo`; motivo `era`; `puedeProducir` y
   `Simulacion.produccion` publican coste, días, sueldo y consumo por modelo.
5. Tres tecnologías al final de `Simulacion.tecnologias`; `trabajoCiudad` sin
   contarlas (decidido, P7).
6. `porDia` y `porDisparo` por modelo; resto fraccional por grupo.
7. NPC (`planearProduccion`): encarga el mejor modelo de su era que pueda
   pagar, salvo con escasez de petróleo (entonces el de menos consumo). Toda
   nación puede fabricar todo lo de su era (P3).
8. El kit de piezas de `diseno-de-armamento.md` queda para más adelante
   (P5): nada de variantes en esta versión.

Para Valeria (escena y vista): impactos que aguanta, daño por impacto y
velocidad por modelo; salvas con sus proyectiles, radio, CEP de juego (F11b)
y alcance (F12); tope visual por salva si hace falta; nombre del modelo en la
ficha del ejército.

Para Camila (arte): el orden de §3.10.

Para Diego y Valeria (Arsenal): la ficha doble de §3.8 y la categoría
«Misiles».

Para Elena: A1 a A8, y A7 con el arnés de batalla.

## 11. Decisiones del dueño (2026-09-30)

Sustituyen a las preguntas P1 a P8 de la primera versión de este documento.

1. **P1. DECIDIDO. Solo la designación:** «T-55», «T-72B», «M1A1», «K2»,
   «Scud-B», «BM-21», «M142 HIMARS»; sin apodos comerciales ni nombres de
   personas. Motivo: pueden ser marcas registradas si el juego se vende;
   antes de vender se consultará a un abogado. Todos los nombres en un único
   archivo de datos (§3.9).
2. **P2. DECIDIDO. Un modelo por era:** T-55, T-72B, M1A1 y K2; y Scud-B,
   BM-21 y M142 HIMARS. El resto del catálogo queda como reserva (§3.4).
3. **P3. DECIDIDO. Todas las naciones, todo lo de su era** (§3.4).
4. **P4. DECIDIDO. Proporciones suavizadas:** α = 0,5 y β = 1/3; el precio
   real en dólares no entra (§4).
5. **P5. DECIDIDO. El catálogo es la base** y el kit de piezas de
   `diseno-de-armamento.md` deriva variantes secretas, **más adelante**
   (§3.7).
6. **P6. DECIDIDO. El camión de hoy es un Scud-B real**, con las cifras de
   hoy como referencia (§3.3, §3.10).
7. **P7. DECIDIDO. Las tecnologías de era no suben el dinero del trabajo**
   (§3.4).
8. **P8. DECIDIDO. Variantes del tanque Synty que se distingan claramente**
   (torreta, cañón, blindaje reactivo, faldones); modelos nuevos para el
   BM-21 y el M142 HIMARS; más adelante, modelos propios para otros (§3.10).

### Pregunta nueva

**P9. ¿Qué hacemos con el tesoro bajo de la primera versión?** Sale de §9.1:
con el M142 HIMARS como único lanzador de era 4 y tope ×3, la mediana del
tesoro del día 500 queda por debajo de 200 en dos de cuatro semillas (180 y
117), fuera de A4.

- A. **Recomendada:** bajar `limiteLanza` a ×2 (el M142 HIMARS pasa de golpe
  120 y 75 de dinero a golpe 80 y unos 55). Medido: tesoro 314–805, A4 se
  cumple; el resto de la economía, como con ×3. Sigue siendo el lanzador más
  fuerte (el BM-21 tiene golpe 48,3).
- B. Dejar ×3 y rebajar A4 a «mediana del tesoro por encima de 100».
  Medido: 117–678.
- C. Dejar ×3 y repetir la medida con más semillas antes de decidir (una
  corrida por caso; la diferencia puede ser ruido). Sin medir.

## Fuentes

Todas consultadas el 2026-09-30 por la API pública de Wikipedia (ficha y
texto del artículo):

- Tanques (en.wikipedia.org): «T-54/T-55», «M60 tank», «Leopard 1», «T-72»,
  «T-80», «T-90», «M1 Abrams», «Leopard 2», «Challenger 2», «Merkava»,
  «Leclerc (tank)», «Type 99 tank», «K2 Black Panther», «Type 10», «T-14
  Armata».
- Lanzadores y misiles (en.wikipedia.org): «R-17 Elbrus» (misil, CEP,
  tripulación, precio y el camión MAZ-543), «Scud missile», «BM-21 Grad»,
  «OTR-21 Tochka», «M270 Multiple Launch Rocket System» (también cohetes M26,
  M31 y GMLRS), «M142 HIMARS», «TOS-1», «BM-30 Smerch», «9K720 Iskander»,
  «ATACMS», «Circular error probable» (definición del CEP y del reparto
  circular normal).
- ru.wikipedia.org, «Р-17»: requisito de diseño de al menos 900 kg de carga
  útil.
- Verificación del daño real (2026-10-01, en.wikipedia.org): «D-10 tank gun»,
  «125 mm smoothbore ammunition», «M829», «CN08 120 mm gun», «AK-74» y
  «5.45×39mm», además de los de arriba. Detalle y propuestas en
  `batalla/DANO-REAL.md` §11.
- Del proyecto: `assets/modelos3d/SYNTY.md` y `tools/blender/tanque_synty.py`
  (medidas de los modelos Synty); listado de `SIMPLE_Military_SourceFiles.zip`.

## Cómo se midió

- Estas órdenes son del arnés de la aproximación, **obsoleto** (§9). Para
  medir el catálogo programado: `luajit tools/auditar_economia_nationsrts.lua
  500 1 7 42 1234`, y con `CATALOGO=0` delante, el mundo de antes.
- `luajit tools/medir_catalogo_armamento_nationsrts.lua tabla` imprime las
  tablas de §4.
- `ESC=<escenario> luajit tools/medir_catalogo_armamento_nationsrts.lua 500 1 7
  42 1234`, con escenario `hoy`, `era1`, `maximo`, `progresion` o
  `progresionX` (perillas `ALFA_TANQUE`, `ALFA_LANZA`, `TEC2`, `TEC3`,
  `TEC4`). Con `HERR=poblacion` y `hoy` como primer argumento corre
  `tools/medir_poblacion_nationsrts.lua`.
- §9.1 (primera versión): la misma herramienta con las series de cada era
  limitadas a los siete modelos de P2 y, para el tope ×2, `C.limiteLanza =
  { 0.75, 2.0 }`, en una copia fuera del repositorio; escenario
  `progresionX`, 500 días, semillas 1, 7, 42 y 1234, sobre HEAD d88da08.
- Las cifras de §9 se tomaron sobre una copia congelada del código (HEAD
  30b2dda más los cambios sin guardar del árbol a las 15:23 del 2026-09-30),
  porque el código cambió mientras se medía. Dos corridas de `hoy` dieron el
  mismo resultado.
- El día de cada era sale de una envoltura de `avanzarDia` que apunta el
  primer día en que cada nación tiene la tecnología.

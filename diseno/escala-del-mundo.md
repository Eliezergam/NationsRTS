# Escala del mundo: naciones sin límite, niveles de detalle y servidor

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Documento de Tomás (red) para Andrés (simulación), Valeria (mundo y vista),
Lucía (diseño) y Elena (mediciones). Estado: **decidido por el dueño el
2026-09-30 (§10), sin programar**; sin preguntas abiertas. Lo marcado «hoy» es el código en HEAD c0faae7 (guardado versión 22).
Las cifras salen de dos prototipos de medición en `tools/` (ver «Cómo se
midió»).

Sale del pedido del dueño: un mundo procedural **infinito** con miles o
millones de ciudades y naciones, cada una con sus ejércitos y sistemas
(economía cerrada, munición, taller, exploradores, diplomacia, NPC que juegan
con las mismas reglas que el jugador) y, más adelante, juego en línea con
muchos jugadores.

---

## 0. Estado de hoy

El mundo **físico** ya es infinito: terreno, ciudades y yacimientos salen de
la semilla, con ids de región (`'rx,ry'`, `'y:…'`). El mundo **vivo** no:

- Al explorar un trozo, `Mundo:explorarTrozo` (mundo.lua l.226) llama a
  `registrarNacionDe` (l.163), que registra la nación de esa zona y las 8
  vecinas con `Simulacion:registrarZona` (simulacion.lua l.949). Una zona son
  4 × 4 regiones (98 304 px, unos 9,8 km de lado) y tiene como mucho una
  nación (medido: 0,84 a 0,88 naciones por zona; el resto es mar).
- Una nación registrada **se simula completa todos los días para siempre** y
  queda en el estado y en el guardado. `zonasRegistradas` nunca se olvida.
- Un día dura un minuto real a la velocidad normal (`VELOCIDADES` en main.lua
  l.91: 60 s, 20 s, 5 s o 1 s por día). `Simulacion:actualizar` (l.3795) hace
  el día entero dentro de un solo cuadro.

### Lo medido hoy

Semilla 4242, cuadrados de L × L zonas alrededor del origen, simulación real
sin LÖVE (`tools/medir_niveles_nationsrts.lua`). Días 21 a 30 (L = 5 y 10) y
21 a 25 (L = 15 y 20). Ryzen 5 5500, LuaJIT 2.1.

| Naciones | ms por día (media / peor) | ms por nación y día | Relaciones guardadas | Guardado día 1 | Guardado al final | Memoria Lua |
|---|---|---|---|---|---|---|
| 21 | 8,7 / 11,1 | 0,42 | 420 | 1,2 MB | 1,4 MB | 9 MB |
| 88 | 75,7 / 95,0 | 0,86 | 7 656 | 5,0 MB | 5,9 MB | 26 MB |
| 198 | 357 / 402 | 1,80 | 39 006 | 12,2 MB | 14,1 MB | 54 MB |
| 350 | 1 181 / 1 255 | 3,37 | 122 150 | 23,9 MB | 27,2 MB (5,6 MB con gzip) | 87 MB |

Lectura:

- **El coste crece con el cuadrado del número de naciones**: el coste por
  nación se duplica cada vez que se duplican las naciones. Se ajusta bien a
  `≈ 0,0096 × N²` ms por día. Extrapolado: 1 000 naciones, unos 10 s por
  día; 4 000, unos 150 s por día (más que el minuto que dura el día). Andrés
  mide ahora hasta 4 096 zonas con `tools/medir_escala_nationsrts.lua` (100
  días y perfilador por muestreo); sus cifras sustituyen a esta extrapolación.
- **Ya hay tirones hoy**: con 21 naciones el día cuesta 9 ms en esta medición
  (Andrés midió 25 a 29 ms más adelante en la partida, con guerras). Con 88,
  un cuadro de 76 a 95 ms cada minuto. Un jugador que explora 20 × 20 zonas
  llega a un cuadro de 1,2 s cada minuto.
- **Reparto por fase con 350 naciones** (ms por día): diplomacia 400,
  `planearRecoleccion` 260, `defenderLoSuyo` 189, `vivas` 60, `economia` 60,
  `planearAbastos` 41, `expansion` 41, `planearProduccion` 34. Las tres
  primeras son el 72 %.
- **El guardado es sobre todo lo que ya da la semilla**: con 350 naciones,
  `depositos` ocupa 15,7 MB de 27,2 (58 %; con 21 naciones, el 70 %); cada
  yacimiento registrado se guarda aunque nadie lo haya tocado. `naciones`
  ocupa 5,1 MB por las relaciones, una por cada par de naciones del mundo.
- **Crear una zona desde la semilla** (`datosZona`: ciudades y yacimientos)
  cuesta 7,6 a 12,7 ms por zona; registrarla, 0,5 a 1 ms.
- **Memoria**: 250 a 440 KB de Lua por nación completa.

### Qué lo hace cuadrático (hoy)

| Dónde | Qué recorre | Por qué pesa |
|---|---|---|
| `avanzarDia` l.3763-3769 | `diplomacia(a, b)` para **cada par** de naciones vivas | N² pares al día, cada uno con `frente` y `recursosEnDisputa` |
| `registrarZona` l.1030-1041 | Una relación con **cada** nación ya registrada | N² relaciones en memoria y en el guardado |
| recoleccionIA.lua l.92, 114, 242, 355; municion.lua l.184, 258; simulacion.lua l.897, 1460, 1970, 2873, 2974; produccion.lua l.281; diplomacia.lua l.353, 367, 457 | Todos los grupos del mundo, filtrando por nación, **por cada nación** | N naciones × G grupos, y G crece con N |
| `gruposOrdenados` l.465 | Crea una lista nueva con todos los grupos en cada llamada | Lo anterior, más basura para el recolector |
| `vivas` l.865 | Ordena todas las naciones en cada llamada | Se llama varias veces al día y dentro de otras funciones |
| `enFrontera` l.1514, `planearCampamento` l.3025, `construirBase` l.3111, taller.lua l.377 | Todas las naciones o todas las ciudades, por ciudad o por nación | N² |

---

## 1. Resumen

El mundo vivo se divide en **cuatro niveles de detalle** por zona (una
nación por zona):

| Nivel | Qué es | Coste por día | Qué se guarda |
|---|---|---|---|
| **Fondo** | Nación que nadie ha tocado. Su estado es una fórmula cerrada de (semilla, zona, día) | Nada: se calcula al preguntar (0,013 µs por consulta en el prototipo) | Nada |
| **Congelada** | Nación tocada, lejos de todo. Duerme y se pone al día al despertar con los pasos resumidos que le tocaron, guerras entre dormidas incluidas (decididas por hash) | Nada mientras duerme; al despertar, 0,1 a 0,5 µs por año de juego (prototipo) | Su estado resumido, el día en que se durmió y su foto de sueño |
| **Resumida** | Nación tocada cerca de la zona de interés. Un paso agregado cada `N` = 10 días (un año de juego, diseno/poblacion.md) con las mismas cuentas en bloque | 0,01 a 0,02 µs por nación y día en el prototipo; se planifica con 2 µs | Su estado resumido (~4 KB previstos) |
| **Completa** | Cerca de un jugador o en guerra con algo completo. La simulación de hoy, día a día | ~0,4 a 1,2 ms por nación y día (hoy con 21 naciones), si deja de ser cuadrática | Su estado completo, solo lo que difiere de la semilla |

Tres principios lo hacen posible y son a la vez lo que necesita el servidor:

1. **Localidad.** El paso de una nación lee solo lo suyo, el resumen que
   publicaron ayer sus vecinas y los mensajes dirigidos a ella. Escribe solo
   lo suyo y manda mensajes. El azar sale de un hash por (semilla, día,
   nación, qué), no de un único generador del día. Así el resultado no
   depende de cuántas naciones existan, de en qué orden se recorren ni de en
   qué máquina o hilo corren.
2. **Lo que da la semilla no se guarda ni viaja.** El guardado y la red
   llevan solo las diferencias con el fondo.
3. **Todo lo que cruza de una nación a otra es un mensaje con un día de
   retraso** (declarar la guerra, un ejército que entra en otra zona, un
   explorador que llega, una propuesta de paz). Dentro de un día nadie ve lo
   que otro hace ese mismo día.

## 2. Fantasía del jugador

- «Viajo mil kilómetros y encuentro naciones que llevan siglos viviendo: tienen
  su nivel, su ejército y sus rencillas, aunque nadie hubiera pasado antes.»
- «Lo que me contó mi explorador de un país lejano es lo que encuentro al
  llegar (con lo que haya cambiado en esos días).»
- «Un amigo y yo vemos el mismo país con el mismo presidente, las mismas
  ciudades y el mismo ejército.»
- «Dejo mi imperio y vuelvo meses después: ha seguido viviendo.»
- «El juego no da tirones cuando cambia el día.»

---

## 3. Reglas

### 3.1 Niveles de detalle

**Zona de interés.** Cada jugador tiene una: las zonas a menos de `Rc` zonas
(distancia de Chebyshev) de su cámara, de cada ciudad suya y de cada grupo
suyo. `Rc` = 3 da 7 × 7 zonas alrededor de cada punto. Alrededor, la
**penumbra**: hasta `Rr` = 8 zonas.

**Nivel de cada zona** (se decide al empezar cada día, en orden fijo de
clave de zona):

1. **Completa** si está en la zona de interés de algún jugador, o si tiene una
   batalla o un grupo propio en contacto (a menos de `alcanceAtaque`) con algo
   de una zona completa, o si un grupo de una zona completa va hacia ella.
2. **Resumida** si está tocada y en la penumbra de algún jugador, o si está en
   guerra con una zona completa o resumida.
3. **Congelada** si está tocada y no cumple nada de lo anterior.
4. **Fondo** si nunca se ha tocado.

**Tocada**: ha estado completa alguna vez. Una zona tocada no vuelve al fondo
(lo que vio un explorador o un jugador tiene que seguir ahí).

**Histéresis.** Bajar de nivel pide llevar `diasBajar` = 5 días seguidos sin
cumplir la condición del nivel de arriba, y los radios de bajar son 2 zonas
más grandes que los de subir. Subir es inmediato (al empezar el día
siguiente). Así una cámara que va y viene por un borde no hace subir y bajar
la misma zona cada día.

**Solo se baja estando quieta.** Una zona completa solo pasa a resumida si no
tiene batallas, ni grupos en choque, ni grupos camino de una zona completa.
Los recolectores en sus minas y los convoyes propios sí se pliegan (3.4).

### 3.2 Fondo: naciones intactas

Una nación intacta no tiene estado. Su situación el día `d` sale de
`Fondo.nacion(semilla, zona, d)`:

- Lo fijo, como hoy en `registrarZona`: nombre, orden, presidente y su
  carácter, ciudades y yacimientos (todo de la semilla).
- Lo que crece, con curvas cerradas calibradas con la simulación completa
  (§8): nivel de la capital, población por cohortes (diseno/poblacion.md
  F11), soldados, tanques, lanzacohetes, munición, tesoro, almacén y
  territorio (el bloque de sus ciudades y las banderas hacia sus mejores
  yacimientos, en el orden de F12 de territorio-y-capitales.md). Cada curva
  depende de la madurez `1 − exp(−d / τ)` y de factores de la nación por hash
  (riqueza de sus yacimientos, agresividad, prudencia).
- La **leyenda**: guerras entre naciones del fondo decididas por hash por par
  de zonas vecinas y época (`hash(semilla, época, zonaA, zonaB)`), con el
  resultado también cerrado (cansancio, bajas, concesiones). Cada nación
  calcula su parte solo con los hashes de sus aristas, sin mirar el estado de
  las vecinas: la cuenta no se propaga por el mapa.

No depende de quién la mire ni de cuándo: dos jugadores que llegan el mismo
día a la misma nación la encuentran igual; uno que llega 100 días después la
encuentra 100 días más vieja.

Hoy no es así: una nación nace fresca (nivel 1, lo inicial) el día en que se
registra, y sus relaciones de partida salen del orden en que se registraron
las demás (l.1030-1040). Dos jugadores que exploran distinto ven mundos
distintos.

### 3.3 Materializar: del fondo a completa

`Fondo.materializar(semilla, zona, d)` construye el estado completo de la
nación con la misma forma que usa hoy la simulación (ciudades, polvorín,
taller vacío, territorio en celdas, presidente y generales) a partir de
`Fondo.nacion`. Es la única puerta de entrada al mundo vivo: sustituye a
`registrarZona` y el informe de un explorador sobre una nación no completa se
hace con la misma función (sin guardar nada). Por eso lo que cuenta el
informe es lo que se encuentra al llegar, salvo lo que cambie por el camino.

Coste medido de la parte que existe hoy: 7,6 a 12,7 ms por zona para leer la
semilla y 0,5 a 1 ms para registrar. Se hace en el hilo de la simulación, o
repartido a una o dos zonas por cuadro, como los trozos del terreno
(`Mundo.porCuadro`).

### 3.4 Resumida y congelada

**Estado resumido** de una nación: las mismas cantidades que la completa, sin
el detalle de los grupos: por ciudad, población por cohortes, inventario
(sanos, heridos, averiados con su daño), polvorín, cola de fábrica y granero;
por nación, tesoro, almacén, afuera, cansancio, relaciones con sus vecinas y
territorio (sus celdas no cambian de forma). En lugar de los grupos:

- **Recolección**: soldados asignados a cada mina propia y lo que traen por
  día (el mismo F10/F11 de recoleccion-y-batallas.md, en media).
- **Frentes**: por cada guerra, la fuerza comprometida de cada lado (tropas y
  munición) y el sitio disputado.

**Paso resumido** cada `N` = 10 días, alineado para todo el mundo (en los días
con `dia % N == 0`): las fórmulas de la economía cerrada multiplicadas por `N`
(sueldos, comida, combustible, mantenimiento, taller por puntos), producción
hasta el tope pagando, cohortes que cumplen un año, recolección media, y los
frentes resueltos con la cuenta de la batalla simulada en bloque (el mismo
poder por unidad y el mismo gasto de munición por día, por `N` días). La IA
estratégica decide como la completa pero una vez por paso (3.6).

**Congelada** = resumida evaluada solo cuando hace falta. Guarda el estado,
el día en que se durmió y su **foto de sueño**: el resumen que publicó ese día
(poder, relaciones con sus vecinas, carácter del presidente, cansancio;
unos 200 bytes). Al despertar (un jugador se acerca, le llega un mensaje, un
explorador pide su informe, o se guarda la partida) da los pasos resumidos
que le tocaron hasta hoy.

**Guerras entre dormidas (decidido).** Las naciones dormidas sí empiezan
guerras entre ellas. En cada paso, para cada vecina:

- la guerra empieza si `hash(semilla, época, zonaA, zonaB)` cae por debajo de
  las ganas de la diplomacia de hoy (relación, poder y carácter, las mismas
  cuentas de `diplomacia`), calculadas con las **fotos de sueño** de las dos,
  no con su estado del momento;
- se libra con la cuenta en bloque de F3, también con las dos fotos, y acaba
  por cansancio con otro hash del par;
- cada una aplica a su propio estado solo su parte (bajas, munición gastada,
  cansancio, relación), recortada a lo que tiene. En estas guerras no se
  ceden ciudades ni pasan bienes de una a otra: así no se crea ni se pierde
  nada (economía cerrada).

Las dos llegan a los mismos números sin mirarse: el inicio y el resultado
solo usan el hash del par y dos fotos que son datos fijos. Si la vecina es del
fondo, su «foto» es `Fondo.nacion` de ese día (cerrada, sin estado). Cada
nación guarda la lista de sus fotos de sueño con sus días (una por cada vez
que se durmió), para que la historia pasada no cambie al volver a dormirse.
El fondo de una nación intacta usa también las fotos de sus vecinas tocadas:
su leyenda incluye las guerras con ellas.

El resultado es el mismo despierte cuando despierte, y es lo que ve un
explorador: su informe despierta la nación hasta hoy (es una cuenta pura, no
cambia nada que no fuera a pasar igual) y cuenta lo que hay, guerras
incluidas. Además, mientras duerme:

- solo se expande dentro de su propia zona (no pisa tierra que otra dormida
  podría querer);
- no manda grupos fuera.

Una guerra entre una dormida y una despierta (resumida o completa) empezada
mientras la primera dormía sigue con la cuenta de las fotos hasta que las dos
estén despiertas; desde entonces, con la de la resumida. Coste del
prototipo: 0,1 a 0,5 µs por año de juego; mil años, menos de medio
milisegundo (la guerra añade unas cuentas por vecina y paso).

**Promoción de resumida o congelada a completa**, al empezar un día:

- Si el día no cae en frontera de paso, se aplica la parte proporcional del
  paso en curso (`(d − inicio) / N` de sus cambios, redondeada con el mismo
  reparto entero de diseno/poblacion.md 3.9).
- Los recolectores pasan a grupos en su mina, fase `recolectando`, por orden
  de valor de la mina; los frentes pasan a un grupo por frente en el punto
  medio entre el sitio propio y el disputado, con líder, munición y umbral de
  retirada como los manda hoy la IA.
- Los ids nuevos salen del contador de la nación (3.7).

**Bajada de completa a resumida**: se suman los grupos en los campos del
resumen (recolectores a su mina, convoyes propios a su destino con la carga,
grupos que vuelven a casa a su ciudad). No hay reparto al azar: la bajada y la
subida son deterministas y la subida de lo recién bajado devuelve lo mismo
salvo las posiciones de los grupos (que nadie ve: la zona estaba fuera de la
zona de interés).

### 3.5 Niveles distintos que se tocan

| Caso | Qué pasa |
|---|---|
| Un grupo de una zona completa sale hacia una zona que no lo es | La de destino sube a completa al empezar el día siguiente. Un ejército tarda al menos un día en llegar (9 000 px por día), así que siempre llega a una completa |
| Una completa en guerra con una resumida | La guerra sigue. Los ataques de la resumida salen de su frente como un grupo sintético (las tropas del frente) que entra en la batalla simulada de hoy (batallas.lua). Si ese grupo va hacia la completa, la resumida sube a completa |
| Dos resumidas en guerra | Se resuelve en su paso, en bloque, con el poder de cada una publicado al final del paso anterior |
| Una resumida junto a una congelada | La congelada no se entera hasta despertar. Si la resumida le declara la guerra, el mensaje la despierta (pasa a resumida). Las guerras que decide la congelada mientras duerme usan las fotos de sueño (3.4) |
| Explorador hacia una nación no completa | El informe sale de `materializar` (fondo) o del estado resumido: las mismas cifras que tendrá al subir |
| Diplomacia entre una completa y una resumida | Diaria para la completa, por paso para la resumida. Cada nación lleva su lado de la relación; lo que una cambia en la otra le llega como mensaje (3.7) |

Para que nadie use los niveles como trampa:

- Todo lo que un jugador puede ver o atacar está completo: la zona de
  interés cubre la vista y cualquier sitio al que llegue un ejército suyo.
- La resumida está calibrada para dar en media lo mismo que la completa
  (criterios 8.2). Lo que no hace es el detalle (qué grupo exacto recolecta
  dónde), que el jugador no ve.
- La congelada sigue creciendo y guerreando mientras duerme: alejarse de un
  rival no lo para.
- El nivel lo decide quien tiene la autoridad (el servidor, o la máquina local
  sin conexión) y queda apuntado en el estado. Un cliente no lo elige.

### 3.6 La IA de los NPC en cada nivel

| Nivel | Qué decide y cada cuánto |
|---|---|
| Completa | Lo de hoy, cada día, con las mismas órdenes que el jugador (`ejecutar`) |
| Resumida | Una vez por paso: mejorar ciudades, producir (unidades y munición), colocar defensas, cuántos soldados manda a cada mina, banderas y campamentos hacia sus mejores yacimientos (F12), declarar la guerra o negociar con sus vecinas, cuánta fuerza pone en cada frente. Las mismas funciones de decisión, con el estado resumido |
| Congelada | Política fija: producir hasta la parte del tope de su carácter, mejorar cuando pueda pagar, expandirse dentro de su zona; guerras con sus vecinas por hash y fotos de sueño (3.4) |
| Fondo | Ninguna: curvas y leyenda |

Una nación de jugador nunca está por debajo de resumida y su IA no decide por
él. Con su jugador desconectado sigue como resumida (economía y colas que ya
dejó encargadas; no produce ni ataca sola), también mientras su jugador
juega sin conexión (3.11).

**Quién simula a los NPC (decidido).** En línea, el servidor: es la autoridad
de todas las naciones NPC y el cliente solo dibuja una réplica. Sin conexión,
ese mismo servidor corre en un `love.thread` de la máquina del jugador.

### 3.7 Localidad: lo que cambia en el día

Para que el resultado no dependa del orden ni de cuántas naciones hay:

1. **Azar por entidad.** `Ruido.hash(semilla, dia, idNumerico(nacion), fase)`
   en lugar del `azar` único del día (l.3743) que hoy se reparte en orden
   entre todas las naciones (diplomacia, `expansion(n, azar, k)`, guerras,
   batallas, movimiento). Hoy, registrar una nación más cambia los sorteos de
   todas las demás.
2. **Ids por nación.** Grupos, batallas, exploradores y convoyes con id
   `'<zona>#<número>'` y un contador por nación, no los globales
   `siguienteGrupo`, `siguienteBatalla` y `siguienteExplorador`. Las batallas
   son de la zona donde ocurren.
3. **Nada por turno.** `expansion` usa hoy el puesto `k` de la nación en la
   lista de vivas (l.2409) para repartir los días de campamentos y banderas.
   Pasa a usar un desfase por hash de la zona.
4. **Resumen publicado.** Al final del día cada nación publica un resumen
   pequeño (fuerza total, sitios, relaciones, guerras). Lo que una nación lee
   de otra durante el día es ese resumen de ayer, no su estado a medio hacer.
5. **Mensajes.** Declarar la guerra, proponer la paz, ceder una ciudad, la
   llegada de un grupo o de un explorador a otra zona: mensajes que se
   entregan al empezar el día siguiente, en orden (día, zona destino, zona
   origen, número).
6. **Vecinas.** La diplomacia solo corre entre naciones a menos de
   `alcanceGuerra + alcanceCodicia` (190 000 px, unas 2 zonas). Las
   relaciones se guardan solo para esos pares. La de partida sale de
   `hash(semilla, zonaA, zonaB)` y del orden político, sin depender de quién
   se registró antes.

Con esto el día de cada nación se puede hacer en cualquier orden: repartido
entre cuadros, en otro hilo o en otra máquina, con el mismo resultado.

### 3.8 Estado y guardado por diferencias

El estado se parte por zonas: `estado.zonas[clave] = { nivel, nacion,
ciudades, grupos, instalaciones, batallas, territorio, minas, noticias,
contadores, desde }`. Lo global se queda en lo mínimo: día, semilla, versión,
guerras (por par) y los mensajes pendientes.

Qué no se guarda:

- **Zonas del fondo**: nada. Son la semilla.
- **Yacimientos**: nada, salvo los tocados (`minas`: lo que queda y cuándo se
  agotó). Hoy son el 58 % al 70 % del guardado.
- **Ciudades y sitios físicos**: solo lo que cambia (población, inventario,
  vida, nivel, dueño si se cedió). Nombre, posición, radio y casco salen de la
  semilla por el id de región.
- **Relaciones**: solo con las vecinas y solo si se apartan de la de partida.

Tamaño previsto por zona tocada (serializado como hoy; con gzip, unas 4 a 5
veces menos):

| Qué | Hoy (por nación, 350 naciones, día 26) | Propuesto |
|---|---|---|
| Yacimientos | 45 KB | 0 a 1 KB (las minas tocadas) |
| Relaciones | ~14 KB (349 pares) | ~0,3 KB (≤ 24 vecinas) |
| Grupos, ciudades, territorio, instalaciones | ~10 KB | ~10 KB |
| Población por cohortes (diseno/poblacion.md) | — | ~3 KB por ciudad |
| **Total** | **~78 KB** | **~14 KB completa, ~4 KB resumida o congelada** |

Meta de guardado (decisión 13, 2026-09-30): **unos 18 KB por nación
completa**. La previsión de ~14 KB de la tabla queda por debajo; el margen
cubre lo que se añada después (por ejemplo, las unidades por modelo del
catálogo de armamento).

Con gzip, unos 3 KB por zona completa tocada y 1 KB por resumida. Mil zonas
tocadas: unos 3 MB. Un millón (muchos jugadores durante mucho tiempo): unos 3
GB en el servidor, repartidos en archivos por sector (3.9).

El guardado sigue siendo texto con las claves en orden fijo (huella para el
determinismo), por zona. Uno por zona permite guardar solo las que cambiaron
y mandarlas por la red por separado.

### 3.9 Servidor: sectores

**Sector** = 8 × 8 zonas (unos 79 km de lado, hasta 64 naciones). Es la
unidad que se reparte entre procesos, se guarda en un archivo y se carga o se
descarga entera. La clave `'s:sx,sy'` sale de la de la zona.

**Día sincronizado.** Todos los sectores hacen el día `d` a la vez:

1. Entregar los mensajes del día `d − 1` y los comandos de los jugadores para
   el día `d`, en orden (día, zona, origen, número).
2. Decidir el nivel de cada zona (3.1).
3. Cada zona hace su día leyendo lo suyo, su bandeja y los resúmenes de ayer.
   Es independiente de las demás: los sectores de un proceso se pueden hacer
   en cualquier orden o en varios procesos.
4. Movimiento y choques de grupos (ver abajo).
5. Publicar resúmenes y mandar los mensajes al sector de destino.
6. Esperar a que todos terminen (barrera) y pasar al día siguiente.

Con un día por minuto, la barrera tiene 60 s: sobra tiempo aunque haya
varios procesos en máquinas distintas.

**Fronteras.** Cada sector tiene una copia de solo lectura (**halo**) de los
resúmenes de las zonas vecinas hasta 2 zonas más allá de su borde (el
alcance de interacción: `alcanceAtaque` 130 000 px ≈ 1,3 zonas, más margen).
El halo se refresca en el paso 5.

**Grupos que cruzan.** El movimiento es en línea recta por días
(`moverGrupos`): el tramo de cada grupo se marca en la rejilla de choques
(`detectarChoques`, F7). Un sector recibe los tramos de los grupos del halo
que tocan su borde, así que ve los choques que caen en su lado. El choque lo
resuelve el sector donde cae el punto de choque, en orden fijo de ids. Un
grupo que termina el día en otra zona pasa a ella como mensaje; si esa zona es
de otro sector, cambia de proceso.

**Límites de lo que cruza por borde de sector y día** (se revisan con
mediciones):

| Qué | Límite | Si se pasa |
|---|---|---|
| Grupos (ejércitos, convoyes, recolectores) | 256 | Esperan un día en el borde, en orden de id |
| Exploradores | 64 | Igual |
| Mensajes diplomáticos | 4 por nación y día | Se rechazan con aviso |
| Diplomacia a distancia (más allá de las vecinas) | Solo con naciones en contacto (con informe o relación) y con un día de retraso por sector atravesado | — |

**Sin conexión.** El mismo servidor corre en un `love.thread` de la máquina
del jugador, con un solo «proceso» que tiene cargados los sectores que hacen
falta. Es el mismo código. Cómo se juntan la partida sin conexión y el mundo
en línea: 3.11.

### 3.10 Protocolo de red (propuesta; el servidor autoritativo está decidido)

**Librería.** ENet en los dos lados: en el cliente, `require('enet')` que ya
trae LÖVE; en el servidor (LuaJIT sin LÖVE), un envoltorio FFI sobre la
`libenet` del sistema (enet 1.3.18 ya está instalada; no hace falta compilar
nada). Tres canales: 0 fiable y ordenado (control, comandos y acuses), 1 fiable
(fotos y cambios de zonas), 2 no fiable (ping y presencia).

**Formato.** Cada mensaje: `{ v = versión, t = tipo, ... }` con un
serializador de solo datos (tablas, números, cadenas, booleanos), con límite
de tamaño y de profundidad por tipo, y comprimido con zlib si pasa de 1 KB. El
servidor **nunca** ejecuta código recibido: hoy `Guardado.cargar` usa
`loadstring` con `setfenv` (guardado.lua l.358), que vale para un archivo
propio pero no para datos de fuera (un `while true do end` bloquearía el
servidor).

| Mensaje | Dirección | Qué lleva | Presupuesto |
|---|---|---|---|
| `hola` | C → S | versión, jugador, prueba de identidad, último día y huellas de las zonas que tiene | ≤ 2 KB |
| `bienvenida` / `rechazo` | S → C | semilla, día, nación del jugador / motivo | ≤ 1 KB |
| `interes` | C → S | centro de la cámara y radio pedido (el servidor lo recorta a `Rc`) | ≤ 64 B, ≤ 4 por segundo |
| `foto` | S → C | una zona entera (sus diferencias con el fondo) y su huella | ≤ 64 KB por zona; ≤ 1 MB al entrar |
| `cambios` | S → C | por zona y día, lo que cambió (las claves que cambiaron) y la huella nueva | media ≤ 8 KB/s por jugador |
| `dia` | S → C | día nuevo y huellas de las zonas de su interés | ≤ 2 KB por día |
| `comando` | C → S | número de secuencia, día y el comando (`{ tipo, ... }`, los de `ejecutar`) | ≤ 512 B, ≤ 20 por segundo |
| `acuse` | S → C | secuencia, aceptado y día en que se aplica, o el motivo | ≤ 128 B |
| `ping` / `pong` | ambos | hora | canal 2 |
| `presencia` | S → C | otros jugadores en su zona de interés: nombre, nación y dónde miran | ≤ 1 KB, canal 2, ≤ 1 por segundo |
| `descubrimiento` | C ↔ S | una zona, ciudad o yacimiento descubierto, con el nombre que le puso quien lo descubrió | ≤ 256 B |
| `salida` | C ↔ S | el cliente avisa de que se va; el servidor responde con la foto de salida firmada (3.11) | ≤ 1 MB (la foto de la burbuja) |
| `bitacora` | C → S | los comandos jugados sin conexión, por día, desde la foto firmada | ≤ 64 KB por trozo, por el canal 1 |

**Validación de cada comando** en el servidor: tipo conocido; campos con su
tipo y rango (enteros, cantidades ≥ 0 y ≤ tope, coordenadas dentro del
alcance); la nación es la del jugador; los ids existen y son suyos (o son
blancos que `puedeAtacar` acepta); el día (si llega para un día ya hecho,
se aplica en el actual y el acuse lo dice; más de 2 días por delante, se
rechaza); y el ritmo por jugador. Después, la misma comprobación que hace `ejecutar` (hoy devuelve
false y un motivo). El cliente nunca manda estado.

**Entrar y volver a entrar.** El cliente manda `hola` con las huellas que
tiene; el servidor manda `foto` de las zonas de su interés cuya huella no
coincide y sigue con `cambios`. El cliente guarda las zonas en disco para no
bajarlas otra vez.

**Réplica en el cliente.** El cliente guarda lo que recibe en un objeto
`Simulacion` más (la réplica) que no avanza días: la vista y los paneles leen
de ella con las mismas consultas de hoy (`consultas.lua`). Entre dos días,
las posiciones de los grupos se interpolan como hoy (`posicionGrupo`).

**Pruebas en local con dos procesos**: `luajit servidor/main.lua --puerto
7777 --semilla 4242` y dos clientes `love NationsRTS --conectar
127.0.0.1:7777`, más un cliente de pruebas sin LÖVE (LuaJIT) que manda
comandos y comprueba huellas.

### 3.11 Una partida, con y sin conexión (decidido)

El dueño: «Que sea como No Man's Sky: que las partidas funcionen en línea y
offline». Una misma partida se juega con y sin conexión; el universo es el
mismo para todos (misma semilla y misma historia de fondo); en línea se
comparten los descubrimientos y se ve a los otros jugadores.

**Qué es de quién.**

| Qué | Dueño | Con conexión | Sin conexión |
|---|---|---|---|
| Semilla, mundo físico y fondo | Nadie: salen de la semilla | Igual en todas las máquinas | Igual |
| Tu nación (ciudades, ejército, economía) | Tu partida | La simula el servidor; tú mandas comandos | Tu máquina juega una **rama** desde la foto de salida; el servidor sigue simulando la suya, atacable |
| Naciones NPC tocadas | El universo | Las simula el servidor | Copia local; lo que les hagas se sube después (ver «Al volver») |
| Naciones de otros jugadores | Sus partidas | Las simula el servidor | Copia local de solo lectura, dormida desde el día en que te fuiste |
| Descubrimientos (zonas, ciudades, yacimientos, nombres) | Quien los hizo primero | Se suben al momento | Se guardan y se suben al conectar; se respeta el primero por día del servidor |
| Reloj | — | 1 día por minuto, sin pausa | 1 día por minuto, sin pausa |

**Un solo ritmo (decidido).** En el juego terminado el tiempo corre siempre a
un día por minuto, con y sin conexión, y nunca se detiene: no hay pausa ni
sin conexión. Las velocidades de hoy (`VELOCIDADES`
en main.lua) quedan solo para el modo de pruebas y depuración, que no se
conecta al servidor ni sube nada. Por eso una partida sin conexión nunca va
por delante del servidor: en el mismo tiempo real ha pasado como mucho el
mismo número de días. Si la bitácora trae más días de los que caben en el
tiempo real transcurrido (reloj del sistema cambiado), los que sobran se
descartan.

**La foto de salida.** Al cerrar el juego o al perder la conexión, el cliente
se queda con la última **foto de salida firmada** por el servidor: la huella
del estado de tu burbuja (las zonas a menos de `Rc` de tus ciudades) y el día
`D0`, firmada con la clave del servidor. El servidor la manda al irte y, por
si la conexión se corta, también una vez por día. Desde ella, sin conexión,
tu máquina juega la rama con su servidor local.

**Tu nación sigue en el mundo y es atacable (decidido).** Mientras juegas
sin conexión, en el servidor tu nación sigue como la de un jugador
desconectado: su economía y sus colas siguen, no decide nada, y los demás
pueden atacarla. Si nadie la toca, sin jugadores cerca duerme como cualquier
otra (3.4). Irse sin conexión no la protege.

**El borde de la burbuja.** Mientras juegas sin conexión, tu burbuja y lo de
fuera solo se tocan con las reglas de las dormidas (3.4), con las fotos de
sueño del día `D0`, tanto en tu máquina como en el servidor (donde tu burbuja
duerme mientras nadie se acerca). Así las dos cuentas cuadran al volver. Lo
único que cruza de verdad son tus propios grupos.

**Al volver.** El cliente manda su bitácora (los comandos de cada día desde la
foto de salida). El servidor mira si otro jugador **atacó** tu nación desde
`D0` (declararle la guerra, atacar un sitio o un grupo suyo, meter un
ejército en su territorio):

- **Nadie la atacó:** el servidor **repite** la rama con la misma simulación,
  desde la foto, día a día, en un proceso aparte, y la versión repetida de tu
  burbuja sustituye a la que él tenía. La simulación es determinista, así que
  llega al mismo estado que tu máquina; si la huella no coincide (cliente
  modificado), vale lo que da el servidor. Nunca se acepta estado enviado por
  el cliente: solo sus comandos, validados uno a uno como en línea.
- **Alguien la atacó:** se pierde lo jugado sin conexión y solo quedan los
  descubrimientos. Tu nación es la que simuló el servidor, con el ataque
  incluido. El juego lo cuenta al conectar («mientras estabas fuera, X atacó
  …»). Se pierde todo lo jugado desde que te fuiste (`D0`), no solo desde el
  día del ataque: quien te atacó peleó contra la nación que tenía el
  servidor, y su batalla no se rehace.
- **Solo te miraron:** si otro jugador pasó cerca y vio tu nación (la que
  simulaba el servidor) sin atacarla, no cuenta: se acepta tu rama y lo que
  vio queda sustituido, como un informe de explorador que se queda viejo.
- **Zonas fuera de tu burbuja que tocaste sin conexión** (NPC que atacaste):
  para cada una, si desde `D0` otro jugador la tuvo en su zona de interés o
  le mandó algo, **gana la historia del servidor** para esa zona: al repetir,
  lo que tus comandos le hacían no se aplica y tus grupos que estaban en ella
  vuelven remolcados a su ciudad con lo que llevaban al entrar (como un grupo
  que cae: los vehículos al taller, sin botín). Si no, se acepta.
- **Naciones de otros jugadores:** sin conexión no se pueden atacar (tu copia
  es de solo lectura), así que no hay conflicto.

**Con el juego cerrado el tiempo sigue.** Tu nación sigue «sola» (como un
jugador desconectado: su economía y sus colas siguen, no decide nada):

- en línea, el servidor la simula mientras no estás;
- sin conexión, al volver a abrir la partida el servidor local pone al día
  los días que pasaron desde que la cerraste (con la nación sola), a partir
  del reloj del sistema, antes de dejarte jugar;
- al conectar, si tu rama tiene menos días de los que pasaron en el servidor
  (ratos con el juego cerrado), el servidor pone al día tu burbuja los días
  que faltan con tu nación sola.

**Coste de repetir.** Solo la burbuja y las zonas tocadas: unas 50 a 120
completas × 1 ms × días jugados. Mil días sin conexión (casi 17 horas de
juego) son unos 100 s de CPU en un proceso aparte del servidor. Mientras
tanto el jugador ya está conectado y ve el mundo; sus comandos esperan a que
acabe la repetición.

**Lo que ve un jugador en línea.** El mismo mundo que los demás, a los otros
jugadores cerca (`presencia`), sus naciones y ejércitos (son estado del
servidor como los NPC) y los nombres de lo que otros descubrieron.

---

## 4. Fórmulas

### F1. Nivel de una zona

```
completa  si  dist(z, interés) ≤ Rc  o  contacto(z) o  destino(z)
resumida  si  tocada(z) y (dist(z, interés) ≤ Rr o guerra con completa o resumida)
congelada si  tocada(z)
fondo     en otro caso
bajar     solo tras diasBajar días seguidos sin la condición, con radios + 2
```

### F2. Madurez del fondo

`m(d) = 1 − exp(−d / τ)`, con `τ` = 180 días de partida (a calibrar). Cada
curva del fondo es `valor(d) = inicial + (final − inicial) × m(d) × factor`,
con `final` y `factor` medidos en la simulación completa por percentiles y
factores por hash de la nación (riqueza, agresividad, prudencia).

### F3. Paso resumido

Para cada flujo diario `f` de la economía cerrada, el paso suma `N × f`
evaluado al principio del paso. Las colas de fábrica y el taller avanzan `N`
días. Un frente con poderes `A` y `B` pierde en el paso, por cada lado,
`bajas = N × ritmo × poder del otro / (A + B)`, la misma cuenta por día de la
batalla simulada, y gasta `N` días de munición (F6 de economia.md). Sin
munición, su golpe baja como en la batalla simulada.

### F4. Coste del día y presupuesto

```
coste(d) = Nc × cc + Nr × cr / N + despertares × cf × años + promociones × cm
```

con `cc` ≈ 1 ms (completa, lineal), `cr` ≈ 20 µs por paso (resumida,
planificado con 100 veces el prototipo), `cf` ≈ 20 µs por año (congelada que
despierta) y `cm` ≈ 12 ms (materializar una zona).

---

## 5. Presupuesto

### 5.1 PC con un jugador

La simulación va en el servidor local, en su propio hilo (`love.thread`,
decisión 5). Hasta la fase 4 se reparte en partes de ≤ 3 ms por cuadro. El
día se prepara durante el minuto que dura el anterior. En el juego terminado
el día dura siempre un minuto (decisión 8); las velocidades más altas solo
existen en el modo de pruebas, y ahí, si el día no está listo, el reloj
espera: el día se alarga en vez de congelar la imagen.

| Velocidad | Tiempo para un día (con el 50 % de un núcleo) | Completas que caben (1 ms) |
|---|---|---|
| 1 día / 60 s (el juego) | 30 s | memoria antes que tiempo |
| 1 día / 5 s (solo pruebas) | 2,5 s | ~2 500 |
| 1 día / 1 s (solo pruebas) | 0,5 s | ~500 |
| Sin hilo, 3 ms por cuadro a 60 fps, 1 día / 60 s | 10,8 s | memoria antes que tiempo |
| Sin hilo, 3 ms por cuadro a 60 fps, 1 día / 1 s | 180 ms | ~150 |

Propuesta para un PC:

| Nivel | Cuántas | CPU por día | Memoria |
|---|---|---|---|
| Completas | ≤ 250 (7 × 7 zonas por punto de interés, más guerras) | ≤ 250 ms | ≤ 110 MB (440 KB cada una hoy) |
| Resumidas | ≤ 20 000 | ≤ 40 ms (2 µs cada una) | ≤ 80 MB |
| Congeladas | sin límite | 0 (despertar mil años de una: < 1 ms) | en disco, ~1 KB con gzip cada una |
| Fondo | infinitas | 0 | 0 |
| Materializar | ≤ 2 zonas por cuadro (o en el hilo) | ~12 ms cada una | — |

### 5.2 Un proceso de servidor

LuaJIT sin LÖVE, un núcleo, día fijo de 60 s, el 70 % para el día (42 s):

| Nivel | Cuántas por proceso | CPU por día | Memoria |
|---|---|---|---|
| Completas | ≤ 5 000 | ≤ 5 s | ≤ 2,2 GB |
| Resumidas | ≤ 500 000 | ≤ 1 s | ≤ 2 GB |
| Congeladas | en disco | 0 | — |

Lo que limita es la memoria, no el tiempo. Con unas 50 a 120 completas por
jugador (menos si están juntos), un proceso atiende de 40 a 100 jugadores;
una máquina de 16 núcleos, de 600 a 1 500. Red: 100 jugadores × 8 KB/s = 0,8
MB/s por proceso. Las recolecciones de basura de LuaJIT con montones de GB
tardan; se llaman por pasos entre días.

Estas cifras dan por hecho que la completa deja de ser cuadrática (fase 1).
Con el código de hoy, 5 000 naciones completas pedirían unos 4 minutos por
día (extrapolado de §0).

---

## 6. Qué ayuda y qué estorba de lo programado

**Ayuda:**

- Mundo físico entero de la semilla con ids de región: el fondo y la
  materialización se apoyan en él.
- Una nación por zona (`'z:zx,zy'`): la zona es la clave natural del nivel de
  detalle, del guardado por diferencias y del sector.
- Simulación determinista, sin LÖVE, con todo cambio externo por
  `ejecutar` y guardado de texto ordenado (huella). El servidor puede correr
  el mismo código.
- La batalla simulada (batallas.lua) ya resuelve bandos sin escena 3D: sirve
  para completa contra resumida.
- Los grupos van en línea recta sin rutas (`trazar`): moverlos entre sectores
  es barato.
- El poder enemigo es oculto salvo informe (exploracion.lua): el jugador ve lo
  que dicen sus exploradores, y el informe de una nación no completa puede
  salir del fondo sin diferencias.
- `depurar/mundo_prueba.lua` y las herramientas de `tools/` miden sin LÖVE.

**Estorba:**

1. Todo lo cuadrático de §0.
2. El azar único del día repartido en orden entre todas las naciones (l.3743)
   y el turno `k` de `expansion` (l.2409).
3. `registrarZona` hace nacer la nación fresca el día que se descubre y saca
   sus relaciones del orden de registro (l.1030-1041).
4. Contadores globales de ids (`siguienteGrupo` l.659, `siguienteBatalla`,
   `siguienteExplorador`).
5. Estado en tablas globales (ciudades, grupos, instalaciones, territorio,
   noticias con 60 en total): no se puede guardar, congelar ni mover una zona
   sola.
6. `depositos` en el guardado aunque salen de la semilla.
7. `cargar` con `loadstring`: no vale para datos de la red.
8. `actualizar` hace el día entero en un cuadro (l.3795).
9. La vista lee `sim.estado` directamente (19 veces en mundo.lua, 107 en
   interfaz/ y main.lua; `despejados`, l.192 y l.197, recorre todas las
   instalaciones y ciudades por cada trozo). Para mover la simulación a otro
   hilo, la vista tiene que leer de una réplica.
10. Flotantes: `Ruido.hash` usa dobles. En x86-64 es determinista; en ARM,
    LuaJIT no fusiona multiplicación y suma (FMA) salvo que se active, y así
    debe quedar.

---

## 7. Fases

### Fase 1: que la completa sea lineal (pequeña y medible)

Sin cambiar las reglas del juego salvo la diplomacia entre naciones lejanas.

| Archivo | Cambio | Área |
|---|---|---|
| `mundo/simulacion.lua` | Índice por nación de los grupos (`gruposDe(nid)`) en la caché de `gruposOrdenados`, sin crear una lista nueva en cada llamada; `vivas` con caché por versión del índice; rejilla de capitales para vecinas | Andrés |
| `mundo/simulacion/recoleccionIA.lua`, `municion.lua`, `produccion.lua`, `diplomacia.lua`, `taller.lua` | Los recorridos de todos los grupos o ciudades pasan a `gruposDe` de la nación o de sus enemigas | Andrés |
| `mundo/simulacion.lua` `avanzarDia` | Diplomacia solo entre vecinas (a menos de 190 000 px); las lejanas se quedan en su relación de partida | Andrés |
| `mundo/simulacion.lua` `registrarZona` | Relaciones solo con las vecinas | Andrés |
| `mundo/simulacion/guardado.lua` | Versión 23: sin `depositos` (se rehacen de la semilla); migración que los quita | Andrés |
| `mundo/mundo.lua` `usarSimulacion` | Al cargar, vuelve a registrar los yacimientos de las zonas registradas | Valeria |
| `tools/medir_niveles_nationsrts.lua` | Ya está: la medida de aceptación | Tomás |

Aceptación: con 350 naciones, el coste por nación y día no pasa de 1,3 veces
el de 21 naciones; el guardado baja de ~78 a unos 18 KB por nación (meta
del dueño, decisión 13); los cambios
de índices dan la misma huella de guardado que antes (determinismo intacto;
la diplomacia entre vecinas cambia resultados y se comprueba aparte con
guardar/cargar y repetición). Esperado: de 1 181 ms a unos 150 a 250 ms por
día con 350 naciones.

### Fase 2: localidad

Azar por entidad, ids por nación, `expansion` sin turno, resumen publicado,
mensajes con un día de retraso (3.7), estado partido por zonas (3.8). El día
se reparte entre cuadros (`avanzarDia` por partes, una nación por parte, con
un presupuesto por cuadro). Aceptación: el resultado de una zona no cambia al
registrar o quitar una zona a más de 3 zonas; la huella no depende del orden
en que se recorren las naciones (prueba: recorrerlas al revés); ningún cuadro
pasa de 20 ms por la simulación con 100 naciones.

### Fase 3: niveles

Fondo calibrado con su leyenda, `materializar`, resumida, congelada con
puesta al día, guerras entre dormidas con fotos de sueño (3.4), histéresis y
guardado por zonas.

| Archivo | Cambio | Área |
|---|---|---|
| `mundo/fondo.lua` (nuevo) | `Fondo.nacion`, `Fondo.materializar`, la leyenda por hash y las fotos de sueño de las vecinas tocadas | Andrés |
| `mundo/simulacion/resumida.lua` (nuevo) | Estado resumido, paso de `N` días, bajar y subir de nivel, puesta al día de la congelada | Andrés |
| `mundo/simulacion.lua` | Nivel por zona (F1) al empezar el día; `registrarZona` pasa a `materializar` | Andrés |
| `mundo/simulacion/exploracion.lua` | El informe de una nación no completa sale de `materializar` o de la puesta al día | Andrés |
| `mundo/simulacion/guardado.lua` | Guardado por zonas, solo diferencias con el fondo | Andrés |
| `mundo/mundo.lua` | Deja de registrar naciones al explorar: pide zonas de interés | Valeria |
| `tools/` | Calibración del fondo y de la resumida contra la completa (criterios 8.2 y 8.3) | Andrés y Elena |

Aceptación: criterios 8.2 a 8.6.

### Fase 4: servidor en un proceso, también sin conexión

`servidor/` en LuaJIT con ENet por FFI y el protocolo v1 (3.10). El cliente
deja de simular: dibuja una réplica. Sin conexión, el mismo servidor en un
`love.thread` hablando con el cliente por canales de LÖVE en lugar de ENet
(decisión 5).

| Archivo | Cambio | Área |
|---|---|---|
| `servidor/main.lua`, `servidor/red.lua`, `servidor/enet_ffi.lua` (nuevos) | Bucle del día a 1 minuto, sesiones, validación de comandos, fotos y cambios por zona | Tomás |
| `servidor/datos.lua` (nuevo) | Serializador de solo datos con límites (sustituye a `loadstring` para todo lo que venga de fuera) | Tomás |
| `servidor/hilo.lua` (nuevo) | El servidor dentro de `love.thread` para jugar sin conexión, a un día por minuto y sin pausa (velocidades y pausa solo en el modo de pruebas); al abrir la partida pone al día los días con el juego cerrado | Tomás |
| `red/cliente.lua` (nuevo) | Conexión, réplica (`Simulacion` que no avanza días) y aplicación de `cambios` | Tomás |
| `main.lua` | Los comandos del jugador van por `red/cliente.lua`; las velocidades y la pausa quedan solo en el modo de pruebas y se mandan al servidor local | Valeria y Tomás |
| `mundo/mundo.lua`, `interfaz/` | Leen de la réplica con las consultas de `consultas.lua`, no de `sim.estado` directamente | Valeria |

Aceptación: criterio 8.7 con dos procesos en local; sin conexión, ningún
cuadro pasa de 20 ms por la simulación.

### Fase 5: sectores en varios procesos

Halo, barrera del día, grupos que cambian de proceso, archivo por sector.

### Fase 6: una partida con y sin conexión

Foto de salida firmada, bitácora, repetición en el servidor, descarte si
atacaron tu nación, conflictos por zona, descubrimientos compartidos y
presencia de otros jugadores (3.11).

| Archivo | Cambio | Área |
|---|---|---|
| `servidor/salida.lua` (nuevo) | Foto de salida firmada (al irse y una vez por día) y registro de ataques de otros jugadores a cada nación ausente | Tomás |
| `servidor/repeticion.lua` (nuevo) | Repetir la bitácora en un proceso aparte, descartarla si atacaron la nación y resolver los conflictos por zona | Tomás |
| `servidor/descubrimientos.lua` (nuevo) | Primer descubridor y nombres | Tomás |
| `mundo/simulacion/guardado.lua` | La partida guarda la foto firmada, `P0`, `D0` y la bitácora | Andrés |
| `interfaz/` | Aviso de lo que pasó mientras estabas fuera (y si se perdió lo jugado), jugadores cercanos, nombres de descubridores | Valeria |

Aceptación: criterio 8.8.

---

## 8. Criterios de aceptación

1. **Lineal**: el coste por nación y día de las completas no crece más de un
   30 % de 21 a 350 naciones (fase 1).
2. **Resumida equivalente**: 500 días, 4 semillas, las mismas naciones una vez
   completas y otra resumidas: medianas por nación de población, soldados,
   tanques, nivel de la capital, tesoro y guerras por año dentro de ±10 %; p10
   y p90 dentro de ±20 %.
3. **Fondo equivalente**: las mismas medianas del fondo el día 100, 500 y 1 000
   contra la simulación completa, dentro de ±15 %.
4. **Congelada independiente del momento**: dormir el día 100 y despertar el
   500 da la misma huella que dormir el 100, despertar el 300, volver a dormir
   y despertar el 500 (sin nada que la toque).
5. **Sin saltos**: subir una resumida a completa y bajarla sin que pase un día
   deja la misma huella salvo las posiciones de los grupos; el poder que dice
   un informe tomado el día de la subida es el que tiene al subir.
6. **Mundo igual para todos**: dos máquinas que materializan la misma zona el
   mismo día, habiendo explorado en distinto orden, dan la misma huella.
7. **Red**: dos clientes en local con el servidor; al desconectar uno 10 días y
   volver, su réplica tiene la misma huella que el servidor; un comando con
   campos fuera de rango o de otra nación se rechaza con motivo.
8. **Con y sin conexión**: una partida juega 200 días sin conexión y vuelve;
   la repetición del servidor da la misma huella que la máquina del jugador;
   con un cliente que altera su estado, gana el servidor. Si otro jugador
   atacó la nación mientras tanto, lo jugado sin conexión se descarta y
   quedan los descubrimientos. Una zona fuera de la burbuja que otro jugador
   miró mientras tanto queda como la tenía el servidor y los grupos del que
   volvió están en su ciudad. Una bitácora con más días que el tiempo real
   transcurrido se recorta.
9. **Guerras entre dormidas coherentes**: dos dormidas vecinas despertadas en
   distinto orden y en días distintos dan la misma guerra (inicio, bajas y
   fin); el informe de un explorador cuenta esa guerra igual que la ve quien
   llega después.

---

## 9. Perillas

| Perilla | Valor de partida | Qué cambia |
|---|---|---|
| `Rc` | 3 zonas | Tamaño de la burbuja completa (coste) |
| `Rr` | 8 zonas | Cuántas resumidas |
| `diasBajar` | 5 | Histéresis |
| `N` | 10 días | Detalle y coste de la resumida |
| `τ` | 180 días | Qué tan rápido madura el fondo |
| Sector | 8 × 8 zonas | Grano del reparto entre procesos |
| Límites de cruce | 256 grupos, 64 exploradores por borde y día | Carga máxima de una frontera |

---

## 10. Decisiones del dueño (2026-09-30)

Sustituyen a las preguntas de la primera versión de este documento.

1. **DECIDIDO. Una misma partida se juega con y sin conexión**, como No Man's
   Sky: el universo es el mismo para todos (misma semilla y misma historia de
   fondo) y en línea se comparten los descubrimientos y se ve a los otros
   jugadores. Diseño en 3.11: foto de salida, repetición en el servidor y
   conflictos por zona.
2. **DECIDIDO. En línea, el tiempo es fijo: un día por minuto, sin pausa**
   (sin conexión, ver decisión 8).
3. **DECIDIDO. Historia de fondo igual para todos** (3.2).
4. **DECIDIDO. Las naciones dormidas sí empiezan guerras entre ellas**,
   decididas por hash de la semilla y coherentes con lo que luego ve un
   explorador (3.4, fotos de sueño).
5. **DECIDIDO. El servidor simula a los NPC.** En línea es la autoridad y el
   cliente solo dibuja una réplica; sin conexión corre ese mismo servidor en
   un `love.thread` local (3.6, 3.10, fase 4).
6. **DECIDIDO. Relaciones entre naciones lejanas fijas** en su valor de
   partida; solo se mueven entre vecinas (fase 1).
7. **DECIDIDO. Lo que una nación hace a otra llega al día siguiente** (3.7,
   fase 2).

8. **DECIDIDO. Sin aceleración del tiempo en el juego terminado.** el dueño:
   «La aceleración debe funcionar en las pruebas nada más; cuando el juego
   esté completo no existirá la aceleración del tiempo». Siempre un día por
   minuto, con y sin conexión; las velocidades solo en el modo de pruebas.
   Una partida sin conexión nunca va por delante del servidor (3.11).
9. **DECIDIDO. Tu nación sin conexión es atacable.** Si alguien la ataca
   mientras estás fuera, se pierde lo jugado sin conexión y solo quedan los
   descubrimientos (3.11).

10. **DECIDIDO. Sin pausa sin conexión.** El tiempo nunca se detiene, igual
    que en línea; con el juego cerrado la nación sigue sola (3.11). La pausa
    solo existe en el modo de pruebas.
11. **DECIDIDO. Si te atacan estando sin conexión, se pierde todo lo jugado
    desde que te fuiste** (quedan los descubrimientos). La batalla del
    atacante no se rehace.
12. **DECIDIDO. Mirar tu nación no cuenta como ataque:** lo que vio otro
    jugador queda sustituido al aceptar tu rama.
13. **DECIDIDO. Meta de guardado: unos 18 KB por nación completa**
    (antes, ≤ 15 KB en la aceptación de la fase 1).

---

## Cómo se midió

- **Simulación de hoy**: `luajit tools/medir_niveles_nationsrts.lua 20 10 4242
  5 10` y `luajit tools/medir_niveles_nationsrts.lua 20 5 4242 15 20`, en HEAD
  c0faae7. Monta L × L zonas alrededor del origen como
  `depurar/mundo_prueba.lua`, calienta 20 días, mide 10 (o 5) con `os.clock`
  y envuelve las fases de `avanzarDia` con un reloj (no tocan estado ni azar).
  Mide el guardado con `sim:guardar()`, su reparto por clave con
  `Simulacion.serializar` y el tamaño con gzip. Solo una semilla y días
  tempranos: con guerras y más grupos el coste sube (Andrés midió 1,2 ms por
  nación y día con 21 a 22 naciones más adelante).
- **Resumida, congelada y fondo**: `luajit tools/medir_resumida_nationsrts.lua
  100 50` (10 000 naciones) y `316 20` (99 856). Es un prototipo de **coste**,
  no de reglas: 25 números por nación, economía en bloque, producción, 8
  vecinas y Lanchester, azar por hash. Dio 0,10 y 0,19 µs por nación y paso,
  1,1 KB por nación, 0,1 a 0,5 µs por año para despertar una congelada y
  0,013 µs por consulta del fondo. El presupuesto usa 100 veces esas cifras
  (20 µs por paso, 4 KB por nación), porque la resumida real llevará cohortes,
  varias ciudades, territorio y la IA estratégica.
- La medición de Andrés (`tools/medir_escala_nationsrts.lua`, hasta 4 096
  zonas y 100 días, con perfilador por muestreo) corría a la vez que esta; sus
  cifras sustituyen a la extrapolación de §0 cuando estén.
- Falta medir: el coste lineal real tras la fase 1, la resumida con las
  reglas de verdad y su calibración (8.2 y 8.3), el tamaño de los `cambios`
  por día en la red y la memoria de LuaJIT con montones de varios GB.

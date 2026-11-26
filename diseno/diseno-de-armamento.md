# Diseño de armamento: personalización de vehículos e infantería

> **Decisión del dueño (2026-10-02):** este documento se reduce a la
> personalización que trae el GDD «Guerra Moderna RTS» (sección 6): blindaje
> reactivo (ERA), rejas anti-RPG y estaciones de armas remotas (RWS) para los
> vehículos, y visores nocturnos o térmicos para la infantería. El kit de
> piezas por nación (diseños propios, estilos heredados, diseños secretos)
> queda **superado**; se conserva más abajo, en el anexo, como historia.
>
> Estado: **sin programar.** Las cifras son propuesta y no están medidas: no
> hay todavía simulación ni batalla con estos accesorios.

## 1. Resumen

Los vehículos y la infantería del juego son modelos reales, nombrados por su
designación (`catalogo-armamento.md`). No se diseñan de cero: se
**personalizan** en el taller de una ciudad con accesorios que cambian cómo
aguantan, cómo ven y cómo disparan. Hay cuatro accesorios:

| Accesorio | Para | Qué hace |
|---|---|---|
| ERA (blindaje reactivo) | MBT, VCI y APC | Reduce el daño de cargas huecas (RPG, ATGM) en el sector donde va |
| Rejas anti-RPG | Todos los vehículos | Probabilidad de hacer fallar un RPG en los laterales y la trasera |
| RWS (estación de armas remota) | Todos los vehículos | Ametralladora o lanzagranadas manejado desde dentro, con supresión |
| Visor nocturno o térmico | Escuadras de infantería | Ver de noche, con humo o a través de vegetación ligera |

## 2. Fantasía del jugador

Su viejo T-72 pierde contra los ATGM de la milicia hasta que paga ERA en el
taller de Dioskar. Sus MRAP aguantan una emboscada porque llevan rejas. De
noche, su escuadra con térmicos ve al enemigo que no le ve a él. Personalizar
es la forma de que una compañía pequeña y pobre pelee por encima de su
tamaño, y de que cada columna se parezca a quien la manda.

## 3. Reglas

1. Se instala en el **taller** de una ciudad (GDD 3.1), con dinero y kits de
   repuestos, y tarda un tiempo de juego. El hangar permite verlo y probarlo.
2. Cada vehículo tiene ranuras por sector: **frontal, lateral izquierdo,
   lateral derecho, trasera y techo** (el blindaje sectorial del GDD 4.2).
   - ERA: frontal y laterales.
   - Rejas: laterales y trasera.
   - RWS: techo (una por vehículo).
3. Un sector lleva **ERA o rejas**, no las dos.
4. **ERA:** cada bloque de un sector aguanta un impacto de carga hueca y se
   gasta. Reponerlo cuesta kits de repuestos después de la batalla.
5. **Rejas:** no se gastan, pero se dañan; un 30 % de los RPG que las tocan
   fallan. No sirven contra ATGM en ataque superior (top-attack) ni contra
   cañones.
6. **RWS:** añade un arma ligera (7,62 mm, 12,7 mm o lanzagranadas de 40 mm)
   que gasta munición ligera o pesada y dispara sin exponer a la tripulación.
7. **Visores:** van por escuadra. El nocturno anula la penalización de la
   noche; el térmico, además, ve a través del humo normal (no del
   multiespectral) y de la vegetación ligera, y revela firmas térmicas.
8. Los accesorios **pesan**: ERA y rejas suben el consumo de combustible del
   vehículo (GDD 2.1, consumo según el peso de la columna).
9. Los NPC (generales) personalizan con las mismas reglas y costes que el
   jugador. La perk de ingeniería «Refuerzo modular» (nivel 100) da ERA
   gratis en los MBT comprados (GDD 9.3).
10. El aspecto sale en el modelo 3D: bloques de ERA, rejas y la RWS se ven
    en la batalla y en el hangar.

## 4. Fórmulas [Propuesta, sin medir]

- **Daño de carga hueca con ERA:** `danio = danioBase * (1 - 0.7 * eraIntacta)`,
  con `eraIntacta` 1 si al sector le queda ERA y 0 si no. Ejemplo: un ATGM de
  600 de daño en un frontal con ERA → 600 × 0,3 = 180, y el bloque se gasta.
- **Rejas:** `pFallo = 0.3 * estadoRejas` (estado de 0 a 1). Ejemplo: rejas al
  50 % → 15 % de fallo.
- **Consumo:** `consumo = consumoBase * (1 + 0.04 * sectoresEra + 0.02 * sectoresRejas)`.
  Ejemplo: MBT con ERA en 3 sectores → +12 %.
- **Visores:** `alcanceVista = alcanceBase * factorLuz`, con `factorLuz`
  0,35 de noche sin visor, 0,8 con nocturno y 1,0 con térmico.

## 5. Casos límite

- ERA y rejas en el mismo sector: no se permite; el taller lo impide.
- Vehículo capturado: conserva sus accesorios.
- RWS sin munición: sigue montada y no dispara.
- Top-attack contra un techo sin protección: daño completo (GDD 7.2).

## 6. Dependencias

- Depende de: catálogo de armamento real, blindaje sectorial y supresión
  (batalla 3D), taller y hangar (asentamientos), economía de kits de
  repuestos y munición.
- Dependen de él: el combate en la batalla 3D, el consumo de combustible en
  el mapa de campaña y el árbol de habilidades (ingeniería).

## 7. Perillas de ajuste [Propuesta, sin medir]

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| `reduccionEra` | 0,7 | 0,4–0,85 | Cuánto protege la ERA de cargas huecas |
| `falloRejas` | 0,3 | 0,15–0,5 | Fiabilidad de las rejas |
| `pesoEra` | 0,04 | 0,02–0,08 | Combustible extra por sector con ERA |
| `pesoRejas` | 0,02 | 0,01–0,05 | Combustible extra por sector con rejas |
| `luzNoche` | 0,35 | 0,2–0,5 | Lo que se ve de noche sin visor |

## 8. Criterios de aceptación (para cuando exista la batalla con accesorios)

- En 100 disparos de ATGM al frontal con ERA, el daño medio queda en el
  30 % ± 3 % del base mientras quede ERA.
- En 1.000 RPG contra rejas intactas, fallan entre el 27 % y el 33 %.
- Una columna de 4 MBT con ERA en 3 sectores gasta un 12 % ± 1 % más de
  combustible por kilómetro.

---

## Anexo: kit de piezas por nación (superado)

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02). Lo que sigue es la
> propuesta anterior: diseños propios por nación con kit de piezas, estilos
> heredados y diseños secretos. Se conserva como historia.

> **Estado: PROPUESTO.** No hay nada programado. El dueño aprobó la idea el
> 2026-09-26 («que los NPC creen sus modelos a su gusto pero inspirándose en
> los que nosotros les demos»; «que los NPC y jugadores crean sus cosas y
> convenciones»; «no aplica solo a los tanques: también a los lanzacohetes,
> aviones y demás armamento») y la recomendación del estudio: kit de piezas,
> el diseño cambia cómo pelea y tiene un precio, la misma acción para NPC y
> jugador, convenciones que salen solas, todo determinista y guardado.
> Corrección suya del mismo día: **los diseños son secretos y no salen en las
> noticias** («no tiene sentido mostrar al rival lo que tiene»). Una nación
> solo conoce un diseño ajeno cuando lo ve de verdad, y solo puede copiar lo
> que conoce.
>
> **Decisiones del dueño (2026-09-26), ya metidas en el documento:**
> 1. El jugador ve los tanques enemigos **tal cual**, con su modelo real,
>    aunque su nación no los conozca. El secreto solo cuenta para los NPC (qué
>    pueden copiar) y para lo que muestran los paneles. La red no filtra el
>    aspecto.
> 2. Se **adelantan los exploradores** como vía de conocimiento. Mientras no
>    lleguen, domina la herencia. No hay vía provisional.
> 3. El orden político **no** empuja el estilo: sale solo del carácter del
>    presidente y de la economía. Las familias de estilo llegan con las
>    alianzas.
> 4. El modelo viejo **convive** con el nuevo; en la fase 2 llega la
>    **modernización pagada**.
>
> Fuentes: `mundo/simulacion.lua` (versión 13 del estado), `mundo/modelos.lua`,
> `tools/blender/` y los commits 03224b9 (franja de la nación) y cf62462
> (tanque A). Las cifras «medidas» salen de la simulación sin ventana (ver
> «Cómo se midió»). Lo que no está medido lo dice.

### 1. Resumen

Cada arma del juego (tanque, lanzacohetes, avión y las que vengan) es un
**modelo**: una combinación de piezas de un kit hecho en Blender, una por
ranura (casco, torreta, cañón…). Las piezas deciden las cifras del modelo en
la simulación (golpe, vida, velocidad, coste, combustible) y cómo se ve (el
juego superpone los sprites prerenderizados de cada pieza y tiñe la franja con
el color de la nación). **Diseñar un modelo** es una acción con coste en
dinero, metal, petróleo y días, igual para un presidente NPC que para un
jugador. Los NPC eligen piezas según su carácter y su economía, se parecen a
sus modelos anteriores, copian lo que les ganó en combate y, cuando haya
alianzas, heredan lo que les comparte un aliado. Así salen escuelas nacionales
y familias de estilo sin que nadie las escriba. Cada nación sabe solo lo que
ha visto: los modelos ajenos son secretos hasta que se encuentran en combate,
los ve un explorador o los comparte un aliado.

### 2. Fantasía del jugador

- **Este tanque es nuestro.** El jugador reconoce la escuela de cada nación
  en el campo de batalla: los cascos pesados de cúpula de un vecino, los
  cazacarros de ruedas de otro. Cada modelo tiene nombre y año: «Lince M2,
  año 3».
- **Aprender del que te gana.** Pierdes una base ante unos tanques pesados que
  no conocías; ahora los conoces y tu siguiente modelo lleva su casco. Al
  enemigo le pasa lo mismo contigo.
- **Nada es gratis.** El cañón largo pega más y cuesta más metal; el casco
  pesado aguanta y bebe petróleo; las ruedas llegan antes y caen antes. Ningún
  diseño gana en todo, y el diseño correcto depende de tu petróleo y de tu
  enemigo.
- **El secreto vale.** Un modelo nuevo que el rival no ha visto es una
  sorpresa; mandarlo al frente es enseñarlo.
- **El mundo parece vivo.** Con los años aparecen familias de tanques en el
  mapa, como bloques de la guerra fría, sin guion.

### 3. Reglas

#### 3.1 Tipos de arma, ranuras y piezas

Un **tipo de arma** es una tabla de datos: sus ranuras, las piezas de cada
ranura, las cifras de cada pieza y su **combinación de referencia**, la que da
exactamente las cifras de hoy en `simulacion.lua`. Tipos previstos:

| Tipo | Clave en la simulación | Ranuras | Referencia (= el arma de hoy) |
|---|---|---|---|
| Tanque | `tanques` | casco, torreta, cañón, extra (0–2), camuflaje | casco medio + torreta en cuña + cañón largo, sin extras, liso |
| Lanzacohetes | `lanzacohetes` | chasis, lanzador, extra (0–1), camuflaje | camión 6×6 + 4 tubos |
| Avión | `aviones` | fuselaje, ala, motor, camuflaje | fuselaje polivalente + ala en flecha + un motor |
| Los que vengan (batería antiaérea, artillería…) | la suya | las que tenga | la unidad que ya exista |

Piezas por tipo. La columna «Fase» dice en qué fase entran (ver §9); las de la
fase 1 son pocas a propósito: Camila y el dueño las modelan.

**Tanque**

| Ranura | Pieza | Fase | Carácter |
|---|---|---|---|
| Casco | ligero | 1 | barato y ágil, poca vida |
| Casco | medio (referencia) | 1 | el de hoy |
| Casco | pesado | 1 | mucha vida, lento, bebe petróleo |
| Casco | de ruedas | 2 | el más rápido y el que menos gasta, frágil |
| Torreta | en cuña (referencia) | 1 | equilibrada |
| Torreta | cúpula | 1 | más vida, algo menos de golpe |
| Torreta | caja | 2 | más golpe (más sitio para la tripulación), menos vida |
| Torreta | baja | 2 | ligera y barata, poco de todo |
| Cañón | corto | 1 | barato, menos golpe y alcance |
| Cañón | largo (referencia) | 1 | el de hoy |
| Cañón | doble | 2 | el que más golpea, caro en metal |
| Extra | blindaje reactivo | 2 | +vida, +metal |
| Extra | bidones | 2 | −consumo efectivo (autonomía), −vida |
| Extra | faldones | 2 | +vida pequeña, barato |
| Camuflaje | liso, manchas, rayas (patrón) × oliva, arena, gris, nieve (color) | 2 | solo aspecto y ocultación ante exploradores (§3.8) |

El tanque A de hoy (cf62462) lleva faldones. En la fase 1 su casco medio se
dibuja con ellos pero cuenta como referencia; los faldones pasan a ser extra
en la fase 2, cuando Camila separe la pieza.

**Lanzacohetes**

| Ranura | Pieza | Fase |
|---|---|---|
| Chasis | camión 4×4 | 3 |
| Chasis | camión 6×6 (referencia, el de hoy) | 3 |
| Chasis | orugas | 3 |
| Lanzador | 4 tubos (referencia) | 3 |
| Lanzador | 8 tubos | 3 |
| Lanzador | 2 tubos pesados | 3 |
| Extra | cabina blindada | 3 |

**Avión**

| Ranura | Pieza | Fase |
|---|---|---|
| Fuselaje | caza | 4 |
| Fuselaje | polivalente (referencia) | 4 |
| Fuselaje | de ataque | 4 |
| Ala | recta | 4 |
| Ala | en flecha (referencia) | 4 |
| Ala | delta | 4 |
| Motor | uno (referencia) | 4 |
| Motor | dos | 4 |

#### 3.2 Regla general: añadir un arma es añadir datos

Para meter un tipo nuevo (o una pieza nueva) se hace esto, y nada más:

1. **Datos de simulación.** Una entrada en la tabla de tipos (propuesta:
   `mundo/armamento.lua`, sin LÖVE, la carga la simulación) con:
   - `ranuras`: lista ordenada; cada una con `obligatoria` (sí/no) y
     `maximo` (1 para casi todas; 2 para los extras del tanque).
   - `piezas[ranura][pieza]`: sus cifras (§4). Las cifras son **sumandos**:
     cada estadística del modelo es la suma de lo que aporta cada pieza, salvo
     velocidad y consumo, que salen del peso (F3, F4).
   - `referencia`: la combinación que reproduce exactamente las constantes de
     hoy. Una prueba automática comprueba que la referencia da las cifras de
     `COSTES`, `FUERZA`, `consumo` y `recuperacion` actuales.
   - `tecnologia`: la de `Simulacion.tecnologias` que lo desbloquea.
2. **Sprites.** Una hoja por pieza y su gemela `_color` (§3.9), con los
   nombres `assets/modelos/<tipo>_<ranura>_<pieza>.png` y
   `..._color.png`. Cada ranura tiene un **punto de encaje fijo** (el mismo
   para todas las piezas de esa ranura), así que no hace falta renderizar
   combinaciones: N piezas son N hojas, no el producto.
3. **Nombres de pieza** en español para la pantalla de diseño.

Si falta el sprite de una pieza, la vista dibuja la pieza de referencia de esa
ranura y deja un aviso en la consola (F3); la simulación no se entera.

#### 3.3 Modelos y unidades en el estado

Todo esto va en `self.estado` y se guarda con `Simulacion:guardar()`:

- `e.modelos[id]`: `{ id, nacion, tipo, nombre, familia, marca, dia,
  piezas = { casco = 'medio', ... }, origen = { via, de } }`. El `id` es
  `'m:' .. nid .. ':' .. k`, con `k` el contador de diseños de esa nación
  (`n.disenos`). `via` es `inicial`, `propio`, `copia` o `aliado`; `de`, el
  modelo del que sale (su predecesor o el copiado).
- `n.serie[tipo]`: el modelo que fabrican las ciudades de esa nación.
- `n.disenando[tipo]`: `{ piezas, hasta, base, via }` mientras dura un
  diseño.
- `n.conoce[id]`: `{ dia, via }` de cada modelo **ajeno** conocido (§3.8).
- `n.derrotas`: lista de los últimos combates perdidos `{ dia, modelos }`
  (máximo 10, se borran los de más de 60 días).
- En cada sitio (ciudad, instalación) y en cada grupo, sus heridos y la cola
  de recuperación: `tanquesPor[id] = cantidad` junto al `tanques` de hoy, que
  sigue siendo el total. Invariante: `tanques == Σ tanquesPor`. Lo mismo
  con `lanzacohetesPor` y `avionesPor` cuando entren esos tipos.

Las cifras de un modelo **no se guardan**: se calculan de sus piezas con la
tabla de datos (caché fuera del estado). Así, ajustar una pieza cambia todos
los modelos que la llevan, también en partidas guardadas.

#### 3.4 Qué hace cada estadística en la simulación

| Estadística | Dónde actúa (hoy es constante) | Regla nueva |
|---|---|---|
| **golpe** | `vidaGrupo` usada como fuerza al golpear en `combatir` y `combatirCiudad`; la fuerza del defensor | Nueva `golpeGrupo(g) = soldados + Σ n·golpe + lanzacohetes·golpe`; las bajas que causa un grupo o un sitio salen de su golpe |
| **vida** | `vidaGrupo` (hoy igual a la fuerza) | `vidaGrupo(g) = soldados + Σ n·vida + …`: umbral de retirada, reparto del daño en `herirGrupo` (por modelo, con la misma fórmula de hoy) |
| **velocidad** | `velocidadEjercito` = 9 000 px/día para todo grupo | Un grupo con tanques va a 9 000 × la velocidad de su modelo más lento; sin tanques, a 9 000 (los soldados siguen a cualquier tanque) |
| **coste** (dinero, metal, petróleo) | `COSTES.tanques`, `defensasCiudad.coste.lanzacohetes`, `COSTES.aviones` | El del modelo de `n.serie[tipo]` |
| **consumo** (petróleo al día) | `consumo.petroleoTanque` 0,03 y `petroleoAvion` 0,1 | `gastoCombustible` suma unidad a unidad por modelo |
| **reparación** | `recuperacion.ritmo` y `precio` | ritmo × vidaRef / vida; precio × dineroModelo / dineroRef (F6) |
| **pérdida en guarnición** | `azar() < 0.4` quita un tanque cuando las bajas pasan de 15 | Pierde uno del modelo con más unidades (empate: `id` menor), con probabilidad 0,4 × vidaRef / vida (máximo 0,8) |
| **alcance** | no existe en la simulación; en la vista los tanques disparan a 150–400 m | Fase 1: solo vista (el tanque dispara a su alcance). Fase 2, propuesta: +10 % de golpe el primer día de combate al bando de más alcance medio |
| **misiles por salva** (lanzacohetes) | `misilesLanzacohetes` = 4 | Los tubos de su lanzador |
| **combate aéreo, carga** (aviones) | 0,45 y 0,3 de derribo; 8 de daño por avión | F9 |
| **ocultación** (camuflaje) | no existe | Probabilidad de que un explorador no identifique el modelo (§3.8) |

#### 3.5 La acción «diseñar»

Comando nuevo de `Simulacion:ejecutar`, el mismo para NPC y jugador:

```
{ tipo = 'disenarModelo', nacion = nid, arma = 'tanques',
  piezas = { casco = 'pesado', torreta = 'cupula', canon = 'largo' },
  nombre = nil }   -- el jugador puede dar nombre; si no, se genera (§3.7)
```

1. **Se rechaza** (devuelve `false`, no cobra nada) si: la nación no tiene
   la tecnología del tipo; alguna ranura obligatoria está vacía o una pieza no
   existe; la combinación es igual a otro modelo **propio** (vivo o no); o no
   alcanza el tesoro, el metal o el petróleo.
2. **Se cobra al empezar**, entero: dinero del tesoro del presidente, metal y
   petróleo del almacén del país (F7). No se devuelve nada.
3. **Dura** `10 + 7 × r` días (F8), con `r` el número de ranuras distintas
   de la combinación conocida más parecida (propia o ajena conocida). Copiar
   tal cual un modelo conocido son 10 días.
4. **Si la combinación es igual a un modelo ajeno conocido**, el nuevo modelo
   queda con `via = 'copia'` y `de` = ese modelo; si es de un aliado que lo
   compartió, `via = 'aliado'`.
5. **Al terminar** (en `economia`, como las mejoras de ciudad), se crea en
   `e.modelos`. El NPC lo pone siempre de serie; el jugador elige con
   `{ tipo = 'fijarSerie', nacion, arma, modelo }` (gratis e inmediato; solo
   modelos propios).
6. **Sin cupos.** Una nación puede tener tantos diseños en curso y tantos
   modelos activos como pague: cada diseño se cobra aparte. Varios diseños a
   la vez del mismo tipo están permitidos. El presidente NPC, por su propia
   lógica (no por regla), lleva uno por tipo a la vez.
7. **Modelo activo** = con alguna unidad en pie, herida o en cola, o de serie.
   No cuesta nada tenerlo. Propuesta de freno natural (perilla `repuestos`):
   cada modelo activo de más de un mismo tipo sube un 2 % el consumo de todas
   las unidades de ese tipo (repuestos distintos).

**Las unidades del modelo viejo conviven** (decidido). No se modernizan
solas: siguen con sus cifras hasta que caen. Lo que se fabrica desde el día
que termina el diseño es del modelo de serie. En la fase 2 llega la
**modernización pagada** (decidido): comando
`modernizar { nacion, ciudad, arma, de, a, cantidad }`, que cambia unidades que
están en una ciudad propia al modelo nuevo pagando la diferencia de las
piezas que cambian (dinero, metal y petróleo de esas piezas) y las mete en la
cola de recuperación de esa ciudad durante ese tiempo (F10).

#### 3.6 Cómo decide un NPC

Todo el azar sale de un flujo propio:
`Ruido.azar(Ruido.hash(Ruido.hash(semilla, zx, zy, 211), dia, indiceTipo))`,
con `zx, zy` los de la nación. **Nunca** del `azar` del día: así, con los
diseños apagados, los demás sorteos no cambian y el mundo sigue idéntico al
de hoy.

**Escuela (al nacer, `registrarZona`).** Cada nación recibe sus pesos de
gusto (F11) de su presidente (agresividad, prudencia) y de su tierra
(escasez de petróleo en los depósitos de su zona). Con ellos puntúa todas las
combinaciones de la fase activa (12 en la fase 1, 48 con el tanque completo)
y se queda con la mejor: es su **modelo inicial** (`via = 'inicial'`), gratis,
porque la nación nace con tanques (1 a 4 por ciudad). Todos los tanques con
los que nace son de ese modelo. Si el presidente cambia (cuando exista), los
pesos no se recalculan: la escuela es de la nación.

**Cuándo diseña (cada día, por tipo desbloqueado, si no tiene uno en
curso).** Una tirada con probabilidad `p` (F12), que sube con:
- **derrotas recientes**: cada combate perdido en los últimos 60 días
  (retirada, grupo aniquilado, instalación tomada) contra unidades de un
  modelo que conoce;
- **escasez de petróleo**: si `reservas` da escasez o crisis de petróleo y
  su serie gasta más que la opción más ahorradora que conoce;
- **edad de su serie**: días desde que se fijó.

Sin tesoro, metal o petróleo para pagarlo, no tira (no se endeuda).

**Qué diseña.** Arma una lista de candidatas:
1. su serie con **una** ranura cambiada, para cada pieza posible (herencia);
2. cada modelo ajeno que **conoce** tal cual (copia);
3. su serie con la pieza de un modelo que le ganó en una ranura (copia parcial);
4. cuando existan alianzas, los modelos compartidos por aliados.

Puntúa cada una con F11 más un premio por parecerse a su serie (herencia) y
otro si lleva piezas de un modelo que le ganó. Si la mejor no supera a su
serie por al menos `margen`, no diseña ese día (no gasta). Si la supera,
con probabilidad `mutacion` cambia una ranura más al azar (la mutación
pequeña) y manda `disenarModelo`. Nunca copia lo que no conoce.

#### 3.7 Nombres

Cada modelo tiene **nombre de familia**, **marca** y **año**:

- **Familia.** Del léxico del orden político de la nación, sorteado con
  `Ruido.hash(semilla, zx, zy, 223 + k)`: Orden del Alba, astros y estaciones
  (Aurora, Cénit, Solsticio, Lucero…); Liga del Estandarte, fieras
  (Lince, Grifo, Oso, Halcón…); Concordia, ríos y montes inventados
  (Varela, Tamarán, Olvesa, Brunal…). Ningún nombre puede coincidir con un
  lugar, un arma o una persona reales; la lista va en `armamento.lua`.
  Esta regla es para las variantes y diseños propios; los modelos base de
  `catalogo-armamento.md` llevan su designación real (decisión P1 de ese
  documento, 2026-09-30).
  Los aviones y lanzacohetes tienen su propio léxico por orden (aves y
  vientos; tormentas).
- **Marca.** Si el modelo nuevo comparte al menos la mitad de sus ranuras con
  su predecesor, hereda su familia y sube la marca: «Lince M1» → «Lince M2».
  Si no, familia nueva y M1. Una copia de un modelo ajeno recibe familia
  propia nueva (la nación lo rebautiza); guarda en `origen` de quién viene.
- **Año.** `1 + floor((dia − 1) / 10)`: el día 400 es el año 40. Se escribe
  «Lince M2, año 40». Un año dura 10 días en todo el juego (decisión de
  el dueño del 2026-09-30, `poblacion.md` §11.3; antes eran 365).
- El jugador puede escribir su propio nombre (máximo 24 caracteres).

Un modelo ajeno conocido **solo por combate** no enseña su nombre: se ve como
«tanque de <nación>, visto el día <d>». Por explorador o aliado se conoce el
nombre.

#### 3.8 Qué sabe cada nación de los diseños ajenos

Sustituye a cualquier noticia de armamento: **ningún diseño sale en el diario
de noticias**, que es común a todos. Cada nación tiene su libro `n.conoce`,
guardado en el estado, que solo crece:

| Vía | Cuándo (determinista) | Qué aprende |
|---|---|---|
| `combate` | Cada día que un grupo combate (`combatir`, `combatirCiudad`), cada bando apunta todos los modelos del otro presentes ese día: los del grupo, los de la guarnición y los de lanzacohetes que lleve. Sin azar: el que pelea, ve | Las piezas, no el nombre |
| `captura` | Un grupo aniquilado deja heridos y averiados en manos del enemigo; una ciudad cedida o conquistada pasa con sus unidades | Las piezas y el nombre (manuales en la chatarra) |
| `aire` | En una incursión con combate aéreo (`cazas > 0`), cada bando apunta el modelo de avión del otro | Las piezas |
| `explorador` | Cuando existan: al volver con su informe, cada modelo presente en el sitio explorado se apunta con probabilidad `1 − ocultación` de su camuflaje, sorteada con el flujo de §3.6 | Las piezas y el nombre |
| `aliado` | Cuando existan alianzas: comando `compartirDiseno { nacion, aliado, modelo }` (gratis). Solo se comparten modelos **propios**, no los ajenos que uno conoce | Todo, y el aliado puede fabricarlo como `via = 'aliado'` sin pagar el diseño entero (F7, factor de licencia) |

Salvas de misiles, golpes a ciudades e interceptores no enseñan nada: el
misil llega de lejos. Los modelos propios se conocen siempre y no se apuntan.

Consecuencia medida con las reglas de hoy (500 días, 6 semillas): el combate
terrestre es raro. La mediana de naciones que ven tanques de **alguna**
nación ajena en combate es 0–1 por nación (máximo 2–3), y el primer
avistamiento llega, en mediana, entre el día 187 y el 293. Sin exploradores
ni alianzas, casi no habrá copias. Decisión del dueño: se adelantan los
exploradores (fase 2) y, hasta entonces, domina la herencia. No hay vía
provisional.

**Lo que ve la cámara** (decidido). El jugador ve cada unidad tal cual, con
su modelo real, la conozca o no su nación: la vista no consulta `n.conoce`.
El secreto cuenta solo para dos cosas: lo que un NPC puede copiar y lo que
dicen los paneles (nombre del modelo, cifras y la pestaña Conocidos, §8).

**Aviso privado.** El jugador sí recibe un aviso de su propio taller
(«Tu diseño Lince M2 está listo») cuando exista su registro propio (ver
interfaz.md, P11); los NPC no generan ningún aviso.

#### 3.9 Color de nación con cualquier combinación

Se mantiene el sistema del commit 03224b9: cada hoja tiene su gemela `_color`
con solo las piezas de material «nación», sombreadas, que el juego dibuja
encima teñidas con `nacion.color`. Reglas para que funcione con cualquier
combinación:

1. **Toda pieza de la ranura portadora lleva franja**: la torreta en el
   tanque, el lanzador en el lanzacohetes (más el techo de cabina del
   chasis), el fuselaje en el avión. Como esa ranura es obligatoria, todo
   modelo tiene color.
2. Cada pieza se dibuja base + `_color` teñida, y luego la siguiente pieza
   encima. El orden de dibujo sale de una tabla por dirección (el cañón va
   detrás de la torreta cuando apunta lejos de la cámara).
3. El camuflaje (fase 2) es otra gemela `_camo_<patrón>` por pieza, teñida
   con el color de camuflaje, que **excluye** la zona de la franja: la franja
   siempre queda a la vista.

#### 3.10 Dos vías de arte: sprites por pieza o mallas 3D

Se está probando el 3D real (mallas en LÖVE; el tanque A en
`assets/modelos3d/tanque_a.lua`). Las reglas de simulación de este documento
no cambian con la vía elegida; solo cambia cómo se dibuja.

- **Vía A, sprites (la descrita arriba):** una hoja prerenderizada por pieza,
  con sus direcciones y sus gemelas `_color` y `_camo`, superpuestas en el
  punto de encaje fijo de cada ranura.
- **Vía B, mallas 3D (si la prueba sale bien):** cada pieza es una malla que
  se encaja en **puntos de montaje** (anillo de torreta en el casco, muñón del
  cañón en la torreta). El material «nación» se tiñe en el sombreador. Las
  piezas admiten **escala ajustable** dentro de un rango (cañón algo más
  largo, casco más ancho): la escala se guarda en el modelo junto a sus
  piezas y, si se adopta, mueve las cifras de forma proporcional (por
  ejemplo, un cañón un 10 % más largo, +10 % de alcance y de metal). Esa
  proporción está por definir y medir. No hace falta renderizar direcciones.

### 4. Fórmulas

Referencias de hoy (`simulacion.lua`): `FUERZA.tanques` 9, `COSTES.tanques`
30 dinero / 3 metal / 1 petróleo, `consumo.petroleoTanque` 0,03,
`recuperacion.ritmo.tanques` 0,5 y `precio.tanques` 22,
`velocidadEjercito` 9 000; lanzacohetes: `fuerzaLanzacohetes` 40,
`misilesLanzacohetes` 4, coste 40/6/2, ritmo 0,4, precio 33; aviones:
`FUERZA.aviones` 15, `COSTES.aviones` 55/4/3, `petroleoAvion` 0,1, 8 de daño
por avión, derribo 0,45 y 0,3.

#### Tabla de piezas del tanque (propuesta)

| Pieza | vida | golpe | dinero | metal | petróleo | peso (t) | motor | gasto |
|---|---|---|---|---|---|---|---|---|
| casco ligero | 4 | 0 | 11 | 1,2 | 0,8 | 20 | 42 | 1 |
| **casco medio** | **7** | 0 | **14** | **1,5** | **1** | **30** | **45** | 1 |
| casco pesado | 10,5 | 0 | 19 | 2,2 | 1,2 | 42 | 48 | 1 |
| casco de ruedas | 2,5 | 0 | 11 | 1 | 0,7 | 16 | 40 | 0,8 |
| **torreta en cuña** | **2** | **2** | **8** | **0,5** | 0 | **12** | — | — |
| torreta cúpula | 2,5 | 1,5 | 8 | 0,5 | 0 | 12 | — | — |
| torreta caja | 1,5 | 2,5 | 8 | 0,5 | 0 | 12 | — | — |
| torreta baja | 1 | 1 | 5 | 0,3 | 0 | 7 | — | — |
| cañón corto (200 m) | 0 | 5 | 5 | 0,6 | 0 | 2 | — | — |
| **cañón largo (350 m)** | 0 | **7** | **8** | **1** | 0 | **3** | — | — |
| cañón doble (250 m) | 0 | 9 | 12 | 1,6 | 0 | 5 | — | — |
| extra blindaje reactivo | 1,5 | 0 | 5 | 0,8 | 0 | 3 | — | — |
| extra bidones | −0,5 | 0 | 2 | 0,2 | 0 | 1 | — | gasto × 0,85 |
| extra faldones | 0,5 | 0 | 2 | 0,3 | 0 | 1,5 | — | — |

En negrita, la referencia: suma vida 9, golpe 9, 30 / 3 / 1, peso 45. Los
extras (fase 2) no están medidos ni comprobados contra dominancia.

**Por qué estos números.** El casco lleva la vida, el peso y el motor (el
chasis es la mayor parte del tanque y de su precio); el cañón, el golpe; la
torreta reparte entre los dos. El petróleo de fabricación va solo en el casco
(es el que lleva motor y depósito). Comprobado con un cálculo aparte (no es
la simulación): de las 48 combinaciones del tanque completo, **ninguna está
dominada** (ninguna es igual o peor en vida, golpe, velocidad y coste total
a la vez que otra), y el valor por coste (vida + golpe entre el coste a 100
días de F5) va de 0,273 (ruedas + baja + corto) a 0,327 (la referencia y sus
vecinas de casco medio): las ligeras pagan su velocidad con menos valor por
moneda, las pesadas su vida con lentitud y combustible.

#### F1. Vida y golpe de un modelo

`vida = Σ vida de sus piezas`, `golpe = Σ golpe de sus piezas`.
Rango (48 combinaciones): vida 3,5–13; golpe 6–11,5.
Ejemplo: pesado + cúpula + largo → vida 10,5 + 2,5 = 13; golpe 1,5 + 7 = 8,5.

#### F2. Vida y golpe de un grupo

`vidaGrupo = soldados + Σ_m n_m·vida_m + lanzacohetes·40`
`golpeGrupo = soldados + Σ_m n_m·golpe_m + lanzacohetes·40`
Las bajas que causa el grupo cada día: `floor(golpeGrupo × azar(0,06; 0,12))`
(hoy: `vidaGrupo`). Las que causa un sitio: igual con sus `soldados +
Σ n·golpe (+ lanzacohetes·40) × (1 + fortificación)` en instalaciones.
Ejemplo: 200 soldados y 10 tanques pesado + cúpula + largo → vida
200 + 130 = 330, golpe 200 + 85 = 285. Con 10 de referencia: 290 y 290.

#### F3. Velocidad

`velocidad = clamp(motor_casco / peso_total, 0,6; 1,5)`, con
`peso_total = Σ peso`. Velocidad de un grupo con tanques:
`9 000 × min(velocidad de sus modelos)` px/día.
Rango: 0,81 (pesado + caja + doble) a 1,5 (ruedas + baja + largo).
Ejemplo: ligero + cuña + largo: 42 / (20 + 12 + 3) = 1,20 → 10 800 px/día.

#### F4. Consumo de petróleo al día (mantenimiento)

`consumo = 0,03 × peso_total / 45 × gasto_casco (× gasto de extras)`.
Rango: 0,013 (ruedas + baja + corto) a 0,039 (pesado + cualquier torreta de
12 t + doble). Ejemplo: pesado + cúpula + largo: 0,03 × 57 / 45 = 0,038 al
día; 60 tanques así gastan 2,28 petróleo al día frente a 1,8 de referencia.

#### F5. Coste total a 100 días (solo para comparar y para que el NPC puntúe)

`coste100 = dinero + 3·metal + 4·petróleo + 400·consumo` (3 y 4 son
`Simulacion.dinero.precio`). Referencia: 30 + 9 + 4 + 12 = 55. Rango:
34,8–74,1.

#### F6. Reparación

`ritmo_m = ritmo_ref × vida_ref / vida_m`; `precio_m = precio_ref × dinero_m /
dinero_ref`. Tanque: ritmo 0,5 × 9 / vida por día y nivel; precio 22 ×
dinero / 30. Ejemplo: pesado + cúpula + largo (vida 13, dinero 35): 0,35 al
día por nivel; 25,7 por unidad acelerada.

#### F7. Coste de diseñar

`dinero = 5 × dinero_ref_del_tipo`, `metal = 10 × metal_ref`,
`petróleo = 10 × petróleo_ref`. Tanque: 150 dinero, 30 metal, 10 petróleo.
Lanzacohetes: 200 / 60 / 20. Avión: 275 / 40 / 30. Con `via = 'aliado'`, se
multiplica por `licencia` (0,5).

Contra lo medido (mediana entre naciones, rango de las 6 semillas): el
tesoro vale 132–168 el día 15, 277–344 el día 30, 602–836 el día 60,
1 224–1 620 el día 100 y 25 822–32 236 el día 500. El petróleo del almacén,
1–3 el día 15 y 30, 0–108 el día 60. **Lo que frena al principio es el
petróleo; a partir del día 100 el dinero no frena nada** (es el hueco 3 del
README: no hay escasez). No propongo escalar el precio con el tesoro: sería un
límite artificial.

#### F8. Duración del diseño

`dias = 10 + 7 × r`, con `r` = ranuras distintas de la combinación conocida
más parecida. Tanque en la fase 1 (3 ranuras): de 10 (copia exacta) a 31
(todo nuevo); una ranura cambiada, 17.

#### F9. Aviones (fase 4, sin medir)

`pDerribo(caza → atacante) = clamp(0,45 × combate_caza / combate_atacante;
0,1; 0,8)`; `pDerribo(atacante → caza) = clamp(0,3 × combate_atacante /
combate_caza; 0,1; 0,8)`; daño por avión que llega = `carga`.
Referencia: combate 1, carga 8, 55 / 4 / 3, consumo 0,1. Piezas propuestas:
fuselaje caza (combate +0,15, carga 5, 20 / 1,5 / 1), polivalente (0, 8,
25 / 2 / 1,5), ataque (−0,15, 12, 32 / 2,8 / 2); ala recta (combate 0,85,
carga +2, 8 / 0,8 / 0,4), flecha (1, 0, 10 / 1 / 0,5), delta (1,1, −1,
13 / 1,2 / 0,6); motor uno (consumo 0,1, velocidad 1, 20 / 1 / 1), dos
(consumo 0,16, combate +0,1, velocidad 1,15, 32 / 1,6 / 1,6). `FUERZA` de
un avión para `Simulacion:fuerza` = 15 × (carga / 8 + combate) / 2.

#### F10. Lanzacohetes (fase 3, sin medir) y modernización

Chasis 4×4 (vida 20, 15 / 2 / 1, velocidad 1,2), **6×6 (28, 20 / 3 / 1,5,
1)**, orugas (38, 28 / 4,5 / 2, 0,85, consumo 0,01 al día); lanzador **4 tubos
(vida 12, 4 misiles, 20 / 3 / 0,5)**, 8 tubos (10, 8 misiles, 32 / 5 / 0,5),
2 tubos pesados (12, 2 misiles que gastan 2 cada uno, daño × 2, se
interceptan con 0,6 en vez de 0,72; 30 / 4 / 0,5). `misilesListos = min(misiles,
Σ lanzacohetes × tubos)`. El tope de lanzacohetes por nivel de ciudad no
cambia: 8 tubos es más fuego por plaza, a más precio.
Modernización (fase 2): coste = Σ (coste de las piezas nuevas que cambian);
días = los de recuperación de una unidad de ese modelo en esa ciudad.

#### F11. Gusto de una nación (puntuación de una combinación)

```
U(d) = wG·golpe/9 + wV·vida/9 + wR·velocidad − wC·coste100/55
       + wH·parecido(d, serie) + wK·[lleva piezas de un modelo que le ganó]
       + ruido
wG = 0,5 + agresividad        (0,6–1,5)
wV = 0,5 + prudencia          (0,6–1,5)
wR = 0,2 + 0,4 × agresividad  (0,24–0,6)
wC = 1,5 + 1,0 × escasez      (1,5–2,5)
escasez = clamp(1 − 3 × campos petrolíferos / depósitos de su zona; 0; 1)
          (al nacer); en cada diseño, +0,5 si `reservas` da escasez o crisis
          de petróleo (máximo 1)
wH = 0,6   parecido = ranuras iguales / ranuras
wK = 0,4
ruido = uniforme en [−0,25; 0,25] por combinación, del flujo de §3.6
```
Ejemplo: agresividad 0,8, prudencia 0,3, escasez 0: pesado + cúpula + largo
da 1,3·8,5/9 + 0,8·13/9 + 0,52·0,84 − 1,5·66,1/55 = 1,228 + 1,156 + 0,437
− 1,803 = 1,018; ligero + cuña + largo da 1,3·1 + 0,8·6/9 + 0,52·1,2 −
1,5·47,6/55 = 1,3 + 0,533 + 0,624 − 1,298 = 1,159: este presidente prefiere
tanques ligeros (antes del ruido).

Calibración (cálculo aparte con 20 000 presidentes al azar y escasez uniforme,
no es la simulación): con `wC` 1,5 y ruido 0,25, en la fase 1 salen las 12
combinaciones como modelo inicial, la más frecuente con el 15 %; con el
tanque completo salen las 48, la más frecuente con el 8 %. Con ruido 0,1 la
más frecuente sube al 21 % (fase 1). Falta medir cuántos campos petrolíferos
tiene de verdad una zona (media y rango): la escasez uniforme es una suposición.

#### F12. Probabilidad de diseñar hoy (NPC)

```
p = min(0,05; 0,005 + 0,02 × derrotas60 + 0,01 × [escasez de petróleo y hay
        opción más ahorradora conocida] + 0,00002 × díasDeSerie)
```
Ejemplo: sin derrotas, serie de 200 días: 0,005 + 0,004 = 0,009 al día
(≈ uno cada 110 días si puede pagar y la mejor candidata supera el margen).
Con dos derrotas recientes: 0,049.
Esperado en 500 días: de 3 a 8 diseños por nación. **Sin medir.**

### 5. Casos límite

- **La nación no tiene la tecnología `tanques`.** Tiene su modelo inicial (nace
  con tanques), no fabrica ni diseña hasta tenerla (día 10–30 medido; mediana
  14–15).
- **Diseño en curso y la nación muere.** El diseño se pierde con ella. Sus
  modelos siguen en `e.modelos` (historia) y quien los conocía los sigue
  conociendo.
- **Unidades de otra nación en mis sitios.** Una ciudad conquistada o cedida
  pasa con sus unidades y su modelo: el nuevo dueño las usa, las repara con
  las cifras de ese modelo y apunta el modelo con `via = 'captura'`. Nunca
  fabrica un modelo ajeno: para eso tiene que copiarlo (diseñar, pagar).
- **Dos naciones llegan a la misma combinación.** Son modelos distintos (id,
  nombre). Conocer uno no da el otro.
- **Copiar una combinación que ya es propia.** Se rechaza (§3.5, paso 1).
- **La nación tiene de serie un modelo cuyo coste no alcanza hoy.** No fabrica
  ese día (como hoy con `puede`). No cambia de serie sola.
- **Se reduce el petróleo a 0 mientras diseña.** El diseño ya está pagado y
  sigue. Las unidades se quedan sin combustible como hoy (`sinCombustible`).
- **Grupo con varios modelos.** Va a la velocidad del más lento; cada modelo
  recibe su parte de daño con la fórmula de `herirGrupo` de hoy, modelo a
  modelo en orden de `id`.
- **Pérdida en guarnición con varios modelos.** Se quita del que más unidades
  tenga; a igualdad, el de `id` menor.
- **Partida guardada de la versión 13.** Al cargar, cada nación recibe su
  modelo inicial (se calcula igual que al nacer, del mismo flujo de azar) y
  todas sus unidades pasan a ese modelo. `n.conoce` empieza vacío.
- **Modelo sin unidades y que no es de serie.** Deja de estar activo; sigue en
  `e.modelos` y en los libros de quien lo conoce. No se borra nunca.
- **El jugador da un nombre ya usado por otro modelo suyo.** Se rechaza el
  nombre y se usa el generado.
- **Pieza nueva sin sprite.** Se dibuja la de referencia de su ranura (§3.2).
- **Diseños desactivados** (perilla `activo = false`). Toda nación tiene solo
  la referencia, no se tira nada del flujo de §3.6 y el estado de las
  reglas de hoy queda idéntico (criterio A1).

### 6. Dependencias

- **economia.md** (decidido el 2026-09-30): el coste, el consumo de
  petróleo y la vida de cada modelo entran por sus F1, F9 y F11; allí los
  vehículos no se destruyen (se averían y se reparan) y la munición es lo
  que se gasta.
Este sistema depende de:
- **instalaciones-y-economia.md**: tesoro, almacén, `fabricarEnCiudad`,
  `gastoCombustible`, `reservas`, tecnologías. Ese documento tiene que nombrar
  que el coste de fabricar y el combustible salen del modelo de serie.
- **guerra.md**: `combatir`, `combatirCiudad`, `incursion`, `salva`,
  velocidad de los grupos. Tiene que nombrar golpe y vida por modelo y que el
  combate apunta lo visto en `n.conoce`.
- **retirada-y-recuperacion.md**: `vidaGrupo`, `herirGrupo`, colas y precio
  de acelerar por modelo (F6). Tiene que nombrar que la vida sale del modelo.
- **naciones-y-politica.md**: agresividad, prudencia, orden político
  (léxico de nombres), nacimiento en `registrarZona`. Tiene que nombrar la
  escuela de armamento.
- **interfaz.md**: la mesa de diseño (§8), el pendón de ciudad y de grupo
  (nombre del modelo), el aviso privado.
- **Exploradores** (adelantados por el dueño para esta necesidad) y
  **alianzas** (decididas, sin programar ni documentar aún): son dos de las
  vías de §3.8; las alianzas son además de donde salen las familias de estilo. Cuando tengan documento,
  tienen que nombrar este.
- **Arte** (`tools/blender/`, `mundo/modelos.lua`): kit de piezas, hojas
  `_color` y `_camo`.

- **catalogo-armamento.md** (decidido por el dueño el 2026-09-30): los
  modelos reales son los diseños base y el kit deriva de ellos variantes
  secretas, **más adelante** (P5 de ese documento); el modelo inicial de cada
  escuela saldrá de la era 1 (§3.7 de ese documento). Los modelos base se
  llaman por su designación real (P1); la regla de nombres de §3.7 de este
  documento sigue para las variantes.

Dependen de este sistema: `poblacion.md` (un solo calendario: el «año» de
§3.7 es el año de 10 días de la población), el futuro documento del jugador (sus comandos
`disenarModelo`, `fijarSerie`, `modernizar`, `compartirDiseno`) y el
protocolo de red (§9).

### 7. Perillas de ajuste

| Perilla | Valor | Rango seguro | Qué cambia al moverla |
|---|---|---|---|
| `activo` | sí | sí/no | No: el mundo es el de hoy (solo referencia) |
| Cifras de cada pieza (tabla de §4) | ver tabla | ±30 % | Qué combinaciones salen; revisar que ninguna quede dominada |
| `limiteVelocidad` | 0,6–1,5 | 0,5–1,8 | Cuánto antes llegan los grupos ligeros |
| `disenoDinero` / `Metal` / `Petroleo` (múltiplos de F7) | 5 / 10 / 10 | 3–10 / 5–20 / 5–20 | Cuántos diseños hay al principio (el petróleo es lo que frena) |
| `diasBase`, `diasRanura` | 10, 7 | 5–20, 4–12 | Lo que tarda un modelo en llegar al frente |
| `licencia` | 0,5 | 0,2–1 | Cuánto ayuda un aliado |
| `pBase` | 0,005 | 0,002–0,01 | Diseños por nación sin guerra |
| `pDerrota` | 0,02 | 0,01–0,05 | Qué deprisa reacciona a las derrotas |
| `pEdad` | 0,00002 | 0–0,0001 | Renovación por vejez |
| `pMax` | 0,05 | 0,02–0,1 | Tope de la tirada diaria |
| `margen` | 0,05 | 0–0,2 | Más alto: menos modelos, cambios más grandes |
| `mutacion` | 0,15 | 0–0,3 | Rarezas: más alto, escuelas menos reconocibles |
| `wH` (herencia) | 0,6 | 0,3–1 | Más alto: escuelas más marcadas, copias más raras |
| `wK` (copia) | 0,4 | 0,2–0,8 | Cuánto pesa lo que te ganó |
| `ruido` | 0,25 | 0,1–0,4 | Variedad de modelos iniciales (medido en F11) |
| `repuestos` | 0,02 | 0–0,05 | Cuánto cuesta tener muchos modelos activos del mismo tipo |
| `ventajaAlcance` (fase 2) | 0,1 | 0–0,2 | Premio al bando de más alcance el primer día |
| `ocultacion` por camuflaje (fase 2) | liso 0, manchas 0,15, rayas 0,1 | 0–0,4 | Cuántos informes de explorador fallan |

### 8. Qué ve el jugador: la mesa de diseño

Propuesta breve en el estilo «Estandarte colgante» (interfaz.md). Es una
**ventana grande** («mesa» centrada de 1200×760, 960×608 a 1280×720) con
cabecera de pendón y la franja del país; se cierra con Esc y pausa sin red.
Tecla por asignar. Se compone en el editor (Diego) como el resto.

- **Pestañas (C8):** Modelos · Taller · Conocidos.
- **Modelos.** Una fila por modelo propio: miniatura (el sprite compuesto,
  dirección 3/4), «Lince M2 · año 2», unidades vivas / heridas, una marca
  `bronceClaro` en el de serie. Botón secundario «Poner de serie».
- **Taller.** Izquierda: una columna por ranura con tarjetas de pieza (icono
  de 64 px, nombre en SC 14); la elegida con contorno `bronceClaro`. Centro:
  el modelo compuesto, 240 px, girando despacio, con la franja del país.
  Derecha: filas dato-valor (C3) de golpe, vida, velocidad, consumo y coste,
  con la diferencia contra la serie (▲ `olivaClaro`, ▼ `granateTexto`,
  siempre con el número). Abajo: precio del diseño (dinero, metal, petróleo,
  días) y botón principal «Encargar diseño»; si no se puede, la razón debajo
  («Faltan 6 petróleo», «Ya tienes este modelo: Lince M1»). Un diseño en
  curso sale como aviso de información (C6): «Diseñando Lince M3 · 12 días».
- **Conocidos.** Por nación (punto de su color, C10): cada modelo ajeno que
  sabe, con su miniatura, nombre o «tanque de <nación>», vía y día
  («Visto en combate · día 212»). Botón «Copiar» que lleva sus piezas al
  Taller. Lo que no se conoce no aparece: no hay «?» por modelo.
- **En el mapa:** el pendón de grupo y el de ciudad dicen el modelo de cada
  unidad («6 Lince M2 · 2 Lince M1») solo si es propio o conocido.

### 9. Orden de trabajo por fases

**Fase 1: tanques con 3 ranuras (la más pequeña jugable).**
Casco ligero / medio / pesado, torreta cuña / cúpula, cañón corto / largo:
12 combinaciones. Sin extras ni camuflaje. Vía de conocimiento: combate y
captura. Sin pantalla del jugador (aún no existe): el NPC diseña solo y el
observador lo ve en los pendones.
- **Camila:** separar el tanque A en piezas con el punto de encaje fijo por
  ranura (anillo de torreta a la misma altura en los tres cascos, muñón del
  cañón en el mismo punto en las dos torretas); modelar casco ligero, pesado,
  torreta cúpula y cañón corto; franja en las dos torretas. Hojas: casco 16
  direcciones; torreta y cañón 32 direcciones, el cañón con cuadro de
  retroceso; todas con `_color`. 7 piezas, 14 hojas.
- **Andrés:** `mundo/armamento.lua` con la tabla del tanque y su prueba de
  referencia; `e.modelos`, `n.serie`, `n.disenando`, `n.conoce`,
  `n.derrotas`, `tanquesPor` en sitios, grupos, heridos y colas (con su
  invariante); `golpeGrupo` y `vidaGrupo` por modelo; velocidad, consumo,
  coste, reparación y pérdida en guarnición por modelo; comandos
  `disenarModelo` y `fijarSerie`; lógica NPC (F11, F12) con su flujo de azar
  propio; nombres; migración de la versión 13 a la 14. Mateo puede escribir la
  tabla de datos y la prueba de referencia bajo su revisión (no hace commits).
- **Valeria:** `Modelos.dibujarTanque` compone casco + torreta + cañón por
  piezas, cada una con su `_color` teñida y la tabla de orden por dirección;
  pieza de referencia si falta un sprite; alcance de disparo en la vista
  según el cañón; nombre del modelo en los pendones.
- **Tomás:** nada de red todavía; revisar que el estado nuevo se serializa en
  orden fijo y medir cuánto crece la partida guardada.
- **Elena:** criterios A1–A9.

**Fase 2: el tanque completo y la mesa del jugador.**
Casco de ruedas, torretas caja y baja, cañón doble, extras, camuflaje
(`_camo`), `modernizar`, ventaja de alcance y **exploradores** como vía de
conocimiento (adelantados por decisión del dueño). Camila: 6 piezas más y las
máscaras de camuflaje (3 patrones por pieza). Valeria: camuflaje y extras en
la composición, miniaturas para la mesa. Diego: la mesa compuesta en el
editor. Andrés: extras, modernización, ocultación y los exploradores (su
viaje, su informe y la vía `explorador` de §3.8; necesitan su propio
documento de diseño, que haré yo).

**Fase 3: lanzacohetes.** Camila: chasis 4×4 y orugas, lanzadores de 8 y 2
tubos, con la postura de disparo (7 posturas) y la marcha de hoy por pieza.
Andrés: `lanzacohetesPor`, tubos por salva, daño e interceptación de los
pesados. Valeria: composición con el contenedor que pivota.

**Fase 4: aviones.** Camila: 3 fuselajes, 3 alas, 2 motores. Andrés: F9 y la
vía `aire`. Valeria: sprites de avión compuestos (hoy los aviones no tienen
sprite de Blender).

**Fase 5: aliados y red.** Cuando existan alianzas, `compartirDiseno` y la
licencia (Andrés); con ellas aparecen las familias de estilo. **Tomás:** el
aspecto de las unidades viaja sin filtrar (decisión del dueño: el jugador
las ve tal cual). Los paneles del cliente solo enseñan nombre y cifras de los
modelos propios y de los que están en `n.conoce` de su nación.

### 10. Criterios de aceptación

Con el arnés sin ventana, 16 zonas, 500 días, las 6 semillas de siempre
(4242, 1, 7, 99, 12345, 2026):

- **A1. Equilibrio de hoy intacto.** Con `activo = false`, el estado final es
  idéntico, campo a campo, al de la versión de hoy en todos los campos que ya
  existían. Con diseños activos pero todas las naciones forzadas a la
  referencia, idem.
- **A2. Referencia exacta.** La prueba de datos da, para la referencia de cada
  tipo, las constantes de hoy (tanque: vida 9, golpe 9, 30 / 3 / 1, 0,03 al
  día, velocidad 1, ritmo 0,5, precio 22).
- **A3. Sin dominancia.** Ninguna combinación de la fase activa es igual o
  peor en vida, golpe, velocidad y `coste100` que otra (hoy: 0 de 48).
- **A4. Variedad.** Modelo inicial: en las 6 semillas aparecen al menos 8 de
  las 12 combinaciones de la fase 1 y ninguna pasa del 30 % de las naciones.
- **A5. Ritmo.** Entre 2 y 8 diseños por nación viva en 500 días (mediana).
- **A6. Escuela.** Cada modelo nuevo comparte con su predecesor al menos 2 de
  3 ranuras en el 60 % o más de los casos.
- **A7. Secreto.** El 100 % de las copias (`via = 'copia'`) tiene su modelo
  en `n.conoce` antes del día en que empezó el diseño; ninguna nación tiene en
  `n.conoce` un modelo sin un suceso que lo explique (se registra la vía);
  ninguna noticia del diario contiene el nombre de un modelo.
- **A8. Mundo parecido.** Guerras declaradas, tomas, bases y extracción
  quedan dentro de ±15 % de los rangos medidos hoy (README y «Cómo se midió»);
  tanques fabricados por nación, mediana entre 40 y 120 (hoy 56–90); días
  sin combustible, por debajo del 10 % de los días-nación (hoy 1,1–6,1 %).
- **A9. Determinismo y coste.** Dos corridas iguales y guardar/cargar a mitad
  dan el mismo estado; el tiempo por día sube como mucho un 10 % y la partida
  guardada, como mucho un 10 %.

### 11. Preguntas abiertas para el dueño

Ninguna. Las cuatro que había (qué ve la cámara, pocas copias al principio,
orden político y modelo viejo) las decidió el dueño el 2026-09-26: ver la
cabecera del documento.

### Cómo se midió

Arneses fuera del repo, en la carpeta temporal de la sesión
(`scratchpad/arma/`): `medir.lua` y `medir2.lua` envuelven `fabricarEnCiudad`,
`enviarDefensas`, `combatir`, `combatirCiudad`, `destruirInstalacion` y
`retirar` para contar, sin cambiar reglas; `piezas.lua` calcula las 48
combinaciones y la dominancia; `eleccion.lua` es la calibración de F11 (azar
de Lua, **no** la simulación). Se corren con `luajit medir.lua <semilla> 500`.
Simulación de hoy (versión 13, HEAD cf62462 más los cambios sin commitear del
árbol), 16 zonas (−2..1), 500 días.

| Medida (500 días) | Rango en 6 semillas |
|---|---|
| Tanques fabricados en todo el mapa | 988–1 300 |
| Tanques fabricados por nación, mediana | 56–90 |
| Tanques por nación el día 500, mediana | 54–78 |
| Día de la tecnología `tanques`, mediana | 14–15 (mínimo 10) |
| Día de la tecnología `aviones`, mediana | 55–62 |
| Aviones fabricados en todo el mapa | 568–824 |
| Parte de la fuerza de una nación que son tanques (día 500), mediana | 4–5 % |
| Días-nación sin combustible | 1,1–6,1 % |
| Combates terrestres en el mapa / con tanques del atacante | 30–164 / 19–104 |
| Naciones ajenas cuyos tanques ve cada nación en combate, mediana (máximo) | 0–1 (2–3) |
| Día del primer avistamiento en combate, mediana | 187–293 |
| Tesoro, mediana, días 15 / 30 / 60 / 100 / 500 | 132–168 / 277–344 / 602–836 / 1 224–1 620 / 25 822–32 236 |
| Petróleo del almacén, mediana, días 15 / 60 / 500 | 2–3 / 0–108 / 3–161 |

Que los tanques sean el 4–5 % de la fuerza medida por `Simulacion:fuerza`
(los soldados pesan casi todo) quiere decir que un error en las cifras del
tanque mueve poco el equilibrio general; también quiere decir que, con las
reglas de hoy, el diseño del tanque decide poco las guerras. Si el dueño
quiere que el armamento pese más, eso es otro ajuste (del peso de los
soldados), fuera de este documento.

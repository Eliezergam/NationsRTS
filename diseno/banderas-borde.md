# Banderas del borde

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Estado: **decidido el 2026-09-30 (ver «Decisiones»), salvo el panel de tropas (3.13), a la espera de la referencia del dueño.** Sin programar. Pedido del dueño (2026-09-30), con sus
palabras: «que cada borde sea una bandera; si esa bandera del borde la
destruyen, entonces en el nuevo borde se crea otra bandera para que pueda ser
atacada también». Aclaración suya del mismo día: «las banderas solo son para
tomar territorio, no almacenan nada; son como las banderas de las alianzas en
Warpath». Segunda precisión suya (misma fecha, referencia Warpath y Rise of
Kingdoms): a una bandera se le pueden mandar soldados para protegerla, con un
**límite de guarnición**; esa guarnición son grupos del ejército estacionados
allí, que siguen siendo de su ciudad; y hace falta un **panel de tropas** con
todas las tropas que están fuera y un botón para que regresen.

Documento para Andrés (simulación) y Valeria (mundo y vista). Cambia la parte
de banderas de [territorio-y-capitales.md](territorio-y-capitales.md) (3.7 y
3.9). Lo marcado «hoy» es lo que hace el código en la versión 25 (HEAD 536f301);
todas las cifras están medidas con la simulación sin ventana (ver «Cómo se
midió»).

---

## 0. Lo que dice la medición antes de diseñar

El problema de escala que midió Andrés se confirma:

| Semilla | Naciones | Banderas día 100 / 300 / 500 | Por nación y día | Guardado día 500 | De ello, banderas | Destruidas por ataque en 500 días |
|---|---|---|---|---|---|---|
| 1 | 22 | 553 / 1 998 / 3 459 | 0,31 | 1 319 KB | 787 KB | 3 |
| 7 | 22 | 617 / 2 182 / 3 458 | 0,31 | 1 325 KB | 785 KB | 1 |
| 42 | 21 | 612 / 2 007 / 3 274 | 0,31 | 1 245 KB | 743 KB | 2 |
| 1234 | 20 | 474 / 1 813 / 3 038 | 0,30 | 1 205 KB | 690 KB | 0 |

**Pero borrar solo las banderas interiores no lo arregla.** Entre el 93 y el
97 % de las banderas terminadas **ya tocan el borde** en todos los cortes y
semillas (día 500: 3 271 de 3 455, 3 281 de 3 451, 3 095 de 3 265 y 2 866 de
3 034). La IA planta en cadena hacia los yacimientos, así que el territorio
crece en tiras de uno o dos bloques de ancho, sin interior. Lo comprobé con un
prototipo que, cada día, quita el objeto de las banderas que no tocan el borde
(semilla 7): el día 500 quedan **3 409 en vez de 3 458** (−1,4 %) y el guardado
no baja (1 330 KB).

Además, las naciones casi no se tocan: el día 500, de los lados de celda del
borde, 0–74 dan a otra nación, 18 000–21 000 a tierra sin dueño y
24 700–27 900 a **agua** sin dueño (hoy se planta en cualquier terreno). El
territorio crece sin freno porque no choca con nadie en 500 días.

Por eso este documento propone que la bandera del borde **no sea un objeto
guardado**, sino algo que sale de las celdas: solo se guarda la que tiene algo
distinto de lo normal (en obra, dañada o atacada). Así se cumple la regla de
El dueño y el guardado y el tiempo dejan de crecer con las banderas. Lo que sí
sigue creciendo es **la longitud del borde**, porque crece el territorio: eso
es una decisión aparte (pregunta P7).

## 1. Resumen

El territorio sigue siendo lo que es hoy: celdas de 500 px con un dueño o
ninguno. El mundo se parte en **bloques de bandera** de 6 × 6 celdas (3 000 px,
300 m), alineados a la rejilla, los mismos de
[rebeldes-y-niveles.md](rebeldes-y-niveles.md) (`bx = floor(cx / 6)`). Cada
bloque que tiene **tierra de bandera** de una nación en su borde lleva **una
bandera** de esa nación: es lo único que se ataca para quitarle tierra. Los
bloques interiores no llevan nada: son territorio sin objeto. Cuando una
bandera del borde cae, la tierra de bandera de su bloque queda sin dueño y los
bloques que quedan expuestos pasan a ser borde y muestran su bandera, con la
vida entera, sin coste y sin tropa. Una bandera **no guarda nada**: ni
recursos, ni producción, ni obras. Solo marca y toma territorio. Lo que sí
admite es una **guarnición**: grupos del ejército que el dueño estaciona allí,
con un tope, y que siguen siendo suyos (3.12). Un **panel de tropas** muestra
todo lo que está fuera y lo hace regresar andando (3.13).

## 2. Fantasía del jugador

- «Mi país tiene un frente: para llegar a mi mina del interior, el vecino
  tiene que arrancar bandera tras bandera, y yo lo veo venir.»
- «Tiro una bandera suya y detrás aparece otra. Avanzo bloque a bloque; no
  hay atajos.»
- «Me avisan de que viene un ejército contra mi bandera del paso: mando una
  guarnición antes de que llegue. Cuando pasa el peligro, la traigo a casa.»
- «Abro el panel de tropas, veo todo lo que tengo fuera y con un clic lo
  traigo de vuelta; tarda lo que tarda el camino.»
- «En el mapa veo mi borde con sus banderas; el interior está limpio.»

## 3. Reglas

### 3.1 Qué es el borde

1. **Tierra de bandera** de la nación N: una celda de N que **no** está dentro
   del bloque de una ciudad suya (20 × 20) ni de un campamento suyo terminado
   (12 × 12). Es la tierra que existe gracias a las banderas. La tierra de la
   capital y de los campamentos no lleva bandera: se defiende con esos sitios,
   como hoy.
2. **Celda de borde** de N: una celda de N con al menos un vecino **por un
   lado** (no en diagonal) que no es de N. Ese vecino puede ser:
   - tierra sin dueño,
   - agua sin dueño (propuesta: cuenta igual, pregunta P6),
   - una celda de otra nación.
   Un hueco sin dueño dentro del territorio también hace borde a su alrededor.
3. **Bloque de borde** de N: un bloque de bandera que contiene al menos una
   celda que es a la vez tierra de bandera de N y celda de borde de N.
4. **Bandera del borde:** cada bloque de borde de N tiene exactamente una
   bandera de N. Su id sale del bloque: `'f:' .. nid .. ':' .. bx .. ',' .. by`.
   Si en un bloque hay tierra de dos naciones, cada una tiene la suya.
5. Un bloque que no es de borde no tiene bandera. No hay objeto, ni icono, ni
   mantenimiento aparte (ver 3.6).

### 3.2 Lo que se guarda

- Una bandera del borde **con todo normal** (vida 100, terminada, sin ataque
  en los últimos 3 días) **no se guarda ni se recorre**: se deduce de las
  celdas.
- Se guarda solo la que tiene estado: `e.banderas[nid]['bx,by'] = { salud,
  progreso, atacadaDia, atacadaPor, inicio }`. Cuando vuelve a vida 100, sin
  obra y sin ataque en 3 días, su entrada se borra.
- El conjunto de bloques de borde de cada nación es un índice fuera del
  estado, como `trozos`: se rehace de las celdas al cargar y se corrige cuando
  cambia una celda (esa celda solo afecta a su bloque y a los 4 vecinos).
- **Quitar de las banderas** (aclaración del dueño): hoy cada bandera es una
  instalación con `soldados`, `tanques`, `misiles`, `interceptores`,
  `aviones`, `lanzacohetes` y `fortificacion`, todos a 0 al plantarla. La
  propuesta los borra. Además:
  - el comando `enviarGrupo` con misión `refuerzo` hacia una bandera se
    rechaza (`'destino'`). Hoy **se acepta**: `refuerzo` suma los soldados y
    los tanques a la bandera y deja allí su munición, pero la bandera no pelea
    con ellos (`golpeSitio` da 0 en banderas). Para proteger una bandera está
    la guarnición (3.12), que son grupos, no campos de la bandera;
  - `destruirInstalacion` ya no llama a `remolcarGuarnicion` para banderas.

### 3.3 Atacar una bandera del borde

1. Se ataca como hoy: `enviarGrupo`, misión `atacar`, `objetivo` = id de la
   bandera. Vale si el bloque es de borde de su dueño en el día de la orden y
   si el trozo de territorio donde está toca el territorio del atacante
   (`tocaTrozo`, regla de hoy).
2. Al empezar el ataque, la bandera pasa a guardarse (3.2).
3. Si tiene guarnición, la batalla es contra ella (3.12.4) y la bandera no
   pierde vida mientras quede algún grupo defendiéndola. Sin guarnición, cada
   día de batalla pierde vida con F7 de
   [territorio-y-capitales.md](territorio-y-capitales.md): `ΔV = min(100, G ×
   100 / 300)`, × 1,5 si está en obra. Sin cambios.
4. Si deja de ser de borde mientras la atacan (el dueño planta delante), el
   ataque acaba: el grupo vuelve (`volver`) sin victoria. La bandera guarda
   su vida y se repara como hoy.
5. **A 0 cae:**
   - la tierra de bandera de N **dentro de ese bloque** queda sin dueño (hoy:
     `soltarBloque`, P2). Las celdas de la capital y de los campamentos no se
     tocan;
   - el atacante anota la victoria y vuelve;
   - noticia al dueño, como hoy: «X arranca una bandera de N en (x, y)»;
   - los bloques de N que quedan con celdas de borde nuevas pasan a ser de
     borde y **tienen bandera desde ese momento** (3.5).
6. Los misiles también le quitan vida (`danarInstalacion`), sin
   fortificación.

### 3.4 Lo que había en la tierra que se pierde o que queda dentro

Una bandera no guarda nada, así que no hay nada que mover al quedar interior.
Lo que está **sobre** la tierra no depende de la bandera:

| Qué | Si su bloque pasa a interior | Si su bloque cae |
|---|---|---|
| Soldados, vehículos, munición | No están en la bandera: siguen en su ciudad, su campamento, su base o su grupo | Igual. Los grupos que pasan por allí siguen su camino |
| Guarnición (grupos estacionados, 3.12) | Deja de ser guarnición y vuelve sola a su ciudad (`regreso`, P9-B) | Solo cae sin guarnición (3.12.4); si cae por misiles o desabasto con guarnición, vuelve sola a su ciudad (P9-B) |
| Campamento | Sin cambio | Sigue en pie con su bloque de 12 × 12, que no se pierde |
| Base | Sin cambio | Sigue en pie; queda en tierra sin dueño si su celda era de bandera (hoy ya puede pasar al encoger la capital) |
| Obra en curso (campamento, base) | Sigue | Sigue; al terminar, el campamento toma las celdas libres de su bloque |
| Mina (yacimiento) | Sigue siendo de N | La celda queda sin dueño: los recolectores de N pierden el +25 % de `ventajaTerritorio` ([recoleccion-y-batallas.md](recoleccion-y-batallas.md)), igual que hoy al caer una bandera |

**Migración de lo que hoy hay en las banderas.** Medido en 4 semillas, en los
días 1, 100, 200, 300, 400 y 500: **0 banderas con tropa**. La IA nunca manda
refuerzos a una bandera (`refuerzos` las salta). Aun así, al cargar una
partida de la versión 25, si una bandera tiene soldados, vehículos o munición,
pasan a un grupo nuevo de su nación, con la misma regla que
`retirarGuarnicion` (sanos como sanos, heridos como heridos, cada vehículo con
su modelo, su munición con él): si el bloque de esa bandera es de borde, el
grupo queda de **guarnición** en ella (3.12) aunque pase del tope ese día; si
no, vuelve a la ciudad propia más cercana (`regreso`). No se destruye ni se
crea nada.

### 3.5 La bandera nueva que aparece al caer una

- **Coste: ninguno** (propuesta, P3). No es tierra nueva: esa tierra ya se
  pagó al plantar y se paga cada día en el mantenimiento (3.6). Lo único que
  cambia es que ahora está en el borde.
- **Vida: 100**, terminada. No se guarda hasta que la dañen.
- **Guarnición: ninguna.** Una bandera no tiene tropa. No se crea ni un
  soldado.
- **Munición, dinero, recursos: ninguno.** No se crea nada.
- Tampoco se crean noticias: son muchas.

### 3.6 Mantenimiento

Hoy: 0,2 de dinero al día por bandera terminada (F9), pagado en
`mantenerBanderas` de la más cercana a la más lejana. Con banderas que no son
objetos, se paga **por tierra de bandera** (propuesta, P5):

`gasto = mantenimientoCelda × celdas de tierra de bandera de N`

con el valor elegido para que el gasto del mundo sea el de hoy (F1). Si no
alcanza:

1. se paga lo que haya;
2. con lo que falta se calcula cuántos bloques quedan sin pagar (F2);
3. esos bloques son **los bloques de borde más lejanos de la capital** (en
   empate, el id menor): cada uno pierde `desabasto` (5) de vida ese día y
   pasa a guardarse;
4. a 0 cae como en 3.3.5, sin atacante ni victoria, con la noticia de hoy
   («Una bandera de N se pierde por falta de mantenimiento»).

Así, una nación que no puede pagar pierde tierra desde fuera hacia dentro, y
eso le baja el gasto.

**Reparación:** como hoy, +2 de vida al día por 0,5 de metal si no la
atacaron en 3 días (`obras`). Solo se recorren las banderas guardadas.

### 3.7 Plantar una bandera

Hoy: `ejecutar({ tipo = 'bandera', nacion, x, y })` crea un bloque de 6 × 6
**centrado** en el vértice más cercano a (x, y); vale si la celda de (x, y) es
propia o sin dueño, el bloque toca lo propio por un lado, cuesta 20 de dinero
y 4 de metal, y no hay otra bandera propia a menos de 500 px.

Propuesta (P4, recomendada la A):

1. El comando es el mismo. El punto (x, y) elige **el bloque de bandera
   alineado** que lo contiene.
2. Validación, en este orden; si falla una, devuelve `false` y no cobra:
   - hay dinero y metal (20 y 4, sumando guardado y afuera);
   - el bloque tiene al menos una celda sin dueño (`'propia'` si todo es de
     N; `'ajena'` si todo es de otras naciones);
   - el bloque toca por un lado una celda de N (`bloqueToca`, como hoy);
   - no hay ya una obra de bandera de N en ese bloque (`'enObra'`).
3. Se paga al momento y queda en obra 2 días (guardada en `e.banderas`,
   atacable con × 1,5, como hoy).
4. Al terminar, toma **solo las celdas sin dueño** del bloque (las de otra
   nación no se pisan, como hoy). Si el bloque es de borde, su bandera se
   queda con vida 100 y deja de guardarse; si no, desaparece como objeto.
5. Desaparece la regla de separación de 500 px: un bloque, una bandera.
6. Sin topes de cantidad: solo el dinero, el metal y el mantenimiento.

### 3.8 Territorio que se desconecta

Si al caer una bandera un trozo de territorio de N queda separado de su
capital y de sus campamentos (propuesta, P4b, recomendada la A):

- **A. Sigue siendo de N** (como hoy: «solo cuenta pegada al plantarla»). Sus
  bloques de borde tienen su bandera y se atacan igual.

### 3.9 NPC y jugador, la misma regla

- Plantar, atacar y defender pasan por `Simulacion:ejecutar`, como hoy.
- `planearBanderas` (IA): la misma lógica de F12. Cambia la distancia al
  borde: hoy se mide contra cada sitio que da territorio (miles de banderas);
  propuesta: la distancia a la celda propia más cercana, buscando por filas de
  tramos como ya hace `caminoCeldas`. `banderaHacia` apunta al bloque alineado
  del camino.
- `defenderBanderas` (IA): pasa a la regla de guarnición de 3.12.8. Recorre
  los avisos de ataque de la nación y las banderas guardadas con ataque en
  los últimos 2 días, no todas las banderas.
- `objetivos` (diplomacia, IA): hoy mira todas las instalaciones enemigas,
  banderas incluidas. Propuesta: de las banderas enemigas solo mira los
  bloques de borde que tocan el territorio propio (la frontera que ya lleva
  `fronterasTerritorio`). Con la IA de hoy casi no hay: 0–3 banderas
  arrancadas en 500 días por semilla.
- El jugador ve y ataca las mismas banderas, con los mismos ids.

### 3.10 Cómo se ve en el mapa 2D

- **Territorio:** igual que hoy (`mundo/territorio.lua`): relleno muy suave y
  la franja del borde. El interior no lleva nada más: «solo el borde».
- **Banderas del borde:** un mástil por bloque de borde, en la celda de borde
  de ese bloque más cercana a su centro (en empate, la de fila menor y
  columna menor), para que quede sobre la línea y no en tierra ajena.
- **Zoom:** de cerca (`zoom ≥ Instalaciones.zoomBandera`, 0,6), todas las del
  borde que se ven. De lejos, solo las guardadas: en obra, dañadas o
  atacadas, con su barra de vida. Así el mapa lejano no se llena de iconos.
- **Al caer una:** el mástil se derriba (animación corta de Camila) y en los
  bloques nuevos del borde se iza el suyo. Solo es vista: no hay dato en la
  simulación para esto.
- El modo «Plantar bandera» (`interfaz/plantar.lua`) dibuja el contorno del
  **bloque alineado** bajo el ratón, en verde si vale y en rojo con el motivo
  si no.

### 3.11 Referencia: las banderas de alianza de Warpath y Rise of Kingdoms

Solo como referencia de reglas, **de memoria, sin comprobar en esta sesión**
(no tengo acceso a la web aquí; si hace falta exactitud, hay que revisarlo):

- se plantan pegadas al territorio de la alianza y cada una añade un área
  alrededor;
- cuestan recursos de la alianza y tardan en levantarse;
- el número de banderas tiene tope por nivel de la alianza (**aquí no**: la
  regla de la casa es sin topes, solo dinero y mantenimiento);
- el enemigo les baja la durabilidad; a 0 desaparecen y se pierde su tierra;
- en juegos del mismo tipo (Rise of Kingdoms), la tierra desconectada del
  centro deja de dar beneficios;
- en Rise of Kingdoms, los miembros de la alianza pueden mandar tropas a una
  bandera para defenderla, hasta la capacidad de tropas de esa bandera;
- en Rise of Kingdoms hay una lista de las tropas que están fuera, cada
  destacamento con su botón para volver, que caminan de vuelta.

Lo que tomamos: pegadas a lo propio, coste y obra, se atacan por su vida,
guarnición con tope, lista de tropas fuera con regreso andando. Lo que no: el
tope de cantidad de banderas.

### 3.12 Guarnición de una bandera

1. **Qué es.** Uno o varios grupos de la nación estacionados en una bandera
   suya del borde. No son de la bandera: cada grupo sigue siendo de su ciudad
   (`g.desde`, `g.origen`), cuenta en su inventario, lleva su munición, cobra
   su sueldo y gasta su petróleo parado como cualquier grupo que está fuera
   hoy. La bandera no guarda nada.
2. **Orden.** Comando nuevo, el mismo para NPC y jugador:
   `ejecutar({ tipo = 'guarnecer', nacion, grupo, bandera })` para un grupo
   que ya está fuera, o `enviarGrupo` con misión `guarnicion` y `objetivo` =
   id de la bandera desde una ciudad, campamento o base. Valida, en este
   orden: la bandera es de la nación y es de borde (`'destino'`); el grupo se
   puede mandar (`mandable`, `'noPuede'`); hay camino por tierra
   (`'sinCamino'`); cabe en el tope (`'llena'`, F5). Si falla, no sale nadie.
3. **Camino.** Marcha de verdad, a la velocidad de su modelo más lento. Al
   llegar pasa a misión `guarnicion` con `g.bandera = id` y se queda en el
   punto de la bandera. Si al llegar ya no cabe (llegó otro antes), no entra:
   queda como grupo en el campo (misión `mover`) en ese punto.
4. **En la batalla.** Cuando un grupo enemigo llega a una bandera con
   guarnición, la batalla se crea con la guarnición en el bando defensor
   (hoy `llegarASitio` la crea con el bando defensor vacío). Pelea como
   cualquier grupo, simulada (F8) o en 3D, con la ventaja de pelear en tierra
   propia que ya existe (`ventajaDefensa`, +10 %). La bandera no pierde vida
   mientras quede algún grupo en el bando defensor: es la regla de hoy
   (`danarSitio`, «solo si no la defiende ningún grupo»). Si la guarnición se
   retira o cae, desde el día siguiente la bandera pierde vida con F7.
5. **Refuerzos durante la batalla.** Los grupos que se suman al bando
   defensor con `redirigir` a la batalla cuentan para el tope (F5), igual que
   la guarnición: una bandera no admite más defensa de la que cabe.
6. **Sin ataque.** La guarnición se queda hasta que el dueño la mueva o la
   haga regresar (3.13). No se va sola.
7. **Si la bandera deja de ser de borde o cae con guarnición** (misiles o
   desabasto): cada grupo de guarnición vuelve solo a su ciudad (`volver`,
   misión `regreso`), andando por la ruta real (decisión P9-B).
8. **NPC (defender por informes).** Con la misma regla que el jugador:
   - se entera por el mismo aviso que recibe el jugador (`avisosAtaque`: un
     grupo enemigo que va hacia la bandera y llega en `avisoDias`, 1 día) o
     por el primer día de batalla (`atacadaDia`, como hoy);
   - valora la bandera con `valorBandera` (hoy: el F12 del yacimiento que
     protege, o 1); solo defiende las de valor mayor que 1, como hoy;
   - estima la fuerza del atacante por su informe (`poderEstimado`, como hoy
     en `defenderBanderas`); sin informe, a ciegas, y manda un explorador;
   - si tiene un sitio o un grupo libre con fuerza estimada mayor y que quepa
     en el tope, lo manda de guarnición (antes del choque) o de apoyo (si la
     batalla ya empezó); si no, la deja caer;
   - retira la guarnición (la hace regresar) cuando pasan `diasGuardiaIA` (5)
     días sin aviso ni batalla en esa bandera. El jugador decide él.

### 3.13 Panel de tropas

> **A la espera de la referencia del dueño** (P10 pendiente): mandará un
> vídeo de cómo quiere el panel de tropas. Lo que sigue es la propuesta de
> partida; no se programa hasta revisarla con esa referencia.

**Qué hay hoy.** El botón «Ejércitos» de la barra (`interfaz/navegacion.lua`)
**elige** todos tus ejércitos (Ctrl+A); el panel de abajo
(`interfaz/ejercito.lua`) suma lo elegido en una tarjeta por tipo de tropa y
tiene «Retirar», que manda `retirar` a cada grupo. La ficha de un ejército
(`interfaz/ficha.lua`) tiene su botón de retirar. En la simulación,
`retirarGrupo` hace `volver`: el grupo camina de vuelta por la ruta real
(`trazar`) a su sitio de salida o al propio más cercano; en batalla es una
retirada y pierde la carga. No acepta grupos que ya vuelven, entregas ni
obras.

**Qué falta.** Una lista de todas las tropas que están fuera, grupo por
grupo, con dónde están y qué hacen, y un «Regresar todos» con un solo clic.

**Propuesta** (Valeria para la vista y Camila para los iconos; en la
simulación no hace falta nada nuevo salvo la misión `guarnicion`):

1. Se abre con el botón «Ejércitos» (P10); Ctrl+A sigue eligiendo todas las
   fichas en el mapa.
2. Una fila por grupo, **tal como lo creó el dueño** (un grupo de la
   simulación = una fila), en orden de creación (id). Columnas:
   - **Grupo:** líder («Gral. X») o tipo («Recolectores de metal», «Convoy de
     munición», «Obra: campamento»);
   - **Dónde:** el sitio o bandera donde está, o «camino a Y, faltan 3,2 km»;
   - **Qué hace:** En marcha, Ataca, En batalla, Guarnición, Recolecta, En
     posición, Vuelve;
   - **Lleva:** soldados, vehículos por modelo, heridos, días de munición y la
     carga si la hay (lo que ya da `fichaGrupo`);
   - **Regreso:** días que tardaría en volver: largo del camino real hasta
     casa / (`velocidadEjercito` × velocidad del grupo), redondeado arriba;
   - **Regresar:** botón por fila. Activo si `retirarGrupo` lo aceptaría; si
     no, gris con el motivo al pasar el ratón («obra en camino», «ya vuelve»).
     En batalla pide confirmación: «Es una retirada: pierdes la carga».
3. **Regresar todos**, al pie: manda `retirar` a cada grupo en orden de id y
   avisa «N vuelven, M no pueden (obras, entregas o ya vuelven)». Los que
   están en batalla se retiran solo si se confirma aparte.
4. **Sin teletransporte:** regresar es caminar. El grupo sigue en el mapa,
   puede chocar por el camino con las reglas de choques de hoy y llega cuando
   llega.
5. Un clic en la fila centra el mapa en el grupo y lo elige.

---

## 4. Fórmulas

**F1. Mantenimiento por tierra de bandera (propuesta).**
`gasto(N) = mantenimientoCelda × celdasBandera(N)`, con
`mantenimientoCelda = 0,245 / 36` de dinero por celda y día (0,245 por cada
bloque de 36 celdas).

- `celdasBandera(N)`: celdas de N fuera de los bloques de sus ciudades y
  campamentos terminados. Rango medido el día 500: de 89 233 a 102 112 en el
  mundo (4 460–4 640 por nación de media).
- De dónde sale 0,245: el gasto de hoy (0,2 × banderas terminadas) dividido
  por los bloques de 36 celdas de tierra de bandera, medido en los días 300 y
  500 de las 4 semillas: 0,2436–0,2459.
- Ejemplo: una nación con 4 632 celdas de tierra de bandera (media de la
  semilla 7 el día 500) paga 0,245 × 4 632 / 36 = **31,5 de dinero al día**.
  Hoy, con 157 banderas terminadas de media, paga 31,4.

**F2. Bloques sin pagar.**
`k = ceil(falta / (mantenimientoCelda × 36))`, donde `falta` es lo que no se
pudo pagar ese día.

- Ejemplo: falta 2,0 de dinero → k = ceil(2,0 / 0,245) = 9 bloques del borde
  pierden 5 de vida.

**F3. Vida que pierde una bandera atacada.** F7 de
[territorio-y-capitales.md](territorio-y-capitales.md), sin cambios:
`ΔV = min(100, G × 100 / 300)`. Grupo de 1 000 de vida → cae en 4 días.

**F4. Profundidad de un frente.** Días para llegar a una celda que está a
`d` bloques del borde: `d × ceil(100 / ΔV)`. Ejemplo: grupo de 1 000 de vida,
mina a 3 bloques (900 m) del borde → 12 días, si nadie lo para.

**F5. Tope de guarnición de una bandera (propuesta, P8).**
`tope = guarnicionPorNivel × nivel de la capital`, con `guarnicionPorNivel =
200`, medido en vida de grupo (`vidaGrupo`: 1 por soldado y la vida de cada
vehículo según su modelo; un T-72B vale 9).

- Cuenta la suma de la vida de los grupos de guarnición en esa bandera, los
  que van hacia ella de guarnición y los que están en su bando defensor.
- Rango: 200 (nivel 1) a 1 000 (nivel 5). Con los niveles de
  [rebeldes-y-niveles.md](rebeldes-y-niveles.md), hasta 10 000 en el 50.
- Ejemplo: capital de nivel 4 → tope 800. Un grupo de 500 soldados y 20
  T-72B vale 500 + 180 = 680: cabe. Otro de 200 soldados ya no (880 > 800).
- Referencia medida (auditor, 500 días, 4 semillas): los bandos de las
  batallas de hoy tienen de mediana 217–988 soldados y 6–15 vehículos (p90:
  1 532–2 585 soldados y 32–45 vehículos); las capitales están en el nivel 5
  de mediana el día 500. Con 1 000, una guarnición llena aguanta un ataque
  mediano, no uno grande. **Sin medir** con la guarnición programada.

## 5. Casos límite

- **Bloque con celdas de borde solo de la capital o de un campamento:** no
  tiene bandera. Para quitar esa tierra hay que ganar la batalla de ese sitio.
- **Bloque con borde de bandera y borde de capital a la vez:** tiene bandera;
  al caer, pierde solo la tierra de bandera; la de la capital se queda.
- **Bloque con tierra de N y de M:** dos banderas, una de cada una. Caer la de
  N no toca las celdas de M.
- **Hueco sin dueño dentro del territorio:** los bloques que lo rodean son de
  borde y tienen bandera. Se puede tapar plantando en el hueco.
- **Bandera en obra que cae:** no había tomado celdas; se pierde lo pagado y no
  se pierde tierra.
- **Dos naciones plantan en el mismo bloque el mismo día:** se resuelve en el
  orden de `ejecutar`. Las dos obras terminan; cada una toma las celdas libres
  en el orden de `obras` (id menor primero).
- **Se planta delante de una bandera atacada:** deja de ser borde; el
  atacante vuelve sin victoria (3.3.4). Es la forma de defender sin ejército,
  pagando.
- **Bloque en agua sin camino por tierra hasta él:** es borde y tiene bandera,
  pero nadie puede mandar un grupo (`trazar` falla). Solo lo dañan los misiles
  y el desabasto.
- **Cae una bandera y parte el territorio:** P4b.
- **Cae un campamento:** hoy su tierra queda sin dueño salvo la que cubre otro
  sitio vivo, bandera incluida. Con esta regla las banderas ya no son objetos
  que cubran nada: queda sin dueño todo su bloque salvo lo que cubra una
  ciudad u otro campamento suyo. Los bloques de N que quedan expuestos pasan a
  ser borde y tienen bandera desde ese día, sin coste.
- **La capital encoge** (su bloque no cambia hoy: 20 × 20 fijo): no aplica.
- **Nación sin dinero:** pierde vida en los k bloques del borde más lejanos
  cada día (F2) hasta poder pagar o hasta perderlos.
- **Guarnición y aviso a la vez en varias banderas:** el NPC las mira en orden
  de valor (y de id en empate) y manda mientras le quede fuerza; al jugador le
  llegan todos los avisos.
- **Guarnición que no cabe al llegar:** se queda como grupo en el campo en ese
  punto (3.12.3). Si luego empieza la batalla allí, no está en ella: tiene que
  sumarse con `redirigir`, si cabe.
- **Baja el tope** (hoy el nivel no baja nunca): la guarnición que ya está se
  queda; no entra nadie más hasta estar por debajo.
- **Grupo de guarnición con recolectores o convoyes:** no pueden ser
  guarnición (no son `mandable` o no son ejército); solo ejércitos.
- **Regresar todos con grupos en batalla:** esos no salen si no se confirma
  aparte (3.13.3).
- **Grupo cuya ciudad de salida ya no es suya o no existe:** `volver` lo
  manda al sitio propio más cercano, como hoy; si no hay, desaparece con lo
  que lleva (regla de hoy, que la capital nunca se pierda hace que no pase).
- **Partida de la versión 25:** se borran todas las banderas instalación. Sus
  celdas no cambian. Las que estaban en obra terminan con su bloque centrado
  de antes al acabar su obra y después desaparecen como objeto. Las dañadas
  pasan su vida a los bloques de borde que tocaban (la menor, si varias tocan
  el mismo). Lo que guardaban vuelve a casa (3.4).

## 6. Dependencias

- **Depende de:**
  - [territorio-y-capitales.md](territorio-y-capitales.md): celdas, bloques,
    `duenoCelda`, `trozos`, F7, F8 y F9;
  - [rebeldes-y-niveles.md](rebeldes-y-niveles.md): la rejilla de bloques de
    6 × 6 alineada (`bx = floor(cx / 6)`);
  - [ejercitos-en-el-mapa.md](ejercitos-en-el-mapa.md): ataques, `volver`,
    victorias y choques;
  - [economia.md](economia.md): economía cerrada (el mantenimiento se paga
    del dinero; la migración no crea ni destruye tropas; los grupos de
    guarnición cobran y gastan como cualquier grupo fuera);
  - [recoleccion-y-batallas.md](recoleccion-y-batallas.md): la batalla por
    bandos, F8, `avisoDias` y la ventaja de pelear en tierra propia.
- **Lo usan:**
  - [territorio-y-capitales.md](territorio-y-capitales.md) (3.7, 3.9 y F9
    quedan sustituidos por este documento);
  - [recoleccion-y-batallas.md](recoleccion-y-batallas.md): el bonus de
    territorio sobre las minas;
  - [interfaz-militar.md](interfaz-militar.md): panel de bandera, modo
    plantar (5.11) y el panel de tropas nuevo (3.13);
  - [ejercitos-en-el-mapa.md](ejercitos-en-el-mapa.md): la ficha y el panel
    de ejércitos, que ganan la misión «Guarnición» y el botón «Regresar»;
  - [escala-del-mundo.md](escala-del-mundo.md): el guardado por nación.

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `ladoBloqueBandera` | 6 celdas | 4–10 | Más grande: menos banderas de borde y frentes más bastos. Tiene que ser el mismo que el de los rebeldes o hay que separarlos |
| `mantenimientoCelda` | 0,245 / 36 | 0,15–0,35 / 36 | El freno a la expansión. Con 0,245 el gasto es el de hoy |
| `desabasto` | 5 de vida al día | 2–10 | Lo rápido que se pierde tierra sin pagar |
| `aguante` (F7) | 300 | 150–600 | Días por bloque en un frente (F4) |
| `vidaNueva` | 100 | 25–100 | La vida de la bandera que aparece al caer otra (P3). Por debajo de 50, un frente cae casi al mismo ritmo que un bloque suelto |
| `diasGuardada` | 3 | 1–7 | Días sin ataque tras los que una bandera a 100 deja de guardarse |
| `guarnicionPorNivel` | 200 de vida | 100–500 | El tope de guarnición (F5). Alto: banderas casi imposibles de tomar con ataques medianos |
| `diasGuardiaIA` | 5 | 2–15 | Días sin aviso ni batalla tras los que el NPC hace regresar la guarnición. Alto: menos tropa libre para atacar |
| `bandera.dinero`, `bandera.metal`, `bandera.dias` | 20, 4, 2 | como en territorio-y-capitales.md | Lo rápido que se expande todo el mundo |

## 8. Criterios de aceptación

Con 500 días en las semillas 1, 7, 42 y 1234, con
`tools/auditar_economia_nationsrts.lua` y una herramienta como la de «Cómo se
midió», cortes en los días 100, 200, 300, 400 y 500:

1. **Banderas guardadas que no crecen con los días:** de media por nación,
   como mucho 30 en cada corte, y la del día 500 no pasa del doble de la del
   día 100 más 5. Hoy: 24–29 el día 100 y 152–157 el día 500.
2. **Banderas de borde (informativo, no es tope):** se apunta el número de
   bloques de borde por nación en cada corte. Crece con el territorio (P7).
   Referencia de hoy, contando todos los bloques alineados con celdas de
   borde: 1 130–1 417 en el mundo el día 100 y 5 856–6 741 el día 500.
3. **Tiempo estable:** la suma de ms/día de `mantenerBanderas`, `obras`,
   `defenderBanderas` y `enFrontera` en el tramo 400–500 no pasa de 1,3 veces
   la del tramo 100–200. Hoy pasa de 1,04–1,60 a 3,14–5,22 ms/día (× 2,1 a
   × 4,1). `planearBanderas`: tramo 400–500 como mucho 1,3 veces el 100–200
   (hoy de 2,28–2,85 a 3,90–5,87 ms/día, × 1,4 a × 2,3). El día entero pasa
   hoy de 8–10 ms (tramo 1–100) a 22–29 ms (tramo 400–500); qué parte de eso
   no es de las banderas no está medido.
4. **Guardado por nación el día 500:** como mucho 28 KB en cada semilla. Hoy,
   59,3–60,2 KB, de los que 23,9–25,7 KB no son banderas.
5. **Equilibrio sin romper lo de hoy**, día 500, frente a lo medido hoy:
   - naciones vivas: 22, 22, 21 y 20 (todas);
   - invariante de conservación del auditor cumplido todos los días;
   - mediana del dinero por nación (guardado + afuera) entre 0,75 y 1,25
     veces la de hoy: 455, 448, 818 y 388;
   - gasto de mantenimiento del mundo entre 0,95 y 1,05 veces el de hoy:
     691, 690, 653 y 607 de dinero al día;
   - celdas de territorio del mundo entre 0,9 y 1,1 veces las de hoy:
     138 008, 137 356, 131 646 y 122 058.
6. **Nada se crea:** al caer una bandera, en ese día no cambia el dinero, el
   metal ni la tropa de ninguna nación por esa causa; la cuenta de tierra de
   bandera baja exactamente en las celdas liberadas.
7. **Migración:** una partida de la versión 25 cargada conserva todas sus
   celdas, sus tropas y su munición (mismos totales por nación antes y
   después de cargar).
8. **Determinismo:** guardar el día 250, cargar y seguir da el mismo texto de
   `guardar()` que no parar.
9. **Misma regla NPC y jugador:** la misma orden por `ejecutar` desde el mismo
   estado da el mismo resultado.
10. **Guarnición:** ningún día la suma de una bandera pasa de su tope (F5),
    salvo el caso de migración; en 500 días hay al menos 1 guarnición NPC por
    semilla (si da 0, la IA no se entera de los ataques a banderas); ninguna
    guarnición NPC sigue más de `diasGuardiaIA` + 1 días sin aviso ni
    batalla; el invariante de conservación del auditor se cumple todos los
    días (los grupos de guarnición cuentan en su ciudad).
11. **Panel de tropas:** «Regresar todos» deja cada grupo aceptado en misión
    `regreso` con su ruta real; ninguno aparece en casa el mismo día si su
    camino es más largo que un día de marcha.

---

## Preguntas para el dueño

La primera opción de cada una es la recomendada.

**P1. ¿Qué es «una bandera del borde»?**
- **A. Una por bloque de 6 × 6 del borde, que sale de las celdas y solo se
  guarda si tiene algo (obra, daño, ataque).** Cumple tu regla y baja el
  guardado y el tiempo.
- B. Las banderas de hoy, borrando las interiores. Medido: no resuelve nada
  (−1,4 % de banderas el día 500).
- C. Una por celda de borde. Serían 33 000–38 000 en el mundo el día 500.

**P2. La tierra de una bandera del borde que cae…**
- **A. Queda sin dueño (como hoy).** El que la quiera, planta.
- B. Pasa al atacante sin pagar. Es tierra gratis por ganar; acelera las
  guerras.

**P3. La bandera nueva que aparece en el borde al caer otra…**
- **A. Gratis, con vida 100 y sin tropa.** Esa tierra ya estaba pagada.
- B. Gratis, con vida 50, y se repara con metal como hoy (+2 por 0,5).
  Frentes más débiles tras cada pérdida.
- C. La paga el dueño (20 de dinero y 4 de metal); si no puede, nace con 25
  de vida. Perder tierra cuesta dinero además de tierra.

**P4. Plantar.**
- **A. En el bloque alineado de 6 × 6 que contiene el punto.** Un bloque, una
  bandera; el mapa queda en cuadrícula limpia.
- B. Como hoy, bloque centrado donde se hace clic. Más libertad, pero la
  bandera plantada ya no coincide con la bandera del borde que la defiende.

**P4b. Territorio que queda separado de la capital y de los campamentos.**
- **A. Sigue siendo tuyo, con sus banderas de borde (como hoy).**
- B. Se pierde entero al separarse. Cortar el cuello de una tira de banderas
  quita todo lo que hay detrás: muy fuerte y barato para el atacante.
- C. Sus banderas pierden 5 de vida al día hasta que se reconecte.

**P5. Mantenimiento de las banderas.**
- **A. 0,245 por cada 36 celdas de tierra de bandera.** Medido: el gasto del
  mundo queda igual que hoy.
- B. 0,2 por bandera del borde. Hoy serían unos 5 900–6 700 bloques de borde
  el día 500: casi el doble de gasto que ahora.
- C. 0,2 por cada 36 celdas: un 18 % menos de gasto que hoy.

**P6. ¿El agua sin dueño hace borde?**
- **A. Sí, como cualquier tierra sin dueño.** Hoy se planta en el agua, así
  que la costa es un borde más.
- B. No: la orilla que da solo al agua no lleva bandera. Menos banderas, pero
  la tierra ganada sobre el agua no se puede quitar. Sin medir cuántas menos.

**P7. ¿Debe tener freno la expansión?** El territorio crece en línea recta
(unas 12 celdas por nación y día) y en 500 días casi nadie se toca. Con P1-A
el guardado deja de crecer por las banderas, pero el borde (lo que se ve y se
puede atacar) sigue creciendo.
- **A. No, por ahora.** Se deja como está y se mide cuando las naciones
  empiecen a tocarse.
- B. Mantenimiento que sube con el tamaño (por ejemplo, × 1 + celdas / 10 000).
  Frena la expansión; cambia la economía; hay que medirlo.
- C. Solo plantar en tierra firme. Más de la mitad del borde de hoy da al
  agua; habría menos territorio y menos borde. Hay que medirlo.

**P8. Tope de guarnición de una bandera.**
- **A. Según el nivel de la capital: 200 × nivel (1 000 en el nivel 5).**
  Crece con la nación.
- B. Fijo, 500 para todas. Más simple; en el nivel 5 queda corto.
- C. Según el nivel de la ciudad más cercana. Da igual hoy (una ciudad por
  nación) y es más caro de calcular.

**P9. Si la bandera deja de ser de borde, o cae por misiles o desabasto con
guarnición dentro…**
- **A. La guarnición queda como grupo en el campo, en ese punto, esperando
  órdenes.** El jugador decide; el NPC la hace regresar ese día.
- B. Vuelve sola a su ciudad (`regreso`).

**P10. ¿Dónde se abre el panel de tropas?**
- **A. Con el botón «Ejércitos»** (hoy elige todas las fichas; eso queda en
  Ctrl+A).
- B. Con un botón nuevo, «Tropas», y «Ejércitos» sigue como hoy.

---

## Decisiones (2026-09-30)

Respuestas transmitidas por Claude (jefe de estudio). P4, P5 y P6 las decidió
Claude; las demás, el dueño.

| Pregunta | Decisión |
|---|---|
| P1 | A: la bandera es el bloque de 6 × 6 del borde, sale de las celdas y solo se guarda si tiene estado |
| P2 | A: la tierra de la bandera que cae queda sin dueño |
| P3 | A: la bandera nueva del borde es gratis, con vida 100 y sin tropa |
| P4 | A: se planta en el bloque alineado que contiene el punto (Claude) |
| P4b | A: el territorio desconectado sigue siendo suyo, con sus banderas de borde |
| P5 | A: mantenimiento de 0,245 por cada 36 celdas de tierra de bandera, el mismo gasto que hoy (Claude) |
| P6 | A: el agua sin dueño hace borde (Claude) |
| P7 | A: sin freno a la expansión por ahora; se revisa cuando las naciones choquen |
| P8 | A: tope de guarnición = 200 × nivel de la capital, en vida de grupo |
| P9 | **B**: si la bandera deja de ser de borde, o cae por misiles o desabasto con guarnición, la guarnición vuelve sola a su ciudad (`regreso`) |
| P10 | Pendiente: el dueño mandará un vídeo de referencia del panel de tropas (3.13) |

---

## Cómo se midió

- Herramienta propia, fuera del repositorio:
  `scratchpad/lucia/medir_banderas_borde.lua`. Usa `depurar/mundo_prueba.lua`
  como el auditor (5 × 5 zonas), corre `avanzarDia` con LuaJIT y, en los días
  1, 100, 200, 300, 400 y 500, cuenta banderas, cuántas tocan una celda de
  borde, las celdas de borde y con qué lindan (otra nación, tierra o agua sin
  dueño, según `terreno:base > 18`), los bloques alineados de 6 × 6 con borde,
  la tierra de bandera, el tamaño de `guardar()` entero, sin banderas y sin
  territorio, y los ms/día de `mantenerBanderas`, `planearBanderas`, `obras`,
  `enFrontera` y `defenderBanderas`.
- `MODO=borde`: prototipo de P1-B. Cada día quita el objeto de las banderas
  terminadas que no tocan el borde (la tierra se queda) y pone una bandera en
  cada celda de borde que no cubre ningún sitio vivo. Semilla 7: 198 banderas
  quitadas en 500 días y 0 nuevas.
- Auditor: `luajit tools/auditar_economia_nationsrts.lua 500 <semilla>` en las
  4 semillas: 22, 22, 21 y 20 naciones vivas, invariante cumplido todos los
  días, mediana del dinero 455, 448, 818 y 388 (las mismas que da mi
  herramienta).
- Las 4 semillas corrían a la vez: los ms/día son comparables entre tramos,
  no son la velocidad de una sola partida.
- HEAD 536f301, catálogo encendido.

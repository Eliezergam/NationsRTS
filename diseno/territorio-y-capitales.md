# Territorio y capitales

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Cómo se pierde y se gana tierra desde el cambio de reglas del dueño: **la
capital nunca se pierde**, todo lo que no es capital y pierde su batalla
**desaparece** y su tierra queda **sin dueño**, y la tierra se gana con
**banderas** plantadas hacia los **yacimientos** que salen del terreno.
Documento para Andrés (simulación) y Valeria (mundo y vista). Estado:
**propuesta, sin programar.** Todo lo marcado "hoy" es lo que hace el código en
la versión 15 (HEAD 6f11897); lo marcado "propuesta" es lo que cambia.

Segunda versión: incorpora las respuestas del dueño a las tres preguntas de la
primera (extracciones y bases vencidas se destruyen; el dinero tiene bóveda por
nivel; las banderas son una acción aparte y hay yacimientos procedurales).

Afecta a: `combatir`, `combatirCiudad`, `tomarCiudad`, `limitarAlmacen`,
`almacen`, `producirRecursos`, `economia`, `obras`, `levantarCampamento`,
`planearCampamento`, `construirExtraccion`, `registrarZona`, `dueno`,
`ejecutar`, `llegada`, `cargar`, y en el mundo `recursos.lua`, `mundo.lua`
(`datosZona`, `explorarTrozo`) y el mapa 2D.

---

## 1. Resumen

Cada nación tiene una sola ciudad, su capital, y la conserva siempre. La guerra
se gana quitando tierra y botín. Un campamento, una extracción, una base o una
bandera que pierde su batalla se borra con todo lo que tenía, y su territorio
queda sin dueño hasta que alguien lo vuelva a cubrir. Una capital que pierde su
batalla no cambia de manos: se queda con **9 de vida sobre 100** y el atacante
se lleva los recursos y el dinero que estaban **afuera**, es decir, los que no
cabían en el almacén o en la bóveda. La tierra se estira con **banderas**:
baratas, sin tropa, sin producción, solo territorio. Sirven para alcanzar los
**yacimientos** (petróleo, metal, oro y comida) que el terreno reparte según su
bioma, altura, pendiente y humedad, y que se ven con un icono en el mapa 2D.
Un yacimiento solo se explota dentro del territorio propio.

## 2. Fantasía del jugador

- "Mi capital es mía pase lo que pase: me pueden humillar, pero no borrarme."
- "Si acumulo más de lo que cabe en el almacén o en la bóveda, lo dejo a la
  vista: o lo gasto, o subo de nivel, o me lo roban."
- "Veo un icono de oro a cuatro kilómetros, en un valle entre montañas. Planto
  una fila de banderas hacia allí y el vecino hace lo mismo desde el otro
  lado: gana quien llega primero y quien la sabe defender."
- "Mis banderas no se defienden solas. Si me avisan de que atacan una, mando
  un ejército a cazar al atacante, como en Warpath."
- "Ganar un campamento enemigo no me da tierra: tengo que ir a clavar mi
  bandera. El mapa se llena de huecos en disputa."
- "Mi capital a 9 de vida está débil y produce poco. Repararla me cuesta caro,
  y tengo que elegir entre repararla ya o rearmarme."

## 3. Reglas

### 3.1 Vida de los sitios

- **Capital (propuesta):** tiene un campo nuevo, `c.vida`, en una **escala de 0
  a 100**. Así "9 de vida" es 9 sobre 100 y también el 9 %, que en esta escala
  son lo mismo. Nace con 100. No baja de 9 por batallas (ver 3.3).
- **Campamento (hoy):** usa `salud`, con un máximo de 30
  (`saludMaxima.campamento`). **Propuesta:** se mantiene el campo `salud` con
  máximo 30 y la interfaz lo muestra como `salud / 30 × 100` para que todas las
  barras vayan de 0 a 100. Así no hay que convertir `salud` en el guardado.
- **Extracción y base (hoy):** `salud` con máximo 100 y 180. No cambia.
- **Bandera (propuesta):** `salud` con máximo 100 (`saludMaxima.bandera`).
- Qué quita vida: los días de batalla en tierra (F3, y F7 en banderas) y, en
  instalaciones, los misiles (`danarInstalacion`, hoy) y el desabasto (5 al
  día, hoy en campamentos; propuesta: también en banderas).

### 3.2 Batalla en un campamento, una extracción o una base

Cada día que un grupo en misión `atacar` está sobre la instalación:

1. Se hace el combate de hoy (`combatir`): bajas en los dos bandos, igual que
   ahora.
2. **Propuesta:** la instalación también pierde vida según F3.
3. La instalación **pierde la batalla** si su `salud` llega a 0 o si su
   guarnición se queda sin soldados ni tanques.
4. Si pierde: `destruirInstalacion`. Hoy ya pasa en los campamentos;
   **propuesta (respuesta 1 del dueño):** pasa igual en extracciones y bases,
   que hoy cambian de dueño (`inst.nacion = g.nacion`). Se borra con todo:
   - guarnición, heridos, lanzacohetes y obra en curso, sin devolver nada;
   - no pasa al ganador;
   - el grupo atacante anota una victoria, sus heridos van a casa
     (`heridosACasa`) y vuelve (`volver`).
5. Su territorio deja de contar en el mismo momento (`ensuciar`). Esa tierra es
   de quien la cubra con otro sitio suyo o, si nadie la cubre, **de nadie**.
6. El yacimiento de una extracción destruida queda libre: cualquiera que tenga
   esa tierra puede volver a construir encima (3.8).
7. Si gana la instalación: el grupo aniquilado desaparece o se retira, como
   hoy.

Una excepción: el **abandono por desabasto** no es una batalla. La guarnición
vuelve a casa, como hoy (`retirarGuarnicion`), y no cambia.

### 3.3 Batalla en una capital

Cada día que un grupo en misión `atacar` está sobre la capital
(`combatirCiudad`):

1. Combate de hoy igual que ahora: bajas, pérdida de tanques y lanzacohetes, y
   `asediadaDia`.
2. **Propuesta:** la capital pierde vida según F3, con un suelo de 0.
3. La capital **pierde la batalla** si `c.vida` llega a 0 o si se queda sin
   soldados ni tanques. Pasa lo que ocurra primero.
4. Si pierde:
   - **No cambia de manos.** Desaparece la llamada a `tomarCiudad` (ver 3.9).
   - `c.vida = 9`.
   - **Saqueo:** el grupo atacante se lleva **todo** lo que la nación tiene
     afuera (`n.afuera.metal`, `n.afuera.petroleo` y `n.afuera.dinero`) en un
     campo nuevo, `g.botin`, y `n.afuera` queda en 0. El almacén
     (`n.recursos`) y la bóveda (el tesoro hasta su tope) no se tocan.
   - Tropas de la capital: se queda con lo que sobrevivió. Si perdió por
     guarnición, eso es 0 soldados y 0 tanques, y vuelve a reclutar por la
     economía normal en cuanto deja de estar sitiada, dos días después del
     último combate.
   - Defensas: se queda con las baterías y los lanzacohetes que sobrevivieron.
     Hoy la conquista las ponía a 0; esa regla desaparece.
   - La mejora en curso y la cola de heridos se conservan. Hoy la conquista las
     borraba.
   - El grupo atacante anota una victoria, sus heridos van a casa
     (`heridosACasa`) y **vuelve con el botín** (`volver`). Sus lanzacohetes
     vuelven con él: ya no se regalan a la ciudad.
   - Cansancio del defensor: +8, como en la conquista de hoy.
   - Noticia: "X saquea Y: se lleva M de metal, P de petróleo y D de dinero".
5. **Llegada con botín:** en la llegada `regreso`, `g.botin` entra en su nación
   con la regla de entrada de 3.4, así que lo que no cabe queda afuera. Si el
   grupo desaparece por el camino, el botín se pierde.
6. **Capital ya a 9 que vuelve a perder:** se queda en 9, porque la vida no baja
   de 9 al perder, y se saquea lo que haya afuera, que puede ser 0. No hay
   inmunidad ni tiempo de gracia. Lo único que la protege es que no le queda
   nada que robar.

### 3.4 Almacén, bóveda y afuera

- **Guardado:** `n.recursos.metal` y `n.recursos.petroleo`, hasta el tope del
  almacén (F1).
- **Bóveda (propuesta, respuesta 2 del dueño):** `n.tesoro`, hasta el tope de
  la bóveda (F1b), que también depende del nivel de la capital. Hoy el tesoro
  no tiene tope.
- **Afuera (propuesta):** hay una tabla nueva,
  `n.afuera = { metal, petroleo, dinero }`, sin tope. En el panel aparece como
  un número pequeño junto a la barra del almacén y junto al tesoro.
- **Entrada.** Todo lo que entra se suma primero al almacén o a la bóveda hasta
  el tope, y el resto va afuera. Entra la producción de campamentos,
  extracciones y minas de oro, el metal de talleres (`metalCiudad`), los
  impuestos, las ventas y el botín. Esto sustituye al recorte de
  `limitarAlmacen`, que hoy **tira** el exceso de metal y petróleo, y pone un
  tope al tesoro, que hoy no lo tiene.
- **Gasto.** Cualquier pago (obras, banderas, mejoras, fabricación,
  mantenimiento, reparación) toma **primero de afuera** y después del almacén o
  de la bóveda. Es la regla natural: se usa antes lo que está a la intemperie.
  Para "¿tengo para pagar?" cuenta la suma de guardado y afuera.
- **Merma.** Cada día se pierde un 3 % de lo que hay afuera (`merma`, F2), en
  los tres recursos. No es un tope: la cantidad afuera se estabiliza sola, en
  proporción a lo que sobra cada día.
- **Comida:** no cambia. Sigue en el granero de la ciudad y no se saquea.

### 3.5 Reparar la capital

- **Comando nuevo:** `ejecutar({ tipo = 'reparar', nacion, ciudad, puntos })`.
  Es la misma entrada para el NPC y para el jugador.
- **Validación:** la ciudad es de `nacion`, `puntos ≥ 1` y
  `vida + puntos en cola ≤ 100`. Si alcanza con guardado y afuera, se paga
  **todo al empezar** (F4): petróleo y metal del almacén y dinero del tesoro,
  primero de afuera en los tres. Si no alcanza, el comando devuelve `false`.
- **Tiempo:** los puntos entran en `c.reparacion` (pendientes) y cada día suben
  `c.vida` en `ritmo` (F5). No hay tope de encargos: se pueden encargar más
  puntos mientras sigue la reparación, hasta llenar a 100.
- **Mientras está sitiada** (`sitiada(c)`, combatió hoy o ayer), la reparación
  se detiene ese día sin perder lo pagado.
- **Quién decide:**
  - NPC: en `planearMejoras`, si `vida < 60` y no está sitiada, pide los puntos
    que pueda pagar sin bajar de `reservaMetal` (40) de metal ni de
    `reservaTesoro` (60) de dinero.
  - Jugador: botón "Reparar" en el panel de su capital, con el coste y los días
    a la vista.
- **Campamentos:** siguen con la reparación automática de hoy (`obras`: +2 de
  salud al día por 0,5 de metal, si no los atacaron en 3 días). No usan el
  comando. Las banderas se reparan igual (3.7).

### 3.6 Poca vida: efectos

Con `f(V)` de F6:

- **Producción:** el trabajo de la capital (`produce[c.id]` en `economia`) y la
  producción de un campamento se multiplican por `f(V)`.
- **Defensa:** en `combatirCiudad`, las bajas que causa la capital
  (`bajasNuestras`) se multiplican por `f(V)`.
- No cambian ni el reclutamiento ni el territorio de la capital.

### 3.7 Banderas (propuesta)

Una bandera es una instalación nueva, `tipo = 'bandera'`, que **solo da
territorio**. No produce, no tiene guarnición y no genera ni mantiene soldados.
Es la forma barata de estirar la tierra hacia un yacimiento; el campamento
sigue siendo lo que produce.

**Plantar.**

1. Comando nuevo: `ejecutar({ tipo = 'bandera', nacion, x, y })`. La misma
   entrada para el NPC y para el jugador.
2. Validación, en este orden; si falla una, devuelve `false` y no cobra:
   - la nación tiene, sumando guardado y afuera, el coste de F8 (20 de dinero y
     4 de metal);
   - `dueno(x, y)` es `nil` o la propia nación; en tierra de otra nación no se
     puede;
   - `sitioValido(x, y)`: tierra firme, fuera de agua y de cascos de ciudad;
   - **pegada a lo tuyo:** existe un sitio propio que ya da territorio (capital,
     campamento, extracción, base o bandera terminados) a una distancia `≤
     alcance(sitio) + bandera.alcance` del punto. Es decir, el círculo de la
     bandera toca tu territorio. Así se avanza en cadena;
   - ninguna bandera propia a menos de `bandera.separacion` (1 500 px). Es una
     regla de sitio, como la de los campamentos, no un tope de cantidad.
3. Se paga al momento. No sale ningún grupo: la bandera aparece en obra en el
   punto (`progreso` de 0 a 1 en `bandera.dias`, 2 días) y no da territorio
   hasta terminarse, como el campamento.
4. Terminada, entra en `dueno` como cualquier instalación, con
   `ALCANCE_INSTALACION.bandera = 1500` px (la mitad del campamento).
5. No hay límite de banderas en obra ni de banderas por día: solo el dinero y
   el metal.

**Mantenimiento.** Cada bandera terminada cuesta `bandera.mantenimiento` (0,2)
de dinero al día (F9). Se paga en `mantenerCampamentos`, después de los
campamentos y de la más cercana a la más lejana de la capital. La que no se
paga pierde 5 de vida al día (`desabasto`), como un campamento. No se abandona:
cae cuando llega a 0.

**Ataque.** Un grupo en misión `atacar` sobre una bandera no combate contra
nadie (no hay guarnición). Cada día la bandera pierde `ΔV` de F7 y, a 0:

- `destruirInstalacion`: se borra, sin devolver nada;
- la tierra que solo cubría ella queda **sin dueño** (`ensuciar`);
- el atacante anota una victoria y vuelve (`volver`);
- noticia al dueño: "X arranca tu bandera en (x, y)". Además, **desde el
  primer día de ataque**, noticia de aviso: "X ataca tu bandera: cae en N días"
  (N sale de F7), para que el dueño tenga tiempo de ir.

Esto necesita una rama nueva en `combatir`: hoy, una instalación sin soldados
ni tanques cae el primer día, y una bandera no tiene ninguno.

**Defensa.** La bandera no se defiende sola. El dueño manda un ejército con
líder a la bandera o contra el atacante. Si sus trayectos del día pasan a menos
de `choque.radio` (3 000 px), quedan trabados y combaten con las reglas de
choque que ya existen (`ejercitos-en-el-mapa.md`, 3.7), con `ventajaDefensa`
si el choque es dentro de su territorio. Mientras el atacante está trabado, no
está sobre la bandera y la bandera no pierde vida. Los misiles también la
dañan (`danarInstalacion`), sin fortificación.

**Reparación.** Como los campamentos: +2 de salud al día por 0,5 de metal si
no la atacaron en 3 días.

**Qué no hace una bandera:** no explota yacimientos, no recluta, no produce,
no se puede usar de origen de grupos (`sitioCercano` la ignora) y no cuenta
para `vivas()`.

**Campamentos y extracciones en tierra de nadie.** Con las banderas ya no hace
falta abrir el campamento a tierra sin dueño: `levantarCampamento` sigue
exigiendo tierra propia, como hoy. Para plantar un campamento en tierra de
nadie, primero se planta una bandera.

### 3.8 Yacimientos procedurales (propuesta)

Sustituyen a los depósitos de `recursos.lua`. Salen de la semilla, igual en
todas las máquinas, y no se guardan (solo se guarda lo que se construye
encima).

**Cuatro tipos:**

| Tipo | Da | Dónde (aptitud 1) | Dónde (aptitud parcial) |
|---|---|---|---|
| `petroleo` | petróleo al almacén | biomas `seca` y `arena` | 0,7 en llanura baja (altura < 60 y pendiente < 0,1) o en costa (mar a 300 px y altura < 40) |
| `metal` | metal al almacén | altura > 190 (`roca`) | 0,7 si altura > 150; 0,35 si pendiente > 0,3 |
| `oro` | dinero al tesoro | "cauce": altura entre 12 y 190, humedad > 0,1 y al menos 8 px más baja que la media de los cuatro puntos a 400 px | 0,5 si altura > 220 |
| `comida` | comida al granero de la ciudad | `pradera` o `bosque` con humedad entre -0,1 y 0,45, pendiente < 0,3 y altura < 150 | — |

La pendiente es `|∇altura|` medida con `Terreno:base` a ±100 px. **El terreno
no tiene ríos**; el "cauce" es un valle húmedo, lo más parecido que hay hoy.
Cuando Valeria añada ríos, la regla del oro pasa a "a menos de 300 px de un
río" y hay que volver a medir.

**Generación (F10), paso a paso:**

1. El mundo se divide en celdas de `yacimientos.celda` (3 200 px).
2. Cada celda (cx, cy) tiene un azar propio:
   `Ruido.azar(Ruido.hash(semilla, cx, cy, 91))`.
3. Un punto candidato: `x = (cx + azar(0,1; 0,9)) × celda`, lo mismo en y.
   Después, en este orden, `u = azar()` y `r = azar()`. Se tiran siempre los
   cuatro números, haya yacimiento o no, para que el orden no cambie.
4. Se descarta si cae en agua o dentro de una ciudad (`ciudades:dentro`).
5. Se calcula la aptitud de los cuatro tipos (tabla). Gana el de aptitud más
   alta; en empate, el primero en el orden fijo `oro, metal, petroleo, comida`.
   Si todas son 0, no hay yacimiento.
6. Hay yacimiento si `u < densidad[tipo] × aptitud`.
7. Riqueza: `1 + floor(r × 2,99)` (1 a 3); el oro, `1 + floor(r × 1,99)` (1 o 2).
8. Id: `'y:' .. cx .. ',' .. cy`. El prefijo nuevo evita chocar con los ids de
   los depósitos viejos (`'rx,ry#k'`).

**Explotar.** Un yacimiento se explota con **una** instalación encima, y solo
si está dentro del territorio propio (`duenoDeposito(d) == nacion`). Hoy basta
con que sea propio **o de nadie**; esa segunda parte desaparece, y así la
bandera es la que abre el camino.

- **Extracción** (como hoy, `construirExtraccion`): 5 de metal y un convoy de 40
  soldados. Produce F11.
- **Campamento encima:** un campamento cuyo centro queda a menos de
  `yacimientos.radioExplotar` (600 px) de un yacimiento libre lo explota con F11,
  **además** de su producción fija. Ese yacimiento ya no admite extracción
  mientras el campamento siga en pie.
- Un yacimiento, una explotación. Si se destruye la instalación, queda libre.
- Si después de construida la bandera que daba esa tierra cae, la extracción
  **sigue produciendo**: tiene su propio territorio (900 px) y su vida. Para
  quitársela al dueño hay que atacarla y destruirla (ver pregunta 1).

**Icono en el mapa 2D (Valeria y Camila).** Un icono por tipo, del mismo tamaño
en pantalla a cualquier zoom, con el aro del color del dueño que ya dibuja
`Recursos.dibujar` (gris si es de nadie):

| Tipo | Icono propuesto |
|---|---|
| petróleo | gota negra |
| metal | pico y lingote gris |
| oro | pepita dorada (brillo leve) |
| comida | espiga verde |

Encima del icono, la riqueza en puntos (1 a 3). Si está explotado, el icono
lleva un borde del color del dueño.

**Cuándo se ve (propuesta).** Se ve **siempre que esté explorado**, que es lo
que hoy ya hace `depositosVistos` (se llena al explorar un trozo). No hace
falta verlo de cerca: la gracia es verlo de lejos y decidir hacia dónde
estirarse. Lo que no está explorado no se ve. Para cumplir NPC = jugador, un NPC
solo "conoce" los yacimientos a menos de `alcanceMeta` (60 000 px) de su
capital, que es la zona que hoy registra el mundo alrededor de su nación. El
jugador ve lo que exploró, que con el mapa de hoy es un área parecida.

**Qué se hace con `recursos.lua`: se adapta, no se sustituye.** El módulo, su
nombre, `Recursos.dibujar` y la forma de los datos
(`{ id, tipo, x, y, riqueza, altura }`) se quedan. Cambia `deRegion`:

- pasa a devolver los yacimientos de las celdas de 3 200 px que caen en la
  región de 8 192 px (la región se sigue usando para cachear y para
  `datosZona`, `despejados` y `explorarTrozo`, que no cambian);
- se añade el tipo `oro` a `Simulacion.recursos`
  (`{ nombre = 'mina de oro', articulo = 'una' }`) y a `producirRecursos`;
- se añade el icono 2D para el mapa.

La ventaja de adaptar es que `registrarZona`, `e.depositos`, las extracciones
(`'i:' .. d.id`) y el dibujo 3D siguen igual.

**Guardado.** Las partidas de la versión 15 tienen depósitos viejos en
`e.depositos`. En `cargar`, desde la 15: se conservan solo los depósitos que
tienen una extracción encima (para no romperla) y se borran los demás; los
yacimientos nuevos entran al registrar las zonas. Si la extracción vieja se
destruye, su depósito se borra con ella.

### 3.9 Cómo elige el NPC hacia dónde plantar banderas (propuesta)

Sustituye la parte "hacia dónde" de `planearCampamento`, que hoy ya estira el
territorio hacia el depósito sin dueño más cercano. Pasa a
`planearBanderas(n)`, que el NPC piensa cada `bandera.cadaDias` (2) días.
Pensar cada 2 días es el ritmo de la IA, no un límite: en cada vuelta puede
plantar todas las que pueda pagar, y el jugador planta cuando quiera.

1. **Presupuesto.** Solo si tesoro + afuera ≥ coste + `reservaTesoro` (60) y el
   balance de dinero del día cubre el mantenimiento de una bandera más.
2. **Candidatos.** Los yacimientos que conoce (3.8), sin explotar y con dueño
   `nil` o propio pero sin explotación.
3. **Puntuación (F12):**
   `valor = riqueza × necesidad[tipo] / (1 + distanciaBorde / 3000)`, y 0 si a
   menos de 3 000 px del yacimiento hay un sitio de una nación en guerra con
   ella. `necesidad` es la que ya calcula la IA para metal, petróleo y comida
   (`codicia`); para el oro, `necesidad.oro = 1,5` si el tesoro está por debajo
   de 10 veces `reservaTesoro`, y 0,5 si no.
4. **Meta:** el de valor más alto; en empate, el id menor.
5. **Plantar en cadena.** Desde su sitio más cercano a la meta, sigue el rayo
   hacia ella en pasos de 250 px (con los giros 0, ±0,4 y ±0,8 de hoy) y planta
   una bandera en el primer punto válido fuera de su territorio actual que toca
   lo suyo. Repite mientras pueda pagar y la meta no esté cubierta. Las
   banderas en obra no dan territorio, así que en una misma vuelta solo planta
   **una por rayo**; la siguiente sale cuando la anterior termina (2 días). No
   es un tope: es que no hay tierra propia donde apoyarla hasta que termina.
6. **Explotar.** Cuando el yacimiento ya es suyo, `construirExtraccion` lo
   encuentra por las reglas de hoy.
7. **Defender.** Si le atacan una bandera cuyo valor (F12 del yacimiento que
   protege, o 1 si no protege ninguno) es mayor que 1, y tiene un ejército
   libre con fuerza mayor que la del atacante, lo manda (`enviarGrupo`, misión
   `atacar`, contra el grupo). Si no, la deja caer.
8. El campamento sigue en `planearCampamento`, pero ya no busca depósitos: se
   planta en tierra propia cerca de un yacimiento sin explotar (para
   explotarlo, 3.8) o, si no hay, hacia el vecino más cercano, como hoy.

### 3.10 Qué cambia en el código

| Hoy | Propuesta |
|---|---|
| `combatirCiudad` llama a `tomarCiudad` y la capital pasa al ganador **con la nación entera** (ciudades, instalaciones, guerras borradas) | Desaparece. Se sustituye por `saquearCapital(c, g)` (3.3). `tomarCiudad` queda sin llamadas: se puede borrar |
| `combatir` en campamento: `destruirInstalacion` | Igual, más la vida por F3 |
| `combatir` en extracción o base: la toma (`inst.nacion = g.nacion`) | `destruirInstalacion`, igual que el campamento (respuesta 1) |
| — | `combatir` en bandera: rama nueva con F7 (3.7) |
| `limitarAlmacen` tira el exceso | Lo manda a `n.afuera` (3.4) |
| `almacen(nid) = 200 + 150 × ciudades` (siempre 350) | `almacen` por nivel de la capital (F1) |
| El tesoro no tiene tope | Bóveda por nivel (F1b); el exceso va a `n.afuera.dinero` |
| No hay vida de ciudad | `c.vida`, `c.reparacion`, comando `reparar` |
| Grupo sin botín | `g.botin = { metal, petroleo, dinero }` o nil |
| No hay banderas | Instalación `bandera`, comando `bandera`, `planearBanderas` |
| `construirExtraccion` acepta depósitos propios o de nadie | Solo propios |
| `recursos.lua` reparte de 1 a 3 depósitos al azar por región | Yacimientos por celda y aptitud del terreno (3.8, F10); tipo `oro` |
| `planearCampamento` busca el depósito sin dueño más cercano | Lo hace `planearBanderas` (3.9) |

**Guardado:** versión 16. En `cargar`, desde la 15:

- para cada ciudad, `vida = 100` y `reparacion = nil`;
- para cada nación, `afuera = { metal = 0, petroleo = 0, dinero = 0 }`; si su
  tesoro pasa de la bóveda, el exceso pasa a `afuera.dinero` el mismo día de
  cargar;
- los grupos no cambian (`botin` nil);
- depósitos viejos: ver 3.8;
- las partidas antiguas se pueden cargar sin perder nada construido.

**Dibujo del territorio sin dueño:** `territorio.lua` ya guarda `false` donde
`duenoEntre` no encuentra a nadie, y esa celda no se pinta. No hace falta nada
nuevo: al borrar una instalación y llamar a `ensuciar`, su terreno pasa a ser
tierra de nadie en el siguiente redibujado. **Propuesta para Valeria o Camila,
no de simulación:** dejar 30 días de "ruinas" (el dibujo gris) en el sitio,
solo como decorado y sin datos en la simulación.

**Consecuencia que ya existe y conviene saber:** el alcance de la capital
depende de su fuerza (`3000 + casco + 25·√fuerza`). Una capital que pierde toda
su guarnición encoge su territorio. Con 5 000 soldados son unos 1 770 px menos
de radio. Así, perder en la capital **sí** cuesta tierra sin que haya que
programar nada, y concuerda con "lo que se pierde es territorio". Las banderas
que se apoyaban en esa tierra **no** caen: una vez terminadas, siguen dando
territorio aunque ya no toquen lo suyo.

### 3.11 Reglas de la casa (cómo se cumplen)

- **Sin turnos ni topes.** No hay "una reparación a la vez", ni tope de botín,
  ni inmunidad tras el saqueo, ni número máximo de banderas. Lo de afuera no
  tiene tope: solo merma. Lo que limita las banderas es el dinero, el metal y
  el mantenimiento. La separación de 1 500 px entre banderas propias es una
  regla de sitio, como la de los campamentos.
- **Una excepción que ya existe y hay que saber:** `construirExtraccion` hoy
  manda "un convoy a la vez" (`grupoEnCamino`). Eso es un tope de turno en la
  IA; no lo toca este documento, pero choca con la regla de la casa. Se lo
  anoto a Andrés.
- **NPC = jugador.** `reparar`, `bandera`, `campamento` y los ataques pasan por
  `Simulacion:ejecutar`. El saqueo no es un comando: es el resultado de la
  batalla.
- **Determinista.** F3 y F7 usan el `azar` del día que ya se pasa a `combatir`.
  Los yacimientos salen de `Ruido.hash(semilla, cx, cy, 91)` y tiran siempre
  los mismos cuatro números por celda. La merma, la reparación y el
  mantenimiento no usan azar. Las naciones y los yacimientos se recorren con
  `lista` u `ordenadas`.

### 3.12 Futuro (solo anotado)

Vista 3D interior de la ciudad, al estilo de Warpath. Al entrar en la capital se
ven sus edificios; al salir, solo la torre. No afecta a estas reglas. La vida
podría verse en los edificios dañados.

---

## 4. Fórmulas

**F1. Tope del almacén por nivel de la capital (propuesta).**
`tope = almacenNivel[nivel]`, con `almacenNivel = { 200, 350, 500, 700, 1000 }`
para metal y para petróleo.

- Nivel 2 = 350: lo mismo que hoy para una capital recién nacida, así que no
  cambia el arranque.
- Ejemplo: capital de nivel 4 con 690 de metal que produce 30 → 700 guardado y
  20 afuera.
- **Error que corrige: hoy el nivel 5 es inalcanzable.** Cuesta 500 de metal y
  el almacén es de 350. Medido: a los 500 días, **ninguna** capital de las 69
  pasa del nivel 4 en las tres semillas.

**F1b. Tope de la bóveda (propuesta, respuesta 2).**
`boveda = bovedaFactor × almacenNivel[nivel]`, con `bovedaFactor = 10`: 2 000,
3 500, 5 000, 7 000 y 10 000 de dinero.

- Ejemplo: capital de nivel 4 con 6 950 de tesoro que cobra 120 de impuestos →
  7 000 en la bóveda y 70 afuera.
- Referencia medida (primera pasada, versión 15, sin bóveda): tesoro el día 300
  entre 6 715 y 18 788; el día 500, entre 13 800 y 46 200. Con capitales en
  nivel 4 como mucho (bóveda 7 000), casi todas las naciones tendrían dinero
  afuera desde el día 300.
- Equilibrio de lo que queda afuera: `afuera ≈ exceso diario / merma` (F2). Con
  el crecimiento medido del tesoro entre los días 300 y 500 (de 36 a 137 al
  día), serían unos **1 200–4 600 de dinero afuera**. Es una estimación a partir
  de datos medidos, **no una medición con F1b aplicada**: la IA gasta distinto
  cuando tiene tope.

**F2. Merma de lo de afuera.**
`afuera ← afuera × (1 − merma)`, una vez al día, antes de la entrada, en metal,
petróleo y dinero. Con `merma = 0,03`.

- En equilibrio, `afuera ≈ exceso diario / merma`.
- Medido hoy, en los días con el almacén lleno, se tiran de media entre 25 y 33
  de metal al día y entre 7 y 9 de petróleo. Con esos datos el equilibrio sería
  unos 830–1 100 de metal y 240–290 de petróleo afuera: el botín de un saqueo en
  un país rico.
- **No está medido con F1 aplicado:** con topes más altos habrá menos exceso.

**F3. Vida que se pierde en un día de batalla (sitios con guarnición).**
`ΔV = 100 × G / (G + D)`, donde:

- `G = bajasSuyas`, el número que ya calcula el combate:
  `vidaGrupo(atacante) × azar(0,06–0,12)`.
- `D = soldados + 9·tanques + 40·lanzacohetes + 20·baterías` del sitio al
  empezar el día.
- En capitales y extracciones (máximo 100), se resta ΔV. En campamentos, sobre
  la escala de 30: se resta `ΔV × 0,3` a `salud`. En bases (180), `ΔV × 1,8`.

Rango: de 0 a 100 por día. Datos medidos en los 45 días de asalto a capitales
en 500 días, semillas 1, 4242 y 12345, con G en su valor medio
(0,09 × vidaGrupo):

- ΔV entre **0,8 y 17,6** por día;
- en 43 de 45 días, **menos de 5**;
- ningún asalto habría bajado una capital a 0: todos se retiraron antes.

Ejemplo: un atacante de 2 738 de vida contra una capital con D = 6 616 da
G = 246 y ΔV = 100 × 246 / 6 862 = 3,6.

Campamento típico (15 soldados, D = 15) contra un atacante de 300 de vida:
G = 27 y ΔV = 64. Cae en 1 o 2 días.

**F4. Coste de reparar (propuesta).**
Por punto de vida: `metal 2`, `petroleo 1`, `dinero 15`.

- Ejemplo: de 9 a 100 son 91 puntos = 182 de metal, 91 de petróleo y 1 365 de
  dinero.
- Referencia medida el día 100: tesoro entre 529 y 2 604, metal entre 1 y 350,
  petróleo entre 0 y 350. Una reparación completa al principio de la partida
  cuesta de verdad.
- Referencia medida el día 300: tesoro entre 6 715 y 18 788. Ahí el dinero ya
  no frena y lo que frena es el petróleo. Con la bóveda (F1b), parte de ese
  dinero estará afuera, pero se puede gastar igual.

**F5. Ritmo de reparación.**
`ritmo = 2 + nivel` puntos al día.

- Nivel 2: 4 al día, de 9 a 100 en 23 días.
- Nivel 4: 6 al día, en 16 días.

**F6. Efecto de la vida.**
`f(V) = 0,4 + 0,6 × V / 100`.

- Con V = 100, f = 1. Con V = 9, f = 0,454: produce y defiende al 45 %.
- Con V = 50, f = 0,7.

**F7. Vida que pierde una bandera atacada.**
`ΔV = min(100, G × 100 / aguanteBandera)`, con `G = bajasSuyas`
(`vidaGrupo × azar(0,06–0,12)`) y `aguanteBandera = 300`.

- Días hasta caer, con G medio (0,09 × vidaGrupo): `ceil(100 / ΔV)`.
- Ejemplo: grupo de 300 de vida → G = 27 → ΔV = 9 → **12 días**.
- Grupo de 1 000 → G = 90 → ΔV = 30 → **4 días**.
- Grupo de 2 738 (el asalto a capital del ejemplo de F3) → G = 246 → ΔV = 82 →
  **2 días**.
- Rango: una partida de 30 soldados tarda unos 38 días; un ejército de más de
  3 400 de vida la tira en 1 día.
- **Sin medir:** el tamaño de los grupos que la IA mandaría contra banderas.

**F8. Coste de una bandera.**
`dinero 20`, `metal 4`, `petroleo 0`, 0 soldados, `dias 2`.

- Frente al campamento (40, 10, 6, 15 soldados, 6 días): la mitad de dinero,
  menos de la mitad de metal, sin petróleo ni tropa, y un tercio del tiempo.
- Ejemplo: llegar a un yacimiento a 6 000 px del borde con banderas de 1 500 de
  alcance, avanzando unos 3 000 por bandera, son **2 banderas**: 40 de dinero,
  8 de metal y 4 días.

**F9. Mantenimiento de las banderas.**
`gasto diario = bandera.mantenimiento × banderas terminadas`, con
`mantenimiento = 0,2` de dinero.

- Ejemplo: 30 banderas cuestan 6 de dinero al día. Referencia: el tesoro crece
  de 36 a 137 al día entre los días 300 y 500 (derivado de los tesoros medidos esos días); el campamento produce
  1,5 al día.
- A diferencia del campamento, no depende de la distancia: una bandera no
  necesita línea de suministro.

**F10. Densidad de yacimientos.**
`hay yacimiento ⇔ u < densidad[tipo] × aptitud[tipo]`, una prueba por celda de
3 200 px, con `densidad = { petroleo 0,6, metal 0,9, oro 0,3, comida 0,6 }`.

Medido con un prototipo de la regla (`scratchpad/lucia/yacimientos.lua`, fuera
del repositorio; usa `Terreno` y `Ciudades` reales, sin simulación), en
51 × 51 celdas (unas 397 regiones de 8 192 px) alrededor del origen:

| Semilla | Por región | Petróleo | Metal | Oro | Comida |
|---|---|---|---|---|---|
| 1 | 2,16 | 338 (39 %) | 216 (25 %) | 72 (8 %) | 231 (27 %) |
| 4242 | 2,16 | 340 (40 %) | 178 (21 %) | 75 (9 %) | 265 (31 %) |
| 12345 | 2,03 | 340 (42 %) | 186 (23 %) | 55 (7 %) | 226 (28 %) |

Riqueza media: 1,96–2,10 en petróleo, metal y comida; 1,50–1,56 en oro.

Comparación con los depósitos de hoy, medidos en las mismas 400 regiones:
1,97–2,06 por región, con un 27–29 % de metal, un 27–28 % de petróleo, un
42–45 % de comida y riqueza media 1,98–2,01. **La densidad total se mantiene**;
cambia el reparto: más petróleo, menos comida y un 7–9 % de oro nuevo. Es a
propósito: hoy el metal llena el almacén el 49–52 % de los días y el petróleo
solo el 9–16 %.

Reparto del suelo medido en esas regiones (para leer las aptitudes): 33 % agua,
6 % arena, 13 % seca, 28 % pradera, 16 % bosque, 3 % roca y 0,3 % nieve, igual
en las tres semillas con ±0,5 puntos.

**F11. Producción de un yacimiento explotado.**
`produce = riqueza × 1,2 × (0,3 + 0,7 × salud / saludMaxima) × nivel.minas`,
igual que `produccionExtraccion` hoy, y para el oro además `× precioOro`, con
`precioOro = 8`, en dinero.

- Petróleo, metal o comida: de 1,2 al día (riqueza 1, nivel 1) a 7,2 (riqueza 3,
  nivel 5).
- Oro: riqueza 2 en una capital de nivel 3 (`minas = 1,5`) → 2 × 1,2 × 1,5 × 8 =
  **28,8 de dinero al día**, unas 19 veces un campamento.
- Rango del oro: de 9,6 (riqueza 1, nivel 1) a 38,4 (riqueza 2, nivel 5).
- **Sin medir:** cuánto cambia el tesoro con minas de oro. Hace falta la
  simulación con los yacimientos programados.

**F12. Valor de un yacimiento para la IA.**
`valor = riqueza × necesidad[tipo] / (1 + distanciaBorde / 3000)`, y 0 si hay
un sitio enemigo en guerra a menos de 3 000 px del yacimiento.

- `distanciaBorde`: distancia del yacimiento al punto más cercano del
  territorio propio, aproximada como `distancia(sitio más cercano) −
  alcance(sitio)`, con un mínimo de 0.
- Ejemplo: oro de riqueza 2 a 6 000 px del borde con el tesoro bajo
  (`necesidad = 1,5`) → 2 × 1,5 / 3 = 1,0. Petróleo de riqueza 3 a 3 000 px con
  necesidad 1 → 3 / 2 = 1,5. Gana el petróleo.

---

## 5. Casos límite

- **La capital pierde con los dos a la vez** (vida 0 y guarnición 0): una sola
  derrota. Vida 9 y un solo saqueo.
- **Dos grupos enemigos atacan la misma capital el mismo día** (de la misma
  nación o de naciones distintas): se resuelven en el orden fijo de
  `moverGrupos`. El primero que la vence se lleva todo lo de afuera. El segundo
  combate contra lo que quede, y si también la vence se lleva afuera = 0 y la
  vida se queda en 9.
- **Una capital a 9 a la que atacan en plena reparación:** ese día la
  reparación se detiene (sitiada). Si pierde, vuelve a 9 y los puntos
  pendientes **no se pierden**: siguen en `c.reparacion`.
- **Un grupo con botín cuya capital de origen ya no existe:** no puede pasar,
  porque la capital nunca se pierde. Si `volver` no encuentra casa, el grupo y
  el botín se pierden, como hoy.
- **Se pide reparar con la vida a 100, o con puntos que superan 100:** el
  comando devuelve `false` y no cobra nada.
- **Hay afuera pero el almacén o la bóveda están vacíos:** es posible, porque se
  gasta primero de afuera y la merma solo toca lo de afuera. Todo se puede usar.
- **Baja el tope** (hoy no pasa, porque el nivel no baja nunca): lo que sobra
  pasa afuera el mismo día.
- **Instalación en obra que pierde:** se borra igual. Lo pagado no se devuelve.
- **Extracción con guarnición 0 atacada:** cae el primer día, como hoy, pero
  ahora se destruye en vez de cambiar de dueño.
- **Bandera atacada por dos naciones a la vez:** cada grupo le quita su ΔV en
  el orden fijo de `moverGrupos`. La victoria la anota el que la deja en 0.
- **Bandera atacada en obra:** pierde ΔV × 1,5, como toda instalación en obra.
  A 0 se borra y el coste no se devuelve.
- **Bandera cuya tierra de apoyo se pierde** (cae el campamento o encoge la
  capital): sigue en pie y sigue dando territorio. Solo cuenta "pegada" al
  plantarla.
- **Bandera en tierra propia, sin tocar el borde:** está permitida; no amplía
  nada y cuesta su mantenimiento. La IA no lo hace (3.9, paso 5).
- **Dos naciones plantan en el mismo hueco el mismo día:** se resuelven en el
  orden de `ejecutar`. Como las banderas en obra no dan territorio, las dos
  pueden terminarse, y el hueco se reparte por `dueno` como cualquier frontera
  entre instalaciones.
- **Se planta una bandera donde había un campamento enemigo destruido y la
  tierra ya volvió a cubrirla otro sitio enemigo:** no se puede plantar, porque
  la tierra tiene dueño.
- **Yacimiento en la frontera:** se explota solo si `duenoDeposito` da la
  nación que construye. Si la frontera se mueve después, la extracción sigue:
  cuenta solo al construir.
- **Campamento a menos de 600 px de dos yacimientos libres:** explota el más
  cercano; en empate, el de id menor. El otro sigue libre.
- **Yacimiento bajo una ciudad o en el agua:** no existe (paso 4 de F10).
- **Partida de la versión 15 con una extracción sobre un depósito viejo:** el
  depósito se conserva hasta que la extracción se destruye.
- **Nación sin campamentos ni banderas y con la capital a 9:** sigue viva
  (`vivas()` cuenta ciudades). Nunca desaparece por guerra.

## 6. Dependencias

- **Depende de:**
  - [ejercitos-en-el-mapa.md](ejercitos-en-el-mapa.md): los grupos, `volver`,
    las victorias y los choques entre ejércitos (defensa de banderas);
  - [instalaciones-y-economia.md](instalaciones-y-economia.md): el almacén, los
    campamentos, las extracciones, el mantenimiento y el nivel;
  - [retirada-y-recuperacion.md](retirada-y-recuperacion.md): la cola de
    heridos y `heridosACasa`;
  - [guerra.md](guerra.md): los misiles que dañan instalaciones;
  - [mundo-fisico.md](mundo-fisico.md): el terreno, los biomas y la humedad de
    los que salen los yacimientos.
- **Lo usan:**
  - [naciones-y-politica.md](naciones-y-politica.md): `necesidades`, `reservas`
    y `codicia` deben mirar guardado + afuera, y la IA de banderas (3.9);
  - [interfaz.md](interfaz.md): la barra de vida, el botón Reparar, el número
    de afuera, el botón y el aviso de las banderas y los iconos del mapa 2D;
  - [banderas-borde.md](banderas-borde.md) (propuesta del 2026-09-30):
    sustituye 3.7, 3.9 y F9. Solo las banderas del borde son objetos
    atacables, con guarnición y mantenimiento por tierra de bandera;
  - [rebeldes-y-niveles.md](rebeldes-y-niveles.md): usa las celdas, el bloque
    de bandera y `duenoCelda`, extiende F1 y F1b hasta el nivel 50 y añade la
    resistencia R(L) a F3.
- **Pendiente de actualizar en esos documentos:**
  - `guerra.md` dice "las ciudades nunca se conquistan": ya era así en la
    práctica y ahora es regla.
  - `retirada-y-recuperacion.md` y `ejercitos-en-el-mapa.md` describen
    `tomarCiudad`, la caída de la nación y la toma de extracciones: quedan
    obsoletos.
  - `instalaciones-y-economia.md` y `mundo-fisico.md` describen los depósitos
    de `recursos.lua`: hay que cambiarlos por los yacimientos y nombrar este
    documento.

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Qué cambia |
|---|---|---|---|
| `vidaDerrota` | 9 | 1–25 | Lo castigada que queda la capital. Por debajo de 5, casi no produce |
| `almacenNivel` | 200/350/500/700/1000 | ±30 % | Más alto: menos afuera y menos botín. El nivel 4 debe ser ≥ 500 para que el 5 sea alcanzable |
| `bovedaFactor` | 10 | 5–20 | Más bajo: más dinero afuera y botines grandes; más alto: el tesoro vuelve a ser casi infinito |
| `merma` | 0,03 | 0,01–0,08 | Más baja: se acumula más afuera y hay botines grandes. Más alta: el exceso casi se tira, como hoy |
| `reparaCoste` | metal 2, petróleo 1, dinero 15 | ×0,5–×2 | Lo que cuesta volver de 9 a 100 |
| `reparaRitmo` | 2 + nivel | 1+nivel – 5+nivel | Días que pasa débil |
| `f(V)`: mínimo 0,4 | 0,4 | 0,2–0,7 | Lo que duele tener poca vida |
| Pesos de D (1/9/40/20) | — | Iguales a `vidaGrupo` salvo baterías | Lo que aguanta cada defensa. La batería (20) es nueva y se puede ajustar |
| Umbral NPC para reparar | 60 | 30–90 | Lo pronto que repara la IA |
| `bandera.alcance` | 1 500 | 1 000–2 500 | Tierra por bandera. Más alto: menos banderas para llegar y mapas menos llenos de iconos |
| `bandera.coste` | 20 dinero, 4 metal | ×0,5–×2 | Lo rápido que se expande todo el mundo |
| `bandera.dias` | 2 | 1–4 | Lo rápido que avanza una cadena de banderas |
| `bandera.mantenimiento` | 0,2 dinero/día | 0–0,5 | Freno a las redes enormes de banderas. A 0 no hay freno más que el coste de plantar |
| `bandera.separacion` | 1 500 | 1 000–2 500 | Lo apiñadas que pueden estar. Por debajo de 1 000, apilar banderas para aguantar sale barato |
| `aguanteBandera` | 300 | 150–600 | Días que tarda en caer. Más alto: más tiempo para acudir a defenderla |
| `bandera.cadaDias` (IA) | 2 | 1–4 | Lo rápido que reacciona la IA; no limita al jugador |
| `yacimientos.celda` | 3 200 | 2 400–4 800 | Densidad total. Con 4 096 y las mismas densidades se midió 1,17–1,23 por región |
| `densidad` | petróleo 0,6, metal 0,9, oro 0,3, comida 0,6 | 0,1–1 cada una | Reparto entre tipos (F10) |
| Aptitudes (alturas 60/150/190/220, humedad, pendiente 0,1/0,3) | tabla de 3.8 | ±20 % | Dónde sale cada tipo. Cambiarlas obliga a volver a medir F10 |
| `precioOro` | 8 | 4–15 | Lo que vale una mina de oro frente al resto |
| `yacimientos.radioExplotar` | 600 | 300–900 | Lo cerca que debe estar un campamento para explotar un yacimiento |

## 8. Criterios de aceptación

Medir con 500 días en las semillas 1, 4242 y 12345, con el mismo arnés que se
usó aquí (ver "Cómo se midió"):

1. **Ninguna capital cambia de dueño** y el número de naciones vivas el día 500
   es igual al de naciones registradas (hoy 24, 22 y 23).
2. **Ninguna instalación cambia de dueño** por combate. Hoy cambian 19, 13 y 16
   extracciones.
3. Toda capital que pierde queda con `vida == 9` al terminar ese día.
4. `n.afuera` nunca es negativo en ninguno de los tres recursos. Con el almacén
   lleno y sin gasto, lo de afuera baja un 3 % al día.
5. `n.tesoro` nunca supera la bóveda de su nivel al terminar el día.
6. **Nivel 5 alcanzable:** al menos una capital llega al nivel 5 antes del día
   500 en cada semilla. Hoy ninguna.
7. Días de nación con metal lleno: hoy entre el 49 y el 52 %. **Objetivo sin
   medir:** entre el 20 y el 45 % con F1.
8. Un campamento, extracción, base o bandera vencidos desaparecen el mismo día
   y ninguna llegada posterior devuelve soldados de ellos.
9. `reparar` y `bandera` con NPC y jugador dan el mismo resultado desde el mismo
   estado (prueba: la misma orden por `ejecutar` en dos copias).
10. **Yacimientos:** con la regla programada, en las 400 regiones alrededor del
    origen hay entre 1,9 y 2,3 yacimientos por región, y el oro es entre el 5 y
    el 12 % del total (medido con el prototipo: 2,03–2,16 y 7–9 %). Dos
    llamadas a `deRegion` con la misma semilla dan la misma lista.
11. **Banderas en uso:** el día 500, cada semilla tiene al menos 100 banderas en
    pie y al menos el 60 % de las extracciones nuevas se construyen sobre
    tierra ganada con banderas. **Objetivo sin medir**, porque no hay nada
    programado.
12. **Ninguna extracción en tierra de nadie:** en el día en que se ordena, el
    yacimiento es de la nación que la construye.
13. **Disputa:** en 500 días hay al menos 20 banderas destruidas por semilla.
    **Objetivo sin medir**; si da 0, la IA no ataca banderas y hay que tocar
    `objetivo`.
14. **Determinismo:** guardar el día 250, cargar y seguir da el mismo texto de
    `guardar()` que no parar. Una partida de la versión 15 se carga y conserva
    sus extracciones.
15. Menos de 10 ms por día simulado. Es el criterio de
    instalaciones-y-economia.md; en esta medición no se volvió a medir el
    tiempo. Generar los yacimientos de 397 regiones en las tres semillas tarda 0,05 s en
    LuaJIT (medido con el prototipo en las tres semillas).

## 9. Decisiones del dueño (2026-09-27)

1. **Si cae la bandera, la extracción que protegía deja de producir** (opción
   B). Sigue en pie, pero no produce mientras su yacimiento no esté cubierto
   por territorio propio. Tirar la bandera corta el suministro, y el dueño
   tiene un motivo para ir a defenderla.
2. **La bandera aparece sola** (opción A): se levanta en el sitio en 2 días
   de obra, sin grupo, como en Rise of Kingdoms.

---

## Cómo se midió

- **Primera pasada (territorio y capitales).** El arnés se perdió con el corte
  de luz; las cifras de esa pasada son las de la versión anterior de este
  documento. Creaba el mundo con `Mundo.nuevo(semilla)`, sustituía `love` por
  un objeto vacío, registraba 9 naciones alrededor de la inicial (±4 regiones)
  y avanzaba 500 días con `luajit`. Envolvía `tomarCiudad`, `combatirCiudad`,
  `combatir`, `destruirInstalacion` y `limitarAlmacen`, y no cambiaba ninguna
  regla. Resultados:
  - 22–24 naciones vivas el día 500.
  - 0 conquistas de capitales.
  - Entre 4 y 8 asaltos a capitales, que suman 45 días de combate, todos
    rechazados o retirados.
  - 0 combates en tierra contra campamentos. Los 9–54 campamentos destruidos
    por semilla caen por misiles e incursiones.
  - Metal en el tope el 49–52 % de los días de nación; petróleo, el 9–16 %.
  - El día 500, todas las capitales están en el nivel 4 o menos: ninguna en el
    nivel 5.
- **Segunda pasada (yacimientos).** Dos scripts sin simulación, en
  `scratchpad/lucia/` (fuera del repositorio), con `Terreno`, `Ciudades` y
  `Recursos` reales y `luajit`:
  - `estatico.lua`: los depósitos de hoy en las regiones -10..9 × -10..9 (400
    regiones) y el reparto de biomas con una muestra cada 400 px (168 100
    puntos por semilla).
  - `yacimientos.lua`: el prototipo de F10 en 51 × 51 celdas de 3 200 px.
- **Consecuencia para el diseño:** con la IA de hoy, casi nadie saqueará nunca
  una capital, porque los ataques contra capitales son pocos y débiles. Si
  el dueño quiere ver saqueos, hará falta tocar la IA ofensiva (`objetivo`,
  `ofensiva`), lo que está fuera de este documento. Lo mismo vale para las
  banderas: sin cambios en `objetivo`, la IA no las atacará (criterio 13).

# Nations RTS: la idea del juego

Qué es el juego, hacia dónde va y las decisiones del dueño.
Reescrito el 2026-10-02 con el GDD «Guerra Moderna RTS»
(`diseno/GDD-guerra-moderna-rts.pdf`) y las decisiones del dueño de ese día.
Sustituye a la visión anterior (mundo procedural, naciones con NPC y mapa 2D
isométrico); lo que queda superado está en la sección 7.

Si algo de aquí choca con el código, el código dice cómo funciona **hoy** y este
documento dice **hacia dónde va**. Si choca con un documento de `diseno/`, este
es más reciente. Lo marcado **[Propuesta]** es del estudio y espera el visto
bueno del dueño; lo marcado **[Pendiente]** no está decidido.

**Nota sobre el «2D» del GDD.** Donde el GDD dice «mapa operativo 2D», «capa
estratégica 2D», «2D/3D» o «red de apoyo remoto 2D → 3D», se refiere al
**mapa de campaña (3D, cámara desde arriba)**, como el de Bannerlord. En este
juego todo es 3D. La «vista de radar» del GDD es solo un modo de visualización
del mismo mapa, con una tecla, no una capa aparte.

---

## 1. El juego en pocas palabras

Es **casi lo mismo que Bannerlord, pero en guerra moderna**, y en el Cáucaso.

El jugador empieza **desde abajo**, en el puerto franco de Dioskar: una persona
cualquiera, un combatiente o contratista con poco. Firma contratos, recluta, monta su propia compañía
militar privada (PMC), gana reputación y, con el tiempo, poder e influencia.
Al principio no es dueño de ninguna ciudad ni de ninguna nación.

El bucle del GDD, adaptado a «todo en 3D»:

1. **Mapa de campaña (3D, cámara desde arriba):** convoyes, combustible,
   reclutamiento, contratos y encuentros.
2. **Hub urbano 3D:** la ciudad por dentro (taller, hangar, mercado negro,
   reclutamiento). **[Pendiente]** cómo se recorre a pie.
3. **Batalla táctica 3D estilo Bannerlord:** armas combinadas, con el jugador
   peleando en persona en el campo.
4. **Después de la batalla:** chatarra, vehículos capturados, munición y
   reparaciones.

El juego se hace **paso a paso**: no todo a la vez. La sección 6 propone el
orden.

## 2. El mapa de campaña

**[Decisión del dueño]**

- **Un solo mapa fijo**, no procedural.
- **Relieve real del Cáucaso y el Mar Negro**, de 37° a 48° E y de 40° a
  45° N: unos 903 × 557 km. Abarca:
  - el Mar Negro al oeste y el Caspio al este;
  - el Gran Cáucaso en diagonal;
  - el valle central;
  - el Cáucaso Menor y el altiplano volcánico al sur;
  - la estepa al norte.
- **Nombres inventados:** países, ciudades y facciones son ficticios; la
  geografía es real.
- **En 3D, como Calradia en Bannerlord**, con cámara desde arriba y una tecla
  para cambiar a **vista de radar** (aún no está).
- **Misma iluminación que la batalla 3D.**

Hoy:

- Hay un prototipo en `campana/` (`mapa3d.lua`, `camara.lua`,
  `luz_campana.lua`, `sombreador_mapa.lua` y el visor de `campana/visor/`).
- Los datos del relieve salen de `tools/mapa/caucaso.py` (DEM Copernicus
  GLO-90) a `assets/mapa/`.
- Unidades del mapa: 1 = 1 km, X al este, Z al sur y el origen en el centro.

## 3. Asentamientos

**[Decisión del dueño]** Ciudades y pueblos como en Bannerlord, modestos y
modernos, **sin castillos**. El detalle está en `diseno/asentamientos.md` y
los datos en `campana/asentamientos.lua`.

- **Ciudades:** centros económicos, políticos y de reclutamiento: mercado,
  cuartel general, diplomacia local, taller, hangar, fábrica de munición,
  refinería y mercado negro. Ahí ocurren los asedios urbanos.
- **Pueblos:** motores económicos. Producen materias primas y abastecen a una
  ciudad.
- Al principio las ciudades no son del jugador: son sitios donde contratar,
  reclutar y comerciar.

**[Decisión del dueño, 2026-10-02]**

- **Economía:** los pueblos dan materia prima y la ciudad la convierte
  (crudo en combustible, acero y explosivos en munición y repuestos, comida y
  reclutas en tropas).
- **Inicio del jugador** en el puerto franco de Dioskar.
- **Campamentos de milicia** al estilo de las guaridas de bandidos de
  Bannerlord.
- Las siete facciones de la sección 5.1.

**[Propuesta]** (en `diseno/asentamientos.md`):

- 18 ciudades y 67 pueblos con sus posiciones.
- Pueblos de cinco tipos: comida, reclutas, acero, explosivos y crudo.
- Ritmos y cifras de producción (sin medir).

**[Decisión del dueño, 2026-10-02]** Lo que puede llegar a poseer el
jugador, en este orden:

1. plaza de hangar en una ciudad, con reputación;
2. taller propio al fundar su PMC;
3. proteger un pueblo a cambio de parte de su producción;
4. una ciudad, concedida o conquistada.

## 4. La batalla 3D

**[Decisión del dueño]**

- **Sigue siendo una batalla 3D estilo Bannerlord.**
- **El jugador está en el campo con su propio soldado.** Pelea en persona y,
  a la vez, manda a su tropa con las órdenes F1 a F3 del GDD:
  - F1: movimiento;
  - F2: formación;
  - F3: reglas de enfrentamiento.
- **Cámara:** por defecto en tercera persona, detrás del hombro; una tecla
  cambia a primera persona.
- **Infantería:** robots soldado (el dueño, 17-nov: solo robots que actúan como
  humanos; los soldados humanos se descartaron), con ruedas u orugas
  (`assets/batalla/robots/`, `batalla/robots/`).

Del GDD, para más adelante:

- armas combinadas (fusileros, antitanque, MBT, drones);
- supresión y moral;
- blindaje por sectores;
- TEL y misiles con sus fases, guiados, CEP y radios de daño;
- asedios urbanos en la misma ciudad del hub.

Hoy:

- Hay batalla 3D en `batalla/` con 3DreamEngine: vehículos, soldado y
  despliegue.
- El personaje del jugador en el campo y la cámara al hombro aún no están.
- Notas técnicas en `GUIA-3D.md`.

## 5. Facciones, NPC, economía y progresión

### 5.1 Facciones como los reinos de Bannerlord

Las facciones siguen el modelo de los reinos de Bannerlord (allí son 8: el
Imperio partido en tres, Vlandia, Sturgia, Battania, Aserai y Khuzait), cada
una con su región, su cultura y su estilo militar, adaptado a la guerra
moderna en el Cáucaso y con nombres inventados.

**[Decisión del dueño, 2026-10-02]** Siete facciones:

| Facción | Tipo (GDD) | Región |
|---|---|---|
| Unión Voskara | Ejército estatal | Estepa y vertiente norte, del Mar Negro al Caspio |
| República Kelvana | Ejército estatal | Cólquida y valle central |
| Federación Hazarlí | Ejército estatal | Llano del Kurá y vertiente sur del Gran Cáucaso |
| República de Anzerat | Ejército estatal | Altiplano volcánico del sur |
| Liga de Pontara | Ejército estatal | Costa del Ponto |
| Hermandad de Ardzun | Milicia regional | Piedemonte y valles altos del norte |
| Puerto franco de Dioskar | Neutral | Costa nordeste del Mar Negro; ciudad de inicio del jugador |

Las PMC no tienen territorio: van de contrato en contrato, como los clanes
mercenarios de Bannerlord. El estilo de tropas de cada facción está propuesto
en `diseno/asentamientos.md`.

**Tipos de facción (GDD 8.1):**

| Tipo | Doctrina | Ventajas | Desventajas |
|---|---|---|---|
| Ejército estatal | Alta intensidad y control territorial formal | MBT de vanguardia, aviación y artillería pesada (TEL), bases muy fortificadas, presupuesto alto | Burocracia (decisiones lentas en el mapa), mucho consumo de combustible, reglas de enfrentamiento estrictas (castigo por daño colateral y bajas civiles) |
| PMC | Flexibilidad táctica, eficiencia y tecnología punta | Drones avanzados, visores térmicos, tropas veteranas resistentes a la supresión, libertad diplomática total | Poco blindaje superpesado propio, costes altos en dinero, sin territorio fijo |
| Milicia / insurgencia | Guerra asimétrica, emboscadas y movilidad | Firma mínima en el mapa, poco consumo de combustible, IED y trampas, reclutar y mantener es barato | Sin blindaje pesado, tecnología vieja, moral que se rompe bajo supresión de gran calibre |

**Clanes y divisiones (GDD 9.1).** Cada facción se divide en grupos que
compiten por influencia, contratos y ciudades:

- Ejércitos estatales: comandos de ejército (por ejemplo, «1.er Comando de
  Blindados») con generales de carrera que responden a un alto mando.
- PMC: compañías con junta directiva y accionistas que compiten por los
  contratos de los gobiernos.
- Milicias: clanes y familias dirigidos por señores de la guerra, con
  alianzas de sangre; dominan montañas y zonas rurales.

**Reputación (GDD 8.2):** de −100 a +100 con cada facción:

- Aliado de honor (+51 a +100): vehículos de élite, −30 % en suministros y
  hangares libres.
- Favorable (+11 a +50): contratos de alto valor y tropas veteranas.
- Neutral (−10 a +10): precios estándar y zonas de alta seguridad cerradas.
- Hostil (−49 a −11): embargo parcial y +50 % al reabastecer.
- Enemigo mortal (−100 a −50): ataque a primera vista y patrullas que cazan
  la columna del jugador.

Cambiar de bando a mitad de misión (traición) cuesta −50 con la facción
traicionada.

**Generales de ejemplo del GDD (9.2), repartidos entre las facciones
[Propuesta]:**

| General | En el GDD | Facción propuesta | Especialidad | Historia |
|---|---|---|---|---|
| Marcus Vance, «El Arquitecto» | Ejército estatal, 1.er Comando | Unión Voskara (1.er Comando de Artillería, Kamennovodsk) | Artillería y TEL: −30 % de tiempo de anclaje, +20 % de área de daño | Ex profesor de la academia militar, obsesionado con aplastar a distancia con artillería |
| Elena Rostova, «Sombra» | PMC Halvaren Security Group (en el GDD, «Aegis Security») | PMC con base en Dioskar, contratada sobre todo por Kelvana | Drones y ciberguerra: revela posiciones en la niebla, drones FPV con +50 % de alcance | Desertora de los servicios de inteligencia, pionera de las redes de reconocimiento con drones |
| Tariq Al-Mansoor | Milicia, Clan de la Sombra | Hermandad de Ardzun (señor de la guerra de Uzdenkala) | Guerra asimétrica e IED: −40 % de combustible, emboscadas nocturnas sin aviso | Veterano de tres guerras civiles; conoce cada paso de montaña |
| Viktor Vane, «Hierro» | PMC Brakhmor Armored Company (en el GDD, «Vanguard Corps») | PMC contratada por la Federación Hazarlí | Blindados pesados: +15 % de blindaje frontal en MBT, reparaciones un 25 % más rápidas | Ex comandante de tanques de un ejército regular; vende sus servicios tras la disolución de su unidad |

**[Decisión del dueño, 2026-10-02]** Las dos PMC del GDD llevan nombres
inventados, porque los originales coinciden con empresas u organizaciones
reales: «Aegis Security» se llama **Halvaren Security Group** y «Vanguard
Corps» se llama **Brakhmor Armored Company**.

**Árbol de habilidades (GDD 9.3).** El jugador y los generales ganan
experiencia en el mapa y en la batalla. Cuatro ramas:

- **Logística:** consumo de diésel, capacidad de carga y coste de reclutas.
  Nivel 50, «Marcha forzada» (+15 % de velocidad por carretera); nivel 100,
  «Red de suministros» (+20 % de cajones de munición en los talleres).
- **Táctica:** resistencia a la supresión, velocidad de formación y
  precisión. Nivel 50, «Disciplina de hierro» (+35 % de tiempo hasta la
  supresión); nivel 100, «Reorganización rápida» (órdenes sin retardo).
- **Ingeniería:** tiempo de TEL, reparación y fortificación. Nivel 50,
  «Dispara y muévete» (repliegue del TEL a la mitad); nivel 100, «Refuerzo
  modular» (ERA gratis en los MBT comprados).
- **Guerra electrónica:** alcance de drones, inmunidad a interferencias y
  marcado láser. Nivel 50, «Firma fantasma» (−40 % de radio de detección);
  nivel 100, «Enlace de datos» (lo que ve un dron queda marcado para la
  artillería).

### 5.2 NPC como en Bannerlord

**[Decisión del dueño]**

- **Generales y señores autónomos**, cada uno con su columna en el mapa:
  reclutan, comercian, patrullan, hacen la guerra y conquistan
  asentamientos.
- **Compañeros** que el jugador puede contratar para su compañía.
- **Notables** en ciudades y pueblos que dan contratos y misiones.
- **Los NPC usan las mismas reglas que el jugador:** mismas acciones, mismos
  costes, mismo combustible y misma munición.

### 5.3 Economía y progresión (del GDD)

- **Economía logística:**
  - combustible (diésel o JP-8), gastado por kilómetro según el peso de la
    columna;
  - munición ligera, pesada y de 120 mm o ATGM;
  - kits de repuestos.
- **Firma térmica y de radar:** las carreteras son rápidas y visibles; los
  bosques y cañones, discretos y caros.
- **Personalización** (GDD 6) en el taller: ERA, rejas anti-RPG y RWS para
  los vehículos; visores nocturnos o térmicos para la infantería
  (`diseno/diseno-de-armamento.md`).
- **Contratos** (escolta de convoyes, eliminación de objetivos, defensa de
  infraestructura y asalto a bases), **traición** y **mercado negro**
  (GDD 8.3).

**[Pendiente]**

- **Cómo se gana o se pierde la partida.**
- **El hub urbano 3D a pie:** qué se ve, cómo se entra y qué se hace dentro.
- **El detalle de las facciones:** estilo de tropas, clanes y generales
  concretos de cada una (hay propuestas en la sección 5.1 y en
  `diseno/asentamientos.md`).
- Si el juego tendrá modo en línea y cómo.

## 6. Orden de construcción por etapas

**[Decisión del dueño]** Orden aprobado por el dueño el 2026-10-02.

Etapas pequeñas, cada una jugable o visible, empezando por lo que ya existe.
El dueño aprueba cada etapa antes de la siguiente.

1. **Mapa de campaña visible:** el relieve 3D con la luz de la batalla, la
   cámara desde arriba y las 18 ciudades y 67 pueblos como iconos con su
   nombre.
2. **Vista de radar:** la tecla que cambia el mismo mapa a vista de radar.
3. **La columna del jugador en el mapa:** una ficha que se mueve con el ratón
   por el relieve y gasta combustible por kilómetro.
4. **Entrar a una ciudad:** un menú (aún no el hub a pie) para contratar,
   reclutar y comprar munición y combustible.
5. **Encuentro y batalla:** chocar con una columna enemiga en el mapa abre la
   batalla 3D con las tropas reales de los dos bandos.
6. **El soldado del jugador en la batalla:** cámara al hombro, primera persona
   con una tecla y las órdenes F1 a F3 para su tropa.
7. **Después de la batalla:** bajas, munición gastada, chatarra y vehículos
   capturados vuelven al mapa.
8. **Pueblos que producen** y convoyes civiles a su ciudad (atacables).
9. **Notables y contratos:** un notable por ciudad que da contratos sencillos
   (escoltar un convoy, limpiar un campamento), con reputación.
10. **Primeras facciones con generales básicos:** 2 o 3 facciones (por
    ejemplo, la Unión Voskara, Kelvana y la Hermandad de Ardzun) con generales
    que se mueven, reclutan y atacan con las mismas reglas que el jugador.
11. **Compañeros contratables** en las ciudades.
12. **El resto de facciones**, clanes, personalidad e historia de los
    generales, comercio y conquista de asentamientos por los NPC.
13. **Más adelante, en este orden aproximado:**
    - hub urbano 3D a pie;
    - asedios urbanos;
    - supresión y blindaje por sectores;
    - TEL y misiles;
    - mercado negro;
    - árbol de habilidades.

## 7. Lo que ya no vale

Superado por el GDD y las decisiones del 2026-10-02:

- **El mundo procedural infinito y las semillas.** Hay un solo mapa fijo con
  relieve real.
- **El mapa 2D isométrico.** El mapa de campaña es 3D con cámara desde
  arriba.
- **Las naciones con territorio procedural:**
  - zonas de 3×3 regiones;
  - una capital con torre;
  - fronteras pintadas por celdas;
  - campamentos de metal, petróleo o dinero.
- **El jugador como presidente o alcalde de su nación.** Ahora empieza desde
  abajo, sin ciudad.
- **Presidentes NPC con órdenes políticos** (Alba, Estandarte, Concordia) y la
  guerra de salvas de misiles contra instalaciones. La política pasa a ser
  facciones con reputación, contratos y generales.
- **La economía cerrada del 2026-09-30:**
  - un solo dinero;
  - producción a mano con tope por nivel;
  - vehículos que no se destruyen.

  La sustituye la economía logística del GDD.
- **La demografía por edades y sexo.** Los reclutas salen de los pueblos y
  ciudades.
- **Escala de naciones sin límite** con niveles de detalle y sectores
  procedurales.
- **El kit de piezas por nación** (diseños propios, estilos heredados y
  diseños secretos). La personalización es la del GDD: ERA, rejas anti-RPG,
  RWS y visores.

Documentos de `diseno/` superados (se conservan como historia, con una línea
al principio que lo indica):

- `mundo-fisico.md`
- `naciones-y-politica.md`
- `instalaciones-y-economia.md`
- `poblacion.md`
- `economia.md`
- `guerra.md`
- `diplomacia.md`
- `banderas-borde.md`
- `escala-del-mundo.md`
- `territorio-y-capitales.md`
- `rebeldes-y-niveles.md`
- `recoleccion-y-batallas.md`
- `ejercitos-en-el-mapa.md`
- `taller-por-zona.md`
- `modo-base.md`
- `retirada-y-recuperacion.md`
- `revision-interfaz-2026-10-01.md`

Siguen sirviendo, total o parcialmente:

- `batalla-despliegue-y-movimiento.md` y `movimiento-unidades-batalla.md`
  (batalla 3D).
- `catalogo-armamento.md` (armamento real por su designación).
- `interfaz-militar.md` (estilo: acero oscuro, dorado y gris claro).
- `convencion-documentacion.md`.
- `diseno-de-armamento.md`, reducido a la personalización del GDD
  **[Decisión del dueño, 2026-10-02]**: ERA, rejas anti-RPG, RWS y visores
  nocturnos o térmicos. El kit de piezas por nación queda superado en su
  anexo.
- **[Pendiente]** `encargo-diseno-hud.md`: los iconos pueden aprovecharse,
  pero la pantalla para la que se pidieron era la del mapa viejo.

Código del juego anterior que sigue en el repositorio (`mundo/`, con la
simulación, el terreno procedural y el mapa isométrico): no se ha borrado.
**[Pendiente]** qué se reaprovecha.

## 8. Decisiones del dueño que siguen vigentes

1. **Estilo realista militar low-poly**, nítido, como en Unreal:
   - nada de imágenes lavadas, neblina ni desenfoque «por estilo»;
   - máxima calidad de cerca, ahorro en lo lejano.
2. **Armamento real**, nombrado por su designación. Todo lo político
   (países, ciudades, facciones y personas) es inventado.
3. **Colores de bando:**
   - camiones y tanques sin la franja de la nación;
   - el soldado lleva el color en la cinta del casco.
4. **Rendimiento con toda la tecnología:** hilos, caché, LOD, sombreadores y
   C o C++ si Lua no alcanza.
5. **Interfaz de estilo militar:** acero oscuro, dorado y gris claro
   (`diseno/interfaz-militar.md`).
6. **Todo en español:** textos del juego, comentarios, commits y documentos.
7. **Estilo de código del dueño:**
   - nada compactado, una sentencia por línea y espacios en los operadores;
   - camelCase, y una clase por responsabilidad;
   - `stylua` y `luacheck` sin avisos.
8. **Sin topes artificiales:** solo los recursos y el tiempo limitan, y los
   NPC (generales, señores y compañeros) usan las mismas acciones y reglas
   que el jugador (sección 5.2).

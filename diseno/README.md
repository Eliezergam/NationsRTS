# Nations RTS: documento de diseño

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02). Este README describe el juego anterior. El índice sigue al día:
> los documentos marcados «superado» se conservan como historia; el rumbo
> nuevo está en `../VISION.md` y en `asentamientos.md`.

Estado a 2026-09-25. Describe cómo funciona **hoy** el juego según el código
(`mundo/simulacion.lua` manda sobre todo lo demás). Lo que se propone cambiar va
siempre aparte, marcado como **Propuesta**. El dueño decide.

## Índice

| Documento | Sistema |
|---|---|
| [diseno-de-armamento.md](diseno-de-armamento.md) | Personalización de vehículos e infantería (decidida el 2026-10-02, sin programar): ERA, rejas anti-RPG, RWS y visores; el kit de piezas por nación queda superado en su anexo |
| [asentamientos.md](asentamientos.md) | Asentamientos del mapa de campaña del Cáucaso (2026-10-02, propuesta, sin programar): 18 ciudades y 67 pueblos, qué produce cada pueblo, vínculo con su ciudad, las 7 facciones (decididas), inicio en Dioskar, campamentos de milicia y lo que puede poseer el jugador; datos en `campana/asentamientos.lua` |
| [mundo-fisico.md](mundo-fisico.md) | **Superado.** Terreno, biomas, ciudades, plantas, depósitos, escalas de región y zona |
| [naciones-y-politica.md](naciones-y-politica.md) | **Superado.** Zonas, capitales, 3 órdenes políticos, presidentes, relaciones, declarar la guerra, días de tensión y calma |
| [instalaciones-y-economia.md](instalaciones-y-economia.md) | **Superado.** Población, investigación, presupuesto, fábricas, convoyes, carreteras, extracción, bases, fortificación |
| [poblacion.md](poblacion.md) | **Superado.** Demografía (decidida el 2026-09-30): cohortes por edad y sexo, parejas y natalidad, mortalidad, reclutamiento de adultos, muertos en combate que restan, retiro, trabajo, vivienda por nivel |
| [economia.md](economia.md) | **Superado.** Economía cerrada (decidida el 2026-09-30): un solo dinero, producción a mano con tope por nivel, munición, vehículos que se averían y no se destruyen, reparación, sueldos, batalla 3D 1:1 |
| [guerra.md](guerra.md) | **Superado.** Misiones terrestres, salvas, interceptores, incursiones aéreas, refuerzos, golpes a ciudades, crímenes de guerra, impactos diferidos |
| [taller-por-zona.md](taller-por-zona.md) | **Superado.** Taller por zona (programado el 2026-10-01, versión 28): orugas, torreta, cañón, motor y casco con su trabajo, dinero y metal; bajas de tripulación; medidas a 500 días y propuestas |
| [diplomacia.md](diplomacia.md) | **Superado.** Negociación, cansancio, alto el fuego, paz, cesiones |
| [catalogo-armamento.md](catalogo-armamento.md) | Catálogo de armamento real (propuesto el 2026-09-30, sin programar): tanques y lanzacohetes reales con su ficha pública, fórmulas que la traducen a cifras de juego, eras por tecnología, Arsenal y modelos 3D |
| [banderas-borde.md](banderas-borde.md) | **Superado.** Banderas del borde (propuesta del 2026-09-30, sin programar): solo el borde lleva bandera atacable, la nueva aparece al caer una, guarnición con tope y panel de tropas |
| [escala-del-mundo.md](escala-del-mundo.md) | **Superado.** Escala del mundo (decidida el 2026-09-30): naciones sin límite con niveles de detalle (fondo, dormida, resumida, completa), guardado por diferencias, servidor que simula a los NPC, sectores, protocolo de red, una misma partida con y sin conexión |
| [batalla-despliegue-y-movimiento.md](batalla-despliegue-y-movimiento.md) | Batalla 3D: preparación de 2 minutos, zonas de despliegue, colocación instantánea y órdenes de movimiento (encargo del dueño del 2026-10-01, pasos 1 y 2 programados) |
| [movimiento-unidades-batalla.md](movimiento-unidades-batalla.md) | Movimiento de unidades en la batalla 3D (propuesto el 2026-10-01, sin programar): estudio de 0 A.D. (GPL 2+, solo ideas), cuadrícula de pasabilidad por clase, buscadores largo y corto, índice de alcanzabilidad, seguimiento sin atascos, empujones, cola de órdenes contextuales, formaciones «cuadrado» y «esparcidos», plan en 9 pasos y umbrales para ir a C |

## El juego en una página

**Qué es.** Un mundo procedural infinito en isométrico, al estilo de No Man's
Sky: todo lo físico (terreno, plantas, ciudades, depósitos) sale de una semilla
y es idéntico en cualquier máquina. Encima vive un mundo político: **naciones
ficticias gobernadas por NPCs** que crecen, investigan, fabrican armas, levantan
instalaciones y **se hacen la guerra por ellas**.

**Mundo físico.** Regiones de 12 288 px con un 55 % de probabilidad de ciudad.
Cada 3×3 regiones (una *zona*, 36 864 px de lado) es una nación: su ciudad más
grande es la capital. Los depósitos (metal, petróleo, comida) están en regiones
de 8 192 px, 1 a 3 por región: unos 50 por zona.

**Mundo vivo.** Cada nación tiene un presidente (agresividad y prudencia al
azar) y pertenece a uno de tres órdenes políticos: Orden del Alba, Liga del
Estandarte (enemigos entre sí) y Concordia. Las relaciones derivan cada día
según el orden, la cercanía y los recursos en disputa. Cuando una relación cae
por debajo de −60 y la nación se ve más fuerte, declara la guerra.

**Economía e instalaciones.** Las ciudades crecen y producen; la producción paga
investigación (7 tecnologías), soldados y una fábrica que rota entre las bases.
Las naciones mandan convoyes que abren carretera y levantan complejos de
extracción sobre los depósitos, y bases militares hacia el vecino. Todo lo
construido se fortifica durante un año.

**Guerra.** Contra instalaciones, no contra ciudades: salvas de misiles contra
interceptores, incursiones aéreas contra cazas, grupos terrestres que toman
instalaciones y refuerzos del atacado. A las ciudades solo llegan golpes sueltos
cada 2 a 20 días, y si alguno pasa las defensas es un crimen de guerra. Las
ciudades solo cambian de manos cedidas en un tratado.

**Diplomacia.** Los presidentes negocian según el cansancio de guerra: alto el
fuego de 5 a 29 días, paz con concesiones o fracaso. Al acabar un alto el fuego,
o se rompe o "la calma se consolida" en paz, con 90 días de tregua.

**En línea y sin internet.** La simulación es determinista (azar de
`Ruido.hash`, recorridos en orden fijo, sin LÖVE) y todo cambio externo es un
comando (`Simulacion:ejecutar`). Solo lo vivo se guarda: F5/F9 en local; en
línea, el servidor corre la misma simulación y reparte el estado.

**El jugador aún no existe.** Hoy se mira: se explora con la cámara, se abren
paneles de ciudades e instalaciones, se cambia la velocidad (un día = 60, 20, 5
o 1 s) y se puede provocar una guerra con G. No hay ciudad propia, soldados ni
órdenes del jugador.

## Números clave medidos

Arnés sin ventana (LuaJIT, stub de `love`), 16 zonas (4×4, de −2 a 1), 500 días,
6 semillas (4242, 1, 7, 99, 12345, 2026). Determinismo y guardar/cargar a mitad:
**idénticos** (semilla 4242).

| Medida (500 días) | Rango en 6 semillas |
|---|---|
| Naciones vivas / ciudades | 13–16 / 31–48 |
| Instalaciones de extracción | 426–537 (11,2–14,2 por ciudad) |
| Bases | 127–202 (4,0–4,2 por ciudad), topadas hacia el día 100 |
| Guerras declaradas | 33–68 (2,5–4,3 por nación) |
| Primera guerra | día 7–34 |
| Tecnología 7 (precisión), mediana | día 34–55 |
| Salvas / misiles lanzados / interceptados | 543–931 / 6 690–10 496 / 54–65 % |
| Tomas de instalaciones / destruidas | 10–18 / 46–106 |
| Crímenes de guerra | 5–12 |
| Cesiones de ciudad | 1–3 |
| Tiempo de simulación por día (mediana) | 2,9–5,3 ms |
| Partida guardada | 1,2–1,6 MB |

## Huecos y preguntas abiertas, por prioridad

1. **El jugador.** ¿Quién es: presidente de una nación, un soldado, un mercenario
   sin bandera? Todo lo demás (escala, ritmo, qué se enseña) depende de esto.
   Hoy la única vía prevista son los comandos de `ejecutar`.
2. **Ritmo real vs. simulado.** A 60 s por día, las bases se topan en ~100 min,
   las 7 tecnologías llegan en ~45 min y luego la investigación no sirve para
   nada. ¿Cuánto debe durar "el arranque" de una nación en horas de juego?
3. **No hay escasez.** Metal, petróleo y comida acaban en miles sin gastarse
   (mediana de metal 2 200–6 000 a 500 días); la población crece sin techo
   (×2,7 de día 500 a 1000). Hoy los recursos no deciden nada. ¿Deben limitar
   la fabricación, la población o ambas?
4. **Las guerras se apagan solas.** Del 83 al 91 % acaban porque un alto el
   fuego expira y "la calma se consolida"; la paz negociada con concesión es
   rara (4–9 por semilla). ¿Quieres que la guerra termine por decisiones
   (victoria, derrota, tratado) o por agotamiento?
5. **El mundo vivo depende de lo que se ha explorado en esta máquina.** Solo
   simulan las zonas registradas al ver ciudades. Dos jugadores que exploren
   distinto tendrían mundos vivos distintos: hay que decidir qué zonas simula el
   servidor y cuándo "nace" una nación.
6. **Relaciones decididas por el orden político.** Los pares del mismo orden
   acaban en +100 y los opuestos en −100 (mediana de vecinos: −57 a −100). La
   agresividad y los sucesos pesan poco. ¿Es la fantasía que buscas (bloques
   ideológicos) o quieres alianzas y traiciones?
7. **Ruido de noticias.** Incidentes fronterizos y acuerdos comerciales salen
   unos 200–255 de cada en 500 días (crece con el cuadrado de naciones) y el
   diario solo guarda 60: tapan lo importante.
8. **Crímenes de guerra sin castigo real.** Bajan relaciones, pero las del
   agresor con sus enemigos ya suelen estar en −100. ¿Qué debe costar de verdad
   un crimen de guerra?

## Ideas decididas por el dueño, aún sin programar

- **Ciudades con nivel, defensas y conquista (2026-09-25).** Plan en 6 pasos:
  1. **Comida por ciudad**: cada ciudad tiene su granero y solo alimenta a su
     gente (sus tierras y las granjas de su territorio). La población trabaja:
     sin comida hay menos trabajo y menos fabricación. El metal y el petróleo
     van al almacén del país.
  2. **Niveles 1 a 5, como en Bannerlord**: el presidente mejora ciudades con
     el almacén del país; la mejora tarda días. El nivel multiplica lo que dan
     sus minas (×1 a ×2) y fija cuántas defensas admite.
  3. **Lanzacohetes y baterías antiaéreas** con tope por nivel (2, 5, 10, 18,
     30): el presidente los reparte para resguardar sus ciudades, y puede
     equivocarse (nivel 5 sin defensas).
  4. **Conquista**: los misiles destruyen defensas y un ejército ocupa; la
     ciudad y su territorio pasan al atacante. **Si cae la capital, cae la
     nación entera** (falta decidir si sus ciudades pasan al conquistador o se
     independizan: **decidido, pasan al conquistador**). Crimen de guerra solo si un misil cae sobre civiles;
     atacar defensas es legítimo.
  5. **Exploradores**: ven el nivel de una ciudad, no sus defensas; con su
     informe el presidente decide si ataca.
  6. **Comercio** entre países y ajuste de todos los números.

- **Los NPC son como jugadores (2026-09-25).** Un presidente NPC y un jugador
  tienen las mismas acciones con las mismas reglas y costes; el NPC solo decide
  con su propia lógica. Los NPC pueden atacar a jugadores y al revés. (En el
  código cada acción pasa por `Simulacion:ejecutar`; no es una consola ni un
  truco: es la puerta única para NPC y jugadores.)
- **Alianzas (2026-09-25).** Según la relación, un presidente NPC manda una
  solicitud de alianza a otro NPC o a un jugador, que la acepta o no. Los
  aliados se ayudan si el enemigo que ataca a su aliado les queda cerca. Entre
  órdenes opuestos (Alba y Estandarte) una alianza es rara pero posible. Habrá
  sanciones y otras medidas diplomáticas.
- **Cómo empieza un jugador (2026-09-25).** Como alcalde de un pueblo pequeño:
  recoge recursos, pone a producir a sus ciudadanos, genera dinero y con él
  compra tecnología (por ejemplo, construir su refinería de petróleo). Es
  distinto del arranque de una nación NPC; se hará con la lógica del jugador.
- **Estilo y misiles (2026-09-26).** Estilo visual militar realista (verde
  oliva, modelos en Blender, `tools/blender/`). Lanzacohetes de 4 tubos en un
  camión: el contenedor pivota atrás, levanta el frente y dispara sobre la
  cabina con el morro hacia el blanco; un misil por segundo real por
  lanzacohetes. La estela nace en punta en la tobera, es densa y se deshace
  2 s después de pasar el misil. Misiles y humo tienen tamaño de mundo: al
  alejar la cámara se ven más pequeños. Así funcionan los misiles del juego.
- **Jugadores personas, más adelante (2026-09-25).** Pelearán contra NPC y
  contra otros jugadores con las mismas reglas. Por eso toda decisión de un
  presidente NPC (mejorar una ciudad, mandar defensas, atacar, negociar) debe
  ser un comando de `Simulacion:ejecutar`: el jugador usará la misma vía.

- **Exploradores e informes (2026-09-25).** La escasez de una nación no sale en
  las noticias: nadie la conoce salvo ella. Las naciones mandarán exploradores
  a las ciudades rivales; al volver traen un informe (reservas, arsenal,
  defensas) y el presidente NPC decide con él si atacar o no. Hasta entonces el
  panel de la ciudad muestra las reservas solo para quien mira el mundo.

Discrepancias entre el código y la documentación existente (para corregir en
`ARQUITECTURA.md` o en el código, lo que decida el dueño):

- `ARQUITECTURA.md` nombra los comandos `enviarEjercito`, `ataqueAereo` y
  `firmarArmisticio`; los reales son `enviarGrupo`, `salva`, `incursion`,
  `altoElFuego` y `firmarPaz` (`simulacion.lua:519`).
- "Salvas de hasta un centenar de misiles": el máximo medido es 59–90.
- "Cada golpe a una ciudad es un crimen de guerra": solo si pasa algún misil
  (5 crímenes de 31 golpes en la semilla 4242).
- El comentario de `Simulacion:defensas` dice 7 000 px; `alcanceDefensa` vale 14 000.

## Cómo se midió

Los arneses están fuera del repo, en la carpeta temporal de la sesión:
`sim3.lua` (original) y `sim4.lua`/`sim5.lua` (ampliados: envuelven métodos de
`Simulacion` para contar, no cambian reglas). Se corren desde
`NationsRTS` con `luajit <ruta>/sim4.lua <semilla> <días>`. Si se
borran, basta con registrar las 16 zonas con `Mundo:datosZona` +
`Simulacion:registrarZona` y llamar `avanzarDia` en bucle.

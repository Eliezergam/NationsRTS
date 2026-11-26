# Plan de traspaso de Nations RTS a Unreal Engine 5

Cómo pasa Nations RTS de LÖVE con 3DreamEngine a Unreal Engine 5.8 con
MassEntity y C++, por etapas. Escrito el 2026-10-03 a partir de las dos rondas
de la prueba en `~/games/NationsUE5Prueba` y de `VISION.md`, `decisiones.md`,
`asentamientos.md`, `historia.md`, `ARQUITECTURA.md` y `MAPA-DEL-CODIGO.md`.

- **[Decisión del dueño]** ya está decidido (fecha en `decisiones.md`).
- **[Propuesta]** es del estudio y espera el visto bueno del dueño.
- **[Pendiente]** no está decidido. Las preguntas de la sección 8 ya están
  respondidas.

Lo decidido hasta hoy **[Decisión del dueño, 2026-10-03]**: Nations RTS se
hace en Unreal Engine 5.8 con MassEntity y C++; los modelos, el relieve, el
diseño, la historia y los asentamientos se reaprovechan; el código Lua se
reescribe. El plan está aprobado y, después de la etapa 0, lo primero que
se rehace es la batalla 3D tal como funciona en LÖVE (sección 3). Las
respuestas a la sección 8 están en `decisiones.md` («Plan de traspaso a UE5
aprobado»).

---

## 1. Proyecto definitivo

**[Decisión del dueño, 2026-10-03]**: repositorio propio con LFS, y los
documentos se mudan a él (`docs/`). Los detalles de la tabla son
**[Propuesta]**.

| Qué | Propuesta |
|---|---|
| Carpeta | `~/games/NationsRTS-UE` |
| Proyecto | `NationsRTS.uproject` |
| Motor | El UE 5.8.2 compilado de fuente en `~/games/UnrealEngine` (el mismo de la prueba y de OfficeTycoon) |
| Repositorio | Git propio, rama `main`, con Git LFS para `*.uasset`, `*.umap`, `*.glb`, `*.png`, `*.jpg`, `*.bin` y `*.r16` |
| Idioma | Todo en español: código, comentarios, commits y textos (`VISION.md`, sección 8) |

### Estructura

```
NationsRTS-UE/
  NationsRTS.uproject
  Config/                   ajustes del proyecto (render fijado en la etapa 0)
  Source/
    NationsSim/             simulación de campaña: C++ puro, sin UObject en los datos,
                            determinista, sin render (se puede correr en un servidor)
    NationsRTS/             juego: mapa de campaña, batalla, cámara, interfaz
    NationsRTSEditor/       utilidades de editor llamables desde Python
                            (Landscape, horneados, importación)
  Content/                  assets binarios, todos generados por script cuando se puede
  Datos/                    fuentes de texto: JSON de asentamientos, facciones, armamento,
                            contratos e historia; se importan a DataTables por script
  Herramientas/             scripts estándar de los agentes (sección 4.1)
  Pruebas/                  pruebas de automatización y arneses de captura
  docs/                     MAPA-DEL-CODIGO (generado), GUIA-UE5, trampas
```

`NationsSim` va aparte para que la simulación siga siendo lo que dice
`ARQUITECTURA.md`: determinista, «todo cambio es un comando», guardable como
datos y capaz de correr sin pantalla. El módulo del juego la lee y le manda
comandos; no la cambia por dentro.

### Qué se trae de la prueba (`~/games/NationsUE5Prueba`)

| Se trae | Cómo |
|---|---|
| Utilidad C++ para crear un Landscape desde un `.r16` (`NPHerramientasEditor::CrearLandscape`) | Se mueve a `NationsRTSEditor` y se amplía a World Partition |
| Cadena de importación del soldado: glb → Interchange (mallas combinadas) → malla estática → horneado de animación por hueso (AnimToTexture) → instancias de material | `crear_assets.py` y `crear_lods.py` pasan a `Herramientas/importar_unidad.py`, para cualquier modelo |
| Reparto de LOD por soldado en CPU con 4 ISM por bando (distancias de `lod.lua`) | Se reescribe limpio como parte de la representación de la batalla |
| Procesador Mass y fragmentos (idea y API de 5.8 ya comprobadas) | Como referencia; la IA de la batalla es nueva |
| `medir.sh` y `medir_r2.sh` (sin ventana, 1920×1080, espera a `love`, limpieza de `GameUserSettings.ini`) | Pasan a `Herramientas/medir.sh` |
| Las trampas encontradas | `docs/trampas-ue5.md` (sección 4.6) |

| No se trae | Por qué |
|---|---|
| El nivel `Valle` y su textura procedural | Era un recorte de 20 km para medir |
| El material del maniquí de Epic usado en los soldados | Es provisional; el soldado necesita su material propio (sección 4.5) |
| La variante Nanite del soldado | Nanite rompe la animación por textura (sección 4.6) |
| `NPBatalla` tal cual | Junta en una clase simulación de prueba, dibujo, medida y cámara; se parte en piezas |
| Los diagnósticos (`-cubos`, `-lodforzado`) | Eran para la prueba |

## 2. Qué se reaprovecha y qué se reescribe

**[Decisión del dueño, 2026-10-03]** en lo general; el detalle de la tabla
es **[Propuesta]**.

| Se reaprovecha tal cual | Origen | Cómo entra en UE5 |
|---|---|---|
| Modelos 3D y sus LOD (soldado, camiones, lanzacohetes, orugas) | `assets/modelos3d/*.glb`, `lod*.lua` | Interchange por script; las distancias de `lod.lua` pasan a JSON |
| Impostores | `*_impostor*.png` | Para el último nivel de lejos (no se usaron en la prueba) |
| Relieve DEM y su generador | `../tools/mapa/caucaso.py`, `assets/mapa/` (`caucaso_alturas_fino.bin`, 9732 × 6000, ~93 m) | Se amplía para escribir `.r16` por regiones de World Partition |
| Texturas PBR | `assets/texturas/` | Importación por script a Texture2D |
| Asentamientos | `campana/asentamientos.lua` (85 entradas) | Se convierte a `Datos/asentamientos.json` → DataTable; el `.lua` sigue siendo la fuente hasta que Lucía lo pase a JSON |
| Diseño | `VISION.md` y `diseno/` | Sin cambios; Lucía sigue igual |
| Historia | `diseno/historia.md` | Datos de misiones en `Datos/` cuando lleguen las etapas 9–12 |
| Estilo de interfaz y kit gráfico | `diseno/interfaz-militar.md`, `assets/ui/` | Brushes de 9-slice en UMG (Box Brush) |
| Clips del soldado | `soldado_clips.lua` | Nombres y orden de los clips del horneado |
| Fuentes | `assets/fuentes/` (Barlow) | Fuentes de UMG |

| Se reescribe en C++ | Hoy en Lua | Por qué no se porta |
|---|---|---|
| Simulación | `mundo/simulacion.lua` y `mundo/simulacion/*.lua` (~16 000 líneas en `mundo/`) | Era el modelo de naciones procedurales, ya superado (`VISION.md`, sección 7). Lo que sigue valiendo es la arquitectura: determinismo, comandos y guardado como datos |
| Mapa de campaña | `campana/*.lua` | Pasa a Landscape con World Partition |
| Batalla 3D | `batalla/` (~18 000 líneas sobre 3DreamEngine) | Pasa a Mass + ISM + Niagara; las ideas de pasillos, despliegue y órdenes se leen como referencia |
| Interfaz | `interfaz/` (~10 800 líneas) | Pasa a UMG; el diseño visual se conserva |
| Cámaras | `campana/camara.lua`, `batalla/camara.lua` | Pasan a Pawn + SpringArm + Enhanced Input |
| Navegación | `runtime/` (A*, flow field, formaciones) | En la batalla, Mass (avoidance, formaciones); en la campaña, una rejilla sobre el relieve en `NationsSim`. Los algoritmos de `runtime/` sirven de referencia |

## 3. Orden de etapas en UE5

**[Decisión del dueño, 2026-10-03]** Tras la etapa 0, lo primero que se
rehace en Unreal es **la batalla 3D tal como funciona hoy en LÖVE**: tropas,
órdenes, tanques, lanzacohetes, misiles, daños, despliegue, cámara e interfaz
de batalla, con la luz, la física y las partículas de UE. Después llega el mapa
de campaña. La referencia de comportamiento es el código de LÖVE en la etiqueta
`love-final-2026-10-03`; las rutas de abajo son de esa etiqueta, relativas a
`NationsRTS/`. Lo que ya no vale no se pasa (sección 3.3).

El orden de los pasos dentro de la batalla es **[Decisión del dueño, 2026-10-03]**. Cada paso es
jugable y se le enseña al dueño antes del siguiente.

Tamaños, a ojo: **pequeño** son 1–3 pasos de trabajo (1–2 días de agentes);
**medio**, 4–8 (unos 3–6 días); **grande**, más de 8 (una o dos semanas). Son
estimaciones sin medir; el paso B1 sirve para calibrarlas.

### Etapa 0. Esqueleto del proyecto
- **Se ve:** el proyecto abre y compila; `Herramientas/compilar.sh`,
  `capturar.sh`, `medir.sh` y `pruebas.sh` funcionan; una prueba de
  automatización vacía en verde y una captura de un nivel en blanco con la luz
  decidida.
- **Sistemas de UE:** módulos C++, Automation Test Framework, Python del
  editor y DDC.
- **Ajustes de render** fijados aquí (cambiarlos después recompila shaders,
  unos 20 min): sin Lumen, FXAA o TAA, VSM con sombras solo de cerca, SM6 en
  Vulkan. Son los de la ronda 2.
- **Tamaño:** pequeño.

### 3.1 La batalla 3D, primero

**Cómo se entra mientras no hay mapa de campaña [Decisión del dueño, 2026-10-03].** Hoy la batalla
se abre desde un choque del mapa 2D (`batalla/escena.lua`,
`Escena.combateDeGrupo`) y lee la simulación de naciones. En UE5, hasta la
etapa de campaña que la conecta, se abre desde un archivo:

- `Datos/batallas/<nombre>.json` describe el sitio (longitud y latitud en el
  Cáucaso), los dos bandos, sus unidades, su munición y la hora;
- se lanza con `-batalla=<nombre>`, como el `--batalla-vivo` de LÖVE;
- al acabar se escribe el resultado unidad por unidad en JSON, con el formato
  de `batalla/DANO-REAL.md` §5.6.

Ese archivo de resultado es lo que leerá `NationsSim` cuando exista.

**Escala.** La batalla va a escala real: 1 px de LÖVE son 10 cm; en UE se
trabaja en cm. El área mide 3 × 3 km (`Suelo.lado = 30000`) con un límite
circular de 1,2 km de radio (`limite.lua`). Unas 40 unidades por bando a la vez
(`Tropas.maxPorBando`), con oleadas desde la reserva.

#### Paso B1. Terreno de batalla y soldados que se mueven con órdenes
Es el riesgo técnico más grande del plan y va aquí, al principio, para medirlo
antes de construir encima (sección 6).

- **Referencia en LÖVE:**
  - suelo: `suelo.lua`, `rejilla.lua`, `color_terreno.lua`, `cauces.lua`,
    `agua.lua`, `limite.lua`, `colocacion.lua`, `vegetacion.lua` y
    `batalla/ESTILO-TERRENO.md`;
  - selección y órdenes de mover: `control.lua`, `ordenes.lua` (ruta por
    terreno transitable y huecos de la formación) y `marcas_holo.lua` (anillo
    de la unidad elegida y cinta de la ruta);
  - cámara: `camara.lua` y `controlador_camara.lua`;
  - estado de animación de los soldados: `soldados.lua`.
- **Qué cambia:** el sitio deja de salir de la semilla del mundo procedural y
  sale del relieve real: un recorte de 3 km del DEM fino (~93 m por muestra)
  con detalle añadido por ruido, como hoy hace `rejilla.lua` sobre el mapa.
- **Primero se mide el terreno en tiempo de juego** (en el editor el Landscape
  no se puede crear mientras se juega; sección 6). Tres opciones, en este
  orden:
  1. una malla propia en C++ por trozos con LOD, con `UDynamicMeshComponent`
     (Geometry Script) o `UProceduralMeshComponent`;
  2. la altura para mover las unidades, leída de una rejilla en memoria, como
     `FNPTerreno` en la prueba, sin colisión física compleja del terreno;
  3. si (1) no llega a 60 FPS o tarda más de 10 s en generarse: un catálogo de
     sitios horneados en el editor como niveles con Landscape.

  Se elige con números: tiempo de generación, FPS y memoria.
- **Sistemas de UE:**
  - la malla de terreno de la opción elegida y vegetación con ISM o HISM
    según las reglas de `colocacion.lua`;
  - un Pawn de cámara RTS con Enhanced Input;
  - soldados como entidades de Mass con animación por textura, LOD por
    soldado y una IA de movimiento en formación (MassMovement y avoidance);
  - un camino por el terreno con A* sobre la rejilla (lo que hace
    `ordenes.lua`);
  - el anillo y la cinta de la orden como decals o mallas con material.
- **Se ve:** el sitio real del Cáucaso en 3D, con ríos y vegetación; dos
  bandos de escuadras; se eligen con clic, Mayús+clic o cuadro y van adonde se
  hace clic derecho, en formación y por terreno transitable, con su cinta de
  ruta. Hay capturas y medidas de FPS y del tiempo de generación.
- **Tamaño:** grande; se enseña en dos mitades, primero el terreno medido y
  luego las órdenes.

#### Paso B2. Combate de infantería
- **Referencia en LÖVE:**
  - `tropas.lua` (parte de la infantería: escuadras, ráfagas, munición por
    disparo, bajas);
  - `dano/datos.lua` (fusil y soldado);
  - `dano/trayectoria.lua` y `dano/proyectiles.lua` (§3.2, ráfagas como haz
    equivalente);
  - `impactos.lua` (contra el terreno y los árboles);
  - `soldados.lua` (clips disparar y morir con fundido);
  - `soldado_clips_boca.lua` (la boca del fusil);
  - `escena.lua` (`vigilarFin`, `dibujarFin`).
- **Sistemas de UE:**
  - procesadores de Mass para objetivo, fuego, daño y bajas, deterministas con
    RNG propio (`DANO-REAL.md` §8.1);
  - trazas contra la rejilla del terreno y las cajas de los árboles;
  - Niagara para fogonazos e impactos de fusil.
- **Se ve:** las escuadras se buscan, se paran a disparar, caen soldados con su
  clip de muerte y gastan munición. Sin munición dejan de disparar. La batalla
  termina cuando un bando no puede seguir y sale el resultado en JSON.
- **Tamaño:** medio.

#### Paso B3. Tanques y lanzacohetes
- **Referencia en LÖVE:**
  - `tropas.lua` (formación de vehículos; avance despacio por el terreno
    esquivando agua, edificios y árboles; parar a disparar a 1–2 km; los
    lanzacohetes en la retaguardia, que no disparan con un tanque a menos de
    500 m; oleadas desde la reserva);
  - `orugas.lua` y `dream/oruga.lua` (oruga y ruedas);
  - `articulacion_camion.lua` y `lanzamisiles.lua` (suspensión y rampa);
  - `derribo.lua` (árboles tumbados);
  - `dano/blindaje.lua` y `dano/cuerpos.lua` (zonas, penetración y averías);
  - `dano/proyectiles.lua` (§3.1, cañonazos con trazador);
  - `fisica.lua` (cómo se apoyan en el relieve).
- **Sistemas de UE:**
  - vehículos como entidades de Mass con movimiento cinemático apoyado en la
    rejilla (no Chaos Vehicles: LÖVE tampoco simula la conducción, y así sigue
    siendo determinista);
  - representación con ISM por LOD (los LOD de `assets/modelos3d/lod_camiones.lua` y
    `lod_orugas.lua`) y articulaciones (torreta, cañón, rampa, ruedas) como
    instancias separadas o por animación por textura;
  - Chaos solo para lo que cae: árboles derribados.
- **Se ve:** tanques T-72B, M1A1 y compañía avanzando en formación y
  disparando cañonazos con trazador que tardan lo que tardan en llegar;
  lanzacohetes BM-21 y HIMARS esperando atrás; vehículos averiados por zona
  que se retiran y dejan entrar a la reserva; árboles tumbados al pasar.
- **Tamaño:** grande.

#### Paso B4. Misiles, explosiones y efectos
- **Referencia en LÖVE:**
  - `dano/proyectiles.lua` y `dano/trayectoria.lua` (§3.3, tiro indirecto);
  - `dano/explosiones.lua` (radio letal y de metralla);
  - `efectos.lua`, `estelas.lua` y `dream/efectos/` (estelas, nube de
    lanzamiento, fogonazos, impactos, marcas de quemado);
  - `destruccion.lua` (restos del lanzamisiles con caída física);
  - `dream/humo_escape.lua`;
  - `dream/sonido.lua` (audio posicional).
- **Sistemas de UE:**
  - Niagara para estelas (cinta), humo, fuego y chispas;
  - decals para las marcas de quemado;
  - Chaos para los restos (Geometry Collection o piezas sueltas con física);
  - MetaSounds o Sound Cues con atenuación 3D.
- **Se ve:** los lanzacohetes disparan salvas con estela continua que caen con
  dispersión, explosiones que matan y averían según su radio, restos que caen
  con física, marcas en el suelo y sonido en su sitio. Con la misma tabla de
  medidas de la prueba (2000 soldados y efectos).
- **Tamaño:** medio–grande.

#### Paso B5. Interfaz de batalla
- **Referencia en LÖVE:**
  - `escena.lua` (`dibujarRotulo`, `dibujarAvisos`, `dibujarFin`, panel de
    bandos con munición y bajas);
  - `control.lua` (selección por tipo con T, L e I; doble clic; mantener
    posición con H);
  - `anillo_holo.lua` y `cinta_holo.lua` (aspecto holográfico);
  - `interfaz/acero.lua`, `interfaz/vida.lua` y `interfaz/tema.lua` (estilo y
    movimiento sutil de los botones);
  - `prueba_raton.lua` (cómo se prueban los controles por sus callbacks
    reales).
- **Sistemas de UE:**
  - UMG con CommonUI y el estilo militar (`interfaz-militar.md`, brushes de
    `assets/ui/`);
  - materiales holográficos para los anillos y las cintas;
  - pruebas de automatización que inyectan Enhanced Input (lo que hace hoy
    `prueba_raton.lua`).
- **Se ve:** el rótulo de los dos bandos con fuerzas, munición y bajas, los
  avisos, la pantalla de fin, la selección completa con atajos y las marcas
  holográficas.
- **Tamaño:** medio. La primera pantalla de UMG fija el estilo de todas las
  demás.

#### Paso B6. Despliegue
- **Referencia en LÖVE:**
  - `despliegue.lua` y `despliegue_vista.lua` (2:00 de preparación con el
    combate en pausa, zonas de despliegue con el color del bando, botón
    «Listo»);
  - `pasillos.lua` (franjas de avance transitables entre los dos bandos);
  - `escena.lua` (`encuadrarDespliegue`, `encuadrarBandos`);
  - `diseno/batalla-despliegue-y-movimiento.md`.
- **Sistemas de UE:** decals o mallas de zona sobre el terreno, UMG para el
  contador y el botón, y los pasillos calculados en C++ con A* sobre la
  rejilla.
- **Se ve:** la batalla empieza en preparación: el jugador coloca sus
  unidades dentro de su zona, el contador baja y, con «Listo» o a los 2:00,
  empieza el combate.
- **Tamaño:** pequeño–medio.

#### Paso B7. Cámara a pie, luz por hora y cierre
- **Referencia en LÖVE:**
  - `caminante.lua` (primera persona del observador: caminar, correr, saltar,
    chocar con troncos, rocas y vehículos);
  - `dream/luz.lua` (sol y luna según la hora del mundo);
  - `dream/atmosfera.lua` e `ibl.lua` (lo que en UE es SkyAtmosphere y
    SkyLight);
  - `dream/PLAN-RENDER-UE.md` (el aspecto que se buscaba).
- **Sistemas de UE:** un Character en primera persona (el observador; el
  soldado del jugador llega en la etapa C6), DirectionalLight con la hora
  del archivo de batalla, SkyAtmosphere y SkyLight, y la tabla de medidas
  final de la batalla.
- **Se ve:** la batalla completa de LÖVE en UE5, recorrible a pie, de día o
  al atardecer; medidas y capturas en las mismas cámaras que LÖVE para
  comparar.
- **Tamaño:** pequeño–medio.

### 3.2 Después, el mapa de campaña y lo demás

Las etapas de `VISION.md`, sección 6, en su orden **[Decisión del dueño,
2026-10-02]**. La 5 (encuentro y batalla) ahora solo conecta la batalla ya
hecha.

#### C1 (VISION 1). Mapa de campaña visible
- **Se ve:** el Cáucaso entero en 3D, con la costa, el Mar Negro y el Caspio,
  la luz de la batalla, la cámara tipo Bannerlord (arrastrar, rueda para el
  zoom, inclinar y girar) y las 18 ciudades y 67 pueblos como iconos con su
  nombre.
- **Sistemas de UE:**
  - Landscape con World Partition, importado por script desde el DEM fino en
    regiones;
  - la maqueta a escala 1:10, unos 90 × 56 km con las montañas ×3
    **[Decisión del dueño, 2026-10-03]**;
  - un material por altura y pendiente y un plano de agua;
  - un Pawn de cámara con Enhanced Input;
  - iconos con ISM y nombres en UMG con ocultado por zoom;
  - `asentamientos.json` en una DataTable.
- **Tamaño:** medio. Empieza con un tercio del mapa y se mide antes de
  importarlo entero.

#### C2 (VISION 2). Vista de radar
- **Se ve:** una tecla cambia el mismo mapa a vista de radar.
- **Sistemas de UE:** Material Parameter Collection, un material de
  postproceso y Custom Depth/Stencil.
- **Tamaño:** pequeño.

#### C3 (VISION 3). La columna del jugador en el mapa
- **Se ve:** la ficha del jugador sale de Dioskar, va adonde se hace clic por
  el relieve y gasta combustible por kilómetro, con aceleradores de tiempo.
- **Sistemas de UE:** `NationsSim` (estado, comandos, tic fijo, guardar y
  cargar en JSON, preparada para servidor desde el principio **[Decisión de
  el dueño, 2026-10-03]**) y A* con coste por pendiente.
- **Tamaño:** medio.

#### C4 (VISION 4). Entrar a una ciudad (menú)
- **Se ve:** el menú de estilo militar para contratar, reclutar y comprar
  munición y combustible.
- **Sistemas de UE:** UMG con el estilo fijado en B5 y comandos de
  `NationsSim`.
- **Tamaño:** pequeño–medio.

#### C5 (VISION 5). Encuentro y batalla
- **Se ve:** al chocar con una columna enemiga se abre la batalla de B1–B7
  en el sitio del mapa, y el resultado vuelve a `NationsSim`.
- **Sistemas de UE:** el archivo de batalla se genera desde `NationsSim` en
  lugar de escribirse a mano; carga del nivel de batalla.
- **Tamaño:** pequeño.

#### C6 a C13 (VISION 6 a 13)
Como en `VISION.md`, sección 6:

- **C6. Soldado del jugador en la batalla.** ACharacter con malla esquelética
  y Animation Blueprint mínimo, cámara al hombro y primera persona, órdenes
  F1–F3 como señales de Mass. Medio–grande.
- **C7. Después de la batalla.** Pequeño (el resultado ya existe desde B2).
- **C8. Pueblos que producen y convoyes.** Medio.
- **C9. Notables y contratos.** Medio, con los primeros hitos de
  `historia.md`.
- **C10. Primeras facciones con generales.** Grande (IA en `NationsSim`, con
  las mismas acciones que el jugador).
- **C11. Compañeros.** Pequeño–medio.
- **C12. El resto de facciones.** Grande.
- **C13. Más adelante:** hub a pie, asedios urbanos, supresión y blindaje
  por sectores, TEL y misiles, mercado negro, árbol de habilidades. Se planean
  cuando lleguen.

### 3.3 Lo que queda en LÖVE y ya no vale (no se pasa)

**[Decisión del dueño, 2026-10-03]** lo general («lo que ya no vale no se
pasa»); la lista es **[Propuesta]** según `VISION.md`, sección 7.

| No se pasa | Dónde está | Por qué |
|---|---|---|
| El mundo procedural infinito, la semilla y sus biomas | `mundo/terreno.lua`, `mundo/ruido.lua` (como fuente del sitio), `mundo/plantas.lua`, `mundo/mundo.lua` | El sitio de la batalla sale del DEM real |
| El mapa 2D isométrico y su proyección | `mundo/iso.lua`, `runtime/projection.lua`, `main.lua` | El mapa es 3D |
| Las naciones procedurales, presidentes, territorio por celdas, instalaciones, recolección y la economía cerrada | `mundo/simulacion.lua` y `mundo/simulacion/*` (`diplomacia`, `territorio`, `produccion`, `recoleccion*`, `lideres`, `nombres`, `exploracion`, `taller`), `mundo/ciudades.lua`, `mundo/instalaciones.lua` | Superado por el GDD |
| La entrada a la batalla desde el mapa 2D | `escena.lua` (`combateDeGrupo`, `combateProvocado`, `buscarCombate`) y `mundo/choques.lua` | Se sustituye por el archivo de batalla y, luego, por C5 |
| El mundo que sigue al 25 % durante la batalla | `escena.lua` | Lo decide `NationsSim` cuando exista |
| Batallas contra instalaciones o ciudades con edificio procedural | `escena.lua` (objetivo «ciudad o instalación»), `dano/cuerpos.lua` (caja del edificio) | Los asedios urbanos son la etapa C13 |
| Todo el motor de render propio sobre 3DreamEngine | `batalla/dream/*` (atmósfera, IBL, AA temporal, oclusión, lotes por FFI, huesos en GPU, sombreadores, calidad), `matriz.lua`, `malla.lua`, `sombreado.lua`, `dream/conversor.lua` | Lo hace UE: SkyAtmosphere, SkyLight, VSM, ISM, Niagara y escalabilidad |
| Las rutas dibujadas del editor (NV) | `runtime/` (agent, graph, flow_field, group…) | Solo como lectura de algoritmos; en la batalla manda Mass |
| La interfaz del mapa viejo | `interfaz/` salvo `acero`, `vida`, `tema` y `paleta`, que dan el estilo | Barra de nación, radial, plantar bandera, perfil de nación, fábrica: modelo superado |
| Los arneses de prueba en LÖVE | `batalla/pruebas_*` | Se convierten en pruebas de automatización y escenas de medida, no se traducen |

Los módulos de `batalla/` que no salen en la tabla son referencia de
comportamiento: se leen para que la batalla en UE haga lo mismo, no se
traducen línea a línea.

## 4. Forma de trabajo de los agentes en UE5

**[Propuesta]** salvo lo marcado.

### 4.1 Scripts estándar (`Herramientas/`)

Todo se hace sin ventana; ninguno abre nada en la pantalla del dueño.

| Script | Qué hace |
|---|---|
| `compilar.sh` | `Build.sh NationsRTSEditor Linux Development`. Compila en 8–25 s si solo cambian los módulos del juego |
| `editor_py.sh <script.py>` | Lanza `UnrealEditor-Cmd -run=pythonscript -RenderOffscreen -AllowCommandletRendering -unattended`. Se niega si el dueño tiene el editor abierto con el proyecto |
| `importar_unidad.py <glb> [lods]` | glb → Interchange (mallas combinadas) → malla estática → horneado de animación por LOD → materiales por bando |
| `importar_relieve.py` | Del DEM a las regiones `.r16` y al Landscape con World Partition |
| `importar_datos.py` | JSON de `Datos/` → DataTables |
| `capturar.sh <nivel> <cámara> <salida.png>` | Juego sin ventana a 1920×1080 y una captura |
| `medir.sh <escena> <n>` | Captura + FPS y ms de Game, Draw y GPU; espera a que no haya `love` ni otra medición en marcha; borra `GameUserSettings.ini` antes de cada ejecución |
| `pruebas.sh [filtro]` | `UnrealEditor-Cmd -ExecCmds="Automation RunTests NationsRTS"` con `-nullrhi` para las pruebas de simulación |
| `perfil_gpu.sh` | `ProfileGPU` en un cuadro y resumen de los pases más caros |
| `generar_mapa_codigo.py` | `docs/MAPA-DEL-CODIGO.md` desde los comentarios de las cabeceras de C++, como hoy con Lua |

### 4.2 Convenciones
- **C++ casi siempre.** Blueprints solo donde UE los pide: el Animation
  Blueprint del soldado del jugador y, si acaso, widgets de UMG con su
  lógica en C++.
- **Datos en texto:** JSON en `Datos/` como fuente, importado a DataTables
  por script. Así los diffs se leen y los agentes no editan binarios.
- **Assets binarios generados por script** desde fuentes de texto (glb,
  JSON, DEM) siempre que se pueda: se pueden rehacer y nadie los toca a mano
  sin avisar.
- **Estilo de código.** **[Decisión del dueño, 2026-10-03]**: convenciones
  de UE con nombres en español.
  - La regla vigente es «camelCase, nada compactado, una clase por
    responsabilidad» (`VISION.md`, sección 8).
  - UE impone sus prefijos (`U`, `A`, `F`, `E`) y usa PascalCase en tipos y
    funciones, con `b` en los booleanos.
  - Propuesta: nombres en español con las convenciones de UE (`ANPBatalla`,
    `SincronizarInstancias`, `bConLods`), nada compactado, una clase por
    responsabilidad y `.clang-format` en el repositorio.
- **Una cabecera por archivo:** qué es y para qué sirve, para el mapa del
  código.

### 4.3 Cómo se verifica
- **Simulación:** pruebas de automatización sin render (determinismo,
  guardar y cargar, fórmulas de `asentamientos.md`) que Elena corre en cada
  cambio.
- **Lo que se ve:** capturas sin ventana que Bruno mira antes de enseñarlas;
  con números (píxel, reparto de LOD, FPS) cuando aplique. «Compila» no es una
  verificación.
- **Rendimiento:** `medir.sh` con escenas fijas y la misma tabla que en la
  prueba (0, 500, 1000 y 2000 soldados), al cerrar cada etapa que toque la
  batalla.
- **Controles:** pruebas de automatización que inyectan acciones de Enhanced
  Input, no simulación de ratón en la pantalla. El dueño prueba él mismo en la
  PC.

### 4.4 DDC y shaders
- La caché de datos derivados ya es compartida en esta máquina (Zen en
  `~/.config/Epic/UnrealEngine/Common/Zen`). La primera compilación de shaders
  globales con unos ajustes de render nuevos tarda unos 19 min; después sale
  de la caché.
- Los ajustes de render se fijan en la etapa 0 y se cambian a propósito, no de
  pasada: cada cambio vuelve a compilar shaders.
- Solo una medición de GPU a la vez en la máquina: `medir.sh` espera a otras
  mediciones y a `love`.

### 4.5 Lo que haríal dueño a mano, una vez
- Abrir el proyecto en el editor la primera vez y aceptar lo que pida (plugins,
  ajustes).
- Dar el visto bueno al **aspecto visual** de referencia: sol, cielo, exposición
  y material del terreno, sobre capturas de los agentes o tocándolo en el
  editor.
- Los **materiales base** (soldado, vehículos, terreno), si quiere
  retocarlos a mano. Los agentes los pueden crear por script, pero el ajuste
  fino del grafo de nodos es más rápido con ventana.
- Probar los controles (cámara del mapa, soldado del jugador) en la PC.

### 4.6 Trampas encontradas en la prueba
1. **Mass en 5.8:** `FMassEntityHandle` está en `Mass/EntityHandle.h` y
   `FMassFragment` en `Mass/EntityElementTypes.h` (módulo `MassCore`), no en
   los sitios de 5.4–5.5.
2. **Interchange separa un glb con varias mallas** en varias mallas
   esqueléticas. Hay que pasar un `InterchangeGenericAssetsPipeline` con
   `combine_skeletal_meshes_behavior = BY_SKELETON` mediante
   `InterchangePipelineStackOverride`.
3. **Sin `-AllowCommandletRendering`,** `ConvertSkeletalMeshToStaticMesh`
   devuelve null en un commandlet, y la siguiente llamada de AnimToTexture hace
   un `check()` y tumba el proceso.
4. **Nanite rompe la animación por textura:** pierde la precisión del canal UV
   que lee los huesos. Los soldados con animación por textura van sin Nanite y
   con LOD.
5. **Las sombras en cascada (CSM) no dibujaban nada** en esa escena, ni
   soldados ni cubos del motor; con VSM sí. Causa sin encontrar. Se usa VSM con
   sombras solo en los LOD cercanos (1,1 ms con 2000 soldados).
6. **Las órdenes `sg.*` se guardan** en
   `Saved/Config/LinuxEditor/GameUserSettings.ini` y contaminan las ejecuciones
   siguientes: se borra antes de cada medición.
7. **El ISM elige el LOD por componente, no por instancia:** el LOD de cada
   soldado se calcula en CPU y se reparte entre un ISM por LOD (como
   MassRepresentation).
8. **La niebla exponencial** se mide en Z del mundo: con un relieve por debajo
   de 0 lo tapa todo.
9. **En commandlets** no existen los subsistemas de editor
   (`StaticMeshEditorSubsystem`) y el registro de assets no ve el contenido de
   los plugins. Se resuelve con utilidades C++ propias y `load_asset`.
10. **La primera compilación del proyecto re-enlazó un módulo del motor**
    (`NetCore`). Es inocuo, pero toca `~/games/UnrealEngine`, compartido con
    OfficeTycoon.

## 5. Roles del estudio en UE5

**[Propuesta]** Cambios para las fichas de `~/forja-studios/agentes/`.

| Trabajador | En LÖVE | En UE5 | Para su ficha |
|---|---|---|---|
| Andrés | `mundo/simulacion.lua` | `Source/NationsSim/` (campaña, comandos, guardado) y la lógica de Mass de la batalla (fragmentos, procesadores, señales) | Determinismo en C++: tic fijo, sin `FMath::Rand` (RNG con semilla propia), sin iterar `TMap` sin ordenar, pruebas de Automation sin render; las trampas 1 y 7 |
| Valeria | Terreno, mapa, interfaz, batalla 3D | Landscape y World Partition, materiales, cámaras, representación de la batalla (ISM, LOD, animación por textura), Niagara junto con Camila, UMG y rendimiento | `medir.sh`, `perfil_gpu.sh`, ajustes de render fijados; las trampas 4–8 |
| Diego | Editor `src/` y `runtime/` | `Source/NationsRTSEditor/` y `Herramientas/`: importadores, utilidades C++ para Python, generadores de mapa del código, scripts estándar | Python del editor en commandlets; las trampas 2, 3 y 9 |
| Camila | Blender → glb, sprites, texturas, shaders | Blender → glb → `importar_unidad.py`: LOD, impostores, PBR, materiales base por script, efectos de Niagara | Lo que pide el horneado: mismo esqueleto en LOD0–2, clips en el orden de `soldado_clips.lua`, escala en cm |
| Tomás | Servidor y juego en línea | El modo en línea va después **[Decisión del dueño, 2026-10-03]**, pero `NationsSim` se prepara para servidor desde el principio | Revisar que `NationsSim` siga separable del render y de la entrada |
| Elena | Lint, pruebas, capturas, revisión | `pruebas.sh`, capturas y medidas, revisión de diffs de C++ (también lo de Codex y Mateo); `clang-tidy` si se adopta | Comprobar que nadie editó un binario sin su script y que la medición de GPU fue en solitario |
| Lucía | Diseño | Sin cambios | Pasar `asentamientos.lua` y lo que salga nuevo a JSON en `Datos/` |
| Mateo (OpenCode) | Programador externo, sin commits | Igual que hoy: C++ y scripts delimitados en el mismo árbol, sin commits; Bruno revisa y guarda | Sin binarios de `Content/` |

### Codex como programador **[Decisión del dueño, 2026-10-03]**

Codex (`codex`, codex-cli 0.160.0, en `~/.local/bin`) sirve para tareas de
C++ **bien delimitadas que se pueden hacer en paralelo** sin pisar a nadie:

- una clase o función nueva con su prueba de Automation (por ejemplo, las
  fórmulas de precios o de producción de `asentamientos.md` en `NationsSim`);
- conversores de datos (Lua o JSON → DataTable);
- pruebas que faltan sobre código ya existente;
- refactorizaciones mecánicas de un solo módulo.

No le tocarían:
- `Content/` (binarios), `Config/` (ajustes de render) ni la arquitectura;
- los encargos que piden mirar capturas o decidir el aspecto visual.

**Reglas para que no haga commits por su cuenta en `main`**, como pasaba en
el repositorio de LÖVE:

1. **Rama y árbol propios:** se lanza con
   `codex exec --worktree -s workspace-write -o <informe.md> "<encargo>"`.
   Trabaja en un worktree de git aparte, así que lo que haga no entra en `main`.
   Si UBT necesita escribir fuera del proyecto (trampa 10), se añade
   `--add-dir ~/games/UnrealEngine`.
2. **Bloqueo igual que los demás:** antes de lanzarlo, Bruno toma con
   `tools/bloqueo.sh tomar codex <archivos>` los archivos del encargo, para
   que nadie más los toque, y los suelta al integrar. El encargo dice qué
   archivos puede cambiar y nada más.
3. **Encargo cerrado:** el porqué, los archivos, la prueba que tiene que pasar
   y qué entrega, como cualquier encargo de Bruno.
4. **Revisión antes de entrar:** Elena corre `pruebas.sh` y revisa el diff del
   worktree; Bruno lo lee y lo integra en `main` con un commit propio que dice
   «hecho por Codex». Un FALLA de Elena lo devuelve a Codex con la salida
   exacta (`codex exec resume`).
5. **Sin compilar el motor ni tocar `~/games/UnrealEngine`** salvo lo que
   haga UBT al compilar el proyecto.

Con Mateo igual, pero en el mismo árbol y sin commits, como hoy.

## 6. Riesgos y el repositorio LÖVE

### Riesgos **[Propuesta]** para `riesgos.md`

| Riesgo | Imp. | Prob. | Señal de alarma | Qué se hace |
|---|---|---|---|---|
| Terreno de la batalla en tiempo de juego (no hay Landscape en tiempo de ejecución) | 5 | 4 | La malla propia no llega a 60 FPS o tarda mucho en generarse | Se mide lo primero, en el paso B1; alternativa: un catálogo de sitios horneados |
| Mapa entero de 903 × 557 km con World Partition | 4 | 3 | La importación o el streaming pasan de minutos a horas | La etapa C1 empieza con un tercio del mapa y mide antes de importarlo entero |
| Binarios de `Content/` y varios agentes a la vez | 4 | 3 | Un `.uasset` cambiado por dos personas o sin su script | Bloqueos sobre `Content/`, assets generados por script, LFS |
| Compilación de shaders o del motor | 3 | 3 | Cambios de render que cuestan 20 min cada vez; actualizar el motor | Ajustes fijados en la etapa 0; el motor se queda en 5.8.2 durante el traspaso |
| IA de batalla real (la prueba era trivial) | 4 | 3 | Game > 8 ms con 2000 y órdenes de verdad | Medir en cada paso B1–B7; Mass con LOD de simulación |
| Fallo de CSM sin explicar | 2 | 2 | — | Se usa VSM; se vuelve a mirar si cambia la luz |
| OfficeTycoon comparte el motor | 2 | 2 | Un cambio en `~/games/UnrealEngine` rompe su compilación | Nadie toca el motor; si hace falta, una copia aparte |

### El repositorio LÖVE **[Decisión del dueño, 2026-10-03]**
- **Se congela como referencia**, sin borrar nada: una etiqueta
  `love-final-2026-10-03` en el último commit y una nota al principio de
  `NationsRTS/VISION.md` que diga dónde sigue el juego.
- El editor de mapas (`src/`, `runtime/`) y otros proyectos del árbol siguen
  como están: el traspaso solo afecta a Nations RTS.
- Los documentos de diseño se mudan al repositorio nuevo (`docs/`)
  **[Decisión del dueño, 2026-10-03]**. En `NationsRTS/diseno/` queda una
  nota que dice adónde fueron.
- El código de batalla de la etiqueta es la referencia de comportamiento de
  los pasos B1–B7; lo de la sección 3.3 no se pasa.
- Las herramientas de datos (`tools/mapa/caucaso.py`, `tools/blender/`) se
  siguen usando desde aquí, o se copian a `Herramientas/` si las cambia el
  traspaso.

## 7. Primeros pasos **[Propuesta]**

1. Diego: etapa 0 (proyecto, scripts estándar, Automation en verde, ajustes
   de render).
2. Valeria: la primera mitad de B1, el terreno de batalla en tiempo de juego
   desde un recorte de 3 km del DEM, medido (generación, FPS, memoria) y con
   capturas. Decide entre malla propia y catálogo horneado.
3. Andrés: el formato del archivo de batalla y del resultado (`DANO-REAL.md`
   §5.6) y los fragmentos de Mass de B1–B2, leídos de `tropas.lua`,
   `ordenes.lua` y `dano/`.
4. Camila: `importar_unidad.py` con el soldado y un tanque, con sus LOD.
5. Lucía: la interfaz de batalla de LÖVE pasada a una especificación para UMG
   (para B5).
6. Elena: `pruebas.sh` y `medir.sh` en el flujo, y una prueba de aceptación
   por paso B.

Los puntos 3, 4 y 5 no se pisan con la etapa 0 y pueden ir en paralelo. El
punto 2 necesita el esqueleto del 1.

## 8. Preguntas para el dueño (respondidas el 2026-10-03)

1. **Proyecto:** `~/games/NationsRTS-UE`, con git propio y LFS. Respondida:
   sí.
2. **Escala del mapa de campaña:** maqueta 1:10 en horizontal (~90 × 56 km)
   con la exageración vertical ×3. Respondida. La batalla va a escala real.
3. **Estilo de código:** convenciones de UE (PascalCase y prefijos) con
   nombres en español. Respondida.
4. **Modo en línea:** después; la simulación se prepara para servidor desde
   el principio. Respondida.
5. **Documentos de diseño:** se mudan al repositorio nuevo. Respondida.
6. **Codex:** sí, con las reglas de la sección 5. Respondida.

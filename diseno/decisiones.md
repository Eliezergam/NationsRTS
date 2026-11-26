# Registro de decisiones

Decisiones del dueño sobre Nations RTS, la más nueva arriba. Cada entrada
dice qué se decidió, por qué (si consta), qué se descartó, a quién afecta y qué
sustituye. Una decisión cambiada no se borra: se marca «sustituida por
<fecha>». El detalle de cada una está en `../VISION.md` y en los documentos que
se citan.

Empieza el 2026-10-02 con el GDD «Guerra Moderna RTS». Las decisiones de ese
día se apuntaron después, a partir de `VISION.md` y de las notas de Claude; el
orden dentro del día es aproximado. Las decisiones anteriores que siguen
vigentes están resumidas al final.

---

## 2026-10-03 · Exposición, interfaz de batalla y teclas
- **Decidió:** el dueño.
- **Qué:**
  - La exposición queda fija en el nivel, con una compensación de −1 EV.
  - La interfaz de batalla (paso B5) se hace como la de hoy, más los arreglos de lectura A1-A3 de `interfaz-batalla-ue.md`: atacante legible, rótulos de unidad legibles y la depuración detrás de una tecla.
  - Teclas con el soldado propio:
    - F1-F3 para las órdenes;
    - V cambia entre tercera y primera persona;
    - la vista de comandante (RTS) va a Tab.
  - Las órdenes se muestran en una tira de botones abajo, como en Bannerlord, y se eligen con 1-4 sin pausar. Antes de construirla se le enseñan al dueño variantes animadas.
- **Afecta a:** Diego (exposición), Valeria y Lucía (interfaz).
- **Sustituye a:** —

## 2026-10-03 · Comportamiento de la batalla en UE5 (dudas de la referencia de Andrés)
- **Decidió:** el dueño (los cuatro primeros puntos); Bruno (el método de comparación).
- **Qué:**
  - Los vehículos llevan la velocidad que se ve hoy en LÖVE (unos 3,4 m/s con orden), no la del catálogo.
  - Un tanque con orden de atacar sin línea de vista se acerca o busca una posición con vista. Hoy en LÖVE se queda quieto, y eso se corrige.
  - La infantería con orden de moverse corre a unos 2,5 m/s aunque esté bajo fuego. Sin orden sigue agachada.
  - Determinismo entre Windows y Linux desde el principio, con matemática propia en el núcleo de la batalla.
  - La comparación entre UE y LÖVE es estadística, sobre unas 10 semillas (en LÖVE los efectos gastan el azar de la pelea).
- **Afecta a:** Andrés y Codex (núcleo, tropas y vehículos) y a Elena (pruebas).
- **Sustituye a:** —

## 2026-10-03 · Pasos de la batalla en UE5 y batallas de prueba desde archivo
- **Decidió:** el dueño.
- **Qué:** se aprueba el orden B1–B7 de `plan-traspaso-ue5.md`:
  1. B1: terreno, soldados con órdenes y cámara.
  2. B2: combate de infantería.
  3. B3: tanques y lanzacohetes.
  4. B4: misiles y efectos.
  5. B5: interfaz.
  6. B6: despliegue.
  7. B7: soldado a pie y luz por hora.

  También se aprueba lanzar batallas de prueba sin campaña con un JSON de `Datos/batallas/` (`-batalla=<nombre>`).
- **Afecta a:** todo el equipo de la batalla.
- **Sustituye a:** —

## 2026-10-03 · En UE5, la batalla 3D va primero
- **Decidió:** el dueño.
- **Qué:** tras la etapa 0, lo primero que se rehace en Unreal es la batalla 3D tal como funciona en LÖVE (tropas, órdenes, tanques, lanzacohetes, misiles, daños, despliegue, cámara e interfaz de batalla), con la iluminación, la física y las partículas de UE. Después llega el mapa de campaña. El código de LÖVE (etiqueta `love-final-2026-10-03`) es la referencia de comportamiento. Lo que ya no vale (mundo procedural, mapa 2D, naciones) no se pasa.
- **Afecta a:** el orden de etapas de `plan-traspaso-ue5.md` y de VISION.md.
- **Sustituye a:** el orden «mapa de campaña primero» del plan.

## 2026-10-03 · Plan de traspaso a UE5 aprobado
- **Decidió:** el dueño.
- **Qué:** aprueba `plan-traspaso-ue5.md` y se empieza por la etapa 0.
  - El repo nuevo va en `~/games/NationsRTS-UE` (git propio con LFS) y los documentos de diseño se mudan a él.
  - El mapa de campaña es una maqueta a escala 1:10 (unos 90 × 56 km) con las montañas exageradas ×3.
  - En C++ se sigue la convención de UE (PascalCase y prefijos), con los nombres en español.
  - El modo en línea queda para después, pero la simulación se prepara para servidor desde el principio.
  - Codex trabaja con las reglas de la sección 5: worktree propio, bloqueos y revisión de Elena y Bruno.
- **Afecta a:** todo el estudio.
- **Sustituye a:** la regla de camelCase solo para el C++ de UE (el Lua que quede sigue igual).

## 2026-10-03 · El juego pasa a Unreal Engine 5
- **Decidió:** el dueño.
- **Qué:** Nations RTS se hará en Unreal Engine 5.8 con MassEntity y C++, no en LÖVE con 3DreamEngine. Antes de empezar se escribe un plan de traspaso por etapas que el dueño aprueba.
- **Por qué:** en la segunda ronda de medidas, UE5 (con LOD y sin Lumen/TSR) movió 2000 soldados a 111 FPS (2,3 ms de juego, 8,5 ms de GPU). LÖVE iba a 15–47 FPS con 1000 por la simulación en Lua. Los agentes trabajaron bien en UE5 desde la terminal. Límite de la comparación: la IA de la prueba en UE5 era trivial.
- **Afecta a:** todo el estudio. Se reaprovechan los modelos, el relieve, el diseño, la historia y los asentamientos. El código Lua se reescribe.
- **Sustituye a:** «LÖVE o Unreal 5: comparar con datos» (2026-10-02).

## 2026-10-03 · Historia: «La Guardia rota» con el incendio de Tavrel
- **Decidió:** el dueño.
- **Qué:** la historia mezcla las propuestas A y C de `historia-propuestas.md`:
  - la Guardia de los Pasos, la fuerza conjunta de las siete facciones, se rompe la misma semana en que arde la refinería de Tavrel;
  - el jugador es un sargento de la Guardia con su escuadra presa;
  - el hilo principal es el Estandarte de la Guardia, con tres finales: entregarlo a una facción, refundar la Guardia neutral en Dioskar o alzarlo con su propio nombre.

  El detalle está en `historia.md`.
- **Alternativas descartadas:** la propuesta B, «La noche del Faro», y las propuestas A o C por separado.
- **Afecta a:** lucia, andres (Tavrel y el combustible), diego, valeria (textos y misiones).
- **Sustituye a:** —
- **Pendiente:** elegir la facción de origen al empezar; un culpable sorteado en cada partida (de la propuesta B), que por ahora queda fuera.

## 2026-10-02 · LÖVE o Unreal 5: comparar con datos
- **Decidió:** el dueño.
- **Qué:** si LÖVE con 3DreamEngine se pone muy difícil para batallas grandes, la alternativa es Unreal Engine 5 (MassEntity y C++). Para decidir se compara con datos: la prueba de carga de Elena en LÖVE y una prueba acotada en UE 5.8 (unos 1000 soldados con MassEntity sobre un trozo del Cáucaso, en ~/games/NationsUE5Prueba). Esa prueba mide también lo bien que trabajan los agentes en Unreal desde la terminal.
- **Por qué:** Unreal trae mucho ya hecho, pero con los agentes el trabajo se complica (compilaciones largas, archivos binarios, el MCP).
- **Afecta a:** todo el estudio. Lo hecho en LÖVE a partir de ahora puede no reaprovecharse.
- **Sustituye a:** —

## 2026-10-02 · Batallas con muchos soldados: medir y, si no alcanza, C++ en LÖVE
- **Decidió:** el dueño.
- **Qué:** la batalla 3D tiene que mover muchos soldados, como Bannerlord (unos 1000). Primero se mide cuánto aguanta hoy (prueba de carga de Elena). Si LÖVE con Lua y 3DreamEngine no llega, se modifica el C++ de LÖVE para este juego (antes, FFI o un módulo nativo, como ya estaba decidido).
- **Por qué:** TaleWorlds hizo un motor propio para Bannerlord porque el de Warband no aguantaba tantos soldados.
- **Afecta a:** Valeria (render y animación), Andrés (simulación de tropas) y Elena (medidas).
- **Sustituye a:** —

## 2026-10-02 · El estudio: Bruno como jefe y personalidades del equipo
- **Decidió:** el dueño (aprobó la propuesta entera).
- **Qué:** Claude, como jefe de estudio, se llama Bruno y trabaja con las reglas de `~/forja-studios/jefe.md` (copiadas en `CLAUDE.md`). Cada trabajador tiene su carácter en su ficha (`~/forja-studios/agentes/`). Se abren este registro y `riesgos.md`.
- **Por qué:** que Claude actúe de verdad como jefe de estudio ante el dueño y ante el equipo, y que cada agente tenga personalidad.
- **Afecta a:** todo el equipo.
- **Sustituye a:** —

## 2026-10-02 · Nombres inventados para las PMC del GDD
- **Decidió:** el dueño.
- **Qué:** «Aegis Security» pasa a ser **Halvaren Security Group** y «Vanguard Corps», **Brakhmor Armored Company**.
- **Por qué:** los nombres originales coinciden con empresas u organizaciones reales.
- **Afecta a:** lucia (facciones y generales), textos del juego.
- **Sustituye a:** los nombres del GDD.

## 2026-10-02 · Personalización de vehículos e infantería: la del GDD
- **Decidió:** el dueño.
- **Qué:** en el taller, ERA, rejas anti-RPG y RWS para los vehículos; visores nocturnos o térmicos para la infantería (`diseno-de-armamento.md`).
- **Alternativas descartadas:** el kit de piezas por nación (diseños propios, estilos heredados y diseños secretos).
- **Afecta a:** lucia, camila, valeria.
- **Sustituye a:** el kit de piezas por nación (queda en el anexo de `diseno-de-armamento.md`).

## 2026-10-02 · Orden de construcción por etapas
- **Decidió:** el dueño.
- **Qué:** 13 etapas pequeñas, cada una jugable o visible y aprobada antes de la siguiente: mapa de campaña visible → vista de radar → columna del jugador con combustible → entrar a una ciudad (menú) → encuentro y batalla → soldado del jugador en la batalla → después de la batalla → pueblos que producen y convoyes → notables y contratos → primeras facciones con generales → compañeros → resto de facciones → hub a pie, asedios, supresión, TEL, mercado negro y habilidades (`VISION.md`, sección 6).
- **Afecta a:** todo el equipo.
- **Sustituye a:** —

## 2026-10-02 · Siete facciones
- **Decidió:** el dueño.
- **Qué:** Unión Voskara, República Kelvana, Federación Hazarlí, República de Anzerat y Liga de Pontara (ejércitos estatales); Hermandad de Ardzun (milicia regional); Puerto franco de Dioskar (neutral). Las PMC no tienen territorio (`VISION.md`, sección 5.1).
- **Afecta a:** lucia, andres.
- **Sustituye a:** las naciones con territorio procedural.

## 2026-10-02 · Lo que puede llegar a poseer el jugador
- **Decidió:** el dueño.
- **Qué:** en este orden: plaza de hangar en una ciudad (con reputación), taller propio al fundar su PMC, proteger un pueblo a cambio de parte de su producción y, al final, una ciudad concedida o conquistada.
- **Afecta a:** lucia, andres.
- **Sustituye a:** el jugador como presidente o alcalde de su nación.

## 2026-10-02 · Economía de asentamientos, inicio en Dioskar y campamentos de milicia
- **Decidió:** el dueño.
- **Qué:** los pueblos dan materia prima y la ciudad la convierte (crudo en combustible; acero y explosivos en munición y repuestos; comida y reclutas en tropas). El jugador empieza en el puerto franco de Dioskar. Hay campamentos de milicia como las guaridas de bandidos de Bannerlord.
- **Afecta a:** lucia, andres.
- **Sustituye a:** la economía cerrada del 2026-09-30 (un solo dinero, producción a mano con tope por nivel, vehículos que no se destruyen).

## 2026-10-02 · Ciudades y pueblos, sin castillos
- **Decidió:** el dueño.
- **Qué:** asentamientos como en Bannerlord, modestos y modernos: ciudades (economía, mercado, reclutamiento, diplomacia) y pueblos (materias primas para su ciudad). Detalle en `asentamientos.md`; las cifras de 18 ciudades y 67 pueblos son propuesta.
- **Alternativas descartadas:** castillos.
- **Afecta a:** lucia, valeria, camila.
- **Sustituye a:** capitales con torre y campamentos de metal, petróleo o dinero.

## 2026-10-02 · La luz del mapa es la de la batalla
- **Decidió:** el dueño.
- **Qué:** el mapa de campaña usa la misma iluminación que la batalla 3D (luz, tono, atmósfera, IBL y sombras), sin una luz aparte.
- **Afecta a:** valeria.
- **Sustituye a:** —

## 2026-10-02 · Un solo mapa fijo del Cáucaso
- **Decidió:** el dueño.
- **Qué:** un único mapa con el relieve real del Cáucaso y el Mar Negro, de 37° a 48° E y de 40° a 45° N (unos 903 × 557 km, DEM Copernicus). Países, ciudades y facciones con nombres inventados; la geografía es real.
- **Por qué:** lo prioritario es que el relieve se vea como Calradia.
- **Alternativas descartadas:** el mundo procedural infinito con semillas.
- **Afecta a:** valeria, andres, lucia.
- **Sustituye a:** el mundo procedural y la escala de naciones sin límite.

## 2026-10-02 · Mapa de campaña en 3D, con vista de radar
- **Decidió:** el dueño.
- **Qué:** el mapa de campaña es 3D, como Calradia en Bannerlord, con cámara desde arriba que se puede inclinar y columnas como modelos pequeños o impostores. Una tecla cambia el mismo mapa a vista de radar (firmas térmicas y de radar, convoyes y alcance de detección). Donde el GDD dice «2D», se refiere a este mapa.
- **Por qué:** se ve mejor, el relieve cuenta para el sigilo (cañones y bosques) y la batalla 3D se puede generar del mismo terreno.
- **Alternativas descartadas:** mapa operativo 2D; mapa 2D isométrico.
- **Afecta a:** valeria, camila.
- **Sustituye a:** el mapa 2D isométrico.

## 2026-10-02 · El jugador pelea en persona en la batalla 3D
- **Decidió:** el dueño.
- **Qué:** el jugador está en el campo con su propio soldado. Cámara en tercera persona tras el hombro y una tecla para la primera persona. A la vez manda a su tropa con F1 (movimiento), F2 (formación) y F3 (reglas de enfrentamiento).
- **Afecta a:** valeria, camila, andres.
- **Sustituye a:** —

## 2026-10-02 · Progresión desde abajo
- **Decidió:** el dueño.
- **Qué:** el jugador empieza como una persona cualquiera (combatiente o contratista con poco), firma contratos, recluta, monta su PMC y gana reputación, poder e influencia. Al principio no es dueño de ninguna ciudad ni nación.
- **Afecta a:** lucia, andres.
- **Sustituye a:** el jugador como presidente o alcalde de su nación.

## 2026-10-02 · El GDD «Guerra Moderna RTS» marca el rumbo
- **Decidió:** el dueño.
- **Qué:** el juego pasa a ser «casi lo mismo que Bannerlord, pero en guerra moderna»: mapa de campaña, hub urbano, batalla táctica 3D y fase después de la batalla, con economía logística (combustible, munición y repuestos), facciones con reputación, contratos y generales (`diseno/GDD-guerra-moderna-rts.pdf`).
- **Afecta a:** todo el equipo.
- **Sustituye a:** la visión anterior; la lista completa está en `VISION.md`, sección 7.

---

## Pendientes de decidir

- Cómo se gana o se pierde la partida.
- El hub urbano 3D a pie: qué se ve, cómo se entra y qué se hace dentro.
- El detalle de las facciones (estilo de tropas, clanes y generales concretos).
- Si habrá modo en línea y cómo.
- Qué se reaprovecha del código del juego anterior en `mundo/`.
- Los iconos de `encargo-diseno-hud.md`.

## Anteriores al 2026-10-02 que siguen vigentes

Resumen de `VISION.md`, sección 8:

- Estilo realista militar low-poly, nítido como Unreal: nada de imágenes lavadas, neblina ni desenfoque «por estilo».
- Armamento real nombrado por su designación; lo político es inventado.
- Color de bando en la cinta del casco del soldado; camiones y tanques sin franja.
- Rendimiento con toda la tecnología: hilos, caché, LOD, sombreadores y C o C++ si Lua no alcanza.
- Interfaz de estilo militar: acero oscuro, dorado y gris claro (`interfaz-militar.md`).
- Todo en español.
- Estilo de código del dueño.
- Sin topes artificiales: solo limitan los recursos y el tiempo, y los NPC usan las mismas acciones y reglas que el jugador.

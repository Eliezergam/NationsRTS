# Pruebas de aceptación de la batalla en UE5

Plan de verificación para comprobar, en cada paso del traspaso
(`plan-traspaso-ue5.md`, §3.1), que la batalla de Unreal Engine 5 se comporta
como la de LÖVE en la etiqueta `love-final-2026-10-03`. Lo escribió Elena
el 2026-10-03. Va con `referencia-batalla.md` de Andrés: él describe los
sistemas y sus pruebas numéricas (§17); este documento dice cómo se mide
cada prueba en LÖVE y en UE, qué se midió hoy en LÖVE y qué pruebas cierran
cada paso. Añade las pruebas de terreno, cámara, interfaz, efectos y
rendimiento, que su §17 no cubre.

- **[Propuesta]** todo el documento, salvo lo que cita una decisión de
  el dueño.
- Rutas relativas a `NationsRTS/` en la etiqueta.

## 1. Nombres y estados

**Identificadores:** los de Andrés, `PA-<SISTEMA>-<nn>`. En UE, la prueba de
automatización se llama `NationsRTS.Batalla.<Sistema>.PA_<SIS>_<nn>`.

| Sistema | Qué cubre | Dónde está |
|---|---|---|
| BAL | Balística | `referencia-batalla.md` §17.1 |
| DAN | Penetración y averías | §17.2 |
| EXP | Explosiones contra infantería | §17.3 |
| INF | Infantería | §17.4 |
| TAN | Tanques | §17.5 |
| LAN | Lanzacohetes | §17.6 |
| MOV, ORD | Movimiento y órdenes | §17.7 |
| DES, OLE, FIN, DET | Despliegue, oleadas, final y determinismo | §17.8 |
| **TER** | Terreno de batalla, límite y pasillos | este documento, §5 |
| **SEL** | Selección con el ratón y el teclado | §6 |
| **CAM** | Cámara RTS y a pie | §7 |
| **INT** | Interfaz de batalla | §8 |
| **EFE** | Efectos, misiles en vuelo y restos | §9 |
| **REN** | Rendimiento | §10 |

**Estado de cada prueba en LÖVE** (columna «LÖVE hoy»):

- **PASA:** el arnés corrió hoy con la etiqueta y dio la cifra.
- **FALLA:** el arnés corrió y la prueba no se cumple en LÖVE.
- **NO COMPROBADO:** no corrió hoy; se dice por qué. Una cifra analítica
  (A) de Andrés que no recalculé va así.

## 2. Cómo se compara UE con LÖVE

LÖVE no se puede repetir bit a bit en UE (Andrés, `referencia-batalla.md`
§15): las partículas gastan el mismo azar que la pelea, los vehículos los
mueve Box2D y las funciones de la libm cambian entre sistemas. Por eso hay
tres tipos de prueba:

| Tipo | Origen (Andrés) | Cómo se acepta en UE |
|---|---|---|
| Exacta | A (analítica) o C (regla del código) | Prueba de automatización sin render (`-nullrhi`) con el escenario aislado; tolerancia de 0,1 % en A y exacta en C |
| Estadística | M (medida en LÖVE) | Misma composición de bandos en **10 semillas** en LÖVE y en UE; se compara la **media** con la tolerancia de la prueba y, además, que la media de UE quede dentro de **dos desviaciones típicas** de las 10 de LÖVE |
| Visual | Captura | Captura sin ventana desde la misma cámara (posición, rumbo, inclinación y FOV de 40°) que la de LÖVE, mirada por Elena y Bruno; los números del rótulo se comparan como en una prueba exacta |

- **Semillas de la serie:** 42, 7, 123, 1234, 1, 2, 3, 4, 5 y 6. Hoy solo
  42, 7, 123 y 1234 tienen medidas en LÖVE (§11); las otras seis están por
  medir (se hace al empezar B2).
- **En UE la semilla es el archivo de batalla** (`Datos/batallas/*.json`).
  Para comparar con LÖVE hace falta una batalla equivalente: la misma
  composición (30 tanques de los cuatro modelos y 10 lanzacohetes de los
  tres por bando, más la infantería de las guarniciones) en un sitio de
  relieve parecido. Como el sitio no será el mismo (en UE sale del DEM real),
  las batallas completas se comparan con la tolerancia de las
  estadísticas, nunca al bit.
- **Determinismo dentro de UE** sí es exacto (PA-DET-01 a 03): misma
  semilla y mismos comandos, misma huella.

### 2.1 Formato de las medidas en UE

Cada prueba de automatización escribe una línea CSV en
`Saved/Pruebas/batalla.csv`:

```
id,semilla,valor,esperado,tolerancia,estado
PA-ORD-01,42,11.8,12.4,15,PASA
```

- `Herramientas/pruebas.sh Batalla` las corre todas; Elena compara el CSV
  con la columna «LÖVE» de este documento.
- Las batallas completas escriben además el resultado unidad por unidad en
  JSON (formato de `batalla/DANO-REAL.md` §5.6) y una línea `ESTADO` cada
  30 s con los mismos campos que `pruebas_dano` (soldados, tanques en pie,
  inmovilizados, avance y distancia al enemigo), para poder trazar las dos
  curvas juntas.

## 3. Qué pruebas cierran cada paso

| Paso (plan §3.1) | Pruebas que deben pasar en UE |
|---|---|
| B1. Terreno y órdenes | PA-TER-*, PA-SEL-*, PA-MOV-01 a 05, PA-ORD-01 a 04 y 06, PA-CAM-01 a 08, PA-INT-01 y 02, PA-REN-01 a 03 |
| B2. Infantería | PA-BAL-05, PA-EXP-*, PA-INF-*, PA-FIN-01 a 03, PA-DET-01 a 03, PA-REN-04 |
| B3. Tanques y lanzacohetes | PA-BAL-01 a 04, PA-DAN-*, PA-TAN-*, PA-LAN-*, PA-ORD-05, PA-OLE-01, PA-REN-05 |
| B4. Misiles y efectos | PA-BAL-06 a 09, PA-EFE-*, PA-CAM-14, PA-FIN-04 y 05, PA-DET-04, PA-REN-06 |
| B5. Interfaz | PA-INT-*, PA-SEL-* otra vez con la interfaz de UMG |
| B6. Despliegue | PA-DES-*, PA-CAM-09 |
| B7. A pie, luz y cierre | PA-CAM-10 a 13, PA-REN-* completo (tabla final) |

Una prueba que pasó en un paso se vuelve a correr en los siguientes
(`pruebas.sh` entero en cada cambio).

## 4. Pruebas de Andrés (§17 de `referencia-batalla.md`)

Las cifras y los escenarios están en su documento; aquí, cómo se mide cada
grupo y lo que medí hoy.

### 4.1 Cómo se mide cada grupo

| Grupo | En LÖVE | En UE |
|---|---|---|
| BAL, DAN, EXP (A y C) | LuaJIT con los módulos puros (`dano/trayectoria.lua`, `dano/blindaje.lua`, `dano/explosiones.lua`, `dano/datos.lua`) | Automation sin render sobre `BatallaProyectiles` y `BatallaDano` (C++ puro); las de 10 000 tiradas, con el RNG por flujos y semilla fija |
| INF, TAN, LAN (C) | No se mide en LÖVE (decidido el 2026-10-03): la cifra es la analítica o la regla de Andrés | Automation con un mundo de Mass mínimo: 1 o 2 unidades sobre un terreno plano y el reloj de paso fijo; se lee el estado paso a paso |
| MOV, ORD | `batalla/pruebas_control` (semillas 42, 7 y 123) y `batalla/pruebas_rutas` | Automation que inyecta acciones de Enhanced Input con coordenadas de pantalla reales (como `prueba_raton.lua`) y lee el destino, la ruta y la llegada |
| DES | `love . --test` (`tests/test_nationsrts_despliegue.lua`) | Automation con la escena de batalla en preparación |
| OLE, FIN | `pruebas_control` (regla de 60 s), `pruebas_economia`, `pruebas_dano` | Batalla completa sin render, 10 semillas |
| DET | `pruebas_dano medir` dos veces (huella) | Dos procesos con `-nullrhi` y la misma batalla; con y sin vista |

### 4.2 Lo medido hoy en LÖVE

| Id | LÖVE hoy | Medida (arnés, semilla) | Nota |
|---|---|---|---|
| PA-BAL-01 a 09 | NO COMPROBADO | — | Analíticas de Andrés; no las recalculé |
| PA-DAN-01 a 12 | NO COMPROBADO | — | Analíticas o reglas; no hay arnés que las aísle |
| PA-DAN-13 | PASA | `pruebas_economia` 42: 13 196 comprobaciones, 0 fallos; ningún vehículo desaparece (61 → 61 y 26 → 26) | |
| PA-EXP-01 a 06 | NO COMPROBADO | — | Analíticas |
| PA-INF-01 a 09 | NO COMPROBADO | — | Sin arnés aislado. Ver la anomalía H3 (§12) |
| PA-TAN-01 a 05, 07, 08 | NO COMPROBADO | — | Reglas del código sin arnés aislado |
| PA-TAN-06 | NO COMPROBADO | — | `pruebas_control` no imprime la velocidad; la cifra es de la traza de Andrés |
| PA-LAN-01 a 04, 06, 07 | NO COMPROBADO | — | Sin arnés aislado |
| PA-LAN-05 | PASA | `love . --test`: las 11 pruebas `rampa:` pasan | |
| PA-MOV-01 | NO COMPROBADO | — | Igual que PA-TAN-06 |
| PA-MOV-02 | PASA | `pruebas_control`: 42 → 38 s y 8,6 m; 7 → 99 s, 8,7–8,9 m; 123 → 41 s, 8,9 m | La duración varía mucho entre semillas (38–99 s): en UE, solo «llegan» y la distancia < 30 m |
| PA-MOV-03 | PASA en parte | `pruebas_limite`: 288 080 comprobaciones en 60 s, 0 fuera del límite, margen mínimo 21,3 m; `pruebas_rutas`: 9 casos, 0 fallos | Agua y pendiente en 600 s: NO COMPROBADO (no hay arnés que lo cuente) |
| PA-MOV-04 | PASA | `pruebas_control` 42: dispara desde su puesto a 25,9 m | |
| PA-MOV-05 | NO COMPROBADO | — | Sin arnés |
| PA-ORD-01 | PASA | `pruebas_control` 42: 12,4 m | Umbral del arnés: 15 m |
| PA-ORD-02 | PASA | `pruebas_control` 42, 7 y 123 | |
| PA-ORD-03 | PASA en parte | `pruebas_control`: huecos separados más de 10 m | El arnés no comprueba las distancias exactas |
| PA-ORD-04 | PASA | `pruebas_control` 42, 7 y 123: ninguna se mueve 4 m o más en 15 s | El arnés no imprime la distancia; Andrés da 0 m |
| PA-ORD-05 | **FALLA** con 42, PASA con 7 y 123 | Ver H1 (§12) | **[Decisión del dueño, 2026-10-03]** en UE se corrige: si el blanco está a tiro pero sin vista, el tanque busca una posición con línea de vista. En UE la prueba exige que dispare (o que el blanco caiga) en 240 s también con la semilla 42 |
| PA-ORD-06 | NO COMPROBADO | — | |
| PA-DES-01, 02 | PASA | `love . --test`: las 7 pruebas `despliegue:` pasan | |
| PA-OLE-01 | PASA en parte | `pruebas_economia` 42: entran 50 vehículos del atacante, 10 por oleadas, 40 como mucho en el campo | No mide los 12 s |
| PA-FIN-01 | PASA | `pruebas_control` 42, 7 y 123 | |
| PA-FIN-02 | PASA | `pruebas_economia` 42: el atacante se retira por `municion` | |
| PA-FIN-03 | NO COMPROBADO | — | |
| PA-FIN-04 | PASA con diferencias | Ver §11.2 | La cifra del defensor no coincide |
| PA-FIN-05 | **No coincide** | Ver §11.1 | Las cifras de Andrés son de DANO-REAL del 2026-10-01 |
| PA-DET-01 | PASA | `pruebas_dano medir 42` en dos procesos: huella 2138962852 las dos veces | |
| PA-DET-02 | NO COMPROBADO hoy | — | DANO-REAL §9.2 dice que pasó el 2026-10-01 |
| PA-DET-03 | NO COMPROBADO | — | Andrés: LÖVE no lo cumple (Box2D solo con vista) |
| PA-DET-04 | NO COMPROBADO hoy | Medida contaminada (§11.1) | Hay que repetirla en solitario |

## 5. Terreno de batalla (TER)

| Id | Escenario | Esperado | Tolerancia | LÖVE hoy | En UE |
|---|---|---|---|---|---|
| PA-TER-01 | Área de la batalla | 3 × 3 km (`Suelo.lado` 30 000 px) con límite circular de 1,2 km de radio (`Limite.radio`) | exacto | PASA (`pruebas_limite`: radio 12 000 px) | Automation: tamaño de la malla y radio del límite |
| PA-TER-02 | Tiempo de generar el sitio | LÖVE: suelo 3,7–4,5 s; escena lista en 8,5–13,2 s (semilla 42, con otros procesos en marcha) | UE: **≤ 10 s** (plan §3.1, B1) | PASA (medida, `pruebas_control`, `pruebas_dano`, `pruebas_limite`, `pruebas_economia`) | Automation que mide de `-batalla=` a la escena lista; CSV |
| PA-TER-03 | Malla del terreno | LÖVE: 454 496 triángulos, vértices a 4 m en el centro (`Suelo.paso`) | UE: misma resolución o más fina en los 420 m centrales | PASA | Recuento de la malla por LOD |
| PA-TER-04 | Ninguna unidad del despliegue fuera del límite y con margen | 80 vehículos, 0 fuera, margen mínimo 21,3 m | 0 fuera | PASA (`pruebas_limite`) | Automation tras formar |
| PA-TER-05 | En 60 s de pelea, nadie sale del límite | 0 fuera (288 080 comprobaciones) | 0 | PASA (`pruebas_limite`) | Automation sin render, 60 s |
| PA-TER-06 | Pasillo de avance: pendiente del perfil ≤ 8°, ninguna celda > 22°, 100 m de ancho | `pruebas_rutas`: 9 casos, perfil 0–8,00°, formación 40/40 por bando | perfil ≤ 8,0° | PASA | Automation sobre el A* de `BatallaTerreno` en 10 sitios |
| PA-TER-07 | El pasillo es el mismo con la misma semilla | firma igual en dos pasadas | exacto | PASA (`pruebas_rutas`, «DETERMINISMO nuevo: BIEN») | Automation: hash del eje |
| PA-TER-08 | Vegetación y rocas del sitio | semilla 42: Pino 2186, Abeto 1394, Roble 4050, Abedul 2021, Arbusto 9137, Roca 6537, Cactus 258 | — (otro sitio en UE) | PASA (medida) | Solo de referencia: en UE el sitio sale del DEM; se compara la **densidad por hectárea** por bioma, ± 20 % |

## 6. Selección (SEL)

Todas por los callbacks reales (en LÖVE, `love.mousepressed`,
`love.mousemoved`, `love.mousereleased` y `love.keypressed` con las
coordenadas de pantalla de la unidad proyectada). En UE, Automation que
inyecta acciones de Enhanced Input; nunca llamando a la función interna.

| Id | Escenario | Esperado | LÖVE hoy (`pruebas_control`, 42/7/123) | En UE |
|---|---|---|---|---|
| PA-SEL-01 | Clic sobre una unidad propia | solo esa elegida | PASA | Automation |
| PA-SEL-02 | Mayús + clic sobre otra | se suma | PASA | Automation |
| PA-SEL-03 | Mayús + clic sobre una elegida | se quita | PASA | Automation |
| PA-SEL-04 | Clic solo con varias elegidas | queda solo esa | PASA | Automation |
| PA-SEL-05 | Doble clic (≤ 0,35 s) | todos los tanques propios a la vista | PASA | Automation |
| PA-SEL-06 | Cuadro arrastrado | las propias de dentro; el cuadro se borra al soltar | PASA | Automation + captura |
| PA-SEL-07 | L / Mayús + T / I | todos los lanzacohetes / suma tanques / escuadras | PASA | Automation |
| PA-SEL-08 | Espacio no pausa; P pausa y la conserva; Escape limpia la selección antes de salir | sí | PASA (`love . --test`, `batalla:`) | Automation |

## 7. Cámara (CAM)

| Id | Escenario | Esperado (LÖVE) | Tolerancia | LÖVE hoy | En UE |
|---|---|---|---|---|---|
| PA-CAM-01 | Campo de visión | 40° | exacto | PASA (`pruebas_camara`) | Automation: FOV del Pawn |
| PA-CAM-02 | Girar con el botón derecho | el ojo no se mueve; sin deriva al soltar | < 1 mm | PASA (`pruebas_camara`) | Automation con Enhanced Input |
| PA-CAM-03 | W/S hacia la mirada en 3D; A/D a los lados; Mayús no mueve | sí | — | PASA | Automation |
| PA-CAM-04 | Sin saltos: la velocidad sube y baja poco a poco (`Controlador.resistencia` 5) | mismo perfil de velocidad a 30, 60 y 144 FPS | ± 5 % | PASA (`pruebas_camara`, trayectoria igual a 30/60/144 FPS) | Automation: posición tras 1 s de W a 30, 60 y 144 FPS |
| PA-CAM-05 | El ojo no sale del campo; se desliza por el borde | sí | — | PASA | Automation |
| PA-CAM-06 | Sin techo: 10 s de Espacio | sube a 948 m | ± 5 % | PASA (`pruebas_camara`) | Automation |
| PA-CAM-07 | Suelo suave | nunca por debajo de 2 m; vuelve a 6 m sin saltos | exacto | PASA | Automation |
| PA-CAM-08 | Sacudida por explosión | solo a menos de 120 m, 0,45 s, vuelve al encuadre exacto | exacto | PASA | Automation |
| PA-CAM-09 | Cámara en la preparación | dentro de la zona propia, a 80 m como mucho, sin salir volando | — | PASA (`love . --test`, `despliegue:`) | Automation |
| PA-CAM-10 | V baja a pie y V vuelve | ojo a 1,7 m del suelo; vuelve a la misma cámara RTS | ± 0,15 m | PASA (`pruebas_caminante` 42: 1,70 m; Esc y V vuelven a la vista RTS donde estaba) | Automation con el Character |
| PA-CAM-11 | Caminar / correr | 1,4 m/s / 4,5 m/s | ± 0,1 / ± 0,2 m/s | PASA (1,40 / 4,50 m/s; salto de 0,47 m) | Automation |
| PA-CAM-12 | El ojo sigue el relieve | desvío < 0,3 m | — | PASA (0,00 m) | Automation |
| PA-CAM-13 | No entra en agua de más de 0,8 m; choca con troncos, rocas y vehículos | sí | — | PASA (se para a 0,30 m del casco y de la corteza; no entra en el agua honda; el recinto de la preparación lo limita) | Automation |
| PA-CAM-14 | Seguir un misil | se acerca sin saltos ni inercia sobrante | — | PASA (`pruebas_camara`) | Automation |

## 8. Interfaz de batalla (INT)

| Id | Escenario | Esperado | LÖVE hoy | En UE |
|---|---|---|---|---|
| PA-INT-01 | Anillo de la unidad elegida | radio 9,5 m (tanque), 13 m (lanzacohetes), 4 m (soldado) | PASA (captura `control_mover.png`, mirada) | Captura desde la misma cámara + Automation que lee el radio del decal |
| PA-INT-02 | Cinta de la ruta | sale de la unidad, sigue la ruta suave (puntos cada 4 m) y acaba en un anillo en el destino; se borra al llegar | PASA (captura `control_mover.png`) | Captura + Automation (puntos de la cinta = puntos de la ruta) |
| PA-INT-03 | Marcador de una orden | dura 1,6 s; rojo para atacar | NO COMPROBADO (no medido hoy) | Automation |
| PA-INT-04 | Rótulo de bandos | nombre, soldados en pie / entraron, tanques y lanzacohetes en pie, munición | PASA (captura) | Captura + Automation que compara los números con `recuento` |
| PA-INT-05 | Avisos y pantalla de fin | aviso de retirada; fin 6 s después del final | PASA en parte (`pruebas_control`: regla de 60 s; el dibujo no se miró) | Captura |
| PA-INT-06 | Contador de la preparación y botón «Listo» | 2:00 que baja; «Listo» abre el combate | PASA (`love . --test`) | Automation + captura |
| PA-INT-07 | Estilo militar (acero, dorado y gris claro) | como `interfaz-militar.md` | NO COMPROBADO (la batalla de LÖVE aún usa el rótulo de texto) | Captura mirada por Bruno; el dueño da el visto bueno |

## 9. Efectos, misiles en vuelo y restos (EFE)

| Id | Escenario | Esperado | LÖVE hoy | En UE |
|---|---|---|---|---|
| PA-EFE-01 | Salva del Scud-B | 4 misiles de uno en uno con estela continua | PASA (`pruebas_lanzamisiles`: 4 disparos, rampa recargada) | Captura secuencia + Automation (eventos `FEvDisparo`) |
| PA-EFE-02 | Restos del camión destruido | caen con gravedad, se apoyan y quedan quietos; no empujan a la unidad vecina | PASA (`pruebas_lanzamisiles`, 33 797 comprobaciones) | Automation con Chaos: reposo en < 10 s y fuerza 0 sobre la vecina |
| PA-EFE-03 | Árbol que choca con un camión | lo detiene aunque acelere | PASA (`pruebas_lanzamisiles`) | Automation |
| PA-EFE-04 | Física igual con balas y explosiones | los impactos no cambian la física del camión | PASA | Automation |
| PA-EFE-05 | Los efectos no cambian la pelea | misma huella con efectos y sin ellos | **No se cumple en LÖVE** (Andrés §15.1) | Automation: huella con Niagara activo y con `-nullrhi` |
| PA-EFE-06 | Misiles dibujados por salva | 8 como mucho; el resto vuela sin dibujarse | NO COMPROBADO | Automation sobre el recuento de instancias |
| PA-EFE-07 | Partículas | 1400 como mucho | NO COMPROBADO | Recuento de Niagara (`stat Niagara`) |

## 10. Rendimiento (REN)

### 10.1 Medido hoy en LÖVE

Todo a 1920 × 1080, calidad alta, sin vsync, sin ventana
(`SDL_VIDEODRIVER=offscreen`), descartando los cuadros de carga. Cada
medida espera a que no haya otro `love` ni Unreal en marcha.

**Soldados animados en combate** (arnés de carga de Elena, `python3
ejecutar.py <N> ml` en
`<carpeta temporal>`;
Diego lo guarda en el repositorio de UE, en
`Pruebas/referencia-love/carga/`): N soldados en dos bandos
que pelean; 60 cuadros de calentamiento y 300 medidos tras 20 s de pelea.
Encuadre m: detrás de la línea, a 60 m y 25 m de alto; l: a 120 m y 50 m.

| Soldados | m: FPS / 1 % peor | l: FPS / 1 % peor | Simulación de tropas (ms por cuadro) | GPU (ms) |
|---|---|---|---|---|
| 0 | 94,7 / 40,3 (2.ª ronda: 101,1 / 47,1) | 107,2 / 51,1 (111,0 / 55,7) | 0,2 | 9,3–9,9 |
| 500 | 85,5 / 23,7 | 80,5 / 15,0 | 5,9–7,4 | 9,9–10,8 |
| 1000 | 39,5 / 20,8 | 37,8 / 22,0 | 20,6–21,9 | 12,6–12,9 |
| 2000 | 17,3 / 10,5 | 16,3 / 8,1 | 52,7–56,2 | 12,5–13,3 |
| 500 + 40 tanques + 40 lanzacohetes por bando (124 misiles en vuelo) | 50,7 / 16,3 | 54,6 / 20,0 | 7,5–9,7 (+ 0,8–1,1 de efectos) | 11,7–12,9 |

- **Una sola ronda limpia.** La segunda se cortó: a partir de N = 500
  empezaron otros procesos de Unreal (Camila y el terreno) y dio 52,2 / 27,6
  y 31,5 / 13,3 con N = 500, con la simulación al doble. Esa ronda no vale.
- **Lo que limita en LÖVE es la simulación en Lua**, no la GPU: con 2000
  soldados la GPU va a 13 ms y la simulación a 53–56 ms.

**Batalla de `pruebas_rendimiento`** (`ejecutar.py alta b,d,e 0.31`,
semilla 42, 40 lanzacohetes por bando y la infantería de las guarniciones,
mediodía, MSAA 4, generación 8,39 s):

| Encuadre | FPS | 1 % peor | CPU (ms) | GPU (ms) | Llamadas de dibujo |
|---|---|---|---|---|---|
| b) normal | 116 | 66 | 8,52 | 8,57 | 201 |
| d) «dentro de la batalla» | 127 | 40 | 7,79 | 7,75 | 254 |
| e) vista alta | 144 | 40 | 6,87 | 6,56 | 186 |

El encuadre d de hoy queda pegado a un pino y casi no ve unidades (captura
`rendimiento_alta_d.png`, mirada): mide vegetación de cerca, no la pelea.

### 10.2 La prueba de UE5 (2026-10-03, ronda 2)

`~/games/NationsUE5Prueba/Saved/medicion.csv`, soldados con LOD y luz
barata, IA trivial:

| Soldados | FPS | Cuadro (ms) | Game (ms) | GPU (ms) | Peor cuadro (ms) |
|---|---|---|---|---|---|
| 0 | 205,4 | 4,87 | 1,45 | 4,41 | 8,62 |
| 500 | 141,5 | 7,07 | 1,82 | 6,62 | 8,35 |
| 1000 | 120,5 | 8,30 | 2,04 | 7,84 | 10,81 |
| 2000 | 111,5 | 8,97 | 2,28 | 8,51 | 10,87 |

Ese CSV da el **peor cuadro**, no el 1 % peor. Diego añade el 1 % peor
(media del 1 % de cuadros más lentos) a `Herramientas/medir.sh` del
proyecto nuevo para poder comparar con LÖVE.

### 10.3 Objetivos mínimos en UE5 por paso **[Propuesta]**

1920 × 1080, los ajustes de render de la etapa 0, sin vsync, sin ventana,
5 s de calentamiento y 300 cuadros medidos, **dos rondas** y se da la peor.
Una medida vale solo si no hay otro `love` ni otro Unreal en marcha.

| Id | Paso | Escena | FPS medio | 1 % peor | Otros límites | LÖVE hoy |
|---|---|---|---|---|---|---|
| PA-REN-01 | B1 | Sitio de 3 km sin unidades; encuadres normal y vista alta | ≥ 144 | ≥ 90 | generación ≤ 10 s | 107–144 / 40–66 |
| PA-REN-02 | B1 | 1000 soldados por bando con órdenes de mover, sin combate | ≥ 90 | ≥ 60 | Game ≤ 4 ms | — (no medido sin combate) |
| PA-REN-03 | B1 | 2000 soldados en total con órdenes | ≥ 60 | ≥ 45 | Game ≤ 8 ms (señal de alarma de la sección 6 del plan) | 16–17 / 8–10 (en combate) |
| PA-REN-04 | B2 | 2000 soldados en combate (ráfagas, trazas y bajas) | ≥ 60 | ≥ 40 | paso de la simulación ≤ 4 ms de media y ≤ 8 ms en el 1 % peor | 16–17 / 8–10 |
| PA-REN-05 | B3 | 1000 soldados + 40 tanques y 40 lanzacohetes por bando | ≥ 60 | ≥ 40 | Game ≤ 8 ms | — (con 500: 51–55 / 16–20) |
| PA-REN-06 | B4 | Lo de REN-05 con 150 misiles en vuelo, explosiones y restos | ≥ 60 | ≥ 40 | Niagara ≤ 2 ms de GPU | — (con 500: 51–55 / 16–20, 124 misiles) |
| PA-REN-07 | B7 | Tabla final: 0, 500, 1000 y 2000 soldados con los vehículos de REN-05, en los encuadres m y l, y a pie | ≥ 60 en todas | ≥ 40 en todas | memoria y tiempo de carga apuntados | ver §10.1 |

- **De dónde salen.** La prueba de UE5 dio 111 FPS con 2000 soldados y una
  IA trivial (2,3 ms de Game). Con IA de verdad, combate, vehículos y
  efectos se pide la mitad: 60 FPS y 40 en el 1 % peor. Con 1000 soldados y
  sin combate (B1) se pide 90, cerca de los 120 de la prueba. En todos los
  casos es más del triple de lo que da hoy LÖVE en la misma escena.
- **Regla además de la tabla:** ninguna escena puede ir más lenta en UE que
  en LÖVE (§10.1).
- **En UE se mide con** `Herramientas/medir.sh <escena> <n>` (plan §4.1),
  que escribe en CSV `escena,soldados,vehiculos,misiles,fps,p1,frame_ms,
  game_ms,draw_ms,gpu_ms,peor_ms`, más una captura de cada encuadre que
  mira Elena. Las cámaras m y l se fijan en el archivo de la escena con las
  mismas distancias que el arnés de carga de LÖVE.

## 11. Batallas completas: cifras medidas hoy

Arnés `batalla/pruebas_dano/ejecutar.py <carpeta> medir <semilla>`: 30
tanques de los cuatro modelos y 10 lanzacohetes de los tres por bando, más
la infantería de las guarniciones; munición sin límite; pasos de 1/30 s;
corte a los 900 s. Corrido el 2026-10-03 con la etiqueta.

### 11.1 Resultado por semilla

| Semilla | Fin | Gana | Tanques en pie a los 60 / 300 / 600 s (A/D) | Soldados en pie a los 60 s (A/D) | Bajas A (m/h) | Bajas D (m/h) | Cañonazos / ráfagas / misiles | Huella |
|---|---|---|---|---|---|---|---|---|
| 42 | > 900 s | — | 28/29 · 13/14 · 6/4 | 48 / 51 | 93/151 | 46/58 | 0 / 0 / 2315 | 2138962852 (igual en 2 procesos) |
| 7 | 708,1 s (`alcance`) | atacante | 30/27 · 19/5 · 7/1 | 78 / 97 | 85/119 | 108/153 | 425 / 4 / 1957 | 1803917258 |
| 123 | 552,8 s (`fuera`) | atacante | 27/21 · 9/1 · — | 63 / 50 | 75/131 | 56/64 | 744 / 0 / 1406 | 780454452 |
| 1234 | 650,1 s (`fuera`) | atacante | 22/13 · 7/1 · 4/0 | 35 / 33 | 104/89 | 62/51 | 445 / 28 / 1487 | 330044791 |

- **PA-FIN-05 no coincide** con las cifras de Andrés (DANO-REAL §10.5, del
  2026-10-01): a los 300 s él da 15/21 · 13/10 · 6/2 y hoy salen 13/14 ·
  19/5 · 7/1. Después de ese día cambiaron el camión de 4 misiles y la
  rampa (2026-10-02). **La referencia para UE son las cifras de hoy**, en
  media de 10 semillas.
- **Patrón que UE debe reproducir** (en las cuatro semillas):
  - el atacante casi no avanza (14–112 m en toda la batalla) y se queda a
    1,45–1,67 km del enemigo;
  - los misiles deciden: de 1406 a 2315 salidas frente a 0–744 cañonazos;
  - la infantería casi no dispara (0–28 ráfagas por batalla) y cae pronto:
    a los 60 s queda en pie, del atacante / defensor, el 20/49 % (42),
    39/86 % (7), 31/42 % (123) y 17/13 % (1234) de los soldados que
    entraron (245/104, 199/113, 206/120 y 208/261);
  - al final, de 24 a 30 tanques por bando fuera de combate, ninguno
    destruido.
- **Tiempo de `Tropas:actualizar`** (2,9–6,0 ms de media por paso del arnés
  de 1/30 s, 11–45 ms en el 1 % peor): **contaminado**, porque corrían 3 o 4
  procesos de LÖVE a la vez. PA-DET-04 se mide en solitario antes de B2.

### 11.2 Batalla de la simulación (PA-FIN-04)

`batalla/pruebas_economia/ejecutar.py <carpeta> 42`: 60 tanques, 8
lanzacohetes y 400 soldados contra 25, 6 y 300, con la munición que llevan.

| | Andrés (DANO-REAL §10.5) | Hoy |
|---|---|---|
| Duración y final | 311 s, el atacante se retira sin munición | 322 s, el atacante se retira (`municion`) |
| Soldados del atacante (m/h/sanos) | 188 / 212 / 0 | 175 / 225 / 0 |
| Soldados del defensor | 10 / 19 / 271 | **49 / 63 / 188** |
| Tanques averiados (A, D) | 34 de 60, 7 de 25 | 33 de 60, **3 de 25** |
| Munición del atacante (balas / obuses / misiles) | 340 / 45 / 4 | 855 / 45 / 4 |
| Munición del defensor | 2935 / 78 / 88 | 2830 / 72 / 96 |
| Comprobaciones | 12 722, 0 fallos | 13 196, 0 fallos |

Las bajas del defensor son 4–5 veces las de Andrés. En la línea de PA-FIN-04
de `referencia-batalla.md` pone «Defensor: 34/60 y 7/25 tanques
averiados»: 34/60 es del atacante.

### 11.3 Infantería sola

`UNIDADES=0 batalla/pruebas_soldados_batalla/ejecutar.py <carpeta> bajas
600` (semilla 42, solo la infantería de las guarniciones):

- 41 escuadras contra 35; nadie tiene blanco hasta los 300 s;
- a los 600 s no ha terminado: el bando 1 pierde 4 figuras, gasta 14 520
  balas, y el bando 2 no pierde ninguna y gasta 0 balas (ver H3).

## 12. Hallazgos de hoy

- **H1. PA-ORD-05 FALLA en LÖVE con la semilla 42** (`pruebas_control`,
  dos veces).
  - Salida: `ATACAR tirador t72b a 6741 px de un tanque; orden atacar,
    visible false, blanco false; …` y `FALLA el tanque le dispara a su
    blanco` (`batalla/pruebas_control/main.lua:485`).
  - Reproducir: `python3 batalla/pruebas_control/ejecutar.py <carpeta> 42`
    desde `NationsRTS/`. Con 7 y 123, pasa.
  - Bisección con copias (`git archive`): pasa en `2bebce6` y falla desde
    `e6c97f0` («camión de 4 misiles exportado del .blend aprobado»). Los dos
    commits de en medio (`545867f`, `6a226a4`) no arrancan solos (`ERROR
    mundo/modelos3d.lua:119: attempt to call local 'cargador' (a nil
    value)`, falta el modelo que llega en `e6c97f0`). Lo más probable es que
    el camión nuevo cambie la formación y el tanque elegido quede sin vista;
    no es un cambio de la lógica de atacar. Causa sin confirmar.
  - **[Decisión del dueño, 2026-10-03]:** se corrige en UE (el tanque
    busca línea de vista). En LÖVE queda como fallo conocido, sin arreglar:
    el repositorio LÖVE está congelado.
- **H2. En la semilla 42 los tanques no disparan en 900 s** (0 cañonazos)
  con el enemigo a 1,45 km, dentro de su alcance de 2,1 km. Ya estaba en
  DANO-REAL §9.2. Es la misma falta de vista de H1 a mayor escala.
- **H3. Munición de la infantería sin contar** (`pruebas_soldados_batalla`,
  §11.3): el bando 2 causa 4 bajas y su munición gastada es 0. Lo probable
  es que las escuadras de la guarnición del defensor no tengan `fuente` y
  `Tropas:gastar` (`tropas.lua:1155`) no apunte lo que gastan; también
  explicaría «0 balas» del defensor en `pruebas_dano`. **NO COMPROBADO**: no
  lo seguí en el código. Afecta a cómo se compara el gasto de munición en
  UE.
- **Arneses que no corrieron hoy:** `pruebas_orugas`,
  `pruebas_camion_misiles`, `pruebas_cabina`, `pruebas_casco`,
  `pruebas_efectos` y `pruebas_soldado`. Sus pruebas quedan NO COMPROBADO.
- **Arneses aislados de INF, TAN y LAN** (también MOV-05 y DAN): no se
  escriben en LÖVE; van directos a UE como Automation. Los valores
  esperados salen de las cifras analíticas de Andrés (LuaJIT sobre los
  módulos puros de la etiqueta) y de las medidas estadísticas de este
  documento.

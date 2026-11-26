# Notas técnicas del 3D de Nations RTS

Referencia sobre cómo está montado hoy el 3D del juego (formatos, escala, la
escena de batalla) y las decisiones del dueño que le afectan. Es información,
no un reglamento: el código manda sobre cómo funciona hoy y el dueño decide
todo lo demás. La idea general del juego está en `VISION.md`.

---

## 1. Qué es 3D y qué no

| Parte | 2D o 3D | Notas |
|---|---|---|
| Mapa del mundo (`mundo/`) | **2D isométrico** | Terreno, capitales, territorio, campamentos. Los ejércitos serán **una ficha (estandarte)** por ejército, sin vehículos. Decisión del dueño: el mapa no lleva 3D. |
| Escena de batalla (`batalla/`) | **3D low-poly** | Se genera al entrar en un combate, a partir del sitio real del mapa y con las unidades reales de cada bando. |
| Vehículos (`assets/modelos3d/`) | **3D** | Mallas low-poly exportadas desde Blender. Se usan en la batalla. |

`mundo/modelos3d.lua` también dibuja tanques 3D **en el mapa** con F4 o
`--3d`. Fue una prueba y se va a retirar cuando lleguen las fichas de
ejército. Las funciones que
usa la batalla: `cargarModelo`, `formato`, `postura`, `matricesTanque` y `boca`.

## 2. Escala y coordenadas

- **1 px del juego = 10 cm.** Todo en px: posiciones, alturas y distancias.
  Un tanque mide unos 94 × 36 px.
- **Coordenadas del mundo = las de la simulación.** `x` y `y` son las del
  mapa (`y` crece hacia el "sur" del mapa) y `z` sube. `terreno:altura(x, y)`
  es la altura del suelo en px. **La altura de la batalla es esa**, no una
  inventada: la escena tiene que corresponder con el mapa.
- **Ángulos:** rumbo 0 = +x, en radianes, con el mismo sentido que
  `math.atan2(dy, dx)` en coordenadas del mundo.
- Un modelo **mira a +x** en su espacio local.

## 3. Formato de modelo 3D (`assets/modelos3d/*.lua`)

Lo genera `tools/blender/exportar_lua3d.py`. Se regeneran con el exportador, así que un cambio a mano se pierde.

```lua
-- Generado por tools/blender/exportar_lua3d.py: no editar a mano.
return {
    boca = { 74.0, 0.0, 20.5 },        -- (tanque) boca del cañón, en coords de la pieza 'canon'
    elevacion = 35,                    -- (lanzacohetes) grados máximos del contenedor
    bocas = { { 42.88, 3.2, 3.2 }, ... },  -- (lanzacohetes) bocas, en coords de 'contenedor'
    piezas = {
        { nombre = 'casco', padre = nil, pivote = { 0, 0, 0 }, vertices = { ... } },
        { nombre = 'torreta', padre = 'casco', pivote = { px, py, pz }, vertices = { ... } },
        ...
    },
}
```

- **`vertices`:** lista plana de triángulos, 3 vértices seguidos por
  triángulo. Cada vértice es `{ x, y, z, nx, ny, nz, r, g, b, nacion }`:
  - posición en px **relativa al pivote de su pieza**;
  - normal de cara (sombreado plano low-poly);
  - color **sRGB** 0-1;
  - `nacion` = 1 donde el juego pinta el **color de la nación dueña** (una
    franja; nunca el vehículo entero).
- **`pivote`:** en coordenadas de la pieza padre. La torreta gira sobre la z
  de su pivote y el cañón retrocede por su x.
- **Contenedor del lanzacohetes:** con `Ry(a)` estándar sobre coordenadas del
  juego, el frente sube con `a = -elevacion`.
- **Caras:** antihorarias vistas desde fuera, en coordenadas del juego.
- **Tamaño:** menos de ~3000 triángulos por vehículo (cilindros a 12 lados).
  En una batalla puede haber 80 o más vehículos.

**Modelos que hay:**
- `tanque_a.lua`: casco, torreta y canon.
- `lanzacohetes.lua`: chasis y contenedor.

**Añadir un vehículo nuevo:**
1. Modelarlo en Blender con Python, en `tools/blender/`, siguiendo
   `tanques_militares.py` y `modelos_militares.py`: vacíos por pieza móvil y
   el material `Nacion` (`M.material_nacion()`) para la franja.
2. Añadirlo a la tabla `MODELOS` de `exportar_lua3d.py`.
3. Exportar con
   `blender -b --python tools/blender/exportar_lua3d.py -- NationsRTS/assets/modelos3d <nombre>`.
4. Comprobar que el archivo carga con `luajit` y que las normales coinciden
   con el orden de los vértices.

**Lo que viene: piezas intercambiables.** El sistema de diseño de armamento
(`diseno/diseno-de-armamento.md`) hará que cada vehículo sea una
**combinación de piezas** (casco, torreta, cañón, extras) que eligen las
naciones. Diseña pensando en eso: una pieza tiene que poder ir sobre otro
casco por un **punto de montaje**. Si propones el campo `montaje` en el
formato, déjalo como propuesta; no rompas el formato actual.

## 4. La escena de batalla (`batalla/`)

| Archivo | Qué hace |
|---|---|
| `escena.lua` | Busca combates en el mapa (`Escena.buscarCombate`, `Escena.combateDeGrupo`), crea la escena (`Escena.nueva(mundo, combate)`), bucle, dibujo, rótulo y entrada (Esc → `'salir'`). |
| `suelo.lua` | Terreno 3D del sitio real (`terreno:altura`, colores del mapa), agua, plantas 3D en las posiciones reales de la vegetación del mapa (`Plantas.enTrozo`) y el edificio atacado. |
| `tropas.lua` | Vehículos de cada bando: formación, disparos, misiles, partículas, impactos y destrucción. |
| `dano/` | Daño real (`DANO-REAL.md`): balística de cada proyectil, cuerpos y rejilla, blindaje y averías por zonas, explosiones y metralla. La pelea avanza en pasos fijos de 1/60 s. |
| `camara.lua` | Cámara en perspectiva: girar, inclinar, acercar y desplazar. |
| `sombreado.lua` | El shader: luz del sol más ambiente y niebla lineal. |
| `malla.lua` | Constructor de mallas estáticas: triángulos, cajas, prismas e icosaedros. |
| `matriz.lua` | Matrices 4×4: colocar, cabecear, perspectiva, mirar y aplicar. |

`main.lua` abre la escena con la tecla B, con clic en la barra de vida de un
grupo que pelea, o con `--batalla` en modo captura. Mientras está abierta,
llama a `batalla:actualizar(dt)` y `batalla:dibujar()` en vez del mapa.

### 4.1 Entrada: la tabla `combate` (contrato)

Es **lo único** que la escena recibe del juego, más `mundo` para consultar
terreno y plantas. Hoy la arma `Escena.combateDeGrupo`:

```lua
combate = {
    grupo = id,                 -- grupo atacante (hoy; mañana, el ejército)
    cx = x, cy = y,             -- centro de la batalla en coords del mundo (px)
    angulo = rumbo,             -- dirección del ataque (atacante → defensor)
    atacante = { nombre, color = {r,g,b}, tanques, lanzacohetes, soldados, fuerza },
    defensor = { nombre, color = {r,g,b}, tanques, lanzacohetes, soldados, fuerza },
    sitio = { tipo = 'ciudad'|'base'|'campamento'|..., x, y, z, color },  -- lo atacado
}
```

- **Cuando lleguen los ejércitos con líder** (`diseno/ejercitos-en-el-mapa.md`,
  en preparación), cada bando traerá su **lista de unidades con su diseño**
  además de los números, así que conviene que un bando pueda ser "N unidades,
  cada una con su modelo y sus estadísticas", no solo dos números fijos.
- La escena no lee ni escribe `mundo.sim.estado` directamente, salvo lo que ya
  hace `escena.lua` para armar `combate`; los datos que necesita van en esa
  tabla.

### 4.2 Salida: el resultado de la batalla (por construir)

El dueño decidió que **en su batalla el jugador manda y eso cambia el
resultado**. Mientras el jugador pelea, el mundo sigue más lento. Hoy la
escena es solo visual: las bajas se limitan según la `fuerza` de cada bando.

Como la simulación es determinista y viaja por la red, el resultado vuelve a
ella como una acción, sin tocar el estado directamente. Forma propuesta:

```lua
mundo.sim:ejecutar({
    tipo = 'resultadoBatalla',   -- nombre propuesto, aún no existe en la simulación
    grupo = combate.grupo,
    bajas = { atacante = { tanques = n, lanzacohetes = n, ... },
              defensor = { tanques = n, lanzacohetes = n, ... } },
    ganador = 'atacante' | 'defensor' | 'retirada',
})
```

La idea es que la escena produzca esa tabla al acabar la pelea
(`Escena:resultado()`) y que `simulacion.lua` tenga la acción que la aplica.

## 5. Notas técnicas

- **Motor:** LÖVE 11.5 con LuaJIT. La ventana tiene `t.window.depth = 24`.
- **Dibujo de la batalla:** 3DreamEngine, elegido por el dueño el 2026-09-26
  tras la comparación de `batalla/dream/README.md`.
  - Está en `lib/3DreamEngine/`, con las extensiones de su `extenciones.zip`:
    sky, physics, raytrace, sound y utils.
  - El dueño pidió que se aprovechen las extensiones.
- **Librerías externas:** permitidas si tienen licencia libre, van copiadas
  en `lib/` y no se usan dentro de la simulación. La simulación tiene que ser
  determinista y correr en un servidor sin LÖVE.
- **Rendimiento de referencia:** generar la batalla tarda hoy entre 1,6 y 2 s.
  Con 40 contra 40 vehículos, el objetivo es ir fluido, por encima de 60 FPS.
  el dueño prefiere optimizar antes que quitar unidades o recortar lo que pasa
  en la batalla.
- **Azar visual:** la escena usa su propio hash, así que dos capturas
  iguales dan lo mismo.
- **Capturas sin ventana:**
  `SDL_VIDEODRIVER=offscreen love NationsRTS 42 --dream --captura 3000 f.png 0 0 0.3 1 --batalla normal 400 [tanques lanzacohetes]`.
  La foto sale en `~/.local/share/love/nationsrts/`.
- **Probar en vivo:** `love . 42 --batalla-vivo 32 8 --dream`, desde
  `NationsRTS`.

### 5.1 Cómo se dibuja todo lo nuevo (decisión del dueño, 2026-11-19)

Todo lo que se cree para el juego (robots, vehículos, muebles, cajas,
edificios, en cualquier escena) se dibuja con pocas llamadas, como lo que ya
está así. Medido el 19-nov: el almacén pasó de 50-60 a ~120 FPS y de ~5 500 a
~580 llamadas de dibujo; la batalla, de 2 148 a 325.

- **Lo que se mueve por piezas** (robots y vehículos con `robots/nucleo.lua`):
  se funde solo con `robots/union.lua`, una malla por material y un hueso
  rígido por pieza. Las piezas se siguen moviendo y ocultando desde Lua como
  siempre. Para que se pueda fundir: mallas sin hijos dentro de cada pieza,
  menos de 256 piezas, y lo que cambie el material de un robot (brillos,
  siglas, colores) hecho en `onLoad`, antes del primer dibujo. Los materiales
  se agrupan por nombre: dos piezas con el mismo nombre de material se ven
  igual. `ROBOTS_UNIDOS=0` dibuja pieza a pieza, para comparar.
- **Muchas copias del mismo modelo** (cajas, estanterías, mesas, carteles,
  misiles...): `batalla/dream/lote_copias.lua`, una llamada por malla para
  todas las copias. Se le pasa el modelo de origen guardado antes de clonar:
  `object:clone()` de 3Dream cambia las piezas del modelo que se clona
  (`lib/3DreamEngine/ORIGEN.md`). Ejemplo: `almacen/objetos/objetos.lua`.
- **Lo fijo de una escena** (nave, muros, suelos): unido en pocas mallas al
  exportar desde Blender (`tools/blender/almacen_interior.py`, `unir`).
- **Comprobarlo:** `ALMACEN_FPS=1` (almacén) y `BATALLA_ROBOTS_MEDIR=<s>`
  (batalla) dan las llamadas de dibujo; con lo nuevo puesto, que no suban
  mucho.

## 6. Decisiones del dueño sobre la batalla

- **Terreno:**
  - imita el mapa 2D del sitio donde chocan los ejércitos;
  - todo procedural (los únicos modelos hechos a mano son los vehículos);
  - estilo del paisaje de `tools/blender/paisaje_lowpoly.py`;
  - la receta con números está en `batalla/ESTILO-TERRENO.md`.
- **Luz y cielo:** luz de media mañana, sin nubes por ahora, sin LUT y sin
  cultivos.
- **Agua y paso:**
  - ríos solo en la batalla;
  - ríos y lagos no transitables, se cruzan solo por puentes (al menos uno
    por río, de 16 m y dos carriles);
  - caminos de tierra y puentes de madera como en el paisaje de Blender;
  - pasillos despejados y con poca pendiente para cruzar de un bando al otro.
- **Colisiones:**
  - montañas y árboles frenan balas y misiles;
  - los tanques derriban árboles jóvenes y arbustos, y los grandes los frenan.
- **Mapa y cámara:**
  - un límite alrededor del campo, con llanura hasta el horizonte y sin techo
    para los misiles;
  - la cámara es suave y se mueve con WASD hacia donde mira.
- **Mando y resultado:** en su batalla el jugador manda y eso cambia el
  resultado (sección 4.2). El mundo sigue más lento mientras tanto.

## 7. Estado a 2026-09-27 (lo que hay en el código)

- **Terreno** (`suelo.lua`, `rejilla.lua`, `color_terreno.lua`,
  `colocacion.lua`, `vegetacion.lua`, `pasillos.lua`, `agua.lua`,
  `impactos.lua`, `derribo.lua`, `limite.lua`, `dream/luz.lua`):
  - relieve suave;
  - color por zona con detalle procedural;
  - 11 especies de planta generadas en código;
  - pasillos;
  - mar y ensenadas no transitables;
  - impactos contra terreno y árboles;
  - derribo de árboles;
  - límite con faldón;
  - luz de media mañana.
- **Consultas útiles del suelo:**
  - `Suelo:transitable(x, y)`, `Suelo:pendiente(x, y)` y
    `Suelo:altura(x, y)`;
  - `suelo.pasillos`, `suelo.limite` (`dentro`, `ajustar`, `margen`) y
    `suelo.agua`;
  - `Impactos.rayo(...)` e `Impactos.visible(...)`.
- **Cámara:** `camara.lua` más `controlador_camara.lua`, con inercia, altura
  suavizada y WASD relativo.
- **Aún no existe:**
  - ríos propios, lagos propios, puentes y caminos;
  - viento;
  - unidades que usen los pasillos o busquen los puentes;
  - el recorte con `transitable` en el movimiento sin física de
    `tropas.lua`;
  - `Escena:resultado()`;
  - marcadores a distancia;
  - sombras propias de los vehículos.
- **Fallo conocido:** con soldados, `--dream` se cae porque el material
  `MaderaFusil` no tiene UV (`lib/3DreamEngine/classes/mesh.lua:313`).

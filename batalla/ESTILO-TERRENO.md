# Estilo del terreno de la batalla (para Codex)

Escrito por Camila (artista técnica) el 2026-09-27. Es la traducción a Lua
procedural del paisaje de `tools/blender/paisaje_lowpoly.py`, que el dueño quiere
como referencia de estilo de la batalla 3D.

**Regla del dueño, textual:** "recuerda que esto es procedural por lo que no
podemos meter los modelos ahí; los únicos modelos que usamos creados son los de
los vehículos".

Por eso aquí no hay ningún modelo exportado:

- el terreno, los árboles, los arbustos, la hierba, las flores, las rocas, el
  agua y las cañas se **generan en código Lua** al entrar en la batalla;
- todo sale de la semilla del mundo y del sitio del mapa (`terreno:altura`,
  `terreno:humedadEn`, `terreno:bioma` y `Plantas.enTrozo`);
- los únicos modelos hechos a mano son los vehículos (`assets/modelos3d/`).

## Decisiones del dueño (2026-09-27), mandan sobre el resto del documento

- **REGLA PRINCIPAL: la batalla imita el terreno del mapa 2D donde se
  encontraron los ejércitos.**
  - El relieve, las montañas, los lagos y el mar son los de ese punto exacto
    del mapa (`terreno:altura`, `terreno:bioma`, `terreno:humedadEn`), a escala
    real.
  - Los árboles del mapa están en su sitio exacto (`Plantas.enTrozo`).
  - Si en el mapa 2D chocan junto a un lago, entre dos montañas o en un bosque
    de pinos, la batalla muestra ese mismo lago, esas montañas y ese bosque.
  - El bioma del mapa manda sobre la vegetación: pinos en un bosque de pinos,
    cactus y rocas en zona árida, nieve en lo alto.
  - Este documento solo añade detalle y estilo encima del terreno del mapa:
    color, rocas, relleno de plantas, ríos y viento. **Nunca inventa un
    terreno distinto** ni lo cambia por otro "más bonito".
- **Luz de media mañana,** como el paisaje de Blender: día claro, cielo azul y
  sombras suaves. No la de atardecer que menciona `GUIA-3D.md`.
- **Sin nubes por ahora:** ni low-poly ni las de la extensión sky. Cielo en
  degradado sin nubes.
- **Sin tabla de color (LUT):** el color se queda como lo da 3DreamEngine, sin
  imitar el look AgX de Blender.
- **Sin campos de cultivo,** tampoco cerca de las ciudades: solo naturaleza
  (pradera, bosques, rocas y agua).
- **Ríos y lagos NO son transitables:** ningún vehículo entra en el agua.
  Solo se cruza por los **puentes**. Cada río que corte el área de batalla
  lleva al menos un puente, puesto por los caminos de §6.5, para que los
  bandos siempre puedan llegar uno al otro. Los lagos se rodean.
- **Caminos y puentes como en el paisaje de Blender** (§6.5): caminos de tierra
  con rodadas que siguen el relieve y puentes de madera donde cruzan los ríos.

Los números vienen del script; donde cito una función o constante del script
(`proto_pino`, `colores_terreno`, `VIENTO`...), busca ese nombre en
`paisaje_lowpoly.py` para ver el original.

---

## 0. Unidades y convenciones

- **El script trabaja en metros. El juego, en px: 1 m = 10 px.** En este
  documento todo está en **metros** salvo que diga px. Al programar, multiplica
  por `M = 10`.
- Ejes del juego: `x`, `y` en el plano del mapa y `z` hacia arriba (Blender
  también usa z arriba). 3DreamEngine usa y arriba: eso ya lo resuelve
  `batalla/dream/conversor.lua` (1 unidad de Dream = 100 px = 10 m).
- **Colores en sRGB 0-1**, como en `batalla/malla.lua`. El conversor los pasa a
  lineal con `^ 2.2`. Los **tonos por copia** (`tono`) y el **viento** van en el
  shader, sobre color lineal: ahí los multiplicadores se aplican tal cual.
- `suave(a, b, x)` es el smoothstep del script (vale también con `a > b`, y
  entonces baja):

```lua
--- Smoothstep de `a` a `b` (si a > b, va de 1 a 0).
function suave(a, b, x)
    local t = (x - a) / (b - a)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

--- Mezcla lineal de dos colores.
function mezcla(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end
```

- **Azar determinista:** nunca `math.random`. Usa `Ruido.hash(semilla, a, b, c)`
  con enteros (`math.floor` de las coordenadas en px o del índice de celda) y
  `Ruido.azar(semilla)` para una secuencia. Cada capa lleva su propia sal (el
  cuarto argumento) para que no se correlacionen. Dos entradas en la misma
  batalla tienen que dar exactamente lo mismo.
- **Ruidos del estilo.** El script usa `noise.noise` de Blender (Perlin, más o
  menos en [-1, 1]); aquí se usa `Ruido:simplex` del juego, que da un rango
  parecido. Crea un `Ruido.nuevo` por capa, con la semilla del mundo más una sal
  fija:

| Nombre | Escala (m) | Llamada en px | Uso |
|---|---|---|---|
| `n1` | 20 | `r1:simplex(x / 200, y / 200)` | pradera A/B, arena o tierra en la orilla, roca |
| `n2` | 60 | `r2:simplex(x / 600, y / 600)` | manchas de hierba seca |
| `fino` | 5 | `r3:simplex(x / 50, y / 50)` | variación por cara, granulado de roca |
| `borde` | 30 | `r4:simplex(x / 300, y / 300)` | borde irregular de los bosques |
| `claros` | 70 | `r5:simplex(x / 700, y / 700)` | claros dentro del bosque |
| `canas` | 18 | `r6:simplex(x / 180, y / 180)` | cañas o piedras en la orilla |

Sales propuestas: `semilla + 27101` para `r1` y luego +1 para cada capa
siguiente. Da igual cuáles sean; lo que importa es que sean fijas.

---

## 1. Relieve: de posiciones fijas a reglas

La escena de Blender tenía cada cosa en una coordenada fija. En el juego el
relieve es el del sitio, `Suelo:altura(x, y)` (terreno real suavizado, más
explanadas y detalle). Todo lo que sigue son **reglas** que se evalúan en
cualquier sitio. Cantidades que se calculan una vez por vértice de la rejilla
del terreno y se guardan en arrays FFI (no por planta):

| Cantidad | Definición |
|---|---|
| `pendiente` | `1 - nz`, con `nz` la componente z de la **normal de la cara** (px en los tres ejes, así que no hace falta convertir) |
| `zRel` (m) | `(h - hRef) / 10`, con `hRef` = percentil 20 de las alturas sobre el mar de toda la rejilla. Es "el fondo del valle" del sitio: hace de `z` del script, donde el valle estaba a 0 m |
| `curvatura` (m) | `(h - media(h en x ± 20 m, y ± 20 m)) / 10`. Positiva en crestas y negativa en vaguadas |
| `solana` | `max(0, nx * sx + ny * sy)`, con `(sx, sy)` la dirección horizontal hacia el sol, normalizada (sección 8) |
| `dAgua` (m) | distancia al borde del agua más cercano (río, lago o mar), sacada del campo de distancias del agua (sección 6) |
| `nivelAgua` | nivel del agua más cercana |
| `humedad` | `terreno:humedadEn(x, y)`, la del mapa |
| `bosque` | máscara 0-1 (abajo) |

**Máscara de bosque** (sustituye a `bosque_v`, que usaba círculos fijos y un
anillo). Sale de la humedad del mapa, para que los bosques de la batalla caigan
donde el mapa pinta bosque (`terreno:bioma` da 'bosque' con humedad > 0,2):

```lua
local b = suave(0.12, 0.3, humedad + 0.12 * borde)
-- Bosquetes sueltos en la pradera, de unos 40-80 m.
b = math.max(b, suave(0.62, 0.8, claros) * suave(-0.35, 0.0, humedad))
-- Claros dentro del bosque.
b = b * suave(-0.75, -0.45, claros)
-- En la hierba seca y en lo empinado no hay bosque denso.
b = b * (1 - suave(0.28, 0.4, pendiente))
bosque = b
```

**Qué pasa con cada pieza del script:**

| En el script | En la batalla |
|---|---|
| `LOMAS` (lomas en posiciones fijas) | **No aplica.** Las lomas son las del mapa: `terreno:altura` |
| `ESCARPE` (ladera marcada) | **No aplica como posición.** Su efecto visual es "roca en lo empinado" y "afloramientos en la cresta": regla de `pendiente` y `curvatura` |
| Anillo de colinas del borde | **No aplica.** El borde se funde con la niebla (sección 8) |
| `RIO_PUNTOS`, `LAGO` | **Regla nueva:** hidrología del terreno del sitio (sección 6) |
| `CAMINOS` y puentes | **Regla nueva:** se trazan en cada batalla por el terreno más llano del sitio, con la misma sección, colores y puentes del script (§6.5) |
| `CAMPOS` y surcos | **No aplica** (decisión del dueño: sin cultivos) |
| `BOSQUES` (círculos) | Regla: máscara `bosque` de arriba |
| `FLORES` (manchas fijas) | Regla: las plantas 'flores' del mapa son centros de mancha (sección 4) |
| `AFLORAMIENTOS` (fijos) | Regla: crestas por `curvatura` más las 'roca' del mapa (sección 4) |
| Cámara `tapa_camara`, `cerca_camara` | **No aplica.** La cámara del juego se mueve; en su lugar, LOD (sección 5) |
| Nubes | Opcional (sección 8) |

**Explanadas:** donde `Suelo:aplicarExplanadas` tiene peso > 0,5 no se pone
nada que estorbe a una formación: ni árboles, ni arbustos, ni rocas de escala
> 0,8. Sí hierba, flores y el color del suelo. Si esto choca con la
correspondencia con el mapa, avisa al dueño.

---

## 2. Paleta y color por cara

### 2.1 Paleta del terreno (sRGB, exacta del script)

```lua
local C_PRADO_A = { 0.33, 0.5, 0.17 }
local C_PRADO_B = { 0.46, 0.58, 0.22 }
local C_SECA = { 0.68, 0.62, 0.33 }
local C_TIERRA = { 0.47, 0.36, 0.23 }
local C_ARENA = { 0.76, 0.69, 0.5 }
local C_ROCA = { 0.55, 0.53, 0.5 }
local C_ROCA_OSC = { 0.42, 0.41, 0.4 }
local C_BOSQUE = { 0.2, 0.33, 0.12 }
local C_FONDO = { 0.26, 0.3, 0.2 }
-- Solo para respetar el mapa (el script no tiene nieve):
local C_NIEVE = { 0.95, 0.95, 0.97 } -- Terreno.colores.nieve
```

Colores de flor (también tiñen el suelo de su mancha):

```lua
local COLORES_FLOR = {
    { 0.85, 0.14, 0.1 }, -- roja
    { 0.96, 0.8, 0.16 }, -- amarilla
    { 0.96, 0.95, 0.9 }, -- blanca
    { 0.6, 0.38, 0.8 }, -- violeta
}
```

### 2.2 Rejilla y sombreado plano

- **Un color por cara, calculado en el centroide del triángulo.** Hoy
  `generarTerreno` pone un color por vértice (`trianguloColores`) y lo
  interpola: eso da degradados, y el estilo son facetas. Usa
  `malla:triangulo(..., color)`.
- **Sombreado plano:** la normal es la de la cara, no la suavizada que se
  calcula hoy en `normales[j][i]`. Con `malla:triangulo` ya sale así.
- **Diagonal alterna** como tablero (ya lo hace; el script también:
  `(i + j) % 2`).
- **Vértices desplazados:** cada vértice interior se mueve en x e y
  `U(-0.3, 0.3) * paso` (el script: `jit = NRNG.uniform(-0.3, 0.3) * PASO`),
  con `paso` el paso local de la rejilla en ese eje. El azar sale de
  `Ruido.hash(semilla, i, j, 31)` con `i` y `j` índices globales de la línea
  de rejilla. La primera y la última fila y columna no se mueven. La altura se
  toma **después** de mover el vértice. Así las caras no forman rayas regulares.
- **Tamaño:** el script usa 2 m en 540 x 420 m. En 3 x 3 km no cabe. Se queda la
  rejilla actual: 4 m (40 px) en el centro, que engorda hasta 28 m en el
  borde, unos 410 000 triángulos. **No la hagas más fina.** A 4 m las facetas
  se leen igual que las de 2 m vistas desde la cámara de batalla.

### 2.3 Fórmula del color de cada cara (`colores_terreno` traducida)

Lo que en el script dependía de los campos se ha quitado; el color de los caminos va en su propia malla (§6.5). `n1`, `n2` y
`fino` son los ruidos de la sección 0, evaluados en el centroide. Todas las
distancias en metros.

```lua
--- Color sRGB de una cara del terreno con su centroide (x, y, h) y su normal.
function Suelo:colorCara(x, y, h, nx, ny, nz)
    local pendiente = 1 - nz
    local zRel = (h - self.hRef) / 10
    local n1 = self.r1:simplex(x / 200, y / 200)
    local n2 = self.r2:simplex(x / 600, y / 600)
    local fino = self.r3:simplex(x / 50, y / 50)
    local humedad = self.terreno:humedadEn(x, y) -- o interpolada de la rejilla
    local bosque = self:mascaraBosque(x, y) -- sección 1
    local solana = math.max(0, nx * self.solX + ny * self.solY)
    local dAgua, nivelAgua = self:agua(x, y) -- sección 6, en m

    -- 1. Pradera: dos verdes mezclados por el ruido grande.
    local c = mezcla(C_PRADO_A, C_PRADO_B, 0.5 + 0.5 * n1)

    -- 2. Hierba seca: manchas, altura y laderas al sol.
    local seca = suave(0.05, 0.45, n2) * 0.6
    seca = seca + suave(10, 28, zRel) * 0.35
    seca = seca + solana * 1.2 * suave(0.06, 0.2, pendiente)
    -- Añadido para respetar el bioma 'seca' del mapa (humedad < -0.25).
    seca = seca + suave(-0.1, -0.4, humedad) * 0.45
    c = mezcla(c, C_SECA, math.min(0.75, seca))

    -- 3. Suelo de bosque, más oscuro.
    c = mezcla(c, C_BOSQUE, bosque * 0.75)

    -- 4. Manchas de flores (centro fx, fy, radio fr, color fc): un 10 %.
    for _, f in ipairs(self:manchasCerca(x, y)) do
        local d = math.sqrt((x - f.x) ^ 2 + (y - f.y) ^ 2) / 10
        if d < f.r then
            c = mezcla(c, COLORES_FLOR[f.color], 0.1 * suave(f.r, f.r * 0.3, d))
        end
    end

    -- 5. Orillas: arena o tierra húmeda, al 72 %.
    local orilla = dAgua < 2.4 and h / 10 < nivelAgua / 10 + 1.0
    -- La costa del mar (bioma 'arena' del mapa, h < 12 px) cuenta como orilla.
    orilla = orilla or (h >= self.terreno.nivelMar and h < self.terreno.nivelMar + 12)
    if orilla then
        local arena = n1 > -0.15 and C_ARENA or C_TIERRA
        c = mezcla(c, arena, 0.72)
    end

    -- 6. Roca en lo empinado.
    local roca = suave(0.2, 0.34, pendiente + 0.05 * fino)
    -- Añadido para respetar el bioma 'roca' del mapa (sobre 170-240 px).
    roca = math.max(roca, suave(170, 240, h) * 0.8)
    if roca > 0 then
        local gris = mezcla(C_ROCA, C_ROCA_OSC, 0.5 + 0.5 * fino)
        c = mezcla(c, gris, roca * (0.78 + 0.22 * suave(-0.3, 0.3, n1)))
    end

    -- 7. Nieve del mapa (sobre 300 px). No está en el script: se conserva
    -- para que la batalla corresponda con el mapa.
    c = mezcla(c, C_NIEVE, suave(300, 340, h) * (1 - roca * 0.5))

    -- 8. Bajo el agua: fondo turbio, más oscuro cuanto más hondo.
    local hondo = (nivelAgua - h) / 10 -- m bajo la superficie
    if hondo > 0.05 then
        c = mezcla(C_ARENA, C_FONDO, suave(0.05, 1.2, hondo))
        local k = 1 - 0.35 * suave(0.8, 3.0, hondo)
        c = { c[1] * k, c[2] * k, c[3] * k }
    end

    -- 9. Variación por cara: +-4 %.
    local k = 0.96 + 0.04 * fino
    return { c[1] * k, c[2] * k, c[3] * k }
end
```

Notas:

- Umbrales de pendiente: 0,06-0,2 para la solana seca, 0,2-0,34 para la roca
  (unos 37° a 49°) y 0,28-0,4 para quitar el bosque. **Mídelos**: saca el
  histograma de `pendiente` de la rejilla en tres semillas. Si la roca queda en
  menos del 2 % del área en sitios de montaña, el relieve del juego es más suave
  que el del script: baja los dos umbrales de roca por igual hasta que el
  percentil 97 de la pendiente sea roca plena. Apunta los valores medidos.
- `Terreno:color` del mapa **deja de usarse** en la batalla. El bioma del mapa
  entra solo por `humedad` (seca, bosque) y por la altura (arena, roca, nieve).
- Evalúa los ruidos en la rejilla una vez (arrays FFI) y cachea
  `humedadEn` por vértice: el terreno tiene unas 410 000 caras y no hay que
  llamar a `fbm` tres veces por cara.

---

## 3. Plantas y rocas en código

### 3.1 Primitivas que hacen falta en `batalla/malla.lua`

Las del script son `Pieza.cilindro` (cono o cilindro), `Pieza.bola` (icosfera
con subdivisión 1 = **icosaedro de 20 caras**) y `Pieza.caja`. Cuidado: en el
script `pos` es el **centro** de la pieza; en `Malla:prisma` y `Malla:caja` es
la **base**. Abajo todo está ya pasado a base.

| Del script | En `malla.lua` | ¿Falta? |
|---|---|---|
| cono o tronco vertical | `prisma(x, y, z, r, rArriba, alto, lados, color, giro)` | Existe |
| cono o tronco inclinado | `prismaEntre(x0, y0, z0, x1, y1, z1, r0, r1, lados, color, giro)` | Existe (sin tapas; vale) |
| caja girada en z | `caja(...)` | Existe |
| icosaedro con escala x, y, z distinta, giro en los **tres** ejes y deformación ajustable | `icosaedro` solo tiene `radio` = `radioZ`, gira en z y deforma fijo de 0,8 a 1,15 | **Falta.** Añade `icosaedroLibre(x, y, z, ex, ey, ez, gx, gy, gz, color, deformar, azar)`: vértice unidad, multiplicado por `1 + deformar * (2 * azar() - 1) * 0.7` si `deformar > 0`; luego escala (ex, ey, ez); luego giro X, Y y Z (Euler XYZ, como Blender); luego traslación |
| color por pieza con variación | no hay | **Falta** un ayudante `variarPieza(color, azar, v)` (abajo) |
| malla en coordenadas locales para instanciar | `Malla` sirve (pasa el origen 0, 0, 0) | El conversor centra en `cx, cy`: **falta** `Conversor:desdeMallaLocal(malla, opciones)` que no reste el centro |

Variación por pieza (la de `Pieza._pintar`): cada primitiva tiene su tono.

```lua
--- Color de una pieza: brillo U(1 - v, 1 + v) y +-3 % por canal.
function variarPieza(color, azar, v)
    local valor = azar(1 - v, 1 + v)
    return {
        color[1] * valor * azar(0.97, 1.03),
        color[2] * valor * azar(0.97, 1.03),
        color[3] * valor * azar(0.97, 1.03),
    }
end
```

(En Blender ese factor multiplica el color lineal; en sRGB equivale a
`valor ^ (1 / 2.2)`. La diferencia no se ve; usa el valor tal cual.)

### 3.2 Paleta de la vegetación (sRGB)

```lua
local PALETA = {
    tronco = { 0.4, 0.28, 0.18 },
    troncoPino = { 0.5, 0.3, 0.2 },
    cortezaAbedul = { 0.88, 0.86, 0.8 },
    marcaAbedul = { 0.12, 0.11, 0.1 },
    pino = { 0.2, 0.36, 0.2 },
    abeto = { 0.12, 0.29, 0.21 },
    roble = { 0.3, 0.47, 0.16 },
    alamo = { 0.46, 0.6, 0.22 },
    abedul = { 0.53, 0.66, 0.26 },
    arbusto = { 0.26, 0.43, 0.16 },
    hierba = { 0.42, 0.56, 0.2 },
    hierbaSeca = { 0.68, 0.62, 0.32 },
    cana = { 0.48, 0.56, 0.24 },
    espiga = { 0.34, 0.22, 0.13 },
    roca = { 0.56, 0.54, 0.5 },
    nenufar = { 0.3, 0.48, 0.16 },
}
```

Rugosidad: 0,85-0,9 en todo (0,8 la corteza del abedul, 0,7 las flores). Un
solo material mate para toda la vegetación vale.

### 3.3 Prototipos (medidas en metros, con la base del árbol en z = 0)

`azar` es `Ruido.azar(...)` de la variante. `U(a, b)` = `azar(a, b)`. "Masa"
es un `icosaedroLibre` sin deformar. Salvo que se diga otra cosa, los ángulos
van en radianes. Los "lados" son los de la primitiva.

**Pino** (`proto_pino`; 3 variantes). Es un pino de copa en masas, no un cono.

- `alto = U(8.5, 10.5)`.
- Inclinación del tronco: giro X y giro Y `U(-0.05, 0.05)` cada uno. Con
  `prismaEntre`, la punta se desplaza `(sin(gy) * alto, -sin(gx) * alto)`.
- Tronco: 5 lados, radio 0,36 abajo y 0,18 arriba, de z = -0,4 a
  z = `alto - 0.4`. Color `troncoPino`, variación 0,08.
- De 4 a 6 masas: ángulo `U(0, 2π)`, a `U(0.4, 1.6)` del eje, centro en
  z = `alto - 1.4 + U(-1.6, 0.8)`, radio `R = U(1.5, 2.2)`, escala
  `(1.15R, 1.15R, 0.62R)`, giro Z `U(0, 3)`. Color `pino`, variación 0,1.
- Cima: masa en (0, 0, `alto + 0.2`), R = 1,6, escala `(1.1R, 1.1R, 0.6R)`,
  variación 0,08.
- Alto total: unos 10-12 m.

**Abeto** (`proto_abeto`; 3 variantes). Pisos de conos.

- `alto = U(10, 13)`.
- Tronco: 5 lados, radio 0,32 (cilindro), de z = -0,4 a z = 2,0. Color
  `tronco`.
- `pisos = 5` o `6` (entero U). Para `k = 0 .. pisos - 1`:
  `f = k / (pisos - 1)`, `r = 3.1 * (1 - f) + 0.9 * f`,
  `z = 1.4 + f * (alto - 3.6)`. Cono truncado de 7 lados, radio `r` abajo y
  0,12 arriba, de z = `z - 0.1` a z = `z + 3.1`, giro Z `U(0, 1)`. Color
  `abeto`, variación 0,08, y los pisos pares (k = 0, 2, 4) multiplicados por
  `(0.9, 0.93, 0.93)`: así se distinguen los pisos.
- Alto total: `alto + 0.9`.

**Roble** (`proto_roble`; 4 variantes).

- Tronco: 6 lados, radio 0,55 abajo y 0,38 arriba, de z = -0,4 a z = 3,6.
- Dos ramas: ángulo `a = U(0, 2π)`. `prismaEntre` de
  `(0.122 cos a, 0.122 sin a, 2.91)` a `(1.478 cos a, 1.478 sin a, 4.89)`,
  radios 0,22 y 0,12, 5 lados. (Es el cilindro de 2,4 m inclinado 0,6 rad
  hacia fuera, centrado en `(0.8 cos a, 0.8 sin a, 3.9)`.) Color `tronco`.
- De 5 a 7 masas: ángulo `U(0, 2π)`, a `U(0.8, 2.8)` del eje, z `U(5.2, 7.6)`,
  R `U(2.3, 3.2)`, escala `(R, R, 0.85R)`, giro X `U(0, 1)` y giro Y `U(0, 1)`.
  Color `roble`, variación 0,1.
- Alto total: unos 9-10,5 m; copa de unos 7 m de radio.

**Álamo** (`proto_alamo`; 2 variantes). Columna alta.

- Tronco: 5 lados, radio 0,36 abajo y 0,26 arriba, de z = -0,2 a z = 3,0.
- Copa: masa en (0, 0, 7,4), R = 1,9, escala `(R, R, 3.1R)` (de 1,5 a
  13,3 m de alto), giro Z `U(0, 3)`, variación 0,08.
- Dos masas más: ángulo U, a 0,9 m del eje, z `U(5.5, 8.5)`, R = 1,3, escala
  `(R, R, 2.4R)`, variación 0,1. Color `alamo`.

**Abedul** (`proto_abedul`; 3 variantes).

- `alto = U(6.5, 8)`. Inclinación del tronco: X e Y `U(-0.08, 0.08)`.
- Tronco: 5 lados, radio 0,22 abajo y 0,13 arriba, de z = -0,3 a
  z = `alto - 0.3`. Color `cortezaAbedul`, variación 0,04.
- 5 marcas: z `U(0.8, alto - 2.5)`, ángulo `a = U(0, 2π)`, caja de
  0,2 x 0,2 x 0,12 con la base en `(0.18 cos a, 0.18 sin a, z - 0.06)`, rumbo
  `a`. Color `marcaAbedul`.
- De 3 a 4 masas: ángulo U, a `U(0.3, 1.3)` del eje, z
  `alto - 1.5 + U(-1.2, 1.2)`, R `U(1.3, 1.9)`, escala `(R, R, 1.25R)`, giro
  X `U(0, 1)` y giro Z `U(0, 1)`. Color `abedul`, variación 0,1.

**Arbusto** (`proto_arbusto`; 4 variantes).

- De 2 a 4 masas: ángulo U, a `U(0, 0.8)` del eje, z `0.5 + U(0, 0.3)`, R
  `U(0.8, 1.25)`, escala `(1.1R, 1.1R, 0.8R)`, giro X y giro Y `U(0, 1)`. Color
  `arbusto`, variación 0,12.

**Mata de hierba** (`proto_mata`; 3 variantes verdes y 2 secas).

- De 7 a 11 hojas. Para cada una: ángulo `a = U(0, 2π)`, alto `U(0.5, 0.95)`,
  inclinación `i = U(0.15, 0.45)`.
- Cada hoja es un cono de **3 lados**, radio 0,09 abajo y 0 arriba, con la
  base en `(0.15 cos a, 0.15 sin a, -0.05)`, inclinado `i` rad hacia fuera (en
  la dirección `a`): la punta queda en
  `base + alto * (sin i * cos a, sin i * sin a, cos i)`. Usa `prismaEntre` con
  `r1 = 0`. Giro de las aristas `U(0, 1)`.
- Color `hierba` o `hierbaSeca`, variación 0,12.

**Flor** (`proto_flor`; 2 variantes por color, 4 colores).

- Una mata verde (`hierba`) como la de arriba.
- De 4 a 6 cabezas: ángulo U, a `U(0.05, 0.35)` del eje, z `U(0.5, 0.8)`,
  radio 0,16, color `COLORES_FLOR[i]`, variación 0,08. En el script es un
  icosaedro; aquí usa `Malla:octaedro` (8 caras): a ese tamaño no se distingue.

**Roca** (`proto_roca`; 5 variantes).

- Un `icosaedroLibre` de radio 1 centrado en z = 0, escala `(1.25, 1.0, 0.72)`,
  giro Z `U(0, 3)`, **deformar 0,28**. Color `roca`, variación 0,06.
- Media roca queda enterrada: al colocarla se hunde (sección 4).

**Cañas** (`proto_canas`; 3 variantes).

- De 9 a 14 tallos: base en `(U(-0.5, 0.5), U(-0.5, 0.5), -0.3)`, alto
  `U(1.3, 2.2)`, inclinación X e Y `U(-0.12, 0.12)`. Cono de 3 lados, radio
  0,05 abajo y 0 arriba. Color `cana`, variación 0,1.
- Con probabilidad 0,35, espiga: cilindro de 5 lados, radio 0,08, alto 0,32,
  centrado en `(x + gy * alto * 0.4, y - gx * alto * 0.4, alto * 0.72 - 0.3)`.
  Color `espiga`.

**Nenúfar** (sin prototipo en el script; va con el agua, sección 6).

- Disco: cilindro de 7 lados, radio `U(0.45, 0.85)`, alto 0,06, giro Z
  `U(0, 6)`. Color `nenufar`, variación 0,12.

### 3.4 Variantes por semilla

- Variantes por especie (las del script): Pino 3, Abeto 3, Roble 4, Álamo 2,
  Abedul 3, Arbusto 4, Mata 3, MataSeca 2, Flor 2 por color (8), Roca 5,
  Cañas 3. En total, 40 mallas.
- La variante `v` de la especie `e` usa
  `Ruido.azar(Ruido.hash(semillaMundo, e, v, 4099))`: cada mundo tiene sus
  propios árboles, y la misma batalla da siempre los mismos.
- Cada variante se construye **una vez** al entrar, en px (metros x 10), con
  origen en la base, y se pasa a Dream con `desdeMallaLocal`.
- Triángulos por variante con las primitivas de `malla.lua` (LOD 0):

| Especie | Triángulos |
|---|---|
| Pino | 115-155 |
| Abeto | 120-140 |
| Roble | 140-180 |
| Álamo | 75 |
| Abedul | 135-155 |
| Arbusto | 40-80 |
| Mata | 21-33 |
| Flor | 55-80 |
| Roca | 20 |
| Cañas | 30-55 |

- **Variantes simplificadas para el LOD** (se generan con el mismo `azar`, para
  que se parezcan):
  - **LOD 1** (unos 40-70 triángulos): tronco de 4 lados; pino y roble, 3
    masas; abedul sin marcas; abeto, 3 pisos; arbusto, 1 masa.
  - **LOD 2** (unos 8-20 triángulos): una sola masa (pino, roble, álamo y
    abedul) con la escala de la copa entera, o un cono de 6 lados (abeto). Sin
    tronco.

---

## 4. Dónde crece cada cosa

Todo con hash, en este orden, marcando lo que se pone en una rejilla de
ocupación de celdas de 4 m (`celdas[(ix, iy)]`, como `Colocador.ocupado`).
**Dos objetos chocan si `distancia < (radio1 + radio2) * 0.5`.** La altura y la
normal de cada punto se leen de la rejilla del terreno ya tallada (interpolada
en su triángulo), nunca con `terreno:altura`: es más rápido y así nada flota.

### 4.1 Colocar una copia (`Colocador.poner`)

```text
escala      según la capa (abajo)
hundir      z = suelo - hundir * escala
giro Z      U(0, 2π)
inclinación giro X y giro Y = alinear * (ángulo de la normal) + U(-inclinar, inclinar)
            (alinear 0 e inclinar 0,04 por defecto; hierba: alinear 0,7)
escala z    escala * U(0.92, 1.1)
tono        u = U(-1, 1), brillo = U(0.88, 1.1)
            tono = (brillo * (1 + 0.08u), brillo * (1 + 0.02u), brillo * (1 - 0.1u))
tono roca   b = U(0.82, 1.12), c = U(-0.05, 0.06)
            tono = (b * (1 + c), b, b * (1 - c))
roca        giro libre: X, Y y Z en U(0, 2π)
variante    hash % número de variantes
```

### 4.2 Constantes

```lua
-- Radio de ocupación de cada árbol (m): ver `Colocador.ocupado`.
local RADIO_ARBOL = { Pino = 4.0, Abeto = 5.0, Roble = 7.0, Alamo = 3.6, Abedul = 3.8 }
-- Altura de la copa (m) para colisiones de misiles y línea de visión.
local ALTO_ARBOL = { Pino = 12.0, Abeto = 13.5, Roble = 10.5, Alamo = 13.5, Abedul = 9.5 }
```

### 4.3 Especie de árbol (`especie_arbol`, con `zRel` en vez de `z`)

```lua
--- Especie de un árbol. `r` = U(0, 1) del hash del punto.
function especieArbol(r, zRel, bosque, juntoAgua, aislado)
    if juntoAgua then
        return r < 0.55 and 'Alamo' or (r < 0.75 and 'Abedul' or 'Roble')
    end
    if aislado then
        if r < 0.55 then
            return 'Roble'
        elseif r < 0.72 then
            return 'Abedul'
        elseif r < 0.9 then
            return 'Pino'
        end
        return 'Abeto'
    end
    local alto = suave(8, 26, zRel)
    if r < 0.15 + 0.4 * alto then
        return 'Abeto'
    elseif r < 0.35 + 0.45 * alto then
        return 'Pino'
    elseif bosque < 0.55 and r < 0.8 then
        return 'Abedul'
    end
    return r < 0.88 and 'Roble' or 'Abedul'
end
```

### 4.4 Capas, en orden

**0. Plantas del mapa como anclas.** Las de `Plantas.enTrozo` van primero,
en su posición exacta, para que la batalla corresponda con el mapa:

| Tipo del mapa | En la batalla |
|---|---|
| `pino` | `especieArbol` con `aislado = false` y `bosque = 1` (sale Pino o Abeto) |
| `pinoNevado` | Abeto con un cono blanco `C_NIEVE` en el 42 % de arriba de cada piso (como hace hoy `PLANTAS3D.pino`) |
| `copa` | `especieArbol` con `aislado = true`, o `juntoAgua` si `dAgua < 10` |
| `arbusto` | Arbusto, escala `U(0.8, 1.4)` |
| `matorral` | Arbusto con el tono seco `(1.12, 0.98, 0.62)` |
| `flores` | Centro de una mancha de flores (capa 5) |
| `roca` | Centro de un afloramiento (capa 6) |
| `cactus` | No está en el estilo: se conserva el cactus actual del bioma arena |

**1. Bosque y árboles sueltos.**

- Candidatos en una rejilla de 4,6 m desplazada `U(-2.0, 2.0)` en x e y.
  Recórrelos en un orden barajado por hash (el script usa una permutación) para
  que ninguna especie gane siempre en los choques.
- Se descarta el candidato si:
  - `dAgua < 2.5`;
  - está en una explanada o en el edificio;
  - `nz < 0.82`.
- Probabilidad: `0.92 * bosque` si `bosque > 0.25`; si no, `0.012` (árboles
  sueltos por la pradera).
- Especie: `especieArbol(r, zRel, bosque, false, bosque <= 0.25)`. Se pone si
  no choca con su radio `RADIO_ARBOL`. Escala `U(0.8, 1.25)`, hundir 0,3.
- Densidad resultante en bosque denso: unos 200-300 árboles por hectárea.

**2. Ribera.**

- Por cada río, cada 4 m de cauce (una muestra de cada dos a 2 m), con
  probabilidad 0,6, un árbol a un lado al azar, a `ancho / 2 + U(3, 8)` del eje.
- Solo si `nz >= 0.85`, no está en el lago y no choca.
- `especieArbol(..., juntoAgua = true)`, escala `U(0.85, 1.2)`, hundir 0,3.

**3. Arbustos.**

- Rejilla de 3,2 m desplazada `U(-1.5, 1.5)`.
- `orla = suave(0.05, 0.3, bosque) * suave(0.7, 0.35, bosque)`: el borde del
  bosque. Probabilidad `0.5 * orla + 0.015`.
- Se descarta si `dAgua < 2.0`, `nz < 0.8` o choca con radio 1,6.
- Escala `U(0.8, 1.4)`, hundir 0,25.
- Los setos del script (lindes de campos) **no aplican**.

**4. Matas de hierba.**

- Unas **400 por hectárea**. El script pone 9000 al azar en 22,7 ha: para eso,
  puntos por hash en celdas de 5 m (una por celda, desplazada dentro de ella).
- Se descarta si `dAgua < 0.8` o `nz < 0.8`.
- Seca si `zRel > 14` o `r2:simplex(x / 600, y / 600) > 0.25`, y entonces
  MataSeca con probabilidad 0,6; si no, Mata.
- Escala `U(0.8, 1.5)`, hundir 0,08, **alinear 0,7** (se inclinan con la
  ladera).
- No ocupan la rejilla de choques.

**5. Flores.**

- Cada ancla `flores` del mapa abre una mancha de radio `fr = U(6, 9)` m, con
  color = `hash % 4 + 1`.
- Además, manchas sueltas en la pradera (`bosque < 0.3`, sin hierba seca): una
  por celda de 60 m con probabilidad 0,15. En el script hay unas 0,3 manchas
  por hectárea.
- Dentro de cada mancha, `floor(fr * fr * 0.9)` flores: ángulo U y radio
  `fr * sqrt(U) * 0.95`. Se descarta si `dAgua < 1`.
- Escala `U(0.9, 1.3)`, hundir 0,05, alinear 0,7.
- La mancha también tiñe el suelo (paso 4 de la sección 2.3).

**6. Rocas.**

- **En lo empinado:** rejilla de 2,8 m desplazada `U(-1.3, 1.3)`. Si
  `pendiente >= 0.18`, probabilidad `0.6 * suave(0.18, 0.32, pendiente)`.
  Escala `U(0.8, 2.6)`, hundir 0,3, giro libre, tono roca. Se descarta si
  `dAgua < 0.5`.
- **Afloramientos en las crestas:**
  - Centros: en una rejilla de 40 m, el punto más alto de cada celda si
    `curvatura > 0.8` y `zRel > 4`, con probabilidad 0,5. También las anclas
    `roca` del mapa.
  - Radio `U(5, 8)`, con `floor(U(4, 7.99))` rocas dentro: ángulo U y radio
    `r * sqrt(U)`.
  - Escala `U(1.4, 3.4)`, hundir 0,35, giro libre.
- **Peñas sueltas:** unas 4 por hectárea por hash, si `dAgua >= 1.5`. Escala
  `U(0.5, 1.6)`, hundir 0,3.

**7. Orillas** (en la sección 6.4).

### 4.5 Qué se entrega a la física y a las tropas

- `plantasFisicas` = **todos** los árboles, con
  `{ x, y, radio = radioTronco * escala * 10, alto = ALTO_ARBOL * escalaZ * 10 }`.
  El radio del tronco es 0,36 en el pino, 0,32 en el abeto, 0,55 en el roble,
  0,36 en el álamo y 0,22 en el abedul. El choque de un tanque es contra el
  **tronco**, no contra la copa.
- También entran las rocas de escala > 1,4, con radio `1.1 * escala`.
- `Suelo:plantaCerca` usa la misma rejilla.

---

## 5. Rendimiento

### 5.1 Objetivos

- **Generar todo al entrar: menos de 1,2 s** (tope 1,5 s):

| Paso | Tiempo |
|---|---|
| terreno más hidrología | ≤ 0,45 s |
| colores de las caras | ≤ 0,15 s |
| 40 prototipos más sus LOD | ≤ 0,05 s |
| colocar árboles, arbustos y rocas | ≤ 0,3 s |
| mallas de agua | ≤ 0,05 s |
| pasar a Dream | ≤ 0,2 s |

- Imprime una línea `SUELO` con el tiempo de cada paso y el número de
  instancias por especie.
- **Hierba, flores, cañas y piedras de orilla no se generan al entrar:** se
  generan por baldosa cuando la cámara se acerca, un máximo de 2 baldosas por
  cuadro (≤ 2 ms). Como salen del hash, dan siempre lo mismo.
- Las máscaras (`bosque`, `humedad`, ruidos) se leen **interpoladas de la
  rejilla del terreno**. No llames a `fbm` por candidato: hay más de 400 000
  candidatos de árbol.

### 5.2 Instancias con tono y escala por copia

- Cada variante de cada especie y LOD es un `dream:newInstancedMesh`.
- La escala va dentro de la matriz de la copia (`addInstance` acepta una mat3
  con escala).
- **El tono por copia no existe en 3DreamEngine:** `instancedMesh` solo lleva
  `InstanceRotation0-2` e `InstancePosition`. **Falta:**
  - una clase `batalla/dream/instancias_tono.lua` que herede de
    `instancedMesh`, añada un buffer `InstanceTono` (vec3, `perinstance`) y lo
    enganche en `getMesh`, igual que los otros atributos;
  - en el shader de vértices de la vegetación (sección 7):
    `VaryingColor.rgb *= InstanceTono;`. LÖVE asigna `VaryingColor` antes de
    llamar a `position()`, así que funciona.
  - No toques `lib/3DreamEngine`: hazlo en `batalla/dream/`.

### 5.3 LOD por baldosas

- Baldosas de **200 m** (15 x 15 en el área). Cada baldosa guarda, por especie,
  variante y LOD, su lista de matrices y tonos, calculada al generar.
- Cuando la cámara **cambia de baldosa o de banda de distancia** (no en cada
  cuadro), se rehacen los lotes con `setInstances` juntando las listas de las
  baldosas de cada banda. Objetivo: ≤ 4 ms cada vez.
- Distancia: la horizontal de la cámara al borde de la baldosa.

| Capa | LOD 0 | LOD 1 | LOD 2 | Fuera |
|---|---|---|---|---|
| Árboles | < 300 m | 300-800 m, la mitad (hash % 2), escala x 1,1 | > 800 m, 35 % (hash % 100 < 35), escala x 1,15 | nunca |
| Arbustos | < 200 m | 200-500 m, 1 masa | — | > 500 m |
| Matas | < 120 m | 120-250 m, 1 de cada 3, 4 hojas | — | > 250 m |
| Flores | < 150 m | — | — | > 150 m |
| Cañas | < 250 m | — | — | > 250 m |
| Rocas > 1,4 | siempre (20 triángulos) | — | — | — |
| Rocas ≤ 1,4 | < 400 m | — | — | > 400 m |

- El aclarado lejos se compensa con escala para que la mancha de bosque se vea
  igual de llena. El color del suelo (`C_BOSQUE`) hace el resto.
- Sombras: las proyectan árboles y rocas en LOD 0 y 1; hierba, flores y cañas
  no (`setShadowVisibility(false)`).

### 5.4 Presupuesto de triángulos visibles

Peor caso: cámara baja en el centro, mirando a un bosque.

| Parte | Tope |
|---|---|
| Terreno | 450 000 |
| Vegetación y rocas | 1 000 000 |
| Agua | 60 000 |
| Vehículos (80 x 3000) | 240 000 |
| **Total** | **1,8 millones** |

Además: como mucho 120 dibujos de vegetación por cuadro y 40 000 instancias
dibujadas. Debe seguir cumpliendo la guía: más de 100 FPS con 40 contra 40,
nunca por debajo de 60. Si no llega, se recortan primero los radios de LOD de
la hierba, luego el LOD 1 de los árboles.

---

## 6. Agua: ríos y lagos desde el terreno del sitio

Ríos solo en la batalla (decisión del dueño). El mapa 2D sigue sin ríos. Los
caminos y puentes van en §6.5.

**Estado (2026-10-01, Valeria):** hecho en `batalla/cauces.lua` con un trazado
más sencillo que la hidrología de §6.1. Por hash del sitio y la humedad del mapa
sale nada (la mayoría de las batallas), un río, un cañón o un cañón con río. El
eje se busca con A* sobre la altura táctica: el río por lo bajo, de lago en lago;
el cañón por lo alto, y solo se talla donde hay relieve, sin inventar terreno.
El cauce y las orillas siguen §6.2 y la cinta del agua va en la malla del mar.
Se traza después de los pasillos, que no cambian. Donde los cruza, el río se
vuelve **vado** (0,3 m de agua, se pisa) y el cañón **rampa** de 10°. Los puentes
de §6.5, los lagos de §6.1 y las ondas de §6.3 siguen pendientes. Sin cauce, el
suelo sale idéntico al de antes.

### 6.1 Hidrología (determinista)

1. **Rejilla hidrológica** de celdas de 20 m (150 x 150), con la altura
   táctica (antes de tallar) interpolada de la rejilla del terreno.
2. **Relleno de depresiones** (*priority-flood*, Barnes 2014).
   - Se siembra desde el borde del área y desde las celdas bajo `nivelMar`.
   - Pendiente mínima de 0,001 m por celda para que todo drene.
   - Los empates se deshacen por índice de celda.
   - Resultado: `hLleno`.
3. **Lagos:** zonas conexas con `hLleno - h > 0.8 m` y **al menos 6 celdas**
   (2400 m²), que no pisen una explanada.
   - Nivel del lago: el `hLleno` de su desagüe **menos 0,8 m**. Así el agua
     nunca rebosa, como hace el script con `nivel_lago`.
   - Las depresiones más pequeñas se ignoran: el río pasa por encima.
4. **Dirección D8** sobre `hLleno` y **acumulación**: se recorren las celdas
   de la más alta a la más baja.
5. **Cauces:** las celdas con `acumulación >= 250` (10 ha).
   - Si salen más de 6 km de cauce en total, multiplica el umbral por 1,5
     hasta que quede por debajo.
   - Ancho: `ancho = min(9.5, 4.0 + 1.4 * log2(acumulación / 250))` m. Va de
     4 m en la cabecera a 9,5 m, como `rio_ancho` del script.
6. **Trazado:**
   - Se sigue cada cauce desde su cabecera por D8 hasta el borde, un lago, el
     mar o la confluencia con otro cauce.
   - Los centros de celda se suavizan con Catmull-Rom (`curva` del script) y
     se remuestrean cada 2 m.
   - Meandro: desplazamiento lateral de `ruido(s / 60 m) * min(12, 1.2 * ancho)`
     m, con `s` los metros recorridos. Se atenúa a 0 en los 20 m de los
     extremos.
7. **Nivel del agua, siempre cuesta abajo** (lo mismo que el script):

```lua
nivel[1] = hBase[1] - 1.2
for i = 2, #puntos do
    nivel[i] = math.min(nivel[i - 1] - 0.02, hBase[i] - 1.2) -- en m, muestras cada 2 m
end
-- Nunca por debajo del lago o del mar donde desemboca.
nivel[i] = math.max(nivel[i], nivelDestino)
```

### 6.2 Tallado del terreno

Se hace **antes** de colorear y plantar, sobre la rejilla del terreno.
`Suelo:altura` pasa a leer esa rejilla tallada (sección 9), para que los
vehículos no floten sobre el río.

- **Valle:** `h = h - (6.0 * ancho / 9.5) * suave(42, 6, d)`, con `d` la
  distancia al eje en m. Así un arroyo abre menos valle que el río. La parte del
  script que abría el anillo de colinas no aplica.
- **Cauce** (`sin_caminos` del script):

```lua
local a = 0.3 * ancho
local b = 0.5 * ancho + 0.8
-- Donde la rejilla es gruesa, el perfil se ensancha para que se vea.
a = math.max(a, paso * 0.75)
b = math.max(b, paso * 1.5)
local perfil
if d < a then
    perfil = -1.2
elseif d < b then
    perfil = -1.2 + (d - a) / (b - a) * 1.5
else
    perfil = 0.3 + (d - b) * 0.35
end
h = math.min(h, nivel + perfil)
```

- **Cubeta del lago:** dentro del lago,
  `h = min(h, nivelLago - 3.2 * (1 - (1 - dBorde / dMax) ^ 2) ^ 0.6)`, con
  `dBorde` la distancia a la orilla y `dMax` la mayor del lago. Fuera,
  `h = min(h, nivelLago + dBorde * 0.35)`, con la pendiente de la orilla del
  script.
- Donde hay explanada, el tallado se multiplica por `1 - pesoExplanada`.
- **Campo de distancias:** para colorear y plantar hace falta `dAgua` y
  `nivelAgua` por punto. Estampa cada segmento del río en una rejilla FFI de
  5 m (600 x 600) hasta `ancho / 2 + 45` m: distancia mínima, nivel y `s`.
  Los lagos se estampan desde su orilla. Son como un millón de operaciones.

### 6.3 Mallas y material del agua

- **Río:** una cinta a lo largo del eje, de ancho `ancho + 2.4` m, con 5 filas
  a través en `f = -0.5, -0.25, 0, 0.25, 0.5`. Z = `nivel`, con un temblor de
  `U(-0.03, 0.03)` m en las filas interiores.
  - Tono por franja: `(1.25, 1.0, 0.85, 1.0, 1.25)`, la media de sus dos
    bordes, por `U(0.96, 1.04)`. Así es más claro en la orilla (poco fondo).
  - Cada vértice lleva **UV = (s en m río abajo, f)**: lo usa el shader de las
    ondas.
- **Lago:** rejilla de 2,4 m desplazada `U(-0.35, 0.35) * 2.4` en x e y y
  `U(-0.03, 0.03)` en z, a nivel constante, sin dibujo radial. Se recortan las
  caras más allá de 1,3 veces el radio. El terreno tapa lo que sobra.
  - Tono `t = 0.85 + 0.45 * suave(0.55, 1.05, 1 - dBorde / dMax)`, por
    `U(0.96, 1.04)`.
  - UV = (x, y) en m.
- **Mar:** el plano actual con el mismo material y UV = (x, y).
- **Formato:** la malla del agua necesita **UV**, que `batalla/malla.lua` no
  tiene. Constrúyela directamente con buffers de Dream en
  `batalla/dream/agua.lua` (formato `textured`) o añade un formato con UV. Es
  otra primitiva que falta.
- **Material** (el de `material_agua`):

| Parámetro | Valor |
|---|---|
| Color | `(0.2, 0.44, 0.5)` sRGB por el tono del vértice |
| Rugosidad | 0,05 |
| Metálico | 0 (el IOR 1,33 da el Fresnel; que refleje el cielo) |
| Alfa | 0,8, en el pase de transparencias (`setAlpha`) |
| Reflejo | el cubemap del cielo (sección 8) |

- **Ondas:** shader de píxel `aguaBatalla`, a partir de
  `lib/3DreamEngine/shaders/inbuilt/water.lua` pero sin textura de normales.
  Relieve procedural con dos capas de ruido y normal por diferencias finitas
  (como el nodo *Bump* del script, distancia 0,32 m):
  - **Río** (UV = s, f; `t` en segundos):

```glsl
vec2 gruesa = vec2((uv.x - t * 2.2) * 0.35, uv.y * 1.2);  // baja a 2,2 m/s
vec2 fina = vec2((uv.x - t * 3.4) * 1.1, uv.y * 4.0);     // capa fina, 3,4 m/s
float alto = ruido(gruesa, t * 0.25) + 0.45 * ruido(fina, t * 0.4);
fuerza = 0.45;
```

  - **Lago y mar** (UV = x, y en m):

```glsl
float alto = ruido(uv / 1.45, t * 0.22) + 0.5 * ruido(uv / 4.6, t * 0.1);
fuerza = 0.28;
```

  `ruido(p, w)` es un ruido 3D de valor (0-1) con `w` como tercera coordenada.
  La corriente sigue `s`: siempre río abajo.

### 6.4 Orillas

- **Arena o tierra:** paso 5 de la fórmula del color (sección 2.3).
- **Cañas y piedras del lago:** unas 1,4 por metro de orilla. Por cada punto,
  se busca a lo largo de la normal de la orilla el sitio donde el suelo cruza
  `nivel + 0.1` (`orilla_cercana`: pasos de 0,5 m, de -6 a +8 m), y se mueve
  `U(-0.5, 0.2)` m.
  - Con probabilidad `0.3 + 0.5 * (0.5 + 0.5 * canas)`: cañas, escala
    `U(0.8, 1.3)`, hundir 0,2, inclinar 0,08.
  - Si no: roca, escala `U(0.25, 0.7)`, hundir 0,3, giro libre, tono roca.
- **Cañas y piedras del río:** cada 4 m de cauce, con probabilidad 0,4, un
  punto a un lado al azar a `ancho / 2 + U(0.2, 1.4)` del eje, fuera del lago.
  - Con probabilidad 0,55: cañas, escala `U(0.7, 1.1)`.
  - Si no: roca, escala `U(0.3, 0.8)`.
- **Nenúfares:** solo en lagos.
  - `min(12, floor(área / 300 m²))` grupos, en celdas con fondo de 0,3 a 1,5 m
    y de 2 a 8 m de la orilla.
  - De 4 a 9 discos por grupo, a `U(-3, 3)` m del centro, en `nivelLago + 0.05`.
  - Se mecen en el shader de vértices: desplazamiento de ±0,25 m en x e y y
    ±0,06 m en z, con ruido de unos 3,5 m de escala y `w = t * 0.35`.
- Los ríos y lagos **no se pueden cruzar**. Los vehículos se paran en la
  orilla y solo cruzan por un puente (decisión del dueño). La física de
  Codex debe tratar el agua como un obstáculo, y el cálculo de ruta de las
  unidades debe llevarlas al puente más cercano.

---


### 6.5 Caminos y puentes (como en el paisaje de Blender)

Decisión del dueño: la batalla lleva caminos de tierra y puentes de madera
como los de `paisaje_lowpoly.py` (`CAMINOS`, `cinta`, `caminos`). Solo existen
en la batalla. **No son rutas del mapa 2D**, que no las tiene, y no cambian la
simulación.

**Trazado** (procedural y determinista, por hash del centro de la batalla):
- Entre 1 y 3 caminos cruzan el área de borde a borde. Uno pasa cerca del
  objetivo, si hay ciudad o instalación. Los otros entran por bordes elegidos
  por hash y se unen en cruces en Y, como en el script: el camino 3 nace del 1.
- Cada camino busca el paso más cómodo con A* sobre una rejilla de unos 8 m:
  - coste = distancia × (1 + (pendiente / 12°)²);
  - prohibido por encima de unos 22°;
  - el agua cuesta 6× salvo cruzándola casi en perpendicular (ahí va un
    puente);
  - si no hay otra salida, rodea los lagos.
- Suaviza la línea resultante con Catmull-Rom y remuestréala cada 1 m, como
  `curva(puntos, 1.0)`. Así queda serpenteando y sin esquinas.
- No pasa por las explanadas donde forman los ejércitos: las bordea.

**Sección y color** (idéntico al script):
- Ancho: 4,4 m el principal, 4,0 m el secundario y 3,0 m el ramal.
- Cintas laterales en `offsets = {-m, -0.62m, -0.34m, 0.34m, 0.62m, m}`, con
  `m = ancho / 2`. Son 5 franjas: polvo, rodada, centro, rodada y polvo.
- Colores sRGB:
  - polvo `(0.62, 0.50, 0.34)`;
  - rodada `(0.43, 0.32, 0.21)`;
  - centro `(0.50, 0.50, 0.28)`, la hierba del lomo central.
- Cada triángulo lleva su tono × `U(0.95, 1.05)`.
- Borde irregular: los vértices exteriores se desplazan ±0,25 m.

**Altura:**
- La altura del terreno bajo la línea se suaviza con una media móvil de 13 m
  (ventana de 13 muestras de 1 m). Así el camino no copia cada bache.
- Los bordes quedan +0,10 m sobre el terreno y el resto +0,16 m.
- Tallado: baja o sube el terreno de debajo hacia esa altura suavizada, a
  todo lo ancho, y mézclalo con el terreno real en 2,5 m a cada lado con
  `smoothstep`. Así el camino va encajado y no flota ni se hunde.

**Puentes** (`caminos()` del script):
- Van donde el camino pasa a menos de `anchoRio/2 + 3` m del eje del río.
- Largo = el tramo sobre el agua + 2 m.
- **Ancho: 16 m, dos carriles** (decisión del dueño). Es más ancho que el
  camino del script (ancho del camino + 0,4 m) para que pasen dos tanques o
  lanzacohetes a la vez. PENDIENTE: todavía no hay puentes en la batalla
  (`Agua:puenteEn` devuelve siempre falso).
- Altura del tablero: `max(zOrillaA, zOrillaB, nivelRio + 1.4) + 0.2`.
- Tablones transversales de 0,5 × ancho × 0,22 m, uno cada 0,55 m, en madera
  `(0.46, 0.32, 0.20)` con variación ±14 %.
- Dos vigas laterales de largo × 0,35 × 0,45 m y 3 pilares por lado de
  0,28 × 0,28 m que bajan hasta el lecho, en madera oscura
  `(0.30, 0.20, 0.13)`.
- Barandilla a 1 m de altura, de 0,16 × 0,14 m.
- Estribos de piedra en los dos extremos, de 1,4 × (ancho + 0,8) m, que
  bajan 1,5 m bajo la orilla, en piedra `(0.60, 0.57, 0.52)`.
- Todo con `Malla:caja`: son cajas giradas al rumbo del camino.

**Vegetación y rocas:**
- Nada de árboles, arbustos ni rocas sobre el camino ni a menos de 2 m de su
  borde.
- A menos de 7 m del centro de un puente, tampoco.
- La hierba sí puede crecer en el lomo central, en la franja "centro".

**Garantía:** si un río corta el área y ningún camino lo cruza, se añade un
camino corto con puente por el tramo más estrecho y llano, para que los
bandos siempre puedan llegar uno al otro.

**Física:** el camino es suelo normal. Si Codex quiere que los vehículos
vayan algo más rápido por él, es una decisión aparte; hoy no lo pidió nadie.

## 7. Viento (shader de vértices)

Un solo shader de vértices, `vientoBatalla`, registrado con
`dream:registerShader` (`type = 'vertex'`) y puesto con `setVertexShader` en
todas las mallas de vegetación. Se basa en
`lib/3DreamEngine/shaders/inbuilt/foliage.lua`, pero con la fórmula del script.

### 7.1 Parámetros

```lua
-- Dirección hacia la que sopla, en el plano: la del río principal, río abajo
-- (media de sus tramos, pesada por el ancho). Sin ríos, ángulo = hash(semilla) % 3600 / 3600 * 2π.
VIENTO_DIR = { dx, dy }

-- especie: { inclinación (rad), pulsación (rad/s), longitud de la ola (m), flexión de la copa (m) }
local VIENTO = {
    Pino = { 0.03, 1.0, 55, 0.35 },
    Abeto = { 0.025, 0.9, 55, 0.3 },
    Roble = { 0.03, 1.1, 55, 0.4 },
    Alamo = { 0.05, 1.3, 55, 0.5 },
    Abedul = { 0.05, 1.4, 55, 0.45 },
    Arbusto = { 0.05, 1.8, 30, 0.12 },
    Mata = { 0.3, 2.6, 14, 0.1 },
    MataSeca = { 0.3, 2.6, 14, 0.1 },
    Flor = { 0.2, 2.4, 14, 0.08 },
    Canas = { 0.16, 2.0, 12, 0.25 },
}
```

La hierba pulsa a 2,6 rad/s y se inclina 0,3 rad; los árboles, a 0,9-1,4 rad/s
y 0,025-0,05 rad. Las cañas y las flores quedan en medio.

### 7.2 Fórmula

Uniforms por material: `amp`, `pulso`, `ola`, `flexion`, `altoProto` (alto de
la variante, en m) y `vientoDir`. Por cuadro: `t` (segundos). Trabaja en metros
y pasa a unidades de Dream (/ 10) al sumar.

```glsl
// P = base de la copia (InstancePosition), en m y en el plano del juego.
float fase = hash(P) * 6.2832;
float fuerza = mix(0.7, 1.3, hash(P + 17.0));

// 1. Ola que avanza en la dirección del viento.
float ola01 = 0.5 + 0.5 * sin(6.2832 / ola * dot(P, vientoDir) - pulso * t);

// 2. Ráfagas: ruido de 70 m que viaja con el viento a 9 m/s,
//    llevado de [0.32, 0.68] a [0.25, 1.35] (con tope).
float n = ruido((P - vientoDir * 9.0 * t) / 70.0);
float rafaga = mix(0.25, 1.35, clamp((n - 0.32) / 0.36, 0.0, 1.0));

// 3. Vaivén propio de cada copia.
float propio = sin(t * pulso * 1.7 + fase);

float angulo = (rafaga * (0.7 * ola01 + 0.3) * amp + propio * amp * 0.18) * fuerza;

// Inclinación desde la base hacia donde sopla (giro sobre el eje horizontal
// perpendicular al viento). hLocal = altura del vértice sobre la base, en m.
desplazamiento.xz += vientoDir * sin(angulo) * hLocal;
desplazamiento.y -= hLocal * (1.0 - cos(angulo));

// 4. Flexión: crece con la altura al cuadrado (la base no se mueve).
float h = max(hLocal, 0.0) / altoProto;
float peso = h * h * flexion;
float fx = sin(t * pulso * 1.9 + fase);
float fy = sin(t * pulso * 1.45 + fase * 2.3 + 1.0);
desplazamiento.xz += vec2(fx * peso, fy * peso * 0.7);   // en ejes locales de la copia
```

- `hash` y `ruido` son funciones GLSL baratas. Para `ruido` vale la
  `noiseTexture` de Dream, como en `foliage.lua`.
- El desplazamiento se suma **después** de la instancia (`vertexPos` ya está en
  mundo) y se aplica `transform` como en `inbuilt/vertex.lua`.
- `hLocal` sale de `vertexPos.y - InstancePosition.y`.
- Rocas y nenúfares no llevan este shader. Los nenúfares tienen el suyo
  (sección 6.4).
- Nubes, si se ponen: avanzan con `VIENTO_DIR`.

---

## 8. Luz, cielo y bruma

| En el script (Blender) | Valor | En 3DreamEngine |
|---|---|---|
| Sol | elevación 40°, "desde el suroeste" | `sun.direction` apunta **hacia** el sol. Usa la dirección de la luz del mapa (`Terreno`, `LUZ = { -0.45, -0.55, 0.7 }`) para que coincida con el mapa: horizontal `(-0.633, -0.774)` y elevación 40°. Hacia el sol en el juego: `(-0.485, -0.593, 0.643)`; en Dream (x, z, y): `vec3(-0.485, 0.643, -0.593)`. Pon esa dirección **después** de `Cielo.iluminar`, porque `setDaytime` la sobrescribe |
| Color del sol | `(1.0, 0.95, 0.86)` lineal | `solDream:setColor(1.0, 0.95, 0.86)`; brillo 1,25 como hoy, a ajustar |
| Tamaño del sol | 1,6° (sombras suaves) | Sombra del sol con `addNewShadow(2048)` y filtrado suave |
| Ambiente | el cielo en degradado | `dream.sun_ambient`: `(0.26, 0.36, 0.55)` lineal por `k`. Ajusta `k` **midiendo** en una captura sobre la pradera: la cara en sombra de una ladera debe quedar al 35-40 % del brillo de la cara al sol |
| `HORIZONTE` | `(0.8, 0.87, 0.95)` sRGB = `(0.612, 0.736, 0.893)` lineal | Color de la niebla y del borde |
| Degradado del cielo | horizonte a 0°, `(0.46, 0.66, 0.92)` a 6,9° (0,12), `(0.12, 0.3, 0.76)` a 33° (0,55) y más arriba; bajo el horizonte, el color del horizonte | Genera en Lua un **cubemap de 6 x 256²** al cargar (unos 50 ms), con el color según el seno de la elevación de cada dirección, y `dream:setSky(cubo)`. Así también sirve de reflejo para el agua. Sustituye a `cielo.png`. Lineal: `(0.181, 0.401, 0.832)` y `(0.0094, 0.0707, 0.547)` |
| Nubes | 30 grupos low-poly a 300-520 m y 100-190 m de alto, en una escena de 300 m | Opcional. Si se ponen: las mismas reglas por 5 (grupos a 1,5-2,6 km y 500-950 m de alto), de 6 a 10 icosaedros aplastados `(1.3, 1.0, 0.62)` más una losa baja. O las nubes de la extensión sky. Que decida el dueño con una captura |
| Bruma (pase Mist) | lineal de 110 a 490 m, mezclando hasta un **36 %** hacia `HORIZONTE`, en una escena de 300 m | Dos partes. 1) **Bruma de estilo:** `dream:setFog(0.0045, vec3(0.612, 0.736, 0.893), 0.3)`, con la densidad por unidad de Dream (10 m): queda en un 24 % a 600 m y un 49 % a 1,5 km. Quita `setFogHeight` o súbelo a `(-2, 120)`. 2) **Borde del área:** en el shader del terreno, mezcla con `HORIZONTE` según `smoothstep(1300 m, 1500 m, distancia horizontal al centro)`, para que el borde se funda con el cielo |
| Oclusión (fast GI, 12 m) | | `dream:setAO(16, 0.5, true)` |
| Bloom | umbral 1,0, fuerza 0,5, tamaño 0,5 | `dream:setBloom(2, 0.5, 0.08, 0.5)` (hoy la fuerza es 0,7) |
| Look | AgX, "Medium High Contrast", exposición 0 | **3DreamEngine no tiene AgX.** Propuesta: exposición fija (sin `setAutoExposure`) y una curva S suave en el pase final. Si no se parece, se puede hornear el look de Blender en una LUT 3D (lo haría yo, sin render de escena). Que el dueño decida con una captura al lado de la del script |

El shader `terrenoNatural` (`dream/textura_terreno.lua`) mete grano y relieve
de textura: el estilo del script no los tiene. **Pon
`fuerzaRelieveTerreno = 0`** y deja la variación de albedo en 1 (o usa
`simple`). La variación por cara de la sección 2 lo sustituye. Aprovecha ese
shader solo para el borde con niebla.

Nota: la guía dice "luz cálida de atardecer como el mapa"; el script es luz de
media mañana (40°). El dueño pidió el estilo del script, así que aquí va 40°. Si
se prefiere el atardecer, basta con bajar la elevación y calentar el color.
**Decisión del dueño.**

---

## 9. Lista de cambios, en orden

Qué hace hoy `suelo.lua` (y el dibujo en `dream/`) y qué falta:

1. **Altura en la rejilla** (`Suelo:altura`).
   - Hoy recalcula `terreno:altura` 5 veces por llamada.
   - Falta: que lea la rejilla final (suavizada, con explanadas, detalle y
     tallado) interpolada en su triángulo. Así la pisan los vehículos y las
     plantas, y es más rápida.
2. **Rejilla desplazada** (sección 2.2). Hoy es regular.
3. **Hidrología y tallado** (secciones 6.1 y 6.2), con su campo de distancias.
   - Hoy solo hay el plano del mar.
   - Va entre el suavizado y el color, dentro de `generarTerreno`.
4. **Color por cara y sombreado plano** (secciones 2.2 y 2.3).
   - Hoy: `colorSuperficie` usa `Terreno:color` del mapa, un color y una
     normal suavizada por vértice, e interpola (`trianguloColores`).
   - Falta: `colorCara` en el centroide, con la paleta, y `malla:triangulo`.
5. **`textura_terreno.lua`:** relieve a 0, sin grano, más el borde con
   niebla (sección 8).
6. **Primitivas que faltan** en `malla.lua`: `icosaedroLibre`,
   `variarPieza`, y `Conversor:desdeMallaLocal` en `dream/conversor.lua`.
7. **Prototipos** en un módulo nuevo (por ejemplo `batalla/vegetacion.lua`):
   las 11 especies de la sección 3, con sus variantes y LOD.
   - Hoy `PLANTAS3D` dibuja cada planta como geometría propia en una sola
     malla estática gigante (hasta 200 000 vértices de partida).
8. **Colocación por reglas** (sección 4), en un módulo nuevo (por ejemplo
   `batalla/colocacion.lua`), con baldosas y `plantasFisicas`.
   - Hoy solo se ponen las plantas del mapa, que quedan de anclas.
   - Se retiran `seQueda`, `trozoConPlantas` y `plantasDeTrozo`.
9. **Agua** (secciones 6.3 y 6.4): cinta del río, rejilla del lago, orillas y
   nenúfares, en `batalla/dream/agua.lua`, con el shader `aguaBatalla`.
   - Hoy es un plano de 2 triángulos con alfa 0,72, rugosidad 0,18 y
     metálico 0,15.
10. **Instancias con tono y LOD** (sección 5): `dream/instancias_tono.lua`, y
    rehacer los lotes al cambiar de baldosa.
    - Hoy `dream/escena.lua` dibuja `dreamPlantas` como una sola malla.
11. **Viento** (sección 7): el shader `vientoBatalla` en la vegetación.
12. **Luz, cielo y bruma** (sección 8), en `configurarMotor` y
    `dream/cielo.lua`.
13. **Medir:**
    - la línea `SUELO` con los tiempos;
    - los triángulos visibles en `normal`, `cerca` y `lejos`;
    - los FPS con 40 contra 40;
    - capturas de tres semillas (una de montaña, una de costa y una de
      pradera), al lado de la captura del script. Las del script las saco yo
      cuando la pantalla esté libre: pídemelas.

**Lo que decide el dueño** (no está resuelto aquí):

- Si los vehículos cruzan ríos (vado lento) o no.
- Luz de media mañana (el script) o de atardecer (la guía).
- Si hay nubes low-poly propias o las de la extensión sky.
- Si se hornea el look AgX en una LUT.
- Campos de cultivo junto a las ciudades: hoy no aplican.

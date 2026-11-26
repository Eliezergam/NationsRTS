# Mundo físico

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Fuentes: `mundo/terreno.lua`, `mundo/ciudades.lua`, `mundo/plantas.lua`,
`mundo/recursos.lua`, `mundo/mundo.lua`, `mundo/ruido.lua`.

## 1. Resumen

Todo lo que se ve y no cambia (terreno, biomas, plantas, ciudades con sus calles
y habitantes, depósitos de recursos) sale de la semilla y de coordenadas. Nunca
se guarda ni viaja por la red: cada máquina lo genera idéntico. Se genera por
**trozos** de 512 px alrededor de la cámara (máximo 3 por cuadro) y se olvida al
alejarse. Sobre ese mundo se reparten las piezas del mundo vivo: cada ciudad es
un sitio de una nación, cada depósito un posible complejo de extracción.

## 2. Fantasía del jugador

Explorar un continente que nadie ha diseñado a mano y que, sin embargo, es el
mismo para todos: costas, cordilleras, bosques, y a decenas de kilómetros unas
de otras, ciudades únicas (nombre, paleta, calles, gente paseando) que son
capitales o provincias de países con historia propia. Encontrar una mina o un
pozo y saber que alguien lo va a querer.

## 3. Reglas

### Escalas (px de mundo)

| Unidad | Tamaño | Constante |
|---|---|---|
| Celda de terreno | 32 | `Terreno.celda` (`terreno.lua:15`) |
| Trozo | 16 × 32 = 512 | `Terreno.celdasPorTrozo` |
| Región de ciudad | 24 576 (2,5 km; 1 px = 10 cm) | `Ciudades.region` (`ciudades.lua`) |
| Región de depósitos | 8 192 | `Recursos.region` (`recursos.lua:14`) |
| Zona (nación) | 4 × 24 576 = 98 304 (unos 10 km) | `Ciudades.porNacion = 4` (`Mundo.zona`) |
| Margen generado fuera de vista | 900 | `Mundo.margen` |

### Terreno

1. `Terreno:base(x, y)` suma tres ruidos: continentes (`fbm` a escala 5 200,
   ×150 +20), cordilleras (`crestas` a escala 1 500, solo donde ya hay tierra,
   hasta ×520) y ondulación (`fbm` a escala 520, ×14). Negativo = mar
   (`nivelMar = 0`).
2. `Terreno:altura` aplana el terreno hacia la altura de la plaza en un anillo
   de `radio + 260` alrededor de cada ciudad (curva suave).
3. `Terreno:bioma(x, y)`, por altura: `< 0` agua, `< 12` arena, `> 300` nieve,
   `> 190` roca; en medio decide la humedad (`fbm` a escala 3 000):
   `> 0,2` bosque, `< −0,25` seca, resto pradera.

### Ciudades

1. Cada región `(rx, ry)` tira `Ruido.hash(semilla, rx, ry, 31)`. Con
   probabilidad `Ciudades.probabilidad = 0,31` elige un punto entre el 25 % y
   el 75 % de la región y lo acerca al centro de su país (`Ciudades.agrupar =
   0,7`). Así las ciudades de un país quedan juntas (mediana 2,4 km a la
   propia más cercana) y entre países hay campo abierto (capital vecina a
   mediana 8 km). Dos ciudades quedan siempre a más de 860 m.
2. Solo nace si la altura natural está entre 18 y 170 (ni mar ni cumbre). Si
   no, la región queda vacía para siempre.
3. Radio 260–620 px, nombre de 2–3 sílabas, semilla propia. El id es la región,
   `'rx,ry'`: es la clave que usa el mundo vivo.
4. `Ciudades:construir` la genera entera la primera vez que se ve: manzanas de
   96–140 px, calles de 22–30, edificios más altos hacia el centro, plaza con
   monumento, `radio / 9` peatones y coches.
5. `Ciudades:dentro(x, y)` = a menos de `radio + 40` del centro.

### Depósitos

1. Cada región de 8 192 px tiene 1–3 depósitos (`Ruido.hash(..., 77)`), en un
   punto entre el 8 % y el 92 % de la región. Hasta 6 intentos por depósito
   para caer fuera de agua, nieve y ciudades; si fallan los 6, ese depósito no
   existe.
2. Tipo según el terreno: roca o altura > 150 → metal; seca o arena →
   petróleo; resto → comida (70 %) o metal (30 %).
3. Riqueza entera 1–3. Id `'rx,ry#k'` (región de depósitos).

### Plantas

1. Por trozo, un número de intentos según el bioma del centro: bosque 70,
   pradera 26, seca 14, roca 10, nieve 8, arena 6, agua 0 (`POR_BIOMA`).
2. Cada intento cae en un punto al azar; se descarta en agua, dentro de una
   ciudad o en un claro (170 px alrededor de depósitos y extracciones, 200 de
   bases: `Mundo:despejados`). Sobrevive con probabilidad
   `0,55 + humedad × 0,6`.
3. Cuando aparece una instalación nueva, los trozos cargados a su alrededor
   rehacen sus plantas (`Mundo:apartarPlantas`).

### Qué se puede construir

`Mundo:sitioValido`: altura natural entre 18 y 200 y fuera de toda ciudad. Es lo
único del mundo físico que consulta la simulación (para las bases).

### Nacimiento de naciones al explorar

Al generar un trozo, cada ciudad que lo toca se construye y
`Mundo:registrarNacionDe` registra su zona **y las 8 zonas vecinas** en la
simulación (`Mundo:datosZona` + `Simulacion:registrarZona`). Una zona se
registra una sola vez.

## 4. Fórmulas

**Altura natural.** `h = c·150 + 20 + crestas² · max(0, c + 0,15) · 520 + ondas·14`,
con `c` el ruido continental (aprox. −1..1). Ciudad y construcción piden
`18 < h < 170` y `18 < h < 200` respectivamente.

**Ciudades por zona.** Esperado ≤ 9 × 0,55 = 4,95; el filtro de altura lo baja.
Medido (16 zonas, 6 semillas): 31–48 ciudades en 144 regiones, **22–33 %** de
regiones con ciudad (media 28 %). Por zona, de 0 a 6. En la semilla 4242 una
zona tiene 0 ciudades (no hay nación) y en la 12345, tres.

**Depósitos por zona.** Esperado ≈ (36 864 / 8 192)² × 2 ≈ 40 (más los que
tocan el borde). Medido: 43–56 por zona; 615–664 en 16 zonas. Reparto medido:
comida 41–46 %, metal 27–30 %, petróleo 26–30 %. Riqueza media 2,0.

**Distancias.** Ciudad más cercana a cada ciudad (día 1): mediana 16 715 px
(semilla 4242) y 12 958 px (semilla 7); mínimo 6 764. Frente más cercano entre
dos naciones (4242): mínimo 9 034, mediana 69 845.

**Población inicial** (la pone la simulación con el radio): `radio × (8..14) ×
1,4 si es capital`. Medido (4242): 2 454–11 142, mediana 5 365.

## 5. Casos límite

- **Región de ciudad en el mar o en la montaña:** sin ciudad. Una zona puede
  quedar con 0 ciudades: no se registra ninguna nación, pero **sus depósitos sí
  entran** en la simulación (`registrarZona` los apunta antes de comprobar las
  ciudades) y son tierra de nadie que cualquier vecino puede explotar.
- **Depósito sin sitio válido en 6 intentos:** se pierde; la región tiene menos.
- **Depósito cerca del borde de un trozo:** los claros se calculan con las
  regiones vecinas (3×3), así que no hay plantas encima.
- **Ciudades muy cercanas de zonas distintas:** pueden estar a ~7 000 px; su
  territorio (alcance 5 000–7 300) se solapa desde el día 1.
- **Semilla distinta al cargar:** `main.lua` rehace el mundo con la semilla de
  la partida antes de usarla.

## 6. Dependencias

- **Lo usan:** [naciones-y-politica.md](naciones-y-politica.md) (zonas →
  naciones, capital = mayor radio), [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (depósitos, `sitioValido`, radio → alcance y población),
  [guerra.md](guerra.md) (distancias de vuelo y alcance).
- **Depende de:** `Ruido` (hash, `fbm`, `crestas`, LCG `Ruido.azar`) y de la
  cámara: qué zonas existen en la simulación depende de lo explorado.

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Efecto al moverla |
|---|---|---|---|
| `Ciudades.region` | 24 576 | 16 000–32 000 | Distancia entre ciudades y, con ella, tiempos de convoy y de vuelo. Cambia todos los ids: rompe partidas. |
| `Ciudades.agrupar` | 0,7 | 0,6–1 | Cuánto se juntan las ciudades hacia el centro de su país. Menos de 0,6 puede encimar ciudades. |
| `Ciudades.probabilidad` | 0,31 | 0,2–0,45 | Ciudades por nación (hoy media 2,6). Más ciudades = más bases (4 por ciudad) y más producción. |
| Altura de ciudad | 18–170 | — | Subir el mínimo quita ciudades costeras. |
| `Ciudades.porNacion` | 4 | 3–5 | Tamaño de nación. Con 2, muchas naciones de 1 ciudad; con 5, pocas y grandes. Rompe partidas. |
| `Recursos.region` | 8 192 | 6 000–16 000 | Densidad de depósitos (~50 por zona hoy). Menos depósitos = más disputa. |
| Depósitos por región | 1–3 | 0–3 | Poner mínimo 0 crea huecos sin recursos. |
| Riqueza | 1–3 | 1–5 | Escala la producción de recursos y la codicia (`recursosEnDisputa`). |
| `POR_BIOMA.intentos` | 6–70 | — | Solo visual y coste de dibujo. |

## 8. Criterios de aceptación

Con 16 zonas (−2..1 × −2..1), cualquier semilla de las 6 medidas:

- Mismo resultado en dos máquinas: `datosZona` devuelve las mismas ciudades y
  depósitos (comprobado indirectamente: la simulación es idéntica).
- Entre el 20 % y el 35 % de las regiones tienen ciudad (medido 22–33 %).
- Entre 40 y 60 depósitos por zona (medido 43–56).
- Ningún depósito en agua, nieve o dentro de una ciudad.
- Ninguna ciudad con altura natural fuera de 18–170.

No medido: número de plantas por trozo, coste en ms de generar un trozo.

## Propuestas (no implementadas)

- **P1. Zonas sin ciudad.** Decidir si sus depósitos deben ser tierra de nadie
  (como hoy) o no registrarse. Son botín gratis para los vecinos.
- **P2. Ids estables ante cambios de escala.** Cualquier cambio de
  `Ciudades.region`, `Recursos.region` o `Mundo.zona` invalida las partidas
  guardadas; conviene subir `Simulacion.version` a la vez.

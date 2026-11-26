# Convención de documentación del código

Para que cualquier equipo entienda un módulo sin leerlo entero, el proyecto
tiene un mapa generado (`MAPA-DEL-CODIGO.md` y `mapa/<carpeta>.md`) que se
alimenta de los comentarios del propio código. Este documento describe qué
comentarios lee y cómo regenerarlo.

## Qué lleva cada módulo

**Cabecera.** Los comentarios del principio del archivo, antes del primer
código. El primer párrafo es el propósito y es lo que aparece en el índice
general, así que la primera frase debe decir qué es el módulo y para qué sirve
(una o dos líneas). Después pueden ir el modelo, las reglas o las referencias
a `diseno/` que hagan falta. La primera línea puede empezar por `---`
(convención de LDoc); el generador propio acepta `--` y `---` por igual.

**Funciones públicas.** Las que cuelgan del módulo (`function Modulo.nombre(...)`,
`function Modulo:nombre(...)`, `Modulo.nombre = function(...)`) llevan justo
encima un comentario contiguo, sin línea en blanco de por medio, cuya primera
frase dice qué hace. Una línea basta; el generador toma el primer párrafo y lo
recorta a unos 150 caracteres. Las `local function` no salen en el mapa
(solo se cuentan) y pueden comentarse a criterio de quien las escribe.

**Dependencias.** Salen solas de los `require`; no hace falta describirlas.

Ejemplo:

```lua
--- Territorio de cada nación, dibujado por sus celdas cuadradas.
--
-- Solo lee la simulación; no cambia nada del mundo vivo.

local Territorio = {}

-- Celdas propias de la nación `nid` dentro del rectángulo visible.
function Territorio:celdasVisibles(nid, x0, y0, x1, y1)
```

## Tamaño por archivo

Referencia orientativa, medida sobre el estado actual del código:

- Hasta unas 800 líneas o 40 funciones públicas: un archivo se lee entero sin
  esfuerzo.
- Entre 800 y 1.500 líneas: aceptable si el módulo tiene una sola
  responsabilidad y la cabecera la explica.
- Por encima de 1.500 líneas o 80 funciones públicas: conviene partirlo por
  responsabilidad. Hoy `mundo/simulacion.lua` (unas 7.400 líneas, 240
  funciones públicas), `main.lua`, `mundo/mundo.lua` y `interfaz/pendon.lua`
  están por encima.

## Regenerar el mapa

```
python3 tools/generar_mapa_codigo.py
```

Tarda menos de un segundo, no ejecuta ni carga el juego y es determinista
(misma entrada, mismos bytes; sin fechas). Escribe:

- `NationsRTS/MAPA-DEL-CODIGO.md`: índice general, una línea por módulo
  (líneas, funciones públicas, propósito) y las dependencias entre carpetas.
- `NationsRTS/mapa/<carpeta>.md`: por módulo, propósito, `require` y funciones
  públicas con firma, línea y descripción. Carpetas: raíz, mundo, batalla,
  interfaz, runtime, depurar, ui, scripts.

Quedan fuera los datos generados y las librerías (`assets/`, `lib/`, `gooi/`,
`build/`, `dist/`, `maps/`) y las carpetas `pruebas_*`.

## LDoc

LDoc 1.5 (instalable con `luarocks --lua-version 5.4 --local install ldoc`;
con Lua 5.5 falla) solo documenta lo que lleva comentarios `---`, produce
HTML y solo saca Markdown de un módulo por ejecución. Los archivos que usan
`--` corriente se ignoran. Por eso el mapa lo genera el script propio, que
lee los comentarios existentes tal como están.

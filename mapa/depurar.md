# Mapa de `depurar/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## depurar/arnes_registro.lua

Arnés sin LÖVE: crea el mundo de una semilla (5 x 5 zonas de naciones alrededor del origen), avanza días con el registro puesto y dice lo que cuesta. Desde la carpeta de NationsRTS:

- Tamaño: 158 líneas, 0 funciones públicas, 2 locales.
- Usa: depurar/registro, mundo/ciudades, mundo/recursos, mundo/simulacion, mundo/terreno

## depurar/mundo_prueba.lua

Mundo de prueba sin LÖVE: crea la simulación de una semilla con sus zonas registradas, como en el juego.

- Tamaño: 78 líneas, 1 funciones públicas, 1 locales.
- Usa: mundo/ciudades, mundo/recursos, mundo/simulacion, mundo/terreno

- `MundoPrueba.crear(s, zonasPorLado)` (l.26) — Simulación de la semilla `s`, su `sitioValido` y su `transitable`, con `zonasPorLado` x `zonasPorLado` zonas (5 si no se da) alrededor del origen.

## depurar/registro.lua

Registro para el agente que mira el juego: escribe en JSONL (una línea JSON por evento) lo que pasa en la simulación, para cruzarlo con las capturas y con los errores. Lo lee `tools/analizar_registro.py`.

- Tamaño: 939 líneas, 26 funciones públicas, 11 locales.
- Usa: mundo/simulacion

- `Registro.json(v)` (l.124) — Texto JSON de un valor (claves en orden fijo).
- `Registro.canalesDe(texto)` (l.131) — Conjunto de canales de un texto 'simulacion,captura' (vacío: el de por defecto).
- `Registro.canalesDeArgumentos(arg)` (l.145) — Canales pedidos con `--registro [canales]` en los argumentos, o nil si no se pidió. Si no se dicen, 'simulacion'.
- `Registro.nuevo(opciones)` (l.167) — Registro nuevo. `opciones`: ruta archivo de salida (los cortes se llaman ruta_2, ruta_3...), o carpeta carpeta donde crear `<fecha>_<semilla>.jsonl`…
- `Registro:rutaActual()` (l.192)
- `Registro:abrir()` (l.199)
- `Registro:activo(canal)` (l.213)
- `Registro:cuadro()` (l.218) — Cuenta un cuadro (el juego lo llama una vez por love.update).
- `Registro:dia()` (l.222)
- `Registro:escribir(canal, tipo, datos)` (l.227) — Escribe una línea: `t`, `dia`, `cuadro`, `canal`, `tipo` y los datos.
- `Registro:volcar()` (l.256)
- `Registro:cerrar()` (l.262)
- `Registro:accion(c, r, motivo)` (l.337)
- `Registro:resumenDia()` (l.391)
- `Registro:cambiosDia()` (l.561) — Cambios del día que no pasan por un método envuelto: guerras que empiezan, cambian de fase o terminan, minas que se reabren y obras terminadas.
- `Registro:batalla(bid)` (l.624)
- `Registro:grupoEntra(b, g, lado)` (l.633)
- `Registro:grupoSale(b, g, como, tropas)` (l.640)
- `Registro:batallaEmpieza(b)` (l.649)
- `Registro:batallaTermina(b, ganador)` (l.673)
- `Registro:vigilar(sim)` (l.719) — Empieza a vigilar `sim` (una vez por instancia): envuelve sus métodos.
- `Registro:minaAgotada(d, grupos)` (l.847)
- `Registro:seguir(sim)` (l.863) — Para el juego: vigila la simulación viva si ha cambiado (partida nueva o cargada).
- `Registro:error(mensaje, traza)` (l.872) — Guarda un error con su traza y un resumen del estado. Nunca lanza.
- `Registro:proteger(fn, ...)` (l.903) — Corre `fn` y, si falla, guarda el error antes de volver a lanzarlo (para los arneses).
- `Registro:captura(datos)` (l.918) — Marca de una captura: `datos` = { archivo, camara = { x, y, zoom }, modo }.


# Mapa de la raíz de NationsRTS

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## conf.lua

(sin comentario de cabecera)

- Tamaño: 17 líneas, 1 funciones públicas, 0 locales.

- `love.conf(t)` (l.1)

## main.lua

Nations RTS: un mundo procedural infinito en isométrico.

- Tamaño: 3752 líneas, 38 funciones públicas, 56 locales.
- Usa: batalla/dream/calidad, batalla/dream/escena, batalla/escena, build.check_grupo_nuevo, build.check_rts, build.check_visual, build.test-ejercito, depurar/registro, interfaz/acero, interfaz/ajustes, interfaz/arsenal, interfaz/barrasuperior, interfaz/batallas, interfaz/columna, interfaz/ejercito, interfaz/envio, interfaz/explorar, interfaz/fabrica, interfaz/ficha, interfaz/galeria, interfaz/inteligencia, interfaz/navegacion, interfaz/noticias, interfaz/opciones, interfaz/pendon, interfaz/perfil, interfaz/placa, interfaz/plantar, interfaz/pregon, interfaz/radial, interfaz/tema, mundo/choques, mundo/iso, mundo/modelos3d, mundo/mundo, mundo/simulacion

- `love.load(arg)` (l.307)
- `prepararAsaltoParaCaptura()` (l.735) — Modo de captura `asalto`: manda el ataque (un comando, como lo haría un presidente) y deja la cámara y el panel en la ciudad que lo mandó.
- `buscarBaseParaCaptura()` (l.784) — Modo de captura `base`: busca la primera base terminada con lanzacohetes, pone la cámara en ella a velocidad normal y abre su panel.
- `buscarRetiradaParaCaptura()` (l.814) — Modos de captura `retirada`, `vuelta`, `recuperacion` y `ataque`: busca lo que hay que fotografiar y, si lo encuentra, pone la cámara ahí y el…
- `capturaRecoleccion()` (l.1076) — Modos de captura de recolección y batallas (ver `--captura`).
- `love.update(dt)` (l.1325)
- `trayectoExplorador(sim, e)` (l.1653) — Dónde va un explorador de `sim:exploradoresEnCamino`: su punto de ahora y el de su objetivo (del mundo).
- `love.draw()` (l.1733)
- `love.wheelmoved(_, dy)` (l.1915)
- `entrarEnBatalla(combate)` (l.1957) — Entra en la escena de batalla de un combate (nil: no hace nada). Sin `enEscena`, solo se mira (observador o prueba): al salir no cambia nada.
- `entrarEnBatallaSim(bid)` (l.1973) — Entra en 3D en la batalla `bid` de la simulación (modo jugador): el comando `entrarBatalla` la congela y da su estado; la escena se arma con lo sano…
- `salirDeBatalla()` (l.1994) — Sale de la escena 3D. Si era una batalla de la simulación, lo que pasó en ella vuelve unidad por unidad con `resolverBatalla` (muertos, heridos,…
- `nombreSitio(sim, s)` (l.2046) — Nombre de un sitio de la simulación: el de la ciudad o, si es una instalación, «una base militar de <nación>» (o la que sea).
- `botonesMina(id)` (l.2104) — Botones del pendón de un yacimiento en modo jugador: «Recolectar» (desde tu ciudad o campamento más cercano; abre el envío en modo recolectar) y, si…
- `botonesFicha(gid)` (l.2183) — Botones de la ficha de un grupo (y el aviso que va encima), modo jugador: - tuyo en una batalla: «Entrar en la batalla»; - tuyo fuera de casa:…
- `abrirAtaque(objetivo)` (l.2285) — Abre el envío contra `objetivo` (sitio de otra nación, datos de la simulación) desde tu sitio con tropa más cercano; con ‹ › se elige otro.
- `botonesInstalacion()` (l.2304) — Botones de órdenes del pendón de una instalación: ninguno (para atacar se va al objetivo: menú radial o ejército elegido).
- `botonesCiudad(ciudad)` (l.2311) — Botones de órdenes del pendón de una ciudad en modo jugador: en tu capital, plantar bandera.
- `objetivoRadial()` (l.2333) — Objetivo del radial abierto: el sitio (o la mina) de la simulación, o nil si ya no existe.
- `filasEconomia(sim, c, filas)` (l.2445) — Filas de la tarjeta del radial de tu ciudad (economía cerrada): cada tropa con su tope (lo de la ciudad, también fuera o en fábrica, contra el tope…
- `opcionesRadial()` (l.2735) — Opciones del radial abierto (nil si su objetivo ya no existe).
- `accionRadial(clave)` (l.2765) — Aplica el botón `clave` del radial abierto.
- `mandarComandos(comandos)` (l.2827) — Manda a la simulación los comandos del panel de encargo abierto (uno por munición, o el de «Reparar» o «Sacar ya» del taller).
- `mandarArsenal(comandos)` (l.2861) — Manda los comandos del Arsenal («Producir» o «Cancelar» una orden) y le dice cómo fue.
- `mandarAtaque()` (l.2923) — Manda lo elegido en el envío (un ataque o una recolección): si hace falta guerra con el dueño del objetivo, primero la declara (comando…
- `vigilarBatallas()` (l.2986) — Modo jugador (diseno/recoleccion-y-batallas.md, 3.8): - un día antes de que llegue un ataque contra algo tuyo (`avisosAtaque`), un aviso con «Ir»…
- `abastecerGrupo(gid, mandar)` (l.3082) — ¿Se puede mandar un convoy de munición al grupo propio `gid`? Sale de tu ciudad más cercana con lo que le falta hasta `dotacion.atacar` días de…
- `pulsarFicha(accion)` (l.3131) — Acción de un botón de la ficha de un grupo (ver `botonesFicha`).
- `combateProvocadoLejano(x, y)` (l.3378) — Combate de prueba cuando no hay ninguna ciudad de otra nación a la vista (la cámara arranca pegada a una capital): la ciudad más cercana a (x, y)…
- `buscarBatallaEnVivo(dt)` (l.3406) — `--batalla-vivo`: en cuanto se ven ciudades, entra en el combate real más cercano o, si no hay ninguno, en uno de prueba (ver…
- `abrirRadial(objetivo, x, y)` (l.3433) — Abre el menú radial sobre `objetivo` (en el punto x, y del mundo): cierra los paneles de sitio y, si el objetivo queda muy al borde, la cámara se…
- `love.mousepressed(x, y, boton)` (l.3461)
- `love.mousemoved(x, y, dx, dy)` (l.3553)
- `love.mousereleased(x, y, boton)` (l.3573) — Suelta del botón. El izquierdo termina el cuadro de selección o, si fue un clic sin arrastre con una selección, la manda a ese punto; el derecho, si…
- `love.focus(enfocada)` (l.3601) — Libera la captura del ratón de batalla al cambiar de ventana.
- `love.textinput(texto)` (l.3608) — Texto escrito: solo lo usa el buscador del arsenal.
- `love.keypressed(tecla)` (l.3612)
- `love.errorhandler(mensaje)` (l.3746)

## project.lua

(sin comentario de cabecera)

- Tamaño: 40 líneas, 0 funciones públicas, 0 locales.


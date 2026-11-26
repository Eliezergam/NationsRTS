# Mapa de `interfaz/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## interfaz/acero.lua

Acero: los componentes de la interfaz militar sobre el kit gráfico de `assets/ui/` (diseno/interfaz-militar.md, §4): panel 9-slice, botón con estados, barra, icono teñido, pestaña, fila de lista, insignia y ayuda.

- Tamaño: 712 líneas, 31 funciones públicas, 3 locales.
- Usa: assets.ui.indice, interfaz/paleta, interfaz/tema

- `Acero.fuente(estilo, tamano)` (l.35) — Fuente de un estilo del diseño (`titulo`, `cuerpo`, `cifra`…). `reduccion` (opcional) los baja a ese tamaño de diseño.
- `Acero.px(valor)` (l.41) — Una medida de diseño en píxeles de pantalla.
- `Acero.color(nombre, alfa)` (l.46) — Pone un color de la paleta (o uno dado como tabla) con su opacidad.
- `Acero.pieza(nombre, estado, x, y, w, h, alfa)` (l.66) — Dibuja una pieza de tamaño fijo del kit estirada al rectángulo (x, y, w, h).
- `Acero.nueve(nombre, estado, x, y, w, h, alfa)` (l.105) — Dibuja una pieza 9-slice del kit en el rectángulo (x, y, w, h) de pantalla.
- `Acero.levantar(x, y, w, h, alfa)` (l.136) — Levanta un rectángulo oscuro del kit hacia el caqui del HUD: una capa de `lineaOliva` con `alfa` (0,5 en los paneles).
- `Acero.contenido(nombre, x, y, w, h)` (l.143) — Relleno interior de una pieza (su `contenido`, ya en píxeles): { x, y, w, h }.
- `Acero.puntosCortados(x, y, w, h, cortes)` (l.155) — Puntos de un rectángulo con esquinas cortadas en diagonal. `cortes` = { arribaIzq, arribaDer, abajoDer, abajoIzq } (0: esquina recta).
- `Acero.placa(x, y, w, h, corte, relleno, borde, alfa)` (l.190) — Rectángulo con las cuatro esquinas cortadas, relleno y con borde de 1 px.
- `Acero.sombra(x, y, w, h)` (l.205) — Sombra de panel (§3.5): tres rectángulos negros desplazados hacia abajo.
- `Acero.panel(x, y, w, h, opciones)` (l.221) — Panel de acero con sombra. Con `titulo` lleva la cabecera de 48 (título a la izquierda y, si `cerrar`, el botón de cierre).
- `Acero.fondoPanel(x, y, w, h)` (l.280) — Fondo de un panel sin cabecera: gris caqui claro en `Tema.modoClaro` o el oliva del kit levantado.
- `Acero.panelClaro(x, y, w, h)` (l.296) — Panel de contenido gris claro (formularios, perfil, opciones).
- `Acero.chip(x, y, w, h, alfa)` (l.302) — Placa oscura pequeña (chips de recurso, cifras, contadores).
- `Acero.rotulo(x, y, w, h)` (l.314) — Rótulo translúcido (nombres sobre el mapa, avisos ligeros).
- `Acero.separador(x, y, w)` (l.319) — Filete horizontal que separa filas de un panel.
- `Acero.icono(nombre, x, y, lado, color, alfa)` (l.326) — Icono del kit teñido con un color de la paleta, cuadrado de `lado` px.
- `Acero.iconoColor(nombre, x, y, lado, alfa)` (l.339) — Icono a color del kit (`Indice.iconosColor`: metal, petróleo, comida, dinero, poder), cuadrado de `lado` px, sin teñir.
- `Acero.boton(boton, x, y, w, h, compacto)` (l.378) — Botón (§4). `boton` = { texto, tipo, activo, precio, icono, estado }; `estado` (opcional) lo fuerza, para la galería; `tipo`: 'dorado' (o…
- `Acero.anchoBoton(boton, compacto)` (l.445) — Ancho que pide un botón con su texto, su icono y su precio.
- `Acero.botonCerrar(x, y, lado)` (l.460) — Botón cuadrado de cierre (la X del kit). Devuelve si el ratón está encima.
- `Acero.textoContorno(fuente, texto, x, y, color, contorno, alfa, grosor)` (l.473) — Texto con contorno (blanco sobre el mapa, familia oliva): se dibuja ocho veces con el color del contorno, desplazado, y una con el color del texto.
- `Acero.insignia(cx, cy, cuenta)` (l.488) — Insignia roja con un número (cuenta de avisos), centrada en (cx, cy), con la pieza del kit.
- `Acero.insigniaNuevo(x, y, texto)` (l.516) — Pastilla roja «Nuevo» (o un aviso de texto corto), con su esquina superior derecha en (x, y).
- `Acero.hexagono(x, y, ancho, opciones)` (l.535) — Hexágono de metal (`hexagono_icono`) de `ancho` px de ancho con su icono y, debajo, la etiqueta blanca con contorno y la insignia roja.
- `Acero.botonIcono(x, y, w, h, opciones)` (l.583) — Botón de icono con etiqueta debajo (columna izquierda y barra de abajo): un hexágono que cabe en el rectángulo (x, y, w, h) con su etiqueta.
- `Acero.pestana(x, y, w, h, texto, activa, pendiente)` (l.594) — Pestaña: `activa` lleva el fondo de selección y el filete dorado. Devuelve si el ratón está encima.
- `Acero.barra(x, y, w, h, parte, tipo, pendiente)` (l.643) — Barra: canal oscuro del kit con el relleno de un tipo (`energia` verde, `recurso` dorado, `peligro` rojo, `estadistica`, `experiencia`) hasta la…
- `Acero.fila(x, y, w, h, estado, clara)` (l.662) — Fila de lista: `estado` = 'normal', 'hover' o 'seleccionada'; `clara` para las de contenido claro.
- `Acero.desplazamiento(x, y, alto, visible, total, posicion)` (l.681) — Barra de desplazamiento fina (6 px) para el tramo (x, y, alto).
- `Acero.tooltip(texto, mx, my, anchoMax)` (l.695) — Ayuda junto al puntero (§4): `abismo` al 96 % con borde dorado y esquinas cortadas, metida en la pantalla.

## interfaz/ajustes.lua

Ajustes del jugador (diseno/interfaz-militar.md, §5.15): calidad gráfica, pantalla, sincronización vertical, FPS, sombras, oclusión y volúmenes.

- Tamaño: 200 líneas, 7 funciones públicas, 0 locales.
- Usa: batalla/dream/calidad

- `Ajustes.copiar(v)` (l.49) — Copia de una tabla de valores.
- `Ajustes.cargar()` (l.61) — Lee el archivo de ajustes (si existe y es válido) sobre los de fábrica.
- `Ajustes.guardar(v)` (l.89) — Guarda los ajustes.
- `Ajustes.resoluciones()` (l.103) — Resoluciones que ofrece el sistema, de menor a mayor (sin repetir), y la actual si no está entre ellas.
- `Ajustes.personalizada(v)` (l.126) — ¿Los sombreados y la oclusión son los del nivel? Si no, «Personalizada».
- `Ajustes.alNivel(v, nombre)` (l.132) — Rellena sombras y oclusión con los valores de un nivel de calidad.
- `Ajustes.aplicar(v, conVentana)` (l.144) — Pone en marcha los valores: calidad de la batalla, volumen y, si `conVentana`, el modo de ventana.

## interfaz/arsenal.lua

Arsenal (diseno/interfaz-militar.md, §6.2 y las referencias de `diseno/referencias-arsenal/`): pantalla completa de la familia oscura con dorado.

- Tamaño: 1228 líneas, 22 funciones públicas, 9 locales.
- Usa: assets.ui.indice, interfaz/acero, interfaz/clara, interfaz/fabrica, interfaz/tema, mundo/simulacion

- `Arsenal.nuevo()` (l.92)
- `Arsenal:abrir(ciudad)` (l.111) — Abre el arsenal; con `ciudad` (id), fabricando en ella.
- `Arsenal:ciudadElegida(sim, nid)` (l.123) — Ciudad tuya que fabrica: la elegida si sigue siendo tuya o tu capital (o la primera). Devuelve la ciudad y la lista de tus ciudades.
- `Arsenal:resultado(ok, texto)` (l.138) — Resultado de mandar los comandos de `pulsar` (main.lua lo llama).
- `Arsenal:cerrar()` (l.142)
- `Arsenal:arte(unidad, cual)` (l.148) — Imagen de arte de una unidad (se carga una vez). La munición, la de su tropa.
- `Arsenal:datos(sim, nid)` (l.216) — Datos vivos de cada unidad (poder, fuerza, existencias, recuperación) y de la ciudad que fabrica (inventario, topes, polvorín y cola).
- `Arsenal:zona(x, y, w, h, accion, dato)` (l.256) — Zona que se puede pulsar en este cuadro.
- `Arsenal:lista(datos)` (l.291) — Lista filtrada y ordenada de unidades.
- `Arsenal:dibujarPestanas(x, y, alto)` (l.337) — Pestañas de arriba: solo «Arsenal» existe hoy.
- `Arsenal:dibujarCategorias(x, y, w, h, alto)` (l.356) — Lista de categorías con su contador.
- `Arsenal:dibujarTarjeta(u, d, x, y, w, h)` (l.425) — Tarjeta de una unidad.
- `Arsenal:dibujarSelectorCiudad(x, y, w, h, sim, nid)` (l.491) — Selector de la ciudad que fabrica: «Fábrica de» ‹ Casa · nv. 2 ›.
- `Arsenal:dibujarCola(x, y, w, h, datos, sim)` (l.527) — Cola de fábrica de la ciudad elegida, con «Cancelar» en cada orden.
- `Arsenal:dibujarCentro(x, y, w, h, datos, sim, nid)` (l.656) — Rejilla del centro con encabezado, buscador, orden, ciudad y la cola.
- `Arsenal:dibujarDetalle(x, y, w, h, datos, sim, nid)` (l.815) — Detalle de lo elegido.
- `Arsenal:dibujarDoctrina(x, y, w, h, sim, nid)` (l.1031) — Tarjeta de doctrina: la orden política de la nación (abajo a la izquierda).
- `Arsenal:dibujar(ctx)` (l.1059) — Dibuja el arsenal. `ctx` = { sim, nacion }.
- `Arsenal:dibujarAyuda()` (l.1102)
- `Arsenal:texto(t)` (l.1110) — Texto escrito (buscador).
- `Arsenal:tecla(tecla)` (l.1117) — Tecla pulsada. Devuelve true si el arsenal la usó.
- `Arsenal:pulsar(x, y)` (l.1143) — Clic. Devuelve `cerrar`, `nada` o { comandos = { … } } (producir o cancelar una orden: los manda main.lua y avisa con `resultado`).

## interfaz/barrasuperior.lua

Barra superior (diseno/interfaz-militar.md, §5.1): a la izquierda la chapa de la nación (escudo, nombre, poder y nivel), en el centro los cuatro recursos (metal, petróleo, comida y dinero) y a la derecha el día con la pausa y…

- Tamaño: 379 líneas, 12 funciones públicas, 3 locales.
- Usa: interfaz/acero, interfaz/tema, mundo/estandartes, mundo/simulacion

- `BarraSuperior.nuevo()` (l.26)
- `BarraSuperior.alto()` (l.35) — Alto que ocupa, para colgar el resto debajo.
- `BarraSuperior:datos(sim, nid)` (l.45) — Poder y reservas de la nación, refrescados cada `REFRESCO` segundos.
- `BarraSuperior:dibujarRecurso(d, x, y, w, h)` (l.104) — Una casilla de recurso: pastilla oliva inclinada con el icono de color, la cifra grande (blanca con contorno; `amarilloDinero` la del dinero), una…
- `BarraSuperior:dibujarChapa(ctx, x, y, w, h)` (l.156) — Chapa de la nación: el anillo del kit con el escudo dentro y, al lado, el nombre, el poder y el nivel de la capital sobre un rótulo oliva.
- `BarraSuperior:dibujarTiempo(ctx, derecha, y, h)` (l.206) — Día y velocidades, de derecha a izquierda desde `derecha`. Devuelve el x donde empieza el bloque.
- `BarraSuperior:dibujar(ctx)` (l.253) — Dibuja la barra. `ctx` = { sim, semilla, pausa, velocidad, velocidades, nacion (id de la nación que se mira o se juega) }.
- `BarraSuperior:dibujarRecursos(ctx, desde, hasta)` (l.277) — Los cuatro recursos, centrados en la pantalla y, si chocan, arrimados al hueco libre entre la chapa (termina en `desde`) y el tiempo (empieza en…
- `BarraSuperior:dibujarObservador(ctx, desde, hasta)` (l.331) — Sin jugador: la nación que se mira no existe; se cuenta el estado del mundo.
- `BarraSuperior:dibujarAyuda()` (l.356) — La ayuda del botón o recurso bajo el ratón (se dibuja encima de todo).
- `BarraSuperior:encima(_, y)` (l.364) — ¿El punto cae sobre la barra?
- `BarraSuperior:pulsar(x, y)` (l.369) — Clic: devuelve la tecla del botón pulsado (o nil).

## interfaz/batallas.lua

Batallas en curso: la lista de las batallas en las que pelea tu nación (diseno/interfaz-militar.md, §5.9). Se abre con el botón de la barra de abajo (o B), a la derecha bajo la barra superior.

- Tamaño: 199 líneas, 5 funciones públicas, 1 locales.
- Usa: interfaz/acero, interfaz/inteligencia, interfaz/tema

- `Batallas.nuevo()` (l.18)
- `Batallas:dibujar(sim, nid, arriba, derecha)` (l.41) — Dibuja la lista bajo la barra superior (`arriba`), con su borde derecho en `derecha` (o a 16 px del borde de la pantalla).
- `Batallas:rueda(x, y, dy)` (l.162) — Rueda sobre la lista: la desplaza. Devuelve true si la usó.
- `Batallas:pulsar(x, y)` (l.175) — Clic: nil si cayó fuera; si no, la acción ({ tipo = 'entrar', batalla }, { tipo = 'ir', x, y }, { tipo = 'cerrar' }) o { tipo = 'nada' }.
- `Batallas:primeraEntrada()` (l.189) — La acción del primer botón «Defender» o «Atacar» activo (para las capturas).

## interfaz/clara.lua

Familia clara (hormigón) de la interfaz militar (diseno/interfaz-militar.md, §3.3b): fondo de hormigón, cabecera con la placa negra del logo, placas de datos, botones anchos con icono y los controles de formulario (desplegable,…

- Tamaño: 285 líneas, 12 funciones públicas, 0 locales.
- Usa: assets.ui.indice, interfaz/acero, interfaz/tema

- `Clara.textoSombra(fuente, texto, x, y, color)` (l.18) — Texto con sombra negra de 2 px abajo y a la derecha (títulos sobre hormigón).
- `Clara.fondo()` (l.30) — Fondo de pantalla completa: la textura de hormigón en mosaico, aclarada para acercarla al `hormigon` del diseño.
- `Clara.anchoPastilla(alto, cifra)` (l.87) — Ancho de la pastilla de recurso sencilla para una cifra.
- `Clara.pastilla(x, y, alto, tipo, cifra)` (l.95) — Pastilla de recurso sencilla (cabecera de las pantallas): icono de color y cifra blanca con contorno. Devuelve el ancho que ocupa.
- `Clara.cabecera(titulo, recursos)` (l.115) — Cabecera de pantalla: placa negra del logo a la izquierda (un clic vuelve), el título con sombra y, a la derecha, los recursos.
- `Clara.placaDato(x, y, w, h, valor, etiqueta, icono)` (l.143) — Placa de dato: el valor grande negro arriba, la etiqueta gris debajo y, a la derecha y muy tenue, un icono opcional. Devuelve si el ratón está encima.
- `Clara.filaOpcion(x, y, w, h, texto, icono, opciones)` (l.168) — Botón ancho de menú (`fila_opcion`): icono negro a la izquierda y texto negro. `opciones` = { nuevo, desactivado, estado }.
- `Clara.desplegable(x, y, w, h, texto, abierto)` (l.199) — Desplegable cerrado (`desplegable`) con el valor elegido. Devuelve si el ratón está encima.
- `Clara.interruptor(x, y, w, h, encendido, desactivado)` (l.214) — Interruptor (`interruptor`) de 44×22 escalado a `w`×`h`. Devuelve si el ratón está encima.
- `Clara.deslizador(x, y, w, valor, desactivado)` (l.226) — Deslizador de 0 a 1 con el pomo. Devuelve si el ratón está encima.
- `Clara.hexagonoPlano(cx, cy, r, relleno, borde)` (l.246) — Hexágono plano (vértice arriba) centrado en (cx, cy), de radio `r`, con relleno y borde de colores de la paleta (medallas vacías).
- `Clara.recursosDe(sim, nid)` (l.264) — Los cuatro recursos de una nación para la cabecera: { tipo, cifra } de metal, petróleo, comida y dinero (solo lee la simulación).

## interfaz/columna.lua

Columna de iconos de la izquierda (diseno/interfaz-militar.md, §6.1): las acciones del mapa, un hexágono de 72 de ancho con su etiqueta y, si hay algo pendiente, una insignia roja. Son hexágonos de metal (`hexagono_icono`).

- Tamaño: 110 líneas, 6 funciones públicas, 0 locales.
- Usa: interfaz/acero, interfaz/tema

- `Columna.nuevo()` (l.35)
- `Columna.ancho()` (l.44) — Ancho que ocupa la columna con su margen, para colocar lo demás a su derecha.
- `Columna:dibujar(ctx, arriba)` (l.51) — Dibuja la columna bajo la barra superior (`arriba`, en píxeles).
- `Columna:dibujarAyuda()` (l.82)
- `Columna:encima(x, y)` (l.90) — ¿El punto cae sobre un botón de la columna?
- `Columna:pulsar(x, y)` (l.100) — Clic: devuelve la tecla del botón pulsado (o nil).

## interfaz/ejercito.lua

Ejército: selección y movimiento de ejércitos sobre el mapa, como en Warpath. Las fichas son los grupos de la simulación.

- Tamaño: 1022 líneas, 28 funciones públicas, 20 locales.
- Usa: interfaz/acero, interfaz/plantar, interfaz/tema, mundo/iso, mundo/simulacion

- `Ejercito.nuevo()` (l.37)
- `Ejercito:reiniciar()` (l.44) — Deja todo como al empezar (mundo nuevo).
- `Ejercito:cuantos()` (l.60)
- `Ejercito:primero()` (l.64)
- `Ejercito:tiene(gid)` (l.68)
- `Ejercito:limpiar()` (l.77)
- `Ejercito:poner(ids)` (l.83)
- `Ejercito:sumar(ids)` (l.93)
- `Ejercito:alternar(gid)` (l.102)
- `Ejercito:grupoDe(mundo, camara, jugador, gid)` (l.188) — Todas las fichas propias dentro del círculo de acción de la ficha `gid` (lo que se ve dentro de su círculo, aunque sean vehículos o soldados).
- `Ejercito:pulsar(mundo, camara, jugador, x, y, suma)` (l.207) — Clic izquierdo en el mapa. Devuelve 'ficha' si eligió (o quitó) una ficha propia, 'orden' si hay selección (el clic se resuelve al soltar: mandar…
- `Ejercito:mover(x, y)` (l.253) — El ratón se mueve con el botón izquierdo apretado: pasado el umbral, es un cuadro.
- `Ejercito:soltar(mundo, camara, jugador, x, y)` (l.268) — Suelta el botón izquierdo. Con cuadro, elige las fichas propias de dentro; sin él (un clic) y con selección, la manda a ese punto.
- `Ejercito:elegirCaja(mundo, camara, jugador, x0, y0, x1, y1, suma)` (l.297) — Elige las fichas propias cuyo pie o cuyo estandarte caen en el cuadro.
- `Ejercito:todas(mundo, jugador)` (l.322) — Ctrl+A: todas las fichas propias.
- `Ejercito:tocar(vx, vy, tipo)` (l.327) — Un toque en pantalla en el punto (vx, vy) de la vista.
- `Ejercito:avisar(texto)` (l.334)
- `Ejercito.destinoEn(mundo, vx, vy)` (l.342) — Lo que hay bajo el punto (vx, vy) de la vista: una mina, una instalación, una ciudad o el suelo. { tipo, x, y, sitio, nombre } (x, y del mundo).
- `Ejercito:ordenar(mundo, camara, jugador, x, y)` (l.379) — Manda la selección al punto (x, y) de la pantalla. Usa las acciones de la simulación: `redirigir` a un sitio propio, `irAPunto` en cualquier otro…
- `Ejercito:retirar(mundo, jugador)` (l.442) — Retira a casa las fichas seleccionadas.
- `Ejercito:actualizar(dt, mundo, jugador)` (l.455) — Cada cuadro: envejece los toques y avisos, y olvida los grupos que ya no existen.
- `Ejercito:dibujarMapa(mundo, camara)` (l.696) — Todo lo que va sobre el mapa (se llama tras el mundo, en pantalla): caminos, círculo de acción, resplandor de cada ficha, toques y cuadro de…
- `Ejercito:resumen(mundo)` (l.770) — Suma de lo seleccionado: soldados, tanques, lanzacohetes, heridos y poder.
- `Ejercito:estado(mundo)` (l.788) — Qué hace lo seleccionado: «En marcha · 4,2 km · 3 d», «En posición»…
- `Ejercito:dibujarPanel(mundo, jugador, noticias, pendon, reserva)` (l.836) — Panel de abajo: cabecera, una tarjeta por tipo de tropa y los botones de orden.
- `Ejercito:dibujarPanelClaro(mundo, jugador, noticias, pendon, reserva)` (l.846)
- `Ejercito:dibujarAyuda()` (l.957) — Aviso y ayudas del panel (encima de todo lo demás).
- `Ejercito:pulsarPanel(mundo, jugador, x, y)` (l.1000) — Clic en el panel: true si lo usó (aunque no fuera en un botón).

## interfaz/envio.lua

Envío: la elección sencilla de cuánto llevar a un ataque o a recolectar (modo jugador). Un panel al centro con una fila por tropa (tanques, lanzacohetes y soldados) con − y +, lo que hay en la ciudad, y los botones «Atacar» (o…

- Tamaño: 588 líneas, 16 funciones públicas, 0 locales.
- Usa: interfaz/acero, interfaz/tema, mundo/estandartes, mundo/simulacion

- `Envio.nuevo(desde, objetivo, nombre, opciones)` (l.48) — Abre el envío desde la ciudad `desde` (datos de la simulación) contra `objetivo` (una ciudad o una instalación de otra nación, o un yacimiento de…
- `Envio:usarOrigen(desde)` (l.84) — Sale desde `desde`: lo propuesto vuelve a ser la mitad de lo que hay.
- `Envio:hay(clave)` (l.95) — Lo que hay en la ciudad de cada tropa.
- `Envio:total()` (l.100) — Unidades elegidas, de todas las tropas.
- `Envio:municion(sim)` (l.111) — Munición que se llevaría con lo elegido: { quiere = { balas, obuses, misiles } (los días elegidos), lleva = (recortado al polvorín), hay = (el…
- `Envio:haceFaltaGuerra(sim)` (l.125) — ¿Hay que declarar la guerra al dueño del objetivo antes de atacar? En una mina no: la simulación la declara al llegar (decisión 3 del dueño).
- `Envio:recolectoresAjenos(sim)` (l.133) — Naciones que recolectan en la mina del objetivo, sin la tuya.
- `Envio:declaraGuerraEnMina(sim)` (l.145) — ¿Atacar la mina declara la guerra a alguien (recolectores en paz contigo)?
- `Envio:estimacion(sim)` (l.158) — Estimación de una recolección con lo elegido: { capacidad, ritmo (al día), viaje (días de ida), llenar (días en la mina), total (días hasta volver)…
- `Envio:motivoDiplomatico(sim)` (l.182) — Por qué no se puede atacar al dueño del objetivo (sitio que ya no existe o ya es tuyo, alto el fuego o tregua vigentes), o nil.
- `Envio:motivoPrevio(sim)` (l.233) — Por qué no saldría el ataque, o nil si puede salir (lo mismo que mira la simulación, para decirlo antes de mandar).
- `Envio:dibujar(sim)` (l.249) — Dibuja el panel en el centro de la pantalla.
- `Envio:dibujarClaro(sim)` (l.259)
- `Envio:dibujarMunicion(sim, cx, cy, cw, fila, lado)` (l.450) — Fila «Munición» (días de batalla, con − y +) y, debajo, cuánto es de cada una y lo que hay en el polvorín. Devuelve la `y` siguiente.
- `Envio:pulsar(x, y)` (l.516) — Clic. Devuelve nil si cayó fuera del panel; si no, 'atacar', 'cancelar' o 'nada' (los − y + se aplican aquí).
- `Envio:comando()` (l.547) — El comando con lo elegido: `recolectar` o `enviarGrupo` (atacar).

## interfaz/explorar.lua

Explorar: el panel para mandar exploradores a un sitio o a un ejército ajeno (modo jugador). Se elige desde qué sitio propio salen (el más cercano por defecto, con ‹ y ›) y se ve lo que cuesta y cuándo llegan.

- Tamaño: 247 líneas, 11 funciones públicas, 0 locales.
- Usa: interfaz/acero, interfaz/tema, mundo/simulacion

- `Explorar.textoDistancia(px)` (l.21) — Distancia (px de mundo) como texto: «12,4 km» o «350 m» (10 px = 1 m).
- `Explorar.origenes(sim, nid, x, y)` (l.32) — Sitios propios de `nid` desde donde pueden salir exploradores, del más cercano a (x, y) al más lejano: ciudades e instalaciones terminadas (sin…
- `Explorar.nuevo(sim, nid, objetivo)` (l.51) — Abre el panel: `nid` explora `objetivo` = { id, x, y, nombre } (un sitio o un grupo ajeno).
- `Explorar:origen()` (l.63) — El sitio elegido de salida (y su distancia), o nil.
- `Explorar.textoCoste(coste)` (l.69) — Coste de la exploración como texto: «40 dinero» o «10 metal · 5 petróleo».
- `Explorar:dias()` (l.87) — Días que tardan en llegar desde el origen (en línea recta, a la velocidad de los exploradores), o nil si no se sabe.
- `Explorar:motivoPrevio()` (l.98) — Por qué no se puede mandar, o nil.
- `Explorar:dibujar(sim)` (l.108)
- `Explorar:dibujarClaro(sim)` (l.117)
- `Explorar:pulsar(x, y)` (l.215) — Clic: nil si cayó fuera; si no, 'enviar', 'cancelar' o 'nada' (‹ y › se aplican aquí).
- `Explorar:comando()` (l.236) — El comando `explorar` con lo elegido.

## interfaz/fabrica.lua

Fábrica: el panel pequeño de encargo que abre el radial de tu ciudad (decisión del dueño: en el 2D solo «Crear soldados» y «Producir munición»; lo demás, desde el Arsenal).

- Tamaño: 750 líneas, 19 funciones públicas, 2 locales.
- Usa: interfaz/acero, interfaz/tema, mundo/simulacion

- `Fabrica.textoDias(dias)` (l.59) — «1 día», «4 días».
- `Fabrica.textoMotivo(sim, nid, cid, tropa, cantidad, motivo)` (l.78) — Texto de por qué `sim:puedeProducir` no deja encargar `cantidad` de `tropa` en la ciudad `cid` de `nid`.
- `Fabrica.anchoCoste(coste, fuente)` (l.119) — Ancho del coste dibujado con `dibujarCoste`.
- `Fabrica.dibujarCoste(coste, x, y, fuente, falta)` (l.135) — Dibuja un coste { dinero, metal, petroleo } como «[icono] 30 [icono] 3…» desde (x, y). Los recursos que no alcanzan (`falta[recurso]`) van en rojo.
- `Fabrica.falta(n, coste)` (l.159) — Recursos de `coste` que la nación `n` no tiene: { dinero = true, … }.
- `Fabrica.reparacionVida(n, c)` (l.171) — Coste de reparar la vida de la ciudad `c`: puntos que se pueden pagar ya (hasta 100), lo que falta y su coste.
- `Fabrica.hayTaller(c)` (l.187) — ¿Hay algo en el taller de la ciudad `c` (heridos o vehículos)?
- `Fabrica.textoTaller(c)` (l.193) — «2 tanq. · 1 lanzac. · 30 heridos» de lo que hay en el taller, o nil.
- `Fabrica.nuevo(sim, ciudad, modo)` (l.215) — Abre el panel sobre la ciudad `ciudad` (datos de la simulación) en el `modo` 'soldados', 'municion' o 'taller'.
- `Fabrica:pedidos()` (l.239) — Lo que se encarga ahora: { { tropa, cantidad } } (sin las filas a 0).
- `Fabrica:coste()` (l.251) — Coste total de lo elegido.
- `Fabrica:motivoPrevio(sim)` (l.263) — Por qué no saldría el encargo (texto), o nil.
- `Fabrica:comandos()` (l.294) — Comandos `producir` de lo elegido.
- `Fabrica:textoHecho(sim)` (l.309) — Texto para el aviso cuando el encargo sale: «Encargados 50 soldados en Casa · 2 días».
- `Fabrica:zona(x, y, w, h, accion)` (l.331) — Pone una zona que se puede pulsar.
- `Fabrica:dibujar(sim)` (l.337) — Dibuja el panel en el centro de la pantalla. Si la ciudad ya no es tuya, devuelve false (main.lua lo cierra).
- `Fabrica:filas(sim, c)` (l.352) — Filas del panel según el modo: { { alto, dibujar = function(x, y, w, h) } }.
- `Fabrica:dibujarClaro(sim, c)` (l.607)
- `Fabrica:pulsar(x, y)` (l.712) — Clic. Devuelve nil si cayó fuera del panel; si no, 'cancelar', 'nada' o { comandos = { … } } (lo que hay que mandar a la simulación).

## interfaz/ficha.lua

Ficha: el panel pequeño de un ejército al hacer clic en su estandarte (diseno/ejercitos-en-el-mapa.md, §3.1.5).

- Tamaño: 303 líneas, 4 funciones públicas, 2 locales.
- Usa: interfaz/acero, interfaz/inteligencia, interfaz/tema, mundo/estandartes, mundo/simulacion

- `Ficha.nuevo()` (l.26)
- `Ficha:dibujar(sim, gid, mira, semillaMundo, arriba, botones, aviso)` (l.89) — Dibuja el panel del grupo `gid` visto por la nación `mira` (nil: todo). `botones` (opcional) = { { texto, tipo, accion, activo }, ...
- `Ficha:dibujarClara(sim, gid, mira, semillaMundo, arriba, botones, aviso)` (l.100)
- `Ficha:pulsar(x, y)` (l.289) — Clic: nil si cayó fuera; si no, 'cerrar', la acción del botón o 'nada'.

## interfaz/galeria.lua

Galería de componentes de la interfaz «Acero» (diseno/interfaz-militar.md, fase 1): una pantalla con todos los componentes de `interfaz/acero.lua` en todos sus estados, para mirarlos de un vistazo y compararlos con el diseño.

- Tamaño: 140 líneas, 1 funciones públicas, 1 locales.
- Usa: interfaz/acero, interfaz/tema

- `Galeria.dibujar()` (l.28) — Dibuja la galería en toda la pantalla.

## interfaz/inteligencia.lua

Inteligencia: lo que el jugador sabe del poder y del arsenal de lo ajeno (decisión del dueño: el poder de lo enemigo está oculto).

- Tamaño: 136 líneas, 8 funciones públicas, 0 locales.
- Usa: interfaz/tema, mundo/simulacion

- `Inteligencia.oculto(mira, duena)` (l.21) — ¿Lo de la nación `duena` está oculto para la nación `mira`? (nil: observador).
- `Inteligencia.informe(sim, mira, objetivo)` (l.26) — Último informe de `mira` sobre `objetivo` (id de sitio o de grupo), o nil.
- `Inteligencia.hace(sim, dia)` (l.34) — «hoy», «hace 1 día», «hace 5 días» desde el día `dia` del informe.
- `Inteligencia.vidaInforme(inf)` (l.44) — Vida de 0 a 100 de un informe (la de una instalación viene en salud, sobre su máximo `vidaMax`).
- `Inteligencia.textoPoder(sim, mira, objetivo, duena, poder)` (l.54) — Poder de `objetivo` (de la nación `duena`, con poder real `poder`) tal como lo ve `mira`. Devuelve el texto, si se conoce y el informe (o nil).
- `Inteligencia.poderCorto(sim, mira, objetivo, duena, poder)` (l.68) — Poder corto para los rótulos del mapa: la cifra, «1 240 (3 d)» con informe viejo o «?» si se desconoce.
- `Inteligencia.ficha(sim, gid, mira)` (l.87) — Ficha de un grupo vista por `mira` (la de `sim:fichaGrupo`, copiada): si es ajeno, su poder y su composición salen del informe o quedan ocultos…
- `Inteligencia.poderRival(sim, mira, b, rival)` (l.119) — Poder del bando rival de una batalla (`b` de `sim:batallasEnCurso`) visto por `mira`: si el rival defiende un sitio y hay informe de ese sitio, el…

## interfaz/navegacion.lua

Barra de navegación de abajo (diseno/interfaz-militar.md, §6.2): una fila centrada de hexágonos de metal, uno por panel (nación, ejércitos, batallas, arsenal, noticias y ajustes), con su etiqueta y su insignia roja.

- Tamaño: 152 líneas, 6 funciones públicas, 0 locales.
- Usa: interfaz/acero, interfaz/tema

- `Navegacion.nuevo()` (l.65)
- `Navegacion.alto()` (l.74) — Alto de la barra con su margen inferior, para dejar libre ese espacio.
- `Navegacion:dibujar(ctx)` (l.81) — Dibuja la barra al pie, centrada. `ctx` = { jugador, batallasAbiertas, noticiasAbiertas, noticiasNuevas (sin leer), batallas (las tuyas en curso),…
- `Navegacion:dibujarAyuda()` (l.128)
- `Navegacion:encima(x, y)` (l.136) — ¿El punto cae sobre la barra?
- `Navegacion:pulsar(x, y)` (l.142) — Clic: devuelve la tecla del botón pulsado (o nil).

## interfaz/noticias.lua

Noticias: ventana emergente abajo a la izquierda, junto a la columna de iconos (diseno/interfaz-militar.md, §5.12).

- Tamaño: 309 líneas, 11 funciones públicas, 2 locales.
- Usa: interfaz/acero, interfaz/navegacion, interfaz/tema

- `Noticias.clasificar(noticia)` (l.65) — Prioridad ('alta', 'media' o 'baja') y tipo ('guerra', 'diplomacia' u 'obras') de una noticia, según su texto.
- `Noticias.nuevo()` (l.85)
- `Noticias:nuevas(noticias)` (l.100) — Cuántas noticias no se han leído (las más nuevas que la última vista). Si la última vista ya no está en la lista (partida cargada), todas.
- `Noticias:leer(noticias)` (l.112) — Da por leídas todas las noticias de ahora.
- `Noticias:alternar(noticias)` (l.117) — Abre o cierra la ventana; al abrirla, todo queda leído.
- `Noticias:dibujar(noticias, compacta, techo, xLibre)` (l.139) — Dibuja las noticias; `noticias` es la lista de la simulación (la más nueva primero). `compacta` = 3 noticias (con el pendón propio a la izquierda).
- `Noticias:dibujarClaro(noticias, compacta, techo, xLibre)` (l.149)
- `Noticias:dibujarAyuda()` (l.273)
- `Noticias:ocultar()` (l.280)
- `Noticias:encima(x, y)` (l.286)
- `Noticias:pulsar(x, y)` (l.292) — Clic: cambia de filtro. Devuelve true si el clic cayó en las noticias.

## interfaz/opciones.lua

Opciones (diseno/interfaz-militar.md, §5.15): pantalla completa de la familia clara. Una rejilla de dos columnas de botones anchos con icono, desplazable con la rueda; cada botón lleva a una subpantalla: General (calidad,…

- Tamaño: 498 líneas, 14 funciones públicas, 1 locales.
- Usa: interfaz/acero, interfaz/ajustes, interfaz/clara, interfaz/tema, mundo/simulacion

- `Opciones.nuevo()` (l.60)
- `Opciones:abrir()` (l.74)
- `Opciones:cerrar()` (l.83)
- `Opciones:atras()` (l.90) — Atrás: de una subpantalla al menú; del menú, cierra. Devuelve si sigue abierta.
- `Opciones:rueda(dy)` (l.103) — Rueda: desplaza la rejilla o la lista. Devuelve si la usó.
- `Opciones:zona(x, y, w, h, accion, dato)` (l.112) — Zona que se puede pulsar en este cuadro.
- `Opciones:dibujarMenu(dw, dh, arriba)` (l.117) — Rejilla del menú: dos columnas, con desplazamiento.
- `Opciones:dibujarGeneral(dw, dh, arriba)` (l.167) — Subpantalla General.
- `Opciones:dibujarLista(dw, arriba, filas, titulo, ancho)` (l.312) — Lista de filas «izquierda … derecha» sobre un panel claro.
- `Opciones:dibujar(ctx)` (l.343) — Dibuja las opciones. `ctx` = { sim, nacion }.
- `Opciones:dibujarAyuda()` (l.418)
- `Opciones:mover(x)` (l.426) — Fija el valor de un deslizador según la posición x del ratón.
- `Opciones:pulsar(x, y)` (l.435) — Clic. Devuelve la acción para main.lua (`cerrar`, `perfil`, `guardar`, `cargar`) o 'nada'.
- `Opciones:soltar()` (l.493)

## interfaz/paleta.lua

Paleta de la interfaz militar, estilo Warpath original (diseno/interfaz-militar.md, §3.2): los colores de diseño en valores de 0 a 1. `Tema` y `Acero` la comparten.

- Tamaño: 94 líneas, 2 funciones públicas, 0 locales.
- Usa: assets.ui.indice

- `Paleta.hex(texto)` (l.15) — Color de un hex «#rrggbb» en valores de 0 a 1.
- `Paleta.kit(nombre, estado)` (l.26) — Color de una entrada de `Indice.paleta` en un estado (`normal`, `resaltado`, `pulsado` o `desactivado`).

## interfaz/pendon.lua

Panel de sitio: el de una ciudad, una instalación, una mina o una bandera (diseno/interfaz-militar.md, §5.2 a §5.5).

- Tamaño: 1534 líneas, 29 funciones públicas, 21 locales.
- Usa: interfaz/acero, interfaz/inteligencia, interfaz/tema, mundo/simulacion

- `Pendon.nuevo()` (l.31)
- `Pendon:filaRecuperacion(contenido, sim, c, nacion, tropa)` (l.116) — Fila de recuperación de una tropa con su botón Acelerar (C7). El botón paga por la nación dueña de la ciudad (aún no hay nación del jugador), con el…
- `Pendon:medidor(contenido, r, nombre, ayuda)` (l.178) — Medidor de reserva con su ayuda al pasar el ratón.
- `Pendon:relacion(contenido, otra, valor)` (l.233) — Relación con otra nación (C10): punto del país, nombre, eje de −100 a +100 y valor. Un clic lleva a su capital.
- `Pendon:resumen(contenido, sim, c, nacion, ancho)` (l.325) — Pestaña Resumen: reservas, defensas y fuerzas.
- `Pendon:ejercito(contenido, sim, c, nacion)` (l.381) — Pestaña Ejército: tropas, recuperación por tropa y grupos en marcha.
- `Pendon:sacarTropas(contenido, sim, c)` (l.443) — Bloque "Sacar tropas" del pendón (dueño 2026-09-29): tres filas con botones −/+ para elegir cuántos soldados, tanques y lanzacohetes sacar, y un…
- `Pendon:dibujarBotonMasMenos(x, y, lado, signo, clave, actual, maximo)` (l.516) — Dibuja un botón cuadrado +/− para ajustar la tropa a sacar (dueño 2026-09-29) y registra su zona pulsable.
- `Pendon:ajustarSacar(clave, dir)` (l.534) — Ajusta la cantidad a sacar para una tropa (dueño 2026-09-29). Saltos: soldados de a 10 (con un mínimo de 1 si la fila tiene algo), tanques y…
- `Pendon:armarGrupoDesde(sim, c)` (l.553) — Crea un grupo en la capital con la cantidad marcada en `self.sacar` y descuenta esos efectivos de la ciudad (dueño 2026-09-29).
- `Pendon:nacion(contenido, sim, c, nacion, oculta)` (l.584) — Pestaña Nación: gobierno, economía de la ciudad y tecnología.
- `Pendon:relaciones(contenido, sim, nacion)` (l.632) — Pestaña Relaciones: todas las naciones vivas, de la más fuerte a la más débil en valor absoluto y, a igualdad, por id (el orden de siempre).
- `Pendon:dibujarIdentidad(cabecera, x, y, w)` (l.810)
- `Pendon:dibujarPestanas(x, y, w, pendientes)` (l.827) — Pestañas (C8) a todo el ancho; un punto rojo avisa de algo pendiente.
- `Pendon:dibujarLista(contenido, x, y, w, alto)` (l.847) — Dibuja la zona desplazable con su contenido y su barra de desplazamiento (C9).
- `Pendon:dibujarVida(vida, x, y, w)` (l.899) — Bloque fijo de vida (diseno/territorio-y-capitales.md, 3.1 y 3.5): «VIDA», el estado, el valor, la barra de 0 a 100 y, en una ciudad tuya, la fila…
- `Pendon:dibujarPendon(datos, arriba)` (l.950) — Coloca y dibuja un panel completo: cabecera, identidad, cifras, vida, avisos, botones, pestañas (si las lleva) y la lista.
- `Pendon:dibujarPendonClaro(datos, arriba)` (l.960)
- `Pendon:dibujarCiudad(sim, ciudad, arriba, botones, propia, mira)` (l.1129) — Pendón de una ciudad. `ciudad` es la ciudad dibujable del mundo (con `region`); los datos vivos salen de la simulación.
- `Pendon:dibujarInstalacion(sim, id, arriba, botones, mira)` (l.1230) — Pendón estrecho de una instalación o base (P3), sin pestañas. `botones` (opcional): órdenes como las del pendón de una ciudad.
- `Pendon:guarnicionInformada(contenido, sim, mira, s)` (l.1317) — Guarnición de un sitio ajeno según el último informe de `mira`: poder, tropas y defensas con su antigüedad, o «Desconocido · Explorar».
- `Pendon:dibujarYacimiento(sim, id, arriba, botones, mira)` (l.1354) — Pendón estrecho de un yacimiento (diseno/recoleccion-y-batallas.md, 3.2 y 3.5): lo que queda de su reserva, si está cerrada, de quién es la tierra…
- `Pendon:contenidoBandera(contenido, i)` (l.1452) — Lo que dice el pendón de una bandera (3.7): solo da territorio, se paga cada día y se repara sola si no la atacan.
- `Pendon:dibujarAyuda()` (l.1466) — La ayuda del medidor bajo el ratón (se dibuja encima de todo).
- `Pendon:primerBoton()` (l.1475) — Primer botón con comando visible (para el modo captura `acelerar`, que hace clic en él como lo haría el ratón).
- `Pendon:ocultar()` (l.1485) — Olvida el pendón (no hay nada que mostrar este cuadro).
- `Pendon:encima(x, y)` (l.1492)
- `Pendon:rueda(x, y, dy)` (l.1498) — Rueda sobre el pendón: desplaza la lista. Devuelve true si la usó.
- `Pendon:pulsar(x, y)` (l.1510) — Clic en el pendón. Devuelve nil si cayó fuera; si cayó dentro, la acción para main.lua ({ tipo = 'cerrar' }, { tipo = 'nacion', id }) o { tipo =…

## interfaz/perfil.lua

Perfil de la nación (diseno/interfaz-militar.md, §5.14): pantalla completa de la familia clara.

- Tamaño: 381 líneas, 7 funciones públicas, 4 locales.
- Usa: interfaz/acero, interfaz/clara, interfaz/tema, mundo/estandartes, mundo/simulacion

- `Perfil.nuevo()` (l.20)
- `Perfil:abrir()` (l.30)
- `Perfil:cerrar()` (l.35)
- `Perfil:dibujarTarjeta(sim, nacion, semilla, x, y, w, h, vs)` (l.108) — Tarjeta de comandante (izquierda). `d` = medidas en píxeles de pantalla.
- `Perfil:dibujar(ctx)` (l.239) — Dibuja el perfil. `ctx` = { sim, semilla, nacion (id o nil) }.
- `Perfil:dibujarAyuda()` (l.358)
- `Perfil:pulsar(x, y)` (l.367) — Clic: devuelve la acción pedida (`cerrar`, `opciones`, `territorio`) o nil. `info` y `guerras` los resuelve el propio perfil.

## interfaz/placa.lua

Placa de lugar: una etiqueta pequeña arriba al centro, bajo la barra superior (diseno/interfaz-militar.md, §10).

- Tamaño: 98 líneas, 4 funciones públicas, 0 locales.
- Usa: interfaz/acero, interfaz/tema

- `Placa.nuevo()` (l.12)
- `Placa:dibujar(sim, ciudad, distancia, arriba)` (l.21) — Dibuja la placa de `ciudad` (dibujable del mundo) a `distancia` unidades, con su borde de arriba en `arriba` (píxeles de pantalla).
- `Placa:ocultar()` (l.83)
- `Placa:pulsar(x, y)` (l.89) — Clic en la placa: devuelve su ciudad (para abrir su pendón) o nil.

## interfaz/plantar.lua

Plantar bandera (modo jugador; diseno/territorio-y-capitales.md, 3.7): el modo de colocación con el ratón.

- Tamaño: 268 líneas, 8 funciones públicas, 1 locales.
- Usa: interfaz/acero, interfaz/tema, mundo/estandartes, mundo/iso, mundo/senales, mundo/simulacion

- `Plantar.nuevo(nid)` (l.37) — Modo de colocación para la nación `nid`.
- `Plantar.sueloBajo(terreno, vx, vy)` (l.48) — Punto del suelo bajo el punto de la vista (vx, vy): Iso.mundo da el de altura 0; unas vueltas con la altura del terreno lo asientan en la ladera.
- `Plantar:poner(sim, x, y)` (l.58) — Coloca el punto (en coordenadas del mundo) y mira si se puede plantar.
- `Plantar:confirmar(sim)` (l.70) — Planta la bandera: el mismo comando que usa un presidente NPC. Devuelve el id o false (y deja el motivo).
- `Plantar:celdas(sim)` (l.87) — Celdas del bloque que daría la bandera: { cx, cy, dueno } (dueno: id de nación o nil) y su caja cx0, cy0, cx1, cy1.
- `Plantar:mallaBloque(mundo, sim)` (l.106) — Malla del bloque: cada celda partida en tramos que siguen el relieve, del color que toca (libre, tuya o de otra nación).
- `Plantar:dibujarMundo(mundo, zoom, semilla, color)` (l.177) — En el mapa (dentro de la transformación de la cámara): el bloque de celdas que dará, siguiendo el relieve, y el mástil fantasma.
- `Plantar:dibujarPantalla(sx, sy, nacion)` (l.219) — Junto al punto de pantalla (sx, sy): título, coste y el motivo o cómo se confirma. `nacion` para el coste en rojo si no alcanza.

## interfaz/pregon.lua

Pregón: las tarjetas de evento de la derecha (diseno/interfaz-militar.md, §5.10). Salen cuando la simulación da una noticia de guerra declarada, caída de una capital, saqueo de una capital, bandera atacada o arrancada, o crimen…

- Tamaño: 327 líneas, 8 funciones públicas, 2 locales.
- Usa: interfaz/acero, interfaz/tema

- `Pregon.nuevo()` (l.35)
- `Pregon:actualizar(dt, noticias, propia)` (l.66) — Mira las noticias nuevas y cuenta el tiempo de los pregones a la vista. Al empezar (o al cargar otra partida) las noticias viejas no dan pregón.
- `Pregon:avisar(titulo, detalle, boton, accion, duracion)` (l.102) — Pregón propio de main.lua (no sale de una noticia), el primero de la cola: `boton` es el texto de su botón y `accion` lo que devuelve `pulsar` al…
- `Pregon:preguntar(titulo, detalle, botones, duracion)` (l.120) — Pregón propio con varios botones (por ejemplo, «Defender» y «Atacar»): `botones` = { { texto, accion, tipo }, ... }, de izquierda a derecha.
- `Pregon:quitar(p)` (l.127) — Quita de la cola un pregón propio (ya no hace falta: la batalla acabó).
- `Pregon:reiniciar()` (l.137) — Olvida lo que había (mundo nuevo o partida cargada).
- `Pregon:dibujar(arriba, derecha)` (l.158) — Dibuja la columna de tarjetas bajo la barra superior (`arriba`), con su borde derecho en `derecha` (o a 16 px del borde de la pantalla).
- `Pregon:pulsar(x, y, boton)` (l.294) — Clic en un pregón: con el izquierdo devuelve 'x' (ir al ataque) o, en los de `avisar`, su acción; con el derecho lo descarta.

## interfaz/radial.lua

Menú radial del mapa, al estilo Warpath (diseno/referencias-warpath/ radial_ciudad_propia.jpg y mapa_hud.jpg): al tocar un sitio sin un ejército elegido sale, alrededor del objetivo, un círculo punteado; bajo el objetivo, su…

- Tamaño: 423 líneas, 8 funciones públicas, 8 locales.
- Usa: interfaz/acero, interfaz/tema

- `Radial.nuevo()` (l.27)
- `Radial:abrir(objetivo)` (l.37) — Abre el menú sobre `objetivo` = { tipo = 'sitio' | 'mina', id }.
- `Radial:cerrar()` (l.42)
- `Radial:abierto()` (l.49)
- `Radial:ficha(opciones, x, y, ancho)` (l.219) — Tarjeta de datos (familia clara): cabecera con la marca verde, el título, las coordenadas y el favorito; filas de etiqueta y valor (con icono a…
- `Radial:dibujar(sx, sy, opciones)` (l.290) — Dibuja el menú con el objetivo en (sx, sy) de la pantalla. `opciones` = { nombre, nivel, colorNombre, titulo, coordenadas, favorito (nil: sin…
- `Radial:dibujarAyuda()` (l.394)
- `Radial:pulsar(x, y)` (l.403) — Clic: la clave del botón pulsado, 'nada' si cayó en la tarjeta o en un botón apagado, o nil si cayó fuera (el menú se cierra y el clic sigue).

## interfaz/tema.lua

Tema de la interfaz «Acero» (diseno/interfaz-militar.md, §3): escala e, fuentes Barlow con caché por tamaño, colores (`interfaz/paleta.lua`) y las piezas de dibujo que comparten todos los paneles (botones, medidores, casillas,…

- Tamaño: 433 líneas, 29 funciones públicas, 1 locales.
- Usa: assets.ui.indice, interfaz/acero, interfaz/paleta, utf8

- `Tema.actualizar()` (l.63)
- `Tema.compacta()` (l.76) — ¿La pantalla es «pequeña» (el lienzo de diseño mide menos de 1700 de ancho)? Los paneles se estrechan un poco.
- `Tema.escala()` (l.80)
- `Tema.px(valor)` (l.85) — Una medida de diseño (a 1920×1080) en píxeles de pantalla, entera.
- `Tema.fuente(tipo, base, minimo)` (l.91) — Fuente de un tipo y tamaño de diseño (F2): nunca baja de `minimo` (12 para texto, 10 para etiquetas). Cada tamaño se carga una sola vez.
- `Tema.fuenteExacta(tipo, base, minimo)` (l.97) — Como `fuente`, pero sin el factor de los tipos viejos: `base` es el tamaño de diseño tal cual.
- `Tema.color(nombre, alfa)` (l.114) — Pone un color del tema (o uno dado como tabla) con su opacidad.
- `Tema.mezcla(a, b, t)` (l.120) — Mezcla de dos colores: `t` = 0 da `a`, 1 da `b`.
- `Tema.mayusculas(texto)` (l.146) — Texto en mayúsculas, con las vocales acentuadas y la ñ (`string.upper` no las toca).
- `Tema.numero(valor)` (l.153) — Número entero con el formato del juego: «19 039», «123 k», «1,2 M».
- `Tema.decimal(valor)` (l.167) — Número con un decimal y signo siempre: «+18,3», «−21,9».
- `Tema.cortar(fuente, texto, ancho)` (l.173) — Texto cortado con «…» si no cabe en `ancho` con la fuente dada.
- `Tema.espaciado(texto, x, y, fuente, espacio)` (l.191) — Texto en versalitas con espaciado (etiquetas y títulos de sección). Devuelve el ancho que ocupa.
- `Tema.anchoEspaciado(texto, fuente, espacio)` (l.203)
- `Tema.degradado(x, y, w, h, arriba, abajo, alfa)` (l.215) — Rectángulo con degradado de `arriba` a `abajo`.
- `Tema.rayado(x, y, w, h, fondo, raya, paso)` (l.234) — Rayado diagonal de dos colores dentro de un rectángulo (crisis, recuperándose).
- `Tema.borde(x, y, w, h, nombre, alfa)` (l.254) — Borde de 1 px por dentro de un rectángulo.
- `Tema.dentro(px, py, x, y, w, h)` (l.260) — ¿Está el punto dentro del rectángulo?
- `Tema.boton(boton, x, y, w, h, compacto)` (l.267) — Botón (C5): lo dibuja `Acero.boton` con las piezas del kit. `boton` = { texto, tipo, activo, precio }; los tipos viejos valen: `principal` es…
- `Tema.anchoBoton(boton, compacto)` (l.272) — Ancho que pide un botón con su texto y su precio.
- `Tema.moneda(cx, cy, radio, vivo)` (l.277) — Icono de moneda (dinero), del kit.
- `Tema.reloj(cx, cy, radio, nombre)` (l.283) — Reloj (plazo): un círculo con dos manecillas.
- `Tema.iconoRecurso(tipo, x, y, lado)` (l.294) — Icono de un recurso (metal, petróleo, comida, dinero), del kit, en `lado` px.
- `Tema.tituloSeccion(texto, x, y, w)` (l.300) — Título de sección (RESERVAS, DEFENSAS): estilo `subtitulo` en dorado con una raya fina hasta el borde. Devuelve el alto que ocupa.
- `Tema.textoReserva(r)` (l.311) — Estado de una reserva escrito (F4): nada si está holgada.
- `Tema.alturaMedidor(r)` (l.326) — Medidor de reserva (C4): icono · nombre · barra · valor; debajo, el estado si no está holgada. Devuelve el alto que ocupa.
- `Tema.medidor(r, nombre, x, y, w)` (l.334)
- `Tema.casillas(partes, plazas, x, y, w)` (l.374) — Casillas de defensas (C7): una por plaza del tope. `partes` = { listas, recuperando, fuera }. Devuelve el alto que ocupa.
- `Tema.ayuda(texto, mx, my, anchoMax)` (l.428) — Caja de ayuda al pasar el ratón (`Acero.tooltip`), pegada al puntero y metida en la pantalla.


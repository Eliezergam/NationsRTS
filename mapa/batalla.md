# Mapa de `batalla/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## batalla/agua.lua

Agua de la batalla (Valeria): dónde no se puede pisar y sus bordes para la física. Por ahora solo el agua del mapa (el mar y sus ensenadas, que en la batalla se ven como lagos); los ríos, los lagos de la hidrología, las ondas y…

- Tamaño: 155 líneas, 9 funciones públicas, 0 locales.

- `Agua.nuevo(suelo)` (l.17)
- `Agua:enAgua(x, y, radio)` (l.28) — ¿Es agua (x, y)? El mar y la orilla encharcada. Con `radio` (px), también si lo es alguno de los cuatro puntos a esa distancia.
- `Agua:lagoEn(_, _)` (l.41) — Lagos de la hidrología: PENDIENTE (el mar ya lo evita el A* por su altura).
- `Agua:rioEn(_, _, _)` (l.46) — Ríos: PENDIENTE.
- `Agua:nivelEn(_, _)` (l.51) — Nivel del agua en (x, y) (px).
- `Agua:pesoFueraDelCauce(_)` (l.57) — Peso (0 a 1) con el que los pasillos pueden rellenar el vértice `k`: sin ríos todavía, siempre 1.
- `Agua:puenteEn(_, _)` (l.62) — Puentes: PENDIENTE.
- `Agua:rellenarCharcos()` (l.69) — Charcos de uno o dos vértices bajo el nivel del agua, sueltos en tierra firme (restos del suavizado, más pequeños que la rejilla de los bordes): se…
- `Agua:sacarBordes()` (l.101) — Tramos de borde entre agua y tierra dentro del límite (con 20 m de margen), en `self.bordes` como { x1, y1, x2, y2 } en px.

## batalla/camara.lua

Cámara libre de la batalla con el control del ejemplo firstpersongame de 3DreamEngine (batalla/controlador_camara.lua): el botón derecho mira, W/S van hacia la mirada en 3D con la inercia del ejemplo, A/D a los lados, Espacio…

- Tamaño: 369 líneas, 26 funciones públicas, 0 locales.
- Usa: batalla/controlador_camara, batalla/matriz

- `Camara.nueva(suelo, x, y)` (l.46) — Cámara mirando a (x, y) sobre `suelo`. El rumbo por defecto (45°) es el del mapa isométrico: se ve el sitio con la misma orientación.
- `Camara:sacudir(x, y, z, intensidad)` (l.68) — Un impacto cercano sacude la mirada, sin desplazar el ojo ni su objetivo.
- `Camara:puntosVista()` (l.88) — Ojo fijo y dirección visual temporal, compartidos por ambos renderizadores.
- `Camara:ojoPlano()` (l.108) — Posición horizontal del ojo para el objetivo y la mirada actuales.
- `Camara:superficie(x, y)` (l.114) — Superficie visible bajo el observador: terreno o agua, nunca el fondo marino.
- `Camara:limitarAltura(x, y, z, margen)` (l.120) — Altura del ojo en (x, y) con al menos `margen` px sobre la superficie (por defecto, el suelo duro). Sin techo.
- `Camara:alturaInicial()` (l.126) — Altura de la mira de un encuadre nuevo: el ojo empieza ya a la altura mínima completa, para que el colchón no lo mueva después del corte.
- `Camara:limitarOjo(x, y)` (l.134) — Posición permitida del ojo dentro del área generada.
- `Camara:recortar()` (l.145) — Recorta un encuadre nuevo por su ojo, sin restringir dónde puede mirar.
- `Camara:ojo()` (l.154) — Posición del observador. También limita los encuadres que fijan objetivoZ directamente. El rango depende de la posición del ojo, nunca de la mirada.
- `Camara:alturaObjetivo()` (l.175) — Altura de la mirada. Tras un corte vale la del suelo de debajo; desde el primer cuadro se conserva en `objetivoZ` hasta el próximo movimiento.
- `Camara:ejes()` (l.183) — Derecha de la pantalla y adelante tridimensional, con Z vertical.
- `Camara:trasladar(dx, dy, dz)` (l.192) — Mueve el ojo y la mira juntos. Muestrea el trayecto para no atravesar una loma entre cuadros; el borde restringe al observador, no su orientación.
- `Camara:desplazar(derecha, arriba)` (l.212) — Arrastre lateral sobre el plano de la pantalla, también con vista vertical.
- `Camara:girar(angulo, inclinar)` (l.221) — Gira sobre el ojo: el objetivo se reubica para que el ojo no se mueva.
- `Camara:orientar(rumbo, inclinacion)` (l.226) — Fija rumbo e inclinación sin mover el ojo.
- `Camara:avanzar(pasos)` (l.239) — Rueda: recorrido físico en la dirección de la mirada, sin zoom. Es un impulso que frena la misma resistencia del aire del vuelo.
- `Camara:acercar(pasos)` (l.249) — Alias para los llamadores existentes; ahora traslada, sin cambiar distancia.
- `Camara:alturas()` (l.255) — Depuración en metros: altura sobre suelo/agua y altitud sobre el mar. La escala del juego es 10 px por metro, independiente de la de 3Dream.
- `Camara:rapidez()` (l.263) — Rapidez de vuelo según la altura actual, con un máximo para explorar.
- `Camara:actualizar(dt)` (l.271) — Un paso del controlador del ejemplo; después, límite del campo y colchón suave sobre el suelo. Devuelve si hubo entrada del jugador.
- `Camara:seguir(x, y, z, dt)` (l.313) — Seguir un punto (un misil) con suavidad: el objetivo se acerca a él sin saltar aunque cambie el misil elegido.
- `Camara:terminarGiro()` (l.323) — El giro del ratón acaba en este instante: consume de una vez lo que el suavizado dejó pendiente, para que la mirada no derive tras soltar el botón.
- `Camara:detener()` (l.336) — Corte: se olvida la inercia (al encuadrar).
- `Camara:arrastrar(dx, dy, girar)` (l.345) — Ratón arrastrado `dx`, `dy` px: con el derecho mira como el ejemplo (`mousemoved`), con el otro desplaza.
- `Camara:matrices()` (l.357) — Matriz de vista y proyección del cuadro; devuelve también el ojo.

## batalla/carga.lua

Pantalla mostrada mientras se construye el campo de batalla. El generador informa por etapas para que una malla detallada no parezca un bloqueo.

- Tamaño: 97 líneas, 2 funciones públicas, 1 locales.

- `Carga.iniciar()` (l.13)
- `Carga.mostrar(etapa, progreso, forzar)` (l.18)

## batalla/colocacion.lua

Dónde crece cada cosa en la batalla (ESTILO-TERRENO.md §4). Todo sale de la semilla por hash, en este orden: 0 plantas del mapa como anclas, en su sitio exacto (Plantas.enTrozo) 1 bosque y árboles sueltos según la máscara de…

- Tamaño: 681 líneas, 20 funciones públicas, 3 locales.
- Usa: batalla/color_terreno, batalla/vegetacion, mundo/plantas, mundo/ruido, mundo/terreno

- `Colocacion.nueva(suelo)` (l.100)
- `Colocacion:dentro(x, y)` (l.120) — ¿Cae (x, y) dentro de la zona con plantas (sin el borde de niebla)?
- `Colocacion:choca(x, y, r)` (l.128) — ¿Choca un objeto de radio `r` m en (x, y) con lo ya puesto?
- `Colocacion:ocupar(x, y, r)` (l.149) — Apunta un objeto de radio `r` m en la rejilla de choques.
- `Colocacion:copia(nombre, x, y, U, o)` (l.166) — Crea una copia de `nombre` en (x, y). `o` lleva: escala, hundir (m), libre (giro en los tres ejes), alinear, inclinar, roca (tono de roca), tono…
- `Colocacion:arbol(nombre, x, y, U, escala)` (l.216) — Pone un árbol y lo apunta para la física y para las formaciones.
- `Colocacion:estorbaAqui(x, y)` (l.233) — ¿Se puede poner algo que estorbe (árbol, arbusto, roca grande) en (x, y)?
- `Colocacion:buscarAnclas()` (l.241) — Capa 0: las plantas del mapa del área, en su sitio.
- `Colocacion:buscarManchas()` (l.273) — Manchas de flores sueltas en la pradera: una por celda de 60 m con probabilidad 0,15, donde no hay bosque ni hierba seca.
- `Colocacion:manchasCerca(x, y)` (l.310) — Manchas de flores cuya celda de 60 m toca la de (x, y) (o nil).
- `Colocacion:plantarAnclas()` (l.336) — Capa 0 (árboles, arbustos y cactus del mapa).
- `Colocacion:recorrer(paso, desplazar, sal, prob, fn)` (l.369) — Recorre una rejilla de `paso` px desplazada `desplazar` px por hash sobre la zona con plantas y llama a `fn(x, y, k, U)` en cada candidato cuya…
- `Colocacion:plantarBosque()` (l.400) — Capa 1: bosque y árboles sueltos.
- `Colocacion:plantarArbustos()` (l.451) — Capa 3: arbustos en la orla del bosque y alguno suelto.
- `Colocacion:roca(x, y, U, escala, hundir)` (l.471) — Una roca de escala `escala`; las grandes estorban a las formaciones.
- `Colocacion:plantarRocas()` (l.494) — Capa 6: rocas en lo empinado, afloramientos y peñas sueltas.
- `Colocacion:crestas()` (l.547) — Centros de afloramiento: en celdas de 40 m, el vértice más alto si su curvatura pasa de 0,8 m y está a más de 4 m sobre el fondo del valle, con…
- `Colocacion:plantar()` (l.585) — Planta todo lo fijo (capas 0, 1, 3 y 6).
- `Colocacion:fueraDeCamino(x, y, k)` (l.595) — El centro de tierra del camino queda visible, sin matas ni flores.
- `Colocacion:hierbaDeBaldosa(bx, by)` (l.606) — Matas y flores de la baldosa (bx, by), generadas la primera vez que se piden. Salen del hash: dan siempre lo mismo.

## batalla/color_terreno.lua

Color del terreno de batalla (`colores_terreno` del paisaje de Blender, traducido en ESTILO-TERRENO.md §2.3), con la paleta exacta del script.

- Tamaño: 155 líneas, 3 funciones públicas, 0 locales.
- Usa: mundo/terreno

- `ColorTerreno.suave(a, b, x)` (l.40) — Smoothstep de `a` a `b` (si a > b, va de 1 a 0). Con `min` y `max` y no con `if`: LuaJIT lo compila sin ramas (se llama millones de veces).
- `ColorTerreno.pesoCamino(distancia, ruido)` (l.48) — Tierra pisada en el centro del pasillo, con borde irregular y suave.
- `ColorTerreno.cara(s, c)` (l.57) — Color sRGB (r, g, b) de un vértice. `c` lleva sus campos: x, y, h (px), nx, ny, nz (normal), n1, n2, fino (ruidos), humedad, bosque, dAgua (m),…

## batalla/control.lua

Control táctico de la escena de batalla (estilo RTS, como el mapa 2D de interfaz/ejercito.lua): selección y órdenes a las unidades del jugador.

- Tamaño: 492 líneas, 26 funciones públicas, 0 locales.
- Usa: batalla/camara, batalla/ordenes

- `Control.nuevo(tropas, camara)` (l.34) — Control para las tropas y la cámara de una escena.
- `Control:usarBando(indice)` (l.50) — El bando que manda el jugador.
- `Control:propia(u)` (l.55) — ¿Es `u` una unidad del jugador que se puede elegir?
- `Control:proyectar(x, y, z, salida)` (l.61) — Proyecta un punto del mundo a pantalla. Devuelve x, y, profundidad, si se ve dentro de la pantalla (`visible`) y si queda delante de la cámara.
- `Control:unidadEn(x, y)` (l.89) — Unidad bajo el punto de pantalla, tomando la más cercana a la cámara si dos círculos se pisan.
- `Control:usarSelector(selector)` (l.113)
- `Control:vaciar()` (l.119)
- `Control:seleccionada(unidad)` (l.126)
- `Control:seleccionar(unidad, sumar)` (l.131) — Selecciona una unidad. Con `sumar`, alterna esa unidad sin borrar las demás.
- `Control:anadir(unidad)` (l.153) — Suma `unidad` a la selección (sin alternar).
- `Control:lista()` (l.161) — Las unidades elegidas, en orden de entrada (estable).
- `Control:click(x, y, sumar, ahora)` (l.175) — Clic izquierdo en (x, y): elige solo esa unidad propia (con `sumar`, la suma o la quita); doble clic, todas las propias de su tipo a la vista.
- `Control:tipoAVista(tipo)` (l.201) — Suma a la selección las unidades propias de `tipo` que se ven en pantalla.
- `Control:todasDeTipo(tipo, sumar)` (l.214) — Todas las unidades propias de `tipo` en el campo (con `sumar`, se suman).
- `Control:cuadro(x0, y0, x1, y1)` (l.226) — Cuadro de selección mientras se arrastra (nil: ninguno).
- `Control:elegirCaja(x0, y0, x1, y1, sumar)` (l.235) — Elige las unidades propias que caen en el cuadro (con `sumar`, las suma).
- `Control:marcar(marca)` (l.255) — Deja constancia de una orden para dibujarla un rato.
- `Control:ordenar(sx, sy)` (l.266) — Clic derecho corto en (sx, sy): sobre un enemigo, la selección lo ataca; sobre el terreno, va allí en formación.
- `Control:moverA(unidades, x, y)` (l.288) — Manda `unidades` a (x, y) del mundo en formación por terreno transitable.
- `Control:mantener()` (l.341) — MANTENER POSICIÓN a la selección (H).
- `Control:actualizar()` (l.348) — Quita de la selección las unidades que cayeron o se retiraron.
- `Control:suelo(x, y)` (l.360) — Altura del suelo (o del agua) en (x, y) para dibujar encima.
- `Control:anillo(x, y, r, lados)` (l.366) — Círculo de radio `r` px del mundo sobre el suelo en (x, y), proyectado.
- `Control:lineaSuelo(ruta, desde)` (l.383) — Línea por el suelo de `ruta` (lista de { x, y }) desde el punto `desde`.
- `Control:marcador(x, y, color, alfa)` (l.404) — Marcador de destino: dos anillos y un punto, que laten.
- `Control:dibujar()` (l.421) — Dibuja la selección (anillos verdes sobre el suelo, como en el mapa 2D), las rutas y destinos de sus órdenes, los enemigos que atacan (rojo), las…

## batalla/controlador_camara.lua

Control de vuelo de la batalla: el `cameraController` del ejemplo firstpersongame de 3DreamEngine, sin reescribirlo.

- Tamaño: 165 líneas, 11 funciones públicas, 0 locales.
- Usa: lib.3DreamEngine.extensions.utils.cameraController

- `Controlador.fraccion(k, dt)` (l.27) — Fracción independiente de la frecuencia de cuadros.
- `Controlador.nuevo()` (l.33) — Un controlador por cámara: el del ejemplo es un único objeto compartido, así que cada cámara lleva su propio estado y hereda sus funciones.
- `Controlador:detener()` (l.45) — Olvida la inercia (encuadres, pérdida de foco).
- `Controlador:orientar(rumbo, inclinacion)` (l.53) — Copia la orientación de la cámara (rumbo e inclinación del juego).
- `Controlador:angulos()` (l.59) — Rumbo e inclinación del juego para la orientación actual.
- `Controlador:mirar(dx, dy)` (l.64) — Ratón relativo, igual que en el ejemplo.
- `Controlador:empujar(distancia)` (l.70) — Rueda: un impulso en la dirección de la mirada que la resistencia del aire del ejemplo frena; recorre `distancia` px en total.
- `Controlador.teclasPulsadas()` (l.81) — ¿Hay alguna tecla de vuelo pulsada?
- `Controlador:actualizar(dt, x, y, z, rapidez)` (l.92) — Un paso del `update` del ejemplo desde el ojo (x, y, z del juego). Devuelve el desplazamiento pedido en ejes del juego y si hubo entrada.
- `Controlador:recortar(bx, by, bz)` (l.143) — El límite o el suelo recortaron el paso en (bx, by, bz) px (lo pedido menos lo recorrido, ejes del juego).
- `Controlador:velocidad()` (l.160) — Velocidad actual en ejes del juego.

## batalla/derribo.lua

Derribo (Valeria): los vehículos tumban los árboles jóvenes, los abedules finos y los arbustos al pasar; los árboles grandes (robles, pinos altos) y las rocas los siguen frenando en la física.

- Tamaño: 117 líneas, 5 funciones públicas, 0 locales.

- `Derribo.derribable(p)` (l.23) — ¿Se tumba la planta `p` al chocar un vehículo? Los arbustos siempre; los árboles, si son finos y no muy altos; las rocas, nunca.
- `Derribo.nuevo(fisica, unidadDe)` (l.35) — Encadena el preSolve al mundo Box2D de `fisica`. `unidadDe` es la tabla cuerpo -> unidad de los vehículos.
- `Derribo:preSolve(a, b, contacto)` (l.54) — Contacto vehículo-árbol derribable: no frena y se apunta para después del paso.
- `Derribo:tumbar(p, unidad)` (l.74) — Tumba la planta `p` hacia el avance de `unidad` y le resta velocidad.
- `Derribo:actualizar()` (l.91) — Tras `mundo:update`: tumba los árboles apuntados y los arbustos bajo los cascos.

## batalla/destruccion.lua

Restos del lanzamisiles: piezas originales, daño variable y caída física. El azar visual es independiente de la puntería y de la simulación del mundo.

- Tamaño: 168 líneas, 4 funciones públicas, 1 locales.
- Usa: batalla/matriz

- `Destruccion.nueva(modelo, suelo, nombres)` (l.22) — Geometría de las ruedas preparada una vez, antes de cualquier destrucción.
- `Destruccion:iniciar(unidad, fisica)` (l.47) — Sortea de una a ocho ruedas sin repetición y conserva su pose al separarse.
- `Destruccion:caerSinMotor(rueda, dt)` (l.117) — Respaldo sin 3Dream: gravedad y contacto con el mismo suelo del juego.
- `Destruccion:actualizar(unidad, dt)` (l.136) — Asienta el casco, deja caer la rampa y anima las ruedas ya independientes.

## batalla/dream/biblioteca_pbr.lua

Biblioteca de materiales PBR para 3DreamEngine (Camila). Cada subcarpeta de `carpeta` es un material con el nombre de la carpeta: albedo, normal y material (R metálico, G rugosidad, B oclusión) en .jpg o .png, y un material.lua…

- Tamaño: 63 líneas, 1 funciones públicas, 1 locales.

- `BibliotecaPbr.cargar(dream, carpeta)` (l.32) — Registra en `dream` los materiales de `carpeta`. Devuelve cuántos.

## batalla/dream/calidad.lua

Calidad del dibujo de la batalla: baja, media o alta (por defecto alta). Se elige con `--calidad <baja|media|alta>` al arrancar el juego.

- Tamaño: 88 líneas, 2 funciones públicas, 0 locales.

- `Calidad.elegir(nombre)` (l.74) — Elige la calidad por su nombre; devuelve false si no existe.
- `Calidad.actual()` (l.83) — Valores de la calidad elegida.

## batalla/dream/cielo.lua

Blacksmith deja que 3Dream dibuje directamente un cielo horneado. Aquí se usa el mismo camino estable con un panorama exterior, mientras la extensión sky aporta la luz solar y ambiental correspondiente al mediodía.

- Tamaño: 21 líneas, 2 funciones públicas, 0 locales.
- Usa: lib.3DreamEngine.extensions.sky

- `Cielo.cargar(dream)` (l.9)
- `Cielo.iluminar(sol)` (l.16)

## batalla/dream/conversor.lua

Puente entre las mallas de NationsRTS y 3DreamEngine. Cambia el eje vertical Z del juego por Y, centra el área para conservar precisión y aplica la escala física de 100 px por unidad de 3Dream (10 m).

- Tamaño: 173 líneas, 6 funciones públicas, 2 locales.
- Usa: batalla/malla, ffi

- `Conversor.nuevo(dream, cx, cy)` (l.15)
- `Conversor:punto(x, y, z)` (l.23)
- `Conversor:desdeMalla(mallaLove, opciones)` (l.53)
- `Conversor:desdeMallaLocal(mallaLove, opciones)` (l.102) — Como `desdeMalla`, pero sin restar el centro del área: para prototipos en coordenadas locales (origen en su base) que luego se instancian.
- `Conversor:desdeVertices(verticesFuente, colorNacion, nombre, tono)` (l.110)
- `Conversor:matriz(matriz)` (l.150) — Convierte una matriz de modelo del juego a una transformación de 3Dream.

## batalla/dream/efectos.lua

Efectos de la batalla en 3DreamEngine (Camila): la `salida` de `batalla/efectos.lua`. Todo va en la GPU con pocas llamadas de dibujo:

- Tamaño: 424 líneas, 13 funciones públicas, 2 locales.
- Usa: batalla/dream/conversor, batalla/dream/efectos/cinta, batalla/dream/efectos/comun, batalla/dream/efectos/lote, batalla/dream/efectos/mallas, batalla/dream/efectos/marcas, batalla/dream/efectos/misiles, batalla/dream/efectos/sombreadores, batalla/dream/efectos/texturas, batalla/efectos

- `EfectosDream.nuevos(dream, conversor, tropas, suelo, opciones)` (l.72) — `opciones.misil`: el modelo del misil cargado en 3Dream (se dibujan los misiles en vuelo por instancias); `opciones.calidad`: baja, media o alta.
- `EfectosDream:particula(clase, p)` (l.193)
- `EfectosDream:tramoEstela(e, a, b)` (l.219)
- `EfectosDream:cabezaEstela(e, a, b)` (l.223)
- `EfectosDream:soltarCabeza(e)` (l.227)
- `EfectosDream:llama(l)` (l.232) — Sprite de un cuadro: la cabeza en (x, y, z) y la cola hacia (dx, dy, dz).
- `EfectosDream:luz(x, y, z, r, g, b, brillo, duracion, debil)` (l.254) — Destello de luz en (x, y, z) px. Con `debil` solo usa una luz libre.
- `EfectosDream:marca(x, y, _, radio, giro)` (l.276)
- `EfectosDream:actualizar()` (l.283) — Después de `tropas:actualizar`: estelas, restos, llamas y luces.
- `EfectosDream:dibujar()` (l.303) — Antes de `dream:present`: sube lo nuevo a la GPU, pide a 3Dream los misiles, los escombros y las marcas y enciende los destellos.
- `EfectosDream:prepararLuz()` (l.328) — Luz del sol, la luna, el cielo, la niebla y los destellos para el pase de efectos: lo mismo que acaba de usar 3Dream en este cuadro.
- `EfectosDream:dibujarEncima()` (l.381) — Después de `dream:present`: estelas, humo, fuego, chispas y llamas sobre la imagen de la escena, probados contra su profundidad.
- `EfectosDream:emitidas()` (l.415) — Cuántas partículas se han emitido (para el rótulo y las pruebas).

## batalla/dream/efectos/cinta.lua

Cinta de las estelas de humo en la GPU (Camila). Cada tramo son cuatro vértices (dos en cada punto, uno a cada lado) y dos triángulos; el sombreador (`estela_vertices.lua`) los abre hacia la cámara, los hace derivar y los…

- Tamaño: 181 líneas, 8 funciones públicas, 0 locales.
- Usa: ffi

- `Cinta.malla(tramos, uso)` (l.39) — Malla de `tramos` tramos (cuatro vértices y dos triángulos cada uno), a cero.
- `Cinta.nueva(dream, conversor, opciones)` (l.58) — `opciones`: cabezas (misiles en vuelo a la vez), tramos (anillo), porCuadro (tramos nuevos por cuadro), vida (s), sombreador, textura y parametros…
- `Cinta:punto(p, k, q, e)` (l.94) — Escribe los dos vértices del punto `q` (px del juego) en `p[k]` y `p[k + 1]`.
- `Cinta:tramo(e, a, b)` (l.106) — Tramo fijo del punto `a` al `b` de la estela `e`.
- `Cinta:cabeza(e, a, b)` (l.117) — Tramo de cabeza de la estela `e` (del último punto `a` a la tobera `b`).
- `Cinta:soltar(e)` (l.132) — La estela `e` pierde su cabeza (el misil ha caído).
- `Cinta:subir()` (l.145) — Sube las cabezas y los tramos nuevos.
- `Cinta:dibujar()` (l.166) — Dibuja todas las estelas con su sombreador (pase de efectos).

## batalla/dream/efectos/comun.lua

Datos del cuadro y código GLSL comunes de los efectos (Camila).

- Tamaño: 235 líneas, 2 funciones públicas, 1 locales.

- `Comun.enviarCuadro(sombreador)` (l.183) — Envía los datos del cuadro a un sombreador de efectos.
- `Comun.enviarDream(objeto)` (l.228) — Para los sombreadores registrados en 3Dream (escombros).

## batalla/dream/efectos/escombro_pixel.lua

Sombreador de píxeles de los escombros (Camila): color de la copia, rugoso; las chapas (vEfecto.z) algo metálicas. Opacos: van en el paso normal de 3Dream, con su sombra y su niebla.

- Tamaño: 21 líneas, 1 funciones públicas, 0 locales.

- `Sombreador:buildPixel()` (l.10)

## batalla/dream/efectos/escombro_vertices.lua

Sombreador de vértices de los escombros (Camila): trozos de tierra y roca, astillas y chapas que saltan en los impactos.

- Tamaño: 78 líneas, 3 funciones públicas, 0 locales.
- Usa: batalla/dream/efectos/comun

- `Sombreador:buildDefines()` (l.17)
- `Sombreador:buildVertex()` (l.43)
- `Sombreador:perTask(objeto)` (l.73)

## batalla/dream/efectos/lote.lua

Lote de partículas en la GPU (Camila): un anillo de copias de tamaño fijo que se escriben una sola vez, al nacer, y se dibujan todas en una llamada con instancias.

- Tamaño: 236 líneas, 6 funciones públicas, 2 locales.
- Usa: ffi

- `Lote.cuadro()` (l.70) — Cuadro de dos triángulos de -0,5 a 0,5 con sus UV: la base de los sprites.
- `Lote.nuevo(dream, opciones)` (l.89) — `opciones`: capacidad, porCuadro (copias nuevas por cuadro como mucho), base (malla de LÖVE de cada copia), nombre y dinamico.
- `Lote:emitir(p)` (l.159) — Escribe una copia con los datos de la tabla `p` (ver `efectos.lua`); en unidades de Dream y segundos. Devuelve false si el cuadro ya va lleno.
- `Lote:vaciar()` (l.179) — Lote dinámico: empieza el cuadro vacío.
- `Lote:subir()` (l.185) — Sube las copias nuevas del cuadro a la GPU.
- `Lote:dibujar()` (l.217) — Dibuja el lote: con su sombreador en el pase de efectos o, si es de 3Dream, pidiéndoselo al motor (antes de `dream:present`).

## batalla/dream/efectos/mallas.lua

Mallas de los escombros (Camila), hechas en código: un terrón o trozo de roca (icosaedro deformado), una astilla (listón afilado) y una chapa (placa fina doblada).

- Tamaño: 132 líneas, 3 funciones públicas, 3 locales.

- `Mallas.roca()` (l.74) — Trozo de roca o terrón: icosaedro aplastado con los vértices movidos.
- `Mallas.astilla()` (l.122) — Astilla: listón largo y fino que se afila en un extremo.
- `Mallas.metal()` (l.127) — Chapa: placa fina, algo doblada.

## batalla/dream/efectos/marcas.lua

Marcas de quemado en el suelo (Camila): cada una es una rejilla de 5 x 5 vértices pegada al relieve (`suelo:altura`) un palmo por encima, con la textura `marca` de `texturas.lua`.

- Tamaño: 136 líneas, 3 funciones públicas, 1 locales.
- Usa: ffi

- `Marcas.nuevas(dream, conversor, suelo, opciones)` (l.34)
- `Marcas:anadir(x, y, radio, giro)` (l.96) — Marca de `radio` m centrada en (x, y) px, girada `giro` rad.
- `Marcas:dibujar(ox, oy, oz)` (l.126)

## batalla/dream/efectos/misiles.lua

Misiles en vuelo por instancias (Camila): el mismo modelo que lleva el camión (`misil_synty4`), todos en una llamada por pieza.

- Tamaño: 71 líneas, 2 funciones públicas, 0 locales.
- Usa: batalla/dream/conversor, batalla/tropas, ffi

- `Misiles.nuevos(dream, conversor, objeto, capacidad)` (l.18) — `objeto`: el modelo cargado en 3Dream (con sus mallas); `capacidad`, los misiles en el aire a la vez como mucho.
- `Misiles:dibujar(tropas)` (l.40) — Escribe las matrices de los misiles de `tropas` y los pide a 3Dream.

## batalla/dream/efectos/sombreadores.lua

Sombreadores del pase de efectos (Camila): partículas (cuadros encarados a la cámara o trazos a lo largo de la velocidad) y la cinta de las estelas. Movimiento, luz, niebla y mezcla: ver `comun.lua`.

- Tamaño: 201 líneas, 2 funciones públicas, 0 locales.
- Usa: batalla/dream/efectos/comun

- `Sombreadores.particula()` (l.192)
- `Sombreadores.estela()` (l.196)

## batalla/dream/efectos/texturas.lua

Texturas de los efectos de la batalla (Camila), pintadas en código al arrancar con ruido: nada se importa. Todas son datos, no color: el canal rojo es el brillo o la densidad interior y el alfa, la cobertura.

- Tamaño: 216 líneas, 6 funciones públicas, 7 locales.
- Usa: ffi

- `Texturas.humo()` (l.120)
- `Texturas.fuego()` (l.129)
- `Texturas.chispa()` (l.138)
- `Texturas.estela()` (l.155)
- `Texturas.marca()` (l.178)
- `Texturas.crear()` (l.202) — Todas, pintadas una vez.

## batalla/dream/escena.lua

Comparador de la escena de batalla con 3DreamEngine. Reutiliza la misma simulación, terreno, cámara y controles de `batalla.escena`; solo cambia la preparación de materiales y el dibujo 3D.

- Tamaño: 502 líneas, 10 funciones públicas, 11 locales.
- Usa: batalla/carga, batalla/dream/biblioteca_pbr, batalla/dream/calidad, batalla/dream/conversor, batalla/dream/efectos, batalla/dream/estilo/mascara, batalla/dream/estilo/recursos, batalla/dream/estilo/sombra_cascadas, batalla/dream/instancias, batalla/dream/lote_unidades, batalla/dream/luz, batalla/dream/rayos, batalla/dream/sonido, batalla/dream/textura_terreno, batalla/dream/vegetacion, batalla/dream/visibilidad, batalla/escena, batalla/estelas, batalla/fisica, batalla/lanzamisiles, batalla/malla, batalla/soldados, batalla/tropas, ffi, lib.3DreamEngine, mundo/modelos3d

- `EscenaDream.nueva(mundo, combate)` (l.210)
- `EscenaDream:horaCielo()` (l.311) — Hora del cielo: el día y la fracción del reloj de la simulación (solo se leen).
- `EscenaDream:ponerHora()` (l.319)
- `EscenaDream:actualizar(dt)` (l.326)
- `EscenaDream:ajustarLienzos()` (l.337) — Hyprland puede ampliar la ventana después de que 3Dream haya creado sus lienzos. Se comprueba aquí para que nunca quede media pantalla sin dibujar.
- `EscenaDream:prepararCamara()` (l.344)
- `EscenaDream:dibujarUnidades()` (l.367) — Camiones y soldados por lotes rellenados por FFI (batalla/dream/lote_unidades.lua): las mismas transformaciones que con addInstance, sin tablas por…
- `EscenaDream:dibujarEsfera(x, y, z, tamano, malla)` (l.427)
- `EscenaDream:dibujarEfectos()` (l.432)
- `EscenaDream:dibujar()` (l.473)

## batalla/dream/estilo/follaje_sombreador.lua

Sombreador de píxeles del follaje (`follajeEstilo`, de la prueba de estilo de Camila, batalla/pruebas_estilo): como el `textured` de 3Dream (albedo de la textura por el color del material), pero inclina la normal hacia la cámara.

- Tamaño: 52 líneas, 3 funciones públicas, 0 locales.

- `FollajeSombreador:buildDefines()` (l.17)
- `FollajeSombreador:buildPixel()` (l.28)
- `FollajeSombreador:perMaterial(objetoSombreador, material)` (l.41)

## batalla/dream/estilo/geometria.lua

Constructor de mallas texturizadas para 3DreamEngine (de la prueba de estilo de Camila, batalla/pruebas_estilo/geometria.lua).

- Tamaño: 145 líneas, 9 funciones públicas, 0 locales.

- `Geometria.nueva()` (l.14)
- `Geometria:vertice(x, y, z, nx, ny, nz, u, v)` (l.24) — Añade un vértice: posición (m), normal y UV.
- `Geometria:triangulo(a, b, c)` (l.43) — Triángulo de tres vértices { x, y, z, nx, ny, nz, u, v }.
- `Geometria:cuadrilatero(a, b, c, d, dobleCara)` (l.52) — Cuadrilátero a-b-c-d (en sentido antihorario visto desde delante).
- `Geometria:escalar(factor)` (l.62) — Multiplica todas las posiciones por `factor` (las normales no cambian).
- `Geometria:caja()` (l.69) — Caja de la geometría (m): minX, minY, minZ, maxX, maxY, maxZ.
- `Geometria:triangulos()` (l.82)
- `Geometria:crearMalla(dream, material, sombreador)` (l.88) — Crea la malla de Dream con `material` y el sombreador de píxeles dado (por defecto 'textured').
- `Geometria.material(dream, nombre, opciones)` (l.122) — Material texturizado. `opciones`: textura, recorte (alpha-test), rugosidad y traslucidez.

## batalla/dream/estilo/hilo_texturas.lua

Hilo que pinta las texturas del estilo (texturas.lua) mientras la batalla genera el suelo. Devuelve por el canal, para cada textura, una tabla con su nombre y sus niveles de mipmap (ImageData); al final, 'fin'.

- Tamaño: 23 líneas, 0 funciones públicas, 0 locales.
- Usa: batalla/dream/estilo/texturas, love.filesystem, love.image, love.math, love.timer

## batalla/dream/estilo/impostor.lua

Impostor de pino: al arrancar se dibuja cada variante de pino completo en proyección ortográfica a un lienzo (de lado y desde arriba) y se guarda como textura recortada con mipmaps que conservan la cobertura (lienzo.lua).

- Tamaño: 213 líneas, 1 funciones públicas, 5 locales.
- Usa: batalla/dream/estilo/geometria, batalla/dream/estilo/lienzo, batalla/dream/estilo/texturas, ffi

- `Impostor.hornear(tronco, follaje, texturas, brilloFollaje)` (l.146) — Hornea la variante: devuelve la textura y la Geometria del impostor. `tronco` y `follaje` son las Geometria del pino completo.

## batalla/dream/estilo/lienzo.lua

Lienzo de píxeles en memoria (flotantes RGBA de 0 a 1) para generar texturas en código: ruido que se repite sin costura, trazos con grosor y paso a una Image de LÖVE con mipmaps que conservan la cobertura del alfa.

- Tamaño: 226 líneas, 10 funciones públicas, 3 locales.
- Usa: ffi

- `Lienzo.nuevo(ancho, alto, r, g, b, a)` (l.10)
- `Lienzo.ruidoCiclico(u, v, frecuencia, octavas, semilla)` (l.27) — Ruido fractal que se repite en u y v (de 0 a 1): se recorre un toro en el ruido 4D de LÖVE, así el borde derecho empalma con el izquierdo.
- `Lienzo:indice(x, y)` (l.48)
- `Lienzo:mezclar(x, y, r, g, b, a, envolver)` (l.54) — Mezcla un color sobre el píxel (x, y) con opacidad `a`. Con `envolver`, las coordenadas que se salen entran por el otro lado.
- `Lienzo:pintar(x, y, r, g, b, a, envolver)` (l.69) — Como `mezclar`, pero también acumula el alfa (para texturas recortadas).
- `Lienzo:trazo(x0, y0, x1, y1, ancho0, ancho1, color0, color1, opciones)` (l.80) — Trazo de (x0, y0) a (x1, y1) con grosor que pasa de `ancho0` a `ancho1` píxeles y color { r, g, b } que va de `color0` a `color1`.
- `Lienzo:rellenarTransparentes()` (l.113) — Pinta el color de los píxeles transparentes con el promedio de los opacos: el filtrado no mete bordes negros alrededor del follaje.
- `Lienzo:niveles(corte)` (l.180) — Niveles de mipmap (ImageData) del lienzo. Si `corte` existe (textura recortada), cada nivel escala su alfa para cubrir la misma fracción que el…
- `Lienzo.imagenDeNiveles(niveles, repetir)` (l.208) — Image con mipmaps de unos niveles (`Lienzo:niveles`), con filtro anisótropo y repetida o recortada en los bordes.
- `Lienzo:imagen(corte, repetir)` (l.221) — Image con mipmaps (ver `Lienzo:niveles`).

## batalla/dream/estilo/lote_rapido.lua

Lote de instancias que se rellena por FFI (de la prueba de estrés de Camila, batalla/pruebas_estilo/lote_rapido.lua), con el tono por copia de la batalla: cada copia son 15 flotantes (tres columnas de giro, la posición y el…

- Tamaño: 180 líneas, 12 funciones públicas, 0 locales.
- Usa: batalla/dream/instancias_tono, ffi

- `LoteRapido.nuevo(dream, malla, capacidad, opciones)` (l.24) — `opciones.soloSombra`: el lote no se dibuja, solo proyecta sombra. `opciones.sinSombra`: se dibuja pero no proyecta sombra.
- `LoteRapido:reservar(capacidad)` (l.58) — Memoria para `capacidad` copias (sin conservar las que hubiera).
- `LoteRapido:reservarDatos(capacidad)` (l.65) — Memoria que se sube a la GPU y búfer de copias de la malla.
- `LoteRapido:reservarCascadas(capacidad)` (l.71)
- `LoteRapido:crecer()` (l.78) — Dobla la capacidad conservando las copias ya escritas.
- `LoteRapido:vaciar()` (l.99)
- `LoteRapido:clase(clase)` (l.109) — En un lote de sombra, las copias siguientes van a la cascada `clase`.
- `LoteRapido:copiar(fuente, indice)` (l.121) — Copia la instancia `indice` (desde 0) de un arreglo de flotantes con el mismo formato.
- `LoteRapido:copiarBloque(fuente, n)` (l.131) — Copia `n` copias seguidas desde `fuente` (un paquete de una celda).
- `LoteRapido:subir()` (l.141) — Sube las copias a la GPU. Hay que llamarlo antes de dream:draw.
- `LoteRapido:dibujar(dream)` (l.169)
- `LoteRapido:triangulos()` (l.175)

## batalla/dream/estilo/mascara.lua

Máscara del suelo de la batalla (R = tierra, G = hierba seca), 2 m por píxel sobre los 3 km del área: pinocha y tierra al pie de los pinos y los abetos (como la máscara de la prueba de estrés de Camila,…

- Tamaño: 71 líneas, 1 funciones públicas, 0 locales.
- Usa: batalla/vegetacion, ffi

- `Mascara.crear(suelo)` (l.18) — Imagen de la máscara del suelo `suelo` y su rectángulo en metros desde el centro del área (x, y, ancho, alto), como lo pide el sombreador.

## batalla/dream/estilo/matas.lua

Matas de hierba y arbustos de planos cruzados con textura recortada (de la prueba de estilo de Camila, batalla/pruebas_estilo/matas.lua).

- Tamaño: 62 líneas, 2 funciones públicas, 0 locales.
- Usa: batalla/dream/estilo/geometria

- `Matas.mata(semilla, detalle)` (l.14)
- `Matas.arbusto(semilla)` (l.36)

## batalla/dream/estilo/pino.lua

Pino procedural con ramas de planos (de la prueba de estilo de Camila, batalla/pruebas_estilo/pino.lua), como los de la referencia: tronco cónico con corteza, tronco desnudo abajo y pisos (verticilos) de ramas arriba.

- Tamaño: 207 líneas, 1 funciones públicas, 6 locales.
- Usa: batalla/dream/estilo/geometria

- `Pino.nuevo(semilla, detalle, opciones)` (l.145) — Pino de la semilla `semilla`. `detalle` (1 cerca, 2 lejos) reduce ramas. `opciones.abeto`: copa que empieza más abajo y más estrecha (abeto).

## batalla/dream/estilo/recursos.lua

Recursos del estilo de la batalla (de la prueba de Camila): texturas, materiales y mallas de los pinos (completo, simplificado e impostor), las rocas (tres detalles), las matas (dos detalles) y los arbustos.

- Tamaño: 167 líneas, 3 funciones públicas, 3 locales.
- Usa: batalla/dream/estilo/geometria, batalla/dream/estilo/impostor, batalla/dream/estilo/matas, batalla/dream/estilo/pino, batalla/dream/estilo/roca, batalla/dream/estilo/texturas, mundo/ruido

- `Recursos.registrar(dream)` (l.38) — Registra los sombreadores del estilo (antes de `dream:init`).
- `Recursos.empezar()` (l.49) — Empieza a pintar las texturas en un hilo (ver texturas.lua).
- `Recursos.de(dream, semilla)` (l.126) — Los recursos de la semilla `semilla` (se hacen la primera vez).

## batalla/dream/estilo/roca.lua

Rocas redondeadas (de la prueba de estilo de Camila, batalla/pruebas_estilo): una esfera de meridianos y paralelos deformada con ruido 3D a dos escalas, aplastada y medio enterrada.

- Tamaño: 85 líneas, 1 funciones públicas, 1 locales.
- Usa: batalla/dream/estilo/geometria

- `Roca.nueva(semilla, radio, detalle)` (l.16) — Roca de radio medio `radio` (m) y semilla `semilla`.

## batalla/dream/estilo/sombra_cascadas.lua

Recorte de los emisores de sombra por cascada. 3Dream pinta las tres cascadas del sol con todos los emisores (su cámara de sombra no recorta): un pino a 100 m se dibuja también en la cascada de 13 m.

- Tamaño: 158 líneas, 7 funciones públicas, 0 locales.

- `SombraCascadas.unico(dream, sol)` (l.20) — El recorte de cascadas de la partida, con el sol `sol` y sin lotes.
- `SombraCascadas.nuevo(dream, sol)` (l.32)
- `SombraCascadas:registrar(lotes)` (l.45) — Añade lotes de sombra (con `porCascada`).
- `SombraCascadas:actualizar(ojo)` (l.55) — Base de la luz y radios (m) de las cascadas para este cuadro. `ojo` es la posición de la cámara en metros.
- `SombraCascadas:clase(x, y, z, radio)` (l.88) — Cascada más pequeña que contiene la esfera (m); 3 si ninguna.
- `SombraCascadas:cascada(camara)` (l.105) — Índice de la cascada de una cámara de sombra, o nil.
- `SombraCascadas:instalar()` (l.118)

## batalla/dream/estilo/texturas.lua

Texturas procedurales del estilo de la batalla (de la prueba de Camila, batalla/pruebas_estilo). Ninguna viene de un archivo: se pintan en código con ruido y trazos (lienzo.lua) al arrancar.

- Tamaño: 389 líneas, 11 funciones públicas, 4 locales.
- Usa: batalla/dream/estilo/lienzo

- `Texturas.hierbaVerde()` (l.80)
- `Texturas.hierbaSeca()` (l.92)
- `Texturas.tierra()` (l.105) — Tierra rojiza con pinocha (trazos finos rojizos) y piedrecitas.
- `Texturas.corteza()` (l.125) — Corteza: surcos verticales (ruido estirado en v) marrón rojizo.
- `Texturas.roca()` (l.149) — Roca gris con manchas de liquen verdoso y claro.
- `Texturas.rama(semilla)` (l.180) — Rama de pino vista desde arriba. u (x) va del tronco (0) a la punta (1), v (y) de un borde al otro con el eje en 0,5.
- `Texturas.mata(seca)` (l.247) — Mata de hierba de perfil: briznas curvas que nacen abajo (v = 1).
- `Texturas.generarNiveles()` (l.324) — Niveles de mipmap (ImageData) de todas las texturas, por nombre. No usa love.graphics: es lo que hace el hilo (hilo_texturas.lua).
- `Texturas.imagenes(niveles)` (l.333) — Las imágenes de LÖVE de unos niveles (en el hilo principal).
- `Texturas.empezar()` (l.347) — Empieza a pintar las texturas en un hilo (tardan ~1,4 s): la batalla genera el suelo mientras tanto.
- `Texturas.crear()` (l.357) — Las texturas (espera al hilo si hace falta; sin hilo, las pinta aquí).

## batalla/dream/estilo/tiempo_gpu.lua

Tiempo de GPU de cada cuadro con consultas GL_TIME_ELAPSED de OpenGL, pedidas por FFI a SDL_GL_GetProcAddress. LÖVE no las usa, así que no se pisan. Se lee el resultado de hace unos cuadros para no esperar a la GPU.

- Tamaño: 90 líneas, 3 funciones públicas, 1 locales.
- Usa: ffi

- `TiempoGpu.nuevo()` (l.40)
- `TiempoGpu:inicio()` (l.64)
- `TiempoGpu:fin()` (l.81)

## batalla/dream/instancias.lua

Adaptador de los lotes móviles de la batalla. Conserva la esfera local al ampliar el buffer y calcula sus límites con las mismas columnas que recibe el shader de instancias de 3DreamEngine.

- Tamaño: 94 líneas, 1 funciones públicas, 5 locales.

- `Instancias.nuevas(dream, malla)` (l.82)

## batalla/dream/instancias_tono.lua

Instancias de 3DreamEngine con tono por copia. El `instancedMesh` de la librería solo lleva el giro y la posición de cada copia; aquí se añade un atributo `InstanceTono` (vec3, por copia) que el shader de vértices de la…

- Tamaño: 121 líneas, 2 funciones públicas, 5 locales.
- Usa: ffi

- `InstanciasTono.nuevas(dream, malla)` (l.102) — Instancias de `malla` (una malla de Dream ya creada) con tono por copia.
- `InstanciasTono.memoria(cantidad)` (l.115) — Memoria para `cantidad` copias: ByteData y su puntero de flotantes.

## batalla/dream/lote_unidades.lua

Relleno por FFI de los lotes de las unidades (camiones lanzamisiles y soldados) de la escena 3Dream.

- Tamaño: 110 líneas, 5 funciones públicas, 0 locales.
- Usa: batalla/dream/conversor, ffi

- `LoteUnidades.preparar(lote)` (l.22) — Prepara el lote (de `Instancias.nuevas`, ya con su `resize`) para el relleno por FFI.
- `LoteUnidades.vaciar(lote)` (l.30)
- `LoteUnidades.escribir(conversor, m, destino)` (l.40) — Escribe en `destino` (12 flotantes) la copia de la matriz del juego `m` (por filas, px, z arriba): columnas del giro en ejes de Dream y posición,…
- `LoteUnidades.anadir(lote, fuente)` (l.49) — Añade al lote la copia escrita en `fuente` (12 flotantes).
- `LoteUnidades.subir(dream, lote)` (l.87) — Sube las copias y pone la esfera que las envuelve. Devuelve cuántas hay.

## batalla/dream/luz.lua

Luz y cielo de la batalla según la hora del mundo, con la extensión `sky` de 3DreamEngine como en el ejemplo firstpersongame: `sky:setDaytime(sol, hora)`, `sky:setSkyColor` y niebla del color del cielo.

- Tamaño: 194 líneas, 5 funciones públicas, 2 locales.
- Usa: lib.3DreamEngine, lib.3DreamEngine.extensions.sky

- `Luz.horaCielo(dia, fraccion)` (l.67) — Hora de la extensión sky para el día y la fracción del reloj del juego.
- `Luz.configurarMotor()` (l.104) — Cielo, bruma, oclusión y resplandor del motor (antes de `dream:init()`).
- `Luz.nuevas()` (l.123) — Sol y luna, cada uno con su sombra. La hora se pone con `Luz.actualizar`.
- `Luz.configurarSombras(luces, calidad)` (l.138) — Sombras del sol y de la luna según la calidad (batalla/dream/calidad.lua): tres cascadas con factor 3; la última llega justo a `calidad.sombra` m.
- `Luz.actualizar(sol, luna, hora, activas)` (l.157) — Pone la hora `hora` (día más fracción de la extensión, ver `horaCielo`): sol, luna, ambiente y niebla. Devuelve las luces que iluminan.

## batalla/dream/rayos.lua

Consultas geométricas de la batalla mediante la extensión raytrace de 3Dream: selección precisa, visibilidad contra el relieve e impactos.

- Tamaño: 92 líneas, 7 funciones públicas, 0 locales.
- Usa: batalla/dream/conversor, lib.3DreamEngine.extensions.raytrace

- `Rayos.nuevo(dream, conversor, mallaTerreno, mallaUnidad, unidades)` (l.11)
- `Rayos:actualizarUnidad(unidad)` (l.28)
- `Rayos:rayoDePantalla(x, y)` (l.41)
- `Rayos:unidadEnPantalla(x, y)` (l.48)
- `Rayos:segmento(x0, y0, z0, x1, y1, z1)` (l.65)
- `Rayos:lineaVisible(origen, destino)` (l.73)
- `Rayos:impacto(x0, y0, z0, x1, y1, z1)` (l.79)

## batalla/dream/sonido.lua

Audio posicional de la batalla mediante la extensión sound de 3Dream. Todos los archivos son mono para que OpenAL pueda ubicarlos en el mundo.

- Tamaño: 29 líneas, 3 funciones públicas, 0 locales.
- Usa: lib.3DreamEngine.extensions.sound

- `Sonido.nuevo(dream, conversor)` (l.9)
- `Sonido:reproducir(nombre, x, y, z, volumen, tono)` (l.17)
- `Sonido:actualizarOyente(ojo, mira)` (l.22)

## batalla/dream/textura_terreno.lua

Shader del terreno de batalla (`terrenoNatural`): el suelo de la prueba de estilo de Camila (batalla/pruebas_estilo/suelo_sombreador.lua) teñido con el color por zona del mapa (batalla/color_terreno.lua, por vértice).

- Tamaño: 206 líneas, 6 funciones públicas, 0 locales.

- `TexturaTerreno.blanca()` (l.31) — Textura de 1 x 1 para la máscara si no hay otra.
- `TexturaTerreno.crear()` (l.41) — Compatibilidad: la escena pedía una textura; ya no se lee.
- `TexturaTerreno:buildDefines()` (l.45)
- `TexturaTerreno:buildPixel()` (l.96)
- `TexturaTerreno:buildVertex()` (l.184)
- `TexturaTerreno:perMaterial(objetoSombreador, material)` (l.190)

## batalla/dream/vegetacion.lua

Dibujo de la vegetación y las rocas de la batalla con 3DreamEngine, con el estilo y las optimizaciones de la prueba de estrés de Camila (batalla/pruebas_estilo/vegetacion_grande.lua):

- Tamaño: 1143 líneas, 26 funciones públicas, 5 locales.
- Usa: batalla/colocacion, batalla/dream/calidad, batalla/dream/conversor, batalla/dream/estilo/lote_rapido, batalla/dream/estilo/recursos, batalla/dream/instancias_tono, batalla/vegetacion, ffi

- `VegetacionDream.nueva(dream, conversor, suelo, opciones)` (l.91)
- `VegetacionDream:lote(malla, triangulos, tipo, sombra)` (l.131) — Lote nuevo de la malla `malla` (de Dream). `tipo` es para la cuenta.
- `VegetacionDream:lotePino(pieza, tipo, sombra)` (l.143) — Par de lotes (tronco y follaje) de un pino, para dibujar o para sombra.
- `VegetacionDream:crearLotes()` (l.151)
- `VegetacionDream:crearAlmacen(capacidad)` (l.239) — Memoria de las copias: 15 flotantes de dibujo y los datos del recorte.
- `VegetacionDream:crecerAlmacen()` (l.257)
- `VegetacionDream:escribir(k, c, grupo)` (l.273) — Escribe la copia `c` en la posición `k` del almacén: columnas del giro en ejes de Dream (y arriba), posición y tono.
- `VegetacionDream:agregar(c)` (l.310) — Añade la copia `c` al almacén y a su celda.
- `VegetacionDream:crearCeldas()` (l.358)
- `VegetacionDream:celdaDe(x, y)` (l.384)
- `VegetacionDream:cerrarCeldas()` (l.397) — Esfera de cada celda (px): su columna de copias con el alcance de la planta más grande, de pie o caída. Solo quedan en la lista las que tienen algo.
- `VegetacionDream:actualizarPlanos(m)` (l.476) — Planos del frustum (px del juego, normalizados) de la matriz de vista y proyección `m` (por filas): izquierda, derecha, abajo, arriba y cerca.
- `VegetacionDream:enVista(x, y, z, radio)` (l.504) — ¿Toca la esfera (x, y, z, radio) en px el frustum? Con `self.margen` (seno de un ángulo), cada plano se abre ese ángulo hacia fuera: la esfera se…
- `VegetacionDream:hierbaPendiente(x, y)` (l.523) — Hierba y flores: la baldosa de 200 m más cercana a la cámara que aún no tenga, si está a menos del alcance de las matas (una por cuadro).
- `VegetacionDream:aplicarDerribos()` (l.556) — Árboles derribados desde el último cuadro: se reescriben sus copias.
- `VegetacionDream:actualizar(ex, ey, ez, matriz)` (l.585) — Rellena los lotes para la cámara. `matriz` es la de vista y proyección de la cámara de la batalla (Camara:matrices) y (ex, ey, ez) el ojo en px.
- `VegetacionDream:guardarVista(ex, ey, ez, m)` (l.625)
- `VegetacionDream:camaraSeAleja(ex, ey, ez, m)` (l.635) — ¿Se ha salido la cámara de lo que cubre el último relleno?
- `VegetacionDream:paquetes(celda, grupo)` (l.659) — Paquetes de las copias de `grupo` en la celda: por especie y variante, sus copias seguidas en memoria FFI, para copiarlas a un lote de una vez…
- `VegetacionDream:prepararDistancias()` (l.729) — Distancias (px) de este relleno y sus cuadrados.
- `VegetacionDream:copiarUniforme(objeto, grupo, d0, clase)` (l.780) — Todas las copias de `grupo` de `objeto` (una celda o un bloque) caen en el mismo detalle, el de la distancia `d0` (px): se copian sus paquetes.
- `VegetacionDream:copiarUnaAUna(celda, grupo, ex, ey)` (l.884) — Las copias de `grupo` de la celda, una a una con su distancia a (ex, ey).
- `VegetacionDream:enteraEnVista(x, y, z, radio)` (l.1010) — ¿Está la esfera (x, y, z, radio) en px entera dentro del frustum?
- `VegetacionDream:claseDe(objeto)` (l.1026) — Cascada del sol de un objeto (celda o bloque) entero.
- `VegetacionDream:rellenar(ex, ey, ez)` (l.1039) — Rellena los lotes: los bloques de 240 m enteros en vista y en un solo detalle copian sus paquetes de una vez; los demás bajan a sus celdas de 30 m,…
- `VegetacionDream:dibujar()` (l.1131) — Dibuja los lotes con copias (y los de sombra, que solo van a las sombras).

## batalla/dream/viento.lua

Shader de vértices de la vegetación de batalla (`vientoBatalla`): aplica el tono de cada copia (`InstanceTono`, ver instancias_tono.lua) sobre el color lineal del vértice.

- Tamaño: 29 líneas, 2 funciones públicas, 0 locales.

- `Viento:buildDefines()` (l.9)
- `Viento:buildVertex()` (l.19)

## batalla/dream/visibilidad.lua

Recorte de la cámara de batalla por esferas y planos normalizados. 3Dream extrae los planos sin normalizar y compensa el radio con un factor fijo: con FOV de 40° descarta objetos que todavía cruzan el borde visible.

- Tamaño: 54 líneas, 3 funciones públicas, 0 locales.

- `Visibilidad.actualizarPlanos(camara)` (l.10) — Los seis planos de recorte en unidades de mundo. El término independiente se normaliza junto con la normal para poder compararlo con un radio real.
- `Visibilidad.enFrustum(camara, posicion, radio, _identificador)` (l.35) — Mantiene la firma de Dream (posición, radio, identificador). La prueba depende del volumen actual, no de una caché compartida entre copias.
- `Visibilidad.instalar(camara)` (l.47) — Instala el recorte solo en esta cámara; conserva las cámaras del motor.

## batalla/efectos.lua

Efectos de la batalla (Camila): estelas de humo de los misiles, nube de lanzamiento, fogonazos, impactos (misil, bala de tanque, fusil; contra el suelo, un vehículo, el agua, un árbol o una roca), restos que arden, destellos de…

- Tamaño: 852 líneas, 30 funciones públicas, 4 locales.
- Usa: batalla/tropas

- `Efectos.nuevos(tropas, suelo, salida, calidad)` (l.105) — `tropas` (para leer misiles, balas y unidades), `suelo` (alturas y agua), `salida` y el nombre de la calidad.
- `Efectos:cuantas(n, minimo)` (l.141) — Cuántas de `n` salen con la calidad actual (al menos `minimo`).
- `Efectos:entre(a, b)` (l.145)
- `Efectos:cono(x, y, z, apertura)` (l.150) — Dirección al azar dentro de un cono de `apertura` rad alrededor de (x, y, z).
- `Efectos:nueva(x, y, z)` (l.169) — Deja la partícula de trabajo en (x, y, z) px con valores neutros.
- `Efectos:emitir(clase)` (l.191)
- `Efectos:superficie(x, y)` (l.196) — Altura del suelo o del agua en (x, y) y si es agua.
- `Efectos:destello(x, y, z, tam, vida, color)` (l.209) — Fogonazo: un destello que dura unas centésimas.
- `Efectos:bolaDeFuego(x, y, z, escala, n)` (l.223) — Bola de fuego que se abre, sube y se apaga.
- `Efectos:chispas(x, y, z, nx, ny, nz, apertura, n, rapidez, metal, sueloZ, grosor)` (l.244) — Chispas en un cono alrededor de (nx, ny, nz); `metal` más blancas y rápidas.
- `Efectos:tierra(x, y, z, nx, ny, nz, apertura, n, rapidez, tam, sueloZ, color0, color1)` (l.265) — Tierra que salta en grumos (partículas de polvo oscuro con gravedad).
- `Efectos:escombros(clase, x, y, z, nx, ny, nz, apertura, n, rapidez, tam, sueloZ, color)` (l.285) — Escombros 3D (`clase` roca, astilla o metal) que saltan y ruedan.
- `Efectos:ondaDePolvo(x, y, z, n, rapidez, tam, vida, color0, color1, alfa)` (l.310) — Polvo que sale en anillo pegado al suelo (onda de la explosión).
- `Efectos:columna(x, y, z, n, duracion, tam, vida, color0, color1, alfa)` (l.330) — Columna de humo que sigue saliendo `duracion` s y sube despacio.
- `Efectos:explosion(x, y, z, escala, superficie, dx, dy, dz)` (l.356) — Explosión grande (misil, vehículo que revienta). `escala` 1 = misil.
- `Efectos:salpicadura(x, y, nivel, escala, conLuz)` (l.386) — Salpicadura en el agua: columna, gotas, espuma y bruma.
- `Efectos:astillas(x, y, z, escala)` (l.441) — Astillas y agujas de un árbol alcanzado.
- `Efectos:impactoPequeno(x, y, z, arma, superficie, dx, dy, dz)` (l.466) — Impacto pequeño: bala de tanque (`canon`) o de fusil, contra el suelo, un vehículo, un soldado, el agua, un árbol o una roca.
- `Efectos:humoGolpe(x, y, z, tam, color0, color1)` (l.521) — Nubecilla de un golpe: sube un poco y se abre.
- `Efectos:lanzamiento(m, x, y, z, dx, dy, dz)` (l.542) — Un misil sale del tubo: fogonazo, llamarada hacia atrás, nube de lanzamiento que se queda en el suelo, y su estela.
- `Efectos:bocanadaEstela(e, punto)` (l.618) — Bocanada de la estela: da volumen a la cinta vista de frente.
- `Efectos:avanzarEstela(e, t, reloj, final)` (l.635) — Avanza la estela `e` hasta la fracción `t` del vuelo en el instante `reloj`: añade puntos cada `pasoEstela` m (a alta velocidad no se deshilacha) y…
- `Efectos:impactoMisil(m, superficie)` (l.675) — El misil `m` cae (al final de su vuelo o contra una loma o un árbol).
- `Efectos:impactoBala(b, x, y, z, superficie)` (l.690) — Una bala llega a (x, y, z) contra `superficie` ('terreno', 'arbol', 'roca', 'vehiculo' o 'soldado').
- `Efectos:disparo(arma, x, y, z, dx, dy, dz)` (l.696) — Disparo de `arma` ('canon' o 'fusil') desde la boca (x, y, z) hacia (dx, dy, dz).
- `Efectos:destruccion(u, explota)` (l.741) — Un vehículo cae: si revienta, explosión; y a partir de ahora arde.
- `Efectos:olvidar(u)` (l.755) — Deja de hacer humo por `u` (un averiado que se retira del campo: oleadas).
- `Efectos:arder(resto, reloj)` (l.766) — Humo (y al principio fuego) de los restos.
- `Efectos:llama(x, y, z, dx, dy, dz, largo, ancho, color0, emision, alfa)` (l.808) — Sprite de un cuadro: posición (px), dirección hacia la cola y largo (m), ancho (m), colores y emisión.
- `Efectos:actualizar()` (l.820) — Avanza estelas y restos y pone las llamas de tobera y los trazadores.

## batalla/escena.lua

Escena de batalla en 3D (prototipo): al entrar en un combate del mapa se genera el sitio real en 3D low-poly (batalla/suelo.lua) con las tropas que de verdad llevan los dos bandos (batalla/tropas.lua), y se ve la pelea con una…

- Tamaño: 884 líneas, 26 funciones públicas, 2 locales.
- Usa: batalla/camara, batalla/carga, batalla/control, batalla/sombreado, batalla/suelo, batalla/tropas, interfaz/tema, mundo/iso, mundo/simulacion

- `Escena.combateDeGrupo(mundo, gr)` (l.34) — Combate de un grupo, si está peleando: un ejército en misión de atacar ya formado (desplegado a la salida o en su objetivo).
- `Escena.describir(mundo, fuerzas, objetivo, angulo)` (l.58) — Descripción de un combate que usa la escena: `fuerzas` (un grupo o un sitio, con nación, tanques y lanzacohetes) ataca `objetivo` (un sitio)…
- `Escena.combateProvocado(mundo, x, y)` (l.102) — Para probar la escena sin esperar a una guerra: un combate imaginado (la simulación no lo tiene) entre la ciudad más cercana a (x, y) y la ciudad de…
- `Escena.buscarCombate(mundo, x, y)` (l.129) — El combate más cercano a (x, y) (a menos de `Escena.cercaParaEntrar`), o nil. Sin punto, el primero (en orden fijo), mejor si ya está en su objetivo.
- `Escena.nueva(mundo, combate)` (l.155)
- `Escena:encuadrarOrganizacion()` (l.181) — Encuadre de organización: una vista aérea baja sobre la formación del jugador. Desde aquí la cámara queda libre para recorrer el terreno.
- `Escena:caben(margen)` (l.214) — ¿Caben todos los vehículos en la pantalla con la cámara como está? `margen` es la fracción de la pantalla que se usa (0,85: se deja un borde).
- `Escena:encuadrarBandos(inclinacion)` (l.234) — Encuadre por defecto: los dos bandos enteros en la pantalla, mirando de lado al avance (el atacante a la izquierda) o, si la pantalla es estrecha,…
- `Escena:encuadrar(modo)` (l.268) — Encuadres: 'normal' (organización aérea baja del atacante), 'tanques' (los dos bandos, más bajo, para ver los trazadores), 'cerca' (un tanque del…
- `Escena:listaParaFoto(modo)` (l.347) — Para las capturas: ¿se ve ya lo que el encuadre quiere enseñar? 'cerca', un tanque cerca de la cámara que acaba de disparar; 'tanques', trazadores…
- `Escena:actualizar(dt)` (l.364)
- `Escena:vigilarFin()` (l.396) — La pelea termina sola (decisión del dueño): la primera vez que `Tropas:fin` da un final se fija en `self.fin` ({ pierde, retira, motivo, desde }) y…
- `Escena:dibujarFin()` (l.417) — Aviso del final en el centro de la pantalla.
- `Escena:colorSitio()` (l.482) — Color de nación para el edificio atacado. En campo abierto no hay `sitio`: el suelo y las plantas usan sus propios colores, así que el color neutro…
- `Escena:dibujar()` (l.487)
- `Escena:dibujarRotulo()` (l.588) — Rótulo arriba a la izquierda: quién pelea, qué queda, la munición de cada bando y los controles.
- `Escena:aPantalla(m, x, y, z, w, h)` (l.686) — Punto de pantalla de (x, y, z) con la cámara de la escena, o nil si queda detrás o fuera.
- `Escena:dibujarAvisos()` (l.703) — Avisos sobre las unidades (§3.6.6): encima de cada unidad en pie sin munición, una marca roja y, si cabe sin pisar otro letrero ni el rótulo, «Sin…
- `Escena:tecla(tecla)` (l.759) — Tecla pulsada. Devuelve 'salir' con Esc (main.lua vuelve al mapa).
- `Escena:pulsar(x, y, boton)` (l.783) — Captura relativa mientras se mantiene el botón derecho: el borde de la pantalla no interrumpe la rotación en primera persona.
- `Escena:liberarRaton()` (l.805) — Devuelve el cursor al modo anterior y cancela el arrastre activo.
- `Escena:foco(enfocada)` (l.817) — Alt-tab cancela el gesto para no dejar el cursor capturado al volver.
- `Escena:mover(x, y, dx, dy)` (l.825) — Usa los deltas reales de LÖVE aunque el cursor no cambie de coordenadas.
- `Escena:soltar(x, y, boton)` (l.849) — Suelta un botón. Izquierdo: clic = elegir (Mayús suma o quita; doble clic, las de su tipo a la vista); arrastre = cuadro.
- `Escena:rueda(dy)` (l.871) — La rueda desplaza físicamente al observador, manteniendo la lente fija.
- `Escena.vistaDelCentro(mundo, combate)` (l.878) — Punto de la vista del mapa (isométrica) en el centro de la batalla: para comparar el mismo sitio en el mapa.

## batalla/estelas.lua

Estelas de humo de los misiles de la escena de batalla: una cinta continua que sigue al misil por el aire, se ensancha y se desvanece con el tiempo, y se queda un rato colgada después de que el misil cae.

- Tamaño: 132 líneas, 5 funciones públicas, 0 locales.
- Usa: ffi

- `Estelas.nuevas()` (l.31)
- `Estelas:nueva()` (l.42) — Estela nueva (sin puntos): se le van añadiendo con `apuntar`.
- `Estelas:apuntar(e, x, y, z, reloj)` (l.49) — Punto de la estela `e` en (x, y, z) en el instante `reloj`, si ya toca.
- `Estelas:actualizar(reloj)` (l.60) — Olvida los puntos ya desvanecidos y las estelas vacías.
- `Estelas:dibujar(shader, reloj, ex, ey, ez)` (l.74) — Dibuja todas las estelas vistas desde (ex, ey, ez).

## batalla/fisica.lua

Mundo físico 3Dream de la batalla. La extensión integra el movimiento en X/Z con Box2D y resuelve la altura Y contra una malla simplificada del relieve. Las posiciones públicas de Tropas siguen expresadas en píxeles.

- Tamaño: 524 líneas, 20 funciones públicas, 4 locales.
- Usa: batalla/derribo, batalla/dream/conversor, batalla/malla, lib.3DreamEngine, lib.3DreamEngine.extensions.physics

- `Fisica.nueva(suelo, unidades)` (l.79)
- `Fisica:crearTerreno()` (l.97)
- `Fisica:crearArboles()` (l.125)
- `Fisica:crearLimite()` (l.152) — Límite (Valeria): aro estático de Box2D en el borde de `suelo.limite` (batalla/limite.lua).
- `Fisica:crearAgua()` (l.178) — Agua (Valeria): paredes estáticas en las orillas (`suelo.agua.bordes`, batalla/agua.lua), sin rozamiento ni rebote como el límite: ningún vehículo…
- `Fisica:transitable(unidad, x, y)` (l.199) — ¿Acepta el terreno a `unidad` en (x, y)? El suelo no cambia: la última respuesta se guarda en la unidad y, si no se ha movido (quieta, parada a…
- `Fisica:muestrearTransitable(unidad, x, y)` (l.208)
- `Fisica:guardarSeguro(unidad)` (l.230)
- `Fisica:restaurarSeguro(unidad)` (l.251)
- `Fisica:crearUnidad(unidad)` (l.279)
- `Fisica:crearUnidades()` (l.306)
- `Fisica:crearResto(rueda)` (l.313) — La rueda conserva su tamaño; colisiona con el suelo y árboles, sin empujar tropas.
- `Fisica:sincronizarRestos()` (l.340) — Recoge la posición física y retira del motor los restos ya apoyados.
- `Fisica:iniciarCuadro()` (l.371)
- `Fisica:impulsar(unidad, rumbo, velocidad)` (l.377)
- `Fisica:conducir(unidad, velocidad, direccionRuedas, entreEjes)` (l.406) — Conduce un vehículo con ruedas delanteras: el giro nace del ángulo de esas ruedas.
- `Fisica:frenar(unidad)` (l.443)
- `Fisica:sincronizar(unidad)` (l.456)
- `Fisica:apoyar(unidad)` (l.488) — Agua (Valeria): el vehículo se apoya en el suelo real (`Suelo:altura`, la superficie dibujada), no en la malla gruesa de colisión.
- `Fisica:actualizar(dt)` (l.503)

## batalla/impactos.lua

Choques de balas y misiles con el terreno y los árboles de la batalla (Valeria). Todo en px del juego (1 px = 10 cm, z hacia arriba).

- Tamaño: 233 líneas, 4 funciones públicas, 3 locales.

- `Impactos.arboles(suelo, x0, y0, z0, x1, y1, z1)` (l.100) — Choque con los árboles y rocas grandes: el menor t (y su planta) o nil.
- `Impactos.terreno(suelo, x0, y0, z0, x1, y1, z1)` (l.163) — Primer t en que el segmento pasa bajo el terreno, o nil.
- `Impactos.rayo(suelo, x0, y0, z0, x1, y1, z1, soloTerreno)` (l.201) — Primer choque del segmento (x0, y0, z0) → (x1, y1, z1) con el terreno o con un árbol o roca grande: { x, y, z, t, tipo = 'terreno' | 'arbol' |…
- `Impactos.visible(suelo, x0, y0, z0, x1, y1, z1)` (l.228) — ¿Se ven (x0, y0, z0) y (x1, y1, z1) sin una loma en medio?

## batalla/lanzamisiles.lua

Articulaciones del camión: rueda según el desplazamiento real y eleva la rampa sin mover el chasis. Ambos renderizadores usan las mismas matrices.

- Tamaño: 168 líneas, 7 funciones públicas, 2 locales.
- Usa: batalla/destruccion, batalla/matriz

- `Lanzamisiles.nuevo(modelo, suelo)` (l.28) — Conserva pivotes y tablas de trabajo; ninguna malla se crea por cuadro.
- `Lanzamisiles:inicializar(unidad)` (l.41) — Cada camión conserva sus matrices y sus ángulos, también al estar parado.
- `Lanzamisiles:recordarPosicion(unidad)` (l.58) — Guarda la posición anterior a la integración física.
- `Lanzamisiles:dirigir(unidad, rumboDeseado, dt)` (l.82) — Gira las ruedas delanteras hacia el rumbo deseado sin saltos instantáneos.
- `Lanzamisiles:medirMovimiento(unidad, dt)` (l.93) — Rodadura con signo y dirección del eje delantero. Un camión bloqueado no gira las ruedas por tener el motor encendido; tiene que desplazarse.
- `Lanzamisiles:actualizarMatrices(unidad)` (l.132) — Compone piezas relativas al chasis y el misil relativo a la rampa.
- `Lanzamisiles.visible(unidad, nombre)` (l.160) — Tras disparar queda la rampa vacía durante la bajada y la recarga.

## batalla/limite.lua

Límite del campo de batalla: un círculo dentro del área generada del que no sale ningún vehículo ni el punto al que mira la cámara.

- Tamaño: 57 líneas, 4 funciones públicas, 0 locales.

- `Limite.nuevo(cx, cy, radio)` (l.19) — Límite circular de centro (cx, cy) y `radio` px.
- `Limite:dentro(x, y, radio)` (l.28) — ¿Cabe entero un objeto de `radio` px con centro en (x, y)?
- `Limite:ajustar(x, y, radio)` (l.37) — (x, y) metido dentro del límite para un objeto de `radio` px: si está fuera, el punto más cercano del borde (se desliza a lo largo de él).
- `Limite:margen(x, y)` (l.50) — Distancia (px) de (x, y) al borde; negativa si está fuera.

## batalla/malla.lua

Constructor de mallas low-poly de caras planas para la escena de batalla.

- Tamaño: 379 líneas, 16 funciones públicas, 0 locales.
- Usa: ffi, mundo/modelos3d

- `Malla.nueva(capacidad)` (l.20)
- `Malla:crecer()` (l.30) — Dobla la memoria cuando no cabe un triángulo más.
- `Malla:vertice(x, y, z, nx, ny, nz, r, g, b, nacion)` (l.38)
- `Malla:triangulo(ax, ay, az, bx, by, bz, cx, cy, cz, color, nacion)` (l.52) — Triángulo de color plano con la normal de su cara (hacia donde gira a, b, c en sentido antihorario visto desde fuera; si queda hacia abajo, se da la…
- `Malla:trianguloColores(ax, ay, az, colorA, bx, by, bz, colorB, cx, cy, cz, colorC, normalA, normalB, normalC)` (l.69) — Triángulo con un color distinto en cada vértice. Conserva la normal plana de la cara, pero permite transiciones de terreno suaves.
- `Malla:caraFuera(ox, oy, oz, ax, ay, az, bx, by, bz, cx, cy, cz, color, nacion)` (l.99) — Triángulo cuya normal apunta hacia fuera del punto (ox, oy, oz): para los sólidos, sin tener que cuidar el orden de los vértices.
- `Malla:prisma(x, y, z, radio, radioArriba, alto, lados, color, giro)` (l.113) — Tronco de cono (o cilindro, o cono si `radioArriba` es 0) de `lados` caras, con la base en (x, y, z) y alto `alto`. `giro` gira las aristas.
- `Malla:prismaEntre(x0, y0, z0, x1, y1, z1, radio0, radio1, lados, color, giro)` (l.136) — Tronco o rama entre dos puntos. Los radios pueden ser distintos para que la pieza se afine hacia la punta.
- `Malla:caja(x, y, z, largo, ancho, alto, rumbo, color, nacion)` (l.200) — Caja de `largo` x `ancho` x `alto` con la base centrada en (x, y, z), girada `rumbo` sobre z. `nacion` (0 a 1) la pinta del color del país.
- `Malla:icosaedro(x, y, z, radio, radioZ, color, azar, rumbo)` (l.261) — Icosaedro de radio `radio` (x, y) y `radioZ` (alto) en (x, y, z).
- `Malla:icosaedroLibre(x, y, z, ex, ey, ez, gx, gy, gz, color, deformar, azar)` (l.279) — Icosaedro con escala distinta en cada eje, giro en los tres ejes (Euler XYZ, como Blender) y deformación ajustable.
- `Malla.variarPieza(color, azar, v)` (l.313) — Color de una pieza: brillo U(1 - v, 1 + v) y +-3 % por canal.
- `Malla:vertices()` (l.323) — Número de vértices escritos (para medir triángulos por prototipo).
- `Malla:octaedro(x, y, z, radio, radioZ, color, azar, rumbo)` (l.329) — Grupo pequeño de hojas con ocho caras. Es más barato que un icosaedro y permite formar copas con muchas masas sin disparar el número de triángulos.
- `Malla:crear()` (l.358) — La malla de LÖVE con lo escrito (estática: se sube una vez).
- `Malla.datosDe(malla)` (l.374) — Datos originales de una malla creada aquí. El comparador con 3DreamEngine los reutiliza una vez al cargar, sin leer vértices de vuelta desde la GPU.

## batalla/matriz.lua

Matrices 4x4 de la escena de batalla, en tablas planas por filas (se mandan al shader con 'row'). El mundo es el del mapa: x, y en el suelo y z hacia arriba, en px (1 px = 10 cm).

- Tamaño: 152 líneas, 9 funciones públicas, 0 locales.

- `Matriz.identidad(r)` (l.8) — Matriz identidad (en `r` si se da).
- `Matriz.multiplicar(a, b, r)` (l.18) — a * b en `r` (`r` no puede ser `a` ni `b`).
- `Matriz.colocar(x, y, z, rumbo, escala, r)` (l.33) — Traslación a (x, y, z), giro `rumbo` sobre z y escala `escala` (un número o tres), en `r`.
- `Matriz.cabecear(angulo, x, y, z, r)` (l.49) — Traslación (x, y, z) y giro `angulo` sobre el eje y (cabeceo), en `r`. Con un ángulo negativo, lo que mira a +x sube.
- `Matriz.entre(ax, ay, az, bx, by, bz, grosor, r)` (l.61) — Pieza alargada de `desde` a `hasta` (x, y, z), con un grosor `grosor`: la malla unidad (de -0,5 a 0,5 en x) queda estirada entre los dos puntos.
- `Matriz.orientar(ax, ay, az, bx, by, bz, escala, r)` (l.84) — Coloca un modelo que mira a +x en (bx, by, bz), orientado en la dirección que va desde (ax, ay, az), con escala uniforme.
- `Matriz.aplicar(m, x, y, z)` (l.107) — Punto (x, y, z) pasado por la matriz `m`.
- `Matriz.perspectiva(campo, aspecto, cerca, lejos, r)` (l.115) — Perspectiva de OpenGL: campo vertical `campo` (radianes), proporción `aspecto` y planos `cerca` y `lejos`.
- `Matriz.mirar(ex, ey, ez, tx, ty, tz, r)` (l.132) — Cámara en (ex, ey, ez) mirando a (tx, ty, tz) con z hacia arriba.

## batalla/ordenes.lua

Órdenes del jugador en la batalla 3D (Valeria): el camino por terreno transitable hasta un punto, los huecos de una formación y el punto del terreno bajo el ratón.

- Tamaño: 285 líneas, 7 funciones públicas, 2 locales.
- Usa: batalla/pasillos

- `Ordenes.nuevas(tropas)` (l.30)
- `Ordenes:rejilla()` (l.37) — Rejilla de rutas (se hace la primera vez que se pide).
- `Ordenes:celdaLibre(x, y)` (l.99) — La celda que se puede pisar más cercana a (x, y), o nil.
- `Ordenes:recta(ax, ay, bx, by)` (l.129) — ¿Se pueden pisar todas las celdas de la recta de (ax, ay) a (bx, by)?
- `Ordenes:ruta(x0, y0, x1, y1)` (l.146) — Camino de (x0, y0) a (x1, y1) por terreno transitable: lista de puntos { x, y } (el primero, el origen; el último, el destino o, si cae en el agua o…
- `Ordenes:formacion(unidades, x, y, rumbo)` (l.192) — Huecos de formación para `unidades` alrededor de (x, y), mirando en el rumbo `rumbo`: devuelve { [unidad] = { x, y } }.
- `Ordenes.puntoEnPantalla(camara, suelo, sx, sy, ancho, alto, campo)` (l.240) — Punto del terreno (o del agua) bajo el píxel (sx, sy) con la `camara` de la batalla, o nil si el rayo no toca el suelo.

## batalla/pasillos.lua

Pasillos de avance de la batalla (Valeria): dos o tres franjas anchas, sin árboles ni rocas grandes y con pendiente suave, que unen la zona donde forma un bando con la del otro (y con el objetivo, si hay ciudad o instalación).

- Tamaño: 668 líneas, 12 funciones públicas, 5 locales.
- Usa: batalla/rejilla

- `Pasillos.curva(xs, ys, paso)` (l.43) — Catmull-Rom por `xs, ys` remuestreada cada `paso` px (como `curva` del script de Blender). Devuelve dos listas nuevas.
- `Pasillos.nuevaRejilla(suelo)` (l.101) — Rejilla cuadrada de `celda` px sobre el límite del campo, con la altura del terreno, la pendiente (grados) y qué celdas no se pueden pisar o son río.
- `Pasillos.marcarCerca(g, p)` (l.155) — Marca en la rejilla del A* las celdas junto al pasillo `p` (hasta dos anchos y la transición del eje): el siguiente pasillo las evita si puede.
- `Pasillos.aEstrella(g, i0, j0, i1, j1, maxPend, rellenar)` (l.219) — A* de la celda (i0, j0) a (i1, j1): coste = distancia × (1 + (pendiente / 12°)²), celdas de más de `maxPend` grados prohibidas y un extra fijo por…
- `Pasillos.ruta(g, puntos, rellenar)` (l.314) — Camino de A* entre dos puntos (px), pasando por `via` si se da. Devuelve las listas de x e y de los centros de celda, o nil.
- `Pasillos.suavizarEje(g, xs, ys, rellenar)` (l.373) — Eje suavizado (media móvil y Catmull-Rom) que no pisa celdas prohibidas: si al suavizar una curva se come una orilla, se suaviza menos.
- `Pasillos.puntosDePaso(suelo, combate)` (l.402) — Puntos de paso de cada pasillo: de la zona de formación del atacante a la del defensor, uno directo y dos por los lados.
- `Pasillos.generar(suelo, combate)` (l.434) — Traza los pasillos, hace sus perfiles y aplana el terreno debajo.
- `Pasillos.perfil(suelo, p)` (l.520) — Perfil seco del terreno real, suavizado y limitado en ambos sentidos. Agua aún no implementa puentes físicos: ninguna ruta depende de un tablero.
- `Pasillos.aplanar(suelo, p, hecho)` (l.557) — Estampa el pasillo `p` en la rejilla del terreno: por vértice, la distancia al eje y la altura del perfil allí; luego mezcla la del mapa con la del…
- `Pasillos.validar(suelo, p)` (l.611) — Comprueba la superficie triangulada, sin depender de normales almacenadas ni del perfil ideal. Muestrea cada 20 px y cada 100 px a lo ancho del paso.
- `Pasillos.distancia(suelo, x, y)` (l.659) — Distancia (px) de (x, y) al eje del pasillo más cercano, por la rejilla.

## batalla/rejilla.lua

Rejilla del terreno de batalla en memoria (FFI): posición desplazada, altura final y los campos que se calculan una vez por vértice (ruidos, humedad, bosque, agua...).

- Tamaño: 292 líneas, 15 funciones públicas, 1 locales.
- Usa: ffi

- `Rejilla.array(n)` (l.19) — Array de `n` números (double) a cero.
- `Rejilla.nueva(xs, ys)` (l.24) — Rejilla sobre las líneas `xs` y `ys` (tablas ordenadas de px).
- `Rejilla.tablaIndices(lineas)` (l.40) — Tabla que da, para cada tramo de `pasoIndice` px, la última línea que queda a su izquierda. Así localizar un punto no necesita búsqueda binaria.
- `Rejilla:cuadro(x, y)` (l.71) — Cuadro sin desplazar (i, j) que contiene (x, y).
- `Rejilla:cercano(x, y)` (l.76) — Vértice más cercano de la rejilla sin desplazar (rápido, para filtros).
- `Rejilla:cercanoEje(eje, x)` (l.90) — Índice (desde 0) de la línea más cercana a `x` en el eje X (`eje` = 'x') o Y.
- `Rejilla:baricentricas(x, y, a, b, c)` (l.102) — Coordenadas baricéntricas de (x, y) en el triángulo (a, b, c). Devuelve nil si cae fuera (con un margen mínimo para los bordes compartidos).
- `Rejilla:triangulosCuadro(i, j)` (l.123) — Los tres vértices de los dos triángulos del cuadro (i, j).
- `Rejilla:probar(x, y, a, b, c)` (l.139) — Prueba el triángulo (a, b, c): si contiene (x, y), deja sus vértices y pesos en `self.ta`, `tb`, `tc`, `wa`, `wb`, `wc` y devuelve true.
- `Rejilla:probarCuadro(x, y, i, j)` (l.162) — Prueba los dos triángulos del cuadro (i, j) (ver `triangulosCuadro`).
- `Rejilla:ubicarVecinos(x, y, i0, j0)` (l.181) — Los 8 cuadros vecinos de (i0, j0) y, si no, el vértice más cercano.
- `Rejilla:ubicar(x, y)` (l.204) — Busca el triángulo de la malla que contiene (x, y) y deja sus vértices y pesos en `self.ta` ... `self.wc`.
- `Rejilla:localizar(x, y)` (l.261) — Triángulo de la malla que contiene (x, y) y sus pesos: a, b, c, wa, wb, wc.
- `Rejilla:interpolar(campo, x, y)` (l.267) — Valor de `campo` (array por vértice) interpolado en (x, y).
- `Rejilla:alturaNormal(x, y)` (l.273) — Altura y normal (de la cara) en (x, y).

## batalla/soldados.lua

Soldados visibles de la batalla 3D. No cambian la simulación: son una representación animada de la infantería que ya trae la tabla `combate`.

- Tamaño: 162 líneas, 5 funciones públicas, 2 locales.
- Usa: batalla/matriz

- `Soldados.inicializar(unidad, azar)` (l.68)
- `Soldados.actualizarMatrices(unidad, modelo)` (l.77)
- `Soldados.boca(unidad)` (l.127)
- `Soldados.actualizar(unidad, dt, moviendo, modelo)` (l.131)
- `Soldados.dibujar(modelo, unidad, shader)` (l.151)

## batalla/sombreado.lua

Shader de la escena de batalla: perspectiva real, luz del sol de la tarde (la misma de los tanques 3D del mapa) y niebla lineal con la distancia hacia el color del horizonte, suave (a 2-3 km aún se lee la escena).

- Tamaño: 97 líneas, 1 funciones públicas, 0 locales.

- `Sombreado.shader()` (l.83)

## batalla/suelo.lua

Suelo de la escena de batalla: el sitio real del mapa en 3D low-poly.

- Tamaño: 1117 líneas, 35 funciones públicas, 4 locales.
- Usa: batalla/agua, batalla/colocacion, batalla/color_terreno, batalla/limite, batalla/malla, batalla/pasillos, batalla/rejilla, batalla/vegetacion, mundo/ciudades, mundo/ruido, mundo/terreno

- `Suelo.nuevo(mundo, cx, cy, sitio, combate, carga)` (l.68) — Suelo alrededor de (cx, cy). `sitio` es lo que se ataca (para el edificio) o nil en una batalla de campo abierto: { tipo = 'ciudad' | 'base' |…
- `Suelo:imprimirTiempos()` (l.125) — Línea `SUELO` con el tiempo de cada paso y las copias por especie.
- `Suelo:informarCarga(etapa, progreso, forzar)` (l.158)
- `Suelo:alturaReal(x, y)` (l.165) — Altura original del mundo en (x, y), sin filtros de batalla.
- `Suelo:alturaSuave(x, y)` (l.171) — Altura suavizada: la batalla conserva la forma grande del mapa, pero quita picos pequeños para que los tanques y las formaciones caminen tranquilos.
- `Suelo:detalleAltura(x, y)` (l.184) — Ondulación grande de la superficie (170 m): evita explanadas del todo lisas. Sin el ruido fino ni las crestas de antes, que hacían picos.
- `Suelo:suavizarGauss(alturas)` (l.192) — Filtro gaussiano separable de `alturas` (array por vértice) sobre la rejilla, con la distancia real entre líneas: en el centro (paso fino) promedia…
- `Suelo:prepararExplanadas(combate)` (l.235) — Prepara las dos explanadas de formación. No inventan un mapa nuevo: solo funden el terreno suavizado hacia una cota estable alrededor de cada bando.
- `Suelo:aplicarExplanadas(x, y, h)` (l.262) — Aplica las explanadas sobre una altura ya suavizada. `generarTerreno` lo usa con la rejilla ya muestreada para no llamar al terreno cinco veces por…
- `Suelo:altura(x, y)` (l.281) — Altura táctica de la batalla en (x, y): la de la rejilla final del terreno (mapa suavizado, explanadas, detalle y cauces tallados), interpolada en…
- `Suelo:desnivel(x, y, radio)` (l.296) — Desnivel bajo un casco de vehículo. Se usa para no formar en laderas rotas.
- `Suelo:pesoExplanada(x, y)` (l.308) — Peso (0 a 1) de las explanadas de formación en (x, y).
- `Suelo:enCamino(x, y, margen)` (l.326) — ¿Cae (x, y) en un pasillo de avance (o a menos de `margen` px de su borde)? Ahí no crecen árboles, arbustos ni rocas (batalla/pasillos.lua).
- `Suelo:pendiente(x, y)` (l.331) — Pendiente del terreno en (x, y), en grados (la de la cara que se dibuja).
- `Suelo:transitable(x, y)` (l.341) — ¿Puede pisar un vehículo o un soldado (x, y)? No en el agua (mar, lagos y ríos, salvo sobre un puente) ni en pendientes de más de 25°.
- `Suelo.pasoA(d)` (l.356) — Paso de la rejilla a `d` px del centro (en un eje): fino donde se pelea y más grueso hacia el borde, sin saltos.
- `Suelo.lineas(centro)` (l.369) — Coordenadas de las líneas de la rejilla en un eje, de `centro - lado / 2` a `centro + lado / 2`, más juntas en el medio.
- `Suelo:ciudadesDelArea()` (l.389) — Ciudades que pueden aplanar alguna parte del área (casi siempre ninguna o una: las capitales están a varios kilómetros).
- `Suelo:alturaMapa(x, y, ciudades)` (l.415) — `Terreno:altura` con la lista de `ciudadesDelArea`: las mismas cuentas, sin buscar las ciudades cercanas en cada punto.
- `Suelo:generarTerreno()` (l.435) — Rejilla del terreno: vértices desplazados, altura táctica y los campos por vértice (ruidos del estilo, humedad del mapa, pendiente y bosque).
- `Suelo:calcularNormales()` (l.535) — Pendiente (1 - nz) y normal suavizada de cada vértice (diferencias centradas). Se rehace después de tallar el agua y aplanar los pasillos.
- `Suelo:despejarPasillos()` (l.560) — En los pasillos no hay bosque: tampoco se pinta suelo de bosque (quedaría una franja oscura sin árboles).
- `Suelo:medirRelieve()` (l.576) — hRef (percentil 20 de las alturas sobre el mar: el fondo del valle) y el umbral de roca.
- `Suelo:colorearTerreno()` (l.603) — Malla del terreno con color por vértice (interpolado en cada triángulo: las zonas se funden en degradados, sin parches por cara) y normal mezclada…
- `Suelo:medirLlanura()` (l.734) — Cota de la gran llanura del faldón: algo por debajo de la altura típica del borde del área (percentil 30 de su tierra firme), nunca bajo el mar.
- `Suelo:alturaFaldon(x, y)` (l.754) — Altura del faldón en (x, y), fuera del área: el mapa real (sus lomas, lagos y orillas siguen con su forma), fundido con la llanura a lo largo de…
- `Suelo:generarFaldon(malla, cr, cg, cb)` (l.768) — Anillos del faldón en `malla` (la del terreno: el mismo material y el mismo dibujo).
- `Suelo:generarAgua()` (l.898) — El mar, un plano a su nivel (solo si alguna parte del área está bajo él).
- `Suelo:generarPlantas()` (l.924) — Prototipos y copias de la vegetación y las rocas (batalla/vegetacion.lua y batalla/colocacion.lua).
- `Suelo:ocupado(x, y, margen)` (l.938) — ¿Cae (x, y) sobre el edificio del sitio (donde no crecen plantas ni se ponen vehículos)? `margen` en px.
- `Suelo:radioEdificio()` (l.947)
- `Suelo:apuntarPlanta(p)` (l.960) — Apunta una planta { x, y, arbol, radio, alto } en la rejilla (para no poner vehículos encima).
- `Suelo:derribarArbol(p, dx, dy, quemado)` (l.974) — Un árbol alcanzado por un proyectil cae hacia (dx, dy) (la dirección del disparo) y, con `quemado`, se oscurece.
- `Suelo:plantaCerca(x, y, radio, soloArboles)` (l.1026) — ¿Hay alguna planta (salvo hierba y flores) a menos de `radio` px de (x, y)? Con `soloArboles`, solo cuentan los árboles y las rocas grandes.
- `Suelo:generarEdificio()` (l.1071)

## batalla/tropas.lua

Tropas de la escena de batalla: los tanques y lanzacohetes reales del combate, formados cada bando en su lado del área a distancia real (1 px = 10 cm; unos 1,7 km entre los frentes), y la pelea que se ve:

- Tamaño: 2397 líneas, 75 funciones públicas, 8 locales.
- Usa: batalla/estelas, batalla/impactos, batalla/lanzamisiles, batalla/malla, batalla/matriz, batalla/soldados, batalla/suelo, mundo/modelos3d, mundo/ruido, mundo/simulacion

- `Tropas.nuevo(suelo, combate)` (l.147) — Tropas para el `combate` (ver Escena) sobre el `suelo`.
- `Tropas.prepararBando(bando)` (l.211) — Lo que pelea un bando: sus fuentes, la cola de vehículos (tanques y lanzacohetes intercalados en su proporción, en orden de fuente: los primeros…
- `Tropas:usarFisica(fisica)` (l.271)
- `Tropas:usarRayos(rayos)` (l.275)
- `Tropas:usarSonido(sonido)` (l.279)
- `Tropas:usarCamara(camara)` (l.284) — Solo la vista recibe la sacudida; los impactos no empujan los cuerpos.
- `Tropas:usarEfectos(efectos)` (l.290) — Efectos (Camila, batalla/efectos.lua): estelas, fogonazos, impactos. Solo mira lo que pasa; no cambia la simulación ni su azar.
- `Tropas:sonar(nombre, x, y, z, volumen, tono)` (l.294)
- `Tropas:lineaVisible(origen, destino)` (l.300)
- `Tropas:radioUnidad(tipo)` (l.307)
- `Tropas:transitable(x, y, tipo)` (l.313) — ¿El terreno acepta una unidad de `tipo` en (x, y)? Usa la decisión de Valeria (`suelo:transitable`) y la comprueba bajo el radio de la unidad.
- `Tropas:libre(x, y, arboles, tipo)` (l.335) — ¿Puede estar un vehículo en (x, y)? En tierra firme bajo todo el casco, dentro del área y fuera del edificio.
- `Tropas:segmentoLibre(x0, y0, x1, y1, tipo)` (l.378) — Comprueba todo el trayecto recto, incluida la huella de la unidad. Un destino seco no basta: el atajo hasta él puede cortar agua o un árbol.
- `Tropas:vehiculoCerca(x, y, radio, salvo, radioSoldado, enMarcha)` (l.403) — ¿Hay otra unidad (viva o no) a menos de `radio` px de (x, y)? Con `radioSoldado`, a los soldados se les mira a esa distancia (la infantería avanza…
- `Tropas:buscarSitio(x, y, radio, tipo, bando)` (l.416) — El sitio libre más cercano a (x, y), conectado a un pasillo de avance. Si la formación cae en una isla, se coloca junto al extremo de su bando.
- `Tropas:formar(indice, bando)` (l.501) — Forma un bando (1 atacante, 2 defensor) en su lado del área, mirando al otro: los tanques delante, en filas, y los lanzacohetes en la retaguardia.
- `Tropas:poner(indice, v, k, cuantos, fondo, separacion)` (l.568) — Pone en el campo la unidad `v` ({ tipo, fuente, soldados }) del bando `indice`, la `k`-ésima de `cuantos` en filas de `Tropas.porFila`, a `fondo` px…
- `Tropas:retirar(u)` (l.631) — Quita del campo un averiado (se lo llevan a retaguardia): deja de estar en `unidades`, en la física y en los efectos, pero sigue en su bando para el…
- `Tropas:relevar()` (l.656) — Oleadas: con reserva esperando, el averiado más antiguo de cada bando que lleve `retiroAveriado` s en el campo se retira y entra el siguiente de la…
- `Tropas:entrarReserva(indice)` (l.681) — Entra el siguiente vehículo de la reserva del bando `indice`, detrás de sus lanzacohetes. Si no encuentra sitio, sigue esperando.
- `Tropas.gastoDisparo(u)` (l.706) — Lo que gasta un disparo de `u` (F6): una ráfaga de figura, 5 balas por cada soldado de su escuadra; un cañonazo, 1 obús; un lanzamiento, 1 misil.
- `Tropas.municionQueda(u)` (l.713) — Munición que le queda a la fuente de `u` para su tipo (infinita en un combate de prueba).
- `Tropas.sinMunicion(u)` (l.723) — ¿Se ha quedado `u` sin munición?
- `Tropas:gastar(u)` (l.729) — Gasta la munición de un disparo de `u`. Sin munición devuelve false y no dispara; con menos de un disparo entero, gasta lo que queda.
- `Tropas:municionBando(indice)` (l.745) — Munición de un bando: { balas, obuses, misiles } con lo que lleva, lo que ha gastado y si es sin límite (combate de prueba).
- `Tropas:blancoDeTanque(u)` (l.771) — Blanco para el tanque `u`: primero un lanzacohetes enemigo que se haya acercado (blanco fácil y peligroso), si no el enemigo más cercano a tiro (con…
- `Tropas:tanqueEnemigoCerca(u)` (l.800) — Tanque enemigo más cercano a `u` (distancia en px, o infinito).
- `Tropas:blancoDeSoldado(u)` (l.813) — Blanco de infantería: primero otro soldado a distancia de fusil; si no, un vehículo cercano.
- `Tropas:blancoDeMisil(u)` (l.841) — Blanco para los misiles de `u`: un enemigo al azar entre el mínimo y el alcance del misil (mejor tanques, que es lo que amenaza), o nil.
- `Tropas:particula(p)` (l.864) — Añade una partícula (si cabe): `p` con x, y, z, vx, vy, vz, vida, tam0, tam1, color, brillo y gravedad.
- `Tropas:humo(x, y, z, tam, vida, gris, subida)` (l.876)
- `Tropas:fogonazo(x, y, z, tam)` (l.894)
- `Tropas:impacto(x, y, z, fuerte, fuego, escala)` (l.909) — Chispas y polvo de un impacto; con `fuego`, una bola de fuego (explosión). `escala` agranda todo (los misiles hacen más que una bala).
- `Tropas:destruir(u)` (l.982) — Un vehículo cae destrozado: ennegrecido, humeando y, a veces, explota (el lanzacohetes pierde ruedas).
- `Tropas:averiar(u)` (l.1013) — Un vehículo sin vida queda averiado: fuera de combate (`muerto`, para todo lo que busca blancos o lo mueve), inmovilizado, humeando y sin disparar.
- `Tropas:golpear(u, dano)` (l.1038) — Un golpe (bala o misil) a `u`: le quita `dano` de vida; sin vida, queda fuera de combate. Sin tope ni ritmo: las bajas son las del combate.
- `Tropas.punteria(d)` (l.1052) — Probabilidad de que un tanque acierte a `d` px: casi nunca a 2 km, a menudo a pocos cientos de metros.
- `Tropas:dispararSoldado(u)` (l.1056)
- `Tropas:dispararTanque(u)` (l.1110)
- `Tropas.posicionBala(b, t)` (l.1170) — Posición de una bala en la fracción `t` de su vuelo.
- `Tropas:bocaLanzacohetes(u, k)` (l.1175) — Bocas del contenedor de un lanzacohetes en el mundo, y su dirección.
- `Tropas:matrizContenedor(u)` (l.1183) — La misma rampa articulada que dibujan los dos renderizadores.
- `Tropas:lanzarMisil(u, k)` (l.1189) — Desprende el misil cargado; no vuelve a crearse hasta terminar la recarga.
- `Tropas.posicionMisil(m, t)` (l.1256) — Posición de un misil en la fracción `t` (0 a 1) de su vuelo.
- `Tropas.matrizMisil(m, t, salida)` (l.1266) — Tangente hacia delante, válida también en el instante exacto del disparo.
- `Tropas:chocarBala(b, dt)` (l.1301) — ¿Choca la bala `b` con una loma o un árbol en el tramo de este cuadro? Si es así, hace su impacto allí (sin dañar al blanco); un proyectil de cañón…
- `Tropas:chocarMisil(m, t, dt)` (l.1327) — ¿Choca el misil `m` (en la fracción `t` de su vuelo) con una loma o un árbol en este cuadro? Si es así, su destino pasa a ser el choque (explota…
- `Tropas:quiereAvanzar(u)` (l.1369) — ¿Sigue avanzando el tanque `u`? El atacante, hasta tener un tanque enemigo cerca; el defensor sale un poco al encuentro y espera.
- `Tropas:darOrden(u, orden)` (l.1406) — Da a `u` la orden `orden` (nil: vuelve a su IA).
- `Tropas.alcanceDe(u)` (l.1419) — Alcance (y distancia mínima) de las armas de `u`.
- `Tropas:seguirOrden(u)` (l.1430) — Cumple la orden de `u` este cuadro: fija `orden.avanza` y, si hay que moverse, `u.rumboOrden`. Con 'atacar' devuelve su blanco si está a tiro.
- `Tropas:pasilloMasCercano(u)` (l.1521)
- `Tropas:indicePasilloAdelantado(pasillo, indice, direccion, distancia)` (l.1564)
- `Tropas:rumboDePasillo(u)` (l.1580)
- `Tropas:rumboLibre(u)` (l.1616) — Rumbo libre para avanzar: el del bando o el desvío más pequeño que no lleve al agua, a un edificio, a un árbol o encima de otro vehículo.
- `Tropas:mantenerTransitable(u, anteriorX, anteriorY)` (l.1637) — Aplica el límite del campo sin aceptar que el ajuste empuje la unidad a agua o pendiente no transitable. Si pasa, vuelve al punto previo del paso.
- `Tropas:mover(u, dt)` (l.1653) — La unidad `u` avanza `dt` segundos. Devuelve si se ha movido. Un paso de una unidad con munición cuenta como que su bando aún busca al rival.
- `Tropas:moverPaso(u, dt)` (l.1661)
- `Tropas:actualizarSoldado(u, dt)` (l.1741)
- `Tropas:actualizarTanque(u, dt)` (l.1791)
- `Tropas:actualizarLanzacohetes(u, dt)` (l.1848) — Despliega el camión, frena, levanta su misil, dispara y baja la rampa vacía.
- `Tropas:medirAvance()` (l.1932) — Cuánto ha avanzado de media cada bando (sus tanques vivos).
- `Tropas:actualizar(dt)` (l.1959)
- `Tropas:dibujarUnidades(shader)` (l.2081)
- `Tropas:dibujarEfectos(shader, ex, ey, ez)` (l.2123) — Efectos: trazadores, misiles, estelas y partículas, vistos desde (ex, ey, ez).
- `Tropas:disparoCerca(x, y, radio)` (l.2175) — ¿Algún tanque a menos de `radio` px de (x, y) acaba de disparar?
- `Tropas:trazadoresLejanos(largo)` (l.2186) — Balas en vuelo, a mitad de camino, de disparos de más de `largo` px.
- `Tropas:misilesAltos()` (l.2198) — Misiles en lo alto de su vuelo.
- `Tropas:adelantado()` (l.2210) — El primer lanzacohetes adelantado (vivo o no).
- `Tropas:enPie(indice, armado)` (l.2221) — ¿Puede seguir peleando el bando `indice`? Con algo en pie en el campo o en la reserva; con `armado`, además con munición.
- `Tropas:exentoAlcance(indice)` (l.2239) — ¿Queda el bando `indice` fuera de la regla de `sinFuego` (decisión del dueño)? El del jugador (solo se retira sin munición o sin nada en pie) y el…
- `Tropas:fin()` (l.2262) — Cómo termina la pelea, o nil si sigue (decisión del dueño): { pierde (1 o 2), retira ('atacante', 'defensor' o nil), motivo }.
- `Tropas:terminada()` (l.2292) — ¿Terminó la pelea? (ver `fin`)
- `Tropas:recuento()` (l.2300) — Recuento por bando para el rótulo: { tanque, lanzacohetes = { campo (en pie en el campo), averiados, reserva, total }, soldado = { enPie (soldados,…
- `Tropas:resultado(semilla, batalla)` (l.2352) — Resultado de la escena para `resolverBatalla` (F11), por lado: { atacante = bando, defensor = bando } con bando = { soldados = { muertos, heridos },…

## batalla/vegetacion.lua

Prototipos de la vegetación y las rocas de la batalla, construidos en código (ESTILO-TERRENO.md §3): roble, álamo, abedul, flor y cañas, más el abeto nevado, el nenúfar y el cactus del mapa. No se importa ningún modelo.

- Tamaño: 373 líneas, 9 funciones públicas, 4 locales.
- Usa: batalla/malla, mundo/ruido, mundo/terreno

- `PROTO.Abeto(m, U, lod, nevado)` (l.63)
- `PROTO.AbetoNevado(m, U, lod)` (l.108)
- `PROTO.Roble(m, U, lod)` (l.112)
- `PROTO.Alamo(m, U, lod)` (l.151)
- `PROTO.Abedul(m, U, lod)` (l.179)
- `PROTO.Canas(m, U)` (l.265)
- `PROTO.Nenufar(m, U)` (l.301)
- `PROTO.Cactus(m, U)` (l.307)
- `Vegetacion.construir(semillaMundo)` (l.348) — Construye todas las variantes y niveles de detalle de la semilla del mundo.


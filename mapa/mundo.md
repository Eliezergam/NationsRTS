# Mapa de `mundo/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## mundo/choques.lua

Choques entre ejércitos en campo abierto (solo vista y entrada a la batalla) y el enganche de las batallas de la simulación con la escena 3D (`deBatalla` arma el combate con lo sano, su munición y su escuadra;…

- Tamaño: 211 líneas, 6 funciones públicas, 3 locales.
- Usa: mundo/simulacion

- `Choques.lista(mundo)` (l.31) — Choques de ahora (de la simulación), solo los que tienen sus dos grupos vivos. Sin `sim:choques()` (una partida de otra versión), ninguno.
- `Choques.indice(lista)` (l.47) — Índice grupo -> choque en que está.
- `Choques.clave(c)` (l.56) — Clave estable de un choque (para los pregones).
- `Choques.combate(mundo, c)` (l.75) — Tabla `combate` (GUIA-3D.md, §4.1) de un choque en campo abierto: centro en el punto del choque, ángulo de a hacia b, a ataca y b defiende, sin sitio.
- `Choques.deBatalla(mundo, estado, describir, nid)` (l.167) — Tabla `combate` (GUIA-3D.md, §4.1) de una batalla de la simulación, a partir de su `estado` (`sim:estadoBatalla`): los dos bandos con lo sano de ese…
- `Choques.resultadoDeEscena(tropas, semilla, bid)` (l.206) — Resultado de una escena para `resolverBatalla` (formato de la cabecera de mundo/simulacion/batallas.lua): la clasificación de cada unidad de la…

## mundo/ciudades.lua

Capitales de las naciones: una por país, generada en un sitio al azar.

- Tamaño: 677 líneas, 14 funciones públicas, 9 locales.
- Usa: mundo/instalaciones, mundo/iso, mundo/ruido

- `Ciudades.nuevo(terreno)` (l.58)
- `Ciudades:deRegion(rx, ry)` (l.86) — Capital de la región (rx, ry), o nil. Cada país (zona de `porNacion` x `porNacion` regiones) tiene una sola capital: la mayor de las candidatas que…
- `Ciudades:candidata(rx, ry)` (l.119) — Candidata a capital que la semilla pone en la región (rx, ry).
- `Ciudades.borde(ciudad, _angulo)` (l.170) — Distancia del centro al borde de lo que ocupa la ciudad en el suelo (px).
- `Ciudades.cerca(ciudad, x, y, margen)` (l.175) — ¿(x, y) está a menos de `margen` px por fuera de lo que ocupa la ciudad?
- `Ciudades:cercanas(x, y)` (l.181) — Ciudades cuyo radio de influencia puede tocar el punto (x, y).
- `Ciudades:dentro(x, y)` (l.212) — ¿El punto cae en el casco de alguna ciudad (calles y edificios)?
- `Ciudades.dibujarFranjaTorre(x, y, z, color)` (l.464) — Franja con el color del país en lo alto de la corona de la torre.
- `Ciudades:construir(ciudad)` (l.486) — Prepara la ciudad para dibujarla: la base cuadrada de la torre (solo se ve en la capital). Nada de casas, calles ni habitantes.
- `Ciudades:actualizar(ciudad, dt)` (l.507) — Solo el reloj de la bandera.
- `Ciudades:piezas(ciudad, lista)` (l.514) — Lo que hay que dibujar de una ciudad, con su profundidad: la capital, su torre; las demás, su campamento.
- `Ciudades.dibujarCamion(x, y, z, color, angulo)` (l.604) — Camión de tropa (los soldados van dentro): 8 x 2,5 m, cabina delante y la caja cubierta con lona; una franja con el color de su nación.
- `Ciudades.dibujarAvion(x, y, z, color)` (l.617) — Avión aparcado: fuselaje, alas y cola, con la escarapela de su nación.
- `Ciudades.dibujarBandera(x, y, z, color, tiempo)` (l.646) — Bandera en su mástil, ondeando.

## mundo/estandartes.lua

Estandartes de los ejércitos en el mapa (diseno/ejercitos-en-el-mapa.md, §3.1).

- Tamaño: 388 líneas, 16 funciones públicas, 5 locales.
- Usa: assets.estandarte.indice, interfaz/tema, mundo/ruido

- `Estandartes.escala()` (l.39) — Hoja que toca a esta escala de interfaz: la 1x a tamaño natural hasta 1,4 y, por encima, la _x2 (que mide el doble) escalada.
- `Estandartes.medidas()` (l.48) — Medidas de la hoja 1x del estandarte (ancho, alto, ancla, etiqueta).
- `Estandartes.semillaEscudo(semillaMundo, nid)` (l.54) — Semilla del escudo de una nación: una por nación, estable (sale de la semilla del mundo y de su zona 'z:zx,zy'; no se guarda).
- `Estandartes.escudoDe(semillaMundo, nid)` (l.60) — Combinación del escudo de una nación (forma, partición, carga y esmaltes).
- `Estandartes.dibujarEscudo(combinacion, cx, cy, hoja, s, alfa)` (l.95) — Dibuja el escudo `combinacion` con su centro en (cx, cy) de pantalla.
- `Estandartes.pose(gr)` (l.119) — Pose de un grupo: 'retirada', 'combate' (pelea en una batalla, `gr.batalla`, o ataca y ya está en su objetivo) o 'marcha'.
- `Estandartes.dibujarEstandarte(sx, sy, ficha, pose, izquierda, semillaMundo)` (l.136) — Estandarte de un ejército con el pie del asta en (sx, sy) de pantalla.
- `Estandartes.dibujarBanderin(sx, sy, color, izquierda)` (l.174) — Banderín pequeño de un convoy (sin líder ni poder), con el pie en (sx, sy).
- `Estandartes.esRecolector(ficha)` (l.201) — ¿Se lee el grupo como recolector? Los que llevan carga de una mina (misión `recolectar`, o `apoyo` y `regreso` redirigidos desde ella) y no tienen…
- `Estandartes.cifraCarga(valor)` (l.214) — Cifra corta de una carga: con un decimal por debajo de 10 («2,4»), entera si no.
- `Estandartes.textoRecolector(ficha)` (l.224) — Texto de la etiqueta de un recolector: «12 / 30», o «×3 · 36 / 90» si resume varios grupos (`ficha.cuantos`).
- `Estandartes.cajaRecolector(sx, sy, ficha, izquierda, pose)` (l.266) — Caja (px de pantalla) que ocuparía la ficha de un recolector con el pie en (sx, sy), sin dibujarla.
- `Estandartes.dibujarRecolector(sx, sy, ficha, izquierda, pose)` (l.273) — Banderín de un recolector con el pie en (sx, sy): el del convoy, una bolsa al pie que se llena con su carga y la etiqueta «carga / capacidad».
- `Estandartes.textoEtiqueta(ficha)` (l.317) — Texto de la etiqueta: «Gral. Mira Oriel · 1 240». Un ejército ajeno sin informe (`poderOculto`, interfaz/inteligencia.lua) lleva «?»; con informe de…
- `Estandartes.cajaEjercito(sx, sy, ficha, izquierda)` (l.332) — Caja (px de pantalla) que ocuparían el estandarte y la etiqueta de un ejército con el pie en (sx, sy), sin dibujarlos (como `dibujarEstandarte` y…
- `Estandartes.dibujarEtiqueta(sx, sy, ficha, izquierda, pegada)` (l.358) — Etiqueta bajo el estandarte, centrada en el asta. Devuelve su caja.

## mundo/instalaciones.lua

Dibujo de instalaciones de extracción, bases militares y campamentos.

- Tamaño: 485 líneas, 3 funciones públicas, 18 locales.
- Usa: mundo/iso, mundo/simulacion

- `Instalaciones.dibujarCampamento(x, y, z, p, color, tiempo)` (l.389) — Campamento: tiendas, sacos terreros y una bandera alta con el color del país. `p` de 0 a 1: cuánto se ha levantado.
- `Instalaciones.dibujar(inst, deposito, color, z, tiempo, dibujos)` (l.404)
- `Instalaciones.dibujarHuerto(h, z, dia)` (l.462) — Huerto de emergencia: unas pocas parcelas pequeñas con surcos, más humilde que un complejo agrícola. Mientras se planta, solo tierra removida.

## mundo/iso.lua

Vista isométrica 2:1, la misma del editor (runtime/projection.lua): vista.x = x - y vista.y = (x + y) / 2 - altura * 1.2247 El mundo es un plano (x, y) con alturas; todo se dibuja en coordenadas de vista.

- Tamaño: 24 líneas, 3 funciones públicas, 0 locales.

- `Iso.vista(x, y, z)` (l.9)
- `Iso.mundo(vx, vy)` (l.14) — Punto de la vista a punto del suelo (a altura 0).
- `Iso.profundidad(x, y)` (l.19) — Profundidad de dibujo: lo de delante (más abajo en pantalla) va después.

## mundo/modelos.lua

Modelos renderizados en Blender con el estilo militar realista (tools/blender/render_sprites_militares.py): el lanzacohetes y el misil.

- Tamaño: 230 líneas, 8 funciones públicas, 4 locales.
- Usa: mundo/iso

- `Modelos.bocaTubo(angulo, n)` (l.130) — Boca del tubo `n` (1 a 4) de un lanzacohetes con el contenedor arriba, respecto al punto del suelo del camión, mirando a `angulo`: dx, dy, dz en px…
- `Modelos.direccion(angulo)` (l.143) — Dirección de la hoja (0 a 7) más cercana a un ángulo del mundo.
- `Modelos.dibujarLanzacohetes(x, y, z, angulo, elevacion, color)` (l.152) — Lanzacohetes en el punto (x, y, z) del suelo. `angulo`: hacia dónde miran la cabina y las bocas de los tubos (el contenedor pivota atrás y sube el…
- `Modelos.dibujarLanzacohetesMarcha(x, y, z, angulo, cuadro, color)` (l.165) — Lanzacohetes en marcha (plegado): `cuadro` avanza las ruedas y el rebote. `color`: el de su nación.
- `Modelos.dibujarTanque(x, y, z, anguloCasco, anguloTorreta, retroceso, color)` (l.182) — Tanque en el punto (x, y, z) del suelo: el casco mirando a `anguloCasco` y la torreta a `anguloTorreta` (ángulos del mundo).
- `Modelos.bocaCanon(anguloTorreta)` (l.206) — Boca del cañón de un tanque con la torreta mirando a `anguloTorreta`, respecto al punto del suelo del tanque: dx, dy, dz en px del mundo.
- `Modelos.anguloTorretaVisible(angulo)` (l.214) — Ángulo del mundo de la columna de la torreta más cercana a `angulo`: hacia donde apunta de verdad el cañón que se ve.
- `Modelos.dibujarMisil(vx, vy, angulo, escala, apagado)` (l.221) — Misil en el punto de la vista (vx, vy), girado `angulo` en pantalla y a `escala` de su imagen. `apagado`: sin llama (recién expulsado del tubo).

## mundo/modelos3d.lua

Vehículos en 3D real (prueba): mallas de assets/modelos3d/*.lua dibujadas con la misma proyección isométrica que el resto del mundo (`Iso.vista`).

- Tamaño: 301 líneas, 7 funciones públicas, 8 locales.
- Usa: mundo/iso

- `Modelos3d.postura(terreno, x, y, z, rumbo, r)` (l.185) — Postura de un tanque en el punto (x, y) del suelo con el casco mirando a `rumbo`: apoyado en el terreno e inclinado con la pendiente.
- `Modelos3d.tanque()` (l.226) — Modelo del tanque ya cargado: { piezas = { casco, torreta, canon }, boca }.
- `Modelos3d.matricesTanque(casco, torreta, retroceso)` (l.233) — Matrices (modelo -> mundo) de la torreta y del cañón de un tanque con casco `casco`.
- `Modelos3d.boca(casco, torreta)` (l.240) — Boca del cañón en el mundo y dirección horizontal del disparo (x, y, z, fx, fy).
- `Modelos3d.empezarCuadro(referencia)` (l.252) — Profundidad de referencia del cuadro (x + y del centro de la vista): el buffer guarda la profundidad relativa a ella.
- `Modelos3d.dibujarTanque(casco, torreta, retroceso, color)` (l.265) — Tanque con el casco en `casco` (ver `postura`), la torreta girada `torreta` respecto al casco, el cañón retrocedido `retroceso` (0 a 1) y la franja…
- `Modelos3d.dibujarSombra(casco)` (l.289) — Sombra del tanque con el casco en `casco`: la planta del casco sobre el suelo inclinado, corrida al lado contrario del sol.

## mundo/mundo.lua

El mundo: trozos de terreno que se generan al acercarse y se olvidan al alejarse.

- Tamaño: 1852 líneas, 55 funciones públicas, 12 locales.
- Usa: assets.ui.indice, interfaz/inteligencia, mundo/choques, mundo/ciudades, mundo/estandartes, mundo/instalaciones, mundo/iso, mundo/modelos, mundo/modelos3d, mundo/plantas, mundo/recursos, mundo/ruido, mundo/senales, mundo/simulacion, mundo/terreno, mundo/territorio

- `Mundo.nuevo(semilla)` (l.35)
- `Mundo:opcionesSimulacion()` (l.75) — Lo que la simulación necesita saber del mundo físico: dónde se puede construir.
- `Mundo:sitioValido()` (l.82) — Dónde se puede construir: tierra firme, no muy alta, fuera de las ciudades.
- `Mundo:ciudadInicial()` (l.107) — Primera ciudad cerca del origen, para empezar allí.
- `Mundo:datosZona(zx, zy)` (l.124) — Datos de la zona (zx, zy): sus ciudades (la más grande primero: la capital) y sus depósitos. Todo sale de la semilla.
- `Mundo:registrarNacionDe(rx, ry)` (l.163) — Registra la nación de una región y las de alrededor (sin seguir más lejos).
- `Mundo:despejados(tx, ty)` (l.179) — Sitios donde no crecen plantas en un trozo: depósitos e instalaciones cercanas.
- `Mundo:sinPlantas(tx, ty)` (l.208) — Filtro de plantas de un trozo: ¿(x, y) cae en una ciudad, un depósito o una instalación, donde no crece nada?
- `Mundo:plantasTrozo(tx, ty)` (l.220)
- `Mundo:explorarTrozo(tx, ty)` (l.226) — Explora un trozo sin dibujarlo: sus ciudades se construyen, su nación entra en la simulación y sus depósitos se ven. Lo usa `generarTrozo`.
- `Mundo:generarTrozo(tx, ty)` (l.246)
- `Mundo:usarSimulacion(sim)` (l.257) — Cambia la simulación por otra (una partida cargada): el mundo físico es el mismo, las ciudades se vuelven a enlazar por su id de región.
- `Mundo:apartarPlantas()` (l.269) — Cuando aparece una obra nueva en un trozo cargado, se apartan sus plantas.
- `Mundo:actualizar(dt, vista)` (l.300) — Genera lo que falta cerca de la cámara, olvida lo lejano y avanza el tiempo.
- `Mundo:repintarTerritorio(x0, y0, x1, y1)` (l.371) — Rehace la malla de territorio de los trozos que la tienen vieja: solo cuando cambia `versionTerritorio` (una celda que cambia de dueño) o el grosor…
- `Mundo:cargado(x, y)` (l.410)
- `Mundo:dibujar()` (l.414)
- `dibujarEstrella(x, y, r)` (l.485) — Estrella de cinco puntas rellena, centrada en (x, y), de radio `r`.
- `Mundo:dibujarNombres()` (l.514) — Nombre de cada ciudad a la vista y, sobre la capital, una estrella y el nombre de su país: texto blanco con contorno sobre un rótulo oscuro, y el…
- `Mundo:dibujarYacimientos()` (l.590) — Iconos de los yacimientos explorados (3.8): gota, pico, pepita o espiga, del mismo tamaño en pantalla a cualquier zoom, con el aro del color de su…
- `Mundo:minaEn(vx, vy)` (l.640) — Yacimiento cuyo icono está bajo el punto (vx, vy) de la vista, o nil.
- `Mundo:dibujarBanderas()` (l.655) — Banderas plantadas (3.7): un mástil con el paño y el escudo de su nación, de tamaño fijo en pantalla, con la barra de obra y, si la atacan, la de…
- `Mundo:piezasDepositos(piezas)` (l.685) — Yacimientos e instalaciones (bases, campamentos y banderas). Ya no hay extracciones: los yacimientos se recolectan con grupos…
- `Mundo:ciudadFisica(id)` (l.724) — La ciudad física de `id`: la de la región ('rx,ry', sale de la semilla) o una fundada durante la partida (si ya se vio).
- `Mundo:puestosLanzacohetes(sitio)` (l.735) — Puestos (x, y, z) de los lanzacohetes de un sitio: en un anillo alrededor de una ciudad o por fuera de la losa de una base, siempre en tierra y…
- `Mundo:lanzacohetesVisibles(sitio)` (l.785) — Cuántos lanzacohetes se ven en un sitio: los de la ciudad (hasta 4) o los de una base terminada (hasta 6).
- `Mundo:piezasLanzacohetes(piezas)` (l.795)
- `Mundo:sitioEn(x, y)` (l.829) — Sitio (ciudad o base) que está en (x, y): de ahí sale una salva.
- `Mundo:posicionRetirada(gr, fraccion)` (l.857) — Dónde se ve un grupo en retirada, y hacia dónde mira; nil si no se ve.
- `Mundo:posicionVisible(gr, fraccion)` (l.887) — Dónde se ve un grupo, y hacia dónde mira; nil si no se ve. Los grupos no recorren el mapa: un ejército que sale a atacar se despliega unos metros…
- `Mundo:posicionFicha(gr, fraccion)` (l.913) — Dónde se dibuja la ficha de un grupo y hacia dónde va; nil si no tiene camino.
- `Mundo:minaDeGrupo(gr)` (l.941) — Mina en la que está un grupo que recolecta en ella (fase 'recolectando') o un ejército que ya la ataca; nil si no.
- `Mundo:fichasGrupos()` (l.957) — Fichas de los grupos a la vista (una por grupo). Se dibujan al final, con tamaño fijo en pantalla (ver `dibujarFichas`).
- `Mundo:fichaPar(c, fraccion, inicios)` (l.1019) — Entrada de un choque para `dibujarFichas`: el punto del choque en la vista y, a cada lado, la ficha que viene de ese lado de la pantalla.
- `Mundo:repele(o, naciones)` (l.1061) — ¿Debe apartarse una ficha de naciones `naciones` de la caja ocupada `o`? Los nombres de ciudad (sin nación) apartan siempre; las fichas, solo si…
- `Mundo:apartar(vx, vy, w, h, arriba, naciones, ocupados, k)` (l.1078) — Desplazamiento horizontal (px de pantalla) para que la caja de `w` x `h` (px de pantalla), centrada en `vx` y con su borde de arriba `arriba` px…
- `Mundo:dibujarFichas()` (l.1116) — Dibuja las fichas: estandarte y etiqueta de los ejércitos, banderín de los convoyes.
- `Mundo:dibujarRecolectoresMina(ancla, fichas, k, ocupados)` (l.1168) — Los recolectores que recolectan en una mina, anclados en pantalla justo debajo de su icono (`ancla`, caja en la vista), a cualquier zoom: una ficha…
- `Mundo:dibujarAtacantesMina(ancla, fichas, mitad, k, ocupados)` (l.1231) — Los ejércitos que atacan una mina, a un lado de su icono (`ancla`) y a `huecoMina` px de pantalla de él y de sus recolectores (que ocupan `mitad` px…
- `Mundo:dibujarFicha(f, k, ocupados)` (l.1301) — Una ficha sola (ver `dibujarFichas`).
- `Mundo:dibujarPar(f, k, ocupados)` (l.1336) — Las dos fichas de un choque, enfrentadas en el punto del choque a `Choques.separacion` px de pantalla, con el polvo y los destellos entre ellas.
- `Mundo:dibujarPolvoChoque(x, y, m, clave)` (l.1402) — Polvo al pie de las dos fichas trabadas, centrado en (x, y) px de pantalla. Va con el reloj del combate: se para en pausa.
- `Mundo:dibujarDestellosChoque(x, y, m, clave)` (l.1418) — Destellos pequeños entre las espadas de las dos fichas.
- `Mundo:fichaEn(vx, vy)` (l.1448) — Grupo cuya ficha está bajo el punto (vx, vy) de la vista, o nil. Si hay varias, la de delante (la última dibujada).
- `Mundo:tanqueEnCombate(clave, semilla, x, y, z, anguloCasco, blancoX, blancoY, casco)` (l.1515) — Torreta de un tanque que combate. `clave` lo identifica entre cuadros y `semilla` es su número; está en (x, y, z), su casco mira a `anguloCasco` y…
- `Mundo:dispararTanque(semilla, t, x, y, z, anguloCasco, casco)` (l.1568) — Dispara el tanque `t` (ya apuntando a su mira): retroceso, fogonazo y humo en la boca y una bala trazadora hacia delante.
- `Mundo:actualizarCombate(_)` (l.1626) — Avanza las balas (al llegar, un impacto con polvo) y borra los efectos terminados y los tanques que ya no se ven.
- `Mundo:posturaTanque(clave, x, y, z, rumbo)` (l.1685) — Postura 3D (matriz del casco) del tanque `clave` en (x, y, z) mirando a `rumbo`.
- `Mundo:dibujarTanqueAparcado(x, y, z, color, angulo, sitio, k)` (l.1702) — Tanque aparcado de un sitio (ciudad o base) mirando a `angulo`, con el `color` de su nación.
- `Mundo:dibujarCombate()` (l.1743) — Balas trazadoras, fogonazos, humo e impactos de los tanques, encima de las piezas (duran muy poco).
- `Mundo:ahora()` (l.1807) — Hora del juego (días con decimales): los visuales de guerra se miden con ella, así que van al ritmo de la velocidad elegida y se congelan en pausa.
- `Mundo:avisarAccion(x, y)` (l.1812) — Apunta dónde hubo acción (para la tecla X, que lleva a la última).
- `Mundo:recibirBatallas()` (l.1819) — Batallas nuevas (de cualquiera): se apuntan para la tecla X.
- `Mundo:enVista(vx, vy)` (l.1830) — ¿Cae el punto de vista (vx, vy) dentro de lo que se ve (con margen)?
- `Mundo:ciudadMasCercana(x, y)` (l.1840) — Ciudad descubierta más cercana a un punto de mundo, con su distancia.

## mundo/plantas.lua

Plantas procedurales: ninguna igual a otra.

- Tamaño: 272 líneas, 11 funciones públicas, 5 locales.
- Usa: mundo/iso, mundo/ruido

- `DIBUJOS.pino(v, x, y, azar, nevado)` (l.78)
- `DIBUJOS.pinoNevado(v, x, y, azar)` (l.107)
- `DIBUJOS.copa(v, x, y, azar)` (l.111)
- `DIBUJOS.arbusto(v, x, y, azar)` (l.131)
- `DIBUJOS.matorral(v, x, y, azar)` (l.139)
- `DIBUJOS.flores(v, x, y, azar)` (l.145)
- `DIBUJOS.cactus(v, x, y, azar)` (l.164)
- `DIBUJOS.roca(v, x, y, azar)` (l.184)
- `DIBUJOS.penasco(v, x, y, azar)` (l.194) — Peñasco: una roca grande de las laderas (de 2 a 5 m), con caras marcadas.
- `Plantas.enTrozo(terreno, tx, ty, dentroDeCiudad)` (l.209) — Plantas de un trozo, sin dibujar: { x, y, h, tipo, semilla } de cada una.
- `Plantas.mallaTrozo(terreno, tx, ty, dentroDeCiudad)` (l.250) — Malla con todas las plantas de un trozo, ordenadas de atrás adelante. Nil si el trozo no tiene ninguna.

## mundo/recursos.lua

Yacimientos: petróleo, metal, oro y comida (diseno/territorio-y-capitales.md, 3.8).

- Tamaño: 282 líneas, 6 funciones públicas, 7 locales.
- Usa: mundo/iso, mundo/ruido

- `Recursos.nuevo(terreno, ciudades)` (l.20)
- `Recursos:pendiente(x, y)` (l.30) — Pendiente del terreno natural en (x, y): |∇altura| medida a ±100 px.
- `Recursos:aptitudes(x, y)` (l.39) — Aptitud de (x, y) para cada tipo (tabla de 3.8), el bioma y la altura; nil en el agua.
- `Recursos:deCelda(cx, cy)` (l.93) — Yacimiento de la celda (cx, cy) o false (F10). Siempre se tiran los cuatro números, haya yacimiento o no.
- `Recursos:deRegion(rx, ry)` (l.139) — Yacimientos de la región (rx, ry): `{ id, tipo, x, y, riqueza, altura }`, los de las celdas cuyo punto cae dentro de la región (así cada uno sale en…
- `Recursos.dibujar(d, colorDueno, tiempo)` (l.268) — Dibuja un yacimiento con el aro de su dueño.

## mundo/ruido.lua

Ruido simplex 2D con semilla, fBm y crestas.

- Tamaño: 187 líneas, 8 funciones públicas, 1 locales.

- `Ruido.nuevo(semilla)` (l.23)
- `Ruido:simplex(x, y)` (l.63) — Simplex 2D en [-1, 1].
- `Ruido:fbm(x, y, octavas)` (l.95) — Suma de octavas, normalizada: aprox. [-1, 1].
- `Ruido:crestas(x, y, octavas)` (l.109) — Crestas: 1 en las cumbres afiladas, 0 lejos de ellas. Para cordilleras.
- `Ruido.hash(semilla, a, b, c)` (l.125) — Número pseudoaleatorio estable para unas coordenadas enteras: la base de que cada árbol y cada ciudad salga siempre igual en el mismo sitio.
- `Ruido.azar(semilla)` (l.135) — Generador de números a partir de una semilla (para decidir las piezas de una planta o de una ciudad). Devuelve una función como `math.random`.
- `Generador.__call(self, a, b)` (l.162)
- `Ruido.generador(semilla)` (l.176)

## mundo/senales.lua

Señales del mapa en píxeles de pantalla: los iconos de los yacimientos (diseno/territorio-y-capitales.md, 3.8) y el mástil de las banderas (3.7).

- Tamaño: 304 líneas, 4 funciones públicas, 6 locales.
- Usa: interfaz/tema, mundo/estandartes

- `Senales.ladoYacimiento(zoom)` (l.98) — Lado en pantalla del icono de un yacimiento (más pequeño muy de lejos).
- `Senales.yacimiento(y, cx, cy, lado, estilo)` (l.123) — Icono de un yacimiento con el centro en (cx, cy). `y` es el de `sim:yacimientosEn` / `sim:mina` (tipo, riqueza, queda, reserva, cerrada,…
- `Senales.medidasBandera()` (l.243) — Medidas de la señal de una bandera (px de pantalla): alto del mástil y ancho del paño.
- `Senales.bandera(b, sx, sy, color, escudo, soloBarras)` (l.251) — Bandera con el pie del mástil en (sx, sy). `b` es la de `sim:banderas`, `color` el de su nación y `escudo` su combinación (Estandartes.escudoDe).

## mundo/simulacion.lua

Simulación del mundo vivo: naciones, ciudades, instalaciones, grupos y guerras.

- Tamaño: 3985 líneas, 138 funciones públicas, 27 locales.
- Usa: mundo/ruido, mundo/simulacion/ataques, mundo/simulacion/ayudas, mundo/simulacion/batallas, mundo/simulacion/consultas, mundo/simulacion/diplomacia, mundo/simulacion/exploracion, mundo/simulacion/guardado, mundo/simulacion/lideres, mundo/simulacion/municion, mundo/simulacion/nombres, mundo/simulacion/produccion, mundo/simulacion/recoleccion, mundo/simulacion/recoleccionIA, mundo/simulacion/taller, mundo/simulacion/territorio

- `Simulacion.nivel(nivel)` (l.193) — Datos del nivel `nivel` de una ciudad. Los niveles por encima de la tabla usan el último: la tabla puede crecer (niveles 1 a 50) sin tocar a quien…
- `Simulacion.casco(c)` (l.200) — Radio físico de una ciudad (sus calles, a escala real). Las partidas viejas no lo guardaban: 5 veces el radio de la economía, como en el mundo.
- `Simulacion.nivelInicial(_radio, esCapital)` (l.206) — Nivel con el que nace una ciudad: 1, y la capital 2. `radio` queda para ajustes futuros (ciudades grandes que nazcan más altas).
- `Simulacion.colorNacion(nid)` (l.293) — Color de un país por su zona ('z:zx,zy'): (5·zx + 3·zy) mod 12 da un color distinto a cada una de sus 8 zonas vecinas.
- `Simulacion.misilesListos(s)` (l.310) — Cuántos misiles puede disparar un sitio (ciudad o base) en una salva: los que le permitan sus lanzacohetes.
- `Simulacion.topeLanzacohetes(s)` (l.316) — Cuántos lanzacohetes admite un sitio: una base, los de sus plataformas; una ciudad, el tope de su nivel (el mismo que para sus baterías).
- `Simulacion.vidaGrupo(g)` (l.381) — Vida de un grupo: soldados, tanques y lanzacohetes con el mismo peso que en combate. Es también la fuerza con la que golpea.
- `Simulacion.poderUnidad(tropa)` (l.403) — Poder de una unidad (F1): escalaPoder × (vida + golpe) / 2.
- `Simulacion.poder(g)` (l.418) — Poder de un grupo (F2). Hoy es exactamente 5,5 × `vidaGrupo(g)`.
- `Simulacion.poderSitio(s)` (l.425) — Poder de las tropas sanas de un sitio (ciudad, base, extracción o campamento), con la misma cuenta que un ejército.
- `Simulacion.poderRedondeado(poder)` (l.430) — El poder como se muestra: redondeado al entero (F2).
- `Simulacion:indiceGrupos()` (l.488) — Índice de grupos: todos en orden de id y, en el mismo orden, por nación, por misión y por objetivo. No es estado: se rehace del estado.
- `Simulacion:gruposOrdenados()` (l.545) — Grupos en orden de id, lo mismo que `lista(e.grupos)` pero sin ordenar cada vez (ver `indiceGrupos`).
- `Simulacion:gruposDe(nid)` (l.550) — Grupos de la nación `nid`, en orden de id.
- `Simulacion:gruposConMision(mision)` (l.555) — Grupos con la misión `mision`, en orden de id.
- `Simulacion:gruposHacia(id)` (l.560) — Grupos cuyo objetivo es `id` (un sitio, un yacimiento o un grupo), en orden de id.
- `Simulacion:gruposDeAmbas(a, b)` (l.565) — Grupos de las naciones `a` y `b`, en orden de id.
- `Simulacion:nivelCapital(nid)` (l.584) — Nivel de la capital de una nación (1 si no la tiene).
- `Simulacion:almacen(nid)` (l.591) — Tope del almacén de una nación, para el metal y para el petróleo (F1).
- `Simulacion:boveda(nid)` (l.597) — Tope de la bóveda de una nación, para el dinero (F1b).
- `Simulacion.disponible(n, recurso)` (l.622) — Lo que una nación puede gastar de un recurso ('metal', 'petroleo' o 'dinero'): lo guardado más lo de afuera.
- `Simulacion:ingresar(n, recurso, cantidad)` (l.629) — Entra `cantidad` de un recurso: al almacén o a la bóveda hasta su tope, y el resto afuera.
- `Simulacion.alcanza(n, coste)` (l.652) — ¿Le alcanza a la nación para `coste` ({ metal, petroleo, dinero })?
- `Simulacion.pagar(n, coste)` (l.662) — Paga `coste` si alcanza (primero de afuera). Devuelve si pagó.
- `Simulacion:mermar()` (l.675) — Merma de lo que está afuera (F2): una vez al día, antes de que entre nada.
- `Simulacion:ajustarAlmacen(n)` (l.686) — Lo que pasa del tope del almacén o de la bóveda sale afuera (si baja el tope o si algo entró sin `ingresar`).
- `Simulacion:trazar(x0, y0, x1, y1)` (l.700) — Camino de (x0, y0) a (x1, y1): en línea recta. Los grupos no recorren el mapa (no hay rutas ni carreteras): el presidente los manda, tardan lo que…
- `Simulacion.largoRuta(ruta)` (l.705) — Largo total de una ruta.
- `Simulacion.puntoEnRuta(ruta, recorrido)` (l.716) — Punto de la ruta a `recorrido` px del inicio, y el rumbo del tramo.
- `Simulacion.posicionGrupo(g, fraccion)` (l.736) — Dónde dibujar un grupo entre dos días (`fraccion` de 0 a 1) y hacia dónde mira.
- `Simulacion.nueva(semilla, opciones)` (l.753) — `opciones.sitioValido(x, y)` dice si se puede construir ahí (tierra firme, fuera de las ciudades). Sale del mundo físico: no se guarda.
- `Simulacion:noticia(texto, color)` (l.783)
- `Simulacion:nacion(id)` (l.791)
- `Simulacion:ciudad(id)` (l.795)
- `Simulacion:instalacion(id)` (l.799)
- `Simulacion:sitio(id)` (l.804) — Ciudad o base con ese id (los sitios desde donde salen las fuerzas).
- `Simulacion:indice()` (l.817)
- `Simulacion:anotarInstalacion(inst)` (l.864) — Apunta una instalación nueva en el índice sin rehacerlo entero (quedan las mismas listas, en el mismo orden, que al rehacerlo).
- `Simulacion:todasInstalaciones()` (l.887) — Todas las instalaciones en orden de id (del índice: no se cambia). Junta las que se anotaron desde la última vez.
- `Simulacion:ensuciar()` (l.914) — Marca el índice para rehacerlo (algo nació, cayó o cambió de manos). El territorio no cambia aquí: cambia celda a celda (`ponerCelda`).
- `Simulacion:ensuciarEn(_sitio)` (l.919) — Algo nació o cayó en `sitio` (una instalación): el índice se rehace.
- `Simulacion:ciudadesDe(nid)` (l.923)
- `Simulacion.explotacion()` (l.930) — Instalación que explota un yacimiento: ya no hay (las extracciones desaparecieron y los campamentos no producen).
- `Simulacion:depositosCerca(x, y, radio)` (l.938) — Yacimientos registrados a menos de `radio` de (x, y), en orden fijo.
- `Simulacion:instalacionesDe(nid, tipo)` (l.962)
- `Simulacion:sitiosDe(nid)` (l.987) — Sitios con fuerzas de una nación: sus ciudades y sus bases terminadas.
- `Simulacion:vivas()` (l.1003) — Naciones con alguna ciudad, en orden de id (una copia). La lista se guarda en el índice: cambia solo cuando nace una nación o una ciudad cambia de…
- `Simulacion:fuerzaCiudad(c)` (l.1029)
- `Simulacion:fuerza(nid)` (l.1033)
- `Simulacion:relacion(a, b)` (l.1047)
- `Simulacion:guerraEntre(a, b)` (l.1051)
- `Simulacion:guerrasDe(nid)` (l.1055)
- `Simulacion:numeroGuerras(nid)` (l.1066) — Cuántas guerras tiene `nid` (contar no depende del orden: sin ordenar).
- `Simulacion:tiene(nid, tecnologia)` (l.1076)
- `Simulacion:registrarZona(zona)` (l.1091) — Registra una nación entera (su zona): capital, ciudades y depósitos. `zona = { clave, ciudades = { {id, nombre, x, y, radio, altura}, ...
- `Simulacion:todasCiudades()` (l.1205)
- `Simulacion:puedeAtacar(nid, objetivoId)` (l.1226) — ¿Puede `nid` atacar `objetivoId`? Una bandera enemiga solo se ataca si el trozo de territorio donde está toca por un lado una celda de quien ataca.
- `Simulacion:jugadores()` (l.1263) — Naciones de jugador, en orden fijo.
- `Simulacion:escenarioPrueba(c)` (l.1280) — Escenario para probar el combate: la nación viva cuya capital está más cerca del origen del mundo pasa a ser del jugador; la capital viva más…
- `Simulacion:ejecutar(c)` (l.1335)
- `Simulacion:mejorarCiudad(nid, cid)` (l.1412) — Empieza a mejorar una ciudad al nivel siguiente, pagando del almacén del país.
- `Simulacion:plantarHuerto(nid, cid)` (l.1432) — Planta un huerto junto a una ciudad propia que no lo tenga: en el primer sitio de tierra firme a su alrededor (en orden fijo desde un ángulo que…
- `Simulacion.costeReparacion(puntos)` (l.1453) — Lo que cuesta reparar `puntos` de vida de una ciudad (F4).
- `Simulacion.ritmoReparacion(c)` (l.1459) — Puntos de vida al día que recupera una ciudad en reparación (F5).
- `Simulacion.diasReparacion(c)` (l.1465) — Días que le quedan a la reparación encargada de una ciudad (0 si no hay). No cuenta los días de asedio, que la paran.
- `Simulacion:reparar(nid, cid, puntos)` (l.1474) — Encarga `puntos` de vida para una ciudad propia (3.5): se paga todo al empezar (F4, primero de afuera) y entra en `c.reparacion`, que sube la vida…
- `Simulacion:avanzarReparacion(c)` (l.1492) — Un día de reparación de una ciudad: sube su vida si no está sitiada.
- `Simulacion:planearReparaciones(n)` (l.1508) — El presidente NPC repara sus ciudades por debajo de `umbralIA` que no estén sitiadas: los puntos que pueda pagar sin bajar de `reservaMetal` de…
- `Simulacion:enviarDefensas(nid, sid, defensa, cantidad)` (l.1535) — Pone defensas en un sitio propio. Lanzacohetes: los COLOCA desde el parque de su ciudad (no se compran: se producen con `producir`); en una ciudad,…
- `Simulacion:enCamino(sid, defensa)` (l.1596) — Cuántas defensas de un tipo van de camino a un sitio (ciudad o base).
- `Simulacion:entregar(n, c, defensa, cantidad, desde)` (l.1630) — Los lanzacohetes salen de la ciudad `desde` (o de la capital) y protegen la base al llegar (tardan el viaje, pero no se ven por el camino).
- `Simulacion:enFrontera(c)` (l.1664) — ¿Hay un rival hostil (en guerra, o con la relación por debajo de `hostil`) con una ciudad o una base a menos de `frontera` de esta ciudad?
- `Simulacion:protegerCiudades(n)` (l.1711) — El presidente resguarda sus ciudades: las de frontera y la capital hasta el tope de su nivel, pagando del tesoro si la ciudad no puede; las del…
- `Simulacion:protegerBases(n)` (l.1736) — El presidente llena de lanzacohetes sus bases terminadas hasta el tope de sus plataformas, pagando del tesoro si la ciudad que las abastece no…
- `Simulacion:atenderHambre(n)` (l.1756) — El presidente no deja que su gente pase hambre: a una ciudad sin granjas propias que va justa de comida o ya la pasa le planta un huerto.
- `Simulacion:planearMejoras(n)` (l.1769) — El presidente mejora todas las ciudades que puede pagar, a la vez: no hay turnos, solo recursos.
- `Simulacion:declararGuerra(a, b, motivo)` (l.1800)
- `Simulacion:umbralRetirada(nid, retirada)` (l.1827) — Umbral de retirada de un grupo de `nid`: el que elija quien lo manda (`retirada`, de 0 a `umbralMaximo`; con 0 lucha hasta el final) o, si no elige,…
- `Simulacion:sumarCansancio(nid, cuanto)` (l.1981)
- `Simulacion:destruirInstalacion(inst, por)` (l.1993) — Una instalación vencida se borra y su tierra queda sin dueño si nadie más la cubre.
- `Simulacion:remolcarGuarnicion(inst)` (l.2027) — Lo que queda en una instalación que se pierde vuelve remolcado al taller de su ciudad (ver `destruirInstalacion`).
- `Simulacion:ahora()` (l.2049) — Hora del juego: el día con la fracción ya transcurrida.
- `Simulacion.produce()` (l.2057) — ¿Produce hoy la instalación? Ya no: nada produce solo (3.3). Queda para la vista de antes.
- `Simulacion.efectoVida(vida)` (l.2062) — Efecto de la vida (F6): f(V) = efectoMinimo + (1 - efectoMinimo) × V / 100.
- `Simulacion.vidaSitio(s)` (l.2069) — Vida de un sitio de 0 a 100: la de una ciudad (`c.vida`) o la salud de una instalación sobre su máximo (un campamento, sobre 30).
- `Simulacion:comidaHuerto(c)` (l.2086) — Comida que da hoy el huerto de una ciudad: lo que le falta a su gente (sin contar a los soldados) hasta su tope, y nada si no está terminado.
- `Simulacion.granero(c)` (l.2099) — Tope del granero de una ciudad.
- `Simulacion:ciudadDuena(nid, x, y)` (l.2106) — Ciudad propia más cercana a un punto: la que se queda lo que da una granja y la que abastece a una base.
- `Simulacion:gastoCombustible(nid)` (l.2133) — Combustible que gastan al día los vehículos y aviones de una nación (F9): `combustible.parado` por vehículo en sus sitios, en su parque o en un…
- `Simulacion:mantenimientoCampamento(i)` (l.2158) — Mantenimiento de un campamento (petróleo al día, fijo: 3.3) y su distancia a la ciudad propia más cercana (el orden en que se paga).
- `Simulacion:mantenimientoCampamentos(nid)` (l.2165) — Petróleo al día que cuestan todos los campamentos terminados de una nación.
- `Simulacion.mantenimientoSiguiente()` (l.2176) — Lo que costaría el siguiente campamento.
- `Simulacion:necesidades(nid)` (l.2204) — Necesidad de cada recurso para una nación: { metal = n, petroleo = n, comida = n }.
- `Simulacion:reservaComida(c)` (l.2263) — Granero de una ciudad: lo que tiene, lo que dan sus tierras (y, en la capital, lo que traen sus recolectores de media), lo que come su gente y…
- `Simulacion:reservas(nid)` (l.2282) — Cómo va una nación de cada recurso: cuánto tiene, lo que entra y lo que gasta a la fuerza cada día (mantener tanques, aviones y campamentos),…
- `Simulacion:producirRecursos()` (l.2320) — Nada produce solo (3.3): cada día solo se paga el mantenimiento de los campamentos y las banderas. Lo que entra lo traen los recolectores.
- `Simulacion:mantenerCampamentos(n)` (l.2329) — Paga el petróleo de los campamentos terminados de una nación, del más cercano a su ciudad al más lejano.
- `Simulacion:mantenerBanderas(n)` (l.2370) — Paga el dinero de las banderas terminadas (F9), de la más cercana a su ciudad a la más lejana.
- `Simulacion:retirarGuarnicion(i)` (l.2410) — La guarnición de un campamento abandonado vuelve a pie a la ciudad propia más cercana (misión 'regreso'), con sus lanzacohetes.
- `Simulacion:economia(n)` (l.2455) — La economía de un día de una nación (diseno/economia.md): cada ciudad come de su granero (sus tierras dan una parte y el resto llega de sus…
- `Simulacion:mercadoComida(ciudades)` (l.2525)
- `Simulacion:sitioCercano(nid, x, y, soldados, campo)` (l.2566) — Sitio propio más cercano a un punto, con al menos `soldados`.
- `Simulacion:expansion(n, azar, turno)` (l.2579)
- `Simulacion:sitiosConTerritorio(nid)` (l.2593) — Sitios de una nación que ya dan territorio, con su alcance: { sitio, alcance }.
- `Simulacion.bloqueBandera(x, y)` (l.2611) — Bloque de celdas que dará una bandera plantada en (x, y): cx0, cy0, cx1, cy1.
- `Simulacion:puedePlantarBandera(nid, x, y)` (l.2620) — ¿Puede `nid` plantar una bandera en (x, y)? En cualquier terreno (tierra, montaña, lago u océano).
- `Simulacion:plantarBandera(nid, x, y)` (l.2648) — Planta una bandera en (x, y): se paga al momento y se levanta sola en `dias` de obra, sin tropa; al terminarse toma las celdas libres de su bloque…
- `Simulacion:yacimientosConocidosDe(nid, tipo)` (l.2681) — Yacimientos de un tipo que conoce una nación (ver `yacimientosConocidos`).
- `Simulacion:yacimientosConocidos(nid)` (l.2702) — Yacimientos que conoce una nación: los registrados a menos de `alcanceMeta` de su capital (se recalcula al registrar zonas).
- `Simulacion:sitiosEnemigos(nid)` (l.2715) — Sitios (ciudades e instalaciones) de las naciones en guerra con `nid`.
- `Simulacion:valorYacimiento(nid, d, territorio, enemigos)` (l.2732) — Valor de un yacimiento para una nación (F12): riqueza × necesidad / (1 + distanciaBorde / distanciaValor), y 0 si hay un sitio enemigo en guerra a…
- `Simulacion.distanciaBorde(territorio, x, y)` (l.2749) — Distancia de (x, y) al borde del territorio propio (F12), aproximada como distancia al sitio − su alcance, con mínimo 0; nil si no tiene sitios.
- `Simulacion:caminoCeldas(nid, tx, ty)` (l.2861) — Camino más corto de celdas (por sus cuatro lados) desde el territorio de `nid` hasta la celda (tx, ty), en cualquier terreno y sin pisar celdas de…
- `Simulacion:banderaEnObraCerca(nid, x, y)` (l.2930) — ¿Tiene `nid` una bandera en obra a menos de su medio bloque de (x, y)? Entonces esa tierra ya está pedida: no se planta otra encima.
- `Simulacion:banderaHacia(n, meta)` (l.2942) — Sigue el camino más corto de celdas hacia la meta (`caminoCeldas`) y planta una bandera lo más adelante posible con su bloque aún pegado a lo suyo,…
- `Simulacion:planearBanderas(n)` (l.2962) — El presidente NPC estira su tierra con banderas hacia el yacimiento que más le vale (3.9, F12): uno sin explotar, o suyo pero descubierto, que no…
- `Simulacion:valorBandera(n, b)` (l.3018) — Valor de una bandera para su dueño: el F12 del yacimiento que protege (el más cercano en su territorio), o 1 si no protege ninguno.
- `Simulacion:defenderBanderas(n)` (l.3035) — El presidente NPC defiende sus banderas atacadas que valen más de 1: manda un ejército con más fuerza que la del atacante desde el sitio más cercano…
- `Simulacion:levantarCampamento(nid, x, y)` (l.3089) — Planta un campamento en (x, y): tiene que caer dentro del territorio propio, en tierra donde se pueda construir y lejos de otro campamento suyo.
- `Simulacion:planearCampamento(n)` (l.3131) — El presidente estira su territorio con campamentos: hacia el depósito sin dueño más cercano o, si no hay, hacia el vecino más cercano.
- `Simulacion:construirBase(n, azar)` (l.3248) — Bases militares en su territorio, hacia el vecino más cercano: una a la vez.
- `Simulacion:obras()` (l.3318) — Obras del día: avanza la construcción, crece la fortificación y se repara.
- `Simulacion:volver(g)` (l.3364) — El grupo vuelve a casa (misión 'regreso'): a su sitio de salida o, si ya no es suyo, al sitio propio más cercano; con carga, a una ciudad o un…
- `Simulacion:retirar(g, blanco)` (l.3389) — El grupo da media vuelta hacia su sitio con los vivos y los heridos.
- `Simulacion:sitiada(c)` (l.3413) — ¿Tiene una ciudad un ejército enemigo encima (combatió hoy o ayer)? Sitiada no recluta, no recibe defensas ni avanza su reparación.
- `Simulacion:saquearCapital(c, g)` (l.3421) — Una capital pierde su batalla (3.3): no cambia de manos. Queda con `derrota` de vida, conserva lo que sobrevivió (tropas, defensas, mejora y cola de…
- `Simulacion:llegada(g)` (l.3450)
- `Simulacion:enGuerraAbierta(a, b)` (l.3586) — ¿Están `a` y `b` en guerra abierta (no en alto el fuego)?
- `Simulacion:hostiles(a, b)` (l.3594) — ¿Pelean `a` y `b` si se encuentran? Hoy, dos naciones en guerra abierta.
- `Simulacion:lugarCercano(x, y)` (l.3643) — Nombre de la ciudad más cercana a (x, y), para las noticias.
- `Simulacion:nombreNacionDe(g)` (l.3660) — Nombre de la nación de un grupo, para las noticias.
- `Simulacion:detectarChoques()` (l.3669) — Busca los choques del día (F7). Solo compara ejércitos que comparten celda de la rejilla (el trayecto de cada uno, ensanchado `radio`, la marca).
- `Simulacion:trabar(g, o, t)` (l.3739) — Traba a `g` y `o` en el momento `t` de sus trayectos: se paran y empieza una batalla de campo entre los dos (ataca el que iba a atacar; si iban los…
- `Simulacion:esperaDetenido(g)` (l.3767) — Mueve los grupos un día. Primero se mueven todos; luego se buscan los choques (los trabados no llegan a su destino); después llegan los demás,…
- `Simulacion:asaltarTrasChoque(llegados)` (l.3797) — Un ejército que gana un choque junto a su destino (ya en él: `recorrido` al final de la ruta) hace su llegada ese mismo día y empieza el asalto, en…
- `Simulacion:moverGrupos(azar)` (l.3817)
- `Simulacion:avanzarDia()` (l.3912)
- `Simulacion:actualizar(dt, velocidad)` (l.3967) — Avanza el tiempo real: `velocidad` días por segundo. Los eventos de comandos dados entre dos días se conservan hasta que el mundo los dibuje.

## mundo/simulacion/ataques.lua

Ataques y órdenes a los grupos: aviso de ataques, retirar, redirigir, ir a un punto y llegada a minas y sitios.

- Tamaño: 406 líneas, 13 funciones públicas, 2 locales.
- Usa: mundo/simulacion/ayudas

- `Ataques:blancoDe(g)` (l.24) — Lo que ataca un grupo: { tipo = 'sitio' | 'mina', id, naciones = { nid = true } } (las naciones atacadas: la del sitio o las de los recolectores de…
- `Ataques:avisosAtaque(nid)` (l.47) — Ataques que van hacia algo de `nid` (un sitio suyo o una mina con sus recolectores) y llegan en `avisoDias` o menos: { grupo, nacion, objetivo = {…
- `Ataques:poderConocido(nid, objetivo)` (l.74) — Poder de `objetivo` (un grupo o un sitio ajeno) que conoce `nid` por su informe, redondeado, o nil si no tiene informe.
- `Ataques:avisarAtaques()` (l.82) — Noticia (una vez por grupo) de cada ataque que llega pronto a algo de un jugador: «El ejército de X va hacia Y: llega en N días» y, solo si tiene…
- `Ataques:retirarGrupo(nid, gid)` (l.135) — Orden de volver a casa (3.1.7) para un grupo propio que está fuera: con la carga que lleve (en una batalla, la pierde: es una retirada).
- `Ataques.mandable(g)` (l.152) — ¿Se le pueden dar órdenes de marcha? Las obras, las entregas, los convoyes de munición y los remolques siguen su camino.
- `Ataques:redirigir(nid, gid, destinoId)` (l.161) — Manda a un grupo propio que está fuera a otro sitio propio (una ciudad, un campamento o una base terminados) o a una batalla en la que pelea su…
- `Ataques:irAPunto(nid, gid, x, y)` (l.205) — Manda a un grupo propio a un punto del mapa (dueño 2026-09-29): camina libre por el mundo sin necesidad de tener una ciudad propia como destino.
- `Ataques:blancoEn(x, y)` (l.256) — Busca el primer objetivo atacable bajo el punto (x, y): una ciudad o una instalación (campamento, base, bandera, huerto) cercana al click.
- `Ataques:llegarAMina(g, d)` (l.283) — Un grupo que va a atacar llega a una mina (3.5): pelea contra los recolectores de las naciones hostiles.
- `Ataques:llegarASitio(g, s)` (l.340) — Un grupo que va a atacar llega a un sitio (ciudad, campamento, base o bandera): empieza la batalla o se suma a la que ya hay.
- `Ataques:atacarDesdeMina(nid, gid, yacimientoId, liderId)` (l.358) — Un grupo que ya recolecta en una mina recibe la orden de atacar allí (3.5.5): pasa a ser un ejército (con un líder libre) y la batalla empieza al…
- `Ataques.instalar(clase)` (l.394) — Cuelga de la clase Simulacion las funciones y datos de este módulo.

## mundo/simulacion/ayudas.lua

Ayudas compartidas de la simulación: orden fijo, distancias y pequeñas piezas de grupos.

- Tamaño: 178 líneas, 16 funciones públicas, 0 locales.

- `Ayudas.ordenadas(t)` (l.12) — Claves de `t` en orden fijo: primero los números y después los textos, cada grupo de menor a mayor.
- `Ayudas.hipotenusa(dx, dy)` (l.35) — Largo de (dx, dy). Con multiplicación y no con `^ 2`: LuaJIT calcula `x ^ 2` a veces como `x * x` (código compilado) y a veces con `pow`…
- `Ayudas.distancia(a, b)` (l.42) — Distancia entre dos cosas con `x` e `y`.
- `Ayudas.lista(tabla)` (l.47) — Valores de `tabla` en el orden de sus claves (`ordenadas`).
- `Ayudas.tropasVacias()` (l.56) — Conteo de tropas a cero: { soldados, tanques, lanzacohetes }.
- `Ayudas.esCiudad(sitio)` (l.61) — ¿Es una ciudad? (las instalaciones tienen `tipo`).
- `Ayudas.ponerAlMando(e, g, l)` (l.66) — Pone al líder `l` al mando del grupo `g` en el estado `e`.
- `Ayudas.cargaDe(g)` (l.75) — Carga de un grupo (0 si no lleva): los grupos de entrega llevan su carga en una tabla, los recolectores en un número.
- `Ayudas.anotar(self, g, campo)` (l.80) — Suma una victoria o una derrota (`campo`) al líder del grupo, si lo tiene.
- `Ayudas.nacionesBando(self, b, lado)` (l.98) — Naciones de un bando (las de sus grupos y la del sitio), como conjunto.
- `Ayudas.sanosBando(self, b, lado, conSitio)` (l.114) — Sanos de un bando por tipo de tropa: { soldados, tanques, lanzacohetes } de sus grupos (y del sitio, si `conSitio`).
- `Ayudas.claveGuerra(a, b)` (l.130)
- `Ayudas.cambiarRelacion(self, a, b, cuanto)` (l.137)
- `Ayudas.grupoEnCamino(self, nid, mision, tipo)` (l.147) — ¿Tiene `nid` algún grupo con esa misión (y esa obra) en camino?
- `Ayudas.prepararCombate(self, g)` (l.158) — Da a `g` lo que necesita para combatir si aún no lo tiene (vida, umbral de retirada, heridos). `self` es la simulación.
- `Ayudas.claveCelda(cx, cy)` (l.170) — Clave numérica única de la celda (cx, cy), para mapas celda -> dato.

## mundo/simulacion/batallas.lua

Batallas de campo: bandos, un día simulado (F8 con munición), bajas y el resultado de la escena 3D.

- Tamaño: 957 líneas, 26 funciones públicas, 14 locales.
- Usa: mundo/simulacion/ayudas

- `Batallas:herirGrupo(g, dano)` (l.139) — Daño a un grupo: sus soldados que caen mueren o quedan heridos (F11b) y sus vehículos quedan averiados con daño 1, y viajan con él.
- `Batallas:herirSitio(s, dano)` (l.152) — Daño a la guarnición de un sitio: igual que a un grupo, pero sus heridos y averiados van al taller de su ciudad.
- `Batallas:unirBatalla(b, g, lado)` (l.171) — Mete a `g` en el bando `lado` de la batalla `b`.
- `Batallas:crearBatalla(lugar, x, y, atacantes, defensores, sitioId)` (l.182) — Empieza una batalla en `lugar` ({ tipo, id }) entre los grupos `atacantes` y `defensores` (y el sitio `sitioId`, que defiende con su guarnición).
- `Batallas:gruposBando(b, lado)` (l.211) — Grupos de un bando que siguen en la batalla, en orden de id (la lista se limpia de los que ya no están).
- `Batallas:sitioBando(b)` (l.228) — Sitio que defiende el bando defensor, si sigue en pie y es de la misma nación que al empezar; nil si no.
- `Batallas:ladoDe(b, nid)` (l.238) — Bando en el que pelea `nid` en la batalla `b` ('atacante', 'defensor') o nil.
- `Batallas:batallaEn(tipo, id)` (l.248) — Batalla abierta en un lugar ('sitio', 'mina') con ese id, o nil.
- `Batallas:ventajaBando(b, lado)` (l.344) — Ventaja de un bando (F8): +`ventajaDefensa` si pelea en la tierra de la nación que lo encabeza (la del sitio o la de su primer grupo) y, si defiende…
- `Batallas:nombreBatalla(b)` (l.363) — Nombre de una batalla para las noticias.
- `Batallas:repartirCarga(b, g, lado)` (l.379) — La carga de `g`, que pierde una batalla, pasa al bando `lado`: cada grupo sano se lleva lo que le quepa (en orden de id) y, en una mina, el resto…
- `Batallas:caerEnBatalla(b, g, ganador)` (l.406) — Un grupo cae en la batalla (nada sano): su carga va al otro bando, sus soldados heridos mueren (el vencedor no los recoge), su munición se pierde y…
- `Batallas:retirarDeBatalla(b, g, ganador)` (l.435) — Un grupo se retira de la batalla: pierde la carga (va al otro bando) y vuelve a casa con los vivos, los heridos y su munición.
- `Batallas:limpiarBatalla(b)` (l.443) — Suelta de la batalla a los grupos que ya no tienen contra quién pelear (se firmó la paz o un alto el fuego): siguen con lo suyo.
- `Batallas:danarSitio(b, s, bajas, atacante, conGrupos)` (l.465) — Un día de daño a un sitio que defiende: una ciudad pierde tropas (F11b, al taller los heridos y averiados) y vida (F3); una instalación, tropas y…
- `Batallas:golpeConMunicion(grupos, sitio)` (l.514) — Golpe de un bando hoy con su munición (F6), y la gasta: la de cada grupo y, en el defensor, la del polvorín de la ciudad del sitio.
- `Batallas:anotarGasto(gastado)` (l.538) — Anota en las medidas la munición gastada.
- `Batallas:diaBatalla(b, azar)` (l.548) — Un día de batalla sin ver (F8, con munición): cada bando golpea con la munición que tiene; las bajas al otro bando se reparten en proporción a la…
- `Batallas:terminarSiToca(b)` (l.610) — Termina la batalla si un bando no tiene nada sano o se ha ido entero. Devuelve true si terminó.
- `Batallas:cerrarBatalla(b, ganador)` (l.632) — Cierra la batalla con su ganador ('atacante', 'defensor' o nil si no queda nadie).
- `Batallas:resolverBatallas(azar)` (l.669) — Pelea las batallas del día, en orden de id: las congeladas (un jugador dentro de la escena 3D) esperan a `resolverBatalla`, hasta `diasEscenaMax`.
- `Batallas:entrarBatalla(nid, bid)` (l.689) — La nación `nid`, que pelea en la batalla, la juega en 3D: la simulación la congela hasta que llegue `resolverBatalla`.
- `Batallas:noDefender(nid, bid)` (l.701) — La nación `nid` no defiende en 3D: la batalla sigue sola con F8. Solo se apunta, para que la vista no vuelva a preguntar.
- `Batallas:aplicarResultado(quienes, sitio, r)` (l.782) — Aplica a los `quienes` de un bando (sus grupos y, al final, el sitio) el resultado `r` de la escena. Devuelve lo aplicado.
- `Batallas:resolverBatalla(c)` (l.865) — Resultado de la escena 3D (3.7, 3.9): ver el contrato en la cabecera.
- `Batallas.instalar(clase)` (l.945) — Cuelga de la clase Simulacion las funciones de batalla y `Simulacion.batalla` (las reglas).

## mundo/simulacion/consultas.lua

Consultas para la vista: lo que la interfaz lee de las batallas y del estado, sin cambiarlo.

- Tamaño: 401 líneas, 12 funciones públicas, 2 locales.
- Usa: mundo/simulacion/ayudas

- `Consultas:estadoBatalla(bid)` (l.89) — Estado de una batalla para la escena 3D o el panel: { id, lugar = { tipo, id }, nombre, x, y, inicio, dias, enEscena, atacante = bando, defensor =…
- `Consultas:batallasEnCurso(nid)` (l.113) — Batallas en curso, en orden de id; con `nid`, solo aquellas en las que pelea: { id, lugar, nombre, x, y, dias, enEscena, lado (el de `nid`),…
- `Consultas:choques()` (l.151) — Choques en campo abierto, para la vista de antes: { a, b (ids de grupo, el primero de cada bando), x, y, jugador, batalla }, en orden de batalla.
- `Consultas:recolectoresMina(id)` (l.170) — Recolectores de una mina ahora, por nación: { { nacion, trabajo, grupos = { gid, ...
- `Consultas:mina(id)` (l.203) — Una mina (yacimiento) para la vista: { id, tipo, x, y, riqueza, dueno (nación de su celda o nil), queda, reserva, agotadaHasta (0 si abierta),…
- `Consultas:yacimientosEn(x0, y0, x1, y1)` (l.242) — Yacimientos registrados dentro del rectángulo (x0, y0)-(x1, y1), en orden fijo, con lo mismo que `mina` (id, tipo, x, y, riqueza, dueno, queda,…
- `Consultas:recolectores(nid)` (l.258) — Grupos de recolección (con `nid`, solo los suyos), en orden de id: { grupo, nacion, yacimiento, recurso, fase ('ida', 'recolectando' o 'vuelta'), x,…
- `Consultas:banderas(nid)` (l.289) — Banderas de una nación (o de todas, sin `nid`), en orden fijo: { id, nacion, x, y, vida (0 a 100), enObra, progreso (0 a 1), atacada (hoy o ayer),…
- `Consultas:almacenDe(nid)` (l.314) — Almacén, bóveda y afuera de una nación: { metal, petroleo, dinero (lo guardado), afuera = { metal, petroleo, dinero }, almacen (tope del metal y del…
- `Consultas:colaFabrica(cid)` (l.335) — Fábricas de una ciudad para el Arsenal: { lineas (órdenes de unidades que avanzan a la vez), unidades = { { id, tropa, cantidad (lo que falta),…
- `Consultas:sinDueno(x, y)` (l.369) — ¿Es (x, y) tierra sin dueño?
- `Consultas.instalar(clase)` (l.390) — Cuelga de la clase Simulacion las funciones y datos de este módulo.

## mundo/simulacion/diplomacia.lua

Diplomacia y guerra: tensión, ataques de los presidentes, negociaciones, altos el fuego y paz.

- Tamaño: 521 líneas, 13 funciones públicas, 1 locales.
- Usa: mundo/simulacion/ayudas

- `Diplomacia:frente(a, b)` (l.21)
- `Diplomacia:minasDe(nid)` (l.36) — Minas de una nación: las que conoce (a menos de `alcanceMeta` de su capital) en su territorio, en orden fijo. Se calcula una vez al día.
- `Diplomacia:recursosEnDisputa(a, b)` (l.59) — Lo que `a` codicia de `b`: la riqueza de las minas de `b` (en su territorio) a su alcance (a menos de `alcanceCodicia` de una ciudad o un campamento…
- `Diplomacia:diplomacia(a, b, azar)` (l.105)
- `Diplomacia:objetivos(nid, enemiga)` (l.178) — Sitios enemigos a los que atacar por tierra, del que más apetece al que menos, cada uno con el sitio propio más cercano: { { blanco, sitio, d } }.
- `Diplomacia:objetivo(nid, enemiga)` (l.214) — El sitio enemigo que más apetece y el propio más cercano (ver `objetivos`).
- `Diplomacia:refuerzos(nid)` (l.221) — El atacado manda refuerzos por tierra a sus instalaciones atacadas (por `ejecutar`, como toda decisión NPC).
- `Diplomacia:ofensiva(nid, enemiga, azar)` (l.286) — Acciones de un bando en un día de tensión: en el mapa no hay ataques a distancia, así que solo manda ejércitos por tierra, a las minas con…
- `Diplomacia:altoElFuego(g, dias)` (l.348)
- `Diplomacia:firmarPaz(g, concesion)` (l.361)
- `Diplomacia:negociar(g, azar)` (l.377) — Conversaciones entre presidentes: según los daños y su carácter.
- `Diplomacia:guerra(g, azar)` (l.440)
- `Diplomacia.instalar(clase)` (l.510) — Cuelga de la clase Simulacion las funciones y datos de este módulo.

## mundo/simulacion/exploracion.lua

Exploradores e informes: lo único que una nación sabe del poder de sus enemigos.

- Tamaño: 373 líneas, 13 funciones públicas, 3 locales.
- Usa: mundo/simulacion/ayudas

- `Exploracion:explorandoA(nid, objetivo)` (l.121) — ¿Tiene `nid` un explorador en camino hacia `objetivo`? (sin orden: solo sí o no)
- `Exploracion:explorar(nid, desdeId, objetivo)` (l.134) — Manda un explorador de `nid` desde su sitio `desdeId` hacia `objetivo` (id de un sitio ajeno o de un grupo ajeno). Paga al salir.
- `Exploracion:llegadaExploradores()` (l.174) — Llegan los exploradores de hoy (en orden de id): cada uno deja su informe con lo que hay ahora en su objetivo.
- `Exploracion:olvidarInformes()` (l.194) — Borra los informes que ya no sirven: de grupos disueltos y de sitios que cayeron o que ahora son de quien los tenía. Una vez al día.
- `Exploracion:informe(nid, objetivo)` (l.217) — El informe de `nid` sobre `objetivo` (id de sitio o de grupo), o nil si no tiene. Es la tabla guardada: la vista la lee y no la cambia.
- `Exploracion:conoce(nid, objetivo)` (l.234) — ¿Conoce `nid` el poder de `objetivo`? Lo propio, siempre; lo ajeno, si tiene un informe (de cualquier día).
- `Exploracion:exploradoresEnCamino(nid)` (l.244) — Exploradores de `nid` en camino, en orden de id: { { id, objetivo, desde, salioDia, llegaDia } }.
- `Exploracion:informeVigente(nid, objetivo)` (l.266) — Informe de `nid` sobre `objetivo` que aún le sirve para decidir (no más viejo que su caducidad), o nil. No manda a nadie.
- `Exploracion:informeFresco(nid, objetivo)` (l.278) — Como `informeVigente`, pero sin él manda un explorador (con la acción `explorar`, desde su sitio más cercano) si no va ya uno.
- `Exploracion.fuerzaInforme(inf)` (l.302) — Fuerza de un informe con la misma cuenta que `fuerzaDe` (tropas y defensas fijas): la de aquel día.
- `Exploracion.defensaInforme(inf)` (l.316) — Poder con el que defiende un sitio según el informe: sus tropas, más las baterías de una ciudad (con el peso que tienen en combate) y × el efecto de…
- `Exploracion:fuerzaConocida(a, b)` (l.331) — Fuerza de la nación `b` como la conoce `a`, para decidir una guerra: la tecnología (sale en las noticias) y lo que dicen sus informes de las…
- `Exploracion.instalar(clase)` (l.364) — Cuelga de la clase Simulacion las funciones y `Simulacion.exploracion` (las reglas).

## mundo/simulacion/guardado.lua

Guardar y cargar la partida: el estado vivo como texto, y las migraciones de versión.

- Tamaño: 389 líneas, 3 funciones públicas, 2 locales.
- Usa: mundo/simulacion/ayudas

- `Guardado.guardar(self)` (l.51) — Texto con todo el estado vivo (para guardar la partida o enviarla a un servidor).
- `Guardado.cargar(texto, opciones)` (l.357) — Simulación con el estado del texto `texto` (de `guardar`), migrado si es de una versión anterior; `nil` y el motivo si no se entiende o es de otra…
- `Guardado.instalar(clase)` (l.381) — Cuelga `guardar`, `cargar` y `serializar` de la clase Simulacion.

## mundo/simulacion/lideres.lua

Líderes y generales: presidente y generales de cada nación, quién manda cada grupo y la ficha del ejército.

- Tamaño: 326 líneas, 15 funciones públicas, 4 locales.
- Usa: mundo/ruido, mundo/simulacion/ayudas, mundo/simulacion/nombres

- `Lideres:nombrarPresidente(n)` (l.65) — Da a la nación su presidente como líder (si no lo tiene ya).
- `Lideres:nombrarGeneral(nid)` (l.89) — Nombra un general nuevo en la nación `nid`, sin coste (fase 1). Su carácter hereda en parte el del presidente que lo nombra.
- `Lideres:liberarLideres()` (l.128) — Deja libres a los líderes cuyo grupo ya no está (al final de cada día).
- `Lideres:liderLibre(nid)` (l.137) — Primer líder libre de la nación: el presidente y luego los generales por orden de nombramiento. Nil si todos están en campaña.
- `Lideres:liderParaSalir(nid, liderId)` (l.155) — Líder que mandará un grupo de ataque de `nid`: `liderId` si lo pide quien manda (debe ser suyo y estar libre) o el primero libre; si no hay ninguno,…
- `Lideres:lider(id)` (l.171) — Líder con ese id, o nil.
- `Lideres:liderDe(g)` (l.176) — Líder que manda el grupo `g`, o nil (convoyes de obra, entregas, refuerzos).
- `Lideres.esEjercito(g)` (l.181) — ¿Se dibuja como ejército (estandarte con líder y poder) o como convoy?
- `Lideres:lideresDe(nid)` (l.187) — Líderes de una nación: el presidente primero y luego los generales por orden de nombramiento.
- `Lideres.rangoLider(l)` (l.201) — Rango de un líder: nombre largo y abreviado ('General', 'Gral.').
- `Lideres.etiquetaLider(l)` (l.213) — Nombre con el rango abreviado, para la etiqueta: 'Gral. Mira Oriel'.
- `Lideres.caracterLider(l)` (l.219) — Carácter a grandes rasgos: 'agresivo y prudente', 'temerario', 'equilibrado'...
- `Lideres.composicion(g)` (l.239) — Lo que lleva un grupo: sanos y heridos de cada tropa.
- `Lideres:fichaGrupo(gid, mira)` (l.253) — Todo lo que muestra la ficha de un grupo, visto por la nación `mira` (nil: observador, lo ve todo).
- `Lideres.instalar(clase)` (l.317) — Cuelga de la clase Simulacion las funciones de líderes y `Simulacion.reglasLideres`.

## mundo/simulacion/municion.lua

Munición: polvorín de cada ciudad, dotación de los grupos, convoyes de abastecimiento y avisos.

- Tamaño: 392 líneas, 19 funciones públicas, 0 locales.

- `Municion:polvorinDe(s)` (l.45) — Polvorín (tabla guardada) de la ciudad que abastece al sitio `sid` (o al sitio `s`), creado si no existía; nil si su nación no tiene ciudades.
- `Municion:polvorin(sid)` (l.56) — Polvorín del sitio `sid` para la vista: { balas, obuses, misiles } (una base o un campamento, el de su ciudad), o nil.
- `Municion.dotacion(unidades, dias)` (l.68) — Dotación de `dias` días de batalla para `unidades` ({ soldados, tanques, lanzacohetes }) (F5).
- `Municion:dotar(g, desde, pedido)` (l.79) — Da a `g` la munición que pide (`pedido`, ver la cabecera) del polvorín del sitio `desde`, sin pasar de lo que hay.
- `Municion:devolverMunicion(g, sitio)` (l.99) — La munición de `g` vuelve al polvorín de la ciudad de `sitio`.
- `Municion:perderMunicion(g)` (l.115) — La munición de `g` se pierde (el grupo cayó entero).
- `Municion.partes(q, m)` (l.126) — Parte que puede disparar hoy de cada tropa de `q` (un grupo o una guarnición) con la munición `m` (F6): min(1, munición / (unidades × porDia)).
- `Municion.gastarDia(q, m)` (l.138) — Gasta la munición de un día de batalla de `q` (F6): lo que le toque a cada tropa, sin pasar de lo que hay en `m`. Devuelve lo gastado.
- `Municion.diasDe(g)` (l.155) — Días de batalla que le quedan a `g` de cada munición (math.huge sin unidades de esa tropa).
- `Municion:municionGrupo(gid)` (l.166) — Munición de un grupo para la vista (ver la cabecera), o nil.
- `Municion:convoyHacia(nid, gid)` (l.183) — ¿Va ya un convoy de munición de `nid` hacia el grupo `gid`?
- `Municion:abastecer(nid, desdeId, gid, balas, obuses, misiles)` (l.194) — Manda munición del polvorín de la ciudad `desdeId` al grupo `gid` (ver la cabecera). Devuelve el id del convoy, o false y el motivo.
- `Municion:llegadaAbasto(convoy)` (l.238) — Llega un convoy de munición: se la da a su grupo si sigue en pie y es suyo; si no, vuelve con ella a su ciudad.
- `Municion:avisosMunicion(nid)` (l.255) — Grupos de `nid` en batalla con menos de `umbralAbasto` días de alguna munición, en orden de id (ver la cabecera).
- `Municion:avisarMunicion()` (l.281) — Noticia al jugador, una vez por grupo, cuando uno suyo en batalla baja de `umbralAbasto` días de alguna munición (decisión del dueño: los convoyes…
- `Municion:planearAbastos(n)` (l.311) — El presidente NPC abastece a sus grupos en batalla con menos de `umbralAbasto` días de alguna munición: les manda `dotacion.atacar` días de lo que…
- `Municion:alcanzaMunicion(s, unidades, dias)` (l.338) — ¿Tiene el polvorín del sitio `s` al menos `dias` días de batalla para esas unidades? (la IA no manda grupos sin dotación).
- `Municion.sumar(lista)` (l.350) — Suma de la munición de una lista de polvorines o grupos, por tipo.
- `Municion.instalar(clase)` (l.377) — Cuelga de la clase Simulacion las funciones de munición.

## mundo/simulacion/nombres.lua

Nombres inventados para los presidentes y generales de cada nación.

- Tamaño: 63 líneas, 0 funciones públicas, 0 locales.

## mundo/simulacion/produccion.lua

Producción, inventario, sueldos y dinero del trabajo: la economía cerrada (diseno/economia.md).

- Tamaño: 831 líneas, 27 funciones públicas, 5 locales.
- Usa: mundo/simulacion/ayudas

- `Produccion.normalizar(tropa)` (l.138) — Nombre canónico de lo que se produce ('soldado' -> 'soldados'...).
- `Produccion.esMunicion(tropa)` (l.143) — ¿Es munición (y no una unidad)?
- `Produccion:ciudadDeSitio(nid, s)` (l.175) — Ciudad de `nid` a la que pertenece el sitio `s` (una ciudad suya, o la suya más cercana a él); sin sitio, su capital o su primera ciudad.
- `Produccion:ciudadDeGrupo(g)` (l.194) — Ciudad a la que pertenece un grupo: la de su sitio de origen (o de salida).
- `Produccion:inventario(nid)` (l.219) — Inventario de la nación `nid`: `{ total = inventario, ciudades = { [cid] = inventario } }` (ver `inventarioVacio`).
- `Produccion:inventarioCiudad(cid)` (l.301) — Inventario de una ciudad (ver `inventario`).
- `Produccion:basesDeCiudad(c)` (l.310) — Bases terminadas que abastece la ciudad `c` (su ciudad propia más cercana).
- `Produccion:topeCiudad(c, tropa)` (l.321) — Tope de `tropa` de la ciudad `c` (F3).
- `Produccion.enInstruccion(c)` (l.331) — Soldados en instrucción de una ciudad (los de sus órdenes de fábrica).
- `Produccion.maximoSoldados(c, inv)` (l.343) — Soldados que la ciudad aún puede encargar sin bajar de sus civiles mínimos (F1b); `inv` es su inventario.
- `Produccion.costeDe(tropa, cantidad)` (l.351) — Coste de `cantidad` de `tropa` (unidades, o lotes de munición).
- `Produccion.diasDe(tropa, cantidad)` (l.362) — Días que tarda una orden sola en su línea (F2), o los de un lote (F4).
- `Produccion:puedeProducir(nid, cid, tropa, cantidad)` (l.375) — ¿Puede `nid` encargar `cantidad` de `tropa` en su ciudad `cid`? Devuelve true, el coste ({ dinero, metal, petroleo }) y los días, o false y el…
- `Produccion:maximoProducible(nid, cid, tropa)` (l.419) — Lo más que `nid` puede encargar hoy de `tropa` en `cid` (0 si nada): lo que pasa `puedeProducir`, sin mirar reservas.
- `Produccion:producir(nid, cid, tropa, cantidad)` (l.446) — Encarga `cantidad` de `tropa` en la ciudad `cid` (ver la cabecera). Devuelve el id de la orden, o false y el motivo.
- `Produccion:cancelarProduccion(nid, cid, ordenId)` (l.486) — Cancela la orden `ordenId` de la ciudad `cid`: devuelve `devolucion` del coste de lo que aún no salió (lo que no quepa, afuera).
- `Produccion:colocarLanzacohetes(s, cantidad)` (l.513) — Pone `cantidad` lanzacohetes en el sitio `s`: en sus plataformas hasta su tope y lo que no cabe en el parque de su ciudad (nunca se desguazan).
- `Produccion:entregarUnidades(c, tropa, cantidad)` (l.528) — Lo terminado entra en la ciudad: soldados y tanques a su guarnición, lanzacohetes a sus plataformas o a su parque.
- `Produccion:avanzarFabrica(c)` (l.538) — Un día de las fábricas de una ciudad (ver la cabecera).
- `Produccion:medir(clave, valor, nid)` (l.587) — Suma `valor` a la medida `clave` (y a `clave|nid` si se da la nación) en `self.medidas`, una tabla que no es estado ni se guarda: solo existe si la…
- `Produccion.trabajoCiudad(n, c, soldados)` (l.604) — Dinero del trabajo de una ciudad (F2b), antes de repartir: trabajadores × base × (1 + tecnología) × hambre × f(vida).
- `Produccion.dineroDelTrabajo(produccion)` (l.615) — Dinero que entra al tesoro por `produccion` de trabajo (F2b).
- `Produccion:licenciar(c, parte)` (l.622) — Licencia `parte` de la guarnición de la ciudad `c` (F8): vuelven a ser civiles (siguen en la población). Devuelve cuántos.
- `Produccion:pagarSueldos(n, inv)` (l.632) — Sueldos del día (F7) de todo lo que tiene la nación salvo lo que está en fábrica.
- `Produccion:cederCiudad(c, nid)` (l.659) — La nación dueña de `c` se la cede a `nid` (una paz con concesión).
- `Produccion:planearProduccion(n)` (l.725) — La política de producción del presidente NPC (3.12), con `producir`: primero munición hasta `reservaMunicion` días de su ejército sano (contando la…
- `Produccion.instalar(clase)` (l.812) — Cuelga de la clase Simulacion las funciones y `Simulacion.produccion` (las reglas).

## mundo/simulacion/recoleccion.lua

Recolección en yacimientos: mandar grupos a las minas, recolectar cada día y entregar.

- Tamaño: 360 líneas, 13 funciones públicas, 1 locales.
- Usa: mundo/simulacion/ayudas

- `Recoleccion.reservaMina(d)` (l.52) — Reserva de un yacimiento (F5): riqueza × reservaBase[tipo].
- `Recoleccion:estadoMina(d)` (l.57) — Lo que queda en una mina, hasta qué día está cerrada (0 si abierta) y su reserva.
- `Recoleccion:minaCerrada(d)` (l.67) — ¿Está cerrada (agotada y enfriándose) la mina?
- `Recoleccion:devolverAMina(d, cantidad)` (l.73) — Vuelve a la mina lo que no se llevó nadie (sin pasar de su reserva).
- `Recoleccion.trabajo(g)` (l.83) — Trabajo de un grupo (F1): lo sano que lleva.
- `Recoleccion:ritmoRecoleccion(g, d)` (l.89) — Ritmo de recolección de un grupo en el yacimiento `d` (F1).
- `Recoleccion:recolectoresEn(id)` (l.103) — Grupos que recolectan ahora en la mina `id` (en orden de id).
- `Recoleccion:recolectar(nid, desdeId, yacimientoId, soldados, tanques, lanzacohetes, municion)` (l.119) — Manda un grupo a recolectar al yacimiento `yacimientoId` desde una ciudad o un campamento propio (3.1). La misma orden para un NPC y para un jugador.
- `Recoleccion.capacidad(g)` (l.179) — Capacidad de carga de un grupo (F2): lo sano que lleva.
- `Recoleccion:entregarCarga(g, casa)` (l.187) — Entrega la carga de un grupo que llega a `casa` (3.1.8): metal y petróleo al almacén, oro como dinero (× precioOro), comida al granero de la ciudad…
- `Recoleccion:cerrarMina(d, grupos)` (l.211) — Cierra una mina agotada (F6) y manda a casa a los que estaban en ella.
- `Recoleccion:recolectarDia()` (l.238) — Un día de recolección, después de mover a todos y de las batallas: cada grupo que está en su mina recolecta F3 (repartido con F4 si no llega para…
- `Recoleccion.instalar(clase)` (l.350) — Cuelga de la clase Simulacion las funciones de recolección y sus reglas (`Simulacion.recoleccion`).

## mundo/simulacion/recoleccionIA.lua

IA de recolección de los NPC: a qué minas mandan grupos, cuándo los retiran y cómo reservan lo que gastan.

- Tamaño: 445 líneas, 7 funciones públicas, 1 locales.
- Usa: mundo/simulacion/ayudas

- `RecoleccionIA:libresEn(n, s, fuera, enGuerra)` (l.27) — Soldados y tanques que un NPC puede sacar hoy de un puesto sin bajar de su guarnición mínima (F9 de ejercitos-en-el-mapa.md: `0,2 + 0,4 ×…
- `RecoleccionIA:faltanRecursos(n, enCamino)` (l.47) — Lo que le falta a una nación de cada recurso para su reserva objetivo (F9): consumo diario medio × `diasReserva`, sin bajar de lo que ya pide (la…
- `RecoleccionIA:poderEstimado(nid, g, explorar)` (l.78) — Poder de un ejército ajeno `g` para `nid`: el de su informe vigente o, sin él, la estimación a ciegas (`exploracion.ciegoEjercito`, por lo alto).
- `RecoleccionIA:planearRecoleccion(n)` (l.111) — El presidente manda a recolectar (3.10): por cada recurso que le falta, a la mina de más valor (F10) de las que conoce, los soldados justos para…
- `RecoleccionIA:atacarRecolectores(n, enemiga)` (l.245) — Ataque a recolectores (3.10, dentro de `ofensiva`): de las minas con recolectores de `enemiga` a menos de `alcanceCodicia` de un sitio propio (lo…
- `RecoleccionIA:defenderLoSuyo(n)` (l.361) — El presidente defiende lo suyo (3.10): retira a sus recolectores de una mina a la que llega en un día o menos un ejército que no pueden aguantar…
- `RecoleccionIA.instalar(clase)` (l.434) — Cuelga de la clase Simulacion las funciones y datos de este módulo.

## mundo/simulacion/taller.lua

Taller y hospital de cada ciudad: heridos que se curan, vehículos averiados que se reparan pagando y remolques.

- Tamaño: 442 líneas, 15 funciones públicas, 7 locales.
- Usa: mundo/simulacion/ayudas

- `Taller.averiar(g, tropa, cantidad, dano)` (l.48) — `cantidad` vehículos de `tropa` de `g` quedan averiados con daño `dano`.
- `Taller:sumarCola(c, soldados, averias)` (l.96) — Suma heridos y averiados a la cola de una ciudad: `soldados` y las averías `averias` ({ tanques = { d, ... }, lanzacohetes = { d, ... } }).
- `Taller:recibirHeridos(g, casa)` (l.122) — Un grupo llega a `casa` (ciudad o base propia): sus lanzacohetes sanos vuelven a las plataformas de casa o, si no caben, al parque de su ciudad; sus…
- `Taller:ciudadTaller(g)` (l.140) — Ciudad a cuyo taller va lo de `g`: su ciudad de origen si sigue siendo suya (la de su base, si salió de una), o su capital.
- `Taller:remolcar(nid, x, y, ciudad, heridos, averias)` (l.152) — Manda al taller de `ciudad`, remolcados desde (x, y), `heridos` ({ soldados, tanques, lanzacohetes }) con sus `averias`: un convoy de regreso sin…
- `Taller.diasRecuperacion(c, tropa)` (l.212) — Días que tarda en vaciarse sola la cola de un tipo de una ciudad (0 si no hay cola de ese tipo).
- `Taller.precioRecuperacion(c, tropa, cantidad)` (l.227) — Lo que cuesta sacar ya `cantidad` unidades de un tipo (sin `cantidad`, toda su cola) del taller de una ciudad: dinero y metal.
- `Taller:devolverVehiculo(c, tipo)` (l.247) — Vuelve a la ciudad `c` un vehículo reparado de `tipo`.
- `Taller:acelerarRecuperacion(nid, cid, tropa, cantidad)` (l.275) — Paga para que vuelvan al momento `cantidad` unidades (sin `cantidad`, toda la cola) de un tipo del taller de una ciudad propia no sitiada: `precio`…
- `Taller:acelerarSiHaceFalta(n, c)` (l.320) — El presidente paga para acelerar la cola de una ciudad si está en guerra o la ciudad está en la frontera: lanzacohetes, tanques y soldados, solo lo…
- `Taller:repararDia(c, n, tipo)` (l.345) — Un día del taller de `c` para un tipo de vehículo (ver la cabecera).
- `Taller:recuperar()` (l.374) — Colas del día, en orden fijo: el presidente NPC decide si paga y después vuelve lo que toca.
- `Taller:huecoLanzacohetes(s)` (l.405) — Cuántos lanzacohetes más le caben a un sitio, contando los que tiene fuera o de camino.
- `Taller.enTaller(c)` (l.410) — ¿Tiene la ciudad algo en el taller?
- `Taller.instalar(clase)` (l.428) — Cuelga de la clase Simulacion las funciones del taller.

## mundo/simulacion/territorio.lua

Territorio por celdas cuadradas: dueños, bloques de los sitios, fronteras y trozos.

- Tamaño: 508 líneas, 22 funciones públicas, 4 locales.
- Usa: mundo/simulacion/ayudas

- `Territorio.celdaDe(x, y)` (l.28) — Celda (cx, cy) que contiene el punto (x, y).
- `Territorio.bloque(x, y, lado)` (l.34) — Bloque de `lado` x `lado` celdas centrado en (x, y): va del vértice de la rejilla más cercano `lado / 2` celdas a cada lado.
- `Territorio.bloqueDe(sitio)` (l.51) — Bloque de territorio de un sitio que lo da ya (cx0, cy0, cx1, cy1), o nil.
- `Territorio:mapaTerritorio()` (l.135) — Mapa celda -> nación, rehecho del estado si hace falta (al cargar).
- `Territorio:duenoCelda(cx, cy)` (l.176) — Nación dueña de la celda (cx, cy) (id), o nil si es tierra sin dueño.
- `Territorio:ponerCelda(cx, cy, nid)` (l.182) — Da la celda (cx, cy) a `nid` (o la deja sin dueño con nil). Devuelve true si cambió.
- `Territorio:territorioCambiado()` (l.233) — El territorio cambió: la vista lo vuelve a pintar (`self.cambios`, que la vista de antes mira; la nueva mira `e.versionTerritorio`).
- `Territorio:reclamarBloque(sitio)` (l.239) — `sitio` empieza a dar territorio: toma las celdas libres de su bloque (las de otra nación no se pisan). Devuelve cuántas tomó.
- `Territorio:cubre(nid, cx, cy)` (l.260) — ¿Cubre la celda (cx, cy) el bloque de algún sitio vivo de `nid` (una ciudad o una instalación que ya da territorio)?
- `Territorio:soltarBloque(sitio, nid)` (l.288) — `sitio` dejó de dar territorio a `nid` (cayó, se abandonó o cambió de manos, y ya no está en el índice como suyo): las celdas de su bloque que eran…
- `Territorio:celdasEn(cx0, cy0, cx1, cy1)` (l.313) — Celdas con dueño en el rectángulo de celdas [cx0, cx1] x [cy0, cy1], en orden fijo (por fila y, en cada fila, de izquierda a derecha): { {cx, cy,…
- `Territorio:celdasDe(nid)` (l.340) — Celdas de una nación (cuántas).
- `Territorio:hayFrontera(a, b)` (l.352) — ¿Comparten a y b algún lado de celda (hacen frontera)?
- `Territorio:bloqueToca(nid, cx0, cy0, cx1, cy1)` (l.360) — ¿Toca el bloque [cx0, cx1] x [cy0, cy1] el territorio de `nid`? Tiene que tener una celda suya dentro o pegada por un lado.
- `Territorio:dueno(x, y)` (l.373) — Nación dueña del punto (x, y), o nil (tierra sin dueño): la de su celda.
- `Territorio:duenoDeposito(d)` (l.381) — Nación dueña de la celda de un yacimiento (id o nil). Las extracciones no dan territorio: una extracción necesita la tierra de una ciudad, una base,…
- `Territorio.alcance(_self, _c)` (l.386) — Medio lado del bloque de territorio de una ciudad (px).
- `Territorio.candidatos()` (l.392) — Compatibilidad con la vista de antes (`territorio.lua`): ya no hay candidatos; `duenoEntre` pregunta a la celda.
- `Territorio:duenoEntre(_candidatos, x, y)` (l.396)
- `Territorio:trozos(nid)` (l.404) — Trozos de territorio de una nación: sus celdas conectadas por un lado.
- `Territorio:tocaTrozo(nid, sitio)` (l.456) — ¿Toca el territorio de `nid` el trozo de territorio donde está `sitio`? Si la celda del sitio no es de su nación (una bandera en obra), cuenta solo…
- `Territorio.instalar(clase)` (l.499) — Cuelga de la clase Simulacion las funciones de territorio.

## mundo/terreno.lua

Terreno infinito: altura, tipo de suelo (bioma) y malla de cada trozo.

- Tamaño: 247 líneas, 7 funciones públicas, 2 locales.
- Usa: mundo/iso, mundo/ruido

- `Terreno.nuevo(semilla)` (l.26)
- `Terreno:base(x, y)` (l.45) — Altura natural (sin ciudades), en px de mundo. Negativa = bajo el mar.
- `Terreno:humedadEn(x, y)` (l.72) — Humedad en [-1, 1]: decide pradera seca, verde o bosque.
- `Terreno:altura(x, y)` (l.77) — Altura final: la natural, aplanada bajo las ciudades.
- `Terreno:color(h, humedad, x, y, pendiente)` (l.117) — Color del suelo según altura y humedad.
- `Terreno:bioma(x, y)` (l.152) — Bioma de un punto, para las plantas: 'agua', 'arena', 'seca', 'pradera', 'bosque', 'roca' o 'nieve'.
- `Terreno:mallaTrozo(tx, ty)` (l.178) — Malla de un trozo (tx, ty): vértices en coordenadas de vista, con el color del suelo y la luz de su ladera en cada vértice.

## mundo/territorio.lua

Territorio de cada nación, dibujado por sus celdas cuadradas.

- Tamaño: 230 líneas, 3 funciones públicas, 2 locales.
- Usa: mundo/iso, mundo/terreno

- `Territorio.grosor(zoom)` (l.34) — Grosor de las franjas según el zoom: de lejos más anchas (en px de mundo) para que se sigan leyendo.
- `Territorio.firma(sim, trozo)` (l.148) — Firma de las celdas que tocan al trozo (y sus vecinas): si no cambia, su malla sirve aunque haya cambiado el territorio en otra parte.
- `Territorio.mallaTrozo(sim, trozo, k)` (l.163) — Malla del territorio del trozo, o nil si todo es tierra de nadie. `k`: grosor de las franjas (`Territorio.grosor`).


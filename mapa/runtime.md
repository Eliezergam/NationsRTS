# Mapa de `runtime/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## runtime/camera.lua

Cámara de juego al estilo OpenRA para el runtime.

- Tamaño: 1037 líneas, 50 funciones públicas, 3 locales.
- Usa: runtime/projection

- `Camera.defaultKeys()` (l.103) — Teclas por defecto: flechas **y** WASD, las dos cosas a la vez.
- `Camera.levelStart(level, playerId)` (l.141) — Rectángulo de mundo que la cámara debería poder recorrer en un nivel.
- `Camera.levelBounds(level, margin)` (l.194)
- `Camera.new(opts)` (l.242)
- `Camera:setBounds(bounds)` (l.353) — Límites del mundo. `nil` los quita.
- `Camera:setProjection(map)` (l.376) — Cambia la vista (`map.projection`) sin mover el punto de mundo del centro.
- `Camera:setScreen(w, h)` (l.386) — Tamaño de la ventana. Lo llaman `resize` y `attach`.
- `Camera:view()` (l.401) — Lienzo lógico y su encaje en la ventana: `vistaW, vistaH, escala, margenX, margenY`. Sin `design` la vista es la ventana y la escala 1.
- `Camera:center()` (l.411) — Centro efectivo: el de la cámara más la sacudida.
- `Camera:toScreen(wx, wy)` (l.416) — Punto del mundo a punto de la pantalla (píxeles de la ventana).
- `Camera:toWorld(sx, sy)` (l.425) — Punto de la pantalla a punto del mundo. Inversa exacta de `toScreen`.
- `Camera:visibleSize()` (l.443) — Tamaño de lo que se ve de verdad, en unidades de la vista (antes del zoom).
- `Camera:visibleViewRect()` (l.452) — Rectángulo de la vista que se está viendo (en isométrico, no es el mundo).
- `Camera:visibleRect()` (l.461) — Rectángulo del mundo que se está viendo, para recortar el dibujo. En isométrico es la caja del rombo visible.
- `Camera:hudRect()` (l.468) — Rectángulo de la pantalla donde poner el HUD: el área de juego.
- `Camera:_applyBounds()` (l.478)
- `Camera:centerOn(wx, wy)` (l.500) — Centra la cámara en un punto del mundo.
- `Camera:move(dx, dy)` (l.509) — Desplaza la cámara en coordenadas de mundo.
- `Camera:panned()` (l.518) — Marca que el jugador ha movido la cámara a mano: el seguimiento se suspende hasta que se vuelva a llamar a `follow`.
- `Camera:setZoom(zoom)` (l.525)
- `Camera:zoomAt(factor, sx, sy)` (l.533) — Zoom manteniendo fijo el punto de mundo que hay bajo `(sx, sy)` de pantalla. Sin punto, hacia el centro de la vista.
- `Camera:follow(target, opts)` (l.575) — Sigue a un nodo de `runtime/world.lua`, a una función que devuelve `x, y`, o a nada (`nil`) para dejar de seguir.
- `Camera:followPoint()` (l.586) — Punto que hay que seguir ahora mismo, o `nil`.
- `Camera:_random()` (l.615) — Generador propio (Lehmer/MINSTD) en vez de `math.random`: la sacudida no puede depender del estado global del azar del juego ni alterarlo, y así las…
- `Camera:shake(intensity, seconds)` (l.622) — Sacude la cámara `seconds` segundos con una amplitud de `intensity` píxeles de mundo que decae linealmente hasta cero.
- `Camera:keyDown(direction)` (l.637) — ¿Está pulsada alguna de las teclas de una dirección?
- `Camera:keyVector()` (l.651) — Desplazamiento por teclado, en píxeles de mundo por segundo. Las teclas opuestas se anulan y la diagonal se normaliza.
- `Camera.edgeScrollVector(mx, my, w, h, opts)` (l.676) — Desplazamiento por borde de pantalla, en píxeles de mundo por segundo.
- `Camera:setEdgeBlocked(blocked)` (l.708) — Apaga el borde de pantalla mientras el puntero está sobre algo del HUD (el minimapa, un panel...), como hace OpenRA.
- `Camera:edgeVector()` (l.713)
- `Camera:inputVector()` (l.725) — Desplazamiento pedido por el jugador. Las teclas mandan sobre el borde: si hay una pulsada, el ratón cerca del borde no suma nada.
- `Camera:update(dt)` (l.735)
- `Camera:attach()` (l.795) — Empuja la transformación de la cámara. Lo que se dibuje hasta `detach()` está en coordenadas de mundo.
- `Camera:detach()` (l.818)
- `Camera:setPointer(x, y)` (l.840) — Posición del puntero. El borde de pantalla la usa en cada cuadro, así que el ratón parado en el borde sigue desplazando sin que llegue ningún evento.
- `Camera:mousepressed(x, y, button, isTouch)` (l.845)
- `Camera:mousemoved(x, y, _dx, _dy, isTouch)` (l.858)
- `Camera:mousereleased(x, y, button, isTouch)` (l.867)
- `Camera:_dragTo(x, y)` (l.881) — Arrastre: el mundo sigue al cursor 1:1. Un píxel de pantalla son `1 / (escala * zoom)` píxeles de mundo.
- `Camera:wheelmoved(_dx, dy)` (l.889)
- `Camera:isCameraKey(key)` (l.905) — ¿Es una tecla de la cámara? Se mira antes de marcarla para no consumir teclas que el juego necesita.
- `Camera:keypressed(key)` (l.919)
- `Camera:keyreleased(key)` (l.927)
- `Camera:focus(focused)` (l.937) — La ventana pierde el foco: se sueltan las teclas, que si no se quedarían pulsadas para siempre y la cámara se iría sola.
- `Camera:resize(w, h)` (l.945)
- `Camera:_touchPair()` (l.952)
- `Camera:_rebase()` (l.968) — Ancla del pellizco: el punto de **mundo** que hay bajo el punto medio de los dos dedos y la distancia entre ellos medida en mundo.
- `Camera:touchpressed(id, x, y)` (l.979)
- `Camera:touchmoved(id, x, y)` (l.991)
- `Camera:touchreleased(id, _x, _y)` (l.1022)

## runtime/class.lua

Clases sencillas para el editor y el runtime.

- Tamaño: 76 líneas, 2 funciones públicas, 2 locales.

- `Class.new(name, parent)` (l.41) — Crea una clase. `parent` es opcional.
- `Class.nameOf(value)` (l.63) — Nombre de la clase de una instancia (o de una clase).

## runtime/effects.lua

Efectos del nivel: humo, fuego y explosiones con partículas de LÖVE.

- Tamaño: 194 líneas, 8 funciones públicas, 3 locales.
- Usa: runtime/projection

- `Effects.new(map)` (l.48) — Sistema de efectos para un mapa (el nivel lo crea con `level.data`).
- `Effects:viewPoint(x, y, z)` (l.103) — Punto de la vista de algo a altura `z` sobre el terreno en `x, y`.
- `Effects:trail(x, y, z)` (l.114) — Una bocanada de estela (llamar cada cuadro mientras algo vuela).
- `Effects:puff(x, y, z)` (l.121) — Nube pequeña: algo que se apaga o se queda sin combustible.
- `Effects:explosion(x, y, z, size)` (l.127) — Explosión: fogonazo, bola de fuego, humo oscuro y restos.
- `Effects:update(dt)` (l.137)
- `Effects:active()` (l.151) — ¿Queda algo vivo que dibujar?
- `Effects:draw()` (l.161) — Dibuja con la transformación de mundo puesta (dentro de la cámara).

## runtime/example_main.lua

(sin comentario de cabecera)

- Tamaño: 21 líneas, 3 funciones públicas, 0 locales.
- Usa: runtime/level_loader, runtime/rts

- `love.load()` (l.3)
- `love.update(dt)` (l.9)
- `love.draw()` (l.14)

## runtime/images.lua

Carga de imágenes con el filtro adecuado a cada una.

- Tamaño: 49 líneas, 3 funciones públicas, 0 locales.

- `Images.configure(image)` (l.19) — Aplica el filtro según el tamaño. Devuelve la imagen.
- `Images.fromData(data)` (l.32) — Imagen a partir de un `ImageData`, con mipmaps si es grande.
- `Images.load(path)` (l.44) — Imagen desde una ruta del sistema de archivos de LÖVE. Lanza si no existe.

## runtime/level_loader.lua

(sin comentario de cabecera)

- Tamaño: 670 líneas, 4 funciones públicas, 6 locales.
- Usa: runtime/effects, runtime/images, runtime/nv/init, runtime/patrol, runtime/projection, runtime/terrain, runtime/transform, runtime/world

- `Loader.loadScript(path, options)` (l.12)
- `Loader.clearScriptCache()` (l.69)
- `Loader.loadData(map, options)` (l.167)
- `Loader.load(path, options)` (l.661)

## runtime/minimap.lua

Minimapa de runtime, al estilo del radar de OpenRA.

- Tamaño: 492 líneas, 23 funciones públicas, 1 locales.
- Usa: runtime/camera, runtime/projection, runtime/terrain_paint, runtime/terrain_relief

- `Minimap.fit(world, panelW, panelH, padding)` (l.72) — Encaja la caja del mundo en un rectángulo conservando la proporción. Devuelve la escala y el rectángulo del dibujo **en coordenadas del panel**.
- `Minimap.toPanel(fit, wx, wy)` (l.93) — Punto de mundo a punto del panel. Con `fit.projection` (un mapa en isométrico) el minimapa es el rombo de la vista y `fit.world` es la caja de la…
- `Minimap.toWorld(fit, px, py)` (l.99) — Punto del panel a punto de mundo. Inversa exacta de `toPanel`.
- `Minimap.new(level, camera, rect, opts)` (l.109)
- `Minimap:setRect(rect)` (l.126)
- `Minimap:layout()` (l.147) — El encaje de este minimapa, cacheado mientras no cambie de tamaño.
- `Minimap:invalidate()` (l.161) — Rehace el terreno y los puntos en el próximo cuadro.
- `Minimap:toScreenFromWorld(wx, wy)` (l.169)
- `Minimap:toWorldFromScreen(sx, sy)` (l.174)
- `Minimap:contains(sx, sy)` (l.179) — ¿Cae el punto dentro del minimapa?
- `Minimap:playerColor(object)` (l.187) — Color del jugador de un objeto, o el neutral.
- `Minimap:rebuildDots()` (l.204) — Los puntos de los objetos, en coordenadas del panel. Se rehacen cada `refresh` segundos, no en cada cuadro.
- `Minimap:update(dt)` (l.230)
- `Minimap:assetColor(path)` (l.243) — Color medio de una imagen, muestreando como mucho 16x16 píxeles. Se guarda por ruta: el mismo tile se repite miles de veces en una capa.
- `Minimap:rebuildTerrain()` (l.275) — Pinta el terreno en un `Canvas` del tamaño del dibujo. Una celda que mediría menos de un píxel se dibuja igualmente de un píxel, y las que caerían…
- `Minimap:draw()` (l.351)
- `Minimap:jumpTo(sx, sy)` (l.421) — Lleva la cámara al punto de mundo que corresponde a `(sx, sy)` de pantalla.
- `Minimap:mousepressed(sx, sy, button, isTouch)` (l.433)
- `Minimap:mousemoved(sx, sy, _dx, _dy, isTouch)` (l.447)
- `Minimap:mousereleased(_sx, _sy, button, isTouch)` (l.454)
- `Minimap:touchpressed(id, sx, sy)` (l.468)
- `Minimap:touchmoved(id, sx, sy)` (l.476)
- `Minimap:touchreleased(id)` (l.483)

## runtime/nv/agent.lua

Agente de navegación: mueve un objeto por la red de su tag.

- Tamaño: 1568 líneas, 36 funciones públicas, 7 locales.
- Usa: runtime/nv/local_avoidance, runtime/nv/path_follower, runtime/nv/steering, runtime/nv/util, runtime/nv/vector2

- `NavigationAgent.normalizeProps(props)` (l.241) — Sanea las propiedades (números finitos, defaults). `lateralAccel` y `maxDeviation` se derivan si faltan.
- `NavigationAgent:init(manager, target, props)` (l.297)
- `NavigationAgent:getCongestionState()` (l.386) — Estado de la detección de atascos: 'moving' | 'slow' | 'locallyBlocked' | 'stuck' | 'repathPending' (no sustituye a `getState`).
- `NavigationAgent:resolveSystem()` (l.391) — El sistema de su tag (nil si no hay red con ese nombre).
- `NavigationAgent:hasNetwork()` (l.397)
- `NavigationAgent:getState()` (l.401)
- `NavigationAgent:isMoving()` (l.405)
- `NavigationAgent:isPending()` (l.410) — ¿Espera una ruta del planificador sin moverse todavía?
- `NavigationAgent:getCurrentPath()` (l.414)
- `NavigationAgent:cancelPending()` (l.431) — Cancela la petición pendiente en el planificador, si la hay.
- `NavigationAgent:routeReady(route, err, request)` (l.445) — Llega (o falla) una ruta del planificador para la petición `request`.
- `NavigationAgent:request(x, y, opts)` (l.472) — Pide la ruta al sistema desde la posición actual. Devuelve true (ruta lista, o pendiente en el planificador: segundo valor 'pending') o false,…
- `NavigationAgent:setDestination(x, y, opts)` (l.526) — Fija el destino y calcula la ruta. Devuelve true, o false y el motivo (`getState()` pasa a 'noroute').
- `NavigationAgent:repath(reason)` (l.558) — Vuelve a pedir la ruta al destino actual. Sin ruta pasa a 'blocked'. Con planificador devuelve true y sigue la ruta vieja hasta que llegue la nueva.
- `NavigationAgent:retarget(x, y)` (l.584) — Cambia de puesto SIN cambiar de orden (el grupo reordena los puestos al llegar, ver `group.lua`): mismo grupo y misma prioridad de paso.
- `NavigationAgent:stop()` (l.601) — Para donde está (conserva la ruta para `getCurrentPath`).
- `NavigationAgent:clearDestination()` (l.614) — Para y olvida destino, ruta y campo.
- `NavigationAgent:awaitFlowField(x, y)` (l.625) — Fija el puesto y deja al agente 'pending' sin pedir ruta propia: el grupo traerá el flow field. Devuelve true, o false y el motivo.
- `NavigationAgent:followFlowField(field, x, y, opts)` (l.657) — Sigue `field` (un `FlowField` construido) hasta el puesto (x, y) (o el destino ya fijado).
- `NavigationAgent:planFromField(field, x, y, la, dest, goalDist)` (l.696) — Dirección deseada, curvatura, límite de velocidad y distancia restante según el flow field (ver la cabecera). Sin reservar memoria.
- `NavigationAgent:setFormationTarget(x, y)` (l.743) — Punto de formación al que tirar (nil lo desactiva).
- `NavigationAgent:queryNeighbours(x, y)` (l.754) — Vecinos para la esquiva: del índice espacial (el propio o el del manager) en el buffer reutilizado, o la lista `neighbours` de respaldo.
- `NavigationAgent:lastNeighbours()` (l.767) — Vecinos de la última consulta (para el dibujo de depuración).
- `NavigationAgent:sameGroup(other)` (l.786) — ¿Van en el mismo grupo (misma orden de `group.lua`)?
- `NavigationAgent:hasPriorityOver(other)` (l.793) — ¿Tiene prioridad de paso sobre `other`? `movementPriority` mayor; a igualdad, la orden más antigua; a igualdad, el agente más antiguo.
- `NavigationAgent:beginYield(to)` (l.806) — Empieza a ceder el paso a `to` (un agente con prioridad).
- `NavigationAgent:endYield()` (l.822) — Deja de ceder (o de tener prioridad). Recoloca el seguidor sobre la ruta (retrocedió a propósito) y vuelve a medir el atasco desde cero.
- `NavigationAgent:negotiateYield()` (l.863) — Paso de "ceder el paso" de la escalera de atascos: con vecinos de otro grupo que le cierran el paso, cede al que tenga prioridad; si la tiene él,…
- `NavigationAgent:yieldAway(neighbours, x, y, dt)` (l.911) — Mientras cede: dirección para apartarse de los que tienen prioridad (y de los compañeros de delante que también ceden), o 0, 0 si ya está fuera de…
- `NavigationAgent:updateCongestion(metric, source, goalDist, canRepath)` (l.1019) — Cierra la ventana de medida si toca y aplica la escalera (ver la cabecera).
- `NavigationAgent:update(dt)` (l.1139)
- `NavigationAgent:coast(dt)` (l.1388) — Entre dos decisiones (LOD 'reduced' y 'coarse', ver la cabecera): integra el movimiento de este cuadro con la última decisión.
- `NavigationAgent:arrive(x, y)` (l.1423) — Pasa a 'arrived' en (x, y): ahí vuelve después de hacer sitio.
- `NavigationAgent:makeWay(dt)` (l.1438) — Hacer sitio (llegado, v2 con atascos): un vecino en marcha se le echó encima (`nudged`), así que da un paso de esquiva v2 compartiendo el desvío,…
- `NavigationAgent:steerV1(neighbours, dirx, diry, target, dt, elapsed)` (l.1480) — v1: la esquiva es un vector que se suma a la dirección; giro acotado; la rapidez es la preferida, o 0 si el objetivo queda a 90° o más.
- `NavigationAgent:steerV2(neighbours, dirx, diry, target, dt, f, x, y, yielding, elapsed)` (l.1515) — v2: velocidad preferida → velocidad segura → giro acotado → rapidez segura a lo largo del rumbo real (ver la cabecera).

## runtime/nv/agent_spatial_hash.lua

Índice espacial dinámico SOLO para agentes móviles (AgentSpatialHash).

- Tamaño: 370 líneas, 9 funciones públicas, 10 locales.
- Usa: runtime/nv/util

- `AgentSpatialHash:init(cellSize)` (l.81)
- `AgentSpatialHash:cellOf(v)` (l.105)
- `AgentSpatialHash:update(agents)` (l.197) — Sincroniza el índice con la lista `agents`: refresca posiciones y radios, mueve a los que cambiaron de celda, añade a los nuevos y quita a los que…
- `AgentSpatialHash:queryRadius(x, y, r, out, exclude)` (l.257) — Agentes a `r` (más su propio radio) o menos del punto, sin `exclude`. `out` se vacía y se rellena; si no se da, se usa una lista interna.
- `AgentSpatialHash:contains(agent)` (l.308) — ¿Está indexado?
- `AgentSpatialHash:remove(agent)` (l.313) — Quita a un agente sin esperar al siguiente `update`.
- `AgentSpatialHash:clear()` (l.322)
- `AgentSpatialHash:stats()` (l.333) — Estadísticas del último cuadro completo (tabla reutilizada): `activeAgents`, `averageNeighbours`, `maxNeighbours`, `queriesPerFrame`,…
- `AgentSpatialHash:cells(out)` (l.348) — Celdas ocupadas como lista de `{cx=, cy=, n=}`, ordenadas por fila y columna (para el dibujo).

## runtime/nv/arc_length.lua

Parametrización por longitud de arco de una spline: tabla acumulada distancia → parámetro `t`, para que un agente pueda pedir "la posición a 340 px del principio" y avanzar a velocidad espacial uniforme.

- Tamaño: 121 líneas, 9 funciones públicas, 0 locales.
- Usa: runtime/nv/util, runtime/nv/vector2

- `ArcLength:init(spline, samplesPerSegment)` (l.27)
- `ArcLength:rebuild()` (l.34)
- `ArcLength:length()` (l.60)
- `ArcLength:sampleCount()` (l.64)
- `ArcLength:sample(i)` (l.69) — Muestra i: x, y, t, d.
- `ArcLength:indexAt(d)` (l.74) — Índice de la última muestra con d ≤ distancia (bisección).
- `ArcLength:tAtDistance(d)` (l.89) — Parámetro t de la spline a la distancia d (acotada a [0, longitud]).
- `ArcLength:positionAtDistance(d)` (l.108)
- `ArcLength:tangentAtDistance(d)` (l.114) — Tangente unitaria a la distancia d. Si la derivada es nula (spline de un punto) devuelve (0, 0).

## runtime/nv/astar.lua

A* sobre el grafo de navegación (nodos y segmentos, no muestras de spline).

- Tamaño: 203 líneas, 2 funciones públicas, 3 locales.
- Usa: runtime/nv/heap

- `AStar.find(graph, startId, goalId, opts)` (l.87)
- `AStar.stepsLength(steps)` (l.194) — Longitud en píxeles de una lista de pasos.

## runtime/nv/catmull_rom.lua

Spline Catmull-Rom (centrípeta por defecto) que pasa por todos sus puntos de control. Cada tramo entre dos puntos consecutivos se convierte al construirla en un polinomio cúbico `a·u³ + b·u² + c·u + d` con `u` en [0, 1], así que…

- Tamaño: 168 líneas, 7 funciones públicas, 1 locales.
- Usa: runtime/nv/util, runtime/nv/vector2

- `CatmullRom:init(points, opts)` (l.64) — `points`: lista de `{x=, y=}` (se copia; los repetidos consecutivos se descartan). `opts.closed` cierra la curva, `opts.alpha` es el exponente.
- `CatmullRom:segmentCount()` (l.106) — Número de tramos: puntos − 1 (abierta), puntos (cerrada), 0 con un punto.
- `CatmullRom:locate(t)` (l.111) — Tramo y parámetro local para un t global (acotado a [0, segmentCount]).
- `CatmullRom:position(t)` (l.130) — Posición en t.
- `CatmullRom:tangent(t)` (l.143) — Primera derivada respecto a t (dirección de avance, no unitaria).
- `CatmullRom:second(t)` (l.152) — Segunda derivada respecto a t.
- `CatmullRom:direction(t)` (l.161) — Tangente unitaria en t (0, 0 si la derivada es nula).

## runtime/nv/commands.lua

Órdenes de movimiento sobre NV, sin lógica de entrada: el juego (o `runtime/units.lua`) decide cuándo hay clic derecho; aquí solo se crea la orden y se entrega a la navegación de grupos.

- Tamaño: 86 líneas, 7 funciones públicas, 0 locales.
- Usa: runtime/nv/group, runtime/nv/util

- `MoveCommand:init(x, y)` (l.26)
- `MoveCommand:attach(request)` (l.37) — Rellena la orden con la petición de grupo ya resuelta.
- `MoveCommand:arrived(fraction)` (l.51)
- `CommandSystem:init(manager, group)` (l.61)
- `CommandSystem:moveUnits(agents, x, y, opts)` (l.70) — Orden de mover para `agents` (lista de `NavigationAgent`). `opts` (`spacing`, `arrivedFraction`, `strategy`, `formation`...) pasan a la navegación…
- `CommandSystem:update(dt)` (l.77)
- `CommandSystem:activeRequests()` (l.81)

## runtime/nv/curvature.lua

Curvatura de una spline paramétrica.

- Tamaño: 167 líneas, 5 funciones públicas, 0 locales.

- `Curvature.at(spline, t)` (l.22)
- `Curvature.profile(spline, arc, step, window)` (l.34) — Perfil a lo largo del arco: una entrada `{d=, k=}` cada `step` píxeles (más la del final). También `max` y `average` (media de las muestras).
- `Curvature.smoothProfile(profile, window)` (l.65) — Media móvil de `k` sobre una ventana de ±`window` px (por defecto `Curvature.defaults.window`).
- `Curvature.lookup(profile, d)` (l.116) — Curvatura interpolada en un perfil a la distancia d.
- `Curvature.maxIn(profile, d0, d1)` (l.145) — Curvatura máxima del perfil en la ventana [d0, d1].

## runtime/nv/debug.lua

Dibujo de depuración de NV con `love.graphics`, en coordenadas de mundo: vale dentro de `camera:attach()` y dentro del `translate/scale` del editor.

- Tamaño: 735 líneas, 3 funciones públicas, 7 locales.
- Usa: runtime/projection

- `NavigationDebug.anyActive(flags)` (l.133) — ¿Hay algún flag activo?
- `NavigationDebug.flags(value)` (l.146) — Todos los flags a `value` (false por defecto).
- `NavigationDebug.draw(manager, flags, extra)` (l.639)

## runtime/nv/flow_field.lua

Flow field: un campo de direcciones sobre una rejilla de celdas para que cientos de agentes con el MISMO destino compartan una sola decisión global en vez de una ruta cada uno.

- Tamaño: 799 líneas, 14 funciones públicas, 11 locales.
- Usa: runtime/nv/heap, runtime/nv/scheduler, runtime/nv/util

- `FlowField:init(system, route, opts)` (l.95)
- `FlowField:cellIndex(x, y)` (l.139) — Índice de la celda que contiene (x, y), o nil fuera de la caja.
- `FlowField:cellCenter(index)` (l.150) — Centro de la celda `index`.
- `FlowField:contains(x, y)` (l.157) — ¿El punto cae en una celda válida (navegable con camino al destino)?
- `FlowField:costAt(x, y)` (l.166) — Coste integrado de la celda bajo el punto (∞ fuera o inválida).
- `FlowField:speedLimitAt(x, y)` (l.175) — Límite de velocidad del tramo bajo el punto (0 = ninguno).
- `FlowField:build()` (l.555) — Construye (o reconstruye) el campo. Devuelve el propio campo.
- `FlowField:invalidate()` (l.614) — Marca el campo para reconstruir en el siguiente `ensure`.
- `FlowField:stale()` (l.621) — ¿Cambió la red bajo el corredor desde que se construyó? Un cambio lejos del campo no cuenta (y se anota la versión nueva para no volver a mirar).
- `FlowField:ensure()` (l.654) — Construye si hace falta (nuevo, invalidado o `stale`). Devuelve true si construyó.
- `FlowField:sample(x, y)` (l.666) — Dirección unitaria interpolada en (x, y): `dx, dy, valid, cost`. Sin celda válida alrededor: `0, 0, false, ∞`. No reserva memoria.
- `FlowField:nearestValid(x, y)` (l.706) — Dirección unitaria hacia el centro de la celda válida más cercana (en anillos de hasta `pullRings` celdas): `dx, dy, true`, o `0, 0, false`.
- `FlowField:cells()` (l.762) — Lista de celdas `{ col=, row=, x=, y=, dx=, dy=, cost=, cellCost=, valid= }` (reserva memoria: solo para pruebas y dibujo).
- `FlowField:stats()` (l.785) — Resumen: `cols`, `rows`, `cells`, `validCells`, `cellSize`, `maxCost`, `builds`, `buildMs`.

## runtime/nv/graph.lua

Grafo de navegación: nodos y segmentos con ids estables, reconstrucción incremental por segmento y un contador `version` que invalida cachés.

- Tamaño: 432 líneas, 20 funciones públicas, 1 locales.
- Usa: runtime/nv/node, runtime/nv/segment, runtime/nv/util, runtime/nv/vector2

- `NavigationGraph:init(opts)` (l.41)
- `NavigationGraph:touch()` (l.65)
- `NavigationGraph:heuristicScale()` (l.75) — Escala de la heurística de A*: `min(1, menor costFactor del grafo)`.
- `NavigationGraph:addNode(x, y, id, metadata)` (l.97) — Añade un nodo. `id` es opcional (al cargar); si se da, `nextNodeId` avanza por encima de él.
- `NavigationGraph:node(id)` (l.113)
- `NavigationGraph:nodes()` (l.118) — Lista de nodos ordenada por id (se cachea hasta el siguiente cambio).
- `NavigationGraph:removeNode(id)` (l.133) — Quita un nodo y todos sus segmentos.
- `NavigationGraph:moveNode(id, x, y)` (l.150) — Mueve un nodo: los segmentos que lo tocan quedan sucios con su extremo ajustado, y se reconstruyen salvo con `deferRebuild`.
- `NavigationGraph:snapEndpoints(seg)` (l.178) — Ajusta el primer y último punto a las posiciones de sus nodos.
- `NavigationGraph:addSegment(fromId, toId, points, props)` (l.204) — Añade un segmento de `fromId` a `toId`. `points` incluye los extremos (si el primero/último no coincide con el nodo, se ajusta).
- `NavigationGraph:segment(id)` (l.232)
- `NavigationGraph:segments()` (l.237) — Lista de segmentos ordenada por id (cacheada).
- `NavigationGraph:removeSegment(id)` (l.252) — Quita un segmento sin tocar los demás ni sus nodos.
- `NavigationGraph:updateSegment(id, props)` (l.274) — Cambia propiedades editables de un segmento (`width`, `oneWay`, `speedLimit`, `costFactor`, `metadata`, `points`) y lo marca sucio.
- `NavigationGraph:markDirty(segmentId)` (l.312)
- `NavigationGraph:rebuildDirty()` (l.323) — Reconstruye solo los segmentos sucios. Devuelve cuántos.
- `NavigationGraph:rebuildAll()` (l.350) — Marca todo sucio y lo reconstruye (cambio de opciones o carga).
- `NavigationGraph:hasDirty()` (l.357)
- `NavigationGraph:neighbours(nodeId, out)` (l.366) — Vecinos de un nodo respetando `oneWay`: lista de `{ segment=, other=, reversed= }`.
- `NavigationGraph:bounds()` (l.394) — Caja envolvente de todos los nodos (x, y, w, h) o nil si no hay.

## runtime/nv/group.lua

Navegación de grupos: puestos de destino, controlador de formación y la petición de grupo que reparte una orden entre redes.

- Tamaño: 1227 líneas, 27 funciones públicas, 13 locales.
- Usa: runtime/nv/flow_field, runtime/nv/slot_validator, runtime/nv/util, runtime/nv/vector2

- `Group.chooseStrategy(n, opts)` (l.105) — Estrategia para `n` agentes con unos umbrales (`opts` puede ser nil).
- `DestinationSlots.generate(cx, cy, n, spacing, width, angle)` (l.128) — Lista de `{x=, y=}` para `n` unidades separadas `spacing`, centrada en (cx, cy), orientada `angle` radianes; `width` opcional acota las columnas.
- `DestinationSlots.assign(positions, slots)` (l.172) — Reparto: cada puesto, en orden, se lo queda la unidad libre más cercana.
- `FormationController:init(route, members, opts)` (l.203) — `members`: lista de `{ agent=, along=, lateral= }` (desplazamientos respecto al ancla, en px). `route`: la ruta principal del grupo.
- `FormationController:update(dt)` (l.225) — Avanza el ancla y reparte los puntos de formación.
- `GroupNavigationRequest:init(manager, agents, x, y, opts)` (l.294) — Clasifica, proyecta, reparte y pide las rutas. `opts`: `spacing`, `arrivedFraction`, `formation` (false para no crear controlador).
- `GroupNavigationRequest:resolveGroup(group, opts)` (l.376)
- `GroupNavigationRequest:resolvePerAgent(group)` (l.470) — 'small' y 'medium': cada agente pide su ruta (compartida por la caché).
- `GroupNavigationRequest:resolveMassive(group, positions, maxProject)` (l.583) — 'massive': una ruta global y un flow field para todo el grupo.
- `GroupNavigationRequest:buildField(group, route)` (l.613) — Construye el campo del grupo sobre su ruta global y lo registra.
- `GroupNavigationRequest:globalRouteReady(group, route, err)` (l.652) — Llega (o falla) la ruta global de un grupo masivo.
- `GroupNavigationRequest:refreshField(group)` (l.682) — El corredor cambió (`field:stale()`): ruta global nueva desde el centro de los que siguen en marcha y campo nuevo; mientras llega, siguen el viejo.
- `GroupNavigationRequest:nearestSlot(slots, p)` (l.728) — Puesto válido más cercano a una posición.
- `GroupNavigationRequest:validateSlots(group, maxProject, maxRadius, spacing)` (l.743) — Valida los puestos de un grupo con `SlotValidator` (límites y colisión estática del manager, distancia a la red del propio sistema).
- `GroupNavigationRequest:settle(group)` (l.783) — Cuando ya nadie espera ruta: quita a los que fallaron, crea la formación.
- `GroupNavigationRequest:update(dt)` (l.828) — Avanza las formaciones, regenera los campos cuyo corredor cambió y cierra los grupos cuyas rutas ya llegaron.
- `GroupNavigationRequest:reorderSlots(group)` (l.973) — Reparte de nuevo los puestos de los miembros en marcha que ya están en la zona de puestos (ver la cabecera). Devuelve cuántos cambiaron.
- `GroupNavigationRequest:swapNearestSlot(group, agent)` (l.1048) — Un miembro bloqueado dentro de la zona de puestos cambia su puesto por el más cercano a él (de los que aún no ocupa nadie que haya llegado) si está…
- `GroupNavigationRequest:release()` (l.1109) — Da de baja los campos de la petición (cuando termina).
- `GroupNavigationRequest:active()` (l.1124) — ¿Sigue alguien en camino (o esperando ruta)?
- `GroupNavigationRequest:pendingCount()` (l.1134) — ¿Cuántos agentes de la petición esperan todavía su ruta?
- `GroupNavigationRequest:arrived(fraction)` (l.1146) — Llegado cuando al menos `fraction` (por defecto `arrivedFraction`) de los agentes con ruta está en su puesto. Sin agentes con ruta: true.
- `GroupNavigationRequest:group(tag)` (l.1161)
- `GroupNavigation:init(manager, opts)` (l.1172)
- `GroupNavigation:moveGroup(agents, x, y, opts)` (l.1182) — Manda `agents` (lista de `NavigationAgent`) hacia (x, y). Devuelve la petición.
- `GroupNavigation:update(dt)` (l.1211) — Avanza las formaciones y olvida las peticiones terminadas.
- `GroupNavigation:activeRequests()` (l.1222)

## runtime/nv/heap.lua

Min-heap binario para la cola de prioridad de A*.

- Tamaño: 104 líneas, 7 funciones públicas, 0 locales.
- Usa: runtime/nv/util

- `Heap:init()` (l.21)
- `Heap:size()` (l.27)
- `Heap:empty()` (l.31)
- `Heap:clear()` (l.35)
- `Heap:push(item, priority)` (l.42)
- `Heap:pop()` (l.64) — Saca el elemento de menor prioridad: devuelve elemento, prioridad (o nil).
- `Heap:peek()` (l.96) — El mínimo sin sacarlo.

## runtime/nv/hierarchical.lua

Búsqueda jerárquica v2 (HPA* con portales): los nodos se agrupan en regiones (celdas de `clusterSize` px) y cada región conoce sus PORTALES: los nodos con algún tramo cuyo otro extremo cae en otra región.

- Tamaño: 702 líneas, 14 funciones públicas, 10 locales.
- Usa: runtime/nv/astar, runtime/nv/heap, runtime/nv/util

- `Hierarchical:init(system, opts)` (l.59)
- `Hierarchical:regionKey(x, y)` (l.81) — Clave de la región de un punto (y sus índices de celda).
- `Hierarchical:regionsBetween(x1, y1, x2, y2)` (l.89) — Regiones que como mínimo cruza la recta entre dos puntos (distancia de Chebyshev entre sus celdas más una): 1 si comparten región.
- `Hierarchical:markRegionDirty(key)` (l.137) — Marca sucia una región (por clave). Devuelve true si no lo estaba ya.
- `Hierarchical:dirtyRegionCount()` (l.148)
- `Hierarchical:nodeAdded(node)` (l.186)
- `Hierarchical:nodeRemoved(node)` (l.193)
- `Hierarchical:nodeMoved(node)` (l.202) — Un nodo movido puede cambiar de región; sus vecinos pueden dejar de ser (o pasar a ser) portales, así que sus regiones también quedan sucias.
- `Hierarchical:segmentChanged(seg)` (l.225) — Cualquier cambio de un tramo ensucia las regiones de sus dos extremos: ahí viven sus portales, sus cruces y los costes locales que lo usan.
- `Hierarchical:build()` (l.310) — Pone al día el grafo de regiones: todo la primera vez (o cuando cambia la versión sin estar `attached`); después, solo las regiones sucias.
- `Hierarchical:countPortals()` (l.342)
- `Hierarchical:find(startId, goalId, opts)` (l.524) — Igual que `AStar.find` (mismo resultado: `nodes`, `steps`, `cost`, `explored`), por el grafo de portales.
- `Hierarchical:regionPath(fromKey, toKey)` (l.638) — A* solo sobre regiones (por `links`): el conjunto de claves de un corredor de regiones, o nil.
- `Hierarchical:stats()` (l.691) — Resumen: regiones, portales, sucias, búsquedas y reconstrucciones.

## runtime/nv/init.lua

NV: fachada del sistema de navegación por rutas dibujadas.

- Tamaño: 151 líneas, 4 funciones públicas, 0 locales.
- Usa: runtime/nv/agent, runtime/nv/agent_spatial_hash, runtime/nv/arc_length, runtime/nv/astar, runtime/nv/catmull_rom, runtime/nv/commands, runtime/nv/curvature, runtime/nv/debug, runtime/nv/flow_field, runtime/nv/graph, runtime/nv/group, runtime/nv/heap, runtime/nv/hierarchical, runtime/nv/local_avoidance, runtime/nv/manager, runtime/nv/node, runtime/nv/path_cache, runtime/nv/path_follower, runtime/nv/profiler, runtime/nv/quadtree, runtime/nv/route, runtime/nv/scheduler, runtime/nv/segment, runtime/nv/serializer, runtime/nv/simplify, runtime/nv/slot_validator, runtime/nv/spatial_hash, runtime/nv/steering, runtime/nv/system, runtime/nv/util, runtime/nv/vector2

- `NV.load(mapData, options)` (l.71) — Manager desde los datos del mapa (`mapData.navigation`); sin ellos, vacío.
- `NV.hasNetworks(mapData)` (l.97) — ¿El mapa trae alguna red?
- `NV.agentProps(object)` (l.109) — Propiedades de agente a partir del componente `object.navigation` (`tag` obligatorio; el resto opcional), con estos respaldos: maxSpeed ←…
- `NV.defaultFlags()` (l.146) — Flags de depuración, todos a false.

## runtime/nv/local_avoidance.lua

Esquiva local entre agentes. Dos versiones, elegibles por agente con `props.avoidance = 'v2' | 'v1'` (por defecto 'v2', ver `docs/NV.md` → "Congestión"). Ninguna lanza búsquedas de camino.

- Tamaño: 865 líneas, 5 funciones públicas, 19 locales.
- Usa: runtime/nv/util, runtime/nv/vector2

- `LocalAvoidance:init(opts)` (l.107)
- `LocalAvoidance:reset()` (l.164)
- `LocalAvoidance:compute(agent, neighbours, dt)` (l.180) — Vector de esquiva para `agent` (un `NavigationAgent`). Devuelve ax, ay.
- `LocalAvoidance:safeVelocity(agent, neighbours, pvx, pvy, dt, maxSpeed, cnx, cny, cc)` (l.708) — v2: velocidad segura para `agent` (un `NavigationAgent` o una tabla plana) con velocidad preferida (pvx, pvy).
- `LocalAvoidance:speedAlong(hx, hy, lo, hi, desired)` (l.846) — v2: rapidez a lo largo del rumbo unitario (hx, hy) dentro de [lo, hi] (lo negativo = marcha atrás) que cumple todos los semiplanos del último…

## runtime/nv/manager.lua

Gestor de sistemas de navegación: uno por tag (`TankNavigation`, `InfantryNavigation`…), con las consultas por tag y la carga/guardado.

- Tamaño: 692 líneas, 33 funciones públicas, 1 locales.
- Usa: runtime/nv/agent_spatial_hash, runtime/nv/profiler, runtime/nv/scheduler, runtime/nv/serializer, runtime/nv/system, runtime/nv/util

- `NavigationManager.lodOptions(raw)` (l.104) — Opciones de LOD saneadas a partir de `options.lod` (`false` lo apaga).
- `NavigationManager:init(options)` (l.124)
- `NavigationManager:noteRepath(n)` (l.153) — Anota un recálculo de ruta (lo llaman `agent:repath` y el grupo al regenerar su flow field).
- `NavigationManager:addSystem(name, opts)` (l.160) — Crea un sistema (o devuelve el que ya tiene ese nombre). `opts.id` fija el id al cargar.
- `NavigationManager:systemById(id)` (l.189)
- `NavigationManager:removeSystem(name)` (l.198)
- `NavigationManager:renameSystem(old, new)` (l.207)
- `NavigationManager:getSystem(tag)` (l.229)
- `NavigationManager:systems()` (l.237) — Lista de sistemas ordenada por nombre (cacheada).
- `NavigationManager:count()` (l.251)
- `NavigationManager:targets(tag)` (l.256) — Sistemas a consultar para un tag (todos si es nil).
- `NavigationManager:findNearestNode(x, y, tag, maxDist)` (l.268) — Nodo más cercano: nodo, distancia, sistema.
- `NavigationManager:findNodesInArea(x, y, w, h, tag)` (l.279)
- `NavigationManager:findSegmentsNear(x, y, r, tag)` (l.289)
- `NavigationManager:update()` (l.300) — Procesa lo sucio de todos los sistemas.
- `NavigationManager:version()` (l.309) — Suma de versiones (cambia si cambia cualquier sistema).
- `NavigationManager:enableScheduler(opts)` (l.321) — Crea (o devuelve) el planificador de rutas. Con él, `setDestination` de los agentes de este manager queda programado por defecto.
- `NavigationManager:disableScheduler()` (l.329) — Quita el planificador (las peticiones pendientes se cancelan).
- `NavigationManager:agentHash()` (l.338) — El índice espacial de agentes (se crea al primer uso).
- `NavigationManager:updateAgents(agents)` (l.348) — Sincroniza el índice de agentes con la lista (una vez por cuadro, antes de moverlos).
- `NavigationManager:beginFrame(agents)` (l.359) — Trabajo NV de principio de cuadro: cola de rutas, índice de agentes y niveles de LOD.
- `NavigationManager:setFocus(x, y, w, h)` (l.382) — Rectángulo de interés en coordenadas de mundo (normalmente `camera:visibleRect()`).
- `NavigationManager:getFocus()` (l.404) — El rectángulo de foco: x, y, w, h, o nil si no hay.
- `NavigationManager:setSelected(agents)` (l.414) — Agentes seleccionados: van 'full' aunque estén lejos del foco. Sustituye la selección anterior (la tabla interna se reutiliza).
- `NavigationManager:lodLevelOf(agent)` (l.428) — Nombre del nivel de LOD de un agente: 'full' | 'reduced' | 'coarse'.
- `NavigationManager:updateLod(agents)` (l.454) — Reparte los niveles de LOD y las cubetas del cuadro (lo llama `beginFrame`, después del índice de agentes).
- `NavigationManager:endFrame()` (l.555) — Cierra el cuadro del profiler.
- `NavigationManager:setProfiling(enabled)` (l.560)
- `NavigationManager:trackFlowField(field)` (l.566) — Registra un flow field activo (lo hace `group.lua` al construirlo).
- `NavigationManager:untrackFlowField(field)` (l.578) — Da de baja un flow field (cuando su grupo termina).
- `NavigationManager:stats()` (l.601) — Estadísticas para el panel NV PROFILER (tabla reutilizada; números, 0 si no aplica): agents, moving, pendingPaths, astarRequestsPerFrame,…
- `NavigationManager:toData(opts)` (l.680)
- `NavigationManager.fromData(data, options)` (l.685) — Construye un gestor desde datos guardados (tolerante: nunca lanza).

## runtime/nv/node.lua

Nodo del grafo de navegación: un extremo, cruce o intersección de rutas.

- Tamaño: 63 líneas, 6 funciones públicas, 0 locales.
- Usa: runtime/nv/util

- `NavigationNode:init(id, x, y, metadata)` (l.14)
- `NavigationNode:connect(segmentId)` (l.23) — Apunta un segmento (idempotente).
- `NavigationNode:disconnect(segmentId)` (l.33)
- `NavigationNode:isConnected(segmentId)` (l.43)
- `NavigationNode:degree()` (l.53) — Cuántos segmentos tocan el nodo.
- `NavigationNode:bounds()` (l.58) — Caja envolvente puntual (para el índice espacial).

## runtime/nv/path_cache.lua

Caché LRU de rutas entre nodos.

- Tamaño: 137 líneas, 9 funciones públicas, 2 locales.
- Usa: runtime/nv/util

- `PathCache.key(systemId, startId, goalId, agentClass, version)` (l.20)
- `PathCache:init(maxEntries)` (l.32)
- `PathCache:get(key)` (l.66)
- `PathCache:put(key, value)` (l.80)
- `PathCache:has(key)` (l.103)
- `PathCache:peek(key)` (l.109) — Como `get`, pero sin contar acierto ni fallo ni tocar el orden LRU (para las consultas "solo caché" del planificador).
- `PathCache:size()` (l.117)
- `PathCache:invalidate()` (l.121)
- `PathCache:each(fn)` (l.128) — Recorre las rutas guardadas (de la más reciente a la más antigua).

## runtime/nv/path_follower.lua

Seguimiento de una ruta por distancia acumulada, con objetivo adelantado (look-ahead) y ventana de curvatura por delante.

- Tamaño: 96 líneas, 9 funciones públicas, 0 locales.
- Usa: runtime/nv/util

- `PathFollower:init(route, props)` (l.28)
- `PathFollower:distanceAlongPath()` (l.41) — Alias con el nombre de la especificación.
- `PathFollower:advanceTo(x, y)` (l.47) — Reproyecta la posición real sobre la ruta cerca de la distancia actual. Devuelve la distancia nueva y la separación.
- `PathFollower:rewindTo(x, y, back)` (l.59) — Reproyecta permitiendo volver atrás hasta `back` px (por defecto `4·aheadWindow`): para cuando el agente retrocedió a propósito.
- `PathFollower:lookAhead(distance)` (l.68) — Punto de la ruta a `distance` px por delante (acotado al final).
- `PathFollower:curvatureAhead(distance)` (l.78) — Curvatura máxima en la ventana [distancia actual, + `distance`].
- `PathFollower:remaining()` (l.82)
- `PathFollower:finished()` (l.86)
- `PathFollower:tangent()` (l.91) — Tangente de la ruta en la distancia actual.

## runtime/nv/profiler.lua

Profiler de NV: cuenta y cronometra lo que hace la navegación en cada cuadro, solo cuando está encendido.

- Tamaño: 134 líneas, 8 funciones públicas, 0 locales.
- Usa: runtime/nv/scheduler, runtime/nv/util

- `NvProfiler:init(opts)` (l.38)
- `NvProfiler:setEnabled(enabled)` (l.54)
- `NvProfiler:start()` (l.65) — Marca de tiempo para `finish`, o nil si está apagado.
- `NvProfiler:finish(name, t)` (l.74) — Suma a la sección `name` el tiempo desde `t` (una marca de `start`).
- `NvProfiler:count(name, n)` (l.88) — Suma `n` (1 por defecto) al contador `name`.
- `NvProfiler:beginFrame()` (l.95)
- `NvProfiler:endFrame()` (l.106)
- `NvProfiler:reset()` (l.124) — Pone a cero contadores y secciones.

## runtime/nv/quadtree.lua

Quadtree de regiones para consultas de área en mapas con reparto muy irregular. OPCIONAL: `NavigationSystem` usa el spatial hash para todo; este árbol existe para quien quiera activarlo (`options.quadtree = true`) o usarlo…

- Tamaño: 213 líneas, 8 funciones públicas, 6 locales.
- Usa: runtime/nv/util

- `Quadtree:init(bounds, capacity, maxDepth)` (l.27)
- `Quadtree:insert(id, bounds)` (l.96)
- `Quadtree:remove(id)` (l.112)
- `Quadtree:update(id, bounds)` (l.127)
- `Quadtree:contains(id)` (l.132)
- `Quadtree:queryRect(x, y, w, h, out)` (l.155) — Ids cuyas cajas tocan el rectángulo.
- `Quadtree:rebuild(items)` (l.172) — Vacía el árbol y lo rellena con `items`: mapa `id → bounds` o lista de `{ id=, bounds= }`.
- `Quadtree:eachNode(fn)` (l.200) — Recorre los nodos del árbol: `fn(node)` con `x, y, w, h, depth, ids`.

## runtime/nv/route.lua

Ruta de un agente: la concatenación de trozos que va desde donde está hasta su destino, con una sola distancia acumulada `d` de principio a fin.

- Tamaño: 302 líneas, 16 funciones públicas, 0 locales.
- Usa: runtime/nv/util, runtime/nv/vector2

- `Route:init(system)` (l.34)
- `Route:addLine(x1, y1, x2, y2)` (l.49) — Añade una recta (si mide algo).
- `Route:addSegmentPart(segment, d0, d1, node0, node1)` (l.61) — Añade el trozo de `segment` que va de la distancia `d0` a la `d1` (medidas desde `from`; `d1 < d0` = a contramano).
- `Route:addStep(step)` (l.81) — Añade un paso de A* entero.
- `Route:finish()` (l.91) — Cierra la ruta: acumula desplazamientos y los nodos anterior/siguiente de cada trozo.
- `Route:length()` (l.120)
- `Route:pieceCount()` (l.124)
- `Route:locate(d)` (l.129) — Trozo y distancia local para una `d` global (acotada).
- `Route:positionAt(d)` (l.160)
- `Route:tangentAt(d)` (l.175) — Tangente unitaria en el sentido de avance.
- `Route:curvatureAt(d)` (l.190)
- `Route:maxCurvatureAhead(d, ahead)` (l.199) — Curvatura máxima en la ventana [d, d + ahead], sin reservar memoria.
- `Route:segmentAt(d)` (l.231) — Segmento bajo la distancia d (nil en una recta libre) y la distancia dentro de él desde su nodo `from`.
- `Route:nodeAt(d)` (l.241) — Nodo que se acaba de dejar atrás y nodo siguiente (ids; pueden ser nil en las rectas de entrada/salida).
- `Route:waypoints()` (l.251) — Polilínea plana `{x1, y1, x2, y2, ...}` muestreada cada `WAYPOINT_STEP` px (se calcula una vez).
- `Route:project(x, y, d, back, ahead, step)` (l.273) — Distancia del punto a la ruta buscando cerca de `d` (ventana `back` hacia atrás y `ahead` hacia delante, muestreando cada `step`).

## runtime/nv/scheduler.lua

Planificador de búsquedas de ruta (NavigationScheduler): una cola con presupuesto por cuadro para que una orden a 500 unidades no lance 500 A* en el mismo `update`.

- Tamaño: 376 líneas, 11 funciones públicas, 6 locales.
- Usa: runtime/nv/heap, runtime/nv/util

- `NavigationScheduler.detectClock()` (l.68) — Reloj en segundos: `love.timer.getTime` si existe, si no `os.clock`.
- `NavigationScheduler:init(manager, opts)` (l.82)
- `NavigationScheduler.key(system, startSegmentId, goalSegmentId, agentClass)` (l.120) — Clave de deduplicación: red, tramo de salida, tramo de entrada y clase.
- `NavigationScheduler:cancel(request)` (l.159) — Cancela una petición en cola. Devuelve true si estaba pendiente.
- `NavigationScheduler:cancelFor(owner)` (l.171) — Cancela la petición pendiente de un dueño (agente).
- `NavigationScheduler:pendingFor(owner)` (l.179) — Petición pendiente de un dueño, o nil.
- `NavigationScheduler:request(spec)` (l.213) — Encola (o resuelve en el acto) una petición. `spec`: `system`, `sx`, `sy`, `tx`, `ty`, `props`, `owner`, `priority`, `callback`, `immediate`.
- `NavigationScheduler:update()` (l.324) — Procesa la cola con el presupuesto del cuadro. Devuelve cuántas búsquedas hizo.
- `NavigationScheduler:clear()` (l.346) — Vacía la cola cancelando todo lo pendiente.
- `NavigationScheduler:stats()` (l.361) — Estadísticas (tabla reutilizada): `queued`, `processedPerFrame`, `cacheHits`, `cacheMisses`, `averageSearchMs`, `maxSearchMs`, `cancelled`,…
- `NavigationScheduler:resetStats()` (l.367) — Pone a cero los acumulados (la cola no se toca).

## runtime/nv/segment.lua

Segmento del grafo de navegación: la curva que une dos nodos.

- Tamaño: 292 líneas, 12 funciones públicas, 0 locales.
- Usa: runtime/nv/arc_length, runtime/nv/catmull_rom, runtime/nv/curvature, runtime/nv/util, runtime/nv/vector2

- `NavigationSegment:init(id, from, to, points, props)` (l.112) — `points` incluye los extremos (el grafo los ajusta a los nodos). `props`: `width`, `oneWay`, `speedLimit`, `costFactor`, `metadata`, `rawPoints`.
- `NavigationSegment:rebuild(opts)` (l.135) — Recalcula todo lo derivado. `opts`: `samplesPerSegment`, `curvatureStep`, `curvatureWindow`, `lateralAccel`, `referenceSpeed`.
- `NavigationSegment:allowsReverse()` (l.192) — ¿Se puede recorrer de `to` a `from`?
- `NavigationSegment:otherEnd(nodeId)` (l.197) — Nodo del otro extremo (o nil si `nodeId` no es un extremo).
- `NavigationSegment:positionAt(d, reversed)` (l.208) — Posición a `d` píxeles del nodo `from` (o del `to`, si `reversed`).
- `NavigationSegment:tangentAt(d, reversed)` (l.216) — Tangente unitaria en el sentido de recorrido.
- `NavigationSegment:curvatureAt(d)` (l.225) — Curvatura (1/radio) a `d` píxeles de `from`, del perfil precalculado.
- `NavigationSegment:maxCurvatureBetween(d0, d1)` (l.230) — Curvatura máxima entre `d0` y `d1` (medidos desde `from`).
- `NavigationSegment:nearestPoint(x, y)` (l.237) — Punto del segmento más cercano a (x, y): busca la muestra del arco más próxima y afina proyectando sobre las dos cuerdas vecinas.
- `NavigationSegment:cost(agent)` (l.260) — Coste del segmento para un agente (`agent` puede ser `{}`).
- `NavigationSegment:partialCost(agent, len)` (l.274) — Coste de recorrer solo una parte (`len` píxeles) del segmento.
- `NavigationSegment:endpoints()` (l.283) — Extremos: x, y del nodo `from` y del `to`, según los puntos.

## runtime/nv/serializer.lua

Guardado y carga de las redes de navegación. Formato versionado:

- Tamaño: 177 líneas, 4 funciones públicas, 2 locales.
- Usa: runtime/nv/util

- `Serializer.systemToData(system, opts)` (l.39) — Datos de un solo sistema.
- `Serializer.toData(manager, opts)` (l.81)
- `Serializer.migrate(data)` (l.92) — Lleva datos de versiones anteriores a la actual. Hoy solo hay la 1; una versión desconocida (más nueva) se deja tal cual y se carga con tolerancia.
- `Serializer.fromData(data, manager)` (l.164) — Rellena `manager` con los sistemas de `data`. Devuelve el manager.

## runtime/nv/simplify.lua

Simplificación del trazo dibujado: muestreo por distancia y Ramer-Douglas-Peucker. Funciones puras sobre listas de `{x=, y=}`.

- Tamaño: 169 líneas, 5 funciones públicas, 2 locales.
- Usa: runtime/nv/vector2

- `S.sampleByDistance(points, sampleDistance)` (l.24) — Añade una muestra solo cuando la distancia a la última muestra supera `sampleDistance`.
- `S.rdp(points, tolerance)` (l.61) — Ramer-Douglas-Peucker iterativo (con pila propia: sin límite de recursión).
- `S.smooth(points, window)` (l.112) — Quita los puntos consecutivos repetidos (a menos de `V.EPSILON`).
- `S.dedupe(points)` (l.147)
- `S.polylineLength(points)` (l.160) — Longitud de una polilínea.

## runtime/nv/slot_validator.lua

Validación de puestos de destino (Destination Slots) de un grupo.

- Tamaño: 172 líneas, 7 funciones públicas, 0 locales.
- Usa: runtime/nv/util

- `SlotValidator:init(system, opts)` (l.49) — `opts`: `bounds` ({x, y, w, h}), `blocked(x, y, r)`, `maxProjectDistance` (por defecto la del sistema), `ringStep`, `maxRings`, `maxAttempts`.
- `SlotValidator:reset()` (l.66) — Olvida los puestos aceptados (para reutilizar el validador en otra orden).
- `SlotValidator:validate(x, y, radius, agent)` (l.74) — Comprueba un punto sin cambiar nada. Devuelve true, o false y el motivo.
- `SlotValidator:accept(x, y, radius)` (l.111) — Reserva el hueco de un puesto válido. Devuelve la entrada de `taken`.
- `SlotValidator:release(slot)` (l.118) — Libera un puesto aceptado (`slot` es lo que devolvió `place`, o su `taken`).
- `SlotValidator:place(x, y, radius, agent)` (l.134) — Valida (x, y) y, si no vale, busca el candidato válido más cercano en anillos crecientes.
- `SlotValidator:stats()` (l.167) — Contadores: validaciones, rechazos del puesto original, respaldos y fallos.

## runtime/nv/spatial_hash.lua

Índice espacial por celdas (spatial hash) para nodos y segmentos.

- Tamaño: 340 líneas, 14 funciones públicas, 6 locales.
- Usa: runtime/nv/util

- `SpatialHash:init(cellSize)` (l.34)
- `SpatialHash:cellOf(v)` (l.44)
- `SpatialHash:cellRange(x, y, w, h)` (l.49) — Rango de celdas de una caja.
- `SpatialHash:insert(id, bounds)` (l.80) — Inserta (o reemplaza) el elemento `id` con su caja `{x, y, w, h}`.
- `SpatialHash:remove(id)` (l.101)
- `SpatialHash:update(id, bounds)` (l.118) — Mueve un elemento: si sigue en las mismas celdas solo actualiza la caja.
- `SpatialHash:contains(id)` (l.135)
- `SpatialHash:bounds(id)` (l.139)
- `SpatialHash:clear()` (l.143)
- `SpatialHash:queryRect(x, y, w, h, out)` (l.182) — Ids cuyas cajas tocan el rectángulo. `out` se vacía y se rellena (si no se da, se usa una lista interna reutilizada).
- `SpatialHash:queryRadius(x, y, r, out)` (l.216) — Ids cuyas cajas quedan a `r` o menos del punto.
- `SpatialHash:nearest(x, y, maxDist, accept)` (l.232) — El elemento más cercano al punto (distancia a su caja), a no más de `maxDist`. `accept(id)` opcional descarta candidatos. Devuelve id, distancia.
- `SpatialHash:extent()` (l.292) — Radio que cubre todos los elementos (para no girar sin fin con maxDist = ∞).
- `SpatialHash:occupiedCells(out)` (l.317) — Celdas ocupadas, como lista de `{cx, cy, n}` (para el dibujo de depuración).

## runtime/nv/steering.lua

Cuentas de conducción (steering), puras y sin tablas: giro acotado, velocidad por curvatura, aceleración/frenado y llegada.

- Tamaño: 124 líneas, 7 funciones públicas, 0 locales.
- Usa: runtime/nv/vector2

- `Steering.seek(x, y, tx, ty, maxSpeed)` (l.32) — Velocidad deseada (vector) hacia un punto, de módulo `maxSpeed`.
- `Steering.limitTurn(heading, desired, maxStep)` (l.39) — Gira `heading` hacia `desired` sin pasar de `maxStep` radianes. Devuelve el rumbo nuevo y el giro aplicado.
- `Steering.speedForCurvature(k, lateralAccel, maxSpeed)` (l.53) — Velocidad que aguanta una curvatura `k` (1/radio) con aceleración lateral `lateralAccel`, acotada por `maxSpeed`.
- `Steering.maxTurnRate(speed, turningRadius, minSpeed)` (l.66) — Giro máximo (rad/s) de una unidad a velocidad `speed` con radio mínimo `turningRadius`. `minSpeed` (opcional) evita que a velocidad 0 no pueda girar.
- `Steering.turningRadius(speed, turnRate)` (l.78) — Radio de giro que describe una unidad a `speed` girando a `turnRate` rad/s.
- `Steering.arrive(dist, stoppingDistance, maxSpeed, braking)` (l.87) — Velocidad objetivo al acercarse: 0 dentro de `stoppingDistance`; fuera, la que aún permite frenar a tiempo con `braking` (o una rampa lineal sin él).
- `Steering.accelerate(speed, target, acceleration, braking, dt)` (l.106) — Acerca `speed` a `target` con `acceleration` al subir y `braking` al bajar.

## runtime/nv/system.lua

Un sistema de navegación (una red con nombre = tag): su grafo, sus índices espaciales, la caché de rutas y la proyección de puntos sobre la red.

- Tamaño: 510 líneas, 22 funciones públicas, 3 locales.
- Usa: runtime/nv/astar, runtime/nv/graph, runtime/nv/hierarchical, runtime/nv/path_cache, runtime/nv/quadtree, runtime/nv/route, runtime/nv/spatial_hash, runtime/nv/util, runtime/nv/vector2

- `NavigationSystem.hierarchicalMode(value)` (l.78) — `'auto' | true | false` a partir de lo que venga (datos guardados incluidos).
- `NavigationSystem:init(id, name, options)` (l.90)
- `NavigationSystem:tag()` (l.122) — Nombre = tag.
- `NavigationSystem:nodeAdded(node)` (l.140)
- `NavigationSystem:nodeMoved(node)` (l.147)
- `NavigationSystem:nodeRemoved(node)` (l.154)
- `NavigationSystem:segmentAdded(seg)` (l.160)
- `NavigationSystem:segmentRebuilt(seg)` (l.166)
- `NavigationSystem:segmentRemoved(seg)` (l.175)
- `NavigationSystem:changed()` (l.184)
- `NavigationSystem:markDirty(segmentId)` (l.193) — Marca un tramo sucio (se reconstruye en `update`). Sus regiones jerárquicas quedan sucias desde ya, no al reconstruir.
- `NavigationSystem:dirtyRegionCount()` (l.202) — Regiones jerárquicas pendientes de reconstruir (0 sin buscador jerárquico).
- `NavigationSystem:update()` (l.208) — Procesa los segmentos sucios (incremental). Devuelve cuántos reconstruyó.
- `NavigationSystem:rebuild()` (l.213) — Reconstruye todo: segmentos e índices (tras cargar o cambiar opciones).
- `NavigationSystem:findNearestNode(x, y, maxDist)` (l.242) — Nodo más cercano a (x, y) a no más de `maxDist` (por defecto sin límite). Devuelve nodo, distancia.
- `NavigationSystem:findNodesInArea(x, y, w, h, out)` (l.251) — Nodos dentro del rectángulo.
- `NavigationSystem:findSegmentsNear(x, y, r, out)` (l.268) — Segmentos cuya caja queda a `r` o menos del punto (candidatos; la distancia exacta la da `segment:nearestPoint`).
- `NavigationSystem:projectPoint(x, y, maxDist, out)` (l.286) — Proyección de un punto sobre la red: `{ segment=, d=, x=, y=, dist= }` o nil si no hay nada a `maxDist` (por defecto `options.maxProjectDistance`).
- `NavigationSystem:useHierarchical(startId, goalId)` (l.326) — ¿Buscador jerárquico para este par de nodos? Ver la cabecera ("Plano o jerárquico"). Sin ids (llamada vieja) decide solo por el tamaño del grafo.
- `NavigationSystem:hierarchical()` (l.348) — El buscador jerárquico (se crea al primer uso, enganchado a los eventos del grafo).
- `NavigationSystem:findNodePath(startId, goalId, agent, cacheOnly)` (l.361) — Ruta de nodos entre dos ids (con caché por clase de agente y versión). Devuelve el resultado de `AStar.find` o nil, motivo.
- `NavigationSystem:requestPath(sx, sy, tx, ty, agent, opts)` (l.435) — Ruta desde (sx, sy) hasta (tx, ty) para un agente. Devuelve `Route` o nil, motivo.

## runtime/nv/util.lua

Utilidades compartidas por los módulos de NV: la clase con constructor "doble" y saneado de números y booleanos que llegan de datos guardados.

- Tamaño: 117 líneas, 8 funciones públicas, 0 locales.
- Usa: runtime/class

- `NvUtil.class(name, parent)` (l.18) — Crea una clase (`Class(name, parent)`) cuyo `new` vale con punto y con dos puntos.
- `NvUtil.nextSerial()` (l.34) — Número de serie creciente (órdenes, grupos, agentes): el orden de creación desempata prioridades de forma reproducible.
- `NvUtil.finite(value, fallback)` (l.41) — Número finito, o `fallback` si no es un número utilizable (texto que no parsea, NaN, ±inf, nil).
- `NvUtil.atLeast(value, fallback, lo)` (l.50) — Número finito acotado por abajo: `max(lo, finite(value, fallback))`.
- `NvUtil.bool(value, fallback)` (l.55) — Booleano tolerante: `false`/`'false'`/`0` → false; nil → `fallback`.
- `NvUtil.shallowCopy(t)` (l.66) — Copia de una tabla plana (un nivel), o `{}`.
- `NvUtil.deepCopy(v)` (l.77) — Copia profunda de un valor de datos (tablas anidadas, sin ciclos).
- `NvUtil.copyPoints(points)` (l.90) — Lista de `{x=, y=}` copiada y saneada: entradas sin números se saltan. Admite también pares `{x, y}` y listas planas `{x1, y1, x2, y2, ...}`.

## runtime/nv/vector2.lua

Vectores 2D como pares de números sueltos (sin tablas), para no reservar memoria en `update`. Todas las funciones son puras.

- Tamaño: 128 líneas, 15 funciones públicas, 0 locales.

- `V.length(x, y)` (l.21) — Longitud de (x, y).
- `V.lengthSq(x, y)` (l.26) — Longitud al cuadrado, para comparar sin raíz.
- `V.normalize(x, y)` (l.32) — Vector unitario y longitud original. Con longitud menor que `V.EPSILON` devuelve (0, 0, 0): nunca divide por cero.
- `V.dot(ax, ay, bx, by)` (l.41) — Producto escalar.
- `V.cross(ax, ay, bx, by)` (l.47) — Producto vectorial (componente z): positivo si b queda a la izquierda de a en un sistema con Y hacia arriba; con Y hacia abajo, a la derecha visual.
- `V.distance(ax, ay, bx, by)` (l.52) — Distancia entre dos puntos.
- `V.distanceSq(ax, ay, bx, by)` (l.58) — Distancia al cuadrado entre dos puntos.
- `V.lerp(a, b, t)` (l.64) — Interpolación lineal de un escalar.
- `V.lerp2(ax, ay, bx, by, t)` (l.69) — Interpolación lineal de un punto: devuelve x, y.
- `V.angle(x, y)` (l.74) — Ángulo del vector, `atan2(y, x)`.
- `V.wrapAngle(a)` (l.79) — Ángulo llevado a (-π, π].
- `V.rotate(x, y, a)` (l.88) — Gira (x, y) el ángulo `a`.
- `V.perpendicular(x, y)` (l.94) — Perpendicular (giro de +90°: en pantalla, hacia la derecha del avance).
- `V.closestOnSegment(px, py, ax, ay, bx, by)` (l.100) — Punto de un segmento a-b más cercano a p. Devuelve x, y, parámetro u en [0, 1] y distancia. Con a = b devuelve a.
- `V.clamp(v, lo, hi)` (l.118) — Acota `v` a [lo, hi].

## runtime/patrol.lua

Small opt-in example behavior shared by editor Play and exported games. Positions belong to Box2D; this controller only supplies velocity.

- Tamaño: 94 líneas, 4 funciones públicas, 1 locales.

- `Patrol.new(object, body)` (l.14)
- `Patrol:turn()` (l.42)
- `Patrol:beforePhysics(dt)` (l.48)
- `Patrol:update()` (l.70)

## runtime/projection.lua

Proyección de la vista: desde arriba (`top`, la de siempre) o isométrica (`iso`).

- Tamaño: 617 líneas, 29 funciones públicas, 1 locales.
- Usa: runtime/terrain_relief

- `Projection.isIso(map)` (l.34) — ¿El mapa se ve en isométrico?
- `Projection.toView(map, x, y)` (l.39) — Punto de mundo a punto de la vista.
- `Projection.toWorld(map, vx, vy)` (l.48) — Punto de la vista a punto de mundo. Inversa exacta de `toView`.
- `Projection.isoTransform()` (l.60) — Matriz de mundo a vista en isométrico.
- `Projection.apply(map)` (l.72) — Aplica la proyección a la transformación actual: desde aquí se dibuja en coordenadas de mundo. En vista desde arriba no hace nada.
- `Projection.worldRect(map, view)` (l.79) — Caja de mundo que cubre un rectángulo de la vista (para recortar el dibujo).
- `Projection.viewRect(map, world)` (l.101) — Caja de la vista que cubre un rectángulo de mundo (el mapa entero, por ejemplo).
- `Projection.depth(map, x, y, z)` (l.123) — Profundidad de dibujo: lo que tiene más valor va delante.
- `Projection.viewAngle(map, angle)` (l.133) — Ángulo de mundo visto en pantalla (para girar una imagen sin direcciones).
- `Projection.imageAngle(map, angle)` (l.145) — Cuánto se gira en pantalla una imagen sin direcciones: lo que el objeto se aparta de rotación 0, medido en la vista.
- `Projection.stripLayout(path)` (l.158) — Rumbos e inclinaciones de una tira por su nombre: `_dir16.png` son 16 rumbos en una fila; `_dir16x5.png`, 16 rumbos (columnas) por 5 inclinaciones…
- `Projection.directionCount(path)` (l.179) — Número de rumbos de una imagen por su nombre, o 1.
- `Projection.directionIndex(angle, count)` (l.185) — Cuadro (0..N-1) para un ángulo de mundo.
- `Projection.pitchIndex(pitch, rows)` (l.194) — Fila (0..rows-1) para una inclinación en radianes (positiva = morro arriba).
- `Projection.frameSize(image, path)` (l.205) — Ancho y alto de un cuadro de la imagen (la imagen entera si no tiene direcciones).
- `Projection.drawThumb(image, path, x, y, box, alpha)` (l.236) — Dibuja la imagen (o su primer cuadro si es una tira de direcciones) encajada en una caja de `box` px con su esquina en `x, y`. Para miniaturas.
- `Projection.drawSprite(map, image, path, x, y, angle, sx, sy, z, pitch)` (l.261) — Dibuja un objeto de pie en `x, y` de mundo, con la transformación de mundo puesta (la de `Projection.apply`). La imagen queda centrada en el punto.
- `Projection.drawShadow(map, x, y, radius, z)` (l.307) — Sombra en el suelo de algo que vuela a altura `z`: una mancha oscura bajo el punto, más tenue y algo más pequeña cuanto más alto.
- `Projection.line3D(x1, y1, z1, x2, y2, z2)` (l.324) — Línea entre dos puntos con altura (x, y, z), con la transformación de mundo puesta. Para estelas y trayectorias de lo que vuela.
- `Projection.baseHeight(map, x, y)` (l.350) — Altura del terreno (relieve) en un punto de mundo; 0 si el mapa es plano.
- `Projection.pick(map, vx, vy)` (l.360) — Punto de la vista a punto de mundo **sobre el terreno**: con relieve, el punto de la colina que se ve ahí, no el del suelo plano de debajo.
- `Projection.toViewGround(map, x, y)` (l.377) — Punto de mundo a punto de la vista, apoyado en el terreno.
- `Projection.expandForRelief(map, rect)` (l.384) — Amplía una caja de mundo visible para que no se recorte lo que el relieve sube dentro de la pantalla desde más abajo.
- `Projection.lift(map, z)` (l.397) — Cuánto sube en la vista una altura `z` de mundo (0 fuera de isométrico).
- `Projection.drawVolume(map, points, z, height, color, fillAlpha)` (l.410) — Dibuja una colisión como volumen. `points` es su contorno en el suelo (mundo, lista plana), `z` su elevación y `height` su altura, en px de mundo.
- `Projection.upright(x, y, draw)` (l.523) — Dibuja algo **de pie** alrededor del punto de mundo `x, y`: barras de salud, rótulos, iconos.
- `Projection.spriteContains(map, image, path, o, vx, vy)` (l.545) — ¿El punto de vista `vx, vy` cae dentro de la imagen de pie de un objeto? Para seleccionar con el ratón lo que se ve, no la huella en el suelo.
- `Projection.spritePixel(map, image, path, o, vx, vy)` (l.558) — Píxel de la imagen (0-based, en la imagen entera) que hay bajo el punto de vista `vx, vy`, o nil si cae fuera.
- `Projection.sortByDepth(map, list, position)` (l.586) — Ordena una lista de objetos por profundidad (estable: a igual profundidad se respeta el orden de la capa).

## runtime/rts.lua

(sin comentario de cabecera)

- Tamaño: 163 líneas, 12 funciones públicas, 5 locales.

- `Rts.new(source)` (l.31)
- `Rts:rebuild()` (l.46)
- `Rts:players()` (l.76)
- `Rts:player(id)` (l.80)
- `Rts:resources(kind)` (l.89)
- `Rts:starts(playerId)` (l.104)
- `Rts:zones(kind)` (l.120)
- `Rts:objectsByPlayer(playerId)` (l.130)
- `Rts:objectsByRole(role)` (l.134)
- `Rts:objectsByKind(kind)` (l.138)
- `Rts:units(playerId)` (l.142)
- `Rts:buildings(playerId)` (l.152)

## runtime/terrain.lua

Terreno por celdas, dibujado en bloques con `SpriteBatch` (fase 8, bloque 3).

- Tamaño: 558 líneas, 11 funciones públicas, 9 locales.
- Usa: runtime/projection, runtime/terrain_paint, runtime/terrain_relief

- `T.size(map)` (l.35)
- `T.cell(map, x, y)` (l.38)
- `T.chunkSize(map)` (l.44) — Lado del bloque en unidades de mundo.
- `T.grid(image, s)` (l.75) — Columnas, filas y tamaño de cada trozo de `image` para una celda de `s`.
- `T.isPiece(image, s)` (l.85) — ¿La imagen mide un número entero de celdas y ocupa más de una? Es la condición para ofrecerla como pieza en la paleta.
- `T.isTallImage(image)` (l.166) — ¿Esta imagen se pinta como baldosa alta? Más alta que ancha en más de un 5 %.
- `T.cellQuadIndex(tile)` (l.171) — Casilla de una celda, o nil si la celda lleva la imagen entera.
- `T.invalidate(layer, cx, cy, tile)` (l.394) — Marca una celda como cambiada. `tile` es la celda nueva, o `nil` si se borró.
- `T.invalidateLayer(layer)` (l.424) — Tira el caché entero de una capa.
- `T.cacheFor(layer, map)` (l.428)
- `T.draw(map, layer, getImage, bounds)` (l.537) — Dibuja una capa de terreno: sus celdas y, encima, su pintura suave.

## runtime/terrain_paint.lua

Pintura suave del terreno ("texture splatting").

- Tamaño: 309 líneas, 9 funciones públicas, 4 locales.

- `Paint.slotChannel(slot)` (l.119) — Máscara y canal de la textura número `slot` (1..8).
- `Paint.sizeFor(worldW, worldH)` (l.124) — Texel y tamaño de máscara para un mapa de `worldW` x `worldH` píxeles.
- `Paint.new(map)` (l.136) — Pintura vacía para un mapa.
- `Paint.decodeMask(text)` (l.146) — PNG en base64 -> ImageData. Nil si la cadena no es una imagen.
- `Paint.encodeMask(data)` (l.160) — ImageData -> PNG en base64.
- `Paint.state(paint)` (l.185) — Estado vivo de una pintura: `{ data = {..}, images = {..}, dirty }`.
- `Paint.ensureMask(paint, index)` (l.213) — Asegura que exista la máscara número `index` (al pasar de 4 texturas).
- `Paint.commit(paint)` (l.227) — Guarda las máscaras vivas en `paint.masks` (al terminar un trazo).
- `Paint.draw(map, layer, getImage, bounds)` (l.239) — Dibuja la pintura de una capa. `bounds` recorta a la vista (opcional).

## runtime/terrain_relief.lua

Relieve del terreno: colinas, lomas y valles con aspecto low-poly.

- Tamaño: 523 líneas, 11 funciones públicas, 5 locales.
- Usa: runtime/projection, runtime/terrain_paint

- `Relief.new(map, cell)` (l.60) — Relieve plano para un mapa.
- `Relief.state(relief)` (l.79) — Alturas decodificadas de un relieve: `state.bytes[1 + i + j * cols]`.
- `Relief.commit(relief)` (l.96) — Guarda las alturas vivas en `relief.data` (al terminar de esculpir).
- `Relief.touch(relief)` (l.107) — Marca el relieve para rehacer malla y textura en el próximo dibujo.
- `Relief.layerOf(map)` (l.112) — Primera capa del mapa con relieve, o nil.
- `Relief.heightAt(map, x, y)` (l.125) — Altura del terreno (px de mundo) en el punto `x, y`. 0 sin relieve.
- `Relief.maxHeight(map)` (l.153) — Altura máxima del relieve del mapa (para ampliar el recorte de lo visible).
- `Relief.buildVertices(map, relief, bytes, flat)` (l.200) — Vértices de la malla: dos triángulos por celda, con color y luz planos por cara. En isométrico cada vértice va subido lo que mide su altura.
- `Relief.draw(map, layer, getImage, flat)` (l.449) — Dibuja el relieve de una capa, con su pintura encima. Con la transformación de mundo puesta.
- `Relief.beginLift(map)` (l.498) — Desde aquí, lo que se dibuje en coordenadas de mundo se levanta con el relieve (rejilla, celdas, rutas, zonas). Devuelve true si hay relieve.
- `Relief.endLift()` (l.518)

## runtime/transform.lua

Shared geometry for selection, collision drawing and physics export.

- Tamaño: 135 líneas, 7 funciones públicas, 0 locales.

- `T.size(o)` (l.3)
- `T.localPoint(o, x, y)` (l.8)
- `T.contains(o, x, y)` (l.13)
- `T.collider(o)` (l.46) — Geometria del collider en coordenadas del cuerpo, ya escalada.
- `T.colliderOutline(o, x, y, angle, segments)` (l.75) — Contorno del collider en coordenadas de mundo, como lista plana `{x1, y1, x2, y2, ...}`.
- `T.colliderHeight(o)` (l.106) — Elevación y altura de la colisión (píxeles de mundo). Solo se ven en la vista isométrica; la física sigue usando la huella en el suelo.
- `T.colliderPoints(o, out)` (l.119) — Puntos del poligono del collider en coordenadas del cuerpo: escalados por el objeto, girados por `rot` y desplazados por `ox, oy`.

## runtime/ui.lua

Adapter for the vendored MIT-licensed Gooi library. One environment per UI keeps previews, Play sessions and game screens independent of each other.

- Tamaño: 386 líneas, 25 funciones públicas, 4 locales.

- `Ui.new(data)` (l.99)
- `Ui:setData(data)` (l.105)
- `Ui:get(idOrName)` (l.183)
- `Ui:on(idOrName, callback)` (l.186)
- `Ui:setViewport(x, y, w, h)` (l.192) — Uniform scaling preserves the authored layout on different aspect ratios.
- `Ui:layout()` (l.195)
- `Ui:toCanvas(x, y)` (l.206)
- `Ui:clearFocus()` (l.211)
- `Ui:cancelInput()` (l.225)
- `Ui:pressed(id, x, y)` (l.234)
- `Ui:moved(id, x, y)` (l.263)
- `Ui:released(id, x, y)` (l.275)
- `Ui:mousepressed(x, y, button, isTouch)` (l.285)
- `Ui:mousemoved(x, y)` (l.292)
- `Ui:mousereleased(x, y, button, isTouch)` (l.296)
- `Ui:touchpressed(id, x, y)` (l.302)
- `Ui:touchmoved(id, x, y)` (l.305)
- `Ui:touchreleased(id, x, y)` (l.308)
- `Ui:hasTextFocus()` (l.311)
- `Ui:keypressed(key, scancode, isRepeat)` (l.315)
- `Ui:keyreleased(key, scancode)` (l.332)
- `Ui:textinput(text)` (l.337)
- `Ui:update(dt)` (l.346)
- `Ui:draw(rect)` (l.352)
- `Ui:destroy()` (l.375)

## runtime/units.lua

Selección de unidades y órdenes de mover, al estilo de OpenRA.

- Tamaño: 1316 líneas, 62 funciones públicas, 6 locales.
- Usa: runtime/nv/commands, runtime/nv/debug, runtime/nv/group, runtime/projection, runtime/terrain_relief, runtime/transform

- `Units.wrapAngle(a)` (l.82) — Ángulo llevado a (-π, π].
- `Units.turnToward(heading, desired, maxStep)` (l.93) — Gira `heading` hacia `desired` sin pasar de `maxStep` radianes (por el lado corto). Devuelve el rumbo nuevo y el giro aplicado.
- `Units.step(x, y, heading, tx, ty, dt, speed, turnRate, arrive)` (l.123) — Un paso de movimiento cinemático, como el misil.
- `Units.formation(n, spacing)` (l.170) — Desplazamientos de una formación de `n` puestos separados `spacing` px, centrados en (0, 0). Lista de `{x, y}`.
- `Units.destinations(cx, cy, n, spacing)` (l.213) — Destinos absolutos para `n` unidades alrededor de (cx, cy).
- `Units.assign(positions, slots)` (l.224) — Reparto de puestos: cada puesto, del centro hacia fuera, se lo queda la unidad libre más cercana.
- `Units.halfExtents(w, h, angle)` (l.246) — Semiejes del rectángulo alineado que envuelve un sprite girado.
- `Units.new(level, camera, opts)` (l.258) — `opts`: `role`, `playerId`, `speed`, `turn`, `arrive`, `orientacion`, `spacing`, `attackRange`, `selectRadius`, `dragThreshold`, `orderDeadzone`,…
- `Units:isUnit(node)` (l.310) — ¿Es una unidad que este jugador puede seleccionar?
- `Units:units()` (l.325) — Todas las unidades seleccionables, en el orden de dibujo (capas y objetos).
- `Units:speedOf(node)` (l.348) — Velocidad de una unidad: `properties.velocidad`, luego `rts.speed`, luego la de `Units.new`.
- `Units:turnOf(node)` (l.355) — Giro máximo en grados por segundo: `properties.giro`, luego `rts.turn`, luego el de `Units.new`.
- `Units:orientacionOf(node)` (l.362) — Grados que se suman al rumbo para dibujar: `properties.orientacion`, o el de `Units.new`.
- `Units:headingOf(node)` (l.367) — Rumbo actual (radianes) deducido del ángulo del sprite.
- `Units:worldPerPixel()` (l.402) — Píxeles de mundo por píxel de pantalla.
- `Units:toWorld(sx, sy)` (l.411)
- `Units:orderPoint(sx, sy)` (l.420) — Punto de mundo de una orden dada en la pantalla: sobre el minimapa, el punto del mapa que representa; fuera, el que hay bajo el puntero.
- `Units:unitAt(wx, wy, grow)` (l.430) — La unidad de más arriba (la última que se dibuja) bajo el punto de mundo. `grow` = px de mundo extra alrededor del sprite.
- `Units:unitsInRect(x1, y1, x2, y2)` (l.444) — Unidades cuyo rectángulo toca el rectángulo de mundo (x1,y1)-(x2,y2).
- `Units:unitsInScreenRect(x1, y1, x2, y2)` (l.464) — Unidades cuyo punto cae dentro de un rectángulo de la pantalla.
- `Units:selected()` (l.483)
- `Units:isSelected(node)` (l.491)
- `Units:clear()` (l.495)
- `Units:select(list)` (l.501) — Sustituye la selección. Solo entra lo que es una unidad seleccionable.
- `Units:add(list)` (l.506)
- `Units:remove(node)` (l.516)
- `Units:toggle(node)` (l.529)
- `Units:combine(list, isCombine, isClick)` (l.540) — `Selection.Combine` de OpenRA: un clic con Shift alterna la unidad; sin Shift la sustituye (o vacía). Una caja con Shift suma; sin Shift sustituye.
- `Units:spacingFor(nodes)` (l.563) — Separación de la formación para un grupo: `spacing`, o el tamaño de la unidad más grande del grupo si es mayor (el lado mayor de su rectángulo),…
- `Units:attackRangeOf(node)` (l.577) — Alcance de ataque de una unidad: `properties.attackRange`, `properties.alcance`, `rts.attackRange`, o el general de `Units.new`.
- `Units:isAttackTarget(target, attacker)` (l.590)
- `Units:attackTargetAt(wx, wy, grow)` (l.605)
- `Units.attackPoint(node, target, range)` (l.629)
- `Units:setMoveState(node, x, y, queue)` (l.639)
- `Units:setAttackState(node, target, range, x, y, queue)` (l.645)
- `Units:enqueue(node, command)` (l.652)
- `Units:startQueued(node, command, queue)` (l.662)
- `Units:finishOrder(node, state)` (l.669)
- `Units:agentOf(node)` (l.685) — El agente de navegación de una unidad, si su tag tiene red en este nivel.
- `Units:commandSystem()` (l.696) — El `CommandSystem` de NV (se crea con la primera orden), o nil sin redes.
- `Units:order(x, y, list, opts)` (l.717) — Manda las unidades (por defecto las seleccionadas) hacia (x, y) en el mundo, repartidas en formación. Devuelve la lista `{ node, x, y }` de destinos.
- `Units:orderAttack(target, list, opts)` (l.796)
- `Units:stop(node)` (l.841) — Detiene una unidad (o todas las que se mueven) donde esté.
- `Units:isMoving(node)` (l.862)
- `Units:syncNavigationSelection()` (l.868) — LOD de NV: las unidades seleccionadas van siempre a tope aunque estén lejos de la cámara (`NavigationManager:setSelected`).
- `Units:update(dt)` (l.890)
- `Units:playerColor(node)` (l.975) — Color del jugador de una unidad (`map.rts.players`), o el del aro por defecto.
- `Units:dragBox()` (l.990) — Rectángulo de la caja de selección en pantalla, o nil si no es una caja todavía.
- `Units:draw()` (l.1001) — Dentro de `camera:attach()`: aros, marcas de destino y la caja de selección.
- `Units:drawNavigationDebug(zoom)` (l.1061) — Depuración de NV (dentro de la cámara): las rutas de las unidades seleccionadas y lo que pidan los flags de `opts.navigationDebug`.
- `Units:drawHud(x, y)` (l.1105) — Fuera de la cámara: cuántas unidades hay seleccionadas.
- `Units:isShift()` (l.1121)
- `Units:cameraDrags(button)` (l.1130) — ¿La cámara arrastra con este botón? Entonces ese botón es suyo también.
- `Units:mousepressed(x, y, button, isTouch)` (l.1135)
- `Units:mousemoved(x, y, _dx, _dy, isTouch)` (l.1150)
- `Units:mousereleased(x, y, button, isTouch)` (l.1172)
- `Units:touchpressed(id, x, y)` (l.1241) — Táctil: un toque sobre una unidad la selecciona (tocar otra vez la única seleccionada la suelta); un toque en vacío con selección es la orden de…
- `Units:touchmoved(id, x, y)` (l.1261)
- `Units:touchreleased(id, x, y)` (l.1273)
- `Units:keypressed(key)` (l.1292)
- `Units:keyreleased(key)` (l.1299)
- `Units:focus(focused)` (l.1307) — La ventana pierde el foco: se suelta Shift y se cancela lo que estuviera a medias.

## runtime/world.lua

Acceso por nombre a lo que hay en un nivel cargado, al estilo Lua/LÖVE.

- Tamaño: 723 líneas, 38 funciones públicas, 11 locales.
- Usa: runtime/transform

- `Node.__index(node, key)` (l.44)
- `Node.__newindex(node, key, value)` (l.88) — Escribir posicion o angulo mueve tambien el cuerpo fisico, para que el dibujo, las colisiones y el dato no se desincronicen.
- `Node:path()` (l.114)
- `Node:position()` (l.124)
- `Node:move(dx, dy)` (l.128)
- `Node:isA(role)` (l.135) — ¿Es de este tipo? Vale el tipo del objeto, su rol RTS (`unit`, `building`…), su tipo RTS (`tank`, `soldier`…) o su tipo de entidad.
- `Node:hasCollider()` (l.162) — ¿Tiene colisión? (La misma regla con la que el editor la dibuja.)
- `Node:colliderShape()` (l.183) — Forma de la colisión en el mundo: `{ kind = 'circle', x, y, r }` o `{ kind = 'polygon', points = { x1, y1, x2, y2, ... } }`. nil sin colisión.
- `Node:heatPoint()` (l.218) — Centro de la colisión en el mundo: el "punto caliente" al que apunta un buscador de calor. Sin colisión, nil.
- `World.shapesTouch(a, b)` (l.310) — ¿Se tocan las dos formas? Circulos, poligonos (rectangulos girados incluidos, convexos o no) y sus mezclas.
- `Node:touches(other, radius)` (l.334) — ¿Toca la colisión de `other`? Si este objeto no tiene colisión se usa un círculo de `radius` px en su posición (un misil sin forma propia, por…
- `Node:distanceTo(other)` (l.350)
- `Node:destroy()` (l.364)
- `Node:isDestroyed()` (l.409)
- `Folder.__index(folder, key)` (l.417)
- `Folder.__newindex(_, key)` (l.434)
- `Folder.__len(folder)` (l.438)
- `Folder:path()` (l.442)
- `Folder:children()` (l.446)
- `Folder:names()` (l.454)
- `Folder:find(path)` (l.463) — Busca por ruta relativa: folder:find('Ligeros/Tanke'). Devuelve nil si algo del camino falta.
- `Folder:descendants(role)` (l.481) — Recorre todo el subarbol. Con `role`, solo los objetos que cumplen Node:isA(role).
- `WorldMeta.__index(world, key)` (l.501)
- `WorldMeta.__newindex(_, key)` (l.510) — Igual que las carpetas: el arbol se cambia con los objetos, no asignando sobre el.
- `World.new(level)` (l.549)
- `World:rebuild()` (l.558)
- `World:addObject(layer, object)` (l.579)
- `World:_remove(node)` (l.603)
- `World:find(path)` (l.619)
- `World:children()` (l.623)
- `World:names()` (l.627)
- `World:objects(role)` (l.631)
- `World:nodeFor(object)` (l.635)
- `World:spawn(asset, x, y, props)` (l.641) — Crea un objeto durante Play usando la misma ruta del level loader que los objetos guardados en el mapa. Devuelve el Node creado, o nil y el motivo.
- `World:destroy(target)` (l.650) — Atajo para destruir por Node o por ruta (`world:destroy('Capa/Objeto')`).
- `World:hotTargets(kind, exclude)` (l.665) — El objeto mas cercano a `from`, opcionalmente filtrando por rol y por radio maximo. Compara por distancia al cuadrado y solo saca la raiz al final.
- `World:nearest(from, role, maxDistance)` (l.677)
- `World:inRect(x, y, w, h, role)` (l.705) — Los objetos dentro de un rectangulo del mundo (bordes incluidos).


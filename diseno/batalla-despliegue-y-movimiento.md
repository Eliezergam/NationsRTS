# Batalla 3D: fase de despliegue y movimiento de unidades

Encargo del dueño (2026-10-01), pendiente de programar después del daño real.
Está copiado de su mensaje; las preguntas abiertas van al final.

## 1. Movimiento individual durante la batalla

- Cada unidad se selecciona con clic izquierdo.
- **La selección se mantiene al mover la cámara:** con una unidad seleccionada, el jugador puede llevar la cámara a cualquier parte del mapa sin perderla.
- **Orden de movimiento:** al marcar una nueva posición en el terreno, la unidad recibe la orden de ir hasta ese punto.
- **Nunca en línea recta sin más.** La unidad usa la navegación y el cálculo de rutas para:
  - encontrar una ruta válida;
  - evitar obstáculos y zonas intransitables;
  - buscar una ruta eficiente según el terreno;
  - adaptar el recorrido si aparecen obstáculos por el camino.
- Funciona igual para todas las unidades que puedan recibir órdenes de movimiento.
- **Deseleccionar:** doble clic en una zona libre de la pantalla o del terreno.

## 2. Fase de preparación (unos 2 minutos)

- Empieza al entrar en la batalla 3D. El combate está en pausa.
- Durante la preparación, las unidades no pueden:
  - atacar;
  - recibir daño;
  - iniciar enfrentamientos;
  - avanzar solas contra el enemigo.
- El objetivo es que cada jugador organice y coloque su ejército antes de luchar.

## 3. Zona de despliegue (como en Mount & Blade: Bannerlord)

- Cada ejército tiene una zona limitada, marcada en el terreno con un área o un rectángulo.
- Solo se pueden colocar unidades dentro de la zona propia.
- No se puede cruzar el límite durante la preparación, para no colocarse pegado al enemigo.
- Disposición: zona del jugador → zona neutral → zona del enemigo.

## 4. Posicionamiento instantáneo en la preparación

1. El jugador selecciona una unidad.
2. Lleva la cámara hasta el sitio donde la quiere.
3. Marca un punto válido dentro de su zona.
4. La unidad **aparece directamente** en ese punto, sin caminar.

Si el punto cae fuera de la zona, se rechaza.

## 5. Inicio de la batalla

Cuando el contador de unos 2:00 llega a cero:
- se habilita el combate, y las unidades atacan y reciben daño;
- se desactiva el posicionamiento instantáneo y entran las órdenes normales de movimiento (ruta y desplazamiento físico);
- los límites de despliegue dejan de frenar el movimiento.

## Flujo

1. Se entra en la batalla 3D.
2. Preparación de 2 minutos, con el combate bloqueado.
3. Selección individual y colocación instantánea dentro de la zona.
4. Termina el contador.
5. Se bloquea el reposicionamiento y se habilita el combate.
6. Las órdenes calculan ruta y las unidades caminan hasta el destino.

**La lógica de las dos fases va separada:**
- **Preparación:** seleccionar → indicar posición → colocar al instante.
- **Batalla activa:** seleccionar → indicar destino → calcular ruta → desplazarse.

## Decisiones del dueño (2026-10-01)

- **Botón «Listo»:** la batalla empieza antes de los 2 minutos solo cuando **los dos bandos** han pulsado «Listo». El NPC se marca listo cuando termina de formarse; en línea, cada jugador pulsa el suyo. Si no, empieza al acabar el contador.
- **El enemigo NPC también se forma** durante la preparación, con su propia disposición dentro de su zona.
- **Varias unidades:** Mayús + clic añade a la selección, también durante la preparación.
- **Doble clic:**
  - sobre una unidad, selecciona todas las de su mismo tipo (como hoy);
  - en una zona libre, deselecciona.
- **Batallas en marcha:** también tienen preparación. Al entrar en una batalla ya empezada, se vuelve al modo de preparación con los vehículos y soldados que quedan.

- **Girar al desplegar:** sí, arrastrando, como en Bannerlord. Se hace clic en el punto y se arrastra hacia donde debe mirar. Un clic sin arrastrar deja la unidad mirando al enemigo.
- **Formaciones:** de momento hay dos tipos para varias unidades seleccionadas: **en cuadrado** (bloque compacto alrededor del punto) y **esparcidos** (repartidos con más separación). Todas miran hacia el mismo lado.

## Orden de trabajo (pasos pequeños)

1. Fase de preparación: contador de 2:00, zonas marcadas en el terreno, botón «Listo» de los dos bandos y combate bloqueado.
2. Colocación instantánea dentro de la zona: giro arrastrando, Mayús + clic, doble clic y las dos formaciones.
3. Batalla activa: órdenes de movimiento con cálculo de ruta. Diseño propio
   (inspirado en 0 A.D., sin su código) en
   [movimiento-unidades-batalla.md](movimiento-unidades-batalla.md): cuadrícula
   de pasabilidad, buscadores largo y corto, seguimiento sin atascos,
   empujones, cola de órdenes y las dos formaciones.
4. El NPC se forma en su zona y, al empezar, avanza con un plan.

## Línea de movimiento y marca de selección (el dueño, 2026-10-01)

- **Línea de la orden de movimiento:** propuesta **2, cinta de rejilla holográfica** (sirve para todas las unidades). Es una cinta con dos bordes de luz, un barrido de líneas transversales que avanza y flechas macizas cada pocos metros hacia el destino. Nace en la unidad, se acorta mientras avanza y desaparece al llegar. Sustituye a la 8 (huellas de oruga), que había elegido antes.
- **Marca de selección:** propuesta **10, anillo de datos**. Es un anillo en el suelo con la vida como arco, marcas de datos que giran y el modelo y el número de la unidad debajo. Entra con una animación corta y se queda en reposo animado mientras la unidad sigue seleccionada.
- **El mismo color en las dos:** verde menta holográfico (#6DFFC4), con brillo suave. El arco de la vida cambia de color según el daño: menta por encima del 60 %, amarillo (#FFD15C) entre el 30 y el 60 %, y rojo (#FF5A5A) por debajo del 30 %.
- Las propuestas animadas están en los artifacts «Rutas de avance» (claude.ai/artifact/Sa7YdogdU2F34FQ31kNtgi) y «Selección holográfica» (claude.ai/artifact/QFC4DfbXaLqiFLaMDurFSz).

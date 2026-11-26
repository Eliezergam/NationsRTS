# Almacén y abastecimiento de misiles

Ideas y decisiones del dueño del 2026-11-16. Estado: **prototipo**. Lo
marcado «hoy» está en el código; lo marcado «idea» aún no.

## Qué es

- El almacén es **un sitio aparte, en otro mapa**: no está en el mapa del
  mundo y **solo se ve por dentro**.
- Es una nave de 105 × 30 m con cuatro zonas: fábrica de misiles, polvorín,
  racks de suministros y plazas de vehículos. El modelo sale de
  `tools/blender/almacen_interior.py`.
- **Los misiles que hay aquí son los que se usan en batalla.** Si el almacén
  está vacío, en batalla no hay qué disparar.
- Los misiles se guardan en el polvorín, cada uno en su contenedor numerado
  (M-001…). Caben 60, en bastidores de 3 alturas, con un contador encima del
  portón.

## Hoy (en el código)

- **Botón «Almacén»** en la barra de abajo del mapa: entra en la nave en 3D.
  - Se recorre con la cámara de vuelo de la batalla: W A S D, Espacio y Ctrl
    para subir y bajar, botón derecho para mirar, Shift para ir rápido.
  - Esc vuelve al mapa.
  - Código: `almacen/escena.lua`.
- **Luz** como el ejemplo AlphaBlending de 3DreamEngine:
  - cada foco es una luz puntual con sombra suave (el motor usa las 16 más
    cercanas a la cámara);
  - un sol entra por los lucernarios;
  - un cielo HDR bajo y un cubo de luz rebotada dan la luz ambiente.
- **Sonido:** un rumor industrial grave en bucle mientras estás dentro
  (`assets/sonidos/almacen/ambiente.ogg`, CC0, elegido por el dueño entre 4).
- **Sala de control** (maqueta aprobada el 2026-11-16), acristalada, en las
  primeras plazas del lado +y: 6 puestos con 3 monitores, muro de 6
  pantallas, 4 armarios de servidores con luces y bandeja de cables.
  - **Regla del dueño: todo lo que enseñan las pantallas sale de la
    partida, nada inventado.** El mapa del muro es la excepción pedida por él:
    una imagen fija (`assets/almacen/mapa_capital.png`, captura del mapa 2D
    de la capital con la semilla 42).
  - Pantallas del muro: la nación (nombre, capital, habitantes, poder,
    nivel, año y día, metal, petróleo, comida y dinero, con las mismas
    cifras que la barra de arriba) y los misiles del almacén.
  - Monitores: polvorín (misiles y huecos), recursos y noticias de la
    partida, en otro orden en cada puesto.
  - Código: `almacen/sala.lua` (pinta) y `almacen/partida.lua` (lee los
    datos, por `Almacen:getPartida()`).
- **Robot de ruedas con brazos** (foto del dueño, 2026-11-16): base de dos
  ruedas, pierna con rodilla, torso, cabeza con cámaras y dos brazos con
  pinzas paralelas para manipular cosas pequeñas. Da una vuelta por el
  almacén (sala de control → polvorín → racks) con gestos en cada parada.
  - Se programa como el lanzamisiles: piezas por capas y scripts
    (`almacen/robots/`, API en `almacen/robots/API.md`).
  - Modelo: `tools/blender/robot_almacen.py --glb`.
  - **Idea:** un robot pesado aparte para mover los misiles (este no puede:
    un misil pesa toneladas).
- **Misiles contados** en la simulación, por nación:
  - `e.almacenes[nación] = { misiles }`, guardado en la partida (versión 29);
  - cada nación empieza con 40 mientras la fábrica no lo llena sola;
  - código: `mundo/simulacion/almacen.lua`.
- **Se ven tantos contenedores como misiles**, y el contador los sigue.
- **Para los scripts:** el objeto global `Almacen`, con el mismo estilo que
  los vehículos (`almacen/API.md`):

  ```lua
  local almacen = Almacen.getDelJugador()
  if almacen and almacen:getMisiles() == 0 then
      -- no hay misiles: no se dispara
  end
  ```

## Idea: camiones de abastecimiento (aún no está)

Lógica de prototipo; no importa que se vea poco real:

1. En batalla, cuando un lanzamisiles necesita misiles, **aparecen camiones
   cargados** con misiles del almacén.
2. Salen de **un punto detrás de las demás unidades** de su bando: aparecen
   (spawn) ahí.
3. **Van por el suelo** hasta donde está cada lanzamisiles.
4. Al llegar, **el lanzamisiles se carga solo**.
5. Los misiles que llevan salen del almacén: si el almacén está vacío, no sale
   ningún camión.

Por decidir cuando se programe: cuántos misiles lleva cada camión, si el
camión vuelve o desaparece, y qué pasa si lo destruyen por el camino.

## Pendiente

- El lanzamisiles aún no mira el almacén: hoy dispara como antes.
- La fábrica no llena el polvorín.
- Las señales de seguridad de la fábrica.
- El arsenal es por nación: cuando exista la compañía (PMC) en la
  simulación, pasará a ser de la compañía.

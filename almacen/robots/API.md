# API de los robots del almacén

Igual que los vehículos de la batalla (`batalla/vehiculos/API.md`): el robot
tiene **piezas** que se mueven por capas y **scripts** (especializaciones) que
las mueven. **`get...` devuelve algo** y no cambia nada; **`set...` cambia
algo** y no devuelve nada. Todas con `:`.

```lua
local robot = GestorRobots.getRobots()[1]
robot:setIrA(-25.5, 0, math.pi)      -- va con sus ruedas y al llegar mira a -x
robot:setMirarA(-29.6, 0, 7.4)       -- mira al contador del polvorín
robot:setBrazo('der', 1.6, 0.15, -0.2, 0)  -- levanta el brazo derecho
robot:setPinza('der', 0.08)          -- abre la pinza derecha 8 cm
```

Medidas del almacén: **metros**; ejes del almacén (los del modelo de
Blender): **x** a lo largo de la nave (los portones en +30), **y** a lo
ancho, **z** arriba; ángulos en **radianes**, rumbo 0 = hacia +x.

`GestorRobots` es global, como `GestorVehiculos`: no hace falta `require`.

## Un script nuevo

1. Crea `almacen/robots/especializaciones/miScript.lua` (copia
   `patrulla.lua`, que es un ejemplo hecho solo con las órdenes de abajo).
2. Pon `'miScript'` en la lista de `almacen/robots/tipos/robotAlmacen.lua`.
3. Lo que guarde tu script va en `self.datos.miScript`.

Funciones que llama el motor (las que no tengas no se llaman):

| Función | Cuándo |
|---|---|
| `MiScript:prerequisitos()` | Al crear el robot. `false`: no se usa. |
| `MiScript:onLoad()` | Una vez, al crear el robot. |
| `MiScript:onUpdate(dt)` | Cada cuadro. Relojes, decisiones, órdenes. |
| `MiScript:onPose()` | Justo antes de colocar las piezas: gira y mueve aquí. |

## Encontrar robots

| Función | Devuelve |
|---|---|
| `GestorRobots.getRobots()` | todos los robots del almacén |
| `GestorRobots.crear(tipo, x, y, rumbo)` | crea uno (`'robotAlmacen'`) |

## El robot

### Dónde está

| Función | Devuelve |
|---|---|
| `robot:getNombreTipo()` | `'robotAlmacen'` |
| `robot:getPosicion()` | `x, y` del centro de la base |
| `robot:getRumbo()` | hacia dónde mira |
| `robot:getVelocidad()` | m/s hacia delante |
| `robot:getGiroVelocidad()` | rad/s que gira |
| `robot:getTieneEspecializacion(nombre)` | `true` si lleva ese script |

### Ir (script `conduccion`)

Base de dos ruedas motrices: si no mira hacia el destino gira sobre sí mismo;
si mira, avanza corrigiendo y frena a tiempo. Velocidad máxima 1,1 m/s.

| Función | Qué hace / devuelve |
|---|---|
| `robot:setIrA(x, y, rumboFinal)` | va a (x, y); con `rumboFinal`, al llegar gira hasta él |
| `robot:setParar()` | frena y se queda |
| `robot:setPosicion(x, y, rumbo)` | lo pone ahí de golpe (sin conducir) |
| `robot:getHaLlegado()` | `true` si no tiene adónde ir y está parado |
| `robot:getDestino()` | `x, y` (nil si no va a ningún sitio) |

### Mirar (script `mirada`)

| Función | Qué hace / devuelve |
|---|---|
| `robot:setMirarA(x, y, z)` | gira cuello y cabeza hacia ese punto; `nil`: hacia delante |
| `robot:getMirandoA()` | `x, y, z` (nil si mira hacia delante) |

### Brazos y cuerpo (script `brazos`)

Cada articulación va hacia el ángulo pedido a 1,6 rad/s, como un servo. Todo
a 0 es la pose de la foto.

| Función | Qué hace / devuelve |
|---|---|
| `robot:setBrazo(lado, hombro, abrir, codo, munieca)` | `lado` `'izq'`/`'der'`; `hombro` > 0 sube el brazo hacia delante, `abrir` > 0 lo separa del cuerpo, `codo` > 0 lo dobla, `munieca` gira la mano; `nil` deja ese igual |
| `robot:getBrazo(lado)` | `hombro, abrir, codo, munieca` de ahora |
| `robot:setAgachar(f)` | 0 de pie … 1 agachado (dobla cadera y rodilla; el torso sigue derecho) |
| `robot:setGirarCintura(a)` | gira el torso sobre la cintura (> 0 a la izquierda) |

### Pinzas (script `pinzas`)

Manos de tres dedos (como la Robotiq 3-Finger): dos dedos a un lado y uno enfrente; cierran con las puntas paralelas.

| Función | Qué hace / devuelve |
|---|---|
| `robot:setPinza(lado, apertura)` | metros entre las gomas, de 0 (cerrada) a 0,1 |
| `robot:getPinza(lado)` | la apertura de ahora |
| `robot:getPuntoAgarre(lado)` | `x, y, z` del punto entre las yemas (donde irá lo que coja) |

### Sus piezas

| Función | Devuelve |
|---|---|
| `robot:getPieza(nombre)` | la pieza (error si no existe) |
| `robot:getTienePieza(nombre)` | `true` si la tiene |
| `robot:getNombresPiezas()` | todos los nombres |

Piezas: `robot` (eje de las ruedas y cubo de la cadera), `ruedaIzq`,
`ruedaDer`, `espinilla` (cadera), `muslo` (rodilla), `torso` (cintura),
`cuello`, `cabeza`, y por lado (`Izq`/`Der`): `ojo` (globo del ojo; dentro `anillo` y `diafragma`, que giran), `parpado`,
`hombro`, `brazo`, `codo`, `munieca`, `dedo…A/B/C` (falanges), `punta…A/B/C`,
`agarre…` (vacío, sin malla).

## Las piezas (`local codo = robot:getPieza('codoDer')`)

| Función | Qué hace / devuelve |
|---|---|
| `pieza:setGiro(eje, angulo, capa)` | gira sobre su eje `'x'`, `'y'` o `'z'` en su pivote (tu capa; `capa` opcional para tener varias) |
| `pieza:setDesplazamiento(x, y, z, capa)` | la desplaza (metros, en sus ejes) |
| `pieza:setVisible(visible)` | la oculta o la muestra (con sus hijas) |
| `pieza:getPosicion()` | `x, y, z` de su pivote en el almacén |
| `pieza:getPunto(x, y, z)` | un punto de la pieza en el almacén |
| `pieza:getMatriz()` | su matriz en el almacén (4x4 por filas; solo leer) |
| `pieza:getGiro(capa, script)` | `eje, angulo` de una capa |
| `pieza:getPadre()` / `pieza:getHijas()` | de quién cuelga / quién cuelga de ella |

## Scripts que ya lleva

`conduccion`, `mirada`, `brazos`, `pinzas`, `reposo` (se mece un poco
quieto) y `patrulla` (la vuelta de ejemplo: sala de control → polvorín →
racks). Sus números están arriba de cada archivo.

Aún no hay: coger objetos (`setCoger`), esquivar obstáculos y sombras del
robot (las de la nave son fijas).

## Almacenaje (`especializaciones/almacenaje.lua`)

El trabajo del robot: lo que llega al patio de descarga (pacas de dinero,
cajas de comida y de obuses) lo guarda en su rack del anexo. Mira las mesas
del patio (el lidar las encuentra, los ojos miran cada hueco), busca con los
ojos el cartel de lo suyo (DINERO, MUNICIÓN, COMIDA) y rellena los racks en
orden: el del cartel 1 primero, abajo de un lado al otro y luego arriba.

| Función | Qué hace / devuelve |
|---|---|
| `robot:setTrabajar(si)` | empieza (`true`, lo hace solo) o para |
| `robot:getTrabajando()` | `true` mientras trabaja |
| `robot:getGuardados()` | cuántas cosas ha guardado |
| `robot:getConocidos()` | lo que ha visto con los ojos: `{ [objeto] = cuándo }` |
| `robot:getCarteles()` | carteles leídos: `{ { tipo, x, y, z, n } }` |
| `robot:getObjetosLidar()` | lo que ha tocado el lidar: `{ [objeto] = true }` |

## Robot grande (`robotPesado`)

Tipo `almacen/robots/tipos/robotPesado.lua` (modelo `assets/almacen/robot_pesado.glb`,
`tools/blender/robot_pesado.py --glb`). Especializaciones: lidar, conduccion (con sus
`ajustes`), orugas, mirada, brazosPesado, acarreo.

| Orden | Qué hace |
|---|---|
| `robot:setAlcanzar(lado, x, y, z)` | lleva la garra `'izq'`/`'der'` a un punto del almacén (nil: reposo) |
| `robot:setAlcanzarEnRobot(lado, adelante, alto)` | la garra a un punto del robot (va con él al moverse) |
| `robot:setGarra(lado, apertura)` | 0 cerrada .. 1 abierta |
| `robot:setGiroGarra(lado, angulo)` | gira la muñeca (pi/2: las uñas cierran de arriba abajo) |
| `robot:setCogerConGarra(lado, objeto)` / `setSoltarDeGarra(lado)` | cuelga o suelta lo que coge |
| `robot:getGarraLista(lado)` | true si el brazo y la garra llegaron |
| `robot:getRodadoOrugas()` | metros que ha rodado cada oruga |

Puntos de agarre para las garras (`mano = 'garra'` en `getPuntosAgarre()`): el bidón de
petróleo (`cuerpo`, redondo), el contenedor de misil (`costadoA`/`costadoB`, a 2,44 m,
`giroGarra = pi/2`) y el misil suelto (tipo `misil`, `cuerpoA`/`cuerpoB`).
`robot:getAjustes(nombre)` da los números de una especialización con los del tipo.

# API de los vehículos

Todo lo que puedes usar en un script de vehículo (una especialización). Las
mismas explicaciones salen en VSCodium al escribir y al pasar el ratón.

Como en Farming Simulator, las funciones del script se escriben con `:` y
**`self` es el vehículo**: `self:getPosicion()`, `self:getPieza('rampaLanzador')`,
`self.datos.miScript`. En las tablas de abajo, `vehiculo:` es lo mismo que
`self:` dentro de tu script.

Nombres, como en Farming Simulator: **`get...` devuelve algo** (no cambia
nada) y **`set...` cambia algo** (no devuelve nada). Todas con `:`.

```lua
local x, y, z = self:getPosicion()      -- get: devuelve
local rampa = self:getPieza('rampaLanzador')
rampa:setGiro('y', math.rad(10))        -- set: cambia
rampa:setVisible(false)
```

Medidas del juego: **1 px = 10 cm**; ángulos en **radianes**
(`math.rad(35)` pasa grados a radianes); ejes **x** hacia delante,
**y** a la izquierda, **z** arriba.

## Un script nuevo

1. Crea `batalla/vehiculos/especializaciones/miScript.lua`.
2. Escribe `especializacion` y pulsa Tab: se rellena la plantilla.
3. Añade `'miScript'` a la lista de su tipo, en
   `batalla/vehiculos/tipos/camionLanzamisiles.lua`.

El nombre entre comillas de `registrarEspecializacion('miScript', MiScript)`
es el del archivo. Lo que guarde tu script va en `self.datos.miScript`.

La primera línea, `---@class MiScript : Especializacion, Vehiculo`, es para
el editor: le dice que `self` es el vehículo.

Las funciones tuyas que no son del motor se llaman con la tabla y `self`:
`MiScript.calcular(self)`, no `self:calcular()` (`self` es el vehículo, que no
las tiene).

## Funciones que llama el motor

Las pones en la tabla de tu script; las que no tengas no se llaman.

| Función | Cuándo |
|---|---|
| `MiScript:prerequisitos()` | Al crear el vehículo. Devuelve `true` si el script puede ir en él; con `false` no se usa. |
| `MiScript:onLoad()` | Una vez, al crear el vehículo. Prepara tus datos y piezas. Aquí las piezas aún no tienen sitio en el mundo (`pieza:getPosicion()` no vale todavía). |
| `MiScript:onUpdate(dt)` | En cada paso de la batalla. `dt`: segundos del paso (en pausa el tiempo no avanza). Lleva aquí tus relojes y cálculos. |
| `MiScript:onPose()` | Justo antes de colocar las piezas. Gira, mueve u oculta aquí. |

Orden en cada paso: `onUpdate` de todos los scripts, después `onPose` de
todos. Entre scripts, el orden de la lista del tipo.

## Fases (`vehiculo:getFase()`)

| Fase | Qué hace el camión |
|---|---|
| `'despliegue'` | Al empezar la batalla: avanza un poco hacia su sitio. |
| `'orden'` | Va adonde se le ha mandado. |
| `'frenando'` | Ha llegado: frena hasta quedarse quieto. |
| `'espera'` | Parado, rampa abajo y gatos recogidos, esperando un blanco. |
| `'apoyando'` | Baja los gatos (`vehiculo:getGatos()` va de 0 a 1). |
| `'subiendo'` | Sube la rampa (`vehiculo:getElevacion()` va de 0 a 35). |
| `'fuego'` | Rampa arriba: dispara los misiles de uno en uno. |
| `'bajando'` | Baja la rampa y recoge los gatos. |
| `'recarga'` | Rampa abajo: carga misiles en la rampa. |

Ciclo normal: `despliegue` → `frenando` → `espera` → `apoyando` → `subiendo`
→ `fuego` → `bajando` → `recarga` → `espera`... Si un tanque enemigo se acerca
o el camión se mueve mientras prepara el disparo, pasa a `bajando`.

## El vehículo (`vehiculo`)

### Qué es

| Función | Devuelve |
|---|---|
| `vehiculo:getNombreTipo()` | `'camionLanzamisiles'`... |
| `vehiculo:getBando()` | 1 o 2 |
| `vehiculo:getNumero()` | su orden de entrada en el bando |
| `vehiculo:getTieneEspecializacion(nombre)` | `true` si lleva ese script |
| `vehiculo:getContrato(nombre)` | una tabla del modelo: `'gatos'`, `'suspensiones'`, `'ruedas'`, `'ventiladores'`, `'apuntan'`, `'puntos'`, `'misiles'`, `'bocas'`, `'rampa'`, `'puertas'`, `'elevacion'` (nil si no la tiene) |

### Su estado (solo leer)

| Función | Devuelve |
|---|---|
| `vehiculo:getPosicion()` | `x, y, z` en el mundo (px) |
| `vehiculo:getRumbo()` | hacia dónde mira (radianes) |
| `vehiculo:getVelocidad()` | px por segundo |
| `vehiculo:getSeHaMovido()` | `true` si se movió o giró desde el paso anterior |
| `vehiculo:getVivo()` | `true` si no está destruido |
| `vehiculo:getFase()` | una de las fases de arriba |
| `vehiculo:getElevacion()` | grados de la rampa que pide la simulación (0 a 35) |
| `vehiculo:getGatos()` | 0 recogidos ... 1 apoyados |
| `vehiculo:getMisilesCargados()` | misiles que quedan en la rampa (0 a 4) |
| `vehiculo:getOrdenMisiles()` | nombres de los misiles en el orden en que salen |

### El mundo

| Función | Devuelve |
|---|---|
| `vehiculo:getAlturaSuelo(x, y)` | altura del terreno en ese punto del mundo |
| `vehiculo:getPuntoMundo(x, y, z)` | `x, y, z` en el mundo de un punto del vehículo (en reposo) |
| `vehiculo:getCasco()` | la matriz del casco de la física (4x4, solo leer) |

### El chasis

El chasis es todo lo que se dibuja encima de la física: cabina, rampa, gatos...

| Función | Qué hace |
|---|---|
| `vehiculo:setInclinacionChasis(altura, cabeceo, balanceo)` | lo sube (px) y lo gira (radianes; cabeceo negativo sube el frente). Cada script tiene su capa y se suman. Las ruedas siguen en el suelo. |
| `vehiculo:getChasis()` | `altura, cabeceo, balanceo` de todas las capas |
| `vehiculo:getChasisDeOtros()` | lo mismo sin la capa de tu script |
| `vehiculo:getCentroChasis()` | `x` del punto sobre el que cabecea |

### Sus piezas

| Función | Devuelve |
|---|---|
| `vehiculo:getPieza(nombre)` | la pieza (error si no existe) |
| `vehiculo:getTienePieza(nombre)` | `true` si el modelo la tiene |
| `vehiculo:getNombresPiezas()` | todos los nombres |
| `vehiculo:getPiezas()` | todas las piezas |

## Las piezas (`local rampa = self:getPieza('rampaLanzador')`)

### Cambiarla

Cada script tiene su propia capa en la pieza: `setGiro` y `setDesplazamiento`
sustituyen lo de tu capa y las capas de todos se suman. Las hijas siguen a la
pieza.

| Función | Qué hace |
|---|---|
| `pieza:setGiro(eje, angulo, capa)` | gira `angulo` radianes sobre su eje `'x'`, `'y'` o `'z'`, en su pivote. `capa` (opcional) para tener varias en el mismo script. |
| `pieza:setDesplazamiento(x, y, z, capa)` | la desplaza (px) desde su sitio |
| `pieza:setVisible(visible)` | `false` la oculta, `true` la vuelve a mostrar. No se dibuja mientras algún script la tenga oculta. |
| `pieza:setApuntarA(destino, x, y, z)` | la gira para que mire siempre al punto `(x, y, z)` de la pieza `destino` (sin punto, a su pivote), como el «Track To» de Blender |
| `pieza:setApuntarA(nil)` | deja de mirar a su destino |

### Leerla

| Función | Devuelve |
|---|---|
| `pieza.nombre` | su nombre |
| `pieza:getPadre()` / `pieza:getHijas()` | la pieza de la que cuelga / las que cuelgan de ella |
| `pieza:getPivote()` | `x, y, z` del pivote, relativo a su padre |
| `pieza:getPivoteVehiculo()` | `x, y, z` del pivote en el vehículo, en reposo |
| `pieza:getPosicion()` | `x, y, z` en el mundo (no en `onLoad`) |
| `pieza:getRotacion()` | `rumbo, cabeceo, balanceo` en el mundo (no en `onLoad`) |
| `pieza:getMatriz()` | su matriz en el mundo (4x4, solo leer) |
| `pieza:getTamano()` | `largo, ancho, alto` (px) |
| `pieza:getCaja()` | `minX, minY, minZ, maxX, maxY, maxZ` alrededor del pivote |
| `pieza:getVisible()` | `true` si se dibuja |
| `pieza:getGiro(capa, script)` | `eje, angulo` de una capa (la tuya, o la de otro script: `rueda:getGiro('rodar', 'ruedas')`) |
| `pieza:getDesplazamiento(capa, script)` | `x, y, z` de una capa |
| `pieza:getApuntarA()` | `destino, x, y, z` (nil si no apunta) |

### Piezas del camión lanzamisiles

- Cuerpo: `chasis`, `insignia`, `puertaIzquierda`, `puertaDerecha`, `balizaLuz`,
  `ventiladorRadiadorIzquierdo`, `ventiladorRadiadorDerecho`
- Rampa: `rampaLanzador`, `pistonRampaBase`, `pistonRampaVastago`,
  `misilExteriorIzquierdo`, `misilExteriorDerecho`, `misilInteriorIzquierdo`,
  `misilInteriorDerecho`
- Gatos: `gato` + `Delantera`/`Trasera` + `Izquierda`/`Derecha`
  (`gatoDelanteraIzquierda`...)
- Ruedas, suspensiones: `rueda` / `suspension` + `Delantera`/`Media`/`Trasera`/`Ultima`
  + `Izquierda`/`Derecha` (`ruedaMediaDerecha`, `suspensionUltimaIzquierda`...)
- Amortiguadores: `amortiguador` + eje + lado + `Cuerpo`/`Vastago`
  (`amortiguadorTraseraDerechaVastago`...)

## Encontrar vehículos desde cualquier script

| Función | Devuelve |
|---|---|
| `GestorVehiculos.getVehiculos()` | todos los de la batalla, por bando y número |
| `GestorVehiculos.getPorTipo('camionLanzamisiles')` | los de ese tipo |
| `GestorVehiculos.getDeUnidad(unidad)` | el de una unidad (nil si no tiene) |

## Scripts que ya lleva el camión

`suspension`, `estremecimiento`, `ruedas`, `hidraulicos`, `ventiladores`,
`gatos`, `rampa`, `misiles`, `baliza`: están en
`batalla/vehiculos/especializaciones/` y sirven de ejemplo. Sus números
(fuerza del temblor, parpadeo de la luz...) están arriba de cada archivo.

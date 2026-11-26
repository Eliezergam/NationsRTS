# Nations RTS: arquitectura pensada para jugar en línea y sin internet

El objetivo es el de No Man's Sky: un mundo infinito, igual para todos, que se
juega solo o compartido con otros jugadores a través de un servidor.

## Dos mundos: el físico y el vivo

| | Mundo físico | Mundo vivo |
|---|---|---|
| Qué es | Terreno, plantas, ciudades, calles, depósitos | Naciones, ejércitos, guerras, recursos, relaciones, noticias |
| De dónde sale | De la semilla (`mundo/terreno.lua`, `plantas.lua`, `ciudades.lua`, `recursos.lua`) | De la simulación (`mundo/simulacion.lua`) |
| Se guarda | Nunca: cada máquina lo genera idéntico | Sí: `Simulacion:guardar()` es texto con solo datos |
| Viaja por la red | Solo la semilla | El estado o sus cambios |

Las ciudades y los depósitos tienen un identificador que sale de su región del
mundo (`'rx,ry'` y `'rx,ry#k'`). Es el mismo en todas las máquinas, así que el
estado vivo siempre sabe a qué ciudad física se refiere.

## La simulación es determinista

`Simulacion:avanzarDia()` da siempre el mismo resultado para el mismo estado:

- el azar sale de `Ruido.hash(semilla, día, ...)`, nunca de `math.random`;
- todo se recorre en orden fijo (`Simulacion.ordenadas`), nunca con `pairs` sin ordenar;
- no usa LÖVE: corre igual en un servidor con LuaJIT.

Comprobado: dos simulaciones iguales acaban en el mismo estado exacto, y guardar
a mitad de camino, cargar y seguir da lo mismo que no parar.

## Todo cambio es un comando

`Simulacion:ejecutar({ tipo = ..., ... })` es la única entrada desde fuera:
`declararGuerra`, `enviarEjercito`, `ataqueAereo`, `firmarArmisticio`. Hoy los
usa la IA de los gobernantes. Mañana los mandarán también los jugadores, por la
misma vía.

## Cómo encaja el servidor

1. **Sin internet:** el juego corre la simulación en local y guarda el estado en un archivo (F5 y F9 en la demo).
2. **En línea:** el servidor corre la misma simulación y es la autoridad. Los clientes le mandan comandos con el día en que ocurren. El servidor los aplica en orden y reparte el estado o sus cambios.
3. **Encontrarse con otros:** como el mundo físico sale de la semilla, dos jugadores en el mismo sitio ven lo mismo. Solo hay que sincronizar lo vivo.
4. **Volver a conectarse:** el cliente descarga el estado del servidor y sigue. Su partida local puede subirse como propuesta, igual que hace No Man's Sky con los descubrimientos.

## El modelo de guerra

- **Naciones por zonas:** cada zona de 3×3 regiones es una nación. Su ciudad más grande es la capital y las demás le pertenecen. Al descubrir una ciudad entra su nación entera y las vecinas.
- **Instalaciones:** convoyes que abren carretera y levantan complejos de extracción sobre los depósitos, y bases militares hacia los vecinos. La fortificación crece un año hasta el máximo.
- **Guerra:** contra instalaciones y bases, no contra ciudades. Hay grupos en misión, salvas de hasta un centenar de misiles contra interceptores, incursiones aéreas contra cazas, y refuerzos del atacado.
- **Ciudades:** golpes sueltos cada 2 a 20 días. Cada uno es un crimen de guerra. Solo cambian de manos cedidas en un tratado.
- **Presidentes:** alternan días de tensión y de calma. Negocian según el cansancio de guerra: alto el fuego, paz con concesiones, o fracaso.

## Lo que falta para el servidor

- Un protocolo de red: comandos hacia arriba, estado o cambios hacia abajo.
- Simular también las regiones que nadie está mirando pero que algún jugador ya descubrió (hoy solo cuentan las descubiertas en esta máquina).
- La lógica del jugador: su ciudad, sus soldados y sus órdenes, que serán comandos más.

## Los sistemas y cómo se hablan (estado del 26-nov)

El juego tiene cuatro escenas que se turnan en `main.lua` y una simulación
que no se para nunca:

```
                 ┌──────────────────────────────────────────────┐
                 │  SIMULACIÓN  mundo/simulacion.lua (+ 22 en    │
                 │  mundo/simulacion/): naciones, guerras,       │
                 │  almacenes, misiles… determinista, sin LÖVE   │
                 └───────▲───────────────────────────┬──────────┘
          órdenes        │ ejecutar({ tipo = … })    │ se lee sim.estado
   (las únicas que       │                           │ (solo lectura)
    cambian algo)        │                           ▼
 ┌────────────┬──────────┴──┬──────────────┬───────────────┐
 │ MAPA       │ BATALLA 3D  │ ALMACÉN 3D   │ CAMPAÑA 3D    │
 │ mundo/ +   │ batalla/    │ almacen/     │ campana/      │
 │ interfaz/  │             │              │               │
 └────────────┴──────┬──────┴──────┬───────┴───────────────┘
                     │             │
                     ▼             ▼
              robots/ (núcleo común de los robots: piezas, especializaciones)
              batalla/dream/ (dibujo 3D con 3DreamEngine: lo usan batalla,
              almacén e interfaz)
```

### Quién es dueño de cada dato

| Dato | Dueño | Cómo lo cambian los demás | Dónde se guarda |
|---|---|---|---|
| Terreno, ciudades, yacimientos | La semilla (`mundo/`) | Nadie: se genera igual en cada máquina | No se guarda |
| Naciones, guerras, grupos, territorio, dinero, recursos del almacén, misiles | La simulación | Órdenes `ejecutar({ tipo = … })`: hay 31 desde fuera (interfaz, batalla, almacén, main) | `partida.lua`, parte `sim` |
| Resultado de una batalla | La batalla 3D mientras dura | Al salir, la orden `resolverBatalla` devuelve bajas y heridos a la simulación | En la simulación |
| Almacén de cada nación para los guiones | La simulación | `Almacen` (global, `almacen/almacen.lua`): `get…` lee y `set…` manda órdenes | En la simulación |
| Dónde está cada caja del almacén 3D | La escena del almacén | Directo, sin órdenes (`almacen/memoria.lua`) | `partida.lua`, sección `almacen` |
| Ordenadores de la sala (ventanas, carpeta personal, muro) | `almacen/pc/` | Directo, sin órdenes (`almacen/memoria.lua`) | `partida.lua`, sección `almacen` |
| Quién es el jugador (su nación y capitales) | `main.lua` | Al empezar (`escenarioPrueba`) | `partida.lua`, sección `jugador` |
| Lo que aprenden los robots | `robots/conocimiento.lua` | Directo | Archivos JSON propios |
| Ajustes del jugador | `interfaz/ajustes.lua` | Directo | Su archivo |

Comprobado en el código: fuera de la simulación nadie asigna en
`sim.estado`, y casi todo lo que cambia el mundo vivo pasa por `ejecutar`.
Hay dos excepciones: `sim:noticia(...)` desde `main.lua` e
`interfaz/pendon.lua` (avisos de pantalla como «Partida guardada» que acaban
dentro del estado guardado) y `Ayudas.cambiarRelacion` en la tecla G de
`main.lua` (provocar una guerra de prueba). Las
lecturas directas de `sim.estado` sí están repartidas: unas 59 en la
interfaz, 59 en `main.lua`, 8 en la batalla y 6 en el almacén.

### El guardado

Una partida es un solo archivo, `partida.lua` (`partida/guardado.lua`): el
mundo vivo de la simulación (`sim`) y una sección por cada sistema que tiene
algo propio que guardar (`secciones`), registrada con
`Partida.registrar(nombre, guardar, cargar)`. Todo con el serializador de la
simulación. Se escribe en un archivo nuevo que luego ocupa el sitio del
viejo (el anterior queda como `partida.anterior.lua`).

Se guarda sola cada 5 minutos, al salir del almacén o de una batalla y al
cerrar el juego, y al abrirlo (pantalla de inicio → Invitado) sigue esa
partida. F5 y F9 guardan y cargan a mano. Las pruebas y las capturas (todo lo
que no abre en la pantalla de inicio) no guardan nada.

### Las escenas

- **Mapa** (`main.lua`, `mundo/`, `interfaz/`): el mundo isométrico, los
  paneles y la IA de los gobernantes. `main.lua` hace de director: carga,
  actualiza y dibuja la escena que toca y reparte el teclado y el ratón.
- **Batalla 3D** (`batalla/`): `Escena.nueva(mundo, combate)` la crea a partir
  de una batalla de la simulación; mientras dura, la simulación sigue más
  lenta (`RITMO_BATALLA`). Física con Jolt (`batalla/robots/fisica.lua`).
- **Almacén 3D** (`almacen/`): la nave de la nación del jugador, sus robots,
  la fábrica de misiles y la sala de control con sus ordenadores
  (`almacen/pc/`). Los archivos de la red de los ordenadores leen la partida
  en vivo.
- **Campaña 3D** (`campana/`): el mapa en relieve.

### Los robots

Un mismo robot está repartido en tres sitios:

- `robots/`: el núcleo común (`nucleo.lua`, `pieza.lua`, `union.lua`) y las
  especializaciones que valen en todas partes (lidar, combate, torreta…);
- `batalla/robots/`: el robot en la batalla y sus especializaciones de
  combate y vehículos (camión de misiles, avión de carga…);
- `almacen/robots/`: el robot del almacén y sus encargos.

## Lo que está torcido (deuda), por orden de riesgo

1. **Lo del almacén va en la partida, pero fuera de la simulación.** Desde
   el 26-nov las cajas y los ordenadores son una sección de `partida.lua`
   (antes iban en archivos propios y el mundo solo se guardaba con F5). Siguen
   sin órdenes: en línea no viajarían. Si otros jugadores tienen que ver tu
   almacén, eso tendrá que pasar a la simulación.
2. **Dos sistemas de vehículos.** `batalla/vehiculos/` (el viejo, con
   `GestorVehiculos`) sigue vivo en el lanzamisiles, `mundo/modelos3d.lua`,
   `batalla/articulacion_camion.lua` y en `robots/pieza.lua`. La decisión del
   18-nov es que todo vaya con los robots (`robots/nucleo.lua`).
3. **Archivos gigantes.** `main.lua` (4.909 líneas: arranque, entrada, las
   cuatro escenas, capturas y medidas), `mundo/simulacion.lua` (4.475) y
   `batalla/tropas.lua` (3.078). Cada cosa nueva los engorda.
4. **Capas que se cruzan.** La simulación y el mundo usan la interfaz
   (`mundo/mundo.lua` → `interfaz/inteligencia`, `interfaz/tema` en 3
   sitios), y la interfaz usa el dibujo de la batalla
   (`batalla/dream/calidad`, `biblioteca_pbr`). Lo de abajo no debería
   conocer lo de arriba: los colores del tema se pueden pasar como dato.
5. **Avisos de pantalla dentro de la simulación.** `sim:noticia` se usa
   desde fuera para mensajes de la interfaz; esos avisos no son del mundo
   vivo y no deberían ir en el guardado ni viajar por la red.
6. **`MAPA-DEL-CODIGO.md` está viejo** (15-nov: no tiene `almacen/`,
   `robots/` ni `campana/`) y su generador, `tools/generar_mapa_codigo.py`,
   ya no está en el repositorio.
7. **`runtime/`** (19.056 líneas) es el runtime del editor de mapas; el juego
   no lo carga.

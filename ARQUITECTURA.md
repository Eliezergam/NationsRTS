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

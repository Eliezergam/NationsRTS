# Aviones de transporte

> **Estado: EN CURSO** (paso 1 desde el 2026-11-26). Nada programado todavía salvo el avión 3D,
> su pista en minas y ciudades y el viaje de demostración
> (`tools/demo_avion.sh`).

## Decisiones del dueño (2026-11-20)

1. **Todo traslado de tropas va en avión**: refuerzos, envíos a minas,
   guarniciones, regresos. La ficha de estandarte que camina por el mapa
   desaparece.
2. **Los ataques no ocurren a medio camino**, solo en minas y ciudades. Para
   atacar también se manda un avión; como no puede aterrizar en una base
   enemiga, los robots, los lanzamisiles y el resto del equipo caen en
   **paracaídas**. El salto en el 3D se hace más adelante.
3. **Los aviones se fabrican y cuestan.**
4. **Velocidad real**: la del avión 3D (unos 75 m/s, 270 km/h). En el mapa
   1 px = 1 m y un día dura 60 s a velocidad normal, así que vuela unos
   4 500 px por día: ciudad → mina cercana (2-5 km), de 30 s a 1 min;
   ciudad → ciudad lejana (15-40 km), de 3 a 9 min.
5. **Las IA usan lo mismo.**
6. **El derribo**, más adelante.
7. **Lo que se ve en 3D sale del mapa**: si entras al origen mientras sale, lo
   ves despegar; si entras al destino antes de que llegue, aparece en el aire
   cuando le toca según el mapa y aterriza. Si en el mapa faltaba 1 minuto,
   esperas 1 minuto.

## Decisiones del dueño (2026-11-26)

8. **Flota**: cada capital empieza con **5 aviones** (al principio, 1;
   cambiado el mismo día: «al principio el transporte no debería ser una
   limitación»); los demás se fabrican.
   Si no hay avión libre, el envío **espera** su turno.
9. **Todo vuela**: ejércitos, refuerzos, guarniciones, regresos, los
   recolectores (ida a la mina y vuelta con la carga) y los convoyes de obra.
   En el mapa ya no camina nada.
10. **Ida y vuelta**: el avión va a buscar la carga si no está donde sale,
    la lleva y vuelve vacío a su ciudad. Mientras vuela no está libre.
11. **Carga en toneladas reales**: 80 t por avión. Robot soldado de 1,85 m,
    150 kg (unos 530 por avión). Camión de misiles con su misil, 37 t (como
    un MAZ-543 cargado: 2 por avión). Un envío que pesa más sale en varios
    aviones o en varios viajes.
12. **Coste del avión**: 200 dinero, 40 metal y 10 petróleo, 15 días de obra
    en la ciudad.
13. **Sin combustible por vuelo**: los robots usan la energía de antes de la
    extinción (sin combustible ni hélices), como el avión 3D.

## Propuestas de antes (por decidir; valores de partida)

- **Carga**: 15 robots por avión, los 15 huecos de la bodega 3D
  (`embarque.lua`). Un lanzamisiles ocupa 5 huecos. Un envío mayor sale en
  varios aviones.
- **Ida y vuelta**: el avión deja la carga y vuelve vacío a su ciudad. Mientras
  vuela no se puede usar.
- **Fabricación** en la ciudad, con metal, petróleo, oro y días de obra (las
  cifras, con Lucía). Cada capital empieza con 1 avión para que el juego
  funcione desde el primer día.
- **Combustible**: cada vuelo gasta petróleo según la distancia.
- **Convoyes de obra** (construir instalaciones): también en avión.

## Hecho (26-nov)

- **Paso 1, simulación** (`mundo/simulacion/aviones.lua`, versión 31): flota
  por nación, vuelos (buscar → llevar → volver), carga en toneladas, cola por
  orden de id, fabricación en la ciudad (orden `fabricarAvion`) y la IA
  encarga uno cuando alguien suyo espera avión (hasta 6). Sin choques en campo
  abierto (`Simulacion.choquesEnCampo = false`). La IA de recolección no manda
  a nadie más mientras alguien suyo espera avión.
- **Paso 2, mapa**: el avión con el modelo 3D en 16 rumbos
  (`tools/blender/avion_mapa.py` → `assets/mapa/avion/`), su sombra y un disco
  del color de su nación; sube y baja en el primer y último 12 % del viaje. Lo
  que vuela o espera avión ya no tiene ficha. Captura: `--captura ... avion`.

- **El avión es de su grupo** (26-nov, el dueño: «ellos mismos llevan lo
  recolectado a la ciudad... y así en todo»): se queda con él donde lo deja
  ('esperar'); en un ataque espera en la ciudad propia más cercana
  ('aparcar') y vuelve a recogerlo. Solo vuelve a su ciudad cuando el grupo
  se deshace.
- **Recolección en avión**: carga = 80 t por avión menos el peso de los
  robots (1 unidad = 1 t); ritmo 0,5 por robot al día (antes 0,03), para que
  15 robots llenen un avión en unos 10 días. Lleno, vuelve a la ciudad,
  entrega y vuelve a la mina con su avión mientras a la nación le falte ese
  recurso (y la mina no se cierre).
- **5 aviones al empezar** (con 1 todo hacía fila y nadie llegaba a fabricar
  el 2.º). La IA junta también lo que cuesta un avión cuando alguien suyo
  espera, y no pasa de 10.

Medido sin pantalla (semilla 2026, 90 días, 5 naciones): de 1 a 5 grupos
esperando avión casi siempre, se fabrican aviones, hay batallas en minas y
ciudades; dinero 101-3 597 y metal 34-302 a los 90 días. Determinista (dos
veces la misma huella) y guardar a mitad con 18 aviones en el aire, cargar y
seguir da lo mismo que no parar.

## Pasos (uno cada vez, enseñado y aprobado antes del siguiente)

1. **Simulación**: el vuelo reemplaza la marcha. Línea recta (cruza el agua),
   velocidad del avión, sin choques por el camino, hora de salida y de
   llegada. Aviones por ciudad, carga y vuelta. Pruebas de determinismo.
2. **Mapa 2D**: el avión dibujado con el modelo 3D (renderizado desde arriba
   en 16 direcciones y su sombra), volando del origen al destino; fuera las
   banderitas.
3. **Menú**: «Enviar avión» en la ciudad o la mina (destino y carga), y
   «Fabricar avión».
4. **IA**: sus refuerzos, envíos a minas y ataques, en avión.
5. **Enlace con el 3D**: despegue y llegada según la hora del mapa.
6. **Después**: paracaídas en los ataques y derribo.

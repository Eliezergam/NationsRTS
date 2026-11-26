# Aviones de transporte

> **Estado: PLAN** (2026-11-20). Nada programado todavía salvo el avión 3D,
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

## Propuestas (por decidir; valores de partida)

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

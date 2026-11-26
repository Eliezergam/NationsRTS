# Cómo están hechos los ojos de los robots

Los ojos salen de un script de Python para Blender y los anima el juego en Lua.

- **Modelo:** `tools/blender/robot_almacen.py`, funciones `ojoCuenca` y `ojoPiezas`. El soldado y el robot grande
  reutilizan esas piezas desde `tools/blender/robot_soldado.py` (`globoOjo`, `cuencaPersiana`, `persianas`), y el
  grande las llama desde `tools/blender/robot_pesado.py`.
- **Animación:** `almacen/robots/especializaciones/mirada.lua`.

Las medidas van en metros a escala 1. Cada robot aplica su propia escala `e`:

| Robot | Escala |
|---|---|
| Robot pequeño del almacén | 1 |
| Soldado | 0,95 |
| Robot grande | 2,8 |

El ojo mira hacia delante, por el eje +X de Blender. Cada pieza móvil es un objeto aparte con el pivote en su
centro, para que el juego pueda moverla sola.

## 1. Lo fijo: la cuenca (va pegada a la cabeza)

| Pieza | Forma | Medidas | Material |
|---|---|---|---|
| Carcasa | Tubo corto con los cantos biselados | Radio interior 3,4 cm, exterior 4,4 cm; sobresale 2 cm de la cara | Negro |
| Bisel | Aro delante de la carcasa | Radio de 3,5 a 4,3 cm, 4 mm de grueso | Acero |
| Dientes del bisel | 48 cubitos girados 45°, en círculo | 3 mm de lado, a 4,05 cm del centro | Acero |
| Tornillos | 8 cilindros de 6 lados (hexagonales), uno cada 45° | A 3,65 cm del centro | Acero |
| Fondo | Disco detrás de todo, para no ver el interior de la cabeza | Radio 3,4 cm | Visor (oscuro) |

## 2. Lo que se mueve: el ojo por dentro

Todo cuelga de la pieza `ojo{S}`, que gira hacia donde mira. `{S}` es el lado: `Izq` o `Der`. Las piezas van de
atrás hacia delante:

1. **Fondo del iris:** disco gris de 2,5 cm de radio.
2. **Halo:** aro de color iris, de 0,6 a 1,25 cm de radio.
3. **Núcleo:** disco cian de 0,75 cm de radio. Su material emite luz y el juego la multiplica ×6.
4. **Centro del núcleo:** punto blanco de 0,35 cm de radio. Es la «pupila».
5. **Aro interior:** aro negro de 2,45 a 2,65 cm que separa el núcleo del resto.
6. **Aro de cobre** (`anillo{S}`): de 2,7 a 3,25 cm de radio, con 24 ranuras negras. Gira sin parar.
7. **Diafragma** (`diafragma{S}`, con las láminas `hoja{S}00` a `hoja{S}17`): 18 láminas curvas que se solapan,
   como el obturador de una cámara.
   - **Forma de cada lámina:** un arco que sale hacia el centro y se curva 70°. Mide 9,5 mm de ancho en la raíz y
     3 mm en la punta, con 0,5 mm de grueso.
   - **Pivote:** cada lámina lleva un remache diminuto. Los 18 están en círculo a 2,35 cm del centro.
   - **Filo:** el borde interior lleva un hilo cian que brilla.
   - **Solape:** cada lámina va inclinada a lo ancho, con el filo del hilo cian 3 mm más adelante que el de fuera,
     para que se monten unas sobre otras igual en todo el círculo (antes, apiladas, la última sobresalía).
8. **Párpados blindados** (`parpadoSup{S}` y `parpadoInf{S}`): solo los lleva el robot pequeño.
   - Cada uno es un trozo de círculo de acero gris que tapa 1,4 cm de la abertura, uno arriba y otro abajo.
   - Llevan un canto recto negro, un nervio de acero y 2 tornillos.

## 3. Soldado y robot grande: globo y persianas

### El globo

En vez del ojo plano, estos robots llevan un globo (`globo{S}`):

1. Una bola de 96 × 48 segmentos y 3,35 cm de radio, cortada por delante con un plano a 2,11 cm del centro.
2. Una tapa negra que cierra ese corte.
3. Dentro del corte, las piezas del ojo de la sección 2, a escala ×0,8.

El diafragma no es plano: forma una punta. Cada lámina se levanta hacia delante según se acerca al centro, hasta
9 mm en el centro mismo. Entre todas forman un cono.

### La cuenca con tubo

La cuenca es la misma de la sección 1, pero el tubo se alarga 7 mm hacia delante. Ese hueco es donde caben los
párpados.

### Los párpados de persiana

- **Piezas:** dos párpados, arriba y abajo. Cada uno tiene 4 láminas finas (`persianaSup{S}{k}` y
  `persianaInf{S}{k}`, con k de 0 a 3).
- **Abiertos:** las láminas están apiladas contra el borde del ojo y solo se ve la primera.
- **Cerrados:** la lámina k baja o sube k pasos. Entre las 4 tapan el ojo entero y se juntan en el centro.
- **Forma de cada lámina:** su contorno se recorta con dos círculos a la vez, el del agujero del ojo y el de la
  pared del tubo. Así no asoma por fuera, ni cerrada ni apilada.

## 4. Cómo lo anima el juego (`mirada.lua`)

| Pieza | Movimiento |
|---|---|
| Cabeza y cuello | Siguen al objetivo con suavidad (rapidez 4 por segundo). |
| Ojo o globo | Salta hacia lo que mira, como unos ojos de verdad (rapidez 30 por segundo). Mueve 0,6 de la mirada; el resto lo pone la cabeza. Límites: 35° a los lados y 25° arriba y abajo. |
| Aro de cobre | Gira a 1,2 rad/s, y hasta 9 rad/s más mientras enfoca algo nuevo. |
| Diafragma entero | Gira despacio en sentido contrario (−0,15 del giro del aro). |
| Cada lámina del diafragma | Gira sobre su pivote para abrir o cerrar la pupila: 0,75 rad de cerrada a abierta. |
| Párpados blindados | Bajan y suben según la expresión. Para parpadear cierran 2,1 cm durante 0,13 s. |
| Persianas | Bajan y suben según la expresión; la lámina k se mueve k veces el paso. |

### Las expresiones

| Expresión | Apertura de la pupila | Párpados |
|---|---|---|
| Normal | 0,6 | En reposo |
| Enfoque | 0,22 (cerrada) | Bajan un poco: casi cierra los ojos |
| Alerta | 0,95 (muy abierta) | Suben: ojos muy abiertos |
| Tenso | 0,4 | Bajan un poco y se inclinan: ceño fruncido |

### Los ojos también ven

Unas 15 veces por segundo, cada ojo lanza un rayo desde la pupila hacia donde mira, con 30 m de alcance. Con lo
que encuentra, el robot reconoce lo que tiene delante, por ejemplo «es mesa de recepción, a 18,5 m».

## 5. Cómo regenerar los robots

```sh
blender -b --factory-startup --python tools/blender/robot_almacen.py -- --glb
blender -b --factory-startup --python tools/blender/robot_soldado.py -- --glb
blender -b --factory-startup --python tools/blender/robot_pesado.py -- --glb
```

Cada uno escribe su `.glb` y su `_piezas.lua` en `assets/`. El juego busca cada pieza móvil por su nombre, así
que no hay que tocar nada más.

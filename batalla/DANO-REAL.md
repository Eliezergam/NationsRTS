# Daño real en la batalla 3D

Diseño de Valeria del 2026-10-01 para que Lucía lo revise. Encargo del dueño:
«cada bala, misil u obús tiene que impactar; agregarle realismo».

Este documento explica cómo funciona ahora el daño de la batalla 3D y qué
cifras usa. Las cifras medidas antes y después están en el §9. Las propuestas
de equilibrio, en el §10.

## 1. Cómo era

Hasta ahora, el daño se decidía casi siempre con una tirada de dados:

- **Disparos.** Se sorteaba si el disparo acertaba:
  - tanque: `punteria(d)`, como mucho 0,5;
  - escuadra: de 0,08 a 0,32;
  - × 0,7 si la escuadra avanzaba agachada.
- **Vuelo.** La bala volaba en línea recta hasta el blanco, o hasta un punto
  sorteado cerca si fallaba.
- **Daño.** Si acertaba, quitaba vida fija:
  - tanque: el golpe de su modelo;
  - fusil contra soldado: 0,25 de la vida de la escuadra;
  - fusil contra vehículo: 0,05.
- **Misiles y cohetes.** Seguían una curva de Bézier. Al caer quitaban 2 de
  vida al 60 % de lo que estuviera dentro de su radio, fuera tanque o
  soldado. No se miraba blindaje ni cobertura.
- **Soldados.** La escuadra perdía vida, y al final se repartían muertos y
  heridos con F11b (0,4 de los que caen mueren).

## 2. Qué cambia

Cada proyectil es un objeto que vuela con balística de verdad y hace daño
donde llega:

- **Choques.** Contra el terreno, un árbol, una roca, el edificio, un
  vehículo o un soldado.
- **Vehículos.** El daño depende de la zona que recibe el golpe, del
  blindaje de esa zona, del ángulo y de la penetración del proyectil.
- **Soldados.** Cada bala que toca a un soldado lo hiere o lo mata. Las
  explosiones matan dentro de su radio letal y hieren con la metralla, que
  se atenúa si hay cobertura.

El código está en `batalla/dano/`, un módulo por tema:

| Módulo | Qué hace |
|---|---|
| `datos.lua` | Cifras reales de cañones, munición, blindaje por zonas, fusil y ojivas, suavizadas como el catálogo |
| `trayectoria.lua` | Balística analítica: tiro directo con gravedad y arrastre; tiro indirecto con impulso y parábola |
| `cuerpos.lua` | Cajas de los vehículos (casco, torreta y cañón) y de los soldados, en una rejilla espacial; rayo contra caja |
| `blindaje.lua` | Blindaje efectivo, rebote, penetración y avería por zona |
| `explosiones.lua` | Radio letal y de metralla, cobertura por línea de visión y onda contra vehículos |
| `proyectiles.lua` | Proyectiles vivos: lanzamiento, avance por pasos, choques y límites |

`batalla/tropas.lua` sigue siendo la fachada. Las funciones que usan otros
módulos se mantienen: `Tropas.posicionBala`, `Tropas.posicionMisil`,
`Tropas.matrizMisil`, `tropas.balas`, `tropas.misiles` y `Tropas:resultado`.

## 3. Proyectiles que vuelan

Unidades del juego: 1 px = 10 cm y g = 9,8 m/s² = 98 px/s².

### 3.1 Tiro directo (balas y cañonazos)

- **Trayectoria analítica.** No se integra paso a paso. El arrastre frena
  la velocidad a lo largo del recorrido, v(s) = v₀·e^(−k·s), así que el
  tiempo para recorrer s es t(s) = (e^(k·s) − 1)/(k·v₀), y la caída por
  gravedad es g·t²/2. La posición en cada instante sale exacta y cuesta lo
  mismo calcularla en cualquier momento.
- **Puntería.** La dirección de salida es la de puntería más la
  sobreelevación que compensa la caída hasta el blanco. El control de tiro
  la calcula con la distancia que mide, que lleva su error. A eso se suman:
  - la **dispersión** del arma, en mrad;
  - el **error de puntería** del tirador;
  - la **anticipación** si el blanco se mueve. Desde la era 2, el control
    de tiro anticipa; la era 1 no.
- **Choques fijos (terreno, edificio).** Se calculan una sola vez al
  disparar, recorriendo la curva en tramos con `Impactos.terreno`. Eso da
  el punto y el instante en que la bala acabaría en el suelo, y de ahí sale
  `duracion`, el tiempo de vuelo que usan los efectos.
- **Choques por paso (árboles, rocas, vehículos, soldados).** Se miran en
  cada paso de 1/60 s, sobre el tramo recorrido en ese paso:
  - árboles y rocas con `Impactos.arboles`, porque el tramo es corto y
    pueden haber caído;
  - vehículos y soldados con la rejilla de `cuerpos.lua`.
- **Si falla,** sigue volando hasta el suelo (o hasta su alcance máximo) y
  cae donde llega.
- **Penetración.** Escala con la velocidad que le queda a la bala al
  llegar: pen = pen₀·(v/v₀)^1,5.

### 3.2 Ráfagas de infantería: haz equivalente

Una escuadra de N soldados dispara 5·N balas por ráfaga (lo de siempre). Se
simula así:

- **Un haz por ráfaga.** Es una trazadora que vuela con la balística del
  fusil por la línea central de la ráfaga. Cada bala lleva su desvío,
  sorteado al disparar. El haz choca con lo que encuentre en el camino:
  - **el terreno**, calculado al disparar. Si la línea central da en una
    loma antes de llegar, toda la ráfaga para ahí: lejos del blanco, las
    balas van juntas, a menos de 1 m a 300 m. Si da en el suelo a menos de
    60 m de la zona del blanco, la zona empieza 5 m antes, para que cada
    bala vea esa loma por su cuenta;
  - **un árbol, una roca o un cuerpo** (mirados en cada paso). Cada bala
    viva se prueba contra eso, en un tramo de 10 m. Las que dan se quedan
    ahí y las demás siguen; el haz ya no vuelve a chocar con ello.
- **Bala por bala cerca del blanco.** Cuando el haz llega a 30 m del
  blanco, cada bala de la ráfaga se resuelve por separado. Lleva su
  dirección (el error común de la ráfaga más su dispersión propia) y se
  prueba un rayo desde ahí hasta 60 m detrás del blanco contra:
  - las cajas de los soldados y vehículos cercanos;
  - los árboles y rocas de esa zona;
  - el perfil del terreno de esa zona, muestreado una vez por haz cada
    1,2 m.

  La primera que toca se lleva la bala. Así cuenta la cobertura de cerca:
  la roca o el tronco tras el que está el soldado, la loma, el vehículo
  averiado.
- **Ráfagas grandes.** Con más de 40 balas en la ráfaga (escuadras de más
  de 8 soldados), se prueban 40 rayos y cada uno vale 5·N/40 balas. El
  resto se reparte con el mismo azar con semilla: la esperanza de bajas no
  cambia.
- **Coste.** Una ráfaga cuesta:
  - un `Impactos.terreno` del camino al disparar;
  - unos 75 muestreos de altura del perfil;
  - por bala, unas pocas pruebas de rayo contra caja o cilindro, porque los
    candidatos se buscan una vez por haz.

  Probar bala a bala con `Impactos.rayo` costaría unas 75 alturas por bala
  y cientos de balas por segundo. El haz da lo mismo dentro de la
  dispersión, que a 300 m es menor de 1 m.
- **Dibujo.** Una trazadora por ráfaga, como antes, sea cual sea la
  distancia a la cámara. Se ven como mucho 3 impactos por ráfaga. La
  colisión no depende de la cámara (§8.1).
- **Línea de fuego.** Un tanque o una escuadra no dispara si el primer
  cuerpo que cruza su línea hasta el blanco es de su bando (un compañero o
  un averiado suyo). Espera a tenerla libre. Sin esta regla, las filas de
  atrás daban a las de delante por la espalda: en la semilla 7, 50 de 68
  golpes traseros eran de un compañero.

### 3.3 Tiro indirecto (cohetes y misiles)

- **Punto de caída.** Cada proyectil de una salva tiene el suyo: el blanco
  más la dispersión del modelo (`escena.cep`, reparto circular normal, como
  antes).
- **Vuelo.**
  1. **Impulso.** Sale por el eje de la rampa y en 1,2 s gira hasta la
     velocidad de la parábola de 45° que llega a su punto. Es una curva de
     Hermite que empalma con la parábola en posición y velocidad.
  2. **Caída balística.** Después solo actúa la gravedad. Con 45° y 3 km,
     el vuelo dura unos 25 s, como antes (unos 20 s).
- **Licencia.** El camión no gira el lanzador hacia el blanco, porque el
  modelo no tiene esa pieza. Por eso el cohete corrige el rumbo durante el
  impulso. En el Scud-B y el HIMARS (guiados) es así de verdad; en el BM-21
  es una licencia.
- **Choques.** Los mismos que el tiro directo: el terreno al lanzar; los
  árboles, el edificio, los vehículos y los soldados en cada paso. Un cohete
  que da en una copa o en un vehículo estalla ahí.
- **Dibujo.** Se dibujan como mucho 8 misiles por salva
  (`maxVisualesSalva`). Ahora cada proyectil vuela por su cuenta y estalla
  donde llega: los ocultos no se dibujan, pero chocan igual.

## 4. Datos de las armas (`dano/datos.lua`)

### 4.1 De dónde salen las cifras

- **Catálogo.** El catálogo (`catalogoArmamento.lua`) solo trae el calibre
  y, del T-55, su blindaje (torreta 205 mm, casco 120 mm a 60°). No trae
  velocidad de boca ni penetración.
- **Lo demás** son cifras públicas aproximadas de fuentes abiertas
  (Wikipedia y fichas de munición), tomadas de memoria, sin conexión en
  esta sesión. **Hay que verificarlas**: están marcadas así en el archivo.
- **Blindaje.** Es el equivalente en mm de acero frente a proyectiles
  cinéticos, en línea horizontal. La inclinación real de la chapa ya va
  dentro de la cifra.

### 4.2 Suavizado

Se suaviza como el catálogo (P4, α = 0,5). La referencia (T-72B) queda con
sus cifras y los demás se acercan a ella:

```
valor_juego(modelo, zona) = valor_ref(zona) · (valor_real(modelo, zona) / valor_ref(zona)) ^ 0,5
```

### 4.3 Cañones (munición perforante)

| Modelo | Cañón | Munición | v boca | Pen. real a 2 km | Pen. juego a 2 km | Error de tiro |
|---|---|---|---|---|---|---|
| T-55 | 100 mm D-10T | 3BM8 | 1 415 m/s | 275 mm | 371 mm | 1,2 mrad, distancia ± 5 % |
| T-72B | 125 mm 2A46M | 3BM42 | 1 700 m/s | 500 mm | 500 mm | 0,7 mrad, ± 1 % |
| M1A1 | 120 mm M256 | M829A1 | 1 575 m/s | 570 mm | 534 mm | 0,45 mrad, ± 1 % |
| K2 | 120 mm CN08 | K279 | 1 760 m/s | 650 mm | 570 mm | 0,4 mrad, ± 1 % |

- **Arrastre** del perforante: k = 4,6·10⁻⁵ /m (pierde unos 75 m/s por km).
- **Dispersión mecánica** del arma: 0,25 mrad.
- **La penetración varía ± 5 %** en cada disparo (σ).
- **Contra soldados,** el tanque tira explosiva (HE-FRAG):
  - v boca 850 m/s y k = 2·10⁻⁴ /m;
  - radio letal 6 m y metralla 20 m, a 125 mm, proporcionales al calibre.

### 4.4 Blindaje por zonas

En mm equivalentes. Entre paréntesis, el valor ya suavizado.

| Modelo | Frente casco | Frente torreta | Costado casco | Costado torreta | Trasera | Techo |
|---|---|---|---|---|---|---|
| T-55 | 200 (310) | 205 (327) | 80 (80) | 150 (194) | 45 (42) | 30 (37) |
| T-72B | 480 | 520 | 80 | 250 | 40 | 45 |
| M1A1 | 560 (518) | 600 (558) | 70 (75) | 270 (260) | 40 (40) | 40 (42) |
| K2 | 600 (537) | 700 (603) | 90 (85) | 300 (274) | 40 (40) | 50 (47) |

Los lanzacohetes son camiones de chapa: 8 mm en la cabina y 5 mm en el
resto. La bala de fusil los atraviesa.

### 4.5 Fusil de la escuadra

- **Bala:** v boca 900 m/s, k = 1,1·10⁻³ /m y penetración 8 mm a 100 m.
- **Dispersión de la ráfaga:** 2,5 mrad por bala.
- **Error de puntería común de la ráfaga:** σ = 4 mrad quieto, 7 mrad si
  dispara bajo fuego y 9 mrad si se mueve, más 0,4 m fijos.

  Esta perilla no tiene cifra real. Se ajusta para que la pelea dure lo
  mismo que antes (§9) y está en `Datos.fusil.apunte`.

### 4.6 Ojivas (cohetes y misiles)

- **Radio letal:** el radio de la escena (`escena.radio`, F10). Escala con
  la raíz cúbica de la ojiva; 18 m en el Scud-B.
- **Metralla:** 2,5 × el radio letal.
- **Penetración de un golpe directo:** 0,25 × el calibre, que en el Scud-B
  se toma de 880 mm. Da 30 mm en el BM-21, 57 mm en el HIMARS y 220 mm en
  el Scud-B.

## 5. Impacto contra vehículos (`dano/cuerpos.lua`, `dano/blindaje.lua`)

### 5.1 Cajas

Cada vehículo tiene cajas orientadas sacadas de los vértices de su modelo 3D:

- **Tanque:** casco, torreta (gira con ella) y cañón.
- **Camión:** chasis y contenedor.

El rayo se pasa a las coordenadas locales de la caja (inversa de la postura
del casco, que sigue la pendiente) y se cruza con ella (método de las
placas). Sale la cara de entrada, la normal y el punto local.

### 5.2 Zona

| Cara de entrada | Zona |
|---|---|
| +x | Frente |
| −x | Trasera |
| ±y | Costado |
| +z | Techo |

En el casco, además:

- **Orugas:** el tercio inferior de los costados (z < 0,35 del alto).
- **Motor:** el último 30 % del largo (en el camión, el frente, la cabina).

### 5.3 Penetración

- **Blindaje efectivo** = espesor / cos θ, donde θ es el ángulo entre la
  dirección del proyectil y la normal de la cara.
- **Rebote** si θ > 75° (perforante) o 65° (explosiva u ojiva). El
  proyectil sigue reflejado con el 50 % de su velocidad y puede dar en otra
  cosa, pero no rebota dos veces.
- **Penetra** si la penetración que le queda a la bala es mayor o igual que
  el blindaje efectivo.

### 5.4 Avería por zona

| Golpe | Avería |
|---|---|
| Oruga (rueda en el camión) | Rota, aunque no penetre: la oruga está fuera del blindaje. Inmovilizado |
| Cañón | Dañado, aunque no penetre (rompe el tubo). No dispara |
| Penetra en la torreta | Torreta atascada con 0,5 de probabilidad; además, tripulación |
| Penetra en el motor | Motor roto: inmovilizado y humea |
| Penetra en cualquier otro sitio | Tripulación: 1 baja (2 con más del 50 % de penetración sobrante) |
| Cada penetración | + 0,15 de `estructura` (el agujero) |

Efecto de cada avería en la batalla:

- **Inmovilizado:** no se mueve, pero dispara.
- **Torreta atascada:** apunta girando el casco, si puede moverse. Si no,
  solo dispara a lo que tenga delante (± 3°).
- **Inmovilizado con una orden de mover:** la cambia por mantener posición.
- **Tripulación:** con bajas, recarga más despacio (× tripulación /
  quedan). Sin nadie, fuera de combate.
- **Fuera de combate** (`averiar`, como hoy: humea y cuenta como baja):
  - sin tripulación;
  - o sin cañón y además inmovilizado;
  - o con `estructura` ≥ 1.

**Regla del dueño: los vehículos no se destruyen.** Ningún daño destruye
un vehículo; vuelve al taller.

### 5.5 Lo que vuelve a la simulación

- **Daño (0 a 1):**
  - orugas 0,2;
  - torreta 0,25;
  - cañón 0,3;
  - motor 0,35;
  - 0,1 por tripulante;
  - más la `estructura`.

  El total se recorta a 1.
- **Lista de averiados.** Un vehículo con daño entra en `averiados` aunque
  siga peleando, por ejemplo con la oruga rota: va al taller.
- **Zonas.** Las zonas de cada averiado van en `averiados.zonas`, en el
  mismo orden. Formato exacto en §5.6.

### 5.6 Formato para la simulación (Andrés)

El dueño decidió (D2 y D3, 2026-10-01) que la simulación repare por zona
en el taller y que las bajas de las tripulaciones cuenten como muertos y
heridos de la nación. Esto es lo que manda la batalla en
`Tropas:resultado` (`Choques.resultadoDeEscena`), por lado (`atacante`,
`defensor`), además de lo de siempre:

```lua
bando = {
    soldados = { muertos = n, heridos = n },          -- las escuadras, como antes
    tripulacion = { muertos = n, heridos = n },       -- NUEVO: las tripulaciones de todos sus vehículos
    averiados = {
        tanques = { dano, ... },                      -- de 0 a 1, como antes
        lanzacohetes = { dano, ... },
        modelos = { tanques = { 't55', ... }, lanzacohetes = { 'bm21', ... } },
        zonas = {                                     -- NUEVO: una tabla por daño, en el mismo orden
            tanques = { zonas, ... },
            lanzacohetes = { zonas, ... },
        },
    },
    municion = { [clave] = { balas, obuses, misiles } }, -- como antes
}

zonas = {                     -- solo están las claves que tocan
    orugas = true,            -- tanque: oruga rota; camión: rueda rota (inmovilizado)
    torreta = true,           -- tanque: torreta atascada (el camión no la tiene)
    canon = true,             -- tanque: cañón roto; camión: lanzador roto
    motor = true,             -- motor roto (inmovilizado)
    tripulacion = n,          -- tripulantes caídos (muertos + heridos) de este vehículo
    tripulacionMuertos = n,   -- de ellos, muertos
    estructura = x,           -- de 0 a 1, con 2 decimales: agujeros y onda
}
```

- **Cuántos y en qué orden.** `#averiados.zonas.tanques ==
  #averiados.tanques`, y la k-ésima tabla es del k-ésimo daño y del
  k-ésimo modelo. Un averiado sin ninguna zona (raro) lleva `{}`.
- **Tripulación.** `tripulacion.muertos` y `tripulacion.heridos` son la
  suma, en el bando, de `tripulacionMuertos` y de `tripulacion −
  tripulacionMuertos` de todos sus vehículos. Todo vehículo con una baja en
  la tripulación tiene daño (0,1 por tripulante), así que está en la lista.
  - Cada tripulante que cae muere con 0,4 de probabilidad
    (`Datos.averias.muerteTripulante`, como F11b). Si no, queda herido.
  - La tripulación de cada modelo es la del catálogo (`tripulacion`): 4 en
    el T-55, 3 en el T-72B, 4 en el M1A1, 3 en el K2, 7 en el Scud-B y 3
    en el BM-21 y el HIMARS.
  - No son soldados de las escuadras: no están en `soldados`.
- **Daño.** `dano` ya suma las zonas (§5.5) y lo puede seguir usando el
  taller para el coste. Las zonas son para el taller por zona y el tiempo
  de cada reparación; lo que dura y cuesta cada una lo decide el diseño.
- **Validación.** `resultadoValido` (batallas.lua) no mira ni `zonas` ni
  `tripulacion`, así que hoy se aceptan y se ignoran.

## 6. Impacto contra soldados

### 6.1 Una figura es una escuadra

Una figura es una escuadra de N soldados (F10). Su vida pasa a ser N: cada
soldado que cae le quita 1. Cuando no le queda nadie en pie, cae la figura.

### 6.2 Balas

- **La caja de un soldado:** 0,5 m de ancho, 0,3 m de fondo y 1,8 m de pie.
- **Agachado:** si avanza agachado (clip `agachadoAvanzar`), la caja mide
  1,15 m. Así acierta menos porque el blanco es más bajo, no por un 0,7
  fijo. Contra la metralla también cuenta: expone 1,15/1,8 de su cuerpo.
- **Cada bala que toca la caja es un soldado caído:**
  - en la cabeza (los 0,25 m de arriba): muerto;
  - en el cuerpo: muerto con 0,3 de probabilidad; si no, herido.

  Con una caja de 1,8 m, eso da cerca de un 0,4 de muertos, como F11b.
- **Cada bala representa el fuego dirigido a un soldado de la escuadra.**
  Por eso basta una caja por figura: la esperanza de bajas es la misma que
  con N cajas, a las que va dirigida 1/N del fuego cada una.
- **Cobertura:** árboles, rocas, lomas, el edificio y los vehículos (también
  los averiados) paran la bala porque se cruzan antes con el rayo.
- **Ráfaga más pequeña.** Una escuadra con bajas dispara 5 balas por
  soldado que le queda en pie, y gasta eso. Antes gastaba siempre por los N
  con que entró.

### 6.3 Explosiones

- **Reparto de la escuadra:** sus N soldados en pie ocupan un disco de 8 m
  alrededor de la figura (unos 5 m entre ellos), en espiral y sin azar.
- **Cada soldado** cae con la función de Carleton, la habitual para la
  metralla:

  ```
  P(r) = 2^−(r / radio letal)²
  ```

  - Por definición, cae la mitad de los que están justo en el radio letal.
  - No llega más allá del radio de metralla (2,5 × el letal, donde P < 2 %).
  - A más de medio radio letal, P se multiplica por 0,64 si va agachado y
    por 0,15 si está a cubierto.
- **Muertos:** de los que caen dentro del radio letal muere el 60 %; de los
  de más lejos, el 25 %. El resto, heridos.
- **A cubierto** quiere decir que la línea entre la explosión (a 1 m del
  suelo) y la figura (a 1,2 m) cruza:
  - el terreno: una prueba corta con `Impactos.terreno`;
  - un árbol o una roca: `Impactos.arboles`, con un segmento de menos de
    50 m;
  - o un vehículo: la rejilla.
- **Tirada:** cada soldado se sortea con el azar de la batalla. N es
  pequeño (de 3 a 50), así que cuesta poco.

## 7. Explosiones contra vehículos

- **Golpe directo** (el proyectil cruza la caja): penetración de la ojiva
  (§4.6) contra el blindaje de la zona, como un cañonazo.
- **Onda** (sin penetración) dentro del radio letal:

  ```
  onda = 1,05 · (radio letal / 18 m)
  estructura += onda · (1 − r / radio letal)
  ```

  Además, rompe la oruga o la rueda con probabilidad 1,43 · onda · (1 − r /
  radio letal): segura al pie de un Scud-B y de 0,42 al pie de un cohete
  del BM-21. Va con la ojiva porque, con la misma probabilidad para todas,
  los cohetes del BM-21 rompían casi todas las orugas (21 de 30 por bando
  en la semilla 42) y nadie avanzaba.

  Onda × 3 (de 0,35 a 1,05), decisión del dueño del 2026-10-01 (D4, §10.5).
- **Metralla:** no hace nada a un tanque. A un camión le da tripulación con
  0,3 de probabilidad dentro del radio de metralla.
- **Efectos:** el cráter y los efectos, como hoy.

## 8. Determinismo y rendimiento

### 8.1 Determinismo

- **Pasos fijos.** `Tropas:actualizar(dt)` acumula el tiempo y avanza la
  pelea en pasos fijos de 1/60 s (`Tropas.pasoFijo`) (4 por cuadro como mucho; si el cuadro va
  lento, la pelea va más despacio, pero da lo mismo). `tropas.relojVista`
  es el reloj más lo que falta para el siguiente paso.
- **Azar.** Todo el azar de la pelea sale de `tropas.azar`, con semilla
  del sitio. Los efectos (Camila) tienen el suyo.
- **La misma batalla da lo mismo**, con la misma semilla y en el mismo
  binario. El arnés `pruebas_dano` lo comprueba con la huella del
  resultado: dos corridas, la misma huella.
- **No es determinista al 100 %:**
  1. **Entre sistemas operativos o bibliotecas de C distintas.** `sin`,
     `cos`, `atan2`, `log` y `exp` vienen de la libm y pueden diferir en el
     último bit. La física 2D (Box2D, de 3DreamEngine) va en coma flotante.
     Una diferencia mínima puede cambiar una pelea larga.
  2. **Órdenes del jugador.** Las aplica el control entre cuadros, no
     sellados con su número de paso. Para repetir una batalla con órdenes
     (red, repetición) habría que sellarlas con el paso.

### 8.2 Rendimiento

- **Rejilla espacial** de celdas de 25,6 m, rehecha en cada paso con los
  cuerpos vivos y los averiados (unos 160). Al rehacerla solo se apuntan el
  centro y el radio de cada cuerpo. Las cajas se colocan cuando un rayo pasa
  cerca: la mayoría de los cuerpos no se prueban en un paso.
- **Rayo contra caja** en coordenadas locales; primero una esfera que
  envuelve la unidad. Los rayos largos (una línea de fuego de 2 km) solo
  recorren las celdas que cruzan.
- **Cohetes en lo alto.** Mientras un cohete va por encima del suelo más
  alto de su camino más 40 m (y del edificio), no se buscan choques. Al
  lanzarlo se calcula entre qué instantes pasa eso.
- **Límite de 1 500 proyectiles vivos** (un haz cuenta 1). Por encima, un
  disparo nuevo se resuelve en el acto en su punto de llegada. Se cuenta en
  `estadisticas.resueltosEnElActo`; en las medidas de §9 no pasó nunca (como
  mucho, 93 vivos).
- **Lua o C.** Lua basta: el paso cuesta lo mismo que antes (§9.2), así que
  no hace falta pasar la balística a C por FFI.

## 9. Medidas

Arnés: `python3 batalla/pruebas_dano/ejecutar.py <carpeta> medir <semilla>`.
Batalla completa con la escena 3Dream real, en pasos de 1/30 s:

- por bando, 30 tanques (de los cuatro modelos) y 10 lanzacohetes (de los
  tres modelos), es decir, 40 vehículos;
- la infantería de las guarniciones: 76 escuadras en la semilla 42.

La munición no tiene límite: es la que se gasta, no la que se lleva. La
pelea se corta a los 900 s si no ha terminado.

### 9.1 Antes

| Semilla | Duración | Gana | Bajas atacante (m/h) | Bajas defensor (m/h) | Tanques averiados (A/D) | Munición atacante (balas/obuses/misiles) | Munición defensor | Tropas:actualizar media / 1 % peor |
|---|---|---|---|---|---|---|---|---|
| 42 | 623,6 s | atacante | 91/136 | 42/62 | 28/30 | 1 110 / 46 / 271,6 | 0 / 0 / 202,2 | 1,09 / 2,8 ms |
| 7 | 655,3 s | atacante | 62/92 | 106/155 | 30/30 | 1 750 / 457 / 299,7 | 570 / 172 / 202,6 | 1,93 / 7,9 ms |
| 1234 | 772,1 s | atacante | 75/114 | 46/67 | 30/30 | 18 175 / 624 / 258,0 | 3 675 / 559 / 254,2 | 1,13 / 3,3 ms |

- **Los misiles deciden casi todo.** En la semilla 42 hubo 1 340 salidas
  de misil o grupo de cohetes, frente a 46 cañonazos y 37 ráfagas.
- **FPS** (`pruebas_rendimiento`, 30 tanques y 10 lanzacohetes por bando
  de todos los modelos, alta, 1920 × 1080):
  - encuadre normal: 128 FPS de media y 37 en el 1 % peor;
  - dentro de la batalla: 114 y 40.

### 9.2 Después

| Semilla | Duración | Gana | Bajas atacante (m/h) | Bajas defensor (m/h) | Tanques averiados (A/D), fuera de combate | Munición atacante | Munición defensor |
|---|---|---|---|---|---|---|---|
| 42 | > 900 s | — | 98/146 | 37/67 | 30/30, 16/12 | 0 / 0 / 452,5 | 0 / 0 / 449,8 |
| 7 | > 900 s | — | 95/113 | 118/141 | 30/30, 20/22 | 0 / 523 / 406,9 | 0 / 116 / 439,7 |
| 1234 | 826,2 s | atacante | 89/110 | 55/58 | 30/30, 20/30 | 105 / 461 / 442,3 | 0 / 271 / 219,8 |

**Vehículos con avería en cada zona** (atacante / defensor; un vehículo
puede tener varias):

| Semilla | Orugas | Torreta | Cañón | Motor | Con bajas en la tripulación |
|---|---|---|---|---|---|
| 42 | 21 / 21 | 2 / 2 | 5 / 5 | 1 / 1 | 13 / 10 |
| 7 | 25 / 15 | 1 / 4 | 5 / 5 | 5 / 3 | 22 / 28 |
| 1234 | 16 / 14 | 7 / 7 | 3 / 6 | 6 / 7 | 32 / 38 |

**Disparos** (cañonazos / ráfagas / salidas de misil o grupo de cohetes):

| Semilla | Antes | Después |
|---|---|---|
| 42 | 46 / 37 / 1 340 | 0 / 0 / 2 513 |
| 7 | 629 / 89 / 1 439 | 639 / 0 / 2 474 |
| 1234 | 1 183 / 972 / 1 427 | 732 / 21 / 1 817 |

**Cañonazos contra vehículos** (semilla 1234):

- **Resultado:** 165 penetran, 133 no penetran y 15 rebotan. Los 15
  rebotes siguen volando y 13 llegan a chocar con algo.
- **Caras:** 161 golpes de frente, 85 de costado, 7 por detrás y 3 en el
  techo.

**Soldados en pie a los 60 s** (atacante / defensor):

| Semilla | Antes | Después |
|---|---|---|
| 42 | 191 / 98 | 76 / 34 |
| 7 | 168 / 237 | 70 / 141 |
| 1234 | 110 / 80 | 76 / 40 |

**Batalla de la simulación** (`pruebas_economia`, semilla 42, con la
munición que se lleva: 60 tanques, 8 lanzacohetes y 400 soldados contra
25, 6 y 300):

| | Antes | Después |
|---|---|---|
| Duración y final | 292 s, el atacante se retira (sin munición) | 332 s, el atacante se retira (sin munición) |
| Soldados del atacante (muertos / heridos / sanos) | 113 / 170 / 117 | 186 / 214 / 0 |
| Soldados del defensor | 27 / 36 / 237 | 17 / 29 / 254 |
| Averiados del atacante (tanques, lanzacohetes) | 29 de 60, 2 de 8 | 34 de 60, 1 de 8 |
| Averiados del defensor | 0 de 25, 0 de 6 | 10 de 25, 0 de 6 |
| Munición del atacante (balas / obuses / misiles) | 3 000 / 45 / 4 | 125 / 45 / 4 |
| Munición del defensor | 3 185 / 150 / 82 | 1 800 / 95 / 94 |

La prueba pasa: 13 547 comprobaciones, 0 fallos. Lo gastado nunca supera
lo que se lleva y ningún vehículo desaparece.

**Determinismo.** La misma batalla da la misma huella:

- con la semilla 42, en dos procesos distintos;
- con la semilla 42 y el arnés a pasos de 1/20, 1/30 y 1/60 s.

Aviso sobre el arnés: el sitio de la batalla de prueba sale del mundo
generado en hilos y a veces cambia de un proceso a otro. La pelea en sí es
determinista. El vídeo genera la batalla dos veces en el mismo proceso.

**Coste de `Tropas:actualizar` por paso de 1/60 s** (semilla 1234, 300 s,
dos pasadas alternas):

- antes: 1,46 y 1,31 ms de media, 3,35 y 3,02 ms en el 1 % peor;
- después: 1,33 y 1,33 ms de media, 3,48 y 3,50 ms en el 1 % peor.

Partes del paso (semilla 1234):

- rehacer los cuerpos: 0,04 a 0,06 ms;
- los cohetes y misiles: 0,06 ms (antes, 0,05);
- las balas: 0,01 ms.

**FPS** (`pruebas_rendimiento`, la misma batalla, alta, 1920 × 1080, sin
vsync; antes = el árbol de hoy con el `tropas.lua` de antes; pasadas
alternas):

| Encuadre | Antes: FPS medio | Antes: 1 % peor | Después: FPS medio | Después: 1 % peor |
|---|---|---|---|---|
| Normal (5 pasadas) | 135,9 | 43,2 | 136,2 | 44,9 |
| Dentro de la batalla, serie 1 (5 pasadas) | 118,8 | 34,3 | 109,1 | 33,2 |
| Dentro de la batalla, serie 2 (4 pasadas) | 120,4 | 37,9 | 120,8 | 43,7 |

En la serie 1 de «dentro de la batalla», la escena de después dibujaba 486
llamadas y la de antes 474. La pelea iba distinta: más golpes en
vehículos, con sus chispas y luces. En la serie 2, las dos con 447
llamadas, dan lo mismo.

## 10. Equilibrio y decisiones

### 10.1 Lo que cambia

1. **La infantería cae antes y casi no llega a disparar.**
   - A los 60 s quedan de un 35 % a un 70 % de los soldados que quedaban
     antes (§9.2).
   - Ráfagas por batalla: 0, 0 y 21, frente a 37, 89 y 972.
   - En la batalla de la simulación, la infantería atacante cae entera y
     gasta 125 balas de 3 000.

   La metralla con la función de Carleton alcanza de media a 1,44 × el área
   del radio letal. Antes, el 60 % de las escuadras dentro del radio
   perdía 2 de vida (la escuadra entera).
2. **Los vehículos aguantan mucho más la artillería.** La onda solo avería
   la estructura y las orugas, y los golpes directos son pocos (164 en la
   semilla 42).
   - Tanques en pie a los 300 s: 30/29, 25/17 y 12/5, frente a 10/5, 11/7
     y 8/4.
   - Con munición sin límite, dos de las tres batallas no terminan en
     900 s; antes terminaban entre 624 y 772 s.
3. **Muchos inmovilizados.** A los 300 s hay de 4 a 15 tanques
   inmovilizados por bando, sobre todo por la oruga rota por la onda de los
   cohetes.
4. **Tanques más certeros a 1,5 km.** El control de tiro real acierta
   mucho más que el 3 % al 50 % de antes: en la semilla 1234 hubo 551
   golpes en vehículos con 732 cañonazos (y 13 rebotes que volvieron a
   dar). El blindaje frontal decide: de frente, un
   T-55 casi no penetra a un M1A1 ni a un K2.
5. **El atacante no avanza** (de 20 a 140 m en 900 s), ni antes ni
   después. Antes no se notaba porque los misiles lo deshacían todo. Ahora
   las batallas quedan en un duelo de artillería que, con munición, no
   acaba.

### 10.2 Propuestas medidas

Las propuestas P1 y P2 son perillas de `dano/datos.lua`. Cifras con
munición sin límite, semillas 42 / 7 / 1234.

- **P1. Metralla al 65 % del radio de la ficha** (`explosion.escalaLetal =
  0,65`). Cada cohete causa de media las mismas bajas que antes.
  - Soldados en pie a los 60 s: 145/79, 141/228 y 127/64. Antes eran
    191/98, 168/237 y 110/80; hoy, 76/34, 70/141 y 76/40.
  - Ráfagas: 0, 528 y 753.
  - Las bajas finales de infantería apenas cambian (al final cae casi
    todo).
- **P2. Onda contra vehículos × 3** (`explosion.onda = 1,05`).
  - Tanques en pie a los 300 s: 24/16, 18/6 y 8/1, cerca de los de antes.
  - Las batallas terminan en > 900, 820,8 y 712,0 s.
  - Suben los vehículos con la oruga rota: de 19 a 35 por bando, frente a
    14 a 25 hoy.
- **P3. Que se acabe el duelo de artillería.** Es una propuesta sin
  cifras, para decidir:
  - o la regla del final (`Tropas.sinFuego`) cuenta como «no avanza» a un
    bando que en 60 s no ha causado ninguna baja;
  - o el atacante avanza aunque tenga tanques enemigos a 1,5 km.

  Es comportamiento (`quiereAvanzar`), no daño.

### 10.3 Decisiones para el dueño

- **D1 (P1).** Radio de la metralla:
  - el de la ficha: realista, la infantería al descubierto muere pronto;
  - o al 65 %: las mismas bajas por cohete que antes.
- **D2.** Las averías por zona ya vuelven en `averiados.zonas`, pero la
  simulación solo lee el daño (de 0 a 1), así que el taller cobra y tarda
  según ese número. Opciones:
  - (a) dejarlo así;
  - (b) que Andrés guarde las zonas y el taller repare por zona (por
    ejemplo, una oruga, rápido y barato; un motor, caro).
- **D3.** Las bajas de la tripulación de los vehículos no cuentan como
  soldados en la simulación. Opciones:
  - (a) dejarlo así;
  - (b) que cuenten como heridos y muertos de la nación.
- **D4 (P2 y P3).** Cuánto deben poder los cohetes contra los tanques y
  cómo termina una batalla que se queda en duelo de artillería.

### 10.4 Para Lucía

- **Cifras por verificar.** Las cifras reales de §4 (velocidades de boca,
  penetraciones y blindajes salvo el del T-55) están tomadas de memoria,
  sin conexión. Hay que verificarlas con las fuentes antes de darlas por
  buenas.
- **Error de puntería del fusil** (§4.5). No tiene cifra real. Con los
  valores de hoy, en la semilla 1234 dieron en un soldado 0 de 48 rayos
  resueltos: la mayoría de las ráfagas acaban en la tierra o en la
  cobertura. Con P1 hay más tiroteos para medirlo.

### 10.5 Decisiones del dueño (2026-10-01) y medidas con ellas

- **D1, metralla:** realista, con el radio de la ficha (`escalaLetal = 1`).
  «Los soldados en batalla son débiles, tiene que llevar una lógica de la
  vida real.» Al principio de la partida se lucha con soldados y pocos
  tanques; con el avance, todos prefieren tanques, lanzacohetes y otras
  unidades. No se aplica el 0,65.
- **D4, onda contra vehículos × 3:** aplicada (`explosion.onda = 1,05`, y la
  oruga con la misma onda, §7).
- **D2 y D3:** sí. Las hace Andrés en la simulación con el formato de §5.6.
  La batalla ya manda `averiados.zonas` y `tripulacion`.

**Batalla completa con la onda × 3** (las mismas condiciones que §9;
semillas 42 / 7 / 1234):

| Semilla | Duración | Gana | Tanques en pie a los 300 s (A/D) | Tanques en pie a los 600 s (A/D) | Fuera de combate al final (tanques A/D) | Bajas tripulación A / D (m/h) |
|---|---|---|---|---|---|---|
| 42 | > 900 s | — | 15 / 21 | 5 / 12 | 30 / 21 | 6/14 · 6/13 |
| 7 | > 900 s | — | 13 / 10 | 3 / 4 | 28 / 29 | 11/20 · 19/35 |
| 1234 | 558,1 s | atacante | 6 / 2 | (terminada) | 26 / 30 | 33/48 · 38/77 |

Con la onda de antes (§9.2), a los 300 s había 30/29, 25/17 y 12/5
tanques en pie y solo terminaba la semilla 1234, a los 826 s.

**Batalla de la simulación** (`pruebas_economia`, semilla 42):

- dura 311 s y el atacante se retira sin munición;
- soldados del atacante: 188 muertos, 212 heridos y 0 sanos; del
  defensor: 10, 19 y 271;
- averiados: el atacante, 34 de 60 tanques y 2 de 8 lanzacohetes; el
  defensor, 7 de 25 tanques y 0 de 6;
- munición del atacante (balas / obuses / misiles): 340 / 45 / 4; del
  defensor: 2 935 / 78 / 88;
- la prueba pasa (12 722 comprobaciones). Su foto de «averiados y sin
  obuses» ya no exige que estén a menos de 150 m: con el daño real quedan
  más repartidos y la foto sale más abierta.

**Sigue pendiente (P3, comportamiento):** en dos de tres semillas la
batalla sigue sin terminar a los 900 s con munición sin límite, porque
el atacante no avanza y los inmovilizados siguen disparando cohetes. Con
la munición de verdad, termina por munición.

## 11. Verificación de las cifras (Lucía, 2026-10-01)

Revisión de las cifras de §4 y de `dano/datos.lua` contra fuentes públicas.
Todas se consultaron el 2026-10-01 en la Wikipedia en inglés (texto fuente de
cada artículo). Donde la fuente no da la cifra, pone **no recogido**: esa
cifra queda como estimación del estudio, no como dato real.

Este documento solo propone. Valeria aplica los cambios en `dano/datos.lua`.

### 11.1 Criterio

- **Suavizado.** Se mantiene el del catálogo, `α = 0,5` con el T-72B de
  referencia (§4.2). Solo se suavizan la penetración y el blindaje de los
  tanques. Las velocidades, las tripulaciones y los calibres van tal cual.
- **Equivalente en línea de mira.** Las cifras de blindaje son mm de acero
  en horizontal, con la inclinación ya dentro (§4.1). Una chapa de *e* mm a
  60° de la vertical da *e* / cos 60° = 2·*e* mm en línea.
- **Variante.** T-72B con Kontakt-1 (1985), que es el que da la fuente con
  cifra. No el de Kontakt-5.

### 11.2 Cañones y munición perforante

| Modelo | Cifra | En `datos.lua` | Fuente | Estado | Propuesta |
|---|---|---|---|---|---|
| T-55 | v boca del 3BM8 | 1 415 m/s | «D-10 tank gun», tabla de munición: 1 415 m/s | Verificada | Igual |
| T-55 | Penetración a 2 km del 3BM8 | 275 mm | «T-54/T-55»: 275 mm a 2 km. «D-10 tank gun»: 290 mm a 0° a 1 900 m | Verificada | Igual |
| T-55 | Pérdida de velocidad del 3BM8 | 75 m/s por km (`perforante.arrastre`, común) | «D-10 tank gun»: 106,5 m/s a 1 000 m | Distinta: el 3BM8 es APDS, no flecha | Opcional (prioridad baja): arrastre propio del T-55, k = 7,8·10⁻⁵ /m |
| T-72B | v boca del 3BM42 | 1 700 m/s | «125 mm smoothbore ammunition»: 1 700 m/s | Verificada | Igual |
| T-72B | Penetración a 2 km del 3BM42 | 500 mm | Mismo artículo: 520 mm a 0° a 2 000 m (230 mm a 60°) | **Distinta** | **520** |
| M1A1 | v boca del M829A1 | 1 575 m/s | «M829»: 1 575 m/s | Verificada | Igual |
| M1A1 | Penetración a 2 km del M829A1 | 570 mm | No recogido. Solo hay la del M829 original: 540 mm a 2 km (Jane's, citado en «M829») | Estimación con cota inferior | 570 (≥ 540) |
| K2 | v boca del K279 | 1 760 m/s | «CN08 120 mm gun»: 1 760 m/s (L/55) | Verificada | Igual |
| K2 | Penetración a 2 km del K279 | 650 mm | Mismo artículo: más de 700 mm a 2 000 m (en línea, chapa a 60°) | **Distinta.** Ojo: el 3BM42 se mide contra chapa a 0° y el K279 en línea contra chapa a 60°, que suele dar algo más. No es exactamente la misma medida | **700** |
| Todos | Error de tiro (1,2 / 0,7 / 0,45 / 0,4 mrad) | — | No recogido | Estimación | Igual |
| Todos | Error en la distancia (± 5 % el T-55, ± 1 % el resto) | — | No recogido como cifra. «T-72»: telémetro láser TPD-K1 desde 1974; los telémetros ópticos de antes no servían a menos de 1 000 m. La ficha del T-55 no cita telémetro | Coherente | Igual |
| Todos | Dispersión del arma 0,25 mrad, rebote a 75°, variación ± 5 %, pen ∝ v^1,5 | — | No recogido (son reglas del modelo) | Estimación | Igual |

**Explosiva (HE-FRAG) del tanque** (`Datos.explosiva`):

| Cifra | En `datos.lua` | Fuente | Estado | Propuesta |
|---|---|---|---|---|
| v boca | 850 m/s | «125 mm smoothbore ammunition», 3OF19 y 3OF26: 850 m/s | Verificada | Igual |
| Dispersión | 0,4 mrad | Mismo artículo: dispersión máxima 0,23 mrad | **Distinta** | **0,23** |
| Radio letal 6 m y metralla 20 m (a 125 mm) | — | Mismo artículo, 3OF19: «zona letal del 90 % de 40 m de ancho y 20 m de fondo», sin cita propia. No es la misma medida que el radio de Carleton | No comparable | Igual; ver D-V3 |

### 11.3 Blindaje por zonas

En mm equivalentes en línea. «Juego» es el valor ya suavizado con la
propuesta (calculado con la fórmula de §4.2).

| Modelo | Zona | En `datos.lua` | Fuente | Estado | Propuesta (juego) |
|---|---|---|---|---|---|
| T-55 | Frente del casco | 200 | «T-54/T-55», ficha: 120 mm a 60°, **100 mm desde 1949** → 200 en línea | Verificada | 200 (310) |
| T-55 | Frente de la torreta | 205 | Ficha: 205 mm | Verificada | 205 (326) |
| T-55 | Costado del casco | 80 | Ficha: 79 mm arriba (20 mm abajo, que es la zona de orugas) | Verificada | 80 (80) |
| T-55 | Costado de la torreta | 150 | Ficha: **130 mm** | **Distinta** | **130 (180)**; hoy 194 |
| T-55 | Trasera | 45 | Ficha: **60 mm** atrás del casco a 0° y 60 mm atrás de la torreta | **Distinta** | **60 (49)**; hoy 42 |
| T-55 | Techo | 30 | Ficha: 30 mm la torreta; 33 a 16 mm el casco | Verificada | 30 (37) |
| T-72B | Frente del casco | 480 | «T-72», tabla de protección estimada (Zaloga): 480–530 mm contra flecha | Verificada (límite bajo) | 480 |
| T-72B | Frente de la torreta | 520 | Misma tabla: 520–540 mm | Verificada (límite bajo) | 520 |
| T-72B | Costados, trasera y techo (80 / 250 / 40 / 45) | — | No recogido | Estimación | Igual |
| M1A1 | Frente de la torreta | 600 | «M1 Abrams»: estimación soviética para el M1A1 de 600 mm contra flecha (Zaloga, 2009). Sin uranio; el M1A1HA da casco 600 y torreta 800 | Verificada | 600 (559) |
| M1A1 | Frente del casco | 560 | No recogido por separado (la cifra de 600 es del frente sin distinguir) | Estimación | 560 (518) |
| M1A1 | Costados, trasera y techo | — | No recogido | Estimación | Igual |
| K2 | Frente del casco y de la torreta (600 / 700) | — | No recogido contra flecha. «K2 Black Panther» solo da cifras contra carga hueca: 900 mm de frente y 330 mm de costado con reactivo (Comisión de Defensa, 2024) | Estimación | Igual; ver D-V1 |
| K2 | Costados, trasera y techo | — | No recogido | Estimación | Igual |
| Camiones | Cabina 8 mm, resto 5 mm | — | No recogido. Las fichas del BM-21 y del R-17 no dan blindaje; el M142 HIMARS puede llevar cabina blindada (foto del artículo), sin cifra | Estimación | Igual |

### 11.4 Fusil

| Cifra | En `datos.lua` | Fuente | Estado | Propuesta |
|---|---|---|---|---|
| v boca | 900 m/s | «AK-74», ficha: 880–900 m/s | Verificada | Igual |
| Penetración | 8 mm a 100 m | «5.45×39mm»: el 7N6M atraviesa 6 mm de acero St3 a 300 m. Con el arrastre y el exponente de `datos.lua`, 8 mm a 100 m dan 5,8 mm a 300 m | Coherente | Igual |
| Arrastre | 1,1·10⁻³ /m | No recogido (el artículo da el coeficiente balístico G7 = 0,168 del 7N6, pero no una tabla de velocidades) | Estimación | Igual |
| Dispersión de la ráfaga | 2,5 mrad | No recogido | Estimación | Igual |
| Error de puntería (4 / 7 / 9 mrad y 0,4 m) | — | No recogido. Es una perilla de juego (§4.5) | Perilla | Igual. **No se propone subirlo ni bajarlo** por la regla del dueño: la infantería es débil ante la artillería (§10.5, D1) |

### 11.5 Ojivas y tripulaciones

| Cifra | En `datos.lua` | Fuente | Estado | Propuesta |
|---|---|---|---|---|
| Calibre del Scud-B | 880 mm | «R-17 Elbrus»: 885 mm. «Scud missile»: 0,88 m | Verificada (redondeo) | 885 (golpe directo: 221 mm, antes 220) |
| Calibre del BM-21 | 122 mm | «BM-21 Grad»: 122 mm | Verificada | Igual |
| Calibre del M142 HIMARS | 227 mm | «M270 Multiple Launch Rocket System»: 227 mm | Verificada | Igual |
| Penetración del golpe directo (0,25 × calibre) | — | No recogido (regla del estudio) | Estimación | Igual; ver D-V2 |
| Tripulaciones | T-55 4, T-72B 3, M1A1 4, K2 3, Scud-B 7, BM-21 3, M142 HIMARS 3 | Fichas de «T-54/T-55», «T-72», «M1 Abrams», «K2 Black Panther», «R-17 Elbrus», «BM-21 Grad» y «M142 HIMARS» | Verificadas | Igual |

### 11.6 Cambios propuestos en `dano/datos.lua`

Por orden de prioridad:

1. `Datos.canones.t72b.pen2km = 520` (era 500).
2. `Datos.canones.k2.pen2km = 700` (era 650).
3. `Datos.blindajes.t55.costadoTorreta = 130` (era 150).
4. `Datos.blindajes.t55.trasera = 60` (era 45).
5. `Datos.explosiva.dispersion = 0.23` (era 0,4).
6. `Datos.calibreCohete.scudb = 885` (era 880).
7. Opcional: arrastre propio del T-55 (k = 7,8·10⁻⁵ /m), con `Datos.canones.t55.arrastre` y `Datos.canon` usando `real.arrastre or p.arrastre`.
8. Cambiar los comentarios «verificar» de `datos.lua` por «verificado» o «no recogido», como en las tablas de arriba.

**Efecto calculado (no medido en batalla).** Penetración de juego a 2 km
contra el frente de la torreta, en mm sobrantes. Negativo: no penetra en
promedio.

| Tirador → blanco | T-55 | T-72B | M1A1 | K2 |
|---|---|---|---|---|
| T-55 (hoy → propuesta) | +44 → +52 | −149 → −142 | −188 → −180 | −233 → −225 |
| T-72B | +174 → +194 | −20 → **0** | −59 → −39 | −103 → −83 |
| M1A1 | +207 → +218 | +14 → +24 | −25 → −14 | −69 → −59 |
| K2 | +244 → +277 | +50 → +83 | +12 → +45 | −33 → **0** |

- **Penetración de juego a 2 km:** T-55 371 → 378 (sale de la nueva
  referencia), T-72B 500 → 520, M1A1 534 → 544 y K2 570 → 603.
- **Lo que cambia:**
  - entre dos T-72B o dos K2, de frente y a 2 km, ahora penetra la mitad de
    las veces (antes, casi nunca);
  - el K2 se separa más de los demás. Es lo que da la fuente;
  - el T-55 sigue sin penetrar de frente a ningún tanque de era 2 o
    posterior.
- **Por lado y por detrás** el T-55 aguanta algo menos en el costado de la
  torreta (194 → 180) y algo más atrás (42 → 49).
- **Sin medir.** Hay que medirlo con `pruebas_dano` (semillas 42, 7 y 1234)
  después de aplicarlo: cañonazos que penetran, tanques en pie a los 300 s y
  duración.

### 11.7 Decisiones para el dueño

- **D-V1. Blindaje del K2 contra flecha (no hay cifra pública).**
  1. **Recomendada:** dejar 600 de casco y 700 de torreta, marcados como
     estimación del estudio. El K2 es de una era posterior al M1A1 y su
     cañón da más de 700 mm; un blindaje parecido mantiene la escalera de
     eras.
  2. Igualarlo al M1A1HA (600 / 800, la cifra pública más parecida): el K2
     se vuelve casi impenetrable de frente para todos menos para sí mismo.
- **D-V2. Penetración del golpe directo de cohetes y misiles.** Hoy no se
  suaviza: 30 mm el BM-21, 57 el HIMARS y 221 el Scud-B.
  1. **Recomendada:** dejarla así. No es un dato de la ficha, sino una
     regla del estudio, y suavizarla con `β = 1/3` daría 114 mm al BM-21 y
     140 al HIMARS: los cohetes atravesarían el costado de cualquier tanque.
     Eso iría contra la regla de que, con el avance, se prefieren los
     blindados.
  2. Suavizarla con `β = 1/3`, como el resto de los lanzacohetes del
     catálogo. Sin medir.
- **D-V3. Radio letal de la explosiva del tanque.** La única cifra pública
  (zona letal del 90 % de 40 × 20 m, unos 630 m²) sugiere un área mayor que
  la del juego (radio de 6 m, unos 113 m²), pero no tiene cita propia ni
  mide lo mismo.
  1. **Recomendada:** dejar 6 m hasta tener una fuente con la misma medida.
  2. Subir el radio letal a unos 14 m (el círculo de la misma área). La
     infantería caería mucho antes ante los tanques. Sin medir.

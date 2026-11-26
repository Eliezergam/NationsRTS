# Asentamientos: ciudades y pueblos

Diseño de los asentamientos del mapa de campaña (3D, cámara desde arriba) de
Nations RTS según el GDD «Guerra Moderna RTS» (`diseno/GDD-guerra-moderna-rts.pdf`)
y las decisiones del dueño del 2026-10-02. Los datos están en
`campana/asentamientos.lua`.

Cuando el GDD dice «mapa 2D» o «mapa operativo 2D» se refiere a este mapa de
campaña: es 3D con cámara desde arriba, como el de Bannerlord, y la vista de
radar es solo un modo de visualización con una tecla.

Estado: el sistema **no existe todavía en el código**. Lo que sigue es diseño.
Las partes marcadas **[Decisión del dueño]** ya están decididas (2026-10-02:
facciones, economía de materia prima a ciudad, inicio en Dioskar,
campamentos de milicia y escalera de lo que puede poseer el jugador); las marcadas **[Propuesta]** esperan su visto
bueno. Ninguna cifra de producción está medida porque aún no hay simulación
de esta economía.

## 1. Resumen

El mapa tiene dos tipos de asentamiento, como en Bannerlord pero modestos y
modernos, sin castillos **[Decisión del dueño]**:

- **Ciudad (18):** centro económico, político y de reclutamiento. Tiene mercado,
  cuartel general, diplomacia local y, según el tamaño, taller, hangar, fábrica
  de munición, refinería y mercado negro. Es donde ocurren los asedios urbanos.
- **Pueblo (67):** motor económico. Produce una materia prima y la manda por
  convoy civil a su ciudad, que la convierte en lo que gasta la guerra:
  combustible, munición, repuestos y tropas.

Todos los nombres de asentamientos y facciones son inventados; las posiciones
salen de ciudades y pueblos reales de la zona (puertos, cruces de valles, bocas
de pasos de montaña) y caen sobre el relieve real del mapa.

## 2. Fantasía del jugador

El jugador empieza desde abajo, como en Bannerlord **[Decisión del dueño]**:
un combatiente o contratista con poco. Para él, al principio, las ciudades no
son suyas: son el sitio donde se firman contratos, se recluta, se compra
munición, se repara el blindado y se vende lo capturado en el mercado negro.
Los pueblos son lo que mueve esas ciudades: el campo de trigo, el pozo, la
mina, la cantera y las familias de donde salen los reclutas.

En cada ciudad y pueblo hay **notables** (alcalde, jefe de clan, contrabandista,
director de la refinería) que dan contratos y misiones, como en Bannerlord, y
por el mapa se cruza con los **generales** de las facciones, que reclutan en
los mismos pueblos y compran en los mismos mercados que él, con las mismas
reglas.

Con el tiempo aprende que una ciudad sin sus pueblos se para. Escoltar un
convoy de acero a la fábrica de munición, defender un pozo o cortar la ruta de
crudo de un rival son contratos con sentido, y la geografía real (pasos de
montaña, valles, costa) decide por dónde pasan.

## 3. Reglas

### 3.1 Ciudad

1. Cada ciudad pertenece a una facción (`faccion`). El jugador no posee
   ninguna al empezar; empieza en Dioskar.
2. Edificios de la ciudad (todos los del GDD, apartado 3.1):
   - **Mercado:** compra y venta de recursos a precio según existencias.
   - **Cuartel general (HQ):** recluta y entrena infantería con los reclutas
     y la comida que llegan de los pueblos.
   - **Diplomacia local:** contratos y reputación con la facción dueña.
   - **Taller / garaje:** repara vehículos ligeros y fabrica kits de repuestos.
   - **Hangar de blindados:** guarda e inspecciona tanques, VCI y helicópteros.
   - **Fábrica de munición:** convierte acero y explosivos en cajones.
   - **Refinería / depósito:** convierte crudo en combustible.
   - **Mercado negro:** compra y vende lo capturado, sin importar la facción.
3. **[Propuesta]** No todas las ciudades tienen todo. Tres tamaños:
   - **Capital** de cada facción (Kamennovodsk, Mtkvarisi, Kapazli,
     Vardanakert, Mavikıyı, Ardzun) y Dioskar: todos los edificios.
   - **Puerto** que no es capital (Zalivsk, Burunsk, Zghvispiri): mercado
     negro y refinería.
   - **Ciudad de provincia** (el resto): mercado, HQ, taller y una fábrica o
     refinería según lo que produzcan sus pueblos.
4. Una ciudad atacada lleva a una batalla 3D en su propia estructura urbana
   (asedio urbano del GDD, 3.3).

### 3.2 Pueblo

1. Cada pueblo produce **una** materia prima (`produce`) y está vinculado a
   **una** ciudad (`ciudad`), que siempre es la más cercana.
2. Cada día acumula su producción en un almacén propio.
3. **[Propuesta]** Cada 3 días sale un convoy civil con lo acumulado hacia su
   ciudad, por el camino más corto del relieve. Al llegar, la carga entra en
   los almacenes de la ciudad.
4. Un convoy civil es atacable. Si lo destruyen o lo capturan, la carga se
   pierde o pasa al atacante.
5. **[Propuesta]** Un pueblo puede ser saqueado (como en Bannerlord): queda
   arrasado unos días, no produce y su prosperidad baja.
6. Los pueblos no tienen asedio; la defensa es una batalla de campo en 3D.

### 3.3 Qué produce cada tipo de pueblo [Decisión del dueño, 2026-10-02]

Los pueblos producen materias primas y las ciudades las convierten en los
recursos del GDD (decidido). Los cinco tipos de la tabla son propuesta. Así los pueblos importan (sin ellos la fábrica se para) y
hay rutas que escoltar o cortar.

| `produce` | Qué es | En la ciudad se convierte en | Pueblos |
|---|---|---|---|
| `comida` | Trigo, ganado, huerta, té, cítricos | Mantener la guarnición y entrenar reclutas | 21 |
| `reclutas` | Pueblos de valle con tradición de servicio | Infantería en el HQ (junto con comida) | 18 |
| `acero` | Mina, fundición o chatarrería | Munición (fábrica) y kits de repuestos (taller) | 11 |
| `explosivos` | Planta química, nitratos o cantera con polvorín | Munición (fábrica) | 11 |
| `crudo` | Pozos de petróleo | Combustible (refinería) | 6 |

Los pozos están donde hay petróleo de verdad en la región (Kubán, Maikop,
Dagestán, Samgori junto a Tiflis y el llano del Kurá). Por eso son pocos y
están repartidos de forma desigual: Anzerat, Pontara y el puerto franco no
tienen crudo propio y tienen que comprarlo o conseguirlo.

### 3.4 Facciones [Decisión del dueño, 2026-10-02]

Siete facciones, al estilo de los reinos de Bannerlord (cada una con su región,
su cultura y su estilo militar), con los tipos del GDD (sección 8.1):

| id | Nombre | Tipo (GDD) | Región real | Estilo de tropas y equipo | Ciudades | Pueblos |
|---|---|---|---|---|---|---|
| `voskara` | Unión Voskara | Ejército regular | Estepa y vertiente norte, del Mar Negro al Caspio | MBT, artillería pesada y TEL | 5 | 19 |
| `kelvana` | República Kelvana | Ejército regular | Cólquida y valle central | Infantería ligera bien equipada, drones | 3 | 12 |
| `hazarli` | Federación Hazarlí | Ejército regular | Llano del Kurá y vertiente sur del Gran Cáucaso | Rica en petróleo: compra blindados y contrata PMC | 3 | 10 |
| `anzerat` | República de Anzerat | Ejército regular | Altiplano volcánico del sur | Artillería de montaña, defensa fortificada | 2 | 8 |
| `pontara` | Liga de Pontara | Ejército regular | Costa del Ponto y montañas al sur | Columnas motorizadas rápidas, todoterrenos y MRAP | 2 | 7 |
| `ardzun` | Hermandad de Ardzun | Milicia regional | Piedemonte norte central y oriental | Emboscadas, IED, ATGM y RPG; sin blindaje pesado | 2 | 8 |
| `libre` | Puerto franco de Dioskar | Neutral | Costa nordeste del Mar Negro | Guarnición pequeña; mercado negro | 1 | 3 |

La columna «Estilo de tropas y equipo» es una propuesta.

- **Inicio del jugador [Decisión del dueño]:** en el puerto franco de
  Dioskar, sin bando, con mercado negro y contratos de todas las facciones.
- Las **PMC** no tienen territorio (GDD 8.1: «ausencia de territorio patrio
  fijo»). Operan desde cualquier ciudad con contratos, como los clanes
  mercenarios de Bannerlord.
- Doctrinas, clanes, generales y reputación: `../VISION.md`, sección 5.

### 3.5 Lista de ciudades

| Ciudad | Facción | Sitio real | Por qué ahí |
|---|---|---|---|
| Zalivsk | voskara | Novorossiysk | Puerto del Mar Negro, salida de la estepa del Kubán |
| Krasnoles | voskara | Maikop | Piedemonte noroeste, petróleo y bosque |
| Kamennovodsk | voskara | Piatigorsk | Cruce de la estepa con el Cáucaso central |
| Vorotsk | voskara | Vladikavkaz | Boca norte del paso de Darial, la llave al valle central |
| Burunsk | voskara | Majachkalá | Puerto del Caspio, petróleo |
| Uzdenkala | ardzun | Nalchik | Boca del valle del Baksán, piedemonte |
| Ardzun | ardzun | Jasaviurt | Cruce de caminos del piedemonte oriental |
| Dioskar | libre | Sujumi | Puerto entre montaña y mar |
| Zghvispiri | kelvana | Batumi | Puerto del sur del Mar Negro, frontera con Pontara |
| Rioneli | kelvana | Kutaisi | Corazón de la Cólquida, paso de Rikoti al este |
| Mtkvarisi | kelvana | Tiflis | Cruce del valle central, salida sur del Darial |
| Kapazli | hazarli | Ganyá | Piedemonte del Cáucaso Menor, minas |
| Kurabad | hazarli | Yevlaj | Cruce del Kurá en el llano |
| Ipekli | hazarli | Shekí | Vertiente sur del Gran Cáucaso |
| Vardanakert | anzerat | Ereván | Llanura del Ararat, al pie de los volcanes |
| Tufashen | anzerat | Guiumri | Altiplano de Shirak, a 1.535 m |
| Mavikıyı | pontara | Trebisonda | Puerto del Ponto |
| Taşhisar | pontara | Bayburt | Valle alto del Çoruh, tras el paso de Zigana |

### 3.6 Huecos del mapa y campamentos de milicia

El reparto deja zonas sin asentamientos a propósito: la estepa norte entre
Kamennovodsk y el Caspio, el valle de Kajetia (entre Mtkvarisi e Ipekli), la
Svanetia alta, el Daguestán montañoso y la costa occidental del Ponto. Son
tierra de nadie para convoyes, batallas de campo y campamentos de milicia.

- **Campamentos de milicia [Decisión del dueño]:** sí, al estilo de las
  guaridas de bandidos de Bannerlord.
- **[Propuesta]** Puntos pequeños, sin pueblos, que salen en zonas de
  montaña o estepa, atacan convoyes y se pueden destruir por contrato. No
  están en `asentamientos.lua`.

### 3.7 Qué puede llegar a poseer el jugador [Decisión del dueño, 2026-10-02]

El jugador empieza sin nada, en Dioskar. La escalera, en este orden:

1. **Plaza de hangar** en una ciudad, con reputación con su facción.
2. **Taller propio** al fundar su PMC: produce kits o munición para él con
   materia prima comprada.
3. **Proteger un pueblo** a cambio de una parte de su producción mientras
   lo defienda.
4. **Una ciudad**, concedida por una facción o conquistada.

**[Propuesta]** Umbrales: plaza de hangar con reputación «Favorable» (+11);
protección de un pueblo con «Favorable» con su facción o con el pueblo sin
dueño defendido; parte del pueblo, un 25 % de su producción.

## 4. Fórmulas [Propuesta, sin medir]

Ninguna cifra está medida: no hay simulación de este sistema todavía. Las
unidades son «lotes» (el tamaño de un lote lo fija la economía cuando exista).

**Producción diaria de un pueblo:**

`produccion = base[produce] * prosperidad * (1 - saqueado)`

- `base`: comida 20, reclutas 4, acero 8, explosivos 6, crudo 12 (lotes/día).
- `prosperidad`: 0,5 a 1,5; empieza en 1,0. Sube +0,01 por convoy entregado y
  baja −0,3 por saqueo.
- `saqueado`: 1 mientras está arrasado (7 días), 0 si no.
- Ejemplo: Neftekamenka (crudo) con prosperidad 1,2 → 12 × 1,2 = 14,4 lotes/día;
  en 3 días el convoy lleva 43 lotes a Zalivsk.

**Conversión en la ciudad (por lote de salida):**

| Edificio | Entrada | Salida |
|---|---|---|
| Refinería | 1 crudo | 10 combustible |
| Fábrica | 1 acero + 1 explosivos | 6 cajones de munición ligera |
| Fábrica | 2 acero + 1 explosivos | 3 cajones de munición pesada |
| Fábrica | 2 acero + 2 explosivos | 1 cajón de 120 mm o ATGM |
| Taller | 2 acero | 1 kit de repuestos |
| HQ | 1 reclutas + 2 comida | 1 soldado entrenable |

- Ejemplo: Mtkvarisi recibe al día 8 de acero (Pholadauri) y 6 de explosivos
  (Azotiani). Si toda la fábrica hace munición ligera: 6 × 6 = 36 cajones al
  día, y sobran 2 de acero para 1 kit de repuestos.

**Precio en el mercado:**

`precio = precioBase * clamp(sqrt(existenciasObjetivo / (existencias + 1)), 0.5, 2.0)`

- Ejemplo: munición ligera, precio base 100, objetivo 200, existencias 50 →
  sqrt(200 / 51) = 1,98 → 198.

**Tiempo del convoy civil:** `dias = distanciaKm / 120`. Los pueblos están a
6–39 km de su ciudad: el viaje dura de 1 a 8 horas de juego.

## 5. Casos límite

- **Ciudad que cambia de facción:** sus pueblos cambian con ella; no hay
  pueblos de una facción abasteciendo a una ciudad de otra.
- **Pueblo saqueado:** no produce durante 7 días; el almacén se pierde.
- **Convoy capturado por el jugador:** la carga pasa a su columna; reputación
  con la facción dueña −5 [Propuesta].
- **Ciudad sin pueblos productores de un recurso:** su edificio se queda
  parado salvo que el recurso se compre en el mercado o llegue por convoy de
  comercio de otra ciudad.
- **Ciudad sitiada:** los convoys de sus pueblos no entran; esperan en el
  pueblo hasta que se levante el asedio.
- **Almacén lleno:** propuesta de tope de 30 días de producción por pueblo; lo
  que pasa del tope se pierde.

## 6. Dependencias

**De qué depende:**
- Mapa de campaña 3D (`campana/mapa3d.lua`, `assets/mapa/caucaso*.bin/.lua`):
  las `x`, `z` usan su sistema (km, X al este, Z al sur, origen en el centro).
- Economía del GDD (combustible, munición, repuestos): las salidas de las
  conversiones.
- Facciones y reputación (GDD 8): dueño de cada asentamiento y precios.

**Qué depende de él:**
- Contratos (escolta de convoyes, defensa de infraestructura, asalto).
- Reclutamiento del jugador y de los generales.
- Hub urbano 3D y asedios urbanos: una escena por ciudad.
- Batallas de campo 3D: se generan en el sitio del pueblo o de la ruta.
- Vista de radar: iconos de ciudad y pueblo.

## 7. Perillas de ajuste [Propuesta, sin medir]

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| `base.comida` | 20 | 10–40 | Más alto: reclutar sale barato |
| `base.reclutas` | 4 | 2–8 | Ritmo al que crecen los ejércitos |
| `base.acero` | 8 | 4–16 | Munición y repuestos disponibles |
| `base.explosivos` | 6 | 3–12 | Cuello de botella de la munición |
| `base.crudo` | 12 | 6–24 | Cuánto pueden moverse las columnas |
| `intervaloConvoy` (días) | 3 | 1–7 | Más alto: convoys más ricos y más tentadores |
| `diasSaqueo` | 7 | 3–14 | Castigo de un saqueo |
| `topeAlmacen` (días) | 30 | 10–60 | Cuánto aguanta un pueblo aislado |
| `prosperidadMin/Max` | 0,5 / 1,5 | 0,3–2,0 | Diferencia entre un pueblo mimado y uno castigado |
| `distanciaPuebloMax` (km) | 40 | 25–50 | Hasta dónde llega el área de una ciudad |

## 8. Criterios de aceptación

Comprobados ya sobre los datos (medidos el 2026-10-02 con el relieve de
`assets/mapa/caucaso_alturas.bin`):

- `campana/asentamientos.lua` carga con LuaJIT y devuelve 85 entradas
  (18 ciudades, 67 pueblos); `luacheck` y `stylua --check` sin avisos.
- Ningún asentamiento cae en el mar (altura mínima: 1 m, Porokhovaya Pristan).
- Cada pueblo está a entre 5 y 40 km de su ciudad (medido: de 6,1 km,
  Kimiuri, a 38,7 km, Svintsovy).
- Cada pueblo tiene como ciudad la más cercana de todas.
- Ningún pueblo en cumbre: pendiente media en 1,5 km de 8,7° como máximo y
  altura relativa en un radio de 10 km por debajo del 60 % del desnivel local.
- Distancia mínima entre ciudades: 63,5 km (Kurabad–Ipekli).

Para cuando exista la simulación (sin medir):

- Con prosperidad 1 y sin ataques, cada ciudad recibe en 30 días
  `30 × base × pueblos` de cada materia prima, con un error < 1 %.
- Una ciudad con todos sus pueblos saqueados deja de producir munición en
  cuanto se le acaba el almacén.
- En 100 días de simulación ninguna facción con crudo propio se queda a 0 de
  combustible si no está en guerra.

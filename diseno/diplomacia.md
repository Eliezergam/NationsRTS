# Diplomacia

> Superado por VISION.md (GDD Guerra Moderna, 2026-10-02).

Fuentes: `mundo/simulacion.lua` — `negociar` :1541, `altoElFuego` :1513,
`firmarPaz` :1525, `guerra` :1601 (fase de calma), `sumarCansancio` :637,
`avanzarDia` :1651 (decaimiento), `ejecutar` :519 (comandos `altoElFuego` y
`firmarPaz`).

## 1. Resumen

Mientras dura una guerra, los dos presidentes pueden sentarse a hablar. La
probabilidad crece con el **cansancio de guerra** de ambos (que suman los daños
sufridos) y con su prudencia. Del encuentro sale una de tres cosas: **paz con
concesión** (el más castigado cede una instalación o una ciudad), **alto el
fuego** de 5 a 29 días, o **fracaso**. Al terminar un alto el fuego, o se rompe
(vuelve la tensión) o "la calma se consolida" y se firma la paz. Tras la paz hay
90 días de tregua.

## 2. Fantasía del jugador

Que las guerras tengan final y el final tenga sentido: el que ha sufrido más
pide la paz y paga por ella; los presidentes prudentes hablan antes; un alto el
fuego frágil entre dos halcones se rompe. Ver en el mapa cómo una ciudad cambia
de bandera por un tratado, no por un asedio.

## 3. Reglas

### Cansancio de guerra (por nación, compartido entre todas sus guerras)

Sube (todo definido en [guerra.md](guerra.md)):

| Hecho | A quién | Cuánto |
|---|---|---|
| Impacto de misil en una instalación | Dueño | +0,05 por impacto |
| Lanzar misiles | Atacante | +0,01 por misil |
| Incursión: bombas que llegan / cazas perdidos | Defensor | +0,1 por avión que pasa, +0,3 por caza perdido |
| Incursión: aviones perdidos | Atacante | +0,3 por avión |
| Combate terrestre | Cada bando | +0,01 por baja propia |
| Instalación tomada | Quien la pierde | +4 |
| Instalación destruida | Dueño | +3 |
| Misil en una ciudad | Víctima | +0,6 por impacto |

Baja: × 0,995 cada día (todas las naciones vivas) y, además, × 0,97 cada día
que una guerra suya está en calma (por cada guerra en calma).

### Negociar (`negociar`), solo en días de tensión

1. Requiere `g.dias ≥ 4` (cuenta todos los días de la guerra, también de calma).
2. Tirada: `azar < 0,02 + 0,006 × (cansancio_A + cansancio_B) + 0,03 ×
   prudencia_media`. Si falla, no hay conversaciones.
3. Cansado = el de más cansancio; fresco = el otro. Segunda tirada `t`:
   - **Paz con concesión** si `t < 0,5`, `cansancio_cansado > 2 × cansancio_fresco + 4`
     y la guerra dura más de 20 días:
     - si el cansado tiene > 20 de cansancio, cede **una ciudad que no sea la
       capital** (la última de su lista ordenada por id), con toda su población,
       soldados y arsenal;
     - si no (o no tiene otra ciudad), cede su **primera extracción** (por id);
     - si no tiene extracciones, paz sin concesión.
     - Luego `firmarPaz`.
   - **Alto el fuego** si no se dio lo anterior y `t < 0,8`: duración
     `floor(azar(5, 30))` = 5–29 días.
   - **Fracaso** en el resto (`t ≥ 0,8`): solo la noticia.

### Alto el fuego (`altoElFuego`)

- Fase `calma` hasta `día + duración`. Relación +18.
- Todos los grupos de ataque de los dos bandos vuelven a casa. Los refuerzos y
  convoyes siguen; **los misiles y aviones ya en vuelo siguen y golpean**.
- Por comando: `{ tipo = 'altoElFuego', nacion, contra, dias }` (15 por defecto).

### Fin de la calma (`guerra`, fase `calma`)

Cuando llega `faseHasta`: si la relación es < −45 y
`azar < 0,8 × max(agresividad_A, agresividad_B)`, **se rompe** y vuelve la
tensión. Si no, `firmarPaz` con ": la calma se consolida".

### Paz (`firmarPaz`)

- Borra la guerra; tregua de 90 días para los dos; relación +35.
- Los grupos de ataque vuelven a casa.
- Por comando: `{ tipo = 'firmarPaz', nacion, contra }` (sin concesión).

### Otras formas de acabar

Si un bando se queda sin ciudades, la guerra se borra sin noticia. Hoy no
ocurre: la capital nunca se cede.

## 4. Fórmulas

**Probabilidad de negociar.** Cansancios 5 y 3, prudencias 0,4 y 0,6:
`0,02 + 0,006 × 8 + 0,03 × 0,5 = 0,083` por día de tensión. Rango típico:
0,023 (sin cansancio, imprudentes) a ~0,2 (cansancios de 15).

**Reparto de resultados** cuando se negocia (sin condición de concesión): 80 %
alto el fuego, 20 % fracaso. Con la condición cumplida: 50 % paz con
concesión, 30 % alto el fuego, 20 % fracaso.

**Ruptura del alto el fuego.** Relación en guerra suele estar en −100; tras
+18 queda en −82 (< −45), así que se rompe con probabilidad `0,8 × agr_max`:
0,4 con un halcón de 0,5, 0,74 con uno de 0,93.

**Paz con concesión.** Ejemplo: A cansancio 22, B 7: `22 > 2×7 + 4 = 18` → si la
guerra lleva > 20 días y `t < 0,5`, A cede una ciudad (22 > 20).

**Medido (500 días, 6 semillas):**

| Medida | Valor |
|---|---|
| Altos el fuego | 69–129; duración mediana 15–18 días |
| Rupturas | 25 / 57 / 77 (semillas 4242 / 1 / 7) |
| Conversaciones fracasadas | 17 / 25 / 32 (4242 / 1 / 7) |
| Guerras cerradas | 27–60 |
| … por "la calma se consolida" | 83–91 % |
| … por paz con concesión | 4–9 por semilla |
| Ciudades cedidas | 1–3 por semilla |
| Duración de guerra cerrada, mediana | 36–51 días (máx. 113–247) |
| Cansancio del atacante al declarar, mediana (4242) | 2,2 |
| Cansancio máximo de los dos al firmar la paz, mediana (4242) | 5,6 (máx. 22,4) |
| Días de calma / días de guerra | 54–60 % |

A 1000 días (4242): 97 guerras, 166 altos el fuego, 86 de 95 cierres por
calma consolidada, 2 ciudades cedidas.

## 5. Casos límite

- **Cansancio compartido:** una nación en dos guerras suma el cansancio de
  ambas; puede ceder en una guerra lo que perdió en la otra.
- **Condición de concesión cumplida pero `t` entre 0,5 y 0,8:** alto el fuego.
- **El cansado solo tiene la capital:** cede una extracción aunque tenga > 20 de
  cansancio.
- **Ciudad cedida:** se va con población, soldados, tanques y arsenal. La
  elegida es la última por id, no la más cercana al vencedor: puede quedar
  como enclave lejos de su nuevo país.
- **Extracción cedida en obras:** se cede igual, a medio hacer.
- **Paz tras alto el fuego:** es la vía normal (83–91 %); la mayoría de las
  guerras no terminan por una decisión, sino porque la calma no se rompe.
- **Tregua:** 90 días sin poder declararse la guerra entre ellos; no impide
  guerras con terceros.
- **Comando `firmarPaz` sin guerra:** devuelve `nil`/`false`, no hace nada.
- **Negociación en calma:** no ocurre (la fase de calma sale antes).

## 6. Dependencias

- **Depende de:** [guerra.md](guerra.md) (fuente de todo el cansancio),
  [naciones-y-politica.md](naciones-y-politica.md) (prudencia, agresividad,
  relaciones), [instalaciones-y-economia.md](instalaciones-y-economia.md) (qué
  hay para ceder).
- **Lo usan:** [naciones-y-politica.md](naciones-y-politica.md) (treguas, +18 y
  +35 de relación), [guerra.md](guerra.md) (fase de calma detiene ataques;
  vuelta de grupos), [instalaciones-y-economia.md](instalaciones-y-economia.md)
  (cesiones cambian dueños y territorio).

## 7. Perillas de ajuste

| Constante | Valor | Rango seguro | Efecto |
|---|---|---|---|
| Base de negociar | 0,02 | 0–0,05 | Guerras que se hablan sin daños. |
| Peso del cansancio | 0,006 | 0,002–0,02 | Cuánto acorta la guerra sufrir. |
| Peso de la prudencia | 0,03 | 0–0,1 | Carácter del presidente. |
| Días mínimos | 4 | 1–30 | — |
| Condición de concesión | > 2×fresco + 4, > 20 días | — | Frecuencia de tratados con cesión (hoy 4–9). |
| Umbral de ceder ciudad | cansancio > 20 | 10–40 | Ciudades cedidas (hoy 1–3). |
| Reparto de tirada | 0,5 / 0,8 | — | Paz / alto el fuego / fracaso. |
| Duración del alto el fuego | 5–29 días | 3–60 | Ritmo de la guerra. |
| Relación por alto el fuego / paz | +18 / +35 | 0–50 | Si pasan de −45, ya no se rompe. |
| Ruptura | rel < −45 y 0,8·agr_max | — | Hoy casi toda guerra acaba así o en paz tácita. |
| Tregua | 90 días | 30–365 | Pausa entre guerras del mismo par. |
| Decaimiento del cansancio | ×0,995 / ×0,97 en calma | — | Memoria del sufrimiento. |

## 8. Criterios de aceptación

16 zonas, 500 días (medido entre paréntesis):

- Entre 60 y 140 altos el fuego (69–129), todos de 5 a 29 días.
- Entre 3 y 10 paces con concesión (4–9).
- Entre 1 y 4 ciudades cedidas (1–3); ninguna capital cedida (por construcción).
- Mediana de duración de guerras cerradas entre 30 y 60 días (36–51).
- Al menos una guerra abierta el día 500 (5–9).
- Ningún ataque (salva, incursión, grupo) ordenado en fase de calma (por
  construcción; no medido).

No medido: cuántas guerras se reabren al acabar la tregua entre el mismo par.

## Propuestas (no implementadas)

- **P1. Paz como decisión, no como inercia.** Hoy el 83–91 % acaba porque la
  calma "se consolida". Opción A: al acabar la calma, negociar de verdad (paz,
  prórroga o ruptura) con las mismas reglas. Opción B: la paz tácita exige que
  la relación haya subido por encima de −45.
- **P2. Ceder lo que tiene sentido**: la ciudad o la extracción más cercana al
  vencedor, o la que este más codicia (`recursosEnDisputa`), en vez de la
  última/primera por id.
- **P3. Cansancio por guerra**, además del nacional, para que ceder en una
  guerra no dependa de otra.
- **P4. Violaciones del alto el fuego**: si un impacto cae en calma, subir la
  probabilidad de ruptura (enlaza con guerra.md P1).
- **P5. Condiciones de rendición** que permitan que una nación desaparezca o se
  convierta en vasallo, si el dueño lo quiere.

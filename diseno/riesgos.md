# Registro de riesgos

Lo que puede salir mal en Nations RTS, cuánto afectaría y qué se está haciendo.
Se revisa al empezar cada sesión de trabajo; los riesgos que ya no aplican se
cierran.

- **Impacto** (0–5): 0, nada; 5, impide sacar el juego.
- **Probabilidad** (0–5): 0, imposible; 5, ya está pasando.
- **Total:** impacto × probabilidad (máximo 25).
- **Estado:** reparación activa (como máximo 5 a la vez), vigilar, normal,
  ignorar por ahora o cerrado.

| Riesgo | Impacto | Prob. | Total | Estado | Señal de alarma | Qué se hace | Dueño | Revisado |
|---|---|---|---|---|---|---|---|---|
| El alcance tipo Bannerlord es enorme: mapa de campaña, hub, batalla en persona, facciones con generales, economía logística, TEL… | 5 | 4 | 20 | Vigilar | Una etapa que no se puede enseñar en una sesión; varias etapas abiertas a la vez | Las 13 etapas de `VISION.md` (sección 6), una cada vez y aprobada antes de la siguiente; si una no cabe, recortar su alcance y ofrecerlo como opción | Bruno | 2026-10-02 |
| El mapa de campaña se ve pobre de cerca: el relieve viene de muestras de unos 185 m (fino) y unos 740 m (malla gruesa) | 3 | 5 | 15 | Reparación activa | Capturas cercanas con laderas planas o borrosas frente a la referencia de Calradia | Detalle de cerca para el mapa (Valeria trabaja en `campana/detalle_mapa.lua` y en los datos de `tools/mapa/caucaso.py`) | valeria | 2026-10-02 |
| El mapa entero va a unos 40 FPS | 3 | 5 | 15 | Reparación activa | FPS medios por debajo de 60 o 1 % peor por debajo de 30 con el mapa entero a la vista | Niveles de detalle, impostores, recorte por vista y generación en hilos; medir FPS medios y 1 % peor antes y después | valeria | 2026-10-02 |
| El código del juego anterior en `mundo/` (simulación, terreno procedural y mapa isométrico) sigue sin decidir | 3 | 3 | 9 | Vigilar | Un trabajo nuevo que toca `mundo/`; pruebas viejas que fallan o se vuelven ruido | Llevar al dueño la decisión con opciones (qué se reaprovecha, qué se archiva) antes de que una etapa dependa de ello | Bruno | 2026-10-02 |
| Codex trabaja en el mismo repositorio y commitea sin avisar | 3 | 3 | 9 | Normal | Commits ajenos en `git log` sobre archivos de una tarea en curso; cambios sin commitear que nadie reconoce | `git log` y `git status` antes de planificar y antes de cada commit; bloqueos con `tools/bloqueo.sh`; commits solo de los archivos propios | todos | 2026-10-02 |

## Historial

- **2026-10-02:** se abre el registro con cinco riesgos.

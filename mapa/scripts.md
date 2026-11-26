# Mapa de `scripts/`

Generado por `tools/generar_mapa_codigo.py`. Índice general: `../MAPA-DEL-CODIGO.md`.
Cada módulo: propósito, dependencias (`require`) y funciones públicas con su
línea de archivo. Las `local function` solo se cuentan.

## scripts/mover.lua

Script de ejemplo. Asignalo a un objeto desde el inspector (fila Script, boton ...). Contrato: new(obj, world, params) -> entidad con update(dt) y opcionalmente draw().

- Tamaño: 22 líneas, 2 funciones públicas, 0 locales.

- `Mover.new(obj, world, params)` (l.9)
- `Mover:update(dt)` (l.16)


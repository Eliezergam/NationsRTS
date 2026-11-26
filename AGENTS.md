# AGENTS.md — guide for AI assistants (and humans)

Read this before changing anything. The project is written in Spanish (code
names, comments, documents): keep it that way, and answer the owner in
Spanish. You may write pull request descriptions in English or Spanish.

Lee esto antes de cambiar nada. El proyecto está en español (nombres,
comentarios y documentos): mantenlo así.

## What the game is / Qué es

Nations RTS: a modern-war strategy game. A procedural world map (2D,
isometric) with nations, cities and mines simulated day by day, and a 3D
battle scene at real scale (robots with personalities, vehicles, aircraft).
Direction and the owner's decisions: `VISION.md`. Designs: `diseno/`.

## Run it / Cómo se ejecuta

- LÖVE 11.5 (LuaJIT). From the repository root:
  - `love . 2026 --jugador` — the world map with seed 2026, skipping the login.
  - `BATALLA_LUGAR=metal love . 2026 --batalla preparacion 999999` — straight
    into a 3D battle at a metal mine (`oro`, `nuestra` for other sites).
- Packaging: `EMPAQUETADO.md`.

## Where things are / Dónde está cada cosa

- `MAPA-DEL-CODIGO.md` (generated, one line per module) and `mapa/<folder>.md`
  (signatures). Start there instead of grepping blindly.
- `ARQUITECTURA.md`: the two worlds. The physical world (terrain, plants,
  cities, mines) comes from the seed and is never saved; the living world
  (`mundo/simulacion.lua` and `mundo/simulacion/`) is saved and must stay
  **deterministic**: no `math.random`, no unordered `pairs` in decisions, no
  LÖVE calls. Every change from outside goes through `Simulacion:ejecutar`.
- `batalla/`: the 3D scene (3DreamEngine in `lib/`), `batalla/robots/` the
  robot system (types + specializations, like Farming Simulator).
- `interfaz/`: UI drawn in Lua. `tools/`: scripts (Blender models are built by
  Python scripts in `tools/blender/`).

## Code style / Estilo

- Lua with `local` everywhere, **camelCase**, one module per responsibility.
- Nothing compacted: one statement per line, spaces around operators, no
  one-line `if … then … end` chains.
- A comment above every function saying what it does, in Spanish.
- Real units: 1 m = 10 px in the battle; sizes in `medidas.lua`.
- Visuals: real PBR textures (CC0) and real geometry; no washed-out colors, no
  faceted or toothed shapes.

## Before you open a pull request / Antes del *pull request*

1. Run the game and look at what you changed (map or battle). Attach
   screenshots for anything visual.
2. Check the console for `Error` lines.
3. Only assets you may share (see `CONTRIBUTING.md`), with their source in the
   folder's `LICENCIAS.md`.
4. Small, focused changes. Don't reformat files you didn't need to touch.
5. Don't change `VISION.md` decisions on your own: propose them in an issue.

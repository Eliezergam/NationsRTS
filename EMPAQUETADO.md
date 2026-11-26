# Empaquetado de NationsRTS

NationsRTS se distribuye en tres formas: `.love` (oficial LÖVE),
AppImage (Linux, sin instalar nada) y `.exe` (Windows).

## Compilar (Linux)

```bash
cd ~/PracticalMapEditor/NationsRTS
bash build/build-appimage.sh
```

El script:

1. Descarga `love-11.5-x86_64.AppImage` y `appimagetool` si no están en
   `build/work/`.
2. Empaqueta el juego como `.love` (un zip con `main.lua` en la raíz).
   Excluye `assets/source_packs/`, `assets/previews/` y
   `batalla/dream/capturas/` (no son parte del juego).
3. Ensambla el AppImage: binario de LÖVE + `.love` pegados al final,
   icono, `.desktop` y AppRun.
4. Copia el `.desktop` a `~/.local/share/applications/` para que
   aparezca en el menú de tu Hyprland.

El `.desktop` lanza con `--dream --jugador`: el juego arranca en modo
jugador con el motor 3DreamEngine activo (texturas, luces y sombras
en la batalla 3D). Para abrirlo sin esas flags, pasalas a mano al
AppImage desde la terminal.

Salida:

- `build/work/NationsRTS.love` — paquete oficial LÖVE (7.8 MB).
- `dist/NationsRTS.AppImage` — ejecutable con LÖVE incluido (13 MB).
- `dist/NationsRTS.desktop` — acceso directo copiado también a
  `~/.local/share/applications/NationsRTS.desktop`.

## Usar en Linux

Doble clic sobre `dist/NationsRTS.AppImage`, o desde la terminal:

```bash
./dist/NationsRTS.AppImage
```

Para que aparezca en tu menú de aplicaciones:

```bash
update-desktop-database ~/.local/share/applications
```

## Compilar para Windows (vos)

No tengo Windows para compilar el `.exe`, pero vos lo generás con dos
pasos. Una vez que tengas `NationsRTS.love`:

1. Descargá LÖVE para Windows desde
   https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip
   y extraé `love.exe` en una carpeta (por ejemplo `C:\love-win64\`).

2. Pegá el `.love` al final de `love.exe`. En PowerShell o CMD:

   ```
   copy /b love.exe + NationsRTS.love NationsRTS.exe
   ```

   Quedan juntos como un solo `NationsRTS.exe` que se distribuye sin
   instalar nada.

3. Para un acceso directo en el escritorio y el menú, hacé un `.msi` o
   un `.iss` con Inno Setup, o un simple `NationsRTS.bat` con:

   ```bat
   @echo off
   start "" "%~dp0NationsRTS.exe" %*
   ```

## Lo que incluye el paquete

- `main.lua`, `conf.lua`, `project.lua`.
- `assets/` (sprites, paletas, modelos 3D, capturas excluidas).
- `batalla/`, `mundo/`, `interfaz/`, `depurar/`, `lib/` (incluye
  3DreamEngine y sus extensiones), `scripts/`, `ui/`, `maps/`,
  `diseno/`.
- `ARQUITECTURA.md`, `VISION.md`, `GUIA-3D.md`.

## Lo que NO incluye

- `assets/source_packs/` — packs originales de Synty Studios. Material
  de trabajo, no parte del juego.
- `assets/previews/` — previsualizaciones para vos.
- `batalla/dream/capturas/` — comparaciones de prueba.
- `batalla/pruebas_*/` — pruebas y benchmarks.
- `tools/` — scripts de Blender y Python para re-exportar assets.
- `diseno/` — documentos de diseño (planes, no se usan en runtime).
- `build/` — el script de build y el icono temporal.

## Icono

El icono en `build/icon.png` es temporal (1 KB, una bandera militar
dibujada a mano). Cuando tengas uno mejor en PNG, reemplazalo y
reconstruí el AppImage.
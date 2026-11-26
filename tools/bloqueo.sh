#!/usr/bin/env bash
# tools/bloqueo.sh - Bloqueo de archivos entre los trabajadores del estudio
# (agentes de Claude, OpenCode/Mateo, Codex) que comparten el mismo árbol.
#
#   tools/bloqueo.sh tomar <dueño> <archivo>...   # falla si otro lo tiene
#   tools/bloqueo.sh soltar <dueño> [archivo]...  # sin archivos: suelta todos los suyos
#   tools/bloqueo.sh ver                          # lista quién tiene qué
#
# Cada bloqueo es un directorio en .bloqueos/ (mkdir es atómico), con un
# archivo `dueno` dentro. Los bloqueos de más de 6 h se consideran abandonados.

set -u
raiz="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$raiz/.bloqueos"
mkdir -p "$dir"
CADUCA=$((6 * 3600))

clave() {
    local ruta="$1"
    ruta="${ruta#"$raiz"/}"
    printf '%s' "$ruta" | sed 's|/|__|g'
}

caducado() {
    local d="$1" ahora t
    ahora=$(date +%s)
    t=$(stat -c %Y "$d" 2>/dev/null || echo 0)
    [ $((ahora - t)) -gt $CADUCA ]
}

accion="${1:-ver}"
shift || true

case "$accion" in
tomar)
    dueno="${1:?falta el dueño}"
    shift
    fallo=0
    tomados=()
    for archivo in "$@"; do
        d="$dir/$(clave "$archivo").lock"
        if mkdir "$d" 2>/dev/null; then
            printf '%s %s %s\n' "$dueno" "$(date '+%F %T')" "$archivo" >"$d/dueno"
            tomados+=("$d")
        else
            otro=$(cut -d' ' -f1 "$d/dueno" 2>/dev/null || echo '?')
            if [ "$otro" = "$dueno" ]; then
                touch "$d"
            elif caducado "$d"; then
                printf '%s %s %s\n' "$dueno" "$(date '+%F %T')" "$archivo" >"$d/dueno"
                touch "$d"
                echo "aviso: $archivo tenía un bloqueo abandonado de $otro; ahora es de $dueno"
            else
                echo "OCUPADO: $archivo lo tiene $otro ($(cut -d' ' -f2-3 "$d/dueno"))"
                fallo=1
            fi
        fi
    done
    if [ $fallo -ne 0 ]; then
        # Todo o nada: suelta lo que acaba de tomar.
        for d in "${tomados[@]}"; do rm -rf "$d"; done
        exit 1
    fi
    ;;
soltar)
    dueno="${1:?falta el dueño}"
    shift
    if [ $# -eq 0 ]; then
        for d in "$dir"/*.lock; do
            [ -e "$d" ] || continue
            [ "$(cut -d' ' -f1 "$d/dueno" 2>/dev/null)" = "$dueno" ] && rm -rf "$d"
        done
    else
        for archivo in "$@"; do
            d="$dir/$(clave "$archivo").lock"
            [ -e "$d" ] && [ "$(cut -d' ' -f1 "$d/dueno")" = "$dueno" ] && rm -rf "$d"
        done
    fi
    ;;
ver)
    for d in "$dir"/*.lock; do
        [ -e "$d" ] || continue
        cat "$d/dueno"
    done
    ;;
*)
    echo "uso: tools/bloqueo.sh tomar|soltar|ver ..." >&2
    exit 2
    ;;
esac
exit 0

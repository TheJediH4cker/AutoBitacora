#!/usr/bin/env bash
# uninstall.sh — Desinstalación completa de AutoBitácora
# Revierte exactamente lo que hace install.sh. No toca tus ficheros CSV.

set -e

INSTALL_DIR="$HOME/.config/bitacora"
LOCAL_BIN="$HOME/.local/bin"
LINK_TARGET="$LOCAL_BIN/bitacora-export"

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()   { printf "${CYAN}[info]${RESET}  %s\n" "$*"; }
ok()     { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()   { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
header() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ── Detectar RC del shell ─────────────────────────────────────────────────────
detect_rc() {
    case "$(basename "$SHELL")" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

RC_FILE="$(detect_rc)"

# ── Banner ────────────────────────────────────────────────────────────────────
header "══ AutoBitácora — Desinstalador ══"
info "RC file         : $RC_FILE"
info "Directorio inst : $INSTALL_DIR"

# ── Advertencia si hay sesión activa ─────────────────────────────────────────
if [[ -n "$BITACORA_FILE" ]]; then
    warn "Hay una sesión de bitácora activa en: $BITACORA_FILE"
    warn "Ejecuta 'bitacora stop' antes de desinstalar."
    exit 1
fi

# ── 1. Eliminar línea del RC ──────────────────────────────────────────────────
header "1. Limpiando $RC_FILE"
if grep -qF "AutoBitácora" "$RC_FILE" 2>/dev/null; then
    # Eliminar la línea del source y la línea en blanco anterior si la hay
    sed -i '/AutoBitácora/d' "$RC_FILE"
    # Limpiar líneas en blanco dobles que puedan haber quedado al final
    sed -i -e '/^$/{ N; /^\n$/d }' "$RC_FILE" 2>/dev/null || true
    ok "Línea de source eliminada de $RC_FILE"
else
    ok "No se encontró línea de AutoBitácora en $RC_FILE — nada que limpiar."
fi

# ── 2. Eliminar enlace simbólico ──────────────────────────────────────────────
header "2. Eliminando enlace en $LOCAL_BIN"
if [[ -L "$LINK_TARGET" ]]; then
    rm -f "$LINK_TARGET"
    ok "Eliminado: $LINK_TARGET"
elif [[ -f "$LINK_TARGET" ]]; then
    warn "$LINK_TARGET existe pero no es un enlace simbólico — no se toca."
else
    ok "Enlace no encontrado — nada que limpiar."
fi

# ── 3. Eliminar directorio de instalación ────────────────────────────────────
header "3. Eliminando $INSTALL_DIR"
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Eliminado: $INSTALL_DIR"
else
    ok "Directorio no encontrado — nada que limpiar."
fi

# ── Resumen ───────────────────────────────────────────────────────────────────
header "══ Desinstalación completa ══"
printf "\n${YELLOW}Nota:${RESET} tus ficheros CSV de bitácora NO han sido eliminados.\n"
printf "      Están en las rutas que indicaste al ejecutar 'bitacora <fichero>'.\n\n"
printf "Para que los cambios en el RC surtan efecto:\n"
printf "  source %s\n\n" "$RC_FILE"

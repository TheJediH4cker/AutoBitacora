#!/usr/bin/env bash
# install.sh — Instalación de AutoBitácora
# Copia los ficheros a ~/.config/bitacora/ y añade el source al rc del shell.
# Idempotente: volver a ejecutarlo no duplica entradas.

set -e

INSTALL_DIR="$HOME/.config/bitacora"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { printf "${CYAN}[info]${RESET}  %s\n" "$*"; }
ok()      { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
error()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ── Detectar shell del usuario ────────────────────────────────────────────────
detect_rc() {
    local shell_bin; shell_bin="$(basename "$SHELL")"
    case "$shell_bin" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)
            error "Shell no soportado: $shell_bin (solo zsh y bash)"
            exit 1
            ;;
    esac
}

RC_FILE="$(detect_rc)"
SHELL_NAME="$(basename "$SHELL")"
SOURCE_LINE="source \"$INSTALL_DIR/bitacora.sh\"  # AutoBitácora"
EXPORT_LINK="$INSTALL_DIR/bitacora-export.py"

# ── Banner ────────────────────────────────────────────────────────────────────
header "══ AutoBitácora — Instalador ══"
info "Shell detectado : $SHELL_NAME"
info "RC file         : $RC_FILE"
info "Directorio dest : $INSTALL_DIR"

# ── Crear directorio de instalación ──────────────────────────────────────────
header "1. Copiando ficheros"
mkdir -p "$INSTALL_DIR"

cp -f "$SRC_DIR/bitacora.sh"         "$INSTALL_DIR/bitacora.sh"
cp -f "$SRC_DIR/bitacora-export.py"  "$INSTALL_DIR/bitacora-export.py"
cp -f "$SRC_DIR/plantilla.csv"       "$INSTALL_DIR/plantilla.csv"
chmod 600 "$INSTALL_DIR/plantilla.csv"
chmod 755 "$INSTALL_DIR/bitacora-export.py"

ok "bitacora.sh        → $INSTALL_DIR/"
ok "bitacora-export.py → $INSTALL_DIR/"
ok "plantilla.csv      → $INSTALL_DIR/"

# ── Añadir source al RC (idempotente) ────────────────────────────────────────
header "2. Configurando $RC_FILE"
if grep -qF "AutoBitácora" "$RC_FILE" 2>/dev/null; then
    ok "Source ya presente en $RC_FILE — no se modifica."
else
    printf '\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"
    ok "Añadido al final de $RC_FILE"
fi

# ── Enlace simbólico para bitacora-export en PATH ────────────────────────────
header "3. Acceso a bitacora-export"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

LINK_TARGET="$LOCAL_BIN/bitacora-export"
if [[ -L "$LINK_TARGET" || -f "$LINK_TARGET" ]]; then
    ok "bitacora-export ya existe en $LOCAL_BIN — no se sobreescribe."
else
    ln -s "$EXPORT_LINK" "$LINK_TARGET"
    ok "Enlace creado: $LINK_TARGET → $EXPORT_LINK"
fi

# ── Integración con Powerlevel10k (si existe) ────────────────────────────────
header "4. Integración con Powerlevel10k"
P10K_CFG="$HOME/.p10k.zsh"
if [[ -f "$P10K_CFG" ]]; then
    if grep -q "'bitacora'" "$P10K_CFG" 2>/dev/null || grep -q '"bitacora"' "$P10K_CFG" 2>/dev/null || grep -q ' bitacora' "$P10K_CFG" 2>/dev/null; then
        ok "Segmento 'bitacora' ya presente en $P10K_CFG — no se modifica."
    else
        # Insertar 'bitacora' después de 'vcs' en POWERLEVEL9K_LEFT_PROMPT_ELEMENTS
        if grep -q 'vcs' "$P10K_CFG"; then
            sed -i '/vcs.*# git status/a\    bitacora                # grabación activa (AutoBitácora)' "$P10K_CFG"
            ok "Segmento 'bitacora' añadido a POWERLEVEL9K_LEFT_PROMPT_ELEMENTS en $P10K_CFG"
        else
            warn "No se encontró 'vcs' en $P10K_CFG — añade 'bitacora' manualmente al array POWERLEVEL9K_LEFT_PROMPT_ELEMENTS"
        fi
    fi
else
    info "No se encontró $P10K_CFG — saltando integración p10k (prompt fallback activo)."
fi

# ── Verificar Python y openpyxl ───────────────────────────────────────────────
header "5. Dependencias opcionales (exportación a Excel)"
if command -v python3 &>/dev/null; then
    ok "Python 3 encontrado: $(python3 --version)"
    if python3 -c "import openpyxl" 2>/dev/null; then
        ok "openpyxl instalado."
    else
        warn "openpyxl no encontrado. Para exportar a Excel:"
        warn "  pip install openpyxl   (o:  pip3 install openpyxl)"
        warn "  La bitácora CSV funciona igualmente sin openpyxl."
    fi
else
    warn "Python 3 no encontrado en PATH. La exportación a Excel no estará disponible."
fi

# ── Resumen y uso ─────────────────────────────────────────────────────────────
header "══ Instalación completa ══"

printf "\n${BOLD}Para activar sin reiniciar la terminal:${RESET}\n"
printf "  source %s\n\n" "$RC_FILE"
printf "${BOLD}Uso básico:${RESET}\n"
printf "  bitacora <fichero.csv>          Iniciar grabación en ese fichero\n"
printf "  bitacora stop                   Detener grabación\n"
printf "  bitacora status                 Ver estado de la sesión activa\n"
printf "  bitacora help                   Mostrar ayuda completa\n"
printf "  bita-nota \"texto\"               Insertar anotación manual\n"
printf "  bitacora-export <fichero.csv>   Exportar la bitácora a Excel (.xlsx)\n\n"

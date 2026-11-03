#!/usr/bin/env sh
# bitacora.sh — AutoBitácora: registro automático de comandos para pentest/red team
# Compatible con zsh y bash. Compatible con Powerlevel10k y cualquier otro prompt.
# Source desde ~/.zshrc o ~/.bashrc. No activa nada hasta llamar a `bitacora <fichero>`.

# ── Variables de estado ───────────────────────────────────────────────────────
BITACORA_FILE=""
_BITACORA_CMD=""
_BITACORA_START=""
_BITACORA_IP_DEST=""
_BITACORA_IP_SRC=""
_BITACORA_USER_DEST=""
_BITACORA_ORIG_RPROMPT=""
_BITACORA_ORIG_PS1=""

# ── Extracción de IP/host objetivo ───────────────────────────────────────────
_bitacora_resolve_to_ip() {
    local host="$1"
    # Si ya es IP, devolverla tal cual
    printf '%s' "$host" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && printf '%s' "$host" && return
    # Intentar resolver vía /etc/hosts + DNS
    local ip; ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1)
    [[ -n "$ip" ]] && printf '%s' "$ip" || printf '%s' "$host"
}

_bitacora_find_raw_target() {
    local cmd="$1"
    local target=""

    # 1. Flag explícito -dc-ip / --dc-ip (impacket, GetNPUsers, etc.)
    target=$(printf '%s' "$cmd" | grep -oE -- '-dc-ip [^ ]+' | awk '{print $2}' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 2. --host o --target
    target=$(printf '%s' "$cmd" | grep -oE -- '--(host|target) [^ ]+' | awk '{print $2}' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 3. URL (curl, wget, etc.) — extraer host de http(s)://host
    target=$(printf '%s' "$cmd" | grep -oE 'https?://[^/:@ ]+' | sed 's|https\?://||' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 4. Formato impacket: domain/user[:pass]@host — extraer host
    target=$(printf '%s' "$cmd" | grep -oE '[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(:[^@ ]+)?@[a-zA-Z0-9._-]+' \
        | grep -oE '@[a-zA-Z0-9._-]+' | sed 's/@//' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 5. Rutas SMB tipo //host
    target=$(printf '%s' "$cmd" | grep -oE '//[^/@ ]+' | sed 's|//||' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 6. Herramientas con estructura fija
    local tool; tool=$(printf '%s' "$cmd" | awk '{print $1}' | sed 's|.*/||')
    case "$tool" in
        nxc|crackmapexec|cme)
            target=$(printf '%s' "$cmd" | awk '{print $3}')
            [[ -n "$target" && "$target" != -* ]] && printf '%s' "$target" && return
            ;;
        ssh|scp|sftp)
            target=$(printf '%s' "$cmd" | grep -oE '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' | cut -d@ -f2 | head -1)
            [[ -n "$target" ]] && printf '%s' "$target" && return
            target=$(printf '%s' "$cmd" | awk '{print $NF}')
            [[ -n "$target" && "$target" != -* ]] && printf '%s' "$target" && return
            ;;
    esac

    # 7. Cualquier IP en el comando (excluir loopback y broadcast)
    target=$(printf '%s' "$cmd" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
        | grep -Ev '^(127\.|0\.|255\.)' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    # 8. Hostnames de laboratorio (.htb, .thm, .local, .internal, .corp, .lan)
    target=$(printf '%s' "$cmd" | grep -oE '\b[a-zA-Z0-9-]+\.(htb|thm|local|internal|corp|lan)\b' | head -1)
    [[ -n "$target" ]] && printf '%s' "$target" && return

    printf ''
}

_bitacora_extract_target() {
    local raw; raw="$(_bitacora_find_raw_target "$1")"
    [[ -z "$raw" ]] && return
    # Preferir IP sobre hostname: intentar resolver
    _bitacora_resolve_to_ip "$raw"
}

# ── IP del operador para llegar al objetivo ───────────────────────────────────
_bitacora_get_src_ip() {
    local dest="$1"
    local ip="" src=""

    if [[ -n "$dest" ]]; then
        # Asegurar que tenemos una IP (ip route get falla con hostnames no resueltos)
        if printf '%s' "$dest" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            ip="$dest"
        else
            ip=$(getent hosts "$dest" 2>/dev/null | awk '{print $1}' | head -1)
        fi
        [[ -n "$ip" ]] && src=$(ip route get "$ip" 2>/dev/null | grep -oE 'src [^ ]+' | awk '{print $2}' | head -1)
    fi

    [[ -n "$src" ]] && printf '%s' "$src" && return
    hostname -I 2>/dev/null | awk '{print $1}'
}

# ── Extracción de usuario objetivo ───────────────────────────────────────────
_bitacora_extract_usuario_objetivo() {
    local cmd="$1"
    local user=""

    # -u USER o -U USER
    user=$(printf '%s' "$cmd" | grep -oE ' -[uU] [^ ]+' | awk '{print $2}' | head -1)
    [[ -n "$user" ]] && printf '%s' "$(_bitacora_strip_quotes "$user")" && return

    # --username USER o --user USER
    user=$(printf '%s' "$cmd" | grep -oE -- '--username [^ ]+' | awk '{print $2}' | head -1)
    [[ -z "$user" ]] && user=$(printf '%s' "$cmd" | grep -oE -- '--user [^ ]+' | awk '{print $2}' | head -1)
    [[ -n "$user" ]] && printf '%s' "$(_bitacora_strip_quotes "$user")" && return

    # -l USER (ldap, ssh)
    user=$(printf '%s' "$cmd" | grep -oE ' -l [^ ]+' | awk '{print $2}' | head -1)
    [[ -n "$user" ]] && printf '%s' "$(_bitacora_strip_quotes "$user")" && return

    # Formato impacket: domain/user[:pass]@host — extraer solo el user
    # Ejemplo: overwatch.htb/sqlsvc:PASSWORD@host → sqlsvc
    user=$(printf '%s' "$cmd" | grep -oE '[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+' \
        | grep -v '^[0-9]' | cut -d/ -f2 | head -1)
    [[ -n "$user" ]] && user="${user//\'/}" && user="${user//\"/}" \
        && [[ -n "$user" ]] && printf '%s' "$user" && return

    printf ''
}

# Limpiar comillas de un valor extraído
_bitacora_strip_quotes() {
    local v="$1"
    v="${v//\'/}"
    v="${v//\"/}"
    printf '%s' "$v"
}

# ── Redacción de secretos ─────────────────────────────────────────────────────
_bitacora_redact() {
    printf '%s' "$1" | sed -E \
        -e 's/(--password[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/(--passwd[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/(--secret[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/(--token[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/(--api-key[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/(--key[= ])([^ ]+)/\1[REDACTED]/g' \
        -e 's/( -p )([^0-9][^ ]*)/\1[REDACTED]/g' \
        -e 's/( -P )([^ ]+)/\1[REDACTED]/g' \
        -e 's/(AKIA[A-Z0-9]{16})/[REDACTED_AWS_KEY]/g' \
        -e 's|(https?://)([^:@/]+):([^@/]+)@|\1\2:[REDACTED]@|g' \
        -e 's|([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+:)([^@ ]+)(@)|\1[REDACTED]\3|g' \
        -e 's/(export [A-Za-z_]*(PASS|KEY|TOKEN|SECRET|PWD|CRED)[A-Za-z_]*=)([^ ]+)/\1[REDACTED]/g'
}

# ── Helpers CSV ───────────────────────────────────────────────────────────────
_bitacora_csv_field() {
    local f="${1//\"/\"\"}"
    printf '"%s"' "$f"
}

_bitacora_next_id() {
    local count=0
    [[ -f "$BITACORA_FILE" ]] && count=$(( $(wc -l < "$BITACORA_FILE") - 1 ))
    [[ $count -lt 0 ]] && count=0
    printf 'UT-%03d' $(( count + 1 ))
}

_bitacora_get_tool() {
    local token
    token=$(printf '%s' "$1" | awk '{print $1}')
    [[ "$token" == "viacliente" || "$token" == "sudo" ]] && \
        token=$(printf '%s' "$1" | awk '{print $2}')
    printf '%s' "${token##*/}"
}

_bitacora_is_vpn() {
    local t; t=$(printf '%s' "$1" | awk '{print $1}')
    [[ "$t" == "viacliente" ]] && printf 'Sí' || printf 'No'
}

# ── Filtro de comandos a ignorar ──────────────────────────────────────────────
_bitacora_should_skip() {
    local cmd="${1#"${1%%[![:space:]]*}"}"
    [[ -z "$cmd" ]] && return 0
    case "$cmd" in
        bitacora*|bita-nota*) return 0 ;;
    esac
    return 1
}

# ── Escritura al CSV ──────────────────────────────────────────────────────────
# Columnas: ID,Día,Hora Inicio,Hora Fin,Operador,Host Operador,IP Operador,
#           IP Objetivo,Herramienta,Comando,Usuario Objetivo,Exit Code,VPN,
#           Prueba,Severidad,Ejecución,Detectado,Comentarios
_bitacora_write_entry() {
    local id="$1"      dia="$2"       hora_ini="$3"   hora_fin="$4"
    local operador="$5" host="$6"     ip_src="$7"     ip_dest="$8"
    local tool="$9"    cmd="${10}"    user_dest="${11}"
    local exit_code="${12}" vpn="${13}"

    {
        printf '%s,' "$(_bitacora_csv_field "$id")"
        printf '%s,' "$(_bitacora_csv_field "$dia")"
        printf '%s,' "$(_bitacora_csv_field "$hora_ini")"
        printf '%s,' "$(_bitacora_csv_field "$hora_fin")"
        printf '%s,' "$(_bitacora_csv_field "$operador")"
        printf '%s,' "$(_bitacora_csv_field "$host")"
        printf '%s,' "$(_bitacora_csv_field "$ip_src")"
        printf '%s,' "$(_bitacora_csv_field "$ip_dest")"
        printf '%s,' "$(_bitacora_csv_field "$tool")"
        printf '%s,' "$(_bitacora_csv_field "$cmd")"
        printf '%s,' "$(_bitacora_csv_field "$user_dest")"
        printf '%s,' "$(_bitacora_csv_field "$exit_code")"
        printf '%s,' "$(_bitacora_csv_field "$vpn")"
        printf ',,,,\n'   # Prueba, Severidad, Ejecución, Detectado, Comentarios
    } >> "$BITACORA_FILE"
}

_bitacora_flush() {
    local exit_code="$1"
    [[ -z "$_BITACORA_CMD" ]] && return

    _bitacora_write_entry \
        "$(_bitacora_next_id)" \
        "$(date +%d/%m/%Y)" \
        "$_BITACORA_START" \
        "$(date +%H:%M:%S)" \
        "$USER" \
        "$(hostname -s)" \
        "$_BITACORA_IP_SRC" \
        "$_BITACORA_IP_DEST" \
        "$(_bitacora_get_tool "$_BITACORA_CMD")" \
        "$_BITACORA_CMD" \
        "$_BITACORA_USER_DEST" \
        "$exit_code" \
        "$(_bitacora_is_vpn "$_BITACORA_CMD")"

    _BITACORA_CMD=""
    _BITACORA_START=""
    _BITACORA_IP_DEST=""
    _BITACORA_IP_SRC=""
    _BITACORA_USER_DEST=""
}

# ── Init CSV ──────────────────────────────────────────────────────────────────
_bitacora_init_csv() {
    local file="$1"
    local dir; dir="$(dirname "$file")"
    [[ ! -d "$dir" ]] && mkdir -p "$dir"
    if [[ ! -f "$file" ]]; then
        printf 'ID,Día,Hora Inicio,Hora Fin,Operador,Host Operador,IP Operador,IP Objetivo,Herramienta,Comando,Usuario Objetivo,Exit Code,VPN,Prueba,Severidad,Ejecución,Detectado,Comentarios\n' > "$file"
        chmod 600 "$file"
        printf '[bitácora] Fichero creado: %s\n' "$file"
    else
        local entries=$(( $(wc -l < "$file") - 1 ))
        printf '[bitácora] Continuando en: %s (%d entradas existentes)\n' "$file" "$entries"
    fi
}

# ── Detección de entorno ──────────────────────────────────────────────────────
_bitacora_has_p10k() {
    [[ -n "$POWERLEVEL9K_VERSION" ]] || (( ${+functions[p10k]} ))
}

# =============================================================================
# BLOQUE ZSH
# =============================================================================
if [[ -n "$ZSH_VERSION" ]]; then
    autoload -Uz add-zsh-hook

    # ── Hooks de datos ────────────────────────────────────────────────────────
    _bitacora_preexec_hook() {
        [[ -z "$BITACORA_FILE" ]] && return
        local cmd="$1"
        _BITACORA_CMD=""
        _BITACORA_START=""
        _BITACORA_IP_DEST=""
        _BITACORA_IP_SRC=""
        _BITACORA_USER_DEST=""
        _bitacora_should_skip "$cmd" && return

        # Extraer ANTES de redactar para no perder los valores
        _BITACORA_USER_DEST="$(_bitacora_extract_usuario_objetivo "$cmd")"
        _BITACORA_IP_DEST="$(_bitacora_extract_target "$cmd")"
        _BITACORA_IP_SRC="$(_bitacora_get_src_ip "$_BITACORA_IP_DEST")"

        _BITACORA_CMD="$(_bitacora_redact "$cmd")"
        _BITACORA_START="$(date +%H:%M:%S)"
    }

    _bitacora_precmd_hook() {
        local exit_code=$?
        [[ -z "$BITACORA_FILE" ]] && return
        _bitacora_flush "$exit_code"
    }

    # ── Indicador visual — segmento p10k ─────────────────────────────────────
    typeset -g POWERLEVEL9K_BITACORA_BACKGROUND=4
    typeset -g POWERLEVEL9K_BITACORA_FOREGROUND=196

    function prompt_bitacora() {
        [[ -z "$BITACORA_FILE" ]] && return
        p10k segment -i '⏺' -t '%BREC%b'
    }
    function instant_prompt_bitacora() {
        prompt_bitacora
    }

    _bitacora_enable_prompt_p10k() {
        zle reset-prompt 2>/dev/null || true
    }
    _bitacora_disable_prompt_p10k() {
        zle reset-prompt 2>/dev/null || true
    }

    # ── Indicador visual — fallback RPROMPT ───────────────────────────────────
    _bitacora_enable_prompt_fallback() {
        _BITACORA_ORIG_RPROMPT="$RPROMPT"
        RPROMPT='%K{red}%F{white}%B ⏺ REC %b%f%k'"${RPROMPT:+ $RPROMPT}"
    }
    _bitacora_disable_prompt_fallback() {
        RPROMPT="$_BITACORA_ORIG_RPROMPT"
        _BITACORA_ORIG_RPROMPT=""
    }

    # ── Enable / disable unificados ───────────────────────────────────────────
    _bitacora_enable_hooks() {
        add-zsh-hook preexec _bitacora_preexec_hook
        add-zsh-hook precmd  _bitacora_precmd_hook
        if _bitacora_has_p10k; then
            _bitacora_enable_prompt_p10k
        else
            _bitacora_enable_prompt_fallback
        fi
    }

    _bitacora_disable_hooks() {
        add-zsh-hook -d preexec _bitacora_preexec_hook
        add-zsh-hook -d precmd  _bitacora_precmd_hook
        if _bitacora_has_p10k; then
            _bitacora_disable_prompt_p10k
        else
            _bitacora_disable_prompt_fallback
        fi
    }
fi

# =============================================================================
# BLOQUE BASH
# =============================================================================
if [[ -n "$BASH_VERSION" ]]; then

    _bitacora_debug_hook() {
        [[ -z "$BITACORA_FILE" ]] && return
        [[ "$BASH_COMMAND" == _bitacora_* ]] && return
        [[ "$BASH_COMMAND" == bitacora*   ]] && return
        [[ "$BASH_COMMAND" == bita-nota*  ]] && return
        [[ "${#FUNCNAME[@]}" -gt 1 ]] && return

        _BITACORA_CMD=""
        _BITACORA_START=""
        _BITACORA_IP_DEST=""
        _BITACORA_IP_SRC=""
        _BITACORA_USER_DEST=""
        _bitacora_should_skip "$BASH_COMMAND" && return

        _BITACORA_USER_DEST="$(_bitacora_extract_usuario_objetivo "$BASH_COMMAND")"
        _BITACORA_IP_DEST="$(_bitacora_extract_target "$BASH_COMMAND")"
        _BITACORA_IP_SRC="$(_bitacora_get_src_ip "$_BITACORA_IP_DEST")"

        _BITACORA_CMD="$(_bitacora_redact "$BASH_COMMAND")"
        _BITACORA_START="$(date +%H:%M:%S)"
    }

    _bitacora_prompt_hook() {
        local exit_code=$?
        [[ -z "$BITACORA_FILE" ]] && return
        _bitacora_flush "$exit_code"
    }

    _bitacora_enable_prompt_bash() {
        _BITACORA_ORIG_PS1="$PS1"
        PS1="\[\e[41;97m\] ⏺ REC \[\e[0m\] $PS1"
    }
    _bitacora_disable_prompt_bash() {
        PS1="$_BITACORA_ORIG_PS1"
        _BITACORA_ORIG_PS1=""
    }

    _bitacora_enable_hooks() {
        trap '_bitacora_debug_hook' DEBUG
        if [[ -z "$PROMPT_COMMAND" ]]; then
            PROMPT_COMMAND="_bitacora_prompt_hook"
        else
            PROMPT_COMMAND="_bitacora_prompt_hook; $PROMPT_COMMAND"
        fi
        _bitacora_enable_prompt_bash
    }

    _bitacora_disable_hooks() {
        trap - DEBUG
        PROMPT_COMMAND="${PROMPT_COMMAND/_bitacora_prompt_hook; /}"
        PROMPT_COMMAND="${PROMPT_COMMAND/_bitacora_prompt_hook/}"
        _bitacora_disable_prompt_bash
    }
fi

# =============================================================================
# COMANDO PRINCIPAL
# =============================================================================
bitacora() {
    local subcmd="$1"
    case "$subcmd" in

        stop)
            if [[ -z "$BITACORA_FILE" ]]; then
                printf '[bitácora] No hay ninguna sesión activa.\n'
                return 1
            fi
            _bitacora_disable_hooks
            printf '[bitácora] Grabación detenida. Fichero: %s\n' "$BITACORA_FILE"
            BITACORA_FILE=""
            _BITACORA_CMD=""
            _BITACORA_START=""
            _BITACORA_IP_DEST=""
            _BITACORA_IP_SRC=""
            _BITACORA_USER_DEST=""
            ;;

        status)
            if [[ -n "$BITACORA_FILE" ]]; then
                local entries=$(( $(wc -l < "$BITACORA_FILE") - 1 ))
                printf '[bitácora] ⏺  ACTIVA → %s (%d entradas)\n' "$BITACORA_FILE" "$entries"
            else
                printf '[bitácora] Inactiva.\n'
            fi
            ;;

        ""|--help|-h|help)
            printf '\nAutobitácora — Registro automático de comandos para pentest/red team\n\n'
            printf 'Uso:\n'
            printf '  bitacora <fichero.csv>          Iniciar grabación en ese fichero\n'
            printf '  bitacora stop                   Detener grabación\n'
            printf '  bitacora status                 Ver estado de la sesión activa\n'
            printf '  bitacora plantilla              Crear bitacora.csv vacío en el directorio actual\n'
            printf '  bitacora help                   Mostrar esta ayuda\n'
            printf '\nComandos relacionados:\n'
            printf '  bita-nota "texto"               Insertar anotación manual en la bitácora\n'
            printf '  bitacora-export <fichero.csv>   Exportar la bitácora a Excel (.xlsx)\n'
            printf '\nEjemplo de sesión:\n'
            printf '  bitacora ~/proyectos/lab/bitacora.csv\n'
            printf '  nmap -sV 10.10.10.5\n'
            printf '  bita-nota "puerto 8080 expone panel de administración"\n'
            printf '  bitacora stop\n'
            printf '  bitacora-export ~/proyectos/lab/bitacora.csv\n\n'
            ;;

        plantilla)
            local dest="$PWD/bitacora.csv"
            if [[ -f "$dest" ]]; then
                printf '[bitácora] Ya existe un fichero en: %s\n' "$dest"
                printf '           Usa un nombre distinto o bórralo primero.\n'
                return 1
            fi
            printf 'ID,Día,Hora Inicio,Hora Fin,Operador,Host Operador,IP Operador,IP Objetivo,Herramienta,Comando,Usuario Objetivo,Exit Code,VPN,Prueba,Severidad,Ejecución,Detectado,Comentarios\n' > "$dest"
            chmod 600 "$dest"
            printf '[bitácora] Plantilla creada: %s\n' "$dest"
            ;;

        *)
            local filepath="$1"
            if [[ -n "$BITACORA_FILE" ]]; then
                printf '[bitácora] Ya hay una sesión activa en: %s\n' "$BITACORA_FILE"
                printf '           Usa "bitacora stop" primero.\n'
                return 1
            fi
            _bitacora_init_csv "$filepath"
            BITACORA_FILE="$filepath"
            _bitacora_enable_hooks
            printf '[bitácora] ⏺  Grabando → %s\n' "$BITACORA_FILE"
            ;;
    esac
}

# =============================================================================
# BITA-NOTA
# =============================================================================
bita-nota() {
    if [[ -z "$BITACORA_FILE" ]]; then
        printf '[bitácora] No hay sesión activa. Inicia con: bitacora <fichero.csv>\n'
        return 1
    fi
    local nota="$*"
    if [[ -z "$nota" ]]; then
        printf 'Uso: bita-nota "texto de la anotación"\n'
        return 1
    fi
    local ahora; ahora="$(date +%H:%M:%S)"
    local ip_src; ip_src="$(hostname -I 2>/dev/null | awk '{print $1}')"
    {
        printf '%s,' "$(_bitacora_csv_field "$(_bitacora_next_id)")"
        printf '%s,' "$(_bitacora_csv_field "$(date +%d/%m/%Y)")"
        printf '%s,' "$(_bitacora_csv_field "$ahora")"
        printf '%s,' "$(_bitacora_csv_field "$ahora")"
        printf '%s,' "$(_bitacora_csv_field "$USER")"
        printf '%s,' "$(_bitacora_csv_field "$(hostname -s)")"
        printf '%s,' "$(_bitacora_csv_field "$ip_src")"
        printf ',' # IP Objetivo vacía
        printf '%s,' "$(_bitacora_csv_field "[NOTA]")"
        printf '%s,' "$(_bitacora_csv_field "$nota")"
        printf ',' # Usuario Objetivo vacío
        printf ',' # Exit Code vacío
        printf ',' # VPN vacío
        printf ',,,,\n'  # manuales vacíos
    } >> "$BITACORA_FILE"
    printf '[bitácora] Nota registrada.\n'
}

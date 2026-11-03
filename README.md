# AutoBitacora

Utilidad de shell que registra automáticamente todos los comandos lanzados durante una sesión de pentest o red team en un fichero CSV, sin interrumpir el flujo de trabajo.

El operador activa el registro con un único comando al inicio de la sesión y trabaja con normalidad. Los datos técnicos (timestamp, comando, herramienta, IP, exit code...) se capturan solos. Los campos semánticos (descripción, severidad, si fue detectado...) se rellenan a posteriori sobre el CSV o sobre el Excel exportado.

## Qué captura

| Campo | Tipo | Descripción |
|-------|------|-------------|
| ID | auto | Identificador incremental (UT-001, UT-002...) |
| Día / Hora inicio / Hora fin | auto | Timestamps del comando |
| Operador / Host / IP Operador | auto | Quién ejecutó y desde dónde |
| IP Objetivo | best-effort | Extraída del comando (~80% precisión) |
| Herramienta | auto | Primer token del comando |
| Comando | auto | Comando completo con secretos redactados |
| Usuario Objetivo | best-effort | Extraído de flags -u, --user, etc. |
| Exit Code | auto | Código de salida del proceso |
| VPN | auto | Detecta uso de wrapper VPN |
| Prueba / Severidad / Ejecución / Detectado | manual | Se rellena a posteriori |

## Instalación

```bash
bash install.sh
source ~/.zshrc  # o source ~/.bashrc
```

Dependencia opcional para exportar a Excel:

```bash
pip install openpyxl
```

## Uso

```bash
# Iniciar grabación
bitacora /ruta/proyecto/bitacora.csv

# Trabajar con normalidad
nmap -sV 10.10.10.5
crackmapexec smb 192.168.1.0/24

# Insertar nota manual
bita-nota "Puerto 8080 expone panel de administración"

# Detener grabación
bitacora stop

# Exportar a Excel
bitacora-export /ruta/proyecto/bitacora.csv
```

## Indicador visual

El script detecta el prompt del operador y muestra un indicador `⏺ REC` mientras graba:

- **Powerlevel10k**: segmento rojo nativo en el prompt
- **Otros prompts**: indicador en RPROMPT (zsh) o PS1 (bash)

Si el indicador no está visible, no se está grabando.

## Redacción automática de secretos

Antes de escribir cada comando al CSV, se redactan automáticamente:

- `--password`, `--passwd`, `--secret`, `--token`, `--api-key`, `--key`
- Tokens AWS (`AKIA...`)
- Credenciales en URLs (`http://user:PASS@host`)
- Variables de entorno sensibles (`export VAR_SECRET=...`)

El comando original se ejecuta con normalidad — la redacción es solo sobre lo que se escribe al fichero.

## Excel exportado

El exportador genera un `.xlsx` con:

- Columnas coloreadas por tipo (auto / best-effort / manual)
- Filas de notas con fondo amarillo
- Dropdowns en Severidad, Ejecución y Detectado
- Autofilter en cabecera
- Leyenda de colores

## Compatibilidad

- **Shells**: zsh, bash
- **Prompts**: Powerlevel10k (segmento nativo), cualquier otro
- **Python**: 3.x (solo para el exportador)
- **OS**: Linux, macOS

## Desinstalación

```bash
bash uninstall.sh
```

Los ficheros CSV de bitácora no se tocan.

## Licencia

MIT

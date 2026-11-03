================================================================================
  AUTOBITÁCORA — Registro automático de comandos para pentest / red team
================================================================================
  Versión: 1.0
  Autor:   TheJediH4cker
  Repo:    https://github.com/TheJediH4cker/AutoBitacora
================================================================================


── QUÉ ES ──────────────────────────────────────────────────────────────────────

AutoBitácora es una utilidad de shell que registra automáticamente todos los
comandos lanzados durante una sesión de pentest o red team en un fichero CSV,
sin interrumpir el flujo de trabajo.

El operador activa el registro con un único comando al inicio de la sesión y
trabaja con normalidad. Los datos técnicos (timestamp, comando, herramienta,
exit code...) se capturan solos. Los campos semánticos (descripción, severidad,
si fue detectado...) se rellenan a posteriori sobre el CSV o sobre el Excel.

Compatible con zsh y bash. Compatible con Powerlevel10k y cualquier otro prompt.
Sin dependencias externas obligatorias.


── FICHEROS DEL PROYECTO ────────────────────────────────────────────────────────

  instrucciones.txt      Este fichero
  bitacora.sh            Núcleo: funciones + hooks de shell + indicador visual
  bitacora-export.py     Exportador CSV → Excel formateado (requiere openpyxl)
  plantilla.csv          Cabeceras del CSV para copiar en nuevos proyectos
  install.sh             Instalador automático
  uninstall.sh           Desinstalador — revierte todos los cambios


── INSTALACIÓN ──────────────────────────────────────────────────────────────────

  $ bash install.sh

  Qué hace:
    1. Copia bitacora.sh, bitacora-export.py y plantilla.csv a ~/.config/bitacora/
    2. Añade una línea de source al final de ~/.zshrc (o ~/.bashrc en bash)
    3. Crea un enlace simbólico ~/.local/bin/bitacora-export para el exportador
    4. Verifica que Python 3 y openpyxl estén disponibles (avisa si no)

  Es idempotente: volver a ejecutarlo no duplica entradas.

  Para que surta efecto sin reiniciar la terminal:
    $ source ~/.zshrc    (o source ~/.bashrc)

  Dependencia opcional para exportar a Excel:
    $ pip install openpyxl


── DESINSTALACIÓN ───────────────────────────────────────────────────────────────

  $ bash uninstall.sh

  Qué revierte:
    1. Elimina la línea de source del RC del shell
    2. Elimina el enlace simbólico ~/.local/bin/bitacora-export
    3. Elimina el directorio ~/.config/bitacora/ completo

  Tus ficheros CSV de bitácora NO se tocan. Están donde tú los pusiste.
  Si hay una sesión activa, el script avisa y aborta hasta que hagas
  `bitacora stop`.


── USO ─────────────────────────────────────────────────────────────────────────

  Al inicio de la sesión de trabajo:
    $ bitacora /ruta/proyecto/bitacora.csv

  Si el fichero no existe, lo crea con las cabeceras y permisos 600.
  Si ya existe, continúa añadiendo entradas a partir de las que haya.
  El prompt cambia visualmente para indicar que está grabando (ver más abajo).

  Durante la sesión — trabajas con normalidad:
    $ nmap -sV 10.10.10.5
    $ aws iam list-roles --profile lab
    $ curl -s http://target/api/v1/users
    $ crackmapexec smb 192.168.1.0/24

  Para añadir una anotación manual en la línea de tiempo:
    $ bita-nota "Inicio de escalada — usuario svc_backup comprometido"

  Para ver qué fichero se está grabando:
    $ bitacora status

  Para detener la grabación:
    $ bitacora stop

  Para ver la ayuda completa:
    $ bitacora help

  Para crear una plantilla CSV vacía en el directorio actual:
    $ bitacora plantilla
    Crea bitacora.csv con las cabeceras correctas y permisos 600.
    Útil para preparar el fichero antes de la sesión o para inicializar
    una ruta de proyecto sin empezar todavía la grabación.

  Para exportar el CSV a Excel (.xlsx):
    $ bitacora-export /ruta/proyecto/bitacora.csv
    $ bitacora-export /ruta/proyecto/bitacora.csv --open   # abre el .xlsx al generar


── INDICADOR VISUAL EN EL PROMPT ───────────────────────────────────────────────

  El script detecta automáticamente qué prompt usa el operador:

  Con Powerlevel10k:
    Aparece un segmento rojo con icono ⏺ y texto REC en el prompt izquierdo.
    Cuando se detiene la grabación, el segmento desaparece completamente.
    El prompt queda exactamente igual que antes, sin rastro.

      [ os ][ ~/proyecto ][ git:main ][ ⏺ REC ] $

  Con cualquier otro prompt (zsh sin p10k, bash):
    Se añade un indicador rojo al lado derecho del prompt (zsh) o al inicio
    de PS1 (bash). Al detener, el prompt vuelve a su estado original.

  En todos los casos: si el indicador no está visible, no se está grabando.


── COLUMNAS DEL CSV ─────────────────────────────────────────────────────────────

  [auto]   = capturado automáticamente y de forma fiable
  [best]   = capturado automáticamente, best-effort (puede quedar vacío)
  [manual] = el operador lo rellena a posteriori

  En el Excel exportado, cada tipo tiene un color de fondo diferente (ver leyenda).

  Columna           Tipo    Descripción
  ────────────────  ──────  ────────────────────────────────────────────────────
  ID                auto    Identificador incremental: UT-001, UT-002...
                            Se calcula sobre las líneas existentes, funciona
                            correctamente entre sesiones distintas.
  Día               auto    Fecha. Formato: DD/MM/YYYY
  Hora Inicio       auto    Timestamp de inicio del comando. HH:MM:SS
  Hora Fin          auto    Timestamp de fin del comando. HH:MM:SS
  Operador          auto    Usuario de shell que ejecuta ($USER) — nombre del
                            pentester que está registrando la actividad.
  Host Operador     auto    Hostname de la máquina del operador — útil en
                            pivoting y jump boxes.
  IP Operador       auto    IP de origen usada para llegar al objetivo.
                            Se obtiene con `ip route get <IP objetivo>`, por lo
                            que refleja la interfaz real usada (VPN, tun0, etc.)
                            Si no hay IP objetivo detectada, se usa la IP
                            primaria del sistema.
  IP Objetivo       best    IP o hostname del objetivo extraído del comando.
                            Prioridad: flags explícitos (-dc-ip, --host) >
                            URLs > rutas SMB > patrones por herramienta >
                            cualquier IP en el comando > hostnames .htb/.thm
                            Precisión estimada: ~80% en comandos típicos de
                            pentest. Los casos no detectados quedan vacíos.
  Herramienta       auto    Primer token del comando (nmap, nxc, curl...).
                            Si empieza por `viacliente` o `sudo`, se toma
                            el siguiente token.
  Comando           auto    Comando exacto tal como fue escrito, sin truncar.
                            Se aplica redacción automática de secretos.
  Usuario Objetivo  best    Usuario objetivo extraído del comando.
                            Detecta: -u, -U, --user, --username, -l, user@host
                            Precisión estimada: ~85% en herramientas estándar.
  Exit Code         auto    Código de salida numérico del proceso.
  VPN               auto    Sí/No — detectado si el comando empieza por
                            `viacliente`.
  Prueba            manual  Descripción semántica de la prueba realizada.
  Severidad         manual  Baja / Media / Alta / Crítica
  Ejecución         manual  Satisfactoria / Fallida / Parcialmente satisfactoria
  Detectado         manual  Sí / No (rellenar tras revisar SIEM/EDR)
  Comentarios       manual  Observaciones, hallazgos, referencias cruzadas

  Las filas de bita-nota aparecen con Herramienta = [NOTA] y fondo amarillo.


── PLANTILLA CSV ────────────────────────────────────────────────────────────────

  Cabeceras (contenido de plantilla.csv):

  ID,Día,Hora Inicio,Hora Fin,Operador,Host Operador,IP Operador,IP Objetivo,
  Herramienta,Comando,Usuario Objetivo,Exit Code,VPN,Prueba,Severidad,
  Ejecución,Detectado,Comentarios

  Ejemplo de filas:

  "UT-001","17/09/2026","09:15:00","09:15:04","operator","kali","10.10.14.23",
  "10.10.10.5","nmap","nmap -sV -p 80,443 10.10.10.5","","0","No","","","","",""

  "UT-002","17/09/2026","09:18:00","09:18:01","operator","kali","10.10.14.23",
  "10.10.10.5","nxc","nxc smb 10.10.10.5 -u 'admin' -p [REDACTED]",
  "admin","0","No","Autenticación SMB","Alta","Satisfactoria","No",""

  "UT-003","17/09/2026","09:20:00","09:20:00","operator","kali","10.10.14.23",
  "","[NOTA]","Inicio de escalada de privilegios","","","","","","","",""


── REDACCIÓN AUTOMÁTICA DE SECRETOS ─────────────────────────────────────────────

  Antes de escribir cada comando al CSV, el hook aplica sustitución de patrones.
  Los siguientes valores se reemplazan por [REDACTED]:

    --password <valor>       --passwd <valor>
    --secret <valor>         --token <valor>
    --api-key <valor>        --key <valor>
    -p <valor>               (cuidado: afecta también a puertos tipo -p 443)
    AKIA[A-Z0-9]{16}         tokens de acceso AWS
    http://user:PASS@host    credenciales en URLs
    export VAR_KEY=valor     variables de entorno con KEY/PASS/TOKEN/SECRET/PWD

  El comando redactado es el que queda en el CSV. El comando original se ejecuta
  con normalidad — la redacción es solo sobre lo que se escribe al fichero.


── EXCEL EXPORTADO ──────────────────────────────────────────────────────────────

  El fichero .xlsx generado por bitacora-export incluye:

    - Cabecera con fondo oscuro y texto blanco en negrita
    - Columnas [auto] con fondo azul claro
    - Columnas [best-effort] con fondo naranja claro (IP obj., usuario obj.)
    - Columnas [manual] con fondo blanco (editables)
    - Filas de [NOTA] con fondo amarillo y texto en cursiva
    - Autofilter en la cabecera
    - Dropdowns en Severidad, Ejecución y Detectado
    - Leyenda de colores al pie del documento

  Se genera en la misma ruta que el CSV, con extensión .xlsx.


── SEGURIDAD ─────────────────────────────────────────────────────────────────────

  1. El CSV se crea con permisos 600 (solo lectura/escritura del propietario).

  2. Los hooks solo están activos en el proceso de shell donde se ejecutó
     `bitacora <fichero>`. Abrir una terminal nueva NO activa el hook.
     El indicador visual en el prompt hace imposible confundir sesiones.

  3. El CSV es material operacional sensible: contiene el playbook completo
     del ejercicio. Tratarlo como material sensible.
     No almacenar en rutas compartidas ni repos sin cifrado.

  4. Los comandos propios (bitacora, bita-nota) no se registran en el CSV.

  5. Si en algún momento el hook está activo y cierras la terminal sin hacer
     `bitacora stop`, el fichero CSV queda íntegro — no se corrompe.


── COMPATIBILIDAD ───────────────────────────────────────────────────────────────

  Shells:   zsh, bash
  Prompts:  Powerlevel10k (segmento nativo), cualquier otro (RPROMPT / PS1)
  Python:   3.x (solo para bitacora-export)
  OS:       Linux, macOS (xdg-open / open para --open en el export)

================================================================================

#!/usr/bin/env python3
"""
bitacora-export.py — Convierte una bitácora CSV a Excel formateado.
Uso: bitacora-export <fichero.csv> [--open]
     --open  Abre el Excel generado al terminar (xdg-open / open)
"""

import csv
import sys
import os
import subprocess
from pathlib import Path

try:
    import openpyxl
    from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation
except ImportError:
    print("Error: openpyxl no está instalado.")
    print("       Instálalo con: pip install openpyxl")
    sys.exit(1)

# ── Paleta ────────────────────────────────────────────────────────────────────
C_HEADER_BG  = "1E2A3A"
C_HEADER_FG  = "FFFFFF"
C_AUTO_BG    = "EBF4FF"   # azul claro — columnas auto
C_AUTO_BEST  = "FFF3E0"   # naranja claro — auto best-effort (IP obj, usuario obj)
C_MANUAL_BG  = "FFFFFF"   # blanco — columnas manuales
C_NOTA_BG    = "FFFBEB"   # amarillo — filas de nota
C_ALT_BG     = "F8FAFC"   # gris alternado
C_BORDER     = "CBD5E0"

# ── Columnas ──────────────────────────────────────────────────────────────────
# (nombre, ancho, tipo)  tipo: "auto" | "best" | "manual"
COLUMNS = [
    ("ID",               9,   "auto"),
    ("Día",              12,  "auto"),
    ("Hora Inicio",      12,  "auto"),
    ("Hora Fin",         12,  "auto"),
    ("Operador",         12,  "auto"),
    ("Host Operador",    15,  "auto"),
    ("IP Operador",      14,  "auto"),
    ("IP Objetivo",      16,  "best"),   # best-effort
    ("Herramienta",      14,  "auto"),
    ("Comando",          54,  "auto"),
    ("Usuario Objetivo", 16,  "best"),   # best-effort
    ("Exit Code",        10,  "auto"),
    ("VPN",               6,  "auto"),
    ("Prueba",           30,  "manual"),
    ("Severidad",        12,  "manual"),
    ("Ejecución",        22,  "manual"),
    ("Detectado",        11,  "manual"),
    ("Comentarios",      42,  "manual"),
]

VALIDATIONS = {
    "Severidad":  '"Baja,Media,Alta,Crítica"',
    "Ejecución":  '"Satisfactoria,Fallida,Parcialmente satisfactoria"',
    "Detectado":  '"Sí,No"',
}

def make_fill(hex_color):
    return PatternFill("solid", fgColor=hex_color)

def make_border():
    side = Side(style="thin", color=C_BORDER)
    return Border(left=side, right=side, top=side, bottom=side)

def col_letter(idx):
    return get_column_letter(idx + 1)

def export(csv_path: Path, open_after: bool):
    if not csv_path.exists():
        print(f"Error: no se encuentra el fichero: {csv_path}")
        sys.exit(1)

    xlsx_path = csv_path.with_suffix(".xlsx")

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if not rows:
        print("El fichero CSV está vacío.")
        sys.exit(1)

    data_rows = rows[1:]

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Bitácora"
    ws.freeze_panes = "A2"

    # ── Fills ─────────────────────────────────────────────────────────────────
    fills = {
        "header": make_fill(C_HEADER_BG),
        "auto":   make_fill(C_AUTO_BG),
        "best":   make_fill(C_AUTO_BEST),
        "manual": make_fill(C_MANUAL_BG),
        "alt":    make_fill(C_ALT_BG),
        "nota":   make_fill(C_NOTA_BG),
    }
    border = make_border()

    # ── Cabecera ──────────────────────────────────────────────────────────────
    header_font  = Font(bold=True, color=C_HEADER_FG, size=10)
    header_align = Alignment(horizontal="center", vertical="center")

    for col_idx, (col_name, col_width, _) in enumerate(COLUMNS):
        cell = ws.cell(row=1, column=col_idx + 1, value=col_name)
        cell.fill      = fills["header"]
        cell.font      = header_font
        cell.alignment = header_align
        cell.border    = border
        ws.column_dimensions[col_letter(col_idx)].width = col_width

    ws.row_dimensions[1].height = 22
    ws.auto_filter.ref = f"A1:{col_letter(len(COLUMNS)-1)}1"

    # ── Validaciones ──────────────────────────────────────────────────────────
    col_idx_map = {name: idx for idx, (name, _, _) in enumerate(COLUMNS)}
    dv_objects = {}
    for col_name, formula in VALIDATIONS.items():
        idx = col_idx_map.get(col_name)
        if idx is None:
            continue
        dv = DataValidation(type="list", formula1=formula, allow_blank=True,
                            showDropDown=False, showErrorMessage=False)
        ws.add_data_validation(dv)
        dv_objects[col_name] = (idx, dv)

    # ── Filas de datos ────────────────────────────────────────────────────────
    cell_font    = Font(size=10)
    nota_font    = Font(italic=True, color="92400E", size=10)
    cell_align   = Alignment(vertical="top", wrap_text=False)

    for row_idx, row_data in enumerate(data_rows, start=2):
        is_nota = len(row_data) > 8 and row_data[8] == "[NOTA]"
        is_alt  = (row_idx % 2 == 0) and not is_nota

        while len(row_data) < len(COLUMNS):
            row_data.append("")

        for col_idx, (col_name, _, col_type) in enumerate(COLUMNS):
            value = row_data[col_idx] if col_idx < len(row_data) else ""
            cell  = ws.cell(row=row_idx, column=col_idx + 1, value=value)
            cell.border    = border
            cell.alignment = cell_align

            if is_nota:
                cell.fill = fills["nota"]
                cell.font = nota_font
            elif col_type == "auto":
                cell.fill = fills["auto"]
                cell.font = cell_font
            elif col_type == "best":
                cell.fill = fills["best"]
                cell.font = cell_font
            else:
                cell.fill = fills["alt"] if is_alt else fills["manual"]
                cell.font = cell_font

        for col_name, (cidx, dv) in dv_objects.items():
            ref = f"{col_letter(cidx)}{row_idx}"
            dv.sqref = f"{dv.sqref} {ref}" if dv.sqref else ref

        ws.row_dimensions[row_idx].height = 16

    # ── Leyenda ───────────────────────────────────────────────────────────────
    leg = len(data_rows) + 3
    legend_font = Font(size=9, color="6B7280")
    ws.cell(row=leg,   column=1, value="Leyenda:").font = Font(bold=True, size=9, color="6B7280")
    ws.cell(row=leg+1, column=1).fill = fills["auto"]
    ws.cell(row=leg+1, column=2, value="Capturado automáticamente").font = legend_font
    ws.cell(row=leg+2, column=1).fill = fills["best"]
    ws.cell(row=leg+2, column=2, value="Automático best-effort (IP obj., usuario obj.)").font = legend_font
    ws.cell(row=leg+3, column=1).fill = fills["manual"]
    ws.cell(row=leg+3, column=2, value="Rellenar manualmente").font = legend_font
    ws.cell(row=leg+4, column=1).fill = fills["nota"]
    ws.cell(row=leg+4, column=2, value="Anotación manual (bita-nota)").font = legend_font

    wb.save(xlsx_path)
    print(f"[bitácora] Excel generado: {xlsx_path}")
    print(f"           {len(data_rows)} entradas exportadas.")

    if open_after:
        opener = "xdg-open" if sys.platform.startswith("linux") else "open"
        subprocess.Popen([opener, str(xlsx_path)])

# ── Entrada ───────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    args  = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]

    if not args:
        print(__doc__)
        sys.exit(0)

    export(
        csv_path   = Path(args[0]).expanduser().resolve(),
        open_after = "--open" in flags,
    )

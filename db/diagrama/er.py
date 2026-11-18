#!/usr/bin/env python3
"""Dibuja el diagrama entidad-relación de la base `cruzroja` a partir de los scripts de db/.

No se conecta a ninguna base: lee los CREATE TABLE y los ALTER TABLE ... ADD COLUMN de
01_esquema.sql, 08_pedidos.sql, 09_pedidos_admin.sql y 10_modo_personal.sql, así el
diagrama siempre corresponde a lo que está en el repositorio.

Uso (desde la carpeta db/):
    python3 diagrama/er.py            # escribe diagrama/er.png y diagrama/er.dot
Necesita Graphviz (en Mac: brew install graphviz).
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
SCRIPTS = ["01_esquema.sql", "08_pedidos.sql", "09_pedidos_admin.sql", "10_modo_personal.sql"]
NO_SON_COLUMNAS = {"PRIMARY", "UNIQUE", "KEY", "INDEX", "CONSTRAINT", "CHECK", "FOREIGN", "FULLTEXT"}
# Una línea solo es columna si después del nombre viene un tipo de dato (así no se cuela
# la segunda línea de un CHECK que ocupa dos renglones).
TIPOS = ("CHAR|VARCHAR|TEXT|TINYINT|SMALLINT|INT|BIGINT|DECIMAL|DOUBLE|FLOAT|DATETIME|DATE|TIME|"
         "TIMESTAMP|ENUM|SET|JSON|BOOLEAN|BLOB")

# Las tablas se agrupan por módulo solo para colorearlas y acomodarlas juntas.
MODULOS = {
    "Directorio y personal": ["directorio_meta", "delegacion", "personal", "intento_acceso", "bitacora"],
    "Dispositivo y consentimiento": ["dispositivo", "aviso_privacidad", "consentimiento"],
    "Llamada de emergencia": ["llamada", "ficha", "transcripcion"],
    "Citas": ["especialista", "servicio_horario", "cita", "cita_folio_seq"],
    "Capacitación y contenido": ["curso", "inscripcion_curso", "tutorial"],
    "Productos con causa": ["producto", "pedido", "pedido_folio_seq", "evento_stripe"],
}
COLORES = ["#B0241A", "#1F5F8B", "#2E7D32", "#8E5A00", "#5E35B1", "#00695C"]


def tipo_corto(resto):
    """'ENUM('a','b') NOT NULL' -> 'ENUM';  'CHAR(36) NOT NULL' -> 'CHAR(36)'."""
    m = re.match(r"([A-Za-z]+)\s*(\([^)]*\))?", resto.strip())
    if not m:
        return ""
    nombre = m.group(1).upper()
    if nombre in ("ENUM", "SET"):
        return nombre
    return nombre + (m.group(2) or "").replace(" ", "")


def leer_esquema():
    tablas = {}      # nombre -> {"columnas": [(nombre, tipo)], "pk": set(), "fk": set()}
    relaciones = []  # (tabla, columnas, tabla_referida)
    for script in SCRIPTS:
        texto = (CARPETA.parent / script).read_text(encoding="utf-8")
        texto = re.sub(r"--[^\n]*", "", texto).replace("''", "'")

        for m in re.finditer(r"CREATE TABLE (?:IF NOT EXISTS )?(\w+) \((.*?)\n\)", texto, re.S):
            nombre, cuerpo = m.group(1), m.group(2)
            tabla = tablas.setdefault(nombre, {"columnas": [], "pk": set(), "fk": set()})
            for linea in cuerpo.split("\n"):
                linea = linea.strip().rstrip(",")
                if not linea:
                    continue
                primera = linea.split()[0].upper()
                pk = re.match(r"PRIMARY KEY \(([^)]*)\)", linea, re.I)
                fk = re.search(r"FOREIGN KEY\s*\(([^)]*)\)\s+REFERENCES\s+(\w+)", linea, re.I)
                if pk:
                    tabla["pk"].update(c.strip() for c in pk.group(1).split(","))
                elif fk:
                    columnas = [c.strip() for c in fk.group(1).split(",")]
                    tabla["fk"].update(columnas)
                    relaciones.append((nombre, columnas, fk.group(2)))
                elif primera not in NO_SON_COLUMNAS and re.match(rf"\w+\s+({TIPOS})\b", linea, re.I):
                    columna, resto = linea.split(None, 1)
                    tabla["columnas"].append((columna, tipo_corto(resto)))

        for m in re.finditer(r"ALTER TABLE (\w+)(.*?);", texto, re.S):
            nombre, cuerpo = m.group(1), m.group(2)
            if nombre not in tablas:
                continue
            for c in re.finditer(r"ADD COLUMN\s+(?:IF NOT EXISTS\s+)?(\w+)\s+([^\n]*)", cuerpo):
                if c.group(1) not in [col for col, _ in tablas[nombre]["columnas"]]:
                    tablas[nombre]["columnas"].append((c.group(1), tipo_corto(c.group(2))))
    return tablas, relaciones


def a_dot(tablas, relaciones):
    lineas = [
        "digraph cruzroja {",
        '  graph [rankdir=LR, splines=true, nodesep=0.35, ranksep=1.1, fontname="Helvetica", fontsize=20,',
        '         labelloc=t, label="Base de datos cruzroja · diagrama entidad-relación", bgcolor="white", pad=0.3];',
        '  node [shape=plain, fontname="Helvetica", fontsize=11];',
        '  edge [color="#555555", arrowhead=normal, arrowtail=none, arrowsize=0.8];',
    ]
    for (modulo, nombres), color in zip(MODULOS.items(), COLORES):
        lineas.append(f'  subgraph "cluster_{modulo}" {{')
        lineas.append(f'    label="{modulo}"; fontname="Helvetica-Bold"; fontsize=14; color="{color}"; style="rounded";')
        for nombre in nombres:
            if nombre not in tablas:
                continue
            tabla = tablas[nombre]
            filas = [f'<TR><TD COLSPAN="2" BGCOLOR="{color}"><FONT COLOR="white"><B>{nombre}</B></FONT></TD></TR>']
            for columna, tipo in tabla["columnas"]:
                marcas = []
                if columna in tabla["pk"]:
                    marcas.append("PK")
                if columna in tabla["fk"]:
                    marcas.append("FK")
                etiqueta = columna + (f' <FONT COLOR="{color}"><B>{" ".join(marcas)}</B></FONT>' if marcas else "")
                filas.append(f'<TR><TD ALIGN="LEFT" PORT="{columna}">{etiqueta}</TD>'
                             f'<TD ALIGN="LEFT"><FONT COLOR="#666666">{tipo}</FONT></TD></TR>')
            lineas.append(f'    {nombre} [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="3">'
                          + "".join(filas) + "</TABLE>>];")
        lineas.append("  }")
    for tabla, columnas, referida in relaciones:
        lineas.append(f"  {tabla}:{columnas[0]} -> {referida};")
    lineas.append("}")
    return "\n".join(lineas) + "\n"


def main():
    tablas, relaciones = leer_esquema()
    sin_modulo = set(tablas) - {t for nombres in MODULOS.values() for t in nombres}
    if sin_modulo:
        sys.exit(f"Agrega estas tablas a MODULOS en er.py: {', '.join(sorted(sin_modulo))}")
    dot = CARPETA / "er.dot"
    dot.write_text(a_dot(tablas, relaciones), encoding="utf-8")
    print(f"{len(tablas)} tablas y {len(relaciones)} relaciones -> {dot.name}")
    if not shutil.which("dot"):
        sys.exit("Falta Graphviz para generar la imagen (en Mac: brew install graphviz).")
    subprocess.run(["dot", "-Tpng", "-Gdpi=130", str(dot), "-o", str(CARPETA / "er.png")], check=True)
    print("Listo: er.png")


if __name__ == "__main__":
    main()

"""Paso 3: parsea el HTML crudo (listado + fichas) y escribe las tablas en data/processed/.

Uso:  python3 -I scripts/03_parsear.py

No toca la red: trabaja sólo sobre data/raw/. Se puede correr mientras el paso 2
sigue bajando fichas (usa las que ya están).

Salida (CSV UTF-8; scripts/04_a_parquet.R los pasa a parquet tipado):
    legisladores, cargos_legislativos, actividad_politica, titulos, estudios,
    actividad_gremial, cargos_oficiales, publicaciones, premios,
    listado_cargos (los cargos tal como los muestra la tarjeta del listado, para validar),
    anomalias (todo lo que el parser no pudo interpretar o no cuadró).
"""
import csv
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from trayectorias.cliente import RAW, RAIZ  # noqa: E402
from trayectorias.parse import (  # noqa: E402
    cargo_norm, clave, en_actividad, parse_ficha, parse_listado, periodo,
)

SALIDA = RAIZ / "data" / "processed"

COLS_COMUN = ["id", "orden", "periodo_raw", "desde", "hasta", "en_actividad"]
COLS = {
    "cargos_legislativos": COLS_COMUN + ["cargo_original", "cargo", "condicion", "circunscripcion",
                                         "partido", "sublema", "lista", "lineas_raw"],
    "actividad_politica": COLS_COMUN + ["descripcion", "partido", "sector", "lineas_raw"],
}
for t in ["titulos", "estudios", "actividad_gremial", "cargos_oficiales", "publicaciones", "premios"]:
    COLS[t] = COLS_COMUN + ["destacado", "detalle", "lineas_raw"]

COLS_LEG = ["id", "nombre_listado", "nombre_ficha", "nacimiento_raw", "nacimiento_iso", "defuncion_raw",
            "defuncion_iso", "lugar_nacimiento_raw", "nac_ciudad", "nac_subdivision", "nac_pais",
            "ultima_actualizacion", "pagina_listado", "en_listado", "estado_ficha", "bytes_ficha"] + \
           [f"n_{t}" for t in COLS]


def escribir(nombre: str, cols: list[str], filas: list[dict]) -> None:
    with (SALIDA / f"{nombre}.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in filas:
            w.writerow({c: ("" if r.get(c) is None else r.get(c)) for c in cols})
    print(f"  {nombre}.csv: {len(filas)} filas", flush=True)


def tablas_del_formulario() -> tuple[list[dict], list[dict]]:
    """Legislaturas (número, años) y lemas, tal como los ofrece el formulario de búsqueda."""
    from lxml import html as lh
    doc = lh.fromstring((RAW / "listado" / "pagina_001.html").read_text(encoding="utf-8"))
    legs = []
    for o in doc.xpath('//select[@id="legislatura"]/option[@value!=""]'):
        m = re.fullmatch(r"Legislatura (\d+) \((\d{4}) - (\d{4})\)", " ".join(o.text_content().split()))
        if not m:
            raise SystemExit(f"Etiqueta de legislatura inesperada: {o.text_content()!r}")
        legs.append({"numero": int(m.group(1)), "desde": int(m.group(2)), "hasta": int(m.group(3))})
    lemas = [{"id_fuente": o.get("value"), "nombre": " ".join(o.text_content().split())}
             for o in doc.xpath('//select[@id="lema"]/option[@value!=""]')]
    return sorted(legs, key=lambda r: r["numero"]), lemas


def leer_estado() -> dict[int, dict]:
    p = RAW / "fichas_estado.csv"
    if not p.exists():
        return {}
    with p.open(encoding="utf-8", newline="") as f:
        return {int(r["id"]): r for r in csv.DictReader(f)}  # gana la última fila


def firma(desde, hasta, cargo, partido, cond) -> tuple:
    return (desde, hasta, cargo_norm(cargo), clave(partido or ""), clave(cond or ""))


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    anomalias: list[dict] = []

    def anom(id_, tabla, tipo, detalle=""):
        anomalias.append({"id": id_, "tabla": tabla, "tipo": tipo, "detalle": detalle})

    # ---- listado
    tarjetas: dict[int, dict] = {}
    paginas = sorted((RAW / "listado").glob("pagina_*.html"))
    for p in paginas:
        n_pag = int(p.stem.split("_")[1])
        for pos, reg in enumerate(parse_listado(p.read_text(encoding="utf-8")), 1):
            if reg["id"] in tarjetas:
                anom(reg["id"], "listado", "id_repetido_en_listado", f"páginas {tarjetas[reg['id']]['pagina']} y {n_pag}")
                continue
            reg["pagina"], reg["pos"] = n_pag, pos
            tarjetas[reg["id"]] = reg
    print(f"Listado: {len(paginas)} páginas, {len(tarjetas)} legisladores distintos", flush=True)

    listado_cargos = []
    for i, reg in tarjetas.items():
        for orden, c in enumerate(reg["cargos"], 1):
            d, h = periodo(c["periodo_raw"])
            listado_cargos.append({"id": i, "orden": orden, "periodo_raw": c["periodo_raw"], "desde": d,
                                   "hasta": h, "en_actividad": en_actividad(c["periodo_raw"]), "cargo": c["cargo"], "cargo_norm": cargo_norm(c["cargo"]),
                                   "partido": c["partido"], "condicion": c["condicion"]})
            if c["partido"] is None:
                anom(i, "listado_cargos", "tarjeta_sin_partido", c["detalle_raw"])

    # ---- fichas
    estado = leer_estado()
    ids_ficha = sorted(i for i, r in estado.items() if r["estado"] == "ok" and (RAW / "fichas" / f"{i}.html").exists())
    print(f"Fichas con HTML: {len(ids_ficha)} (estado conocido de {len(estado)} IDs)", flush=True)

    tablas: dict[str, list[dict]] = {t: [] for t in COLS}
    legisladores: list[dict] = []
    for i in ids_ficha:
        out = parse_ficha((RAW / "fichas" / f"{i}.html").read_text(encoding="utf-8"), i)
        for t_, tipo, det in out["anomalias"]:
            anom(i, t_, tipo, det)
        d = out["datos"]
        reg = tarjetas.get(i)
        d["nombre_listado"] = reg["nombre_listado"] if reg else None
        d["pagina_listado"] = reg["pagina"] if reg else None
        d["en_listado"] = reg is not None
        d["estado_ficha"] = "ok"
        d["bytes_ficha"] = estado[i]["bytes"]
        for t, filas in out["secciones"].items():
            d[f"n_{t}"] = len(filas)
            for f in filas:
                f["id"] = i
                tablas[t].append(f)
        legisladores.append(d)

        # validación cruzada: cargos de la tarjeta vs cargos de la ficha
        if reg:
            fich = Counter(firma(f["desde"], f["hasta"], f["cargo_original"], f["partido"], f["condicion"])
                           for f in out["secciones"]["cargos_legislativos"])
            card = Counter(firma(*periodo(c["periodo_raw"]), c["cargo"], c["partido"], c["condicion"])
                           for c in reg["cargos"])
            if fich != card:
                solo_f, solo_c = fich - card, card - fich
                anom(i, "cargos_legislativos", "listado_vs_ficha",
                     f"solo ficha: {dict(solo_f)} | solo tarjeta: {dict(solo_c)}"[:400])

    # IDs del listado cuya ficha no se pudo bajar: queda la fila con lo que dice la tarjeta
    for i, reg in tarjetas.items():
        if i in set(ids_ficha):
            continue
        st = estado.get(i, {}).get("estado", "sin_descargar")
        legisladores.append({
            "id": i, "nombre_listado": reg["nombre_listado"], "nacimiento_raw": reg["nacimiento_raw"],
            "defuncion_raw": reg["defuncion_raw"], "lugar_nacimiento_raw": reg["lugar_raw"],
            "pagina_listado": reg["pagina"], "en_listado": True, "estado_ficha": st})
        if st != "sin_descargar":
            anom(i, "legisladores", "ficha_no_disponible", st)

    legisladores.sort(key=lambda r: r["id"])
    for t in tablas:
        tablas[t].sort(key=lambda r: (r["id"], r["orden"]))

    print("Escribiendo data/processed/:", flush=True)
    escribir("legisladores", COLS_LEG, legisladores)
    for t, filas in tablas.items():
        escribir(t, COLS[t], filas)
    escribir("listado_cargos", ["id", "orden", "periodo_raw", "desde", "hasta", "en_actividad", "cargo", "cargo_norm",
                                "partido", "condicion"], listado_cargos)
    escribir("anomalias", ["id", "tabla", "tipo", "detalle"], anomalias)
    legs, lemas = tablas_del_formulario()
    escribir("legislaturas", ["numero", "desde", "hasta"], legs)
    escribir("lemas", ["id_fuente", "nombre"], lemas)
    # Estado de todos los IDs sondeados (listado + barrido): los que no están en el listado
    # y dan 500 no aparecen en ninguna otra tabla.
    escribir("ids_estado", ["id", "estado", "en_listado", "http", "bytes"],
             [{"id": i, "estado": r["estado"], "en_listado": i in tarjetas, "http": r["http"], "bytes": r["bytes"]}
              for i, r in sorted(estado.items())])

    # ---- resumen para mirar a ojo
    print("\nAnomalías por tipo:", dict(Counter((a["tabla"], a["tipo"]) for a in anomalias)), flush=True)
    cl = tablas["cargos_legislativos"]
    print("Cargos (normalizados):", Counter(f["cargo"] for f in cl).most_common(15), flush=True)
    print("Condición:", Counter(f["condicion"] for f in cl).most_common(8), flush=True)
    print("Partidos:", Counter(f["partido"] for f in cl).most_common(12), flush=True)


if __name__ == "__main__":
    main()

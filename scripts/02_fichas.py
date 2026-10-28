"""Paso 2: baja la ficha de cada legislador y guarda el HTML crudo.

Uso:
    python3 -I scripts/02_fichas.py              # los IDs que aparecen en el listado
    python3 -I scripts/02_fichas.py --barrido    # además, prueba el resto de IDs 2..2400
                                                 # para ver si el listado es todo el universo

Retomable: data/raw/fichas_estado.csv guarda el resultado de cada ID. Se salta
lo que ya está `ok`, `inexistente` o `error_500` (los tres son terminales); se
reintenta `error_red` y `otro`.
"""
import csv
import re
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from trayectorias.cliente import BASE, PAUSA, RAW, nueva_sesion, pedir, quitar_fotos  # noqa: E402

DESTINO = RAW / "fichas"
ESTADO = RAW / "fichas_estado.csv"
TERMINALES = {"ok", "inexistente", "error_500"}
ID_MAX_BARRIDO = 2400  # el techo observado fue ~2290; margen por si hay altas


def ids_del_listado() -> list[int]:
    ids: set[int] = set()
    paginas = sorted((RAW / "listado").glob("pagina_*.html"))
    if not paginas:
        raise SystemExit("No hay páginas de listado: correr primero scripts/01_listado.py")
    for p in paginas:
        ids.update(int(x) for x in re.findall(r"/biografias/legislador/(\d+)", p.read_text(encoding="utf-8")))
    return sorted(ids)


def leer_estado() -> dict[int, str]:
    if not ESTADO.exists():
        return {}
    with ESTADO.open(encoding="utf-8", newline="") as f:
        return {int(r["id"]): r["estado"] for r in csv.DictReader(f)}  # gana la última fila


def main() -> None:
    barrido = "--barrido" in sys.argv
    ids = ids_del_listado()
    print(f"IDs en el listado: {len(ids)} (min {ids[0]}, max {ids[-1]})", flush=True)
    if barrido:
        resto = [i for i in range(2, ID_MAX_BARRIDO + 1) if i not in set(ids)]
        print(f"Barrido: {len(resto)} IDs fuera del listado", flush=True)
        ids = ids + resto

    estado = leer_estado()
    pendientes = [i for i in ids if estado.get(i) not in TERMINALES]
    print(f"Pendientes: {len(pendientes)} de {len(ids)}", flush=True)

    nuevo = not ESTADO.exists()
    s = nueva_sesion()
    with ESTADO.open("a", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        if nuevo:
            w.writerow(["id", "estado", "http", "bytes", "nota", "fecha"])
        for k, i in enumerate(pendientes, 1):
            r = pedir(s, f"{BASE}/legislador/{i}")
            n_bytes = 0
            if r.estado == "ok":
                texto = quitar_fotos(r.html)
                (DESTINO / f"{i}.html").write_text(texto, encoding="utf-8")
                n_bytes = len(texto.encode("utf-8"))
            w.writerow([i, r.estado, r.http or "", n_bytes, r.nota, datetime.now().isoformat(timespec="seconds")])
            f.flush()
            if k % 50 == 0 or k == len(pendientes):
                print(f"  {k}/{len(pendientes)} (último ID {i}: {r.estado})", flush=True)
            time.sleep(PAUSA)

    final = leer_estado()
    resumen = {}
    for e in final.values():
        resumen[e] = resumen.get(e, 0) + 1
    print("Resumen por estado:", resumen, flush=True)


if __name__ == "__main__":
    main()

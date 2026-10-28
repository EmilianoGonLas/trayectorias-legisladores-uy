"""Paso 1: baja las páginas del listado (?page=N) y las guarda crudas.

Uso:  python3 -I scripts/01_listado.py

Retomable: salta las páginas que ya están en data/raw/listado/. El total de
páginas se lee del enlace «>>» de la primera, no está escrito a mano.
"""
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from trayectorias.cliente import BASE, PAUSA, RAW, nueva_sesion, pedir, quitar_fotos  # noqa: E402

DESTINO = RAW / "listado"


def ruta(n: int) -> Path:
    return DESTINO / f"pagina_{n:03d}.html"


def total_paginas(html: str) -> int:
    nums = [int(x) for x in re.findall(r"busqueda\?page=(\d+)", html)]
    if not nums:
        raise SystemExit("No encuentro la paginación en la primera página: ¿cambió el sitio?")
    return max(nums)


def main() -> None:
    s = nueva_sesion()
    if ruta(1).exists():
        total = total_paginas(ruta(1).read_text(encoding="utf-8"))
    else:
        r = pedir(s, f"{BASE}/busqueda")
        if r.estado != "ok":
            raise SystemExit(f"Primera página: {r.estado} {r.nota}")
        ruta(1).write_text(quitar_fotos(r.html), encoding="utf-8")
        total = total_paginas(r.html)
        time.sleep(PAUSA)
    print(f"Total de páginas según la fuente: {total}", flush=True)

    fallidas = []
    for n in range(1, total + 1):
        if ruta(n).exists():
            continue
        r = pedir(s, f"{BASE}/busqueda?page={n}")
        if r.estado != "ok":
            print(f"  página {n}: {r.estado} {r.nota}", flush=True)
            fallidas.append(n)
        else:
            ruta(n).write_text(quitar_fotos(r.html), encoding="utf-8")
            if n % 10 == 0 or n == total:
                print(f"  página {n}/{total}", flush=True)
        time.sleep(PAUSA)

    bajadas = len(list(DESTINO.glob("pagina_*.html")))
    print(f"Listo: {bajadas}/{total} páginas en {DESTINO}. Fallidas: {fallidas or 'ninguna'}", flush=True)


if __name__ == "__main__":
    main()

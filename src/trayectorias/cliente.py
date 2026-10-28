"""Cliente HTTP para el Sistema de Consultas de Biografías de Legisladores.

Lo que hay que saber de la fuente (verificado el 2026-10-28, ver BITACORA.md):

* El HTTP/2 del servidor está roto: devuelve 200 con cuerpo vacío. `requests`
  habla HTTP/1.1, así que no hace falta forzar nada, pero no migrar a `httpx`
  con h2 sin probar.
* Un ID inexistente responde 302 (a la búsqueda), no 404. Hay que pedir con
  `allow_redirects=False` o se descarga la página de búsqueda como si fuera una ficha.
* Algunos IDs responden 500 de forma determinista: reintentar en bucle no sirve.
* Cada página trae las fotos en base64 dentro del HTML (hasta 600 KB). Se quitan
  antes de guardar: no se usan y multiplican el disco por diez.
"""
from __future__ import annotations

import re
import time
from dataclasses import dataclass
from pathlib import Path

import requests

BASE = "https://biblioteca.parlamento.gub.uy:8008/biografias"
USER_AGENT = "trayectorias-legisladores-uy/0.1 (investigacion academica; descarga lenta y con cache)"
PAUSA = 1.0  # segundos entre pedidos: el servidor es chico y de una biblioteca
TIMEOUT = 60

RAIZ = Path(__file__).resolve().parents[2]
RAW = RAIZ / "data" / "raw"

# La fuente escribe «data:image/webp; base64,...» con un espacio después del «;».
_FOTO = re.compile(r"data:image/[A-Za-z0-9.+-]+;\s*base64,[A-Za-z0-9+/=\s]*")


def quitar_fotos(html: str) -> str:
    return _FOTO.sub("data:IMAGEN-OMITIDA", html)


def nueva_sesion() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "es"})
    return s


@dataclass
class Respuesta:
    estado: str          # ok | inexistente | error_500 | error_red | otro
    http: int | None
    html: str | None
    nota: str = ""


def pedir(sesion: requests.Session, url: str, reintentos: int = 3) -> Respuesta:
    """Pide una URL y clasifica el resultado. Nunca sigue redirects.

    - 200 con cuerpo  -> ok
    - 302             -> inexistente (la fuente redirige a la búsqueda)
    - 500             -> error_500 tras un segundo intento (es determinista)
    - red / timeout   -> se reintenta con espera creciente; si persiste, error_red
                         (estado NO terminal: la próxima corrida lo vuelve a intentar)
    """
    ultimo = ""
    for intento in range(1, reintentos + 1):
        try:
            r = sesion.get(url, timeout=TIMEOUT, allow_redirects=False)
        except requests.RequestException as e:
            ultimo = f"{type(e).__name__}: {e}"
            time.sleep(5 * intento)
            continue

        if r.status_code == 200:
            if not r.content:
                ultimo = "200 con cuerpo vacío"
                time.sleep(5 * intento)
                continue
            return Respuesta("ok", 200, r.content.decode("utf-8", errors="replace"))
        if r.status_code in (301, 302, 303):
            return Respuesta("inexistente", r.status_code, None, r.headers.get("Location", ""))
        if r.status_code == 500:
            if intento == 1:
                time.sleep(3)
                continue
            return Respuesta("error_500", 500, None, "500 repetido")
        return Respuesta("otro", r.status_code, None, f"HTTP {r.status_code}")
    return Respuesta("error_red", None, None, ultimo)

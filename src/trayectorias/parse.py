"""Parseo del HTML crudo: tarjetas del listado y fichas individuales.

Principio: cada fila conserva `lineas_raw` (el texto tal cual, separado por « ¦ »)
además de los campos interpretados. Si una regla de interpretación resulta mala,
se corrige acá y se vuelve a correr sin tocar la fuente.
"""
from __future__ import annotations

import re
import unicodedata
from datetime import date

from lxml import html as lh

SEP = " ¦ "

# Formularios de la fuente (lema= y departamento=), sirven para reconocer partidos
# y circunscripciones sin adivinar por posición.
PARTIDOS = [
    "Asamblea Popular", "Frente Amplio", "Frente Izquierda de Liberacion (FIDEL)",
    "Identidad Soberana", "Nuevo Espacio", "Partido Blanco Radical", "Partido Cabildo Abierto",
    "Partido Colorado", "Partido Colorado Radical", "Partido Comunista del Uruguay",
    "Partido Constitucional", "Partido de la Gente", "Partido Democrata Cristiano",
    "Partido Ecologista Radical Intransigente (PERI)", "Partido General Fructuoso Rivera",
    "Partido Independiente", "Partido Nacional", "Partido Nacional Independiente",
    "Partido por el Gobierno del Pueblo (PGP)", "Partido por la Tradicion Colorada",
    "Partido Socialista del Uruguay", "Union Civica del Uruguay", "Union DemóCrata Reformista",
    "Union Popular", "Union Socialista Liberal",
]
DEPARTAMENTOS = [
    "Artigas", "Canelones", "Cerro Largo", "Colonia", "Durazno", "Flores", "Florida",
    "Lavalleja", "Maldonado", "Minas", "Montevideo", "Paysandú", "Río Negro", "Rivera",
    "Rocha", "Salto", "San José", "Soriano", "Tacuarembó", "Treinta y Tres",
]


def clave(s: str) -> str:
    """Mayúsculas, sin tildes, espacios colapsados: para comparar textos."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s).strip().upper()


_PARTIDOS_K = sorted((clave(p) for p in PARTIDOS), key=len, reverse=True)
_DEPTOS_K = {clave(d) for d in DEPARTAMENTOS}

_FEMENINOS = {"DIPUTADA": "DIPUTADO", "SENADORA": "SENADOR", "PRESIDENTA": "PRESIDENTE",
              "VICEPRESIDENTA": "VICEPRESIDENTE", "REPRESENTANTE": "REPRESENTANTE"}


def txt(s: str | None) -> str:
    return re.sub(r"\s+", " ", s or "").strip()


def es_partido(linea: str) -> bool:
    k = clave(linea.split(" - ")[0])
    return k in _PARTIDOS_K


def es_depto(linea: str) -> bool:
    return clave(re.sub(r"\(.*?\)", "", linea)) in _DEPTOS_K


def cargo_norm(cargo: str | None) -> str | None:
    """Pasa el cargo a masculino genérico: la fuente lo flexiona por género (DIPUTADA)."""
    if not cargo:
        return None
    k = clave(cargo)
    for fem, masc in _FEMENINOS.items():
        k = re.sub(rf"\b{fem}\b", masc, k)
    return k


def fecha_iso(raw: str | None) -> str | None:
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", (raw or "").strip())
    if not m:
        return None
    d, mth, y = map(int, m.groups())
    try:
        return date(y, mth, d).isoformat()
    except ValueError:
        return None


def periodo(raw: str) -> tuple[int | None, int | None]:
    anios = re.findall(r"\d{4}", raw or "")
    return (int(anios[0]) if anios else None, int(anios[1]) if len(anios) > 1 else None)


_EN_ACTIVIDAD = re.compile(r"en\s+actividad", re.I)


def en_actividad(raw: str) -> bool:
    """«2025 - en actividad»: la fuente marca así al legislador que sigue en el cargo."""
    return bool(_EN_ACTIVIDAD.search(raw or ""))


def periodo_raro(raw: str) -> bool:
    """True si la celda de período trae algo más que años, guiones y espacios
    (la frase «en actividad» está permitida; cualquier otra variante se registra)."""
    return bool(re.sub(r"[\d\s\-–]", "", _EN_ACTIVIDAD.sub("", raw or "")))


def lineas_de(td) -> tuple[list[str], list[str]]:
    """(negritas, líneas) de una celda; las líneas se cortan en cada <br>.

    Las negritas se sacan del árbol antes de cortar: la fuente a veces las parte
    entre líneas («Militante» <br> </b> FEUU), así que no sirven como marcas de texto.
    """
    import copy

    td = copy.deepcopy(td)
    negritas = []
    for b in list(td.iter("b", "strong")):
        negritas.append(txt(b.text_content()))
        b.drop_tree()
    for br in td.iter("br"):
        br.tail = "\n" + (br.tail or "")
    lineas = [txt(x) for x in td.text_content().split("\n")]
    return [n for n in negritas if n], [x for x in lineas if x]


def _doc(html: str):
    return lh.fromstring(html)


# --------------------------------------------------------------------------- listado

def parse_listado(html: str) -> list[dict]:
    """Una dict por tarjeta: datos básicos y filas de cargos tal como las muestra el listado."""
    doc = _doc(html)
    out = []
    tarjetas = doc.xpath(
        '//div[contains(concat(" ", normalize-space(@class), " "), " card ")][.//h4/a[contains(@href,"/legislador/")]]'
    )
    for t in tarjetas:
        a = t.xpath('.//h4/a[contains(@href,"/legislador/")]')[0]
        m = re.search(r"/legislador/(\d+)", a.get("href"))
        reg = {"id": int(m.group(1)), "nombre_listado": txt(a.text_content()),
               "nacimiento_raw": None, "defuncion_raw": None, "lugar_raw": None, "cargos": []}
        for bloque in t.xpath('.//div[contains(@class,"card-datos-personales")]'):
            _, lineas = lineas_de(bloque)
            resto = []
            for l in lineas:
                if l.lower().startswith("fecha de nacimiento:"):
                    reg["nacimiento_raw"] = l.split(":", 1)[1].strip() or None
                elif l.lower().startswith("fecha de defunción:") or l.lower().startswith("fecha de defuncion:"):
                    reg["defuncion_raw"] = l.split(":", 1)[1].strip() or None
                else:
                    resto.append(l)
            reg["lugar_raw"] = " ".join(resto) or None
        # La tarjeta trae el bloque de cargos dos veces (versión de escritorio y versión
        # móvil, `d-lg-block` / `d-lg-none`): con tomar el primero alcanza.
        bloques = t.xpath('.//div[contains(@class,"card-datos-legislativos")]')
        for tr in (bloques[0].xpath(".//tr") if bloques else []):
            tds = tr.xpath("./td")
            if len(tds) < 2:
                continue
            periodo_raw = txt(tds[0].text_content())
            span = tds[1].xpath(".//span")
            cargo = txt(tds[1].text) if tds[1].text else ""
            detalle = txt(span[0].text_content()) if span else ""
            partido = condicion = None
            m2 = re.fullmatch(r"\((.*)\)", detalle)
            if m2:
                interior = m2.group(1)
                if " - " in interior:
                    partido, condicion = [txt(x) for x in interior.rsplit(" - ", 1)]
                else:
                    partido = txt(interior)
            reg["cargos"].append({"periodo_raw": periodo_raw, "cargo": cargo,
                                  "partido": partido or None, "condicion": condicion or None,
                                  "detalle_raw": detalle})
        out.append(reg)
    return out


# --------------------------------------------------------------------------- ficha

SECCIONES = {
    "cargosLegislativos": "cargos_legislativos",
    "actividadPolitica": "actividad_politica",
    "titulos": "titulos",
    "estudiosCursados": "estudios",
    "actividadGremial": "actividad_gremial",
    "cargosOficiales": "cargos_oficiales",
    "publicacionesS": "publicaciones",
    "premios": "premios",
}


def _filas_seccion(sec) -> list[dict]:
    filas = []
    for tr in sec.xpath(".//tr"):
        tds = tr.xpath("./td")
        if not tds or not txt(tr.text_content()):
            continue
        if len(tds) >= 2:
            izq, der, una_celda = txt(tds[0].text_content()), tds[1], False
        else:
            izq, der, una_celda = "", tds[0], True
        negritas, lineas = lineas_de(der)
        desde, hasta = periodo(izq)
        filas.append({"periodo_raw": izq or None, "desde": desde, "hasta": hasta,
                      "en_actividad": en_actividad(izq),
                      "destacado": " ".join(negritas) or None, "lineas": lineas,
                      "una_celda": una_celda, "periodo_raro": periodo_raro(izq)})
    return filas


def _cargo_legislativo(f: dict) -> dict:
    cond = sublema = lista = partido = circ = None
    otros = []
    for l in f["lineas"]:
        if cond is None and re.fullmatch(r"\(.*\)", l):
            cond = l[1:-1].strip()
        elif l.lower().startswith("sublema:"):
            s = l.split(":", 1)[1].strip()
            m = re.search(r"\s*-\s*Lista:\s*(.+)$", s, re.I)
            if m:
                lista, s = m.group(1).strip(), s[: m.start()].strip()
            sublema = s or None
        else:
            otros.append(l)
    partido_raw = None
    if len(otros) >= 2:
        circ, partido_raw = otros[0], otros[1]
    elif len(otros) == 1:
        if es_depto(otros[0]) and not es_partido(otros[0]):
            circ = otros[0]
        else:
            partido_raw = otros[0]
    if partido_raw:
        m = re.search(r"\s*-\s*Lista:\s*(.+)$", partido_raw, re.I)
        if m:
            lista = lista or m.group(1).strip()
            partido_raw = partido_raw[: m.start()].strip()
        partido = partido_raw or None
    return {"cargo_original": f["destacado"], "cargo": cargo_norm(f["destacado"]),
            "condicion": cond, "circunscripcion": circ, "partido": partido,
            "sublema": sublema, "lista": lista, "_otros": len(otros)}


def _actividad_politica(f: dict) -> dict:
    lineas = list(f["lineas"])
    partido = sector = None
    if lineas and es_partido(lineas[-1]):
        ult = lineas.pop()
        partido, _, sector = ult.partition(" - ")
        sector = sector or None
    descripcion = SEP.join(([f["destacado"]] if f["destacado"] else []) + lineas) or None
    return {"descripcion": descripcion, "partido": partido, "sector": sector}


def parse_ficha(html: str, id_: int) -> dict:
    """Devuelve {'datos': {...}, 'secciones': {tabla: [filas]}, 'anomalias': [(tabla, tipo, detalle)]}."""
    doc = _doc(html)
    anom: list[tuple[str, str, str]] = []

    nombre = doc.xpath('//*[@id="tituloLegislador"]')
    datos = {"id": id_, "nombre_ficha": txt(nombre[0].text_content()) if nombre else None}
    if not nombre:
        anom.append(("legisladores", "sin_nombre", "no hay #tituloLegislador"))

    dp = doc.xpath('//*[@id="datosPersonales"]')
    etiquetas = {}
    if dp:
        for tr in dp[0].xpath(".//tr"):
            tds = tr.xpath("./td")
            if len(tds) == 2 and tds[0].xpath(".//b"):
                etiquetas[txt(tds[0].text_content())] = txt(tds[1].text_content())
        m = re.search(r"Última actualización:\s*([^)]+)", dp[0].text_content())
        datos["ultima_actualizacion"] = txt(m.group(1)) if m else None
    else:
        anom.append(("legisladores", "sin_datos_personales", ""))
    conocidas = {"Fecha de nacimiento", "Lugar de nacimiento", "Fecha de defunción"}
    for e in etiquetas:
        if e not in conocidas:
            anom.append(("legisladores", "etiqueta_desconocida", f"{e}: {etiquetas[e]}"))
    datos["nacimiento_raw"] = etiquetas.get("Fecha de nacimiento") or None
    datos["defuncion_raw"] = etiquetas.get("Fecha de defunción") or None
    lugar = etiquetas.get("Lugar de nacimiento") or None
    datos["lugar_nacimiento_raw"] = lugar
    partes = [txt(p) for p in lugar.split(",")] if lugar else []
    datos["nac_ciudad"] = datos["nac_subdivision"] = datos["nac_pais"] = None
    if len(partes) == 3:
        # [ciudad, subdivisión, país]; la subdivisión es el departamento sólo si nació en Uruguay
        datos["nac_ciudad"], datos["nac_subdivision"], datos["nac_pais"] = partes
    elif len(partes) == 2:  # [subdivisión, país]: p. ej. «MONTEVIDEO, URUGUAY»
        datos["nac_subdivision"], datos["nac_pais"] = partes
    elif len(partes) == 1:  # sólo el país: lugar desconocido (p. ej. «URUGUAY»)
        datos["nac_pais"] = partes[0]
    elif lugar:
        anom.append(("legisladores", "lugar_no_parseable", lugar))
    for campo in ("nacimiento_raw", "defuncion_raw"):
        raw = datos[campo]
        datos[campo.replace("_raw", "_iso")] = fecha_iso(raw)
        if raw and not fecha_iso(raw):
            anom.append(("legisladores", "fecha_no_parseable", f"{campo}={raw}"))

    secciones: dict[str, list[dict]] = {}
    for sid, tabla in SECCIONES.items():
        el = doc.xpath(f'//*[@id="{sid}"]')
        if not el:
            anom.append((tabla, "seccion_ausente", sid))
            secciones[tabla] = []
            continue
        filas = _filas_seccion(el[0])
        for orden, f in enumerate(filas, 1):
            f["orden"] = orden
            f["lineas_raw"] = SEP.join(([f["destacado"]] if f["destacado"] else []) + f["lineas"])
            if f["una_celda"]:
                anom.append((tabla, "fila_una_celda", f["lineas_raw"][:200]))
            if f["periodo_raro"]:
                anom.append((tabla, "periodo_raro", f["periodo_raw"]))
            if tabla == "cargos_legislativos":
                f.update(_cargo_legislativo(f))
                if f["_otros"] > 2:
                    anom.append((tabla, "lineas_de_mas", f["lineas_raw"][:200]))
                if f["partido"] and not es_partido(f["partido"]):
                    anom.append((tabla, "partido_no_reconocido", f["partido"]))
                if f["circunscripcion"] and not es_depto(f["circunscripcion"]):
                    anom.append((tabla, "circunscripcion_no_reconocida", f["circunscripcion"]))
                if not f["cargo_original"]:
                    anom.append((tabla, "sin_cargo", f["lineas_raw"][:200]))
            elif tabla == "actividad_politica":
                f.update(_actividad_politica(f))
            else:
                f["detalle"] = SEP.join(f["lineas"]) or None
        secciones[tabla] = filas
    return {"datos": datos, "secciones": secciones, "anomalias": anom}

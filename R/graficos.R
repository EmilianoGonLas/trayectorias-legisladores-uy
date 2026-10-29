# Gráficos en HTML/CSS (sin plotly ni ggplot2): arrancan rápido en frío, escalan en el celular y
# cambian de claro a oscuro con variables CSS, sin volver a dibujar. Los colores viven en
# www/estilos.css; acá sólo se eligen clases (l1..l8 = lemas con color propio, l9 = otros lemas,
# l0 = sin dato, n = neutro).

fmt_n <- function(x) format(x, big.mark = ".", decimal.mark = ",", trim = TRUE)
pct <- function(x) paste0(formatC(100 * x, format = "f", digits = 1, decimal.mark = ","), " %")

ANIO_ACTUAL <- as.integer(format(Sys.Date(), "%Y"))

# Un año es verosímil entre 1750 y el año que viene. La fuente trae algún error de tipeo (un premio
# fechado en «1006», id 2036): estirar el eje 900 años por eso rompe la línea, así que esos registros
# se dejan fuera de la línea (siguen en las tablas) y se avisa.
anio_ok <- function(x) !is.na(x) & x >= 1750 & x <= ANIO_ACTUAL + 1

# ---- piezas de texto -----------------------------------------------------------------------------
persona_link <- function(id, texto) tags$a(href = "#", class = "plink", `data-persona` = id, texto)

periodo_txt <- function(desde, hasta, act, raw = NA) {
  ifelse(!is.na(act) & act & !is.na(desde), paste0(desde, "–actualidad"),
  ifelse(is.na(desde), ifelse(is.na(raw) | raw == "", "s/f", raw),
  ifelse(is.na(hasta) | hasta == desde, as.character(desde), paste0(desde, "–", hasta))))
}

cargo_txt <- function(cargo, cond, circ = NA) {
  paste0(cargo, ifelse(is.na(cond), "", paste0(" · ", tolower(cond))),
         ifelse(is.na(circ), "", paste0(" · ", circ)))
}

# Nombre de la clase de color de un lema (por ranura).
cl_lema <- function(ranura) paste0("l", ranura)

leyenda_lemas <- function(ranuras, nombres) {
  u <- unique(data.frame(r = ranuras, n = nombres)); u <- u[order(ifelse(u$r == 0, 99, u$r)), ]
  tags$div(class = "leyenda", lapply(seq_len(nrow(u)), function(i)
    tags$span(class = "ley", tags$i(class = paste("pto", cl_lema(u$r[i]))), u$n[i])))
}

nombre_ranura <- function(r, lemas_por_ranura = NULL) {
  ifelse(r %in% 1:8, meta$slots_nombre[pmax(r, 1)], ifelse(r == 9, "Otros lemas", "Sin dato"))
}

# ---- línea de vida de una persona ----------------------------------------------------------------
# Una fila por cargo o actividad con año; barra de `desde` a `hasta` (inclusive) o punto si hay un
# solo año. Los cargos parlamentarios llevan el color del lema; todo lo demás va en gris, para que
# un mismo color no signifique dos cosas.
linea_tiempo <- function(cp, tp, grupos) {
  ev <- list()
  if (nrow(cp)) {
    ev$parl <- data.frame(
      grupo = "Parlamento", desde = cp$desde,
      hasta = ifelse(cp$en_actividad, ANIO_ACTUAL, cp$hasta), act = cp$en_actividad,
      rot = cargo_txt(cp$cargo, cp$condicion, cp$circunscripcion), clase = cl_lema(cp$ranura),
      tip = paste0(cargo_txt(cp$cargo_original, cp$condicion, cp$circunscripcion), " — ",
                   periodo_txt(cp$desde, cp$hasta, cp$en_actividad), " — ",
                   ifelse(is.na(cp$lema), "sin lema en la fuente", cp$lema),
                   ifelse(is.na(cp$sublema), "", paste0(" — sublema: ", cp$sublema)),
                   ifelse(is.na(cp$lista), "", paste0(" — lista ", cp$lista))))
  }
  tp <- tp[tp$seccion %in% grupos & anio_ok(tp$desde), , drop = FALSE]
  if (nrow(tp)) {
    ev$otros <- data.frame(
      grupo = tp$seccion, desde = tp$desde, hasta = ifelse(tp$en_actividad, ANIO_ACTUAL, tp$hasta),
      act = tp$en_actividad, clase = "n",
      # etiqueta: título; si falta, el detalle; si falta, el lema/sector de la actividad
      rot = ifelse(!is.na(tp$titulo), tp$titulo, ifelse(!is.na(tp$detalle), tp$detalle,
              ifelse(!is.na(tp$lema) | !is.na(tp$sector), trimws(paste(ifelse(is.na(tp$lema), "", tp$lema),
                     ifelse(is.na(tp$sector), "", paste0(" · ", tp$sector)))), NA))),
      tip = paste0(ifelse(is.na(tp$titulo), "", tp$titulo), ifelse(is.na(tp$detalle), "", paste0(" — ", tp$detalle)),
                   " — ", periodo_txt(tp$desde, tp$hasta, tp$en_actividad)))
  }
  if (!length(ev)) return(tags$p(class = "vacio", "No hay cargos con año para mostrar en esta línea."))
  ev <- do.call(rbind, ev)
  ev$rot[is.na(ev$rot)] <- "(sin descripción)"
  mal <- !anio_ok(ev$hasta) | ev$hasta < ev$desde          # sin «hasta» o con uno imposible: un solo año
  ev$hasta[mal] <- ev$desde[mal]

  lo <- min(ev$desde); hi <- max(ev$hasta); span <- hi - lo + 1
  pasos <- c(1, 2, 5, 10, 20, 25, 50, 100, 200)
  paso <- pasos[which(span / pasos <= 9)[1]]
  if (is.na(paso)) paso <- 200
  marcas <- seq(ceiling(lo / paso) * paso, hi, by = paso)
  est <- sprintf("--gp:%.3f%%;--gs:%.3f%%", (marcas[1] - lo) / span * 100, paso / span * 100)
  if (!length(marcas)) est <- "--gp:0%;--gs:100%"

  eje <- tags$div(class = "fila eje", tags$div(class = "rot"),
    tags$div(class = "pista", style = est,
      lapply(marcas, function(m) tags$span(style = sprintf("left:%.3f%%", (m - lo) / span * 100), m))))

  orden <- c("Parlamento", "Cargos oficiales", "Actividad política", "Estudios", "Títulos",
             "Actividad gremial", "Premios")
  cuerpo <- lapply(intersect(orden, unique(ev$grupo)), function(g) {
    d <- ev[ev$grupo == g, , drop = FALSE]; d <- d[order(d$desde, d$hasta), ]
    tagList(
      tags$div(class = "grupo", g, tags$small(fmt_n(nrow(d)))),
      lapply(seq_len(nrow(d)), function(i) {
        x <- d[i, ]; izq <- (x$desde - lo) / span * 100; ancho <- (x$hasta - x$desde + 1) / span * 100
        punto <- x$hasta == x$desde && x$clase == "n"
        tags$div(class = "fila",
          tags$div(class = "rot", title = x$tip, tags$span(x$rot)),
          tags$div(class = "pista", style = est,
            tags$i(class = paste("barra", x$clase, if (punto) "punto", if (x$act) "act"),
                   style = sprintf("left:%.3f%%;width:%.3f%%", if (punto) izq + ancho / 2 else izq, ancho), title = x$tip)))
      }))
  })
  tags$div(class = "tl", role = "img",
           `aria-label` = "Línea de tiempo de cargos y actividades. La misma información está en las tablas de abajo.",
           eje, cuerpo)
}

# ---- columnas apiladas: personas con cargo por lema, legislatura a legislatura -------------------
columnas_legislaturas <- function(cuentas, legs, modo = "n", sel = NA) {
  # cuentas: data.frame(leg, ranura, n). Orden de apilado fijo (de abajo hacia arriba).
  orden_r <- c(1:8, 9, 0)
  tot <- tapply(cuentas$n, cuentas$leg, sum); tope <- max(c(tot, 1))
  paso <- c(10, 20, 25, 50, 100, 200, 250, 500)[which(tope / c(10, 20, 25, 50, 100, 200, 250, 500) <= 5)[1]]
  techo <- if (modo == "n") ceiling(tope / paso) * paso else 100
  marcas <- if (modo == "n") seq(0, techo, by = paso) else seq(0, 100, by = 25)

  cols <- lapply(seq_len(nrow(legs)), function(i) {
    L <- legs[i, ]; d <- cuentas[cuentas$leg == L$numero, , drop = FALSE]; t <- sum(d$n)
    desglose <- vapply(orden_r, function(r) { n <- sum(d$n[d$ranura == r]); if (n) paste0(nombre_ranura(r), " ", n) else "" }, "")
    tip <- sprintf("Legislatura %d (%d–%d): %s personas%s", L$numero, L$desde, L$hasta, fmt_n(t),
                   if (t) paste0(" — ", paste(desglose[nzchar(desglose)], collapse = " · ")) else "")
    segs <- lapply(orden_r, function(r) {
      n <- sum(d$n[d$ranura == r]); if (!n) return(NULL)
      h <- if (modo == "n") n / techo * 100 else n / t * 100
      tags$span(class = paste("seg", cl_lema(r)), style = sprintf("height:%.3f%%", h))
    })
    tags$button(type = "button", class = paste("col", if (!is.na(sel) && sel == L$numero) "sel"),
                `data-leg` = L$numero, title = tip, `aria-label` = tip, segs)
  })
  etq <- lapply(seq_len(nrow(legs)), function(i) {
    if ((legs$numero[i] - 1) %% 5 != 0 && legs$numero[i] != max(legs$numero)) return(NULL)
    tags$span(style = sprintf("left:%.3f%%", (i - 0.5) / nrow(legs) * 100), legs$desde[i])
  })
  tags$div(class = "apilado",
    tags$div(class = "plano",
      tags$div(class = "yax", lapply(marcas, function(m)
        tags$span(style = sprintf("bottom:%.2f%%", m / max(techo, 1) * 100), if (modo == "n") fmt_n(m) else paste0(m, " %")))),
      tags$div(class = "cols",
        lapply(marcas, function(m) tags$i(class = "gr", style = sprintf("bottom:%.2f%%", m / max(techo, 1) * 100))),
        cols)),
    tags$div(class = "xax", etq),
    tags$div(class = "tenue pie-eje", "Cada columna es una legislatura (de la 1 a la 50), rotulada con su año de inicio; ",
             "el ancho de las columnas no es proporcional al tiempo."))
}

# ---- barras horizontales simples (una serie: color neutro) ---------------------------------------
barras_h <- function(etiquetas, valores, total = NULL, unidad = "personas") {
  mx <- max(valores, 1)
  tags$div(class = "bh",
    lapply(seq_along(valores), function(i)
      tags$div(class = "fila-bh",
        tags$span(class = "et", etiquetas[i]),
        tags$span(class = "pista-bh",
          tags$i(style = sprintf("width:%.3f%%", valores[i] / mx * 100),
                 title = sprintf("%s: %s %s%s", etiquetas[i], fmt_n(valores[i]), unidad,
                                 if (!is.null(total)) paste0(" (", pct(valores[i] / total), ")") else ""))),
        tags$span(class = "val", fmt_n(valores[i])))))
}

# ---- matriz de cambios de lema (secuencial: un solo tono, claro a oscuro) -------------------------
matriz_lemas <- function(tr) {
  if (!nrow(tr)) return(tags$p(class = "vacio", "No hay cambios de lema."))
  ord <- function(x) { x <- unique(x); x[order(match(x, meta$slots_nombre, nomatch = 99), x)] }
  filas_l <- ord(tr$de); cols_l <- ord(tr$a); mx <- max(tr$n)
  etq <- function(l) { r <- match(l, meta$slots_nombre, nomatch = 9L)
    tags$span(class = "et-m", tags$i(class = paste("pto", cl_lema(r))), sub("^Partido ", "P. ", l)) }
  tags$div(class = "matriz-wrap",
    tags$table(class = "matriz",
      tags$thead(tags$tr(tags$th(class = "esq", "de ↓ · a →"), lapply(cols_l, function(l) tags$th(scope = "col", etq(l))))),
      tags$tbody(lapply(filas_l, function(f) tags$tr(tags$th(scope = "row", etq(f)),
        lapply(cols_l, function(c) {
          n <- tr$n[tr$de == f & tr$a == c]
          if (!length(n) || f == c) return(tags$td(class = "cero", if (f == c) "" else "·"))
          p <- n / mx
          tags$td(style = sprintf("--p:%.1f%%", 8 + p * 82), class = if (p > .55) "fuerte",
                  title = sprintf("De %s a %s: %d cambios", f, c, n), n)
        }))))))
}

# Los cambios más frecuentes, como ranking: se lee mejor que la matriz completa.
transiciones_top <- function(tr, k = 12) {
  d <- head(tr[order(-tr$n, tr$de, tr$a), ], k); mx <- max(d$n)
  punto <- function(l) tags$i(class = paste("pto", cl_lema(match(l, meta$slots_nombre, nomatch = 9L))))
  tags$div(class = "bh bh-ancho", lapply(seq_len(nrow(d)), function(i)
    tags$div(class = "fila-bh",
      tags$span(class = "et", punto(d$de[i]), " ", d$de[i], " → ", punto(d$a[i]), " ", d$a[i]),
      tags$span(class = "pista-bh", tags$i(style = sprintf("width:%.3f%%", d$n[i] / mx * 100),
                title = sprintf("De %s a %s: %d cambios", d$de[i], d$a[i], d$n[i]))),
      tags$span(class = "val", d$n[i]))))
}

# ---- tabla de cobertura (sección «Sobre los datos») ------------------------------------------------
tabla_cobertura <- function(cb) {
  cols <- setdiff(names(cb), c("epoca", "personas"))
  tags$div(class = "matriz-wrap",
    tags$table(class = "matriz cobertura",
      tags$thead(tags$tr(tags$th(class = "esq", "Primer cargo"), tags$th(scope = "col", "Personas"),
                         lapply(cols, function(c) tags$th(scope = "col", c)))),
      tags$tbody(lapply(seq_len(nrow(cb)), function(i) tags$tr(
        tags$th(scope = "row", cb$epoca[i]), tags$td(class = "cero num", fmt_n(cb$personas[i])),
        lapply(cols, function(c) { v <- cb[[c]][i]
          tags$td(style = sprintf("--p:%.1f%%", 6 + v / 100 * 84), class = if (v > 55) "fuerte", paste0(v, " %")) }))))))
}

# ---- tablas simples ---------------------------------------------------------------------------------
tabla_simple <- function(cabeceras, filas, clase = "") {
  if (!length(filas)) return(tags$p(class = "vacio", "Sin registros."))
  tags$div(class = "tabla-wrap",
    tags$table(class = paste("tabla", clase),
      tags$thead(tags$tr(lapply(cabeceras, tags$th))),
      tags$tbody(filas)))
}

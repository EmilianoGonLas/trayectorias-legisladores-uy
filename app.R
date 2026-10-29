# Trayectorias legislativas del Uruguay — app Shiny.
# global.R carga los datos; R/graficos.R define los gráficos HTML/CSS (Shiny lo ejecuta solo); estilos en www/.
source("global.R", encoding = "UTF-8")

tema <- bs_theme(
  version = 5, primary = "#26251f",
  base_font = font_collection("system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"),
  "font-size-base" = "0.95rem")

LEGS_OPC <- setNames(rev(legs$numero), sprintf("Legislatura %d (%d–%d)", rev(legs$numero), rev(legs$desde), rev(legs$hasta)))
GRUPOS_LINEA <- c("Cargos oficiales", "Actividad política", "Estudios", "Títulos", "Actividad gremial", "Premios")
DESC <- "Los cargos, los partidos y las actividades de 1.816 legisladores uruguayos, de 1830 a hoy, a partir de las biografías de la Biblioteca del Poder Legislativo."

nav_ayuda <- function(...) div(class = "contenido", ...)

ui <- page_navbar(
  id = "tabs", theme = tema, lang = "es", fillable = FALSE,
  title = tags$span(class = "marca", "Trayectorias", tags$small("legislativas del Uruguay")),
  window_title = "Trayectorias legislativas del Uruguay",
  header = tags$head(
    tags$meta(name = "description", content = DESC),
    tags$meta(property = "og:title", content = "Trayectorias legislativas del Uruguay"),
    tags$meta(property = "og:description", content = DESC),
    tags$link(rel = "stylesheet", href = "estilos.css"), tags$script(src = "app.js")),

  # ------------------------------------------------------------------ Trayectoria
  nav_panel("Trayectoria", value = "trayectoria", nav_ayuda(
    div(class = "buscador",
      selectizeInput("persona", NULL, choices = NULL, width = "100%",
                     options = list(placeholder = "Buscar un legislador por apellido o nombre…", maxOptions = 40)),
      actionButton("azar", "Otro al azar", class = "btn btn-outline-secondary")),
    uiOutput("cabecera"),
    div(class = "controles",
      checkboxGroupInput("grupos", "Además del Parlamento, mostrar en la línea", choices = GRUPOS_LINEA,
                         selected = c("Cargos oficiales", "Actividad política"), inline = TRUE)),
    uiOutput("linea"),
    h2("Todo el detalle", class = "h5 mt-4"),
    uiOutput("detalle"))),

  # ------------------------------------------------------------------ Legislaturas
  nav_panel("Legislaturas", value = "legislaturas", nav_ayuda(
    h1("Quiénes ocuparon una banca, legislatura por legislatura", class = "h3"),
    p(class = "sub", "Cada columna es una legislatura; su altura, la cantidad de personas con algún cargo en ella,",
      "apiladas por lema. Un clic en una columna lista a esas personas más abajo."),
    div(class = "filtros controles",
      radioButtons("camara", "Cámara", c("Ambas", "Diputados", "Senado"), inline = TRUE),
      radioButtons("cond", "Condición registrada", c("Todas", "Titular", "Suplente"), inline = TRUE),
      radioButtons("vista", "Mostrar", c("Personas" = "n", "Proporción" = "p"), inline = TRUE)),
    card(card_body(uiOutput("graf_leg"), uiOutput("ley_leg"),
                   tags$details(class = "tabla-vista", tags$summary("Ver como tabla"), uiOutput("tab_leg_vista")))),
    div(class = "nota",
        "Una persona cuenta una vez por legislatura y lema. No son bancas: incluye a titulares y suplentes tal como",
        "figuran en la fuente, y la fuente no dice cuántas veces un suplente llegó a ocupar la banca."),
    div(class = "filtros mt-4", selectInput("leg", "Ver las personas de", LEGS_OPC, selected = max(legs$numero), width = "300px")),
    uiOutput("tabla_leg"))),

  # ------------------------------------------------------------------ Recorridos
  nav_panel("Recorridos", value = "recorridos", nav_ayuda(
    h1("Recorridos: lo que se repite y lo que se aparta", class = "h3"),
    p(class = "sub", "Conteos sobre los cargos parlamentarios registrados. Describen a quienes llegaron a una banca;",
      "no dicen nada de quienes se presentaron y no asumieron."),
    layout_columns(fill = FALSE, col_widths = breakpoints(sm = 12, lg = c(6, 6)),
      card(card_header("¿Cuántas legislaturas?"), card_body(uiOutput("perm"))),
      card(card_header("Entre cámaras"), card_body(uiOutput("camaras")))),
    card(class = "mt-3", card_header("Casos concretos"), card_body(
      div(class = "controles",
        radioButtons("caso", NULL, inline = TRUE, choices = c(
          "Cambio de lema" = "lema", "Cambio de departamento (diputados)" = "circunscripcion",
          "Pasaje entre cámaras" = "camara"))),
      uiOutput("caso_ui"))))),

  # ------------------------------------------------------------------ Buscar en el texto
  nav_panel("Buscar en el texto", value = "buscar", nav_ayuda(
    h1("Buscar en cargos, actividades y estudios", class = "h3"),
    p(class = "sub", "Búsqueda libre sobre el texto de las biografías, sin distinguir tildes ni mayúsculas.",
      "Con varias palabras, deben aparecer todas."),
    div(class = "filtros controles",
      textInput("q", "Buscar", placeholder = "intendente, ministro, exilio, sindicato…", width = "320px"),
      checkboxGroupInput("secs", "En", choices = meta$secciones, selected = meta$secciones, inline = TRUE)),
    div(class = "filtros controles",
      sliderInput("anios", "Años", min = 1830, max = ANIO_ACTUAL, value = c(1830, ANIO_ACTUAL), sep = "", step = 1, width = "320px"),
      checkboxInput("sin_anio", "Incluir registros sin año", TRUE)),
    uiOutput("resumen_busq"),
    uiOutput("tabla_busq"))),

  # ------------------------------------------------------------------ Sobre los datos
  nav_panel("Sobre los datos", value = "datos", nav_ayuda(
    h1("Sobre los datos", class = "h3"),
    uiOutput("sobre"))),

  nav_spacer(),
  nav_item(tags$a(href = URL_REPO, target = "_blank", rel = "noopener", "Código y datos ↗")),
  nav_item(input_dark_mode(id = "modo"))
)

server <- function(input, output, session) {

  # ---- elección de persona (selector, enlaces internos, URL compartible) ----
  elegir <- function(id) updateSelectizeInput(session, "persona", choices = OPCIONES, selected = id, server = TRUE)

  observeEvent(session$clientData$url_search, {
    q <- suppressWarnings(as.integer(parseQueryString(session$clientData$url_search)$persona))
    elegir(if (length(q) == 1 && !is.na(q) && q %in% personas$id) q else sample(POOL, 1))
  }, once = TRUE)
  observeEvent(input$azar, elegir(sample(setdiff(POOL, suppressWarnings(as.integer(input$persona))), 1)))
  observeEvent(input$abrir, {
    elegir(input$abrir); nav_select("tabs", "trayectoria"); session$sendCustomMessage("arriba", TRUE)
  })
  observeEvent(input$persona, {
    if (nzchar(input$persona)) updateQueryString(paste0("?persona=", input$persona), mode = "replace")
  }, ignoreInit = TRUE)

  pid <- reactive(as.integer(req(input$persona)))
  P  <- reactive(personas[personas$id == pid(), ])
  CP <- reactive({ d <- cargos[cargos$id == pid(), ]; d[order(d$desde, d$orden), ] })
  TP <- reactive(texto[texto$id == pid(), ])

  # ---- Trayectoria ----
  output$cabecera <- renderUI({
    p <- P(); cp <- CP()
    nac <- c(if (!is.na(p$nacimiento)) paste0("Nació el ", p$nacimiento, if (!is.na(p$lugar)) paste0(" en ", p$lugar)),
             if (!is.na(p$defuncion)) paste0("falleció el ", p$defuncion))
    chips <- list()
    if (nrow(cp)) {
      chips <- c(chips, list(tags$span(class = "chip", sprintf("%d cargo%s en %d legislatura%s", nrow(cp), if (nrow(cp) > 1) "s" else "",
                                                           p$n_leg, if (p$n_leg > 1) "s" else ""))))
      lem <- unique(cp[order(cp$desde), c("lema", "ranura")])
      chips <- c(chips, lapply(seq_len(nrow(lem)), function(i)
        tags$span(class = "chip", tags$i(class = paste("pto", cl_lema(lem$ranura[i]))), ifelse(is.na(lem$lema[i]), "Sin lema en la fuente", lem$lema[i]))))
    }
    tagList(
      h1(class = "persona", p$nombre),
      if (length(nac)) p(class = "sub", paste(nac, collapse = " · ")),
      div(class = "chips", chips),
      p(class = "tenue",
        tags$a(href = sprintf("https://biblioteca.parlamento.gub.uy:8008/biografias/legislador/%d", p$id), target = "_blank",
               rel = "noopener", "Ficha original ↗"),
        if (!is.na(p$actualizacion) && p$actualizacion != "--") paste0(" · actualizada: ", sub("^(.)", "\\U\\1", tolower(p$actualizacion), perl = TRUE))),
      if (!nrow(cp)) div(class = "nota", "La fuente no registra cargos legislativos para esta persona."))
  })

  output$linea <- renderUI({
    cp <- CP(); tp <- TP(); gr <- input$grupos %||% character()
    sin <- sum(tp$seccion %in% gr & !anio_ok(tp$desde))
    card(card_body(
      linea_tiempo(cp, tp, gr),
      if (nrow(cp)) leyenda_lemas(cp$ranura, nombre_ranura(cp$ranura)),
      div(class = "tenue", "Barras de color: cargos parlamentarios, según el lema. Barras grises: lo demás. ",
          "Los puntos son hechos de un solo año.",
          if (sin) sprintf(" %d registro%s sin año (o con un año imposible en la fuente) aparece%s sólo en las tablas.", sin, if (sin > 1) "s" else "", if (sin > 1) "n" else ""))))
  })

  output$detalle <- renderUI({
    cp <- CP(); tp <- TP()
    filas_c <- lapply(seq_len(nrow(cp)), function(i) { x <- cp[i, ]
      tags$tr(tags$td(class = "per", periodo_txt(x$desde, x$hasta, x$en_actividad)), tags$td(x$cargo), tags$td(x$condicion),
              tags$td(x$circunscripcion),
              tags$td(if (!is.na(x$lema)) tags$span(class = "ley", tags$i(class = paste("pto", cl_lema(x$ranura))), x$lema) else "—"),
              tags$td(x$sublema), tags$td(x$lista)) })
    paneles <- list(accordion_panel(
      title = tagList("Cargos legislativos", tags$span(class = "n-sec", nrow(cp))), value = "Cargos legislativos",
      tabla_simple(c("Período", "Cargo", "Condición", "Circunscripción", "Lema", "Sublema", "Lista"), filas_c)))
    for (s in meta$secciones) {
      d <- tp[tp$seccion == s, ]; if (!nrow(d)) next
      filas <- lapply(seq_len(nrow(d)), function(i) { x <- d[i, ]
        tags$tr(tags$td(class = "per", periodo_txt(x$desde, x$hasta, x$en_actividad, x$periodo_raw)),
                tags$td(x$titulo), tags$td(x$detalle),
                if (s == "Actividad política") tags$td(paste(na.omit(c(x$lema, x$sector)), collapse = " · "))) })
      cab <- c("Período", "Descripción", "Detalle", if (s == "Actividad política") "Lema · sector")
      paneles <- c(paneles, list(accordion_panel(
        title = tagList(s, tags$span(class = "n-sec", nrow(d))), value = s, tabla_simple(cab, filas))))
    }
    do.call(accordion, c(list(id = "acc", open = "Cargos legislativos", multiple = TRUE), paneles))
  })

  # ---- Legislaturas ----
  cargos_f <- reactive({
    d <- cargos
    if (input$camara != "Ambas") d <- d[d$camara == input$camara, ]
    if (input$cond != "Todas") d <- d[!is.na(d$condicion) & d$condicion == input$cond, ]
    d
  })
  cuentas <- reactive(cargos_f() |> distinct(id, leg, ranura) |> count(leg, ranura, name = "n"))

  output$graf_leg <- renderUI(columnas_legislaturas(cuentas(), legs, input$vista, sel = suppressWarnings(as.integer(input$leg))))
  output$ley_leg <- renderUI({ r <- sort(unique(cuentas()$ranura)); r <- c(r[r %in% 1:9], r[r == 0])
    leyenda_lemas(r, nombre_ranura(r)) })
  output$tab_leg_vista <- renderUI({
    cu <- cuentas(); r <- c(1:9, 0); r <- r[r %in% cu$ranura]
    filas <- lapply(rev(legs$numero), function(l) { x <- cu[cu$leg == l, ]; L <- legs[legs$numero == l, ]
      tags$tr(tags$td(sprintf("%d (%d–%d)", l, L$desde, L$hasta)), tags$td(fmt_n(sum(x$n))),
              lapply(r, function(k) tags$td(fmt_n(sum(x$n[x$ranura == k]))))) })
    tabla_simple(c("Legislatura", "Total", nombre_ranura(r)), filas)
  })
  observeEvent(input$leg_click, updateSelectInput(session, "leg", selected = input$leg_click))

  output$tabla_leg <- renderUI({
    L <- as.integer(req(input$leg)); LL <- legs[legs$numero == L, ]
    d <- cargos_f() |> filter(leg == L)
    if (!nrow(d)) return(div(class = "nota", "Sin personas con estos filtros en la legislatura ", L, "."))
    g <- d |> group_by(id) |> summarise(
      cargo = paste(unique(cargo_txt(cargo, condicion)), collapse = "; "),
      lema = paste(unique(na.omit(lema)), collapse = " / "), circ = paste(unique(na.omit(circunscripcion)), collapse = ", "),
      cam = first(camara), r = first(ranura), .groups = "drop") |>
      left_join(personas |> select(id, nombre_busq), by = "id") |> arrange(cam, nombre_busq)
    filas <- lapply(seq_len(nrow(g)), function(i) { x <- g[i, ]
      tags$tr(tags$td(persona_link(x$id, x$nombre_busq)), tags$td(x$cargo),
              tags$td(if (nzchar(x$lema)) tags$span(class = "ley", tags$i(class = paste("pto", cl_lema(x$r))), x$lema) else "—"),
              tags$td(x$circ)) })
    tagList(h2(sprintf("Legislatura %d (%d–%d): %s personas", L, LL$desde, LL$hasta, fmt_n(nrow(g))), class = "h5"),
            tabla_simple(c("Persona", "Cargo", "Lema", "Circunscripción"), filas))
  })

  # ---- Recorridos ----
  output$perm <- renderUI({
    pm <- meta$perm; k <- pmin(pm$k, 6); v <- tapply(pm$personas, k, sum)
    tagList(barras_h(c(paste(1:5, c("legislatura", rep("legislaturas", 4))), "6 o más"), as.integer(v), total = sum(v)),
            div(class = "nota", "Cuenta las legislaturas distintas en las que la persona tiene algún cargo registrado. ",
                "Un suplente que nunca llegó a sentarse figura igual que quien cumplió el período."))
  })
  output$camaras <- renderUI({
    ct <- meta$cam_tipo; ord <- c("Sólo Diputados", "Sólo Senado", "Diputados y después Senado", "Senado y después Diputados", "Ambas cámaras en el mismo año")
    ct <- ct[match(ord, ct$tipo), ]; amb <- sum(ct$personas[3:5]); dp <- ct$personas[3]
    tagList(barras_h(ct$tipo, ct$personas, total = sum(ct$personas)),
            div(class = "nota", sprintf("De las %s personas con cargo en las dos cámaras, %s (%s) empezó por Diputados. ",
                                        fmt_n(amb), fmt_n(dp), pct(dp / amb)),
                "El orden se define por el año del primer cargo en cada cámara."))
  })

  output$caso_ui <- renderUI({
    k <- input$caso; cs <- meta$casos[meta$casos$tipo == k, ] |>
      left_join(personas |> select(id, nombre_busq), by = "id") |> arrange(nombre_busq)
    filas <- lapply(seq_len(nrow(cs)), function(i) tags$tr(tags$td(persona_link(cs$id[i], cs$nombre_busq[i])), tags$td(cs$trayecto[i])))
    pie <- switch(k,
      lema = "Se cuenta un cambio cuando dos cargos consecutivos de la misma persona tienen lemas distintos. No registra cambios de sector o sublema dentro de un mismo lema, ni candidaturas, ni afiliaciones sin cargo.",
      circunscripcion = "Diputados que figuran por más de un departamento a lo largo de sus cargos. Un cambio de circunscripción no implica un cambio de residencia.",
      camara = "Personas con cargo en ambas cámaras, con el año de su primer cargo en cada una.")
    tagList(
      div(class = "kpis", div(class = "kpi", tags$b(fmt_n(nrow(cs))), tags$span("personas"))),
      if (k == "lema") tagList(
        h3(sprintf("Los cambios más frecuentes (de %s en total)", fmt_n(sum(meta$trans$n))), class = "h6 mt-3"),
        transiciones_top(meta$trans),
        tags$details(class = "tabla-vista", tags$summary("Ver la matriz completa"), matriz_lemas(meta$trans))),
      div(class = "nota", pie),
      tabla_simple(c("Persona", "Trayecto"), filas))
  })

  # ---- Buscar en el texto ----
  q_d <- debounce(reactive(input$q), 350)
  hallazgos <- reactive({
    q <- tolower(iconv(trimws(q_d() %||% ""), to = "ASCII//TRANSLIT"))
    if (!nzchar(q)) return(NULL)
    d <- texto[texto$seccion %in% (input$secs %||% character()), ]
    for (t in strsplit(q, "\\s+")[[1]]) d <- d[grepl(t, d$busq, fixed = TRUE), ]
    lo <- input$anios[1]; hi <- input$anios[2]
    ok <- if (isTRUE(input$sin_anio)) is.na(d$desde) else FALSE
    d <- d[ok | (!is.na(d$desde) & d$desde <= hi & coalesce(d$hasta, d$desde) >= lo), ]
    d |> left_join(personas |> select(id, nombre_busq), by = "id") |> arrange(nombre_busq, desde)
  })
  output$resumen_busq <- renderUI({
    h <- hallazgos()
    if (is.null(h)) return(div(class = "nota", "Escribir una o más palabras para buscar."))
    if (!nrow(h)) return(div(class = "nota", "Sin resultados."))
    div(class = "sub mb-2", sprintf("%s registros de %s personas", fmt_n(nrow(h)), fmt_n(n_distinct(h$id))),
        if (nrow(h) > 200) " (se muestran los primeros 200; todos van en la descarga)",
        downloadButton("bajar", "Descargar CSV", class = "btn btn-sm btn-outline-secondary ms-3"))
  })
  output$tabla_busq <- renderUI({
    h <- hallazgos(); if (is.null(h) || !nrow(h)) return(NULL)
    h <- head(h, 200)
    filas <- lapply(seq_len(nrow(h)), function(i) { x <- h[i, ]
      tags$tr(tags$td(persona_link(x$id, x$nombre_busq)), tags$td(tags$span(class = "sec", x$seccion)),
              tags$td(class = "per", periodo_txt(x$desde, x$hasta, x$en_actividad, x$periodo_raw)),
              tags$td(x$titulo, if (!is.na(x$detalle)) tags$span(class = "tenue", paste0(" — ", x$detalle)))) })
    tabla_simple(c("Persona", "Sección", "Período", "Texto"), filas)
  })
  output$bajar <- downloadHandler(
    filename = function() "busqueda_trayectorias.csv",
    content = function(file) {
      h <- hallazgos()
      write.csv(h[, c("id", "nombre_busq", "seccion", "desde", "hasta", "titulo", "detalle", "lema", "sector")],
                file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    })

  # ---- Sobre los datos ----
  output$sobre <- renderUI({
    n_cargos <- fmt_n(meta$n_cargos)
    tagList(
      p("Esta página reúne las biografías de ", fmt_n(meta$n_personas), " legisladores uruguayos —titulares y suplentes, de la ",
        "primera legislatura (1830) a la actual— y las ordena para ver trayectorias: qué cargos ocupó cada persona, en qué orden, ",
        "por qué lema y por qué departamento, y qué hizo antes y después de pasar por el Parlamento."),
      h2("La fuente", class = "h5 mt-4"),
      p("Todo sale del ", tags$a(href = URL_FUENTE, target = "_blank", rel = "noopener", "Sistema de Consultas de Biografías de Legisladores"),
        " de la Biblioteca del Poder Legislativo, que publica cada biografía como una página con texto libre. ",
        "Se descargó entera el ", meta$fecha_descarga, " y se le devolvió estructura: una tabla por tipo de dato, ",
        "con una fila por cargo, estudio o actividad. Los datos son de la Biblioteca; lo que se agrega acá es el orden."),
      h2("Cómo se comprobó", class = "h5 mt-4"),
      p("Los ", n_cargos, " cargos legislativos de las fichas coinciden uno a uno con los de las tarjetas del listado de la fuente. ",
        "Todo lo que el programa no pudo interpretar queda registrado en vez de descartarse o adivinarse. ",
        "El código, los datos y la bitácora con cada decisión están en el ", tags$a(href = URL_REPO, target = "_blank", rel = "noopener", "repositorio"), "."),
      h2("La cobertura cambia con la época", class = "h5 mt-4"),
      p("Porcentaje de personas con al menos un dato, según el año de su primer cargo:"),
      tabla_cobertura(meta$cobertura),
      p(class = "tenue mt-2", "La fecha de nacimiento y la actividad política tienen un hueco entre quienes ingresaron de 1900 a 1939. ",
        "Publicaciones, premios y cargos oficiales, al revés, caen en las cohortes recientes. Es probable que cada ficha refleje lo que la ",
        "persona declaró o lo que se pudo reconstruir, pero eso es una hipótesis, no algo verificado."),
      h2("Qué no permiten afirmar", class = "h5 mt-4"),
      tags$ul(
        tags$li(tags$b("Quién llega y quién no."), " Sólo están quienes ocuparon una banca; no hay candidatos que no asumieron."),
        tags$li(tags$b("Comparar épocas sin cuidado."), " Que una ficha reciente tenga menos premios o publicaciones no quiere decir que esas personas tengan menos: puede ser cómo se completó la ficha."),
        tags$li(tags$b("Bancas ocupadas."), " «Titular» y «suplente» son como los registra la fuente. Hay más titulares distintos por legislatura que bancas, por los reemplazos, y no se sabe cuánto sirvió cada suplente."),
        tags$li(tags$b("El año exacto de ingreso."), " Cada cargo se ubica en la legislatura que empieza en su año de inicio. Un suplente de un tramo que cae en el último año de una legislatura queda en la siguiente."),
        tags$li(tags$b("Cambios dentro de un partido."), " Los cambios de lema se detectan sólo entre cargos parlamentarios; los sectores y sublemas son texto libre y no se normalizaron."),
        tags$li(tags$b("Cobertura completa."), sprintf(" Hay %d identificadores en la base de la fuente que no se pueden consultar (devuelven error) y no figuran en el listado. No se sabe quiénes son.", meta$n_sin_ficha))),
      p(class = "pie", "Datos: Biblioteca del Poder Legislativo de la República Oriental del Uruguay. Descarga: ", meta$fecha_descarga, ".")
    )
  })
}

shinyApp(ui, server)

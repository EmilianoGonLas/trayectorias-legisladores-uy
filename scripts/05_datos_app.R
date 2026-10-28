# Paso 5: arma data/app/datos.rds, lo único que lee la app.
# Uso (desde la raíz del repo):  Rscript scripts/05_datos_app.R
#
# La app arranca en frío en un servidor chico, así que no lee parquet ni carga arrow:
# todo lo que se puede precalcular se precalcula acá (ver global.R).

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(stringr)
})

rd <- function(n) as_tibble(read_parquet(file.path("data/processed", paste0(n, ".parquet"))))
llave <- function(x) toupper(iconv(x, to = "ASCII//TRANSLIT"))

# Mayúsculas de la fuente -> «Nombre Apellido», con las partículas en minúscula.
titulo <- function(x) {
  x <- str_to_title(str_to_lower(x))
  x <- str_replace_all(x, c(" De " = " de ", " Del " = " del ", " La " = " la ", " Las " = " las ",
                            " Los " = " los ", " Y " = " y ", " Da " = " da ", " Di " = " di ", " Von " = " von "))
  # D'auggero -> D'Auggero, O'neill -> O'Neill
  str_replace_all(x, "(?<=[A-Za-zÀ-ÿ]')([a-zà-ÿ])", \(m) toupper(m))
}

leg <- rd("legisladores"); cl <- rd("cargos_legislativos"); lg <- rd("legislaturas"); lm <- rd("lemas")

# ---- lemas: nombre oficial y ranura de color (fija por entidad, no por ranking) -----------------
# Orden validado con scripts de la guía dataviz en claro y oscuro (ver BITACORA §7).
SLOTS <- c("Partido Nacional", "Partido Colorado", "Frente Amplio", "Partido Cabildo Abierto",
           "Partido Independiente", "Nuevo Espacio", "Partido Nacional Independiente",
           "Unión Cívica del Uruguay")
# La fuente escribe varios lemas sin tildes; se corrigen sólo para mostrar.
tildes <- c("Union Civica del Uruguay" = "Unión Cívica del Uruguay", "Union Popular" = "Unión Popular",
            "Union Socialista Liberal" = "Unión Socialista Liberal", "Union DemóCrata Reformista" = "Unión Demócrata Reformista",
            "Partido Democrata Cristiano" = "Partido Demócrata Cristiano",
            "Partido por la Tradicion Colorada" = "Partido por la Tradición Colorada",
            "Frente Izquierda de Liberacion (FIDEL)" = "Frente Izquierda de Liberación (FIDEL)")
lm$nombre <- ifelse(lm$nombre %in% names(tildes), unname(tildes[lm$nombre]), lm$nombre)
lema_nombre <- setNames(lm$nombre, llave(lm$nombre))
lema_de <- function(p) unname(lema_nombre[llave(p)])
ranura <- function(l) ifelse(is.na(l), 0L, match(l, SLOTS, nomatch = 9L))   # 9 = otros lemas; 0 = sin dato

# ---- legislatura de cada cargo: la que tiene el mayor inicio <= desde ---------------------------
# Un cargo «2020 - 2020» (suplente de un tramo) se asigna a la legislatura que empieza en 2020, no a
# la anterior que termina ese año. Es una convención, no un dato de la fuente.
asignar_leg <- function(d) {
  i <- findInterval(d, lg$desde)
  ifelse(i > 0 & d <= lg$hasta[pmax(i, 1)], lg$numero[pmax(i, 1)], NA_integer_)
}

cargos <- cl |>
  mutate(
    lema = lema_de(partido),
    ranura = ranura(lema),
    camara = case_when(
      cargo == "DIPUTADO" | str_detect(cargo, "REPRESENTANTES") ~ "Diputados",
      cargo == "SENADOR" | str_detect(cargo, "SENAD") ~ "Senado",
      TRUE ~ "Otro"),
    # Para mostrar se usa el cargo tal como lo escribe la fuente (con tilde y género: «Diputada»);
    # `cargo` normalizado sólo sirve para agrupar y para detectar la cámara.
    cargo_txt = str_to_sentence(str_to_lower(cargo_original)),
    circunscripcion = ifelse(is.na(circunscripcion), NA, titulo(str_remove(circunscripcion, " \\(.*\\)"))),
    sublema = ifelse(is.na(sublema), NA, titulo(sublema)),
    leg = asignar_leg(desde)) |>
  select(id, orden, desde, hasta, en_actividad, cargo_original, cargo = cargo_txt, camara, condicion,
         circunscripcion, lema, ranura, sublema, lista, leg)
stopifnot(!anyNA(cargos$leg))

# ---- texto libre: las siete secciones que no son cargos legislativos -----------------------------
sec <- function(nombre, etiqueta) {
  d <- rd(nombre)
  if (nombre == "actividad_politica") {
    d <- d |> mutate(titulo = str_extract(descripcion, "^[^¦]+") |> str_trim(),
                     detalle = str_trim(str_remove(descripcion, "^[^¦]+¦?")), destacado = NA_character_)
  } else {
    d <- d |> mutate(titulo = destacado, sector = NA_character_, partido = NA_character_)
  }
  d |> transmute(id, seccion = etiqueta, orden, desde, hasta, en_actividad, periodo_raw,
                 titulo, detalle = str_replace_all(detalle, " ¦ ", " · "),
                 lema = lema_de(partido), sector)
}
texto <- bind_rows(
  sec("cargos_oficiales", "Cargos oficiales"), sec("actividad_politica", "Actividad política"),
  sec("estudios", "Estudios"), sec("titulos", "Títulos"), sec("actividad_gremial", "Actividad gremial"),
  sec("publicaciones", "Publicaciones"), sec("premios", "Premios")) |>
  mutate(detalle = ifelse(detalle == "" | is.na(detalle), NA, detalle),
         busq = tolower(llave(paste(titulo, detalle, sector, lema))))

# ---- personas ------------------------------------------------------------------------------------
res <- cargos |> group_by(id) |>
  summarise(n_cargos = n(), n_leg = n_distinct(leg), primer = min(desde), ultimo = max(coalesce(hasta, desde)),
            vigente = any(en_actividad), .groups = "drop")
personas <- leg |>
  transmute(id, nombre_busq = titulo(nombre_listado), nombre = titulo(nombre_ficha),
            nacimiento = nacimiento_raw, defuncion = defuncion_raw,
            lugar = case_when(!is.na(nac_ciudad) & !is.na(nac_pais) & nac_pais != "URUGUAY" ~
                                paste0(titulo(nac_ciudad), ", ", titulo(nac_pais)),
                              !is.na(nac_ciudad) ~ titulo(nac_ciudad),
                              !is.na(nac_subdivision) ~ titulo(nac_subdivision), TRUE ~ NA_character_),
            actualizacion = ultima_actualizacion) |>
  left_join(res, by = "id") |>
  mutate(etiqueta = ifelse(is.na(primer), nombre_busq, paste0(nombre_busq, " (", primer, "–", ifelse(vigente, "", ultimo), ")"))) |>
  arrange(nombre_busq)

# ---- recorridos ----------------------------------------------------------------------------------
# Secuencia de valores en orden cronológico, sin repetir consecutivos: «A (1990) → B (1995)».
secuencia <- function(d, col) {
  d |> filter(!is.na(.data[[col]])) |> arrange(id, desde, orden) |>
    group_by(id) |> filter(.data[[col]] != lag(.data[[col]], default = "") ) |> ungroup()
}
trayecto <- function(s, col) s |> group_by(id) |>
  summarise(n = n(), trayecto = paste0(.data[[col]], " (", desde, ")", collapse = " → "), .groups = "drop") |>
  filter(n > 1)

sec_lema <- secuencia(cargos, "lema")
sec_circ <- secuencia(filter(cargos, camara == "Diputados"), "circunscripcion")
lema_casos <- trayecto(sec_lema, "lema")
circ_casos <- trayecto(sec_circ, "circunscripcion")

trans <- sec_lema |> group_by(id) |> mutate(a = lag(lema)) |> ungroup() |>
  filter(!is.na(a)) |> count(de = a, a = lema, name = "n")

ord_cam <- cargos |> filter(camara != "Otro") |> group_by(id, camara) |>
  summarise(p = min(desde), .groups = "drop") |> pivot_wider(names_from = camara, values_from = p)
cam_tipo <- ord_cam |> mutate(tipo = case_when(
  !is.na(Diputados) & is.na(Senado) ~ "Sólo Diputados",
  is.na(Diputados) & !is.na(Senado) ~ "Sólo Senado",
  Diputados < Senado ~ "Diputados y después Senado",
  Senado < Diputados ~ "Senado y después Diputados",
  TRUE ~ "Ambas cámaras en el mismo año"))
cam_casos <- cam_tipo |> filter(grepl("después|mismo", tipo)) |>
  transmute(id, tipo, trayecto = paste0("Diputados (", Diputados, ") · Senado (", Senado, ")"))

perm <- cargos |> distinct(id, leg) |> count(id, name = "k") |> count(k, name = "personas")

# ---- cobertura de cada dato según la época de ingreso --------------------------------------------
cobertura <- leg |> inner_join(res |> select(id, primer), by = "id") |>
  mutate(epoca = paste0(primer %/% 20 * 20, "–", primer %/% 20 * 20 + 19)) |>
  group_by(epoca) |>
  summarise(personas = n(),
            `Fecha de nacimiento` = round(100 * mean(!is.na(nacimiento_iso))),
            `Actividad política` = round(100 * mean(n_actividad_politica > 0)),
            `Cargos oficiales` = round(100 * mean(n_cargos_oficiales > 0)),
            `Estudios` = round(100 * mean(n_estudios > 0)),
            `Publicaciones` = round(100 * mean(n_publicaciones > 0)),
            `Premios` = round(100 * mean(n_premios > 0)), .groups = "drop")

meta <- list(
  fecha_descarga = "28 de octubre de 2026",
  n_personas = nrow(leg), n_cargos = nrow(cargos), n_texto = nrow(texto),
  n_sin_ficha = 170L, slots = SLOTS,
  secciones = c("Cargos oficiales", "Actividad política", "Estudios", "Títulos", "Actividad gremial",
                "Publicaciones", "Premios"),
  anio_max = max(lg$hasta), cobertura = cobertura, perm = perm, trans = trans,
  cam_tipo = count(cam_tipo, tipo, name = "personas"),
  casos = bind_rows(
    lema_casos |> transmute(tipo = "lema", id, n, trayecto),
    circ_casos |> transmute(tipo = "circunscripcion", id, n, trayecto),
    cam_casos |> transmute(tipo = "camara", id, n = 2L, trayecto)))

dir.create("data/app", showWarnings = FALSE, recursive = TRUE)
saveRDS(list(personas = personas, cargos = cargos, texto = select(texto, -busq) |> mutate(busq = texto$busq),
             legislaturas = lg, meta = meta), "data/app/datos.rds", compress = "xz")
message(sprintf("data/app/datos.rds: %.1f MB | personas %d · cargos %d · texto %d · casos %d",
                file.size("data/app/datos.rds") / 1e6, nrow(personas), nrow(cargos), nrow(texto), nrow(meta$casos)))
print(count(meta$casos, tipo)); print(cam_tipo |> count(tipo)); print(cobertura)

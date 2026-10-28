# Paso 4: pasa los CSV de data/processed/ a parquet con tipos explícitos.
# Uso (desde la raíz del repo):  Rscript scripts/04_a_parquet.R
#
# Los CSV son la salida de scripts/03_parsear.py. Se mantienen en el repo porque son
# diffeables; el parquet es lo que se consume desde R.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(arrow)
})

dir <- "data/processed"
stopifnot(dir.exists(dir))

leer <- function(nombre, ...) {
  read_csv(file.path(dir, paste0(nombre, ".csv")),
           col_types = cols(.default = col_character(), ...),
           na = c("", "NA"), progress = FALSE)
}

escribir <- function(df, nombre) {
  write_parquet(df, file.path(dir, paste0(nombre, ".parquet")))
  message(sprintf("  %-22s %6d filas x %2d columnas", nombre, nrow(df), ncol(df)))
}

message("Escribiendo parquet en ", dir)

leer("legisladores",
     id = col_integer(), nacimiento_iso = col_date(), defuncion_iso = col_date(),
     pagina_listado = col_integer(), en_listado = col_logical(), bytes_ficha = col_integer()) |>
  mutate(across(starts_with("n_"), as.integer)) |>
  escribir("legisladores")

secciones <- c("cargos_legislativos", "actividad_politica", "titulos", "estudios",
               "actividad_gremial", "cargos_oficiales", "publicaciones", "premios")
for (s in secciones) {
  leer(s, id = col_integer(), orden = col_integer(), desde = col_integer(), hasta = col_integer(),
       en_actividad = col_logical()) |>
    escribir(s)
}

leer("listado_cargos",
     id = col_integer(), orden = col_integer(), desde = col_integer(), hasta = col_integer(),
     en_actividad = col_logical()) |>
  escribir("listado_cargos")

leer("anomalias", id = col_integer()) |> escribir("anomalias")
leer("ids_estado", id = col_integer(), en_listado = col_logical(), http = col_integer(),
     bytes = col_integer()) |>
  escribir("ids_estado")

leer("legislaturas", numero = col_integer(), desde = col_integer(), hasta = col_integer()) |>
  escribir("legislaturas")
leer("lemas") |> escribir("lemas")

# Trayectorias legislativas del Uruguay — dependencias y datos globales.
#
# Pensado para arrancar rápido en frío (Connect Cloud apaga la app tras unos minutos sin visitas):
# no se carga arrow ni ggplot2, los gráficos son HTML/CSS y todo viene precalculado de un único
# .rds (scripts/05_datos_app.R).
suppressPackageStartupMessages({
  library(shiny); library(bslib); library(dplyr)
})

# bslib compila Bootstrap con Sass en cada arranque (~1,5 s). La caché compilada viaja con la app
# (Rscript scripts/precalentar_css.R la regenera).
if (dir.exists("sass-cache")) options(sass.cache = sass::sass_file_cache("sass-cache"))

`%||%` <- function(a, b) if (is.null(a)) b else a   # base R lo trae desde 4.4

D <- readRDS("data/app/datos.rds")
personas <- D$personas; cargos <- D$cargos; texto <- D$texto; legs <- D$legislaturas; meta <- D$meta
meta$slots_nombre <- meta$slots
rm(D)

URL_REPO <- "https://github.com/EmilianoGonLas/trayectorias-legisladores-uy"
URL_FUENTE <- "https://biblioteca.parlamento.gub.uy:8008/biografias/busqueda"

OPCIONES <- setNames(personas$id, personas$etiqueta)

# Al abrir la app sin enlace a una persona se muestra una al azar entre las de recorrido rico
# (varias legislaturas y bastante texto): así la primera pantalla enseña qué hace la línea de vida
# sin elegir a nadie en particular. Cualquier otra persona se abre con ?persona=<id>.
.n_texto <- table(texto$id)
POOL <- personas$id[!is.na(personas$n_leg) & personas$n_leg >= 3 &
                      coalesce(as.integer(.n_texto[as.character(personas$id)]), 0L) >= 15]

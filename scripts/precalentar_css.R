# Genera sass-cache/ con el CSS del tema ya compilado (ver global.R).
# bslib compila Bootstrap con Sass en cada arranque (~1,5 s); en Connect Cloud, donde la app se apaga
# tras unos minutos sin visitas, eso se suma al arranque en frío. Acá se levanta la app de verdad y se
# pide la página: así se cachea exactamente lo que Shiny compila al servirla.
# Correr desde la raíz tras cambiar el tema o actualizar bslib/sass, y volver a desplegar.
unlink("sass-cache", recursive = TRUE); dir.create("sass-cache")
puerto <- 4598
cmd <- sprintf("shiny::runApp('.', port=%d, launch.browser=FALSE)", puerto)
pid <- system2("sh", c("-c", shQuote(sprintf("Rscript -e %s >/dev/null 2>&1 & echo $!", shQuote(cmd)))), stdout = TRUE)
ok <- FALSE
for (i in 1:60) { Sys.sleep(1)
  ok <- tryCatch({ readLines(url(sprintf("http://127.0.0.1:%d/", puerto)), warn = FALSE); TRUE }, error = function(e) FALSE)
  if (ok) break }
system2("kill", pid)
stopifnot(ok)
cat("sass-cache:", length(list.files("sass-cache", recursive = TRUE)), "archivos,",
    round(sum(file.size(list.files("sass-cache", full.names = TRUE, recursive = TRUE))) / 1e6, 2), "MB\n")

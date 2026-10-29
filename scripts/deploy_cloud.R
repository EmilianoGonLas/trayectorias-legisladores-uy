# Publica/actualiza la app en Posit Connect Cloud (cuenta emilianogonlas).
# Requiere rsconnect >= 1.11 y haber registrado las credenciales de API una vez:
#   rsconnect::connectCloudClientCredentials(clientId=, clientSecret=, accountName="emilianogonlas")
# NO guardar el clientSecret en el repo. Uso: Rscript scripts/deploy_cloud.R (desde la raíz)
#
# Si la app publicada carga pero sin datos o con errores, mirar PRIMERO los logs (connect.posit.cloud ->
# contenido -> Logs). La causa que tuvo acá fue un .rds con vectores de Arrow, no un ajuste de la plataforma:
# ver docs/BITACORA.md §8.
# La caché de estilos no se versiona: si falta, se genera (acelera el arranque en frío de la app).
if (!dir.exists("sass-cache")) source("scripts/precalentar_css.R", encoding = "UTF-8")

rsconnect::deployApp(
  appDir = ".", appPrimaryDoc = "app.R",
  appFiles = c("app.R", "global.R", "R", "www", "sass-cache", "data/app/datos.rds"),
  appName = "trayectorias-legisladores-uy", appTitle = "Trayectorias legislativas del Uruguay",
  account = "emilianogonlas", server = "connect.posit.cloud",
  forceUpdate = TRUE, launch.browser = FALSE)

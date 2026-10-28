# Publica/actualiza la app en Posit Connect Cloud (cuenta emilianogonlas).
# Requiere rsconnect >= 1.11 y haber registrado las credenciales de API una vez:
#   rsconnect::connectCloudClientCredentials(clientId=, clientSecret=, accountName="emilianogonlas")
# NO guardar el clientSecret en el repo. Uso: Rscript scripts/deploy_cloud.R (desde la raíz)
#
# Tras publicar por primera vez: Settings -> Runtime -> Idle timeout en 60 s (el valor por defecto, 5 s,
# mata el worker de R entre el HTML y el websocket y da 503). Ver BITACORA.
rsconnect::deployApp(
  appDir = ".", appPrimaryDoc = "app.R",
  appFiles = c("app.R", "global.R", "R", "www", "sass-cache", "data/app/datos.rds"),
  appName = "trayectorias-legisladores-uy", appTitle = "Trayectorias legislativas del Uruguay",
  account = "emilianogonlas", server = "connect.posit.cloud",
  forceUpdate = TRUE, launch.browser = FALSE)

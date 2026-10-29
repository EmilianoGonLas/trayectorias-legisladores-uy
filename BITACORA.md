# Bitácora — Trayectorias de legisladores uruguayos

Documento de trabajo. Se actualiza en cada sesión: qué se verificó, qué se decidió y por
qué, qué falta. La idea es que cualquier sesión pueda retomar sin releer todo.

- **Iniciado:** 2026-10-28
- **Estado:** descarga y parseo hechos (§5) · app Shiny hecha (§7) · análisis sin empezar
- **Repo:** https://github.com/EmilianoGonLas/trayectorias-legisladores-uy

---

## 1. La pregunta

Estudiar **trayectorias políticas** de quienes llegaron al Parlamento uruguayo:
secuencias de cargos, circulación entre partidos y sectores, carrera territorial,
pasaje por cargos oficiales antes y después, formación y origen.

Todavía no hay una hipótesis fija. Esta etapa es de infraestructura de datos: dejar la
fuente en tablas que se puedan unir y auditar. Las preguntas se eligen mirando las tablas.

## 2. La fuente

`https://biblioteca.parlamento.gub.uy:8008/biografias/busqueda` — Sistema de Consultas de
Biografías de Legisladores, Biblioteca del Poder Legislativo.

- **Listado:** `/busqueda?page=N`, 10 por página, 182 páginas = **1.816 legisladores**.
  Cada tarjeta trae nombre, nacimiento/defunción, lugar y los cargos legislativos.
- **Ficha:** `/legislador/<id>`. IDs de 2 a 2288. Secciones con `id` HTML estable:
  `datosPersonales`, `cargosLegislativos`, `actividadPolitica`, `titulos`, `estudiosCursados`,
  `actividadGremial`, `cargosOficiales`, `publicacionesS`, `premios`.
- La ficha tiene lo que la tarjeta no: circunscripción (departamento), sublema y lista de cada
  cargo; la línea de actividad política (texto libre); cargos oficiales; estudios; etc.
- Universo: **legisladores actuantes, titulares y suplentes**. Quedan afuera quienes fueron
  candidatos y nunca asumieron.

## 3. Trampas de la fuente (verificadas)

1. **El HTTP/2 del servidor está roto.** curl con h2 devuelve 200 con cuerpo vacío.
   `requests` usa HTTP/1.1 y anda; no migrar a un cliente h2 sin probar.
2. **ID inexistente → 302**, no 404 (redirige a la búsqueda). Se pide con `allow_redirects=False`.
3. **Algunos IDs dan 500 determinista** (muestreados: 2199, 2200, 2260, 2270, 2280, 2290).
   No es transitorio. El cliente reintenta una vez y lo registra como `error_500`.
4. **Fotos en base64 dentro del HTML** (hasta 600 KB por página). Se quitan al guardar:
   la regla es `data:image/webp; base64,…` **con un espacio** después del `;`, que un regex
   ingenuo no agarra. El listado pasa de ~620 KB a ~50 KB por página.
5. **La tarjeta del listado trae el bloque de cargos dos veces** (versión escritorio y móvil,
   `d-lg-block` / `d-lg-none`). Parsear ambos duplica cada cargo; se toma el primero.
6. **La negrita se parte entre líneas** en algunas secciones (`Militante<br></b>`), así que el
   parser saca las `<b>` del árbol antes de cortar por `<br>` en vez de usarlas como marcas.
7. **El cargo viene flexionado por género** (`DIPUTADA`/`DIPUTADO`). Se guarda `cargo_original`
   y un `cargo` normalizado a masculino genérico.
8. **El período viene como texto** («1967 - 1972», «2025», o vacío). Se guarda `periodo_raw`
   y se extraen `desde`/`hasta`; un año solo queda con `hasta` nulo. No se asume que
   «2025» significa «2025–2025» (es una decisión de análisis, no de parseo).
9. **Hay cargos sin partido** en la tarjeta (`( - Titular)`): huecos de la fuente, no del parser.
10. **Hay años imposibles.** Un premio de la ficha 2036 figura en «1006» (casi seguro 1906). Estiraba el eje de
    la línea de vida a ~900 años y rompía el cálculo de la escala. El parser lo registra como `anio_inverosimil`
    (fuera de 1750–2100) y la app deja esos registros fuera de la línea (siguen en las tablas, con aviso).
    Se encontró probando la lógica de la app contra las 1.816 personas, no a mano.

## 4. Decisiones de diseño

- **Python para bajar y parsear** (`requests` + `lxml`, ya instalados), **R para el parquet**
  (`arrow`, que Python no tiene acá). Los CSV intermedios se versionan: son diffeables.
- **Se guarda el HTML crudo** (sin fotos) y el parseo corre siempre sobre él. Si una regla de
  interpretación sale mal se corrige y se re-corre sin volver a pegarle al servidor.
- **Cada fila conserva `lineas_raw`** (el texto tal cual, separado por « ¦ »), además de los
  campos interpretados, para auditar cualquier decisión.
- **Todo lo que el parser no pudo interpretar va a `anomalias.csv`**, no se descarta ni se
  inventa. Las anomalías se revisan antes de analizar.
- **Cortesía con el servidor:** un pedido por segundo, secuencial, con caché y reintentos acotados.
  No hay `robots.txt` (404). User-Agent identifica el proyecto, sin datos personales.
- **Validación cruzada:** los cargos de la tarjeta del listado se comparan con los de la ficha.

## 5. Estado y resultados (sesión 1, 2026-10-28)

**Descarga completa.** 182 páginas de listado y 1.816 fichas, **todas con HTTP 200**, sin
una sola falla. HTML crudo sin fotos: 68 MB (`data/raw/`, no versionado). Tablas en
`data/processed/` (11 MB, CSV + parquet).

| tabla | filas | qué es |
|---|---:|---|
| `legisladores` | 1.816 | una fila por persona, datos personales y conteo de filas por sección |
| `cargos_legislativos` | 4.786 | cargo, titular/suplente, circunscripción, partido, sublema, lista |
| `actividad_politica` | 8.692 | línea de actividad (texto libre) con partido y sector separados |
| `cargos_oficiales` | 3.986 | cargos fuera del Parlamento |
| `estudios`, `titulos` | 6.966 · 1.242 | formación |
| `actividad_gremial`, `publicaciones`, `premios` | 4.158 · 4.422 · 1.136 | |
| `listado_cargos` | 4.786 | los cargos según la tarjeta del listado (sólo para validar) |
| `ids_estado` | 2.399 | resultado de cada ID sondeado, incluidos los que no tienen ficha |
| `anomalias` | 84 | lo que el parser no pudo interpretar |

**Validación.** Los cargos de las tarjetas del listado y los de las fichas **coinciden
exactamente**: 4.786 contra 4.786, sin una discrepancia. Se comprobó que el chequeo no es
vacío fabricando una alteración, que sí detecta. Circunscripción: 3.112 de 3.125 cargos de
diputado la traen (13 no). Los de senador no la traen en general (986), **salvo 223 que sí**: 214 son
de antes de 1940 y 9 posteriores. Probablemente refleja que el Senado se elegía por departamento
en esa etapa, pero eso es conocimiento previo, no verificado contra la fuente. Hay 20
circunscripciones, las mismas del formulario (incluida «MINAS (1837-1927)»). Los 9 senadores
posteriores a 1940 con circunscripción y los 13 diputados sin ella son para revisar a mano.

**El listado es todo el universo accesible.** Barrido de los IDs 2–2400 fuera del listado
(583): **ninguno** tiene ficha. 413 no existen (302) y **170 dan 500** determinista. De esos 170,
71 están en los 2200 y llegan hasta el 2297; el resto está disperso. Son registros que están en la
base y no se pueden mostrar. No sabemos quiénes son (ver §6).

**Anomalías (85):** 82 cargos de la tarjeta sin partido (`( - Titular)`; es la fuente, la ficha
dice lo mismo) y 2 lugares de nacimiento en el extranjero con comas dentro del nombre del país
(ids 1579 y 2087; el texto crudo está en `lugar_nacimiento_raw`) y 1 año inverosímil (id 2036, ver §3.10).

### Cobertura despareja por época (leer antes de comparar períodos)

Porcentaje de legisladores con al menos un dato, según el año de su primer cargo:

| primer cargo | n | fecha nac. | actividad política | cargos oficiales | publicaciones | premios |
|---|---:|---:|---:|---:|---:|---:|
| 1900–1919 | 97 | 68 % | 81 % | 88 % | 63 % | 40 % |
| 1920–1939 | 138 | 64 % | 70 % | 73 % | 49 % | 36 % |
| 1940–1959 | 71 | 99 % | 100 % | 83 % | 68 % | 61 % |
| 1960–1979 | 73 | 99 % | 99 % | 77 % | 52 % | 51 % |
| 1980–1999 | 215 | 98 % | 99 % | 78 % | 50 % | 35 % |
| 2000–2019 | 724 | 98 % | 98 % | 65 % | 17 % | 11 % |
| 2020–2039 | 432 | 97 % | 99 % | 58 % | 15 % | 17 % |

Dos patrones distintos y no hay que mezclarlos: la **fecha de nacimiento y la actividad política
tienen un hueco en 1900–1939** (~65–80 %) y están casi completas después; en cambio
**publicaciones, premios y cargos oficiales caen en las cohortes recientes**. Lo más probable es
que cada ficha refleje lo que la persona declaró o lo que se pudo reconstruir, pero eso es una
hipótesis, no un hecho verificado. Consecuencia: «los legisladores recientes publican menos» es
una lectura que los datos *no* permiten.

La columna `ultima_actualizacion` es texto con mayúsculas inconsistentes («febrero 2020» /
«Febrero 2020») y 81 fichas dicen «--». Sin normalizar todavía.

### Chequeo de completitud de la Legislatura 50 (no concluyente)

Con cargos desde 2025 hay 108 diputados y 35 senadores titulares distintos, contra 99 y 30
bancas. Estar por encima es lo esperable (reemplazos durante la legislatura), así que **no hay
evidencia de faltantes, pero este chequeo no puede probar que no los haya**.

## 6. Pendiente y preguntas abiertas

1. **Los 170 IDs con 500.** ¿Quiénes son? Si son legisladores recientes en carga, podrían faltar
   suplentes de la Legislatura 50. Para saberlo habría que cruzar con una lista oficial de
   integrantes. Reintentar de vez en cuando por si los arreglan.
2. **Significado de Titular/Suplente.** No está claro si un suplente que asume la banca figura como
   «Suplente» o «Titular» en la fuente. Hay que entenderlo antes de contar «titulares» por
   legislatura (108 diputados titulares distintos contra 99 bancas lo sugiere).
3. **`hasta` nulo.** Hay 8 cargos con un solo año (`2025`, no `2025 - 2025`). No se asumió nada;
   decidir en el análisis. Los 314 con «en actividad» tienen `en_actividad = TRUE`.
4. **Normalizar `ultima_actualizacion`** a fecha.
5. **Partido, sector y sublema** son texto libre con variantes (el partido sí está contra una
   lista cerrada de 25 lemas). Falta una tabla de equivalencias para seguir sectores en el tiempo;
   ahí podría servir `agy`, siempre con muestra verificada, después de ver cuántas variantes hay.
6. **Género.** No hay campo. El cargo viene flexionado (`DIPUTADA`) y `cargo_original` lo
   conserva, pero cubre sólo a quienes tuvieron cargo con flexión; no inferir por nombres.
7. **Personas repetidas.** No se comprobó si una misma persona figura con dos IDs.
8. **Geobloqueo.** No se probó este host desde fuera de Uruguay. Su host hermano
   `parlamento.gub.uy` sí bloquea. Si hace falta una versión web, el camino es publicar el
   parquet y no una app que scrapee en vivo.

## 7. La app (sesión 2, 2026-10-28)

Cinco pestañas: **Trayectoria** (línea de vida de una persona), **Legislaturas** (personas por lema en cada
legislatura), **Recorridos** (permanencia, cámaras, cambios de lema y de departamento), **Buscar en el texto** y
**Sobre los datos**. Código en `app.R`, `global.R`, `R/graficos.R`, `www/`; datos en `data/app/datos.rds`
(1,1 MB, armado por `scripts/05_datos_app.R`).

### Decisiones

- **Gráficos en HTML/CSS, sin plotly ni ggplot2.** Aprendido en compras-estatales: el arranque en frío de
  Connect Cloud es la restricción dura. Además los colores salen de variables CSS, así que claro/oscuro cambia
  sin volver a dibujar, y cada marca tiene su tooltip nativo.
- **Paleta validada, no elegida a ojo.** Las ocho ranuras de la guía dataviz se asignan por lema y quedan **fijas
  por entidad** (no por ranking): Nacional azul, Colorado rojo, Frente Amplio violeta, Cabildo Abierto naranja,
  Independiente aqua, Nuevo Espacio amarillo, Nacional Independiente magenta, Unión Cívica verde; el resto de los
  lemas va en gris («Otros lemas») y el vacío en gris más claro («Sin dato»). El primer orden probado
  (azul, rojo, violeta, naranja, aqua, **verde**, magenta, amarillo) **falló en oscuro** (aqua y verde adyacentes,
  ΔE 11,9 contra un piso de 15). Se enumeraron los órdenes posibles con los tres primeros fijos: de 120 sólo 4 pasan
  en ambos modos; se eligió el que tiene más margen (CVD 9,1 claro / 8,4 oscuro; visión normal 19,6 / 19,3).
  Tres tonos (aqua, magenta, amarillo) quedan bajo 3:1 de contraste en claro: el aviso obliga a mostrar etiquetas
  o tabla, y la app tiene leyenda, tooltip y tabla en cada vista.
- **Un color no significa dos cosas.** Los cargos fuera del Parlamento van en gris neutro, para que el azul de
  «Partido Nacional» no se confunda con un cargo oficial. Los gráficos de una sola serie van en tinta neutra, no
  en azul, por lo mismo.
- **La persona inicial es al azar** entre las de recorrido rico (≥ 3 legislaturas y ≥ 15 filas de texto, 306
  personas). Un ejemplo fijo habría sido una elección política en una herramienta académica. Cualquier persona se
  comparte con `?persona=<id>`.
- **Cargo mostrado vs. cargo normalizado.** Se muestra `cargo_original` (con tilde y con el género gramatical que
  trae la fuente: «Diputada»); `cargo` (masculino genérico) sólo agrupa y detecta la cámara.
- **Legislatura de cada cargo = la de mayor inicio ≤ año de inicio del cargo.** 0 cargos quedaron sin legislatura;
  80,6 % empiezan exactamente en el año de inicio de su legislatura y 9 caen en el último año de una (quedan en
  la siguiente). Es una convención, y la app lo dice.
- **La matriz de cambios de lema se reemplazó por un ranking.** Con 25 lemas la matriz era ilegible (filas vacías
  para lemas que sólo aparecen como destino); queda plegada, con filas = origen y columnas = destino.
- **El eje de legislaturas no es proporcional al tiempo** (50 columnas iguales); se rotula con el año de inicio y
  la app lo aclara debajo del gráfico.
- **Lo que no se hizo a propósito:** no hay mapa ni red, no se infiere género, no se clasifican los sectores de
  texto libre, y ninguna pantalla compara «épocas» como si la cobertura fuera pareja.

### Verificación

En el navegador (escritorio y 375 px de ancho, claro y oscuro): las cinco pestañas cargan sin errores de consola ni
del servidor; clic en una columna del gráfico cambia la legislatura (45 → 195 personas, coincide con el cálculo
directo); clic en una persona del listado abre su trayectoria y actualiza la URL; «otro al azar» cambia de persona;
los filtros Senado + Titular dan 33 personas en la legislatura 45; los casos límite (dos personas sin cargos
registrados, una con sólo un cargo y sin texto) muestran la nota o la fila correspondiente sin errores. Los conteos
de la pestaña Recorridos coinciden con los calculados aparte (895 personas con una sola legislatura; 353 de 406
empezaron por Diputados; 76 personas con más de un lema; 125 diputados en más de un departamento).

**No verificado:** un teléfono real (sólo emulación), lectores de pantalla, y el comportamiento tras publicar (ver
más abajo).

### Primeras lecturas (descriptivas, con las cautelas de arriba)

76 personas figuran con más de un lema, con 100 cambios entre cargos consecutivos. Los más frecuentes: Partido
Nacional Independiente → Partido Nacional (9), Colorado → Frente Amplio (8), Nuevo Espacio → Frente Amplio (7),
Nacional → Nacional Independiente (7). De las 406 personas con cargo en las dos cámaras, 353 (86,9 %) empezaron
por Diputados. **No son hallazgos**: describen a quienes llegaron a una banca, con lemas tal como figuran en cada
cargo, y no dicen nada de afiliaciones, candidaturas ni sectores.

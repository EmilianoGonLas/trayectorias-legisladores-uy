# Diccionario de datos

Todas las tablas están en [`processed/`](processed), en **CSV** (UTF-8, vacío = dato ausente) y **parquet** (tipado).
Salen de las 1.816 biografías de la Biblioteca del Poder Legislativo; el origen, las trampas de la fuente y lo que
las cifras no permiten afirmar están en [`../docs/BITACORA.md`](../docs/BITACORA.md).

**Clave de unión:** `id`, el identificador de la persona en la fuente (`/legislador/<id>`). Todas las tablas de
filas por persona lo traen.

## Convenciones

- **Texto crudo.** Los textos conservan las mayúsculas y la ortografía de la fuente (los nombres y los lemas vienen en
  mayúsculas). `lineas_raw` es el texto de la fila tal como salió de la página, con ` ¦ ` entre líneas; sirve para
  auditar cualquier interpretación.
- **Períodos.** `periodo_raw` es lo que dice la fuente («1967 - 1972», «2025», vacío). De ahí salen `desde` y `hasta`.
  Un año solo queda con `hasta` **vacío** (no se asume que «2025» es «2025–2025»). «2025 - en actividad» marca
  `en_actividad = TRUE` y deja `hasta` vacío.
- **`orden`.** Posición de la fila dentro de su sección en la ficha original. La fuente las lista de la más reciente
  a la más antigua (siempre en los cargos legislativos; en general en las demás secciones).
- **Los cargos no están asignados a una legislatura**: eso lo hace la app, con una convención (la legislatura que
  empieza en el año de inicio del cargo). La tabla `legislaturas` permite replicarla.

## Tablas

### `legisladores` — una fila por persona (1.816)

| Columna | Tipo | Qué es |
|---|---|---|
| `id` | entero | Identificador en la fuente. |
| `nombre_listado` | texto | «APELLIDOS, NOMBRES», como en el listado. |
| `nombre_ficha` | texto | «NOMBRES APELLIDOS», como en el encabezado de la ficha. |
| `nacimiento_raw`, `defuncion_raw` | texto | Fecha tal como figura (dd/mm/aaaa). |
| `nacimiento_iso`, `defuncion_iso` | fecha | La misma fecha interpretada; vacía si no se pudo. |
| `lugar_nacimiento_raw` | texto | Lugar de nacimiento tal como figura. |
| `nac_ciudad`, `nac_subdivision`, `nac_pais` | texto | El lugar separado. `nac_subdivision` es el departamento sólo si nació en Uruguay (si no, provincia o estado). Pueden venir vacíos según el formato del lugar (ver `anomalias`). |
| `ultima_actualizacion` | texto | «Abril 2024», etc.; mayúsculas inconsistentes y «--» si se desconoce. Sin normalizar. |
| `pagina_listado` | entero | Página del listado donde aparece. |
| `en_listado` | lógico | Si figura en el listado de la fuente (todas las filas, por construcción). |
| `estado_ficha`, `bytes_ficha` | texto, entero | Resultado de la descarga (`ok`) y tamaño del HTML guardado. |
| `n_cargos_legislativos`, `n_actividad_politica`, `n_titulos`, `n_estudios`, `n_actividad_gremial`, `n_cargos_oficiales`, `n_publicaciones`, `n_premios` | entero | Cuántas filas tiene la persona en cada tabla de sección. |

### `cargos_legislativos` — un cargo parlamentario por fila (4.786)

| Columna | Tipo | Qué es |
|---|---|---|
| `id`, `orden`, `periodo_raw`, `desde`, `hasta`, `en_actividad`, `lineas_raw` | | Ver convenciones. |
| `cargo_original` | texto | Cargo tal como lo escribe la fuente, con tilde y con género gramatical («DIPUTADA»). |
| `cargo` | texto | Cargo normalizado: masculino genérico, mayúsculas, sin tildes («DIPUTADO», «VICEPRESIDENTE DE LA CAMARA DE SENADORES»). Sirve para agrupar. |
| `condicion` | texto | `Titular` o `Suplente`, tal como lo registra la fuente (no dice si el suplente llegó a ocupar la banca). |
| `circunscripcion` | texto | Departamento por el que fue elegido. Lo traen casi todos los diputados (3.112 de 3.125) y, hasta la década de 1920, la gran mayoría de los senadores (57–92 % por década); en los años treinta baja a 19 % y después casi desaparece. |
| `partido` | texto | Lema. Vacío en 82 cargos: es un hueco de la fuente. |
| `sublema`, `lista` | texto | Sublema y lista(s) tal como figuran; `lista` puede traer varias («11, 215, 315 Y 715»). |

### `actividad_politica` — línea de actividad política, texto libre (8.692)

`id`, `orden`, `periodo_raw`, `desde`, `hasta`, `en_actividad`, `lineas_raw` (ver convenciones) y:

| Columna | Tipo | Qué es |
|---|---|---|
| `descripcion` | texto | Descripción de la actividad (varias líneas unidas con ` ¦ `). |
| `partido` | texto | Lema al que se asocia la actividad, si la última línea es un lema reconocido. |
| `sector` | texto | Sector dentro del lema («Asamblea Uruguay», «Batllismo»…), texto libre sin normalizar. |

### Secciones con la misma forma

`cargos_oficiales` (3.986, cargos fuera del Parlamento), `estudios` (6.966), `titulos` (1.242, títulos universitarios o
equivalentes), `actividad_gremial` (4.158), `publicaciones` (4.422) y `premios` (1.136) comparten estas columnas:
`id`, `orden`, `periodo_raw`, `desde`, `hasta`, `en_actividad`, `lineas_raw` (ver convenciones) y

| Columna | Tipo | Qué es |
|---|---|---|
| `destacado` | texto | La línea en negrita de la ficha: el cargo, el estudio, el título o el premio. |
| `detalle` | texto | El resto de las líneas (institución, país, aclaraciones), unidas con ` ¦ `. |

### Catálogos

| Tabla | Columnas | Qué es |
|---|---|---|
| `legislaturas` (50) | `numero`, `desde`, `hasta` | Años de cada legislatura, del formulario de la fuente. Hay huecos, entre ellos 1846–1852 y 1973–1985. |
| `lemas` (25) | `id_fuente`, `nombre` | Los lemas del formulario de búsqueda. Varios nombres vienen sin tildes. |

### Control de calidad

| Tabla | Columnas | Qué es |
|---|---|---|
| `listado_cargos` (4.786) | `id`, `orden`, `periodo_raw`, `desde`, `hasta`, `en_actividad`, `cargo`, `cargo_norm`, `partido`, `condicion` | Los cargos tal como los muestra la tarjeta del listado. Se usa sólo para validar: coinciden uno a uno con `cargos_legislativos`. |
| `ids_estado` (2.399) | `id`, `estado`, `en_listado`, `http`, `bytes` | Resultado de cada identificador sondeado (2 a 2400): `ok` (1.816), `inexistente` (413) o `error_500` (170, registros que existen en la base pero la fuente no puede mostrar). |
| `anomalias` (85) | `id`, `tabla`, `tipo`, `detalle` | Lo que el parseo no pudo interpretar: `tarjeta_sin_partido` (82), `lugar_no_parseable` (2, nacidos en el extranjero con comas dentro del nombre del país) y `anio_inverosimil` (1, un premio fechado en «1006»). |

## Cautelas

- **La cobertura cambia con la época**: por ejemplo, la fecha de nacimiento está en ~65 % de quienes ingresaron entre
  1900 y 1939 y en ~98 % después. La tabla completa está en la app y en la bitácora.
- Sólo figuran quienes **ocuparon** una banca; no hay candidatos que no asumieron.
- Las fichas incluyen fechas y lugares de nacimiento de legisladores vivos, tal como los publica la Biblioteca.

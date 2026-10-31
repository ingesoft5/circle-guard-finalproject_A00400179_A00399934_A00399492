# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y una
comparación directa confirmó que ningún secreto generado aparece en los archivos versionables ni
en los logs.

**Estado general: HU-01 NO está terminada.** El código y la validación local están completos;
falta la ejecución en AWS (C1, C2 y la reconstrucción desde cero), que requiere autorización de
costos, y la decisión del equipo sobre el EULA de Nexus.

## Matriz final: seis criterios

| Criterio | Estado | Qué está hecho | Qué falta |
|---|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y Nexus | **Falta (AWS)** | `bootstrap-servers.sh` (EC2 cifradas, IMDSv2, créditos `standard`) y los tres stacks automatizados. Jenkins y SonarQube validados en local de punta a punta | Crear las instancias (facturable) y ejecutar los *bootstrap*. Nexus, pendiente del EULA |
| C2 · dev, stage y prod aislados | **Falta (AWS)** | Subred, grupo de seguridad, llave SSH y ruta SSM propias por ambiente; ninguna regla entre ambientes; `verify-infra.sh --isolation` listo | Ejecutarlo en AWS y capturar la prueba de aislamiento |
| C3 · `infra/bootstrap-*.sh` idempotentes | **Parcial** | Demostrado en local (2.ª ejecución con `created=0 updated=0`: secretos, Jenkins y SonarQube, más la corrección de derivas). Revisión estática de todos los scripts y 6 defectos corregidos ([08](08-revision-idempotencia.md)) | Dos ejecuciones de `bootstrap-all.sh` en AWS con *snapshot* y `diff` vacío |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **Terminado** | `${VAR:?}` sin valores por defecto, `.env.example` vacío y credenciales en `~/.circleguard/dev.env`; incluido en el commit `3a43855` | — |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **Parcial** | Jenkins (JCasC) y SonarQube (API) sin pasos manuales; acceso administrativo por túnel documentado; prerrequisitos documentados en `infra/README.md` | Nexus (decisión del EULA) y la reconstrucción en AWS siguiendo solo la documentación |
| C6 · Credenciales fuera del repositorio, con un mecanismo seguro | **Terminado en el repositorio**; SSM pendiente de ejecución | 0 secretos activos ([03](03-gitleaks-arbol-de-trabajo.txt)); los 7 `application.yml` funcionan con variables y fallan sin ellas ([07](07-verificacion-arranque-servicios.txt)); SSM y `.env` 0600 implementados | Crear los parámetros SSM en AWS (sin costo; requiere autorización) |

## Matriz final: cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **Parcial**: ejecuciones locales completas (`local/`); **falta la salida en AWS** | [`local/`](local/), [`08-revision-idempotencia.md`](08-revision-idempotencia.md) |
| 2. Diagrama de ambientes | **Terminado**. Actualizado con el acceso por túnel; este cambio aún no tiene commit | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| 3. Commit que elimina las credenciales | **Terminado**: `3a43855` (rama `HU01_Infraestructura_nube_bash`, publicada en `origin`). Sin reescribir el historial | `git show --stat 3a43855` |
| 4. Captura del escaneo de secretos | **Terminado**: árbol de trabajo en PASS e historial completo. Falta solo la captura de pantalla, que hará el equipo | [`03`](03-gitleaks-arbol-de-trabajo.txt), [`04`](04-gitleaks-historial.txt) |

## Clasificación de los hallazgos de Gitleaks

| Categoría | Árbol de trabajo | Historial (`6f254ed`) | Definición |
|---|---|---|---|
| **ACTIVO** | **0** | — | Secreto real en un archivo que se versionaría. Debe ser 0 |
| **HISTÓRICO** | — | **51** | Credencial publicada en el commit inicial. Se considera **comprometida**, no se reutiliza en ningún ambiente y no se reescribe el historial |
| **PRUEBA** | 9 | 9 | Valor ficticio en `src/test` (*fixtures* de H2, JWT y bóveda de los tests) |
| **RESIDUAL** | 2 | 4 | Contraseña de prueba en los comentarios de las migraciones V2/V3, que son inmutables por la decisión X-2 (E2.6) |

**Desglose de los 51 históricos:**

| Origen | Hallazgos | Archivos y líneas |
|---|---|---|
| Configuración principal (`src/main/resources/application.yml`) | 19 | auth 7,19,22,26 · identity 10,20,20,21,22,25 · promotion 7,19,38 · gateway 10,14 · notification 26,30 · dashboard 7 · form 7 |
| Copias del IDE de esa configuración (`bin/main/application.yml`, retiradas del índice) | 19 | Mismas líneas que la fila anterior |
| `docker-compose.dev.yml` | 3 | 9, 24, 68 |
| `.agent/workflows/run-project.md` | 1 | 45 |
| `scratch/run_seed.py` | 1 | 7 |
| Copias del IDE de los *fixtures* (`bin/test/*.yml`) | 8 | auth 2,12 · identity 11,18,18,19,20 · promotion 14 |

**Observación sobre los fixtures:** el *fixture* de la bóveda en
`identity-service/src/test/resources/application.yml` (líneas 18-20) tiene **los mismos valores** que
la antigua configuración principal. Hoy es solo un dato de prueba, ningún ambiente lo usa y las
claves nuevas son distintas. Sustituirlo por valores ficticios nuevos queda como propuesta,
pendiente de decisión del equipo, porque afecta a los tests de identity.

## Archivos

| Archivo | Contenido |
|---|---|
| `01-validacion-estatica.txt` | `bash -n` (19/19), ShellCheck v0.11.0 sin hallazgos, validez de JSON y YAML |
| `02-validacion-compose.txt` | Los 4 Compose fallan sin variables y son válidos con valores; imágenes fijadas, puertos, volúmenes y *healthchecks* |
| `03-gitleaks-arbol-de-trabajo.txt` | 0 ACTIVO · 9 PRUEBA · 2 RESIDUAL |
| `04-gitleaks-historial.txt` | 64 hallazgos: 51 HISTÓRICO, 9 PRUEBA y 4 RESIDUAL |
| `05-tests-linea-base-vs-hu01.txt` | 48 tests antes y después de X-1: idénticos, sin regresiones. **Los 10 fallos previos se conservan como línea base** (E1.6) |
| `06-iam-minimo-privilegio.txt` | Contraste estático: 0 acciones sin permiso, 0 permisos sin uso, ninguna acción destructiva en la política del operador |
| `07-verificacion-arranque-servicios.txt` | Los 8 servicios arrancados con y sin variables: no hay valores por defecto inseguros |
| `08-revision-idempotencia.md` | Revisión de todos los scripts, estado de cada demostración y defectos corregidos |
| `local/*.log` | Ejecuciones locales (`--target local`) en Docker Desktop. La ruta del usuario aparece como `~` |

## Artefactos locales fuera del repositorio (no se borran sin autorización)

| Artefacto | Contenido | Sensibilidad | Protección actual |
|---|---|---|---|
| Volumen `circleguard-jenkins_jenkins_home` (119 MB) | Configuración de Jenkins, plugins, `users/` (hash del admin local), `secrets/master.key` | Media: credenciales **locales** de prueba | Docker, solo en esta máquina |
| Volúmenes `circleguard-sonarqube_*` (155 + 348 MB + logs) | BD PostgreSQL de SonarQube (hash del admin local) e índices | Media | Igual |
| Volumen `circleguard-nexus_nexus-data` (5 MB) | BD de Nexus (hash del admin local), almacenes de llaves | Media | Igual |
| `~/.cache/circleguard-hu01/baseline` (WSL, 15 MB) | Exportación de `6f254ed` y su *build*: **18 archivos con las claves antiguas** (JWT, QR y bóveda) | **Alta**: credenciales comprometidas | Permisos 700, fuera de OneDrive |
| `~/.cache/circleguard-hu01/after` (447 MB) | Copia del árbol HU-01 y sus JAR; 2 archivos con el *fixture* que coincide con la clave antigua | Media | Permisos 700 |
| `~/.cache/circleguard-hu01/{jdk,gradle-8.14,gradle-home,dl,runtime-logs}` | JDK, Gradle, caché de dependencias, descargas y logs de arranque (sin secretos) | Baja | 700 en la raíz |

**Propuesta de eliminación segura** (cuando HU-01 esté cerrada y el equipo lo autorice):
1. Primero, `baseline` y `after`, que son las copias con valores sensibles:
   `find ~/.cache/circleguard-hu01/{baseline,after} -type f -exec shred -u {} +` y después `rm -rf`
   de los directorios.
2. **Limitación:** en ext4 con *journaling* y discos SSD, `shred` no garantiza borrar los bloques.
   El riesgo residual es aceptable porque esos valores ya son públicos en el historial y se
   consideran revocados.
3. Los volúmenes Docker de prueba se borrarían con
   `docker volume rm circleguard-jenkins_jenkins_home …`, siempre de forma explícita y nombrándolos.
   Nunca con `prune`.

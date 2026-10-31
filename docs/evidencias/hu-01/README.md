# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y se
comprobó por comparación directa que ningún secreto generado aparece en los archivos
versionables ni en los logs.

## Estado de las cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **Parcial**. Validación **local** completa de Jenkins y SonarQube (1.ª y 2.ª ejecución sin cambios). Nexus validado hasta el EULA (pendiente de decisión). **Falta la ejecución en AWS**, que necesita autorización de costos | [`local/`](local/) |
| 2. Diagrama de ambientes | Completa | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| 3. Commit que elimina las credenciales | **Preparado, sin commit** (pendiente de la autorización del equipo) | `git diff` del árbol de trabajo |
| 4. Captura del escaneo de secretos | Completa: árbol de trabajo **sin secretos activos** (PASS); historial reportado sin ocultar nada | [`03-gitleaks-arbol-de-trabajo.txt`](03-gitleaks-arbol-de-trabajo.txt), [`04-gitleaks-historial.txt`](04-gitleaks-historial.txt) |

## Archivos

| Archivo | Contenido |
|---|---|
| `01-validacion-estatica.txt` | `bash -n` (18/18), ShellCheck v0.11.0 sin hallazgos, validez de JSON y YAML (incluidos los `application.yml` externalizados) |
| `02-validacion-compose.txt` | Los 4 Compose: fallan sin variables, también con `.env.example` sin completar, y son válidos con valores; imágenes fijadas, puertos, volúmenes y *healthchecks* |
| `03-gitleaks-arbol-de-trabajo.txt` | 0 ACTIVO · 9 PRUEBA (valores ficticios en `src/test`) · 2 RESIDUAL (comentarios de V2/V3, decisión X-2) |
| `04-gitleaks-historial.txt` | 64 hallazgos en el commit `6f254ed`: 51 HISTÓRICO (credenciales expuestas, consideradas comprometidas), 9 PRUEBA y 4 RESIDUAL |
| `05-tests-linea-base-vs-hu01.txt` | 48 tests antes y después de externalizar los `application.yml`: resultados idénticos y sin regresiones; causas de los 10 fallos previos |
| `local/bootstrap-*.log`, `local/verify-infra-*.log`, `local/teardown-stop-*.log` | Ejecuciones locales (`--target local`) en Docker Desktop. La ruta del usuario aparece como `~` |

## Ejecuciones locales destacadas

| Log | Resultado |
|---|---|
| `bootstrap-secrets-…050650Z` | Plan (4 pendientes), aplicación (`created=4`) y 2.ª ejecución (`unchanged=4`) |
| `bootstrap-jenkins-…050822Z` | 1.ª ejecución: imagen con JCasC construida, sin asistente, administrador gestionado, anónimo con 403 (`created=6`) |
| `bootstrap-jenkins-…051052Z` / `…051058Z` | 2.ª y 3.ª ejecución: `created=0 updated=0` y el mismo contenedor (mismo ID y fecha de creación) |
| `bootstrap-sonarqube-…051444Z` | 1.ª ejecución: PostgreSQL y SonarQube desplegados; contraseña de fábrica reemplazada por API (`updated=1`) |
| `bootstrap-sonarqube-…051857Z` / `…052034Z` | Cambio en el Compose (*healthcheck*) aplicado y luego `created=0 updated=0` |
| `bootstrap-nexus-…052249Z` / `…052559Z` | Contraseña inicial reemplazada; **se detiene en el EULA** de Community Edition hasta que el equipo decida |
| `verify-infra-…052043Z` | SonarQube: estado UP, contenedor y BD saludables, anónimo 401 |
| `teardown-stop-…052603Z` | Stacks detenidos y volúmenes conservados; los que ya estaban detenidos se informan como `UNCHANGED` |

**Hallazgos de la validación local que se corrigieron:**
- `--build` en cada ejecución recreaba Jenkins, porque BuildKit genera un digest nuevo en cada *build*.
- En modo plan, la configuración intentaba ejecutarse sobre un host sin desplegar.
- `teardown.sh` usaba la configuración antes de cargarla.
- Un falso positivo de la regla propia de Gitleaks con la interpolación `${VAR:?}`.

## Criterios de aceptación

| Criterio | Estado | Evidencia y pendiente |
|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y Nexus | **Pendiente (AWS)** | Scripts y stacks listos y validados en local. Falta crear las instancias (operación facturable) |
| C2 · dev, stage y prod aislados | **Pendiente (AWS)** | Red, grupos de seguridad, llaves y secretos por ambiente implementados; `verify-infra.sh --isolation` listo. Falta ejecutarlo en AWS |
| C3 · `infra/bootstrap-*.sh` idempotentes | **Demostrado en local**; pendiente en AWS | 2.ª ejecución con `created=0 updated=0` (secretos, Jenkins, SonarQube) |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **Cumplido** (pendiente del commit) | `02-validacion-compose.txt`, `03-gitleaks-arbol-de-trabajo.txt` |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **Parcial** | Jenkins (JCasC) y SonarQube (API) automatizados; Nexus bloqueado por la decisión del EULA. Falta la reconstrucción en AWS |
| C6 · Credenciales fuera del repositorio con un mecanismo seguro | **Cumplido en el repositorio** | 0 secretos activos; SSM y `.env` 0600 implementados. Riesgo residual V2/V3 documentado |

## Cómo regenerar

```bash
bash infra/scan-secrets.sh                                  # evidencias 3 y 4
bash infra/bootstrap-<herramienta>.sh --target local --apply  # salida local del bootstrap
bash infra/bootstrap-all.sh --apply --approve all           # evidencia 1 en AWS (FACTURABLE: requiere autorización)
```

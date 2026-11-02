# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y una
comparación directa confirmó que ningún secreto generado aparece en los archivos versionables ni
en los logs.

**Estado general: HU-01 NO está terminada.** El código, la validación local y la preparación de
AWS están completos. Falta la ejecución en AWS (C1, C2 y la reconstrucción desde cero), que
requiere autorizaciones individuales, y la decisión del equipo sobre el EULA de Nexus.

**Preparación de AWS (2026-11-01, solo lectura, [09](09-aws-preparacion-cuenta-e-iam.txt)):**
- Cuenta independiente en el **plan gratuito**: 100 USD de créditos; el plan termina el 2027-04-30.
- Tipos del plan gratuito (8 GiB como máximo), ofrecidos en us-east-2a y compatibles con la AMI.
  **Topología B aprobada el 2026-11-02** ([12](12-preparacion-arquitectura-b.txt)): dos
  `m7i-flex.large`, `ci` (Jenkins, SonarQube y PostgreSQL) y `nexus`; los ambientes no tienen
  servidores en HU-01 (aislamiento por red, configurado y sin verificar con tráfico).
- Plantillas IAM: Access Analyzer sin hallazgos en las 8, y el simulador IAM sin escalada posible.
- Cuota de vCPU de 5: la topología B necesita 4, sin aumento.
- La cuenta raíz ya tiene MFA (activada por el equipo el 2026-11-01).
- **IAM creado el 2026-11-01 con autorización:** 3 políticas, 2 usuarios sin claves y 3 roles; convergencia comprobada en una segunda ejecución ([10](10-iam-creacion-e-idempotencia.txt)). Ningún recurso EC2, red o almacenamiento.

## Matriz final: seis criterios

| Criterio | Estado | Qué está hecho | Qué falta |
|---|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y Nexus | **Falta (AWS)** | `bootstrap-servers.sh` (EC2 cifradas, IMDSv2) y los tres stacks automatizados. Jenkins y SonarQube validados en local de punta a punta. Tipos aptos para el plan gratuito verificados en la cuenta ([09](09-aws-preparacion-cuenta-e-iam.txt)) | Crear `ci` y `nexus` (facturable) y ejecutar los *bootstrap*. Nexus quedará desplegado con el EULA pendiente |
| C2 · dev, stage y prod aislados | **Falta (AWS)** | Subred, grupo de seguridad, llave SSH y ruta SSM propias por ambiente; ninguna regla entre ambientes; `verify-infra.sh --health` comprueba esa configuración | Crear la red en AWS y capturar la verificación. Sin servidores de ambiente (topología B), el aislamiento queda **configurado, no verificado con tráfico** |
| C3 · `infra/bootstrap-*.sh` idempotentes | **Parcial** | Demostrado en local (2.ª ejecución con `created=0 updated=0`: secretos, Jenkins y SonarQube, más la corrección de derivas). Revisión estática de todos los scripts y 6 defectos corregidos ([08](08-revision-idempotencia.md)) | Dos ejecuciones de `bootstrap-all.sh` en AWS con *snapshot* y `diff` vacío |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **Terminado** | `${VAR:?}` sin valores por defecto, `.env.example` vacío y credenciales en `~/.circleguard/dev.env`; incluido en el commit `3a43855` | — |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **Parcial** | Jenkins (JCasC) y SonarQube (API) sin pasos manuales; acceso administrativo por túnel; IAM, sesiones temporales, cuota y destrucción en CloudShell automatizados y documentados en `infra/README.md`. Los únicos pasos manuales son los que deben serlo (contraseñas y MFA en la consola de AWS), y están documentados | Nexus (decisión del EULA) y la reconstrucción en AWS siguiendo solo la documentación |
| C6 · Credenciales fuera del repositorio, con un mecanismo seguro | **Terminado en el repositorio**; SSM pendiente de ejecución | 0 secretos activos ([03](03-gitleaks-arbol-de-trabajo.txt)); los 7 `application.yml` funcionan con variables y fallan sin ellas ([07](07-verificacion-arranque-servicios.txt)); SSM y `.env` 0600 implementados; acceso a AWS sin claves permanentes (sesiones temporales y roles separados, [06](06-iam-minimo-privilegio.txt), [09](09-aws-preparacion-cuenta-e-iam.txt)) | Crear los parámetros SSM en AWS (sin costo; requiere autorización) |

## Matriz final: cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **Parcial**: ejecuciones locales completas (`local/`); **falta la salida en AWS** | [`local/`](local/), [`08-revision-idempotencia.md`](08-revision-idempotencia.md) |
| 2. Diagrama de ambientes | **Terminado** para la topología B: red, aislamiento (configurado frente a verificado), servidores `ci` y `nexus`, memoria prevista e identidades y autorización | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
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

**Observación sobre los fixtures (resuelta, D-4):** el *fixture* de la bóveda en
`identity-service/src/test/resources/application.yml` (líneas 18-20) tenía los mismos valores que
la antigua configuración principal. Se sustituyó por valores ficticios en el commit `67af77d`.
Los tests de identity mantienen sus 4 fallos previos, sin regresiones. Los hallazgos PRUEBA de
esas líneas corresponden ya a los valores ficticios.

## Archivos

| Archivo | Contenido |
|---|---|
| `01-validacion-estatica.txt` | `bash -n` (19/19), ShellCheck v0.11.0 sin hallazgos, validez de JSON y YAML (corte del 2026-10-31; los 26 scripts actuales también pasaron ShellCheck el 2026-11-01, y se regenerará al cierre) |
| `02-validacion-compose.txt` | Los 4 Compose fallan sin variables y son válidos con valores; imágenes fijadas, puertos, volúmenes y *healthchecks* |
| `03-gitleaks-arbol-de-trabajo.txt` | 0 ACTIVO · 9 PRUEBA · 2 RESIDUAL |
| `04-gitleaks-historial.txt` | 64 hallazgos: 51 HISTÓRICO, 9 PRUEBA y 4 RESIDUAL |
| `05-tests-linea-base-vs-hu01.txt` | 48 tests antes y después de X-1: idénticos, sin regresiones. **Los 10 fallos previos se conservan como línea base** (E1.6) |
| `06-iam-minimo-privilegio.txt` | Contraste estático de los roles de lectura, operación y teardown: 0 acciones sin permiso, 0 permisos sin uso, ninguna acción destructiva en la política del operador, usuarios sin permisos sobre recursos |
| `07-verificacion-arranque-servicios.txt` | Los 8 servicios arrancados con y sin variables: no hay valores por defecto inseguros |
| `08-revision-idempotencia.md` | Revisión de todos los scripts, estado de cada demostración y defectos corregidos |
| `10-iam-creacion-e-idempotencia.txt` | Creación autorizada de los 8 recursos IAM, segunda y tercera ejecución (dos defectos del informe corregidos, convergencia `created=0 updated=0`), verificación directa y auditoría CloudTrail (14 escrituras, solo IAM) |
| `11-validacion-identidades.txt` | Validación de las identidades: inicio de sesión del operador (y sus fallos corregidos), 13/13 pruebas de lectura, operación y denegación de teardown, revocación de credenciales expuestas, ausencia de claves permanentes, dependencia de la MFA y teardown en CloudShell (revisión, simulación, dos intentos fallidos, corrección de las peticiones repetidas de MFA y plan verificado en CloudShell con un solo código MFA) |
| `12-preparacion-arquitectura-b.txt` | Fase 2: topología B (servidores `ci` y `nexus`), aclaración de los requisitos de Nexus, EULA pendiente, parada automática, costos, IAM v1/v2 y validaciones locales |
| `09-aws-preparacion-cuenta-e-iam.txt` | Inspección de solo lectura de la cuenta, elegibilidad de tipos, Access Analyzer, simulador IAM de escalada, plan IAM, cuota, auditoría CloudTrail, incidente de la caché raíz y barreras locales de autorización |
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

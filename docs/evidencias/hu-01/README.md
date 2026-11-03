# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y una
comparación directa confirmó que ningún secreto generado aparece en los archivos versionables ni
en los logs. Las copias de los registros de AWS de [`fase4/`](fase4/) están además enmascaradas
(número de cuenta, identificadores de IAM y último octeto de IP públicas).

**Estado general: HU-01 NO está terminada.** El 2026-11-02 se desplegó y validó en AWS
([evidencia 14](14-despliegue-aws-fase4.md)): red, IAM, 35 secretos en SSM, `ci` con Jenkins,
SonarQube y PostgreSQL (PASS) y `nexus` con Nexus desplegado y el EULA **pendiente**; después se
detuvieron las dos instancias, conservando sus volúmenes. Falta la prueba de idempotencia completa
en AWS (C3, [procedimiento 15](15-procedimiento-idempotencia-aws.md), requiere arrancar las
instancias), la decisión del equipo sobre el EULA ([16](16-nexus-eula.md)) y la reconstrucción desde
cero siguiendo solo la documentación.

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

Clasificación usada en todas las evidencias de HU-01: **PASS** (cumplido y comprobado), **PARTIAL**
(hecho en parte; se indica lo que falta), **FAIL** (comprobado y no cumple) y **NOT VERIFIED** (sin
comprobar). Estado de la historia: **PARCIALMENTE COMPLETADA**.

| Criterio | Estado | Qué está hecho | Qué falta |
|---|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y Nexus | **PARTIAL** | En AWS el 2026-11-02 ([14](14-despliegue-aws-fase4.md)): `ci` y `nexus` (m7i-flex.large, AMI fijada, IMDSv2, gp3 cifrado) creados por script; Jenkins, SonarQube y PostgreSQL **PASS** (`verify-infra.sh` 22/0/1 y 53/0/5); Nexus desplegado, en línea y con la contraseña gestionada | Nexus sin función de repositorio hasta la decisión del EULA ([16](16-nexus-eula.md)) |
| C2 · dev, stage y prod aislados | **PARTIAL** | En AWS: subred y grupo de seguridad propios por ambiente, ninguna regla entre ambientes y solo referencias a `ci` y `nexus` (15 comprobaciones PASS); con tráfico real, `ci → nexus:8081` permitido y `nexus → ci:8080/9000` bloqueados ([14](14-despliegue-aws-fase4.md) §8) | Sin servidores de ambiente (topología B), el aislamiento está **configurado y verificado por reglas, no con tráfico entre ambientes**. El equipo debe decidir si eso basta para HU-01 (recomendado) o si se prueba en la historia que despliegue esos servidores; C2 no se cierra sin esa aceptación |
| C3 · `infra/bootstrap-*.sh` idempotentes | **PARTIAL** | Demostrado en local (2.ª ejecución con `created=0 updated=0`: secretos, Jenkins y SonarQube, más la corrección de derivas). Revisión estática de todos los scripts y 6 defectos corregidos ([08](08-revision-idempotencia.md)). En AWS: red `unchanged=28` y secretos `unchanged=43` en la 2.ª ejecución, e IAM convergente ([14](14-despliegue-aws-fase4.md)) | Dos ejecuciones de `bootstrap-all.sh` en AWS con *snapshot* y `diff` vacío: procedimiento listo en la [evidencia 15](15-procedimiento-idempotencia-aws.md), pendiente de autorización (arranca las instancias) |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **PASS** | `${VAR:?}` sin valores por defecto, `.env.example` vacío y credenciales en `~/.circleguard/dev.env`; incluido en el commit `3a43855` | — |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **PARTIAL** | Jenkins (JCasC) y SonarQube (API) sin pasos manuales; acceso administrativo por túnel; IAM, sesiones temporales, cuota y destrucción en CloudShell automatizados y documentados en `infra/README.md`. Los únicos pasos manuales son los que deben serlo (contraseñas y MFA en la consola de AWS), y están documentados | Nexus (decisión del EULA) y la reconstrucción en AWS siguiendo solo la documentación. La instalación del 2026-11-02 se hizo solo con los scripts ([14](14-despliegue-aws-fase4.md)) |
| C6 · Credenciales fuera del repositorio, con un mecanismo seguro | **PASS** | 0 secretos activos ([03](03-gitleaks-arbol-de-trabajo.txt); repetido el 2026-11-02 en [`fase4/`](fase4/)); los 7 `application.yml` funcionan con variables y fallan sin ellas ([07](07-verificacion-arranque-servicios.txt)); acceso a AWS sin claves permanentes ([06](06-iam-minimo-privilegio.txt), [09](09-aws-preparacion-cuenta-e-iam.txt)). En AWS: 35 parámetros SecureString, `.env` 0600 root en los hosts, secretos distintos por ambiente y 0 apariciones de los valores en el repositorio y en los registros ([14](14-despliegue-aws-fase4.md)) | — |

## Matriz final: cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **PARTIAL**: ejecuciones locales (`local/`) y en AWS del 2026-11-02 (`fase4/`, enmascaradas). Falta la salida de la prueba de idempotencia completa (C3) | [`local/`](local/), [`fase4/`](fase4/), [`14`](14-despliegue-aws-fase4.md), [`08-revision-idempotencia.md`](08-revision-idempotencia.md) |
| 2. Diagrama de ambientes | **PASS** para la topología B: red, aislamiento (configurado frente a verificado), servidores `ci` y `nexus`, memoria prevista e identidades y autorización | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| 3. Commit que elimina las credenciales | **PASS**: `3a43855` (rama `HU01_Infraestructura_nube_bash`, publicada en `origin`). Sin reescribir el historial | `git show --stat 3a43855` |
| 4. Captura del escaneo de secretos | **PARTIAL**: árbol de trabajo en PASS e historial completo, repetido el 2026-11-02 sobre `3632068` (ACTIVO=0). Falta solo la captura de pantalla, que hará el equipo | [`03`](03-gitleaks-arbol-de-trabajo.txt), [`04`](04-gitleaks-historial.txt), [`fase4/20261102T194438Z-worktree-summary.txt`](fase4/20261102T194438Z-worktree-summary.txt) |

## Clasificación de los hallazgos de Gitleaks

| Categoría | Árbol de trabajo | Historial (`6f254ed`) | Definición |
|---|---|---|---|
| **ACTIVO** | **0** | — | Secreto real en un archivo que se versionaría. Debe ser 0 |
| **HISTÓRICO** | — | **51** | Credencial publicada en el commit inicial. Se considera **comprometida**, no se reutiliza en ningún ambiente y no se reescribe el historial |
| **PRUEBA** | 9 | 9 | Valor ficticio en `src/test` (*fixtures* de H2, JWT y bóveda de los tests) |
| **RESIDUAL** | 2 | 4 | Contraseña de prueba en los comentarios de las migraciones V2/V3, que son inmutables por la decisión X-2 (E2.6) |

**Escaneo del 2026-11-02** (Gitleaks v8.30.1 sobre `3632068`, [`fase4/`](fase4/)): árbol de trabajo igual
(0 ACTIVO, 9 PRUEBA, 2 RESIDUAL); historial de 13 commits con 68 hallazgos: los 51 HISTÓRICO y 4
RESIDUAL anteriores y 13 PRUEBA (los 4 nuevos son los valores ficticios del *fixture* del commit
`67af77d`).

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
| `01-validacion-estatica.txt` | `bash -n` (19/19), ShellCheck v0.11.0 sin hallazgos, validez de JSON y YAML (corte del 2026-10-31, 19 scripts). Para los 26 scripts actuales, la evidencia verificable es el reporte del 2026-11-02 [`fase4/20261102T214225Z-shellcheck-hu01.txt`](fase4/20261102T214225Z-shellcheck-hu01.txt): 0 hallazgos y control positivo SC2086. Las pasadas anteriores sobre 26 scripts (2026-11-01 y la de las 19:09 del 2026-11-02, cuyo reporte quedó vacío) no tienen reporte verificable |
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
| `13-plan-despliegue-fase3.txt` | Plan de la fase 3 (inventario, IAM, presupuesto, secuencia, recuperación y criterios) y, en su sección 9, las diferencias registradas al ejecutarlo en la fase 4 |
| `14-despliegue-aws-fase4.md` | Despliegue en AWS del 2026-11-02: estado final, trazabilidad criterio → prueba → resultado → evidencia, cronología, temporizadores, incidentes y correcciones, seguridad, coste, suficiencia del aislamiento y pendientes |
| `15-procedimiento-idempotencia-aws.md` | Procedimiento de la prueba de idempotencia en AWS (C3), con comandos, resultado esperado, coste y riesgos. **No ejecutado** |
| `16-nexus-eula.md` | EULA de Nexus Community Edition: texto y condiciones oficiales, interpretación técnica y consecuencias, para la decisión del equipo |
| `17-auditoria-final-hu01.md` | Auditoría final del 2026-11-02: matriz C1–C6 (PASS o PARTIAL, con lo que falta), inventario, scripts, seguridad, persistencia, Nexus, ambientes, idempotencia, evidencias, cambios locales, plan de cierre y autorizaciones. Estado: **PARCIALMENTE COMPLETADA** |
| `fase4/*` | Copias enmascaradas de los registros y reportes de la fase 4; cada una indica el sha256 de su original en `infra/logs` o `infra/security/reports` |
| `auditoria/*` | Validaciones locales de la auditoría final (`bash -n`, ShellCheck, YAML y JSON, `docker compose config`, `.gitignore`) y el resumen del Gitleaks final |
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

# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y una
comparación directa confirmó que ningún secreto generado aparece en los archivos versionables ni
en los logs. Las copias de los registros de AWS de [`fase4/`](fase4/) están además enmascaradas
(número de cuenta, identificadores de IAM y último octeto de IP públicas).

**Estado general (2026-11-03): HU-01 NO está terminada.** Informe completo, con la matriz del
Sprint 1 y los enlaces a cada evidencia: [INFORME_FINAL_HU01_SPRINT1.md](INFORME_FINAL_HU01_SPRINT1.md).

- **En AWS el 2026-11-02** ([evidencia 14](14-despliegue-aws-fase4.md)): red, IAM, 35 secretos en
  SSM, `ci` con Jenkins, SonarQube y PostgreSQL (PASS) y `nexus` con Nexus. Después se detuvieron las
  dos instancias, conservando sus volúmenes.
- **El 2026-11-03, implementado y probado en local** ([evidencia 18](18-mejoras-cierre-tecnico.md) e
  informe final):
  - registro principal CNCF Distribution, con su integración con Jenkins y la rotación;
  - servidores de ambiente probados por pares;
  - pruebas automatizadas de idempotencia, recuperación y aislamiento.
- **Pendiente:** su ejecución en AWS, que requiere autorización.

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

Clasificación desde el 2026-11-03 (informe final):
- **PASS:** implementación completa y evidencia verificable.
- **PARTIAL:** implementación o evidencia incompletas.
- **FAIL:** requisito incumplido.
- **BLOCKED:** requiere una autorización, una decisión o una dependencia externa.

Las evidencias 14 a 18, fechadas, usaron PASS, PARTIAL, FAIL y NOT VERIFIED. Estado de la historia:
**PARCIALMENTE COMPLETADA**.

| Criterio | Estado | Qué está hecho | Qué falta |
|---|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y el registro de artefactos | **BLOCKED** (autorización AWS) | En AWS el 2026-11-02 ([14](14-despliegue-aws-fase4.md)): `ci` y `nexus` (m7i-flex.large, AMI fijada, IMDSv2, gp3 cifrado) creados por script; Jenkins, SonarQube y PostgreSQL **PASS** (`verify-infra.sh` 22/0/1 y 53/0/5); Nexus desplegado, en línea y con la contraseña gestionada | Registro principal CNCF Distribution (decisión del equipo) e integración con Jenkins (`crane`): implementados y probados en local (integración 22/22, [auditoria](auditoria/20261103T041534Z-integracion-local-hu01.txt)). Falta desplegarlos y probarlos en AWS con `test-idempotency.sh` (autorización) |
| C2 · dev, stage y prod aislados | **BLOCKED** (autorización AWS) | En AWS: subred y grupo de seguridad propios por ambiente, ninguna regla entre ambientes y solo referencias a `ci` y `nexus` (15 comprobaciones PASS); con tráfico real, `ci → nexus:8081` permitido y `nexus → ci:8080/9000` bloqueados ([14](14-despliegue-aws-fase4.md) §8) | Sin servidores de ambiente (topología B), el aislamiento está **configurado y verificado por reglas, no con tráfico entre ambientes**. Decisión del 2026-11-03: un `t3.small` por ambiente, creados y probados por pares con `test-isolation.sh` dentro de la cuota de 5 vCPU (≈ 0.15 USD más el EBS). Falta ejecutarlo en AWS (autorización). El despliegue de las aplicaciones en los ambientes (E1.5) no cabe en HU-01 (ver el informe final) |
| C3 · `infra/bootstrap-*.sh` idempotentes | **BLOCKED** (autorización AWS) | Demostrado en local (2.ª ejecución con `created=0 updated=0`: secretos, Jenkins y SonarQube, más la corrección de derivas). Revisión estática de todos los scripts y 6 defectos corregidos ([08](08-revision-idempotencia.md)). En AWS: red `unchanged=28` y secretos `unchanged=43` en la 2.ª ejecución, e IAM convergente ([14](14-despliegue-aws-fase4.md)) | Dos ejecuciones de `bootstrap-all.sh` en AWS con *snapshot* y `diff` vacío: procedimiento listo en la [evidencia 15](15-procedimiento-idempotencia-aws.md) y automatizado en `infra/test-idempotency.sh` ([18](18-mejoras-cierre-tecnico.md)), pendiente de autorización (arranca las instancias) |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **PASS** | `${VAR:?}` sin valores por defecto, `.env.example` vacío y credenciales en `~/.circleguard/dev.env`; incluido en el commit `3a43855` | — |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **BLOCKED** (autorización AWS y otra persona) | Jenkins (JCasC) y SonarQube (API) sin pasos manuales; acceso administrativo por túnel; IAM, sesiones temporales, cuota y destrucción en CloudShell automatizados y documentados en `infra/README.md`. Los únicos pasos manuales son los que deben serlo (contraseñas y MFA en la consola de AWS), y están documentados | La reconstrucción en AWS siguiendo solo la documentación (nivel 1 del ensayo). La instalación del 2026-11-02 se hizo solo con los scripts ([14](14-despliegue-aws-fase4.md)). **Preparado el 2026-11-03:** ensayo de reconstrucción en dos niveles y tabla de pasos humanos con su motivo en `infra/README.md`, sin ejecutar ([18](18-mejoras-cierre-tecnico.md)) |
| C6 · Credenciales fuera del repositorio, con un mecanismo seguro | **PASS** | 0 secretos activos ([03](03-gitleaks-arbol-de-trabajo.txt); repetido el 2026-11-02 en [`fase4/`](fase4/)); los 7 `application.yml` funcionan con variables y fallan sin ellas ([07](07-verificacion-arranque-servicios.txt)); acceso a AWS sin claves permanentes ([06](06-iam-minimo-privilegio.txt), [09](09-aws-preparacion-cuenta-e-iam.txt)). En AWS: 35 parámetros SecureString, `.env` 0600 root en los hosts, secretos distintos por ambiente y 0 apariciones de los valores en el repositorio y en los registros ([14](14-despliegue-aws-fase4.md)) | — |

## Matriz final: cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **BLOCKED** (autorización AWS): salidas reales paso a paso en AWS del 2026-11-02 (`fase4/`, enmascaradas) y locales (`local/`, `auditoria/`). Falta la salida del comando único en AWS (`test-idempotency.sh`) | [`local/`](local/), [`fase4/`](fase4/), [`14`](14-despliegue-aws-fase4.md), [`08-revision-idempotencia.md`](08-revision-idempotencia.md) |
| 2. Diagrama de ambientes | **PASS** para la topología B: red, aislamiento (configurado frente a verificado), servidores `ci` y `nexus`, memoria prevista e identidades y autorización | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| 3. Commit que elimina las credenciales | **PASS**: `3a43855` (rama `HU01_Infraestructura_nube_bash`, publicada en `origin`). Sin reescribir el historial | `git show --stat 3a43855` |
| 4. Captura del escaneo de secretos | **BLOCKED** (captura manual): reporte de texto actual en `auditoria/` (ACTIVO=0). Falta la captura de pantalla, con instrucciones en [`capturas/README.md`](capturas/README.md) | [`03`](03-gitleaks-arbol-de-trabajo.txt), [`04`](04-gitleaks-historial.txt), [`fase4/20261102T194438Z-worktree-summary.txt`](fase4/20261102T194438Z-worktree-summary.txt) |

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
| `18-mejoras-cierre-tecnico.md` | Mejoras del 2026-11-03 **preparadas y validadas en local, sin desplegar en AWS**: registro CNCF Distribution junto a Nexus, servidores de ambiente opcionales, prueba de idempotencia automatizada y ensayo de reconstrucción. Las clasificaciones no cambian |
| `fase4/*` | Copias enmascaradas de los registros y reportes de la fase 4; cada una indica el sha256 de su original en `infra/logs` o `infra/security/reports` |
| `auditoria/*` | Validaciones locales fechadas (`bash -n`, ShellCheck, Compose, `.gitignore`), resúmenes de Gitleaks y, del 2026-11-03, la integración local en contenedor Linux (22/22), la prueba del registro (21/21), las comprobaciones unitarias (32/32) y el ShellCheck de 32 scripts. Los archivos de las 03:02-03:12 UTC quedan superados por los de las 04:11-04:15 UTC |
| `INFORME_FINAL_HU01_SPRINT1.md` | Informe final: matriz del Sprint 1 y de C1-C6, evidencias con enlaces, pruebas, costos, riesgos, pendientes humanos y commits sugeridos |
| `capturas/README.md` | Instrucciones exactas de las capturas de pantalla pendientes (ninguna capturada todavía) |
| `ensayo-reconstruccion/README.md` | Ensayo de reconstrucción de nivel 1 para otro integrante (C5): pasos, identidad y MFA, evidencia que entregar, criterios de PASS y mensaje listo para enviar |
| `aws/README.md` | Carpeta preparada para las salidas enmascaradas de las pruebas en AWS (idempotencia, aislamiento y ensayo): vacía hasta su ejecución autorizada |
| `auditoria/*-commit-3a43855-credenciales.txt` | Evidencia 3: el commit que eliminó las credenciales, con las líneas añadidas y solo el recuento de las eliminadas |
| `auditoria/*-prerrequisitos-wsl.txt` | `check-prerequisites.sh` en la estación de trabajo: la primera ejecución midió los 26 min de `git status` sobre OneDrive; la segunda, 13 s tras la corrección |
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

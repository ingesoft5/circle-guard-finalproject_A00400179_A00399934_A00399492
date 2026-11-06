# Evidencias de HU-01 · Infraestructura en la nube con Bash

Ningún archivo de esta carpeta contiene secretos. Los valores de Gitleaks están redactados, y una
comparación directa confirmó que ningún secreto generado aparece en los archivos versionables ni
en los logs. Las copias de los registros de AWS de [`fase4/`](fase4/) están además enmascaradas
(número de cuenta, identificadores de IAM y último octeto de IP públicas).

**Estado general (2026-11-04): HU-01 NO está cerrada.** C1, C2, C3, C4 y C6 están en **PASS**. Solo
C5 queda **BLOCKED**: necesita el ensayo de reconstrucción de otro integrante. Informe completo, con
la matriz y los enlaces a cada evidencia:
[INFORME_FINAL_HU01_SPRINT1.md](INFORME_FINAL_HU01_SPRINT1.md).

- **En AWS el 2026-11-02** ([evidencia 14](14-despliegue-aws-fase4.md)): red, IAM, 35 secretos en
  SSM, `ci` con Jenkins, SonarQube y PostgreSQL (PASS) y `nexus` con Nexus. Después se detuvieron las
  dos instancias, conservando sus volúmenes.
- **En AWS el 2026-11-03** ([`aws/idempotencia/`](aws/idempotencia/README.md)): el responsable
  ejecutó `test-idempotency.sh --apply --approve ci,nexus` con el resultado
  **`RESULTADO: IDEMPOTENTE`**:
  - dos `bootstrap-all.sh`; la 2.ª con `created=0 updated=0 unchanged=137`;
  - `diff S1 S2` y `diff S2 S3` vacíos;
  - publicación y descarga en CNCF Distribution desde `ci` y desde Jenkins con `crane`;
  - recuperación tras reiniciar los contenedores y persistencia de `jenkins_home`;
  - salud 25 PASS, 0 FAIL, 1 PENDING (Nexus sin EULA, por decisión);
  - parada de las instancias.
- **En AWS el 2026-11-03/04** ([`aws/aislamiento/`](aws/aislamiento/README.md)): la prueba de
  aislamiento con tráfico (`test-isolation.sh --apply`, dos sesiones con MFA, autorizada por el
  responsable) dio **`AISLAMIENTO VERIFICADO CON TRÁFICO`**:
  - se crearon los tres servidores `t3.small` de ambiente;
  - dev ↔ stage, dev ↔ prod y stage ↔ prod están bloqueados en los dos sentidos;
  - `ci → env:22` y `env → nexus:8082` están permitidos; `env → ci:8080/9000` y `nexus → env:22`,
    bloqueados;
  - la 2.ª ejecución de `bootstrap-env.sh` dio `created=0 updated=0` en los tres ambientes;
  - las 5 instancias quedaron detenidas.
- **En AWS el 2026-11-06** ([`aws/reconstruccion/`](aws/reconstruccion/README.md)): **destrucción total y
  reconstrucción desde cero** con el comando único:
  - el responsable destruyó todo en CloudShell (17 recursos, secretos conservados);
  - `bootstrap-all.sh --apply --approve ci,nexus` lo reconstruyó en **922 s** con `verify-infra pass=26 fail=0`;
  - la 2.ª ejecución dio `created=0 updated=0 unchanged=138`;
  - los ambientes y el aislamiento se probaron de nuevo sobre la infraestructura nueva (PASS).
- **Decisiones definitivas:**
  - el registro es CNCF Distribution;
  - el EULA de Nexus no se acepta: Nexus queda instalado sin repositorio operativo;
  - un `t3.small` por ambiente, encendidos por pares.
- **Pendiente:**
  - el ensayo de reconstrucción por otro integrante (C5);
  - las capturas de pantalla.

**Preparación de AWS (2026-11-01, solo lectura, [09](09-aws-preparacion-cuenta-e-iam.txt)):**
- Cuenta independiente en el **plan gratuito**: 100 USD de créditos; el plan termina el 2027-04-30.
- Tipos del plan gratuito (8 GiB como máximo), ofrecidos en us-east-2a y compatibles con la AMI.
  **Topología B aprobada el 2026-11-02** ([12](12-preparacion-arquitectura-b.txt)): dos
  `m7i-flex.large`, `ci` (Jenkins, SonarQube y PostgreSQL) y `nexus`; los ambientes no tienen
  servidores en HU-01 (aislamiento por red, configurado y sin verificar con tráfico). Superado el
  2026-11-03: un `t3.small` por ambiente, verificado con tráfico el 2026-11-03/04.
- Plantillas IAM: Access Analyzer sin hallazgos en las 8, y el simulador IAM sin escalada posible.
- Cuota de vCPU de 5: la topología B necesita 4, sin aumento. El 2026-11-03 `bootstrap-quota.sh`
  leyó 16 vCPU ([lectura](auditoria/20261103T201403Z-bootstrap-quota.txt)). El equipo mantiene
  `QUOTA_VCPU_LIMIT=5` como límite conservador.
- La cuenta raíz ya tiene MFA (activada por el equipo el 2026-11-01).
- **IAM creado el 2026-11-01 con autorización:** 3 políticas, 2 usuarios sin claves y 3 roles; convergencia comprobada en una segunda ejecución ([10](10-iam-creacion-e-idempotencia.txt)). Ningún recurso EC2, red o almacenamiento.

## Matriz final: seis criterios

Clasificación desde el 2026-11-03 (informe final):
- **PASS:** implementación completa y evidencia verificable.
- **PARTIAL:** implementación o evidencia incompletas.
- **FAIL:** requisito incumplido.
- **BLOCKED:** requiere una autorización, una decisión o una dependencia externa.

Las evidencias 14 a 18, fechadas, usaron PASS, PARTIAL, FAIL y NOT VERIFIED. Estado de la historia:
**PARCIALMENTE COMPLETADA** (5 de 6 criterios en PASS; C5, BLOCKED).

| Criterio | Estado | Qué está hecho | Qué falta |
|---|---|---|---|
| C1 · Servidores en la nube para Jenkins, SonarQube y el registro de artefactos | **PASS** | En AWS el 2026-11-02 ([14](14-despliegue-aws-fase4.md)): `ci` y `nexus` (m7i-flex.large, AMI fijada, IMDSv2, gp3 cifrado) creados por script; Jenkins, SonarQube y PostgreSQL **PASS**. **En AWS el 2026-11-03** ([`aws/idempotencia/`](aws/idempotencia/README.md)): registro CNCF Distribution en el servidor `nexus` (TLS y usuario `ci`); publicación y descarga desde `ci` y desde Jenkins con `crane` (`registry.txt`: 2 PASS); salud 25 PASS, 0 FAIL, 1 PENDING (Nexus sin EULA, por decisión) tras reiniciar los contenedores | Solo las capturas de pantalla ([`capturas/`](capturas/README.md)). Nexus queda instalado sin repositorio operativo: el EULA no se acepta |
| C2 · dev, stage y prod aislados | **PASS** | Subred, grupo de seguridad, llave, secretos y servidor `t3.small` propios por ambiente. **Con tráfico real en AWS el 2026-11-03/04** ([`aws/aislamiento/`](aws/aislamiento/README.md)): los 6 flujos entre ambientes bloqueados; `ci → env:22` y `env → nexus:8082` permitidos; `env → ci:8080/9000` y `nexus → env:22` bloqueados; cada host solo con el `.env` de su ambiente (0600 root). Antes: 15 comprobaciones de reglas en PASS ([14](14-despliegue-aws-fase4.md) §8) | Las capturas. El despliegue de las aplicaciones en los ambientes (E1.5) no forma parte de HU-01 |
| C3 · `infra/bootstrap-*.sh` idempotentes | **PASS** | **En AWS el 2026-11-03**: dos `bootstrap-all.sh` (el comando único); la 2.ª con `created=0 updated=0 unchanged=137` y ninguna línea CREATED ni UPDATED; `diff S1 S2` y `diff S2 S3` vacíos ([`aws/idempotencia/`](aws/idempotencia/README.md)). Cubre red, secretos, servidores, Jenkins, SonarQube, Nexus, el registro y la verificación. **En AWS el 2026-11-03/04**: la 2.ª ejecución de `bootstrap-env.sh` dio `created=0 updated=0 unchanged=9` en dev, stage y prod ([`aws/aislamiento/`](aws/aislamiento/README.md)). Antes: revisión estática y 6 defectos corregidos ([08](08-revision-idempotencia.md)) | — |
| C4 · Credenciales de `docker-compose.dev.yml` fuera del repositorio | **PASS** | `${VAR:?}` sin valores por defecto, `.env.example` vacío y credenciales en `~/.circleguard/dev.env`; incluido en el commit `3a43855` | — |
| C5 · Bash y Docker Compose sin configuración manual no documentada | **BLOCKED** (otro integrante) | Jenkins (JCasC), SonarQube (API) y el registro sin pasos manuales; acceso administrativo por túnel; IAM, sesiones temporales, cuota y destrucción en CloudShell automatizados y documentados en `infra/README.md`, con la tabla de pasos humanos y su motivo. La prueba del 2026-11-03 se hizo solo con los scripts | La reconstrucción siguiendo solo la documentación, por un integrante distinto del responsable: [ensayo de nivel 1](ensayo-reconstruccion/README.md), [plantilla del acta](ensayo-reconstruccion/ACTA-PLANTILLA.md) y [carpeta de evidencia](aws/ensayo-nivel1/README.md) preparados |
| C6 · Credenciales fuera del repositorio, con un mecanismo seguro | **PASS** | 0 secretos activos (Gitleaks del 2026-11-03 en [`auditoria/`](auditoria/)); los 7 `application.yml` funcionan con variables y fallan sin ellas ([07](07-verificacion-arranque-servicios.txt)); acceso a AWS sin claves permanentes ([06](06-iam-minimo-privilegio.txt), [09](09-aws-preparacion-cuenta-e-iam.txt)). En AWS: 35 parámetros SecureString, `.env` 0600 root en los hosts, secretos distintos por ambiente y 0 apariciones de los valores en el repositorio y en los registros ([14](14-despliegue-aws-fase4.md)); contraseña del registro en SSM, htpasswd bcrypt en el host | — |

## Matriz final: cuatro evidencias

| Evidencia | Estado | Archivos |
|---|---|---|
| 1. Salida del bootstrap | **PASS**: salida real del comando único `bootstrap-all.sh` en AWS, dos veces, del 2026-11-03 ([`run1.txt`](aws/idempotencia/run1.txt), [`run2.txt`](aws/idempotencia/run2.txt), enmascaradas), además de las salidas paso a paso del 2026-11-02 (`fase4/`) y las locales (`local/`, `auditoria/`) | [`aws/idempotencia/`](aws/idempotencia/README.md), [`fase4/`](fase4/), [`14`](14-despliegue-aws-fase4.md), [`local/`](local/) |
| 2. Diagrama de ambientes | **PASS** para la topología B: red, aislamiento (configurado frente a verificado), servidores `ci` y `nexus`, memoria prevista e identidades y autorización | [`../../arquitectura/infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| 3. Commit que elimina las credenciales | **PASS**: `3a43855` (rama `HU01_Infraestructura_nube_bash`, publicada en `origin`). Sin reescribir el historial | `git show --stat 3a43855` |
| 4. Captura del escaneo de secretos | **BLOCKED** (captura manual, sin AWS): reporte de texto actual en `auditoria/` (ACTIVO=0). Falta la captura de pantalla, con instrucciones en [`capturas/README.md`](capturas/README.md) | [`03`](03-gitleaks-arbol-de-trabajo.txt), [`04`](04-gitleaks-historial.txt), resúmenes de Gitleaks del 2026-11-03 en [`auditoria/`](auditoria/) |

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

**Escaneo final del 2026-11-04** (Gitleaks v8.30.1 sobre `3afca6f` más los cambios sin confirmar):
- árbol de trabajo: 467 archivos, sin cambios en la clasificación (0 ACTIVO, 9 PRUEBA, 2 RESIDUAL);
- historial: 24 commits, sin cambios (68 = 51 HISTÓRICO + 13 PRUEBA + 4 RESIDUAL);
- resúmenes: [árbol](auditoria/20261104T002645Z-worktree-summary.txt) e
  [historial](auditoria/20261104T002645Z-history-summary.txt).

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
| `15-procedimiento-idempotencia-aws.md` | Procedimiento de la prueba de idempotencia en AWS (C3), con comandos, resultado esperado, coste y riesgos. Automatizado en `test-idempotency.sh` y **ejecutado el 2026-11-03** ([`aws/idempotencia/`](aws/idempotencia/README.md)) |
| `16-nexus-eula.md` | EULA de Nexus Community Edition: texto y condiciones oficiales, interpretación técnica y consecuencias. **Decisión final: no se acepta**; el registro es CNCF Distribution |
| `17-auditoria-final-hu01.md` | Auditoría final del 2026-11-02: matriz C1–C6 (PASS o PARTIAL, con lo que falta), inventario, scripts, seguridad, persistencia, Nexus, ambientes, idempotencia, evidencias, cambios locales, plan de cierre y autorizaciones. Estado: **PARCIALMENTE COMPLETADA** |
| `18-mejoras-cierre-tecnico.md` | Mejoras del 2026-11-03 **preparadas y validadas en local, sin desplegar en AWS**: registro CNCF Distribution junto a Nexus, servidores de ambiente opcionales, prueba de idempotencia automatizada y ensayo de reconstrucción. Las clasificaciones no cambian |
| `fase4/*` | Copias enmascaradas de los registros y reportes de la fase 4; cada una indica el sha256 de su original en `infra/logs` o `infra/security/reports` |
| `auditoria/*` | Validaciones locales fechadas (`bash -n`, ShellCheck, Compose, `.gitignore`), resúmenes de Gitleaks y, del 2026-11-03, la integración local en contenedor Linux (22/22) y la prueba del registro (21/21). Los archivos de las 03:02-03:12 UTC quedan superados por los de las 04:11-04:15 UTC, y estos por los finales (abajo) |
| `auditoria/20261104T002821Z-validaciones-locales-hu01.txt` | Validaciones locales finales: `bash -n` (34), YAML y JSON, los 5 Compose (válidos con valores y rechazados sin ellos), `.gitignore`, enlaces y espacios en blanco |
| `auditoria/20261104T002645Z-{worktree,history}-summary.txt` | Gitleaks final: árbol de trabajo (ACTIVO=0) e historial |
| `auditoria/20261103T231039Z-comprobaciones-unitarias-hu01.txt` | Comprobaciones unitarias finales, sin AWS: 40/40 |
| `auditoria/20261103T231008Z-shellcheck-hu01.txt` | ShellCheck v0.11.0 final de los 34 scripts, con el sha256 de cada uno: 0 hallazgos y control positivo SC2086 |
| `auditoria/20261103T230202Z-decision-eula-local.txt` | Prueba local de la decisión final sobre el EULA: `configure.sh` informa UNCHANGED sin escribir en Nexus y `verify-infra.sh` da PASS con CNCF Distribution (19/19) |
| `auditoria/20261103T225236Z-check-evidence.txt` | Prueba de `infra/check-evidence.sh`: 0 hallazgos en `aws/idempotencia/` y detección de los valores ficticios plantados |
| `auditoria/20261103T201403Z-bootstrap-quota.txt` | Lectura de solo lectura de la cuota de vCPU: 16 (valor por defecto de AWS: 5) |
| `INFORME_FINAL_HU01_SPRINT1.md` | Informe final en 17 secciones: alcance, arquitectura, servidores, ambientes, registro, Jenkins, secretos, scripts, idempotencia, aislamiento, ensayo, seguridad, costos, limitaciones, matriz y conclusión |
| `capturas/README.md` | Instrucciones exactas de las capturas de pantalla pendientes (ninguna capturada todavía): cuáles se pueden tomar ya sin AWS y cuáles no |
| `ensayo-reconstruccion/README.md` | Ensayo de reconstrucción de nivel 1 para otro integrante (C5): pasos, identidad y MFA, evidencia que entregar, criterios de PASS y mensaje listo para enviar |
| `ensayo-reconstruccion/ACTA-PLANTILLA.md` | Plantilla del acta del ensayo, que completa el otro integrante después de ejecutarlo |
| `aws/README.md` | Índice de las pruebas en AWS y procedimiento para versionar sus salidas enmascaradas con `infra/check-evidence.sh` |
| `aws/idempotencia/` | **Prueba de idempotencia integral del 2026-11-03** (C1, C3): 14 salidas enmascaradas, con el sha256 de los originales |
| `auditoria/20261103T230549Z-orden-evidencias-local.txt` | Prueba local de la corrección de `test-idempotency.sh`: las copias enmascaradas se hacen después del resultado y de la parada (7/7) |
| `aws/reconstruccion/` | **Destrucción y reconstrucción desde cero del 2026-11-06** («desde cero con un comando», P1.2): inventarios antes y después, la salida de CloudShell, el comando único dos veces y el aislamiento sobre la infraestructura nueva. 16 salidas enmascaradas con el sha256 de los originales |
| `aws/aislamiento/` | **Prueba de aislamiento con tráfico del 2026-11-03/04** (C2, C3): `fases-1-3/` y `fases-4-5/`, 11 salidas enmascaradas, con el sha256 de los originales y los criterios de PASS cumplidos |
| `aws/ensayo-nivel1/` | Ensayo de reconstrucción (C5): **pendiente del otro integrante**; archivos que debe contener |
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

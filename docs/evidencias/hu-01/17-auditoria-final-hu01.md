# 17 · Auditoría final de HU-01 (2026-11-02)

Auditoría del repositorio, de la documentación y del estado de AWS, hecha el 2026-11-02 desde las
22:17 UTC sobre el commit `3632068` más los cambios locales sin confirmar (sección K).
Solo se ejecutaron pruebas locales y **lecturas** en AWS con el rol de lectura: ninguna instancia se
arrancó y no se modificó ningún recurso.

## A. Resumen ejecutivo

**Estado: PARCIALMENTE COMPLETADA.** La infraestructura se aprovisionó con los scripts, se validó
en AWS y está detenida con sus volúmenes EBS conservados (la recuperación de los servicios tras un
arranque no está probada; sección F). Las herramientas de CI (Jenkins, SonarQube y
PostgreSQL) cumplen. Quedan tres cosas antes de poder cerrarla:

1. La **prueba de idempotencia completa** en AWS (C3), que exige arrancar las instancias.
2. La **decisión sobre el EULA** de Nexus (C1 y C5), que corresponde al equipo.
3. La aceptación, por parte del equipo, de que el aislamiento de los ambientes quede **configurado y
   verificado por reglas** sin una prueba con tráfico entre ambientes (C2).

## B. Matriz C1–C6

| Criterio | Requisito | Implementación | Responsable | Prueba | Evidencia | Resultado | Falta | Acción |
|---|---|---|---|---|---|---|---|---|
| C1 | Servidores para Jenkins, SonarQube y Nexus | 2 EC2 `m7i-flex.large` (AMI fijada, IMDSv2, gp3 cifrado); stacks Compose; configuración por API | `bootstrap-servers.sh`, `bootstrap-{jenkins,sonarqube,nexus}.sh`, `setup-docker.sh`, `*/configure.sh` | Pasos 6a-11 en AWS | [14](14-despliegue-aws-fase4.md), [`fase4/`](fase4/) | **PARTIAL**: Jenkins, SonarQube y PostgreSQL PASS; Nexus desplegado y en línea, sin función de repositorio | Decisión del EULA | Decisión del equipo ([16](16-nexus-eula.md)) |
| C2 | dev, stage y prod aislados | Subred y grupo de seguridad propios por ambiente; ninguna regla entre ambientes; SSH y 8082 solo desde `ci` y hacia `nexus` | `bootstrap-network.sh` | `verify-infra.sh` (15 comprobaciones de configuración) y flujos `ci ↔ nexus` con `nc` | [14](14-despliegue-aws-fase4.md) §8, `fase4/verify-infra-20261102T193653Z.log.txt` | **PARTIAL**: configurado y verificado por reglas; **no** probado con tráfico entre ambientes | Tráfico entre ambientes (no hay servidores de ambiente en la topología B) | Aceptar la limitación para HU-01 (recomendado) y probarlo en la historia que despliegue esos servidores; C2 no se cierra sin esa aceptación |
| C3 | Bootstrap idempotentes | Búsqueda por etiquetas, comparación por hash, creación solo si falta, reconciliación de reglas, contadores `created/updated/unchanged/planned` | Todos los `bootstrap-*.sh` y `lib/` | 2.ª ejecución en AWS de red (`unchanged=28`), secretos (`unchanged=43`) e IAM; ejecuciones locales; convergencia tras el fallo parcial del paso 4 (VPC e IGW reutilizados, `unchanged=4`) | [08](08-revision-idempotencia.md), [10](10-iam-creacion-e-idempotencia.txt), [14](14-despliegue-aws-fase4.md) | **PARTIAL** | `bootstrap-all.sh` dos veces en AWS con *snapshot* y `diff` vacío | Ejecutar la [evidencia 15](15-procedimiento-idempotencia-aws.md) con autorización |
| C4 | Credenciales de `docker-compose.dev.yml` fuera del repositorio | `${VAR:?}` sin valores por defecto; `.env.example` sin valores | `docker-compose.dev.yml`, `.env.example` | `docker compose config -q` (válido con variables, rechazado sin ellas); Gitleaks | [02](02-validacion-compose.txt), [03](03-gitleaks-arbol-de-trabajo.txt), `auditoria/` | **PASS** | — | — |
| C5 | Bash y Compose sin configuración manual no documentada | Todo por scripts; los pasos manuales son contraseñas y MFA en AWS y la decisión del EULA | `infra/README.md`, scripts | Despliegue completo del 2026-11-02 solo con los scripts | [14](14-despliegue-aws-fase4.md), [`infra/README.md`](../../../infra/README.md) | **PARTIAL** | EULA; reconstrucción desde cero por alguien que solo siga la documentación | Ensayo de reconstrucción en una cuenta o sesión autorizada |
| C6 | Credenciales fuera del repositorio con un mecanismo seguro | SSM SecureString (clave `aws/ssm`), `.env` 0600 root en los hosts por tubería SSH, sesiones temporales sin claves permanentes, roles separados | `bootstrap-secrets.sh`, `lib/common.sh`, `lib/remote.sh`, `lib/session.sh` | Gitleaks (ACTIVO=0), comparación en memoria de valores de SSM, `verify-infra.sh --credentials` | [06](06-iam-minimo-privilegio.txt), [14](14-despliegue-aws-fase4.md) | **PASS** | — | — |

Ningún criterio está en FAIL. Ningún criterio queda NOT VERIFIED: los aspectos sin probar se indican
dentro de cada PARTIAL.

## C. Inventario técnico (comprobado a las 22:17 UTC, solo lectura)

| Tipo | Elemento | Estado |
|---|---|---|
| EC2 | `circleguard-ci` `i-010843f2125041114` | **stopped** · m7i-flex.large · `ami-0fc53b217ec1ad816` |
| EC2 | `circleguard-nexus` `i-08c990919adc43fa1` | **stopped** · igual |
| EBS | `vol-07b111aa93b1cec4f` (30 GiB) y `vol-06a01333bd08c9382` (25 GiB) | gp3 cifrados, conservados |
| Red | VPC `vpc-017214d72e444769e`, IGW, 4 subredes, 1 tabla de rutas, 5 grupos de seguridad | 31 reglas, idénticas a las esperadas |
| IAM | Roles de lectura, operación y teardown; usuarios operador y teardown sin claves | Operador v3, teardown v2 y lectura v1, iguales a las plantillas (verificado a las 18:53) |
| Secretos | 35 parámetros SecureString y 4 pares ed25519 | Verificados a las 18:14 |
| Servicios (al parar) | Jenkins 2.580.2 LTS, SonarQube 26.10 con PostgreSQL 16.15, Nexus 3.96.5 | `healthy`; EULA de Nexus pendiente |
| Scripts | 26 (`git ls-files 'infra/*.sh' 'infra/**/*.sh'`) | Sin cambios respecto a `3632068` |

## D. Auditoría de scripts

- **Herramientas** (registro `auditoria/20261102T222030Z-validaciones-locales-hu01.txt`):
  - `bash -n`: 26/26 sin errores.
  - **ShellCheck v0.11.0** (`sha256:61862eba1fcf…25a8d`), `-x -S style`: **0 hallazgos**, `{"comments":[]}`.
  - El reporte verificable de las 21:42 (`fase4/20261102T214225Z-shellcheck-hu01.txt`) coincide en lista
    y en el sha256 de cada uno de los 26 scripts con el código actual. Su control positivo detectó SC2086.
- **Manejo de errores:** `set -Eeuo pipefail`, una *trap* `ERR` y `die` con código 1 en la librería común.
  El modo por defecto es plan; lo facturable exige `--apply --approve`, y la parada pide la palabra
  `DETENER` (o `CG_CONFIRM`).
- **Idempotencia del código:** cada recurso se busca por etiquetas y `cg_one` se detiene ante
  duplicados. Los archivos y el `.env` se comparan por sha256, y los secretos solo se crean si faltan.
  Las reglas se reconcilian: se añaden las que faltan y se revocan las que sobran. La AMI está fijada.
  `docker compose up -d` solo reconstruye si cambió el contexto. Los `configure.sh` comprueban antes de
  actuar.
  - **Distinción importante:** que el código esté diseñado para ser idempotente **no** sustituye a la
    prueba real de C3 en AWS, que sigue pendiente.
- **Estados parciales:** el fallo de las 16:37 dejó una VPC y un IGW. La ejecución siguiente los
  reutilizó (`unchanged=4`) y completó la red. Es evidencia real de convergencia tras un fallo parcial.
- **Defectos corregidos durante la fase 4**, todos con commit: `536771a` (IAM de red), `b18f27c`
  (orden de teardown), `7eb262b` (`cg_dry_run`) y `3632068` (AMI fijada).
- **Hallazgo menor, informativo:** `aws-session.sh`, `bootstrap-iam.sh`, `bootstrap-quota.sh` y
  `teardown-cloudshell.sh` no tienen bit de ejecución en Git. No afecta, porque la documentación los
  invoca siempre con `bash infra/...`. No se cambió.

## E. Auditoría de seguridad

- **Gitleaks v8.30.1:**
  - Árbol de trabajo sin secretos activos en todas las ejecuciones del 2026-11-02 (ACTIVO=0, PRUEBA=9,
    RESIDUAL=2); la de las 22:24 (`auditoria/`) cubre los documentos nuevos (ver K). Tras la revisión
    final de coherencia se repitió el 2026-11-03 a las 00:19 UTC con el mismo resultado, sobre la
    versión definitiva de los documentos (reporte en `infra/security/reports/20261103T001932Z-*`,
    ignorado por Git).
  - Historial de 13 commits (19:08): 68 hallazgos, de ellos 51 HISTÓRICO, 13 PRUEBA y 4 RESIDUAL.
  - **El historial no está limpio:** los 51 hallazgos HISTÓRICO son credenciales del commit inicial
    `6f254ed`, que se consideran comprometidas, no se reutilizan y no se reescriben.
  - **Recomendación sin cambiar el historial:** confirmar que ninguna de esas credenciales sigue activa
    en ningún sistema.
- **Cobertura de los escaneos:**
  - Gitleaks revisa los archivos que se versionarían, incluidas las copias de `fase4/`, y no los
    ignorados (`infra/logs`, `infra/security/reports`).
  - La comparación en memoria de los 35 valores de SSM cubrió el repositorio y los 112 registros
    escritos **hasta las 19:43**. Los posteriores (parada, Gitleaks final y ShellCheck) solo están
    cubiertos por Gitleaks.
- **Evidencias de `fase4/`:**
  - Las 29 son legibles y no están vacías. Están enmascaradas, así que su hash no coincide con el de
    sus originales; cada cabecera indica el sha256 del original. El diagnóstico
    `diag-6a-autorizacion.txt` remite a sus tres originales, conservados sin cambios en
    `infra/logs/diag-6a-20261102/` (ignorado por Git).
  - Ninguna contiene el número de cuenta, identificadores de IAM, mensajes de autorización codificados,
    IP públicas completas, claves de AWS ni llaves privadas.
  - El sha256 declarado coincide con el original en las 28 copias de un solo registro y en los tres
    originales del diagnóstico.
- **Archivos sensibles:** ningún `.env`, `*.local.env`, `*.pem` ni `*.key` versionado. Las reglas de
  `.gitignore` se comprobaron, y ninguna evidencia queda ignorada.
- **Reportes no válidos que se conservan:**
  - `infra/security/reports/20261102T190651Z-*` (el contenedor vio la copia vacía);
  - `20261102T190923Z-shellcheck.txt` (0 bytes).

  Están documentados como no evidencia.

## F. Persistencia

**Configurado:**
- volúmenes con nombre para todos los datos;
- *healthchecks* en los cuatro contenedores;
- `restart: unless-stopped` en AWS;
- `depends_on: db` con `service_healthy`;
- los datos en el EBS, que se conservó.

**Probado:**
- arranque y salud de los cuatro servicios en AWS;
- **volúmenes EBS conservados** tras la parada: siguen existiendo y adjuntos (lectura de las 22:17).

**No probado:** la **recuperación de los datos y de los servicios tras un arranque**. No se afirma que
la persistencia después de reiniciar esté demostrada. La 1.ª ejecución de la prueba de idempotencia
permitirá comprobarlo: servicios sanos y contraseñas gestionadas todavía válidas (evidencia 15,
sección 7).

## G. Nexus

- **Estado:** desplegado, en línea y con la contraseña gestionada. **EULA no aceptado**
  (`NEXUS_ACCEPT_EULA=false`, sin cambios).
- **Pendiente:** repositorio `circleguard-docker`, realm DockerToken y acceso anónimo.
- **Recomendación:** esperar la decisión de la persona autorizada. Condiciones, riesgos (uso «internal
  business purposes», pruebas de seguridad prohibidas y telemetría) y cambios por alternativa en la
  [evidencia 16](16-nexus-eula.md).

## H. Ambientes

- **Configurado y verificado por reglas en AWS:** subred y grupo de seguridad propios, ninguna regla
  entre ambientes y solo referencias a `ci` y `nexus`.
- **Probado con tráfico:** `ci → nexus:8081` permitido; `nexus → ci:8080` y `nexus → ci:9000`
  bloqueados.
- **No probado:** tráfico entre ambientes, porque no hay servidores de ambiente.
- **Recomendación:** trasladar esa prueba a la historia que despliegue los servidores de ambiente
  (`bootstrap-env.sh`).

## I. Idempotencia

- **Procedimiento:** [evidencia 15](15-procedimiento-idempotencia-aws.md), revisado en esta auditoría
  (sección 7: punto de partida, persistencia, ID y estados, contadores, aborto y ventana de MFA).
- **Autorización necesaria:** arrancar las dos instancias y, si cambió la IP pública del operador,
  que se actualice la regla del puerto 22.
- **Criterio de aceptación:** `diff S1 S2` vacío y la 2.ª ejecución con `created=0 updated=0` y
  `planned=1` (EULA).
- **Coste:** ≈ 0.12-0.21 USD.

## J. Evidencias

| Grupo | Archivos | Contenido |
|---|---|---|
| 01-05 | Validación estática, Compose, Gitleaks, tests | Fase local (2026-10-31) |
| 06 | IAM de mínimo privilegio | Actualizado con las v2 y v3 del operador |
| 07-08 | Arranque de servicios y revisión de idempotencia | Fase local |
| 09-12 | Preparación de AWS, IAM, identidades y topología B | Fases 0-2, con notas posteriores fechadas en 11 y 12 |
| 13 | Plan de despliegue | Fase 3; la sección 9 registra la fase 4 |
| 14 | Despliegue en AWS | Fase 4: trazabilidad, cronología, temporizadores, incidentes, seguridad, coste, persistencia |
| 15 | Procedimiento de idempotencia | No ejecutado; revisado |
| 16 | EULA de Nexus | Condiciones, interpretación y recomendación |
| 17 | Esta auditoría | — |
| `local/` | 11 registros de ejecuciones locales | Fase local |
| `fase4/` | 29 copias enmascaradas (25 registros, 3 reportes y el diagnóstico del 6a) | Fase 4 |
| `auditoria/` | Validaciones locales y resumen final de Gitleaks | Esta auditoría |

## K. Cambios locales (sin confirmar)

- **Modificados respecto a `3632068`:**
  - `docs/evidencias/hu-01/11-validacion-identidades.txt` (nota fechada)
  - `docs/evidencias/hu-01/12-preparacion-arquitectura-b.txt` (nota fechada)
  - `docs/evidencias/hu-01/13-plan-despliegue-fase3.txt` (sección 9)
  - `docs/evidencias/hu-01/README.md`
  - `infra/README.md`
- **Nuevos:**
  - `docs/evidencias/hu-01/14-despliegue-aws-fase4.md`
  - `docs/evidencias/hu-01/15-procedimiento-idempotencia-aws.md`
  - `docs/evidencias/hu-01/16-nexus-eula.md`
  - `docs/evidencias/hu-01/17-auditoria-final-hu01.md`
  - `docs/evidencias/hu-01/fase4/` (29 archivos)
  - `docs/evidencias/hu-01/auditoria/` (2 archivos)
- **Sin cambios:** ningún script, plantilla IAM, Compose ni archivo de configuración.
- **Ignorados (no se versionan ni deben añadirse):** `infra/logs/` (incluidos los originales del
  diagnóstico del 6a en `infra/logs/diag-6a-20261102/`) e `infra/security/reports/`. Las copias
  enmascaradas que sí se versionan están en `fase4/` y `auditoria/`.

## L. Plan de cierre

| Prioridad | Tarea | Motivo | Riesgo | Coste estimado | Requiere autorización |
|---|---|---|---|---|---|
| 1 | Revisar y confirmar los cambios locales (commit y push) | Que las evidencias queden en el repositorio | Bajo | 0 | Sí (lo hace el usuario) |
| 2 | Prueba de idempotencia en AWS (evidencia 15), que también prueba la persistencia | C3 y persistencia | Medio: arranca instancias; puede actualizar la regla del 22 | ≈ 0.12-0.21 USD | Sí |
| 3 | Decisión sobre el EULA de Nexus | C1 y C5 | Contractual | 0 (decisión); ≈ 0.10 USD/h si se aplica | Sí (persona autorizada) |
| 4 | Aceptar o no el alcance de C2 sin tráfico entre ambientes | C2 | Bajo | 0 | Sí (equipo) |
| 5 | Ensayo de reconstrucción desde cero siguiendo solo la documentación | C5 | Medio | Depende de cómo se haga | Sí |
| 6 | Captura de pantalla del escaneo de secretos | Evidencia 4 | Bajo | 0 | No (la hace el equipo) |
| 7 | Prueba real de la parada automática (paso 12) | Opcional | Bajo | ≈ 0.83 USD (4 h encendidas) | Sí |
| 8 | Bit de ejecución de 4 scripts | Coherencia (opcional) | Ninguno | 0 | Sí (cambio en el repositorio) |

## M. Autorizaciones pendientes

1. Arrancar `circleguard-ci` y `circleguard-nexus` para la prueba de idempotencia, aceptando que pueda
   actualizarse la regla del puerto 22 si cambió la IP del operador.
2. Decisión sobre el EULA de Nexus, por la persona autorizada.
3. Aceptación del alcance de C2.
4. Commits y push (el usuario).
5. Opcionales: paso 12 y ensayo de reconstrucción.

## N. Conclusión

**HU-01: PARCIALMENTE COMPLETADA.** La documentación y las evidencias están listas para revisión.
Para declararla completada falta la prueba de idempotencia en AWS (C3), una decisión contractual
(EULA de Nexus) y la aceptación del alcance de C2. Mientras tanto, las instancias permanecen detenidas.
El cargo fijo previsto es el EBS, ≈ 0.145 USD/día (estimación con precios de referencia; no es el coste
total de AWS, que se comprueba en Billing). Límites: presupuesto absoluto de 15 USD y línea operativa
de parada de 12 USD; acumulado estimado ≈ 0.13 USD más el EBS de los días transcurridos.

# Informe final de HU-01 · Infraestructura en la nube con Bash (Sprint 1, E1.2)

Actualizado: 2026-11-03, 16:30 UTC. Base: commit `889ce09` de la rama
`HU01_Infraestructura_nube_bash` más los cambios locales sin confirmar descritos aquí.
- No se hizo ninguna operación de escritura en AWS, ni commits ni push.
- El EULA de Nexus sigue sin aceptar.

Estados:
- **PASS:** implementación completa y evidencia verificable.
- **PARTIAL:** implementación o evidencia incompletas.
- **FAIL:** requisito incumplido.
- **BLOCKED:** requiere una autorización, una decisión o una dependencia externa.

## A. Resumen ejecutivo

**Resultado global: HU-01 NO está terminada.**
- **Criterios en PASS:** C4 y C6.
- **Criterios en BLOCKED:** C1, C2, C3 y C5. Todo su código y sus pruebas están listos y validados en
  local; falta ejecutarlos en AWS, lo que exige la sesión con MFA del responsable y su autorización.
  C5 necesita además que otro integrante siga la documentación.
- **Ningún criterio en FAIL.**
- **Coste:** acumulado estimado de 0.24 USD; previsto hasta el 2026-11-22, ≈ 6.4 USD de 15.

**Implementado** (sobre el despliegue en AWS del 2026-11-02, [evidencia 14](14-despliegue-aws-fase4.md)):
- **Registro principal CNCF Distribution 3.0.0** en el servidor `nexus`, puerto 8082 (decisión del
  equipo). Nexus sigue instalado sin EULA y nada depende de él
  ([decisión](../../arquitectura/registro-artefactos.md)).
  - TLS, con certificado EC P-256 generado en el host.
  - Usuario bcrypt `ci`, con la contraseña en SSM.
  - Volumen persistente y *healthcheck*.
  - Certificado y usuario preparados **antes** de arrancar el contenedor.
- **Jenkins publica y descarga con `crane`** v0.22.1 (sha256 fijado), sin el socket de Docker.
  Credenciales desde SSM.
- **Rotación de la contraseña del registro** con verificación y recuperación automática.
- **Ambientes:** un `t3.small` por ambiente, con subred, grupo de seguridad, llave y credenciales
  propios. Se crean y prueban por pares (la cuota es de 5 vCPU), con una guarda que impide superarla.
- **Pruebas para AWS**, con parada garantizada:
  - `test-idempotency.sh`: comando único dos veces, persistencia, Jenkins → registro, flujos de
    red y recuperación tras reiniciar contenedores;
  - `test-isolation.sh`: tráfico entre ambientes, en dos sesiones.
- **Ensayo de reconstrucción de nivel 1** preparado para otro integrante
  ([instrucciones](ensayo-reconstruccion/README.md)) y comprobación de la estación de trabajo
  (`check-prerequisites.sh`).

**Corregido hoy:**
- La prueba de idempotencia habría dado un **falso FAIL** de persistencia en Jenkins: el contenedor
  se recrea con la nueva imagen. Ahora comprueba que el volumen `jenkins_home` es anterior a la prueba.
- La prueba de aislamiento no actualizaba la regla SSH si cambiaba la IP del operador.
- `git status` tardó **26 min** desde WSL sobre la carpeta de OneDrive. La prueba ahora lo limita a
  90 s y lo hace antes de usar la ventana MFA de 1 h.
- Anteriores: la parada automática de los hosts de ambiente, el error silencioso de `prepare.sh`,
  `scan-secrets.sh` en Git Bash y la aprobación de roles no configurados.

## B. Matriz de cumplimiento (Sprint 1 / E1.2 y HU-01)

Fuentes del enunciado ([PDF](../../../Proyecto_Final_CircleGuard.pdf)):
- **p. 2:** contexto: credenciales en texto plano; ciclo «automatizado, seguro, observable y reproducible».
- **p. 4:** E1.2 y el alcance de despliegue de la Parte 1.
- **p. 6:** estructura del repositorio y regla de evidencias verificables.
- **p. 7:** rúbrica P1.2.
- **p. 9:** instrucciones de entrega 2 y 4.

| # | Requisito (fuente) | Criterio | Implementación | Prueba | Resultado | Evidencia | Estado |
|---|---|---|---|---|---|---|---|
| 1 | Servidores en la nube para Jenkins, SonarQube y el registro (E1.2) | C1 | `ci` (Jenkins JCasC, SonarQube y PostgreSQL) y `nexus` (registro Distribution) en EC2 | AWS 2026-11-02: `verify-infra.sh` 22/0/1 y 53/0/5. Local 2026-11-03: registro y Jenkins → registro | Jenkins y SonarQube PASS en AWS; registro y Jenkins PASS en local; **registro sin desplegar en AWS** | [verify 193451Z](fase4/verify-infra-20261102T193451Z.log.txt), [verify 193653Z](fase4/verify-infra-20261102T193653Z.log.txt), [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) | **BLOCKED** |
| 2 | dev, stage y prod aislados (E1.2) · «Tres ambientes aislados» (P1.2) | C2 | Subred, grupo de seguridad, llave, credenciales y servidor `t3.small` por ambiente | AWS 2026-11-02: 15 PASS de configuración; tráfico real `ci↔nexus`. Local: roles y guarda de cuota | **Sin prueba de tráfico entre ambientes** (`test-isolation.sh`) | [verify 193653Z](fase4/verify-infra-20261102T193653Z.log.txt) l. 42-63, [diagrama](../../arquitectura/infra-ambientes.md) | **BLOCKED** |
| 3 | Scripts Bash idempotentes (E1.2) | C3 | Búsqueda por etiquetas, crear solo si falta, reconciliación, hashes, contadores, guardas | AWS: 2.ª ejecución de red `0/0/28`, secretos `0/0/43` e IAM `0/0/19`. Local: 2.ª, 3.ª y 4.ª ejecución sin cambios | **Integral en AWS pendiente** | [red](fase4/bootstrap-network-20261102T175849Z.log.txt), [secretos](fase4/bootstrap-secrets-20261102T181248Z.log.txt), [IAM](10-iam-creacion-e-idempotencia.txt), [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) | **BLOCKED** |
| 4 | Credenciales de `docker-compose.dev.yml` fuera del repositorio (p. 2) | C4 | `${VAR:?}` sin valores por defecto y `.env.example` vacío (commit `3a43855`) | `docker compose config`; Gitleaks 2026-11-03 | Compose se niega sin variables; ACTIVO=0 | [commit 3a43855](auditoria/20261103T160739Z-commit-3a43855-credenciales.txt), [02](02-validacion-compose.txt), [Gitleaks](auditoria/20261103T162946Z-worktree-summary.txt) | **PASS** |
| 5 | Bash y Compose sin configuración manual no documentada (E1.2) | C5 | Scripts, JCasC y API; pasos humanos listados con su motivo; ensayo de nivel 1 preparado | AWS 2026-11-02: instalación solo con scripts. Prerrequisitos en WSL: `fail=0` | **Ensayo por otro integrante pendiente** | [14](14-despliegue-aws-fase4.md), [prerrequisitos](auditoria/20261103T162805Z-prerrequisitos-wsl.txt), [ensayo](ensayo-reconstruccion/README.md) | **BLOCKED** |
| 6 | Credenciales con un mecanismo seguro; sin secretos en el repositorio ni en el PDF (p. 9) | C6 | SSM SecureString, `.env` 0600 root por SSH, IAM con MFA, valores solo por stdin | AWS: credenciales distintas por ambiente, `.env` 0600 y 0 valores en el repositorio. Gitleaks | ACTIVO=0; 51 HISTÓRICO; 2 RESIDUAL explicados | [verify 193653Z](fase4/verify-infra-20261102T193653Z.log.txt) l. 64-76, [historial](auditoria/20261103T162946Z-history-summary.txt) | **PASS** |
| 7 | «Reconstruyen Jenkins, SonarQube y registro desde cero con un comando» (P1.2) | C3, C5 | `bootstrap-all.sh --apply --approve ci,nexus` | Solo `--plan` en AWS | Pendiente en AWS | [README](../../../infra/README.md#flujo-de-aprovisionamiento-con-control-de-costos) | **BLOCKED** |
| 8 | Servicios núcleo desplegados en los tres ambientes (p. 4, alcance de la Parte 1) | E1.5 (no es HU-01) | Ambientes aprovisionados y aislados, sin aplicaciones | — | No cabe en la cuota (5 vCPU) ni en el tamaño `t3.small` | [conflicto](../../../infra/README.md#ambientes-dev-stage-y-prod-servidores-por-pares) | **BLOCKED** (cuota; otra HU) |
| 9 | Estructura `infra/bootstrap/` (p. 6) | — | `infra/bootstrap-*.sh` e `infra/bootstrap/{lib,host,jenkins,sonarqube,nexus,registry}/` | Revisión | Conforme | [infra/README.md](../../../infra/README.md) | **PASS** |
| 10 | Evidencias verificables con capturas (p. 6 y p. 9, n.º 2) | Todos | Registros y reportes enmascarados en el repositorio | — | Faltan las capturas | [capturas/](capturas/README.md) | **BLOCKED** (manual) |
| 11 | Evidencias de HU-01: E1 salida del bootstrap, E2 diagrama, E3 commit, E4 captura | — | — | — | E1: falta el comando único en AWS; E2 PASS; E3 PASS; E4: falta la captura | [README de evidencias](README.md) | E1 **BLOCKED** · E2 **PASS** · E3 **PASS** · E4 **BLOCKED** |
| 12 | Apagar o destruir los recursos tras la evaluación (p. 9, n.º 4) | — | Parada automática a las 4 h, `teardown.sh` y destrucción en CloudShell | Parada controlada en AWS (2026-11-02) | Mecanismo listo; la destrucción final es del equipo | [teardown](fase4/teardown-stop-20261102T194755Z.log.txt) | **PASS** (mecanismo) |

## C. Matriz de evidencias

Tipo: **AWS** = ejecución real en la cuenta; **Local** = Docker Desktop o el contenedor Linux
auxiliar; **Doc.** = documento o configuración. Fechas en UTC.

| Evidencia | Archivo | Criterio | Tipo | Fecha | Resultado |
|---|---|---|---|---|---|
| Salidas de los *bootstrap* | [`fase4/`](fase4/) (25 registros enmascarados), [`local/`](local/) | C1, C3, C5 | AWS / Local | 2026-11-02 / 2026-10-31 | Despliegue completo |
| Idempotencia (partes) | [red 2.ª](fase4/bootstrap-network-20261102T175849Z.log.txt), [secretos 2.ª](fase4/bootstrap-secrets-20261102T181248Z.log.txt), [IAM](10-iam-creacion-e-idempotencia.txt) | C3 | AWS | 2026-11-01/02 | `created=0 updated=0` |
| Idempotencia, persistencia y rotación del registro y Jenkins | [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) | C1, C3 | Local | 2026-11-03 04:00 | 22/22 |
| TLS y autenticación del registro | [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt), [registro](auditoria/20261103T041534Z-prueba-local-registro.txt) | C1, C6 | Local | 2026-11-03 04:00 y 04:08 | 401 sin credenciales; 200 con `ci`; HTTP sin TLS rechazado |
| Jenkins publica y descarga (digest comparado) | [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) §4 | C1 | Local | 2026-11-03 | PASS |
| Rotación (la contraseña anterior se rechaza) | [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) §5 | C1, C6 | Local | 2026-11-03 | PASS |
| Persistencia y recuperación | [integración local](auditoria/20261103T041534Z-integracion-local-hu01.txt) §6; [14 §9](14-despliegue-aws-fase4.md) | C1, C3 | Local / AWS | 2026-11-03 / 2026-11-02 | Local PASS; EBS conservado en AWS; recuperación en AWS pendiente |
| Aislamiento de red | [verify 193653Z](fase4/verify-infra-20261102T193653Z.log.txt) | C2 | AWS | 2026-11-02 | 15 PASS de configuración; tráfico entre ambientes pendiente |
| Servicios funcionando | [verify 193451Z](fase4/verify-infra-20261102T193451Z.log.txt), [Jenkins](fase4/bootstrap-jenkins-20261102T192736Z.log.txt), [SonarQube](fase4/bootstrap-sonarqube-20261102T192956Z.log.txt) | C1 | AWS | 2026-11-02 | 22/0/1 |
| Diagrama de ambientes, subredes y grupos de seguridad | [infra-ambientes.md](../../arquitectura/infra-ambientes.md) | C2 | Doc. | 2026-11-03 | 31 reglas descritas |
| Commit que eliminó las credenciales | [auditoria/20261103T160739Z-commit-3a43855-credenciales.txt](auditoria/20261103T160739Z-commit-3a43855-credenciales.txt) | C4 | Repositorio | 2026-11-03 | 4 variables `:?`; valores eliminados (solo contados) |
| Reporte de Gitleaks | [árbol](auditoria/20261103T162946Z-worktree-summary.txt), [historial](auditoria/20261103T162946Z-history-summary.txt) | C4, C6 | Local | 2026-11-03 16:29 | ACTIVO=0 (426 archivos); historial 68 = 51 HISTÓRICO + 13 PRUEBA + 4 RESIDUAL |
| Captura de Gitleaks | [capturas/README.md](capturas/README.md) | C4, C6 | — | — | **Pendiente** (manual) |
| Prerrequisitos de la estación de trabajo | [16:28, 13 s](auditoria/20261103T162805Z-prerrequisitos-wsl.txt) y [15:39, 26 min antes de la corrección](auditoria/20261103T153946Z-prerrequisitos-wsl.txt) | C5 | Local (WSL) | 2026-11-03 | `pass=17 warn=1 fail=0` |
| Análisis estático | [auditoria/20261103T162716Z-shellcheck-hu01.txt](auditoria/20261103T162716Z-shellcheck-hu01.txt) | C3, C5 | Local | 2026-11-03 16:27 | 0 hallazgos en 33 scripts, con el sha256 de cada uno. El intermedio de las 16:08 (5 avisos `info` SC2031, corregidos) queda superado |
| Comprobaciones unitarias | [auditoria/20261103T162542Z-comprobaciones-unitarias-hu01.txt](auditoria/20261103T162542Z-comprobaciones-unitarias-hu01.txt) | C2, C3 | Local | 2026-11-03 16:25 | 34/34 |
| Ensayo de reconstrucción | [ensayo-reconstruccion/README.md](ensayo-reconstruccion/README.md) → `aws/ensayo-nivel1/` | C5 | — | — | **Pendiente** (otro integrante) |
| Pruebas en AWS | [aws/README.md](aws/README.md) | C1, C2, C3 | — | — | **Pendientes** (autorización) |

## D. Resultados de pruebas

| Prueba | Comando | Fecha (UTC) | Resultado | Limitaciones |
|---|---|---|---|---|
| Sintaxis | `bash -n` de los 33 scripts | 2026-11-03 16:08 | 33/33 | — |
| Análisis estático | ShellCheck v0.11.0 `-x -S style` | 2026-11-03 16:27 (33 scripts) | 0 hallazgos; control SC2086 detectado | — |
| Unitarias | Roles, guarda de cuota, registro, `daemon.json`, Compose y planes | 2026-11-03 16:25 | 34/34 | AWS simulado en la guarda de cuota |
| Integración local | Contenedor Linux: secretos, registro (×4), `verify-infra`, *build* de Jenkins y `crane`, rotación, persistencia | 2026-11-03 04:00 | 22/22 | Sin SSH, VPC ni grupos de seguridad. Los scripts que ejercita no han cambiado desde entonces (sha256 en el reporte de ShellCheck) |
| Registro (scripts del host) | `prepare.sh` y `configure.sh` | 2026-11-03 04:08 | 21/21 | Git Bash en NTFS |
| Prerrequisitos | `check-prerequisites.sh` en WSL | 2026-11-03 16:28 | `pass=17 warn=1 fail=0` en 13 s | El aviso: cambios sin confirmar. La ejecución de las 15:39 tardó 26 min (`git status` sobre OneDrive) y motivó la corrección |
| Secretos | `scan-secrets.sh` (árbol de trabajo e historial) | 2026-11-03 16:29 | ACTIVO=0 en 426 archivos; historial 68 = 51 HISTÓRICO + 13 PRUEBA + 4 RESIDUAL | 2 RESIDUAL y 51 HISTÓRICO (sección F) |
| Estado de AWS (lectura) | `aws-session.sh status` y `teardown.sh --stop` | 03:44 y 15:37 | A las 03:44: todo detenido. A las 15:37: **sesiones caducadas**, sin lectura posible | Requiere el inicio de sesión del responsable |
| Idempotencia, aislamiento y reconstrucción en AWS | `test-idempotency.sh`, `test-isolation.sh` y el ensayo | — | **No ejecutadas** | Requieren autorización y MFA |

Nota: los cambios de hoy por la tarde (`test-idempotency.sh`, `test-isolation.sh` y el nuevo
`check-prerequisites.sh`) están validados con `bash -n`, ShellCheck y las comprobaciones unitarias
de sus planes; `check-prerequisites.sh` se ejecutó realmente en WSL. Sus partes que tocan AWS solo
pueden probarse en AWS.

## E. Costes (estimaciones con los precios de referencia de `infra/config/aws.env`; la factura real está en Billing y llega con retraso)

| Concepto | USD |
|---|---|
| Presupuesto absoluto · línea operativa | 15 · 12 |
| **Acumulado estimado** (ledger de los scripts: sesión del 2026-11-02 y EBS desde entonces) | **0.24** |
| Recursos que facturan ahora | 55 GiB de EBS de `ci` y `nexus`: 0.145 USD/día |
| Prueba de idempotencia (ensayo de nivel 1) | ≤ 0.21 |
| Prueba de aislamiento | ≈ 0.15, más 0.079 USD/día de EBS de los ambientes (30 GiB) desde su creación |
| Dos demostraciones de 3 h | ≈ 1.25 |
| EBS hasta el 2026-11-22 (55 + 30 GiB) | ≈ 2.66 + 1.42 |
| Reserva de transferencia | 0.27 |
| **Previsto hasta el 2026-11-22** | **≈ 6.4** |
| Margen frente a 15 USD y frente a 12 USD | ≈ 8.6 y ≈ 5.6 |

Los créditos no se consideran presupuesto. `bootstrap-servers.sh` rechaza cualquier operación cuya
estimación supere los 15 USD.

## F. Impedimentos

| Impedimento | Tipo | Efecto | Cómo se resuelve |
|---|---|---|---|
| Las sesiones de AWS caducaron. Solo el responsable puede iniciarlas (MFA en el navegador) | AWS/permisos | No se pudo verificar hoy la cuota ni el inventario | G1 |
| Ninguna prueba en AWS está autorizada | AWS/permisos | C1, C2 y C3 en BLOCKED | G2 y G3 |
| La cuota de 5 vCPU (leída el 2026-11-01) solo permite dos servidores a la vez; la aprobación de un aumento no es segura en una cuenta del plan gratuito | Cuota | Ambientes por pares; los servicios núcleo en tres ambientes (E1.5) no caben | Aceptado en el diseño; G1 confirma la cuota |
| El único usuario operador tiene la MFA del responsable | AWS/permisos y dependencia del equipo | Otro integrante no puede autenticarse solo | Opción A del ensayo: B ejecuta y el responsable escribe la MFA |
| El ensayo de reconstrucción debe hacerlo otra persona | Dependencia del equipo | C5 en BLOCKED | H1 |
| Faltan las capturas de pantalla | Evidencia manual | E4 y el informe PDF | G4 |
| Desplegar los servicios núcleo en dev, stage y prod (p. 4) | Dependencia de otra HU (E1.5) y cuota | Fuera de HU-01; riesgo en la rúbrica («ambientes operativos») | Decisión de E1.5 (G5) |
| 2 RESIDUAL de Gitleaks: comentarios de las migraciones V2 y V3 del código base con la contraseña trivial de usuarios de prueba | Dependencia de otra HU (E2.6) | No son secretos de infraestructura; riesgo si se despliegan en stage o prod | E2.6 (las migraciones aplicadas no se modifican) |
| `git status` sobre OneDrive desde WSL tarda decenas de minutos | Técnico (resuelto) | Podía agotar la ventana MFA | Limitado a 90 s y antes del inicio de sesión; recomendación de clonar en WSL |

## G. Acciones obligatorias del usuario

Todas se hacen **desde WSL en la raíz del repositorio**, mejor en un clon dentro de `~/` (sección F).
Las credenciales y la MFA se escriben **solo en la página de AWS**, nunca en el chat.

| N.º | Qué hacer | Por qué no puede hacerlo el asistente | Comando | Resultado esperado | Evidencia que entregar | MFA | Coste | Riesgo |
|---|---|---|---|---|---|---|---|---|
| G1 | Leer la cuota real de vCPU y el inventario | Requiere su MFA (sesiones de administración y de operador) | `bash infra/aws-session.sh login bootstrap` → `bash infra/bootstrap-quota.sh` → `bash infra/aws-session.sh logout bootstrap` → `bash infra/aws-session.sh login operator` → `bash infra/teardown.sh --stop` | `cuota actual en us-east-2: N vCPU`; `no hay instancias de circleguard en ejecución` | La línea de la cuota. Si N ≠ 5, se actualiza `QUOTA_VCPU_LIMIT` | Sí | 0 | Ninguno (solo lectura) |
| G2 | Autorizar y lanzar la prueba de idempotencia, que despliega el registro y prueba Jenkins → registro. Recomendado: que la ejecute el otro integrante (H1) para cubrir también C5 | Requiere autorización de gasto y MFA | `bash infra/test-idempotency.sh --apply --approve ci,nexus` (escribir `PROBAR IDEMPOTENCIA`) | `RESULTADO: IDEMPOTENTE (todas las comprobaciones en PASS)` e `instancias detenidas al terminar` | `~/.circleguard/idempotency/<marca>/masked/*` → `docs/evidencias/hu-01/aws/idempotencia/` | Sí (sesión de menos de 1 h) | ≤ 0.21 USD | Si cambió su IP, actualiza la regla 22. Detalle debajo de la tabla |
| G3 | Autorizar y lanzar la prueba de aislamiento, después de G2 | Crea recursos nuevos facturables; requiere MFA | `bash infra/test-isolation.sh --apply --phases=1,2,3`; nuevo `login operator`; `bash infra/test-isolation.sh --apply --phases=4,5` (frase `PROBAR AISLAMIENTO`) | Las cinco fases en PASS e `instancias detenidas al terminar` | Las dos carpetas `masked/` → `docs/evidencias/hu-01/aws/aislamiento/` | Sí (dos sesiones) | ≈ 0.15 USD + 0.079 USD/día de EBS | Crea 3 instancias y 3 volúmenes que permanecen, detenidos, hasta destruirlos |
| G4 | Tomar las capturas | Requieren una persona frente a la pantalla | Ver [capturas/README.md](capturas/README.md) | — | Los PNG de esa lista en `docs/evidencias/hu-01/capturas/` | Algunas, durante G2 o G3 | 0 | No mostrar contraseñas, IP públicas ni el número de cuenta |
| G5 | Decidir con el equipo o el profesor el alcance de los ambientes: HU-01 entrega ambientes aislados y aprovisionados; las aplicaciones (y su cuota y tamaño) llegan con E1.5 | Decisión académica y económica | — | Decisión registrada (por ejemplo, en el acta del sprint) | Referencia a la decisión | No | 0 | Sin ella, la rúbrica podría valorar «ambientes no operativos» |
| G6 | Revisar y confirmar los cambios (sección I) y publicar la rama | Los commits y el push los hace el usuario | `bash infra/scan-secrets.sh --worktree` (debe dar PASS) y después sus commits | — | — | No | 0 | — |
| G7 | Al terminar la evaluación, destruir la infraestructura | Destructivo; por diseño se hace desde CloudShell con el usuario de teardown | [Detener o destruir](../../../infra/README.md#detener-o-destruir) | Inventario vacío | Salida de `teardown-cloudshell.sh` | Sí | Detiene el gasto | Pérdida de los datos de las herramientas (esperada) |

Detalles de G2:
- **Al terminar:** la sesión es de 45-55 min. Puede quedar desplegado el registro y se recrean
  Jenkins y Nexus una vez.
- **Acumulado tras G2:** ≈ 0.45 USD; tras G3, ≈ 0.6 USD más el EBS.

## H. Acciones de otros integrantes

| N.º | Quién | Qué | Instrucciones | Evidencia |
|---|---|---|---|---|
| H1 | Un integrante distinto del responsable | Ensayo de reconstrucción de nivel 1 en su WSL. Su paso 6 **es** la prueba G2, así que no se repite | [ensayo-reconstruccion/README.md](ensayo-reconstruccion/README.md), con el mensaje listo para enviar | `docs/evidencias/hu-01/aws/ensayo-nivel1/` (prerrequisitos, secretos, plan, `idempotencia/` y `ACTA.md`) |
| H2 | Equipo | Incluir capturas, enlaces y evidencias en el informe PDF de la Parte 1 | [capturas/README.md](capturas/README.md) y este informe | PDF de entrega |

## I. Commits sugeridos (no ejecutados)

| N.º | Mensaje | Archivos |
|---|---|---|
| 1 | `feat(registry): registro CNCF Distribution en el servidor nexus` | `infra/bootstrap-registry.sh`, `infra/bootstrap/registry/`, `infra/bootstrap-nexus.sh`, `infra/bootstrap/nexus/docker-compose.yml`, `infra/bootstrap/host/setup-docker.sh`, `infra/config/aws.env`, `infra/config/secrets.catalog`, `docs/arquitectura/registro-artefactos.md` |
| 2 | `feat(jenkins): publicar en el registro con crane y rotar su contraseña` | `infra/bootstrap/jenkins/{Dockerfile,docker-compose.yml}`, `infra/bootstrap-jenkins.sh`, `infra/bootstrap/lib/remote.sh`, `infra/rotate-registry-password.sh`, `infra/verify-infra.sh` |
| 3 | `feat(envs): servidores de ambiente por pares dentro de la cuota de vCPU` | `infra/bootstrap/lib/{aws,common}.sh`, `infra/bootstrap-servers.sh`, `infra/bootstrap-env.sh`, `infra/bootstrap-all.sh`, `infra/bootstrap-quota.sh`, `infra/config/envs/*.env`, `infra/test-isolation.sh` |
| 4 | `test(infra): idempotencia integral, prerrequisitos y escaneo de secretos` | `infra/test-idempotency.sh`, `infra/check-prerequisites.sh`, `infra/scan-secrets.sh` |
| 5 | `docs(hu-01): informe final del Sprint 1, ensayo y evidencias locales` | `infra/README.md`, `docs/arquitectura/infra-ambientes.md`, `docs/evidencias/hu-01/` (README, 15-18, este informe, `capturas/`, `ensayo-reconstruccion/`, `aws/` y `auditoria/`) |

## J. Veredicto final

- **¿Está HU-01 terminada?** No.
- **¿Pueden los seis criterios estar en PASS?** Sí, si las pruebas en AWS (G2 y G3) y el ensayo (H1)
  dan PASS. El código, la documentación y los procedimientos están listos y validados en local.
  El coste previsto (≈ 6.4 USD) cabe en 15 USD.
- **¿Qué falta exactamente?**
  1. La ejecución autorizada en AWS de `test-idempotency.sh` (C1 y C3) y de `test-isolation.sh` (C2).
  2. El ensayo de reconstrucción por otro integrante (C5).
  3. Las capturas.
  4. La decisión sobre el alcance de los ambientes frente a E1.5.
  5. Los commits.
- **¿Qué lo impide?** La MFA y la autorización de gasto del responsable de AWS, que el asistente
  no puede ni debe suplir, y la participación de otro integrante.
- **Usuario:** G1 → G2 (con H1) → G3 → G4 → G5 → G6 y, al final de la evaluación, G7.
- **Otro integrante:** H1 (que incluye G2).
- **Siguiente paso recomendado:**
  1. Confirmar los cambios.
  2. Leer la cuota (G1).
  3. Hacer una videollamada en la que el otro integrante ejecute el ensayo de nivel 1 mientras el
     responsable escribe la MFA. Ese ensayo cubre C1, C3 y C5 de una vez.
  4. En otra sesión, la prueba de aislamiento (G3, C2).

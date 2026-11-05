# 14 · Despliegue en AWS (fase 4, 2026-11-02)

Ejecución controlada del plan de la [evidencia 13](13-plan-despliegue-fase3.txt) en `us-east-2a`
(topología B). Horas en UTC. Cada resultado procede de un registro real; las copias enmascaradas
están en [`fase4/`](fase4/) (los registros con la extensión `.log.txt`, porque `.gitignore` excluye
`*.log`) y los originales siguen intactos en `infra/logs/` y `infra/security/reports/`, ignorados por
Git. Cada copia indica el sha256 de su **original**; la copia, al estar enmascarada, tiene otro hash.
El diagnóstico `diag-6a-autorizacion.txt` reúne tres originales (`infra/logs/diag-6a-20261102/`,
con sus sha256 en la cabecera).

Clasificación usada en todas las evidencias de HU-01: **PASS**, **PARTIAL**, **FAIL** y **NOT VERIFIED**.

Enmascarado aplicado a las copias: número de cuenta, identificadores únicos de IAM, mensaje de
autorización codificado y último octeto de IP públicas. Secretos: Gitleaks sobre las copias da
ACTIVO=0 (21:58), y una comparación en memoria de los 35 valores de SSM dio 0 apariciones en el
repositorio y en los 112 registros originales escritos hasta las 19:43. Los registros posteriores
(parada, Gitleaks final y ShellCheck) solo están cubiertos por Gitleaks.

## 1. Estado final (comprobado a las 19:48)

| Recurso | Estado |
|---|---|
| `circleguard-ci` `i-010843f2125041114` | **stopped** desde las 19:47:30 · m7i-flex.large · `ami-0fc53b217ec1ad816` · IMDSv2 obligatorio · apagado iniciado por la instancia = `stop` |
| `circleguard-nexus` `i-08c990919adc43fa1` | **stopped** desde las 19:47:30 · igual |
| Volúmenes | `vol-07b111aa93b1cec4f` (30 GiB) y `vol-06a01333bd08c9382` (25 GiB), gp3 cifrados, **conservados** y adjuntos; ninguna instancia terminada |
| Red | VPC `vpc-017214d72e444769e`, IGW, 4 subredes, 1 tabla de rutas y 5 grupos de seguridad con 31 reglas (sin NAT, Elastic IP ni balanceadores) |
| IAM | operador **v3** = plantilla · teardown **v2** = plantilla · lectura v1 = plantilla |
| Secretos | 35 parámetros SecureString (versión 1) y 4 pares de llaves ed25519 |
| Servicios (al parar) | Jenkins, SonarQube y PostgreSQL `healthy` en `ci`; Nexus `healthy` en `nexus` con el EULA **pendiente** |

## 2. Trazabilidad: criterio → prueba → resultado → evidencia

| Criterio | Prueba | Resultado | Evidencia |
|---|---|---|---|
| C1 · Servidores para Jenkins, SonarQube y Nexus | Creación (6b), bootstrap de las herramientas (8-9) y `verify-infra.sh --health` (10) | **PARTIAL**: Jenkins PASS · SonarQube PASS · PostgreSQL PASS · Nexus PARTIAL (desplegado y en línea; EULA pendiente) | `bootstrap-servers-20261102T191128Z.log.txt`, `bootstrap-{jenkins,sonarqube,nexus}-*.log.txt`, `verify-infra-20261102T193451Z.log.txt` |
| C2 · dev, stage y prod aislados | `verify-infra.sh` completo (11): subred y grupo propios, sin reglas entre ambientes, flujos entre servidores | **PARTIAL**: configuración verificada por reglas; **sin prueba con tráfico** entre ambientes (no hay servidores de ambiente); su cierre requiere la aceptación del equipo | `verify-infra-20261102T193653Z.log.txt`, `bootstrap-network-20261102T175528Z.log.txt` |
| C3 · Bootstrap idempotentes | 2.ª ejecución de red (`unchanged=28`), secretos (`unchanged=43`) e IAM (convergencia) | **PARTIAL**: falta `bootstrap-all.sh` dos veces con *snapshot* y `diff` | `bootstrap-network-20261102T175849Z.log.txt`, `bootstrap-secrets-20261102T181248Z.log.txt`; procedimiento en la [evidencia 15](15-procedimiento-idempotencia-aws.md) |
| C4 · Credenciales de Compose fuera del repositorio | Sin cambios en esta fase | PASS (commit `3a43855`) | [README](README.md) |
| C5 · Sin configuración manual no documentada | Instalación solo con los scripts y la documentación | **PARTIAL**: Nexus espera la decisión del EULA; la reconstrucción desde cero no se ha ensayado | Esta evidencia y la [16](16-nexus-eula.md) |
| C6 · Credenciales con un mecanismo seguro | SSM SecureString, `.env` 0600 root, comparación en memoria, Gitleaks | **PASS** | `bootstrap-secrets-20261102T181015Z.log.txt`, `verify-infra-20261102T193653Z.log.txt`, `20261102T194438Z-worktree-summary.txt` |

## 3. Cronología y archivos

| Hora | Paso | Resultado | Archivo en `fase4/` |
|---|---|---|---|
| 16:36 | 4 · red (1.er intento) | Se detiene en `CreateSubnet`: `UnauthorizedOperation` sobre la VPC | `bootstrap-network-20261102T163637Z.log.txt` |
| 17:09 | IAM · operador v2 | `CreateOnlyInsideCircleGuardVpc`; `updated=1` | `bootstrap-iam-20261102T170920Z.log.txt` |
| 17:55 | 4 · red | `created=10 updated=45 unchanged=4` | `bootstrap-network-20261102T175528Z.log.txt` |
| 17:58 | 4 · idempotencia | `created=0 updated=0 unchanged=28` | `bootstrap-network-20261102T175849Z.log.txt` |
| 18:10 | 5 · secretos | `created=43` (valores no mostrados) | `bootstrap-secrets-20261102T181015Z.log.txt` |
| 18:12 | 5 · idempotencia | `unchanged=43` | `bootstrap-secrets-20261102T181248Z.log.txt` |
| 18:15 | 6a (1.er intento) | El `UnauthorizedOperation` del operador quedó como nota (defecto) | `bootstrap-servers-20261102T181513Z.log.txt` |
| 18:21-18:28 | 6a · diagnóstico | `ec2:Owner = amazon` en la AMI de Canonical | `diag-6a-autorizacion.txt` |
| 18:36 | `cg_dry_run` corregido | El mismo dry-run falla de forma visible | `bootstrap-servers-20261102T183655Z.log.txt` |
| 18:51 | IAM · operador v3 | `RunOnlyPinnedUbuntuImage` (`ec2:ImageID`); `updated=1` | `bootstrap-iam-20261102T185123Z.log.txt` |
| 18:56 | 6a | «permiso verificado con --dry-run: ec2 run-instances» ×2 | `bootstrap-servers-20261102T185657Z.log.txt` |
| 19:08 | Seguridad previa | Gitleaks: árbol de trabajo ACTIVO=0; historial 13 commits | `scan-secrets-20261102T190815Z.log.txt`, `20261102T190815Z-history-summary.txt` |
| 19:11 | 6b · servidores | `created=2`; 7.59 de 15 USD en la comprobación previa | `bootstrap-servers-20261102T191128Z.log.txt` |
| 19:16 y 19:24 | 6c | `instanceInitiatedShutdownBehavior = stop` ×2 | `paso6c-20261102T191654Z.log.txt`, `paso6c-20261102T192412Z.log.txt` |
| 19:27 | 8 · Jenkins | `created=9 updated=3 unchanged=5` | `bootstrap-jenkins-20261102T192736Z.log.txt`, `hu01-hostcheck-ci-20261102T192921Z.log.txt` |
| 19:29 | 8 · SonarQube | `created=3 updated=1 unchanged=10` | `bootstrap-sonarqube-20261102T192956Z.log.txt`, `hu01-hostcheck-ci-20261102T193238Z.log.txt` |
| 19:32 | 9 · Nexus | `created=7 updated=4 unchanged=2 planned=1` (EULA) | `bootstrap-nexus-20261102T193238Z.log.txt`, `hu01-hostcheck-nexus-20261102T193443Z.log.txt` |
| 19:34 | 10 · salud | `pass=22 fail=0 pendiente=1` | `verify-infra-20261102T193451Z.log.txt` |
| 19:36 | 11 · completo | `pass=53 fail=0 pendiente=5` | `verify-infra-20261102T193653Z.log.txt` |
| 19:44 | Seguridad final | Gitleaks: árbol de trabajo ACTIVO=0 | `scan-secrets-20261102T194437Z.log.txt`, `20261102T194438Z-worktree-summary.txt` |
| 19:46 | 14 · parada | `updated=1`: las dos instancias detenidas | `teardown-stop-20261102T194644Z.log.txt` |
| 19:48 | 14 · comprobación | «no hay instancias de circleguard en ejecución» | `teardown-stop-20261102T194755Z.log.txt` |
| 21:42 | ShellCheck verificable | 26 scripts, 0 hallazgos, control positivo SC2086 | `20261102T214225Z-shellcheck-hu01.txt` |

## 4. Temporizadores de parada (4 h)

| Host | Instalado | Comprobación en el host | Disparo previsto |
|---|---|---|---|
| `ci` | 19:28:15, por el bootstrap de Jenkins (SonarQube lo encontró `UNCHANGED`) | `enabled` · `active` · **`waiting`**, `OnActiveSec=4h` | 23:28:14 |
| `nexus` | 19:33:14, por el bootstrap de Nexus | `enabled` · `active` · **`waiting`** | 23:33:13 |

`verify-infra.sh` lo confirmó en los pasos 10 y 11. Las instancias se detuvieron a mano antes del
disparo; el temporizador se rearma con 4 h en cada arranque. La **prueba real del apagado** (paso 12)
no se ha ejecutado.

## 5. Incidentes y correcciones

| Incidente | Causa | Corrección | Commit |
|---|---|---|---|
| `CreateSubnet` denegado (16:37) | `CreateNetworkOnlyWithProjectTag` exigía `aws:RequestTag` también sobre la VPC existente | `CreateOnlyInsideCircleGuardVpc` (operador v2) | `536771a` |
| Teardown con `PLAN` en el plan de IAM | Orden de sentencias distinto del de la v2 creada desde la consola | Plantilla alineada con la v2 (se conserva la v2) | `b18f27c` |
| 6a dio por bueno un `UnauthorizedOperation` | `cg_dry_run` decidía por la capacidad `read`, no por la identidad; el motivo de los rechazos salía vacío | Decide por la identidad y usa `cg_aws_error` | `7eb262b` |
| `RunInstances` denegado sobre la AMI | AWS evalúa `ec2:Owner = amazon` (la AMI es de la cuenta 099720109477) | AMI fijada (`AMI_ID`) y `RunOnlyPinnedUbuntuImage` con `ec2:ImageID` (operador v3) | `3632068` |
| Rol de operación denegado (19:24) | MFA de más de 1 h | Nuevo inicio de sesión del operador (19:25) | — |
| Primer Gitleaks (19:06) con «0 bytes» | Ruta temporal de Git Bash no montable en Docker | Repetido con ruta Windows; reportes `20261102T190651Z-*` **inválidos** (conservados, no son evidencia) | — |
| ShellCheck de las 19:09 con reporte vacío | ShellCheck no imprime nada sin hallazgos y la ejecución no guardó metadatos | Reporte verificable de las 21:42 | — |

## 6. Seguridad

- **Gitleaks v8.30.1** (imagen `zricethezav/gitleaks:v8.30.1`): árbol de trabajo **ACTIVO=0** (9 PRUEBA,
  2 RESIDUAL) a las 19:08 y a las 19:44; historial de 13 commits: 68 hallazgos (51 HISTÓRICO, 13
  PRUEBA, 4 RESIDUAL), informativo. Valores redactados.
- **ShellCheck v0.11.0** (`sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d`):
  26 scripts idénticos a `3632068`, **0 hallazgos** (`{"comments":[]}`), control positivo SC2086
  detectado. El reporte de las 19:09 (`20261102T190923Z-shellcheck.txt`, 0 bytes) **no** es evidencia.
- **Secretos:** 35 SecureString; `.env` de Jenkins, SonarQube y Nexus en `0600 root`; 0 apariciones de
  los valores en el repositorio y en los registros; credenciales distintas por ambiente.
- **Exposición:** Jenkins (8080), SonarQube (9000) y Nexus (8081) no responden desde Internet y sí por
  túnel SSH; el registro Docker de Nexus no está expuesto.

## 7. Coste [ESTIMADO]

- **Sesión del 2026-11-02:** `ci` 35 min 37 s y `nexus` 35 min 9 s encendidas a 0.10076 USD/h cada una
  (EC2 e IPv4), más el EBS de esas horas y la transferencia de salida: **≈ 0.13 USD**.
- **Mientras estén detenidas: ≈ 0.145 USD/día**, calculado como 55 GiB × 0.08 USD/GB-mes (precio de
  referencia de gp3 en us-east-2, `infra/config/aws.env`) ÷ 30.42 días = 0.1447 (`ci` 0.0789 y
  `nexus` 0.0658).
  - **Incluye:** el almacenamiento de los dos volúmenes gp3 con su rendimiento base (3000 IOPS y
    125 MB/s, sin extras).
  - **No incluye:** EC2 (no se cobra con la instancia detenida), la IPv4 pública (se libera al
    detener), la transferencia de datos, *snapshots* (no hay), parámetros SSM de nivel Standard y
    llaves administradas de KMS (sin cuota mensual según los precios de referencia), impuestos ni
    otros recursos de la cuenta.
  - **No es el coste total de AWS:** es la estimación del único concepto con cargo fijo previsto. El
    importe real se comprueba en Billing.
- **Límites:** presupuesto absoluto de **15 USD** y línea operativa de parada de **12 USD**. El
  acumulado estimado es ≈ 0.13 USD de la sesión más el EBS de los días que pasen.
- **Facturación:** AWS factura con retraso, y los créditos (100.0 USD en la última consulta) no son
  un límite de gasto.

## 8. Aislamiento de ambientes: suficiencia de la evidencia

- **Comprobado:** cada ambiente tiene subred y grupo de seguridad propios, ninguna regla entre
  ambientes y solo referencias a `ci` y `nexus` (paso 11, 15 comprobaciones PASS). Con tráfico real se
  probó `ci → nexus:8081` permitido y `nexus → ci:8080/9000` bloqueados.
- **No comprobado:** tráfico entre ambientes, porque la topología B aprobada no crea servidores de
  ambiente. Los scripts de HU-01 no tienen otra forma de probarlo: `verify-infra.sh --isolation` usa
  `nc` desde los hosts existentes. La alternativa de AWS sin tráfico, *Reachability Analyzer*, analiza
  rutas entre recursos con interfaz de red (no hay ninguna en las subredes de los ambientes),
  necesitaría permisos que los roles de HU-01 no tienen (`ec2:CreateNetworkInsightsPath` y
  `ec2:StartNetworkInsightsAnalysis`) y tiene coste por análisis [según la documentación de AWS; no
  verificado en esta fase].
- **Recomendación:** para el alcance de HU-01 (topología B), la evidencia de configuración es la que
  corresponde, siempre que se declare la limitación. Una prueba con tráfico entre ambientes pertenece
  a la historia que despliegue sus servidores (`bootstrap-env.sh`); hacerla ahora exigiría crear
  recursos y una autorización aparte.

## 9. Persistencia: configurada frente a probada

| Elemento | Configurado (Compose y bootstrap) | Probado |
|---|---|---|
| Jenkins | Volumen `jenkins_home`; JCasC montado en solo lectura; *healthcheck* de `/login`; `restart: unless-stopped` | Arranque y salud en AWS (19:28) y en local |
| SonarQube | Volúmenes `sonarqube_data`, `_extensions` y `_logs`; `depends_on: db` con `service_healthy`; *healthcheck* de estado `UP` | Arranque, salud y uso de PostgreSQL (19:32) |
| PostgreSQL | Volumen `sonar_db_data`; *healthcheck* `pg_isready` | Salud (19:30-19:43) |
| Nexus | Volumen `nexus-data`; *healthcheck* de la API de estado | Arranque y salud (19:34) |
| Datos en AWS | Los volúmenes Docker están en el EBS raíz, que se conserva al detener (comprobado: los dos volúmenes siguen existiendo) | **No probado**: tras la parada de las 19:47 no se ha vuelto a arrancar ninguna instancia |

Hay que distinguir tres cosas:
- **Volúmenes EBS conservados (comprobado):** los dos volúmenes siguen existiendo, adjuntos a sus
  instancias detenidas (lectura de las 22:17).
- **Persistencia configurada (comprobada en la configuración):** volúmenes Docker con nombre sobre ese
  EBS, *healthchecks*, `restart: unless-stopped` y dependencias.
- **Recuperación de los datos y de los servicios tras un arranque: no demostrada.** Ninguna instancia
  se ha vuelto a arrancar desde la parada de las 19:47.

La 1.ª ejecución de la prueba de idempotencia (evidencia 15, comprobación 2 de la sección 7)
permitirá comprobar esa recuperación: que los servicios vuelvan a estar sanos y que las contraseñas
gestionadas sigan siendo válidas. El mensaje «SonarQube en estado UP con base de datos PostgreSQL
persistente» de los registros es la comprobación de que SonarQube usa PostgreSQL, no una prueba de
recuperación.

## 10. Pendiente

1. **C3:** idempotencia completa con `bootstrap-all.sh` dos veces, *snapshots* y `diff` (procedimiento
   en la [evidencia 15](15-procedimiento-idempotencia-aws.md)). Requiere arrancar las instancias.
2. **Nexus:** decisión del equipo sobre el EULA ([evidencia 16](16-nexus-eula.md)); hasta entonces no
   hay acceso anónimo configurado, realm DockerToken ni repositorio `circleguard-docker`.
3. **Paso 12:** prueba real de la parada automática (opcional).
4. **Reconstrucción desde cero** siguiendo solo la documentación (C5).
5. **Captura de pantalla** del escaneo de secretos (la hace el equipo).
6. Ningún registro de `infra/logs` se borra; el de las 16:36 contiene el número de cuenta en el
   original y solo se entrega su copia enmascarada.

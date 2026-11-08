# Sesión IAG · 2026-11-08 · HU-06 en AWS

| Campo | Valor |
|---|---|
| Fecha | 2026-11-08 |
| Historias | HU-06 · Entrega continua y promoción |
| Rama | `HU-06-_Entrega-continua-y-promoción` |
| Herramienta | OpenCode |
| Modelo | DeepSeek V4.1 Flash 1017 (`deepseek/deepseek-flash`) |
| Nivel de uso | Nivel 3 · colaboración con IAG |
| Participantes | Equipo CircleGuard + asistente |

> Esta sesión es la ejecución real de lo diseñado el 2026-11-05. HU-07 sigue en su propia rama.

---

## Solicitud (síntesis de la interacción)

Completar HU-06 de extremo a extremo con evidencia real en AWS: construir y correr el pipeline de
entrega continua, promover dev → stage → prod con aprobación manual, generar el tag y la
trazabilidad, ejecutar el rollback y abrir el PR a `dev`. No tocar HU-04 ni ocultar los tests base.

---

## Trabajo realizado

1. **Infraestructura.** Se levantaron `ci` y `nexus` en AWS con el bootstrap de HU-01. Jenkins corre
   en `ci` con un daemon Docker-in-Docker (sin socket del host) y un repositorio Git interno.
2. **Imagen de Jenkins.** Se agregaron Docker CLI, Compose, buildx, Node 22 y dependencias de
   Playwright; se configuraron las credenciales `circleguard-env-{dev,stage,prod}`,
   `circleguard-registry` y el job multibranch `circleguard-hu06-v2`.
3. **Correcciones de despliegue.**
   - OpenLDAP con healthcheck autenticado.
   - Zookeeper con `start_period` de 180 s.
   - Creación de las bases de datos con `psql` por stdin después de que postgres esté healthy.
   - `compose-down.sh` con `CG_DOWN_VOLUMES=1` para que `Stop dev`/`Stop stage` eliminen volúmenes.
   - `rollback.sh` acepta imágenes locales y no aborta si aún no hay release registrado.
4. **Build de entrega continua #6 (`dd825e6`).** Deploy dev, E2E dev, Stop dev, Deploy stage, E2E
   stage, Stop stage, aprobación manual de `admin`, Deploy prod y tag `v0.1.0`. Resultado global
   `UNSTABLE` por los tests base de HU-04; el resto de etapas `SUCCESS`.
5. **Build de rollback #13 (`3a8b347`).** `rollback.sh dev 0.1.0`, evento `rollback` registrado en
   JSON y en el historial; resultado `SUCCESS`.

## Decisiones aplicadas

| Decisión | Entrada |
|---|---|
| Tests base no bloqueantes | [D-15](../decisiones.md#d-15--tests-base-no-bloqueantes) |
| Build/publicación de imágenes opcionales | [D-16](../decisiones.md#d-16--build-y-publicación-de-imágenes-opcionales) |
| Trazabilidad JSON + TSV | [D-17](../decisiones.md#d-17--trazabilidad-json--historial-tsv) |
| Rollback reutiliza deploy y valida imágenes | [D-18](../decisiones.md#d-18--rollback-reutiliza-deploy-y-valida-imágenes) |
| Notificaciones no fatales | [D-19](../decisiones.md#d-19--notificaciones-discordslack-no-fatales) |
| E2E de humo como gate de stage | [D-20](../decisiones.md#d-20--e2e-de-humo-como-gate-de-stage) |
| Registro oficial: CNCF Distribution/Nexus | [D-25](../decisiones.md#d-25--el-registro-oficial-pasa-a-cncf-distribution) |

## Incidentes y resolución

| Incidente | Causa | Resolución |
|---|---|---|
| `No space left on device` | dev + stage + prod con volúmenes simultáneos en 30 GB | parada secuencial con eliminación de volúmenes y limpieza de builds/imágenes |
| `address already in use :3000` | el web de dev o prod seguía levantado al promover | `Stop dev`/`Stop stage` con los archivos Compose correctos; `CG_DOWN_VOLUMES=1` |
| Build zombie de la rama `HU-06-ci` | reinicio del host durante un build | rama de ejecución limpia `HU-06-run`; se deshabilitó la rama vieja |
| Rollback sin mensaje | `cg_current_version` llamaba `exit 1` dentro del `|| true` | `cg_current_version_optional` + trap de línea |
| Rollback con puerto ocupado | prod web en `127.0.0.1:3000` | se detuvo temporalmente prod web y se reinició al terminar |
| Notificación omitida | no hay webhook de Discord/Slack | se registra la omisión; el pipeline no falla |

## Evidencias

Todas están en [`docs/evidencias/hu-06/`](../../evidencias/hu-06/README.md), incluidos los logs
completos `console-build-6.txt` y `console-build-13.txt`.

- Build #6: `00-build-summary.txt` a `07-tag.txt`, `11-stop-envs.txt`.
- Trazabilidad: `08-traceability.json`.
- Notificación: `09-notification.txt` (limitación).
- Rollback: `10-rollback.txt`, `12-prod-web-restored.txt`.
- E2E: `e2e-results-build-6.xml`.

## Limitaciones

- HU-04 mantiene 10 tests base fallando; el build es `UNSTABLE` por diseño.
- No se configuró un webhook externo de notificaciones.
- Solo existe la versión `0.1.0`; el rollback se validó contra la misma versión. Un downgrade real
  requiere publicar una versión anterior (por ejemplo `0.2.0 → 0.1.0`).
- La URL de Jenkins era `localhost:8080` mediante túnel; el host se apaga al terminar. La evidencia
  durable son los logs y artefactos versionados.

## Siguiente paso

El PR **#9** quedó abierto contra `dev`:
<https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492/pull/9>.
Después del merge, crear la rama de HU-07 desde el nuevo `dev` y aplicar el contenido preservado en
`hu07-seed` / `75791ad`.

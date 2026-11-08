# Evidencias de HU-06 · Entrega continua y promoción

**Estado: ejecutado el 2026-11-08 en AWS (host CI + Docker-in-Docker) y en Jenkins.**

- Build de entrega continua: `circleguard-hu06-v2 » HU-06-run #6`, commit `dd825e6`.
  Resultado **UNSTABLE** porque la etapa `Unit tests and coverage` publica fallos de tests base que
  pertenecen a HU-04; las etapas de despliegue, E2E, aprobación, prod y tag terminaron **SUCCESS**.
- Build de rollback: `circleguard-hu06-v2 » HU-06-run #13`, commit `3a8b347`,
  resultado **SUCCESS**.
- El host de Jenkins es efímero (se apaga al terminar); por eso el log completo de ambos builds
  queda versionado en `console-build-6.txt` y `console-build-13.txt`. La URL `localhost:8080`
  corresponde al túnel del operador y no es accesible desde fuera.
- PR abierto contra `dev`: <https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492/pull/9>.

## Resumen de la ejecución

| Dato | Valor |
|---|---|
| Rama | `HU-06-_Entrega-continua-y-promoción` |
| Commit de entrega | `dd825e6` (build #6) |
| Commit del rollback | `3a8b347` (build #13) |
| Versión desplegada | `0.1.0` |
| Destino | AWS `ci` (m7i-flex.large, 8 GiB) + DinD; registry Nexus `10.20.0.106:8082` |
| Promoción | dev → stage → aprobación manual → prod |
| Tests base | 10 fallos de HU-04; etapa no bloqueante (`UNSTABLE`) |
| Tag | `v0.1.0` en `dd825e6`, publicado en GitHub |
| Secretos | Sin credenciales en el repositorio; los `.env` viven en credenciales de Jenkins |

Parámetros del build #6:

```text
VERSION=0.1.0
FORCE_PROD=true
SEQUENTIAL_ENVS=true
SKIP_E2E=false
PUSH_TAG=false
RUN_SONAR=false
RUN_INTEGRATION=false
BUILD_IMAGES=false
PUBLISH_IMAGES=false
```

Las imágenes `0.1.0` ya estaban publicadas en el registry; por eso el build de evidencia no las
reconstruyó. Las etapas `Package images`, `Publish images`, `SonarQube`, `Integration tests` y
`Publish artifacts` quedaron `NOT_EXECUTED` por esos parámetros.

## Matriz de criterios

| Criterio | Implementación | Evidencia |
|---|---|---|
| Despliegue automático a dev tras merge | `Jenkinsfile` → `Deploy dev`; `deploy/deploy.sh` | [`01-dev-deploy.txt`](01-dev-deploy.txt) |
| Promoción a stage solo si pasan E2E | `E2E dev` antes de `Deploy stage`; `deploy/e2e.sh` | [`02-e2e-dev.txt`](02-e2e-dev.txt), [`03-stage-deploy.txt`](03-stage-deploy.txt) |
| Aprobación manual antes de prod | `input` en `Approve prod` (`submitter: admin`) | [`05-approval.txt`](05-approval.txt) |
| Versionado semántico + tag | `deploy/next-version.sh`, `tag-release.sh`, tag `v0.1.0` | [`07-tag.txt`](07-tag.txt) |
| Prod solo tras aprobación | `Deploy prod` después del `input` | [`06-prod-deploy.txt`](06-prod-deploy.txt) |
| Trazabilidad por ambiente | `deploy/releases/*.json`, `history.tsv`, copia persistente | [`08-traceability.json`](08-traceability.json) |
| Notificación de fallos | `deploy/notify.sh` + `post` no bloqueante | [`09-notification.txt`](09-notification.txt) — **limitación: webhook no configurado** |
| Rollback a una versión anterior | `deploy/rollback.sh` y evento `rollback` | [`10-rollback.txt`](10-rollback.txt) — **limitación: solo existe 0.1.0** |
| Parada secuencial de ambientes | `Stop dev`, `Stop stage`, `CG_DOWN_VOLUMES=1` | [`11-stop-envs.txt`](11-stop-envs.txt) |
| Restauración de prod tras el rollback | reinicio del web de prod | [`12-prod-web-restored.txt`](12-prod-web-restored.txt) |
| Higiene de secretos | `infra/scan-secrets.sh` (Gitleaks) | [`13-secret-scan.txt`](13-secret-scan.txt) — worktree PASS |

## Evidencias

| Archivo | Contenido |
|---|---|
| `00-build-summary.txt` | Estado de todas las etapas del build #6 y razón del `UNSTABLE` |
| `01-dev-deploy.txt` | Comando, versión, healthchecks y `OK: dev desplegado en 0.1.0` |
| `02-e2e-dev.txt` | Playwright: 2 tests aprobados contra dev |
| `03-stage-deploy.txt` | Promoción a stage, creación de volúmenes y `OK: stage desplegado en 0.1.0` |
| `04-e2e-stage.txt` | Playwright: 2 tests aprobados contra stage |
| `05-approval.txt` | `¿Desplegar 0.1.0 a prod?`, `Desplegar a prod` y `Approved by admin` |
| `06-prod-deploy.txt` | Despliegue de prod, 15 contenedores healthy y `OK: prod desplegado en 0.1.0` |
| `07-tag.txt` | Salida del CI, `git tag -n`, `git show v0.1.0` y URL de GitHub |
| `08-traceability.json` | Releases de dev/stage/prod, deploy previo de dev e historial completo |
| `09-notification.txt` | Líneas reales del log y alcance de la notificación |
| `10-rollback.txt` | Etapa `Rollback` del build #13, `event=rollback`, historial y limitación |
| `11-stop-envs.txt` | Contenedores y volúmenes eliminados al promover (libera el puerto 3000) |
| `12-prod-web-restored.txt` | Estado final `Up (healthy)` del web de prod |
| `13-secret-scan.txt` | Gitleaks: worktree PASS, corrección del falso positivo y conteos del historial |
| `console-build-6.txt` | Log completo del build de entrega continua |
| `console-build-13.txt` | Log completo del build de rollback |
| `e2e-results-build-6.xml` | Resultado JUnit de Playwright del build #6 |
| `release-history-build-6.tsv` | Historial TSV generado por el build #6 |

## Limitaciones y notas

1. **Tests base (HU-04).** El build queda `UNSTABLE`; no se modificaron los tests ni se ocultó el
   resultado. Las etapas de CD continúan por diseño (D-15).
2. **Notificación.** No hay webhook de Discord/Slack configurado. `deploy/notify.sh` está
   implementado y el pipeline no falla si falta la credencial; el log muestra la omisión.
3. **Rollback.** El registry solo tiene `0.1.0`. Se ejecutó `rollback.sh dev 0.1.0` para validar el
   mecanismo, el registro `event=rollback` y el historial. Un downgrade real requiere publicar una
   versión anterior (por ejemplo `0.2.0 → 0.1.0`).
4. **Host único.** Dev y prod comparten el DinD y el puerto `3000`. Para el rollback se detuvo
   temporalmente el web de prod y se reinició al terminar (`12-prod-web-restored.txt`). En la
   promoción normal, `Stop dev`/`Stop stage` liberan el puerto y los volúmenes.
5. **Tag.** El build usó `PUSH_TAG=false` para no publicar desde Jenkins; el tag `v0.1.0` se recreó
   en el repositorio de entrega en el mismo commit `dd825e6` y se publicó en GitHub.
6. **Sin secretos.** `infra/scan-secrets.sh` (Gitleaks) pasó el árbol de trabajo sin ACTIVOS
   (`13-secret-scan.txt`); el historial conserva hallazgos históricos informativos y no se reescribe.
   Los `.env` son credenciales Secret file de Jenkins y el log enmascara `$CG_ENV_FILE`. No se
   versionaron contraseñas, tokens, Account ID ni códigos MFA.

## Cambios de código relevantes

- `Jenkinsfile`: checkout, build/tests, imágenes opcionales, dev, E2E, stage, aprobación, prod, tag
  y rollback.
- `deploy/compose-down.sh` + `stopEnv`: `CG_DOWN_VOLUMES=1` elimina los volúmenes del ambiente
  detenido para no llenar el disco de 30 GB.
- `deploy/rollback.sh`: acepta imágenes locales cuando el registry no es accesible desde el host de
  despliegue y usa `cg_current_version_optional` para no abortar si aún no hay release registrado.
- `deploy/compose-up.sh`: crea las bases de datos después de que postgres esté healthy.
- `deploy/compose/docker-compose.common.yml`: healthcheck de OpenLDAP y `start_period` de
  zookeeper.
- `jenkins/vars/cgPublish.groovy`: publicación de artifacts con `netrc` temporal en lugar de
  `curl --user`; evita el falso positivo de Gitleaks y no expone el password en el log.

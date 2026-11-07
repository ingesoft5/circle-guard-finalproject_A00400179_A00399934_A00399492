# Evidencias de HU-06 · Entrega continua y promoción

**Estado: pipeline y scripts implementados; evidencias de ejecución pendientes de Jenkins,
Docker y un destino de despliegue.** El código está listo para ejecutarse cuando HU-04 instale los
plugins y el agente con Docker/Node.

## Matriz de criterios

| Criterio | Implementación | Evidencia |
|---|---|---|
| Despliegue automático a dev tras merge | `Jenkinsfile` etapas `Deploy dev` en `dev`/`main`; `deploy/deploy.sh` | `01-dev-deploy.txt` + captura de Jenkins |
| Promoción a stage solo si pasan E2E | `E2E dev` antes de `Deploy stage`; `deploy/e2e.sh` | `02-e2e-dev.txt`, `03-stage-deploy.txt` |
| Aprobación manual antes de prod | `input` en `Approve prod` (`submitter: admin`) | `05-approval.png` |
| Versionado semántico automático + tag | `deploy/next-version.sh`, `tag-release.sh`, `vX.Y.Z` | `07-tag.txt` + captura de GitHub |
| Prod solo tras aprobación | `Deploy prod` después del `input` | `06-prod-deploy.txt` |
| Trazabilidad por ambiente | `deploy/releases/<env>.json`, `history.tsv`, copia persistente en `CG_RELEASES_DIR`; artefactos | `09-traceability.json` |
| Notificación de fallos | `deploy/notify.sh` (Discord/Slack) en `post` | `10-notification.png` |

## Evidencias a generar

| Archivo | Cómo |
|---|---|
| `01-dev-deploy.txt` | `./deploy/deploy.sh dev 1.0.0` o salida de Jenkins |
| `02-e2e-dev.txt` | `E2E_BASE_URL=http://localhost:3000 ./deploy/e2e.sh dev` |
| `03-stage-deploy.txt` | `DEPLOY_MODE=ssh ... ./deploy/deploy.sh stage 1.0.0` |
| `04-e2e-stage.txt` | `E2E_BASE_URL=http://<stage>:3000 ./deploy/e2e.sh stage` |
| `05-approval.png` | Captura del `input` de Jenkins |
| `06-prod-deploy.txt` | Salida del despliegue a prod |
| `07-tag.txt` | `git tag -l`, `git show v1.0.0`, captura del tag en GitHub |
| `08-release-notes.md` | `docs/release-notes/v1.0.0.md` y `CHANGELOG.md` |
| `09-traceability.json` | `deploy/releases/*.json` y `history.tsv` |
| `10-notification.png` | Captura del mensaje de Discord/Slack |

## Flujo local (sin Jenkins)

Si Docker está disponible, se puede validar la lógica sin Jenkins:

```bash
./deploy/next-version.sh
./deploy/build-images.sh 1.0.0
./deploy/publish-images.sh 1.0.0
./deploy/deploy.sh dev 1.0.0
E2E_BASE_URL=http://localhost:3000 ./deploy/e2e.sh dev
./deploy/rollback.sh dev 0.9.0   # si existe esa versión
./deploy/current-version.sh dev
```

## Bloqueos actuales

| Bloqueo | Impacto |
|---|---|
| Imagen de Jenkins sin `nodejs`/SSH | El CI arranca con los plugins de HU-03, pero el E2E y el despliegue `DEPLOY_MODE=ssh` necesitan reconstruir la imagen con los extras de `jenkins/plugins.txt` |
| Jenkins sin Docker | No construye imágenes en el controlador |
| Hosts `t3.small` (2 GiB) | No aguantan los 15 contenedores |
| `QUOTA_VCPU_LIMIT=5` | `ci` + `nexus` + un ambiente = 6 vCPU |
| Jenkins privado | No hay webhook; se usa `pollSCM` cada 5 min |
| 10 tests base fallando | Build `UNSTABLE`; no bloquea el despliegue, pero debe corregirse en HU-04 |

# Evidencias de HU-07 · Rollback, notificaciones y release notes

**Estado: ejecutado en AWS/Jenkins con evidencias completas. Pendiente la aprobación del PR a
`dev` y el apagado de AWS.**

## Matriz de criterios

| Criterio | Implementación | Evidencia | Estado |
|---|---|---|---|
| Rollback a una versión anterior, verificado en dev y prod | `deploy/rollback.sh <env> <version>`; valida imágenes y redespliega con `event=rollback` | [`01-rollback.txt`](01-rollback.txt) y [`08-traceability.json`](08-traceability.json) | Cumplido |
| Notificación automática de fallos | `deploy/notify.sh` (Discord/Slack) en el `post` de Jenkins | [`02-notification.txt`](02-notification.txt) + [`02-notification.png`](02-notification.png) | Cumplido |
| Plantilla de solicitud de cambio | `docs/operaciones/solicitud-cambio.md` | [`05-politica.md`](05-politica.md) | Cumplido |
| Política de aprobación por tipo | `docs/operaciones/politica-aprobacion.md` | [`05-politica.md`](05-politica.md) | Cumplido |
| Release notes desde commits/PR | `deploy/release-notes.sh` + `CHANGELOG.md` | [`03-release-notes.md`](03-release-notes.md) | Cumplido |
| Esquema de etiquetado de releases | `vMAJOR.MINOR.PATCH` en `deploy/tag-release.sh` | [`04-tag.txt`](04-tag.txt) | Cumplido |
| Trazabilidad de despliegues y rollbacks | `deploy/releases/*.json` e historial TSV | [`08-traceability.json`](08-traceability.json) | Cumplido |
| Escaneo de secretos en PASS | `infra/scan-secrets.sh` | [`13-secret-scan.txt`](13-secret-scan.txt) | Cumplido |

## Ejecución real

| Build | Resultado | Detalle |
|---|---|---|
| #16 | FAILURE | `ENOSPC` en `Package images`; se limpió disco. |
| #17 | FAILURE | Unit/coverage e integración OK; imágenes 0.2.0 publicadas; `Deploy stage` unhealthy; notificación de fallo enviada. |
| #18 | UNSTABLE | CD completo; prod 0.2.0; tag/release notes/GitHub Release. `Unit tests` interrumpidos por reinicio de Jenkins, no por test fallido. |
| #19 | SUCCESS | Rollback dev `0.2.0 → 0.1.0`; 15 contenedores healthy. |
| #20 | SUCCESS | Build SCM sin tests ni despliegue. |
| #21 | SUCCESS | Rollback prod `0.2.0 → 0.1.0`; 15 contenedores healthy. |

Detalle completo en [`00-build-summary.txt`](00-build-summary.txt).

## Rollback

- Dev: build #19, evento `rollback`, `0.2.0 → 0.1.0`; stack dev eliminado tras la evidencia.
- Prod: build #21, evento `rollback`, `0.2.0 → 0.1.0`; 15 servicios healthy.
- El campo `commit` de los rollbacks es el checkout de Jenkins; la imagen `0.1.0` corresponde al
  tag `v0.1.0` (`dd825e6`). La relación queda documentada en `01` y `08`.

## Notificaciones

- Fallo real: build #17, `./deploy/notify.sh failure stage 0.2.0 Pipeline falló`.
- Mensaje: `[CircleGuard] failure · stage · 0.2.0 · Pipeline falló`.
- Captura de Discord pendiente: guardar como `02-notification.png` (sin webhook visible).

## Release notes y tag

- `docs/release-notes/v0.2.0.md` y `CHANGELOG.md` actualizados.
- `v0.2.0` → `59cec5c`.
- GitHub Release:
  <https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492/releases/tag/v0.2.0>
- El tag/release se corrigió después de detectar que `PUSH_TAG=true` no era reconocido por
  `tag-release.sh` y que faltaba `target_commitish` en `github-release.sh`.

## Tests

- #17: `Unit tests and coverage` y `Integration tests` en SUCCESS.
- #18: `Unit tests and coverage` UNSTABLE por reinicio de Jenkins (JENKINS-48300), no por fallo de
  tests; el CD continuó y terminó.
- #20: no ejecutó tests.
- HU-04 no se modificó; los tests base siguen siendo no bloqueantes por decisión D2.

## Archivos

| Archivo | Contenido |
|---|---|
| [`00-build-summary.txt`](00-build-summary.txt) | Resumen de #16–#21 y estado de tests |
| [`01-rollback.txt`](01-rollback.txt) | Rollback dev/prod, JSON e historial |
| [`02-notification.txt`](02-notification.txt) / [`02-notification.png`](02-notification.png) | Fallo real #16 (captura), #17 y prueba manual |
| [`03-release-notes.md`](03-release-notes.md) | Notas v0.2.0, CHANGELOG y GitHub Release |
| [`04-tag.txt`](04-tag.txt) | Tags v0.1.0/v0.2.0 y corrección |
| [`05-politica.md`](05-politica.md) | Política, RFC y PR template |
| [`08-traceability.json`](08-traceability.json) | Estado dev/prod/stage e historial |
| [`13-secret-scan.txt`](13-secret-scan.txt) | Worktree PASS e historial |
| [`console-build-18.txt`](console-build-18.txt) | Consola del build de CD |
| [`console-build-19.txt`](console-build-19.txt) | Consola del rollback dev |
| [`console-build-21.txt`](console-build-21.txt) | Consola del rollback prod |

## Pendiente para cerrar

1. Aprobar y mergear el PR de HU-07 a `dev` (el autor no puede autoaprobar).
2. Detener `ci`/`nexus` si no se necesita la infraestructura.

# Evidencias HU-16 · Change management y rollback en Kubernetes (E2.8)

**Estado:** parcial. Compose está ejecutado y evidenciado (HU-07); el registro D-30 está
implementado; el rollback en K8s tiene **procedimiento implementado** en `deploy/rollback.sh`
(`DEPLOY_MODE=k8s`), pero **falta ejecutarlo y adjuntar la salida**.

**Documento dueño:** [`../../operaciones/gestion-cambios.md`](../../operaciones/gestion-cambios.md)
**Documento de apoyo:** [`../../operacion/manual-operaciones.md`](../../operacion/manual-operaciones.md) §7

## Matriz de criterios E2.8

| # | Criterio | Implementación | Evidencia | Estado |
|---|---|---|---|---|
| 1 | Identificador único y tag semántico | `deploy/tag-release.sh`, tags `v0.1.0`, `v0.2.0` | [`01-tags.txt`](01-tags.txt) | Cumplido hasta `v0.2.0`; `v0.3.0` pendiente |
| 2 | Release notes por versión | `deploy/release-notes.sh`, `CHANGELOG.md` | [`02-release-notes.md`](02-release-notes.md) | Notas `v0.3.0` escritas; tag pendiente |
| 3 | Funcionalidades, correcciones y cambios técnicos | Secciones de las notas | [`../../release-notes/v0.3.0.md`](../../release-notes/v0.3.0.md) | Cumplido |
| 4 | Plan de rollback documentado | `gestion-cambios.md` §7.1–§7.3 | Documento | Cumplido (Compose y K8s) |
| 5 | Rollback de artefactos en Kubernetes | `DEPLOY_MODE=k8s ./deploy/rollback.sh` | [`03-rollback-k8s.txt`](03-rollback-k8s.txt) | Implementado; **pendiente ejecutar** |
| 6 | Prueba real de rollback | Compose verificado; K8s pendiente | `03-rollback-k8s.txt` + [`../../hu-07/01-rollback.txt`](../../hu-07/01-rollback.txt) | Cumplido en Compose; **pendiente en K8s** |
| 7 | Registro por dev, stage y prod | `deploy/releases/*.json` e `history.tsv` | [`04-registro.txt`](04-registro.txt) | Parcial |
| 8 | Versión, fecha, ambiente, responsable, aprobación, resultado | `record-release.sh` con D-30 | [`04-registro.txt`](04-registro.txt) | Implementado; falta evidencia de ejecución |
| 9 | Evidencia de aprobación de prod | Stage `Approve prod` de Jenkins | [`05-approval.txt`](05-approval.txt) | Cumplido (HU-06) |
| 10 | Relación con commits y versiones | Campo `commit` en el registro y tag | [`01-tags.txt`](01-tags.txt) | Cumplido |
| 11 | Procedimientos documentados | `gestion-cambios.md` + manual | Documentos | Cumplido |

## Archivos

| Archivo | Contenido | Estado |
|---|---|---|
| [`01-tags.txt`](01-tags.txt) | `git tag -n` y relación tag → commit | Hecho |
| [`02-release-notes.md`](02-release-notes.md) | Notas del Sprint 2 y comandos de publicación | Borrador |
| [`03-rollback-k8s.txt`](03-rollback-k8s.txt) | Comandos y plantilla del rollback real | Pendiente de ejecución |
| [`04-registro.txt`](04-registro.txt) | Plantilla del registro con campos D-30 | Pendiente de ejecución |
| [`05-approval.txt`](05-approval.txt) | Enlace a la aprobación de HU-06 | Reutilizada |

## Pendiente para cerrar

1. Ejecutar `DEPLOY_MODE=k8s ./deploy/rollback.sh dev 0.2.0` y pegar la salida en `03`.
2. Registrar un despliegue real con `APPROVED_BY`, `APPROVAL_REF`, `IMAGE_DIGEST` y `RESULT` en `04`.
3. Publicar el tag `v0.3.0` y el GitHub Release desde Jenkins.
4. Verificar que el manual §7.2 coincide con los comandos usados.

## Dependencias

| Pendiente | Depende de | Estado |
|---|---|---|
| Rollback K8s real | HU-10 (hecho, PR #21) + `kubectl`/AWS | Listo para ejecutar |
| Tag y release desde Jenkins | HU-11 (pipeline) | Pendiente; se puede publicar manualmente |
| Digest de imagen | ECR | Disponible con `aws ecr describe-images` |

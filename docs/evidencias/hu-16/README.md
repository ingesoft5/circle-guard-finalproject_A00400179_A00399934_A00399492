# Evidencias HU-16 · Change management y rollback en Kubernetes (E2.8)

**Estado:** parcial. El change management sobre Docker Compose ya está ejecutado y evidenciado en
HU-07; el rollback real en Kubernetes sigue bloqueado por HU-10/HU-11. El registro ampliado (D-30)
ya está implementado en `deploy/record-release.sh`, pero falta evidenciarlo en un despliegue.

**Documento dueño:** [`../../operaciones/gestion-cambios.md`](../../operaciones/gestion-cambios.md)
**Documento de apoyo:** [`../../operacion/manual-operaciones.md`](../../operacion/manual-operaciones.md) §7

## Matriz de criterios E2.8

| # | Criterio | Implementación | Evidencia esperada | Estado |
|---|---|---|---|---|
| 1 | Identificador único y tag semántico | `deploy/tag-release.sh`, tags `v0.1.0`, `v0.2.0` | `01-tags.txt` | Cumplido (HU-07) |
| 2 | Release notes por versión | `deploy/release-notes.sh`, `CHANGELOG.md` | `02-release-notes.md` | Cumplido hasta `v0.2.0`; falta la del Sprint 2 |
| 3 | Funcionalidades, correcciones y cambios técnicos | Secciones de las notas | `02-release-notes.md` | Cumplido hasta `v0.2.0` |
| 4 | Plan de rollback documentado | `gestion-cambios.md` §7.1 | Documento | Cumplido (Compose) |
| 5 | Rollback de artefactos en Kubernetes | `kubectl rollout undo` / `helm rollback` | `03-rollback-k8s.txt` | **Pendiente** (HU-10/HU-11) |
| 6 | Prueba real de rollback | `deploy/rollback.sh` en Compose; K8s pendiente | `03-rollback-k8s.txt` + `08-traceability.json` | Cumplido en Compose; **pendiente en K8s** |
| 7 | Registro por dev, stage y prod | `deploy/releases/*.json` e `history.tsv` | `04-registro.txt` | Parcial |
| 8 | Versión, fecha, ambiente, responsable, aprobación, resultado | `record-release.sh` con `RESULT`, `APPROVED_BY`, `APPROVAL_REF`, `IMAGE_DIGEST` (D-30) | `04-registro.txt` | Implementado; falta evidencia de ejecución |
| 9 | Evidencia de aprobación de prod | Stage `Approve prod` de Jenkins | `05-approval.txt` (HU-06) | Cumplido (Sprint 1) |
| 10 | Relación con commits y versiones | Campo `commit` en el registro y tag | `04-registro.txt` | Cumplido |
| 11 | Procedimientos documentados | `gestion-cambios.md` + manual de operaciones | Documentos | Cumplido |

## Archivos previstos

| Archivo | Contenido | Estado |
|---|---|---|
| [`01-tags.txt`](01-tags.txt) | `git tag -n` y relación tag → commit | Por crear |
| [`02-release-notes.md`](02-release-notes.md) | Notas del Sprint 2 y `CHANGELOG.md` | Por crear |
| [`03-rollback-k8s.txt`](03-rollback-k8s.txt) | Rollback real en dev y prod sobre K8s | Bloqueado |
| [`04-registro.txt`](04-registro.txt) | JSON y `history.tsv` con los campos D-30 | Por crear |
| [`05-approval.txt`](05-approval.txt) | Aprobación de prod en Jenkins | Reutilizar HU-06 |

## Pendiente para cerrar

1. Ejecutar un rollback real en Kubernetes (dev y prod) y adjuntar la salida en `03-rollback-k8s.txt`.
2. Registrar un despliegue con `RESULT`, `APPROVED_BY`, `APPROVAL_REF` e `IMAGE_DIGEST` y guardar el
   JSON/TSV en `04-registro.txt`.
3. Publicar las release notes del Sprint 2 (`v0.3.0` o la versión que se acuerde).
4. Verificar que el manual de operaciones §7.2 coincide con los comandos usados.

## Dependencias

| Pendiente | Depende de | Qué falta |
|---|---|---|
| Rollback K8s | HU-10/HU-11 | Manifiestos de los 8 servicios y pipeline con `kubectl`/`helm` |
| Aprobación en K8s | HU-11 | Stage de aprobación conectado al clúster |
| Digest de imagen | HU-02/HU-06 | `crane manifest` o `docker inspect` en el pipeline |

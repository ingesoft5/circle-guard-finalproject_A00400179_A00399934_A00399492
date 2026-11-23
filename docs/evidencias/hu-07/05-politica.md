# 05 · Política de aprobación y solicitud de cambio

Fecha: 2026-11-08
Historia: HU-07

## Documentos versionados

| Documento | Ruta |
|---|---|
| Política de aprobación por tipo de cambio | [`docs/operaciones/politica-aprobacion.md`](../../operaciones/politica-aprobacion.md) |
| Plantilla de solicitud de cambio (RFC) | [`docs/operaciones/solicitud-cambio.md`](../../operaciones/solicitud-cambio.md) |
| Plantilla de PR | [`.github/PULL_REQUEST_TEMPLATE.md`](../../../.github/PULL_REQUEST_TEMPLATE.md) |
| Decisiones D-21/D-22 | [`docs/iag/decisiones.md`](../../iag/decisiones.md) |

## Matriz de aprobación

| Tipo | Ejemplos | Aprobadores mínimos |
|---|---|---|
| Estándar | Documentación, configuración no funcional | 1 revisor |
| Normal | Código, Dockerfiles, Compose, scripts de `deploy/`, Jenkinsfile | 1 revisor + responsable técnico |
| Mayor | Esquema/DB, breaking change, seguridad/privacidad, topología | 2 revisores + responsable técnico |
| Emergencia | Hotfix de seguridad o caída en prod | Responsable de incidente + responsable técnico |

## Aplicación a HU-07

- Tipo de cambio: **Normal** (scripts de despliegue, Jenkinsfile, notificaciones, release notes).
- Aprobación requerida: 1 revisor + responsable técnico.
- El autor del PR no puede autoaprobar.
- `prod` requiere adicionalmente el `input` manual del pipeline (usuario `admin` en Jenkins).
- Rollback identificado y probado en dev y prod:
  `./deploy/rollback.sh dev 0.1.0` y `./deploy/rollback.sh prod 0.1.0`.
- Evidencias: `01-rollback.txt`, `02-notification.txt`, `03-release-notes.md`, `04-tag.txt`,
  `08-traceability.json` y `13-secret-scan.txt`.

## Flujo

```text
RFC -> PR -> revisión -> pipeline (build/test) -> E2E dev -> stage -> E2E stage
    -> aprobación según tipo -> input prod -> despliegue -> tag + release notes
```

La solicitud de cambio completa se copia en el PR; no se versionan datos personales de los
aprobadores, solo el rol y la decisión.

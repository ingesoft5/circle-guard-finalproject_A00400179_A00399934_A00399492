# Sesión IAG · Cierre del Sprint 2 (HU-13, HU-16 y HU-17)

| Campo | Valor |
|---|---|
| Fecha | 2026-11-21 |
| Historia | HU-13, HU-16 y HU-17 |
| Rama | `HU-13-evidencia-observabilidad`, `HU-16-change-management-rollback-k8s`, `HU-17-documentacion-cierre-e2.9` |
| Herramienta | OpenCode |
| Modelo | DeepSeek V4.1 Flash |
| Nivel de uso | Nivel 3 · colaboración con IAG |
| Participantes | Sebastian Cosme + asistente |

## Turno 1 · Auditoría de `dev` y corrección de la documentación

### Prompt (literal, resumido)

```text
Quiero que revises exhaustivamente dev, según lo que veo eso de terraform sí está creado,
así que revisa bien y luego me das lo que en verdad falta.
```

### Respuesta (síntesis)

- Se actualizaron las referencias: `origin/dev` ya tenía Terraform (PR #15, #16 y #18) y el
  `dev` local estaba desactualizado.
- Se listaron los vacíos reales: evidencia de observabilidad, rollback K8s, estados de
  documentación y capturas de Jira/Billing.
- Se corrigió `docs/arquitectura/terraform.md` con el estado real, el diagrama y el índice de
  evidencias `e2.1-terraform`.

### Decisiones aplicadas

| Decisión | Entrada |
|---|---|
| Documentar el estado real y no el objetivo | D-32 |
| Mantener la evidencia en `docs/evidencias/` y enlazarla | DoD del sprint |

### Archivos generados

- `docs/arquitectura/terraform.md`
- `docs/evidencias/e2.1-terraform/README.md`
- Actualizaciones de `docs/README.md`, `sprint-2.md`, `infra/README.md` y el manual.

## Turno 2 · Cierre por ramas de cada HU

### Prompt (literal, resumido)

```text
Procede con el proceso que indicas para terminar todo lo que falta... recuerda respetar hacerlo
por rama que cada rama es una HU mía, y apenas termines una haces el pr y creamos una nueva.
```

### Respuesta (síntesis)

- **HU-13:** script `deploy/observability/capture-evidence.sh` y matriz de evidencia actualizada.
- **HU-16:** `deploy/rollback.sh` con `DEPLOY_MODE=k8s`, notas `v0.3.0`, plantillas de rollback y
  registro D-30.
- **HU-17:** estados de sprint, Kubernetes, seguridad, manual, costos, resumen en inglés, índices
  de evidencia y bitácora.
- No se inventaron capturas ni resultados: lo que requiere ejecución quedó como pendiente explícito.

### Decisiones aplicadas

| Decisión | Entrada |
|---|---|
| Un rollback por versión con `deploy/k8s/deploy.sh` | D-29 |
| Registro con `result`, `approved_by`, `approval_ref` e `image_digest` | D-30 |
| No aplicar recursos facturables sin plan revisado | D-33 |

### Archivos generados

- `deploy/observability/capture-evidence.sh`
- `deploy/rollback.sh` (modo K8s)
- `docs/release-notes/v0.3.0.md`
- `docs/evidencias/hu-16/*`
- `docs/operacion/seguridad.md` y `docs/evidencias/hu-14/README.md`
- `docs/evidencias/e2.2-kubernetes/README.md`
- `docs/sustentacion/resumen-ejecutivo-en.md`
- `docs/evidencias/hu-17/*`

### Pendiente

1. Capturas de Grafana, Alertmanager, Jaeger y Loki, y la falla provocada.
2. Ejecutar el rollback real en K8s y registrar el despliegue con D-30.
3. Capturas de Jira, factura de AWS y ensayo de la demo.
4. Revisión de la documentación por otro integrante.

> Verificación humana: el equipo revisa cada cambio, ejecuta los comandos en su entorno y adjunta
> las capturas. La IA no sustituye la ejecución ni la revisión.

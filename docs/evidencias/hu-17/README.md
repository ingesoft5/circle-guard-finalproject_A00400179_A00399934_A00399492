# Evidencias HU-17 · Documentación completa y metodología (E2.9)

**Estado:** en curso. Terraform, Kubernetes, seguridad y rendimiento ya están implementados y
mergeados; la documentación está actualizada a ese estado. Faltan las capturas de Jira, la factura
real de AWS y la revisión por otra persona.

**Documentos dueños:** [`../../README.md`](../../README.md) (índice),
[`../../metodologia/sprint-2.md`](../../metodologia/sprint-2.md),
[`../../sustentacion/resumen-ejecutivo-en.md`](../../sustentacion/resumen-ejecutivo-en.md)

## Matriz de criterios E2.9

| # | Criterio | Documento | Estado | Evidencia |
|---|---|---|---|---|
| 1 | Arquitectura con diagramas | [`arquitectura-general.md`](../../arquitectura/arquitectura-general.md), [`diagramas.md`](../../arquitectura/diagramas.md) | Cumplido; diagramas vigentes | [`01-arquitectura.md`](01-arquitectura.md) |
| 2 | Metodología ágil aplicada | [`sprint-2.md`](../../metodologia/sprint-2.md) | En curso; faltan capturas de Jira | `02-jira-sprint2.png`, `03-flujo-acumulado.png`, `04-burndown.png`, `05-retro.png` |
| 3 | Patrones de diseño | [`patrones-diseno.md`](../../arquitectura/patrones-diseno.md) | Implementado (HU-12; PR #14 y #20) | [`06-patrones.md`](06-patrones.md) |
| 4 | Infraestructura como código | [`terraform.md`](../../arquitectura/terraform.md) | Implementado y aplicado (HU-09) | [`e2.1-terraform/`](../e2.1-terraform/README.md) |
| 5 | Resultados de pruebas | [`pruebas-avanzadas.md`](../../operacion/pruebas-avanzadas.md) | Implementado (HU-15, PR #20) | [`hu-15/INFORME.md`](../hu-15/INFORME.md) |
| 6 | Costos (estimación y real) | [`analisis-costos.md`](../../operacion/analisis-costos.md) | Estimación lista; **Billing pendiente** | `09-billing.png`, `09-billing.csv` |
| 7 | Manual de operaciones | [`manual-operaciones.md`](../../operacion/manual-operaciones.md) | Cumplido; K8s implementado | Documento |
| 8 | Resumen ejecutivo en inglés (1 página) | [`resumen-ejecutivo-en.md`](../../sustentacion/resumen-ejecutivo-en.md) | Cumplido; cifras de HU-15 incluidas | Documento |
| 9 | Presentación | [`guion-sprint-2.md`](../../sustentacion/guion-sprint-2.md) | Listo para ensayo | `10-ensayo.md` |
| 10 | Revisión por otra persona | — | Pendiente | [`11-revision.md`](11-revision.md) |

## Archivos

| Archivo | Contenido | Responsable | Estado |
|---|---|---|---|
| [`01-arquitectura.md`](01-arquitectura.md) | Índice de diagramas y decisiones de arquitectura | Sebastian | Hecho |
| `02-jira-sprint2.png` | Tablero de Jira al cierre | Sebastian | Por capturar |
| `03-flujo-acumulado.png` | Export del flujo acumulado | Sebastian | Por capturar |
| `04-burndown.png` | Export del burndown | Sebastian | Por capturar |
| `05-retro.png` | Tablero de acciones de la retrospectiva | Sebastian | Por capturar |
| [`06-patrones.md`](06-patrones.md) | Enlaces a código y pruebas de HU-12 | Matt | Hecho |
| `07-terraform.txt` | `terraform init/plan/apply` y backend remoto | Juan Esteban | Cumplido: [`e2.1-terraform/`](../e2.1-terraform/README.md) |
| `08-locust-zap.md` | p95, throughput, errores y hallazgos ZAP | Matt | Cumplido: [`hu-15/INFORME.md`](../hu-15/INFORME.md) |
| `09-billing.png` / `09-billing.csv` | Factura real y comparación con la estimación | Sebastian | Por capturar |
| `10-ensayo.md` | Fecha, duración y ajustes del ensayo | Sebastian | Por crear |
| [`11-revision.md`](11-revision.md) | Revisión de la documentación por otro integrante | Juan Esteban | Pendiente |

## Pendiente para cerrar

1. Capturar el tablero de Jira, el flujo acumulado, el burndown y la retrospectiva.
2. Adjuntar la factura real de AWS y cerrar §5 de `analisis-costos.md`.
3. Hacer el ensayo de la demo y registrarlo en `10-ensayo.md`.
4. Pedir a Juan Esteban la revisión de la documentación (`11-revision.md`).
5. Revisar que el resumen en inglés tenga las cifras finales.

## Dependencias

| Pendiente | Depende de | Estado |
|---|---|---|
| Resultados de rendimiento | HU-15 | Cumplido (PR #20) |
| Sección IaC real | HU-09 | Cumplido |
| Manual con K8s | HU-10 | Cumplido (PR #21) |
| Revisión por otra persona | Juan Esteban | Pendiente |

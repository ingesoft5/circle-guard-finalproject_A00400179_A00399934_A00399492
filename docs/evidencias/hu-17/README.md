# Evidencias HU-17 · Documentación completa y metodología (E2.9)

**Estado:** en curso. Los documentos están escritos en la rama HU-13, pero varios dependen de
resultados que aún no están mergeados (Kubernetes, seguridad y rendimiento) y faltan las capturas
de cierre del sprint. Terraform ya está implementado y aplicado (HU-09).

**Documentos dueños:** [`../../README.md`](../../README.md) (índice),
[`../../metodologia/sprint-2.md`](../../metodologia/sprint-2.md),
[`../../sustentacion/resumen-ejecutivo-en.md`](../../sustentacion/resumen-ejecutivo-en.md)

## Matriz de criterios E2.9

| # | Criterio | Documento | Estado | Evidencia |
|---|---|---|---|---|
| 1 | Arquitectura con diagramas | [`arquitectura-general.md`](../../arquitectura/arquitectura-general.md), [`diagramas.md`](../../arquitectura/diagramas.md) | Escrito; diagramas vigentes | `01-arquitectura.md` |
| 2 | Metodología ágil aplicada | [`sprint-2.md`](../../metodologia/sprint-2.md) | En curso; faltan datos de cierre | `02-jira-sprint2.png`, `03-flujo-acumulado.png`, `04-burndown.png`, `05-retro.png` |
| 3 | Patrones de diseño | [`patrones-diseno.md`](../../arquitectura/patrones-diseno.md) | Implementado (HU-12) | `06-patrones.md` |
| 4 | Infraestructura como código | [`terraform.md`](../../arquitectura/terraform.md) | Documento listo; **sin `.tf`** | `07-terraform.txt` (HU-09) |
| 5 | Resultados de pruebas | [`pruebas-avanzadas.md`](../../operacion/pruebas-avanzadas.md) | Documento listo; sin resultados | `08-locust-zap.md` (HU-15) |
| 6 | Costos (estimación y real) | [`analisis-costos.md`](../../operacion/analisis-costos.md) | Estimación lista; **Billing pendiente** | `09-billing.png`, `09-billing.csv` |
| 7 | Manual de operaciones | [`manual-operaciones.md`](../../operacion/manual-operaciones.md) | Escrito; K8s pendiente | Documento |
| 8 | Resumen ejecutivo en inglés (1 página) | [`resumen-ejecutivo-en.md`](../../sustentacion/resumen-ejecutivo-en.md) | Escrito; revisar cifras finales | Documento |
| 9 | Presentación | [`guion-sprint-2.md`](../../sustentacion/guion-sprint-2.md) | Listo para ensayo | `10-ensayo.md` |
| 10 | Revisión por otra persona | — | Pendiente | `11-revision.md` |

## Archivos previstos

| Archivo | Contenido | Responsable | Estado |
|---|---|---|---|
| `01-arquitectura.md` | Índice de diagramas y decisiones de arquitectura | Sebastian | Por crear |
| `02-jira-sprint2.png` | Tablero de Jira al cierre | Sebastian | Por crear |
| `03-flujo-acumulado.png` | Export del flujo acumulado | Sebastian | Por crear |
| `04-burndown.png` | Export del burndown | Sebastian | Por crear |
| `05-retro.png` | Tablero de acciones de la retrospectiva | Sebastian | Por crear |
| `06-patrones.md` | Enlaces a código y pruebas de HU-12 | Matt | Por crear |
| `07-terraform.txt` | `terraform init/plan/apply` y backend remoto | Juan Esteban | Cumplido: ver [`e2.1-terraform/`](../e2.1-terraform/README.md) |
| `08-locust-zap.md` | p95, throughput, errores y hallazgos ZAP | Matt | Bloqueado |
| `09-billing.png` / `09-billing.csv` | Factura real y comparación con la estimación | Sebastian | Por crear |
| `10-ensayo.md` | Fecha, duración y ajustes del ensayo | Sebastian | Por crear |
| `11-revision.md` | Revisión de la documentación por otro integrante | Juan Esteban | Por crear |

## Pendiente para cerrar

1. Completar `sprint-2.md` §5.1, §5.2, §5.3 y §7 con los datos del cierre (20-nov y cierre).
2. Capturar el tablero de Jira, el flujo acumulado, el burndown y la retrospectiva.
3. Adjuntar la factura real de AWS y cerrar §5 de `analisis-costos.md`.
4. Incorporar los resultados de HU-15 y el `plan/apply` de HU-09 cuando existan.
5. Pedir a Juan Esteban la revisión de la documentación (`11-revision.md`).
6. Revisar que el resumen en inglés tenga las cifras finales.

## Dependencias

| Pendiente | Depende de | Qué falta |
|---|---|---|
| Resultados de rendimiento | HU-15 | Informe en la rama HU-14; falta merge |
| Sección IaC real | HU-09 | Cumplido: `infra/terraform/` y `arquitectura/terraform.md` |
| Manual con K8s | HU-10/HU-11 | Comandos reales del clúster |
| Revisión por otra persona | Juan Esteban | Tiempo de revisión antes del cierre |

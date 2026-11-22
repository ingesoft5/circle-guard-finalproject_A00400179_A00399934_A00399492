# Índice de la documentación

Punto de entrada a todo lo que no es código. El README general del proyecto está en
[`../README.md`](../README.md). Cada documento declara su **estado** (`Implementado`, `Parcial`,
`Pendiente`) para que la documentación no prometa más de lo que existe.

## Estado por criterio de la rúbrica (Entregable 2)

| Criterio | Documento dueño | Evidencia | Estado 2026-11-16 |
|---|---|---|---|
| C1 · Metodología ágil, cierre (E2.9) | [`metodologia/sprint-2.md`](metodologia/sprint-2.md) | Jira, flujo acumulado, retrospectiva | En curso; faltan capturas de Jira y cierre |
| C2 · Terraform (E2.1) | [`arquitectura/terraform.md`](arquitectura/terraform.md) | Módulos, plan/apply, backend remoto | Implementado y aplicado (HU-09 S2) |
| C3 · Kubernetes (E2.2) | [`arquitectura/kubernetes.md`](arquitectura/kubernetes.md) | Manifiestos, pods, Ingress, HPA | Implementado (PR #21); despliegue desde Jenkins pendiente |
| C4 · Patrones de diseño (E2.4) | [`arquitectura/patrones-diseno.md`](arquitectura/patrones-diseno.md) | Código + pruebas de falla | Implementado (HU-12, PR #14; correcciones en PR #20) |
| C5 · CI/CD avanzado (E2.3) | [`arquitectura/pipeline-cd.md`](arquitectura/pipeline-cd.md) | Jenkinsfile, builds | Parcial: K8s desplegado manualmente; Jenkins con K8s/Trivy en PR #25, pendiente merge |
| C6 · Pruebas avanzadas (E2.7) | [`operacion/pruebas-avanzadas.md`](operacion/pruebas-avanzadas.md) | Locust, ZAP, informe | Implementado (PR #20); Jenkins pendiente |
| C7 · Change management y rollback (E2.8) | [`operaciones/gestion-cambios.md`](operaciones/gestion-cambios.md) | Release notes, registro, rollback | Parcial: rollback K8s implementado; pendiente ejecutar |
| C8 · Observabilidad (E2.5) | [`operacion/observabilidad.md`](operacion/observabilidad.md) | Dashboards, alertas, trazas, logs | Parcial: implementado y mergeado; faltan capturas y evidencia K8s |
| C9 · Seguridad (E2.6) | [`operacion/seguridad.md`](operacion/seguridad.md) | Trivy, RBAC, TLS, secretos | Implementado (PR #20); Jenkins en PR #25 y despliegue K8s pendientes |
| C10 · Documentación completa (E2.9) | Este índice + [`operacion/manual-operaciones.md`](operacion/manual-operaciones.md) + [`operacion/analisis-costos.md`](operacion/analisis-costos.md) + [`sustentacion/resumen-ejecutivo-en.md`](sustentacion/resumen-ejecutivo-en.md) | Documentos + evidencias | En curso; faltan Jira, Billing y revisión |
| C11 · Presentación (E2.10) | [`sustentacion/guion-sprint-2.md`](sustentacion/guion-sprint-2.md) | Demo y falla provocada | Listo para ensayo |

> **Convención:** `HU-09 (S1)` es branching; `HU-09 (S2)` es Terraform. Ver D-32 en
> [`iag/decisiones.md`](iag/decisiones.md).

## Arquitectura y diseño

| Documento | Contenido | Estado |
|---|---|---|
| [`arquitectura/arquitectura-general.md`](arquitectura/arquitectura-general.md) | Vista lógica, responsabilidades, dependencias, comunicación y ambientes | Vigente |
| [`arquitectura/diagramas.md`](arquitectura/diagramas.md) | Diagramas de arquitectura, flujo de eventos, CI, CD e infraestructura | Vigente |
| [`arquitectura/infra-ambientes.md`](arquitectura/infra-ambientes.md) | Diagrama completo de la infraestructura AWS y los tres ambientes | Vigente |
| [`arquitectura/kubernetes.md`](arquitectura/kubernetes.md) | Contrato de K8s: namespaces, ConfigMaps, Secrets, probes, HPA, Blue-Green | Implementado (HU-10, PR #21); Jenkins pendiente |
| [`arquitectura/terraform.md`](arquitectura/terraform.md) | Módulos, backend remoto, variables, ambientes y diagrama | Implementado y aplicado (HU-09 S2) |
| [`arquitectura/pipeline-cd.md`](arquitectura/pipeline-cd.md) | Etapas del Jenkinsfile y mapeo de ramas | Vigente |
| [`arquitectura/patrones-diseno.md`](arquitectura/patrones-diseno.md) | Inventario de patrones + Circuit Breaker, External Configuration y DLT | Implementado (HU-12) |
| [`arquitectura/empaquetado-inmutable.md`](arquitectura/empaquetado-inmutable.md) | Imágenes inmutables y Compose por ambiente | Vigente |
| [`arquitectura/registro-artefactos.md`](arquitectura/registro-artefactos.md) | Decisión del registro: CNCF Distribution en lugar de Nexus | Vigente |

## Operación

| Documento | Contenido | Estado |
|---|---|---|
| [`operacion/manual-operaciones.md`](operacion/manual-operaciones.md) | Instalar, configurar, desplegar, operar, monitorear, recuperar y revertir | Vigente; K8s implementado |
| [`operacion/observabilidad.md`](operacion/observabilidad.md) | Stack, métricas, dashboards, alertas, trazas, logs y runbook | Implementado; evidencia en ejecución (HU-13 S2) |
| [`operacion/seguridad.md`](operacion/seguridad.md) | Controles actuales y pendientes: Trivy, RBAC, TLS, secretos | Implementado (PR #20); Jenkins/K8s pendiente |
| [`operacion/pruebas-avanzadas.md`](operacion/pruebas-avanzadas.md) | Objetivos, Locust, ZAP e informe consolidado | Implementado y ejecutado en local; Jenkins pendiente (HU-15 S2) |
| [`operacion/analisis-costos.md`](operacion/analisis-costos.md) | Tarifas, gasto real, estimación del Sprint 2 y FinOps | Estimación lista; Billing pendiente |
| [`operacion/infraestructura-aws.md`](operacion/infraestructura-aws.md) | Construir, destruir y reconstruir la plataforma; demostración guiada | Vigente |
| [`operaciones/gestion-cambios.md`](operaciones/gestion-cambios.md) | Releases, registro por ambiente, aprobación y rollback | Parcial: rollback K8s implementado; pendiente ejecutar |
| [`operaciones/politica-aprobacion.md`](operaciones/politica-aprobacion.md) | Tipos de cambio y aprobadores | Vigente |
| [`operaciones/solicitud-cambio.md`](operaciones/solicitud-cambio.md) | Plantilla de RFC | Vigente |
| [`../infra/README.md`](../infra/README.md) | Referencia técnica de los scripts de infraestructura | Vigente |
| [`../deploy/README.md`](../deploy/README.md) | Imágenes y despliegue con Compose | Vigente |
| [`../jenkins/README.md`](../jenkins/README.md) | Requisitos de Jenkins (plugins, credenciales, agente) | Vigente |
| [`estrategia-branching.md`](estrategia-branching.md) | GitHub Flow y Conventional Commits | Vigente |

## Metodología y revisiones

| Documento | Contenido | Estado |
|---|---|---|
| [`metodologia/sprint-2.md`](metodologia/sprint-2.md) | Objetivo, alcance, dependencias, DoD, métricas, review y retro | En curso |
| [`revisiones/hu-12-revision.md`](revisiones/hu-12-revision.md) | Revisión de HU-12 contra sus 9 criterios y observaciones | Cerrada |

## Evidencias por historia de usuario

| Historia | Carpeta | Estado |
|---|---|---|
| HU-01 (S1) · Infraestructura en la nube | [`evidencias/hu-01/`](evidencias/hu-01/README.md) | Completa |
| HU-02 (S1) · Imágenes Docker inmutables | [`evidencias/hu-02/`](evidencias/hu-02/README.md) | Completa |
| HU-04 (S1) · Pruebas unitarias y de integración | [`evidencias/hu-04/`](evidencias/hu-04/README.md) | Completa |
| HU-06 (S1) · Entrega continua y promoción | [`evidencias/hu-06/`](evidencias/hu-06/README.md) | Completa |
| HU-07 (S1) · Rollback, notificaciones y release notes | [`evidencias/hu-07/`](evidencias/hu-07/README.md) | Completa |
| HU-08 (S1) · Documentación y bitácora de IAG | [`evidencias/hu-08/`](evidencias/hu-08/README.md) | Completa |
| HU-09 (S2) · Terraform | [`evidencias/e2.1-terraform/`](evidencias/e2.1-terraform/README.md) | Completa (módulos, backend y apply) |
| HU-10 (S2) · Kubernetes | [`evidencias/e2.2-kubernetes/`](evidencias/e2.2-kubernetes/README.md) | Completa (dev, stage y prod) |
| HU-12 (S2) · Patrones de diseño | [`arquitectura/patrones-diseno.md`](arquitectura/patrones-diseno.md) + [`revisiones/hu-12-revision.md`](revisiones/hu-12-revision.md) | Implementada; correcciones en PR #20 |
| HU-13 (S2) · Observabilidad | [`evidencias/hu-13/`](evidencias/hu-13/README.md) | Parcial; evidencia en ejecución (PR #22) |
| HU-14 (S2) · Seguridad | [`evidencias/hu-14/`](evidencias/hu-14/README.md) + [`seguridad/hu-14.md`](seguridad/hu-14.md) | Implementada; Jenkins/K8s pendiente |
| HU-15 (S2) · Rendimiento | [`evidencias/hu-15/INFORME.md`](evidencias/hu-15/INFORME.md) | Implementada; Jenkins pendiente |
| HU-16 (S2) · Change management | [`operaciones/gestion-cambios.md`](operaciones/gestion-cambios.md) + [`evidencias/hu-16/`](evidencias/hu-16/README.md) | Procedimiento K8s listo; falta ejecutar el rollback |
| HU-17 (S2) · Documentación | este índice + [`sustentacion/resumen-ejecutivo-en.md`](sustentacion/resumen-ejecutivo-en.md) + [`evidencias/hu-17/`](evidencias/hu-17/README.md) | En curso; cierre de datos pendiente |

## Bitácora de IA generativa y decisiones

| Documento | Contenido |
|---|---|
| [`../IAG_REGISTRO.md`](../IAG_REGISTRO.md) | Anexo: índice, método de verificación y reflexión crítica |
| [`iag/README.md`](iag/README.md) | Reglas e índice de sesiones |
| [`iag/sesiones/`](iag/sesiones/) | Prompts literales y respuestas por historia |
| [`iag/decisiones.md`](iag/decisiones.md) | Decisiones D-01 a D-35 (Sprint 1 y Sprint 2) |

## Sustentación

| Documento | Contenido |
|---|---|
| [`sustentacion/guion-sprint-2.md`](sustentacion/guion-sprint-2.md) | Guion de 20–30 min, demo en vivo, falla provocada y preguntas |
| [`sustentacion/decisiones-clave.md`](sustentacion/decisiones-clave.md) | Decisiones explicadas en 30 s + Blue-Green vs Canary |
| [`sustentacion/resumen-ejecutivo-en.md`](sustentacion/resumen-ejecutivo-en.md) | Resumen ejecutivo en inglés (1 página) |
| [`sustentacion/GUION_SUSTENTACION_HU01_HU04.md`](sustentacion/GUION_SUSTENTACION_HU01_HU04.md) | Guion del Sprint 1 (HU-01 y HU-04) |

## Cómo mantener el índice

1. Todo documento nuevo se agrega aquí en el mismo PR.
2. La columna **Estado** se actualiza al cerrar la HU, no al final del sprint.
3. Una captura sin documento dueño es un archivo huérfano: se elimina o se enlaza.
4. Si un documento describe algo que no está en el código, se corrige el documento o se marca
   `Pendiente` con la HU que lo desbloquea.

# Arquitectura — índice para el cierre (HU-17)

**Estado:** vigente al 2026-11-21. Reúne los documentos que responden al criterio 1 de E2.9.

| Documento | Contenido |
|---|---|
| [`arquitectura-general.md`](../../arquitectura/arquitectura-general.md) | Vista lógica, responsabilidades, dependencias, comunicación y atributos de calidad |
| [`diagramas.md`](../../arquitectura/diagramas.md) | Diagramas de arquitectura, flujo de eventos, CI, CD e infraestructura |
| [`infra-ambientes.md`](../../arquitectura/infra-ambientes.md) | Red y hosts AWS de los tres ambientes |
| [`terraform.md`](../../arquitectura/terraform.md) | Módulos, ambientes, backend remoto y diagrama de recursos |
| [`kubernetes.md`](../../arquitectura/kubernetes.md) | Namespaces, Deployments, Services, ConfigMaps, Secrets, Ingress, HPA y probes |
| [`pipeline-cd.md`](../../arquitectura/pipeline-cd.md) | Etapas del Jenkinsfile y mapeo de ramas |
| [`patrones-diseno.md`](../../arquitectura/patrones-diseno.md) | Circuit Breaker, External Configuration, DLT y trade-offs |
| [`empaquetado-inmutable.md`](../../arquitectura/empaquetado-inmutable.md) | Imágenes inmutables y Compose por ambiente |
| [`registro-artefactos.md`](../../arquitectura/registro-artefactos.md) | Decisión del registro (CNCF Distribution) |

## Decisiones que explican la arquitectura

| Decisión | Tema |
|---|---|
| [D-25](../../iag/decisiones.md) | Registro CNCF Distribution en lugar de Nexus |
| [D-26 a D-28](../../iag/decisiones.md) | Stack de observabilidad (Prometheus, Grafana, Jaeger, Loki) |
| [D-29](../../iag/decisiones.md) | Blue-Green en prod y RollingUpdate en dev/stage |
| [D-32](../../iag/decisiones.md) | `HU-09 (S1)` vs `HU-09 (S2)` |
| [D-33](../../iag/decisiones.md) | Sin gasto no aprobado |

## Verificación

```bash
# Estado desplegado
kubectl -n circleguard-dev get pods,svc,ingress,hpa

# Infraestructura
cd infra/terraform/envs/dev && terraform output
```

Evidencias: [`../e2.1-terraform/`](../e2.1-terraform/README.md) y
[`../e2.2-kubernetes/`](../e2.2-kubernetes/README.md).

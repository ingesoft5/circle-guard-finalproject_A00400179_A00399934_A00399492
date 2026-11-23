# Evidencias E2.2 · Kubernetes (HU-10 S2)

**Estado:** implementado y desplegado en `dev`, `stage` y `prod` (PR #21). Evidencia real del
21-nov-2026: pods `1/1 Running`, servicios, Ingress y HPA.

**Documento dueño:** [`../../arquitectura/kubernetes.md`](../../arquitectura/kubernetes.md)
**Código:** [`../../../deploy/k8s/`](../../../deploy/k8s)

## Matriz de criterios

| # | Criterio | Evidencia | Estado |
|---|---|---|---|
| 1 | Clúster k3s por ambiente | `02-dev-resources.log` (pods programados en el nodo k3s) | Cumplido |
| 2 | 8 servicios + cliente web desplegados | `02-dev-resources.log` | Cumplido |
| 3 | Middleware (PostgreSQL, Neo4j, Redis, Kafka, ZooKeeper, OpenLDAP) | `02-dev-resources.log` | Cumplido |
| 4 | Pods `1/1 Running` y `Ready` | `02-dev-resources.log` | Cumplido |
| 5 | Servicios con DNS interno | `02-dev-resources.log` | Cumplido |
| 6 | Ingress (Traefik) | `01-dev-deploy.log`, `02-dev-resources.log` | Cumplido |
| 7 | HPA por servicio | `01-dev-deploy.log`, `02-dev-resources.log` | Cumplido (9 HPA) |
| 8 | Consumo de CPU (`kubectl top`) | `03-dev-top.log` | Cumplido |
| 9 | Healthcheck de la aplicación | `04-dev-health.log` | Cumplido |
| 10 | Stage desplegado | `05-stage-deploy.log`, `06-stage-resources.log` | Cumplido |
| 11 | Prod desplegado | `07-prod-deploy.log`, `08-prod-resources.log` | Cumplido |
| 12 | Despliegue desde Jenkins | [`../e2.3-pipeline/`](../e2.3-pipeline) | Cumplido (HU-11) |

## Archivos

| Archivo | Contenido |
|---|---|
| [`01-dev-deploy.log`](01-dev-deploy.log) | Despliegue en dev, pods, servicios, Ingress y HPA |
| [`02-dev-resources.log`](02-dev-resources.log) | Recursos completos de dev (`kubectl get`) |
| [`03-dev-top.log`](03-dev-top.log) | Consumo de CPU/memoria |
| [`04-dev-health.log`](04-dev-health.log) | `{"status":"UP"}` del health |
| [`05-stage-deploy.log`](05-stage-deploy.log) | Despliegue en stage |
| [`06-stage-resources.log`](06-stage-resources.log) | Recursos de stage |
| [`07-prod-deploy.log`](07-prod-deploy.log) | Despliegue en prod |
| [`08-prod-resources.log`](08-prod-resources.log) | Recursos de prod |

## Cómo se generó

```bash
export AWS_REGION=us-east-2
export KUBECONFIG=/tmp/dev.kubeconfig
aws ssm get-parameter --region "$AWS_REGION" --name /circleguard/dev/kubeconfig \
  --with-decryption --query Parameter.Value --output text > "$KUBECONFIG"

./deploy/k8s/deploy.sh dev 0.3.0
kubectl -n circleguard-dev get pods,svc,ingress,hpa
kubectl -n circleguard-dev top pods
```

## Pendiente

| Pendiente | Depende de | Impacto |
|---|---|---|
| Despliegue desde Jenkins | HU-11 | Hoy se despliega con `deploy/k8s/deploy.sh` |
| Blue-Green y rollback en K8s | HU-16 | El manifiesto base usa RollingUpdate; el rollback está implementado y pendiente de ejecutar |
| Stack de observabilidad en el clúster | HU-13 | La app está desplegada; Prometheus/Grafana/Jaeger/Loki no |
| RBAC y TLS del clúster | HU-14 | Manifiestos listos; no aplicados |

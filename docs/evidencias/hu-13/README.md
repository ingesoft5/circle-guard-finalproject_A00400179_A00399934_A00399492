# Evidencias HU-13 · Observabilidad centralizada (E2.5)

**Estado:** implementación **mergeada en `dev`** (PR #19). La evidencia está en ejecución: solo se
verificó en vivo `file-service`; faltan los otros 7 servicios, las capturas de dashboards/alerta/
traza/logs y la falla provocada.

> Guía paso a paso para ejecutar y tomar cada captura: [`00-guia-capturas.md`](00-guia-capturas.md).

## Matriz de criterios

| # | Criterio | Implementación | Evidencia | Estado |
|---|---|---|---|---|
| 1 | Métricas con Micrometer y endpoints Prometheus | Actuator + `micrometer-registry-prometheus` en los 8 servicios | [`01-actuator-prometheus.txt`](01-actuator-prometheus.txt), [`09-check-metrics.txt`](09-check-metrics.txt) | Parcial: solo `file` verificado en vivo; faltan los otros 7 |
| 2 | Prometheus recopila periódicamente | `deploy/observability/prometheus/*.yml` | [`10-prometheus-targets.txt`](10-prometheus-targets.txt) | Pendiente de ejecución |
| 3 | Dashboards por servicio y de negocio | `grafana/dashboards/service-overview.json` y `business.json` | [`02-grafana-servicio.png`](02-grafana-servicio.png), [`03-grafana-negocio.png`](03-grafana-negocio.png) | Pendiente de captura |
| 4 | Métricas técnicas y de negocio | HTTP/JVM + `circleguard.promotions`, `checkins`, `containment.time`, `notifications` | Paneles de negocio | Pendiente de captura |
| 5 | ≥ 3 alertas críticas | `circleguard-alerts.yml` (5 reglas) | [`04-alertmanager-firing.png`](04-alertmanager-firing.png), [`11-alertmanager-alerts.txt`](11-alertmanager-alerts.txt) | Pendiente de ejecución |
| 6 | Umbral, condición y severidad | Reglas con `expr`, `for`, `labels.severity` | Archivo de reglas | Cumplido (estático) |
| 7 | Trazas OpenTelemetry/Jaeger | `micrometer-tracing-bridge-otel` + collector | [`05-jaeger-traza.png`](05-jaeger-traza.png), [`12-jaeger-services.json`](12-jaeger-services.json) | Pendiente de captura |
| 8 | Traza E2E form → Kafka → promotion → notification | `observation-enabled` en productor/consumidor | Traza con cuatro spans | Pendiente de ejecución |
| 9 | Propagación de trace ID por HTTP y Kafka | `RestTemplateBuilder` + Kafka observation | [`06-kafka-headers.txt`](06-kafka-headers.txt) | Pendiente de ejecución |
| 10 | Logs centralizados | Loki + Promtail | [`07-loki-consulta.png`](07-loki-consulta.png), [`13-loki-errors.json`](13-loki-errors.json) | Pendiente de captura |
| 11 | Logs con servicio, severidad y contexto | Patrón `%X{traceId}` y logs JSON | Consulta por `traceId` | Pendiente de ejecución |
| 12 | Consultar métricas, trazas y logs ante un incidente | Runbook §9 | [`08-incidente.md`](08-incidente.md) | Pendiente de ejecución |

## Evidencia ejecutada

El 2026-11-16 se levantó `circleguard-file-service` con JDK 21 y se verificó en vivo:

- `GET /actuator` → 200, con enlaces a `health` y `prometheus`.
- `GET /actuator/health/liveness` → 200 `{"status":"UP"}`.
- `GET /actuator/health/readiness` → 200 `{"status":"UP"}`.
- `GET /actuator/prometheus` → 200 con `jvm_memory_used_bytes` y las etiquetas
  `application="circleguard-file-service"` y `environment="dev"`.

Salida completa: [`01-actuator-prometheus.txt`](01-actuator-prometheus.txt).

## Cómo generar la evidencia

### Captura automática (texto)

```bash
# 1. Servicios + middleware (Compose)
./deploy/compose-up.sh dev

# 2. Stack de observabilidad unido a la red de la app
export GRAFANA_ADMIN_USER=admin
export GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24)"
CG_APP_NETWORK=circleguard-dev_circleguard \
  docker compose -f deploy/observability/docker-compose.yml \
                 -f deploy/observability/docker-compose.compose.yml up -d

# 3. Texto: endpoints, targets, alertas, Jaeger y Loki
./deploy/observability/capture-evidence.sh localhost
```

El script escribe `09`–`13` en esta carpeta. No reemplaza las capturas manuales.

### Capturas manuales

| Archivo | Qué mostrar |
|---|---|
| `02-grafana-servicio.png` | Dashboard técnico con tráfico de los servicios |
| `03-grafana-negocio.png` | Dashboard de negocio con promociones/check-ins |
| `04-alertmanager-firing.png` | Alerta en `firing` con umbral y severidad |
| `05-jaeger-traza.png` | Traza E2E con los cuatro spans |
| `06-kafka-headers.txt` | `traceId` en los headers de Kafka |
| `07-loki-consulta.png` | Consulta por `service`, `level` y `traceId` |

### Evidencia en Kubernetes

El clúster k3s ya existe por ambiente (Terraform, HU-09) y la aplicación está desplegada (HU-10,
PR #21). Los manifiestos de `deploy/k8s/base/apps/` ya llevan las anotaciones
`prometheus.io/scrape`, `prometheus.io/port` y `prometheus.io/path`, así que Prometheus descubre los
pods **después de redesplegar** con `./deploy/k8s/deploy.sh dev 0.3.0`. Falta desplegar el stack de
observabilidad:

```bash
aws ssm get-parameter --name /circleguard/dev/kubeconfig --with-decryption \
  --query Parameter.Value --output text > /tmp/dev.kubeconfig
KUBECONFIG=/tmp/dev.kubeconfig kubectl apply -k deploy/k8s/observability
KUBECONFIG=/tmp/dev.kubeconfig kubectl -n observability get pods,svc
```

Guardar la salida como `10-k8s-observability.txt` y una captura de los pods.

## Falla provocada (para `08-incidente.md`)

1. Abrir Grafana y anotar el estado normal.
2. Detener `identity`.
3. Intentar login y registrar: 503 en `auth`, circuito abierto, alerta en Alertmanager, traza en
   Jaeger y log en Loki con el mismo `traceId`.
4. Restaurar `identity` y confirmar la recuperación.
5. Escribir hora, versión, síntoma, causa y acción.

## Pendientes y dependencias

| Pendiente | Depende de | Qué falta |
|---|---|---|
| Evidencia de los 8 servicios | — | Ejecutar `capture-evidence.sh` con el stack completo |
| Capturas de dashboards y trazas | — | Abrir Grafana/Jaeger/Loki y guardar las imágenes |
| Evidencia en K8s de la app | HU-10 (hecho, PR #21) | Desplegar el stack de observabilidad y capturar pods |
| Pipeline que despliegue en K8s | HU-11 | Etapas de `kubectl` en Jenkins |
| TLS de Grafana | HU-14 (hecho, PR #20) | Aplicar el Ingress TLS de `security/k8s/tls/` |
| Objetivos de rendimiento | HU-15 (hecho, PR #20) | Contrastar p95/throughput con los paneles |

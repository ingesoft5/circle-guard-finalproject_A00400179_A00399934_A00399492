# Evidencias HU-13 · Observabilidad centralizada (E2.5)

**Estado:** implementación en curso. Esta matriz se completa con capturas y resultados reales; no
se marca `Cumplido` sin evidencia ejecutada.

## Matriz de criterios

| # | Criterio | Implementación | Evidencia | Estado |
|---|---|---|---|---|
| 1 | Métricas con Micrometer y endpoints Prometheus | Actuator + `micrometer-registry-prometheus` en los 8 servicios | [`01-actuator-prometheus.txt`](01-actuator-prometheus.txt), `check-metrics.sh` | Cumplido en `file`; faltan los otros 7 en ejecución |
| 2 | Prometheus recopila periódicamente | `deploy/observability/prometheus/*.yml` | Targets `UP` | Parcial |
| 3 | Dashboards por servicio y de negocio | `grafana/dashboards/service-overview.json` y `business.json` | `02-grafana-servicio.png`, `03-grafana-negocio.png` | Parcial |
| 4 | Métricas técnicas y de negocio | HTTP/JVM + `circleguard.promotions`, `checkins`, `containment.time`, `notifications` | Paneles de negocio | Parcial |
| 5 | ≥ 3 alertas críticas | `circleguard-alerts.yml` (5 reglas) | `04-alertmanager-firing.png` | Parcial |
| 6 | Umbral, condición y severidad | Reglas con `expr`, `for`, `labels.severity` | Archivo de reglas | Cumplido (estático) |
| 7 | Trazas OpenTelemetry/Jaeger | `micrometer-tracing-bridge-otel` + collector | `05-jaeger-traza.png` | Parcial |
| 8 | Traza E2E form → Kafka → promotion → notification | `observation-enabled` en productor/consumidor | Traza con cuatro spans | Pendiente |
| 9 | Propagación de trace ID por HTTP y Kafka | `RestTemplateBuilder` + Kafka observation | `06-kafka-headers.txt` | Pendiente |
| 10 | Logs centralizados | Loki + Promtail | `07-loki-consulta.png` | Parcial |
| 11 | Logs con servicio, severidad y contexto | Patrón `%X{traceId}` y logs JSON | Consulta por `traceId` | Pendiente |
| 12 | Consultar métricas, trazas y logs ante un incidente | Runbook §9 | [`08-incidente.md`](08-incidente.md) (plantilla) | Pendiente de ejecución |

## Evidencia ejecutada

El 2026-11-16 se levantó `circleguard-file-service` con JDK 21 y se verificó en vivo:

- `GET /actuator` → 200, con enlaces a `health` y `prometheus`.
- `GET /actuator/health/liveness` → 200 `{"status":"UP"}`.
- `GET /actuator/health/readiness` → 200 `{"status":"UP"}`.
- `GET /actuator/prometheus` → 200 con `jvm_memory_used_bytes` y las etiquetas
  `application="circleguard-file-service"` y `environment="dev"`.

Salida completa: [`01-actuator-prometheus.txt`](01-actuator-prometheus.txt).

## Cómo generar la evidencia

```bash
# 1. Servicios
./gradlew bootRun --parallel

# 2. Stack de observabilidad
docker compose -f deploy/observability/docker-compose.yml up -d

# 3. Verificar los 8 endpoints
./deploy/observability/check-metrics.sh localhost

# 4. Targets de Prometheus
curl -s http://localhost:9090/api/v1/targets \
  | jq '.data.activeTargets[] | {scrapeUrl, health}'

# 5. Métricas de negocio
curl -s http://localhost:8088/actuator/prometheus | grep circleguard_

# 6. Logs por traceId
curl -sG http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={service="circleguard-promotion-service"} |= "ERROR"'
```

## Falla provocada (para `08-incidente.md`)

1. Abrir Grafana y anotar el estado normal.
2. Detener `identity`.
3. Intentar login y registrar: 503 en `auth`, circuito abierto, alerta en Alertmanager, traza en
   Jaeger y log en Loki con el mismo `traceId`.
4. Restaurar `identity` y confirmar la recuperación.
5. Escribir hora, versión, síntoma, causa y acción.

## Pendientes bloqueados por dependencias

| Pendiente | Depende de | Qué falta |
|---|---|---|
| Evidencia en K8s | HU-10/HU-11 | Clúster, namespaces y pipeline de despliegue |
| TLS de Grafana | HU-14 | Ingress y certificado |
| Objetivos de rendimiento | HU-15 | p95/throughput/errores de Locust |
| Captura de trazas E2E | HU-13 | Instrumentación ya hecha; falta ejecutar el flujo completo |

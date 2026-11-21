# Observabilidad de CircleGuard (HU-13)

Stack local y de Kubernetes para métricas, trazas y logs. Diseño completo y runbook:
[`../../docs/operacion/observabilidad.md`](../../docs/operacion/observabilidad.md).

## Componentes

| Componente | Local | Kubernetes |
|---|---|---|
| Prometheus | `localhost:9090` | `prometheus.observability:9090` |
| Alertmanager | `localhost:9093` | `alertmanager.observability:9093` |
| Grafana | `localhost:3000` | `grafana.observability:3000` |
| Jaeger | `localhost:16686` | `jaeger.observability:16686` |
| OTLP (collector) | `localhost:4320` | `otel-collector.observability:4318` |
| Loki | `localhost:3100` | `loki.observability:3100` |

## Credenciales

Grafana **no tiene contraseña por defecto**. Antes de levantar el stack:

```bash
export GRAFANA_ADMIN_USER=admin
export GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24)"
```

Sin `GRAFANA_ADMIN_PASSWORD`, Compose detiene el arranque con un mensaje explícito. La contraseña
no se escribe en ningún archivo versionado.

## Modo 1 · servicios con `bootRun` (local)

Los servicios escuchan en el host; Prometheus los busca en `host.docker.internal`.

```bash
# 1. Servicios (desde la raíz del repo, con las variables de entorno cargadas)
./gradlew bootRun --parallel

# 2. Stack de observabilidad
docker compose -f deploy/observability/docker-compose.yml up -d

# 3. Comprobar
curl -s http://localhost:9090/-/ready
curl -s http://localhost:3000/api/health
curl -s http://localhost:16686/
```

En este modo los logs de Loki solo aparecen si los servicios corren en contenedores
(Promtail lee el socket de Docker). Para logs, usar el modo 2.

## Modo 2 · stack completo en Compose (evidencia recomendada)

```bash
# 1. Stack de la aplicación (dev)
./deploy/compose-up.sh dev

# 2. Observabilidad unida a la red de la app
CG_APP_NETWORK=circleguard-dev_circleguard \
docker compose -f deploy/observability/docker-compose.yml \
               -f deploy/observability/docker-compose.compose.yml up -d

# 3. Verificar targets
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
```

Los servicios deben tener `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318/v1/traces`
(el `docker-compose.common.yml` ya lo define por defecto).

## Kubernetes

```bash
kubectl apply -k deploy/k8s/observability

# Secreto de Grafana (no se versiona)
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<password>'

kubectl -n observability get pods,svc
kubectl -n observability port-forward svc/grafana 3000:3000
kubectl -n observability port-forward svc/jaeger 16686:16686
```

Los pods de la aplicación deben llevar:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8180"          # puerto del servicio
  prometheus.io/path: "/actuator/prometheus"
```

## Evidencia rápida

```bash
# Targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl, health}'

# Métricas de negocio
curl -s http://localhost:8180/actuator/prometheus | grep circleguard_

# Consulta de logs (Loki)
curl -sG http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={service="circleguard-promotion-service"}' | jq '.data.result | length'

# Traza (Jaeger)
# Abrir http://localhost:16686, servicio circleguard-form-service, operación POST /api/v1/forms/survey
```

## Falla provocada (demo)

```bash
# 1. Ver el estado normal en Grafana
# 2. Detener identity
docker compose -f deploy/compose/docker-compose.common.yml stop identity
# 3. Intentar login y mirar:
#    - Grafana: 5xx en auth, circuit breaker abierto
#    - Alertmanager: HighErrorRate / CircuitBreakerOpen en firing
#    - Jaeger: traza del login que termina en auth
#    - Loki: log con "circuit" y el traceId
# 4. Restaurar
docker compose -f deploy/compose/docker-compose.common.yml start identity
```

## Alertas

Las reglas están en `prometheus/rules/circleguard-alerts.yml`. Para probar sin esperar 5 minutos,
bajar `for` a `1m` en local y restaurarlo antes de la evidencia final. Alertmanager local muestra
las alertas en la UI; para Discord, editar `alertmanager/alertmanager.yml` con el webhook (nunca
commitear la URL real).

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| Target `DOWN` | Servicio no escucha o ruta incorrecta | `curl http://<host>:<puerto>/actuator/prometheus` |
| `/actuator/prometheus` 401/404 | Seguridad o exposición | Revisar `SecurityConfig` y `management.endpoints.web.exposure.include` |
| Sin trazas en Jaeger | Endpoint OTLP incorrecto | `OTEL_EXPORTER_OTLP_ENDPOINT` debe terminar en `/v1/traces` |
| Sin logs en Loki | Promtail no ve el socket | Montar `/var/run/docker.sock`; usar modo 2 |
| Grafana sin dashboards | Provisioning mal montado | Revisar `/etc/grafana/provisioning/dashboards` |

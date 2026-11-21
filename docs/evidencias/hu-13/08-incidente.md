# 08 · Incidente provocado — identidad caída (HU-13)

**Estado: pendiente de ejecución.** Esta es la plantilla del runbook §9 de
[`../../operacion/observabilidad.md`](../../operacion/observabilidad.md). No se marca como
evidencia hasta ejecutarla y adjuntar las capturas.

**Objetivo:** demostrar que, ante una falla real, las métricas, la alerta, la traza y los logs
permiten diagnosticar el mismo incidente con el mismo `traceId`.

## Preparación

| Paso | Comando / acción | Resultado esperado |
|---|---|---|
| 1 | `docker compose -f deploy/observability/docker-compose.yml up -d` | Prometheus, Grafana, Jaeger, Loki y Alertmanager `Up` |
| 2 | Levantar los servicios con `./gradlew bootRun --parallel` | 8 servicios y middleware `healthy` |
| 3 | `./deploy/observability/check-metrics.sh localhost` | 8 endpoints `/actuator/prometheus` en 200 |
| 4 | Abrir Grafana y anotar el estado normal | Paneles de negocio y técnicos estables |
| 5 | Abrir `http://localhost:16686` (Jaeger) y `http://localhost:9090` (Prometheus) | UIs accesibles |

## Ejecución

| Paso | Acción | Qué registrar |
|---|---|---|
| 1 | Detener `circleguard-identity-service` | Hora exacta (`HH:MM:SS` UTC) y versión desplegada |
| 2 | Intentar login desde la app | Código HTTP, mensaje y `traceId` de la respuesta |
| 3 | Esperar la regla `ServiceDown` / errores 5xx | Hora en que la alerta pasa a `firing` |
| 4 | Consultar la traza en Jaeger por `traceId` | Servicios y spans de la traza (`auth → identity`) |
| 5 | Consultar Loki por el mismo `traceId` | Líneas `ERROR` con servicio, severidad y contexto |
| 6 | Levantar `identity` de nuevo | Hora de recuperación y vuelta a `UP` |

## Datos del incidente

| Campo | Valor |
|---|---|
| Fecha y hora (UTC) | |
| Versión desplegada | |
| Servicio detenido | `circleguard-identity-service` |
| Síntoma observado | |
| Código HTTP / mensaje | |
| `traceId` | |
| Alerta disparada | |
| Hora de `firing` | |
| Hora de recuperación | |
| Causa raíz | Servicio de identidad no disponible (falla provocada) |
| Acción tomada | Reiniciar el servicio y verificar readiness |

## Capturas requeridas

| Archivo | Contenido | Estado |
|---|---|---|
| `02-grafana-servicio.png` | Dashboard técnico antes y durante la falla | Pendiente |
| `03-grafana-negocio.png` | Métricas de negocio antes y durante la falla | Pendiente |
| `04-alertmanager-firing.png` | Alerta en `firing` con umbral y severidad | Pendiente |
| `05-jaeger-traza.png` | Traza con el `traceId` del incidente | Pendiente |
| `06-kafka-headers.txt` | Propagación del `traceId` por Kafka | Pendiente |
| `07-loki-consulta.png` | Consulta por `traceId` y por severidad | Pendiente |

## Conclusión

Escribir 3–5 líneas: qué señal permitió detectar la falla primero, qué señal confirmó la causa y
cuánto tardó la recuperación. Si alguna señal no apareció, anotarlo como hallazgo y abrir una tarea.

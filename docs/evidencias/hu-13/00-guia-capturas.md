# Guía de capturas · HU-13

Esta guía dice **qué ejecutar** y **dónde mirar** para producir la evidencia que falta. No sustituye
la ejecución: las capturas las toma una persona y se guardan en esta carpeta.

## 0. Elige un camino

| Camino | Cuándo usarlo | Qué necesitas |
|---|---|---|
| **A · Docker Compose** (recomendado para logs) | Tienes Docker Desktop | Docker, JDK 21, 8–10 GiB libres |
| **B · Kubernetes de `dev`** | Ya tienes acceso a AWS/kubectl | `kubectl`, `kubeconfig` de SSM, imágenes en ECR |

El camino A es el más completo porque incluye Promtail y Loki con logs de todos los contenedores.
El camino B usa la aplicación que ya está desplegada en `circleguard-dev` y solo agrega el stack de
observabilidad.

---

## Camino A · Docker Compose

### A.1 Crear los secretos locales

Docker Compose exige las variables de `.env.example`. Créalas fuera del repositorio:

```bash
mkdir -p ~/.circleguard
cat > ~/.circleguard/dev.env <<EOF
POSTGRES_USER=circleguard
POSTGRES_PASSWORD=$(openssl rand -hex 16)
NEO4J_PASSWORD=$(openssl rand -hex 16)
LDAP_ADMIN_PASSWORD=$(openssl rand -hex 16)
CG_JWT_SECRET=$(openssl rand -hex 32)
CG_QR_SECRET=$(openssl rand -hex 32)
CG_VAULT_SECRET=$(openssl rand -hex 32)
CG_VAULT_SALT=$(openssl rand -hex 16)
CG_VAULT_HASH_SALT=$(openssl rand -hex 16)
EOF
chmod 600 ~/.circleguard/dev.env
```

### A.2 Construir y levantar

```bash
export IMAGE_TAG=0.3.0
./deploy/build-images.sh "$IMAGE_TAG"
./deploy/compose-up.sh dev
```

Espera a que `./deploy/compose-up.sh` termine con todos los contenedores `healthy`.

### A.3 Levantar observabilidad

```bash
export GRAFANA_ADMIN_USER=admin
export GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24)"
echo "Grafana: $GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_PASSWORD"

CG_APP_NETWORK=circleguard-dev_circleguard \
  docker compose -f deploy/observability/docker-compose.yml \
                 -f deploy/observability/docker-compose.compose.yml up -d
```

Comprueba:

```bash
curl -s http://localhost:9090/-/ready
curl -s http://localhost:3000/api/health
curl -s http://localhost:16686/
```

### A.4 Captura automática de texto

```bash
./deploy/observability/capture-evidence.sh localhost
```

Eso escribe `09`–`13` en `docs/evidencias/hu-13/`.

---

## Camino B · Kubernetes de `dev`

### B.1 Kubeconfig

Desde la consola de AWS: **SSM Parameter Store** → `/circleguard/dev/kubeconfig` → *Show decrypted
value* → copiar todo. Guárdalo como `%USERPROFILE%\.kube\config` (Windows) o `~/.kube/config`.

O con AWS CLI:

```bash
export AWS_REGION=us-east-2
aws ssm get-parameter --region "$AWS_REGION" --name /circleguard/dev/kubeconfig \
  --with-decryption --query Parameter.Value --output text > ~/.kube/config
```

### B.2 Desplegar el stack

```bash
kubectl apply -k deploy/k8s/observability

kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability get pods,svc
```

> El secreto debe existir **antes** de que Grafana arranque; si ya estaba corriendo, reinicia el
> deployment: `kubectl -n observability rollout restart deployment/grafana`.

### B.3 Redesplegar la app con las anotaciones de Prometheus

Los manifiestos de `deploy/k8s/base/apps/` ya incluyen `prometheus.io/scrape`. Para aplicarlos:

```bash
export AWS_REGION=us-east-2
./deploy/k8s/deploy.sh dev 0.3.0
```

### B.4 Port-forward para las capturas

En terminales separadas:

```bash
kubectl -n observability port-forward svc/grafana 3000:3000
kubectl -n observability port-forward svc/prometheus 9090:9090
kubectl -n observability port-forward svc/alertmanager 9093:9093
kubectl -n observability port-forward svc/jaeger 16686:16686
kubectl -n observability port-forward svc/loki 3100:3100
```

---

## 1. Mapa de capturas

| Archivo | Dónde se ve | Qué debe aparecer |
|---|---|---|
| `02-grafana-servicio.png` | `http://localhost:3000/d/circleguard-service` | Paneles **Requests per second**, latencia y JVM con datos de los 8 servicios |
| `03-grafana-negocio.png` | `http://localhost:3000/d/circleguard-business` | **Promotions per minute**, check-ins y notificaciones con datos |
| `04-alertmanager-firing.png` | `http://localhost:9093/#/alerts` | Alerta **ServiceDown** en estado *active* con `severity="critical"` |
| `05-jaeger-traza.png` | `http://localhost:16686/search?service=circleguard-form-service` | Una traza con spans de `form`, `promotion` y `notification` (y `kafka`) |
| `06-kafka-headers.txt` | Terminal | Cabecera `traceparent` con el `traceId` del mensaje |
| `07-loki-consulta.png` | Grafana → **Explore** → datasource **Loki** | Logs filtrados por servicio, nivel y `traceId` |
| `08-incidente.md` | Markdown | Tabla llena con horas, HTTP 503, `traceId`, alerta y recuperación |
| `10-k8s-observability.txt` | Terminal | `kubectl -n observability get pods` con todo `Running` (solo camino B) |

### 02 · Dashboard técnico

1. Abre `http://localhost:3000`, inicia sesión con `admin` y la contraseña que imprimiste.
2. Menú **Dashboards** → **CircleGuard · Service overview** (UID `circleguard-service`).
3. Genera tráfico: abre la web en `http://localhost:3000` (Compose) o el Ingress de `dev`, inicia
   sesión y envía una encuesta.
4. Captura la pantalla completa, sin la barra de contraseña.

### 03 · Dashboard de negocio

1. **Dashboards** → **CircleGuard · Business** (UID `circleguard-business`).
2. Necesita al menos una encuesta con síntomas y una promoción. Si los paneles están vacíos, envía
   otra encuesta.
3. Captura **Promotions per minute**, check-ins y notificaciones.

### 04 · Alerta en `firing`

1. Deja Grafana y Prometheus abiertos y anota la hora.
2. Detén `identity`:
   - Compose: `docker stop $(docker ps -q --filter "name=identity")`
   - K8s: `kubectl -n circleguard-dev scale deployment/identity --replicas=0`
3. Espera 2–3 minutos (la regla `ServiceDown` usa `for: 2m`).
4. Captura `http://localhost:9093/#/alerts` con **ServiceDown** activa y `severity="critical"`.
   Alternativa: `http://localhost:9090/alerts` muestra el estado `firing`.
5. **Restaura identity**:
   - Compose: `docker start $(docker ps -aq --filter "name=identity")`
   - K8s: `kubectl -n circleguard-dev scale deployment/identity --replicas=1`

### 05 · Traza E2E

1. Abre `http://localhost:16686`.
2. Service = `circleguard-form-service`, Operation = `POST /api/v1/forms/survey` (o la operación
   equivalente), **Find Traces**.
3. Abre la traza más reciente y verifica que aparezcan `form`, `promotion`, `notification` y los
   spans de Kafka con el mismo `traceId`.
4. Captura la traza completa.

### 06 · Headers de Kafka

Con Compose:

```bash
docker compose --env-file deploy/compose/dev.env \
  --env-file ~/.circleguard/dev.env \
  -f deploy/compose/docker-compose.common.yml \
  -f deploy/compose/docker-compose.dev.yml \
  exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic survey.submitted \
  --property print.headers=true \
  --from-beginning
```

Con K8s:

```bash
kubectl -n circleguard-dev exec -it kafka-0 -- \
  kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic survey.submitted --property print.headers=true --from-beginning
```

Busca la cabecera `traceparent:00-<traceId>-<spanId>-01`. Copia la línea en
`docs/evidencias/hu-13/06-kafka-headers.txt`.

### 07 · Loki

1. Grafana → **Explore** → datasource **Loki**.
2. Consulta por servicio:
   ```logql
   {service="circleguard-promotion-service"} |= "ERROR"
   ```
3. Consulta por `traceId` (usa el de la traza `05`):
   ```logql
   {service=~"circleguard-.*"} | json | traceId="<traceId>"
   ```
4. Captura las líneas con `service`, `level`, `traceId` y el mensaje.

### 08 · Incidente

Sigue los pasos de [`08-incidente.md`](08-incidente.md). Mientras `identity` está detenido:

- Intenta iniciar sesión y guarda el código HTTP (503) y el `traceId` de la respuesta.
- En Jaeger, busca ese `traceId` y captura la traza `auth → identity`.
- En Loki, busca el mismo `traceId` y captura el `ERROR`.
- Restaura `identity` y anota la hora de recuperación.

Llena la tabla de `08-incidente.md` con esos datos.

---

## 3. Checklist antes de cerrar la evidencia

- [ ] `09-check-metrics.txt` con 8 `PASS`.
- [ ] `10-prometheus-targets.txt` con 8 targets `UP`.
- [ ] `02` y `03` con datos (no paneles vacíos).
- [ ] `04` con `ServiceDown` en `firing` y severidad.
- [ ] `05` con los cuatro servicios/spans y el `traceId`.
- [ ] `06` con `traceparent` y el mismo `traceId`.
- [ ] `07` con el `traceId` y el nivel.
- [ ] `08` con horas, HTTP 503 y recuperación.
- [ ] Sin contraseñas, tokens ni IPs públicas en las capturas.

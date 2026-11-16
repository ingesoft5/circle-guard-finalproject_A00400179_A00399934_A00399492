# Manual de operaciones de CircleGuard

**Documento:** HU-17 (Sprint 2 · E2.9, criterios 10 y 11)
**Última actualización:** 2026-11-16
**Alcance:** instalar, configurar, desplegar, operar, monitorear, recuperar y revertir CircleGuard.
**Estado:** procedimientos del Sprint 1 **verificados**; los de Kubernetes/Terraform están marcados
**[S2]** y se completan cuando HU-09/HU-10/HU-11/HU-13/HU-14 se mergeen.

> Este manual está escrito para que **otra persona** lo ejecute sin preguntar. Cada procedimiento
> dice qué necesita, qué comandos ejecutar, qué salida es correcta y qué hacer si falla. Si un paso
> no se puede ejecutar, es un defecto del manual: repórtelo y corríjalo.

## 1. Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| JDK | 21 | Compilar y probar los servicios |
| Docker + Compose | v2.20+ | Middleware, imágenes y ambientes locales |
| Git + Bash | Git Bash, WSL o Linux | Scripts de `deploy/` e `infra/` |
| Node.js | 22 | Cliente web y Playwright |
| AWS CLI + sesión | Rol de operador con MFA | Infraestructura en AWS |
| `kubectl` / `terraform` | 1.29+ / 1.8+ | **[S2]** Clúster e IaC |

**Regla de oro:** ningún secreto se escribe en el repositorio, en un comando que quede en el
historial ni en una captura. Se usan variables de entorno, SSM o archivos con permisos `0600`.

## 2. Instalación y configuración

### 2.1 Clonar y verificar

```bash
git clone https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492.git
cd circle-guard-finalproject_A00400179_A00399934_A00399492
git checkout dev
./gradlew --version          # debe usar Gradle 8.14 y JDK 21
```

**Salida correcta:** Gradle 8.14, JVM 21.
**Si falla:** instale JDK 21 y defina `JAVA_HOME`; en Windows use `gradlew.bat`.

### 2.2 Crear los archivos de entorno

```bash
mkdir -p ~/.circleguard
cp .env.example ~/.circleguard/dev.env
cp .env.example ~/.circleguard/dev-app.env
# complete TODOS los valores con datos aleatorios:
openssl rand -hex 24
chmod 600 ~/.circleguard/dev.env ~/.circleguard/dev-app.env
```

**Salida correcta:** `ls -l ~/.circleguard` muestra `-rw-------`.
**Nunca** copie estos archivos dentro del repositorio ni los adjunte a un issue.

### 2.3 Levantar el middleware

```bash
docker compose -f docker-compose.dev.yml --env-file "$HOME/.circleguard/dev.env" up -d
docker compose -f docker-compose.dev.yml ps
```

**Salida correcta:** PostgreSQL, Neo4j, Kafka, ZooKeeper, Redis y OpenLDAP en `healthy`.
**Si falla:** `docker compose logs <servicio>`; no ejecute `down -v` (borra los volúmenes).

### 2.4 Ejecutar los servicios en local

```bash
set -a; . "$HOME/.circleguard/dev.env"; . "$HOME/.circleguard/dev-app.env"; set +a
./gradlew bootRun --parallel
```

**Salida correcta:** cada servicio escucha en su puerto (auth 8180, identity 8083, form 8086,
promotion 8088, notification 8082, gateway 8087, dashboard 8084, file 8085).
**Si falla:** el servicio se niega a arrancar si falta una variable; revise el mensaje y complete el
archivo de entorno.

## 3. Despliegue de los servicios

### 3.1 Imágenes inmutables (HU-02)

```bash
./deploy/build-images.sh 1.0.0
./deploy/publish-images.sh 1.0.0
./deploy/verify-images.sh --evidence 1.0.0
```

**Salida correcta:** nueve imágenes `circleguard-*:1.0.0` publicadas y verificadas por digest.
**Si falla:** revise `IMAGE_REGISTRY`, el login del registro y el espacio en disco
(`docker system df`).

### 3.2 Ambientes con Compose (estado actual)

```bash
./deploy/compose-up.sh dev
./deploy/compose-down.sh dev       # conserva volúmenes
```

Stage y prod exigen `IMAGE_REGISTRY` y `IMAGE_TAG` explícitos. Guía completa:
[`../deploy/README.md`](../../deploy/README.md).

### 3.3 Pipeline (HU-06/HU-11)

| Rama | Despliega | Aprobación |
|---|---|---|
| `dev` | dev y stage | No |
| `main` | dev, stage y prod | Manual en Jenkins (24 h) |

```bash
./deploy/deploy.sh dev 1.0.0
./deploy/current-version.sh dev
```

**Salida correcta:** `deploy/releases/dev.json` con versión, commit, fecha, actor y evento; el
historial `history.tsv` crece con una línea.

### 3.4 Kubernetes **[S2]**

```bash
kubectl apply -k deploy/k8s/overlays/dev
kubectl -n circleguard-dev rollout status deployment/auth
kubectl -n circleguard-dev get pods,svc,ingress,hpa
```

**Salida correcta:** todos los pods `1/1 Running` y `Ready`.
**Si falla:** `kubectl -n circleguard-dev describe pod <pod>` y `logs <pod> --previous`.

## 4. Operación de los ambientes

| Ambiente | Propósito | Datos | Se apaga |
|---|---|---|---|
| dev | Integración y pruebas | Desechables | Sí, al terminar la sesión |
| stage | Validación previa a prod | Copia sintética | Sí |
| prod | Demostración/evaluación | Reales o sintéticos controlados | Sí, con aprobación |

**Antes de una sesión** (AWS):

```bash
bash infra/aws-session.sh login operator
bash infra/bootstrap-all.sh --plan
bash infra/bootstrap-servers.sh --apply --approve ci,nexus   # facturable
bash infra/verify-infra.sh --health --roles=ci,nexus
```

**Después de una sesión:**

```bash
bash infra/teardown.sh --stop --apply
aws ec2 describe-instances --region us-east-2 \
  --filters Name=tag:Project,Values=circleguard Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId'
```

**Salida correcta:** la lista final está vacía. Si no, detenga las instancias y regístrelo.

## 5. Monitoreo y observabilidad

### 5.1 Estado actual

- Healthchecks HTTP en Compose (`/` con 2xx–4xx aceptados).
- Jenkins conserva logs, reportes JUnit, JaCoCo y artefactos.
- **HU-13 en curso:** los servicios ya exponen `/actuator/health/*` y `/actuator/prometheus`, y el
  stack de observabilidad está en `deploy/observability/`. La evidencia K8s queda pendiente de
  HU-10/HU-11. Ver [`observabilidad.md`](observabilidad.md).

### 5.2 Estado objetivo **[S2]**

| Señal | Herramienta | Dónde mirar |
|---|---|---|
| Métricas técnicas | Prometheus + Grafana | `grafana.<host>` → dashboards por servicio |
| Métricas de negocio | Prometheus + Grafana | Promociones/min, check-ins, tiempo de contención |
| Alertas | Alertmanager | Estado `firing`, severidad y umbral |
| Trazas | Jaeger | `traceId` de `form → Kafka → promotion → notification` |
| Logs | Loki | `{service="promotion"} |= "ERROR"` |

Procedimiento completo, catálogo de métricas y alertas:
[`observabilidad.md`](observabilidad.md).

### 5.3 Investigar un incidente (runbook)

1. **¿Qué se ve?** Consulte el dashboard del servicio y el *error rate*.
2. **¿Cuándo empezó?** Compare con el registro de cambios (`deploy/releases/<env>.json`).
3. **¿Es una sola versión?** Si hay Blue-Green, compare métricas de `blue` y `green`.
4. **¿Dónde falla?** Busque el `traceId` en Jaeger y salte al log en Loki.
5. **¿Se puede revertir?** Si el fallo coincide con un despliegue, ejecute §7.
6. **Registre** hora, versión, síntoma, causa y acción en el registro de cambios.

## 6. Gestión de secretos

| Secreto | Dónde vive | Quién lo rota |
|---|---|---|
| PostgreSQL, Neo4j, LDAP | SSM SecureString + `.env` 0600 | Operador |
| `CG_JWT_SECRET`, `CG_VAULT_*`, `CG_QR_SECRET` | SSM + Secret de K8s | Responsable de seguridad |
| Credenciales de Jenkins/registro | Credenciales de Jenkins | Responsable de CI |
| Certificados TLS | Secret `tls` + renovación | Responsable de seguridad |

**Reglas:**
- Nunca `git add` de `.env`, `*.pem`, `*.key`, `kubeconfig` ni `terraform.tfstate`.
- Gitleaks se ejecuta con `infra/scan-secrets.sh`; el worktree debe dar **0 hallazgos**.
- Si un secreto se filtra: se rota, se invalida el anterior y se registra el incidente. No basta
  con borrar el commit.

## 7. Recuperación y rollback

### 7.1 Rollback con Compose (verificado en HU-07)

```bash
./deploy/rollback.sh dev 0.1.0
./deploy/current-version.sh dev
```

**Salida correcta:** evento `rollback` en `deploy/releases/dev.json`, contenedores `healthy`.
**Evidencia:** [`../evidencias/hu-07/01-rollback.txt`](../evidencias/hu-07/01-rollback.txt).

### 7.2 Rollback en Kubernetes **[S2]**

```bash
# Opción A: historial de despliegue
kubectl -n circleguard-prod rollout history deployment/auth
kubectl -n circleguard-prod rollout undo deployment/auth --to-revision=<N>
kubectl -n circleguard-prod rollout status deployment/auth

# Opción B: Blue-Green (D-29)
kubectl -n circleguard-prod patch service/auth -p '{"spec":{"selector":{"version":"blue"}}}'
kubectl -n circleguard-prod get endpoints auth
```

**Salida correcta:** pods `Ready` y el `Service` apunta a la versión anterior. Adjuntar
`kubectl get pods`, `rollout history` y el registro de cambios actualizado.

### 7.3 Recuperación de datos

- PostgreSQL: restaurar el volumen o un dump verificado; nunca improvisar sobre prod.
- Neo4j: restaurar el volumen; el grafo se puede reconstruir desde eventos si hay respaldo.
- Kafka: los eventos no consumidos permanecen en el tópico; los fallidos están en `.DLT`.
- Si un mensaje del DLT es reprocesable, se reinyecta al tópico original con un script controlado
  y se registra el `offset`.

## 8. Checklist para otra persona (criterio 11)

Marque cada paso; si algo no coincide, anótelo y deténgase.

- [ ] Cloné el repositorio y `./gradlew --version` muestra JDK 21 y Gradle 8.14.
- [ ] Creé `~/.circleguard/*.env` con permisos `0600` y sin secretos en Git.
- [ ] Levanté el middleware y los seis contenedores están `healthy`.
- [ ] Ejecuté los servicios y abrí `/swagger-ui/index.html` de al menos dos.
- [ ] Construí y publiqué las nueve imágenes con una versión semver.
- [ ] Desplegué dev y `current-version.sh dev` devuelve la versión esperada.
- [ ] Ejecuté un rollback y volví a la versión anterior.
- [ ] Encontré el registro del despliegue y del rollback en `deploy/releases/`.
- [ ] Ejecuté `infra/scan-secrets.sh` y el worktree dio PASS.
- [ ] **[S2]** Desplegué en K8s y todos los pods quedaron `Ready`.
- [ ] **[S2]** Abrí Grafana, vi una métrica y una traza en Jaeger.
- [ ] **[S2]** Provoqué una falla y la alerta se disparó.

## 9. Contactos y responsabilidades

| Rol | Persona | Responsabilidad |
|---|---|---|
| Plataforma / K8s / Terraform | Juan Esteban Sotelo | HU-09, HU-10, HU-11 (S2) |
| Patrones / seguridad / pruebas | Matt Lane | HU-12, HU-14, HU-15 (S2) |
| Observabilidad / cambios / documentación | Sebastian Cosme | HU-13, HU-16, HU-17 (S2) |

## 10. Documentos relacionados

- [`../operacion/infraestructura-aws.md`](../operacion/infraestructura-aws.md) — construir/destruir AWS.
- [`../deploy/README.md`](../../deploy/README.md) — imágenes y Compose.
- [`../jenkins/README.md`](../../jenkins/README.md) — plugins y credenciales.
- [`observabilidad.md`](observabilidad.md) — métricas, trazas y alertas.
- [`../operaciones/gestion-cambios.md`](../operaciones/gestion-cambios.md) — releases, aprobaciones y rollback formal.
- [`../operacion/analisis-costos.md`](../operacion/analisis-costos.md) — costo estimado y real.

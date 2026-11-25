# Guía de sustentación: HU-09, HU-10 y HU-11

**Para:** Juan Esteban (Terraform, Kubernetes y pipeline Jenkins)
**Uso:** léela de arriba abajo una vez. Antes de sustentar, repasa las secciones 1, 6, 7 y 8.
**Regla de oro:** di *qué problema había → qué decidimos → qué sacrificamos*. No leas diapositivas.

---

## 1. Resumen de tu parte en 60 segundos

> "Yo construí la base sobre la que corre CircleGuard en la nube. Con Terraform declaré toda la infraestructura de AWS: red, nodos, registro de imágenes, almacenamiento y el servidor de Jenkins, en tres ambientes aislados más uno de herramientas. Sobre esos nodos corre Kubernetes (k3s) con los 8 microservicios, el cliente web y el middleware, configurado con Kustomize. Y el pipeline de Jenkins une todo: compila, prueba, escanea, publica en ECR, despliega a dev, luego a stage, pide aprobación manual para prod, etiqueta, notifica por Discord y puede hacer rollback."

**Tres ideas que debes dejar claras:**
1. Todo está como código y se puede reconstruir (Terraform + Kustomize + Jenkinsfile).
2. Hay aislamiento real: un nodo, un estado de Terraform y un namespace por ambiente.
3. Las brechas están declaradas, no escondidas (UNSTABLE por dependencias, rendimiento).

---

## 2. HU-09: Terraform (E2.1)

### Qué se hizo
- `infra/terraform/` con **6 módulos**: `network`, `compute` (k3s), `registry` (ECR), `storage` (S3), `observability` (CloudWatch) y `ci-server` (Jenkins).
- **4 configuraciones** independientes: `envs/dev`, `envs/stage`, `envs/prod`, `envs/tools`.
- CIDR por ambiente: dev `10.10.0.0/16`, stage `10.20.0.0/16`, prod `10.30.0.0/16`, tools `10.40.0.0/16`.
- **Estado remoto** en S3 (versionado y cifrado) con **bloqueo en DynamoDB** (`circleguard-tflock`).
- Cada nodo es una EC2 `m7i-flex.large` con k3s y una **Elastic IP**. El `kubeconfig` queda en SSM Parameter Store.
- ECR con **9 repositorios** (8 servicios + web).
- Sin credenciales en archivos: roles IAM y SSM.

### Por qué (decisiones y trade-offs)
| Decisión | Alternativa descartada | Qué sacrificamos |
|---|---|---|
| k3s sobre EC2 | EKS | Alta disponibilidad: es un solo nodo por ambiente. Ganamos costo y rapidez. |
| Un estado por ambiente | Un estado único | Más archivos. Ganamos que un `apply` en dev nunca toca prod. |
| Módulos compartidos | Copiar código por ambiente | Más abstracción. Un cambio se prueba una vez y aplica a los tres. |
| Lock en DynamoDB | Estado local | Un recurso más. Evita dos `apply` a la vez. |
| ECR para k8s | Nexus | Ver sección 5. |

### Evidencia
- `docs/evidencias/e2.1-terraform/`: 23 logs de plan y apply.
- Build #29 (rama HU-11): `apply` en dev, stage y prod con **0 cambios**, con `Approve prod` antes de prod.
- Build de dev del 23-nov (`0.3.0-78f32ed`): stage `Terraform checks` con `fmt`, `validate` y `plan` en los tres ambientes, todos `No changes`.

### Limitaciones que debes admitir
- Un nodo por ambiente: si cae, el ambiente cae.
- Falta documentar un `terraform destroy` ejecutado. Se hace después de la sustentación.
- `TERRAFORM_APPLY` viene en `false` por defecto: el pipeline planifica siempre, aplica solo si se pide.

---

## 3. HU-10: Kubernetes (E2.2)

### Qué se hizo
- **Kustomize**: una `base` común y un `overlay` por ambiente (`deploy/k8s/overlays/{dev,stage,prod}`).
- Namespaces `circleguard-dev`, `circleguard-stage`, `circleguard-prod`.
- **8 servicios + web + middleware** (PostgreSQL, Neo4j, Redis, Kafka con ZooKeeper, OpenLDAP; los de datos como StatefulSet).
- **9 HPA** por CPU al 70 %. En prod, el gateway tiene mínimo 2 réplicas.
- `RollingUpdate` con `maxUnavailable: 0` y `maxSurge: 1`: nunca baja la capacidad durante un despliegue.
- Seguridad del pod: `runAsNonRoot` (usuario 10001), `seccomp RuntimeDefault`, `automountServiceAccountToken: false`.
- **Sondas** de readiness en `/actuator/health/readiness`.
- **Secretos**: `secrets.sh` genera valores aleatorios con `openssl`, los guarda en SSM y crea el Secret. Nada va al repositorio.
- **Ingress Traefik** con TLS como componente de Kustomize (certificado autofirmado para la IP del nodo).
- El cliente web (nginx) hace de proxy por ruta: `/auth`, `/identity`, `/form`, etc.
- Namespace `observability`: Prometheus, Grafana, Jaeger, Loki, Promtail, Alertmanager.
- `deploy.sh`: crea namespace y `ecr-pull`, aplica secretos y Kustomize, y espera el `rollout status` de cada pieza.

### Puertos (por si preguntan)
auth 8180 · identity 8083 · dashboard 8084 · file 8085 · form 8086 · gateway 8087 · notification 8082 · promotion 8088 · web 8080.

### Por qué
| Decisión | Alternativa descartada | Qué sacrificamos |
|---|---|---|
| Kustomize | Helm | Plantillas más potentes. Tres ambientes casi iguales no las justifican. |
| Middleware dentro del clúster | RDS, MSK (gestionados) | Durabilidad gestionada. Ganamos costo. |
| Un nodo por ambiente | Un clúster con 3 namespaces | Más máquinas. Ganamos aislamiento real. |
| Secretos en SSM | Secretos en el repositorio | Un paso extra al desplegar. |

### Evidencia
- `docs/evidencias/e2.2-kubernetes/`: despliegue y recursos de dev, stage y prod, `kubectl top` y health.
- `smoke-k8s.sh`: comprueba el *readiness* de los 8 servicios y el `healthz` de la web. Pasó en dev y stage.

### Limitaciones que debes admitir
- Los StatefulSet del middleware no cumplen todo el `securityContext` (hallazgos KSV-0014 y KSV-0118 de Trivy). Están cubiertos por **excepciones aprobadas** con dueño y vencimiento.
- El certificado TLS es autofirmado. `cert-manager` con DNS queda como mejora.
- No hay DNS público: se accede por la IP del nodo.

---

## 4. HU-11: pipeline CI/CD (E2.3)

### Flujo (de memoria)
1. **Checkout y Prepare**: detecta qué servicios cambiaron.
2. **Seguridad**: Trivy IaC, escaneo de secretos (Gitleaks), dependencias.
3. **Terraform checks**: `fmt`, `validate`, `plan` en dev, stage y prod.
4. **Build, pruebas unitarias con JaCoCo, paquete.**
5. **ECR build and push**: construye las 9 imágenes y las publica con tag `0.3.0-<sha>`.
6. **Trivy de imágenes**: bloquea en CRITICAL.
7. **Deploy dev → Smoke dev → ZAP → (Locust)**.
8. **Deploy stage → Smoke stage**.
9. **Approve prod** (aprobación manual con `input`).
10. **Terraform apply prod, Deploy prod, Smoke prod**.
11. **Tag release, release notes, GitHub release, Discord**.

El mismo tag recorre los tres ambientes: **no se reconstruye entre ambientes**.

### Piezas que debes saber explicar
- **Jenkinsfile declarativo, multibranch**, con **Shared Library** `circleguard` (`jenkins/vars/`).
- **`cgRun(stage)`**: función que decide qué stages corren según la rama y los parámetros. La creamos porque el `Jenkinsfile` superó el límite de tamaño de método de Groovy ("Method too large").
- **Condiciones por rama**: despliegue, ZAP y Locust solo en `dev` o `main`. Los stages de prod, el tag y el release solo en `main`.
- **Parámetros clave**:
  - `DEPLOY_MODE`: `k8s` (Parte 2), `local` (Compose) o `ssh`.
  - `SERVICES_MODE`: `changed` o `all`.
  - `RUN_TERRAFORM` y `TERRAFORM_APPLY`: plan siempre que se pida, apply solo con permiso explícito.
  - `SECURITY_GATE`: `report` o `enforce`.
  - `PUSH_TAG`, `VERSION`: control del versionado.
  - `ROLLBACK_VERSION` y `ROLLBACK_ENV`: activan el rollback.
- **Versionado**: semántico, nunca `latest`. Si `VERSION` va vacío, se calcula con Conventional Commits.
- **Commit-lint** en GitHub Actions: valida el formato `tipo(alcance): descripción` y un máximo de 72 caracteres.
- **Notificaciones**: Discord, no fatales (si Discord falla, el despliegue sigue).
- **Registro de cambios**: `record-release.sh` anota dev, stage, prod y rollback.

### Resultados verificados
| Ejecución | Resultado |
|---|---|
| Build #29 (rama HU-11) | SUCCESS. Terraform sin cambios, deploy y smoke completos. |
| Rollback #49 | SUCCESS. De `0.3.0-af89396` a `0.3.0-3f92511`, 9 deployments *rolled out*. |
| Build de dev, 23-nov (`0.3.0-78f32ed`) | **UNSTABLE**, ningún stage falló. |

**Detalle del build de dev (`0.3.0-78f32ed`):**
- Secretos: PASS.
- IaC: PASS, 0 bloqueantes y 62 hallazgos con excepción vigente.
- Terraform: `No changes` en los 3 ambientes.
- JaCoCo: **94.03 %** de cobertura de línea (gate de 60 %).
- Trivy de las 9 imágenes: sin hallazgos bloqueantes.
- Smoke: correcto en dev y stage.
- ZAP: High = 0, Medium = 1, Low = 3.
- **UNSTABLE por una sola causa:** el escaneo de dependencias (8 servicios con CRITICAL y HIGH) corre en modo `report`.

### Por qué UNSTABLE (respuesta preparada)
> "El gate de dependencias está en modo `report` a propósito. Si lo pasáramos a `enforce`, el pipeline fallaría hoy, porque hay librerías con vulnerabilidades. Lo tratamos como riesgo aceptado temporal: está documentado, tiene plan de remediación y las excepciones de IaC tienen dueño y vencimiento a 30 días. Preferimos un pipeline que informa con honestidad a uno en verde que oculta hallazgos."

### Limitaciones que debes admitir
- El pipeline **publica en ECR antes de escanear**. Si el escaneo falla, queda una imagen vulnerable en el registro. Se corrige invirtiendo el orden.
- Con `DEPLOY_MODE=k8s`, Playwright no corre: stage se promueve por *smoke*, no por E2E.
- Rendimiento: el caudal no alcanza los objetivos a 100 usuarios (ver sección 7).
- El mensaje de Discord dice "advertencias (tests base)": es una etiqueta fija vieja del `Jenkinsfile`.

---

## 5. Registro de artefactos: ¿usan Nexus?

> "Nexus Repository está instalado en el host `nexus`, pero no aceptamos su EULA, por una decisión del equipo del 3 de noviembre. El enunciado dice 'Nexus o equivalente', así que usamos dos equivalentes: **CNCF Distribution** (Apache 2.0) en el modo Compose de la Parte 1, y **Amazon ECR** en el modo Kubernetes de la Parte 2."

Documento: `docs/arquitectura/registro-artefactos.md` (tabla de alternativas: Distribution, Harbor, Zot, GHCR, ECR, Nexus OSS antiguo).

---

## 6. Demostración en vivo (guion de 5 minutos)

**Antes:**
- Enciende las EC2 (Jenkins primero) con 10 minutos de margen.
- Abre pestañas: Jenkins, GitHub, terminal con `kubectl` y Discord.
- Ten **capturas de respaldo** de Stage View por si algo falla.

**Pasos:**
1. **Estado actual del clúster** (30 s).
   - `kubectl -n circleguard-dev get pods,svc,ingress,hpa`
   - Señala: 9 pods `1/1 Running`, Ingress, 9 HPA.
2. **Lanzar el pipeline** en `main` (30 s). Muestra los parámetros: `DEPLOY_MODE=k8s`, `SERVICES_MODE`, `PUSH_TAG`.
3. **Mientras corre**, explica el flujo con el diagrama del pipeline (2 min).
4. **Aprobar prod**: muestra la pausa de `Approve prod` y aprueba (30 s).
5. **Resultado**: Stage View, aviso en Discord, tag creado (30 s).
6. **Rollback** (1 min): lanza el job con `ROLLBACK_VERSION=<versión anterior>` y `ROLLBACK_ENV=dev`. Muestra que los 9 deployments quedan *rolled out*.

**Plan B:** si Jenkins tarda, muestra la captura del build #29 y la del rollback #49 (`docs/evidencias/e2.3-pipeline/pipeline-rollback.jpg`).

**Comandos de apoyo:**
```bash
kubectl -n circleguard-dev get pods,svc,ingress,hpa
kubectl -n circleguard-dev top pods
kubectl -n circleguard-prod get deploy
kubectl -n circleguard-dev rollout status deployment/gateway
curl -s -o /dev/null -w "%{http_code}\n" http://18.224.41.57/
```

**IPs de los ambientes:** dev `18.224.41.57` · stage `18.225.129.35` · prod `18.190.106.207` · Jenkins `13.184.160.31:8080`.

---

## 7. Preguntas difíciles y cómo responderlas

**¿Por qué k3s y no EKS?**
Costo y tiempo. EKS suma el plano de control de pago y más preparación. Sacrificamos alta disponibilidad: un nodo por ambiente.

**¿Qué pasa si se cae el nodo de un ambiente?**
Ese ambiente cae. No hay réplicas de nodo. Como todo es código, se recrea con Terraform y Kustomize. Para producción real usaríamos varios nodos o EKS.

**¿Por qué Kustomize y no Helm?**
Tres ambientes casi iguales no justifican plantillas. Kustomize deja la `base` común y un parche pequeño por ambiente.

**¿Cómo manejan los secretos?**
`secrets.sh` genera valores aleatorios, los guarda en SSM Parameter Store como `SecureString` y crea el Secret de Kubernetes. Nada va al repositorio. Gitleaks escanea el árbol y el historial.

**¿Qué pasa si falla un `terraform apply`?**
El estado está en S3 con lock en DynamoDB, así que no hay dos `apply` simultáneos. El pipeline hace `plan` primero y el `apply` de prod espera `Approve prod`.

**¿Por qué el estado es por ambiente?**
Para que un cambio en dev nunca pueda tocar prod. Menor radio de impacto.

**¿Por qué el pipeline queda UNSTABLE?**
Ver la respuesta preparada en la sección 4.

**¿Por qué no pasan el gate a `enforce`?**
Hoy fallaría por las dependencias. Pasa a `enforce` cuando se actualicen las librerías o se aprueben excepciones por CVE con justificación real. Maquillar el gate no era honesto.

**¿Por qué se publica en ECR antes de escanear?**
Fue un orden heredado de la HU-11. Es una limitación conocida: si el escaneo falla, queda una imagen vulnerable. La corrección es escanear antes de publicar.

**¿Cómo funciona el rollback?**
Con `ROLLBACK_VERSION` el pipeline omite el flujo normal, redespliega esa versión anterior en los 9 deployments, espera el *rollout* y registra el evento con `record-release.sh`. No reconstruye imágenes: las versiones anteriores siguen en ECR.

**¿Y Blue-Green?**
La decisión D-29 lo documenta para prod. Antes de afirmarlo en la sustentación, confirma con el equipo qué parte está implementada. Lo verificado es: `RollingUpdate` más rollback por redespliegue de la versión anterior.

**¿Por qué no usan Nexus?**
Ver la sección 5.

**¿Cuánto costó?**
Presupuesto de 15 USD. Estimado acumulado de unos 8,5 USD. La factura real de Billing se captura antes de entregar. El riesgo principal es olvidar apagar las máquinas, por eso las apagamos al terminar y no usamos NAT Gateway ni balanceadores.

**¿Qué mejorarían?**
1. Actualizar las dependencias y pasar el gate a `enforce`.
2. Escanear antes de publicar en ECR.
3. Varios nodos o EKS, y TLS real con `cert-manager`.
4. Más recursos en los nodos para el rendimiento.

**¿Qué aprendieron?**
1. Un pipeline grande necesita las condiciones centralizadas (`cgRun`).
2. Los gates de seguridad se introducen en modo `report` y se endurecen con excepciones aprobadas.
3. El estado separado por ambiente evita accidentes.
4. Lo que no se prueba en el pipeline se rompe: el rollback solo es confiable porque se ejecutó.

---

## 8. Números para recordar

| Dato | Valor |
|---|---|
| Módulos de Terraform | 6 |
| Configuraciones de ambiente | 4 (dev, stage, prod, tools) |
| Servicios + web | 8 + 1 |
| Repositorios ECR | 9 |
| HPA | 9, CPU al 70 % |
| Cobertura JaCoCo | 94,03 % (gate 60 %) |
| ZAP | High 0, Medium 1, Low 3 |
| Excepciones IaC vigentes | 62 hallazgos cubiertos (54 filas nuevas en `exceptions.tsv`) |
| Vencimiento de excepciones | 22 y 23 de diciembre de 2026 |
| Build SUCCESS de referencia | #29 |
| Rollback de referencia | #49: `0.3.0-af89396` → `0.3.0-3f92511` |
| Versión del último build de dev | `0.3.0-78f32ed` |
| Presupuesto y gasto estimado | 15 USD y unos 8,5 USD |

---

## 9. Lista de verificación el día de la sustentación

- [ ] 4 EC2 encendidas, Jenkins responde en `:8080`.
- [ ] `curl` a la IP de dev da `200`.
- [ ] Tag `v1.0.0` publicado (o explicar por qué no).
- [ ] Capturas de respaldo abiertas.
- [ ] Introducción en inglés de 2–3 minutos practicada (`docs/sustentacion/resumen-ejecutivo-en.md`).
- [ ] Tu parte ensayada en menos de 8 minutos.
- [ ] Al terminar: `terraform destroy` y revisión de Billing.

---

## 10. Dónde está cada cosa

| Tema | Documento |
|---|---|
| Terraform | `docs/arquitectura/terraform.md` |
| Kubernetes | `docs/arquitectura/kubernetes.md` |
| Pipeline | `docs/arquitectura/pipeline-cd.md` |
| Registro y Nexus | `docs/arquitectura/registro-artefactos.md` |
| Decisiones explicadas | `docs/sustentacion/decisiones-clave.md` |
| Guion de la presentación | `docs/sustentacion/guion-sprint-2.md` |
| Seguridad y excepciones | `docs/operacion/seguridad.md` y `security/exceptions.tsv` |
| Costos | `docs/operacion/analisis-costos.md` |
| Evidencias | `docs/evidencias/e2.1-terraform/`, `e2.2-kubernetes/`, `e2.3-pipeline/` |

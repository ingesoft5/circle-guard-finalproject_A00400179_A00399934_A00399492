# Guion de sustentación — Sprint 2 (20–30 min)

**Documento:** HU-17 / rúbrica de presentación (C1–C5)
**Última actualización:** 2026-11-21
**Objetivo:** recorrer un cambio desde el commit hasta producción, explicar las decisiones y
demostrar observabilidad ante una falla provocada, sin ocultar lo que falta.

> **Estado al 23-nov.** Terraform, Kubernetes, el pipeline hacia K8s (HU-11: IaC, Trivy, apply, deploy, smoke y aprobación de prod),
> observabilidad, seguridad y rendimiento están en `dev`. Seguridad y rendimiento se ejecutaron en el Jenkins y el clúster de AWS (build #10).
> Quedan declarados: throughput de HU-15 sin cumplir, `SECURITY_GATE` en `report` y la corrección del gateway (HU-04). El rollback en K8s
> tiene evidencia de HU-16 (`docs/evidencias/e2.3-pipeline/pipeline-rollback-console.log`).

> Regla: **se muestra el sistema, no diapositivas**. Las diapositivas solo cubren decisiones,
> arquitectura y resultados que no se pueden ver en pantalla.

## 1. Reparto y tiempos

| Min | Bloque | Quién | Qué se ve | Rúbrica |
|---:|---|---|---|---|
| 0–3 | Introducción en inglés | Sebastian | Objetivo, arquitectura y resultados en una página | C5 |
| 3–7 | Arquitectura e infraestructura | Juan Esteban | Diagrama, decisiones de red y aislamiento | C1 |
| 7–12 | Terraform y Kubernetes | Juan Esteban | `terraform plan`, clúster, pods, ConfigMaps/Secrets, Ingress, HPA | C1/C2 |
| 12–18 | CI/CD en vivo | Juan Esteban + Matt | Commit → build → tests → imagen → dev → stage → aprobación → prod | C2 |
| 18–22 | Patrones y seguridad | Matt | Circuit Breaker, DLT, Trivy, RBAC, TLS | C3/C4 |
| 22–26 | Observabilidad y falla provocada | Sebastian | Grafana, alerta `firing`, traza Jaeger, log Loki | C3 |
| 26–29 | Resultados y lecciones | Matt + Sebastian | Locust vs objetivos, ZAP, costos, retrospectiva | C4 |
| 29–30 | Cierre y preguntas | Todos | Estado por criterio y enlaces | C5 |

**Si el tiempo se acorta:** se recorta la explicación de Terraform, nunca la demo de CI/CD ni la
falla provocada.

## 2. Antes de empezar (checklist T-60 min)

- [ ] Clúster encendido y `kubectl get nodes` en `Ready`.
- [ ] `ci`/`nexus` encendidos solo si la demo los usa; costo ≈ 0.20 USD/h.
- [ ] Grafana, Prometheus, Jaeger y Loki responden.
- [ ] Alertmanager con el webhook de Discord probado (mensaje de prueba).
- [ ] Versión anterior disponible para el rollback (`v0.2.0` o la que corresponda).
- [ ] Usuario, QR y encuesta de prueba cargados (sin PII).
- [ ] Jenkins abierto en una pestaña; pipeline de `dev` verde.
- [ ] Grabación de respaldo de la demo (por si falla la red).
- [ ] Capturas de Billing y de los dashboards listas como respaldo.
- [ ] Cronómetro y guion impreso.

## 3. Introducción en inglés (2–3 min, Sebastian)

> “CircleGuard is a privacy-first contact-tracing platform for university campuses. It combines a
> Spring Boot microservice architecture with an event-driven backbone: Kafka for asynchronous
> events, PostgreSQL for the identity vault, Neo4j for the anonymous contact graph, and Redis for
> access control. Our goal is to contain a possible outbreak in under 60 seconds without exposing
> student identities.
>
> The project is delivered as a monorepo with a Jenkins pipeline that builds, tests, packages,
> scans and promotes nine immutable images from dev to stage to production. In this second sprint
> we moved from Docker Compose to Terraform and Kubernetes, added observability with Prometheus,
> Grafana, Jaeger and Loki, and implemented a version-based rollback. The most important design
> decision is Blue-Green in production: we deploy a new colour, validate it, and switch the Service
> selector so a rollback takes seconds.
>
> Our current results are 269 unit tests with zero failures, over 90 % line coverage in the five
> gated services, integration tests with real Kafka and databases, and releases v0.1.0 and v0.2.0
> with rollback evidence. Everything we show today is reproducible from the repository.”

**No leer:** mirar al público, hablar despacio, señalar el diagrama.

## 4. Arquitectura e infraestructura (4 min, Juan Esteban)

1. Mostrar `docs/arquitectura/arquitectura-general.md` §1 (diagrama).
2. Explicar la regla de oro: “los nombres reales solo existen en la bóveda de identity; todo lo
   demás usa `anonymousId`”.
3. Mostrar la tabla de dependencias: dos llamadas REST, el resto Kafka.
4. Mostrar `docs/arquitectura/terraform.md` y `docs/arquitectura/kubernetes.md` (estado y
   decisiones).
5. Cerrar con el aislamiento: dev/stage/prod no se hablan; secretos en SSM; sin NAT/ELB.

**Frase de transición:** “Ahora veamos cómo un cambio llega a producción sin pasos manuales
ocultos.”

## 5. CI/CD en vivo (6 min, Juan Esteban + Matt)

### 5.1 Preparar el cambio

```bash
git checkout -b demo/sprint2
# cambio visible pero de bajo riesgo: versión en un texto o una etiqueta de UI
git commit -am "feat(demo): mostrar version en el panel"
git push origin demo/sprint2
```

### 5.2 Recorrido que se narra

| Etapa | Qué decir | Qué se ve |
|---|---|---|
| Checkout | “Detecta solo los servicios modificados.” | `SELECTED_SERVICES` |
| Build + unit | “269 pruebas, cobertura ≥ 60 %.” | Stage verde |
| Integración | “Kafka, PostgreSQL, Neo4j y Redis reales.” | Testcontainers |
| Package images | “Nueve imágenes con la misma versión.” | Log de build |
| Publish | “Registro CNCF, sin `latest`.” | Digest |
| Deploy dev | “Despliegue automático.” | Pods `Ready` |
| E2E dev | “Login, encuesta y acceso.” | Playwright |
| Deploy stage | “Misma imagen, no se reconstruye.” | Digest igual |
| Approve prod | “Aprobación manual; aquí se ve el nombre y la hora.” | Input de Jenkins |
| Deploy prod | “Blue-Green: verde listo, se conmuta el Service.” | `kubectl get deploy,svc` |
| Tag + notes | “Tag semántico y notas desde commits.” | GitHub Release |
| Notificación | “Discord con versión y resultado.” | Mensaje |

**Si algo falla:** no improvisar. Decir “este es el comportamiento esperado si X” y mostrar la
grabación o el build anterior. La rúbrica evalúa comprensión, no suerte.

## 6. Patrones y seguridad (4 min, Matt)

1. **Circuit Breaker y DLT (HU-12):** diagrama de estados; el 503 rápido sin fallback; `survey.submitted.DLT` con reintento acotado.
2. **Escaneo continuo (HU-14):** en Jenkins, stage *Security: secrets, dependencies and governed IaC*. Mostrar `security/reports/` archivado y la tabla de
   excepciones: `security/exceptions.tsv` (responsable, justificación, 30 días). Mensaje: «una excepción no oculta el hallazgo, solo cambia si bloquea».
3. **RBAC (HU-14):** `bash security/k8s/test-rbac.sh --namespace circleguard-dev` → 38/38 PASS; mostrar que el `default` no puede leer ConfigMaps. Evidencia:
   `docs/evidencias/hu-14/fase11/04-rbac-dev-despues.txt`.
4. **TLS (HU-14):** `bash security/tls/verify-tls.sh <host>.sslip.io 443 --ca dev-ca.pem` → 8/8 (TLS 1.0/1.1 rechazados, HSTS presente). Decir la limitación: la CA es de desarrollo.
5. **Hallazgo honesto:** el gateway solo deniega `CONTAGIED`/`POTENTIAL` y promoción escribe `CONFIRMED`/`SUSPECT`/`PROBABLE`; es de HU-04 y está reportado.

## 7. Observabilidad y falla provocada (4 min, Sebastian)

### 7.1 Guion de la falla

1. Abrir Grafana: dashboard de negocio con promociones/min y check-ins.
2. Abrir el dashboard de `auth`: latencia y errores.
3. **Provocar la falla:** escalar `identity` a 0 réplicas.
   ```bash
   kubectl -n circleguard-dev scale deployment/identity --replicas=0
   ```
4. Intentar login desde el cliente (o `curl`).
5. Mostrar:
   - `auth` devuelve **503**;
   - el panel de errores sube;
   - Alertmanager muestra `HighErrorRate`/`CircuitBreakerOpen` en `firing`;
   - Jaeger muestra la traza del login que termina en `auth`;
   - Loki muestra la transición `CLOSED → OPEN` con el `traceId`.
6. **Restaurar:**
   ```bash
   kubectl -n circleguard-dev scale deployment/identity --replicas=1
   ```
7. Mostrar el circuito volviendo a `CLOSED` y el login en 200.

**Frase:** “La falla no se esconde: se provoca, se observa y se recupera. Eso es observabilidad, no
solo dashboards.”

### 7.2 Si no hay clúster en vivo

Usar Compose:

```bash
docker compose -f deploy/compose/docker-compose.common.yml stop identity
# repetir login y mirar Grafana/Jaeger/Loki
docker compose -f deploy/compose/docker-compose.common.yml start identity
```

Si tampoco hay stack: mostrar la grabación y las capturas de `docs/evidencias/hu-13/`, y explicar
la decisión.

## 8. Resultados y lecciones (3 min, Matt + Sebastian)

| Tema | Mensaje |
|---|---|
| Rendimiento (HU-15) | «Objetivos declarados antes de medir. En el clúster, a 100 usuarios: p95 230 ms (acceso, objetivo 300) y 280 ms (envío, objetivo 800), errores 0 % y 0,17 %. **El throughput no cumple**: 192 de 200 y 49 de 50 req/s, aun ofreciendo 25 % más de carga. Hay un techo de capacidad cerca de ese valor; no sabemos aún si es el servicio, el nodo o el generador.» |
| Seguridad (HU-14) | «Cuatro escáneres con compuerta; un escaneo que no corre falla el build; las excepciones caducan. RBAC 38/38 y TLS 8/8 verificados en AWS. ZAP sin alertas High.» |
| Qué encontró la prueba de carga | «Una expiración de QR mal configurada: 80 % de errores en la compuerta. Corregida con prueba.» |
| Costos | «≈ 3 USD de 15; apagado a las 4 h; el EBS es el costo dominante cuando está detenido.» |
| Lecciones | «Lo más difícil fue la capacidad y el costo, no el código. Una hipótesis nuestra (que el throughput era un artefacto del generador) la refutó el dato; la corregimos en el informe.» |
| Mejoras | «E2E pasó de 2 humos a 3 flujos; cobertura bloqueante; DLT; documentación por criterio.» |

## 9. Cierre (1 min, todos)

> “Cada criterio de la rúbrica tiene un documento, un dueño y un estado en `docs/README.md`. Lo que
> está hecho se puede reproducir; lo que falta está marcado con su dependencia. No presentamos una
> maqueta: presentamos un sistema con evidencia y un plan.”

## 10. Preguntas frecuentes (respuestas de 20 s)

| Pregunta | Respuesta |
|---|---|
| ¿Por qué Blue-Green y no canary? | Rollback en segundos, sin malla de servicios ni análisis de tráfico; canary queda como evolución con métricas maduras. |
| ¿Cómo garantizan el rollback? | Se ejecutó en Compose (builds #19/#21) y se repite en K8s con `rollout undo`; el registro guarda versión, digest y aprobación. |
| ¿Qué pasa si cae identity? | El Circuit Breaker abre, `auth` devuelve 503 rápido y la alerta se dispara; no se inventa un `anonymousId`. |
| ¿Cómo evitan perder eventos? | DLT con reintento acotado; los errores de datos y negocio van directo al DLT. |
| ¿Cómo controlan el costo? | Apagado automático, sin NAT/ELB, plan antes de apply y Billing al cierre. |
| ¿La documentación está actualizada? | Cada documento tiene fecha y estado; lo pendiente dice qué HU lo desbloquea. |
| ¿Qué harían con más tiempo? | Canary con NGINX/Flagger, clúster más grande, Sonar completo y pruebas de caos. |
| ¿Por qué el throughput no cumple? | Se midió dos veces en el clúster (190 y 192 de 200; 48 y 49 de 50) aunque se ofreció 25 % más: es un techo de capacidad, no pacing. La causa (servicio, nodo único o generador) no está separada; falta medir CPU durante la prueba. No cambiamos el objetivo. |
| ¿Por qué el gate de dependencias está en `report`? | Los 8 servicios tienen 1–2 CRITICAL y 14–20 HIGH de Spring; las CRITICAL exigen Spring Boot 4 y Spring Boot 3.5.16 rompe 2 pruebas de identity. Es un riesgo aceptado con plan, responsable y fecha (2026-12-22); por eso el build queda UNSTABLE. Imágenes, secretos e IaC sí bloquean, y IaC tiene excepciones por hallazgo con dueño y 30 días. |
| ¿Cómo sabemos que un escaneo que no corre no pasa? | Sale con código 2 y el build falla; Jenkins lo demostró: sin `docker compose` el escaneo de dependencias no corrió y se corrigió para que no cuente como hallazgo ni como aprobado. |

## 11. Evidencias de respaldo (si falla la demo)

| Tema | Archivo |
|---|---|
| Pipeline y builds | `docs/evidencias/hu-06/`, `docs/evidencias/hu-07/` |
| Pruebas y cobertura | `docs/evidencias/hu-04/` |
| Patrones | `docs/arquitectura/patrones-diseno.md` |
| Observabilidad | `docs/evidencias/hu-13/` |
| Costos | `docs/operacion/analisis-costos.md` |
| Decisiones | `docs/iag/decisiones.md`, `docs/sustentacion/decisiones-clave.md` |

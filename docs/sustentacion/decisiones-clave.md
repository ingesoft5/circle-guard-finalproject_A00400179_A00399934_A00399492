# Decisiones clave y cómo explicarlas

**Documento:** guía de sustentación (HU-17 · E2.9 / rúbrica de presentación C1)
**Última actualización:** 2026-11-16
**Fuente técnica:** [`../iag/decisiones.md`](../iag/decisiones.md) (D-01 a D-35)

> La rúbrica de presentación evalúa “explicación clara de decisiones técnicas, trade-offs y
> diagramas”. Este documento no reemplaza el registro técnico: lo traduce a una explicación de
> 20–30 segundos por decisión, con la evidencia que la respalda.

## 1. Cómo usar esta guía

1. Cada integrante elige las decisiones de su HU y practica la frase de 30 segundos.
2. Nunca se lee la diapositiva: se dice **qué problema había → qué se decidió → qué se sacrificó**.
3. Si preguntan “¿por qué no X?”, la respuesta está en la columna *Alternativa descartada*.
4. La evidencia se muestra en pantalla solo si aporta; si no, se dice dónde está.

## 2. Decisiones transversales (las que más preguntan)

| # | Decisión | Explicación de 30 s | Alternativa descartada | Evidencia |
|---|---|---|---|---|
| D-01 | PR de cada HU hacia `dev` | “`main` solo recibe `dev`; así `main` siempre es desplegable y el PR muestra solo los commits de la historia.” | PR directo a `main` (arrastra trabajo ajeno) | `docs/estrategia-branching.md` |
| D-02 | Bash portable, no WSL | “El equipo desarrolla en Windows, pero los hosts son Linux; los scripts no asumen rutas ni PowerShell.” | Scripts de WSL o PowerShell | `infra/README.md` |
| D-04 | No tocar el código base en HU-02 | “La historia era de empaquetado; adaptamos el cliente dentro del Dockerfile para no mezclar responsabilidades.” | Editar YAML y `Config.ts` | `docs/arquitectura/empaquetado-inmutable.md` |
| D-05 | Compose base + overrides | “Una sola verdad para los 15 contenedores y un archivo por ambiente con solo las diferencias.” | Tres archivos duplicados | `deploy/compose/` |
| D-07 | Semver obligatorio, sin `latest` | “Una imagen `latest` no se puede reproducir ni revertir; el pipeline rechaza tags flotantes.” | `latest` o tags manuales | `deploy/lib.sh` |
| D-14 | `pollSCM` en vez de webhook | “Jenkins no está expuesto a Internet; el polling cada 5 min evita abrir un puerto y mantiene el flujo.” | Webhook con TLS/relé | `Jenkinsfile` |
| D-19 | Notificación no fatal | “Si Discord falla, el despliegue no se cae; la notificación es evidencia, no un gate.” | Bloquear el pipeline por la notificación | `deploy/notify.sh` |
| D-25 | CNCF Distribution en vez de Nexus | “Nexus exige aceptar un EULA; Distribution es Apache 2.0, compatible con OCI y suficiente para el curso.” | Aceptar el EULA de Sonatype | `docs/arquitectura/registro-artefactos.md` |
| D-29 | Blue-Green en prod | “Desplegamos el color nuevo, validamos y conmutamos el Service; volver es cambiar el selector.” | Canary / Istio | Este documento §3 |
| D-32 | `HU-09 (S1)` vs `HU-09 (S2)` | “El Sprint 1 y el Sprint 2 reutilizan el número 09; el sufijo evita confundir branching con Terraform.” | Renombrar ramas | `docs/iag/decisiones.md` |
| D-33 | Sin gasto no aprobado | “Terraform puede crear recursos facturables; nada se aplica sin plan revisado y aprobación.” | Aplicar y ver después | `docs/operacion/analisis-costos.md` |

## 3. Estrategia de despliegue: Blue-Green vs Canary

### 3.1 Contexto del proyecto

- Ocho microservicios + middleware, tres ambientes, un equipo de tres personas.
- Clúster pequeño (2 vCPU / 8 GiB por nodo), presupuesto de 15 USD.
- Pipeline con aprobación manual y notificaciones ya funcionando.
- La rúbrica pide **rollback real en Kubernetes** (C7) y menciona canary solo como **bonus** de
  service mesh.

### 3.2 Comparación

| Criterio | RollingUpdate | **Blue-Green** | Canary (NGINX/Ingress) | Canary (Istio/Flagger) |
|---|---|---|---|---|
| Complejidad de implementación | Baja | **Media** | Media | Alta |
| Recursos extra | 0 | **1 réplica del servicio** | 1 réplica parcial | 1 réplica + sidecars + control plane |
| Rollback | `rollout undo` | **Cambiar selector** | Cambiar peso a 0 | Cambiar peso a 0 |
| Validación antes del 100 % | Probes | **Smoke test al color nuevo** | % de tráfico real | % + análisis automático |
| Métricas necesarias | Básicas | **Básicas** | p95/errores por versión | p95/errores + Prometheus |
| Encaja con 3 personas y 2 vCPU | Sí | **Sí** | Sí, con cuidado | No para la entrega |
| Bonus de rúbrica | No | No | Parcial | Sí (+0.10) |

### 3.3 Recomendación

**Blue-Green en producción y RollingUpdate en dev/stage.**

Razones:

1. **Cumple el criterio central**: permite volver a la versión anterior con un cambio de selector y
   deja evidencia clara (`kubectl get deploy`, `endpoints`, `pods`).
2. **No exige infraestructura extra**: solo duplica el servicio que se despliega, no el stack.
3. **Es explicable en 30 segundos** y demostrable en vivo sin depender de una malla de servicios.
4. **Canary sería más fino, pero más frágil para la demo**: sin métricas maduras, un canary al 10 %
   no dice nada; con Istio, el clúster de 2 vCPU y el tiempo del equipo no alcanzan para operarlo
   con seguridad.

**Cuándo cambiar a canary:** cuando HU-13 tenga Prometheus estable, NGINX Ingress con
`canary-weight` y un análisis automático de p95/errores por versión. Se puede presentar como
evolución, no como deuda.

### 3.4 Requisito que casi nadie menciona

Blue-Green obliga a que la base de datos sea **compatible hacia atrás** (expand-contract) porque las
dos versiones conviven unos minutos. Lo mismo aplica a los contratos de Kafka y Redis. Si se olvida,
el rollback “funciona” pero los datos quedan inconsistentes.

## 4. Decisiones de HU-12 (patrones)

| Decisión | Explicación | Trade-off |
|---|---|---|
| Circuit Breaker en `auth → identity` | “Si identity se cuelga, no queremos hilos esperando para siempre; el circuito abre y devolvemos 503 rápido.” | Durante 10 s se rechazan logins legítimos |
| Sin fallback de `anonymousId` | “Inventar un ID rompería la anonimización; es mejor fallar que mentir.” | El login no funciona sin identity (deliberado) |
| External Configuration | “URL, timeouts y umbrales se cambian por ambiente sin recompilar.” | El despliegue debe definir la URL |
| Dead Letter Topic | “Un evento que no se puede procesar va a `.DLT` en vez de perderse; el consumidor sigue.” | Entrega al menos una vez: posibles duplicados |
| DLT para errores de datos y negocio | “Reintentar un `FenceException` no cambia el resultado; va directo al DLT.” | Hay que vigilar y reprocesar el DLT |

## 5. Decisiones de HU-13 (observabilidad)

| Decisión | Explicación | Trade-off |
|---|---|---|
| Prometheus + Grafana | “Es el estándar de facto y se integra con Actuator sin agente.” | Cardinalidad: no se etiqueta por usuario |
| Jaeger + OpenTelemetry | “Permite seguir una solicitud por HTTP y por Kafka con el mismo `traceId`.” | Muestreo: no se guardan todas las trazas |
| Loki en vez de ELK | “Indexa etiquetas, no texto completo; cabe en el clúster y cumple el criterio.” | Búsquedas menos potentes que Elasticsearch |
| Alertas con umbral y `for` | “Una alerta sin umbral ni duración es ruido; las tres tienen condición y severidad.” | Hay que calibrar con tráfico real |
| Fallo provocado en la demo | “Detenemos identity y mostramos 503, circuito abierto, traza y log con el mismo `traceId`.” | Requiere ensayo previo |

## 6. Decisiones de HU-16 (cambios y rollback)

| Decisión | Explicación | Trade-off |
|---|---|---|
| Tag semántico solo en `main` | “`dev` integra; `main` publica. El tag identifica lo que llegó a prod.” | `dev` usa versión con SHA |
| Release notes desde commits | “Se generan del historial real, no de una lista manual.” | Requiere Conventional Commits |
| Registro por ambiente con digest | “Saber qué imagen exacta corrió, quién la aprobó y qué pasó.” | Más campos que mantener |
| Rollback probado, no solo escrito | “La rúbrica pide evidencia; ejecutamos el rollback y adjuntamos logs.” | Consume una sesión de clúster |

## 7. Preguntas probables y respuestas cortas

| Pregunta | Respuesta |
|---|---|
| “¿Por qué no usaron canary?” | “Porque exige dividir tráfico y analizar métricas por versión; con 2 vCPU y tres personas, Blue-Green da el rollback exigido con menos superficie de fallo. Canary queda como evolución.” |
| “¿Blue-Green no duplica el costo?” | “Duplica solo el servicio que se despliega durante la ventana, no los tres ambientes. En la demo se apaga al terminar.” |
| “¿Qué pasa si la base cambia?” | “La migración debe ser expand-contract: agregar compatible, desplegar, migrar datos, retirar lo viejo. Está en el manual.” |
| “¿Por qué Loki y no ELK?” | “El criterio acepta ambos; Elasticsearch pide ≈ 1 GiB de heap y el clúster es pequeño. Loki cumple con menos memoria.” |
| “¿Cómo saben que el rollback funciona?” | “Se ejecutó en Compose (builds #19 y #21) y se repite en K8s con `rollout undo` y captura de pods `Ready`.” |
| “¿Las métricas son reales o inventadas?” | “Salen de Actuator/Micrometer y de contadores de negocio; los dashboards se aprovisionan como código, no a mano.” |
| “¿Qué falta?” | “La lista está en `docs/README.md`: cada criterio tiene estado y dueño. Lo pendiente está marcado, no escondido.” |
| “¿Cómo controlan el costo?” | “Apagado a las 4 h, sin NAT/ELB, `terraform plan` antes de apply y captura de Billing. Estimado ≈ 3 USD de 15.” |

## 8. Regla de oro para la sustentación

No decir “quedó pendiente” sin decir **por qué**, **quién** y **cuándo**. Una limitación explicada
con plan vale más que una funcionalidad a medias presentada como completa.

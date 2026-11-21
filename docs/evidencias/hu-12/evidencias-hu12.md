# Evidencias de HU-12 · Patrones de diseño (E2.4)

Este archivo reúne la evidencia ejecutada de HU-12: qué se probó, con qué resultado, cuándo y cómo repetirlo. La
explicación de cada patrón (propósito, trade-offs, componentes) está en
[patrones-diseno.md](../../arquitectura/patrones-diseno.md); aquí solo está lo verificable.

| Dato | Valor |
|---|---|
| Fecha de la ejecución | 2026-11-16, entre 14:15 y 14:41 (hora de Bogotá; los XML de JUnit la guardan en UTC, 19:15–19:41) |
| Código probado | El de la rama `HU14-fortalecimiento-seguridad-plataforma` en el commit `9753d6e` (sin cambios de código posteriores a la corrida) |
| Entorno | WSL Ubuntu, JDK 21.0.13, Gradle 8.14 (wrapper), Docker 29.2 con Testcontainers (Kafka `cp-kafka:7.5.3`, Postgres 15, Neo4j 5.12, Redis 7.2) |
| Quién la ejecutó | El agente de IA en la máquina del autor; no es una ejecución de Jenkins (ver «Limitaciones») |

## 1. Resultado por criterio de aceptación

| Criterio | Estado | Dónde está la evidencia | Cómo verla |
|---|---|---|---|
| CA-01/CA-02 Inventario de patrones existentes, verificado en el código | Cumplido | [patrones-diseno.md §B](../../arquitectura/patrones-diseno.md#b-inventario-de-patrones-existentes-ca-01-ca-02) | Cada patrón trae archivo y línea. Estado: Database per Service ✅, eventos ✅, API Gateway ⚠️, Cache-Aside ⚠️, máquina de estados ⚠️ |
| CA-03 Resiliencia con Resilience4j | Cumplido | [IdentityClient.java](../../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/client/IdentityClient.java), [LoginController.java](../../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/controller/LoginController.java) | Pruebas de la §3, grupo «Circuit Breaker» |
| CA-04 Configuración externa | Cumplido | [IdentityClientProperties.java](../../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/client/IdentityClientProperties.java), [application.yml](../../../services/circleguard-auth-service/src/main/resources/application.yml) | Pruebas de la §3, grupo «External Configuration» |
| CA-05 Tercer patrón: Dead Letter Topic | Cumplido | [promotion](../../../services/circleguard-promotion-service/src/main/java/com/circleguard/promotion/config/KafkaErrorHandlingConfig.java) y [notification](../../../services/circleguard-notification-service/src/main/java/com/circleguard/notification/config/KafkaErrorHandlingConfig.java) | Pruebas de la §3, grupo «Dead Letter Topic» |
| CA-06 Documentación y trade-offs | Cumplido | [patrones-diseno.md §C](../../arquitectura/patrones-diseno.md#c-patrones-implementados-o-mejorados) | Cada patrón: propósito, problema, componentes, ventajas, desventajas |
| CA-07 Pruebas con falla inyectada | Cumplido | Esta carpeta, §2 y §3 | Resultados reales de JUnit |
| CA-08 Compatibilidad con lo existente | Cumplido | Esta carpeta, §2 | Suites completas con el gate de cobertura activo: 0 fallos |

## 2. Resultados de las suites

Comandos ejecutados desde la raíz del repositorio:

```bash
./gradlew :services:circleguard-auth-service:test :services:circleguard-promotion-service:test :services:circleguard-notification-service:test
./gradlew :tests:integration:integrationTest :services:circleguard-promotion-service:integrationTest
```

| Suite | Pruebas | Fallos | Errores | Cobertura de líneas |
|---|---|---|---|---|
| auth, unitarias | 57 | 0 | 0 | 196 de 199 = 98,5 % (mínimo exigido: 60 %) |
| promotion, unitarias | 125 | 0 | 0 | 656 de 718 = 91,4 % (mínimo exigido: 60 %) |
| notification, unitarias | 20 | 0 | 0 | 122 de 182 = 67,0 % (sin gate) |
| `tests:integration` (Kafka, Postgres, Neo4j y Redis reales) | 11 | 0 | 0 | no aplica |
| promotion `integrationTest` | 6 | 0 | 0 | no aplica |

Ambos comandos terminaron en `BUILD SUCCESSFUL`.

Detalle por clase de prueba (dato de los XML de JUnit):

| Clase | Pruebas | Fallos | Tiempo |
|---|---|---|---|
| `IdentityClientTest` | 5 | 0 | 4,2 s |
| `IdentityClientTest$CircuitBreakerWithInjectedFaults` | 6 | 0 | 2,3 s |
| `IdentityClientTest$ExternalConfiguration` | 4 | 0 | 2,7 s |
| `LoginControllerFlowsTest` | 5 | 0 | 1,9 s |
| `DeadLetterHandlingTest` (notification) | 9 | 0 | 9,7 s |
| `DeadLetterTopicIntegrationTest` (Kafka real) | 6 | 0 | 28,8 s |
| `FormToPromotionIntegrationTest` (HU-04) | 3 | 0 | 2,5 s |
| `PromotionToNotificationIntegrationTest` (HU-04) | 2 | 0 | 1,5 s |
| `SurveyListenerTest` (promotion) | 2 | 0 | 0,03 s |

## 3. Pruebas con falla inyectada, caso por caso

Todas pasaron.

### Circuit Breaker · [IdentityClientTest.java](../../../services/circleguard-auth-service/src/test/java/com/circleguard/auth/client/IdentityClientTest.java)

Un servidor HTTP real del JDK hace de identity-service y se le inyectan fallas; no hay mocks del breaker.

| Caso | Falla inyectada | Qué demuestra |
|---|---|---|
| `staysClosedWhileIdentityServiceIsHealthy` | ninguna | El circuito sigue cerrado con un servidor sano |
| `opensAtTheFailureThresholdAndThenRejectsWithoutCallingIdentityService` | respuestas 500 | Abre al llegar al umbral y rechaza sin llamar al servidor |
| `recoversThroughHalfOpenAndClosesAgainWhenIdentityServiceIsBack` | 500 y luego servidor sano | OPEN → HALF_OPEN → CLOSED |
| `reopensIfTheTrialCallsFail` | 500 persistente | Vuelve a abrir si las llamadas de prueba fallan |
| `aResponseSlowerThanTheReadTimeoutCountsAsAFailure` | respuesta más lenta que el timeout | Un timeout cuenta como fallo |
| `clientErrorsAreBusinessErrorsAndDoNotOpenTheCircuit` | respuestas 400 | Los 4xx no abren el circuito |
| `getAnonymousId_WithAnEmptyBody…`, `…WithoutTheAnonymousIdField…`, `…WithAMalformedAnonymousId…` | cuerpo vacío, campo ausente, UUID mal formado | Se informa «identity no disponible» (503), no un 500 |

### External Configuration · mismo archivo

| Caso | Qué demuestra |
|---|---|
| `defaultsAreSafeAndKeepTheAddressTheClientAlwaysUsed` | Valores por defecto seguros, sin credenciales |
| `bindsTheTypedPropertiesFromTheEnvironment` | Enlace tipado desde propiedades |
| `environmentVariablesOverrideTheDefaultsThroughRelaxedBinding` | Sobrescritura con `CIRCLEGUARD_IDENTITYSERVICE_URL` y similares |
| `changingOnlyTheConfigurationChangesWhenTheCircuitOpens` | Cambiar solo la configuración cambia cuándo abre el circuito |

### Dead Letter Topic

[DeadLetterTopicIntegrationTest.java](../../../tests/integration/src/test/java/com/circleguard/it/DeadLetterTopicIntegrationTest.java) usa un Kafka real:

| Caso | Qué demuestra |
|---|---|
| Evento de encuesta malformado | Llega a `survey.submitted.DLT` y el consumidor real de promotion sigue procesando |
| Bytes que no son JSON | Llegan al DLT sin alterarse (`ErrorHandlingDeserializer`) y el consumo continúa |
| Eventos malformados en los tres tópicos de notification | Cada uno va a su `.DLT` y un cambio de estado posterior se sigue notificando |
| Fallo transitorio | Se reintenta (3 entregas) y se recupera sin pasar por el DLT |
| Fallo permanente | Se entrega 1 + 2 veces y va al DLT |
| Errores de datos y de negocio | No se reintentan: directo al DLT |

[DeadLetterHandlingTest.java](../../../services/circleguard-notification-service/src/test/java/com/circleguard/notification/service/DeadLetterHandlingTest.java) (9 casos) comprueba que los tres listeners de notification ya no
tragan la excepción y que el manejador reintenta lo transitorio y manda lo malformado al DLT sin reintento.

## 4. Cómo repetirlo

Requiere JDK 21. Las pruebas de integración requieren Docker encendido.

```bash
# Todas las de HU-12 (≈2,5 min cada comando)
./gradlew :services:circleguard-auth-service:test :services:circleguard-promotion-service:test :services:circleguard-notification-service:test
./gradlew :tests:integration:integrationTest :services:circleguard-promotion-service:integrationTest

# Solo las de HU-12 (los filtros exigen omitir el gate de cobertura)
./gradlew :services:circleguard-auth-service:test --tests '*IdentityClientTest*' --tests '*LoginController*' -x jacocoTestCoverageVerification
./gradlew :tests:integration:integrationTest --tests '*DeadLetterTopicIntegrationTest'
```

Reportes HTML tras la ejecución: `services/<servicio>/build/reports/tests/test/index.html` y
`tests/integration/build/reports/tests/integrationTest/index.html`.

## 5. Compatibilidad con HU-13 (integración con Micrometer)

HU-13 cambia `IdentityClient` para usar un `CircuitBreakerRegistry` compartido y publicar `resilience4j_circuitbreaker_state`
(rama `origin/HU-13-Observabilidad-centralizada-E2.5`, commit `18e5871`). El 2026-11-16 se comprobó, sin modificar ninguna rama:

- `git merge-tree` entre `HEAD` (`9753d6e`) y esa rama: **fusión sin conflictos**.
- Copia aislada del resultado de la fusión, con `./gradlew` sobre auth, promotion, notification, gateway y dashboard
  (gate de cobertura activo): `BUILD SUCCESSFUL` en 6 min 49 s. auth 58 pruebas (las 57 de HU-12 más `ObservabilityConfigTest`),
  promotion 125, notification 20, gateway 11, dashboard 2: **0 fallos, 0 errores**.
- No se ejecutaron las pruebas de integración sobre esa copia.

## 6. Limitaciones de esta evidencia

- **No es una ejecución de Jenkins.** Se ejecutó en la máquina del autor (WSL). El revisor pidió repetirla en Jenkins o en un
  equipo con JDK 21 (observación O3 de [la revisión](../../revisiones/hu-12-revision.md), si ya está integrada en la rama).
- **Auth no se volvió a ejecutar en la última corrida.** Gradle reutilizó el resultado de la ejecución anterior porque el código
  no había cambiado (los XML de auth son de las 14:16, los demás de las 14:35 a 14:40). El código es el mismo.
- **No hay captura de pantalla ni log crudo versionado:** las tablas se generaron a partir de los XML de JUnit de esa ejecución.
- **El login dentro de contenedores sigue pendiente** de definir `CIRCLEGUARD_IDENTITYSERVICE_URL` en Compose y Kubernetes
  (observación O1; depende de HU-10/HU-11). Está probado a nivel de código, no en un despliegue.
- **Los diagramas Mermaid de patrones-diseno.md** no se vieron renderizados en esta sesión.

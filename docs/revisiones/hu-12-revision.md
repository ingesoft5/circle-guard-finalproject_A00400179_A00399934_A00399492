# Revisión de HU-12 (Sprint 2 · E2.4) — PR #14

**Revisor:** Sebastian Cosme Benitez
**Fecha:** 2026-11-16
**Commit revisado:** `6659e1b` (merge del PR #14 `HU12-Implementacion-patrones-diseno` en `dev`)
**Jira:** PDDZ-67 · HU-12 – Implementación de patrones de diseño (E2.4)
**Estado en Jira al revisar:** *En curso*

## 1. Veredicto

**Cumple los nueve criterios de aceptación (9/9) y la calidad de la evidencia es alta.** La
documentación identifica patrones reales con archivo y línea, distingue lo implementado de lo
parcial y declara las limitaciones en lugar de esconderlas. Es, hasta ahora, el entregable mejor
trazado del Sprint 2.

No se considera **cerrada** por tres observaciones de integración (§4). Ninguna invalida el
trabajo; dos son de despliegue (HU-10/HU-11) y una es de repetibilidad de la evidencia.

## 2. Matriz criterio por criterio

| # | Criterio | Evidencia verificada | Veredicto |
|---|---|---|---|
| 1 | Inventario de patrones existentes | `docs/arquitectura/patrones-diseno.md` §B: Database per Service, eventos, API Gateway, Cache-Aside, máquina de estados, Retry y Feature Toggle, con estado y ubicación | Cumplido |
| 2 | Documentar Database per Service, eventos, API Gateway, Cache-Aside y máquina de estados | §B.1–B.5, cada uno con funcionamiento, beneficios y limitaciones | Cumplido |
| 3 | Patrón de resiliencia con Resilience4j | `IdentityClient` con `CircuitBreaker.of("identity-service")` (`:67`), timeouts, mapeo a 503 en `LoginController:50`; 12 pruebas en `IdentityClientTest` | Cumplido |
| 4 | Patrón de configuración | `IdentityClientProperties` con `@ConfigurationProperties("circleguard.identity-service")`; URL, timeouts y umbrales sobrescribibles; 4 pruebas de configuración | Cumplido con observación O2 |
| 5 | Tercer patrón justificado | Dead Letter Topic en `KafkaErrorHandlingConfig`; `SurveyListener` deja de tragar excepciones; justificación y alternativas en §C.3 | Cumplido |
| 6 | Documentar propósito, problema, componentes y ubicación | Tablas de componentes y diagramas *antes/después* para los tres patrones | Cumplido |
| 7 | Trade-offs y desventajas | Tablas de ventajas/desventajas por patrón, incluida la entrega *al menos una vez* del DLT | Cumplido |
| 8 | Al menos una prueba por patrón | `IdentityClientTest` (12), `LoginControllerFlowsTest` (5), `DeadLetterTopicIntegrationTest` (4, Kafka real) | Cumplido (ver O3) |
| 9 | No afectar negativamente los servicios existentes | Cambios acotados a auth y promotion; suite reportada `BUILD SUCCESSFUL` (auth 54, promotion 125, notification 11) | Cumplido con observación O1 |

## 3. Lo que está bien

- **El inventario es honesto.** No cuenta una dependencia como patrón: por ejemplo, dice que
  `circleguard-gateway-service` **no** es un API Gateway y que `getCachedStatus` no se usa en
  producción. Eso vale más que un listado de tecnologías.
- **Los diagramas *antes/después* explican el problema**, no solo la solución. Sirven para la
  sustentación sin preparar otra cosa.
- **La configuración no tiene credenciales** y todos los valores tienen un valor por defecto
  seguro. El *relaxed binding* está explicado con el nombre exacto de la variable.
- **El DLT distingue errores transitorios de errores de datos.** `ClassCastException`,
  `IllegalArgumentException` y `FenceException` no se reintentan; el resto sí (2 reintentos, 3
  entregas). Es la decisión correcta: reintentar una regla de negocio no cambia el resultado.
- **Reporta siete hallazgos fuera de alcance** (§F), incluido el defecto del gateway que no bloquea
  los estados reales (`SUSPECT`, `PROBABLE`, `CONFIRMED`). Ese hallazgo es material para la
  sustentación y para HU-14.

## 4. Observaciones (qué falta para cerrar)

### O1 · El login falla dentro de Compose/Kubernetes (bloqueante de integración)

`IdentityClientProperties.url` vale `http://localhost:8083` por defecto. El servicio `auth` de
`deploy/compose/docker-compose.common.yml` **no** define `CIRCLEGUARD_IDENTITYSERVICE_URL`, así que
dentro del contenedor `localhost` es el propio `auth`, no `identity`. El login devolverá 503 (o
timeout) en los ambientes.

No es una regresión de HU-12: el código anterior también tenía `localhost:8083` fijo. Pero HU-12
hace la URL configurable y aun así el despliegue no la configura. **Acción:** agregar
`CIRCLEGUARD_IDENTITYSERVICE_URL: http://identity:8083` al servicio `auth` en Compose y en los
manifiestos/Helm de HU-10, y `circleguard.promotion-service.url` al `dashboard` (mismo patrón).
Dueño sugerido: HU-10/HU-11 (Juan Esteban), con verificación de Sebastián en HU-13 al levantar el
stack.

### O2 · La configuración no está visible en `application.yml`

`grep` de `circleguard.identity-service` en `services/circleguard-auth-service/src/main/resources/application.yml`
no devuelve nada. El patrón funciona por los valores por defecto de la clase, pero un integrante
nuevo no descubre la propiedad leyendo el YAML. **Acción:** agregar el bloque con los valores por
defecto (sin secretos) y un comentario que remita a la tabla de §C.2. Es un cambio de una línea por
propiedad y no altera comportamiento.

### O3 · La suite no se pudo re-ejecutar en esta revisión

El equipo reporta `BUILD SUCCESSFUL` con 54 + 125 + 11 pruebas y 0 fallos, y el documento da los
comandos exactos. En esta máquina no hay JDK 21 y la autoprovisión de toolchains falló
(`Cannot find a Java installation ... languageVersion=21`), así que la revisión es estática sobre
el código y sobre la evidencia reportada. **Acción:** repetir los tres comandos en Jenkins o en un
equipo con JDK 21 y adjuntar el `BUILD SUCCESSFUL` al cierre de la HU.

## 5. Hallazgos menores (no bloquean)

| Hallazgo | Impacto | Sugerencia |
|---|---|---|
| `IdentityClient.getAnonymousId` hace `response.get(...)` sin comprobar `null`; un 200 con cuerpo vacío produce NPE y 500 | Bajo | Validar la respuesta y lanzar `IdentityServiceUnavailableException` o una excepción de datos |
| `UUID.fromString` puede lanzar `IllegalArgumentException` y se convierte en 500 | Bajo | Capturarla y devolver 502/503 con mensaje claro |
| `LoginController` imprime la longitud de la contraseña y usa `printStackTrace` | Medio (higiene y logs) | Migrar a SLF4J; no registrar datos del intento |
| Los consumidores de `notification` siguen con `catch (Exception)` y descartan eventos | Medio | Aplicar el mismo `CommonErrorHandler` en una historia posterior |
| Un JSON no deserializable sigue bloqueando la partición | Medio | `ErrorHandlingDeserializer` + segundo `KafkaTemplate` (D-34) |
| El DLT se crea por auto-creación del broker | Bajo | Declarar los tópicos `.DLT` en el bootstrap de Kafka |

## 6. Evidencia que debe enlazarse en Jira

- PR #14 y commits `63bb2ef`, `e5fc48d`, `bfd7b38`.
- `docs/arquitectura/patrones-diseno.md` (documento principal).
- `IdentityClientTest`, `LoginControllerFlowsTest`, `DeadLetterTopicIntegrationTest`.
- Capturas adjuntas en PDDZ-67 (tres PNG del 14 y 15 de noviembre).
- Resultado de la suite completa al cerrar O3.

## 7. Recomendación

Aprobar el contenido y **no reabrir el alcance**. Asignar O1 y O2 a HU-10/HU-11 y a una revisión
de cierre de HU-12; ejecutar O3 en Jenkins. Con eso, HU-12 puede pasar a *Hecho* sin trabajo
adicional de diseño.

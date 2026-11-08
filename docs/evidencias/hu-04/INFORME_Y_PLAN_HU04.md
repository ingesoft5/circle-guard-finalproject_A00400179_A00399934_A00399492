# HU-04 · Pruebas unitarias y de integración: informe de situación y plan de implementación

Fecha del análisis: 2026-11-06. Rama: `HU04-Pruebas-unitarias-y-integracion`, creada a partir de `dev`
(commit `fe29383`, que ya incluye HU-01, HU-02, HU-03 y HU-09). Entrega de la Parte 1: **domingo 2026-11-08, 23:59**.

**Estado: solo análisis y plan. No se ha modificado ningún archivo del código ni de la infraestructura.** Lo único
que se creó es esta carpeta con la línea base medida ([`00-linea-base-cobertura.txt`](00-linea-base-cobertura.txt)).

Etiquetas usadas en este documento:
- **[MEDIDO]** lo ejecuté y tengo la salida.
- **[LEÍDO]** lo comprobé en el código o la configuración.
- **[ESTIMADO]** cálculo mío, sin medir.
- **[HIPÓTESIS]** explicación probable que hay que confirmar al implementarla.

---

## 1. Veredicto

**¿Se puede realizar la HU-04 completa? Sí, con condiciones.** Es viable técnicamente y no hay ningún bloqueo
imposible, pero es la historia con más trabajo de las vistas hasta ahora y tiene un riesgo real de calendario.

| Pregunta | Respuesta |
|---|---|
| ¿Cumple los 3 criterios de aceptación y las 3 evidencias? | Sí, con el plan de abajo |
| ¿Cuánto trabajo es? | ≈ 180 pruebas unitarias nuevas, 6 de integración, cambios de build, de pipeline y de infraestructura. **≈ 35 h** de trabajo [ESTIMADO] |
| ¿Cabe antes del 8 de nov? | Ajustado: quedan ≈ 2 días. Cabe si se trabaja en paralelo y se decide ya lo bloqueante (sección 11) |
| ¿Qué es lo más arriesgado? | Ejecutar Testcontainers **dentro de Jenkins** en el servidor `ci` de 8 GiB, que hoy no tiene Docker |
| ¿Qué es lo más pesado? | Subir de 25 % a 60 % la cobertura de `promotion` (851 líneas) |

**Lo que descubrí y cambia el planteamiento** (todo verificado):
1. **La cobertura de partida es baja:** 29 %, 10 %, 25 %, 41 % y 81 % en los cinco servicios.
2. **Hay 10 pruebas que ya fallan** y 3 clases con Testcontainers que ni siquiera arrancan.
3. **El pipeline de HU-03 ya existe** (`Jenkinsfile` y `jenkins/vars/`): HU-04 se apoya en él y no lo crea.
4. **Jenkins no tiene Docker**, y Testcontainers lo necesita: es la mayor decisión pendiente.
5. **El Jenkins de AWS se reconstruyó el 2026-11-06** y perdió sus credenciales y su job: hay que recrearlos a mano.

---

## 2. Qué pide la HU-04 y cómo se demuestra

| N.º | Requisito (tal cual la HU) | Tarea que lo cumple | Cómo se demuestra |
|---|---|---|---|
| **A1** | Cobertura de líneas **≥ 60 %** con JaCoCo en **auth, identity, promotion, form y gateway** | Fases 0 y 1 | Informe JaCoCo por servicio; el build **falla** por debajo del 60 % |
| **A2** | **≥ 3 pruebas de integración con Testcontainers** | Fase 2 | Informe JUnit de la etapa de integración, con ≥ 3 pruebas que arrancan contenedores reales |
| **A2b** | «una de ellas **form → Kafka → promotion**» | Fase 2 (IT-1) | La prueba envía una encuesta a `form`, el evento viaja por Kafka y `promotion` cambia el estado del usuario |
| **A3** | **Informes publicados por el pipeline** | Fase 3 | En Jenkins: resultados de pruebas, cobertura y artefactos HTML/XML por *build* |
| **E1** | Evidencia: **informe JaCoCo** | Fase 4 | `docs/evidencias/hu-04/01-informe-jacoco/` |
| **E2** | Evidencia: **informe de pruebas de integración** | Fase 4 | `docs/evidencias/hu-04/02-informe-integracion/` |
| **E3** | Evidencia: **captura del pipeline** | Fase 4 | `docs/evidencias/hu-04/capturas/` con el *build* real en Jenkins |

Relación con el enunciado (E1.6 y rúbrica P1.6, 3.5 %): E1.6 incluye además **pruebas E2E con Playwright** (3 flujos). **No
forman parte de esta HU-04**, que se limita a unitarias e integración. Pero la rúbrica P1.6 las exige juntas
(«todo ejecutado y reportado por el pipeline»): si nadie más las hace, P1.6 no llegará a «Excelente».

---

## 3. Estado actual verificado

### 3.1 Repositorio y build
- Spring Boot 3.2.4, Gradle 8.14, JDK 21 (toolchain), 8 servicios en `settings.gradle.kts` [LEÍDO].
- El `build.gradle.kts` raíz **ya aplica JaCoCo** a todos los servicios, con informes XML y HTML, y define:
  - `test`, que excluye las clases `*IntegrationTest` y termina con `jacocoTestReport`;
  - `integrationTest`, que ejecuta solo `*IntegrationTest` [LEÍDO].
- **No existe**: `jacocoTestCoverageVerification` (el umbral del 60 %), exclusiones de Lombok, ni ningún módulo de pruebas de integración [LEÍDO].
- Solo `promotion` tiene dependencias de Testcontainers (`junit-jupiter`, `postgresql`, `neo4j`, versión 1.19.3). `form`, `auth`, `identity` y `gateway` no tienen ninguna [LEÍDO].

### 3.2 Pipeline (HU-03, ya fusionado)
- `Jenkinsfile` multibranch con etapas: Checkout, Build, **Unit tests and coverage**, SonarQube quality gate, **Integration tests**, Package y Publish [LEÍDO].
- Detecta los servicios modificados (`cgDetectChanges`); con `SERVICES_MODE=all` procesa los 8 [LEÍDO].
- `cgUnitTests` ejecuta `test` y `jacocoTestReport`, publica los XML de JUnit y **archiva** los XML y HTML de JaCoCo [LEÍDO].
- `cgIntegrationTests` ejecuta `integrationTest` y publica los XML de JUnit [LEÍDO].

### 3.3 Pruebas existentes en los servicios núcleo
| Servicio | Archivos de prueba | Líneas de prueba / de código | Observación |
|---|---|---|---|
| auth | 1 | 67 / 591 | Solo `LoginControllerTest` |
| identity | 3 | 180 / 381 | Pruebas del controlador rotas |
| promotion | 8 | 849 / 2446 | 3 clases con Testcontainers que no arrancan |
| form | 4 | 197 / 527 | 1 prueba rota; el servicio de encuestas no tiene pruebas |
| gateway | 2 | 107 / 80 | Ya cumple |

### 3.4 Línea base de cobertura [MEDIDO]
Sobre una copia temporal del commit `fe29383`, con el JaCoCo que ya trae el build
([salida completa](00-linea-base-cobertura.txt)):

| Servicio | Líneas cubiertas / totales | **Cobertura** | Falta para el 60 % |
|---|---|---|---|
| auth | 53 / 182 | **29.1 %** | +57 líneas |
| identity | 14 / 135 | **10.4 %** | +67 líneas |
| promotion | 212 / 851 | **24.9 %** | +299 líneas |
| form | 58 / 140 | **41.4 %** | +26 líneas |
| gateway | 17 / 21 | **81.0 %** | ya cumple |

Dos matices para interpretar estas cifras:
- Son un **suelo**, no el estado final: parte de lo que falta lo cubrirán las pruebas que hoy están rotas (por ejemplo, las 4 de `identity`, que cubrirían `IdentityVaultController`, 41 líneas).
- No hay `lombok.config` [LEÍDO]: los métodos que genera Lombok cuentan como código sin cubrir y bajan el porcentaje de forma artificial (por ejemplo, `LocalUser` y `Role` en auth). Corregirlo es legítimo y no es «maquillar» el dato.

### 3.5 Las 10 pruebas que ya fallan [MEDIDO] y su causa
| Prueba | Causa | Arreglo |
|---|---|---|
| `IdentityVaultControllerTest` (4) | `WeakKeyException`: la clave JWT del fixture de pruebas tiene 104 bits y se exigen 256 | Fixture con una clave de ≥ 32 caracteres (solo de prueba) |
| `HealthStatusControllerTest` (2) | `403` en peticiones POST | [HIPÓTESIS] falta el token CSRF en `MockMvc`: añadir `.with(csrf())` o ajustar la seguridad de la prueba |
| `AttachmentControllerTest` (1) | Carga el contexto completo y busca Postgres/Kafka (*Connection refused*) | Convertirla en `@WebMvcTest` con dependencias simuladas; hacer configurable la ruta de `StorageService` (hoy fija en `/tmp`) |
| `AdministrativeCorrectionTest`, `HealthStatusReevaluationTest`, `PromotionPerformanceTest` | *initializationError*: Testcontainers 1.19.3 no detecta Docker Engine 29 | Ver 3.6, y arrancar también PostgreSQL |

### 3.6 Testcontainers frente a Docker 29 [MEDIDO]
- Tu Docker Engine es la 29.2 (API 1.53, **mínima 1.44**); los servidores de AWS instalan la 29.9 (comprobado en los de ambiente: 29.9.3), así que el problema también aparecerá en Jenkins. Testcontainers 1.19.3 usa una API más antigua y falla.
- **Comprobado:** con `-Dapi.version=1.44`, Testcontainers detecta Docker y la prueba llega a ejecutarse (antes no pasaba de la inicialización).
- **Qué falló después:** el contexto de Spring también necesita **PostgreSQL**. Estas pruebas arrancan Neo4j y Redis, pero no Postgres, así que Flyway da *Connection refused* en `localhost:5432`. Hay que añadir un contenedor `PostgreSQLContainer` (la dependencia ya está) o usar el perfil `test`, que desactiva Flyway.
- Decisión recomendada: fijar `api.version=1.44` en las tareas `Test` de Gradle y, además, probar a subir Testcontainers a una versión que soporte Docker 29. Se resuelve en la Fase 0.

### 3.7 El flujo form → Kafka → promotion [LEÍDO]
```
POST encuesta ──► form: HealthSurveyService.submitSurvey()
                    guarda en PostgreSQL y publica en el tema «survey.submitted»
                    {anonymousId, hasSymptoms, timestamp}   (JSON)
                          │
                          ▼  Kafka
promotion: SurveyListener.onSurveySubmitted()
           si hasSymptoms ──► HealthStatusService.updateStatus(id, "SUSPECT")  ──► Neo4j (+ Redis, + evento «promotion.status.changed»)

Aprobar certificado ──► form publica «certificate.validated» ──► promotion: SurveyListener.onCertificateValidated() ──► estado «ACTIVE»
```
Otros enlaces entre servicios por Kafka [LEÍDO]: `promotion` publica `promotion.status.changed`, `alert.priority` y `circle.fenced`, que
consume `notification-service`. `auth` llama a `identity` por HTTP (`IdentityClient`, con la URL fija `localhost:8083`).

### 3.8 Jenkins y AWS hoy [LEÍDO / MEDIDO]
- El contenedor de Jenkins **no tiene Docker ni su socket**, por la decisión de seguridad de HU-01. **Testcontainers no puede ejecutarse dentro del pipeline tal como está.**
- Memoria del servidor `ci` (8 GiB), con Jenkins y SonarQube en reposo: **≈ 3.3 GiB en uso** [MEDIDO el 2026-11-06]. Quedan ≈ 4.4 GiB para Gradle y los contenedores de las pruebas.
- Los plugins `coverage` y `htmlpublisher` **no están** en `plugins.txt` [LEÍDO].
- Tras la reconstrucción del 2026-11-06, el Jenkins de AWS está **sin credenciales** (`github-token`, `sonar-token`) y **sin job multibranch**; se crean a mano en la interfaz, según `infra/README.md` [LEÍDO]. Los 5 servidores están apagados.

---

## 4. Brechas frente a la HU

| Criterio | Hoy | Brecha |
|---|---|---|
| ≥ 60 % de cobertura en 5 servicios | 29 / 10 / 25 / 41 / 81 % | Faltan ≈ 450 líneas cubiertas; 10 pruebas rotas; sin umbral que falle el build; Lombok sin tratar |
| ≥ 3 integraciones con Testcontainers | 0 válidas (3 clases rotas y sin Kafka) | Ninguna prueba de integración entre servicios; no hay contenedor de Kafka en ninguna |
| Una de ellas form → Kafka → promotion | No existe | Hay que crearla; `form` ni siquiera tiene Testcontainers |
| Informes publicados por el pipeline | JUnit y JaCoCo archivados (HU-03) | Sin visor de cobertura ni informe HTML; sin umbral; Testcontainers no corre en Jenkins |
| Evidencias (JaCoCo, integración, captura) | Ninguna | Hay que producirlas con un *build* real en Jenkins |

---

## 5. Decisiones de diseño (con recomendación)

### D1. Cómo ejecutar Testcontainers en Jenkins
| Opción | Ventajas | Inconvenientes | Veredicto |
|---|---|---|---|
| **A. Contenedor `docker:dind` junto a Jenkins**, solo en la red interna del *stack* | Jenkins no toca el Docker del servidor; sin puertos publicados; se versiona y se reconstruye con los scripts | Contenedor privilegiado; consume memoria; cambia el Compose de HU-01 | **Recomendada** |
| B. Montar `/var/run/docker.sock` del host | Trivial | Equivale a dar *root* del servidor a Jenkins; contradice la decisión de HU-01 | Descartada |
| C. Agente de *build* en otra instancia EC2 | Aísla la carga | Coste, cuota (límite de 5 vCPU) y trabajo extra | Plan de respaldo |
| D. Ejecutar las integraciones solo en la máquina del equipo | Sin cambios en Jenkins | No cumple «informes publicados por el pipeline» | Descartada |

### D2. Cómo contar la cobertura
**Recomendación:** el **60 % se exige con las pruebas unitarias solas** (tarea `test`), por servicio. Es la lectura más estricta (E1.6 habla de
cobertura de las pruebas unitarias) y no depende de que Docker funcione en Jenkins. Se publica además un informe combinado, unitarias más integración.

### D3. Qué se excluye de la cobertura
Solo lo legítimo y documentado: las clases `*Application` (arranque) y el código que genera Lombok (`lombok.config` con
`lombok.addLombokGeneratedAnnotation = true`). **No** se excluyen paquetes enteros (`model`, `config`, `dto`) para inflar el porcentaje.

### D4. Dónde viven las pruebas cruzadas entre servicios
Un módulo nuevo `tests/integration` que arranca los servicios reales como contenedores (JAR de `bootJar` sobre una imagen JRE) junto con Kafka,
PostgreSQL, Neo4j y Redis, y prueba **solo por HTTP y Kafka**. Es la forma más fiel de «form → Kafka → promotion». Se descartó cargar los dos servicios en una
misma JVM: comparten `application.yml` y las migraciones `V1__...` de Flyway chocarían en el *classpath*.
**Plan B** si la memoria de `ci` no alcanza: dividir cada flujo en una prueba del lado productor (`form`) y otra del consumidor (`promotion`), con un contrato JSON compartido.

### D5. Quién toca qué
HU-04 modifica archivos de otras historias (el `Jenkinsfile` y `jenkins/vars/` son de HU-03; `infra/bootstrap/jenkins/` es de HU-01). Se mantienen los
cambios mínimos, en commits separados y con revisión de quien los creó.

---

## 6. Plan de implementación por fases

### Fase 0 · Base técnica (≈ 3-4 h) · local, sin AWS
| Tarea | Detalle |
|---|---|
| 0.1 | Testcontainers con Docker 29: `systemProperty("api.version", "1.44")` en las tareas `Test`; probar también subir la versión de Testcontainers |
| 0.2 | Arreglar las 4 pruebas de `identity` (clave del fixture) |
| 0.3 | Arreglar las 2 de `HealthStatusControllerTest` |
| 0.4 | `AttachmentControllerTest` a `@WebMvcTest`, y la ruta de `StorageService` configurable |
| 0.5 | Las 3 clases con Testcontainers de `promotion`: añadir PostgreSQL, renombrarlas a `*IntegrationTest` y moverlas a la etapa de integración |
| 0.6 | `lombok.config`; exclusión de `*Application`; `jacocoTestCoverageVerification` con 0.60 de líneas **por servicio**, enlazada a `check`; `gradle.properties` con memoria acotada |
| 0.7 | Tarea Gradle `coverageSummary` que imprime y guarda una tabla de cobertura por servicio |
| **Salida** | `gradle test` en los 5 servicios con **0 fallos** y una cobertura medida (sin el umbral todavía activo) |

### Fase 1 · Pruebas unitarias hasta superar el 60 % (≈ 12-16 h) · local
Objetivo: **≥ 65 %** por servicio, para dejar margen frente al umbral. Los números de pruebas son [ESTIMADO].

| Servicio | Clases con más líneas sin cubrir (medido) | Pruebas nuevas | Total aprox. |
|---|---|---|---|
| **auth** | `CustomUserDetailsService` 20, `JwtTokenService` 16, `JwtAuthenticationFilter` 15, `QrTokenService` 10, `UserController` 8, `LoginController` | `JwtTokenServiceTest`, `QrTokenServiceTest`, `CustomUserDetailsServiceTest`, `JwtAuthenticationFilterTest`, `UserControllerTest`, `QrTokenControllerTest`, `DualChainAuthenticationProviderTest`, ampliar `LoginControllerTest`, `IdentityClientTest` | ≈ 39 |
| **identity** | `IdentityVaultController` 41, `JwtAuthenticationFilter` 22, `IdentityVaultService` 20, `SecurityConfig` 16 | Arreglar las 4 existentes, `IdentityVaultServiceTest`, `JwtAuthenticationFilterTest`, `IdentityAccessEventTest` | ≈ 17 |
| **form** | `HealthSurveyService` 28, `QuestionnaireService` 16, `StorageService` 12 | `HealthSurveyServiceTest` (con y sin síntomas, adjunto pendiente, validación aprobada o rechazada), `QuestionnaireServiceTest`, `StorageServiceTest`, `CertificateValidationControllerTest` | ≈ 21 |
| **promotion** | `SpatialService` 56, `BuildingController` 48, `CircleService` 45, `HealthStatusService` 43, `FloorController` 32, `AdminController` 30, `HealthStatsController` 30, `LocationResolutionService` 29 | ≈ 18 clases de prueba: servicios (`Spatial`, `Circle`, `LocationResolution`, `AutoCircle`, `AccessPoint`, `Graph`, `StatusLifecycle`), controladores (`Building`, `Floor`, `Admin`, `HealthStats`, `Encounter`, `Circle`, `AccessPoint`, `Mesh`), filtro JWT y tarea de limpieza | ≈ 100 |
| **gateway** | `QrValidationService` 2 | 3 pruebas de casos límite (token caducado, firma inválida, QR vacío) | ≈ 3 |
| **Total** | | | **≈ 180** |

Reglas: un `@WebMvcTest` por controlador y Mockito para los servicios; **sin Docker** en estas pruebas, para que corran en cualquier parte; valores aleatorios o
ficticios, nunca credenciales reales (Gitleaks sigue pasando).
**Salida:** `gradle check` en verde, con el umbral del 60 % activo y cumplido en los 5 servicios.

### Fase 2 · Pruebas de integración con Testcontainers (≈ 8-10 h) · local
| ID | Prueba (`*IntegrationTest`) | Qué recorre | Contenedores |
|---|---|---|---|
| **IT-1** | `FormToPromotionSurveyIntegrationTest` **(la obligatoria)** | `POST` de una encuesta con síntomas a **form** → tema `survey.submitted` en Kafka → **promotion** deja al usuario en `SUSPECT` en Neo4j | Kafka, PostgreSQL, Neo4j, Redis + `form` y `promotion` |
| **IT-2** | `FormCertificateToPromotionIntegrationTest` | Aprobar un certificado en **form** → `certificate.validated` → **promotion** devuelve al usuario a `ACTIVE` | Los mismos |
| **IT-3** | `PromotionToNotificationIntegrationTest` | Un cambio de estado en **promotion** publica `promotion.status.changed` → **notification** lo consume y despacha el aviso (con el canal externo simulado) | Kafka + los servicios implicados |
| IT-4 a IT-6 | Las 3 clases con Testcontainers que ya existen en `promotion`, arregladas y renombradas | Neo4j y Redis de verdad: corrección administrativa, reevaluación de estado y rendimiento | Neo4j, Redis, PostgreSQL |

- **Cumplen el criterio:** IT-1, IT-2 e IT-3 son pruebas **entre servicios relacionados**, con Testcontainers y una de ellas form → Kafka → promotion. IT-4 a IT-6 son un extra.
- **Estructura:** el módulo `tests/integration` (nuevo `include("tests:integration")`) para IT-1 a IT-3, y `src/test` de `promotion` para IT-4 a IT-6.
- **Eficiencia:** los contenedores se arrancan **una vez** y se reutilizan entre pruebas; esperas con Awaitility, no con `sleep`.
- **Contrato:** los eventos JSON (`survey.submitted` y los demás) se documentan y se prueban con el mismo ejemplo en el lado productor y el consumidor, para detectar roturas de formato.
- **Qué falta confirmar al implementarlo** [HIPÓTESIS]: nombres exactos de las variables de entorno de cada servicio; imagen de Kafka compatible con Testcontainers 1.19; consumo de memoria real con dos JVM más Kafka y Neo4j.

**Salida:** `gradle integrationTest` con IT-1 a IT-6 en verde, en tu máquina (Docker 29).

### Fase 3 · Pipeline e infraestructura (≈ 6-8 h) · necesita AWS
| Tarea | Archivos | Detalle |
|---|---|---|
| 3.1 | `infra/bootstrap/jenkins/docker-compose.yml` | Contenedor `docker:dind` en la red interna, con límite de memoria; `DOCKER_HOST` y variables de Testcontainers para Jenkins; nuevo *tag* de imagen (`-ci2`) |
| 3.2 | `infra/bootstrap/jenkins/plugins.txt` | Añadir `coverage` y `htmlpublisher` |
| 3.3 | `jenkins/vars/cgUnitTests.groovy` | `recordCoverage` (JaCoCo, umbral 60 % que falla el build) y `publishHTML` del informe |
| 3.4 | `jenkins/vars/cgIntegrationTests.groovy` | Incluir `:tests:integration:integrationTest`; publicar JUnit y los informes HTML |
| 3.5 | `Jenkinsfile` | Ajustes mínimos de orden y parámetros |
| 3.6 | Jenkins (a mano, documentado) | Crear `github-token` y `sonar-token`, y el job multibranch |
| 3.7 | SonarQube | (Opcional) definir un *quality gate* con «cobertura ≥ 60 %» mediante script idempotente |
| **Salida** | | Un *build* real en Jenkins con `SERVICES_MODE=all`, con ambas etapas en verde y los informes visibles |

### Fase 4 · Evidencias, documentación y PR (≈ 3-4 h)
Ver la sección 8. Termina con el PR de la rama HU04 a `dev`, revisado por otra persona.

---

## 7. Archivos que se van a crear o modificar

### Crear
| Archivo | Para qué |
|---|---|
| `lombok.config` | Excluir de la cobertura el código que genera Lombok |
| `tests/integration/build.gradle.kts` | Módulo de las pruebas cruzadas (dependencias de Testcontainers, Awaitility, `bootJar` de los servicios) |
| `tests/integration/src/test/java/.../` | `FormToPromotionSurveyIntegrationTest`, `FormCertificateToPromotionIntegrationTest`, `PromotionToNotificationIntegrationTest`, clases base y utilidades de contenedores |
| `tests/integration/src/test/resources/contracts/*.json` | Ejemplos de los eventos de Kafka (contrato) |
| `services/*/src/test/java/**` | ≈ 35 clases de prueba unitaria nuevas (sección 6, fase 1) |
| `services/circleguard-form-service/src/test/resources/` y `identity` | Perfiles de prueba y fixtures con claves de prueba válidas |
| `gradle.properties` | Memoria acotada y sin paralelismo agresivo para el servidor `ci` |
| `jenkins/vars/cgCoverage.groovy` | (Si conviene separarlo) publicación de cobertura |
| `docs/arquitectura/estrategia-pruebas.md` | Pirámide de pruebas, qué cubre cada nivel, cómo ejecutarlas |
| `docs/evidencias/hu-04/README.md` | Matriz de criterios y de evidencias |
| `docs/evidencias/hu-04/01-informe-jacoco/` | Resumen por servicio y XML de JaCoCo |
| `docs/evidencias/hu-04/02-informe-integracion/` | Informe JUnit y HTML de las pruebas de integración |
| `docs/evidencias/hu-04/capturas/` | Capturas del pipeline |
| `docs/iag/sesiones/2026-11-0X-hu-04.md` | Registro de uso de IA, como en HU-02 |

### Modificar
| Archivo | Cambio |
|---|---|
| `build.gradle.kts` | Umbral de JaCoCo, exclusiones, `systemProperty("api.version")`, `integrationTest`, `coverageSummary` |
| `settings.gradle.kts` | `include("tests:integration")` |
| `services/circleguard-*/build.gradle.kts` | Dependencias de Testcontainers (Kafka, PostgreSQL) y `awaitility` donde falten |
| `services/circleguard-form-service/.../StorageService.java` | Ruta configurable (necesaria para probarlo) |
| `services/circleguard-auth-service/.../IdentityClient.java` | URL configurable (opcional; solo si se prueba la integración auth→identity) |
| Pruebas existentes (identity, promotion, form) | Las correcciones de la sección 3.5 |
| `jenkins/vars/cgUnitTests.groovy`, `cgIntegrationTests.groovy` y `Jenkinsfile` | Sección 6, fase 3 |
| `infra/bootstrap/jenkins/docker-compose.yml` y `plugins.txt` | `dind` y plugins |
| `infra/README.md` y `README.md` | Documentar la etapa de pruebas y cómo ejecutarlas |

---

## 8. Evidencias y cómo se producen

| Evidencia | Contenido | Cómo se genera |
|---|---|---|
| **Informe JaCoCo** | Tabla de cobertura de líneas por servicio (≥ 60 %), XML y HTML de cada uno | `gradle test jacocoTestReport coverageSummary` y los artefactos del *build* de Jenkins |
| **Informe de integración** | IT-1 a IT-6 en verde, con tiempos y los contenedores usados | `gradle integrationTest` y los XML/HTML de JUnit del *build* |
| **Captura del pipeline** | Vista de etapas con Unit tests e Integration tests en verde; pestaña de resultados de pruebas; informe de cobertura; artefactos | Capturas del *build* real en Jenkins (por túnel SSH) |
| Extra | Cobertura vista en SonarQube | Captura del proyecto en SonarQube |

Todas las capturas sin contraseñas ni IP públicas, igual que en HU-01.

---

## 9. Qué falta para poder empezar y completarla

### Ya está listo (verificado)
- La rama `HU04-Pruebas-unitarias-y-integracion` sobre `dev`, con el pipeline de HU-03.
- JDK 21, Gradle 8.14 y Docker 29 en tu máquina; JaCoCo ya aplicado; la línea base medida.
- La causa de las 10 pruebas rotas y una solución comprobada para Testcontainers con Docker 29.

### Decisiones que necesito del equipo
| N.º | Decisión | Mi recomendación |
|---|---|---|
| 1 | Docker en Jenkins | **dind** (D1-A). Cambia el Compose de HU-01 |
| 2 | Cómo se cuenta el 60 % | Con las unitarias solas (D2) |
| 3 | Estructura de las pruebas cruzadas | Módulo `tests/integration` (D4) |
| 4 | Quién crea las credenciales y el job de Jenkins | Una persona del equipo, con el token de GitHub |
| 5 | ¿Quién hace Playwright (E2E) del mismo criterio P1.6? | Otra HU; confirmarlo ya |

### Acciones humanas necesarias
| Acción | Quién | Cuándo |
|---|---|---|
| Un *token* de GitHub con permiso de lectura del repositorio (`github-token`) | Un integrante con acceso | Fase 3 |
| Iniciar sesión como operador (MFA) para encender `ci` y reconstruir la imagen de Jenkins | El responsable de AWS | Fase 3 |
| Generar el *token* de SonarQube (`sonar-token`) tras encender Jenkins | El responsable | Fase 3 |
| Crear el job multibranch en la interfaz de Jenkins | El responsable, por túnel SSH | Fase 3 |
| Revisión del PR por una persona distinta del autor | Un compañero | Fase 4 |

### Qué se puede hacer **desde ahora**, sin esperar a nadie ni usar AWS
Las fases 0, 1 y 2 completas, y la mitad de la 4 (documentación y evidencias locales). Eso es ≈ 70 % del trabajo.

### Qué queda bloqueado hasta resolver lo anterior
La fase 3: el *build* real en Jenkins, la captura del pipeline y la publicación de informes dentro del pipeline.

---

## 10. Riesgos

| Riesgo | Prob. | Efecto | Mitigación |
|---|---|---|---|
| **Memoria del servidor `ci`** insuficiente con Kafka, Neo4j, Postgres, Redis y dos JVM dentro de dind | Media | Las integraciones fallan en Jenkins | Reutilizar contenedores, heaps pequeños, ejecución en serie, límite de `dind`; plan B (D4): dividir cada flujo en productor y consumidor |
| **Plazo:** ≈ 35 h de trabajo para ≈ 2 días | Alta | Quedar por debajo del 60 % en algún servicio | Empezar por `promotion` (lo más grande); priorizar por líneas sin cubrir; medir al final de cada servicio |
| `promotion` no llega al 60 % con pruebas unitarias | Media | Incumple A1 | Mockito sobre repositorios y `Neo4jClient`; las pruebas de integración como último recurso |
| Testcontainers + Kafka inestable | Media | Pruebas intermitentes | Awaitility con tiempo máximo, imágenes fijadas, contenedores reutilizados |
| Cambios en HU-01 (Compose) rompen la plataforma | Baja | Jenkins no arranca | Cambio mínimo y reversible; `verify-infra` tras la reconstrucción |
| Conflictos con HU-03 y HU-06 en `Jenkinsfile` | Media | Rehacer cambios | Rama desde `dev` al día; commits pequeños; avisar a sus autores |
| El Jenkins reconstruido no tiene job ni credenciales | **Cierta** | Sin captura del pipeline | Fase 3.6, a mano y documentada |

**Coste en AWS** [ESTIMADO]: solo `ci` encendido unas 5-6 h para montar y ejecutar → **≈ 0.5-0.6 USD** (≈ 0.10 USD/hora); no hace falta `nexus` ni los ambientes. El presupuesto
sigue lejos de los 15 USD (hoy ≈ 1.1 USD).

---

## 11. Cronograma sugerido hasta el 8 de noviembre

| Día | Trabajo |
|---|---|
| **Vie 6** | Fase 0 completa y Fase 1 de `form`, `identity` y `auth`. Decisiones D1-D5 con el equipo |
| **Sáb 7** | Fase 1 de `promotion` y `gateway`; Fase 2 (IT-1 a IT-6); empezar la Fase 3 en AWS |
| **Dom 8** | Fase 3 (Jenkins y *build* real), Fase 4 (evidencias, capturas, documentación) y PR. Dejar horas de margen antes de las 23:59 |

---

## 12. Definición de «hecho» (lista de verificación)

- [ ] `gradle test` verde en los 5 servicios, **0 fallos**
- [ ] Cobertura de líneas **≥ 60 %** en auth, identity, promotion, form y gateway, **exigida por el build** (`jacocoTestCoverageVerification`)
- [ ] ≥ 3 pruebas de integración con Testcontainers en verde (IT-1 a IT-3)
- [ ] IT-1 recorre **form → Kafka → promotion**
- [ ] El pipeline de Jenkins ejecuta las pruebas unitarias y las de integración y las **publica** (resultados, cobertura, HTML)
- [ ] `docs/evidencias/hu-04/` con el informe JaCoCo, el informe de integración y la captura del pipeline
- [ ] Gitleaks sin secretos activos; ShellCheck sin hallazgos (si se tocan scripts)
- [ ] Documentación y registro de IA actualizados
- [ ] PR a `dev` revisado por otra persona

## 13. Qué NO cubre esta HU (para no prometerlo)
- Pruebas **E2E con Playwright** (E1.6, otra HU).
- La **entrega continua** y la promoción entre ambientes (E1.5, HU-06).
- El despliegue de los servicios en los ambientes.
- Pruebas de rendimiento y de seguridad (Parte 2).

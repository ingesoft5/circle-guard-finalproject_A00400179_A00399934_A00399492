# Diagramas de arquitectura y del pipeline (HU-08)

Los diagramas están escritos en [Mermaid](https://mermaid.js.org/): GitHub y VS Code (con la
extensión «Markdown Preview Mermaid Support») los dibujan directamente. Cada diagrama indica de
dónde salen sus datos, para poder verificarlos contra el código.

| # | Diagrama | Responde a |
|---|---|---|
| 1 | [Arquitectura lógica de la aplicación](#1-arquitectura-lógica-de-la-aplicación) | ¿Qué servicios hay y cómo se comunican? |
| 2 | [Flujo de eventos de una encuesta de salud](#2-flujo-de-eventos-de-una-encuesta-de-salud) | ¿Qué ocurre cuando alguien reporta síntomas? |
| 3 | [Pipeline de integración continua (CI)](#3-pipeline-de-integración-continua-ci) | ¿Qué valida cada cambio antes de integrarse? |
| 4 | [Pipeline de entrega continua (CD)](#4-pipeline-de-entrega-continua-cd) | ¿Cómo llega una versión a dev, stage y prod? |
| 5 | [Infraestructura en AWS](#5-infraestructura-en-aws) | ¿Dónde corre todo y cómo se aíslan los ambientes? |

---

## 1. Arquitectura lógica de la aplicación

Ocho microservicios Spring Boot (Java 21), un cliente Expo (web/móvil) y cuatro almacenes de datos.
El cliente llama directamente a cada servicio (ver `mobile/constants/Config.ts`); los servicios se
desacoplan entre sí con **Kafka** y con dos llamadas REST (`auth → identity`, `dashboard → promotion`).

```mermaid
flowchart LR
    client["Cliente Expo<br/>web / iOS / Android"]

    subgraph svc["Microservicios (Spring Boot 3.2.4 · Java 21)"]
        auth["auth :8180<br/>login LDAP / local + JWT"]
        identity["identity :8083<br/>bóveda de identidades"]
        form["form :8086<br/>encuestas y certificados"]
        promotion["promotion :8088<br/>motor de estados"]
        notification["notification :8082<br/>Push · Email · SMS · LMS"]
        gateway["gateway :8087<br/>validación de QR de acceso"]
        dashboard["dashboard :8084<br/>analítica agregada"]
        file["file :8085<br/>certificados y documentos"]
    end

    kafka{{"Apache Kafka"}}
    pg[("PostgreSQL 16<br/>bóveda y formularios")]
    neo[("Neo4j 5.26<br/>grafo de contactos")]
    redis[("Redis 7.2<br/>estado para el acceso")]
    ldap[("OpenLDAP<br/>usuarios universitarios")]

    client --> auth & form & gateway & dashboard & file
    auth -- "REST" --> identity
    auth --> ldap
    identity --> pg
    form --> pg
    form -- "survey.submitted<br/>certificate.validated" --> kafka
    kafka --> promotion
    promotion --> neo
    promotion --> redis
    promotion -- "promotion.status.changed<br/>circle.fenced · alert.priority" --> kafka
    kafka --> notification
    notification -- "notification.audit" --> kafka
    identity -- "audit.identity.accessed" --> kafka
    gateway --> redis
    dashboard -- "REST" --> promotion
    file --> store[("Almacenamiento<br/>compatible con S3")]
```

**Fuentes:** puertos en `services/*/src/main/resources/application.yml`; tópicos en
`HealthSurveyService`, `HealthStatusService`, `AuditLogService` y los `@KafkaListener` de promotion y
notification; clientes REST en `IdentityClient` y `PromotionClient`; Redis en `QrValidationService`.

**Decisión de diseño.** El grafo (Neo4j) guarda solo identificadores anónimos; los nombres reales
viven únicamente en la bóveda de `identity` (PostgreSQL). Un fallo de `notification` no detiene
a `promotion`, porque se comunican por eventos.

---

## 2. Flujo de eventos de una encuesta de salud

Es el recorrido que ejercitan las pruebas de integración de HU-04
(`tests/integration`, clases `FormToPromotionIntegrationTest` y
`PromotionToNotificationIntegrationTest`).

```mermaid
sequenceDiagram
    autonumber
    actor U as Estudiante
    participant F as form
    participant K as Kafka
    participant P as promotion
    participant N as Neo4j
    participant R as Redis
    participant NT as notification

    U->>F: envía la encuesta (con síntomas)
    F->>F: calcula la lista de síntomas y guarda la encuesta
    F->>K: survey.submitted
    K->>P: entrega el evento (promotion-service-group)
    P->>N: marca al usuario como SUSPECT<br/>y recorre sus contactos de 14 días
    P->>R: actualiza el estado para el control de acceso
    P->>K: promotion.status.changed
    K->>NT: entrega el evento (notification-group)
    NT->>U: Push / SMS (según canales)
    NT->>K: notification.audit
```

> Defecto conocido (no corregido): en `HealthStatusService.updateStatus` la consulta Cypher no devuelve
> filas si el usuario no tiene contactos recientes o si el nuevo estado es `ACTIVE`; en esos casos
> los pasos 6 y 7 no ocurren. Está documentado en `docs/evidencias/hu-04/README.md`.

---

## 3. Pipeline de integración continua (CI)

Lo ejecuta el `Jenkinsfile` con la Shared Library de `jenkins/vars/`. Se dispara con `githubPush()` o,
si Jenkins no es alcanzable desde Internet, con `pollSCM` cada 5 minutos.

```mermaid
flowchart LR
    push["Push / PR"] --> co["Checkout<br/>cgDetectChanges"]
    co --> prep["Prepare<br/>versión semver"]
    prep --> build["Build<br/>cgGradle"]
    build --> unit["Unit tests + cobertura<br/>cgUnitTests · JaCoCo ≥ 60 %"]
    unit --> sonar{"RUN_SONAR"}
    sonar -- "sí" --> qg["SonarQube<br/>quality gate"]
    sonar -- "no" --> integ
    qg --> integ{"RUN_INTEGRATION"}
    integ -- "sí" --> it["Integration tests<br/>cgIntegrationTests<br/>Testcontainers en dind"]
    integ -- "no" --> pack
    it --> pack["Package<br/>cgPackage · bootJar"]
    pack --> pub["Publish artifacts<br/>cgPublish (solo dev/main)"]

    unit -. "JUnit · Coverage · HTML JaCoCo" .-> rep[("Reportes en Jenkins")]
    it -. "JUnit · HTML" .-> rep
```

| Etapa | Qué verifica | Falla el build si… |
|---|---|---|
| Unit tests + cobertura | `test` de cada servicio y JaCoCo | La cobertura de líneas de auth, identity, promotion, form o gateway baja de 60 % |
| SonarQube (opcional) | Calidad y vulnerabilidades | El quality gate no es `OK` |
| Integration tests (opcional) | 5 pruebas con Kafka, PostgreSQL, Neo4j y Redis reales | Cualquier prueba falla |

**Docker en Jenkins.** Testcontainers necesita un daemon de Docker. Se usa un contenedor
Docker-in-Docker (`dind`) en la red interna de Compose, sin puerto publicado, en lugar de montar el
socket del host (`infra/bootstrap/jenkins/docker-compose.yml`).

---

## 4. Pipeline de entrega continua (CD)

Detalle de etapas y ramas en [`pipeline-cd.md`](pipeline-cd.md). Vista de conjunto:

```mermaid
flowchart LR
    ci["CI superado"] --> img["Package images<br/>9 imágenes"]
    img --> reg[("Registro OCI<br/>CNCF Distribution")]
    reg --> dev["Deploy dev"]
    dev --> e2e1["E2E dev<br/>Playwright"]
    e2e1 --> stage["Deploy stage"]
    stage --> e2e2["E2E stage"]
    e2e2 --> approve{"Aprobación manual<br/>submitter: admin · 24 h"}
    approve -- "rama main" --> prod["Deploy prod"]
    approve -. "rama dev: se detiene antes" .-> stop(["Fin"])
    prod --> tag["Tag vX.Y.Z"]
    tag --> notes["Release notes<br/>CHANGELOG.md"]
    notes --> gh["GitHub Release"]
    prod -. "falla" .-> rb["rollback.sh<br/>versión anterior"]
    prod -.-> trace[("deploy/releases/&lt;env&gt;.json")]
```

| Rama | Despliega | Producción |
|---|---|---|
| `dev` | dev y stage | No |
| `main` | dev, stage y prod | Con aprobación manual; crea tag y notas |

---

## 5. Infraestructura en AWS

El diagrama completo, con todas las reglas de red, está en [`infra-ambientes.md`](infra-ambientes.md).
Resumen:

```mermaid
flowchart TB
    op["Operador<br/>SSH 22 desde una IP /32"]
    ssm[("SSM Parameter Store<br/>SecureString · secretos")]

    subgraph vpc["VPC 10.20.0.0/16 · us-east-2"]
        subgraph tools["subred tools"]
            ci["ci · Jenkins + SonarQube + dind"]
            nx["nexus · registro CNCF Distribution :8082"]
        end
        dev["env-dev"]
        stage["env-stage"]
        prod["env-prod"]
    end

    op -- "túnel SSH" --> ci
    op -.-> ssm
    ci -- "push / pull" --> nx
    ci -- "deploy (22)" --> dev & stage & prod
    dev & stage & prod -- "pull (8082)" --> nx
    dev x--x stage
    stage x--x prod
    dev x--x prod
```

Reglas clave: las interfaces de Jenkins, SonarQube y Nexus **no** se exponen a Internet (solo SSH,
desde una IP); los tres ambientes no pueden hablarse entre sí; los secretos no están en el
repositorio (SSM + `.env` con permisos 0600 en cada host).

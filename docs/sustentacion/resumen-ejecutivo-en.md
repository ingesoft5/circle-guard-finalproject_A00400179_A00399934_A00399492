# CircleGuard — Executive Summary

**One-page summary · Sprint 2 deliverable · November 2026**
**Team:** Sebastian Cosme, Matt Lane, Juan Esteban Sotelo · Universidad Icesi

## Purpose

CircleGuard is a privacy-first contact-tracing platform for university campuses. It identifies
interconnected contact groups (“circles”) and applies rapid containment measures without exposing
real identities. The system is designed for the time window between symptom reporting and
laboratory confirmation, when fast action matters most.

The product goal is a containment time under 60 seconds, 100 % anonymisation of student identities,
over 70 % check-in adoption, fewer than 15 % false positives, and 99.5 % availability during peak
academic hours.

## Architecture

CircleGuard is a monorepo with **eight Spring Boot 3.2.4 microservices on Java 21**, an Expo
web/mobile client, and a middleware layer:

- **PostgreSQL 16** — identity vault, forms, configuration and audit data (one logical database per
  service).
- **Neo4j 5.26** — anonymous contact graph with a 14-day edge lifetime.
- **Redis 7.2** — precomputed health status used by the access-control gateway.
- **Apache Kafka** — event backbone for survey, promotion, notification and audit events.

The key design rule is the separation between the **identity vault** (`identity` service, the only
place where real names exist) and the **anonymous graph** (everything else works with
`anonymousId`). Services communicate asynchronously through Kafka, except for two synchronous calls:
`auth → identity` and `dashboard → promotion`. A failure in `notification` does not stop
`promotion`.

## Delivery and operations

The project uses GitHub Flow with a `dev` integration branch and `main` as production. Jenkins
multibranch runs a shared-library pipeline: change detection, build, unit tests with a **60 % JaCoCo
gate**, optional SonarQube, Testcontainers integration tests, immutable Docker images, and promotion
from dev to stage to production with **manual approval**. Nine versioned images are published to a
CNCF Distribution registry; `latest` is never used.

Infrastructure is provisioned on AWS (`us-east-2`) with **Terraform** modules for network, k3s
compute, ECR, S3, CloudWatch and Jenkins. The state lives in S3 with DynamoDB locking, and
`dev`, `stage`, `prod` and `tools` are parameterised environments. Each application environment
runs a single-node k3s cluster; the eight services, the web client and the middleware are deployed
with Kustomize overlays, Ingress and HPA. Jenkins uses Docker-in-Docker, SonarQube, the registry,
IAM roles with MFA and secrets in SSM Parameter Store. Environments auto-stop after four hours to
control cost.

## Current results

| Indicator | Result |
|---|---|
| Unit tests | 269 tests, 0 failures |
| Line coverage (five gated services) | 90.9 %–100 % (gate: 60 %) |
| Integration tests | 5 cross-service + 6 promotion, real Kafka/PostgreSQL/Neo4j/Redis |
| E2E | Playwright flows for login, survey and access validation |
| Terraform | 6 modules, 4 parameterised environments, S3 + DynamoDB remote state |
| Kubernetes | 8 services + web + 6 middleware, pods `1/1 Running`, 9 HPA, Ingress in dev/stage/prod |
| Observability | Prometheus, Grafana, Alertmanager, Jaeger and Loki implemented; visual evidence pending |
| Security | Trivy, dependency and secret scans, RBAC and TLS tested locally; Jenkins integration pending |
| Performance (Locust) | Access p95 200/400/460 ms at 10/50/100 users; survey p95 620/1 100/2 700 ms |
| OWASP ZAP | 0 High findings; the gate passes at High and would block at Medium |
| Releases | `v0.1.0`, `v0.2.0`; `v0.3.0` notes prepared |
| Rollback | Executed in Compose (`0.2.0 → 0.1.0`); Kubernetes procedure implemented, execution pending |
| Secret scanning | 0 active secrets in the working tree |
| Estimated spend | ≈ 3 USD of a 15 USD budget before the Sprint 2 apply |

## Sprint 2 delivered

Sprint 2 moved the platform from Docker Compose to a declarative, orchestrated and observable
platform:

1. **Terraform (done).** Modules for network, k3s compute, registry, storage, observability and
   Jenkins, with three application environments plus `tools` and remote state with locking.
2. **Kubernetes (done).** Eight services, the web client and middleware with ConfigMaps, Secrets,
   Ingress, HPA and Actuator-backed liveness/readiness probes. Deployment from Jenkins is still
   pending (HU-11).
3. **Advanced CI/CD (partial).** The pipeline builds, tests, packages and promotes with approval;
   the Kubernetes and Trivy stages are prepared but not applied.
4. **Design patterns (done).** Circuit Breaker, External Configuration and Dead Letter Topic with
   injected-fault tests and documented trade-offs.
5. **Observability (implemented).** Micrometer/Prometheus metrics, Grafana technical and business
   dashboards, five alert rules, OpenTelemetry/Jaeger traces across `form → Kafka → promotion →
   notification`, and Loki logs. Dashboard and incident screenshots are pending.
6. **Security (implemented).** Trivy image and dependency scanning, secrets outside the repository,
   Kubernetes RBAC, verifiable TLS and exceptions with expiry. Three CRITICAL and 22 HIGH findings
   remain documented; Jenkins and cluster deployment are pending.
7. **Performance and security testing (executed locally).** Locust scenarios with pre-declared
   objectives and OWASP ZAP baseline. The access and survey targets are met at 10 users but not at
   50 or 100; this is reported as a result, not hidden.
8. **Change management (partial).** Per-version release notes, semantic tags, per-environment
   records with approval and result (D-30), and a Kubernetes rollback command. The real Kubernetes
   rollback still needs to be executed and attached as evidence.
9. **Documentation (in progress).** Architecture, operations manual, infrastructure as code, cost
   analysis and this English summary. Jira closing data and the real AWS bill are pending.

## Performance results

Declared objectives: access `p95 ≤ 300 ms`, `≥ 200 req/s`, errors `< 1 %`; survey
`p95 ≤ 800 ms`, `≥ 50 req/s`, errors `< 2 %`.

| Flow | Users | p95 | Throughput | Errors | Meets target |
|---|---:|---:|---:|---:|---|
| Access validation | 10 | 200 ms | 18.2 req/s | 0 % | p95 yes; throughput n/a |
| Access validation | 50 | 400 ms | 65.9 req/s | 0 % | No (p95) |
| Access validation | 100 | 460 ms | 86.8 req/s | 0 % | No (p95 and throughput) |
| Survey submission | 10 | 620 ms | 5.0 req/s | 0 % | Yes |
| Survey submission | 50 | 1 100 ms | 24.6 req/s | 0 % | No (p95) |
| Survey submission | 100 | 2 700 ms | 40.6 req/s | 0 % | No (p95 and throughput) |

The bottleneck is the local, resource-constrained environment (0.5–1 CPU per container), not the
functional correctness. The team reports the gap and the corrections applied after measuring
(QR expiration, security headers and additional tests).

## Key decisions

The team documents every architectural decision with its context, alternatives and consequences in
`docs/iag/decisiones.md`. Highlights: CNCF Distribution instead of Nexus (avoiding the Sonatype
EULA), Kafka for decoupling, Circuit Breaker without a degraded fallback (inventing an
`anonymousId` would break anonymisation), Dead Letter Topics to stop losing events, Loki instead of
ELK for a small cluster, and Blue-Green instead of canary for a three-person team.

## Lessons learned

The hardest problems were not code: they were environment capacity, cost control and keeping
documentation honest. The team learned to declare limitations (single PostgreSQL instance, 2 vCPU
hosts, self-signed registry certificate) and to convert them into decisions instead of hiding them.
The next improvement is to measure before optimising: observability and Locust objectives now
precede performance claims.

## Repository

<https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492>

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

Infrastructure is provisioned on AWS (`us-east-2`) with idempotent Bash scripts: a VPC, isolated
dev/stage/prod hosts, Jenkins with Docker-in-Docker, SonarQube, the registry, IAM roles with MFA,
and secrets in SSM Parameter Store. Environments auto-stop after four hours to control cost.

## Current results

| Indicator | Result |
|---|---|
| Unit tests | 269 tests, 0 failures |
| Line coverage (five gated services) | 90.9 %–100 % (gate: 60 %) |
| Integration tests | 5 cross-service + 6 promotion, real Kafka/PostgreSQL/Neo4j/Redis |
| E2E | Playwright flows for login, survey and access validation |
| Releases | `v0.1.0`, `v0.2.0` with generated notes and GitHub Releases |
| Rollback | Executed in dev and prod (`0.2.0 → 0.1.0`), 15 containers healthy |
| Secret scanning | 0 active secrets in the working tree |
| Estimated spend | ≈ 3 USD of a 15 USD budget |

## Sprint 2 scope (in progress)

Sprint 2 moves the platform from Docker Compose to a declarative, orchestrated and observable
platform:

1. **Terraform** modules for network, compute, registry, storage and observability, with three
   parameterised environments and remote state with locking.
2. **Kubernetes** deployment of the eight services and middleware, with ConfigMaps, Secrets,
   Ingress, HPA and Actuator-backed liveness/readiness probes.
3. **Advanced CI/CD** that governs Kubernetes deployments, blocks on Trivy findings and requires
   approval before production.
4. **Design patterns**: an inventory of existing patterns plus Circuit Breaker, External
   Configuration and Dead Letter Topic, with injected-fault tests and documented trade-offs.
5. **Observability**: Micrometer/Prometheus metrics, Grafana dashboards (technical and business),
   at least three tested alerts, OpenTelemetry/Jaeger traces across `form → Kafka → promotion →
   notification`, and Loki logs.
6. **Security**: Trivy and dependency scanning, secrets outside the repository, Kubernetes RBAC and
   verifiable TLS.
7. **Performance and security testing**: Locust scenarios with declared objectives (p95, throughput,
   error rate) and OWASP ZAP baseline in the pipeline.
8. **Change management**: per-version release notes, semantic tags, per-environment change records
   with approval and result, and a real Kubernetes rollback. Production uses a **Blue-Green**
   strategy; dev and stage use RollingUpdate. Canary remains an optional evolution once metrics are
   mature.
9. **Complete documentation**: architecture, operations manual, infrastructure as code, cost
   analysis and this English summary.

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

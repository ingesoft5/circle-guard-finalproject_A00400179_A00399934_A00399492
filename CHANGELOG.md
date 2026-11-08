# Changelog

Todas las versiones notables de CircleGuard. Formato basado en
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y
[Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/).

## [Unreleased]

### Added

- Pipeline de Jenkins (`Jenkinsfile`) con build/tests, imágenes, publicación, despliegue a dev,
  E2E, promoción a stage, aprobación manual a prod, tag semver y release notes.
- Scripts `deploy/deploy.sh`, `rollback.sh`, `record-release.sh`, `current-version.sh`,
  `next-version.sh`, `tag-release.sh`, `release-notes.sh`, `notify.sh` y `e2e.sh`.
- Trazabilidad por ambiente en `deploy/releases/<env>.json` e historial `history.tsv`.
- Suite E2E de humo con Playwright en `tests/e2e-playwright`.
- Plantilla de solicitud de cambio y política de aprobación por tipo de cambio.
- Notificaciones de fallo/estado por Discord o Slack.
- `gradle/wrapper/gradle-wrapper.jar` versionado para que `./gradlew` funcione en Jenkins.

### Changed

- `Jenkinsfile` y `deploy/**` usan LF; `gradlew` y `Jenkinsfile` normalizados.
- Documentación de arquitectura del pipeline en `docs/arquitectura/pipeline-cd.md`.

### Known issues

- La línea base de HU-04 tenía 10 tests fallando; la ejecución de HU-04 (build #10) cerró 269
  pruebas OK. La etapa sigue siendo no bloqueante para no ocultar regresiones: un fallo nuevo se
  documenta y no se promueve a prod sin justificación.
- Los hosts de ambiente `t3.small` (2 GiB) no se usan en la demo de HU-06/HU-07; el stack corre en
  el Docker-in-Docker del host `ci`. Para un despliegue multi-host real se requieren hosts con más
  memoria y subir `QUOTA_VCPU_LIMIT`.

<!-- releases -->

## [v0.2.0] - 2026-11-08

- Fecha: 2026-11-08
- Tag: `v0.2.0`
- Commit: `59cec5c`
- Desde: `v0.1.0`

## Features

- completar release notes, GitHub release y documentacion
- semilla de change management y release notes

## Fixes

- publicar el tag en GitHub desde Jenkins
- publicar artifacts con netrc y evitar falso positivo de gitleaks
- consultar la version actual sin abortar
- reportar la linea que falla
- aceptar imagenes locales en despliegues locales

## Otros

- Merge pull request #9 from ingesoft5/HU-06-_Entrega-continua-y-promoción
- merge(dev): integrar HU-04 (integracion y cobertura) en HU-06
- Merge pull request #8 from ingesoft5/HU04-Pruebas-unitarias-y-integracion
- enlazar el PR #9
- registrar escaneo de secretos
- evidencias reales del build #6 y rollback #13
- Merge branch 'dev' into HU04-Pruebas-unitarias-y-integracion.
- ci(hu-04): ejecutar pruebas de integración y cobertura en Jenkins + evidencias
- ci(hu-04): ejecutar pruebas de integración y cobertura en Jenkins
- pruebas de integración con Testcontainers



## [v0.1.0] - 2026-11-08

- Fecha: 2026-11-08
- Tag: `v0.1.0`
- Commit: `dd825e6`

## Features

- soportar Docker/Node en Jenkins y completar el pipeline
- add multibranch ci pipeline and shared library
- add branching strategy and conventional commits hook
- add CI/CD pipeline and deployment scripts
- servidores de ambiente por pares dentro de la cuota de vCPU
- add per-environment compose stacks and image scripts
- add multi-stage non-root images for services and web
- preparar la topología B de HU-01 (servidores ci y nexus, parada automática y EULA pendiente)
- automatizar acceso seguro y preparación de AWS para HU-01
- fortalecer aprovisionamiento y seguridad de HU-01
- implementar scripts de bootstrap y configuración segura de servicios

## Fixes

- eliminar volumenes de dev/stage al promover
- detener el ambiente anterior con compose-down
- crear las bases de datos despues de postgres
- dar mas tiempo de arranque a zookeeper
- healthcheck de openldap con credenciales de admin
- resolver DNS del DinD con el resolver de la VPC
- instalar buildx para las cache mounts de Docker
- habilitar BuildKit y limitar imagenes a dev/main
- qualify gradle tasks and run sonar from root
- place library path inside modernscm retriever
- share docker network between jenkins and sonarqube
- load shared library and sonar config from jenkins.yaml
- size the zookeeper heap for the dev memory budget
- use a glibc node image for the Expo build stage
- make image verification labels exact
- restrict EC2 launches to pinned Ubuntu AMI
- fail operator dry-run on unauthorized operations
- align teardown policy statement order
- scope network creation to CircleGuard VPC
- corregir validaciones y apagado automático de HU-01 + Documento plan de despliegue 13
- una sola petición de MFA por ejecución en el teardown de CloudShell
- validar identidades IAM y endurecer el inicio de sesión de HU-01
- externaliza credenciales y agrega infraestructura HU-01 con Bash y Docker

## Otros

- merge(dev): integrar el fix de Gradle y Sonar del PR #7
- Merge pull request #7 from ingesoft5/fix/jenkins-pipeline-stages
- separar el alcance de HU-07
- alinear la guia del pipeline con el CI de HU-03
- merge(dev): integrar HU-01, HU-03 y HU-09 en HU-06
- Merge pull request #6 from ingesoft5/fix/jenkins-sonar-network
- Merge branch 'dev' into fix/jenkins-sonar-network
- Merge pull request #5 from ingesoft5/HU01_Infraestructura_nube_bash
- Merge remote-tracking branch 'origin/dev' into HU01_Infraestructura_nube_bash
- demostración en vivo de HU-01 con comandos y resultados
- Merge pull request #4 from ingesoft5/HU-03_Pipeline-Jenkins-multibranch
- ci(jenkins): add pollscm fallback to github push trigger
- Merge remote-tracking branch 'origin/dev' into HU-03_Pipeline-Jenkins-multibranch
- Merge pull request #3 from ingesoft5/HU01_Infraestructura_nube_bash
- Merge pull request #2 from ingesoft5/HU-09_Branching-conventional-commits
- sección de infraestructura en AWS, destrucción y reconstrucción desde cero y evidencias de HU-01
- actualizar informe con la reconstrucción desde cero (P1.2)
- ci(hu-09): add commit-lint workflow and dev integration flow
- update gradle wrapper properties
- document CD pipeline, change policy and evidence
- Merge branch 'HU01_Infraestructura_nube_bash' into dev
- actualizar informe final y evidencias de HU01
- documentar despliegue en AWS y evidencias de validación final
- Merge pull request #1 from ingesoft5/HU-02_Imágenes-Docker-inmutables
- record the follow-up commits in the IAG session
- add Docker installation guidance for WSL and hosts
- document immutable packaging, evidence and IAG decisions
- Initial commit



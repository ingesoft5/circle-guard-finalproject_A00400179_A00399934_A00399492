# Changelog

Todas las versiones notables de CircleGuard. Formato basado en
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y
[Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/).

<!-- releases -->

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

- Los 10 tests base de HU-01 siguen fallando; el pipeline los publica y deja el build `UNSTABLE`
  sin bloquear el despliegue. Se corrigen en HU-04/E1.6.
- Los servidores de ambiente `t3.small` (2 GiB) no soportan el stack completo; el despliegue real
  requiere servidores más grandes y subir `QUOTA_VCPU_LIMIT`.

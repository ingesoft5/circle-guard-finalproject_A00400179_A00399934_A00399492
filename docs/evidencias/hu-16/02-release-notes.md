# HU-16 · Release notes y tag `v0.3.0`

**Estado:** notas escritas; tag y GitHub Release pendientes de publicar desde Jenkins.

## Notas

[`../../release-notes/v0.3.0.md`](../../release-notes/v0.3.0.md)

Resumen del Sprint 2:

- Terraform (HU-09): módulos, backend remoto y tres ambientes.
- Kubernetes (HU-10): 8 servicios, web, middleware, Ingress y HPA.
- Observabilidad (HU-13): Prometheus, Grafana, Alertmanager, Jaeger y Loki.
- Seguridad (HU-14): Trivy, RBAC, TLS y gestión de secretos.
- Rendimiento y ZAP (HU-15): Locust y OWASP ZAP con compuerta.
- Registro D-30 (HU-16): `result`, `approved_by`, `approval_ref` e `image_digest`.

## Cómo publicar

```bash
# Opción Jenkins: build de main con PUBLISH_TAG=true
./deploy/tag-release.sh v0.3.0
./deploy/release-notes.sh v0.3.0
./deploy/github-release.sh v0.3.0
```

Pegar la salida real debajo cuando se ejecute:

```text
(pendiente)
```

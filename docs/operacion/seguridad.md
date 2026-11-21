# Seguridad de la plataforma (HU-14 · E2.6)

**Documento:** consolidación para HU-17 (E2.9) sobre HU-14 (S2 · E2.6)
**Última actualización:** 2026-11-21
**Estado:** los controles de HU-14 están **implementados y probados en local** (PR #20). La
integración en el `Jenkinsfile` está preparada como parche, y el RBAC/TLS de Kubernetes todavía no
se aplica al clúster. Este documento separa lo probado de lo pendiente.

> Detalle técnico por fase: [`../seguridad/hu-14.md`](../seguridad/hu-14.md).
> Evidencias: [`../evidencias/hu-14/`](../evidencias/hu-14/README.md).
> Diseño de pipeline y despliegue: [`../arquitectura/pipeline-cd.md`](../arquitectura/pipeline-cd.md),
> [`../arquitectura/kubernetes.md`](../arquitectura/kubernetes.md).

## 1. Matriz E2.6

| # | Criterio | Implementación | Estado |
|---|---|---|---|
| 1 | Análisis de vulnerabilidades de imágenes con Trivy | `security/scan-images.sh` sobre 9 imágenes propias y 13 de terceros; SARIF/JSON | Implementado y probado en local; **integración Jenkins pendiente** |
| 2 | Análisis de dependencias | SBOM de Gradle + Trivy; `security/scan-dependencies.sh` | Implementado y probado en local; **integración Jenkins pendiente** |
| 3 | Informes como artefactos del pipeline | JSON, SARIF, SBOM y resumen por imagen | Implementado en local; falta archivarlos desde Jenkins |
| 4 | Bloqueo por umbral de vulnerabilidades | Compuerta por severidad con excepciones y caducidad; 14 casos de prueba | Implementado y probado |
| 5 | Sin credenciales reales en el repositorio | `.gitignore`, `.gitleaks.toml` y Gitleaks en PASS | Cumplido |
| 6 | Secretos en mecanismo seguro | SSM SecureString, `.env` 0600, `security/k8s/create-secrets.sh` y catálogo | Cumplido en Compose; despliegue K8s pendiente |
| 7 | Credenciales protegidas en Jenkins | Credenciales `circleguard-*`; auditoría con `security/audit-jenkins-credentials.sh` | Cumplido |
| 8 | RBAC en Kubernetes | Manifiestos en `security/k8s/rbac/`, matriz y pruebas; RBAC de Jenkins validado en un controlador real | Probado en simulación; **validación en el clúster pendiente** |
| 9 | TLS en servicios expuestos | Terminador nginx y certificado de desarrollo; `security/tls/verify-tls.sh` | Probado con certificado de desarrollo; **Ingress TLS no desplegado** |
| 10 | Certificados verificables | `openssl s_client` y verificador propio | Certificado de desarrollo verificable; producción pendiente |
| 11 | Documentar controles y resultados | Este documento + `docs/seguridad/hu-14.md` + evidencias | Cumplido |

## 2. Lo que está implementado y probado

### 2.1 Imágenes y dependencias

- Trivy fijado por digest; escaneo de las 9 imágenes propias y 13 de terceros.
- Compuerta por severidad con umbral configurable en `security/policy.env`.
- Correcciones aplicadas a dependencias vulnerables dentro de la misma línea de versión.
- Resultado documentado: **3 CRITICAL y 22 HIGH** pendientes, con análisis de origen y excepciones.
- Evidencia: [`../evidencias/hu-14/fase2/`](../evidencias/hu-14/fase2/) y
  [`fase3/`](../evidencias/hu-14/fase3/).

### 2.2 Secretos y credenciales

- Gitleaks en PASS sobre el árbol de trabajo.
- Auditoría de credenciales de Jenkins sin imprimir valores.
- Creación de secretos de K8s desde SSM con `security/k8s/create-secrets.sh`.
- Catálogo de secretos en `security/k8s/secrets.catalog`.
- Evidencia: [`fase4/`](../evidencias/hu-14/fase4/) y [`fase5/`](../evidencias/hu-14/fase5/).

### 2.3 RBAC y TLS

- RBAC de Jenkins validado en un controlador real (`security/jenkins/validate-rbac-live.sh`).
- Manifiestos de RBAC de K8s para `jenkins-deployer`, `prometheus`, `developer` y `admin`.
- Terminador TLS con nginx y certificado de desarrollo; verificación con `openssl`.
- Evidencia: [`fase6/`](../evidencias/hu-14/fase6/) y [`fase7/`](../evidencias/hu-14/fase7/).

### 2.4 Excepciones con caducidad

- `security/exceptions.tsv` activo vacío y `security/exceptions.pending.tsv` con candidatas.
- Cada excepción tiene responsable, motivo y fecha de revisión.
- Evidencia: [`../evidencias/hu-14/excepciones.md`](../evidencias/hu-14/excepciones.md).

## 3. Lo que falta

| Pendiente | Depende de | Impacto |
|---|---|---|
| Aplicar `security/jenkins/Jenkinsfile-security-stages.patch` | HU-11 | Trivy y dependencias no bloquean en CI todavía |
| Desplegar RBAC en el clúster y capturar `kubectl auth can-i` | HU-10 (hecho) | El RBAC está probado en simulación, no en el clúster |
| Aplicar el Ingress TLS de `security/k8s/tls/` | HU-10/HU-11 | El TLS está probado con certificado de desarrollo, no en prod |
| Cerrar las 3 CRITICAL y 22 HIGH o declararlas como excepción | Matt | La compuerta las conoce, pero siguen abiertas |
| Corregir el mapeo de estados del QR (`SUSPECT`, `PROBABLE`, `CONFIRMED`) | HU-12/HU-16 | El gateway podría dejar pasar estados reales |

## 4. Pruebas

| Prueba | Herramienta | Evidencia |
|---|---|---|
| Escaneo de imágenes | Trivy | [`fase2/`](../evidencias/hu-14/fase2/) |
| Escaneo de dependencias | Trivy SBOM | [`fase3/`](../evidencias/hu-14/fase3/) |
| Escaneo de secretos | Gitleaks | [`fase4/`](../evidencias/hu-14/fase4/) |
| Credenciales de Jenkins | Auditoría propia | [`fase5/02-auditoria-credenciales-jenkins.txt`](../evidencias/hu-14/fase5/02-auditoria-credenciales-jenkins.txt) |
| RBAC | `rbac-check.py` y controlador real | [`fase6/`](../evidencias/hu-14/fase6/) |
| TLS | `openssl s_client` | [`fase7/`](../evidencias/hu-14/fase7/) |
| Sintaxis del parche Jenkins | Groovy + `kubeconform` | [`fase8/`](../evidencias/hu-14/fase8/) |

## 5. Riesgos

| Riesgo | Mitigación |
|---|---|
| Trivy bloquea por CVEs de la imagen base | Umbral en `CRITICAL`, imagen base actualizada y excepciones con caducidad |
| El certificado autofirmado no valida en el navegador | Documentar la limitación; usar TLS de desarrollo solo en la demo interna |
| RBAC demasiado amplio para que “funcione” | Revisar `kubectl auth can-i --list` y quitar permisos de Secrets |
| Secretos en logs de Jenkins | Enmascarar credenciales; no imprimir el entorno completo |
| Estados reales del QR sin bloquear | Corregir el mapeo antes de la demo o declararlo como hallazgo crítico |

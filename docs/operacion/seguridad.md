# Seguridad de la plataforma (HU-14 · E2.6)

**Documento:** consolidación para HU-17 (E2.9) sobre HU-14 (S2 · E2.6)
**Última actualización:** 2026-11-16
**Estado:** controles del Sprint 1 **verificados**; los controles de Kubernetes, Trivy y TLS están
**pendientes** de HU-14. Este documento separa lo que existe de lo que se va a implementar para no
declarar como hecho lo que todavía no está.

> Diseño de pipeline y despliegue: [`pipeline-cd.md`](../arquitectura/pipeline-cd.md),
> [`kubernetes.md`](../arquitectura/kubernetes.md).

## 1. Matriz E2.6

| # | Criterio | Implementación actual | Estado |
|---|---|---|---|
| 1 | Análisis de vulnerabilidades de imágenes con Trivy | Pipeline no lo ejecuta | Pendiente |
| 2 | Análisis de dependencias | Gradle resuelve dependencias; no hay escaneo bloqueante | Pendiente |
| 3 | Informes como artefactos del pipeline | Jenkins archiva JUnit/JaCoCo; falta Trivy | Parcial |
| 4 | Bloqueo por umbral de vulnerabilidades | No existe | Pendiente |
| 5 | Sin credenciales reales en el repositorio | `.gitignore`, `.gitleaks.toml`, escaneo en PASS | Cumplido |
| 6 | Secretos en mecanismo seguro | SSM SecureString + `.env` 0600; K8s Secrets pendiente | Parcial |
| 7 | Credenciales protegidas en Jenkins | `circleguard-*` como credenciales, no en el Jenkinsfile | Cumplido |
| 8 | RBAC en Kubernetes | No hay clúster todavía | Pendiente |
| 9 | TLS en servicios expuestos | Registro CNCF con TLS; Ingress pendiente | Parcial |
| 10 | Certificados verificables | Certificado autofirmado del registro; falta Ingress | Parcial |
| 11 | Documentar controles y resultados | Este documento + evidencias | En curso |

## 2. Lo que ya existe (Sprint 1)

### 2.1 Secretos fuera del repositorio

- `.env.example` solo tiene nombres y valores de ejemplo; los valores reales viven en
  `~/.circleguard/*.env` con permisos `0600`.
- En AWS, los secretos están en **SSM Parameter Store** como `SecureString` y se inyectan al host.
- `infra/scan-secrets.sh` ejecuta Gitleaks y distingue worktree de historial.
- Resultado declarado: **0 secretos activos en el worktree**; los 51 hallazgos del historial se
  consideran comprometidos y no se reutilizan.

```bash
bash infra/scan-secrets.sh          # PASS esperado
```

### 2.2 Acceso a la plataforma

- Jenkins, SonarQube y el registro **no** se exponen a Internet: solo SSH (22) desde la IP del
  operador; el resto por túnel.
- IAM con roles temporales y MFA; no hay claves de acceso permanentes.
- El registro CNCF Distribution usa TLS y `htpasswd` (usuario `ci`).
- Imágenes Docker multi-stage con usuario no root.

### 2.3 Seguridad de la aplicación

| Control | Dónde | Nota |
|---|---|---|
| JWT firmado | `auth`, `gateway` | Secreto `CG_JWT_SECRET` fuera del repo |
| RBAC de aplicación | Spring Security en auth/identity/promotion | Roles `ADMIN`, `HEALTH_CENTER`, `VISITOR` |
| Anonimización | `identity` | Los nombres no salen de la bóveda |
| Cifrado de identidades | `IdentityEncryptionConverter` | Clave en SSM |
| QR firmado y de vida corta | `gateway` | Secreto `CG_QR_SECRET` |
| Auditoría | Kafka `audit.identity.accessed`, `notification.audit` | Trazabilidad de accesos |

**Hallazgo de HU-12 que afecta la seguridad:** `QrValidationService` solo bloquea `CONTAGIED` y
`POTENTIAL`, pero promotion escribe `SUSPECT`, `PROBABLE` y `CONFIRMED`. Con los estados reales, el
control de acceso no bloquea a nadie. Debe corregirse en HU-14 o en una historia de defecto; no se
corrigió en HU-12 para no ampliar su alcance.

## 3. Lo que falta (HU-14)

### 3.1 Trivy en el pipeline

```groovy
stage('Trivy image scan') {
  steps {
    sh '''
      trivy image --exit-code 1 --severity CRITICAL \
        --format table -o trivy-auth.txt $IMAGE
      trivy image --exit-code 0 --severity HIGH \
        --format json -o trivy-auth.json $IMAGE
    '''
    archiveArtifacts artifacts: 'trivy-*.txt,trivy-*.json', allowEmptyArchive: false
  }
}
```

- **Umbral propuesto:** falla con `CRITICAL`; reporta `HIGH` sin bloquear (se revisa y se documenta).
- El umbral debe estar en una variable (`TRIVY_SEVERITY=CRITICAL`) para poder explicarlo.
- Se ejecuta **después** de construir la imagen y **antes** de publicarla.

### 3.2 Análisis de dependencias

- `./gradlew dependencyCheckAnalyze` (OWASP Dependency-Check) u `osv-scanner`.
- Publicar el informe HTML como artefacto.
- Un `CRITICAL` con CVSS ≥ 9 bloquea; el resto se documenta con fecha de revisión.

### 3.3 RBAC en Kubernetes

| Sujeto | Namespace | Permisos |
|---|---|---|
| `jenkins-deployer` | `circleguard-dev/stage/prod` | `get,list,watch,create,update,patch` sobre Deployments, Services, ConfigMaps; **no** Secrets |
| `prometheus` | `observability` + lectura de pods | `get,list,watch` pods/services/endpoints |
| `developer` | dev/stage | lectura + port-forward; sin prod |
| `admin` | todos | solo operador de guardia |

Se crean con `Role`/`RoleBinding` (no `ClusterRole` salvo para Prometheus). El `kubeconfig` de
Jenkins usa el `ServiceAccount` `jenkins-deployer`, no credenciales de administrador.

### 3.4 TLS

- Ingress con `cert-manager` y `Let's Encrypt` si hay dominio público; si no, certificado
  autofirmado y validación con `openssl s_client`.
- Redirección 301 de HTTP a HTTPS.
- HSTS opcional; no se activa si el certificado es autofirmado.
- Evidencia: `openssl s_client -connect <host>:443 -servername <host>` con `Verify return code: 0`
  (o explicación del autofirmado).

### 3.5 Secretos en Kubernetes

- `Secret` creado desde SSM con `External Secrets Operator` o un `Job` de sincronización.
- Nunca `stringData` con valores reales en Git.
- `imagePullSecret` para el registro.
- Rotación documentada en el manual de operaciones §6.

## 4. Pruebas de seguridad

| Prueba | Herramienta | Cuándo | Evidencia |
|---|---|---|---|
| Escaneo de imagen | Trivy | Cada build | `trivy-*.json`, stage en Jenkins |
| Escaneo de dependencias | Dependency-Check/OSV | Cada build | Informe HTML |
| Escaneo de secretos | Gitleaks | Cada build | `scan-secrets.log` |
| Análisis dinámico web | OWASP ZAP baseline | Cada build de dev | Informe HTML (HU-15) |
| TLS | `openssl s_client` | Al desplegar | Salida con código 0 |
| RBAC | `kubectl auth can-i` | Al desplegar | Matriz de permisos |
| QR / acceso | Prueba funcional | Antes de prod | Caso `SUSPECT` bloqueado |

## 5. Evidencias

| Evidencia | Archivo sugerido | Estado |
|---|---|---|
| Informe Trivy | `docs/evidencias/hu-14/01-trivy.json` | Pendiente |
| Informe de dependencias | `docs/evidencias/hu-14/02-dependency-check.html` | Pendiente |
| Escaneo de secretos | `docs/evidencias/hu-14/03-gitleaks.txt` | Existe en HU-06/HU-07 |
| RBAC | `docs/evidencias/hu-14/04-rbac.yaml` + `kubectl auth can-i` | Pendiente |
| TLS | `docs/evidencias/hu-14/05-tls.txt` | Pendiente |
| Credenciales de Jenkins | Captura sin valores | Pendiente |

## 6. Riesgos

| Riesgo | Mitigación |
|---|---|
| Trivy bloquea todo por CVEs base de la imagen | Fijar umbral en `CRITICAL` y actualizar la imagen base |
| El certificado autofirmado no “valida” en el navegador | Documentar la limitación y usar `-k` solo en la demo interna |
| RBAC demasiado amplio para que “funcione” | Revisar `kubectl auth can-i --list` y quitar permisos de Secrets |
| Secretos en logs de Jenkins | Enmascarar credenciales; no imprimir `env` completo |
| El defecto del gateway deja pasar estados reales | Corregir antes de la demo o declararlo como hallazgo crítico |

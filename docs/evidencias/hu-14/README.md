# Evidencias HU-14 · Fortalecimiento de la seguridad (E2.6)

**Estado:** implementado y probado en local; integrado en `dev` por el PR #20. La aplicación del
paso de Jenkins y el despliegue de RBAC/TLS en el clúster siguen pendientes.

**Documento dueño:** [`../../operacion/seguridad.md`](../../operacion/seguridad.md)
**Detalle técnico:** [`../../seguridad/hu-14.md`](../../seguridad/hu-14.md)

## Fases

| Fase | Contenido | Evidencia | Estado |
|---|---|---|---|
| 1 | Diagnóstico | — | Hecho |
| 2 | Escaneo de imágenes con Trivy | [`fase2/`](fase2/) | Implementado y probado en local |
| 3 | Análisis de dependencias | [`fase3/`](fase3/) | Implementado y probado en local |
| 3b | Correcciones de vulnerabilidades | [`correcciones/`](correcciones/) | Aplicadas; quedan 3 CRITICAL y 22 HIGH |
| 4 | Escaneo de secretos | [`fase4/`](fase4/) | Implementado y probado |
| 5 | Gestión de secretos | [`fase5/`](fase5/) | Herramientas probadas; despliegue K8s pendiente |
| 6 | RBAC (Jenkins y Kubernetes) | [`fase6/`](fase6/) | Jenkins validado en real; K8s en simulación |
| 7 | TLS | [`fase7/`](fase7/) | Probado con certificado de desarrollo |
| 8 | Integración con Jenkins | [`fase8/`](fase8/) | Parche verificado; no aplicado |
| 9 | Excepciones con caducidad | [`excepciones.md`](excepciones.md) | Implementado y probado |

## Comprobaciones sobre HU-01/HU-02

| Evidencia | Archivo |
|---|---|
| RBAC de Jenkins con archivos reales | [`hu01-hu02/01-jenkins-rbac-archivos-reales.txt`](hu01-hu02/01-jenkins-rbac-archivos-reales.txt) |
| Verificación estática de HU-01 | [`hu01-hu02/02-hu01-verificacion-estatica.txt`](hu01-hu02/02-hu01-verificacion-estatica.txt) |
| Imagen del cliente web antes/después | [`hu01-hu02/03-web-imagen-antes-despues.txt`](hu01-hu02/03-web-imagen-antes-despues.txt) |
| Regresión del proxy web | [`hu01-hu02/04-web-proxy-regresion.txt`](hu01-hu02/04-web-proxy-regresion.txt) |
| Proxy con servicios reales | [`hu01-hu02/05-web-proxy-con-servicios-reales.txt`](hu01-hu02/05-web-proxy-con-servicios-reales.txt) |

## Resumen de herramientas

[`resumen-pruebas-de-las-herramientas.txt`](resumen-pruebas-de-las-herramientas.txt)

## Pendiente para cerrar

1. ~~Integrar los stages de seguridad en el `Jenkinsfile`~~ — **hecho** sobre el Jenkinsfile de HU-11 (sintaxis Groovy y auditoría de credenciales verificadas: [fase11/01-jenkinsfile-integrado.txt](fase11/01-jenkinsfile-integrado.txt)).
2. Con el kubeconfig de cada ambiente: `bash security/k8s/fetch-kubeconfig.sh <env>` y luego `bash security/k8s/test-rbac.sh --namespace circleguard-<env>` (requiere la cuenta AWS del proyecto).
3. Con el clúster: `bash security/k8s/tls/ensure-tls-secret.sh` y verificar el certificado (el Ingress es de Traefik; el componente TLS de `deploy/k8s/components/tls` añade `spec.tls` a los overlays). `security/k8s/tls/ingress-tls.yaml` es una referencia de ingress-nginx y no se aplica.
4. Aprobar o corregir las excepciones de `security/exceptions.pending.tsv` (responsable, justificación y caducidad); entonces pasar `SECURITY_GATE` a `enforce`.

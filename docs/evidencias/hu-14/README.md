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

1. Aplicar `security/jenkins/Jenkinsfile-security-stages.patch` en el `Jenkinsfile` (HU-11).
2. Desplegar `security/k8s/rbac/` y capturar `kubectl auth can-i`.
3. Aplicar `security/k8s/tls/ingress-tls.yaml` y verificar el certificado en el clúster.
4. Cerrar o declarar las 3 CRITICAL y 22 HIGH.

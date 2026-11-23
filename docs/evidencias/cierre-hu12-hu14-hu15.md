# Cierre de HU-12, HU-14 y HU-15 · rutas a las evidencias

Estado a 2026-11-22, con `dev` que ya contiene HU-09, HU-10, HU-11, HU-13, HU-16 y HU-17. Todo lo de esta tabla se puede verificar **sin AWS**. Lo que exige la cuenta de AWS del proyecto está en «Qué no se puede cerrar sin AWS o sin una decisión».

## HU-12 · Autenticación, LDAP y expiración del QR

| Qué | Ruta |
|---|---|
| Informe general | [hu-12/evidencias-hu12.md](hu-12/evidencias-hu12.md) |
| LDAP configurable (sin contraseña por defecto) y su prueba | [hu-12/auth-ldap-configurable.md](hu-12/auth-ldap-configurable.md) |
| Código | [SecurityConfig.java](../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/security/SecurityConfig.java) y `QrExpirationConfigurationTest` |
| Defecto del QR hallado con la prueba de carga (80 % de errores con la configuración antigua) | [hu-15/hallazgo-qr/README.md](hu-15/hallazgo-qr/README.md) |

## HU-14 · Fortalecimiento de la seguridad

| Qué | Ruta |
|---|---|
| Documento principal (todas las fases, matriz y dependencias) | [../seguridad/hu-14.md](../seguridad/hu-14.md) |
| Resumen operativo (matriz E2.6) | [../operacion/seguridad.md](../operacion/seguridad.md) |
| Índice de evidencias | [hu-14/README.md](hu-14/README.md) · texto para el informe: [informe-hu12-hu14-hu15.md](informe-hu12-hu14-hu15.md) |
| Imágenes (Trivy), compuerta y bloqueo controlado | [hu-14/fase2/](hu-14/fase2/) |
| Dependencias | [hu-14/fase3/](hu-14/fase3/) y [hu-14/correcciones/](hu-14/correcciones/) |
| Secretos (Gitleaks) y archivos sensibles | [hu-14/fase4/](hu-14/fase4/) · escaneo actual: [hu-14/fase11/03-secretos.txt](hu-14/fase11/03-secretos.txt) |
| Creación de secretos y auditoría de credenciales de Jenkins | [hu-14/fase5/](hu-14/fase5/) |
| RBAC (Kubernetes y Jenkins en un controlador real) | [hu-14/fase6/](hu-14/fase6/) |
| TLS | [hu-14/fase7/](hu-14/fase7/) |
| Integración con Jenkins | [hu-14/fase8/](hu-14/fase8/) · **estado actual**: [hu-14/fase11/01-jenkinsfile-integrado.txt](hu-14/fase11/01-jenkinsfile-integrado.txt) |
| Excepciones con caducidad (marco y candidatas) | [hu-14/excepciones.md](hu-14/excepciones.md) |
| Adaptación a HU-09/HU-10: render, nginx, secretos, IaC | [hu-14/fase10/](hu-14/fase10/) |
| Render tras el merge con `dev` (43 recursos por ambiente + RBAC 7, kubeconform estricto) | [hu-14/fase11/04-render-tras-merge.txt](hu-14/fase11/04-render-tras-merge.txt) |
| Suite completa de pruebas de las herramientas (175 casos, 11 suites; en WSL/Linux) | [hu-14/fase11/02-suite-completa.txt](hu-14/fase11/02-suite-completa.txt) |

## HU-15 · Pruebas avanzadas (carga y seguridad dinámica)

| Qué | Ruta |
|---|---|
| Informe con resultados, límites y conclusiones | [hu-15/INFORME.md](hu-15/INFORME.md) |
| Cómo ejecutar y evaluar | [../operacion/pruebas-avanzadas.md](../operacion/pruebas-avanzadas.md) |
| Carga con Locust (10/50/100 usuarios), evaluación y gráficas | [hu-15/rendimiento/](hu-15/rendimiento/) · [evaluation.md](hu-15/rendimiento/evaluation.md) |
| OWASP ZAP antes de las cabeceras | [hu-15/zap/](hu-15/zap/) |
| OWASP ZAP tras las cabeceras de seguridad de nginx | [hu-15/zap-con-cabeceras/](hu-15/zap-con-cabeceras/) |
| Hallazgo del QR | [hu-15/hallazgo-qr/](hu-15/hallazgo-qr/) |
| Integración en Jenkins (stages «ZAP baseline dev» y «Performance dev») | [Jenkinsfile](../../Jenkinsfile) · [hu-14/fase11/01-jenkinsfile-integrado.txt](hu-14/fase11/01-jenkinsfile-integrado.txt) |

## Qué no se puede cerrar sin AWS o sin una decisión

| Pendiente | Por qué | Cómo se cierra |
|---|---|---|
| Probar RBAC y TLS en el clúster de cada ambiente | Requiere la cuenta AWS del proyecto | `bash security/k8s/fetch-kubeconfig.sh <env>`, luego `bash security/k8s/test-rbac.sh --namespace circleguard-<env>` y `bash security/k8s/tls/ensure-tls-secret.sh`; adjuntar la salida en `hu-14/fase11/` |
| Ejecutar un build en Jenkins con los stages de HU-14/HU-15 | Requiere el Jenkins de AWS y credenciales | Parámetros `SECURITY_GATE=enforce`, `RUN_ZAP=true`, `RUN_PERF=true` (con `E2E_URL_DEV` = Ingress de dev y la credencial `perf-test-user`) |
| Aprobar las excepciones y pasar a `enforce` | Es decisión de los dueños (HU-09: 4 CRITICAL de IaC; Spring: 3 CRITICAL y 22 HIGH de dependencias) | Completar `security/exceptions.pending.tsv` (responsable, justificación, caducidad) y moverlas a `exceptions.tsv`; sustituir `.trivyignore` de HU-11 |
| Objetivos de rendimiento a 100 usuarios | Con 0,5 CPU por servicio no se cumplen (acceso: p95 460 ms frente a 300 ms; envío: 40,6 req/s frente a 50). Es un resultado medido y declarado, no un error de método | Repetir en el clúster con los límites de recursos de HU-10 o subir las CPU del servicio de auth |
| Mapeo de estados del QR en el gateway | Pertenece a HU-04 (el gateway solo deniega `CONTAGIED`/`POTENTIAL` y la promoción escribe `CONFIRMED`/`SUSPECT`/`PROBABLE`) | Corregir en `circleguard-gateway-service`; no se tocó |

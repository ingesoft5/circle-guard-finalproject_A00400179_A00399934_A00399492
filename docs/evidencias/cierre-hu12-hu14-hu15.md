# Cierre de HU-12, HU-14 y HU-15 · rutas a las evidencias

Estado a 2026-11-23, con `dev` que ya contiene HU-09, HU-10, HU-11, HU-13, HU-16 y HU-17. Los controles se ejecutaron en el Jenkins y el clúster de AWS; lo que queda abierto, y por qué, está en «Qué queda abierto y por qué».

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

## Qué queda abierto y por qué

| Pendiente | Estado | Cómo se cierra |
|---|---|---|
| RBAC y TLS en el clúster de cada ambiente | **Hecho** en dev, stage y prod: RBAC 38/38 y TLS 8/8 | [hu-14/fase11/](hu-14/fase11/) |
| Build en Jenkins con los stages de HU-14/HU-15 | **Hecho** (build de `dev` 0.3.0-78f32ed y build #10): IaC PASS con 62 excepciones, secretos PASS, Trivy de imágenes sin bloqueos, ZAP sin High, JaCoCo 94 %, `Terraform checks` sin cambios en los tres ambientes (cifras del build de `dev` reportadas por quien lo ejecutó) | Adjuntar el log del build de `dev` junto a `pipeline-10.log` |
| Dependencias de Spring (8 servicios: 1–2 CRITICAL y 14–20 HIGH por servicio) | **Riesgo aceptado** (opción C, D-39): informan, no bloquean; el build queda UNSTABLE solo por eso. Las CRITICAL exigen Spring Boot 4 y Spring Boot 3.5.16 rompe 2 pruebas de identity | Plan, responsable (Matthew Lane) y fecha (2026-12-22) en la FASE 12 de [../seguridad/hu-14.md](../seguridad/hu-14.md); luego `SECURITY_GATE=enforce` |
| Excepciones de IaC | **Hecho**: 54 vigentes (2 de juanes, 52 de matthew), 30 días | [security/exceptions.tsv](../../security/exceptions.tsv) |
| Objetivos de rendimiento a 100 usuarios | **No cumplidos (NOT MET)**: p95 y errores cumplen en el clúster; el throughput no (192,3 de 200 y 48,7 de 50 aun con 25 % más de carga). Hay un techo de capacidad no atribuido | Medir CPU del nodo y del agente durante la prueba o repartir la carga en varios procesos de Locust; adjuntar el log de la repetición |
| Mapeo de estados del QR en el gateway | Pertenece a HU-04 (solo deniega `CONTAGIED`/`POTENTIAL`; promoción escribe `CONFIRMED`/`SUSPECT`/`PROBABLE`) | Corregir en `circleguard-gateway-service`; no se tocó |

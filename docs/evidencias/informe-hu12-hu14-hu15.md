# Informe · HU-12, HU-14 y HU-15 (partes para el PDF)

Texto listo para pegar en el informe, con los enlaces a las evidencias del repositorio y la lista de capturas que hay que tomar (no se pueden generar desde el código: salen de Jenkins, GitHub y AWS). Estado a 2026-11-23. Cada cifra procede de un log o un archivo enlazado; lo que no se pudo verificar está declarado como tal.

---

## HU-12 · Patrones de diseño, autenticación y expiración del QR

**Objetivo.** Que el servicio de autenticación sea configurable y resiliente sin secretos en el código, y que el QR de acceso expire a los 60 s.

**Qué se hizo.**
- El contexto LDAP de `auth` se configura con `spring.ldap.urls/base/username/password`, **sin contraseña por defecto** ([SecurityConfig.java](../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/security/SecurityConfig.java), con su prueba).
- La expiración del QR queda fija en `qr.expiration: 60000` con una prueba de configuración que falla si cambia el valor.
- La prueba de carga de HU-15 reveló que **con la configuración anterior el 80 % de las validaciones del QR fallaban**; ese defecto está documentado con su evidencia.

**Resultados.** Cobertura de líneas de `auth`: 98,6 %. 330 pruebas unitarias y 11 de integración, sin fallos.

**Evidencias.** [hu-12/evidencias-hu12.md](hu-12/evidencias-hu12.md) · [hu-12/auth-ldap-configurable.md](hu-12/auth-ldap-configurable.md) · [hu-15/hallazgo-qr/README.md](hu-15/hallazgo-qr/README.md) · revisión: [../revisiones/hu-12-revision.md](../revisiones/hu-12-revision.md).

**Limitación declarada.** El gateway solo deniega los estados `CONTAGIED` y `POTENTIAL`, pero la promoción escribe `CONFIRMED`, `SUSPECT` y `PROBABLE`. Es un defecto de HU-04, reportado y no corregido en esta entrega.

**Capturas a incluir.** (1) Informe JaCoCo de `auth` en Jenkins (build de `dev`; tras la corrección de `cgUnitTests` ya enlaza el código fuente). (2) La prueba `QrExpirationConfigurationTest` en verde en el reporte de pruebas del build.

---

## HU-14 · Fortalecimiento de la seguridad

**Objetivo.** Escaneo continuo de vulnerabilidades, secretos fuera del repositorio, RBAC aplicado y TLS verificable.

**Qué se hizo.**
- **Cuatro escáneres con compuerta por umbral:** imágenes, dependencias, secretos (Gitleaks) e IaC (Trivy config), integrados en el [Jenkinsfile](../../Jenkinsfile). Un escaneo que no corre sale con código 2 y falla el build; nunca cuenta como aprobado.
- **Excepciones que caducan** ([security/exceptions.tsv](../../security/exceptions.tsv)): responsable, justificación, aprobación y 30 días; sin comodines. Una excepción no oculta el hallazgo: solo cambia si bloquea.
- **Kubernetes:** RBAC por ambiente (`jenkins-deployer`, Roles `deployer`, `readonly`, `secret-manager`), Pod Security Admission, TLS por Traefik.
- **Secretos por stdin** en los scripts de HU-10; **cabeceras de seguridad** y bloqueo de `/actuator` en nginx.

**Resultados verificados en AWS (ejecutados por Juan Esteban).**

| Ambiente | RBAC | TLS |
|---|---|---|
| dev | 38/38 PASS tras aplicar | 8/8 PASS |
| stage | 38/38 PASS | 8/8 PASS |
| prod | 38/38 PASS | 8/8 PASS |

IaC: 4 CRITICAL, 58 HIGH, 70 MEDIUM y 131 LOW; los 62 CRITICAL/HIGH están cubiertos por excepciones con dueño y 30 días (siguen contados). Secretos: ningún secreto activo. 11 suites de las herramientas (178 casos) en PASS.

**Evidencias.** Índice: [cierre-hu12-hu14-hu15.md](cierre-hu12-hu14-hu15.md) · [../seguridad/hu-14.md](../seguridad/hu-14.md) · [hu-14/fase11/](hu-14/fase11/) (RBAC, TLS, `pipeline-10.log`) · [hu-14/fase10/](hu-14/fase10/) · [hu-14/excepciones.md](hu-14/excepciones.md).

**Limitaciones declaradas.** El escaneo de dependencias **informa pero no bloquea** (`SECURITY_GATE=report`): en el build de `dev` 0.3.0-78f32ed los 8 servicios tienen 1–2 CRITICAL y 14–20 HIGH de Spring. Es un **riesgo aceptado** con plan, responsable (Matthew Lane) y fecha (2026-12-22): las CRITICAL exigen Spring Boot 4 y Spring Boot 3.5.16 rompe 2 pruebas de `identity-service`; por eso el build queda UNSTABLE solo por esa causa y así se declara (no hay SUCCESS). Con `enforce` el pipeline fallaría. El certificado TLS es de una CA de desarrollo, no de una CA pública.

**Capturas a incluir.** (1) Jenkins, build con el stage *Security: secrets, dependencies and governed IaC* y los informes archivados. (2) Salida de `test-rbac.sh` (matriz 38/38) de [fase11/04-rbac-dev-despues.txt](hu-14/fase11/04-rbac-dev-despues.txt). (3) `verify-tls.sh` 8/8 ([fase11/08-tls-dev-verify.txt](hu-14/fase11/08-tls-dev-verify.txt)). (4) Pestaña *Files* del PR con `security/exceptions.tsv`.

---

## HU-15 · Pruebas avanzadas (carga y seguridad dinámica)

**Objetivo.** Medir rendimiento con Locust contra objetivos declarados **antes** de medir, y analizar la seguridad dinámica con OWASP ZAP.

**Qué se hizo.** Dos escenarios de Locust (validación de acceso y envío de cuestionarios; 10/50/100 usuarios), un evaluador que compara con [targets.json](../../tests/performance/targets.json), y ZAP baseline con compuerta (umbral High). Ambos se integraron en el Jenkinsfile (`RUN_ZAP`, `RUN_PERF`).

**Resultados en el clúster de dev (Jenkins, 100 usuarios).**

| Flujo | p95 (objetivo) | Throughput (objetivo) | Errores |
|---|---|---|---|
| Validación de acceso | 230 ms (≤ 300) ✔ | 189,7 → 192,3 req/s con 25 % más de carga (≥ 200) ✘ | 0 % ✔ |
| Envío de cuestionario | 280 ms (≤ 800) ✔ | 48,4 → 48,7 req/s (≥ 50) ✘ | 0,17 % ✔ |

ZAP baseline sobre dev: **sin alertas High**. Antes de las cabeceras de nginx había 2 Medium y 7 Low; después, 1 Medium (`style-src 'unsafe-inline'`) y 3 Low.

**Lectura honesta.** Latencia y errores cumplen; **el throughput no** (NOT MET). Se sospechó del generador de carga y se descartó al ofrecer 25 % más de carga sin que el resultado cambiara: hay un techo de capacidad cerca de 190 y 49 req/s. La causa (servicio, nodo único o generador) no está separada y no se afirma. Los objetivos no se cambiaron después de medir.

**Evidencias.** [hu-15/INFORME.md](hu-15/INFORME.md) · [hu-15/rendimiento/](hu-15/rendimiento/) · [hu-15/zap-con-cabeceras/](hu-15/zap-con-cabeceras/) · [hu-14/fase11/pipeline-10.log](hu-14/fase11/pipeline-10.log) · guía: [../operacion/pruebas-avanzadas.md](../operacion/pruebas-avanzadas.md).

**Limitación declarada.** El log de la repetición con 25 % más de carga (192,3 y 48,7 req/s) lo reportó quien la ejecutó y **falta adjuntarlo**.

**Capturas a incluir.** (1) Tabla de veredicto del build #10 (`evaluation.md`). (2) Gráficas de `hu-15/rendimiento/graficas/`. (3) Informe HTML de ZAP archivado en Jenkins (*OWASP ZAP baseline*). (4) La repetición, cuando se adjunte.

---

## Cómo se usó la IA en estas HU

Registrado en [../iag/sesiones/2026-11-23-hu-12-14-15.md](../iag/sesiones/2026-11-23-hu-12-14-15.md) y en el anexo [IAG_REGISTRO.md](../../IAG_REGISTRO.md), con tres errores de la IA descubiertos por la ejecución real (escaneo no ejecutado leído como hallazgo, hipótesis de throughput refutada, mensajes de commit que incumplían el lint).

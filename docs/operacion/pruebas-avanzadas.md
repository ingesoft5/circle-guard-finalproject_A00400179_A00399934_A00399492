# Pruebas avanzadas de rendimiento y seguridad (HU-15 · E2.7)

**Documento:** consolidación para HU-17 (E2.9) sobre HU-15 (S2 · E2.7)
**Última actualización:** 2026-11-20
**Estado:** **Implementado y ejecutado en un ambiente local aislado** (Docker Compose, nunca prod). Locust, ZAP baseline, la compuerta
de bloqueo y los pasos de Jenkins existen y están probados; **la integración en el Jenkinsfile está preparada como parche, no aplicada**
(el Jenkinsfile es de HU-11), y **no se ha ejecutado en Jenkins ni en dev de AWS** (HU-09/HU-10/HU-11). Resultados e interpretación:
[docs/evidencias/hu-15/INFORME.md](../evidencias/hu-15/INFORME.md).

> Resultados base de pruebas: [`../evidencias/hu-04/README.md`](../evidencias/hu-04/README.md).

## 1. Objetivos de rendimiento (declarados antes de medir)

Congelados en [tests/performance/targets.json](../../tests/performance/targets.json) y verificados por una prueba que falla si cambian sin avisar.

| Flujo | Solicitud medida | Objetivo | Justificación |
|---|---|---|---|
| Validación de acceso (`gateway`) | `POST /gateway/gate/validate` | p95 ≤ 300 ms · ≥ 200 req/s · errores < 1 % | Es el flujo de una puerta; debe responder antes de que la fila avance |
| Envío de cuestionario (`form`) | `POST /form/surveys` | p95 ≤ 800 ms · ≥ 50 req/s · errores < 2 % | Escritura + evento Kafka; tolera más latencia que el acceso |
| Promoción (consumidor) | — | p95 ≤ 2 s por evento · lag < 100 | **No se mide con Locust** (es un consumidor de Kafka): se observa con las métricas de HU-13 |
| Sistema en conjunto | escalón de 100 usuarios | 100 usuarios concurrentes durante 5 min sin degradación | Escala de un campus pequeño |

**Regla:** si un objetivo no se cumple, se reporta el valor real y la causa; no se cambia el objetivo después de medir.
Las solicitudes auxiliares (`GET /auth/qr/generate`, `GET /form/questionnaires/active`) se miden y se informan, sin objetivo.

## 2. Escenarios Locust

```text
tests/performance/
├── locustfile.py            # AccessValidationUser, SurveySubmissionUser
├── access_validation.py     # login compartido (1 vez) -> QR -> validación
├── survey_submission.py     # cuestionario activo -> envío (datos sintéticos)
├── common.py                # configuración por entorno; rechaza prod
├── seed_questionnaire.py    # deja un cuestionario activo sintético (idempotente)
├── targets.json             # objetivos declarados
├── run-perf.sh              # escalones, calentamiento, gráficas y evaluación
├── evaluate.py, charts.py, consolidate.py
└── README.md
```

Las rutas son las reales de la aplicación, a través del proxy del cliente web (como las usa el cliente):

| Flujo | Solicitudes |
|---|---|
| Acceso | `POST /auth/api/v1/auth/login` (una vez, preparación) → `GET /auth/api/v1/auth/qr/generate` → `POST /gateway/api/v1/gate/validate` con `{"token": <qr>}` |
| Cuestionario | `GET /form/api/v1/questionnaires/active` → `POST /form/api/v1/surveys` con `anonymousId` sintético y respuestas `NO` |

(Las rutas `/api/v1/gateway/validate` y `/api/v1/forms/survey` de la versión anterior de este documento no existen en la aplicación.)

### 2.1 Parámetros (todo configurable)

| Parámetro | Cómo | Por defecto |
|---|---|---|
| Usuarios concurrentes | `--steps "10 50 100"` | escalones de 10, 50 y 100 |
| Duración | `--duration 5m` | 5 min por escalón |
| Tasa de generación de usuarios | `--spawn-rate 10` | 10 usuarios/s |
| Tasa de solicitudes por usuario | `PERF_ACCESS_RPS_PER_USER`, `PERF_SURVEY_RPS_PER_USER` | 2 y 0,5 (con 100 usuarios se ofrecen 200 y 50 solicitudes/s, igual que los objetivos) |
| Calentamiento | `--warmup 20s` | 20 s con 2 usuarios, no evaluados |
| Ambiente | `PERF_TARGET_ENV` = `local`, `dev` o `stage` (cualquier otro valor, **prod incluido, se rechaza**) | obligatorio |
| Usuario de prueba | `PERF_USERNAME` y `PERF_PASSWORD` (entorno; en Jenkins, una credencial) | obligatorio |

```bash
export PERF_TARGET_ENV=local PERF_USERNAME=<usuario de prueba>
read -rs -p "Contraseña del usuario de prueba: " PERF_PASSWORD; export PERF_PASSWORD   # sin eco, no se guarda
tests/performance/run-perf.sh --network <red del stack> --host http://web:8080 --seed
```

**Cambio respecto al diseño inicial (antes de medir, documentado):** la versión anterior de este documento fijaba ≥ 200 req/s con 100 usuarios esperando 0,5–1,5 s,
lo que es inalcanzable por construcción (como máximo ~100 req/s). Los objetivos numéricos no cambian; lo que cambia es el modelo de carga: cada usuario
mantiene una tasa fija (`constant_throughput`), de modo que 100 usuarios ofrecen exactamente la carga del objetivo.

## 3. Informe de rendimiento

`evaluate.py` compara cada escalón con los objetivos y produce `evaluation.md/json`; `charts.py` dibuja latencia p95 y throughput en el tiempo por escalón y p95/throughput frente a usuarios.
p95 y errores se evalúan en todos los escalones; el throughput solo en el de referencia (100 usuarios). Un objetivo no medido es error, nunca cumplimiento.
La tabla completa, las gráficas, el cuello de botella y las acciones propuestas están en [INFORME.md](../evidencias/hu-15/INFORME.md).

## 4. OWASP ZAP baseline

```bash
security/zap/run-zap-baseline.sh --target http://web:8080 --network <red del stack> --env local
```

- Imagen `ghcr.io/zaproxy/zaproxy:stable` fijada por digest en [security/policy.env](../../security/policy.env); contenedor sin root; los informes salen por flujo (sirve con Docker remoto/DinD).
- Reglas: [security/zap/zap-baseline.conf](../../security/zap/zap-baseline.conf), sin excepciones: toda regla pasiva conserva su nivel y toda alerta se informa.
- Informes: `zap-report.html` (legible), `zap-report.json` (máquina), `zap-report.md` y `gate.txt` (resumen de la compuerta).
- Rechaza `--env prod`: solo local, dev o stage.

### 4.1 Integración en Jenkins

Paso de la Shared Library [cgZapBaseline](../../jenkins/vars/cgZapBaseline.groovy) y [cgPerformanceTest](../../jenkins/vars/cgPerformanceTest.groovy), y el parche
[security/jenkins/Jenkinsfile-hu15-stages.patch](../../security/jenkins/Jenkinsfile-hu15-stages.patch), que añade las etapas «ZAP baseline dev» y «Performance dev» **después de «E2E dev»
y antes de desplegar a stage**, y los parámetros `ZAP_GATE`, `RUN_ZAP`, `RUN_PERF`, `PERF_CREDENTIALS_ID`, `PERF_STEPS`, `PERF_DURATION` y `ADV_DOCKER_NETWORK`.
El parche se verifica con `git apply --check` (solo y encadenado después del de HU-14), la sintaxis Groovy se comprueba con un intérprete real y la auditoría de credenciales de HU-14
da 0 violaciones con ambos parches (la credencial del usuario de prueba pasa solo por `withCredentials`). **No está aplicado al Jenkinsfile.**

### 4.2 Política de bloqueo

Umbral en `ZAP_BLOCK_RISK` ([security/policy.env](../../security/policy.env)); acordado inicialmente: **High**.

| Riesgo | Acción |
|---|---|
| Alta (High) | El build falla (`ZAP_GATE=enforce`) y no se promociona a stage; se corrige o se registra una excepción |
| Media (Medium) | Se informa y se planifica la corrección; **bloquea si se baja el umbral a Medium** |
| Baja / informativa | Se informa; no bloquea |

La compuerta (`security/zap/evaluate-zap.sh`) devuelve 0, 1 o 2; 2 (informe ausente, no ZAP o sin sitio analizado) siempre falla: un análisis que no se hizo no es un pase. 13 pruebas
(`security/tests/test-zap-gate.sh`). Se comprobó además con el informe real: pasa con umbral High y **bloquea con umbral Medium**
([evidencia](../evidencias/hu-15/zap/gate-umbral-medium.txt)).

ZAP baseline es **pasivo**: no envía ataques ni sustituye una prueba de penetración. Solo ve lo que el rastreador de 1 minuto alcanza.

## 5. Informe consolidado de calidad

[docs/evidencias/hu-15/INFORME.md](../evidencias/hu-15/INFORME.md) reúne: alcance y objetivos, ambiente y versión probada, rendimiento (tabla y gráficas), ZAP (conteo por severidad),
cobertura (JaCoCo), pruebas ejecutadas (unitarias e integración), comparación con los objetivos con veredicto, hallazgos con causa y acción, y limitaciones.
`tests/performance/consolidate.py` genera las tablas a partir de los resultados, sin inventar datos ausentes.

## 6. Matriz E2.7

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Escenario Locust de validación de acceso | **Hecho** | [access_validation.py](../../tests/performance/access_validation.py) |
| 2 | Escenario Locust de envío de cuestionarios | **Hecho** | [survey_submission.py](../../tests/performance/survey_submission.py) |
| 3 | Usuarios, duración y tasa configurables | **Hecho** | `run-perf.sh --steps/--duration/--spawn-rate`, variables `PERF_*` |
| 4 | Objetivos definidos antes de ejecutar | **Hecho** | §1 y `targets.json` |
| 5 | p95, throughput y errores | **Hecho** (ejecutado en local) | [INFORME.md](../evidencias/hu-15/INFORME.md) |
| 6 | Informe comparativo con los objetivos | **Hecho** | `evaluation.md` y INFORME.md |
| 7 | Ambiente controlado, no prod | **Hecho** | `PERF_TARGET_ENV` rechaza prod; pila local aislada |
| 8 | ZAP baseline sobre el cliente web | **Hecho** (ejecutado en local) | [zap-report.html](../evidencias/hu-15/zap/zap-report.html) |
| 9 | ZAP integrado en Jenkins | **Preparado, no aplicado** | parche + `cgZapBaseline`; falta aplicarlo (HU-11) |
| 10 | Informe de vulnerabilidades y riesgo | **Hecho** | `zap-report.*` y §Seguridad del INFORME |
| 11 | Bloqueo por umbral | **Hecho y probado** | `evaluate-zap.sh`, 13 pruebas, informe real con umbral High y Medium |
| 12 | Informe consolidado | **Hecho** | INFORME.md |
| 13 | Evidencia de integración con Jenkins | **Parcial**: parche verificado; sin ejecución en un Jenkins | Falta HU-11 |

## 7. Dependencias

| Necesidad | Historia | Estado |
|---|---|---|
| Ambiente dev/stage estable y accesible para ejecutar contra él | HU-10/HU-09 | **Esperar**: se ejecutó en una pila local aislada |
| Usuario y QR de prueba | HU-04/HU-05 | Usado el usuario sembrado por la migración V3; ver limitación del usuario único |
| Métricas de latencia/errores | HU-13 | Disponibles (Micrometer); no se contrastaron con Prometheus en esta ejecución |
| Pipeline con las etapas | HU-11 | **Esperar**: parche listo para aplicar |
| Umbral de seguridad acordado | HU-14 | Hecho: High, configurable en `security/policy.env` |
| Credencial `perf-test-user` en Jenkins | HU-01/HU-11 | **Pendiente de crear** en el Jenkins real |

## 8. Riesgos

| Riesgo | Mitigación |
|---|---|
| La prueba tumba el entorno compartido | Solo local/dev/stage; avisar al equipo; `RUN_PERF` desactivado por defecto |
| Datos sintéticos poco realistas | `anonymousId` aleatorio, respuestas `NO`, un usuario de prueba; se documenta |
| ZAP reporta ruido por cabeceras ausentes | Se priorizan High/Medium; el resto se informa sin bloquear |
| El ambiente pequeño satura antes de 100 usuarios | Se reporta el límite real y la causa; no se oculta ni se cambia el objetivo |
| Se cambian los objetivos después de medir | Congelados en `targets.json` y verificados por una prueba |

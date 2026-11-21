# Pruebas avanzadas de rendimiento y seguridad (HU-15 · E2.7)

**Documento:** consolidación para HU-17 (E2.9) sobre HU-15 (S2 · E2.7)
**Última actualización:** 2026-11-16
**Estado:** **Pendiente de implementación.** Hoy existen pruebas unitarias, de integración y E2E de
humo; no hay Locust ni OWASP ZAP en el pipeline. Este documento define objetivos, escenarios y
evidencia para que HU-15 se ejecute sin improvisar.

> Resultados base de pruebas: [`../evidencias/hu-04/README.md`](../evidencias/hu-04/README.md).

## 1. Objetivos de rendimiento (declarados antes de medir)

| Flujo | Objetivo | Justificación |
|---|---|---|
| Validación de acceso (`gateway`) | p95 ≤ 300 ms · ≥ 200 req/s · errores < 1 % | Es el flujo de una puerta; debe responder antes de que la fila avance |
| Envío de cuestionario (`form`) | p95 ≤ 800 ms · ≥ 50 req/s · errores < 2 % | Escritura + evento Kafka; tolera más latencia que el acceso |
| Promoción (consumidor) | p95 ≤ 2 s por evento · lag < 100 | El recorrido del grafo es la operación más costosa |
| Sistema en conjunto | 100 usuarios concurrentes durante 5 min sin degradación | Escala de un campus pequeño |

**Regla:** si un objetivo no se cumple, se reporta el valor real y la causa; no se cambia el
objetivo después de medir.

## 2. Escenarios Locust

### 2.1 Estructura

```text
tests/performance/
├── locustfile.py
├── scenarios/
│   ├── access_validation.py
│   └── survey_submission.py
├── data/
│   └── users.csv            # datos sintéticos, sin PII
└── README.md
```

### 2.2 Escenario de validación de acceso

```python
from locust import HttpUser, task, between

class AccessUser(HttpUser):
    wait_time = between(0.5, 1.5)

    def on_start(self):
        # Token de un usuario de prueba creado por el seed; nunca credenciales reales
        self.qr = self.environment.parsed_options.qr_token

    @task
    def validate_access(self):
        self.client.post("/api/v1/gateway/validate", json={"qrToken": self.qr},
                         name="POST /gateway/validate")
```

### 2.3 Escenario de envío de cuestionario

```python
class SurveyUser(HttpUser):
    wait_time = between(2, 5)

    @task
    def submit_survey(self):
        payload = {"anonymousId": self.environment.parsed_options.anonymous_id,
                   "hasSymptoms": True, "symptoms": ["fever"]}
        self.client.post("/api/v1/forms/survey", json=payload,
                         name="POST /forms/survey")
```

### 2.4 Parámetros

| Parámetro | Valor de la prueba |
|---|---|
| Usuarios concurrentes | 10, 50, 100 (escalonado) |
| Duración | 5 min por escalón |
| Ramp-up | 10 usuarios/s |
| Entorno | dev o stage aislado; **nunca prod** |
| Datos | Sintéticos; sin nombres reales |

```bash
locust -f tests/performance/locustfile.py \
  --host http://<host-dev> \
  --users 100 --spawn-rate 10 --run-time 5m \
  --headless --csv results/access --html results/access.html
```

## 3. Informe de rendimiento

El informe debe incluir, por escenario:

| Métrica | Valor | Objetivo | Cumple |
|---|---|---|---|
| Latencia p50 | | — | — |
| Latencia p95 | | p95 declarado | Sí/No |
| Latencia p99 | | — | — |
| Throughput (req/s) | | declarado | Sí/No |
| Tasa de errores | | < 1–2 % | Sí/No |
| Usuarios concurrentes | | 100 | Sí/No |
| Duración | | 5 min | — |
| Cuello de botella identificado | CPU, memoria, Neo4j, Kafka o pool de conexiones | — | — |
| Acción propuesta | índice, caché, réplica, ajuste de pool | — | — |

**Gráficas:** latencia vs tiempo, RPS vs usuarios, errores vs usuarios. Se adjuntan como PNG y se
enlazan en el informe.

## 4. OWASP ZAP baseline

### 4.1 Ejecución

```bash
docker run --rm -v "$PWD:/zap/wrk:rw" -t ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t http://<host-dev> -r zap-report.html -J zap-report.json
```

### 4.2 Integración en Jenkins

```groovy
stage('OWASP ZAP baseline') {
  when { expression { params.RUN_ZAP } }
  steps {
    sh 'docker run --rm -v "$PWD:/zap/wrk:rw" ghcr.io/zaproxy/zaproxy:stable \
        zap-baseline.py -t $E2E_URL_DEV -r zap-report.html -J zap-report.json || true'
    archiveArtifacts artifacts: 'zap-report.*', allowEmptyArchive: false
    publishHTML target: [reportDir: '.', reportFiles: 'zap-report.html',
                         reportName: 'OWASP ZAP']
  }
}
```

### 4.3 Política de bloqueo

| Riesgo | Acción |
|---|---|
| Alta (High) | Falla el pipeline; se corrige o se acepta con justificación firmada |
| Media (Medium) | Reporta; se planifica corrección |
| Baja (Low) / informativa | Reporta; no bloquea |

ZAP baseline es pasivo: no sustituye una prueba de penetración. Se documenta esa limitación.

## 5. Informe consolidado de calidad

Un solo documento (`docs/evidencias/hu-15/INFORME.md`) con:

1. Alcance y objetivos.
2. Entorno y versión probada (commit + imagen).
3. Resultados de rendimiento (tabla + gráficas).
4. Resultados de ZAP (conteo por severidad + enlaces).
5. Cobertura de pruebas (JaCoCo, integración, E2E).
6. Comparación con los objetivos y veredicto.
7. Hallazgos, causas y acciones.
8. Limitaciones (entorno pequeño, datos sintéticos, ZAP pasivo).

## 6. Matriz E2.7

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Escenario Locust de validación de acceso | Pendiente | `scenarios/access_validation.py` |
| 2 | Escenario Locust de envío de cuestionarios | Pendiente | `scenarios/survey_submission.py` |
| 3 | Usuarios, duración y tasa configurables | Pendiente | CLI + README |
| 4 | Objetivos definidos antes de ejecutar | Listo | §1 |
| 5 | p95, throughput y errores | Pendiente | Informe |
| 6 | Informe comparativo | Pendiente | Informe |
| 7 | Ambiente controlado, no prod | Pendiente | URL de dev/stage |
| 8 | ZAP baseline sobre el cliente web | Pendiente | `zap-report.html` |
| 9 | ZAP integrado en Jenkins | Pendiente | Stage |
| 10 | Informe de vulnerabilidades y riesgo | Pendiente | Informe |
| 11 | Bloqueo por umbral | Pendiente | §4.3 |
| 12 | Informe consolidado | Pendiente | `INFORME.md` |

## 7. Dependencias

| Necesidad | Historia | Si falta |
|---|---|---|
| Entorno dev/stage estable | HU-10/HU-11 | No hay URL ni datos para la prueba |
| Usuario y QR de prueba | HU-04/HU-05 | El escenario no puede autenticarse |
| Métricas de latencia/errores | HU-13 | El informe no se puede contrastar con Prometheus |
| Pipeline con stage | HU-11 | ZAP no se ejecuta automáticamente |
| Umbral de seguridad acordado | HU-14 | No hay política de bloqueo común |

## 8. Riesgos

| Riesgo | Mitigación |
|---|---|
| La prueba tumba el entorno compartido | Ejecutar en dev aislado y avisar al equipo |
| Datos sintéticos poco realistas | Generar usuarios y QR con el seed; documentar |
| ZAP reporta ruido por faltantes de cabeceras | Priorizar High/Medium y justificar el resto |
| El clúster de 2 vCPU satura antes de 100 usuarios | Reportar el límite real y proponer escalado; no ocultar |
| Se cambian los objetivos después de medir | Objetivos congelados en este documento antes de la primera ejecución |

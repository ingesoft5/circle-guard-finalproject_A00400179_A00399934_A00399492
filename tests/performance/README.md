# Pruebas de rendimiento con Locust (HU-15 · E2.7)

Dos escenarios sobre los flujos críticos, con objetivos declarados antes de medir ([targets.json](targets.json), origen: [docs/operacion/pruebas-avanzadas.md](../../docs/operacion/pruebas-avanzadas.md) §1).

| Archivo | Qué hace |
|---|---|
| [access_validation.py](access_validation.py) | Validación de acceso: inicia sesión una vez (preparación), y en bucle genera un QR (`GET /auth/api/v1/auth/qr/generate`) y lo valida (`POST /gateway/api/v1/gate/validate`) |
| [survey_submission.py](survey_submission.py) | Envío de cuestionario: carga el cuestionario activo y envía la encuesta (`POST /form/api/v1/surveys`) con datos sintéticos |
| [locustfile.py](locustfile.py) | Punto de entrada: `AccessValidationUser` y `SurveySubmissionUser` |
| [run-perf.sh](run-perf.sh) | Ejecuta los escalones en un contenedor de Locust fijado por digest, dibuja las gráficas y compara con los objetivos |
| [evaluate.py](evaluate.py), [charts.py](charts.py), [consolidate.py](consolidate.py) | Evaluación contra objetivos, gráficas SVG e informe consolidado (solo biblioteca estándar) |

## Configuración (todo es configurable, nada está fijo)

| Qué | Cómo | Por defecto |
|---|---|---|
| Usuarios concurrentes | `--steps "10 50 100"` (un escalón por valor) | 10 50 100 |
| Duración de cada escalón | `--duration 5m` | 5m |
| Tasa de generación de usuarios | `--spawn-rate 10` (usuarios por segundo) | 10 |
| Tasa de solicitudes por usuario | `PERF_ACCESS_RPS_PER_USER`, `PERF_SURVEY_RPS_PER_USER` | 2 y 0,5 (con 100 usuarios: 200 y 50 solicitudes/s ofrecidas) |
| Ambiente | `PERF_TARGET_ENV` = `local`, `dev` o `stage`. **Cualquier otro valor (prod) se rechaza** | obligatorio |
| Usuario de prueba | `PERF_USERNAME`, `PERF_PASSWORD` (entorno; no se escriben en ningún archivo) | obligatorio para acceso |

```bash
export PERF_TARGET_ENV=local PERF_USERNAME=<usuario de prueba>
read -rs -p "Contraseña del usuario de prueba: " PERF_PASSWORD; export PERF_PASSWORD   # sin eco, no se guarda
tests/performance/run-perf.sh --network <red de Docker del stack> --host http://web:8080            # 10/50/100 usuarios x 5 min, ambos escenarios
tests/performance/run-perf.sh --scenario survey --steps "10" --duration 30s --host http://web:8080  # prueba rápida
tests/performance/run-perf.sh --enforce ...                                                         # exit 1 si un objetivo no se cumple
```

Salida en `tests/performance/results/<fecha>/` (no versionada): CSV y HTML de Locust por escalón, `charts/*.svg`, `evaluation.md` y `evaluation.json`.

## Cómo se evalúa

- p95 y tasa de errores se comprueban en **todos** los escalones; el throughput solo en el escalón de referencia (100 usuarios), porque en los menores la carga ofrecida es menor que el objetivo por diseño.
- Un objetivo que no se midió (falta el escalón de referencia) es **error (código 2)**, nunca un cumplimiento.
- Los objetivos no se cambian después de medir: si no se cumplen, se informa el valor real y la causa.

## Pruebas del evaluador

`python3 tests/performance/tests/test_evaluate.py` (14 pruebas, sin Locust, Docker ni red) o `security/run-tests.sh`.

## Limitaciones

El usuario de prueba es uno solo (el sembrado por la migración V3); la validación de acceso usa el mismo `anonymousId` para todos los usuarios virtuales. Los envíos de cuestionario responden siempre NO para no cambiar el estado de salud de nadie. Los resultados dependen de los recursos del ambiente probado (ver el informe).

| Solicitud | Usuarios | Peticiones | p50 (ms) | p95 (ms) | Objetivo p95 | Throughput (req/s) | Objetivo | Errores (%) | Objetivo | Veredicto |
|---|---|---|---|---|---|---|---|---|---|---|
| POST /gateway/gate/validate | 10 | 304 | 43 | 150 | ≤ 300 | 11.0 | ≥ 200 | 80.26 | ≤ 1.0 | p95 cumple · throughput n/a · errores NO cumple |
| GET /auth/qr/generate (informativa) | 10 | 306 | 170 | 540 | — | 11.1 | — | 0.00 | — | — |
| POST /form/surveys | 10 | 140 | 510 | 1200 | ≤ 800 | 5.1 | ≥ 50 | 0.00 | ≤ 2.0 | p95 NO cumple · throughput n/a · errores cumple |
| GET /form/questionnaires/active (informativa) | 10 | 140 | 320 | 1100 | — | 5.1 | — | 0.00 | — | — |

Veredicto por objetivo (en el escalón de referencia de 100 usuarios):

- **POST /gateway/gate/validate**: NOT MEASURED
- **POST /form/surveys**: NOT MEASURED

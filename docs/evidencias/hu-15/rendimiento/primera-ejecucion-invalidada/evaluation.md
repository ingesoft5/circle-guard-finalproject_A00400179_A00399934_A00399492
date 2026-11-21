| Solicitud | Usuarios | Peticiones | p50 (ms) | p95 (ms) | Objetivo p95 | Throughput (req/s) | Objetivo | Errores (%) | Objetivo | Veredicto |
|---|---|---|---|---|---|---|---|---|---|---|
| POST /gateway/gate/validate | 100 | 19910 | 48 | 260 | ≤ 300 | 67.3 | ≥ 200 | 0.00 | ≤ 1.0 | p95 cumple · throughput NO cumple · errores cumple |
| GET /auth/qr/generate (informativa) | 100 | 19911 | 180 | 860 | — | 67.3 | — | 0.00 | — | — |
| POST /gateway/gate/validate | 10 | 5672 | 19 | 110 | ≤ 300 | 19.1 | ≥ 200 | 0.00 | ≤ 1.0 | p95 cumple · throughput n/a · errores cumple |
| GET /auth/qr/generate (informativa) | 10 | 5672 | 24 | 270 | — | 19.1 | — | 0.00 | — | — |
| POST /gateway/gate/validate | 50 | 16969 | 36 | 180 | ≤ 300 | 57.3 | ≥ 200 | 0.00 | ≤ 1.0 | p95 cumple · throughput n/a · errores cumple |
| GET /auth/qr/generate (informativa) | 50 | 16972 | 160 | 830 | — | 57.3 | — | 0.00 | — | — |
| POST /form/surveys | 100 | 12729 | 480 | 2200 | ≤ 800 | 43.8 | ≥ 50 | 0.00 | ≤ 2.0 | p95 NO cumple · throughput NO cumple · errores cumple |
| GET /form/questionnaires/active (informativa) | 100 | 12743 | 410 | 2200 | — | 43.8 | — | 0.00 | — | — |
| POST /form/surveys | 10 | 1470 | 110 | 600 | ≤ 800 | 5.0 | ≥ 50 | 0.00 | ≤ 2.0 | p95 cumple · throughput n/a · errores cumple |
| GET /form/questionnaires/active (informativa) | 10 | 1470 | 34 | 310 | — | 5.0 | — | 0.00 | — | — |
| POST /form/surveys | 50 | 7030 | 280 | 1100 | ≤ 800 | 24.2 | ≥ 50 | 0.00 | ≤ 2.0 | p95 NO cumple · throughput n/a · errores cumple |
| GET /form/questionnaires/active (informativa) | 50 | 7031 | 160 | 920 | — | 24.2 | — | 0.00 | — | — |

Veredicto por objetivo (en el escalón de referencia de 100 usuarios):

- **POST /gateway/gate/validate**: NOT MET
- **POST /form/surveys**: NOT MET

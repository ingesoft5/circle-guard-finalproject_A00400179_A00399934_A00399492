| Solicitud | Usuarios | Peticiones | p50 (ms) | p95 (ms) | Objetivo p95 | Throughput (req/s) | Objetivo | Errores (%) | Objetivo | Veredicto |
|---|---|---|---|---|---|---|---|---|---|---|
| POST /gateway/gate/validate | 100 | 24652 | 77 | 460 | ≤ 300 | 86.8 | ≥ 200 | 0.00 | ≤ 1.0 | p95 NO cumple · throughput NO cumple · errores cumple |
| GET /auth/qr/generate (informativa) | 100 | 24688 | 670 | 2500 | — | 86.9 | — | 0.00 | — | — |
| POST /gateway/gate/validate | 10 | 5195 | 21 | 200 | ≤ 300 | 18.2 | ≥ 200 | 0.00 | ≤ 1.0 | p95 cumple · throughput n/a · errores cumple |
| GET /auth/qr/generate (informativa) | 10 | 5197 | 27 | 450 | — | 18.2 | — | 0.00 | — | — |
| POST /gateway/gate/validate | 50 | 18752 | 57 | 400 | ≤ 300 | 65.9 | ≥ 200 | 0.00 | ≤ 1.0 | p95 NO cumple · throughput n/a · errores cumple |
| GET /auth/qr/generate (informativa) | 50 | 18757 | 350 | 1500 | — | 65.9 | — | 0.00 | — | — |
| POST /form/surveys | 100 | 11473 | 700 | 2700 | ≤ 800 | 40.6 | ≥ 50 | 0.00 | ≤ 2.0 | p95 NO cumple · throughput NO cumple · errores cumple |
| GET /form/questionnaires/active (informativa) | 100 | 11534 | 630 | 2700 | — | 40.8 | — | 0.00 | — | — |
| POST /form/surveys | 10 | 1411 | 47 | 620 | ≤ 800 | 5.0 | ≥ 50 | 0.00 | ≤ 2.0 | p95 cumple · throughput n/a · errores cumple |
| GET /form/questionnaires/active (informativa) | 10 | 1413 | 21 | 380 | — | 5.0 | — | 0.00 | — | — |
| POST /form/surveys | 50 | 6970 | 290 | 1100 | ≤ 800 | 24.6 | ≥ 50 | 0.00 | ≤ 2.0 | p95 NO cumple · throughput n/a · errores cumple |
| GET /form/questionnaires/active (informativa) | 50 | 6970 | 180 | 1000 | — | 24.6 | — | 0.00 | — | — |

Veredicto por objetivo (en el escalón de referencia de 100 usuarios):

- **POST /gateway/gate/validate**: NOT MET
- **POST /form/surveys**: NOT MET

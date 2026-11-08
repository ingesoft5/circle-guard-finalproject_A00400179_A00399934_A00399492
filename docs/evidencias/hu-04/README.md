# HU-04 · Pruebas unitarias y de integración · Evidencias

Rama: `HU04-Pruebas-unitarias-y-integracion`. Ejecución de referencia: build **#10** del job multibranch
`circleguard` en el Jenkins de AWS (resultado **SUCCESS**, 7 min 7 s, `RUN_SONAR=false`).

## Matriz criterio → evidencia

| Criterio de HU-04 | Resultado | Evidencia |
|---|---|---|
| Cobertura de líneas JaCoCo ≥ 60 % en auth, identity, promotion, form y gateway | auth 98,0 % · identity 98,1 % · promotion 90,9 % · form 97,9 % · gateway 100 % | `01-informe-jacoco/coverage-summary.md` y el HTML por servicio (`01-informe-jacoco/<servicio>/index.html`) |
| El gate falla el build si la cobertura baja de 60 % | `jacocoTestCoverageVerification` (LINE, BUNDLE) activo solo en esos 5 servicios | `build.gradle.kts` (raíz); línea base previa en `00-linea-base-cobertura.txt` |
| ≥ 3 pruebas de integración con Testcontainers | 5 pruebas cross-service + las `*IntegrationTest` de promotion, 0 fallos, 0 omitidas | `02-informe-integracion/cross-service/index.html` y `02-informe-integracion/junitResult-build10.xml` |
| Una prueba formulario → Kafka → promotion | IT-1, IT-1b, IT-2 (`FormToPromotionIntegrationTest`) | mismo informe de integración |
| Notificación a partir de un cambio de estado (promotion → Kafka → notification) | IT-3, IT-4 (`PromotionToNotificationIntegrationTest`) | mismo informe de integración |
| Reportes publicados por el pipeline | JUnit, Coverage (`recordCoverage`) y HTML Publisher (JaCoCo por servicio e integración) | `03-pipeline/consola-build10.txt` |
| Captura del pipeline | Etapas del build #10 en verde, 269 pruebas OK, cobertura y quality gate | `capturas/01` a `capturas/06` (ver tabla abajo) |

### Capturas (`capturas/`)

| Archivo | Qué demuestra |
|---|---|
| `01-jenkins-build10-resumen-cobertura.png` | Build #10 en verde, sin pruebas fallidas, cobertura 93,36 % de líneas (agregado) y quality gate: Success |
| `02-jenkins-build10-269-pruebas-ok.png` | 269 pruebas, todas pasan |
| `03-informe-integracion-testcontainers-5-ok.png` | Informe de integración: 5 pruebas (3 form → promotion, 2 promotion → notification), 0 fallos |
| `04-jenkins-pipeline-etapas-build10.png` | Stage View: etapas del #10 en verde (SonarQube y Publish omitidas) |
| `04b-jenkins-pipeline-historial-builds.png` | Continuación del Stage View: historial de builds anteriores |
| `05-jacoco-promotion-service.png` | Informe JaCoCo de promotion: 641 de 705 líneas cubiertas (90,9 %) |
| `06-jenkins-rama-tendencias.png` | Tendencias de pruebas y de cobertura de la rama |

## Qué se ejecutó

- Etapas del build #10: Checkout → Build → Unit tests and coverage → (SonarQube omitida) → Integration tests → Package → (Publish omitida).
- Integration tests ejecuta `integrationTest` en los servicios y `:tests:integration:integrationTest`.
  Los contenedores (Kafka, Postgres, Neo4j, Redis) se levantan en el Docker-in-Docker (`dind`) de Jenkins.
- Para validar sin depender de GitHub se usó un repositorio git desechable servido por HTTP dentro de la red
  interna de Jenkins, con la misma rama y el mismo contenido del árbol de trabajo. El flujo real
  (GitHub + `github-token`) requiere el push y el job multibranch contra el repositorio.

## Cómo repetir la captura del pipeline

1. Encender `ci` si está detenida: `bash infra/bootstrap-servers.sh --apply --approve ci`.
2. `bash infra/tunnel.sh jenkins` y abrir http://localhost:8080.
3. Job `circleguard` → rama `HU04-Pruebas-unitarias-y-integracion` → build #10: capturar la vista de etapas, la
   pestaña *Test Result*, *Coverage Report* y los enlaces «JaCoCo …» e «Integration tests (cross-service)».
4. Guardar las imágenes en `capturas/` y revisar con `bash infra/check-evidence.sh` (sin cuenta AWS ni IP completas).

## Limitaciones conocidas

- La etapa SonarQube no se validó: falta conectar Jenkins con la red de SonarQube y crear la credencial `sonar-token`
  (fuera de los criterios de HU-04). El nombre de la tarea se corrigió a `:services:sonar`.
- Defecto del producto detectado y **no corregido**: en `HealthStatusService.updateStatus` (promotion) la consulta
  Cypher no devuelve filas si el usuario no tiene contactos recientes o si el nuevo estado es ACTIVE, por lo que
  no se actualiza Redis ni se publica `promotion.status.changed`. Las pruebas IT-1/IT-2 lo documentan afirmando
  sobre el grafo (Neo4j).
- Corregido: `application.yml` de promotion y notification no declaraba el serializador JSON de Kafka.

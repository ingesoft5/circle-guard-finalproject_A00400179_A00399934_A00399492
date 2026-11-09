# Evidencias de HU-08 · Documentación y bitácora de IAG

Historia: «Como equipo, quiero documentar el proyecto para que pueda reproducirse y evaluarse».
Rúbrica relacionada: **P1.8** (1,0 %): «README que permite reproducir, diagramas claros y bitácora de IAG
completa con reflexión crítica».

## Matriz criterio → evidencia

| Criterio de aceptación | Estado | Dónde está |
|---|---|---|
| README operativo con instrucciones de reproducción | ✅ | [`README.md`](../../../README.md), sección «Inicio rápido»: cuatro recorridos (pruebas, ejecución local, imágenes con Compose y AWS), con prerrequisitos y resultados esperados |
| Diagrama de arquitectura | ✅ | [`docs/arquitectura/diagramas.md`](../../arquitectura/diagramas.md), diagramas 1 y 2 (arquitectura lógica y flujo de eventos); versión resumida en el README. Infraestructura: diagrama 5 y [`infra-ambientes.md`](../../arquitectura/infra-ambientes.md) |
| Diagrama del pipeline | ✅ | [`docs/arquitectura/diagramas.md`](../../arquitectura/diagramas.md), diagramas 3 (CI) y 4 (CD); detalle de etapas en [`pipeline-cd.md`](../../arquitectura/pipeline-cd.md) |
| Bitácora de IAG como anexo, con los prompts empleados | ✅ con lagunas declaradas | [`IAG_REGISTRO.md`](../../../IAG_REGISTRO.md) (anexo) y [`docs/iag/sesiones/`](../../iag/sesiones/) (prompts y respuestas). Reflexión crítica en la sección 5 del anexo |
| Evidencias: README, diagramas y bitácora en el repositorio | ✅ | Todos los archivos anteriores están versionados; índice general en [`docs/README.md`](../../README.md) |

## Qué se cambió

- `README.md`: reescrito como README general (en español). Corrige «Spring Boot 4» a 3.2.4, separa pruebas
  unitarias e integración y añade inicio rápido, mapa de evidencias y limitaciones.
- `docs/operacion/infraestructura-aws.md`: contiene, sin cambios de contenido, la guía de operación y
  demostración de HU-01 que estaba en el README raíz (solo se ajustaron los enlaces relativos).
- `docs/arquitectura/diagramas.md`: cinco diagramas Mermaid con la fuente de cada dato.
- `docs/README.md`: índice de toda la documentación.
- `IAG_REGISTRO.md` y `docs/iag/`: anexo, sesiones de HU-04 y HU-08, e índice actualizado.

## Cómo comprobarlo

1. Abra `README.md` en GitHub o en la vista previa de VS Code: las secciones y los diagramas deben dibujarse.
2. Siga la sección A del inicio rápido: `./gradlew test coverageSummary` debe terminar con
   `BUILD SUCCESSFUL` y la tabla de cobertura.
3. Compruebe que los enlaces relativos de los archivos nuevos resuelven (la verificación de esta HU está
   descrita abajo).

## Verificaciones realizadas

| Verificación | Resultado |
|---|---|
| Enlaces relativos de `README.md`, `docs/README.md`, `docs/arquitectura/diagramas.md`, `docs/operacion/infraestructura-aws.md`, `IAG_REGISTRO.md`, sesiones y esta carpeta | Sin enlaces rotos (script de comprobación sobre el árbol de trabajo) |
| Datos de los diagramas contra el código | Puertos (`application.yml`), tópicos de Kafka (`HealthSurveyService`, `HealthStatusService`, `@KafkaListener`), clientes REST (`IdentityClient`, `PromotionClient`) y Redis (`QrValidationService`) |
| Versión de Spring Boot | `build.gradle.kts` (3.2.4) |
| Secretos en la documentación nueva | `bash infra/check-evidence.sh docs/evidencias/hu-08` |

## Limitaciones

- Los diagramas Mermaid **no se renderizaron** durante la elaboración: se escribieron con la sintaxis de los
  diagramas ya existentes en el repositorio. Revíselos en la vista previa de GitHub o de VS Code.
- La bitácora no tiene sesiones de HU-01, HU-03 y HU-09 (no se conservaron sus prompts); está declarado en
  la sección 3 de `IAG_REGISTRO.md` y debe completarse si el equipo usó IA en ellas.
- El vídeo de la rúbrica E1.8 no es un criterio de aceptación de HU-08 y no se produjo.
- Los flags `RUN_SONAR` y `RUN_INTEGRATION` del `Jenkinsfile` están en `false` por defecto: el pipeline no ejecuta
  por sí solo las pruebas de integración ni SonarQube hasta activarlos (ver el README, sección «Pipeline de CI/CD»).

# Índice de la documentación

Punto de entrada a todo lo que no es código. El README general del proyecto está en
[`../README.md`](../README.md).

## Arquitectura y diseño

| Documento | Contenido |
|---|---|
| [`arquitectura/diagramas.md`](arquitectura/diagramas.md) | Diagramas de arquitectura lógica, flujo de eventos, pipeline de CI, pipeline de CD e infraestructura |
| [`arquitectura/infra-ambientes.md`](arquitectura/infra-ambientes.md) | Diagrama completo de la infraestructura en AWS y de los tres ambientes |
| [`arquitectura/pipeline-cd.md`](arquitectura/pipeline-cd.md) | Etapas del Jenkinsfile y mapeo de ramas |
| [`arquitectura/empaquetado-inmutable.md`](arquitectura/empaquetado-inmutable.md) | Imágenes inmutables y Compose por ambiente |
| [`arquitectura/registro-artefactos.md`](arquitectura/registro-artefactos.md) | Decisión del registro: CNCF Distribution en lugar de Nexus |

## Operación

| Documento | Contenido |
|---|---|
| [`operacion/infraestructura-aws.md`](operacion/infraestructura-aws.md) | Construir, destruir y reconstruir la plataforma; demostración guiada |
| [`../infra/README.md`](../infra/README.md) | Referencia técnica de los scripts de infraestructura |
| [`../deploy/README.md`](../deploy/README.md) | Imágenes y despliegue con Compose |
| [`../jenkins/README.md`](../jenkins/README.md) | Requisitos de Jenkins (plugins, credenciales, agente) |
| [`estrategia-branching.md`](estrategia-branching.md) | GitHub Flow y Conventional Commits |

## Evidencias por historia de usuario

| Historia | Carpeta |
|---|---|
| HU-01 · Infraestructura en la nube | [`evidencias/hu-01/`](evidencias/hu-01/README.md) |
| HU-02 · Imágenes Docker inmutables | [`evidencias/hu-02/`](evidencias/hu-02/README.md) |
| HU-04 · Pruebas unitarias y de integración | [`evidencias/hu-04/`](evidencias/hu-04/README.md) |
| HU-06 · Entrega continua y promoción | [`evidencias/hu-06/`](evidencias/hu-06/README.md) |
| HU-07 · Rollback, notificaciones y release notes | [`evidencias/hu-07/`](evidencias/hu-07/README.md) |
| HU-08 · Documentación y bitácora de IAG | [`evidencias/hu-08/`](evidencias/hu-08/README.md) |

## Bitácora de IA generativa

| Documento | Contenido |
|---|---|
| [`../IAG_REGISTRO.md`](../IAG_REGISTRO.md) | Anexo: índice, método de verificación y reflexión crítica |
| [`iag/README.md`](iag/README.md) | Reglas e índice de sesiones |
| [`iag/sesiones/`](iag/sesiones/) | Prompts literales y respuestas por historia |
| [`iag/decisiones.md`](iag/decisiones.md) | Decisiones D-01 a D-25 |

## Sustentación

| Documento | Contenido |
|---|---|
| [`sustentacion/GUION_SUSTENTACION_HU01_HU04.md`](sustentacion/GUION_SUSTENTACION_HU01_HU04.md) | Guion para exponer HU-01 y HU-04, con preguntas probables |

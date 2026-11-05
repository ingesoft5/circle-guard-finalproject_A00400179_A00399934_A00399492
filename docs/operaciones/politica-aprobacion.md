# Política de aprobación por tipo de cambio (HU-07)

Esta política aplica a cambios en código, imágenes, Compose, pipeline e infraestructura. El
pipeline de Jenkins exige la aprobación manual de `prod`; esta política define **quién** debe
aprobar antes de llegar allí.

## Tipos de cambio

| Tipo | Ejemplos | Aprobadores mínimos | Evidencia obligatoria |
|---|---|---|---|
| **Estándar** | Documentación, textos, configuración no funcional, dependencias de desarrollo | 1 revisor | PR revisado; pipeline verde o `UNSTABLE` justificado |
| **Normal** | Código de servicios, Dockerfiles, Compose, scripts de `deploy/`, Jenkinsfile | 1 revisor + responsable técnico | PR, tests, E2E dev/stage, escaneo de secretos |
| **Mayor** | Cambio de esquema/DB, breaking change, seguridad/privacidad, cambio de registro o de topología | 2 revisores + responsable técnico | RFC, ADR, plan de migración, rollback probado, ventana |
| **Emergencia** | Hotfix de seguridad o caída en prod | Responsable de incidente + responsable técnico | Ticket de incidente, rollback listo, postmortem ≤ 24 h |

## Reglas

1. **Nadie aprueba su propio cambio** en Normal, Mayor o Emergencia.
2. **Prod** siempre requiere el `input` del pipeline (usuario `admin` en Jenkins) y la aprobación
   previa según el tipo.
3. **Stage** solo se promueve si el E2E de dev pasó; **prod** solo si el E2E de stage pasó.
4. Un cambio **Mayor** no se despliega el mismo día de la aprobación: requiere ventana y plan de
   rollback verificado.
5. Una **Emergencia** puede saltar la ventana, pero no el rollback: se registra la versión anterior
   y se ejecuta `deploy/rollback.sh` si falla.
6. Todo cambio Normal/Mayor debe incluir la plantilla de
   [`solicitud-cambio.md`](solicitud-cambio.md).
7. Las aprobaciones se registran en el PR y en el historial de Jenkins; no se aceptan aprobaciones
   verbales.
8. El pipeline deja `UNSTABLE` si los tests base fallan; un cambio no puede pasar a **Mayor** ni a
   **prod** con fallos no justificados.

## Flujo

```text
RFC -> PR -> revisión -> pipeline (build/test) -> E2E dev -> stage -> E2E stage
    -> aprobación según tipo -> input prod -> despliegue -> tag + release notes
```

## Responsables

| Rol | Responsabilidad |
|---|---|
| Revisor técnico | Calidad, tests, seguridad básica, rollback |
| Responsable técnico | Arquitectura, riesgos, aprobación de stage/prod |
| Responsable de despliegue | Ejecuta/valida la ventana y el rollback |
| Responsable de incidente | Emergencias y postmortem |

Los nombres concretos se mantienen en el tablero ágil del equipo para no versionar datos
personales.

# Solicitud de cambio (RFC)

> Plantilla obligatoria para cambios que afecten `dev`, `stage`, `prod`, las imágenes o el
> pipeline. Copiar en el PR o en el ticket del tablero. Un cambio sin esta información no se
> aprueba.

## 1. Identificación

| Campo | Valor |
|---|---|
| Título | |
| Solicitante | |
| Fecha | |
| Historia / issue | |
| Rama / PR | |
| Tipo de cambio | Estándar / Normal / Emergencia / Mayor |
| Ambientes afectados | dev / stage / prod / todos |
| Servicios afectados | |

## 2. Descripción

- **Qué cambia:**
- **Por qué:**
- **Alcance (incluye):**
- **Fuera de alcance:**

## 3. Riesgo y reversibilidad

| Pregunta | Respuesta |
|---|---|
| ¿Rompe compatibilidad? | |
| ¿Cambia esquema/DB? | |
| ¿Requiere migración de datos? | |
| ¿Afecta seguridad o privacidad? | |
| ¿Cómo se detecta un fallo? | |
| ¿Rollback? (versión anterior) | |
| ¿Ventana de despliegue? | |

## 4. Validación

- [ ] Tests unitarios / integración ejecutados.
- [ ] E2E en dev.
- [ ] E2E en stage.
- [ ] `./infra/scan-secrets.sh` en PASS.
- [ ] Evidencias adjuntas (pipeline, logs, capturas).

## 5. Aprobaciones

| Rol | Nombre | Fecha | Decisión |
|---|---|---|---|
| Revisor técnico | | | |
| Responsable de despliegue | | | |
| Aprobación prod (`input`) | | | |

## 6. Despliegue y rollback

- **Versión a desplegar:**
- **Comando:** `./deploy/deploy.sh <env> <version>`
- **Rollback:** `./deploy/rollback.sh <env> <version-anterior>`
- **Notificación:** Discord/Slack del pipeline.
- **Responsable de la ventana:**

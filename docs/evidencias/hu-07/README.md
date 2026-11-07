# Evidencias de HU-07 · Rollback, notificaciones y release notes

**Estado: mecanismos implementados; evidencias pendientes de una ejecución real.**

## Matriz de criterios

| Criterio | Implementación | Evidencia |
|---|---|---|
| Rollback a una versión anterior, verificado | `deploy/rollback.sh <env> <version>`; valida imágenes y redespliega | `01-rollback.txt` + `09-traceability.json` |
| Notificación automática de fallos | `deploy/notify.sh` (Discord/Slack) en `post` de Jenkins | `02-notification.png` |
| Plantilla de solicitud de cambio | `docs/operaciones/solicitud-cambio.md` | Archivo versionado |
| Política de aprobación por tipo | `docs/operaciones/politica-aprobacion.md` | Archivo versionado |
| Release notes desde commits/PR | `deploy/release-notes.sh` + `CHANGELOG.md` | `03-release-notes.md` |
| Esquema de etiquetado de releases | `vMAJOR.MINOR.PATCH` en `deploy/tag-release.sh` | `04-tag.txt` |

## Evidencias a generar

| Archivo | Cómo |
|---|---|
| `01-rollback.txt` | `IMAGE_REGISTRY=... ./deploy/rollback.sh dev <version-anterior>` |
| `02-notification.png` | Captura del mensaje de fallo en Discord/Slack |
| `03-release-notes.md` | `docs/release-notes/v1.0.0.md` y `CHANGELOG.md` |
| `04-tag.txt` | `git tag -l`, `git show v1.0.0` |
| `05-politica.md` | Copia/enlace de la política y la plantilla |

## Rollback

```bash
# Ver la versión actual
./deploy/current-version.sh dev

# Volver a la versión anterior publicada
IMAGE_REGISTRY=localhost:5000 ./deploy/rollback.sh dev 0.9.0

# Verificar el registro
cat deploy/releases/dev.json
```

El script:

1. Rechaza la versión actual.
2. Verifica las 9 imágenes en el registro.
3. Redespliega con `event=rollback`.
4. Notifica y deja la trazabilidad en `deploy/releases/`.

## Notificaciones

```bash
DISCORD_WEBHOOK_URL=... ./deploy/notify.sh failure dev 1.0.0 "Fallo simulado"
```

Sin webhook configurado, el script informa y termina en 0: una notificación ausente no debe
marcar un despliegue como fallido.

## Release notes

```bash
./deploy/release-notes.sh 1.0.0
cat docs/release-notes/v1.0.0.md
head -40 CHANGELOG.md
```

El generador agrupa `feat`, `fix`, `perf` y otros, convierte `(#123)` en enlaces al PR y actualiza
`CHANGELOG.md` sin duplicar la versión.

## Pendiente

- Ejecutar un rollback real en dev o stage con dos versiones publicadas.
- Capturar la notificación de un fallo real del pipeline.
- Publicar las notas generadas por Jenkins en el PR/release de GitHub.

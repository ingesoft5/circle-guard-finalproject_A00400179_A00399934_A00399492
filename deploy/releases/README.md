# Trazabilidad de versiones por ambiente

Los scripts `deploy/deploy.sh` y `deploy/rollback.sh` escriben aquí:

| Archivo | Contenido |
|---|---|
| `<env>.json` | Última versión desplegada en el ambiente (`dev`, `stage` o `prod`) |
| `history.tsv` | Historial append-only de deploys y rollbacks |

Ejemplo de `<env>.json`:

```json
{
  "environment": "dev",
  "version": "1.0.0",
  "commit": "abc1234",
  "deployed_at": "2026-11-05T12:00:00Z",
  "deployed_by": "jenkins",
  "event": "deploy"
}
```

- No editar a mano: los scripts validan semver, ambiente y evento.
- `history.tsv` tiene encabezado y columnas separadas por tabulador.
- El pipeline archiva ambos como artefactos de Jenkins.
- Además, `record-release.sh` escribe una copia persistente en `CG_RELEASES_DIR`
  (por defecto `$HOME/.circleguard/releases`), para que la trazabilidad sobreviva a la limpieza
  del workspace de Jenkins. `current-version.sh` consulta primero esa copia.
- Si se requiere una fuente de verdad en Git, el equipo puede hacer que Jenkins commitee estos
  archivos; para HU-06 se archivan y se adjuntan a la evidencia.

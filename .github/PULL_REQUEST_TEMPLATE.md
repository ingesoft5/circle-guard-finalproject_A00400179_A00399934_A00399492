## Resumen

<!-- Qué cambia y por qué, en 2-4 líneas. -->

## Historia / issue

- HU:
- Tipo de cambio (Estándar / Normal / Mayor / Emergencia):
- Ambientes afectados:

## Checklist

- [ ] La plantilla `docs/operaciones/solicitud-cambio.md` está completa (si aplica).
- [ ] `./gradlew test` ejecutado; fallos base justificados.
- [ ] `./deploy/build-images.sh <version>` y `./deploy/verify-images.sh <version>` OK.
- [ ] E2E de dev y stage ejecutados (o justificación).
- [ ] `./infra/scan-secrets.sh` en PASS.
- [ ] Rollback identificado: versión anterior y comando.
- [ ] Sin secretos en el diff ni en las capturas.
- [ ] La documentación/IAG se actualizó si se tomó una decisión.

## Evidencias

<!-- Enlaces a Jenkins, capturas, docs/evidencias/... -->

## Rollback

```bash
./deploy/rollback.sh <env> <version-anterior>
```

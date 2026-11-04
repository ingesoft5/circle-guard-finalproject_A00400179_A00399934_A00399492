# Evidencias de las pruebas de HU-01 en AWS

Salidas **reales y enmascaradas** de las pruebas en AWS. Cada prueba requiere una autorización y una
sesión con MFA del responsable de la cuenta.

| Subcarpeta | Prueba | Estado | Criterios | Resultado |
|---|---|---|---|---|
| [`idempotencia/`](idempotencia/README.md) | `bash infra/test-idempotency.sh --apply --approve ci,nexus` (commit `3afca6f`) | **Ejecutada el 2026-11-03** | C1, C3 | `RESULTADO: IDEMPOTENTE`. Detalle debajo de la tabla |
| [`aislamiento/`](aislamiento/README.md) | `bash infra/test-isolation.sh --apply --phases=1,2,3` y `--phases=4,5` | **Ejecutada el 2026-11-03/04** (23:41-00:20 UTC) | C2, C3 (`bootstrap-env.sh`) | `RESULTADO: AISLAMIENTO VERIFICADO CON TRÁFICO` en las dos sesiones; `bootstrap-env.sh` idempotente en los tres ambientes |
| [`ensayo-nivel1/`](ensayo-nivel1/README.md) | Ensayo de [`../ensayo-reconstruccion/`](../ensayo-reconstruccion/README.md) por otro integrante | **Pendiente** (otro integrante) | C5 | — |

Resultado de la prueba de idempotencia:
- 2.ª ejecución con `created=0 updated=0 unchanged=137`.
- `diff S1 S2` y `diff S2 S3` vacíos.
- Publicación y descarga desde `ci` y desde Jenkins.
- Recuperación tras reiniciar los contenedores.
- `verify-infra.sh --health`: 25 PASS, 0 FAIL, 1 PENDING. El PENDING es Nexus sin EULA, que ya es
  una decisión definitiva; el código actual lo informa como PASS
  ([nota](idempotencia/README.md)).
- Instancias detenidas al terminar.

Las copias `masked/` llegan sin el número de cuenta, sin el último octeto de las IP públicas y sin
los hashes de archivos secretos. Cómo versionar una de ellas:

```bash
src=~/.circleguard/isolation/<marca>/masked                 # ensayo: ~/.circleguard/idempotency/<marca>/masked
dst=docs/evidencias/hu-01/aws/aislamiento/fases-1-3        # o fases-4-5, o ensayo-nivel1/idempotencia
mkdir -p "$dst"
for f in "$src"/*.txt; do
  sed -E 's#/home/[a-z_][a-z0-9_-]*#~#g; s/[[:space:]]+$//' "$f" > "$dst/${f##*/}"
done
bash infra/check-evidence.sh "$dst"                          # debe terminar con hallazgos=0
```

`check-evidence.sh` es de solo lectura y no llama a AWS. Cuenta, sin mostrarlos:
- el número de cuenta y las IP públicas completas;
- claves e identificadores de AWS, y llaves privadas;
- asignaciones de secretos y hashes de archivos secretos;
- rutas personales y valores de los secretos locales.

Así se comprobó la carpeta `idempotencia/`: 0 en todas las categorías.

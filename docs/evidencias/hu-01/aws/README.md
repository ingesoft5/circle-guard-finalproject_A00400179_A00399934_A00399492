# Evidencias de AWS pendientes de HU-01

Carpeta preparada el 2026-11-03 para las salidas **reales y enmascaradas** de las pruebas en AWS.
**Todavía no contiene ninguna**: cada prueba requiere una autorización y una sesión con MFA.

| Subcarpeta | Prueba | Copiar desde | Criterios | Se considera PASS si |
|---|---|---|---|---|
| `idempotencia/` | `bash infra/test-idempotency.sh --apply --approve ci,nexus` | `~/.circleguard/idempotency/<marca>/masked/*` | C1, C3 (y C5 si la ejecuta otro integrante) | `report.txt` termina en `RESULTADO: IDEMPOTENTE` y `registry.txt` contiene la línea PASS de Jenkins |
| `aislamiento/` | `bash infra/test-isolation.sh --apply --phases=1,2,3` y `--phases=4,5` | `~/.circleguard/isolation/<marca>/masked/*` (las dos marcas) | C2 | Las cinco fases en PASS y `instancias detenidas al terminar` |
| `ensayo-nivel1/` | Ensayo de [`../ensayo-reconstruccion/`](../ensayo-reconstruccion/README.md) | Lo que entrega el otro integrante | C5 | Los criterios de ese documento |

Las copias `masked/` ya llegan sin el número de cuenta, sin el último octeto de las IP públicas y
sin los hashes de archivos secretos. Aun así, revíselas antes de versionarlas.

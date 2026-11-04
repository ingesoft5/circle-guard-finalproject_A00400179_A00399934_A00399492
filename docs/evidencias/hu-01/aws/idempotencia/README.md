# Prueba de idempotencia integral en AWS · 2026-11-03 (copias enmascaradas)

Ejecutada por el responsable de la cuenta con `bash infra/test-idempotency.sh --apply --approve ci,nexus`
sobre el commit `3afca6f`. Resultado: **IDEMPOTENTE (todas las comprobaciones en PASS)**.

Copias de `~/.circleguard/idempotency/20261103T202052Z/masked/` (generadas por `cg_mask_evidence`): sin número de
cuenta, con el último octeto de las IP públicas oculto y sin los hashes de `.env`, htpasswd ni llaves. Al copiarlas,
las rutas de `$HOME` se sustituyeron por `~` y se quitaron los espacios finales.

**`report.txt` y `stop.txt` se enmascararon de nuevo desde los originales**, con la misma función:
- **Por qué:** la prueba generaba `masked/` antes de escribir sus 4 últimas líneas en `report.txt`:
  la ruta de `masked/`, `RESULTADO: IDEMPOTENTE`, la parada de las instancias y la duración.
  Además, no copiaba `stop.txt`.
- **Corrección:** `test-idempotency.sh` hace ahora las copias al final, después de la parada
  ([prueba local](../../auditoria/20261103T230549Z-orden-evidencias-local.txt)).
- **Contenido:** las 20 primeras líneas son idénticas a la copia anterior. La duración, 1889 s, se
  mide desde la confirmación hasta la parada; según el registro de costos, los servidores
  estuvieron encendidos ≈ 26 min (20:27-20:53 UTC).

Comprobado antes de versionar:
0 apariciones del número de cuenta, de IP públicas, de claves o de valores de secretos
(`bash infra/check-evidence.sh docs/evidencias/hu-01/aws/idempotencia` → `hallazgos=0`).

**Nota sobre el PENDING de Nexus.** Las salidas son las del commit `3afca6f`, en el que
`verify-infra.sh` aún describía el EULA no aceptado como «PENDIENTE de la decisión del equipo». La
decisión es definitiva: el EULA no se acepta y el registro es CNCF Distribution. Desde esta
revisión, `verify-infra.sh` informa de esa comprobación como **PASS** («EULA no aceptado por
decisión del equipo; Nexus no es el registro») y `configure.sh` como UNCHANGED. Los archivos de
esta carpeta no se han editado. El nuevo mensaje no se ha ejecutado aún en AWS: aparecerá en la
próxima prueba.

| Archivo | Contenido |
|---|---|
| `report.txt` | Resumen de la prueba: cada comprobación en PASS o FAIL, `RESULTADO: IDEMPOTENTE` y la parada |
| `stop.txt` | Parada obligatoria con `teardown.sh --stop --apply` y comprobación posterior: `no hay instancias de circleguard en ejecución` |
| `run1.txt`, `run2.txt` | Salida completa de las dos ejecuciones de `bootstrap-all.sh` (la 2.ª: `created=0 updated=0 unchanged=137`) |
| `S0.txt` a `S3.txt` | Instantáneas de `verify-infra.sh --snapshot`: antes, tras cada ejecución y tras reiniciar los contenedores |
| `diff-S0-S1.txt`, `diff-S1-S2.txt`, `diff-S2-S3.txt` | Diferencias; las dos últimas, vacías |
| `registry.txt` | Publicación y descarga en CNCF Distribution desde el host `ci` y desde el contenedor de Jenkins con `crane` |
| `isolation.txt` | Flujos de red entre `ci` y `nexus` (incluido `ci → registro:8082`) |
| `health-after-restart.txt` | `verify-infra.sh --health` tras reiniciar todos los contenedores (25 PASS, 0 FAIL, 1 PENDING: Nexus sin EULA, por decisión) |

sha256 de los originales sin enmascarar: los seis primeros, de `sha256sums.txt` de la prueba; los
dos últimos, calculados al volver a enmascararlos (fuera del repositorio):

```
6df0a0b3f3512d165f764d9302186a802dc55b9142e1d7517cd08cb30197b3a7  S0.txt
6a609662dae4d8dd402e0b8ffcef2cc6abb7b29845515f7d802b437634cd4d05  S1.txt
6a609662dae4d8dd402e0b8ffcef2cc6abb7b29845515f7d802b437634cd4d05  S2.txt
b5982477255e9dadd4cb4b5d162e9c952789e08de107ae780023ad9ab448ad0c  run1.txt
9a21a9815410cb2b485d1c48d5ec2863e83c5de3fe588a8871f8c9b47fb1f034  run2.txt
6a609662dae4d8dd402e0b8ffcef2cc6abb7b29845515f7d802b437634cd4d05  S3.txt
c2b73c14122794673639cba3ea44df669024dedf935bfa5ee9ce26eba9d72245  report.txt
98b19f8685c9e0d7b64be252cb495430429a193085d141400d8113ddf2d29ad1  stop.txt
```

# Destrucción y reconstrucción desde cero en AWS · 2026-11-06 (copias enmascaradas)

**Resultado: PASS.** La infraestructura de HU-01 se destruyó por completo y se reconstruyó con
`bootstrap-all.sh --apply --approve ci,nexus` en **922 s**, sin ningún paso manual dentro del comando.
Esta es la prueba del «reconstruyen Jenkins, SonarQube y registro desde cero con un comando» de la
rúbrica P1.2 (nivel 2 del [ensayo de reconstrucción](../../ensayo-reconstruccion/README.md)).

## Qué hizo cada persona

| Paso | Quién | Dónde |
|---|---|---|
| Autorizar la pérdida de datos de las herramientas, conservando los secretos | Responsable de la cuenta | Conversación |
| Destruir: `teardown-cloudshell.sh --apply`, sin `--purge-secrets` | Responsable, como el usuario IAM `circleguard-hu01-teardown`, con su MFA | AWS CloudShell |
| Iniciar sesión como operador (dos veces) | Responsable, con su MFA | Página oficial de AWS |
| Reconstruir con el comando único y probar la segunda ejecución y el aislamiento | Asistente, con la sesión del operador | WSL |

La destrucción solo puede hacerse en CloudShell, con otro usuario y su MFA: el rol de operación no puede
borrar nada, por diseño. El comando único cubre la reconstrucción.

## Cronología (UTC; hora local = UTC−5)

| Hora | Hecho | Archivo |
|---|---|---|
| 02:26 | Inventario previo (solo lectura): 5 instancias, 5 volúmenes (85 GiB), 5 grupos de seguridad, 4 subredes, tabla de rutas, Internet Gateway, VPC y 4 pares de llaves | [`01-inventario-previo.txt`](01-inventario-previo.txt) |
| 02:46-02:48 | **Destrucción** en CloudShell: 17 recursos eliminados; secretos de SSM conservados | [`02-destruccion-cloudshell.txt`](02-destruccion-cloudshell.txt) |
| 02:53 | Comprobación: `no hay instancias, red ni llaves de circleguard que destruir` | [`03-inventario-posterior.txt`](03-inventario-posterior.txt) |
| 03:01-03:17 | **Reconstrucción desde cero:** `bootstrap-all created=43 updated=55 unchanged=67 duración=922s`; `verify-infra pass=26 fail=0 pendiente=0` | [`04-bootstrap-all-desde-cero.txt`](04-bootstrap-all-desde-cero.txt) |
| 03:25-03:33 | **Segunda ejecución:** `created=0 updated=0 unchanged=138 duración=475s`; ninguna línea CREATED ni UPDATED | [`05-bootstrap-all-segunda-ejecucion.txt`](05-bootstrap-all-segunda-ejecucion.txt) |
| 03:37-04:00 | Ambientes y aislamiento, fases 1-3 (1358 s): 16/16 PASS en cada una | [`ambientes/fases-1-3/`](ambientes/fases-1-3/report.txt) |
| 04:01-04:11 | Aislamiento, fases 4-5 (625 s): 3/3 y 2/2 PASS | [`ambientes/fases-4-5/`](ambientes/fases-4-5/report.txt) |
| 04:18 | Las 5 instancias, detenidas | `ambientes/fases-4-5/stops.txt` |

## La infraestructura es nueva

| Recurso | Antes | Después |
|---|---|---|
| VPC | `vpc-017214…` | `vpc-00f01f…` |
| `circleguard-ci` | `i-010843f2125041114` | `i-0802315f63ba2f6cc` |
| `circleguard-nexus` | `i-08c990919adc43fa1` | `i-04404084d9394ef13` |
| `circleguard-env-dev` | `i-06c9577f8afb5a763` | `i-09dd58896a6e461a7` |
| `circleguard-env-stage` | `i-0eacec7096879d402` | `i-007d7c86d6848eaf6` |
| `circleguard-env-prod` | `i-0b11b6112952c0dbf` | `i-01a3fdafe5d4b27d5` |

Las pruebas de idempotencia y aislamiento anteriores ([`../idempotencia/`](../idempotencia/README.md) y
[`../aislamiento/`](../aislamiento/README.md)) corresponden a la infraestructura anterior; se conservan
como historia. Sus IDs ya no existen en la consola de AWS.

## Qué se pierde y qué se conserva

- **Se perdió** (y se recreó desde los scripts): los volúmenes de Jenkins, SonarQube, Nexus y el registro, los certificados TLS del registro y las IP públicas. No había pipelines, proyectos analizados ni imágenes publicadas.
- **Se conservó:** los 36 secretos de SSM, las llaves SSH (por su copia de custodia), los usuarios y roles de IAM y todo el repositorio.

## Qué demuestra y qué no

- **Demuestra:** que el comando único crea desde una cuenta sin recursos la red, los servidores y las cuatro herramientas, con el estado sano (`pass=26`), y que una segunda ejecución no cambia nada.
- **Los ambientes se crean con otro comando** (`test-isolation.sh`): el límite de 5 vCPU impide encender los cinco servidores a la vez, y `bootstrap-all.sh --approve all` se rechaza. La rúbrica nombra Jenkins, SonarQube y el registro.
- **El tiempo medido (922 s)** incluye la creación de la red y los servidores y el arranque de las herramientas, pero no los pasos humanos (CloudShell y los inicios de sesión).

## Enmascarado

Los archivos 01, 03 y 04 salen de `infra/logs` con `cg_mask_evidence`; el 02 es la transcripción de la salida que el
responsable pegó, con el número de cuenta sustituido; el 05 salió ya enmascarado. Se quitaron las rutas de `$HOME` y los
espacios finales. `bash infra/check-evidence.sh` da `hallazgos=0` en esta carpeta y en `ambientes/`.

sha256 de los originales sin enmascarar (fuera del repositorio):

```
edec5bda8a63cb875a77bae91e92409f6671b0cf4d0efa60344f4b59769fd8f3  01-inventario-previo.txt
8696037138ce4f77667cc92b6a126ede8b5d02215b1e066cdf6d686de90d8188  03-inventario-posterior.txt
bbb35156dcb5e4ac11575d5f88da3655ff47256ef10d2744efb41996a88dea36  04-bootstrap-all-desde-cero.txt
1cfb4d471ab55d9f67ca88ce94646bb9fc639b8820fda33d2b19dd9f1ea082d0  05-bootstrap-all-segunda-ejecucion.txt (sin enmascarado adicional)
ec8dbd21e421ac549ddf6a2f8c0b40b9cf5c5542b5629eea4581e6e7c864b8b5  ambientes/fases-1-3/fase1-env-dev-env-stage.txt
fd0dec10dbd9b25b73d49cfb66645016bc292ec8ed319d054cc3c47e453bca8f  ambientes/fases-1-3/fase2-env-dev-env-prod.txt
5e7b0d09b1d9f5f17f9d0ae6acc71828a7fb77d1b50b0f101f9621b69bfc76e9  ambientes/fases-1-3/fase3-env-stage-env-prod.txt
d8cfb118371cbf2a359924cab18c0bd886402c31f86cb30af06aa7f23ec259a3  ambientes/fases-1-3/network.txt
0ccfc61126e508fc502e52775734ac2fd0dd952b73bb7856c5265b81714c9ac9  ambientes/fases-1-3/report.txt
d49b55419454178c4792c895b6d03a4bd64f05e2cabf213807b67dfc4cf5e05a  ambientes/fases-1-3/stops.txt
95640b5e95bdd7163eeb20b5963c88f410c1f74addf888c5ac322c9ce06d0b71  ambientes/fases-4-5/fase4-ci-env-dev.txt
20f7bb03bc21bd577c989bc794ccd36d120e5bc3e9511643976faebc9f61d85d  ambientes/fases-4-5/fase5-nexus-env-dev.txt
daa6e448c409182d5368cf3aad1b6f9dae5767d4880fba7ba45a5bedbefd8c11  ambientes/fases-4-5/network.txt
ed9ce21e25789cadb2a744b913c09300f8235904935223dde33f61f1a7764713  ambientes/fases-4-5/report.txt
e531352ab1ee55a200cf0e5110ebbde3a7533f86017916d40470b7e33e055d1d  ambientes/fases-4-5/stops.txt
```

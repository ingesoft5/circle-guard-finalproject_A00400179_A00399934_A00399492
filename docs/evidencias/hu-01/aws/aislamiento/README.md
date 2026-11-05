# Prueba de aislamiento con tráfico en AWS (C2) · 2026-11-03/04 (copias enmascaradas)

**Estado: ejecutada. Resultado: `AISLAMIENTO VERIFICADO CON TRÁFICO (todas las comprobaciones en
PASS)` en las dos sesiones.**
- **Comando:** `infra/test-isolation.sh --apply`, lanzado con la autorización explícita del
  responsable de la cuenta.
- **Base:** commit `3afca6f` más los cambios locales de esta revisión.
- **MFA:** dos sesiones; el responsable la escribió solo en la página oficial de AWS
  ([procedimiento](../../INFORME_FINAL_HU01_SPRINT1.md#11-prueba-de-aislamiento-con-tráfico)).

| Subcarpeta | Sesión (UTC) | Fases | Resultado |
|---|---|---|---|
| [`fases-1-3/`](fases-1-3/report.txt) | 2026-11-03 23:41 → 2026-11-04 00:05 (1427 s) | 1. `env-dev` + `env-stage` · 2. `env-dev` + `env-prod` · 3. `env-stage` + `env-prod` | 16/16 PASS en cada fase; `bootstrap-env.sh` idempotente en dev, stage y prod |
| [`fases-4-5/`](fases-4-5/report.txt) | 2026-11-04 00:08 → 00:20 (716 s) | 4. `ci` + `env-dev` · 5. `nexus` + `env-dev` | 3/3 y 2/2 PASS; `bootstrap-env.sh` idempotente en dev |

## Qué se comprobó (con `nc` desde los hosts)

| Flujo | Esperado | Resultado | Archivo |
|---|---|---|---|
| dev ↔ stage, dev ↔ prod y stage ↔ prod, puerto 22, en ambos sentidos (6 flujos) | Bloqueado | PASS | `fases-1-3/fase*.txt` |
| `ci → env-dev:22` (despliegue) | Permitido | PASS | `fases-4-5/fase4-ci-env-dev.txt` |
| `env-dev → ci:8080` y `env-dev → ci:9000` (Jenkins y SonarQube) | Bloqueado | PASS | `fases-4-5/fase4-ci-env-dev.txt` |
| `env-dev → nexus:8082` (registro) | Permitido | PASS | `fases-4-5/fase5-nexus-env-dev.txt` |
| `nexus → env-dev:22` | Bloqueado | PASS | `fases-4-5/fase5-nexus-env-dev.txt` |

En cada host de ambiente (fases 1-3) se comprobaron también:
- Docker activo;
- parada automática programada;
- swap de seguridad;
- un `.env` propio de su ambiente, 0600 de root.

## Idempotencia de `bootstrap-env.sh` (C3)

Cada ambiente se preparó dos veces, en dos fases distintas:
- **1.ª ejecución:** `created=4 updated=3 unchanged=2` (Docker, swap, `.env` y parada automática).
- **2.ª ejecución:** `created=0 updated=0 unchanged=9` en dev, stage y prod.
- **Sesión 2:** `env-dev` volvió a dar `created=0 updated=0` en las fases 4 y 5.

## Cambios en la red

En la sesión 1, `bootstrap-network.sh` informó `updated=10`:
- **Causa:** la IP pública del operador había cambiado desde la prueba anterior.
- **Cambio:** la regla del puerto 22 pasó a la IP nueva en los 5 grupos de seguridad; se revocó la
  regla anterior y se autorizó la nueva ([network.txt](fases-1-3/network.txt)).
- **Nada más cambió:** en la sesión 2 la red dio `created=0 updated=0`.

## Recursos y parada

- **Creadas en la fase 1 y 2:** las 3 instancias `t3.small` con sus volúmenes de 10 GiB
  (`bootstrap-servers created=2`, luego `created=1`).
- **Parada:** cada fase detuvo sus servidores; al final, `no hay instancias de circleguard en
  ejecución` ([stops 1-3](fases-1-3/stops.txt), [stops 4-5](fases-4-5/stops.txt)).
- **Comprobación independiente** de solo lectura a las 00:21 UTC: las 5 instancias `stopped`.

## Enmascarado

- **Origen:** `masked/` de `~/.circleguard/isolation/20261103T234117Z/` y
  `~/.circleguard/isolation/20261104T000818Z/`, generadas por `cg_mask_evidence` después de la
  parada.
- **Al copiarlas:** las rutas de `$HOME` se sustituyeron por `~` y se quitaron los espacios finales.
- **Comprobación:** `bash infra/check-evidence.sh` da `hallazgos=0` en las dos carpetas.

sha256 de los originales sin enmascarar (fuera del repositorio):

```
a622ffbca36ad1bddfc23f627d1826c0fc59db7f325ad394b2a57cb2916913a9  fases-1-3/fase1-env-dev-env-stage.txt
9d8c9dbfe399e84ad3b4e0a7e8a0f356646af1a522e594ff373b18879aadfc3f  fases-1-3/fase2-env-dev-env-prod.txt
2dd592a10918d594467adc69e3662709fc574db956b17688f27a88bc7e724530  fases-1-3/fase3-env-stage-env-prod.txt
0c4b37c33358b74b0e4750194ece568fc1daab77803cbde256727b25b72dcaed  fases-1-3/network.txt
e65df48bb9a6cbd547bf90194b47e082c62e75b6a3181acb6e73bd6a99812179  fases-1-3/report.txt
047e2d545cd01c1f3b6adbcfccd914974138c1f94112e45cfb0e3ad23c99a276  fases-1-3/stops.txt
0c22b1857270ecedd6474811aab1ac3909673f00cc105d09bc4ba1b806ecaa60  fases-4-5/fase4-ci-env-dev.txt
be3935f23efb82fe758c55c158dbf5ceb18fa39b7d215a3ffde65c08a5afa1de  fases-4-5/fase5-nexus-env-dev.txt
087b6b5f55bcece712dd7446af4535124b1296a84ba4a9fd74b7f4fa559ebf47  fases-4-5/network.txt
7568c967339b50a111cb32d0651654fc30b0fd104409ccac0a83005b3c5e760d  fases-4-5/report.txt
9f768d849ac6aa3c1e67e3cb22c702c846ba5b113ed08d2399e1ca9caa0861a1  fases-4-5/stops.txt
```

## Criterios de PASS (definidos antes de ejecutarla)

1. Cada `report.txt` contiene
   `RESULTADO: AISLAMIENTO VERIFICADO CON TRÁFICO (todas las comprobaciones en PASS)` y, a
   continuación, `instancias detenidas al terminar`. **Cumplido en las dos sesiones.**
2. Las líneas `aislamiento: env-X -> env-Y:22 bloqueado` cubren los tres pares, y `permitido: ci ->
   env-dev:22` y `permitido: env-dev -> nexus:8082` están en PASS. **Cumplido.**
3. `idempotencia: bootstrap-env.sh <ambiente> sin cambios…` está en PASS (C3). **Cumplido.**

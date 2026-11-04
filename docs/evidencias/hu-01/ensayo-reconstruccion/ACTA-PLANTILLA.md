# Acta del ensayo de reconstrucción de nivel 1 (C5) · PLANTILLA

> Copie este archivo como `docs/evidencias/hu-01/aws/ensayo-nivel1/ACTA.md` y complételo **después**
> de ejecutar el ensayo ([instrucciones](README.md)). No escriba contraseñas, códigos MFA, IP
> públicas ni el número de cuenta.

## Datos

| Campo | Valor |
|---|---|
| Integrante que ejecuta (B) | |
| Responsable que autentica (opción A) | |
| Fecha y hora de inicio y fin (UTC) | |
| Commit (`git rev-parse --short HEAD`) | |
| Máquina y sistema (por ejemplo, Windows 11 + WSL Ubuntu 24.04) | |
| Estado inicial (`~/.circleguard` y `~/.ssh/circleguard` inexistentes: sí o no) | |

## Pasos (marque cada uno y anote el resultado)

| Paso | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `git clone …` y `git checkout HU01_Infraestructura_nube_bash` | Clon en el sistema de archivos de WSL | |
| 2 | `bash infra/check-prerequisites.sh` | `fail=0` | |
| 3 | `bash infra/aws-session.sh init` · `login operator` · `status` | `circleguard-hu01-operator-login activa` | |
| 4 | `bash infra/bootstrap-secrets.sh --apply` | 4 llaves `restaurada desde SSM`; el resto `UNCHANGED` | |
| 5 | `bash infra/bootstrap-all.sh --plan` | Sin errores; costo estimado | |
| 6 | `bash infra/test-idempotency.sh --apply --approve ci,nexus` | `RESULTADO: IDEMPOTENTE` e `instancias detenidas al terminar` | |

## Desviaciones respecto a la documentación

Enumere todo lo que no estuviera documentado, fallara o hubiera que deducir: el paso, qué ocurrió
y cómo se resolvió. Escriba «ninguna» si no las hubo.

1.

## Evidencia entregada (en `docs/evidencias/hu-01/aws/ensayo-nivel1/`)

- [ ] `ensayo-01-prerrequisitos.txt`
- [ ] `ensayo-02-secretos.txt`
- [ ] `ensayo-03-plan.txt`
- [ ] `idempotencia/` (copia de `~/.circleguard/idempotency/<marca>/masked/*`)
- [ ] `bash infra/check-evidence.sh docs/evidencias/hu-01/aws/ensayo-nivel1` termina con `hallazgos=0`

## Conclusión

- [ ] Se cumplen los criterios de PASS de C5 ([README](README.md#criterios-para-declarar-c5-en-pass))
- Firma o nombre de B:
- Firma o nombre del responsable:

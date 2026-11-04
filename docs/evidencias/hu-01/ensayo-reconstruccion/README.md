# Ensayo de reconstrucción de nivel 1 (C5): instrucciones para otro integrante

**Objetivo:** demostrar que una persona que **no** hizo el despliegue del 2026-11-02 reproduce y
hace converger la plataforma siguiendo solo la documentación, sin destruir nada. Es la evidencia
de C5 y del «se reconstruye con un comando» de la rúbrica P1.2.

La idempotencia en AWS (C3) ya la demostró el responsable el 2026-11-03
([aws/idempotencia/](../aws/idempotencia/README.md)). La ejecución de B aporta lo que le falta a
C5: que **otra persona** reproduce el resultado solo con la documentación. De paso, confirma la
idempotencia de forma independiente.

**Estado: no realizado.** Nadie lo ha ejecutado todavía.

**No depende de los secretos del responsable:**
- B no recibe contraseñas ni valores.
- Los secretos se leen de SSM y las llaves SSH se restauran desde su copia de custodia (paso 4).
- Lo único que aporta el responsable es la autenticación del usuario operador (ver «Identidad»).

| Aspecto | Valor |
|---|---|
| Quién | Un integrante distinto de quien desplegó (en adelante, «B») |
| Dónde | Su propia máquina con WSL Ubuntu 24.04, o una distribución o un usuario de WSL nuevo, sin `~/.circleguard` ni `~/.ssh/circleguard` |
| Coste | ≤ 0.21 USD (1 h como máximo con `ci` y `nexus` encendidas) |
| Duración | Unos 30 min de preparación y unos 45 min de prueba. La del 2026-11-03 duró 1889 s (≈ 32 min), con los servidores encendidos ≈ 26 min según el registro de costos |
| Destruye datos | No. El nivel 2, destructivo, no forma parte de este ensayo |
| Requiere | La autorización del responsable de AWS y la MFA del usuario operador (ver «Identidad») |

## Identidad: quién escribe la MFA

El único usuario con permisos de operación es `circleguard-hu01-operator`, y su MFA la tiene el
responsable de la cuenta. Hay dos opciones; la recomendada es la A.

- **A (recomendada, sin cambios en IAM):** B ejecuta todos los comandos. Cuando `aws-session.sh login
  operator` abra la página de AWS, el responsable escribe el usuario, la contraseña y la MFA en esa
  página. Puede hacerse por videollamada, compartiendo pantalla, sin enviar códigos por chat.
- **B (cambia IAM y requiere autorización):** crear un acceso de operador propio para B (otro
  usuario o un segundo dispositivo MFA). Queda fuera de HU-01, salvo que el equipo lo apruebe.

En ningún caso se envían contraseñas ni códigos MFA por chat o correo.

## Pasos de B

Desde la raíz del clon, en WSL:

1. **Clonar** la rama `HU01_Infraestructura_nube_bash` en el commit que indique el equipo.
   Anotar `git rev-parse --short HEAD`.
2. **Prerrequisitos.** Resultado esperado: `fail=0`.
   ```bash
   bash infra/check-prerequisites.sh 2>&1 | tee ~/ensayo-01-prerrequisitos.txt
   ```
   Si falta AWS CLI v2, se instala con los comandos de `infra/README.md` («Prerrequisitos») y se
   repite el paso.
3. **Sesiones**, con el responsable escribiendo las credenciales en la página de AWS:
   ```bash
   bash infra/aws-session.sh init
   bash infra/aws-session.sh login operator
   bash infra/aws-session.sh status
   ```
   Resultado esperado: `circleguard-hu01-operator-login activa`.
4. **Llaves y secretos:** restaura las cuatro llaves SSH desde su copia en SSM.
   ```bash
   bash infra/bootstrap-secrets.sh --apply 2>&1 | tee ~/ensayo-02-secretos.txt
   ```
   Resultado esperado:
   - cuatro líneas `UPDATED llave privada circleguard-… restaurada desde SSM`;
   - `created=1` (el secreto del registro) o `created=0` si ya existe;
   - los demás secretos, `UNCHANGED`.
5. **Plan del comando único**, sin cambios: revisar las líneas `PLAN` y el costo estimado.
   ```bash
   bash infra/bootstrap-all.sh --plan 2>&1 | tee ~/ensayo-03-plan.txt
   ```
6. **Prueba integral**, que es FACTURABLE: pide escribir `PROBAR IDEMPOTENCIA` y detiene las
   instancias al terminar.
   ```bash
   bash infra/test-idempotency.sh --apply --approve ci,nexus
   ```
   Resultado esperado: `report.txt` contiene
   `RESULTADO: IDEMPOTENTE (todas las comprobaciones en PASS)` y, a continuación,
   `instancias detenidas al terminar`.
7. **Desviaciones:** anotar todo lo que no estuviera en la documentación o no saliera como dice:
   comandos que fallaron, pasos que hubo que adivinar, tiempos.

## Evidencia que B entrega

Va en `docs/evidencias/hu-01/aws/ensayo-nivel1/` y la versiona el equipo. Antes de entregarla,
`bash infra/check-evidence.sh docs/evidencias/hu-01/aws/ensayo-nivel1` debe terminar con
`hallazgos=0`. Comprueba, sin AWS y sin mostrar nada, que no hay número de cuenta, IP públicas
completas, claves, secretos ni rutas personales.

| Archivo | Contenido |
|---|---|
| `ensayo-01-prerrequisitos.txt` | Salida del paso 2 |
| `ensayo-02-secretos.txt` | Salida del paso 4. Contiene nombres de parámetros, no valores; las rutas de `$HOME` pueden reemplazarse por `~` |
| `ensayo-03-plan.txt` | Salida del paso 5 |
| `idempotencia/` | Copia de `~/.circleguard/idempotency/<marca>/masked/*` |
| `ACTA.md` | Nombre de B, fecha y hora (UTC), commit, máquina y sistema, quién escribió la MFA (opción A o B), duración, desviaciones encontradas y conclusión |

## Criterios para declarar C5 en PASS

1. B completó los pasos 2-6 sin ayuda verbal, salvo la autenticación de la opción A.
2. `check-prerequisites.sh` terminó con `fail=0`.
3. `report.txt` contiene `RESULTADO: IDEMPOTENTE` y las instancias quedaron detenidas.
4. Toda desviación de `ACTA.md` está corregida en `infra/README.md` (o justificada) antes de cerrar.

Si el paso 6 falla, la evidencia se conserva igualmente y C5 y C3 quedan en FAIL hasta que se
corrija y se repita.

## Mensaje para B (listo para enviar)

> Hola. Necesito que hagas el ensayo de reconstrucción de HU-01 (criterio C5). Sigue
> `docs/evidencias/hu-01/ensayo-reconstruccion/README.md` en tu WSL, desde un clon limpio de la
> rama `HU01_Infraestructura_nube_bash`. No necesitas credenciales de AWS. Cuando el paso 3 abra
> la página de AWS, avísame por videollamada y escribo yo el usuario y la MFA; no me envíes ni me
> pidas códigos por chat. El paso 6 cuesta como máximo 0.21 USD y apaga todo al terminar. Al
> acabar, pásame los archivos de la tabla «Evidencia que B entrega» y el `ACTA.md` con lo que no
> haya estado claro en la documentación.

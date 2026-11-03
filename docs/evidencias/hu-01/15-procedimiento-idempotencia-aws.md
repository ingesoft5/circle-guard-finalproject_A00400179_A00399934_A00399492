# 15 · Procedimiento de la prueba de idempotencia en AWS (criterio C3) — NO ejecutado

Preparado el 2026-11-02 sobre el commit `3632068`. Las instancias están **detenidas** y esta prueba
**requiere arrancarlas**: no se ejecuta sin una autorización explícita aparte.

## 1. Qué hace `bootstrap-all.sh --apply --approve ci,nexus`

Comprobado en el código (`infra/bootstrap-all.sh`, `infra/bootstrap/lib/remote.sh`):

| Orden | Paso | Recursos que consulta o puede modificar | Efecto esperado con el estado actual |
|---|---|---|---|
| 1 | `cg_aws_preflight` | Identidad y zona | Rol de operación |
| 2 | `bootstrap-network.sh --apply` | VPC, IGW, subredes, ruta, asociaciones, 5 grupos y 31 reglas | `UNCHANGED`, salvo la regla del 22 si cambió la IP pública del operador (revoca la `/32` antigua y añade la nueva) |
| 3 | `bootstrap-secrets.sh --apply` | 35 parámetros SSM y 4 pares; solo crea lo que falta y nunca sobrescribe | `UNCHANGED` ×43 |
| 4 | `bootstrap-servers.sh --apply --approve ci,nexus` | Busca las instancias por etiquetas; si están detenidas las **inicia** (facturable) | 1.ª ejecución: `UPDATED` ×2 (inicio); 2.ª: `UNCHANGED` |
| 5 | `bootstrap-jenkins/sonarqube/nexus.sh --apply` (solo con la instancia en ejecución) | Por SSH: Docker, swap, temporizador, archivos del stack, `.env`, `docker compose up -d` (reconstruye solo si cambió el contexto) y `configure.sh` | `UNCHANGED`; Nexus termina con `PLAN` del EULA (no acepta nada porque `NEXUS_ACCEPT_EULA=false`) |
| 6 | `bootstrap-env.sh` | Solo con servidores de ambiente en ejecución (no existen) | Se omite |
| 7 | `verify-infra.sh --health --roles=ci,nexus` | Lectura | `pass` con 1 `PENDING` (EULA) |

- **No crea recursos nuevos:** red y secretos ya existen y se buscan por etiquetas, y las instancias se
  **inician** en lugar de crearse. Las instancias no tienen perfil IAM y no hay NAT, Elastic IP ni
  balanceadores.
- **Permisos:** rol de operación (MFA de menos de 1 h) para todo el bootstrap y las instantáneas; rol
  de lectura para la parada; SSH (22) desde la IP del operador.
- **Nexus:** la ejecución no cambia el EULA; `configure.sh` se detiene en el `PLAN` y termina sin
  error. Por eso cada ejecución acaba con `planned=1`: es la acción que espera esa decisión, no un
  cambio.

## 2. Qué compara la instantánea (`verify-infra.sh --snapshot`)

Salida ordenada, sin registro propio y en modo de solo lectura: VPC, subredes, IGW, tablas de rutas,
reglas de los grupos de seguridad, llaves con su huella, **nombres y versiones** de los parámetros
SSM (sin valores), instancias (rol, ID, tipo, AMI, estado y `HttpTokens`) y, para cada host
**encendido**, el sha256 de cada archivo bajo `/opt/circleguard` y la lista de contenedores (nombre,
ID, imagen y fecha de creación).

- **Secretos:** no contiene valores. Incluye el **hash** de los `.env`: no revela el secreto, pero
  las instantáneas se guardan fuera del repositorio y, en las copias de evidencia, esas líneas se
  sustituyen por `<hash del .env omitido>`.
- **Lo que no compara:** IP públicas (cambian en cada arranque) ni el estado del temporizador.

## 3. Procedimiento (comandos exactos, desde la raíz del repositorio en WSL)

```bash
# 0. Preparación (sin coste)
git status --short                                   # vacío
bash infra/aws-session.sh login operator             # el usuario escribe su MFA en la página de AWS
bash infra/teardown.sh --stop                        # plan: las dos instancias, ninguna en ejecución
R=$(pwd)                                             # raíz del repositorio
install -d -m 700 ~/.circleguard/snapshots && cd ~/.circleguard/snapshots

# 1. Instantánea inicial, con las instancias detenidas
(cd "$R" && bash infra/verify-infra.sh --snapshot) > S0.txt

# 2. Primera ejecución: INICIA ci y nexus (facturable desde ese momento)
(cd "$R" && bash infra/bootstrap-all.sh --apply --approve ci,nexus) 2>&1 | tee run1.txt

# 3. Instantánea después de la primera ejecución
(cd "$R" && bash infra/verify-infra.sh --snapshot) > S1.txt

# 4. Segunda ejecución: no debe cambiar nada
(cd "$R" && bash infra/bootstrap-all.sh --apply --approve ci,nexus) 2>&1 | tee run2.txt

# 5. Instantánea después de la segunda ejecución
(cd "$R" && bash infra/verify-infra.sh --snapshot) > S2.txt

# 6. Comparación
diff S1.txt S2.txt && echo "IDEMPOTENTE: estado idéntico tras la segunda ejecución"
grep 'SUMMARY   bootstrap-all' run2.txt              # esperado: created=0 updated=0 (planned=1: EULA)
diff S0.txt S1.txt                                   # diferencias esperadas: ver el punto 4

# 7. Parada obligatoria (rol de lectura)
(cd "$R" && bash infra/teardown.sh --stop)                         # debe listar exactamente las dos instancias
(cd "$R" && CG_CONFIRM=DETENER bash infra/teardown.sh --stop --apply)
(cd "$R" && bash infra/teardown.sh --stop)                         # «no hay instancias de circleguard en ejecución»
```

## 4. Resultado esperado y criterio de aceptación

| Comparación | Esperado |
|---|---|
| `diff S1 S2` | **Vacío** (criterio de aceptación de C3) |
| `SUMMARY` de la 2.ª ejecución | `created=0 updated=0` y `planned=1` (EULA) |
| `SUMMARY` de la 1.ª ejecución | `created=0`; `updated=2` por el inicio de las dos instancias (más 2 si cambió la IP del operador); `planned=1` |
| `diff S0 S1` | Solo el estado de las instancias (`stopped` → `running`) y las líneas `file` y `container` de los hosts encendidos; quizá la regla del 22 si cambió la IP |

Si `diff S1 S2` no está vacío o la segunda ejecución informa `created` o `updated`, la prueba **falla**:
se detienen las instancias, se conserva todo y se diagnostica antes de cambiar nada.

## 5. Duración y coste [ESTIMADO]

- **Duración con las instancias encendidas:** arranque ≈ 2 min, 1.ª ejecución 10-15 min (esperas de
  SSH, `cloud-init` y arranque de SonarQube), 2.ª ejecución ≈ 8-10 min, tres instantáneas ≈ 2 min
  cada una y parada ≈ 2 min. En total **35-45 min**, con un máximo de 1 h.
- **Coste:** 0.2075 USD/h con las dos encendidas, es decir, **≈ 0.12-0.16 USD**, y como máximo
  0.21 USD en 1 h, más el EBS que ya se cobra (≈ 0.145 USD/día). Acumulado previo ≈ 0.13 USD más el
  EBS de los días transcurridos: muy lejos de la línea operativa de 12 USD y del presupuesto absoluto
  de 15 USD. La parada automática de 4 h, que se rearma al arrancar, cubre un olvido. Son estimaciones
  con precios de referencia; la factura real se comprueba en Billing.

## 6. Riesgos y verificaciones

| Riesgo | Mitigación |
|---|---|
| Vence la ventana de MFA del rol de operación (1 h) a mitad de la prueba | Iniciar sesión justo antes y hacer toda la prueba dentro de esa hora; si vence, detener las instancias (rol de lectura) y repetir |
| Cambió la IP pública del operador | La 1.ª ejecución actualiza la regla del 22 de los 5 grupos: **modifica grupos de seguridad**, así que hay que autorizarlo expresamente |
| Algún contenedor se recrea | `compose up -d` solo recrea lo que cambió; se vería en `diff S1 S2` |
| Fallo de SSH o de arranque de servicios | Repetir el paso (idempotente); si no se resuelve en 30 min, parar |
| Olvido de la parada | Temporizador de 4 h desde el arranque, comprobado en `verify-infra.sh --health` |
| EULA | Sin efecto: `NEXUS_ACCEPT_EULA=false` y `configure.sh` se detiene en el `PLAN` |

## 7. Revisión de la auditoría final (2026-11-02): comprobaciones añadidas

El procedimiento es seguro: arranca solo las dos instancias existentes, no crea recursos y termina
con una parada obligatoria. Para que sea suficiente, en la ejecución hay que añadir:

1. **Punto de partida:** antes del paso 2, `grep '^instance' S0.txt` debe mostrar `ci` y `nexus` en
   `stopped`, con los ID `i-010843f2125041114` e `i-08c990919adc43fa1`. Si aparece otra instancia u
   otro estado, no se continúa.
2. **Persistencia tras parada y arranque:** la 1.ª ejecución es también la primera prueba real de que
   los datos sobreviven a una parada (hasta ahora solo está **configurada**: volúmenes con nombre sobre
   EBS). En `run1.txt` deben aparecer `UNCHANGED` para «el administrador gestionado inicia sesión»
   (Jenkins), «el administrador usa la contraseña gestionada» (SonarQube y Nexus) y los contenedores
   sin recrear. Si alguna contraseña vuelve a ser la de fábrica, la persistencia **falla**.
3. **Identificadores y estados:** `grep '^instance' S1.txt S2.txt` debe mostrar los mismos ID en
   `running` y `HttpTokens=required`. Guardar `sha256sum S0.txt S1.txt S2.txt` junto a las salidas.
4. **Contadores:** además del `SUMMARY` de `bootstrap-all`, revisar en `run2.txt` que no hay ninguna
   línea `CREATED` ni `UPDATED` de ningún paso; la única `PLAN` debe ser la del EULA.
5. **Aborto:** ante cualquier `ERROR`, una diferencia inesperada o al llegar a 60 minutos encendidas,
   se ejecuta **inmediatamente** la parada del paso 7 (rol de lectura) y se diagnostica con las
   instancias detenidas. La parada es obligatoria también si la prueba falla.
6. **Rol de operación:** `verify-infra.sh --snapshot` también usa el rol de operación (lee los hosts),
   así que las tres instantáneas deben hacerse dentro de la misma ventana de MFA de 1 h.

## 8. Evidencias que produciría

Las instantáneas `S0`, `S1` y `S2`, las salidas `run1` y `run2`, los `diff` y los registros de
`infra/logs`. Se publicarían copias enmascaradas en `docs/evidencias/hu-01/`, con las líneas del hash
del `.env` omitidas y sin el número de cuenta.

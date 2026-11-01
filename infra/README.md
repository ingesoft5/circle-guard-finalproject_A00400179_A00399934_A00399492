# Infraestructura de CircleGuard en AWS (HU-01)

Scripts Bash idempotentes y stacks Docker Compose que aprovisionan, configuran, verifican y
destruyen la plataforma de HU-01:

- **Herramientas:** Jenkins (JCasC), SonarQube (con PostgreSQL) y Nexus Repository (registro
  Docker `circleguard-docker`), cada una en su propia instancia EC2.
- **Ambientes aislados:** un host EC2 por ambiente (`dev`, `stage`, `prod`), cada uno en su subred,
  con su grupo de seguridad y sus credenciales independientes.

Arquitectura y reglas de red: [docs/arquitectura/infra-ambientes.md](../docs/arquitectura/infra-ambientes.md).
Evidencias de HU-01: [docs/evidencias/hu-01/](../docs/evidencias/hu-01/README.md).

> **Costos.** Crear o iniciar instancias consume créditos de AWS. Ningún script crea recursos
> facturables sin `--apply --approve <rol>`. El modo por defecto, `--plan`, no cambia nada.
> Detenga las instancias al terminar cada sesión (`bash infra/teardown.sh --stop --apply`).

---

## Contenido

| Ruta | Función |
|---|---|
| `bootstrap-all.sh` | **Comando único**: red → secretos → servidores → Jenkins → SonarQube → Nexus → dev/stage/prod → verificación |
| `bootstrap-network.sh` | VPC, 4 subredes públicas, internet gateway (sin NAT Gateway), tabla de rutas y grupos de seguridad de mínimo privilegio |
| `bootstrap-secrets.sh` | Secretos del catálogo en SSM Parameter Store (SecureString) y llaves SSH por nivel |
| `bootstrap-servers.sh` | Instancias EC2 (FACTURABLE: requiere `--approve`); `--prices` consulta precios vigentes |
| `bootstrap-jenkins.sh`, `bootstrap-sonarqube.sh`, `bootstrap-nexus.sh` | Preparan el host, despliegan el stack y configuran la herramienta por código o API |
| `bootstrap-env.sh <env>` | Prepara el host de `dev`, `stage` o `prod` (Docker, Compose y `.env` propio) |
| `verify-infra.sh` | Verificación de solo lectura: salud, aislamiento, credenciales y *snapshot* |
| `tunnel.sh <herramienta>` | Acceso administrativo a Jenkins, SonarQube o Nexus por **túnel SSH** (las UIs nunca se exponen a Internet) |
| `teardown.sh` | Detiene (`--stop`) o elimina (`--destroy`) **solo** los recursos de HU-01 |
| `scan-secrets.sh` | Escaneo de secretos con Gitleaks (árbol de trabajo e historial) |
| `aws-session.sh` | Sesiones AWS temporales: abre la página oficial de AWS (`aws login`); estado y cierre de sesión |
| `bootstrap-iam.sh` | Inspección de solo lectura de la cuenta, validación con Access Analyzer y creación de los roles y usuarios de HU-01 (con aprobación) |
| `config/aws.env` | Configuración **no secreta**: región, CIDR, tipos, puertos, precios de referencia |
| `config/envs/<env>.env` | Subred, tipo y disco de cada ambiente |
| `config/secrets.catalog` | **Nombres** y generadores de los secretos (nunca valores) |
| `config/iam/hu01-{reader,operator,teardown}-policy.json` | Permisos de los tres roles: lectura y detener; crear e iniciar sin borrar; destruir solo lo etiquetado |
| `config/iam/hu01-*-role-trust.json`, `hu01-*-user-policy.json` | Quién asume cada rol y con qué MFA; permisos mínimos de los dos usuarios (sin claves) |
| `bootstrap/lib/*.sh` | Librerías: utilidades comunes, AWS, sesiones, estimación de costos y transporte SSH/local |
| `bootstrap/host/setup-docker.sh` | Se ejecuta en el host: Docker Engine, Compose, rotación de logs, `vm.max_map_count` |
| `bootstrap/{jenkins,sonarqube,nexus}/` | Stacks Compose con imágenes fijadas y scripts de configuración por API |

## Convenciones

- **Idempotencia.** Cada recurso se busca por sus etiquetas (`Project=circleguard`,
  `ManagedBy=infra-bootstrap`, `Role`, `Environment`). Se crea solo si falta y se corrige si se
  desvió. Cada acción se informa como `CREATED`, `UPDATED`, `UNCHANGED` o `PLAN`. Una segunda
  ejecución sobre una infraestructura que ya convergió termina con `created=0 updated=0`.
- **Seguridad por defecto.** `--plan` es el modo por defecto. Los recursos facturables requieren
  `--apply --approve <rol>`, y lo destructivo, una frase de confirmación. Nada destruye datos por defecto.
- **Secretos.** Nunca se imprimen ni se pasan como argumentos. Viajan por tuberías y SSH, y en
  el host se guardan en `/opt/circleguard/<stack>/.env` con modo `0600`. Los logs
  (`infra/logs/`, ignorado por Git) solo contienen nombres, versiones y resultados.
- **Reanudación.** Si una ejecución se interrumpe, se vuelve a lanzar el mismo comando: continúa
  desde el estado real.

## Prerrequisitos

1. **WSL Ubuntu** (recomendado) con Bash ≥ 4, `ssh`, `ssh-keygen`, `curl`, `python3`, `tar` y `nc`.
   Ubuntu 24.04 ya los trae. En Windows con Git Bash los scripts definen `MSYS_NO_PATHCONV=1`.
2. **AWS CLI v2**, instalada en el directorio del usuario (sin `sudo`):
   ```bash
   curl -fsSLo /tmp/awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
   cd /tmp && python3 -c "import zipfile,os; z=zipfile.ZipFile('awscliv2.zip'); [os.chmod(z.extract(i,'.'), (i.external_attr>>16)&0o777 or 0o644) for i in z.infolist()]"
   ./aws/install -i ~/.local/aws-cli -b ~/.local/bin && export PATH="$HOME/.local/bin:$PATH" && aws --version
   ```
3. **Acceso a AWS sin claves permanentes.** Ver
   [Acceso a AWS](#acceso-a-aws-sesiones-temporales-y-autorización-técnica). Cada script elige
   por sí mismo el perfil de la capacidad que necesita.

   La política del operador:
   - solo permite las acciones que usan los scripts (contraste estático en
     [`06-iam-minimo-privilegio.txt`](../docs/evidencias/hu-01/06-iam-minimo-privilegio.txt));
   - funciona únicamente en `us-east-2`;
   - exige la etiqueta `Project=circleguard` para crear o modificar recursos;
   - limita EC2 a `t3.small`, `c7i-flex.large` y `m7i-flex.large` (aptos para el plan gratuito) con IMDSv2, y los discos a gp3 cifrados de
     40 GiB como máximo;
   - acepta solo AMIs de Canonical y secretos bajo `/circleguard/*`;
   - **no incluye ninguna acción destructiva.**

   Destruir solo es posible con el rol de teardown, que asume **otro usuario**
   ([`hu01-teardown-policy.json`](config/iam/hu01-teardown-policy.json)).
4. **Docker Desktop** con integración WSL, solo para la validación local y para Gitleaks.
5. Los scripts se ejecutan desde la raíz del repositorio con `bash infra/<script>.sh`.

## Acceso a AWS: sesiones temporales y autorización técnica

No se crean ni se aceptan claves de acceso permanentes: los scripts se detienen si encuentran una.
Las contraseñas y los códigos MFA se escriben **solo en la página oficial de AWS**, que
`aws-session.sh` abre en el navegador con `aws login`. Ningún script, terminal, archivo ni chat
los recibe. La configuración y las sesiones de la CLI viven en `~/.circleguard/aws` (modo `0700`,
sistema de archivos de WSL), no en `~/.aws`.

### Identidades

| Identidad | Se obtiene con | Puede | Límite impuesto por AWS |
|---|---|---|---|
| `bootstrap`: la identidad que ya usa la cuenta | `aws-session.sh login bootstrap` | Inspección de solo lectura y `bootstrap-iam.sh` | Credenciales temporales; la sesión se cierra al terminar |
| Rol `circleguard-hu01-reader` | Sesión del usuario operador | Describir, consultar precios, Access Analyzer y **detener** instancias | Solo el usuario operador |
| Rol `circleguard-hu01-operator` | Sesión del usuario operador + **código MFA en la llamada `AssumeRole`** | Crear e iniciar recursos acotados; **ningún borrado** | MFA obligatorio; sesiones de 1 h como máximo |
| Rol `circleguard-hu01-teardown` | **Usuario de teardown** + código MFA de menos de 15 min | Borrar solo recursos con `Project=circleguard` | MFA obligatorio; sesiones de 1 h como máximo |

Los usuarios IAM `circleguard-hu01-operator` y `circleguard-hu01-teardown` no tienen claves ni
permisos propios: solo pueden usar `aws login`, ver su propio dispositivo MFA y asumir sus roles.

### Autorización técnica

1. **Capacidades separadas en AWS.** La lectura no crea ni borra; el operador no borra; destruir
   solo es posible con el rol de teardown, que únicamente asume el otro usuario.
2. **La persona abre la ventana con un código MFA.** La sesión de `aws login` no transmite el
   contexto MFA (comprobado en CloudTrail el 2026-11-01: `mfaAuthenticated=false`). Por eso los
   roles de operación y de teardown exigen un **código MFA enviado en la propia llamada
   `AssumeRole`**. Cada código vale una sola vez y abre como máximo 1 h de operación. Sin un
   código nuevo de la persona, AWS rechaza la operación, la intente quien la intente.
   - **Destrucción, opción recomendada:** se ejecuta en **AWS CloudShell**, en el navegador, con
     la sesión del usuario de teardown (contraseña y MFA en la página de AWS). Ninguna credencial
     de teardown llega a esta máquina.
   - **Alternativa:** el código se escribe en la petición de la AWS CLI, en una ventana de
     terminal. Pasa por un proceso local, vale una sola vez y da como máximo 15 minutos para
     asumir el rol.
3. **Límites de lo que se puede crear** (política del operador): `us-east-2`,
   `t3.small/medium/large`, gp3 cifrado de 40 GiB como máximo, AMIs de Canonical y etiqueta
   `Project=circleguard` obligatoria.
4. **Barreras de los scripts**, como defensa adicional: `--plan` por defecto, `--apply --approve
   <rol>` para lo facturable, frase para destruir y estimación local de costos.
5. **Auditoría:** CloudTrail registra cada llamada con su identidad y si tenía MFA.

**Límite inherente:** mientras no caduque, cualquier proceso del mismo usuario del sistema puede
usar una credencial temporal que haya recibido la CLI. Por eso las ventanas son cortas, los
permisos están acotados, `aws-session.sh logout` borra las sesiones locales y la destrucción se
recomienda desde CloudShell.

### Costos: estimación local frente a facturación real

`bootstrap-servers.sh` se niega a crear o iniciar instancias si la **estimación local** (registro
`~/.circleguard/budget/ledger.tsv` más la operación pedida) supera `HU01_BUDGET_USD` (15 USD).
**No es un límite de facturación:** AWS no ofrece un tope de gasto, el registro solo ve lo que
hacen los scripts y usa precios de referencia. El costo real se consulta en la consola de
Billing. Una alerta de AWS Budgets, que requiere aprobación para crearla, avisa con horas de retraso.

### Puesta en marcha

```bash
bash infra/aws-session.sh init                   # ~/.circleguard/aws (0700) y perfiles de inicio de sesión
bash infra/aws-session.sh login bootstrap        # se abre el navegador: inicie sesión con su identidad actual
bash infra/bootstrap-iam.sh                      # solo lectura: cuenta, permisos, cuotas, Access Analyzer y plan
bash infra/bootstrap-iam.sh --audit              # CloudTrail: contexto MFA y escrituras desde el inicio de sesión
bash infra/bootstrap-iam.sh --apply --approve iam   # CON APROBACIÓN: crea roles y usuarios (sin costo)
bash infra/bootstrap-quota.sh                    # cuota de vCPU actual y solicitudes previas (solo lectura)
bash infra/bootstrap-quota.sh --apply --approve quota  # CON APROBACIÓN: pide subir la cuota a 12 vCPU (sin costo)
bash infra/aws-session.sh logout bootstrap       # la identidad administrativa deja de estar disponible
```

**Primer acceso de los usuarios** (una vez, en la consola de AWS, con la identidad actual): en
IAM → Usuarios → `circleguard-hu01-operator` → Credenciales de seguridad:
- **Habilitar el acceso a la consola** con una contraseña que la persona escribe en esa página.
- **Asignar un dispositivo MFA**: escanear el código QR con una app de autenticación e
  introducir dos códigos consecutivos.

Después, lo mismo con `circleguard-hu01-teardown` (en la app es otra entrada). Este usuario solo
inicia sesión en la consola para usar AWS CloudShell; nunca se usa en la estación de trabajo.

**Cada sesión de trabajo:**
```bash
bash infra/aws-session.sh login operator         # navegador: usuario, contraseña y MFA del operador (lectura)
bash infra/aws-session.sh unlock                 # operación aprobada: ventana donde usted escribe el código MFA (1 h)
bash infra/aws-session.sh status                 # sesiones activas, sin mostrar credenciales
bash infra/aws-session.sh logout all             # al terminar
```
`unlock` abre una ventana de Windows Terminal en la que la propia AWS CLI pide el código MFA del
operador; el script que la abre solo espera a que termine. Cada código vale una vez y la sesión
del rol de operación dura 1 h como máximo.

## Configuración

- `config/aws.env`: región `us-east-2`, zona `us-east-2a`, CIDR `10.20.0.0/16`, tipos
  (Jenkins `c7i-flex.large`, SonarQube y Nexus `m7i-flex.large`), puertos, precios de referencia,
  presupuesto estimado (`HU01_BUDGET_USD`) y cuota de vCPU objetivo (`QUOTA_VCPU_TARGET`).
  La cuenta está en el **plan gratuito de AWS**, que solo lanza tipos aptos para la capa gratuita;
  Nexus (≈ 5,4 GiB de JVM) y SonarQube (≈ 3 GiB de JVM y PostgreSQL) necesitan las 8 GiB de
  `m7i-flex.large`.
- `config/envs/{dev,stage,prod}.env`: subredes `10.20.{10,20,30}.0/24`, `t3.small`, 20 GiB.
- `config/operator.local.env` (ignorado): `ADMIN_CIDRS` (y, si hace falta, `CG_AWS_PROFILE`). Si `ADMIN_CIDRS` está
  vacío, se usa la IP pública actual del operador (`/32`).
- `NEXUS_ACCEPT_EULA` (en `aws.env`): Nexus Community Edition 3.96.5 **exige aceptar su EULA**
  (<https://links.sonatype.com/products/nxrm/ce-eula>). Es una decisión del equipo: con `false`,
  el bootstrap de Nexus se detiene antes de usarlo.

## Gestión de secretos

| Ámbito | Ruta en SSM (SecureString) | Contenido |
|---|---|---|
| Herramientas | `/circleguard/tools/{jenkins,sonarqube,nexus}/*` | Contraseñas de administrador y de la BD de SonarQube |
| Ambientes | `/circleguard/{dev,stage,prod}/*` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `NEO4J_PASSWORD`, `LDAP_ADMIN_PASSWORD`, `CG_JWT_SECRET`, `CG_QR_SECRET`, `CG_VAULT_*`: **valores distintos por ambiente** |
| Acceso | `/circleguard/ssh/circleguard-{tools,dev,stage,prod}` | Copia de custodia de las llaves SSH ED25519 (la llave privada vive en `~/.ssh/circleguard/`) |

- `bootstrap-secrets.sh` genera **solo lo que falta** y nunca sobrescribe ni rota. Las claves
  `CG_VAULT_*` cifran identidades: rotarlas exige un procedimiento de migración aprobado.
- Las instancias **no tienen rol IAM**: el operador lee SSM y envía a cada host, por SSH, solo
  los secretos de ese host.
- Los parámetros SSM estándar no tienen cargo de almacenamiento (verificar en la página de precios
  de AWS).

## Flujo de aprovisionamiento con control de costos

Cada paso admite `--plan` (por defecto), que muestra lo que haría y valida permisos con
`--dry-run` de AWS sin crear nada, y `--apply`.

| Paso | Comando | ¿Facturable? |
|---|---|---|
| 1. Red | `bash infra/bootstrap-network.sh --apply` | No (VPC, subredes, IGW, rutas y SG no se cobran) |
| 2. Secretos y llaves | `bash infra/bootstrap-secrets.sh --apply` | No (SSM estándar y pares de llaves) |
| 3. Estimación | `bash infra/bootstrap-servers.sh` y `--prices` | No (solo lectura) |
| 4. Servidores | `bash infra/bootstrap-servers.sh --apply --approve jenkins` (un rol por aprobación, o una lista) | **Sí**: EC2, EBS e IPv4 pública |
| 5. Herramientas | `bash infra/bootstrap-{jenkins,sonarqube,nexus}.sh --apply` | Horas de instancia |
| 6. Ambientes | `bash infra/bootstrap-env.sh dev --apply` (y `stage`, `prod`) | Horas de instancia |
| 7. Verificación | `bash infra/verify-infra.sh` | Horas de instancia |
| 8. Acceso administrativo | `bash infra/tunnel.sh jenkins` (o `sonarqube`, `nexus`) y abrir `http://localhost:8080` | Horas de instancia |

**Comando único** (reconstrucción desde cero, después de aprobar el costo):
```bash
bash infra/bootstrap-all.sh --plan                       # recorrido completo sin cambios + costo estimado
bash infra/bootstrap-all.sh --apply --approve all        # FACTURABLE: construye o converge toda la plataforma
```
Con `--approve jenkins,sonarqube` solo se crean o inician esos servidores, y los pasos de los
demás roles se omiten.

### Presupuesto por recurso (topología A en el plan gratuito, On-Demand en us-east-2)

Tarifas de la AWS Pricing API del 2026-11-01. Confírmelas antes de cada sesión con
`bash infra/bootstrap-servers.sh --prices` (solo lectura). En el plan gratuito todo se descuenta
de los créditos y **AWS no cobra más allá de ellos**: el plan termina el 2027-04-30 03:45 UTC
(`freetier get-account-plan-state`) o al agotarse los créditos.

| Recurso | Cantidad | Tarifa | Encendido (USD/h) | Detenido | USD/día (24 h encendido) | USD/mes (730 h) |
|---|---|---|---|---|---|---|
| EC2 Jenkins `c7i-flex.large` (2 vCPU, 4 GiB) | 1 | 0.08479/h | 0.0848 | 0 | 2.03 | 61.90 |
| EC2 SonarQube `m7i-flex.large` (2 vCPU, 8 GiB) | 1 | 0.09576/h | 0.0958 | 0 | 2.30 | 69.90 |
| EC2 Nexus `m7i-flex.large` (2 vCPU, 8 GiB) | 1 | 0.09576/h | 0.0958 | 0 | 2.30 | 69.90 |
| EC2 dev, stage y prod `t3.small` (2 vCPU, 2 GiB) | 3 | 0.0208/h c/u | 0.0624 | 0 | 1.50 | 45.55 |
| IPv4 pública (automática, sin Elastic IP) | 6 | 0.005/h c/u | 0.0300 | 0 (se libera) | 0.72 | 21.90 |
| EBS gp3 cifrado (30 + 30 + 40 + 3×20 GiB) | 160 GiB | 0.08/GB-mes | 0.0175 | **0.0175/h** | 0.42 | 12.80 |
| Transferencia de salida | < 1 GB | 100 GB/mes gratis | 0 | 0 | 0 | 0 |
| SSM Parameter Store estándar y KMS `aws/ssm` | 35 parámetros | Sin cargo (capa gratuita de KMS) | 0 | 0 | 0 | 0 |
| VPC, subredes, IGW, rutas, grupos de seguridad, pares de llaves, IAM, CloudShell, Service Quotas | — | Sin cargo | 0 | 0 | 0 | 0 |
| NAT Gateway, balanceadores, Elastic IP, *snapshots*, ráfagas T3 | — | **No se usan** | 0 | 0 | 0 | 0 |
| **Total** | | | **0.386** | **0.42 USD/día** | **9.27** | **281.9** |

**Encendida 24/7, la plataforma agota los 100 USD en unos 11 días.** Por eso se trabaja por sesiones.

### Ejecución por sesiones (estimación para completar HU-01)

Cada sesión empieza con la autorización de las operaciones facturables que contiene y termina con
`bash infra/teardown.sh --stop --apply`. El costo por hora con las seis instancias encendidas es de
0.369 USD (EC2 e IPv4), más el EBS, que se cobra mientras los volúmenes existen. **S4, S5 y S6
necesitan 12 vCPU a la vez**: la cuota actual es de 5 (solo caben 2 instancias encendidas), por
lo que dependen del aumento solicitado con `bootstrap-quota.sh`.

| Sesión | Contenido | Operaciones facturables que se autorizan | Duración | Costo | Acumulado* |
|---|---|---|---|---|---|
| Preparación | Acceso temporal, Access Analyzer, simulador IAM, `--prices`, planes | Ninguna | — | 0 | 0 |
| S1 | Red, secretos y llaves (sin cargo) y Jenkins: crear, configurar, 2.ª ejecución y `verify-infra.sh --health --roles=jenkins` | `run-instances` jenkins | 1.5 h | 0.13 | 0.13 |
| S2 | SonarQube: crear, configurar, 2.ª ejecución y `verify-infra.sh --health --roles=sonarqube` | `run-instances` sonarqube | 1.5 h | 0.15 | 0.29 |
| S3 | Nexus, **solo si el equipo autoriza el EULA** | `run-instances` nexus | 1.5 h | 0.15 | 0.44 |
| S4 | dev, stage y prod: crear y configurar; `verify-infra.sh` completo con las 6 encendidas (requiere 12 vCPU) | `start-instances` ×3 y `run-instances` ×3 | 2 h | 0.74 | 1.17 |
| S5 | Idempotencia: `bootstrap-all` ×2, *snapshot* y `diff` | `start-instances` ×6 | 1.5 h | 0.55 | 1.73 |
| S6 | Reconstrucción desde cero (destrucción en CloudShell con su propia autorización) | `terminate-instances` ×6 y `run-instances` ×6 | 3 h | 1.11 | 2.83 |
| — | Contingencia para depuración y reintentos | Según la sesión | 6 h | 2.21 | 5.05 |
| — | EBS mientras existen los volúmenes (cota de 10 días con los 160 GiB) | — | 10 días | 4.21 | 9.25 |
| **Total HU-01** | | | | **≈ 9.3 USD**, unos **13.9 USD con un 50 % de margen** (límite: 15 USD) | |

\* El acumulado no incluye el EBS de los días entre sesiones: cada volumen se cobra desde que se
crea hasta que se destruye (Jenkins 0.079, SonarQube 0.079, Nexus 0.105 y cada ambiente 0.053
USD/día). El EBS es el costo dominante: con las horas estimadas, los 15 USD alcanzan para unos 17
días de volúmenes con margen (23 sin él). Sin la aprobación del EULA no se crea Nexus y C1 queda
incompleto.

**Otros costos:**
- **Transferencia:** la entrada (imágenes, paquetes, plugins) no se cobra. La salida a Internet es
  inferior a 1 GB, dentro de los 100 GB gratis al mes. El tráfico entre instancias usa IP privadas
  en una misma zona, que no se cobra.
- **Servicios auxiliares:** SSM estándar, KMS `aws/ssm` dentro de la capa gratuita, STS, Access
  Analyzer, Pricing API y la monitorización básica de CloudWatch no tienen cargo. No se usan
  *snapshots*, NAT, Elastic IP ni balanceadores.

**Barreras de costo:**
- **AWS Budgets** (requiere aprobación): alertas en 5, 10 y 15 USD. Según la API del plan
  gratuito, crear un presupuesto de costos es una actividad que suma 20 USD de créditos (igual que
  lanzar la primera instancia EC2).
- Al cerrar cada sesión, ejecute `teardown.sh --stop --apply` y confirme que no queda nada encendido:
  ```bash
  aws ec2 describe-instances --region us-east-2 \
    --filters Name=tag:Project,Values=circleguard Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].InstanceId'
  ```
- Si el consumo supera **25 USD** antes de terminar HU-01, se detiene todo y se revisa.
- Al finalizar la evaluación, ejecute `teardown.sh --destroy --apply`, como pide el enunciado.
- **Fuera de HU-01:** E1.5 necesitará ambientes más grandes, porque `t3.small` no basta para los
  servicios núcleo, y eso aumentará el costo por hora.
- **[Por verificar] Rendimiento inicial:** las T3 en modo `standard` no reciben créditos de
  lanzamiento, así que el primer arranque de SonarQube o Nexus puede ser lento. Los scripts esperan
  hasta 10 minutos y se pueden reejecutar sin riesgo.

## Idempotencia: cómo demostrarla

```bash
bash infra/bootstrap-all.sh --apply --approve all 2>&1 | tee /tmp/run1.log
bash infra/verify-infra.sh --snapshot > /tmp/snap1.txt
bash infra/bootstrap-all.sh --apply --approve all 2>&1 | tee /tmp/run2.log   # debe terminar con created=0 updated=0
bash infra/verify-infra.sh --snapshot > /tmp/snap2.txt
diff /tmp/snap1.txt /tmp/snap2.txt && echo "estado idéntico"
```
El *snapshot* lista VPC, subredes, rutas, reglas de seguridad, llaves, nombres y versiones de los
parámetros SSM (sin valores), instancias, hashes de los archivos desplegados y los contenedores
con su ID y su fecha de creación.

## Verificación

```bash
bash infra/verify-infra.sh                  # --health --isolation --credentials
bash infra/verify-infra.sh --isolation      # dev, stage y prod no se alcanzan entre sí; flujos permitidos sí
```
Solo lectura. Termina con código 1 si alguna comprobación falla.

## Detener o destruir

```bash
bash infra/teardown.sh --destroy                  # --plan por defecto: inventario y lo que eliminaría, sin cambios
bash infra/teardown.sh --stop --apply             # detiene las instancias (conserva datos); rol de lectura
```
**La destrucción no se ejecuta en la estación de trabajo**: el rol `circleguard-hu01-teardown`
solo lo asume el usuario `circleguard-hu01-teardown`, con MFA, desde **AWS CloudShell**. Sus
credenciales nunca existen en esta máquina.

1. `bash infra/aws-session.sh cloudshell-bundle`: paquete con `teardown.sh`, sus librerías y la
   configuración no secreta (sin secretos ni `operator.local.env`).
2. En la consola de AWS, inicie sesión como `circleguard-hu01-teardown` (contraseña y MFA en la
   página de AWS), abra CloudShell en `us-east-2` y cargue el paquete (Acciones → Cargar archivo).
3. En CloudShell:
   ```bash
   tar -xzf circleguard-teardown.tgz
   bash infra/teardown-cloudshell.sh                          # pide el código MFA; inventario y plan
   bash infra/teardown-cloudshell.sh --apply                  # destruye: exige escribir 'DESTRUIR circleguard'
   bash infra/teardown-cloudshell.sh --purge-secrets --apply  # además borra /circleguard/* de SSM
   ```
- Solo actúa sobre recursos con las etiquetas `Project=circleguard` y `ManagedBy=infra-bootstrap`.
- La sesión del rol dura 15 minutos y sus credenciales en caché se borran al salir del script.
- La llave privada local y su copia en SSM se conservan, salvo que se use `--purge-secrets`.

## Validación local gratuita (`--target local`)

Valida en Docker Desktop, sin AWS, los mismos stacks y scripts de configuración que se usarán en
EC2. Publica solo en `127.0.0.1`, con secretos en `~/.circleguard/secrets` (fuera del repositorio
y de OneDrive). Docker Desktop tiene unos 7.4 GiB: **valide una herramienta a la vez**.

```bash
bash infra/bootstrap-secrets.sh --target local --apply
bash infra/bootstrap-jenkins.sh --target local --apply      # http://localhost:8080
bash infra/bootstrap-sonarqube.sh --target local --apply    # http://localhost:9000
bash infra/bootstrap-nexus.sh --target local --apply        # http://localhost:8081 (registro en localhost:5000)
bash infra/verify-infra.sh --target local
bash infra/teardown.sh --target local --stop --apply        # nunca borra volúmenes
```
Para iniciar sesión en local, el usuario es `admin` y la contraseña está en
`~/.circleguard/secrets/tools/<herramienta>/`. Léala solo en su propia terminal.

| Herramienta | Descarga aprox. | RAM recomendada | Disco inicial |
|---|---|---|---|
| Jenkins `2.580.2-lts-jdk21` | 244 MB | ≥ 1 GiB (4 GiB o más con *builds*) | 1-10 GiB |
| SonarQube `26.10.0.133078-community` + `postgres:16.15` | 1.09 GB + 160 MB | ≥ 2 GiB para SonarQube + 1 GiB para el sistema | 1-2 GiB |
| Nexus `3.96.5` | 484 MB | *heap* de 2.7 GiB + memoria directa de 2.7 GiB por defecto | crece con los artefactos |

## Entorno local de desarrollo

Los archivos de credenciales locales viven **fuera del repositorio y de OneDrive**:

| Archivo | Uso | Plantilla |
|---|---|---|
| `C:\Users\<usuario>\.circleguard\dev.env` | Middleware de `docker-compose.dev.yml` | [`.env.example`](../.env.example) (secciones de PostgreSQL, Neo4j y LDAP) |
| `C:\Users\<usuario>\.circleguard\dev-app.env` | Secretos de aplicación `CG_*` de los microservicios | [`.env.example`](../.env.example) (sección de secretos de aplicación) |

```bash
# Git Bash ($HOME = C:\Users\<usuario>). En WSL use /mnt/c/Users/<usuario>/.circleguard/...
docker compose -f docker-compose.dev.yml --env-file "$HOME/.circleguard/dev.env" up -d    # iniciar
docker compose -f docker-compose.dev.yml --env-file "$HOME/.circleguard/dev.env" stop     # detener
set -a; . "$HOME/.circleguard/dev.env"; . "$HOME/.circleguard/dev-app.env"; set +a         # antes de bootRun
```
- **Nunca** ejecute `docker compose ... down -v`, `docker volume prune` ni `docker system prune`:
  borran los volúmenes `pgdata` y `neo4jdata`.
- `down` sin `-v` conserva esos volúmenes. Kafka, Redis y LDAP no tienen volumen: sus datos se
  pierden al eliminar los contenedores.
- Un volumen inicializado con credenciales anteriores **conserva esas credenciales**: Postgres y
  Neo4j solo leen las variables al crear la base. En ese caso, la contraseña debe cambiarse dentro
  de la base, con una decisión explícita.

## Puertos y volúmenes

| Servidor | Puerto | Acceso permitido |
|---|---|---|
| todos | 22/tcp | Solo `ADMIN_CIDRS` (llave SSH, sin contraseña). Además, Jenkins puede llegar a dev, stage y prod |
| jenkins | 8080/tcp | Escucha **solo en 127.0.0.1** del host: se accede con `tunnel.sh jenkins` |
| sonarqube | 9000/tcp | Jenkins por la red privada. Administración con `tunnel.sh sonarqube` |
| nexus | 8081/tcp (UI/API) | Jenkins por la red privada. Administración con `tunnel.sh nexus` |
| nexus | 8082/tcp (registro Docker) | Jenkins, dev, stage y prod por la red privada |
| salida de todos | 80, 443/tcp | Paquetes, imágenes y plugins |

**Ninguna interfaz HTTP está abierta a Internet**, ni siquiera para la IP del operador. El tráfico
administrativo viaja cifrado dentro del túnel SSH, así que no hace falta TLS para la administración
en la Parte 1. TLS para los servicios expuestos corresponde a E2.6.

Volúmenes Docker: `circleguard-jenkins_jenkins_home`, `circleguard-sonarqube_{sonarqube_data,sonarqube_extensions,sonarqube_logs,sonar_db_data}`
y `circleguard-nexus_nexus-data`. En EC2 viven en el EBS cifrado de cada instancia.

## Solución de problemas

| Síntoma | Causa y solución |
|---|---|
| `No hay una sesión AWS válida para el perfil ...` | Inicie la sesión que indica el mensaje: `bash infra/aws-session.sh login operator` (o `teardown`) |
| `La identidad ... no corresponde a la capacidad ...` | La operación necesita otro rol (por ejemplo, operación fuera de la ventana de 1 h): vuelva a iniciar sesión |
| `La estimación supera el presupuesto de HU-01` | Estimación local: revise el costo real en Billing y consulte al equipo antes de continuar |
| `Sin acceso SSH` | Su IP pública cambió: vuelva a ejecutar `bootstrap-network.sh --apply` (actualiza `ADMIN_CIDRS`) o defínala |
| La UI no responde en `http://<ip-publica>:8080` | Es intencional: las UIs no se exponen a Internet. Use `bash infra/tunnel.sh jenkins` y abra `http://localhost:8080` |
| `No hay una instancia '<rol>' en ejecución` | Créela o iníciela con `bootstrap-servers.sh --apply --approve <rol>` |
| `Nexus Community Edition exige aceptar su EULA` | Decisión del equipo: revise el EULA y defina `NEXUS_ACCEPT_EULA=true` |
| El puerto 5432 está ocupado en Windows | Un PostgreSQL nativo usa ese puerto: el middleware local no puede publicar 5432 mientras siga activo. Deténgalo (es su decisión) o use otra máquina. Los scripts nunca lo tocan |
| El puerto 8082 está ocupado en Windows | En local, Nexus publica su registro en 5000 (`LOCAL_NEXUS_DOCKER_HOST_PORT`) |
| `error getting credentials` al descargar imágenes desde WSL | Es el asistente de credenciales de Docker Desktop: descargue la imagen desde PowerShell o Git Bash (`docker pull <imagen>`) y repita |
| Aviso `the attribute version is obsolete` | Es un aviso inocuo de Compose v2 sobre `docker-compose.dev.yml` |
| Los scripts fallan con `$'\r'` | Saltos de línea CRLF: `.gitattributes` fuerza LF. Vuelva a obtener los archivos (`git checkout -- infra`) |

## Advertencias de seguridad

- Las credenciales del commit inicial `6f254ed` (ya publicado) se consideran **comprometidas**.
  Ningún ambiente las reutiliza y el historial no se reescribe (decisión del equipo).
- Jenkins, SonarQube y Nexus hablan **HTTP**. Por eso sus puertos no se abren a Internet: la
  administración pasa por el túnel SSH (`tunnel.sh`). No añada reglas que abran 8080, 9000 u 8081:
  `bootstrap-network.sh` las revocaría en la siguiente ejecución. Exponer Jenkins a los *webhooks*
  de GitHub (E1.4) exigirá TLS o un relé, y queda fuera de HU-01.
- Los `.env` de los hosts (`0600 root`) y las variables de los contenedores son visibles para
  root en el host (`docker inspect`). Es un riesgo aceptado para la Parte 1.
- **Riesgo residual:** las migraciones Flyway `V2`/`V3` de auth-service crean usuarios de prueba
  con una contraseña conocida y la revelan en un comentario. No se modifican (decisión X-2); queda
  para E2.6.
- `scan-secrets.sh` debe terminar en `PASS` antes de cada commit.

## Dependencias con otros entregables (no implementadas en HU-01)

- **E1.3:** imágenes de los microservicios y *compose* por ambiente que consumirá
  `/opt/circleguard/<env>/.env`; usuarios de *push*/*pull* del registro.
- **E1.4:** Jenkinsfile, plugins de *pipeline*, *webhook* de GitHub, conexión con SonarQube
  (*quality gate*) y acceso de Jenkins a Docker.
- **E1.5:** llaves de Jenkins hacia los ambientes, despliegue, promoción y *rollback*.
- **Gradle:** `gradle/wrapper/gradle-wrapper.jar` no está versionado (lo excluye `*.jar`), así que
  `./gradlew` no funciona en un clon limpio. Se recomienda resolverlo en E1.4.
